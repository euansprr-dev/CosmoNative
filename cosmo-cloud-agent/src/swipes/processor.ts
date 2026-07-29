// cosmo-cloud-agent/src/swipes/processor.ts
// The cloud swipe worker: claims pending swipes, extracts via Apify,
// mirrors media permanently, transcribes, analyzes, and writes results —
// all while the user's Mac can be closed. The Mac's local pipeline is the
// fallback tier: it skips swipes we claim, and reclaims stale claims.
//
// Status vocabulary (unchanged from the Mac; both apps parse it):
//   pending → extracting → transcribing → analyzing → complete | partial | extraction_failed
//
// INVARIANTS:
//   • every atom update goes through updateAtom (bumps _version, _source:'cloud')
//   • never touch is_deleted; never process a deleted row (deletes are one-way)
//   • structured is spread-merged — sibling keys (autoMetadata, …) must survive
//   • carouselImageStorageURLs is all-or-nothing (client contract)
//   • transcriptEditedByUser is terminal for transcript fields

import cron from 'node-cron';
import { supabase, userId } from '../db/client';
import { config } from '../config';
import { Atom, fetchAtom, updateAtom } from '../db/queries';
import { apifyBudgetAvailable, extractInstagramPost, instagramShortcode } from './instagram';
import { ensureBuckets, mirrorCarousel, mirrorThumbnail, mirrorVideoBuffer, resolveInstantThumbnailURL, downloadBinary } from './media';
import { transcribeSlides, transcribeSpeech, whisperConfigured } from './transcribe';
import { postProcessSlidesJSON, sanitizeSlideText } from './slideText';
import { annotateSlidesWithVoiceover, deduplicateSlidesJSON, extractAudioTrack, transcribeReel } from './reelPipeline';
import { clearProgress, setProgress } from './progress';
import { shouldEscalateToFrames, understandReelVideo } from './reelVideoUnderstanding';
import { randomUUID as newUUID } from 'crypto';
import { fetchTweetText, fetchYouTubeTranscript, youtubeVideoId } from './fetchers';
import {
  AnalyzeContext, buildAnalysisJSON, classify, engagementFields,
  normalizeCreatorHandle, resolveCreator,
} from './analyze';
import { canonicalNicheList, resolveNiche } from './niche';
import {
  appleSeconds, ExtractedMedia, inWorkerScope, SpeechSegmentJSON, SwipeExtractionError, TranscriptSlideJSON,
} from './types';
import { randomUUID } from 'crypto';

const CLAIM_STALE_MINUTES = 15;
const MAX_CLOUD_RETRIES = 2;
const CONCURRENCY = 3;

/// Retries are a CAPTURE-TIME affordance, not a background job. A swipe gets
/// its first pass plus MAX_CLOUD_RETRIES quick re-attempts, all inside
/// RETRY_WINDOW_MINUTES of capture — long enough to ride out a transient
/// Instagram rate-limit while the user is still at the keyboard, short enough
/// that nothing fires once they've walked away.
///
/// This replaced a `30 * attempts`-minute ladder (30/60/90/120/150) which
/// deliberately spread five full pipeline passes across ~8 hours. Every pass
/// re-ran vision from scratch — one saved reel could reach ~120 Gemini calls
/// overnight. Past the window a swipe goes terminal and waits for a human.
const RETRY_DELAYS_SECONDS = [60, 180];
const RETRY_WINDOW_MINUTES = 15;

/// Terminal: fetchCandidates never selects this, so no tick can resurrect it.
/// Only an explicit kick (POST /api/swipes/process) processes it again.
const STATUS_NEEDS_RETRY = 'needs_manual_retry';

/// UUIDs this process is currently working on. The API kick and the cron tick
/// both call processSwipe — without this, a swipe kicked at capture time gets
/// processed twice in parallel (two Apify runs, racing writes).
const inFlightUUIDs = new Set<string>();

const PLACEHOLDER_TITLES = new Set([
  'Instagram Post', 'Instagram Reel', 'Instagram', 'YouTube Video',
  'X Post', 'Threads Post', 'Saved Content', 'Saved Text',
]);

let tickRunning = false;
let workerTask: cron.ScheduledTask | null = null;
let processedToday = 0;
let processedDay = '';

export function startSwipeWorker(): void {
  if (workerTask || !config.swipeWorkerEnabled) return;
  void ensureBuckets();
  // A deploy kills this (single) worker instance mid-swipe; its fresh claims
  // would otherwise block reprocessing for the 15-min stale window. We are
  // the only worker — anything still claimed at boot is ours and orphaned.
  void reclaimOrphanedClaims();
  workerTask = cron.schedule('*/15 * * * * *', () => {
    void tick();
  });
  // Video backfill: the whole pre-worker library has reels with no
  // videoStorageURL (the Mac's mirror never uploaded). Slow drip, one per
  // minute, media-only — transcripts and analysis are never touched.
  cron.schedule('0 * * * * *', () => {
    void backfillTick();
  });
  // Transcript repair: cloud-processed carousels stored raw vision output
  // with visual line-wraps (no post-processing). Pure text transform over
  // stored slides — zero model calls; idempotent (only writes when the
  // normalized text differs), so repeat boots converge to no-ops.
  void normalizeStoredTranscripts();
  console.log('🌀 Swipe worker started (every 15s, concurrency 3; video backfill 1/min)');
}

export function swipeWorkerStats(): { processedToday: number } {
  rolloverDay();
  return { processedToday };
}

function rolloverDay(): void {
  const day = new Date().toISOString().slice(0, 10);
  if (day !== processedDay) {
    processedDay = day;
    processedToday = 0;
  }
}

