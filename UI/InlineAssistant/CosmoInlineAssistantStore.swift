import Combine
import Foundation

struct CosmoInlineAssistantPaneMessage: Identifiable, Codable, Equatable, Sendable {
    enum Role: String, Codable, Equatable, Sendable {
        case user
        case assistant
        case system
    }

    var id = UUID()
    var role: Role
    var content: String
    var proposalID: UUID? = nil
    var createdAt = Date()
}

enum CosmoInlineAssistantSessionScope {
    static let globalSurfaceID = "global"

    static func surfaceID(for rawSurfaceID: String?) -> String {
        let trimmed = rawSurfaceID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? globalSurfaceID : trimmed
    }

    static func conversationID(for rawSurfaceID: String?) -> String {
        "cosmo-inline-assistant:\(surfaceID(for: rawSurfaceID))"
    }
}

struct CosmoInlineAssistantPersistedSession: Codable, Equatable {
    var schemaVersion = 1
    var surfaceID: String
    var paneMessages: [CosmoInlineAssistantPaneMessage]
    var proposals: [CosmoAssistantProposal]
    var selectedContextAtoms: [Atom]
    var selectedSkillID: String?
    var lastSubmissionRoute: CosmoInlineAssistantRoute?
    var updatedAt = Date()

    var isEmpty: Bool {
        paneMessages.isEmpty && proposals.isEmpty && selectedContextAtoms.isEmpty && selectedSkillID == nil
    }
}

final class CosmoInlineAssistantSessionPersistence {
    private let loadData: (String) -> Data?
    private let saveData: (String, Data) -> Void
    private let deleteData: (String) -> Void

    init(
        loadData: @escaping (String) -> Data?,
        saveData: @escaping (String, Data) -> Void,
        deleteData: @escaping (String) -> Void
    ) {
        self.loadData = loadData
        self.saveData = saveData
        self.deleteData = deleteData
    }

    static let live = CosmoInlineAssistantSessionPersistence.userDefaults()

    static func defaultForRuntime() -> CosmoInlineAssistantSessionPersistence {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return inMemory()
        }
        return live
    }

    static func userDefaults(
        _ defaults: UserDefaults = .standard,
        namespace: String = "cosmo.inlineAssistant.session"
    ) -> CosmoInlineAssistantSessionPersistence {
        CosmoInlineAssistantSessionPersistence(
            loadData: { surfaceID in
                defaults.data(forKey: storageKey(namespace: namespace, surfaceID: surfaceID))
            },
            saveData: { surfaceID, data in
                defaults.set(data, forKey: storageKey(namespace: namespace, surfaceID: surfaceID))
            },
            deleteData: { surfaceID in
                defaults.removeObject(forKey: storageKey(namespace: namespace, surfaceID: surfaceID))
            }
        )
    }

    static func inMemory() -> CosmoInlineAssistantSessionPersistence {
        final class Box {
            var values: [String: Data] = [:]
        }
        let box = Box()
        return CosmoInlineAssistantSessionPersistence(
            loadData: { box.values[$0] },
            saveData: { box.values[$0] = $1 },
            deleteData: { box.values.removeValue(forKey: $0) }
        )
    }

    func load(surfaceID: String) -> CosmoInlineAssistantPersistedSession? {
        guard let data = loadData(surfaceID) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CosmoInlineAssistantPersistedSession.self, from: data)
    }

    func save(_ session: CosmoInlineAssistantPersistedSession) {
        guard !session.isEmpty else {
            delete(surfaceID: session.surfaceID)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(session) else { return }
        saveData(session.surfaceID, data)
    }

    func delete(surfaceID: String) {
        deleteData(surfaceID)
    }

    private static func storageKey(namespace: String, surfaceID: String) -> String {
        "\(namespace).\(surfaceID)"
    }
}

enum CosmoInlineAssistantPromptClassifier {
    static func route(
        for prompt: String,
        previousRoute: CosmoInlineAssistantRoute? = nil
    ) -> CosmoInlineAssistantRoute {
        if CosmoInlineAssistantWorkingContextCache.isFollowUp(prompt),
           let previousRoute {
            return previousRoute
        }
        return CosmoInlineAssistantSkillRuntime.plan(for: prompt, surfaceKind: nil).route
    }
}

