// cosmo-cloud-agent/src/swipes/media.ts
// Permanent media mirroring to Supabase Storage. The service-role key
// bypasses storage RLS (the Mac's user-scoped uploads have been 403-ing
// on atom-images since day one — this path does not).
//
// STORAGE CONTRACT (must match the Mac mirrors in SwipeProcessingService):
//   video     → swipe-videos/<userId lowercased>/<atomUUID>.mp4  → metadata.videoStorageURL
//   thumbnail → atom-images/<userId lowercased>/swipe-thumbs/<atomUUID>.jpg → metadata.thumbnailStorageURL
//   carousel  → atom-images/<userId lowercased>/swipe-carousel/<atomUUID>-<index>.jpg
//               → metadata.carouselImageStorageURLs (ordered, ALL-OR-NOTHING)
// URL shape both clients fetch with their own auth headers:
//   <supabaseUrl>/storage/v1/object/<bucket>/<path>

import { supabase, userId } from '../db/client';
import { config } from '../config';
import { instagramShortcode } from './instagram';
import { describeFetchError, hostOf, sleep } from './http';

const MAX_VIDEO_BYTES = 120 << 20; // sanity ceiling — reels are ~5–15 MB

/** Mutable so tests can zero the delay. */
export const downloadTuning = { retryDelayMs: 1_500 };

export function storageObjectURL(bucket: string, path: string): string {
  return `${config.supabaseUrl}/storage/v1/object/${bucket}/${path}`;
}

/**
 * The Mac's video mirror silently failed forever because the `swipe-videos`
 * bucket was never created in the dashboard. The service role can create
 * buckets — make both required buckets exist at worker startup so uploads
 * can never fail for that reason again.
 */
export async function ensureBuckets(): Promise<void> {
  for (const bucket of ['atom-images', 'swipe-videos']) {
    try {
      const { data } = await supabase.storage.getBucket(bucket);
      if (data) continue;
      const { error } = await supabase.storage.createBucket(bucket, { public: false });
      if (error && !/already exists/i.test(error.message)) {
        console.warn(`⚠️ createBucket(${bucket}) failed:`, error.message);
      } else if (!error) {
        console.log(`🪣 created storage bucket "${bucket}"`);
      }
    } catch (error) {
      console.warn(`⚠️ ensureBuckets(${bucket}):`, error instanceof Error ? error.message : error);
    }
  }
}

// ── Instagram CDN host canonicalization ─────────────────────────────────────

/** Instagram's general-purpose CDN front door; every signed path resolves here. */
export const INSTAGRAM_CANONICAL_CDN_HOST = 'scontent.cdninstagram.com';

/**
 * Apify hands back media URLs on whichever edge served ITS scraper — often an
 * ISP-embedded cache node (`instagram.frtm1-1.fna.fbcdn.net`: FNA = Facebook
 * Network Appliance, a box racked inside one ISP's network). Those nodes are
 * not reliably reachable from anywhere else: Railway's fetch died with a bare
 * "fetch failed" on slide 0 of one carousel after another (Sept 2026), and the
 * phones showed the same URLs as slow or blank images. The signature in the
 * query string (`oh=`/`oe=`) is host-independent, so the same path served
 * from the canonical front door works — verified against a live URL.
 * Returns null for anything that is not an FNA host.
 */
export function canonicalInstagramCDNURL(url: string): string | null {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return null;
  }
  if (!/\.fna\.fbcdn\.net$/i.test(parsed.hostname)) return null;
  parsed.hostname = INSTAGRAM_CANONICAL_CDN_HOST;
  return parsed.toString();
}

/** Ordered URLs to try for one download: canonical front door first for FNA hosts. */
export function downloadCandidates(url: string): string[] {
  const canonical = canonicalInstagramCDNURL(url);
  return canonical && canonical !== url ? [canonical, url] : [url];
}

// ── Downloads ───────────────────────────────────────────────────────────────

class DownloadError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
    this.name = 'DownloadError';
  }
}

export function sniffImageMime(buffer: Buffer): 'image/jpeg' | 'image/png' | 'image/webp' | null {
  if (buffer[0] === 0xff && buffer[1] === 0xd8) return 'image/jpeg';
  if (buffer[0] === 0x89 && buffer[1] === 0x50) return 'image/png';
  if (buffer.subarray(8, 12).toString('ascii') === 'WEBP') return 'image/webp';
  return null;
}

async function fetchBinaryOnce(url: string, kind: 'video' | 'image', timeoutMs: number): Promise<Buffer> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, {
      signal: controller.signal,
      headers: { 'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)' },
    });
    if (!response.ok) throw new DownloadError(`download ${response.status} for ${kind}`, response.status);
    const buffer = Buffer.from(await response.arrayBuffer());
    if (buffer.length < 1_000) throw new DownloadError(`${kind} download too small (${buffer.length}B)`, 0);
    if (buffer.length > MAX_VIDEO_BYTES) throw new DownloadError(`${kind} download too large (${buffer.length}B)`, 0);

    // Magic-byte sanity: a JPEG served where a video was promised must not be
    // mirrored as an .mp4 (the cobalt poster-JPEG lesson, enforced here too).
    const isMP4 = buffer.subarray(4, 8).toString('ascii') === 'ftyp';
    if (kind === 'video' && !isMP4) throw new DownloadError('video download is not an MP4', 0);
    if (kind === 'image' && !sniffImageMime(buffer)) throw new DownloadError('image download is not an image', 0);
    return buffer;
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Download with the resilience the CDN actually needs: the canonical host is
 * tried before an ISP cache node, transport failures and 5xx/429 get one
 * retry per host, and a dead URL (403/404) moves straight on to the next
 * candidate. The thrown error is the LAST failure; every attempt is logged
 * with the real transport cause.
 */