async function tick(): Promise<void> {
  if (tickRunning) return;
  tickRunning = true;
  try {
    const candidates = await fetchCandidates();
    if (candidates.length === 0) return;

    console.log(`🌀 Swipe worker: ${candidates.length} candidate(s)`);
    // Simple bounded pool.
    const queue = [...candidates];
    await Promise.all(Array.from({ length: Math.min(CONCURRENCY, queue.length) }, async () => {
      while (queue.length > 0) {
        const atom = queue.shift();
        if (atom) await processSwipe(atom.uuid);
      }
    }));
  } catch (error) {
    console.error('❌ Swipe worker tick failed:', error);
  } finally {
    tickRunning = false;
  }
}

async function reclaimOrphanedClaims(): Promise<void> {
  try {
    const { data } = await supabase
      .from('atoms')
      .select('uuid, metadata, created_at')
      .eq('user_id', userId)
      .eq('type', 'research')
      .eq('is_deleted', false)
      .eq('metadata->>isSwipeFile', 'true')
      .eq('metadata->>processingWorker', 'cloud')
      .in('metadata->>processingStatus', ['extracting', 'transcribing', 'analyzing'])
      .limit(25);
    const now = Date.now();
    for (const atom of (data ?? []) as Atom[]) {
      // A claim orphaned INSIDE the capture window goes back to 'pending' and
      // the next tick picks it up. Outside it, resetting to 'pending' would
      // hand it a fresh unbudgeted first pass — every redeploy would silently
      // re-run the full pipeline on old swipes — so it retires instead.
      const reopen = withinCaptureWindow(atom, now);
      await updateAtom(atom.uuid, {
        metadata: {
          processingStatus: reopen ? 'pending' : STATUS_NEEDS_RETRY,
          processingClaimedAt: null,
        },
      });
      console.log(
        reopen
          ? `♻️ released orphaned claim on ${atom.uuid.slice(0, 8)}`
          : `🛑 retired stale claim on ${atom.uuid.slice(0, 8)} — awaiting manual retry`
      );
    }
  } catch (error) {
    console.warn('⚠️ reclaimOrphanedClaims failed:', error instanceof Error ? error.message : error);
  }
}

export async function fetchCandidates(): Promise<Atom[]> {
  const { data, error } = await supabase
    .from('atoms')
    .select('uuid, metadata, updated_at, created_at')
    .eq('user_id', userId)
    .eq('type', 'research')
    .eq('is_deleted', false)
    .eq('metadata->>isSwipeFile', 'true')
    // STATUS_NEEDS_RETRY is deliberately absent — a swipe that exhausted its
    // capture-window budget must never re-enter the tick.
    .in('metadata->>processingStatus', ['pending', 'partial', 'extraction_failed', 'extracting', 'transcribing', 'analyzing'])
    .order('updated_at', { ascending: true })
    .limit(25);

  if (error || !data) {
    if (error) console.error('❌ swipe candidate query failed:', error.message);
    return [];
  }

  const now = Date.now();
  return (data as Atom[]).filter(atom => {
    const meta = atom.metadata ?? {};
    const status = meta.processingStatus as string | undefined;

    // Out-of-scope swipes (websites, tiktok, …) belong to the Mac pipeline —
    // never surface them as candidates.
    if (!inWorkerScope(
      meta.url ?? '',
      (meta.contentSource ?? '') as string,
      (meta.swipeKind ?? null) as string | null,
    )) return false;
    // Already being worked on by this process (API kick in flight).
    if (inFlightUUIDs.has(atom.uuid)) return false;

    // In-flight statuses: only reclaim stale claims (crashed worker / dead Mac
    // run), and only while the capture window is still open. A claim stranded
    // by a deploy an hour ago is not worth a fresh pipeline pass —
    // reclaimOrphanedClaims retires it to STATUS_NEEDS_RETRY at boot instead.
    if (status === 'extracting' || status === 'transcribing' || status === 'analyzing') {
      // NaN-checked, not truthiness — epoch 0 is a VALID (very stale) claim.
      const claimParsed = Date.parse(meta.processingClaimedAt ?? '');
      const claimedAt = Number.isFinite(claimParsed) ? claimParsed : (Date.parse(atom.updated_at) || 0);
      if (now - claimedAt <= CLAIM_STALE_MINUTES * 60_000) return false;
      return withinCaptureWindow(atom, now);
    }
    // Failed AND partial: a couple of quick re-attempts inside the capture
    // window, then terminal. Both the attempt cap and the window must hold —
    // the cap alone let a swipe that failed at 8pm still be burning passes at
    // 3am, which is exactly the overnight spend this replaced.
    if (status === 'extraction_failed' || status === 'partial') {
      const attempts = Number(meta.cloudRetryCount ?? 0);
      if (attempts >= MAX_CLOUD_RETRIES) return false;
      if (!withinCaptureWindow(atom, now)) return false;
      const retryAfter = Date.parse(meta.processingRetryAfter ?? '') || 0;
      return now >= retryAfter;
    }
    // pending: always allow a genuine first pass. If it has been attempted
    // before, it is only still 'pending' because a pass bailed early without
    // reaching a terminal write — respect the window so it can't spin on the
    // 15s tick forever.
    return meta.processingFirstAttemptAt ? withinCaptureWindow(atom, now) : true;
  });
}

