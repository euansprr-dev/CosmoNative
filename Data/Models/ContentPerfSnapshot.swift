// CosmoOS/Data/Models/ContentPerfSnapshot.swift
// Real performance data for published content: dated per-platform metric
// snapshots entered by hand (fast keyboard sheet) — the ground truth that
// feeds the taste engine and, later, own-post ranking in the Margin.
// Multiple snapshots per post over time are expected (day-1, week-1, …).
// July 2026

import Foundation
import GRDB

struct ContentPerfSnapshot: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "content_perf_snapshots"

    var id: Int64?
    var contentUuid: String
    var platform: String
    var views: Int
    var likes: Int
    var comments: Int
    var shares: Int
    var saves: Int
    var followsGained: Int
    var capturedAt: String

    enum CodingKeys: String, ColumnExpression, CodingKey {
        case id
        case contentUuid = "content_uuid"
        case platform, views, likes, comments, shares, saves
        case followsGained = "follows_gained"
        case capturedAt = "captured_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var engagement: Int { likes + comments + shares + saves }

    var engagementRate: Double {
        views > 0 ? Double(engagement) / Double(views) : 0
    }

    var capturedAtDate: Date {
        ISO8601.date(from: capturedAt) ?? .distantPast
    }
}

// MARK: - Store

enum ContentPerfStore {
    static func record(_ snapshot: ContentPerfSnapshot) async throws {
        try await CosmoDatabase.shared.asyncWrite { db in
            guard (try? db.tableExists(ContentPerfSnapshot.databaseTableName)) ?? false else { return }
            var row = snapshot
            try row.insert(db)
        }
    }

    static func snapshots(forContent uuid: String) async -> [ContentPerfSnapshot] {
        (try? await CosmoDatabase.shared.asyncRead { db in
            guard (try? db.tableExists(ContentPerfSnapshot.databaseTableName)) ?? false else { return [] }
            return try ContentPerfSnapshot
                .filter(ContentPerfSnapshot.CodingKeys.contentUuid == uuid)
                .order(ContentPerfSnapshot.CodingKeys.capturedAt.desc)
                .fetchAll(db)
        }) ?? []
    }

    /// Latest snapshot per content atom — the queue's at-a-glance numbers.
    static func latestByContent() async -> [String: ContentPerfSnapshot] {
        (try? await CosmoDatabase.shared.asyncRead { db in
            guard (try? db.tableExists(ContentPerfSnapshot.databaseTableName)) ?? false else { return [:] }
            let all = try ContentPerfSnapshot
                .order(ContentPerfSnapshot.CodingKeys.capturedAt.desc)
                .fetchAll(db)
            var out: [String: ContentPerfSnapshot] = [:]
            for snapshot in all where out[snapshot.contentUuid] == nil {
                out[snapshot.contentUuid] = snapshot
            }
            return out
        }) ?? [:]
    }
}
