// cosmo-cloud-agent/src/writing/contextAssembler.ts
// 4-block context assembly for the Cloud Writing Engine
// PORTING SOURCE: UnifiedWritingEngine assembleBlock1/2/3Stable/3Dynamic
//
// Block 1 (Cached): Methodology + System Prompt + Platform Constraints
// Block 2 (Cached): Client intelligence model, voice targets, failure rules
// Block 3A (Session-Stable): Selected swipes + application rules + pattern intelligence
// Block 3B (Dynamic): Current content state, outline, hooks, draft preview

import { Atom, fetchAtom, fetchAllByType, loadPromptTemplate } from '../db/queries';
import { CompressedSwipe, ContentFormat, formatCompressedSwipe, OutlineItem } from './types';
import { computeSwipeIntelligenceBrief } from './swipeSelector';

export interface WritingBlock {
  label: string;
  content: string;
  cacheControl: boolean;
}

// ============================================================
// Block 1: Methodology + System Prompt
// ============================================================

export async function assembleBlock1(format: ContentFormat): Promise<WritingBlock> {
  // System prompt: ALWAYS use the code default — this is the engine's core instruction set.
  // It must stay in sync with the 3-phase pipeline in engine.ts. Supabase had a stale version.
  // Methodology + constraints: still load from Supabase (user-editable from Mac app).
  const methodology = await loadPromptTemplate('methodology');
  const constraints = await loadPromptTemplate('platform_constraints');

  let content = DEFAULT_WRITING_SYSTEM_PROMPT;
  console.log(`    ✍️ System prompt: using engine default (${content.length} chars)`);

  // Inject methodology (Supabase version if available, else hardcoded default)
  const methodologyText = methodology || DEFAULT_METHODOLOGY;
  if (content.includes('{METHODOLOGY_TEXT}')) {
    content = content.replace('{METHODOLOGY_TEXT}', methodologyText);
  } else {
    console.warn('    ⚠️ CRITICAL: {METHODOLOGY_TEXT} placeholder missing from system prompt — appending methodology');
    content += '\n\n' + methodologyText;
  }
  console.log(`    ✍️ Methodology: ${methodology ? 'from Supabase' : 'engine default'} (${methodologyText.length} chars)`);

  // Inject platform constraints
  if (content.includes('{PLATFORM_CONSTRAINTS}')) {
    content = content.replace('{PLATFORM_CONSTRAINTS}', constraints || '');
  } else {
    if (constraints) content += '\n\n' + constraints;
  }

  // Inject format-specific density override AFTER the system prompt
  content += '\n\n' + getFormatDensityOverride(format);
  console.log(`    ✍️ Block 1 assembled: ${content.length} chars (format: ${format})`);

  return { label: 'Block 1: Methodology', content, cacheControl: true };
}

function getFormatDensityOverride(format: ContentFormat): string {
  switch (format) {
    case 'carousel':
    case 'thread':
      return `═══════════════════════════════════════════════════════════════
FORMAT GUIDANCE: CAROUSEL/THREAD DENSITY
═══════════════════════════════════════════════════════════════
This is a CAROUSEL/THREAD. Carousel density varies dramatically by style:
• Teaching/listicle carousels: typically 3-6 sentences, 50-100 words per slide, with bullets and specific data
• Story/narrative carousels: typically 1-2 sentences per slide — dialogue, year markers, emotional beats

YOUR DENSITY TARGET COMES FROM THE PRIMARY BLUEPRINT, NOT THESE DEFAULTS.
Count the actual words per slide in the blueprint — that number is your target (±10%).
The FORMATTING DNA section in your loaded swipe intelligence shows measured avgWordsPerSlide
and avgSentencesPerSlide from all 20 swipes. Use those measured numbers as your reference.

If the blueprint has 10-word slides, write 10-word slides.
If the blueprint has 80-word slides, write 80-word slides.
The blueprint IS the density standard. Match IT, not a generic rule.

• Study the loaded swipe examples — COUNT their words per slide and MATCH the blueprint's density
• The "1-2 sentences default" and "3 max" rules from Voice DNA do NOT apply to carousels
• Use bullet points (-- or •) ONLY if the blueprint uses them — don't add formatting the blueprint doesn't have`;

    case 'reel':
    case 'voiceoverReel':
    case 'oneSliderReel':
    case 'multiSliderReel':
    case 'twoStepCTA':
      return `═══════════════════════════════════════════════════════════════
FORMAT OVERRIDE: REEL DENSITY
═══════════════════════════════════════════════════════════════
This is a REEL. Reel slides are SHORT and PUNCHY.
• Each slide: 1-2 sentences max, 10-25 words
• No bullet points — clean, flowing text
• One thought per slide, conversational tone
• Study the loaded swipe examples for the right density`;

    default:
      return '';
  }
}

