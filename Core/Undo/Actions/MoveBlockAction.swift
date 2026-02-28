// CosmoOS/Core/Undo/Actions/MoveBlockAction.swift

import Foundation

@MainActor
final class MoveBlockAction: UndoableAction {
    let actionDescription = "Move Block"
    let timestamp: Date

    private let blockId: String
    private let oldPosition: CGPoint
    private(set) var newPosition: CGPoint
    private weak var spatialEngine: SpatialEngine?

    init(blockId: String, oldPosition: CGPoint, newPosition: CGPoint, spatialEngine: SpatialEngine) {
        self.blockId = blockId
        self.oldPosition = oldPosition
        self.newPosition = newPosition
        self.spatialEngine = spatialEngine
        self.timestamp = Date()
    }

    func undo() async {
        spatialEngine?.updateBlockPosition(blockId, position: oldPosition)
    }

    func redo() async {
        spatialEngine?.updateBlockPosition(blockId, position: newPosition)
    }

    // MARK: - Coalescing (rapid micro-moves merge into one action)

    func canCoalesce(with other: UndoableAction) -> Bool {
        guard let otherMove = other as? MoveBlockAction else { return false }
        return otherMove.blockId == blockId
    }

    func coalesce(with other: UndoableAction) {
        guard let otherMove = other as? MoveBlockAction else { return }
        // Keep our original oldPosition, take the latest newPosition
        newPosition = otherMove.newPosition
    }
}
