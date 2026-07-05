// CosmoOS/AI/InquiryPlacementEngine.swift
// Local placement classifier for Inquiry Workspace routing. It keeps conceptual
// questions separate from operational research tasks before anything is persisted.

import Foundation

struct InquiryPlacementEngine {
    enum OriginAction: String, Sendable {
        case deepen
        case saveNote
        case chat
        case evidenceWarning
        case findSources
        case manualAdd
        case crystallization
    }

    struct Context {
        var deepDiveTitle: String?
        var activeQuestion: Atom?
        var activeQuestionUUID: String?
        var activeBranchNodeId: String?
        var sourceTabId: String?
        var originExtractUUID: String?
        var originAction: OriginAction
        var questions: [Atom]
        var claims: [Atom]

        init(
            deepDiveTitle: String?,
            activeQuestion: Atom?,
            activeQuestionUUID: String?,
            activeBranchNodeId: String?,
            sourceTabId: String?,
            originExtractUUID: String?,
            originAction: OriginAction,
            questions: [Atom],
            claims: [Atom]
        ) {
            self.deepDiveTitle = deepDiveTitle
            self.activeQuestion = activeQuestion
            self.activeQuestionUUID = activeQuestionUUID
            self.activeBranchNodeId = activeBranchNodeId
            self.sourceTabId = sourceTabId
            self.originExtractUUID = originExtractUUID
            self.originAction = originAction
            self.questions = questions
            self.claims = claims
        }
    }

    static func route(text: String, context: Context) -> [InquiryRoutingCard] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let candidates = extractCandidates(from: trimmed)
        var cards: [InquiryRoutingCard] = []

        for candidate in candidates {
            let analysis = placement(for: candidate, fullText: trimmed, context: context)
            let card = routingCard(for: candidate, analysis: analysis, context: context)
            if !cards.contains(where: { existing in
                normalized(existing.proposedQuestion ?? existing.proposedExtractText ?? existing.title) == normalized(card.proposedQuestion ?? card.proposedExtractText ?? card.title)
                    && existing.placement?.nodeType == card.placement?.nodeType
            }) {
                cards.append(card)
            }
        }

        if let claimCard = claimCard(from: trimmed, context: context) {
            cards.append(claimCard)
        }

        if shouldWarnAboutEvidence(trimmed) {
            let warning = InquiryRoutingCard(
                kind: .sourceQualityWarning,
                title: "Source quality note",
                detail: "This is interesting but needs stronger support, replication, or counterevidence before it becomes a working belief.",
                proposedExtractText: "This claim is speculative and needs stronger sources, replication, or counterevidence.",
                proposedExtractKind: .sourceQualityNote,
                actionTitle: "Save warning",
                parentQuestionUUID: context.activeQuestionUUID,
                parentBranchNodeId: context.activeBranchNodeId,
                originExtractUUID: context.originExtractUUID,
                sourceTabId: context.sourceTabId
            )
            cards.append(warning)

            let audit = "What stronger sources support or challenge this claim?"
            let decision = InquiryPlacementDecision(
                nodeType: .evidenceQualityInvestigation,
                parentQuestionUUID: context.activeQuestionUUID,
                parentBranchNodeId: context.activeBranchNodeId,
                relationshipType: .evidenceAuditForClaim,
                confidence: .high,
                explanation: "This audits the evidence behind a claim rather than opening a new conceptual branch.",
                appearsInBranchMap: false
            )
            cards.append(
                InquiryRoutingCard(
                    kind: .evidenceAudit,
                    title: "Evidence audit",
                    detail: decision.explanation,
                    proposedQuestion: audit,
                    actionTitle: "Create evidence task",
                    parentQuestionUUID: context.activeQuestionUUID,
                    parentBranchNodeId: context.activeBranchNodeId,
                    originExtractUUID: context.originExtractUUID,
                    sourceTabId: context.sourceTabId,
                    placement: decision,
                    alternatePlacements: [
                        childDecision(for: audit, context: context, explanation: "Promote this to a child question if you want it visible in the Branch Map.")
                    ],
                    linkedClaimExtractUUID: context.claims.first?.uuid
                )
            )
        }

