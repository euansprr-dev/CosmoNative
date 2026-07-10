// Swipe worker unit tests: Apify item mapping, analysis JSON contract
// (field names must match Swift SwipeAnalysis CodingKeys), engagement math,
// creator handle normalization, and helper parsing.
// Run: npx tsx tests/swipeWorker.test.ts

import assert from 'node:assert/strict';
import { mapApifyItem, instagramShortcode } from '../src/swipes/instagram';
import { buildAnalysisJSON, engagementFields, normalizeCreatorHandle, parseResponse } from '../src/swipes/analyze';
import { appleSeconds, APPLE_EPOCH_OFFSET } from '../src/swipes/types';
import { youtubeVideoId } from '../src/swipes/fetchers';

// ── Apify item mapping: reel ────────────────────────────────────────────────

const reel = mapApifyItem({
  type: 'Video',
  productType: 'clips',
  shortCode: 'DaQ5qGXo2zA',
  caption: 'Trump just changed the SBA rules…',
  ownerUsername: 'somecreator',
  ownerFullName: 'Some Creator',
  timestamp: '2026-07-03T10:00:00.000Z',
  videoUrl: 'https://cdn.example/video.mp4',
  displayUrl: 'https://cdn.example/thumb.jpg',
  likesCount: 4800,
  commentsCount: 312,
  videoViewCount: 1_200_000,
});
assert.equal(reel.contentType, 'reel');
assert.equal(reel.videoUrl, 'https://cdn.example/video.mp4');
assert.equal(reel.thumbnailUrl, 'https://cdn.example/thumb.jpg');
assert.equal(reel.engagement.likesCount, 4800);
assert.equal(reel.engagement.viewsCount, 1_200_000);
assert.equal(reel.shortcode, 'DaQ5qGXo2zA');
assert.equal(reel.slides.length, 0);

// ── Apify item mapping: sidecar (carousel with a video slide) ───────────────

const sidecar = mapApifyItem({
  type: 'Sidecar',
  shortCode: 'CAROUSEL1',
  caption: 'Five lessons',
  ownerUsername: 'carouselqueen',
  childPosts: [
    { type: 'Image', displayUrl: 'https://cdn.example/s0.jpg' },
    { type: 'Video', videoUrl: 'https://cdn.example/s1.mp4', displayUrl: 'https://cdn.example/s1.jpg' },
    { type: 'Image', displayUrl: 'https://cdn.example/s2.jpg' },
  ],
  likesCount: 100,
});
assert.equal(sidecar.contentType, 'carousel');
assert.equal(sidecar.slides.length, 3);
assert.deepEqual(sidecar.slides[1], {
  index: 1,
  mediaUrl: 'https://cdn.example/s1.mp4',
  thumbnailUrl: 'https://cdn.example/s1.jpg',
  isVideo: true,
});
assert.equal(sidecar.slides[0].isVideo, false);

// ── Analysis JSON contract: keys must match SwipeAnalysis CodingKeys ────────

const classification = parseResponse(`\`\`\`json
{
  "primaryNarrative": "storytelling",
  "contentType": "voiceoverReel",
  "niche": "SMB Acquisition",
  "creatorHandle": "@buyer",
  "classificationConfidence": 0.9,
  "frameworkType": "pas",
  "sections": [{"label": "Hook", "purpose": "Opens the gap", "sizePercent": 0.1, "emotion": "curiosity"}],
  "emotionalArc": [{"position": 0, "emotion": "curiosity", "intensity": 0.8}],
  "persuasionTechniques": [{"type": "authority", "intensity": 0.7, "example": "SBA rules"}],
  "hookScore": 8.5,
  "hookScoreReason": "Newsjack",
  "keyInsight": "Newsjacking works",
  "hookMechanism": "Curiosity",
  "structuralRecipe": "1. Hook",
  "voiceMarkers": ["direct"],
  "sentimentQuartiles": [0.1, 0.2, 0.3, 0.4],
  "intensityQuartiles": [0.5, 0.5, 0.5, 0.5]
}
\`\`\``);
assert.ok(classification, 'fenced JSON must parse');

