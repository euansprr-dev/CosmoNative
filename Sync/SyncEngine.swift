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

    // MARK: - Sync Tables (unified)
    // Push: atoms + canvas_blocks go UP to Supabase
    // Pull: ONLY atoms come DOWN (canvas_blocks are Mac-only, never modified by cloud)
    // graph_edges are derived from atom.links and rebuilt by NodeGraphEngine — no sync needed
    private let pushTables = ["atoms", "canvas_blocks"]
    private let pullTables = ["atoms"]  // Only pull cloud-originated changes

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

        // FIX 5: Housekeeping — remove expired sync fences to prevent unbounded table growth
        await cleanupExpiredFences()

        syncState = .syncing

        // 1. Push local changes
        await syncPendingChanges()

        // 2. Pull remote changes
        await pullRemoteChanges()

        // 3. One-shot catch-up: convert any inbox-capture atoms that were pulled
        // before this fix shipped (they're in GRDB but never became InboxItems).
        await runInboxCatchupMigrationIfNeeded()

        // Update state
        lastSyncTime = Date()
        syncState = .idle
    }

    // MARK: - Inbox Catch-Up Migration
    /// Recovers cloud inbox captures that were pulled into GRDB before the
    /// batch-pull path learned how to convert them. Runs once per install.
    private func runInboxCatchupMigrationIfNeeded() async {
        let key = "inboxCatchupMigrationRan_v1"
        if UserDefaults.standard.bool(forKey: key) { return }

        let rows: [[String: Any]]? = try? await database.asyncRead { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT uuid, body, title, metadata, is_deleted
                FROM atoms
                WHERE is_deleted = 0
                  AND metadata LIKE '%"isInboxCapture":true%'
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

        if let rows, !rows.isEmpty {
            print("📥 SyncEngine: inbox catch-up migration processing \(rows.count) stuck capture(s)")
            for row in rows {
                guard let uuid = row["uuid"] as? String else { continue }
                await InboxCaptureConverter.convertIfInboxCapture(uuid: uuid, atomData: row)
            }
        }

        UserDefaults.standard.set(true, forKey: key)
    }

    // MARK: - Push Local Changes (Invisible)
    private func syncPendingChanges() async {
        guard isOnline else { return }

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

                try await database.asyncWrite { db in
                    try db.execute(
                        sql: "UPDATE sync_queue SET status = 'synced', synced_at = ? WHERE id = ?",
                        arguments: [ISO8601DateFormatter().string(from: Date()), item.id]
                    )
                }

                pendingChanges -= 1

            } catch {
                try? await database.asyncWrite { db in
                    let newRetryCount = item.retryCount + 1
                    let newStatus = newRetryCount >= self.maxRetries ? "failed" : "pending"

                    try db.execute(
                        sql: "UPDATE sync_queue SET status = ?, retry_count = ?, error_message = ? WHERE id = ?",
                        arguments: [newStatus, newRetryCount, error.localizedDescription, item.id]
                    )

                    // FIX 2 [P0]: If permanently failed, unblock remote updates.
                    // Without this, _local_pending stays 1 forever and ALL future
                    // Realtime/pull updates for this atom are silently dropped.
                    if newStatus == "failed" {
                        try db.execute(
                            sql: "UPDATE \(item.tableName) SET _local_pending = 0 WHERE uuid = ?",
                            arguments: [item.uuid]
                        )
                    }
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

    private func pushChange(_ item: SyncQueueItem) async throws {
        guard let client = supabaseClient else {
            throw SyncError.noClient
        }

        // Set sync fence to prevent remote from overwriting
        try await setSyncFence(uuid: item.uuid)

        // Parse the data payload
        guard let data = item.data,
              let jsonData = data.data(using: .utf8),
              var payload = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw SyncError.invalidPayload
        }

        let serverVersion = payload["_server_version"] as? Int ?? 0

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

        // Update local server version
        try await database.asyncWrite { db in
            try db.execute(
                sql: """
                UPDATE \(item.tableName)
                SET _server_version = _local_version,
                    _local_pending = 0
                WHERE uuid = ?
                """,
                arguments: [item.uuid]
            )
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
            do {
                let lastSync = await getLastPullTime(for: table)
                let remoteChanges = try await client.fetchChanges(
                    table: table,
                    since: lastSync
                )

                for change in remoteChanges {
                    await applyRemoteChange(table: table, data: change)

                    // Track pulled atom UUIDs for automation catch-up
                    if table == "atoms", let uuid = change["uuid"] as? String {
                        let source = change["_source"] as? String ?? "mac"
                        if source != "mac" {
                            pulledAtomUUIDs.append(uuid)
                            // Cloud inbox captures that arrived while this Mac was offline
                            // never hit Realtime — convert them here so they reach the Inbox UI.
                            await InboxCaptureConverter.convertIfInboxCapture(uuid: uuid, atomData: change)
                        }
                    }
                }

                await updateLastPullTime(for: table)

            } catch {
                print("⚠️ Pull failed for \(table): \(error)")
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
        let source = data["_source"] as? String ?? "mac"
        if source == "mac" {
            return
        }

        // Check sync fence
        if await hasSyncFence(uuid: uuid) {
            print("🛡️ Sync fence active for \(uuid), skipping remote change")
            return
        }

        // Check editing lock
        if AtomRepository.shared.isBeingEdited(uuid) {
            print("🛡️ Editing lock active for \(uuid), skipping remote change")
            return
        }

        // Check for local pending changes
        let hasPending = try? await database.asyncRead { db in
            try Row.fetchOne(
                db,
                sql: "SELECT _local_pending FROM \(table) WHERE uuid = ? AND _local_pending = 1",
                arguments: [uuid]
            )
        }

        if hasPending != nil {
            print("🛡️ Local pending change for \(uuid), skipping remote update")
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
        try? await database.asyncWrite { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO sync_fence (uuid, expires_at) VALUES (?, ?)",
                arguments: [uuid, Int64(expiresAt)]
            )
        }
    }

    private func hasSyncFence(uuid: String) async -> Bool {
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        let fence = try? await database.asyncRead { db in
            try Row.fetchOne(
                db,
                sql: "SELECT expires_at FROM sync_fence WHERE uuid = ? AND expires_at > ?",
                arguments: [uuid, now]
            )
        }

        return fence != nil
    }

    private func cleanupExpiredFences() async {
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        try? await database.asyncWrite { db in
            try db.execute(
                sql: "DELETE FROM sync_fence WHERE expires_at < ?",
                arguments: [now]
            )
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
            return ISO8601DateFormatter().date(from: dateStr)
        }

        return nil
    }

    private func updateLastPullTime(for table: String) async {
        let now = ISO8601DateFormatter().string(from: Date())

        try? await database.asyncWrite { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO user_settings (key, value)
                VALUES (?, ?)
                """,
                arguments: ["last_pull_\(table)", now]
            )
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
