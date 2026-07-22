// Slide-text post-processing parity tests (port of the Mac's
// InstagramAutoTranscriber sanitize pipeline). Fixtures come from real field
// bugs — the July 22 "$695k portfolio" carousel whose transcript preserved
// the image's visual line wrapping and split sentences mid-thought.
// Run: npm run test:slide-text

import assert from 'node:assert/strict';
import {
  isLikelyArtifactLine,
  postProcessSlidesJSON,
  sanitizeSlideText,
  shouldJoinLine,
  splitAtSentenceBoundaries,
} from '../src/swipes/slideText';
import { TranscriptSlideJSON } from '../src/swipes/types';

function slide(text: string, n: number): TranscriptSlideJSON {
  return { id: `id-${n}`, text, slideNumber: n, source: 'geminiVision' };
}

// ── The field bug: visual wraps must merge into flowing sentences ───────────

{
  const raw = [
    '↑ RETURN',
    '$695,613.43',
    'My stockmarket portfolio',
    'made a gain of almost $700k',
    'in 12 months',
    "That's so much more",
    'than my salary',
    "That's not normal",
  ].join('\n');
  const cleaned = sanitizeSlideText(raw, true);
  const lines = cleaned.split('\n');
  assert.ok(
    lines.includes('My stockmarket portfolio made a gain of almost $700k in 12 months'),
    `wrapped sentence must merge into one line, got:\n${cleaned}`
  );
  assert.ok(
    lines.includes("That's so much more than my salary"),
    `second wrapped sentence must merge, got:\n${cleaned}`
  );
  assert.ok(
    lines.includes("That's not normal"),
    `distinct statement keeps its own line, got:\n${cleaned}`
  );
  assert.ok(
    !lines.includes('made a gain of almost $700k'),
    'no orphaned sentence fragments may survive'
  );
}

{
  const raw = [
    'I belive in financial transparency,',
    "here's how much my stock market",
    'portfolio MADE me in a year',
  ].join('\n');
  const cleaned = sanitizeSlideText(raw, true);
  assert.equal(
    cleaned,
    "I belive in financial transparency, here's how much my stock market portfolio MADE me in a year",
    'hook slide wraps join into one flowing sentence'
  );
}

// ── List structure must be preserved, never merged ──────────────────────────

{
  const raw = ['5 tools I use:', '1. Notion', '2. Figma', '→ Try it today'].join('\n');
  const cleaned = sanitizeSlideText(raw, true);
  assert.equal(
    cleaned,
    '5 tools I use:\n1. Notion\n2. Figma\n→ Try it today',
    'numbered/arrow list items stay on their own lines'
  );
}

{
  // A standalone year header is intentional layout — never folded into text.
  const raw = ['2016', 'We started a new business in sales'].join('\n');
  const cleaned = sanitizeSlideText(raw, false);
  assert.equal(cleaned, '2016\nWe started a new business in sales');
}

// ── Multi-sentence blocks split one sentence per line (carousels) ───────────

{
  const cleaned = sanitizeSlideText("I quit my job. Here's what happened next", true);
  assert.equal(cleaned, "I quit my job.\nHere's what happened next");
}

assert.deepEqual(
  splitAtSentenceBoundaries('One thing. Another thing! A third?'),
  ['One thing.', 'Another thing!', 'A third?']
);

// ── Join heuristics ─────────────────────────────────────────────────────────

assert.equal(shouldJoinLine('My stockmarket portfolio', 'made a gain of almost $700k', true), true);
assert.equal(shouldJoinLine('anti-', 'establishment ideas won', true), true);
assert.equal(shouldJoinLine('1. First item', '2. Second item', true), false);
assert.equal(shouldJoinLine('Intro line:', 'anything after', true), false);
assert.equal(shouldJoinLine('Short Label', 'Other Label', true), false, 'two short Title-case lines are separate carousel items');

// ── Artifact lines drop; digit-confusable years normalize ───────────────────

assert.equal(isLikelyArtifactLine('|||~~^^'), true);
assert.equal(isLikelyArtifactLine('Real sentence here'), false);
assert.equal(sanitizeSlideText('In 2O26 we grew', true), 'In 2026 we grew');

// ── postProcessSlidesJSON: dedup + renumber, empty slides survive ───────────

{
  const processed = postProcessSlidesJSON(
    [
      slide('Same exact closing CTA follow for more', 1),
      slide('', 2),
      slide('Same exact closing CTA follow for more', 3),
      slide('A different slide entirely about money', 4),
    ],
    { isCarousel: true }
  );
  assert.equal(processed.length, 3, 'duplicate slide folds, empty slide survives');
  assert.deepEqual(processed.map(s => s.slideNumber), [1, 2, 3], 'slides renumber 1-based');
}

{
  // The repair pass itself: wrapped raw slides come out sentence-merged.
  const processed = postProcessSlidesJSON(
    [slide('My stockmarket portfolio\nmade a gain of almost $700k\nin 12 months', 1)],
    { isCarousel: true }
  );
  assert.equal(
    processed[0].text,
    'My stockmarket portfolio made a gain of almost $700k in 12 months'
  );
}

console.log('✅ slideText tests passed');
