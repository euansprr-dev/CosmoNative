// CosmoOS/Sync/CloudReconciliationService.swift
// One-shot cloud reconciliation: makes Supabase match this Mac's local truth.
//
// Why this exists (July 2026): the cloud accumulated years of rows the Mac
// could never see or correct, because the Mac's pull filters `_source neq mac`
// (its own rows never round-trip):
//   1. Unit-test fixtures — tests sandboxed the local DB but pushed through the
//      real authenticated SupabaseClient, so every test run wrote fixture atoms
//      ("Custom future title", "Project migration fixture …") into production.
//   2. Hard deletes (trash purge / permanentlyDelete) removed rows locally but
//      never touched the cloud row.
//   3. canvas_blocks were never change-tracked, so placements since the initial
//      migration exist only in local GRDB.
// A fresh iOS install pulled all of it. This service repairs the cloud once:
//
//   Step 1 — FULL RE-PUSH: upsert every local atom (including tombstones),
//            canvas_block, and the tombstone state implied by local truth, with
//            `updated_at` bumped to now so other devices' incremental pulls
//            pick everything up.
//   Step 2 — ORPHAN SWEEP: any cloud row owned by this Mac (`_source` = "mac"
//            or NULL) that no longer exists locally is tombstoned.
//
// Gated by an app_flags row (survives reinstalls of UserDefaults, matches the
// project-migration pattern) and attempted once per launch until it succeeds.
// The sweep only ever soft-deletes (reversible); it never hard-deletes.

import Foundation
import GRDB

@MainActor
enum CloudReconciliationService {

    private static let flagKey = "cloudReconciliationRan_v1"
    /// Set COSMO_RECON_DRY_RUN=1 to log what would change without writing.
    private static var isDryRun: Bool {
        ProcessInfo.processInfo.environment["COSMO_RECON_DRY_RUN"] == "1"
    }

    /// Cloud HARD REBUILD, requested via:
    ///   defaults write com.cosmo.CosmoOS cosmo.cloudHardRebuild -bool YES
    /// then launching the app. Tombstones EVERY cloud row the user owns (any
    /// `_source` — the sweep's mac-only predicate spared ghost rows last
    /// written by iOS/cloud) and re-pushes the Mac's full local truth on top.
    /// Rows that exist only in the cloud stay tombstoned; everything local
    /// comes back live. Never hard-deletes, never touches local data.
    private static let hardRebuildDefaultsKey = "cosmo.cloudHardRebuild"

    private static var attemptedThisLaunch = false
    // 50 keeps typical batch payloads comfortably inside slow-uplink timeouts;
    // upsertSplittingOnTimeout halves further when a batch still times out.
    private static let pushBatchSize = 50
    private static let sweepPageLimit = 1000
    private static let tombstoneBatchSize = 50
    /// Safety floor: an almost-empty local DB (fresh install mid-hydration)
    /// must never be treated as truth for the sweep.
    private static let minimumLocalAtomsForSweep = 25

    // MARK: - Entry

    /// Called from the sync cycle AFTER a pull, so local GRDB already contains
    /// every live iOS/cloud-originated row before we compare.
    static func runIfNeeded() async {
        guard SupabaseSyncTrafficPolicy.allowsNetworkSync else { return }
        guard !attemptedThisLaunch else { return }
        guard let client = SupabaseClient.shared, client.isAuthenticated,
              let userId = client.currentUserId else { return }

        // Explicitly requested hard rebuild takes precedence over the one-shot.
        if UserDefaults.standard.bool(forKey: hardRebuildDefaultsKey) {
            attemptedThisLaunch = true
            await runHardRebuild(client: client, userId: userId)
            return
        }

        let alreadyRan = (try? await CosmoDatabase.shared.asyncRead { db in
            try Row.fetchOne(db, sql: "SELECT value FROM app_flags WHERE key = ?", arguments: [flagKey]) != nil
        }) ?? false
        if alreadyRan { return }

        attemptedThisLaunch = true
        print("CloudReconciliation: starting\(isDryRun ? " (DRY RUN)" : "")")

        do {
            let pushedAtoms = try await repushAtoms(client: client, userId: userId)
            let pushedBlocks = try await repushCanvasBlocks(client: client, userId: userId)

            let sweptAtoms = try await sweepOrphans(table: "atoms", localUUIDs: localAtomUUIDs(), client: client)
            let sweptBlocks = try await sweepOrphans(table: "canvas_blocks", localUUIDs: localCanvasBlockUUIDs(), client: client)
            let sweptBoards = try await sweepOrphans(table: "swipe_boards", localUUIDs: localSwipeBoardUUIDs(), client: client)

            let summary = "atoms: \(pushedAtoms) pushed / \(sweptAtoms) tombstoned; canvas_blocks: \(pushedBlocks) pushed / \(sweptBlocks) tombstoned; swipe_boards: \(sweptBoards) tombstoned"
            print("CloudReconciliation: complete — \(summary)")

            if !isDryRun {
                try await CosmoDatabase.shared.asyncWrite { db in
                    try db.execute(
                        sql: "INSERT OR REPLACE INTO app_flags (key, value, updated_at) VALUES (?, '1', ?)",
                        arguments: [flagKey, ISO8601.string(from: Date())]
                    )
                }
            }
        } catch {
            // Flag stays unset — retried next launch. attemptedThisLaunch stops
            // hammering a broken connection within this session.
            PersistenceHealth.note(.syncFailure, context: "CloudReconciliation", detail: String(describing: error))
            print("CloudReconciliation: FAILED (will retry next launch) — \(error)")
        }
    }

