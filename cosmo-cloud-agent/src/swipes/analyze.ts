// cosmo-cloud-agent/src/swipes/analyze.ts
// Unified taxonomy classification + deep structural analysis — a 1:1 port of
// the Mac's SwipeClassificationEngine (buildUnifiedPrompt / parseResponse /
// buildAnalysis). The prompt text is VERBATIM; taxonomy value lists are the
// Swift enums' CaseIterable order. Output field names match SwipeAnalysis
// CodingKeys exactly (see types.ts header for the date/UUID encoding rules).

import { config } from '../config';
import { fetchAllByType, createAtom, updateAtom, Atom } from '../db/queries';
import { appleSeconds, EngagementSnapshot, SpeechSegmentJSON, TranscriptSlideJSON } from './types';

const CLASSIFICATION_MODEL = 'google/gemini-3-flash-preview';
const SCHEMA_VERSION = 1; // SwipeClassificationEngine.currentSchemaVersion

// Swift CaseIterable orders — do not reorder.
const NARRATIVE_VALUES = ['studentSuccess', 'noValue', 'lessonsLearned', 'authorityHacking', 'businessBreakdown', 'storytelling', 'fearMongering'];
const FORMAT_VALUES = ['voiceoverReel', 'oneSliderReel', 'multiSliderReel', 'twoStepCTA', 'carousel', 'tweet', 'thread', 'longForm', 'youtube', 'newsletter', 'post', 'reel'];
const FRAMEWORK_VALUES = ['aida', 'pas', 'bab', 'escalationArc', 'storyLoop', 'listicle', 'tutorial', 'caseStudy', 'interview', 'beforeAfter', 'mythBusting', 'dayInLife'];
const EMOTION_VALUES = ['curiosity', 'urgency', 'aspiration', 'fear', 'desire', 'awe', 'frustration', 'relief', 'belonging', 'exclusivity'];
const PERSUASION_VALUES = ['socialProof', 'curiosityGap', 'contrastEffect', 'authority', 'scarcity', 'urgency', 'reciprocity', 'storytelling', 'lossAversion', 'exclusivity', 'anchoring', 'framing'];

export interface AnalyzeContext {
  title: string;
  url: string;
  platform: string;
  author: string;
  oembedTitle: string;
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
}

// ── Prompt (VERBATIM port of buildUnifiedPrompt) ────────────────────────────

