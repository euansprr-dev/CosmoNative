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

  // Analyze persuasion techniques present in the text
  const allResearch = await fetchAllByType('research', { limit: 500 });
  const swipes = allResearch.filter(isSwipeFileAtom);

  return jsonEncode({
    textLength: text.length,
    wordCount: text.split(/\s+/).length,
    swipeLibrarySize: swipes.length,
    message: 'Persuasion review: analyze the draft against your swipe library patterns using search_swipes and get_swipe_analysis for specific comparisons.',
  });
}

// ============================================================
// 9. suggest_persuasion_stack
// PORTING CHECKLIST: AgentToolExecutor.swift (PersuasionCoachEngine)
// ✅ topic required, platform required
// ✅ Return: persuasion technique recommendations
// ============================================================

export async function suggestPersuasionStack(args: Record<string, any>): Promise<string> {
  const topic = args.topic as string;
  const platform = args.platform as string;
  if (!topic || !platform) return jsonError('topic and platform are required');

  // Aggregate persuasion techniques from swipe library
  const allResearch = await fetchAllByType('research', { limit: 500 });
  const swipes = allResearch.filter(isSwipeFileAtom);

  const techniqueCounts: Record<string, number> = {};
  for (const s of swipes) {
    const analysis = s.structured?.swipeAnalysis || s.structured;
    const persuasion = (analysis?.persuasionTypes as any[]) || [];
    for (const p of persuasion) {
      const name = typeof p === 'string' ? p : p.type || p.name || '';
      if (name) techniqueCounts[name] = (techniqueCounts[name] || 0) + 1;
    }
  }

  const topTechniques = Object.entries(techniqueCounts)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([technique, count]) => ({ technique, frequency: count }));

  return jsonEncode({
    topic,
    platform,
    suggestedStack: topTechniques,
    totalSwipesAnalyzed: swipes.length,
    message: `Top persuasion techniques from your ${swipes.length}-swipe library for ${platform} content about "${topic}".`,
  });
}

// ============================================================
// 10. compare_to_swipe
// PORTING CHECKLIST: AgentToolExecutor.swift (PersuasionCoachEngine)
// ✅ text required, swipeUUID required
// ✅ Compare draft text structure against a reference swipe
// ✅ Return: comparison analysis
// ============================================================

export async function compareToSwipe(args: Record<string, any>): Promise<string> {
  const text = args.text as string;
  const swipeUUID = args.swipeUUID as string;
  if (!text || !swipeUUID) return jsonError('text and swipeUUID are required');

  const { fetchAtom } = await import('../db/queries');
  const swipe = await fetchAtom(swipeUUID);
  if (!swipe) return jsonError(`Swipe not found: ${swipeUUID}`);

  const swipeBody = swipe.body || '';
  const analysis = swipe.structured?.swipeAnalysis || swipe.structured || {};

  const draftWords = text.split(/\s+/).length;
  const swipeWords = swipeBody.split(/\s+/).length;
  const draftSentences = text.split(/[.!?]+/).filter(Boolean).length;
  const swipeSentences = swipeBody.split(/[.!?]+/).filter(Boolean).length;

  return jsonEncode({
    comparison: {
      draftWordCount: draftWords,
      swipeWordCount: swipeWords,
      draftSentenceCount: draftSentences,
      swipeSentenceCount: swipeSentences,
      swipeHookType: analysis.hookType || null,
      swipeFramework: analysis.frameworkType || null,
      swipeBeatPattern: analysis.beatFingerprint || null,
      lengthRatio: swipeWords > 0 ? Math.round((draftWords / swipeWords) * 100) / 100 : 0,
    },
    swipeTitle: swipe.title,
    message: `Draft (${draftWords} words) compared to "${swipe.title}" (${swipeWords} words). Length ratio: ${swipeWords > 0 ? (draftWords / swipeWords * 100).toFixed(0) : 0}%.`,
  });
}

// ============================================================
// 11. suggest_module_addition
// PORTING CHECKLIST: AgentToolExecutor.swift line 3352
// ✅ action required (add_to_module | create_module)
// ✅ content, reason required; moduleId or newModuleTitle/newModuleId conditional
// ✅ In Swift, queues as PendingModuleSuggestion for user confirmation via Telegram buttons
// ✅ Cloud version: stores the suggestion as a lesson directly (no confirmation UI)
// ============================================================

export async function suggestModuleAddition(args: Record<string, any>): Promise<string> {
  const action = args.action as string;
  const content = args.content as string;
  const reason = args.reason as string;
  if (!action || !content || !reason) return jsonError('action, content, and reason are required');

  const { createAtom } = await import('../db/queries');

  if (action === 'add_to_module') {
    const moduleId = args.moduleId as string;
    if (!moduleId) return jsonError('moduleId is required for add_to_module');

    // Store as a lesson targeting the specific module
    await createAtom({
      type: 'agent_learning',
      title: content.substring(0, 80),
      body: content,
      metadata: {
        subtype: 'lesson',
        lessonType: 'module_suggestion',
        category: 'general',
        targetModuleId: moduleId,
        reason,
        source: 'agent_suggestion',
        enforcement: 'advisory',
        confidence: 0.8,
      },
    });

    return jsonEncode({
      success: true,
      module: moduleId,
      message: `Module suggestion saved: content will be added to "${moduleId}" module.`,
    });
  }

  if (action === 'create_module') {
    const newModuleTitle = args.newModuleTitle as string;
    const newModuleId = args.newModuleId as string;
    if (!newModuleTitle || !newModuleId) return jsonError('newModuleTitle and newModuleId required for create_module');

    await createAtom({
      type: 'agent_learning',
      title: content.substring(0, 80),
      body: content,
      metadata: {
        subtype: 'lesson',
        lessonType: 'new_module_suggestion',
        category: 'general',
        newModuleId,
        newModuleTitle,
        reason,
        source: 'agent_suggestion',
        enforcement: 'advisory',
        confidence: 0.8,
      },
    });

    return jsonEncode({
      success: true,
      module: newModuleTitle,
      message: `New module suggestion saved: "${newModuleTitle}" (${newModuleId}).`,
    });
  }

  return jsonError(`Unknown action: ${action}. Use "add_to_module" or "create_module".`);
}
