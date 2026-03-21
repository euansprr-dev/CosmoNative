// CosmoOS/Sync/RealtimeSyncService.swift
// Phase 1: Supabase Realtime listener for instant cloud→local sync
// Replaces 30s polling for remote changes. Polling remains as 5-minute fallback.

import Foundation
import Supabase
import Realtime

@MainActor
@Observable
final class RealtimeSyncService {
    static let shared = RealtimeSyncService()

    private(set) var isConnected = false
    private(set) var lastEventTime: Date?

    /// Pause Realtime processing (e.g. during data migration to avoid echo loop)
    var isPaused = false

    private var atomsChannel: RealtimeChannelV2?
    private var canvasChannel: RealtimeChannelV2?
    private var listenTask: Task<Void, Never>?

    private let conflictResolver = ConflictResolver()
    private let database = CosmoDatabase.shared

    private var supabase: Supabase.SupabaseClient {
        SupabaseAuthService.shared.supabaseSDKClient
    }

    private init() {}

    // MARK: - Start Listening

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
            if let channel = canvasChannel {
                await supabase.realtimeV2.removeChannel(channel)
            }
        }

        atomsChannel = nil
        canvasChannel = nil
        isConnected = false
        print("🔌 Realtime sync disconnected")
    }

    // MARK: - Subscribe

    private func subscribeToChanges() async {
        let atoms = supabase.channel("atoms_sync")
        self.atomsChannel = atoms

        let canvas = supabase.channel("canvas_sync")
        self.canvasChannel = canvas

        let atomChanges = atoms.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "atoms"
        )

        let canvasChanges = canvas.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "canvas_blocks"
        )

        await atoms.subscribe()
        await canvas.subscribe()

        isConnected = true
        print("✅ Realtime sync connected — listening for atoms + canvas_blocks changes")

        Task { [weak self] in
            for await action in atomChanges {
                guard let self, !self.isPaused else { continue }
                await self.handleAtomChange(action)
            }
        }

        Task { [weak self] in
            for await action in canvasChanges {
                guard let self, !self.isPaused else { continue }
                await self.handleCanvasChange(action)
            }
        }
    }

    // MARK: - Handle Changes

    private func handleAtomChange(_ action: AnyAction) async {
        switch action {
        case .insert(let insert):
            let data = convertRecord(insert.record)
            guard let uuid = data["uuid"] as? String, !uuid.isEmpty else { return }
            guard shouldApplyRemoteChange(data: data) else { return }
            let localData = convertJSONFieldsFromPostgres(data)
            await conflictResolver.applyRemoteChange(table: "atoms", uuid: uuid, data: localData)
            lastEventTime = Date()
            print("📡 Realtime: atom inserted — \(uuid)")

        case .update(let update):
            let data = convertRecord(update.record)
            guard let uuid = data["uuid"] as? String, !uuid.isEmpty else { return }
            guard shouldApplyRemoteChange(data: data) else { return }
            let localData = convertJSONFieldsFromPostgres(data)
            await conflictResolver.applyRemoteChange(table: "atoms", uuid: uuid, data: localData)
            lastEventTime = Date()
            print("📡 Realtime: atom updated — \(uuid)")

        case .delete(let delete):
            let oldData = convertRecord(delete.oldRecord)
            guard let uuid = oldData["uuid"] as? String, !uuid.isEmpty else { return }
            try? await database.asyncWrite { db in
                try db.execute(
                    sql: "UPDATE atoms SET is_deleted = 1, updated_at = ? WHERE uuid = ?",
                    arguments: [ISO8601DateFormatter().string(from: Date()), uuid]
                )
            }
            lastEventTime = Date()
            print("📡 Realtime: atom deleted — \(uuid)")
        }
    }

    private func handleCanvasChange(_ action: AnyAction) async {
        switch action {
        case .insert(let insert):
            let data = convertRecord(insert.record)
            guard let uuid = data["uuid"] as? String, !uuid.isEmpty else { return }
            guard shouldApplyRemoteChange(data: data) else { return }
            await conflictResolver.applyRemoteChange(table: "canvas_blocks", uuid: uuid, data: data)
            lastEventTime = Date()

        case .update(let update):
            let data = convertRecord(update.record)
            guard let uuid = data["uuid"] as? String, !uuid.isEmpty else { return }
            guard shouldApplyRemoteChange(data: data) else { return }
            await conflictResolver.applyRemoteChange(table: "canvas_blocks", uuid: uuid, data: data)
            lastEventTime = Date()

        case .delete(let delete):
            let oldData = convertRecord(delete.oldRecord)
            guard let uuid = oldData["uuid"] as? String, !uuid.isEmpty else { return }
            try? await database.asyncWrite { db in
                try db.execute(
                    sql: "UPDATE canvas_blocks SET is_deleted = 1 WHERE uuid = ?",
                    arguments: [uuid]
                )
            }
            lastEventTime = Date()
        }
    }

    // MARK: - Helpers

    /// Skip changes that originated from this Mac (avoid echo)
    private func shouldApplyRemoteChange(data: [String: Any]) -> Bool {
        let source = data["_source"] as? String ?? "unknown"
        if source == "mac" {
            return false
        }
        return true
    }

    /// Convert [String: AnyJSON] to [String: Any] using AnyJSON's built-in .value
    private func convertRecord(_ record: [String: AnyJSON]) -> [String: Any] {
        var dict: [String: Any] = [:]
        for (key, value) in record {
            let native = value.value
            if native is NSNull { continue } // Skip nulls
            dict[key] = native
        }
        return dict
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
        converted.removeValue(forKey: "user_id")
        converted.removeValue(forKey: "_source")
        converted.removeValue(forKey: "fts")
        return converted
    }
}
