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
    /// Links the message to a staged inquiry-question confirmation card.
    /// Decodes as nil from older persisted sessions.
    var inquiryProposalID: UUID? = nil
    /// The tool-call timeline behind this answer — replayed as a collapsed
    /// receipt. Decodes as nil from older persisted sessions.
    var activitySteps: [CosmoInlineAssistantActivityStep]? = nil
    /// The skill that handled the run this (user) message started.
    /// Decodes as nil from older persisted sessions.
    var skillID: String? = nil
    /// Links the message to a staged canvas-plan review card (thinkspace
    /// copilot). Plans are transient — a persisted message whose plan is gone
    /// renders as plain text. Decodes as nil from older persisted sessions.
    var canvasPlanID: UUID? = nil
    /// Groups every message of one run (ask → receipts → deliverables) so the
    /// pane renders runs as cards instead of a flat bubble stream. Decodes as
    /// nil from older persisted sessions (those render ungrouped).
    var runID: UUID? = nil
}

enum CosmoCanvasPlanStatus: Equatable, Sendable {
    case pending
    case applied
    case dismissed
}

enum CosmoInlineAssistantSessionScope {
    static let globalSurfaceID = "global"
    /// Conversation-id prefix marking inline assistant sessions — the agent
    /// service keys its window/receipt policies on it.
    static let conversationIDPrefix = "cosmo-inline-assistant"

    static func surfaceID(for rawSurfaceID: String?) -> String {
        let trimmed = rawSurfaceID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? globalSurfaceID : trimmed
    }

    static func conversationID(for rawSurfaceID: String?) -> String {
        "\(conversationIDPrefix):\(surfaceID(for: rawSurfaceID))"
    }
}

struct CosmoInlineAssistantPersistedSession: Codable, Equatable {
    var schemaVersion = 1
    var surfaceID: String
    var paneMessages: [CosmoInlineAssistantPaneMessage]
    var proposals: [CosmoAssistantProposal]
    var selectedContextAtoms: [Atom]
    var selectedSkillID: String?
    /// True only when the user explicitly chose a skill via slash, menu, or
    /// accepting the suggestion chip. Passive auto-routing stays one-shot.
    var selectedSkillIsExplicit: Bool? = nil
    var lastSubmissionRoute: CosmoInlineAssistantRoute?
    /// Optional so blobs persisted before inquiry cards decode unchanged.
    var inquiryQuestionProposals: [CosmoAssistantInquiryQuestionProposal]? = nil
    /// The session's turn ledger — optional so older persisted blobs decode
    /// unchanged (schemaVersion stays 1).
    var ledger: [CosmoInlineTurnRecord]? = nil
    var updatedAt = Date()

    var isEmpty: Bool {
        paneMessages.isEmpty && proposals.isEmpty && selectedContextAtoms.isEmpty && selectedSkillID == nil
            && (inquiryQuestionProposals?.isEmpty ?? true)
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
        // `swift test` (SPM) does not set XCTestConfigurationFilePath the way
        // xcodebuild test does — without the class check, test stores restored
        // the USER'S real persisted sessions and every count assertion drifted.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil {
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
        previousRoute: CosmoInlineAssistantRoute? = nil,
        hasSelection: Bool = false,
        hasRecentActionContext: Bool = false
    ) -> CosmoInlineAssistantRoute {
        // A live selection plus a short imperative ("shorten this", "punchier")
        // is an edit on the selection — keyword planning would otherwise scatter
        // these across routes.
        if hasSelection, isShortImperative(prompt) {
            return .action
        }
        // A short imperative in a session whose last run staged edits continues
        // that work — decided by session state (the ledger holds a recent
        // action), not by follow-up keyword lists.
        if let previousRoute, hasRecentActionContext, isShortImperative(prompt) {
            return previousRoute
        }
        return CosmoInlineAssistantSkillRuntime.plan(for: prompt, surfaceKind: nil).route
    }

