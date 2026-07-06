import AppKit
import SwiftUI

/// A freehand drawing board inside a note. Rendered with SwiftUI `Canvas`
/// (Catmull-Rom smoothed); click to enter drawing mode — a floating tool
/// capsule offers pen / highlighter / eraser, four inks, and three widths.
/// Every completed stroke is one document commit (one undo step). Strokes
/// are portable JSON (`RichSketchDrawing`), never PencilKit archives.
struct SketchBlockView: View {
    @Binding var block: RichBlock

    var darkMode: Bool = false
    var onSketchChange: (() -> Void)? = nil

    @State private var isEditing = false
    @State private var liveStroke: RichSketchStroke?
    @State private var tool: SketchTool = .pen
    @State private var inkID: String = "ink"
    @State private var strokeWidth: Double = 2.5
    @State private var isHovered = false
    @State private var resizeStartHeight: Double?

    private enum SketchTool: Equatable {
        case pen
        case highlighter
        case eraser
    }

    private var drawing: RichSketchDrawing {
        block.sketch ?? RichSketchDrawing()
    }

    var body: some View {
        canvasSurface
            .frame(height: drawing.height)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(paperFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .overlay(alignment: .top) {
                if isEditing {
                    toolCapsule
                        .padding(.top, DS.space6)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                }
            }
            .overlay(alignment: .bottom) {
                if isEditing || isHovered {
                    resizeGrip
                        .transition(.opacity)
                }
            }
            .onHover { isHovered = $0 }
            .animation(ProMotionSprings.snappy, value: isEditing)
            .onKeyPress(.escape) {
                guard isEditing else { return .ignored }
                isEditing = false
                return .handled
            }
    }

    // MARK: - Canvas

    private var canvasSurface: some View {
        Canvas { context, _ in
            for stroke in drawing.strokes {
                draw(stroke, in: &context)
            }
            if let liveStroke {
                draw(liveStroke, in: &context)
            }
        }
        .clipShape(.rect(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .gesture(isEditing ? drawGesture : nil)
        .onTapGesture {
            if !isEditing {
                isEditing = true
            }
        }
        .accessibilityLabel(drawing.strokes.isEmpty ? "Empty sketch" : "Sketch with \(drawing.strokes.count) strokes")
        .accessibilityAddTraits(.isButton)
        .overlay {
            if drawing.strokes.isEmpty, !isEditing {
                Text("Click to sketch")
                    .font(DS.subheadline)
                    .foregroundStyle(mutedColor)
                    .allowsHitTesting(false)
            }
        }
    }

    private func draw(_ stroke: RichSketchStroke, in context: inout GraphicsContext) {
        guard stroke.points.count > 1 else {
            if let only = stroke.points.first {
                let dot = Path(ellipseIn: CGRect(
                    x: only.x - stroke.width / 2, y: only.y - stroke.width / 2,
                    width: stroke.width, height: stroke.width
                ))
                context.fill(dot, with: .color(color(for: stroke)))
            }
            return
        }
        let path = SketchGeometry.smoothedPath(for: stroke.points)
        context.stroke(
            path,
            with: .color(color(for: stroke)),
            style: StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round)
        )
    }

    private func color(for stroke: RichSketchStroke) -> Color {
        let base: Color
        if stroke.inkID == "ink" {
            base = darkMode ? DS.focusImmersiveText : DS.documentText
        } else {
            base = NoteInkPalette.tone(stroke.inkID).ink(darkMode: darkMode)
        }
        return stroke.isHighlighter ? base.opacity(0.35) : base
    }

    // MARK: - Drawing gesture

    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = RichSketchPoint(x: value.location.x, y: value.location.y)
                switch tool {
                case .eraser:
                    eraseStrokes(near: point)
                case .pen, .highlighter:
                    if liveStroke == nil {
                        liveStroke = RichSketchStroke(
                            points: [point],
                            width: tool == .highlighter ? strokeWidth * 4 : strokeWidth,
                            inkID: inkID,
                            isHighlighter: tool == .highlighter
                        )
                    } else {
                        liveStroke?.points.append(point)
                    }
                }
            }
            .onEnded { _ in
                guard let stroke = liveStroke else { return }
                liveStroke = nil
                var updated = drawing
                updated.strokes.append(stroke)
                commit(updated)
            }
    }

    private func eraseStrokes(near point: RichSketchPoint) {
        let radius: Double = 12
        var updated = drawing
        let before = updated.strokes.count
        updated.strokes.removeAll { stroke in
            stroke.points.contains { hypot($0.x - point.x, $0.y - point.y) < radius }
        }
        if updated.strokes.count != before {
            commit(updated)
        }
    }

    private func commit(_ updated: RichSketchDrawing) {
        block.sketch = updated
        onSketchChange?()
    }

