// CosmoOS/Canvas/SpatialEngine.swift
// Voice-driven spatial placement and layout system

import Foundation
import SwiftUI
import GRDB

@MainActor
@Observable
class SpatialEngine {
    var blocks: [CanvasBlock] = [] {
        didSet { blocksDataRevision &+= 1 }
    }
    var isLoading = false
    private(set) var blocksDataRevision = 0

    private let database: CosmoDatabase
    private let localLLM: LocalLLM

    // Current document context
    var currentDocumentType: String = "home"
    var currentDocumentId: Int64 = 0
    var currentThinkspaceId: String? = nil

    /// In-flight (debounced/fire-and-forget) geometry writes, flushed
    /// synchronously at app termination so the last drag never loses its save.
    private struct PendingGeometry {
        var position: CGPoint
        var size: CGSize?
    }
    private var pendingGeometryWrites: [String: PendingGeometry] = [:]
    private let dirtyRegistryId = "spatial-engine-\(UUID().uuidString)"

    convenience init() {
        self.init(database: .shared, localLLM: .shared)
    }

    init(database: CosmoDatabase, localLLM: LocalLLM) {
        self.database = database
        self.localLLM = localLLM
        DirtyEditorRegistry.shared.register(id: dirtyRegistryId) { [weak self] in
            self?.flushPendingGeometryWritesSync()
        }
    }

    deinit {
        let id = dirtyRegistryId
        Task { @MainActor in
            DirtyEditorRegistry.shared.unregister(id: id)
        }
    }

    /// Synchronous, DB-only flush of any in-flight position/size writes.
    /// Called by DirtyEditorRegistry at app termination.
    private func flushPendingGeometryWritesSync() {
        guard !pendingGeometryWrites.isEmpty else { return }
        let writes = pendingGeometryWrites
        do {
            try database.write { db in
                for (blockId, geometry) in writes {
                    if let size = geometry.size {
                        try db.execute(
                            sql: """
                            UPDATE canvas_blocks
                            SET position_x = ?, position_y = ?, width = ?, height = ?, updated_at = CURRENT_TIMESTAMP
                            WHERE id = ?
                            """,
                            arguments: [
                                Int(geometry.position.x), Int(geometry.position.y),
                                Int(size.width), Int(size.height), blockId
                            ]
                        )
                    } else {
                        try db.execute(
                            sql: "UPDATE canvas_blocks SET position_x = ?, position_y = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
                            arguments: [Int(geometry.position.x), Int(geometry.position.y), blockId]
                        )
                    }
                }
            }
            pendingGeometryWrites.removeAll()
        } catch {
            PersistenceHealth.note(.writeFailure, context: "spatialEngine.terminateFlush", detail: "\(writes.count) pending geometry write(s) lost: \(error)")
            print("❌ Failed to flush pending geometry writes: \(error)")
        }
    }

