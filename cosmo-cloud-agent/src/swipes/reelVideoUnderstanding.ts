// cosmo-cloud-agent/src/swipes/reelVideoUnderstanding.ts
// Reel V3 (SWIPE_REEL_V3_PLAN.md): ONE native-video multimodal call replaces
// the frame-batch + heuristic-arbitration pipeline. The model watches the
// reel WITH its audio track, so it directly answers the questions V2's ~30
// hand-tuned thresholds approximated blind:
//   • is the audio narration or a music bed?           (it hears it)
//   • is the on-screen text authored cards or captions
//     that just mirror the speech?                     (it sees + hears both)
//   • what does every distinct text card say?          (it reads them)
//
// Tiers:
//   1. Direct Gemini API (GEMINI_API_KEY): Files API upload, videoMetadata
//      fps control (default 4 — same rate the Mac used to catch 1-frame text
//      cuts), responseSchema-enforced JSON.
//   2. OpenRouter video_url (existing key): base64 data URL; provider-default
//      sampling (~1fps) — dense text reels with few detected slides escalate
//      to tier 3.
//   3. (in processor.ts) the V2 frame-batch pipeline, byte-identical fallback.

import { config } from '../config';

export interface VideoSlide {
  text: string;
  startSec: number;
  endSec: number;
}

export interface VideoSpeechSegment {
  startSec: number;
  endSec: number;
  text: string;
}

export interface VideoUnderstanding {
  modality: 'textOnly' | 'voiceoverOnly' | 'voiceoverPlusText' | 'empty';
  audioIsMusic: boolean;
  visualTextDensity: 'none' | 'sparse' | 'dense';
  slides: VideoSlide[];
  speechTranscript: VideoSpeechSegment[];
  tier: 'gemini' | 'openrouter';
}

const MAX_OPENROUTER_VIDEO_BYTES = 14 << 20; // base64 inflation must stay under request limits

// ── The prompt (single source of truth for both tiers) ─────────────────────
// Carries every hard-won rule from the Mac's batch prompt, restated for a
// model that has the full video + audio context.

const VIDEO_PROMPT = `You are analyzing an Instagram reel — you can see the video frames AND hear the audio track.

Instagram reels come in these forms:
- MULTI-SLIDER: a sequence of creator-authored text cards on screen (usually over a music bed). The text cards ARE the content.
- VOICEOVER: a person talking (talking head or B-roll narration). The speech IS the content. These often have burned-in captions/subtitles on screen that merely repeat what is being said — those captions are NOT content slides.
- DUAL: authored text cards PLUS narration whose content is DISTINCT from the cards (the speaker adds different information than what is written).
- Music-only with no meaningful on-screen text and no speech.

YOUR TASKS:

1. CLASSIFY modality:
- "textOnly": authored text cards carry the content; audio is music or negligible speech.
- "voiceoverOnly": speech carries the content; on-screen text is absent OR is captions/subtitles mirroring the speech. Captions mirroring speech means: the words on screen track what is currently being said (even paraphrased or fragmented). When in doubt between authored cards and captions, check whether the on-screen text appears in sync with the spoken words — if yes, they are captions.
- "voiceoverPlusText": BOTH authored cards and distinct narration are present.
- "empty": neither meaningful text nor speech.

2. EXTRACT SLIDES (only authored text cards — NEVER captions/subtitles):
- FIRST CARD IS THE HOOK: the opening text card must be captured completely as slide 1. Never skip or merge it into later slides.
- EVERY UNIQUE TEXT = ONE SLIDE: each time the body text changes, that is a new slide — even if a header (like a year) stays the same. Do NOT merge distinct cards. Do NOT emit the same card twice.
- COMPLETE TEXT: include the FULL text visible on each card — every word, every number, every line. Do NOT truncate, summarize, or abbreviate.
- LAST CARDS MATTER: the final card must be captured. Do not omit ending cards.
- ANIMATION HANDLING: if text appears gradually (typing/fade-in), use the fully-visible version.
- TEXT TO IGNORE: Instagram UI (like counts, usernames, buttons, progress bar), watermarks, @handles, brand logos, music/audio attribution, text that is part of background photographs rather than overlaid by the creator, and captions/subtitles of the speech.
- SCREEN RECORDINGS: reels often show a recorded website or app (a browser page, a dashboard, a listing) behind or between the creator's text cards. The recorded screen's own text (menus, headers, paragraphs of the web page) is BACKGROUND — never emit it as slides. Read ONLY the text the creator overlaid on top of it.
- DIGITS AND YEARS: transcribe every number, year, price, and percentage EXACTLY as displayed — verify each digit character by character. Getting "2026" vs "2025" wrong changes the meaning entirely.
- FORMATTING: join visual line breaks into one flowing sentence. Exception: a short year/date header (e.g. "2016", "Age 12") stays on its own line before the body: "2016\\nWe started a new business".
- startSec/endSec: when the card is first and last visible, in seconds.

3. TRANSCRIBE SPEECH (verbatim):
- Transcribe ONLY spoken narration/dialogue, word for word, as timestamped segments (natural sentence-sized chunks).
- NEVER transcribe sung lyrics, music, chants, or background vocals — if the audio is only music/lyrics, return an empty speechTranscript and set audioIsMusic to true.
- If there is real narration over background music, transcribe the narration and set audioIsMusic to false.

4. visualTextDensity: "dense" if authored text cards appear throughout the reel, "sparse" if only occasional text, "none" if no authored text.

Return ONLY JSON matching the schema. No markdown.`;

