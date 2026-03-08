// CosmoOS/Canvas/Drawing/CanvasDrawingsLayer.swift
// Rendering layer for all canvas drawing elements
// Lives OUTSIDE the scaled ZStack — renders in screen coordinates to prevent clipping

import SwiftUI
import AppKit

struct CanvasDrawingsLayer: View {
    @ObservedObject var drawingState: DrawingStateManager
    let transform: CanvasViewportTransform
    @StateObject private var strokeCache = CanvasDrawingStrokeCache()

    // MARK: - Constants

    private enum Constants {
        static let hitTestWidth: CGFloat = 20
        static let deleteButtonOffset: CGFloat = 20
        static let selectionPadding: CGFloat = 8
        static let resizeHandleSize: CGFloat = 10
        static let resizeHandleHitSize: CGFloat = 22
        static let shapeHitPadding: CGFloat = 10
        static let minimumShapeHitDimension: CGFloat = 28
        static let lineHitExpansion: CGFloat = 12
    }

    // MARK: - Coordinate Conversion

    /// Convert a canvas-space point to screen-space for rendering
    private func canvasToScreen(_ p: CGPoint) -> CGPoint {
        transform.canvasToScreen(p)
    }

    /// Scale a canvas-space size to screen-space
    private func scaleSize(_ s: CGSize) -> CGSize {
        CGSize(width: s.width * transform.effectiveScale, height: s.height * transform.effectiveScale)
    }

    private var effectiveScale: CGFloat {
        transform.effectiveScale
    }

    /// Returns the drag offset for a drawing being dragged (in canvas space)
    private func dragOffset(for id: String) -> CGSize {
        drawingState.draggingDrawingId == id ? drawingState.drawingDragOffset : .zero
    }

    /// Canvas point with drag offset applied, then converted to screen
    private func canvasToScreenDragged(_ p: CGPoint, drawingId: String) -> CGPoint {
        let drag = dragOffset(for: drawingId)
        return canvasToScreen(CGPoint(x: p.x + drag.width, y: p.y + drag.height))
    }

    private func canvasRectToScreen(_ rect: CGRect) -> CGRect {
        let minPt = canvasToScreen(rect.origin)
        let maxPt = canvasToScreen(CGPoint(x: rect.maxX, y: rect.maxY))
        return CGRect(
            x: min(minPt.x, maxPt.x),
            y: min(minPt.y, maxPt.y),
            width: abs(maxPt.x - minPt.x),
            height: abs(maxPt.y - minPt.y)
        )
    }

