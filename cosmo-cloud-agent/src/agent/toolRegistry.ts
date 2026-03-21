// cosmo-cloud-agent/src/agent/toolRegistry.ts
// Tool definitions with parameter schemas — ported from AgentToolRegistry.swift
// PORTING SOURCE: AgentToolRegistry.swift (1,063 lines)
//
// Returns tool definitions in OpenAI function calling format.
// Intent-based filtering matches Swift's toolsForIntent() exactly.

import { AgentIntent } from './intentClassifier';

interface ToolDefinition {
  name: string;
  description: string;
  parameters: Record<string, any>;
}

// All tool definitions
const ALL_TOOLS: ToolDefinition[] = [
  // === IDEAS ===
  { name: 'search_ideas', description: 'Search ideas by keyword', parameters: { type: 'object', properties: { query: { type: 'string', description: 'Search query' }, limit: { type: 'integer', description: 'Max results (default 10)' } }, required: ['query'] } },
  { name: 'get_idea', description: 'Get full idea details by UUID', parameters: { type: 'object', properties: { uuid: { type: 'string' } }, required: ['uuid'] } },
  { name: 'create_idea', description: 'Create a new idea', parameters: { type: 'object', properties: { title: { type: 'string' }, body: { type: 'string' }, clientName: { type: 'string', description: 'Client to associate this idea with' } }, required: ['title'] } },
  { name: 'update_idea', description: 'Update an idea', parameters: { type: 'object', properties: { uuid: { type: 'string' }, title: { type: 'string' }, body: { type: 'string' }, status: { type: 'string', enum: ['spark', 'developing', 'ready', 'activated', 'parked', 'archived'] } }, required: ['uuid'] } },
  { name: 'activate_idea', description: 'Promote idea to content pipeline', parameters: { type: 'object', properties: { uuid: { type: 'string' } }, required: ['uuid'] } },

  // === SWIPES ===
  { name: 'search_swipes', description: 'Search swipe files by keyword', parameters: { type: 'object', properties: { query: { type: 'string' }, limit: { type: 'integer' } }, required: ['query'] } },
  { name: 'list_all_swipes', description: 'List all swipes with pagination', parameters: { type: 'object', properties: { limit: { type: 'integer' }, offset: { type: 'integer' } } } },
  { name: 'filter_swipes_by_taxonomy', description: 'Filter swipes by hook type, framework, emotion, platform, or format', parameters: { type: 'object', properties: { hookType: { type: 'string', enum: ['story', 'curiosityGap', 'statistic', 'contrast', 'howTo', 'controversy', 'challenge', 'question', 'quotation', 'metaphor', 'promise', 'authority', 'painPoint', 'transformation'] }, frameworkType: { type: 'string', enum: ['storyLoop', 'listicle', 'tutorial', 'beforeAfter', 'mythBusting', 'caseStudy', 'dayInLife', 'PAS', 'AIDA', 'escalationArc', 'problemSolution', 'comparison'] }, emotion: { type: 'string' }, platform: { type: 'string' }, format: { type: 'string' } } } },
  { name: 'get_swipe_analysis', description: 'Get full analysis of a swipe file', parameters: { type: 'object', properties: { uuid: { type: 'string' } }, required: ['uuid'] } },
  { name: 'find_similar_swipes', description: 'Find structurally similar swipes', parameters: { type: 'object', properties: { query: { type: 'string' }, limit: { type: 'integer' } }, required: ['query'] } },
  { name: 'get_swipe_stats', description: 'Get aggregate swipe library statistics', parameters: { type: 'object', properties: {} } },
  { name: 'adapt_swipes_for_client', description: 'Analyze swipe library and generate adapted content ideas for a specific client', parameters: { type: 'object', properties: { clientName: { type: 'string' }, timeFilter: { type: 'string' }, maxResults: { type: 'integer' } }, required: ['clientName'] } },

  // === CONTENT ===
  { name: 'get_content_pipeline', description: 'List content grouped by pipeline phase', parameters: { type: 'object', properties: { phase: { type: 'string', enum: ['ideation', 'brainstorm', 'draft', 'polish', 'scheduled', 'published', 'analyzing', 'archived'] } } } },
  { name: 'advance_pipeline_phase', description: 'Move content to next pipeline phase', parameters: { type: 'object', properties: { uuid: { type: 'string' }, notes: { type: 'string' } }, required: ['uuid'] } },
  { name: 'create_content', description: 'Create new content atom', parameters: { type: 'object', properties: { title: { type: 'string' }, body: { type: 'string' }, platform: { type: 'string' }, clientName: { type: 'string' }, sourceIdeaUUID: { type: 'string' }, description: { type: 'string' }, framework: { type: 'string' }, hooks: { type: 'array', items: { type: 'string' } }, swipeUUIDs: { type: 'array', items: { type: 'string' } } }, required: ['title'] } },
  { name: 'get_content', description: 'Get content details by UUID', parameters: { type: 'object', properties: { uuid: { type: 'string' } }, required: ['uuid'] } },
  { name: 'update_content', description: 'Update content atom', parameters: { type: 'object', properties: { uuid: { type: 'string' }, title: { type: 'string' }, body: { type: 'string' }, platform: { type: 'string' }, clientName: { type: 'string' }, description: { type: 'string' }, framework: { type: 'string' }, hooks: { type: 'array', items: { type: 'string' } }, outline: { type: 'array', items: { type: 'string' } } }, required: ['uuid'] } },
  { name: 'create_thinkspace', description: 'Create a new canvas thinkspace', parameters: { type: 'object', properties: { title: { type: 'string' } }, required: ['title'] } },

  // === CAPTURE ===
  { name: 'capture_swipe', description: 'Capture a URL as a swipe file', parameters: { type: 'object', properties: { url: { type: 'string' }, hook: { type: 'string' }, notes: { type: 'string' }, clientName: { type: 'string' } }, required: ['url'] } },
  { name: 'capture_swipe_with_idea', description: 'Capture URL as swipe and create linked idea', parameters: { type: 'object', properties: { url: { type: 'string' }, ideaContext: { type: 'string' }, clientName: { type: 'string' }, hook: { type: 'string' }, title: { type: 'string' } }, required: ['url'] } },
  { name: 'capture_research', description: 'Capture a research note or URL', parameters: { type: 'object', properties: { title: { type: 'string' }, url: { type: 'string' }, body: { type: 'string' } }, required: ['title'] } },

  // === CALENDAR / TASKS ===
  { name: 'get_calendar_blocks', description: 'Get schedule blocks for a date', parameters: { type: 'object', properties: { date: { type: 'string', description: 'ISO8601 date or yyyy-MM-dd' } } } },
  { name: 'create_block', description: 'Create a time block', parameters: { type: 'object', properties: { title: { type: 'string' }, startTime: { type: 'string' }, endTime: { type: 'string' }, intent: { type: 'string', enum: ['write', 'research', 'plan', 'design', 'admin', 'learn', 'health'] } }, required: ['title', 'startTime', 'endTime'] } },
  { name: 'update_block', description: 'Update a time block', parameters: { type: 'object', properties: { uuid: { type: 'string' }, title: { type: 'string' }, startTime: { type: 'string' }, endTime: { type: 'string' } }, required: ['uuid'] } },
  { name: 'delete_block', description: 'Delete a time block', parameters: { type: 'object', properties: { uuid: { type: 'string' } }, required: ['uuid'] } },
  { name: 'complete_block', description: 'Mark a block as completed', parameters: { type: 'object', properties: { uuid: { type: 'string' } }, required: ['uuid'] } },
  { name: 'get_unscheduled_tasks', description: 'Get tasks without a scheduled time', parameters: { type: 'object', properties: { limit: { type: 'integer' } } } },
  { name: 'create_task', description: 'Create a new task', parameters: { type: 'object', properties: { title: { type: 'string' }, body: { type: 'string' }, priority: { type: 'string', enum: ['low', 'medium', 'high', 'urgent'] }, intent: { type: 'string' }, dueDate: { type: 'string' } }, required: ['title'] } },

  // === ANALYTICS ===
  { name: 'get_dimension_xp', description: 'Get XP totals and levels', parameters: { type: 'object', properties: {} } },
  { name: 'get_streak_data', description: 'Get consecutive day streaks', parameters: { type: 'object', properties: {} } },

  // === PREFERENCES ===
  { name: 'get_preferences', description: 'Get stored preferences', parameters: { type: 'object', properties: { scope: { type: 'string', enum: ['global', 'client', 'taskType'] } } } },
  { name: 'store_preference', description: 'Store a preference', parameters: { type: 'object', properties: { key: { type: 'string' }, value: { type: 'string' }, scope: { type: 'string' }, scopeQualifier: { type: 'string' } }, required: ['key', 'value'] } },
  { name: 'delete_preference', description: 'Delete a preference', parameters: { type: 'object', properties: { key: { type: 'string' } }, required: ['key'] } },

  // === CLIENT PROFILES ===
  { name: 'list_client_profiles', description: 'List all client profiles', parameters: { type: 'object', properties: {} } },
  { name: 'get_client_profile', description: 'Get full client profile (fuzzy matched)', parameters: { type: 'object', properties: { client_name: { type: 'string' } }, required: ['client_name'] } },
  { name: 'search_by_client', description: 'Search ideas/swipes/content for a specific client', parameters: { type: 'object', properties: { clientName: { type: 'string' }, entityType: { type: 'string', enum: ['idea', 'swipe', 'content'] } }, required: ['clientName'] } },
  { name: 'update_client_memory', description: 'Store a learned fact about a client', parameters: { type: 'object', properties: { client_name: { type: 'string' }, field: { type: 'string' }, value: { type: 'string' } }, required: ['client_name', 'field', 'value'] } },
  { name: 'list_client_memory', description: 'List stored facts about a client', parameters: { type: 'object', properties: { client_name: { type: 'string' } }, required: ['client_name'] } },

  // === LESSONS ===
  { name: 'save_lessons', description: 'Save learned writing rules', parameters: { type: 'object', properties: { lessons: { type: 'array', items: { type: 'object', properties: { rule: { type: 'string' }, category: { type: 'string' }, evidence: { type: 'string' }, intent: { type: 'string' }, targetModule: { type: 'string' } }, required: ['rule', 'category'] } }, clientName: { type: 'string' } }, required: ['lessons'] } },
  { name: 'get_lessons', description: 'Get saved lessons', parameters: { type: 'object', properties: { clientName: { type: 'string' }, category: { type: 'string' }, intent: { type: 'string' } } } },
  { name: 'update_skill', description: 'Update a lesson', parameters: { type: 'object', properties: { lessonId: { type: 'string' }, rule: { type: 'string' }, category: { type: 'string' }, intent: { type: 'string' } }, required: ['lessonId'] } },
  { name: 'delete_skill', description: 'Delete a lesson', parameters: { type: 'object', properties: { lessonId: { type: 'string' } }, required: ['lessonId'] } },

  // === STANDING INSTRUCTIONS ===
  { name: 'add_standing_instruction', description: 'Add a recurring instruction', parameters: { type: 'object', properties: { body: { type: 'string' }, schedule: { type: 'string', enum: ['daily', 'weekday', 'weekly', 'specific_days', 'interval', 'monthly'] }, hour: { type: 'integer' }, minute: { type: 'integer' }, days: { type: 'array', items: { type: 'integer' } }, intervalMinutes: { type: 'integer' }, dayOfMonth: { type: 'integer' } }, required: ['body'] } },
  { name: 'list_standing_instructions', description: 'List all standing instructions', parameters: { type: 'object', properties: {} } },
  { name: 'remove_standing_instruction', description: 'Remove a standing instruction', parameters: { type: 'object', properties: { uuid: { type: 'string' } }, required: ['uuid'] } },
  { name: 'update_standing_instruction', description: 'Update a standing instruction', parameters: { type: 'object', properties: { uuid: { type: 'string' }, body: { type: 'string' }, schedule: { type: 'string' }, hour: { type: 'integer' }, minute: { type: 'integer' }, enabled: { type: 'boolean' } }, required: ['uuid'] } },
  { name: 'get_instruction_history', description: 'Get execution history for a standing instruction', parameters: { type: 'object', properties: { uuid: { type: 'string' } }, required: ['uuid'] } },

  // === WRITING ===
  { name: 'generate_outline', description: 'Generate a content outline', parameters: { type: 'object', properties: { contentUUID: { type: 'string' }, notes: { type: 'string' }, clientName: { type: 'string' }, blueprintSwipeUUID: { type: 'string' }, contentFormat: { type: 'string', enum: ['reel', 'carousel', 'thread', 'post'] } }, required: ['contentUUID'] } },
  { name: 'generate_draft', description: 'Write a full draft', parameters: { type: 'object', properties: { contentUUID: { type: 'string' }, clientName: { type: 'string' }, userDirection: { type: 'string' }, contentFormat: { type: 'string' } }, required: ['contentUUID'] } },
  { name: 'read_draft', description: 'Read the current draft', parameters: { type: 'object', properties: { contentUUID: { type: 'string' } }, required: ['contentUUID'] } },
  { name: 'revise_draft', description: 'Revise a draft with feedback', parameters: { type: 'object', properties: { contentUUID: { type: 'string' }, feedback: { type: 'string' }, currentDraft: { type: 'string' }, clientName: { type: 'string' } }, required: ['contentUUID', 'feedback'] } },
  { name: 'generate_hooks', description: 'Generate hook variants', parameters: { type: 'object', properties: { contentUUID: { type: 'string' }, count: { type: 'integer' }, clientName: { type: 'string' } }, required: ['contentUUID'] } },
  { name: 'score_draft', description: 'Score a draft on 6 dimensions', parameters: { type: 'object', properties: { contentUUID: { type: 'string' } }, required: ['contentUUID'] } },

  // === SCORING / BEATS ===
  { name: 'get_beat_patterns', description: 'Get top beat patterns from swipe library', parameters: { type: 'object', properties: { format: { type: 'string' }, niche: { type: 'string' }, limit: { type: 'integer' } } } },

  // === INSIGHT MEMORY ===
  { name: 'save_analysis', description: 'Save a deep pattern analysis', parameters: { type: 'object', properties: { title: { type: 'string' }, content: { type: 'string' }, clientName: { type: 'string' }, tags: { type: 'array', items: { type: 'string' } } }, required: ['title', 'content'] } },
  { name: 'get_saved_analyses', description: 'Get saved analyses', parameters: { type: 'object', properties: { clientName: { type: 'string' }, tags: { type: 'array', items: { type: 'string' } }, limit: { type: 'integer' } } } },

  // === WEB SEARCH ===
  { name: 'web_search', description: 'Search the web for current information', parameters: { type: 'object', properties: { query: { type: 'string' }, maxResults: { type: 'integer' } }, required: ['query'] } },

  // === TELEGRAM UX ===
  { name: 'send_telegram_buttons', description: 'Send inline buttons to Telegram', parameters: { type: 'object', properties: { message: { type: 'string' }, buttons: { type: 'array', items: { type: 'object', properties: { label: { type: 'string' }, action: { type: 'string' } } } } }, required: ['message', 'buttons'] } },
];

