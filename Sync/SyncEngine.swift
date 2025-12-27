// CosmoOS/Sync/SyncEngine.swift
// Bulletproof local-first sync with invisible background uploads
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

    // MARK: - Configuration
    private let syncInterval: TimeInterval = 30 // seconds
    private let maxRetries = 3
    private let fenceExpiryMs: Int64 = 5000 // 5 seconds

    // MARK: - Sync Tables
    private let syncTables = [
        "ideas", "content", "tasks", "connections", "research",
        "projects", "calendar_events", "canvas_blocks", "journal_entries"
    ]

    private init() {
        // Initialize Supabase client
        supabaseClient = SupabaseClient.shared

        // Observe network changes
        setupNetworkObserver()

        // Start background sync
        startBackgroundSync()

        print("✅ SyncEngine initialized (local-first, invisible sync)")
    }

    // MARK: - Network Observer
    private func setupNetworkObserver() {
        networkMonitor.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                self?.isOnline = isConnected
                if isConnected {
                    // Connection restored - sync pending changes
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

        syncState = .syncing

        // 1. Push local changes
        await syncPendingChanges()

        // 2. Pull remote changes
        await pullRemoteChanges()

        // Update state
        lastSyncTime = Date()
        syncState = .idle
    }

    // MARK: - Push Local Changes (Invisible)
    private func syncPendingChanges() async {
        guard isOnline else { return }

        // Get pending items from sync_queue
        let pendingItems = try? await database.asyncRead { db in
            try SyncQueueItem
                .filter(Column("status") == "pending")
                .order(Column("created_at").asc)
                .limit(50) // Process in batches
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

                // Mark as synced
                try await database.asyncWrite { db in
                    try db.execute(
                        sql: "UPDATE sync_queue SET status = 'synced', synced_at = ? WHERE id = ?",
                        arguments: [ISO8601DateFormatter().string(from: Date()), item.id]
                    )
                }

                pendingChanges -= 1

            } catch {
                // Mark as failed with retry
                try? await database.asyncWrite { db in
                    let newRetryCount = item.retryCount + 1
                    let newStatus = newRetryCount >= self.maxRetries ? "failed" : "pending"

                    try db.execute(
                        sql: "UPDATE sync_queue SET status = ?, retry_count = ?, error_message = ? WHERE id = ?",
                        arguments: [newStatus, newRetryCount, error.localizedDescription, item.id]
                    )
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

        // Set sync fence to prevent real-time from overwriting
        try await setSyncFence(uuid: item.uuid)

        // Parse the data payload
        guard let data = item.data,
              let jsonData = data.data(using: .utf8),
              var payload = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw SyncError.invalidPayload
        }

        // Remove local-only fields before pushing
        payload.removeValue(forKey: "_local_version")
        payload.removeValue(forKey: "_server_version")
        payload.removeValue(forKey: "_sync_version")
        payload.removeValue(forKey: "_local_pending")

        switch item.operation {
        case "INSERT":
            try await client.insert(table: item.tableName, data: payload)

        case "UPDATE":
            try await client.update(table: item.tableName, uuid: item.uuid, data: payload)

        case "DELETE":
            try await client.softDelete(table: item.tableName, uuid: item.uuid)

        default:
            throw SyncError.unknownOperation
        }

        // Update local server version
        try await database.asyncWrite { db in
            try db.execute(
                sql: """
                UPDATE \(item.tableName)
                SET _server_version = _local_version,
                    _local_pending = 0,
                    synced_at = ?
                WHERE uuid = ?
                """,
                arguments: [ISO8601DateFormatter().string(from: Date()), item.uuid]
            )
        }
    }

    // MARK: - Pull Remote Changes
    private func pullRemoteChanges() async {
        guard isOnline, let client = supabaseClient else { return }

        for table in syncTables {
            do {
                let lastSync = await getLastPullTime(for: table)
                let remoteChanges = try await client.fetchChanges(
                    table: table,
                    since: lastSync
                )

                for change in remoteChanges {
                    await applyRemoteChange(table: table, data: change)
                }

                await updateLastPullTime(for: table)

            } catch {
                print("⚠️ Pull failed for \(table): \(error)")
            }
        }
    }

    private func applyRemoteChange(table: String, data: [String: Any]) async {
        guard let uuid = data["uuid"] as? String else { return }

        // Check sync fence - don't overwrite local pending changes
        if await hasSyncFence(uuid: uuid) {
            print("🛡️ Sync fence active for \(uuid), skipping remote change")
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

        // Apply the change with conflict resolution
        await conflictResolver.applyRemoteChange(table: table, uuid: uuid, data: data)
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
