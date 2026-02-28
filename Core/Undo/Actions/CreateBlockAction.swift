// CosmoOS/Core/Undo/Actions/CreateBlockAction.swift

import Foundation

@MainActor
final class CreateBlockAction: UndoableAction {
    let actionDescription = "Create Block"
    let timestamp: Date

    private let block: CanvasBlock
    private weak var spatialEngine: SpatialEngine?

    init(block: CanvasBlock, spatialEngine: SpatialEngine) {
        self.block = block
        self.spatialEngine = spatialEngine
        self.timestamp = Date()
    }

    func undo() async {
        await spatialEngine?.removeBlock(block.id)
    }

    func redo() async {
        await spatialEngine?.restoreBlock(block)
    }
}
