// CosmoOS/Data/DeepScoutTasteStore.swift
// Learned source taste: every Deep Scout candidate the user imports or
// dismisses is recorded with its creator (YouTube channel, podcast show, book
// author). Favorite creators emerge from behavior and feed both the query
// planner ("this user loves Alex Hormozi, Modern Wisdom…") and the ranker as
// boosts — learned rules, never a hardcoded creator list.

import Foundation
import GRDB

/// One creator's learned standing, aggregated from decisions.
struct DeepScoutCreatorAffinity: Sendable, Equatable {
    var creator: String
    var provider: String
    var imports: Int
    var dismissals: Int

    /// Net signal: repeated imports make a favorite; repeated dismissals bury one.
    var signal: Int { imports - dismissals }
}

/// The taste snapshot handed to the planner and ranker.
struct DeepScoutTasteProfile: Sendable, Equatable {
    /// Creators the user keeps importing, strongest first.
    var favoriteCreators: [DeepScoutCreatorAffinity] = []
    /// Creators the user keeps dismissing.
    var avoidedCreators: [DeepScoutCreatorAffinity] = []

    var isEmpty: Bool { favoriteCreators.isEmpty && avoidedCreators.isEmpty }
}

actor DeepScoutTasteStore {
    static let shared = DeepScoutTasteStore()

    enum Decision: String {
        case imported
        case dismissed
    }

    /// Decision rows kept; older rows are pruned on write.
    private let retentionLimit = 600
    private let iso = ISO8601DateFormatter()

    /// Record one import/dismiss decision. Creator is the candidate's channel,
    /// show, or first author — decisions without a creator still count for
    /// provider-level stats but can't build creator affinity.
    func record(
        decision: Decision,
        candidate: InquirySourceCandidate,
        deepDiveUUID: String?
    ) async {
        let creator = Self.creatorName(for: candidate)
        do {
            try await CosmoDatabase.shared.asyncWrite { [retentionLimit, iso] db in
                try db.execute(
                    sql: """
                        INSERT INTO deep_scout_taste
                            (id, decision, creator, provider, lane, title, deep_dive_uuid, created_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        UUID().uuidString,
                        decision.rawValue,
                        creator,
                        candidate.provider.rawValue,
                        candidate.sourceLane?.rawValue,
                        String(candidate.title.prefix(200)),
                        deepDiveUUID,
                        iso.string(from: Date())
                    ]
                )
                try db.execute(
                    sql: """
                        DELETE FROM deep_scout_taste
                        WHERE id NOT IN (
                            SELECT id FROM deep_scout_taste
                            ORDER BY created_at DESC LIMIT ?
                        )
                    """,
                    arguments: [retentionLimit]
                )
            }
        } catch {
            print("[DeepScoutTasteStore] record failed: \(error)")
        }
    }

    /// Aggregated taste across all deep dives — taste in teachers is a
    /// property of the person, not of one topic.
    func profile(favoriteLimit: Int = 10, avoidedLimit: Int = 6) async -> DeepScoutTasteProfile {
        let rows: [(decision: String, creator: String?, provider: String)]
        do {
            rows = try await CosmoDatabase.shared.asyncRead { db in
                try Row.fetchAll(
                    db,
                    sql: "SELECT decision, creator, provider FROM deep_scout_taste ORDER BY created_at DESC LIMIT 600"
                ).map { ($0["decision"], $0["creator"], $0["provider"]) }
            }
        } catch {
            print("[DeepScoutTasteStore] profile fetch failed: \(error)")
            return DeepScoutTasteProfile()
        }

        var affinities: [String: DeepScoutCreatorAffinity] = [:]
        for row in rows {
            guard let creator = row.creator?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !creator.isEmpty else { continue }
            let key = creator.lowercased()
            var entry = affinities[key] ?? DeepScoutCreatorAffinity(
                creator: creator, provider: row.provider, imports: 0, dismissals: 0
            )
            if row.decision == Decision.imported.rawValue {
                entry.imports += 1
            } else {
                entry.dismissals += 1
            }
            affinities[key] = entry
        }

        let favorites = affinities.values
            .filter { $0.signal > 0 }
            .sorted { ($0.signal, $0.imports) > ($1.signal, $1.imports) }
            .prefix(favoriteLimit)
        // One stray dismissal isn't avoidance — require a repeated pattern.
        let avoided = affinities.values
            .filter { $0.signal <= -2 }
            .sorted { $0.signal < $1.signal }
            .prefix(avoidedLimit)
        return DeepScoutTasteProfile(
            favoriteCreators: Array(favorites),
            avoidedCreators: Array(avoided)
        )
    }

    /// The candidate's creator identity: channel for videos, show for podcast
    /// episodes, first author for books/papers.
    static func creatorName(for candidate: InquirySourceCandidate) -> String? {
        switch candidate.provider {
        case .youtube, .podcast:
            return candidate.subtitle
        default:
            return candidate.authors.first ?? candidate.subtitle
        }
    }
}
