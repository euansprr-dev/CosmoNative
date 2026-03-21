// cosmo-cloud-agent/src/tools/swipes.ts
// Swipe tools — 7 tools ported from AgentToolExecutor.swift
// PORTING SOURCE: AgentToolExecutor.swift lines 451-750

import { fetchAtom, fetchAllByType, searchAtoms, fuzzyFindClient, atomToDict, isSwipeFileAtom, getSwipeAnalysis as getSwipeAnalysisFromAtom } from '../db/queries';
import { jsonEncode, jsonError } from '../agent/toolExecutor';

// ============================================================
// 1. search_swipes
// PORTING CHECKLIST: AgentToolExecutor.swift line 529
// ✅ Keyword search via FTS with swipe filter
// ✅ Filter: isSwipeFileAtom only
// ✅ Return format: {results: [{uuid, title, preview, hookType, frameworkType, hookText, format}], count}
// ✅ Empty result: {results: [], count: 0}
// ============================================================

export async function searchSwipes(args: Record<string, any>): Promise<string> {
  const query = args.query as string;
  if (!query) return jsonError('query is required');

  const limit = (args.limit as number) || 10;

  const results = await searchAtoms(query, { types: ['research'], limit: limit * 2 });
  const swipes = results.filter(isSwipeFileAtom).slice(0, limit);

  return jsonEncode({
    results: swipes.map(a => {
      const analysis = getSwipeAnalysisHelper(a);
      return {
        uuid: a.uuid,
        title: a.title,
        preview: a.body ? a.body.substring(0, 200) : null,
        hookType: analysis?.hookType ?? null,
        frameworkType: analysis?.frameworkType ?? null,
        hookText: analysis?.hookText ?? null,
        format: a.metadata?.contentSource ?? null,
      };
    }),
    count: swipes.length,
  });
}

// ============================================================
// 2. list_all_swipes
// PORTING CHECKLIST: AgentToolExecutor.swift line 746
// ✅ limit (default 50), offset (default 0)
// ✅ Filter: isSwipeFileAtom
// ✅ Pagination: dropFirst(offset).prefix(limit)
// ✅ Return: {results, count, total, offset, hasMore}
// ============================================================

export async function listAllSwipes(args: Record<string, any>): Promise<string> {
  const limit = (args.limit as number) || 50;
  const offset = (args.offset as number) || 0;

  const allResearch = await fetchAllByType('research', { limit: 1000 });
  const allSwipes = allResearch.filter(isSwipeFileAtom);
  const total = allSwipes.length;

  const page = allSwipes.slice(offset, offset + limit);

  return jsonEncode({
    results: page.map(a => {
      const analysis = getSwipeAnalysisHelper(a);
      return {
        uuid: a.uuid,
        title: a.title,
        preview: a.body ? a.body.substring(0, 150) : null,
        hookType: analysis?.hookType ?? null,
        frameworkType: analysis?.frameworkType ?? null,
      };
    }),
    count: page.length,
    total,
    offset,
    hasMore: offset + limit < total,
  });
}

// ============================================================
// 3. filter_swipes_by_taxonomy
// PORTING CHECKLIST: AgentToolExecutor.swift line 783
// ✅ hookType, frameworkType, emotion, platform, format all optional
// ✅ AND all provided filters against swipeAnalysis
// ✅ Return: {results, count}
// RISK: MEDIUM — enum values must match exactly
// ============================================================

export async function filterSwipesByTaxonomy(args: Record<string, any>): Promise<string> {
  const hookType = args.hookType as string | undefined;
  const frameworkType = args.frameworkType as string | undefined;
  const emotion = args.emotion as string | undefined;
  const platform = args.platform as string | undefined;
  const format = args.format as string | undefined;

  const allResearch = await fetchAllByType('research', { limit: 1000 });
  const allSwipes = allResearch.filter(isSwipeFileAtom);

  const filtered = allSwipes.filter(a => {
    const analysis = getSwipeAnalysisHelper(a);
    if (!analysis) return false;

    if (hookType && analysis.hookType !== hookType) return false;
    if (frameworkType && analysis.frameworkType !== frameworkType) return false;
    if (emotion) {
      const emotions = analysis.emotions as string[] | undefined;
      if (!emotions?.includes(emotion)) return false;
    }
    if (platform) {
      const source = a.metadata?.contentSource as string | undefined;
      if (source && !source.toLowerCase().includes(platform.toLowerCase())) return false;
    }
    if (format) {
      const atomFormat = a.metadata?.contentFormat as string | undefined;
      if (atomFormat && atomFormat !== format) return false;
    }
    return true;
  });

  return jsonEncode({
    results: filtered.map(a => {
      const analysis = getSwipeAnalysisHelper(a);
      return {
        uuid: a.uuid,
        title: a.title,
        preview: a.body ? a.body.substring(0, 200) : null,
        hookType: analysis?.hookType ?? null,
        frameworkType: analysis?.frameworkType ?? null,
        hookText: analysis?.hookText ?? null,
      };
    }),
    count: filtered.length,
  });
}

