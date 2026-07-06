// CosmoOS/Data/InquiryGardenerDecisionStore.swift
// Memory for the Gardener: every accepted or dismissed structure proposal is
// recorded so a dismissed suggestion never resurfaces and future judgment
// passes can learn the user's structural taste (the correction-store pattern).

import Foundation
import GRDB

actor InquiryGardenerDecisionStore {
    static let shared = InquiryGardenerDecisionStore()

    enum Decision: String {
        case accepted
        case dismissed
    }

    private let retentionLimit = 400
    private let iso = ISO8601DateFormatter()

    func record(key: String, decision: Decision, deepDiveUUID: String?) async {
        do {
            try await CosmoDatabase.shared.asyncWrite { [retentionLimit, iso] db in
                try db.execute(
                    sql: """
                        INSERT INTO inquiry_gardener_decisions
                            (id, proposal_key, decision, deep_dive_uuid, created_at)
                        VALUES (?, ?, ?, ?, ?)
                    """,
                    arguments: [UUID().uuidString, key, decision.rawValue, deepDiveUUID, iso.string(from: Date())]
                )
                try db.execute(
                    sql: """
                        DELETE FROM inquiry_gardener_decisions
                        WHERE id NOT IN (
                            SELECT id FROM inquiry_gardener_decisions
                            ORDER BY created_at DESC LIMIT ?
                        )
                    """,
                    arguments: [retentionLimit]
                )
            }
        } catch {
            print("[InquiryGardenerDecisionStore] record failed: \(error)")
        }
    }

    /// Every proposal key the user has already ruled on for this topic —
    /// the Gardener never re-litigates a decision.
    func decidedKeys(deepDiveUUID: String) async -> Set<String> {
        do {
            let rows = try await CosmoDatabase.shared.asyncRead { db in
                try Row.fetchAll(
                    db,
                    sql: "SELECT proposal_key FROM inquiry_gardener_decisions WHERE deep_dive_uuid = ?",
                    arguments: [deepDiveUUID]
                ).map { $0["proposal_key"] as String }
            }
            return Set(rows)
        } catch {
            print("[InquiryGardenerDecisionStore] decidedKeys failed: \(error)")
            return []
        }
    }
}
