// CosmoOS/Core/Undo/Actions/MoveDrawingAction.swift

import Foundation

@MainActor
final class MoveDrawingAction: UndoableAction {
    let actionDescription = "Move Drawing"
    let timestamp: Date

    private let drawingId: String
    private let oldOrigin: CGPoint
    private let newOrigin: CGPoint
    /// For freehand drawings, path points also shift
    private let oldPathPoints: [CGPoint]?
    private let newPathPoints: [CGPoint]?
    private weak var drawingState: DrawingStateManager?

    init(drawingId: String,
         oldOrigin: CGPoint,
         newOrigin: CGPoint,
         oldPathPoints: [CGPoint]?,
         newPathPoints: [CGPoint]?,
         drawingState: DrawingStateManager) {
        self.drawingId = drawingId
        self.oldOrigin = oldOrigin
        self.newOrigin = newOrigin
        self.oldPathPoints = oldPathPoints
        self.newPathPoints = newPathPoints
        self.drawingState = drawingState
        self.timestamp = Date()
    }

    func undo() async {
        applyState(origin: oldOrigin, pathPoints: oldPathPoints)
    }

    func redo() async {
        applyState(origin: newOrigin, pathPoints: newPathPoints)
    }

    private func applyState(origin: CGPoint, pathPoints: [CGPoint]?) {
        guard let state = drawingState,
              let idx = state.drawings.firstIndex(where: { $0.id == drawingId }) else { return }
        state.drawings[idx].origin = origin
        if let points = pathPoints {
            state.drawings[idx].pathPoints = points
        }
        state.saveDrawing(state.drawings[idx])
    }
}