/// True while a swipe is still inside its capture-time retry window.
///
/// Anchored to the FIRST processing attempt, not created_at: an iPhone capture
/// can sync down long after it was saved, and the window should measure from
/// when this worker first touched it, not from when the user hit share. Falls
/// back to created_at for rows predating the stamp.
export function withinCaptureWindow(atom: Atom, now: number): boolean {
  const meta = atom.metadata ?? {};
  const firstAttempt = Date.parse(meta.processingFirstAttemptAt ?? '');
  const anchor = Number.isFinite(firstAttempt)
    ? firstAttempt
    : (Date.parse(atom.created_at ?? '') || 0);
  // No anchor at all (unparseable both ways) — treat as never attempted rather
  // than as infinitely old, so a genuine first pass isn't refused.
  if (!anchor) return true;
  return now - anchor <= RETRY_WINDOW_MINUTES * 60_000;
}

export async function processSwipe(uuid: string): Promise<void> {
  // One pass per swipe per process — the capture-time API kick and the cron
  // tick used to double-process the same swipe (two Apify runs, racing writes).
  if (inFlightUUIDs.has(uuid)) {
    console.log(`⏭ swipe ${uuid.slice(0, 8)} already in flight — skipping duplicate`);
    return;
  }
  inFlightUUIDs.add(uuid);
  try {
    await processSwipeInner(uuid);
  } finally {
    inFlightUUIDs.delete(uuid);
  }
}

async function processSwipeInner(uuid: string): Promise<void> {
  const atom = await fetchAtom(uuid);
  if (!atom || atom.is_deleted) return;
  const meta = atom.metadata ?? {};
  if (meta.isSwipeFile !== true && meta.isSwipeFile !== 'true') return;

  const url: string = meta.url ?? atom.structured?.sourceUrl ?? '';
  const source: string = (meta.contentSource ?? '').toLowerCase();

  // The kind gate matters most HERE: POST /api/swipes/process bypasses
  // fetchCandidates entirely, so an over-eager kick from a Mac capture surface
  // is the one path that could hand this worker a page/frame/flow/note swipe.
  if (!url || !inWorkerScope(url, source, (meta.swipeKind ?? null) as string | null)) return;
  const isInstagram = source.includes('instagram') || /instagram\.com/i.test(url);
  const isYouTube = source.includes('youtube') || /youtube\.com|youtu\.be/i.test(url);

  console.log(`🌀 processing swipe ${uuid.slice(0, 8)} (${source || 'url'})`);
  setProgress(uuid, 'extracting', 0.04);
  // Stamp the retry-window anchor on the first pass only — a manual kick days
  // later must not reopen the window and let the tick take over again.
  if (!meta.processingFirstAttemptAt) {
    await updateAtom(uuid, { metadata: { processingFirstAttemptAt: new Date().toISOString() } });
  }
  await setStatus(uuid, 'extracting');

  try {
    if (isInstagram) {
      await processInstagram(uuid, url);
    } else if (isYouTube) {
      await processYouTube(uuid, url);
    } else {
      await processTwitter(uuid, url);
    }
    rolloverDay();
    processedToday += 1;
    setProgress(uuid, 'complete', 1);
    console.log(`✅ swipe ${uuid.slice(0, 8)} complete`);
  } catch (error) {
    clearProgress(uuid);
    const permanent = error instanceof SwipeExtractionError && error.permanent;
    console.error(`❌ swipe ${uuid.slice(0, 8)} failed:`, error instanceof Error ? error.message : error);
    await markFailed(uuid, permanent);
  }
}

// ── Instagram pipeline ──────────────────────────────────────────────────────

/// A usable transcript persisted by an earlier pass, or null.
///
/// persistAndAnalyze writes the transcript into structured.swipeAnalysis
/// BEFORE the insight call, so a swipe that reached 'partial' via a failed
/// classification already has its expensive vision work banked on disk.
/// Requires actual content — an empty-but-present key means the prior pass
/// produced nothing and the work genuinely has to be redone.
export function priorTranscript(atom: Atom): {
  slides: TranscriptSlideJSON[];
  rawSlides: TranscriptSlideJSON[];
  speech: SpeechSegmentJSON[];
  quality: string;
  warnings: string[];
} | null {
  const analysis = atom.structured?.swipeAnalysis ?? {};
  const slides: TranscriptSlideJSON[] = Array.isArray(analysis.transcriptSlides) ? analysis.transcriptSlides : [];
  const speech: SpeechSegmentJSON[] = Array.isArray(analysis.transcriptSpeechSegments)
    ? analysis.transcriptSpeechSegments
    : [];
  const hasContent = slides.some(s => s?.text?.trim()) || speech.some(s => s?.text?.trim());
  if (!hasContent) return null;

  const rawSlides: TranscriptSlideJSON[] = Array.isArray(analysis.rawTranscriptSlides)
    ? analysis.rawTranscriptSlides
    : slides;
  return {
    slides,
    rawSlides,
    speech,
    quality: typeof analysis.transcriptionQuality === 'string' ? analysis.transcriptionQuality : 'accurate',
    warnings: Array.isArray(analysis.transcriptionWarnings) ? analysis.transcriptionWarnings : [],
  };
}

