// CosmoOS/Sync/ConflictResolver.swift
// Handles sync conflicts with source-aware merge strategies
// Phase 0: Enhanced with _source tracking (mac vs cloud)

import Foundation
import GRDB

@MainActor
class ConflictResolver {
    private let database = CosmoDatabase.shared

    // MARK: - Apply Remote Change
    func applyRemoteChange(
        table: String,
        uuid: String,
        data: [String: Any]
    ) async {
        let remoteSource = data["_source"] as? String ?? "unknown"
        let remoteBody = (data["body"] as? String)?.prefix(80) ?? "nil"
        print("[SYNC-RESOLVE] applyRemoteChange — table=\(table) uuid=\(uuid) source=\(remoteSource) remoteBodyPreview=\"\(remoteBody)\"")
        do {
            let local = try await database.asyncRead { db in
                try Row.fetchOne(
                    db,
                    sql: "SELECT *, _local_version, _server_version, _local_pending FROM \(table) WHERE uuid = ?",
                    arguments: [uuid]
                )
            }

            if let local = local {
                let localVersion = local["_local_version"] as? Int ?? 0
                let serverVersion = local["_server_version"] as? Int ?? 0
                let localPending = local["_local_pending"] as? Int ?? 0

                let remoteVersion = data["_version"] as? Int ?? data["_server_version"] as? Int ?? data["version"] as? Int ?? 0
                print("[SYNC-RESOLVE] local state — uuid=\(uuid) localVersion=\(localVersion) serverVersion=\(serverVersion) localPending=\(localPending) remoteVersion=\(remoteVersion)")

                if localPending == 1 {
                    print("[SYNC-RESOLVE] SKIPPED — localPending=1 uuid=\(uuid)")
                    return
                }

                if remoteVersion <= serverVersion && remoteVersion > 0 {
                    print("[SYNC-RESOLVE] SKIPPED — stale remote version uuid=\(uuid) remote=\(remoteVersion) <= server=\(serverVersion)")
                    return
                }

                if localVersion > serverVersion {
                    // Local was modified since last sync — conflict!
                    await handleConflict(
                        table: table,
                        uuid: uuid,
                        localData: rowToDictionary(local),
                        remoteData: data
                    )
                } else {
                    await applyRemoteUpdate(table: table, uuid: uuid, data: data)
                }

            } else {
                print("[SYNC-RESOLVE] applying as INSERT — uuid=\(uuid)")
                await applyRemoteInsert(table: table, data: data)
            }

        } catch {
            print("[SYNC-RESOLVE] ❌ error — uuid=\(uuid) error=\(error)")
            PersistenceHealth.note(.syncFailure, context: "ConflictResolver.applyRemoteChange(\(uuid.prefix(8)))", detail: String(describing: error))
        }
    }

    // MARK: - Handle Conflict (Source-Aware)
    private func handleConflict(
        table: String,
        uuid: String,
        localData: [String: Any],
        remoteData: [String: Any]
    ) async {
        print("⚠️ Conflict detected for \(table):\(uuid)")

        var merged = localData

        // Determine source of remote change
        let remoteSource = remoteData["_source"] as? String ?? "unknown"

        // Fields that ALWAYS prefer remote (sync metadata)
        let remotePreferredFields: Set = ["synced_at", "updated_at", "_server_version", "_version"]

        // Fields where the local user's copy wins outright. The discarded remote
        // copy of body/title content is preserved as a conflict snapshot below —
        // local wins, but the remote edit must never be unrecoverable.
        let localPreferredFields: Set = [
            "title", "content", "body", "description",
            "position_x", "position_y",
        ]

        // Metadata conflict: cloud agent metadata status changes win,
        // but Mac user metadata edits win over cloud
        let metadataStrategy: MetadataStrategy = remoteSource == "cloud"
            ? .preferRemoteForStatus
            : .preferLocal

        for (key, remoteValue) in remoteData {
            if remotePreferredFields.contains(key) {
                merged[key] = remoteValue
            } else if localPreferredFields.contains(key) {
                // Keep local (already in merged)
            } else if key == "metadata" {
                merged[key] = mergeMetadata(
                    local: localData[key],
                    remote: remoteValue,
                    strategy: metadataStrategy
                )
            } else if key == "structured" {
                // Key-level merge: local keys win, remote-only keys survive
                // (whole-blob local-wins silently dropped remote keys).
                merged[key] = mergeJSONKeysPreferLocal(local: localData[key], remote: remoteValue)
            } else if key == "links" {
                // Union merge: relationships added by either side survive.
                merged[key] = mergeLinksUnion(local: localData[key], remote: remoteValue)
            } else if merged[key] == nil {
                merged[key] = remoteValue
            }
        }

        // BEFORE the local-wins resolution lands, preserve any remote user content
        // it discards so a multi-device edit is recoverable instead of vanishing.
        await snapshotDiscardedRemote(
            table: table,
            uuid: uuid,
            localData: localData,
            remoteData: remoteData,
            contentFields: ["title", "content", "body", "description"]
        )

        // Update server version to remote
        merged["_server_version"] = remoteData["_version"] ?? remoteData["_server_version"] ?? remoteData["version"]
        merged["_sync_version"] = (merged["_sync_version"] as? Int ?? 0) + 1

        await applyMergedData(table: table, uuid: uuid, data: merged)

        print("✅ Conflict resolved for \(table):\(uuid) (remote source: \(remoteSource))")
    }