    // MARK: - Hard rebuild

    private static func runHardRebuild(client: SupabaseClient, userId: String) async {
        print("CloudRebuild: starting — tombstoning ALL cloud rows, then re-pushing local truth")
        do {
            for table in ["atoms", "canvas_blocks", "swipe_boards"] {
                let count = try await tombstoneAllChunked(table: table, client: client)
                print("CloudRebuild: \(table) — \(count) live cloud row(s) tombstoned")
            }

            let atoms = try await repushAtoms(client: client, userId: userId)
            let blocks = try await repushCanvasBlocks(client: client, userId: userId)
            let boards = try await repushSwipeBoards(client: client, userId: userId)

            UserDefaults.standard.removeObject(forKey: hardRebuildDefaultsKey)
            // The regular one-shot is superseded by a rebuild.
            try await CosmoDatabase.shared.asyncWrite { db in
                try db.execute(
                    sql: "INSERT OR REPLACE INTO app_flags (key, value, updated_at) VALUES (?, '1', ?)",
                    arguments: [flagKey, ISO8601.string(from: Date())]
                )
            }
            print("CloudRebuild: complete — \(atoms) atoms, \(blocks) canvas blocks, \(boards) swipe boards live in cloud; everything else tombstoned")
        } catch {
            // Defaults key stays set — retried next launch. Tombstone-then-push
            // is idempotent, so a partial run is always safe to redo.
            PersistenceHealth.note(.syncFailure, context: "CloudRebuild", detail: String(describing: error))
            print("CloudRebuild: FAILED (will retry next launch) — \(error)")
        }
    }

    /// Tombstone every live cloud row in 50-uuid chunks. A single whole-table
    /// PATCH updates thousands of rows in one statement and trips Supabase's
    /// statement timeout (HTTP 500); the chunked PATCHes are the same machinery
    /// the orphan sweep already runs successfully.
    private static func tombstoneAllChunked(table: String, client: SupabaseClient) async throws -> Int {
        var liveUUIDs: [String] = []
        var offset = 0
        while true {
            let page = try await client.fetchColumns(
                table: table,
                columns: ["uuid", "is_deleted"],
                limit: sweepPageLimit,
                offset: offset
            )
            if page.isEmpty { break }
            for row in page {
                guard let uuid = row["uuid"] as? String, !uuid.isEmpty else { continue }
                let isDeleted = (row["is_deleted"] as? Bool) ?? ((row["is_deleted"] as? Int) == 1)
                if !isDeleted { liveUUIDs.append(uuid) }
            }
            if page.count < sweepPageLimit { break }
            offset += page.count
        }

        for chunkStart in stride(from: 0, to: liveUUIDs.count, by: tombstoneBatchSize) {
            let chunk = Array(liveUUIDs[chunkStart..<min(chunkStart + tombstoneBatchSize, liveUUIDs.count)])
            try await client.batchSoftDelete(table: table, uuids: chunk)
        }
        return liveUUIDs.count
    }

