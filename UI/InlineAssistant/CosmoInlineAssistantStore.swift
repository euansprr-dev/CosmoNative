import Combine
import Foundation

struct CosmoInlineAssistantPaneMessage: Identifiable, Equatable, Sendable {
    enum Role: Equatable, Sendable {
        case user
        case assistant
        case system
    }

    var id = UUID()
    var role: Role
    var content: String
    var createdAt = Date()
}

enum CosmoInlineAssistantPromptClassifier {
    static func route(for prompt: String) -> CosmoInlineAssistantRoute {
        let lower = prompt.lowercased()

        let explicitQuestionPrefixes = [
            "what ", "why ", "how ", "where ", "when ", "who ",
            "is ", "are ", "does ", "do ", "should ", "would ",
            "could "
        ]
        let startsLikeQuestion = explicitQuestionPrefixes.contains { lower.hasPrefix($0) }

        let actionPhrases = [
            "replace", "rewrite", "edit", "insert", "append", "organize",
            "move", "cluster", "reorder", "clean up", "turn this into",
            "change", "fix", "apply", "update", "make", "set", "fill",
            "populate", "add", "remove", "delete", "format", "draft"
        ]

        if startsLikeQuestion && !containsDirectEditRequest(lower) {
            return .answer
        }

        if actionPhrases.contains(where: { containsActionPhrase($0, in: lower) }) {
            return .action
        }
        return .answer
    }

    private static func containsDirectEditRequest(_ lower: String) -> Bool {
        [
            "can you rewrite", "could you rewrite", "please rewrite",
            "can you replace", "could you replace", "please replace",
            "can you edit", "could you edit", "please edit",
            "can you change", "could you change", "please change",
            "can you update", "could you update", "please update",
            "can you organize", "could you organize", "please organize",
            "what should i replace", "what should this replace"
        ].contains { lower.contains($0) }
    }

    private static func containsActionPhrase(_ phrase: String, in lower: String) -> Bool {
        if phrase.contains(" ") {
            return lower.contains(phrase)
        }

        let separators = CharacterSet.alphanumerics.inverted
        return lower
            .components(separatedBy: separators)
            .contains(phrase)
    }
}

enum CosmoInlineAssistantActivityLabel {
    static let maxStatusLength = 72

    static func statusText(for event: ToolActivityEvent) -> String? {
        switch event {
        case .started(_, let displayLabel, _):
            return compact(displayLabel)
        case .completed:
            return "Reviewing results"
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
        var bundles: Set<AgentToolBundle> = [.workspaceEditing]

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

        if containsAny(lower, [
            "research online", "search online", "look up", "latest", "current",
            "find stats", "statistics", "sources", "citations"
        ]) {
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
    @Published var isPaneRequested = false
    @Published var errorText: String?

    private let agentBridge: CosmoInlineAssistantAgentBridge
    private var activeSubmissionRoute: CosmoInlineAssistantRoute?

    init(agentBridge: CosmoInlineAssistantAgentBridge = .live) {
        self.agentBridge = agentBridge
    }

    func submit() async {
        let prompt = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        composerText = ""
        errorText = nil
        isProcessing = true
        statusText = "Reading current context"

        let route = CosmoInlineAssistantPromptClassifier.route(for: prompt)
        activeSubmissionRoute = route
        defer { activeSubmissionRoute = nil }

        if route == .answer {
            isPaneRequested = true
        }

        paneMessages.append(.init(role: .user, content: prompt))

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
        isPaneRequested = false
    }

    func receivePaneAnswer(
        title: String?,
        answer: String,
        route: CosmoInlineAssistantRoute? = nil
    ) {
        let effectiveRoute = route ?? activeSubmissionRoute
        guard effectiveRoute != .action else { return }

        isPaneRequested = true
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            paneMessages.append(.init(role: .system, content: title))
        }
        paneMessages.append(.init(role: .assistant, content: answer))
    }

    func requestPane() {
        isPaneRequested = true
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
        let operation = proposal.operations[location.operationIndex]
        guard operation.status == .pending else { return }

        guard let provider = registry.provider(surfaceID: proposal.surfaceID) else {
            markOperation(operationID, as: .conflicted)
            errorText = "The editable surface for this proposal is no longer available."
            return
        }

        let snapshot = provider.editableSnapshot()
        guard operation.canApply(against: snapshot) else {
            markOperation(operationID, as: .conflicted)
            errorText = "The source changed since Cosmo drafted this edit. Ask Cosmo to regenerate it."
            return
        }

        do {
            let result = try await provider.apply(operation: operation)
            markOperation(operationID, as: result.status)
            errorText = nil
        } catch {
            markOperation(operationID, as: .conflicted)
            errorText = error.localizedDescription
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
    }

    func acceptAll(proposalID: UUID) async {
        guard let proposal = proposals.first(where: { $0.id == proposalID }) else { return }
        for operation in proposal.operations where operation.status == .pending {
            await accept(operationID: operation.id)
        }
    }

    func rejectAll(proposalID: UUID) async {
        guard let proposal = proposals.first(where: { $0.id == proposalID }) else { return }
        for operation in proposal.operations where operation.status == .pending || operation.status == .conflicted {
            await reject(operationID: operation.id)
        }
    }

    func dismissPaneRequest() {
        isPaneRequested = false
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
}