async function processInstagram(uuid: string, url: string): Promise<void> {
  // Quick stage: permanent thumbnail within seconds, before Apify returns.
  await quickThumbnailStage(uuid, url);
  setProgress(uuid, 'extracting', 0.10);

  const media = await extractInstagramPost(url);
  setProgress(uuid, 'extracting', 0.35);
  const atom = await fetchAtom(uuid);
  if (!atom || atom.is_deleted) return;

  // A transcript banked by an earlier pass makes this run analysis-only.
  const prior = priorTranscript(atom);

  // Media mirroring (before transcription — CDN URLs expire). The video is
  // downloaded ONCE and the buffer reused for mirror + Whisper + frames.
  const metadataUpdates: Record<string, unknown> = {};
  let videoData: Buffer | null = null;
  // Only pull the video down if something still needs the bytes: transcription
  // (no banked transcript) or the storage mirror. On an analysis-only retry of
  // an already-mirrored reel that is a pointless multi-MB download.
  const needsVideoBytes = !prior || !atom.metadata?.videoStorageURL;
  if (media.videoUrl && needsVideoBytes) {
    try {
      videoData = await downloadBinary(media.videoUrl, 'video');
    } catch (error) {
      console.warn(`⚠️ video download failed for ${uuid.slice(0, 8)}:`, error instanceof Error ? error.message : error);
    }
  }
  if (videoData) setProgress(uuid, 'extracting', 0.45);
  if (videoData && !atom.metadata?.videoStorageURL) {
    try {
      metadataUpdates.videoStorageURL = await mirrorVideoBuffer(uuid, videoData);
    } catch (error) {
      console.warn(`⚠️ video mirror failed for ${uuid.slice(0, 8)}:`, error instanceof Error ? error.message : error);
    }
  }
  if (media.thumbnailUrl && !atom.metadata?.thumbnailStorageURL) {
    try {
      metadataUpdates.thumbnailStorageURL = await mirrorThumbnail(uuid, media.thumbnailUrl);
      metadataUpdates.thumbnailUrl = media.thumbnailUrl;
    } catch { /* quick stage may already have covered this */ }
  }
  if (media.slides.length > 1) {
    const slideImageUrls = media.slides.map(s => (s.isVideo ? s.thumbnailUrl ?? s.mediaUrl : s.mediaUrl));
    const mirrored = await mirrorCarousel(uuid, slideImageUrls);
    if (mirrored) metadataUpdates.carouselImageStorageURLs = mirrored;
  }
  if (Object.keys(metadataUpdates).length > 0) {
    await updateAtom(uuid, { metadata: metadataUpdates });
  }

  // Transcription.
  setProgress(uuid, 'transcribing', 0.55);
  await setStatus(uuid, 'transcribing');
  const editedByUser = atom.structured?.swipeAnalysis?.transcriptEditedByUser === true;

  let slides: TranscriptSlideJSON[] = [];
  let rawSlides: TranscriptSlideJSON[] = [];
  let speech: SpeechSegmentJSON[] = [];
  const warnings: string[] = [];
  let quality = 'accurate';

  // CHECKPOINT: vision is by far the most expensive step in this pipeline —
  // one Gemini call per carousel slide, or up to 24 per reel (240 frames in
  // batches of 20, each batch retried once). A retry almost always exists
  // because the CHEAP tail failed (a classification call), so re-running
  // vision to get back there re-bought the whole thing. Reuse it instead.
  if (prior) {
    slides = prior.slides;
    rawSlides = prior.rawSlides;
    speech = prior.speech;
    quality = prior.quality;
    warnings.push(...prior.warnings);
    console.log(
      `♻️ swipe ${uuid.slice(0, 8)}: reusing transcript from a previous pass ` +
      `(${slides.length} slide(s), ${speech.length} segment(s)) — skipping vision`
    );
  } else if (!editedByUser) {
    if (media.contentType === 'carousel' && media.slides.length > 0) {
      const slideImageUrls = media.slides.map(s => (s.isVideo ? s.thumbnailUrl ?? s.mediaUrl : s.mediaUrl));
      rawSlides = await transcribeSlides(slideImageUrls);
      // Mac-parity repair pass (postProcessSlides port): merge visual
      // line-wraps into sentences, one idea per line, drop artifacts/dupes.
      // Without this, cloud carousels rendered mid-sentence line breaks.
      slides = postProcessSlidesJSON(rawSlides, { isCarousel: true });
    } else if (media.contentType === 'image' && media.thumbnailUrl) {
      rawSlides = await transcribeSlides([media.thumbnailUrl]);
      slides = postProcessSlidesJSON(rawSlides, { isCarousel: false });
    } else if (videoData) {
      // Reels V3: Whisper (precision timestamps) runs IN PARALLEL with one
      // native-video understanding call — the model sees the frames AND hears
      // the audio, so modality (voiceover vs text cards vs captions vs music)
      // is a single informed judgment. Tier 3 = the V2 frame-batch pipeline.
      // Whisper gets the AUDIO TRACK, not the video — its API caps uploads at
      // 25MB, which a 3-minute reel video exceeds while its audio is ~1.5MB.
      const whisperPromise: Promise<SpeechSegmentJSON[]> = whisperConfigured()
        ? extractAudioTrack(videoData)
            .then(audio => transcribeSpeech(audio, { filename: 'audio.m4a', mimeType: 'audio/mp4' }))
            .catch(async error => {
              console.warn(`⚠️ whisper (audio) failed for ${uuid.slice(0, 8)}:`, error instanceof Error ? error.message : error);
              // ffmpeg-less or codec edge: original video still works when small.
              if (videoData.length < 24 << 20) {
                try { return await transcribeSpeech(videoData); } catch { /* fall through */ }
              }
              return [] as SpeechSegmentJSON[];
            })
        : Promise.resolve([]);

      const [whisperSegments, understanding] = await Promise.all([
        whisperPromise,
        understandReelVideo(videoData, media.caption),
      ]);

      setProgress(uuid, 'transcribing', 0.82);
      if (understanding && understanding.modality !== 'empty' && !shouldEscalateToFrames(understanding)) {
        // Slides straight from the model (authored cards only, captions
        // excluded by instruction) + the V2 dedup pass as cheap insurance.
        slides = deduplicateSlidesJSON(understanding.slides.map((s, index) => ({
          id: newUUID(),
          text: s.text,
          slideNumber: index + 1,
          timestamp: s.startSec,
          endTimestamp: s.endSec,
          source: 'geminiVision',
        })));
        rawSlides = slides;

        // Speech: Whisper wins on precision when present; the model's own
        // transcript covers the no-OpenAI-key case. Music never stored.
        if (understanding.modality === 'textOnly' || understanding.audioIsMusic) {
          speech = [];
        } else if (whisperSegments.length > 0) {
          speech = whisperSegments;
        } else {
          speech = understanding.speechTranscript.map(s => ({ start: s.startSec, end: s.endSec, text: s.text }));
        }

        if (understanding.modality === 'voiceoverOnly' && slides.length > 0) {
          // Model found stray text on a voiceover reel — speech is the content.
          slides = [];
          rawSlides = [];
        }
        if (understanding.modality === 'voiceoverPlusText' && speech.length > 0) {
          slides = annotateSlidesWithVoiceover(slides, speech);
        }
        if (understanding.modality === 'voiceoverOnly' && speech.length === 0) {
          warnings.push('Voiceover detected but no transcript captured.');
          quality = 'degraded';
        }
        console.log(`🎞 reel ${uuid.slice(0, 8)}: V3/${understanding.tier} ${understanding.modality}, ${slides.length} slide(s), ${speech.length} segment(s)`);
      } else {
        // Tier 3: the V2 frame-batch pipeline (4fps + heuristic arbitration).
        speech = whisperSegments;
        if (!whisperConfigured()) warnings.push('Cloud speech transcription unavailable (no OpenAI key).');
        const reel = await transcribeReel(videoData, speech);
        slides = reel.slides;
        rawSlides = reel.rawSlides;
        warnings.push(...reel.warnings);
        if (reel.contentType === 'textOnly') speech = [];
        // V3 parity: voiceover reels render as timestamped seek rows on the
        // clients — segments carry the transcript, not one giant slide.
        if (reel.contentType === 'voiceoverOnly' && speech.length > 0) {
          slides = [];
          rawSlides = [];
        }
        console.log(`🎞 reel ${uuid.slice(0, 8)}: V2-fallback ${reel.contentType}, ${slides.length} slide(s)`);
      }
    } else if (media.videoUrl) {
      warnings.push('Video download failed; transcript unavailable this pass.');
      quality = 'degraded';
    }
  }

  setProgress(uuid, 'analyzing', 0.86);
  await setStatus(uuid, 'analyzing');
  await persistAndAnalyze(uuid, url, media, { slides, rawSlides, speech, warnings, quality, editedByUser });
}