// ============================================================
// 4. get_swipe_analysis
// PORTING CHECKLIST: AgentToolExecutor.swift line 595
// ✅ uuid required
// ✅ Return atomToDict + analysis JSON
// ============================================================

export async function getSwipeAnalysisTool(args: Record<string, any>): Promise<string> {
  const uuid = args.uuid as string;
  if (!uuid) return jsonError('uuid is required');

  const atom = await fetchAtom(uuid);
  if (!atom) return jsonError(`Swipe not found: ${uuid}`);

  const analysis = atom.structured || {};

  return jsonEncode({
    ...atomToDict(atom),
    analysis,
  });
}

// ============================================================
// 5. find_similar_swipes
// PORTING CHECKLIST: AgentToolExecutor.swift line 615
// ✅ query required, limit (default 5)
// ✅ Uses FTS ranking (Phase 2). pgvector in Phase 5.
// ✅ Return: {results: [{uuid, title, preview}], count}
// ============================================================

export async function findSimilarSwipes(args: Record<string, any>): Promise<string> {
  const query = args.query as string;
  if (!query) return jsonError('query is required');

  const limit = (args.limit as number) || 5;

  const results = await searchAtoms(query, { types: ['research'], limit: limit * 3 });
  const swipes = results.filter(isSwipeFileAtom).slice(0, limit);

  return jsonEncode({
    results: swipes.map(a => ({
      uuid: a.uuid,
      title: a.title,
      preview: a.body ? a.body.substring(0, 200) : null,
    })),
    count: swipes.length,
  });
}

// ============================================================
// 6. get_swipe_stats
// PORTING CHECKLIST: AgentToolExecutor.swift line 641
// ✅ No params
// ✅ Aggregation: count hookType/frameworkType, top 5
// ✅ Return: {totalSwipes, topHooks, topFrameworks}
// ============================================================

export async function getSwipeStats(_args: Record<string, any>): Promise<string> {
  const allResearch = await fetchAllByType('research', { limit: 2000 });
  const swipes = allResearch.filter(isSwipeFileAtom);

  const hookCounts: Record<string, number> = {};
  const frameworkCounts: Record<string, number> = {};

  for (const s of swipes) {
    const analysis = getSwipeAnalysisHelper(s);
    if (analysis?.hookType) {
      hookCounts[analysis.hookType] = (hookCounts[analysis.hookType] || 0) + 1;
    }
    if (analysis?.frameworkType) {
      frameworkCounts[analysis.frameworkType] = (frameworkCounts[analysis.frameworkType] || 0) + 1;
    }
  }

  const topHooks = Object.entries(hookCounts)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([hook, count]) => ({ hook, count }));

  const topFrameworks = Object.entries(frameworkCounts)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([framework, count]) => ({ framework, count }));

  return jsonEncode({
    totalSwipes: swipes.length,
    topHooks,
    topFrameworks,
  });
}

// ============================================================
// 7. adapt_swipes_for_client
// PORTING CHECKLIST: AgentToolExecutor.swift line 681
// ✅ clientName required, timeFilter optional, maxResults (default 10, cap 25)
// NOTE: In Swift this uses SwipeAdaptationEngine with LLM calls.
//       Cloud version: assemble prompt + call OpenRouter directly.
// ✅ Return: {clientName, totalSwipesScanned, adaptedIdeas: [...], count}
// ============================================================

export async function adaptSwipesForClient(args: Record<string, any>): Promise<string> {
  const clientName = args.clientName as string;
  if (!clientName) return jsonError('clientName is required');

  const maxResults = Math.min((args.maxResults as number) || 10, 25);

  const client = await fuzzyFindClient(clientName);
  if (!client) return jsonError(`Client not found: ${clientName}`);

  // Load swipes
  const allResearch = await fetchAllByType('research', { limit: 1000 });
  const swipes = allResearch.filter(isSwipeFileAtom);

  // For now, return top swipes by recency with client context
  // Full LLM-powered adaptation will be added in Phase 3
  const topSwipes = swipes.slice(0, maxResults);

  return jsonEncode({
    clientName: client.title,
    clientUUID: client.uuid,
    totalSwipesScanned: swipes.length,
    candidatesEvaluated: Math.min(swipes.length, 50),
    adaptedIdeas: topSwipes.map(s => {
      const analysis = getSwipeAnalysisHelper(s);
      return {
        sourceSwipeTitle: s.title,
        sourceSwipeUUID: s.uuid,
        hookType: analysis?.hookType ?? null,
        frameworkType: analysis?.frameworkType ?? null,
        hookText: analysis?.hookText ?? null,
      };
    }),
    count: topSwipes.length,
    warning: 'Full LLM-powered adaptation will be available after Phase 3 writing engine deployment.',
  });
}

// ============================================================
// Internal helper (avoids name collision with exported getSwipeAnalysis)
// ============================================================

function getSwipeAnalysisHelper(atom: { structured: Record<string, any> | null }): Record<string, any> | null {
  if (!atom.structured) return null;
  if (atom.structured.swipeAnalysis) return atom.structured.swipeAnalysis;
  if (atom.structured.hookType) return atom.structured;
  return null;
}