export function buildUnifiedPrompt(ctx: AnalyzeContext): string {
  const truncated = ctx.text.split(/ /).slice(0, 4000).join(' ');

  let mediaContext = '';
  if (ctx.sourceType) mediaContext += `Source Type: ${ctx.sourceType}\n`;
  if (ctx.instagramType) mediaContext += `Instagram Type: ${ctx.instagramType}\n`;
  if (ctx.durationSeconds > 0) mediaContext += `Duration: ${ctx.durationSeconds} seconds\n`;
  if (ctx.slideCount > 0) mediaContext += `Carousel/Slide Count: ${ctx.slideCount}\n`;
  if (ctx.hasVideo) mediaContext += 'Has Video: yes\n';
  mediaContext += transcriptionContext(ctx);

  return `You are a content intelligence analyst. Analyze this content and return a single JSON object that covers BOTH taxonomy classification AND structural analysis.

Title: ${ctx.title || 'Untitled'}
URL: ${ctx.url}
Platform: ${ctx.platform}
Creator/Author: ${ctx.author}
oEmbed Title: ${ctx.oembedTitle}
${mediaContext}
Transcript (first 4000 words): ${truncated}

## Taxonomy Classification
Classify the content across these dimensions:

Narrative Styles (pick primary and optional secondary): ${NARRATIVE_VALUES.join(', ')}
- studentSuccess: A STUDENT or CLIENT success story — someone ELSE achieved a specific result (revenue, transformation, milestone). Must feature a real person's outcome, NOT generic tips. Example: "My student went from $0 to $10K/month in 90 days."
- storytelling: The creator recapping a STORY — their own journey, a client's story told narratively, or a behind-the-scenes experience. The content is structured as a narrative arc, not tips or analysis.
- lessonsLearned: A LISTICLE or numbered list of lessons, mistakes, or takeaways. The format is "X things I learned" or "X mistakes to avoid." Must be structured as a list, not a single topic deep-dive.
- authorityHacking: The HOOK or opening references a famous person, public figure, brand, or celebrity to borrow credibility. Example: "How Warren Buffett buys real estate" or "The strategy Hormozi uses to..."
- businessBreakdown: Analyzing, explaining, or breaking down a BUSINESS MODEL, market, strategy, tool, or system. Includes resource lists, platform comparisons, market analysis, how-to explanations of business mechanics. Example: "5 websites to find homes under $75K" = businessBreakdown (analyzing tools/market), NOT lessonsLearned.
- fearMongering: The hook leverages a CURRENT EVENT, alarming trend, or scary scenario to grab attention. Creates urgency through fear or concern. Example: "The housing market is about to crash" or "This new law will destroy your business."
- noValue: Pure entertainment, engagement-bait, or meme content with no educational, aspirational, or strategic value.
Content Formats: ${FORMAT_VALUES.join(', ')}
- voiceoverReel: A single continuous video with voiceover narration (talking head, B-roll with VO)
- oneSliderReel: A reel with ONE static or slow-motion background image/clip and text overlay
- multiSliderReel: A reel with MULTIPLE distinct visual slides/cards shown in sequence (timed text cards, image transitions). Use this ONLY when the video clearly contains unique visual cards carrying the content. Do NOT infer multiSliderReel from subtitle fragments, burned captions, or talking-head captions that mirror speech.
- carousel: Static multi-image swipeable post (NO video, NO audio)
- post: A single static image post (NO video). Only use this for truly static single-image content.
- reel: Generic short-form video (use a more specific reel type if possible)
IMPORTANT: If the content has VIDEO (duration > 0 seconds) and is from Instagram, it is a REEL format (voiceoverReel, oneSliderReel, or multiSliderReel), NEVER "post". "post" is ONLY for static images with no video.
IMPORTANT TRANSCRIPTION GUIDANCE:
- If inferred transcription modality is voiceoverOnly, strongly prefer voiceoverReel.
- If inferred transcription modality is voiceoverPlusText, prefer voiceoverReel or oneSliderReel unless there is clear evidence of distinct visual cards.
- If speech segments exist but on-screen text largely mirrors the speech, treat that as captions/subtitles, not multi-slider structure.
- Music lyrics, chant-like repetition, or sparse repeated speech should NOT by themselves force voiceoverReel.
Niche: A short label for the content vertical (e.g., "Real Estate Wholesaling", "Fitness", "SaaS Marketing")
Creator: Extract the creator's @username handle and display name. IMPORTANT: The Creator/Author field above may contain a numeric ID (e.g. "63181063998") — do NOT use this. Instead, look for the actual @username in the transcript text, captions, or any visible mentions. If no real username is found, return null for creatorHandle.

## Structural Analysis
Also provide deep structural analysis:

Frameworks: ${FRAMEWORK_VALUES.join(', ')}
Valid emotions: curiosity, urgency, aspiration, fear, desire, awe, frustration, relief, belonging, exclusivity
Valid persuasion types: socialProof, curiosityGap, contrastEffect, authority, scarcity, urgency, reciprocity, storytelling, lossAversion, exclusivity, anchoring, framing

Return ONLY valid JSON with no markdown formatting:
{
  "primaryNarrative": "storytelling",
  "secondaryNarrative": null,
  "contentType": "voiceoverReel",
  "niche": "Real Estate Wholesaling",
  "creatorHandle": "@username",
  "creatorName": "Display Name",
  "classificationConfidence": 0.85,
  "frameworkType": "aida",
  "sections": [
    {"label": "Hook", "purpose": "Creates curiosity gap about...", "sizePercent": 0.12, "emotion": "curiosity"},
    {"label": "Problem", "purpose": "Establishes the pain point...", "sizePercent": 0.25, "emotion": "frustration"}
  ],
  "emotionalArc": [
    {"position": 0.0, "emotion": "curiosity", "intensity": 0.8},
    {"position": 0.15, "emotion": "frustration", "intensity": 0.6}
  ],
  "persuasionTechniques": [
    {"type": "socialProof", "intensity": 0.7, "example": "Quote from transcript"}
  ],
  "hookScore": 8.5,
  "hookScoreReason": "Strong curiosity gap with specific number...",
  "keyInsight": "One sentence structural insight about what makes this content work",
  "hookMechanism": "WHY this hook works — explain the psychological mechanism in 1 sentence",
  "structuralRecipe": "Step-by-step writing recipe. Format: numbered list, each step = beat label + word count + density (sparse/moderate/dense)",
  "voiceMarkers": ["conversational", "data-driven", "short sentences"],
  "sentimentQuartiles": [0.1, -0.3, 0.2, 0.6],
  "intensityQuartiles": [0.7, 0.5, 0.6, 0.9]
}

Provide at least 6 emotional arc data points. Provide at least 3 sections.
For classificationConfidence, use 0.0-1.0 where 1.0 = very confident.
If you cannot determine a field, use null.`;
}

