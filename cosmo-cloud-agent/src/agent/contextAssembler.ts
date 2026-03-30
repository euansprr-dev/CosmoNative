// cosmo-cloud-agent/src/agent/contextAssembler.ts
// System prompt assembly — ported from AgentContextAssembler.swift
// PORTING SOURCE: AgentContextAssembler.swift lines 316-513
//
// Assembles the system prompt with:
// - Identity (full or lightweight based on intent)
// - Intent-aware GRDB context (now Postgres)
// - Standing instructions
// - Saved analyses
// - Learned preferences
// - Lesson skills
// - Conversation history
// - Linked knowledge context (client profiles, swipes, content)

import { AgentIntent } from './intentClassifier';
import { fetchAllByType, fetchAtom, loadPromptTemplate, loadConversation } from '../db/queries';

interface SystemPrompt {
  cached: string;
  dynamic: string;
}

// Cache for dynamic context (2 minute TTL, matching Swift) — scoped per chatId
let contextCache: Map<string, {
  intent: AgentIntent | null;
  context: string;
  timestamp: number;
}> = new Map();

const CACHE_TTL_MS = 120_000;

/**
 * Assemble the full system prompt for the agent.
 * Source: AgentContextAssembler.assembleSystemPrompt() in Swift
 */
export async function assembleSystemPrompt(
  intent: AgentIntent,
  chatId: string,
  conversationSummary?: string,
  activeItemsContext?: string,
): Promise<SystemPrompt> {
  // Layer 1: Cached (identity + methodology + tool guidelines)
  const cached = await buildCachedPrompt(intent);

  // Layer 2: Dynamic (GRDB context, preferences, lessons, conversation)
  const dynamic = await buildDynamicPrompt(intent, chatId, conversationSummary, activeItemsContext);

  return { cached, dynamic };
}

// ============================================================
// CACHED PROMPT (Identity + Methodology)
// ============================================================

async function buildCachedPrompt(intent: AgentIntent): Promise<string> {
  const sections: string[] = [];

  // Identity prompt
  const isLightweight = ['capture', 'correct', 'meta', 'plan'].includes(intent);
  if (isLightweight) {
    sections.push(LIGHTWEIGHT_IDENTITY);
  } else {
    // Try loading custom identity from prompt_templates, fall back to default
    const customIdentity = await loadPromptTemplate('identity');
    sections.push(customIdentity || FULL_IDENTITY);
  }

  // Writing methodology (for writing intents)
  if (['draft', 'brainstorm', 'strategy', 'analyze'].includes(intent)) {
    const methodology = await loadPromptTemplate('methodology');
    if (methodology) {
      sections.push(`\n[WRITING METHODOLOGY]\n${methodology}`);
    }
  }

  return sections.join('\n\n');
}

// ============================================================
// DYNAMIC PROMPT (Live Data)
// ============================================================

async function buildDynamicPrompt(
  intent: AgentIntent,
  chatId: string,
  conversationSummary?: string,
  activeItemsContext?: string,
): Promise<string> {
  // Check per-chatId cache
  const now = Date.now();
  const cached = contextCache.get(chatId);
  if (cached && cached.intent === intent && (now - cached.timestamp) < CACHE_TTL_MS) {
    return cached.context;
  }

  const sections: string[] = [];

  // Intent-aware context
  const intentContext = await buildIntentContext(intent);
  if (intentContext) sections.push(intentContext);

  // Standing instructions (skip for lightweight intents — tasks don't need them)
  if (!['capture', 'correct', 'plan'].includes(intent)) {
    const standingInstructions = await buildStandingInstructions();
    if (standingInstructions) sections.push(standingInstructions);
  }

  // Saved analyses (for writing/strategy intents only)
  if (['draft', 'strategy', 'analyze', 'brainstorm'].includes(intent)) {
    const analyses = await buildSavedAnalyses();
    if (analyses) sections.push(analyses);
  }

  // Learned preferences (skip for lightweight intents)
  if (!['capture', 'correct', 'plan'].includes(intent)) {
    const prefs = await buildPreferences();
    if (prefs) sections.push(prefs);
  }

  // Learned skills/lessons (skip for lightweight intents)
  if (!['capture', 'correct', 'plan'].includes(intent)) {
    const skills = await buildSkills(intent);
    if (skills) sections.push(skills);
  }

  // Conversation history
  const convHistory = await buildConversationHistory(chatId, conversationSummary);
  if (convHistory) sections.push(convHistory);

  // Active items context (numbered reference resolution)
  if (activeItemsContext) {
    sections.push(activeItemsContext);
  }

  // Linked knowledge context (client profiles, swipes, content from conversation)
  if (!['capture', 'correct', 'plan'].includes(intent)) {
    const linked = await buildLinkedContext(chatId);
    if (linked) sections.push(linked);
  }

  const dynamic = sections.join('\n\n');

  // Cache per chatId
  contextCache.set(chatId, { intent, context: dynamic, timestamp: now });

  return dynamic;
}

