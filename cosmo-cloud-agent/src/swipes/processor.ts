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
import { annotateSlidesWithVoiceover, deduplicateSlidesJSON, extractAudioTrack, transcribeReel } from './reelPipeline';
import { shouldEscalateToFrames, understandReelVideo } from './reelVideoUnderstanding';
import { randomUUID as newUUID } from 'crypto';
import { fetchTweetText, fetchYouTubeTranscript, youtubeVideoId } from './fetchers';
import {
  AnalyzeContext, buildAnalysisJSON, classify, engagementFields,
  normalizeCreatorHandle, resolveCreator,
} from './analyze';
import {
  appleSeconds, ExtractedMedia, SpeechSegmentJSON, SwipeExtractionError, TranscriptSlideJSON,
} from './types';
import { randomUUID } from 'crypto';

const CLAIM_STALE_MINUTES = 15;
const MAX_CLOUD_RETRIES = 5;
const CONCURRENCY = 3;

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
  workerTask = cron.schedule('*/15 * * * * *', () => {
    void tick();
  });
  // Video backfill: the whole pre-worker library has reels with no
  // videoStorageURL (the Mac's mirror never uploaded). Slow drip, one per
  // minute, media-only — transcripts and analysis are never touched.
  cron.schedule('0 * * * * *', () => {
    void backfillTick();
  });
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

export async function fetchCandidates(): Promise<Atom[]> {
  const { data, error } = await supabase
    .from('atoms')
    .select('uuid, metadata, updated_at')
    .eq('user_id', userId)
    .eq('type', 'research')
    .eq('is_deleted', false)
    .eq('metadata->>isSwipeFile', 'true')
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

    // In-flight statuses: only reclaim stale claims (crashed worker / dead Mac run).
    if (status === 'extracting' || status === 'transcribing' || status === 'analyzing') {
      const claimedAt = Date.parse(meta.processingClaimedAt ?? '') || Date.parse(atom.updated_at) || 0;
      return now - claimedAt > CLAIM_STALE_MINUTES * 60_000;
    }
    // Failed AND partial: exponential-ish backoff via processingRetryAfter,
    // capped attempts (an unthrottled partial reprocesses every 15s tick —
    // an Apify run each time).
    if (status === 'extraction_failed' || status === 'partial') {
      const attempts = Number(meta.cloudRetryCount ?? 0);
      if (attempts >= MAX_CLOUD_RETRIES) return false;
      const retryAfter = Date.parse(meta.processingRetryAfter ?? '') || 0;
      return now >= retryAfter;
    }
    return true; // pending
  });
}

export async function processSwipe(uuid: string): Promise<void> {
  const atom = await fetchAtom(uuid);
  if (!atom || atom.is_deleted) return;
  const meta = atom.metadata ?? {};
  if (meta.isSwipeFile !== true && meta.isSwipeFile !== 'true') return;

  const url: string = meta.url ?? atom.structured?.sourceUrl ?? '';
  const source: string = (meta.contentSource ?? '').toLowerCase();

  // Scope: instagram / youtube / twitter. Everything else stays untouched
  // for the Mac pipeline (websites etc. have richer local handling).
  const isInstagram = source.includes('instagram') || /instagram\.com/i.test(url);
  const isYouTube = source.includes('youtube') || /youtube\.com|youtu\.be/i.test(url);
  const isTwitter = source === 'twitter' || /twitter\.com|(^|\.)x\.com/i.test(url);
  if (!url || (!isInstagram && !isYouTube && !isTwitter)) return;

  console.log(`🌀 processing swipe ${uuid.slice(0, 8)} (${source || 'url'})`);
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
    console.log(`✅ swipe ${uuid.slice(0, 8)} complete`);
  } catch (error) {
    const permanent = error instanceof SwipeExtractionError && error.permanent;
    console.error(`❌ swipe ${uuid.slice(0, 8)} failed:`, error instanceof Error ? error.message : error);
    await markFailed(uuid, permanent);
  }
}

// ── Instagram pipeline ──────────────────────────────────────────────────────

