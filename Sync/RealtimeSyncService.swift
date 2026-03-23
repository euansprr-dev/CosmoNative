// CosmoOS/Sync/RealtimeSyncService.swift
// Supabase Realtime listener — ONLY applies changes from non-Mac sources.
//
// LOCAL-FIRST PRINCIPLE:
// - Mac writes are authoritative. They push to Supabase but NEVER echo back.
// - Only changes with _source != "mac" are applied (cloud TG agent, iOS app, etc.)
// - Canvas blocks are Mac-only — no Realtime subscription needed.

import Foundation
import Supabase
import Realtime
import GRDB

@MainActor
@Observable
final class RealtimeSyncService {
    static let shared = RealtimeSyncService()

    private(set) var isConnected = false
    private(set) var lastEventTime: Date?

    /// Pause Realtime processing (e.g. during data migration)
    var isPaused = false

    private var atomsChannel: RealtimeChannelV2?
    private var listenTask: Task<Void, Never>?

    private let conflictResolver = ConflictResolver()
    private let database = CosmoDatabase.shared

    private var supabase: Supabase.SupabaseClient {
        SupabaseAuthService.shared.supabaseSDKClient
    }

    private init() {}

    // MARK: - Start/Stop

    func startListening() {
        guard !isConnected else { return }

        listenTask = Task { [weak self] in
            guard let self else { return }
            await self.subscribeToChanges()
        }
    }

    func stopListening() {
        listenTask?.cancel()
        listenTask = nil

        Task {
            if let channel = atomsChannel {
                await supabase.realtimeV2.removeChannel(channel)
            }
        }

        atomsChannel = nil
        isConnected = false
        print("🔌 Realtime sync disconnected")
    }

    // MARK: - Subscribe

    private func subscribeToChanges() async {
        // Only subscribe to atoms — canvas_blocks are Mac-only, never modified by cloud
        let atoms = supabase.channel("atoms_sync")
        self.atomsChannel = atoms

        let atomChanges = atoms.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "atoms"
        )

        await atoms.subscribe()

        isConnected = true
        print("✅ Realtime sync connected — listening for cloud-originated atom changes only")

        Task { [weak self] in
            for await action in atomChanges {
                guard let self, !self.isPaused else { continue }
                await self.handleAtomChange(action)
            }
        }
    }

    // MARK: - Handle Changes

    private func handleAtomChange(_ action: AnyAction) async {
        switch action {
        case .insert(let insert):
            let data = convertRecord(insert.record)
            guard let uuid = data["uuid"] as? String, !uuid.isEmpty else { return }
            guard isFromCloud(data) else { return }
            guard !isLocallyPending(uuid: uuid) else { return }
            let localData = convertJSONFieldsFromPostgres(data)
            await conflictResolver.applyRemoteChange(table: "atoms", uuid: uuid, data: localData)
            lastEventTime = Date()
            print("📡 Realtime: cloud atom inserted — \(uuid)")
            // Notify automation dispatcher for catch-up evaluation
            await MainActor.run {
                NotificationCenter.default.post(
                    name: CosmoNotification.Sync.atomsPulled,
                    object: nil,
                    userInfo: ["atomUUIDs": [uuid]]
                )
            }

        case .update(let update):
            let data = convertRecord(update.record)
            guard let uuid = data["uuid"] as? String, !uuid.isEmpty else { return }
            guard isFromCloud(data) else { return }
            guard !isLocallyPending(uuid: uuid) else { return }
            let localData = convertJSONFieldsFromPostgres(data)
            await conflictResolver.applyRemoteChange(table: "atoms", uuid: uuid, data: localData)
            lastEventTime = Date()
            print("📡 Realtime: cloud atom updated — \(uuid)")
            // Notify automation dispatcher for catch-up evaluation
            await MainActor.run {
                NotificationCenter.default.post(
                    name: CosmoNotification.Sync.atomsPulled,
                    object: nil,
                    userInfo: ["atomUUIDs": [uuid]]
                )
            }

        case .delete(let delete):
            let oldData = convertRecord(delete.oldRecord)
            guard let uuid = oldData["uuid"] as? String, !uuid.isEmpty else { return }
            guard isFromCloud(oldData) else { return }
            try? await database.asyncWrite { db in
                try db.execute(
                    sql: "UPDATE atoms SET is_deleted = 1, updated_at = ? WHERE uuid = ?",
                    arguments: [ISO8601DateFormatter().string(from: Date()), uuid]
                )
            }
            lastEventTime = Date()
            print("📡 Realtime: cloud atom deleted — \(uuid)")
        }
    }

    // MARK: - Filters

    /// ONLY apply changes that did NOT originate from this Mac.
    /// Cloud agent sets _source = "cloud", iOS app will set _source = "ios".
    /// Mac sets _source = "mac" — those are OUR writes echoing back. Always skip.
    private func isFromCloud(_ data: [String: Any]) -> Bool {
        let source = data["_source"] as? String
        // If no _source field (e.g., canvas_blocks), assume it's a Mac write → skip
        guard let source else { return false }
        // Only apply if source is NOT "mac"
        return source != "mac"
    }

    /// Skip changes for atoms that have pending local modifications.
    /// The local version is authoritative until it's pushed and confirmed.
    private func isLocallyPending(uuid: String) -> Bool {
        // Check sync fence
        // Check _local_pending flag
        let hasPending = try? CosmoDatabase.shared.dbQueue.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT _local_pending FROM atoms WHERE uuid = ? AND _local_pending = 1",
                arguments: [uuid]
            )
        }
        return hasPending != nil
    }

    // MARK: - Converters

    private func convertRecord(_ record: [String: AnyJSON]) -> [String: Any] {
        var dict: [String: Any] = [:]
        for (key, value) in record {
            let native = value.value
            if native is NSNull { continue }
            dict[key] = native
        }
        return dict
    }

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
        converted.removeValue(forKey: "user_id")
        converted.removeValue(forKey: "_source")
        converted.removeValue(forKey: "fts")
        return converted
    }
}
