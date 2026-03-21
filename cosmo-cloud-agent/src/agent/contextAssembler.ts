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

import { AgentIntent } from './intentClassifier';
import { fetchAllByType, loadPromptTemplate, loadConversation } from '../db/queries';

interface SystemPrompt {
  cached: string;
  dynamic: string;
}

// Cache for dynamic context (2 minute TTL, matching Swift)
let contextCache: {
  intent: AgentIntent | null;
  context: string;
  timestamp: number;
} | null = null;

const CACHE_TTL_MS = 120_000;

/**
 * Assemble the full system prompt for the agent.
 * Source: AgentContextAssembler.assembleSystemPrompt() in Swift
 */
export async function assembleSystemPrompt(
  intent: AgentIntent,
  chatId: string,
): Promise<SystemPrompt> {
  // Layer 1: Cached (identity + methodology + tool guidelines)
  const cached = await buildCachedPrompt(intent);

  // Layer 2: Dynamic (GRDB context, preferences, lessons, conversation)
  const dynamic = await buildDynamicPrompt(intent, chatId);

  return { cached, dynamic };
}

// ============================================================
// CACHED PROMPT (Identity + Methodology)
// ============================================================

async function buildCachedPrompt(intent: AgentIntent): Promise<string> {
  const sections: string[] = [];

  // Identity prompt
  const isLightweight = ['capture', 'correct', 'meta'].includes(intent);
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

async function buildDynamicPrompt(intent: AgentIntent, chatId: string): Promise<string> {
  // Check cache
  const now = Date.now();
  if (contextCache && contextCache.intent === intent && (now - contextCache.timestamp) < CACHE_TTL_MS) {
    return contextCache.context;
  }

  const sections: string[] = [];

  // Intent-aware context
  const intentContext = await buildIntentContext(intent);
  if (intentContext) sections.push(intentContext);

  // Standing instructions
  const standingInstructions = await buildStandingInstructions();
  if (standingInstructions) sections.push(standingInstructions);

  // Saved analyses (for writing/strategy intents)
  if (['draft', 'strategy', 'analyze', 'brainstorm'].includes(intent)) {
    const analyses = await buildSavedAnalyses();
    if (analyses) sections.push(analyses);
  }

  // Learned preferences
  const prefs = await buildPreferences();
  if (prefs) sections.push(prefs);

  // Learned skills (lessons)
  const skills = await buildSkills(intent);
  if (skills) sections.push(skills);

  // Conversation history
  const convHistory = await buildConversationHistory(chatId);
  if (convHistory) sections.push(convHistory);

  const dynamic = sections.join('\n\n');

  // Cache
  contextCache = { intent, context: dynamic, timestamp: now };

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

async function buildConversationHistory(chatId: string): Promise<string | null> {
  const conv = await loadConversation(chatId);
  if (!conv || !conv.messages || conv.messages.length === 0) return null;

  // Show summary if available, otherwise last few messages
  if (conv.summary) {
    return `[CONVERSATION CONTEXT]\n${conv.summary}`;
  }

  const recent = conv.messages.slice(-6);
  const lines = ['[RECENT CONVERSATION]'];
  for (const msg of recent) {
    const role = msg.role === 'user' ? 'User' : 'Cosmo';
    const content = typeof msg.content === 'string'
      ? msg.content.substring(0, 150)
      : JSON.stringify(msg.content).substring(0, 150);
    lines.push(`  ${role}: ${content}`);
  }

  return lines.join('\n');
}

// ============================================================
// Identity Prompts
// ============================================================

const FULL_IDENTITY = `You are Cosmo — a personal creative strategist and ghostwriter. You are NOT a helper or assistant. You are a writing partner who delivers COMPLETE work.

CORE RULES:
- NEVER write full drafts or outlines inline. Route ALL content generation through writing tools (generate_outline, generate_draft, revise_draft).
- NEVER hallucinate statistics, numbers, or data. If you don't know, call the relevant tool.
- NEVER mention tool names to the user. Just do the work.
- NEVER expose raw UUIDs, JSON, or metadata. Reference items by their actual titles.
- ALWAYS call relevant tools before responding about user data (search_ideas, search_swipes, get_client_profile, etc.)
- When the user references a number (#1, "the first one"), resolve it from the most recent numbered list.
- For content creation: create_content() → generate_outline() → generate_draft(). Always in this order.
- Before creating new content, check the ACTIVE CONTENT list to avoid duplicates.

TELEGRAM RESPONSE RULES:
- Keep responses concise (2-3 sentences max for summaries)
- No Markdown headers or complex formatting
- Plain text with minimal emoji
- After generating a draft, show it and stop. No analysis unless asked.

TASK DISPLAY RULES:
- When showing tasks, use clear sectioned formatting
- Priority indicators: 🔴 critical, 🟠 high, 🟡 medium, ⚪ low
- Intent icons: ✍️ writeContent, 🔍 research, ⚡ studySwipes, 🧠 deepThink, 👀 review
- 🔄 = recurring task, ⚠️ = overdue
- Show times in 12h format (9:00 AM)
- Group today's tasks: OVERDUE → SCHEDULED → UNSCHEDULED
- For upcoming: group by day with date headers
- Use numbered lists so user can reference tasks by # ("complete #3", "reschedule #2")
- Show project in [brackets] after title, checklist progress as (2/5)
- For task creation, use smart_task_create which parses natural language (priority, date, time, recurrence, project)
- ALWAYS use get_tasks to show task lists — NEVER make up task data

WRITING QUALITY:
- No generic openers ("In today's world...", "Have you ever wondered...")
- No filler words ("delve", "unleash", "unlock", "game-changer")
- Good hooks: contrarian claim, specific result, pattern interrupt, story lead, direct challenge
- Blueprint-first: search for structurally relevant swipes, extract skeletons, steal structure not phrases`;

const LIGHTWEIGHT_IDENTITY = `You are Cosmo — a personal creative assistant. Keep responses brief and action-oriented.

RULES:
- Call relevant tools before responding about user data
- Never expose UUIDs or raw JSON
- Reference items by title
- For URLs: capture as swipes unless told otherwise
- Keep Telegram responses concise`;
