// CosmoOS/Sync/SyncIntegration.swift
// Integrates sync with all entity operations
// All changes are now tracked automatically through AtomRepository

import Foundation

// MARK: - AtomRepository Sync Extensions
// NOTE: AtomRepository already tracks all changes via ChangeTracker.
// These convenience methods exist for explicit sync control if needed.

extension AtomRepository {
    /// Create an atom with explicit sync tracking confirmation
    @discardableResult
    func createAndSync(_ atom: Atom) async throws -> Atom {
        // AtomRepository.create() already tracks changes
        return try await create(atom)
    }

    /// Update an atom with explicit sync tracking confirmation
    @discardableResult
    func updateAndSync(_ atom: Atom) async throws -> Atom {
        // AtomRepository.update() already tracks changes
        return try await update(atom)
    }

    /// Delete an atom with explicit sync tracking confirmation
    func deleteAndSync(uuid: String) async throws {
        // AtomRepository.delete() already tracks changes
        try await delete(uuid: uuid)
    }
}

// MARK: - Scheduler Engine Sync Extension
extension SchedulerEngine {
    func createBlockAndSync(_ block: inout ScheduleBlock) async throws {
        block = try await createBlockAndSync(block)
    }

    func createBlockAndSync(_ block: ScheduleBlock) async throws -> ScheduleBlock {
        let created = try await CosmoDatabase.shared.asyncWrite { db -> ScheduleBlock in
            var insertingBlock = block
            try insertingBlock.insert(db)
            insertingBlock.databaseId = db.lastInsertedRowID
            return insertingBlock
        }

        Task {
            await ChangeTracker.shared.trackInsert(table: "schedule_blocks", entity: created)
        }

        return created
    }

    func updateBlockAndSync(_ block: ScheduleBlock) async throws {
        try await CosmoDatabase.shared.asyncWrite { db in
            try block.update(db)
        }

        Task {
            await ChangeTracker.shared.trackUpdate(table: "schedule_blocks", entity: block)
        }
    }

    func deleteBlockAndSync(id: Int64, uuid: String) async throws {
        try await CosmoDatabase.shared.asyncWrite { db in
            try db.execute(
                sql: "UPDATE schedule_blocks SET is_deleted = 1, updated_at = ? WHERE id = ?",
                arguments: [ISO8601DateFormatter().string(from: Date()), id]
            )
        }

        Task {
            await ChangeTracker.shared.trackDelete(table: "schedule_blocks", uuid: uuid, rowId: id)
        }
    }
}

// MARK: - Canvas Block Sync
extension SpatialEngine {
    func saveBlockAndSync(_ block: CanvasBlock) async {
        // Save locally first
        await saveBlockToDatabase(block)

        // Track for sync
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
        self.isCollapsed = false  // Not tracked in current CanvasBlock model
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

// MARK: - Research Sync Extension
extension ResearchService {
    func saveResearchAndSync(_ research: inout Research) async throws {
        research = try await saveResearchAndSync(research)
    }

    func saveResearchAndSync(_ research: Research) async throws -> Research {
        let database = await MainActor.run { CosmoDatabase.shared }
        let created = try await database.asyncWrite { db -> Research in
            var insertingResearch = research
            try insertingResearch.insert(db)
            insertingResearch.id = db.lastInsertedRowID
            return insertingResearch
        }

        Task {
            await ChangeTracker.shared.trackInsert(table: "research", entity: created)
        }

        return created
    }
}

// MARK: - Journal Entry Sync Extension (for Cosmo conversations)
extension CosmoCore {
    func saveJournalEntryAndSync(_ entry: inout JournalEntry) async throws {
        entry = try await saveJournalEntryAndSync(entry)
    }

    func saveJournalEntryAndSync(_ entry: JournalEntry) async throws -> JournalEntry {
        let created = try await database.asyncWrite { db -> JournalEntry in
            let entryCopy = entry
            try entryCopy.insert(db)
            return entryCopy
        }

        Task {
            await ChangeTracker.shared.trackInsert(table: "journal_entries", entity: created)
        }

        return created
    }
}

// JournalEntry already conforms to Syncable (has id, uuid, and is Encodable)