// ============================================================
// Block 2: Client Intelligence
// ============================================================

export async function assembleBlock2(
  clientAtom: Atom | null,
  lessons: Array<{ rule: string; enforcement: string; evidence?: string; category?: string; clientUUID?: string }>,
): Promise<WritingBlock> {
  if (!clientAtom) {
    return { label: 'Block 2: Client', content: '[No client profile loaded]', cacheControl: true };
  }

  const meta = clientAtom.metadata || {};
  const structured = clientAtom.structured || {};
  const intel = structured.intelligenceModel || {};
  const voice = intel.voiceFingerprint || {};
  const performance = intel.performanceFingerprint || {};
  const audience = intel.audienceModel || {};
  const positioning = intel.nicheAndPositioning || {};

  const sections: string[] = [];

  // Client identity
  sections.push(`=== CLIENT PROFILE: ${clientAtom.title} ===`);
  if (meta.niche) sections.push(`Niche: ${meta.niche}`);
  if (meta.preferredPlatforms) sections.push(`Platforms: ${(meta.preferredPlatforms as string[]).join(', ')}`);

  // Voice targets
  if (voice.avgSentenceLength || voice.readingLevel) {
    sections.push('\n--- VOICE TARGETS ---');
    if (voice.avgSentenceLength) sections.push(`Sentence Length: ${voice.avgSentenceLength} words (target)`);
    if (voice.readingLevel) sections.push(`Reading Level: ${voice.readingLevel}`);
    if (voice.punctuationStyle) sections.push(`Punctuation: ${voice.punctuationStyle}`);
    if (voice.ctaPattern) sections.push(`CTA Pattern: ${voice.ctaPattern}`);
    if (voice.powerWords && (voice.powerWords as string[]).length > 0) {
      sections.push(`Power Words: ${(voice.powerWords as string[]).join(', ')}`);
    }
    if (voice.signaturePhrases && (voice.signaturePhrases as string[]).length > 0) {
      sections.push(`Signature Phrases: ${(voice.signaturePhrases as string[]).join(', ')}`);
    }
    if (voice.blacklistedPhrases && (voice.blacklistedPhrases as string[]).length > 0) {
      sections.push(`BANNED Phrases: ${(voice.blacklistedPhrases as string[]).join(', ')}`);
    }
    if (voice.formattingQuirks && (voice.formattingQuirks as string[]).length > 0) {
      sections.push(`Formatting Quirks: ${(voice.formattingQuirks as string[]).join(', ')}`);
    }
    if (voice.emotionalTone) {
      const tones = voice.emotionalTone as Record<string, number>;
      const sorted = Object.entries(tones).sort((a, b) => b[1] - a[1]).slice(0, 3);
      if (sorted.length > 0) {
        sections.push(`Emotional Tone: ${sorted.map(([t, p]) => `${t}: ${Math.round(p as number * 100)}%`).join(', ')}`);
      }
    }
  }

  // Performance patterns
  if (performance.bestTopics || performance.optimalLength || performance.hookTypePerformance) {
    sections.push('\n--- PERFORMANCE PATTERNS ---');
    if (performance.bestTopics && (performance.bestTopics as string[]).length > 0) {
      sections.push(`Best Topics: ${(performance.bestTopics as string[]).join(', ')}`);
    }
    if (performance.optimalLength) {
      sections.push(`Optimal Length: ${performance.optimalLength}`);
    }
    if (performance.bestBeatPatterns && (performance.bestBeatPatterns as string[]).length > 0) {
      sections.push(`Best Beat Patterns: ${(performance.bestBeatPatterns as string[]).join('; ')}`);
    }
    if (performance.engagementTriggers && (performance.engagementTriggers as string[]).length > 0) {
      sections.push(`Engagement Triggers: ${(performance.engagementTriggers as string[]).join(', ')}`);
    }
    if (performance.hookTypePerformance) {
      const hookPerf = performance.hookTypePerformance as Record<string, number>;
      const sorted = Object.entries(hookPerf).sort((a, b) => b[1] - a[1]).slice(0, 5);
      if (sorted.length > 0) {
        sections.push(`Top Hook Types: ${sorted.map(([t, f]) => `${t}: ${f}`).join(', ')}`);
      }
    }
  }

  // Audience model
  if (audience.primaryAudience || audience.topPainPoints || audience.aspirationalOutcomes) {
    sections.push('\n--- AUDIENCE MODEL ---');
    if (audience.primaryAudience) sections.push(`Primary Audience: ${audience.primaryAudience}`);
    if (audience.topPainPoints && (audience.topPainPoints as string[]).length > 0) {
      sections.push(`Pain Points: ${(audience.topPainPoints as string[]).join('; ')}`);
    }
    if (audience.aspirationalOutcomes && (audience.aspirationalOutcomes as string[]).length > 0) {
      sections.push(`Aspirational Outcomes: ${(audience.aspirationalOutcomes as string[]).join('; ')}`);
    }
    if (audience.commonObjections && (audience.commonObjections as string[]).length > 0) {
      sections.push(`Common Objections: ${(audience.commonObjections as string[]).join('; ')}`);
    }
    if (audience.audienceLanguage && (audience.audienceLanguage as string[]).length > 0) {
      sections.push(`Audience Language: ${(audience.audienceLanguage as string[]).join(', ')}`);
    }
  }

  // Positioning
  if (positioning.specificNiche || positioning.uniqueAngle || positioning.coreBeliefs) {
    sections.push('\n--- POSITIONING ---');
    if (positioning.specificNiche) sections.push(`Niche: ${positioning.specificNiche}`);
    if (positioning.uniqueAngle) sections.push(`Unique Angle: ${positioning.uniqueAngle}`);
    if (positioning.uniqueMechanism) sections.push(`Unique Mechanism: ${positioning.uniqueMechanism}`);
    if (positioning.coreBeliefs && (positioning.coreBeliefs as string[]).length > 0) {
      sections.push(`Core Beliefs: ${(positioning.coreBeliefs as string[]).join('; ')}`);
    }
    if (positioning.enemies && (positioning.enemies as string[]).length > 0) {
      sections.push(`Enemies (what they stand against): ${(positioning.enemies as string[]).join('; ')}`);
    }
  }

  // Failure fingerprint (hard rules from past edits)
  const failureRules = intel.failureRules as any[] | undefined;
  if (failureRules && failureRules.length > 0) {
    sections.push('\n--- FAILURE FINGERPRINT (HARD RULES — never violate) ---');
    const highRules = failureRules.filter((r: any) => r.severity === 'HIGH');
    const medRules = failureRules.filter((r: any) => r.severity === 'MEDIUM');
    for (const rule of [...highRules, ...medRules]) {
      sections.push(`  [${rule.severity}] ${rule.rule || rule.description}`);
    }
  }

  // Learned lesson rules (RULE/BAD/GOOD/WHY format matching Swift's optimized instructions)
  if (lessons.length > 0) {
    const hardRules = lessons.filter(l => l.enforcement === 'hard');
    const advisoryRules = lessons.filter(l => l.enforcement !== 'hard');

    if (hardRules.length > 0) {
      sections.push('\n--- LEARNED WRITING RULES — MANDATORY (HARD) ---');
      sections.push('These rules were learned from the user\'s past edits and explicit instructions.');
      sections.push('Violating ANY of these will trigger an automatic rewrite. Follow them exactly.');
      for (let i = 0; i < hardRules.length; i++) {
        const r = hardRules[i];
        const scope = r.clientUUID ? '[client-specific]' : '[universal]';
        // If rule has RULE/BAD/GOOD format, use it directly
        if (r.rule.includes('RULE:') || r.rule.includes('BAD:') || r.rule.includes('\n')) {
          sections.push(`\n${i + 1}. ${scope} ${r.rule}`);
        } else {
          sections.push(`\n${i + 1}. ${scope} RULE: ${r.rule}`);
        }
        if (r.evidence) {
          sections.push(`   EVIDENCE: ${r.evidence}`);
        }
        if (r.category) {
          sections.push(`   CATEGORY: ${r.category}`);
        }
      }
    }

    if (advisoryRules.length > 0) {
      sections.push('\n--- LEARNED WRITING PREFERENCES — ADVISORY ---');
      sections.push('These patterns were observed from the user\'s edits. Follow when possible.');
      for (let i = 0; i < advisoryRules.length; i++) {
        const r = advisoryRules[i];
        const scope = r.clientUUID ? '[client-specific]' : '[universal]';
        sections.push(`  ${i + 1}. ${scope} ${r.rule}`);
        if (r.evidence) {
          sections.push(`     EVIDENCE: ${r.evidence}`);
        }
      }
    }
  }

  // Client profile documents (story, voice guide, top performing content with real numbers)
  // Source: ProfileDocument array in metadata.documents or structured.documents
  // Categories: story, voiceGuide, reel, thread, underperformingReel, underperformingThread
  const documents = (structured.documents || meta.documents) as any[] | undefined;

  if (documents && documents.length > 0) {
    // Story documents (brand story with real business numbers — properties, revenue, etc.)
    const stories = documents.filter((d: any) => d.category === 'story');
    for (const story of stories) {
      if (story.content) {
        sections.push(`\n--- BRAND STORY (contains real numbers — use these, NEVER ask user for them) ---`);
        sections.push(story.content);
      }
    }

    // Voice guides
    const guides = documents.filter((d: any) => d.category === 'voiceGuide');
    for (const guide of guides) {
      if (guide.content) {
        sections.push(`\n--- VOICE GUIDE ---`);
        sections.push(guide.content);
      }
    }

    // Top performing content (reels + threads with real transcripts and engagement metrics)
    const topContent = documents.filter((d: any) => ['reel', 'thread'].includes(d.category));
    if (topContent.length > 0) {
      sections.push('\n--- TOP PERFORMING CONTENT (real transcripts with engagement data) ---');
      for (const doc of topContent.slice(0, 5)) {
        const stats: string[] = [];
        if (doc.likes) stats.push(`${doc.likes} likes`);
        if (doc.shares) stats.push(`${doc.shares} shares`);
        if (doc.views) stats.push(`${doc.views} views`);
        if (doc.leads) stats.push(`${doc.leads} leads`);
        if (doc.platform) stats.push(doc.platform);
        sections.push(`  [${doc.category}] "${doc.title || 'Untitled'}" — ${stats.join(', ')}`);
        if (doc.content) {
          sections.push(`    ${doc.content.substring(0, 1000)}`);
        }
      }
    }

    // Underperforming content (for failure fingerprint)
    const underperforming = documents.filter((d: any) => d.category?.startsWith('underperforming'));
    if (underperforming.length > 0) {
      sections.push('\n--- UNDERPERFORMING CONTENT (avoid these patterns) ---');
      for (const doc of underperforming.slice(0, 3)) {
        sections.push(`  [${doc.category}] "${doc.title || 'Untitled'}"`);
        if (doc.content) {
          sections.push(`    ${doc.content.substring(0, 500)}`);
        }
      }
    }
  } else {
    // Fallback to flat fields if no documents array
    if (structured.brandStory) {
      sections.push(`\n--- BRAND STORY ---\n${structured.brandStory}`);
    }
    if (structured.voiceNotes) {
      sections.push(`\n--- VOICE GUIDE ---\n${structured.voiceNotes}`);
    }

    // Top performing posts (flat field fallback)
    const topPosts = structured.topPerformingPosts as any[] | undefined;
    if (topPosts && topPosts.length > 0) {
      sections.push('\n--- TOP PERFORMING POSTS ---');
      for (const post of topPosts.slice(0, 5)) {
        const title = post.title || post.transcript?.substring(0, 80) || 'Untitled';
        const stats: string[] = [];
        if (post.likes) stats.push(`${post.likes} likes`);
        if (post.shares) stats.push(`${post.shares} shares`);
        if (post.views) stats.push(`${post.views} views`);
        sections.push(`  "${title}" — ${stats.join(', ')}`);
        if (post.transcript) sections.push(`    ${post.transcript.substring(0, 500)}`);
      }
    }
  }

  // Log what profile data is loaded for debugging
  const storyCount = documents?.filter((d: any) => d.category === 'story').length || 0;
  const guideCount = documents?.filter((d: any) => d.category === 'voiceGuide').length || 0;
  const topCount = documents?.filter((d: any) => ['reel', 'thread'].includes(d.category)).length || 0;
  const hasBrandStory = !!(structured.brandStory);
  console.log(`    ✍️ Profile context: ${storyCount} stories, ${guideCount} voice guides, ${topCount} top posts, ${documents?.length || 0} total docs${hasBrandStory ? ', brandStory: yes' : ''}`);
  if (!documents?.length && !hasBrandStory) {
    console.log(`    ⚠️ No profile documents loaded — engine may ask user for context`);
  }

  // If profile docs are loaded, explicitly tell LLM to USE them instead of asking
  if (storyCount > 0 || hasBrandStory) {
    sections.push('\n⚠️ IMPORTANT: The brand story, backstory details, and real numbers are loaded above. Do NOT ask the user for this information — WRITE the draft using what you have. Fill any small gaps with plausible specifics based on the loaded context.');
  }

  const content = sections.join('\n');

  // Cap at 200K chars (matching Swift)
  const capped = content.length > 200_000 ? content.substring(0, 200_000) + '\n... [truncated]' : content;

  return { label: 'Block 2: Client Intelligence', content: capped, cacheControl: true };
}

