// cosmo-cloud-agent/src/writing/engine.ts
// Cloud Writing Engine — agentic conversation loop with inner tools
// PORTING SOURCE: UnifiedWritingEngine.swift
//
// ONE continuous conversation per content piece.
// Phases: Brainstorm → Draft → Polish
// Inner tools: think, update_outline, add_hooks, write_draft, read_draft, etc.

import { config } from '../config';
import { Atom, fetchAtom, updateAtom, fetchAllByType, fuzzyFindClient, loadPromptTemplate } from '../db/queries';
import { selectSwipes } from './swipeSelector';
import { assembleBlock1, assembleBlock2, assembleBlock3Stable, assembleBlock3Dynamic, getSwipeApplicationRules, WritingBlock } from './contextAssembler';
import {
  WritingPhase, WritingMessage, CompressedSwipe, OutlineItem, HookVariant,
  ContentFormat, detectContentFormat, renderDraftForDisplay, validateDraft,
} from './types';

const MAX_INNER_ITERATIONS = 10;

// ============================================================
// Engine Cache (matches Swift: max 3 engines, 30min TTL)
// ============================================================

interface CachedEngine {
  engine: CloudWritingEngine;
  lastUsed: number;
}

const engineCache = new Map<string, CachedEngine>();

export async function getOrCreateEngine(contentUUID: string): Promise<CloudWritingEngine> {
  // Evict stale engines
  const now = Date.now();
  for (const [key, cached] of engineCache) {
    if (now - cached.lastUsed > config.engineCacheTTLMs) {
      engineCache.delete(key);
    }
  }

  // Evict oldest if at capacity
  if (engineCache.size >= config.maxCachedEngines && !engineCache.has(contentUUID)) {
    let oldestKey = '';
    let oldestTime = Infinity;
    for (const [key, cached] of engineCache) {
      if (cached.lastUsed < oldestTime) {
        oldestTime = cached.lastUsed;
        oldestKey = key;
      }
    }
    if (oldestKey) engineCache.delete(oldestKey);
  }

  // Return cached engine if it exists — conversation context persists across phases
  // Only evicted on explicit evictEngine() call or TTL expiry
  const existing = engineCache.get(contentUUID);
  if (existing) {
    existing.lastUsed = now;
    console.log(`  ✍️ Reusing cached engine for ${contentUUID} (${existing.engine.getSwipeCount()} swipes, conversation preserved)`);
    return existing.engine;
  }

  const engine = new CloudWritingEngine(contentUUID);
  engineCache.set(contentUUID, { engine, lastUsed: now });
  return engine;
}

export function evictEngine(contentUUID: string): void {
  engineCache.delete(contentUUID);
}

// ============================================================
// Cloud Writing Engine
// ============================================================

export class CloudWritingEngine {
  private contentUUID: string;
  private contentAtom: Atom | null = null;
  private clientAtom: Atom | null = null;
  private selectedSwipes: CompressedSwipe[] = [];
  private blocks: WritingBlock[] = [];
  private messages: WritingMessage[] = [];
  private outline: OutlineItem[] = [];
  private hooks: string[] = [];
  private conversationSummary: string | null = null;
  private initialized = false;
  private targetFormat: ContentFormat = 'unknown';

  // Reference material cache — persists across turns, 25K char budget
  private referenceMaterial: Map<string, string> = new Map();
  private referenceMaterialChars = 0;
  private static readonly REFERENCE_MATERIAL_MAX_CHARS = 25_000;

  // Lessons (cached for deterministic validation)
  private lessons: Array<{ rule: string; enforcement: string; evidence?: string; category?: string; clientUUID?: string }> = [];

  // Auto-refinement counter (max 2 passes)
  private refinementCount = 0;

  // 3-phase pipeline: writing plan created in Phase 1, used in Phases 2-3
  private writingPlan: string | null = null;

  // Blueprint anchor — resolved in initialize() (true primary or highest-scoring fallback)
  private blueprintAnchor: CompressedSwipe | null = null;
  private hasTruePrimaryBlueprint = false;

  // Deep analysis tracking — gates outline/draft/hooks behind substantive thinking
  // Uses analysisDepth as single gate (no boolean flags — they caused bypass-on-revision bugs)
  private analysisDepth = 0;
  private hasCompletedSelfReview = false;
  private writingContext: import('./contextAssembler').WritingContext = {};

  constructor(contentUUID: string) {
    this.contentUUID = contentUUID;
  }

  // ============================================================
  // Initialize
  // ============================================================

  async initialize(): Promise<void> {
    if (this.initialized) return;

    // Load content atom
    this.contentAtom = await fetchAtom(this.contentUUID);
    if (!this.contentAtom) throw new Error(`Content not found: ${this.contentUUID}`);

    // Detect format
    this.targetFormat = detectContentFormat(this.contentAtom.metadata);

    // Load client profile
    const clientUUID = this.contentAtom.metadata?.clientProfileUUID as string | undefined;
    if (clientUUID) {
      this.clientAtom = await fetchAtom(clientUUID);
    }

    // Load existing outline/hooks from metadata
    const meta = this.contentAtom.metadata || {};
    if (meta.outline && Array.isArray(meta.outline)) {
      this.outline = meta.outline as OutlineItem[];
    }
    if (meta.hooks && Array.isArray(meta.hooks)) {
      this.hooks = meta.hooks as string[];
    } else if (meta.inheritedHooks && Array.isArray(meta.inheritedHooks)) {
      this.hooks = meta.inheritedHooks as string[];
    }

    // Restore persisted conversation + writing context
    const structured = this.contentAtom.structured || {};
    if (structured.writingConversation && Array.isArray(structured.writingConversation)) {
      this.messages = structured.writingConversation as WritingMessage[];
    }
    if (structured.writingContext) {
      this.writingContext = structured.writingContext as import('./contextAssembler').WritingContext;
      this.analysisDepth = this.writingContext.analysisDepth || 0;
      this.writingPlan = this.writingContext.writingPlan || null;
      // analysisDepth persists across phases — no boolean flags needed
      // If LLM did deep analysis in outline phase, gates stay open for draft phase
    }

    // Select swipes — use stored selection if available (persists across engine re-creation)
    const storedSwipeUUIDs = meta.selectedSwipeUUIDs as string[] | undefined;
    if (storedSwipeUUIDs && storedSwipeUUIDs.length > 0) {
      // Re-load the SAME swipes from a previous session (not random re-selection)
      this.selectedSwipes = await this.loadSpecificSwipes(storedSwipeUUIDs, (meta.inheritedSwipeUUIDs as string[]) || []);
      console.log(`  ✍️ Restored ${this.selectedSwipes.length} swipes from previous session`);
    } else {
      // First-time selection — weighted random sampling
      const primaryUUIDs = (meta.inheritedSwipeUUIDs as string[]) || [];
      this.selectedSwipes = await selectSwipes(this.contentAtom, this.targetFormat, primaryUUIDs);
      // Persist selection for future re-initialization
      const selectedUUIDs = this.selectedSwipes.map(s => s.uuid);
      await updateAtom(this.contentUUID, { metadata: { selectedSwipeUUIDs: selectedUUIDs } });
    }

    // Resolve blueprint anchor — true primary or highest-scoring fallback
    const primary = this.selectedSwipes.find(s => s.isPrimary);
    if (primary && primary.fullBody) {
      this.blueprintAnchor = primary;
      this.hasTruePrimaryBlueprint = true;
    } else {
      const fallback = this.selectedSwipes
        .filter(s => s.fullBody)
        .reduce<CompressedSwipe | null>((best, s) => (!best || s.hookScore > best.hookScore) ? s : best, null);
      this.blueprintAnchor = fallback;
      this.hasTruePrimaryBlueprint = false;
    }

    // Load lessons for this client (also cached for deterministic validation in write_draft)
    const lessons = await this.loadLessons();
    this.lessons = lessons;

    // Load experience buffer (past edit examples) for few-shot learning
    const experiences = await this.loadExperiences();

    // Build blocks
    const block1 = await assembleBlock1(this.targetFormat);
    const block2 = await assembleBlock2(this.clientAtom, lessons);
    const block3a = assembleBlock3Stable(
      this.selectedSwipes,
      this.clientAtom?.metadata?.niche as string | null || null,
      experiences,
    );

    this.blocks = [block1, block2, block3a];
    this.initialized = true;

    console.log(`  ✍️ Writing engine initialized: ${this.selectedSwipes.length} swipes, ${lessons.length} lessons, ${experiences.length} experiences, client: ${this.clientAtom?.title || 'none'}, format: ${this.targetFormat}`);
  }

  // ============================================================
  // Send Message (Main Entry Point)
  // ============================================================

  /**
   * Send a user message and run the writing conversation loop.
   * Returns the final assistant response text.
   */
  async sendMessage(instruction: string, phase: WritingPhase): Promise<string> {
    await this.initialize();
    if (!this.contentAtom) throw new Error('Engine not initialized');

    // Refresh content atom for latest state
    this.contentAtom = await fetchAtom(this.contentUUID) || this.contentAtom;

    // Log context state for every phase (not just init)
    console.log(`  ✍️ Phase: ${phase}, messages: ${this.messages.length}, client: ${this.clientAtom?.title || 'none'}, analysisDepth: ${this.analysisDepth}, swipes: ${this.selectedSwipes.length}`);

    // Reset self-review flag for new draft requests
    if (phase === 'draft') {
      this.hasCompletedSelfReview = false;
    }

    // Draft phase uses 3-phase pipeline (Plan → Write → Self-Edit)
    if (phase === 'draft' && !this.writingPlan) {
      return this.runDraftPipeline(instruction);
    }

    // Brainstorm/polish/revision use normal conversation loop
    const block3b = this.buildDynamicBlock();

    this.messages.push({
      id: crypto.randomUUID(),
      role: 'user',
      content: instruction,
      timestamp: new Date().toISOString(),
    });

    const result = await this.runConversationLoop(phase, block3b);
    await this.persistConversation();
    return result;
  }

  private buildDynamicBlock(): WritingBlock {
    return assembleBlock3Dynamic(
      this.contentAtom!,
      this.outline.length > 0 ? this.outline : null,
      this.hooks.length > 0 ? this.hooks : null,
      this.conversationSummary,
      this.writingContext,
    );
  }

  // ============================================================
  // 3-Phase Draft Pipeline (Plan → Write → Self-Edit)
  // ============================================================

  private async runDraftPipeline(instruction: string): Promise<string> {
    const bp = this.blueprintAnchor;
    console.log(`\n  ═══ DRAFT PIPELINE START ═══`);
    console.log(`  📋 Client: ${this.clientAtom?.title || 'none'} | Format: ${this.targetFormat} | Swipes: ${this.selectedSwipes.length}`);
    console.log(`  📋 Blueprint: ${bp ? `"${bp.title.substring(0, 60)}" (${this.hasTruePrimaryBlueprint ? 'TRUE PRIMARY' : 'INFERRED — highest hookScore'}, score: ${bp.hookScore}/10)` : 'NONE'}`);
    if (bp?.beatSequence.length) console.log(`  📋 Blueprint beats: ${bp.beatSequence.join(' > ')}`);
    console.log(`  📋 Lessons: ${this.lessons.length} (${this.lessons.filter(l => l.enforcement === 'hard').length} hard, ${this.lessons.filter(l => l.enforcement !== 'hard').length} advisory)`);
    console.log(`  📋 Blocks: ${this.blocks.map(b => `${b.label}(${(b.content.length / 1024).toFixed(0)}KB${b.cacheControl ? ',cached' : ''})`).join(' + ')}`);

    // PHASE 1: PLAN — full context, create comprehensive writing plan
    console.log(`\n  ✍️ ─── Phase 1: PLAN ───`);
    console.log(`  ✍️ System blocks: ${this.blocks.length} (${this.blocks.map(b => b.label).join(', ')})`);
    console.log(`  ✍️ Tools: think, create_writing_plan, search_swipes, read_swipe_body, analyze_swipe_patterns`);
    console.log(`  ✍️ Goal: LLM studies swipes (beat map, density, format, hook anatomy) → absorbs client → creates writing plan`);
    await this.runPlanPhase(instruction);

    if (!this.writingPlan) {
      console.log('  ⚠️ No writing plan created — falling back to normal conversation loop');
      const block3b = this.buildDynamicBlock();
      this.messages.push({ id: crypto.randomUUID(), role: 'user', content: instruction, timestamp: new Date().toISOString() });
      const result = await this.runConversationLoop('draft', block3b);
      await this.persistConversation();
      return result;
    }

    // PHASE 2: WRITE — plan + swipe examples context, focused draft
    console.log(`\n  ✍️ ─── Phase 2: WRITE ───`);
    console.log(`  ✍️ Tools: think, write_draft, read_draft`);
    console.log(`  ✍️ Goal: LLM follows plan slide-by-slide, matches blueprint shape, checks word counts ±10%`);
    await this.runWritePhase();

    const draftBody = this.contentAtom?.body || '';
    const draftWords = draftBody.split(/\s+/).filter(Boolean).length;
    const draftSlides = (draftBody.match(/^Slide \d+/gim) || []).length || (draftBody.match(/^[-=]{3,}$/gm) || []).length + 1;
    console.log(`  ✍️ Draft written: ${draftWords} words, ~${draftSlides} slides`);

    // PHASE 3: SELF-EDIT — plan + skill modules + lessons, quality pass
    console.log(`\n  ✍️ ─── Phase 3: SELF-EDIT ───`);
    console.log(`  ✍️ Tools: think, write_draft, read_draft`);
    console.log(`  ✍️ Goal: LLM runs 6-check scorecard (slide count, density, visual format, voice, specificity, hook format)`);
    const result = await this.runSelfEditPhase();

    const finalBody = this.contentAtom?.body || '';
    const finalWords = finalBody.split(/\s+/).filter(Boolean).length;
    console.log(`\n  ═══ DRAFT PIPELINE COMPLETE ═══`);
    console.log(`  📋 Final draft: ${finalWords} words`);
    console.log(`  📋 Messages in conversation: ${this.messages.length}`);

    await this.persistConversation();
    return result;
  }

