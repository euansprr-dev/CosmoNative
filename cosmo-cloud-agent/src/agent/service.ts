// cosmo-cloud-agent/src/agent/service.ts
// Main agent orchestrator — ported from CosmoAgentService.swift
// PORTING SOURCE: CosmoAgentService.swift lines 300-700
//
// Flow: classify intent → assemble context → tool loop → response

import { config } from '../config';
import { classifyIntent, modelTierForIntent, maxToolIterations, AgentIntent, ModelTier } from './intentClassifier';
import { assembleSystemPrompt } from './contextAssembler';
import { executeTool, jsonEncode } from './toolExecutor';
import { loadConversation, saveConversation, logApiUsage, createAtom, fetchAtom } from '../db/queries';
import { getToolDefinitions } from './toolRegistry';

interface AgentMessage {
  role: 'system' | 'user' | 'assistant' | 'tool';
  content: string | any[];
  tool_calls?: any[];
  tool_call_id?: string;
  name?: string;
}

interface ProcessResult {
  response: string;
  toolsUsed: string[];
  createdAtomUUIDs: string[];
  intent: AgentIntent;
}

// Module-level active items context for numbered reference resolution
const activeItemsContext = new Map<string, string>();

// ============================================================
// Session Rotation / Auto-Summarization
// ============================================================