async function quickThumbnailStage(uuid: string, url: string): Promise<void> {
  try {
    const atom = await fetchAtom(uuid);
    if (!atom || atom.metadata?.thumbnailStorageURL) return;
    const cdnURL = await resolveInstantThumbnailURL(url);
    if (!cdnURL) return;
    const storageURL = await mirrorThumbnail(uuid, cdnURL);
    await updateAtom(uuid, { metadata: { thumbnailStorageURL: storageURL, thumbnailUrl: cdnURL } });
    console.log(`⚡ quick thumbnail mirrored for ${uuid.slice(0, 8)}`);
  } catch {
    // best-effort — never fails the pipeline
  }
}

// ── YouTube / Twitter pipelines ─────────────────────────────────────────────

async function processYouTube(uuid: string, url: string): Promise<void> {
  const videoId = youtubeVideoId(url);
  if (!videoId) throw new SwipeExtractionError('unrecognized YouTube URL', true);

  await setStatus(uuid, 'transcribing');
  const segments = await fetchYouTubeTranscript(videoId);
  await setStatus(uuid, 'analyzing');
  await persistAndAnalyze(uuid, url, null, {
    slides: [], rawSlides: [], speech: segments, warnings: [], quality: 'accurate', editedByUser: false,
  });
}

async function processTwitter(uuid: string, url: string): Promise<void> {
  await setStatus(uuid, 'transcribing');
  const text = await fetchTweetText(url);
  if (!text) throw new SwipeExtractionError('tweet text unavailable');
  const slide: TranscriptSlideJSON = { id: randomUUID(), text, slideNumber: 1, source: 'manual' };
  await setStatus(uuid, 'analyzing');
  await persistAndAnalyze(uuid, url, null, {
    slides: [slide], rawSlides: [slide], speech: [], warnings: [], quality: 'accurate', editedByUser: false,
  });
}

// ── Persist + analyze (port of the Mac's persistAndAnalyze contract) ───────

interface TranscriptionResult {
  slides: TranscriptSlideJSON[];      // cleaned — what clients render
  rawSlides: TranscriptSlideJSON[];   // pre-cleanup (Mac's rawTranscriptSlides)
  speech: SpeechSegmentJSON[];
  warnings: string[];
  quality: string;
  editedByUser: boolean;
}

