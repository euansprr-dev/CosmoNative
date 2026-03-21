// cosmo-cloud-agent/src/agent/service.ts
// Main agent orchestrator — ported from CosmoAgentService.swift
// PORTING SOURCE: CosmoAgentService.swift lines 300-700
//
// Flow: classify intent → assemble context → tool loop → response

import { config } from '../config';
import { classifyIntent, modelTierForIntent, maxToolIterations, AgentIntent, ModelTier } from './intentClassifier';
import { assembleSystemPrompt } from './contextAssembler';
import { executeTool, jsonEncode } from './toolExecutor';
import { loadConversation, saveConversation, logApiUsage } from '../db/queries';
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

/**
 * Process a user message through the full agent pipeline.
 * Source: CosmoAgentService.processMessage() in Swift
 */
export async function processMessage(
  text: string,
  chatId: string,
): Promise<ProcessResult> {
  // 1. Classify intent
  const intent = classifyIntent(text);
  const tier = modelTierForIntent(intent);
  const model = config.models[tier];
  const iterationLimit = maxToolIterations(intent);

  console.log(`🧠 Intent: ${intent} | Model: ${model} | Max iterations: ${iterationLimit}`);

  // 2. Load or create conversation
  const existingConv = await loadConversation(chatId);
  const messages: AgentMessage[] = existingConv?.messages || [];

  // 3. Assemble system prompt
  const systemPrompt = await assembleSystemPrompt(intent, chatId);

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

    // Call LLM
    const llmResponse = await callLLM({
      model,
      systemPrompt: `${systemPrompt.cached}\n\n${systemPrompt.dynamic}`,
      messages,
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

      const result = await executeTool(toolCall.name, toolCall.arguments);

      // Track created atoms
      try {
        const parsed = JSON.parse(result);
        if (parsed.uuid) createdAtomUUIDs.push(parsed.uuid);
        if (parsed.ideaUUID) createdAtomUUIDs.push(parsed.ideaUUID);
        if (parsed.contentUUID) createdAtomUUIDs.push(parsed.contentUUID);
        if (parsed.swipeUUID) createdAtomUUIDs.push(parsed.swipeUUID);
      } catch {}

      messages.push({
        role: 'tool',
        content: result,
        tool_call_id: toolCall.id,
      });
    }

    // Compress old tool results (keep last 2 intact, compress older)
    compressOldToolResults(messages);
  }

  // 7. Save conversation
  await saveConversation(chatId, messages.slice(-30), {
    linkedAtomUUIDs: createdAtomUUIDs,
  });

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

  // Build OpenAI-compatible messages
  const apiMessages: any[] = [
    { role: 'system', content: params.systemPrompt },
    ...params.messages.map(m => {
      if (m.role === 'tool') {
        return { role: 'tool', content: m.content, tool_call_id: m.tool_call_id };
      }
      if (m.tool_calls) {
        return { role: 'assistant', content: m.content || null, tool_calls: m.tool_calls };
      }
      return { role: m.role, content: m.content };
    }),
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

function compressOldToolResults(messages: AgentMessage[]): void {
  // Keep last 2 tool results intact, compress older ones
  let toolResultCount = 0;
  for (let i = messages.length - 1; i >= 0; i--) {
    if (messages[i].role === 'tool') {
      toolResultCount++;
      if (toolResultCount > 2) {
        // Compress: extract just the key info
        try {
          const content = messages[i].content as string;
          const parsed = JSON.parse(content);
          const compressed: Record<string, any> = { compressed: true };
          if (parsed.success !== undefined) compressed.success = parsed.success;
          if (parsed.count !== undefined) compressed.count = parsed.count;
          if (parsed.uuid) compressed.uuid = parsed.uuid;
          if (parsed.title) compressed.title = parsed.title;
          if (parsed.message) compressed.message = parsed.message;
          messages[i].content = JSON.stringify(compressed);
        } catch {
          // Leave as-is if not JSON
        }
      }
    }
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
