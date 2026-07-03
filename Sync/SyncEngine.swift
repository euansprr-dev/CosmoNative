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
    private let pullTables = ["atoms", "canvas_blocks", "swipe_boards", "canvas_drawings"]

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

        // Drawings sync: one-shot enqueue of every drawing created before the
        // CanvasDrawingSyncObserver existed — without this, historical
        // annotations never reach the cloud or the iPhone.
        await backfillCanvasDrawingsIfNeeded()

        syncState = .syncing

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
                dict["is_deleted"] = (row["is_deleted"] as? Int) ?? 0
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

                pendingChanges -= 1

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

    /// Apply a remote deletion as a local SOFT-delete (is_deleted = 1 — never a
    /// hard delete). Shields (fence, editing lock, _local_pending) were already
    /// checked by the caller; rows with unpushed local edits never reach here.
    private func applyRemoteTombstone(table: String, uuid: String, data: [String: Any]) async {
        let remoteVersion = data["_version"] as? Int ?? data["_server_version"] as? Int ?? data["version"] as? Int ?? 0
        let updatedAt = (data["updated_at"] as? String).map(ISO8601.normalize) ?? ISO8601.string(from: Date())
        let keyColumn = ["canvas_blocks", "canvas_drawings"].contains(table) ? "id" : "uuid"
        do {
            try await database.asyncWrite { db in
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
                }
            }
            print("🗑️ Applied remote tombstone: \(table):\(uuid)")
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
