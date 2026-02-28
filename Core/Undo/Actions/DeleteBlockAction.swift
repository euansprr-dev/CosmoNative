// CosmoOS/Core/Undo/Actions/DeleteBlockAction.swift

import Foundation

@MainActor
final class DeleteBlockAction: UndoableAction {
    let actionDescription = "Delete Block"
    let timestamp: Date

    private let block: CanvasBlock
    private weak var spatialEngine: SpatialEngine?

    init(block: CanvasBlock, spatialEngine: SpatialEngine) {
        self.block = block
        self.spatialEngine = spatialEngine
        self.timestamp = Date()
    }

    func undo() async {
        await spatialEngine?.restoreBlock(block)
    }

    func redo() async {
        await spatialEngine?.removeBlock(block.id)
    }
}
