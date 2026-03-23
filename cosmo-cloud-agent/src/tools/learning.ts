// cosmo-cloud-agent/src/tools/learning.ts
// Tools for teaching the agent from URLs and pasted text.
// Creates agent_learning atoms with extracted rules.

import { createAtom, fuzzyFindClient } from '../db/queries';
import { jsonEncode, jsonError } from '../agent/toolExecutor';
import { config } from '../config';

// ============================================================
// learn_from_url
// ============================================================

export async function learnFromUrl(args: {
  url: string;
  context?: string;
  clientName?: string;
}): Promise<string> {
  if (!args.url) return jsonError('url is required');

  try {
    // 1. Fetch URL content and strip HTML tags
    const response = await fetch(args.url);
    if (!response.ok) {
      return jsonError(`Failed to fetch URL: ${response.status} ${response.statusText}`);
    }

    const html = await response.text();
    const text = html
      .replace(/<script[\s\S]*?<\/script>/gi, '')
      .replace(/<style[\s\S]*?<\/style>/gi, '')
      .replace(/<[^>]+>/g, ' ')
      .replace(/\s+/g, ' ')
      .trim()
      .substring(0, 8000); // Cap content length for LLM context

    if (text.length < 50) {
      return jsonError('Could not extract meaningful text from URL');
    }

    // 2. Resolve client if provided
    let clientUUID: string | null = null;
    if (args.clientName) {
      const client = await fuzzyFindClient(args.clientName);
      if (client) clientUUID = client.uuid;
    }

    // 3. Extract rules via Haiku
    const rules = await extractRulesFromContent(text, args.context);
    if (rules.length === 0) {
      return jsonEncode({ success: true, rulesLearned: [], message: 'No actionable rules found in content' });
    }

    // 4. Store each rule as an agent_learning atom
    const stored: Array<{ rule: string; category: string }> = [];
    for (const rule of rules.slice(0, 5)) {
      await createAtom({
        type: 'agent_learning',
        title: (rule.rule as string).substring(0, 80),
        body: `RULE: ${rule.rule}\nBAD: ${rule.bad_example || 'N/A'}\nGOOD: ${rule.good_example || 'N/A'}\nWHY: ${rule.why || 'N/A'}`,
        metadata: {
          subtype: 'lesson',
          lessonType: 'inferred_lesson',
          category: rule.category || 'general',
          confidence: 0.8,
          source: 'url_learning',
          sourceUrl: args.url,
          enforcement: 'hard',
          ...(clientUUID ? { clientUUID } : {}),
        },
      });
      stored.push({ rule: rule.rule, category: rule.category || 'general' });
    }

    return jsonEncode({
      success: true,
      rulesLearned: stored,
      message: `Learned ${stored.length} rule${stored.length !== 1 ? 's' : ''} from ${new URL(args.url).hostname}`,
    });
  } catch (error: any) {
    return jsonError(`learn_from_url failed: ${error.message || error}`);
  }
}

// ============================================================
// learn_from_text
// ============================================================

export async function learnFromText(args: {
  text: string;
  context?: string;
  clientName?: string;
}): Promise<string> {
  if (!args.text || args.text.trim().length < 10) {
    return jsonError('text is required (minimum 10 characters)');
  }

  try {
    // 1. Resolve client if provided
    let clientUUID: string | null = null;
    if (args.clientName) {
      const client = await fuzzyFindClient(args.clientName);
      if (client) clientUUID = client.uuid;
    }

    // 2. Extract rules via Haiku
    const content = args.text.substring(0, 8000);
    const rules = await extractRulesFromContent(content, args.context);
    if (rules.length === 0) {
      return jsonEncode({ success: true, rulesLearned: [], message: 'No actionable rules found in text' });
    }

    // 3. Store each rule as an agent_learning atom
    const stored: Array<{ rule: string; category: string }> = [];
    for (const rule of rules.slice(0, 5)) {
      await createAtom({
        type: 'agent_learning',
        title: (rule.rule as string).substring(0, 80),
        body: `RULE: ${rule.rule}\nBAD: ${rule.bad_example || 'N/A'}\nGOOD: ${rule.good_example || 'N/A'}\nWHY: ${rule.why || 'N/A'}`,
        metadata: {
          subtype: 'lesson',
          lessonType: 'inferred_lesson',
          category: rule.category || 'general',
          confidence: 0.8,
          source: 'text_learning',
          enforcement: 'hard',
          ...(clientUUID ? { clientUUID } : {}),
        },
      });
      stored.push({ rule: rule.rule, category: rule.category || 'general' });
    }

    return jsonEncode({
      success: true,
      rulesLearned: stored,
      message: `Learned ${stored.length} rule${stored.length !== 1 ? 's' : ''} from pasted text`,
    });
  } catch (error: any) {
    return jsonError(`learn_from_text failed: ${error.message || error}`);
  }
}

// ============================================================
// Shared: Extract rules from content via Haiku
// ============================================================

interface ExtractedRule {
  rule: string;
  bad_example?: string;
  good_example?: string;
  why?: string;
  category?: string;
}

async function extractRulesFromContent(content: string, context?: string): Promise<ExtractedRule[]> {
  const response = await fetch(`${config.openRouterBaseUrl}/chat/completions`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${config.openRouterApiKey}`,
    },
    body: JSON.stringify({
      model: config.models.sensor,
      messages: [
        {
          role: 'system',
          content: 'Extract 2-3 specific, actionable writing rules from this content. The user wants to learn from it. Format each as JSON: {"rule", "bad_example", "good_example", "why", "category"}. Categories: hook_style, voice, structure, format, cta, general. Return a JSON array ONLY, no other text.',
        },
        {
          role: 'user',
          content: `Content:\n${content}\n\nUser context: ${context || 'Learn from this content'}`,
        },
      ],
      max_tokens: 1024,
      temperature: 0,
    }),
  });

  const data = await response.json() as any;
  const raw = data.choices?.[0]?.message?.content || '[]';

  // Parse JSON array from response (may be wrapped in markdown fences)
  const match = raw.match(/\[[\s\S]*\]/);
  if (!match) return [];

  try {
    const parsed = JSON.parse(match[0]);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter((r: any) => r && typeof r.rule === 'string' && r.rule.length > 0);
  } catch {
    return [];
  }
}
