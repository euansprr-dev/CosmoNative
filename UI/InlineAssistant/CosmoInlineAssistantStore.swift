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
    /// Sources the assistant actually read for this message — rendered as
    /// clickable chips. Decodes as nil from older persisted sessions.
    var sourceRefs: [CosmoAssistantSourceRef]? = nil
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

// MARK: - Thinking States

/// The inline assistant's visible state machine. Each phase has its own narration
/// register and (in the bar/orb) its own motion, so progress reads as character
/// instead of a generic spinner.
enum CosmoInlineAssistantPhase: Equatable, Sendable {
    case idle
    /// Request sent; the model is deciding what to do (no tool has fired yet).
    case planning
    /// Tools are running — narrated with verb-first status lines.
    case gathering(status: String)
    /// The model is producing its deliverable (streaming an answer or staging edits).
    case drafting
    /// A proposal is staged and awaiting the user's accept/reject.
    case reviewing

    var isWorking: Bool {
        switch self {
        case .planning, .gathering, .drafting: return true
        case .idle, .reviewing: return false
        }
    }

    var statusText: String? {
        switch self {
        case .idle: return nil
        case .planning: return "Cosmo is thinking…"
        case .gathering(let status): return status
        case .drafting: return "Cosmo is writing…"
        case .reviewing: return nil
        }
    }
}

/// Turns raw tool activity into verb-first status lines in the user's vocabulary —
/// "Pulling swipes on curiosity hooks", "Checking Hormozi's voice profile" — built
/// client-side from the tool name + arguments at zero model cost. The narration IS
/// the personality made visible; generic "Working…" tells the user nothing.
enum CosmoInlineAssistantStatusGrammar {
    static func line(toolName: String, displayLabel: String, args: [String: String]) -> String {
        let subject = args["query"] ?? args["title"] ?? args["clientName"] ?? args["client_name"] ?? args["name"]
        let trimmedSubject = subject?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch toolName {
        case "search_swipes", "find_similar_swipes", "filter_swipes_by_taxonomy":
            if let trimmedSubject, !trimmedSubject.isEmpty { return "Pulling swipes on \(trimmedSubject)" }
            return "Pulling swipes"
        case "get_client_profile", "lookup_client_facts":
            if let trimmedSubject, !trimmedSubject.isEmpty { return "Checking \(trimmedSubject)'s profile" }
            return "Checking the client profile"
        case "search_ideas":
            if let trimmedSubject, !trimmedSubject.isEmpty { return "Searching ideas for \(trimmedSubject)" }
            return "Searching your ideas"
        case "retrieve_context", "search_memory":
            if let trimmedSubject, !trimmedSubject.isEmpty { return "Recalling \(trimmedSubject)" }
            return "Recalling related work"
        case "web_search", "search_web":
            if let trimmedSubject, !trimmedSubject.isEmpty { return "Researching \(trimmedSubject)" }
            return "Researching online"
        case "read_draft", "get_content":
            return "Reading your draft"
        case "get_lessons":
            return "Reviewing learned rules"
        case "propose_workspace_edit":
            return "Staging your edits"
        case "answer_in_assistant_pane":
            return "Writing the answer"
        case "create_inline_skill":
            return "Saving the new skill"
        case "inspect_current_thinkspace":
            return "Looking at your canvas"
        default:
            return displayLabel
        }
    }
}

enum CosmoInlineAssistantActivityLabel {
    static let maxStatusLength = 72