// Tool groups for intent-based filtering
const TOOL_GROUPS: Record<string, string[]> = {
  idea: ['search_ideas', 'get_idea', 'create_idea', 'update_idea', 'activate_idea'],
  swipe: ['search_swipes', 'list_all_swipes', 'filter_swipes_by_taxonomy', 'get_swipe_analysis', 'find_similar_swipes', 'get_swipe_stats', 'adapt_swipes_for_client'],
  content: ['get_content_pipeline', 'advance_pipeline_phase', 'create_content', 'get_content', 'update_content', 'create_thinkspace'],
  capture: ['capture_swipe', 'capture_swipe_with_idea', 'capture_research'],
  schedule: ['get_calendar_blocks', 'create_block', 'update_block', 'delete_block', 'complete_block', 'get_unscheduled_tasks', 'create_task'],
  analytics: ['get_dimension_xp', 'get_streak_data'],
  preference: ['get_preferences', 'store_preference', 'delete_preference'],
  client: ['search_by_client', 'update_client_memory', 'list_client_memory'],
  clientProfile: ['list_client_profiles', 'get_client_profile'],
  lesson: ['save_lessons', 'get_lessons', 'update_skill', 'delete_skill'],
  standing: ['add_standing_instruction', 'list_standing_instructions', 'remove_standing_instruction', 'update_standing_instruction', 'get_instruction_history'],
  writing: ['generate_outline', 'generate_draft', 'read_draft', 'revise_draft', 'generate_hooks', 'update_content'],
  scoring: ['get_beat_patterns', 'score_draft'],
  intelligence: ['get_weekly_content_plan', 'suggest_next_content', 'analyze_content_gap', 'predict_performance', 'get_swipe_study_plan', 'get_creator_profile', 'get_audience_insights', 'review_draft_persuasion'],
  insightMemory: ['save_analysis', 'get_saved_analyses'],
  webSearch: ['web_search'],
  ux: ['send_telegram_buttons'],
};

