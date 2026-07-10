// CosmoOS/Data/Models/AtomRevision.swift
// Local-only version history for atoms. Every risky write path snapshots the
// pre-image row into atom_revisions BEFORE overwriting it, so a bad AI apply,
// a sync stomp, or a plain editing accident is always recoverable.
// Revisions never sync and never appear in search.
// July 2026

import Foundation
import GRDB

// MARK: - Revision Source

/// What kind of write produced (i.e. replaced) the snapshotted state.
enum RevisionSource: String, Codable, Sendable, CaseIterable {
    /// A normal user edit through any editor surface.
    case userEdit = "user_edit"
    /// An inline-assistant / agent apply overwrote the content.
    case aiApply = "ai_apply"
    /// A remote (Supabase) change was applied over the local row.
    case syncApply = "sync_apply"
    /// The user restored an older revision (the replaced current state).
    case restore = "restore"
    /// The atom was soft-deleted; this is its final content.
    case preDelete = "pre_delete"

    var displayName: String {
        switch self {
        case .userEdit: return "You"
        case .aiApply: return "Cosmo"
        case .syncApply: return "Sync"
        case .restore: return "Restore"
        case .preDelete: return "Deleted"
        }
    }

    var icon: String {
        switch self {
        case .userEdit: return "pencil"
        case .aiApply: return "sparkles"
        case .syncApply: return "arrow.triangle.2.circlepath"
        case .restore: return "clock.arrow.circlepath"
        case .preDelete: return "trash"
        }
    }
}

// MARK: - Atom Revision Record

/// A full pre-image copy of an atom row at a point in time.
struct AtomRevision: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "atom_revisions"

    var id: Int64?
    var atomUuid: String
    var type: String
    var title: String?
    var body: String?
    var structured: String?
    var metadata: String?
    var links: String?
    var localVersion: Int64
    var source: String
    var createdAt: String

    enum CodingKeys: String, ColumnExpression, CodingKey {
        case id
        case atomUuid = "atom_uuid"
        case type, title, body, structured, metadata, links
        case localVersion = "local_version"
        case source
        case createdAt = "created_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var revisionSource: RevisionSource {
        RevisionSource(rawValue: source) ?? .userEdit
    }

    var createdAtDate: Date {
        ISO8601.date(from: createdAt) ?? .distantPast
    }

    init(of atom: Atom, source: RevisionSource, createdAt: Date = Date()) {
        self.id = nil
        self.atomUuid = atom.uuid
        self.type = atom.type.rawValue
        self.title = atom.title
        self.body = AtomRevisionPolicy.cappedBody(atom.body)
        self.structured = atom.structured
        self.metadata = atom.metadata
        self.links = atom.links
        self.localVersion = atom.localVersion
        self.source = source.rawValue
        self.createdAt = ISO8601.string(from: createdAt)
    }
}

// MARK: - Snapshot Policy

/// Pure decision logic for when a write should leave a revision behind.
/// Kept side-effect free so the rules are unit-testable.
enum AtomRevisionPolicy {
    /// Content-bearing atom types worth versioning. Tasks, habits, schedule
    /// blocks, and other operational rows churn constantly and are excluded.
    static let eligibleTypes: Set<AtomType> = [
        .note, .content, .idea, .connection, .research, .stickyNote,
    ]

    /// Minimum age of the newest revision before a plain user edit snapshots again.
    static let minUserEditInterval: TimeInterval = 300 // 5 minutes

    /// A body change bigger than this snapshots regardless of the interval.
    static let minLargeBodyDelta = 200 // characters

    /// Stored body cap — pathological bodies are truncated, not dropped.
    static let maxStoredBodyLength = 2_000_000 // characters

    static func isEligible(_ atom: Atom) -> Bool {
        eligibleTypes.contains(atom.type)
    }