async function persistAndAnalyze(
  uuid: string,
  url: string,
  media: ExtractedMedia | null,
  result: TranscriptionResult
): Promise<void> {
  const atom = await fetchAtom(uuid);
  if (!atom || atom.is_deleted) return;

  const structured: Record<string, any> = { ...(atom.structured ?? {}) };
  const existingAnalysis: Record<string, any> = { ...(structured.swipeAnalysis ?? {}) };
  const richContent: Record<string, any> = { ...(structured.richContent ?? {}) };

  // Transcript text (slides joined, or speech joined).
  const slideText = result.slides.map(s => s.text.trim()).filter(Boolean).join('\n\n');
  const speechText = result.speech.map(s => s.text).join(' ').trim();
  const combined = slideText || speechText;

  let body = atom.body;
  if (!result.editedByUser && combined) {
    body = combined;
    richContent.transcript = combined;
    richContent.transcriptStatus = 'available';
  }

  // Rich content enrichment from Apify (Instagram only).
  if (media) {
    if (media.authorUsername && !richContent.author) richContent.author = media.authorUsername;
    if (media.thumbnailUrl && !richContent.thumbnailUrl) richContent.thumbnailUrl = media.thumbnailUrl;
    const igContentType = media.contentType;
    richContent.sourceType = igContentType === 'carousel' ? 'instagram_carousel'
      : igContentType === 'image' ? 'instagram_post'
      : 'instagram_reel';
    richContent.instagramType = igContentType === 'carousel' ? 'carousel'
      : igContentType === 'image' ? 'post' : 'reel';

    const igData: Record<string, any> = { ...(richContent.instagramData ?? {}) };
    igData.originalURL = igData.originalURL ?? url;
    igData.contentType = igContentType;
    if (media.authorUsername) igData.authorUsername = media.authorUsername;
    if (media.caption) igData.caption = media.caption;
    igData.extractedAt = appleSeconds(new Date());
    if (media.slides.length > 1) {
      igData.expectedCarouselItemCount = media.slides.length;
      igData.carouselItems = media.slides.map(slide => ({
        id: randomUUID(),
        index: slide.index,
        mediaType: slide.isVideo ? 'video' : 'image',
        mediaURL: slide.mediaUrl,
        ...(slide.thumbnailUrl ? { thumbnailURL: slide.thumbnailUrl } : {}),
      }));
    }
    richContent.instagramData = igData;
  }

  // Hook + title from the first non-empty slide. Mac rule: refresh whenever
  // the transcript isn't user-owned (a stale hook must not survive a
  // retranscribe — e.g. a misread year in the old title).
  const metadataUpdates: Record<string, unknown> = {};
  let title = atom.title;
  const firstText = result.slides.find(s => s.text.trim())?.text
    ?? result.speech[0]?.text;
  if (firstText && (!result.editedByUser || !atom.title || PLACEHOLDER_TITLES.has(atom.title))) {
    const hook = firstText.replace(/\n/g, ' ').replace(/\s+/g, ' ').trim();
    metadataUpdates.hook = hook.slice(0, 500);
    title = hook.slice(0, 120);
    richContent.title = hook.slice(0, 120);
  }

  // Transcript fields into swipeAnalysis (respecting the user-edit lock).
  if (!result.editedByUser && (result.slides.length > 0 || result.speech.length > 0)) {
    existingAnalysis.transcriptSlides = result.slides;
    existingAnalysis.rawTranscriptSlides = result.rawSlides.length ? result.rawSlides : result.slides;
    existingAnalysis.transcriptSpeechSegments = result.speech;
    existingAnalysis.transcriptionQuality = result.quality;
    if (result.warnings.length) existingAnalysis.transcriptionWarnings = result.warnings;
  }

  // Engagement (merge-protected fields — only ever set at import/refresh).
  if (media) {
    Object.assign(existingAnalysis, engagementFields(media.engagement, media.publishedAtISO, media.shortcode));
  }

  // Insight LLM call (the Mac's v4 pass, ported 1:1).
  const analysisText = combined || media?.caption || '';
  const hookText = firstText
    ? firstText.replace(/\n/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 500)
    : analysisText.slice(0, 500);
  const analyzableSlideCount = result.slides.filter(s => s.text.trim()).length;
  const ctx: AnalyzeContext = {
    title: title ?? 'Untitled',
    url,
    platform: (atom.metadata?.contentSource as string) ?? '',
    author: richContent.author ?? media?.authorUsername ?? '',
    oembedTitle: richContent.title ?? '',
    sourceType: richContent.sourceType ?? '',
    instagramType: richContent.instagramType ?? '',
    hasVideo: Boolean(media?.videoUrl),
    slideCount: media?.slides.length ?? result.slides.length,
    durationSeconds: 0,
    transcriptSlides: result.slides,
    speechSegments: result.speech,
    transcriptionQuality: result.quality,
    transcriptionWarnings: result.warnings,
    text: analysisText,
    canonicalNiches: await canonicalNicheList(),
    engagement: media?.engagement,
  };

  // One inline retry — a transient LLM failure shouldn't cost a full
  // re-extraction pass (each retry pass burns an Apify run).
  let classification = analysisText.trim() ? await classify(ctx) : null;
  if (!classification && analysisText.trim()) {
    console.warn(`⚠️ insight pass failed for ${uuid.slice(0, 8)} — retrying once`);
    await new Promise(resolve => setTimeout(resolve, 3_000));
    classification = await classify(ctx);
  }
  if (classification) {
    // Canonicalize the niche — the model saw the registry list; the
    // deterministic matcher (exact → alias → fuzzy → create) is the net.
    if (classification.niche) {
      classification.niche = await resolveNiche(classification.niche);
    }
    const { handle, name } = normalizeCreatorHandle(
      classification.creatorHandle, classification.creatorName, ctx.author
    );
    const creatorUUID = await resolveCreator(handle, name, atom, ctx.platform || 'instagram');
    const analysisJSON = buildAnalysisJSON(classification, creatorUUID, {
      hookText,
      slideCount: analyzableSlideCount,
      hasVideo: Boolean(media?.videoUrl),
    });
    // Insight fields override; transcript/engagement keys set above survive.
    Object.assign(existingAnalysis, analysisJSON);

    // Library headline: the sanitized short displayTitle wins over the raw
    // 120-char hook prefix (same rule as the Mac's runInsightPass).
    const displayTitle = analysisJSON.displayTitle as string | undefined;
    if (displayTitle && (!result.editedByUser || !atom.title || PLACEHOLDER_TITLES.has(atom.title))) {
      title = displayTitle;
      richContent.title = displayTitle;
    }
  }

  // Two ways this pass can end incomplete — both are "partial", never a
  // silent "complete" that strands the swipe half-processed forever:
  //   • a video reel with NO transcript at all (Whisper down + all video
  //     tiers failing) — transient pile-up
  //   • a transcript exists but the insight/classification call failed —
  //     without this, the swipe synced down "complete" with an empty
  //     analysis and the Mac had to re-run the pass locally on open
  //
  // "Incomplete" no longer implies "will be retried": retrySchedule decides
  // whether there is capture-window budget left, and retires the swipe to
  // STATUS_NEEDS_RETRY when there isn't. The transcript is written either way
  // (below), so a later manual retry resumes at analysis instead of re-running
  // vision.
  const isVideoReel = Boolean(media?.videoUrl);
  const missingTranscript = !result.editedByUser && !slideText && !speechText && isVideoReel;
  const missingAnalysis = Boolean(analysisText.trim()) && !classification
    && existingAnalysis.isFullyAnalyzed !== true;
  const isPartial = missingTranscript || missingAnalysis;
  metadataUpdates.processingWorker = 'cloud';
  if (isPartial) {
    const attempts = Number(atom.metadata?.cloudRetryCount ?? 0) + 1;
    metadataUpdates.cloudRetryCount = attempts;
    Object.assign(metadataUpdates, retrySchedule(atom, attempts));
  } else {
    metadataUpdates.processingStatus = 'complete';
    metadataUpdates.cloudRetryCount = 0;
    metadataUpdates.processingRetryAfter = null;
  }

  structured.swipeAnalysis = existingAnalysis;
  structured.richContent = richContent;

  await updateAtom(uuid, {
    title: title ?? undefined,
    body: body ?? undefined,
    structured,
    metadata: metadataUpdates,
  });
}