const analysis = buildAnalysisJSON(classification!, 'CREATOR-UUID');
// Exact SwipeAnalysis CodingKeys (Swift; duplicated Mac<->iOS):
for (const key of [
  'hookScore', 'frameworkType', 'sections', 'dominantEmotion', 'emotionalArc',
  'persuasionTechniques', 'persuasionStack', 'keyInsight', 'fingerprint',
  'hookScoreReason', 'analysisVersion', 'analyzedAt', 'isFullyAnalyzed',
  'primaryNarrative', 'swipeContentFormat', 'niche', 'creatorUUID',
  'classifiedAt', 'classificationSource', 'classificationConfidence',
  'hookMechanism', 'structuralRecipe', 'voiceMarkers',
]) {
  assert.ok(key in analysis, `missing SwipeAnalysis key: ${key}`);
}
assert.equal(analysis.swipeContentFormat, 'voiceoverReel'); // contentType → swipeContentFormat
assert.equal(analysis.classificationSource, 'ai');
assert.equal(analysis.dominantEmotion, 'curiosity');
// classifiedAt is a NUMBER in Apple reference-date seconds (plain JSONDecoder).
assert.equal(typeof analysis.classifiedAt, 'number');
assert.ok((analysis.classifiedAt as number) < Date.now() / 1000, 'classifiedAt must be apple-epoch, not unix');
// fingerprint techniqueWeights: 12 values in PersuasionType order, authority = index 3.
const fingerprint = analysis.fingerprint as { techniqueWeights: number[] };
assert.equal(fingerprint.techniqueWeights.length, 12);
assert.equal(fingerprint.techniqueWeights[3], 0.7);
// sections carry startIndex/endIndex ints (Swift SwipeSection contract).
const section = (analysis.sections as Array<Record<string, unknown>>)[0];
assert.equal(section.startIndex, 0);
assert.equal(section.endIndex, 1);

// ── Engagement fields ───────────────────────────────────────────────────────

const engagement = engagementFields(
  { likesCount: 100, commentsCount: 20, viewsCount: 1000 },
  '2026-07-03T10:00:00.000Z',
  'ABC123'
);
assert.equal(engagement.engagementRate, 12); // (100+20)/1000*100
assert.equal(engagement.postShortcode, 'ABC123');
assert.equal(typeof engagement.publishedAt, 'number');
assert.ok(Math.abs(engagement.publishedAt! - (Date.parse('2026-07-03T10:00:00.000Z') / 1000 - APPLE_EPOCH_OFFSET)) < 1);

// ── Creator handle normalization (numeric-ID fallback rules) ────────────────

assert.deepEqual(
  normalizeCreatorHandle('@real_handle', 'Real Name', 'whatever'),
  { handle: '@real_handle', name: 'Real Name' }
);
// numeric AI handle → derive from oEmbed author
assert.deepEqual(
  normalizeCreatorHandle('@63181063998', null, 'Ben Allgeyer | Real Estate Investor'),
  { handle: '@ben_allgeyer', name: 'Ben Allgeyer' }
);
// numeric author too → no creator
assert.equal(normalizeCreatorHandle(null, null, '12345').handle, null);

// ── URL helpers ─────────────────────────────────────────────────────────────

