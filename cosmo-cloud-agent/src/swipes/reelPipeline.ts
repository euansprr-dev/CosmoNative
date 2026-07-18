// cosmo-cloud-agent/src/swipes/reelPipeline.ts
// Multi-slide reel transcription — a faithful port of the Mac's
// InstagramAutoTranscriber Gemini pipeline. This is what makes text-card
// reels transcribe with every slide captured, no duplicates, and music
// never mistaken for a voiceover:
//   1. ffmpeg extracts frames at 4fps (max 240) — catches 1-frame text cuts
//   2. Gemini vision reads batches of 20 frames with the Mac's VERBATIM
//      batch prompt (frame→timestamp mapping, hook-first, every-unique-text)
//   3. batch results merge with boundary/global dedup (Jaccard ≥0.92,
//      containment ≥0.90 keeps the longer variant, timestamps union)
//   4. modality arbitration (lyricRisk / voiceoverScore / textScore) decides
//      textOnly vs voiceoverOnly vs voiceoverPlusText — lyrics and caption
//      mirrors never masquerade as narration
//   5. an LLM cleanup pass (Mac's verbatim prompt) fixes OCR artifacts
//      without merging/dropping slides
// Deviations from the Mac (deliberate): no Apple-Vision OCR fallback (no
// Apple frameworks server-side; Gemini is the primary there too) and no
// year-confusable digit normalization (an Apple-OCR-specific artifact).

import { spawn } from 'child_process';
import { mkdtemp, readFile, readdir, rm, writeFile } from 'fs/promises';
import { tmpdir } from 'os';
import { join } from 'path';
import { randomUUID } from 'crypto';
import { config } from '../config';
import { SpeechSegmentJSON, TranscriptSlideJSON } from './types';

const GEMINI_VISION_MODEL = config.openRouterVisionModel;
const GEMINI_FPS = 4.0;          // 4fps to catch short 1-frame text transitions
const MAX_GEMINI_FRAMES = 240;   // Accuracy-first cap for short reels with fast cuts
const GEMINI_BATCH_SIZE = 20;    // Frames per API call
const JACCARD_THRESHOLD = 0.62;

export type ReelContentType = 'textOnly' | 'voiceoverOnly' | 'voiceoverPlusText' | 'empty';

export interface ReelTranscription {
  slides: TranscriptSlideJSON[];       // cleaned (what clients render)
  rawSlides: TranscriptSlideJSON[];    // pre-cleanup merge output
  contentType: ReelContentType;
  warnings: string[];
}

interface Frame {
  jpeg: Buffer;
  timestamp: number;
}

interface Slide {
  text: string;
  slideNumber: number;
  timestamp?: number;
  endTimestamp?: number;
  source?: string;
}

interface Speech {
  text: string;
  timestamp: number;
  duration: number;
}

// ── Entry point ─────────────────────────────────────────────────────────────

export async function transcribeReel(
  videoData: Buffer,
  speechSegments: SpeechSegmentJSON[]
): Promise<ReelTranscription> {
  const warnings: string[] = [];
  const speech: Speech[] = speechSegments.map(s => ({
    text: s.text,
    timestamp: s.start,
    duration: Math.max(s.end - s.start, 0),
  }));

  let frames: Frame[] = [];
  let duration = 0;
  try {
    duration = await probeDuration(videoData);
    frames = await extractFrames(videoData, duration);
    console.log(`🎞 reel frames: ${frames.length} @ ${GEMINI_FPS}fps (${Math.round(duration)}s)`);
  } catch (error) {
    warnings.push('Frame extraction failed; on-screen text may be missing.');
    console.warn('⚠️ ffmpeg frame extraction failed:', error instanceof Error ? error.message : error);
  }

  let geminiSlides: Slide[] = [];
  if (frames.length > 0) {
    geminiSlides = await runGeminiVisionPipeline(frames);
    console.log(`🎞 gemini vision produced ${geminiSlides.length} slides`);
  }

  const merged = mergeGeminiWithSpeech(geminiSlides, speech, duration);
  const cleaned = await cleanupSlides(merged.slides, merged.contentType);

  return {
    slides: toJSON(cleaned),
    rawSlides: toJSON(merged.slides),
    contentType: merged.contentType,
    warnings,
  };
}

function toJSON(slides: Slide[]): TranscriptSlideJSON[] {
  return slides.map((slide, index) => ({
    id: randomUUID(),
    text: slide.text,
    slideNumber: index + 1,
    ...(slide.timestamp != null ? { timestamp: slide.timestamp } : {}),
    ...(slide.endTimestamp != null ? { endTimestamp: slide.endTimestamp } : {}),
    ...(slide.source ? { source: slide.source } : {}),
  }));
}

// ── ffmpeg frame extraction ─────────────────────────────────────────────────

function runProcess(command: string, args: string[], stdin?: Buffer): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args);
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', chunk => { stdout += chunk; });
    child.stderr.on('data', chunk => { stderr += chunk; });
    child.on('error', reject);
    child.on('close', code => {
      if (code === 0) resolve(stdout);
      else reject(new Error(`${command} exited ${code}: ${stderr.slice(-300)}`));
    });
    if (stdin) child.stdin.write(stdin);
    child.stdin.end();
  });
}