    // MARK: - Tool capsule

    private var toolCapsule: some View {
        HStack(spacing: DS.space8) {
            toolButton(.pen, icon: "pencil.tip", help: "Pen")
            toolButton(.highlighter, icon: "highlighter", help: "Highlighter")
            toolButton(.eraser, icon: "eraser", help: "Eraser")
            capsuleDivider
            inkDot("ink", color: darkMode ? DS.focusImmersiveText : DS.documentText)
            ForEach(["moss", "clay", "slate"], id: \.self) { id in
                inkDot(id, color: NoteInkPalette.tone(id).ink(darkMode: darkMode))
            }
            capsuleDivider
            widthButton(1.5, help: "Fine")
            widthButton(2.5, help: "Medium")
            widthButton(4.5, help: "Broad")
            capsuleDivider
            Button {
                isEditing = false
            } label: {
                Text("Done")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.accent)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Finish sketching (Esc)")
            .accessibilityLabel("Finish sketching")
        }
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space6)
        .background(Capsule().fill(capsuleFill))
        .overlay(Capsule().strokeBorder(borderColor, lineWidth: 1))
    }

    private var capsuleDivider: some View {
        Rectangle()
            .fill(borderColor)
            .frame(width: 1, height: 14)
    }

    private func toolButton(_ target: SketchTool, icon: String, help: String) -> some View {
        let isSelected = tool == target
        return Button {
            tool = target
        } label: {
            Image(systemName: icon)
                .font(DS.caption.weight(.medium))
                .foregroundStyle(isSelected ? DS.accent : mutedColor)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? DS.accentSoft : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func inkDot(_ id: String, color: Color) -> some View {
        let isSelected = inkID == id && tool != .eraser
        return Button {
            inkID = id
            if tool == .eraser { tool = .pen }
        } label: {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .strokeBorder(isSelected ? color.opacity(0.45) : Color.clear, lineWidth: 2)
                        .padding(-3)
                )
                .frame(width: 20, height: 20)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(id == "ink" ? "Ink" : NoteInkPalette.tone(id).label)
        .accessibilityLabel(id == "ink" ? "Ink color" : "\(NoteInkPalette.tone(id).label) color")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func widthButton(_ width: Double, help: String) -> some View {
        let isSelected = strokeWidth == width
        return Button {
            strokeWidth = width
        } label: {
            Circle()
                .fill(isSelected ? DS.accent : mutedColor)
                .frame(width: 3 + width, height: 3 + width)
                .frame(width: 20, height: 20)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel("\(help) stroke")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Resize grip

    private var resizeGrip: some View {
        Capsule()
            .fill(mutedColor.opacity(0.6))
            .frame(width: 36, height: 4)
            .padding(.vertical, DS.space4)
            .contentShape(Rectangle().size(CGSize(width: 80, height: 16)))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if resizeStartHeight == nil {
                            resizeStartHeight = drawing.height
                        }
                        guard let start = resizeStartHeight else { return }
                        var updated = drawing
                        updated.height = min(
                            RichSketchDrawing.maxHeight,
                            max(RichSketchDrawing.minHeight, start + value.translation.height)
                        )
                        block.sketch = updated
                    }
                    .onEnded { _ in
                        resizeStartHeight = nil
                        onSketchChange?()
                    }
            )
            .help("Drag to resize")
            .accessibilityLabel("Resize sketch")
    }

    // MARK: - Colors

    private var paperFill: Color {
        darkMode ? Color.white.opacity(0.045) : Color.white.opacity(0.55)
    }

    private var borderColor: Color {
        darkMode ? Color.white.opacity(0.10) : DS.documentBorderSubtle
    }

    private var mutedColor: Color {
        darkMode ? DS.focusImmersiveTextMuted : DS.documentTextMuted
    }

    private var capsuleFill: Color {
        darkMode ? Color(hex: "232323") : DS.documentBackground
    }
}

/// Pure stroke geometry — Catmull-Rom smoothing shared by the editor and the
/// read-only renderer, unit-testable in isolation.
enum SketchGeometry {
    static func smoothedPath(for points: [RichSketchPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.x, y: first.y))
        guard points.count > 2 else {
            for point in points.dropFirst() {
                path.addLine(to: CGPoint(x: point.x, y: point.y))
            }
            return path
        }

        // Catmull-Rom → cubic Bézier: each segment's control points come
        // from its neighbors, giving pen-like curvature through every point.
        for index in 0..<(points.count - 1) {
            let p0 = points[max(0, index - 1)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(points.count - 1, index + 2)]

            let control1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let control2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )
            path.addCurve(to: CGPoint(x: p2.x, y: p2.y), control1: control1, control2: control2)
        }
        return path
    }
}
