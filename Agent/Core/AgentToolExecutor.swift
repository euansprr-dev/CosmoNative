// CosmoOS/Agent/Core/AgentToolExecutor.swift
// Executes agent tools against CosmoOS services

import Foundation
import CoreGraphics

@MainActor
class AgentToolExecutor {
    static let shared = AgentToolExecutor()

    private let atomRepo = AtomRepository.shared

    /// Pending confirmations for Hard tier actions
    var pendingConfirmations: [String: PendingConfirmation] = [:]

    /// Batch tracker for rapid idea captures (3+ within 2 minutes → batched confirmation)
    private var recentIdeaCaptures: [(timestamp: Date, title: String, clientName: String?)] = []

    // Writing engine cache removed — all writing now goes through CloudWritingClient.
    // The cloud engine manages its own session cache per contentUUID.

    struct PendingConfirmation {
        let toolName: String
        let arguments: [String: Any]
        let description: String
        let createdAt: Date
    }

    /// Pending module suggestions queued for user confirmation via Telegram.
    struct PendingModuleSuggestion: Codable {
        let id: UUID
        let action: String // "add_to_module" or "create_module"
        let moduleId: String?
        let content: String
        let reason: String
        let newModuleTitle: String?
        let newModuleId: String?
    }

    /// In-memory queue of module suggestions awaiting user approval.
    var pendingModuleSuggestions: [PendingModuleSuggestion] = []

    /// Optional callback for emitting live tool activity events to the UI.
    /// Set by CosmoAgentService before each tool loop iteration so that tool
    /// execution (including context-loading sub-tools) can stream progress.
    /// Paired with a session token to prevent concurrent sessions from clearing
    /// each other's callbacks (see setToolActivity/clearToolActivity).
    private(set) var onToolActivity: (@Sendable (ToolActivityEvent) -> Void)?
    private var toolActivitySessionToken: UUID?

    /// Set the tool activity callback with a session token. Concurrent sessions
    /// on different chats each get their own token; clearToolActivity only clears
    /// if the token matches, preventing one session from killing another's callback.
    func setToolActivity(_ callback: (@Sendable (ToolActivityEvent) -> Void)?, token: UUID) {
        onToolActivity = callback
        toolActivitySessionToken = token
    }

    /// Clear the callback only if the token matches the one that set it.
    /// This prevents Session A from nilling out Session B's callback.
    func clearToolActivity(token: UUID) {
        if toolActivitySessionToken == token {
            onToolActivity = nil
            toolActivitySessionToken = nil
        }
    }

    /// Optional callback for delivering in-app action buttons from the `send_action_buttons` tool.
    /// Set by CosmoWindowViewModel before each agent call; cleared after completion.
    var onActionButtons: ((_ message: String, _ buttons: [(label: String, action: String)]) -> Void)?

    /// Optional callback for non-mutating canvas plan proposals.
    /// The Cosmo window owns review/apply/cancel so tools never directly mutate canvas state.
    var onCanvasPlan: ((PendingCanvasPlan) -> Void)?
    var onNoteStructurePlan: ((PendingNoteStructurePlan) -> Void)?

    private init() {}

    /// Context atom UUIDs from @ mentions — passed to cloud writing engine
    /// so it can load full structured content (connections, research, etc.)
    var contextAtomUUIDs: [String] = []

    /// Context source IDs from the shared Cosmo context subsystem.
    /// These stay scoped to the active agent call and power retrieve_context.
    var contextSourceIDs: [String] = []

    /// Active conversation ID for shared working-memory tools.
    var contextConversationID: String?

    /// Active client profile UUID from the current UI context.
    var activeClientUUID: String?

    // Writing engine cache removed — all writing now goes through CloudWritingClient.
    // The cloud engine manages its own session cache per contentUUID.
    // The getOrCreateEngine method has been replaced by cloud API calls in
    // generateOutline, generateDraft, and reviseDraft.

    // MARK: - Execute

    func execute(toolName: String, arguments: [String: Any]) async throws -> String {
        switch toolName {
        // Shared context and memory
        case "retrieve_context": return try await retrieveContext(arguments)
        case "inspect_pinned_sources": return try await inspectPinnedSources(arguments)
        case "remember_context": return try await rememberContext(arguments)
        case "search_memory": return try await searchMemory(arguments)
        // Ideas
        case "search_ideas": return try await searchIdeas(arguments)
        case "get_idea": return try await getIdea(arguments)
        case "create_idea": return try await createIdea(arguments)
        case "update_idea": return try await updateIdea(arguments)
        case "activate_idea": return try await activateIdea(arguments)
        // Swipes
        case "search_by_client": return try await searchByClient(arguments)
        case "search_swipes": return try await searchSwipes(arguments)
        case "list_all_swipes": return try await listAllSwipes(arguments)
        case "filter_swipes_by_taxonomy": return try await filterSwipesByTaxonomy(arguments)
        case "get_swipe_analysis": return try await getSwipeAnalysis(arguments)
        case "find_similar_swipes": return try await findSimilarSwipes(arguments)
        case "get_swipe_stats": return try await getSwipeStats(arguments)
        case "adapt_swipes_for_client": return try await adaptSwipesForClient(arguments)
        // Capture
        case "capture_swipe": return try await captureSwipe(arguments)
        case "capture_swipe_with_idea": return try await captureSwipeWithIdea(arguments)
        case "capture_research": return try await captureResearch(arguments)
        // Content
        case "get_content_pipeline": return try await getContentPipeline(arguments)
        case "advance_pipeline_phase": return try await advancePipelinePhase(arguments)
        case "create_content": return try await createContent(arguments)
        case "get_content": return try await getContent(arguments)
        case "create_thinkspace": return try await createThinkspace(arguments)
        case "inspect_current_thinkspace": return try await inspectCurrentThinkspace(arguments)
        case "propose_canvas_plan": return try await proposeCanvasPlan(arguments)
        case "propose_note_structure_plan": return try await proposeNoteStructurePlan(arguments)
        // Calendar / Schedule Blocks
        case "get_calendar_blocks": return try await getCalendarBlocks(arguments)
        case "create_block": return try await createBlock(arguments)
        case "update_block": return try await updateBlock(arguments)
        case "delete_block": return try await deleteBlock(arguments)
        case "complete_block": return try await completeBlock(arguments)
        case "get_unscheduled_tasks": return try await getUnscheduledTasks(arguments)
        case "create_task": return try await createTask(arguments)
        // Analytics
        case "get_dimension_xp": return try await getDimensionXP(arguments)
        case "get_streak_data": return try await getStreakData(arguments)
        // Preferences
        case "get_preferences": return try await getPreferences(arguments)
        case "store_preference": return try await storePreference(arguments)
        case "delete_preference": return try await deletePreference(arguments)
        // Strategy
        case "get_weekly_content_plan": return try await getWeeklyContentPlan(arguments)
        case "suggest_next_content": return try await suggestNextContent(arguments)
        case "analyze_content_gap": return try await analyzeContentGap(arguments)
        case "predict_performance": return try await predictPerformance(arguments)
        case "get_swipe_study_plan": return try await getSwipeStudyPlan(arguments)
        // Standing Instructions
        case "add_standing_instruction": return try await addStandingInstruction(arguments)
        case "list_standing_instructions": return try await listStandingInstructions(arguments)
        case "remove_standing_instruction": return try await removeStandingInstruction(arguments)
        case "update_standing_instruction": return try await updateStandingInstruction(arguments)
        case "get_instruction_history": return try await getInstructionHistory(arguments)
        // Intelligence
        case "get_creator_profile": return try await getCreatorProfile(arguments)
        case "get_audience_insights": return try await getAudienceInsights(arguments)
        case "review_draft_persuasion": return try await reviewDraftPersuasion(arguments)
        case "suggest_persuasion_stack": return try await suggestPersuasionStack(arguments)
        case "compare_to_swipe": return try await compareToSwipe(arguments)
        // Writing (Opus Engine)
        case "generate_outline": return try await generateOutline(arguments)
        case "generate_draft": return try await generateDraft(arguments)
        case "read_draft": return try await readDraft(arguments)
        case "revise_draft": return try await reviseDraft(arguments)
        case "generate_hooks": return try await generateHooks(arguments)
        case "update_content": return try await updateContent(arguments)
        // Client Profiles
        case "list_client_profiles": return try await listClientProfiles(arguments)
        case "get_client_profile": return try await getClientProfile(arguments)
        // Client Memory
        case "update_client_memory": return try await updateClientMemory(arguments)
        case "list_client_memory": return try await listClientMemory(arguments)
        // Scoring
        case "get_beat_patterns": return try await getBeatPatterns(arguments)
        case "score_draft": return try await scoreDraft(arguments)
        // Insight Memory (WP6)
        case "save_analysis": return try await saveAnalysis(arguments)
        case "get_saved_analyses": return try await getSavedAnalyses(arguments)
        // Lessons / Skills
        case "save_lessons": return try await saveLessons(arguments)
        case "get_lessons": return try await getLessons(arguments)
        case "update_skill": return try await updateSkill(arguments)
        case "delete_skill": return try await deleteSkill(arguments)
        // Module Management
        case "suggest_module_addition": return try await suggestModuleAddition(arguments)
        // Web Search
        case "web_search": return try await webSearch(arguments)
        // Automations
        case "create_automation": return try await createAutomation(arguments)
        case "list_automations": return try await listAutomations(arguments)
        case "toggle_automation": return try await toggleAutomation(arguments)
        case "delete_automation": return try await deleteAutomation(arguments)
        // Telegram UX
        case "send_telegram_buttons": return try await sendTelegramButtons(arguments)
        // In-App UX
        case "send_action_buttons": return try await sendActionButtons(arguments)
        default:
            return jsonError("Unknown tool: \(toolName)")
        }
    }

    // MARK: - Shared Context and Memory

    private func retrieveContext(_ args: [String: Any]) async throws -> String {
        guard let query = args["query"] as? String else {
            return jsonError("Missing required parameter: query")
        }

        let purpose = (args["purpose"] as? String).flatMap(RetrievalPurpose.init(rawValue:)) ?? .general
        let limit = args["limit"] as? Int ?? 8
        let sourceIDs = await activeContextSourceIDs()

        let request = ContextRetrievalRequest(
            query: query,
            conversationID: contextConversationID ?? "tool-context",
            surface: .cosmoWindow,
            purpose: purpose,
            pinnedSourceIDs: sourceIDs,
            activeAtomUUID: contextAtomUUIDs.last,
            activeClientUUID: activeClientUUID,
            maxChunks: limit,
            tokenBudget: 3_500
        )
        let results = try await CosmoRetrievalService.shared.retrieve(request)
        let payload = results.map { result in
            [
                "sourceTitle": result.source.title,
                "sourceId": result.source.id,
                "atomUUID": result.source.atomUUID ?? "",
                "anchor": result.chunk.anchor ?? "",
                "matchType": result.matchType,
                "score": result.score,
                "text": result.chunk.rawText
            ] as [String: Any]
        }
        return jsonEncode(["results": payload, "count": payload.count])
    }

    private func inspectPinnedSources(_ args: [String: Any]) async throws -> String {
        let sourceIDs = await activeContextSourceIDs()
        let sources = try await ContextIndexStore.shared.sources(ids: sourceIDs)
        let payload = sources.map { source in
            [
                "id": source.id,
                "title": source.title,
                "kind": source.kind.rawValue,
                "atomUUID": source.atomUUID ?? ""
            ]
        }
        return jsonEncode(["sources": payload, "count": payload.count])
    }

    private func rememberContext(_ args: [String: Any]) async throws -> String {
        guard let key = args["key"] as? String,
              let value = args["value"] as? String,
              let scope = args["scope"] as? String else {
            return jsonError("Missing required parameters: key, value, scope")
        }

        switch scope {
        case "core":
            try await CosmoMemoryService.shared.upsertCoreMemory(value, key: key)
        case "working":
            try await CosmoMemoryService.shared.upsertWorkingMemory(contextConversationID ?? "tool-context", value: value)
        case "archival":
            try await CosmoMemoryService.shared.addArchivalMemory(value)
        default:
            return jsonError("Invalid scope: \(scope)")
        }

        return jsonEncode(["success": true, "scope": scope, "key": key])
    }

    private func searchMemory(_ args: [String: Any]) async throws -> String {
        guard let query = args["query"] as? String else {
            return jsonError("Missing required parameter: query")
        }
        let limit = args["limit"] as? Int ?? 5
        let archival = try await CosmoMemoryService.shared.searchArchivalMemory(query: query, limit: limit)
        let core = try await CosmoMemoryService.shared.coreMemory()
        let working = try await CosmoMemoryService.shared.workingMemory(conversationID: contextConversationID ?? "tool-context")
        let lower = query.lowercased()
        let visible = (core + working).filter { lower.isEmpty || $0.lowercased().contains(lower) }
        let results = Array((visible + archival).prefix(limit))
        return jsonEncode(["results": results, "count": results.count])
    }

    private func activeContextSourceIDs() async -> [String] {
        var ids = contextSourceIDs
        for uuid in contextAtomUUIDs {
            if let sourceID = await ContextIndexStore.shared.sourceID(atomUUID: uuid),
               !ids.contains(sourceID) {
                ids.append(sourceID)
            }
        }
        return ids
    }

    private func rememberContextAtom(_ atom: Atom) async {
        guard let sourceID = try? await ContextIndexStore.shared.upsert(atom: atom, pinState: .pinned) else { return }
        if !contextSourceIDs.contains(sourceID) {
            contextSourceIDs.append(sourceID)
        }
        if !contextAtomUUIDs.contains(atom.uuid) {
            contextAtomUUIDs.append(atom.uuid)
        }
    }

    private func rememberContextAtomUUIDs(_ uuids: [String]) async {
        for uuid in uuids {
            guard let atom = try? await atomRepo.fetch(uuid: uuid) else { continue }
            await rememberContextAtom(atom)
        }
    }

    private func rememberContextAtoms(_ atoms: [Atom]) async {
        for atom in atoms {
            await rememberContextAtom(atom)
        }
    }

    private func sharedWritingContextBlock(
        contentUUID: String,
        prompt: String,
        clientName: String?
    ) async -> String? {
        if let contentAtom = try? await atomRepo.fetch(uuid: contentUUID) {
            await rememberContextAtom(contentAtom)
        }
        if let clientName, !clientName.isEmpty,
           let clientAtom = try? await atomRepo.fuzzyFindClient(query: clientName) {
            await rememberContextAtom(clientAtom)
        }

        let sourceIDs = await activeContextSourceIDs()
        let coreMemory = (try? await CosmoMemoryService.shared.coreMemory()) ?? []
        let workingMemory = (try? await CosmoMemoryService.shared.workingMemory(conversationID: contextConversationID ?? "writing-\(contentUUID)")) ?? []
        let request = ContextRetrievalRequest(
            query: prompt,
            conversationID: contextConversationID ?? "writing-\(contentUUID)",
            surface: .writingMode,
            purpose: .writing,
            pinnedSourceIDs: sourceIDs,
            activeAtomUUID: contentUUID,
            activeClientUUID: nil,
            maxChunks: 10,
            tokenBudget: 6_000
        )
        let retrievalResults = ((try? await CosmoRetrievalService.shared.retrieve(request)) ?? [])
        guard !retrievalResults.isEmpty || !coreMemory.isEmpty || !workingMemory.isEmpty else {
            return nil
        }

        let pack = ContextPackAssembler.assemble(
            request: request,
            retrievalResults: retrievalResults,
            coreMemory: coreMemory,
            workingMemory: workingMemory,
            recallMemory: []
        )
        return pack.promptBlock
    }

    nonisolated static func mergeWritingContext(_ text: String?, contextBlock: String?) -> String? {
        let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContext = contextBlock?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (trimmedText?.isEmpty == false ? trimmedText : nil, trimmedContext?.isEmpty == false ? trimmedContext : nil) {
        case let (text?, context?):
            return [text, context].joined(separator: "\n\n")
        case let (text?, nil):
            return text
        case let (nil, context?):
            return context
        case (nil, nil):
            return nil
        }
    }

    // MARK: - Ideas

    private func searchIdeas(_ args: [String: Any]) async throws -> String {
        guard let query = args["query"] as? String else {
            return jsonError("Missing required parameter: query")
        }
        let limit = args["limit"] as? Int ?? 10

        do {
            let results = try await HybridSearchEngine.shared.search(
                query: query,
                limit: limit,
                entityTypes: [.idea]
            )
            let items: [[String: Any]] = results.map { result in
                [
                    "uuid": result.entityUUID ?? "",
                    "title": result.title,
                    "preview": result.preview
                ]
            }
            await rememberContextAtomUUIDs(results.compactMap(\.entityUUID))
            return jsonEncode(["results": items, "count": items.count])
        } catch {
            // Fallback to AtomRepository keyword search + client match
            let atoms = try await atomRepo.fetchAll(type: .idea)
            let q = query.lowercased()

            // Check if query matches a client name
            let clientAtom = try? await atomRepo.fuzzyFindClient(query: query)

            let matching = atoms.filter { atom in
                let title = (atom.title ?? "").lowercased()
                let body = (atom.body ?? "").lowercased()
                let textMatch = title.contains(q) || body.contains(q)
                let clientMatch = clientAtom != nil && atom.ideaClientUUID == clientAtom?.uuid
                return textMatch || clientMatch
            }.prefix(limit)

            let items: [[String: Any]] = matching.map { atom in
                [
                    "uuid": atom.uuid,
                    "title": atom.title ?? "Untitled",
                    "preview": String((atom.body ?? "").prefix(200))
                ]
            }
            return jsonEncode(["results": items, "count": items.count])
        }
    }

    private func getIdea(_ args: [String: Any]) async throws -> String {
        guard let uuid = args["uuid"] as? String else {
            return jsonError("Missing required parameter: uuid")
        }
        guard let atom = try await atomRepo.fetch(uuid: uuid) else {
            return jsonError("Idea not found: \(uuid)")
        }
        await rememberContextAtom(atom)
        return jsonEncode(atomToDict(atom))
    }