// ============================================================
// Shared: Swipe Application Rules (used in Block 3A and in write-phase examples block)
// ============================================================

export function getSwipeApplicationRules(swipeCount: number, primarySwipe?: CompressedSwipe): string {
  const lines: string[] = [];
  lines.push('--- SWIPE APPLICATION RULES (apply on EVERY turn, including revisions) ---');
  if (primarySwipe) {
    lines.push(`PRIMARY BLUEPRINT: "${primarySwipe.title}"`);
    lines.push(`  Beat pattern: ${primarySwipe.beatSequence.join(' > ')}`);
    lines.push(`  Hook type: ${primarySwipe.hookType} (score: ${primarySwipe.hookScore}/10)`);
    if (primarySwipe.hookText) {
      const hookPreview = primarySwipe.hookText.length > 200 ? primarySwipe.hookText.substring(0, 200) : primarySwipe.hookText;
      lines.push(`  Hook text: "${hookPreview}"`);
      lines.push(`  → All generated hooks MUST match this format exactly (case, perspective, structure)`);
    }
    if (primarySwipe.beatSequence.length > 0) {
      lines.push('  Beat functions (apply these structural roles, NOT the blueprint\'s topic):');
      primarySwipe.beatSequence.forEach((beat, i) => {
        const transition = primarySwipe.keyTransitions && i < primarySwipe.keyTransitions.length
          ? ` — ${primarySwipe.keyTransitions[i]}` : '';
        lines.push(`    ${i + 1}. [${beat}]${transition}`);
      });
    }
  }
  lines.push('RULES:');
  lines.push(`1. These ${swipeCount} swipes are your PERMANENT reference library. Their full bodies are loaded — read and absorb them.`);
  lines.push('2. The PRIMARY swipe is your closest structural anchor — mirror its beat pattern, hook type, and emotional arc.');
  lines.push('3. On EVERY revision, maintain the PRIMARY swipe\'s structural DNA — beat pattern, section count, and emotional arc.');
  lines.push('4. When shortening/lengthening, REDISTRIBUTE content to preserve the beat pattern — don\'t flatten the structure.');
  lines.push('5. NEVER copy phrases or examples from swipes — only steal STRUCTURE.');
  lines.push('6. Study how the top-scoring swipes write transitions, hooks, and CTAs — match their energy and mechanics.');
  return lines.join('\n');
}