  private async runPlanPhase(instruction: string): Promise<string> {
    const label = this.getBlueprintLabel();
    const clientName = this.clientAtom?.title || 'the client';

    const planInstruction = `${instruction}

═══ PHASE 1: STUDY & PLAN ═══

You're about to write a ${this.targetFormat} for ${clientName}. Before you write a single word, you need to reverse-engineer what makes the loaded reference posts work. You're not reading for enjoyment — you're dissecting a machine to understand how each part creates the output. Then you'll build a plan so detailed that writing becomes mechanical execution.

Use the think tool for each step below. Do not skip steps or combine them — each builds on the last.

────────────────────────────────────────
STEP 1: DISSECT THE ${label}
────────────────────────────────────────

Find the swipe labeled [${label}] in your loaded examples. This is the post your draft must structurally ${this.hasTruePrimaryBlueprint ? 'mirror' : 'use as its primary reference'}. Open it and work through this analysis:

1a. SLIDE COUNT
    Go through the ${label}'s body text. Each "Slide N" marker (or separator like ---) is a new slide.
    Write down the total: "The ${label} has N slides."

1b. BEAT MAP
    For each slide, identify its FUNCTION — what job does this slide do in the post?
    Common beat functions: Hook (grabs attention), Context (sets the scene), Teach (delivers a lesson), Prove (gives evidence/numbers), Story (personal narrative), Reframe (shifts perspective), Reveal (surprise/twist), CTA (call to action).

    Write it out like this:
      Slide 1 = [Hook] — opens with a surprising claim
      Slide 2 = [Context] — explains how they got here
      Slide 3 = [Teach] — first actionable point
      ...

    This beat map is the skeleton of your draft. Your draft will have the SAME number of slides with the SAME beat functions in the SAME order.

1c. DENSITY MEASUREMENT
    For slides 1, 3, the middle slide, and the last slide of the ${label}, count:
    - Words: split the text by spaces and count. Write the number.
    - Sentences: count the periods, question marks, and exclamation marks. Write the number.
    - Lines: count the line breaks within the slide. Write the number.

    This gives you your density target per slide position. These aren't guidelines — they're exact targets your draft must hit (±10%).

1d. VISUAL FORMAT
    Look at the ${label}'s slides as if they were images. For each slide, note:
    - Does it use bullet points (-- dashes or • bullets)? How many?
    - Are there line breaks WITHIN the slide separating ideas? How many?
    - Are sentences short fragments (5-8 words) or longer flowing sentences (15+ words)?
    - Is anything in ALL CAPS?
    - Is it one dense paragraph, or does it breathe with whitespace?

    Write a format tag for each slide: e.g., "Slide 3 = 4 bullet points with -- dashes, short fragments, line break between each"

1e. HOOK ANATOMY
    Look at the ${label}'s slide 1 (the hook) and answer EXACTLY:
    - Case: Is it ALL CAPS, Title Case, or lowercase?
    - Person: Is it first-person ("I did X"), third-person ("Man does X"), or second-person ("You can X")?
    - Structure: What's the sentence skeleton? (e.g., "SUBJECT + VERB + SPECIFIC METRIC + TIMEFRAME")
    - Word count: How many words?
    - Does it end with a period, no punctuation, or an ellipsis?

    Your hook must match ALL of these properties. Different words, same skeleton.

1f. TRANSITIONS
    Read slide 2, then slide 3. What's the invisible connector? Try inserting "so...", "but...", "and that's when...", or "here's the thing..." between them. One of those should fit naturally. If none fits, the slides might use a different chaining method (numbered list, chronological, or emotional escalation).

    Do this for 3-4 consecutive slide pairs. Note the pattern — this is how your draft will flow between slides.

────────────────────────────────────────
STEP 2: CROSS-REFERENCE OTHER SWIPES
────────────────────────────────────────

Now scan 3-5 of the other loaded swipes. You're not studying them as deeply — you're CALIBRATING.

2a. DENSITY RANGE
    Pick 3 swipes. Count words in their slide 1, middle slide, and last slide.
    Now you have a range. The ${label}'s density is your TARGET. The range tells you what's acceptable vs what's too thin or too dense.

2b. FORMAT DNA
    Look across all swipes. What formatting patterns appear in MOST of them?
    - Do most use line breaks within slides? → That's a format requirement.
    - Do most use -- dashes for lists? → That's a format requirement.
    - Do most keep sentences under 15 words? → That's a format requirement.
    Things that only appear in 1-2 swipes are that author's style. Things that appear in 5+ swipes are the FORMAT'S DNA — your draft must have them.

2c. WHAT SWIPES TEACH ABOUT THE RULES
    The swipes are the best demonstration of how all the rules in your system context (Voice DNA, methodology, banned phrases, density guidelines) actually look in practice. When a rule says "use physical verbs" — look at the swipes to see WHICH physical verbs real authors use. When Voice DNA says "vary sentence length" — look at the swipes to see the ACTUAL range (e.g., 4-word fragments mixed with 18-word sentences). The swipes are the answer key for every abstract rule in your system prompt.

────────────────────────────────────────
STEP 3: ABSORB THE CLIENT
────────────────────────────────────────

Now look at the CLIENT PROFILE section in your context. This is who you're writing AS.

3a. REAL DETAILS
    Read the brand story. Pull out every specific detail you'll use in the draft:
    - Names (people, businesses, places)
    - Numbers (revenue, properties, years, ages, dollar amounts)
    - Dates and timeframes
    - Locations
    Write them down. These are MANDATORY inclusions — a draft without the client's real details is generic and fails. Don't make up details when real ones are loaded.

3b. VOICE FINGERPRINT
    Read the voice targets. The key numbers:
    - Target sentence length: ____ words. This is your average — some shorter, some longer.
    - Banned phrases: List them. Memorize them. If even ONE appears in your draft, rewrite.
    - Signature phrases: These should appear 2-3 times naturally in the draft.

    Now read the client's TOP PERFORMING POSTS (also in the client profile). Read them as if you're the client. Notice how THEY talk — their rhythm, their word choices, their level of formality. Your draft must sound like the same person wrote it on the same day.

3c. LESSONS
    Read the LEARNED WRITING RULES. Hard rules are non-negotiable — violating them means an automatic rewrite. Advisory rules are strong preferences. For each hard rule, think about how it applies specifically to THIS draft. A rule like "never use more than 2 rhetorical questions per post" means you need to COUNT your rhetorical questions.

────────────────────────────────────────
STEP 4: BUILD THE WRITING PLAN
────────────────────────────────────────

Now you have all the data. Call create_writing_plan with a plan structured EXACTLY like this:

STRUCTURAL TEMPLATE
For EACH slide (same count as ${label}), write:
  Slide N: [beat function from your beat map]
  Words: [target from your density measurement] | Sentences: [target] | Lines: [target]
  Format: [from your visual format analysis — bullets? breaks? fragments?]
  Content: [what specific information goes here — cite real client details by name]
  Transition to next: [the connector type you identified]

VOICE RULES
  Target sentence length: ___
  Signature phrases to include: ___
  BANNED (instant rewrite): ___
  Tone match: [describe based on the client's real posts, not generic adjectives]

HARD RULES THAT APPLY
  List every hard lesson. For each one, note how it applies to THIS draft specifically.

HOOK SPECIFICATION
  Case: ___ | Person: ___ | Structure: ___ | Words: ___ | Ending: ___
  (from your Step 1e analysis)

DENSITY TARGETS
  [List the exact word count per slide position from your Step 1c measurement]

This plan is your construction blueprint. Phase 2 will follow it slide by slide.`;

    this.messages.push({ id: crypto.randomUUID(), role: 'user', content: planInstruction, timestamp: new Date().toISOString() });

    // Run with plan-phase tools (think + create_writing_plan + swipe tools — NO write_draft)
    const block3b = this.buildDynamicBlock();
    return this.runConversationLoop('draft', block3b, 'plan');
  }

  private async runWritePhase(): Promise<string> {
    // Swap system prompt to plan + swipe examples (focused context)
    const originalBlocks = this.blocks;

    const planBlock: WritingBlock = {
      label: 'Writing Plan',
      content: `═══ YOUR WRITING PLAN ═══\nFollow this plan EXACTLY. Every detail was derived from studying 20 high-performing examples + client profile + learned rules.\n\n${this.writingPlan}`,
      cacheControl: true,
    };

    const examplesBlock: WritingBlock = {
      label: 'Reference Examples',
      content: this.buildSwipeReferenceBlock(),
      cacheControl: true,
    };

    // Keep Block 1 (methodology + system prompt + density override) and Block 2 (client intelligence)
    // as prefix — they're already cached from Phase 1 (Anthropic prefix caching = cache hit).
    // Without these, the LLM has no writing methodology, no client voice, no brand story.
    this.blocks = [originalBlocks[0], originalBlocks[1], planBlock, examplesBlock];
    console.log(`  ✍️ Write phase blocks: ${this.blocks.map(b => `${b.label}(${(b.content.length / 1024).toFixed(0)}KB)`).join(' + ')}`);

    this.messages.push({
      id: crypto.randomUUID(),
      role: 'user',
      content: `Your writing plan is ready. Now write the draft.

You are a ghostwriter. Your job is to produce a draft that LOOKS and FEELS like the loaded reference posts, but talks about ${this.clientAtom?.title || 'the client'}'s topic using their voice. The plan you created tells you exactly what to write in each slide. Follow it mechanically.

────────────────────────────────────────
HOW TO WRITE EACH SLIDE
────────────────────────────────────────

Work through your plan slide by slide. For each slide:

1. READ YOUR PLAN ENTRY for this slide. It tells you: the beat function, the target word count, the target sentence count, the visual format, and the specific content.

2. LOOK AT THE CORRESPONDING SLIDE in the ${this.getBlueprintLabel()}. Your slide must MATCH ITS SHAPE:
   - If the ${this.getBlueprintLabel()}'s slide 3 has 4 short lines separated by line breaks → yours has 4 short lines separated by line breaks
   - If the ${this.getBlueprintLabel()}'s slide 5 is a dense paragraph with 3 sentences → yours is a dense paragraph with 3 sentences
   - If the ${this.getBlueprintLabel()} uses -- dashes for a list → you use -- dashes for a list
   The shape is the blueprint. You're filling it with different words.

3. WRITE THE SLIDE using the client's voice. Use their real details from the brand story (names, numbers, places — from your plan). Use their signature phrases where they fit naturally. Keep sentences close to the target length from the voice fingerprint.

4. CHECK THE WORD COUNT. Your plan says "Slide 3: 47 words." Count the words you wrote. If you wrote 62 words, cut 15. If you wrote 31 words, add detail. The tolerance is ±10% — for a 47-word target, that's 42-52 words.

5. READ IT AS THE CLIENT. Would ${this.clientAtom?.title || 'the client'} say this exact thing to a friend at dinner? If it sounds like a caption, a thesis statement, or marketing copy — it fails the Dinner Table Test. Rewrite it as speech.

────────────────────────────────────────
THE VISUAL SHAPE TEST
────────────────────────────────────────

After writing the full draft, imagine printing your draft and the ${this.getBlueprintLabel()} side by side. Squint so you can't read the words — you can only see the SHAPES. The blocks of text, the whitespace, the line breaks, the bullet indentation.

They should look like the same document. Same number of sections. Same density per section. Same rhythm of short-lines-then-long-lines or dense-paragraph-then-breathing-space.

The words are different. The visual shape is identical.

────────────────────────────────────────
WHAT MAKES A DRAFT FAIL (INSTANT REWRITES)
────────────────────────────────────────

- PARAGRAPH SLIDES: Your slide is a paragraph but the ${this.getBlueprintLabel()}'s equivalent slide uses line breaks and bullet points. Fix: break it up to match the visual format.
- GENERIC CLAIMS: You wrote "this changed everything" or "the results were incredible." The swipes use SPECIFIC numbers: "$47K in 11 days", "17 properties", "quit at 28." Fix: replace every generic claim with a specific detail from the client's brand story.
- WRONG SLIDE COUNT: You wrote 8 slides but the ${this.getBlueprintLabel()} has 12. Your plan specified 12. Fix: add the missing slides.
- HOOK FORMAT MISMATCH: Your hook doesn't match the ${this.getBlueprintLabel()}'s format (case, person, structure, word count). Fix: rewrite matching the hook specification from your plan.
- BANNED PHRASES: If any phrase from the BANNED list appears ANYWHERE, replace it immediately. Common traps: "in today's", "leverage", "game-changer", "let that sink in", "this isn't X, this is Y."
- AI VOICE DRIFT: Sentences getting longer and more sophisticated. Vocabulary feels elevated. Hedging with "perhaps" and "it might be." Fix: rewrite as shorter, more direct, more like the client's real posts.

Call write_draft with the complete content.

FINAL CHECK BEFORE SUBMITTING: Count your total slides. Does it match the ${this.getBlueprintLabel()}? Count words in slide 1. Does it match your plan target (±10%)? If not, fix it now.`,
      timestamp: new Date().toISOString(),
    });

    const block3b = this.buildDynamicBlock();
    const result = await this.runConversationLoop('draft', block3b, 'write');

    this.blocks = originalBlocks;
    return result;
  }