    /// Whether replacing `previous` with `incoming` should snapshot `previous` first.
    static func shouldSnapshot(
        previous: Atom,
        incoming: Atom,
        source: RevisionSource,
        lastRevisionAt: Date?,
        now: Date = Date()
    ) -> Bool {
        guard isEligible(previous) else { return false }

        let contentChanged =
            previous.title != incoming.title
            || previous.body != incoming.body
            || previous.structured != incoming.structured

        switch source {
        case .preDelete:
            // Always keep the final content of a deleted atom (if it has any).
            return (previous.body?.isEmpty == false) || (previous.title?.isEmpty == false)
        case .aiApply, .syncApply, .restore:
            // The scary paths always snapshot when they actually change content.
            return contentChanged
        case .userEdit:
            guard contentChanged else { return false }
            guard let last = lastRevisionAt else { return true }
            if now.timeIntervalSince(last) >= minUserEditInterval { return true }
            let previousLength = previous.body?.count ?? 0
            let incomingLength = incoming.body?.count ?? 0
            return abs(previousLength - incomingLength) >= minLargeBodyDelta
        }
    }

    static func cappedBody(_ body: String?) -> String? {
        guard let body, body.count > maxStoredBodyLength else { return body }
        return String(body.prefix(maxStoredBodyLength)) + "\n…[truncated]"
    }
}

// MARK: - Revision Writer

/// Database-level helpers shared by every write path (repository, sync apply).
/// All functions run inside the caller's transaction so a snapshot and the
/// write that follows it are atomic.
enum AtomRevisionWriter {
    /// True once the migration has run — guards writes during first launch on
    /// an older database and makes the helpers safe to call from any path.
    private static func tableExists(_ db: Database) -> Bool {
        (try? db.tableExists(AtomRevision.databaseTableName)) ?? false
    }

    static func lastRevisionDate(_ db: Database, atomUuid: String) throws -> Date? {
        guard tableExists(db) else { return nil }
        let iso = try String.fetchOne(
            db,
            sql: "SELECT created_at FROM atom_revisions WHERE atom_uuid = ? ORDER BY created_at DESC LIMIT 1",
            arguments: [atomUuid]
        )
        return iso.flatMap { ISO8601.date(from: $0) }
    }

    /// Snapshot `previous` if the policy says the incoming write warrants it.
    /// Never throws upward on failure — losing a snapshot must not block a save.
    static func snapshotIfNeeded(
        _ db: Database,
        previous: Atom,
        incoming: Atom,
        source: RevisionSource
    ) {
        guard tableExists(db) else { return }
        do {
            guard AtomRevisionPolicy.isEligible(previous) else { return }
            let last = try lastRevisionDate(db, atomUuid: previous.uuid)
            guard AtomRevisionPolicy.shouldSnapshot(
                previous: previous, incoming: incoming, source: source, lastRevisionAt: last
            ) else { return }
            var revision = AtomRevision(of: previous, source: source)
            try revision.insert(db)
        } catch {
            print("AtomRevisionWriter: snapshot failed for \(previous.uuid.prefix(8)): \(error)")
        }
    }

    /// Unconditional snapshot (pre-delete, pre-restore). Same never-block contract.
    static func snapshot(_ db: Database, of atom: Atom, source: RevisionSource) {
        guard tableExists(db) else { return }
        guard AtomRevisionPolicy.isEligible(atom) else { return }
        if source == .preDelete,
           (atom.body?.isEmpty ?? true) && (atom.title?.isEmpty ?? true) {
            return
        }
        do {
            var revision = AtomRevision(of: atom, source: source)
            try revision.insert(db)
        } catch {
            print("AtomRevisionWriter: snapshot failed for \(atom.uuid.prefix(8)): \(error)")
        }
    }

    /// Snapshot the current local row for `uuid` before a remote/sync write
    /// replaces it. Used by the sync apply paths, which write raw SQL.
    static func snapshotBeforeRemoteApply(_ db: Database, uuid: String) {
        guard tableExists(db) else { return }
        do {
            guard let previous = try Atom
                .filter(Atom.CodingKeys.uuid == uuid)
                .filter(Atom.CodingKeys.isDeleted == false)
                .fetchOne(db),
                AtomRevisionPolicy.isEligible(previous)
            else { return }
            // Remote applies always snapshot (the whole point is surviving stomps),
            // but dedupe against an identical snapshot taken moments ago.
            if let last = try AtomRevision
                .filter(AtomRevision.CodingKeys.atomUuid == uuid)
                .order(AtomRevision.CodingKeys.createdAt.desc)
                .fetchOne(db),
               last.body == AtomRevisionPolicy.cappedBody(previous.body),
               last.title == previous.title,
               last.structured == previous.structured {
                return
            }
            var revision = AtomRevision(of: previous, source: .syncApply)
            try revision.insert(db)
        } catch {
            print("AtomRevisionWriter: pre-sync snapshot failed for \(uuid.prefix(8)): \(error)")
        }
    }
}

