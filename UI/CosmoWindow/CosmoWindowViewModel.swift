// CosmoOS/UI/CosmoWindow/CosmoWindowViewModel.swift
// Singleton brain for the global floating Cosmo chat window
// Handles message routing, context tracking, and conversation persistence
// February 2026

import SwiftUI
import Combine

private enum CosmoWindowAgentIDs {
    static let writingMode = "writing-editor"
}

struct CosmoWindowNewChatTransition: Sendable {
    let previousConversationId: String
    let previousMessages: [CosmoWindowMessage]
    let previousLinkedAtomUUIDs: Set<String>
    let previousPinnedContextSourceIDs: [String]
    let previousActiveAtomUUID: String?
    let previousActiveClientUUID: String?
    let newConversationId: String
}

@MainActor
final class CosmoWindowViewModel: ObservableObject {
    static let shared = CosmoWindowViewModel()

    // MARK: - Published State

    @Published var messages: [CosmoWindowMessage] = []
    @Published var isProcessing: Bool = false
    @Published var activeContext: CosmoActiveContext = .none
    @Published var inputText: String = "" {
        didSet {
            collaboratorSessions.saveDraft(inputText, for: collaboratorSessionKey)
        }
    }
    @Published var inputSelectionRange = NSRange(location: 0, length: 0)
    @Published var error: String? = nil
    @Published var processingStartedAt: Date?
    @Published private(set) var collaboratorSessionKey: CollaboratorSessionKey?
    @Published private(set) var collaboratorTarget: CollaborationTarget?
    @Published private(set) var collaboratorPreset: CollaboratorPreset?

    // MARK: - Live Tool Activity (WP5)

    @Published var liveToolActivity: [ToolActivityGroup] = []
    @Published var activeToolLabel: String? = nil
    /// Coalesced scroll tick — incremented on group-level changes only (not per-item).
    /// CosmoWindowView observes this instead of liveToolActivity.count to avoid render loops.
    @Published var toolActivityScrollTick: Int = 0

    // MARK: - Mention State (WP2 - @ Mention System)

    @Published var mentionedAtoms: [Atom] = []
    @Published var showMentionOverlay = false
    @Published var mentionSearchText = ""
    @Published var modelOverride: AgentModelTier? = nil {
        didSet {
            // Prompt caches are model-scoped: warm the new model's prefix once
            // so the first request after a switch skips the cold cache write.
            guard oldValue != modelOverride else { return }
            CosmoInlineAssistantCacheWarmer.warmForModelChange()
        }
    }
    @Published var selectedAgentProfileID: String? = nil
    @Published private(set) var agentProfiles: [CustomAgentProfile] = []
    @Published var pendingCanvasPlan: PendingCanvasPlan? = nil
    @Published var pendingNoteStructurePlan: PendingNoteStructurePlan? = nil
    @Published var pendingNoteStructurePreviewError: NoteStructurePlanError? = nil
    @Published var pendingProposedEdit: CosmoProposedEdit? = nil

    // MARK: - Edit State

    @Published var pendingEditIndex: Int? = nil

    // MARK: - Dependencies

    private let agentService = CosmoAgentService.shared
    private let contextAssembler = AgentContextAssembler.shared
    private let conversationMemory = ConversationMemoryService.shared
    private let toolRegistry = AgentToolRegistry.shared
    private let collaboratorSessions = CollaboratorSessionStore.shared
    private let agentProfileStore = CustomAgentProfileStore.shared
    private var noteStructureSourceSnapshotsByNoteUUID: [UUID: NoteStructureSourceSnapshot] = [:]

    // MARK: - Chat History State

    @Published var showChatHistory = false
    @Published var chatHistoryEntries: [ChatHistoryEntry] = []
    @Published var historySearchText = ""

    // MARK: - Conversation Persistence

    private let globalConversationDefaultsKey = "cosmoWindow.lastConversationId"
    private var globalConversationId: String = UserDefaults.standard.string(forKey: "cosmoWindow.lastConversationId") ?? "cosmo-global-window"
    private var conversationId: String = UserDefaults.standard.string(forKey: "cosmoWindow.lastConversationId") ?? "cosmo-global-window"
    private var linkedAtomUUIDs: Set<String> = []
    private var pinnedContextSourceIDs: [String] = []
    private let messageArchiveKeyPrefix = "cosmoWindow.messageArchive."

    // MARK: - Context Tracking

    private var contextProvider: (any CosmoContextProvider)?
    private var previousContextType: CosmoContextType = .none

    // MARK: - Cancellation

    private var currentTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var pendingContextTraceSections: [ContextTraceSection] = []

    // MARK: - Init

    private init() {
        conversationId = globalConversationId
        setupNotificationObservers()
        Task { await loadAgentProfiles() }
    }

    // MARK: - Send Message (Unified Pipeline — matches Telegram routing)

    /// Main entry point for user messages. Routes through the same pipeline as Telegram:
    /// fast URL capture → FlashLiteRouter → full agent
    func sendMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // /clear command — start a new chat session
        if trimmed.lowercased() == "/clear" {
            inputText = ""
            await startNewChat()
            messages.append(.system("New chat started. Previous conversation saved to history."))
            return
        }

        // Clear input immediately
        inputText = ""

        // Reset live tool activity for new message
        liveToolActivity = []
        activeToolLabel = nil
        toolActivityScrollTick = 0
        pendingContextTraceSections = []
        processingStartedAt = Date()

        // Capture mention info for the user message before clearing
        let mentionInfo: [MentionedAtomInfo]? = mentionedAtoms.isEmpty ? nil : mentionedAtoms.map {
            MentionedAtomInfo(uuid: $0.uuid, type: $0.type.rawValue, title: $0.title ?? "Untitled")
        }

        // Append user message to chat (with mention metadata)
        let userMessage = CosmoWindowMessage.user(trimmed, mentionedAtoms: mentionInfo)
        messages.append(userMessage)

        isProcessing = true
        error = nil

        // Create a placeholder assistant message for streaming
        let assistantId = UUID()
        let placeholder = CosmoWindowMessage(
            id: assistantId,
            type: .assistant,
            content: "",
            isStreaming: true
        )
        messages.append(placeholder)

