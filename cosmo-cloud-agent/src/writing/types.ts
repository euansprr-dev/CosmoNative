// cosmo-cloud-agent/src/writing/types.ts
// Data structures for the Cloud Writing Engine
// PORTING SOURCE: UnifiedWritingEngine.swift + UnifiedWritingTypes.swift

// ============================================================
// Writing Phases
// ============================================================

export type WritingPhase = 'brainstorm' | 'draft' | 'polish';

// ============================================================
// Content Format Detection
// ============================================================

export type ContentFormat =
  | 'reel' | 'voiceoverReel' | 'oneSliderReel' | 'multiSliderReel' | 'twoStepCTA'
  | 'carousel' | 'thread' | 'tweet' | 'post'
  | 'youtube' | 'newsletter' | 'longForm'
  | 'unknown';

export type FormatFamily = 'reel' | 'carousel_thread' | 'tweet' | 'post' | 'youtube' | 'newsletter';

/**
 * Map a content format to its swipe format family.
 * Source: WritingContentFormat.swipeFormatFamily in Swift
 */
export function getFormatFamily(format: ContentFormat): FormatFamily {
  switch (format) {
    case 'reel':
    case 'voiceoverReel':
    case 'oneSliderReel':
    case 'multiSliderReel':
    case 'twoStepCTA':
      return 'reel';
    case 'carousel':
    case 'thread':
      return 'carousel_thread';
    case 'tweet':
      return 'tweet';
    case 'post':
      return 'post';
    case 'youtube':
    case 'longForm':
      return 'youtube';
    case 'newsletter':
      return 'newsletter';
    default:
      return 'carousel_thread'; // Safe default
  }
}

/**
 * Detect content format from atom metadata.
 * Source: WritingContentFormat.detect(from:) in Swift
 * Priority: explicitFormat > contentFormat > platform fallback
 */
export function detectContentFormat(metadata: Record<string, any> | null): ContentFormat {
  if (!metadata) return 'unknown';

  // Priority 1: Explicit format set by agent
  const explicit = metadata.explicitFormat as string | undefined;
  if (explicit) return normalizeFormat(explicit);

  // Priority 2: Canonical content format
  const canonical = metadata.contentFormat as string | undefined;
  if (canonical) return normalizeFormat(canonical);

  // Priority 3: Platform fallback
  const platform = metadata.platform as string | undefined;
  if (platform) {
    switch (platform.toLowerCase()) {
      case 'instagram': return 'carousel';
      case 'twitter': case 'x': return 'thread';
      case 'linkedin': return 'post';
      case 'youtube': return 'youtube';
      case 'tiktok': return 'reel';
      default: return 'unknown';
    }
  }

  return 'unknown';
}

function normalizeFormat(format: string): ContentFormat {
  const lower = format.toLowerCase().replace(/[\s_-]/g, '');
  if (lower.includes('reel') || lower.includes('tiktok')) return 'reel';
  if (lower.includes('carousel')) return 'carousel';
  if (lower.includes('thread')) return 'thread';
  if (lower.includes('tweet')) return 'tweet';
  if (lower.includes('post') || lower.includes('linkedin')) return 'post';
  if (lower.includes('youtube') || lower.includes('longform')) return 'youtube';
  if (lower.includes('newsletter')) return 'newsletter';
  return 'unknown';
}

// ============================================================
// Compressed Swipe (for Block 3A context)
// ============================================================

export interface CompressedSwipe {
  uuid: string;
  title: string;
  hookText: string;
  hookType: string;
  hookScore: number;
  beatSequence: string[];
  beatFingerprint: string;
  keyTransitions: string[];
  ctaText: string;
  framework: string;
  format: string;
  isPrimary: boolean;
  isClientExample: boolean;
  engagementSummary: string;
  fullBody: string;
  structuralBreakdown: string;
  persuasionTechniques: string[];
  emotionalArc: string[];
  hookScoreReason: string;
  hookMechanism: string;      // WHY the hook works (psychological mechanism)
  structuralRecipe: string;   // Step-by-step writing recipe
  voiceMarkers: string[];     // Voice traits (e.g., ["conversational", "data-driven"])
  quarkSummary?: QuarkSummary; // Pre-extracted Content Physics summary (from Opus extraction)
}