// MARK: - Pruning Policy

/// Tiered retention: everything for a day, hourly for a week, daily for
/// 90 days, weekly forever, hard cap per atom. Pure so the tiers are testable.
enum AtomRevisionPruningPolicy {
    static let hardCapPerAtom = 200

    /// Given revision timestamps for ONE atom (any order), returns the set of
    /// array indices to KEEP. `preDeleteIndices` are always kept (newest final
    /// content of deleted atoms must survive).
    static func indicesToKeep(
        createdAt: [Date],
        preDeleteIndices: Set<Int> = [],
        now: Date = Date()
    ) -> Set<Int> {
        let sorted = createdAt.enumerated().sorted { $0.element > $1.element }
        var keep = Set<Int>()
        var hourBuckets = Set<Int>()
        var dayBuckets = Set<Int>()
        var weekBuckets = Set<Int>()

        for (index, date) in sorted {
            if keep.count >= hardCapPerAtom { break }
            let age = now.timeIntervalSince(date)
            if age < 86_400 {
                keep.insert(index)
            } else if age < 7 * 86_400 {
                let bucket = Int(date.timeIntervalSince1970 / 3_600)
                if !hourBuckets.contains(bucket) {
                    hourBuckets.insert(bucket)
                    keep.insert(index)
                }
            } else if age < 90 * 86_400 {
                let bucket = Int(date.timeIntervalSince1970 / 86_400)
                if !dayBuckets.contains(bucket) {
                    dayBuckets.insert(bucket)
                    keep.insert(index)
                }
            } else {
                let bucket = Int(date.timeIntervalSince1970 / (7 * 86_400))
                if !weekBuckets.contains(bucket) {
                    weekBuckets.insert(bucket)
                    keep.insert(index)
                }
            }
        }

        keep.formUnion(preDeleteIndices)
        return keep
    }
}

// MARK: - Pruner

/// Daily maintenance: applies the retention tiers per atom.
enum AtomRevisionPruner {
    private static let lastRunKey = "atomRevisions.lastPruneAt"

    /// Runs at most once per day; cheap no-op otherwise.
    static func pruneIfDue(database: CosmoDatabase = .shared, now: Date = Date()) async {
        let last = UserDefaults.standard.double(forKey: lastRunKey)
        guard now.timeIntervalSince1970 - last >= 86_400 else { return }
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: lastRunKey)

        do {
            try await database.asyncWrite { db in
                guard (try? db.tableExists(AtomRevision.databaseTableName)) ?? false else { return }
                let uuids = try String.fetchAll(
                    db, sql: "SELECT DISTINCT atom_uuid FROM atom_revisions"
                )
                for uuid in uuids {
                    let revisions = try AtomRevision
                        .filter(AtomRevision.CodingKeys.atomUuid == uuid)
                        .fetchAll(db)
                    guard revisions.count > 1 else { continue }
                    let dates = revisions.map(\.createdAtDate)
                    let preDelete = Set(revisions.indices.filter {
                        revisions[$0].revisionSource == .preDelete
                    })
                    let keep = AtomRevisionPruningPolicy.indicesToKeep(
                        createdAt: dates, preDeleteIndices: preDelete, now: now
                    )
                    let dropIds = revisions.indices
                        .filter { !keep.contains($0) }
                        .compactMap { revisions[$0].id }
                    if !dropIds.isEmpty {
                        try AtomRevision.deleteAll(db, keys: dropIds)
                    }
                }
            }
        } catch {
            print("AtomRevisionPruner: prune failed: \(error)")
        }
    }
}