    /// Serialize a block's metadata dictionary for the canvas_blocks.metadata column.
    nonisolated static func encodeBlockMetadataJSON(_ metadata: [String: String]) -> String? {
        guard !metadata.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(metadata)).flatMap { String(data: $0, encoding: .utf8) }
    }

    nonisolated static func decodeBlockMetadataJSON(_ json: String?) -> [String: String]? {
        guard let json, !json.isEmpty, let data = json.data(using: .utf8) else { return nil }
        guard let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            PersistenceHealth.note(.decodeFailure, context: "canvasBlocks.metadata", detail: "undecodable metadata column JSON (\(json.count) chars)")
            return nil
        }
        return decoded
    }

    // MARK: - Load Blocks from Database
    func loadBlocks(for documentType: String = "home", documentId: Int64 = 0, thinkspaceId: String? = nil) async {
        let signpost = CanvasPerformanceInstrumentation.signposter.beginInterval("thinkspace-load-blocks")
        isLoading = true
        currentDocumentType = documentType
        currentDocumentId = documentId
        currentThinkspaceId = thinkspaceId

        let deduped = await fetchBlocksSnapshot(for: documentType, documentId: documentId, thinkspaceId: thinkspaceId)

        // Guard: don't apply results if the switch was cancelled or superseded.
        guard let deduped, !Task.isCancelled, thinkspaceId == currentThinkspaceId else {
            isLoading = false
            CanvasPerformanceInstrumentation.signposter.endInterval("thinkspace-load-blocks", signpost)
            return
        }
        self.blocks = deduped
        isLoading = false
        CanvasPerformanceInstrumentation.signposter.endInterval("thinkspace-load-blocks", signpost)
        print("✅ Loaded \(deduped.count) canvas blocks for \(documentType)/\(documentId)")
    }

    /// Fetch and build the fully-enriched block array WITHOUT mutating engine
    /// state, so a thinkspace switch can overlap this work with its exit
    /// animation. DB reads run on the GRDB pool; the record→block conversion
    /// (including per-atom metadata JSON decoding) runs off the main actor.
    /// Returns nil on error so callers can preserve existing state.
    func fetchBlocksSnapshot(for documentType: String = "home", documentId: Int64 = 0, thinkspaceId: String? = nil) async -> [CanvasBlock]? {
        do {
            let tsId = thinkspaceId  // Capture for closure
            let (savedBlocks, metadataJSONByBlockId): ([CanvasBlockRecord], [String: String]) = try await database.asyncRead { db in
                var query = CanvasBlockRecord
                    .filter(Column("document_type") == documentType)
                    .filter(Column("document_id") == documentId)
                    .filter(Column("is_deleted") == false)
                    // Thinkspace portals were removed July 2026 — rows persist
                    // in the DB (feature could return) but must never render;
                    // without this filter they'd fall into the default block
                    // chrome as inert cards.
                    .filter(Column("entity_type") != "portal")
                    // Membership without position: only PLACED rows are world
                    // blocks. Unplaced members show in the tray/library/board.
                    .filter(Column("is_placed") == true)

                // Filter by ThinkSpace if provided
                if let thinkspaceId = tsId {
                    query = query.filter(Column("thinkspace_id") == thinkspaceId)
                } else {
                    // If no thinkspace specified, only load blocks without a thinkspace
                    query = query.filter(Column("thinkspace_id") == nil)
                }

                var records = try query.order(Column("z_index")).fetchAll(db)

                // Shield: never render a placement whose atom is tombstoned. Sync
                // gaps can orphan canvas_blocks rows (atom deleted on another
                // device); the block would otherwise render from its cached
                // entity_title forever. Blocks without an atom row (sticky notes,
                // legacy metadata-backed notes) are untouched.
                let atomUuids = records.compactMap(\.entityUuid).filter { !$0.isEmpty }
                if !atomUuids.isEmpty {
                    let tombstonedUuids = try String.fetchSet(
                        db,
                        Atom
                            .filter(atomUuids.contains(Column("uuid")))
                            .filter(Column("is_deleted") == true)
                            .select(Column("uuid"), as: String.self)
                    )
                    if !tombstonedUuids.isEmpty {
                        records.removeAll { record in
                            guard let uuid = record.entityUuid, !uuid.isEmpty else { return false }
                            return tombstonedUuids.contains(uuid)
                        }
                    }
                }

                // The metadata column (sticky color, rich body document, …) is not
                // part of CanvasBlockRecord — fetch it separately and key by block id.
                var metadataById: [String: String] = [:]
                let metadataRows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT id, metadata FROM canvas_blocks
                        WHERE document_type = ? AND document_id = ? AND is_deleted = 0 AND is_placed = 1 AND thinkspace_id IS ?
                    """,
                    arguments: [documentType, documentId, tsId]
                )
                for row in metadataRows {
                    if let id: String = row["id"], let json: String = row["metadata"] {
                        metadataById[id] = json
                    }
                }
                return (records, metadataById)
            }

            // Batch-fetch the entity atoms for EVERY block in two reads instead
            // of one DB round-trip per block during thinkspace switches. The
            // enrichment below still only rewrites rich block types; the full
            // batch feeds CanvasAtomWarmStore so mounting block views read
            // their atom synchronously instead of re-fetching what this switch
            // just loaded.
            let idsToFetch = savedBlocks
                .map { Int64($0.entityId) }
                .filter { $0 > 0 }
            let uuidsToFetch = savedBlocks
                .compactMap(\.entityUuid)
                .filter { !$0.isEmpty }

            async let atomsByIDTask = AtomRepository.shared.fetchBatch(ids: Array(Set(idsToFetch)))
            async let atomsByUUIDTask = AtomRepository.shared.fetchBatch(uuids: Array(Set(uuidsToFetch)))
            let fetchedAtomsByID = try await atomsByIDTask
            let fetchedAtomsByUUID = try await atomsByUUIDTask

            // Warm the shared atom store BEFORE returning, so views mounting
            // off this snapshot (and off the cached snapshot the hub keeps
            // fresh) hit it synchronously. Absorb also fans genuinely-newer
            // atoms out to already-mounted subscribers — this is what corrects
            // stale cached-snapshot content as targeted per-atom updates.
            CanvasAtomObservationHub.shared.absorb(fetchedAtomsByID + fetchedAtomsByUUID)

            // Record→block conversion decodes atom metadata JSON per rich block —
            // too heavy for the main actor during a switch animation.
            return await Task.detached(priority: .userInitiated) {
                let blocks = Self.buildBlocks(
                    records: savedBlocks,
                    metadataJSONByBlockId: metadataJSONByBlockId,
                    fetchedAtomsByID: fetchedAtomsByID,
                    fetchedAtomsByUUID: fetchedAtomsByUUID
                )
                // Pre-warm the shared document decode caches while still
                // off-main: the block views run these exact loads
                // synchronously at mount, and a switch mounts every visible
                // card in one frame — cold decodes of multi-hundred-KB
                // metadata columns belong here, not in the swap frame.
                // (Both caches are lock-guarded and Sendable.)
                Self.prewarmDocumentDecodeCaches(atoms: fetchedAtomsByID + fetchedAtomsByUUID)
                return blocks
            }.value
        } catch {
            PersistenceHealth.note(.writeFailure, context: "canvas.load", detail: "Could not load saved canvas data: \(error)")
            print("❌ Failed to load canvas blocks: \(error)")
            return nil
        }
    }

    /// Apply a snapshot from fetchBlocksSnapshot as the current canvas state.
    /// Cheap main-thread array swap; nil (fetch error) preserves existing blocks.
    func applyFetchedBlocks(_ fetched: [CanvasBlock]?, for documentType: String = "home", documentId: Int64 = 0, thinkspaceId: String? = nil) {
        currentDocumentType = documentType
        currentDocumentId = documentId
        currentThinkspaceId = thinkspaceId
        guard let fetched else { return }
        blocks = fetched
        isLoading = false
        print("✅ Loaded \(fetched.count) canvas blocks for \(documentType)/\(documentId)")
    }

    /// Runs the same cache-backed document loads the block views perform at
    /// mount, so their mount-frame calls become cache hits. Safe off-main:
    /// RichDocumentDecodeCache and Atom.DecodedColumnCache are lock-guarded.
    nonisolated private static func prewarmDocumentDecodeCaches(atoms: [Atom]) {
        for atom in atoms {
            switch atom.type {
            case .note:
                _ = RichDocumentPersistence.loadAtomDocument(
                    field: .title, metadata: atom.metadata, fallbackPlainText: atom.title, atomUUID: atom.uuid
                )
                _ = RichDocumentPersistence.loadAtomDocument(
                    field: .body, metadata: atom.metadata, fallbackPlainText: atom.body, atomUUID: atom.uuid
                )
            case .content:
                _ = RichDocumentMetadataStorage.readDocument(
                    from: atom.metadata, key: RichDocumentMetadataKeys.contentDraftDocument, atomUUID: atom.uuid
                )
                _ = atom.metadataValue(as: ContentAtomMetadata.self)
            case .connection:
                _ = RichDocumentPersistence.loadAtomDocument(
                    field: .title, metadata: atom.metadata, fallbackPlainText: atom.title, atomUUID: atom.uuid
                )
            default:
                break
            }
        }
    }

    nonisolated static func buildBlocks(
        records savedBlocks: [CanvasBlockRecord],
        metadataJSONByBlockId: [String: String] = [:],
        fetchedAtomsByID: [Atom],
        fetchedAtomsByUUID: [Atom]
    ) -> [CanvasBlock] {
        // Convert database records to CanvasBlocks
        var loadedBlocks: [CanvasBlock] = []
        for record in savedBlocks {
                // Build metadata from database record
                var metadata: [String: String] = [:]

                // For note, stickyNote, and content blocks, restore content from note_content field
                // These types use metadata-based storage rather than atoms table
                if (record.entityType == "note" || record.entityType == "sticky_note" || record.entityType == "content"),
                   let noteContent = record.noteContent {
                    metadata["content"] = noteContent
                }

                // For note, stickyNote, and content blocks, also restore title in metadata
                // This is needed because the block views load title from metadata
                if (record.entityType == "note" || record.entityType == "sticky_note" || record.entityType == "content"),
                   let title = record.entityTitle, !title.isEmpty {
                    metadata["title"] = title
                }

                // Restore created timestamp if available
                if let createdAt = record.createdAt {
                    metadata["created"] = createdAt
                }

                // Merge the persisted metadata column (sticky color, rich body
                // document, …). The DB column wins over note_content-derived keys —
                // every writer updates both in the same transaction.
                if let persisted = Self.decodeBlockMetadataJSON(metadataJSONByBlockId[record.id]) {
                    for (key, value) in persisted {
                        metadata[key] = value
                    }
                }

                let block = CanvasBlock(
                    id: record.id,
                    position: CGPoint(x: CGFloat(record.positionX), y: CGFloat(record.positionY)),
                    size: CGSize(width: CGFloat(record.width ?? 220), height: CGFloat(record.height ?? 310)),
                    isPinned: record.isPinned ?? false,  // Read pin state from database
                    zIndex: record.zIndex ?? 0,
                    entityType: EntityType(rawValue: record.entityType) ?? .idea,
                    entityId: Int64(record.entityId),
                    entityUuid: record.entityUuid ?? "",
                    title: record.entityTitle ?? "Untitled",
                    metadata: metadata
                )
                var placedBlock = block
                placedBlock.isPlaced = record.isPlaced ?? true
                loadedBlocks.append(placedBlock)
            }

            let atomsByID = Dictionary(uniqueKeysWithValues: fetchedAtomsByID.compactMap { atom in
                atom.id.map { ($0, atom) }
            })
            let atomsByUUID = Dictionary(uniqueKeysWithValues: fetchedAtomsByUUID.map { ($0.uuid, $0) })

            let enrichedBlocks = loadedBlocks.map { block -> CanvasBlock in
                guard block.entityType == .research ||
                        block.entityType == .image ||
                        block.entityType == .note ||
                        block.entityType == .template ||
                        block.entityType == .file else {
                    return block
                }

                let atom = atomsByID[block.entityId] ?? atomsByUUID[block.entityUuid]
                guard let atom else { return block }

                // Rebuild with proper metadata from atom, preserving DB position/id/pin state/size.
                let fromAtom = CanvasBlock.fromAtom(atom, position: block.position)
                return CanvasBlock(
                    id: block.id,
                    position: block.position,
                    size: block.size,
                    isPinned: block.isPinned,
                    zIndex: block.zIndex,
                    entityType: fromAtom.entityType,
                    entityId: fromAtom.entityId,
                    entityUuid: fromAtom.entityUuid,
                    title: fromAtom.title,
                    subtitle: fromAtom.subtitle,
                    metadata: fromAtom.metadata
                )
            }

            // Deduplicate: if multiple blocks reference the same entity, keep only the first
            var seenEntityUUIDs: Set<String> = []
            let deduped = enrichedBlocks.filter { block in
                guard !block.entityUuid.isEmpty else { return true } // notes may lack entityUuid
                if seenEntityUUIDs.contains(block.entityUuid) {
                    print("⚠️ Dedup: removing duplicate block for entity \(block.entityUuid)")
                    return false
                }
                seenEntityUUIDs.insert(block.entityUuid)
                return true
            }

            return deduped
    }

    // MARK: - Save Block to Database
    func saveBlock(_ block: CanvasBlock) async {
        let docType = currentDocumentType
        let docId = currentDocumentId
        let tsId = currentThinkspaceId

        do {
            try await database.asyncWrite { db in
                // Extract content from metadata for note, stickyNote, and content blocks (all use metadata-based storage)
                let noteContent: String? = (block.entityType == .note || block.entityType == .stickyNote || block.entityType == .content)
                    ? block.metadata["content"]
                    : nil

                let atomUUID: String? = block.entityType == .note ? block.entityUuid : nil
                let metadataJSON = Self.encodeBlockMetadataJSON(block.metadata)

                let existingBlock = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT id, is_deleted FROM canvas_blocks
                        WHERE id = ? LIMIT 1
                    """,
                    arguments: [block.id]
                )

                if let existingBlock {
                    // A delayed layout save must never resurrect a deleted row.
                    guard !(existingBlock["is_deleted"] as Bool) else { return }
                    // NOTE: deliberately does NOT rewrite thinkspace_id — during a
                    // thinkspace-switch overlap window the engine context can lag,
                    // and rewriting it here re-homed blocks into the wrong space.
                    // Only the INSERT branch assigns a row's thinkspace.
                    try db.execute(
                        sql: """
                            UPDATE canvas_blocks
                            SET entity_type = ?, entity_id = CASE WHEN entity_id > 0 THEN entity_id ELSE ? END,
                                entity_uuid = COALESCE(NULLIF(entity_uuid, ''), ?), atom_uuid = COALESCE(atom_uuid, ?),
                                position_x = ?, position_y = ?, width = ?, height = ?,
                                z_index = ?, is_pinned = ?, is_placed = ?, updated_at = ?
                            WHERE id = ?
                        """,
                        arguments: [
                            block.entityType.rawValue, block.entityId, block.entityUuid, atomUUID,
                            Int(block.position.x), Int(block.position.y),
                            Int(block.size.width), Int(block.size.height),
                            block.zIndex, block.isPinned, block.isPlaced,
                            ISO8601.string(from: Date()),
                            block.id
                        ]
                    )
                    return
                }

                // For blocks with a real entity, check for existing row to prevent duplicates
                if !block.entityUuid.isEmpty {
                    let existingId = try String.fetchOne(db,
                        sql: """
                            SELECT id FROM canvas_blocks
                            WHERE entity_uuid = ? AND thinkspace_id IS ? AND document_type = ? AND document_id = ? AND is_deleted = 0
                            LIMIT 1
                        """,
                        arguments: [block.entityUuid, tsId, docType, docId]
                    )

                    if let existingId = existingId {
                        // Update existing row instead of inserting a duplicate
                        try db.execute(
                            sql: """
                                UPDATE canvas_blocks
                                SET entity_type = ?, entity_id = CASE WHEN entity_id > 0 THEN entity_id ELSE ? END,
                                entity_uuid = COALESCE(NULLIF(entity_uuid, ''), ?), atom_uuid = COALESCE(atom_uuid, ?),
                                    position_x = ?, position_y = ?, width = ?, height = ?,
                                    z_index = ?, is_pinned = ?, is_placed = ?, updated_at = ?
                                WHERE id = ?
                            """,
                            arguments: [
                                block.entityType.rawValue, block.entityId, block.entityUuid, atomUUID,
                                Int(block.position.x), Int(block.position.y),
                                Int(block.size.width), Int(block.size.height),
                                block.zIndex, block.isPinned, block.isPlaced,
                                ISO8601.string(from: Date()),
                                existingId
                            ]
                        )
                        return
                    }
                }

                // No existing row (or empty entityUuid for notes) — insert new
                try db.execute(
                    sql: """
                    INSERT INTO canvas_blocks
                    (id, document_type, document_id, entity_type, entity_id, entity_uuid, atom_uuid, entity_title,
                     position_x, position_y, width, height, z_index, note_content, metadata, is_pinned, is_placed, thinkspace_id, is_deleted, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                    """,
                    arguments: [
                        block.id,
                        docType,
                        docId,
                        block.entityType.rawValue,
                        block.entityId,
                        block.entityUuid,
                        atomUUID,
                        block.title,
                        Int(block.position.x),
                        Int(block.position.y),
                        Int(block.size.width),
                        Int(block.size.height),
                        block.zIndex,
                        noteContent,
                        metadataJSON,
                        block.isPinned,
                        block.isPlaced,
                        tsId
                    ]
                )
            }
            print("💾 Saved block: \(block.title) to ThinkSpace: \(tsId ?? "none")")
        } catch {
            PersistenceHealth.note(.writeFailure, context: "spatialEngine.saveBlock", detail: "block \(block.id) (\(block.entityType.rawValue)): \(error)")
            print("❌ Failed to save block: \(error)")
        }
    }

    /// Content changes patch the current row. Layout saves above never own
    /// note_content/metadata, so a delayed resize cannot erase a newer edit.
    func updateBlockMetadata(blockID: String, patch: [String: String], alreadyPersisted: Bool = false) throws {
        var committed = patch
        if !alreadyPersisted {
            committed = try database.write { db in
                guard let row = try Row.fetchOne(db,
                    sql: "SELECT metadata FROM canvas_blocks WHERE id = ? AND is_deleted = 0",
                    arguments: [blockID]
                ) else { throw CanvasNotePersistence.SaveError.missingBlock }
                let json: String? = row["metadata"]
                var merged = [String: String]()
                if let json, !json.isEmpty {
                    merged = try JSONDecoder().decode([String: String].self, from: Data(json.utf8))
                }
                merged.merge(patch) { _, new in new }
                if let content = patch["content"], patch[RichDocumentMetadataKeys.bodyDocument] == nil {
                    merged = RichDocumentPersistence.writeBlockDocument(
                        RichDocument.migrateLegacy(content), key: RichDocumentMetadataKeys.bodyDocument, metadata: merged
                    )
                }
                try db.execute(sql: """
                    UPDATE canvas_blocks SET metadata = ?,
                        note_content = CASE WHEN ? THEN ? ELSE note_content END,
                        entity_title = CASE WHEN ? THEN ? ELSE entity_title END,
                        updated_at = ?, _local_version = _local_version + 1, _local_pending = 1
                    WHERE id = ? AND is_deleted = 0
                    """, arguments: [Self.encodeBlockMetadataJSON(merged),
                                      patch["content"] != nil, patch["content"],
                                      patch["title"] != nil, patch["title"],
                                      ISO8601.string(from: Date()), blockID])
                return merged
            }
        }
        if let index = blocks.firstIndex(where: { $0.id == blockID }) {
            blocks[index].metadata.merge(committed) { _, new in new }
            if let title = committed["title"] { blocks[index].title = title }
        }
        ThinkspaceCanvasSnapshotCache.shared.invalidate(blockID: blockID)
    }

    // MARK: - Update Block Position
    func updateBlockPosition(_ blockId: String, position: CGPoint) {
        // Update in memory (instant)
        if let index = blocks.firstIndex(where: { $0.id == blockId }) {
            blocks[index].position = position
        }

        // Track as in-flight so the terminate flush can persist it synchronously.
        pendingGeometryWrites[blockId] = PendingGeometry(position: position, size: nil)

        // Fire-and-forget database update
        let db = database
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try await db.asyncWrite { database in
                    try database.execute(
                        sql: "UPDATE canvas_blocks SET position_x = ?, position_y = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
                        arguments: [Int(position.x), Int(position.y), blockId]
                    )
                }
                await self?.clearPendingGeometryWrite(blockId, ifPosition: position, size: nil)
            } catch {
                PersistenceHealth.note(.writeFailure, context: "spatialEngine.updateBlockPosition", detail: "block \(blockId): \(error)")
                print("❌ Failed to update block position: \(error)")
            }
        }
    }

    func updateBlockGeometry(_ blockId: String, position: CGPoint, size: CGSize) {
        if let index = blocks.firstIndex(where: { $0.id == blockId }) {
            blocks[index].position = position
            blocks[index].size = size
        }

        pendingGeometryWrites[blockId] = PendingGeometry(position: position, size: size)

        let db = database
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try await db.asyncWrite { database in
                    try database.execute(
                        sql: """
                        UPDATE canvas_blocks
                        SET position_x = ?, position_y = ?, width = ?, height = ?, updated_at = CURRENT_TIMESTAMP
                        WHERE id = ?
                        """,
                        arguments: [Int(position.x), Int(position.y), Int(size.width), Int(size.height), blockId]
                    )
                }
                await self?.clearPendingGeometryWrite(blockId, ifPosition: position, size: size)
            } catch {
                PersistenceHealth.note(.writeFailure, context: "spatialEngine.updateBlockGeometry", detail: "block \(blockId): \(error)")
                print("❌ Failed to update block geometry: \(error)")
            }
        }
    }

    /// Clear an in-flight geometry write once it has landed — but only if no
    /// newer write for the same block superseded it in the meantime.
    private func clearPendingGeometryWrite(_ blockId: String, ifPosition position: CGPoint, size: CGSize?) {
        guard let pending = pendingGeometryWrites[blockId],
              pending.position == position,
              pending.size == size else { return }
        pendingGeometryWrites.removeValue(forKey: blockId)
    }

    // MARK: - Move Block to Another Thinkspace

    /// Persist a cross-thinkspace move directly, without needing an engine whose
    /// in-memory context matches the source space (MainView's drop handler has none).
    static func persistCrossThinkspaceMove(blockId: String, targetThinkspaceId: String, position: CGPoint) async throws {
        try await CosmoDatabase.shared.asyncWrite { db in
            try db.execute(
                sql: """
                UPDATE canvas_blocks
                SET thinkspace_id = ?, position_x = ?, position_y = ?, is_placed = 0, updated_at = ?
                WHERE id = ?
                """,
                arguments: [targetThinkspaceId, Int(position.x), Int(position.y), ISO8601.string(from: Date()), blockId]
            )
        }
    }

    /// Finds an entity's live thinkspace-canvas block row (document "home")
    /// regardless of which thinkspace holds it. Used by the ⌘K filing verb to
    /// decide between moving an existing block and creating a fresh one.
    static func findThinkspaceBlockRow(entityUuid: String) async throws -> (blockId: String, thinkspaceId: String?)? {
        try await CosmoDatabase.shared.asyncRead { db in
            let row = try Row.fetchOne(db,
                sql: """
                    SELECT id, thinkspace_id FROM canvas_blocks
                    WHERE entity_uuid = ? AND document_type = 'home' AND document_id = 0 AND is_deleted = 0
                    LIMIT 1
                """,
                arguments: [entityUuid]
            )
            guard let row else { return nil }
            return (blockId: row["id"], thinkspaceId: row["thinkspace_id"])
        }
    }

    /// Files an atom into a thinkspace the user is NOT visiting by inserting
    /// its canvas_blocks row directly — no live engine exists for the target
    /// space. Thinkspace canvases live under document ("home", 0). Dedupes on
    /// (entity_uuid, thinkspace_id) like `saveBlock`'s insert path; an existing
    /// row is left untouched (filing is idempotent, not a move).
    static func persistBlockToUnmountedThinkspace(_ block: CanvasBlock, thinkspaceId: String, isPlaced: Bool = false) async throws {
        try await CosmoDatabase.shared.asyncWrite { db in
            if !block.entityUuid.isEmpty {
                let existing = try String.fetchOne(db,
                    sql: """
                        SELECT id FROM canvas_blocks
                        WHERE entity_uuid = ? AND thinkspace_id IS ? AND document_type = 'home' AND document_id = 0 AND is_deleted = 0
                        LIMIT 1
                    """,
                    arguments: [block.entityUuid, thinkspaceId]
                )
                if existing != nil { return }
            }

            let noteContent: String? = (block.entityType == .note || block.entityType == .stickyNote || block.entityType == .content)
                ? block.metadata["content"]
                : nil
            let atomUUID: String? = block.entityType == .note ? block.entityUuid : nil
            let metadataJSON = Self.encodeBlockMetadataJSON(block.metadata)

            try db.execute(
                sql: """
                INSERT OR REPLACE INTO canvas_blocks
                (id, document_type, document_id, entity_type, entity_id, entity_uuid, atom_uuid, entity_title,
                 position_x, position_y, width, height, z_index, note_content, metadata, is_pinned, is_placed, thinkspace_id, is_deleted, created_at, updated_at)
                VALUES (?, 'home', 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """,
                arguments: [
                    block.id,
                    block.entityType.rawValue,
                    block.entityId,
                    block.entityUuid,
                    atomUUID,
                    block.title,
                    Int(block.position.x),
                    Int(block.position.y),
                    Int(block.size.width),
                    Int(block.size.height),
                    block.zIndex,
                    noteContent,
                    metadataJSON,
                    block.isPinned,
                    isPlaced,
                    thinkspaceId
                ]
            )
        }
    }

    func moveBlockToThinkspace(_ blockId: String, newThinkspaceId: String, position: CGPoint) async {
        // Remove from in-memory array (it belongs to the new thinkspace now)
        withAnimation(.easeOut(duration: 0.15)) {
            blocks.removeAll { $0.id == blockId }
        }

        // Update thinkspace_id and position in database
        do {
            try await database.asyncWrite { database in
                try database.execute(
                    sql: """
                    UPDATE canvas_blocks
                    SET thinkspace_id = ?, position_x = ?, position_y = ?, updated_at = CURRENT_TIMESTAMP
                    WHERE id = ?
                    """,
                    arguments: [newThinkspaceId, Int(position.x), Int(position.y), blockId]
                )
            }
            print("📦 Moved block \(blockId) to thinkspace \(newThinkspaceId)")
        } catch {
            PersistenceHealth.note(.writeFailure, context: "spatialEngine.moveBlockToThinkspace", detail: "block \(blockId) → \(newThinkspaceId): \(error)")
            print("❌ Failed to move block to thinkspace: \(error)")
        }
    }

    // MARK: - Remove Block
    func removeBlock(_ blockId: String) async {
        // Remove from memory FIRST (instant UI update)
        withAnimation(.easeOut(duration: 0.15)) {
            blocks.removeAll { $0.id == blockId }
        }

        // Fire-and-forget database update (non-blocking)
        let db = database
        Task.detached(priority: .background) {
            do {
                try await db.asyncWrite { database in
                    try database.execute(
                        sql: "UPDATE canvas_blocks SET is_deleted = 1, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
                        arguments: [blockId]
                    )
                }
                print("🗑️ Removed block: \(blockId)")
            } catch {
                PersistenceHealth.note(.writeFailure, context: "spatialEngine.removeBlock", detail: "block \(blockId): \(error)")
                print("❌ Failed to remove block: \(error)")
            }
        }
    }

    // MARK: - Restore Block (undo delete)
    func restoreBlock(_ block: CanvasBlock) async {
        blocks.append(block)

        // Un-soft-delete in database
        let db = database
        Task.detached(priority: .background) {
            do {
                try await db.asyncWrite { database in
                    try database.execute(
                        sql: "UPDATE canvas_blocks SET is_deleted = 0, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
                        arguments: [block.id]
                    )
                }
            } catch {
                PersistenceHealth.note(.writeFailure, context: "spatialEngine.restoreBlock", detail: "block \(block.id): \(error)")
                print("❌ Failed to restore block: \(error)")
            }
        }
    }

    // MARK: - Detach Atom From A Thinkspace (remove from thinkspace)

    /// Soft-delete EVERY placement of an atom WITHIN one thinkspace, leaving the
    /// atom alive in the Library and untouched in any OTHER thinkspaces. This is
    /// the "remove from thinkspace" tier — one step heavier than `removeBlock`
    /// (which drops a single placement) and one step lighter than deleting the
    /// atom. Scoped to `thinkspaceId` so it never reaches into spaces the user
    /// isn't looking at.
    ///
    /// ISO8601 (not CURRENT_TIMESTAMP) because the block observer pushes this
    /// `updated_at` to the cloud and SQLite's space-separated format breaks the
    /// LWW cursor comparison (same reason AtomRepository.delete uses ISO8601).
    func removeAtomFromThinkspace(entityUuid: String, thinkspaceId: String) async {
        guard !entityUuid.isEmpty, !thinkspaceId.isEmpty else { return }

        // Remove from memory FIRST (instant UI update). `blocks` only holds the
        // current thinkspace, so matching on entityUuid is already space-scoped.
        withAnimation(.easeOut(duration: 0.15)) {
            blocks.removeAll { $0.entityUuid == entityUuid }
        }

        let db = database
        let now = ISO8601.string(from: Date())
        do {
            try await db.asyncWrite { database in
                try database.execute(
                    sql: "UPDATE canvas_blocks SET is_deleted = 1, updated_at = ? WHERE entity_uuid = ? AND thinkspace_id = ?",
                    arguments: [now, entityUuid, thinkspaceId]
                )
            }
        } catch {
            PersistenceHealth.note(.writeFailure, context: "spatialEngine.removeAtomFromThinkspace", detail: "atom \(entityUuid.prefix(8)) in \(thinkspaceId.prefix(8)): \(error)")
        }

        NotificationCenter.default.post(
            name: Notification.Name("com.cosmo.canvasBlocksChanged"),
            object: nil
        )
    }

    /// Undo of `removeAtomFromThinkspace`: un-soft-delete the atom's placements
    /// in that one thinkspace and reload the current canvas if it's the one that
    /// changed, so the restored blocks reappear in memory.
    func reattachAtomToThinkspace(entityUuid: String, thinkspaceId: String) async {
        guard !entityUuid.isEmpty, !thinkspaceId.isEmpty else { return }

        let db = database
        let now = ISO8601.string(from: Date())
        do {
            try await db.asyncWrite { database in
                try database.execute(
                    sql: "UPDATE canvas_blocks SET is_deleted = 0, updated_at = ? WHERE entity_uuid = ? AND thinkspace_id = ?",
                    arguments: [now, entityUuid, thinkspaceId]
                )
            }
        } catch {
            PersistenceHealth.note(.writeFailure, context: "spatialEngine.reattachAtomToThinkspace", detail: "atom \(entityUuid.prefix(8)) in \(thinkspaceId.prefix(8)): \(error)")
        }

        if currentThinkspaceId == thinkspaceId {
            await loadBlocks(for: "home", documentId: 0, thinkspaceId: thinkspaceId)
        }

        NotificationCenter.default.post(
            name: Notification.Name("com.cosmo.canvasBlocksChanged"),
            object: nil
        )
    }

    // MARK: - Add Block (with persistence)
    func addBlock(_ block: CanvasBlock, persist: Bool = true) async {
        // Prevent duplicate blocks for the same entity (in-memory check)
        if !block.entityUuid.isEmpty,
           blocks.contains(where: { $0.entityUuid == block.entityUuid }) {
            print("⚠️ addBlock: skipping duplicate for entity \(block.entityUuid)")
            return
        }

        // Database-level check (catches duplicates after app restart when memory is empty)
        if !block.entityUuid.isEmpty {
            switch await entityPlacement(block.entityUuid) {
            case .placed:
                print("⚠️ addBlock: entity \(block.entityUuid) already in DB, skipping")
                return
            case .unplaced:
                // The atom is a member waiting in the tray — a gesture that
                // adds it again PLACES it (the tray must never be a trap).
                _ = await placeMember(entityUuid: block.entityUuid, at: block.position)
                return
            case .unknown:
                // Unknown (DB error) — creating anyway could produce a duplicate row.
                PersistenceHealth.note(.writeFailure, context: "spatialEngine.addBlock", detail: "duplicate check failed for \(block.entityUuid); skipping create")
                print("⚠️ addBlock: duplicate check failed for \(block.entityUuid), skipping create")
                return
            case .absent:
                break
            }
        }

        blocks.append(block)

        if persist {
            await saveBlock(block)
            // Register undo (CosmoUndoManager ignores during undo/redo)
            CosmoUndoManager.shared.register(CreateBlockAction(block: block, spatialEngine: self))
        }
    }

    /// How an entity already sits in the current thinkspace/document.
    enum EntityPlacement: Equatable {
        case absent
        case placed
        case unplaced(blockId: String)
        /// The check itself failed — callers must NOT treat this as absent or
        /// they can create duplicate rows.
        case unknown
    }

    private func entityPlacement(_ entityUuid: String) async -> EntityPlacement {
        let docType = currentDocumentType
        let docId = currentDocumentId
        let tsId = currentThinkspaceId
        do {
            return try await database.asyncRead { db in
                let row = try Row.fetchOne(db,
                    sql: """
                        SELECT id, is_placed FROM canvas_blocks
                        WHERE entity_uuid = ? AND thinkspace_id IS ? AND document_type = ? AND document_id = ? AND is_deleted = 0
                        ORDER BY is_placed DESC
                        LIMIT 1
                    """,
                    arguments: [entityUuid, tsId, docType, docId]
                )
                guard let row else { return .absent }
                let placed = (row["is_placed"] as Bool?) ?? true
                let id: String = row["id"]
                return placed ? .placed : .unplaced(blockId: id)
            }
        } catch {
            print("❌ entityPlacement failed for \(entityUuid): \(error)")
            return .unknown
        }
    }

    // MARK: - Membership without position (the tray)

    /// Every membership row of a space — placed or not — for the library,
    /// the board and the tray. Static: no engine needs to be mounted.
    static func fetchMembers(thinkspaceId: String, placedOnly: Bool? = nil) async throws -> [CanvasBlockRecord] {
        try await CosmoDatabase.shared.asyncRead { db in
            var query = CanvasBlockRecord
                .filter(Column("document_type") == "home")
                .filter(Column("document_id") == 0)
                .filter(Column("thinkspace_id") == thinkspaceId)
                .filter(Column("is_deleted") == false)
                .filter(Column("entity_type") != "portal")
            if let placedOnly {
                query = query.filter(Column("is_placed") == placedOnly)
            }
            var records = try query.order(Column("updated_at").desc).fetchAll(db)
            // Tombstone shield (same law as the world fetch).
            let atomUuids = records.compactMap(\.entityUuid).filter { !$0.isEmpty }
            if !atomUuids.isEmpty {
                let tombstoned = try String.fetchSet(
                    db,
                    Atom.filter(atomUuids.contains(Column("uuid")))
                        .filter(Column("is_deleted") == true)
                        .select(Column("uuid"), as: String.self)
                )
                if !tombstoned.isEmpty {
                    records.removeAll { record in
                        guard let uuid = record.entityUuid, !uuid.isEmpty else { return false }
                        return tombstoned.contains(uuid)
                    }
                }
            }
            // First wins per entity (a placed row outranks an unplaced twin).
            var seen = Set<String>()
            return records.filter { record in
                guard let uuid = record.entityUuid, !uuid.isEmpty else { return true }
                return seen.insert(uuid).inserted
            }
        }
    }

    static func fetchUnplacedMembers(thinkspaceId: String) async throws -> [CanvasBlockRecord] {
        try await fetchMembers(thinkspaceId: thinkspaceId, placedOnly: false)
    }

    /// "Remove from canvas": the row stays (the atom is still a member of the
    /// space) but leaves the world; it waits in the tray. Returns the block
    /// for the undo action. ISO8601 stamp — the observer pushes it to the cloud.
    @discardableResult
    func unplaceBlock(_ blockId: String) async -> CanvasBlock? {
        let removed = blocks.first { $0.id == blockId }
        withAnimation(.easeOut(duration: 0.15)) {
            blocks.removeAll { $0.id == blockId }
        }
        let now = ISO8601.string(from: Date())
        do {
            try await database.asyncWrite { db in
                try db.execute(
                    sql: "UPDATE canvas_blocks SET is_placed = 0, updated_at = ? WHERE id = ?",
                    arguments: [now, blockId]
                )
            }
        } catch {
            PersistenceHealth.note(.writeFailure, context: "spatialEngine.unplaceBlock", detail: "block \(blockId): \(error)")
        }
        NotificationCenter.default.post(name: Notification.Name("com.cosmo.canvasBlocksChanged"), object: nil)
        return removed
    }

    /// Undo of `unplaceBlock`: the exact placement comes back.
    func restorePlacement(_ block: CanvasBlock) async {
        var placed = block
        placed.isPlaced = true
        if !blocks.contains(where: { $0.id == block.id }) {
            blocks.append(placed)
        }
        let now = ISO8601.string(from: Date())
        do {
            try await database.asyncWrite { db in
                try db.execute(
                    sql: "UPDATE canvas_blocks SET is_placed = 1, position_x = ?, position_y = ?, updated_at = ? WHERE id = ?",
                    arguments: [Int(block.position.x), Int(block.position.y), now, block.id]
                )
            }
        } catch {
            PersistenceHealth.note(.writeFailure, context: "spatialEngine.restorePlacement", detail: "block \(block.id): \(error)")
        }
        NotificationCenter.default.post(name: Notification.Name("com.cosmo.canvasBlocksChanged"), object: nil)
    }

    /// Place a tray member at a canvas point: the membership row gains a
    /// position and joins the world. Returns the live block.
    @discardableResult
    func placeMember(entityUuid: String, at position: CGPoint) async -> CanvasBlock? {
        guard !entityUuid.isEmpty, let tsId = currentThinkspaceId else { return nil }
        if let existing = blocks.first(where: { $0.entityUuid == entityUuid }) {
            return existing
        }
        do {
            let record: CanvasBlockRecord? = try await database.asyncRead { db in
                try CanvasBlockRecord
                    .filter(Column("entity_uuid") == entityUuid)
                    .filter(Column("thinkspace_id") == tsId)
                    .filter(Column("document_type") == "home")
                    .filter(Column("document_id") == 0)
                    .filter(Column("is_deleted") == false)
                    .fetchOne(db)
            }
            guard let record else { return nil }
            let atoms = (try? await AtomRepository.shared.fetchBatch(uuids: [entityUuid])) ?? []
            let metadataJSON: [String: String] = try await database.asyncRead { db in
                let json = try String.fetchOne(db, sql: "SELECT metadata FROM canvas_blocks WHERE id = ?", arguments: [record.id])
                return json.map { [record.id: $0] } ?? [:]
            }
            guard var block = Self.buildBlocks(
                records: [record],
                metadataJSONByBlockId: metadataJSON,
                fetchedAtomsByID: atoms,
                fetchedAtomsByUUID: atoms
            ).first else { return nil }
            block.position = position
            block.isPlaced = true
            block.zIndex = (blocks.map(\.zIndex).max() ?? 0) + 1
            let now = ISO8601.string(from: Date())
            try await database.asyncWrite { db in
                try db.execute(
                    sql: "UPDATE canvas_blocks SET is_placed = 1, position_x = ?, position_y = ?, z_index = ?, updated_at = ? WHERE id = ?",
                    arguments: [Int(position.x), Int(position.y), block.zIndex, now, record.id]
                )
            }
            withAnimation(.easeOut(duration: 0.18)) {
                blocks.append(block)
            }
            NotificationCenter.default.post(name: Notification.Name("com.cosmo.canvasBlocksChanged"), object: nil)
            return block
        } catch {
            PersistenceHealth.note(.writeFailure, context: "spatialEngine.placeMember", detail: "atom \(entityUuid.prefix(8)): \(error)")
            return nil
        }
    }

    /// Lay every unplaced member out on a grid around the anchor — one undo.
    @discardableResult
    func placeAllUnplaced(anchor: CGPoint) async -> [String] {
        guard let tsId = currentThinkspaceId,
              let members = try? await Self.fetchUnplacedMembers(thinkspaceId: tsId),
              !members.isEmpty else { return [] }
        let columns = max(1, Int(Double(members.count).squareRoot().rounded(.up)))
        let cell = CGSize(width: 320, height: 300)
        var placed: [(entityUuid: String, position: CGPoint, blockId: String)] = []
        for (index, member) in members.enumerated() {
            guard let uuid = member.entityUuid, !uuid.isEmpty else { continue }
            let column = index % columns
            let row = index / columns
            let position = CGPoint(
                x: anchor.x + (CGFloat(column) - CGFloat(columns - 1) / 2) * cell.width,
                y: anchor.y + CGFloat(row) * cell.height
            )
            if let block = await placeMember(entityUuid: uuid, at: position) {
                placed.append((uuid, position, block.id))
            }
        }
        let snapshot = placed
        CosmoUndoManager.shared.register(InlineUndoAction(
            actionDescription: "Place all",
            undo: { [weak self] in
                for entry in snapshot { _ = await self?.unplaceBlock(entry.blockId) }
            },
            redo: { [weak self] in
                for entry in snapshot { _ = await self?.placeMember(entityUuid: entry.entityUuid, at: entry.position) }
            }
        ))
        return placed.map(\.entityUuid)
    }

    // MARK: - Voice-Driven Placement
    func placeBlocks(
        query: String,
        entityType: EntityType,
        quantity: Int,
        layout: LayoutStyle = .orbital,
        canvasSize: CGSize,
        centerOverride: CGPoint? = nil
    ) async throws {
        print("🎨 Placing \(quantity) \(entityType.rawValue)s with layout: \(layout)")

        // Search for entities
        let entities = try await searchEntities(
            query: query,
            type: entityType,
            limit: quantity
        )

        // Create blocks from entities
        var newBlocks: [CanvasBlock] = []

        for entity in entities {
            guard let block = createBlock(from: entity, type: entityType) else { continue }
            newBlocks.append(block)
        }

        // Compute spatial layout
        let positions = computeLayout(
            count: newBlocks.count,
            style: layout,
            canvasSize: canvasSize,
            centerOverride: centerOverride
        )

        // Apply positions
        for (index, position) in positions.enumerated() {
            if index < newBlocks.count {
                newBlocks[index].position = position
                newBlocks[index].animateTo(position: position)
            }
        }

        // Add to canvas with animation — route through addBlock so voice
        // placements are persisted (and deduplicated) like every other add.
        for block in newBlocks {
            await addBlock(block, persist: true)
        }

        print("✅ Placed \(newBlocks.count) blocks on canvas")
    }

    // MARK: - Entity Search (FTS5 Enabled)
    private func searchEntities(
        query: String,
        type: EntityType,
        limit: Int
    ) async throws -> [Any] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        switch type {
        case .idea:
            return try await database.asyncRead { db in
                if !cleanQuery.isEmpty {
                    // FTS5 search for relevant ideas
                    let ftsQuery = cleanQuery.split(separator: " ").map { "\($0)*" }.joined(separator: " ")
                    return try Idea.fetchAll(db, sql: """
                        SELECT ideas.* FROM ideas
                        LEFT JOIN ideas_fts ON ideas.id = ideas_fts.rowid
                        WHERE ideas.is_deleted = 0
                        AND (
                            ideas_fts MATCH ?
                            OR ideas.title LIKE ?
                            OR ideas.content LIKE ?
                        )
                        ORDER BY
                            CASE WHEN ideas_fts MATCH ? THEN 0 ELSE 1 END,
                            ideas.updated_at DESC
                        LIMIT ?
                    """, arguments: [ftsQuery, "%\(cleanQuery)%", "%\(cleanQuery)%", ftsQuery, limit])
                } else {
                    return try Atom
                        .filter(Column("type") == AtomType.idea.rawValue)
                        .filter(Column("is_deleted") == false)
                        .order(Column("updated_at").desc)
                        .limit(limit)
                        .fetchAll(db)
                        .map { IdeaWrapper(atom: $0) }
                }
            }

        case .content:
            return try await database.asyncRead { db in
                if !cleanQuery.isEmpty {
                    // Use simple LIKE search on atoms table
                    return try Atom
                        .filter(Column("type") == AtomType.content.rawValue)
                        .filter(Column("is_deleted") == false)
                        .filter(Column("title").like("%\(cleanQuery)%") || Column("body").like("%\(cleanQuery)%"))
                        .order(Column("updated_at").desc)
                        .limit(limit)
                        .fetchAll(db)
                        .map { ContentWrapper(atom: $0) }
                } else {
                    return try Atom
                        .filter(Column("type") == AtomType.content.rawValue)
                        .filter(Column("is_deleted") == false)
                        .order(Column("updated_at").desc)
                        .limit(limit)
                        .fetchAll(db)
                        .map { ContentWrapper(atom: $0) }
                }
            }

        case .task:
            return try await database.asyncRead { db in
                if !cleanQuery.isEmpty {
                    return try Atom
                        .filter(Column("type") == AtomType.task.rawValue)
                        .filter(Column("is_deleted") == false)
                        .filter(Column("title").like("%\(cleanQuery)%") || Column("body").like("%\(cleanQuery)%"))
                        .order(Column("updated_at").desc)
                        .limit(limit)
                        .fetchAll(db)
                        .map { TaskWrapper(atom: $0) }
                } else {
                    return try Atom
                        .filter(Column("type") == AtomType.task.rawValue)
                        .filter(Column("is_deleted") == false)
                        .order(Column("updated_at").desc)
                        .limit(limit)
                        .fetchAll(db)
                        .map { TaskWrapper(atom: $0) }
                }
            }

        case .connection:
            return try await database.asyncRead { db in
                if !cleanQuery.isEmpty {
                    return try Atom
                        .filter(Column("type") == AtomType.connection.rawValue)
                        .filter(Column("is_deleted") == false)
                        .filter(Column("title").like("%\(cleanQuery)%"))
                        .order(Column("updated_at").desc)
                        .limit(limit)
                        .fetchAll(db)
                        .map { ConnectionWrapper(atom: $0) }
                } else {
                    return try Atom
                        .filter(Column("type") == AtomType.connection.rawValue)
                        .filter(Column("is_deleted") == false)
                        .order(Column("updated_at").desc)
                        .limit(limit)
                        .fetchAll(db)
                        .map { ConnectionWrapper(atom: $0) }
                }
            }

        case .research:
            return try await database.asyncRead { db in
                if !cleanQuery.isEmpty {
                    return try Atom
                        .filter(Column("type") == AtomType.research.rawValue)
                        .filter(Column("is_deleted") == false)
                        .filter(Column("title").like("%\(cleanQuery)%") || Column("body").like("%\(cleanQuery)%"))
                        .order(Column("updated_at").desc)
                        .limit(limit)
                        .fetchAll(db)
                        .map { ResearchWrapper(atom: $0) }
                } else {
                    return try Atom
                        .filter(Column("type") == AtomType.research.rawValue)
                        .filter(Column("is_deleted") == false)
                        .order(Column("updated_at").desc)
                        .limit(limit)
                        .fetchAll(db)
                        .map { ResearchWrapper(atom: $0) }
                }
            }

        case .project:
            return try await database.asyncRead { db in
                if !cleanQuery.isEmpty {
                    return try Atom
                        .filter(Column("type") == AtomType.project.rawValue)
                        .filter(Column("is_deleted") == false)
                        .filter(Column("title").like("%\(cleanQuery)%") || Column("body").like("%\(cleanQuery)%"))
                        .order(Column("updated_at").desc)
                        .limit(limit)
                        .fetchAll(db)
                        .map { ProjectWrapper(atom: $0) }
                } else {
                    return try Atom
                        .filter(Column("type") == AtomType.project.rawValue)
                        .filter(Column("is_deleted") == false)
                        .order(Column("updated_at").desc)
                        .limit(limit)
                        .fetchAll(db)
                        .map { ProjectWrapper(atom: $0) }
                }
            }

        default:
            return []
        }
    }

    // MARK: - Block Creation
    private func createBlock(from entity: Any, type: EntityType) -> CanvasBlock? {
        let center = CGPoint(x: 960, y: 540)  // Start at center

        switch type {
        case .idea:
            guard let idea = entity as? Idea else { return nil }
            return CanvasBlock.fromIdea(idea, position: center)
        case .content:
            guard let content = entity as? CosmoContent else { return nil }
            return CanvasBlock.fromContent(content, position: center)
        case .task:
            guard let task = entity as? CosmoTask else { return nil }
            return CanvasBlock.fromTask(task, position: center)
        case .connection:
            guard let connection = entity as? Connection else { return nil }
            return CanvasBlock.fromConnection(connection, position: center)
        case .research:
            guard let research = entity as? Research else { return nil }
            return CanvasBlock.fromResearch(research, position: center)
        case .project:
            guard let project = entity as? Project else { return nil }
            return CanvasBlock.fromProject(project, position: center)
        default:
            print("SpatialEngine: Unsupported entity type: \(type)")
            return nil
        }
    }

    // MARK: - Layout Computation
    private func computeLayout(
        count: Int,
        style: LayoutStyle,
        canvasSize: CGSize,
        centerOverride: CGPoint? = nil
    ) -> [CGPoint] {
        let center = centerOverride ?? CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

        switch style {
        case .orbital:
            return computeOrbitalLayout(count: count, center: center)

        case .grid:
            return computeGridLayout(count: count, center: center)

        case .linear:
            return computeLinearLayout(count: count, center: center)

        case .clustered:
            return computeClusteredLayout(count: count, center: center)

        case .llmDriven:
            // Use local LLM for semantic placement
            return computeLLMLayout(count: count, center: center)

        // NEW: Magical arrangements
        case .snake:
            return computeSnakeLayout(count: count, center: center)

        case .spiral:
            return computeSpiralLayout(count: count, center: center)

        case .wave:
            return computeWaveLayout(count: count, center: center)

        case .diamond:
            return computeDiamondLayout(count: count, center: center)

        case .tree:
            return computeTreeLayout(count: count, center: center)

        case .flow:
            return computeFlowLayout(count: count, center: center)
        }
    }

    private func computeOrbitalLayout(count: Int, center: CGPoint) -> [CGPoint] {
        let radius: CGFloat = 300
        var positions: [CGPoint] = []

        for i in 0..<count {
            let angle = (CGFloat(i) / CGFloat(count)) * 2 * .pi
            let x = center.x + cos(angle) * radius
            let y = center.y + sin(angle) * radius
            positions.append(CGPoint(x: x, y: y))
        }

        return positions
    }

    private func computeGridLayout(count: Int, center: CGPoint) -> [CGPoint] {
        let columns = Int(ceil(sqrt(Double(count))))
        let spacing: CGFloat = 320
        var positions: [CGPoint] = []

        let startX = center.x - (CGFloat(columns) * spacing / 2)
        let startY = center.y - (CGFloat(count / columns) * spacing / 2)

        for i in 0..<count {
            let col = i % columns
            let row = i / columns

            let x = startX + CGFloat(col) * spacing
            let y = startY + CGFloat(row) * spacing

            positions.append(CGPoint(x: x, y: y))
        }

        return positions
    }

    private func computeLinearLayout(count: Int, center: CGPoint) -> [CGPoint] {
        let spacing: CGFloat = 320
        var positions: [CGPoint] = []

        let startX = center.x - (CGFloat(count - 1) * spacing / 2)

        for i in 0..<count {
            let x = startX + CGFloat(i) * spacing
            positions.append(CGPoint(x: x, y: center.y))
        }

        return positions
    }

    private func computeClusteredLayout(count: Int, center: CGPoint) -> [CGPoint] {
        // Random cluster with slight randomness
        var positions: [CGPoint] = []
        let maxOffset: CGFloat = 200

        for _ in 0..<count {
            let x = center.x + CGFloat.random(in: -maxOffset...maxOffset)
            let y = center.y + CGFloat.random(in: -maxOffset...maxOffset)
            positions.append(CGPoint(x: x, y: y))
        }

        return positions
    }

    private func computeLLMLayout(count: Int, center: CGPoint) -> [CGPoint] {
        // TODO: Use LocalLLM.computeSpatialPlacement for semantic layouts
        // For now, fallback to orbital
        return computeOrbitalLayout(count: count, center: center)
    }

    // MARK: - Block Movement
    func moveBlocks(
        direction: Direction,
        distance: CGFloat = 100
    ) {
        let selectedBlocks = blocks.filter { $0.isSelected || !blocks.contains(where: { $0.isSelected }) }

        for index in blocks.indices {
            guard selectedBlocks.contains(where: { $0.id == blocks[index].id }) else { continue }

            var newPosition = blocks[index].position

            switch direction {
            case .left:
                newPosition.x -= distance
            case .right:
                newPosition.x += distance
            case .up:
                newPosition.y -= distance
            case .down:
                newPosition.y += distance
            }

            blocks[index].animateTo(position: newPosition)
        }

        print("✅ Moved \(selectedBlocks.count) blocks \(direction)")
    }

    // MARK: - Block Selection
    func selectBlock(at point: CGPoint) -> CanvasBlock? {
        // Find topmost block at point
        let hitBlocks = blocks.filter { block in
            let frame = CGRect(
                origin: block.position,
                size: CGSize(
                    width: block.size.width * block.scale,
                    height: block.size.height * block.scale
                )
            )
            return frame.contains(point)
        }

        return hitBlocks.max(by: { $0.zIndex < $1.zIndex })
    }

    // MARK: - Clear Canvas
    func clearCanvas() {
        blocks.removeAll()
        print("🗑️  Canvas cleared")
    }

    // MARK: - Magical Spatial Arrangements (INSTANT!)

    /// Rearrange all blocks (or selected blocks) into a new pattern
    func arrangeBlocks(style: LayoutStyle, canvasSize: CGSize? = nil) {
        let targetBlocks = blocks.filter { $0.isSelected }
        let blocksToArrange = targetBlocks.isEmpty ? blocks : targetBlocks

        guard !blocksToArrange.isEmpty else { return }

        let size = canvasSize ?? CGSize(width: 1920, height: 1080)

        let positions = computeLayout(count: blocksToArrange.count, style: style, canvasSize: size)

        // Animate blocks to new positions with staggered timing
        for (index, block) in blocksToArrange.enumerated() {
            if let blockIndex = blocks.firstIndex(where: { $0.id == block.id }),
               index < positions.count {
                // Staggered animation for magical effect
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.05) {
                    self.blocks[blockIndex].animateTo(position: positions[index])
                }
            }
        }

        print("✨ Arranged \(blocksToArrange.count) blocks in \(style.rawValue) pattern")
    }

    // MARK: - Snake Layout (Sinusoidal serpent)
    private func computeSnakeLayout(count: Int, center: CGPoint) -> [CGPoint] {
        var positions: [CGPoint] = []
        let amplitude: CGFloat = 120
        let frequency: CGFloat = 0.4
        let spacing: CGFloat = 180

        let startX = center.x - (CGFloat(count - 1) * spacing / 2)

        for i in 0..<count {
            let x = startX + CGFloat(i) * spacing
            let y = center.y + sin(CGFloat(i) * frequency * .pi) * amplitude
            positions.append(CGPoint(x: x, y: y))
        }

        return positions
    }

    // MARK: - Spiral Layout (Outward golden spiral)
    private func computeSpiralLayout(count: Int, center: CGPoint) -> [CGPoint] {
        var positions: [CGPoint] = []
        let angleIncrement: CGFloat = 2.4  // Golden angle in radians
        let radiusGrowth: CGFloat = 40

        for i in 0..<count {
            let angle = CGFloat(i) * angleIncrement
            let radius = radiusGrowth * sqrt(CGFloat(i + 1))

            let x = center.x + cos(angle) * radius
            let y = center.y + sin(angle) * radius
            positions.append(CGPoint(x: x, y: y))
        }

        return positions
    }

    // MARK: - Wave Layout (Horizontal flowing wave)
    private func computeWaveLayout(count: Int, center: CGPoint) -> [CGPoint] {
        var positions: [CGPoint] = []
        let amplitude: CGFloat = 80
        let wavelength: CGFloat = 250
        let verticalSpacing: CGFloat = 140

        let rows = Int(ceil(Double(count) / 4.0))
        let itemsPerRow = Int(ceil(Double(count) / Double(rows)))
        let startX = center.x - CGFloat(itemsPerRow - 1) * wavelength / 2
        let startY = center.y - CGFloat(rows - 1) * verticalSpacing / 2

        var index = 0
        for row in 0..<rows {
            for col in 0..<itemsPerRow {
                guard index < count else { break }

                let x = startX + CGFloat(col) * wavelength
                let waveOffset = sin(CGFloat(col) * 0.8 + CGFloat(row) * 0.5) * amplitude
                let y = startY + CGFloat(row) * verticalSpacing + waveOffset

                positions.append(CGPoint(x: x, y: y))
                index += 1
            }
        }

        return positions
    }

    // MARK: - Diamond Layout (Rhombus arrangement)
    private func computeDiamondLayout(count: Int, center: CGPoint) -> [CGPoint] {
        var positions: [CGPoint] = []
        let spacing: CGFloat = 180

        // Diamond pattern: 1, 2, 3, 2, 1 (or similar based on count)
        var currentY = center.y
        var remaining = count
        var row = 0
        var widths: [Int] = []

        // Calculate row widths for diamond shape
        while remaining > 0 {
            let width = min(remaining, row + 1)
            widths.append(width)
            remaining -= width
            row += 1
        }

        // Mirror for bottom half (not used in current implementation)

        // Place blocks
        var blockIndex = 0
        currentY = center.y - CGFloat(widths.count - 1) * spacing / 2

        for (_, width) in widths.enumerated() {
            let startX = center.x - CGFloat(width - 1) * spacing / 2

            for col in 0..<width {
                guard blockIndex < count else { break }
                let x = startX + CGFloat(col) * spacing
                positions.append(CGPoint(x: x, y: currentY))
                blockIndex += 1
            }

            currentY += spacing
        }

        return positions
    }

    // MARK: - Tree Layout (Hierarchical)
    private func computeTreeLayout(count: Int, center: CGPoint) -> [CGPoint] {
        var positions: [CGPoint] = []
        let horizontalSpacing: CGFloat = 200
        let verticalSpacing: CGFloat = 150

        // Root at top, branching down
        let levels = Int(ceil(log2(Double(count + 1))))
        var nodeIndex = 0

        for level in 0..<levels {
            let nodesAtLevel = min(Int(pow(2.0, Double(level))), count - nodeIndex)
            let levelWidth = CGFloat(nodesAtLevel - 1) * horizontalSpacing
            let startX = center.x - levelWidth / 2
            let y = center.y - CGFloat(levels - 1) * verticalSpacing / 2 + CGFloat(level) * verticalSpacing

            for i in 0..<nodesAtLevel {
                guard nodeIndex < count else { break }
                let x = startX + CGFloat(i) * horizontalSpacing
                positions.append(CGPoint(x: x, y: y))
                nodeIndex += 1
            }
        }

        return positions
    }

    // MARK: - Flow Layout (River-like flowing path)
    private func computeFlowLayout(count: Int, center: CGPoint) -> [CGPoint] {
        var positions: [CGPoint] = []
        let baseSpacing: CGFloat = 200

        // Bezier-like flowing path
        var x = center.x - CGFloat(count) * baseSpacing / 3
        var y = center.y - 200
        var direction: CGFloat = 1

        for i in 0..<count {
            positions.append(CGPoint(x: x, y: y))

            // Flow forward with gentle curves
            x += baseSpacing * 0.7
            y += sin(CGFloat(i) * 0.6) * 60 + (direction * 30)

            // Occasionally change direction
            if i % 3 == 0 {
                direction *= -0.8
            }
        }

        return positions
    }
}

// MARK: - Layout Styles
enum LayoutStyle: String, CaseIterable, Sendable {
    case orbital    // Circle around center
    case grid       // Evenly spaced grid
    case linear     // Horizontal line
    case clustered  // Random cluster
    case llmDriven  // AI semantic placement

    // NEW: Magical spatial arrangements
    case snake      // Sinusoidal serpent pattern
    case spiral     // Outward spiral from center
    case wave       // Horizontal wave pattern
    case diamond    // Diamond/rhombus shape
    case tree       // Hierarchical tree layout
    case flow       // Flowing river pattern
}

// MARK: - Direction
enum Direction: String {
    case left, right, up, down
}
