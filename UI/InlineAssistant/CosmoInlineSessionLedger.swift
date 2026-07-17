// CosmoOS/UI/InlineAssistant/CosmoInlineSessionLedger.swift
// The structured session memory for an inline assistant conversation: one
// record per run (ask → deliverable → review outcome), rendered into the
// volatile prompt layer as "## Session So Far". This is the state-based
// continuity carrier — the model reads what was actually asked, proposed,
// answered, and accepted, instead of inferring it from a message window that
// may have scrolled the previous ask out.

import Foundation

/// One run of the inline assistant, from the user's ask to the review outcome.
/// Flat fields (not an enum) because a single run can produce both a staged
/// proposal and a pane answer, and the review outcome arrives later.
struct CosmoInlineTurnRecord: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    /// The pane-message run this record describes (nil on older blobs) — lets
    /// a run card find its ledger record for actions like "save as skill".
    var runID: UUID?
    var userAsk: String
    var route: CosmoInlineAssistantRoute
    var skillID: String?

    /// Staged proposal, when the run produced one.
    var proposalID: UUID?
    var proposalTitle: String?
    var proposalSummary: String?
    var operationCount: Int = 0

    /// Review outcome — written back when the user acts on the proposal.
    var acceptedOperationCount: Int = 0
    var rejectedOperationCount: Int = 0

    /// First sentences of a pane answer, when the run produced one.
    var answerDigest: String?
    /// Set when the run failed or was stopped before delivering.
    var errorDigest: String?

    var createdAt = Date()

    var hasPendingOperations: Bool {
        proposalID != nil && (acceptedOperationCount + rejectedOperationCount) < operationCount
    }
}

enum CosmoInlineSessionLedger {
    static let maxRenderedRecords = 20
    static let maxStoredRecords = 60
    private static let askCap = 160
    private static let digestCap = 220

    /// Build the record for a completed run from what the run visibly produced.
    static func record(
        userAsk: String,
        route: CosmoInlineAssistantRoute,
        skillID: String?,
        newProposals: [CosmoAssistantProposal],
        newAnswerText: String?,
        errorText: String?
    ) -> CosmoInlineTurnRecord {
        var record = CosmoInlineTurnRecord(
            userAsk: clipped(userAsk, limit: askCap),
            route: route,
            skillID: skillID
        )
        if let proposal = newProposals.last {
            record.proposalID = proposal.id
            record.proposalTitle = proposal.title
            record.proposalSummary = clipped(proposal.summary, limit: digestCap)
            // Count only the recorded proposal's operations — review-state sync
            // (`updated(_:withReviewStateOf:)`) tracks this same proposal, so a
            // multi-proposal run must not inflate the count it can never settle.
            record.operationCount = proposal.operations.count
        }
        if let answer = newAnswerText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !answer.isEmpty {
            record.answerDigest = clipped(answer, limit: digestCap)
        }
        if record.proposalID == nil, record.answerDigest == nil,
           let error = errorText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !error.isEmpty {
            record.errorDigest = clipped(error, limit: digestCap)
        }
        return record
    }

    /// Sync a record's review counts from its proposal's live operation
    /// statuses — called from the store's operation-status choke point so
    /// accept/reject/revert all land here.
    static func updated(
        _ records: [CosmoInlineTurnRecord],
        withReviewStateOf proposal: CosmoAssistantProposal
    ) -> [CosmoInlineTurnRecord] {
        guard let index = records.lastIndex(where: { $0.proposalID == proposal.id }) else {
            return records
        }
        var next = records
        next[index].acceptedOperationCount = proposal.operations.filter {
            $0.status == .applied || $0.status == .accepted
        }.count
        next[index].rejectedOperationCount = proposal.operations.filter {
            $0.status == .rejected
        }.count
        next[index].operationCount = proposal.operations.count
        return next
    }

    /// The "## Session So Far" block for the volatile prompt layer.
    /// One line per run, oldest → newest, review state included.
    static func promptBlock(records: [CosmoInlineTurnRecord]) -> String? {
        guard !records.isEmpty else { return nil }
        let rendered = records.suffix(maxRenderedRecords)
        let omitted = records.count - rendered.count

        var lines: [String] = []
        for (offset, record) in rendered.enumerated() {
            lines.append(line(for: record, number: omitted + offset + 1))
        }

        var header = "## Session So Far\nEvery run of this session, oldest first. \"This\", \"that\", \"the same\" and other references in the user's next message resolve against these turns and the active surface."
        if omitted > 0 {
            header += "\n(\(omitted) earlier turn\(omitted == 1 ? "" : "s") omitted)"
        }
        return header + "\n" + lines.joined(separator: "\n")
    }