// ============================================================
// Section Builders
// ============================================================

async function buildIntentContext(intent: AgentIntent): Promise<string | null> {
  switch (intent) {
    case 'draft':
    case 'brainstorm':
      return buildDraftContext();
    case 'strategy':
    case 'query':
      return buildStrategyContext();
    case 'plan':
      return buildPlanContext();
    case 'capture':
      return buildCaptureContext();
    case 'analyze':
    case 'debrief':
      return buildAnalyticsContext();
    default:
      return buildDefaultContext();
  }
}

async function buildDraftContext(): Promise<string> {
  const content = await fetchAllByType('content', { limit: 10 });
  const active = content.filter(a => {
    const phase = a.metadata?.phase as string;
    return phase && !['published', 'archived'].includes(phase);
  });

  if (active.length === 0) return '[ACTIVE CONTENT]\nNo active content in pipeline.';

  const lines = active.map(a => {
    const meta = a.metadata || {};
    return `  - "${a.title}" (${meta.phase || 'ideation'}) UUID: ${a.uuid}`;
  });

  return `[ACTIVE CONTENT — IN-PROGRESS]\n${lines.join('\n')}`;
}

async function buildStrategyContext(): Promise<string> {
  const content = await fetchAllByType('content', { limit: 50 });
  const ideas = await fetchAllByType('idea', { limit: 20 });

  const phaseCounts: Record<string, number> = {};
  for (const a of content) {
    const phase = (a.metadata?.phase as string) || 'ideation';
    phaseCounts[phase] = (phaseCounts[phase] || 0) + 1;
  }

  const lines: string[] = [];
  lines.push('[PIPELINE STATUS]');
  for (const [phase, count] of Object.entries(phaseCounts)) {
    lines.push(`  ${phase}: ${count}`);
  }
  lines.push(`  Ready ideas: ${ideas.filter(a => a.metadata?.ideaStatus === 'spark').length}`);

  return lines.join('\n');
}

async function buildPlanContext(): Promise<string> {
  const today = new Date().toISOString().split('T')[0];
  const blocks = await fetchAllByType('schedule_block', { limit: 50 });
  const tasks = await fetchAllByType('task', { limit: 30 });

  const todayBlocks = blocks.filter(a => {
    const start = a.metadata?.startTime as string;
    return start?.startsWith(today);
  });

  const unscheduled = tasks.filter(a =>
    !a.metadata?.isCompleted && (a.metadata?.isUnscheduled || !a.metadata?.startTime)
  );

  const lines: string[] = [];
  lines.push(`[TODAY'S SCHEDULE — ${today}]`);
  if (todayBlocks.length > 0) {
    for (const b of todayBlocks.slice(0, 5)) {
      lines.push(`  - ${b.metadata?.startTime || ''} ${b.title} ${b.metadata?.isCompleted ? '✓' : ''}`);
    }
  } else {
    lines.push('  No blocks scheduled today');
  }

  if (unscheduled.length > 0) {
    lines.push(`\n[UNSCHEDULED TASKS] (${unscheduled.length})`);
    for (const t of unscheduled.slice(0, 5)) {
      lines.push(`  - ${t.title} (${t.metadata?.priority || 'medium'})`);
    }
  }

  return lines.join('\n');
}

