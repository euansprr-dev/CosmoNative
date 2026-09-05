// CosmoOS/Core/Undo/Actions/UnplaceBlockAction.swift
// "Remove from canvas": the block leaves the canvas but stays a member of
// the space (it waits in the tray). Undo restores the exact placement.

import Foundation

@MainActor
final class UnplaceBlockAction: UndoableAction {
    let actionDescription = "Remove from Canvas"
    let timestamp: Date

    private let block: CanvasBlock
    private weak var spatialEngine: SpatialEngine?

    init(block: CanvasBlock, spatialEngine: SpatialEngine) {
        self.block = block
        self.spatialEngine = spatialEngine
        self.timestamp = Date()
    }

    func undo() async {
        await spatialEngine?.restorePlacement(block)
    }

    func redo() async {
        _ = await spatialEngine?.unplaceBlock(block.id)
    }
}

/// Placing a tray member on the canvas. Undo sends it back to the tray.
@MainActor
final class PlaceMemberAction: UndoableAction {
    let actionDescription = "Place on Canvas"
    let timestamp: Date

    private let entityUuid: String
    private let position: CGPoint
    private var placedBlockId: String?
    private weak var spatialEngine: SpatialEngine?

    init(entityUuid: String, position: CGPoint, placedBlockId: String?, spatialEngine: SpatialEngine) {
        self.entityUuid = entityUuid
        self.position = position
        self.placedBlockId = placedBlockId
        self.spatialEngine = spatialEngine
        self.timestamp = Date()
    }

    func undo() async {
        guard let placedBlockId else { return }
        _ = await spatialEngine?.unplaceBlock(placedBlockId)
    }

    func redo() async {
        if let block = await spatialEngine?.placeMember(entityUuid: entityUuid, at: position) {
            placedBlockId = block.id
        }
    }
}