const RESPONSE_SCHEMA = {
  type: 'OBJECT',
  properties: {
    modality: { type: 'STRING', enum: ['textOnly', 'voiceoverOnly', 'voiceoverPlusText', 'empty'] },
    audioIsMusic: { type: 'BOOLEAN' },
    visualTextDensity: { type: 'STRING', enum: ['none', 'sparse', 'dense'] },
    slides: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          text: { type: 'STRING' },
          startSec: { type: 'NUMBER' },
          endSec: { type: 'NUMBER' },
        },
        required: ['text', 'startSec', 'endSec'],
      },
    },
    speechTranscript: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          startSec: { type: 'NUMBER' },
          endSec: { type: 'NUMBER' },
          text: { type: 'STRING' },
        },
        required: ['startSec', 'endSec', 'text'],
      },
    },
  },
  required: ['modality', 'audioIsMusic', 'visualTextDensity', 'slides', 'speechTranscript'],
} as const;

// ── Entry point ─────────────────────────────────────────────────────────────

export async function understandReelVideo(videoData: Buffer, caption?: string): Promise<VideoUnderstanding | null> {
  const prompt = promptWithCaption(caption);
  if (config.geminiApiKey) {
    // Two attempts: the preview model intermittently 503s under load and a
    // second try often lands on capacity (otherwise tier 2 takes over).
    for (let attempt = 0; attempt < 2; attempt += 1) {
      try {
        const result = await viaGeminiAPI(videoData, prompt);
        if (result) return result;
        break; // parse-level null: retrying the same video won't help
      } catch (error) {
        console.warn(`⚠️ tier-1 video understanding failed (attempt ${attempt + 1}):`, error instanceof Error ? error.message : error);
        if (attempt === 0) await new Promise(resolve => setTimeout(resolve, 3_000));
      }
    }
  }
  if (config.openRouterApiKey && videoData.length <= MAX_OPENROUTER_VIDEO_BYTES) {
    try {
      const result = await viaOpenRouter(videoData, prompt);
      if (result) return result;
    } catch (error) {
      console.warn('⚠️ tier-2 video understanding failed:', error instanceof Error ? error.message : error);
    }
  }
  return null;
}

/**
 * The post caption frequently repeats the on-screen hook verbatim — hand it
 * to the model as a cross-reference for exact wording and digits.
 */