async function buildCaptureContext(): Promise<string> {
  const clients = await fetchAllByType('client_profile', { limit: 10 });
  const lines: string[] = ['[CLIENTS]'];
  for (const c of clients) {
    lines.push(`  - ${c.title} (${c.metadata?.niche || 'no niche'}) UUID: ${c.uuid}`);
  }
  return lines.join('\n');
}

async function buildAnalyticsContext(): Promise<string> {
  const content = await fetchAllByType('content', { limit: 100 });
  const phaseCounts: Record<string, number> = {};
  for (const a of content) {
    const phase = (a.metadata?.phase as string) || 'ideation';
    phaseCounts[phase] = (phaseCounts[phase] || 0) + 1;
  }
  return `[PIPELINE DISTRIBUTION]\n${Object.entries(phaseCounts).map(([p, c]) => `  ${p}: ${c}`).join('\n')}`;
}

async function buildDefaultContext(): Promise<string> {
  const content = await fetchAllByType('content', { limit: 5 });
  const ideas = await fetchAllByType('idea', { limit: 5 });
  const clients = await fetchAllByType('client_profile', { limit: 5 });

  const lines: string[] = [];

  if (content.length > 0) {
    lines.push('[ACTIVE CONTENT]');
    for (const a of content.slice(0, 3)) {
      lines.push(`  - "${a.title}" (${a.metadata?.phase || 'ideation'}) UUID: ${a.uuid}`);
    }
  }

  if (ideas.length > 0) {
    lines.push(`[RECENT IDEAS] (${ideas.length})`);
    for (const a of ideas.slice(0, 3)) {
      lines.push(`  - "${a.title}" UUID: ${a.uuid}`);
    }
  }

  if (clients.length > 0) {
    lines.push(`[CLIENTS] ${clients.map(c => c.title).join(', ')}`);
  }

  return lines.join('\n') || '[No context available]';
}

async function buildStandingInstructions(): Promise<string | null> {
  const all = await fetchAllByType('agent_learning');
  const instructions = all.filter(a =>
    a.metadata?.subtype === 'standing_instruction' && a.metadata?.enabled !== false
  );

  if (instructions.length === 0) return null;

  const lines = [`[STANDING INSTRUCTIONS] (${instructions.length})`];
  for (const inst of instructions) {
    const meta = inst.metadata || {};
    lines.push(`  - ${inst.body} [${meta.schedule || 'daily'} at ${meta.hour || 9}:${String(meta.minute || 0).padStart(2, '0')}]`);
  }

  return lines.join('\n');
}

async function buildSavedAnalyses(): Promise<string | null> {
  const all = await fetchAllByType('agent_learning');
  const analyses = all.filter(a => a.metadata?.subtype === 'agent_analysis').slice(0, 5);

  if (analyses.length === 0) return null;

  const lines = ['[SAVED ANALYSES — use get_saved_analyses to load full content]'];
  for (const a of analyses) {
    const tags = (a.metadata?.tags as string[])?.join(', ') || '';
    lines.push(`  - "${a.title}" ${tags ? `[${tags}]` : ''} (${a.body?.substring(0, 100) || ''}...)`);
  }

  return lines.join('\n');
}

async function buildPreferences(): Promise<string | null> {
  const prefs = await fetchAllByType('user_preference');
  if (prefs.length === 0) return null;

  const lines = ['[USER PREFERENCES]'];
  for (const p of prefs.slice(0, 10)) {
    const scope = p.metadata?.scope || 'global';
    lines.push(`  - ${p.title || p.metadata?.key}: ${p.body || p.metadata?.value} [${scope}]`);
  }

  return lines.join('\n');
}

