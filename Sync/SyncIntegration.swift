// CosmoOS/Sync/SyncIntegration.swift
// Integrates sync with all entity operations
// All changes are tracked automatically through AtomRepository → ChangeTracker → SyncEngine
// Phase 1: Cleaned up legacy table references (research, journal_entries)

import Foundation
import GRDB

enum SyncWriteDisposition: Equatable {
    case upsert
    case update

    static func resolve(requestedOperation: String, serverVersion: Int) -> SyncWriteDisposition {
        if requestedOperation == "INSERT" || serverVersion == 0 {
            return .upsert
        }
        return .update
    }
}

// MARK: - AtomRepository Sync Extensions
// NOTE: AtomRepository already tracks all changes via ChangeTracker.
// These convenience methods exist for explicit sync control if needed.

extension AtomRepository {
    @discardableResult
    func createAndSync(_ atom: Atom) async throws -> Atom {
        return try await create(atom)
    }

    @discardableResult
    func updateAndSync(_ atom: Atom) async throws -> Atom {
        return try await update(atom)
    }

    func deleteAndSync(uuid: String) async throws {
        try await delete(uuid: uuid)
    }
}

// Canvas block sync: handled by CanvasBlockSyncObserver (CanvasBlockRecord.swift),
// which auto-enqueues every local canvas_blocks write for push. The former
// saveBlockAndSync/SyncableCanvasBlock pair here was dead code with the wrong
// cloud keying (partial columns, uuid = placement id while the rest of the
// pipeline keyed by entity uuid).

@MainActor
final class NoteRepairService {
    static let shared = NoteRepairService()

    private let database = CosmoDatabase.shared
    private var isRunning = false

    private init() {}

    func repairNotesIfNeeded() async {
        guard !isRunning else { return }
        await waitForDatabaseReady()
        guard database.isReady else {
            print("[NOTE-REPAIR] Skipping repair — database not ready")
            return
        }

        isRunning = true
        defer { isRunning = false }

        do {
            let noteAtoms = try await fetchNoteAtoms()
            let noteBlocks = try await fetchNoteBlocks()

            var atomsByUUID = Dictionary(uniqueKeysWithValues: noteAtoms.map { ($0.uuid, $0) })
            var atomsByID = Dictionary(uniqueKeysWithValues: noteAtoms.compactMap { atom in
                atom.id.map { ($0, atom) }
            })
            var linkedUUIDs = Set<String>()
            var repairedAtomCount = 0
            var repairedBlockCount = 0

            for block in noteBlocks {
                if let linkedAtom = resolvedAtom(for: block, atomsByUUID: atomsByUUID, atomsByID: atomsByID) {
                    linkedUUIDs.insert(linkedAtom.uuid)
                    let result = try await repairLinked(block: block, atom: linkedAtom)
                    atomsByUUID[result.atom.uuid] = result.atom
                    if let atomID = result.atom.id {
                        atomsByID[atomID] = result.atom
                    }
                    if result.atomChanged { repairedAtomCount += 1 }
                    if result.blockChanged { repairedBlockCount += 1 }
                } else {
                    let result = try await repairOrphanedBlock(block: block)
                    atomsByUUID[result.atom.uuid] = result.atom
                    if let atomID = result.atom.id {
                        atomsByID[atomID] = result.atom
                    }
                    linkedUUIDs.insert(result.atom.uuid)
                    repairedAtomCount += 1
                    repairedBlockCount += 1
                }
            }

            for atom in Array(atomsByUUID.values) where !linkedUUIDs.contains(atom.uuid) {
                let repairedAtom = try await repairStandalone(atom: atom)
                atomsByUUID[repairedAtom.uuid] = repairedAtom
                if let atomID = repairedAtom.id {
                    atomsByID[atomID] = repairedAtom
                }
                if repairedAtom != atom {
                    repairedAtomCount += 1
                }
            }

            if repairedAtomCount > 0 || repairedBlockCount > 0 {
                print("[NOTE-REPAIR] Completed — repairedAtoms=\(repairedAtomCount) repairedBlocks=\(repairedBlockCount)")
            } else {
                print("[NOTE-REPAIR] Completed — no broken notes found")
            }
        } catch {
            print("[NOTE-REPAIR] Failed: \(error)")
        }
    }