// Port of transcriptionContext(from:) — counts + inferred modality.
function transcriptionContext(ctx: AnalyzeContext): string {
  const lines: string[] = [];
  const slides = ctx.transcriptSlides.filter(s => s.text.trim().length > 0);
  const hasSpeech = ctx.speechSegments.length > 0;

  let modality: string | null = null;
  if (slides.length > 0 || hasSpeech) {
    if (!hasSpeech) modality = 'textOnly';
    else if (slides.length === 0) modality = 'voiceoverOnly';
    else modality = 'voiceoverPlusText';
  }
  if (modality) lines.push(`Inferred Transcription Modality: ${modality}`);
  if (ctx.transcriptSlides.length > 0) {
    const visual = ctx.transcriptSlides.filter(s => (s.source ?? 'manual') !== 'speechAudio');
    lines.push(`Transcript Slide Count: ${ctx.transcriptSlides.length}`);
    lines.push(`Visual Slide Count: ${visual.length}`);
  }
  if (hasSpeech) lines.push(`Speech Segment Count: ${ctx.speechSegments.length}`);
  if (ctx.transcriptionQuality) lines.push(`Transcription Quality: ${ctx.transcriptionQuality}`);
  if (ctx.transcriptionWarnings?.length) lines.push(`Transcription Warnings: ${ctx.transcriptionWarnings.join(' | ')}`);
  return lines.length ? lines.join('\n') + '\n' : '';
}

// ── LLM call + parse ────────────────────────────────────────────────────────

interface ClassificationResponse {
  primaryNarrative?: string | null;
  secondaryNarrative?: string | null;
  contentType?: string | null;
  niche?: string | null;
  creatorHandle?: string | null;
  creatorName?: string | null;
  classificationConfidence?: number | null;
  frameworkType?: string | null;
  sections?: Array<{ label?: string; purpose?: string; sizePercent?: number; emotion?: string }> | null;
  emotionalArc?: Array<{ position?: number; emotion?: string; intensity?: number }> | null;
  persuasionTechniques?: Array<{ type?: string; intensity?: number; example?: string }> | null;
  hookScore?: number | null;
  hookScoreReason?: string | null;
  keyInsight?: string | null;
  hookMechanism?: string | null;
  structuralRecipe?: string | null;
  voiceMarkers?: string[] | null;
  sentimentQuartiles?: number[] | null;
  intensityQuartiles?: number[] | null;
}

export async function classify(ctx: AnalyzeContext): Promise<ClassificationResponse | null> {
  if (!config.openRouterApiKey || !ctx.text.trim()) return null;

  const response = await fetch(`${config.openRouterBaseUrl}/chat/completions`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${config.openRouterApiKey}`,
      'X-Title': 'CosmoOS',
    },
    body: JSON.stringify({
      model: CLASSIFICATION_MODEL,
      messages: [{ role: 'user', content: buildUnifiedPrompt(ctx) }],
      temperature: 0.2,
      max_tokens: 4000,
    }),
    signal: AbortSignal.timeout(120_000),
  });
  if (!response.ok) {
    console.warn(`⚠️ classification call failed: ${response.status}`);
    return null;
  }
  const payload = await response.json() as { choices?: Array<{ message?: { content?: string } }> };
  const content = payload.choices?.[0]?.message?.content ?? '';
  return parseResponse(content);
}

export function parseResponse(response: string): ClassificationResponse | null {
  let jsonStr = response.trim();
  if (jsonStr.startsWith('```')) {
    const firstNewline = jsonStr.indexOf('\n');
    if (firstNewline >= 0) jsonStr = jsonStr.slice(firstNewline + 1);
    if (jsonStr.endsWith('```')) jsonStr = jsonStr.slice(0, -3);
    jsonStr = jsonStr.trim();
  }
  try {
    return JSON.parse(jsonStr) as ClassificationResponse;
  } catch {
    return null;
  }
}

// ── buildAnalysis port — produces SwipeAnalysis-shaped JSON ────────────────

