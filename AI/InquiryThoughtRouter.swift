// CosmoOS/AI/InquiryThoughtRouter.swift
// Cheap local parser for turning notes/chat into multiple routeable inquiry units.

import Foundation

struct InquiryThoughtRouter {
    static func route(
        text: String,
        activeQuestionUUID: String?,
        activeBranchNodeId: String?,
        originExtractUUID: String?,
        sourceTabId: String?
    ) -> [InquiryRoutingCard] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var cards: [InquiryRoutingCard] = []
        let lower = trimmed.lowercased()
        let sentences = splitThoughts(trimmed)

        for question in questions(in: sentences) {
            cards.append(
                card(
                    kind: .branchProposal,
                    title: "Question candidate",
                    detail: "Detected inside the saved thought.",
                    proposedQuestion: normalizeQuestion(question),
                    activeQuestionUUID: activeQuestionUUID,
                    activeBranchNodeId: activeBranchNodeId,
                    originExtractUUID: originExtractUUID,
                    sourceTabId: sourceTabId
                )
            )
        }

        if cards.isEmpty, let inferred = inferredBranchQuestion(from: lower) {
            cards.append(
                card(
                    kind: .branchProposal,
                    title: "Question candidate",
                    detail: "This looks like a path worth separating from the current question.",
                    proposedQuestion: inferred,
                    activeQuestionUUID: activeQuestionUUID,
                    activeBranchNodeId: activeBranchNodeId,
                    originExtractUUID: originExtractUUID,
                    sourceTabId: sourceTabId
                )
            )
        }

        if let deeper = deeperQuestion(from: lower) {
            cards.append(
                card(
                    kind: .childBranchProposal,
                    title: "Bigger follow-up",
                    detail: "This can sit beneath the branch as a second-order question.",
                    proposedQuestion: deeper,
                    activeQuestionUUID: activeQuestionUUID,
                    activeBranchNodeId: activeBranchNodeId,
                    originExtractUUID: originExtractUUID,
                    sourceTabId: sourceTabId
                )
            )
        }

        if let claim = claimText(from: trimmed, lower: lower) {
            let speculative = looksSpeculative(lower)
            cards.append(
                card(
                    kind: .claimProposal,
                    title: speculative ? "Speculative claim" : "Claim",
                    detail: speculative ? "Save it as low-confidence material until evidence is attached." : "Save it to Answer Forming for this question.",
                    proposedExtractText: claim,
                    proposedExtractKind: speculative ? .speculativeClaim : .claim,
                    actionTitle: speculative ? "Save as speculative claim" : "Save claim",
                    activeQuestionUUID: activeQuestionUUID,
                    activeBranchNodeId: activeBranchNodeId,
                    originExtractUUID: originExtractUUID,
                    sourceTabId: sourceTabId
                )
            )
        }

        if let mechanism = mechanismText(from: trimmed, lower: lower) {
            cards.append(
                card(
                    kind: .mechanismProposal,
                    title: "Mechanism candidate",
                    detail: "This explains how or why a claim might work.",
                    proposedExtractText: mechanism,
                    proposedExtractKind: .mechanism,
                    actionTitle: "Save mechanism",
                    activeQuestionUUID: activeQuestionUUID,
                    activeBranchNodeId: activeBranchNodeId,
                    originExtractUUID: originExtractUUID,
                    sourceTabId: sourceTabId
                )
            )
        }

        if needsEvidenceWarning(lower) {
            cards.append(
                card(
                    kind: .sourceQualityWarning,
                    title: "Evidence quality warning",
                    detail: "This idea is interesting, but it needs stronger sources or counterevidence before it becomes a working belief.",
                    proposedExtractText: "This claim is speculative and needs stronger sources, replication, or counterevidence.",
                    proposedExtractKind: .sourceQualityNote,
                    actionTitle: "Save warning",
                    activeQuestionUUID: activeQuestionUUID,
                    activeBranchNodeId: activeBranchNodeId,
                    originExtractUUID: originExtractUUID,
                    sourceTabId: sourceTabId
                )
            )
            cards.append(
                card(
                    kind: .sourceFinding,
                    title: "Find stronger sources",
                    detail: "Search for direct support, replication, and counterevidence before relying on this.",
                    proposedQuestion: "What stronger sources support or challenge this claim?",
                    actionTitle: "Create evidence task",
                    activeQuestionUUID: activeQuestionUUID,
                    activeBranchNodeId: activeBranchNodeId,
                    originExtractUUID: originExtractUUID,
                    sourceTabId: sourceTabId
                )
            )
        }

        return cards
    }

    private static func card(
        kind: InquiryRoutingCard.Kind,
        title: String,
        detail: String?,
        proposedQuestion: String? = nil,
        proposedExtractText: String? = nil,
        proposedExtractKind: ExtractKind? = nil,
        actionTitle: String? = nil,
        activeQuestionUUID: String?,
        activeBranchNodeId: String?,
        originExtractUUID: String?,
        sourceTabId: String?
    ) -> InquiryRoutingCard {
        InquiryRoutingCard(
            kind: kind,
            title: title,
            detail: detail,
            proposedQuestion: proposedQuestion,
            proposedExtractText: proposedExtractText,
            proposedExtractKind: proposedExtractKind,
            actionTitle: actionTitle,
            parentQuestionUUID: activeQuestionUUID,
            parentBranchNodeId: activeBranchNodeId,
            originExtractUUID: originExtractUUID,
            sourceTabId: sourceTabId
        )
    }

    private static func splitThoughts(_ text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet(charactersIn: "\n.;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func questions(in sentences: [String]) -> [String] {
        Array(sentences.filter { $0.contains("?") }.prefix(3))
    }

    private static func normalizeQuestion(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix("?") ? trimmed : "\(trimmed)?"
    }

    private static func inferredBranchQuestion(from lower: String) -> String? {
        if lower.contains("breath") && (lower.contains("frequency") || lower.contains("biomagnetic") || lower.contains("energy")) {
            return "How does breathing affect frequency and biomagnetic field?"
        }
        if lower.contains("less about") && lower.contains("more about") {
            return "What is this really about?"
        }
        if lower.contains("affect") || lower.contains("influence") || lower.contains("relate") {
            return "How does this relationship actually work?"
        }
        return nil
    }

    private static func deeperQuestion(from lower: String) -> String? {
        if lower.contains("frequency") || lower.contains("biomagnetic") || lower.contains("energy state") {
            return "What does frequency or biomagnetic energy affect?"
        }
        return nil
    }

    private static func claimText(from text: String, lower: String) -> String? {
        guard lower.contains("i think") || lower.contains("may") || lower.contains("might") || lower.contains("seems") || lower.contains("is actually") || lower.contains("influence") || lower.contains("affect") || lower.contains("relate") else {
            return nil
        }
        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count <= 180 { return cleaned }
        return String(cleaned.prefix(180)) + "..."
    }

    private static func mechanismText(from text: String, lower: String) -> String? {
        guard lower.contains("through") || lower.contains("via") || lower.contains("because") || lower.contains("mechanism") || lower.contains("mediated by") else {
            return nil
        }
        return text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func looksSpeculative(_ lower: String) -> Bool {
        lower.contains("may") || lower.contains("might") || lower.contains("maybe") || lower.contains("speculative") || lower.contains("frequency") || lower.contains("biomagnetic") || lower.contains("energy")
    }

    private static func needsEvidenceWarning(_ lower: String) -> Bool {
        lower.contains("frequency") || lower.contains("biomagnetic") || lower.contains("qi gong") || lower.contains("qigong") || lower.contains("energy field") || lower.contains("unusual") || lower.contains("replication")
    }
}