    private func drawingRectWithDrag(_ drawing: CanvasDrawing) -> CGRect {
        let rect = drawing.boundingRect
        let drag = dragOffset(for: drawing.id)
        return rect.offsetBy(dx: drag.width, dy: drag.height)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // 1. Freehand strokes — cached canvas-space paths rendered through one Canvas.
            freehandLayer
                .allowsHitTesting(false)

            // 2. Shape views
            shapesLayer

            // 3. Text views
            textsLayer

            // 4. Freehand hit areas (invisible fat paths for tap detection)
            freehandHitLayer

            // 5. Group selection outline + resize handles for selected shapes
            selectionOverlayLayer

            // 6. Active drawing preview (in-progress shape or freehand)
            activePreviewLayer
                .allowsHitTesting(false)

            // 7. Delete button for selected element
            deleteButtonLayer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: drawingState.drawings.map(\.id)) { _, ids in
            strokeCache.retain(ids: Set(ids))
        }
        .onDisappear {
            strokeCache.invalidateAll()
        }
    }

    // MARK: - Freehand Layer (Path views — no frame clipping)

    private var freehandLayer: some View {
        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, _ in
            let signpost = CanvasPerformanceInstrumentation.signposter.beginInterval("drawing-strokes")
            let screenTransform = transform.canvasToScreenAffineTransform()

            for drawing in drawingState.drawings where drawing.drawingType == .freehand {
                guard let rendering = strokeCache.rendering(for: drawing) else { continue }

                var drawingContext = context
                drawingContext.concatenate(screenTransform)
                drawingContext.opacity = drawing.opacity

                let translatedPath = rendering.path.applying(
                    CGAffineTransform(
                        translationX: dragOffset(for: drawing.id).width,
                        y: dragOffset(for: drawing.id).height
                    )
                )

                switch rendering {
                case .fill:
                    drawingContext.fill(translatedPath, with: .color(CanvasDrawing.colorFromHex(drawing.strokeColor)))
                case .stroke(_, let lineWidth):
                    drawingContext.stroke(
                        translatedPath,
                        with: .color(CanvasDrawing.colorFromHex(drawing.strokeColor)),
                        style: StrokeStyle(
                            lineWidth: lineWidth,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                }
            }

            CanvasPerformanceInstrumentation.signposter.endInterval("drawing-strokes", signpost)
        }
    }

    // MARK: - Variable-Width Stroke Rendering

    /// Builds a filled Path that simulates a variable-width stroke by computing
    /// perpendicular offsets at each point and connecting them with bezier curves.
    private func variableWidthStrokePath(points: [CGPoint], widths: [CGFloat]) -> Path {
        guard points.count >= 2 else { return Path() }

        let scaledWidths = widths.map { $0 * effectiveScale / 2.0 }

        // Compute perpendicular normals at each point
        var normals: [CGPoint] = []
        for i in 0..<points.count {
            let prev = i > 0 ? points[i - 1] : points[i]
            let next = i < points.count - 1 ? points[i + 1] : points[i]
            let dx = next.x - prev.x
            let dy = next.y - prev.y
            let len = max(hypot(dx, dy), 0.001)
            normals.append(CGPoint(x: -dy / len, y: dx / len))
        }

        // Build left and right edge points
        var leftEdge: [CGPoint] = []
        var rightEdge: [CGPoint] = []
        for i in 0..<points.count {
            let w = scaledWidths[i]
            leftEdge.append(CGPoint(x: points[i].x + normals[i].x * w, y: points[i].y + normals[i].y * w))
            rightEdge.append(CGPoint(x: points[i].x - normals[i].x * w, y: points[i].y - normals[i].y * w))
        }

        // Build filled path: left edge forward, right edge backward
        return Path { path in
            // Start cap (rounded)
            path.addArc(
                center: points[0],
                radius: max(scaledWidths[0], 0.5),
                startAngle: .radians(atan2(leftEdge[0].y - points[0].y, leftEdge[0].x - points[0].x) + Double.pi),
                endAngle: .radians(atan2(leftEdge[0].y - points[0].y, leftEdge[0].x - points[0].x)),
                clockwise: false
            )

            // Left edge with Catmull-Rom smoothing
            addSmoothCurve(to: &path, through: leftEdge)

            // End cap (rounded)
            let lastIdx = points.count - 1
            path.addArc(
                center: points[lastIdx],
                radius: max(scaledWidths[lastIdx], 0.5),
                startAngle: .radians(atan2(leftEdge[lastIdx].y - points[lastIdx].y, leftEdge[lastIdx].x - points[lastIdx].x)),
                endAngle: .radians(atan2(rightEdge[lastIdx].y - points[lastIdx].y, rightEdge[lastIdx].x - points[lastIdx].x)),
                clockwise: false
            )

            // Right edge backward with Catmull-Rom smoothing
            addSmoothCurve(to: &path, through: rightEdge.reversed())

            path.closeSubpath()
        }
    }

    /// Adds a smooth Catmull-Rom spline through the given points to the path.
    /// Continues from current path position (does NOT move to first point).
    private func addSmoothCurve(to path: inout Path, through points: [CGPoint]) {
        guard points.count >= 2 else { return }

        if points.count == 2 {
            path.addLine(to: points[1])
            return
        }

        // Continue from current position — addLine to first point to connect
        path.addLine(to: points[0])
        for i in 0..<(points.count - 1) {
            let p0 = i > 0 ? points[i - 1] : points[i]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = i + 2 < points.count ? points[i + 2] : points[i + 1]

            // Catmull-Rom to cubic bezier control points
            let cp1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6.0,
                y: p1.y + (p2.y - p0.y) / 6.0
            )
            let cp2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6.0,
                y: p2.y - (p3.y - p1.y) / 6.0
            )
            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }
    }

    /// Creates a smooth bezier path through points (for constant-width fallback)
    private func smoothBezierPath(through points: [CGPoint]) -> Path {
        Path { path in
            guard points.count >= 2 else { return }
            path.move(to: points[0])

            if points.count == 2 {
                path.addLine(to: points[1])
                return
            }

            for i in 0..<(points.count - 1) {
                let p0 = i > 0 ? points[i - 1] : points[i]
                let p1 = points[i]
                let p2 = points[i + 1]
                let p3 = i + 2 < points.count ? points[i + 2] : points[i + 1]

                let cp1 = CGPoint(
                    x: p1.x + (p2.x - p0.x) / 6.0,
                    y: p1.y + (p2.y - p0.y) / 6.0
                )
                let cp2 = CGPoint(
                    x: p2.x - (p3.x - p1.x) / 6.0,
                    y: p2.y - (p3.y - p1.y) / 6.0
                )
                path.addCurve(to: p2, control1: cp1, control2: cp2)
            }
        }
    }

    // MARK: - Shapes Layer

    private var shapesLayer: some View {
        ForEach(drawingState.drawings.filter { $0.drawingType == .shape }) { drawing in
            shapeView(for: drawing)
        }
    }

    @ViewBuilder
    private func shapeView(for drawing: CanvasDrawing) -> some View {
        let rect = drawing.boundingRect
        let drag = dragOffset(for: drawing.id)
        let draggedRect = CGRect(
            origin: CGPoint(x: rect.origin.x + drag.width, y: rect.origin.y + drag.height),
            size: rect.size
        )
        let screenMin = canvasToScreen(draggedRect.origin)
        let screenMax = canvasToScreen(CGPoint(x: draggedRect.maxX, y: draggedRect.maxY))
        let screenRect = CGRect(
            x: min(screenMin.x, screenMax.x),
            y: min(screenMin.y, screenMax.y),
            width: abs(screenMax.x - screenMin.x),
            height: abs(screenMax.y - screenMin.y)
        )
        let scaledStroke = drawing.strokeWidth * effectiveScale

        Group {
            switch drawing.shapeKind ?? .rectangle {
            case .rectangle:
                rectangleShape(drawing: drawing, rect: screenRect, strokeWidth: scaledStroke)
            case .roundedRectangle:
                roundedRectangleShape(drawing: drawing, rect: screenRect, strokeWidth: scaledStroke)
            case .circle:
                ellipseShape(drawing: drawing, rect: screenRect, strokeWidth: scaledStroke)
            case .line:
                lineShape(drawing: drawing, rect: screenRect, strokeWidth: scaledStroke)
            case .arrow:
                arrowShape(drawing: drawing, rect: screenRect, strokeWidth: scaledStroke)
            case .triangle:
                triangleShape(drawing: drawing, rect: screenRect, strokeWidth: scaledStroke)
            }
        }
        .overlay {
            shapeHitArea(for: drawing, rect: screenRect, scaledStroke: scaledStroke)
        }
        .opacity(drawing.opacity)
    }

    @ViewBuilder
    private func shapeHitArea(for drawing: CanvasDrawing, rect: CGRect, scaledStroke: CGFloat) -> some View {
        let kind = drawing.shapeKind ?? .rectangle
        let strokeHitWidth = max(Constants.hitTestWidth, scaledStroke + Constants.lineHitExpansion)
        let baseWidth = max(rect.width, 1)
        let baseHeight = max(rect.height, 1)
        let center = CGPoint(x: rect.midX, y: rect.midY)

        Group {
            switch kind {
            case .line:
                let start = CGPoint(
                    x: rect.width <= 1 ? baseWidth / 2 : 0,
                    y: rect.height <= 1 ? baseHeight / 2 : 0
                )
                let end = CGPoint(
                    x: rect.width <= 1 ? baseWidth / 2 : baseWidth,
                    y: rect.height <= 1 ? baseHeight / 2 : baseHeight
                )

                Path { path in
                    path.move(to: start)
                    path.addLine(to: end)
                }
                .strokedPath(StrokeStyle(
                    lineWidth: strokeHitWidth,
                    lineCap: .round,
                    lineJoin: .round
                ))
                .fill(Color.white.opacity(0.001))
                .frame(width: baseWidth, height: baseHeight)
                .position(center)

            case .arrow:
                let start = CGPoint(
                    x: rect.width <= 1 ? baseWidth / 2 : 0,
                    y: rect.height <= 1 ? baseHeight / 2 : 0
                )
                let end = CGPoint(
                    x: rect.width <= 1 ? baseWidth / 2 : baseWidth,
                    y: rect.height <= 1 ? baseHeight / 2 : baseHeight
                )

                Path { path in
                    path.move(to: start)
                    path.addLine(to: end)

                    let angle = atan2(end.y - start.y, end.x - start.x)
                    let headLength: CGFloat = 16 * effectiveScale
                    let headAngle: CGFloat = CGFloat.pi / 6

                    path.move(to: end)
                    path.addLine(to: CGPoint(
                        x: end.x - headLength * cos(angle - headAngle),
                        y: end.y - headLength * sin(angle - headAngle)
                    ))
                    path.move(to: end)
                    path.addLine(to: CGPoint(
                        x: end.x - headLength * cos(angle + headAngle),
                        y: end.y - headLength * sin(angle + headAngle)
                    ))
                }
                .strokedPath(StrokeStyle(
                    lineWidth: strokeHitWidth,
                    lineCap: .round,
                    lineJoin: .round
                ))
                .fill(Color.white.opacity(0.001))
                .frame(width: baseWidth, height: baseHeight)
                .position(center)

            case .rectangle, .roundedRectangle:
                if drawing.fillColor != nil {
                    Rectangle()
                        .fill(Color.white.opacity(0.001))
                        .frame(
                            width: max(rect.width + (Constants.shapeHitPadding * 2), Constants.minimumShapeHitDimension),
                            height: max(rect.height + (Constants.shapeHitPadding * 2), Constants.minimumShapeHitDimension)
                        )
                        .position(center)
                        .contentShape(Rectangle())
                } else {
                    Rectangle()
                        .stroke(Color.white.opacity(0.001), lineWidth: strokeHitWidth)
                        .frame(width: baseWidth, height: baseHeight)
                        .position(center)
                }

            case .circle:
                if drawing.fillColor != nil {
                    Ellipse()
                        .fill(Color.white.opacity(0.001))
                        .frame(
                            width: max(rect.width + (Constants.shapeHitPadding * 2), Constants.minimumShapeHitDimension),
                            height: max(rect.height + (Constants.shapeHitPadding * 2), Constants.minimumShapeHitDimension)
                        )
                        .position(center)
                } else {
                    Ellipse()
                        .stroke(Color.white.opacity(0.001), lineWidth: strokeHitWidth)
                        .frame(width: baseWidth, height: baseHeight)
                        .position(center)
                }

            case .triangle:
                let trianglePath = Path { path in
                    path.move(to: CGPoint(x: baseWidth / 2, y: 0))
                    path.addLine(to: CGPoint(x: baseWidth, y: baseHeight))
                    path.addLine(to: CGPoint(x: 0, y: baseHeight))
                    path.closeSubpath()
                }

                if drawing.fillColor != nil {
                    trianglePath
                        .fill(Color.white.opacity(0.001))
                        .frame(width: baseWidth, height: baseHeight)
                        .position(center)
                } else {
                    trianglePath
                        .strokedPath(StrokeStyle(lineWidth: strokeHitWidth, lineCap: .round, lineJoin: .round))
                        .fill(Color.white.opacity(0.001))
                        .frame(width: baseWidth, height: baseHeight)
                        .position(center)
                }
            }
        }
        .gesture(selectModeDragGesture(for: drawing, hitTest: { point in
            shapeContainsPoint(point, drawing: drawing, rect: rect, scaledStroke: scaledStroke)
        }))
        .onTapGesture { location in
            guard shapeContainsPoint(location, drawing: drawing, rect: rect, scaledStroke: scaledStroke) else {
                return
            }
            let additive = NSEvent.modifierFlags.contains(.shift)
            handleTap(drawing, additive: additive)
        }
    }

    private func shapeContainsPoint(
        _ point: CGPoint,
        drawing: CanvasDrawing,
        rect: CGRect,
        scaledStroke: CGFloat
    ) -> Bool {
        let kind = drawing.shapeKind ?? .rectangle
        let tolerance = max(Constants.hitTestWidth, scaledStroke + Constants.lineHitExpansion) / 2

        switch kind {
        case .line:
            let start = CGPoint(x: rect.minX, y: rect.minY)
            let end = CGPoint(x: rect.maxX, y: rect.maxY)
            return distanceToSegment(point: point, start: start, end: end) <= tolerance

        case .arrow:
            let start = CGPoint(x: rect.minX, y: rect.minY)
            let end = CGPoint(x: rect.maxX, y: rect.maxY)
            if distanceToSegment(point: point, start: start, end: end) <= tolerance {
                return true
            }

            let angle = atan2(end.y - start.y, end.x - start.x)
            let headLength: CGFloat = 16 * effectiveScale
            let headAngle: CGFloat = CGFloat.pi / 6
            let leftHead = CGPoint(
                x: end.x - headLength * cos(angle - headAngle),
                y: end.y - headLength * sin(angle - headAngle)
            )
            let rightHead = CGPoint(
                x: end.x - headLength * cos(angle + headAngle),
                y: end.y - headLength * sin(angle + headAngle)
            )
            return distanceToSegment(point: point, start: end, end: leftHead) <= tolerance ||
                distanceToSegment(point: point, start: end, end: rightHead) <= tolerance

        case .rectangle, .roundedRectangle:
            if drawing.fillColor != nil {
                let expanded = rect.insetBy(dx: -Constants.shapeHitPadding, dy: -Constants.shapeHitPadding)
                return expanded.contains(point)
            }
            let outer = rect.insetBy(dx: -tolerance, dy: -tolerance)
            let inner = rect.insetBy(dx: tolerance, dy: tolerance)
            if inner.width <= 0 || inner.height <= 0 {
                return outer.contains(point)
            }
            return outer.contains(point) && !inner.contains(point)

        case .circle:
            if drawing.fillColor != nil {
                let expanded = rect.insetBy(dx: -Constants.shapeHitPadding, dy: -Constants.shapeHitPadding)
                return ellipseContains(point: point, in: expanded)
            }
            let outer = rect.insetBy(dx: -tolerance, dy: -tolerance)
            let inner = rect.insetBy(dx: tolerance, dy: tolerance)
            let inOuter = ellipseContains(point: point, in: outer)
            if inner.width <= 0 || inner.height <= 0 {
                return inOuter
            }
            return inOuter && !ellipseContains(point: point, in: inner)

        case .triangle:
            let p1 = CGPoint(x: rect.midX, y: rect.minY)
            let p2 = CGPoint(x: rect.maxX, y: rect.maxY)
            let p3 = CGPoint(x: rect.minX, y: rect.maxY)

            if drawing.fillColor != nil {
                return pointInTriangle(point, p1, p2, p3)
            }
            return distanceToSegment(point: point, start: p1, end: p2) <= tolerance ||
                distanceToSegment(point: point, start: p2, end: p3) <= tolerance ||
                distanceToSegment(point: point, start: p3, end: p1) <= tolerance
        }
    }

    private func distanceToSegment(point: CGPoint, start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }
        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }

    private func ellipseContains(point: CGPoint, in rect: CGRect) -> Bool {
        guard rect.width > 0, rect.height > 0 else { return false }
        let nx = (point.x - rect.midX) / (rect.width / 2)
        let ny = (point.y - rect.midY) / (rect.height / 2)
        return (nx * nx) + (ny * ny) <= 1
    }

    private func pointInTriangle(_ point: CGPoint, _ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Bool {
        let d1 = signedArea(point, a, b)
        let d2 = signedArea(point, b, c)
        let d3 = signedArea(point, c, a)
        let hasNeg = (d1 < 0) || (d2 < 0) || (d3 < 0)
        let hasPos = (d1 > 0) || (d2 > 0) || (d3 > 0)
        return !(hasNeg && hasPos)
    }

    private func signedArea(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> CGFloat {
        (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)
    }

    @ViewBuilder
    private func rectangleShape(drawing: CanvasDrawing, rect: CGRect, strokeWidth: CGFloat) -> some View {
        let shape = Rectangle()
        ZStack {
            if let fill = drawing.fillSwiftUIColor {
                shape.fill(fill)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
            shape.stroke(drawing.strokeSwiftUIColor, lineWidth: strokeWidth)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
    }

    @ViewBuilder
    private func roundedRectangleShape(drawing: CanvasDrawing, rect: CGRect, strokeWidth: CGFloat) -> some View {
        let cornerRadius: CGFloat = 8 * effectiveScale
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if let fill = drawing.fillSwiftUIColor {
                shape.fill(fill)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
            shape.stroke(drawing.strokeSwiftUIColor, lineWidth: strokeWidth)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
    }

    @ViewBuilder
    private func ellipseShape(drawing: CanvasDrawing, rect: CGRect, strokeWidth: CGFloat) -> some View {
        let shape = Ellipse()
        ZStack {
            if let fill = drawing.fillSwiftUIColor {
                shape.fill(fill)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
            shape.stroke(drawing.strokeSwiftUIColor, lineWidth: strokeWidth)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
    }

    @ViewBuilder
    private func lineShape(drawing: CanvasDrawing, rect: CGRect, strokeWidth: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        .stroke(drawing.strokeSwiftUIColor, lineWidth: strokeWidth)
    }

    @ViewBuilder
    private func arrowShape(drawing: CanvasDrawing, rect: CGRect, strokeWidth: CGFloat) -> some View {
        let start = CGPoint(x: rect.minX, y: rect.minY)
        let end = CGPoint(x: rect.maxX, y: rect.maxY)

        // Filled arrowhead with larger size
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength: CGFloat = 16 * effectiveScale
        let headAngle: CGFloat = .pi / 6

        let leftTip = CGPoint(
            x: end.x - headLength * cos(angle - headAngle),
            y: end.y - headLength * sin(angle - headAngle)
        )
        let rightTip = CGPoint(
            x: end.x - headLength * cos(angle + headAngle),
            y: end.y - headLength * sin(angle + headAngle)
        )

        ZStack {
            // Shaft line
            Path { path in
                path.move(to: start)
                path.addLine(to: end)
            }
            .stroke(drawing.strokeSwiftUIColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))

            // Filled arrowhead
            Path { path in
                path.move(to: end)
                path.addLine(to: leftTip)
                path.addLine(to: rightTip)
                path.closeSubpath()
            }
            .fill(drawing.strokeSwiftUIColor)
        }
    }

    @ViewBuilder
    private func triangleShape(drawing: CanvasDrawing, rect: CGRect, strokeWidth: CGFloat) -> some View {
        let tri = Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
        ZStack {
            if let fill = drawing.fillSwiftUIColor {
                tri.fill(fill)
            }
            tri.stroke(drawing.strokeSwiftUIColor, lineWidth: strokeWidth)
        }
    }

    // MARK: - Text Layer

    private var textsLayer: some View {
        ForEach(drawingState.drawings.filter { $0.drawingType == .text }) { drawing in
            textView(for: drawing)
                .gesture(selectModeDragGesture(for: drawing))
        }
    }

    @ViewBuilder
    private func textView(for drawing: CanvasDrawing) -> some View {
        let weight = drawing.textWeight ?? .M
        let isEditing = drawingState.editingTextId == drawing.id
        let isSelected = drawingState.isSelected(drawing.id)
        let screenPos = canvasToScreenDragged(drawing.origin, drawingId: drawing.id)
        let scaledFontSize = weight.fontSize * effectiveScale

        Group {
            if isEditing {
                DrawingTextEditor(
                    drawingId: drawing.id,
                    drawingState: drawingState,
                    textWeight: weight,
                    strokeColor: drawing.strokeColor,
                    scaledFontSize: scaledFontSize
                )
            } else {
                Text(drawing.textContent ?? "")
                    .font(.system(size: scaledFontSize, weight: weight.fontWeight))
                    .foregroundColor(CanvasDrawing.colorFromHex(drawing.strokeColor))
                    .onTapGesture {
                        if drawingState.toolMode == .erase {
                            drawingState.deleteDrawing(drawing.id)
                        } else if drawingState.toolMode == .text {
                            drawingState.editingTextId = drawing.id
                        } else {
                            let additive = NSEvent.modifierFlags.contains(.shift)
                            handleTap(drawing, additive: additive)
                        }
                    }
                    .onTapGesture(count: 2) {
                        drawingState.editingTextId = drawing.id
                    }
            }
        }
        .position(x: screenPos.x, y: screenPos.y)
        .overlay {
            if isSelected && !isEditing {
                let rect = drawing.boundingRect
                let screenSize = scaleSize(rect.size)
                Rectangle()
                    .stroke(DS.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(width: screenSize.width + 8, height: screenSize.height + 8)
                    .position(x: screenPos.x, y: screenPos.y)
            }
        }
    }

    // MARK: - Freehand Hit Areas

    private var freehandHitLayer: some View {
        ForEach(drawingState.drawings.filter { $0.drawingType == .freehand }) { drawing in
            if let points = drawing.pathPoints, points.count > 1 {
                freehandHitArea(for: drawing, points: points)
                    .gesture(selectModeDragGesture(for: drawing))
            }
        }
    }

    @ViewBuilder
    private func freehandHitArea(for drawing: CanvasDrawing, points: [CGPoint]) -> some View {
        Path { path in
            let first = canvasToScreenDragged(points[0], drawingId: drawing.id)
            path.move(to: first)
            for i in 1..<points.count {
                let pt = canvasToScreenDragged(points[i], drawingId: drawing.id)
                path.addLine(to: pt)
            }
        }
        .strokedPath(StrokeStyle(lineWidth: Constants.hitTestWidth * effectiveScale, lineCap: .round))
        .fill(Color.white.opacity(0.001))
        .onTapGesture {
            let additive = NSEvent.modifierFlags.contains(.shift)
            handleTap(drawing, additive: additive)
        }
    }

    // MARK: - Shape Group Selection Overlay

    private var selectionOverlayLayer: some View {
        Group {
            if drawingState.toolMode == .select,
               let screenRect = selectedShapeScreenBounds {
                let padded = screenRect.insetBy(dx: -Constants.selectionPadding, dy: -Constants.selectionPadding)

                Rectangle()
                    .stroke(DS.accent.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(width: max(padded.width, 1), height: max(padded.height, 1))
                    .position(x: padded.midX, y: padded.midY)
                    .allowsHitTesting(false)

                ForEach(ShapeResizeCorner.allCases, id: \.self) { corner in
                    resizeHandle(corner: corner, in: padded)
                }
            }
        }
    }

    private var selectedShapeScreenBounds: CGRect? {
        let selectedShapes = drawingState.drawings.filter {
            $0.drawingType == .shape && drawingState.isSelected($0.id)
        }
        guard !selectedShapes.isEmpty else { return nil }

        let canvasBounds = selectedShapes
            .map(drawingRectWithDrag)
            .dropFirst()
            .reduce(drawingRectWithDrag(selectedShapes[0])) { partial, rect in
                partial.union(rect)
            }
        return canvasRectToScreen(canvasBounds)
    }

    @ViewBuilder
    private func resizeHandle(corner: ShapeResizeCorner, in rect: CGRect) -> some View {
        let point = resizeHandlePoint(for: corner, in: rect)

        Circle()
            .fill(DS.surfaceElevated)
            .frame(width: Constants.resizeHandleSize, height: Constants.resizeHandleSize)
            .overlay(
                Circle()
                    .stroke(DS.accent.opacity(0.9), lineWidth: 1.5)
            )
            .frame(width: Constants.resizeHandleHitSize, height: Constants.resizeHandleHitSize)
            .contentShape(Circle())
            .position(point)
            .gesture(groupResizeGesture(corner: corner))
    }

    private func resizeHandlePoint(for corner: ShapeResizeCorner, in rect: CGRect) -> CGPoint {
        switch corner {
        case .topLeft:
            return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight:
            return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft:
            return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight:
            return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    private func groupResizeGesture(corner: ShapeResizeCorner) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard drawingState.toolMode == .select else { return }
                drawingState.updateSelectedShapeResize(
                    corner: corner,
                    translation: CGSize(
                        width: value.translation.width / effectiveScale,
                        height: value.translation.height / effectiveScale
                    )
                )
            }
            .onEnded { _ in
                guard drawingState.toolMode == .select else { return }
                drawingState.finishSelectedShapeResize()
            }
    }

    // MARK: - Active Preview

    private var activePreviewLayer: some View {
        Group {
            if let active = drawingState.activeDrawing {
                switch active.drawingType {
                case .shape:
                    activeShapePreview(active)
                case .freehand:
                    activeFreehandPreview()
                case .text:
                    EmptyView()
                }
            }
        }
    }

    @ViewBuilder
    private func activeShapePreview(_ drawing: CanvasDrawing) -> some View {
        let rect = drawing.boundingRect
        let screenMin = canvasToScreen(rect.origin)
        let screenMax = canvasToScreen(CGPoint(x: rect.maxX, y: rect.maxY))
        let screenRect = CGRect(
            x: min(screenMin.x, screenMax.x),
            y: min(screenMin.y, screenMax.y),
            width: abs(screenMax.x - screenMin.x),
            height: abs(screenMax.y - screenMin.y)
        )
        let scaledStroke = drawing.strokeWidth * effectiveScale

        ZStack {
            switch drawing.shapeKind ?? .rectangle {
            case .rectangle:
                Rectangle()
                    .stroke(drawing.strokeSwiftUIColor.opacity(0.7), lineWidth: scaledStroke)
                    .frame(width: max(screenRect.width, 1), height: max(screenRect.height, 1))
                    .position(x: screenRect.midX, y: screenRect.midY)
            case .roundedRectangle:
                RoundedRectangle(cornerRadius: 8 * effectiveScale, style: .continuous)
                    .stroke(drawing.strokeSwiftUIColor.opacity(0.7), lineWidth: scaledStroke)
                    .frame(width: max(screenRect.width, 1), height: max(screenRect.height, 1))
                    .position(x: screenRect.midX, y: screenRect.midY)
            case .circle:
                Ellipse()
                    .stroke(drawing.strokeSwiftUIColor.opacity(0.7), lineWidth: scaledStroke)
                    .frame(width: max(screenRect.width, 1), height: max(screenRect.height, 1))
                    .position(x: screenRect.midX, y: screenRect.midY)
            case .line:
                Path { path in
                    path.move(to: CGPoint(x: screenRect.minX, y: screenRect.minY))
                    path.addLine(to: CGPoint(x: screenRect.maxX, y: screenRect.maxY))
                }
                .stroke(drawing.strokeSwiftUIColor.opacity(0.7), lineWidth: scaledStroke)
            case .arrow:
                arrowShape(drawing: drawing, rect: screenRect, strokeWidth: scaledStroke)
                    .opacity(0.7)
            case .triangle:
                Path { path in
                    path.move(to: CGPoint(x: screenRect.midX, y: screenRect.minY))
                    path.addLine(to: CGPoint(x: screenRect.maxX, y: screenRect.maxY))
                    path.addLine(to: CGPoint(x: screenRect.minX, y: screenRect.maxY))
                    path.closeSubpath()
                }
                .stroke(drawing.strokeSwiftUIColor.opacity(0.7), lineWidth: scaledStroke)
            }

            // Dimension label during shape creation
            if screenRect.width > 20 && screenRect.height > 20 {
                let canvasW = Int(screenRect.width / effectiveScale)
                let canvasH = Int(screenRect.height / effectiveScale)
                Text("\(canvasW) × \(canvasH)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(DS.textMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(DS.surfaceElevated.opacity(0.9))
                    )
                    .position(x: screenRect.midX, y: screenRect.maxY + 16)
            }
        }
    }

    @ViewBuilder
    private func activeFreehandPreview() -> some View {
        let points = drawingState.activePathPoints
        let widths = drawingState.activePathWidths
        if points.count > 1, let active = drawingState.activeDrawing {
            let screenPoints = points.map { canvasToScreen($0) }

            if widths.count == screenPoints.count {
                variableWidthStrokePath(points: screenPoints, widths: widths)
                    .fill(CanvasDrawing.colorFromHex(active.strokeColor))
            } else {
                smoothBezierPath(through: screenPoints)
                    .stroke(
                        CanvasDrawing.colorFromHex(active.strokeColor),
                        style: StrokeStyle(
                            lineWidth: active.strokeWidth * effectiveScale,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
            }
        }
    }

    // MARK: - Delete Button

    private var deleteButtonLayer: some View {
        Group {
            if drawingState.selectedDrawingIds.count == 1,
               let selectedId = drawingState.selectedDrawingIds.first,
               let drawing = drawingState.drawings.first(where: { $0.id == selectedId }) {
                drawingDeleteButton(for: drawing)
            }
        }
        .animation(ProMotionSprings.snappy, value: drawingState.selectedDrawingIds)
    }

    @ViewBuilder
    private func drawingDeleteButton(for drawing: CanvasDrawing) -> some View {
        let rect = drawing.boundingRect
        let drag = dragOffset(for: drawing.id)
        let center = CGPoint(x: rect.midX + drag.width, y: rect.midY + drag.height)
        let screenCenter = canvasToScreen(center)

        Button {
            withAnimation(ProMotionSprings.snappy) {
                drawingState.deleteDrawing(drawing.id)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                Text("Remove")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(DS.red)
                    .shadow(color: .black.opacity(0.15), radius: 6)
            )
        }
        .buttonStyle(.plain)
        .position(x: screenCenter.x, y: screenCenter.y - Constants.deleteButtonOffset)
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Drag-to-Move Gesture

    private func selectModeDragGesture(
        for drawing: CanvasDrawing,
        hitTest: ((CGPoint) -> Bool)? = nil
    ) -> some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                guard drawingState.toolMode == .select else { return }
                if drawingState.selectedDrawingIds.count > 1,
                   drawingState.isSelected(drawing.id) {
                    return
                }
                if drawingState.draggingDrawingId != drawing.id {
                    if let hitTest, !hitTest(value.startLocation) {
                        return
                    }
                    drawingState.beginDragDrawing(id: drawing.id)
                }
                // Convert screen-space translation to canvas-space
                drawingState.updateDragDrawing(translation: CGSize(
                    width: value.translation.width / effectiveScale,
                    height: value.translation.height / effectiveScale
                ))
            }
            .onEnded { _ in
                guard drawingState.toolMode == .select else { return }
                if drawingState.selectedDrawingIds.count > 1,
                   drawingState.isSelected(drawing.id) {
                    return
                }
                drawingState.finishDragDrawing()
            }
    }

    // MARK: - Tap Handling

    private func handleTap(_ drawing: CanvasDrawing, additive: Bool = false) {
        if drawingState.toolMode == .erase {
            withAnimation(ProMotionSprings.snappy) {
                drawingState.deleteDrawing(drawing.id)
            }
        } else {
            withAnimation(ProMotionSprings.snappy) {
                let allowAdditiveSelection = additive && drawing.drawingType == .shape
                drawingState.toggleSelection(drawing.id, additive: allowAdditiveSelection)
            }
        }
    }
}

// MARK: - Drawing Text Editor (inline TextField with @FocusState)

struct DrawingTextEditor: View {
    let drawingId: String
    @ObservedObject var drawingState: DrawingStateManager
    let textWeight: DrawingTextWeight
    let strokeColor: String
    var scaledFontSize: CGFloat? = nil

    @FocusState private var isFocused: Bool
    @State private var text: String = ""

    private var fontSize: CGFloat {
        scaledFontSize ?? textWeight.fontSize
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Custom placeholder that's always visible on any background
            if text.isEmpty {
                Text("Type...")
                    .font(.system(size: fontSize, weight: textWeight.fontWeight))
                    .foregroundColor(DS.textMuted.opacity(0.6))
                    .allowsHitTesting(false)
            }

            TextField("", text: $text)
                .font(.system(size: fontSize, weight: textWeight.fontWeight))
                .foregroundColor(CanvasDrawing.colorFromHex(strokeColor))
                .textFieldStyle(.plain)
                .focused($isFocused)
                .frame(minWidth: 80)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(DS.surfaceElevated.opacity(0.85))
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        )
        .onAppear {
            text = drawingState.drawings.first(where: { $0.id == drawingId })?.textContent ?? ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFocused = true
            }
        }
        .onChange(of: text) { _, newValue in
            drawingState.updateTextContent(drawingId, content: newValue)
        }
        .onChange(of: isFocused) { _, focused in
            if !focused {
                drawingState.finishTextEditing(drawingId)
                // Auto-switch to select after placing text
                drawingState.toolMode = .select
            }
        }
        .onSubmit {
            drawingState.finishTextEditing(drawingId)
            drawingState.toolMode = .select
        }
    }
}