    static func isShortImperative(_ prompt: String) -> Bool {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasSuffix("?") else { return false }
        let words = trimmed.split(separator: " ")
        guard words.count <= 8 else { return false }
        let lower = trimmed.lowercased()
        let interrogatives = ["what", "why", "how", "who", "when", "where", "which", "does", "is ", "are ", "can you explain", "tell me"]
        return !interrogatives.contains { lower.hasPrefix($0) }
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

    /// One symbol vocabulary for every surface that wears the phase (orb, pane
    /// header, timeline) — the bar and pane previously disagreed on idle.
    var symbolName: String {
        switch self {
        case .idle: return "sparkles"
        case .planning: return "sparkles"
        case .gathering: return "magnifyingglass"
        case .drafting: return "pencil.and.outline"
        case .reviewing: return "checkmark.circle"
        }
    }
}

/// Turns raw tool activity into verb-first status lines in the user's vocabulary —
/// "Pulling swipes on curiosity hooks", "Checking Hormozi's voice profile" — built
/// client-side from the tool name + arguments at zero model cost. The narration IS
/// the personality made visible; generic "Working…" tells the user nothing.
enum CosmoInlineAssistantStatusGrammar {
    /// The key argument worth narrating, in priority order. Shared by the status
    /// line and the activity timeline so both name the same subject.
    static func subject(args: [String: String]) -> String? {
        let raw = args["query"] ?? args["title"] ?? args["clientName"] ?? args["client_name"] ?? args["name"]
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    static func line(toolName: String, displayLabel: String, args: [String: String]) -> String {
        let trimmedSubject = subject(args: args)

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
        return String(normalized[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
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
        // Recall cloud embeddings (the old daemon path threw on every call).
        // Skill vectors are cached per-launch, so dims stay consistent.
        guard let vector = try? await RecallEmbedding.embedText(text) else { return nil }
        await EmbeddingCache.shared.set(vector, for: text)
        return vector
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
    @Published var inquiryQuestionProposals: [CosmoAssistantInquiryQuestionProposal] = []
    @Published var paneMessages: [CosmoInlineAssistantPaneMessage] = []
    @Published var selectedContextAtoms: [Atom] = []
    @Published var selectedSkillID: String? {
        didSet {
            selectedSkillIsExplicit = selectedSkillID != nil
        }
    }
    @Published var isPaneRequested = false
    @Published var errorText: String?
    /// Contextual quick replies after a run — one tap prefills and sends.
    /// Transient: cleared on submit, clear, and session switches.
    @Published var followUpSuggestions: [String] = []
    /// Staged canvas plans awaiting review (thinkspace copilot). Transient —
    /// they reference the live canvas and don't survive session reloads.
    @Published private(set) var canvasPlanProposals: [PendingCanvasPlan] = []
    @Published private(set) var canvasPlanStatuses: [UUID: CosmoCanvasPlanStatus] = [:]
    /// The live text selection on the focused editor — the bar quotes it in a
    /// chip so the user sees what "shorten this" will target before sending.
    /// Equality-guarded so caret churn doesn't re-render the bar.
    @Published private(set) var currentSelection: CosmoEditableSelection?
    private var currentSelectionSurfaceID: String?
    /// Embedding-routed skill suggestion shown as a ghost chip (Tab to confirm).
    @Published var skillSuggestion: CosmoInlineSkillAutoRouter.Suggestion?
    /// The in-flight run's tool calls, in order — drives the live working
    /// thread, then gets attached to the answer as its receipt.
    @Published private(set) var currentRunSteps: [CosmoInlineAssistantActivityStep] = []
    /// Title of the surface the active session is scoped to (nil for global).
    @Published private(set) var activeSurfaceTitle: String?
    /// Kind of the active surface — lets the empty state suggest starters that
    /// fit what the user is looking at.
    @Published private(set) var activeSurfaceKind: CosmoEditableSurfaceKind?
    /// The entity prefix of the bound surface ("content", "note", "idea",
    /// "connection") — drives the scope chip's tint in the pane header.
    @Published private(set) var activeSurfaceEntity: String?
    /// One record per run this session: ask → deliverable → review outcome.
    /// Rendered into the volatile prompt layer as "## Session So Far", so every
    /// turn's model sees the true session state (the continuity carrier).
    @Published private(set) var sessionLedger: [CosmoInlineTurnRecord] = []
    /// Event-triggered skill offer (one-tap chip; dismissible; zero tokens
    /// until tapped). Set by CosmoInlineSkillAutoRunner.
    @Published private(set) var autoSkillSuggestion: CosmoInlineSkillAutoRunner.Suggestion?
    /// "Promote this run to a skill" — a prefilled draft the Assistant Studio
    /// opens with. Set from a run card's context menu; the bar presents the
    /// Studio when this becomes non-nil.
    @Published var pendingStudioSkillDraft: CosmoInlineSkillDefinition?

    private var skillSuggestionTask: Task<Void, Never>?
    /// The in-flight agent run, held so the stop button can actually cancel it.
    private var activeRunTask: Task<Void, Error>?
    /// Stamped on every pane message the current run produces — the pane
    /// groups a run's messages into one card.
    private var currentRunID: UUID?

    private let agentBridge: CosmoInlineAssistantAgentBridge
    private let sessionPersistence: CosmoInlineAssistantSessionPersistence
    private var activeSessionSurfaceID = CosmoInlineAssistantSessionScope.globalSurfaceID
    private(set) var activeSubmissionSkillID: String?
    private var selectedSkillIsExplicit = false
    private var activeSubmissionRoute: CosmoInlineAssistantRoute?
    private var lastSubmissionRoute: CosmoInlineAssistantRoute?
    private var activeSubmissionShouldOpenPaneForAnswer = false
    /// The pane message currently being streamed token-by-token, if any.
    /// Finalized (replaced with the complete answer) when the tool call lands.
    private(set) var streamingPaneMessageID: UUID?
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

        bindToLiveSurfaceBeforeSubmission()

        let skillRegistry = CosmoInlineSkillRegistry()
        let slashCommand = CosmoInlineSlashSkillParser.extractCommand(
            from: rawPrompt,
            registry: skillRegistry
        )
        let explicitSelectedSkillID = selectedSkillIsExplicit ? selectedSkillID : nil
        let autoRoutedSkillID = (slashCommand == nil && explicitSelectedSkillID == nil)
            ? skillSuggestion?.skillID
            : nil
        let effectiveSkillID = slashCommand?.skillID ?? explicitSelectedSkillID ?? autoRoutedSkillID
        let shouldKeepSkillSelected = slashCommand?.skillID != nil || explicitSelectedSkillID != nil
        var prompt = slashCommand?.remainingPrompt ?? rawPrompt
        if prompt.isEmpty {
            // A bare slash command ("/concept ⏎") is a valid way to start a
            // skill session — kick it off instead of silently doing nothing.
            guard effectiveSkillID != nil else { return }
            prompt = "Begin."
        }

        selectedContextAtoms = ContextSourcePolicy.filteredAtoms(selectedContextAtoms, query: prompt)

        composerText = ""
        errorText = nil
        followUpSuggestions = []
        skillSuggestionTask?.cancel()
        skillSuggestion = nil
        isProcessing = true
        phase = .planning
        statusText = "Reading current context"
        currentRunSteps = []
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
            previousRoute: lastSubmissionRoute,
            hasSelection: activeEditableSnapshot()?.selection?.isEmpty == false,
            hasRecentActionContext: hasRecentActionContext
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
            // or picker), every following turn stays in that skill. Passive
            // auto-routing is only for this run so it cannot hijack later asks.
            selectedSkillID = shouldKeepSkillSelected ? effectiveSkillID : nil
            persistActiveSession()
        }

        if route == .answer || activeSubmissionShouldOpenPaneForAnswer {
            isPaneRequested = true
        } else {
            isPaneRequested = false
        }

        let runID = UUID()
        currentRunID = runID
        paneMessages.append(.init(role: .user, content: prompt, skillID: effectiveSkillID, runID: runID))
        persistActiveSession()

        let assistantMessageCountBeforeRun = paneMessages.filter { $0.role == .assistant }.count
        let answerMessageCountBeforeRun = paneMessages.filter {
            $0.role == .assistant && $0.proposalID == nil
        }.count
        let proposalCountBeforeRun = proposals.count

        let runTask = Task { [agentBridge] in
            try await agentBridge.send(prompt, route, self)
        }
        activeRunTask = runTask
        do {
            try await runTask.value
        } catch {
            if Self.isCancellation(error) {
                finalizeCancelledRun()
            } else {
                let message = error.localizedDescription
                errorText = message
                if !didProduceVisibleRunOutput(
                    assistantMessageCountBeforeRun: assistantMessageCountBeforeRun,
                    proposalCountBeforeRun: proposalCountBeforeRun
                ) {
                    receivePaneAnswer(
                        title: nil,
                        answer: "I hit an error before I could finish: \(message)",
                        route: .answer
                    )
                }
            }
        }
        activeRunTask = nil

        appendLedgerRecord(
            runID: runID,
            userAsk: prompt,
            route: route,
            skillID: effectiveSkillID,
            proposalCountBeforeRun: proposalCountBeforeRun,
            answerMessageCountBeforeRun: answerMessageCountBeforeRun
        )
        currentRunID = nil

        isProcessing = false
        statusText = nil
        streamingPaneMessageID = nil
        currentRunSteps = []
        phase = activePendingProposal != nil ? .reviewing : .idle
    }

    /// Stop the in-flight run. Cancellation propagates through the agent loop's
    /// awaits; whatever already streamed into the pane stays.
    func cancelActiveRun() {
        activeRunTask?.cancel()
    }

    var canCancelActiveRun: Bool {
        isProcessing && activeRunTask != nil
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    /// A stopped run still settles its receipts: a partially streamed answer
    /// keeps its content and gets the steps so far; a run that produced nothing
    /// leaves a quiet "Stopped" marker instead of vanishing.
    private func finalizeCancelledRun() {
        if let streamingID = streamingPaneMessageID,
           let index = paneMessages.firstIndex(where: { $0.id == streamingID }) {
            paneMessages[index].sourceRefs = currentSourceRefs
            paneMessages[index].activitySteps = takeFinalizedRunSteps()
        } else {
            paneMessages.append(.init(role: .system, content: "Stopped"))
        }
        persistActiveSession()
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
            sourceRefs: currentSourceRefs,
            activitySteps: takeFinalizedRunSteps(),
            runID: currentRunID
        ))
        statusText = nil
        if !activeSubmissionShouldOpenPaneForAnswer {
            isPaneRequested = false
        }
        phase = .reviewing
        followUpSuggestions = Self.followUps(afterProposal: stamped)
        CosmoInlineAssistantMetrics.shared.proposalStaged()
        persistActiveSession()
    }

    /// A staged canvas plan (thinkspace copilot): rendered as a review card in
    /// the pane; nothing touches the canvas until the user approves. Plans are
    /// transient by design — they reference the live canvas, so they don't
    /// survive session reloads (the card degrades to its summary text).
    func receive(canvasPlan: PendingCanvasPlan) {
        canvasPlanProposals.append(canvasPlan)
        paneMessages.append(.init(
            role: .assistant,
            content: "\(canvasPlan.title) — \(canvasPlan.rationale)",
            activitySteps: takeFinalizedRunSteps(),
            canvasPlanID: canvasPlan.id,
            runID: currentRunID
        ))
        statusText = nil
        phase = .reviewing
        isPaneRequested = true
        followUpSuggestions = ["Tighten the clusters", "Name them better", "Try a different grouping"]
        persistActiveSession()
    }

    func canvasPlan(id: UUID) -> PendingCanvasPlan? {
        canvasPlanProposals.first { $0.id == id }
    }

    func canvasPlanStatus(id: UUID) -> CosmoCanvasPlanStatus {
        canvasPlanStatuses[id] ?? .pending
    }

    /// Approve: apply through the same pipeline the old window used, then
    /// drop a receipt line.
    func approveCanvasPlan(id: UUID) {
        guard let plan = canvasPlan(id: id), canvasPlanStatus(id: id) == .pending else { return }
        let applied = CosmoWindowViewModel.shared.applyCanvasPlan(plan)
        canvasPlanStatuses[id] = .applied
        paneMessages.append(.init(
            role: .system,
            content: applied == plan.operations.count
                ? "Applied — \(applied) canvas \(applied == 1 ? "change" : "changes")."
                : "Applied \(applied) of \(plan.operations.count) canvas changes."
        ))
        persistActiveSession()
    }

    func dismissCanvasPlan(id: UUID) {
        guard canvasPlanStatus(id: id) == .pending else { return }
        canvasPlanStatuses[id] = .dismissed
    }

    /// A staged inquiry-question card: the user confirms (→ deep-dive session)
    /// or dismisses it, right in the conversation flow.
    func receive(inquiryProposal: CosmoAssistantInquiryQuestionProposal) {
        inquiryQuestionProposals.append(inquiryProposal)
        paneMessages.append(.init(
            role: .assistant,
            content: inquiryProposal.question,
            inquiryProposalID: inquiryProposal.id,
            runID: currentRunID
        ))
        statusText = nil
        isPaneRequested = true
        persistActiveSession()
    }

    func inquiryProposal(id: UUID) -> CosmoAssistantInquiryQuestionProposal? {
        inquiryQuestionProposals.first { $0.id == id }
    }

    /// Confirm the card: create the question in its deep dive and jump into the
    /// inquiry session. Errors surface in the pane without losing the card.
    func startInquiry(proposalID: UUID) async {
        guard let index = inquiryQuestionProposals.firstIndex(where: { $0.id == proposalID }) else { return }
        let proposal = inquiryQuestionProposals[index]
        if proposal.status == .started, let sessionUUID = proposal.startedSessionUUID {
            CosmoInlineInquiryQuestionStarter.reopen(
                sessionUUID: sessionUUID,
                connectionUUID: proposal.connectionUUID
            )
            return
        }

        do {
            let result = try await CosmoInlineInquiryQuestionStarter.start(proposal)
            inquiryQuestionProposals[index].status = .started
            inquiryQuestionProposals[index].startedSessionUUID = result.sessionUUID
            inquiryQuestionProposals[index].deepDiveUUID = result.deepDiveUUID
            persistActiveSession()
        } catch {
            errorText = "Couldn't start the inquiry: \(error.localizedDescription)"
        }
    }

    func dismissInquiry(proposalID: UUID) {
        guard let index = inquiryQuestionProposals.firstIndex(where: { $0.id == proposalID }),
              inquiryQuestionProposals[index].status == .pending else { return }
        inquiryQuestionProposals[index].status = .dismissed
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
        let message = CosmoInlineAssistantPaneMessage(role: .assistant, content: delta, runID: currentRunID)
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
        var finalAnswer = CraftPaneAnswerRepair.repairedAnswer(
            forRawSkillID: activeSubmissionSkillID,
            content: answer
        ) ?? answer
        // The concept collaborator must never use em dashes (user preference);
        // the prompt says so, this guarantees it even if the model slips.
        if activeSubmissionSkillID == CosmoInlineAssistantSkillID.concept.rawValue {
            finalAnswer = ConnectionSurfaceSerializer.removeEmDashes(finalAnswer)
        }

        if shouldOpenPane {
            isPaneRequested = true
        }
        statusText = nil
        CosmoInlineAssistantMetrics.shared.paneAnswerDelivered()

        // If this answer was streamed in, finalize the streaming message in place
        // (the complete tool arguments are authoritative) instead of duplicating it.
        if let streamingID = streamingPaneMessageID,
           let index = paneMessages.firstIndex(where: { $0.id == streamingID }) {
            if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                paneMessages.insert(.init(role: .system, content: title), at: index)
                paneMessages[index + 1].content = finalAnswer
                paneMessages[index + 1].sourceRefs = currentSourceRefs
                paneMessages[index + 1].activitySteps = takeFinalizedRunSteps()
            } else {
                paneMessages[index].content = finalAnswer
                paneMessages[index].sourceRefs = currentSourceRefs
                paneMessages[index].activitySteps = takeFinalizedRunSteps()
            }
            streamingPaneMessageID = nil
            followUpSuggestions = Self.followUps(afterAnswerRoute: effectiveRoute, skillID: activeSubmissionSkillID)
            persistActiveSession()
            return
        }

        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            paneMessages.append(.init(role: .system, content: title, runID: currentRunID))
        }
        paneMessages.append(.init(
            role: .assistant,
            content: finalAnswer,
            sourceRefs: currentSourceRefs,
            activitySteps: takeFinalizedRunSteps(),
            runID: currentRunID
        ))
        followUpSuggestions = Self.followUps(afterAnswerRoute: effectiveRoute, skillID: activeSubmissionSkillID)
        persistActiveSession()
    }

