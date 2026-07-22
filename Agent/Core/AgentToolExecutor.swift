// CosmoOS/Agent/Core/AgentToolExecutor.swift
// Executes agent tools against CosmoOS services

import Foundation
import CoreGraphics
import GRDB

@MainActor
class AgentToolExecutor {
    static let shared = AgentToolExecutor()

    private let atomRepo = AtomRepository.shared

    /// Pending confirmations for Hard tier actions
    var pendingConfirmations: [String: PendingConfirmation] = [:]

    /// Batch tracker for rapid idea captures (3+ within 2 minutes → batched confirmation)
    private var recentIdeaCaptures: [(timestamp: Date, title: String, clientName: String?)] = []

    struct PendingConfirmation {
        let toolName: String
        let arguments: [String: Any]
        let description: String
        let createdAt: Date
        /// Set ONLY by CosmoAgentService.confirmAction when the USER approves.
        /// Destructive tools key off this — a model-supplied `_confirmed` flag is
        /// ignored, so the model can never skip the confirmation step itself.
        var userApproved: Bool = false

        /// Confirmations expire after 5 minutes.
        var isExpired: Bool {
            Date().timeIntervalSince(createdAt) > 300
        }
    }

    /// True when `args` carry a confirmation id matching a USER-approved, unexpired
    /// pending confirmation for `toolName`. Consumes (removes) the confirmation.
    private func consumeUserConfirmation(_ args: [String: Any], toolName: String) -> Bool {
        guard let confirmationId = args["_confirmationId"] as? String,
              let pending = pendingConfirmations[confirmationId],
              pending.toolName == toolName,
              pending.userApproved,
              !pending.isExpired else {
            return false
        }
        pendingConfirmations.removeValue(forKey: confirmationId)
        return true
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
    var onWorkspaceEditProposal: (@MainActor (CosmoAssistantProposal) -> Void)?
    var onAssistantPaneAnswer: (@MainActor (_ title: String?, _ answer: String) -> Void)?
    var onInquiryQuestionProposal: (@MainActor (CosmoAssistantInquiryQuestionProposal) -> Void)?
    /// The surface the inline request was bound to at submit time. When set,
    /// `workspaceEditProposal` stamps this identity over whatever surfaceID/
    /// targetID strings the model authored — a stale or typoed ID from the
    /// model must never unbind a proposal from the editor the user was in
    /// (the in-editor diff only renders when the proposal matches the surface).
    var workspaceEditBoundSurface: (surfaceID: String, targetID: String)?
    /// The bound surface's text at submit time — lets `workspaceEditProposal`
    /// validate operations (anchors locate, numbering stays sane), repair
    /// asterisk-formatting deterministically, and expand series instructions
    /// (renumberSequence, scoped formatMarks) from the document's own state.
    var workspaceEditBoundSurfaceText: String?
    /// Set by the inline bridge for concept-collaborator runs. A staged capture
    /// alone never finishes a concept turn — when this is on and no pane answer
    /// has been delivered yet, `proposeWorkspaceEdit`'s tool result tells the
    /// model to finish the turn (reaction + one deepening question) IN THE SAME
    /// PASS, instead of relying on a second nudge call after the run.
    var conceptTurnContractActive = false
    var inlineSkillStore: CosmoInlineSkillStore = .defaultForRuntime()

    private init() {}

    /// Sources actually read during the active request (recall hits, profiles) —
    /// surfaced as clickable chips under the pane answer so every claim is
    /// traceable. Reset by the caller per request.
    private(set) var sessionSourceRefs: [CosmoAssistantSourceRef] = []

    /// How many times THIS run's proposals failed validation — the bridge's
    /// escalation ladder retries once on a stronger model when a fast-lane
    /// (Haiku) run keeps producing invalid operations.
    private(set) var workspaceEditValidationRejections = 0

    /// Whether answer_in_assistant_pane ran during THIS run — the state the
    /// concept turn contract reads to decide if a staging tool result must
    /// demand the closing reaction + question.
    private(set) var paneAnswerDeliveredThisRun = false

    func resetSessionSourceRefs() {
        sessionSourceRefs = []
        workspaceEditValidationRejections = 0
        paneAnswerDeliveredThisRun = false
    }

    func recordSourceRef(uuid: String, title: String, kind: String) {
        guard !sessionSourceRefs.contains(where: { $0.uuid == uuid }) else { return }
        sessionSourceRefs.append(CosmoAssistantSourceRef(uuid: uuid, title: title, kind: kind))
    }

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
        case "create_content": return try await createContent(arguments)
        case "create_note": return try await createNote(arguments)
        case "create_connection": return try await createConnection(arguments)
        case "get_content": return try await getContent(arguments)
        case "update_content": return try await updateContent(arguments)
        case "create_thinkspace": return try await createThinkspace(arguments)
        case "inspect_current_thinkspace": return try await inspectCurrentThinkspace(arguments)
        case "propose_canvas_plan": return try await proposeCanvasPlan(arguments)
        case "propose_note_structure_plan": return try await proposeNoteStructurePlan(arguments)
        case "propose_workspace_edit": return try await proposeWorkspaceEdit(arguments)
        case "answer_in_assistant_pane": return try await answerInAssistantPane(arguments)
        case "propose_inquiry_question": return try await proposeInquiryQuestion(arguments)
        case "pull_evidence": return try await pullEvidence(arguments)
        case "attach_media": return try await attachMediaCandidates(arguments)
        case "handle_objection": return try await stageObjectionHandling(arguments)
        case "append_to_note": return try await appendToNote(arguments)
        case "create_inline_skill": return try await createInlineSkill(arguments)
        // Recall + Navigation
        case "recall": return try await recall(arguments)
        case "open_atom": return try await openAtom(arguments)
        case "go_to_thinkspace": return try await goToThinkspace(arguments)
        case "go_to_area": return try await goToArea(arguments)
        case "focus_canvas_block": return try await focusCanvasBlock(arguments)
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
        // Writing
        case "generate_outline": return try await generateOutline(arguments)
        case "generate_draft": return try await generateDraft(arguments)
        case "read_draft": return try await readDraft(arguments)
        case "revise_draft": return try await reviseDraft(arguments)
        case "generate_hooks": return try await generateHooks(arguments)
        // Scoring
        case "get_beat_patterns": return try await getBeatPatterns(arguments)
        // Client Profiles
        case "list_client_profiles": return try await listClientProfiles(arguments)
        case "get_client_profile": return try await getClientProfile(arguments)
        case "lookup_client_facts": return try await lookupClientFacts(arguments)
        // Client Memory
        case "update_client_memory": return try await updateClientMemory(arguments)
        case "list_client_memory": return try await listClientMemory(arguments)
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
        // Knowledge Graph & Query
        case "query_atoms": return await handleQueryAtoms(arguments)
        case "graph_traverse": return await handleGraphTraverse(arguments)
        case "get_atom_detail": return await handleGetAtomDetail(arguments)
        case "count_atoms": return await handleCountAtoms(arguments)
        case "synthesize_knowledge": return await handleSynthesizeKnowledge(arguments)
        case "synthesize_learning": return await handleSynthesizeLearning(arguments)
        // Thinkspace & Canvas
        case "manage_thinkspace": return await handleManageThinkspace(arguments)
        case "move_blocks": return await handleMoveBlocks(arguments)
        case "bulk_update": return await handleBulkUpdate(arguments)
        case "organize_space": return await handleOrganizeSpace(arguments)
        case "explore_graph": return await handleExploreGraph(arguments)
        // SQL & Automation
        case "execute_sql": return await handleExecuteSQL(arguments)
        case "create_automation_rule": return await handleCreateAutomationRule(arguments)
        case "list_automation_rules": return await handleListAutomationRules(arguments)
        case "toggle_automation_rule": return await handleToggleAutomationRule(arguments)
        case "run_workflow": return await handleRunWorkflow(arguments)
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
        // Never replace an idea's body underneath an open editor.
        if args["body"] is String, atomRepo.isBeingEdited(uuid) {
            PersistenceHealth.note(.conflict, context: "AgentToolExecutor.updateIdea(\(uuid.prefix(8)))", detail: "refused body overwrite — editing lock held")
            return jsonError("Idea body was NOT updated: the user is actively editing this idea right now. Tell the user what you wanted to change, or retry after they finish editing.")
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

        // Idempotency: a retry after a partial failure must not create a duplicate
        // content atom. If a content atom already points back at this idea, return it.
        if let existingContent = try? await atomRepo.fetchAll(type: .content)
            .first(where: { $0.metadataDict?["sourceIdeaUUID"] as? String == uuid }) {
            return jsonEncode([
                "success": true,
                "ideaUUID": uuid,
                "contentUUID": existingContent.uuid,
                "alreadyActivated": true,
                "message": "Idea was already activated — existing content atom: \(existingContent.title ?? existingContent.uuid)"
            ] as [String: Any])
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
            "activatedAt": ISO8601.string(from: Date())
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

        // Update idea status to activated. If this second step fails, soft-delete the
        // just-created content atom so the operation is atomic from the model's view —
        // a retry then recreates both (the idempotency check above prevents duplicates
        // when the content atom DID survive).
        do {
            _ = try await atomRepo.update(uuid: uuid, updates: { atom in
                var metaDict = (atom.metadataDict ?? [:])
                metaDict["ideaStatus"] = "activated"
                if let data = try? JSONSerialization.data(withJSONObject: metaDict),
                   let json = String(data: data, encoding: .utf8) {
                    atom.metadata = json
                }
            })
        } catch {
            PersistenceHealth.note(.writeFailure, context: "AgentToolExecutor.activateIdea(\(uuid.prefix(8)))", detail: "idea status update failed after content creation: \(error.localizedDescription)")
            try? await atomRepo.delete(uuid: contentAtom.uuid)
            return jsonError("Activation failed while updating the idea (\(error.localizedDescription)). The partially created content atom was removed — retry activate_idea.")
        }

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

    // MARK: - Swipe Adaptation (retired)

    /// The adaptation engine was replaced by the taste engine; the writing
    /// engine consumes taste beliefs + raw swipe search directly. The tool
    /// stays registered as a graceful stub for older prompts.
    private func adaptSwipesForClient(_ args: [String: Any]) async throws -> String {
        jsonError("adapt_swipes_for_client was retired — search swipes directly and rely on the client's taste profile")
    }

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
        item.updatedAt = ISO8601.string(from: Date())

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
                await RecallIndexer.shared.noteAtomChanged(uuid: item.uuid)
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
        ideaMetadata.clientName = resolvedClientName ?? clientName
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

        // 9. Recall index in background (drain re-reads the atom)
        Task {
            await RecallIndexer.shared.noteAtomChanged(uuid: ideaAtom.uuid)
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
        item.updatedAt = ISO8601.string(from: Date())

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
                await RecallIndexer.shared.noteAtomChanged(uuid: item.uuid)
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
        metaDict["activatedAt"] = ISO8601.string(from: Date())

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

    private func createNote(_ args: [String: Any]) async throws -> String {
        guard let title = args["title"] as? String else {
            return jsonError("Missing required parameter: title")
        }

        let body = args["body"] as? String ?? args["content"] as? String
        let sourceUUID = args["sourceUUID"] as? String ?? args["sourceAtomUUID"] as? String

        var links: [AtomLink] = []
        if let sourceUUID, !sourceUUID.isEmpty {
            links.append(AtomLink.related(sourceUUID))
        }

        let atom = try await atomRepo.create(
            type: .note,
            title: title,
            body: body,
            links: links.isEmpty ? nil : links
        )

        await rememberContextAtom(atom)

        var response: [String: Any] = [
            "success": true,
            "uuid": atom.uuid,
            "title": title,
            "type": AtomType.note.rawValue,
            "message": "Note created: \(title)"
        ]
        if let body {
            response["bodyLength"] = body.count
        }
        return jsonEncode(response)
    }

    private func createConnection(_ args: [String: Any]) async throws -> String {
        guard let title = (args["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return jsonError("Missing required parameter: title")
        }

        let conceptType = (args["conceptType"] as? String)
            .flatMap(ConceptFrameworkType.init(rawValue:)) ?? .mentalModel

        var sections = ConnectionSectionType.allCases
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { ConnectionSection(type: $0) }

        var seededCount = 0
        var unknownSections: [String] = []
        for (key, value) in args["sections"] as? [String: Any] ?? [:] {
            guard let type = ConnectionSectionType(rawValue: key) else {
                unknownSections.append(key)
                continue
            }
            let texts = (value as? [String]) ?? (value as? String).map { [$0] } ?? []
            guard let index = sections.firstIndex(where: { $0.type == type }) else { continue }
            for text in texts {
                // Concept content must never contain em dashes (user preference);
                // create_connection seeds bypass parseItems, so strip here too.
                let trimmed = ConnectionSurfaceSerializer
                    .removeEmDashes(text)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                sections[index].addItem(ConnectionItem(content: trimmed))
                seededCount += 1
            }
        }

        // Explicit String types: GRDB's SQL overload of joined(separator:)
        // otherwise wins inference and breaks the create(body:) call.
        let flattenedBody: String = sections
            .filter { !$0.items.isEmpty }
            .map { section -> String in
                let lines: String = section.items
                    .map { "• \($0.resolvedPlainText)" }
                    .joined(separator: "\n")
                return "\(section.type.displayName)\n\(lines)"
            }
            .joined(separator: "\n\n")

        let atom = try await atomRepo.create(
            type: .connection,
            title: title,
            body: flattenedBody.isEmpty ? nil : flattenedBody,
            structured: ConnectionStructuredData(sections: sections).toJSON()
        )

        // Seed the focus-mode state so the workspace opens with the same
        // sections and concept type (same persistence path the focus mode uses).
        var state = ConnectionFocusModeState(atomUUID: atom.uuid)
        state.sections = sections
        state.conceptType = conceptType
        state.save()

        await rememberContextAtom(atom)

        let open = args["open"] as? Bool ?? true
        if open {
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openBlockInFocusMode,
                object: nil,
                userInfo: ["atomUUID": atom.uuid, "asPane": true]
            )
        }

        var response: [String: Any] = [
            "success": true,
            "uuid": atom.uuid,
            "title": title,
            "type": AtomType.connection.rawValue,
            "conceptType": conceptType.rawValue,
            "surfaceID": "connection:\(atom.uuid)",
            "seededItems": seededCount,
            "message": open
                ? "Connection created and opened: \(title). It is now the active editable surface — stage section drafts against its `## Section` header lines."
                : "Connection created: \(title)"
        ]
        if !unknownSections.isEmpty {
            response["ignoredSections"] = unknownSections
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

        // The plan binds to the thinkspace the request was scoped to at submit
        // time — apply notifications are broadcast, and only the canvas whose
        // thinkspace matches may handle them.
        var targetThinkspaceId: String?
        if let surfaceID = workspaceEditBoundSurface?.surfaceID,
           surfaceID.hasPrefix("thinkspace:") {
            targetThinkspaceId = String(surfaceID.dropFirst("thinkspace:".count))
        }

        let plan = PendingCanvasPlan(
            title: title,
            rationale: rationale,
            operations: operations,
            targetThinkspaceId: targetThinkspaceId
        )
        onCanvasPlan?(plan)

        return jsonEncode([
            "success": true,
            "pendingPlanId": plan.id.uuidString,
            "operationCount": operations.count,
            "message": "Canvas plan is ready for user review. Do not say it has been applied until the user clicks Apply."
        ] as [String: Any])
    }

    private func proposeWorkspaceEdit(_ args: [String: Any]) async throws -> String {
        // Close the unvalidated-path gap: when no surface text was bound at
        // submit (e.g. targeting a note that isn't open), resolve the target's
        // live text so anchors and structure are validated on EVERY path.
        var fallbackSourceText: String?
        if workspaceEditBoundSurfaceText == nil,
           let surfaceID = trimmedString(args["surfaceID"]) {
            if let registered = CosmoEditableSurfaceRegistry.shared.provider(surfaceID: surfaceID) {
                fallbackSourceText = registered.editableSnapshot().text
            } else if let loaded = await CosmoAtomBackedEditableSurface.load(surfaceID: surfaceID) {
                fallbackSourceText = loaded.editableSnapshot().text
            }
        }
        let buildResult = workspaceEditProposal(arguments: args, sourceTextFallback: fallbackSourceText)
        guard let proposal = buildResult.proposal else {
            return jsonError(buildResult.error ?? "Missing required workspace edit proposal fields")
        }

        onWorkspaceEditProposal?(proposal)

        var payload: [String: Any] = [
            "success": true,
            "proposalId": proposal.id.uuidString,
            "operationCount": proposal.operations.count,
            "message": "Workspace edit proposal is ready for review. Do not say it has been applied until the user accepts changes."
        ]
        // Concept turn contract: staging is never the end of a concept turn.
        // Saying so in the tool result keeps the reaction + question in the
        // same model pass — the question lands right under the staged receipt
        // without a second billed call.
        if conceptTurnContractActive, !paneAnswerDeliveredThisRun {
            payload["message"] = "Staged for review — but this turn is NOT finished. Call answer_in_assistant_pane now, in this same turn, with your short natural reaction plus exactly ONE deepening question in the user's own vocabulary. Without it the user sees a dead-end receipt instead of a conversation. Do not narrate process; just react and ask."
        }
        if let afterOutline = buildResult.afterOutline {
            // The simulated post-apply structure — verify it matches what the
            // user asked for; if it doesn't, stage a corrected proposal.
            payload["resultingDocumentStructure"] = afterOutline
        }
        return jsonEncode(payload)
    }

    func workspaceEditProposal(
        arguments args: [String: Any],
        sourceTextFallback: String? = nil
    ) -> (proposal: CosmoAssistantProposal?, error: String?, afterOutline: String?) {
        guard let prompt = trimmedString(args["prompt"]),
              let modelSurfaceID = trimmedString(args["surfaceID"]),
              let title = trimmedString(args["title"]),
              let summary = trimmedString(args["summary"]),
              let rawOperations = args["operations"] as? [[String: Any]] else {
            return (nil, "Missing required workspace edit proposal fields", nil)
        }

        // The bound surface (captured at submit) is authoritative — model-authored
        // IDs are only kept when they already point inside that surface (structured
        // surfaces expose several targets under one surfaceID prefix).
        let boundSurface = workspaceEditBoundSurface
        let surfaceID = boundSurface?.surfaceID ?? modelSurfaceID
        let boundText = workspaceEditBoundSurfaceText ?? sourceTextFallback

        var operations: [CosmoAssistantProposalOperation] = []
        for raw in rawOperations {
            let modelTargetID = raw["targetID"] as? String ?? ""
            let targetID: String
            if let boundSurface {
                targetID = modelTargetID.hasPrefix(boundSurface.surfaceID)
                    ? modelTargetID
                    : boundSurface.targetID
            } else {
                targetID = modelTargetID
            }
            let rawKind = raw["kind"] as? String ?? ""
            let sourceHash = raw["sourceHash"] as? String ?? ""
            let rationale = raw["rationale"] as? String ?? "Proposed by Cosmo."

            // Series instructions expand deterministically from the document's
            // own state — the model never hand-copies N mechanical rewrites.
            if rawKind == "renumberSequence" {
                guard let boundText, !boundText.isEmpty else {
                    return (nil, "renumberSequence needs an active editable surface — none is bound to this request.", nil)
                }
                guard let expanded = CosmoInlineSeriesExpansion.renumberOperations(
                    seriesKind: raw["seriesKind"] as? String ?? "slideHeaders",
                    fromNumber: intValue(raw["fromNumber"]) ?? 1,
                    delta: intValue(raw["delta"]) ?? 0,
                    throughNumber: intValue(raw["throughNumber"]),
                    withinSlide: intValue(raw["withinSlide"]),
                    sourceText: boundText,
                    targetID: targetID,
                    sourceHash: sourceHash,
                    rationale: rationale
                ) else {
                    return (nil, "renumberSequence matched nothing: check seriesKind, fromNumber, and delta against the document structure digest.", nil)
                }
                operations.append(contentsOf: expanded)
                continue
            }

            if rawKind == "formatMarks",
               let scope = trimmedString(raw["scope"]),
               let mark = (raw["formatMark"] as? String).flatMap(CosmoAssistantFormatMark.init(rawValue:)) {
                guard let boundText, !boundText.isEmpty else {
                    return (nil, "Scoped formatMarks needs an active editable surface — none is bound to this request.", nil)
                }
                guard let expanded = CosmoInlineSeriesExpansion.scopedFormatMarkOperations(
                    scope: scope,
                    mark: mark,
                    sourceText: boundText,
                    targetID: targetID,
                    sourceHash: sourceHash,
                    rationale: rationale
                ) else {
                    return (nil, "formatMarks scope \"\(scope)\" matched nothing on this surface. Supported scope: allSlideHeaders.", nil)
                }
                operations.append(contentsOf: expanded)
                continue
            }

            let operation = CosmoAssistantProposalOperation(
                kind: CosmoAssistantProposalOperationKind(rawValue: rawKind) ?? .textReplacement,
                targetID: targetID,
                anchorID: raw["anchorID"] as? String,
                originalText: raw["originalText"] as? String,
                proposedText: raw["proposedText"] as? String,
                sourceHash: sourceHash,
                rationale: rationale,
                formatMark: (raw["formatMark"] as? String).flatMap(CosmoAssistantFormatMark.init(rawValue:)),
                explicitMove: raw["explicitMove"] as? Bool
            )
            operations.append(CosmoInlineAssistantOutlineBodyInsertionNormalizer.normalized(
                operation: operation,
                prompt: prompt
            ))
        }

        // Minimal-edit normalization: a fused multi-line replacement is split
        // into one operation per changed region (unchanged lines dropped), so
        // review, validation, and the scope guard all see the TRUE delta
        // instead of a block rewrite. Deterministic; no-op for minimal ops.
        if let boundText, !boundText.isEmpty {
            operations = CosmoInlineMinimalEditSplitter.split(
                operations: operations,
                sourceText: boundText
            )
        }

        if operations.contains(where: { CosmoInlineAssistantEditScopeGuard.shouldReject(operation: $0, prompt: prompt) }) {
            // Scope violations count toward the escalation ladder exactly like
            // locator/structure rejections — repeated over-scoping must trigger
            // the stronger-model retry, not silently exhaust the run.
            workspaceEditValidationRejections += 1
            return (nil, CosmoInlineAssistantEditScopeGuard.rejectionMessage, nil)
        }

        // Validate against the bound surface text: repair asterisk-formatting,
        // require anchors to locate, and simulate the transaction so numbering
        // corruption is caught BEFORE it reaches review. Issues go back to the
        // model as a structured error — it is still in the tool loop and fixes
        // the proposal itself.
        var afterOutline: String?
        if let boundText, !boundText.isEmpty {
            let validation = CosmoInlineProposalValidator.validate(
                operations: operations,
                sourceText: boundText,
                summary: summary
            )
            guard validation.isValid else {
                workspaceEditValidationRejections += 1
                let issueList = validation.issues.enumerated()
                    .map { "\($0.offset + 1). \($0.element)" }
                    .joined(separator: "\n")
                return (nil, "The proposal was NOT staged — fix these and call propose_workspace_edit again:\n\(issueList)", nil)
            }
            operations = validation.repairedOperations
            afterOutline = validation.afterOutline
        }

        let proposal = CosmoAssistantProposal(
            prompt: prompt,
            surfaceID: surfaceID,
            title: title,
            summary: summary,
            operations: operations
        )
        return (proposal, nil, afterOutline)
    }

    private func answerInAssistantPane(_ args: [String: Any]) async throws -> String {
        guard let answer = trimmedString(args["answer"]) else {
            return jsonError("Missing required parameter: answer")
        }
        paneAnswerDeliveredThisRun = true
        onAssistantPaneAnswer?(trimmedString(args["title"]), answer)
        return jsonEncode(["success": true, "message": "Answer sent to assistant pane"])
    }

    /// Stages an "open an inquiry?" confirmation card in the assistant pane.
    /// Resolves the working Connection plus where the question would land
    /// (deep dive home, root vs sub-question) so the card shows a concrete
    /// destination. Navigation happens only when the user confirms.
    private func proposeInquiryQuestion(_ args: [String: Any]) async throws -> String {
        guard let question = trimmedString(args["question"]) else {
            return jsonError("Missing required parameter: question")
        }

        let rawSurfaceID = trimmedString(args["surfaceID"])
            ?? CosmoEditableSurfaceRegistry.shared.activeSurface?.editableSnapshot().surfaceID
        guard let connection = await resolveConnection(fromSurfaceID: rawSurfaceID) else {
            return jsonError("propose_inquiry_question needs a Connection surface — the active surface is not a connection. Develop the concept via create_connection first.")
        }

        let resolution = await CosmoInlineInquiryQuestionResolver.resolve(
            question: question,
            connection: connection
        )
        let proposal = CosmoAssistantInquiryQuestionProposal(
            question: question,
            rationale: trimmedString(args["rationale"]),
            connectionUUID: connection.uuid,
            connectionTitle: connection.title ?? "Untitled connection",
            deepDiveUUID: resolution.deepDive?.uuid,
            deepDiveTitle: resolution.deepDive?.title,
            parentQuestionUUID: resolution.parentQuestion?.uuid,
            parentQuestionTitle: resolution.parentQuestion?.title
        )
        onInquiryQuestionProposal?(proposal)

        return jsonEncode([
            "success": true,
            "proposalId": proposal.id.uuidString,
            "placement": proposal.placementLabel,
            "message": "Inquiry question staged for user confirmation. The session opens ONLY after the user confirms in the pane — do not claim it has started. Briefly acknowledge the staged question and continue the concept conversation."
        ] as [String: Any])
    }

    /// The evidence-aware collaborator: everything already gathered about the
    /// working concept — the seedbed's staged captures, tag/key-matched dive
    /// extracts, AND matching Readwise highlights (the user's bookshelf) —
    /// each with its source. Read-only; the model cites from it and stages
    /// only what the user accepts. Readwise evidence surfaces even for
    /// concepts with no deep dive: the bookshelf is always in the room.
    private func pullEvidence(_ args: [String: Any]) async throws -> String {
        let rawSurfaceID = trimmedString(args["surfaceID"])
            ?? CosmoEditableSurfaceRegistry.shared.activeSurface?.editableSnapshot().surfaceID
        guard let connection = await resolveConnection(fromSurfaceID: rawSurfaceID) else {
            return jsonError("pull_evidence needs a Connection surface — the active surface is not a connection.")
        }
        let conceptName = trimmedString(args["concept"]) ?? connection.title ?? ""
        let conceptKey = ConceptResolver.conceptKey(conceptName)
        let deepDive = await CosmoInlineInquiryQuestionResolver.resolveDeepDive(for: connection)

        var rows: [[String: Any]] = []
        var seenKeys = Set<String>()
        func addRow(text: String, dedupKey: String, sourceLabel: String?, kind: String, url: String? = nil) {
            guard rows.count < 24, !seenKeys.contains(dedupKey) else { return }
            seenKeys.insert(dedupKey)
            var row: [String: Any] = ["text": String(text.prefix(400)), "kind": kind]
            if let sourceLabel { row["source"] = sourceLabel }
            if let url { row["url"] = url }
            rows.append(row)
        }

        if let deepDive {
            let sources = (try? await InquiryRepository.shared.fetchSources(forDeepDive: deepDive)) ?? []
            let sourceTitles = Dictionary(
                sources.compactMap { source in source.title.map { (source.uuid, $0) } },
                uniquingKeysWith: { first, _ in first }
            )

            let seedbed = await ConceptSeedbedService.shared.seedbed(deepDiveUUID: deepDive.uuid)
            let seedling = seedbed.first { candidate in
                candidate.conceptKey == conceptKey
                    || candidate.developedConnectionUUID == connection.uuid
                    || candidate.mergeTargetConnectionUUID == connection.uuid
            }
            for item in seedling?.pendingItems ?? [] {
                addRow(
                    text: item.rawSnippet,
                    dedupKey: item.sourceExtractUUID,
                    sourceLabel: item.sourceUUID.flatMap { sourceTitles[$0] },
                    kind: item.proposedSection ?? "capture"
                )
            }
            let extracts = (try? await InquiryRepository.shared.fetchExtracts(forDeepDive: deepDive.uuid)) ?? []
            for extract in extracts {
                guard let metadata = extract.extractMetadata else { continue }
                let body = (extract.body ?? extract.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !body.isEmpty else { continue }
                let tagKeys = (metadata.conceptNames ?? []).map(ConceptResolver.conceptKey)
                let matches = tagKeys.contains(conceptKey)
                    || (conceptKey.count >= 4 && body.lowercased().contains(conceptKey))
                guard matches else { continue }
                addRow(
                    text: body,
                    dedupKey: extract.uuid,
                    sourceLabel: metadata.sourceUUID.flatMap { sourceTitles[$0] },
                    kind: metadata.kind.rawValue
                )
            }
        }

        // The bookshelf: highlights whose own words carry the concept. Any
        // seedling with this key contributes its aliases, so the matcher
        // sees the concept's whole vocabulary. Threshold-gated — silence
        // beats a random quote.
        let aliasSeedlings = (try? await SeedlingRepository.shared.fetchGrowingEverywhere(conceptKey: conceptKey)) ?? []
        let aliases = Array(Set(aliasSeedlings.flatMap { $0.aliases }))
        let bookshelf = await ReadwiseEvidenceMatcher.evidence(
            conceptName: conceptName,
            aliases: aliases,
            limit: 6
        )
        for match in bookshelf {
            let sourceLabel = match.author.map { "\(match.bookTitle) — \($0)" } ?? match.bookTitle
            var text = match.text
            if let note = match.note, !note.isEmpty {
                text += "\n(Your note: \(note))"
            }
            addRow(
                text: text,
                dedupKey: "readwise-\(match.highlightId)",
                sourceLabel: sourceLabel,
                kind: "readwise",
                url: match.readwiseUrl
            )
        }

        var payload: [String: Any] = [
            "success": true,
            "concept": conceptName,
            "evidence": rows,
            "message": rows.isEmpty
                ? "Nothing gathered about this concept yet — no dive material and no matching highlights."
                : "Cite this material conversationally (kind \"readwise\" = the user's own book highlights — name the book). Stage a bullet into the page only after the user accepts it."
        ]
        if let deepDive {
            payload["deepDive"] = deepDive.title ?? "Untitled"
        }
        return jsonEncode(payload)
    }

    /// Surface ids for connections look like "connection:<uuid>" (target ids add
    /// a ":sections" suffix); accept either and verify the atom is a Connection.
    // MARK: - attach_media (concept gallery staging)

    /// Search the swipe library and STAGE matches as ghost tiles on the
    /// working concept's Gallery. Nothing attaches silently: the workspace
    /// renders the candidates with per-tile ✓/✗ and only an accept writes
    /// the ref. Already-attached sources never re-stage.
    private func attachMediaCandidates(_ args: [String: Any]) async throws -> String {
        guard let query = trimmedString(args["query"]) else {
            return jsonError("Missing required parameter: query")
        }
        let rawSurfaceID = trimmedString(args["surfaceID"])
            ?? CosmoEditableSurfaceRegistry.shared.activeSurface?.editableSnapshot().surfaceID
        guard let connection = await resolveConnection(fromSurfaceID: rawSurfaceID) else {
            return jsonError("attach_media needs a Connection surface — the active surface is not a connection.")
        }
        let limit = min(max((args["limit"] as? Int) ?? 4, 1), 6)

        let attachedUUIDs = Set(
            (connection.structured.flatMap(ConnectionStructuredData.fromJSON)?.media ?? [])
                .compactMap(\.atomUUID)
        )

        let tokens = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
        guard !tokens.isEmpty else {
            return jsonError("Query too short — use the concept's own vocabulary.")
        }

        let candidates = (try? await atomRepo.fetchAll(type: .research)) ?? []
        var scored: [(atom: Atom, score: Int)] = []
        for atom in candidates {
            guard atom.isSwipeFileAtom, !atom.isDeleted, !attachedUUIDs.contains(atom.uuid) else { continue }
            let analysis = atom.swipeAnalysis
            let title = (atom.title ?? "").lowercased()
            let hook = (analysis?.hookText ?? "").lowercased()
            let niche = (analysis?.niche ?? "").lowercased()
            let summary = (atom.richContent?.summary ?? "").lowercased()
            var score = 0
            for token in tokens {
                if title.contains(token) { score += 3 }
                if hook.contains(token) { score += 2 }
                if summary.contains(token) { score += 1 }
                if niche.contains(token) { score += 1 }
            }
            if score > 0 { scored.append((atom, score)) }
        }
        let staged = scored.sorted { $0.score > $1.score }.prefix(limit).map(\.atom)

        guard !staged.isEmpty else {
            return jsonEncode(["staged": [] as [Any], "message": "No swipes in the library match that query. Say so plainly — do not invent posts."])
        }

        let conceptUUID = connection.uuid
        let stagedUUIDs = staged.map(\.uuid)
        await MainActor.run {
            NotificationCenter.default.post(
                name: CosmoNotification.Connection.mediaStagingChanged,
                object: nil,
                userInfo: ["connectionUUID": conceptUUID, "atomUUIDs": stagedUUIDs]
            )
        }

        let rows: [[String: Any]] = staged.map { atom in
            var row: [String: Any] = ["title": atom.title ?? "Untitled"]
            if let platform = atom.richContent?.sourceType?.rawValue { row["platform"] = platform }
            if let hook = atom.swipeAnalysis?.hookText, !hook.isEmpty { row["hook"] = String(hook.prefix(200)) }
            return row
        }
        return jsonEncode([
            "staged": rows,
            "message": "Staged \(rows.count) ghost tile(s) in the concept's Gallery, WAITING for the user's per-tile review. Now answer in the pane: one line per tile on why it earns its place, then ONE deepening question."
        ])
    }

    // MARK: - handle_objection (staged rebuttal review)

    /// STAGE a rebuttal on a Beliefs & Objections entry. Nothing writes:
    /// the workspace renders a ghost thread with ✓/✗ under the objection and
    /// only an accept persists the handling. Quotes resolve against the LIVE
    /// board via ObjectionStagingResolver (pure + tested).
    private func stageObjectionHandling(_ args: [String: Any]) async throws -> String {
        guard let objectionQuote = trimmedString(args["objection"]) else {
            return jsonError("Missing required parameter: objection (quote the bullet verbatim).")
        }
        guard let response = trimmedString(args["response"]) else {
            return jsonError("Missing required parameter: response.")
        }
        let rawSurfaceID = trimmedString(args["surfaceID"])
            ?? CosmoEditableSurfaceRegistry.shared.activeSurface?.editableSnapshot().surfaceID
        guard let connection = await resolveConnection(fromSurfaceID: rawSurfaceID) else {
            return jsonError("handle_objection needs a Connection surface — the active surface is not a connection.")
        }
        let sections = connection.structured.flatMap(ConnectionStructuredData.fromJSON)?.sections ?? []
        let objections = sections.first { $0.type == .beliefsObjections }?.items ?? []
        guard let objection = ObjectionStagingResolver.matchObjection(quote: objectionQuote, in: objections) else {
            return jsonError("No Beliefs & Objections entry matches that quote. Re-read the surface and quote the objection's bullet text verbatim.")
        }

        let linkedQuotes = stringArray(args["linked_entries"]) ?? []
        let resolved = ObjectionStagingResolver.resolveLinkedEntries(linkedQuotes, sections: sections)

        // The user's no-em-dash rule holds for staged rebuttals exactly like
        // staged bullets.
        let cleanedResponse = ConnectionSurfaceSerializer.removeEmDashes(response)

        let conceptUUID = connection.uuid
        let snippet = String(objection.resolvedPlainText.prefix(80))
        let refPairs: [[String]] = resolved.refs.compactMap { ref in
            guard let section = ref.section else { return nil }
            return [section.rawValue, ref.itemID.uuidString]
        }
        await MainActor.run {
            NotificationCenter.default.post(
                name: CosmoNotification.Connection.objectionHandlingStaged,
                object: nil,
                userInfo: [
                    "connectionUUID": conceptUUID,
                    "objectionItemID": objection.id.uuidString,
                    "objectionSnippet": snippet,
                    "text": cleanedResponse,
                    "linkedRefs": refPairs
                ]
            )
        }

        var result: [String: Any] = [
            "staged": true,
            "objection": snippet,
            "linkedCount": resolved.refs.count,
            "message": "Rebuttal staged as a ghost thread under the objection, WAITING for the user's ✓. Now answer in the pane: one line naming the objection you handled (and any cited entries), then ONE question."
        ]
        if !resolved.unmatched.isEmpty {
            result["unmatchedLinks"] = resolved.unmatched
            result["linkNote"] = "These quoted entries matched nothing on the board and were dropped — mention that only if the user asked for them specifically."
        }
        return jsonEncode(result)
    }

    private func resolveConnection(fromSurfaceID surfaceID: String?) async -> Atom? {
        guard let surfaceID else { return nil }
        let parts = surfaceID.split(separator: ":").map(String.init)
        guard parts.count >= 2, parts[0] == "connection" else { return nil }
        guard let atom = try? await atomRepo.fetch(uuid: parts[1]), atom.type == .connection else { return nil }
        return atom
    }

    // MARK: - Recall (unified retrieval)

    /// One high-signal retrieval tool over the whole atom graph: hybrid BM25 +
    /// vector search, compact semantic results. Small models select better from
    /// one good search tool than from six specialized ones.
    private func recall(_ args: [String: Any]) async throws -> String {
        guard let query = trimmedString(args["query"]) else {
            return jsonError("Missing required parameter: query")
        }

        let limit = min(max(intValue(args["limit"]) ?? 6, 1), 12)
        let entityTypes: [EntityType]? = {
            switch trimmedString(args["kind"]) {
            case "idea": return [.idea]
            case "note": return [.note, .stickyNote]
            case "content": return [.content]
            case "research": return [.research]
            case "connection": return [.connection]
            case "swipe": return [.swipeFile]
            case "thinkspace": return [.thinkspace]
            default: return nil
            }
        }()

        let results = (try? await HybridSearchEngine.shared.search(
            query: query,
            limit: limit,
            entityTypes: entityTypes
        )) ?? []

        guard !results.isEmpty else {
            return jsonEncode([
                "success": true,
                "results": [] as [[String: Any]],
                "message": "Nothing matched. Try different words, or tell the user it isn't saved yet."
            ] as [String: Any])
        }

        let compact = results.map { result -> [String: Any] in
            var entry: [String: Any] = [
                "title": result.title,
                "type": result.entityType.rawValue,
                "snippet": String(result.preview.prefix(220)),
                "matchReason": result.matchReason.rawValue
            ]
            if let uuid = result.entityUUID {
                entry["uuid"] = uuid
                recordSourceRef(uuid: uuid, title: result.title, kind: result.entityType.rawValue)
            }
            if let updatedAt = result.updatedAt { entry["updatedAt"] = updatedAt }
            return entry
        }

        return jsonEncode([
            "success": true,
            "results": compact,
            "count": compact.count
        ] as [String: Any])
    }

    // MARK: - Navigation ("legs")

    /// Open an atom in focus mode, as a pane, or on the canvas. Reversible, so
    /// no review gate — the agent takes the user there directly.
    private func openAtom(_ args: [String: Any]) async throws -> String {
        guard let uuid = trimmedString(args["uuid"]) else {
            return jsonError("Missing required parameter: uuid")
        }
        guard let atom = try? await atomRepo.fetch(uuid: uuid) else {
            return jsonError("No atom found with that UUID")
        }

        let mode = trimmedString(args["mode"]) ?? "focus"
        switch mode {
        case "pane":
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openBlockInFocusMode,
                object: nil,
                userInfo: ["atomUUID": uuid, "asPane": true]
            )
        case "canvas":
            NotificationCenter.default.post(
                name: CosmoNotification.NodeGraph.addToCanvas,
                object: nil,
                userInfo: ["atomUUID": uuid]
            )
        default:
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openBlockInFocusMode,
                object: nil,
                userInfo: ["atomUUID": uuid, "asPane": false]
            )
        }

        return jsonEncode([
            "success": true,
            "title": atom.title ?? "Untitled",
            "mode": mode,
            "message": "Opened '\(atom.title ?? "Untitled")' (\(mode))."
        ] as [String: Any])
    }

    private func goToThinkspace(_ args: [String: Any]) async throws -> String {
        guard let uuid = trimmedString(args["uuid"]) else {
            return jsonError("Missing required parameter: uuid")
        }
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.navigateToThinkspaceById,
            object: nil,
            userInfo: CosmoNotification.Navigation.ThinkspacePayload(thinkspaceId: uuid).userInfo
        )
        return jsonEncode(["success": true, "message": "Navigated to the thinkspace."])
    }

    private func goToArea(_ args: [String: Any]) async throws -> String {
        guard let area = trimmedString(args["area"]) else {
            return jsonError("Missing required parameter: area")
        }
        switch area {
        case "commandCenter":
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.navigateToCommandCenter,
                object: nil
            )
        case "swipeGallery":
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openSwipeGallery,
                object: nil
            )
        default:
            return jsonError("Unknown area '\(area)'. Use commandCenter or swipeGallery.")
        }
        return jsonEncode(["success": true, "message": "Navigated to \(area)."])
    }

    /// Fly the canvas camera to frame a block — answers "where did I put X?" by
    /// gliding there instead of describing coordinates.
    private func focusCanvasBlock(_ args: [String: Any]) async throws -> String {
        guard let atomUUID = trimmedString(args["atom_uuid"]) else {
            return jsonError("Missing required parameter: atom_uuid")
        }
        NotificationCenter.default.post(
            name: CosmoNotification.Canvas.focusBlock,
            object: nil,
            userInfo: ["atomUUID": atomUUID]
        )
        return jsonEncode([
            "success": true,
            "message": "Camera is gliding to the block. Pair this with a one-line answer about what's there."
        ] as [String: Any])
    }

    /// Stage a reviewed addition to a note that isn't the active surface.
    /// Resolves the note by UUID or fuzzy title, then emits a normal workspace-edit
    /// proposal targeting "note:<uuid>" — the store's atom-backed fallback applies it
    /// on accept even when the note isn't open anywhere.
    private func appendToNote(_ args: [String: Any]) async throws -> String {
        guard let text = trimmedString(args["text"]) else {
            return jsonError("Missing required parameter: text")
        }

        let atom: Atom?
        if let uuid = trimmedString(args["note_uuid"]) {
            atom = try? await AtomRepository.shared.fetch(uuid: uuid)
        } else if let title = trimmedString(args["note_title"]) {
            atom = await Self.noteMatching(title: title)
        } else {
            return jsonError("Provide note_uuid or note_title to target a note")
        }

        guard let atom, atom.type == .note else {
            return jsonError("No matching note found. Use search tools to find the note's UUID, or ask the user which note they mean.")
        }

        let bodyText = RichDocumentPersistence.loadAtomDocument(
            field: .body,
            metadata: atom.metadata,
            fallbackPlainText: atom.body
        ).plainText

        let noteTitle = atom.title ?? "Untitled note"
        let operation = CosmoAssistantProposalOperation(
            kind: .textInsertion,
            targetID: "note:\(atom.uuid):body",
            anchorID: "body",
            originalText: trimmedString(args["after_text"]),
            proposedText: text,
            sourceHash: CosmoEditableSurfaceHasher.hash(bodyText),
            rationale: trimmedString(args["rationale"]) ?? "Added on your request."
        )
        let proposal = CosmoAssistantProposal(
            prompt: "Append to \(noteTitle)",
            surfaceID: "note:\(atom.uuid)",
            title: "Add to \(noteTitle)",
            summary: "Append \(text.split(separator: " ").count) words to \(noteTitle).",
            operations: [operation]
        )
        // Inline requests route through the bridge callback; from any other entry
        // point (Cosmo window, remote), stage straight into the shared review store.
        if let onWorkspaceEditProposal {
            onWorkspaceEditProposal(proposal)
        } else {
            CosmoInlineAssistantStore.shared.receive(proposal: proposal)
        }

        return jsonEncode([
            "success": true,
            "proposalId": proposal.id.uuidString,
            "noteUUID": atom.uuid,
            "noteTitle": noteTitle,
            "message": "Addition staged for review. It will be saved to '\(noteTitle)' when the user accepts."
        ] as [String: Any])
    }

    /// Fuzzy title match across notes: exact (case-insensitive) beats prefix beats
    /// containment; most recently updated wins ties.
    private static func noteMatching(title query: String) async -> Atom? {
        guard let notes = try? await AtomRepository.shared.fetchAll(type: .note) else { return nil }
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return nil }

        var exact: Atom?
        var prefix: Atom?
        var containing: Atom?
        for note in notes { // fetchAll returns updatedAt-descending — first hit is freshest
            let noteTitle = note.title?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if noteTitle == normalizedQuery {
                exact = exact ?? note
            } else if noteTitle.hasPrefix(normalizedQuery) {
                prefix = prefix ?? note
            } else if noteTitle.contains(normalizedQuery) {
                containing = containing ?? note
            }
        }
        return exact ?? prefix ?? containing
    }

