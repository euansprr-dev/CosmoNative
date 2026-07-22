// cosmo-cloud-agent/src/swipes/slideText.ts
// Faithful port of the Mac's slide-text post-processing
// (InstagramAutoTranscriber.postProcessSlides → sanitizeSlideText and
// helpers). The Mac repairs vision output client-side — merging visual
// line-wraps back into flowing sentences, splitting at true sentence
// boundaries, dropping OCR artifact lines, deduplicating — but the worker
// stored raw model output untouched, so cloud-processed carousels rendered
// with mid-sentence line breaks on every client. This module is the parity
// layer; the prompt-side JOIN rules in transcribe.ts are the first line of
// defense and this is deterministic insurance.
//
// Deliberate deviation from the Mac (matching reelPipeline's existing
// deviations): correctLikelyYearOutliers (cross-slide year medians) is not
// ported. normalizeStandaloneYearArtifacts (digit-confusable years) IS.
//
// If the Mac heuristics change, port them again — the thresholds
// (Jaccard 0.85 line dedup, 14-char short-line merges) are calibrated pairs.

import { TranscriptSlideJSON } from './types';
import { deduplicateSlidesJSON } from './reelPipeline';

const CONTENT_PUNCTUATION = new Set(".,;:!?()[]$%&@#/'-\"—–…✓✗•·");

function isAlphanumeric(ch: string): boolean {
  return /[\p{L}\p{N}]/u.test(ch);
}

function isUppercaseLetter(ch: string | undefined): boolean {
  return ch !== undefined && /\p{Lu}/u.test(ch);
}

function isLowercaseLetter(ch: string | undefined): boolean {
  return ch !== undefined && /\p{Ll}/u.test(ch);
}