    private func createIdea(_ args: [String: Any]) async throws -> String {
        guard let title = args["title"] as? String else {
            return jsonError("Missing required parameter: title")
        }
        let body = args["body"] as? String

        let atom = try await atomRepo.create(
            type: .idea,
            title: title,
            body: body
        )
        return jsonEncode([
            "success": true,
            "uuid": atom.uuid,
            "title": atom.title ?? title,
            "message": "Idea created: \(title)"
        ] as [String: Any])
    }

    private func updateIdea(_ args: [String: Any]) async throws -> String {
        guard let uuid = args["uuid"] as? String else {
            return jsonError("Missing required parameter: uuid")
        }
        guard let updated = try await atomRepo.update(uuid: uuid, updates: { atom in
            if let title = args["title"] as? String { atom.title = title }
            if let body = args["body"] as? String { atom.body = body }
            if let status = args["status"] as? String {
                // Update idea status in metadata
                var metaDict = (atom.metadataDict ?? [:])
                metaDict["ideaStatus"] = status
                if let data = try? JSONSerialization.data(withJSONObject: metaDict),
                   let json = String(data: data, encoding: .utf8) {
                    atom.metadata = json
                }
            }
        }) else {
            return jsonError("Idea not found: \(uuid)")
        }
        return jsonEncode([
            "success": true,
            "uuid": updated.uuid,
            "title": updated.title ?? "",
            "message": "Idea updated"
        ] as [String: Any])
    }

    private func activateIdea(_ args: [String: Any]) async throws -> String {
        guard let uuid = args["uuid"] as? String else {
            return jsonError("Missing required parameter: uuid")
        }
        guard let ideaAtom = try await atomRepo.fetch(uuid: uuid) else {
            return jsonError("Idea not found: \(uuid)")
        }

        // Run full analysis to get swipe matches, hooks, framework recommendations.
        // fullAnalysis returns IdeaInsight (non-optional) — may have nil sub-fields if analysis is thin.
        let insight = await IdeaInsightEngine.shared.fullAnalysis(atom: ideaAtom)

        // Extract idea metadata for context carry-through
        let ideaMeta = ideaAtom.metadataDict ?? [:]
        let clientUUID = ideaMeta["clientUUID"] as? String
        let platform = ideaMeta["platform"] as? String

        // Build rich content metadata with inherited context
        var contentMeta: [String: Any] = [
            "phase": "ideation",
            "sourceIdeaUUID": uuid,
            "wordCount": 0,
            "activatedAt": ISO8601DateFormatter().string(from: Date())
        ]
        if let clientUUID = clientUUID { contentMeta["clientProfileUUID"] = clientUUID }
        if let platform = platform { contentMeta["platform"] = platform }

        // Inherit swipe UUIDs: merge user-linked swipes + analysis-matched swipes (deduplicated)
        var allSwipeUUIDs: [String] = []
        // First: user's explicitly linked swipes (highest priority)
        if let linkedIds = ideaAtom.ideaMetadata?.linkedSwipeIds {
            allSwipeUUIDs.append(contentsOf: linkedIds)
        }
        // Then: analysis-matched swipes (may overlap)
        if let matchingSwipes = insight.matchingSwipes, !matchingSwipes.isEmpty {
            for match in matchingSwipes {
                if !allSwipeUUIDs.contains(match.swipeAtomUUID) {
                    allSwipeUUIDs.append(match.swipeAtomUUID)
                }
            }
        }
        let matchedSwipeCount = allSwipeUUIDs.count
        if !allSwipeUUIDs.isEmpty {
            contentMeta["inheritedSwipeUUIDs"] = allSwipeUUIDs
        }

        // Inherit framework from analysis
        var inheritedFramework: String?
        if let frameworks = insight.frameworkRecommendations, let first = frameworks.first {
            contentMeta["inheritedFramework"] = first.framework.rawValue
            inheritedFramework = first.framework.rawValue
        }

        // Inherit hooks from analysis
        var hookCount = 0
        if let hookSuggestions = insight.hookSuggestions, !hookSuggestions.isEmpty {
            let hookTexts = hookSuggestions.map { $0.hookText }
            contentMeta["inheritedHooks"] = hookTexts
            hookCount = hookTexts.count
        }

        let metaJSON: String?
        if let data = try? JSONSerialization.data(withJSONObject: contentMeta),
           let json = String(data: data, encoding: .utf8) {
            metaJSON = json
        } else {
            metaJSON = nil
        }

        // Build links
        var links: [AtomLink] = [
            AtomLink(type: "ideaToContent", uuid: uuid, entityType: "idea")
        ]
        if let clientUUID = clientUUID {
            links.append(AtomLink.contentToClient(clientUUID))
        }

        // Create content atom with full inherited context
        let contentAtom = try await atomRepo.create(
            type: .content,
            title: ideaAtom.title,
            body: ideaAtom.body,
            metadata: metaJSON,
            links: links
        )

        // Update idea status to activated
        _ = try await atomRepo.update(uuid: uuid, updates: { atom in
            var metaDict = (atom.metadataDict ?? [:])
            metaDict["ideaStatus"] = "activated"
            if let data = try? JSONSerialization.data(withJSONObject: metaDict),
               let json = String(data: data, encoding: .utf8) {
                atom.metadata = json
            }
        })

        return jsonEncode([
            "success": true,
            "ideaUUID": uuid,
            "contentUUID": contentAtom.uuid,
            "matchedSwipes": matchedSwipeCount,
            "framework": inheritedFramework ?? "",
            "hookCount": hookCount,
            "message": "Idea activated with \(matchedSwipeCount) matched swipes, \(hookCount) hooks, and framework: \(inheritedFramework ?? "none")"
        ] as [String: Any])
    }

    // MARK: - Client Search

    private func searchByClient(_ args: [String: Any]) async throws -> String {
        guard let clientName = args["clientName"] as? String else {
            return jsonError("Missing required parameter: clientName")
        }
        let entityType = args["entityType"] as? String

        // Resolve client profile by fuzzy name match
        guard let clientAtom = try await atomRepo.fuzzyFindClient(query: clientName) else {
            return jsonEncode([
                "results": [] as [[String: Any]],
                "count": 0,
                "message": "No client profile found matching '\(clientName)'"
            ] as [String: Any])
        }
        let clientUUID = clientAtom.uuid
        let resolvedName = clientAtom.title ?? clientName

        var results: [[String: Any]] = []

        // Search ideas tagged for this client
        if entityType == nil || entityType == "idea" {
            let ideas = try await atomRepo.fetchAll(type: .idea)
            let clientIdeas = ideas.filter { $0.ideaClientUUID == clientUUID }
            for atom in clientIdeas {
                results.append([
                    "uuid": atom.uuid,
                    "type": "idea",
                    "title": atom.title ?? "Untitled",
                    "preview": String((atom.body ?? "").prefix(200))
                ] as [String: Any])
            }
        }

        // Search swipes tagged for this client via swipeToClient links
        if entityType == nil || entityType == "swipe" {
            let swipes = try await atomRepo.fetchAll(type: .research)
            let clientSwipes = swipes.filter { atom in
                guard atom.isSwipeFileAtom else { return false }
                let links = atom.linksList
                return links.contains { $0.type == AtomLinkType.swipeToClient.rawValue && $0.uuid == clientUUID }
            }
            for atom in clientSwipes {
                results.append([
                    "uuid": atom.uuid,
                    "type": "swipe",
                    "title": atom.title ?? "Untitled",
                    "preview": String((atom.body ?? "").prefix(200))
                ] as [String: Any])
            }
        }

        // Search content tagged for this client via contentToClient links
        if entityType == nil || entityType == "content" {
            let content = try await atomRepo.fetchAll(type: .content)
            let clientContent = content.filter { atom in
                let links = atom.linksList
                return links.contains { $0.type == AtomLinkType.contentToClient.rawValue && $0.uuid == clientUUID }
            }
            for atom in clientContent {
                results.append([
                    "uuid": atom.uuid,
                    "type": "content",
                    "title": atom.title ?? "Untitled",
                    "preview": String((atom.body ?? "").prefix(200))
                ] as [String: Any])
            }
        }

        return jsonEncode([
            "clientName": resolvedName,
            "clientUUID": clientUUID,
            "results": results,
            "count": results.count
        ] as [String: Any])
    }

    // MARK: - Swipes

    private func searchSwipes(_ args: [String: Any]) async throws -> String {
        guard let query = args["query"] as? String else {
            return jsonError("Missing required parameter: query")
        }
        let limit = args["limit"] as? Int ?? 10

        do {
            let results = try await HybridSearchEngine.shared.search(
                query: query,
                limit: limit,
                entityTypes: [.swipeFile]
            )
            let items: [[String: Any]] = results.map { result in
                [
                    "uuid": result.entityUUID ?? "",
                    "title": result.title,
                    "preview": result.preview
                ]
            }
            return jsonEncode(["results": items, "count": items.count])
        } catch {
            // Fallback to keyword search on research atoms that are swipe files + client match
            let atoms = try await atomRepo.fetchAll(type: .research)
            let swipes = atoms.filter { $0.isSwipeFileAtom }
            let q = query.lowercased()

            // Check if query matches a client name
            let clientAtom = try? await atomRepo.fuzzyFindClient(query: query)

            let matching = Array(swipes.filter { atom in
                let title = (atom.title ?? "").lowercased()
                let body = (atom.body ?? "").lowercased()
                // Also search structured JSON (catches hookText, framework names, transcript for IG)
                let structuredText = (atom.structured ?? "").lowercased()
                // Also search metadata JSON (catches hook, emotionTone, structureType)
                let metadataText = (atom.metadata ?? "").lowercased()
                let textMatch = title.contains(q) || body.contains(q)
                    || structuredText.contains(q) || metadataText.contains(q)
                let clientMatch: Bool
                if let clientUUID = clientAtom?.uuid {
                    clientMatch = atom.linksList.contains { $0.type == AtomLinkType.swipeToClient.rawValue && $0.uuid == clientUUID }
                } else {
                    clientMatch = false
                }
                return textMatch || clientMatch
            }.prefix(limit))
            await rememberContextAtoms(matching)

            let items: [[String: Any]] = matching.map { atom in
                var item: [String: Any] = [
                    "uuid": atom.uuid,
                    "title": atom.title ?? "Untitled",
                    "preview": String((atom.body ?? "").prefix(200))
                ]
                // Include analysis summary for richer results (human-readable, no scores)
                if let analysis = atom.swipeAnalysis {
                    item["hookType"] = analysis.hookType?.rawValue ?? ""
                    item["frameworkType"] = analysis.frameworkType?.rawValue ?? ""
                    item["hookText"] = analysis.hookText ?? ""
                    item["format"] = analysis.swipeContentFormat?.rawValue ?? ""
                }
                return item
            }
            return jsonEncode(["results": items, "count": items.count])
        }
    }

    private func getSwipeAnalysis(_ args: [String: Any]) async throws -> String {
        guard let uuid = args["uuid"] as? String else {
            return jsonError("Missing required parameter: uuid")
        }
        guard let atom = try await atomRepo.fetch(uuid: uuid) else {
            return jsonError("Swipe file not found: \(uuid)")
        }
        await rememberContextAtom(atom)

        var result = atomToDict(atom)

        // Include swipe analysis from structured field
        if let structured = atom.structured,
           let data = structured.data(using: .utf8),
           let analysis = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            result["analysis"] = analysis
        }

