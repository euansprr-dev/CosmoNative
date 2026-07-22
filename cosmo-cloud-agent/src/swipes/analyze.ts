// cosmo-cloud-agent/src/swipes/analyze.ts
// The single per-swipe insight pass — a 1:1 port of the Mac's
// SwipeInsightEngine (insightVersion 4, Sonnet 5). The prompt text is
// VERBATIM from SwipeInsightEngine.buildPrompt; taxonomy value lists are the
// Swift enums' CaseIterable order. Output field names match SwipeAnalysis
// CodingKeys exactly (see types.ts header for the date/UUID encoding rules).
//
// Replaces the old v2 unified-classification port: the v4 pass produces the
// displayTitle, keyInsight, hook analysis, slide-anchored structure, taxonomy,
// and the signature card that feeds the cross-swipe PatternWeaver — the SAME
// analysis the Mac produces, so a swipe processed in the cloud opens on the
// Mac fully loaded with nothing left to compute.

import { config } from '../config';
import { fetchAllByType, createAtom, updateAtom, Atom } from '../db/queries';
import { appleSeconds, EngagementSnapshot, SpeechSegmentJSON, TranscriptSlideJSON } from './types';
import { nichePromptInstruction } from './niche';

// Mirrors SwipeInsightEngine.analysisTier (.sonnet5) — every swipe is curated;
// one premium call per capture is the budget.
const INSIGHT_MODEL = 'anthropic/claude-sonnet-5';
// Mirrors SwipeInsightEngine.insightVersion.
export const INSIGHT_VERSION = 4;

// Swift CaseIterable orders — do not reorder.
const NARRATIVE_VALUES = ['studentSuccess', 'noValue', 'lessonsLearned', 'authorityHacking', 'businessBreakdown', 'storytelling', 'fearMongering'];
const FORMAT_VALUES = ['voiceoverReel', 'oneSliderReel', 'multiSliderReel', 'twoStepCTA', 'carousel', 'tweet', 'thread', 'longForm', 'youtube', 'newsletter', 'post', 'reel'];
const FRAMEWORK_VALUES = ['aida', 'pas', 'bab', 'escalationArc', 'storyLoop', 'listicle', 'tutorial', 'caseStudy', 'interview', 'beforeAfter', 'mythBusting', 'dayInLife'];
const HOOK_TYPE_VALUES = ['curiosityGap', 'boldClaim', 'question', 'story', 'statistic', 'controversy', 'contrast', 'howTo', 'list', 'challenge', 'hiddenGem', 'contrarian', 'personal', 'transformation'];

// SwipeFrameworkType.description, verbatim.
const FRAMEWORK_DESCRIPTIONS: Record<string, string> = {
  aida: 'Attention → Interest → Desire → Action',
  pas: 'Problem → Agitate → Solve',
  bab: 'Before → After → Bridge',
  escalationArc: 'Progressive intensity build to climax',
  storyLoop: 'Setup → Conflict → Resolution',
  listicle: 'Numbered items with a unifying theme',
  tutorial: 'Step-by-step instructional format',
  caseStudy: 'Deep dive into a specific example',
  interview: 'Q&A or conversational format',
  beforeAfter: 'Contrasting two states of transformation',
  mythBusting: 'Debunking common misconceptions',
  dayInLife: 'Following a chronological personal narrative',
};