        currentTask = Task {
            do {
                let response = await routeUnified(text: trimmed, assistantId: assistantId)

                // If routeUnified returned a response, update the placeholder
                if let response = response {
                    let frozenGroups = liveToolActivity.isEmpty ? nil : liveToolActivity
                    updateAssistantMessage(id: assistantId, content: response, isStreaming: false, toolActivityGroups: frozenGroups)
                    liveToolActivity = []
                    activeToolLabel = nil
                }

                // Persist conversation
                await persistConversation()

            } catch is CancellationError {
                updateAssistantMessage(id: assistantId, content: "Cancelled.", isStreaming: false)
            }

            isProcessing = false
            processingStartedAt = nil
            currentTask = nil
        }
    }

    // MARK: - Unified Routing Pipeline

    /// Routes a message through the in-app pipeline:
    /// fast URL capture -> FlashLiteRouter -> full agent.
    /// Returns nil if a route handled the assistant message directly.
    private func routeUnified(text: String, assistantId: UUID) async -> String? {
        if Self.isNoReplyComplaint(text) {
            return "You're right -- that last turn came back without usable text. I won't turn that into a database search; resend the prompt and I'll answer it directly."
        }

        // 1. Fast URL capture
        if text.range(of: "https?://[^\\s]+", options: .regularExpression) != nil {
            if let captureResult = await tryFastURLCapture(text: text) {
                await saveFlashRouterResult(text: text, response: captureResult, toolName: "capture_swipe")
                return captureResult
            }
        }

        if let stagedEditResponse = tryStageNoteEditFromUserCommand(text: text) {
            return stagedEditResponse
        }

        // 2. FlashLiteRouter for quick single-shot operations
        // Skip flash router when mentions are present — mentions signal contextual reasoning
        let bypassFlash: Bool
        if !mentionedAtoms.isEmpty || selectedAgentProfile != nil || !forcedToolBundles(for: text).isEmpty {
            bypassFlash = true
        } else {
            bypassFlash = Self.shouldBypassFlashRouter(
                text: text,
                recentAssistantContents: recentAssistantContentsForFlashBypass
            )
        }
        if !bypassFlash, let (flashResponse, toolName) = await FlashLiteRouter.shared.tryRoute(text) {
            await saveFlashRouterResult(text: text, response: flashResponse, toolName: toolName)
            return flashResponse
        }

        // 3. Full agent — route to CosmoAgentService (same as Telegram fallback)
        let response = await routeToAgentService(text: text)
        return response
    }

    // MARK: - Fast URL Capture (local version for CosmoWindow)

    /// Attempts fast-path URL capture via FlashLiteRouter, bypassing the full agent.
    private func tryFastURLCapture(text: String) async -> String? {
        // Delegate to FlashLiteRouter which handles swipe capture for URLs
        if let (response, _) = await FlashLiteRouter.shared.tryRoute(text) {
            return response
        }
        return nil
    }

    private func tryStageNoteEditFromUserCommand(text: String) -> String? {
        guard activeContext.type == .noteFocusMode,
              let atomUUID = activeContext.data.currentAtomUUID,
              !atomUUID.isEmpty else {
            return nil
        }

        let lower = text.lowercased()
        let wantsAppend = Self.containsAny(lower, ["append to note", "add to note", "put this in the note", "drop it in", "append this"])
        let wantsInsert = Self.containsAny(lower, ["insert at cursor", "insert this"])
        let wantsReplace = Self.containsAny(lower, ["replace", "rewrite selected", "rewrite this section"])
        guard wantsAppend || wantsInsert || wantsReplace else { return nil }

        guard let proposedText = lastAssistantContentForEditing() else {
            return nil
        }

        let title = activeContext.data.currentAtomTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetTitle = title?.isEmpty == false ? title! : "current note"
        let targetEditorID = EditorCommandTarget.noteBody(atomUUID)

        if wantsReplace,
           let selectedText = activeContext.data.selectedText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !selectedText.isEmpty {
            pendingProposedEdit = .replacement(
                targetTitle: targetTitle,
                targetEditorID: targetEditorID,
                originalText: selectedText,
                replacementText: proposedText,
                rationale: "Replacing the selected passage keeps the note tighter than appending another version."
            )
            return "I staged this as a replacement in \(targetTitle). Review the diff before I apply it."
        }

        let operation: CosmoProposedEditOperation = wantsInsert ? .insertAtCursor : .appendToDocument
        pendingProposedEdit = .insertion(
            targetTitle: targetTitle,
            targetEditorID: targetEditorID,
            operation: operation,
            proposedText: proposedText,
            rationale: operation == .appendToDocument
                ? "This looks like a new section for the current note."
                : "This should go at the current cursor location."
        )
        return "I staged this for \(targetTitle). Review it before I insert it."
    }

    private func lastAssistantContentForEditing() -> String? {
        messages.reversed().compactMap { message -> String? in
            guard case .assistant = message.type else { return nil }
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }
            return content
        }.first
    }

    // MARK: - FlashLiteRouter Follow-Up Detection

    private var recentAssistantContentsForFlashBypass: [String] {
        Array(messages.compactMap { message in
            guard case .assistant = message.type else { return nil }
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return content.isEmpty ? nil : content
        }.suffix(3))
    }

    /// Check if a message is a follow-up about already-captured content (should bypass FlashLiteRouter).
    nonisolated static func shouldBypassFlashRouter(text: String, recentAssistantContents: [String]) -> Bool {
        guard !recentAssistantContents.isEmpty else { return false }

        let capturePatterns = ["captured", "saved idea", "saved research", "swipe",
                               "idea:", "task created", "content created"]
        let hasCaptureHistory = recentAssistantContents.contains { content in
            let lower = content.lowercased()
            return capturePatterns.contains(where: { lower.contains($0) })
        }

        guard hasCaptureHistory else { return false }

        let lower = text.lowercased()
        let followUpSignals = [
            "this idea", "that idea", "the idea", "this swipe", "that swipe", "the swipe",
            "take action", "action on", "action this", "act on this",
            "using the", "using this as", "using that", "based on",
            "make the hook", "make a hook", "make the content", "make content",
            "similar to", "like the", "same style", "same hook", "same angle",
            "let's do", "let's make", "let's create", "let's write", "let's draft",
            "turn this into", "turn that into", "make this into"
        ]

        return followUpSignals.contains(where: { lower.contains($0) })
    }

    /// Save FlashLiteRouter-handled messages to conversation memory for follow-up context.
    private func saveFlashRouterResult(text: String, response: String, toolName: String) async {
        var conversation: AgentConversation
        if let existing = await conversationMemory.loadConversation(id: conversationId) {
            conversation = existing
        } else {
            conversation = AgentConversation(id: conversationId, source: .inApp)
        }
        conversation.append(.user(text))
        conversation.append(.assistant(response))
        await conversationMemory.saveConversation(conversation)
    }

    // MARK: - Mention Management (WP2)

    /// Adds an atom as @-mentioned context for the next message.
    func addMention(_ atom: Atom) {
        // Avoid duplicates
        guard !mentionedAtoms.contains(where: { $0.uuid == atom.uuid }) else { return }
        mentionedAtoms.append(atom)
        showMentionOverlay = false
        mentionSearchText = ""

        // Track linked atom UUID for conversation persistence
        linkedAtomUUIDs.insert(atom.uuid)
        pinContextSource(for: atom, allowGeneratedCodexCorpus: true)
    }

    /// Removes a previously @-mentioned atom.
    func removeMention(_ atom: Atom) {
        mentionedAtoms.removeAll { $0.uuid == atom.uuid }
    }

    /// Clears all @-mentioned atoms after sending.
    func clearMentions() {
        mentionedAtoms.removeAll()
    }

    private func pinContextSource(for atom: Atom, allowGeneratedCodexCorpus: Bool = false) {
        guard allowGeneratedCodexCorpus || !atom.isGeneratedCodexCorpus else { return }
        let source = Self.contextSource(for: atom)
        if !pinnedContextSourceIDs.contains(source.id) {
            pinnedContextSourceIDs.append(source.id)
        }

        let body = ContextIndexStore.indexableBody(for: atom)
        let chunks = ContextChunker.chunk(
            sourceID: source.id,
            title: source.title,
            body: body,
            bodyHash: source.bodyHash
        )

        Task {
            try? await ContextIndexStore.shared.upsert(source: source, chunks: chunks)
            await self.persistContextSession()
        }
    }

    nonisolated static func contextSource(for atom: Atom) -> ContextSource {
        ContextIndexStore.source(for: atom, pinState: .pinned)
    }

    nonisolated static func contextRetrievalRequest(
        text: String,
        conversationId: String,
        pinnedSourceIDs: [String],
        activeAtomUUID: String?,
        activeClientUUID: String?
    ) -> ContextRetrievalRequest {
        ContextRetrievalRequest(
            query: text,
            conversationID: conversationId,
            surface: .cosmoWindow,
            purpose: retrievalPurpose(for: text),
            pinnedSourceIDs: pinnedSourceIDs,
            activeAtomUUID: activeAtomUUID,
            activeClientUUID: activeClientUUID,
            maxChunks: 8,
            tokenBudget: 3_500
        )
    }

    private nonisolated static func retrievalPurpose(for text: String) -> RetrievalPurpose {
        let lower = normalizedPolicyText(text)
        if containsAny(lower, ["mention", "does it say", "does the doc", "does this doc", "where does", "find", "quote", "locks on doors"]) {
            return .factLookup
        }
        if containsAny(lower, ["draft", "write", "revise", "slide", "script", "post", "carousel"]) {
            return .writing
        }
        if containsAny(lower, ["remember", "what did we decide", "last time", "previously"]) {
            return .memory
        }
        if containsAny(lower, ["themes", "across", "summarize all", "patterns"]) {
            return .globalSynthesis
        }
        if containsAny(lower, ["brainstorm", "ideas", "think through", "angles"]) {
            return .brainstorm
        }
        return .general
    }

    // MARK: - Context Management

    /// Called by views when they become active to register their context provider.
    func updateContext(provider: any CosmoContextProvider) {
        let newType = provider.contextType
        let oldType = activeContext.type

        contextProvider = provider
        if let editableProvider = provider as? any CosmoEditableSurfaceProvider {
            CosmoEditableSurfaceRegistry.shared.register(editableProvider)
            // Binding the assistant session here is gated on idleness: a view
            // appearing (opening a source, switching panes) must never replace
            // a conversation the user is in the middle of. Ongoing chats bind
            // at submit time instead.
            CosmoInlineAssistantStore.shared.activateSessionIfIdle(surfaceID: editableProvider.surfaceID)
        }

        activeContext = CosmoActiveContext(
            type: newType,
            summary: provider.contextSummary,
            data: provider.contextData,
            actions: provider.availableActions
        )

        previousContextType = newType

        // Post notification for any observers
        NotificationCenter.default.post(
            name: CosmoNotification.CosmoWindow.contextChanged,
            object: nil,
            userInfo: ["contextType": newType.rawValue]
        )
    }

    /// Clears the current context (e.g., when leaving a focus mode).
    func clearContext() {
        contextProvider = nil
        activeContext = .none
    }

    /// Leaving a focus mode releases its window context — identity-guarded so
    /// a departing view can never clobber a context another surface already
    /// took over. The next live editable surface (a document still open in
    /// another window) becomes the context; with none, the window goes global.
    /// Callers unregister their editable surface BEFORE releasing, so the
    /// fallback lookup cannot resurrect the departing provider.
    func releaseContext(provider: any CosmoContextProvider) {
        guard contextProvider === provider else { return }
        if let fallback = CosmoEditableSurfaceRegistry.shared.activeSurface as? any CosmoContextProvider,
           fallback !== provider {
            updateContext(provider: fallback)
        } else {
            clearContext()
        }
    }

    /// Lightweight context update from MainView (no full CosmoContextProvider needed).
    /// Used when the window opens or the user navigates between top-level views.
    func updateContextManually(type: CosmoContextType) {
        activeContext = CosmoActiveContext(
            type: type,
            summary: type.displayName,
            data: CosmoContextData(),
            actions: []
        )

        previousContextType = type
    }

    /// Refreshes context data from the current provider without changing the provider itself.
    func refreshContext() {
        guard let provider = contextProvider else { return }
        activeContext = CosmoActiveContext(
            type: provider.contextType,
            summary: provider.contextSummary,
            data: provider.contextData,
            actions: provider.availableActions
        )
    }

    func refreshContextIfCurrentAtomMatches(atomUUID: String) {
        guard activeContext.data.currentAtomUUID == atomUUID else { return }
        refreshContext()
    }

    var isCollaboratorActive: Bool {
        collaboratorSessionKey != nil && collaboratorTarget != nil && collaboratorPreset != nil
    }

    var currentPromptSuggestions: [String] {
        if let selectedAgentProfile {
            return agentSuggestions(for: selectedAgentProfile)
        }
        if let collaboratorPreset {
            return collaboratorPreset.seedPrompts
        }
        return defaultPromptSuggestions
    }

    var currentHeaderSubtitle: String {
        if let collaboratorTarget {
            return "\(collaboratorTarget.displayTypeLabel) · \(collaboratorTarget.title)"
        }
        if let selectedAgentProfile {
            return selectedAgentProfile.summary
        }
        if activeContext.type == .none {
            return "Global assistant"
        }
        if let title = activeContext.data.currentAtomTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }
        return activeContext.type.displayName
    }

    var selectedAgentProfile: CustomAgentProfile? {
        guard let selectedAgentProfileID else { return nil }
        return agentProfiles.first(where: { $0.id == selectedAgentProfileID && $0.isEnabled })
    }

    var currentAgentLabel: String {
        selectedAgentProfile?.name ?? "Auto Cosmo"
    }

    var currentAgentIcon: String {
        selectedAgentProfile?.icon ?? "sparkles"
    }

    var isCurrentContextDockable: Bool {
        guard let currentAtomUUID = activeContext.data.currentAtomUUID else { return false }
        guard !currentAtomUUID.isEmpty else { return false }
        return dockableEntityType != nil
    }

    var dockableContextAtomUUID: String? {
        guard isCurrentContextDockable else { return nil }
        return activeContext.data.currentAtomUUID
    }

    var currentCollaboratorPresetID: String? {
        collaboratorPreset?.id
    }

    private var dockableEntityType: EntityType? {
        switch activeContext.type {
        case .connectionFocusMode:
            return .connection
        case .ideaFocusMode:
            return .idea
        case .noteFocusMode:
            return .note
        case .contentFocusMode:
            return .content
        default:
            return nil
        }
    }

    func activateCollaborator(target: CollaborationTarget, presetID: String? = nil) async {
        let preset = presetForID(presetID)
        let key = collaboratorSessions.activate(target: target, preset: preset)

        if conversationId != key.conversationID {
            await persistConversation()
            conversationId = key.conversationID
        }

        collaboratorSessionKey = key
        collaboratorTarget = target
        collaboratorPreset = preset
        inputText = collaboratorSessions.draft(for: key)
        linkedAtomUUIDs.insert(target.atomUUID)
        await rebuildPinnedContextSourcesFromLinkedAtoms()
        await loadConversation()
    }

    func deactivateCollaborator() async {
        guard collaboratorSessionKey != nil else { return }

        await persistConversation()

        collaboratorSessions.clearActive()
        collaboratorSessionKey = nil
        collaboratorTarget = nil
        collaboratorPreset = nil
        mentionedAtoms.removeAll()
        showMentionOverlay = false
        mentionSearchText = ""
        inputText = ""

        if conversationId != globalConversationId {
            conversationId = globalConversationId
        }

        await loadConversation()
    }

    func performAction(_ action: CosmoWindowAction, prompt: String = "") async {
        do {
            let response = try await action.handler(prompt)
            messages.append(.system(response))
            refreshContext()
            await persistConversation()
        } catch {
            messages.append(.system(error.localizedDescription))
        }
    }

    private func presetForID(_ presetID: String?) -> CollaboratorPreset {
        switch presetID {
        case nil, "deepen":
            return .deepen
        default:
            return .deepen
        }
    }

    func loadAgentProfiles() async {
        await agentProfileStore.loadProfiles()
        agentProfiles = agentProfileStore.profiles
        if let selectedAgentProfileID,
           !agentProfiles.contains(where: { $0.id == selectedAgentProfileID && $0.isEnabled }) {
            self.selectedAgentProfileID = nil
        }
    }

    func selectAgentProfile(_ profile: CustomAgentProfile?) {
        selectedAgentProfileID = profile?.id
        if modelOverride == nil {
            modelOverride = profile?.preferredModelTier
        }
    }

    func saveAgentProfile(_ profile: CustomAgentProfile) async {
        await agentProfileStore.save(profile)
        await loadAgentProfiles()
    }

    func deleteAgentProfile(_ profile: CustomAgentProfile) async {
        await agentProfileStore.delete(profile)
        if selectedAgentProfileID == profile.id {
            selectedAgentProfileID = nil
        }
        await loadAgentProfiles()
    }

    func cancelPendingCanvasPlan() {
        pendingCanvasPlan = nil
    }

    func cancelPendingNoteStructurePlan() {
        pendingNoteStructurePlan = nil
        pendingNoteStructurePreviewError = nil
    }

    func revisePendingNoteStructurePlan() {
        guard let plan = pendingNoteStructurePlan else { return }
        inputText = "Revise the note structure plan named \(plan.title). Keep the original note visible and keep exact source ranges only."
        cancelPendingNoteStructurePlan()
    }

    func applyPendingNoteStructurePlan() {
        guard let plan = pendingNoteStructurePlan else { return }
        if let validationError = validatePendingNoteStructurePlan(plan) {
            pendingNoteStructurePreviewError = validationError
            return
        }

        Task {
            do {
                let result = try await NoteStructureApplyService.shared.apply(plan)
                await MainActor.run {
                    self.pendingNoteStructurePlan = nil
                    self.pendingNoteStructurePreviewError = nil
                    self.messages.append(.system("Created \(result.notesCreated) exact-copy notes across \(result.clustersCreated) clusters. Original note stayed visible."))
                }
            } catch let error as NoteStructurePlanError {
                await MainActor.run {
                    self.pendingNoteStructurePreviewError = error
                }
            } catch {
                await MainActor.run {
                    self.error = "Could not apply the note structure plan: \(error.localizedDescription)"
                }
            }
        }
    }

    func receivePendingNoteStructurePlan(_ plan: PendingNoteStructurePlan) {
        pendingNoteStructurePlan = plan
        pendingNoteStructurePreviewError = validatePendingNoteStructurePlan(plan)
    }

    func validatePendingNoteStructurePlan(_ plan: PendingNoteStructurePlan) -> NoteStructurePlanError? {
        guard let snapshot = noteStructureSnapshot(for: plan) else {
            return .missingSourceNote
        }

        do {
            try plan.validate(against: snapshot)
            return nil
        } catch let error as NoteStructurePlanError {
            return error
        } catch {
            return .sourceHashMismatch(expected: plan.sourceBodyHash, actual: snapshot.bodyHash)
        }
    }

    var canApplyPendingNoteStructurePlan: Bool {
        pendingNoteStructurePlan != nil && pendingNoteStructurePreviewError == nil
    }

    func noteStructurePreviewText(for module: NoteStructureModuleProposal) -> String {
        let snapshot = pendingNoteStructurePlan.flatMap { noteStructureSnapshot(for: $0) } ?? activeNoteStructureSnapshot()
        guard let snapshot,
              let text = try? module.copiedText(in: snapshot.body) else {
            return ""
        }
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > 180 else { return collapsed }
        return "\(collapsed.prefix(180))…"
    }

    func revisePendingCanvasPlan() {
        guard let plan = pendingCanvasPlan else { return }
        inputText = "Revise this canvas plan: \(plan.title). "
        pendingCanvasPlan = nil
    }

    func applyPendingCanvasPlan() {
        guard let plan = pendingCanvasPlan else { return }
        let applied = applyCanvasOperations(plan.operations)
        pendingCanvasPlan = nil
        messages.append(.system("Applied \(applied) of \(plan.operations.count) canvas operations."))
    }

    /// Applies an approved canvas plan from the assistant pane's plan card.
    /// Returns how many operations actually applied (for the receipt line).
    @discardableResult
    func applyCanvasPlan(_ plan: PendingCanvasPlan) -> Int {
        let applied = applyCanvasOperations(plan.operations, targetThinkspaceId: plan.targetThinkspaceId)
        // The plan decides which blocks belong together; geometry is never the
        // model's job. One completion signal lets the canvas run its
        // deterministic cluster-overlap resolution AFTER every operation landed.
        var userInfo: [AnyHashable: Any] = [:]
        if let target = plan.targetThinkspaceId { userInfo["thinkspaceId"] = target }
        NotificationCenter.default.post(
            name: CosmoNotification.Canvas.canvasPlanDidApply,
            object: nil,
            userInfo: userInfo
        )
        return applied
    }

    func applyPendingProposedEdit() {
        guard let edit = pendingProposedEdit else { return }

        switch edit.operation {
        case .appendToDocument:
            EditorCommandBus.shared.insertText(
                "\n\n\(edit.proposedText)",
                at: .endOfDocument,
                targetEditorID: edit.targetEditorID,
                allowInactive: true
            )
        case .insertAtCursor:
            EditorCommandBus.shared.insertText(
                edit.proposedText,
                at: .cursor,
                targetEditorID: edit.targetEditorID,
                allowInactive: true
            )
        case .replaceSelection:
            EditorCommandBus.shared.replaceSelection(
                with: edit.proposedText,
                targetEditorID: edit.targetEditorID,
                allowInactive: true
            )
        }

        pendingProposedEdit = nil
        messages.append(.system("Inserted into \(edit.targetTitle)."))
        refreshContext()
    }

    func dismissPendingProposedEdit() {
        pendingProposedEdit = nil
    }

    func revisePendingProposedEdit() {
        guard let edit = pendingProposedEdit else { return }
        inputText = "Revise this proposed edit for \(edit.targetTitle): \(edit.proposedText)"
        pendingProposedEdit = nil
    }

    func activeNoteStructureSnapshot() -> NoteStructureSourceSnapshot? {
        if activeContext.type == .noteFocusMode,
           activeContext.data.currentAtomType?.lowercased() == "note",
           let noteUUIDString = activeContext.data.currentAtomUUID,
           let noteUUID = UUID(uuidString: noteUUIDString),
           let body = activeContext.data.viewSpecificData["noteBody"] {
            return rememberNoteStructureSnapshot(NoteStructureSourceSnapshot(
                sourceNoteUUID: noteUUID,
                sourceTitle: activeContext.data.currentAtomTitle ?? "Untitled Note",
                body: body
            ))
        }

        if activeContext.type == .thinkspaceCanvas,
           let mentionedNote = mentionedAtoms.first(where: { $0.type == .note }),
           let snapshot = noteStructureSnapshot(for: mentionedNote) {
            return snapshot
        }

        return nil
    }

    private func noteStructureSnapshot(for plan: PendingNoteStructurePlan) -> NoteStructureSourceSnapshot? {
        if let activeSnapshot = activeNoteStructureSnapshot(),
           activeSnapshot.sourceNoteUUID == plan.sourceNoteUUID {
            return activeSnapshot
        }
        return noteStructureSourceSnapshotsByNoteUUID[plan.sourceNoteUUID]
    }

    private func noteStructureSnapshot(for atom: Atom) -> NoteStructureSourceSnapshot? {
        guard atom.type == .note,
              let noteUUID = UUID(uuidString: atom.uuid) else {
            return nil
        }
        let body = DocumentElementContextFormatter.contextBody(for: atom)
        return rememberNoteStructureSnapshot(NoteStructureSourceSnapshot(
            sourceNoteUUID: noteUUID,
            sourceTitle: atom.title ?? "Untitled Note",
            body: body
        ))
    }

    private func rememberNoteStructureSnapshot(_ snapshot: NoteStructureSourceSnapshot) -> NoteStructureSourceSnapshot {
        noteStructureSourceSnapshotsByNoteUUID[snapshot.sourceNoteUUID] = snapshot
        return snapshot
    }

    func resolvedTargetThinkspaceForNoteStructure() -> UUID? {
        if let explicit = activeContext.data.viewSpecificData["targetThinkspaceUUID"],
           let uuid = UUID(uuidString: explicit) {
            return uuid
        }
        if let explicit = activeContext.data.viewSpecificData["currentThinkspaceUUID"],
           let uuid = UUID(uuidString: explicit) {
            return uuid
        }
        if let explicit = activeContext.data.viewSpecificData["thinkspaceUUID"],
           let uuid = UUID(uuidString: explicit) {
            return uuid
        }
        return nil
    }

    // MARK: - Conversation Lifecycle

    /// Loads the persisted global conversation on app launch.
    func loadConversation() async {
        let storedMessages = loadStoredMessages(for: conversationId)

        if let conversation = await conversationMemory.loadConversation(id: conversationId) {
            linkedAtomUUIDs = Set(conversation.linkedAtomUUIDs)

            if let storedMessages {
                messages = storedMessages
            } else {
                messages = conversation.messages.compactMap { agentMsg in
                    switch agentMsg.role {
                    case .user:
                        return CosmoWindowMessage.user(agentMsg.content)
                    case .assistant:
                        return CosmoWindowMessage.assistant(agentMsg.content)
                    case .system:
                        return CosmoWindowMessage.system(agentMsg.content)
                    case .tool:
                        return CosmoWindowMessage.toolResult(
                            name: "tool",
                            summary: String(agentMsg.content.prefix(120))
                        )
                    }
                }
            }
        } else if let storedMessages {
            messages = storedMessages
        } else {
            messages = []
        }

        pinnedContextSourceIDs.removeAll()
        if let session = try? await ContextIndexStore.shared.session(id: conversationId) {
            mergePinnedContextSourceIDs(session.pinnedSourceIDs)
        }
        await rebuildPinnedContextSourcesFromLinkedAtoms(reset: false)
    }

    private func rebuildPinnedContextSourcesFromLinkedAtoms(reset: Bool = true) async {
        if reset {
            pinnedContextSourceIDs.removeAll()
        }
        for uuid in linkedAtomUUIDs {
            guard let atom = try? await AtomRepository.shared.fetch(uuid: uuid) else { continue }
            guard !atom.isGeneratedCodexCorpus else { continue }
            let source = Self.contextSource(for: atom)
            if !pinnedContextSourceIDs.contains(source.id) {
                pinnedContextSourceIDs.append(source.id)
            }
            _ = try? await ContextIndexStore.shared.upsert(atom: atom, pinState: .pinned)
        }
    }

    private func ensurePinnedContextForCurrentTurn() async {
        for atom in mentionedAtoms {
            let source = Self.contextSource(for: atom)
            if !pinnedContextSourceIDs.contains(source.id) {
                pinnedContextSourceIDs.append(source.id)
            }
            linkedAtomUUIDs.insert(atom.uuid)
            _ = try? await ContextIndexStore.shared.upsert(atom: atom, pinState: .pinned)
        }

        if let activeUUID = activeContext.data.currentAtomUUID,
           !activeUUID.isEmpty,
           let atom = try? await AtomRepository.shared.fetch(uuid: activeUUID) {
            if !atom.isGeneratedCodexCorpus {
                let source = Self.contextSource(for: atom)
                if !pinnedContextSourceIDs.contains(source.id) {
                    pinnedContextSourceIDs.append(source.id)
                }
                _ = try? await ContextIndexStore.shared.upsert(atom: atom, pinState: .active)
            }
        }

        if let activeClientUUID = activeContext.data.activeClientUUID,
           !activeClientUUID.isEmpty,
           let clientAtom = try? await AtomRepository.shared.fetch(uuid: activeClientUUID),
           clientAtom.type == .clientProfile {
            let source = Self.contextSource(for: clientAtom)
            if !pinnedContextSourceIDs.contains(source.id) {
                pinnedContextSourceIDs.append(source.id)
            }
            linkedAtomUUIDs.insert(clientAtom.uuid)
            _ = try? await ContextIndexStore.shared.upsert(atom: clientAtom, pinState: .pinned)
        }
        await persistContextSession()
    }

    /// Clears the conversation history.
    func clearConversation() async {
        messages.removeAll()
        linkedAtomUUIDs.removeAll()
        pinnedContextSourceIDs.removeAll()
        error = nil
        processingStartedAt = nil
        pendingContextTraceSections = []

        // Persist the empty state
        await persistConversation()
    }

    /// Cancels any currently running operation.
    func cancelCurrentOperation() {
        currentTask?.cancel()
        currentTask = nil
        isProcessing = false
        processingStartedAt = nil
        pendingContextTraceSections = []
        liveToolActivity = []
        activeToolLabel = nil
        messages.append(.system("Operation cancelled."))
    }

    // MARK: - Edit & Resend

    /// Copies a past user message's content into the input field for editing.
    func editAndResend(messageId: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        inputText = messages[index].content
        pendingEditIndex = index
    }

    /// Truncates the conversation to the pending edit index and sends a new message.
    func sendEditedMessage(_ text: String) async {
        guard let editIndex = pendingEditIndex else {
            await sendMessage(text)
            return
        }
        // Remove the edited message and everything after it
        messages = Array(messages.prefix(editIndex))
        pendingEditIndex = nil
        await sendMessage(text)
    }

    // MARK: - Token Usage

    /// Estimated token count for the current conversation (rough: 4 chars per token).
    var estimatedTokenUsage: Int {
        messages.reduce(0) { $0 + ($1.content.count / 4) }
    }

    var currentModelLabel: String {
        modelOverride?.displayLabel ?? "Auto"
    }

    var filteredChatHistoryEntries: [ChatHistoryEntry] {
        let query = historySearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return chatHistoryEntries }
        return chatHistoryEntries.filter { entry in
            entry.preview.lowercased().contains(query)
        }
    }

    private var defaultPromptSuggestions: [String] {
        let title = activeContext.data.currentAtomTitle ?? "what I’m looking at"

        switch activeContext.type {
        case .commandCenter:
            return [
                "What deserves attention in Command Center?",
                "Summarize what changed recently",
                "What should I tackle next?"
            ]
        case .contentFocusMode:
            return [
                "Help me think through \(title)",
                "What problem does this solve?",
                "What would the better version look like?"
            ]
        case .ideaFocusMode, .connectionFocusMode, .noteFocusMode:
            return CollaboratorPromptLibrary.seedPrompts
        case .swipeGallery, .swipeStudy:
            return [
                "What pattern is showing up here?",
                "Find the strongest hook angle",
                "How would I adapt this swipe?"
            ]
        case .researchFocusMode:
            return [
                "Summarize the important takeaways",
                "What contradictions should I examine?",
                "Turn this into actionable notes"
            ]
        case .thinkspaceCanvas:
            return [
                "Summarize what I’m looking at",
                "What should I focus on next?",
                "Turn this into a plan"
            ]
        case .inbox:
            return [
                "What deserves attention today?",
                "Summarize my current state",
                "What should I improve first?"
            ]
        case .none:
            return [
                "What should I focus on next?",
                "Help me turn a thought into a plan",
                "Summarize what I’m working on"
            ]
        default:
            return [
                "Help me think through \(title)",
                "What matters most here?",
                "Give me the next best move"
            ]
        }
    }

    // MARK: - Session Management

    /// Starts a new chat session, preserving the current conversation in history.
    func startNewChat() async {
        if isCollaboratorActive {
            await clearConversation()
            return
        }

        let transition = beginNewGlobalChatSession()

        Task { [weak self] in
            await Task.yield()
            await self?.finishNewGlobalChatTransition(transition)
        }
    }

    @discardableResult
    func beginNewGlobalChatSession(
        newConversationId: String = "cosmo-window-\(UUID().uuidString.prefix(8).lowercased())"
    ) -> CosmoWindowNewChatTransition {
        let transition = CosmoWindowNewChatTransition(
            previousConversationId: conversationId,
            previousMessages: messages,
            previousLinkedAtomUUIDs: linkedAtomUUIDs,
            previousPinnedContextSourceIDs: pinnedContextSourceIDs,
            previousActiveAtomUUID: activeContext.data.currentAtomUUID,
            previousActiveClientUUID: activeContext.data.activeClientUUID,
            newConversationId: newConversationId
        )

        globalConversationId = newConversationId
        conversationId = newConversationId
        UserDefaults.standard.set(newConversationId, forKey: globalConversationDefaultsKey)

        currentTask?.cancel()
        currentTask = nil

        // Clear all state
        messages.removeAll()
        linkedAtomUUIDs.removeAll()
        pinnedContextSourceIDs.removeAll()
        error = nil
        isProcessing = false
        liveToolActivity = []
        activeToolLabel = nil
        toolActivityScrollTick = 0
        historySearchText = ""
        processingStartedAt = nil
        pendingContextTraceSections = []

        saveStoredMessages([], for: newConversationId)

        return transition
    }

    private func finishNewGlobalChatTransition(_ transition: CosmoWindowNewChatTransition) async {
        if !transition.previousMessages.isEmpty {
            await persistConversationSnapshot(
                conversationId: transition.previousConversationId,
                messages: transition.previousMessages,
                linkedAtomUUIDs: transition.previousLinkedAtomUUIDs,
                activeAtomUUID: transition.previousActiveAtomUUID,
                activeClientUUID: transition.previousActiveClientUUID,
                pinnedContextSourceIDs: transition.previousPinnedContextSourceIDs
            )
        }

        await loadChatHistory()
    }

    /// Loads recent in-app chat sessions for the history popover.
    func loadChatHistory() async {
        let recent = await conversationMemory.getRecentConversations(limit: 20)
        let inAppConversations = recent.filter { $0.source == .inApp && !$0.messages.isEmpty }

        chatHistoryEntries = inAppConversations.map { conv in
            let preview: String
            if let summary = conv.summary, !summary.isEmpty {
                preview = String(summary.prefix(80))
            } else if let firstUser = conv.messages.first(where: { $0.role == .user }) {
                preview = String(firstUser.content.prefix(80))
            } else {
                preview = "Empty conversation"
            }

            // Use the most recent message timestamp if available, otherwise fall back to createdAt
            let lastMessageDate = conv.messages.last?.timestamp ?? conv.createdAt

            return ChatHistoryEntry(
                id: conv.id,
                preview: preview,
                messageCount: conv.messages.count,
                lastActivity: lastMessageDate,
                isActive: conv.id == conversationId
            )
        }
        .sorted { $0.lastActivity > $1.lastActivity }
    }

    /// Switches to a different chat session from history.
    func switchToChat(id: String) async {
        guard !isCollaboratorActive else { return }

        // Persist current conversation first
        if !messages.isEmpty {
            await persistConversation()
        }

        // Switch to the selected conversation
        conversationId = id
        globalConversationId = id
        UserDefaults.standard.set(globalConversationId, forKey: globalConversationDefaultsKey)
        await loadConversation()
        await loadChatHistory()
    }

    // MARK: - Private Helpers

    /// Routes a message through the general CosmoAgentService.
    private func routeToAgentService(text: String) async -> String {
        let hasMentionedAtoms = !mentionedAtoms.isEmpty
        let activeProfile = selectedAgentProfile
        let writingModeAgentSelected = Self.allowsWritingModeAgentRoute(
            selectedAgentProfileID: activeProfile?.id
        )
        let responseMode: AgentResponseMode
        if writingModeAgentSelected {
            responseMode = .automatic
        } else if Self.shouldUseInlineMentionDraftResponse(text: text, hasMentionedAtoms: hasMentionedAtoms) {
            responseMode = .inlineMentionDraftReference
        } else {
            responseMode = .directChat
        }

        await ensurePinnedContextForCurrentTurn()

        // Inject current context into the message if available
        let contextBlock = buildContextBlock()

        // Use the agent service with context-enriched prompt
        var enrichedText: String
        if !contextBlock.isEmpty {
            enrichedText = """
            \(text)

            <active_cosmo_context>
            \(contextBlock)
            </active_cosmo_context>
            """
        } else {
            enrichedText = text
        }

        // Inject @-mentioned atom context inline at mention positions
        if hasMentionedAtoms {
            enrichedText = MentionContextHelper.expandMentionsInline(
                text: enrichedText,
                atoms: mentionedAtoms
            )
            clearMentions()
        }

        // Wire in-app action buttons callback so `send_action_buttons` tool delivers
        // interactive buttons directly into the CosmoWindow conversation
        let toolExecutor = AgentToolExecutor.shared
        toolExecutor.onActionButtons = { [weak self] message, buttons in
            Task { @MainActor in
                let actionButtons = buttons.map { CosmoActionButton(label: $0.label, action: $0.action) }
                self?.messages.append(.actionButtons(message, buttons: actionButtons))
            }
        }
        toolExecutor.onCanvasPlan = { [weak self] plan in
            Task { @MainActor in
                self?.pendingCanvasPlan = plan
            }
        }
        toolExecutor.onNoteStructurePlan = { [weak self] plan in
            Task { @MainActor in
                self?.receivePendingNoteStructurePlan(plan)
            }
        }

        var forcedBundles = forcedToolBundles(for: text)
        if !writingModeAgentSelected {
            forcedBundles.remove(.writing)
        }
        if responseMode == .inlineMentionDraftReference {
            forcedBundles.subtract([.contentSearch, .swipes, .writing, .strategy])
        }
        let profileToolBundles = activeProfile?.toolBundles.filter { bundle in
            writingModeAgentSelected || bundle != .writing
        } ?? []
        let retrievalRequest = Self.contextRetrievalRequest(
            text: text,
            conversationId: conversationId,
            pinnedSourceIDs: pinnedContextSourceIDs,
            activeAtomUUID: activeContext.data.currentAtomUUID,
            activeClientUUID: activeContext.data.activeClientUUID
        )
        let retrievalResults = (try? await CosmoRetrievalService.shared.retrieve(retrievalRequest)) ?? []
        let coreMemory = (try? await CosmoMemoryService.shared.coreMemory()) ?? []
        let workingMemory = (try? await CosmoMemoryService.shared.workingMemory(conversationID: conversationId)) ?? []
        let contextPack = ContextPackAssembler.assemble(
            request: retrievalRequest,
            retrievalResults: retrievalResults,
            coreMemory: coreMemory,
            workingMemory: workingMemory,
            recallMemory: []
        )
        let hasContextPackContent = !contextPack.retrievedResults.isEmpty || !coreMemory.isEmpty || !workingMemory.isEmpty
        let runtimePrompt = runtimePromptLayer(
            collaboratorPrompt: collaboratorPreset?.runtimePrompt,
            agentProfile: activeProfile,
            forcedBundles: forcedBundles
        )
        let systemPromptOverride = [
            hasContextPackContent ? contextPack.promptBlock : nil,
            runtimePrompt
        ]
        .compactMap { $0 }
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n\n")

        toolExecutor.contextAtomUUIDs = Array(linkedAtomUUIDs)
        toolExecutor.contextSourceIDs = pinnedContextSourceIDs
        toolExecutor.contextConversationID = conversationId
        toolExecutor.activeClientUUID = activeContext.data.activeClientUUID
        let (response, trace) = await agentService.processMessage(
            enrichedText,
            conversationId: conversationId,
            source: .inApp,
            tierOverride: modelOverride ?? activeProfile?.preferredModelTier,
            systemPromptOverride: systemPromptOverride.isEmpty ? nil : systemPromptOverride,
            responseMode: responseMode,
            profileToolBundles: profileToolBundles,
            forcedToolBundles: forcedBundles,
            onToolActivity: { [weak self] event in
                Task { @MainActor in
                    self?.handleToolActivity(event)
                }
            }
        )

        // Clear the action buttons callback after processing
        mergePinnedContextSourceIDs(toolExecutor.contextSourceIDs)
        linkedAtomUUIDs.formUnion(toolExecutor.contextAtomUUIDs)
        toolExecutor.onActionButtons = nil
        toolExecutor.onCanvasPlan = nil
        toolExecutor.onNoteStructurePlan = nil
        toolExecutor.contextAtomUUIDs = []
        toolExecutor.contextSourceIDs = []
        toolExecutor.contextConversationID = nil
        toolExecutor.activeClientUUID = nil

        let retrievalTraceSections = hasContextPackContent ? CosmoWindowMessage.contextTraceSections(from: contextPack) : []
        let toolTraceSections = trace.hasContent ? CosmoWindowMessage.contextTraceSections(from: trace) : []
        pendingContextTraceSections = retrievalTraceSections + toolTraceSections

        return response
    }

    func prepareInlineAssistantAgentRequest(
        prompt: String,
        route: CosmoInlineAssistantRoute,
        snapshot: CosmoEditableSourceSnapshot?,
        inlineContextAtoms: [Atom] = [],
        selectedSkillID: String? = nil,
        sessionLedgerBlock: String? = nil
    ) async -> CosmoInlineAssistantPreparedAgentRequest {
        let inlineRequestContextAtoms = ContextSourcePolicy.filteredAtoms(
            Self.uniqueAtoms(mentionedAtoms + inlineContextAtoms),
            query: prompt
        )
        let hasMentionedAtoms = !mentionedAtoms.isEmpty
        let hasInlineContextAtoms = !inlineRequestContextAtoms.isEmpty
        let activeProfile = selectedAgentProfile
        let writingModeAgentSelected = Self.allowsWritingModeAgentRoute(
            selectedAgentProfileID: activeProfile?.id
        )
        let workingContextCache = CosmoInlineAssistantWorkingContextCache.shared
        let previousWorkingContextFrame = workingContextCache.currentFrame(
            conversationID: conversationId,
            snapshot: snapshot,
            activeAtomUUID: activeContext.data.currentAtomUUID
        )
        let skillPlan = CosmoInlineAssistantSkillRuntime.plan(
            for: prompt,
            surfaceKind: snapshot?.kind,
            previousSkillID: previousWorkingContextFrame?.skillID,
            selectedSkillID: selectedSkillID
        )
        let responseMode: AgentResponseMode = route == .action ? .automatic : .inlineAssistant
        let workingContextFrame = workingContextCache.updateFrame(
            conversationID: conversationId,
            route: route,
            snapshot: snapshot,
            activeAtomUUID: activeContext.data.currentAtomUUID,
            activeClientUUID: activeContext.data.activeClientUUID,
            contextAtoms: inlineRequestContextAtoms,
            skillPlan: skillPlan
        )
        let resolvedSkillContext = await CosmoInlineSkillContextResolver.resolve(
            skillPlan: skillPlan,
            snapshot: snapshot,
            prompt: prompt,
            activeClientUUID: activeContext.data.activeClientUUID,
            inlineContextAtoms: inlineRequestContextAtoms
        )

        await ensurePinnedContextForCurrentTurn()

        // The surface snapshot in the volatile layer is the ONE "what the user
        // is looking at" statement for inline requests. The old single-slot
        // `<active_cosmo_context>` block (CosmoWindowViewModel.activeContext,
        // last-registered-view-wins) could describe a DIFFERENT view than the
        // snapshot in the same request — the agent then refused or edited the
        // wrong thing. Only the note-structure planning payload survives here;
        // it has no home in the snapshot.
        var enrichedText: String
        let structureBlock = noteStructurePlanningBlock()
        if !structureBlock.isEmpty {
            enrichedText = """
            \(prompt)

            <active_cosmo_context>
            \(structureBlock)
            </active_cosmo_context>
            """
        } else {
            enrichedText = prompt
        }

        if hasInlineContextAtoms {
            enrichedText = MentionContextHelper.expandMentionsInline(
                text: enrichedText,
                atoms: inlineRequestContextAtoms
            )
        }

        if hasMentionedAtoms {
            clearMentions()
        }

        var forcedBundles = forcedToolBundles(for: prompt)
        if !writingModeAgentSelected {
            forcedBundles.remove(.writing)
        }
        forcedBundles.formUnion(CosmoInlineAssistantToolBundlePolicy.bundles(
            for: prompt,
            route: route,
            surfaceKind: snapshot?.kind
        ))
        forcedBundles.formUnion(skillPlan.toolBundles)
        forcedBundles = CosmoInlineAssistantToolBundlePolicy.reducedBundlesForInlineRequest(
            forcedBundles,
            route: route,
            resolvedContexts: resolvedSkillContext.satisfiedContexts
        )

        let rawProfileToolBundles = activeProfile?.toolBundles.filter { bundle in
            writingModeAgentSelected || bundle != .writing
        } ?? []
        let reducedProfileToolBundles = CosmoInlineAssistantToolBundlePolicy.reducedBundlesForInlineRequest(
            Set(rawProfileToolBundles),
            route: route,
            resolvedContexts: resolvedSkillContext.satisfiedContexts
        )
        let profileToolBundles = reducedProfileToolBundles == Set(rawProfileToolBundles)
            ? rawProfileToolBundles
            : reducedProfileToolBundles.sorted { $0.rawValue < $1.rawValue }
        let retrievalRequest = Self.contextRetrievalRequest(
            text: prompt,
            conversationId: conversationId,
            pinnedSourceIDs: pinnedContextSourceIDs,
            activeAtomUUID: activeContext.data.currentAtomUUID,
            activeClientUUID: activeContext.data.activeClientUUID
        )
        // Surgical edits fetch what they need via tools (e.g. get_client_profile), so skip
        // the embeddings-backed pre-retrieval for action edits — it's redundant there and was
        // the bulk of `prepare` latency (worse when the local embeddings daemon is cold).
        let retrievalResults = route == .action
            ? []
            : ((try? await CosmoRetrievalService.shared.retrieve(retrievalRequest)) ?? [])
        let coreMemory = (try? await CosmoMemoryService.shared.coreMemory()) ?? []
        let workingMemory = (try? await CosmoMemoryService.shared.workingMemory(conversationID: conversationId)) ?? []
        // Distilled session facts, embedding-matched to this ask — runs for
        // BOTH routes (a ~100-token recall is worth it on action edits too:
        // "wants headers bolded" is exactly what an edit request needs).
        let recallMemory = await CosmoMemoryService.shared.recallArchivalMemory(
            query: [prompt, snapshot?.title ?? ""].joined(separator: " "),
            limit: 3
        )
        // What the user actually accepted/rejected for this skill recently —
        // the render-back half of review-outcome learning.
        let reviewTrackRecord = route == .action
            ? await CosmoInlineReviewTrackRecord.promptBlock(
                skillID: selectedSkillID ?? skillPlan.primarySkill.id.rawValue
            )
            : nil
        let contextPack = ContextPackAssembler.assemble(
            request: retrievalRequest,
            retrievalResults: retrievalResults,
            coreMemory: coreMemory,
            workingMemory: workingMemory,
            recallMemory: recallMemory
        )
        let hasContextPackContent = !contextPack.retrievedResults.isEmpty || !coreMemory.isEmpty
            || !workingMemory.isEmpty || !recallMemory.isEmpty
        let runtimePrompt = runtimePromptLayer(
            collaboratorPrompt: collaboratorPreset?.runtimePrompt,
            agentProfile: activeProfile,
            forcedBundles: forcedBundles
        )

        // Cache-ordered split: the static instruction layer (route rules + personality)
        // is byte-identical across requests and rides inside the prompt-cache prefix.
        // Everything request-specific — context pack, runtime layer (varies with forced
        // bundles), resolved skill facts, skill plan, working frame, and the surface
        // snapshot — renders after the cache breakpoint so the prefix survives intact.
        let staticInstructionOverride = CosmoInlineAssistantInstructionPrompt.staticInstructions(
            for: route,
            requiresPaneExplanation: CosmoInlineAssistantResearchIntent.shouldRequirePaneExplanation(skillPlan)
        )
        let volatileContextOverride = [
            hasContextPackContent ? contextPack.promptBlock : nil,
            runtimePrompt,
            resolvedSkillContext.isEmpty ? nil : resolvedSkillContext.promptBlock,
            reviewTrackRecord,
            // Prefetched related-work digest — assembled in the background when the
            // surface activated, so the common request needs zero tool round-trips.
            CosmoInlineAmbientContextPack.shared.digest(forSurfaceID: snapshot?.surfaceID),
            // The session turn ledger — what was asked, staged, answered, and
            // accepted so far. This is the state-based continuity carrier; it
            // must precede the surface snapshot so references resolve before
            // the model reads the live text.
            sessionLedgerBlock,
            CosmoInlineAssistantInstructionPrompt.volatileContext(
                snapshot: snapshot,
                skillPlan: skillPlan,
                workingContextFrame: workingContextFrame
            )
        ]
        .compactMap { $0 }
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n\n")

        // Mechanical fast lane, decided by STATE: a live selection plus the
        // default edit skill and no research bundles is a surgical edit —
        // Haiku handles it at ~10x less cost and latency. Any explicit skill,
        // profile, or user model pick still wins.
        let mechanicalFastLane = route == .action
            && snapshot?.selection?.isEmpty == false
            && selectedSkillID == nil
            && skillPlan.primarySkill.id == .inlineEdit
            && !skillPlan.toolBundles.contains(.webResearch)

        return CosmoInlineAssistantPreparedAgentRequest(
            prompt: enrichedText,
            // Dedicated, surface-scoped conversation so the inline assistant doesn't drag
            // in (or grow) the large shared Cosmo-window chat history on every edit.
            conversationID: CosmoInlineAssistantSessionScope.conversationID(for: snapshot?.surfaceID),
            // Normal inline requests use the daily driver (Sonnet 5, via the shared
            // request shape so the prewarmer warms the same model); explicit
            // skill/model overrides still win for specialized work.
            tierOverride: modelOverride
                ?? skillPlan.preferredModelTier
                ?? activeProfile?.preferredModelTier
                ?? (mechanicalFastLane ? .sensor : CosmoInlineAssistantRequestShape.defaultModelTier),
            intentOverride: CosmoInlineAssistantRequestShape.pinnedIntent(for: route),
            systemPromptOverride: staticInstructionOverride,
            volatileContextOverride: volatileContextOverride.isEmpty ? nil : volatileContextOverride,
            responseMode: responseMode,
            profileToolBundles: profileToolBundles,
            forcedToolBundles: forcedBundles,
            contextAtomUUIDs: Array(linkedAtomUUIDs.union(inlineRequestContextAtoms.map(\.uuid))),
            contextSourceIDs: pinnedContextSourceIDs,
            activeClientUUID: activeContext.data.activeClientUUID,
            pipelineSteps: skillPlan.pipelineSteps ?? []
        )
    }

    func finishInlineAssistantAgentRequest(
        contextAtomUUIDs: [String],
        contextSourceIDs: [String]
    ) {
        mergePinnedContextSourceIDs(contextSourceIDs)
        linkedAtomUUIDs.formUnion(contextAtomUUIDs)
    }

    private static func uniqueAtoms(_ atoms: [Atom]) -> [Atom] {
        var seen: Set<String> = []
        var unique: [Atom] = []

        for atom in atoms where !seen.contains(atom.uuid) {
            seen.insert(atom.uuid)
            unique.append(atom)
        }

        return unique
    }

    private func mergePinnedContextSourceIDs(_ sourceIDs: [String]) {
        for sourceID in sourceIDs where !pinnedContextSourceIDs.contains(sourceID) {
            pinnedContextSourceIDs.append(sourceID)
        }
    }

    /// Builds the dynamic context block for system prompt injection.
    private func buildContextBlock() -> String {
        guard activeContext.type != .none else { return "" }

        var lines: [String] = []
        lines.append("## Current Context: \(activeContext.type.displayName)")
        if !activeContext.summary.isEmpty {
            lines.append(activeContext.summary)
        }

        let contextBlock = activeContext.data.toContextBlock()
        if !contextBlock.isEmpty {
            lines.append(contextBlock)
        }
        let structureBlock = noteStructurePlanningBlock()
        if !structureBlock.isEmpty {
            lines.append("\n" + structureBlock)
        }

        if !activeContext.actions.isEmpty {
            lines.append("\nAvailable actions: \(activeContext.actions.map(\.name).joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }

    /// The note-structure planning payload (source note + target thinkspace) —
    /// used by canvas plan flows; travels with inline requests independently of
    /// the view-registration context block.
    private func noteStructurePlanningBlock() -> String {
        guard let noteSnapshot = activeNoteStructureSnapshot() else { return "" }
        return """
        Active source note for structure planning:
        sourceNoteUUID: \(noteSnapshot.sourceNoteUUID.uuidString)
        sourceTitle: \(noteSnapshot.sourceTitle)
        sourceBodyHash: \(noteSnapshot.bodyHash)
        targetThinkspaceUUID: \(resolvedTargetThinkspaceForNoteStructure()?.uuidString ?? "unresolved")
        keepOriginalVisible: true
        Use UTF-16 ranges into the exact noteBody above. Do not rewrite module bodies.
        """
    }

    private func runtimePromptLayer(
        collaboratorPrompt: String?,
        agentProfile: CustomAgentProfile?,
        forcedBundles: Set<AgentToolBundle>
    ) -> String? {
        var sections: [String] = []

        if let collaboratorPrompt,
           !collaboratorPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(collaboratorPrompt)
        }

        if let agentProfile {
            sections.append(agentProfile.routingPromptLayer)
        }

        if !forcedBundles.isEmpty {
            let bundleList = forcedBundles
                .map(\.displayName)
                .sorted()
                .joined(separator: ", ")
            sections.append("""
            ## Request-Forced Capabilities
            The user's wording or active context explicitly requires these capability bundles: \(bundleList).
            Prefer these tools when they are relevant before answering from memory.
            """)
        }

        if forcedBundles.contains(.clientProfiles) {
            sections.append("""
            ## Client Profile Access
            Treat "content profile", "creator profile", "brand profile", and "profile" as client profile requests. If the user names a client or asks for voice, best-performing posts, performance patterns, or an Intelligence Model, load the client profile before answering. Do not say the profile is unavailable or not pinned until the profile tools and pinned context have both failed.
            """)
        }

        return sections.isEmpty ? nil : sections.joined(separator: "\n\n")
    }

    private func forcedToolBundles(for text: String) -> Set<AgentToolBundle> {
        let lower = text.lowercased()
        var bundles: Set<AgentToolBundle> = []

        if containsAny(lower, ["research online", "search online", "look up", "latest", "current", "find stats", "statistics", "sources", "citations"]) {
            bundles.insert(.webResearch)
        }
        if containsAny(lower, ["client profile", "client voice", "client memory", "for client", "brand profile"]) {
            bundles.insert(.clientProfiles)
            bundles.insert(.clientMemory)
        }
        if containsAny(lower, [
            "content profile", "creator profile", "voice profile", "client intelligence",
            "intelligence model", "voice fingerprint", "performance pattern",
            "best performing post", "best-performing post", "top performing post", "top-performing post"
        ]) || (containsAny(lower, ["check out", "show me", "inspect", "look at", "read", "load"]) &&
              (lower.contains(" profile") || lower.contains("'s profile"))) {
            bundles.insert(.clientProfiles)
        }
        if containsAny(lower, ["swipe", "swipes", "examples", "reference ads", "hooks", "frameworks"]) {
            bundles.insert(.swipes)
        }
        if containsAny(lower, [
            "canvas", "thinkspace", "move", "organize", "reorganize", "spatial", "cluster", "arrange", "place this",
            "split note", "structure note", "major concept", "major concepts", "module", "modules", "modularize"
        ]) {
            bundles.insert(.canvasSpatial)
        }
        if containsAny(lower, ["docs", "notes", "database", "db", "content from", "reference docs", "library"]) {
            bundles.insert(.contentSearch)
        }
        if containsAny(lower, ["draft", "write", "rewrite", "edit", "polish", "outline"]) {
            bundles.insert(.writing)
        }

        if activeContext.type == .thinkspaceCanvas {
            bundles.insert(.canvasSpatial)
        }
        if activeContext.type == .contentFocusMode || activeContext.type == .noteFocusMode || activeContext.type == .ideaFocusMode {
            bundles.insert(.contentSearch)
        }
        if activeContext.type == .swipeGallery || activeContext.type == .swipeStudy {
            bundles.insert(.swipes)
        }

        return bundles
    }

    nonisolated static func shouldUseInlineMentionDraftResponse(text: String, hasMentionedAtoms: Bool) -> Bool {
        guard hasMentionedAtoms else { return false }

        let lower = normalizedPolicyText(text)
        let explicitWorkflowSignals = [
            "writing mode",
            "draft mode",
            "create content",
            "create a content",
            "new content atom",
            "save to draft",
            "put it in draft",
            "open in focus mode",
            "generate in the editor"
        ]
        guard !containsAny(lower, explicitWorkflowSignals) else { return false }

        let draftSignals = [
            "write",
            "draft",
            "reel",
            "thread",
            "carousel",
            "script",
            "content piece"
        ]
        let inlineReferenceSignals = [
            "give me every detail",
            "every detail",
            "as reference",
            "output as reference",
            "while writing",
            "first draft",
            "1st draft",
            "reply with",
            "in chat",
            "right here",
            "based on @",
            "use @"
        ]

        return containsAny(lower, draftSignals) && containsAny(lower, inlineReferenceSignals)
    }

    nonisolated static func allowsWritingModeAgentRoute(selectedAgentProfileID: String?) -> Bool {
        selectedAgentProfileID == CosmoWindowAgentIDs.writingMode
    }

    nonisolated static func isNoReplyComplaint(_ text: String) -> Bool {
        let lower = normalizedPolicyText(text)
        let noReplySignals = [
            "you didn't reply",
            "you didnt reply",
            "didn't reply",
            "didnt reply",
            "you didn't answer",
            "you didnt answer",
            "no reply",
            "no response"
        ]
        return lower.count <= 120 && containsAny(lower, noReplySignals)
    }

    private nonisolated static func normalizedPolicyText(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private func agentSuggestions(for profile: CustomAgentProfile) -> [String] {
        let prompts = profile.seedPrompts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return prompts.isEmpty ? defaultPromptSuggestions : Array(prompts.prefix(3))
    }

    private func applyCanvasOperations(
        _ operations: [PendingCanvasOperation],
        targetThinkspaceId: String? = nil
    ) -> Int {
        var applied = 0
        for operation in operations {
            if applyCanvasOperation(operation, targetThinkspaceId: targetThinkspaceId) {
                applied += 1
            }
        }
        return applied
    }

    private func applyCanvasOperation(
        _ operation: PendingCanvasOperation,
        targetThinkspaceId: String? = nil
    ) -> Bool {
        let payload = operation.payload

        switch operation.kind {
        case .arrange:
            NotificationCenter.default.post(
                name: .arrangeCanvasBlocks,
                object: nil,
                userInfo: ["style": payload["style"] ?? payload["layout"] ?? "orbital"]
            )
            return true

        case .placeSearch:
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.placeBlocksOnCanvas,
                object: nil,
                userInfo: [
                    "query": payload["query"] ?? "",
                    "entityType": payload["entityType"] ?? "idea",
                    "quantity": Int(payload["quantity"] ?? "") ?? 5,
                    "layout": payload["layout"] ?? "orbital"
                ]
            )
            return true

        case .createEntity:
            guard let entityType = entityType(from: payload["entityType"]) else { return false }
            var userInfo: [AnyHashable: Any] = ["type": entityType]
            if let title = payload["title"] { userInfo["title"] = title }
            if let content = payload["content"] { userInfo["content"] = content }
            if let position = canvasPosition(from: payload) { userInfo["position"] = position }
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.createEntityAtPosition,
                object: nil,
                userInfo: userInfo
            )
            return true

        case .placeExistingAtom:
            guard let entityType = entityType(from: payload["entityType"]),
                  let uuid = payload["existingAtomUUID"], !uuid.isEmpty else { return false }
            var userInfo: [AnyHashable: Any] = ["type": entityType, "existingAtomUUID": uuid]
            if let position = canvasPosition(from: payload) { userInfo["position"] = position }
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.createEntityAtPosition,
                object: nil,
                userInfo: userInfo
            )
            return true

        case .moveSelection:
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.moveCanvasBlocks,
                object: nil,
                userInfo: [
                    "direction": payload["direction"] ?? "right",
                    "distance": CGFloat(Double(payload["distance"] ?? "") ?? 160)
                ]
            )
            return true

        case .resizeSelection:
            var userInfo: [AnyHashable: Any] = [:]
            if let width = payload["width"].flatMap(Double.init) { userInfo["width"] = CGFloat(width) }
            if let height = payload["height"].flatMap(Double.init) { userInfo["height"] = CGFloat(height) }
            if let scale = payload["scale"].flatMap(Double.init) { userInfo["scale"] = CGFloat(scale) }
            guard !userInfo.isEmpty else { return false }
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.resizeSelectedBlock,
                object: nil,
                userInfo: userInfo
            )
            return true

        case .createAIBlock:
            var userInfo: [AnyHashable: Any] = [:]
            if let query = payload["query"] { userInfo["query"] = query }
            if let mode = payload["mode"] { userInfo["mode"] = mode }
            if let position = canvasPosition(from: payload) { userInfo["position"] = position }
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.createCosmoAIBlock,
                object: nil,
                userInfo: userInfo
            )
            return true

        case .createCluster:
            guard let name = payload["name"], !name.isEmpty else { return false }
            let blockUUIDs = (payload["blockUUIDs"] ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !blockUUIDs.isEmpty else { return false }
            var userInfo: [AnyHashable: Any] = [
                "name": name,
                "blockUUIDs": blockUUIDs
            ]
            if let intent = payload["intent"], !intent.isEmpty { userInfo["intent"] = intent }
            if let targetThinkspaceId { userInfo["thinkspaceId"] = targetThinkspaceId }
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.createClusterFromPlan,
                object: nil,
                userInfo: userInfo
            )
            return true

        case .moveToCluster:
            guard let clusterName = payload["clusterName"], !clusterName.isEmpty else { return false }
            let blockUUIDs = (payload["blockUUIDs"] ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !blockUUIDs.isEmpty else { return false }
            var moveInfo: [AnyHashable: Any] = [
                "clusterName": clusterName,
                "blockUUIDs": blockUUIDs
            ]
            if let targetThinkspaceId { moveInfo["thinkspaceId"] = targetThinkspaceId }
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.moveBlocksToCluster,
                object: nil,
                userInfo: moveInfo
            )
            return true

        case .unsupported:
            return false
        }
    }

    private func entityType(from rawValue: String?) -> EntityType? {
        guard let rawValue else { return .idea }
        return EntityType(rawValue: rawValue)
            ?? EntityType(rawValue: rawValue.replacingOccurrences(of: " ", with: "_"))
            ?? .idea
    }

    private func canvasPosition(from payload: [String: String]) -> CGPoint? {
        guard let xRaw = payload["x"], let yRaw = payload["y"],
              let x = Double(xRaw), let y = Double(yRaw) else {
            return nil
        }
        return CGPoint(x: x, y: y)
    }

    // MARK: - Live Tool Activity Handling (WP5)

    private func handleToolActivity(_ event: ToolActivityEvent) {
        switch event {
        case .started(let name, let displayLabel, _):
            activeToolLabel = displayLabel
            let category = toolActivityCategory(for: name)
            let icon = toolActivityIcon(for: name)
            let item = ToolActivityItem(icon: icon, label: displayLabel, status: .active)

            if let idx = liveToolActivity.firstIndex(where: { $0.category == category }) {
                liveToolActivity[idx].items.append(item)
            } else {
                liveToolActivity.append(ToolActivityGroup(category: category, items: [item]))
                // Only bump scroll tick on new group creation (not every item) to avoid render loop
                toolActivityScrollTick += 1
            }

        case .completed(let name, _, let preview):
            let category = toolActivityCategory(for: name)
            if let gIdx = liveToolActivity.firstIndex(where: { $0.category == category }),
               let iIdx = liveToolActivity[gIdx].items.lastIndex(where: { $0.status == .active }) {
                liveToolActivity[gIdx].items[iIdx] = ToolActivityItem(
                    icon: liveToolActivity[gIdx].items[iIdx].icon,
                    label: liveToolActivity[gIdx].items[iIdx].label,
                    detail: preview,
                    status: .done
                )
            }

        case .allDone:
            activeToolLabel = nil
            for i in liveToolActivity.indices {
                liveToolActivity[i].isComplete = true
            }
            toolActivityScrollTick += 1
        }
    }

    private func toolActivityCategory(for toolName: String) -> String {
        if toolName.hasPrefix("load_") { return "Context Loaded" }
        if toolName.hasPrefix("search_") || toolName.hasPrefix("find_") || toolName.hasPrefix("get_") || toolName.hasPrefix("list_") { return "Viewed" }
        if toolName.hasPrefix("generate_") || toolName.hasPrefix("create_") || toolName.hasPrefix("write_") { return "Generated" }
        if toolName == "web_search" { return "Searched" }
        if toolName.hasPrefix("score_") || toolName.hasPrefix("evaluate_") { return "Analyzed" }
        return "Processed"
    }

    private func toolActivityIcon(for toolName: String) -> String {
        // Context loading tools — specific icons per loaded resource type
        switch toolName {
        case "load_client_profile": return "person.fill"
        case "load_swipe": return "doc.text"
        case "load_client_post": return "star.fill"
        case "load_learned_rules": return "book.fill"
        case "load_skill_modules": return "wrench.and.screwdriver"
        default: break
        }
        if toolName.hasPrefix("search_") || toolName.hasPrefix("find_") || toolName.hasPrefix("get_") || toolName.hasPrefix("list_") { return "doc.text" }
        if toolName.hasPrefix("generate_") || toolName.hasPrefix("create_") || toolName.hasPrefix("write_") { return "sparkles" }
        if toolName == "web_search" { return "globe" }
        if toolName.hasPrefix("score_") || toolName.hasPrefix("evaluate_") { return "chart.bar" }
        return "gearshape"
    }

    /// Updates an existing assistant message in the messages array (for streaming).
    private func updateAssistantMessage(id: UUID, content: String, isStreaming: Bool, toolActivityGroups: [ToolActivityGroup]? = nil) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            let responseMeta = isStreaming ? nil : buildResponseMeta(toolActivityGroups: toolActivityGroups)
            messages[index] = CosmoWindowMessage(
                id: id,
                type: .assistant,
                content: content,
                timestamp: messages[index].timestamp,
                isStreaming: isStreaming,
                toolActivityGroups: toolActivityGroups,
                responseMeta: responseMeta
            )
        }
        if !isStreaming {
            pendingContextTraceSections = []
        }
    }

    /// Persists the current conversation via ConversationMemoryService.
    private func persistConversation() async {
        await persistConversationSnapshot(
            conversationId: conversationId,
            messages: messages,
            linkedAtomUUIDs: linkedAtomUUIDs,
            activeAtomUUID: activeContext.data.currentAtomUUID,
            activeClientUUID: activeContext.data.activeClientUUID,
            pinnedContextSourceIDs: pinnedContextSourceIDs
        )
    }

    private func persistConversationSnapshot(
        conversationId: String,
        messages: [CosmoWindowMessage],
        linkedAtomUUIDs: Set<String>,
        activeAtomUUID: String?,
        activeClientUUID: String?,
        pinnedContextSourceIDs: [String]
    ) async {
        let existingConv = await conversationMemory.loadConversation(id: conversationId)
        let conversation = Self.mergedConversationForPersistence(
            existing: existingConv,
            visibleMessages: messages,
            conversationId: conversationId,
            linkedAtomUUIDs: linkedAtomUUIDs
        )
        await conversationMemory.saveConversation(conversation)
        saveStoredMessages(messages, for: conversationId)
        await persistContextSession(
            conversationId: conversationId,
            activeAtomUUID: activeAtomUUID,
            activeClientUUID: activeClientUUID,
            pinnedContextSourceIDs: pinnedContextSourceIDs
        )
    }

    private func persistContextSession() async {
        await persistContextSession(
            conversationId: conversationId,
            activeAtomUUID: activeContext.data.currentAtomUUID,
            activeClientUUID: activeContext.data.activeClientUUID,
            pinnedContextSourceIDs: pinnedContextSourceIDs
        )
    }

    private func persistContextSession(
        conversationId: String,
        activeAtomUUID: String?,
        activeClientUUID: String?,
        pinnedContextSourceIDs: [String]
    ) async {
        let session = ContextSession(
            id: conversationId,
            surface: .cosmoWindow,
            activeAtomUUID: activeAtomUUID,
            activeClientUUID: activeClientUUID,
            pinnedSourceIDs: pinnedContextSourceIDs
        )
        try? await ContextIndexStore.shared.upsert(session: session)
    }

    nonisolated static func mergedConversationForPersistence(
        existing: AgentConversation?,
        visibleMessages: [CosmoWindowMessage],
        conversationId: String,
        linkedAtomUUIDs: Set<String>
    ) -> AgentConversation {
        var uiConversation = AgentConversation(
            id: conversationId,
            source: .inApp,
            createdAt: existing?.createdAt ?? Date()
        )

        for msg in visibleMessages {
            switch msg.type {
            case .user:
                uiConversation.append(AgentMessage(role: .user, content: msg.content, timestamp: msg.timestamp))
            case .assistant:
                uiConversation.append(AgentMessage(role: .assistant, content: msg.content, timestamp: msg.timestamp))
            case .system:
                uiConversation.append(AgentMessage(role: .system, content: msg.content, timestamp: msg.timestamp))
            case .toolResult(let name, _, _):
                uiConversation.append(AgentMessage(role: .tool, content: msg.content, timestamp: msg.timestamp, toolCallId: name))
            case .contextTrace, .contextChange, .atomCard, .atomList, .graphView, .automationPreview, .workflowPlan, .timelineView, .synthesisCard:
                break
            case .actionButtons:
                uiConversation.append(AgentMessage(role: .assistant, content: msg.content, timestamp: msg.timestamp))
            }
        }

        uiConversation.linkedAtomUUIDs = Array(linkedAtomUUIDs)

        guard var merged = existing, existing?.containsAgentToolContext == true else {
            return uiConversation
        }

        merged = CosmoAgentService.pruneShadowVisibleMessages(merged)

        for message in uiConversation.messages where !merged.messages.containsEquivalentVisibleMessage(to: message) {
            if message.role == .user,
               merged.messages.containsContextEnrichedUserMessage(equivalentTo: message) {
                continue
            }
            merged.append(message)
        }

        merged = CosmoAgentService.pruneShadowVisibleMessages(merged)
        merged.linkedAtomUUIDs = orderedUnique(merged.linkedAtomUUIDs + Array(linkedAtomUUIDs))
        return merged
    }

    nonisolated private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        // Toggle window
        NotificationCenter.default.publisher(for: CosmoNotification.CosmoWindow.toggle)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // Toggle is handled by MainView -- this is for menu bar command routing
                _ = self
            }
            .store(in: &cancellables)
    }

    private func buildResponseMeta(toolActivityGroups: [ToolActivityGroup]?) -> CosmoResponseMeta? {
        let elapsedSeconds: Int?
        if let processingStartedAt {
            elapsedSeconds = max(1, Int(Date().timeIntervalSince(processingStartedAt).rounded()))
        } else {
            elapsedSeconds = nil
        }

        let meta = CosmoResponseMeta(
            elapsedSeconds: elapsedSeconds,
            toolGroups: toolActivityGroups,
            contextTraceSections: pendingContextTraceSections,
            modelLabel: currentModelLabel
        )
        return meta.hasVisibleContent ? meta : nil
    }

    private func messageArchiveKey(for conversationId: String) -> String {
        messageArchiveKeyPrefix + conversationId
    }

    private func loadStoredMessages(for conversationId: String) -> [CosmoWindowMessage]? {
        let key = messageArchiveKey(for: conversationId)
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let decoded = try? decoder.decode([CosmoWindowMessage].self, from: data) else {
            return nil
        }

        return decoded.compactMap { message in
            // Strip stale context change dividers from persisted history
            if case .contextChange = message.type { return nil }
            var normalized = message
            normalized.isStreaming = false
            normalized.toolActivityGroups = nil
            return normalized
        }
    }

    private func saveStoredMessages(_ messages: [CosmoWindowMessage], for conversationId: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(messages) else { return }
        UserDefaults.standard.set(data, forKey: messageArchiveKey(for: conversationId))
    }

    private func appendContextChangeIfNeeded(from oldType: CosmoContextType, to newType: CosmoContextType) {
        guard shouldSurfaceContextChange(from: oldType, to: newType) else { return }
        messages.append(.contextChange(from: oldType.displayName, to: newType.displayName))
    }

    private func shouldSurfaceContextChange(from oldType: CosmoContextType, to newType: CosmoContextType) -> Bool {
        guard oldType != newType, oldType != .none, newType != .none else { return false }

        let hasConversation = messages.contains { message in
            switch message.type {
            case .user, .assistant, .actionButtons:
                return true
            default:
                return false
            }
        }
        guard hasConversation else { return false }

        if case .contextChange(_, let lastTo)? = messages.last?.type, lastTo == newType.displayName {
            return false
        }

        return true
    }
}

