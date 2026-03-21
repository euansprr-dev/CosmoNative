// cosmo-cloud-agent/src/agent/toolExecutor.ts
// Central tool dispatcher — routes tool names to handler functions
// PORTING SOURCE: AgentToolExecutor.swift execute() method (line 140)
//
// CRITICAL: Every tool must return the EXACT same JSON structure as the Swift version.
// The LLM's behavior depends on the shape of tool results.

import * as ideas from '../tools/ideas';
import * as swipes from '../tools/swipes';
import * as content from '../tools/content';
import * as capture from '../tools/capture';
import * as calendar from '../tools/calendar';
import * as analytics from '../tools/analytics';
import * as preferences from '../tools/preferences';
import * as clients from '../tools/clients';
import * as lessons from '../tools/lessons';
import * as standing from '../tools/standing';
import * as insights from '../tools/insights';
import * as beats from '../tools/beats';
import * as intelligence from '../tools/intelligence';
import * as writing from '../tools/writing';
import * as search from '../tools/search';
import * as tasks from '../tools/tasks';
import * as projects from '../tools/projects';

export type ToolResult = string; // JSON-encoded string, matching Swift jsonEncode()

/**
 * Execute a tool by name with given arguments.
 * Source: AgentToolExecutor.execute(_:_:) in Swift (line 140)
 *
 * Returns a JSON-encoded string result, matching the Swift tool result format.
 */