    // MARK: - Conflict Snapshot

    /// When local-wins resolution discards a differing remote body/title, save the
    /// full remote payload as a `sync_queue` row (operation CONFLICT, status
    /// 'conflict') so the remote copy stays recoverable, and record the conflict.
    private func snapshotDiscardedRemote(
        table: String,
        uuid: String,
        localData: [String: Any],
        remoteData: [String: Any],
        contentFields: [String]
    ) async {
        let discarded = contentFields.filter { key in
            guard let remoteString = remoteData[key] as? String else { return false }
            return remoteString != (localData[key] as? String)
        }
        guard !discarded.isEmpty else { return }

        do {
            let payload = sanitizeForJSON(remoteData)
            let payloadData = try JSONSerialization.data(withJSONObject: payload)
            let payloadString = String(data: payloadData, encoding: .utf8) ?? "{}"

            try await database.asyncWrite { db in
                // Don't pile up identical snapshots for the same remote payload.
                let existing = try Row.fetchOne(
                    db,
                    sql: "SELECT 1 FROM sync_queue WHERE uuid = ? AND status = 'conflict' AND data = ?",
                    arguments: [uuid, payloadString]
                )
                guard existing == nil else { return }
                try db.execute(
                    sql: """
                    INSERT INTO sync_queue (uuid, table_name, operation, data, local_version, status)
                    VALUES (?, ?, 'CONFLICT', ?, 0, 'conflict')
                    """,
                    arguments: [uuid, table, payloadString]
                )
            }
            PersistenceHealth.note(.conflict, context: "ConflictResolver.handleConflict(\(uuid.prefix(8)))", detail: "local wins for \(discarded.joined(separator: ", ")); remote copy preserved as conflict snapshot")
        } catch {
            PersistenceHealth.note(.writeFailure, context: "ConflictResolver.conflictSnapshot(\(uuid.prefix(8)))", detail: String(describing: error))
        }
    }

    /// JSONSerialization-safe copy of a payload (row values may include types
    /// JSONSerialization rejects).
    private func sanitizeForJSON(_ dict: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (key, value) in dict {
            if value is String || value is NSNumber || value is NSNull || JSONSerialization.isValidJSONObject(value) {
                out[key] = value
            } else {
                out[key] = String(describing: value)
            }
        }
        return out
    }

    // MARK: - Structured / Links Conflict Merge