// ── Video backfill (media-only repair for the pre-worker library) ──────────

let backfillRunning = false;
let backfillExhausted = false;

async function backfillTick(): Promise<void> {
  if (backfillRunning || backfillExhausted) return;
  if (!apifyBudgetAvailable()) return;
  backfillRunning = true;
  try {
    // Reel filter lives IN the query — deciding from a 10-row window once
    // declared the library "fully mirrored" while dozens of reels waited.
    const { data } = await supabase
      .from('atoms')
      .select('uuid, metadata')
      .eq('user_id', userId)
      .eq('type', 'research')
      .eq('is_deleted', false)
      .eq('metadata->>isSwipeFile', 'true')
      .eq('metadata->>processingStatus', 'complete')
      .is('metadata->>videoStorageURL', null)
      .is('metadata->>videoBackfillFailed', null)
      .like('metadata->>url', '%instagram.com%reel%')
      .order('updated_at', { ascending: false })
      .limit(5);

    const candidate = ((data ?? []) as Atom[]).find(atom => {
      const url: string = atom.metadata?.url ?? '';
      return /instagram\.com\/(reel|reels|tv)\//i.test(url);
    });
    if (!candidate) {
      backfillExhausted = true; // re-checked on next deploy/restart
      console.log('🎬 video backfill: library fully mirrored');
      return;
    }

    const url: string = candidate.metadata?.url ?? '';
    console.log(`🎬 video backfill: ${candidate.uuid.slice(0, 8)}`);
    try {
      const media = await extractInstagramPost(url);
      if (!media.videoUrl) throw new SwipeExtractionError('no videoUrl for backfill', true);
      const videoData = await downloadBinary(media.videoUrl, 'video');
      const videoStorageURL = await mirrorVideoBuffer(candidate.uuid, videoData);
      const updates: Record<string, unknown> = { videoStorageURL };
      if (!candidate.metadata?.thumbnailStorageURL && media.thumbnailUrl) {
        try {
          updates.thumbnailStorageURL = await mirrorThumbnail(candidate.uuid, media.thumbnailUrl);
        } catch { /* thumbnail is a bonus here */ }
      }
      await updateAtom(candidate.uuid, { metadata: updates });
      console.log(`🎬 video backfill: ${candidate.uuid.slice(0, 8)} mirrored (${Math.round(videoData.length / 1024 / 1024)}MB)`);
    } catch (error) {
      // Mark so we never re-spend Apify runs on a dead/unfetchable post.
      await updateAtom(candidate.uuid, { metadata: { videoBackfillFailed: new Date().toISOString() } });
      console.warn(`⚠️ video backfill failed for ${candidate.uuid.slice(0, 8)}:`, error instanceof Error ? error.message : error);
    }
  } catch (error) {
    console.error('❌ backfill tick failed:', error);
  } finally {
    backfillRunning = false;
  }
}

// ── One-shot transcript normalization (boot) ────────────────────────────────

