// CosmoOS/Sync/SyncEngine.swift
// Bulletproof local-first sync with invisible background uploads
// Phase 0+1: Unified atoms table sync with Supabase Realtime readiness
// UI NEVER blocks - all sync happens in background

import Foundation
import Combine
import GRDB

@MainActor
class SyncEngine: ObservableObject {
    static let shared = SyncEngine()

    // MARK: - Published State (UI-safe)
    @Published private(set) var syncState: SyncState = .idle
    @Published private(set) var pendingChanges: Int = 0
    @Published private(set) var lastSyncTime: Date?
    @Published private(set) var isOnline: Bool = true

    // MARK: - Private Dependencies
    private let database = CosmoDatabase.shared
    private let networkMonitor = NetworkMonitor.shared
    private let conflictResolver = ConflictResolver()
    private let changeTracker = ChangeTracker.shared
    private let supabaseClient: SupabaseClient?

    private var syncTimer: Timer?
    private var realtimeSubscription: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    nonisolated deinit {
        // Timer and Task cleanup handled by ARC / cancellation
    }

    // MARK: - Configuration
    // Phase 1: Polling reduced to 5 minutes (fallback for missed Realtime events)
    // RealtimeSyncService handles instant cloud→local updates
    private let syncInterval: TimeInterval = 300 // 5 minutes (was 30s before Realtime)
    private let maxRetries = 3
    private let fenceExpiryMs: Int64 = 30_000
    private let extendedFenceExpiryMs: Int64 = 120_000
    private let pullPageLimit = 100
    /// Overlap subtracted from the pull cursor so rows committed in the same
    /// second as the last pulled row are never skipped.
    private let pullCursorOverlap: TimeInterval = 2
    /// Failed pushes are re-queued for retry after this cool-down (slow cadence, indefinite).
    private let failedPushRequeueDelay: TimeInterval = 600 // 10 minutes

    // MARK: - Sync Tables (unified)
    // Push: atoms + canvas_blocks go UP to Supabase
    // Pull: atoms AND canvas_blocks come DOWN — both filtered `_source neq mac`,
    // so Mac-originated rows never round-trip. iOS-placed blocks land in GRDB
    // and appear on the canvas via SpatialEngine's thinkspace_id query on open.
    // graph_edges are derived from atom.links and rebuilt by NodeGraphEngine — no sync needed
    private let pushTables = ["atoms", "canvas_blocks", "canvas_drawings"]
    private let pullTables = [
        "atoms", "canvas_blocks", "swipe_boards", "canvas_drawings",
        // Inbox domain (July 2026): iPhone captures, lanes, and lane captures
        // flow in; classification/triage updates flow back out via the queue.
        "inbox_items", "capture_destinations", "captured_items",
        // Physical capture (July 2026): page-scan/photo attachment records
        // captured on the iPhone flow in; transcription updates flow back.
        "media_attachments",
        // Camera relay: status/pageCount updates flow back as the phone
        // fulfills this Mac's scan requests.
        "capture_requests",
        // The global Seedbed (July 2026): seedlings fed/renamed/pinned on the
        // phone flow in; this Mac's router feeds and develop-settles flow out.
        "seedlings",
    ]

    private init() {
        supabaseClient = SupabaseClient.shared
        setupNetworkObserver()
        startBackgroundSync()
        print("✅ SyncEngine initialized (local-first, unified atoms sync)")
    }

    // MARK: - Network Observer
    private func setupNetworkObserver() {
        networkMonitor.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                self?.isOnline = isConnected
                if isConnected {
                    Task { @MainActor in
                        await self?.syncPendingChanges()
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Background Sync
    private func startBackgroundSync() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performBackgroundSync()
            }
        }

        // Initial sync after a short delay
        Task {
            try? await Task.sleep(for: .seconds(2))
            await performBackgroundSync()
        }
    }

    private func performBackgroundSync() async {
        guard isOnline, syncState != .syncing else { return }

        // Don't sync if not authenticated — RLS will block everything
        guard let client = supabaseClient, client.isAuthenticated else { return }

        // Refresh auth token before sync to prevent JWT expired errors
        await SupabaseAuthService.shared.refreshSessionIfNeeded()
        guard SupabaseSyncTrafficPolicy.shouldAttemptPush(isAuthenticated: client.isAuthenticated) else { return }

        // FIX 5: Housekeeping — remove expired sync fences to prevent unbounded table growth
        await cleanupExpiredFences()

        // iOS companion ext 2: one-shot push of existing boards to the cloud.
        await SwipeBoardStore.shared.backfillCloudBoardsIfNeeded()

        // iOS companion ext 3a: mirror cached swipe thumbnails to Supabase
        // Storage (throttled, once per launch) so the iPhone renders real cards.
        await SwipeThumbnailCloudMirror.runBackfillPassIfNeeded()

        // Swipe media v2: reels/videos + every carousel page mirror to Storage
        // so the iPhone gets the full swipe experience. The coordinator drains
        // the backlog continuously (non-blocking); this kick is a no-op when
        // there's nothing left.
        SwipeMediaMirrorCoordinator.kick()

        // Physical capture: mirror page-scan/photo attachment blobs to
        // Storage so the other device can render originals, and finish any
        // transcriptions the iPhone left for this Mac. No-ops when idle.
        AttachmentCloudStore.kick()
        AttachmentTranscriptionWorker.kick()

        // Drawings sync: one-shot enqueue of every drawing created before the
        // CanvasDrawingSyncObserver existed — without this, historical
        // annotations never reach the cloud or the iPhone.
        await backfillCanvasDrawingsIfNeeded()

        // Inbox domain: one-shot enqueue of every capture, lane, and lane
        // capture created before the Inbox became a synced domain (July 2026)
        // — without this, the Mac's existing inbox never reaches the cloud or
        // the iPhone.
        await backfillInboxDomainIfNeeded()

        syncState = .syncing

        // 0. Heal orphaned pending rows BEFORE the push reads the queue, so any
        // row whose _local_pending shield is up but has no queue row (stranded
        // in both directions) gets re-enqueued and pushed in this same cycle.
        await requeueOrphanedPendingRows()

        // 1. Push local changes
        await syncPendingChanges()

        // 2. Pull remote changes
        await pullRemoteChanges()

        // 3. One-shot catch-up: convert any inbox-capture atoms that were pulled
        // before this fix shipped (they're in GRDB but never became InboxItems).
        await runInboxCatchupMigrationIfNeeded()

        // 4. One-shot cloud reconciliation: full re-push of local truth + sweep
        // of cloud rows this Mac deleted (or that tests leaked) — runs AFTER a
        // pull so live iOS-originated rows are in GRDB before comparing.
        await CloudReconciliationService.runIfNeeded()

        // Update state
        lastSyncTime = Date()
        syncState = .idle
    }

    // MARK: - Canvas Drawings Backfill

