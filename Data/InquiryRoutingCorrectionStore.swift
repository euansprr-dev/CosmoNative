// CosmoOS/Data/InquiryRoutingCorrectionStore.swift
// Learned classification rules: every manual kind correction the user makes is
// recorded here and fed back into the live-router prompt as a worked example,
// so the classifier converges on the user's personal taxonomy instead of
// repeating the same misroute forever.

import Foundation
import GRDB

struct InquiryRoutingCorrection: Codable, Sendable, Identifiable {
    var id: String
    var text: String
    var fromKind: String
    var toKind: String
    var deepDiveUUID: String?
    var createdAt: String

    var fromExtractKind: ExtractKind? { ExtractKind(rawValue: fromKind) }
    var toExtractKind: ExtractKind? { ExtractKind(rawValue: toKind) }
}

actor InquiryRoutingCorrectionStore {
    static let shared = InquiryRoutingCorrectionStore()

    /// Corrections kept in the table; older rows are pruned on write.
    private let retentionLimit = 200
    private let iso = ISO8601DateFormatter()

    /// Records one manual kind correction. No-op when the kind didn't change.
    func record(
        text: String,
        fromKind: ExtractKind,
        toKind: ExtractKind,
        deepDiveUUID: String?
    ) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, fromKind != toKind else { return }
        let correction = InquiryRoutingCorrection(
            id: UUID().uuidString,
            text: String(trimmed.prefix(300)),
            fromKind: fromKind.rawValue,
            toKind: toKind.rawValue,
            deepDiveUUID: deepDiveUUID,
            createdAt: iso.string(from: Date())
        )
        let limit = retentionLimit
        do {
            try await CosmoDatabase.shared.asyncWrite { db in
                try db.execute(
                    sql: """
                        INSERT INTO inquiry_routing_corrections
                            (id, text, from_kind, to_kind, deep_dive_uuid, created_at)
                        VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        correction.id, correction.text, correction.fromKind,
                        correction.toKind, correction.deepDiveUUID, correction.createdAt
                    ]
                )
                try db.execute(
                    sql: """
                        DELETE FROM inquiry_routing_corrections
                        WHERE id NOT IN (
                            SELECT id FROM inquiry_routing_corrections
                            ORDER BY created_at DESC LIMIT ?
                        )
                    """,
                    arguments: [limit]
                )
            }
        } catch {
            print("[InquiryRoutingCorrectionStore] record failed: \(error)")
        }
    }

    /// Most useful corrections for a classification prompt: same deep dive
    /// first (freshest wins), then global recency to fill the remainder.
    func recentExamples(deepDiveUUID: String?, limit: Int = 8) async -> [InquiryLiveRouter.CorrectionExample] {
        let rows: [InquiryRoutingCorrection]
        do {
            rows = try await CosmoDatabase.shared.asyncRead { db in
                try Row.fetchAll(
                    db,
                    sql: """
                        SELECT id, text, from_kind, to_kind, deep_dive_uuid, created_at
                        FROM inquiry_routing_corrections
                        ORDER BY created_at DESC LIMIT 60
                    """
                ).map { row in
                    InquiryRoutingCorrection(
                        id: row["id"],
                        text: row["text"],
                        fromKind: row["from_kind"],
                        toKind: row["to_kind"],
                        deepDiveUUID: row["deep_dive_uuid"],
                        createdAt: row["created_at"]
                    )
                }
            }
        } catch {
            print("[InquiryRoutingCorrectionStore] fetch failed: \(error)")
            return []
        }

        let sameDive = rows.filter { $0.deepDiveUUID != nil && $0.deepDiveUUID == deepDiveUUID }
        let others = rows.filter { $0.deepDiveUUID == nil || $0.deepDiveUUID != deepDiveUUID }
        var seenTexts = Set<String>()
        var examples: [InquiryLiveRouter.CorrectionExample] = []
        for correction in sameDive + others {
            guard examples.count < limit else { break }
            guard let from = correction.fromExtractKind, let to = correction.toExtractKind else { continue }
            let key = correction.text.lowercased()
            guard !seenTexts.contains(key) else { continue }
            seenTexts.insert(key)
            examples.append(.init(text: correction.text, fromKind: from, toKind: to))
        }
        return examples
    }
}