async function summarizeOlderMessages(messages: AgentMessage[], chatId: string): Promise<{ summary: string; recentMessages: AgentMessage[] }> {
  const keepCount = 8;
  if (messages.length <= 15) return { summary: '', recentMessages: messages };

  const older = messages.slice(0, -keepCount);
  const recent = messages.slice(-keepCount);

  // Build text summary of older messages
  const olderText = older.map(m => `${m.role}: ${typeof m.content === 'string' ? m.content.substring(0, 200) : ''}`).join('\n');

  try {
    const response = await fetch(`${config.openRouterBaseUrl}/chat/completions`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${config.openRouterApiKey}` },
      body: JSON.stringify({
        model: config.models.sensor,
        messages: [
          { role: 'system', content: 'Summarize this conversation in 2-3 sentences. Preserve: client names, content pieces created (titles), key creative decisions, and any feedback given.' },
          { role: 'user', content: olderText },
        ],
        max_tokens: 256,
      }),
    });
    const data = await response.json() as any;
    const summary = data.choices?.[0]?.message?.content || '';
    return { summary, recentMessages: recent };
  } catch {
    return { summary: '', recentMessages: messages.slice(-keepCount) };
  }
}

// ============================================================
// Intent Escalation
// ============================================================

function escalateIntent(intent: AgentIntent, messages: AgentMessage[]): AgentIntent {
  // Already draft/brainstorm — no escalation needed
  if (intent === 'draft' || intent === 'brainstorm') return intent;
  if (messages.length === 0) return intent;

  const recentMessages = messages.slice(-10);

  // Session-aware escalation: if there's an active writing session (recent writing tool usage),
  // ANY intent escalates to draft. This handles ALL revision wordings without keyword matching.
  const writingToolNames = ['generate_outline', 'generate_draft', 'generate_hooks', 'revise_draft', 'create_content'];
  const hasActiveWritingSession = recentMessages.some(m => {
    // Check tool call results for writing tool output
    if (m.role === 'tool' && typeof m.content === 'string') {
      return m.content.includes('formattedDraft') || m.content.includes('outlineSections')
        || m.content.includes('hookVariants') || m.content.includes('"contentUUID"');
    }
    // Check if agent called writing tools
    if (m.tool_calls) {
      return m.tool_calls.some((tc: any) => {
        const name = tc.function?.name || tc.name || '';
        return writingToolNames.includes(name);
      });
    }
    return false;
  });

  if (hasActiveWritingSession && intent !== 'capture') {
    console.log(`🧠 Escalated ${intent} → draft (active writing session detected)`);
    return 'draft';
  }

  // Fallback: creative signal escalation for query intent only
  if (intent !== 'query') return intent;

  const creativeSignals = ['write', 'draft', 'reel', 'thread', 'carousel', 'hook', 'outline', 'brainstorm', 'punchier', 'rewrite', 'make it', 'too formal', 'too long'];
  const creativeTools = new Set(['generate_outline', 'generate_draft', 'generate_hooks', 'revise_draft', 'search_swipes', 'find_similar_swipes', 'create_content', 'get_client_profile', 'get_beat_patterns']);

  const hasCreativeText = recentMessages.some(m => {
    if (m.role !== 'user') return false;
    const lower = (typeof m.content === 'string' ? m.content : '').toLowerCase();
    return creativeSignals.some(s => lower.includes(s));
  });

  const hasCreativeTools = recentMessages.some(m => {
    if (!m.tool_calls) return false;
    return m.tool_calls.some((tc: any) => {
      const name = tc.function?.name || tc.name || '';
      return creativeTools.has(name);
    });
  });

  if (hasCreativeText || hasCreativeTools) return 'draft';
  return intent;
}

/**
 * Fast-path capture: if the user sends an obvious "swipe this [URL]" or "capture [URL]",
 * skip the LLM entirely and call capture_swipe directly. This avoids Haiku asking
 * unnecessary clarifying questions.
 */
async function tryFastCapture(
  text: string,
  intent: AgentIntent,
  chatId: string,
  messages: AgentMessage[],
  onToolProgress?: ToolProgressCallback,
): Promise<ProcessResult | null> {
  if (intent !== 'capture') return null;

  const lower = text.toLowerCase();
  const urlMatch = text.match(/https?:\/\/[^\s]+/);
  if (!urlMatch) return null;

  const url = urlMatch[0];
  const hasSwipeKeyword = /swipe|save this|capture this|add this/i.test(lower);

  // Only fast-path when there's a clear action word — bare URLs still go through LLM
  if (!hasSwipeKeyword) return null;

  console.log(`⚡ Fast-path capture: ${url}`);

  onToolProgress?.({ type: 'started', tool: 'capture_swipe', label: 'Swiping...' });

  const result = await executeTool('capture_swipe', { url });

  onToolProgress?.({ type: 'completed', tool: 'capture_swipe', label: 'Swiped', preview: url });

  let parsed: any = {};
  try { parsed = JSON.parse(result); } catch {}

  const createdAtomUUIDs = parsed.uuid ? [parsed.uuid] : [];

  // Build a confirmation response
  const title = parsed.title || 'Swipe';
  const source = parsed.source || 'link';
  const response = parsed.success !== false
    ? `⚡ Swiped\n\n${title}\n${source} ‣ saved to your library`
    : `Something went wrong capturing that URL. ${parsed.error || ''}`;

  // Save to conversation history
  messages.push({ role: 'user', content: text });
  messages.push({ role: 'assistant', content: response });
  await saveConversation(chatId, messages, { linkedAtomUUIDs: createdAtomUUIDs });

  return { response, toolsUsed: ['capture_swipe'], createdAtomUUIDs, intent: 'capture' };
}

/**
 * Process a user message through the full agent pipeline.
 * Source: CosmoAgentService.processMessage() in Swift
 */
export type ToolProgressCallback = (event: { type: 'started' | 'completed'; tool: string; label: string; preview?: string }) => void;

export async function processMessage(
  text: string,
  chatId: string,
  onToolProgress?: ToolProgressCallback,
): Promise<ProcessResult> {
  // 1. Classify intent (with escalation based on conversation history)
  let intent = classifyIntent(text);
  const existingConv = await loadConversation(chatId);
  const messages: AgentMessage[] = existingConv?.messages || [];

  // Escalate intent based on conversation context
  intent = escalateIntent(intent, messages);

  const tier = modelTierForIntent(intent);
  const model = config.models[tier];
  const iterationLimit = maxToolIterations(intent);

  console.log(`🧠 Intent: ${intent} | Model: ${model} | Max iterations: ${iterationLimit}`);

  // 1b. FAST PATH — deterministic capture for obvious swipe/capture commands
  // Bypasses LLM entirely when intent is unambiguous (e.g. "swipe this" + URL)
  const fastCaptureResult = await tryFastCapture(text, intent, chatId, messages, onToolProgress);
  if (fastCaptureResult) return fastCaptureResult;

  // 2. Session rotation — summarize older messages if conversation is long
  let conversationSummary = existingConv?.summary || '';
  if (messages.length > 15) {
    const { summary, recentMessages } = await summarizeOlderMessages(messages, chatId);
    if (summary) {
      conversationSummary = conversationSummary ? `${conversationSummary} | ${summary}` : summary;
      messages.length = 0;
      messages.push(...recentMessages);
    }
  }

  // 3. Assemble system prompt (with conversation summary + active items context)
  const systemPrompt = await assembleSystemPrompt(intent, chatId, conversationSummary);

  // Append active items context if available for this chat
  const activeItems = activeItemsContext.get(chatId) || '';

  // 4. Add user message
  messages.push({ role: 'user', content: text });

  // 5. Get available tools for this intent
  const tools = getToolDefinitions(intent);

  // 6. Tool loop
  const toolsUsed: string[] = [];
  const createdAtomUUIDs: string[] = [];
  let finalResponse = '';
  let iterations = 0;

  while (iterations < iterationLimit) {
    iterations++;

    // Build full system prompt with active items
    let fullDynamic = systemPrompt.dynamic;
    if (activeItems) {
      fullDynamic += `\n\n${activeItems}`;
    }

    // Sanitize messages before sending — remove orphaned tool_calls without matching tool_results
    const sanitizedMessages = sanitizeToolPairs(messages);

    // Call LLM
    const llmResponse = await callLLM({
      model,
      systemPrompt: `${systemPrompt.cached}\n\n${fullDynamic}`,
      messages: sanitizedMessages,
      tools,
    });

    // Track token usage
    if (llmResponse.usage) {
      await logApiUsage({
        model,
        inputTokens: llmResponse.usage.inputTokens,
        outputTokens: llmResponse.usage.outputTokens,
        cachedTokens: llmResponse.usage.cachedTokens || 0,
        costUsd: estimateCost(model, llmResponse.usage),
        intent,
      });
    }

    // If no tool calls, we have the final response
    if (!llmResponse.toolCalls || llmResponse.toolCalls.length === 0) {
      finalResponse = llmResponse.content || '';

      // Add assistant message to history
      messages.push({ role: 'assistant', content: finalResponse });
      break;
    }

    // Execute tool calls
    const assistantMessage: AgentMessage = {
      role: 'assistant',
      content: llmResponse.content || '',
      tool_calls: llmResponse.toolCalls.map(tc => ({
        id: tc.id,
        type: 'function',
        function: { name: tc.name, arguments: JSON.stringify(tc.arguments) },
      })),
    };
    messages.push(assistantMessage);

    for (const toolCall of llmResponse.toolCalls) {
      console.log(`  🔧 Tool: ${toolCall.name}`);
      toolsUsed.push(toolCall.name);

      // Emit progress: started
      const displayLabel = getToolDisplayLabel(toolCall.name, toolCall.arguments);
      onToolProgress?.({ type: 'started', tool: toolCall.name, label: displayLabel });

      const result = await executeTool(toolCall.name, toolCall.arguments);

      // Track created atoms (with deduplication + success check)
      try {
        const parsed = JSON.parse(result);
        if (parsed.success !== false) {
          const uuids = [parsed.uuid, parsed.ideaUUID, parsed.contentUUID, parsed.swipeUUID].filter(Boolean) as string[];
          for (const uuid of uuids) {
            if (!createdAtomUUIDs.includes(uuid)) {
              createdAtomUUIDs.push(uuid);
            }
          }
        }
      } catch {}

      // Track active items for numbered reference resolution
      try {
        const parsed = JSON.parse(result);
        const results = parsed.results || parsed.tasks || parsed.projects || parsed.analyses;
        if (Array.isArray(results) && results.length >= 2) {
          const itemLines = ['[ACTIVE ITEMS — reference by number]'];
          results.slice(0, 15).forEach((item: any, i: number) => {
            const title = item.title || item.name || 'Untitled';
            const uuid = item.uuid || '';
            itemLines.push(`${i + 1}. ${title} (uuid: ${uuid})`);
          });
          activeItemsContext.set(chatId, itemLines.join('\n'));
        }
      } catch {}

      // Emit progress: completed
      const resultPreview = getResultPreview(toolCall.name, result);
      onToolProgress?.({ type: 'completed', tool: toolCall.name, label: displayLabel, preview: resultPreview });

      messages.push({
        role: 'tool',
        content: result,
        tool_call_id: toolCall.id,
      });
    }

    // Compress old tool results (keep last 2 intact, compress older)
    compressOldToolResults(messages);
  }

  // Fallback: if loop exhausted iterations without a final response, explain what happened
  if (!finalResponse && toolsUsed.length > 0) {
    const hasContent = toolsUsed.includes('create_content');
    const hasOutline = toolsUsed.includes('generate_outline');
    const searchCount = toolsUsed.filter(t => t === 'search_swipes').length;
    if (hasContent && !hasOutline) {
      finalResponse = `I created the content atom but ran out of processing steps before generating the outline (${searchCount} searches used). Send "continue" and I'll pick up from here.`;
    } else if (!hasContent) {
      finalResponse = `I ran out of processing steps before completing the task. ${searchCount} searches were made. Please try again with a simpler request.`;
    }
    console.log(`⚠️ Loop exhausted: ${iterations}/${iterationLimit} iterations, tools: ${toolsUsed.join(', ')}`);
  }

  // 7. Save conversation (with summary + linked atoms)
  // Always keep the first user message to ensure loaded conversations
  // start with role=user (required by Anthropic API).
  const firstUserIdx = messages.findIndex(m => m.role === 'user');
  const tail = messages.slice(-30);
  let toSave: AgentMessage[];
  if (firstUserIdx >= 0 && !tail.some(m => m.role === 'user')) {
    // Tail has no user message — prepend the first one
    toSave = [messages[firstUserIdx], ...tail];
  } else {
    toSave = tail;
  }
  await saveConversation(chatId, toSave, {
    summary: conversationSummary || undefined,
    linkedAtomUUIDs: createdAtomUUIDs,
  });

  // Fire-and-forget: extract lessons from conversation if teachable moment detected
  // Try to find active client from tool results (get_client_profile, create_content, generate_outline)
  let activeClientUUID: string | null = null;
  for (const uuid of createdAtomUUIDs) {
    try {
      const atom = await fetchAtom(uuid);
      if (atom?.metadata?.clientProfileUUID) {
        activeClientUUID = atom.metadata.clientProfileUUID as string;
        break;
      }
    } catch {}
  }
  extractLessonsFromConversation(chatId, text, finalResponse, activeClientUUID).catch(() => {});

  return {
    response: finalResponse || 'I processed your request but had no final response.',
    toolsUsed,
    createdAtomUUIDs,
    intent,
  };
}