// ============================================================
// Content Physics: Quark Summary (compact, for Block 3A per-swipe display)
// ============================================================

export interface QuarkSummary {
  dominantSpeechActs: string[];   // top 3 speech acts (e.g., ["confession", "update", "reveal"])
  arcShape: string;               // e.g., "fail-win-loss-win-emptiness-restart-peace"
  symmetryBreakSlide: number;     // which slide breaks the established pattern
  phaseTransition?: string;       // e.g., "success → meaning" or undefined if none
  peakGravityLoops: number;       // open loops at peak gravity point
  novelDiscoveries: string[];     // top 2 unique patterns found
}

// ============================================================
// Content Physics: Full Quark Profile (stored per-swipe in atom.structured.contentPhysics)
// ============================================================

export interface QuarkProfile {
  version: number;
  extractedAt: string;
  extractedBy: string;            // model ID used for extraction

  slideQuarks: Array<{
    slideNumber: number;
    text: string;                 // first 100 chars of slide text for reference
    speechAct: { type: string; mechanism: string };
    readerDeltas: Array<{ type: string; mechanism: string }>;
    proofType?: { type: string; mechanism: string };
    motivation?: { type: string; mechanism: string };
    compression?: { type: string; size: string; mechanism: string };
    resonanceFrequency?: { detail: string; unspokenExperience: string; estimatedReach: string };
    frame?: { type: string; mechanism: string };
  }>;

  transitions: Array<{
    from: number;
    to: number;
    type: string;                 // e.g., "doubt→reaffirmation", "deflation", "escalation"
    mechanism: string;
    swapTestPasses: boolean;      // false = strong transition (can't swap)
    doubleHelix: boolean;         // both narrative + psychological causality present
    doubleHelixDetail?: string;
  }>;

  arcQuarks: {
    shape: string;
    winLossReversals: number;
    tensionPeaks: number[];
    sparseDensePattern: string;
    internalExternalTension?: {
      present: boolean;
      peakSlide: number;
      description: string;
    };
  };

  rsv: {
    trajectoryPoints: Array<{
      afterSlide: number;
      openLoops: { count: number; loops: string[] };
      trust: string;
      tension: { level: string; type: string };
      patternExpectation: string;
      frame: string;
      energyBalance: string;
      superpositionCount?: number;
      superpositions?: string[];
    }>;
  };

  physicsEvents: {
    symmetryBreak: {
      slideNumber: number;
      patternEstablished: string;
      whatBreaks: string;
      whyDevastating: string;
    };
    phaseTransition: {
      slideNumber: number;
      frameBefore: string;
      frameAfter: string;
      recontextualization: string;
    };
    energyResolution: {
      proportional: boolean;
      loopsClosed: Array<{ loop: string; closedAtSlide: number }>;
      loopsUnclosed: string[];
      assessment: string;
    };
    peakGravity: {
      slideNumber: number;
      activeLoops: number;
      coincidesWithTransition: boolean;
    };
  };

  novelDiscoveries: string[];

  // Long-range interactions (Pass 7)
  longRangeInteractions?: {
    setupPayoffBonds: Array<{ setupSlide: number; payoffSlide: number; distance: number; planted: string; harvested: string }>;
    echoPatterns: Array<{ quarkType: string; positions: number[]; transformation: string }>;
    interferences: Array<{ slides: number[]; forces: string[]; emergentEffect: string }>;
    deliberateAbsences: Array<{ what: string; slides: number[]; effect: string }>;
    callbackChains: Array<{ element: string; appearances: Array<{ slide: number; meaning: string }>; transformationArc: string }>;
    entanglementPairs?: Array<{ slideA: number; slideB: number; ifARemoved: string; ifBRemoved: string }>;
  };

  // Antimatter — phrases/structures/moves that would destroy this post's physics
  antimatter?: string[];

  // Rhythm and pacing (Pass 8)
  rhythm?: {
    densityWaveform: number[];
    energyCurve: number[];
    informationRate: number[];
    silenceSlides: number[];
    momentumMechanism: string;
    pacingPattern: string;
  };