// ============================================================
// Block 3A: Stable Session Context (Swipes + Rules)
// ============================================================

export function assembleBlock3Stable(
  swipes: CompressedSwipe[],
  clientNiche: string | null,
  experiences?: Array<{ generated: string; edited: string; summary: string; format?: string }>,
): WritingBlock {
  const sections: string[] = [];

  sections.push('=== STABLE SESSION CONTEXT ===');

  if (clientNiche) {
    sections.push(`[CLIENT NICHE: ${clientNiche}]`);
  }

  // Swipe intelligence brief (aggregated patterns)
  const brief = computeSwipeIntelligenceBrief(swipes);
  if (brief) {
    sections.push('');
    sections.push(brief);
  }

  // Swipe examples
  sections.push(`\n--- SAME-TYPE SWIPE EXAMPLES (${swipes.length} selected) ---`);
  for (const swipe of swipes) {
    sections.push(formatCompressedSwipe(swipe));
    sections.push(''); // Blank line separator
  }

  // Application rules (shared function — also used in write-phase examples block)
  const primarySwipe = swipes.find(s => s.isPrimary);
  sections.push(getSwipeApplicationRules(swipes.length, primarySwipe));

  // Pattern intelligence (aggregated)
  if (swipes.length > 0) {
    sections.push('\n--- PATTERN INTELLIGENCE (aggregated) ---');

    // Hook distribution
    const hookCounts: Record<string, number> = {};
    for (const s of swipes) {
      hookCounts[s.hookType] = (hookCounts[s.hookType] || 0) + 1;
    }
    const topHooks = Object.entries(hookCounts).sort((a, b) => b[1] - a[1]).slice(0, 3);
    sections.push(`Top Hook Types: ${topHooks.map(([h, c]) => `${h} (${c}x)`).join(', ')}`);

    // Average hook score
    const avgScore = swipes.reduce((sum, s) => sum + s.hookScore, 0) / swipes.length;
    sections.push(`Average Hook Score: ${avgScore.toFixed(1)}/10`);
  }

  // Experience buffer (few-shot examples from past edits)
  if (experiences && experiences.length > 0) {
    sections.push('\n=== PAST EDITING EXAMPLES ===');
    sections.push('The user previously made these edits to AI-generated content.');
    sections.push('Learn from these patterns to generate content closer to their preferences:\n');
    for (let i = 0; i < Math.min(experiences.length, 3); i++) {
      const exp = experiences[i];
      sections.push(`--- Example ${i + 1}${exp.format ? ` (${exp.format})` : ''} ---`);
      sections.push(`AI Generated: ${exp.generated}`);
      sections.push(`User Edited To: ${exp.edited}`);
      sections.push(`Key Change: ${exp.summary}`);
      sections.push('');
    }
  }

  const content = sections.join('\n');
  return { label: 'Block 3A: Swipe Context', content, cacheControl: true };
}