// SwipeInsightEngine.hookTypeDefinitions, verbatim.
const HOOK_TYPE_DEFINITIONS: Array<[string, string]> = [
  ['curiosityGap', 'opens a specific unanswered question the viewer must resolve ("Nobody talks about why...")'],
  ['boldClaim', 'a declarative, falsifiable assertion stated as fact ("Housing didn\'t get expensive by accident.")'],
  ['question', 'a direct question aimed at the viewer'],
  ['story', 'drops the viewer mid-narrative ("I lost the deal at 11pm on a Tuesday...")'],
  ['statistic', 'leads with a specific number or data point as the attention device'],
  ['controversy', 'takes a side on a divisive topic to provoke reaction'],
  ['contrast', 'juxtaposes two states or options ("Rich people do X. Everyone else does Y.")'],
  ['howTo', 'promises a method ("How to..." / "The exact system for...")'],
  ['list', 'promises enumerated items ("5 websites that...")'],
  ['challenge', 'dares the viewer or sets a test ("Try this for 30 days")'],
  ['hiddenGem', 'reveals something obscure or insider ("The clause nobody reads...")'],
  ['contrarian', 'inverts accepted advice ("Stop saving money.")'],
  ['personal', 'leads with the creator\'s own status or vulnerability ("I made $40K last month and I\'m terrified.")'],
  ['transformation', 'before→after change as the opener ("From evicted to 12 doors in 3 years")'],
];

// BeatPatternService.defaultVocabulary labels — the canonical beat vocabulary
// the Mac prompt teaches. The Mac also appends learned beats; the worker uses
// the stable core (labels outside it come back as "Uncategorized: X" and the
// Mac's normalizer handles them).
const CANONICAL_BEATS = [
  'BoldClaim', 'CuriosityGap', 'PersonalFailure', 'DiscoveryMoment', 'StepByStepProof',
  'SocialProofNumbers', 'BeliefReframe', 'AspirationalOutcome', 'UrgencyCTA', 'ValueStack',
  'EnemyCallout', 'ObjectionCrusher', 'StorySetup', 'EmotionalHook', 'TransitionBridge',
  'ListicleItem', 'AuthorityEstablishment', 'PainAmplification', 'SolutionReveal',
  'ComparisonContrast', 'AudienceCallout', 'FutureWarning', 'MetaphorAnalogy',
  'TestimonialQuote', 'IdentityShift', 'ScarcityTrigger', 'CommunitySignal',
].join(', ');

export interface AnalyzeContext {
  title: string;
  url: string;
  platform: string;
  author: string;
  oembedTitle: string;      // caption / oEmbed title
  sourceType: string;       // e.g. instagram_reel
  instagramType: string;    // e.g. reel / carousel
  hasVideo: boolean;
  slideCount: number;
  durationSeconds: number;
  transcriptSlides: TranscriptSlideJSON[];
  speechSegments: SpeechSegmentJSON[];
  transcriptionQuality?: string;
  transcriptionWarnings?: string[];
  text: string;             // the transcript/caption text to analyze
  canonicalNiches?: string; // usage-ordered registry values for the prompt
  engagement?: EngagementSnapshot;
}

// ── Prompt (VERBATIM port of SwipeInsightEngine.buildPrompt) ────────────────

