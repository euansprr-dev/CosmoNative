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

// MARK: - Canvas Block Sync
extension SpatialEngine {
    func saveBlockAndSync(_ block: CanvasBlock) async {
        await saveBlockToDatabase(block)

        Task {
            let syncableBlock = SyncableCanvasBlock(block: block)
            await ChangeTracker.shared.trackUpdate(
                table: "canvas_blocks",
                entity: syncableBlock
            )
        }
    }

    private func saveBlockToDatabase(_ block: CanvasBlock) async {
        let database = CosmoDatabase.shared

        try? await database.asyncWrite { db in
            try db.execute(
                sql: """
                UPDATE canvas_blocks
                SET position_x = ?, position_y = ?, width = ?, height = ?,
                    z_index = ?, updated_at = ?,
                    _local_version = _local_version + 1, _local_pending = 1
                WHERE id = ?
                """,
                arguments: [
                    Int(block.position.x),
                    Int(block.position.y),
                    Int(block.size.width),
                    Int(block.size.height),
                    block.zIndex,
                    ISO8601DateFormatter().string(from: Date()),
                    block.id
                ]
            )
        }
    }
}

// MARK: - Syncable Canvas Block Wrapper
struct SyncableCanvasBlock: Syncable {
    let id: Int64? = nil
    let uuid: String
    let positionX: Int
    let positionY: Int
    let width: Int
    let height: Int
    let isCollapsed: Bool
    let zIndex: Int

    init(block: CanvasBlock) {
        self.uuid = block.id
        self.positionX = Int(block.position.x)
        self.positionY = Int(block.position.y)
        self.width = Int(block.size.width)
        self.height = Int(block.size.height)
        self.isCollapsed = false
        self.zIndex = block.zIndex
    }

    func getUUID() -> String? {
        return uuid
    }

    enum CodingKeys: String, CodingKey {
        case uuid
        case positionX = "position_x"
        case positionY = "position_y"
        case width, height
        case isCollapsed = "is_collapsed"
        case zIndex = "z_index"
    }
}

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
                    ISO8601DateFormatter().string(from: Date()),
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