// ============================================================
// Block 3B: Dynamic Context (Current Content State)
// ============================================================

export interface WritingContext {
  latestAnalysis?: string;          // Always captured for >200 word thinks (no keyword gate)
  swipePatternAnalysis?: string;    // Keyword-matched subset (swipe/pattern/density/etc.)
  structuralPlan?: string;          // Keyword-matched subset (plan/approach/strategy/etc.)
  writingPlan?: string;             // Comprehensive writing plan from Phase 1 of draft pipeline
  keyDecisions?: string[];
  selfReviewFindings?: string;
  analysisDepth?: number;
}

export function assembleBlock3Dynamic(
  contentAtom: Atom,
  outline: OutlineItem[] | null,
  hooks: string[] | null,
  conversationSummary: string | null,
  writingContext?: WritingContext,
): WritingBlock {
  const meta = contentAtom.metadata || {};
  const sections: string[] = [];

  sections.push('=== DYNAMIC CONTEXT ===');

  // Current content state
  sections.push('--- CURRENT CONTENT STATE ---');
  sections.push(`Title: ${contentAtom.title || 'Untitled'}`);
  sections.push(`Platform: ${meta.platform || 'Not set'}`);
  sections.push(`Phase: ${meta.phase || 'ideation'}`);

  // Core idea
  const coreIdea = meta.contentDescription || contentAtom.body;
  if (coreIdea) {
    const truncated = (coreIdea as string).substring(0, 1000);
    sections.push(`Core Idea: ${truncated}`);
  }

  // Outline
  if (outline && outline.length > 0) {
    sections.push('\nOutline:');
    for (const item of outline) {
      const beat = item.beatLabel ? ` [${item.beatLabel}]` : '';
      sections.push(`  ${item.sortOrder + 1}. ${item.title}${beat}`);
      if ((item as any).reasoning) {
        sections.push(`     Notes: ${(item as any).reasoning}`);
      }
    }
  }

  // Hooks
  if (hooks && hooks.length > 0) {
    sections.push('\nHook Variants:');
    for (let i = 0; i < hooks.length; i++) {
      sections.push(`  ${i + 1}. ${hooks[i]}`);
    }
  }

  // Current draft preview
  const draft = contentAtom.body;
  if (draft && (draft as string).length > 0) {
    const draftStr = draft as string;
    if (draftStr.length > 6000) {
      sections.push(`\nCurrent Draft (${draftStr.length} chars — use read_draft for full text):`);
      sections.push(draftStr.substring(0, 6000) + '...\n[TRUNCATED — call read_draft to see full draft]');
    } else {
      sections.push(`\nCurrent Draft (${draftStr.length} chars):`);
      sections.push(draftStr);
    }
  }

  // Framework
  if (meta.inheritedFramework) {
    sections.push(`\nFramework: ${meta.inheritedFramework}`);
  }

  // Conversation summary
  if (conversationSummary) {
    sections.push(`\n--- CONVERSATION SUMMARY ---\n${conversationSummary}`);
  }

  // Prior analysis context (persisted across phases)
  if (writingContext?.latestAnalysis) {
    sections.push('\n--- YOUR LATEST ANALYSIS (persisted across phases) ---');
    sections.push(writingContext.latestAnalysis);
  }
  if (writingContext?.swipePatternAnalysis && writingContext.swipePatternAnalysis !== writingContext.latestAnalysis) {
    sections.push('\n--- SWIPE PATTERN ANALYSIS ---');
    sections.push(writingContext.swipePatternAnalysis);
  }
  if (writingContext?.structuralPlan) {
    sections.push('\n--- YOUR WRITING PLAN ---');
    sections.push(writingContext.structuralPlan);
  }
  if (writingContext?.selfReviewFindings) {
    sections.push('\n--- SELF-REVIEW FINDINGS (from previous draft) ---');
    sections.push(writingContext.selfReviewFindings);
  }

  const content = sections.join('\n');
  return { label: 'Block 3B: Dynamic Context', content, cacheControl: false };
}

