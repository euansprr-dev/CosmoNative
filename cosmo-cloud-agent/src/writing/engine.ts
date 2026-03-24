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
import { assembleBlock1, assembleBlock2, assembleBlock3Stable, assembleBlock3Dynamic, WritingBlock } from './contextAssembler';
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

  // Deep analysis tracking — gates outline/draft behind substantive thinking
  private analysisDepth = 0;
  private hasWrittenOutlineBefore = false;
  private hasWrittenDraftBefore = false;
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
      // If analysis was done in a prior phase, don't re-gate
      if (this.analysisDepth > 0) {
        this.hasWrittenOutlineBefore = true;
      }
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

    // Reset self-review flag for new draft requests
    if (phase === 'draft') {
      this.hasCompletedSelfReview = false;
    }

    // Build dynamic block (includes prior analysis context)
    const block3b = assembleBlock3Dynamic(
      this.contentAtom,
      this.outline.length > 0 ? this.outline : null,
      this.hooks.length > 0 ? this.hooks : null,
      this.conversationSummary,
      this.writingContext,
    );

    // Add user message
    this.messages.push({
      id: crypto.randomUUID(),
      role: 'user',
      content: instruction,
      timestamp: new Date().toISOString(),
    });

    // Run conversation loop
    const result = await this.runConversationLoop(phase, block3b);

    // Persist conversation to atom
    await this.persistConversation();

    return result;
  }

  // ============================================================
  // Conversation Loop
  // ============================================================

  private async runConversationLoop(phase: WritingPhase, block3b: WritingBlock): Promise<string> {
    let lastAssistantText = '';
    let emptyResponseCount = 0;
    let consecutiveThinks = 0;

    for (let iteration = 0; iteration < MAX_INNER_ITERATIONS; iteration++) {
      // Build system prompt from blocks
      const systemPrompt = [
        ...this.blocks.map(b => b.content),
        block3b.content,
      ].join('\n\n');

      // Build API messages
      const apiMessages = this.buildAPIMessages();

      // Available tools for this phase
      const tools = this.getToolDefinitions(phase);

      // Call LLM
      const response = await this.callWritingLLM(systemPrompt, apiMessages, tools);

      // No tool calls — classify response (ported from Swift classifyLoopResponse)
      if (!response.toolCalls || response.toolCalls.length === 0) {
        const text = (response.content || '').trim();

        if (text.length > 0) {
          // Has content — accept
          if (response.finishReason === 'length') {
            // Truncated by max_tokens — accept with warning
            lastAssistantText = text + '\n\n[System] The model hit its output limit before finishing. Ask me to continue from where it left off.';
            console.log(`  ⚠️ Accepted truncated response (finish_reason=length)`);
          } else {
            lastAssistantText = text;
          }
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

      // Detect extended analysis — gentle nudge after 8 consecutive thinks (was 3 — too aggressive)
      const allThinks = response.toolCalls.every(tc => tc.name === 'think');
      if (allThinks) {
        consecutiveThinks++;
        if (consecutiveThinks >= 8) {
          console.log(`  ⚠️ Extended analysis (${consecutiveThinks} consecutive thinks) — gentle nudge`);
          this.messages.push({
            id: crypto.randomUUID(),
            role: 'user',
            content: '[System] You\'ve done extensive analysis. When you\'re ready, apply your findings — call update_outline, add_hooks, or write_draft to take action.',
            timestamp: new Date().toISOString(),
          });
          consecutiveThinks = 0;
        }
      } else {
        consecutiveThinks = 0;
      }

      // Log warning for incomplete responses (finish_reason missing)
      if (!response.finishReason) {
        console.log(`  ⚠️ Incomplete response (finish_reason=--) on iteration ${iteration + 1} — model may be producing truncated output`);
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

        // Track analysis depth for pre-write/outline gate
        if (wordCount > 200) {
          this.analysisDepth++;
          // Capture analysis into writingContext for cross-phase persistence
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

        // Guide toward thorough analysis
        if (this.analysisDepth === 0 && wordCount < 100) {
          return `Analysis received (${wordCount} words). Before writing, ensure you've analyzed your loaded swipes through EVERY lens: density patterns, punctuation usage, hook mechanics, voice characteristics, transition patterns, CTA structure. Reference the Slide Density, Dinner Table Test, Voice Matching, Hook Craft, Causal Chaining, and CTA Craft modules in your context for what to look for.`;
        }

        return `Analysis received (${wordCount} words). ${this.analysisDepth >= 2 ? 'Deep analysis complete. You may proceed when ready.' : 'Continue analyzing — check remaining skill module dimensions.'}`;
      }

      case 'update_outline': {
        // Pre-outline analysis gate — require deep thinking before first outline
        if (this.analysisDepth < 1 && !this.hasWrittenOutlineBefore) {
          return `[BLOCKED] You haven't analyzed your context deeply enough yet. Before creating an outline:

1. Call think to study ALL loaded swipes — read their full bodies in your context. For EACH dimension below, note what patterns you observe:
   • HOOKS: What hook mechanisms do the top-scoring swipes use? How are they structured? (Hook Craft module)
   • STRUCTURE: What beat patterns do the swipes follow? How many sections? (Beat Patterns in methodology)
   • DENSITY: How many sentences per slide? Words per sentence? (Slide Density module)
   • VOICE: What's the tone, formality, sentence length patterns? (Voice Matching module)
   • TRANSITIONS: How do slides connect? (Causal Chaining module)
   • CTA: What CTA patterns work? (CTA Craft module)
   • DINNER TABLE: Would these sound natural spoken aloud? (Dinner Table Test)

2. Call think to study the CLIENT PROFILE — their voice targets, brand story, beliefs, audience, positioning, failure fingerprint, top performing content patterns

3. Call think to plan your outline approach — how will you combine the swipe structural DNA with the client's voice and topic?

Only after thorough analysis can you call update_outline.`;
        }
        this.hasWrittenOutlineBefore = true;

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
        const hookVariants = args.hooks as any[];
        if (!hookVariants) return 'Error: hooks required';
        this.hooks = hookVariants.map((h: any) => typeof h === 'string' ? h : h.text || '');
        await updateAtom(this.contentUUID, {
          metadata: { hooks: this.hooks, inheritedHooks: this.hooks },
        });
        return `Added ${this.hooks.length} hook variants.`;
      }

      case 'write_draft': {
        // Pre-write analysis gate — require deep thinking before first draft
        if (this.analysisDepth < 1 && !this.hasWrittenDraftBefore) {
          return `[BLOCKED] You haven't analyzed your context deeply enough yet. Before writing:

1. Call think to study ALL loaded swipes — read their full bodies in your context. For EACH dimension below, note what patterns you observe across the swipes:
   • DENSITY: How many sentences per slide? How many words per sentence? (Slide Density module)
   • VOICE: What's the tone? Contractions? Sentence fragments vs full sentences? Formality level? (Voice Matching module)
   • HOOKS: What hook mechanisms do the top-scoring swipes use? How long are hooks? (Hook Craft module)
   • TRANSITIONS: How do slides connect? Implied "so/but/that's when"? (Causal Chaining module)
   • PUNCTUATION: Do they use em-dashes? Ellipses? Exclamation marks? What's ABSENT? (Voice DNA)
   • CTA: What CTA pattern do they use? Keyword + action? (CTA Craft module)
   • DINNER TABLE: Would these swipes sound natural spoken aloud at dinner? What makes them conversational? (Dinner Table Test)

2. Call think again to plan your writing approach — how will you apply these patterns to THIS content for THIS client?

Only after thorough analysis can you call write_draft.`;
        }
        this.hasWrittenDraftBefore = true;

        const content = args.content as string;
        if (!content) return 'Error: content required';
        const format = args.format as string || 'plaintext';

        // Persist draft to atom body
        await updateAtom(this.contentUUID, { body: content });

        // Validate format
        const validation = validateDraft(content, this.targetFormat);
        const wordCount = content.split(/\s+/).filter(Boolean).length;

        let result = `Draft written (${wordCount} words, format: ${format})`;
        if (!validation.isValid) {
          result += `\nValidation issues:\n${validation.violations.map(v => `  - ${v}`).join('\n')}`;
        }

        // Deterministic validation (ported from Swift DeterministicWritingValidators)
        const deterministicViolations = runDeterministicValidators(content, this.lessons);
        if (deterministicViolations.length > 0) {
          result += `\n\n⚠️ DETERMINISTIC RULE VIOLATIONS (fix before presenting):`;
          for (const v of deterministicViolations) {
            result += `\n  - [${v.type}] ${v.message}`;
          }
        }

        // Voice compliance check
        const voiceViolations = checkVoiceCompliance(content, this.clientAtom);
        if (voiceViolations.length > 0) {
          result += `\n\n⚠️ VOICE COMPLIANCE:`;
          for (const v of voiceViolations) {
            result += `\n  - ${v}`;
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
  // LLM Call
  // ============================================================

  private async callWritingLLM(
    systemPrompt: string,
    messages: any[],
    tools: any[],
  ): Promise<{ content: string | null; toolCalls: Array<{ id: string; name: string; arguments: Record<string, any> }>; finishReason: string | null }> {
    const apiKey = config.openRouterApiKey;
    const model = config.models.writer;

    // Estimate context size for logging
    const isAnthropicModel = model.includes('anthropic') || model.includes('claude');
    const systemContent = isAnthropicModel
      ? this.blocks.map(block => ({
          type: 'text' as const,
          text: block.content,
          ...(block.cacheControl ? { cache_control: { type: 'ephemeral', ttl: '1h' } } : {}),
        }))
      : systemPrompt;

    const apiMessages = [
      { role: 'system', content: systemContent },
      ...messages,
    ];

    const body: any = {
      model,
      messages: apiMessages,
      max_tokens: 16384,
      temperature: 0.3,
    };

    if (tools.length > 0) {
      body.tools = tools.map(t => ({
        type: 'function',
        function: { name: t.name, description: t.description, parameters: t.parameters },
      }));
    }

    const estimatedTokens = Math.round(JSON.stringify(body).length / 4);
    console.log(`  ✍️ Writing engine → ${model} (${messages.length} messages, ${tools.length} tools, ~${estimatedTokens} est tokens)`);

    // Retry loop with timeout (ported from Swift performWritingAPICall)
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
          },
          body: JSON.stringify(body),
          signal: AbortSignal.timeout(300_000), // 5 min timeout
        });

        // Retryable errors: 429 rate limit, 5xx server errors
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

        // Log usage + cache stats (matching Swift)
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
  // Build API Messages (with compaction for old turns)
  // ============================================================

  private buildAPIMessages(): any[] {
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

  // ============================================================
  // Persist Conversation
  // ============================================================

  private async persistConversation(): Promise<void> {
    // Save ALL messages including think tool calls — analysis must persist across phases
    const toSave = this.messages.map(m => {
      // For think tool results, preserve full content
      if (m.role === 'tool' && m.toolCallId) {
        const matchingCall = this.messages.find(
          msg => msg.toolCalls?.some(tc => tc.id === m.toolCallId)
        );
        const isThink = matchingCall?.toolCalls?.some(
          tc => tc.id === m.toolCallId && tc.name === 'think'
        );
        if (isThink) {
          return { id: m.id, role: m.role, content: m.content, timestamp: m.timestamp, toolCallId: m.toolCallId };
        }
        return null; // Skip non-think tool results
      }

      // For assistant messages with think tool calls, preserve the full thought
      if (m.toolCalls?.some(tc => tc.name === 'think')) {
        return {
          id: m.id, role: m.role, content: m.content,
          timestamp: m.timestamp,
          toolCalls: m.toolCalls.filter(tc => tc.name === 'think').map(tc => ({
            id: tc.id, name: tc.name,
            arguments: { thought: (tc.arguments as any)?.thought || '' },
          })),
        };
      }

      // Skip assistant messages that only contain non-think tool calls
      if (m.toolCalls && m.toolCalls.length > 0 && !m.toolCalls.some(tc => tc.name === 'think')) {
        return null;
      }

      // For user + assistant text messages, keep with generous truncation
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

  private getToolDefinitions(phase: WritingPhase): any[] {
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
        { name: 'edit_section', description: 'Edit a specific section', parameters: { type: 'object', properties: { sectionIdentifier: { type: 'string' }, newContent: { type: 'string' }, reasoning: { type: 'string' } }, required: ['sectionIdentifier', 'newContent'] } },
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

      // Include ALL lessons regardless of client — writing lessons are universal.
      // A lesson learned from one client's content applies to all content.
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

  // 4. Lesson-derived banned phrases (extract "never use X" / "avoid X" from hard rules)
  const hardRules = lessons.filter(l => l.enforcement === 'hard');
  for (const rule of hardRules) {
    const neverMatch = rule.rule.match(/never use ["'](.+?)["']/i);
    const avoidMatch = rule.rule.match(/avoid ["'](.+?)["']/i);
    const phrase = neverMatch?.[1] || avoidMatch?.[1];
    if (phrase && lowerDraft.includes(phrase.toLowerCase())) {
      violations.push({
        type: 'banned_phrase',
        message: `Learned rule violation: "${phrase}" found in draft (rule: ${rule.rule.substring(0, 80)})`,
      });
    }
  }

  // 5. Em-dash detection (content lines only, not slide headers which use — structurally)
  const contentLines = draft.split('\n').filter(l => !l.match(/^Slide \d+/i));
  const emDashMatches = contentLines.join('\n').match(/[\u2014\u2013]/g);
  if (emDashMatches) {
    violations.push({
      type: 'em_dash',
      message: `${emDashMatches.length} em-dash(es) found in content. Replace ALL with commas, periods, colons, semicolons, or parentheses. Em-dashes are NEVER used in your loaded swipes.`,
    });
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

  // Check blacklisted phrases
  const blacklisted = voice.blacklistedPhrases as string[] | undefined;
  if (blacklisted && blacklisted.length > 0) {
    const lowerDraft = draft.toLowerCase();
    for (const phrase of blacklisted) {
      if (lowerDraft.includes(phrase.toLowerCase())) {
        violations.push(`Client-banned phrase detected: "${phrase}"`);
      }
    }
  }

  return violations;
}