    // MARK: - Follow-up suggestions

    /// Contextual quick replies after a run — one tap prefills and sends.
    /// Transient by design: cleared on the next submit or session switch.
    static func followUps(afterProposal proposal: CosmoAssistantProposal) -> [String] {
        let hasFormatting = proposal.operations.contains { $0.kind == .formatMarks }
        var suggestions = ["Explain the changes"]
        suggestions.append(hasFormatting ? "Do the same for the rest" : "Push it further")
        suggestions.append("Try a different angle")
        return suggestions
    }

    static func followUps(
        afterAnswerRoute route: CosmoInlineAssistantRoute?,
        skillID: String? = nil
    ) -> [String] {
        if skillID == CosmoInlineAssistantSkillID.concept.rawValue {
            // The concept partner already asks its own deepening question in
            // prose and captures as you go — so these continue the dialogue
            // instead of implying it didn't go deep or offering to author
            // content for the user.
            return ["Keep developing this", "That's not quite what I mean", "Move to another angle"]
        }
        return ["Stage that as an edit", "Go deeper", "Give me an example"]
    }

    /// Whether this message is still receiving streamed deltas — streaming rows
    /// render as cheap plain text; finalized rows get the rich prose treatment.
    func isStreamingMessage(_ id: UUID) -> Bool {
        streamingPaneMessageID == id
    }

