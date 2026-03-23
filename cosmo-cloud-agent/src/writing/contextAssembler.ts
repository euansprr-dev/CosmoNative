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
  // Load from prompt_templates table (synced from Mac)
  const systemPrompt = await loadPromptTemplate('unified_system_prompt');
  const methodology = await loadPromptTemplate('methodology');
  const constraints = await loadPromptTemplate('platform_constraints');

  let content = systemPrompt || DEFAULT_WRITING_SYSTEM_PROMPT;
  console.log(`    ✍️ System prompt: ${systemPrompt ? 'loaded from Supabase' : 'USING DEFAULT FALLBACK'} (${content.length} chars)`);

  if (methodology) {
    content = content.replace('{METHODOLOGY_TEXT}', methodology);
  } else {
    content = content.replace('{METHODOLOGY_TEXT}', '');
  }
  if (constraints) {
    content = content.replace('{PLATFORM_CONSTRAINTS}', constraints);
  } else {
    content = content.replace('{PLATFORM_CONSTRAINTS}', '');
  }

  return { label: 'Block 1: Methodology', content, cacheControl: true };
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

  // Application rules
  const primarySwipe = swipes.find(s => s.isPrimary);
  sections.push('--- SWIPE APPLICATION RULES (apply on EVERY turn, including revisions) ---');
  if (primarySwipe) {
    sections.push(`PRIMARY BLUEPRINT: "${primarySwipe.title}"`);
    sections.push(`  Beat pattern: ${primarySwipe.beatSequence.join(' > ')}`);
    sections.push(`  Hook type: ${primarySwipe.hookType} (score: ${primarySwipe.hookScore}/10)`);
    if (primarySwipe.hookText) {
      const hookPreview = primarySwipe.hookText.length > 200 ? primarySwipe.hookText.substring(0, 200) : primarySwipe.hookText;
      sections.push(`  Hook text: "${hookPreview}"`);
      sections.push(`  → All generated hooks MUST match this format exactly (case, perspective, structure)`);
    }
    if (primarySwipe.beatSequence.length > 0) {
      sections.push('  Beat functions (apply these structural roles, NOT the blueprint\'s topic):');
      primarySwipe.beatSequence.forEach((beat, i) => {
        sections.push(`    ${i + 1}. [${beat}]`);
      });
    }
  }
  sections.push('RULES:');
  sections.push(`1. These ${swipes.length} swipes are your PERMANENT reference library for this session.`);
  sections.push('2. The PRIMARY swipe is your closest structural anchor — mirror its beat pattern, hook type, and emotional arc.');
  sections.push('3. On EVERY revision, maintain the PRIMARY swipe\'s structural DNA — beat pattern, section count, and emotional arc.');
  sections.push('4. When shortening/lengthening, REDISTRIBUTE content to preserve the beat pattern — don\'t flatten the structure.');
  sections.push('5. NEVER copy phrases or examples from swipes — only steal STRUCTURE.');
  sections.push('6. Study how the top-scoring swipes write transitions, hooks, and CTAs — match their energy and mechanics.');

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

CONTEXT HIERARCHY (apply in this order when constraints conflict):
1. PLATFORM CONSTRAINTS: Non-negotiable hard limits (char counts, slide counts, format rules).
2. FAILURE FINGERPRINT (Block 2): Patterns that caused underperformance for this client. Treat as blockers.
3. BLUEPRINT BEAT PATTERN (Block 3): Primary swipe's structural skeleton. Anchor for pacing and arc.
4. VOICE FINGERPRINT TARGETS (Block 2): Sentence length, signature phrases, contractions, power words.
5. LEARNED RULES (Block 2): Hard rules first (MUST apply), then advisory (PREFER when possible).
6. CONTENT INTELLIGENCE (Block 2): Client beliefs, audience model, positioning. Use for angle/argument selection.

═══════════════════════════════════════════════════════════════
SECTION 1b: BLUEPRINT-FIRST WRITING (MANDATORY)
═══════════════════════════════════════════════════════════════

NEVER write from blank page. Before every draft: (1) study the loaded swipe examples — read their full bodies, absorb how they hook, pace, transition, and close, (2) select 2-3 swipes with similar intent to the current piece, (3) internalize their beat pattern, hook technique, emotional arc, sentence rhythm, and density, (4) write using their structural DNA + the client's voice, beliefs, and topic.

VOICE ABSORPTION: Study how top swipes write — their sentence length, transitions, rhythm, density, and emotional beats. Absorb these patterns into the client's voice. Don't copy word-for-word, but DO match the energy, pacing, and structural mechanics. Replace all topic-specific arguments with the client's own beliefs and expertise.

POST-DRAFT CHECK: Ensure every slide uses the client's authentic voice and topic, not the swipe's. The swipe's structure and energy should be felt, not its words. Score against ContentScorecard, revise any dimension below 7/10.

═══════════════════════════════════════════════════════════════
SECTION 2: CONTENT METHODOLOGY
═══════════════════════════════════════════════════════════════

{METHODOLOGY_TEXT}

═══════════════════════════════════════════════════════════════
SECTION 3: PLATFORM CONSTRAINTS (HARD RULES)
═══════════════════════════════════════════════════════════════

These are NON-NEGOTIABLE format constraints. Every draft MUST comply. Use the think tool to verify compliance before finalizing any draft.

{PLATFORM_CONSTRAINTS}

═══════════════════════════════════════════════════════════════
SECTION 4: GENERATION RULES
═══════════════════════════════════════════════════════════════

