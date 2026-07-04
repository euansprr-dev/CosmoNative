// cosmo-cloud-agent/src/swipes/instagram.ts
// Apify-backed Instagram extraction for single swipe URLs.
// One apify~instagram-scraper run per post returns everything at once:
// playable videoUrl, carousel childPosts, caption, owner, timestamp AND
// engagement counts — this is the primary extraction path for V2
// (the Mac's cobalt/embed/GraphQL chain is the fallback tier).

import { config } from '../config';
import { ExtractedMedia, ExtractedSlide, SwipeContentType, SwipeExtractionError } from './types';

const SCRAPER_ACTOR_ID = 'apify~instagram-scraper';

interface ApifyRunResponse {
  data?: {
    id?: string;
    defaultDatasetId?: string;
    status?: string;
    statusMessage?: string;
  };
}

// ── Budget guard ────────────────────────────────────────────────────────────
// In-memory monthly counter. Restarts reset it, which only ever UNDER-counts
// toward the cap — acceptable for a guard whose job is stopping runaway loops.

let budgetMonth = '';
let budgetRuns = 0;

export function apifyRunsThisMonth(): number {
  rolloverBudgetMonth();
  return budgetRuns;
}

function rolloverBudgetMonth(): void {
  const month = new Date().toISOString().slice(0, 7);
  if (month !== budgetMonth) {
    budgetMonth = month;
    budgetRuns = 0;
  }
}

export function apifyBudgetAvailable(): boolean {
  rolloverBudgetMonth();
  return budgetRuns < config.apifyMonthlyRunCap;
}

function recordApifyRun(): void {
  rolloverBudgetMonth();
  budgetRuns += 1;
}

// ── Extraction ──────────────────────────────────────────────────────────────

export function instagramShortcode(url: string): string | null {
  const match = url.match(/instagram\.com\/(?:p|reel|reels|tv)\/([A-Za-z0-9_-]+)/i);
  return match ? match[1] : null;
}

export async function extractInstagramPost(url: string): Promise<ExtractedMedia> {
  if (!config.apifyApiKey) {
    throw new SwipeExtractionError('APIFY_API_KEY not configured', true);
  }
  if (!apifyBudgetAvailable()) {
    throw new SwipeExtractionError(`Apify monthly run cap (${config.apifyMonthlyRunCap}) reached`);
  }

  recordApifyRun();
  const run = await runActor(SCRAPER_ACTOR_ID, {
    directUrls: [url],
    resultsType: 'posts',
    resultsLimit: 1,
    addParentData: false,
  });
  await waitForRun(run.runId);
  const items = await fetchDatasetItems(run.datasetId);

  const item = items[0];
  if (!item) {
    throw new SwipeExtractionError('Apify returned an empty dataset for this URL');
  }
  if (typeof item.error === 'string' && item.error) {
    // e.g. "restricted_page" / "not_found" — retrying won't help for these.
    const permanent = /not_?found|restricted|private/i.test(item.error);
    throw new SwipeExtractionError(`Apify item error: ${item.error}`, permanent);
  }

  return mapApifyItem(item);
}