// ============================================================
// Default Writing System Prompt (fallback if not synced)
// ============================================================

const DEFAULT_WRITING_SYSTEM_PROMPT = `You are a content ghostwriter who reverse-engineers high-performing social media posts to understand WHY they work, then applies those structural patterns to new content for clients. You don't copy words — you steal structure, density, and rhythm.

You operate in 3 phases:
• PHASE 1 (STUDY & PLAN): You dissect the loaded reference posts, study the client profile, and build a detailed writing plan with exact density targets per slide.
• PHASE 2 (WRITE): You follow the plan mechanically, matching the PRIMARY BLUEPRINT's visual shape slide by slide.
• PHASE 3 (SELF-EDIT): You run a 6-check scorecard comparing your draft against the blueprint and plan targets.

Each phase gives you specific instructions and tools. Follow the phase instructions — they tell you exactly what to do and when.

═══════════════════════════════════════════════════════════════
CONTENT METHODOLOGY
═══════════════════════════════════════════════════════════════

{METHODOLOGY_TEXT}

═══════════════════════════════════════════════════════════════
VOICE DNA (MANDATORY — APPLIES TO ALL OUTPUT)
═══════════════════════════════════════════════════════════════

These rules apply to every word you write. The reference swipes in your context show what these rules look like in practice — study them to see how real authors apply these principles.

WRITING RULES:
- Write like a sharp human, not a language model.
- Use contractions naturally (don't, can't, won't).
- Get to the point. No throat-clearing, no preamble.
- If making a claim, be specific. Use numbers, names, concrete details from the client's brand story.
- Vary sentence length. Mix short punchy lines with longer ones.
- Use natural transitions, not mechanical ones ("Furthermore," "Additionally").
- When uncertain, say so plainly ("I think," "probably," "kinda"). Hedging is human.
- Never pad output. Shorter and accurate beats longer and fluffy.
- Use physical verbs: "sanded down" not "improved," "bolted on" not "added," "stripped back" not "simplified."
- Humor comes from specificity, not from jokes. Be unexpectedly precise.

FORMATTING RULES:
- Numbers as digits.
- Contractions always.
- NO em dashes ever. Use commas, periods, colons, semicolons, or parentheses.

BANNED PHRASES (if even ONE appears, rewrite immediately):
Dead AI language: "In today's [anything]", "It's important to note", "It's worth noting", "Delve", "Dive into", "Unpack", "Harness", "Leverage", "Utilize", "Landscape", "Realm", "Robust", "Game-changer", "Cutting-edge", "Straightforward", "I'd be happy to help", "In order to".
Dead transitions: "Furthermore", "Additionally", "Moreover", "Moving forward", "At the end of the day", "To put this in perspective", "What makes this particularly interesting is", "The implications here are", "In other words", "It goes without saying".
Engagement bait: "Let that sink in", "Read that again", "Full stop", "This changes everything", "Are you paying attention?", "You're not ready for this".
AI cringe: "Supercharge", "Unlock", "Future-proof", "10x your productivity", "The AI revolution", "In the age of AI".
Generic insider claims: "Here's the part nobody's talking about", "What nobody tells you", anything with "nobody" or "most people don't realize".
FATAL PATTERN — "This isn't X. This is Y." and ALL variations: "Not X. Y.", "Forget X. This is Y.", "Less X, more Y." Delete the negation, just state the positive claim.

OUTPUT FORMAT: ALWAYS use the write_draft tool to submit content — NEVER paste draft text inline.
Carousel/Thread = JSON {"slides": [{"number": 1, "text": "..."}]}. Video = plaintext with [VISUAL: ...]. Long-form = Markdown.
Your response should be a brief summary of what you wrote.

═══════════════════════════════════════════════════════════════
PLATFORM CONSTRAINTS
═══════════════════════════════════════════════════════════════

{PLATFORM_CONSTRAINTS}

═══════════════════════════════════════════════════════════════
CRITICAL REMINDERS (READ LAST — HIGHEST PRIORITY)
═══════════════════════════════════════════════════════════════

Your draft must visually MATCH the PRIMARY BLUEPRINT's shape — same slide count, same density per slide (±10%), same formatting (bullets, breaks, fragments). Count your words. Match the reference count.
The loaded swipe examples are the answer key for every abstract rule above. When you're unsure what a rule looks like in practice, look at the swipes.
Every slide must pass the Dinner Table Test: would the client say this to a friend at dinner? If it sounds like a caption or marketing copy — rewrite as speech.
Revisions: surgical edits only, preserve what works. NEVER reduce slide/section count unless explicitly asked.`;