    /// One-shot: enqueue every existing (pre-observer) canvas drawing for
    /// cloud push. Flag-gated in app_flags so it survives UserDefaults resets.
    private func backfillCanvasDrawingsIfNeeded() async {
        let flagKey = "canvas_drawings_backfill_v1"
        do {
            let done = try await database.asyncRead { db in
                try Row.fetchOne(db, sql: "SELECT value FROM app_flags WHERE key = ?", arguments: [flagKey]) != nil
            }
            guard !done else { return }

            try await database.asyncWrite { db in
                let rows = try Row.fetchAll(db, sql: "SELECT * FROM canvas_drawings WHERE is_deleted = 0")
                for row in rows {
                    guard let payload = CanvasDrawingRecord.cloudSyncPayload(row: row),
                          let cloudKey = payload["uuid"] as? String,
                          let json = try? JSONSerialization.data(withJSONObject: payload),
                          let jsonString = String(data: json, encoding: .utf8) else { continue }
                    let pending = try Row.fetchOne(
                        db,
                        sql: "SELECT 1 FROM sync_queue WHERE uuid = ? AND table_name = 'canvas_drawings' AND status = 'pending'",
                        arguments: [cloudKey]
                    )
                    guard pending == nil else { continue }
                    try db.execute(
                        sql: """
                        INSERT INTO sync_queue (uuid, table_name, row_id, operation, data, local_version, status)
                        VALUES (?, 'canvas_drawings', NULL, 'INSERT', ?, ?, 'pending')
                        """,
                        arguments: [cloudKey, jsonString, row["_local_version"] as Int? ?? 1]
                    )
                }
                try db.execute(
                    sql: "INSERT OR REPLACE INTO app_flags (key, value, updated_at) VALUES (?, '1', ?)",
                    arguments: [flagKey, ISO8601.string(from: Date())]
                )
                print("🖊️ Canvas drawings backfill enqueued \(rows.count) drawing(s)")
            }
        } catch {
            PersistenceHealth.note(.syncFailure, context: "SyncEngine.backfillCanvasDrawings", detail: String(describing: error))
        }
    }

    // MARK: - Inbox Domain Backfill

    /// One-shot: enqueue every live inbox item, capture lane, and lane capture
    /// for cloud push. Rows created before the Inbox became a synced domain
    /// (July 2026) were never change-tracked, so without this they exist only
    /// in local GRDB and a signed-in iPhone sees an empty inbox. Flag-gated in
    /// app_flags (survives UserDefaults resets, matches the drawings backfill).
    private func backfillInboxDomainIfNeeded() async {
        let flagKey = "inbox_domain_backfill_v1"
        do {
            let done = try await database.asyncRead { db in
                try Row.fetchOne(db, sql: "SELECT value FROM app_flags WHERE key = ?", arguments: [flagKey]) != nil
            }
            guard !done else { return }

            let encoder = JSONEncoder()
            try await database.asyncWrite { db in
                let now = ISO8601.string(from: Date())
                var enqueued = 0

                // Skip rows that already have a pending queue entry (a tracked
                // mutation may have raced this backfill) — queueChange's
                // uuid+table dedupe, applied here.
                func enqueue(uuid: String, table: String, localVersion: Int64, json: String) throws {
                    let pending = try Row.fetchOne(
                        db,
                        sql: "SELECT 1 FROM sync_queue WHERE uuid = ? AND table_name = ? AND status = 'pending'",
                        arguments: [uuid, table]
                    )
                    guard pending == nil else { return }
                    try db.execute(
                        sql: """
                        INSERT INTO sync_queue (uuid, table_name, row_id, operation, data, local_version, status)
                        VALUES (?, ?, NULL, 'INSERT', ?, ?, 'pending')
                        """,
                        arguments: [uuid, table, json, localVersion]
                    )
                    enqueued += 1
                }

                // Live rows only: tombstones of never-pushed rows have nothing
                // to delete in the cloud. updated_at is bumped so other devices'
                // incremental pull cursors pick the rows up (the reconciliation
                // precedent), and the refetched models carry it in the payload.
                for table in ["inbox_items", "capture_destinations", "captured_items"] {
                    try db.execute(
                        sql: "UPDATE \(table) SET updated_at = ? WHERE is_deleted = 0",
                        arguments: [now]
                    )
                }

                for item in try InboxItem.fetchAll(db, sql: "SELECT * FROM inbox_items WHERE is_deleted = 0") {
                    guard let data = try? encoder.encode(item),
                          let json = String(data: data, encoding: .utf8) else { continue }
                    try enqueue(uuid: item.uuid, table: "inbox_items", localVersion: item.localVersion, json: json)
                }
                for lane in try CaptureDestination.fetchAll(db, sql: "SELECT * FROM capture_destinations WHERE is_deleted = 0") {
                    guard let data = try? encoder.encode(lane),
                          let json = String(data: data, encoding: .utf8) else { continue }
                    try enqueue(uuid: lane.uuid, table: "capture_destinations", localVersion: lane.localVersion, json: json)
                }
                for capture in try CapturedItem.fetchAll(db, sql: "SELECT * FROM captured_items WHERE is_deleted = 0") {
                    guard let data = try? encoder.encode(capture),
                          let json = String(data: data, encoding: .utf8) else { continue }
                    try enqueue(uuid: capture.uuid, table: "captured_items", localVersion: capture.localVersion, json: json)
                }

                try db.execute(
                    sql: "INSERT OR REPLACE INTO app_flags (key, value, updated_at) VALUES (?, '1', ?)",
                    arguments: [flagKey, now]
                )
                print("📥 Inbox domain backfill enqueued \(enqueued) row(s) for cloud push")
            }
        } catch {
            PersistenceHealth.note(.syncFailure, context: "SyncEngine.backfillInboxDomain", detail: String(describing: error))
        }
    }