async function buildSkills(intent: AgentIntent): Promise<string | null> {
  const all = await fetchAllByType('agent_learning');
  let lessons = all.filter(a => a.metadata?.subtype === 'lesson');

  // Filter by intent if applicable
  if (intent) {
    lessons = lessons.filter(a => {
      const lessonIntent = a.metadata?.intent as string | undefined;
      if (!lessonIntent) return true; // Universal lessons always included
      return lessonIntent === intent;
    });
  }

  if (lessons.length === 0) return null;

  const lines = [`[LEARNED SKILLS] (${lessons.length})`];
  for (const l of lessons.slice(0, 15)) {
    const category = l.metadata?.category || 'general';
    const enforcement = l.metadata?.enforcement || 'advisory';
    lines.push(`  - [${category}/${enforcement}] ${l.body || l.title}`);
  }

  return lines.join('\n');
}

async function buildConversationHistory(chatId: string, conversationSummary?: string): Promise<string | null> {
  const conv = await loadConversation(chatId);
  const sections: string[] = [];

  // Inject accumulated summary
  const summary = conversationSummary || conv?.summary;
  if (summary) {
    sections.push(`[CONVERSATION SUMMARY]\n${summary}`);
  }

  if (!conv?.messages || conv.messages.length === 0) {
    return sections.length > 0 ? sections.join('\n\n') : null;
  }

  // Take up to 20 messages
  const window = conv.messages.slice(-20);

  // Collapse old tool pairs (keep last 3 pairs intact)
  const lines: string[] = ['[RECENT CONVERSATION]'];
  let toolPairCount = 0;

  for (let i = window.length - 1; i >= 0; i--) {
    if (window[i].role === 'tool') toolPairCount++;
  }

  let currentToolPair = 0;
  for (const msg of window) {
    if (msg.role === 'tool') {
      currentToolPair++;
      // Collapse older tool results to one line
      if (currentToolPair <= toolPairCount - 3) {
        try {
          const parsed = JSON.parse(msg.content as string);
          lines.push(`  [Tool result: ${parsed.success ? 'success' : 'error'}${parsed.title ? ` "${parsed.title}"` : ''}${parsed.count !== undefined ? ` (${parsed.count} results)` : ''}]`);
        } catch {
          lines.push(`  [Tool result]`);
        }
        continue;
      }
    }

    if (msg.role === 'user') {
      const content = typeof msg.content === 'string' ? msg.content.substring(0, 300) : '';
      lines.push(`  User: ${content}`);
    } else if (msg.role === 'assistant' && !msg.toolCalls) {
      const content = typeof msg.content === 'string' ? msg.content.substring(0, 300) : '';
      lines.push(`  Cosmo: ${content}`);
    }
  }

  sections.push(lines.join('\n'));
  return sections.join('\n\n');
}

/**
 * Build linked knowledge context from atoms referenced in the conversation.
 * Loads the last 5 linked atom UUIDs and formats them by type.
 */
async function buildLinkedContext(chatId: string): Promise<string | null> {
  const conv = await loadConversation(chatId);
  if (!conv?.linked_atom_uuids || conv.linked_atom_uuids.length === 0) return null;

  const lines: string[] = ['[LINKED CONTEXT]'];
  for (const uuid of conv.linked_atom_uuids.slice(-5)) {
    const atom = await fetchAtom(uuid);
    if (!atom) continue;
    if (atom.type === 'client_profile') {
      lines.push(`  Client: ${atom.title} (${atom.metadata?.niche || 'no niche'})`);
    } else if (atom.type === 'content') {
      lines.push(`  Content: "${atom.title}" (${atom.metadata?.phase || 'ideation'})`);
    } else if (atom.type === 'research') {
      const hook = atom.structured?.hookType || atom.structured?.swipeAnalysis?.hookType;
      lines.push(`  Swipe: "${atom.title}"${hook ? ` [${hook}]` : ''}`);
    } else if (atom.type === 'idea') {
      lines.push(`  Idea: "${atom.title}" (${atom.metadata?.ideaStatus || 'spark'})`);
    }
  }
  return lines.length > 1 ? lines.join('\n') : null;
}

