// CosmoOS/Core/Undo/Actions/ResizeBlockAction.swift

import Foundation
import SwiftUI

@MainActor
final class ResizeBlockAction: UndoableAction {
    let actionDescription = "Resize Block"
    let timestamp: Date

    private let blockId: String
    private let oldSize: CGSize
    private let newSize: CGSize
    private weak var spatialEngine: SpatialEngine?

    init(blockId: String, oldSize: CGSize, newSize: CGSize, spatialEngine: SpatialEngine) {
        self.blockId = blockId
        self.oldSize = oldSize
        self.newSize = newSize
        self.spatialEngine = spatialEngine
        self.timestamp = Date()
    }

    func undo() async {
        applySize(oldSize)
    }

    func redo() async {
        applySize(newSize)
    }

    private func applySize(_ size: CGSize) {
        guard let engine = spatialEngine,
              let index = engine.blocks.firstIndex(where: { $0.id == blockId }) else { return }
        engine.blocks[index].size = size
        Task { await engine.saveBlock(engine.blocks[index]) }
    }
}