        return cards
    }

    static func placement(for candidate: String, fullText: String, context: Context) -> InquiryPlacementDecision {
        let lower = candidate.lowercased()

        if isSourceSearch(lower) {
            return InquiryPlacementDecision(
                nodeType: .sourceSearchTask,
                parentQuestionUUID: context.activeQuestionUUID,
                parentBranchNodeId: context.activeBranchNodeId,
                relationshipType: .sourceSearchForQuestion,
                confidence: .high,
                explanation: "This asks Cosmo to find material, so it should produce source candidates rather than become a map question.",
                appearsInBranchMap: false
            )
        }

        if isEvidenceAudit(lower) || context.originAction == .evidenceWarning {
            return InquiryPlacementDecision(
                nodeType: .evidenceQualityInvestigation,
                parentQuestionUUID: context.activeQuestionUUID,
                parentBranchNodeId: context.activeBranchNodeId,
                relationshipType: .evidenceAuditForClaim,
                confidence: .high,
                explanation: "This evaluates support, credibility, or counterevidence for a claim instead of creating a conceptual path.",
                appearsInBranchMap: false
            )
        }

        if isTermDefinition(lower) {
            return InquiryPlacementDecision(
                nodeType: .lexiconTerm,
                parentQuestionUUID: context.activeQuestionUUID,
                parentBranchNodeId: context.activeBranchNodeId,
                relationshipType: .definitionOfTerm,
                confidence: .medium,
                explanation: "This is primarily defining a term, so it should start as a lexicon entry until promoted.",
                appearsInBranchMap: false
            )
        }

        if isDeepDiveCandidate(lower, deepDiveTitle: context.deepDiveTitle) {
            return InquiryPlacementDecision(
                nodeType: .deepDiveCandidate,
                parentQuestionUUID: nil,
                parentBranchNodeId: nil,
                relationshipType: .promotedToDeepDive,
                confidence: .medium,
                explanation: "This is broad enough to contain its own questions, sources, and sessions.",
                appearsInBranchMap: false
            )
        }

        if shouldBeChild(lower: lower, fullText: fullText, context: context) {
            return childDecision(
                for: candidate,
                context: context,
                explanation: childExplanation(lower: lower, context: context)
            )
        }

        if shouldBeRoot(lower: lower, context: context) {
            return InquiryPlacementDecision(
                nodeType: .rootQuestion,
                parentQuestionUUID: nil,
                parentBranchNodeId: nil,
                relationshipType: .rootUnderTopic,
                confidence: .high,
                explanation: "This shifts to a different axis of the Deep Dive, so it belongs beside the current question.",
                appearsInBranchMap: true
            )
        }

        return InquiryPlacementDecision(
            nodeType: .rootQuestion,
            parentQuestionUUID: nil,
            parentBranchNodeId: nil,
            relationshipType: .rootUnderTopic,
            confidence: .low,
            explanation: "This could be a sibling/root question or a child of the active question; choose the destination before creating it.",
            appearsInBranchMap: true
        )
    }

    private static func routingCard(for candidate: String, analysis: InquiryPlacementDecision, context: Context) -> InquiryRoutingCard {
        let kind: InquiryRoutingCard.Kind
        let title: String
        let actionTitle: String
        let proposedExtractKind: ExtractKind?
        let proposedExtractText: String?
        let proposedQuestion: String?

        switch analysis.nodeType {
        case .rootQuestion:
            kind = .placementPreview
            title = analysis.confidence == .low ? "Where should this go?" : "Root question candidate"
            actionTitle = "Create root question"
            proposedQuestion = normalizeQuestion(candidate)
            proposedExtractKind = nil
            proposedExtractText = nil
        case .branchQuestion:
            kind = .placementPreview
            title = "Child question candidate"
            actionTitle = "Create here"
            proposedQuestion = normalizeQuestion(candidate)
            proposedExtractKind = nil
            proposedExtractText = nil
        case .sourceSearchTask:
            kind = .sourceSearchTask
            title = "Source search"
            actionTitle = "Create source task"
            proposedQuestion = normalizeQuestion(candidate)
            proposedExtractKind = nil
            proposedExtractText = nil
        case .evidenceQualityInvestigation:
            kind = .evidenceAudit
            title = "Evidence audit"
            actionTitle = "Create evidence task"
            proposedQuestion = normalizeQuestion(candidate)
            proposedExtractKind = nil
            proposedExtractText = nil
        case .lexiconTerm:
            kind = .termCandidate
            title = "Term candidate"
            actionTitle = "Save term"
            proposedQuestion = nil
            proposedExtractKind = .term
            proposedExtractText = termText(from: candidate)
        case .deepDiveCandidate:
            kind = .deepDiveCandidate
            title = "Deep Dive candidate"
            actionTitle = "Save candidate"
            proposedQuestion = nil
            proposedExtractKind = .aiInsight
            proposedExtractText = candidate
        default:
            kind = .placementPreview
            title = "Placement candidate"
            actionTitle = "Create"
            proposedQuestion = normalizeQuestion(candidate)
            proposedExtractKind = nil
            proposedExtractText = nil
        }

        return InquiryRoutingCard(
            kind: kind,
            title: title,
            detail: analysis.explanation,
            proposedQuestion: proposedQuestion,
            proposedExtractText: proposedExtractText,
            proposedExtractKind: proposedExtractKind,
            actionTitle: actionTitle,
            parentQuestionUUID: analysis.parentQuestionUUID,
            parentBranchNodeId: analysis.parentBranchNodeId,
            originExtractUUID: context.originExtractUUID,
            sourceTabId: context.sourceTabId,
            placement: analysis,
            alternatePlacements: alternates(for: candidate, primary: analysis, context: context)
        )
    }

    private static func alternates(for candidate: String, primary: InquiryPlacementDecision, context: Context) -> [InquiryPlacementDecision] {
        var decisions: [InquiryPlacementDecision] = []
        let root = InquiryPlacementDecision(
            nodeType: .rootQuestion,
            parentQuestionUUID: nil,
            parentBranchNodeId: nil,
            relationshipType: .rootUnderTopic,
            confidence: .medium,
            explanation: "Place this beside the current question under the Deep Dive.",
            appearsInBranchMap: true
        )
        let child = childDecision(for: candidate, context: context, explanation: "Place this under the active question as a narrowing follow-up.")
        let evidence = InquiryPlacementDecision(
            nodeType: .evidenceQualityInvestigation,
            parentQuestionUUID: context.activeQuestionUUID,
            parentBranchNodeId: context.activeBranchNodeId,
            relationshipType: .evidenceAuditForClaim,
            confidence: .medium,
            explanation: "Treat this as an evidence audit rather than a conceptual branch.",
            appearsInBranchMap: false
        )
        for decision in [root, child, evidence] where decision.nodeType != primary.nodeType {
            decisions.append(decision)
        }
        return decisions
    }

    private static func childDecision(for candidate: String, context: Context, explanation: String) -> InquiryPlacementDecision {
        InquiryPlacementDecision(
            nodeType: .branchQuestion,
            parentQuestionUUID: context.activeQuestionUUID,
            parentBranchNodeId: context.activeBranchNodeId,
            relationshipType: childRelationship(for: candidate),
            confidence: .high,
            explanation: explanation,
            appearsInBranchMap: true
        )
    }

    private static func childRelationship(for text: String) -> InquiryRelationshipType {
        let lower = text.lowercased()
        if lower.contains("affect") || lower.contains("effect") || lower.contains("consequence") {
            return .consequenceOf
        }
        if lower.contains("mechanism") || lower.contains("how") || lower.contains("why") {
            return .mechanismFor
        }
        if lower.contains("before") || lower.contains("prerequisite") {
            return .prerequisiteFor
        }
        return .childOf
    }

    private static func extractCandidates(from text: String) -> [String] {
        let split = text
            .components(separatedBy: CharacterSet(charactersIn: "\n;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let questions = split.filter { $0.contains("?") }
        if !questions.isEmpty { return Array(questions.prefix(3)) }

        let lower = text.lowercased()
        if isSourceSearch(lower) || isEvidenceAudit(lower) || isTermDefinition(lower) {
            return [text]
        }
        if lower.contains("breath") && (lower.contains("frequency") || lower.contains("biomagnetic") || lower.contains("energy")) {
            return ["How does breathing affect frequency and biomagnetic field?"]
        }
        if lower.contains("affect") || lower.contains("influence") || lower.contains("relate") {
            return ["How does this relationship actually work?"]
        }
        return []
    }

    private static func claimCard(from text: String, context: Context) -> InquiryRoutingCard? {
        let lower = text.lowercased()
        guard lower.contains("i think") || lower.contains("may") || lower.contains("might") || lower.contains("seems") || lower.contains("influence") || lower.contains("affect") else {
            return nil
        }
        let speculative = lower.contains("may") || lower.contains("might") || lower.contains("maybe") || lower.contains("speculative") || lower.contains("biomagnetic") || lower.contains("energy")
        let cleaned = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return InquiryRoutingCard(
            kind: .claimProposal,
            title: speculative ? "Speculative claim" : "Claim",
            detail: speculative ? "Save it as low-confidence material until evidence is attached." : "Save it to Answer Forming for this question.",
            proposedExtractText: cleaned.count <= 180 ? cleaned : String(cleaned.prefix(180)) + "...",
            proposedExtractKind: speculative ? .speculativeClaim : .claim,
            actionTitle: speculative ? "Save speculative claim" : "Save claim",
            parentQuestionUUID: context.activeQuestionUUID,
            parentBranchNodeId: context.activeBranchNodeId,
            originExtractUUID: context.originExtractUUID,
            sourceTabId: context.sourceTabId
        )
    }

    private static func shouldBeChild(lower: String, fullText: String, context: Context) -> Bool {
        if context.originAction == .deepen { return true }
        guard let activeTitle = context.activeQuestion?.title?.lowercased(), !activeTitle.isEmpty else { return false }
        if lower.contains("within") || lower.contains("example") || lower.contains("mechanism") || lower.contains("why") { return true }
        let activeTokens = significantTokens(activeTitle)
        let candidateTokens = significantTokens(lower)
        let overlap = activeTokens.intersection(candidateTokens).count
        return overlap >= 2 && !axisShift(from: activeTitle, to: lower)
    }

    private static func shouldBeRoot(lower: String, context: Context) -> Bool {
        guard let activeTitle = context.activeQuestion?.title?.lowercased() else { return true }
        if axisShift(from: activeTitle, to: lower) { return true }
        let candidateTokens = significantTokens(lower)
        let activeTokens = significantTokens(activeTitle)
        return activeTokens.intersection(candidateTokens).isEmpty && candidateTokens.count >= 4
    }

    private static func childExplanation(lower: String, context: Context) -> String {
        if context.originAction == .deepen {
            return "This came from Deepen inside the active question, so it narrows that branch."
        }
        if lower.contains("mechanism") || lower.contains("how") || lower.contains("why") {
            return "This asks for mechanism or explanation inside the active question."
        }
        return "This narrows the active question and depends on that parent context."
    }

    private static func axisShift(from active: String, to candidate: String) -> Bool {
        let axes: [[String]] = [
            ["ancient", "history", "practice", "origin", "used", "tradition"],
            ["biology", "physiology", "nervous", "hrv", "vagus", "co2", "oxygen"],
            ["physics", "frequency", "biomagnetic", "field", "energy", "emission"],
            ["spiritual", "ritual", "meditation", "qigong", "pranayama"],
            ["evidence", "source", "study", "replication", "credibility"]
        ]
        let activeAxis = axes.firstIndex { axis in axis.contains { active.contains($0) } }
        let candidateAxis = axes.firstIndex { axis in axis.contains { candidate.contains($0) } }
        if let activeAxis, let candidateAxis {
            return activeAxis != candidateAxis
        }
        return false
    }

    private static func isEvidenceAudit(_ lower: String) -> Bool {
        lower.contains("stronger source")
            || lower.contains("support or challenge")
            || lower.contains("counterevidence")
            || lower.contains("replication")
            || lower.contains("credible")
            || lower.contains("credibility")
            || lower.contains("quality")
            || lower.contains("limitations")
    }

    private static func isSourceSearch(_ lower: String) -> Bool {
        lower.hasPrefix("find ")
            || lower.contains("find sources")
            || lower.contains("source search")
            || lower.contains("look for studies")
            || lower.contains("search for")
    }

    private static func isTermDefinition(_ lower: String) -> Bool {
        if lower.contains("what does") && lower.contains("mean") { return true }
        if lower.contains("define ") { return true }
        if lower.hasPrefix("what is ") {
            let words = lower
                .replacingOccurrences(of: "?", with: "")
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
            return words.count <= 5
        }
        return false
    }

    private static func isDeepDiveCandidate(_ lower: String, deepDiveTitle: String?) -> Bool {
        let broadSignals = lower.contains("topic")
            || lower.contains("field of ")
            || lower.contains("entire")
            || lower.contains("world of")
        let weaklyRelated = deepDiveTitle.map { !lower.contains($0.lowercased()) } ?? false
        return broadSignals && weaklyRelated
    }

    private static func shouldWarnAboutEvidence(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("frequency")
            || lower.contains("biomagnetic")
            || lower.contains("energy field")
            || lower.contains("replication")
            || lower.contains("unusual")
    }

    static func normalizeQuestion(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix("?") ? trimmed : "\(trimmed)?"
    }

    static func normalized(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "&", with: "and")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func termText(from candidate: String) -> String {
        candidate
            .replacingOccurrences(of: "What does", with: "")
            .replacingOccurrences(of: "what does", with: "")
            .replacingOccurrences(of: "mean?", with: "")
            .replacingOccurrences(of: "mean", with: "")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "?")))
    }

    private static func significantTokens(_ text: String) -> Set<String> {
        let stop: Set<String> = ["what", "does", "how", "why", "are", "the", "and", "or", "this", "that", "with", "from", "about", "into", "affect"]
        let tokens = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 && !stop.contains($0) }
        return Set(tokens)
    }
}