  // Complete reader simulation (Pass 9)
  readerSimulation?: Array<{
    afterSlide: number;
    activeQuestions: string[];
    builtAssumptions: string[];
    prediction: string;
    dominantEmotion: string;
    investmentLevel: string;
  }>;

  // Deep fabric synthesis (Pass 10)
  deepFabric?: string;
}

/**
 * Format a compressed swipe for inclusion in Block 3A.
 * Source: CompressedSwipe.formatted() in Swift
 */
export function formatCompressedSwipe(swipe: CompressedSwipe): string {
  const lines: string[] = [];

  if (swipe.isClientExample) {
    lines.push(`[CLIENT TOP POST]: "${swipe.title}" (engagement: ${swipe.engagementSummary})`);
    lines.push(`Format: ${swipe.format}`);
    if (swipe.fullBody) {
      lines.push(`--- FULL BODY ---`);
      lines.push(swipe.fullBody);
    }
    return lines.join('\n');
  }

  lines.push(`Title: "${swipe.title}"`);
  lines.push(`Hook Type: ${swipe.hookType} (score: ${swipe.hookScore}/10)`);
  if (swipe.hookMechanism) {
    lines.push(`Hook Mechanism: ${swipe.hookMechanism}`);
  }
  lines.push(`Beat Pattern: ${swipe.beatSequence.join(' > ')}`);
  if (swipe.structuralRecipe) {
    lines.push(`Structural Recipe:`);
    lines.push(`  ${swipe.structuralRecipe}`);
  }
  lines.push(`Framework: ${swipe.framework} | Format: ${swipe.format}${swipe.isPrimary ? ' [PRIMARY BLUEPRINT]' : ''}`);
  if (swipe.voiceMarkers.length > 0) {
    lines.push(`Voice: ${swipe.voiceMarkers.join(', ')}`);
  }

  if (swipe.hookScoreReason) {
    lines.push(`Why Hook Works: ${swipe.hookScoreReason}`);
  }
  if (swipe.engagementSummary) {
    lines.push(`Engagement: ${swipe.engagementSummary}`);
  }
  if (swipe.persuasionTechniques.length > 0) {
    lines.push(`Persuasion: ${swipe.persuasionTechniques.join(', ')}`);
  }
  if (swipe.emotionalArc.length > 0) {
    lines.push(`Emotional Arc: ${swipe.emotionalArc.join(' → ')}`);
  }

  if (swipe.fullBody) {
    lines.push(`--- FULL BODY ---`);
    lines.push(swipe.fullBody);
  }

  if (swipe.isPrimary && swipe.structuralBreakdown) {
    lines.push(`--- STRUCTURAL BLUEPRINT ---`);
    lines.push(swipe.structuralBreakdown);
  }

  if (swipe.quarkSummary) {
    const q = swipe.quarkSummary;
    lines.push(`Physics: Arc=${q.arcShape}, Break@slide${q.symmetryBreakSlide}${q.phaseTransition ? `, Transition=${q.phaseTransition}` : ''}, Gravity=${q.peakGravityLoops} loops`);
    if (q.novelDiscoveries.length > 0) {
      lines.push(`Novel: ${q.novelDiscoveries.join('; ')}`);
    }
  }

  return lines.join('\n');
}

// ============================================================
// Writing Messages (conversation history)
// ============================================================

export interface WritingMessage {
  id: string;
  role: 'user' | 'assistant' | 'system' | 'tool';
  content: string;
  timestamp: string;
  toolCallId?: string;
  toolCalls?: Array<{
    id: string;
    name: string;
    arguments: Record<string, any>;
  }>;
  isSystemNudge?: boolean; // System-generated nudge — excluded from persistence
}

// ============================================================
// Outline & Hooks
// ============================================================

export interface OutlineItem {
  id: string;
  title: string;
  beatLabel?: string;
  description?: string;
  estimatedSeconds?: number;
  sortOrder: number;
}

export interface HookVariant {
  text: string;
  hookType?: string;
  estimatedScore?: number;
  reasoning?: string;
}

// ============================================================
// Scorecard
// ============================================================