    private static func line(for record: CosmoInlineTurnRecord, number: Int) -> String {
        let routeLabel = record.route == .action ? "edit" : "answer"
        var line = "\(number). [\(routeLabel)] \"\(record.userAsk)\""
        if let skillID = record.skillID {
            line += " (skill: \(CosmoInlineSkillRegistry.humanized(skillID)))"
        }

        var outcomes: [String] = []
        if let title = record.proposalTitle {
            var proposalPart = "staged \"\(title)\""
            if record.operationCount > 0 {
                proposalPart += " (\(record.operationCount) op\(record.operationCount == 1 ? "" : "s"))"
            }
            if let summary = record.proposalSummary, !summary.isEmpty {
                proposalPart += ": \(summary)"
            }
            outcomes.append(proposalPart)
            outcomes.append(reviewState(for: record))
        }
        if let answer = record.answerDigest {
            outcomes.append("answered: \(answer)")
        }
        if let error = record.errorDigest {
            outcomes.append("failed: \(error)")
        }
        if outcomes.isEmpty {
            outcomes.append("no visible result")
        }

        line += " → " + outcomes.joined(separator: " — ")
        return line
    }

    private static func reviewState(for record: CosmoInlineTurnRecord) -> String {
        let accepted = record.acceptedOperationCount
        let rejected = record.rejectedOperationCount
        let pending = max(0, record.operationCount - accepted - rejected)
        if accepted == 0 && rejected == 0 {
            return "awaiting review"
        }
        var parts: [String] = []
        if accepted > 0 { parts.append("user accepted \(accepted)") }
        if rejected > 0 { parts.append("rejected \(rejected)") }
        if pending > 0 { parts.append("\(pending) pending") }
        return parts.joined(separator: ", ")
    }

    private static func clipped(_ value: String, limit: Int) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

// MARK: - Review track record (learning render-back)

/// Closes the loop on review-outcome learning: accept/reject decisions were
/// recorded (AgentOutcomeTracker) but never read back, so the assistant could
/// repeat a rejected pattern forever. This distills the skill's recent review
/// outcomes into a short volatile-prompt block — acceptance rate plus the most
/// recent rejected edits as concrete negative examples.
@MainActor
enum CosmoInlineReviewTrackRecord {
    static let minimumOutcomesForSignal = 3
    static let maxRejectedExamples = 2

    static func promptBlock(skillID: String?) async -> String? {
        let category = "skill:\(skillID ?? CosmoInlineAssistantSkillID.inlineEdit.rawValue)"
        let events = await AgentOutcomeTracker.shared.getRecentEvents(
            category: .suggestionAcceptance,
            limit: 50
        )
        let scoped = events.filter { $0.context["category"] == category }
        guard scoped.count >= minimumOutcomesForSignal else { return nil }

        let acceptedCount = scoped.filter { $0.context["accepted"] == "true" }.count
        let rejected = scoped.filter { $0.context["accepted"] != "true" }
        guard !rejected.isEmpty else { return nil }

        var lines = [
            "## Review Track Record",
            "For this kind of request, the user accepted \(acceptedCount) of the last \(scoped.count) staged edits. Rejected edits are the strongest available signal — do not repeat their shape."
        ]
        for event in rejected.prefix(maxRejectedExamples) {
            let preview = event.offered
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(140)
            guard !preview.isEmpty else { continue }
            lines.append("- Recently REJECTED: \"\(preview)\"")
        }
        lines.append("Stay closer to the user's wording and scope than these rejected attempts did.")
        return lines.joined(separator: "\n")
    }
}

extension CosmoInlineSkillDefinition {
    /// A prefilled custom-skill draft from a successful run — "promote this run
    /// into a skill". The ask becomes the routing description and the run's
    /// deliverable becomes the worked example; the user refines in the Studio.
    static func draft(fromRun record: CosmoInlineTurnRecord) -> CosmoInlineSkillDefinition {
        let idealOutput = record.proposalSummary ?? record.answerDigest ?? ""
        return .custom(
            name: record.proposalTitle ?? String(record.userAsk.prefix(40)),
            summary: "Repeats a proven run: \(record.userAsk)",
            route: record.route,
            instructions: [
                "The user's ask follows this pattern: \"\(record.userAsk)\".",
                record.route == .action
                    ? "Stage the edits with propose_workspace_edit, matching the example's shape and quality."
                    : "Answer via answer_in_assistant_pane, matching the example's shape and quality."
            ],
            outputContract: record.route == .action
                ? "One reviewed proposal with in-place operations."
                : "One pane answer.",
            requiresReviewedDiff: record.route == .action,
            panePolicy: record.route == .action ? .neverForAction : .openForAnswer,
            triggerDescription: record.userAsk,
            examples: idealOutput.isEmpty
                ? nil
                : [CosmoInlineSkillExample(input: record.userAsk, idealOutput: idealOutput)]
        )
    }
}
