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

/** The worker's scope: instagram / youtube / twitter. Everything else stays
 *  untouched for the Mac pipeline (websites etc. have richer local handling).
 *  Shared by fetchCandidates and processSwipe so the candidate list never
 *  contains swipes the pipeline would refuse — an out-of-scope pending swipe
 *  used to surface as a phantom "candidate" on every 15s tick, forever.
 *  The Mac mirrors this check (SwipeProcessingService.isCloudWorkerScoped)
 *  to decide which swipes to leave to this worker.
 *  A matching contentSource alone qualifies — candidates are scoped from
 *  metadata only, and some swipes carry their URL in structured.sourceUrl. */
export function inWorkerScope(url: string, source: string): boolean {
  const s = source.toLowerCase();
  return s.includes('instagram') || /instagram\.com/i.test(url)
    || s.includes('youtube') || /youtube\.com|youtu\.be/i.test(url)
    || s === 'twitter' || /twitter\.com|(^|\/|\.)x\.com/i.test(url);
}