    static func statusText(for event: ToolActivityEvent) -> String? {
        switch event {
        case .started(let name, let displayLabel, let args):
            return compact(CosmoInlineAssistantStatusGrammar.line(
                toolName: name,
                displayLabel: displayLabel,
                args: args
            ))
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

// MARK: - Embedding Skill Auto-Routing

/// Zero-LLM skill routing: embeds the composer prompt with the local nomic daemon
/// and cosine-matches it against each skill's trigger description. The winning
/// skill surfaces as a ghost chip the user can Tab to confirm — explicit /slash
/// selection always beats this suggestion. Replaces brittle keyword heuristics
/// and gets *better* as users describe triggers in their own vocabulary.
@MainActor
final class CosmoInlineSkillAutoRouter {
    static let shared = CosmoInlineSkillAutoRouter()

    struct Suggestion: Equatable {
        let skillID: String
        let skillName: String
        let icon: String
        let score: Float
    }

    /// Skills the router never suggests: the per-route defaults the request falls
    /// back to anyway — a suggestion that matches the fallback is pure noise.
    private static let defaultSkillIDs: Set<String> = [
        CosmoInlineAssistantSkillID.inlineEdit.rawValue,
        CosmoInlineAssistantSkillID.researchAnswer.rawValue
    ]

    private static let minimumScore: Float = 0.50
    private static let minimumMargin: Float = 0.05
    private static let minimumPromptLength = 12

    /// Per-skill vector cache keyed by a fingerprint of the routing text, so
    /// edited skills re-embed and untouched ones don't.
    private var skillVectors: [String: (fingerprint: String, vector: [Float])] = [:]

    func suggestion(
        for rawPrompt: String,
        registry: CosmoInlineSkillRegistry = CosmoInlineSkillRegistry()
    ) async -> Suggestion? {
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard prompt.count >= Self.minimumPromptLength,
              !prompt.hasPrefix("/") else { return nil }

        guard let promptVector = await embed(prompt) else { return nil }

        var best: (skill: CosmoInlineSkillDefinition, score: Float)?
        var runnerUpScore: Float = 0

        for skill in registry.enabledSkills where !Self.defaultSkillIDs.contains(skill.id) {
            guard let skillVector = await vector(for: skill) else { continue }
            let score = Self.cosineSimilarity(promptVector, skillVector)
            if score > (best?.score ?? 0) {
                runnerUpScore = best?.score ?? 0
                best = (skill, score)
            } else if score > runnerUpScore {
                runnerUpScore = score
            }
        }

        guard let best,
              best.score >= Self.minimumScore,
              best.score - runnerUpScore >= Self.minimumMargin else {
            return nil // Below confidence or ambiguous — stay quiet, never guess.
        }

        return Suggestion(
            skillID: best.skill.id,
            skillName: best.skill.name,
            icon: best.skill.icon,
            score: best.score
        )
    }

    private func vector(for skill: CosmoInlineSkillDefinition) async -> [Float]? {
        let routingText = Self.routingText(for: skill)
        let fingerprint = CosmoEditableSurfaceHasher.hash(routingText)

        if let cached = skillVectors[skill.id], cached.fingerprint == fingerprint {
            return cached.vector
        }
        guard let vector = await embed(routingText) else { return nil }
        skillVectors[skill.id] = (fingerprint, vector)
        return vector
    }

    static func routingText(for skill: CosmoInlineSkillDefinition) -> String {
        var parts = [skill.name, skill.triggerDescription ?? skill.summary]
        parts.append(contentsOf: skill.triggerPhrases)
        return parts
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: ". ")
    }

    private func embed(_ text: String) async -> [Float]? {
        if let cached = await EmbeddingCache.shared.get(for: text) { return cached }
        guard let full = try? await DaemonXPCClient.shared.embed(text: text) else { return nil }
        let truncated = Array(full.prefix(256)) // Matryoshka truncation, matches stored vectors
        await EmbeddingCache.shared.set(truncated, for: text)
        return truncated
    }

    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var magnitudeA: Float = 0
        var magnitudeB: Float = 0
        for index in a.indices {
            dot += a[index] * b[index]
            magnitudeA += a[index] * a[index]
            magnitudeB += b[index] * b[index]
        }
        let denominator = magnitudeA.squareRoot() * magnitudeB.squareRoot()
        return denominator > 0 ? dot / denominator : 0
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

        // The agent can always take the user places — navigation is reversible
        // and costs four small tool definitions.
        bundles.insert(.navigation)

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
    @Published var phase: CosmoInlineAssistantPhase = .idle
    @Published var proposals: [CosmoAssistantProposal] = []
    @Published var paneMessages: [CosmoInlineAssistantPaneMessage] = []
    @Published var selectedContextAtoms: [Atom] = []
    @Published var selectedSkillID: String?
    @Published var isPaneRequested = false
    @Published var errorText: String?
    /// Embedding-routed skill suggestion shown as a ghost chip (Tab to confirm).
    @Published var skillSuggestion: CosmoInlineSkillAutoRouter.Suggestion?

    private var skillSuggestionTask: Task<Void, Never>?

    private let agentBridge: CosmoInlineAssistantAgentBridge
    private let sessionPersistence: CosmoInlineAssistantSessionPersistence
    private var activeSessionSurfaceID = CosmoInlineAssistantSessionScope.globalSurfaceID
    private(set) var activeSubmissionSkillID: String?
    private var activeSubmissionRoute: CosmoInlineAssistantRoute?
    private var lastSubmissionRoute: CosmoInlineAssistantRoute?
    private var activeSubmissionShouldOpenPaneForAnswer = false
    /// The pane message currently being streamed token-by-token, if any.
    /// Finalized (replaced with the complete answer) when the tool call lands.
    private var streamingPaneMessageID: UUID?
    /// Supplies the sources actually read for the in-flight request — set by the
    /// agent bridge for the request's duration, attached to answers/proposals as
    /// clickable context chips.
    var sourceRefsProvider: (() -> [CosmoAssistantSourceRef])?

    private var currentSourceRefs: [CosmoAssistantSourceRef]? {
        let refs = sourceRefsProvider?() ?? []
        return refs.isEmpty ? nil : refs
    }

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
        var prompt = slashCommand?.remainingPrompt ?? rawPrompt
        if prompt.isEmpty {
            // A bare slash command ("/concept ⏎") is a valid way to start a
            // skill session — kick it off instead of silently doing nothing.
            guard effectiveSkillID != nil else { return }
            prompt = "Begin."
        }

        composerText = ""
        errorText = nil
        skillSuggestionTask?.cancel()
        skillSuggestion = nil
        isProcessing = true
        phase = .planning
        statusText = "Reading current context"
        CosmoInlineAssistantMetrics.shared.requestStarted()

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
            // Skill sessions are sticky: once a skill is invoked (slash command
            // or picker), every following turn stays in that skill — like
            // talking to a dedicated agent — until /clear, the chip's ✕, or
            // another slash command replaces it.
            selectedSkillID = effectiveSkillID
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
        streamingPaneMessageID = nil
        phase = activePendingProposal != nil ? .reviewing : .idle
    }

    func receive(proposal: CosmoAssistantProposal) {
        var stamped = proposal
        if stamped.skillID == nil {
            stamped.skillID = activeSubmissionSkillID
        }
        proposals.append(stamped)
        paneMessages.append(.init(
            role: .assistant,
            content: stamped.summary,
            proposalID: stamped.id,
            sourceRefs: currentSourceRefs
        ))
        if !activeSubmissionShouldOpenPaneForAnswer {
            isPaneRequested = false
        }
        phase = .reviewing
        CosmoInlineAssistantMetrics.shared.proposalStaged()
        persistActiveSession()
    }

    /// Streamed fragment of the pane answer, decoded live from the
    /// `answer_in_assistant_pane` tool call's partial JSON. Creates the assistant
    /// message on the first delta and grows it in place, so the answer reads out
    /// token-by-token instead of landing as a wall of text seconds later.
    func receivePaneAnswerDelta(_ delta: String) {
        guard !delta.isEmpty else { return }
        phase = .drafting
        statusText = nil
        CosmoInlineAssistantMetrics.shared.firstAnswerTokenArrived()

        if let streamingID = streamingPaneMessageID,
           let index = paneMessages.firstIndex(where: { $0.id == streamingID }) {
            paneMessages[index].content += delta
            return
        }

        let effectiveRoute = activeSubmissionRoute
        if effectiveRoute != .action || activeSubmissionShouldOpenPaneForAnswer {
            isPaneRequested = true
        }
        let message = CosmoInlineAssistantPaneMessage(role: .assistant, content: delta)
        streamingPaneMessageID = message.id
        paneMessages.append(message)
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
        CosmoInlineAssistantMetrics.shared.paneAnswerDelivered()

        // If this answer was streamed in, finalize the streaming message in place
        // (the complete tool arguments are authoritative) instead of duplicating it.
        if let streamingID = streamingPaneMessageID,
           let index = paneMessages.firstIndex(where: { $0.id == streamingID }) {
            if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                paneMessages.insert(.init(role: .system, content: title), at: index)
                paneMessages[index + 1].content = answer
                paneMessages[index + 1].sourceRefs = currentSourceRefs
            } else {
                paneMessages[index].content = answer
                paneMessages[index].sourceRefs = currentSourceRefs
            }
            streamingPaneMessageID = nil
            persistActiveSession()
            return
        }

        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            paneMessages.append(.init(role: .system, content: title))
        }
        paneMessages.append(.init(role: .assistant, content: answer, sourceRefs: currentSourceRefs))
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

