// CosmoOS/Canvas/Drawing/CanvasDrawingsLayer.swift
// Rendering layer for all canvas drawing elements
// Lives OUTSIDE the scaled ZStack — renders in screen coordinates to prevent clipping

import SwiftUI

struct CanvasDrawingsLayer: View {
    @ObservedObject var drawingState: DrawingStateManager
    var canvasOffset: CGSize = .zero
    var scaledPanOffset: CGSize = .zero
    var effectiveScale: CGFloat = 1.0
    var screenCenter: CGPoint = .zero

    // MARK: - Constants

    private enum Constants {
        static let hitTestWidth: CGFloat = 20
        static let deleteButtonOffset: CGFloat = 20
    }

    // MARK: - Coordinate Conversion

    /// Convert a canvas-space point to screen-space for rendering
    private func canvasToScreen(_ p: CGPoint) -> CGPoint {
        let ox = p.x + canvasOffset.width + scaledPanOffset.width
        let oy = p.y + canvasOffset.height + scaledPanOffset.height
        return CGPoint(
            x: screenCenter.x + (ox - screenCenter.x) * effectiveScale,
            y: screenCenter.y + (oy - screenCenter.y) * effectiveScale
        )
    }

    /// Scale a canvas-space size to screen-space
    private func scaleSize(_ s: CGSize) -> CGSize {
        CGSize(width: s.width * effectiveScale, height: s.height * effectiveScale)
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

    // MARK: - Body

    var body: some View {
        ZStack {
            // 1. Freehand strokes — individual Path views (not Canvas, to avoid frame clipping)
            freehandLayer
                .allowsHitTesting(false)

            // 2. Shape views
            shapesLayer

            // 3. Text views
            textsLayer

            // 4. Freehand hit areas (invisible fat paths for tap detection)
            freehandHitLayer

            // 5. Active drawing preview (in-progress shape or freehand)
            activePreviewLayer
                .allowsHitTesting(false)

            // 6. Delete button for selected element
            deleteButtonLayer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Freehand Layer (Path views — no frame clipping)

    private var freehandLayer: some View {
        ForEach(drawingState.drawings.filter { $0.drawingType == .freehand }) { drawing in
            if let points = drawing.pathPoints, points.count > 1 {
                freehandStroke(for: drawing, points: points)
            }
        }
    }

    @ViewBuilder
    private func freehandStroke(for drawing: CanvasDrawing, points: [CGPoint]) -> some View {
        Path { path in
            let first = canvasToScreenDragged(points[0], drawingId: drawing.id)
            path.move(to: first)
            for i in 1..<points.count {
                let pt = canvasToScreenDragged(points[i], drawingId: drawing.id)
                path.addLine(to: pt)
            }
        }
        .stroke(
            CanvasDrawing.colorFromHex(drawing.strokeColor),
            style: StrokeStyle(
                lineWidth: drawing.strokeWidth * effectiveScale,
                lineCap: .round,
                lineJoin: .round
            )
        )
        .opacity(drawing.opacity)
    }

    // MARK: - Shapes Layer

    private var shapesLayer: some View {
        ForEach(drawingState.drawings.filter { $0.drawingType == .shape }) { drawing in
            shapeView(for: drawing)
                .gesture(selectModeDragGesture(for: drawing))
                .onTapGesture {
                    handleTap(drawing)
                }
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
        let isSelected = drawingState.selectedDrawingId == drawing.id
        let scaledStroke = drawing.strokeWidth * effectiveScale

        Group {
            switch drawing.shapeKind ?? .rectangle {
            case .rectangle:
                rectangleShape(drawing: drawing, rect: screenRect, strokeWidth: scaledStroke)
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
        .opacity(drawing.opacity)
        .overlay {
            if isSelected {
                Rectangle()
                    .stroke(Color.blue.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(width: screenRect.width + 8, height: screenRect.height + 8)
                    .position(x: screenRect.midX, y: screenRect.midY)
            }
        }
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

        Path { path in
            path.move(to: start)
            path.addLine(to: end)

            // Arrowhead
            let angle = atan2(end.y - start.y, end.x - start.x)
            let headLength: CGFloat = 12 * effectiveScale
            let headAngle: CGFloat = .pi / 6
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
        .stroke(drawing.strokeSwiftUIColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
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
        let isSelected = drawingState.selectedDrawingId == drawing.id
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
                            handleTap(drawing)
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
                    .stroke(Color.blue.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
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
            handleTap(drawing)
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

        switch drawing.shapeKind ?? .rectangle {
        case .rectangle:
            Rectangle()
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
    }

    @ViewBuilder
    private func activeFreehandPreview() -> some View {
        let points = drawingState.activePathPoints
        if points.count > 1, let active = drawingState.activeDrawing {
            Path { path in
                let first = canvasToScreen(points[0])
                path.move(to: first)
                for i in 1..<points.count {
                    path.addLine(to: canvasToScreen(points[i]))
                }
            }
            .stroke(
                CanvasDrawing.colorFromHex(active.strokeColor).opacity(0.8),
                style: StrokeStyle(
                    lineWidth: active.strokeWidth * effectiveScale,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
    }

    // MARK: - Delete Button

    private var deleteButtonLayer: some View {
        Group {
            if let selectedId = drawingState.selectedDrawingId,
               let drawing = drawingState.drawings.first(where: { $0.id == selectedId }) {
                drawingDeleteButton(for: drawing)
            }
        }
        .animation(ProMotionSprings.snappy, value: drawingState.selectedDrawingId)
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
                    .fill(Color.red.opacity(0.8))
                    .shadow(color: .black.opacity(0.4), radius: 6)
            )
        }
        .buttonStyle(.plain)
        .position(x: screenCenter.x, y: screenCenter.y - Constants.deleteButtonOffset)
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Drag-to-Move Gesture

    private func selectModeDragGesture(for drawing: CanvasDrawing) -> some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                guard drawingState.toolMode == .select else { return }
                if drawingState.draggingDrawingId != drawing.id {
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
                drawingState.finishDragDrawing()
            }
    }

    // MARK: - Tap Handling

    private func handleTap(_ drawing: CanvasDrawing) {
        if drawingState.toolMode == .erase {
            withAnimation(ProMotionSprings.snappy) {
                drawingState.deleteDrawing(drawing.id)
            }
        } else {
            withAnimation(ProMotionSprings.snappy) {
                if drawingState.selectedDrawingId == drawing.id {
                    drawingState.selectedDrawingId = nil
                } else {
                    drawingState.selectedDrawingId = drawing.id
                }
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
        TextField("Type here...", text: $text)
            .font(.system(size: fontSize, weight: textWeight.fontWeight))
            .foregroundColor(CanvasDrawing.colorFromHex(strokeColor))
            .textFieldStyle(.plain)
            .focused($isFocused)
            .frame(minWidth: 60)
            .fixedSize()
            .onAppear {
                text = drawingState.drawings.first(where: { $0.id == drawingId })?.textContent ?? ""
                isFocused = true
            }
            .onChange(of: text) { _, newValue in
                drawingState.updateTextContent(drawingId, content: newValue)
            }
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    drawingState.finishTextEditing(drawingId)
                }
            }
            .onSubmit {
                drawingState.finishTextEditing(drawingId)
            }
    }
}
