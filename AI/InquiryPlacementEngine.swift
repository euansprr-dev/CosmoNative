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
        let broadSignals = lower.contains("topic") || lower.contains("field") || lower.contains("entire") || lower.contains("world of")
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
