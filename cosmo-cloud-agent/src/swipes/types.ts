// cosmo-cloud-agent/src/swipes/types.ts
// Shared shapes for the cloud swipe-processing worker.
//
// FIELD-NAME CONTRACT: everything this worker writes into atom.structured /
// atom.metadata is decoded by plain JSONDecoder() in BOTH Swift apps
// (SwipeAnalysis.swift is duplicated Mac<->iOS). That means:
//   • Date-typed Swift fields (classifiedAt, publishedAt, extractedAt) are
//     NUMBERS in seconds since 2001-01-01 (Apple reference date), NOT ISO
//     strings. analyzedAt is a String field — ISO is correct there.
//   • UUID-typed fields (TranscriptSlide.id, CarouselItem.id) are UUID strings.
// Breaking either silently corrupts swipeAnalysis on the clients.

export type SwipeContentType = 'reel' | 'videoPost' | 'carousel' | 'image';

export interface ExtractedSlide {
  index: number;
  mediaUrl: string;        // live CDN URL (expires — mirror promptly)
  thumbnailUrl?: string;   // for video slides
  isVideo: boolean;
}

export interface EngagementSnapshot {
  likesCount?: number;
  commentsCount?: number;
  viewsCount?: number;
  sharesCount?: number;
}

export interface ExtractedMedia {
  contentType: SwipeContentType;
  videoUrl?: string;
  thumbnailUrl?: string;
  slides: ExtractedSlide[];
  caption?: string;
  authorUsername?: string;
  authorFullName?: string;
  publishedAtISO?: string;
  shortcode?: string;
  engagement: EngagementSnapshot;
}

export interface TranscriptSlideJSON {
  id: string;              // UUID string (Swift TranscriptSlide.id)
  text: string;
  slideNumber: number;     // 1-based
  timestamp?: number;
  endTimestamp?: number;
  source?: string;         // TranscriptSlideSource raw value
}

export interface SpeechSegmentJSON {
  start: number;
  end: number;
  text: string;
}

/** Apple reference date epoch offset: 2001-01-01T00:00:00Z in unix seconds. */
export const APPLE_EPOCH_OFFSET = 978_307_200;

export function appleSeconds(date: Date): number {
  return date.getTime() / 1000 - APPLE_EPOCH_OFFSET;
}

export class SwipeExtractionError extends Error {
  constructor(message: string, readonly permanent: boolean = false) {
    super(message);
    this.name = 'SwipeExtractionError';
  }
}

/** Swipe kinds. Mirrors Swift `SwipeKind` (SwipeFile/Artifacts/SwipeKind.swift).
 *  Only 'post' is cloud-processable — every other kind is captured AND
 *  decomposed on the Mac (screenshots, captured web pages, funnels, pasted
 *  copy), and this worker has no extractor for any of them. */
export const CLOUD_PROCESSABLE_SWIPE_KIND = 'post';

/** The worker's scope: instagram / youtube / twitter POST swipes. Everything
 *  else stays untouched for the Mac pipeline (websites etc. have richer local
 *  handling). Shared by fetchCandidates and processSwipe so the candidate list
 *  never contains swipes the pipeline would refuse — an out-of-scope pending
 *  swipe used to surface as a phantom "candidate" on every 15s tick, forever.
 *
 *  SCOPE-TWIN LAW: this function and the Mac's
 *  SwipeProcessingService.isCloudWorkerScoped change TOGETHER. `swipeKind`
 *  comes from atom.metadata.swipeKind, denormalised beside the artifact
 *  envelope in structured.swipeArtifact so this check never has to decode the
 *  structured column. If only one half of the twin learns to refuse a kind,
 *  this worker claims the swipe, fails extraction, and burns its whole retry
 *  ladder on something it can never process. The kind check runs FIRST and is
 *  unconditional: a page swipe of a youtube.com URL is still a page swipe.
 *
 *  A matching contentSource alone qualifies — candidates are scoped from
 *  metadata only, and some swipes carry their URL in structured.sourceUrl. */
export function inWorkerScope(url: string, source: string, swipeKind?: string | null): boolean {
  // Raw-string comparison on purpose. An UNRECOGNISED kind (a row written by a
  // newer client) is Mac-owned too: the Mac is the fallback tier for
  // everything, so "unknown ⇒ Mac" is the only direction that cannot strand a
  // swipe with nobody processing it. The Swift twin is strict here for the
  // same reason, even though its SwipeKind decoder is lenient elsewhere.
  if (swipeKind && swipeKind !== CLOUD_PROCESSABLE_SWIPE_KIND) return false;
  const s = source.toLowerCase();
  return s.includes('instagram') || /instagram\.com/i.test(url)
    || s.includes('youtube') || /youtube\.com|youtu\.be/i.test(url)
    || s === 'twitter' || /twitter\.com|(^|\/|\.)x\.com/i.test(url);
}