enum InquiryDockRouteIntent: String, Sendable, Equatable {
    case ask
    case note
    case question
    case rootQuestion
    case branchQuestion
    case claim
    case speculativeClaim
    case evidence
    case counterevidence
    case source
    case deepScout
    case openSource
    case term
    case practice
    case output
    case challenge
    case summarize
    case refreshSources
    case goal
    case problem
    case benefit
    case example
    case mechanism
    case objection
    case principle
    case assumption
    case quote
    case reference
}

struct InquiryDockParseResult: Sendable, Equatable {
    var intent: InquiryDockRouteIntent
    var body: String
    var targetBranch: String?

    var extractKind: ExtractKind? {
        switch intent {
        case .note: return .note
        case .claim: return .claim
        case .speculativeClaim: return .speculativeClaim
        case .evidence: return .evidence
        case .counterevidence: return .counterevidence
        case .term: return .term
        case .practice: return .practice
        case .output: return .outputIdea
        case .goal: return .goal
        case .problem: return .problem
        case .benefit: return .benefit
        case .example: return .example
        case .mechanism: return .mechanism
        case .objection: return .objection
        case .principle: return .principle
        case .assumption: return .assumption
        case .quote: return .quote
        case .reference: return .reference
        default: return nil
        }
    }
}

struct InquiryDockPrefixParser {
    static func parse(_ raw: String) -> InquiryDockParseResult {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if lower == "/sources" {
            return InquiryDockParseResult(intent: .refreshSources, body: "")
        }
        if lower.hasPrefix("/sources ") {
            return InquiryDockParseResult(intent: .refreshSources, body: strippedCommandBody(trimmed))
        }
        if lower == "/scout" {
            return InquiryDockParseResult(intent: .deepScout, body: "")
        }
        if lower.hasPrefix("/scout ") {
            return InquiryDockParseResult(intent: .deepScout, body: strippedCommandBody(trimmed))
        }
        if lower == "/challenge" || lower.hasPrefix("/challenge ") {
            return InquiryDockParseResult(intent: .challenge, body: strippedCommandBody(trimmed))
        }
        if lower == "/summarize" || lower.hasPrefix("/summarize ") {
            return InquiryDockParseResult(intent: .summarize, body: strippedCommandBody(trimmed))
        }
        if let target = branchTarget(in: trimmed) {
            let body = trimmed.replacingOccurrences(of: "@branch \(target)", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return InquiryDockParseResult(intent: .note, body: body, targetBranch: target)
        }
        if looksLikeURL(trimmed) {
            return InquiryDockParseResult(intent: .openSource, body: trimmed)
        }

        let prefixes: [(String, InquiryDockRouteIntent)] = [
            ("root:", .rootQuestion),
            ("branch:", .branchQuestion),
            ("claim:", .claim),
            ("maybe:", .speculativeClaim),
            ("evidence:", .evidence),
            ("counter:", .counterevidence),
            ("scout:", .deepScout),
            ("source:", .source),
            ("term:", .term),
            ("concept:", .term),
            ("practice:", .practice),
            ("output:", .output),
            ("note:", .note),
            ("goal:", .goal),
            ("problem:", .problem),
            ("benefit:", .benefit),
            ("example:", .example),
            ("mechanism:", .mechanism),
            ("objection:", .objection),
            ("principle:", .principle),
            ("assumption:", .assumption),
            ("quote:", .quote),
            ("reference:", .reference),
            ("ref:", .reference),
            ("q:", .question)
        ]

        for (prefix, intent) in prefixes where lower.hasPrefix(prefix) {
            return InquiryDockParseResult(
                intent: intent,
                body: String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return InquiryDockParseResult(intent: .ask, body: trimmed)
    }

    private static func strippedCommandBody(_ text: String) -> String {
        guard let firstSpace = text.firstIndex(where: { $0.isWhitespace }) else { return "" }
        return String(text[text.index(after: firstSpace)...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func branchTarget(in text: String) -> String? {
        guard let range = text.range(of: "@branch ", options: [.caseInsensitive]) else { return nil }
        let suffix = text[range.upperBound...]
        let parts = suffix.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        return parts.first.map(String.init)
    }

    static func looksLikeURL(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.hasPrefix("http://")
            || lower.hasPrefix("https://")
            || lower.hasPrefix("www.")
    }
}

struct InquiryBranchResearchProfile: Sendable, Equatable {
    var deepDiveTitle: String?
    var activeQuestionTitle: String
    var activeQuestionUUID: String?
    var branchNodeId: String
    var ancestorTitles: [String]
    var claims: [String]
    var evidence: [String]
    var sourceQuery: String? = nil
    /// Domain anchor terms derived from the deep dive title, aliases, and lexicon —
    /// replaces hardcoded topic keywords in ranking and topic gating.
    var anchorTerms: Set<String> = []

    var query: String {
        var rawPieces: [String] = []
        if let sourceQuery {
            rawPieces.append(sourceQuery)
        }
        if let deepDiveTitle { rawPieces.append(deepDiveTitle) }
        rawPieces.append(activeQuestionTitle)
        rawPieces.append(contentsOf: ancestorTitles)
        if sourceQuery == nil {
            rawPieces.append(contentsOf: claims.prefix(3))
        }
        let pieces = rawPieces
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return pieces.joined(separator: " ")
    }

    var tokens: Set<String> {
        var rawPieces: [String] = []
        if let deepDiveTitle { rawPieces.append(deepDiveTitle) }
        rawPieces.append(activeQuestionTitle)
        if let sourceQuery { rawPieces.append(sourceQuery) }
        rawPieces.append(contentsOf: ancestorTitles)
        rawPieces.append(contentsOf: claims)
        rawPieces.append(contentsOf: evidence)
        return InquirySourceRecommendationEngine.significantTokens(rawPieces.joined(separator: " "))
    }
}

final class InquirySourceRecommendationEngine: @unchecked Sendable {
    static let shared = InquirySourceRecommendationEngine()

    func recommend(
        profile: InquiryBranchResearchProfile,
        existingSourceRefs: [InquirySourceRef],
        localSources: [Atom],
        searchMode: InquirySourceSearchMode = .quick,
        onProgress: (@MainActor (InquiryProviderStatus) -> Void)? = nil
    ) async -> InquiryRecommendationBatch {
        let localCandidates = Self.localCandidates(from: localSources, profile: profile)

        // The LLM planner writes human-quality, creator-aware queries; the
        // keyword templates are only the offline fallback.
        let taste = await DeepScoutTasteStore.shared.profile()
        let deepScoutPlan: DeepScoutPlan
        if searchMode == .deepScout,
           let llmPlan = await DeepScoutLLMPlanner.shared.plan(for: profile, taste: taste) {
            deepScoutPlan = llmPlan
        } else {
            deepScoutPlan = DeepScoutIntentPlanner.plan(for: profile, mode: searchMode)
        }
        let queries = searchMode == .deepScout ? deepScoutPlan.queries.map(\.query) : [profile.query]
        let academicQueries: [String]
        if searchMode == .deepScout {
            academicQueries = Array(
                deepScoutPlan.queries
                    .filter { !$0.providers.filter(Self.isAcademicProvider).isEmpty }
                    .map(\.query)
                    .prefix(4)
            )
        } else {
            academicQueries = Array(queries.prefix(1))
        }

        @Sendable func report(_ status: InquiryProviderStatus) async {
            guard let onProgress else { return }
            await MainActor.run { onProgress(status) }
        }
        @Sendable func tracked(
            _ fetch: @escaping () async -> (InquiryProviderStatus, [InquirySourceCandidate])
        ) async -> (InquiryProviderStatus, [InquirySourceCandidate]) {
            let result = await fetch()
            await report(result.0)
            return result
        }

        var rawCandidates = localCandidates
        var statuses = [InquiryProviderStatus(provider: .local, state: .succeeded, count: localCandidates.count)]
        await report(statuses[0])

        if searchMode == .deepScout {
            // All providers fan out concurrently; each reports its status as it lands.
            async let openAlex = tracked { await Self.fetchOpenAlexAcross(queries: academicQueries, profile: profile) }
            async let crossref = tracked { await Self.fetchCrossrefAcross(queries: academicQueries, profile: profile) }
            async let semantic = tracked { await Self.fetchSemanticScholarAcross(queries: academicQueries, profile: profile) }
            async let pubMed = tracked { await Self.fetchEuropePMCAcross(queries: academicQueries, profile: profile) }
            async let googleBooks = tracked { await Self.fetchPlannedProvider(.googleBooks, plan: deepScoutPlan, profile: profile) }
            async let openLibrary = tracked { await Self.fetchPlannedProvider(.openLibrary, plan: deepScoutPlan, profile: profile) }
            async let archive = tracked { await Self.fetchPlannedProvider(.internetArchive, plan: deepScoutPlan, profile: profile) }
            async let youtube = tracked { await Self.fetchPlannedProvider(.youtube, plan: deepScoutPlan, profile: profile) }
            async let podcasts = tracked { await Self.fetchPlannedProvider(.podcast, plan: deepScoutPlan, profile: profile) }
            async let web = tracked { await Self.fetchWebResearch(query: profile.query, profile: profile) }

            let results = await [openAlex, crossref, semantic, pubMed, googleBooks, openLibrary, archive, youtube, podcasts, web]
            for (status, candidates) in results {
                rawCandidates.append(contentsOf: candidates)
                statuses.append(status)
            }
            rawCandidates = Self.applyDeepScoutMetadata(rawCandidates, plan: deepScoutPlan)
        } else {
            async let openAlex = tracked { await Self.fetchOpenAlexAcross(queries: academicQueries, profile: profile) }
            async let crossref = tracked { await Self.fetchCrossrefAcross(queries: academicQueries, profile: profile) }
            let results = await [openAlex, crossref]
            for (status, candidates) in results {
                rawCandidates.append(contentsOf: candidates)
                statuses.append(status)
            }
        }

        let merged = Self.mergeCandidates(rawCandidates)
        var ranked = searchMode == .deepScout
            ? DeepScoutRanker.rank(
                merged,
                profile: profile,
                plan: deepScoutPlan,
                existingSourceRefs: existingSourceRefs,
                limit: DeepScoutLLMRanker.maxCandidates
            )
            : Self.rankCandidates(merged, profile: profile, existingSourceRefs: existingSourceRefs)
        if searchMode == .deepScout {
            // One judging call reads the survivors against the actual question;
            // learned creator taste applies even when the judge is offline.
            let judgments = await DeepScoutLLMRanker.shared.judge(
                candidates: ranked,
                profile: profile,
                intent: deepScoutPlan.intent,
                taste: taste
            )
            ranked = DeepScoutRanker.blend(ranked, judgments: judgments, taste: taste)
        }

        statuses = statuses.map { status in
            var copy = status
            copy.count = ranked.filter { $0.provider == status.provider }.count
            return copy
        }
        statuses = statuses.sorted { $0.provider.displayName < $1.provider.displayName }

        return InquiryRecommendationBatch(
            questionUUID: profile.activeQuestionUUID,
            branchNodeId: profile.branchNodeId,
            query: profile.query,
            searchMode: searchMode,
            providerStatuses: statuses,
            scoutSteps: Self.scoutSteps(for: searchMode, queryCount: queries.count, candidateCount: rawCandidates.count, rankedCount: ranked.count),
            candidates: Array(ranked.prefix(20))
        )
    }

    static func scoutQueries(for profile: InquiryBranchResearchProfile) -> [String] {
        DeepScoutIntentPlanner.plan(for: profile, mode: .deepScout).queries.map(\.query)
    }

    static func activityPlan(
        for profile: InquiryBranchResearchProfile,
        mode: InquirySourceSearchMode
    ) -> [String] {
        let subject = clippedActivitySubject(profile.sourceQuery ?? profile.activeQuestionTitle)
        switch mode {
        case .quick:
            return [
                "Searching your library for \(subject)",
                "Searching OpenAlex for branch-matched papers",
                "Checking Crossref for publisher-indexed sources",
                "Filtering off-topic results",
                "Ranking the strongest candidates"
            ]
        case .deepScout:
            return [
                "Expanding \(subject) into intent-aware source lanes",
                "Searching your local library",
                "Searching books, primary texts, and archive material",
                "Searching OpenAlex and Crossref for scholarly context",
                "Checking Semantic Scholar and PubMed only where the intent calls for it",
                "Looking for relevant YouTube lectures",
                "Running web research for sources outside academic APIs",
                "Filtering off-topic and clinically drifted results",
                "Ranking with lane diversity for this branch"
            ]
        }
    }

    private static func clippedActivitySubject(_ raw: String) -> String {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "this branch" }
        guard cleaned.count > 54 else { return cleaned }
        return "\(cleaned.prefix(51))..."
    }

    static func rankCandidates(
        _ candidates: [InquirySourceCandidate],
        profile: InquiryBranchResearchProfile,
        existingSourceRefs: [InquirySourceRef]
    ) -> [InquirySourceCandidate] {
        if candidates.contains(where: { $0.sourceLane != nil || $0.researchIntent != nil }) {
            let plan = DeepScoutIntentPlanner.plan(for: profile, mode: .deepScout)
            return DeepScoutRanker.rank(candidates, profile: profile, plan: plan, existingSourceRefs: existingSourceRefs)
        }

        return candidates
            .compactMap { candidate -> InquirySourceCandidate? in
                var copy = candidate
                let text = candidateText(for: candidate)
                let anchorGate = relevanceGate(candidateText: text, profile: profile)
                guard anchorGate.passed else { return nil }

                let candidateTokens = significantTokens(text)
                let matchedTokens = Array(candidateTokens.intersection(profile.tokens)).sorted()
                let overlap = Double(matchedTokens.count)
                let overlapScore = min(0.36, overlap * 0.06)
                let anchorScore = min(0.22, Double(anchorGate.matches.count) * 0.09)
                let providerBoost = providerBoost(for: candidate.provider)
                let roleBoost = roleBoost(for: candidate.evidenceRole)
                let kindBoost = kindBoost(for: candidate.sourceKind)
                let qualityBoost = qualityBoost(for: candidate)
                let recencyBoost = recencyBoost(for: candidate.publishedDate)
                let importedPenalty = alreadyImported(candidate, existingSourceRefs: existingSourceRefs) ? -0.18 : 0
                copy.importStatus = alreadyImported(candidate, existingSourceRefs: existingSourceRefs) ? .imported : candidate.importStatus
                copy.score = max(0.05, min(0.99, 0.16 + overlapScore + anchorScore + providerBoost + roleBoost + kindBoost + qualityBoost + recencyBoost + importedPenalty))
                if candidate.reason.isEmpty || isGenericProviderReason(candidate.reason) {
                    copy.reason = reason(for: copy, matchedTokens: matchedTokens, anchorMatches: anchorGate.matches)
                }
                return copy
            }
            .sorted {
                if $0.score == $1.score {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.score > $1.score
            }
    }

    static func significantTokens(_ text: String) -> Set<String> {
        let stop: Set<String> = [
            "what", "does", "from", "with", "have", "this", "that", "into", "about", "after",
            "before", "while", "where", "when", "which", "there", "their", "would", "could",
            "should", "study", "paper", "research", "source", "effect", "effects", "body"
        ]
        let tokens = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 && !stop.contains($0) }
        return Set(tokens)
    }

    private static func candidateText(for candidate: InquirySourceCandidate) -> String {
        [
            candidate.title,
            candidate.subtitle,
            candidate.abstract,
            candidate.authors.joined(separator: " "),
            candidate.qualitySignals.joined(separator: " ")
        ].compactMap { $0 }.joined(separator: " ")
    }

    private static func relevanceGate(
        candidateText: String,
        profile: InquiryBranchResearchProfile
    ) -> (passed: Bool, matches: [String]) {
        let lower = candidateText.lowercased()
        let anchors = anchorTerms(for: profile)
        let requiredAnchors = requiredAnchorTerms(for: profile)
        if !requiredAnchors.isEmpty {
            let requiredMatches = requiredAnchors.filter { anchor in
                containsAnchor(anchor, in: lower)
            }
            guard !requiredMatches.isEmpty else { return (false, []) }
            let optionalMatches = anchors.filter { anchor in
                containsAnchor(anchor, in: lower)
            }
            return (true, Array(Set(requiredMatches + optionalMatches)).sorted())
        }
        guard !anchors.isEmpty else {
            return (!significantTokens(candidateText).intersection(profile.tokens).isEmpty, [])
        }
        let matches = anchors.filter { anchor in
            containsAnchor(anchor, in: lower)
        }
        return (!matches.isEmpty, matches)
    }

    private static func anchorTerms(for profile: InquiryBranchResearchProfile) -> [String] {
        let raw = [
            profile.deepDiveTitle,
            profile.activeQuestionTitle,
            profile.sourceQuery,
            profile.ancestorTitles.joined(separator: " ")
        ].compactMap { $0 }.joined(separator: " ").lowercased()

        var anchors: Set<String> = []
        if rawRequiresBreathAnchor(raw) {
            anchors.formUnion(breathAnchorTerms)
        }

        for token in significantTokens(raw) where !genericAnchorTokens.contains(token) {
            anchors.insert(token)
        }

        return anchors.sorted {
            if $0.count == $1.count { return $0 < $1 }
            return $0.count > $1.count
        }
    }

    private static func requiredAnchorTerms(for profile: InquiryBranchResearchProfile) -> [String] {
        let raw = [
            profile.deepDiveTitle,
            profile.activeQuestionTitle,
            profile.sourceQuery,
            profile.ancestorTitles.joined(separator: " ")
        ].compactMap { $0 }.joined(separator: " ").lowercased()

        guard rawRequiresBreathAnchor(raw) else { return [] }
        return Array(breathAnchorTerms).sorted {
            if $0.count == $1.count { return $0 < $1 }
            return $0.count > $1.count
        }
    }

    private static func rawRequiresBreathAnchor(_ raw: String) -> Bool {
        raw.contains("breath") || raw.contains("respirat") || raw.contains("pranayama") || raw.contains("co2") || raw.contains("carbon dioxide")
    }

    private static var breathAnchorTerms: Set<String> {
        [
            "breathwork",
            "breath work",
            "breathing",
            "breathing exercise",
            "breathing exercises",
            "breath exercise",
            "breath training",
            "paced breathing",
            "slow breathing",
            "diaphragmatic breathing",
            "controlled breathing",
            "voluntary breathing",
            "pranayama",
            "respiration",
            "respiratory",
            "ventilation",
            "hyperventilation",
            "hypoventilation",
            "carbon dioxide",
            "co2"
        ]
    }

    private static var genericAnchorTokens: Set<String> {
        [
            "affect", "affects", "affected", "answer", "answers", "branch", "branches",
            "main", "question", "questions", "within", "under", "source", "sources",
            "find", "best", "strong", "stronger", "evidence", "study", "studies",
            "review", "paper", "papers"
        ]
    }

    private static func containsAnchor(_ anchor: String, in lowerText: String) -> Bool {
        if anchor.contains(" ") {
            return lowerText.contains(anchor)
        }
        let pattern = #"(?<![a-z0-9])\#(NSRegularExpression.escapedPattern(for: anchor))(s|es|ed|ing)?(?![a-z0-9])"#
        return lowerText.range(of: pattern, options: .regularExpression) != nil
    }

    private static func isGenericProviderReason(_ reason: String) -> Bool {
        reason == "Academic match for this branch from OpenAlex."
            || reason == "Publisher-indexed source that may answer this branch."
            || reason.hasPrefix("Deep Scout")
    }

    private static func localCandidates(from atoms: [Atom], profile: InquiryBranchResearchProfile) -> [InquirySourceCandidate] {
        atoms.compactMap { atom in
            let title = atom.title ?? atom.url ?? "Untitled source"
            let summary = atom.researchMetadata?.summary ?? atom.body
            let findings = atom.researchMetadata?.findings
            let searchable = [title, summary, findings, atom.researchMetadata?.personalNotes].compactMap { $0 }.joined(separator: " ")
            let matches = significantTokens(searchable).intersection(profile.tokens)
            guard !matches.isEmpty else { return nil }

            let kind = inferKind(title: title, url: atom.url, type: atom.researchType, body: searchable, local: true)
            return InquirySourceCandidate(
                id: "local-\(atom.uuid)",
                provider: .local,
                sourceKind: kind,
                title: title,
                subtitle: atom.url,
                authors: [],
                publishedDate: atom.createdAt,
                url: atom.url,
                abstract: summary,
                evidenceRole: .localLibrary,
                reason: "Already in your library and overlaps with \(Array(matches).sorted().prefix(3).joined(separator: ", ")).",
                qualitySignals: ["Local library", atom.processingStatus ?? "Saved"],
                branchQuestionUUID: profile.activeQuestionUUID,
                branchNodeId: profile.branchNodeId,
                importedSourceUUID: atom.uuid,
                importStatus: .imported
            )
        }
    }

    private static func fetchOpenAlexAcross(
        queries: [String],
        profile: InquiryBranchResearchProfile
    ) async -> (InquiryProviderStatus, [InquirySourceCandidate]) {
        var statuses: [InquiryProviderStatus] = []
        var candidates: [InquirySourceCandidate] = []
        for query in queries {
            let (status, queryCandidates) = await fetchOpenAlex(query: query, profile: profile)
            statuses.append(status)
            candidates.append(contentsOf: queryCandidates)
        }
        return (rollupStatus(provider: .openAlex, statuses: statuses, candidateCount: candidates.count), candidates)
    }

    private static func fetchCrossrefAcross(
        queries: [String],
        profile: InquiryBranchResearchProfile
    ) async -> (InquiryProviderStatus, [InquirySourceCandidate]) {
        var statuses: [InquiryProviderStatus] = []
        var candidates: [InquirySourceCandidate] = []
        for query in queries {
            let (status, queryCandidates) = await fetchCrossref(query: query, profile: profile)
            statuses.append(status)
            candidates.append(contentsOf: queryCandidates)
        }
        return (rollupStatus(provider: .crossref, statuses: statuses, candidateCount: candidates.count), candidates)
    }

    private static func fetchSemanticScholarAcross(
        queries: [String],
        profile: InquiryBranchResearchProfile
    ) async -> (InquiryProviderStatus, [InquirySourceCandidate]) {
        var statuses: [InquiryProviderStatus] = []
        var candidates: [InquirySourceCandidate] = []
        for query in queries.prefix(3) {
            let (status, queryCandidates) = await fetchSemanticScholar(query: query, profile: profile)
            statuses.append(status)
            candidates.append(contentsOf: queryCandidates)
        }
        return (rollupStatus(provider: .semanticScholar, statuses: statuses, candidateCount: candidates.count), candidates)
    }

    private static func fetchEuropePMCAcross(
        queries: [String],
        profile: InquiryBranchResearchProfile
    ) async -> (InquiryProviderStatus, [InquirySourceCandidate]) {
        var statuses: [InquiryProviderStatus] = []
        var candidates: [InquirySourceCandidate] = []
        for query in queries.prefix(3) {
            let (status, queryCandidates) = await fetchEuropePMC(query: query, profile: profile)
            statuses.append(status)
            candidates.append(contentsOf: queryCandidates)
        }
        return (rollupStatus(provider: .pubMed, statuses: statuses, candidateCount: candidates.count), candidates)
    }

    private static func fetchPlannedProvider(
        _ provider: InquirySourceProvider,
        plan: DeepScoutPlan,
        profile: InquiryBranchResearchProfile
    ) async -> (InquiryProviderStatus, [InquirySourceCandidate]) {
        var statuses: [InquiryProviderStatus] = []
        var candidates: [InquirySourceCandidate] = []

        for query in plan.queries where query.providers.contains(provider) {
            let result: (InquiryProviderStatus, [InquirySourceCandidate])
            switch provider {
            case .googleBooks:
                result = await DeepScoutProviders.fetchGoogleBooks(
                    query: query.query,
                    lane: query.lane,
                    intent: plan.intent,
                    profile: profile
                )
            case .openLibrary:
                result = await DeepScoutProviders.fetchOpenLibrary(
                    query: query.query,
                    lane: query.lane,
                    intent: plan.intent,
                    profile: profile
                )
            case .internetArchive:
                result = await DeepScoutProviders.fetchInternetArchive(
                    query: query.query,
                    lane: query.lane,
                    intent: plan.intent,
                    profile: profile
                )
            case .youtube:
                result = await DeepScoutProviders.fetchYouTube(
                    query: query.query,
                    lane: query.lane,
                    intent: plan.intent,
                    profile: profile
                )
            case .podcast:
                result = await DeepScoutProviders.fetchPodcasts(
                    query: query.query,
                    lane: query.lane,
                    intent: plan.intent,
                    profile: profile
                )
            default:
                result = (InquiryProviderStatus(provider: provider, state: .idle, count: 0), [])
            }
            statuses.append(result.0)
            candidates.append(contentsOf: result.1)
        }

        return (rollupStatus(provider: provider, statuses: statuses, candidateCount: candidates.count), candidates)
    }

    private static func rollupStatus(
        provider: InquirySourceProvider,
        statuses: [InquiryProviderStatus],
        candidateCount: Int
    ) -> InquiryProviderStatus {
        if statuses.contains(where: { $0.state == .succeeded }) {
            return InquiryProviderStatus(provider: provider, state: .succeeded, count: candidateCount)
        }
        if let first = statuses.first {
            return InquiryProviderStatus(provider: provider, state: first.state, message: first.message, count: candidateCount)
        }
        return InquiryProviderStatus(provider: provider, state: .idle, count: candidateCount)
    }

    private static func isAcademicProvider(_ provider: InquirySourceProvider) -> Bool {
        switch provider {
        case .openAlex, .crossref, .semanticScholar, .pubMed, .arxiv:
            return true
        case .local, .youtube, .podcast, .web, .googleBooks, .openLibrary, .internetArchive:
            return false
        }
    }

    private static func applyDeepScoutMetadata(
        _ candidates: [InquirySourceCandidate],
        plan: DeepScoutPlan
    ) -> [InquirySourceCandidate] {
        candidates.map { candidate in
            var copy = candidate
            copy.researchIntent = copy.researchIntent ?? plan.intent
            copy.sourceLane = copy.sourceLane ?? defaultLane(for: copy, intent: plan.intent)
            return copy
        }
    }

    private static func defaultLane(
        for candidate: InquirySourceCandidate,
        intent: InquiryResearchIntent
    ) -> InquirySourceLane {
        switch candidate.provider {
        case .local:
            return .localLibrary
        case .googleBooks, .openLibrary, .internetArchive:
            return candidate.evidenceRole == .primaryText ? .primaryText : .deepRead
        case .youtube, .podcast:
            return .teacherLecture
        case .pubMed:
            return .clinicalEvidence
        case .openAlex, .crossref, .semanticScholar, .arxiv:
            return intent == .clinicalEvidence || intent == .mechanismScience ? .clinicalEvidence : .scholarlyContext
        case .web:
            return .webResource
        }
    }

    private static func scoutSteps(
        for mode: InquirySourceSearchMode,
        queryCount: Int,
        candidateCount: Int,
        rankedCount: Int
    ) -> [String] {
        guard mode == .deepScout else { return [] }
        return [
            "Expanded into \(queryCount) intent-aware source lanes",
            "Searched books, primary texts, lectures, scholarly indexes, web, and local library",
            "Screened \(candidateCount) raw hits for topic fit",
            "Ranked \(rankedCount) candidates by intent fit, lane diversity, and source quality"
        ]
    }

    private static func fetchOpenAlex(
        query: String,
        profile: InquiryBranchResearchProfile
    ) async -> (InquiryProviderStatus, [InquirySourceCandidate]) {
        guard let url = searchURL(base: "https://api.openalex.org/works", queryItems: [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "per-page", value: "8"),
            URLQueryItem(name: "sort", value: "relevance_score:desc")
        ]) else {
            return (InquiryProviderStatus(provider: .openAlex, state: .failed, message: "Invalid query"), [])
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let results = object?["results"] as? [[String: Any]] ?? []
            let candidates = results.compactMap { item -> InquirySourceCandidate? in
                let title = (item["display_name"] as? String) ?? (item["title"] as? String)
                guard let title, !title.isEmpty else { return nil }
                let authorships = item["authorships"] as? [[String: Any]] ?? []
                let authors = authorships.compactMap { authorship -> String? in
                    let author = authorship["author"] as? [String: Any]
                    return author?["display_name"] as? String
                }
                let ids = item["ids"] as? [String: Any]
                let doi = (ids?["doi"] as? String) ?? (item["doi"] as? String)
                let location = item["primary_location"] as? [String: Any]
                let landingURL = location?["landing_page_url"] as? String
                let openAccess = item["open_access"] as? [String: Any]
                let url = (openAccess?["oa_url"] as? String) ?? landingURL ?? doi
                let year = (item["publication_year"] as? Int).map(String.init)
                let type = item["type"] as? String
                let citedBy = item["cited_by_count"] as? Int
                let abstract = abstractText(fromOpenAlex: item["abstract_inverted_index"] as? [String: [Int]])
                let kind = inferKind(title: title, url: url, type: type, body: abstract ?? "", local: false)
                let role = evidenceRole(for: kind, title: title, body: abstract ?? "", year: year)
                let signals = [
                    year.map { "Published \($0)" },
                    citedBy.map { "\($0) citations" },
                    doi == nil ? nil : "DOI"
                ].compactMap { $0 }
                return InquirySourceCandidate(
                    id: stableID(provider: .openAlex, key: doi ?? url ?? title),
                    provider: .openAlex,
                    sourceKind: kind,
                    title: title,
                    authors: authors,
                    publishedDate: year,
                    url: url,
                    doi: doi,
                    abstract: abstract,
                    evidenceRole: role,
                    reason: "Academic match for this branch from OpenAlex.",
                    qualitySignals: signals,
                    branchQuestionUUID: profile.activeQuestionUUID,
                    branchNodeId: profile.branchNodeId
                )
            }
            return (InquiryProviderStatus(provider: .openAlex, state: .succeeded, count: candidates.count), candidates)
        } catch {
            return (InquiryProviderStatus(provider: .openAlex, state: .failed, message: error.localizedDescription), [])
        }
    }

    private static func fetchCrossref(
        query: String,
        profile: InquiryBranchResearchProfile
    ) async -> (InquiryProviderStatus, [InquirySourceCandidate]) {
        guard let url = searchURL(base: "https://api.crossref.org/works", queryItems: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "rows", value: "8")
        ]) else {
            return (InquiryProviderStatus(provider: .crossref, state: .failed, message: "Invalid query"), [])
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = object?["message"] as? [String: Any]
            let items = message?["items"] as? [[String: Any]] ?? []
            let candidates = items.compactMap { item -> InquirySourceCandidate? in
                let titles = item["title"] as? [String]
                guard let title = titles?.first, !title.isEmpty else { return nil }
                let subtitles = item["subtitle"] as? [String]
                let authors = (item["author"] as? [[String: Any]] ?? []).compactMap { author -> String? in
                    let given = author["given"] as? String
                    let family = author["family"] as? String
                    return [given, family].compactMap { $0 }.joined(separator: " ").nilIfEmpty
                }
                let doi = item["DOI"] as? String
                let url = (item["URL"] as? String) ?? doi.map { "https://doi.org/\($0)" }
                let year = crossrefYear(from: item)
                let type = item["type"] as? String
                let subject = (item["subject"] as? [String])?.prefix(2).joined(separator: ", ")
                let kind = inferKind(title: title, url: url, type: type, body: subject ?? "", local: false)
                let role = evidenceRole(for: kind, title: title, body: subject ?? "", year: year)
                let signals = [
                    year.map { "Published \($0)" },
                    doi == nil ? nil : "DOI",
                    subject
                ].compactMap { $0 }
                return InquirySourceCandidate(
                    id: stableID(provider: .crossref, key: doi ?? url ?? title),
                    provider: .crossref,
                    sourceKind: kind,
                    title: title,
                    subtitle: subtitles?.first,
                    authors: authors,
                    publishedDate: year,
                    url: url,
                    doi: doi,
                    evidenceRole: role,
                    reason: "Publisher-indexed source that may answer this branch.",
                    qualitySignals: signals,
                    branchQuestionUUID: profile.activeQuestionUUID,
                    branchNodeId: profile.branchNodeId
                )
            }
            return (InquiryProviderStatus(provider: .crossref, state: .succeeded, count: candidates.count), candidates)
        } catch {
            return (InquiryProviderStatus(provider: .crossref, state: .failed, message: error.localizedDescription), [])
        }
    }

    private static func fetchSemanticScholar(
        query: String,
        profile: InquiryBranchResearchProfile
    ) async -> (InquiryProviderStatus, [InquirySourceCandidate]) {
        guard let url = searchURL(base: "https://api.semanticscholar.org/graph/v1/paper/search", queryItems: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: "8"),
            URLQueryItem(name: "fields", value: "title,abstract,year,url,citationCount,authors,externalIds,publicationTypes,venue")
        ]) else {
            return (InquiryProviderStatus(provider: .semanticScholar, state: .failed, message: "Invalid query"), [])
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode == 429 {
                return (InquiryProviderStatus(provider: .semanticScholar, state: .rateLimited, message: "Semantic Scholar rate limited Deep Scout"), [])
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return (InquiryProviderStatus(provider: .semanticScholar, state: .failed, message: "Invalid response"), [])
            }
            let results = object["data"] as? [[String: Any]] ?? []
            let candidates = results.compactMap { item -> InquirySourceCandidate? in
                guard let title = item["title"] as? String, !title.isEmpty else { return nil }
                let abstract = item["abstract"] as? String
                let year = (item["year"] as? Int).map(String.init)
                let url = item["url"] as? String
                let citationCount = item["citationCount"] as? Int
                let authors = (item["authors"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
                let externalIds = item["externalIds"] as? [String: Any]
                let doi = externalIds?["DOI"] as? String
                let publicationTypes = (item["publicationTypes"] as? [String])?.joined(separator: ", ")
                let venue = item["venue"] as? String
                let kind = inferKind(title: title, url: url, type: publicationTypes, body: abstract ?? "", local: false)
                let role = evidenceRole(for: kind, title: title, body: abstract ?? "", year: year)
                let signals = [
                    year.map { "Published \($0)" },
                    citationCount.map { "\($0) citations" },
                    doi == nil ? nil : "DOI",
                    venue
                ].compactMap { $0 }
                return InquirySourceCandidate(
                    id: stableID(provider: .semanticScholar, key: doi ?? url ?? title),
                    provider: .semanticScholar,
                    sourceKind: kind,
                    title: title,
                    authors: authors,
                    publishedDate: year,
                    url: url ?? doi.map { "https://doi.org/\($0)" },
                    doi: doi,
                    abstract: abstract,
                    evidenceRole: role,
                    reason: "Deep Scout academic candidate from Semantic Scholar.",
                    qualitySignals: signals,
                    branchQuestionUUID: profile.activeQuestionUUID,
                    branchNodeId: profile.branchNodeId
                )
            }
            return (InquiryProviderStatus(provider: .semanticScholar, state: .succeeded, count: candidates.count), candidates)
        } catch {
            return (InquiryProviderStatus(provider: .semanticScholar, state: .failed, message: error.localizedDescription), [])
        }
    }

    private static func fetchEuropePMC(
        query: String,
        profile: InquiryBranchResearchProfile
    ) async -> (InquiryProviderStatus, [InquirySourceCandidate]) {
        guard let url = searchURL(base: "https://www.ebi.ac.uk/europepmc/webservices/rest/search", queryItems: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "pageSize", value: "8"),
            URLQueryItem(name: "sort", value: "RELEVANCE")
        ]) else {
            return (InquiryProviderStatus(provider: .pubMed, state: .failed, message: "Invalid query"), [])
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let resultList = object?["resultList"] as? [String: Any]
            let results = resultList?["result"] as? [[String: Any]] ?? []
            let candidates = results.compactMap { item -> InquirySourceCandidate? in
                guard let title = item["title"] as? String, !title.isEmpty else { return nil }
                let abstract = item["abstractText"] as? String
                let year = item["pubYear"] as? String
                let doi = item["doi"] as? String
                let pmid = item["pmid"] as? String
                let journal = item["journalTitle"] as? String
                let authorString = item["authorString"] as? String
                let citedBy = item["citedByCount"] as? Int
                let url = doi.map { "https://doi.org/\($0)" }
                    ?? pmid.map { "https://pubmed.ncbi.nlm.nih.gov/\($0)/" }
                let kind = inferKind(title: title, url: url, type: item["pubType"] as? String, body: abstract ?? "", local: false)
                let role = evidenceRole(for: kind, title: title, body: abstract ?? "", year: year)
                let signals = [
                    year.map { "Published \($0)" },
                    citedBy.map { "\($0) citations" },
                    doi == nil ? nil : "DOI",
                    journal
                ].compactMap { $0 }
                return InquirySourceCandidate(
                    id: stableID(provider: .pubMed, key: doi ?? pmid ?? title),
                    provider: .pubMed,
                    sourceKind: kind,
                    title: title,
                    subtitle: journal,
                    authors: authorString.map { [$0] } ?? [],
                    publishedDate: year,
                    url: url,
                    doi: doi,
                    abstract: abstract,
                    evidenceRole: role,
                    reason: "Deep Scout biomedical candidate from Europe PMC/PubMed.",
                    qualitySignals: signals,
                    branchQuestionUUID: profile.activeQuestionUUID,
                    branchNodeId: profile.branchNodeId
                )
            }
            return (InquiryProviderStatus(provider: .pubMed, state: .succeeded, count: candidates.count), candidates)
        } catch {
            return (InquiryProviderStatus(provider: .pubMed, state: .failed, message: error.localizedDescription), [])
        }
    }