// ============================================================
// LLM Call
// ============================================================

interface LLMResponse {
  content: string | null;
  toolCalls: Array<{ id: string; name: string; arguments: Record<string, any> }>;
  usage: { inputTokens: number; outputTokens: number; cachedTokens?: number } | null;
}

async function callLLM(params: {
  model: string;
  systemPrompt: string;
  messages: AgentMessage[];
  tools: any[];
}): Promise<LLMResponse> {
  const apiKey = config.openRouterApiKey || config.agentLLMApiKey;
  const baseUrl = config.agentLLMBaseUrl || config.openRouterBaseUrl;

  // Build OpenAI-compatible messages with safety sanitization
  // Collect all tool_result IDs so we can verify tool_calls have matching results
  const toolResultIds = new Set(
    params.messages.filter(m => m.role === 'tool' && m.tool_call_id).map(m => m.tool_call_id!)
  );

  const mappedMessages = params.messages.map(m => {
    if (m.role === 'tool') {
      return { role: 'tool', content: m.content, tool_call_id: m.tool_call_id };
    }
    if (m.tool_calls) {
      // Filter out tool_calls that don't have matching tool_results (prevents Anthropic 400 error)
      const validCalls = m.tool_calls.filter((tc: any) => {
        const id = tc.id || tc.function?.id || '';
        return toolResultIds.has(id);
      });
      if (validCalls.length === 0) {
        // All tool_calls orphaned — send as plain assistant message
        return { role: 'assistant', content: m.content || 'Previous tool calls completed.' };
      }
      return { role: 'assistant', content: m.content || null, tool_calls: validCalls };
    }
    return { role: m.role, content: m.content };
  });

  // Anthropic requires the first non-system message to be role=user.
  // After conversation slicing, the first message may be an orphaned assistant/tool message.
  // Drop leading non-user messages to satisfy the API constraint.
  while (mappedMessages.length > 0 && mappedMessages[0].role !== 'user') {
    mappedMessages.shift();
  }

  const apiMessages: any[] = [
    { role: 'system', content: params.systemPrompt },
    ...mappedMessages,
  ];

  // Build tools in OpenAI format
  const apiTools = params.tools.length > 0
    ? params.tools.map(t => ({
        type: 'function' as const,
        function: {
          name: t.name,
          description: t.description,
          parameters: t.parameters,
        },
      }))
    : undefined;

  const body: any = {
    model: params.model,
    messages: apiMessages,
    max_tokens: 4096,
  };
  if (apiTools) body.tools = apiTools;

  const response = await fetch(`${baseUrl}/chat/completions`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`,
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(`LLM API error ${response.status}: ${errorBody.substring(0, 200)}`);
  }

  const data = await response.json() as any;
  const choice = data.choices?.[0];

  if (!choice) {
    throw new Error('No choices in LLM response');
  }

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
    usage: data.usage ? {
      inputTokens: data.usage.prompt_tokens || 0,
      outputTokens: data.usage.completion_tokens || 0,
      cachedTokens: data.usage.prompt_tokens_details?.cached_tokens || 0,
    } : null,
  };
}

// ============================================================
// Helpers
// ============================================================

/**
 * Remove orphaned tool_calls that don't have matching tool_results.
 * Anthropic API rejects messages with tool_use blocks that aren't followed by tool_result.
 * This happens when conversation history is loaded from a previous session where
 * tool results were compressed or the session was interrupted.
 */
function sanitizeToolPairs(messages: AgentMessage[]): AgentMessage[] {
  const result: AgentMessage[] = [];

  for (let i = 0; i < messages.length; i++) {
    const msg = messages[i];

    // If this is an assistant message with tool_calls, check that ALL tool_calls
    // have matching tool_result messages following it
    if (msg.tool_calls && msg.tool_calls.length > 0) {
      const toolCallIds = new Set(
        msg.tool_calls.map((tc: any) => tc.id || tc.function?.id || '')
      );

      // Look ahead for matching tool_results
      let allMatched = true;
      const matchedResults: AgentMessage[] = [];

      for (let j = i + 1; j < messages.length && matchedResults.length < toolCallIds.size; j++) {
        if (messages[j].role === 'tool' && messages[j].tool_call_id) {
          if (toolCallIds.has(messages[j].tool_call_id!)) {
            matchedResults.push(messages[j]);
          }
        } else if (messages[j].role === 'user' || (messages[j].role === 'assistant' && !messages[j].tool_call_id)) {
          break; // Hit a new turn — stop looking
        }
      }

      if (matchedResults.length < toolCallIds.size) {
        // Orphaned tool_calls — convert to plain assistant message
        result.push({
          role: 'assistant',
          content: msg.content || '[Tool calls from previous session]',
        });
        // Skip the orphaned tool_result messages too
        continue;
      }
    }

    result.push(msg);
  }

  return result;
}

function compressOldToolResults(messages: AgentMessage[]): void {
  let toolResultCount = 0;
  for (let i = messages.length - 1; i >= 0; i--) {
    if (messages[i].role === 'tool') {
      toolResultCount++;
      if (toolResultCount > 2) {
        try {
          const content = messages[i].content as string;
          const parsed = JSON.parse(content);
          const compressed: Record<string, any> = { compressed: true };
          // Core fields
          if (parsed.success !== undefined) compressed.success = parsed.success;
          if (parsed.count !== undefined) compressed.count = parsed.count;
          if (parsed.uuid) compressed.uuid = parsed.uuid;
          if (parsed.title) compressed.title = parsed.title;
          if (parsed.message) compressed.message = parsed.message;
          // Writing refinement fields (CRITICAL for multi-turn)
          if (parsed.weakAreas) compressed.weakAreas = parsed.weakAreas;
          if (parsed.hookScore) compressed.hookScore = parsed.hookScore;
          if (parsed.copyScore) compressed.copyScore = parsed.copyScore;
          if (parsed.ctaScore) compressed.ctaScore = parsed.ctaScore;
          if (parsed.voiceMatchPercentage) compressed.voiceMatchPercentage = parsed.voiceMatchPercentage;
          if (parsed.engineNotes) compressed.engineNotes = typeof parsed.engineNotes === 'string' ? parsed.engineNotes.substring(0, 200) : parsed.engineNotes;
          if (parsed.format) compressed.format = parsed.format;
          if (parsed.wordCount) compressed.wordCount = parsed.wordCount;
          if (parsed.formattedDraft) compressed.formattedDraft = parsed.formattedDraft.substring(0, 2000);
          if (parsed.outlineSections) compressed.outlineSections = parsed.outlineSections;
          if (parsed.hookVariants) compressed.hookVariants = parsed.hookVariants;
          messages[i].content = JSON.stringify(compressed);
        } catch {}
      }
    }
  }
}

// ============================================================
// Auto-Lesson Extraction
// ============================================================

// Require directive framing — bare "never" matches hook text like "he's never suffered"
const TEACHABLE_PATTERN = /\b(remember this|always use|never use|from now on|don't use|do not use|stop using|I prefer|I like when|rule:|lesson:|not like that|that's wrong|that's not what|you should always|next time|I want you to|please don't|going forward|here's what I changed|here's what i changed)\b/i;

async function extractLessonsFromConversation(chatId: string, userMessage: string, agentResponse: string, activeClientUUID?: string | null): Promise<void> {
  // Skip if no teachable signals
  if (!TEACHABLE_PATTERN.test(userMessage)) return;

  try {
    const response = await fetch(`${config.openRouterBaseUrl}/chat/completions`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${config.openRouterApiKey}` },
      body: JSON.stringify({
        model: config.models.sensor, // Haiku — cheap
        messages: [
          {
            role: 'system',
            content: `You analyze conversations to extract reusable writing rules. ONLY extract rules that:
1. The USER explicitly taught, corrected, or stated as a preference
2. Are REUSABLE across different content pieces (not specific to one story or topic)
3. Are about HOW to write, not WHAT to write

Do NOT extract:
- Story-specific feedback (e.g., "add a down slide after the success part" — that's about THIS specific story, not a general rule)
- Content-specific details (names, dates, topics, story beats for one particular piece)
- Generic writing advice the agent already knows (hook structures, blueprint usage)
- The agent's own operational decisions
- Content from hook text, titles, quotes, or creative writing

GOOD rules (reusable): "Always include an emotional bridge before a major life change", "Don't reference roles/jobs without establishing them first", "Keep the dialogue format consistent throughout"
BAD rules (too specific): "Add a 'down' slide after the $6k/month success slide", "Mention Vietnam after the ghostwriting part"

For each rule, classify scope:
- "client": This is about a specific client's voice, style, or preferences
- "universal": This is a general writing principle that applies to all clients

Each rule: {"rule": "clear reusable instruction", "scope": "client|universal", "category": "hook_style|voice|structure|format|cta|general", "evidence": "what the user said"}. If nothing genuinely reusable, return empty array []. ONLY return JSON.`,
          },
          {
            role: 'user',
            content: `User said: "${userMessage}"\n\nAgent responded: "${agentResponse.substring(0, 500)}"`,
          },
        ],
        max_tokens: 512,
        temperature: 0,
      }),
    });

    const data = await response.json() as any;
    const content = data.choices?.[0]?.message?.content || '[]';

    // Parse JSON
    const match = content.match(/\[[\s\S]*\]/);
    if (!match) return;

    const rules = JSON.parse(match[0]);
    if (!Array.isArray(rules) || rules.length === 0) return;

    // Store each rule as a lesson (with structured field for Mac app display)
    for (const rule of rules.slice(0, 3)) {
      if (!rule.rule) continue;

      const lessonId = crypto.randomUUID().toUpperCase();
      const now = new Date().toISOString();
      const category = rule.category || 'general';
      // Scope: LLM classifies as "client" or "universal". Client-scoped lessons get clientUUID.
      const scope = rule.scope || 'universal';
      const clientUUID = scope === 'client' && activeClientUUID ? activeClientUUID : null;

      await createAtom({
        type: 'agent_learning',
        title: (rule.rule as string).substring(0, 80),
        body: rule.rule,
        // structured must match Swift's InferredLesson Codable struct for Mac app display
        structured: {
          id: lessonId,
          clientUUID,
          rule: rule.rule,
          evidence: rule.evidence || '',
          category,
          confidence: 0.7,
          createdAt: now,
          lastConfirmedAt: now,
          source: 'inferred_edit',  // Closest Swift enum value for conversation inference
          enforcement: 'advisory',
          targetModuleId: null,
          intent: null,
        },
        metadata: {
          subtype: 'lesson',
          lessonType: 'inferred_lesson',
          lessonID: lessonId, // Must match what Mac's deleteLearnedSkill() looks for
          category,
          confidence: 0.7,
          source: 'conversation_inference',
          enforcement: 'advisory',
          evidence: rule.evidence || null,
          clientUUID,
        },
      });

      console.log(`\u{1F4DA} Auto-learned [${scope}${clientUUID ? ', client=' + clientUUID.substring(0, 8) : ''}]: ${(rule.rule as string).substring(0, 60)}`);
    }
  } catch (error) {
    // Silent failure — learning is best-effort, never blocks
  }
}