export function promptWithCaption(caption?: string): string {
  const trimmed = caption?.trim();
  if (!trimmed) return VIDEO_PROMPT;
  return `${VIDEO_PROMPT}

REFERENCE — the post's caption (it often repeats the opening card's text; use it to verify exact wording and numbers when pixels are ambiguous, but transcribe what is actually ON SCREEN):
${trimmed.slice(0, 1500)}`;
}

/**
 * Tier-2 sampling (~1fps) can under-sample dense fast-cut text reels: a model
 * that says "dense text" but found almost no slides has likely missed cards —
 * escalate to the 4fps frame-batch pipeline instead of trusting it.
 */
export function shouldEscalateToFrames(result: VideoUnderstanding): boolean {
  return result.tier === 'openrouter' &&
    result.visualTextDensity === 'dense' &&
    result.slides.length < 3;
}

// ── Tier 1: direct Gemini API (Files API + fps control) ────────────────────

async function viaGeminiAPI(videoData: Buffer, prompt: string): Promise<VideoUnderstanding | null> {
  const fileUri = await uploadToGeminiFiles(videoData);
  try {
    const body = {
      contents: [{
        parts: [
          {
            fileData: { fileUri, mimeType: 'video/mp4' },
            videoMetadata: { fps: config.reelVideoFps },
          },
          { text: prompt },
        ],
      }],
      generationConfig: {
        temperature: 0.1,
        maxOutputTokens: 8192,
        responseMimeType: 'application/json',
        responseSchema: RESPONSE_SCHEMA,
      },
    };

    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${config.geminiVideoModel}:generateContent?key=${encodeURIComponent(config.geminiApiKey)}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(180_000),
      }
    );
    if (!response.ok) {
      const detail = await response.text();
      throw new Error(`generateContent ${response.status}: ${detail.slice(0, 200)}`);
    }
    const payload = await response.json() as {
      candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
    };
    const text = payload.candidates?.[0]?.content?.parts?.map(p => p.text ?? '').join('') ?? '';
    return parseVideoUnderstanding(text, 'gemini');
  } finally {
    void deleteGeminiFile(fileUri);
  }
}

/** Resumable upload to the Gemini Files API; polls until ACTIVE. */
async function uploadToGeminiFiles(videoData: Buffer): Promise<string> {
  const startResponse = await fetch(
    `https://generativelanguage.googleapis.com/upload/v1beta/files?key=${encodeURIComponent(config.geminiApiKey)}`,
    {
      method: 'POST',
      headers: {
        'X-Goog-Upload-Protocol': 'resumable',
        'X-Goog-Upload-Command': 'start',
        'X-Goog-Upload-Header-Content-Length': String(videoData.length),
        'X-Goog-Upload-Header-Content-Type': 'video/mp4',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ file: { display_name: `reel-${Date.now()}.mp4` } }),
      signal: AbortSignal.timeout(30_000),
    }
  );
  const uploadUrl = startResponse.headers.get('x-goog-upload-url');
  if (!startResponse.ok || !uploadUrl) {
    throw new Error(`files start ${startResponse.status}`);
  }

  const uploadResponse = await fetch(uploadUrl, {
    method: 'POST',
    headers: {
      'X-Goog-Upload-Command': 'upload, finalize',
      'X-Goog-Upload-Offset': '0',
      'Content-Length': String(videoData.length),
    },
    body: new Uint8Array(videoData),
    signal: AbortSignal.timeout(120_000),
  });
  if (!uploadResponse.ok) throw new Error(`files upload ${uploadResponse.status}`);
  const uploaded = await uploadResponse.json() as { file?: { name?: string; uri?: string; state?: string } };
  const name = uploaded.file?.name;
  const uri = uploaded.file?.uri;
  if (!name || !uri) throw new Error('files upload returned no uri');

  // Video needs server-side processing before it is usable.
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const status = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/${name}?key=${encodeURIComponent(config.geminiApiKey)}`,
      { signal: AbortSignal.timeout(15_000) }
    );
    if (status.ok) {
      const info = await status.json() as { state?: string };
      if (info.state === 'ACTIVE') return uri;
      if (info.state === 'FAILED') throw new Error('file processing failed');
    }
    await new Promise(resolve => setTimeout(resolve, 2_000));
  }
  throw new Error('file processing timed out');
}

async function deleteGeminiFile(fileUri: string): Promise<void> {
  try {
    const name = fileUri.split('/v1beta/')[1] ?? fileUri.match(/files\/[^/?]+$/)?.[0];
    if (!name) return;
    await fetch(
      `https://generativelanguage.googleapis.com/v1beta/${name}?key=${encodeURIComponent(config.geminiApiKey)}`,
      { method: 'DELETE', signal: AbortSignal.timeout(10_000) }
    );
  } catch { /* files auto-expire in 48h anyway */ }
}