export interface ScorecardResult {
  hookScore: { score: number; suggestions: string[] };
  copyScore: { score: number; suggestions: string[] };
  ctaScore: { score: number; suggestions: string[] };
  voiceMatchPercentage: number;
  voiceDrifts: Array<{ lineNumber: number; issue: string; suggestion: string }>;
  structuralAlignmentScore: number;
  structuralSuggestions: string[];
  draftBeats: string[];
  recommendedBeats: string[];
  slideCount: number;
  overallConfidence: number;
  guidedFeedback: string;
}

// ============================================================
// Draft Validation
// ============================================================

export interface DraftValidation {
  isValid: boolean;
  violations: string[];
  format: string;
  wordCount: number;
}

/**
 * Validate a draft against format constraints.
 * Source: validateDraft() in UnifiedWritingEngine.swift
 */
export function validateDraft(content: string, format: ContentFormat): DraftValidation {
  const violations: string[] = [];
  const wordCount = content.split(/\s+/).filter(Boolean).length;

  try {
    const parsed = JSON.parse(content);

    if (parsed.slides && Array.isArray(parsed.slides)) {
      // Carousel validation
      if (parsed.slides.length < 5) violations.push(`Only ${parsed.slides.length} slides — minimum 5 required`);
      if (parsed.slides.length > 15) violations.push(`${parsed.slides.length} slides — maximum 15`);
      for (let i = 0; i < parsed.slides.length; i++) {
        const text = parsed.slides[i].text || '';
        if (text.length > 300) violations.push(`Slide ${i + 1}: ${text.length} chars (max 300)`);
      }
      return { isValid: violations.length === 0, violations, format: 'carousel', wordCount };
    }

    if (parsed.tweets && Array.isArray(parsed.tweets)) {
      // Thread validation
      if (parsed.tweets.length < 4) violations.push(`Only ${parsed.tweets.length} tweets — minimum 4`);
      if (parsed.tweets.length > 12) violations.push(`${parsed.tweets.length} tweets — maximum 12`);
      for (let i = 0; i < parsed.tweets.length; i++) {
        const text = typeof parsed.tweets[i] === 'string' ? parsed.tweets[i] : parsed.tweets[i].text || '';
        if (text.length > 280) violations.push(`Tweet ${i + 1}: ${text.length} chars (max 280)`);
      }
      return { isValid: violations.length === 0, violations, format: 'thread', wordCount };
    }
  } catch {
    // Plaintext — check word count based on format
  }

  if (format === 'reel' || format === 'voiceoverReel') {
    if (wordCount < 50) violations.push(`Only ${wordCount} words — minimum 50 for reels`);
    if (wordCount > 300) violations.push(`${wordCount} words — maximum 300 for reels`);
  }

  return { isValid: violations.length === 0, violations, format: 'plaintext', wordCount };
}

// ============================================================
// Draft Rendering
// ============================================================

/**
 * Render structured JSON draft to readable plaintext.
 * Source: renderDraftForDisplay() in AgentToolExecutor.swift
 */
export function renderDraftForDisplay(body: string): string {
  if (!body) return '';

  try {
    const parsed = JSON.parse(body);

    if (parsed.slides && Array.isArray(parsed.slides)) {
      return parsed.slides.map((s: any, i: number) => {
        const num = s.number || i + 1;
        let text = `SLIDE ${num}\n${s.text || ''}`;
        if (s.visualDirection) text += `\n[Visual: ${s.visualDirection}]`;
        return text;
      }).join('\n\n');
    }

    if (parsed.tweets && Array.isArray(parsed.tweets)) {
      return parsed.tweets.map((t: any, i: number) =>
        `TWEET ${i + 1}\n${typeof t === 'string' ? t : t.text || ''}`
      ).join('\n\n');
    }

    if (Array.isArray(parsed)) {
      return parsed.map((item: any, i: number) => {
        if (typeof item === 'string') return `SLIDE ${i + 1}\n${item}`;
        return `SLIDE ${i + 1}\n${item.text || JSON.stringify(item)}`;
      }).join('\n\n');
    }
  } catch {
    // Not JSON
  }

  return body;
}