// ============================================================
// Tool Progress Display Labels (matching Swift's toolDisplayLabel)
// ============================================================

function getToolDisplayLabel(tool: string, args: Record<string, any>): string {
  const client = args.clientName || args.client_name || args.name || '';
  switch (tool) {
    case 'get_client_profile': return client ? `Loading profile: ${client}` : 'Loading client profile';
    case 'search_swipes': return 'Searching swipe library';
    case 'list_all_swipes': return 'Loading swipe library';
    case 'find_similar_swipes': return 'Finding similar swipes';
    case 'generate_outline': return client ? `Generating outline for ${client}` : 'Generating outline';
    case 'generate_draft': return client ? `Writing draft for ${client}` : 'Writing draft';
    case 'generate_hooks': return client ? `Generating hooks for ${client}` : 'Generating hooks';
    case 'revise_draft': return client ? `Revising draft for ${client}` : 'Revising draft';
    case 'score_draft': return 'Scoring draft';
    case 'read_draft': return 'Reading current draft';
    case 'update_content': return 'Updating outline';
    case 'create_content': return 'Creating content atom';
    case 'activate_idea': return 'Activating idea to pipeline';
    case 'capture_swipe': return 'Capturing swipe';
    case 'search_ideas': return 'Searching ideas';
    case 'get_tasks': return 'Loading tasks';
    case 'smart_task_create': return 'Creating task';
    case 'complete_task': return 'Completing task';
    case 'reschedule_task': return 'Rescheduling task';
    case 'learn_from_url': return 'Learning from URL';
    case 'learn_from_text': return 'Learning from content';
    case 'web_search': return `Searching: ${args.query || ''}`;
    default: return tool.replace(/_/g, ' ');
  }
}

