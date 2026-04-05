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
import { assembleBlock1, assembleBlock2, assembleBlock3Stable, assembleBlock3Dynamic, getSwipeApplicationRules, WritingBlock, assembleBlock1Codex, assembleBlock3StableCodex, buildCodexSystemPrompt, buildCodexPhase1Prompt, buildCodexPhase2Prompt, buildCodexPhase3Prompt, buildCodexSessionPrompt } from './contextAssembler';
import {
  WritingPhase, WritingMessage, CompressedSwipe, OutlineItem, HookVariant,
  ContentFormat, detectContentFormat, renderDraftForDisplay, validateDraft,
  PhysicsTarget, PhysicsValidationResult,
} from './types';
import { mapBlueprintPhysicsToTargets, extractDraftPhysics, validatePhysics } from './physicsValidator';

const MAX_INNER_ITERATIONS = 5;  // Revisions: think + write + follow-up + safety
const MAX_PHASE_ITERATIONS = 3;  // Pipeline phases: think + tool + text response (or tool + text + safety)
const MAX_SESSION_ITERATIONS = 8; // Single session: plan + write + score + revise + score = 5 typical, 3 buffer

type SlideDepthType = 'sparse_emotional' | 'bridge' | 'proof' | 'detail_dense' | 'payoff' | 'unknown';

interface StructuredSlideContract {
  slideNumber: number;
  beatFunction: string;
  prerequisites: string;
  targetWords: number | null;
  targetWordBand: [number, number] | null;
  targetSentences: number | null;
  targetSentenceBand: [number, number] | null;
  format: string;
  content: string;
  transitionExpectation: string;
  depthType: SlideDepthType;
  allowedAdaptation?: string;
  requiredAddressPrefix?: string | null;
  requiresYearMarker?: boolean;
  physicsTarget?: PhysicsTarget;
}

interface StructuredSlidePlan {
  blueprintSlideCount: number;
  voicePattern: string;
  tensePattern: string;
  directAddressPrefix: string | null;
  endingZoneStartsAt: number;
  slides: StructuredSlideContract[];
}

interface NarrativeValidationViolation {
  kind: 'blueprint_fidelity' | 'conversationality';
  slideNumbers: number[];
  message: string;
  evidence?: string;
}

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

/**
 * Full fresh start — evict engine cache AND clear persisted conversation state on the atom.
 * Use when the user wants to start from scratch on an existing content atom.
 */
