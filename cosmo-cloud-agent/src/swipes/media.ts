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

const MAX_VIDEO_BYTES = 120 << 20; // sanity ceiling — reels are ~5–15 MB

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

export async function downloadBinary(
  url: string,
  kind: 'video' | 'image',
  timeoutMs = 120_000
): Promise<Buffer> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, {
      signal: controller.signal,
      headers: { 'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)' },
    });
    if (!response.ok) throw new Error(`download ${response.status} for ${kind}`);
    const buffer = Buffer.from(await response.arrayBuffer());
    if (buffer.length < 1_000) throw new Error(`${kind} download too small (${buffer.length}B)`);
    if (buffer.length > MAX_VIDEO_BYTES) throw new Error(`${kind} download too large (${buffer.length}B)`);

    // Magic-byte sanity: a JPEG served where a video was promised must not be
    // mirrored as an .mp4 (the cobalt poster-JPEG lesson, enforced here too).
    const isJPEG = buffer[0] === 0xff && buffer[1] === 0xd8;
    const isPNG = buffer[0] === 0x89 && buffer[1] === 0x50;
    const isWEBP = buffer.subarray(8, 12).toString('ascii') === 'WEBP';
    const isMP4 = buffer.subarray(4, 8).toString('ascii') === 'ftyp';
    if (kind === 'video' && !isMP4) throw new Error('video download is not an MP4');
    if (kind === 'image' && !(isJPEG || isPNG || isWEBP)) throw new Error('image download is not an image');
    return buffer;
  } finally {
    clearTimeout(timer);
  }
}

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

/** Mirrors every slide; returns the ordered URL array only if ALL succeed. */
export async function mirrorCarousel(
  atomUUID: string,
  slideUrls: string[]
): Promise<string[] | null> {
  const uploaded: string[] = [];
  for (let index = 0; index < slideUrls.length; index += 1) {
    try {
      const data = await downloadBinary(slideUrls[index], 'image', 30_000);
      uploaded.push(await uploadObject(
        'atom-images',
        `${userId.toLowerCase()}/swipe-carousel/${atomUUID}-${index}.jpg`,
        data,
        'image/jpeg'
      ));
    } catch (error) {
      console.warn(`⚠️ carousel slide ${index} mirror failed for ${atomUUID}:`, error instanceof Error ? error.message : error);
      return null; // partial arrays must never be written (client contract)
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