        return jsonEncode(result)
    }

    private func findSimilarSwipes(_ args: [String: Any]) async throws -> String {
        guard let query = args["query"] as? String else {
            return jsonError("Missing required parameter: query")
        }
        let limit = args["limit"] as? Int ?? 5

        do {
            let results = try await HybridSearchEngine.shared.search(
                query: query,
                limit: limit,
                entityTypes: [.swipeFile]
            )
            let items: [[String: Any]] = results.map { result in
                [
                    "uuid": result.entityUUID ?? "",
                    "title": result.title,
                    "preview": result.preview
                ]
            }
            await rememberContextAtomUUIDs(results.compactMap(\.entityUUID))
            // Results are ordered by relevance (most similar first)
            return jsonEncode(["results": items, "count": items.count])
        } catch {
            return jsonError("Search failed: \(error.localizedDescription)")
        }
    }

    private func getSwipeStats(_ args: [String: Any]) async throws -> String {
        let atoms = try await atomRepo.fetchAll(type: .research)
        let swipes = atoms.filter { $0.isSwipeFileAtom }

        var hookCounts: [String: Int] = [:]
        var frameworkCounts: [String: Int] = [:]

        for atom in swipes {
            // Check SwipeAnalysis in structured JSON first (canonical source)
            if let analysis = atom.swipeAnalysis {
                if let hookType = analysis.hookType {
                    hookCounts[hookType.rawValue, default: 0] += 1
                }
                if let frameworkType = analysis.frameworkType {
                    frameworkCounts[frameworkType.rawValue, default: 0] += 1
                }
            } else {
                // Fallback to metadata dict
                let metaDict = (atom.metadataDict ?? [:])
                if let hook = metaDict["hookType"] as? String {
                    hookCounts[hook, default: 0] += 1
                }
                if let framework = metaDict["framework"] as? String {
                    frameworkCounts[framework, default: 0] += 1
                }
            }
        }

        let topHooks = hookCounts.sorted { $0.value > $1.value }.prefix(5).map { ["hook": $0.key, "count": $0.value] as [String: Any] }
        let topFrameworks = frameworkCounts.sorted { $0.value > $1.value }.prefix(5).map { ["framework": $0.key, "count": $0.value] as [String: Any] }

        return jsonEncode([
            "totalSwipes": swipes.count,
            "topHooks": topHooks,
            "topFrameworks": topFrameworks
        ] as [String: Any])
    }

    // MARK: - Swipe Adaptation

    private func adaptSwipesForClient(_ args: [String: Any]) async throws -> String {
        guard let clientName = args["clientName"] as? String else {
            return jsonError("Missing required parameter: clientName")
        }
        let timeFilter = args["timeFilter"] as? String
        let maxResults = min(args["maxResults"] as? Int ?? 10, 25)

        onToolActivity?(.started(name: "adapt_swipes_for_client", displayLabel: "Scoring swipe library for \(clientName)...", args: ["clientName": clientName]))

        do {
            let result = try await SwipeAdaptationEngine.shared.adaptSwipesForClient(
                clientName: clientName,
                timeFilter: timeFilter,
                maxResults: maxResults
            )

            let ideas: [[String: Any]] = result.adaptedIdeas.enumerated().map { (idx, idea) in
                // Map sourceIndex back to source swipe title
                let sourceTitle: String
                if idea.sourceIndex >= 1 && idea.sourceIndex <= result.sourceSwipes.count {
                    sourceTitle = result.sourceSwipes[idea.sourceIndex - 1].title
                } else {
                    sourceTitle = "Unknown source"
                }

                return [
                    "adaptedHook": idea.adaptedHook,
                    "hookVariants": idea.hookVariants ?? [idea.adaptedHook],
                    "ideaTitle": idea.ideaTitle,
                    "ideaBody": idea.ideaBody,
                    "sourceSwipeTitle": sourceTitle,
                    "hookType": idea.hookType,
                    "suggestedFramework": idea.suggestedFramework,
                    "adaptationReasoning": idea.adaptationReasoning,
                    "whyItWorks": idea.whyItWorks ?? idea.adaptationReasoning,
                    "confidence": idea.confidence
                ] as [String: Any]
            }

            var response: [String: Any] = [
                "clientName": result.clientName,
                "totalSwipesScanned": result.totalSwipesScanned,
                "candidatesEvaluated": result.candidatesEvaluated,
                "adaptedIdeas": ideas,
                "count": ideas.count,
                "timeFilter": result.timeFilter ?? "all time"
            ]

            if let engineError = result.engineError {
                response["error"] = engineError
                response["message"] = "The adaptation engine encountered an error. The ideas below may be incomplete."
            }

            if ideas.isEmpty && result.candidatesEvaluated > 0 {
                response["warning"] = "Screening found \(result.candidatesEvaluated) candidates but adaptation generated 0 ideas. This likely indicates an API error."
            }

            return jsonEncode(response as [String: Any])
        } catch {
            return jsonError("Swipe adaptation failed: \(error.localizedDescription)")
        }
    }

    // MARK: - List All Swipes

    private func listAllSwipes(_ args: [String: Any]) async throws -> String {
        let limit = args["limit"] as? Int ?? 50
        let offset = args["offset"] as? Int ?? 0

        let atoms = try await atomRepo.fetchAll(type: .research)
        let swipes = atoms.filter { $0.isSwipeFileAtom }

        let page = Array(swipes.dropFirst(offset).prefix(limit))
        await rememberContextAtoms(page)

        let items: [[String: Any]] = page.map { atom in
            var item: [String: Any] = [
                "uuid": atom.uuid,
                "title": atom.title ?? "Untitled"
            ]
            if let analysis = atom.swipeAnalysis {
                item["hookText"] = analysis.hookText ?? ""
                item["hookType"] = analysis.hookType?.rawValue ?? ""
                item["frameworkType"] = analysis.frameworkType?.rawValue ?? ""
                item["dominantEmotion"] = analysis.dominantEmotion?.rawValue ?? ""
                item["format"] = analysis.swipeContentFormat?.rawValue ?? ""
            }
            let metaDict = atom.metadataDict ?? [:]
            item["platform"] = metaDict["contentSource"] as? String ?? ""
            return item
        }

        return jsonEncode([
            "results": items,
            "count": items.count,
            "total": swipes.count,
            "offset": offset,
            "hasMore": offset + limit < swipes.count
        ] as [String: Any])
    }

    // MARK: - Filter Swipes by Taxonomy

    private func filterSwipesByTaxonomy(_ args: [String: Any]) async throws -> String {
        let hookTypeFilter = args["hookType"] as? String
        let frameworkFilter = args["frameworkType"] as? String
        let emotionFilter = args["emotion"] as? String
        let platformFilter = args["platform"] as? String
        let formatFilter = args["format"] as? String

        let atoms = try await atomRepo.fetchAll(type: .research)
        let swipes = atoms.filter { $0.isSwipeFileAtom }

        let matching = swipes.filter { atom in
            guard let analysis = atom.swipeAnalysis else { return false }

            if let hookTypeFilter = hookTypeFilter,
               analysis.hookType?.rawValue != hookTypeFilter { return false }
            if let frameworkFilter = frameworkFilter,
               analysis.frameworkType?.rawValue != frameworkFilter { return false }
            if let emotionFilter = emotionFilter,
               analysis.dominantEmotion?.rawValue != emotionFilter { return false }
            if let platformFilter = platformFilter {
                let metaDict = atom.metadataDict ?? [:]
                let source = metaDict["contentSource"] as? String ?? ""
                if source != platformFilter { return false }
            }
            if let formatFilter = formatFilter {
                let swipeFormat = analysis.swipeContentFormat?.rawValue ?? ""
                if swipeFormat != formatFilter { return false }
            }

            return true
        }

        let items: [[String: Any]] = matching.map { atom in
            var item: [String: Any] = [
                "uuid": atom.uuid,
                "title": atom.title ?? "Untitled"
            ]
            if let analysis = atom.swipeAnalysis {
                item["hookText"] = analysis.hookText ?? ""
                item["hookType"] = analysis.hookType?.rawValue ?? ""
                item["frameworkType"] = analysis.frameworkType?.rawValue ?? ""
                item["dominantEmotion"] = analysis.dominantEmotion?.rawValue ?? ""
                item["format"] = analysis.swipeContentFormat?.rawValue ?? ""
            }
            return item
        }

        return jsonEncode([
            "results": items,
            "count": items.count
        ] as [String: Any])
    }

    // MARK: - Capture

    private func captureSwipe(_ args: [String: Any]) async throws -> String {
        guard let input = args["url"] as? String else {
            return jsonError("Missing required parameter: url")
        }
        let userHook = args["hook"] as? String
        let notes = args["notes"] as? String
        let clientName = args["clientName"] as? String

        let classifier = SwipeURLClassifier()
        let classification = classifier.classify(input)

        var item: Atom
        var sourceLabel = classification.sourceType.displayName

        switch classification.sourceType {
        case .youtube, .youtubeShort:
            guard let videoId = classification.contentId else {
                return jsonError("Could not extract YouTube video ID from URL")
            }
            item = Research.swipeFromYouTube(
                videoId: videoId,
                url: input,
                hook: userHook,
                isShort: classification.sourceType == .youtubeShort
            )
            item.thumbnailUrl = "https://img.youtube.com/vi/\(videoId)/maxresdefault.jpg"

            // Fetch metadata via oEmbed
            do {
                let metadata = try await YouTubeProcessor.shared.fetchMetadata(videoId: videoId)
                item.title = metadata.title
                var richContent = item.richContent ?? ResearchRichContent()
                richContent.title = metadata.title
                richContent.author = metadata.channelName
                richContent.thumbnailUrl = item.thumbnailUrl
                item.setRichContent(richContent)
            } catch {
                print("Agent: YouTube oEmbed failed (non-fatal): \(error)")
            }

            // Fetch transcript
            let segments = await YouTubeProcessor.shared.fetchCaptions(videoId: videoId)
            if let segments = segments, !segments.isEmpty {
                let fullText = segments.map(\.text).joined(separator: " ")
                var richContent = item.richContent ?? ResearchRichContent()
                richContent.transcript = fullText
                richContent.transcriptStatus = "available"
                item.setRichContent(richContent)
                if userHook == nil, let firstLine = fullText.components(separatedBy: .newlines).first {
                    item.hook = String(firstLine.prefix(200))
                }
                item.summary = String(fullText.prefix(500))
                item.body = segments.jsonString
                item.processingStatus = "complete"
            }
            sourceLabel = "YouTube"

        case .instagramReel, .instagramPost, .instagramCarousel:
            let igType: ResearchRichContent.InstagramContentType
            switch classification.sourceType {
            case .instagramReel: igType = .reel
            case .instagramCarousel: igType = .carousel
            default: igType = .post
            }
            item = Research.swipeFromInstagram(
                instagramId: classification.contentId ?? UUID().uuidString,
                url: input,
                hook: userHook,
                type: igType
            )
            // Attempt oEmbed metadata
            let encoded = input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input
            if let oEmbedURL = URL(string: "https://api.instagram.com/oembed/?url=\(encoded)") {
                do {
                    let (data, _) = try await URLSession.shared.data(from: oEmbedURL)
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let title = json["title"] as? String, !title.isEmpty {
                            item.title = title
                            if userHook == nil { item.hook = String(title.prefix(200)) }
                        }
                        if let authorName = json["author_name"] as? String {
                            var richContent = item.richContent ?? ResearchRichContent()
                            richContent.author = authorName
                            item.setRichContent(richContent)
                        }
                    }
                } catch {
                    print("Agent: Instagram oEmbed failed (non-fatal): \(error)")
                }
            }
            // Attempt media extraction to detect carousel items and get caption/thumbnail
            if let igURL = URL(string: input) {
                do {
                    let mediaData = try await InstagramMediaCache.shared.getMedia(for: igURL)
                    let isIncompletePostMedia = InstagramMediaResolution.isIncompletePostMedia(
                        mediaData: mediaData,
                        sourceURL: igURL
                    )
                    var richContent = item.richContent ?? ResearchRichContent()
                    var igData = richContent.instagramData ?? InstagramData(
                        originalURL: igURL,
                        contentType: igType == .reel ? .reel : (igType == .carousel ? .carousel : .image)
                    )
                    if let author = mediaData.authorUsername, !author.isEmpty {
                        richContent.author = author
                        igData.authorUsername = author
                    }
                    if let caption = mediaData.caption, !caption.isEmpty {
                        igData.caption = caption
                        if (item.title ?? "").isEmpty || item.title == "Instagram" {
                            item.title = String(caption.prefix(100))
                            if userHook == nil { item.hook = String(caption.prefix(200)) }
                        }
                    }
                    if !isIncompletePostMedia,
                       let thumb = mediaData.thumbnailURL?.absoluteString, !thumb.isEmpty {
                        item.thumbnailUrl = thumb
                        richContent.thumbnailUrl = thumb
                    }
                    if !isIncompletePostMedia {
                        igData.extractedMediaURL = mediaData.videoURL
                        igData.extractedAt = mediaData.extractedAt
                        igData.expectedCarouselItemCount = mediaData.expectedCarouselItemCount
                    }
                    if !isIncompletePostMedia,
                       let carouselItems = mediaData.carouselItems, !carouselItems.isEmpty {
                        igData.carouselItems = carouselItems
                        richContent.sourceType = .instagramCarousel
                        richContent.instagramType = "carousel"
                        let shortcode = classification.contentId ?? InstagramExtractor.shared.extractShortcode(from: igURL)
                        let cachedSlideCount = await InstagramCarouselImageCache.cacheCarouselImages(
                            items: carouselItems,
                            shortcode: shortcode
                        )
                        if cachedSlideCount > 0 {
                            print("Agent: Cached \(cachedSlideCount) carousel media images for \(shortcode ?? "unknown")")
                        }
                        if item.thumbnailUrl == nil || item.thumbnailUrl?.isEmpty == true {
                            if let firstImage = carouselItems.first(where: { $0.mediaType == .image }) {
                                item.thumbnailUrl = firstImage.mediaURL.absoluteString
                                richContent.thumbnailUrl = firstImage.mediaURL.absoluteString
                            }
                        }
                    }
                    richContent.instagramData = igData
                    item.setRichContent(richContent)
                } catch {
                    print("Agent: Instagram media extraction failed (non-fatal): \(error)")
                }
            }
            item.processingStatus = "pending"
            sourceLabel = "Instagram"

        case .xPost, .twitter:
            guard let tweetId = classification.contentId else {
                return jsonError("Could not extract tweet ID from URL")
            }
            item = Research.swipeFromXPost(tweetId: tweetId, url: input, hook: userHook)
            do {
                let embedResult = try await XEmbedFetcher.shared.fetchEmbed(url: input)
                var richContent = item.richContent ?? ResearchRichContent()
                richContent.embedHtml = embedResult.html
                richContent.author = embedResult.authorName
                item.setRichContent(richContent)
                if let tweetText = embedResult.text {
                    if userHook == nil { item.hook = String(tweetText.prefix(280)) }
                    item.title = item.hook ?? "X Post"
                    item.summary = tweetText
                }
                item.processingStatus = "complete"
            } catch {
                print("Agent: X embed fetch failed: \(error)")
                item.processingStatus = "pending"
            }
            sourceLabel = "X"

        case .threads:
            item = Research.swipeFromThreads(
                threadId: classification.contentId ?? UUID().uuidString,
                url: input,
                hook: userHook
            )
            item.title = userHook ?? "Threads Post"
            item.processingStatus = "pending"
            sourceLabel = "Threads"

        case .rawNote:
            item = Research.swipeFromRawText(text: input, hook: userHook)
            sourceLabel = "Raw Text"

        default:
            // Website or unknown URL
            item = Research.newSwipeFile(
                url: input,
                hook: userHook,
                sourceType: .website,
                contentSource: .clipboard
            )
            item.title = userHook ?? input
            item.processingStatus = "pending"
            sourceLabel = "Website"
        }

        // Apply user hook override if provided
        if let userHook = userHook, !userHook.isEmpty {
            item.hook = userHook
            if (item.title ?? "").isEmpty { item.title = userHook }
        }

        // Apply notes to body if no body exists
        if let notes = notes, !notes.isEmpty {
            if (item.body ?? "").isEmpty {
                item.body = notes
            } else {
                item.body = (item.body ?? "") + "\n\n--- Agent Notes ---\n" + notes
            }
        }

        // Mark as swipe file
        item.isSwipeFile = true
        item.contentSource = SwipeContentSource.clipboard.rawValue
        item.updatedAt = ISO8601DateFormatter().string(from: Date())

        // Save to GRDB
        do {
            let capturedItem = item
            let insertedId = try await CosmoDatabase.shared.asyncWrite { db -> Int64? in
                var dbItem = capturedItem
                try dbItem.insert(db)
                return db.lastInsertedRowID
            }
            item.id = insertedId
        } catch {
            return jsonError("Failed to save swipe: \(error.localizedDescription)")
        }

        // Generate embedding in background
        Task {
            var textToEmbed = ""
            if let hook = item.hook { textToEmbed += hook + " " }
            if let summary = item.summary { textToEmbed += summary }
            if !textToEmbed.isEmpty {
                try? await VectorDatabase.shared.index(
                    text: textToEmbed,
                    entityType: "research",
                    entityId: item.id ?? 0,
                    entityUUID: item.uuid
                )
            }
        }

        // Tag for client if clientName provided
        var resolvedClientName: String? = nil
        if let clientName = clientName, !clientName.isEmpty {
            if let clientAtom = try? await atomRepo.fuzzyFindClient(query: clientName) {
                resolvedClientName = clientAtom.title ?? clientName
                let clientUUID = clientAtom.uuid
                // Add swipeToClient link + update swipe analysis with clientUUID
                _ = try? await atomRepo.update(uuid: item.uuid, updates: { atom in
                    // Add link
                    var links = atom.linksList
                    links.append(AtomLink.swipeToClient(clientUUID))
                    atom.links = try? String(data: JSONEncoder().encode(links), encoding: .utf8)
                    // Update swipe analysis clientUUID
                    if let structured = atom.structured,
                       let data = structured.data(using: .utf8),
                       var analysis = try? JSONDecoder().decode(SwipeAnalysis.self, from: data) {
                        analysis.clientUUID = clientUUID
                        atom.structured = try? String(data: JSONEncoder().encode(analysis), encoding: .utf8)
                    }
                })

                // Check if this source type has hit a batch analysis threshold (every 30 swipes of same type)
                let swipeSourceType = item.sourceType?.rawValue ?? sourceLabel.lowercased()
                await checkBatchSwipeThreshold(sourceType: swipeSourceType)
            }
        }

        // Auto-link to matching ideas in background
        if let savedAtom = try? await atomRepo.fetch(uuid: item.uuid) {
            Task {
                await IdeaInsightEngine.shared.findIdeasForSwipe(swipeAtom: savedAtom)
            }
        }

        // Post notification for UI updates
        NotificationCenter.default.post(
            name: .researchCreated,
            object: nil,
            userInfo: ["research": item, "uuid": item.uuid]
        )

        // Auto-process swipe in background (transcription + analysis)
        if item.processingStatus == "pending" {
            SwipeProcessingService.shared.processSwipeInBackground(uuid: item.uuid)
        }

        var responseDict: [String: Any] = [
            "success": true,
            "uuid": item.uuid,
            "title": item.title ?? sourceLabel,
            "source": sourceLabel,
            "hook": item.hook ?? "",
            "processingStatus": item.processingStatus ?? "complete",
            "message": "Swipe captured from \(sourceLabel): \(item.title ?? "Untitled")"
        ]
        if let resolvedClientName = resolvedClientName {
            responseDict["clientName"] = resolvedClientName
        }
        return jsonEncode(responseDict)
    }

    // MARK: - Capture Swipe With Idea

    private func captureSwipeWithIdea(_ args: [String: Any]) async throws -> String {
        guard let url = args["url"] as? String else {
            return jsonError("Missing required parameter: url")
        }
        let ideaContext = args["ideaContext"] as? String
        let clientName = args["clientName"] as? String
        let userHook = args["hook"] as? String
        let userTitle = args["title"] as? String

        // 1. Capture the swipe via existing captureSwipe
        var swipeArgs: [String: Any] = ["url": url]
        if let userHook = userHook { swipeArgs["hook"] = userHook }
        if let clientName = clientName { swipeArgs["clientName"] = clientName }
        let swipeResult = try await captureSwipe(swipeArgs)

        // Parse swipe result to get UUID, title, hook
        guard let swipeData = swipeResult.data(using: .utf8),
              let swipeJSON = try? JSONSerialization.jsonObject(with: swipeData) as? [String: Any],
              swipeJSON["success"] as? Bool == true,
              let swipeUUID = swipeJSON["uuid"] as? String else {
            return swipeResult // Return the swipe error as-is
        }

        let swipeTitle = swipeJSON["title"] as? String ?? "Untitled"
        let swipeHook = swipeJSON["hook"] as? String ?? ""
        let swipeSource = swipeJSON["source"] as? String ?? ""

        // 2. Use user-provided title or generate AI title
        var ideaTitle: String
        if let userTitle = userTitle, !userTitle.isEmpty {
            // User specified an explicit title — use it directly (no AI call, faster)
            ideaTitle = userTitle
        } else if let ideaContext = ideaContext, !ideaContext.isEmpty,
                  !ideaContext.contains("\n"), ideaContext.count <= 120 {
            // ideaContext looks like a misrouted title (short, single-line) — use it directly
            ideaTitle = ideaContext
        } else {
            do {
                let titlePrompt = """
                Generate a short, compelling idea title (max 10 words) based on this swipe hook: "\(swipeHook)"
                \(ideaContext != nil ? "User context: \(ideaContext!)" : "")
                Return just the title, nothing else.
                """
                ideaTitle = try await ResearchService.shared.analyzeContent(prompt: titlePrompt)
                ideaTitle = ideaTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if ideaTitle.isEmpty { ideaTitle = swipeTitle }
            } catch {
                ideaTitle = swipeTitle
            }
        }

        // 3. Build idea body
        var ideaBody = ""
        if let ideaContext = ideaContext, !ideaContext.isEmpty {
            ideaBody += ideaContext
        }
        ideaBody += "\n\nInspired by: \(swipeHook.isEmpty ? swipeTitle : swipeHook)"
        ideaBody += "\nReference: \(url)"
        ideaBody = ideaBody.trimmingCharacters(in: .whitespacesAndNewlines)

        // 4. Map swipe source to IdeaPlatform
        let platform: IdeaPlatform? = {
            switch swipeSource.lowercased() {
            case "youtube": return .youtube
            case "instagram": return .instagram
            case "x": return .x
            case "threads": return .threads
            default: return nil
            }
        }()

        // 5. Map source to ContentFormat
        let classifier = SwipeURLClassifier()
        let classification = classifier.classify(url)
        let contentFormat: ContentFormat? = {
            switch classification.sourceType {
            case .instagramReel: return .voiceoverReel
            case .instagramCarousel: return .carousel
            case .instagramPost: return .post
            case .youtubeShort: return .reel
            case .youtube: return .youtube
            case .xPost, .twitter: return .tweet
            case .threads: return .thread
            default: return nil
            }
        }()

        // 6. Resolve client
        var resolvedClientUUID: String?
        var resolvedClientName: String?
        if let clientName = clientName, !clientName.isEmpty {
            if let clientAtom = try? await atomRepo.fuzzyFindClient(query: clientName) {
                resolvedClientUUID = clientAtom.uuid
                resolvedClientName = clientAtom.title ?? clientName
            }
        }

        // 7. Create idea atom with full metadata
        var ideaMetadata = IdeaMetadata()
        ideaMetadata.ideaStatus = .spark
        ideaMetadata.platform = platform
        ideaMetadata.contentFormat = contentFormat
        ideaMetadata.clientUUID = resolvedClientUUID
        ideaMetadata.captureSource = "telegram"
        ideaMetadata.originSwipeUUID = swipeUUID
        ideaMetadata.linkedSwipeIds = [swipeUUID]

        let metadataJSON = try? String(data: JSONEncoder().encode(ideaMetadata), encoding: .utf8)

        var ideaAtom = Atom.new(
            type: .idea,
            title: ideaTitle,
            body: ideaBody,
            metadata: metadataJSON,
            links: [
                AtomLink.ideaToSwipe(swipeUUID),
                resolvedClientUUID.map { AtomLink.ideaToClient($0) }
            ].compactMap { $0 }
        )

        // Save idea to GRDB
        do {
            let capturedIdea = ideaAtom
            let insertedId = try await CosmoDatabase.shared.asyncWrite { db -> Int64? in
                var dbItem = capturedIdea
                try dbItem.insert(db)
                return db.lastInsertedRowID
            }
            ideaAtom.id = insertedId
        } catch {
            return jsonError("Swipe captured but failed to create idea: \(error.localizedDescription)")
        }

        // 8. Add reverse link on the swipe (swipeToIdea)
        _ = try? await atomRepo.update(uuid: swipeUUID, updates: { atom in
            var links = atom.linksList
            links.append(AtomLink.swipeToIdea(ideaAtom.uuid))
            atom.links = try? String(data: JSONEncoder().encode(links), encoding: .utf8)
        })

        // 9. Generate embedding for the idea in background
        Task {
            let textToEmbed = [ideaTitle, ideaBody].joined(separator: " ")
            try? await VectorDatabase.shared.index(
                text: textToEmbed,
                entityType: "idea",
                entityId: ideaAtom.id ?? 0,
                entityUUID: ideaAtom.uuid
            )
        }

        // Post notification for UI updates
        NotificationCenter.default.post(
            name: CosmoNotification.Entity.created,
            object: nil,
            userInfo: ["atom": ideaAtom, "uuid": ideaAtom.uuid, "type": "idea"]
        )

        // 10. Batch tracking — check if we should batch confirmations
        let now = Date()
        recentIdeaCaptures.append((timestamp: now, title: ideaTitle, clientName: resolvedClientName))
        // Prune captures older than 2 minutes
        recentIdeaCaptures = recentIdeaCaptures.filter { now.timeIntervalSince($0.timestamp) < 120 }

        if recentIdeaCaptures.count >= 3 {
            // Batch confirmation
            let count = recentIdeaCaptures.count
            let clientLabel = resolvedClientName ?? "your inbox"
            let batchResponse: [String: Any] = [
                "success": true,
                "batch": true,
                "swipeUUID": swipeUUID,
                "ideaUUID": ideaAtom.uuid,
                "ideaTitle": ideaTitle,
                "count": count,
                "message": "Captured \(count) swipes and created \(count) ideas for \(clientLabel). They're waiting in your Ideas inbox."
            ]
            return jsonEncode(batchResponse)
        }

        // 11. Individual confirmation
        let clientSuffix = resolvedClientName.map { " for \($0)" } ?? ""
        let responseDict: [String: Any] = [
            "success": true,
            "swipeUUID": swipeUUID,
            "ideaUUID": ideaAtom.uuid,
            "ideaTitle": ideaTitle,
            "swipeTitle": swipeTitle,
            "clientName": resolvedClientName ?? "",
            "message": "Got it! I captured the swipe and created an idea\(clientSuffix): \"\(ideaTitle)\". The swipe is linked as structural inspiration. When you're at your desk, it'll be ready in your Ideas inbox with hook suggestions from the linked swipe."
        ]
        return jsonEncode(responseDict)
    }

    private func captureResearch(_ args: [String: Any]) async throws -> String {
        guard let title = args["title"] as? String else {
            return jsonError("Missing required parameter: title")
        }
        let url = args["url"] as? String
        let body = args["body"] as? String

        // Determine source type from URL if provided
        var sourceType: ResearchRichContent.SourceType? = nil
        if let url = url {
            let classifier = SwipeURLClassifier()
            let classification = classifier.classify(url)
            sourceType = classification.sourceType
        }

        var item = Research.new(
            title: title,
            url: url,
            sourceType: sourceType
        )
        item.body = body
        item.updatedAt = ISO8601DateFormatter().string(from: Date())

        // Save to GRDB
        do {
            let capturedItem = item
            let insertedId = try await CosmoDatabase.shared.asyncWrite { db -> Int64? in
                var dbItem = capturedItem
                try dbItem.insert(db)
                return db.lastInsertedRowID
            }
            item.id = insertedId
        } catch {
            return jsonError("Failed to save research: \(error.localizedDescription)")
        }

        // Run full URL processing (title, transcript, thumbnail) — same pipeline as Command-K
        if let urlString = url,
           let parsedURL = URL(string: urlString),
           let itemId = item.id {
            let urlType = URLClassifier.classify(parsedURL)
            do {
                try await ResearchProcessor.shared.processURL(into: itemId, url: parsedURL, type: urlType)
                if let processed = try? await atomRepo.fetch(uuid: item.uuid) {
                    item = processed
                }
            } catch {
                print("Agent: Research URL processing failed (non-fatal): \(error)")
            }
        }

        // Generate embedding in background
        Task {
            let textToEmbed = [title, body ?? ""].joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !textToEmbed.isEmpty {
                try? await VectorDatabase.shared.index(
                    text: textToEmbed,
                    entityType: "research",
                    entityId: item.id ?? 0,
                    entityUUID: item.uuid
                )
            }
        }

        // Post notification for UI updates
        NotificationCenter.default.post(
            name: .researchCreated,
            object: nil,
            userInfo: ["research": item, "uuid": item.uuid]
        )

        let resolvedTitle = item.title ?? title
        return jsonEncode([
            "success": true,
            "uuid": item.uuid,
            "title": resolvedTitle,
            "message": "Research captured: \(resolvedTitle)"
        ] as [String: Any])
    }

    // MARK: - Content

    private func getContentPipeline(_ args: [String: Any]) async throws -> String {
        let filterPhase = args["phase"] as? String
        let contentAtoms = try await atomRepo.fetchAll(type: .content)

        var grouped: [String: [[String: Any]]] = [:]

        for atom in contentAtoms {
            let meta = atom.metadataValue(as: ContentAtomMetadata.self)
            let phase = meta?.phase.rawValue ?? "ideation"

            if let filterPhase = filterPhase, phase != filterPhase {
                continue
            }

            let item: [String: Any] = [
                "uuid": atom.uuid,
                "title": atom.title ?? "Untitled",
                "phase": phase,
                "wordCount": meta?.wordCount ?? 0,
                "platform": meta?.platform?.rawValue ?? "none"
            ]
            grouped[phase, default: []].append(item)
        }

        var result: [String: Any] = ["pipeline": grouped]
        result["totalCount"] = contentAtoms.count
        return jsonEncode(result)
    }

    private func advancePipelinePhase(_ args: [String: Any]) async throws -> String {
        guard let uuid = args["uuid"] as? String else {
            return jsonError("Missing required parameter: uuid")
        }
        let notes = args["notes"] as? String

        do {
            let phaseAtom = try await ContentPipelineService().advancePhase(
                contentUUID: uuid,
                notes: notes
            )
            return jsonEncode([
                "success": true,
                "phaseTransition": phaseAtom.title ?? "",
                "message": "Content advanced to next phase"
            ] as [String: Any])
        } catch {
            return jsonError("Failed to advance phase: \(error.localizedDescription)")
        }
    }

    private func createContent(_ args: [String: Any]) async throws -> String {
        guard let title = args["title"] as? String else {
            return jsonError("Missing required parameter: title")
        }
        let body = args["body"] as? String
        let description = args["description"] as? String ?? args["coreIdea"] as? String
        let platformStr = args["platform"] as? String
        let sourceIdeaUUID = args["sourceIdeaUUID"] as? String
        let framework = args["framework"] as? String
        let hooks = args["hooks"] as? [String]
        let swipeUUIDs = args["swipeUUIDs"] as? [String]

        // Use description as body if body not provided
        let contentBody = body ?? description

        // Resolve client if clientName provided
        var resolvedClientUUID: String?
        var resolvedClientName: String?
        if let clientName = args["clientName"] as? String, !clientName.isEmpty {
            if let clientAtom = try? await atomRepo.fuzzyFindClient(query: clientName) {
                resolvedClientUUID = clientAtom.uuid
                resolvedClientName = clientAtom.title ?? clientName
            }
        }

        // Build metadata
        var metaDict: [String: Any] = [
            "phase": "ideation",
            "wordCount": (contentBody ?? "").split(separator: " ").count
        ]
        if let platformStr = platformStr { metaDict["platform"] = platformStr }
        if let resolvedClientUUID = resolvedClientUUID { metaDict["clientProfileUUID"] = resolvedClientUUID }
        if let sourceIdeaUUID = sourceIdeaUUID { metaDict["sourceIdeaUUID"] = sourceIdeaUUID }
        if let swipeUUIDs = swipeUUIDs, !swipeUUIDs.isEmpty { metaDict["inheritedSwipeUUIDs"] = swipeUUIDs }
        if let framework = framework { metaDict["inheritedFramework"] = framework }
        if let hooks = hooks, !hooks.isEmpty { metaDict["inheritedHooks"] = hooks }
        metaDict["activatedAt"] = ISO8601DateFormatter().string(from: Date())

        let metaJSON: String?
        if let data = try? JSONSerialization.data(withJSONObject: metaDict),
           let json = String(data: data, encoding: .utf8) {
            metaJSON = json
        } else {
            metaJSON = nil
        }

        // Build links
        var links: [AtomLink] = []
        if let sourceIdeaUUID = sourceIdeaUUID {
            links.append(AtomLink(type: "ideaToContent", uuid: sourceIdeaUUID, entityType: "idea"))
        }
        if let resolvedClientUUID = resolvedClientUUID {
            links.append(AtomLink.contentToClient(resolvedClientUUID))
        }

        let atom = try await atomRepo.create(
            type: .content,
            title: title,
            body: contentBody,
            metadata: metaJSON,
            links: links.isEmpty ? nil : links
        )

        var response: [String: Any] = [
            "success": true,
            "uuid": atom.uuid,
            "title": title,
            "message": "Content created: \(title)"
        ]
        if let resolvedClientName = resolvedClientName {
            response["clientName"] = resolvedClientName
        }
        if let swipeUUIDs = swipeUUIDs {
            response["linkedSwipes"] = swipeUUIDs.count
        }
        return jsonEncode(response)
    }

    private func getContent(_ args: [String: Any]) async throws -> String {
        guard let uuid = args["uuid"] as? String else {
            return jsonError("Missing required parameter: uuid")
        }
        guard let atom = try await atomRepo.fetch(uuid: uuid) else {
            return jsonError("Content not found: \(uuid)")
        }
        await rememberContextAtom(atom)
        var result = atomToDict(atom)
        if let meta = atom.metadataValue(as: ContentAtomMetadata.self) {
            result["phase"] = meta.phase.rawValue
            result["platform"] = meta.platform?.rawValue ?? "none"
            result["wordCount"] = meta.wordCount
        }
        return jsonEncode(result)
    }

    private func createThinkspace(_ args: [String: Any]) async throws -> String {
        guard let title = args["title"] as? String else {
            return jsonError("Missing required parameter: title")
        }
        let atom = try await atomRepo.create(
            type: .thinkspace,
            title: title
        )
        return jsonEncode([
            "success": true,
            "uuid": atom.uuid,
            "title": title,
            "message": "Thinkspace created: \(title)"
        ] as [String: Any])
    }

    private func inspectCurrentThinkspace(_ args: [String: Any]) async throws -> String {
        let context = CosmoWindowViewModel.shared.activeContext
        let contextBlock = context.data.toContextBlock()
        var result: [String: Any] = [
            "success": true,
            "contextType": context.type.rawValue,
            "contextName": context.type.displayName,
            "summary": context.summary,
            "contextBlock": contextBlock,
            "availableActions": context.actions.map(\.name)
        ]
        if let value = context.data.currentAtomUUID { result["currentAtomUUID"] = value }
        if let value = context.data.currentAtomType { result["currentAtomType"] = value }
        if let value = context.data.currentAtomTitle { result["currentAtomTitle"] = value }
        if let value = context.data.visibleItemCount { result["visibleItemCount"] = value }
        return jsonEncode(result)
    }

    private func proposeCanvasPlan(_ args: [String: Any]) async throws -> String {
        let title = (args["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rationale = (args["rationale"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawOperations = args["operations"] as? [[String: Any]]

        guard let title, !title.isEmpty else {
            return jsonError("Missing required parameter: title")
        }
        guard let rationale, !rationale.isEmpty else {
            return jsonError("Missing required parameter: rationale")
        }
        guard let rawOperations, !rawOperations.isEmpty else {
            return jsonError("Missing required parameter: operations")
        }

        let operations = rawOperations.map { raw in
            PendingCanvasOperation(
                kind: PendingCanvasOperationKind(rawValue: raw["kind"] as? String ?? "") ?? .unsupported,
                summary: (raw["summary"] as? String) ?? "Canvas operation",
                payload: stringifyCanvasPayload(raw)
            )
        }

        let plan = PendingCanvasPlan(title: title, rationale: rationale, operations: operations)
        onCanvasPlan?(plan)

        return jsonEncode([
            "success": true,
            "pendingPlanId": plan.id.uuidString,
            "operationCount": operations.count,
            "message": "Canvas plan is ready for user review. Do not say it has been applied until the user clicks Apply."
        ] as [String: Any])
    }

    private func proposeNoteStructurePlan(_ args: [String: Any]) async throws -> String {
        guard let title = trimmedString(args["title"]) else {
            return jsonError("Missing required parameter: title")
        }
        guard let rationale = trimmedString(args["rationale"]) else {
            return jsonError("Missing required parameter: rationale")
        }
        guard let sourceNoteUUID = uuidValue(args["sourceNoteUUID"]) else {
            return jsonError("Missing or invalid required parameter: sourceNoteUUID")
        }
        guard let sourceTitle = trimmedString(args["sourceTitle"]) else {
            return jsonError("Missing required parameter: sourceTitle")
        }
        guard let sourceBodyHash = trimmedString(args["sourceBodyHash"]) else {
            return jsonError("Missing required parameter: sourceBodyHash")
        }
        guard let targetThinkspaceUUID = uuidValue(args["targetThinkspaceUUID"]) else {
            return jsonError("Missing or invalid required parameter: targetThinkspaceUUID")
        }
        guard let rawClusters = args["clusters"] as? [[String: Any]], !rawClusters.isEmpty else {
            return jsonError("Missing required parameter: clusters")
        }
        guard let rawModules = args["modules"] as? [[String: Any]], !rawModules.isEmpty else {
            return jsonError("Missing required parameter: modules")
        }

        let clusters = try rawClusters.map(parseNoteStructureCluster)
        let modules = try rawModules.map(parseNoteStructureModule)
        let plan = PendingNoteStructurePlan(
            title: title,
            rationale: rationale,
            sourceNoteUUID: sourceNoteUUID,
            sourceTitle: sourceTitle,
            sourceBodyHash: sourceBodyHash,
            targetThinkspaceUUID: targetThinkspaceUUID,
            keepOriginalVisible: args["keepOriginalVisible"] as? Bool ?? true,
            clusters: clusters,
            modules: modules
        )

        onNoteStructurePlan?(plan)

        return jsonEncode([
            "success": true,
            "pendingPlanId": plan.id.uuidString,
            "clusterCount": clusters.count,
            "moduleCount": modules.count,
            "keepOriginalVisible": plan.keepOriginalVisible,
            "message": "Note structure plan is ready for user review. Do not say it has been applied until the user clicks Apply."
        ] as [String: Any])
    }

    private func parseNoteStructureCluster(_ raw: [String: Any]) throws -> NoteStructureClusterProposal {
        guard let id = uuidValue(raw["id"]) else {
            throw toolArgumentError("Invalid note structure cluster id")
        }
        guard let name = trimmedString(raw["name"]) else {
            throw toolArgumentError("Missing note structure cluster name")
        }
        let colorIndex = intValue(raw["colorIndex"]) ?? 0
        let x = doubleValue(raw["x"]) ?? 0
        let y = doubleValue(raw["y"]) ?? 0
        let width = doubleValue(raw["width"]) ?? 900
        let height = doubleValue(raw["height"]) ?? 700
        let moduleIDs = (raw["moduleIDs"] as? [String] ?? []).compactMap(UUID.init(uuidString:))

        return NoteStructureClusterProposal(
            id: id,
            name: name,
            colorIndex: colorIndex,
            frame: CGRect(x: x, y: y, width: width, height: height),
            moduleIDs: moduleIDs
        )
    }

    private func parseNoteStructureModule(_ raw: [String: Any]) throws -> NoteStructureModuleProposal {
        guard let id = uuidValue(raw["id"]) else {
            throw toolArgumentError("Invalid note structure module id")
        }
        guard let clusterID = uuidValue(raw["clusterID"]) else {
            throw toolArgumentError("Invalid note structure module clusterID")
        }
        guard let title = trimmedString(raw["title"]) else {
            throw toolArgumentError("Missing note structure module title")
        }
        guard let start = intValue(raw["startUTF16Offset"]) else {
            throw toolArgumentError("Missing note structure module startUTF16Offset")
        }
        guard let length = intValue(raw["lengthUTF16"]) else {
            throw toolArgumentError("Missing note structure module lengthUTF16")
        }

        let x = doubleValue(raw["x"]) ?? 0
        let y = doubleValue(raw["y"]) ?? 0
        let width = doubleValue(raw["width"]) ?? Double(CanvasBlock.documentLayoutSize.width)
        let height = doubleValue(raw["height"]) ?? Double(CanvasBlock.documentLayoutSize.height)

        return NoteStructureModuleProposal(
            id: id,
            clusterID: clusterID,
            title: title,
            startUTF16Offset: start,
            lengthUTF16: length,
            position: CGPoint(x: x, y: y),
            size: CGSize(width: width, height: height)
        )
    }

    private func stringifyCanvasPayload(_ raw: [String: Any]) -> [String: String] {
        var payload: [String: String] = [:]
        for (key, value) in raw where key != "summary" {
            if let string = value as? String {
                payload[key] = string
            } else if let number = value as? NSNumber {
                payload[key] = number.stringValue
            } else {
                payload[key] = "\(value)"
            }
        }
        return payload
    }

    // MARK: - Calendar / Schedule Blocks

    private func getCalendarBlocks(_ args: [String: Any]) async throws -> String {
        let dateStr = args["date"] as? String
        let calendar = Calendar.current

        let targetDate: Date
        if let dateStr = dateStr, let parsed = ISO8601DateFormatter().date(from: dateStr) {
            targetDate = parsed
        } else if let dateStr = dateStr {
            // Try simple date format
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            targetDate = formatter.date(from: dateStr) ?? Date()
        } else {
            targetDate = Date()
        }

        let dayStart = calendar.startOfDay(for: targetDate)

        let blocks = try await atomRepo.fetchAll(type: .scheduleBlock)
        let dayBlocks = blocks.filter { atom in
            let meta = atom.metadataValue(as: ScheduleBlockMetadata.self)
            if let startStr = meta?.startTime,
               let startDate = ISO8601DateFormatter().date(from: startStr) {
                return calendar.isDate(startDate, inSameDayAs: dayStart)
            }
            // Fallback to createdAt
            if let date = ISO8601DateFormatter().date(from: atom.createdAt) {
                return calendar.isDate(date, inSameDayAs: dayStart)
            }
            return false
        }

        let items: [[String: Any]] = dayBlocks.map { atom in
            let meta = atom.metadataValue(as: ScheduleBlockMetadata.self)
            return [
                "uuid": atom.uuid,
                "title": atom.title ?? "Untitled",
                "startTime": meta?.startTime ?? "",
                "endTime": meta?.endTime ?? "",
                "isCompleted": meta?.isCompleted ?? false,
                "blockType": meta?.blockType ?? "",
                "intent": meta?.originType ?? ""
            ] as [String: Any]
        }

        return jsonEncode([
            "date": ISO8601DateFormatter().string(from: dayStart),
            "blocks": items,
            "count": items.count
        ] as [String: Any])
    }

    private func createBlock(_ args: [String: Any]) async throws -> String {
        guard let title = args["title"] as? String else {
            return jsonError("Missing required parameter: title")
        }
        guard let startTime = args["startTime"] as? String else {
            return jsonError("Missing required parameter: startTime")
        }
        guard let endTime = args["endTime"] as? String else {
            return jsonError("Missing required parameter: endTime")
        }
        let intent = args["intent"] as? String

        var metaDict: [String: Any] = [
            "startTime": startTime,
            "endTime": endTime,
            "status": "scheduled"
        ]
        if let intent = intent {
            metaDict["originType"] = intent
        }

        let metaJSON: String?
        if let data = try? JSONSerialization.data(withJSONObject: metaDict),
           let json = String(data: data, encoding: .utf8) {
            metaJSON = json
        } else {
            metaJSON = nil
        }

        let atom = try await atomRepo.create(
            type: .scheduleBlock,
            title: title,
            metadata: metaJSON
        )

        return jsonEncode([
            "success": true,
            "uuid": atom.uuid,
            "title": title,
            "startTime": startTime,
            "endTime": endTime,
            "message": "Schedule block created: \(title)"
        ] as [String: Any])
    }

    private func updateBlock(_ args: [String: Any]) async throws -> String {
        guard let uuid = args["uuid"] as? String else {
            return jsonError("Missing required parameter: uuid")
        }
        guard let updated = try await atomRepo.update(uuid: uuid, updates: { atom in
            if let title = args["title"] as? String { atom.title = title }

            var metaDict = (atom.metadataDict ?? [:])
            if let startTime = args["startTime"] as? String { metaDict["startTime"] = startTime }
            if let endTime = args["endTime"] as? String { metaDict["endTime"] = endTime }

            if let data = try? JSONSerialization.data(withJSONObject: metaDict),
               let json = String(data: data, encoding: .utf8) {
                atom.metadata = json
            }
        }) else {
            return jsonError("Schedule block not found: \(uuid)")
        }
        return jsonEncode([
            "success": true,
            "uuid": updated.uuid,
            "message": "Schedule block updated"
        ] as [String: Any])
    }

    private func deleteBlock(_ args: [String: Any]) async throws -> String {
        guard let uuid = args["uuid"] as? String else {
            return jsonError("Missing required parameter: uuid")
        }

        // Check if this is a confirmed deletion
        let isConfirmed = args["_confirmed"] as? Bool ?? false
        if isConfirmed {
            try await atomRepo.delete(uuid: uuid)
            return jsonEncode([
                "success": true,
                "message": "Schedule block deleted"
            ] as [String: Any])
        }

        // Fetch block to show description
        let atom = try await atomRepo.fetch(uuid: uuid)
        let blockTitle = atom?.title ?? uuid

        // Hard confirmation — store pending and return confirmation request
        let confirmationId = UUID().uuidString
        pendingConfirmations[confirmationId] = PendingConfirmation(
            toolName: "delete_block",
            arguments: ["uuid": uuid, "_confirmed": true],
            description: "Delete schedule block: \(blockTitle)",
            createdAt: Date()
        )

        return jsonEncode([
            "confirmation_required": true,
            "confirmation_id": confirmationId,
            "action": "delete_block",
            "description": "Delete schedule block: \(blockTitle)"
        ] as [String: Any])
    }

    private func completeBlock(_ args: [String: Any]) async throws -> String {
        guard let uuid = args["uuid"] as? String else {
            return jsonError("Missing required parameter: uuid")
        }

        guard let updated = try await atomRepo.update(uuid: uuid, updates: { atom in
            var metaDict = (atom.metadataDict ?? [:])
            metaDict["isCompleted"] = true
            metaDict["completedAt"] = ISO8601DateFormatter().string(from: Date())
            metaDict["status"] = "completed"
            if let data = try? JSONSerialization.data(withJSONObject: metaDict),
               let json = String(data: data, encoding: .utf8) {
                atom.metadata = json
            }
        }) else {
            return jsonError("Schedule block not found: \(uuid)")
        }

        return jsonEncode([
            "success": true,
            "uuid": updated.uuid,
            "title": updated.title ?? "",
            "message": "Block completed. XP awarded."
        ] as [String: Any])
    }

    private func getUnscheduledTasks(_ args: [String: Any]) async throws -> String {
        let limit = args["limit"] as? Int ?? 20

        let tasks = try await atomRepo.fetchAll(type: .task)
        let unscheduled = tasks.filter { atom in
            let meta = atom.metadataValue(as: TaskMetadata.self)
            return meta?.isUnscheduled == true || meta?.startTime == nil
        }.prefix(limit)

        let items: [[String: Any]] = unscheduled.map { atom in
            let meta = atom.metadataValue(as: TaskMetadata.self)
            return [
                "uuid": atom.uuid,
                "title": atom.title ?? "Untitled",
                "priority": meta?.priority ?? "medium",
                "intent": meta?.intent ?? "",
                "dueDate": meta?.dueDate ?? ""
            ] as [String: Any]
        }

        return jsonEncode(["tasks": items, "count": items.count])
    }

    private func createTask(_ args: [String: Any]) async throws -> String {
        guard let title = args["title"] as? String else {
            return jsonError("Missing required parameter: title")
        }
        let body = args["body"] as? String
        let priority = args["priority"] as? String ?? "medium"
        let intent = args["intent"] as? String
        let dueDate = args["dueDate"] as? String

        var metaDict: [String: Any] = [
            "priority": priority,
            "isUnscheduled": true
        ]
        if let intent = intent { metaDict["intent"] = intent }
        if let dueDate = dueDate { metaDict["dueDate"] = dueDate }

        let metaJSON: String?
        if let data = try? JSONSerialization.data(withJSONObject: metaDict),
           let json = String(data: data, encoding: .utf8) {
            metaJSON = json
        } else {
            metaJSON = nil
        }

        let atom = try await atomRepo.create(
            type: .task,
            title: title,
            body: body,
            metadata: metaJSON
        )

        return jsonEncode([
            "success": true,
            "uuid": atom.uuid,
            "title": title,
            "message": "Task created: \(title)"
        ] as [String: Any])
    }

    // MARK: - Analytics

    private func getDimensionXP(_ args: [String: Any]) async throws -> String {
        // Legacy dimension system removed
        return jsonEncode([
            "dimensions": [] as [[String: Any]],
            "overallLevel": 1,
            "overallTrend": "stable"
        ] as [String: Any])
    }

    private func getStreakData(_ args: [String: Any]) async throws -> String {
        // Load streak data from dimensionSnapshot atoms
        let snapshots = try await atomRepo.fetchAll(type: .dimensionSnapshot)

        var streaks: [String: Int] = [:]
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Group snapshots by day, check consecutive
        let dailySnapshots = snapshots.compactMap { atom -> Date? in
            ISO8601DateFormatter().date(from: atom.createdAt)
        }.map { calendar.startOfDay(for: $0) }

        let uniqueDays = Set(dailySnapshots).sorted(by: >)
        var consecutiveDays = 0
        var checkDate = today

        for day in uniqueDays {
            if calendar.isDate(day, inSameDayAs: checkDate) {
                consecutiveDays += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            } else {
                break
            }
        }

        streaks["overall"] = consecutiveDays

        return jsonEncode(["streaks": streaks])
    }

    // MARK: - Preferences

    private func getPreferences(_ args: [String: Any]) async throws -> String {
        let scopeStr = args["scope"] as? String
        let scope: PreferenceScope? = scopeStr.flatMap { PreferenceScope(rawValue: $0) }

        let preferences = await PreferenceLearningEngine.shared.getAllPreferences(scope: scope)

        let items: [[String: Any]] = preferences.map { pref in
            [
                "key": pref.key,
                "value": pref.value,
                "scope": pref.scope.rawValue,
                "source": pref.source
            ]
        }

        return jsonEncode(["preferences": items, "count": items.count])
    }

    private func storePreference(_ args: [String: Any]) async throws -> String {
        guard let key = args["key"] as? String else {
            return jsonError("Missing required parameter: key")
        }
        guard let value = args["value"] as? String else {
            return jsonError("Missing required parameter: value")
        }
        let scopeStr = args["scope"] as? String ?? "global"
        let scope = PreferenceScope(rawValue: scopeStr) ?? .global
        let scopeQualifier = args["scopeQualifier"] as? String

        await PreferenceLearningEngine.shared.learnPreference(
            key: key,
            value: value,
            scope: scope,
            source: "explicit",
            confidence: 1.0,
            scopeQualifier: scopeQualifier
        )

        return jsonEncode([
            "success": true,
            "key": key,
            "value": value,
            "scope": scopeStr,
            "message": "Preference stored: \(key) = \(value)"
        ] as [String: Any])
    }

    private func deletePreference(_ args: [String: Any]) async throws -> String {
        guard let key = args["key"] as? String else {
            return jsonError("Missing required parameter: key")
        }

        let scopeStr = args["scope"] as? String ?? "global"
        let scope: PreferenceScope = scopeStr == "client" ? .client : scopeStr == "taskType" ? .taskType : .global
        let scopeQualifier = args["scopeQualifier"] as? String

        await PreferenceLearningEngine.shared.deletePreference(key: key, scope: scope, scopeQualifier: scopeQualifier)

        return jsonEncode([
            "success": true,
            "key": key,
            "message": "Preference deleted: \(key)"
        ] as [String: Any])
    }

    // MARK: - Client Memory

    private func updateClientMemory(_ args: [String: Any]) async throws -> String {
        guard let clientName = args["client_name"] as? String else {
            return jsonError("Missing required parameter: client_name")
        }
        guard let field = args["field"] as? String else {
            return jsonError("Missing required parameter: field")
        }
        guard let value = args["value"] as? String else {
            return jsonError("Missing required parameter: value")
        }

        // Fuzzy-match client name to get UUID
        guard let clientAtom = try? await atomRepo.fuzzyFindClient(query: clientName) else {
            return jsonError("Client not found: \(clientName)")
        }
        let clientUUID = clientAtom.uuid
        let resolvedName = clientAtom.title ?? clientName

        // Check if a .userPreference atom with matching scope+key already exists
        let existingPrefs = (try? await atomRepo.fetchAll(type: .userPreference)) ?? []
        let existing = existingPrefs.first { atom in
            guard let meta = atom.metadata,
                  let data = meta.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            return dict["scope"] as? String == clientUUID && dict["key"] as? String == field
        }

        let metaDict: [String: Any] = [
            "scope": clientUUID,
            "key": field,
            "value": value,
            "source": "agent_memory",
            "updatedAt": ISO8601DateFormatter().string(from: Date())
        ]
        let metadataJSON = (try? JSONSerialization.data(withJSONObject: metaDict)).flatMap { String(data: $0, encoding: .utf8) }

        if var existingAtom = existing {
            // Update existing memory atom
            existingAtom.body = value
            existingAtom.metadata = metadataJSON
            _ = try? await atomRepo.update(existingAtom)
        } else {
            // Create new memory atom
            let atom = Atom.new(
                type: .userPreference,
                title: "client_memory:\(resolvedName):\(field)",
                body: value,
                metadata: metadataJSON
            )
            _ = try? await atomRepo.create(atom)
        }

        return jsonEncode([
            "success": true,
            "clientName": resolvedName,
            "field": field,
            "value": value,
            "message": "Memory updated for \(resolvedName): \(field)"
        ] as [String: Any])
    }

    private func listClientMemory(_ args: [String: Any]) async throws -> String {
        guard let clientName = args["client_name"] as? String else {
            return jsonError("Missing required parameter: client_name")
        }

        // Fuzzy-match client name to get UUID
        guard let clientAtom = try? await atomRepo.fuzzyFindClient(query: clientName) else {
            return jsonError("Client not found: \(clientName)")
        }
        let clientUUID = clientAtom.uuid
        let resolvedName = clientAtom.title ?? clientName

        // Query .userPreference atoms where metadata.scope matches clientUUID
        let allPrefs = (try? await atomRepo.fetchAll(type: .userPreference)) ?? []
        let clientMemories = allPrefs.filter { atom in
            guard let meta = atom.metadata,
                  let data = meta.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            return dict["scope"] as? String == clientUUID && dict["source"] as? String == "agent_memory"
        }

        let items: [[String: Any]] = clientMemories.map { atom in
            var item: [String: Any] = [
                "field": "",
                "value": atom.body ?? ""
            ]
            if let meta = atom.metadata,
               let data = meta.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                item["field"] = dict["key"] as? String ?? ""
                item["value"] = dict["value"] as? String ?? (atom.body ?? "")
                item["updatedAt"] = dict["updatedAt"] as? String ?? ""
            }
            return item
        }

        return jsonEncode([
            "clientName": resolvedName,
            "memories": items,
            "count": items.count
        ] as [String: Any])
    }

    // MARK: - Writing Tools (Cloud Writing Engine — canonical)
    // All writing goes through the cloud engine for guaranteed quality parity.
    // The cloud engine has all craft modules, validators, scoring, and retry logic.

    private func generateOutline(_ args: [String: Any]) async throws -> String {
        guard let contentUUID = args["contentUUID"] as? String else {
            return jsonError("Missing or invalid contentUUID")
        }

        print("☁️ [AgentToolExecutor] generate_outline → cloud engine for \(contentUUID)")

        do {
            let notes = args["notes"] as? String
            let sharedContext = await sharedWritingContextBlock(
                contentUUID: contentUUID,
                prompt: notes ?? "Generate an outline for this content.",
                clientName: args["clientName"] as? String
            )
            let result = try await CloudWritingClient.shared.generateOutline(
                contentUUID: contentUUID,
                blueprintTitles: args["blueprintTitles"] as? [String],
                blueprintSwipeUUIDs: {
                    var uuids = args["blueprintSwipeUUIDs"] as? [String] ?? []
                    if let single = args["blueprintSwipeUUID"] as? String, !single.isEmpty, !uuids.contains(single) {
                        uuids.insert(single, at: 0)
                    }
                    return uuids.isEmpty ? nil : uuids
                }(),
                notes: Self.mergeWritingContext(notes, contextBlock: sharedContext),
                clientName: args["clientName"] as? String,
                contentFormat: args["contentFormat"] as? String,
                contextAtomUUIDs: contextAtomUUIDs.isEmpty ? nil : contextAtomUUIDs
            )

            // Re-encode as JSON string for the agent tool result format
            let encoder = JSONEncoder()
            let data = try encoder.encode(result)
            return String(data: data, encoding: .utf8) ?? jsonError("Failed to encode outline result")
        } catch {
            return jsonError("Cloud outline failed: \(error.localizedDescription)")
        }
    }

    private func generateDraft(_ args: [String: Any]) async throws -> String {
        guard let contentUUID = args["contentUUID"] as? String else {
            return jsonError("Missing or invalid contentUUID")
        }

        // Advance pipeline phase for XP
        _ = try? await ContentPipelineService().advancePhase(
            contentUUID: contentUUID,
            notes: "Draft generated via cloud writing engine"
        )

        // Check if content atom has a codex outline → single agentic session (Opus, adaptive thinking)
        let atom = try? await AtomRepository.shared.fetch(uuid: contentUUID)
        let hasCodexOutline: Bool = {
            guard let metadata = atom?.metadata,
                  let data = metadata.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return false
            }
            // Check both direct and inherited outline fields
            return dict["codexOutline"] != nil || dict["inheritedCodexOutline"] != nil
        }()

        if hasCodexOutline {
            print("☁️ [AgentToolExecutor] generate_draft → SINGLE SESSION (Opus) for \(contentUUID)")

            // Pass local metadata to cloud to avoid Supabase sync race conditions.
            // The cloud engine merges these into the atom metadata it reads from Supabase.
            var localMetadata: [String: Any]?
            if let metadata = atom?.metadata,
               let data = metadata.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                localMetadata = dict
            }

            do {
                let userDirection = args["userDirection"] as? String
                let sharedContext = await sharedWritingContextBlock(
                    contentUUID: contentUUID,
                    prompt: userDirection ?? "Generate a draft for this content.",
                    clientName: args["clientName"] as? String
                )
                let result = try await CloudWritingClient.shared.runSession(
                    contentUUID: contentUUID,
                    userDirection: Self.mergeWritingContext(userDirection, contextBlock: sharedContext),
                    localMetadata: localMetadata
                )

                await persistGeneratedDraftLocally(
                    contentUUID: contentUUID,
                    formattedDraft: result.formattedDraft,
                    source: "single-session generate_draft"
                )

                let encoder = JSONEncoder()
                let data = try encoder.encode(result)
                return String(data: data, encoding: .utf8) ?? jsonError("Failed to encode session result")
            } catch {
                print("❌ [AgentToolExecutor] Single session failed: \(error.localizedDescription)")
                return jsonError("Single session failed: \(error.localizedDescription)")
            }
        }

        print("☁️ [AgentToolExecutor] generate_draft → multi-phase pipeline for \(contentUUID)")

        do {
            let userDirection = args["userDirection"] as? String
            let sharedContext = await sharedWritingContextBlock(
                contentUUID: contentUUID,
                prompt: userDirection ?? "Generate a draft for this content.",
                clientName: args["clientName"] as? String
            )
            let result = try await CloudWritingClient.shared.generateDraft(
                contentUUID: contentUUID,
                userDirection: Self.mergeWritingContext(userDirection, contextBlock: sharedContext),
                clientName: args["clientName"] as? String,
                contentFormat: args["contentFormat"] as? String
            )

            await persistGeneratedDraftLocally(
                contentUUID: contentUUID,
                formattedDraft: result.formattedDraft,
                source: "multi-phase generate_draft"
            )

            let encoder = JSONEncoder()
            let data = try encoder.encode(result)
            return String(data: data, encoding: .utf8) ?? jsonError("Failed to encode draft result")
        } catch {
            return jsonError("Cloud draft failed: \(error.localizedDescription)")
        }
    }

    /// Detect the structural format of a draft body (carousel JSON, thread JSON, or plaintext).
    private static func detectDraftFormat(_ body: String) -> String {
        guard !body.isEmpty,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return "plaintext"
        }
        if let dict = json as? [String: Any] {
            if dict["slides"] != nil { return "carousel" }
            if dict["tweets"] != nil { return "thread" }
        }
        if let arr = json as? [[String: Any]], let first = arr.first {
            if first["number"] != nil, first["text"] != nil { return "carousel" }
            if first["tweet"] != nil { return "thread" }
        }
        return "json"
    }

    // MARK: - Read Draft

    private func readDraft(_ args: [String: Any]) async throws -> String {
        guard let contentUUID = args["contentUUID"] as? String else {
            return jsonError("Missing required parameter: contentUUID")
        }
        guard let atom = try await atomRepo.fetch(uuid: contentUUID) else {
            return jsonError("Content atom not found: \(contentUUID)")
        }
        let rawBody = atom.body ?? ""
        let formatted = Self.renderDraftForDisplay(rawBody)
        let wordCount = formatted
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
        let title = atom.title ?? "Untitled"

        return jsonEncode([
            "success": true,
            "contentUUID": contentUUID,
            "title": title,
            "formattedDraft": formatted,
            "wordCount": wordCount
        ] as [String: Any])
    }

    // MARK: - Draft Display Renderer

    /// Converts structured draft JSON (carousel slides, thread tweets) into a readable
    /// plaintext representation suitable for display in conversation. Strips internal
    /// fields like `visualDirection` that are not relevant to the user-facing draft.
    static func renderDraftForDisplay(_ draftBody: String) -> String {
        guard !draftBody.isEmpty else { return "" }

        guard let data = draftBody.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data) else {
            // Not JSON — return plaintext/script as-is
            return draftBody
        }

        // Raw array format: [{"number": 1, "text": "...", "visualDirection": "..."}]
        // The LLM sometimes omits the {"slides": [...]} wrapper
        if let rawArray = jsonObject as? [[String: Any]],
           let first = rawArray.first,
           first["number"] != nil, first["text"] != nil {
            let sorted = rawArray.sorted { ($0["number"] as? Int ?? 0) < ($1["number"] as? Int ?? 0) }
            var lines: [String] = []
            for slide in sorted {
                let num = slide["number"] as? Int ?? (lines.count / 2 + 1)
                let text = slide["text"] as? String ?? ""
                lines.append("SLIDE \(num)")
                lines.append(text)
                lines.append("")
            }
            if lines.last?.isEmpty == true { lines.removeLast() }
            return lines.joined(separator: "\n")
        }

        guard let json = jsonObject as? [String: Any] else { return draftBody }

        // Carousel format: {"slides": [{"number": 1, "text": "...", "visualDirection": "..."}]}
        if let slides = json["slides"] as? [[String: Any]] {
            let sortedSlides = slides.sorted {
                ($0["number"] as? Int ?? 0) < ($1["number"] as? Int ?? 0)
            }
            var lines: [String] = []
            for slide in sortedSlides {
                let num = slide["number"] as? Int ?? (lines.count / 2 + 1)
                let text = slide["text"] as? String ?? ""
                lines.append("SLIDE \(num)")
                lines.append(text)
                lines.append("")
            }
            // Remove trailing empty line
            if lines.last?.isEmpty == true { lines.removeLast() }
            return lines.joined(separator: "\n")
        }

        // Thread format: {"tweets": [{"number": 1, "text": "..."}]}
        if let tweets = json["tweets"] as? [[String: Any]] {
            let sortedTweets = tweets.sorted {
                ($0["number"] as? Int ?? 0) < ($1["number"] as? Int ?? 0)
            }
            var lines: [String] = []
            for tweet in sortedTweets {
                let num = tweet["number"] as? Int ?? (lines.count / 2 + 1)
                let text = tweet["text"] as? String ?? ""
                lines.append("TWEET \(num)")
                lines.append(text)
                lines.append("")
            }
            if lines.last?.isEmpty == true { lines.removeLast() }
            return lines.joined(separator: "\n")
        }

        // Unknown JSON structure — return raw body
        return draftBody
    }

    static func draftBodyForLocalPersistence(_ formattedDraft: String?) -> String? {
        guard let formattedDraft else { return nil }
        let renderedDraft = renderDraftForDisplay(formattedDraft)
        guard !renderedDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return renderedDraft
    }

    static func draftUpdateNotificationUserInfo(contentUUID: String, content: String) -> [String: String] {
        [
            "contentUUID": contentUUID,
            "uuid": contentUUID,
            "content": content,
            "format": detectDraftFormat(content)
        ]
    }

    private func persistGeneratedDraftLocally(
        contentUUID: String,
        formattedDraft: String?,
        source: String
    ) async {
        guard let draft = Self.draftBodyForLocalPersistence(formattedDraft) else {
            print("☁️ [AgentToolExecutor] No draft to persist from \(source) for \(contentUUID)")
            return
        }

        guard var atom = try? await atomRepo.fetch(uuid: contentUUID) else {
            print("⚠️ [AgentToolExecutor] Could not persist draft from \(source); content atom not found: \(contentUUID)")
            return
        }

        atom.body = draft
        atom.metadata = RichDocumentMetadataStorage.writeDocument(
            RichDocument.migrateLegacy(draft),
            into: atom.metadata,
            key: RichDocumentMetadataKeys.contentDraftDocument
        )

        do {
            _ = try await atomRepo.update(atom)
            NotificationCenter.default.post(
                name: .unifiedEngineDraftUpdate,
                object: nil,
                userInfo: Self.draftUpdateNotificationUserInfo(contentUUID: contentUUID, content: draft)
            )
            print("☁️ [AgentToolExecutor] Draft persisted locally from \(source) (\(draft.count) chars) for \(contentUUID)")
        } catch {
            print("❌ [AgentToolExecutor] Failed to persist draft from \(source) for \(contentUUID): \(error)")
        }
    }

    private func reviseDraft(_ args: [String: Any]) async throws -> String {
        guard let contentUUID = args["contentUUID"] as? String else {
            return jsonError("Missing or invalid contentUUID")
        }

        guard let feedback = args["feedback"] as? String, !feedback.isEmpty else {
            return jsonError("Missing required parameter: feedback")
        }

        print("☁️ [AgentToolExecutor] revise_draft → cloud engine for \(contentUUID)")

        do {
            let sharedContext = await sharedWritingContextBlock(
                contentUUID: contentUUID,
                prompt: feedback,
                clientName: args["clientName"] as? String
            )
            let result = try await CloudWritingClient.shared.reviseDraft(
                contentUUID: contentUUID,
                feedback: Self.mergeWritingContext(feedback, contextBlock: sharedContext) ?? feedback,
                currentDraft: args["currentDraft"] as? String,
                clientName: args["clientName"] as? String
            )

            await persistGeneratedDraftLocally(
                contentUUID: contentUUID,
                formattedDraft: result.formattedDraft,
                source: "revise_draft"
            )

            let encoder = JSONEncoder()
            let data = try encoder.encode(result)
            return String(data: data, encoding: .utf8) ?? jsonError("Failed to encode revision result")
        } catch {
            return jsonError("Cloud revision failed: \(error.localizedDescription)")
        }
    }

    private func generateHooks(_ args: [String: Any]) async throws -> String {
        guard let contentUUID = args["contentUUID"] as? String else {
            return jsonError("Missing or invalid contentUUID")
        }

        print("☁️ [AgentToolExecutor] generate_hooks → cloud engine for \(contentUUID)")

        // Route through cloud outline (hooks are generated as part of outline)
        do {
            let sharedContext = await sharedWritingContextBlock(
                contentUUID: contentUUID,
                prompt: "Generate hooks for this content.",
                clientName: args["clientName"] as? String
            )
            let result = try await CloudWritingClient.shared.generateOutline(
                contentUUID: contentUUID,
                notes: sharedContext,
                clientName: args["clientName"] as? String
            )

            let encoder = JSONEncoder()
            let data = try encoder.encode(result)
            return String(data: data, encoding: .utf8) ?? jsonError("Failed to encode hooks result")
        } catch {
            return jsonError("Cloud hooks failed: \(error.localizedDescription)")
        }
    }

    private func updateContent(_ args: [String: Any]) async throws -> String {
        guard let uuid = args["uuid"] as? String else {
            return jsonError("Missing required parameter: uuid")
        }
        var draftUpdateContent: String?

        // Resolve client if clientName provided
        var resolvedClientUUID: String?
        var resolvedClientName: String?
        if let clientName = args["clientName"] as? String, !clientName.isEmpty {
            if let clientAtom = try? await atomRepo.fuzzyFindClient(query: clientName) {
                resolvedClientUUID = clientAtom.uuid
                resolvedClientName = clientAtom.title ?? clientName
            }
        }

        guard let updated = try await atomRepo.update(uuid: uuid, updates: { atom in
            if let title = args["title"] as? String { atom.title = title }
            if let body = args["body"] as? String {
                let renderedBody = Self.renderDraftForDisplay(body)
                atom.body = renderedBody
                let richDraft = renderedBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? RichDocument.empty
                    : RichDocument.migrateLegacy(renderedBody)
                atom.metadata = RichDocumentMetadataStorage.writeDocument(
                    richDraft,
                    into: atom.metadata,
                    key: RichDocumentMetadataKeys.contentDraftDocument
                )
                draftUpdateContent = renderedBody
            }

            var metaDict = atom.metadataDict ?? [:]

            // Description → metadata["contentDescription"] (NOT atom.body)
            if let desc = args["description"] as? String ?? args["coreIdea"] as? String {
                metaDict["contentDescription"] = desc
            }

            if let platform = args["platform"] as? String { metaDict["platform"] = platform }
            if let framework = args["framework"] as? String { metaDict["inheritedFramework"] = framework }

            // Hooks → write to both "hooks" (focus mode state) and "inheritedHooks" (context panel)
            if let hooks = args["hooks"] as? [String] {
                metaDict["hooks"] = hooks
                metaDict["inheritedHooks"] = hooks
            }

            // Outline → write to metadata["outline"] as OutlineItem-compatible JSON
            if let outlineItems = args["outline"] as? [String] {
                let outlineArray: [[String: Any]] = outlineItems.enumerated().map { index, text in
                    [
                        "id": UUID().uuidString,
                        "title": text,
                        "reasoning": "",
                        "sortOrder": index,
                        "isCompleted": false
                    ] as [String: Any]
                }
                metaDict["outline"] = outlineArray
            }

            if let clientUUID = resolvedClientUUID { metaDict["clientProfileUUID"] = clientUUID }

            if let data = try? JSONSerialization.data(withJSONObject: metaDict),
               let json = String(data: data, encoding: .utf8) {
                atom.metadata = json
            }

            // Add contentToClient link if new client resolved
            if let clientUUID = resolvedClientUUID {
                var links = atom.linksList
                let hasClientLink = links.contains { $0.type == AtomLinkType.contentToClient.rawValue }
                if !hasClientLink {
                    links.append(AtomLink.contentToClient(clientUUID))
                    atom.links = try? String(data: JSONEncoder().encode(links), encoding: .utf8)
                }
            }
        }) else {
            return jsonError("Content atom not found: \(uuid)")
        }

        var response: [String: Any] = [
            "success": true,
            "uuid": updated.uuid,
            "title": updated.title ?? "",
            "message": "Content updated"
        ]
        if let resolvedClientName = resolvedClientName {
            response["clientName"] = resolvedClientName
        }
        if let draftUpdateContent {
            NotificationCenter.default.post(
                name: .unifiedEngineDraftUpdate,
                object: nil,
                userInfo: Self.draftUpdateNotificationUserInfo(contentUUID: uuid, content: draftUpdateContent)
            )
        }
        return jsonEncode(response)
    }

    // MARK: - Lessons

    private func saveLessons(_ args: [String: Any]) async throws -> String {
        guard let lessonsArray = args["lessons"] as? [[String: Any]] else {
            return jsonError("Missing required parameter: lessons (array)")
        }

        let clientName = args["clientName"] as? String
        var clientUUID: String?
        if let clientName = clientName {
            let clientAtom = try? await atomRepo.fuzzyFindClient(query: clientName)
            clientUUID = clientAtom?.uuid
        }

        let validCategories: Set<String> = [
            "hook_style", "voice", "structure", "format", "cta",
            "scheduling", "productivity", "time_management",
            "strategy_pattern", "audience_insight",
            "analysis_method", "reflection_prompt", "general"
        ]
        var savedCount = 0

        for lessonDict in lessonsArray {
            guard let rule = lessonDict["rule"] as? String,
                  let category = lessonDict["category"] as? String,
                  validCategories.contains(category) else {
                continue
            }
            let evidence = lessonDict["evidence"] as? String ?? "Explicitly shared by user"
            let intent = lessonDict["intent"] as? String

            let targetModuleOverride = lessonDict["targetModule"] as? String
            let targetModuleId = targetModuleOverride ?? PromptTemplateStore.categoryToModuleMap[category]
            let lesson = InferredLesson(
                clientUUID: clientUUID,
                rule: rule,
                evidence: evidence,
                category: category,
                confidence: 0.9,  // High confidence for explicit user lessons
                intent: intent,
                source: .explicitUser,
                enforcement: .hard,  // Explicit user saves are always hard rules
                targetModuleId: targetModuleId
            )
            await LessonExtractor.shared.storeLesson(lesson)
            savedCount += 1
        }

        return jsonEncode([
            "success": true,
            "savedCount": savedCount,
            "message": "Saved \(savedCount) lesson\(savedCount == 1 ? "" : "s")\(clientName != nil ? " for \(clientName!)" : "")"
        ] as [String: Any])
    }

    private func getLessons(_ args: [String: Any]) async throws -> String {
        let clientName = args["clientName"] as? String
        let categoryFilter = args["category"] as? String
        let intentFilter = args["intent"] as? String

        var clientUUID: UUID?
        if let clientName = clientName {
            let clientAtom = try? await atomRepo.fuzzyFindClient(query: clientName)
            if let uuid = clientAtom?.uuid {
                clientUUID = UUID(uuidString: uuid)
            }
        }

        let lessons = await LessonExtractor.shared.loadLessons(clientUUID: clientUUID, intent: intentFilter)

        let filtered: [InferredLesson]
        if let categoryFilter = categoryFilter {
            filtered = lessons.filter { $0.category == categoryFilter }
        } else {
            filtered = lessons
        }

        let items: [[String: Any]] = filtered.map { lesson in
            var dict: [String: Any] = [
                "id": lesson.id.uuidString,
                "rule": lesson.rule,
                "category": lesson.category,
                "evidence": lesson.evidence,
                "confidence": lesson.confidence,
                "intent": lesson.intent ?? "universal"
            ]
            if lesson.clientUUID != nil {
                dict["scope"] = "client-specific"
            } else {
                dict["scope"] = "universal"
            }
            return dict
        }

        return jsonEncode([
            "results": items,
            "count": items.count,
            "message": items.isEmpty ? "No lessons found" : "Found \(items.count) lesson\(items.count == 1 ? "" : "s")"
        ] as [String: Any])
    }

    private func updateSkill(_ args: [String: Any]) async throws -> String {
        guard let lessonIdStr = args["lessonId"] as? String else {
            return jsonError("Missing required parameter: lessonId")
        }

        let atoms = try await atomRepo.fetchAll(type: .agentLearning)
        guard var atom = atoms.first(where: { atom in
            guard let meta = atom.metadataDict else { return false }
            return meta["lessonType"] as? String == "inferred_lesson"
                && meta["lessonID"] as? String == lessonIdStr
        }) else {
            return jsonError("Skill not found: \(lessonIdStr)")
        }

        guard let structuredStr = atom.structured,
              let data = structuredStr.data(using: .utf8) else {
            return jsonError("Invalid skill data")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let lesson = try decoder.decode(InferredLesson.self, from: data)

        let newRule = args["rule"] as? String ?? lesson.rule
        let newCategory = args["category"] as? String ?? lesson.category
        let newIntentRaw = args["intent"] as? String
        let newIntent: String? = newIntentRaw == "universal" ? nil : (newIntentRaw ?? lesson.intent)

        let updated = InferredLesson(
            id: lesson.id,
            clientUUID: lesson.clientUUID,
            rule: newRule,
            evidence: lesson.evidence,
            category: newCategory,
            confidence: lesson.confidence,
            createdAt: lesson.createdAt,
            lastConfirmedAt: Date(),
            optimizedInstruction: lesson.optimizedInstruction,
            intent: newIntent
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let updatedData = try encoder.encode(updated)
        atom.structured = String(data: updatedData, encoding: .utf8)
        atom.body = newRule
        atom.title = "Lesson: \(newCategory) — \(String(newRule.prefix(60)))"

        // Update metadata
        var meta = atom.metadataDict ?? [:]
        meta["category"] = newCategory
        meta["intent"] = newIntent ?? ""
        if let metaData = try? JSONSerialization.data(withJSONObject: meta),
           let metaStr = String(data: metaData, encoding: .utf8) {
            atom.metadata = metaStr
        }

        _ = try await atomRepo.update(atom)

        return jsonEncode([
            "success": true,
            "message": "Updated skill: \(String(newRule.prefix(60)))"
        ] as [String: Any])
    }

    private func deleteSkill(_ args: [String: Any]) async throws -> String {
        guard let lessonIdStr = args["lessonId"] as? String else {
            return jsonError("Missing required parameter: lessonId")
        }

        let atoms = try await atomRepo.fetchAll(type: .agentLearning)
        guard var atom = atoms.first(where: { atom in
            guard let meta = atom.metadataDict else { return false }
            return meta["lessonType"] as? String == "inferred_lesson"
                && meta["lessonID"] as? String == lessonIdStr
        }) else {
            return jsonError("Skill not found: \(lessonIdStr)")
        }

        atom.isDeleted = true
        _ = try await atomRepo.update(atom)

        return jsonEncode([
            "success": true,
            "message": "Deleted skill \(lessonIdStr)"
        ] as [String: Any])
    }


    // MARK: - Helpers

    private func atomToDict(_ atom: Atom) -> [String: Any] {
        var dict: [String: Any] = [
            "uuid": atom.uuid,
            "type": atom.type.rawValue,
            "title": atom.title ?? "",
            "body": String((atom.body ?? "").prefix(2000)),
            "createdAt": atom.createdAt,
            "updatedAt": atom.updatedAt
        ]
        if let metadata = atom.metadata,
           let data = metadata.data(using: .utf8),
           let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict["metadata"] = meta
        }
        // Include client association for ideas
        if let clientUUID = atom.ideaClientUUID {
            dict["clientUUID"] = clientUUID
        }
        return dict
    }

    private func jsonEncode(_ dict: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"error\": \"Failed to encode response\"}"
        }
        return json
    }

    private func jsonError(_ message: String) -> String {
        jsonEncode(["error": message])
    }

    private func trimmedString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func uuidValue(_ value: Any?) -> UUID? {
        guard let string = value as? String else { return nil }
        return UUID(uuidString: string.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    private func toolArgumentError(_ message: String) -> NSError {
        NSError(domain: "AgentToolExecutor", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    // MARK: - Batch Swipe Analysis Threshold

    /// Check if a source type has accumulated a multiple of 30 swipes globally.
    /// If so, post a notification so the agent system can trigger batch analysis.
    /// The count is computed from GRDB at query time (not persisted), so it stays accurate even if swipes are deleted.
    private func checkBatchSwipeThreshold(sourceType: String) async {
        do {
            let count: Int = try await CosmoDatabase.shared.asyncRead { db in
                // Count non-deleted research atoms that:
                // 1. Are swipe files (metadata JSON contains "isSwipeFile":true)
                // 2. Match the given source type (metadata JSON researchType field)
                try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM atoms
                    WHERE type = ?
                      AND is_deleted = 0
                      AND metadata LIKE '%"isSwipeFile":true%'
                      AND metadata LIKE ?
                """, arguments: [
                    AtomType.research.rawValue,
                    "%\"researchType\":\"\(sourceType)\"%"
                ]) ?? 0
            }

            if count > 0 && count % 30 == 0 {
                NotificationCenter.default.post(
                    name: CosmoNotification.SwipeFile.batchSwipeAnalysisTriggered,
                    object: nil,
                    userInfo: [
                        "sourceType": sourceType,
                        "swipeCount": count
                    ]
                )
                print("SwipeFile: Batch analysis triggered — \(count) \(sourceType) swipes")
            }
        } catch {
            print("SwipeFile: Failed to check batch threshold: \(error)")
        }
    }

    // MARK: - Standing Instructions

    private func addStandingInstruction(_ args: [String: Any]) async throws -> String {
        guard let body = args["body"] as? String else {
            return jsonError("Missing required parameter: body")
        }
        let schedule = args["schedule"] as? String ?? "daily"
        let hour = args["hour"] as? Int ?? 9
        let minute = args["minute"] as? Int ?? 0
        let days = args["days"] as? [Int]
        let intervalMinutes = args["intervalMinutes"] as? Int
        let dayOfMonth = args["dayOfMonth"] as? Int

        return try await StandingInstructionEngine.shared.addInstruction(
            body: body, schedule: schedule, hour: hour, minute: minute,
            days: days, intervalMinutes: intervalMinutes, dayOfMonth: dayOfMonth
        )
    }

    private func listStandingInstructions(_ args: [String: Any]) async throws -> String {
        let instructions = try await StandingInstructionEngine.shared.listInstructions()
        return jsonEncode(["instructions": instructions, "count": instructions.count])
    }

    private func removeStandingInstruction(_ args: [String: Any]) async throws -> String {
        guard let uuid = args["uuid"] as? String else {
            return jsonError("Missing required parameter: uuid")
        }
        return try await StandingInstructionEngine.shared.removeInstruction(uuid: uuid)
    }

    private func updateStandingInstruction(_ args: [String: Any]) async throws -> String {
        guard let uuid = args["uuid"] as? String else {
            return jsonError("Missing required parameter: uuid")
        }
        return try await StandingInstructionEngine.shared.updateInstruction(
            uuid: uuid,
            body: args["body"] as? String,
            schedule: args["schedule"] as? String,
            hour: args["hour"] as? Int,
            minute: args["minute"] as? Int,
            enabled: args["enabled"] as? Bool,
            days: args["days"] as? [Int],
            intervalMinutes: args["intervalMinutes"] as? Int,
            dayOfMonth: args["dayOfMonth"] as? Int
        )
    }

    private func getInstructionHistory(_ args: [String: Any]) async throws -> String {
        guard let uuid = args["uuid"] as? String else {
            return jsonError("Missing required parameter: uuid")
        }
        let history = try await StandingInstructionEngine.shared.getExecutionHistory(uuid: uuid)
        return jsonEncode(["uuid": uuid, "history": history, "count": history.count])
    }

    // MARK: - Strategy Tools

    private func getWeeklyContentPlan(_ args: [String: Any]) async throws -> String {
        let recommendations = await ContentStrategyEngine.shared.generateWeeklyPlan()
        let items: [[String: Any]] = recommendations.map { rec in
            [
                "day": rec.dayOfWeek,
                "topic": rec.topic,
                "format": rec.format,
                "hookType": rec.hookType,
                "framework": rec.framework,
                "reasoning": rec.reasoning,
                "matchingSwipes": rec.matchingSwipeUUIDs.count,
                "matchingIdeas": rec.matchingIdeaUUIDs.count,
                "estimatedEngagement": rec.estimatedEngagement
            ] as [String: Any]
        }
        return jsonEncode(["plan": items, "count": items.count])
    }

    private func suggestNextContent(_ args: [String: Any]) async throws -> String {
        let suggestion = await ContentStrategyEngine.shared.suggestNextContent()
        return jsonEncode(["suggestion": suggestion])
    }

    private func analyzeContentGap(_ args: [String: Any]) async throws -> String {
        let analysis = await ContentStrategyEngine.shared.analyzeContentGap()
        return jsonEncode(["analysis": analysis])
    }

    private func predictPerformance(_ args: [String: Any]) async throws -> String {
        guard let text = args["text"] as? String else {
            return jsonError("Missing required parameter: text")
        }
        let hookType = args["hookType"] as? String
        let framework = args["framework"] as? String

        let prediction = await ContentStrategyEngine.shared.predictPerformance(
            draftBody: text,
            hookType: hookType,
            framework: framework
        )
        // Translate numeric scores to plain-language assessment for the LLM
        let overallLabel: String
        if prediction.overallScore >= 80 { overallLabel = "strong" }
        else if prediction.overallScore >= 60 { overallLabel = "decent" }
        else if prediction.overallScore >= 40 { overallLabel = "needs work" }
        else { overallLabel = "weak" }

        let compareLabel: String
        if prediction.comparedToAverage > 1.2 { compareLabel = "above your average" }
        else if prediction.comparedToAverage > 0.8 { compareLabel = "around your average" }
        else { compareLabel = "below your average" }

        return jsonEncode([
            "overall": overallLabel,
            "comparedToAverage": compareLabel,
            "suggestions": prediction.suggestions
        ] as [String: Any])
    }

    private func getSwipeStudyPlan(_ args: [String: Any]) async throws -> String {
        let plan = await SwipePatternMiner.shared.generateSwipeStudyPlan()
        return jsonEncode(["studyPlan": plan])
    }

    // MARK: - Client Profile Tools

    private func listClientProfiles(_ args: [String: Any]) async throws -> String {
        let profiles = try await atomRepo.fetchAll(type: .clientProfile)
        let results: [[String: Any]] = profiles.map { atom in
            let meta = atom.metadataValue(as: ClientProfileMetadata.self)
            return [
                "uuid": atom.uuid,
                "name": atom.title ?? meta?.clientName ?? "Untitled",
                "niche": meta?.niche ?? meta?.industry ?? "",
                "platforms": (meta?.platforms ?? []).map(\.rawValue),
                "hasIntelligenceModel": meta?.intelligenceModel != nil,
                "topPerformingPostCount": meta?.topPerformingPosts?.count ?? meta?.topPerformingTranscripts?.count ?? 0
            ] as [String: Any]
        }
        return jsonEncode([
            "profiles": results,
            "count": results.count
        ] as [String: Any])
    }

    private func getClientProfile(_ args: [String: Any]) async throws -> String {
        guard let clientName = args["client_name"] as? String else {
            return jsonError("Missing required parameter: client_name")
        }

        guard let clientAtom = try await atomRepo.fuzzyFindClient(query: clientName) else {
            return jsonError("No client profile found matching '\(clientName)'")
        }

        guard let meta = clientAtom.metadataValue(as: ClientProfileMetadata.self) else {
            return jsonError("Client profile '\(clientName)' has no metadata")
        }
        await rememberContextAtom(clientAtom)

        var result: [String: Any] = [
            "uuid": clientAtom.uuid,
            "name": meta.clientName,
            "niche": meta.niche ?? meta.industry ?? "",
            "platforms": (meta.platforms).map(\.rawValue),
            "handle": meta.handle ?? "",
            "brandStory": meta.brandStory ?? "",
            "brandVision": meta.brandVision ?? "",
            "uniqueAngle": meta.uniqueAngle ?? "",
            "voiceNotes": meta.voiceNotes ?? "",
            "coreBeliefs": meta.coreBeliefs ?? [],
            "signaturePhrases": meta.signaturePhrases ?? [],
            "targetAudience": meta.targetAudience ?? "",
            "bestFormats": meta.bestFormats ?? [],
            "preferredBeatPatterns": meta.preferredBeatPatterns ?? [],
            "postingFrequency": meta.postingFrequency ?? ""
        ]

        // Include top-performing posts
        if let topPosts = meta.topPerformingPosts, !topPosts.isEmpty {
            result["topPerformingPosts"] = topPosts.map { post in
                [
                    "id": post.id.uuidString,
                    "transcript": post.transcript,
                    "platform": post.platform,
                    "likes": post.likes,
                    "shares": post.shares,
                    "views": post.views,
                    "leads": post.leads,
                    "datePosted": post.datePosted
                ] as [String: Any]
            }
        }
        if let transcripts = meta.topPerformingTranscripts, !transcripts.isEmpty {
            result["topPerformingTranscripts"] = transcripts
        }
        if let documents = meta.documents, !documents.isEmpty {
            result["documents"] = documents.map { document in
                [
                    "id": document.id.uuidString,
                    "category": document.category.rawValue,
                    "categoryLabel": document.category.displayName,
                    "title": document.title,
                    "content": document.content,
                    "filename": document.filename ?? "",
                    "platform": document.platform ?? "",
                    "likes": document.likes ?? 0,
                    "shares": document.shares ?? 0,
                    "saves": document.saves ?? 0,
                    "comments": document.comments ?? 0,
                    "leads": document.leads ?? 0,
                    "sourceURL": document.sourceURL ?? "",
                    "warning": document.warning ?? "",
                    "isHighPerformer": document.category.isHighPerformer,
                    "isUnderperformer": document.category.isUnderperformer
                ] as [String: Any]
            }
        }

        // Include intelligence model summary if available
        if let intModel = meta.intelligenceModel {
            var intel: [String: Any] = [:]

            // Voice fingerprint
            let vf = intModel.voiceFingerprint
            intel["voiceFingerprint"] = [
                "avgSentenceLength": vf.avgSentenceLength,
                "readingLevel": vf.readingLevel,
                "punctuationStyle": vf.punctuationStyle,
                "ctaPattern": vf.ctaPattern,
                "powerWords": vf.powerWords,
                "formattingQuirks": vf.formattingQuirks,
                "signaturePhrases": vf.signaturePhrases,
                "blacklistedPhrases": vf.blacklistedPhrases
            ] as [String: Any]

            // Audience model
            let am = intModel.audienceModel
            intel["audienceModel"] = [
                "primaryAudience": am.primaryAudience,
                "topPainPoints": am.topPainPoints,
                "aspirationalOutcomes": am.aspirationalOutcomes,
                "commonObjections": am.commonObjections
            ] as [String: Any]

            // Failure fingerprint
            if let ff = intModel.failureFingerprint, !ff.rules.isEmpty {
                intel["failureRules"] = ff.rules.map { rule in
                    "[\(rule.severity.rawValue)] \(rule.rule)"
                }
            }

            // Niche and positioning
            intel["niche"] = intModel.nicheAndPositioning.specificNiche
            intel["uniqueAngle"] = intModel.nicheAndPositioning.uniqueAngle
            intel["coreBeliefs"] = intModel.nicheAndPositioning.coreBeliefs

            // Performance fingerprint
            let pf = intModel.performanceFingerprint
            intel["performanceFingerprint"] = [
                "optimalLength": pf.optimalLength,
                "bestTopics": pf.bestTopics,
                "engagementTriggers": pf.engagementTriggers,
                "bestBeatPatterns": pf.bestBeatPatterns
            ] as [String: Any]

            result["intelligenceModel"] = intel
        }

        return jsonEncode(result)
    }

    // MARK: - Intelligence Tools

    private func getCreatorProfile(_ args: [String: Any]) async throws -> String {
        let summary = await CreatorStyleProfiler.shared.getProfileSummary()
        return jsonEncode(["profile": summary])
    }

    private func getAudienceInsights(_ args: [String: Any]) async throws -> String {
        let patterns = await AudienceIntelligenceEngine.shared.getEngagementPatterns()
        let drivers = await AudienceIntelligenceEngine.shared.getGrowthDrivers()
        let profile = await AudienceIntelligenceEngine.shared.getAudienceProfile()

        return jsonEncode([
            "engagementPatterns": patterns,
            "growthDrivers": drivers,
            "audienceProfile": profile
        ])
    }

    private func reviewDraftPersuasion(_ args: [String: Any]) async throws -> String {
        guard let text = args["text"] as? String else {
            return jsonError("Missing required parameter: text")
        }
        let review = await PersuasionCoachEngine.shared.reviewDraft(text: text)
        return jsonEncode(["review": review])
    }

    private func suggestPersuasionStack(_ args: [String: Any]) async throws -> String {
        guard let topic = args["topic"] as? String else {
            return jsonError("Missing required parameter: topic")
        }
        guard let platform = args["platform"] as? String else {
            return jsonError("Missing required parameter: platform")
        }
        let suggestion = await PersuasionCoachEngine.shared.suggestPersuasionStack(topic: topic, platform: platform)
        return jsonEncode(["suggestion": suggestion])
    }

    private func compareToSwipe(_ args: [String: Any]) async throws -> String {
        guard let text = args["text"] as? String else {
            return jsonError("Missing required parameter: text")
        }
        guard let swipeUUID = args["swipeUUID"] as? String else {
            return jsonError("Missing required parameter: swipeUUID")
        }
        let comparison = await PersuasionCoachEngine.shared.compareToSwipe(draftText: text, swipeUUID: swipeUUID)
        return jsonEncode(["comparison": comparison])
    }

    // MARK: - Scoring Tools

    private func getBeatPatterns(_ args: [String: Any]) async throws -> String {
        let format = args["format"] as? String
        let niche = args["niche"] as? String
        let limit = min(args["limit"] as? Int ?? 5, 20)

        let patterns = await BeatPatternService.shared.findTopPatterns(
            format: format,
            niche: niche,
            limit: limit
        )

        let items: [[String: Any]] = patterns.map { pattern in
            [
                "fingerprint": pattern.fingerprint,
                "beatSequence": pattern.beatSequence,
                "frequency": pattern.frequency,
                "avgHookScore": pattern.avgHookScore,
                "swipeCount": pattern.swipeUUIDs.count
            ] as [String: Any]
        }

        return jsonEncode([
            "patterns": items,
            "count": items.count
        ] as [String: Any])
    }

    private func scoreDraft(_ args: [String: Any]) async throws -> String {
        guard let contentUUID = args["contentUUID"] as? String else {
            return jsonError("Missing required parameter: contentUUID")
        }
        guard let contentAtom = try await atomRepo.fetch(uuid: contentUUID) else {
            return jsonError("Content atom not found: \(contentUUID)")
        }

        guard let state = ContentFocusModeState.from(atom: contentAtom) else {
            return jsonError("Could not load content state for \(contentUUID). Ensure the content has a draft body.")
        }

        let engine = ContentScorecardEngine()
        do {
            let scorecard = try await engine.evaluate(contentAtom: contentAtom, state: state)

            var result: [String: Any] = [
                "success": true,
                "contentUUID": contentUUID,
                "hookScore": scorecard.hookScore.score,
                "copyScore": scorecard.copyScore.score,
                "ctaScore": scorecard.ctaScore.score,
                "voiceMatchPercentage": scorecard.voiceMatch.percentage,
                "structuralAlignmentScore": scorecard.structuralAlignment.alignmentScore,
                "overallConfidence": scorecard.overallConfidence,
                "hookSuggestions": scorecard.hookScore.suggestions,
                "copySuggestions": scorecard.copyScore.suggestions,
                "ctaSuggestions": scorecard.ctaScore.suggestions,
                "structuralSuggestions": scorecard.structuralAlignment.suggestions,
                "draftBeats": scorecard.structuralAlignment.draftBeats,
                "recommendedBeats": scorecard.structuralAlignment.recommendedBeats,
                "slideCount": scorecard.slideAnalysis.count
            ]

            if let originality = scorecard.originalityScore {
                result["originalityScore"] = originality.score
                result["originalitySuggestions"] = originality.suggestions
            }

            // Voice drifts summary
            if !scorecard.voiceMatch.drifts.isEmpty {
                let driftSummaries: [[String: Any]] = scorecard.voiceMatch.drifts.prefix(5).map { drift in
                    [
                        "lineNumber": drift.lineNumber,
                        "issue": drift.issue,
                        "suggestion": drift.suggestion
                    ] as [String: Any]
                }
                result["voiceDrifts"] = driftSummaries
            }

            // Generate guided feedback
            let feedback = engine.generateGuidedFeedback(
                scores: scorecard,
                matchedSwipes: [],
                clientVoice: nil
            )
            if !feedback.isEmpty {
                result["guidedFeedback"] = feedback
            }

            return jsonEncode(result)
        } catch {
            return jsonError("Scorecard evaluation failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Insight Memory Tools (WP6)

    private func saveAnalysis(_ args: [String: Any]) async throws -> String {
        guard let title = args["title"] as? String else {
            return jsonError("Missing required parameter: title")
        }
        guard let content = args["content"] as? String else {
            return jsonError("Missing required parameter: content")
        }

        let clientName = args["clientName"] as? String
        let tags = args["tags"] as? [String] ?? []

        // Build metadata
        var meta: [String: Any] = [
            "subtype": "agent_analysis",
            "tags": tags
        ]
        if let clientName = clientName {
            meta["clientName"] = clientName
        }
        let metadataJSON = (try? JSONSerialization.data(withJSONObject: meta))
            .flatMap { String(data: $0, encoding: .utf8) }

        let structuredDict: [String: Any] = [
            "savedAt": ISO8601DateFormatter().string(from: Date()),
            "tags": tags,
            "clientName": clientName ?? ""
        ]
        let structuredJSON = (try? JSONSerialization.data(withJSONObject: structuredDict))
            .flatMap { String(data: $0, encoding: .utf8) }

        let atom = Atom.new(
            type: .agentLearning,
            title: title,
            body: content,
            structured: structuredJSON,
            metadata: metadataJSON
        )

        _ = try await atomRepo.create(atom)

        // Auto-store as batch analysis report if tags indicate a content type analysis
        let batchTypes = ["carousel", "reel", "thread", "tiktok", "youtube", "newsletter", "instagram_carousel", "instagram_reel"]
        let matchedType = tags.first { tag in
            batchTypes.contains { tag.localizedCaseInsensitiveContains($0) }
        }
        if let sourceType = matchedType {
            // Extract swipe count from title (e.g., "30 carousel swipes analysis") or default
            let swipeCount = title.components(separatedBy: " ")
                .compactMap { Int($0) }
                .first ?? 30
            await MainActor.run {
                PromptTemplateStore.shared.saveBatchAnalysisReport(
                    sourceType: sourceType,
                    swipeCount: swipeCount,
                    content: content
                )
            }
        }

        return jsonEncode([
            "success": true,
            "uuid": atom.uuid,
            "title": title,
            "message": "Analysis saved. It will be available in future sessions via get_saved_analyses."
        ] as [String: Any])
    }

    private func getSavedAnalyses(_ args: [String: Any]) async throws -> String {
        let clientName = args["clientName"] as? String
        let filterTags = args["tags"] as? [String] ?? []
        let limit = args["limit"] as? Int ?? 10

        let allLearnings = try await atomRepo.fetchAll(type: .agentLearning)

        // Filter to agent_analysis subtype
        let analyses = allLearnings.filter { atom in
            guard let meta = atom.metadata,
                  let data = meta.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let subtype = dict["subtype"] as? String,
                  subtype == "agent_analysis" else { return false }

            // Filter by client name if specified
            if let filterClient = clientName {
                let atomClient = dict["clientName"] as? String ?? ""
                if !atomClient.localizedCaseInsensitiveContains(filterClient) { return false }
            }

            // Filter by tags if specified
            if !filterTags.isEmpty {
                let atomTags = dict["tags"] as? [String] ?? []
                let hasMatchingTag = filterTags.contains { filterTag in
                    atomTags.contains { $0.localizedCaseInsensitiveContains(filterTag) }
                }
                if !hasMatchingTag { return false }
            }

            return true
        }

        let results: [[String: Any]] = analyses.prefix(limit).map { atom in
            let meta = atom.metadataDict ?? [:]
            return [
                "uuid": atom.uuid,
                "title": atom.title ?? "Untitled",
                "content": String((atom.body ?? "").prefix(500)),
                "tags": meta["tags"] as? [String] ?? [],
                "clientName": meta["clientName"] as? String ?? "",
                "createdAt": atom.createdAt
            ] as [String: Any]
        }

        return jsonEncode([
            "success": true,
            "count": results.count,
            "analyses": results
        ] as [String: Any])
    }

    // MARK: - Telegram UX

    // MARK: - Module Management

    private func suggestModuleAddition(_ args: [String: Any]) async throws -> String {
        guard let action = args["action"] as? String else {
            return jsonError("Missing required parameter: action")
        }
        guard let content = args["content"] as? String else {
            return jsonError("Missing required parameter: content")
        }
        guard let reason = args["reason"] as? String else {
            return jsonError("Missing required parameter: reason")
        }

        let suggestion: PendingModuleSuggestion

        if action == "add_to_module" {
            guard let moduleId = args["moduleId"] as? String else {
                return jsonError("Missing required parameter: moduleId for add_to_module action")
            }
            guard PromptTemplateStore.shared.modules.contains(where: { $0.id == moduleId }) else {
                return jsonError("Unknown module ID: \(moduleId). Use one of: \(PromptTemplateStore.shared.modules.map(\.id).joined(separator: ", "))")
            }
            suggestion = PendingModuleSuggestion(
                id: UUID(),
                action: action,
                moduleId: moduleId,
                content: content,
                reason: reason,
                newModuleTitle: nil,
                newModuleId: nil
            )
        } else if action == "create_module" {
            guard let newModuleTitle = args["newModuleTitle"] as? String else {
                return jsonError("Missing required parameter: newModuleTitle for create_module action")
            }
            guard let newModuleId = args["newModuleId"] as? String else {
                return jsonError("Missing required parameter: newModuleId for create_module action")
            }
            guard !PromptTemplateStore.shared.modules.contains(where: { $0.id == newModuleId }) else {
                return jsonError("Module ID '\(newModuleId)' already exists")
            }
            suggestion = PendingModuleSuggestion(
                id: UUID(),
                action: action,
                moduleId: nil,
                content: content,
                reason: reason,
                newModuleTitle: newModuleTitle,
                newModuleId: newModuleId
            )
        } else {
            return jsonError("Invalid action: \(action). Must be 'add_to_module' or 'create_module'")
        }

        pendingModuleSuggestions.append(suggestion)

        let targetName: String
        if action == "add_to_module", let moduleId = suggestion.moduleId {
            targetName = PromptTemplateStore.shared.modules.first(where: { $0.id == moduleId })?.title ?? moduleId
        } else {
            targetName = suggestion.newModuleTitle ?? "New Module"
        }

        return jsonEncode([
            "success": true,
            "message": "Suggested \(action == "create_module" ? "new module" : "addition to") \(targetName). Waiting for user approval.",
            "suggestionId": suggestion.id.uuidString
        ] as [String: Any])
    }

    /// Drain all pending module suggestions (called after agent message is sent).
    func drainPendingModuleSuggestions() -> [PendingModuleSuggestion] {
        let drained = pendingModuleSuggestions
        pendingModuleSuggestions.removeAll()
        return drained
    }

    private func sendTelegramButtons(_ args: [String: Any]) async throws -> String {
        guard let message = args["message"] as? String else {
            return jsonError("Missing required parameter: message")
        }
        guard let buttons = args["buttons"] as? [[String: Any]], !buttons.isEmpty else {
            return jsonError("Missing required parameter: buttons (non-empty array)")
        }

        // Resolve chat ID from active Telegram session
        guard let chatId = TelegramBridgeService.shared.activeChatId else {
            return jsonError("No active Telegram chat")
        }

        // Build inline keyboard rows (max 3 buttons per row, max 8 total)
        let capped = Array(buttons.prefix(8))
        var rows: [[[String: String]]] = []
        var currentRow: [[String: String]] = []

        for btn in capped {
            guard let label = btn["label"] as? String,
                  let action = btn["action"] as? String else { continue }

            currentRow.append([
                "text": label,
                "callback_data": "agent_btn:\(action)"
            ])

            if currentRow.count >= 3 {
                rows.append(currentRow)
                currentRow = []
            }
        }
        if !currentRow.isEmpty {
            rows.append(currentRow)
        }

        guard !rows.isEmpty else {
            return jsonError("No valid buttons provided")
        }

        let success = await TelegramBridgeService.shared.sendMessage(
            chatId: chatId,
            text: message,
            parseMode: "Markdown",
            replyMarkup: rows
        )

        return jsonEncode([
            "success": success,
            "buttonCount": capped.count
        ] as [String: Any])
    }

    // MARK: - In-App Action Buttons

    private func sendActionButtons(_ args: [String: Any]) async throws -> String {
        guard let message = args["message"] as? String else {
            return jsonError("Missing required parameter: message")
        }
        guard let buttons = args["buttons"] as? [[String: Any]], !buttons.isEmpty else {
            return jsonError("Missing required parameter: buttons (non-empty array)")
        }

        let capped = Array(buttons.prefix(8))
        var parsed: [(label: String, action: String)] = []
        for btn in capped {
            guard let label = btn["label"] as? String,
                  let action = btn["action"] as? String else { continue }
            parsed.append((label: label, action: action))
        }

        guard !parsed.isEmpty else {
            return jsonError("No valid buttons provided")
        }

        onActionButtons?(message, parsed)

        return jsonEncode([
            "success": true,
            "buttonCount": parsed.count
        ] as [String: Any])
    }

    // MARK: - Web Search

    private func webSearch(_ args: [String: Any]) async throws -> String {
        guard let query = args["query"] as? String, !query.isEmpty else {
            return jsonError("Missing required parameter: query")
        }
        let maxResults = args["maxResults"] as? Int ?? 5

        do {
            let result = try await ResearchService.shared.performResearch(
                query: query,
                searchType: .web,
                maxResults: maxResults
            )

            var findings: [[String: Any]] = []
            for finding in result.findings {
                findings.append([
                    "title": finding.title,
                    "snippet": finding.snippet ?? "",
                    "url": finding.url ?? ""
                ] as [String: Any])
            }

            return jsonEncode([
                "success": true,
                "query": query,
                "summary": result.summary,
                "findings": findings,
                "count": findings.count
            ] as [String: Any])
        } catch {
            return jsonEncode([
                "success": false,
                "error": "Web search failed: \(error.localizedDescription)",
                "query": query
            ] as [String: Any])
        }
    }

    // MARK: - Automations

    private func createAutomation(_ args: [String: Any]) async throws -> String {
        guard let name = args["name"] as? String else {
            return jsonError("name is required")
        }

        let triggerStr = args["trigger"] as? String ?? "atom_created"
        let conditionStr = args["condition"] as? String
        let actionStr = args["action"] as? String ?? "show_notification"
        let scopeStr = args["scope"] as? String ?? "global"

        // Parse scope
        let scope: AutomationScope
        var scopeId: String?
        if scopeStr.contains(":") {
            let parts = scopeStr.split(separator: ":")
            scope = AutomationScope(rawValue: String(parts[0])) ?? .global
            scopeId = String(parts[1])
        } else {
            scope = AutomationScope(rawValue: scopeStr) ?? .global
        }

        // Parse trigger type from natural language
        let triggerType = parseTriggerType(triggerStr)
        var triggerConfig: [String: String] = [:]
        if let atomType = parseAtomTypeFromTrigger(triggerStr) {
            triggerConfig["atomType"] = atomType
        }

        // Parse conditions
        var conditions: [AutomationCondition] = []
        if let cond = conditionStr {
            if let parsed = parseConditionNL(cond) {
                conditions.append(parsed)
            }
        }

        // Parse action
        let action = parseActionNL(actionStr)

        let rule = AutomationRule.create(
            name: name,
            scope: scope,
            scopeId: scopeId,
            triggerType: triggerType,
            triggerConfig: triggerConfig,
            conditions: conditions,
            actions: [action]
        )

        let saved = try await AutomationDispatcher.shared.createRule(rule)

        return jsonEncode([
            "success": true,
            "uuid": saved.uuid,
            "name": name,
            "message": "Automation rule '\(name)' created and active."
        ] as [String: Any])
    }

    private func listAutomations(_ args: [String: Any]) async throws -> String {
        let rules = try await AutomationDispatcher.shared.fetchAllRules()

        let ruleList = rules.map { rule -> [String: Any] in
            [
                "uuid": rule.uuid,
                "name": rule.name,
                "trigger": rule.triggerType.rawValue,
                "scope": rule.scope.rawValue,
                "isEnabled": rule.isEnabled,
                "fireCount": rule.fireCount
            ]
        }

        return jsonEncode([
            "rules": ruleList,
            "count": rules.count
        ] as [String: Any])
    }

    private func toggleAutomation(_ args: [String: Any]) async throws -> String {
        guard let uuid = args["uuid"] as? String else {
            return jsonError("uuid is required")
        }

        try await AutomationDispatcher.shared.toggleRule(uuid: uuid)

        return jsonEncode([
            "success": true,
            "uuid": uuid,
            "message": "Automation toggled."
        ] as [String: Any])
    }

    private func deleteAutomation(_ args: [String: Any]) async throws -> String {
        guard let uuid = args["uuid"] as? String else {
            return jsonError("uuid is required")
        }

        try await AutomationDispatcher.shared.deleteRule(uuid: uuid)

        return jsonEncode([
            "success": true,
            "uuid": uuid,
            "message": "Automation deleted."
        ] as [String: Any])
    }

    // MARK: - NL Parsing Helpers (Automation)

    private func parseTriggerType(_ input: String) -> AutomationTriggerType {
        let lower = input.lowercased()
        if lower.contains("status") && lower.contains("change") { return .statusChanged }
        if lower.contains("link") { return .linkCreated }
        if lower.contains("idea") || lower.contains("content") || lower.contains("swipe") || lower.contains("task") || lower.contains("research") {
            return .atomTypeCreated
        }
        return .atomCreated
    }

    private func parseAtomTypeFromTrigger(_ input: String) -> String? {
        let lower = input.lowercased()
        if lower.contains("idea") { return "idea" }
        if lower.contains("content") { return "content" }
        if lower.contains("swipe") || lower.contains("research") { return "research" }
        if lower.contains("task") { return "task" }
        return nil
    }

    private func parseConditionNL(_ input: String) -> AutomationCondition? {
        let lower = input.lowercased()
        if lower.contains("telegram") {
            return AutomationCondition(field: .captureSource, op: .equals, value: .string("telegram"))
        }
        if lower.contains("client") {
            return AutomationCondition(field: .atomClientUUID, op: .isSet, value: .bool(true))
        }
        return nil
    }

    private func parseActionNL(_ input: String) -> AutomationAction {
        let lower = input.lowercased()
        if lower.contains("telegram") || lower.contains("notify") && lower.contains("telegram") {
            return AutomationAction(
                type: .sendTelegram,
                config: ["message": .string("⚡ {{atom.title}} — automation fired")],
                label: "Send Telegram notification"
            )
        }
        if lower.contains("notify") || lower.contains("notification") {
            return AutomationAction(
                type: .showNotification,
                config: ["message": .string("Rule fired for {{atom.title}}")],
                label: "Show notification"
            )
        }
        if lower.contains("status") {
            // Extract target status
            let words = input.split(separator: " ")
            let statusValue = words.last.map(String.init) ?? "developing"
            return AutomationAction(
                type: .setStatus,
                config: ["status": .string(statusValue)],
                label: "Set status to \(statusValue)"
            )
        }
        if lower.contains("analyz") || lower.contains("enrich") {
            return AutomationAction(
                type: .runAnalysis,
                config: ["analysisType": .string("quickEnrich")],
                label: "Run analysis"
            )
        }
        return AutomationAction(
            type: .showNotification,
            config: ["message": .string("Rule fired for {{atom.title}}")],
            label: "Show notification"
        )
    }
}

// Note: Uses Atom.metadataDict from Atom.swift (returns [String: Any]?)