    /// Key-level JSON merge for `structured`: local keys win, remote-only keys
    /// survive. Falls back to local (previous behavior) when unparseable.
    private func mergeJSONKeysPreferLocal(local: Any?, remote: Any?) -> Any {
        guard let localVal = local, !(localVal is NSNull) else { return remote ?? NSNull() }
        guard let remoteVal = remote, !(remoteVal is NSNull) else { return localVal }
        guard var mergedDict = parseMetadataToDict(remoteVal),
              let localDict = parseMetadataToDict(localVal) else {
            return localVal
        }
        for (key, value) in localDict {
            mergedDict[key] = value
        }
        if let data = try? JSONSerialization.data(withJSONObject: mergedDict),
           let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }
        return localVal
    }

    /// Union merge for `links`: relationships added by either writer survive.
    /// Delegates to AtomRepository's shared helper (local/caller's choice wins
    /// for single-value link types). Falls back to local when unparseable.
    private func mergeLinksUnion(local: Any?, remote: Any?) -> Any {
        guard let localString = jsonStringValue(local) else { return remote ?? NSNull() }
        guard let remoteString = jsonStringValue(remote) else { return localString }
        return AtomRepository.mergedLinks(fresh: remoteString, caller: localString) ?? localString
    }

    /// Normalize a column value to a JSON string (GRDB stores TEXT; defensive
    /// dict handling for values that escaped Postgres conversion).
    private func jsonStringValue(_ value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty { return string }
        if let value, !(value is NSNull), JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return nil
    }

    // MARK: - Metadata Merge Strategy

    private enum MetadataStrategy {
        case preferLocal
        case preferRemoteForStatus
    }

    /// Merge metadata JSON, optionally preferring remote for status-like fields
    private func mergeMetadata(local: Any?, remote: Any?, strategy: MetadataStrategy) -> Any {
        // If either side is nil/null, return the other
        guard let localVal = local else { return remote ?? NSNull() }
        guard let remoteVal = remote else { return localVal }

        // Try to parse both as JSON strings (GRDB stores as TEXT)
        let localDict = parseMetadataToDict(localVal)
        let remoteDict = parseMetadataToDict(remoteVal)

        guard var localDict = localDict, let remoteDict = remoteDict else {
            return strategy == .preferLocal ? localVal : remoteVal
        }

        switch strategy {
        case .preferLocal:
            // Only add new keys from remote
            for (key, value) in remoteDict where localDict[key] == nil {
                localDict[key] = value
            }

        case .preferRemoteForStatus:
            // Cloud agent wins for status fields (pipeline phase, completion, etc.)
            let statusFields: Set = [
                "phase", "status", "ideaStatus", "isCompleted", "completedAt",
                "statusChangedAt", "lastAnalyzedAt", "schedulingState",
                "lastExecutedAt", "enabled"
            ]
            for (key, value) in remoteDict {
                if statusFields.contains(key) {
                    localDict[key] = value
                } else if localDict[key] == nil {
                    localDict[key] = value
                }
            }
        }

        // Re-serialize to JSON string for GRDB
        if let data = try? JSONSerialization.data(withJSONObject: localDict),
           let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }
        return localVal
    }

    private func parseMetadataToDict(_ value: Any) -> [String: Any]? {
        if let dict = value as? [String: Any] {
            return dict
        }
        if let string = value as? String,
           let data = string.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return dict
        }
        return nil
    }

    // MARK: - Apply Remote Insert
    private func applyRemoteInsert(table: String, data: [String: Any]) async {
        var insertData = data

        insertData["_local_version"] = 1
        insertData["_server_version"] = data["_version"] as? Int ?? data["version"] as? Int ?? 1
        insertData["_local_pending"] = 0

        // Remove Postgres-only fields that don't exist in local schema
        insertData.removeValue(forKey: "user_id")
        insertData.removeValue(forKey: "_source")
        insertData.removeValue(forKey: "_version")
        insertData.removeValue(forKey: "fts")
        // Strip Postgres serial `id` — let GRDB assign its own autoincrement.
        // Without this, Supabase's id collides with local ids causing
        // INSERT OR IGNORE to silently drop the entire row.
        insertData.removeValue(forKey: "id")

        // Normalize Postgres timestamps (fractional seconds/offsets) to canonical ISO 8601
        for dateKey in ["created_at", "updated_at"] {
            if let dateStr = insertData[dateKey] as? String {
                insertData[dateKey] = ISO8601.normalize(dateStr)
            }
        }

        // Fill NOT NULL defaults for canvas_blocks (Postgres allows null, GRDB doesn't)
        if table == "canvas_blocks" {
            sanitizeCanvasBlockDefaults(&insertData)
            // Local canvas_blocks PK is TEXT (Postgres id is BIGSERIAL and was
            // stripped above) — reuse the row's uuid as its local id.
            if insertData["id"] == nil {
                insertData["id"] = insertData["uuid"] as? String ?? UUID().uuidString
            }
        }
        // swipe_boards: local table uses camelCase TEXT timestamps only.
        if table == "swipe_boards" {
            insertData.removeValue(forKey: "created_at")
            insertData.removeValue(forKey: "updated_at")
            insertData.removeValue(forKey: "synced_at")
        }

        let columns = insertData.keys.filter { key in
            !key.starts(with: "_") || ["_local_version", "_server_version", "_sync_version", "_local_pending"].contains(key)
        }
        let placeholders = columns.map { _ in "?" }.joined(separator: ", ")
        let values = columns.compactMap { insertData[$0] }

        let dbValues = values.map { databaseValue(from: $0) }

        // FIX 4 [P0]: Replace INSERT OR IGNORE with existence check + conditional insert/update.
        // INSERT OR IGNORE silently drops the entire row if UUID already exists (race between
        // Realtime and batch pull), losing the cloud atom's data and skipping FTS triggers.
        // canvas_blocks: match local rows by `id` — the local PK always equals
        // the cloud key (pulled rows set id = cloud uuid; Mac-created rows push
        // keyed by their id). The local `uuid` column holds the entity uuid on
        // legacy Mac rows and must not be used for identity.
        let keyColumn = table == "canvas_blocks" ? "id" : "uuid"

        do {
            try await database.asyncWrite { db in
                try CanvasBlockSyncObserver.suppressingSync {
                    let uuidValue = insertData["uuid"] as? String ?? ""
                    let exists = try Row.fetchOne(
                        db,
                        sql: "SELECT 1 FROM \(table) WHERE \(keyColumn) = ?",
                        arguments: [uuidValue]
                    )

                    if exists != nil {
                        // Key already exists — treat as update instead of silently dropping
                        let updateCols = columns.filter { $0 != "uuid" && $0 != "id" }
                        let setClause = updateCols.map { "\($0) = ?" }.joined(separator: ", ")
                        let updateValues = updateCols.compactMap { insertData[$0] }
                        var updateArgs = updateValues.map { databaseValue(from: $0) }
                        updateArgs.append(databaseValue(from: uuidValue))
                        try db.execute(
                            sql: "UPDATE \(table) SET \(setClause) WHERE \(keyColumn) = ?",
                            arguments: StatementArguments(updateArgs)
                        )
                        print("📥 Remote insert → update (key exists): \(table):\(uuidValue)")
                    } else {
                        let sql = "INSERT INTO \(table) (\(columns.joined(separator: ", "))) VALUES (\(placeholders))"
                        try db.execute(sql: sql, arguments: StatementArguments(dbValues))
                        print("📥 Inserted remote entity: \(table):\(uuidValue)")
                    }
                }
            }
        } catch {
            print("❌ Remote insert failed: \(error)")
            PersistenceHealth.note(.writeFailure, context: "ConflictResolver.applyRemoteInsert(\((insertData["uuid"] as? String ?? "?").prefix(8)))", detail: String(describing: error))
        }
    }

    // MARK: - Apply Remote Update
    private func applyRemoteUpdate(table: String, uuid: String, data: [String: Any]) async {
        var updateData = data

        updateData["_server_version"] = data["_version"] as? Int ?? data["version"] as? Int ?? updateData["_server_version"]

        // Remove Postgres-only fields
        updateData.removeValue(forKey: "user_id")
        updateData.removeValue(forKey: "_source")
        updateData.removeValue(forKey: "_version")
        updateData.removeValue(forKey: "fts")

        // Normalize Postgres timestamps (fractional seconds/offsets) to canonical ISO 8601
        for dateKey in ["created_at", "updated_at"] {
            if let dateStr = updateData[dateKey] as? String {
                updateData[dateKey] = ISO8601.normalize(dateStr)
            }
        }

        // Fill NOT NULL defaults for canvas_blocks
        if table == "canvas_blocks" {
            sanitizeCanvasBlockDefaults(&updateData)
        }
        if table == "swipe_boards" {
            updateData.removeValue(forKey: "created_at")
            updateData.removeValue(forKey: "updated_at")
            updateData.removeValue(forKey: "synced_at")
        }

        let updateColumns = updateData.keys.filter { $0 != "id" && $0 != "uuid" }
        let setClause = updateColumns.map { "\($0) = ?" }.joined(separator: ", ")
        let values = updateColumns.compactMap { updateData[$0] }

        // canvas_blocks: local identity is `id` (== cloud key), see applyRemoteInsert.
        let keyColumn = table == "canvas_blocks" ? "id" : "uuid"
        let sql = "UPDATE \(table) SET \(setClause) WHERE \(keyColumn) = ?"

        var dbArgsArray = values.map { databaseValue(from: $0) }
        dbArgsArray.append(databaseValue(from: uuid))
        let finalArgs = dbArgsArray

        do {
            try await database.asyncWrite { db in
                try CanvasBlockSyncObserver.suppressingSync {
                    try db.execute(sql: sql, arguments: StatementArguments(finalArgs))
                }
            }
            print("📥 Updated from remote: \(table):\(uuid)")
        } catch {
            print("❌ Remote update failed: \(error)")
            PersistenceHealth.note(.writeFailure, context: "ConflictResolver.applyRemoteUpdate(\(uuid.prefix(8)))", detail: String(describing: error))
        }
    }

    // MARK: - Apply Merged Data
    private func applyMergedData(table: String, uuid: String, data: [String: Any]) async {
        await applyRemoteUpdate(table: table, uuid: uuid, data: data)
    }

    // MARK: - Canvas Block NOT NULL Defaults
    /// GRDB canvas_blocks has NOT NULL constraints on document_type, document_id, entity_id, entity_type.
    /// Postgres allows null for these (migration didn't enforce them). Fill defaults to prevent SQLite errors.
    private func sanitizeCanvasBlockDefaults(_ data: inout [String: Any]) {
        if data["document_type"] == nil || data["document_type"] is NSNull {
            data["document_type"] = "thinkspace"
        }
        if data["document_id"] == nil || data["document_id"] is NSNull {
            data["document_id"] = 0
        }
        if data["entity_id"] == nil || data["entity_id"] is NSNull {
            data["entity_id"] = 0
        }
        if data["entity_type"] == nil || data["entity_type"] is NSNull {
            data["entity_type"] = data["type"] as? String ?? "note"
        }
        // position fields
        if data["position_x"] == nil || data["position_x"] is NSNull {
            data["position_x"] = 0
        }
        if data["position_y"] == nil || data["position_y"] is NSNull {
            data["position_y"] = 0
        }
    }

    // MARK: - Helper: Row to Dictionary
    private func rowToDictionary(_ row: Row) -> [String: Any] {
        var dict: [String: Any] = [:]
        for column in row.columnNames {
            dict[column] = row[column]
        }
        return dict
    }
}

// MARK: - Helper to convert Any to DatabaseValue
func databaseValue(from any: Any?) -> DatabaseValue {
    guard let value = any else { return .null }

    switch value {
    case let string as String:
        return string.databaseValue
    case let int as Int:
        return int.databaseValue
    case let int64 as Int64:
        return int64.databaseValue
    case let double as Double:
        return double.databaseValue
    case let bool as Bool:
        return bool.databaseValue
    case let data as Data:
        return data.databaseValue
    case is NSNull:
        return .null
    default:
        // Dictionaries/arrays that escaped convertJSONFieldsFromPostgres:
        // serialize to JSON text instead of NULLing the local column, which
        // silently wiped structured/metadata/links during remote applies.
        if JSONSerialization.isValidJSONObject(value),
           let jsonData = try? JSONSerialization.data(withJSONObject: value),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            PersistenceHealth.note(.decodeFailure, context: "databaseValue(from:)", detail: "unconverted JSON value (\(type(of: value))) serialized to text instead of NULL")
            return jsonString.databaseValue
        }
        PersistenceHealth.note(.writeFailure, context: "databaseValue(from:)", detail: "unrepresentable value of type \(type(of: value)) written as NULL")
        return .null
    }
}