  private async runSelfEditPhase(): Promise<string> {
    const originalBlocks = this.blocks;

    // Load methodology for quality criteria
    const methodology = await loadPromptTemplate('methodology');

    const blueprintSummary = this.getBlueprintStructuralSummary();

    const qualityBlock: WritingBlock = {
      label: 'Self-Edit Context',
      content: [
        '═══ SELF-EDIT PASS ═══',
        'Review the draft against your writing plan and quality rules.',
        'Run all self-edit checks. Fix any issues. Call write_draft with the corrected version.',
        '',
        '--- WRITING PLAN (reference) ---',
        this.writingPlan || '',
        '',
        ...(blueprintSummary ? [blueprintSummary, ''] : []),
        '--- QUALITY RULES ---',
        this.buildCriticalRulesReminder(),
        '',
        ...(methodology ? ['--- SKILL MODULES (quality criteria) ---', methodology, ''] : []),
        '--- CURRENT DRAFT ---',
        this.contentAtom?.body || '[no draft yet]',
      ].join('\n'),
      cacheControl: false,
    };

    // Keep Block 1 (system prompt + density override) and Block 2 (client intelligence) as prefix
    // for cache hit + full writing context during self-edit
    this.blocks = [originalBlocks[0], originalBlocks[1], qualityBlock];
    console.log(`  ✍️ Self-edit blocks: ${this.blocks.map(b => `${b.label}(${(b.content.length / 1024).toFixed(0)}KB)`).join(' + ')}`);

    const structuralCheck = blueprintSummary
      ? ` Also verify structural fidelity: does your draft's beat sequence match the ${this.getBlueprintLabel()}? Does slide count match? Does hook format match?`
      : '';

    this.messages.push({
      id: crypto.randomUUID(),
      role: 'user',
      content: `Self-edit pass. You are now the EDITOR, not the writer. Your job is to catch everything the writer missed. You have the writing plan, the ${this.getBlueprintLabel()} structural summary, the quality rules, and the current draft.

Use the think tool to run each of these 6 checks. For each check, write down your finding and whether it PASSES or FAILS. Then fix everything that fails and call write_draft with the corrected version. If all 6 pass, respond with a brief summary listing each check and its result.

────────────────────────────────────────
CHECK 1: SLIDE COUNT
────────────────────────────────────────
Procedure:
- Look at the ${this.getBlueprintLabel()} STRUCTURAL SUMMARY in your context. It says "Slide count: N".
- Count the slides in your draft (look for "Slide N" markers or --- separators).
- Compare.
Pass: Same number. Fail: Different number → add missing slides or merge extras.

────────────────────────────────────────
CHECK 2: DENSITY PER SLIDE
────────────────────────────────────────
Procedure:
- Open your writing plan. It has word count targets for each slide position.
- For your draft's slide 1, split the text by spaces and count words.
- Compare to the plan's target for slide 1.
- Repeat for slides 3, the middle slide, and the last slide (minimum 4 spot checks).
Pass: Each checked slide is within ±10% of the plan target (e.g., 47-word target → 42-52 is pass).
Fail: Outside ±10% → cut words from too-dense slides or add specific details to too-thin slides.

────────────────────────────────────────
CHECK 3: VISUAL FORMAT
────────────────────────────────────────
Procedure:
- Pick slide 3 from your draft and slide 3 from the ${this.getBlueprintLabel()} (in the loaded examples).
- Compare: same number of lines? Same formatting (bullets, line breaks, fragments vs paragraphs)?
- Repeat for slide 1 and one other slide.
Pass: Your slides look like they came from the same template. Fail: Different format → reformat to match.

────────────────────────────────────────
CHECK 4: VOICE MATCH
────────────────────────────────────────
Procedure:
- Read your slide 5 as if reading aloud at dinner.
- Compare to the client's TOP PERFORMING POSTS from the client profile.
- Do they sound like the same person?
What voice drift looks like: sentences getting longer/more complex, sophisticated vocabulary, hedging ("perhaps", "it might be"), sounds "written" instead of "spoken."
Pass: Same person, same day. Fail: Voice drift → rewrite with shorter sentences, client's vocabulary, their signature phrases.

────────────────────────────────────────
CHECK 5: SPECIFICITY
────────────────────────────────────────
Procedure:
- Count every specific detail in your draft: numbers, names, dates, places, dollar amounts, percentages.
- Count the same in the ${this.getBlueprintLabel()}.
Pass: Your count is within 50% of the ${this.getBlueprintLabel()}'s count. Fail: Too few → replace generic claims with real details from the brand story.

────────────────────────────────────────
CHECK 6: HOOK FORMAT
────────────────────────────────────────
Procedure:
- Compare your hook (slide 1) to the ${this.getBlueprintLabel()}'s hook on 5 properties:
  Case (ALL CAPS/lowercase/Title), Person (first/third/second), Structure (sentence skeleton), Length (±5 words), Ending punctuation.
Pass: All 5 match. Fail: Any mismatch → rewrite the hook to match.

────────────────────────────────────────
After all 6 checks: fix failures and call write_draft, or respond with a summary if all passed.`,
      timestamp: new Date().toISOString(),
    });

    const block3b = this.buildDynamicBlock();
    const result = await this.runConversationLoop('draft', block3b, 'edit');

    this.blocks = originalBlocks;
    return result;
  }

  private getBlueprintLabel(): string {
    return this.hasTruePrimaryBlueprint ? 'PRIMARY BLUEPRINT' : 'STRUCTURAL ANCHOR';
  }

  private getBlueprintStructuralSummary(): string {
    const bp = this.blueprintAnchor;
    if (!bp) return '';
    const label = this.getBlueprintLabel();
    const lines: string[] = [];
    lines.push(`--- ${label} STRUCTURAL SUMMARY ---`);
    if (bp.beatSequence.length > 0) {
      lines.push(`Beat sequence: ${bp.beatSequence.join(' > ')}`);
    }
    const slideCount = this.countSlidesInBody(bp.fullBody);
    if (slideCount > 0) {
      lines.push(`Slide count: ${slideCount}`);
    }
    lines.push(`Hook: "${bp.hookText?.substring(0, 150) || bp.title}"`);
    lines.push(`Hook type: ${bp.hookType} (score: ${bp.hookScore}/10)`);
    if (bp.hookMechanism) {
      lines.push(`Hook mechanism: ${bp.hookMechanism}`);
    }
    if (bp.framework && bp.framework !== 'Original') {
      lines.push(`Framework: ${bp.framework}`);
    }
    return lines.join('\n');
  }

  private countSlidesInBody(body: string): number {
    if (!body) return 0;
    try {
      const parsed = JSON.parse(body);
      if (parsed.slides) return parsed.slides.length;
    } catch { /* not JSON */ }
    const slideMatches = body.match(/^Slide \d+/gim);
    if (slideMatches) return slideMatches.length;
    const separators = body.split(/^[-=]{3,}$/m).filter(s => s.trim().length > 0);
    if (separators.length > 1) return separators.length;
    return 0;
  }

  private buildSwipeReferenceBlock(): string {
    const sections: string[] = [];
    const bp = this.blueprintAnchor;

    // Blueprint anchor first — structural guide for the draft
    if (bp && bp.fullBody) {
      if (this.hasTruePrimaryBlueprint) {
        sections.push('═══ PRIMARY BLUEPRINT — YOUR STRUCTURAL ANCHOR ═══');
        sections.push('This is the post you must structurally mirror. Match its:');
      } else {
        sections.push('═══ INFERRED STRUCTURAL ANCHOR (highest-scoring example) ═══');
        sections.push('No explicit primary blueprint was provided. This is the highest-scoring swipe — use as your primary structural reference, adapting as needed. Match its:');
      }
      sections.push('• Beat pattern (how it opens, builds, and closes)');
      sections.push('• Slide architecture (sentence count, bullet usage, line breaks per slide)');
      sections.push('• Density and visual rhythm');
      sections.push('• Hook format and perspective');
      if (bp.beatSequence.length > 0) {
        sections.push(`\nBeat Pattern: ${bp.beatSequence.join(' > ')}`);
      }
      sections.push(`Hook: "${bp.hookText?.substring(0, 200) || bp.title}"`);
      // Metadata — preserved from plan phase analysis
      if (bp.hookType) {
        sections.push(`Hook Type: ${bp.hookType} (score: ${bp.hookScore}/10)`);
      }
      if (bp.hookMechanism) {
        sections.push(`Hook Mechanism: ${bp.hookMechanism}`);
      }
      if (bp.framework && bp.framework !== 'Original') {
        sections.push(`Framework: ${bp.framework}`);
      }
      if (bp.structuralBreakdown) {
        sections.push(`Structural Breakdown: ${bp.structuralBreakdown}`);
      }
      if (bp.keyTransitions.length > 0) {
        sections.push(`Key Transitions: ${bp.keyTransitions.join(', ')}`);
      }
      if (bp.structuralRecipe) {
        sections.push(`Structural Recipe: ${bp.structuralRecipe}`);
      }
      sections.push('');
      sections.push(bp.fullBody);
      sections.push('');
    }

    // Supporting examples
    sections.push('═══ SUPPORTING EXAMPLES — STYLE REFERENCE ═══');
    sections.push('Study these for copy quality, transitions, and formatting patterns.');
    sections.push('NOTICE: line breaks within slides, -- bullet lists, short sentences.\n');

    for (const swipe of this.selectedSwipes) {
      if (bp && swipe.uuid === bp.uuid) continue; // Already shown above
      if (swipe.fullBody) {
        sections.push('[EXAMPLE]');
        sections.push(swipe.fullBody);
        sections.push('');
      }
    }

    // Application rules — critical structural enforcement from Block 3A
    sections.push('');
    sections.push(getSwipeApplicationRules(this.selectedSwipes.length, bp || undefined));

    return sections.join('\n');
  }

  // ============================================================
  // Conversation Loop
  // ============================================================

