// CosmoOS/Sync/SyncIntegration.swift
// Integrates sync with all entity operations
// All changes are tracked automatically through AtomRepository → ChangeTracker → SyncEngine
// Phase 1: Cleaned up legacy table references (research, journal_entries)

import Foundation

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
