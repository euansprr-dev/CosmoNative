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
                    sql: "SELECT *, _local_version, _server_version, _local_pending FROM \(table) WHERE \(["canvas_blocks", "canvas_drawings"].contains(table) ? "id" : "uuid") = ?",
                    arguments: [uuid]
                )
            }

            if let local = local {
                // Typed GRDB subscripts (`as Int?` / `as Bool?`), NEVER `as? Int`:
                // SQLite integers surface as Int64 and the untyped cast silently
                // returns nil. These casts were broken for months — version and
                // pending reads all collapsed to 0, which disabled the pending
                // shield here, the stale-remote skip, and the entire conflict-
                // merge branch (every remote apply degraded to a blind whole-row
                // overwrite). See the same incident class documented on
                // CanvasBlockRecord.cloudSyncPayload.
                let localVersion = local["_local_version"] as Int? ?? 0
                let serverVersion = local["_server_version"] as Int? ?? 0
                let localPending = local["_local_pending"] as Int? ?? 0
                print("[SYNC-RESOLVE] local state — uuid=\(uuid) localVersion=\(localVersion) serverVersion=\(serverVersion) localPending=\(localPending)")

                if localPending == 1 {
                    print("[SYNC-RESOLVE] SKIPPED — localPending=1 uuid=\(uuid)")
                    return
                }

                // Deletes are one-way: a locally-deleted row is never
                // resurrected by a remote live row (covers Realtime, which
                // calls this resolver directly and skips SyncEngine's guard).
                // Sole escape hatch: an explicit user restore, proven by a
                // metadata.restoredAt marker strictly newer than the local
                // tombstone (wire contract shared with the iOS repo).
                let localDeleted = (local["is_deleted"] as Bool?) ?? false
                let remoteDeleted = (data["is_deleted"] as? Bool) ?? ((data["is_deleted"] as? Int).map { $0 == 1 } ?? false)
                if localDeleted && !remoteDeleted {
                    if SyncEngine.remoteCarriesExplicitRestore(data: data, localTombstoneUpdatedAt: local["updated_at"] as String?) {
                        PersistenceHealth.note(.conflict, context: "ConflictResolver.applyRemoteChange(\(uuid.prefix(8)))", detail: "explicit restore applied — restoredAt newer than local tombstone")
                        await applyExplicitRestore(table: table, uuid: uuid, data: data)
                        return
                    }
                    print("[SYNC-RESOLVE] SKIPPED — locally deleted, remote live; deletes are one-way uuid=\(uuid)")
                    return
                }

                // LWW stale guard. This replaces the old version-based skip,
                // which compared THIS device's push-ack counter against the
                // OTHER device's counter — the values share no lineage, so the
                // comparison was meaningless (and, with the broken casts, dead).
                // A live remote row strictly OLDER than the local row by
                // updated_at can never regress local state; equal timestamps
                // re-apply (idempotent) so same-second edits are never dropped.
                // Tombstone flows never reach here (handled above / diverted to
                // applyRemoteTombstone) — deletes stay timestamp-independent.
                if !remoteDeleted,
                   let remoteUpdatedStr = data["updated_at"] as? String,
                   let remoteUpdated = ISO8601.date(from: ISO8601.normalize(remoteUpdatedStr)),
                   let localUpdatedStr = local["updated_at"] as String?,
                   let localUpdated = ISO8601.date(from: ISO8601.normalize(localUpdatedStr)),
                   remoteUpdated < localUpdated {
                    print("[SYNC-RESOLVE] SKIPPED — stale remote row uuid=\(uuid) remote=\(remoteUpdatedStr) < local=\(localUpdatedStr)")
                    return
                }

                if localVersion > serverVersion {
                    // Local is genuinely ahead of the last acknowledged push
                    // (both counters are local-only, so this comparison IS
                    // sound): unpushed local edits exist even though the
                    // pending shield is down. Merge local-wins instead of
                    // letting the remote row stomp them.
                    await handleConflict(
                        table: table,
                        uuid: uuid,
                        localData: rowToDictionary(local),
                        remoteData: data
                    )
                } else if Self.remoteWouldBlankLocalContent(table: table, localData: rowToDictionary(local), remoteData: data) {
                    // Anti-wipe shield: a live remote row carrying a BLANK body
                    // must never blind-overwrite substantial local content —
                    // the observed source of such rows is another device stuck
                    // holding an empty scaffold of this atom, not a user who
                    // typed a full note and then deleted every character. Route
                    // through the conflict merge: local content wins, the
                    // remote payload stays recoverable as a conflict snapshot.
                    PersistenceHealth.note(.conflict, context: "ConflictResolver.applyRemoteChange(\(uuid.prefix(8)))", detail: "anti-wipe: remote blank body over substantial local content — routed to merge")
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

    // MARK: - Explicit Restore

    /// Undelete accepted by the explicit-resurrection gate
    /// (`SyncEngine.remoteCarriesExplicitRestore`). Routed straight to
    /// applyRemoteUpdate — the local row is a tombstone, so there are no live
    /// local edits for handleConflict's local-wins merge to protect (and that
    /// merge would keep is_deleted = 1, silently dropping the restore).
    /// Mirrors the iOS implementation — shared wire contract.
    private func applyExplicitRestore(table: String, uuid: String, data: [String: Any]) async {
        var restored = data
        restored["is_deleted"] = 0 // undelete even if the remote row omitted the column
        await applyRemoteUpdate(table: table, uuid: uuid, data: restored)

        // delete() tombstones an atom's canvas placements with it — bring
        // them back too or the restored atom stays invisible on every space
        // (mirrors AtomRepository.restore()). Deliberately NOT suppressed:
        // the Mac owns placement sync, so the un-tombstoned blocks should be
        // enqueued and pushed live again by the CanvasBlockSyncObserver.
        guard table == Atom.databaseTableName else { return }
        do {
            try await database.asyncWrite { db in
                try db.execute(
                    sql: "UPDATE canvas_blocks SET is_deleted = 0, updated_at = ? WHERE entity_uuid = ? AND is_deleted = 1",
                    arguments: [ISO8601.string(from: Date()), uuid]
                )
            }
            await MainActor.run {
                NotificationCenter.default.post(
                    name: Notification.Name("com.cosmo.canvasBlocksChanged"),
                    object: nil
                )
            }
        } catch {
            PersistenceHealth.note(.writeFailure, context: "ConflictResolver.applyExplicitRestore(\(uuid.prefix(8)))", detail: String(describing: error))
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

        // Fields that ALWAYS prefer remote (sync metadata). `_server_version`
        // and `_version` are deliberately NOT here: the server's `_version`
        // column froze at its insert-time default (no client bumps it), and
        // adopting it REGRESSED the local push-ack counter — the row looked
        // permanently "local-ahead", every future pull re-entered this merge,
        // and the other device's edits could never land.
        let remotePreferredFields: Set = ["synced_at", "updated_at"]

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

        // Content fields where the blank local copy lost to substantial remote
        // content — their rich-document metadata keys must follow (below).
        var contentAdoptedFromRemote: Set<String> = []

        for (key, remoteValue) in remoteData {
            if remotePreferredFields.contains(key) {
                merged[key] = remoteValue
            } else if localPreferredFields.contains(key) {
                // Local wins for user content — but only content that exists.
                // A blank local copy never beats substantial remote content:
                // "local wins" protects edits, not voids. (July 22 2026: an
                // iPhone-created empty note scaffold rejected the Mac's typed
                // body on every pull — the note could never reach the phone.)
                if Self.isBlankContent(merged[key]), !Self.isBlankContent(remoteValue) {
                    merged[key] = remoteValue
                    contentAdoptedFromRemote.insert(key)
                }
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

        // Rich documents ride with their text field: when a blank local
        // body/title adopted the remote text, the metadata documents must
        // follow, or the editor keeps rendering the stale empty document
        // (metadata beats the plaintext fallback in
        // RichDocumentPersistence.loadAtomDocument).
        if !contentAdoptedFromRemote.isEmpty {
            merged["metadata"] = Self.metadataAdoptingRemoteDocuments(
                merged: merged["metadata"],
                remote: remoteData["metadata"],
                adoptBody: contentAdoptedFromRemote.contains("body"),
                adoptTitle: contentAdoptedFromRemote.contains("title")
            )
        }

        // BEFORE the local-wins resolution lands, preserve any remote user content
        // it discards so a multi-device edit is recoverable instead of vanishing.
        // Fields adopted FROM remote didn't lose — nothing of theirs to preserve.
        await snapshotDiscardedRemote(
            table: table,
            uuid: uuid,
            localData: localData,
            remoteData: remoteData,
            contentFields: ["title", "content", "body", "description"].filter { !contentAdoptedFromRemote.contains($0) }
        )

        // `_server_version` stays LOCAL: it is this device's push-ack counter
        // and only pushChange's ack may advance it. The merged row deliberately
        // remains local-ahead so SyncQueueReconciler uploads the merge result;
        // the ack then closes the gap and later pulls apply cleanly.
        // merged comes from rowToDictionary — GRDB row values are Int64, so
        // coerce both widths (the bare `as? Int` read always failed).
        let currentSyncVersion = (merged["_sync_version"] as? Int)
            ?? (merged["_sync_version"] as? Int64).map(Int.init)
            ?? 0
        merged["_sync_version"] = currentSyncVersion + 1

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
        // canvas_drawings: same TEXT-PK contract, and the local table has no
        // uuid column — the cloud uuid becomes the local id.
        if table == "canvas_drawings" {
            if insertData["id"] == nil {
                insertData["id"] = insertData["uuid"] as? String ?? UUID().uuidString
            }
            insertData.removeValue(forKey: "uuid")
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
        let keyColumn = ["canvas_blocks", "canvas_drawings"].contains(table) ? "id" : "uuid"

        do {
            try await database.asyncWrite { db in
                try CanvasBlockSyncObserver.suppressingSync {
                    // canvas_drawings rows carry no uuid column locally — their id IS the cloud key.
                    let uuidValue = insertData["uuid"] as? String ?? (insertData["id"] as? String ?? "")
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
            let description = String(describing: error)
            if description.contains("no such column") {
                // Systemic, not per-row: a cloud-side migration added a column
                // the local schema lacks, so EVERY pulled row is being dropped
                // while pushes keep working — the "device silently falls
                // behind" failure. PersistenceHealth dedupes its note, so
                // without this line the console looks deceptively quiet.
                print("🚨 SCHEMA DRIFT on \(table): remote rows carry a column the local schema lacks — all pulls are being dropped until a local migration adds it. \(description)")
            }
            print("❌ Remote insert failed: \(error)")
            PersistenceHealth.note(.writeFailure, context: "ConflictResolver.applyRemoteInsert(\((insertData["uuid"] as? String ?? "?").prefix(8)))", detail: String(describing: error))
        }
    }

    // MARK: - Apply Remote Update
    private func applyRemoteUpdate(table: String, uuid: String, data: [String: Any]) async {
        var updateData = data

        // `_server_version` is this device's push-ack counter — remote payloads
        // must never move it. This line used to adopt the server's `_version`
        // column, which froze at its insert-time default (no client bumps it),
        // so every clean apply REGRESSED the counter to ~1. The next pull then
        // saw the row as "local-ahead" and fell into handleConflict's
        // local-wins merge forever — a device that had once edited an atom
        // could never accept remote updates to it again (the July 22 2026
        // "note stays empty on iPhone" bug).
        updateData.removeValue(forKey: "_server_version")
        updateData.removeValue(forKey: "_local_version")
        updateData.removeValue(forKey: "_local_pending")

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
        if table == "canvas_drawings" {
            updateData.removeValue(forKey: "uuid")
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
        let keyColumn = ["canvas_blocks", "canvas_drawings"].contains(table) ? "id" : "uuid"
        let sql = "UPDATE \(table) SET \(setClause) WHERE \(keyColumn) = ?"

        var dbArgsArray = values.map { databaseValue(from: $0) }
        dbArgsArray.append(databaseValue(from: uuid))
        let finalArgs = dbArgsArray

        do {
            try await database.asyncWrite { db in
                // Version history: a remote write is about to replace the local
                // row — keep the local pre-image so sync can never eat content.
                if table == Atom.databaseTableName {
                    AtomRevisionWriter.snapshotBeforeRemoteApply(db, uuid: uuid)
                }
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

// MARK: - Content-Preservation Policy (pure — unit-tested, iOS-mirrored)
//
// The July 22 2026 cross-device note incident: an iPhone-created note synced
// its empty scaffold everywhere; the phone's copy then rejected the Mac's
// typed content on every pull (blank-local-wins + regressed ack counter),
// while its own re-pushed blank row could wipe the Mac's full note through
// the clean-apply overwrite. These helpers encode the two laws that close
// that class of bug: blank content never beats substantial content, and a
// blank remote body never blind-overwrites a substantial local one.
// CosmoOS-iOS/CosmoCoreKit/Sources/Sync/ConflictResolver.swift carries the
// identical implementations — keep them in lockstep.
extension ConflictResolver {
    /// A content value is "blank" when it carries no user text — nil/NSNull or
    /// whitespace-only. Non-string values are never blank (unknown payload
    /// shapes must not trigger content adoption).
    nonisolated static func isBlankContent(_ value: Any?) -> Bool {
        guard let value, !(value is NSNull) else { return true }
        guard let string = value as? String else { return false }
        return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True when applying `remoteData` over `localData` would replace a
    /// substantial local atom body with a blank one. Absent body keys are safe
    /// (the UPDATE leaves the local column untouched).
    nonisolated static func remoteWouldBlankLocalContent(
        table: String,
        localData: [String: Any],
        remoteData: [String: Any]
    ) -> Bool {
        guard table == "atoms" else { return false }
        guard remoteData.keys.contains("body") else { return false }
        return isBlankContent(remoteData["body"]) && !isBlankContent(localData["body"])
    }

    /// Carries the rich-document metadata keys along with an adopted text
    /// field: when the blank local body/title lost to remote content, the
    /// remote's document replaces the stale empty local document — and when
    /// the remote has no document at all, the stale local one is REMOVED so
    /// the adopted plaintext fallback can render.
    nonisolated static func metadataAdoptingRemoteDocuments(
        merged: Any?,
        remote: Any?,
        adoptBody: Bool,
        adoptTitle: Bool
    ) -> Any {
        var adoptedKeys: [String] = []
        if adoptBody { adoptedKeys.append(RichDocumentMetadataKeys.bodyDocument) }
        if adoptTitle { adoptedKeys.append(RichDocumentMetadataKeys.titleDocument) }
        guard !adoptedKeys.isEmpty else { return merged ?? NSNull() }

        let remoteDict = remote.flatMap(Self.parseJSONDict)
        guard var mergedDict = merged.flatMap(Self.parseJSONDict) else {
            // No usable merged metadata — the remote copy (which carries the
            // adopted documents) is strictly better than a blank/unparseable one.
            if let remoteDict,
               let data = try? JSONSerialization.data(withJSONObject: remoteDict),
               let json = String(data: data, encoding: .utf8) {
                return json
            }
            return merged ?? NSNull()
        }

        for key in adoptedKeys {
            if let remoteValue = remoteDict?[key] {
                mergedDict[key] = remoteValue
            } else {
                mergedDict.removeValue(forKey: key)
            }
        }

        if let data = try? JSONSerialization.data(withJSONObject: mergedDict),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return merged ?? NSNull()
    }

    /// Metadata is a JSON string locally but a JSONB dictionary on payloads
    /// straight from Postgres — accept both shapes.
    nonisolated static func parseJSONDict(_ value: Any) -> [String: Any]? {
        if let dict = value as? [String: Any] { return dict }
        if let string = value as? String,
           let data = string.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return dict
        }
        return nil
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