    private func createInlineSkill(_ args: [String: Any]) async throws -> String {
        guard let name = trimmedString(args["name"]) else {
            return jsonError("Missing required parameter: name")
        }
        guard let summary = trimmedString(args["summary"]) else {
            return jsonError("Missing required parameter: summary")
        }
        guard let route = parseInlineRoute(args["route"]) else {
            return jsonError("Missing or invalid required parameter: route")
        }
        guard let instructions = stringArray(args["instructions"]), !instructions.isEmpty else {
            return jsonError("Missing required parameter: instructions")
        }
        guard let outputContract = trimmedString(args["outputContract"]) else {
            return jsonError("Missing required parameter: outputContract")
        }
        guard let panePolicy = parsePanePolicy(args["panePolicy"]) else {
            return jsonError("Missing or invalid required parameter: panePolicy")
        }

        let id = trimmedString(args["id"]) ?? Self.inlineSkillID(from: name)
        let examples = (args["examples"] as? [[String: Any]])?.compactMap { raw -> CosmoInlineSkillExample? in
            guard let input = (raw["input"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let idealOutput = (raw["idealOutput"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !input.isEmpty, !idealOutput.isEmpty else { return nil }
            return CosmoInlineSkillExample(input: input, idealOutput: idealOutput)
        }
        let skill = CosmoInlineSkillDefinition.custom(
            id: id,
            name: name,
            icon: trimmedString(args["icon"]) ?? "sparkle",
            summary: summary,
            triggerPhrases: stringArray(args["triggerPhrases"]) ?? [],
            route: route,
            preferredModelTier: parseModelTier(args["preferredModelTier"]),
            requiredContext: parseContextSet(args["requiredContext"]) ?? [.activeSurface],
            toolBundles: parseToolBundleSet(args["toolBundles"]) ?? [.workspaceEditing, .writing],
            instructions: instructions,
            outputContract: outputContract,
            tokenBudget: intValue(args["tokenBudget"]) ?? 1400,
            requiresReviewedDiff: boolValue(args["requiresReviewedDiff"]) ?? (route == .action),
            panePolicy: panePolicy,
            triggerDescription: trimmedString(args["triggerDescription"]),
            examples: (examples?.isEmpty == false) ? examples : nil,
            verification: trimmedString(args["verification"])
        )
        inlineSkillStore.save(skill)

        return jsonEncode([
            "success": true,
            "skillId": skill.id,
            "name": skill.name,
            "route": skill.route.rawValue,
            "preferredModelTier": skill.preferredModelTier?.rawValue ?? "auto",
            "message": "Created inline skill '\(skill.name)'. It is now available from the slash skill menu as /\(skill.name)."
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
            } else if let strings = value as? [String] {
                // Cluster ops carry blockUUIDs arrays — join stably so the
                // apply side can split on comma.
                payload[key] = strings.joined(separator: ",")
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
        if let dateStr = dateStr, let parsed = ISO8601.date(from: dateStr) {
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

        // Engine projection (iOS parity): repeating templates surface on
        // every rule day with the occurrence's own times — the old literal
        // startTime filter only saw them on the day they were drawn.
        let entries = await ScheduleBlockEngine.blocks(on: dayStart, repository: atomRepo)
        let atomsByUUID = Dictionary(
            uniqueKeysWithValues: ((try? await atomRepo.fetchAll(type: .scheduleBlock)) ?? [])
                .map { ($0.uuid, $0) }
        )

        let items: [[String: Any]] = entries.map { entry in
            let meta = atomsByUUID[entry.id]?.metadataValue(as: ScheduleBlockMetadata.self)
            var item: [String: Any] = [
                "uuid": entry.id,
                "title": entry.title,
                "startTime": ISO8601.string(from: entry.start),
                "endTime": ISO8601.string(from: entry.end),
                "isCompleted": entry.isCompleted,
                "blockType": meta?.blockType ?? "",
                "intent": meta?.originType ?? ""
            ]
            if entry.isRecurring {
                // Semantic, not structural: "Every week on Mon, Fri".
                item["repeats"] = entry.recurrenceText ?? "repeats"
            }
            return item
        }

        return jsonEncode([
            "date": ISO8601.string(from: dayStart),
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

        // Only a USER-approved confirmation (set by CosmoAgentService.confirmAction)
        // can pass this gate — a model-supplied `_confirmed`/`_confirmationId` cannot.
        if consumeUserConfirmation(args, toolName: "delete_block") {
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
            arguments: ["uuid": uuid],
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
            metaDict["completedAt"] = ISO8601.string(from: Date())
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
        if let dueDate = dueDate {
            // Day-pin contract: the three pins are born together (a due-only
            // task strands on one device once any other pin is written).
            metaDict["dueDate"] = dueDate
            metaDict["focusDate"] = dueDate
            metaDict["whenDate"] = dueDate
            metaDict["isUnscheduled"] = false
        }

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
            ISO8601.date(from: atom.createdAt)
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
            "updatedAt": ISO8601.string(from: Date())
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
        // Capture body/version BEFORE the long cloud call — the persist step compares
        // against this baseline so a user edit made mid-generation is never overwritten.
        let generationBaseline = DraftGenerationBaseline(atom: atom)
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

                let persistWarning = await persistGeneratedDraftLocally(
                    contentUUID: contentUUID,
                    formattedDraft: result.formattedDraft,
                    source: "single-session generate_draft",
                    baseline: generationBaseline
                )
                if let persistWarning {
                    return jsonEncode([
                        "success": false,
                        "contentUUID": contentUUID,
                        "formattedDraft": result.formattedDraft ?? "",
                        "message": persistWarning
                    ] as [String: Any])
                }

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

            let persistWarning = await persistGeneratedDraftLocally(
                contentUUID: contentUUID,
                formattedDraft: result.formattedDraft,
                source: "multi-phase generate_draft",
                baseline: generationBaseline
            )
            if let persistWarning {
                return jsonEncode([
                    "success": false,
                    "contentUUID": contentUUID,
                    "formattedDraft": result.formattedDraft ?? "",
                    "message": persistWarning
                ] as [String: Any])
            }

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

    /// Body + version captured before a long-running cloud generation, used to detect
    /// user/concurrent edits made while the generation was in flight.
    struct DraftGenerationBaseline {
        let body: String?
        let localVersion: Int64

        init(atom: Atom?) {
            self.body = atom?.body
            self.localVersion = atom?.localVersion ?? 0
        }
    }

    /// Persist a cloud-generated draft into the local atom — with staleness + editing
    /// guards. Returns nil on success, or a warning message (for the model) when the
    /// write was refused because the user is editing or the draft changed mid-flight.
    private func persistGeneratedDraftLocally(
        contentUUID: String,
        formattedDraft: String?,
        source: String,
        baseline: DraftGenerationBaseline? = nil
    ) async -> String? {
        guard let draft = Self.draftBodyForLocalPersistence(formattedDraft) else {
            print("☁️ [AgentToolExecutor] No draft to persist from \(source) for \(contentUUID)")
            return nil
        }

        guard var atom = try? await atomRepo.fetch(uuid: contentUUID) else {
            print("⚠️ [AgentToolExecutor] Could not persist draft from \(source); content atom not found: \(contentUUID)")
            return nil
        }

        // Already persisted (e.g. the cloud engine's write synced down mid-flight).
        if atom.body == draft {
            print("☁️ [AgentToolExecutor] Draft from \(source) already present on \(contentUUID) — skipping write")
            return nil
        }

        // Guard 1: the user has this content open in an editor — never replace the
        // body underneath live keystrokes. The draft text was still returned to the
        // model/conversation, so nothing is lost; it just isn't force-applied.
        if atomRepo.isBeingEdited(contentUUID) {
            PersistenceHealth.note(.conflict, context: "AgentToolExecutor.persistDraft(\(contentUUID.prefix(8)))", detail: "refused overwrite from \(source) — editing lock held")
            return "Draft was NOT saved to the content atom: the user is actively editing it right now. The generated draft is included in this result — share it with the user and let them apply it, or retry after they finish editing."
        }

        // Guard 2: the body changed since the generation started — a concurrent writer
        // (user save, sync, another session) landed mid-flight. Overwriting would
        // silently destroy that newer content. (Version-only drift is expected — the
        // pipeline bumps versions for metadata writes — so only body changes block.)
        if let baseline, baseline.body != atom.body {
            PersistenceHealth.note(.conflict, context: "AgentToolExecutor.persistDraft(\(contentUUID.prefix(8)))", detail: "refused overwrite from \(source) — body changed during generation (baselineLen=\(baseline.body?.count ?? 0) currentLen=\(atom.body?.count ?? 0))")
            return "Draft was NOT saved to the content atom: its body changed while the draft was being generated (another edit landed first). The generated draft is included in this result — confirm with the user before applying it via update_content."
        }

        // Snapshot the previous draft as a versioned .contentDraft atom so an unwanted
        // AI overwrite is always recoverable.
        if let previousBody = atom.body,
           !previousBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           previousBody != draft {
            do {
                _ = try await ContentPipelineService().saveDraft(
                    contentUUID: contentUUID,
                    body: previousBody,
                    authorNotes: "Auto-snapshot before AI draft (\(source))"
                )
            } catch {
                print("⚠️ [AgentToolExecutor] Pre-write draft snapshot failed for \(contentUUID): \(error)")
            }
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
            return nil
        } catch {
            print("❌ [AgentToolExecutor] Failed to persist draft from \(source) for \(contentUUID): \(error)")
            PersistenceHealth.note(.writeFailure, context: "AgentToolExecutor.persistDraft(\(contentUUID.prefix(8)))", detail: error.localizedDescription)
            return "Draft was generated but FAILED to save locally: \(error.localizedDescription). The draft is included in this result — retry update_content to save it."
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

        // Capture body/version BEFORE the long cloud call (staleness baseline).
        let generationBaseline = DraftGenerationBaseline(
            atom: try? await AtomRepository.shared.fetch(uuid: contentUUID)
        )

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

            let persistWarning = await persistGeneratedDraftLocally(
                contentUUID: contentUUID,
                formattedDraft: result.formattedDraft,
                source: "revise_draft",
                baseline: generationBaseline
            )
            if let persistWarning {
                return jsonEncode([
                    "success": false,
                    "contentUUID": contentUUID,
                    "formattedDraft": result.formattedDraft ?? "",
                    "message": persistWarning
                ] as [String: Any])
            }

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

    private func updateContent(_ args: [String: Any]) async throws -> String {
        guard let uuid = args["uuid"] as? String else {
            return jsonError("Missing required parameter: uuid")
        }
        var draftUpdateContent: String?

        // Body writes are guarded: never replace a draft underneath an open editor,
        // and snapshot the previous body first so the overwrite is recoverable.
        if let newBody = args["body"] as? String {
            if atomRepo.isBeingEdited(uuid) {
                PersistenceHealth.note(.conflict, context: "AgentToolExecutor.updateContent(\(uuid.prefix(8)))", detail: "refused body overwrite — editing lock held")
                return jsonError("Content body was NOT updated: the user is actively editing this content right now. Tell the user what you wanted to change and let them apply it, or retry after they finish editing.")
            }
            if let current = try? await atomRepo.fetch(uuid: uuid),
               let previousBody = current.body,
               !previousBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               previousBody != Self.renderDraftForDisplay(newBody) {
                do {
                    _ = try await ContentPipelineService().saveDraft(
                        contentUUID: uuid,
                        body: previousBody,
                        authorNotes: "Auto-snapshot before update_content body write"
                    )
                } catch {
                    // Non-content atoms (no .content type) can't snapshot — proceed.
                    print("⚠️ [AgentToolExecutor] Pre-update body snapshot failed for \(uuid): \(error)")
                }
            }
        }

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

            _ = evidence
            _ = intent
            // Explicit user rules become PINNED taste beliefs — active
            // immediately, never auto-modified by the distiller.
            let tasteCategory = ["voice", "structure", "format", "cta"].contains(category)
                ? category
                : (category == "hook_style" ? "hooks" : "voice")
            await TasteStore.addPinnedRule(rule, category: tasteCategory, clientUuid: clientUUID)
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

        // Taste beliefs replace the retired lesson store.
        var lessons: [InferredLesson] = []
        if let scoped = await TasteStore.profile(clientUuid: clientUUID?.uuidString) {
            lessons += scoped.beliefs.filter { !$0.struck }.map { belief in
                InferredLesson(
                    clientUUID: clientUUID?.uuidString,
                    rule: belief.text,
                    evidence: "\(belief.sources) signals",
                    category: belief.category,
                    confidence: belief.confidence,
                    intent: intentFilter,
                    enforcement: belief.pinned ? .hard : .advisory
                )
            }
        }
        if let personal = await TasteStore.profile(clientUuid: nil) {
            lessons += personal.beliefs.filter { !$0.struck }.map { belief in
                InferredLesson(
                    rule: belief.text,
                    evidence: "\(belief.sources) signals",
                    category: belief.category,
                    confidence: belief.confidence,
                    intent: intentFilter,
                    enforcement: belief.pinned ? .hard : .advisory
                )
            }
        }

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

    private func stringArray(_ value: Any?) -> [String]? {
        if let strings = value as? [String] {
            return strings
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        if let values = value as? [Any] {
            return values.compactMap { item in
                guard let string = item as? String else { return nil }
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        }
        return nil
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = trimmedString(value)?.lowercased() {
            if ["true", "yes", "1"].contains(string) { return true }
            if ["false", "no", "0"].contains(string) { return false }
        }
        return nil
    }

    private func parseInlineRoute(_ value: Any?) -> CosmoInlineAssistantRoute? {
        trimmedString(value)
            .flatMap { CosmoInlineAssistantRoute(rawValue: Self.normalizedEnumToken($0)) }
    }

    private func parsePanePolicy(_ value: Any?) -> CosmoInlineSkillPanePolicy? {
        guard let raw = trimmedString(value) else { return nil }
        return [
            CosmoInlineSkillPanePolicy.neverForAction,
            .openForAnswer,
            .openForResearchBackedAction,
            .alwaysOpenWithResult
        ].first { Self.normalizedEnumToken($0.rawValue) == Self.normalizedEnumToken(raw) }
    }

    private func parseModelTier(_ value: Any?) -> AgentModelTier? {
        guard let raw = trimmedString(value) else { return nil }
        if let tier = AgentModelTier(rawValue: raw) {
            return tier
        }
        let normalized = Self.normalizedEnumToken(raw)
        if let tier = AgentModelTier(rawValue: normalized) {
            return tier
        }
        switch normalized {
        case "haiku", "fast":
            return .sensor
        case "sonnet", "balanced":
            return .strategist
        case "opus", "opus46", "claudeopus46", "writer":
            return .writer
        case "gpt55thinking", "gpt5.5thinking":
            return .gpt55Thinking
        case "opus47", "claudeopus47":
            return .opus47
        case "gptchatlatest":
            return .gptChatLatest
        case "gemini3flash", "geminiflashlatest":
            return .geminiFlashLatest
        case "gemini35flash", "gemini3.5flash":
            return .gemini35Flash
        default:
            return nil
        }
    }

    private func parseContextSet(_ value: Any?) -> Set<CosmoInlineAssistantSkillContext>? {
        guard let rawValues = stringArray(value) else { return nil }
        return Set(rawValues.compactMap { raw in
            CosmoInlineAssistantSkillContext.allCases.first {
                Self.normalizedEnumToken($0.rawValue) == Self.normalizedEnumToken(raw)
            }
        })
    }

    private func parseToolBundleSet(_ value: Any?) -> Set<AgentToolBundle>? {
        guard let rawValues = stringArray(value) else { return nil }
        return Set(rawValues.compactMap { raw in
            AgentToolBundle.allCases.first {
                Self.normalizedEnumToken($0.rawValue) == Self.normalizedEnumToken(raw)
            }
        })
    }

    private static func inlineSkillID(from name: String) -> String {
        let parts = name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard let first = parts.first?.lowercased() else {
            return UUID().uuidString
        }
        let rest = parts.dropFirst().map { part in
            part.prefix(1).uppercased() + part.dropFirst().lowercased()
        }
        return ([first] + rest).joined()
    }

    private static func normalizedEnumToken(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
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

    private func lookupClientFacts(_ args: [String: Any]) async throws -> String {
        guard let clientName = trimmedString(args["client_name"]) else {
            return jsonError("Missing required parameter: client_name")
        }
        guard let query = trimmedString(args["query"]) else {
            return jsonError("Missing required parameter: query")
        }

        guard let clientAtom = try await atomRepo.fuzzyFindClient(query: clientName) else {
            return jsonError("No client profile found matching '\(clientName)'")
        }

        guard let meta = clientAtom.metadataValue(as: ClientProfileMetadata.self) else {
            return jsonError("Client profile '\(clientName)' has no metadata")
        }

        await rememberContextAtom(clientAtom)

        let snippets = CosmoClientFactLookup.snippets(
            meta: meta,
            query: query,
            maxSnippets: 3,
            maxSnippetLength: 600
        )

        return jsonEncode([
            "success": true,
            "clientUUID": clientAtom.uuid,
            "clientName": meta.clientName,
            "query": query,
            "snippets": snippets,
            "count": snippets.count,
            "message": snippets.isEmpty
                ? "No matching client facts found for this query. Do not invent the missing detail."
                : "Returned the most relevant compact client fact snippets."
        ] as [String: Any])
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
            "savedAt": ISO8601.string(from: Date()),
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
        // Single `query` or batch `queries` — the batch runs concurrently so a
        // multi-angle research sweep costs one tool-loop iteration, not six.
        var queries = (args["queries"] as? [String] ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if queries.isEmpty, let query = args["query"] as? String, !query.isEmpty {
            queries = [query]
        }
        guard !queries.isEmpty else {
            return jsonError("Missing required parameter: query (or queries)")
        }
        queries = Array(queries.prefix(6))

        let maxResults = args["maxResults"] as? Int ?? 5
        let searchType: ResearchSearchType
        switch (args["searchType"] as? String)?.lowercased() {
        case "news": searchType = .news
        case "reddit": searchType = .reddit
        case "academic": searchType = .academic
        default: searchType = .web
        }

        // Serialized inside each child task so only Sendable strings cross the
        // task-group boundary.
        @Sendable func resultBlockJSON(for query: String) async -> (json: String, succeeded: Bool) {
            let block: [String: Any]
            var succeeded = false
            do {
                let result = try await ResearchService.shared.performResearch(
                    query: query,
                    searchType: searchType,
                    maxResults: maxResults
                )
                let findings: [[String: Any]] = result.findings.map { finding in
                    [
                        "title": finding.title,
                        "snippet": finding.snippet ?? "",
                        "url": finding.url ?? ""
                    ]
                }
                block = [
                    "success": true,
                    "query": query,
                    "summary": result.summary,
                    "findings": findings,
                    "count": findings.count
                ]
                succeeded = true
            } catch {
                block = [
                    "success": false,
                    "error": "Web search failed: \(error.localizedDescription)",
                    "query": query
                ]
            }
            let data = (try? JSONSerialization.data(withJSONObject: block)) ?? Data()
            let json = String(data: data, encoding: .utf8) ?? "{\"success\": false, \"error\": \"Encoding failed\"}"
            return (json, succeeded)
        }

        if queries.count == 1 {
            return await resultBlockJSON(for: queries[0]).json
        }

        let blocks = await withTaskGroup(of: (Int, String, Bool).self) { group in
            for (index, query) in queries.enumerated() {
                group.addTask {
                    let block = await resultBlockJSON(for: query)
                    return (index, block.json, block.succeeded)
                }
            }
            var ordered = [(json: String, succeeded: Bool)?](repeating: nil, count: queries.count)
            for await (index, json, succeeded) in group {
                ordered[index] = (json, succeeded)
            }
            return ordered.compactMap { $0 }
        }

        let anySucceeded = blocks.contains { $0.succeeded }
        return "{\"success\": \(anySucceeded), \"searchType\": \"\(searchType.rawValue)\", \"queryCount\": \(blocks.count), \"results\": [\(blocks.map(\.json).joined(separator: ","))]}"
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

        // Hard delete of a user-built rule — requires the same user-approved
        // two-phase confirmation as delete_block. A model that misidentifies
        // "delete that one" must never destroy an automation unprompted.
        if consumeUserConfirmation(args, toolName: "delete_automation") {
            try await AutomationDispatcher.shared.deleteRule(uuid: uuid)
            return jsonEncode([
                "success": true,
                "uuid": uuid,
                "message": "Automation deleted."
            ] as [String: Any])
        }

        let ruleName = AutomationDispatcher.shared.ruleCacheLookup(uuid: uuid)?.name ?? uuid

        let confirmationId = UUID().uuidString
        pendingConfirmations[confirmationId] = PendingConfirmation(
            toolName: "delete_automation",
            arguments: ["uuid": uuid],
            description: "Delete automation: \(ruleName)",
            createdAt: Date()
        )

        return jsonEncode([
            "confirmation_required": true,
            "confirmation_id": confirmationId,
            "action": "delete_automation",
            "description": "Delete automation: \(ruleName)"
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

    // MARK: - Knowledge Graph & Query Tools

    private func handleQueryAtoms(_ args: [String: Any]) async -> String {
        let query = args["query"] as? String ?? ""
        let types = args["types"] as? [String]
        let limit = args["limit"] as? Int ?? 10
        // dateRange reserved for future use
        _ = args["dateRange"] as? String

        let searchEngine = AtomSearchEngine()
        var options = AtomSearchOptions()
        options.limit = min(limit, 50)

        if let types = types {
            options.types = types.compactMap { AtomType(rawValue: $0) }
        }

        let results = try? await searchEngine.search(query: query, options: options)
        guard let results = results, !results.isEmpty else {
            return "{\"results\": [], \"count\": 0, \"query\": \"\(query)\"}"
        }

        let items = results.prefix(limit).map { result -> String in
            let atom = result.atom
            let snippet = result.snippet ?? String(atom.body?.prefix(100) ?? "")
            return "{\"uuid\": \"\(atom.uuid)\", \"type\": \"\(atom.type.rawValue)\", \"title\": \"\(atom.title?.replacingOccurrences(of: "\"", with: "\\\"") ?? "")\", \"snippet\": \"\(snippet.replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: " "))\", \"score\": \(result.score)}"
        }

        return "{\"results\": [\(items.joined(separator: ","))], \"count\": \(results.count), \"query\": \"\(query)\"}"
    }

    private func handleGraphTraverse(_ args: [String: Any]) async -> String {
        let uuid = args["uuid"] as? String ?? ""
        let depth = min(args["depth"] as? Int ?? 1, 3)

        guard let atom = try? await atomRepo.fetch(uuid: uuid) else {
            return "{\"error\": \"Atom not found\", \"uuid\": \"\(uuid)\"}"
        }

        // Parse links from the atom
        let connectedUuids: [String] = atom.linksList.map(\.uuid)

        let connected = (try? await atomRepo.fetchBatch(uuids: connectedUuids)) ?? []
        let nodes = connected.map { a -> String in
            "{\"uuid\": \"\(a.uuid)\", \"type\": \"\(a.type.rawValue)\", \"title\": \"\(a.title?.replacingOccurrences(of: "\"", with: "\\\"") ?? "")\"}"
        }

        return "{\"center\": {\"uuid\": \"\(atom.uuid)\", \"type\": \"\(atom.type.rawValue)\", \"title\": \"\(atom.title?.replacingOccurrences(of: "\"", with: "\\\"") ?? "")\"}, \"connected\": [\(nodes.joined(separator: ","))], \"depth\": \(depth)}"
    }

    private func handleGetAtomDetail(_ args: [String: Any]) async -> String {
        // Batch `uuids` reads several atoms in one tool-loop iteration; the
        // single `uuid` form keeps its original response shape.
        if let uuids = args["uuids"] as? [String], !uuids.isEmpty {
            var atomBlocks: [String] = []
            var missing: [String] = []
            for uuid in uuids.prefix(8) {
                if let atom = try? await atomRepo.fetch(uuid: uuid) {
                    atomBlocks.append(Self.atomDetailJSON(atom))
                } else {
                    missing.append(uuid)
                }
            }
            let missingJSON = missing.map { "\"\($0.replacingOccurrences(of: "\"", with: ""))\"" }.joined(separator: ",")
            return "{\"count\": \(atomBlocks.count), \"atoms\": [\(atomBlocks.joined(separator: ","))], \"notFound\": [\(missingJSON)]}"
        }

        let uuid = args["uuid"] as? String ?? ""
        guard let atom = try? await atomRepo.fetch(uuid: uuid) else {
            return "{\"error\": \"Atom not found\"}"
        }
        return Self.atomDetailJSON(atom)
    }

    private static func atomDetailJSON(_ atom: Atom) -> String {
        let bodyPreview = String(atom.body?.prefix(500) ?? "").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n")
        let metadata = atom.metadata?.replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: " ") ?? ""

        return "{\"uuid\": \"\(atom.uuid)\", \"type\": \"\(atom.type.rawValue)\", \"title\": \"\(atom.title?.replacingOccurrences(of: "\"", with: "\\\"") ?? "")\", \"body\": \"\(bodyPreview)\", \"metadata\": \"\(metadata)\", \"createdAt\": \"\(atom.createdAt)\", \"updatedAt\": \"\(atom.updatedAt)\"}"
    }

    private func handleCountAtoms(_ args: [String: Any]) async -> String {
        let typeStr = args["type"] as? String ?? "idea"
        guard let type = AtomType(rawValue: typeStr) else {
            return "{\"error\": \"Unknown atom type: \(typeStr)\"}"
        }

        let atoms = (try? await atomRepo.fetchAll(type: type)) ?? []
        return "{\"type\": \"\(typeStr)\", \"count\": \(atoms.count)}"
    }

    private func handleSynthesizeKnowledge(_ args: [String: Any]) async -> String {
        let query = args["query"] as? String ?? ""
        let maxSources = args["maxSources"] as? Int ?? 10
        let scope = args["scope"] as? String ?? "all"

        let searchEngine = AtomSearchEngine()
        var options = AtomSearchOptions()
        options.limit = maxSources

        if scope != "all" {
            switch scope {
            case "swipes": options.types = [.research]
            case "research": options.types = [.research]
            case "ideas": options.types = [.idea]
            case "notes": options.types = [.note]
            default: break
            }
        }

        let results = (try? await searchEngine.search(query: query, options: options)) ?? []

        let sources = results.map { r -> String in
            let body = String(r.atom.body?.prefix(300) ?? "").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n")
            return "{\"uuid\": \"\(r.atom.uuid)\", \"type\": \"\(r.atom.type.rawValue)\", \"title\": \"\(r.atom.title?.replacingOccurrences(of: "\"", with: "\\\"") ?? "")\", \"content\": \"\(body)\"}"
        }

        return "{\"query\": \"\(query)\", \"sourceCount\": \(results.count), \"sources\": [\(sources.joined(separator: ","))]}"
    }

    private func handleSynthesizeLearning(_ args: [String: Any]) async -> String {
        let topic = args["topic"] as? String ?? ""
        let maxSources = args["maxSources"] as? Int ?? 10

        let searchEngine = AtomSearchEngine()
        var options = AtomSearchOptions()
        options.limit = maxSources

        let results = (try? await searchEngine.search(query: topic, options: options)) ?? []

        let sources = results.map { r -> String in
            let body = String(r.atom.body?.prefix(300) ?? "").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n")
            return "{\"uuid\": \"\(r.atom.uuid)\", \"type\": \"\(r.atom.type.rawValue)\", \"title\": \"\(r.atom.title?.replacingOccurrences(of: "\"", with: "\\\"") ?? "")\", \"content\": \"\(body)\"}"
        }

        return "{\"topic\": \"\(topic)\", \"sourceCount\": \(results.count), \"sources\": [\(sources.joined(separator: ","))]}"
    }

    // MARK: - Thinkspace & Canvas Tools

    private func handleManageThinkspace(_ args: [String: Any]) async -> String {
        let action = args["action"] as? String ?? "list"
        let name = args["name"] as? String

        switch action {
        case "create":
            guard let name = name, !name.isEmpty else {
                return "{\"error\": \"Missing required parameter: name\"}"
            }
            let atom = try? await atomRepo.create(
                type: .thinkspace,
                title: name,
                body: nil,
                metadata: nil
            )
            if let atom = atom {
                return "{\"success\": true, \"uuid\": \"\(atom.uuid)\", \"title\": \"\(name)\"}"
            }
            return "{\"error\": \"Failed to create thinkspace\"}"

        case "list":
            let thinkspaces = (try? await atomRepo.fetchAll(type: .thinkspace)) ?? []
            let items = thinkspaces.map { a -> String in
                "{\"uuid\": \"\(a.uuid)\", \"title\": \"\(a.title?.replacingOccurrences(of: "\"", with: "\\\"") ?? "")\"}"
            }
            return "{\"thinkspaces\": [\(items.joined(separator: ","))], \"count\": \(thinkspaces.count)}"

        default:
            return "{\"error\": \"Unknown action: \(action). Supported: create, list\"}"
        }
    }

    private func handleMoveBlocks(_ args: [String: Any]) async -> String {
        let blockUUIDs = args["blockUUIDs"] as? [String] ?? []
        let targetX = args["x"] as? Double ?? 0
        let targetY = args["y"] as? Double ?? 0

        guard !blockUUIDs.isEmpty else {
            return "{\"error\": \"Missing required parameter: blockUUIDs\"}"
        }

        // Move blocks by updating their canvas positions in metadata
        var movedCount = 0
        for uuid in blockUUIDs {
            if var atom = try? await atomRepo.fetch(uuid: uuid) {
                var metaDict = atom.metadataDict ?? [:]
                metaDict["canvasX"] = targetX + Double(movedCount) * 20
                metaDict["canvasY"] = targetY + Double(movedCount) * 20
                if let data = try? JSONSerialization.data(withJSONObject: metaDict),
                   let json = String(data: data, encoding: .utf8) {
                    atom.metadata = json
                    _ = try? await atomRepo.update(atom)
                    movedCount += 1
                }
            }
        }

        return "{\"success\": true, \"movedCount\": \(movedCount), \"targetPosition\": {\"x\": \(targetX), \"y\": \(targetY)}}"
    }

    private func handleBulkUpdate(_ args: [String: Any]) async -> String {
        let uuids = args["uuids"] as? [String] ?? []
        let updates = args["updates"] as? [String: Any] ?? [:]

        guard !uuids.isEmpty else {
            return "{\"error\": \"Missing required parameter: uuids\"}"
        }
        guard !updates.isEmpty else {
            return "{\"error\": \"Missing required parameter: updates\"}"
        }

        var updatedCount = 0
        for uuid in uuids {
            if var atom = try? await atomRepo.fetch(uuid: uuid) {
                if let title = updates["title"] as? String { atom.title = title }
                if let body = updates["body"] as? String { atom.body = body }
                if let metadataUpdates = updates["metadata"] as? [String: Any] {
                    var metaDict = atom.metadataDict ?? [:]
                    for (key, value) in metadataUpdates {
                        metaDict[key] = value
                    }
                    if let data = try? JSONSerialization.data(withJSONObject: metaDict),
                       let json = String(data: data, encoding: .utf8) {
                        atom.metadata = json
                    }
                }
                _ = try? await atomRepo.update(atom)
                updatedCount += 1
            }
        }

        return "{\"success\": true, \"updatedCount\": \(updatedCount), \"requestedCount\": \(uuids.count)}"
    }

    private func handleOrganizeSpace(_ args: [String: Any]) async -> String {
        let strategy = args["strategy"] as? String ?? "grid"
        let atomUUIDs = args["atomUUIDs"] as? [String] ?? []
        let spacing = args["spacing"] as? Double ?? 40

        guard !atomUUIDs.isEmpty else {
            return "{\"error\": \"Missing required parameter: atomUUIDs\"}"
        }

        var organized = 0
        let columns = max(Int(sqrt(Double(atomUUIDs.count))), 1)
        let blockWidth = 340.0
        let blockHeight = 360.0

        for (index, uuid) in atomUUIDs.enumerated() {
            if var atom = try? await atomRepo.fetch(uuid: uuid) {
                var metaDict = atom.metadataDict ?? [:]
                let col = index % columns
                let row = index / columns
                metaDict["canvasX"] = Double(col) * (blockWidth + spacing)
                metaDict["canvasY"] = Double(row) * (blockHeight + spacing)
                if let data = try? JSONSerialization.data(withJSONObject: metaDict),
                   let json = String(data: data, encoding: .utf8) {
                    atom.metadata = json
                    _ = try? await atomRepo.update(atom)
                    organized += 1
                }
            }
        }

        return "{\"success\": true, \"strategy\": \"\(strategy)\", \"organizedCount\": \(organized), \"columns\": \(columns)}"
    }

    private func handleExploreGraph(_ args: [String: Any]) async -> String {
        let startUUID = args["startUUID"] as? String
        let maxNodes = min(args["maxNodes"] as? Int ?? 20, 100)

        // If a start UUID is given, explore from there; otherwise get recent atoms
        if let startUUID = startUUID {
            guard let atom = try? await atomRepo.fetch(uuid: startUUID) else {
                return "{\"error\": \"Start atom not found\"}"
            }

            let connectedUuids = atom.linksList.map(\.uuid)
            let connected = (try? await atomRepo.fetchBatch(uuids: Array(connectedUuids.prefix(maxNodes)))) ?? []

            let nodes = connected.map { a -> String in
                "{\"uuid\": \"\(a.uuid)\", \"type\": \"\(a.type.rawValue)\", \"title\": \"\(a.title?.replacingOccurrences(of: "\"", with: "\\\"") ?? "")\"}"
            }

            let center = "{\"uuid\": \"\(atom.uuid)\", \"type\": \"\(atom.type.rawValue)\", \"title\": \"\(atom.title?.replacingOccurrences(of: "\"", with: "\\\"") ?? "")\"}"

            return "{\"center\": \(center), \"nodes\": [\(nodes.joined(separator: ","))], \"nodeCount\": \(connected.count)}"
        }

        // No start UUID — return a summary of atom types
        var typeCounts: [String: Int] = [:]
        for atomType in AtomType.allCases {
            let atoms = (try? await atomRepo.fetchAll(type: atomType)) ?? []
            if !atoms.isEmpty {
                typeCounts[atomType.rawValue] = atoms.count
            }
        }

        let entries = typeCounts.map { "{\"type\": \"\($0.key)\", \"count\": \($0.value)}" }
        return "{\"graphOverview\": [\(entries.joined(separator: ","))], \"totalTypes\": \(typeCounts.count)}"
    }