  private async runConversationLoop(phase: WritingPhase, block3b: WritingBlock, pipelineStep?: 'plan' | 'write' | 'edit'): Promise<string> {
    let lastAssistantText = '';
    let emptyResponseCount = 0;
    let consecutiveThinks = 0;
    let truncatedResponseCount = 0;

    for (let iteration = 0; iteration < MAX_INNER_ITERATIONS; iteration++) {
      console.log(`    🔄 Iteration ${iteration + 1}/${MAX_INNER_ITERATIONS} [${pipelineStep || phase}] (${this.messages.length} messages)`);

      // Build API messages
      const apiMessages = this.buildAPIMessages();

      // Available tools for this phase (pipeline step overrides if present)
      const tools = this.getToolDefinitions(phase, pipelineStep);

      // Call LLM (pass dynamic block separately — it changes each iteration)
      const response = await this.callWritingLLM(block3b, apiMessages, tools);

      // Log response shape
      const toolNames = response.toolCalls?.map(tc => tc.name).join(', ') || 'none';
      const respPreview = (response.content || '').substring(0, 120).replace(/\n/g, ' ');
      console.log(`    🔄 Response: tools=[${toolNames}], text=${(response.content || '').length} chars, finish=${response.finishReason || '--'}${respPreview ? `, preview: "${respPreview}..."` : ''}`);

      // No tool calls — classify response (ported from Swift classifyLoopResponse)
      if (!response.toolCalls || response.toolCalls.length === 0) {
        const text = (response.content || '').trim();

        if (text.length > 0) {
          // Has content — accept
          if (response.finishReason === 'length') {
            lastAssistantText = text + '\n\n[System] The model hit its output limit before finishing. Ask me to continue from where it left off.';
            console.log(`  ⚠️ Accepted truncated response (finish_reason=length)`);
          } else {
            lastAssistantText = text;
          }
          // Log full assistant response
          console.log(`    🤖 Assistant response (${text.length} chars):`);
          console.log(`    ────────────────────────────────────────`);
          for (const line of text.split('\n')) {
            console.log(`    🤖 ${line}`);
          }
          console.log(`    ────────────────────────────────────────`);
          this.messages.push({
            id: crypto.randomUUID(),
            role: 'assistant',
            content: lastAssistantText,
            timestamp: new Date().toISOString(),
          });
          break;
        } else {
          // Empty response, no tools — retry once then abort (matching Swift maxTransientEmptyNoToolRetries=1)
          emptyResponseCount++;
          if (emptyResponseCount <= 1) {
            console.log(`  ⚠️ Empty no-tool response (${emptyResponseCount}/1) — retrying`);
            continue; // retry without pushing message
          } else {
            lastAssistantText = 'The writing engine stopped after empty provider responses. I stopped retrying so this does not keep burning tokens. Please try again or ask me to continue.';
            console.log(`  ❌ Empty response repeated — aborting`);
            this.messages.push({
              id: crypto.randomUUID(),
              role: 'assistant',
              content: lastAssistantText,
              timestamp: new Date().toISOString(),
            });
            break;
          }
        }
      }

      // Detect truncated/degraded responses — provider returned garbage
      // A real response has finish_reason set (tool_calls, stop, length) and meaningful content
      // A truncated response has finish_reason=null and tiny completion (<50 tokens)
      if (!response.finishReason && response.completionTokens < 50 && response.toolCalls.length > 0) {
        truncatedResponseCount++;
        const thinkContent = response.toolCalls
          .filter(tc => tc.name === 'think')
          .map(tc => (tc.arguments as any)?.thought || '')
          .join(' ');
        const thinkWords = thinkContent.split(/\s+/).filter(Boolean).length;

        console.log(`  ⚠️ Truncated response detected (${response.completionTokens} tokens, ${thinkWords} think words, attempt ${truncatedResponseCount}/3)`);

        if (truncatedResponseCount >= 3) {
          // Circuit breaker — stop burning tokens
          console.log(`  ❌ Truncated response loop (${truncatedResponseCount}x) — aborting to save tokens`);
          lastAssistantText = 'The writing engine received repeated truncated responses from the AI provider (likely a timeout). The model could not produce meaningful output. Please try again — the provider may route to a faster instance.';
          this.messages.push({
            id: crypto.randomUUID(),
            role: 'assistant',
            content: lastAssistantText,
            timestamp: new Date().toISOString(),
          });
          break;
        }

        // Don't push garbage to messages — retry with clean conversation state
        // Brief delay before retry to allow provider recovery
        await new Promise(r => setTimeout(r, 2000));
        continue; // retry without accumulating garbage
      }

      // Valid response — reset truncated counter
      if (response.finishReason) {
        truncatedResponseCount = 0;
      }

      // Execute tool calls
      const assistantMessage: WritingMessage = {
        id: crypto.randomUUID(),
        role: 'assistant',
        content: response.content || '',
        timestamp: new Date().toISOString(),
        toolCalls: response.toolCalls,
      };
      this.messages.push(assistantMessage);

      for (const toolCall of response.toolCalls) {
        console.log(`    ✍️ Engine tool: ${toolCall.name}`);
        const result = await this.executeInnerTool(toolCall.name, toolCall.arguments);
        this.messages.push({
          id: crypto.randomUUID(),
          role: 'tool',
          content: result,
          timestamp: new Date().toISOString(),
          toolCallId: toolCall.id,
        });
      }

      // Detect extended analysis — nudge after 4 consecutive thinks
      const allThinks = response.toolCalls.every(tc => tc.name === 'think');
      if (allThinks) {
        consecutiveThinks++;
        if (consecutiveThinks >= 4) {
          console.log(`  ⚠️ Extended analysis (${consecutiveThinks} consecutive thinks) — directive nudge`);
          this.messages.push({
            id: crypto.randomUUID(),
            role: 'user',
            content: '[System] You have done 4 consecutive think calls without taking action. You MUST now call a tool to make progress — update_outline, add_hooks, or write_draft. Do NOT call think again.',
            timestamp: new Date().toISOString(),
            isSystemNudge: true,
          });
          consecutiveThinks = 0;
        }
      } else {
        consecutiveThinks = 0;
      }

      // Refresh dynamic block after tool execution (outline/hooks/draft may have changed)
      this.contentAtom = await fetchAtom(this.contentUUID) || this.contentAtom!;
      block3b = assembleBlock3Dynamic(
        this.contentAtom,
        this.outline.length > 0 ? this.outline : null,
        this.hooks.length > 0 ? this.hooks : null,
        this.conversationSummary,
        this.writingContext,
      );
    }

    return lastAssistantText;
  }

  // ============================================================
  // Inner Tool Execution
  // ============================================================

