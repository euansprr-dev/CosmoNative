// CosmoOS/Canvas/SpatialEngine.swift
// Voice-driven spatial placement and layout system

import Foundation
import SwiftUI
import GRDB

@MainActor
class SpatialEngine: ObservableObject {
    @Published var blocks: [CanvasBlock] = [] {
        didSet { blocksDataRevision &+= 1 }
    }
    @Published var isLoading = false
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
        pendingGeometryWrites.removeAll()
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

                // Filter by ThinkSpace if provided
                if let thinkspaceId = tsId {
                    query = query.filter(Column("thinkspace_id") == thinkspaceId)
                } else {
                    // If no thinkspace specified, only load blocks without a thinkspace
                    query = query.filter(Column("thinkspace_id") == nil)
                }

                let records = try query.order(Column("z_index")).fetchAll(db)

                // The metadata column (sticky color, rich body document, …) is not
                // part of CanvasBlockRecord — fetch it separately and key by block id.
                var metadataById: [String: String] = [:]
                let metadataRows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT id, metadata FROM canvas_blocks
                        WHERE document_type = ? AND document_id = ? AND is_deleted = 0 AND thinkspace_id IS ?
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

            // Enrich rich block types with atom metadata in two batch reads instead
            // of one DB round-trip per block during thinkspace switches.
            let enrichableTypes: Set<String> = ["research", "image", "note", "template"]
            let enrichableRecords = savedBlocks.filter { enrichableTypes.contains($0.entityType) }
            let idsToFetch = enrichableRecords
                .map { Int64($0.entityId) }
                .filter { $0 > 0 }
            let uuidsToFetch = enrichableRecords
                .compactMap(\.entityUuid)
                .filter { !$0.isEmpty }

            async let atomsByIDTask = AtomRepository.shared.fetchBatch(ids: Array(Set(idsToFetch)))
            async let atomsByUUIDTask = AtomRepository.shared.fetchBatch(uuids: Array(Set(uuidsToFetch)))
            let fetchedAtomsByID = (try? await atomsByIDTask) ?? []
            let fetchedAtomsByUUID = (try? await atomsByUUIDTask) ?? []

            // Record→block conversion decodes atom metadata JSON per rich block —
            // too heavy for the main actor during a switch animation.
            return await Task.detached(priority: .userInitiated) {
                Self.buildBlocks(
                    records: savedBlocks,
                    metadataJSONByBlockId: metadataJSONByBlockId,
                    fetchedAtomsByID: fetchedAtomsByID,
                    fetchedAtomsByUUID: fetchedAtomsByUUID
                )
            }.value
        } catch {
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

    nonisolated private static func buildBlocks(
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
                loadedBlocks.append(block)
            }

            let atomsByID = Dictionary(uniqueKeysWithValues: fetchedAtomsByID.compactMap { atom in
                atom.id.map { ($0, atom) }
            })
            let atomsByUUID = Dictionary(uniqueKeysWithValues: fetchedAtomsByUUID.map { ($0.uuid, $0) })

            let enrichedBlocks = loadedBlocks.map { block -> CanvasBlock in
                guard block.entityType == .research ||
                        block.entityType == .image ||
                        block.entityType == .note ||
                        block.entityType == .template else {
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

                let existingBlockId = try String.fetchOne(
                    db,
                    sql: """
                        SELECT id FROM canvas_blocks
                        WHERE id = ? AND is_deleted = 0
                        LIMIT 1
                    """,
                    arguments: [block.id]
                )

                if existingBlockId != nil {
                    // NOTE: deliberately does NOT rewrite thinkspace_id — during a
                    // thinkspace-switch overlap window the engine context can lag,
                    // and rewriting it here re-homed blocks into the wrong space.
                    // Only the INSERT branch assigns a row's thinkspace.
                    try db.execute(
                        sql: """
                            UPDATE canvas_blocks
                            SET entity_type = ?, entity_id = ?, entity_uuid = ?, atom_uuid = ?, entity_title = ?,
                                position_x = ?, position_y = ?, width = ?, height = ?,
                                z_index = ?, note_content = ?, metadata = ?, is_pinned = ?, updated_at = CURRENT_TIMESTAMP
                            WHERE id = ?
                        """,
                        arguments: [
                            block.entityType.rawValue, block.entityId, block.entityUuid, atomUUID, block.title,
                            Int(block.position.x), Int(block.position.y),
                            Int(block.size.width), Int(block.size.height),
                            block.zIndex, noteContent, metadataJSON, block.isPinned,
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
                                SET entity_type = ?, entity_id = ?, entity_uuid = ?, atom_uuid = ?, entity_title = ?,
                                    position_x = ?, position_y = ?, width = ?, height = ?,
                                    z_index = ?, note_content = ?, metadata = ?, is_pinned = ?, updated_at = CURRENT_TIMESTAMP
                                WHERE id = ?
                            """,
                            arguments: [
                                block.entityType.rawValue, block.entityId, block.entityUuid, atomUUID, block.title,
                                Int(block.position.x), Int(block.position.y),
                                Int(block.size.width), Int(block.size.height),
                                block.zIndex, noteContent, metadataJSON, block.isPinned,
                                existingId
                            ]
                        )
                        return
                    }
                }

                // No existing row (or empty entityUuid for notes) — insert new
                try db.execute(
                    sql: """
                    INSERT OR REPLACE INTO canvas_blocks
                    (id, document_type, document_id, entity_type, entity_id, entity_uuid, atom_uuid, entity_title,
                     position_x, position_y, width, height, z_index, note_content, metadata, is_pinned, thinkspace_id, is_deleted, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
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
                SET thinkspace_id = ?, position_x = ?, position_y = ?, updated_at = CURRENT_TIMESTAMP
                WHERE id = ?
                """,
                arguments: [targetThinkspaceId, Int(position.x), Int(position.y), blockId]
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
            switch await entityExistsInDb(block.entityUuid) {
            case true?:
                print("⚠️ addBlock: entity \(block.entityUuid) already in DB, skipping")
                return
            case nil:
                // Unknown (DB error) — creating anyway could produce a duplicate row.
                PersistenceHealth.note(.writeFailure, context: "spatialEngine.addBlock", detail: "duplicate check failed for \(block.entityUuid); skipping create")
                print("⚠️ addBlock: duplicate check failed for \(block.entityUuid), skipping create")
                return
            case false?:
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

    /// Check if an entity already has a canvas_block row in the current thinkspace/document.
    /// Returns nil when the check itself failed (unknown) — callers must NOT
    /// treat unknown as "doesn't exist" or they can create duplicate rows.
    private func entityExistsInDb(_ entityUuid: String) async -> Bool? {
        let docType = currentDocumentType
        let docId = currentDocumentId
        let tsId = currentThinkspaceId
        do {
            return try await database.asyncRead { db in
                let count = try Int.fetchOne(db,
                    sql: """
                        SELECT COUNT(*) FROM canvas_blocks
                        WHERE entity_uuid = ? AND thinkspace_id IS ? AND document_type = ? AND document_id = ? AND is_deleted = 0
                    """,
                    arguments: [entityUuid, tsId, docType, docId]
                ) ?? 0
                return count > 0
            }
        } catch {
            print("❌ entityExistsInDb failed for \(entityUuid): \(error)")
            return nil
        }
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