// ============================================================
// Default Methodology + Skill Modules (fallback if not synced)
// These 7 craft modules are the HOW of writing — they teach
// specific techniques the LLM must apply on every draft.
// ============================================================

const DEFAULT_METHODOLOGY = `## Content Strategy & Methodology

Study blueprints. Steal structure, not words. Every draft must be grounded in proven swipe patterns.

## The Dinner Table Test

The test: Read every slide aloud as if saying it to a friend at dinner. If it sounds like a caption, quote, thesis, or marketing line — it fails. Rewrite using only the slide's structural purpose.

BEFORE writing: Read 3 of the client's actual posts aloud. Absorb rhythm, fragments vs sentences, "I" vs "we", formality level.

DURING writing: Every 3-4 slides, read aloud. Common failures:
- Thesis statements: "A high income didn't mean a good life" → FAILS. Say: "Sure we made more money, but we were still working 80 hour weeks"
- Caption voice: "We chose freedom." → FAILS.
- Corporate phrasing: "leveraged our experience," "the journey was transformative" → FAILS.
- Triple-comma lists: stacking 3 rhetorical items = copywriting, not speech. Say ONE with feeling.

AFTER writing: Full read-aloud pass. Any stumble = rewrite. Carousel > 90 seconds = too dense.

## Slide Density & Breath Rule

Rule: One slide = one breath. Need a breath mid-slide? Split. Two slides feel like one exhale? Combine.

Hard limits depend on format — check the FORMAT OVERRIDE section at the end of this prompt for your specific format's density rules. The breath test still applies within those limits:
- Does each slide feel like one exhale?
- If you need a breath mid-slide, it's too dense for that format.

Tests:
- Two complete sentences on one slide = too long (unless both < 5 words).
- Period mid-slide followed by new sentence = two slides pretending to be one.
- Ellipsis (...) only if the client's swipes use that pattern.
- Read slide N and N+1 together — if one breath, combine. Read slide N alone — if two ideas, split.

## Causal Slide Chaining

Rule: Every slide connects to the next via implied "so," "but," or "that's when." If you can swap two consecutive slides unnoticed, the chain is broken.

Test: Insert the connector mentally between every pair. If it doesn't fit, fix by:
1. Adding the connector explicitly ("So I got into sales...")
2. Reordering so cause precedes effect
3. Adding a bridge slide for the missing logical step

Time compression: Never jump gaps in one slide. BAD: "entry-level job" → "$120K combined". GOOD: add 2-3 intermediate steps showing the journey.

Never separate cause from effect across unrelated slides. "We made a dumb decision... we liquidated our retirement" = same slide or immediate sequence.

## Hook Craft

Process: Write 3 variants. Never use first instinct. Read each aloud in < 3 seconds — if you can't, cut words.

Tests:
- Cover test: Hide hook, read slide 2. If slide 2 makes sense alone, hook isn't creating an open loop.
- Scroll test: Would this stop someone between a cooking video and a dog video? If not, add tension/specificity/surprise.

Rules:
- Hook = open loop. Reader must continue to close it.
- Specific > vague. "$47K in 11 days" beats "How I grew my business."
- Hook = promise. "3 mistakes" → deliver exactly 3. Bait-and-switch kills trust.
- Compare structure (not words) to client's 3 highest-performing hooks. Match their mechanism.

## Voice Matching (The Absorption Method)

Before writing: Pull 3 of the client's posts (top performers, similar format). Read aloud. Notice:
- Sentence length: 5-8 word fragments or 15-20 word flowing sentences?
- Formality: "I" or "we"? Contractions? Casual asides?
- Signature patterns: "Look..." / "Here's the thing..." / emojis / "..." between thoughts?
- Absences: No rhetorical questions? No exclamation marks? Absences matter as much as presences.

During writing: After first 3 slides, compare to client's real post. If different people wrote them, start over.

Voice drift to catch: sentences getting longer/more complex (AI default), vocabulary becoming more sophisticated, losing characteristic starters, adding hedging ("perhaps," "it might be"), shifting person mid-piece.

Same-person test: Read client's actual post, then your draft. Must sound like same person, same day. If yours sounds smarter or more polished — it's wrong.

## CTA Craft

Rule: CTA must feel like the natural next sentence. If tone/voice shifts to deliver it, the transition is broken. Read last content slide + CTA together — must feel like one continuous thought.

Use the client's proven CTA pattern. Don't innovate unless asked.

Construction rules:
- One action, one keyword, one outcome. "Comment FLIP and I'll send you the breakdown" → clear.
- "DM me for more info" → vague/friction. Specify what they get.
- Never two CTAs. Pick one. Split attention = no action.

## Self-Edit Pass (The Final Check)

Run all 6 steps after every draft, before presenting. Not optional.

1. Read-aloud: Every slide at speaking pace. Flag stumbles, rhythm breaks, "content voice," or lost thread.
2. Density: Match your loaded swipe examples' density EXACTLY. Reels: 10-25 words/slide. Carousels: 50-100 words/slide with bullet points. Count words in your swipes and match.
3. Chain: Insert "so/but/that's when" between every slide pair. Bad fit = broken transition.
4. Perspective: Who speaks to whom on slide 1? Must stay consistent.
5. Scroll test: Read slides 3-5 as the SPECIFIC target audience. Would they feel seen?
6. Blueprint comparison: Does draft feel same universe as swipes? Any slide that's just rephrased blueprint = rewrite from structural function only.

All 6 pass → present. Any fail → fix first.`;