export function normalizedLineKey(text: string): string {
  return text
    .toLowerCase()
    .replace(/’/g, "'")
    .replace(/[^\p{L}\p{N}\s$%'/]+/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function jaccardSimilarity(a: Set<string>, b: Set<string>): number {
  if (a.size === 0 && b.size === 0) return 1;
  let intersection = 0;
  for (const item of a) if (b.has(item)) intersection += 1;
  const union = a.size + b.size - intersection;
  return union === 0 ? 0 : intersection / union;
}

/// Port of isLikelyArtifactLine — OCR noise (symbol runs, vowelless fragments).
export function isLikelyArtifactLine(line: string): boolean {
  const compact = line.trim();
  if (compact.length <= 1) return true;

  const chars = Array.from(compact);
  const symbols = chars.filter(
    ch => !isAlphanumeric(ch) && !/\s/.test(ch) && !CONTENT_PUNCTUATION.has(ch)
  );
  const ratio = symbols.length / chars.length;
  if (symbols.length >= 3 && ratio > 0.3) return true;

  const words = compact.split(' ').filter(w => w.length > 0);
  if (words.length === 1) {
    const word = words[0];
    if (Array.from(word).length <= 3) {
      const hasDigit = /\p{Nd}/u.test(word);
      const hasVowel = /[aeiouy]/.test(word.toLowerCase());
      if (!hasDigit && !hasVowel) return true;
    }
    const letters = Array.from(word).filter(ch => /\p{L}/u.test(ch));
    const vowels = letters.filter(ch => /[aeiouAEIOU]/.test(ch));
    if (letters.length >= 5 && vowels.length === 0) return true;
  }
  return false;
}

function endsSentence(line: string): boolean {
  const last = line.trim().slice(-1);
  return last !== '' && ['.', '!', '?', ':'].includes(last);
}

/// Port of shouldJoinLine — decides whether `next` is a visual wrap of
/// `previous` (join) or a deliberate separate line (keep).
export function shouldJoinLine(previous: string, next: string, isCarousel: boolean): boolean {
  // Hyphenated word wrap ("anti-\nestablishment") — letter before the dash.
  if (previous.endsWith('-') && previous.length > 1) {
    const beforeDash = previous.slice(0, -1);
    const lastChar = beforeDash.slice(-1);
    if (/\p{L}/u.test(lastChar)) return true;
  }
  // Numbered list items never merge.
  const numberedPattern = /^\d+[.)\-]\s?/;
  if (numberedPattern.test(previous) || numberedPattern.test(next)) return false;
  // Arrow / bullet list items never merge.
  const bulletPattern = /^[→▸►•·\-*+]\s/;
  if (bulletPattern.test(next) || bulletPattern.test(previous)) return false;
  // A line that is purely a number (year header, big stat) is intentional
  // slide layout — never fold it into surrounding text.
  if ((previous.length > 0 && /^\p{Nd}+$/u.test(previous)) ||
      (next.length > 0 && /^\p{Nd}+$/u.test(next))) {
    return false;
  }
  // Carousels: a colon-ending line introduces a list or section.
  if (isCarousel && previous.endsWith(':')) return false;

  const nextChars = Array.from(next);
  const prevChars = Array.from(previous);
  if (nextChars.length <= 3) {
    if (isCarousel && isUppercaseLetter(nextChars[0])) return false;
    return true;
  }
  if (isLowercaseLetter(nextChars[0]) && !endsSentence(previous)) return true;
  if (prevChars.length <= 14 && nextChars.length <= 14) {
    // Two short uppercase-starting lines on a carousel are separate items.
    if (isCarousel && isUppercaseLetter(prevChars[0]) && isUppercaseLetter(nextChars[0])) {
      return false;
    }
    return true;
  }
  return false;
}

/// Port of splitAtSentenceBoundaries — ". "/"! "/"? " followed by uppercase.
export function splitAtSentenceBoundaries(text: string): string[] {
  if (Array.from(text).length <= 1) return [text];
  const parts = text
    .replace(/(?<=[.!?])\s+(?=[A-Z])/g, '\n')
    .split('\n')
    .map(part => part.trim())
    .filter(part => part.length > 0);
  return parts.length === 0 ? [text] : parts;
}

function deduplicateLinesPreservingOrder(lines: string[]): string[] {
  const unique: string[] = [];
  const normalizedSeen: string[] = [];
  for (const line of lines) {
    const cleaned = line
      .replace(/\n/g, ' ')
      .replace(/\s+/g, ' ')
      .trim()
      .replace(/’/g, "'");
    if (cleaned.length === 0) continue;
    const normalized = normalizedLineKey(cleaned);
    if (normalized.length === 0) continue;

    const normalizedWords = new Set(normalized.split(' ').filter(w => w.length > 0));
    const isDuplicate = normalizedSeen.some(existing => {
      if (existing === normalized) return true;
      const existingWords = new Set(existing.split(' ').filter(w => w.length > 0));
      return jaccardSimilarity(existingWords, normalizedWords) >= 0.85;
    });
    if (!isDuplicate) {
      unique.push(cleaned);
      normalizedSeen.push(normalized);
    }
  }
  return unique;
}

const DIGIT_CONFUSABLES: Record<string, string> = {
  O: '0', o: '0', I: '1', l: '1', S: '5', s: '5', B: '8',
};

function normalizeStandaloneYearArtifacts(text: string): string {
  if (text.length === 0) return text;
  return text.replace(/\b[0-9OIlSB]{4}[^0-9A-Za-z\s]?\b/g, raw => {
    const normalized = Array.from(raw)
      .filter(ch => /[0-9A-Za-z]/.test(ch))
      .map(ch => DIGIT_CONFUSABLES[ch] ?? ch)
      .join('');
    if (normalized.length !== 4 || !/^\d{4}$/.test(normalized)) return raw;
    return normalized;
  });
}

/// Port of sanitizeSlideText — the full line pipeline: collapse whitespace,
/// drop artifacts, merge visual wraps, dedupe, and (carousels) split at
/// sentence/list boundaries so each idea sits on its own line.
export function sanitizeSlideText(text: string, isCarousel: boolean): string {
  const rawLines = text
    .split(/\r?\n/)
    .map(line => line.replace(/\s+/g, ' ').trim())
    .filter(line => line.length > 0);

  let mergedLines: string[] = [];
  for (const line of rawLines) {
    if (isLikelyArtifactLine(line)) continue;
    const last = mergedLines[mergedLines.length - 1];
    if (last !== undefined && shouldJoinLine(last, line, isCarousel)) {
      mergedLines.pop();
      const joiner = last.endsWith('-') ? '' : ' ';
      mergedLines.push((last + joiner + line).replace(/\s+/g, ' ').trim());
    } else {
      mergedLines.push(line);
    }
  }

  mergedLines = deduplicateLinesPreservingOrder(mergedLines);

  if (isCarousel) {
    mergedLines = mergedLines.flatMap(line => {
      // List items are already atomic — never split them further.
      const listPattern = /^(\d+[.)]\s|[→▸►•·\-*+]\s|--\s|#\d|Step\s)/;
      if (listPattern.test(line)) return [line];
      // Force line breaks before mid-line arrows and dash/plus list items.
      let working = line.replace(/ → /g, '\n→ ');
      working = working.replace(/(?<=\S)\s+[-+] (?=[A-Z])/g, '\n- ');
      // Split "Label: +24% Label: +26%" stat-list patterns.
      working = working.replace(/(%\s+)(?=[A-Z][a-z])/g, '%\n');
      if (working.includes('\n')) {
        return working.split('\n').map(part => part.trim()).filter(part => part.length > 0);
      }
      return splitAtSentenceBoundaries(line);
    });
  }

  const joined = mergedLines.join('\n').trim();
  return normalizeStandaloneYearArtifacts(joined);
}

/// Port of postProcessSlides for the worker's carousel/image path: sanitize
/// each slide's text (falling back to the trimmed original when sanitation
/// empties it), drop duplicate slides, renumber 1-based.
export function postProcessSlidesJSON(
  slides: TranscriptSlideJSON[],
  options: { isCarousel: boolean }
): TranscriptSlideJSON[] {
  if (slides.length === 0) return [];
  const sanitized = slides.map(slide => {
    const cleaned = sanitizeSlideText(slide.text ?? '', options.isCarousel);
    return { ...slide, text: cleaned.length > 0 ? cleaned : (slide.text ?? '').trim() };
  });
  const deduped = deduplicateSlidesJSON(sanitized);
  return deduped.map((slide, index) => ({ ...slide, slideNumber: index + 1 }));
}