export function buildInsightPrompt(ctx: AnalyzeContext): string {
  // Media signals
  const mediaLines: string[] = [];
  if (ctx.sourceType) mediaLines.push(`Source type: ${ctx.sourceType}`);
  if (ctx.instagramType) mediaLines.push(`Instagram type: ${ctx.instagramType}`);
  if (ctx.durationSeconds > 0) mediaLines.push(`Video duration: ${ctx.durationSeconds} seconds`);
  if (ctx.slideCount > 0) mediaLines.push(`Carousel image count: ${ctx.slideCount}`);
  if (ctx.hasVideo) mediaLines.push('Has video: yes');
  mediaLines.push(...transcriptionModalityLines(ctx));

  // Engagement signals
  const engagementLines: string[] = [];
  if (ctx.engagement?.viewsCount != null) engagementLines.push(`Views: ${ctx.engagement.viewsCount}`);
  if (ctx.engagement?.likesCount != null) engagementLines.push(`Likes: ${ctx.engagement.likesCount}`);
  if (ctx.engagement?.commentsCount != null) engagementLines.push(`Comments: ${ctx.engagement.commentsCount}`);

  // The transcript, slide-indexed so structure anchors are verifiable.
  const slides = ctx.transcriptSlides.filter(s => s.text.trim().length > 0);
  let transcriptBlock: string;
  if (slides.length > 0) {
    transcriptBlock = slides
      .map((slide, index) => {
        const provenance = slide.source === 'speechAudio' ? ' (spoken)' : '';
        return `[Slide ${index + 1}${provenance}] ${slide.text}`;
      })
      .join('\n\n');
  } else {
    const words = ctx.text.split(/ /);
    transcriptBlock = '[Slide 1] ' + words.slice(0, 4000).join(' ');
  }
  const slideCount = Math.max(slides.length, 1);

  const frameworkList = FRAMEWORK_VALUES
    .map(v => `${v}: ${FRAMEWORK_DESCRIPTIONS[v]}`)
    .join('\n');
  const hookTypeList = HOOK_TYPE_DEFINITIONS
    .map(([name, def]) => `- ${name}: ${def}`)
    .join('\n');

  return `You are a senior direct-response content analyst inside a swipe-file study tool. A creator saved this piece of short-form content because it worked; your job is to explain WHY it worked precisely enough that they could replicate the mechanics on a different topic tomorrow. Every field you return is displayed in a study interface or fed to a pattern-mining engine, so be specific, mechanical, and grounded in the actual text — never generic.

## THE CONTENT

Platform: ${ctx.platform || 'unknown'}
Creator/Author (may be a numeric ID — see creator rules): ${ctx.author}
Caption/oEmbed title: ${ctx.oembedTitle}
${mediaLines.join('\n')}
${engagementLines.length === 0 ? '' : engagementLines.join('\n')}

Transcript (${slideCount} slide${slideCount === 1 ? '' : 's'}, 1-indexed — slide 1 is the hook the viewer sees first):

${transcriptBlock}

## WHAT TO PRODUCE

### displayTitle
A short library headline for this swipe, ≤60 characters.
- NEVER include author attribution in the title. If slide 1 opens with a person's name, @handle, or credential line from a screenshotted post (e.g. "Brennan Schlagbaum, CPA @Budgetdog_ How To Retire Early…"), drop that attribution and build the title from the post's body text only ("How To Retire Early (without waiting until 60)").
- If slide 1 (after dropping any attribution) is already ≤60 characters, return it VERBATIM.
- Otherwise compress slide 1 into one headline that keeps the creator's voice and the single most specific claim. Keep concrete numbers ("$75K", "90 days") — specificity is the value. No quotation marks, no emoji, no trailing period, no editorializing ("Amazing thread about...").
- Example: slide 1 = "Housing didn't get expensive by accident. For decades, home prices ran way ahead of incomes, and now everyone wants to act surprised that young families can't buy" → displayTitle = "Housing didn't get expensive by accident".

### keyInsight
2–3 sentences explaining the MECHANISM that makes this content work — not a summary of what it says. The test: a reader should be able to apply the insight to a completely different niche. Name the specific move (e.g. "validates the audience's struggle with third-party data before offering the reframe, so the solve lands as relief instead of a lecture"), not the category ("uses social proof").

### Hook analysis (judge slide 1 / the first 3 seconds ONLY)
hookType — exactly one of:
${hookTypeList}

hookScore — 0 to 10, one decimal, anchored rubric:
- 9–10: stops the scroll cold — a specific, unresolved tension aimed at a defined audience (a number, a named enemy, a forbidden claim). Rare.
- 7–8.9: strong — specific and curiosity-driving, but the tension is familiar or the audience broad.
- 5–6.9: clear topic, generic angle — tells you WHAT it's about but gives no reason to need the answer now.
- 3–4.9: slow or self-focused opening; the viewer must be patient to find the value.
- 0–2.9: no hook — greeting, context-first ramble, or pure vibes.
hookScoreReason — one sentence citing the exact words that earn (or lose) the score.
hookMechanism — one sentence on the psychological lever (what unresolved question or identity-threat/validation it plants, and in whom).

### Structure (sections)
Segment the ENTIRE transcript into 3–8 beats, in order, covering every slide with no gaps or overlaps.
- label: use ONLY these canonical beat labels: ${CANONICAL_BEATS}. If nothing fits, use "Uncategorized: YourLabel".
- purpose: what this beat DOES to the reader (creates the gap / supplies proof / removes the objection), not what it says.
- slideStart / slideEnd: 1-based inclusive slide numbers this beat spans. Beats must be verifiable against the numbered transcript above.
- sizePercent: fraction of total content length, all sections summing to ~1.0.

frameworkType — one of the following if (and only if) the beat sequence genuinely matches; otherwise null:
${frameworkList}

structuralRecipe — a numbered, step-by-step writing recipe someone could follow to recreate this structure on a new topic. Each step: beat + approximate length + density (sparse/moderate/dense). Ground it in what THIS content actually did.

voiceMarkers — 3–5 short phrases capturing the prose voice (e.g. "second-person accusation", "data-point-per-sentence", "no hedging").

### Taxonomy
primaryNarrative and optional secondaryNarrative — from: ${NARRATIVE_VALUES.join(', ')}
- studentSuccess: A STUDENT or CLIENT success story — someone ELSE achieved a specific result (revenue, transformation, milestone). Must feature a real person's outcome, NOT generic tips. Example: "My student went from $0 to $10K/month in 90 days."
- storytelling: The creator recapping a STORY — their own journey, a client's story told narratively, or a behind-the-scenes experience. Structured as a narrative arc, not tips or analysis.
- lessonsLearned: A LISTICLE or numbered list of lessons, mistakes, or takeaways ("X things I learned", "X mistakes to avoid"). Must be structured as a list, not a single-topic deep-dive.
- authorityHacking: The HOOK references a famous person, public figure, brand, or celebrity to borrow credibility ("How Warren Buffett buys real estate").
- businessBreakdown: Analyzing or breaking down a BUSINESS MODEL, market, strategy, tool, or system — including resource lists, platform comparisons, market analysis, how-to explanations of business mechanics. "5 websites to find homes under $75K" = businessBreakdown (analyzing tools/market), NOT lessonsLearned.
- fearMongering: The hook leverages a CURRENT EVENT, alarming trend, or scary scenario for urgency ("The housing market is about to crash").
- noValue: Pure entertainment, engagement-bait, or meme content with no educational, aspirational, or strategic value.

contentType — from: ${FORMAT_VALUES.join(', ')}
- voiceoverReel: continuous video with voiceover narration (talking head or B-roll with VO).
- oneSliderReel: a reel with ONE static or slow-motion background and text overlay.
- multiSliderReel: a reel with MULTIPLE distinct visual cards in sequence. Use ONLY with clear evidence of distinct cards carrying the content — do NOT infer it from subtitle fragments or burned captions that mirror speech.
- carousel: static multi-image swipeable post (no video, no audio).
- post: a single static image (no video). NEVER use "post" for anything with video or duration > 0.
Transcription-modality guidance: voiceoverOnly ⇒ strongly prefer voiceoverReel. voiceoverPlusText ⇒ prefer voiceoverReel or oneSliderReel unless distinct visual cards are evident. On-screen text that mirrors speech = captions, not slides.

${nichePromptInstruction(ctx.canonicalNiches ?? '')}

creatorHandle / creatorName — the creator's @username and display name. The Creator/Author field above may be a numeric ID — never use a numeric ID. Look for the real @username in the transcript or caption; if none exists, return null for creatorHandle.

classificationConfidence — 0.0–1.0.

### signatureCard
A compact pattern fingerprint (≤80 words) that a pattern-mining engine will compare across many swipes WITHOUT seeing transcripts. Exact format:
"HOOK: <mechanism, 5–8 words>. BEATS: <label → label → label>. MOVES: <2–4 persuasion moves actually used>. SUBJECT: <topic, 3–5 words>. NUMBERS: <how quantification is used, or 'none'>. VOICE: <2–3 markers>."
Describe the observable moves of THIS content — not textbook framework names.

## OUTPUT

Return ONLY valid JSON, no markdown fences, exactly this shape (null for unknowable fields):
{
  "displayTitle": "...",
  "keyInsight": "...",
  "hookType": "boldClaim",
  "hookScore": 8.5,
  "hookScoreReason": "...",
  "hookMechanism": "...",
  "primaryNarrative": "businessBreakdown",
  "secondaryNarrative": null,
  "contentType": "carousel",
  "niche": "...",
  "creatorHandle": "@username",
  "creatorName": "Display Name",
  "classificationConfidence": 0.9,
  "frameworkType": "pas",
  "sections": [
    {"label": "Hook", "purpose": "...", "slideStart": 1, "slideEnd": 1, "sizePercent": 0.12},
    {"label": "PainAmplification", "purpose": "...", "slideStart": 2, "slideEnd": 4, "sizePercent": 0.4}
  ],
  "structuralRecipe": "1. ...\\n2. ...",
  "voiceMarkers": ["...", "..."],
  "signatureCard": "HOOK: ... BEATS: ... MOVES: ... SUBJECT: ... NUMBERS: ... VOICE: ..."
}`;
}