async function processInstagram(uuid: string, url: string): Promise<void> {
  // Quick stage: permanent thumbnail within seconds, before Apify returns.
  await quickThumbnailStage(uuid, url);

  const media = await extractInstagramPost(url);
  const atom = await fetchAtom(uuid);
  if (!atom || atom.is_deleted) return;

  // Media mirroring (before transcription — CDN URLs expire). The video is
  // downloaded ONCE and the buffer reused for mirror + Whisper + frames.
  const metadataUpdates: Record<string, unknown> = {};
  let videoData: Buffer | null = null;
  if (media.videoUrl) {
    try {
      videoData = await downloadBinary(media.videoUrl, 'video');
    } catch (error) {
      console.warn(`⚠️ video download failed for ${uuid.slice(0, 8)}:`, error instanceof Error ? error.message : error);
    }
  }
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
  await setStatus(uuid, 'transcribing');
  const editedByUser = atom.structured?.swipeAnalysis?.transcriptEditedByUser === true;

  let slides: TranscriptSlideJSON[] = [];
  let rawSlides: TranscriptSlideJSON[] = [];
  let speech: SpeechSegmentJSON[] = [];
  const warnings: string[] = [];
  let quality = 'accurate';

  if (!editedByUser) {
    if (media.contentType === 'carousel' && media.slides.length > 0) {
      const slideImageUrls = media.slides.map(s => (s.isVideo ? s.thumbnailUrl ?? s.mediaUrl : s.mediaUrl));
      slides = await transcribeSlides(slideImageUrls);
      rawSlides = slides;
    } else if (media.contentType === 'image' && media.thumbnailUrl) {
      slides = await transcribeSlides([media.thumbnailUrl]);
      rawSlides = slides;
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
        console.log(`🎞 reel ${uuid.slice(0, 8)}: V2-fallback ${reel.contentType}, ${slides.length} slide(s)`);
      }
    } else if (media.videoUrl) {
      warnings.push('Video download failed; transcript unavailable this pass.');
      quality = 'degraded';
    }
  }

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

  // Classification LLM call.
  const analysisText = combined || media?.caption || '';
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
  };

  const classification = await classify(ctx);
  if (classification) {
    const { handle, name } = normalizeCreatorHandle(
      classification.creatorHandle, classification.creatorName, ctx.author
    );
    const creatorUUID = await resolveCreator(handle, name, atom, ctx.platform || 'instagram');
    const analysisJSON = buildAnalysisJSON(classification, creatorUUID);
    // Classification overrides; transcript/engagement keys set above survive.
    Object.assign(existingAnalysis, analysisJSON);
    // Instagram video can never be a static "post" (Mac platform-validation rule).
    if (media?.videoUrl && (existingAnalysis.swipeContentFormat === 'post' || !existingAnalysis.swipeContentFormat)) {
      existingAnalysis.swipeContentFormat = 'multiSliderReel';
    }
  }

  // A video reel that ends with NO transcript at all is not "complete" — it
  // is a transient pile-up (Whisper down + all video tiers failing). Mark it
  // partial with backoff so it self-heals instead of silently staying empty.
  const isVideoReel = Boolean(media?.videoUrl);
  const isPartial = !result.editedByUser && !slideText && !speechText && isVideoReel;
  metadataUpdates.processingStatus = isPartial ? 'partial' : 'complete';
  metadataUpdates.processingWorker = 'cloud';
  if (isPartial) {
    const attempts = Number(atom.metadata?.cloudRetryCount ?? 0) + 1;
    metadataUpdates.cloudRetryCount = attempts;
    metadataUpdates.processingRetryAfter = new Date(Date.now() + 30 * attempts * 60_000).toISOString();
  } else {
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

async function markFailed(uuid: string, permanent: boolean): Promise<void> {
  const atom = await fetchAtom(uuid);
  const attempts = Number(atom?.metadata?.cloudRetryCount ?? 0) + 1;
  const retryDelayMinutes = permanent ? 24 * 60 : 30 * attempts;
  await updateAtom(uuid, {
    metadata: {
      processingStatus: 'extraction_failed',
      processingWorker: 'cloud',
      cloudRetryCount: permanent ? MAX_CLOUD_RETRIES : attempts,
      processingRetryAfter: new Date(Date.now() + retryDelayMinutes * 60_000).toISOString(),
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