    private func waitForDatabaseReady() async {
        for _ in 0..<20 where !database.isReady {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private func fetchNoteAtoms() async throws -> [Atom] {
        try await database.asyncRead { db in
            try Atom
                .filter(Column("type") == AtomType.note.rawValue)
                .filter(Column("is_deleted") == false)
                .fetchAll(db)
        }
    }

    private func fetchNoteBlocks() async throws -> [NoteRepairBlock] {
        try await database.asyncRead { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT id, entity_id, entity_uuid, entity_title, note_content, atom_uuid
                FROM canvas_blocks
                WHERE is_deleted = 0
                  AND entity_type = ?
                """,
                arguments: [EntityType.note.rawValue]
            )
            return rows.map(NoteRepairBlock.init(row:))
        }
    }

    private func resolvedAtom(
        for block: NoteRepairBlock,
        atomsByUUID: [String: Atom],
        atomsByID: [Int64: Atom]
    ) -> Atom? {
        if let atomUUID = block.atomUUID,
           !atomUUID.isEmpty,
           let atom = atomsByUUID[atomUUID] {
            return atom
        }
        if !block.entityUUID.isEmpty, let atom = atomsByUUID[block.entityUUID] {
            return atom
        }
        if block.entityID > 0, let atom = atomsByID[block.entityID] {
            return atom
        }
        return nil
    }

    private func repairLinked(block: NoteRepairBlock, atom: Atom) async throws -> NoteRepairOutcome {
        let titleDocument = RichDocumentPersistence.loadAtomDocument(
            field: .title,
            metadata: atom.metadata,
            fallbackPlainText: atom.title
        )
        let bodyDocument = RichDocumentPersistence.loadAtomDocument(
            field: .body,
            metadata: atom.metadata,
            fallbackPlainText: atom.body,
            preferFallbackPlainTextWhenRicher: true
        )

        let titleFromDocument = RichDocumentPersistence.titlePlainText(from: titleDocument)
        let bodyFromDocument = bodyDocument.plainText
        let canonicalTitle = preferredNoteTitle([titleFromDocument, atom.title, block.entityTitle])
        let canonicalBody = RichDocumentPersistence.richestPlainText([
            atom.body,
            bodyFromDocument,
            block.noteContent
        ])

        let canonicalTitleDocument = canonicalTitle == titleFromDocument
            ? titleDocument
            : RichDocument.migrateLegacy(canonicalTitle)
        let canonicalBodyDocument = canonicalBody == bodyFromDocument
            ? bodyDocument
            : RichDocument.migrateLegacy(canonicalBody)
        let snapshot = RichDocumentPersistence.noteSnapshot(
            existingMetadata: atom.metadata,
            titleDocument: canonicalTitleDocument,
            bodyDocument: canonicalBodyDocument,
            plainBodyText: canonicalBody
        )

        var repairedAtom = atom
        let atomNeedsUpdate =
            repairedAtom.title != snapshot.atomTitle ||
            repairedAtom.body != snapshot.atomBody ||
            repairedAtom.metadata != snapshot.metadata

        if atomNeedsUpdate {
            repairedAtom.title = snapshot.atomTitle
            repairedAtom.body = snapshot.atomBody
            repairedAtom.metadata = snapshot.metadata
            repairedAtom = try await AtomRepository.shared.update(repairedAtom)
        } else if repairedAtom.serverVersion == 0 {
            await ChangeTracker.shared.trackInsert(table: "atoms", entity: repairedAtom)
        }

        let blockChanged = try await updateBlockRow(
            block,
            linkedAtom: repairedAtom,
            title: snapshot.titlePlainText,
            body: snapshot.bodyPlainText
        )

        return NoteRepairOutcome(
            atom: repairedAtom,
            atomChanged: atomNeedsUpdate,
            blockChanged: blockChanged
        )
    }

    private func repairStandalone(atom: Atom) async throws -> Atom {
        let titleDocument = RichDocumentPersistence.loadAtomDocument(
            field: .title,
            metadata: atom.metadata,
            fallbackPlainText: atom.title
        )
        let bodyDocument = RichDocumentPersistence.loadAtomDocument(
            field: .body,
            metadata: atom.metadata,
            fallbackPlainText: atom.body,
            preferFallbackPlainTextWhenRicher: true
        )

        let titleFromDocument = RichDocumentPersistence.titlePlainText(from: titleDocument)
        let bodyFromDocument = bodyDocument.plainText
        let canonicalTitle = preferredNoteTitle([titleFromDocument, atom.title])
        let canonicalBody = RichDocumentPersistence.richestPlainText([atom.body, bodyFromDocument])
        let canonicalTitleDocument = canonicalTitle == titleFromDocument
            ? titleDocument
            : RichDocument.migrateLegacy(canonicalTitle)
        let canonicalBodyDocument = canonicalBody == bodyFromDocument
            ? bodyDocument
            : RichDocument.migrateLegacy(canonicalBody)
        let snapshot = RichDocumentPersistence.noteSnapshot(
            existingMetadata: atom.metadata,
            titleDocument: canonicalTitleDocument,
            bodyDocument: canonicalBodyDocument,
            plainBodyText: canonicalBody
        )

        if atom.title != snapshot.atomTitle || atom.body != snapshot.atomBody || atom.metadata != snapshot.metadata {
            var repairedAtom = atom
            repairedAtom.title = snapshot.atomTitle
            repairedAtom.body = snapshot.atomBody
            repairedAtom.metadata = snapshot.metadata
            return try await AtomRepository.shared.update(repairedAtom)
        }

        if atom.serverVersion == 0 {
            await ChangeTracker.shared.trackInsert(table: "atoms", entity: atom)
        }

        return atom
    }

    private func repairOrphanedBlock(block: NoteRepairBlock) async throws -> NoteRepairOutcome {
        let canonicalTitle = preferredNoteTitle([block.entityTitle])
        let canonicalBody = RichDocumentPersistence.richestPlainText([block.noteContent])
        let snapshot = RichDocumentPersistence.noteSnapshot(
            existingMetadata: nil,
            titleDocument: RichDocument.migrateLegacy(canonicalTitle),
            bodyDocument: RichDocument.migrateLegacy(canonicalBody),
            plainBodyText: canonicalBody
        )

        var repairedAtom = Atom.new(
            type: .note,
            title: snapshot.atomTitle,
            body: snapshot.atomBody,
            metadata: snapshot.metadata
        )
        if let preferredUUID = preferredAtomUUID(for: block) {
            repairedAtom.uuid = preferredUUID
        }

        let createdAtom = try await AtomRepository.shared.create(repairedAtom)
        _ = try await updateBlockRow(
            block,
            linkedAtom: createdAtom,
            title: snapshot.titlePlainText,
            body: snapshot.bodyPlainText
        )

        return NoteRepairOutcome(atom: createdAtom, atomChanged: true, blockChanged: true)
    }

    private func updateBlockRow(
        _ block: NoteRepairBlock,
        linkedAtom: Atom,
        title: String,
        body: String
    ) async throws -> Bool {
        let displayTitle = title.isEmpty ? "Note" : title
        let atomID = linkedAtom.id ?? block.entityID
        let needsUpdate =
            block.entityID != atomID ||
            block.entityUUID != linkedAtom.uuid ||
            block.atomUUID != linkedAtom.uuid ||
            block.entityTitle != displayTitle ||
            block.noteContent != body

        guard needsUpdate else { return false }

        try await database.asyncWrite { db in
            try db.execute(
                sql: """
                UPDATE canvas_blocks
                SET entity_id = ?,
                    entity_uuid = ?,
                    atom_uuid = ?,
                    entity_title = ?,
                    note_content = ?,
                    updated_at = ?,
                    _local_version = _local_version + 1,
                    _local_pending = 1
                WHERE id = ?
                """,
                arguments: [
                    atomID,
                    linkedAtom.uuid,
                    linkedAtom.uuid,
                    displayTitle,
                    body,
                    ISO8601.string(from: Date()),
                    block.id
                ]
            )
        }

        return true
    }

    private func preferredNoteTitle(_ candidates: [String?]) -> String {
        candidates
            .compactMap { candidate -> String? in
                guard let candidate else { return nil }
                let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                guard !["Note", "Untitled", "Untitled Note"].contains(trimmed) else { return nil }
                return trimmed
            }
            .max(by: { $0.count < $1.count }) ?? ""
    }

    private func preferredAtomUUID(for block: NoteRepairBlock) -> String? {
        [block.atomUUID, block.entityUUID]
            .compactMap { candidate -> String? in
                guard let candidate else { return nil }
                let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .first
    }
}

private struct NoteRepairBlock {
    let id: String
    let entityID: Int64
    let entityUUID: String
    let entityTitle: String?
    let noteContent: String?
    let atomUUID: String?

    init(row: Row) {
        id = row["id"] ?? ""
        entityID = row["entity_id"] ?? 0
        entityUUID = row["entity_uuid"] ?? ""
        entityTitle = row["entity_title"]
        noteContent = row["note_content"]
        atomUUID = row["atom_uuid"]
    }
}

private struct NoteRepairOutcome {
    let atom: Atom
    let atomChanged: Bool
    let blockChanged: Bool
}


// MARK: - Durable capture outbox

/// Capture rows and their upload payload commit in the SAME SQLite transaction.
/// The async tracker is only a delivery kick; quitting before it runs is safe.
/// Keep this contract identical on Mac and iPhone.
enum CaptureSyncOutbox {
    static let tables = ["capture_destinations", "inbox_items", "captured_items", "media_attachments", "capture_requests", "seedlings"]

    struct Snapshot: Sendable {
        let table: String
        let uuid: String
        let data: String
        let localVersion: Int
        let serverVersion: Int
        let isDeleted: Bool
        var operation: String { serverVersion == 0 ? "INSERT" : "UPDATE" }
    }

    static func snapshot(_ db: Database, table: String, uuid: String) throws -> Snapshot? {
        func encode<T: Encodable>(_ record: T?) throws -> Snapshot? {
            guard let record else { return nil }
            let data = try JSONEncoder().encode(record)
            let fields = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            return Snapshot(
                table: table, uuid: uuid, data: String(decoding: data, as: UTF8.self),
                localVersion: fields["_local_version"] as? Int ?? 1,
                serverVersion: fields["_server_version"] as? Int ?? 0,
                isDeleted: fields["is_deleted"] as? Bool ?? false
            )
        }
        switch table {
        case "inbox_items": return try encode(InboxItem.filter(Column("uuid") == uuid).fetchOne(db))
        case "captured_items": return try encode(CapturedItem.filter(Column("uuid") == uuid).fetchOne(db))
        case "capture_destinations": return try encode(CaptureDestination.filter(Column("uuid") == uuid).fetchOne(db))
        case "media_attachments": return try encode(MediaAttachment.filter(Column("uuid") == uuid).fetchOne(db))
        case "capture_requests": return try encode(CaptureRequest.filter(Column("uuid") == uuid).fetchOne(db))
        case "seedlings": return try encode(Seedling.filter(Column("uuid") == uuid).fetchOne(db))
        default: return nil
        }
    }

    @discardableResult
    static func enqueue(_ db: Database, table: String, uuid: String) throws -> Snapshot? {
        guard let current = try snapshot(db, table: table, uuid: uuid) else { return nil }
        try db.execute(sql: "UPDATE \(table) SET _local_pending = 1 WHERE uuid = ?", arguments: [uuid])
        let existing = try Row.fetchOne(
            db, sql: "SELECT id, local_version FROM sync_queue WHERE table_name = ? AND uuid = ? AND status = 'pending' ORDER BY local_version DESC LIMIT 1",
            arguments: [table, uuid]
        )
        if let id = existing?["id"] as Int64? {
            // A delayed delegate must never relabel an older payload with a
            // newer version. Always encode the current row inside this write.
            guard (existing?["local_version"] as Int? ?? 0) <= current.localVersion else { return nil }
            try db.execute(sql: """
                UPDATE sync_queue
                SET operation = ?, data = ?,
                    retry_count = CASE WHEN local_version < ? THEN 0 ELSE retry_count END,
                    error_message = CASE WHEN local_version < ? THEN NULL ELSE error_message END,
                    local_version = ?, created_at = ?
                WHERE id = ?
                """, arguments: [current.operation, current.data, current.localVersion, current.localVersion,
                                  current.localVersion, Int64(Date().timeIntervalSince1970 * 1000), id])
        } else {
            try db.execute(sql: """
                INSERT INTO sync_queue (uuid, table_name, operation, data, local_version, status)
                VALUES (?, ?, ?, ?, ?, 'pending')
                """, arguments: [uuid, table, current.operation, current.data, current.localVersion])
        }
        return current
    }

    /// Recover older captures saved before their async tracker ran. Failed or
    /// dead-lettered uploads retain their existing retry/review policy.
    static func reconcileUnqueued(_ db: Database) throws -> Int {
        var count = 0
        for table in tables where try db.tableExists(table) {
            let uuids = try String.fetchAll(db, sql: """
                SELECT uuid FROM \(table) AS capture
                WHERE (_server_version = 0 OR _local_version > _server_version OR _local_pending = 1)
                  AND NOT EXISTS (
                    SELECT 1 FROM sync_queue AS q
                    WHERE q.table_name = ? AND q.uuid = capture.uuid
                      AND q.status IN ('pending', 'failed', 'abandoned')
                  )
                """, arguments: [table])
            for uuid in uuids {
                if try enqueue(db, table: table, uuid: uuid) != nil { count += 1 }
            }
        }
        return count
    }

    /// The old UPDATE-before-first-upload bug left a false success receipt.
    /// Return today's local row, NEVER replay the potentially stale receipt.
    static func falseAcknowledgementCandidates(_ db: Database) throws -> [Snapshot] {
        var candidates: [Snapshot] = []
        for table in tables where try db.tableExists(table) {
            let uuids = try String.fetchAll(db, sql: """
                SELECT DISTINCT uuid FROM sync_queue
                WHERE table_name = ? AND operation = 'UPDATE' AND status = 'synced'
                  AND CASE WHEN json_valid(data) THEN json_extract(data, '$._server_version') = 0 ELSE 0 END
                """, arguments: [table])
            for uuid in uuids {
                if let current = try snapshot(db, table: table, uuid: uuid), !current.isDeleted {
                    candidates.append(current)
                }
            }
        }
        return candidates
    }

    static func recoveryPayload(_ snapshot: Snapshot, userID: String, source: String) throws -> [String: Any] {
        var payload = try JSONSerialization.jsonObject(with: Data(snapshot.data.utf8)) as! [String: Any]
        for key in ["id", "_local_version", "_server_version", "_sync_version", "_local_pending"] {
            payload.removeValue(forKey: key)
        }
        payload["user_id"] = userID
        payload["_source"] = source
        // Catch up the other device even if its pull cursor passed the capture.
        payload["updated_at"] = ISO8601.string(from: Date())
        return payload
    }
}