// Port of SwipeInsightEngine.transcriptionModalityLines.
function transcriptionModalityLines(ctx: AnalyzeContext): string[] {
  const lines: string[] = [];
  const nonEmpty = ctx.transcriptSlides.filter(s => s.text.trim().length > 0);
  const hasSpeech = ctx.speechSegments.length > 0;

  if (nonEmpty.length > 0 || hasSpeech) {
    const hasVisual = nonEmpty.some(s => (s.source ?? 'manual') !== 'speechAudio');
    const modality = !hasSpeech ? 'textOnly' : (hasVisual ? 'voiceoverPlusText' : 'voiceoverOnly');
    lines.push(`Inferred transcription modality: ${modality}`);
  }
  if (hasSpeech) lines.push(`Speech segment count: ${ctx.speechSegments.length}`);
  if (ctx.transcriptionQuality) lines.push(`Transcription quality: ${ctx.transcriptionQuality}`);
  if (ctx.transcriptionWarnings?.length) {
    lines.push(`Transcription warnings: ${ctx.transcriptionWarnings.join(' | ')}`);
  }
  return lines;
}

// ── LLM call + parse ────────────────────────────────────────────────────────

// Mirrors SwipeInsightResponse.
export interface InsightResponse {
  displayTitle?: string | null;
  keyInsight?: string | null;
  hookType?: string | null;
  hookScore?: number | null;
  hookScoreReason?: string | null;
  hookMechanism?: string | null;
  primaryNarrative?: string | null;
  secondaryNarrative?: string | null;
  contentType?: string | null;
  niche?: string | null;
  creatorHandle?: string | null;
  creatorName?: string | null;
  classificationConfidence?: number | null;
  frameworkType?: string | null;
  sections?: Array<{ label?: string; purpose?: string; slideStart?: number; slideEnd?: number; sizePercent?: number }> | null;
  structuralRecipe?: string | null;
  voiceMarkers?: string[] | null;
  signatureCard?: string | null;
}