    /// Debounced embedding-based skill routing for the composer's current text.
    /// Quiet by design: no suggestion while a skill is already selected, while a
    /// slash command is being typed, or when the router isn't confident.
    func refreshSkillSuggestion() {
        skillSuggestionTask?.cancel()

        let prompt = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard selectedSkillID == nil, !prompt.isEmpty, !prompt.hasPrefix("/") else {
            skillSuggestion = nil
            return
        }

        skillSuggestionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            let suggestion = await CosmoInlineSkillAutoRouter.shared.suggestion(for: prompt)
            guard !Task.isCancelled, let self,
                  self.composerText.trimmingCharacters(in: .whitespacesAndNewlines) == prompt else { return }
            self.skillSuggestion = suggestion
        }
    }

    /// Confirm the ghost-chip suggestion (Tab in the composer).
    func acceptSkillSuggestion() {
        guard let suggestion = skillSuggestion else { return }
        selectedSkillID = suggestion.skillID
        skillSuggestion = nil
        persistActiveSession()
    }

    func dismissSkillSuggestion() {
        skillSuggestion = nil
    }

    func receiveToolActivity(_ event: ToolActivityEvent) {
        statusText = CosmoInlineAssistantActivityLabel.statusText(for: event)

        switch event {
        case .started(let name, _, _):
            if name == "inline_thinking" || name == "inline_context" {
                phase = .planning
            } else if let status = statusText {
                phase = .gathering(status: status)
            }
        case .completed:
            phase = .drafting
        case .allDone:
            break
        }
    }

    func accept(
        operationID: UUID,
        registry: CosmoEditableSurfaceRegistry = .shared
    ) async {
        guard let location = operationLocation(for: operationID) else { return }
        let proposal = proposals[location.proposalIndex]

        // Live view first; if no view has this surface open, fall back to applying
        // straight to the atom (e.g. appending to a note that isn't open).
        var resolvedProvider: (any CosmoEditableSurfaceProvider)? = registry.provider(surfaceID: proposal.surfaceID)
        if resolvedProvider == nil {
            resolvedProvider = await CosmoAtomBackedEditableSurface.load(surfaceID: proposal.surfaceID)
        }
        guard let provider = resolvedProvider else {
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
            if result.status == .applied || result.status == .accepted {
                recordSkillOutcome(
                    proposal: proposals[location.proposalIndex],
                    operation: operation,
                    accepted: true
                )
            }
        } catch {
            markOperation(operationID, as: .conflicted)
            errorText = error.localizedDescription
            persistActiveSession()
        }
    }

    /// Skill-scoped learning: every accept/reject accrues to the skill that
    /// produced the proposal, so per-skill accept rates (and future lesson
    /// extraction) reflect real usage instead of vibes.
    private func recordSkillOutcome(
        proposal: CosmoAssistantProposal,
        operation: CosmoAssistantProposalOperation,
        accepted: Bool
    ) {
        guard let skillID = proposal.skillID else { return }
        let suggestion = operation.proposedText ?? proposal.summary
        Task {
            await AgentOutcomeTracker.shared.trackSuggestionAcceptance(
                suggestion: String(suggestion.prefix(500)),
                userFeedback: accepted ? "accepted inline diff" : "rejected inline diff",
                accepted: accepted,
                category: "skill:\(skillID)"
            )
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
        recordSkillOutcome(proposal: proposal, operation: operation, accepted: false)
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
        CosmoInlineAssistantMetrics.shared.operationResolved(status: status)
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
        phase = .idle
        streamingPaneMessageID = nil
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
        phase = .idle
        streamingPaneMessageID = nil
        isPaneRequested = false
    }

    private static func isClearCommand(_ prompt: String) -> Bool {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "/clear"
    }
}