    private static func repushSwipeBoards(client: SupabaseClient, userId: String) async throws -> Int {
        let rows = try await CosmoDatabase.shared.asyncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT uuid, name, icon, tintToken, sortOrder, isArchived, createdAt, updatedAt
                FROM swipe_boards
                ORDER BY uuid ASC
            """)
        }
        guard !rows.isEmpty else { return 0 }

        let now = ISO8601.string(from: Date())
        // Payload shape mirrors SwipeBoardStore.syncBoardToCloud, plus a bumped
        // snake_case updated_at so pull cursors pick the rows up.
        // Typed GRDB subscripts — see repushAtoms note (Int64 vs `as? Int`).
        let payloads = rows.map { row -> [String: Any] in
            [
                "uuid": row["uuid"] as String? ?? "",
                "name": row["name"] as String? ?? "",
                "icon": row["icon"] as String? ?? "",
                "tintToken": (row["tintToken"] as String?).map { $0 as Any } ?? NSNull(),
                "sortOrder": row["sortOrder"] as Int? ?? 0,
                "isArchived": row["isArchived"] as Bool? ?? false,
                "createdAt": row["createdAt"] as String? ?? now,
                "updatedAt": row["updatedAt"] as String? ?? now,
                "updated_at": now,
                "is_deleted": false,
                "user_id": userId,
                "_source": "mac",
            ]
        }
        try await client.batchUpsert(table: "swipe_boards", records: payloads, onConflict: "uuid")
        return payloads.count
    }

    // MARK: - Step 1: full re-push

    private static func repushAtoms(client: SupabaseClient, userId: String) async throws -> Int {
        var offset = 0
        var pushed = 0
        let now = ISO8601.string(from: Date())

        while true {
            let rows = try await CosmoDatabase.shared.asyncRead { db in
                try Row.fetchAll(db, sql: """
                    SELECT uuid, type, title, body, structured, metadata, links,
                           created_at, updated_at, is_deleted, _local_version
                    FROM atoms
                    ORDER BY uuid ASC
                    LIMIT ? OFFSET ?
                """, arguments: [pushBatchSize, offset])
            }
            if rows.isEmpty { break }

            // NOTE: numeric/bool columns MUST use GRDB's typed subscript
            // (`as Int?` / `as Bool?`), never `as? Int` — GRDB stores SQLite
            // integers as Int64 and the `as?` cast silently fails, which once
            // pushed every local tombstone to the cloud as is_deleted = false,
            // resurrecting months of deleted rows on every rebuild.
            let payloads = rows.map { row -> [String: Any] in
                [
                    "uuid": row["uuid"] as String? ?? "",
                    "type": row["type"] as String? ?? "",
                    "title": (row["title"] as String?).map { $0 as Any } ?? NSNull(),
                    "body": (row["body"] as String?).map { $0 as Any } ?? NSNull(),
                    "structured": jsonValue(row["structured"] as String?),
                    "metadata": jsonValue(row["metadata"] as String?),
                    "links": jsonValue(row["links"] as String?),
                    "created_at": row["created_at"] as String? ?? now,
                    // Bumped: other devices pull incrementally by updated_at.
                    "updated_at": now,
                    "is_deleted": row["is_deleted"] as Bool? ?? false,
                    "user_id": userId,
                    "_version": row["_local_version"] as Int? ?? 1,
                    "_source": "mac",
                ]
            }

            if !isDryRun {
                try await upsertSplittingOnTimeout(table: "atoms", records: payloads, client: client)
            }
            pushed += payloads.count
            offset += rows.count
        }
        return pushed
    }

    /// Batch upsert that survives timeouts of BOTH kinds: Postgres statement
    /// timeouts (57014 — large atoms make a 100-row batch exceed the server's
    /// statement limit) and client network timeouts (slow uplink, megabyte
    /// payloads). On timeout, split the batch in half and recurse — smaller
    /// batches are cheaper on both sides. A single row that still times out is
    /// retried once before giving up.
    private static func upsertSplittingOnTimeout(
        table: String,
        records: [[String: Any]],
        client: SupabaseClient,
        isRetry: Bool = false
    ) async throws {
        guard !records.isEmpty else { return }
        do {
            try await client.batchUpsert(table: table, records: records, onConflict: "uuid")
        } catch {
            guard isTimeout(error) else { throw error }

            if records.count > 1 {
                let mid = records.count / 2
                try await upsertSplittingOnTimeout(table: table, records: Array(records[..<mid]), client: client)
                try await upsertSplittingOnTimeout(table: table, records: Array(records[mid...]), client: client)
            } else if !isRetry {
                try await Task.sleep(for: .seconds(3))
                try await upsertSplittingOnTimeout(table: table, records: records, client: client, isRetry: true)
            } else {
                throw error
            }
        }
    }

    private static func isTimeout(_ error: Error) -> Bool {
        if case .upsertFailed(_, let body)? = error as? SupabaseError, body.contains("57014") {
            return true
        }
        if let urlError = error as? URLError {
            return urlError.code == .timedOut || urlError.code == .networkConnectionLost
        }
        return false
    }

    private static func repushCanvasBlocks(client: SupabaseClient, userId: String) async throws -> Int {
        var offset = 0
        var pushed = 0
        let now = ISO8601.string(from: Date())

        while true {
            let rows = try await CosmoDatabase.shared.asyncRead { db in
                try Row.fetchAll(db, sql: """
                    SELECT id, uuid, entity_uuid, entity_id, entity_type, entity_title,
                           thinkspace_id, position_x, position_y, width, height, z_index,
                           is_collapsed, is_pinned, document_type, document_id, document_uuid,
                           zone, note_content, is_deleted, created_at, updated_at
                    FROM canvas_blocks
                    ORDER BY id ASC
                    LIMIT ? OFFSET ?
                """, arguments: [pushBatchSize, offset])
            }
            if rows.isEmpty { break }

            // Placement-id keying (one cloud row per placement) via the shared
            // payload builder, plus reconciliation-specific fields: bumped
            // updated_at (so incremental pulls fetch it), user_id, and an
            // explicit _source — historically omitted, leaving NULL _source
            // rows that `_source=neq.ios` pulls silently exclude (NULL never
            // matches neq).
            let payloads = rows.compactMap { row -> [String: Any]? in
                guard var payload = CanvasBlockRecord.cloudSyncPayload(row: row) else { return nil }
                payload["updated_at"] = now
                payload["user_id"] = userId
                payload["_source"] = "mac"
                return payload
            }

            if !isDryRun {
                try await upsertSplittingOnTimeout(table: "canvas_blocks", records: payloads, client: client)
            }
            pushed += payloads.count
            offset += rows.count
        }
        return pushed
    }

    // MARK: - Step 2: orphan sweep

    /// Tombstone cloud rows owned by this Mac that no longer exist locally.
    /// Ownership = `_source` "mac" or NULL (pre-_source migration rows were all
    /// Mac-authored). iOS/cloud-authored rows are never touched.
    private static func sweepOrphans(
        table: String,
        localUUIDs: Set<String>,
        client: SupabaseClient
    ) async throws -> Int {
        guard localUUIDs.count >= (table == "atoms" ? minimumLocalAtomsForSweep : 0) else {
            print("CloudReconciliation: skipping \(table) sweep — only \(localUUIDs.count) local rows (safety floor)")
            return 0
        }

        var orphans: [String] = []
        var offset = 0
        while true {
            let page = try await client.fetchColumns(
                table: table,
                columns: ["uuid", "_source", "is_deleted"],
                limit: sweepPageLimit,
                offset: offset
            )
            if page.isEmpty { break }

            for row in page {
                guard let uuid = row["uuid"] as? String, !uuid.isEmpty else { continue }
                let source = row["_source"] as? String
                let isDeleted = (row["is_deleted"] as? Bool) ?? ((row["is_deleted"] as? Int) == 1)
                let macOwned = source == nil || source == SupabaseSyncTrafficPolicy.localSource
                if macOwned && !isDeleted && !localUUIDs.contains(uuid) {
                    orphans.append(uuid)
                }
            }

            if page.count < sweepPageLimit { break }
            offset += page.count
        }

        guard !orphans.isEmpty else { return 0 }
        print("CloudReconciliation: \(table) — tombstoning \(orphans.count) cloud orphan(s)")

        if !isDryRun {
            for chunk in stride(from: 0, to: orphans.count, by: tombstoneBatchSize).map({
                Array(orphans[$0..<min($0 + tombstoneBatchSize, orphans.count)])
            }) {
                try await client.batchSoftDelete(table: table, uuids: chunk)
            }
        }
        return orphans.count
    }

    // MARK: - Local UUID sets

    private static func localAtomUUIDs() async throws -> Set<String> {
        // Includes soft-deleted rows: they exist locally as tombstones and are
        // re-pushed as such — not orphans.
        let uuids = try await CosmoDatabase.shared.asyncRead { db in
            try String.fetchAll(db, sql: "SELECT uuid FROM atoms")
        }
        return Set(uuids)
    }

    private static func localCanvasBlockUUIDs() async throws -> Set<String> {
        // Cloud key = local placement `id` (matches CanvasBlockRecord.cloudSyncPayload).
        // Old entity-uuid-keyed cloud rows deliberately won't match — they are
        // stale collapsed placements and get tombstoned by the sweep.
        let ids = try await CosmoDatabase.shared.asyncRead { db in
            try String.fetchAll(db, sql: "SELECT id FROM canvas_blocks")
        }
        return Set(ids)
    }

    private static func localSwipeBoardUUIDs() async throws -> Set<String> {
        let uuids = try await CosmoDatabase.shared.asyncRead { db in
            try String.fetchAll(db, sql: "SELECT uuid FROM swipe_boards")
        }
        return Set(uuids)
    }

    // MARK: - Helpers

    private static func jsonValue(_ jsonString: String?) -> Any {
        guard let jsonString, !jsonString.isEmpty else { return NSNull() }
        guard let data = jsonString.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) else {
            return jsonString
        }
        return parsed
    }
}