export async function classify(ctx: AnalyzeContext): Promise<InsightResponse | null> {
  if (!config.openRouterApiKey || !ctx.text.trim()) return null;

  const response = await fetch(`${config.openRouterBaseUrl}/chat/completions`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${config.openRouterApiKey}`,
      'X-Title': 'CosmoOS',
    },
    body: JSON.stringify({
      model: INSIGHT_MODEL,
      messages: [{ role: 'user', content: buildInsightPrompt(ctx) }],
      // Claude Sonnet 5 runs adaptive thinking BY DEFAULT when no reasoning
      // config is sent, and max_tokens caps thinking + text COMBINED (with the
      // thinking text omitted from the response). On long transcripts the
      // model burned the entire budget thinking and returned EMPTY content
      // with finish_reason "length" — every 8+-slide swipe classified as
      // 'partial' forever. This is a structured-extraction prompt tuned for
      // no-thinking models; keep reasoning off.
      reasoning: { enabled: false },
      max_tokens: 8000,
    }),
    signal: AbortSignal.timeout(180_000),
  });
  if (!response.ok) {
    console.warn(`⚠️ insight call failed: ${response.status}`);
    return null;
  }
  const payload = await response.json() as {
    choices?: Array<{ message?: { content?: string }; finish_reason?: string }>;
  };
  const choice = payload.choices?.[0];
  const content = choice?.message?.content ?? '';
  const parsed = parseResponse(content);
  if (!parsed) {
    // Surface WHY — an empty-content "length" finish is invisible without this
    // (the July 22 partial-swipe pileup hid behind a generic failure log).
    console.warn(
      `⚠️ insight response unparseable: finish=${choice?.finish_reason ?? '?'} ` +
      `contentChars=${content.length} head=${JSON.stringify(content.slice(0, 120))}`
    );
  }
  return parsed;
}

export function parseResponse(response: string): InsightResponse | null {
  let jsonStr = response.trim();
  if (jsonStr.startsWith('```')) {
    const firstNewline = jsonStr.indexOf('\n');
    if (firstNewline >= 0) jsonStr = jsonStr.slice(firstNewline + 1);
    if (jsonStr.endsWith('```')) jsonStr = jsonStr.slice(0, -3);
    jsonStr = jsonStr.trim();
  }
  try {
    return JSON.parse(jsonStr) as InsightResponse;
  } catch {
    // Model wrapped the JSON in prose ("Here is the analysis: {...}") —
    // recover the outermost object rather than failing the whole pass.
    const start = jsonStr.indexOf('{');
    const end = jsonStr.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        return JSON.parse(jsonStr.slice(start, end + 1)) as InsightResponse;
      } catch { /* fall through */ }
    }
    return null;
  }
}