export async function freshStartEngine(contentUUID: string): Promise<void> {
  evictEngine(contentUUID);
  await updateAtom(contentUUID, {
    structured: { writingConversation: null, writingContext: null },
    metadata: { selectedSwipeUUIDs: null, outline: null, hooks: null },
  });
  console.log(`  ✍️ Fresh start: cleared engine cache + conversation + swipes + outline + hooks for ${contentUUID}`);
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
  private useCodexMode = false;
  private targetFormat: ContentFormat = 'unknown';

  // Codex-era fields (set by Swift app via Supabase sync)
  private codexOutline: import('./types').CodexOutlineModel | null = null;
  private inheritedArcType: string | null = null;
  private inheritedResearchResults: import('./types').IdeaResearchFinding[] | null = null;
  private inheritedCreativeDirection: string | null = null;
  private inheritedContext: string | null = null;

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
  private structuredSlidePlan: StructuredSlidePlan | null = null;

  // Blueprint anchor — resolved in initialize() (true primary or highest-scoring fallback)
  private blueprintAnchor: CompressedSwipe | null = null;
  private hasTruePrimaryBlueprint = false;
  private hasBlueprintProfile = false;
  private hasWrittenDraft = false;

  // Deep analysis tracking — gates outline/draft/hooks behind substantive thinking
  // Uses analysisDepth as single gate (no boolean flags — they caused bypass-on-revision bugs)
  private analysisDepth = 0;
  private hasCompletedSelfReview = false;
  private writingContext: import('./contextAssembler').WritingContext = {};

  // Current pipeline step — set during conversation loop for tool handlers to reference
  private pipelineStep: 'plan' | 'write' | 'edit' | 'session' | undefined;

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

    // Codex outline + research (from Swift app idea flow)
    // Check both codexOutline (direct) and inheritedCodexOutline (from idea→content promotion)
    const rawOutline = meta.codexOutline || meta.inheritedCodexOutline;
    if (rawOutline) {
      try {
        this.codexOutline = typeof rawOutline === 'string'
          ? JSON.parse(rawOutline)
          : rawOutline;
      } catch { /* ignore parse errors */ }
    }
    this.inheritedArcType = (meta.inheritedArcType as string) || null;
    if (meta.inheritedResearchResults) {
      try {
        this.inheritedResearchResults = typeof meta.inheritedResearchResults === 'string'
          ? JSON.parse(meta.inheritedResearchResults)
          : meta.inheritedResearchResults;
      } catch { /* ignore parse errors */ }
    }
    this.inheritedCreativeDirection = (meta.inheritedCreativeDirection as string) || null;
    this.inheritedContext = (meta.inheritedContext as string) || null;

    // Restore persisted conversation + writing context
    const structured = this.contentAtom.structured || {};
    if (structured.writingConversation && Array.isArray(structured.writingConversation)) {
      this.messages = structured.writingConversation as WritingMessage[];
    }
    if (structured.writingContext) {
      this.writingContext = structured.writingContext as import('./contextAssembler').WritingContext;
      this.analysisDepth = this.writingContext.analysisDepth || 0;
      this.writingPlan = this.writingContext.writingPlan || null;
      this.structuredSlidePlan = (this.writingContext as any).structuredSlidePlan || null;
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

    // Resolve blueprint anchor — use explicit blueprintSwipeUUID, then inheritedSwipeUUIDs[0], then first isPrimary
    const explicitBlueprintUUID = (meta.blueprintSwipeUUID || (meta.inheritedSwipeUUIDs as string[] | undefined)?.[0]) as string | undefined;
    if (explicitBlueprintUUID) {
      let bp = this.selectedSwipes.find(s => s.uuid === explicitBlueprintUUID);
      if (!bp) {
        // Blueprint wasn't in the selected set — force-load it
        console.log(`  ✍️ Blueprint ${explicitBlueprintUUID.substring(0, 8)}... not in selected set — force-loading`);
        const forceLoaded = await this.loadSpecificSwipes([explicitBlueprintUUID], [explicitBlueprintUUID]);
        if (forceLoaded.length > 0) {
          this.selectedSwipes.unshift(forceLoaded[0]);
          bp = forceLoaded[0];
        }
      }
      if (bp && bp.fullBody) {
        this.blueprintAnchor = bp;
        this.hasTruePrimaryBlueprint = true;
        this.hasBlueprintProfile = !!bp.fullQuarkProfile;
        console.log(`  ✍️ Blueprint anchor resolved by explicit UUID: "${bp.title.substring(0, 60)}"`);
      }
    }
    // Fallback: first isPrimary or highest-scoring
    if (!this.blueprintAnchor) {
      const primary = this.selectedSwipes.find(s => s.isPrimary);
      if (primary && primary.fullBody) {
        this.blueprintAnchor = primary;
        this.hasTruePrimaryBlueprint = true;
        this.hasBlueprintProfile = !!primary.fullQuarkProfile;
      } else {
        const fallback = this.selectedSwipes
          .filter(s => s.fullBody)
          .reduce<CompressedSwipe | null>((best, s) => (!best || s.hookScore > best.hookScore) ? s : best, null);
        this.blueprintAnchor = fallback;
        this.hasTruePrimaryBlueprint = false;
      }
    }

    // Load lessons for this client (also cached for deterministic validation in write_draft)
    const lessons = await this.loadLessons();
    this.lessons = lessons;

    // Load experience buffer (past edit examples) for few-shot learning
    const experiences = await this.loadExperiences();

    // Build blocks — Codex mode or legacy mode
    if (config.useExemplarCodex) {
      // Codex mode: full Codex as Block 1, walkthrough as Block 3A
      const block1 = await assembleBlock1Codex();
      const block2 = await assembleBlock2(this.clientAtom, lessons);

      // Load blueprint walkthrough from the primary swipe's atom
      let walkthrough: string | null = null;
      let blueprintBody: string | null = null;
      if (this.blueprintAnchor) {
        const bpAtom = await fetchAtom(this.blueprintAnchor.uuid);
        walkthrough = (bpAtom?.structured as any)?.blueprintWalkthrough || null;

        // Prefer transcriptSlides for blueprint body — they have explicit slide markers
        // so the model can clearly see slide boundaries and count words per slide
        const ts = (bpAtom?.structured as any)?.swipeAnalysis?.transcriptSlides as Array<{ text: string; slideNumber: number }> | undefined;
        if (ts && Array.isArray(ts) && ts.length > 1) {
          blueprintBody = ts
            .sort((a, b) => (a.slideNumber || 0) - (b.slideNumber || 0))
            .map(s => `--- Slide ${s.slideNumber} ---\n${s.text}`)
            .join('\n\n');
          console.log(`  ✍️ Blueprint body: ${ts.length} slides from transcriptSlides (with markers)`);
        } else {
          blueprintBody = this.blueprintAnchor.fullBody || bpAtom?.body || null;
          console.log(`  ✍️ Blueprint body: raw text (${blueprintBody?.length || 0} chars, no slide markers)`);
        }
        if (walkthrough) {
          console.log(`  ✍️ Blueprint walkthrough loaded: ${walkthrough.length} chars`);
        } else {
          console.log(`  ⚠️ No walkthrough for blueprint — extraction needed first`);
        }
      }

      const block3a = assembleBlock3StableCodex(walkthrough, blueprintBody);

      this.blocks = [block1, block2, block3a];
      this.initialized = true;
      this.useCodexMode = true;

      const clientName = this.clientAtom?.title || 'the client';
      console.log(`  ✍️ Writing engine initialized (CODEX MODE): walkthrough=${!!walkthrough}, client: ${clientName}, format: ${this.targetFormat}`);
    } else {
      // Legacy mode: old methodology + swipes
      const block1 = await assembleBlock1(this.targetFormat);
      const block2 = await assembleBlock2(this.clientAtom, lessons);
      const block3a = await assembleBlock3Stable(
        this.selectedSwipes,
        this.clientAtom?.metadata?.niche as string | null || null,
        experiences,
      );

      this.blocks = [block1, block2, block3a];
      this.initialized = true;
      this.useCodexMode = false;

      console.log(`  ✍️ Writing engine initialized (legacy): ${this.selectedSwipes.length} swipes, ${lessons.length} lessons, client: ${this.clientAtom?.title || 'none'}, format: ${this.targetFormat}`);
    }
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

    // Draft phase: 3-state pipeline
    // State 1: No plan → Phase 1 only (plan + outline + hooks) → return for user confirmation
    // State 2: Plan exists, no draft written → Phase 2+3 (write + self-edit)
    // State 3: Plan + draft exist → Revision mode
    if (phase === 'draft' && !this.writingPlan) {
      console.log(`  ⚛️ Pipeline State 1: No plan → running Phase 1 (physics plan + outline + hooks)`);
      return this.runPlanPhaseOnly(instruction);
    }
    if (phase === 'draft' && this.writingPlan && !this.hasWrittenDraft) {
      console.log(`  ⚛️ Pipeline State 2: Plan ready (${this.writingPlan.split(/\s+/).length} words) → running Phase 2+3 (write + self-edit)`);
      return this.runWriteAndEditPhases(instruction);
    }
    if (phase === 'draft' && this.writingPlan && this.hasWrittenDraft) {
      console.log(`  ⚛️ Pipeline State 3: Revision mode (plan: ${this.writingPlan.split(/\s+/).length} words, draft exists)`);
    }

    // Brainstorm/polish/revision use normal conversation loop
    console.log(`  ✍️ Conversation loop mode: ${phase} (${this.messages.length} existing messages, analysisDepth: ${this.analysisDepth})`);
    const block3b = this.buildDynamicBlock();

    // Revision protocol: guide the model to think once + write once (not 10 exploratory iterations)
    const isRevision = phase === 'draft' && this.writingPlan;
    const revisionPrefix = isRevision ? `═══ REVISION MODE ═══
Apply the user's feedback surgically. Your writing plan, the blueprint's physics profile,
and all swipe examples are still in your system context. The draft is in conversation history.

1. Think ONCE about what specific slides need to change — reference the plan's WRITE instructions and physics targets for those slides
2. Make the MINIMAL targeted edits — do NOT rewrite slides that weren't flagged
3. Call write_draft with the complete updated draft
4. List what you changed and why

Keep everything that already works. Fix only what the user asked for.

USER FEEDBACK:
` : '';

    this.messages.push({
      id: crypto.randomUUID(),
      role: 'user',
      content: revisionPrefix + instruction,
      timestamp: new Date().toISOString(),
    });

    const result = await this.runConversationLoop(phase, block3b);
    await this.persistConversation();
    return result;
  }

  // ============================================================
  // Single Agentic Session (outline-required, all phases in one call)
  // ============================================================

  /**
   * Single agentic session — outline-required mode.
   * One API call: plan execution → write → self-critique → revise.
   * Used when codexOutline is present (user provided structural skeleton).
   * Opus 4.6 with adaptive thinking — interleaved thinking between tool calls.
   */
  async runSingleSession(userDirection: string): Promise<{ text: string; contentUUID: string }> {
    await this.initialize();
    if (!this.contentAtom) throw new Error('Engine not initialized');
    if (!this.codexOutline?.slides?.length) {
      throw new Error('Single session requires a codex outline');
    }

    this.logPipelineHeader();
    console.log(`  ⚛️ SINGLE SESSION MODE: outline-required, all phases in one call`);
    console.log(`  ⚛️ Outline: ${this.codexOutline.slides.length} slides, arc: ${this.codexOutline.arcShape || 'auto'}`);
    console.log(`  ⚛️ Research: ${this.inheritedResearchResults?.length || 0} findings`);
    console.log(`  ⚛️ Creative direction: ${this.inheritedCreativeDirection ? 'yes' : 'none'}`);

    const block3b = this.buildDynamicBlock();

    // Dump full system prompt for debugging
    console.log(JSON.stringify({
      type: '📋 SESSION_SYSTEM_PROMPT_DUMP',
      blocks: this.blocks.map(b => ({
        label: b.label,
        chars: b.content.length,
        cached: b.cacheControl,
      })),
      dynamicBlock: { label: 'Block 3B: Dynamic', chars: block3b.content.length },
    }));

    const sessionPrompt = buildCodexSessionPrompt(
      userDirection,
      this.targetFormat,
      (this.contentAtom.metadata?.platform as string) || 'instagram',
      this.clientAtom?.title || 'the client',
      this.codexOutline,
      this.inheritedResearchResults,
      this.inheritedCreativeDirection,
      this.hooks.length > 0 ? this.hooks : null,
    );

    this.messages.push({
      id: crypto.randomUUID(),
      role: 'user',
      content: sessionPrompt,
      timestamp: new Date().toISOString(),
    });

    // Single conversation loop — 'session' pipeline step gives access to ALL tools
    const result = await this.runConversationLoop('draft', block3b, 'session');

    this.hasWrittenDraft = true;
    this.writingPlan = 'session'; // Mark plan as existing for revision mode compatibility
    await this.persistConversation();

    // Log full recap
    const finalBody = this.contentAtom?.body || '';
    const finalWords = finalBody.split(/\s+/).filter(Boolean).length;
    const totalThinks = this.messages.filter(m => m.toolCalls?.some(tc => tc.name === 'think')).length;
    const totalWrites = this.messages.filter(m => m.toolCalls?.some(tc => tc.name === 'write_draft')).length;
    const totalPlans = this.messages.filter(m => m.toolCalls?.some(tc => tc.name === 'create_writing_plan')).length;
    const totalCalls = this.messages.filter(m => m.role === 'assistant' && (m.toolCalls?.length || m.content)).length;

    console.log(`\n  ═══ SINGLE SESSION COMPLETE ═══`);
    console.log(`  📋 Final: ${finalWords} words`);
    console.log(`  📋 API calls: ${totalCalls} total (${totalThinks} thinks, ${totalPlans} plans, ${totalWrites} writes)`);
    console.log(`  📋 Messages: ${this.messages.length}`);

    // Full session recap — one copyable JSON log
    const recap: any = {
      type: '📋 SESSION_RECAP',
      client: this.clientAtom?.title || 'unknown',
      blueprint: this.blueprintAnchor?.title?.substring(0, 80) || 'none',
      outlineSlides: this.codexOutline.slides.length,
      arcShape: this.codexOutline.arcShape || 'auto',
      apiCalls: totalCalls,
      thinks: [] as any[],
      plans: [] as any[],
      drafts: [] as any[],
      finalDraft: finalBody,
    };
    for (const msg of this.messages) {
      if (msg.toolCalls) {
        for (const tc of msg.toolCalls) {
          if (tc.name === 'think') {
            recap.thinks.push({ words: ((tc.arguments as any)?.thought || '').split(/\s+/).length });
          } else if (tc.name === 'create_writing_plan') {
            recap.plans.push({ words: ((tc.arguments as any)?.plan || '').split(/\s+/).length, hooks: (tc.arguments as any)?.hookVariants || [] });
          } else if (tc.name === 'write_draft') {
            recap.drafts.push({ words: ((tc.arguments as any)?.content || '').split(/\s+/).length });
          }
        }
      }
    }
    console.log(JSON.stringify(recap));

    return { text: result, contentUUID: this.contentUUID };
  }

  private buildDynamicBlock(): WritingBlock {
    const base = assembleBlock3Dynamic(
      this.contentAtom!,
      this.outline.length > 0 ? this.outline : null,
      this.hooks.length > 0 ? this.hooks : null,
      this.conversationSummary,
      this.writingContext,
    );

    // In Codex mode, prepend the system prompt (role + voice rules + antimatter)
    // to the dynamic block so it's the LAST thing before the conversation —
    // recency bias means these instructions influence generation most strongly.
    if (this.useCodexMode) {
      const clientName = this.clientAtom?.title || 'the client';
      const systemPrompt = buildCodexSystemPrompt(this.targetFormat, clientName);
      return {
        ...base,
        content: systemPrompt + '\n\n' + base.content,
      };
    }

    return base;
  }

  // ============================================================
  // Split Pipeline: Phase 1 (Plan) and Phase 2+3 (Write + Self-Edit)
  // ============================================================

  private logPipelineHeader() {
    const bp = this.blueprintAnchor;
    const profile = bp?.fullQuarkProfile;
    const profileSlides = profile?.slideQuarks?.length || 0;
    const profileTransitions = profile?.transitions?.length || 0;
    const dominantFrame = profile?.arcQuarks?.dominantFrame?.type || 'none';
    const arcShape = profile?.arcQuarks?.shape ? profile.arcQuarks.shape.substring(0, 80) : 'none';
    const symmetryBreak = profile?.physicsEvents?.symmetryBreak?.slideNumber || '?';
    const phaseTransitionLabel = profile?.physicsEvents?.phaseTransition ? `${profile.physicsEvents.phaseTransition.frameBefore} → ${profile.physicsEvents.phaseTransition.frameAfter}` : 'none';
    const peakGravity = profile?.physicsEvents?.peakGravity?.activeLoops || '?';

    console.log(`\n  ═══ CONTENT PHYSICS PIPELINE ═══`);
    console.log(`  📋 Client: ${this.clientAtom?.title || 'none'} | Format: ${this.targetFormat} | Swipes: ${this.selectedSwipes.length}`);
    console.log(`  📋 Blueprint: ${bp ? `"${bp.title.substring(0, 60)}" (${this.hasTruePrimaryBlueprint ? 'TRUE PRIMARY' : 'INFERRED'}, score: ${bp.hookScore}/10)` : 'NONE'}`);
    if (bp?.beatSequence.length) console.log(`  📋 Blueprint beats: ${bp.beatSequence.join(' > ')}`);
    console.log(`  📋 Atomic Profile: ${this.hasBlueprintProfile ? `✅ LOADED (${profileSlides} slides, ${profileTransitions} transitions)` : '❌ NOT AVAILABLE — will use inline analysis'}`);
    if (this.hasBlueprintProfile) {
      console.log(`  📋 Physics: dominant_frame=${dominantFrame} | arc=${arcShape}`);
      console.log(`  📋 Events: symmetry_break=slide${symmetryBreak} | phase_transition=${phaseTransitionLabel} | peak_gravity=${peakGravity}_loops`);
      if (profile?.antimatter?.length) console.log(`  📋 Antimatter: ${profile.antimatter.slice(0, 3).map(a => `"${a}"`).join(', ')}${(profile.antimatter.length || 0) > 3 ? ` (+${(profile.antimatter.length || 0) - 3} more)` : ''}`);
    }
    console.log(`  📋 Lessons: ${this.lessons.length} (${this.lessons.filter(l => l.enforcement === 'hard').length} hard, ${this.lessons.filter(l => l.enforcement !== 'hard').length} advisory)`);
    console.log(`  📋 Blocks: ${this.blocks.map(b => `${b.label}(${(b.content.length / 1024).toFixed(0)}KB${b.cacheControl ? ',cached' : ''})`).join(' + ')}`);
  }

  // Phase 1 ONLY — creates plan + outline + hooks, returns for user confirmation
  private async runPlanPhaseOnly(instruction: string): Promise<string> {
    this.logPipelineHeader();
    console.log(`  📋 Strategy: Phase 1 only → plan + outline + hooks → user confirmation`);

    // Dump full system prompt for debugging — one copyable JSON entry showing everything the model sees
    const debugBlock3b = this.buildDynamicBlock();
    console.log(JSON.stringify({
      type: '📋 FULL_SYSTEM_PROMPT_DUMP',
      blocks: this.blocks.map(b => ({
        label: b.label,
        chars: b.content.length,
        cached: b.cacheControl,
        content: b.content,
      })),
      dynamicBlock: {
        label: 'Block 3B: Dynamic',
        chars: debugBlock3b.content.length,
        content: debugBlock3b.content,
      },
    }));

    console.log(`\n  ⚛️ ─── Phase 1: ${this.hasBlueprintProfile ? 'MAP PHYSICS + PLAN + HOOKS' : 'ANALYZE + PLAN + HOOKS'} ───`);
    console.log(`  ⚛️ Mode: ${this.hasBlueprintProfile ? 'READ atomic profile → MAP to client → create plan with hooks (1 think)' : 'Inline analysis → create plan with hooks (1 think)'}`);
    console.log(`  ⚛️ Tools: think, create_writing_plan, search_swipes, read_swipe_body`);
    const result = await this.runPlanPhase(instruction);

    if (!this.writingPlan) {
      console.log('  ⚠️ No writing plan created — falling back to normal conversation loop');
      const block3b = this.buildDynamicBlock();
      this.messages.push({ id: crypto.randomUUID(), role: 'user', content: instruction, timestamp: new Date().toISOString() });
      const loopResult = await this.runConversationLoop('draft', block3b);
      await this.persistConversation();
      return loopResult;
    }

    console.log(`  ⚛️ Phase 1 complete: plan=${this.writingPlan.split(/\s+/).length} words, outline=${this.outline.length} slides, hooks=${this.hooks.length}`);
    console.log(`  ⚛️ Waiting for user confirmation before Phase 2+3`);

    // Phase 1 recap — copyable JSON with think + plan + hooks
    const phase1Recap: any = {
      type: '📋 PHASE_1_RECAP',
      client: this.clientAtom?.title || 'unknown',
      blueprint: this.blueprintAnchor?.title?.substring(0, 80) || 'none',
      thinks: [] as any[],
      plan: this.writingPlan,
      planWords: this.writingPlan.split(/\s+/).length,
      hooks: this.hooks,
      outline: this.outline.map((o: any) => `${o.sortOrder + 1}. ${o.title}`),
    };
    for (const msg of this.messages) {
      if (msg.toolCalls) {
        for (const tc of msg.toolCalls) {
          if (tc.name === 'think') {
            phase1Recap.thinks.push({ words: ((tc.arguments as any)?.thought || '').split(/\s+/).length, content: (tc.arguments as any)?.thought || '' });
          }
        }
      }
    }
    console.log(JSON.stringify(phase1Recap));

    await this.persistConversation();
    return result;
  }

  // Phase 2+3 — writes the draft and self-edits, called after user confirms plan
  private async runWriteAndEditPhases(instruction?: string): Promise<string> {
    if (!this.writingPlan) {
      console.log('  ⚠️ No writing plan — cannot run Phase 2+3');
      return 'No writing plan exists. Run Phase 1 first.';
    }

    console.log(`\n  ⚛️ ─── Phase 2: WRITE (direct from plan + think + profile) ───`);
    console.log(`  ⚛️ Sources: plan + full Phase 1 analysis + ${this.hasBlueprintProfile ? 'atomic profile' : 'inline analysis'} + swipe bodies`);
    console.log(`  ⚛️ Mode: Direct write_draft (0 thinks, 1 write)`);
    console.log(`  ⚛️ Blocks: STABLE (full cache hit expected)`);
    await this.runWritePhase();

    const draftBody = this.contentAtom?.body || '';
    const draftWords = draftBody.split(/\s+/).filter(Boolean).length;
    const draftSlides = (draftBody.match(/^Slide \d+/gim) || []).length || (draftBody.match(/^[-=]{3,}$/gm) || []).length + 1;
    console.log(`  ⚛️ Draft written: ${draftWords} words, ~${draftSlides} slides`);

    console.log(`\n  ⚛️ ─── Phase 3: PHYSICS SELF-EDIT ───`);
    console.log(`  ⚛️ Mode: 5-step structured think → write_draft`);
    console.log(`  ⚛️ Priority: distance > techniques > speech act > frame > delta > transition`);
    console.log(`  ⚛️ Blocks: STABLE (full cache hit expected)`);
    const result = await this.runSelfEditPhase();

    this.hasWrittenDraft = true;

    const finalBody = this.contentAtom?.body || '';
    const finalWords = finalBody.split(/\s+/).filter(Boolean).length;
    const finalSlides = (finalBody.match(/^Slide \d+/gim) || []).length || (finalBody.match(/^[-=]{3,}$/gm) || []).length + 1;
    const totalThinks = this.messages.filter(m => m.toolCalls?.some(tc => tc.name === 'think')).length;
    const totalWrites = this.messages.filter(m => m.toolCalls?.some(tc => tc.name === 'write_draft')).length;
    const totalCalls = this.messages.filter(m => m.role === 'assistant' && (m.toolCalls?.length || m.content)).length;
    console.log(`\n  ═══ CONTENT PHYSICS PIPELINE COMPLETE ═══`);
    console.log(`  📋 Final: ${finalWords} words, ~${finalSlides} slides`);
    console.log(`  📋 API calls: ${totalCalls} total (${totalThinks} thinks, ${totalWrites} writes, ${totalCalls - totalThinks - totalWrites} other)`);
    console.log(`  📋 Messages: ${this.messages.length}`);

    // Full pipeline recap — one copyable JSON log with everything
    const recap: any = {
      type: '📋 FULL_PIPELINE_RECAP',
      client: this.clientAtom?.title || 'unknown',
      blueprint: this.blueprintAnchor?.title?.substring(0, 80) || 'none',
      hasProfile: this.hasBlueprintProfile,
      swipeCount: this.selectedSwipes.length,
      apiCalls: totalCalls,
      thinks: [] as any[],
      plans: [] as any[],
      drafts: [] as any[],
      validations: [] as any[],
      responses: [] as any[],
      finalDraft: finalBody,
    };

    for (const msg of this.messages) {
      if (msg.toolCalls) {
        for (const tc of msg.toolCalls) {
          if (tc.name === 'think') {
            recap.thinks.push({ words: ((tc.arguments as any)?.thought || '').split(/\s+/).length, content: (tc.arguments as any)?.thought || '' });
          } else if (tc.name === 'create_writing_plan') {
            recap.plans.push({ words: ((tc.arguments as any)?.plan || '').split(/\s+/).length, content: (tc.arguments as any)?.plan || '', hooks: (tc.arguments as any)?.hookVariants || [] });
          } else if (tc.name === 'write_draft') {
            recap.drafts.push({ words: ((tc.arguments as any)?.content || '').split(/\s+/).length, format: (tc.arguments as any)?.format || 'unknown', content: (tc.arguments as any)?.content || '' });
          }
        }
      }
      // Capture tool results that contain validation info
      if (msg.role === 'tool' && msg.content && (msg.content.includes('violation') || msg.content.includes('REJECTED'))) {
        recap.validations.push(msg.content.substring(0, 2000));
      }
      // Capture assistant text responses (summaries, explanations)
      if (msg.role === 'assistant' && msg.content && !msg.toolCalls?.length) {
        recap.responses.push(msg.content.substring(0, 1000));
      }
    }

    console.log(JSON.stringify(recap));

    await this.persistConversation();
    return result;
  }

  private async runPlanPhase(instruction: string): Promise<string> {
    const label = this.getBlueprintLabel();
    const clientName = this.clientAtom?.title || 'the client';

    // Codex mode: use the compact reconstruction plan prompt
    if (this.useCodexMode) {
      const codexInstruction = buildCodexPhase1Prompt(
        instruction,
        this.targetFormat,
        this.contentAtom?.metadata?.platform as string || 'instagram',
        clientName,
        this.codexOutline,
        this.inheritedResearchResults,
        this.inheritedCreativeDirection,
      );
      console.log(`  📋 Phase 1 (Codex mode): reconstruction plan for ${clientName}`);
      this.messages.push({
        id: crypto.randomUUID(),
        role: 'user',
        content: codexInstruction,
        timestamp: new Date().toISOString(),
      });
      const block3b = this.buildDynamicBlock();
      return this.runConversationLoop('brainstorm', block3b, 'plan');
    }

    const hasProfile = this.hasBlueprintProfile;
    const planInstruction = `${instruction}

═══ PHASE 1: STUDY & PLAN ═══

You're about to write a ${this.targetFormat} for ${clientName}. Before you write a single word, you need to understand exactly what makes the loaded reference posts work — then build a plan so detailed that writing becomes mechanical execution.

Your analysis must be comprehensive — this is where quality is determined. A thin analysis produces a thin plan which produces a thin draft.

────────────────────────────────────────
THINK 1: ${hasProfile ? 'MAP THE BLUEPRINT\'S PHYSICS TO THE CLIENT\'S STORY' : `DISSECT THE ${label}`} (all dimensions in ONE think)
────────────────────────────────────────

${hasProfile ? `The ${label}'s complete atomic profile is loaded in your context under "BLUEPRINT PHYSICS SPECIFICATION." This was extracted by a dedicated 10-pass deep analysis — DO NOT re-analyze the blueprint's quarks from scratch. Instead, READ the profile and MAP it to the client's story.

For each slide in the blueprint's profile:
1. READ the slide's quarks: speech act + mechanism, reader delta + mechanism, experiential distance, techniques, frame
2. DECIDE what client content fills this slot. Cite specific details from the brand story.
3. NOTE any adaptation needed — where the client's story doesn't have a direct parallel, identify the EMOTIONAL EQUIVALENT that preserves the quark physics.
4. FLAG slides where the experiential distance target is "zero" — these are the hardest to replicate. The client's version must also be INSIDE the moment (no explaining, no reporting, no "I decided to"). Zero distance = the reader IS there.

Then MAP the macro physics to the client's story:
- How does the client's story map to the blueprint's arc shape?
- Which client events become the symmetry break, phase transition?
- Which client details create the long-range bonds and entanglement pairs?
- What is the client-specific antimatter? (phrases/structures that would collapse THEIR version)

Also verify from the profile + blueprint body:
1b. BEAT MAP — confirm slide count and beat functions (the profile's slideQuarks give you the function per slide)
1c. DENSITY — Count the actual words per slide in the blueprint's FULL BODY (in your loaded swipe examples). These are your density targets (±10%). If the blueprint body only shows partial text, use the client's top performing posts in the SAME FORMAT (carousel for carousel, reel for reel) as your density reference. Every slide must still pass the one-breath test from the Slide Density skill module.
1d. VISUAL FORMAT — read techniques per slide for formatting cues (line breaks, ALL CAPS, bullets, fragments)
1e. HOOK ANATOMY — read slide 1's techniques, experiential distance, and the blueprint's actual hook text. Match: Case, Person, Structure, Word count, Ending punctuation.
1f. TRANSITIONS — read the transitions array (pre-analyzed with mechanisms and swap tests)
1g. COLD AUDIENCE TEST — still required: read the CLIENT'S story slide by slide as a STRANGER. Flag any slide that references unestablished context or makes emotional jumps without bridges. Note prerequisites.
1h. FORMAT CONSISTENCY & TENSE — identify from the blueprint body: voice pattern (e.g., "Dad, I..."), tense pattern (consistent past? past→present payoff?), WHERE any shifts occur.`

: `Call the think tool ONCE to analyze the ${label} across ALL of these dimensions. Find the swipe labeled [${label}] in your loaded examples — this is the post your draft must structurally ${this.hasTruePrimaryBlueprint ? 'mirror' : 'use as its primary reference'}. Work through EVERY item below in a single comprehensive analysis:

1a. SLIDE COUNT
    Go through the ${label}'s body text. Each "Slide N" marker (or separator like ---) is a new slide.
    Write down the total: "The ${label} has N slides."

1b. BEAT MAP
    For each slide, identify TWO things:
    - Its FUNCTION — what job does this slide do? Common beat functions: Hook, Context, Teach, Prove, Story, Reframe, Reveal, CTA.
    - Its SPECIFIC CONTENT vs its FUNCTION — note these separately.
    Write it out: Slide 1 = [Hook] — opens with a surprising claim. Slide 2 = [Context] — explains origin...

1c. DENSITY MEASUREMENT
    For slides 1, 3, the middle slide, and the last slide, count: Words, Sentences, Lines.
    These are your exact density targets per slide position (±10%).

1d. VISUAL FORMAT
    For each slide, note: bullet points? line breaks? short fragments or flowing sentences? ALL CAPS?

1e. HOOK ANATOMY
    Slide 1: Case (ALL CAPS / Title / lowercase), Person (first/third/second), Structure (sentence skeleton), Word count, Ending punctuation.

1f. TRANSITIONS
    For 3-4 consecutive slide pairs, identify the invisible connector.

1g. COLD AUDIENCE TEST
    Read slide by slide as a STRANGER. Flag unestablished context or emotional jumps.

1h. FORMAT CONSISTENCY & TENSE PATTERN
    Voice pattern, tense pattern (a-d), where shifts occur.

1i. QUARK ANALYSIS (three passes — reference the Quark Layer section in your methodology)

    PASS 1 — MICRO (per slide): Speech act + mechanism, reader delta + text mechanism, proof type, motivation, compression.
    Format: "Slide 4: confession — 6 words, direct, names failure, no excuse. Reader: empathy+ (sensory detail), identification+ (universal gap)."

    PASS 2 — MESO (per slide pair): Transition type + mechanism, inevitability test.
    Format: "Slide 5→6: doubt→reaffirmation — creates reader need to know outcome. Swap: impossible."

    PASS 3 — MACRO: Win/loss alternation, tension curve, internal/external tension, payoff uniqueness.

    PASS 4 — RSV TRAJECTORY at 5 key boundaries: open loops, trust, tension, pattern expectation, frame, energy balance.
    Then identify: SYMMETRY BREAK, PHASE TRANSITION, ENERGY RESOLUTION, PEAK GRAVITY.

    Compare to the CONTENT PHYSICS CODEX (if present).`}

Also in the SAME think, cover:

SWIPE CALIBRATION (scan 3-5 support swipes):
- DENSITY RANGE: Count words in 3 swipes' slide 1, middle, and last. The ${label}'s density is your TARGET. The range tells you acceptable bounds.
- FORMAT DNA: What formatting patterns appear in MOST swipes? (line breaks, dashes, sentence length) 5+ swipes = requirement. 1-2 = that author's style.
- DEPTH RHYTHM: Measure information density per slide. Sparse emotional beats vs dense proof beats. Your draft must match this rhythm.
- QUARK PATTERNS: ${hasProfile ? 'Cross-reference support swipes\' quark summaries against the blueprint\'s profile. What patterns repeat? Where does the blueprint deviate?' : 'Cross-reference quark summaries across swipes.'}

CLIENT ABSORPTION:
- REAL DETAILS: Pull every specific detail from the brand story — names, numbers, dates, locations. MANDATORY.
- VOICE FINGERPRINT: Sentence length targets, banned phrases (memorize), signature phrases (use 2-3 naturally). Read TOP PERFORMING POSTS for rhythm and word choices.
- LESSONS: Read LEARNED WRITING RULES. Hard rules = non-negotiable. Note how each applies to THIS draft.

This is ONE think covering the full analysis. Do NOT call think a second time.

────────────────────────────────────────
STEP 2: BUILD THE WRITING PLAN
────────────────────────────────────────

IMMEDIATELY after your think, call create_writing_plan with a plan structured EXACTLY like this:

SLIDE-BY-SLIDE PLAN (structure from blueprint + physics understanding + client content)

The blueprint IS your structural skeleton. Match its slide count, density per position, and arc shape closely. Content Physics tells you WHY each slide works — use that understanding to write each slide with intent, not just fill a template.

For EACH SLIDE (same count as the blueprint), write:
  Slide N: [beat function — what this slide DOES in the arc]
  Blueprint reference: [what the blueprint's actual slide says — READ it from the body, note word count and format]
  Physics (WHY it works): [speech act + mechanism, reader delta + what creates it, experiential distance.
    Describe the mechanism, not just label it.
    Example: "Second-person 'Your' collapses distance between abstract data and daily life.
    The reader isn't reading about inflation — they're feeling their wallet shrink."]
  Transition to next: [what pressure in THIS slide forces the reader to the next?]
  Client content: [what specific client details fill this slot — names, numbers, dates from brand story and research briefing]
  WRITE: [PRESCRIPTIVE CRAFT INSTRUCTION for this slide.
    - Target density: match the blueprint slide's actual word count (READ the body — ±10%)
    - Sentence structure and formatting: guided by the blueprint's formatting for this position
    - What to include vs omit
    - How it should feel when read aloud — must pass the Dinner Table Test
    - WHY this technique creates the planned reader delta
    - What the client's version sounds like vs the blueprint's version]

Good WRITE: "~40 words, matching blueprint slide 1. 3 dash bullets with 'Your' + specific %. Contrast line breaks the bullet pattern. Agenda line with colon. Should feel like being accused by statistics — the reader can't escape because gas, groceries, and the dollar are things they buy every day."
Bad WRITE: "Write an alarm slide." (too vague — no craft direction, no density, no mechanism)

Where the client's story doesn't have a direct parallel to the blueprint slide:
  ADAPTED: [blueprint's function for this slide] → [client equivalent that preserves the emotional job and physics. The beat function must still land — through the client's authentic story, not a forced parallel.]

Each slide must introduce UNIQUE content. If two slides reference the same statistics, consolidate.
A stranger who has NEVER seen this person must understand every slide. Flag prerequisites.

VOICE PATTERN
  [The consistent format the draft must maintain on EVERY slide — from your analysis]
  Example: "Every slide addresses Dad directly with 'Dad, I...' No narration. No third-person."

TENSE PATTERN
  [The tense pattern from your analysis — where shifts occur and why]
  Example: "Past tense throughout slides 1-20 (story narration), shifts to present tense at slide 21 (emotional resolution/payoff)"

VOICE RULES
  Target sentence length: ___
  Signature phrases to include: ___
  BANNED (instant rewrite): ___
  Tone match: [describe based on the client's real posts, not generic adjectives]

COLD AUDIENCE FLOW
  For each slide: what does the audience already know at this point?
  Flag any slide that references something not yet established.
  Flag any emotional jump that needs a bridge slide.

HARD RULES THAT APPLY
  List every hard lesson. For each one, note how it applies to THIS draft specifically.

HOOK SPECIFICATION
  Case: ___ | Person: ___ | Structure: ___ | Words: ___ | Ending: ___

DENSITY TARGETS
  [For each zone: sparse / moderate / dense. Reference the actual blueprint body for calibration — read how long each slide actually is. The body is truth, not the waveform.]

ARC QUARKS
  Win/loss pattern: [describe the oscillation — e.g., "fail-struggle-smallwin-bigwin-loss-grind-hugewin-emptiness-restart-peace"]
  Tension peaks at slides: [list slide numbers where stakes are highest]
  Internal/external tension: [where does external success meet internal struggle?]
  Payoff uniqueness: [what does the ending do that no earlier slide did?]

RSV TRAJECTORY (reader's cumulative state at key boundaries)
  After slide 1: [open loops, trust, tension, pattern, frame, energy]
  After slide ~5: [...]
  At midpoint: [...]
  At phase transition (slide ___): [...]
  At final slide: [...]

RSV PHYSICS
  Pattern established by slides 1-___: [describe the pattern the reader learns to expect]
  Symmetry break at slide ___: [what breaks and why it's devastating]
  Phase transition at slide ___: [frame A → frame B — what shifts and what it recontextualizes]
  Peak gravity at slide ___: [how many active loops, list them]
  Energy resolution: [is the total payoff proportional to the total buildup? which loops close where?]

ANTIMATTER (phrases, structures, or moves that would DESTROY this post's physics — never use in a draft):
  [List the specific antimatter derived from the blueprint's analysis. What would collapse the earned trust, break the voice, or annihilate the accumulated physics?]

HOOK VARIANTS (pass 3-4 variants via the hookVariants parameter of create_writing_plan):
${this.hasBlueprintProfile && this.blueprintAnchor?.fullQuarkProfile?.slideQuarks?.[0] ? `
The blueprint's hook slide (slide 1) has these physics — your hooks must produce the SAME effects:
  Speech Act: ${this.blueprintAnchor.fullQuarkProfile.slideQuarks[0].speechAct?.type || '?'} — ${this.blueprintAnchor.fullQuarkProfile.slideQuarks[0].speechAct?.mechanism || '?'}
  Reader Delta: ${(this.blueprintAnchor.fullQuarkProfile.slideQuarks[0].readerDeltas || []).map((d: any) => `${d.type}${d.mechanism ? ` (${d.mechanism})` : ''}`).join(', ') || '?'}
  Distance: ${this.blueprintAnchor.fullQuarkProfile.slideQuarks[0].experientialDistance?.level || '?'} — ${this.blueprintAnchor.fullQuarkProfile.slideQuarks[0].experientialDistance?.mechanism || '?'}
  Techniques: ${(this.blueprintAnchor.fullQuarkProfile.slideQuarks[0].techniques || []).map((t: any) => t.technique).join(', ') || '?'}
  Frame: ${this.blueprintAnchor.fullQuarkProfile.slideQuarks[0].frame?.type || '?'}` : 'Analyze the blueprint hook for speech act, reader delta, techniques, and distance.'}

Your hook variants must produce the SAME physics:
- If the blueprint creates curiosity+ via an open loop (stat list with no explanation) → your hooks must open the same kind of loop
- If the blueprint creates tension+ via accusatory second-person "Your X costs Y% more" → replicate that tension mechanism
- If the blueprint uses specific techniques (bullet list, number formatting, contrast structure, ALL CAPS) → use the same techniques
- Match the experiential distance: if blueprint hook is zero-distance, don't write a far-distance hook that reports facts
- Match case (ALL CAPS / Title / lowercase), person (first/third/second), structure (sentence skeleton), word count (±5), ending punctuation
- Keep the same sentence skeleton as the user's title: "${this.contentAtom?.title || ''}"
- Use real stats from the research briefing if available — no placeholders
- Each variant takes a different angle/stat while maintaining identical physics
Blueprint hook: "${this.blueprintAnchor?.hookText?.substring(0, 300) || ''}"

Include the hookVariants array in your create_writing_plan call.

This plan is your construction blueprint. The user will review the outline and hooks before Phase 2 writes the draft.`;

    this.messages.push({ id: crypto.randomUUID(), role: 'user', content: planInstruction, timestamp: new Date().toISOString() });

    // Run with plan-phase tools (think + create_writing_plan + swipe tools — NO write_draft)
    const block3b = this.buildDynamicBlock();
    return this.runConversationLoop('draft', block3b, 'plan');
  }

  private async runWritePhase(): Promise<string> {
    console.log(`  ✍️ Write phase: keeping stable blocks for cache (${this.blocks.map(b => `${b.label}(${(b.content.length / 1024).toFixed(0)}KB)`).join(' + ')})`);

    // Codex mode: compact write prompt
    if (this.useCodexMode) {
      const clientName = this.clientAtom?.title || 'the client';
      const writeInstruction = buildCodexPhase2Prompt(clientName);
      console.log(`  ✍️ Write phase (Codex mode): ${clientName}`);
      this.messages.push({
        id: crypto.randomUUID(),
        role: 'user',
        content: writeInstruction,
        timestamp: new Date().toISOString(),
      });
      const block3b = this.buildDynamicBlock();
      return this.runConversationLoop('draft', block3b, 'write');
    }

    // Legacy mode below
    const bp = this.blueprintAnchor;
    const clientName = this.clientAtom?.title || 'the client';
    const voiceContext = this.buildCriticalVoiceContext();
    const rawBody = bp?.fullBody || '[Blueprint body not available]';
    // Parse slide markers for readability — bodies stored as one continuous string are unreadable
    const blueprintBody = /Slide\s*\d+/i.test(rawBody)
      ? rawBody.replace(/Slide\s*(\d+)/gi, '\n\n--- Slide $1 ---\n').trim()
      : rawBody;
    const hardRules = this.lessons
      .filter((l: any) => l.enforcement === 'hard')
      .map((l: any) => `• ${(l.rule || '').split('\n')[0].replace(/^RULE:\s*/i, '')}`)
      .slice(0, 10)
      .join('\n');

    this.messages.push({
      id: crypto.randomUUID(),
      role: 'user',
      content: `Your writing plan is ready. Now write the draft.

═══ YOUR WRITING PLAN ═══
${this.writingPlan}${this.buildStructuredPlanSummary()}

═══ CRITICAL WRITING CONTEXT (highest priority — read before composing) ═══

CLIENT VOICE (${clientName}):
${voiceContext}

${hardRules ? `HARD RULES (non-negotiable — automatic rewrite if violated):\n${hardRules}\n` : ''}BANNED PATTERNS (check EVERY sentence):
- NO em-dashes — use commas, periods, or ellipsis
- NO "This isn't X. This is Y." or ANY variation (Not X. Y. / Forget X. / Less X, more Y.)
- NO triple-beat patterns (X. Y. Z.) — three consecutive short sentences
- NO "leverage," "game-changer," "let that sink in," "unprecedented," "robust," "utilize"
- NO hedging ("perhaps," "it might be," "could potentially")
- NO "in today's [anything]," "furthermore," "additionally," "moreover"

CRAFT RULES (apply to every slide):
- DINNER TABLE TEST IS #1: If a slide sounds like a news report, caption, thesis, or marketing copy — rewrite as speech. This overrides density, structure, everything.
- Write like a sharp human, not a language model. Contractions always.
- Get to the point. No throat-clearing, no preamble, no padding.
- Specific > vague. Use numbers, names, concrete details from the brand story.
- Vary sentence length. Mix short punchy lines with longer ones.
- One slide = one breath. If you need a breath mid-slide, split it.
- Follow the blueprint's structure (slide count, arc). Derive density from the blueprint BODY, not from numbers.
- If any slide's phrasing is >80% similar to the blueprint's text, rewrite from structural function only.
- ALL skill modules apply: density checks, voice matching, causal chaining, self-edit. None are overridden.

PRIMARY BLUEPRINT BODY (this is your density and style reference — QUOTE it before writing each zone):
${blueprintBody}

(The full brand story, all client details, top performing posts, and all swipe examples are
in your system context. Reference them while writing — but the voice rules, banned patterns,
and blueprint body above are your highest-priority writing guardrails.)

═══ WRITE THE DRAFT ═══

You are a ghostwriter for ${clientName}. Write the draft NOW. Call write_draft with the complete carousel.

Your plan has per-slide WRITE instructions. The blueprint body above shows the density and format per slide. The client's voice and real details are in your context. Follow the plan, match the blueprint's structure, use the client's voice. Call write_draft.

────────────────────────────────────────
WHILE COMPOSING EACH SLIDE
────────────────────────────────────────

FOR EACH SLIDE, follow the WRITE instruction from your plan. The WRITE instruction tells you: target density, sentence structure, what to include vs omit, how it should feel when read aloud. Follow it as your primary guide. Then check:

1. PHYSICS: Does this slide produce the planned speech act and reader delta? Is the experiential distance right (zero/near/far)? Does it use the planned techniques?

2. DENSITY FROM THE BODY: Look at the corresponding section of the BLUEPRINT BODY in your loaded examples. How many words per slide? Match that density — not the plan's numbers, not the waveform. READ the body.

3. DINNER TABLE TEST: Would ${this.clientAtom?.title || 'the client'} say this exact thing to a friend at dinner? If it sounds like a caption, a thesis statement, news reporting, or marketing copy — it FAILS. Rewrite as speech. Read the client's TOP PERFORMING POSTS in your context — your slides must sound like the same person wrote them.

4. CLIENT VOICE: Use their real details from the brand story (names, numbers, places). Use their signature phrases where they fit naturally. Keep sentences close to the target length from the voice fingerprint. The client's voice is in Block 2 — reference it.

5. BANNED PHRASES: Check every sentence. NO em-dashes. NO "leverage," "game-changer," "let that sink in." NO "This isn't X, this is Y" or ANY variation (Not X. Y. / Forget X. / Less X, more Y.). NO triple-beat patterns (X. Y. Z.). If ANY banned phrase appears, rewrite immediately.

6. CAUSALITY: Is the transition to the next slide causal? The reader should feel pulled forward. If "and then..." is the only connector, add the pressure or question that makes the next slide inevitable.

7. STATE CHANGE: Does this slide change at least ONE thing in the reader's mind? Zero-delta slides are dead weight.

8. TENSE: Follow the tense pattern from your plan. Shifts only at structural beat transitions. No random tense switching mid-section.

BLUEPRINT AS SKELETON: Follow the blueprint's structure closely — same slide count, same density per position, same arc shape. But ALL words, phrasing, and arguments must be the client's own. If any slide's text is >80% similar to the blueprint's actual text, rewrite using only the structural function and the client's real details.

EVERY SLIDE EARNS ITS PLACE: If a slide doesn't change something in the reader's mind, it's dead weight. If two slides say the same thing, consolidate.

────────────────────────────────────────
THE QUALITY TEST
────────────────────────────────────────

Read your draft, then read the blueprint. Check:
- STRUCTURE: Same slide count? Same density per position (±10%)? Same arc shape?
- PHYSICS: Same emotional journey? Same tension peaks? Same symmetry break and phase transition?
- VOICE: Does every slide sound like ${clientName} talking at dinner? Not a news report, not a caption?
- DENSITY: Count words on your slide 1, 3, middle, last. Compare to the blueprint. Match ±10%.
- BANNED: Any banned phrase anywhere? Fix immediately.
If all pass: draft is ready. If any fail: fix before submitting.

────────────────────────────────────────
WHAT MAKES A DRAFT FAIL (INSTANT REWRITES)
────────────────────────────────────────

- DENSITY MISMATCH: A zone that should feel sparse is crammed with detail, or a zone that should feel dense is too thin. Fix: read the blueprint body for that zone and match its weight.
- GENERIC CLAIMS: You wrote "this changed everything" or "the results were incredible." Fix: replace with specific details from the client's brand story or research briefing.
- HOOK PHYSICS MISMATCH: Your hook doesn't produce the same reader deltas as the blueprint's hook. Fix: rewrite to create the same tension/curiosity/identification.
- BANNED PHRASES: If any phrase from the BANNED list appears ANYWHERE, replace it immediately. Common traps: "in today's", "leverage", "game-changer", "let that sink in", "this isn't X, this is Y."
- AI VOICE DRIFT: Sentences getting longer and more sophisticated. Vocabulary elevated. Hedging. Fix: rewrite as shorter, more direct, more like the client's real posts.
- DISTANCE VIOLATION: Your slide reads like a report but the physics call for zero distance. Fix: cut all explanation, put the reader INSIDE the moment. "I decided to leave" → "Left."
- FRAME VIOLATION: The dominant frame is broken (e.g., a "success" slide in a loss-accumulation zone). Fix: reframe the same content to serve the zone's physics.
- MISSING ZONE: A physics zone from the plan is absent from the draft. Fix: add it.`,
      timestamp: new Date().toISOString(),
    });

    const block3b = this.buildDynamicBlock();
    return this.runConversationLoop('draft', block3b, 'write');
  }

  private async runSelfEditPhase(): Promise<string> {
    console.log(`  ✍️ Self-edit: keeping stable blocks for cache (${this.blocks.map(b => `${b.label}(${(b.content.length / 1024).toFixed(0)}KB)`).join(' + ')})`);

    // Codex mode: compact self-edit prompt
    if (this.useCodexMode) {
      const clientName = this.clientAtom?.title || 'the client';
      const editInstruction = buildCodexPhase3Prompt(clientName);
      console.log(`  ✍️ Self-edit phase (Codex mode): ${clientName}`);
      this.messages.push({
        id: crypto.randomUUID(),
        role: 'user',
        content: editInstruction,
        timestamp: new Date().toISOString(),
      });
      const block3b = this.buildDynamicBlock();
      return this.runConversationLoop('draft', block3b, 'edit');
    }

    // Legacy mode below
    const blueprintSummary = this.getBlueprintStructuralSummary();
    const qualityRules = this.buildCriticalRulesReminder();

    this.messages.push({
      id: crypto.randomUUID(),
      role: 'user',
      content: `Self-edit pass. You are now the EDITOR, not the writer. Your job is to catch everything the writer missed.

Your system context contains: the writing methodology (Block 1), the client profile and voice targets (Block 2), the swipe examples${this.hasBlueprintProfile ? ', the blueprint\'s full atomic profile,' : ''} and pattern intelligence (Block 3A). Reference these as needed.

${blueprintSummary ? `--- BLUEPRINT STRUCTURAL SUMMARY ---\n${blueprintSummary}\n` : ''}${qualityRules ? `--- QUALITY RULES ---\n${qualityRules}\n` : ''}
Call the think tool ONCE. In this single think, work through FIVE steps in order. Then IMMEDIATELY call write_draft with the fully corrected version. Do NOT call think a second time. One think → one write → done.

The two hard gates: CONVERSATIONALITY (speech, not narration) and BLUEPRINT FIDELITY (each slide does the same job as the blueprint slide in that position).

────────────────────────────────────────
STEP 1 — EXTRACT YOUR DRAFT'S ACTUAL PHYSICS
────────────────────────────────────────
For each slide you wrote, identify what you ACTUALLY produced (not what you planned — what you WROTE):
- Speech act: what is this slide actually doing? (Name based on what you wrote, not what you planned)
- Reader delta: what genuinely changes in the reader? (Read it fresh — what genuinely changes?)
- Experiential distance: zero (inside moment, sensory, no explanation), near (telling friend, vivid past tense), far (reporting, formal, observer)?
- Techniques used: what craft moves did you actually use? (subject-drop? ALL CAPS? maximum-compression? casual spelling? ellipsis? direct address? number formatting?)
- Frame: how does this slide position its content? (loss, decision, consequence, success, observation, setup, absurd, compression-punch, transformation)

Write compact per slide: "Slide 1: confession | empathy+,curiosity+ | dist=zero | tech=[subject-drop,compression] | frame=loss"

────────────────────────────────────────
STEP 2 — COMPARE PHYSICS TO BLUEPRINT
────────────────────────────────────────
Read your draft alongside the BLUEPRINT BODY in your loaded examples. For each zone: does the reader FEEL the same things in the same order? Is the density similar (read both aloud — similar breath count)? Then cross-reference the ${this.hasBlueprintProfile ? 'blueprint\'s atomic profile' : 'plan\'s quarks'} for missed physics. Flag every mismatch in priority order:

1. EXPERIENTIAL DISTANCE (priority #1): actual vs target. This determines whether the reader FEELS or just PROCESSES.
   If target is "zero" and your slide reads like "near" or "far" — REWRITE. Zero distance = no explanation, sensory detail, reader simulates directly. "Slept in my car" not "I ended up sleeping in my car because I had nowhere else to go."
   Far distance is almost always wrong for viral content.

2. TECHNIQUES (priority #2): actual vs target. If target says [subject-drop, maximum-compression] and your slide starts with "I" and has 12 words — technique mismatch.
   Techniques are the TOOLS that produce the physics. Wrong tools = wrong physics.

3. SPEECH ACT: actual vs target. "confession" vs "report" = MISS.
   The MECHANISM must match too — if target says "4 words, no explanation" and you wrote 15 words with explanation, the act label might match but the physics don't.

4. DOMINANT FRAME: Does every slide conform to the post's dominant frame?
   A "success" slide in a "museum_of_failures" post breaks the post's identity. Even positive events must be reframed as losses/traps.

5. READER DELTA: actual vs target. If target says "empathy+" and your slide creates "curiosity+" — different physics, different reader experience. Test: can the reader skip this slide without noticing? If yes, delta is zero.

6. TRANSITION: actual vs target. Can you swap this slide and the next without the reader noticing? If yes, transition is broken. Decision/action slides without visible motivation = broken causality.

────────────────────────────────────────
STEP 3 — UNIVERSAL CHECKS
────────────────────────────────────────
Run each of these. For each: PASS or FAIL with specific evidence.

SLIDE COUNT: Does your draft have the same number of slides as the blueprint? Count them. If different, add or merge to match.

DENSITY PER SLIDE: Open the BLUEPRINT BODY in your loaded examples. For the blueprint's slide 1, count actual words. For your slide 1, count actual words. Compare — must be within ±10%. Repeat for slides 3, the middle slide, and the last slide (minimum 4 spot checks). The BLUEPRINT BODY is your density reference.

FORMATTING: Pick slide 3 from your draft and slide 3 from the blueprint. Compare: similar density? Similar formatting style (bullets, line breaks, fragments vs paragraphs)? Repeat for slide 1 and one other. Your slides should feel like they came from the same structural family as the blueprint.

VOICE MATCH: Read your slide 5 as if reading aloud at dinner. Compare to the client's TOP PERFORMING POSTS from the client profile. Do they sound like the same person? What voice drift looks like: sentences getting longer/more complex, sophisticated vocabulary, hedging ("perhaps", "it might be"), sounds "written" instead of "spoken." Pass: same person, same day. Fail: rewrite with shorter sentences, client's vocabulary, their signature phrases.

SPECIFICITY: Count every specific detail in your draft: numbers, names, dates, places, dollar amounts, percentages. Count the same in the ${this.getBlueprintLabel()}. Pass: your count is within 50% of the blueprint's count. Fail: replace generic claims with real details from the brand story.

HOOK FORMAT: Compare your hook (slide 1) to the ${this.getBlueprintLabel()}'s hook on 5 properties: Case (ALL CAPS/lowercase/Title), Person (first/third/second), Structure (sentence skeleton), Length (±5 words), Ending punctuation. All 5 must match.

COLD AUDIENCE FLOW: Read your draft from slide 1 to end as a COMPLETE STRANGER who has never seen this person. For each slide ask: "Do I understand this based ONLY on what previous slides told me?" Flag any slide that: references a role/relationship/place not yet established (e.g., "my head chef" before saying they worked as a chef), makes an emotional jump without a bridge (e.g., "I want to destroy myself" → "I quit everything" with no WHY), uses inside knowledge the audience doesn't have. Example fix: "My head chef threw his cigarette on the floor" → either cut it, or add "Mom, I started working in a kitchen..." before it.

FORMAT CONSISTENCY & TENSE: Identify the voice pattern established in slides 1-3 (e.g., "Mom, I..." dialogue, year markers, first-person narration). Read every slide — does each maintain that exact pattern? Flag any that break it (switches to narration, drops address, changes person/tense). TENSE CHECK: Identify every point where tense changes. Is each shift at a structural beat transition (story→payoff)? Or random mid-section? Tense shifts only at narrative arc transitions.

────────────────────────────────────────
STEP 4 — THREE FORCES + RSV PHYSICS + PLAN ALL FIXES
────────────────────────────────────────

STATE CHANGE: For each slide, does it change at least ONE reader state? A zero-delta slide (nothing changes) is dead weight — the reader's mind processes it without transitioning. Consecutive slides changing SAME thing in SAME direction are redundant — combine or differentiate.

CAUSALITY: For each slide pair, is the transition causal? Insert "so...", "but...", or "that's when..." between them. If none fits AND you can swap them unnoticed, the transition is broken. The arc should show win/loss oscillation. If 3+ consecutive slides are all wins or all losses, the rhythm is broken.

EARNED-NESS: For major moments (decisions, losses, payoffs, relational callbacks): was this moment set up by earlier slides? A relational payoff ("Dad, thank you") requires prior relational investment. Is any compression earned? A time jump after an emotional slide with no directional signal = confusing, not intriguing. Is the ending payoff UNIQUE? If it repeats an earlier slide's beat, the post deflates instead of resolving.

RSV PHYSICS:
- ENERGY CONSERVATION: Count open loops at the post's peak. Count resolutions by the end. If major loops are unresolved or the biggest tension resolves in 1 weak line after 10+ slides of buildup, the energy balance is broken. Fix: add resolution or strengthen the payoff.
- SYMMETRY BREAKING: Read slides 1-5, note what pattern they establish. Find the slide that BREAKS it. If no pattern breaks — the post has no emotional core. If the break is too early (before tension peaks) or too late (no time to resolve), adjust.
- PHASE TRANSITION: Identify where the reader's frame shifts from story type A to type B. If you can describe the post as ONLY one story type start to finish, the phase transition is missing. The strongest posts are TWO stories — the frame shifts mid-post.
- CUMULATIVE GRAVITY: At the phase transition point, are there 3+ active open loops? If fewer, the reader might scroll away before the transition hits. Open more loops in the first half.

ENTANGLEMENT: For each entangled pair in the plan — if you removed your slide X, would your slide Y still make sense? If the bond is broken, fix BOTH sides.

DETECTABILITY: Read the full draft as a SKEPTIC. Flag any slide where the engineering is visible: generic motivation language, manufactured emotional beats, mechanical transitions, CTA that breaks voice. Invisible physics = powerful. Visible physics = collapsed.

NOW PLAN ALL FIXES: For each flagged issue, write the specific fix — what slide, what changes, what the corrected text should achieve. Priority order: distance > techniques > speech act > frame > delta > transition > universal checks.

────────────────────────────────────────
STEP 5 — MENTALLY APPLY AND VERIFY
────────────────────────────────────────
Before writing: mentally apply ALL your planned fixes. Re-read the corrected draft in your head. Does it now pass every check? Does the arc oscillate? Does energy conserve? Does the pattern break? Does the frame shift? Are distance and techniques correct on every slide? Would a stranger follow every slide? Does the voice match the client's real posts?

Then IMMEDIATELY call write_draft with the fully corrected version. Do NOT call think again. One think → one write → done.`,
      timestamp: new Date().toISOString(),
    });

    const block3b = this.buildDynamicBlock();
    let result = await this.runConversationLoop('draft', block3b, 'edit');

    const finalDraft = this.contentAtom?.body || '';
    const blockingViolations = this.getBlockingNarrativeViolations(finalDraft);
    if (blockingViolations.length > 0) {
      console.log(`  ⚠️ Self-edit did not clear blocking narrative violations (${blockingViolations.length}) — forcing repair pass`);
      this.messages.push({
        id: crypto.randomUUID(),
        role: 'user',
        content: `Binding repair pass. The draft still fails the hard gates below. Fix ONLY these exact slide issues and call write_draft with the corrected full draft.\n\n${formatNarrativeViolations(blockingViolations)}`,
        timestamp: new Date().toISOString(),
      });
      result = await this.runConversationLoop('draft', this.buildDynamicBlock(), 'edit');
    }

    return result;
  }

  private getBlueprintLabel(): string {
    return this.hasTruePrimaryBlueprint ? 'PRIMARY BLUEPRINT' : 'STRUCTURAL ANCHOR';
  }

  // Extract critical voice data from client profile for recency positioning
  // (Block 2 has the full data but it's in the middle of 250KB — this puts the essentials at the end)
  private buildCriticalVoiceContext(): string {
    const client = this.clientAtom;
    if (!client) return 'No client profile loaded.';

    const intel = (client.structured as any)?.intelligenceModel;
    const voice = intel?.voiceFingerprint;
    const lines: string[] = [];

    if (voice?.avgSentenceLength) lines.push(`Sentence length: ${voice.avgSentenceLength} words`);
    if (voice?.signaturePhrases?.length) lines.push(`Signature phrases: ${(voice.signaturePhrases as string[]).join(', ')}`);
    if (voice?.blacklistedPhrases?.length) lines.push(`CLIENT-SPECIFIC BANNED: ${(voice.blacklistedPhrases as string[]).join(', ')}`);
    if (voice?.emotionalTone?.length) {
      const tones = (voice.emotionalTone as any[]).slice(0, 3).map((t: any) => typeof t === 'string' ? t : t.name || String(t)).join(', ');
      lines.push(`Tone: ${tones}`);
    }
    if (voice?.formattingQuirks?.length) lines.push(`Formatting: ${(voice.formattingQuirks as string[]).join(', ')}`);

    const positioning = intel?.nicheAndPositioning;
    if (positioning?.specificNiche) lines.push(`Niche: ${positioning.specificNiche}`);
    if (positioning?.uniqueMechanism) lines.push(`Mechanism: ${positioning.uniqueMechanism}`);
    if (positioning?.uniqueAngle) lines.push(`Angle: ${positioning.uniqueAngle}`);

    return lines.join('\n') || 'Voice data not available — match the blueprint and swipe examples.';
  }

  private buildStructuredPlanSummary(): string {
    if (!this.structuredSlidePlan || this.structuredSlidePlan.slides.length === 0) return '';

    const lines: string[] = [];
    lines.push('\n\n═══ STRUCTURED SLIDE CONTRACT ═══');
    lines.push(`Voice Pattern: ${this.structuredSlidePlan.voicePattern || 'unspecified'}`);
    lines.push(`Tense Pattern: ${this.structuredSlidePlan.tensePattern || 'unspecified'}`);
    if (this.structuredSlidePlan.directAddressPrefix) {
      lines.push(`Direct Address Prefix: ${this.structuredSlidePlan.directAddressPrefix}`);
    }
    lines.push(`Blueprint Slide Count: ${this.structuredSlidePlan.blueprintSlideCount}`);
    for (const slide of this.structuredSlidePlan.slides) {
      const words = slide.targetWordBand ? `${slide.targetWordBand[0]}-${slide.targetWordBand[1]} words` : 'flex words';
      lines.push(`Slide ${slide.slideNumber}: [${slide.beatFunction}] ${slide.depthType}, ${words}, transition=${slide.transitionExpectation || 'none'}`);
    }
    return lines.join('\n');
  }

  private getBlockingNarrativeViolations(draft: string): NarrativeValidationViolation[] {
    if (!draft || !this.blueprintAnchor || !this.structuredSlidePlan) return [];

    const draftSlides = extractContentSlides(draft);
    const blueprintSlides = extractContentSlides(this.blueprintAnchor.fullBody || '');
    const blueprintViolations = validateBlueprintFidelity(
      draftSlides,
      blueprintSlides,
      this.structuredSlidePlan,
    );
    const conversationalViolations = validateConversationality(
      draftSlides,
      this.structuredSlidePlan,
    );
    return [...blueprintViolations, ...conversationalViolations];
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
    const slideMatches = body.match(/Slide\s*\d+/gi);
    if (slideMatches) return slideMatches.length;
    const separators = body.split(/^[-=]{3,}$/m).filter(s => s.trim().length > 0);
    if (separators.length > 1) return separators.length;
    // Paragraph fallback — matches extractContentSlides behavior
    const paragraphs = body.split(/\n{2,}/).map(p => p.trim()).filter(p => p.length > 0);
    if (paragraphs.length > 1) return paragraphs.length;
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
      if (bp.keyTransitions.length > 0) {
        sections.push(`Key Transitions: ${bp.keyTransitions.join(', ')}`);
      }
      sections.push('');
      sections.push(bp.fullBody);
      sections.push('');
    }

    // Supporting examples
    sections.push('═══ SUPPORTING EXAMPLES — STYLE REFERENCE ═══');
    sections.push('Study these for copy quality, transitions, and formatting patterns.');
    sections.push('These do NOT get to change the blueprint story structure. They only help you say each slide more naturally.');
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

  private async runConversationLoop(phase: WritingPhase, block3b: WritingBlock, pipelineStep?: 'plan' | 'write' | 'edit' | 'session'): Promise<string> {
    // Track pipeline step for tool handlers (e.g., session-specific rules injection)
    this.pipelineStep = pipelineStep;

    // Session mode: extended budget for full plan+write+edit cycle
    // Pipeline phases: tighter cap. Open-ended (revisions, brainstorm): full budget.
    const maxIterations = pipelineStep === 'session' ? MAX_SESSION_ITERATIONS
      : pipelineStep ? MAX_PHASE_ITERATIONS : MAX_INNER_ITERATIONS;
    let lastAssistantText = '';
    let emptyResponseCount = 0;
    let consecutiveThinks = 0;
    let truncatedResponseCount = 0;

    for (let iteration = 0; iteration < maxIterations; iteration++) {
      console.log(`    🔄 Iteration ${iteration + 1}/${maxIterations} [${pipelineStep || phase}] (${this.messages.length} messages)`);

      // Build API messages
      const apiMessages = this.buildAPIMessages();

      // Available tools for this phase (pipeline step overrides if present)
      const tools = this.getToolDefinitions(phase, pipelineStep);

      // Call LLM (pass dynamic block separately — it changes each iteration)
      const response = await this.callWritingLLM(block3b, apiMessages, tools, pipelineStep);

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
          // Structured JSON log — Railway renders as ONE expandable entry
          console.log(JSON.stringify({ type: '🤖 RESPONSE', chars: text.length, content: text }));
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

      // Detect extended analysis — nudge after consecutive thinks
      // Plan/edit phases: think ONCE then act. Write phase: think ONCE to compose (don't nudge on first think).
      // Revisions: allow 1-2 thinks for complex feedback.
      // Write + edit phases need one think to compose/review. Plan phase: think once then create_writing_plan.
      // Session mode: allow 2 consecutive thinks (plan + self-edit both use think)
      const thinkNudgeThreshold = pipelineStep === 'session' ? 2
        : (pipelineStep === 'write' || pipelineStep === 'edit') ? 2
        : (pipelineStep ? 1 : 2);
      const allThinks = response.toolCalls.every(tc => tc.name === 'think');
      if (allThinks) {
        consecutiveThinks++;
        if (consecutiveThinks >= thinkNudgeThreshold) {
          console.log(`  ⚠️ Extended analysis (${consecutiveThinks} consecutive thinks, threshold ${thinkNudgeThreshold}) — directive nudge`);
          this.messages.push({
            id: crypto.randomUUID(),
            role: 'user',
            content: `[System] You have done ${consecutiveThinks} consecutive think calls without taking action. You MUST now call a tool to make progress — create_writing_plan, write_draft, update_outline, or add_hooks. Do NOT call think again.`,
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

        // Log full think content — essential for debugging Content Physics pipeline
        const thinkTopics: string[] = [];
        if (/slide|density|word.?count/i.test(thought)) thinkTopics.push('density');
        if (/beat|hook|structure/i.test(thought)) thinkTopics.push('structure');
        if (/voice|client|brand|tone/i.test(thought)) thinkTopics.push('voice');
        if (/swipe|example|blueprint|primary/i.test(thought)) thinkTopics.push('swipes');
        if (/rule|lesson|ban/i.test(thought)) thinkTopics.push('rules');
        if (/plan|outline|approach/i.test(thought)) thinkTopics.push('planning');
        if (/edit|check|fix|rewrite|correct/i.test(thought)) thinkTopics.push('editing');
        // Content Physics topics
        if (/speech act|reader delta|quark|transition.*→|inevitability|state change|causality|earned/i.test(thought)) thinkTopics.push('quarks');
        if (/experiential.?distance|zero.?distance|near.?distance|far.?distance/i.test(thought)) thinkTopics.push('distance');
        if (/technique|subject.?drop|all.?caps|compression|ellipsis|casual.?spelling/i.test(thought)) thinkTopics.push('techniques');
        if (/dominant.?frame|museum.?of|chronological|dialogue|tutorial|letter.?to|testimony|listicle/i.test(thought)) thinkTopics.push('frame');
        if (/symmetry.?break|phase.?transition|peak.?gravity|energy.?(conservation|resolution)/i.test(thought)) thinkTopics.push('physics-events');
        if (/rsv|reader.?state|open.?loop|superposition|entangle/i.test(thought)) thinkTopics.push('rsv');
        if (/antimatter|destroy|collapse|annihilate/i.test(thought)) thinkTopics.push('antimatter');
        if (/arc.?shape|win.?loss|reversal|tension.?peak/i.test(thought)) thinkTopics.push('arc');
        // Structured JSON log — Railway renders as ONE expandable entry
        console.log(JSON.stringify({ type: '💭 THINK', words: wordCount, topics: thinkTopics, content: thought }));

        // Track analysis depth for pre-write/outline gate
        if (wordCount > 200) {
          this.analysisDepth++;
          // Capture FULL analysis — no truncation. With fewer think calls (2 vs 4),
          // total think content is smaller than before even without truncation.
          this.writingContext.latestAnalysis = thought;
          // Also capture into specific buckets IF keywords match (additive, not exclusive)
          if (/swipe|pattern|density|hook|voice|structure|transition|punctuation/i.test(thought)) {
            this.writingContext.swipePatternAnalysis = thought;
          }
          if (/plan|approach|strategy|will write|going to|outline|structure/i.test(thought)) {
            this.writingContext.structuralPlan = thought;
          }
          this.writingContext.analysisDepth = this.analysisDepth;
        }

        // Capture self-review findings
        if (this.hasCompletedSelfReview && wordCount > 100) {
          this.writingContext.selfReviewFindings = thought;
        }

        // Guard against garbage/truncated thinks — never confirm ultra-short thoughts
        if (wordCount < 30) {
          return `Analysis received (${wordCount} words) — this is very short. If you're planning to take action, call the appropriate tool (update_outline, add_hooks, write_draft). If you need to reason, write a thorough analysis with specific observations from your loaded swipes (200+ words minimum for substantive analysis).`;
        }

        // Guide toward thorough analysis on first real think
        if (this.analysisDepth === 0 && wordCount < 200) {
          return `Analysis received (${wordCount} words). Before writing, ensure you've analyzed your loaded swipes through EVERY lens: density patterns, punctuation usage, hook mechanics, voice characteristics, transition patterns, CTA structure. Reference the Slide Density, Dinner Table Test, Voice Matching, Hook Craft, Causal Chaining, and CTA Craft modules in your context for what to look for.`;
        }

        // Quality signal check — ensure first think covers Content Physics dimensions
        if (this.analysisDepth === 1 && wordCount >= 200) {
          const hasDensity = /\d+\s*words/.test(thought) && /slide\s*\d/i.test(thought);
          const hasBeatMap = /\[(Hook|Context|Teach|Prove|Story|Reframe|Reveal|CTA)\]/i.test(thought);
          const hasHookAnalysis = /(case|person|structure).{0,40}(hook|slide.?1)/i.test(thought);
          const hasTensePattern = /tense.{0,30}(past|present|pattern)/i.test(thought);
          const hasQuarks = /(speech act|reader delta|quark|transition.*→|inevitability|state change|causality)/i.test(thought);
          const hasDistance = /experiential.?distance|zero.?distance|distance.{0,10}(zero|near|far)/i.test(thought);
          const hasTechniques = /technique|subject.?drop|all.?caps|compression/i.test(thought);
          const hasPhysicsMapping = /map|mapping|client.{0,20}(content|story|detail)|adapt/i.test(thought);
          const signals = [hasDensity, hasBeatMap, hasHookAnalysis, hasTensePattern, hasQuarks, hasDistance, hasTechniques, hasPhysicsMapping];
          const signalCount = signals.filter(Boolean).length;

          if (signalCount < 5) {
            const missing: string[] = [];
            if (!hasDensity) missing.push('DENSITY: Word counts per slide position');
            if (!hasBeatMap) missing.push('BEAT MAP: Slide functions [Hook/Context/Teach/etc.]');
            if (!hasHookAnalysis) missing.push('HOOK: Case, person, structure of slide 1');
            if (!hasTensePattern) missing.push('TENSE: Pattern and shift positions');
            if (!hasQuarks) missing.push('QUARKS: Speech acts + reader deltas per slide');
            if (!hasDistance) missing.push('DISTANCE: Experiential distance per slide (zero/near/far)');
            if (!hasTechniques) missing.push('TECHNIQUES: Craft moves per slide (subject-drop, ALL CAPS, etc.)');
            if (!hasPhysicsMapping) missing.push('MAPPING: Client content mapped to blueprint physics');
            console.log(`    ⚠️ Think quality: ${signalCount}/8 physics signals (missing: ${missing.join(', ')})`);
            return `Analysis received (${wordCount} words) but missing key Content Physics dimensions:\n${missing.map(m => `- ${m}`).join('\n')}\n\nContinue your analysis and cover the missing dimensions. These are critical for a physics-accurate plan.`;
          }
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
   • DENSITY: How many words per slide? Match the PRIMARY BLUEPRINT's density (count its actual words per slide)
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
   • DENSITY: How many sentences per slide? How many words per slide? Match the PRIMARY BLUEPRINT's density (count its actual words per slide). Reels are typically 10-25 words per slide.
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
        // Structured JSON log — Railway renders as ONE expandable entry
        console.log(JSON.stringify({ type: '📝 DRAFT', words: wordCount, slides: slideCount, format, content }));

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

        // Slide-level narrative quality checks
        const narrativeViolations = this.getBlockingNarrativeViolations(content);
        if (narrativeViolations.length > 0) {
          console.log(`    ⚠️ Narrative quality violations (${narrativeViolations.length}): ${narrativeViolations.map(v => `[${v.kind}] ${v.message.substring(0, 80)}`).join('; ')}`);
          result += `\n\n⚠️ HARD NARRATIVE QUALITY FAILURES:`;
          result += `\n${formatNarrativeViolations(narrativeViolations)}`;
        } else {
          console.log('    ✅ Blueprint fidelity + conversational slide checks passed');
        }

        // Content Physics validation (runs after structural/voice/narrative checks)
        let physicsBlockingCount = 0;
        if (this.structuredSlidePlan?.slides.some(s => s.physicsTarget)) {
          try {
            const physicsTargets = this.structuredSlidePlan!.slides
              .map(s => s.physicsTarget).filter(Boolean) as PhysicsTarget[];
            console.log(`    🔬 Running physics extraction on draft (${physicsTargets.length} targets)...`);
            const extraction = await extractDraftPhysics(content, physicsTargets);
            const physicsResult = validatePhysics(
              extraction,
              physicsTargets,
              (this.blueprintAnchor as any)?.fullQuarkProfile || null,
            );
            (this as any).lastPhysicsValidation = physicsResult;

            const blockingPhysics = [
              ...physicsResult.perSlideViolations.filter(v => v.severity === 'blocking'),
              ...physicsResult.conservationViolations.filter(v => v.severity === 'blocking'),
              ...physicsResult.eventViolations.filter(v => v.severity === 'blocking'),
            ];
            physicsBlockingCount = blockingPhysics.length;

            if (physicsResult.formattedViolations) {
              console.log(`    🔬 Physics: score=${physicsResult.overallScore}/100, blocking=${blockingPhysics.length}, advisory=${physicsResult.perSlideViolations.length + physicsResult.transitionViolations.length + physicsResult.conservationViolations.length + physicsResult.eventViolations.length - blockingPhysics.length}`);
              result += `\n\n${physicsResult.formattedViolations}`;
            } else {
              console.log(`    ✅ Physics validation passed (score: ${physicsResult.overallScore}/100)`);
            }
          } catch (err) {
            console.error(`    ⚠️ Physics validation error (non-blocking):`, err);
          }
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
        if (deterministicViolations.length > 0 || voiceViolations.length > 0 || narrativeViolations.length > 0 || physicsBlockingCount > 0) {
          this.refinementCount = (this.refinementCount || 0) + 1;
          if (this.refinementCount <= 2) {
            result += `\n\nAUTO-REFINEMENT PASS ${this.refinementCount}/2: Fix the violations above, then call write_draft again with the corrected content.`;
          }
        }

        // Self-review injection — fires once per draft, after all deterministic validation
        if (!this.hasCompletedSelfReview && deterministicViolations.length === 0 && voiceViolations.length === 0 && narrativeViolations.length === 0) {
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
• The structured slide contract — is each slide still doing the blueprint slide's job?
• Conversationality — does each sparse slide sound like speech instead of narration?

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
        const structuredPlan = buildStructuredSlidePlan(plan, this.blueprintAnchor?.fullBody || '', args.structuredPlan);

        // Map blueprint Content Physics to per-slide targets (deterministic, no LLM call)
        if (this.blueprintAnchor?.fullQuarkProfile) {
          const physicsTargets = mapBlueprintPhysicsToTargets(
            this.blueprintAnchor.fullQuarkProfile as any,
            structuredPlan.slides.length,
          );
          for (let i = 0; i < structuredPlan.slides.length && i < physicsTargets.length; i++) {
            structuredPlan.slides[i].physicsTarget = physicsTargets[i];
          }
          console.log(`    📋 Physics targets mapped: ${physicsTargets.length} slides from blueprint quark profile`);
        }

        this.structuredSlidePlan = structuredPlan;
        (this.writingContext as any).structuredSlidePlan = structuredPlan;

        // Log plan quality signals
        const hasSlideEntries = (plan.match(/Slide \d+/gi) || []).length;
        const hasWordCounts = (plan.match(/\d+ words/gi) || []).length;
        const hasBeatLabels = (plan.match(/\[(Hook|Context|Teach|Prove|Story|Reframe|Reveal|CTA)\]/gi) || []).length;
        const hasBannedSection = /banned|ban list/i.test(plan);
        const hasHookSpec = /hook.*(case|person|structure|caps)/i.test(plan);
        // Content Physics plan signals
        const hasDistanceTargets = (plan.match(/distance.{0,5}(zero|near|far)/gi) || []).length;
        const hasTechniqueEntries = (plan.match(/technique|subject.?drop|all.?caps|compression|ellipsis/gi) || []).length;
        const hasDominantFrame = /dominant.?frame/i.test(plan);
        const hasWriteInstructions = (plan.match(/WRITE:/gi) || []).length;
        const hasAntimatter = /antimatter/i.test(plan);
        const hasRSV = /rsv|reader.?state/i.test(plan);

        console.log(`    📋 Plan created: ${planWords} words`);
        console.log(`    📋 Structure: ${hasSlideEntries} slides, ${hasBeatLabels} beat labels, ${hasWordCounts} word targets, ${hasWriteInstructions} WRITE instructions`);
        console.log(`    📋 Physics: ${hasDistanceTargets} distance targets, ${hasTechniqueEntries} technique refs, frame=${hasDominantFrame ? 'yes' : 'NO'}, antimatter=${hasAntimatter ? 'yes' : 'NO'}, RSV=${hasRSV ? 'yes' : 'NO'}`);
        console.log(`    📋 Quality: banned=${hasBannedSection ? 'yes' : 'NO'}, hook_spec=${hasHookSpec ? 'yes' : 'NO'}`);
        if (hasSlideEntries < 3) console.log(`    ⚠️ Few slide entries (${hasSlideEntries}) — may lack per-slide detail`);
        if (hasWordCounts < 2) console.log(`    ⚠️ Few word count targets (${hasWordCounts}) — density may be vague`);
        if (hasDistanceTargets < 2) console.log(`    ⚠️ Few distance targets (${hasDistanceTargets}) — experiential distance may be unspecified`);
        if (hasWriteInstructions < 3) console.log(`    ⚠️ Few WRITE instructions (${hasWriteInstructions}) — craft direction may be vague`);
        // Structured JSON log — Railway renders as ONE expandable entry
        console.log(JSON.stringify({ type: '📋 PLAN', words: planWords, slideEntries: hasSlideEntries, wordCountTargets: hasWordCounts, beatLabels: hasBeatLabels, distanceTargets: hasDistanceTargets, techniqueRefs: hasTechniqueEntries, writeInstructions: hasWriteInstructions, content: plan }));

        // Store hook variants if provided (bundled with plan creation)
        if (args.hookVariants && Array.isArray(args.hookVariants) && args.hookVariants.length > 0) {
          this.hooks = (args.hookVariants as string[]);
          await updateAtom(this.contentUUID, {
            metadata: { hooks: this.hooks, inheritedHooks: this.hooks },
          });
          console.log(`    📋 Hooks bundled: ${this.hooks.length} variants`);
        }

        // Derive outline from structured slide plan
        if (structuredPlan.slides.length > 0) {
          this.outline = structuredPlan.slides.map((s: any, i: number) => ({
            id: `slide_${s.slideNumber || i + 1}`,
            title: `Slide ${s.slideNumber || i + 1}: ${s.beatFunction || 'Content'}`,
            beatLabel: s.beatFunction || undefined,
            sortOrder: i,
          }));
          await updateAtom(this.contentUUID, {
            metadata: { outline: this.outline },
          });
          console.log(`    📋 Outline derived: ${this.outline.length} slides from structured plan`);
        }

        // Session mode: inject critical rules reminder right before writing (recency bias)
        // In multi-phase mode, the user confirms first, so rules are injected later.
        const ruleReminder = this.buildCriticalRulesReminder();
        const confirmMessage = `Writing plan created (${planWords} words, ${structuredPlan.slides.length} slides, ${this.hooks.length} hook variants). The plan includes per-slide physics targets, density targets, WRITE instructions, and hook variants.`;

        if (this.pipelineStep === 'session') {
          return `${confirmMessage}\n\nBEFORE YOU WRITE — review these rules (violations trigger automatic rewrite):\n${ruleReminder}\n\nNow call write_draft with the complete content.`;
        }

        return `${confirmMessage} Ready for user confirmation before writing.`;
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
    pipelineStep?: 'plan' | 'write' | 'edit' | 'session',
  ): Promise<{ content: string | null; toolCalls: Array<{ id: string; name: string; arguments: Record<string, any> }>; finishReason: string | null; completionTokens: number }> {
    const useDirectAnthropic = !!config.anthropicApiKey;
    // Model routing: Sonnet 4.6 for all modes — full codex in context makes it cost-effective
    const model = config.models.strategist;  // Sonnet 4.6 — $3/$15 per MTok

    // Strip provider prefix for direct Anthropic (e.g., "anthropic/claude-opus-4-6" → "claude-opus-4-6")
    const modelId = useDirectAnthropic ? model.replace(/^anthropic\//, '') : model;

    const systemChars = this.blocks.reduce((sum, b) => sum + b.content.length, 0);
    const estimatedTokens = Math.round((systemChars + JSON.stringify(messages).length) / 4);
    console.log(`  ✍️ Writing engine → ${modelId} (${messages.length} messages, ${tools.length} tools, ~${estimatedTokens} est tokens)${useDirectAnthropic ? ' [direct]' : ' [openrouter]'}`);

    if (useDirectAnthropic) {
      return this.callAnthropicDirect(modelId, messages, tools, dynamicBlock, pipelineStep);
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
    pipelineStep?: 'plan' | 'write' | 'edit' | 'session',
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

    // Session mode needs much higher output budget: adaptive thinking + plan + draft + self-edit all in one call.
    // Multi-phase mode uses 16K per phase (plenty for a single think + write).
    const maxTokens = pipelineStep === 'session' ? 64000 : 16384;

    const body: any = {
      model,
      system,
      messages,
      max_tokens: maxTokens,
    };

    // Adaptive thinking for session mode — interleaved thinking between tool calls
    if (pipelineStep === 'session') {
      body.thinking = { type: 'adaptive' };
      body.temperature = 1; // Required for adaptive thinking
    } else {
      body.temperature = 0.3;
    }

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
            // Prompt caching is GA — no beta header needed
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

        // Parse response content blocks (including thinking blocks from adaptive thinking)
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
          } else if (block.type === 'thinking') {
            // Adaptive thinking block — log summary for debugging
            const thinkText = block.thinking || '';
            const thinkWords = thinkText.split(/\s+/).filter(Boolean).length;
            console.log(`  🧠 Adaptive thinking: ${thinkWords} words`);
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

    // Message-level cache breakpoint REMOVED — it was writing 87K tokens at $3.75/M every call
    // but never reading them back (the breakpoint position changes every call, so the prefix
    // never matches). Without it, messages are regular uncached input at $3/M instead of
    // cache write at $3.75/M. Saves ~25% on message tokens per call.
    // System blocks (Block 1+2+3A) still have their 3 cache breakpoints and work correctly.

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

  private getToolDefinitions(phase: WritingPhase, pipelineStep?: 'plan' | 'write' | 'edit' | 'session'): any[] {
    // Single session: NO think tool — adaptive thinking handles all reasoning.
    // Checkpoint logic (quality gates, rules injection) moves to create_writing_plan and write_draft handlers.
    if (pipelineStep === 'session') {
      return [
        { name: 'create_writing_plan', description: 'Create a comprehensive writing plan with hook variants. Must cover: physics mapping, voice & style, slide-by-slide blueprint with per-slide quarks/distance/techniques, rules checklist, density targets, hook variants. The plan drives the entire draft.', parameters: { type: 'object', properties: { plan: { type: 'string', description: 'The complete writing plan text' }, hookVariants: { type: 'array', items: { type: 'string' }, description: '3-4 hook variants matching the blueprint hook format and physics' }, structuredPlan: { type: 'object', description: 'Structured slide contract for deterministic validation', properties: { voicePattern: { type: 'string' }, tensePattern: { type: 'string' }, directAddressPrefix: { type: 'string' }, slides: { type: 'array', items: { type: 'object', properties: { slideNumber: { type: 'number' }, beatFunction: { type: 'string' }, prerequisites: { type: 'string' }, targetWords: { type: 'number' }, targetSentences: { type: 'number' }, format: { type: 'string' }, content: { type: 'string' }, transitionExpectation: { type: 'string' }, depthType: { type: 'string', enum: ['sparse_emotional', 'bridge', 'proof', 'detail_dense', 'payoff', 'unknown'] }, allowedAdaptation: { type: 'string' } }, required: ['slideNumber', 'beatFunction'] } } } } }, required: ['plan'] } },
        { name: 'write_draft', description: 'Write or revise the full draft. On first call: write following your plan. On subsequent calls: apply self-edit corrections.', parameters: { type: 'object', properties: { content: { type: 'string', description: 'Full draft text or JSON' }, format: { type: 'string', enum: ['plaintext', 'carousel_json', 'thread_json', 'script'] }, selfEvaluation: { type: 'object', properties: { confidenceScore: { type: 'number' }, voiceMatchScore: { type: 'number' }, weakAreas: { type: 'array', items: { type: 'string' } } } } }, required: ['content'] } },
        { name: 'read_draft', description: 'Read the current draft for self-edit review', parameters: { type: 'object', properties: {} } },
        { name: 'search_swipes', description: 'Search loaded swipe library', parameters: { type: 'object', properties: { query: { type: 'string' } }, required: ['query'] } },
        { name: 'read_swipe_body', description: 'Load full swipe text', parameters: { type: 'object', properties: { swipe_id: { type: 'string' } }, required: ['swipe_id'] } },
      ];
    }

    // Pipeline-specific tool sets
    if (pipelineStep === 'plan') {
      return [
        { name: 'think', description: 'Internal reasoning — use before complex decisions', parameters: { type: 'object', properties: { thought: { type: 'string' } }, required: ['thought'] } },
        { name: 'create_writing_plan', description: 'Create a comprehensive writing plan with hook variants. Must cover: physics mapping, voice & style, slide-by-slide blueprint with per-slide quarks/distance/techniques, rules checklist, density targets, hook variants. The plan drives the entire draft.', parameters: { type: 'object', properties: { plan: { type: 'string', description: 'The complete writing plan text' }, hookVariants: { type: 'array', items: { type: 'string' }, description: '3-4 hook variants matching the blueprint hook format and physics' }, structuredPlan: { type: 'object', description: 'Structured slide contract for deterministic validation', properties: { voicePattern: { type: 'string' }, tensePattern: { type: 'string' }, directAddressPrefix: { type: 'string' }, slides: { type: 'array', items: { type: 'object', properties: { slideNumber: { type: 'number' }, beatFunction: { type: 'string' }, prerequisites: { type: 'string' }, targetWords: { type: 'number' }, targetSentences: { type: 'number' }, format: { type: 'string' }, content: { type: 'string' }, transitionExpectation: { type: 'string' }, depthType: { type: 'string', enum: ['sparse_emotional', 'bridge', 'proof', 'detail_dense', 'payoff', 'unknown'] }, allowedAdaptation: { type: 'string' } }, required: ['slideNumber', 'beatFunction'] } } } } }, required: ['plan'] } },
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
        structuralRecipe: '', // deprecated
        voiceMarkers: (analysis.voiceMarkers as string[]) || [],
        fullQuarkProfile: isPrimary ? (atom.structured?.contentPhysics as any) : undefined,
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
      rules.push('• [FORMAT] Match the PRIMARY BLUEPRINT slide density, not a generic carousel average');
      rules.push('• [FORMAT] Sparse emotional slides stay sparse. Proof slides carry the heavy specifics.');
      rules.push('• [FORMAT] Support swipes teach natural phrasing and depth rhythm, not story structure');
    } else {
      rules.push('• [FORMAT] Match the PRIMARY BLUEPRINT slide density and pacing');
      rules.push('• [FORMAT] Keep slides conversational, one thought per slide, no narration drift');
    }

    // Write directive
    rules.push('• WRITE the draft using loaded context. Do NOT ask for more information.');
    rules.push('• BLUEPRINT slides decide what happens. Supporting swipes only help you say it naturally.');
    rules.push('• If a slide is meant to be emotional and sparse, do not overload it with facts.');

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
  type: 'banned_phrase' | 'negation_pattern' | 'cadence' | 'static_banned' | 'em_dash' | 'sentence_stacking' | 'formal_voice' | 'copywriter_punchline';
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

  // 7. Within-slide sentence stacking — slides with 3+ sentences but no causal connectors
  // BAD: "So inflation just hit 3.4%. The Fed's target is 2%. Essentials are running hotter."
  // GOOD: "So inflation just hit 3.4%... and that's just the headline. The stuff you actually buy? Way worse."
  const slideTexts = extractSlideTextsForValidation(draft);
  const connectorPattern = /^(so\b|because\b|which\b|that'?s why|that'?s when|and the\b|and here|and that|but\b|this is\b|here'?s\b|meaning\b|what that means|that means)/i;
  let stackingFlagged = false;
  for (const { slideNumber, text } of slideTexts) {
    if (stackingFlagged) break;
    // Split on sentence boundaries (. ! ? followed by space+capital or newline)
    const sentences = text.split(/[.!?]\s+/).filter(s => s.trim().length > 5);
    if (sentences.length < 3) continue;
    // Check if ANY sentence after the first starts with a causal connector
    const hasConnector = sentences.slice(1).some(s => connectorPattern.test(s.trim()));
    if (!hasConnector) {
      violations.push({
        type: 'sentence_stacking',
        message: `Slide ${slideNumber}: ${sentences.length} sentences stacked as separate facts with no causal flow. Read the blueprint's equivalent slide — study how IT chains sentences. At least one sentence after the first must start with a connector (So, Because, Which, And, But, That's why, Here's, This is, etc).`,
      });
      stackingFlagged = true; // One warning triggers auto-refinement
    }
  }

  // 8. Formal vocabulary detector — news-anchor/report voice phrases
  // These are phrases a news anchor or textbook would use, not a friend at dinner.
  // Don't suggest AI rewrites — tell the model to study how the blueprint/client says the same thing.
  const formalPhrases: Array<{ pattern: RegExp; label: string }> = [
    { pattern: /your purchasing power/i, label: '"your purchasing power"' },
    { pattern: /the official inflation/i, label: '"the official inflation number"' },
    { pattern: /quietly (shrinking|growing|eroding|declining)/i, label: '"quietly shrinking/growing"' },
    { pattern: /essentials like .{5,40} are running .{0,10}hotter/i, label: '"essentials are running hotter"' },
    { pattern: /purchasing power is/i, label: '"purchasing power is..."' },
    { pattern: /the (average|median) (american|household|worker)/i, label: 'formal demographic label' },
    { pattern: /structural(ly)? (un)?sustain/i, label: '"structurally unsustainable"' },
    { pattern: /disproportionately (affect|impact)/i, label: '"disproportionately affects"' },
  ];
  for (const { pattern, label } of formalPhrases) {
    if (pattern.test(textToCheck)) {
      violations.push({
        type: 'formal_voice',
        message: `News-anchor voice detected: ${label}. Nobody talks like this at dinner. Read the blueprint's slides — study how IT says similar things, then rewrite using that voice.`,
      });
    }
  }

  // 9. Copywriter punchline detector — mirror/invert sentence pairs that feel written, not spoken
  // BAD: "Your paycheck didn't move. That list did."
  // GOOD: "Your paycheck stayed the same. Everything else went up."
  for (const { slideNumber, text } of slideTexts) {
    const sentences = text.split(/[.!?]\s+/).filter(s => s.trim().length > 0);
    for (let j = 0; j < sentences.length - 1; j++) {
      const a = sentences[j].trim();
      const b = sentences[j + 1].trim();
      const aWords = a.split(/\s+/).length;
      const bWords = b.split(/\s+/).length;
      // Both short (<=7 words) and second inverts/mirrors the first
      if (aWords <= 7 && bWords <= 7) {
        // Check for subject inversion pattern: same structure, contrasting meaning
        const aSubject = a.split(/\s+/)[0]?.toLowerCase();
        const bSubject = b.split(/\s+/)[0]?.toLowerCase();
        // "Your X didn't Y. That Z did." or "X stayed the same. Y didn't."
        if (aSubject && bSubject && aSubject !== bSubject &&
            ((a.includes("didn't") && b.includes('did')) ||
             (a.includes('did') && b.includes("didn't")) ||
             (a.includes('same') || b.includes('same')) ||
             (a.includes('not') || b.includes('not')))) {
          violations.push({
            type: 'copywriter_punchline',
            message: `Slide ${slideNumber}: "${a}. ${b}." — this is a copywriter's mirror/invert punchline. Nobody talks like this. Study how the blueprint or client's top posts end similar slides, and say the same idea the way they would at dinner.`,
          });
          break;
        }
      }
    }
  }

  return violations;
}

/**
 * Extract slide texts from a draft (JSON carousel, thread, or plaintext) for per-slide validation.
 * Returns array of { slideNumber, text } where text is the raw content of each slide.
 */
function extractSlideTextsForValidation(draft: string): Array<{ slideNumber: number; text: string }> {
  try {
    const parsed = JSON.parse(draft);
    if (parsed.slides && Array.isArray(parsed.slides)) {
      return parsed.slides.map((s: any, i: number) => ({
        slideNumber: i + 1,
        text: String(typeof s === 'string' ? s : s.text || ''),
      }));
    }
    if (parsed.tweets && Array.isArray(parsed.tweets)) {
      return parsed.tweets.map((t: any, i: number) => ({
        slideNumber: i + 1,
        text: String(typeof t === 'string' ? t : t.text || t.content || ''),
      }));
    }
  } catch {}

  // Slide N markers
  if (/^Slide \d+/im.test(draft)) {
    const matches = [...draft.matchAll(/^Slide \d+[^\n]*\n([\s\S]*?)(?=^Slide \d+[^\n]*\n|$)/gim)];
    if (matches.length > 0) {
      return matches.map((m, i) => ({ slideNumber: i + 1, text: (m[1] || '').trim() }));
    }
  }

  // Paragraph split fallback
  const paragraphs = draft.split(/\n{2,}/).filter(p => p.trim().length > 10);
  return paragraphs.map((p, i) => ({ slideNumber: i + 1, text: p.trim() }));
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

interface SlideSnapshot {
  slideNumber: number;
  text: string;
  lowerText: string;
  words: number;
  sentences: number;
  specificityCount: number;
  addressPrefix: string | null;
  startsWithYear: boolean;
  hasListSyntax: boolean;
  hasFirstPerson: boolean;
  commaCount: number;
  clauseJoinerCount: number;
}

function formatNarrativeViolations(violations: NarrativeValidationViolation[]): string {
  return violations.map(v => {
    const slides = v.slideNumbers.length > 0 ? `Slide${v.slideNumbers.length > 1 ? 's' : ''} ${v.slideNumbers.join(', ')}` : 'Draft';
    const evidence = v.evidence ? `\n    Evidence: ${v.evidence}` : '';
    return `  - [${v.kind}] ${slides}: ${v.message}${evidence}`;
  }).join('\n');
}

function buildStructuredSlidePlan(
  planText: string,
  blueprintBody: string,
  structuredPlanArg?: any,
): StructuredSlidePlan {
  const blueprintSlides = extractContentSlides(blueprintBody);
  const blueprintSlideCount = blueprintSlides.length || Math.max((planText.match(/^Slide \d+:/gim) || []).length, 0);

  const voicePattern = extractSection(planText, 'VOICE PATTERN', 'TENSE PATTERN');
  const tensePattern = extractSection(planText, 'TENSE PATTERN', 'VOICE RULES');
  const fallbackDirectAddress = inferRepeatedDirectAddressPrefix(blueprintSlides);

  let slides: StructuredSlideContract[] = [];
  if (structuredPlanArg?.slides && Array.isArray(structuredPlanArg.slides)) {
    slides = structuredPlanArg.slides
      .map((slide: any) => normalizeSlideContract(slide))
      .filter((slide: StructuredSlideContract | null): slide is StructuredSlideContract => !!slide);
  }

  if (slides.length === 0) {
    const blocks = planText.split(/(?=^Slide \d+:)/gm).filter(block => /^Slide \d+:/m.test(block));
    slides = blocks.map(block => {
      const header = block.match(/^Slide (\d+):\s*\[(.*?)\]/m);
      const targetWords = parsePositiveInt(captureLabeledValue(block, 'Words'));
      const targetSentences = parsePositiveInt(captureLabeledValue(block, 'Sentences'));
      const format = captureLabeledValue(block, 'Format');
      const content = captureLabeledValue(block, 'Content');
      const transitionExpectation = captureLabeledValue(block, 'Transition to next');
      const depthTypeRaw = captureLabeledValue(block, 'Depth Type');
      const prerequisites = captureLabeledValue(block, 'Prerequisites') || 'none';
      const allowedAdaptation = captureLabeledValue(block, 'Allowed Adaptation');
      return normalizeSlideContract({
        slideNumber: parsePositiveInt(header?.[1]) || 0,
        beatFunction: header?.[2] || 'Unknown',
        prerequisites,
        targetWords,
        targetSentences,
        format,
        content,
        transitionExpectation,
        depthType: depthTypeRaw || inferDepthType(`${header?.[2] || ''} ${content} ${transitionExpectation}`),
        allowedAdaptation,
      })!;
    }).filter(Boolean);
  }

  const directAddressPrefix = sanitizeAddressPrefix(
    structuredPlanArg?.directAddressPrefix
      || extractDirectAddressPrefixFromVoicePattern(voicePattern)
      || fallbackDirectAddress,
  );

  slides = slides.map((slide, index) => {
    const blueprintSlide = blueprintSlides[index];
    return {
      ...slide,
      requiredAddressPrefix: blueprintSlide?.addressPrefix || null,
      requiresYearMarker: blueprintSlide?.startsWithYear || false,
    };
  });

  const payoffIndex = slides.findIndex(slide => slide.depthType === 'payoff');
  return {
    blueprintSlideCount: blueprintSlideCount || slides.length,
    voicePattern,
    tensePattern,
    directAddressPrefix,
    endingZoneStartsAt: payoffIndex >= 0 ? payoffIndex + 1 : Math.max((blueprintSlideCount || slides.length) - 3, 1),
    slides,
  };
}

function normalizeSlideContract(raw: any): StructuredSlideContract | null {
  const slideNumber = parsePositiveInt(raw?.slideNumber);
  const beatFunction = String(raw?.beatFunction || raw?.beat || '').trim();
  if (!slideNumber || !beatFunction) return null;

  const targetWords = parsePositiveInt(raw?.targetWords);
  const targetSentences = parsePositiveInt(raw?.targetSentences);
  const depthType = normalizeDepthType(raw?.depthType || inferDepthType(`${beatFunction} ${raw?.content || ''}`));

  return {
    slideNumber,
    beatFunction,
    prerequisites: String(raw?.prerequisites || 'none').trim(),
    targetWords: targetWords || null,
    targetWordBand: buildToleranceBand(targetWords || null),
    targetSentences: targetSentences || null,
    targetSentenceBand: buildToleranceBand(targetSentences || null, 0),
    format: String(raw?.format || '').trim(),
    content: String(raw?.content || '').trim(),
    transitionExpectation: String(raw?.transitionExpectation || '').trim(),
    depthType,
    allowedAdaptation: raw?.allowedAdaptation ? String(raw.allowedAdaptation).trim() : undefined,
  };
}

function validateBlueprintFidelity(
  draftSlides: SlideSnapshot[],
  blueprintSlides: SlideSnapshot[],
  structuredPlan: StructuredSlidePlan,
): NarrativeValidationViolation[] {
  const violations: NarrativeValidationViolation[] = [];
  // Slide count should match the blueprint closely
  if (structuredPlan.blueprintSlideCount > 0 && draftSlides.length !== structuredPlan.blueprintSlideCount) {
    violations.push({
      kind: 'blueprint_fidelity',
      slideNumbers: [],
      message: `Slide count ${draftSlides.length} does not match blueprint ${structuredPlan.blueprintSlideCount}`,
    });
  }

  const priorText: string[] = [];
  const maxSlides = Math.min(draftSlides.length, structuredPlan.slides.length);
  for (let i = 0; i < maxSlides; i++) {
    const draft = draftSlides[i];
    const contract = structuredPlan.slides[i];
    const blueprint = blueprintSlides[i];

    if (contract.requiredAddressPrefix && draft.addressPrefix !== contract.requiredAddressPrefix) {
      violations.push({
        kind: 'blueprint_fidelity',
        slideNumbers: [draft.slideNumber],
        message: `Breaks the blueprint's direct-address pattern. Expected "${contract.requiredAddressPrefix}" opening.`,
        evidence: trimEvidence(draft.text),
      });
    }

    if (contract.requiresYearMarker && !draft.startsWithYear) {
      violations.push({
        kind: 'blueprint_fidelity',
        slideNumbers: [draft.slideNumber],
        message: 'Missing the blueprint year-marker opening for this slide position.',
        evidence: trimEvidence(draft.text),
      });
    }

    if (i < 3 && isSparseLike(contract.depthType)) {
      const openingMax = contract.targetWordBand?.[1] || Math.max((blueprint?.words || 14) + 4, 16);
      if (draft.words > Math.max(22, Math.round(openingMax * 1.35)) || draft.specificityCount > 2) {
        violations.push({
          kind: 'blueprint_fidelity',
          slideNumbers: [draft.slideNumber],
          message: 'Opening slide is overfilled versus the blueprint. It feels like setup/explanation instead of the intended sparse beat.',
          evidence: trimEvidence(draft.text),
        });
      }
    }

    if ((contract.depthType === 'proof' || contract.depthType === 'detail_dense') && draft.specificityCount === 0 && draft.words < 10) {
      violations.push({
        kind: 'blueprint_fidelity',
        slideNumbers: [draft.slideNumber],
        message: `This slide is supposed to carry proof/detail, but it is too vague to do the blueprint slide's job.`,
        evidence: trimEvidence(draft.text),
      });
    }

    if (introducesOrphanRole(draft.text, priorText.join(' ')) && !looksLikeBridge(contract)) {
      violations.push({
        kind: 'blueprint_fidelity',
        slideNumbers: [draft.slideNumber],
        message: 'Introduces a new role/event without enough setup. This reads like a random inserted slide, not a clean blueprint progression.',
        evidence: trimEvidence(draft.text),
      });
    }

    if (draft.slideNumber >= structuredPlan.endingZoneStartsAt && containsEndingConflict(draft.lowerText)) {
      violations.push({
        kind: 'blueprint_fidelity',
        slideNumbers: [draft.slideNumber],
        message: 'The ending zone reintroduces conflict instead of paying off cleanly like the blueprint.',
        evidence: trimEvidence(draft.text),
      });
    }

    priorText.push(draft.text);
  }

  return dedupeNarrativeViolations(violations);
}

function validateConversationality(
  draftSlides: SlideSnapshot[],
  structuredPlan: StructuredSlidePlan,
): NarrativeValidationViolation[] {
  const violations: NarrativeValidationViolation[] = [];
  const maxSlides = Math.min(draftSlides.length, structuredPlan.slides.length);

  for (let i = 0; i < maxSlides; i++) {
    const draft = draftSlides[i];
    const contract = structuredPlan.slides[i];
    const isSparse = isSparseLike(contract.depthType);

    if (structuredPlan.directAddressPrefix && (contract.requiredAddressPrefix || isSparse) && draft.addressPrefix !== (contract.requiredAddressPrefix || structuredPlan.directAddressPrefix)) {
      violations.push({
        kind: 'conversationality',
        slideNumbers: [draft.slideNumber],
        message: 'Slides drifted out of the conversational direct-address voice and into narration.',
        evidence: trimEvidence(draft.text),
      });
    }

    if (isSparse) {
      const maxWords = contract.targetWordBand?.[1] || 18;
      if (draft.words > Math.max(24, Math.round(maxWords * 1.35))) {
        violations.push({
          kind: 'conversationality',
          slideNumbers: [draft.slideNumber],
          message: 'Sparse slide is too long. It is explaining instead of speaking naturally in one thought.',
          evidence: trimEvidence(draft.text),
        });
      }

      if (draft.sentences > 2 || draft.clauseJoinerCount >= 3 || draft.commaCount >= 3) {
        violations.push({
          kind: 'conversationality',
          slideNumbers: [draft.slideNumber],
          message: 'Slide carries too many thoughts to feel conversational.',
          evidence: trimEvidence(draft.text),
        });
      }

      if (draft.specificityCount > 2) {
        violations.push({
          kind: 'conversationality',
          slideNumbers: [draft.slideNumber],
          message: 'Sparse emotional slide is jammed with too many facts/details.',
          evidence: trimEvidence(draft.text),
        });
      }

      if (draft.hasListSyntax) {
        violations.push({
          kind: 'conversationality',
          slideNumbers: [draft.slideNumber],
          message: 'Slide formatting reads like copy or notes, not like someone actually talking.',
          evidence: trimEvidence(draft.text),
        });
      }
    }

    if ((contract.requiredAddressPrefix || structuredPlan.directAddressPrefix) && !draft.hasFirstPerson && draft.addressPrefix == null) {
      violations.push({
        kind: 'conversationality',
        slideNumbers: [draft.slideNumber],
        message: 'This slide loses the first-person spoken voice and reads like detached narration.',
        evidence: trimEvidence(draft.text),
      });
    }

    // Within-slide chaining check for ALL slides with 3+ sentences (not just sparse)
    if (draft.sentences >= 3) {
      const hasConnector = checkWithinSlideConnectors(draft.text);
      if (!hasConnector) {
        violations.push({
          kind: 'conversationality',
          slideNumbers: [draft.slideNumber],
          message: 'Sentences are stacked as separate facts with no causal flow between them. Chain them: "So...", "Which means...", "And that\'s why...", "Here\'s the thing..."',
          evidence: trimEvidence(draft.text),
        });
      }
    }

    // Between-slide bridge check for consecutive non-hook, non-CTA slides
    if (i > 0 && i < maxSlides - 1) {
      // Not first slide (hook) and not last slide (CTA)
      const prevDraft = draftSlides[i - 1];
      const hasBridge = checkBetweenSlideBridge(prevDraft.text, draft.text);
      if (!hasBridge) {
        violations.push({
          kind: 'conversationality',
          slideNumbers: [prevDraft.slideNumber, draft.slideNumber],
          message: `Slides ${prevDraft.slideNumber}→${draft.slideNumber}: No bridge between slides. End previous slide with a forward pull ("here's how:", "this is why:") or start this slide with a backward link ("So", "And", "But", "Because", "That's why").`,
          evidence: trimEvidence(prevDraft.text).slice(-60) + ' → ' + trimEvidence(draft.text).slice(0, 60),
        });
      }
    }
  }

  return dedupeNarrativeViolations(violations);
}

/**
 * Check if a slide with 3+ sentences has at least one causal connector after the first sentence.
 * Returns true if flow exists, false if sentences are stacked facts.
 */
function checkWithinSlideConnectors(text: string): boolean {
  const connectorStarts = /^(so\b|because\b|which\b|that'?s why|that'?s when|and the\b|and here|and that\b|but\b|this is\b|here'?s\b|meaning\b|what that means|that means|it'?s\b|when\b)/i;
  // Split on sentence endings followed by space
  const sentences = text.split(/[.!?]\s+/).filter(s => s.trim().length > 5);
  if (sentences.length < 3) return true;
  return sentences.slice(1).some(s => connectorStarts.test(s.trim()));
}

/**
 * Check if there's a bridge between two consecutive slides.
 * Returns true if slide N ends with a forward pull OR slide N+1 starts with a backward link.
 */
function checkBetweenSlideBridge(slideText: string, nextSlideText: string): boolean {
  // Forward pulls: phrases at the END of a slide that pull the reader forward
  const forwardPulls = /(here'?s (how|what|why|where|the)|this is (why|where|how|what)|that'?s (when|why|where)|which means|and here'?s|so:|here'?s why|here'?s what)\s*[:.]?\s*$/im;
  // Backward links: words at the START of a slide that link back to the previous
  const backwardLinks = /^\s*(so\b|and\b|but\b|because\b|which\b|that'?s|this is|when\b|it'?s\b|here'?s\b|now\b|then\b|meanwhile)/im;
  return forwardPulls.test(slideText.trim()) || backwardLinks.test(nextSlideText.trim());
}

function extractContentSlides(content: string): SlideSnapshot[] {
  if (!content) return [];

  try {
    const parsed = JSON.parse(content);
    if (parsed.slides && Array.isArray(parsed.slides)) {
      return parsed.slides
        .map((slide: any, index: number) => createSlideSnapshot(index + 1, String(typeof slide === 'string' ? slide : slide.text || '')))
        .filter(Boolean);
    }
    if (parsed.tweets && Array.isArray(parsed.tweets)) {
      return parsed.tweets
        .map((tweet: any, index: number) => createSlideSnapshot(index + 1, String(typeof tweet === 'string' ? tweet : tweet.text || tweet.content || '')))
        .filter(Boolean);
    }
  } catch {
    // Not JSON
  }

  const separatorParts = content
    .split(/^\s*[-=]{3,}\s*$/gm)
    .map(part => part.trim())
    .filter(part => part.length > 0);
  if (separatorParts.length > 1) {
    return separatorParts.map((part, index) => createSlideSnapshot(index + 1, part)).filter(Boolean);
  }

  if (/^Slide \d+/im.test(content)) {
    const matches = [...content.matchAll(/^Slide \d+[^\n]*\n([\s\S]*?)(?=^Slide \d+[^\n]*\n|$)/gim)];
    if (matches.length > 0) {
      return matches.map((match, index) => createSlideSnapshot(index + 1, match[1] || '')).filter(Boolean);
    }
  }

  const paragraphs = content
    .split(/\n{2,}/)
    .map(part => part.trim())
    .filter(part => part.length > 0 && !/^[-=]{3,}$/.test(part));
  return paragraphs.map((part, index) => createSlideSnapshot(index + 1, part)).filter(Boolean);
}

function createSlideSnapshot(slideNumber: number, rawText: string): SlideSnapshot {
  const text = stripNonContentLines(rawText);
  const lowerText = text.toLowerCase();
  return {
    slideNumber,
    text,
    lowerText,
    words: countWords(text),
    sentences: countSentences(text),
    specificityCount: (text.match(/\$?\d[\d,]*(?:\.\d+)?%?/g) || []).length,
    addressPrefix: extractAddressPrefix(text),
    startsWithYear: /^\s*(19|20)\d{2}:\s*/.test(text),
    hasListSyntax: /(^|\n)\s*(?:[-*•]|\d+\.)\s+/m.test(text) || /[:;]/.test(text),
    hasFirstPerson: /\b(I|I'm|I’d|I'd|I've|I’ll|I'll|my|me|we|we're|we'd|we've|our|us)\b/i.test(text),
    commaCount: (text.match(/,/g) || []).length,
    clauseJoinerCount: (text.match(/\b(and|but|so|then|because)\b/gi) || []).length,
  };
}

function stripNonContentLines(text: string): string {
  return text
    .split('\n')
    .map(line => line.trim())
    .filter(line => line.length > 0 && !/^\[VISUAL:.*\]$/i.test(line))
    .join(' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function countWords(text: string): number {
  return text.split(/\s+/).filter(Boolean).length;
}

function countSentences(text: string): number {
  const matches = text.match(/[^.!?]+[.!?]+/g) || [];
  return Math.max(matches.length, text.trim().length > 0 ? 1 : 0);
}

function parsePositiveInt(value: any): number | null {
  if (typeof value === 'number' && Number.isFinite(value) && value > 0) return Math.round(value);
  if (typeof value !== 'string') return null;
  const match = value.match(/\d+/);
  return match ? parseInt(match[0], 10) : null;
}

function captureLabeledValue(block: string, label: string): string {
  const escaped = label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = block.match(new RegExp(`${escaped}:\\s*(.+)$`, 'im'));
  return match?.[1]?.trim() || '';
}

function extractSection(planText: string, startLabel: string, endLabel: string): string {
  const escapedStart = startLabel.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const escapedEnd = endLabel.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = planText.match(new RegExp(`${escapedStart}\\s*\\n([\\s\\S]*?)\\n\\s*${escapedEnd}`, 'i'));
  return match?.[1]?.trim() || '';
}

function buildToleranceBand(target: number | null, floor = 1): [number, number] | null {
  if (!target || target <= 0) return null;
  const delta = Math.max(1, Math.round(target * 0.1));
  return [Math.max(floor, target - delta), Math.max(floor, target + delta)];
}

function inferDepthType(text: string): SlideDepthType {
  const lower = text.toLowerCase();
  if (/(cta|thank|gratitude|retire|grandfather|daughter|wife|married|happy again|thank you|visit|gift|payoff)/i.test(lower)) return 'payoff';
  if (/(bridge|transition|that's when|then|after that|so i|so we|context|moved|started over)/i.test(lower)) return 'bridge';
  if (/(proof|prove|numbers|deal|revenue|month|sales|students|get their first deal|score|percent|losses|details)/i.test(lower)) return 'proof';
  if (/(teach|framework|steps|how to|why this worked|lesson|explain)/i.test(lower)) return 'detail_dense';
  if (/(hook|story|reveal|emotion|lost|sorry|feel|what's all of this for|couldn't go back)/i.test(lower)) return 'sparse_emotional';
  return 'unknown';
}

function normalizeDepthType(value: any): SlideDepthType {
  const lower = String(value || '').trim().toLowerCase();
  if (lower === 'sparse_emotional' || lower === 'bridge' || lower === 'proof' || lower === 'detail_dense' || lower === 'payoff') {
    return lower;
  }
  return inferDepthType(lower);
}

function inferRepeatedDirectAddressPrefix(slides: SlideSnapshot[]): string | null {
  const counts = new Map<string, number>();
  for (const slide of slides) {
    if (!slide.addressPrefix) continue;
    counts.set(slide.addressPrefix, (counts.get(slide.addressPrefix) || 0) + 1);
  }
  const winner = [...counts.entries()].sort((a, b) => b[1] - a[1])[0];
  return winner && winner[1] >= 3 ? winner[0] : null;
}

function extractDirectAddressPrefixFromVoicePattern(voicePattern: string): string | null {
  const quoted = voicePattern.match(/['"]([A-Z][^'"]{0,20},)['"]/);
  if (quoted?.[1]) return sanitizeAddressPrefix(quoted[1]);
  const plain = voicePattern.match(/\b(Mom|Dad|Coach|Ben|Mama|Papa),\s*I\b/i);
  if (plain?.[0]) return sanitizeAddressPrefix(plain[1] + ',');
  return null;
}

function sanitizeAddressPrefix(value: string | null | undefined): string | null {
  if (!value) return null;
  const trimmed = value.trim();
  return trimmed.endsWith(',') ? trimmed : `${trimmed},`;
}

function extractAddressPrefix(text: string): string | null {
  const match = text.match(/^\s*([A-Z][a-z]+,)/);
  return match?.[1] || null;
}

function isSparseLike(depthType: SlideDepthType): boolean {
  return depthType === 'sparse_emotional' || depthType === 'bridge' || depthType === 'payoff' || depthType === 'unknown';
}

function looksLikeBridge(contract: StructuredSlideContract): boolean {
  const combined = `${contract.beatFunction} ${contract.transitionExpectation} ${contract.prerequisites}`.toLowerCase();
  return contract.depthType === 'bridge' || /(bridge|context|setup|transition|chronological|that's when|then|after)/.test(combined);
}

function introducesOrphanRole(text: string, priorText: string): boolean {
  const roleMatch = text.match(/\b(?:the|my|our)\s+(business partner|partner|mentor|wife|husband|girlfriend|boyfriend|coach|investor|boss|chef|team|client|friend)\b/i);
  if (!roleMatch) return false;
  return !new RegExp(`\\b${roleMatch[1]}\\b`, 'i').test(priorText);
}

function containsEndingConflict(lowerText: string): boolean {
  return /\b(almost|loss|losses|debt|owe|problem|broke|failure|failed|close the doors|shut down|quit|sorry|couldn't)\b/i.test(lowerText);
}

function trimEvidence(text: string): string {
  return text.length > 120 ? `${text.substring(0, 117)}...` : text;
}

function dedupeNarrativeViolations(violations: NarrativeValidationViolation[]): NarrativeValidationViolation[] {
  const seen = new Set<string>();
  return violations.filter(v => {
    const key = `${v.kind}:${v.slideNumbers.join(',')}:${v.message}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}