// Intent → tool groups mapping (matches Swift toolsForIntent exactly)
const INTENT_TOOL_GROUPS: Record<AgentIntent, string[]> = {
  capture: ['idea', 'swipe', 'capture', 'schedule', 'client', 'clientProfile', 'lesson'],
  brainstorm: ['idea', 'swipe', 'capture', 'client', 'clientProfile', 'intelligence', 'writing', 'preference', 'scoring', 'lesson', 'webSearch'],
  plan: ['schedule', 'content', 'intelligence', 'clientProfile', 'lesson'],
  query: Object.keys(TOOL_GROUPS), // All tools
  correct: ['idea', 'content', 'schedule', 'client', 'clientProfile'],
  execute: ['content', 'schedule', 'writing', 'clientProfile', 'ux', 'lesson'],
  debrief: ['analytics', 'lesson'],
  reflect: ['analytics', 'lesson'],
  meta: ['preference', 'standing', 'client', 'lesson', 'ux'],
  strategy: ['intelligence', 'swipe', 'content', 'analytics', 'writing', 'clientProfile', 'client', 'insightMemory', 'ux', 'lesson', 'webSearch'],
  draft: ['content', 'swipe', 'idea', 'intelligence', 'writing', 'clientProfile', 'client', 'preference', 'capture', 'scoring', 'insightMemory', 'lesson', 'ux', 'webSearch'],
  analyze: ['intelligence', 'swipe', 'analytics', 'content', 'clientProfile', 'insightMemory', 'lesson', 'webSearch'],
};

/**
 * Get tool definitions for a given intent.
 * Source: AgentToolRegistry.toolsForIntent() in Swift
 */
export function getToolDefinitions(intent: AgentIntent): ToolDefinition[] {
  const groups = INTENT_TOOL_GROUPS[intent] || INTENT_TOOL_GROUPS.query;
  const allowedNames = new Set(groups.flatMap(g => TOOL_GROUPS[g] || []));
  return ALL_TOOLS.filter(t => allowedNames.has(t.name));
}