assert.equal(instagramShortcode('https://www.instagram.com/reel/DaQ5qGXo2zA/?igsh=x'), 'DaQ5qGXo2zA');
assert.equal(instagramShortcode('https://www.instagram.com/p/ABC_12-3/'), 'ABC_12-3');
assert.equal(instagramShortcode('https://example.com/'), null);
assert.equal(youtubeVideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
assert.equal(youtubeVideoId('https://youtu.be/dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
assert.equal(youtubeVideoId('https://www.youtube.com/shorts/abcdefghijk'), 'abcdefghijk');

// ── appleSeconds sanity ─────────────────────────────────────────────────────

assert.equal(appleSeconds(new Date('2001-01-01T00:00:00Z')), 0);

console.log('✅ swipeWorker tests passed');

// ── Reel pipeline: dedup, batch merge, modality arbitration ─────────────────

import {
  areDuplicateSlideTexts, deduplicateSlides, detectContentType, joinVisualLineBreaks,
  mergeGeminiBatchResults, mergeGeminiWithSpeech, normalizedLineKey, parseGeminiSlides,
  parseCleanedSlides,
} from '../src/swipes/reelPipeline';

// normalizedLineKey matches the Mac's regex behavior
assert.equal(normalizedLineKey("It’s 100% TRUE — really!"), "it's 100% true really");

// joinVisualLineBreaks: year headers stay on their own line, body joins
assert.equal(joinVisualLineBreaks('2016\nWe started\na new business'), '2016\nWe started a new business');
assert.equal(joinVisualLineBreaks('First line\nsecond line'), 'First line second line');

// duplicate detection: exact, near (≥0.92 jaccard), and containment (≥0.90)
assert.ok(areDuplicateSlideTexts('Buy your first business', 'buy your FIRST business!'));
assert.ok(areDuplicateSlideTexts('Step one: find the deal', 'Step one: find the deal today'));
assert.ok(!areDuplicateSlideTexts('Step one: find the deal', 'Step two: negotiate the price'));

// batch-boundary dedup: the same slide seen at the end of batch 1 and start
// of batch 2 merges into ONE slide with the union of timestamps
const batch1 = [
  { text: 'Hook: he bought a laundromat', slideNumber: 1, timestamp: 0, endTimestamp: 4.5, source: 'geminiVision' },
];
const batch2 = [
  { text: 'Hook: he bought a laundromat', slideNumber: 1, timestamp: 4.75, endTimestamp: 5.0, source: 'geminiVision' },
  { text: 'Step 2: seller financing', slideNumber: 2, timestamp: 5.25, endTimestamp: 8.0, source: 'geminiVision' },
];
const mergedBatches = mergeGeminiBatchResults([batch1, batch2]);
assert.equal(mergedBatches.length, 2, 'boundary duplicate must merge');
assert.equal(mergedBatches[0].endTimestamp, 5.0);
assert.equal(mergedBatches[1].slideNumber, 2);

// non-consecutive duplicates collapse too (global dedup)
const withRepeat = deduplicateSlides([
  { text: 'Slide A text here', slideNumber: 1 },
  { text: 'Slide B other text', slideNumber: 2 },
  { text: 'slide a TEXT here', slideNumber: 3 },
]);
assert.equal(withRepeat.length, 2);

// MUSIC GUARD: sparse repetitive lyrics over a 10-slide text reel → textOnly,
// lyrics never become the transcript
const slideBodies = [
  'In 2016 I was broke and sleeping on my brother\'s couch in Ohio',
  'A mentor told me boring businesses print money while startups burn it',
  'So I cold-called forty laundromat owners over one weekend',
  'One of them wanted to retire and had zero buyers lined up',
  'We agreed on ninety percent seller financing at five percent interest',
  'The machines were old but the location sat next to two dorms',
  'Monthly revenue was eleven thousand with basically no marketing',
  'I raised prices by fifty cents and added a wash-and-fold service',
  'Cash flow doubled within eight months and paid the note early',
  'Today that single deal funds every new acquisition I make',
];
const textSlides = slideBodies.map((text, i) => ({
  text,
  slideNumber: i + 1,
  timestamp: i * 3,
  endTimestamp: i * 3 + 2.8,
  source: 'geminiVision',
}));
const lyrics = [
  { text: 'oh na na', timestamp: 1, duration: 1.2 },
  { text: 'oh na na', timestamp: 6, duration: 1.2 },
  { text: 'yeah yeah', timestamp: 12, duration: 1.0 },
];
assert.equal(detectContentType(textSlides, lyrics, 30), 'textOnly');
const musicMerge = mergeGeminiWithSpeech(textSlides, lyrics, 30);
assert.equal(musicMerge.contentType, 'textOnly');
assert.equal(musicMerge.slides.length, 10, 'all 10 text slides survive');
assert.ok(!musicMerge.slides.some(s => s.text.includes('oh na na')), 'lyrics never enter slides');

// VOICEOVER GUARD: dense narration mirrored by burned captions → voiceoverOnly,
// one speech slide, caption fragments do not become fake slides
const captionFragments = Array.from({ length: 30 }, (_, i) => ({
  text: ['so I bought', 'a laundromat', 'with seller financing', 'and cash flow'][i % 4],
  slideNumber: i + 1,
  timestamp: i * 0.9,
  endTimestamp: i * 0.9 + 0.85,
  source: 'geminiVision',
}));
const narration = Array.from({ length: 12 }, (_, i) => ({
  text: 'so I bought a laundromat with seller financing and it cash flows four thousand a month which is amazing honestly',
  timestamp: i * 2.4,
  duration: 2.3,
}));
assert.equal(detectContentType(captionFragments, narration, 28), 'voiceoverOnly');
const voMerge = mergeGeminiWithSpeech(captionFragments, narration, 28);
assert.equal(voMerge.slides.length, 1, 'voiceover reels read as ONE transcript slide');
assert.equal(voMerge.slides[0].source, 'speechAudio');

// DISTINCT slides + real narration → voiceoverPlusText with [Voiceover:] annotations
const authoredBodies = [
  'Hook: the bank said no so the seller became the bank instead',
  'Deal criteria: profitable ten years running with an owner past sixty',
  'Financing structure: small down payment then monthly payments from profit',
  'Due diligence: read the tax returns not the listing brochure',
  'Closing move: keep the manager and give them equity upside',
];
const authoredSlides = authoredBodies.map((text, i) => ({
  text,
  slideNumber: i + 1,
  timestamp: i * 5,
  endTimestamp: i * 5 + 4.5,
  source: 'geminiVision',
}));
const narrationBodies = [
  'let me walk you through why this strategy beats venture capital entirely',
  'most brokers will never show you these listings because commissions are tiny',
  'your lawyer drafts the note and the amortization schedule protects both sides',
  'ask for the last three years of returns and match deposits to revenue',
  'people run businesses and keeping the operator happy is the whole game',
];
const distinctNarration = narrationBodies.map((text, i) => ({
  text,
  timestamp: i * 5 + 0.5,
  duration: 4,
}));
const vptMerge = mergeGeminiWithSpeech(authoredSlides, distinctNarration, 25);
assert.equal(vptMerge.contentType, 'voiceoverPlusText');
assert.equal(vptMerge.slides.length, 5, 'slide structure preserved');
assert.ok(vptMerge.slides[0].text.includes('[Voiceover:'), 'distinct speech annotates slides');

// Gemini response parsing: fenced JSON with frame→timestamp mapping
const parsed = parseGeminiSlides(
  '```json\n{"slides":[{"text":"2016\\nWe started a business","startFrame":0,"endFrame":3},{"text":"2020\\nWe sold it","startFrame":4,"endFrame":7}]}\n```',
  [0, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75]
);
assert.equal(parsed.length, 2);
assert.equal(parsed[0].timestamp, 0);
assert.equal(parsed[0].endTimestamp, 0.75);
assert.equal(parsed[0].text, '2016\nWe started a business');
assert.equal(parsed[1].timestamp, 1.0);

// Cleanup response parsing preserves slide count contract
assert.deepEqual(
  parseCleanedSlides('{"slides":[{"index":2,"text":"b"},{"index":1,"text":"a"}]}', 2),
  ['a', 'b']
);
assert.equal(parseCleanedSlides('{"slides":[{"index":1,"text":"only one"}]}', 2), null);

console.log('✅ reelPipeline tests passed');

// ── Reel V3: video-understanding parsing, escalation, annotation ────────────

import { parseVideoUnderstanding, shouldEscalateToFrames } from '../src/swipes/reelVideoUnderstanding';
import { annotateSlidesWithVoiceover, deduplicateSlidesJSON } from '../src/swipes/reelPipeline';

// fenced JSON + full schema parses
const vu = parseVideoUnderstanding(`\`\`\`json
{
  "modality": "textOnly",
  "audioIsMusic": true,
  "visualTextDensity": "dense",
  "slides": [
    {"text": "2016\\nI was broke in Ohio", "startSec": 0, "endSec": 3.5},
    {"text": "A mentor changed everything", "startSec": 3.5, "endSec": 7}
  ],
  "speechTranscript": []
}
\`\`\``, 'gemini');
assert.ok(vu);
assert.equal(vu!.modality, 'textOnly');
assert.equal(vu!.audioIsMusic, true);
assert.equal(vu!.slides.length, 2);
assert.equal(vu!.slides[0].endSec, 3.5);
assert.equal(vu!.tier, 'gemini');

// invalid modality → reject (forces tier fallback rather than bad data)
assert.equal(parseVideoUnderstanding('{"modality":"weird","slides":[],"speechTranscript":[]}', 'gemini'), null);
// garbage → null
assert.equal(parseVideoUnderstanding('sorry, I cannot help with that', 'openrouter'), null);

// escalation: tier-2 (1fps) saying "dense text" but finding <3 slides is suspect
assert.ok(shouldEscalateToFrames({
  modality: 'textOnly', audioIsMusic: true, visualTextDensity: 'dense',
  slides: [{ text: 'only one', startSec: 0, endSec: 2 }], speechTranscript: [], tier: 'openrouter',
}));
// same result from tier-1 (4fps) is trusted
assert.ok(!shouldEscalateToFrames({
  modality: 'textOnly', audioIsMusic: true, visualTextDensity: 'dense',
  slides: [{ text: 'only one', startSec: 0, endSec: 2 }], speechTranscript: [], tier: 'gemini',
}));
// sparse-text reels with few slides are fine on tier 2
assert.ok(!shouldEscalateToFrames({
  modality: 'voiceoverOnly', audioIsMusic: false, visualTextDensity: 'none',
  slides: [], speechTranscript: [{ startSec: 0, endSec: 3, text: 'hello' }], tier: 'openrouter',
}));

// JSON-level dedup wrapper: duplicates collapse, ids/numbering stay coherent
const dedupJSON = deduplicateSlidesJSON([
  { id: 'a', text: 'Buy the boring business', slideNumber: 1, timestamp: 0, endTimestamp: 2, source: 'geminiVision' },
  { id: 'b', text: 'buy the BORING business', slideNumber: 2, timestamp: 2, endTimestamp: 4, source: 'geminiVision' },
  { id: 'c', text: 'Then hire an operator', slideNumber: 3, timestamp: 4, endTimestamp: 6, source: 'geminiVision' },
]);
assert.equal(dedupJSON.length, 2);
assert.equal(dedupJSON[1].slideNumber, 2);

// [Voiceover:] annotation reuses V2's distinctness rule at the JSON level
const annotated = annotateSlidesWithVoiceover(
  [{ id: 'x', text: 'Deal criteria: ten years profitable', slideNumber: 1, timestamp: 0, endTimestamp: 5, source: 'geminiVision' }],
  [{ start: 0.5, end: 4.5, text: 'most brokers hide these listings because the commissions are tiny' }]
);
assert.ok(annotated[0].text.includes('[Voiceover:'), 'distinct narration annotates the slide');
const mirrored = annotateSlidesWithVoiceover(
  [{ id: 'y', text: 'ten years profitable with an owner past sixty', slideNumber: 1, timestamp: 0, endTimestamp: 5, source: 'geminiVision' }],
  [{ start: 0.5, end: 4.5, text: 'ten years profitable with an owner past sixty' }]
);
assert.ok(!mirrored[0].text.includes('[Voiceover:'), 'mirrored speech never annotates');

console.log('✅ reelVideoUnderstanding tests passed');

// ── Worker scope: candidates and processSwipe must agree ────────────────────

import { inWorkerScope, SwipeExtractionError } from '../src/swipes/types';

assert.ok(inWorkerScope('https://www.instagram.com/p/Dalun2ODxrf/', 'instagram_post'));
assert.ok(inWorkerScope('https://youtu.be/NgeyFln7RGk?si=x', 'youtube'));
assert.ok(inWorkerScope('https://www.youtube.com/watch?v=abc123', ''));
assert.ok(inWorkerScope('https://x.com/user/status/1', ''), 'bare x.com is in scope');
assert.ok(inWorkerScope('https://twitter.com/user/status/1', 'twitter'));
assert.ok(!inWorkerScope('https://example.com/article', 'website'), 'websites stay with the Mac');
assert.ok(!inWorkerScope('https://www.tiktok.com/@u/video/1', 'tiktok'), 'tiktok stays with the Mac');
assert.ok(inWorkerScope('', 'instagram_post'), 'contentSource alone qualifies (URL may live in structured.sourceUrl)');

console.log('✅ worker scope tests passed');

// YouTube videos without captions fail PERMANENTLY (no retry churn)
import { fetchYouTubeTranscript } from '../src/swipes/fetchers';
void (async () => {
  const realFetch = globalThis.fetch;
  globalThis.fetch = (async () => new Response('<html>no captions here</html>', { status: 200 })) as typeof fetch;
  try {
    await assert.rejects(
      () => fetchYouTubeTranscript('dQw4w9WgXcQ'),
      (err: unknown) => err instanceof SwipeExtractionError && err.permanent === true,
      'caption-less video must throw a permanent SwipeExtractionError'
    );
    console.log('✅ permanent-failure test passed');
  } finally {
    globalThis.fetch = realFetch;
  }
})().catch(err => {
  console.error(err);
  process.exit(1);
});
