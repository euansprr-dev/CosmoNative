// CosmoOS/Sync/ConflictResolver.swift
// Handles sync conflicts with last-write-wins + merge strategies
// Ensures no data loss during conflicts

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
            // Get local version
            let local = try await database.asyncRead { db in
                try Row.fetchOne(
                    db,
                    sql: "SELECT *, _local_version, _server_version, _local_pending FROM \(table) WHERE uuid = ?",
                    arguments: [uuid]
                )
            }

            if let local = local {
                // Entity exists locally
                let localVersion = local["_local_version"] as? Int ?? 0
                let serverVersion = local["_server_version"] as? Int ?? 0
                let localPending = local["_local_pending"] as? Int ?? 0

                let remoteVersion = data["_server_version"] as? Int ?? data["version"] as? Int ?? 0

                // Check for conflicts
                if localPending == 1 {
                    // Local has pending changes - don't overwrite
                    print("🛡️ Skipping remote update for \(uuid) - local pending")
                    return
                }

                if remoteVersion <= serverVersion {
                    // Remote is older or same - skip
                    print("⏭️ Skipping older remote version for \(uuid)")
                    return
                }

                if localVersion > serverVersion {
                    // Local was modified since last sync - conflict!
                    await handleConflict(
                        table: table,
                        uuid: uuid,
                        localData: rowToDictionary(local),
                        remoteData: data
                    )
                } else {
                    // No conflict - apply remote
                    await applyRemoteUpdate(table: table, uuid: uuid, data: data)
                }

            } else {
                // Entity doesn't exist locally - insert
                await applyRemoteInsert(table: table, data: data)
            }

        } catch {
            print("❌ Conflict resolution error: \(error)")
        }
    }

    // MARK: - Handle Conflict
    private func handleConflict(
        table: String,
        uuid: String,
        localData: [String: Any],
        remoteData: [String: Any]
    ) async {
        print("⚠️ Conflict detected for \(table):\(uuid)")

        // Strategy: Merge fields, prefer local for content, remote for metadata
        var merged = localData

        // Fields that prefer remote (metadata)
        let remotePreferredFields = ["synced_at", "updated_at", "_server_version"]

        // Fields that prefer local (user content)
        let localPreferredFields = ["title", "content", "body", "description", "position_x", "position_y"]

        // Merge strategy
        for (key, remoteValue) in remoteData {
            if remotePreferredFields.contains(key) {
                // Use remote value
                merged[key] = remoteValue
            } else if localPreferredFields.contains(key) {
                // Keep local value (already in merged)
            } else if merged[key] == nil {
                // Field only exists in remote - add it
                merged[key] = remoteValue
            }
            // For other fields, keep local
        }

        // Update server version to remote
        merged["_server_version"] = remoteData["_server_version"] ?? remoteData["version"]
        merged["_sync_version"] = (merged["_sync_version"] as? Int ?? 0) + 1

        // Apply merged data
        await applyMergedData(table: table, uuid: uuid, data: merged)

        print("✅ Conflict resolved for \(table):\(uuid) using merge strategy")
    }

    // MARK: - Apply Remote Insert
    private func applyRemoteInsert(table: String, data: [String: Any]) async {
        var insertData = data

        // Set sync metadata
        insertData["_local_version"] = 1
        insertData["_server_version"] = data["version"] as? Int ?? 1
        insertData["_local_pending"] = 0
        insertData["synced_at"] = ISO8601DateFormatter().string(from: Date())

        // Build insert query
        let columns = insertData.keys.filter { !$0.starts(with: "_") || ["_local_version", "_server_version", "_sync_version", "_local_pending"].contains($0) }
        let placeholders = columns.map { _ in "?" }.joined(separator: ", ")
        let values = columns.compactMap { insertData[$0] }

        let sql = "INSERT OR IGNORE INTO \(table) (\(columns.joined(separator: ", "))) VALUES (\(placeholders))"

        // Convert to DatabaseValue array before the async closure
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

        // Update sync metadata
        updateData["_server_version"] = data["version"] as? Int ?? updateData["_server_version"]
        updateData["synced_at"] = ISO8601DateFormatter().string(from: Date())

        // Build update query (exclude id and uuid)
        let updateColumns = updateData.keys.filter { $0 != "id" && $0 != "uuid" }
        let setClause = updateColumns.map { "\($0) = ?" }.joined(separator: ", ")
        let values = updateColumns.compactMap { updateData[$0] }

        let sql = "UPDATE \(table) SET \(setClause) WHERE uuid = ?"

        // Convert to DatabaseValue array before the async closure
        var dbArgsArray = values.map { databaseValue(from: $0) }
        dbArgsArray.append(databaseValue(from: uuid))
        let finalArgs = dbArgsArray  // Capture as let

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
        // Same as remote update but with merged data
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