    // MARK: - Inbox Catch-Up Migration
    /// Recovers cloud inbox captures that were pulled into GRDB before the
    /// batch-pull path learned how to convert them. Runs once per install.
    private func runInboxCatchupMigrationIfNeeded() async {
        let key = "inboxCatchupMigrationRan_v2"
        if UserDefaults.standard.bool(forKey: key) { return }

        // Only rows the converter can actually act on: it permanently skips
        // empty captures, so those must not hold the flag open forever.
        let rows: [[String: Any]]? = try? await database.asyncRead { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT uuid, body, title, metadata, is_deleted
                FROM atoms
                WHERE is_deleted = 0
                  AND (
                    metadata LIKE '%"isInboxCapture":true%'
                    OR metadata LIKE '%"isCaptureLaneCapture":true%'
                  )
                  AND (TRIM(COALESCE(body, '')) <> '' OR TRIM(COALESCE(title, '')) <> '')
                """
            )
            return rows.map { row -> [String: Any] in
                var dict: [String: Any] = [:]
                for name in ["uuid", "body", "title", "metadata"] {
                    if let s: String = row[name] { dict[name] = s }
                }
                dict["is_deleted"] = (row["is_deleted"] as Int?) ?? 0
                return dict
            }
        }

        // Read failed — don't claim the migration ran.
        guard let rows else { return }

        if rows.isEmpty {
            // Nothing left to convert — the catch-up genuinely completed.
            UserDefaults.standard.set(true, forKey: key)
            return
        }

        print("📥 SyncEngine: inbox catch-up migration processing \(rows.count) stuck capture(s)")
        for row in rows {
            guard let uuid = row["uuid"] as? String else { continue }
            await InboxCaptureConverter.convertIfInboxCapture(uuid: uuid, atomData: row)
        }

        // The converter soft-deletes each transport atom it consumed, so successes
        // drop out of the query above. The one-shot flag is deliberately NOT set
        // here: the next sync cycle re-checks, and only an empty result marks
        // completion — failed conversions keep retrying instead of being orphaned.
    }

    // MARK: - Push Local Changes (Invisible)
    private func syncPendingChanges() async {
        guard isOnline else { return }
        guard let client = supabaseClient,
              SupabaseSyncTrafficPolicy.shouldAttemptPush(isAuthenticated: client.isAuthenticated) else {
            print("⏸️ Sync push paused — Supabase auth unavailable")
            return
        }

        // Give permanently-failed pushes another chance at a slow cadence —
        // they must never silently orphan local edits.
        await requeueStaleFailedPushes()

        let pendingItems = try? await database.asyncRead { db in
            try SyncQueueItem
                .filter(Column("status") == "pending")
                .order(Column("created_at").asc)
                .limit(500)
                .fetchAll(db)
        }

        guard let items = pendingItems, !items.isEmpty else {
            pendingChanges = 0
            return
        }

        pendingChanges = items.count
        print("📤 Syncing \(items.count) pending changes...")

        for item in items {
            do {
                try await pushChange(item)

                // Scope to the pushed local_version (mirrors ChangeTracker.immediatePush):
                // queueChange bumps the same row in place when an edit lands mid-flight,
                // so an unscoped update would claim the newer edit was synced.
                do {
                    try await database.asyncWrite { db in
                        try db.execute(
                            sql: "UPDATE sync_queue SET status = 'synced', synced_at = ? WHERE id = ? AND local_version <= ?",
                            arguments: [ISO8601.string(from: Date()), item.id, item.localVersion]
                        )
                    }
                } catch {
                    PersistenceHealth.note(.syncFailure, context: "SyncEngine.syncPendingChanges(\(item.uuid.prefix(8)))", detail: "post-push queue bookkeeping failed: \(error)")
                }

                pendingChanges = max(0, pendingChanges - 1)

            } catch {
                let resolution = SyncFailurePolicy.resolve(
                    currentRetryCount: item.retryCount,
                    maxRetries: self.maxRetries,
                    error: error
                )

                do {
                    try await database.asyncWrite { db in
                        try db.execute(
                            sql: "UPDATE sync_queue SET status = ?, retry_count = ?, error_message = ? WHERE id = ?",
                            arguments: [resolution.status, resolution.retryCount, error.localizedDescription, item.id]
                        )

                        // Stamp the failure time so requeueStaleFailedPushes can
                        // re-queue this row after a cool-down.
                        if resolution.status == "failed" {
                            try db.execute(
                                sql: "UPDATE sync_queue SET created_at = ? WHERE id = ?",
                                arguments: [Int64(Date().timeIntervalSince1970 * 1000), item.id]
                            )
                        }

                        // NOTE: _local_pending is deliberately NOT cleared on permanent
                        // failure. The shield must stay up — clearing it let every future
                        // remote change route into handleConflict and silently discard
                        // the unpushed local edit (audit RC7). The row is re-queued for
                        // slow-cadence retry by requeueStaleFailedPushes() instead.
                    }
                } catch {
                    PersistenceHealth.note(.writeFailure, context: "SyncEngine.syncPendingChanges(\(item.uuid.prefix(8)))", detail: "failed to record push failure: \(error)")
                }

                if resolution.status == "failed" {
                    PersistenceHealth.note(.syncFailure, context: "SyncEngine.pushChange(\(item.uuid.prefix(8)))", detail: "push failed after \(resolution.retryCount) attempts (will keep retrying every \(Int(failedPushRequeueDelay / 60)) min): \(error.localizedDescription)")
                }

                if resolution.shouldPauseFurtherAttempts {
                    print("⏸️ Supabase sync writes paused — preserving pending local changes and pausing this sync pass")
                    break
                }
            }
        }

        // Clean up old synced items
        try? await database.asyncWrite { db in
            try db.execute(
                sql: "DELETE FROM sync_queue WHERE status = 'synced' AND synced_at < datetime('now', '-1 day')"
            )
        }
    }

    /// Heal rows whose `_local_pending` shield is raised but that have NO pending
    /// sync_queue row — the divergence that silently freezes a row in BOTH sync
    /// directions.
    ///
    /// Root cause: `_local_pending` (the inbound shield, checked in
    /// applyRemoteChange) and `sync_queue` (the outbound push driver) are two
    /// independent stores. Roughly twenty raw-SQL write paths set
    /// `_local_pending = 1` directly, and the synchronous close-save escort
    /// persists with the flag but without the async `trackUpdate` that would
    /// enqueue. Any of them can leave the flag up with no queue row. The pusher
    /// only reads sync_queue, so the stranded local edit never uploads;
    /// meanwhile the shield skips EVERY inbound remote change for that row, so
    /// the other device's edits never apply. The row is frozen until this pass
    /// re-enqueues it (after which the push lands and the post-push bookkeeping
    /// drops the shield), or — when the server has already moved past the local
    /// version — clears the stale shield so the next pull can apply the newer
    /// remote row. Cheap enough to run every cycle (indexed NOT EXISTS).
    private func requeueOrphanedPendingRows() async {
        // Atoms — the user-facing surface (tasks, notes, ideas, content, …).
        do {
            let result = try await database.asyncWrite { db in
                try SyncQueueReconciler.reconcileOrphanedPendingAtoms(db)
            }
            if result.requeued > 0 || result.cleared > 0 {
                print("🩹 Orphaned-pending heal — atoms: re-enqueued \(result.requeued), stale shield cleared \(result.cleared)")
                // .recovery, NOT .syncFailure: this is the healer SUCCEEDING.
                // Reporting it as a failure put a scary "Cloud sync issue"
                // banner over routine self-repair.
                PersistenceHealth.note(.recovery, context: "SyncEngine.requeueOrphanedPending(atoms)", detail: "re-enqueued \(result.requeued) local-ahead atom(s) with no queue row; cleared \(result.cleared) stale shield(s)")
            }
        } catch {
            PersistenceHealth.note(.writeFailure, context: "SyncEngine.requeueOrphanedPending(atoms)", detail: String(describing: error))
        }

        // Canvas blocks — same shield, same divergence (raw-SQL block writes in
        // note/sticky/connection views set _local_pending directly).
        do {
            let requeued = try await database.asyncWrite { db in
                try SyncQueueReconciler.reconcileOrphanedPendingCanvasBlocks(db)
            }
            if requeued > 0 {
                print("🩹 Orphaned-pending heal — canvas_blocks: re-enqueued \(requeued)")
                PersistenceHealth.note(.recovery, context: "SyncEngine.requeueOrphanedPending(canvas_blocks)", detail: "re-enqueued \(requeued) block(s) with _local_pending=1 and no queue row")
            }
        } catch {
            PersistenceHealth.note(.writeFailure, context: "SyncEngine.requeueOrphanedPending(canvas_blocks)", detail: String(describing: error))
        }
    }

    /// Re-queue permanently-failed pushes after a cool-down so they keep retrying
    /// indefinitely at a slow cadence instead of orphaning local edits forever.
    /// retry_count is reset to maxRetries - 1, granting exactly one fresh attempt
    /// per cool-down window before the row returns to 'failed'.
    private func requeueStaleFailedPushes() async {
        let cutoff = Int64((Date().timeIntervalSince1970 - failedPushRequeueDelay) * 1000)
        let retryFloor = maxRetries - 1
        do {
            let requeued = try await database.asyncWrite { db -> Int in
                try db.execute(
                    sql: """
                    UPDATE sync_queue
                    SET status = 'pending', retry_count = ?
                    WHERE status = 'failed' AND created_at < ?
                    """,
                    arguments: [retryFloor, cutoff]
                )
                return db.changesCount
            }
            if requeued > 0 {
                print("🔁 Re-queued \(requeued) failed push(es) for slow-cadence retry")
            }
        } catch {
            PersistenceHealth.note(.writeFailure, context: "SyncEngine.requeueStaleFailedPushes", detail: String(describing: error))
        }
    }

    private func pushChange(_ item: SyncQueueItem) async throws {
        guard let client = supabaseClient else {
            throw SyncError.noClient
        }
        guard SupabaseSyncTrafficPolicy.shouldAttemptPush(isAuthenticated: client.isAuthenticated) else {
            throw SupabaseError.authRequired
        }

        // Set sync fence to prevent remote from overwriting
        try await setSyncFence(uuid: item.uuid)

        // Parse the data payload. DELETE rows are queued with no payload
        // (soft delete by uuid) — requiring one made every batch-retried
        // delete throw invalidPayload, so offline deletes never propagated.
        var payload: [String: Any] = [:]
        var serverVersion = 0
        if item.operation != "DELETE" {
            guard let data = item.data,
                  let jsonData = data.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                throw SyncError.invalidPayload
            }
            payload = parsed
            serverVersion = payload["_server_version"] as? Int ?? 0

            // Remove local-only fields + GRDB autoincrement id (conflicts with Postgres serial)
            payload.removeValue(forKey: "id")
            payload.removeValue(forKey: "_local_version")
            payload.removeValue(forKey: "_server_version")
            payload.removeValue(forKey: "_sync_version")
            payload.removeValue(forKey: "_local_pending")

            // Add user_id for RLS compliance
            if let userId = client.currentUserId {
                payload["user_id"] = userId
            }

            // Add source tracking
            payload["_source"] = "mac"

            // For the unified atoms table, convert TEXT JSON fields to parsed objects
            // so Postgres can store them as JSONB
            if item.tableName == "atoms" {
                payload = convertJSONFieldsForPostgres(payload)
            }
        }

        let writeDisposition: SyncWriteDisposition
        if item.tableName == "atoms" {
            writeDisposition = SyncWriteDisposition.resolve(
                requestedOperation: item.operation,
                serverVersion: serverVersion
            )
        } else if item.operation == "INSERT" {
            writeDisposition = .upsert
        } else {
            writeDisposition = .update
        }

        switch item.operation {
        case "DELETE":
            try await client.softDelete(table: item.tableName, uuid: item.uuid)

        case "INSERT", "UPDATE":
            switch writeDisposition {
            case .upsert:
                try await client.upsert(table: item.tableName, data: payload, onConflict: "uuid")
            case .update:
                try await client.update(table: item.tableName, uuid: item.uuid, data: payload)
            }

        default:
            throw SyncError.unknownOperation
        }

        // Update local server version — scoped to the version actually pushed
        // (mirrors ChangeTracker.immediatePush). An edit made while this push
        // was in flight keeps `_local_pending = 1` and gets its own push instead
        // of being silently claimed as synced.
        do {
            let keyColumn = ["canvas_blocks", "canvas_drawings"].contains(item.tableName) ? "id" : "uuid"
            try await database.asyncWrite { db in
                try CanvasBlockSyncObserver.suppressingSync {
                    try db.execute(
                        sql: """
                        UPDATE \(item.tableName)
                        SET _server_version = MAX(_server_version, ?),
                            _local_pending = CASE WHEN _local_version > ? THEN _local_pending ELSE 0 END
                        WHERE \(keyColumn) = ?
                        """,
                        arguments: [item.localVersion, item.localVersion, item.uuid]
                    )
                }
            }
        } catch {
            // Push succeeded but bookkeeping failed — shield stays up, the row
            // stays pending and is retried (idempotent upsert). Must be visible.
            PersistenceHealth.note(.syncFailure, context: "SyncEngine.pushChange(\(item.uuid.prefix(8)))", detail: "post-push version bookkeeping failed: \(error)")
        }
    }

    /// Convert TEXT JSON fields to parsed objects for JSONB storage in Postgres
    private func convertJSONFieldsForPostgres(_ payload: [String: Any]) -> [String: Any] {
        var converted = payload
        for key in ["structured", "metadata", "links"] {
            if let jsonString = converted[key] as? String,
               !jsonString.isEmpty,
               let data = jsonString.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) {
                converted[key] = parsed
            }
        }
        return converted
    }

    // MARK: - Pull Remote Changes
    private func pullRemoteChanges() async {
        guard isOnline, let client = supabaseClient else { return }

        var pulledAtomUUIDs: [String] = []

        for table in pullTables {
            let lastSync = await getLastPullTime(for: table)
            // Honest cursor: track the max updated_at actually pulled. Stamping
            // wall-clock `Date()` skipped anything beyond the first page forever.
            var maxPulledUpdatedAt: Date?
            var offset = 0

            do {
                // Paginate until a page comes back short — a single 100-row page
                // silently dropped everything past it after a week offline.
                while true {
                    let page = try await client.fetchChanges(
                        table: table,
                        since: lastSync,
                        excludeLocalSource: true,
                        limit: pullPageLimit,
                        offset: offset
                    )

                    for change in page {
                        await applyRemoteChange(table: table, data: change)

                        if let updatedStr = change["updated_at"] as? String,
                           let updated = ISO8601.date(from: ISO8601.normalize(updatedStr)) {
                            if maxPulledUpdatedAt.map({ updated > $0 }) ?? true {
                                maxPulledUpdatedAt = updated
                            }
                        }

                        // Track pulled atom UUIDs for automation catch-up
                        if table == "atoms", let uuid = change["uuid"] as? String {
                            let source = change["_source"] as? String ?? "mac"
                            if source != "mac", !Self.isRemoteDeleted(change) {
                                pulledAtomUUIDs.append(uuid)
                                // Cloud inbox captures that arrived while this Mac was offline
                                // never hit Realtime — convert them here so they reach the Inbox UI.
                                await InboxCaptureConverter.convertIfInboxCapture(uuid: uuid, atomData: change)
                            }
                        }
                    }

                    if page.count < pullPageLimit { break }
                    offset += page.count
                }

            } catch {
                print("⚠️ Pull failed for \(table): \(error)")
                PersistenceHealth.note(.syncFailure, context: "SyncEngine.pullRemoteChanges(\(table))", detail: String(describing: error))
            }

            // Cursor = max pulled updated_at minus a small overlap (never wall-clock now).
            // Zero rows pulled = cursor unchanged. Mid-pagination failures still advance
            // only as far as what was actually applied.
            if let maxPulled = maxPulledUpdatedAt {
                var newCursor = maxPulled.addingTimeInterval(-pullCursorOverlap)
                if let lastSync, newCursor < lastSync { newCursor = lastSync }
                await updateLastPullTime(for: table, to: newCursor)
            }
        }

        // Notify automation dispatcher of newly pulled cloud atoms
        if !pulledAtomUUIDs.isEmpty {
            await MainActor.run {
                NotificationCenter.default.post(
                    name: CosmoNotification.Sync.atomsPulled,
                    object: nil,
                    userInfo: ["atomUUIDs": pulledAtomUUIDs]
                )
            }

            // Auto-process any cloud-captured swipes that arrived via batch pull
            SwipeProcessingService.shared.scanForPendingSwipes()
        }
    }

    private func applyRemoteChange(table: String, data: [String: Any]) async {
        guard let uuid = data["uuid"] as? String else { return }

        // LOCAL-FIRST: NEVER apply our own writes back.
        // Only apply changes from cloud agent (_source = "cloud") or iOS app (_source = "ios").
        if !SupabaseSyncTrafficPolicy.shouldApplyRemoteChange(source: data["_source"] as? String) {
            return
        }

        let isRemoteTombstone = Self.isRemoteDeleted(data)

        // Check sync fence
        if await hasSyncFence(uuid: uuid) {
            if isRemoteTombstone {
                PersistenceHealth.note(.conflict, context: "SyncEngine.applyRemoteChange(\(uuid.prefix(8)))", detail: "remote delete skipped — sync fence active; local row kept")
            }
            print("🛡️ Sync fence active for \(uuid), skipping remote change")
            return
        }

        // Check editing lock
        if AtomRepository.shared.isBeingEdited(uuid) {
            if isRemoteTombstone {
                PersistenceHealth.note(.conflict, context: "SyncEngine.applyRemoteChange(\(uuid.prefix(8)))", detail: "remote delete skipped — editing lock active; local row kept")
            }
            print("🛡️ Editing lock active for \(uuid), skipping remote change")
            return
        }

        // Check for local pending changes. If the check itself fails, fail safe:
        // skip the remote apply rather than risk overwriting unpushed local edits.
        // canvas_blocks: local identity is `id` (== cloud key; the local uuid
        // column holds the entity uuid on legacy rows).
        let keyColumn = ["canvas_blocks", "canvas_drawings"].contains(table) ? "id" : "uuid"

        let hasPending: Bool
        do {
            let row = try await database.asyncRead { db in
                try Row.fetchOne(
                    db,
                    sql: "SELECT _local_pending FROM \(table) WHERE \(keyColumn) = ? AND _local_pending = 1",
                    arguments: [uuid]
                )
            }
            hasPending = row != nil
        } catch {
            PersistenceHealth.note(.syncFailure, context: "SyncEngine.applyRemoteChange(\(uuid.prefix(8)))", detail: "pending-shield check failed, remote change skipped: \(error)")
            return
        }

        if hasPending {
            if isRemoteTombstone {
                PersistenceHealth.note(.conflict, context: "SyncEngine.applyRemoteChange(\(uuid.prefix(8)))", detail: "remote delete skipped — unpushed local edits; local row kept")
            }
            print("🛡️ Local pending change for \(uuid), skipping remote update")
            return
        }

        // Remote tombstone past all shields → apply as a LOCAL SOFT-DELETE.
        if isRemoteTombstone {
            await applyRemoteTombstone(table: table, uuid: uuid, data: data)
            return
        }

        // Deletes are one-way: a locally-deleted row is never resurrected by
        // a remote live row (e.g. another device's update in flight while the
        // delete's tombstone push races it). The queued DELETE tombstones the
        // cloud copy and the other device follows. Sole escape hatch: an
        // explicit user restore — see remoteCarriesExplicitRestore. COALESCE
        // distinguishes "tombstone with NULL updated_at" ('') from "no
        // tombstone" (nil).
        let tombstoneUpdatedAt = (try? await database.asyncRead { db in
            try String.fetchOne(
                db,
                sql: "SELECT COALESCE(updated_at, '') FROM \(table) WHERE \(keyColumn) = ? AND is_deleted = 1",
                arguments: [uuid]
            )
        }) ?? nil
        if let tombstoneUpdatedAt {
            if Self.remoteCarriesExplicitRestore(data: data, localTombstoneUpdatedAt: tombstoneUpdatedAt.isEmpty ? nil : tombstoneUpdatedAt) {
                PersistenceHealth.note(.conflict, context: "SyncEngine.applyRemoteChange(\(uuid.prefix(8)))", detail: "explicit restore accepted — remote restoredAt newer than local tombstone")
                // Fall through: the conflict resolver applies the undelete.
            } else {
                PersistenceHealth.note(.conflict, context: "SyncEngine.applyRemoteChange(\(uuid.prefix(8)))", detail: "remote live row skipped — row is locally deleted; deletes are one-way")
                return
            }
        }

        // For atoms table: convert JSONB objects back to TEXT strings for GRDB
        var localData = data
        if table == "atoms" {
            localData = convertJSONFieldsFromPostgres(localData)
        }

        // Apply with conflict resolution
        await conflictResolver.applyRemoteChange(table: table, uuid: uuid, data: localData)
    }

    /// True when a remote row is a tombstone (`is_deleted` true/1).
    private nonisolated static func isRemoteDeleted(_ data: [String: Any]) -> Bool {
        if let flag = data["is_deleted"] as? Bool { return flag }
        if let flag = data["is_deleted"] as? Int { return flag == 1 }
        return false
    }

    // MARK: - Explicit Resurrection Gate

    /// The one sanctioned escape hatch through "deletes are one-way".
    /// `metadata.restoredAt` is written ONLY by an explicit user restore
    /// (AtomRepository.restore — identical wire contract in the iOS repo),
    /// never by a mirror re-pushing rows it already held. So a live remote
    /// row whose marker is strictly newer than the local tombstone's
    /// updated_at proves a deliberate restore happened after our delete.
    /// Everything else stays blocked: rows with no marker (the July 3 2026
    /// stale-mirror resurrection incident) and markers older than a
    /// re-delete. Unparseable timestamps fail closed — never resurrect
    /// without proof of ordering.
    nonisolated static func remoteCarriesExplicitRestore(data: [String: Any], localTombstoneUpdatedAt: String?) -> Bool {
        guard let marker = restoredAtMarker(inMetadata: data["metadata"]),
              let restoredAt = ISO8601.date(from: ISO8601.normalize(marker)),
              let tombstoneString = localTombstoneUpdatedAt,
              let tombstonedAt = ISO8601.date(from: ISO8601.normalize(tombstoneString)) else { return false }
        return restoredAt > tombstonedAt
    }

    /// metadata is a JSON string locally but a JSONB dictionary on paths that
    /// run before Postgres conversion — accept both shapes.
    private nonisolated static func restoredAtMarker(inMetadata metadata: Any?) -> String? {
        if let dict = metadata as? [String: Any] { return dict["restoredAt"] as? String }
        if let string = metadata as? String,
           let data = string.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return dict["restoredAt"] as? String
        }
        return nil
    }

    /// Apply a remote deletion as a local SOFT-delete (is_deleted = 1 — never a
    /// hard delete). Shields (fence, editing lock, _local_pending) were already
    /// checked by the caller; rows with unpushed local edits never reach here.
    private func applyRemoteTombstone(table: String, uuid: String, data: [String: Any]) async {
        let remoteVersion = data["_version"] as? Int ?? data["_server_version"] as? Int ?? data["version"] as? Int ?? 0
        let updatedAt = (data["updated_at"] as? String).map(ISO8601.normalize) ?? ISO8601.string(from: Date())
        let keyColumn = ["canvas_blocks", "canvas_drawings"].contains(table) ? "id" : "uuid"
        do {
            try await database.asyncWrite { db in
                // Version history: a remote tombstone is about to soft-delete the
                // local row — keep its final content (same contract as local delete).
                if table == Atom.databaseTableName,
                   let previous = try? Atom
                       .filter(Atom.CodingKeys.uuid == uuid)
                       .filter(Atom.CodingKeys.isDeleted == false)
                       .fetchOne(db) {
                    AtomRevisionWriter.snapshot(db, of: previous, source: .preDelete)
                }
                try CanvasBlockSyncObserver.suppressingSync {
                    try db.execute(
                        sql: """
                        UPDATE \(table)
                        SET is_deleted = 1,
                            updated_at = ?,
                            _server_version = MAX(_server_version, ?)
                        WHERE \(keyColumn) = ? AND is_deleted = 0
                        """,
                        arguments: [updatedAt, remoteVersion, uuid]
                    )

                    // Cascade like the local delete path (AtomRepository.delete):
                    // canvas placements for a tombstoned atom must die with it, or
                    // the block keeps rendering from its cached entity_title.
                    if table == Atom.databaseTableName {
                        try db.execute(
                            sql: "UPDATE canvas_blocks SET is_deleted = 1, updated_at = ? WHERE entity_uuid = ? AND is_deleted = 0",
                            arguments: [updatedAt, uuid]
                        )
                    }
                }
            }
            print("🗑️ Applied remote tombstone: \(table):\(uuid)")
            if table == Atom.databaseTableName {
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: Notification.Name("com.cosmo.canvasBlocksChanged"),
                        object: nil
                    )
                }
            }
        } catch {
            PersistenceHealth.note(.writeFailure, context: "SyncEngine.applyRemoteTombstone(\(uuid.prefix(8)))", detail: String(describing: error))
        }
    }

    /// Convert JSONB objects from Postgres back to TEXT strings for GRDB storage
    private func convertJSONFieldsFromPostgres(_ data: [String: Any]) -> [String: Any] {
        var converted = data
        for key in ["structured", "metadata", "links"] {
            if let obj = converted[key], !(obj is String), !(obj is NSNull) {
                if let jsonData = try? JSONSerialization.data(withJSONObject: obj),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    converted[key] = jsonString
                }
            }
        }
        // Normalize Postgres timestamps (fractional seconds/offsets) to canonical ISO 8601
        for dateKey in ["created_at", "updated_at"] {
            if let dateStr = converted[dateKey] as? String {
                converted[dateKey] = ISO8601.normalize(dateStr)
            }
        }
        // Remove Postgres-only fields
        converted.removeValue(forKey: "user_id")
        converted.removeValue(forKey: "_source")
        converted.removeValue(forKey: "fts")
        return converted
    }

    // MARK: - Sync Fence
    private func setSyncFence(uuid: String) async throws {
        let expiresAt = Date().timeIntervalSince1970 * 1000 + Double(fenceExpiryMs)

        try await database.asyncWrite { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO sync_fence (uuid, expires_at) VALUES (?, ?)",
                arguments: [uuid, Int64(expiresAt)]
            )
        }
    }

    func setExtendedFence(uuid: String) async {
        let expiresAt = Date().timeIntervalSince1970 * 1000 + Double(extendedFenceExpiryMs)
        do {
            try await database.asyncWrite { db in
                try db.execute(
                    sql: "INSERT OR REPLACE INTO sync_fence (uuid, expires_at) VALUES (?, ?)",
                    arguments: [uuid, Int64(expiresAt)]
                )
            }
        } catch {
            // A missing fence lets a remote echo overwrite the row being protected.
            PersistenceHealth.note(.writeFailure, context: "SyncEngine.setExtendedFence(\(uuid.prefix(8)))", detail: String(describing: error))
        }
    }

    private func hasSyncFence(uuid: String) async -> Bool {
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        do {
            let fence = try await database.asyncRead { db in
                try Row.fetchOne(
                    db,
                    sql: "SELECT expires_at FROM sync_fence WHERE uuid = ? AND expires_at > ?",
                    arguments: [uuid, now]
                )
            }
            return fence != nil
        } catch {
            // Fail safe: if the shield can't be verified, behave as if fenced.
            PersistenceHealth.note(.syncFailure, context: "SyncEngine.hasSyncFence(\(uuid.prefix(8)))", detail: String(describing: error))
            return true
        }
    }

    private func cleanupExpiredFences() async {
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        do {
            try await database.asyncWrite { db in
                try db.execute(
                    sql: "DELETE FROM sync_fence WHERE expires_at < ?",
                    arguments: [now]
                )
            }
        } catch {
            PersistenceHealth.note(.writeFailure, context: "SyncEngine.cleanupExpiredFences", detail: String(describing: error))
        }
    }

    // MARK: - Last Pull Time
    private func getLastPullTime(for table: String) async -> Date? {
        let result = try? await database.asyncRead { db in
            try Row.fetchOne(
                db,
                sql: "SELECT value FROM user_settings WHERE key = ?",
                arguments: ["last_pull_\(table)"]
            )
        }

        if let dateStr = result?["value"] as? String {
            return ISO8601.date(from: dateStr)
        }

        return nil
    }

    /// Persist the pull cursor. `date` must be derived from the max `updated_at`
    /// actually pulled (minus overlap) — never wall-clock now, which would skip
    /// any rows beyond the last fetched page forever.
    private func updateLastPullTime(for table: String, to date: Date) async {
        let cursor = ISO8601.string(from: date)

        do {
            try await database.asyncWrite { db in
                try db.execute(
                    sql: """
                    INSERT OR REPLACE INTO user_settings (key, value)
                    VALUES (?, ?)
                    """,
                    arguments: ["last_pull_\(table)", cursor]
                )
            }
        } catch {
            // A stale cursor only causes re-pulls (safe direction), but the
            // failure itself signals DB trouble — surface it.
            PersistenceHealth.note(.writeFailure, context: "SyncEngine.updateLastPullTime(\(table))", detail: String(describing: error))
        }
    }

    // MARK: - Manual Sync
    func forceSync() async {
        await performBackgroundSync()
    }

    // MARK: - Stop Sync
    func stop() {
        syncTimer?.invalidate()
        syncTimer = nil
        realtimeSubscription?.cancel()
    }
}

// MARK: - Sync Queue Reconciler

/// Reconciles the `_local_pending` shield against the `sync_queue`. Pure,
/// synchronous, and DB-injectable so it is unit-testable on an in-memory
/// database (the shared SyncEngine path just wraps these in `asyncWrite`).
enum SyncQueueReconciler {

    struct AtomOutcome: Equatable {
        var requeued: Int
        var cleared: Int
    }

    /// Build the sync payload for a stuck atom row directly from its columns —
    /// the same wire shape `SyncEngine.pushChange` expects (it strips the
    /// local-only fields and parses the JSON TEXT columns into JSONB). Typed
    /// GRDB subscripts throughout: SQLite stores integers as Int64, and the
    /// untyped `as? Int` cast silently fails (the tombstone-resurrection class
    /// of bug), so bool/int columns MUST use `as Bool?` / `as Int?`.
    static func atomPayloadJSON(_ row: Row) -> String? {
        let payload: [String: Any] = [
            "uuid": row["uuid"] as String? ?? "",
            "type": row["type"] as String? ?? "",
            "title": (row["title"] as String?).map { $0 as Any } ?? NSNull(),
            "body": (row["body"] as String?).map { $0 as Any } ?? NSNull(),
            "structured": (row["structured"] as String?).map { $0 as Any } ?? NSNull(),
            "metadata": (row["metadata"] as String?).map { $0 as Any } ?? NSNull(),
            "links": (row["links"] as String?).map { $0 as Any } ?? NSNull(),
            "created_at": row["created_at"] as String? ?? "",
            "updated_at": row["updated_at"] as String? ?? "",
            "is_deleted": (row["is_deleted"] as Bool?) ?? false,
            "_local_version": row["_local_version"] as Int? ?? 1,
            // Read by pushChange to choose update-vs-upsert, then stripped.
            "_server_version": row["_server_version"] as Int? ?? 0,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return json
    }

    /// - Re-enqueue atoms whose local version is genuinely ahead of the last
    ///   acknowledged push (`_local_version > _server_version`) but that have
    ///   no pending OR failed queue row — their stranded local edit must still
    ///   upload. The shield is deliberately NOT required here: a conflict
    ///   auto-merge (ConflictResolver.handleConflict) leaves the merged row
    ///   local-ahead with the shield down, and without this clause its
    ///   local-wins content would never reach the cloud. Failed rows are
    ///   excluded because requeueStaleFailedPushes already owns their retry —
    ///   re-inserting would duplicate the queue row.
    /// - Clear the stale shield on atoms whose local version is NOT ahead
    ///   (`_local_version <= _server_version`) and that have no pending queue
    ///   row: the flag is spurious (the edit already reached the cloud, or the
    ///   server moved past it), and leaving it up would keep blocking inbound
    ///   pulls. Re-pushing those would clobber newer remote content, so we
    ///   never do.
    @discardableResult
    static func reconcileOrphanedPendingAtoms(_ db: Database) throws -> AtomOutcome {
        let orphanClause = """
            _local_pending = 1
            AND NOT EXISTS (
                SELECT 1 FROM sync_queue q
                WHERE q.uuid = atoms.uuid AND q.table_name = 'atoms' AND q.status = 'pending'
            )
            """

        let requeueRows = try Row.fetchAll(db, sql: """
            SELECT * FROM atoms
            WHERE _local_version > _server_version
              AND NOT EXISTS (
                SELECT 1 FROM sync_queue q
                WHERE q.uuid = atoms.uuid AND q.table_name = 'atoms' AND q.status IN ('pending', 'failed')
              )
            """)

        var requeued = 0
        for row in requeueRows {
            guard let uuid = row["uuid"] as String?, !uuid.isEmpty,
                  let json = atomPayloadJSON(row) else { continue }
            try db.execute(
                sql: """
                INSERT INTO sync_queue (uuid, table_name, row_id, operation, data, local_version, status)
                VALUES (?, 'atoms', ?, 'UPDATE', ?, ?, 'pending')
                """,
                arguments: [uuid, row["id"] as Int64?, json, row["_local_version"] as Int? ?? 1]
            )
            requeued += 1
        }

        // Suppressed: clearing a stale shield is bookkeeping on a row whose
        // content already reached the cloud (local <= server). If the
        // AtomSyncObserver enqueued this write, it would re-push local content
        // over a potentially NEWER cloud row that is waiting to pull in.
        let cleared = try CanvasBlockSyncObserver.suppressingSync { () -> Int in
            try db.execute(sql: """
                UPDATE atoms SET _local_pending = 0
                WHERE \(orphanClause) AND _local_version <= _server_version
                """)
            return db.changesCount
        }

        return AtomOutcome(requeued: requeued, cleared: cleared)
    }

    /// Canvas blocks re-enqueue via the same cloud payload builder the
    /// CanvasBlockSyncObserver uses (placement-`id`-keyed, INSERT/upsert). The
    /// shield's cloud key is the placement `id`, mirrored into the queue `uuid`.
    @discardableResult
    static func reconcileOrphanedPendingCanvasBlocks(_ db: Database) throws -> Int {
        let rows = try Row.fetchAll(db, sql: """
            SELECT * FROM canvas_blocks
            WHERE _local_pending = 1
              AND NOT EXISTS (
                SELECT 1 FROM sync_queue q
                WHERE q.uuid = canvas_blocks.id AND q.table_name = 'canvas_blocks' AND q.status = 'pending'
              )
            """)

        var requeued = 0
        for row in rows {
            guard let payload = CanvasBlockRecord.cloudSyncPayload(row: row),
                  let cloudKey = payload["uuid"] as? String,
                  let data = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: data, encoding: .utf8) else { continue }
            try db.execute(
                sql: """
                INSERT INTO sync_queue (uuid, table_name, row_id, operation, data, local_version, status)
                VALUES (?, 'canvas_blocks', NULL, 'INSERT', ?, ?, 'pending')
                """,
                arguments: [cloudKey, json, row["_local_version"] as Int? ?? 1]
            )
            requeued += 1
        }
        return requeued
    }
}

// MARK: - Atom Sync Observer

/// GRDB transaction observer that auto-enqueues every LOCAL atoms
/// insert/update for cloud sync — the atoms twin of CanvasBlockSyncObserver.
///
/// Why: atoms are written by raw SQL from ~20 call sites (focus modes, block
/// views, agent tools, pipelines, …), each of which had to remember to pair
/// its write with a ChangeTracker enqueue in a SEPARATE transaction. Every
/// gap — quit between write and enqueue, a failed `try?` re-fetch, a future
/// writer that forgets — stranded the edit until the orphaned-pending healer
/// found it a cycle later. Observing the table catches every current and
/// future writer at the commit itself. Existing trackUpdate calls stay
/// harmless: queueChange dedupes on (uuid, table, pending).
///
/// Echo prevention: remote-apply and push-bookkeeping writers wrap their
/// writes in `CanvasBlockSyncObserver.suppressingSync { }` — ONE shared
/// suppression window honored by all table observers — so pulled changes are
/// never re-enqueued as local edits and successful pushes never loop.
///
/// Hard DELETEs are ignored: AtomRepository.hardDelete tracks its own cloud
/// deletion. Soft deletes are UPDATEs and flow through here as tombstone
/// payloads (is_deleted = true), which correctly tombstone the cloud row.
final class AtomSyncObserver: TransactionObserver, @unchecked Sendable {
    static let shared = AtomSyncObserver()

    // Writer-queue-confined (GRDB invokes observer callbacks on the database
    // writer queue) — same pattern as CanvasBlockSyncObserver, no locking.
    private var pendingRowIDs: Set<Int64> = []

    private init() {}

    func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool {
        eventKind.tableName == Atom.databaseTableName
    }

    func databaseDidChange(with event: DatabaseEvent) {
        guard !CanvasBlockSyncObserver.isSuppressingRemoteApply else { return }
        switch event.kind {
        case .insert, .update:
            pendingRowIDs.insert(event.rowID)
        case .delete:
            break
        }
    }

    func databaseDidCommit(_ db: Database) {
        guard !pendingRowIDs.isEmpty else { return }
        let rowIDs = pendingRowIDs
        pendingRowIDs.removeAll()
        Task { @MainActor in
            await Self.enqueueForSync(rowIDs: rowIDs)
        }
    }

    func databaseDidRollback(_ db: Database) {
        pendingRowIDs.removeAll()
    }

    /// Fetch the committed rows and upsert sync_queue entries. Operation is
    /// UPDATE — the push path resolves update-vs-upsert from _server_version
    /// (0 = never pushed → upsert), so new atoms are covered too. The
    /// fire-and-forget immediatePush or the periodic SyncEngine pass flushes
    /// the queue.
    @MainActor
    private static func enqueueForSync(rowIDs: Set<Int64>) async {
        let ids = Array(rowIDs)
        do {
            try await CosmoDatabase.shared.asyncWrite { db in
                for chunkStart in stride(from: 0, to: ids.count, by: 100) {
                    let chunk = Array(ids[chunkStart..<min(chunkStart + 100, ids.count)])
                    let marks = chunk.map { _ in "?" }.joined(separator: ",")
                    let rows = try Row.fetchAll(
                        db,
                        sql: "SELECT * FROM atoms WHERE rowid IN (\(marks))",
                        arguments: StatementArguments(chunk)
                    )
                    for row in rows {
                        guard let uuid = row["uuid"] as String?, !uuid.isEmpty,
                              let json = SyncQueueReconciler.atomPayloadJSON(row) else { continue }
                        let localVersion = row["_local_version"] as Int? ?? 1

                        let existing = try Row.fetchOne(
                            db,
                            sql: "SELECT id FROM sync_queue WHERE uuid = ? AND table_name = 'atoms' AND status = 'pending'",
                            arguments: [uuid]
                        )
                        if let existingId = existing?["id"] as Int64? {
                            try db.execute(
                                sql: "UPDATE sync_queue SET operation = 'UPDATE', data = ?, local_version = ?, created_at = ? WHERE id = ?",
                                arguments: [json, localVersion, Int64(Date().timeIntervalSince1970 * 1000), existingId]
                            )
                        } else {
                            try db.execute(
                                sql: """
                                INSERT INTO sync_queue (uuid, table_name, row_id, operation, data, local_version, status)
                                VALUES (?, 'atoms', ?, 'UPDATE', ?, ?, 'pending')
                                """,
                                arguments: [uuid, row["id"] as Int64?, json, localVersion]
                            )
                        }
                    }
                }
            }
        } catch {
            PersistenceHealth.note(.syncFailure, context: "AtomSyncObserver.enqueue", detail: "\(rowIDs.count) row(s) not enqueued: \(error)")
        }
    }
}

// MARK: - Sync State
enum SyncState: Equatable {
    case idle
    case syncing
    case error(String)

    static func == (lhs: SyncState, rhs: SyncState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.syncing, .syncing): return true
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - Sync Errors
enum SyncError: LocalizedError {
    case noClient
    case invalidPayload
    case unknownOperation
    case conflict(local: Int, server: Int)
    case networkError

    var errorDescription: String? {
        switch self {
        case .noClient: return "Supabase client not initialized"
        case .invalidPayload: return "Invalid sync payload"
        case .unknownOperation: return "Unknown sync operation"
        case .conflict(let local, let server): return "Sync conflict: local v\(local), server v\(server)"
        case .networkError: return "Network error"
        }
    }
}

// MARK: - Sync Queue Item
struct SyncQueueItem: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "sync_queue"

    var id: Int64?
    var uuid: String
    var tableName: String
    var rowId: Int64?
    var operation: String
    var data: String?
    var localVersion: Int
    var createdAt: Int64
    var status: String
    var retryCount: Int
    var errorMessage: String?
    var syncedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, uuid, operation, data, status
        case tableName = "table_name"
        case rowId = "row_id"
        case localVersion = "local_version"
        case createdAt = "created_at"
        case retryCount = "retry_count"
        case errorMessage = "error_message"
        case syncedAt = "synced_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