// ── Tier 2: OpenRouter video_url ────────────────────────────────────────────

async function viaOpenRouter(videoData: Buffer, prompt: string): Promise<VideoUnderstanding | null> {
  const response = await fetch(`${config.openRouterBaseUrl}/chat/completions`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${config.openRouterApiKey}`,
      'X-Title': 'CosmoOS',
    },
    body: JSON.stringify({
      model: 'google/gemini-3-flash-preview',
      messages: [{
        role: 'user',
        content: [
          { type: 'text', text: prompt },
          { type: 'video_url', video_url: { url: `data:video/mp4;base64,${videoData.toString('base64')}` } },
        ],
      }],
      temperature: 0.1,
      max_tokens: 8192,
    }),
    signal: AbortSignal.timeout(180_000),
  });
  if (!response.ok) {
    const detail = await response.text();
    throw new Error(`openrouter video ${response.status}: ${detail.slice(0, 200)}`);
  }
  const payload = await response.json() as { choices?: Array<{ message?: { content?: string } }> };
  return parseVideoUnderstanding(payload.choices?.[0]?.message?.content ?? '', 'openrouter');
}

// ── Parsing (pure — unit-tested) ────────────────────────────────────────────

export function parseVideoUnderstanding(
  raw: string,
  tier: 'gemini' | 'openrouter'
): VideoUnderstanding | null {
  let jsonString = raw.trim();
  if (jsonString.startsWith('```')) {
    const firstNewline = jsonString.indexOf('\n');
    if (firstNewline >= 0) jsonString = jsonString.slice(firstNewline);
    if (jsonString.endsWith('```')) jsonString = jsonString.slice(0, -3);
    jsonString = jsonString.trim();
  }
  const braceStart = jsonString.indexOf('{');
  const braceEnd = jsonString.lastIndexOf('}');
  if (braceStart < 0 || braceEnd <= braceStart) return null;

  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(jsonString.slice(braceStart, braceEnd + 1)) as Record<string, unknown>;
  } catch {
    return null;
  }

  const modality = parsed.modality;
  if (modality !== 'textOnly' && modality !== 'voiceoverOnly' &&
      modality !== 'voiceoverPlusText' && modality !== 'empty') {
    return null;
  }

  const slides = (Array.isArray(parsed.slides) ? parsed.slides : [])
    .map((s: Record<string, unknown>) => ({
      text: typeof s.text === 'string' ? s.text.trim() : '',
      startSec: numberOr(s.startSec, 0),
      endSec: numberOr(s.endSec, numberOr(s.startSec, 0)),
    }))
    .filter(s => s.text.length > 0);

  const speechTranscript = (Array.isArray(parsed.speechTranscript) ? parsed.speechTranscript : [])
    .map((s: Record<string, unknown>) => ({
      startSec: numberOr(s.startSec, 0),
      endSec: numberOr(s.endSec, numberOr(s.startSec, 0)),
      text: typeof s.text === 'string' ? s.text.trim() : '',
    }))
    .filter(s => s.text.length > 0);

  const density = parsed.visualTextDensity;
  return {
    modality,
    audioIsMusic: parsed.audioIsMusic === true,
    visualTextDensity: density === 'dense' || density === 'sparse' || density === 'none' ? density : 'none',
    slides,
    speechTranscript,
    tier,
  };
}

function numberOr(value: unknown, fallback: number): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
}