    /// Sources known so far for the in-flight run — lets the streaming row
    /// resolve `[[uuid]]` markers to titles before the rich finalize.
    var currentStreamingSourceRefs: [CosmoAssistantSourceRef] {
        sourceRefsProvider?() ?? []
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

    /// Synthetic bridge events that narrate planning — they drive the phase but
    /// are not real tool calls, so they never become timeline steps.
    private static let planningEventNames: Set<String> = ["inline_thinking", "inline_context"]

    func receiveToolActivity(_ event: ToolActivityEvent) {
        statusText = CosmoInlineAssistantActivityLabel.statusText(for: event)

        switch event {
        case .started(let name, let displayLabel, let args):
            if Self.planningEventNames.contains(name) {
                phase = .planning
            } else {
                if let status = statusText {
                    phase = .gathering(status: status)
                }
                currentRunSteps.append(CosmoInlineAssistantActivityStep(
                    toolName: name,
                    label: CosmoInlineAssistantActivityLabel.compact(
                        CosmoInlineAssistantStatusGrammar.line(toolName: name, displayLabel: displayLabel, args: args)
                    ),
                    subject: CosmoInlineAssistantStatusGrammar.subject(args: args)
                ))
            }
        case .completed(let name, _, _):
            phase = .drafting
            if let index = currentRunSteps.lastIndex(where: { $0.toolName == name && $0.state == .running }) {
                currentRunSteps[index].state = .done
                currentRunSteps[index].finishedAt = Date()
            }
        case .allDone:
            finishAllRunningSteps()
        }
    }

    private func finishAllRunningSteps() {
        let now = Date()
        for index in currentRunSteps.indices where currentRunSteps[index].state == .running {
            currentRunSteps[index].state = .done
            currentRunSteps[index].finishedAt = now
        }
    }

    /// Hands the finished timeline to the message that landed it: stragglers are
    /// marked done, the live thread empties, and only the first finalize in a run
    /// gets steps — one receipt per run.
    private func takeFinalizedRunSteps() -> [CosmoInlineAssistantActivityStep]? {
        guard !currentRunSteps.isEmpty else { return nil }
        finishAllRunningSteps()
        let steps = currentRunSteps
        currentRunSteps = []
        return steps
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

    /// Accept a single operation. When `applying` is set (transaction steps),
    /// that compiled, byte-exact operation is what actually applies while the
    /// review status stays keyed to the ORIGINAL operation's id.
    func accept(
        operationID: UUID,
        provider: any CosmoEditableSurfaceProvider,
        applying override: CosmoAssistantProposalOperation? = nil
    ) async {
        guard let location = operationLocation(for: operationID) else { return }
        let operation = proposals[location.proposalIndex].operations[location.operationIndex]
        guard operation.status == .pending || operation.status == .conflicted else { return }
        let applying = override ?? operation

        let snapshot = provider.editableSnapshot()
        guard provider.surfaceID == proposals[location.proposalIndex].surfaceID
                || operation.targetID == snapshot.targetID else {
            markOperation(operationID, as: .conflicted)
            errorText = "The editable surface for this proposal changed."
            return
        }

        guard applying.canApply(against: snapshot) else {
            markOperation(operationID, as: .conflicted)
            errorText = "The source changed since Cosmo drafted this edit. Ask Cosmo to regenerate it."
            return
        }

        do {
            let result = try await provider.apply(operation: applying)
            markOperation(operationID, as: result.status)
            errorText = nil
            persistActiveSession()
            if result.status == .applied || result.status == .accepted {
                recordSkillOutcome(
                    proposal: proposals[location.proposalIndex],
                    operation: operation,
                    accepted: true
                )
                // Event hook for auto-triggered skills (cooldown-guarded, so a
                // multi-op accept-all fires at most once per skill+surface).
                CosmoInlineSkillAutoRunner.shared.proposalAccepted(
                    surfaceID: proposals[location.proposalIndex].surfaceID,
                    store: self
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
        // Plain edit runs (no explicit skill) accrue to the default edit skill —
        // otherwise the most common proposals would never build a track record
        // for the review-outcome recall block.
        let skillID = proposal.skillID ?? CosmoInlineAssistantSkillID.inlineEdit.rawValue
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

    /// Accept every pending operation as ONE transaction: all anchors resolve
    /// against the same original snapshot and apply bottom-up, so a renumber
    /// cascade can never alias into text an earlier accept just produced
    /// (the old one-at-a-time re-resolution corrupted multi-op edits).
    func acceptAll(
        proposalID: UUID,
        registry: CosmoEditableSurfaceRegistry = .shared
    ) async {
        guard let proposal = proposals.first(where: { $0.id == proposalID }) else { return }
        let pending = proposal.operations.filter { $0.status == .pending || $0.status == .conflicted }
        guard !pending.isEmpty else { return }

        var resolvedProvider: (any CosmoEditableSurfaceProvider)? = registry.provider(surfaceID: proposal.surfaceID)
        if resolvedProvider == nil {
            resolvedProvider = await CosmoAtomBackedEditableSurface.load(surfaceID: proposal.surfaceID)
        }
        guard let provider = resolvedProvider else {
            for operation in pending {
                markOperation(operation.id, as: .conflicted)
            }
            errorText = "The editable surface for this proposal is no longer available."
            return
        }

        let snapshot = provider.editableSnapshot()

        // Drift shield for the one-click path: an operation that was staged as
        // a LOCATED edit but no longer matches the document would degrade to a
        // bottom-append here — silently, because accept-all doesn't force the
        // user through each woven diff. Those stay pending for individual
        // review; everything still anchored applies as one transaction.
        // (Individual accepts keep the never-block contract untouched.)
        var applicable: [CosmoAssistantProposalOperation] = []
        var driftedCount = 0
        for operation in pending {
            let isTextEdit = operation.kind == .textReplacement
                || operation.kind == .structuredFieldReplacement
                || operation.kind == .textInsertion
            let anchoredAtStaging = operation.originalText?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty == false
            if isTextEdit, anchoredAtStaging,
               let placement = CosmoInlineTextEditResolver.placement(for: operation, in: snapshot.text),
               placement.placementKind == .appendFallback {
                driftedCount += 1
                continue
            }
            applicable.append(operation)
        }
        if !applicable.isEmpty {
            let plan = CosmoInlineEditTransaction.compile(
                operations: applicable,
                sourceText: snapshot.text
            )
            for step in plan.steps {
                await accept(operationID: step.id, provider: provider, applying: step)
            }
        }

        // After the applies — a successful accept clears errorText, and the
        // drift notice must survive the transaction it was excluded from.
        if driftedCount > 0 {
            errorText = driftedCount == 1
                ? "1 change no longer matches the document — review it in the diff before accepting."
                : "\(driftedCount) changes no longer match the document — review them in the diff before accepting."
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

    func activeEditableSnapshot(
        registry: CosmoEditableSurfaceRegistry = .shared
    ) -> CosmoEditableSourceSnapshot? {
        if activeSessionSurfaceID != CosmoInlineAssistantSessionScope.globalSurfaceID,
           let scopedSnapshot = registry
            .provider(surfaceID: activeSessionSurfaceID)?
            .editableSnapshot() {
            return scopedSnapshot
        }

        return registry.activeSurface?.editableSnapshot()
    }

    func dismissPaneRequest() {
        isPaneRequested = false
    }

    /// THE single entry point for every "ask Cosmo" affordance (✦ in the quill
    /// bar, ⌥A, the margins' "ask cosmo →", Command-K, the Notes rail card):
    /// scope the assistant to the calling surface and open the pane.
    func openPane(forSurfaceID surfaceID: String? = nil) {
        if let surfaceID {
            CosmoEditableSurfaceRegistry.shared.activateIfNeeded(surfaceID: surfaceID)
            activateSessionIfIdle(surfaceID: surfaceID)
        }
        isPaneRequested = true
    }

    /// Submit a prompt programmatically on behalf of a surface affordance
    /// ("improve selected text") — binds, fills the composer, and sends.
    func submitPrompt(_ prompt: String, forSurfaceID surfaceID: String? = nil) {
        if let surfaceID {
            CosmoEditableSurfaceRegistry.shared.activateIfNeeded(surfaceID: surfaceID)
        }
        composerText = prompt
        Task { await submit() }
    }

    /// Focus modes report their live selection here (from the same handlers
    /// that feed the surface snapshot). Editors report nil/empty on deselection;
    /// an editor that is NOT the current selection's owner can't wipe another
    /// editor's chip by clearing its own stale selection.
    /// A selection is only true while its owning surface is the ACTIVE one.
    /// Called from the surface registry's activation choke points: navigating
    /// to a different document must never carry the previous document's
    /// highlight (the owning editor is unmounted and can no longer clear it,
    /// and `reportSelection`'s ownership guard rightly ignores other editors).
    func clearSelectionIfForeign(toActiveSurfaceID surfaceID: String) {
        guard let owner = currentSelectionSurfaceID, owner != surfaceID else { return }
        currentSelectionSurfaceID = nil
        if currentSelection != nil { currentSelection = nil }
    }

    /// The owning editor is going away (document closed) — its highlight goes
    /// with it, even when no new editable surface takes over.
    func clearSelectionIfOwned(bySurfaceID surfaceID: String) {
        guard currentSelectionSurfaceID == surfaceID else { return }
        currentSelectionSurfaceID = nil
        if currentSelection != nil { currentSelection = nil }
    }

    func reportSelection(_ selection: CosmoEditableSelection?, forSurfaceID surfaceID: String) {
        let normalized = (selection?.isEmpty == false) ? selection : nil
        if normalized == nil {
            guard currentSelectionSurfaceID == surfaceID || currentSelectionSurfaceID == nil else { return }
            currentSelectionSurfaceID = nil
            if currentSelection != nil { currentSelection = nil }
            return
        }
        currentSelectionSurfaceID = surfaceID
        guard currentSelection != normalized else { return }
        currentSelection = normalized
    }

    /// The active session's surface key — exposed for the session distiller
    /// (which turns idle sessions into durable memory).
    var activeSessionSurfaceIDForDistillation: String {
        activeSessionSurfaceID
    }

    func activateSession(surfaceID rawSurfaceID: String?) {
        let surfaceID = CosmoInlineAssistantSessionScope.surfaceID(for: rawSurfaceID)
        guard surfaceID != activeSessionSurfaceID else {
            refreshActiveSurfaceTitle()
            return
        }

        persistActiveSession()
        // Switching away is the session's natural end — distill durable facts
        // from the outgoing ledger in the background.
        CosmoSessionDistiller.shared.distillIfWorthwhile(
            sessionKey: activeSessionSurfaceID,
            ledger: sessionLedger
        )
        activeSessionSurfaceID = surfaceID
        followUpSuggestions = []
        restoreSession(for: surfaceID)
        refreshActiveSurfaceTitle()
    }

    /// Navigation binding: a view registering its surface may pull the assistant
    /// to it whenever no run is in flight. Sessions are isolated by surface, so
    /// a finished chat on atom A must not follow the user into atom B; the only
    /// unsafe time to retarget is while a request is actively running.
    func activateSessionIfIdle(surfaceID rawSurfaceID: String?) {
        guard !isProcessing,
              activeRunTask == nil else {
            return
        }
        activateSession(surfaceID: rawSurfaceID)
    }

    private func bindToLiveSurfaceBeforeSubmission() {
        guard let liveSurfaceID = CosmoEditableSurfaceRegistry.shared.activeSurface?.surfaceID else { return }

        let previousSessionID = activeSessionSurfaceID
        let shouldCarryFreshGlobalComposerPicks = activeSessionSurfaceID == CosmoInlineAssistantSessionScope.globalSurfaceID
            && paneMessages.isEmpty
            && proposals.isEmpty
            && inquiryQuestionProposals.isEmpty
        let pickedSkillID = selectedSkillID
        let pickedContexts = selectedContextAtoms

        activateSession(surfaceID: liveSurfaceID)

        if activeSessionSurfaceID != previousSessionID, shouldCarryFreshGlobalComposerPicks {
            // Explicit composer picks made before the first surface bind belong
            // to this message. Do not carry picks from one atom-scoped thread to
            // another; that is context leakage.
            if pickedSkillID != nil { selectedSkillID = pickedSkillID }
            if !pickedContexts.isEmpty { selectedContextAtoms = pickedContexts }
        }
    }

    private func didProduceVisibleRunOutput(
        assistantMessageCountBeforeRun: Int,
        proposalCountBeforeRun: Int
    ) -> Bool {
        let assistantMessageCount = paneMessages.filter { $0.role == .assistant }.count
        return assistantMessageCount > assistantMessageCountBeforeRun || proposals.count > proposalCountBeforeRun
    }

    /// Names the surface the session is scoped to, so the pane header can say
    /// what Cosmo is looking at. Global sessions stay untitled.
    private func refreshActiveSurfaceTitle() {
        guard activeSessionSurfaceID != CosmoInlineAssistantSessionScope.globalSurfaceID,
              let snapshot = CosmoEditableSurfaceRegistry.shared
                .provider(surfaceID: activeSessionSurfaceID)?
                .editableSnapshot() else {
            activeSurfaceTitle = nil
            activeSurfaceKind = nil
            activeSurfaceEntity = nil
            return
        }
        let title = snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines)
        activeSurfaceTitle = title.isEmpty ? nil : title
        activeSurfaceKind = snapshot.kind
        activeSurfaceEntity = snapshot.surfaceID.split(separator: ":").first.map(String.init)
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
        // Review outcomes feed the session ledger — the next turn's model sees
        // "accepted 24, rejected 2" instead of guessing what the user did.
        sessionLedger = CosmoInlineSessionLedger.updated(
            sessionLedger,
            withReviewStateOf: proposals[location.proposalIndex]
        )
    }

    // MARK: - Session ledger

    /// The "## Session So Far" block for the volatile prompt layer, or nil for
    /// a fresh session.
    var sessionLedgerPromptBlock: String? {
        CosmoInlineSessionLedger.promptBlock(records: sessionLedger)
    }

    /// True when the session's latest run staged a proposal that is still
    /// (partly) unreviewed — the state signal route stickiness keys on.
    var hasRecentActionContext: Bool {
        guard let last = sessionLedger.last else { return false }
        return last.route == .action || last.hasPendingOperations
    }

    // MARK: - Auto-triggered skills

    func presentAutoSkillSuggestion(_ suggestion: CosmoInlineSkillAutoRunner.Suggestion) {
        autoSkillSuggestion = suggestion
    }

    func dismissAutoSkillSuggestion() {
        autoSkillSuggestion = nil
    }

    func acceptAutoSkillSuggestion() {
        guard let suggestion = autoSkillSuggestion else { return }
        autoSkillSuggestion = nil
        runAutoSkill(
            skillID: suggestion.skillID,
            prompt: suggestion.prompt,
            surfaceID: suggestion.surfaceID
        )
    }

    func runAutoSkill(skillID: String, prompt: String, surfaceID: String) {
        guard !isProcessing else { return }
        selectedSkillID = skillID
        selectedSkillIsExplicit = true
        submitPrompt(prompt, forSurfaceID: surfaceID)
    }

    /// Promote a successful run into a skill draft — the Studio opens prefilled.
    func promoteRunToSkill(recordID: UUID) {
        guard let record = sessionLedger.first(where: { $0.id == recordID }) else { return }
        pendingStudioSkillDraft = .draft(fromRun: record)
    }

    /// Same, addressed by the pane run (run cards know their runID).
    func promoteRun(withRunID runID: UUID) {
        guard let record = sessionLedger.last(where: { $0.runID == runID }) else { return }
        pendingStudioSkillDraft = .draft(fromRun: record)
    }

    private func appendLedgerRecord(
        runID: UUID,
        userAsk: String,
        route: CosmoInlineAssistantRoute,
        skillID: String?,
        proposalCountBeforeRun: Int,
        answerMessageCountBeforeRun: Int
    ) {
        let newProposals = proposals.count > proposalCountBeforeRun
            ? Array(proposals[proposalCountBeforeRun...])
            : []
        let answerMessages = paneMessages.filter {
            $0.role == .assistant && $0.proposalID == nil
        }
        let newAnswerText = answerMessages.count > answerMessageCountBeforeRun
            ? answerMessages.last?.content
            : nil

        var record = CosmoInlineSessionLedger.record(
            userAsk: userAsk,
            route: route,
            skillID: skillID,
            newProposals: newProposals,
            newAnswerText: newAnswerText,
            errorText: errorText
        )
        record.runID = runID
        sessionLedger.append(record)
        if sessionLedger.count > CosmoInlineSessionLedger.maxStoredRecords {
            sessionLedger.removeFirst(sessionLedger.count - CosmoInlineSessionLedger.maxStoredRecords)
        }
    }

    private func persistActiveSession() {
        sessionPersistence.save(CosmoInlineAssistantPersistedSession(
            surfaceID: activeSessionSurfaceID,
            paneMessages: paneMessages,
            proposals: proposals,
            selectedContextAtoms: selectedContextAtoms,
            selectedSkillID: selectedSkillID,
            selectedSkillIsExplicit: selectedSkillID == nil ? nil : selectedSkillIsExplicit,
            lastSubmissionRoute: lastSubmissionRoute,
            inquiryQuestionProposals: inquiryQuestionProposals,
            ledger: sessionLedger.isEmpty ? nil : sessionLedger
        ))
    }

    private func restoreSession(for surfaceID: String) {
        guard let session = sessionPersistence.load(surfaceID: surfaceID) else {
            resetSessionState()
            return
        }

        let repairedPaneMessages = CraftPaneAnswerRepair.repairedMessages(session.paneMessages)
        paneMessages = repairedPaneMessages.messages
        proposals = session.proposals
        inquiryQuestionProposals = session.inquiryQuestionProposals ?? []
        sessionLedger = session.ledger ?? []
        selectedContextAtoms = ContextSourcePolicy.filteredAtoms(session.selectedContextAtoms, query: "")
        selectedSkillID = session.selectedSkillIsExplicit == true ? session.selectedSkillID : nil
        lastSubmissionRoute = session.lastSubmissionRoute
        composerText = ""
        errorText = nil
        statusText = nil
        phase = .idle
        streamingPaneMessageID = nil
        currentRunSteps = []
        isPaneRequested = false

        if repairedPaneMessages.repaired {
            persistActiveSession()
        }
    }

    private func resetSessionState() {
        composerText = ""
        paneMessages = []
        proposals = []
        inquiryQuestionProposals = []
        sessionLedger = []
        selectedContextAtoms = []
        selectedSkillID = nil
        lastSubmissionRoute = nil
        activeSubmissionSkillID = nil
        activeSubmissionRoute = nil
        errorText = nil
        statusText = nil
        phase = .idle
        streamingPaneMessageID = nil
        currentRunSteps = []
        isPaneRequested = false
    }

    private static func isClearCommand(_ prompt: String) -> Bool {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "/clear"
    }
}
