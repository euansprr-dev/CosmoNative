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

                if localPending == 1 {
                    print("🛡️ Skipping remote update for \(uuid) - local pending")
                    return
                }

                if remoteVersion <= serverVersion && remoteVersion > 0 {
                    print("⏭️ Skipping older remote version for \(uuid)")
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
                await applyRemoteInsert(table: table, data: data)
            }

        } catch {
            print("❌ Conflict resolution error: \(error)")
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

        // Fields that ALWAYS prefer local (user content)
        let localPreferredFields: Set = [
            "title", "content", "body", "description",
            "position_x", "position_y",
            "structured",
            "links",
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
            } else if merged[key] == nil {
                merged[key] = remoteValue
            }
        }

        // Update server version to remote
        merged["_server_version"] = remoteData["_version"] ?? remoteData["_server_version"] ?? remoteData["version"]
        merged["_sync_version"] = (merged["_sync_version"] as? Int ?? 0) + 1

        await applyMergedData(table: table, uuid: uuid, data: merged)

        print("✅ Conflict resolved for \(table):\(uuid) (remote source: \(remoteSource))")
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

        let columns = insertData.keys.filter { key in
            !key.starts(with: "_") || ["_local_version", "_server_version", "_sync_version", "_local_pending"].contains(key)
        }
        let placeholders = columns.map { _ in "?" }.joined(separator: ", ")
        let values = columns.compactMap { insertData[$0] }

        let sql = "INSERT OR IGNORE INTO \(table) (\(columns.joined(separator: ", "))) VALUES (\(placeholders))"

        let dbValues = values.map { databaseValue(from: $0) }

        do {
            try await database.asyncWrite { db in
                try db.execute(sql: sql, arguments: StatementArguments(dbValues))
            }
            print("📥 Inserted remote entity: \(table):\(data["uuid"] ?? "?")")
        } catch {
            print("❌ Remote insert failed: \(error)")
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

        let updateColumns = updateData.keys.filter { $0 != "id" && $0 != "uuid" }
        let setClause = updateColumns.map { "\($0) = ?" }.joined(separator: ", ")
        let values = updateColumns.compactMap { updateData[$0] }

        let sql = "UPDATE \(table) SET \(setClause) WHERE uuid = ?"

        var dbArgsArray = values.map { databaseValue(from: $0) }
        dbArgsArray.append(databaseValue(from: uuid))
        let finalArgs = dbArgsArray

        do {
            try await database.asyncWrite { db in
                try db.execute(sql: sql, arguments: StatementArguments(finalArgs))
            }
            print("📥 Updated from remote: \(table):\(uuid)")
        } catch {
            print("❌ Remote update failed: \(error)")
        }
    }

    // MARK: - Apply Merged Data
    private func applyMergedData(table: String, uuid: String, data: [String: Any]) async {
        await applyRemoteUpdate(table: table, uuid: uuid, data: data)
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
    default:
        return .null
    }
}
