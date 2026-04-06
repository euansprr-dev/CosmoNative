// CosmoOS/Agent/Core/AgentToolRegistry.swift
// Tool definitions for the Cosmo Intelligence Layer — knowledge queries, research, workspace, automation

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
            LLMToolDefinition(
                name: "adapt_swipes_for_client",
                description: "Analyze the ENTIRE swipe library and generate content ideas adapted to a specific client's niche, voice, and audience. Use this when the user asks for ideas based on swipes, like 'give me ideas for [client]', 'adapt swipes for [client]', 'what can we make from the swipe library for [client]', or 'look at recent swipes and find ideas for [client]'. This is DIFFERENT from search_swipes — it scores every hook for structural adaptability and generates ready-to-use adapted ideas. Supports time filters like 'today', 'this week', 'last 7 days'.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "clientName": ["type": "string", "description": "The client name to adapt swipes for (e.g. 'Ben', 'Michael')"] as [String: Any],
                        "timeFilter": ["type": "string", "description": "Optional time filter: 'today', 'yesterday', 'this week', 'this month', 'last N days'"] as [String: Any],
                        "maxResults": ["type": "integer", "description": "Max adapted ideas to return (default 10, max 25)"] as [String: Any]
                    ] as [String: Any],
                    "required": ["clientName"]
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

    private var scheduleTools: [LLMToolDefinition] {
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
                description: "Get XP totals and levels for dimensions (cognitive, creative, physiological, behavioral, knowledge, reflection).",
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

    // MARK: - Content Data Tools (non-writing)

    private var contentDataTools: [LLMToolDefinition] {
        [
            LLMToolDefinition(
                name: "update_content",
                description: "Update an existing content atom's fields (title, body, description, hooks, outline, platform, client, framework). Pure data update, no AI generation.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "uuid": ["type": "string", "description": "UUID of the content atom to update"] as [String: Any],
                        "title": ["type": "string", "description": "New title"] as [String: Any],
                        "body": ["type": "string", "description": "New draft body text"] as [String: Any],
                        "platform": ["type": "string", "description": "Target platform (twitter, instagram, youtube, linkedin, tiktok, threads, substack, medium)"] as [String: Any],
                        "clientName": ["type": "string", "description": "Client name to associate (fuzzy-matched to profile)"] as [String: Any],
                        "description": ["type": "string", "description": "Content description / core idea"] as [String: Any],
                        "framework": ["type": "string", "description": "Framework to use (e.g. AIDA, PAS, storyLoop)"] as [String: Any],
                        "hooks": ["type": "array", "items": ["type": "string"] as [String: Any], "description": "Hook texts to store"] as [String: Any],
                        "outline": ["type": "array", "items": ["type": "string"] as [String: Any], "description": "Outline point titles"] as [String: Any]
                    ] as [String: Any],
                    "required": ["uuid"]
                ]
            ),
        ]
    }

    // MARK: - Knowledge Query Tools

    private var knowledgeQueryTools: [LLMToolDefinition] {
        [
            LLMToolDefinition(
                name: "query_atoms",
                description: "Search across ALL atom types using keyword search. Use this for natural language queries like 'ideas about marketing', 'tasks due this week', 'recent research'. Combines FTS5 BM25 ranking with metadata filtering.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "Search query text"] as [String: Any],
                        "types": ["type": "array", "items": ["type": "string"] as [String: Any], "description": "Optional: filter by atom types (idea, task, research, content, connection, note, project, thinkspace, etc.)"] as [String: Any],
                        "limit": ["type": "integer", "description": "Max results (default 10, max 50)"] as [String: Any],
                        "dateRange": ["type": "string", "description": "Optional: 'today', 'yesterday', 'this_week', 'last_7d', 'last_30d', 'this_month'"] as [String: Any],
                        "projectUuid": ["type": "string", "description": "Optional: filter to atoms in a specific project"] as [String: Any]
                    ] as [String: Any],
                    "required": ["query"]
                ]
            ),
            LLMToolDefinition(
                name: "graph_traverse",
                description: "Follow relationships from an atom to find connected atoms. Use this for 'show everything connected to X', 'what's related to this research', etc. Performs BFS traversal of AtomLinks.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "uuid": ["type": "string", "description": "UUID of the source atom to traverse from"] as [String: Any],
                        "linkTypes": ["type": "array", "items": ["type": "string"] as [String: Any], "description": "Optional: filter by link types (e.g. ideaToSwipe, ideaToContent, project, related)"] as [String: Any],
                        "depth": ["type": "integer", "description": "Max traversal depth (default 1, max 3)"] as [String: Any],
                        "direction": ["type": "string", "description": "Traversal direction: 'outgoing' (default), 'incoming', or 'both'"] as [String: Any]
                    ] as [String: Any],
                    "required": ["uuid"]
                ]
            ),
            LLMToolDefinition(
                name: "get_atom_detail",
                description: "Get full details of any atom by UUID. Returns parsed metadata, structured data, link count, and thinkspace membership. Use this when you need the complete picture of a single atom.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "uuid": ["type": "string", "description": "The atom UUID to retrieve"] as [String: Any]
                    ] as [String: Any],
                    "required": ["uuid"]
                ]
            ),
            LLMToolDefinition(
                name: "count_atoms",
                description: "Count atoms with optional grouping. Use for analytics questions like 'how many ideas per week', 'tasks by status', etc.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "type": ["type": "string", "description": "Atom type to count (idea, task, research, content, etc.)"] as [String: Any],
                        "dateRange": ["type": "string", "description": "Optional: 'today', 'this_week', 'last_7d', 'last_30d', 'this_month', 'this_quarter'"] as [String: Any],
                        "groupBy": ["type": "string", "description": "Optional: 'week', 'month', 'status', 'type'"] as [String: Any]
                    ] as [String: Any],
                    "required": ["type"]
                ]
            ),
        ]
    }

    // MARK: - Research & Synthesis Tools

    private var researchTools: [LLMToolDefinition] {
        [
            LLMToolDefinition(
                name: "synthesize_knowledge",
                description: "Gather and synthesize knowledge from multiple atoms on a topic. Use when the user asks 'what do I know about X', 'summarize my research on Y', or wants a research-grounded answer. Searches your knowledge base and returns concatenated source content for synthesis.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "The topic or question to synthesize knowledge about"] as [String: Any],
                        "atomUuids": ["type": "array", "items": ["type": "string"] as [String: Any], "description": "Optional: specific atom UUIDs to use as sources (skips search)"] as [String: Any],
                        "maxSources": ["type": "integer", "description": "Max source atoms to include (default 10, max 20)"] as [String: Any],
                        "scope": ["type": "string", "description": "Optional: limit to specific types — 'swipes', 'research', 'ideas', 'notes', or 'all' (default)"] as [String: Any]
                    ] as [String: Any],
                    "required": ["query"]
                ]
            ),
            LLMToolDefinition(
                name: "synthesize_learning",
                description: "Identify patterns and themes across multiple atoms. Use for 'what patterns have I found about X', 'create a summary of everything about Y'. Returns structured analysis with themes, patterns, and actionable insights. Can save results as a new atom.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "topic": ["type": "string", "description": "The topic to synthesize learning about"] as [String: Any],
                        "scope": ["type": "string", "description": "Source scope: 'swipes', 'research', 'ideas', 'notes', or 'all' (default)"] as [String: Any],
                        "maxSources": ["type": "integer", "description": "Max source atoms (default 15, max 30)"] as [String: Any],
                        "outputFormat": ["type": "string", "description": "Output: 'summary' (narrative), 'patterns' (recurring themes), 'actionable' (concrete takeaways), 'flashcards' (Q&A pairs)"] as [String: Any],
                        "saveAsAtom": ["type": "boolean", "description": "If true, saves the synthesis as a new research atom linked to all sources"] as [String: Any]
                    ] as [String: Any],
                    "required": ["topic"]
                ]
            ),
        ]
    }

    // MARK: - Workspace Organization Tools

    private var workspaceTools: [LLMToolDefinition] {
        [
            LLMToolDefinition(
                name: "manage_thinkspace",
                description: "Create, rename, archive, or duplicate a thinkspace. Supports templates for common layouts.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "action": ["type": "string", "description": "Action: 'create', 'rename', 'archive', 'duplicate'"] as [String: Any],
                        "name": ["type": "string", "description": "Thinkspace name (for create/rename)"] as [String: Any],
                        "uuid": ["type": "string", "description": "Thinkspace UUID (for rename/archive/duplicate)"] as [String: Any],
                        "template": ["type": "string", "description": "Template for create: 'blank', 'brainstorm', 'kanban', 'research', 'daily'"] as [String: Any],
                        "projectUuid": ["type": "string", "description": "Optional: project UUID to assign the thinkspace to"] as [String: Any]
                    ] as [String: Any],
                    "required": ["action"]
                ]
            ),
            LLMToolDefinition(
                name: "move_blocks",
                description: "Move atoms between thinkspaces. Relocates canvas blocks and updates their positions.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "atomUuids": ["type": "array", "items": ["type": "string"] as [String: Any], "description": "UUIDs of atoms to move"] as [String: Any],
                        "targetThinkspaceUuid": ["type": "string", "description": "UUID of the destination thinkspace"] as [String: Any],
                        "position": ["type": "string", "description": "Positioning strategy: 'auto' (default), 'grid', 'stack'"] as [String: Any]
                    ] as [String: Any],
                    "required": ["atomUuids", "targetThinkspaceUuid"]
                ]
            ),
            LLMToolDefinition(
                name: "bulk_update",
                description: "Update multiple atoms at once. Use for batch operations like 'archive all completed tasks', 'tag these ideas for project X'. Always shows preview before executing.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "uuids": ["type": "array", "items": ["type": "string"] as [String: Any], "description": "UUIDs of atoms to update"] as [String: Any],
                        "updates": ["type": "object", "description": "Fields to update: status, tags, projectUuid, isArchived"] as [String: Any]
                    ] as [String: Any],
                    "required": ["uuids", "updates"]
                ]
            ),
            LLMToolDefinition(
                name: "organize_space",
                description: "AI-powered thinkspace layout optimization. Reads all blocks and rearranges them by strategy. Shows preview before applying.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "thinkspaceUuid": ["type": "string", "description": "UUID of the thinkspace to organize"] as [String: Any],
                        "strategy": ["type": "string", "description": "Layout strategy: 'cluster_by_type', 'timeline', 'priority', 'grid'"] as [String: Any]
                    ] as [String: Any],
                    "required": ["thinkspaceUuid", "strategy"]
                ]
            ),
            LLMToolDefinition(
                name: "explore_graph",
                description: "Explore the knowledge graph visually from a center atom. Returns nodes and edges for inline graph rendering. Use for 'show connections to X', 'map out project Y'.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "centerUuid": ["type": "string", "description": "UUID of the center atom to explore from"] as [String: Any],
                        "depth": ["type": "integer", "description": "Exploration depth (default 1, max 3)"] as [String: Any],
                        "filterTypes": ["type": "array", "items": ["type": "string"] as [String: Any], "description": "Optional: filter to specific atom types"] as [String: Any],
                        "filterLinkTypes": ["type": "array", "items": ["type": "string"] as [String: Any], "description": "Optional: filter to specific link types"] as [String: Any]
                    ] as [String: Any],
                    "required": ["centerUuid"]
                ]
            ),
        ]
    }

    // MARK: - Semantic SQL Tool

    private var sqlTools: [LLMToolDefinition] {
        [
            LLMToolDefinition(
                name: "execute_sql",
                description: "Execute a read-only SQL query against the Atom database. Use for complex analytical questions that can't be answered by other tools (e.g. 'ideas per week grouped by client', 'most connected atoms'). ONLY SELECT queries are allowed. The atoms table has columns: uuid, type, title, body, structured, metadata, links, created_at, updated_at, is_deleted. The atoms_fts table supports full-text search. The canvas_blocks table has: id, entityUuid, entityType, positionX, positionY, width, height, thinkspaceId.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "SQL SELECT query to execute"] as [String: Any],
                        "explain": ["type": "boolean", "description": "If true, returns query explanation instead of results"] as [String: Any]
                    ] as [String: Any],
                    "required": ["query"]
                ]
            ),
        ]
    }

    // MARK: - Automation Tools

    private var automationTools: [LLMToolDefinition] {
        [
            LLMToolDefinition(
                name: "create_automation_rule",
                description: "Create an automation rule that triggers actions when events occur. Use for 'when I complete a deep work session, create a journal entry', 'when a task is completed, notify me', etc.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string", "description": "Rule name"] as [String: Any],
                        "trigger": ["type": "object", "description": "Trigger config: { event: 'atom_created'|'atom_updated'|'task_completed'|'deep_work_ended'|'time_schedule'|'phase_advanced', conditions: [{field, op, value}] }"] as [String: Any],
                        "actions": ["type": "array", "items": ["type": "object"] as [String: Any], "description": "Actions: [{ type: 'create_atom'|'update_atom'|'move_to_thinkspace'|'send_notification'|'create_journal_entry'|'tag_atom', params: {...} }]"] as [String: Any],
                        "isEnabled": ["type": "boolean", "description": "Whether the rule is active (default true)"] as [String: Any]
                    ] as [String: Any],
                    "required": ["name", "trigger", "actions"]
                ]
            ),
            LLMToolDefinition(
                name: "list_automations",
                description: "List all automation rules with their trigger, actions, and enabled status.",
                parametersSchema: [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ]
            ),
            LLMToolDefinition(
                name: "toggle_automation",
                description: "Enable or disable an automation rule.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "uuid": ["type": "string", "description": "UUID of the automation rule"] as [String: Any],
                        "enabled": ["type": "boolean", "description": "New enabled state"] as [String: Any]
                    ] as [String: Any],
                    "required": ["uuid", "enabled"]
                ]
            ),
        ]
    }

    // MARK: - Workflow Tools

    private var workflowTools: [LLMToolDefinition] {
        [
            LLMToolDefinition(
                name: "run_workflow",
                description: "Execute a multi-step workflow. Use for complex requests like 'prepare my morning briefing', 'set up a new project with tasks and thinkspace'. Shows a plan card for user confirmation before executing.",
                parametersSchema: [
                    "type": "object",
                    "properties": [
                        "description": ["type": "string", "description": "What this workflow accomplishes"] as [String: Any],
                        "steps": ["type": "array", "items": [
                            "type": "object",
                            "properties": [
                                "tool": ["type": "string", "description": "Tool to call"] as [String: Any],
                                "args": ["type": "object", "description": "Arguments for the tool"] as [String: Any],
                                "dependsOn": ["type": "integer", "description": "Index of step this depends on (for sequential execution)"] as [String: Any]
                            ] as [String: Any],
                            "required": ["tool", "args"]
                        ] as [String: Any], "description": "Ordered steps to execute"] as [String: Any]
                    ] as [String: Any],
                    "required": ["description", "steps"]
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

    // MARK: - Intent-Based Tool Selection

    /// Return relevant tools for a given intent.
    /// Source-gated: Telegram gets `send_telegram_buttons`, in-app gets `send_action_buttons`.
    func toolsForIntent(_ intent: AgentIntent, source: MessageSource = .inApp) -> [LLMToolDefinition] {
        let uxTools = interactiveUXTools(for: source)
        let coreTools = knowledgeQueryTools + researchTools
        switch intent {
        case .capture:
            return ideaTools + swipeTools + captureTools + scheduleTools + clientTools + clientProfileTools + clientMemoryTools + lessonTools + moduleManagementTools
        case .brainstorm:
            return coreTools + ideaTools + swipeTools + captureTools + clientTools + clientProfileTools + intelligenceTools + clientMemoryTools + preferenceTools + lessonTools + moduleManagementTools + webSearchTools
        case .plan:
            return scheduleTools + contentTools + strategyTools + clientProfileTools + lessonTools + moduleManagementTools + workspaceTools
        case .query:
            return allTools
        case .correct:
            return ideaTools + contentTools + contentDataTools + scheduleTools + clientTools + clientProfileTools + moduleManagementTools + workspaceTools
        case .execute:
            return contentTools + contentDataTools + scheduleTools + clientProfileTools + uxTools + lessonTools + moduleManagementTools + workspaceTools + workflowTools
        case .debrief, .reflect:
            return coreTools + analyticsTools + lessonTools + moduleManagementTools
        case .meta:
            return preferenceTools + standingInstructionTools + clientMemoryTools + lessonTools + uxTools + moduleManagementTools
        case .strategy:
            return coreTools + strategyTools + swipeTools + contentTools + analyticsTools + intelligenceTools + clientProfileTools + clientMemoryTools + insightMemoryTools + uxTools + lessonTools + moduleManagementTools + webSearchTools
        case .research:
            return coreTools + swipeTools + ideaTools + captureTools + clientProfileTools + insightMemoryTools + webSearchTools + lessonTools
        case .synthesize:
            return coreTools + swipeTools + ideaTools + intelligenceTools + insightMemoryTools + clientProfileTools + lessonTools + webSearchTools
        case .analyze:
            return coreTools + intelligenceTools + swipeTools + analyticsTools + contentTools + clientProfileTools + insightMemoryTools + lessonTools + moduleManagementTools + webSearchTools + sqlTools
        case .organize:
            return workspaceTools + contentTools + ideaTools + scheduleTools + uxTools + workflowTools + automationTools
        }
    }

    // MARK: - Registration

    private func registerAllTools() {
        allTools = knowledgeQueryTools + researchTools + ideaTools + swipeTools + captureTools + contentTools + contentDataTools + scheduleTools + analyticsTools + preferenceTools + clientTools + clientProfileTools + strategyTools + intelligenceTools + standingInstructionTools + clientMemoryTools + insightMemoryTools + lessonTools + interactiveUXTools(for: .telegram) + interactiveUXTools(for: .inApp) + moduleManagementTools + webSearchTools + workspaceTools + sqlTools + automationTools + workflowTools
    }
}