// MARK: - Model Picker

struct CosmoModelOption: Identifiable {
    let id: String
    let tier: AgentModelTier?
    let title: String
    let detail: String
    let icon: String

    static let all: [CosmoModelOption] = [
        CosmoModelOption(
            id: "auto",
            tier: nil,
            title: "Auto",
            detail: "Sonnet 5 by default",
            icon: "wand.and.stars"
        ),
        CosmoModelOption(
            id: "gptChatLatest",
            tier: .gptChatLatest,
            title: "GPT Chat Latest",
            detail: "Premium general chat",
            icon: "bubble.left.and.bubble.right"
        ),
        CosmoModelOption(
            id: "geminiFlashLatest",
            tier: .geminiFlashLatest,
            title: "Gemini 3 Flash",
            detail: "Pinned everyday search and brainstorming",
            icon: "bolt"
        ),
        CosmoModelOption(
            id: "gemini35Flash",
            tier: .gemini35Flash,
            title: "Gemini 3.5 Flash",
            detail: "Higher-cost agentic and deepening work",
            icon: "bolt.badge.clock"
        ),
        CosmoModelOption(
            id: "gpt55Thinking",
            tier: .gpt55Thinking,
            title: "GPT 5.5 Thinking",
            detail: "Deep reasoning and hard planning",
            icon: "brain.head.profile"
        ),
        CosmoModelOption(
            id: "opus47",
            tier: .opus47,
            title: "Opus 4.7",
            detail: "Deep writing and synthesis",
            icon: "sparkles"
        ),
        CosmoModelOption(
            id: "haiku",
            tier: .sensor,
            title: "Haiku",
            detail: "Fast capture and lightweight help",
            icon: "speedometer"
        ),
        CosmoModelOption(
            id: "sonnet",
            tier: .strategist,
            title: "Sonnet 4.6",
            detail: "Daily driver via Claude API",
            icon: "point.3.connected.trianglepath.dotted"
        ),
        CosmoModelOption(
            id: "opus",
            tier: .writer,
            title: "Opus 4.6",
            detail: "Legacy premium writing route",
            icon: "text.badge.star"
        )
    ]
}

