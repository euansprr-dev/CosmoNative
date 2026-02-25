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

    // MARK: - Tool Groups

    private var clientTools: [LLMToolDefinition] {
        [
            LLMToolDefinition(
                name: "search_by_client",
                description: "Search for ideas, swipes, or content tagged for a specific client. Use this when the user asks about items 'for [client name]'.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "clientName": ["type": "string", "description": "The client name to search for (e.g. 'Ben', 'Michael')"] as [String: Any],
                        "entityType": ["type": "string", "description": "Optional: filter to 'idea', 'swipe', or 'content'. Omit for all types."] as [String: Any]
                    ] as [String: Any],
                    "required": ["clientName"]
                ]
            ),
        ]
    }

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
                description: "Search the swipe file library by keyword, topic, hook text, or transcript content. Searches across title, body, hook, framework names, and transcript. For filtering by specific hook type or framework enum, use filter_swipes_by_taxonomy instead.",
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
                name: "list_all_swipes",
                description: "List all swipe files with their analysis summary. Use this to browse the full swipe library when search returns empty results, or when the user asks 'what swipes do I have'. Returns hookText, hookType, frameworkType, emotion, and platform for each swipe.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "limit": ["type": "integer", "description": "Max results per page (default 50)"] as [String: Any],
                        "offset": ["type": "integer", "description": "Pagination offset (default 0)"] as [String: Any]
                    ] as [String: Any],
                    "required": [] as [String]
                ]
            ),
            LLMToolDefinition(
                name: "filter_swipes_by_taxonomy",
                description: "Filter swipes by analysis categories. Use when the user asks for swipes with a specific hook type, framework, emotion, or content format. hookType values: story, curiosityGap, statistic, contrast, howTo, controversy, challenge, question, quotation, metaphor, promise, authority, painPoint, transformation. frameworkType values: storyLoop, listicle, tutorial, beforeAfter, mythBusting, caseStudy, dayInLife, PAS, AIDA, escalationArc, problemSolution, comparison. emotion values: curiosity, urgency, empathy, humor, fear, inspiration, surprise, anger, nostalgia, excitement. format values: reel, voiceoverReel, oneSliderReel, multiSliderReel, twoStepCTA, carousel, tweet, thread, longForm, youtube, newsletter, post.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "hookType": ["type": "string", "description": "Hook type to filter by (e.g. 'story', 'curiosityGap', 'statistic')"] as [String: Any],
                        "frameworkType": ["type": "string", "description": "Framework type to filter by (e.g. 'storyLoop', 'PAS', 'AIDA')"] as [String: Any],
                        "emotion": ["type": "string", "description": "Dominant emotion to filter by (e.g. 'curiosity', 'urgency')"] as [String: Any],
                        "platform": ["type": "string", "description": "Source platform to filter by (e.g. 'youtube', 'instagram', 'x')"] as [String: Any],
                        "format": ["type": "string", "description": "Content format filter (e.g. 'reel', 'carousel', 'thread', 'voiceoverReel', 'tweet')"] as [String: Any]
                    ] as [String: Any],
                    "required": [] as [String]
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
                description: "Create a new content piece in the pipeline with full metadata. Supports client linking, source idea inheritance, framework/hook/swipe context.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string", "description": "Content title"] as [String: Any],
                        "body": ["type": "string", "description": "Initial draft body text"] as [String: Any],
                        "platform": ["type": "string", "description": "Target platform (twitter, instagram, youtube, linkedin, tiktok, threads, substack, medium)"] as [String: Any],
                        "clientName": ["type": "string", "description": "Client name to associate (fuzzy-matched to client profile)"] as [String: Any],
                        "sourceIdeaUUID": ["type": "string", "description": "UUID of the source idea atom to link"] as [String: Any],
                        "description": ["type": "string", "description": "Description text — the creative seed for this content piece"] as [String: Any],
                        "framework": ["type": "string", "description": "Framework to use (e.g. AIDA, PAS, storyLoop, beforeAfter)"] as [String: Any],
                        "hooks": ["type": "array", "items": ["type": "string"] as [String: Any], "description": "Hook texts inherited from swipe analysis"] as [String: Any],
                        "swipeUUIDs": ["type": "array", "items": ["type": "string"] as [String: Any], "description": "UUIDs of matched swipe files for structural reference"] as [String: Any]
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

    private var captureTools: [LLMToolDefinition] {
        [
            LLMToolDefinition(
                name: "capture_swipe",
                description: "Capture a URL or raw text as a swipe file. Supports YouTube, Instagram, X/Twitter, Threads, and plain text. Fetches metadata, transcript (for YouTube), and auto-links to matching ideas.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "url": ["type": "string", "description": "The URL to capture (YouTube, Instagram, X, Threads, or any website). For raw text swipes, pass the text here."] as [String: Any],
                        "hook": ["type": "string", "description": "Optional user-provided hook or summary for the swipe"] as [String: Any],
                        "notes": ["type": "string", "description": "Optional notes about why this was captured"] as [String: Any],
                    "clientName": ["type": "string", "description": "Optional client name to tag this swipe for (e.g. 'Ben', 'Michael')"] as [String: Any]
                    ] as [String: Any],
                    "required": ["url"]
                ]
            ),
            LLMToolDefinition(
                name: "capture_swipe_with_idea",
                description: "Capture a URL as a swipe file AND create a linked idea from it. Use this when the user wants to capture a swipe AND create an idea in one step. Triggered by messages like 'Swipe this, great idea for Ben [URL]', 'capture this for Michael, we could do something similar about pricing [URL]', 'idea for a reel [URL]', or any message containing a URL plus idea-related language (idea, could do, similar, angle, topic, great for, inspiration, we should, let's try).",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "url": ["type": "string", "description": "The URL to capture (YouTube, Instagram, X, Threads, or any website)"] as [String: Any],
                        "ideaContext": ["type": "string", "description": "The user's context, angle, or reasoning for the idea (e.g. 'we could do something similar about pricing')"] as [String: Any],
                        "clientName": ["type": "string", "description": "Client name to assign the idea to (e.g. 'Ben', 'Michael')"] as [String: Any],
                        "hook": ["type": "string", "description": "Optional user-provided hook override for the swipe"] as [String: Any]
                    ] as [String: Any],
                    "required": ["url"]
                ]
            ),
            LLMToolDefinition(
                name: "capture_research",
                description: "Capture a URL, note, or reference material as a research atom (not a swipe file). Use this for general research capture, bookmarks, or reference notes.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string", "description": "Title for the research entry"] as [String: Any],
                        "url": ["type": "string", "description": "Optional URL to associate with this research"] as [String: Any],
                        "body": ["type": "string", "description": "Notes, content, or description for the research entry"] as [String: Any]
                    ] as [String: Any],
                    "required": ["title"]
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

    // MARK: - Standing Instructions Tools

    private var standingInstructionTools: [LLMToolDefinition] {
        [
            LLMToolDefinition(
                name: "add_standing_instruction",
                description: "Add a recurring standing instruction that executes automatically on a schedule. Supports schedule types: 'daily' (every day), 'weekday' (Mon-Fri), 'weekly' (specific weekday via day param, 1=Sun..7=Sat), 'specific_days' (specific weekdays via days array), 'interval' (every N minutes, min 30), 'monthly' (specific day of month via dayOfMonth).",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "body": ["type": "string", "description": "The instruction to execute (e.g. 'Give me 3 top hooks based on my swipe file')"] as [String: Any],
                        "schedule": ["type": "string", "description": "Schedule type: 'daily', 'weekday', 'weekly', 'specific_days', 'interval', or 'monthly'. Default: daily."] as [String: Any],
                        "hour": ["type": "integer", "description": "Hour to execute (0-23). Default: 9."] as [String: Any],
                        "minute": ["type": "integer", "description": "Minute to execute (0-59). Default: 0."] as [String: Any],
                        "days": ["type": "array", "items": ["type": "integer"] as [String: Any], "description": "Weekdays for 'specific_days' schedule (1=Sun, 2=Mon, ..., 7=Sat)"] as [String: Any],
                        "intervalMinutes": ["type": "integer", "description": "Minutes between executions for 'interval' schedule (minimum 30)"] as [String: Any],
                        "dayOfMonth": ["type": "integer", "description": "Day of month (1-31) for 'monthly' schedule"] as [String: Any]
                    ] as [String: Any],
                    "required": ["body"]
                ]
            ),
            LLMToolDefinition(
                name: "list_standing_instructions",
                description: "List all standing instructions with their schedule, enabled status, and last execution time.",
                parametersSchema: [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ]
            ),
            LLMToolDefinition(
                name: "remove_standing_instruction",
                description: "Remove a standing instruction by its UUID.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "uuid": ["type": "string", "description": "The UUID of the standing instruction to remove"] as [String: Any]
                    ] as [String: Any],
                    "required": ["uuid"]
                ]
            ),
            LLMToolDefinition(
                name: "update_standing_instruction",
                description: "Update an existing standing instruction's body, schedule, time, or enabled status.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "uuid": ["type": "string", "description": "The UUID of the standing instruction to update"] as [String: Any],
                        "body": ["type": "string", "description": "New instruction body text"] as [String: Any],
                        "schedule": ["type": "string", "description": "New schedule type: 'daily', 'weekday', 'weekly', 'specific_days', 'interval', or 'monthly'"] as [String: Any],
                        "hour": ["type": "integer", "description": "New hour (0-23)"] as [String: Any],
                        "minute": ["type": "integer", "description": "New minute (0-59)"] as [String: Any],
                        "enabled": ["type": "boolean", "description": "Enable or disable the instruction"] as [String: Any],
                        "days": ["type": "array", "items": ["type": "integer"] as [String: Any], "description": "Weekdays for 'specific_days' (1=Sun..7=Sat)"] as [String: Any],
                        "intervalMinutes": ["type": "integer", "description": "Minutes between executions for 'interval' (minimum 30)"] as [String: Any],
                        "dayOfMonth": ["type": "integer", "description": "Day of month for 'monthly' schedule"] as [String: Any]
                    ] as [String: Any],
                    "required": ["uuid"]
                ]
            ),
            LLMToolDefinition(
                name: "get_instruction_history",
                description: "Get the execution history of a standing instruction (last 10 executions with timestamps and result previews).",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "uuid": ["type": "string", "description": "The UUID of the standing instruction"] as [String: Any]
                    ] as [String: Any],
                    "required": ["uuid"]
                ]
            ),
        ]
    }

    // MARK: - Writing Tools (Opus Engine)

    private var scoringTools: [LLMToolDefinition] {
        [
            LLMToolDefinition(
                name: "get_beat_patterns",
                description: "Query the beat pattern library to find the most common structural patterns across swipe files. Returns fingerprint, beat sequence, frequency, and average hook score for each pattern. Use this to understand what content structures perform best.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "format": ["type": "string", "description": "Optional: filter by content format (e.g. 'reel', 'thread', 'carousel')"] as [String: Any],
                        "niche": ["type": "string", "description": "Optional: filter by niche"] as [String: Any],
                        "limit": ["type": "integer", "description": "Max results (default 5, max 20)"] as [String: Any]
                    ] as [String: Any],
                    "required": [] as [String]
                ]
            ),
            LLMToolDefinition(
                name: "score_draft",
                description: "Run the content scorecard engine on a draft to get 6-dimension scores (Hook, Copy, CTA, Voice Match, Structural Alignment, Slide Analysis) plus guided feedback and improvement suggestions. Requires a content atom UUID with a draft body.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "contentUUID": ["type": "string", "description": "UUID of the content atom to score"] as [String: Any]
                    ] as [String: Any],
                    "required": ["contentUUID"]
                ]
            ),
        ]
    }

    private var writingTools: [LLMToolDefinition] {
        [
            LLMToolDefinition(
                name: "generate_outline",
                description: """
                Generate a structured content outline using the unified writing engine. Assembles full client profile, swipe library intelligence, and beat pattern analysis to create a beat-mapped outline with hook variants. Requires a content atom UUID (create one first with create_content). ALWAYS pass clientName so the engine loads the correct client profile. \
                CRITICAL: When the user specifies a particular swipe to use as a blueprint, you MUST pass that swipe's UUID as blueprintSwipeUUID. This forces the engine to treat that swipe as the PRIMARY structural blueprint — emulating its hook type, beat pattern, and section structure rather than loosely drawing inspiration. \
                Always pass the user's creative direction in notes (e.g. 'emulate the hook structure exactly', 'use the comparison format'). \
                AFTER calling this tool, ALWAYS present the generated hook variants and outline section titles to the user so they can review before drafting.
                """,
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "contentUUID": ["type": "string", "description": "UUID of the content atom to generate an outline for"] as [String: Any],
                        "notes": ["type": "string", "description": "Creator direction for the outline. Include specific instructions like 'emulate the hook structure of the blueprint swipe', 'use the same comparison format', etc."] as [String: Any],
                        "clientName": ["type": "string", "description": "Client name for this content piece (e.g. 'Ben A'). Ensures the engine loads the correct client profile."] as [String: Any],
                        "blueprintSwipeUUID": ["type": "string", "description": "UUID of a specific swipe to use as the PRIMARY structural blueprint. When provided, the engine will emulate this swipe's hook type, beat pattern, and section structure rather than searching for matches."] as [String: Any],
                        "contentFormat": ["type": "string", "enum": ["reel", "carousel", "thread", "post"], "description": "Content format — reel (video script), carousel (slides), thread (tweets), post (single). MUST match what the user requested."] as [String: Any]
                    ] as [String: Any],
                    "required": ["contentUUID"]
                ]
            ),
            LLMToolDefinition(
                name: "generate_draft",
                description: "Generate a full draft for a content atom using the unified writing engine. Loads client profile, swipe intelligence, and beat patterns, then writes a draft following the outline beat-by-beat. Requires a content atom UUID with an outline (call generate_outline first). ALWAYS pass clientName. Pass userDirection to relay any specific creative instructions from the user. ALWAYS pass contentFormat to specify the format (reel, carousel, thread, post).",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "contentUUID": ["type": "string", "description": "UUID of the content atom to draft"] as [String: Any],
                        "clientName": ["type": "string", "description": "Client name for this content piece. Ensures the engine loads the correct client profile."] as [String: Any],
                        "userDirection": ["type": "string", "description": "The user's specific creative direction or instructions for this draft. Pass the user's exact words — e.g. 'make it punchy', 'focus on the transformation story', 'keep slides under 30 words'. This is prepended as a mandatory directive to the writing engine."] as [String: Any],
                        "contentFormat": ["type": "string", "enum": ["reel", "carousel", "thread", "post"], "description": "Content format — reel (video script), carousel (slides), thread (tweets), post (single). MUST match what the user requested."] as [String: Any]
                    ] as [String: Any],
                    "required": ["contentUUID"]
                ]
            ),
            LLMToolDefinition(
                name: "read_draft",
                description: "Read the full current draft for a content atom. Returns the complete formatted text (carousel slides, thread tweets, or plaintext) with title and word count. Use this to see the FULL draft before revising — never rely on truncated previews from other tools.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "contentUUID": ["type": "string", "description": "UUID of the content atom to read the draft from"] as [String: Any]
                    ] as [String: Any],
                    "required": ["contentUUID"]
                ]
            ),
            LLMToolDefinition(
                name: "generate_hooks",
                description: "Generate hook variants using the unified writing engine. Analyzes the swipe library for best-performing hook types and generates scored variants specific to this content piece. ALWAYS pass clientName.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "contentUUID": ["type": "string", "description": "UUID of the content atom to generate hooks for"] as [String: Any],
                        "count": ["type": "integer", "description": "Number of hook variants to generate (default 5, max 8)"] as [String: Any],
                        "clientName": ["type": "string", "description": "Client name for this content piece. Ensures the engine loads the correct client profile."] as [String: Any]
                    ] as [String: Any],
                    "required": ["contentUUID"]
                ]
            ),
            LLMToolDefinition(
                name: "revise_draft",
                description: "Revise an existing draft using the unified writing engine. The engine makes SURGICAL edits — it preserves everything that works and only changes what the feedback targets. Use this whenever the user gives feedback on a draft. IMPORTANT: Pass the user's COMPLETE feedback in the feedback parameter — include every detail, every slide reference, every comparison. ALWAYS use this instead of writing revisions inline. ALWAYS pass clientName.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "contentUUID": ["type": "string", "description": "UUID of the content atom to revise"] as [String: Any],
                        "feedback": ["type": "string", "description": "The user's COMPLETE revision feedback — include everything: what to change, what to keep, specific slide numbers, comparisons, style notes. Pass the full message, not a summary."] as [String: Any],
                        "currentDraft": ["type": "string", "description": "Optional: the FULL current draft text if it hasn't been saved to the atom yet. Include every slide/section."] as [String: Any],
                        "clientName": ["type": "string", "description": "Client name for this content piece. Ensures the engine loads the correct client profile."] as [String: Any]
                    ] as [String: Any],
                    "required": ["contentUUID", "feedback"]
                ]
            ),
            LLMToolDefinition(
                name: "update_content",
                description: "Update an existing content atom's fields (title, body, description, hooks, outline, platform, client, framework). Pure data update, no AI generation. Use this to set outline points, hooks, and description for a content piece.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "uuid": ["type": "string", "description": "UUID of the content atom to update"] as [String: Any],
                        "title": ["type": "string", "description": "New title"] as [String: Any],
                        "body": ["type": "string", "description": "New draft body text"] as [String: Any],
                        "platform": ["type": "string", "description": "Target platform (twitter, instagram, youtube, linkedin, tiktok, threads, substack, medium)"] as [String: Any],
                        "clientName": ["type": "string", "description": "Client name to associate (fuzzy-matched to profile)"] as [String: Any],
                        "description": ["type": "string", "description": "Content description / core idea (stored in metadata, NOT the draft body)"] as [String: Any],
                        "framework": ["type": "string", "description": "Framework to use (e.g. AIDA, PAS, storyLoop)"] as [String: Any],
                        "hooks": ["type": "array", "items": ["type": "string"] as [String: Any], "description": "Hook texts to store"] as [String: Any],
                        "outline": ["type": "array", "items": ["type": "string"] as [String: Any], "description": "Outline point titles (each string becomes an outline item)"] as [String: Any]
                    ] as [String: Any],
                    "required": ["uuid"]
                ]
            ),
        ]
    }

    // MARK: - Strategy & Intelligence Tools

    private var strategyTools: [LLMToolDefinition] {
        [
            LLMToolDefinition(
                name: "get_weekly_content_plan",
                description: "Generate a personalized weekly content plan with specific recommendations based on your swipe library patterns, idea vault, and content performance.",
                parametersSchema: [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ]
            ),
            LLMToolDefinition(
                name: "suggest_next_content",
                description: "Get a recommendation for what content to create right now, considering pipeline status, ready ideas, and available time.",
                parametersSchema: [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ]
            ),
            LLMToolDefinition(
                name: "analyze_content_gap",
                description: "Identify gaps in your content strategy -- topics you have swipes for but haven't published about, underused hook types, cadence gaps.",
                parametersSchema: [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ]
            ),
            LLMToolDefinition(
                name: "predict_performance",
                description: "Score a draft against your historical content performance patterns.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "text": ["type": "string", "description": "The draft text to analyze"] as [String: Any],
                        "hookType": ["type": "string", "description": "Optional: the hook type used"] as [String: Any],
                        "framework": ["type": "string", "description": "Optional: the framework used"] as [String: Any]
                    ] as [String: Any],
                    "required": ["text"]
                ]
            ),
            LLMToolDefinition(
                name: "get_swipe_study_plan",
                description: "Get a personalized plan for which swipe files to study this week to fill gaps in your framework/hook knowledge.",
                parametersSchema: [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ]
            ),
        ]
    }

    private var intelligenceTools: [LLMToolDefinition] {
        [
            LLMToolDefinition(
                name: "get_creator_profile",
                description: "Get your creative DNA profile -- voice fingerprint, hook DNA, framework preferences, emotional signature, platform strengths.",
                parametersSchema: [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ]
            ),
            LLMToolDefinition(
                name: "get_audience_insights",
                description: "Get audience intelligence -- engagement patterns, growth drivers, audience profile, best posting times.",
                parametersSchema: [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ]
            ),
            LLMToolDefinition(
                name: "review_draft_persuasion",
                description: "Analyze a draft for persuasion techniques and suggest improvements based on your best-performing content.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "text": ["type": "string", "description": "The draft text to review"] as [String: Any]
                    ] as [String: Any],
                    "required": ["text"]
                ]
            ),
            LLMToolDefinition(
                name: "suggest_persuasion_stack",
                description: "Recommend the best persuasion techniques for a given topic and platform based on your swipe library data.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "topic": ["type": "string", "description": "The content topic"] as [String: Any],
                        "platform": ["type": "string", "description": "Target platform (twitter, instagram, youtube, etc.)"] as [String: Any]
                    ] as [String: Any],
                    "required": ["topic", "platform"]
                ]
            ),
            LLMToolDefinition(
                name: "compare_to_swipe",
                description: "Compare your draft to a reference swipe file, analyzing structural differences and improvement opportunities.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "text": ["type": "string", "description": "Your draft text"] as [String: Any],
                        "swipeUUID": ["type": "string", "description": "The UUID of the swipe file to compare against"] as [String: Any]
                    ] as [String: Any],
                    "required": ["text", "swipeUUID"]
                ]
            ),
        ]
    }

    // MARK: - Insight Memory Tools (WP6)

    private var insightMemoryTools: [LLMToolDefinition] {
        [
            LLMToolDefinition(
                name: "save_analysis",
                description: "Save a deep analysis or pattern insight for future reference. Use this after performing heavy analysis of multiple swipes, content pieces, or client patterns. The saved insight can be retrieved later without re-analyzing the raw data.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string", "description": "Descriptive title for the analysis (e.g. 'Ben hook patterns Q1 2026', 'Story framework analysis')"] as [String: Any],
                        "content": ["type": "string", "description": "The full analysis text with insights, patterns, and recommendations"] as [String: Any],
                        "clientName": ["type": "string", "description": "Optional: client name this analysis relates to"] as [String: Any],
                        "tags": ["type": "array", "items": ["type": "string"] as [String: Any], "description": "Tags for retrieval (e.g. ['hooks', 'patterns', 'ben'])"] as [String: Any]
                    ] as [String: Any],
                    "required": ["title", "content"]
                ]
            ),
            LLMToolDefinition(
                name: "get_saved_analyses",
                description: "Retrieve previously saved analyses and insights. Check this before re-analyzing data you've seen before. Returns saved pattern analyses, client insights, and strategic observations.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "clientName": ["type": "string", "description": "Optional: filter by client name"] as [String: Any],
                        "tags": ["type": "array", "items": ["type": "string"] as [String: Any], "description": "Optional: filter by tags"] as [String: Any],
                        "limit": ["type": "integer", "description": "Max results (default 10)"] as [String: Any]
                    ] as [String: Any],
                    "required": [] as [String]
                ]
            ),
        ]
    }

    // MARK: - Lesson Tools

    private var lessonTools: [LLMToolDefinition] {
        [
            LLMToolDefinition(
                name: "save_lessons",
                description: "Save skills, lessons, or rules that should be remembered across sessions. Auto-routes to the matching skill module (e.g. hook lessons → Hook Methodology). Use targetModule to override routing. Categories: hook_style, voice, structure, format, cta, scheduling, productivity, time_management, strategy_pattern, audience_insight, analysis_method, reflection_prompt, general. Module IDs for targetModule: dinner_table_test, slide_density, causal_chaining, hook_craft, voice_matching, cta_craft, self_edit_pass, virality_engine, hook_writing, body_structure, emotional_engineering, funnel_strategy, platform_rules, idea_evaluation.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "lessons": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "rule": ["type": "string", "description": "The lesson or rule to remember"] as [String: Any],
                                    "category": ["type": "string", "description": "Category: hook_style, voice, structure, format, cta, scheduling, productivity, time_management, strategy_pattern, audience_insight, analysis_method, reflection_prompt, general"] as [String: Any],
                                    "evidence": ["type": "string", "description": "Optional evidence or reasoning for this lesson"] as [String: Any],
                                    "intent": ["type": "string", "description": "Optional intent scope: draft, brainstorm, plan, strategy, analyze, reflect, capture, execute, debrief, meta. Omit for universal."] as [String: Any],
                                    "targetModule": ["type": "string", "description": "Override auto-detected module destination. Module IDs: hook_writing, voice_matching, body_structure, platform_rules, cta_craft, funnel_strategy, idea_evaluation, virality_engine, emotional_engineering."] as [String: Any]
                                ] as [String: Any],
                                "required": ["rule", "category"]
                            ] as [String: Any],
                            "description": "Array of lessons to save"
                        ] as [String: Any],
                        "clientName": ["type": "string", "description": "Optional client name to scope these lessons to (e.g. 'Ben', 'Michael')"] as [String: Any]
                    ] as [String: Any],
                    "required": ["lessons"]
                ]
            ),
            LLMToolDefinition(
                name: "get_lessons",
                description: "Retrieve saved skills and lessons. Returns lessons stored via save_lessons, filtered by optional client, category, and intent scope.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "clientName": ["type": "string", "description": "Optional client name to filter lessons for"] as [String: Any],
                        "category": ["type": "string", "description": "Optional category filter"] as [String: Any],
                        "intent": ["type": "string", "description": "Optional intent scope filter: draft, brainstorm, plan, strategy, analyze, reflect, etc."] as [String: Any]
                    ] as [String: Any],
                    "required": [] as [String]
                ]
            ),
            LLMToolDefinition(
                name: "update_skill",
                description: "Update an existing skill's rule text, category, or intent scope.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "lessonId": ["type": "string", "description": "UUID of the lesson to update"] as [String: Any],
                        "rule": ["type": "string", "description": "New rule text"] as [String: Any],
                        "category": ["type": "string", "description": "New category"] as [String: Any],
                        "intent": ["type": "string", "description": "New intent scope. Use 'universal' to clear intent scope."] as [String: Any]
                    ] as [String: Any],
                    "required": ["lessonId"]
                ]
            ),
            LLMToolDefinition(
                name: "delete_skill",
                description: "Delete a learned skill by its UUID.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "lessonId": ["type": "string", "description": "UUID of the lesson to delete"] as [String: Any]
                    ] as [String: Any],
                    "required": ["lessonId"]
                ]
            ),
        ]
    }

    // MARK: - Web Search Tools

    private var webSearchTools: [LLMToolDefinition] {
        [
            LLMToolDefinition(
                name: "web_search",
                description: "Search the web for current information. Use when the user asks about recent events, needs facts, or wants info not in their database.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "Search query"] as [String: Any],
                        "maxResults": ["type": "integer", "description": "Max results (default 5)"] as [String: Any]
                    ] as [String: Any],
                    "required": ["query"]
                ]
            ),
        ]
    }

    // MARK: - Client Profile Tools

    private var clientProfileTools: [LLMToolDefinition] {
        [
            LLMToolDefinition(
                name: "list_client_profiles",
                description: "List all client profiles. Returns name, niche, platforms, and UUID for each client. Use this to find available clients before getting their full profile.",
                parametersSchema: [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ]
            ),
            LLMToolDefinition(
                name: "get_client_profile",
                description: "Get a client's FULL profile including brand story, voice notes, unique angle, core beliefs, signature phrases, top-performing posts, intelligence model (voice fingerprint, failure fingerprint, audience model), and preferred beat patterns. Use this when you need to write in a client's voice or understand their brand.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "client_name": ["type": "string", "description": "The client name (e.g. 'Ben', 'Michael'). Uses fuzzy matching."] as [String: Any]
                    ] as [String: Any],
                    "required": ["client_name"]
                ]
            ),
        ]
    }

    // MARK: - Telegram UX Tools

    private func interactiveUXTools(for source: MessageSource) -> [LLMToolDefinition] {
        let toolName: String
        let toolDescription: String

        switch source {
        case .telegram:
            toolName = "send_telegram_buttons"
            toolDescription = "Send a message with inline buttons to Telegram. Each button triggers an action string that gets routed back through the agent as if the user typed it. Use this to offer quick-action choices after giving recommendations or asking a question. Max 8 buttons."
        case .inApp, .whatsapp:
            toolName = "send_action_buttons"
            toolDescription = "Send a message with interactive buttons to the user. Each button triggers an action string that gets routed back through the agent as if the user typed it. Use this to offer quick-action choices after giving recommendations or asking a question. Max 8 buttons."
        }

        return [
            LLMToolDefinition(
                name: toolName,
                description: toolDescription,
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "message": ["type": "string", "description": "The text displayed above the buttons"] as [String: Any],
                        "buttons": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "label": ["type": "string", "description": "Button display text"] as [String: Any],
                                    "action": ["type": "string", "description": "Action string sent back when pressed (routed as user message)"] as [String: Any]
                                ] as [String: Any],
                                "required": ["label", "action"]
                            ] as [String: Any],
                            "description": "Array of button objects (max 8)"
                        ] as [String: Any]
                    ] as [String: Any],
                    "required": ["message", "buttons"]
                ]
            ),
        ]
    }

    // MARK: - Client Memory Tools

    private var clientMemoryTools: [LLMToolDefinition] {
        [
            LLMToolDefinition(
                name: "update_client_memory",
                description: "Update a persistent memory/preference for a specific client. Use this when you learn something about a client's preferences, voice, or style that should persist across sessions.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "client_name": ["type": "string", "description": "The client name to update memory for"] as [String: Any],
                        "field": ["type": "string", "description": "The memory field: preferred_hook_style, voice_quirks, forbidden_patterns, content_preferences, audience_insights, learned_rules"] as [String: Any],
                        "value": ["type": "string", "description": "The value to store"] as [String: Any]
                    ] as [String: Any],
                    "required": ["client_name", "field", "value"]
                ]
            ),
            LLMToolDefinition(
                name: "list_client_memory",
                description: "List all stored memories and preferences for a client. Use this to review what you know about a client.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "client_name": ["type": "string", "description": "The client name to list memories for"] as [String: Any]
                    ] as [String: Any],
                    "required": ["client_name"]
                ]
            ),
        ]
    }

    // MARK: - Module Management Tools

    private var moduleManagementTools: [LLMToolDefinition] {
        [
            LLMToolDefinition(
                name: "suggest_module_addition",
                description: "Suggest adding a new rule or insight to a skill module, or creating a new skill module. The user will be asked to confirm before any changes are made. Use this when you identify a writing pattern, quality rule, or craft technique that should be remembered for future content generation.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "action": ["type": "string", "enum": ["add_to_module", "create_module"], "description": "Whether to add content to an existing module or create a new one"] as [String: Any],
                        "moduleId": ["type": "string", "description": "ID of existing module to add to (required for add_to_module). Module IDs: dinner_table_test, slide_density, causal_chaining, hook_craft, voice_matching, cta_craft, self_edit_pass, virality_engine, hook_writing, body_structure, emotional_engineering, funnel_strategy, platform_rules, idea_evaluation"] as [String: Any],
                        "content": ["type": "string", "description": "The rule, technique, or insight to add"] as [String: Any],
                        "reason": ["type": "string", "description": "Why this should be added (evidence from recent work)"] as [String: Any],
                        "newModuleTitle": ["type": "string", "description": "Title for new module (required for create_module)"] as [String: Any],
                        "newModuleId": ["type": "string", "description": "Snake_case ID for new module (required for create_module)"] as [String: Any]
                    ] as [String: Any],
                    "required": ["action", "content", "reason"]
                ]
            ),
        ]
    }

    // MARK: - Intent-Based Tool Selection (Updated)

    /// Return relevant tools for a given intent (v2 with strategy + intelligence tools).
    /// Source-gated: Telegram gets `send_telegram_buttons`, in-app gets `send_action_buttons`.
    func toolsForIntent(_ intent: AgentIntent, source: MessageSource = .inApp) -> [LLMToolDefinition] {
        let uxTools = interactiveUXTools(for: source)
        switch intent {
        case .capture:
            return ideaTools + swipeTools + captureTools + plannerumTools + clientTools + clientProfileTools + clientMemoryTools + lessonTools + moduleManagementTools
        case .brainstorm:
            return ideaTools + swipeTools + captureTools + clientTools + clientProfileTools + intelligenceTools + writingTools + clientMemoryTools + preferenceTools + scoringTools + lessonTools + moduleManagementTools + webSearchTools
        case .plan:
            return plannerumTools + contentTools + strategyTools + clientProfileTools + lessonTools + moduleManagementTools
        case .query:
            return allTools
        case .correct:
            return ideaTools + contentTools + plannerumTools + clientTools + clientProfileTools + moduleManagementTools
        case .execute:
            return contentTools + plannerumTools + questTools + writingTools + clientProfileTools + uxTools + lessonTools + moduleManagementTools
        case .debrief, .reflect:
            return analyticsTools + questTools + lessonTools + moduleManagementTools
        case .meta:
            return preferenceTools + standingInstructionTools + clientMemoryTools + lessonTools + uxTools + moduleManagementTools
        case .strategy:
            return strategyTools + swipeTools + contentTools + analyticsTools + intelligenceTools + writingTools + clientProfileTools + clientMemoryTools + insightMemoryTools + uxTools + lessonTools + moduleManagementTools + webSearchTools
        case .draft:
            return contentTools + swipeTools + ideaTools + intelligenceTools + writingTools + clientProfileTools + clientMemoryTools + preferenceTools + captureTools + scoringTools + insightMemoryTools + lessonTools + uxTools + moduleManagementTools + webSearchTools
        case .analyze:
            return intelligenceTools + swipeTools + analyticsTools + contentTools + clientProfileTools + insightMemoryTools + lessonTools + moduleManagementTools + webSearchTools
        }
    }

    // MARK: - Registration

    private func registerAllTools() {
        allTools = ideaTools + swipeTools + captureTools + contentTools + plannerumTools + analyticsTools + questTools + preferenceTools + clientTools + clientProfileTools + strategyTools + intelligenceTools + standingInstructionTools + writingTools + clientMemoryTools + scoringTools + insightMemoryTools + lessonTools + interactiveUXTools(for: .telegram) + interactiveUXTools(for: .inApp) + moduleManagementTools + webSearchTools
    }
}
