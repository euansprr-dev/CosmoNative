// CosmoOS/Agent/Core/AgentToolRegistry.swift
// Tool definitions for the Cosmo Agent — 25 tools across 7 groups

import Foundation

@MainActor
class AgentToolRegistry {
    static let shared = AgentToolRegistry()

    // All available tools
    private(set) var allTools: [LLMToolDefinition] = []

    private init() {
        registerAllTools()
    }

    // MARK: - Intent-Based Tool Selection

    /// Return relevant tools for a given intent
    func toolsForIntent(_ intent: AgentIntent) -> [LLMToolDefinition] {
        switch intent {
        case .capture:
            return ideaTools + swipeTools + plannerumTools
        case .brainstorm:
            return ideaTools + swipeTools
        case .plan:
            return plannerumTools + contentTools
        case .query:
            return allTools
        case .execute:
            return contentTools + plannerumTools + questTools
        case .debrief, .reflect:
            return analyticsTools + questTools
        case .correct:
            return ideaTools + contentTools + plannerumTools
        case .meta:
            return preferenceTools
        }
    }

    // MARK: - Tool Groups

    private var ideaTools: [LLMToolDefinition] {
        [
            LLMToolDefinition(
                name: "search_ideas",
                description: "Search ideas in the knowledge graph by keyword or semantic similarity.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "Search query text"] as [String: Any],
                        "limit": ["type": "integer", "description": "Max results (default 10)"] as [String: Any]
                    ] as [String: Any],
                    "required": ["query"]
                ]
            ),
            LLMToolDefinition(
                name: "get_idea",
                description: "Get full details of a specific idea by its UUID.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "uuid": ["type": "string", "description": "The idea atom UUID"] as [String: Any]
                    ] as [String: Any],
                    "required": ["uuid"]
                ]
            ),
            LLMToolDefinition(
                name: "create_idea",
                description: "Create a new idea in the knowledge graph.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string", "description": "Idea title"] as [String: Any],
                        "body": ["type": "string", "description": "Idea description or body text"] as [String: Any]
                    ] as [String: Any],
                    "required": ["title"]
                ]
            ),
            LLMToolDefinition(
                name: "update_idea",
                description: "Update an existing idea's title, body, or status.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "uuid": ["type": "string", "description": "The idea atom UUID"] as [String: Any],
                        "title": ["type": "string", "description": "New title"] as [String: Any],
                        "body": ["type": "string", "description": "New body text"] as [String: Any],
                        "status": ["type": "string", "description": "New status (spark, developing, validated, activated, published, archived)"] as [String: Any]
                    ] as [String: Any],
                    "required": ["uuid"]
                ]
            ),
            LLMToolDefinition(
                name: "activate_idea",
                description: "Activate an idea to promote it into the content pipeline. Creates a content atom linked to the idea.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "uuid": ["type": "string", "description": "The idea atom UUID to activate"] as [String: Any]
                    ] as [String: Any],
                    "required": ["uuid"]
                ]
            ),
        ]
    }

    private var swipeTools: [LLMToolDefinition] {
        [
            LLMToolDefinition(
                name: "search_swipes",
                description: "Search the swipe file library by keyword or topic.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "Search query text"] as [String: Any],
                        "limit": ["type": "integer", "description": "Max results (default 10)"] as [String: Any]
                    ] as [String: Any],
                    "required": ["query"]
                ]
            ),
            LLMToolDefinition(
                name: "get_swipe_analysis",
                description: "Get the full analysis of a swipe file (hook, framework, persuasion, emotional arc).",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "uuid": ["type": "string", "description": "The swipe file atom UUID"] as [String: Any]
                    ] as [String: Any],
                    "required": ["uuid"]
                ]
            ),
            LLMToolDefinition(
                name: "find_similar_swipes",
                description: "Find swipe files similar to a given swipe or query using semantic search.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "Text or topic to find similar swipes for"] as [String: Any],
                        "limit": ["type": "integer", "description": "Max results (default 5)"] as [String: Any]
                    ] as [String: Any],
                    "required": ["query"]
                ]
            ),
            LLMToolDefinition(
                name: "get_swipe_stats",
                description: "Get aggregate statistics about the swipe file library (total count, top hooks, top frameworks).",
                parametersSchema: [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ]
            ),
        ]
    }

    private var contentTools: [LLMToolDefinition] {
        [
            LLMToolDefinition(
                name: "get_content_pipeline",
                description: "Get all content pieces grouped by pipeline phase (ideation, draft, polish, scheduled, published, analyzing, archived).",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "phase": ["type": "string", "description": "Optional: filter to a specific phase"] as [String: Any]
                    ] as [String: Any],
                    "required": [] as [String]
                ]
            ),
            LLMToolDefinition(
                name: "advance_pipeline_phase",
                description: "Advance a content piece to the next pipeline phase.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "uuid": ["type": "string", "description": "The content atom UUID"] as [String: Any],
                        "notes": ["type": "string", "description": "Optional transition notes"] as [String: Any]
                    ] as [String: Any],
                    "required": ["uuid"]
                ]
            ),
            LLMToolDefinition(
                name: "create_content",
                description: "Create a new content piece in the pipeline.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string", "description": "Content title"] as [String: Any],
                        "body": ["type": "string", "description": "Initial draft body text"] as [String: Any],
                        "platform": ["type": "string", "description": "Target platform (e.g. twitter, instagram, youtube, newsletter, linkedin, tiktok, blog)"] as [String: Any]
                    ] as [String: Any],
                    "required": ["title"]
                ]
            ),
            LLMToolDefinition(
                name: "get_content",
                description: "Get full details of a specific content piece by UUID.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "uuid": ["type": "string", "description": "The content atom UUID"] as [String: Any]
                    ] as [String: Any],
                    "required": ["uuid"]
                ]
            ),
            LLMToolDefinition(
                name: "create_thinkspace",
                description: "Create a new Thinkspace (saved canvas configuration) with a title.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string", "description": "Thinkspace name"] as [String: Any]
                    ] as [String: Any],
                    "required": ["title"]
                ]
            ),
        ]
    }

    private var plannerumTools: [LLMToolDefinition] {
        [
            LLMToolDefinition(
                name: "get_calendar_blocks",
                description: "Get schedule blocks for a specific date. Returns time blocks with start/end times, titles, and completion status.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "date": ["type": "string", "description": "ISO8601 date string (e.g. 2026-02-15). Defaults to today."] as [String: Any]
                    ] as [String: Any],
                    "required": [] as [String]
                ]
            ),
            LLMToolDefinition(
                name: "create_block",
                description: "Create a new schedule block (time block) on the calendar.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string", "description": "Block title"] as [String: Any],
                        "startTime": ["type": "string", "description": "ISO8601 start time"] as [String: Any],
                        "endTime": ["type": "string", "description": "ISO8601 end time"] as [String: Any],
                        "intent": ["type": "string", "description": "Task intent (write, research, plan, design, admin, learn, health)"] as [String: Any]
                    ] as [String: Any],
                    "required": ["title", "startTime", "endTime"]
                ]
            ),
            LLMToolDefinition(
                name: "update_block",
                description: "Update an existing schedule block's title, time, or intent.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "uuid": ["type": "string", "description": "The schedule block atom UUID"] as [String: Any],
                        "title": ["type": "string", "description": "New title"] as [String: Any],
                        "startTime": ["type": "string", "description": "New ISO8601 start time"] as [String: Any],
                        "endTime": ["type": "string", "description": "New ISO8601 end time"] as [String: Any]
                    ] as [String: Any],
                    "required": ["uuid"]
                ]
            ),
            LLMToolDefinition(
                name: "delete_block",
                description: "Delete a schedule block. Requires confirmation.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "uuid": ["type": "string", "description": "The schedule block atom UUID to delete"] as [String: Any]
                    ] as [String: Any],
                    "required": ["uuid"]
                ]
            ),
            LLMToolDefinition(
                name: "complete_block",
                description: "Mark a schedule block as completed, awarding XP.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "uuid": ["type": "string", "description": "The schedule block atom UUID to complete"] as [String: Any]
                    ] as [String: Any],
                    "required": ["uuid"]
                ]
            ),
            LLMToolDefinition(
                name: "get_unscheduled_tasks",
                description: "Get all tasks that are not yet scheduled on the calendar.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "limit": ["type": "integer", "description": "Max results (default 20)"] as [String: Any]
                    ] as [String: Any],
                    "required": [] as [String]
                ]
            ),
            LLMToolDefinition(
                name: "create_task",
                description: "Create a new task.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string", "description": "Task title"] as [String: Any],
                        "body": ["type": "string", "description": "Task description"] as [String: Any],
                        "priority": ["type": "string", "description": "Priority level (low, medium, high)"] as [String: Any],
                        "intent": ["type": "string", "description": "Task intent (write, research, plan, design, admin, learn, health)"] as [String: Any],
                        "dueDate": ["type": "string", "description": "Due date in ISO8601 format"] as [String: Any]
                    ] as [String: Any],
                    "required": ["title"]
                ]
            ),
        ]
    }

    private var analyticsTools: [LLMToolDefinition] {
        [
            LLMToolDefinition(
                name: "get_dimension_xp",
                description: "Get XP totals and levels for Sanctuary dimensions (cognitive, creative, physiological, behavioral, knowledge, reflection).",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "dimension": ["type": "string", "description": "Optional: specific dimension to query. Omit for all."] as [String: Any]
                    ] as [String: Any],
                    "required": [] as [String]
                ]
            ),
            LLMToolDefinition(
                name: "get_streak_data",
                description: "Get the user's current streaks (consecutive days of activity) across dimensions.",
                parametersSchema: [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ]
            ),
        ]
    }

    private var questTools: [LLMToolDefinition] {
        [
            LLMToolDefinition(
                name: "get_quest_status",
                description: "Get the status of all daily quests including progress, completion, and streaks.",
                parametersSchema: [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ]
            ),
            LLMToolDefinition(
                name: "complete_quest",
                description: "Manually complete a quest that allows manual completion (e.g. Heart Health).",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "questId": ["type": "string", "description": "The quest ID to complete (e.g. 'heartHealth')"] as [String: Any]
                    ] as [String: Any],
                    "required": ["questId"]
                ]
            ),
        ]
    }

    private var preferenceTools: [LLMToolDefinition] {
        [
            LLMToolDefinition(
                name: "get_preferences",
                description: "Get the user's stored preferences and learned patterns.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "scope": ["type": "string", "description": "Filter by scope: global, client, taskType. Omit for all."] as [String: Any]
                    ] as [String: Any],
                    "required": [] as [String]
                ]
            ),
            LLMToolDefinition(
                name: "store_preference",
                description: "Store a user preference or learned pattern. Use this when the user says 'remember that...' or expresses a consistent preference.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "key": ["type": "string", "description": "Preference key (e.g. 'preferred_hook_style', 'default_content_format')"] as [String: Any],
                        "value": ["type": "string", "description": "The preference value"] as [String: Any],
                        "scope": ["type": "string", "description": "Scope: global (default), client, taskType"] as [String: Any],
                        "scopeQualifier": ["type": "string", "description": "Client UUID or task type for scoped preferences"] as [String: Any]
                    ] as [String: Any],
                    "required": ["key", "value"]
                ]
            ),
            LLMToolDefinition(
                name: "delete_preference",
                description: "Delete a stored preference.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "key": ["type": "string", "description": "The preference key to delete"] as [String: Any]
                    ] as [String: Any],
                    "required": ["key"]
                ]
            ),
        ]
    }

    // MARK: - Registration

    private func registerAllTools() {
        allTools = ideaTools + swipeTools + contentTools + plannerumTools + analyticsTools + questTools + preferenceTools
    }
}
