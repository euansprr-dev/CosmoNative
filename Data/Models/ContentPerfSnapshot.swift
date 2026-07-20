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
    /// `at` overrides "now" for retroactive records; `preservingExistingDate`
    /// keeps an existing platform record's date untouched (perf logging must
    /// never move a post on the calendar — only dragging moves dates).
    static func markPublished(
        atomUuid: String,
        platform: String,
        url: String? = nil,
        at date: Date? = nil,
        preservingExistingDate: Bool = false
    ) async {
        guard let atom = try? await AtomRepository.shared.fetch(uuid: atomUuid) else { return }
        let existing = records(for: atom)
        let prior = existing.first { $0.platform == platform }
        var records = existing.filter { $0.platform != platform }
        let publishedAt = (preservingExistingDate ? prior?.publishedAt : nil)
            ?? ISO8601.string(from: date ?? Date())
        records.append(ContentPublishRecord(
            platform: platform,
            url: url?.isEmpty == false ? url : prior?.url,
            publishedAt: publishedAt
        ))
        let updated = atom.mergingMetadataKeys(Overlay(publishRecords: records, status: "published"))
        _ = try? await AtomRepository.shared.update(updated)
        await ClientPerfAggregator.recomputeForContent(atom)
    }

    /// Dragging is the only gesture that moves a published post: rewrite every
    /// publish record onto the target day (clock time preserved). The calendar
    /// plots published chips from these records. Returns false when the atom
    /// has no publish history — the caller falls back to rescheduling.
    @discardableResult
    static func moveRecords(atomUuid: String, to day: Date, calendar: Calendar = .current) async -> Bool {
        guard let atom = try? await AtomRepository.shared.fetch(uuid: atomUuid) else { return false }
        let existing = records(for: atom)
        guard !existing.isEmpty else { return false }
        let moved = existing.map { record -> ContentPublishRecord in
            var record = record
            let time = calendar.dateComponents([.hour, .minute, .second], from: record.publishedAtDate)
            let target = calendar.date(
                bySettingHour: time.hour ?? 12,
                minute: time.minute ?? 0,
                second: time.second ?? 0,
                of: day
            ) ?? day
            record.publishedAt = ISO8601.string(from: target)
            return record
        }
        let updated = atom.mergingMetadataKeys(Overlay(publishRecords: moved, status: "published"))
        _ = try? await AtomRepository.shared.update(updated)
        return true
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
        // Omitted when no transcript exists yet (nil keys don't merge, so an
        // earlier transcript set is never clobbered by a numbers-only pass).
        var topPerformingTranscripts: [String]?
    }

    /// Per-transcript cap — the dossier feeds agent context, not an archive.
    static let transcriptCharCap = 4000

    /// What the winning posts actually said: the published transcript
    /// (attached by the perf import) with the draft body as fallback,
    /// in top-post order. Pure — unit-tested.
    static func transcripts(forTop ids: [String], from atoms: [Atom]) -> [String] {
        let byUuid = Dictionary(uniqueKeysWithValues: atoms.map { ($0.uuid, $0) })
        return ids.compactMap { uuid -> String? in
            guard let atom = byUuid[uuid] else { return nil }
            let lens = atom.metadataValue(as: ContentTranscriptLens.self)
            let text = lens?.publishedTranscript?.isEmpty == false
                ? lens!.publishedTranscript!
                : (atom.body ?? "")
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return String(trimmed.prefix(transcriptCharCap))
        }
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
        let topTranscripts = transcripts(forTop: summary.topPerformingPostIds, from: contentAtoms)
        let updated = client.mergingMetadataKeys(Overlay(
            totalReach: summary.totalReach,
            avgEngagementRate: summary.avgEngagementRate,
            topPerformingPostIds: summary.topPerformingPostIds,
            topPerformingTranscripts: topTranscripts.isEmpty ? nil : topTranscripts
        ))
        _ = try? await AtomRepository.shared.update(updated)
    }
}