  private async executeInnerTool(name: string, args: Record<string, any>): Promise<string> {
    switch (name) {
      case 'think': {
        const thought = (args.thought as string) || '';
        const wordCount = thought.split(/\s+/).length;

        // Log full think content — essential for debugging and optimizing the writing system
        const thinkTopics: string[] = [];
        if (/slide|density|word.?count/i.test(thought)) thinkTopics.push('density');
        if (/beat|hook|structure/i.test(thought)) thinkTopics.push('structure');
        if (/voice|client|brand|tone/i.test(thought)) thinkTopics.push('voice');
        if (/swipe|example|blueprint|primary/i.test(thought)) thinkTopics.push('swipes');
        if (/rule|lesson|ban/i.test(thought)) thinkTopics.push('rules');
        if (/plan|outline|approach/i.test(thought)) thinkTopics.push('planning');
        if (/edit|check|fix|rewrite|correct/i.test(thought)) thinkTopics.push('editing');
        console.log(`    💭 Think (${wordCount} words) [${thinkTopics.join(', ') || 'general'}]:`);
        console.log(`    ────────────────────────────────────────`);
        // Log full thought with indentation for readability
        for (const line of thought.split('\n')) {
          console.log(`    💭 ${line}`);
        }
        console.log(`    ────────────────────────────────────────`);

        // Track analysis depth for pre-write/outline gate
        if (wordCount > 200) {
          this.analysisDepth++;
          // Always capture substantial analysis — no keyword gating
          this.writingContext.latestAnalysis = thought.substring(0, 4000);
          // Also capture into specific buckets IF keywords match (additive, not exclusive)
          if (/swipe|pattern|density|hook|voice|structure|transition|punctuation/i.test(thought)) {
            this.writingContext.swipePatternAnalysis = thought.substring(0, 4000);
          }
          if (/plan|approach|strategy|will write|going to|outline|structure/i.test(thought)) {
            this.writingContext.structuralPlan = thought.substring(0, 2000);
          }
          this.writingContext.analysisDepth = this.analysisDepth;
        }

        // Capture self-review findings
        if (this.hasCompletedSelfReview && wordCount > 100) {
          this.writingContext.selfReviewFindings = thought.substring(0, 2000);
        }

        // Guard against garbage/truncated thinks — never confirm ultra-short thoughts
        if (wordCount < 30) {
          return `Analysis received (${wordCount} words) — this is very short. If you're planning to take action, call the appropriate tool (update_outline, add_hooks, write_draft). If you need to reason, write a thorough analysis with specific observations from your loaded swipes (200+ words minimum for substantive analysis).`;
        }

        // Guide toward thorough analysis on first real think
        if (this.analysisDepth === 0 && wordCount < 200) {
          return `Analysis received (${wordCount} words). Before writing, ensure you've analyzed your loaded swipes through EVERY lens: density patterns, punctuation usage, hook mechanics, voice characteristics, transition patterns, CTA structure. Reference the Slide Density, Dinner Table Test, Voice Matching, Hook Craft, Causal Chaining, and CTA Craft modules in your context for what to look for.`;
        }

        if (this.analysisDepth >= 2) {
          const ruleReminder = this.buildCriticalRulesReminder();
          return `Analysis received (${wordCount} words). Deep analysis complete.\n\nBEFORE YOU WRITE — review these rules (violations trigger automatic rewrite):\n${ruleReminder}\n\nYou may now call write_draft.`;
        }

        return `Analysis received (${wordCount} words). Continue analyzing — check remaining skill module dimensions.`;
      }

      case 'update_outline': {
        // Pre-outline analysis gate — require deep thinking before outline
        if (this.analysisDepth < 1) {
          return `[BLOCKED] You haven't analyzed your context deeply enough yet. Before creating an outline:

1. Call think to study ALL loaded swipes — read their full bodies in your context. For EACH dimension below, note what patterns you observe:
   • CONTENT TYPE: Are these tutorials, stories, listicles, case studies? What does each slide DO? What type should your outline follow?
   • SLIDE ARCHITECTURE: What's the internal structure of each slide? Bullet points? Numbered steps? How many sentences per slide?
   • HOOKS: What hook mechanisms do the top-scoring swipes use? How are they structured?
   • STRUCTURE: What beat patterns do the swipes follow? How many sections?
   • DENSITY: How many words per slide? (Carousels = 50-100, Reels = 10-25)
   • VOICE: What's the tone, formality, sentence length patterns?
   • TRANSITIONS: How do slides connect?
   • CTA: What CTA patterns work?

2. Call think to study the CLIENT PROFILE — their voice targets, brand story, beliefs, audience, positioning, failure fingerprint, top performing content patterns

3. Call think to plan your outline approach — how will you combine the swipe structural DNA with the client's voice and topic?

Only after thorough analysis can you call update_outline.`;
        }

        const sections = args.sections as any[];
        if (!sections) return 'Error: sections required';
        this.outline = sections.map((s: any, i: number) => ({
          id: s.id || `section_${i}`,
          title: s.title || '',
          beatLabel: s.beatLabel,
          description: s.description,
          estimatedSeconds: s.estimatedSeconds,
          sortOrder: i,
        }));
        // Persist to atom metadata
        await updateAtom(this.contentUUID, {
          metadata: { outline: this.outline },
        });
        return `Outline updated with ${this.outline.length} sections.`;
      }

      case 'add_hooks': {
        // Analysis gate — require deep thinking before hooks
        if (this.analysisDepth < 1) {
          return `[BLOCKED] Before generating hooks, you must analyze the PRIMARY BLUEPRINT's hook format. Call think and study:

1. The PRIMARY BLUEPRINT hook in your context — what is its exact structure?
   • Is it first-person or third-person?
   • Does it use an authority label (e.g., "Ex-banker explains:")?
   • What's the sentence pattern?
   • How long is it (word count)?
   • Is it ALL CAPS, Title Case, or lowercase?

2. The user's title — this IS the hook template. Your variants must keep its sentence skeleton.

3. Section 6 hook rules in your context — Match CASE, PERSPECTIVE, STRUCTURE, and LENGTH exactly.

Only after this analysis can you call add_hooks.`;
        }

        const hookVariants = args.hooks as any[];
        if (!hookVariants) return 'Error: hooks required';

        // Validate hooks against primary blueprint format
        const primarySwipe = this.selectedSwipes.find(s => s.isPrimary);
        if (primarySwipe) {
          const generatedHooks = hookVariants.map((h: any) => typeof h === 'string' ? h : h.text || '');
          const violations = validateHooksAgainstBlueprint(
            generatedHooks,
            primarySwipe.hookText,
            this.contentAtom?.title || '',
          );
          if (violations.length > 0) {
            return `[HOOK FORMAT VIOLATIONS] Your hooks don't match the primary blueprint format.\n\n` +
              `PRIMARY BLUEPRINT HOOK: "${primarySwipe.hookText.substring(0, 200)}"\n` +
              `USER'S TITLE (your template): "${this.contentAtom?.title || ''}"\n\n` +
              `VIOLATIONS:\n${violations.map(v => `  • ${v}`).join('\n')}\n\n` +
              `Fix these and call add_hooks again. Each variant must keep the SAME sentence skeleton as the user's title.`;
          }
        }

        this.hooks = hookVariants.map((h: any) => typeof h === 'string' ? h : h.text || '');
        await updateAtom(this.contentUUID, {
          metadata: { hooks: this.hooks, inheritedHooks: this.hooks },
        });
        return `Added ${this.hooks.length} hook variants.`;
      }

      case 'write_draft': {
        // Pre-write analysis gate — require deep thinking before draft
        if (this.analysisDepth < 1) {
          return `[BLOCKED] You haven't analyzed your context deeply enough yet. Before writing:

1. Call think to study ALL loaded swipes — read their full bodies in your context. For EACH dimension below, note what patterns you observe across the swipes:
   • CONTENT TYPE: Are these tutorials, personal stories, listicles, case studies, news reactions? What does each slide DO — teach, prove, reveal, connect? What type should YOUR draft be?
   • SLIDE ARCHITECTURE: What's the internal structure of each slide? Count sentences per slide. Do they use bullet points (-- dashes)? Numbered steps? Headers?
   • SPECIFICITY: How many specific numbers, dollar amounts, percentages, resources, or proper nouns appear per slide? Count them. Your draft must match this density.
   • VALUE PER SLIDE: Does every slide teach something, prove something, or advance the argument? What's the ratio of teaching slides vs narrative slides?
   • DENSITY: How many sentences per slide? How many words per slide? (FORMAT-SPECIFIC: carousels = 50-100 words, reels = 10-25 words)
   • VOICE: What's the tone? Contractions? Sentence fragments vs full sentences? Formality level?
   • HOOKS: What hook mechanisms do the top-scoring swipes use? How long are hooks?
   • TRANSITIONS: How do slides connect? Implied "so/but/that's when"?
   • PUNCTUATION: Do they use em-dashes? Ellipses? Exclamation marks? What's ABSENT?
   • CTA: What CTA pattern do they use? Keyword + action?
   • DINNER TABLE: Would these swipes sound natural spoken aloud at dinner?

2. Call think again to plan your writing approach — how will you match the CONTENT TYPE, DENSITY, SPECIFICITY, and SLIDE ARCHITECTURE of your loaded swipes?

Only after thorough analysis can you call write_draft.`;
        }

        const content = args.content as string;
        if (!content) return 'Error: content required';
        const format = args.format as string || 'plaintext';

        // Persist draft to atom body
        await updateAtom(this.contentUUID, { body: content });

        // Validate format
        const validation = validateDraft(content, this.targetFormat);
        const wordCount = content.split(/\s+/).filter(Boolean).length;

        // Log full draft details
        const slideMarkers = content.match(/^Slide \d+/gim) || [];
        const slideCount = slideMarkers.length || (content.match(/^[-=]{3,}$/gm) || []).length + 1;
        console.log(`    📝 write_draft: ${wordCount} words, ${slideCount} slides, format: ${format}`);
        if (this.blueprintAnchor) {
          const bpSlides = this.countSlidesInBody(this.blueprintAnchor.fullBody);
          console.log(`    📝 Blueprint comparison: draft=${slideCount} slides vs blueprint=${bpSlides} slides ${slideCount === bpSlides ? '✅' : '⚠️ MISMATCH'}`);
        }
        // Log full draft for debugging
        console.log(`    📝 ════════ FULL DRAFT ════════`);
        for (const line of content.split('\n')) {
          console.log(`    📝 ${line}`);
        }
        console.log(`    📝 ════════ END DRAFT ════════`);

        let result = `Draft written (${wordCount} words, format: ${format})`;
        if (!validation.isValid) {
          result += `\nValidation issues:\n${validation.violations.map(v => `  - ${v}`).join('\n')}`;
        }

        // Deterministic validation (ported from Swift DeterministicWritingValidators)
        const deterministicViolations = runDeterministicValidators(content, this.lessons);
        if (deterministicViolations.length > 0) {
          console.log(`    ⚠️ Deterministic violations (${deterministicViolations.length}): ${deterministicViolations.map(v => `[${v.type}] ${v.message.substring(0, 60)}`).join('; ')}`);
          result += `\n\n⚠️ DETERMINISTIC RULE VIOLATIONS (fix before presenting):`;
          for (const v of deterministicViolations) {
            result += `\n  - [${v.type}] ${v.message}`;
          }
        }

        // Voice compliance check
        const voiceViolations = checkVoiceCompliance(content, this.clientAtom);
        if (voiceViolations.length > 0) {
          console.log(`    ⚠️ Voice violations (${voiceViolations.length}): ${voiceViolations.map(v => v.substring(0, 60)).join('; ')}`);
          result += `\n\n⚠️ VOICE COMPLIANCE:`;
          for (const v of voiceViolations) {
            result += `\n  - ${v}`;
          }
        } else {
          console.log(`    ✅ Voice compliance passed`);
        }

        // Self-evaluation
        const selfEval = args.selfEvaluation;
        if (selfEval) {
          result += `\nSelf-evaluation: confidence=${selfEval.confidenceScore}%, voice=${selfEval.voiceMatchScore}%`;
          if (selfEval.weakAreas?.length > 0) {
            result += `, weak areas: ${selfEval.weakAreas.join(', ')}`;
          }
        }

        // Auto-refine prompt if violations found
        if (deterministicViolations.length > 0 || voiceViolations.length > 0) {
          this.refinementCount = (this.refinementCount || 0) + 1;
          if (this.refinementCount <= 2) {
            result += `\n\nAUTO-REFINEMENT PASS ${this.refinementCount}/2: Fix the violations above, then call write_draft again with the corrected content.`;
          }
        }

        // Self-review injection — fires once per draft, after all deterministic validation
        if (!this.hasCompletedSelfReview && deterministicViolations.length === 0 && voiceViolations.length === 0) {
          this.hasCompletedSelfReview = true;

          result += `\n\n═══ SELF-REVIEW REQUIRED ═══
Before presenting this draft, you MUST run the Self-Edit Pass (Module 7 in your context). Apply ALL 6 checks:
1. Read-aloud check
2. Density check
3. Causal chain check
4. Perspective check
5. Scroll test
6. Blueprint comparison

Then compare your draft against:
• ALL loaded swipes in your context — does your draft match their density, voice, punctuation patterns, and structural mechanics?
• ALL skill modules (Dinner Table Test, Slide Density, Causal Chaining, Hook Craft, Voice Matching, CTA Craft) — does your draft pass every test described in these modules?
• ALL learned rules and failure fingerprint in your client intelligence — are any rules violated?
• Your own pre-write analysis — did you follow the patterns you identified?

Call think with your self-review findings. If ANY check fails, call write_draft with corrections.
If ALL checks pass, present the draft.
═══════════════════════════`;
        }

        return result;
      }

      case 'create_writing_plan': {
        const plan = (args.plan as string) || '';
        const planWords = plan.split(/\s+/).length;
        if (planWords < 200) {
          console.log(`    ⚠️ Plan REJECTED: only ${planWords} words (minimum 200)`);
          return `[REJECTED] Writing plan is too short (${planWords} words). The plan must cover: Structural Template (per-slide beat/density/format), Voice Rules, Hard Rules, Hook Specification, and Density Targets. Make it detailed enough that writing becomes mechanical execution.`;
        }
        this.writingPlan = plan;
        this.writingContext.writingPlan = plan;

        // Log plan quality signals
        const hasSlideEntries = (plan.match(/Slide \d+/gi) || []).length;
        const hasWordCounts = (plan.match(/\d+ words/gi) || []).length;
        const hasBeatLabels = (plan.match(/\[(Hook|Context|Teach|Prove|Story|Reframe|Reveal|CTA)\]/gi) || []).length;
        const hasBannedSection = /banned|ban list/i.test(plan);
        const hasHookSpec = /hook.*(case|person|structure|caps)/i.test(plan);
        console.log(`    📋 Plan created: ${planWords} words`);
        console.log(`    📋 Plan quality: ${hasSlideEntries} slide entries, ${hasWordCounts} word count targets, ${hasBeatLabels} beat labels, banned section: ${hasBannedSection ? 'yes' : 'NO'}, hook spec: ${hasHookSpec ? 'yes' : 'NO'}`);
        if (hasSlideEntries < 3) console.log(`    ⚠️ Plan has few slide entries (${hasSlideEntries}) — may not have per-slide detail`);
        if (hasWordCounts < 2) console.log(`    ⚠️ Plan has few word count targets (${hasWordCounts}) — density may be vague`);
        // Log full plan for debugging
        console.log(`    📋 ════════ FULL WRITING PLAN ════════`);
        for (const line of plan.split('\n')) {
          console.log(`    📋 ${line}`);
        }
        console.log(`    📋 ════════ END WRITING PLAN ════════`);

        return `Writing plan created (${planWords} words). The engine will now switch to WRITE mode with focused context. Your plan will drive the draft.`;
      }

      case 'read_draft': {
        const atom = await fetchAtom(this.contentUUID);
        const body = atom?.body || '';
        return `Current draft (${body.length} characters):\n\n${body}`;
      }

      case 'edit_section': {
        const sectionId = args.sectionIdentifier as string;
        const newContent = args.newContent as string;
        const reasoning = args.reasoning as string;
        return `Section '${sectionId}' edited. Reasoning: ${reasoning || 'none provided'}`;
      }

      case 'set_title': {
        const title = args.title as string;
        if (title) await updateAtom(this.contentUUID, { title });
        return `Title set to: "${title}"`;
      }

      case 'set_description': {
        const desc = args.description as string;
        if (desc) await updateAtom(this.contentUUID, { metadata: { contentDescription: desc } });
        return `Content description set.`;
      }

      case 'run_scorecard':
        return 'Scorecard evaluation requires Phase 3 scorecard engine. Skipping for now.';

      case 'search_swipes': {
        const query = args.query as string;
        const matching = this.selectedSwipes.filter(s =>
          s.title.toLowerCase().includes((query || '').toLowerCase()) ||
          s.hookType.toLowerCase().includes((query || '').toLowerCase()) ||
          s.fullBody.toLowerCase().includes((query || '').toLowerCase())
        ).slice(0, 5);
        if (matching.length === 0) return 'No matching swipes found in selected library.';
        return `Found ${matching.length} matching swipes:\n\n${matching.map(s =>
          `UUID: ${s.uuid}\n${s.title}\nHook: ${s.hookType} (${s.hookScore}/10)\nBeats: ${s.beatSequence.join(' > ')}`
        ).join('\n\n')}`;
      }

      case 'read_swipe_body': {
        const swipeId = args.swipe_id as string;

        // Check reference material cache first (Gap #11 fix)
        if (this.referenceMaterial.has(swipeId)) {
          return `Swipe "${swipeId}" already loaded in REFERENCE MATERIAL (${this.referenceMaterial.get(swipeId)!.length} chars).`;
        }

        // Check budget
        if (this.referenceMaterialChars >= CloudWritingEngine.REFERENCE_MATERIAL_MAX_CHARS) {
          return `Reference material budget exhausted (${this.referenceMaterialChars}/${CloudWritingEngine.REFERENCE_MATERIAL_MAX_CHARS} chars). Cannot load more.`;
        }

        const swipe = this.selectedSwipes.find(s => s.uuid === swipeId);
        const body = swipe?.fullBody || (await fetchAtom(swipeId))?.body || '';
        const title = swipe?.title || 'Swipe';

        if (!body) return `Swipe ${swipeId} not found.`;

        // Cache and track budget
        this.referenceMaterial.set(swipeId, body);
        this.referenceMaterialChars += body.length;

        return `Loaded swipe "${title}" (${body.length} chars) into REFERENCE MATERIAL:\n\n${body}`;
      }

      case 'list_client_posts':
        return 'Client post index not available in cloud engine. Use read_draft and search_swipes.';

      case 'read_client_post':
        return 'Client post loading not available in cloud engine. Use search_swipes instead.';

      case 'get_client_profile': {
        if (this.clientAtom) {
          return `Client profile "${this.clientAtom.title}" already loaded in system context.`;
        }
        const query = args.query as string;
        if (query) {
          const found = await fuzzyFindClient(query);
          if (found) {
            this.clientAtom = found;
            return `Loaded client profile "${found.title}" into system context.`;
          }
        }
        return 'Client profile not found.';
      }

      case 'analyze_swipe_patterns': {
        const hookCounts: Record<string, number> = {};
        for (const s of this.selectedSwipes) {
          hookCounts[s.hookType] = (hookCounts[s.hookType] || 0) + 1;
        }
        const topHooks = Object.entries(hookCounts).sort((a, b) => b[1] - a[1]).slice(0, 5);
        return `Pattern analysis (${this.selectedSwipes.length} swipes):\n\nTop Hook Types:\n${topHooks.map(([h, c]) => `  ${h}: ${c}x`).join('\n')}\n\nAverage Hook Score: ${(this.selectedSwipes.reduce((s, sw) => s + sw.hookScore, 0) / Math.max(this.selectedSwipes.length, 1)).toFixed(1)}/10`;
      }

      default:
        return `Unknown writing tool: ${name}`;
    }
  }

  // ============================================================
  // LLM Call — Direct Anthropic Messages API (no OpenRouter middleman)
  // ============================================================