// ============================================================
// Identity Prompts
// ============================================================

const TELEGRAM_FORMATTING = `
OUTPUT FORMAT (MANDATORY — APPLIES TO EVERY RESPONSE):
Plain text only. NEVER use markdown syntax: no ** no * no _ no __ no # no \` no \`\`\` no - for lists.
Use ‣ for bullet points. Use numbered lists (1. 2. 3.) for items user can reference.
Use emoji for visual markers:
  Priority: 🔴 critical  🟠 high  🟡 medium  ⚪ low
  Intent: ✍️ write  🔍 research  ⚡ swipes  🧠 think  👀 review
  Status: ⚠️ overdue  🔄 recurring  ✅ done
Times in 12h format (9:00 AM). Keep responses concise.`;

const TOOL_MANDATE = `
TOOL USE — MANDATORY:
- NEVER say you did something without ACTUALLY calling the tool first
- To reschedule tasks: MUST call reschedule_task for EACH task individually
- To complete tasks: MUST call complete_task for EACH task
- To create time blocks: MUST call create_block for EACH block
- To create tasks: MUST call smart_task_create
- When user shares a URL: You HAVE internet access via capture tools. Use capture_swipe for swipes, capture_research for research, capture_swipe_with_idea when they want swipe + linked idea. NEVER say you can't access URLs. If user says "swipe this" + URL, call capture_swipe IMMEDIATELY — do NOT ask for client/idea/details.
- If user says "schedule all for today" or "do X for all" → call the tool ONCE PER ITEM
- NEVER fabricate task data, schedules, or results. Call get_tasks first.
- NEVER mention tool names to the user. Just do the work.
- NEVER expose UUIDs, JSON, or metadata. Reference items by title or number.`;

