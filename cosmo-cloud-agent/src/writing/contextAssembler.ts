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

export interface WritingBlock {
  label: string;
  content: string;
  cacheControl: boolean;
}

// ============================================================
// Block 1: Methodology + System Prompt
// ============================================================

export async function assembleBlock1(format: ContentFormat): Promise<WritingBlock> {
  // Load from prompt_templates table (synced from Mac)
  const systemPrompt = await loadPromptTemplate('unified_system_prompt');
  const methodology = await loadPromptTemplate('methodology');
  const constraints = await loadPromptTemplate('platform_constraints');

  let content = systemPrompt || DEFAULT_WRITING_SYSTEM_PROMPT;

  if (methodology) {
    content = content.replace('{METHODOLOGY_TEXT}', methodology);
  }
  if (constraints) {
    content = content.replace('{PLATFORM_CONSTRAINTS}', constraints);
  }

  return { label: 'Block 1: Methodology', content, cacheControl: true };
}

// ============================================================
// Block 2: Client Intelligence
// ============================================================

export async function assembleBlock2(
  clientAtom: Atom | null,
  lessons: Array<{ rule: string; enforcement: string }>,
): Promise<WritingBlock> {
  if (!clientAtom) {
    return { label: 'Block 2: Client', content: '[No client profile loaded]', cacheControl: true };
  }

  const meta = clientAtom.metadata || {};
  const structured = clientAtom.structured || {};
  const intel = structured.intelligenceModel || {};
  const voice = intel.voiceFingerprint || {};

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
  }

  // Failure fingerprint (hard rules from past edits)
  const failureRules = intel.failureRules as any[] | undefined;
  if (failureRules && failureRules.length > 0) {
    sections.push('\n--- FAILURE FINGERPRINT (HARD RULES — never violate) ---');
    const highRules = failureRules.filter((r: any) => r.severity === 'HIGH');
    const medRules = failureRules.filter((r: any) => r.severity === 'MEDIUM').slice(0, 3);
    for (const rule of [...highRules, ...medRules]) {
      sections.push(`  [${rule.severity}] ${rule.rule || rule.description}`);
    }
  }

  // Learned lesson rules (RULE/BAD/GOOD/WHY format matching Swift's optimized instructions)
  if (lessons.length > 0) {
    const hardRules = lessons.filter(l => l.enforcement === 'hard').slice(0, 10);
    const advisoryRules = lessons.filter(l => l.enforcement !== 'hard').slice(0, 5);

    if (hardRules.length > 0) {
      sections.push('\n--- LEARNED WRITING RULES — MANDATORY (HARD) ---');
      sections.push('Violating ANY of these triggers revision.');
      for (let i = 0; i < hardRules.length; i++) {
        const r = hardRules[i];
        // If rule has RULE/BAD/GOOD format, use it directly
        if (r.rule.includes('RULE:') || r.rule.includes('BAD:') || r.rule.includes('\n')) {
          sections.push(`\n${i + 1}. ${r.rule}`);
        } else {
          sections.push(`\n${i + 1}. RULE: ${r.rule}`);
        }
      }
    }

    if (advisoryRules.length > 0) {
      sections.push('\n--- LEARNED WRITING PREFERENCES — ADVISORY ---');
      for (let i = 0; i < advisoryRules.length; i++) {
        sections.push(`  ${i + 1}. ${advisoryRules[i].rule}`);
      }
    }
  }

  // Brand story
  if (structured.brandStory) {
    sections.push(`\n--- BRAND STORY ---\n${structured.brandStory}`);
  }

  // Voice guide
  if (structured.voiceNotes) {
    sections.push(`\n--- VOICE GUIDE ---\n${structured.voiceNotes}`);
  }

  const content = sections.join('\n');

  // Cap at 200K chars (matching Swift)
  const capped = content.length > 200_000 ? content.substring(0, 200_000) + '\n... [truncated]' : content;

  return { label: 'Block 2: Client Intelligence', content: capped, cacheControl: true };
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

  // Swipe examples
  sections.push(`\n--- SAME-TYPE SWIPE EXAMPLES (${swipes.length} selected) ---`);
  for (const swipe of swipes) {
    sections.push(formatCompressedSwipe(swipe));
    sections.push(''); // Blank line separator
  }

  // Application rules
  const primarySwipe = swipes.find(s => s.isPrimary);
  sections.push('--- SWIPE APPLICATION RULES (apply on EVERY turn) ---');
  if (primarySwipe) {
    sections.push(`PRIMARY BLUEPRINT: "${primarySwipe.title}"`);
    sections.push(`  Beat pattern: ${primarySwipe.beatSequence.join(' > ')}`);
    sections.push(`  Hook type: ${primarySwipe.hookType} (score: ${primarySwipe.hookScore}/10)`);
  }
  sections.push('RULES:');
  sections.push(`1. These ${swipes.length} swipes are your PERMANENT reference library for this session.`);
  sections.push('2. PRIMARY swipe is your closest structural anchor — mirror its section count, beat progression, and density.');
  sections.push('3. NEVER copy phrases or examples from swipes — only steal STRUCTURE.');
  sections.push('4. Every hook must match the blueprint\'s hook TYPE and approximate its word count.');
  sections.push('5. Every section must serve the same FUNCTION as its corresponding beat in the blueprint.');
  sections.push('6. If the blueprint has N sections, your draft should have approximately N sections.');

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

export function assembleBlock3Dynamic(
  contentAtom: Atom,
  outline: OutlineItem[] | null,
  hooks: string[] | null,
  conversationSummary: string | null,
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

  const content = sections.join('\n');
  return { label: 'Block 3B: Dynamic Context', content, cacheControl: false };
}

// ============================================================
// Default Writing System Prompt (fallback if not synced)
// ============================================================

const DEFAULT_WRITING_SYSTEM_PROMPT = `You are a world-class content ghostwriter operating inside the CosmoOS unified writing engine.

You have access to writing tools: think, update_outline, add_hooks, write_draft, edit_section, read_draft, run_scorecard, search_swipes, read_swipe_body, read_client_post, list_client_posts, get_client_profile, analyze_swipe_patterns, set_title, set_description.

BLUEPRINT-FIRST METHODOLOGY:
1. Study the PRIMARY BLUEPRINT swipe's structure — section count, beat progression, density
2. Extract the skeleton: what function does each section serve?
3. Write YOUR content following that skeleton
4. NEVER copy phrases — only steal STRUCTURE

WRITING RULES:
- Write the COMPLETE draft via write_draft tool — NEVER write inline
- No generic openers ("In today's world...")
- No filler verbs ("delve", "leverage", "unleash", "unlock")
- Use read_draft before revising to see the full current draft
- Apply ONLY requested changes during revision — preserve everything else
- Output COMPLETE drafts — never partial sections

{METHODOLOGY_TEXT}

{PLATFORM_CONSTRAINTS}`;