enum CosmoInlineAssistantActivityLabel {
    static let maxStatusLength = 72

    static func statusText(for event: ToolActivityEvent) -> String? {
        switch event {
        case .started(_, let displayLabel, _):
            return compact(displayLabel)
        case .completed:
            // After each step the model is generating the next one — show live progress
            // instead of a stale label during the LLM call that follows.
            return "Cosmo is writing…"
        case .allDone:
            return nil
        }
    }

    static func compact(_ rawLabel: String) -> String {
        let normalized = rawLabel
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")

        guard normalized.count > maxStatusLength else { return normalized }
        let end = normalized.index(normalized.startIndex, offsetBy: maxStatusLength - 3)
        return String(normalized[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

enum CosmoInlineAssistantToolBundlePolicy {
    static func bundles(
        for prompt: String,
        route: CosmoInlineAssistantRoute,
        surfaceKind: CosmoEditableSurfaceKind?
    ) -> Set<AgentToolBundle> {
        let lower = prompt.lowercased()
        let skillPlan = CosmoInlineAssistantSkillRuntime.plan(for: prompt, surfaceKind: surfaceKind)
        var bundles = skillPlan.toolBundles

        if containsAny(lower, [
            "client profile", "client voice", "client memory", "brand profile",
            "content profile", "creator profile", "voice profile", "profile",
            "for client", "for ben", "ben's", "best performing", "top performing",
            "performance pattern", "intelligence model"
        ]) {
            bundles.insert(.clientProfiles)
            bundles.insert(.clientMemory)
        }

        if containsAny(lower, [
            "swipe", "swipes", "reel", "reels", "best performing",
            "top performing", "examples", "reference ads", "hooks", "frameworks"
        ]) {
            bundles.insert(.swipes)
            bundles.insert(.analytics)
        }

        if containsAny(lower, [
            "flow", "outline", "storytelling", "step by step", "sequence",
            "post", "draft", "write", "writing", "rewrite", "script", "slide"
        ]) {
            bundles.insert(.writing)
            bundles.insert(.strategy)
            bundles.insert(.contentSearch)
        }

        if containsAny(lower, [
            "docs", "notes", "database", "content from", "reference docs",
            "library", "current idea", "current focus", "current context"
        ]) {
            bundles.insert(.contentSearch)
        }

        if CosmoInlineAssistantResearchIntent.isWebResearchRequest(lower) {
            bundles.insert(.webResearch)
        }

        if containsAny(lower, [
            "canvas", "thinkspace", "organize", "reorganize", "arrange",
            "cluster", "move", "spatial"
        ]) || surfaceKind == .canvas {
            bundles.insert(.canvasSpatial)
        }

        if route == .answer {
            bundles.insert(.contentSearch)
        }

        return bundles
    }

    static func reducedBundlesForInlineRequest(
        _ bundles: Set<AgentToolBundle>,
        route: CosmoInlineAssistantRoute,
        resolvedContexts: Set<CosmoInlineAssistantSkillContext>
    ) -> Set<AgentToolBundle> {
        guard route == .action,
              resolvedContexts.contains(.clientProfile),
              bundles.contains(.clientProfiles) else {
            return bundles
        }

        var reduced = bundles
        reduced.remove(.clientProfiles)
        reduced.insert(.clientFactLookup)
        return reduced
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}

@MainActor
final class CosmoInlineAssistantStore: ObservableObject {
    static let shared = CosmoInlineAssistantStore()

    @Published var composerText = ""
    @Published var isProcessing = false
    @Published var statusText: String?
    @Published var proposals: [CosmoAssistantProposal] = []
    @Published var paneMessages: [CosmoInlineAssistantPaneMessage] = []
    @Published var selectedContextAtoms: [Atom] = []
    @Published var selectedSkillID: String?
    @Published var isPaneRequested = false
    @Published var errorText: String?

    private let agentBridge: CosmoInlineAssistantAgentBridge
    private let sessionPersistence: CosmoInlineAssistantSessionPersistence
    private var activeSessionSurfaceID = CosmoInlineAssistantSessionScope.globalSurfaceID
    private(set) var activeSubmissionSkillID: String?
    private var activeSubmissionRoute: CosmoInlineAssistantRoute?
    private var lastSubmissionRoute: CosmoInlineAssistantRoute?
    private var activeSubmissionShouldOpenPaneForAnswer = false

    init(
        agentBridge: CosmoInlineAssistantAgentBridge = .live,
        sessionPersistence: CosmoInlineAssistantSessionPersistence = .defaultForRuntime()
    ) {
        self.agentBridge = agentBridge
        self.sessionPersistence = sessionPersistence
        restoreSession(for: activeSessionSurfaceID)
    }

    func submit() async {
        let rawPrompt = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawPrompt.isEmpty else { return }

        if Self.isClearCommand(rawPrompt) {
            await clearActiveSession()
            return
        }

        let skillRegistry = CosmoInlineSkillRegistry()
        let slashCommand = CosmoInlineSlashSkillParser.extractCommand(
            from: rawPrompt,
            registry: skillRegistry
        )
        let effectiveSkillID = slashCommand?.skillID ?? selectedSkillID
        let prompt = slashCommand?.remainingPrompt ?? rawPrompt
        guard !prompt.isEmpty else { return }

        composerText = ""
        errorText = nil
        isProcessing = true
        statusText = "Reading current context"

        let selectedSkillPlan = effectiveSkillID.map {
            CosmoInlineAssistantSkillRuntime.plan(
                for: prompt,
                surfaceKind: nil,
                previousSkillID: nil,
                selectedSkillID: $0,
                registry: skillRegistry
            )
        }
        let route = selectedSkillPlan?.route ?? CosmoInlineAssistantPromptClassifier.route(
            for: prompt,
            previousRoute: lastSubmissionRoute
        )
        activeSubmissionSkillID = effectiveSkillID
        activeSubmissionRoute = route
        activeSubmissionShouldOpenPaneForAnswer = route == .action && (
            selectedSkillPlan?.panePolicy == .openForResearchBackedAction ||
            selectedSkillPlan?.panePolicy == .alwaysOpenWithResult ||
            CosmoInlineAssistantResearchIntent.shouldOpenPaneForActionExplanation(prompt)
        )
        defer {
            lastSubmissionRoute = route
            activeSubmissionSkillID = nil
            activeSubmissionRoute = nil
            activeSubmissionShouldOpenPaneForAnswer = false
            selectedSkillID = nil
            persistActiveSession()
        }

        if route == .answer || activeSubmissionShouldOpenPaneForAnswer {
            isPaneRequested = true
        } else {
            isPaneRequested = false
        }

        paneMessages.append(.init(role: .user, content: prompt))
        persistActiveSession()

        do {
            try await agentBridge.send(prompt, route, self)
        } catch {
            errorText = error.localizedDescription
        }

        isProcessing = false
        statusText = nil
    }

    func receive(proposal: CosmoAssistantProposal) {
        proposals.append(proposal)
        paneMessages.append(.init(
            role: .assistant,
            content: proposal.summary,
            proposalID: proposal.id
        ))
        if !activeSubmissionShouldOpenPaneForAnswer {
            isPaneRequested = false
        }
        persistActiveSession()
    }

    func receivePaneAnswer(
        title: String?,
        answer: String,
        route: CosmoInlineAssistantRoute? = nil
    ) {
        let effectiveRoute = route ?? activeSubmissionRoute
        let shouldOpenPane = effectiveRoute != .action || activeSubmissionShouldOpenPaneForAnswer

        if shouldOpenPane {
            isPaneRequested = true
        }
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            paneMessages.append(.init(role: .system, content: title))
        }
        paneMessages.append(.init(role: .assistant, content: answer))
        persistActiveSession()
    }

    func requestPane() {
        isPaneRequested = true
    }

    var shouldOpenPaneForCurrentActionExplanation: Bool {
        activeSubmissionShouldOpenPaneForAnswer
    }

    func addContext(_ atom: Atom) {
        guard !selectedContextAtoms.contains(where: { $0.uuid == atom.uuid }) else { return }
        selectedContextAtoms.append(atom)
        persistActiveSession()
    }

    func insertContextMention(_ atom: Atom, selection: NSRange) -> MentionComposerTextReplacement {
        addContext(atom)
        return MentionComposerMentionParser.replacingActiveMention(
            in: composerText,
            selectedRange: selection,
            title: CosmoInlineAssistantContextMentionFormatter.mentionTitle(for: atom)
        )
    }

    func removeContext(_ atom: Atom) {
        selectedContextAtoms.removeAll { $0.uuid == atom.uuid }
        persistActiveSession()
    }

    func clearContexts() {
        selectedContextAtoms.removeAll()
        persistActiveSession()
    }

    func receiveToolActivity(_ event: ToolActivityEvent) {
        statusText = CosmoInlineAssistantActivityLabel.statusText(for: event)
    }

    func accept(
        operationID: UUID,
        registry: CosmoEditableSurfaceRegistry = .shared
    ) async {
        guard let location = operationLocation(for: operationID) else { return }
        let proposal = proposals[location.proposalIndex]
        guard let provider = registry.provider(surfaceID: proposal.surfaceID) else {
            markOperation(operationID, as: .conflicted)
            errorText = "The editable surface for this proposal is no longer available."
            return
        }

        await accept(operationID: operationID, provider: provider)
    }

    func accept(
        operationID: UUID,
        provider: any CosmoEditableSurfaceProvider
    ) async {
        guard let location = operationLocation(for: operationID) else { return }
        let operation = proposals[location.proposalIndex].operations[location.operationIndex]
        guard operation.status == .pending || operation.status == .conflicted else { return }

        let snapshot = provider.editableSnapshot()
        guard provider.surfaceID == proposals[location.proposalIndex].surfaceID
                || operation.targetID == snapshot.targetID else {
            markOperation(operationID, as: .conflicted)
            errorText = "The editable surface for this proposal changed."
            return
        }

        guard operation.canApply(against: snapshot) else {
            markOperation(operationID, as: .conflicted)
            errorText = "The source changed since Cosmo drafted this edit. Ask Cosmo to regenerate it."
            return
        }

        do {
            let result = try await provider.apply(operation: operation)
            markOperation(operationID, as: result.status)
            errorText = nil
            persistActiveSession()
        } catch {
            markOperation(operationID, as: .conflicted)
            errorText = error.localizedDescription
            persistActiveSession()
        }
    }

    func reject(
        operationID: UUID,
        registry: CosmoEditableSurfaceRegistry = .shared
    ) async {
        guard let location = operationLocation(for: operationID) else { return }
        let proposal = proposals[location.proposalIndex]
        let operation = proposal.operations[location.operationIndex]
        guard operation.status == .pending || operation.status == .conflicted else { return }

        if let provider = registry.provider(surfaceID: proposal.surfaceID) {
            let result = await provider.reject(operation: operation)
            markOperation(operationID, as: result.status)
        } else {
            markOperation(operationID, as: .rejected)
        }
        errorText = nil
        persistActiveSession()
    }

    func acceptAll(proposalID: UUID) async {
        guard let proposal = proposals.first(where: { $0.id == proposalID }) else { return }
        for operation in proposal.operations where operation.status == .pending || operation.status == .conflicted {
            await accept(operationID: operation.id)
        }
    }

    func rejectAll(proposalID: UUID) async {
        guard let proposal = proposals.first(where: { $0.id == proposalID }) else { return }
        for operation in proposal.operations where operation.status == .pending || operation.status == .conflicted {
            await reject(operationID: operation.id)
        }
    }

    func revert(
        operationID: UUID,
        registry: CosmoEditableSurfaceRegistry = .shared
    ) async {
        guard let location = operationLocation(for: operationID) else { return }
        let proposal = proposals[location.proposalIndex]
        let operation = proposal.operations[location.operationIndex]
        guard operation.isRevertable else { return }

        guard let provider = registry.provider(surfaceID: proposal.surfaceID) else {
            markOperation(operationID, as: .conflicted)
            errorText = "The editable surface for this proposal is no longer available."
            return
        }

        let snapshot = provider.editableSnapshot()
        guard let inverse = operation.inverseOperation(sourceHash: snapshot.sourceHash),
              inverse.targetID == snapshot.targetID else {
            markOperation(operationID, as: .conflicted)
            errorText = "This change cannot be reverted from the current surface."
            return
        }

        do {
            let result = try await provider.apply(operation: inverse)
            if result.status == .applied || result.status == .accepted {
                markOperation(operationID, as: .reverted)
                errorText = nil
            } else {
                markOperation(operationID, as: result.status)
                errorText = result.message
            }
            persistActiveSession()
        } catch {
            markOperation(operationID, as: .conflicted)
            errorText = error.localizedDescription
            persistActiveSession()
        }
    }

    func revertAll(
        proposalID: UUID,
        registry: CosmoEditableSurfaceRegistry = .shared
    ) async {
        guard let proposal = proposals.first(where: { $0.id == proposalID }) else { return }
        for operation in proposal.operations where operation.isRevertable {
            await revert(operationID: operation.id, registry: registry)
        }
    }

    func proposal(id: UUID) -> CosmoAssistantProposal? {
        proposals.first { $0.id == id }
    }

    /// The most recent proposal for a specific surface that still has changes to review.
    /// Drives the inline diff that replaces a surface's editor while review is active.
    func pendingProposal(
        forSurfaceID surfaceID: String,
        targetID: String? = nil,
        activeAtomUUID: String? = nil
    ) -> CosmoAssistantProposal? {
        proposals.last { proposal in
            proposal.hasReviewableOperations && proposal.matches(
                surfaceID: surfaceID,
                targetID: targetID,
                activeAtomUUID: activeAtomUUID
            )
        }
    }

    /// The most recent proposal anywhere that still has changes to review.
    /// Drives the global accept/reject bar above the composer.
    var activePendingProposal: CosmoAssistantProposal? {
        proposals.last { $0.hasReviewableOperations }
    }

    func dismissPaneRequest() {
        isPaneRequested = false
    }

    func activateSession(surfaceID rawSurfaceID: String?) {
        let surfaceID = CosmoInlineAssistantSessionScope.surfaceID(for: rawSurfaceID)
        guard surfaceID != activeSessionSurfaceID else { return }

        persistActiveSession()
        activeSessionSurfaceID = surfaceID
        restoreSession(for: surfaceID)
    }

    var activeConversationID: String {
        CosmoInlineAssistantSessionScope.conversationID(for: activeSessionSurfaceID)
    }

    func clearActiveSession() async {
        let surfaceID = activeSessionSurfaceID
        let conversationID = activeConversationID

        resetSessionState()
        sessionPersistence.delete(surfaceID: surfaceID)
        CosmoInlineAssistantWorkingContextCache.shared.clear(
            conversationID: conversationID,
            surfaceID: surfaceID
        )
        await ConversationMemoryService.shared.deleteConversation(id: conversationID)
        await CosmoMemoryService.shared.clearWorkingMemory(conversationID: conversationID)
    }

    private func operationLocation(for operationID: UUID) -> (proposalIndex: Int, operationIndex: Int)? {
        for proposalIndex in proposals.indices {
            if let operationIndex = proposals[proposalIndex].operations.firstIndex(where: { $0.id == operationID }) {
                return (proposalIndex, operationIndex)
            }
        }
        return nil
    }

    private func markOperation(_ operationID: UUID, as status: CosmoProposalStatus) {
        guard let location = operationLocation(for: operationID) else { return }
        proposals[location.proposalIndex].operations[location.operationIndex].status = status
    }

    private func persistActiveSession() {
        sessionPersistence.save(CosmoInlineAssistantPersistedSession(
            surfaceID: activeSessionSurfaceID,
            paneMessages: paneMessages,
            proposals: proposals,
            selectedContextAtoms: selectedContextAtoms,
            selectedSkillID: selectedSkillID,
            lastSubmissionRoute: lastSubmissionRoute
        ))
    }

    private func restoreSession(for surfaceID: String) {
        guard let session = sessionPersistence.load(surfaceID: surfaceID) else {
            resetSessionState()
            return
        }

        paneMessages = session.paneMessages
        proposals = session.proposals
        selectedContextAtoms = session.selectedContextAtoms
        selectedSkillID = session.selectedSkillID
        lastSubmissionRoute = session.lastSubmissionRoute
        composerText = ""
        errorText = nil
        statusText = nil
        isPaneRequested = false
    }

    private func resetSessionState() {
        composerText = ""
        paneMessages = []
        proposals = []
        selectedContextAtoms = []
        selectedSkillID = nil
        lastSubmissionRoute = nil
        activeSubmissionSkillID = nil
        activeSubmissionRoute = nil
        errorText = nil
        statusText = nil
        isPaneRequested = false
    }

    private static func isClearCommand(_ prompt: String) -> Bool {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "/clear"
    }
}