export async function downloadBinary(
  url: string,
  kind: 'video' | 'image',
  timeoutMs = 120_000
): Promise<Buffer> {
  let lastError: unknown = new Error('no download candidates');
  for (const candidate of downloadCandidates(url)) {
    for (let attempt = 0; attempt < 2; attempt += 1) {
      try {
        return await fetchBinaryOnce(candidate, kind, timeoutMs);
      } catch (error) {
        lastError = error;
        const status = error instanceof DownloadError ? error.status : 0;
        const retryable = status === 0 ? !(error instanceof DownloadError) : (status === 429 || status >= 500);
        console.warn(
          `⚠️ ${kind} download failed (${hostOf(candidate)}${attempt ? ', retry' : ''}): ${describeFetchError(error)}`
        );
        // A DownloadError with status 0 is a content problem (too small, wrong
        // type) — the same bytes will come back, so try the next host instead.
        if (!retryable) break;
        if (attempt === 0) await sleep(downloadTuning.retryDelayMs);
      }
    }
  }
  throw lastError;
}

/**
 * Every slide of a carousel, 3-concurrent, null where a slide could not be
 * fetched. ONE download serves both the storage mirror and the OCR pass.
 */
export async function downloadCarouselSlides(slideUrls: string[], timeoutMs = 30_000): Promise<(Buffer | null)[]> {
  const buffers: (Buffer | null)[] = new Array(slideUrls.length).fill(null);
  let cursor = 0;
  const workers = Array.from({ length: Math.min(3, slideUrls.length) }, async () => {
    while (cursor < slideUrls.length) {
      const index = cursor;
      cursor += 1;
      try {
        buffers[index] = await downloadBinary(slideUrls[index], 'image', timeoutMs);
      } catch {
        buffers[index] = null; // already logged per attempt
      }
    }
  });
  await Promise.all(workers);
  return buffers;
}

// ── Uploads ─────────────────────────────────────────────────────────────────

async function uploadObject(
  bucket: string,
  path: string,
  data: Buffer,
  contentType: string
): Promise<string> {
  const { error } = await supabase.storage.from(bucket).upload(path, data, {
    contentType,
    upsert: true,
  });
  if (error) throw new Error(`storage upload ${bucket}/${path}: ${error.message}`);
  return storageObjectURL(bucket, path);
}

export async function mirrorVideoBuffer(atomUUID: string, data: Buffer): Promise<string> {
  return uploadObject('swipe-videos', `${userId.toLowerCase()}/${atomUUID}.mp4`, data, 'video/mp4');
}

export async function mirrorThumbnail(atomUUID: string, imageUrl: string): Promise<string> {
  const data = await downloadBinary(imageUrl, 'image', 30_000);
  return uploadObject('atom-images', `${userId.toLowerCase()}/swipe-thumbs/${atomUUID}.jpg`, data, 'image/jpeg');
}

/**
 * Discovery-post thumbnail mirror. Scraped CDN URLs (Instagram especially)
 * expire within weeks; scrape time is the one moment they are guaranteed
 * alive, so we pin a durable copy then.
 */
export async function mirrorDiscoveryThumbnail(
  platform: string,
  platformPostId: string,
  imageUrl: string
): Promise<string> {
  const safeId = platformPostId.replace(/[^A-Za-z0-9_-]/g, '-');
  const data = await downloadBinary(imageUrl, 'image', 15_000);
  return uploadObject(
    'atom-images',
    `${userId.toLowerCase()}/discover-thumbs/${platform}-${safeId}.jpg`,
    data,
    'image/jpeg'
  );
}

/**
 * Mirrors already-downloaded slides; returns the ordered URL array only if
 * EVERY slide is present (partial arrays must never be written — the clients
 * index into this array by page).
 */
export async function mirrorCarouselBuffers(
  atomUUID: string,
  slides: (Buffer | null)[]
): Promise<string[] | null> {
  const missing = slides.findIndex(slide => !slide);
  if (slides.length === 0 || missing >= 0) {
    if (slides.length > 0) console.warn(`⚠️ carousel mirror skipped for ${atomUUID}: slide ${missing} was not downloaded`);
    return null;
  }
  const uploaded: string[] = [];
  for (let index = 0; index < slides.length; index += 1) {
    try {
      uploaded.push(await uploadObject(
        'atom-images',
        `${userId.toLowerCase()}/swipe-carousel/${atomUUID}-${index}.jpg`,
        slides[index] as Buffer,
        'image/jpeg'
      ));
    } catch (error) {
      console.warn(`⚠️ carousel slide ${index} upload failed for ${atomUUID}:`, error instanceof Error ? error.message : error);
      return null;
    }
  }
  return uploaded;
}

/**
 * Instant thumbnail: instagram.com/<p|reel>/<code>/media/?size=l 302-redirects
 * to the post's CDN JPEG with no auth (<1s). Used as the quick stage the
 * moment a swipe is claimed, long before Apify returns.
 */
export async function resolveInstantThumbnailURL(postUrl: string): Promise<string | null> {
  const shortcode = instagramShortcode(postUrl);
  if (!shortcode) return null;

  for (const kind of ['p', 'reel']) {
    try {
      const response = await fetch(
        `https://www.instagram.com/${kind}/${shortcode}/media/?size=l`,
        { method: 'GET', redirect: 'manual', signal: AbortSignal.timeout(4_000) }
      );
      const location = response.headers.get('location');
      if (location && /^https?:\/\//.test(location) && !location.includes('/accounts/login')) {
        return location;
      }
    } catch {
      // try the next path variant
    }
  }
  return null;
}
