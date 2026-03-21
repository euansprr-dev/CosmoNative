// cosmo-cloud-agent/src/tools/intelligence.ts
// Intelligence & strategy tools — 8 tools ported from AgentToolExecutor.swift
// PORTING SOURCE: AgentToolExecutor.swift lines 2896-3130
// NOTE: Many of these are stubs in Swift. Cloud version returns same shape.
//       Full LLM-powered implementations will be added in Phase 3.

import { fetchAllByType, isSwipeFileAtom } from '../db/queries';
import { jsonEncode, jsonError } from '../agent/toolExecutor';

// ============================================================
// 1. get_weekly_content_plan
// ============================================================

export async function getWeeklyContentPlan(_args: Record<string, any>): Promise<string> {
  const content = await fetchAllByType('content', { limit: 50 });
  const ideas = await fetchAllByType('idea', { limit: 50 });

  const inPipeline = content.filter(a => {
    const phase = a.metadata?.phase as string;
    return phase && !['published', 'archived'].includes(phase);
  });

  return jsonEncode({
    activePipelineCount: inPipeline.length,
    readyIdeas: ideas.filter(a => a.metadata?.ideaStatus === 'spark').length,
    message: 'Weekly content plan based on current pipeline and ready ideas.',
    recommendation: `You have ${inPipeline.length} items in the pipeline and ${ideas.filter(a => a.metadata?.ideaStatus === 'spark').length} spark ideas ready to activate.`,
  });
}

// ============================================================
// 2. suggest_next_content
// ============================================================

export async function suggestNextContent(_args: Record<string, any>): Promise<string> {
  const ideas = await fetchAllByType('idea', { limit: 20 });
  const sparks = ideas.filter(a => a.metadata?.ideaStatus === 'spark');

  if (sparks.length === 0) {
    return jsonEncode({ message: 'No spark ideas available. Capture some swipes first.' });
  }

  // Suggest most recent spark idea
  const suggestion = sparks[0];

  return jsonEncode({
    suggestion: {
      uuid: suggestion.uuid,
      title: suggestion.title,
      status: suggestion.metadata?.ideaStatus,
      platform: suggestion.metadata?.platform ?? null,
    },
    totalSparks: sparks.length,
    message: `Suggested: "${suggestion.title}" — ${sparks.length} spark ideas available.`,
  });
}

// ============================================================
// 3. analyze_content_gap
// ============================================================

export async function analyzeContentGap(_args: Record<string, any>): Promise<string> {
  const allResearch = await fetchAllByType('research', { limit: 1000 });
  const swipes = allResearch.filter(isSwipeFileAtom);
  const content = await fetchAllByType('content', { limit: 200 });

  // Count hook types used in swipes vs content
  const swipeHooks: Record<string, number> = {};
  for (const s of swipes) {
    const hook = s.structured?.hookType || s.structured?.swipeAnalysis?.hookType;
    if (hook) swipeHooks[hook] = (swipeHooks[hook] || 0) + 1;
  }

  return jsonEncode({
    totalSwipes: swipes.length,
    totalContent: content.length,
    swipeHookDistribution: swipeHooks,
    message: `Analyzed ${swipes.length} swipes and ${content.length} content items.`,
  });
}

// ============================================================
// 4. predict_performance
// ============================================================

export async function predictPerformance(args: Record<string, any>): Promise<string> {
  return jsonEncode({
    message: 'Performance prediction requires historical engagement data. Connect your social platforms to enable this feature.',
    available: false,
  });
}

// ============================================================
// 5. get_swipe_study_plan
// ============================================================

export async function getSwipeStudyPlan(_args: Record<string, any>): Promise<string> {
  const allResearch = await fetchAllByType('research', { limit: 500 });
  const swipes = allResearch.filter(isSwipeFileAtom);

  // Find least-studied hook types
  const hookCounts: Record<string, number> = {};
  for (const s of swipes) {
    const hook = s.structured?.hookType || s.structured?.swipeAnalysis?.hookType;
    if (hook) hookCounts[hook] = (hookCounts[hook] || 0) + 1;
  }

  const underStudied = Object.entries(hookCounts)
    .sort((a, b) => a[1] - b[1])
    .slice(0, 3)
    .map(([hook, count]) => ({ hook, count }));

  return jsonEncode({
    totalSwipes: swipes.length,
    underStudiedHooks: underStudied,
    message: `Study plan: focus on ${underStudied.map(h => h.hook).join(', ')} hook types.`,
  });
}

// ============================================================
// 6. get_creator_profile
// ============================================================

export async function getCreatorProfile(_args: Record<string, any>): Promise<string> {
  return jsonEncode({
    message: 'Creator profile analysis requires the full TasteProfileBuilder engine. Use get_client_profile for client-specific profiles.',
  });
}

// ============================================================
// 7. get_audience_insights
// ============================================================

export async function getAudienceInsights(_args: Record<string, any>): Promise<string> {
  return jsonEncode({
    message: 'Audience insights require connected social platform data. Use the Connections settings to link your accounts.',
  });
}

// ============================================================
// 8. review_draft_persuasion
// ============================================================

export async function reviewDraftPersuasion(args: Record<string, any>): Promise<string> {
  const text = args.text as string;
  if (!text) return jsonError('text is required');

  return jsonEncode({
    message: 'Draft persuasion review will be available after Phase 3 writing engine deployment.',
    textLength: text.length,
    wordCount: text.split(/\s+/).length,
  });
}
