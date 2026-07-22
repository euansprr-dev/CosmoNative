// cosmo-cloud-agent/src/swipes/transcribe.ts
// Cloud transcription: Whisper API for reel speech, Gemini Flash vision
// (via OpenRouter) for carousel slide text. The slide prompt is ported
// VERBATIM from the Mac's InstagramAutoTranscriber.callGeminiVisionForSingleImage
// — prompt detail drives quality; do not compress it.

import { randomUUID } from 'crypto';
import { config } from '../config';
import { SpeechSegmentJSON, TranscriptSlideJSON } from './types';

const GEMINI_VISION_MODEL = config.openRouterVisionModel;

// ── Reel speech via Whisper ─────────────────────────────────────────────────

export function whisperConfigured(): boolean {
  return config.openaiApiKey.length > 0;
}

export async function transcribeSpeech(
  mediaData: Buffer,
  media: { filename: string; mimeType: string } = { filename: 'video.mp4', mimeType: 'video/mp4' }
): Promise<SpeechSegmentJSON[]> {
  if (!whisperConfigured()) throw new Error('OPENAI_API_KEY not configured');

  const form = new FormData();
  form.append('file', new Blob([new Uint8Array(mediaData)], { type: media.mimeType }), media.filename);
  form.append('model', 'whisper-1');
  form.append('response_format', 'verbose_json');

  const response = await fetch('https://api.openai.com/v1/audio/transcriptions', {
    method: 'POST',
    headers: { Authorization: `Bearer ${config.openaiApiKey}` },
    body: form,
    signal: AbortSignal.timeout(300_000),
  });
  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Whisper ${response.status}: ${body.slice(0, 200)}`);
  }

  const payload = await response.json() as {
    segments?: Array<{ start?: number; end?: number; text?: string }>;
    text?: string;
  };

  const segments = (payload.segments ?? [])
    .map(s => ({
      start: typeof s.start === 'number' ? s.start : 0,
      end: typeof s.end === 'number' ? s.end : 0,
      text: (s.text ?? '').trim(),
    }))
    .filter(s => s.text.length > 0);

  if (segments.length === 0 && payload.text?.trim()) {
    segments.push({ start: 0, end: 0, text: payload.text.trim() });
  }
  return segments;
}

// ── Carousel slides via Gemini vision ───────────────────────────────────────

// PORTED VERBATIM from InstagramAutoTranscriber.callGeminiVisionForSingleImage.
const SLIDE_PROMPT = `You are reading text from a single Instagram carousel slide image.

Read ALL visible text overlays — the main text the creator placed on this slide for viewers to read.
This includes headings, statements, facts, quotes, captions, and call-to-action text.

IGNORE:
- Instagram UI (like counts, username, share button)
- Watermarks, brand logos
- Text in background images (not overlaid by creator)
- Author attribution on a screenshotted post: many slides are screenshots of a tweet, thread, or other social post. The attribution header/footer of that embedded post — profile photo, display name, @username handle, verified badge, timestamp, and like/reply/retweet counts — is attribution, NOT content. Skip it entirely and read ONLY the post's body text, verbatim. Example: for a tweet screenshot reading "Brennan Schlagbaum, CPA @Budgetdog_ / How To Retire Early…", output starts at "How To Retire Early" — the name and handle are never included.

Return ONLY the text content as a single string.
FORMATTING RULES:
- JOIN wrapped lines: text that wraps across multiple lines INSIDE one text block is one flowing sentence — never keep the image's visual line wrapping. A card reading "My stockmarket portfolio / made a gain of almost $700k / in 12 months" is ONE line: "My stockmarket portfolio made a gain of almost $700k in 12 months".
- One line per sentence: when a block contains several sentences, each sentence goes on its own line.
- One line per distinct element: separate text blocks/cards, headings, and standalone labels or big stats each get their own line (a card showing "RETURN" above "$695,613.43" is two lines).
- List items keep their bullet/number/arrow markers, one item per line. Never merge two list items into one line.
If no readable text is found, return an empty string.`;

/**
 * Transcribe carousel slides — one vision call per slide, matching the Mac's
 * per-slide pipeline (line breaks preserved per slide, no cross-slide bleed).
 * Calls run 6-concurrent: a 10-slide carousel drops from ~30s to ~4s with
 * identical per-slide accuracy. `slideImageUrls` are the LIVE CDN URLs from
 * Apify (fresh, publicly fetchable by OpenRouter).
 */
export async function transcribeSlides(slideImageUrls: string[]): Promise<TranscriptSlideJSON[]> {
  const texts: (string | null)[] = new Array(slideImageUrls.length).fill(null);
  let cursor = 0;
  const workers = Array.from({ length: Math.min(6, slideImageUrls.length) }, async () => {
    while (cursor < slideImageUrls.length) {
      const index = cursor;
      cursor += 1;
      texts[index] = await transcribeSingleSlide(slideImageUrls[index], index);
    }
  });
  await Promise.all(workers);

  return texts.map((text, index) => ({
    id: randomUUID(),
    text: text ?? '',
    slideNumber: index + 1,
    source: 'geminiVision',
  }));
}

async function transcribeSingleSlide(imageUrl: string, index: number): Promise<string | null> {
  if (!config.openRouterApiKey) return null;

  const body = {
    model: GEMINI_VISION_MODEL,
    messages: [{
      role: 'user',
      content: [
        { type: 'text', text: SLIDE_PROMPT },
        { type: 'image_url', image_url: { url: imageUrl } },
      ],
    }],
    temperature: 0.1,
    max_tokens: 1000,
  };

  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      const response = await fetch(`${config.openRouterBaseUrl}/chat/completions`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${config.openRouterApiKey}`,
          'X-Title': 'CosmoOS',
        },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(45_000),
      });
      if (!response.ok) {
        if (attempt === 0) continue;
        return null;
      }
      const payload = await response.json() as {
        choices?: Array<{ message?: { content?: string } }>;
      };
      const content = payload.choices?.[0]?.message?.content?.trim();
      return content && content.length > 0 ? content : null;
    } catch (error) {
      if (attempt === 1) {
        console.warn(`⚠️ slide ${index} vision transcription failed:`, error instanceof Error ? error.message : error);
      }
    }
  }
  return null;
}