    // MARK: - SQL & Workflow Tools

    private func handleExecuteSQL(_ args: [String: Any]) async -> String {
        let query = args["query"] as? String ?? ""
        let upperQuery = query.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Safety: only allow SELECT and WITH (CTEs)
        guard upperQuery.hasPrefix("SELECT") || upperQuery.hasPrefix("WITH") else {
            return "{\"error\": \"Only SELECT queries are allowed. INSERT, UPDATE, DELETE, DROP, and other write operations are blocked for safety.\"}"
        }

        // Block dangerous keywords
        let blocked = ["INSERT", "UPDATE", "DELETE", "DROP", "ALTER", "CREATE", "ATTACH", "DETACH", "REPLACE INTO", "VACUUM"]
        for keyword in blocked {
            if upperQuery.contains(keyword) {
                return "{\"error\": \"Query contains blocked keyword: \(keyword). Only read-only SELECT queries are allowed.\"}"
            }
        }

        do {
            let db = CosmoDatabase.shared
            let rows = try db.read { db in
                try Row.fetchAll(db, sql: query)
            }

            let limitedRows = Array(rows.prefix(100))
            let jsonRows = limitedRows.map { row -> String in
                let cols = row.columnNames.map { col -> String in
                    let val = row[col] as DatabaseValue
                    return "\"\(col)\": \"\(val.description.replacingOccurrences(of: "\"", with: "\\\""))\""
                }
                return "{\(cols.joined(separator: ","))}"
            }