    private static func fetchYouTube(
        query: String,
        profile: InquiryBranchResearchProfile
    ) async -> (InquiryProviderStatus, [InquirySourceCandidate]) {
        guard let apiKey = APIKeys.youtube, !apiKey.isEmpty else {
            return (InquiryProviderStatus(provider: .youtube, state: .missingKey, message: "Add a YouTube API key to include videos"), [])
        }
        guard let url = searchURL(base: "https://www.googleapis.com/youtube/v3/search", queryItems: [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "type", value: "video"),
            URLQueryItem(name: "maxResults", value: "10"),
            URLQueryItem(name: "order", value: "relevance"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "key", value: apiKey)
        ]) else {
            return (InquiryProviderStatus(provider: .youtube, state: .failed, message: "Invalid query"), [])
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode == 403 {
                return (InquiryProviderStatus(provider: .youtube, state: .rateLimited, message: "YouTube quota or key rejected"), [])
            }
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let items = object?["items"] as? [[String: Any]] ?? []
            let candidates = items.compactMap { item -> InquirySourceCandidate? in
                guard let id = item["id"] as? [String: Any],
                      let videoId = id["videoId"] as? String,
                      let snippet = item["snippet"] as? [String: Any],
                      let title = snippet["title"] as? String,
                      !title.isEmpty else { return nil }
                let description = snippet["description"] as? String
                let channel = snippet["channelTitle"] as? String
                let publishedAt = snippet["publishedAt"] as? String
                let year = publishedAt.map { String($0.prefix(4)) }
                return InquirySourceCandidate(
                    id: stableID(provider: .youtube, key: videoId),
                    provider: .youtube,
                    sourceKind: .video,
                    title: decodeHTMLEntities(title),
                    subtitle: channel,
                    publishedDate: year,
                    url: "https://www.youtube.com/watch?v=\(videoId)",
                    abstract: description,
                    evidenceRole: .videoExplainer,
                    reason: "Deep Scout video candidate from YouTube.",
                    qualitySignals: [
                        channel,
                        year.map { "Published \($0)" },
                        "Video"
                    ].compactMap { $0 },
                    branchQuestionUUID: profile.activeQuestionUUID,
                    branchNodeId: profile.branchNodeId
                )
            }
            return (InquiryProviderStatus(provider: .youtube, state: .succeeded, count: candidates.count), candidates)
        } catch {
            return (InquiryProviderStatus(provider: .youtube, state: .failed, message: error.localizedDescription), [])
        }
    }

    @MainActor
    private static func fetchWebResearch(
        query: String,
        profile: InquiryBranchResearchProfile
    ) async -> (InquiryProviderStatus, [InquirySourceCandidate]) {
        guard APIKeys.hasOpenRouter else {
            return (InquiryProviderStatus(provider: .web, state: .missingKey, message: "Add OpenRouter to include agentic web search"), [])
        }

        do {
            let result = try await ResearchService.shared.performResearch(query: query, searchType: .web, maxResults: 8)
            let candidates = result.findings.compactMap { finding -> InquirySourceCandidate? in
                guard !finding.title.isEmpty else { return nil }
                return InquirySourceCandidate(
                    id: stableID(provider: .web, key: finding.url ?? finding.title),
                    provider: .web,
                    sourceKind: .web,
                    title: finding.title,
                    subtitle: finding.source,
                    url: finding.url,
                    abstract: finding.snippet,
                    evidenceRole: .webContext,
                    reason: "Deep Scout web candidate from grounded research.",
                    qualitySignals: [
                        finding.source,
                        finding.confidence.capitalized
                    ],
                    branchQuestionUUID: profile.activeQuestionUUID,
                    branchNodeId: profile.branchNodeId
                )
            }
            return (InquiryProviderStatus(provider: .web, state: .succeeded, count: candidates.count), candidates)
        } catch ResearchError.noAPIKey {
            return (InquiryProviderStatus(provider: .web, state: .missingKey, message: "Add OpenRouter to include agentic web search"), [])
        } catch {
            return (InquiryProviderStatus(provider: .web, state: .failed, message: error.localizedDescription), [])
        }
    }

    private static func mergeCandidates(_ candidates: [InquirySourceCandidate]) -> [InquirySourceCandidate] {
        var merged: [String: InquirySourceCandidate] = [:]
        var byWork: [String: String] = [:]   // work key (title+author) → merge key
        for candidate in candidates {
            var key = mergeKey(for: candidate)
            // The same book/paper often appears with different URLs across
            // providers (Google Books vs Open Library) — collapse by work key.
            let work = workKey(for: candidate)
            if let existingKey = byWork[work] {
                key = existingKey
            } else {
                byWork[work] = key
            }
            if let existing = merged[key], existing.provider == .local {
                continue
            }
            if let existing = merged[key], existing.qualitySignals.count >= candidate.qualitySignals.count {
                continue
            }
            merged[key] = candidate
        }
        return Array(merged.values)
    }

    private static func mergeKey(for candidate: InquirySourceCandidate) -> String {
        if let doi = candidate.doi?.lowercased(), !doi.isEmpty { return "doi:\(doi)" }
        if let url = candidate.url?.lowercased(), !url.isEmpty { return "url:\(url)" }
        return "title:\(InquiryPlacementEngine.normalized(candidate.title))"
    }

    private static func workKey(for candidate: InquirySourceCandidate) -> String {
        let title = InquiryPlacementEngine.normalized(candidate.title)
        let authorLastName = candidate.authors.first?
            .split(separator: " ")
            .last
            .map { InquiryPlacementEngine.normalized(String($0)) } ?? ""
        return "\(title)|\(authorLastName)"
    }

    private static func alreadyImported(_ candidate: InquirySourceCandidate, existingSourceRefs: [InquirySourceRef]) -> Bool {
        if candidate.importStatus == .imported || candidate.importedSourceUUID != nil {
            return true
        }
        guard let candidateURL = candidate.url?.lowercased() else { return false }
        return existingSourceRefs.contains { ref in
            ref.url?.lowercased() == candidateURL || ref.sourceUUID == candidate.importedSourceUUID
        }
    }

    private static func providerBoost(for provider: InquirySourceProvider) -> Double {
        switch provider {
        case .local: return 0.13
        case .openAlex: return 0.10
        case .crossref: return 0.07
        case .semanticScholar, .pubMed: return 0.11
        case .arxiv: return 0.08
        case .youtube, .podcast: return 0.04
        case .web: return 0.03
        case .googleBooks, .openLibrary, .internetArchive: return 0.04
        }
    }

    private static func roleBoost(for role: InquiryEvidenceRole) -> Double {
        switch role {
        case .review, .metaAnalysis: return 0.12
        case .foundational, .mechanism, .counterevidence: return 0.08
        case .recent, .localLibrary: return 0.07
        case .practicalGuide, .videoExplainer, .webContext: return 0.04
        case .primaryText, .book, .lecture, .philosophicalContext, .traditionGuide: return 0.04
        }
    }

    private static func kindBoost(for kind: InquirySourceKind) -> Double {
        switch kind {
        case .review, .metaAnalysis: return 0.10
        case .paper, .localResearch, .book: return 0.06
        case .web, .video, .localNote: return 0.02
        case .unknown: return 0
        }
    }

    private static func recencyBoost(for date: String?) -> Double {
        guard let date,
              let year = Int(date.prefix(4)) else { return 0 }
        if year >= 2021 { return 0.05 }
        if year >= 2015 { return 0.03 }
        return 0
    }

    private static func qualityBoost(for candidate: InquirySourceCandidate) -> Double {
        let text = candidate.qualitySignals.joined(separator: " ").lowercased()
        var boost = 0.0
        if candidate.doi != nil || text.contains("doi") { boost += 0.025 }
        if text.contains("citations") {
            boost += 0.035
        }
        if candidate.sourceKind == .metaAnalysis || candidate.sourceKind == .review {
            boost += 0.02
        }
        if candidate.provider == .youtube && candidate.sourceKind == .video {
            boost += 0.01
        }
        return min(boost, 0.07)
    }

    private static func reason(
        for candidate: InquirySourceCandidate,
        matchedTokens: [String],
        anchorMatches: [String]
    ) -> String {
        if !anchorMatches.isEmpty {
            let anchors = anchorMatches.prefix(2).joined(separator: ", ")
            let supporting = matchedTokens.filter { !anchorMatches.contains($0) }.prefix(2).joined(separator: ", ")
            if supporting.isEmpty {
                return "Mentions \(anchors) and fills a \(candidate.evidenceRole.displayName.lowercased()) role."
            }
            return "Mentions \(anchors), also matches \(supporting), and fills a \(candidate.evidenceRole.displayName.lowercased()) role."
        }
        if matchedTokens.isEmpty {
            return "\(candidate.evidenceRole.displayName) source for the active branch."
        }
        return "Matches \(matchedTokens.prefix(3).joined(separator: ", ")) and fills a \(candidate.evidenceRole.displayName.lowercased()) role."
    }

    private static func evidenceRole(for kind: InquirySourceKind, title: String, body: String, year: String?) -> InquiryEvidenceRole {
        let lower = "\(title) \(body)".lowercased()
        if kind == .metaAnalysis { return .metaAnalysis }
        if kind == .review { return .review }
        if lower.contains("contradict") || lower.contains("adverse") || lower.contains("limitation") { return .counterevidence }
        if lower.contains("mechanism") || lower.contains("physiology") || lower.contains("neural") || lower.contains("biochemical") { return .mechanism }
        if let year, let intYear = Int(year), intYear >= 2021 { return .recent }
        return .foundational
    }

    private static func inferKind(title: String, url: String?, type: String?, body: String, local: Bool) -> InquirySourceKind {
        let lower = "\(title) \(type ?? "") \(body) \(url ?? "")".lowercased()
        if lower.contains("youtube.com") || lower.contains("youtu.be") { return .video }
        if lower.contains("meta-analysis") || lower.contains("metaanalysis") { return .metaAnalysis }
        if lower.contains("review") || lower.contains("systematic") { return .review }
        if local { return .localResearch }
        if lower.contains("journal") || lower.contains("article") || lower.contains("paper") { return .paper }
        return url == nil ? .unknown : .web
    }

    private static func searchURL(base: String, queryItems: [URLQueryItem]) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = queryItems
        return components?.url
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let decoded = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ).string else {
            return text
        }
        return decoded
    }

    private static func stableID(provider: InquirySourceProvider, key: String) -> String {
        var hash: UInt64 = 5381
        for scalar in key.lowercased().unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ UInt64(scalar.value)
        }
        return "\(provider.rawValue)-\(String(hash, radix: 16))"
    }

    private static func abstractText(fromOpenAlex inverted: [String: [Int]]?) -> String? {
        guard let inverted else { return nil }
        let pairs = inverted.flatMap { word, positions in positions.map { ($0, word) } }
        let words = pairs.sorted { $0.0 < $1.0 }.map(\.1)
        let text = words.prefix(80).joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    private static func crossrefYear(from item: [String: Any]) -> String? {
        for key in ["published-print", "published-online", "published", "issued"] {
            guard let published = item[key] as? [String: Any],
                  let dateParts = published["date-parts"] as? [[Int]],
                  let year = dateParts.first?.first else { continue }
            return String(year)
        }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