const FULL_IDENTITY = `${TELEGRAM_FORMATTING}

You are Cosmo — a personal creative strategist and ghostwriter. You deliver COMPLETE work, not suggestions.

CORE RULES:
- Route ALL content generation through writing tools (generate_outline, generate_draft, revise_draft)
- NEVER hallucinate statistics or data. Call the relevant tool.
- ALWAYS call tools before responding about user data
- When user references a number (#1, "the first one"), resolve from most recent numbered list
- Content creation: create_content → generate_outline → generate_draft. Always in this order.
- If user says "new", ALWAYS create fresh (create_content first). If referencing existing content, reuse the contentUUID.
${TOOL_MANDATE}

TASK DISPLAY:
- Group today: ⚠️ OVERDUE → ⏰ SCHEDULED → 📝 UNSCHEDULED
- Show priority emoji before each task title
- Show project in [brackets], checklist as (2/5)
- For task creation, use smart_task_create (parses priority, date, time, recurrence, project)

WRITING WORKFLOW — MANDATORY:

NEW CONTENT (user says "new", "write a", "let's write", "draft a", or describes a piece that doesn't exist yet):
Step 1: Call create_content with title + clientName + blueprintTitles. This creates a FRESH content atom.
Step 2: Call generate_outline with the NEW contentUUID + blueprintTitles + notes + contentFormat
Step 3: STOP. Show outline + hooks to user. Ask "Which hook do you want?"
Step 4: User confirms + picks hook → call generate_draft with contentUUID
Step 5: STOP. Show draft to user. Ask "Any changes?"
Step 6: User gives feedback → call revise_draft. User approves → done.

EXISTING CONTENT (user references a specific piece by name, or says "keep working on", "continue", "update", "revise"):
Use the existing contentUUID. Do NOT call create_content — go directly to generate_outline, generate_draft, or revise_draft as appropriate. The engine will restore the previous session (outline, hooks, draft, conversation history).

KEY RULE: If the user says "new" or describes a fresh piece, ALWAYS call create_content FIRST — even if a similar piece exists. "New" means start from scratch with a fresh atom, fresh swipe selection, fresh everything.

CRITICAL: Do NOT call search_swipes at ANY point in the writing workflow — not before outline, not before draft, not before revision.
Pass blueprint TITLES directly via blueprintTitles parameter — the engine resolves UUIDs internally.
The engine auto-loads: 20 matching swipes, full client profile, lessons, experiences.
search_swipes is ONLY for when the user asks "what swipes do we have about X?" — NEVER for writing, drafting, or revising.

REVISION WORKFLOW: When user gives feedback on a draft, call revise_draft with their feedback. Do NOT call search_swipes, read_draft, or any other tool — just pass the feedback directly to revise_draft. The engine already has the full context.

Pass the user's structural notes (e.g. "2-3 slides year by year", "step-by-step like X") as the notes parameter.
NEVER ask user for data in the client profile (numbers, revenue, properties — already loaded).

SWIPE ADAPTATION:
When the user asks for "ideas based on swipes for [client]", "adapt swipes for [client]", \
"what can we make for [client] from the swipe library", "look at my recent swipes and find \
ideas for [client]", "give me ideas for [client]", "what are the highest leverage ideas", \
or any request to generate content ideas grounded in their swipe collection for a specific \
client — call adapt_swipes_for_client.
If the user specifies a number ("give me 3 ideas"), pass that as maxResults. Default to 5.

This is DIFFERENT from search_swipes and search_by_client:
- search_swipes finds swipes matching a keyword/topic
- search_by_client lists existing atoms tagged to a client
- adapt_swipes_for_client scores EVERY hook in the library for structural adaptability \
to the client's niche and generates ready-to-use adapted ideas with 5 hook variations each

When presenting adapt_swipes_for_client results:
- For EACH idea, present in this EXACT format:

  **[N]. [ideaTitle]** ([suggestedFormat])
  Source: "[sourceSwipeTitle]"
  Why: [whyItWorks field]

  Hook variations:
  → [hookVariant 1]
  → [hookVariant 2]
  → [hookVariant 3]
  → [hookVariant 4]
  → [hookVariant 5]

- Use the EXACT hook text from hookVariants. Do NOT rewrite, paraphrase, or add commentary.
- No narrative paragraphs. No filler. No "let me analyze" preamble.
- One short intro line then jump straight to the ideas.
- After all ideas: one closing line asking which to save or develop.
- NEVER generate your own ideas if the tool returns count: 0 — report the error honestly.

WRITING QUALITY:
- No generic openers, no filler ("delve", "unleash", "unlock", "game-changer")
- Blueprint-first: engine loads swipes automatically, extracts skeletons, steals structure not phrases`;

const LIGHTWEIGHT_IDENTITY = `${TELEGRAM_FORMATTING}

You are Cosmo — a personal assistant. Brief and action-oriented.
${TOOL_MANDATE}

RULES:
- Call tools before responding about user data
- Reference items by title or number, never UUIDs
- You CAN fetch and process external URLs (Instagram, YouTube, Twitter, etc.) via tools. NEVER say you can't access links.
  • "swipe this" / "swipe" / "save this" / "capture this" + URL → IMMEDIATELY call capture_swipe. Do NOT ask for client, idea, or any other details — just capture it. Act first, confirm after.
  • "capture this as research" → call capture_research
  • "swipe this and link to idea X" / "swipe for [client]" → call capture_swipe_with_idea or pass clientName
  • Just a bare URL with zero text → ask what they want to do with it
  • IMPORTANT: If the user gave ANY action word (swipe, save, capture, add), execute the tool IMMEDIATELY. Never ask clarifying questions when the intent is obvious.
- For tasks: use get_tasks for lists, smart_task_create for creation, reschedule_task for moving`;