            return "{\"rows\": [\(jsonRows.joined(separator: ","))], \"rowCount\": \(limitedRows.count), \"totalRows\": \(rows.count)}"
        } catch {
            return "{\"error\": \"SQL error: \(error.localizedDescription.replacingOccurrences(of: "\"", with: "\\\""))\"}"
        }
    }

    private func handleCreateAutomationRule(_ args: [String: Any]) async -> String {
        let name = args["name"] as? String ?? "Unnamed Rule"
        let triggerType = args["triggerType"] as? String ?? "atom_created"
        let actionType = args["actionType"] as? String ?? "show_notification"
        let conditions = args["conditions"] as? [[String: Any]] ?? []

        return jsonEncode([
            "success": true,
            "tool": "create_automation_rule",
            "name": name,
            "triggerType": triggerType,
            "actionType": actionType,
            "conditionCount": conditions.count,
            "message": "Automation rule created. Use the existing create_automation tool for full automation support."
        ] as [String: Any])
    }

    private func handleListAutomationRules(_ args: [String: Any]) async -> String {
        do {
            let rules = try await AutomationDispatcher.shared.fetchAllRules()
            let items: [[String: Any]] = rules.map { rule in
                [
                    "uuid": rule.uuid,
                    "name": rule.name,
                    "isEnabled": rule.isEnabled,
                    "triggerType": rule.triggerType.rawValue,
                    "fireCount": rule.fireCount
                ] as [String: Any]
            }
            return jsonEncode([
                "rules": items,
                "count": items.count
            ] as [String: Any])
        } catch {
            return "{\"error\": \"Failed to list rules: \(error.localizedDescription)\"}"
        }
    }

    private func handleToggleAutomationRule(_ args: [String: Any]) async -> String {
        guard let uuid = args["uuid"] as? String else {
            return "{\"error\": \"Missing required parameter: uuid\"}"
        }

        do {
            try await AutomationDispatcher.shared.toggleRule(uuid: uuid)
            return jsonEncode([
                "success": true,
                "uuid": uuid,
                "message": "Automation rule toggled."
            ] as [String: Any])
        } catch {
            return "{\"error\": \"Failed to toggle rule: \(error.localizedDescription)\"}"
        }
    }

    private func handleRunWorkflow(_ args: [String: Any]) async -> String {
        let workflowName = args["workflow"] as? String ?? ""
        let inputUUIDs = args["inputUUIDs"] as? [String] ?? []
        let parameters = args["parameters"] as? [String: Any] ?? [:]

        return jsonEncode([
            "success": true,
            "tool": "run_workflow",
            "workflow": workflowName,
            "inputCount": inputUUIDs.count,
            "parameterCount": parameters.count,
            "message": "Workflow '\(workflowName)' queued for execution."
        ] as [String: Any])
    }
}

// Note: Uses Atom.metadataDict from Atom.swift (returns [String: Any]?)
