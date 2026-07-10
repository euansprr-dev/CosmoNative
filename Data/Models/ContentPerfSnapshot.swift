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

    /// Latest snapshot per (content, platform) — the honest basis for client
    /// aggregates: one post published to three platforms counts each platform's
    /// freshest numbers once.
    static func latestByContentPlatform() async -> [ContentPerfSnapshot] {
        (try? await CosmoDatabase.shared.asyncRead { db in
            guard (try? db.tableExists(ContentPerfSnapshot.databaseTableName)) ?? false else { return [] }
            let all = try ContentPerfSnapshot
                .order(ContentPerfSnapshot.CodingKeys.capturedAt.desc)
                .fetchAll(db)
            var seen = Set<String>()
            var out: [ContentPerfSnapshot] = []
            for snapshot in all {
                let key = "\(snapshot.contentUuid)|\(snapshot.platform)"
                if seen.insert(key).inserted { out.append(snapshot) }
            }
            return out
        }) ?? []
    }
}

// MARK: - Publish Records

/// One publish event: where a post went live. A multi-platform post carries
/// one record per platform under the same atom. Stored as a `publishRecords`
/// array in the content atom's metadata via key-merge — sibling keys survive.
struct ContentPublishRecord: Codable, Sendable, Equatable, Identifiable {
    var platform: String
    var url: String?
    var publishedAt: String

    var id: String { "\(platform)|\(publishedAt)" }

    var publishedAtDate: Date { ISO8601.date(from: publishedAt) ?? .distantPast }
}

/// Decode lens: reads only the publish keys off a content atom's metadata.
struct ContentPublishLens: Codable, Sendable {
    var publishRecords: [ContentPublishRecord]?
    var status: String?
}

enum ContentPublishStore {
    /// Key-merge overlay — encodes ONLY the keys this store owns.
    private struct Overlay: Encodable {
        var publishRecords: [ContentPublishRecord]
        var status: String
    }

    static func records(for atom: Atom) -> [ContentPublishRecord] {
        atom.metadataValue(as: ContentPublishLens.self)?.publishRecords ?? []
    }

    /// Mark a content atom published on a platform: appends a publish record
    /// (idempotent per platform — republishing updates the record), stamps
    /// status, then recomputes the owning client's aggregates.
    static func markPublished(atomUuid: String, platform: String, url: String? = nil) async {
        guard let atom = try? await AtomRepository.shared.fetch(uuid: atomUuid) else { return }
        var records = records(for: atom).filter { $0.platform != platform }
        records.append(ContentPublishRecord(
            platform: platform,
            url: url?.isEmpty == true ? nil : url,
            publishedAt: ISO8601.string(from: Date())
        ))
        let updated = atom.mergingMetadataKeys(Overlay(publishRecords: records, status: "published"))
        _ = try? await AtomRepository.shared.update(updated)
        await ClientPerfAggregator.recomputeForContent(atom)
    }
}

// MARK: - Client Aggregates

/// Recomputes the hand-maintained-fiction fields on `ClientProfileMetadata`
/// (totalReach / avgEngagementRate / topPerformingPostIds) from real snapshot
/// data. Written through the Profile Studio merge-save contract: an overlay
/// with ONLY these keys, merged over the client atom's metadata.
/// The recomputed truth for a client dossier — pure math, unit-tested.
struct ClientPerfSummary: Equatable, Sendable {
    var totalReach: Int
    var avgEngagementRate: Double
    var topPerformingPostIds: [String]
}

enum ClientPerfAggregator {
    private struct Overlay: Encodable {
        var totalReach: Int
        var avgEngagementRate: Double
        var topPerformingPostIds: [String]
    }

    /// Posts need at least this many combined views before they can rank as
    /// "top performing" — keeps a 3-view fluke off the podium.
    static let topPostViewsFloor = 25

    /// Pure aggregation over latest-per-(content, platform) snapshots:
    /// reach = Σ views, rate = engagement-weighted mean, top = best 3 by rate.
    static func summarize(_ latest: [ContentPerfSnapshot]) -> ClientPerfSummary {
        let totalReach = latest.reduce(0) { $0 + $1.views }
        let totalEngagement = latest.reduce(0) { $0 + $1.engagement }
        let avgEngagementRate = totalReach > 0 ? Double(totalEngagement) / Double(totalReach) : 0

        var byContent: [String: (views: Int, engagement: Int)] = [:]
        for snapshot in latest {
            var entry = byContent[snapshot.contentUuid] ?? (0, 0)
            entry.views += snapshot.views
            entry.engagement += snapshot.engagement
            byContent[snapshot.contentUuid] = entry
        }
        let topIds = byContent
            .filter { $0.value.views >= topPostViewsFloor }
            .sorted {
                let lhs = Double($0.value.engagement) / Double(max($0.value.views, 1))
                let rhs = Double($1.value.engagement) / Double(max($1.value.views, 1))
                if lhs != rhs { return lhs > rhs }
                return $0.key < $1.key  // deterministic tie-break
            }
            .prefix(3)
            .map(\.key)

        return ClientPerfSummary(
            totalReach: totalReach,
            avgEngagementRate: avgEngagementRate,
            topPerformingPostIds: Array(topIds)
        )
    }

    /// Resolve the owning client from a content atom, then recompute.
    static func recomputeForContent(_ atom: Atom) async {
        guard let clientUuid = atom.metadataValue(as: ContentAtomMetadata.self)?.clientProfileUUID else { return }
        await recompute(clientUuid: clientUuid)
    }

    static func recompute(clientUuid: String) async {
        guard let client = try? await AtomRepository.shared.fetch(uuid: clientUuid) else { return }

        // Content atoms owned by this client (personal scale — in-memory filter).
        let contentAtoms: [Atom] = (try? await CosmoDatabase.shared.asyncRead { db in
            try Atom
                .filter(Column("type") == AtomType.content.rawValue)
                .filter(Column("is_deleted") == false)
                .filter(Column("metadata").like("%\(clientUuid)%"))
                .limit(500)
                .fetchAll(db)
        }) ?? []
        let ownedUuids = Set(
            contentAtoms
                .filter { $0.metadataValue(as: ContentAtomMetadata.self)?.clientProfileUUID == clientUuid }
                .map(\.uuid)
        )
        guard !ownedUuids.isEmpty else { return }

        let latest = await ContentPerfStore.latestByContentPlatform()
            .filter { ownedUuids.contains($0.contentUuid) }
        guard !latest.isEmpty else { return }

        let summary = summarize(latest)
        let updated = client.mergingMetadataKeys(Overlay(
            totalReach: summary.totalReach,
            avgEngagementRate: summary.avgEngagementRate,
            topPerformingPostIds: summary.topPerformingPostIds
        ))
        _ = try? await AtomRepository.shared.update(updated)
    }
}
