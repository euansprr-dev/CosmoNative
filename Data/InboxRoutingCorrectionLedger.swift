// CosmoOS/Data/InboxRoutingCorrectionLedger.swift
// The Ledger — learned routing rules for the inbox Atlas router.
//
// Every time the user overrides a suggestion (dismisses it, picks an
// alternate, or files the capture somewhere else with a verb), the override
// is recorded here and fed back into the router prompt as a worked example.
// This is InquiryRoutingCorrectionStore's pattern promoted to workspace
// scale: the router converges on the user's world map instead of repeating
// the same misroute forever ("real estate ideas are NOT for Josh").
//
// Accepts are recorded too (sparsely, see `record`) — positive examples teach
// the model which instincts to keep.

import Foundation
import GRDB

struct InboxRoutingCorrection: Codable, Sendable, Identifiable {
    var id: String
    var text: String
    /// What the user actually did — an `InboxRouteKind` rawValue or a verb
    /// slug ("task", "idea", "question", "connect", "dismiss").
    var chosenKind: String
    /// Human destination line ("Home Saving client", "Voluntary Hardship › Evidence").
    var chosenLabel: String
    /// The suggestion the user rejected, when there was one.
    var rejectedKind: String?
    var rejectedLabel: String?
    var createdAt: String
}

actor InboxRoutingCorrectionLedger {
    static let shared = InboxRoutingCorrectionLedger()

    /// One worked example for the router prompt.
    struct Example: Sendable, Equatable {
        var text: String
        var chosenLabel: String
        var rejectedLabel: String?
    }

    /// Corrections kept in the table; older rows are pruned on write.
    private let retentionLimit = 200
    private let iso = ISO8601DateFormatter()

    private init() {}

    /// Records one routing outcome. Pure accepts (no rejected destination)
    /// matter less than overrides, so callers should record them only when
    /// the accepted suggestion was an Atlas move — that keeps the table
    /// dominated by corrective signal.
    func record(
        text: String,
        chosenKind: String,
        chosenLabel: String,
        rejectedKind: String? = nil,
        rejectedLabel: String? = nil
    ) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !chosenLabel.isEmpty else { return }
        // A "correction" that chose the same destination it rejected is noise.
        if let rejectedLabel, rejectedLabel == chosenLabel, rejectedKind == chosenKind { return }

        let correction = InboxRoutingCorrection(
            id: UUID().uuidString,
            text: String(trimmed.prefix(300)),
            chosenKind: chosenKind,
            chosenLabel: String(chosenLabel.prefix(120)),
            rejectedKind: rejectedKind,
            rejectedLabel: rejectedLabel.map { String($0.prefix(120)) },
            createdAt: iso.string(from: Date())
        )
        let limit = retentionLimit
        do {
            try await CosmoDatabase.shared.asyncWrite { db in
                try db.execute(
                    sql: """
                        INSERT INTO inbox_routing_corrections
                            (id, text, chosen_kind, chosen_label, rejected_kind, rejected_label, created_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        correction.id, correction.text, correction.chosenKind, correction.chosenLabel,
                        correction.rejectedKind, correction.rejectedLabel, correction.createdAt
                    ]
                )
                try db.execute(
                    sql: """
                        DELETE FROM inbox_routing_corrections
                        WHERE id NOT IN (
                            SELECT id FROM inbox_routing_corrections
                            ORDER BY created_at DESC LIMIT ?
                        )
                    """,
                    arguments: [limit]
                )
            }
        } catch {
            print("[InboxRoutingCorrectionLedger] record failed: \(error)")
        }
    }

    /// Recent worked examples for the router prompt. Overrides (rows with a
    /// rejected destination) come first — they carry the teaching signal.
    func recentExamples(limit: Int = 8) async -> [Example] {
        let rows: [InboxRoutingCorrection]
        do {
            rows = try await CosmoDatabase.shared.asyncRead { db in
                try Row.fetchAll(
                    db,
                    sql: """
                        SELECT id, text, chosen_kind, chosen_label, rejected_kind, rejected_label, created_at
                        FROM inbox_routing_corrections
                        ORDER BY created_at DESC LIMIT 60
                    """
                ).map { row in
                    InboxRoutingCorrection(
                        id: row["id"],
                        text: row["text"],
                        chosenKind: row["chosen_kind"],
                        chosenLabel: row["chosen_label"],
                        rejectedKind: row["rejected_kind"],
                        rejectedLabel: row["rejected_label"],
                        createdAt: row["created_at"]
                    )
                }
            }
        } catch {
            print("[InboxRoutingCorrectionLedger] fetch failed: \(error)")
            return []
        }

        let overrides = rows.filter { $0.rejectedLabel != nil }
        let confirmations = rows.filter { $0.rejectedLabel == nil }
        var seenTexts = Set<String>()
        var examples: [Example] = []
        for correction in overrides + confirmations {
            guard examples.count < limit else { break }
            let key = correction.text.lowercased()
            guard !seenTexts.contains(key) else { continue }
            seenTexts.insert(key)
            examples.append(Example(
                text: correction.text,
                chosenLabel: correction.chosenLabel,
                rejectedLabel: correction.rejectedLabel
            ))
        }
        return examples
    }
}