export function buildAnalysisJSON(
  response: ClassificationResponse,
  creatorUUID: string | null
): Record<string, unknown> {
  const primaryNarrative = enumOrNull(response.primaryNarrative, NARRATIVE_VALUES);
  const secondaryNarrative = enumOrNull(response.secondaryNarrative, NARRATIVE_VALUES);
  const contentFormat = enumOrNull(response.contentType, FORMAT_VALUES);
  const frameworkType = enumOrNull(response.frameworkType, FRAMEWORK_VALUES);

  const sections = (response.sections ?? [])
    .map((s, index) => {
      const label = (s.label ?? '').trim();
      const effectiveLabel = label || (s.purpose ?? '').slice(0, 30).trim();
      if (!effectiveLabel) return null;
      const section: Record<string, unknown> = {
        label: effectiveLabel,
        startIndex: index,
        endIndex: index + 1,
        purpose: s.purpose ?? '',
      };
      const emotion = enumOrNull(s.emotion, EMOTION_VALUES);
      if (emotion) section.emotion = emotion;
      if (typeof s.sizePercent === 'number') section.sizePercent = s.sizePercent;
      return section;
    })
    .filter((s): s is Record<string, unknown> => s !== null);

  const emotionalArc = (response.emotionalArc ?? [])
    .filter(p => enumOrNull(p.emotion, EMOTION_VALUES) !== null)
    .map(p => ({
      position: clamp01(p.position ?? 0),
      intensity: clamp01(p.intensity ?? 0),
      emotion: p.emotion as string,
    }));

  let dominantEmotion: string | null = null;
  if (emotionalArc.length > 0) {
    const intensity: Record<string, number> = {};
    for (const point of emotionalArc) {
      intensity[point.emotion] = (intensity[point.emotion] ?? 0) + point.intensity;
    }
    dominantEmotion = Object.entries(intensity).sort((a, b) => b[1] - a[1])[0][0];
  }

  const persuasionTechniques = (response.persuasionTechniques ?? [])
    .filter(t => enumOrNull(t.type, PERSUASION_VALUES) !== null)
    .map(t => ({
      type: t.type as string,
      intensity: clamp01(t.intensity ?? 0),
      ...(t.example ? { example: t.example } : {}),
    }));

  const persuasionStack: Record<string, number> = {};
  for (const t of persuasionTechniques) persuasionStack[t.type] = t.intensity;

  const techniqueMap: Record<string, number> = { ...persuasionStack };
  const fingerprint = {
    sentimentArc: normalizeQuartiles(response.sentimentQuartiles),
    intensityArc: normalizeQuartiles(response.intensityQuartiles),
    techniqueWeights: PERSUASION_VALUES.map(v => techniqueMap[v] ?? 0),
    sectionCount: sections.length,
    hookType: null,
    frameworkType,
  };

  const analysis: Record<string, unknown> = {
    analysisVersion: SCHEMA_VERSION + 1,
    analyzedAt: new Date().toISOString(),
    isFullyAnalyzed: true,
    classificationSource: 'ai',
    classifiedAt: appleSeconds(new Date()),
  };
  if (response.hookScore != null && response.hookScore > 0) analysis.hookScore = response.hookScore;
  if (frameworkType) analysis.frameworkType = frameworkType;
  if (sections.length) analysis.sections = sections;
  if (dominantEmotion) analysis.dominantEmotion = dominantEmotion;
  if (emotionalArc.length) analysis.emotionalArc = emotionalArc;
  if (persuasionTechniques.length) {
    analysis.persuasionTechniques = persuasionTechniques;
    analysis.persuasionStack = persuasionStack;
  }
  if (response.keyInsight) analysis.keyInsight = response.keyInsight;
  analysis.fingerprint = fingerprint;
  if (response.hookScoreReason) analysis.hookScoreReason = response.hookScoreReason;
  if (primaryNarrative) analysis.primaryNarrative = primaryNarrative;
  if (secondaryNarrative) analysis.secondaryNarrative = secondaryNarrative;
  if (contentFormat) analysis.swipeContentFormat = contentFormat;
  if (response.niche) analysis.niche = response.niche;
  if (creatorUUID) analysis.creatorUUID = creatorUUID;
  if (response.classificationConfidence != null) analysis.classificationConfidence = response.classificationConfidence;
  if (response.hookMechanism) analysis.hookMechanism = response.hookMechanism;
  if (response.structuralRecipe) analysis.structuralRecipe = response.structuralRecipe;
  if (response.voiceMarkers?.length) analysis.voiceMarkers = response.voiceMarkers;
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

function clamp01(value: number): number {
  return Math.min(Math.max(value, 0), 1);
}

function normalizeQuartiles(values: number[] | null | undefined): number[] {
  if (Array.isArray(values) && values.length === 4 && values.every(v => typeof v === 'number')) return values;
  return [0, 0, 0, 0];
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