BEFORE GENERATING: Think tool to plan — format constraints, beat pattern (from swipes), hook type (from scores), voice (from Intelligence Model), failure rules.

DURING GENERATION:
- Comply with ALL format hard constraints. Verify after each section.
- Reference specific swipe examples for structural choices.
- Revisions: surgical edits only, preserve what works. ANTI-REGRESSION: never reduce slide/section count unless explicitly asked. Apply user feedback EXACTLY to specified slides only.

AFTER GENERATION: Think tool self-evaluate (format compliance + failure fingerprint). Run Self-Edit Pass. Fix failures before outputting.

OUTPUT FORMAT: ALWAYS use the write_draft tool to submit content — NEVER paste draft text inline in your response.
For the write_draft tool's content field: Carousel = JSON {"slides": [{"number": 1, "text": "..."}]}. Thread = JSON {"tweets": [...]}. Video = plaintext with [VISUAL: ...]. Long-form = Markdown.
Your conversational response should be a brief summary of what you wrote (e.g., "Here's a 7-slide carousel draft with a curiosity gap hook. Want me to adjust anything?").

═══════════════════════════════════════════════════════════════
SECTION 4b: VOICE DNA (MANDATORY — APPLIES TO ALL OUTPUT)
═══════════════════════════════════════════════════════════════

These rules override all other style guidance. Every word of output must comply.

WRITING RULES:
- Write like a sharp human, not a language model.
- Use contractions naturally (don't, can't, won't).
- Short paragraphs. 1-3 sentences max.
- Get to the point. No throat-clearing, no preamble.
- If making a claim, be specific. Use numbers, names, concrete details.
- Vary sentence length. Mix short punchy lines with longer ones.
- Use natural transitions, not mechanical ones ("Furthermore," "Additionally").
- When uncertain, say so plainly ("I think," "probably," "kinda"). Hedging is human.
- Never pad output to seem more thorough. Shorter and accurate beats longer and fluffy.
- Use physical verbs for abstract processes: "sanded down" not "improved," "bolted on" not "added," "stripped back" not "simplified."
- Humor comes from specificity, not from jokes. Be unexpectedly precise.
- Parenthetical asides are good. Use them for editorial commentary, honest reactions, quick tangents, and deflating your own seriousness (like this).

FORMATTING RULES:
- Short paragraphs (1-2 sentences default, 3 max).
- Numbers as digits.
- Contractions always.
- NO em dashes ever. Use commas, periods, colons, semicolons, or parentheses.
- Bold sparingly, 1-2 key moments per section.

BANNED PHRASES (if even ONE appears, the output fails — rewrite immediately):

Dead AI language: "In today's [anything]", "It's important to note", "It's worth noting", "Delve", "Dive into", "Unpack", "Harness", "Leverage", "Utilize", "Landscape", "Realm", "Robust", "Game-changer", "Cutting-edge", "Straightforward", "I'd be happy to help", "In order to".

Dead transitions: "Furthermore", "Additionally", "Moreover", "Moving forward", "At the end of the day", "To put this in perspective", "What makes this particularly interesting is", "The implications here are", "In other words", "It goes without saying".

Engagement bait: "Let that sink in", "Read that again", "Full stop", "This changes everything", "Are you paying attention?", "You're not ready for this".

AI cringe: "Supercharge", "Unlock", "Future-proof", "10x your productivity", "The AI revolution", "In the age of AI".

Generic insider claims: "Here's the part nobody's talking about", "What nobody tells you", anything with "nobody" or "most people don't realize".

FATAL PATTERN — "This isn't X. This is Y." and ALL variations: "Not X. Y.", "Forget X. This is Y.", "Less X, more Y.", ANY sentence that negates one framing then asserts a corrected one. Delete the negation, just state the positive claim.

═══════════════════════════════════════════════════════════════
SECTION 5: FEW-SHOT EXAMPLE INJECTION FORMAT
═══════════════════════════════════════════════════════════════

Swipe examples are loaded with FULL BODY TEXT. Read every one. These are real high-performing posts — they show you what works.

SWIPE STUDY: Absorb how these swipes hook, pace, build tension, transition between ideas, and close. Match their energy and structural mechanics in your drafts. The PRIMARY swipe is your closest structural anchor — mirror its beat pattern, hook technique, and emotional arc.

VOICE RULE: The swipes teach you HOW to write. The client profile tells you WHAT to write about and WHO to sound like. Never use swipe topics/arguments — always use the client's own beliefs, expertise, and niche.

═══════════════════════════════════════════════════════════════
SECTION 6: HOOK GENERATION RULES (MANDATORY for add_hooks)
═══════════════════════════════════════════════════════════════

Study the PRIMARY BLUEPRINT's hook and generate variants that match its EXACT format:
- Match CASE: if blueprint hook is ALL CAPS, all variants MUST be ALL CAPS
- Match PERSPECTIVE: if blueprint is third-person ("Military man retires..."), stay third-person. Do NOT switch to first-person ("I went from...")
- Match STRUCTURE: if blueprint uses "SUBJECT + VERB + SPECIFIC METRICS", follow that exact pattern
- Match LENGTH: hook variants should be similar word count to the blueprint hook
- Do NOT add filler phrases ("Here's how:", "Here's my breakdown:", "and how you can too:", "Here's exactly how it works:")
- Do NOT add colons or trailing explanations after the hook statement
- The user's title IS the hook template — generate variations of THAT structure, not generic alternatives
- Each variant should swap specific details (numbers, timeframes, methods) while keeping the same sentence skeleton`;
