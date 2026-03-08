// CosmoOS/Canvas/Drawing/CanvasDrawingGestureLayer.swift
// Transparent gesture capture layer for drawing tools
// Lives OUTSIDE the scaled ZStack — converts screen coords to canvas coords

import SwiftUI

struct CanvasDrawingGestureLayer: View {
    @ObservedObject var drawingState: DrawingStateManager
    let transform: CanvasViewportTransform

    // Block frame tracker for lasso hit testing
    @EnvironmentObject var blockFrameTracker: CanvasBlockFrameTracker

    // Forward magnification to parent
    @GestureState private var magnificationState: CGFloat = 1.0
    var onMagnification: ((CGFloat) -> Void)?
    var onMagnificationEnd: ((CGFloat) -> Void)?

    // Lasso state
    @State private var lassoPoints: [CGPoint] = []

    private var effectiveScale: CGFloat {
        transform.effectiveScale
    }

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .allowsHitTesting(drawingState.toolMode != .select)
                .onContinuousHover { phase in
                    switch phase {
                    case .active:
                        updateCursor(for: drawingState.toolMode)
                    case .ended:
                        NSCursor.arrow.set()
                    }
                }
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

            // Lasso visual preview
            if drawingState.toolMode == .lasso, drawingState.currentLassoSubMode == .lasso, lassoPoints.count > 1 {
                lassoPreview
                    .allowsHitTesting(false)
            }

            // Zone rectangle preview
            if drawingState.toolMode == .lasso, drawingState.currentLassoSubMode == .zone, drawingState.activeZoneRect != nil {
                zonePreview
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Lasso Preview

    private var lassoPreview: some View {
        Path { path in
            path.move(to: lassoPoints[0])
            for i in 1..<lassoPoints.count {
                path.addLine(to: lassoPoints[i])
            }
            // Close the path visually
            path.addLine(to: lassoPoints[0])
        }
        .stroke(
            DS.textMuted,
            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round, dash: [6, 4])
        )
    }

    // MARK: - Zone Preview

    private var zonePreview: some View {
        let rect = drawingState.activeZoneRect ?? .zero
        let screenOrigin = canvasToScreen(CGPoint(x: rect.minX, y: rect.minY))
        let screenEnd = canvasToScreen(CGPoint(x: rect.maxX, y: rect.maxY))
        let screenRect = CGRect(
            x: min(screenOrigin.x, screenEnd.x),
            y: min(screenOrigin.y, screenEnd.y),
            width: abs(screenEnd.x - screenOrigin.x),
            height: abs(screenEnd.y - screenOrigin.y)
        )

        return ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(DS.textMuted.opacity(0.04))
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    DS.textMuted.opacity(0.6),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [8, 5])
                )
        }
        .frame(width: screenRect.width, height: screenRect.height)
        .position(x: screenRect.midX, y: screenRect.midY)
    }

    // MARK: - Canvas → Screen Coordinate Conversion

    private func canvasToScreen(_ point: CGPoint) -> CGPoint {
        transform.canvasToScreen(point)
    }

    // MARK: - Screen → Canvas Coordinate Conversion

    /// Reverses the scale+offset transform to convert screen-space points to canvas-space
    private func screenToCanvas(_ point: CGPoint) -> CGPoint {
        transform.screenToCanvas(point)
    }

    // MARK: - Drawing Gesture

    private var drawingGesture: some Gesture {
        DragGesture(minimumDistance: drawingState.toolMode == .draw || drawingState.toolMode == .lasso ? 1 : 5)
            .onChanged { value in
                let canvasStart = screenToCanvas(value.startLocation)
                let canvasLoc = screenToCanvas(value.location)

                switch drawingState.toolMode {
                case .shape:
                    // Monitor Shift key for 1:1 aspect ratio constraint
                    drawingState.shiftConstrain = NSEvent.modifierFlags.contains(.shift)
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

                case .lasso:
                    switch drawingState.currentLassoSubMode {
                    case .lasso:
                        // Collect screen-space points for lasso (hit test against screen-space block frames)
                        if lassoPoints.isEmpty {
                            lassoPoints = [value.startLocation]
                        }
                        lassoPoints.append(value.location)
                    case .zone:
                        // Zone: drag rectangle in canvas coords
                        if drawingState.activeZoneRect == nil {
                            drawingState.beginZone(at: canvasStart)
                        }
                        drawingState.updateZone(to: canvasLoc)
                    }

                case .text, .select:
                    break
                }
            }
            .onEnded { value in
                switch drawingState.toolMode {
                case .shape:
                    drawingState.finishShape()
                case .draw:
                    drawingState.finishFreehand()
                case .lasso:
                    switch drawingState.currentLassoSubMode {
                    case .lasso:
                        finishLasso()
                    case .zone:
                        finishZone(startLocation: value.startLocation, endLocation: value.location)
                    }
                case .erase, .text, .select:
                    break
                }
            }
    }

    // MARK: - Lasso Completion

    private func finishLasso() {
        guard lassoPoints.count >= 3 else {
            lassoPoints = []
            return
        }

        // Force-refresh block frames to capture any blocks dragged since last pan/zoom change
        blockFrameTracker.updateFrames(
            blocks: blockFrameTracker.trackedBlocks,
            transform: transform
        )

        // Check which blocks have any point inside the lasso polygon (screen space)
        let enclosed = LassoGestureDetector.enclosedBlocks(
            lassoPath: lassoPoints,
            blockFrames: blockFrameTracker.blockFrames
        )

        lassoPoints = []

        guard enclosed.count >= 2 else { return }

        // Post notification with enclosed block IDs
        NotificationCenter.default.post(
            name: CosmoNotification.Canvas.lassoEnclosedBlocks,
            object: nil,
            userInfo: ["blockIds": enclosed]
        )
    }

    // MARK: - Zone Completion

    private func finishZone(startLocation: CGPoint, endLocation: CGPoint) {
        guard let rect = drawingState.finishZone() else { return }

        // Compute screen-space position for the popover (center-top of drawn rectangle)
        let popoverX = (startLocation.x + endLocation.x) / 2
        let popoverY = min(startLocation.y, endLocation.y) - 40

        NotificationCenter.default.post(
            name: CosmoNotification.Canvas.zoneDrawn,
            object: nil,
            userInfo: [
                "rectX": rect.origin.x,
                "rectY": rect.origin.y,
                "rectW": rect.size.width,
                "rectH": rect.size.height,
                "popoverX": popoverX,
                "popoverY": popoverY,
            ]
        )
    }

    // MARK: - Tap Handling

    private func handleTap(at location: CGPoint) {
        switch drawingState.toolMode {
        case .text:
            drawingState.createText(at: location)
        case .erase:
            eraseAtPoint(location)
        case .shape, .draw, .select, .lasso:
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

    // MARK: - Tool Cursors

    private func updateCursor(for mode: CanvasToolMode) {
        switch mode {
        case .draw:
            NSCursor.crosshair.set()
        case .shape:
            NSCursor.crosshair.set()
        case .text:
            NSCursor.iBeam.set()
        case .erase:
            NSCursor.disappearingItem.set()
        case .lasso:
            NSCursor.crosshair.set()
        case .select:
            NSCursor.arrow.set()
        }
    }
}
