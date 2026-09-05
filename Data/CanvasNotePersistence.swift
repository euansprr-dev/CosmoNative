import Foundation
import GRDB

/// One transaction owns sticky text, its rich document, and its atom link.
/// Legacy canvas-only stickies acquire an atom on their first edit, giving
/// them the same revision history and sync path as other documents.
enum CanvasNotePersistence {
    struct RecoveryDraft: Codable {
        let document: RichDocument
        let plainText: String
    }

    @MainActor private static func recoveryURL(blockID: String) -> URL {
        // Hex-encode the key so legacy IDs cannot become path components.
        let filename = blockID.utf8.map { String(format: "%02x", $0) }.joined()
        return CosmoDatabase.databasePath.deletingLastPathComponent()
            .appendingPathComponent("draft-recovery", isDirectory: true)
            .appendingPathComponent(filename + ".json")
    }

    @MainActor static func stashRecovery(blockID: String, document: RichDocument, plainText: String) throws {
        let url = recoveryURL(blockID: blockID)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(RecoveryDraft(document: document, plainText: plainText)).write(to: url, options: .atomic)
    }

    @MainActor static func loadRecovery(blockID: String) throws -> RecoveryDraft? {
        let url = recoveryURL(blockID: blockID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(RecoveryDraft.self, from: Data(contentsOf: url))
    }

    @MainActor static func clearRecovery(blockID: String) throws {
        let url = recoveryURL(blockID: blockID)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    struct SavedSticky {
        let atom: Atom
        let metadata: [String: String]
    }

    enum SaveError: LocalizedError {
        case missingBlock
        case deletedAtom

        var errorDescription: String? {
            switch self {
            case .missingBlock: return "The canvas item is no longer available."
            case .deletedAtom: return "This sticky note was deleted while it was being edited."
            }
        }
    }

    static func saveSticky(
        in db: Database, blockID: String, document: RichDocument, plainText: String
    ) throws -> SavedSticky {
        if blockID.hasPrefix("composition:") {
            let parts = blockID.split(separator: ":", maxSplits: 2).map(String.init)
            guard parts.count == 3,
                  let container = try Atom.filter(Column("uuid") == parts[1]).filter(Column("is_deleted") == false).fetchOne(db),
                  try SpaceCanvasPersistence.items(in: container, db: db).contains(where: { $0.uuid == parts[2] }),
                  let atom = try Atom.filter(Column("uuid") == parts[2]).filter(Column("is_deleted") == false).fetchOne(db) else { throw SaveError.missingBlock }
            let current = document.plainText == plainText ? document : RichDocument.migrateLegacy(plainText)
            let fields = RichDocumentPersistence.writeAtomDocuments(existingMetadata: atom.metadata, bodyDocument: current)
            AtomRevisionWriter.snapshotBeforeRawWrite(db, uuid: atom.uuid, incomingTitle: atom.title, incomingBody: plainText)
            try db.execute(sql: """
                UPDATE atoms SET body = ?, metadata = ?, updated_at = ?, _local_version = _local_version + 1, _local_pending = 1
                WHERE uuid = ? AND is_deleted = 0
                """, arguments: [plainText, fields.metadata, ISO8601.string(from: Date()), atom.uuid])
            guard let saved = try Atom.filter(Column("uuid") == atom.uuid).fetchOne(db) else { throw SaveError.deletedAtom }
            var metadata = RichDocumentPersistence.writeBlockDocument(current, key: RichDocumentMetadataKeys.bodyDocument, metadata: [:])
            metadata["content"] = plainText
            return SavedSticky(atom: saved, metadata: metadata)
        }
        guard let row = try Row.fetchOne(db,
            sql: "SELECT * FROM canvas_blocks WHERE id = ? AND is_deleted = 0",
            arguments: [blockID]
        ) else { throw SaveError.missingBlock }

        // Decode strictly: a malformed payload must not become an empty
        // dictionary that silently erases unrelated saved fields.
        let json: String? = row["metadata"]
        var metadata: [String: String] = [:]
        if let json, !json.isEmpty {
            metadata = try JSONDecoder().decode([String: String].self, from: Data(json.utf8))
        }
        let existingUUID: String? = row["entity_uuid"]
        let uuid = existingUUID.flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString
        var atom = try Atom.filter(Column("uuid") == uuid).fetchOne(db)
        if atom?.isDeleted == true { throw SaveError.deletedAtom }
        if atom == nil {
            // Preserve the pre-edit legacy content in history, too.
            var created = Atom.new(type: .stickyNote, body: row["note_content"])
            created.uuid = uuid
            let oldDocument = RichDocumentPersistence.loadBlockDocument(
                key: RichDocumentMetadataKeys.bodyDocument, metadata: metadata,
                fallbackPlainText: row["note_content"]
            )
            created.metadata = RichDocumentPersistence.writeAtomDocuments(
                existingMetadata: nil, bodyDocument: oldDocument
            ).metadata
            try created.insert(db)
            created.id = db.lastInsertedRowID
            atom = created
        }
        guard var saved = atom else { throw SaveError.missingBlock }
        let currentDocument = document.plainText == plainText
            ? document : RichDocument.migrateLegacy(plainText)
        let fields = RichDocumentPersistence.writeAtomDocuments(
            existingMetadata: saved.metadata, bodyDocument: currentDocument
        )
        AtomRevisionWriter.snapshotBeforeRawWrite(db, uuid: uuid,
            incomingTitle: saved.title, incomingBody: plainText)
        try db.execute(sql: """
            UPDATE atoms SET body = ?, metadata = ?, updated_at = ?,
                _local_version = _local_version + 1, _local_pending = 1
            WHERE uuid = ? AND is_deleted = 0
            """, arguments: [plainText, fields.metadata, ISO8601.string(from: Date()), uuid])
        guard let refreshed = try Atom.filter(Column("uuid") == uuid).fetchOne(db) else { throw SaveError.deletedAtom }
        saved = refreshed
        metadata = RichDocumentPersistence.writeBlockDocument(
            currentDocument, key: RichDocumentMetadataKeys.bodyDocument, metadata: metadata
        )
        metadata["content"] = plainText
        try db.execute(sql: """
            UPDATE canvas_blocks SET entity_id = ?, entity_uuid = ?, atom_uuid = ?,
                note_content = ?, metadata = ?, updated_at = ?,
                _local_version = _local_version + 1, _local_pending = 1
            WHERE id = ? AND is_deleted = 0
            """, arguments: [saved.id, uuid, uuid, plainText,
                              SpatialEngine.encodeBlockMetadataJSON(metadata), ISO8601.string(from: Date()), blockID])
        return SavedSticky(atom: saved, metadata: metadata)
    }
}