  private async callWritingLLM(
    dynamicBlock: WritingBlock | null,
    messages: any[],
    tools: any[],
  ): Promise<{ content: string | null; toolCalls: Array<{ id: string; name: string; arguments: Record<string, any> }>; finishReason: string | null; completionTokens: number }> {
    const useDirectAnthropic = !!config.anthropicApiKey;
    const model = config.models.writer;

    // Strip provider prefix for direct Anthropic (e.g., "anthropic/claude-opus-4-6" → "claude-opus-4-6")
    const modelId = useDirectAnthropic ? model.replace(/^anthropic\//, '') : model;

    const systemChars = this.blocks.reduce((sum, b) => sum + b.content.length, 0);
    const estimatedTokens = Math.round((systemChars + JSON.stringify(messages).length) / 4);
    console.log(`  ✍️ Writing engine → ${modelId} (${messages.length} messages, ${tools.length} tools, ~${estimatedTokens} est tokens)${useDirectAnthropic ? ' [direct]' : ' [openrouter]'}`);

    if (useDirectAnthropic) {
      return this.callAnthropicDirect(modelId, messages, tools, dynamicBlock);
    } else {
      return this.callOpenRouter(model, messages, tools, dynamicBlock);
    }
  }

  /**
   * Direct Anthropic Messages API — no middleman, native prompt caching, no provider routing
   */
  private async callAnthropicDirect(
    model: string,
    messages: any[],
    tools: any[],
    dynamicBlock: WritingBlock | null,
  ): Promise<{ content: string | null; toolCalls: Array<{ id: string; name: string; arguments: Record<string, any> }>; finishReason: string | null; completionTokens: number }> {
    const apiKey = config.anthropicApiKey!;

    // System prompt: stable blocks with cache_control + dynamic block (no cache — changes each iteration)
    const system: any[] = this.blocks.map(block => ({
      type: 'text' as const,
      text: block.content,
      ...(block.cacheControl ? { cache_control: { type: 'ephemeral' as const } } : {}),
    }));
    if (dynamicBlock) {
      system.push({ type: 'text', text: dynamicBlock.content });
    }

    const body: any = {
      model,
      system,
      messages, // already in Anthropic format from buildAPIMessages() → buildAnthropicMessages()
      max_tokens: 16384,
      temperature: 0.3,
    };

    // Tools: Anthropic uses input_schema instead of parameters
    if (tools.length > 0) {
      body.tools = tools.map(t => ({
        name: t.name,
        description: t.description,
        input_schema: t.parameters,
      }));
    }

    // Retry loop
    // Rate-limit-aware retry: up to 5 attempts for 429s (transient, always resolve)
    const MAX_RETRIES = 5;
    let lastError: Error | null = null;
    for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
      try {
        const response = await fetch('https://api.anthropic.com/v1/messages', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
            'anthropic-beta': 'prompt-caching-2024-07-31',
          },
          body: JSON.stringify(body),
          signal: AbortSignal.timeout(300_000), // 5 min timeout
        });

        // Rate limit: parse retry-after header or wait 30s default
        if (response.status === 429) {
          const retryAfter = response.headers.get('retry-after');
          const waitMs = retryAfter ? Math.ceil(parseFloat(retryAfter) * 1000) : 30_000;
          const errorText = await response.text();
          console.log(`  ⚠️ Anthropic rate limited — waiting ${(waitMs / 1000).toFixed(0)}s before retry ${attempt + 1}/${MAX_RETRIES} (${errorText.substring(0, 120)})`);
          lastError = new Error(`Anthropic rate limit`);
          await new Promise(r => setTimeout(r, waitMs));
          continue;
        }

        // Server errors: shorter backoff
        if (response.status === 529 || (response.status >= 500 && response.status < 600)) {
          const backoff = (attempt + 1) * 2000;
          const errorText = await response.text();
          console.log(`  ⚠️ Anthropic server error ${response.status} — retrying in ${backoff}ms: ${errorText.substring(0, 120)}`);
          lastError = new Error(`Anthropic error ${response.status}`);
          await new Promise(r => setTimeout(r, backoff));
          continue;
        }

        if (!response.ok) {
          const errorText = await response.text();
          throw new Error(`Anthropic error ${response.status}: ${errorText.substring(0, 200)}`);
        }

        const data = await response.json() as any;

        // Log usage + cache stats
        if (data.usage) {
          const prompt = data.usage.input_tokens || 0;
          const completion = data.usage.output_tokens || 0;
          const cacheCreation = data.usage.cache_creation_input_tokens || 0;
          const cacheRead = data.usage.cache_read_input_tokens || 0;
          const totalInput = prompt + cacheRead + cacheCreation;
          const cacheRate = totalInput > 0 ? ((cacheRead / totalInput) * 100).toFixed(1) : '0.0';
          console.log(`  ✍️ Usage: input=${totalInput} (uncached=${prompt}, cache_read=${cacheRead}, cache_write=${cacheCreation}), completion=${completion}, cache_hit=${cacheRate}%`);
        }

        const finishReason = data.stop_reason || null;
        const completionTokens = data.usage?.output_tokens || 0;
        console.log(`  ✍️ Finish: ${finishReason || '--'}, completion=${completionTokens}`);

        // Parse response content blocks
        let textContent = '';
        const toolCalls: Array<{ id: string; name: string; arguments: Record<string, any> }> = [];

        for (const block of (data.content || [])) {
          if (block.type === 'text') {
            textContent += block.text;
          } else if (block.type === 'tool_use') {
            toolCalls.push({
              id: block.id,
              name: block.name,
              arguments: block.input || {},
            });
          }
        }

        return {
          content: textContent || null,
          toolCalls,
          finishReason,
          completionTokens,
        };
      } catch (error) {
        lastError = error instanceof Error ? error : new Error(String(error));
        if (error instanceof DOMException && error.name === 'TimeoutError') {
          console.log(`  ⚠️ Anthropic timeout (attempt ${attempt + 1}/3)`);
          continue;
        }
        if (attempt === 2) throw error;
      }
    }

    throw lastError || new Error(`Anthropic API failed after ${MAX_RETRIES} attempts`);
  }

  /**
   * OpenRouter fallback — used when ANTHROPIC_API_KEY is not set
   */
  private async callOpenRouter(
    model: string,
    messages: any[],
    tools: any[],
    dynamicBlock: WritingBlock | null,
  ): Promise<{ content: string | null; toolCalls: Array<{ id: string; name: string; arguments: Record<string, any> }>; finishReason: string | null; completionTokens: number }> {
    const apiKey = config.openRouterApiKey;

    const isAnthropicModel = model.includes('anthropic') || model.includes('claude');
    const allBlocks = dynamicBlock ? [...this.blocks, dynamicBlock] : this.blocks;
    const systemContent = isAnthropicModel
      ? allBlocks.map(block => ({
          type: 'text' as const,
          text: block.content,
          ...(block.cacheControl ? { cache_control: { type: 'ephemeral', ttl: '1h' } } : {}),
        }))
      : allBlocks.map(b => b.content).join('\n\n');

    const apiMessages = [
      { role: 'system', content: systemContent },
      ...messages,
    ];

    const body: any = {
      model,
      messages: apiMessages,
      max_tokens: 16384,
      temperature: 0.3,
      provider: {
        order: ['Anthropic'],
        allow_fallbacks: true,
        require_parameters: true,
      },
    };

    if (tools.length > 0) {
      body.tools = tools.map(t => ({
        type: 'function',
        function: { name: t.name, description: t.description, parameters: t.parameters },
      }));
    }

    let lastError: Error | null = null;
    for (let attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        const backoff = attempt * 2000;
        console.log(`  ⏳ Writing retry ${attempt}/2 after ${backoff}ms`);
        await new Promise(r => setTimeout(r, backoff));
      }

      try {
        const response = await fetch(`${config.openRouterBaseUrl}/chat/completions`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${apiKey}`,
            'HTTP-Referer': 'https://cosmoos.app',
            'X-Title': 'CosmoOS Writing Engine',
          },
          body: JSON.stringify(body),
          signal: AbortSignal.timeout(300_000),
        });

        if (response.status === 429 || (response.status >= 500 && response.status < 600)) {
          const errorText = await response.text();
          console.log(`  ⚠️ Writing LLM retryable error ${response.status}: ${errorText.substring(0, 200)}`);
          lastError = new Error(`Writing LLM error ${response.status}`);
          continue;
        }

        if (!response.ok) {
          const errorText = await response.text();
          throw new Error(`Writing LLM error ${response.status}: ${errorText.substring(0, 200)}`);
        }

        const data = await response.json() as any;
        const choice = data.choices?.[0];
        if (!choice) throw new Error('No choices in writing LLM response');

        if (data.usage) {
          const prompt = data.usage.prompt_tokens || 0;
          const completion = data.usage.completion_tokens || 0;
          const cached = data.usage.prompt_tokens_details?.cached_tokens || 0;
          const cacheRate = prompt > 0 ? ((cached / prompt) * 100).toFixed(1) : '0.0';
          console.log(`  ✍️ Usage: prompt=${prompt}, cached=${cached}, completion=${completion}, cache_hit=${cacheRate}%`);
        }

        const finishReason = choice.finish_reason
          || choice.native_finish_reason
          || choice.message?.stop_reason
          || null;

        console.log(`  ✍️ Finish: ${finishReason || '--'}, completion=${data.usage?.completion_tokens || '?'}`);

        const toolCalls = (choice.message?.tool_calls || []).map((tc: any) => ({
          id: tc.id,
          name: tc.function.name,
          arguments: typeof tc.function.arguments === 'string'
            ? JSON.parse(tc.function.arguments)
            : tc.function.arguments,
        }));

        return {
          content: choice.message?.content || null,
          toolCalls,
          finishReason,
          completionTokens: data.usage?.completion_tokens || 0,
        };
      } catch (error) {
        lastError = error instanceof Error ? error : new Error(String(error));
        if (error instanceof DOMException && error.name === 'TimeoutError') {
          console.log(`  ⚠️ Writing LLM timeout (attempt ${attempt + 1}/3)`);
          continue;
        }
        if (attempt === 2) throw error;
      }
    }

    throw lastError || new Error('Writing LLM failed after 3 attempts');
  }

  // ============================================================
  // Build API Messages
  // ============================================================

  /**
   * Build messages for OpenRouter (OpenAI chat/completions format)
   */
  private buildAPIMessages(): any[] {
    const useDirectAnthropic = !!config.anthropicApiKey;
    if (useDirectAnthropic) {
      return this.buildAnthropicMessages();
    }

    const result: any[] = [];

    for (let i = 0; i < this.messages.length; i++) {
      const msg = this.messages[i];

      if (msg.role === 'tool') {
        result.push({
          role: 'tool',
          content: msg.content,
          tool_call_id: msg.toolCallId,
        });
      } else if (msg.toolCalls && msg.toolCalls.length > 0) {
        result.push({
          role: 'assistant',
          content: msg.content || null,
          tool_calls: msg.toolCalls.map(tc => ({
            id: tc.id,
            type: 'function',
            function: { name: tc.name, arguments: JSON.stringify(tc.arguments) },
          })),
        });
      } else {
        result.push({
          role: msg.role === 'system' ? 'user' : msg.role,
          content: msg.content,
        });
      }
    }

    return result;
  }

  /**
   * Build messages for Anthropic Messages API format.
   * Key differences from OpenAI format:
   * - Tool results are user messages with content: [{ type: "tool_result", tool_use_id, content }]
   * - Assistant tool calls are content: [{ type: "tool_use", id, name, input }]
   * - Consecutive same-role messages must be merged
   */
  private buildAnthropicMessages(): any[] {
    const result: any[] = [];

    for (let i = 0; i < this.messages.length; i++) {
      const msg = this.messages[i];

      if (msg.role === 'tool') {
        // Anthropic: tool results are user messages with tool_result content blocks
        // Batch consecutive tool results into one user message
        const toolResults: any[] = [{
          type: 'tool_result',
          tool_use_id: msg.toolCallId,
          content: msg.content,
        }];
        // Look ahead for more consecutive tool results
        while (i + 1 < this.messages.length && this.messages[i + 1].role === 'tool') {
          i++;
          toolResults.push({
            type: 'tool_result',
            tool_use_id: this.messages[i].toolCallId,
            content: this.messages[i].content,
          });
        }
        result.push({ role: 'user', content: toolResults });
      } else if (msg.toolCalls && msg.toolCalls.length > 0) {
        // Assistant message with tool_use blocks
        const content: any[] = [];
        if (msg.content) {
          content.push({ type: 'text', text: msg.content });
        }
        for (const tc of msg.toolCalls) {
          content.push({
            type: 'tool_use',
            id: tc.id,
            name: tc.name,
            input: tc.arguments,
          });
        }
        result.push({ role: 'assistant', content });
      } else if (msg.role === 'user' || msg.role === 'system') {
        // Merge consecutive user messages (Anthropic rejects consecutive same-role)
        const lastMsg = result[result.length - 1];
        if (lastMsg && lastMsg.role === 'user') {
          if (typeof lastMsg.content === 'string') {
            // Both are strings — simple concatenation
            lastMsg.content += '\n\n' + msg.content;
          } else if (Array.isArray(lastMsg.content)) {
            // Previous is tool_result array — append text block
            lastMsg.content.push({ type: 'text', text: msg.content });
          }
        } else {
          result.push({ role: 'user', content: msg.content });
        }
      } else if (msg.role === 'assistant') {
        // Merge consecutive assistant messages (can happen with restored conversations)
        const lastMsg = result[result.length - 1];
        if (lastMsg && lastMsg.role === 'assistant' && typeof lastMsg.content === 'string' && typeof msg.content === 'string') {
          lastMsg.content += '\n\n' + msg.content;
        } else {
          result.push({ role: 'assistant', content: msg.content });
        }
      }
    }

    return result;
  }

  // ============================================================
  // Persist Conversation
  // ============================================================

  private async persistConversation(): Promise<void> {
    // Save ALL messages — tool calls persist for context continuity across phases
    const toSave = this.messages.map(m => {
      // Skip system nudges (they're ephemeral and confuse the LLM on restore)
      if (m.isSystemNudge) return null;

      // Tool results: preserve all (think results in full, others truncated)
      if (m.role === 'tool' && m.toolCallId) {
        const matchingCall = this.messages.find(
          msg => msg.toolCalls?.some(tc => tc.id === m.toolCallId)
        );
        const isThink = matchingCall?.toolCalls?.some(
          tc => tc.id === m.toolCallId && tc.name === 'think'
        );
        // Think results: full content. Other tool results: truncated to 500 chars
        const content = isThink ? m.content : m.content.substring(0, 500);
        return { id: m.id, role: m.role, content, timestamp: m.timestamp, toolCallId: m.toolCallId };
      }

      // Assistant messages with tool calls: preserve ALL tool calls
      if (m.toolCalls && m.toolCalls.length > 0) {
        return {
          id: m.id, role: m.role, content: m.content,
          timestamp: m.timestamp,
          toolCalls: m.toolCalls.map(tc => {
            if (tc.name === 'think') {
              // Think: preserve full thought
              return { id: tc.id, name: tc.name, arguments: { thought: (tc.arguments as any)?.thought || '' } };
            }
            // Other tools: keep name + truncated arguments for context
            const args = tc.arguments || {};
            const truncated: Record<string, any> = {};
            for (const [key, val] of Object.entries(args)) {
              truncated[key] = typeof val === 'string' ? val.substring(0, 500) : val;
            }
            return { id: tc.id, name: tc.name, arguments: truncated };
          }),
        };
      }

      // User + assistant text messages: keep with generous truncation
      if (m.role === 'user' || m.role === 'assistant') {
        return { id: m.id, role: m.role, content: m.content.substring(0, 4000), timestamp: m.timestamp };
      }

      return null;
    }).filter(Boolean);

    await updateAtom(this.contentUUID, {
      structured: {
        writingConversation: toSave,
        writingContext: this.writingContext,
      },
    });
  }

  // ============================================================
  // Tool Definitions
  // ============================================================

  private getToolDefinitions(phase: WritingPhase, pipelineStep?: 'plan' | 'write' | 'edit'): any[] {
    // Pipeline-specific tool sets
    if (pipelineStep === 'plan') {
      return [
        { name: 'think', description: 'Internal reasoning — use before complex decisions', parameters: { type: 'object', properties: { thought: { type: 'string' } }, required: ['thought'] } },
        { name: 'create_writing_plan', description: 'Create a comprehensive writing plan. Must cover: content analysis, voice & style, slide-by-slide blueprint, rules checklist, quality targets. The plan drives the entire draft.', parameters: { type: 'object', properties: { plan: { type: 'string', description: 'The complete writing plan text' } }, required: ['plan'] } },
        { name: 'search_swipes', description: 'Search loaded swipe library', parameters: { type: 'object', properties: { query: { type: 'string' } }, required: ['query'] } },
        { name: 'read_swipe_body', description: 'Load full swipe text', parameters: { type: 'object', properties: { swipe_id: { type: 'string' } }, required: ['swipe_id'] } },
        { name: 'analyze_swipe_patterns', description: 'Analyze patterns across swipe library', parameters: { type: 'object', properties: { focus: { type: 'string', enum: ['hooks', 'persuasion', 'emotional_arc', 'engagement', 'all'] } } } },
      ];
    }

    if (pipelineStep === 'write') {
      return [
        { name: 'think', description: 'Internal reasoning', parameters: { type: 'object', properties: { thought: { type: 'string' } }, required: ['thought'] } },
        { name: 'write_draft', description: 'Write the full draft following your writing plan', parameters: { type: 'object', properties: { content: { type: 'string', description: 'Full draft text or JSON' }, format: { type: 'string', enum: ['plaintext', 'carousel_json', 'thread_json', 'script'] }, selfEvaluation: { type: 'object', properties: { confidenceScore: { type: 'number' }, voiceMatchScore: { type: 'number' }, weakAreas: { type: 'array', items: { type: 'string' } } } } }, required: ['content'] } },
        { name: 'read_draft', description: 'Read the current draft', parameters: { type: 'object', properties: {} } },
      ];
    }

    if (pipelineStep === 'edit') {
      return [
        { name: 'think', description: 'Internal reasoning for self-edit review', parameters: { type: 'object', properties: { thought: { type: 'string' } }, required: ['thought'] } },
        { name: 'write_draft', description: 'Submit corrected draft after self-edit', parameters: { type: 'object', properties: { content: { type: 'string', description: 'Full draft text or JSON' }, format: { type: 'string', enum: ['plaintext', 'carousel_json', 'thread_json', 'script'] }, selfEvaluation: { type: 'object', properties: { confidenceScore: { type: 'number' }, voiceMatchScore: { type: 'number' }, weakAreas: { type: 'array', items: { type: 'string' } } } } }, required: ['content'] } },
        { name: 'read_draft', description: 'Read the current draft', parameters: { type: 'object', properties: {} } },
      ];
    }

    // Default: brainstorm phase tools
    const tools: any[] = [
      { name: 'think', description: 'Internal reasoning — use before complex decisions', parameters: { type: 'object', properties: { thought: { type: 'string' } }, required: ['thought'] } },
      { name: 'update_outline', description: 'Set the content outline sections', parameters: { type: 'object', properties: { sections: { type: 'array', items: { type: 'object', properties: { beatLabel: { type: 'string' }, title: { type: 'string' }, description: { type: 'string' }, estimatedSeconds: { type: 'number' } }, required: ['title'] } }, reasoning: { type: 'string' } }, required: ['sections'] } },
      { name: 'add_hooks', description: 'Add hook variants. MUST match the PRIMARY BLUEPRINT hook format: same case (ALL CAPS if blueprint is caps), same perspective (third-person if blueprint is third-person), same structure pattern (e.g. SUBJECT + VERB + METRICS). No filler phrases or trailing explanations.', parameters: { type: 'object', properties: { hooks: { type: 'array', items: { type: 'object', properties: { text: { type: 'string' }, hookType: { type: 'string' }, estimatedScore: { type: 'number' }, reasoning: { type: 'string' } }, required: ['text'] } } }, required: ['hooks'] } },
      { name: 'search_swipes', description: 'Search loaded swipe library', parameters: { type: 'object', properties: { query: { type: 'string' } }, required: ['query'] } },
      { name: 'read_swipe_body', description: 'Load full swipe text', parameters: { type: 'object', properties: { swipe_id: { type: 'string' } }, required: ['swipe_id'] } },
      { name: 'analyze_swipe_patterns', description: 'Analyze patterns across swipe library', parameters: { type: 'object', properties: { focus: { type: 'string', enum: ['hooks', 'persuasion', 'emotional_arc', 'engagement', 'all'] } } } },
      { name: 'get_client_profile', description: 'Load client profile by name', parameters: { type: 'object', properties: { query: { type: 'string' } }, required: ['query'] } },
    ];

    if (phase === 'brainstorm') {
      tools.push(
        { name: 'set_title', description: 'Update content title', parameters: { type: 'object', properties: { title: { type: 'string' } }, required: ['title'] } },
        { name: 'set_description', description: 'Set content description', parameters: { type: 'object', properties: { description: { type: 'string' } }, required: ['description'] } },
      );
    }

    if (phase === 'draft' || phase === 'polish') {
      tools.push(
        { name: 'write_draft', description: 'Write the full draft', parameters: { type: 'object', properties: { content: { type: 'string', description: 'Full draft text or JSON' }, format: { type: 'string', enum: ['plaintext', 'carousel_json', 'thread_json', 'script'] }, selfEvaluation: { type: 'object', properties: { confidenceScore: { type: 'number' }, voiceMatchScore: { type: 'number' }, weakAreas: { type: 'array', items: { type: 'string' } } } } }, required: ['content'] } },
        { name: 'read_draft', description: 'Read the current draft', parameters: { type: 'object', properties: {} } },
      );
    }

    return tools;
  }

  // ============================================================
  // Load Lessons
  // ============================================================

  private async loadSpecificSwipes(uuids: string[], primaryUUIDs: string[]): Promise<CompressedSwipe[]> {
    const { selectSwipes } = await import('./swipeSelector');
    const swipes: CompressedSwipe[] = [];
    for (const uuid of uuids) {
      const atom = await fetchAtom(uuid);
      if (!atom) continue;
      const isPrimary = primaryUUIDs.includes(uuid);
      // Re-compress with same format as initial selection
      const analysis = atom.structured?.swipeAnalysis || atom.structured || {};
      const fingerprint = (analysis.beatFingerprint as string) || '';
      const hookText = (analysis.hookText as string) || atom.body?.substring(0, 500) || '';
      swipes.push({
        uuid: atom.uuid,
        title: atom.title || 'Untitled',
        hookText,
        hookType: (analysis.hookType as string) || 'Unknown',
        hookScore: (analysis.hookScore as number) || 5,
        beatSequence: fingerprint ? fingerprint.split('>').map((b: string) => b.trim()) : [],
        beatFingerprint: fingerprint,
        keyTransitions: [],
        ctaText: '',
        framework: (analysis.frameworkType as string) || 'Original',
        format: (atom.metadata?.contentSource as string) || 'Unknown',
        isPrimary,
        isClientExample: false,
        engagementSummary: '',
        fullBody: atom.body || '',
        structuralBreakdown: '',
        persuasionTechniques: ((analysis.persuasionTypes as any[]) || []).slice(0, 5).map((p: any) => typeof p === 'string' ? p : p.type || ''),
        emotionalArc: ((analysis.emotions as any[]) || []).slice(0, 6).map((e: any) => typeof e === 'string' ? e : e.name || ''),
        hookScoreReason: (analysis.hookScoreReason as string) || '',
        hookMechanism: (analysis.hookMechanism as string) || '',
        structuralRecipe: (analysis.structuralRecipe as string) || '',
        voiceMarkers: (analysis.voiceMarkers as string[]) || [],
      });
    }
    return swipes;
  }

  /**
   * Build a compact summary of ALL loaded rules for injection right before write_draft.
   * Recency effect: rules at the END of context get the most attention from the LLM.
   * Pulls from actual saved lessons + client voice data — nothing hardcoded, no caps.
   */
  private buildCriticalRulesReminder(): string {
    const rules: string[] = [];

    // ALL hard-enforcement lessons (no cap — designed to accumulate over time)
    const hardLessons = this.lessons.filter(l => l.enforcement === 'hard');
    for (const lesson of hardLessons) {
      const core = lesson.rule.split('\n')[0].replace(/^RULE:\s*/i, '').substring(0, 120);
      rules.push(`• [HARD] ${core}`);
    }

    // Client voice constraints (from loaded profile)
    if (this.clientAtom) {
      const voice = (this.clientAtom.structured?.intelligenceModel as any)?.voiceFingerprint || {};
      if (voice.avgSentenceLength) {
        rules.push(`• [VOICE] Target sentence length: ~${voice.avgSentenceLength} words`);
      }
      const blacklisted = voice.blacklistedPhrases as string[] | undefined;
      if (blacklisted && blacklisted.length > 0) {
        rules.push(`• [VOICE] Banned phrases: ${blacklisted.map((p: string) => `"${p}"`).join(', ')}`);
      }
      const signaturePhrases = voice.signaturePhrases as string[] | undefined;
      if (signaturePhrases && signaturePhrases.length > 0) {
        rules.push(`• [VOICE] Use signature phrases: ${signaturePhrases.map((p: string) => `"${p}"`).join(', ')}`);
      }
    }

    // ALL advisory lessons (no cap)
    const advisoryLessons = this.lessons.filter(l => l.enforcement !== 'hard');
    for (const lesson of advisoryLessons) {
      const core = lesson.rule.split('\n')[0].replace(/^RULE:\s*/i, '').substring(0, 120);
      rules.push(`• [ADVISORY] ${core}`);
    }

    // Format-specific content guidance
    if (this.targetFormat === 'carousel' || this.targetFormat === 'thread') {
      rules.push('• [FORMAT] CAROUSEL: 3-6 sentences/slide, 50-100 words, bullet points (--), specific numbers in EVERY slide');
      rules.push('• [FORMAT] Each slide must TEACH or PROVE something — no empty narrative slides');
      rules.push('• [FORMAT] Count specifics (numbers, $, %, names) in your loaded swipes and MATCH that density');
    } else {
      rules.push('• [FORMAT] REEL: 1-2 sentences/slide, 10-25 words, punchy conversational tone');
    }

    // Write directive
    rules.push('• WRITE the draft using loaded context. Do NOT ask for more information.');

    return rules.join('\n');
  }

  private async loadLessons(): Promise<Array<{ rule: string; enforcement: string; evidence?: string; category?: string; clientUUID?: string }>> {
    const all = await fetchAllByType('agent_learning');
    console.log(`    ✍️ Lessons: ${all.length} agent_learning atoms found`);

    // Log what subtypes/lessonTypes exist in the DB for debugging
    const subtypes = new Map<string, number>();
    for (const a of all) {
      const meta = a.metadata || {};
      const key = `subtype=${meta.subtype || 'none'},lessonType=${meta.lessonType || 'none'}`;
      subtypes.set(key, (subtypes.get(key) || 0) + 1);
    }
    console.log(`    ✍️ Lesson types: ${[...subtypes.entries()].map(([k, v]) => `${k}(${v})`).join(', ')}`);

    const lessons = all.filter(a => {
      const meta = a.metadata || {};
      const subtype = meta.subtype as string | undefined;
      const lessonType = meta.lessonType as string | undefined;

      // Exclude non-lesson subtypes explicitly
      if (subtype === 'standing_instruction' || subtype === 'agent_analysis' || subtype === 'experience') return false;

      // Accept: has a lessonType (any value) OR subtype is 'lesson'
      const isLesson = subtype === 'lesson' || !!lessonType;
      if (!isLesson) return false;

      // Include universal lessons (no clientUUID) + lessons for this specific client
      const lessonClientUUID = meta.clientUUID as string | undefined;
      if (lessonClientUUID && this.clientAtom?.uuid && lessonClientUUID !== this.clientAtom.uuid) {
        return false; // Skip lessons for OTHER clients
      }
      return true;
    });

    console.log(`    ✍️ Lessons: ${lessons.length} matched (client: ${this.clientAtom?.title || 'universal'})`);

    return lessons.map(a => ({
      rule: a.body || a.title || '',
      enforcement: (a.metadata?.enforcement as string) || 'advisory',
      evidence: (a.metadata?.evidence as string) || (a.structured?.evidence as string) || undefined,
      category: (a.metadata?.category as string) || undefined,
      clientUUID: (a.metadata?.clientUUID as string) || undefined,
    }));
  }

  private async loadExperiences(): Promise<Array<{ generated: string; edited: string; summary: string; format?: string }>> {
    const all = await fetchAllByType('agent_learning');
    const experiences = all.filter(a => {
      const meta = a.metadata || {};
      if (meta.lessonType !== 'experience') return false;
      const clientUUID = this.clientAtom?.uuid;
      if (meta.clientUUID && clientUUID && meta.clientUUID !== clientUUID) return false;
      return true;
    });

    return experiences
      .sort((a, b) => {
        // Sort by edit distance (most surprising first)
        const aD = (a.metadata?.editDistance as number) || 0;
        const bD = (b.metadata?.editDistance as number) || 0;
        return bD - aD;
      })
      .slice(0, 3)
      .map(a => ({
        generated: (a.structured?.generatedExcerpt as string) || '',
        edited: (a.structured?.editedExcerpt as string) || '',
        summary: (a.structured?.diffSummary as string) || a.body || '',
        format: a.metadata?.contentFormat as string | undefined,
      }));
  }

  // ============================================================
  // Public Accessors
  // ============================================================

  getOutline(): OutlineItem[] { return this.outline; }
  getHooks(): string[] { return this.hooks; }
  getSwipeCount(): number { return this.selectedSwipes.length; }
  getSwipeTitles(): string[] { return this.selectedSwipes.map(s => s.title); }
  getClientUUID(): string | undefined { return this.clientAtom?.uuid; }

  /** Get loaded swipes as a numbered list with hooks — for context transparency */
  getRefinementCount(): number { return this.refinementCount; }

  getSwipesSummary(): string[] {
    return this.selectedSwipes.map((s, i) => {
      const hook = s.hookText.length > 80 ? s.hookText.substring(0, 80) + '...' : s.hookText;
      const badge = s.isPrimary ? ' [PRIMARY]' : '';
      return `${i + 1}.${badge} "${hook}"`;  // Clean format, no scores
    });
  }
}

// ============================================================
// Deterministic Writing Validators
// Ported from Swift: DeterministicWritingValidators.swift
// These run WITHOUT an API call — pure string pattern matching.
// ============================================================

interface ValidationViolation {
  type: 'banned_phrase' | 'negation_pattern' | 'cadence' | 'static_banned' | 'em_dash';
  message: string;
}

function validateHooksAgainstBlueprint(
  hooks: string[],
  blueprintHook: string,
  userTitle: string,
): string[] {
  const violations: string[] = [];
  const template = userTitle || blueprintHook;
  if (!template) return [];

  // Detect blueprint characteristics
  const bpIsThirdPerson = /^(man|woman|guy|girl|couple|expert|banker|investor|millionaire|[a-z]+ (explains|reveals|shares|shows))/i.test(template);
  const bpHasExplains = /explains:|reveals:|shares:|shows:/i.test(template);
  const bpIsAllCaps = template === template.toUpperCase() && template.length > 10;
  const bpWordCount = template.split(/\s+/).length;

  for (let i = 0; i < hooks.length; i++) {
    const hook = hooks[i];

    // Perspective check: if blueprint is third-person, hooks should be too
    if (bpIsThirdPerson && /^(I |I'|My |We |I just|I got|I paid|I made)/i.test(hook)) {
      violations.push(`Hook ${i + 1}: First-person but blueprint is third-person.`);
    }

    // "explains:" pattern check
    if (bpHasExplains && !/explains:|reveals:|shares:|shows:/i.test(hook)) {
      violations.push(`Hook ${i + 1}: Missing "[Authority] explains:" pattern.`);
    }

    // Case check
    if (bpIsAllCaps && hook !== hook.toUpperCase()) {
      violations.push(`Hook ${i + 1}: Blueprint is ALL CAPS but hook is not.`);
    }

    // Length check (within 50% of blueprint)
    const hookWords = hook.split(/\s+/).length;
    if (hookWords < bpWordCount * 0.5 || hookWords > bpWordCount * 1.5) {
      violations.push(`Hook ${i + 1}: ${hookWords} words vs blueprint ${bpWordCount} words.`);
    }
  }

  return violations;
}

function runDeterministicValidators(
  draft: string,
  lessons: Array<{ rule: string; enforcement: string }>,
): ValidationViolation[] {
  const violations: ValidationViolation[] = [];

  // 1. Static banned phrases (from system prompt VOICE DNA)
  const staticBanned = [
    "in today's", "it's important to note", "it's worth noting", "delve", "dive into",
    "unpack", "harness", "leverage", "utilize", "landscape", "realm", "robust",
    "game-changer", "cutting-edge", "straightforward", "in order to",
    "furthermore", "additionally", "moreover", "moving forward",
    "at the end of the day", "let that sink in", "read that again", "full stop",
    "this changes everything", "supercharge", "unlock your", "future-proof",
    "10x your", "here's the part nobody", "what nobody tells you",
  ];

  const lowerDraft = draft.toLowerCase();
  for (const phrase of staticBanned) {
    if (lowerDraft.includes(phrase)) {
      violations.push({
        type: 'static_banned',
        message: `Banned phrase detected: "${phrase}"`,
      });
    }
  }

  // 2. Negation pattern ("This isn't X. This is Y." and variations)
  const negationPatterns = [
    /this isn['']t .{3,30}\.\s*(this|it)['']?s?\s/gi,
    /forget .{3,20}\.\s*(this|it)/gi,
    /less .{3,20},\s*more .{3,20}/gi,
  ];
  for (const pattern of negationPatterns) {
    const match = draft.match(pattern);
    if (match) {
      violations.push({
        type: 'negation_pattern',
        message: `Fatal pattern "Not X. Y." detected: "${match[0].substring(0, 60)}..." — delete the negation, just state the positive claim`,
      });
      break;
    }
  }

  // 3. Cadence validator — flag 4+ consecutive short fragments (≤5 words)
  const lines = draft.split('\n').filter(l => l.trim().length > 0);
  let consecutiveShort = 0;
  for (const line of lines) {
    const wordCount = line.trim().split(/\s+/).length;
    if (wordCount <= 5) {
      consecutiveShort++;
      if (consecutiveShort >= 4) {
        violations.push({
          type: 'cadence',
          message: `${consecutiveShort}+ consecutive short lines (≤5 words) — vary sentence length for rhythm`,
        });
        break;
      }
    } else {
      consecutiveShort = 0;
    }
  }

  // 4. Lesson-derived rule enforcement (parse multiple rule formats from hard rules)
  const hardRules = lessons.filter(l => l.enforcement === 'hard');
  for (const rule of hardRules) {
    const ruleText = rule.rule;
    const bannedPhrases: string[] = [];

    // Pattern 1: never use "X" / avoid "X" (quoted)
    const quotedMatches = ruleText.matchAll(/(?:never use|avoid|don't use|do not use|stop using|ban|eliminate)\s+["'](.+?)["']/gi);
    for (const m of quotedMatches) bannedPhrases.push(m[1]);

    // Pattern 2: BAD: "X" (from RULE/BAD/GOOD format)
    const badMatches = ruleText.matchAll(/BAD:\s*["'](.+?)["']/gi);
    for (const m of badMatches) bannedPhrases.push(m[1]);

    // Pattern 3: "X are NOT used" / "X is NOT used" / "X are never used"
    const notUsedMatch = ruleText.match(/["']?(.+?)["']?\s+(?:are|is)\s+(?:NOT|never)\s+used/i);
    if (notUsedMatch) bannedPhrases.push(notUsedMatch[1].replace(/^["']|["']$/g, ''));

    // Pattern 4: "don't X" / "do not X" / "never X" (unquoted, extract subject)
    if (bannedPhrases.length === 0) {
      const unquotedBan = ruleText.match(/(?:don't|do not|never)\s+(?:use|start with|begin with|include|write)\s+(.+?)(?:\.|,|$)/i);
      if (unquotedBan) {
        const phrase = unquotedBan[1].trim().replace(/^["']|["']$/g, '');
        if (phrase.length >= 3 && phrase.length <= 60) bannedPhrases.push(phrase);
      }
    }

    // Check each extracted banned phrase against draft
    for (const phrase of bannedPhrases) {
      if (phrase.length < 2) continue;
      if (lowerDraft.includes(phrase.toLowerCase())) {
        violations.push({
          type: 'banned_phrase',
          message: `Learned rule violation: "${phrase}" found in draft (rule: ${ruleText.substring(0, 80)})`,
        });
      }
    }
  }

  // 5. Em-dash detection — extract text content from JSON drafts to avoid false positives
  let textToCheck = draft;
  try {
    const parsed = JSON.parse(draft);
    if (parsed.slides && Array.isArray(parsed.slides)) {
      textToCheck = parsed.slides.map((s: any) => s.text || '').join('\n');
    } else if (parsed.tweets && Array.isArray(parsed.tweets)) {
      textToCheck = parsed.tweets.map((t: any) => t.text || t.content || '').join('\n');
    }
  } catch {} // Not JSON — check full draft

  const contentLines = textToCheck.split('\n').filter(l => !l.match(/^Slide \d+/i));
  const emDashMatches = contentLines.join('\n').match(/[\u2014\u2013]/g);
  if (emDashMatches) {
    violations.push({
      type: 'em_dash',
      message: `${emDashMatches.length} em-dash(es) found in content. Replace ALL with commas, periods, colons, semicolons, or parentheses. Em-dashes are NEVER used in your loaded swipes.`,
    });
  }

  // 6. Split sentence detection — periods mid-line creating short fragments
  // BAD: "dropped out. went full-time in a restaurant. hated every second of it."
  // GOOD: "dropped out and went full-time in a restaurant, hated every second of it"
  // BAD: "head chef threw his cigarette on the floor. told me to clean it."
  // GOOD: "head chef threw his cigarette on the floor and told me to clean it"
  for (const line of contentLines) {
    const trimmed = line.trim();
    if (trimmed.length < 10) continue;
    // Split on ". " (period + space) — not end-of-line periods
    const fragments = trimmed.split(/\.\s+/).filter(f => f.trim().length > 0);
    if (fragments.length >= 2) {
      // Check if all fragments are short (≤10 words each) — indicates split sentence, not legitimate multiple sentences
      const allShort = fragments.every(f => f.trim().split(/\s+/).length <= 10);
      if (allShort) {
        violations.push({
          type: 'cadence',
          message: `Split sentence detected: "${trimmed.substring(0, 80)}..." — merge into one flowing sentence. Periods mid-slide break conversational rhythm. Use commas or "and" instead.`,
        });
        break; // One warning is enough to trigger auto-refinement
      }
    }
  }

  return violations;
}

/**
 * Check draft against client voice fingerprint for compliance.
 * Ported from Swift: verifyVoiceCompliance()
 */
function checkVoiceCompliance(draft: string, clientAtom: Atom | null): string[] {
  if (!clientAtom) return [];

  const violations: string[] = [];
  const intel = clientAtom.structured?.intelligenceModel || {};
  const voice = intel.voiceFingerprint || {};

  // Extract readable text from JSON drafts
  let textContent = draft;
  try {
    const parsed = JSON.parse(draft);
    if (parsed.slides && Array.isArray(parsed.slides)) {
      textContent = parsed.slides.map((s: any) => s.text || '').join('\n');
    } else if (parsed.tweets && Array.isArray(parsed.tweets)) {
      textContent = parsed.tweets.map((t: any) => t.text || t.content || '').join('\n');
    }
  } catch {} // Not JSON — use full draft

  const lowerDraft = textContent.toLowerCase();

  // 1. Blacklisted phrases
  const blacklisted = voice.blacklistedPhrases as string[] | undefined;
  if (blacklisted && blacklisted.length > 0) {
    for (const phrase of blacklisted) {
      if (lowerDraft.includes(phrase.toLowerCase())) {
        violations.push(`Client-banned phrase detected: "${phrase}"`);
      }
    }
  }

  // 2. Average sentence length check
  const targetLength = voice.avgSentenceLength as number | undefined;
  if (targetLength && targetLength > 0) {
    const sentences = textContent.split(/[.!?]+/).filter(s => s.trim().length > 5);
    if (sentences.length >= 3) {
      const avgWords = sentences.reduce((sum, s) => sum + s.trim().split(/\s+/).length, 0) / sentences.length;
      if (avgWords > targetLength * 1.5) {
        violations.push(`Average sentence length (${avgWords.toFixed(0)} words) exceeds client target (${targetLength} words) by >50%. Shorten sentences.`);
      }
    }
  }

  // 3. Signature phrases — check at least one appears (if client has them)
  const signaturePhrases = voice.signaturePhrases as string[] | undefined;
  if (signaturePhrases && signaturePhrases.length > 0) {
    const hasAny = signaturePhrases.some(p => lowerDraft.includes(p.toLowerCase()));
    if (!hasAny) {
      violations.push(`No signature phrases found. Client uses: ${signaturePhrases.slice(0, 3).map(p => `"${p}"`).join(', ')}. Try to incorporate at least one.`);
    }
  }

  return violations;
}