/** Map one apify~instagram-scraper dataset item to our internal shape. */
export function mapApifyItem(item: Record<string, unknown>): ExtractedMedia {
  const itemType = stringField(item, ['type']) ?? '';
  const videoUrl = stringField(item, ['videoUrl']);
  const displayUrl = stringField(item, ['displayUrl']);
  const productType = stringField(item, ['productType']) ?? '';

  let contentType: SwipeContentType;
  let slides: ExtractedSlide[] = [];

  if (itemType === 'Sidecar') {
    contentType = 'carousel';
    const children = Array.isArray(item.childPosts) ? item.childPosts as Array<Record<string, unknown>> : [];
    slides = children.map((child, index) => {
      const childVideo = stringField(child, ['videoUrl']);
      const childImage = stringField(child, ['displayUrl']);
      return {
        index,
        mediaUrl: childVideo ?? childImage ?? '',
        thumbnailUrl: childVideo ? childImage : undefined,
        isVideo: Boolean(childVideo),
      };
    }).filter(slide => slide.mediaUrl);
    // Fallback: some responses carry an images array instead of childPosts.
    if (slides.length === 0 && Array.isArray(item.images)) {
      slides = (item.images as unknown[])
        .filter((u): u is string => typeof u === 'string')
        .map((mediaUrl, index) => ({ index, mediaUrl, isVideo: false }));
    }
  } else if (itemType === 'Video' || videoUrl) {
    contentType = productType === 'clips' || productType === 'reels' ? 'reel' : 'videoPost';
  } else {
    contentType = 'image';
  }

  return {
    contentType: contentType!,
    videoUrl: videoUrl ?? undefined,
    thumbnailUrl: displayUrl ?? undefined,
    slides,
    caption: stringField(item, ['caption']),
    authorUsername: stringField(item, ['ownerUsername']),
    authorFullName: stringField(item, ['ownerFullName']),
    publishedAtISO: stringField(item, ['timestamp']),
    shortcode: stringField(item, ['shortCode', 'shortcode']),
    engagement: {
      likesCount: numberField(item, ['likesCount']),
      commentsCount: numberField(item, ['commentsCount']),
      viewsCount: numberField(item, ['videoViewCount', 'videoPlayCount']),
      sharesCount: numberField(item, ['sharesCount']),
    },
  };
}

function stringField(record: Record<string, unknown>, keys: string[]): string | undefined {
  for (const key of keys) {
    const value = record[key];
    if (typeof value === 'string' && value.trim()) return value.trim();
  }
  return undefined;
}

function numberField(record: Record<string, unknown>, keys: string[]): number | undefined {
  for (const key of keys) {
    const value = record[key];
    if (typeof value === 'number' && Number.isFinite(value) && value >= 0) return value;
  }
  return undefined;
}

// ── Apify plumbing (same pattern as discovery/providers/apifyInstagram.ts) ──

async function runActor(
  actorId: string,
  input: Record<string, unknown>
): Promise<{ runId: string; datasetId: string }> {
  const response = await fetch(
    `https://api.apify.com/v2/acts/${actorId}/runs?token=${encodeURIComponent(config.apifyApiKey)}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(input),
    }
  );
  if (!response.ok) {
    const body = await response.text();
    throw new SwipeExtractionError(`Apify ${actorId} ${response.status}: ${body.slice(0, 300)}`);
  }
  const run = await response.json() as ApifyRunResponse;
  const runId = run.data?.id;
  const datasetId = run.data?.defaultDatasetId;
  if (!runId || !datasetId) {
    throw new SwipeExtractionError(`Apify ${actorId} did not return a run/dataset ID`);
  }
  return { runId, datasetId };
}

async function waitForRun(runId: string): Promise<void> {
  const statusUrl = `https://api.apify.com/v2/actor-runs/${encodeURIComponent(runId)}?token=${encodeURIComponent(config.apifyApiKey)}`;
  // Single-post runs normally finish in 10–30s; poll for up to 4 minutes.
  for (let attempt = 0; attempt < 80; attempt += 1) {
    await new Promise(resolve => setTimeout(resolve, 3_000));
    const response = await fetch(statusUrl);
    if (!response.ok) continue;
    const payload = await response.json() as ApifyRunResponse;
    const status = payload.data?.status;
    if (status === 'SUCCEEDED') return;
    if (status === 'FAILED' || status === 'ABORTED' || status === 'TIMED-OUT') {
      throw new SwipeExtractionError(payload.data?.statusMessage ?? `Apify run ${status.toLowerCase()}`);
    }
  }
  throw new SwipeExtractionError('Apify run timed out');
}

async function fetchDatasetItems(datasetId: string): Promise<Array<Record<string, unknown>>> {
  const response = await fetch(
    `https://api.apify.com/v2/datasets/${encodeURIComponent(datasetId)}/items?token=${encodeURIComponent(config.apifyApiKey)}&format=json&clean=true`
  );
  if (!response.ok) {
    const body = await response.text();
    throw new SwipeExtractionError(`Apify dataset ${response.status}: ${body.slice(0, 300)}`);
  }
  return await response.json() as Array<Record<string, unknown>>;
}
