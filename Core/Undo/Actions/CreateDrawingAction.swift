// CosmoOS/Core/Undo/Actions/CreateDrawingAction.swift

import Foundation

@MainActor
final class CreateDrawingAction: UndoableAction {
    let actionDescription = "Create Drawing"
    let timestamp: Date

    private let drawing: CanvasDrawing
    private weak var drawingState: DrawingStateManager?

    init(drawing: CanvasDrawing, drawingState: DrawingStateManager) {
        self.drawing = drawing
        self.drawingState = drawingState
        self.timestamp = Date()
    }

    func undo() async {
        drawingState?.deleteDrawing(drawing.id)
    }

    func redo() async {
        drawingState?.saveDrawing(drawing)
    }
}
