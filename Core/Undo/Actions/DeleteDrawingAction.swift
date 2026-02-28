// CosmoOS/Core/Undo/Actions/DeleteDrawingAction.swift

import Foundation

@MainActor
final class DeleteDrawingAction: UndoableAction {
    let actionDescription = "Delete Drawing"
    let timestamp: Date

    private let drawing: CanvasDrawing
    private weak var drawingState: DrawingStateManager?

    init(drawing: CanvasDrawing, drawingState: DrawingStateManager) {
        self.drawing = drawing
        self.drawingState = drawingState
        self.timestamp = Date()
    }

    func undo() async {
        // Restore the drawing (re-add to memory + persist)
        drawingState?.restoreDrawing(drawing)
    }

    func redo() async {
        drawingState?.deleteDrawing(drawing.id)
    }
}