// ── Display title guardrail (port of sanitizedDisplayTitle) ────────────────

export function sanitizedDisplayTitle(raw: string | null | undefined, hook: string | null | undefined): string | null {
  const cleanedHook = hook
    ?.replace(/\n/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (cleanedHook && cleanedHook.length > 0 && cleanedHook.length <= 60) {
    return cleanedHook;
  }

  let title = raw?.trim() ?? '';
  if (!title) return null;
  const quotePairs: Array<[string, string]> = [['"', '"'], ['“', '”'], ["'", "'"]];
  let stripped = true;
  while (title.length >= 2 && stripped) {
    stripped = false;
    for (const [open, close] of quotePairs) {
      if (title.startsWith(open) && title.endsWith(close)) {
        title = title.slice(1, -1).trim();
        stripped = true;
        break;
      }
    }
  }
  title = title.replace(/\n/g, ' ').replace(/\s+/g, ' ');
  if (!title) return null;
  if (title.length > 90) {
    const cut = title.slice(0, 90);
    title = cut.includes(' ')
      ? cut.split(' ').slice(0, -1).join(' ')
      : cut;
  }
  return title || null;
}

// ── buildAnalysis port — produces SwipeAnalysis-shaped JSON (v4) ────────────

export interface BuildAnalysisInputs {
  hookText: string;   // first non-empty slide / fallback prefix — verbatim
  slideCount: number; // analyzable slide count (anchors are clamped to it)
  hasVideo: boolean;  // format sanity: video can never be a static "post"
}

export function buildAnalysisJSON(
  response: InsightResponse,
  creatorUUID: string | null,
  inputs: BuildAnalysisInputs
): Record<string, unknown> {
  const primaryNarrative = enumOrNull(response.primaryNarrative, NARRATIVE_VALUES);
  const secondaryNarrative = enumOrNull(response.secondaryNarrative, NARRATIVE_VALUES);
  let contentFormat = enumOrNull(response.contentType, FORMAT_VALUES);
  const frameworkType = enumOrNull(response.frameworkType, FRAMEWORK_VALUES);
  const hookType = enumOrNull(response.hookType, HOOK_TYPE_VALUES);

  const sections = (response.sections ?? [])
    .map((s, index) => {
      const label = (s.label ?? '').trim();
      const effectiveLabel = label || (s.purpose ?? '').slice(0, 30).trim();
      if (!effectiveLabel) return null;
      // Clamp slide anchors to the actual slide range; drop nonsense.
      let slideStart = typeof s.slideStart === 'number' ? s.slideStart : null;
      let slideEnd = typeof s.slideEnd === 'number' ? s.slideEnd : null;
      if (inputs.slideCount > 0) {
        if (slideStart != null) slideStart = Math.min(Math.max(slideStart, 1), inputs.slideCount);
        if (slideEnd != null) slideEnd = Math.min(Math.max(slideEnd, slideStart ?? 1), inputs.slideCount);
      } else {
        slideStart = null;
        slideEnd = null;
      }
      const section: Record<string, unknown> = {
        label: effectiveLabel,
        startIndex: index,
        endIndex: index + 1,
        purpose: s.purpose ?? '',
      };
      if (typeof s.sizePercent === 'number') section.sizePercent = s.sizePercent;
      if (slideStart != null) section.slideStart = slideStart;
      if (slideEnd != null) section.slideEnd = slideEnd;
      return section;
    })
    .filter((s): s is Record<string, unknown> => s !== null);

  // Format sanity: Instagram video can never be a static "post".
  if ((contentFormat === 'post' || contentFormat === null) && inputs.hasVideo) {
    contentFormat = 'multiSliderReel';
  }

  const analysis: Record<string, unknown> = {
    analysisVersion: INSIGHT_VERSION,
    analyzedAt: new Date().toISOString(),
    isFullyAnalyzed: true,
    classificationSource: 'ai',
    classifiedAt: appleSeconds(new Date()),
  };
  if (inputs.hookText) {
    analysis.hookText = inputs.hookText;
    analysis.hookWordCount = inputs.hookText.split(/ /).filter(Boolean).length;
  }
  if (hookType) analysis.hookType = hookType;
  if (response.hookScore != null) analysis.hookScore = Math.min(Math.max(response.hookScore, 0), 10);
  if (response.hookScoreReason) analysis.hookScoreReason = response.hookScoreReason;
  if (response.hookMechanism) analysis.hookMechanism = response.hookMechanism;
  if (frameworkType) analysis.frameworkType = frameworkType;
  if (sections.length) analysis.sections = sections;
  if (response.keyInsight) analysis.keyInsight = response.keyInsight;
  if (response.structuralRecipe) analysis.structuralRecipe = response.structuralRecipe;
  if (response.voiceMarkers?.length) analysis.voiceMarkers = response.voiceMarkers;
  if (primaryNarrative) analysis.primaryNarrative = primaryNarrative;
  if (secondaryNarrative) analysis.secondaryNarrative = secondaryNarrative;
  if (contentFormat) analysis.swipeContentFormat = contentFormat;
  if (response.niche) analysis.niche = response.niche;
  if (creatorUUID) analysis.creatorUUID = creatorUUID;
  if (response.classificationConfidence != null) analysis.classificationConfidence = response.classificationConfidence;
  const displayTitle = sanitizedDisplayTitle(response.displayTitle, inputs.hookText);
  if (displayTitle) analysis.displayTitle = displayTitle;
  const signatureCard = response.signatureCard?.trim();
  if (signatureCard) analysis.signatureCard = signatureCard;
  return analysis;
}

// ── Creator resolution (handle fallback + find-or-create + linking) ────────

export function normalizeCreatorHandle(
  aiHandle: string | null | undefined,
  aiName: string | null | undefined,
  oembedAuthor: string
): { handle: string | null; name: string | null } {
  let handle = aiHandle ?? null;
  let name = aiName ?? null;

  const isNumericHandle = handle != null && /^[0-9]+$/.test(handle.replace(/@/g, ''));
  if ((handle == null || isNumericHandle) && oembedAuthor && !/^[0-9]+$/.test(oembedAuthor)) {
    const base = (oembedAuthor.split('|')[0] ?? oembedAuthor).trim();
    handle = '@' + base.toLowerCase().replace(/ /g, '_').replace(/[^a-z0-9_.]/g, '');
    name = name ?? base;
  }
  if (handle != null && /^[0-9]+$/.test(handle.replace(/@/g, ''))) return { handle: null, name };
  if (handle != null && !handle.startsWith('@')) handle = `@${handle}`;
  if (handle === '@') handle = null;
  return { handle, name };
}

export async function resolveCreator(
  handle: string | null,
  name: string | null,
  swipe: Atom,
  platform: string
): Promise<string | null> {
  if (!handle) return null;

  try {
    const creators = await fetchAllByType('creator', { limit: 500 });
    const match = creators.find(c => {
      const metaHandle = (c.metadata?.handle as string | undefined) ?? '';
      return metaHandle.toLowerCase() === handle.toLowerCase();
    });

    let creatorUUID: string;
    if (match) {
      creatorUUID = match.uuid;
    } else {
      const created = await createAtom({
        type: 'creator',
        title: name ?? handle,
        metadata: { handle, platform, swipeCount: 0, isActive: true },
      });
      if (!created) return null;
      creatorUUID = created.uuid;
    }

    // Bidirectional links — updateAtom appends+dedupes links.
    await updateAtom(swipe.uuid, { links: [{ type: 'swipe_to_creator', uuid: creatorUUID }] });
    await updateAtom(creatorUUID, { links: [{ type: 'creator_to_swipe', uuid: swipe.uuid }] });
    return creatorUUID;
  } catch (error) {
    console.warn('⚠️ creator resolution failed:', error instanceof Error ? error.message : error);
    return null;
  }
}

// ── helpers ────────────────────────────────────────────────────────────────

function enumOrNull(value: string | null | undefined, allowed: string[]): string | null {
  return value != null && allowed.includes(value) ? value : null;
}

export interface EngagementFields {
  likesCount?: number;
  viewsCount?: number;
  commentsCount?: number;
  sharesCount?: number;
  engagementRate?: number;
  publishedAt?: number;    // Apple reference-date seconds
  postShortcode?: string;
}

export function engagementFields(
  engagement: EngagementSnapshot,
  publishedAtISO: string | undefined,
  shortcode: string | undefined
): EngagementFields {
  const fields: EngagementFields = {};
  if (engagement.likesCount != null) fields.likesCount = engagement.likesCount;
  if (engagement.viewsCount != null) fields.viewsCount = engagement.viewsCount;
  if (engagement.commentsCount != null) fields.commentsCount = engagement.commentsCount;
  if (engagement.sharesCount != null) fields.sharesCount = engagement.sharesCount;
  const views = engagement.viewsCount ?? 0;
  if (views > 0) {
    fields.engagementRate = ((engagement.likesCount ?? 0) + (engagement.commentsCount ?? 0)) / views * 100;
  }
  if (publishedAtISO) {
    const parsed = new Date(publishedAtISO);
    if (!Number.isNaN(parsed.getTime())) fields.publishedAt = appleSeconds(parsed);
  }
  if (shortcode) fields.postShortcode = shortcode;
  return fields;
}
