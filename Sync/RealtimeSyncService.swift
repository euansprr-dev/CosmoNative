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
            let source = data["_source"] as? String ?? "unknown"
            print("[REALTIME] INSERT received — uuid=\(uuid) source=\(source)")
            guard isFromCloud(data) else { print("[REALTIME] INSERT SKIPPED — source=mac (own echo) uuid=\(uuid)"); return }
            guard !isLocallyPending(uuid: uuid) else { print("[REALTIME] INSERT SKIPPED — localPending uuid=\(uuid)"); return }
            // FIX 3 [P0]: Match batch pull safety — check sync fence + editing lock
            guard !hasSyncFence(uuid: uuid) else { print("[REALTIME] INSERT SKIPPED — syncFence active uuid=\(uuid)"); return }
            guard !AtomRepository.shared.isBeingEdited(uuid) else { print("[REALTIME] INSERT SKIPPED — editingLock active uuid=\(uuid)"); return }
            let localData = convertJSONFieldsFromPostgres(data)
            print("[REALTIME] INSERT APPLYING — uuid=\(uuid) source=\(source)")
            await conflictResolver.applyRemoteChange(table: "atoms", uuid: uuid, data: localData)
            lastEventTime = Date()
            print("[REALTIME] INSERT APPLIED — uuid=\(uuid)")
            // Notify automation dispatcher for catch-up evaluation
            await MainActor.run {
                NotificationCenter.default.post(
                    name: CosmoNotification.Sync.atomsPulled,
                    object: nil,
                    userInfo: ["atomUUIDs": [uuid]]
                )
            }

            // Auto-process cloud-captured swipes (transcription + analysis)
            await autoProcessCloudSwipe(uuid: uuid, data: localData)

        case .update(let update):
            let data = convertRecord(update.record)
            guard let uuid = data["uuid"] as? String, !uuid.isEmpty else { return }
            let source = data["_source"] as? String ?? "unknown"
            print("[REALTIME] UPDATE received — uuid=\(uuid) source=\(source)")
            guard isFromCloud(data) else { print("[REALTIME] UPDATE SKIPPED — source=mac (own echo) uuid=\(uuid)"); return }
            guard !isLocallyPending(uuid: uuid) else { print("[REALTIME] UPDATE SKIPPED — localPending uuid=\(uuid)"); return }
            // FIX 3 [P0]: Match batch pull safety — check sync fence + editing lock
            guard !hasSyncFence(uuid: uuid) else { print("[REALTIME] UPDATE SKIPPED — syncFence active uuid=\(uuid)"); return }
            guard !AtomRepository.shared.isBeingEdited(uuid) else { print("[REALTIME] UPDATE SKIPPED — editingLock active uuid=\(uuid)"); return }
            let localData = convertJSONFieldsFromPostgres(data)
            print("[REALTIME] UPDATE APPLYING — uuid=\(uuid) source=\(source) bodyPreview=\"\((data["body"] as? String)?.prefix(80) ?? "nil")\"")
            await conflictResolver.applyRemoteChange(table: "atoms", uuid: uuid, data: localData)
            lastEventTime = Date()
            print("[REALTIME] UPDATE APPLIED — uuid=\(uuid)")
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
        let hasPending = try? CosmoDatabase.shared.dbQueue.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT _local_pending FROM atoms WHERE uuid = ? AND _local_pending = 1",
                arguments: [uuid]
            )
        }
        return hasPending != nil
    }

    /// FIX 3: Check if a sync fence is active for this atom.
    /// Prevents Realtime from overwriting atoms we just pushed (echo loop protection).
    private func hasSyncFence(uuid: String) -> Bool {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let fence = try? CosmoDatabase.shared.dbQueue.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT expires_at FROM sync_fence WHERE uuid = ? AND expires_at > ?",
                arguments: [uuid, now]
            )
        }
        return fence != nil
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

    // MARK: - Auto-Process Cloud Swipes

    /// When a cloud-captured swipe syncs down, auto-trigger transcription + analysis.
    private func autoProcessCloudSwipe(uuid: String, data: [String: Any]) async {
        // Check if this is a swipe file needing processing
        guard let type = data["type"] as? String, type == "research" else { return }

        // Parse metadata to check isSwipeFile
        let metadataStr: String?
        if let str = data["metadata"] as? String {
            metadataStr = str
        } else if let obj = data["metadata"], !(obj is NSNull),
                  let jsonData = try? JSONSerialization.data(withJSONObject: obj),
                  let str = String(data: jsonData, encoding: .utf8) {
            metadataStr = str
        } else {
            metadataStr = nil
        }

        guard let metaStr = metadataStr,
              let metaData = metaStr.data(using: .utf8),
              let meta = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any],
              meta["isSwipeFile"] as? Bool == true else { return }

        // Check processingStatus — only process if not already complete
        let status = meta["processingStatus"] as? String
        if status == "complete" { return }

        print("📡 Realtime: auto-processing cloud swipe \(uuid)")

        // Small delay to let the atom fully persist locally before processing
        try? await Task.sleep(nanoseconds: 500_000_000)

        await MainActor.run {
            SwipeProcessingService.shared.processSwipeInBackground(uuid: uuid)
        }
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
