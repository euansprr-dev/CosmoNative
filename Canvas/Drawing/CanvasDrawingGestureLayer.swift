// CosmoOS/Canvas/Drawing/CanvasDrawingGestureLayer.swift
// Transparent gesture capture layer for drawing tools
// Lives OUTSIDE the scaled ZStack — converts screen coords to canvas coords

import SwiftUI

struct CanvasDrawingGestureLayer: View {
    @ObservedObject var drawingState: DrawingStateManager

    // Coordinate conversion params (passed from CanvasView)
    var canvasOffset: CGSize = .zero
    var scaledPanOffset: CGSize = .zero
    var effectiveScale: CGFloat = 1.0
    var screenCenter: CGPoint = .zero

    // Forward magnification to parent
    @GestureState private var magnificationState: CGFloat = 1.0
    var onMagnification: ((CGFloat) -> Void)?
    var onMagnificationEnd: ((CGFloat) -> Void)?

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .allowsHitTesting(drawingState.toolMode != .select)
            .gesture(drawingGesture)
            .simultaneousGesture(
                MagnifyGesture()
                    .updating($magnificationState) { value, state, _ in
                        state = value.magnification
                        onMagnification?(value.magnification)
                    }
                    .onEnded { value in
                        onMagnificationEnd?(value.magnification)
                    }
            )
            .onTapGesture { location in
                handleTap(at: screenToCanvas(location))
            }
    }

    // MARK: - Screen → Canvas Coordinate Conversion

    /// Reverses the scale+offset transform to convert screen-space points to canvas-space
    private func screenToCanvas(_ point: CGPoint) -> CGPoint {
        let unscaledX = screenCenter.x + (point.x - screenCenter.x) / effectiveScale
        let unscaledY = screenCenter.y + (point.y - screenCenter.y) / effectiveScale
        return CGPoint(
            x: unscaledX - canvasOffset.width - scaledPanOffset.width,
            y: unscaledY - canvasOffset.height - scaledPanOffset.height
        )
    }

    // MARK: - Drawing Gesture

    private var drawingGesture: some Gesture {
        DragGesture(minimumDistance: drawingState.toolMode == .draw ? 1 : 5)
            .onChanged { value in
                let canvasStart = screenToCanvas(value.startLocation)
                let canvasLoc = screenToCanvas(value.location)

                switch drawingState.toolMode {
                case .shape:
                    if drawingState.activeDrawing == nil {
                        drawingState.beginShape(at: canvasStart)
                    }
                    drawingState.updateShape(to: canvasLoc)

                case .draw:
                    if drawingState.activeDrawing == nil {
                        drawingState.beginFreehand(at: canvasStart)
                    }
                    drawingState.addFreehandPoint(canvasLoc)

                case .erase:
                    eraseAtPoint(canvasLoc)

                case .text, .select:
                    break
                }
            }
            .onEnded { _ in
                switch drawingState.toolMode {
                case .shape:
                    drawingState.finishShape()
                case .draw:
                    drawingState.finishFreehand()
                case .erase, .text, .select:
                    break
                }
            }
    }

    // MARK: - Tap Handling

    private func handleTap(at location: CGPoint) {
        switch drawingState.toolMode {
        case .text:
            drawingState.createText(at: location)
        case .erase:
            eraseAtPoint(location)
        case .shape, .draw, .select:
            break
        }
    }

    // MARK: - Erase Hit Test

    private func eraseAtPoint(_ point: CGPoint) {
        for drawing in drawingState.drawings.reversed() {
            if hitTest(point: point, drawing: drawing) {
                withAnimation(ProMotionSprings.snappy) {
                    drawingState.deleteDrawing(drawing.id)
                }
                return
            }
        }
    }

    private func hitTest(point: CGPoint, drawing: CanvasDrawing) -> Bool {
        let threshold: CGFloat = 10

        switch drawing.drawingType {
        case .shape, .text:
            let rect = drawing.boundingRect.insetBy(dx: -threshold, dy: -threshold)
            return rect.contains(point)

        case .freehand:
            guard let points = drawing.pathPoints else { return false }
            for pt in points {
                if hypot(point.x - pt.x, point.y - pt.y) < threshold + drawing.strokeWidth / 2 {
                    return true
                }
            }
            return false
        }
    }
}
