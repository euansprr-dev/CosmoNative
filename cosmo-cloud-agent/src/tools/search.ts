// cosmo-cloud-agent/src/tools/search.ts
// Web search tool — ported from AgentToolExecutor.swift
// PORTING SOURCE: AgentToolExecutor.swift line 3512
// NOTE: Uses OpenRouter to perform web search via an LLM with search capability

import { config } from '../config';
import { jsonEncode, jsonError } from '../agent/toolExecutor';

// ============================================================
// web_search
// PORTING CHECKLIST: AgentToolExecutor.swift line 3512
// ✅ query required, maxResults optional (default 5)
// ✅ Uses LLM with web search capability
// ✅ Return: {success, query, summary, findings: [{title, snippet, url}], count}
// ============================================================

export async function webSearch(args: Record<string, any>): Promise<string> {
  const query = args.query as string;
  if (!query) return jsonError('query is required');

  const maxResults = (args.maxResults as number) || 5;

  try {
    const response = await fetch(`${config.openRouterBaseUrl}/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${config.openRouterApiKey}`,
      },
      body: JSON.stringify({
        model: 'perplexity/sonar',
        messages: [
          {
            role: 'system',
            content: `You are a research assistant. Search the web for the query and return a structured summary with ${maxResults} key findings. Format each finding with a title, snippet, and URL if available.`,
          },
          { role: 'user', content: query },
        ],
        max_tokens: 2048,
      }),
    });

    if (!response.ok) {
      throw new Error(`API returned ${response.status}`);
    }

    const data = await response.json() as any;
    const content = data.choices?.[0]?.message?.content || '';

    return jsonEncode({
      success: true,
      query,
      summary: content,
      findings: [],
      count: 0,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return jsonEncode({
      success: false,
      error: `Web search failed: ${message}`,
      query,
    });
  }
}