function getResultPreview(tool: string, result: string): string {
  try {
    const parsed = JSON.parse(result);
    switch (tool) {
      case 'generate_outline': {
        const swipes = parsed.swipesLoaded as string[] | undefined;
        let preview = parsed.sectionCount ? `${parsed.sectionCount} sections` : '';
        if (swipes && swipes.length > 0) {
          preview += `\n    Swipes loaded (${swipes.length}):\n` + swipes.map((s: string) => `    ${s}`).join('\n');
        }
        return preview;
      }
      case 'generate_draft': {
        const swipes = parsed.swipesLoaded as string[] | undefined;
        let preview = parsed.wordCount ? `${parsed.wordCount} words` : '';
        if (swipes && swipes.length > 0 && !preview.includes('Swipes')) {
          preview += `\n    Swipes loaded (${swipes.length}):\n` + swipes.map((s: string) => `    ${s}`).join('\n');
        }
        return preview;
      }
      case 'generate_hooks':
        return parsed.hookVariants ? `${parsed.hookVariants.length} variants` : '';
      case 'revise_draft':
        return parsed.wordCount ? `${parsed.wordCount} words` : '';
      case 'score_draft':
        return parsed.overallConfidence ? `Score: ${parsed.overallConfidence}/100` : '';
      case 'get_client_profile':
        return parsed.name || '';
      case 'search_swipes':
      case 'search_ideas':
      case 'get_tasks':
        return parsed.count !== undefined ? `${parsed.count} results` : '';
      case 'learn_from_url':
      case 'learn_from_text':
        return parsed.rulesLearned ? `${parsed.rulesLearned.length} rules` : '';
      default:
        return parsed.message?.substring(0, 60) || '';
    }
  } catch {
    return '';
  }
}

function estimateCost(model: string, usage: { inputTokens: number; outputTokens: number; cachedTokens?: number }): number {
  // Rough cost estimates per 1M tokens
  const costs: Record<string, { input: number; output: number }> = {
    'anthropic/claude-opus-4-1': { input: 15, output: 75 },
    'anthropic/claude-sonnet-4-5': { input: 3, output: 15 },
    'anthropic/claude-haiku-4-5': { input: 0.8, output: 4 },
  };

  const modelCosts = costs[model] || { input: 3, output: 15 };
  const inputCost = (usage.inputTokens / 1_000_000) * modelCosts.input;
  const outputCost = (usage.outputTokens / 1_000_000) * modelCosts.output;

  return Math.round((inputCost + outputCost) * 10000) / 10000;
}