/// Re-runs the Mac-parity sanitize pass over STORED carousel/image slide
/// texts. Scope guards:
///   • never touches user-edited transcripts (transcriptEditedByUser terminal)
///   • never touches reel slides (any slide carrying a timestamp) — those went
///     through the reel pipeline's own arbitration and carry seek anchors
///   • rawTranscriptSlides stay untouched (raw is raw)
///   • bounded writes per boot; only writes when the text actually changes
export async function normalizeStoredTranscripts(): Promise<number> {
  const MAX_WRITES = 150;
  let repaired = 0;
  try {
    const { data } = await supabase
      .from('atoms')
      .select('uuid, structured')
      .eq('user_id', userId)
      .eq('type', 'research')
      .eq('is_deleted', false)
      .eq('metadata->>isSwipeFile', 'true')
      .not('structured->swipeAnalysis->transcriptSlides', 'is', null)
      .order('updated_at', { ascending: false })
      .limit(1000);

    for (const atom of (data ?? []) as Atom[]) {
      if (repaired >= MAX_WRITES) break;
      const analysis = atom.structured?.swipeAnalysis ?? {};
      if (analysis.transcriptEditedByUser === true) continue;
      const slides: TranscriptSlideJSON[] = Array.isArray(analysis.transcriptSlides)
        ? analysis.transcriptSlides
        : [];
      if (slides.length === 0) continue;
      if (slides.some(s => typeof s?.timestamp === 'number')) continue; // reel slides
      if (!slides.some(s => (s?.text ?? '').trim())) continue;

      const isCarousel = slides.length > 1;
      let changed = false;
      const normalized = slides.map(slide => {
        const original = slide?.text ?? '';
        if (!original.trim()) return slide;
        const cleaned = sanitizeSlideText(original, isCarousel);
        if (cleaned.length === 0 || cleaned === original) return slide;
        changed = true;
        return { ...slide, text: cleaned };
      });
      if (!changed) continue;

      const structured: Record<string, any> = { ...(atom.structured ?? {}) };
      structured.swipeAnalysis = { ...analysis, transcriptSlides: normalized };
      const updated = await updateAtom(atom.uuid, { structured });
      if (updated) {
        repaired += 1;
        console.log(`🧹 transcript normalized: ${atom.uuid.slice(0, 8)}`);
      }
    }
    if (repaired > 0) {
      console.log(`🧹 transcript normalization: repaired ${repaired} swipe(s)`);
    }
  } catch (error) {
    console.warn('⚠️ transcript normalization failed:', error instanceof Error ? error.message : error);
  }
  return repaired;
}

// ── Engagement refresh (manual, from the apps) ──────────────────────────────

export async function refreshEngagement(uuid: string): Promise<boolean> {
  const atom = await fetchAtom(uuid);
  if (!atom) return false;
  const url: string = atom.metadata?.url ?? '';
  if (!/instagram\.com/i.test(url)) return false;

  const media = await extractInstagramPost(url);
  const structured: Record<string, any> = { ...(atom.structured ?? {}) };
  const analysis: Record<string, any> = { ...(structured.swipeAnalysis ?? {}) };
  Object.assign(analysis, engagementFields(media.engagement, media.publishedAtISO, media.shortcode));
  structured.swipeAnalysis = analysis;
  await updateAtom(uuid, { structured });
  return true;
}

// ── Status helpers ──────────────────────────────────────────────────────────

async function setStatus(uuid: string, status: string): Promise<void> {
  await updateAtom(uuid, {
    metadata: {
      processingStatus: status,
      processingWorker: 'cloud',
      processingClaimedAt: new Date().toISOString(),
    },
  });
}

/// Decide what happens after a failed pass: one more quick attempt inside the
/// capture window, or retirement to STATUS_NEEDS_RETRY.
///
/// `failedStatus` is what the swipe should read as while it still has budget
/// ('partial' or 'extraction_failed'); once budget is gone the status becomes
/// terminal regardless, so no tick can pick it up again.
export function retrySchedule(
  atom: Atom | null,
  attempts: number,
  failedStatus: string = 'partial'
): Record<string, unknown> {
  const budgetLeft = attempts <= MAX_CLOUD_RETRIES;
  const inWindow = atom ? withinCaptureWindow(atom, Date.now()) : false;
  if (!budgetLeft || !inWindow) {
    return { processingStatus: STATUS_NEEDS_RETRY, processingRetryAfter: null };
  }
  const delaySeconds = RETRY_DELAYS_SECONDS[attempts - 1] ?? RETRY_DELAYS_SECONDS[RETRY_DELAYS_SECONDS.length - 1];
  return {
    processingStatus: failedStatus,
    processingRetryAfter: new Date(Date.now() + delaySeconds * 1_000).toISOString(),
  };
}

async function markFailed(uuid: string, permanent: boolean): Promise<void> {
  const atom = await fetchAtom(uuid);
  const attempts = Number(atom?.metadata?.cloudRetryCount ?? 0) + 1;
  // A permanent error (deleted post, private account) never earns a retry —
  // re-fetching it tomorrow costs an Apify run to learn the same thing.
  const schedule = permanent
    ? { processingStatus: STATUS_NEEDS_RETRY, processingRetryAfter: null }
    : retrySchedule(atom, attempts, 'extraction_failed');
  await updateAtom(uuid, {
    metadata: {
      processingWorker: 'cloud',
      cloudRetryCount: attempts,
      ...schedule,
    },
  });
}

export async function pendingHealth(): Promise<{ pendingCount: number; oldestPendingAgeSeconds: number }> {
  const { data } = await supabase
    .from('atoms')
    .select('updated_at')
    .eq('user_id', userId)
    .eq('type', 'research')
    .eq('is_deleted', false)
    .eq('metadata->>isSwipeFile', 'true')
    .in('metadata->>processingStatus', ['pending', 'extracting', 'transcribing', 'analyzing'])
    .order('updated_at', { ascending: true })
    .limit(100);

  const rows = (data ?? []) as Array<{ updated_at: string }>;
  const oldest = rows[0] ? (Date.now() - Date.parse(rows[0].updated_at)) / 1000 : 0;
  return { pendingCount: rows.length, oldestPendingAgeSeconds: Math.max(0, Math.round(oldest)) };
}
