// cosmo-cloud-agent/src/tools/insights.ts
// Insight memory tools — 2 tools ported from AgentToolExecutor.swift
// PORTING SOURCE: AgentToolExecutor.swift lines 3229-3350

import { fetchAllByType, createAtom } from '../db/queries';
import { jsonEncode, jsonError } from '../agent/toolExecutor';

// ============================================================
// 1. save_analysis
// PORTING CHECKLIST: AgentToolExecutor.swift line 3229
// ✅ title, content required; clientName, tags optional
// ✅ Creates agent_learning atom with subtype=agent_analysis
// ✅ Return: {success, uuid, title, message}
// ============================================================

export async function saveAnalysis(args: Record<string, any>): Promise<string> {
  const title = args.title as string;
  const content = args.content as string;
  if (!title || !content) return jsonError('title and content are required');

  const tags = args.tags as string[] | undefined;
  const clientName = args.clientName as string | undefined;

  const atom = await createAtom({
    type: 'agent_learning',
    title,
    body: content,
    structured: {
      savedAt: new Date().toISOString(),
      tags: tags ?? [],
      clientName: clientName ?? null,
    },
    metadata: {
      subtype: 'agent_analysis',
      tags: tags ?? [],
      clientName: clientName ?? null,
    },
  });

  if (!atom) return jsonError('Failed to save analysis');

  return jsonEncode({
    success: true,
    uuid: atom.uuid,
    title,
    message: `Analysis saved: "${title}"`,
  });
}

// ============================================================
// 2. get_saved_analyses
// PORTING CHECKLIST: AgentToolExecutor.swift line 3296
// ✅ clientName, tags, limit optional
// ✅ Filter: subtype=agent_analysis, optional client/tag match
// ✅ Return: {success, count, analyses: [{uuid, title, content (first 500), tags, clientName, createdAt}]}
// ============================================================

export async function getSavedAnalyses(args: Record<string, any>): Promise<string> {
  const clientName = args.clientName as string | undefined;
  const tags = args.tags as string[] | undefined;
  const limit = (args.limit as number) || 10;

  const all = await fetchAllByType('agent_learning');

  let analyses = all.filter(a => a.metadata?.subtype === 'agent_analysis');

  if (clientName) {
    analyses = analyses.filter(a =>
      a.metadata?.clientName === clientName || a.structured?.clientName === clientName
    );
  }

  if (tags && tags.length > 0) {
    analyses = analyses.filter(a => {
      const atomTags = (a.metadata?.tags || a.structured?.tags || []) as string[];
      return tags.some(t => atomTags.includes(t));
    });
  }

  const limited = analyses.slice(0, limit);

  return jsonEncode({
    success: true,
    count: limited.length,
    analyses: limited.map(a => ({
      uuid: a.uuid,
      title: a.title,
      content: a.body ? a.body.substring(0, 500) : null,
      tags: a.metadata?.tags ?? a.structured?.tags ?? [],
      clientName: a.metadata?.clientName ?? a.structured?.clientName ?? null,
      createdAt: a.created_at,
    })),
  });
}