async function probeDuration(videoData: Buffer): Promise<number> {
  const dir = await mkdtemp(join(tmpdir(), 'reel-'));
  const videoPath = join(dir, 'video.mp4');
  try {
    await writeFile(videoPath, videoData);
    const out = await runProcess('ffprobe', [
      '-v', 'error', '-show_entries', 'format=duration',
      '-of', 'default=noprint_wrappers=1:nokey=1', videoPath,
    ]);
    const parsed = parseFloat(out.trim());
    return Number.isFinite(parsed) && parsed > 0.5 ? parsed : 60;
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

/**
 * Extract the audio track as mono 64kbps M4A. Whisper's API caps uploads at
 * 25MB — a 3-minute reel video blows past it, but its audio is ~1.5MB.
 */
export async function extractAudioTrack(videoData: Buffer): Promise<Buffer> {
  const dir = await mkdtemp(join(tmpdir(), 'reel-audio-'));
  const videoPath = join(dir, 'video.mp4');
  const audioPath = join(dir, 'audio.m4a');
  try {
    await writeFile(videoPath, videoData);
    await runProcess('ffmpeg', [
      '-i', videoPath,
      '-vn', '-ac', '1', '-b:a', '64k', '-c:a', 'aac',
      audioPath,
    ]);
    return await readFile(audioPath);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

export async function extractFrames(videoData: Buffer, duration: number): Promise<Frame[]> {
  // Mac contract: 4fps capped at 240 frames — long reels sample evenly.
  const fps = Math.min(GEMINI_FPS, MAX_GEMINI_FRAMES / Math.max(duration, 1));
  const dir = await mkdtemp(join(tmpdir(), 'reel-'));
  const videoPath = join(dir, 'video.mp4');
  try {
    await writeFile(videoPath, videoData);
    await runProcess('ffmpeg', [
      '-i', videoPath,
      '-vf', `fps=${fps.toFixed(4)},scale=-2:640`,
      '-q:v', '7',
      '-frames:v', String(MAX_GEMINI_FRAMES),
      join(dir, 'frame-%04d.jpg'),
    ]);
    const files = (await readdir(dir)).filter(f => f.startsWith('frame-')).sort();
    const frames: Frame[] = [];
    for (let i = 0; i < files.length; i += 1) {
      frames.push({ jpeg: await readFile(join(dir, files[i])), timestamp: i / fps });
    }
    return frames;
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

// ── Gemini vision pipeline (batch prompt VERBATIM from the Mac) ────────────

async function runGeminiVisionPipeline(frames: Frame[]): Promise<Slide[]> {
  if (!config.openRouterApiKey) return [];

  const batches: Slide[][] = [];
  for (let start = 0; start < frames.length; start += GEMINI_BATCH_SIZE) {
    const batch = frames.slice(start, start + GEMINI_BATCH_SIZE);
    let slides = await callGeminiVisionBatch(batch, start / GEMINI_BATCH_SIZE);
    if (slides === null) {
      slides = await callGeminiVisionBatch(batch, start / GEMINI_BATCH_SIZE); // retry once
    }
    if (slides && slides.length > 0) batches.push(slides);
  }
  return mergeGeminiBatchResults(batches);
}

async function callGeminiVisionBatch(frames: Frame[], batchIndex: number): Promise<Slide[] | null> {
  const timestamps = frames.map(f => f.timestamp);
  const timestampList = timestamps
    .map((t, i) => `Frame ${i}=${t.toFixed(1)}s`)
    .join(', ');

  // PORTED VERBATIM from InstagramAutoTranscriber.callGeminiVision.
  const prompt = `You are analyzing ${frames.length} sequential frames from an Instagram reel, captured at ~4fps.
Frame mapping: ${timestampList}

TASK: Extract ALL creator-placed text overlays and segment them into slides (distinct text screens).

CRITICAL REQUIREMENTS:
1. FIRST FRAME IS THE HOOK: Frame 0's text is the opening hook of this reel. You MUST capture it completely as your first slide. Never skip or merge it with later slides.
2. EVERY UNIQUE TEXT = ONE SLIDE: Each time the body text changes between frames, that is a new slide — even if a header (like a year) stays the same. Do NOT merge distinct text screens.
3. COMPLETE TEXT: For each slide, include the FULL text visible — every word, every number, every line. Do NOT truncate, summarize, or abbreviate.
4. LAST FRAMES MATTER: The final frames' text must be captured as the last slide. Do not omit ending slides.
5. ANIMATION HANDLING: If text appears gradually (animation/fade-in), use the fully-visible version as the slide text.

TEXT TO READ:
- Year/date headers (e.g., "2016", "Age 12", "1618")
- Main statement, fact, quote, or caption text
- Title cards, chapter markers, call-to-action text

TEXT TO IGNORE:
- Instagram UI (like counts, username, share/comment buttons, progress bar)
- Watermarks, @handles, brand logos
- Music credits, audio attribution
- Author attribution on a screenshotted post shown in-frame (tweet/thread/repost screenshots): the embedded post's profile photo, display name, @username handle, verified badge, timestamp, and like/reply counts are attribution, NOT content — skip them and read ONLY the post's body text
- Text that is part of background photographs (not overlaid by the creator)
- App/website UI inside screen recordings (browser pages, dashboards, listings) shown behind or between the creator's text overlays — the recorded screen's own menus, headers, and paragraphs are BACKGROUND; read ONLY the creator's overlay text

DIGITS AND YEARS: transcribe every number, year, price, and percentage EXACTLY as displayed — verify each digit. Getting "2026" vs "2025" wrong changes the meaning entirely.

OUTPUT FORMAT — return ONLY valid JSON:
{"slides": [{"text": "Full slide text", "startFrame": 0, "endFrame": 3}]}

FORMATTING:
- Join visual line breaks into one flowing sentence (do NOT preserve line wrapping from the video)
- If there is a year/date header, put it first then newline then body: "2016\\nWe started a new business in sales"
- startFrame/endFrame are 0-indexed within this batch
- Same text across consecutive frames = ONE slide with wider frame range`;

  const content: Array<Record<string, unknown>> = [{ type: 'text', text: prompt }];
  for (const frame of frames) {
    content.push({
      type: 'image_url',
      image_url: { url: `data:image/jpeg;base64,${frame.jpeg.toString('base64')}` },
    });
  }

  try {
    const response = await fetch(`${config.openRouterBaseUrl}/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${config.openRouterApiKey}`,
        'X-Title': 'CosmoOS',
      },
      body: JSON.stringify({
        model: GEMINI_VISION_MODEL,
        messages: [{ role: 'user', content }],
        temperature: 0.1,
        max_tokens: 4000,
      }),
      signal: AbortSignal.timeout(90_000),
    });
    if (!response.ok) {
      console.warn(`⚠️ gemini batch ${batchIndex} failed: ${response.status}`);
      return null;
    }
    const payload = await response.json() as { choices?: Array<{ message?: { content?: string } }> };
    const text = payload.choices?.[0]?.message?.content ?? '';
    return parseGeminiSlides(text, timestamps);
  } catch (error) {
    console.warn(`⚠️ gemini batch ${batchIndex} error:`, error instanceof Error ? error.message : error);
    return null;
  }
}

export function parseGeminiSlides(response: string, timestamps: number[]): Slide[] {
  let jsonString = response.trim();
  if (jsonString.startsWith('```')) {
    const firstNewline = jsonString.indexOf('\n');
    if (firstNewline >= 0) jsonString = jsonString.slice(firstNewline);
    if (jsonString.endsWith('```')) jsonString = jsonString.slice(0, -3);
    jsonString = jsonString.trim();
  }

  const braceStart = jsonString.indexOf('{');
  const braceEnd = jsonString.lastIndexOf('}');
  let slidesArray: Array<Record<string, unknown>> | null = null;
  if (braceStart >= 0 && braceEnd > braceStart) {
    try {
      const obj = JSON.parse(jsonString.slice(braceStart, braceEnd + 1)) as { slides?: Array<Record<string, unknown>> };
      if (Array.isArray(obj.slides)) slidesArray = obj.slides;
    } catch { /* fall through to array parse */ }
  }
  if (!slidesArray) {
    const bracketStart = jsonString.indexOf('[');
    const bracketEnd = jsonString.lastIndexOf(']');
    if (bracketStart < 0 || bracketEnd <= bracketStart) return [];
    try {
      slidesArray = JSON.parse(jsonString.slice(bracketStart, bracketEnd + 1)) as Array<Record<string, unknown>>;
    } catch {
      return [];
    }
  }

  return slidesArray
    .map((obj, index) => {
      const text = typeof obj.text === 'string' ? obj.text.trim() : '';
      if (!text) return null;
      const startFrame = typeof obj.startFrame === 'number' ? obj.startFrame : 0;
      const endFrame = typeof obj.endFrame === 'number' ? obj.endFrame : startFrame;
      const timestamp = startFrame < timestamps.length ? timestamps[startFrame] : undefined;
      const endTimestamp = endFrame < timestamps.length ? timestamps[endFrame] : timestamp;
      return {
        text: joinVisualLineBreaks(text),
        slideNumber: index + 1,
        timestamp,
        endTimestamp,
        source: 'geminiVision',
      } as Slide;
    })
    .filter((s): s is Slide => s !== null);
}

/** Keeps a year/date header on its own line; joins body lines into one sentence. */
export function joinVisualLineBreaks(text: string): string {
  const lines = text.split('\n').map(l => l.trim()).filter(Boolean);
  if (lines.length <= 1) return text.trim();
  const isYearHeader = lines[0].length <= 10 && /^(age\s*)?\d{2,4}/i.test(lines[0]);
  return isYearHeader ? `${lines[0]}\n${lines.slice(1).join(' ')}` : lines.join(' ');
}

// ── Batch merge + dedup (mergeGeminiBatchResults port) ──────────────────────

export function mergeGeminiBatchResults(batches: Slide[][]): Slide[] {
  const merged: Slide[] = [];

  for (const batch of batches) {
    for (const slide of batch) {
      const trimmedText = slide.text.trim();
      if (!trimmedText) continue;

      const last = merged[merged.length - 1];
      if (last && shouldMergeBoundarySlides(last, slide)) {
        if (trimmedText.length > last.text.length) last.text = trimmedText;
        const newEnd = slide.endTimestamp ?? slide.timestamp;
        if (newEnd != null) last.endTimestamp = newEnd;
        continue;
      }

      const duplicateIndex = merged.findIndex(existing => areDuplicateSlideTexts(existing.text, slide.text));
      if (duplicateIndex >= 0) {
        merged[duplicateIndex] = mergedDuplicateSlide(merged[duplicateIndex], slide);
        continue;
      }

      merged.push({ ...slide });
    }
  }

  merged.forEach((slide, i) => { slide.slideNumber = i + 1; });
  return merged;
}

function shouldMergeBoundarySlides(lhs: Slide, rhs: Slide): boolean {
  const lhsFingerprint = normalizedLineKey(lhs.text);
  const rhsFingerprint = normalizedLineKey(rhs.text);
  if (!lhsFingerprint || !rhsFingerprint) return false;
  if (lhsFingerprint === rhsFingerprint) return slidesOverlapInTime(lhs, rhs);
  const overlap = jaccard(new Set(lhsFingerprint.split(' ')), new Set(rhsFingerprint.split(' ')));
  return overlap >= 0.92 && slidesOverlapInTime(lhs, rhs);
}

function slidesOverlapInTime(lhs: Slide, rhs: Slide): boolean {
  const lhsStart = lhs.timestamp;
  const lhsEnd = lhs.endTimestamp ?? lhs.timestamp;
  const rhsStart = rhs.timestamp;
  if (lhsStart == null || lhsEnd == null || rhsStart == null) return false;
  return rhsStart <= lhsEnd + 0.35 && rhsStart >= lhsStart - 0.35;
}

export function areDuplicateSlideTexts(lhs: string, rhs: string): boolean {
  const lhsNorm = normalizedLineKey(lhs);
  const rhsNorm = normalizedLineKey(rhs);
  if (!lhsNorm || !rhsNorm) return false;
  if (lhsNorm === rhsNorm) return true;

  const lhsWords = new Set(lhsNorm.split(' '));
  const rhsWords = new Set(rhsNorm.split(' '));
  if (lhsWords.size < 2 || rhsWords.size < 2) return false;

  if (jaccard(lhsWords, rhsWords) >= 0.92) return true;
  const intersection = [...lhsWords].filter(w => rhsWords.has(w)).length;
  return intersection / Math.min(lhsWords.size, rhsWords.size) >= 0.90;
}

function mergedDuplicateSlide(existing: Slide, candidate: Slide): Slide {
  const merged = { ...existing };
  const existingWords = wordCount(existing.text);
  const candidateWords = wordCount(candidate.text);
  if (candidateWords > existingWords ||
      (candidateWords === existingWords && candidate.text.length > existing.text.length)) {
    merged.text = candidate.text;
    merged.source = candidate.source ?? existing.source;
  }
  if (existing.timestamp != null && candidate.timestamp != null) {
    merged.timestamp = Math.min(existing.timestamp, candidate.timestamp);
  } else {
    merged.timestamp = existing.timestamp ?? candidate.timestamp;
  }
  const existingEnd = existing.endTimestamp ?? existing.timestamp;
  const candidateEnd = candidate.endTimestamp ?? candidate.timestamp;
  if (existingEnd != null && candidateEnd != null) {
    merged.endTimestamp = Math.max(existingEnd, candidateEnd);
  } else {
    merged.endTimestamp = existingEnd ?? candidateEnd;
  }
  return merged;
}

// ── Modality arbitration (ReelModalityEvidence port) ────────────────────────

const LOW_SIGNAL_TOKENS = new Set([
  'a', 'an', 'and', 'are', 'as', 'at', 'be', 'but', 'by', 'can', 'for',
  'from', 'had', 'has', 'have', 'how', 'i', 'if', 'in', 'is', 'it',
  'its', 'just', 'like', 'of', 'on', 'or', 'so', 'that', 'the', 'their',
  'them', 'then', 'there', 'they', 'this', 'to', 'was', 'we', 'were',
  'what', 'when', 'with', 'you', 'your',
]);

export function detectContentType(
  visualSlides: Slide[],
  speech: Speech[],
  duration: number
): ReelContentType {
  const hasVisual = visualSlides.some(s => s.text.trim().length > 0);
  const hasSpeech = speech.some(s => s.text.trim().length > 0);
  if (!hasVisual && !hasSpeech) return 'empty';
  if (!hasVisual) return 'voiceoverOnly';
  if (!hasSpeech) return 'textOnly';

  const e = modalityEvidence(visualSlides, speech, duration);
  if (shouldPreferVoiceover(e)) return 'voiceoverOnly';
  if (shouldTreatAsTextOnly(e)) return 'textOnly';
  return 'voiceoverPlusText';
}

interface Evidence {
  visualWordCount: number;
  speechWordCount: number;
  visualSlideCount: number;
  avgVisualWordsPerSlide: number;
  shortVisualSlideRatio: number;
  longVisualSlideRatio: number;
  distinctVisualRatio: number;
  subtitleOverlapRatio: number;
  globalSubtitleOverlapRatio: number;
  captionMirroredSlideRatio: number;
  speechCoverageRatio: number;
  visualSlidesPerSecond: number;
  speechWordsPerSecond: number;
  avgSpeechWordsPerSegment: number;
  speechUniqueWordRatio: number;
  repeatedSpeechSegmentRatio: number;
  lyricRisk: number;
  voiceoverScore: number;
  textScore: number;
}

export function modalityEvidence(visualSlides: Slide[], speech: Speech[], duration: number): Evidence {
  const visualTexts = visualSlides.map(s => s.text.trim()).filter(Boolean);
  const speechTexts = speech.map(s => s.text.trim()).filter(Boolean);
  const visualWordCounts = visualTexts.map(wordCount);
  const speechWordCounts = speechTexts.map(wordCount);

  const visualWordCount = visualWordCounts.reduce((a, b) => a + b, 0);
  const speechWordCount = speechWordCounts.reduce((a, b) => a + b, 0);
  const visualSlideCount = visualTexts.length;
  const avgVisualWordsPerSlide = visualSlideCount ? visualWordCount / visualSlideCount : 0;
  const shortVisualSlideRatio = visualSlideCount ? visualWordCounts.filter(c => c <= 4).length / visualSlideCount : 0;
  const longVisualSlideRatio = visualSlideCount ? visualWordCounts.filter(c => c >= 8).length / visualSlideCount : 0;
  const distinctVisualCount = new Set(visualTexts.map(normalizedLineKey).filter(Boolean)).size;
  const distinctVisualRatio = visualSlideCount ? distinctVisualCount / visualSlideCount : 0;

  const subtitleOverlap = subtitleOverlapRatio(visualSlides, speech);
  const globalOverlap = tokenContainmentScore(
    visualSlides.map(s => s.text).join(' '),
    speech.map(s => s.text).join(' ')
  );
  const mirroredRatio = captionMirroredSlideRatio(visualSlides, speech);

  const totalSpeechDuration = speech.reduce((sum, s) => sum + Math.max(s.duration, 0), 0);
  const speechCoverageRatio = duration > 0 ? Math.min(totalSpeechDuration / duration, 1) : 0;
  const visualSlidesPerSecond = duration > 0 ? visualSlideCount / duration : visualSlideCount;
  const speechWordsPerSecond = duration > 0 ? speechWordCount / duration : speechWordCount;
  const avgSpeechWordsPerSegment = speechWordCounts.length ? speechWordCount / speechWordCounts.length : 0;

  const speechTokens = tokenSet(speechTexts.join(' '));
  const speechUniqueWordRatio = speechWordCount ? speechTokens.size / speechWordCount : 0;

  const normalizedSegments = speechTexts.map(normalizedLineKey).filter(Boolean);
  const segmentFrequency: Record<string, number> = {};
  for (const seg of normalizedSegments) segmentFrequency[seg] = (segmentFrequency[seg] ?? 0) + 1;
  const repeatedSegments = Object.values(segmentFrequency).filter(c => c > 1).reduce((a, b) => a + b, 0);
  const repeatedSpeechSegmentRatio = normalizedSegments.length ? repeatedSegments / normalizedSegments.length : 0;

  let lyricRisk = 0;
  if (speechWordCount > 0 && speechWordCount < 24 && avgSpeechWordsPerSegment <= 4.5) lyricRisk += 1;
  if (speechUniqueWordRatio < 0.55) lyricRisk += 1;
  if (repeatedSpeechSegmentRatio >= 0.2) lyricRisk += 1;
  if (speechWordsPerSecond < 0.9) lyricRisk += 1;
  if (subtitleOverlap >= 0.7 && speechCoverageRatio < 0.25) lyricRisk += 1;

  let voiceoverScore = 0;
  if (speechWordCount >= 18) voiceoverScore += 2;
  else if (speechWordCount >= 10) voiceoverScore += 1;
  if (speechCoverageRatio >= 0.35) voiceoverScore += 1;
  if (speechWordsPerSecond >= 1.4) voiceoverScore += 1;
  if (subtitleOverlap >= 0.58) voiceoverScore += 2;
  else if (subtitleOverlap >= 0.4) voiceoverScore += 1;
  if (globalOverlap >= 0.72) voiceoverScore += 2;
  if (mirroredRatio >= 0.6) voiceoverScore += 1;
  if (shortVisualSlideRatio >= 0.6 && visualSlideCount >= 5) voiceoverScore += 1;
  if (speechWordCount >= 24 && visualSlideCount >= 24 && visualSlidesPerSecond >= 1.25) {
    voiceoverScore += 3;
  } else if (speechWordCount >= 24 && visualSlideCount >= 48 && visualSlidesPerSecond >= 0.75) {
    voiceoverScore += 2;
  }
  if (speechWordCount >= Math.max(visualWordCount, 20)) voiceoverScore += 1;

  let textScore = 0;
  if (visualWordCount >= 30) textScore += 1;
  if (avgVisualWordsPerSlide >= 7) textScore += 1;
  if (visualSlideCount >= 4 && avgVisualWordsPerSlide >= 6 && subtitleOverlap < 0.4) textScore += 2;
  if (distinctVisualRatio >= 0.75 && longVisualSlideRatio >= 0.5) textScore += 1;
  if (speechWordCount <= 8) textScore += 1;

  return {
    visualWordCount, speechWordCount, visualSlideCount, avgVisualWordsPerSlide,
    shortVisualSlideRatio, longVisualSlideRatio, distinctVisualRatio,
    subtitleOverlapRatio: subtitleOverlap, globalSubtitleOverlapRatio: globalOverlap,
    captionMirroredSlideRatio: mirroredRatio, speechCoverageRatio,
    visualSlidesPerSecond, speechWordsPerSecond, avgSpeechWordsPerSegment,
    speechUniqueWordRatio, repeatedSpeechSegmentRatio, lyricRisk, voiceoverScore, textScore,
  };
}

function captionsGloballyMirrorSpeech(e: Evidence): boolean {
  return e.speechWordCount >= 18 && e.visualWordCount >= 12 &&
    e.globalSubtitleOverlapRatio >= 0.72 && e.captionMirroredSlideRatio >= 0.6;
}

function isLikelyOversegmentedVisualTranscript(e: Evidence): boolean {
  if (e.speechWordCount < 24 || e.visualWordCount < 40 || e.visualSlideCount < 24 || e.lyricRisk >= 4) return false;
  const denseByRate = e.visualSlidesPerSecond >= 1.25;
  const denseByAbsoluteCount = e.visualSlideCount >= 48 && e.visualSlidesPerSecond >= 0.75;
  const speechIsPrimary = e.speechCoverageRatio >= 0.35 || e.speechWordsPerSecond >= 1.2;
  return speechIsPrimary && (denseByRate || denseByAbsoluteCount);
}

export function shouldPreferVoiceover(e: Evidence): boolean {
  if (e.speechWordCount === 0) return false;
  if (e.visualWordCount === 0) return true;
  if (captionsGloballyMirrorSpeech(e)) return e.lyricRisk < 4 || e.voiceoverScore > e.textScore;
  if (isLikelyOversegmentedVisualTranscript(e)) return true;
  if (e.subtitleOverlapRatio >= 0.58 && e.speechCoverageRatio >= 0.25) {
    if (e.speechWordCount >= 18) return e.lyricRisk < 4 || e.voiceoverScore > e.textScore;
    // Mirrored speech too short to be real narration is a lyric or music
    // overlay — the slides carry the content, not the audio.
    return false;
  }
  if (e.distinctVisualRatio >= 0.75 && e.visualWordCount >= 12) return false;
  return e.voiceoverScore >= e.textScore + 2 && e.lyricRisk < 4;
}

export function shouldTreatAsTextOnly(e: Evidence): boolean {
  if (e.visualWordCount === 0) return false;
  if (e.speechWordCount === 0) return true;
  if (captionsGloballyMirrorSpeech(e) && e.lyricRisk < 4) return false;
  if (isLikelyOversegmentedVisualTranscript(e)) return false;
  // Short speech that merely mirrors the on-screen text (lyric or music
  // overlay) adds nothing — the slides already carry all of the content.
  if (e.subtitleOverlapRatio >= 0.7 && e.speechWordCount < 18) return true;
  if (e.lyricRisk >= 3 && e.textScore >= e.voiceoverScore) return true;
  return e.textScore >= e.voiceoverScore + 2 && !(e.speechWordCount >= 18 && e.subtitleOverlapRatio >= 0.4);
}

// ── Slides ⊕ speech merge (mergeGeminiWithSpeech port) ─────────────────────

export function mergeGeminiWithSpeech(
  geminiSlides: Slide[],
  speech: Speech[],
  duration: number
): { slides: Slide[]; contentType: ReelContentType } {
  const hasGemini = geminiSlides.length > 0;
  const hasSpeech = speech.length > 0;

  if (hasGemini && hasSpeech) {
    const contentType = detectContentType(geminiSlides, speech, duration);
    if (contentType === 'voiceoverOnly') {
      return { slides: speechToSlides(speech), contentType };
    }
    if (contentType === 'textOnly') {
      return { slides: deduplicateSlides(geminiSlides), contentType };
    }
    return {
      slides: mergeVisualSlidesWithSpeech(deduplicateSlides(geminiSlides), speech),
      contentType: 'voiceoverPlusText',
    };
  }
  if (hasGemini) return { slides: deduplicateSlides(geminiSlides), contentType: 'textOnly' };
  if (hasSpeech) return { slides: speechToSlides(speech), contentType: 'voiceoverOnly' };
  return { slides: [], contentType: 'empty' };
}

/** Voiceover-only reels read as ONE transcript slide, never artificial splits. */
function speechToSlides(speech: Speech[]): Slide[] {
  const text = speech.map(s => s.text).join(' ').trim();
  if (!text) return [];
  const start = Math.min(...speech.map(s => s.timestamp));
  const end = Math.max(...speech.map(s => s.timestamp + s.duration));
  return [{ text, slideNumber: 1, timestamp: start, endTimestamp: end, source: 'speechAudio' }];
}

/** Visual slides are primary; distinct speech appends as [Voiceover:] annotations. */
function mergeVisualSlidesWithSpeech(visualSlides: Slide[], speech: Speech[]): Slide[] {
  const merged = visualSlides.map(s => ({ ...s }));
  merged.forEach((slide, idx) => {
    const slideStart = slide.timestamp ?? 0;
    const slideEnd = slide.endTimestamp ?? slideStart + 3;
    const overlapping = speech.filter(seg => {
      const segEnd = seg.timestamp + Math.max(seg.duration, 0);
      return seg.timestamp <= slideEnd + 0.5 && segEnd >= slideStart - 0.5;
    });
    if (overlapping.length === 0) return;
    const spokenText = overlapping.map(s => s.text).join(' ');
    const slideNorm = normalizedLineKey(slide.text);
    const speechNorm = normalizedLineKey(spokenText);
    const overlapScore = tokenOverlapScore(slide.text, spokenText);
    if (slideNorm && speechNorm &&
        !slideNorm.includes(speechNorm) && !speechNorm.includes(slideNorm) &&
        overlapScore < 0.72) {
      merged[idx].text += `\n[Voiceover: ${spokenText}]`;
      merged[idx].source = 'merged';
    }
  });
  return merged;
}

/**
 * JSON-level [Voiceover:] annotation for dual-content reels — the V3 video
 * path reuses V2's exact merge rule (annotate only when the speech is
 * genuinely distinct from the slide text; overlap < 0.72).
 */
export function annotateSlidesWithVoiceover(
  slides: TranscriptSlideJSON[],
  speech: SpeechSegmentJSON[]
): TranscriptSlideJSON[] {
  const internalSlides: Slide[] = slides.map(s => ({
    text: s.text,
    slideNumber: s.slideNumber,
    timestamp: s.timestamp,
    endTimestamp: s.endTimestamp,
    source: s.source,
  }));
  const internalSpeech: Speech[] = speech.map(s => ({
    text: s.text,
    timestamp: s.start,
    duration: Math.max(s.end - s.start, 0),
  }));
  const merged = mergeVisualSlidesWithSpeech(internalSlides, internalSpeech);
  return merged.map((slide, index) => ({
    ...slides[index],
    text: slide.text,
    source: slide.source ?? slides[index].source,
  }));
}

/** JSON-level global dedup wrapper for the V3 video path. */
export function deduplicateSlidesJSON(slides: TranscriptSlideJSON[]): TranscriptSlideJSON[] {
  const internal: Slide[] = slides.map(s => ({
    text: s.text,
    slideNumber: s.slideNumber,
    timestamp: s.timestamp,
    endTimestamp: s.endTimestamp,
    source: s.source,
  }));
  const deduped = deduplicateSlides(internal);
  // Rebuild JSON slides — dedup can drop/merge entries, so re-id by position.
  return deduped.map((slide, index) => {
    const original = slides.find(s => s.text === slide.text) ?? slides[Math.min(index, slides.length - 1)];
    return {
      id: original.id,
      text: slide.text,
      slideNumber: index + 1,
      ...(slide.timestamp != null ? { timestamp: slide.timestamp } : {}),
      ...(slide.endTimestamp != null ? { endTimestamp: slide.endTimestamp } : {}),
      ...(slide.source ? { source: slide.source } : {}),
    };
  });
}

/** Global dedup against ALL accepted slides (consecutive AND non-consecutive). */
export function deduplicateSlides(slides: Slide[]): Slide[] {
  if (slides.length <= 1) return slides;
  const result: Slide[] = [{ ...slides[0] }];
  for (let i = 1; i < slides.length; i += 1) {
    const duplicateIndex = result.findIndex(existing => areDuplicateSlideTexts(existing.text, slides[i].text));
    if (duplicateIndex >= 0) {
      result[duplicateIndex] = mergedDuplicateSlide(result[duplicateIndex], slides[i]);
    } else {
      result.push({ ...slides[i] });
    }
  }
  result.forEach((slide, i) => { slide.slideNumber = i + 1; });
  return result;
}

// ── LLM cleanup pass (cleanupWithClaude port, reel variant) ─────────────────

async function cleanupSlides(slides: Slide[], contentType: ReelContentType): Promise<Slide[]> {
  const needsRefinement = contentType !== 'voiceoverOnly' &&
    slides.some(s => (s.source ?? 'manual') !== 'speechAudio');
  if (!needsRefinement || slides.length === 0 || !config.openRouterApiKey) return slides;

  // PORTED VERBATIM from InstagramAutoTranscriber.cleanupWithClaude (reel variant).
  const prompt = `You are cleaning up auto-transcribed text from Instagram Instagram slides. The OCR captured ALL visible text from each slide image. Your job is to extract ONLY the main text overlays that the creator intended viewers to read, while preserving the original slide structure exactly.

RULES:
1. REMOVE background text: brand names, watermarks, URLs, UI elements, text visible in background images, or any text that is clearly not the main overlay.
2. DO NOT merge, delete, reorder, or add slides. Output exactly one cleaned string for every input slide, in the same order.
3. FIX OCR artifacts: truncated words, random symbols, garbled characters, wrong numbers/letters from OCR misreads.
4. FIX incomplete sentences only when the correction is obvious. If uncertain, keep the original raw text for that slide.
5. KEEP the creator's original wording — do not rephrase or add new content.
6. JOIN text into flowing sentences — do NOT preserve visual line breaks from the image. Each slide's text should read as a natural paragraph. Only use a newline to separate a distinct header/title from the body text below it.
10. Each slide should contain the COMPLETE text from that slide — do not truncate or summarize.

Return ONLY valid JSON in this format:
{"slides":[{"index":1,"text":"cleaned text for slide 1"}, {"index":2,"text":"slide 2"}]}

The number of slides in your output MUST equal the number of input slides.
If a slide is uncertain, return the raw text for that slide.

Raw OCR slides:
${slides.map((s, i) => `[${i + 1}] ${s.text}`).join('\n')}`;

  try {
    const response = await fetch(`${config.openRouterBaseUrl}/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${config.openRouterApiKey}`,
        'X-Title': 'CosmoOS',
      },
      body: JSON.stringify({
        model: GEMINI_VISION_MODEL,
        messages: [{ role: 'user', content: prompt }],
        temperature: 0.1,
        max_tokens: 4000,
      }),
      signal: AbortSignal.timeout(60_000),
    });
    if (!response.ok) return slides;
    const payload = await response.json() as { choices?: Array<{ message?: { content?: string } }> };
    const cleaned = parseCleanedSlides(payload.choices?.[0]?.message?.content ?? '', slides.length);
    if (!cleaned) return slides;
    const refined = slides.map((original, index) => {
      const text = cleaned[index].trim();
      return {
        ...original,
        text: text || original.text,
        source: original.source === 'speechAudio' ? original.source : 'aiCleaned',
        slideNumber: index + 1,
      };
    });
    // CRITICAL: dedup AFTER cleanup. The cleaner maps 1:1 and can normalize
    // several noisy raw fragments (e.g. per-frame OCR of a screen recording)
    // into the SAME sentence — pre-cleanup dedup never sees those duplicates.
    return deduplicateSlides(refined);
  } catch {
    return slides;
  }
}

export function parseCleanedSlides(response: string, expectedCount: number): string[] | null {
  const attempts: string[] = [response.trim()];
  const braceStart = response.indexOf('{');
  const braceEnd = response.lastIndexOf('}');
  if (braceStart >= 0 && braceEnd > braceStart) attempts.push(response.slice(braceStart, braceEnd + 1));
  const bracketStart = response.indexOf('[');
  const bracketEnd = response.lastIndexOf(']');
  if (bracketStart >= 0 && bracketEnd > bracketStart) attempts.push(response.slice(bracketStart, bracketEnd + 1));

  for (const attempt of attempts) {
    try {
      const parsed = JSON.parse(attempt) as unknown;
      if (Array.isArray(parsed) && parsed.every(v => typeof v === 'string')) {
        if (parsed.length === expectedCount) return parsed as string[];
        continue;
      }
      const obj = parsed as { slides?: Array<{ index?: number; text?: string }> };
      if (Array.isArray(obj.slides)) {
        const sorted = [...obj.slides].sort((a, b) => (a.index ?? 0) - (b.index ?? 0));
        const texts = sorted.map(s => s.text ?? '');
        if (texts.length === expectedCount) return texts;
      }
    } catch { /* try next form */ }
  }
  return null;
}

// ── Text helpers (normalizedLineKey etc., ported) ──────────────────────────

export function normalizedLineKey(text: string): string {
  return text
    .toLowerCase()
    .replace(/’/g, "'")
    .replace(/[^\p{L}\p{N}\s$%'/]+/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function wordCount(text: string): number {
  return text.split(/\s+/).filter(Boolean).length;
}

function tokenSet(text: string): Set<string> {
  return new Set(normalizedLineKey(text).split(' ').filter(Boolean));
}

function tokenOverlapScore(lhs: string, rhs: string): number {
  const lhsTokens = tokenSet(lhs);
  const rhsTokens = tokenSet(rhs);
  if (lhsTokens.size === 0 || rhsTokens.size === 0) return 0;
  const intersection = [...lhsTokens].filter(t => rhsTokens.has(t)).length;
  return intersection / Math.min(lhsTokens.size, rhsTokens.size);
}

function jaccard(lhs: Set<string>, rhs: Set<string>): number {
  const intersection = [...lhs].filter(t => rhs.has(t)).length;
  const union = new Set([...lhs, ...rhs]).size;
  return union > 0 ? intersection / union : 0;
}

function subtitleOverlapRatio(visualSlides: Slide[], speech: Speech[]): number {
  if (visualSlides.length === 0 || speech.length === 0) return 0;
  const scores: number[] = [];
  for (const slide of visualSlides) {
    const slideStart = slide.timestamp ?? 0;
    const slideEnd = slide.endTimestamp ?? slideStart + 2;
    const overlapping = speech.filter(seg => {
      const segEnd = seg.timestamp + Math.max(seg.duration, 0);
      return seg.timestamp <= slideEnd + 0.5 && segEnd >= slideStart - 0.5;
    });
    const spokenText = overlapping.map(s => s.text).join(' ');
    if (!spokenText) continue;
    scores.push(tokenOverlapScore(slide.text, spokenText));
  }
  return scores.length ? scores.reduce((a, b) => a + b, 0) / scores.length : 0;
}

function captionMirroredSlideRatio(visualSlides: Slide[], speech: Speech[]): number {
  const speechText = speech.map(s => s.text).join(' ');
  if (!speechText.trim()) return 0;
  const eligible = visualSlides.filter(s => wordCount(s.text) >= 5);
  if (eligible.length === 0) return 0;
  const mirrored = eligible.filter(s => tokenContainmentScore(s.text, speechText) >= 0.72).length;
  return mirrored / eligible.length;
}

function tokenContainmentScore(needle: string, haystack: string): number {
  const needleTokens = significantTokens(needle);
  const haystackTokens = new Set(significantTokens(haystack));
  if (needleTokens.length === 0 || haystackTokens.size === 0) return 0;
  const matched = needleTokens.filter(t => haystackTokens.has(t)).length;
  return matched / needleTokens.length;
}

function significantTokens(text: string): string[] {
  return normalizedLineKey(text)
    .split(' ')
    .filter(token => {
      if (!token || LOW_SIGNAL_TOKENS.has(token)) return false;
      return token.length > 2 || /\d/.test(token);
    });
}