export async function executeTool(
  toolName: string,
  args: Record<string, any>
): Promise<ToolResult> {
  try {
    switch (toolName) {
      // === IDEAS ===
      case 'search_ideas':
        return await ideas.searchIdeas(args);
      case 'get_idea':
        return await ideas.getIdea(args);
      case 'create_idea':
        return await ideas.createIdea(args);
      case 'update_idea':
        return await ideas.updateIdea(args);
      case 'activate_idea':
        return await ideas.activateIdea(args);

      // === SWIPES ===
      case 'search_swipes':
        return await swipes.searchSwipes(args);
      case 'list_all_swipes':
        return await swipes.listAllSwipes(args);
      case 'filter_swipes_by_taxonomy':
        return await swipes.filterSwipesByTaxonomy(args);
      case 'get_swipe_analysis':
        return await swipes.getSwipeAnalysisTool(args);
      case 'find_similar_swipes':
        return await swipes.findSimilarSwipes(args);
      case 'get_swipe_stats':
        return await swipes.getSwipeStats(args);
      case 'adapt_swipes_for_client':
        return await swipes.adaptSwipesForClient(args);

      // === CONTENT ===
      case 'get_content_pipeline':
        return await content.getContentPipeline(args);
      case 'advance_pipeline_phase':
        return await content.advancePipelinePhase(args);
      case 'create_content':
        return await content.createContent(args);
      case 'get_content':
        return await content.getContent(args);
      case 'update_content':
        return await content.updateContent(args);
      case 'create_thinkspace':
        return await content.createThinkspace(args);

      // === CAPTURE ===
      case 'capture_swipe':
        return await capture.captureSwipe(args);
      case 'capture_swipe_with_idea':
        return await capture.captureSwipeWithIdea(args);
      case 'capture_research':
        return await capture.captureResearch(args);

      // === CALENDAR / TASKS ===
      case 'get_calendar_blocks':
        return await calendar.getCalendarBlocks(args);
      case 'create_block':
        return await calendar.createBlock(args);
      case 'update_block':
        return await calendar.updateBlock(args);
      case 'delete_block':
        return await calendar.deleteBlock(args);
      case 'complete_block':
        return await calendar.completeBlock(args);
      case 'get_unscheduled_tasks':
        return await tasks.getTasks({ ...args, list: 'anytime' }); // Backward compat alias
      case 'create_task':
        return await tasks.smartTaskCreate(args); // Backward compat alias

      // === ENHANCED TASKS (Phase 4) ===
      case 'smart_task_create':
        return await tasks.smartTaskCreate(args);
      case 'get_tasks':
        return await tasks.getTasks(args);
      case 'complete_task':
        return await tasks.completeTask(args);
      case 'uncomplete_task':
        return await tasks.uncompleteTask(args);
      case 'reschedule_task':
        return await tasks.rescheduleTask(args);
      case 'update_task':
        return await tasks.updateTask(args);
      case 'set_task_recurrence':
        return await tasks.setTaskRecurrence(args);
      case 'get_recurring_tasks':
        return await tasks.getRecurringTasks(args);

      // === PROJECTS ===
      case 'get_projects':
        return await projects.getProjects(args);
      case 'get_project_tasks':
        return await projects.getProjectTasks(args);
      case 'create_project':
        return await projects.createProject(args);
      case 'move_task_to_project':
        return await projects.moveTaskToProject(args);

      // === ANALYTICS ===
      case 'get_dimension_xp':
        return await analytics.getDimensionXp(args);
      case 'get_streak_data':
        return await analytics.getStreakData(args);

      // === PREFERENCES ===
      case 'get_preferences':
        return await preferences.getPreferences(args);
      case 'store_preference':
        return await preferences.storePreference(args);
      case 'delete_preference':
        return await preferences.deletePreference(args);

      // === CLIENT PROFILES ===
      case 'list_client_profiles':
        return await clients.listClientProfiles(args);
      case 'get_client_profile':
        return await clients.getClientProfile(args);
      case 'search_by_client':
        return await clients.searchByClient(args);
      case 'update_client_memory':
        return await clients.updateClientMemory(args);
      case 'list_client_memory':
        return await clients.listClientMemory(args);

      // === LESSONS ===
      case 'save_lessons':
        return await lessons.saveLessons(args);
      case 'get_lessons':
        return await lessons.getLessons(args);
      case 'update_skill':
        return await lessons.updateSkill(args);
      case 'delete_skill':
        return await lessons.deleteSkill(args);

      // === STANDING INSTRUCTIONS ===
      case 'add_standing_instruction':
        return await standing.addStandingInstruction(args);
      case 'list_standing_instructions':
        return await standing.listStandingInstructions(args);
      case 'remove_standing_instruction':
        return await standing.removeStandingInstruction(args);
      case 'update_standing_instruction':
        return await standing.updateStandingInstruction(args);
      case 'get_instruction_history':
        return await standing.getInstructionHistory(args);

      // === INSIGHT MEMORY ===
      case 'save_analysis':
        return await insights.saveAnalysis(args);
      case 'get_saved_analyses':
        return await insights.getSavedAnalyses(args);

      // === BEAT PATTERNS ===
      case 'get_beat_patterns':
        return await beats.getBeatPatterns(args);

      // === INTELLIGENCE ===
      case 'get_creator_profile':
        return await intelligence.getCreatorProfile(args);
      case 'get_audience_insights':
        return await intelligence.getAudienceInsights(args);
      case 'review_draft_persuasion':
        return await intelligence.reviewDraftPersuasion(args);
      case 'suggest_persuasion_stack':
        return await intelligence.suggestPersuasionStack(args);
      case 'compare_to_swipe':
        return await intelligence.compareToSwipe(args);
      case 'suggest_module_addition':
        return await intelligence.suggestModuleAddition(args);
      case 'get_weekly_content_plan':
        return await intelligence.getWeeklyContentPlan(args);
      case 'suggest_next_content':
        return await intelligence.suggestNextContent(args);
      case 'analyze_content_gap':
        return await intelligence.analyzeContentGap(args);
      case 'predict_performance':
        return await intelligence.predictPerformance(args);
      case 'get_swipe_study_plan':
        return await intelligence.getSwipeStudyPlan(args);

      // === WRITING ===
      case 'generate_outline':
        return await writing.generateOutline(args);
      case 'generate_draft':
        return await writing.generateDraft(args);
      case 'read_draft':
        return await writing.readDraft(args);
      case 'revise_draft':
        return await writing.reviseDraft(args);
      case 'generate_hooks':
        return await writing.generateHooks(args);
      case 'score_draft':
        return await writing.scoreDraft(args);

      // === WEB SEARCH ===
      case 'web_search':
        return await search.webSearch(args);

      // === TELEGRAM UX ===
      case 'send_telegram_buttons':
        return jsonEncode({ success: false, error: 'send_telegram_buttons handled at bridge level' });
      case 'send_action_buttons':
        return jsonEncode({ success: false, error: 'send_action_buttons not available in cloud mode' });

      default:
        return jsonError(`Unknown tool: ${toolName}`);
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`❌ Tool execution failed (${toolName}): ${message}`);
    return jsonError(`Tool '${toolName}' failed: ${message}`);
  }
}

// ============================================================
// JSON Helpers (matching Swift jsonEncode/jsonError)
// ============================================================

export function jsonEncode(obj: Record<string, any>): string {
  try {
    return JSON.stringify(obj);
  } catch {
    return JSON.stringify({ error: 'Failed to encode result' });
  }
}

export function jsonError(message: string): string {
  return JSON.stringify({ error: message });
}