// MARK: - Chat History Entry

struct ChatHistoryEntry: Identifiable {
    let id: String
    let preview: String
    let messageCount: Int
    let lastActivity: Date
    var isActive: Bool
}

private extension AgentConversation {
    var containsAgentToolContext: Bool {
        messages.contains { message in
            message.role == .tool || !(message.toolCalls?.isEmpty ?? true)
        }
    }
}

private extension Array where Element == AgentMessage {
    func containsEquivalentVisibleMessage(to message: AgentMessage) -> Bool {
        contains { $0.isEquivalentVisibleMessage(to: message) }
    }

    func containsContextEnrichedUserMessage(equivalentTo message: AgentMessage) -> Bool {
        guard message.role == .user else { return false }
        for candidate in self where candidate.role == .user {
            var conversation = AgentConversation(id: "candidate", source: .inApp)
            conversation.messages = [candidate, message]
            let pruned = CosmoAgentService.pruneShadowVisibleMessages(conversation)
            if pruned.messages.count == 1 {
                return true
            }
        }
        return false
    }
}

private extension AgentMessage {
    func isEquivalentVisibleMessage(to other: AgentMessage) -> Bool {
        guard role == other.role else { return false }

        if role == .tool {
            return toolCallId == other.toolCallId && normalizedContent == other.normalizedContent
        }

        return normalizedContent == other.normalizedContent
    }

    var normalizedContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Equatable Helpers

extension CosmoWindowMessageType: Equatable {
    static func == (lhs: CosmoWindowMessageType, rhs: CosmoWindowMessageType) -> Bool {
        switch (lhs, rhs) {
        case (.user, .user), (.assistant, .assistant), (.system, .system):
            return true
        case (.toolResult(let n1, let s1, let e1), .toolResult(let n2, let s2, let e2)):
            return n1 == n2 && s1 == s2 && e1 == e2
        case (.contextTrace(let l1, _), .contextTrace(let l2, _)):
            return l1 == l2
        case (.contextChange(let f1, let t1), .contextChange(let f2, let t2)):
            return f1 == f2 && t1 == t2
        case (.actionButtons(let b1), .actionButtons(let b2)):
            return b1 == b2
        default:
            return false
        }
    }
}
