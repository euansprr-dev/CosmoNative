// CosmoOS/Canvas/Drawing/CanvasDrawingToolbar.swift
// Drawing toolbar with stroke width picker, enhanced color/style panel, and tool polish

import SwiftUI

struct CanvasDrawingToolbar: View {
    var drawingState: DrawingStateManager
    @State private var showStylePanel = false
    @State private var toolsVisible = true
    @State private var customColor: Color = .black

    // Tool items in display order (right-to-left when collapsed).
    // Tools with sub-modes show the selected sub-mode as their icon.
    private var toolItems: [(CanvasToolMode, String, String)] {
        [
            (.select, "cursorarrow", "Select (V)"),
            (.lasso, drawingState.currentLassoSubMode == .zone ? "rectangle.dashed" : "lasso", "Lasso (L)"),
            (.shape, shapeIcon(drawingState.currentShapeKind), "Shape (S)"),
            (.draw, "pencil.tip", "Draw (D)"),
            (.text, "textformat", "Text (T)"),
            (.erase, "eraser", "Erase (E)"),
        ]
    }

    // MARK: - Fixed metrics (dropdown anchoring depends on these)

    private let toolButtonWidth: CGFloat = 28
    private let toolRowHeight: CGFloat = 28
    private let gripWidth: CGFloat = 20
    private let dropdownWidth: CGFloat = 36

    // MARK: - Preset Colors (expanded to 12)

    private let presetColors: [(String, Color)] = [
        ("#1A1A1A", Color(red: 0.1, green: 0.1, blue: 0.1)),
        ("#FFFFFF", .white),
        ("#9CA3AF", Color(red: 0.61, green: 0.64, blue: 0.69)),
        ("#FF3B30", Color(red: 1.0, green: 0.23, blue: 0.19)),
        ("#C2410C", Color(red: 0.76, green: 0.25, blue: 0.05)),
        ("#FF9500", Color(red: 1.0, green: 0.58, blue: 0.0)),
        ("#FFCC00", Color(red: 1.0, green: 0.8, blue: 0.0)),
        ("#34C759", Color(red: 0.2, green: 0.78, blue: 0.35)),
        ("#0D9488", Color(red: 0.05, green: 0.58, blue: 0.53)),
        ("#00C7BE", Color(red: 0.0, green: 0.78, blue: 0.75)),
        ("#007AFF", Color(red: 0.0, green: 0.48, blue: 1.0)),
        ("#AF52DE", Color(red: 0.69, green: 0.32, blue: 0.87)),
    ]

    // MARK: - Stroke Width Presets

    private let strokePresets: [(String, CGFloat)] = [
        ("Thin", 1.0),
        ("Medium", 2.5),
        ("Thick", 4.0),
        ("Heavy", 6.0),
    ]

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            // Tool icons + style button
            toolRow

            // Divider grip handle (clickable toggle)
            dividerToggle
        }
        // Sub-tool pickers drop DOWN below the active tool button; the overlay
        // doesn't affect toolbar layout, it floats over the canvas.
        .overlay(alignment: .topTrailing) {
            secondaryDropdown
        }
    }

    // MARK: - Tool Row

    private var toolRow: some View {
        HStack(spacing: 0) {
            // Style dot (opens style panel)
            styleButton
                .drawingToolReveal(
                    visible: toolsVisible,
                    index: toolItems.count,
                    total: toolItems.count + 1
                )

            // Tool buttons
            ForEach(Array(toolItems.enumerated()), id: \.offset) { index, item in
                let (mode, icon, tooltip) = item
                toolIcon(mode, icon: icon, tooltip: tooltip)
                    .drawingToolReveal(
                        visible: toolsVisible,
                        index: toolItems.count - 1 - index,
                        total: toolItems.count + 1
                    )
            }
        }
        .clipped()
    }

    // MARK: - Tool Icon (with active highlight + tooltip)

    private func toolIcon(_ mode: CanvasToolMode, icon: String, tooltip: String) -> some View {
        Button {
            withAnimation(ProMotionSprings.snappy) {
                if drawingState.toolMode == mode {
                    drawingState.toolMode = .select
                } else {
                    drawingState.toolMode = mode
                }
                drawingState.clearSelection()
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(drawingState.toolMode == mode ? DS.text : DS.textMuted)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(drawingState.toolMode == mode ? DS.accent.opacity(0.12) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    // MARK: - Style Button (color dot → opens style panel)

    private var styleButton: some View {
        Button {
            showStylePanel.toggle()
        } label: {
            ZStack {
                Circle()
                    .fill(CanvasDrawing.themeResolvedColorFromHex(drawingState.currentStrokeColor))
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle().stroke(DS.textMuted.opacity(0.5), lineWidth: 1)
                    )

                // Inner fill indicator if fill is active
                if drawingState.currentFillColor != nil {
                    Circle()
                        .fill(CanvasDrawing.themeResolvedColorFromHex(drawingState.currentFillColor!))
                        .frame(width: 6, height: 6)
                }
            }
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showStylePanel, arrowEdge: .bottom) {
            stylePanel
        }
    }

    // MARK: - Divider Toggle (grip handle)

    private var dividerToggle: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                toolsVisible.toggle()
            }
        } label: {
            VStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(DS.textMuted.opacity(0.35))
                        .frame(width: 3, height: 3)
                }
            }
            .frame(width: gripWidth, height: toolRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Secondary Dropdown (drops below the active tool button)

    /// Enumerated toolItems index of the active tool, when it has sub-options.
    private var activeDropdownIndex: Int? {
        guard [.shape, .draw, .text, .lasso].contains(drawingState.toolMode) else { return nil }
        return toolItems.firstIndex { $0.0 == drawingState.toolMode }
    }

    /// Distance from the toolbar's trailing edge to the center of the tool button
    /// at `index`. All widths are fixed, so this is pure arithmetic.
    private func trailingDistanceToButtonCenter(_ index: Int) -> CGFloat {
        gripWidth + CGFloat(toolItems.count - 1 - index) * toolButtonWidth + toolButtonWidth / 2
    }

    @ViewBuilder
    private var secondaryDropdown: some View {
        Group {
            if toolsVisible, let index = activeDropdownIndex {
                dropdownContent
                    .padding(4)
                    .frame(width: dropdownWidth)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(CosmoColors.thinkspaceTertiary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(DS.textMuted.opacity(0.15), lineWidth: 1)
                    )
                    .offset(
                        x: -(trailingDistanceToButtonCenter(index) - dropdownWidth / 2),
                        y: toolRowHeight + 6
                    )
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .animation(ProMotionSprings.snappy, value: drawingState.toolMode)
        .animation(ProMotionSprings.snappy, value: toolsVisible)
    }

    @ViewBuilder
    private var dropdownContent: some View {
        VStack(spacing: 2) {
            switch drawingState.toolMode {
            case .shape:
                shapeColumn
                dropdownDivider
                strokeWidthColumn
            case .draw:
                strokeWidthColumn
            case .text:
                weightColumn
            case .lasso:
                lassoColumn
            default:
                EmptyView()
            }
        }
    }

    private var dropdownDivider: some View {
        Rectangle()
            .fill(DS.textMuted.opacity(0.25))
            .frame(width: 12, height: 1)
            .padding(.vertical, 3)
    }

    // MARK: - Dropdown Columns

    private var shapeColumn: some View {
        ForEach(ShapeKind.allCases, id: \.self) { kind in
            dropdownIconButton(
                icon: shapeIcon(kind),
                isSelected: drawingState.currentShapeKind == kind,
                tooltip: shapeTooltip(kind)
            ) {
                drawingState.currentShapeKind = kind
            }
        }
    }

    private var strokeWidthColumn: some View {
        ForEach(strokePresets, id: \.1) { name, width in
            Button {
                drawingState.currentStrokeWidth = width
            } label: {
                let isSelected = drawingState.currentStrokeWidth == width
                RoundedRectangle(cornerRadius: width / 2)
                    .fill(isSelected ? DS.text : DS.textMuted.opacity(0.6))
                    .frame(width: 14, height: max(width, 1))
                    .frame(width: 28, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isSelected ? DS.accent.opacity(0.1) : Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(name)
        }
    }

    private var weightColumn: some View {
        ForEach(DrawingTextWeight.allCases, id: \.self) { weight in
            Button {
                drawingState.currentTextWeight = weight
            } label: {
                let isSelected = drawingState.currentTextWeight == weight
                Text(weight.rawValue)
                    .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                    .foregroundColor(isSelected ? DS.text : DS.textMuted)
                    .frame(width: 28, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isSelected ? DS.accent.opacity(0.1) : Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var lassoColumn: some View {
        dropdownIconButton(
            icon: "lasso",
            isSelected: drawingState.currentLassoSubMode == .lasso,
            tooltip: "Freeform Lasso"
        ) {
            drawingState.currentLassoSubMode = .lasso
        }

        dropdownIconButton(
            icon: "rectangle.dashed",
            isSelected: drawingState.currentLassoSubMode == .zone,
            tooltip: "Zone Select"
        ) {
            drawingState.currentLassoSubMode = .zone
        }
    }

    private func dropdownIconButton(
        icon: String,
        isSelected: Bool,
        tooltip: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(isSelected ? DS.text : DS.textMuted)
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? DS.accent.opacity(0.1) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    // MARK: - Style Panel (replaces basic color picker)

    private var stylePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section: Stroke
            styleSectionHeader("Stroke")

            strokeColorGrid

            // Section: Fill
            styleSectionHeader("Fill")

            fillSection

            Divider().opacity(0.2)

            // Section: Opacity
            opacitySection

            Divider().opacity(0.2)

            // Custom color picker
            customColorSection
        }
        .padding(14)
        .frame(width: 190)
        .background(CosmoColors.thinkspaceTertiary)
    }

    private func styleSectionHeader(_ title: String) -> some View {
        Text(title)
            .dsSmallCapsLabel()
    }

    private var strokeColorGrid: some View {
        VStack(spacing: 6) {
            // Recent colors row
            if !drawingState.recentColors.isEmpty {
                HStack(spacing: 4) {
                    ForEach(drawingState.recentColors.prefix(4), id: \.self) { hex in
                        colorDot(hex: hex, isStroke: true, size: 18)
                    }
                    Spacer()
                }
            }

            // Main color grid (4×3)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 6), count: 4), spacing: 6) {
                ForEach(presetColors, id: \.0) { hex, _ in
                    colorDot(hex: hex, isStroke: true, size: 24)
                }
            }
        }
    }

    @ViewBuilder
    private func colorDot(hex: String, isStroke: Bool, size: CGFloat) -> some View {
        let isSelected = isStroke
            ? drawingState.currentStrokeColor == hex
            : drawingState.currentFillColor == hex

        Button {
            if isStroke {
                drawingState.currentStrokeColor = hex
                drawingState.trackRecentColor(hex)
            } else {
                drawingState.currentFillColor = hex
            }
        } label: {
            Circle()
                .fill(CanvasDrawing.colorFromHex(hex))
                .frame(width: size, height: size)
                .overlay(
                    Circle().stroke(
                        hex == "#FFFFFF" ? DS.textMuted.opacity(0.3) : Color.clear,
                        lineWidth: 1
                    )
                )
                .overlay(
                    Circle().stroke(
                        isSelected ? DS.accent : Color.clear,
                        lineWidth: 2
                    )
                    .frame(width: size + 4, height: size + 4)
                )
        }
        .buttonStyle(.plain)
    }

    private var fillSection: some View {
        VStack(spacing: 6) {
            HStack {
                Toggle("", isOn: Binding(
                    get: { drawingState.currentFillColor != nil },
                    set: { enabled in
                        drawingState.currentFillColor = enabled ? drawingState.currentStrokeColor : nil
                    }
                ))
                .toggleStyle(.switch)
                .scaleEffect(0.65)
                .labelsHidden()

                Text(drawingState.currentFillColor != nil ? "On" : "Off")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.textSecondary)

                Spacer()

                if let fill = drawingState.currentFillColor {
                    Circle()
                        .fill(CanvasDrawing.themeResolvedColorFromHex(fill))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(DS.textMuted.opacity(0.3), lineWidth: 1))
                }
            }

            // Fill color grid when enabled
            if drawingState.currentFillColor != nil {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(20), spacing: 4), count: 6), spacing: 4) {
                    ForEach(presetColors.prefix(12), id: \.0) { hex, _ in
                        colorDot(hex: hex, isStroke: false, size: 18)
                    }
                }
            }
        }
    }

    private var opacitySection: some View {
        HStack(spacing: 8) {
            Text("Opacity")
                .dsSmallCapsLabel()

            // Simple discrete opacity buttons
            ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { value in
                Button {
                    // Apply opacity to all selected drawings
                    for id in drawingState.selectedDrawingIds {
                        if let idx = drawingState.drawings.firstIndex(where: { $0.id == id }) {
                            drawingState.drawings[idx].opacity = value
                            drawingState.saveDrawing(drawingState.drawings[idx])
                        }
                    }
                } label: {
                    Text("\(Int(value * 100))")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(DS.textSecondary)
                        .frame(width: 28, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(DS.surfaceElevated.opacity(0.6))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var customColorSection: some View {
        HStack {
            Text("Custom")
                .dsSmallCapsLabel()

            Spacer()

            ColorPicker("", selection: $customColor, supportsOpacity: false)
                .labelsHidden()
                .scaleEffect(0.8)
                .onChange(of: customColor) { _, newColor in
                    let hex = hexFromColor(newColor)
                    drawingState.currentStrokeColor = hex
                    drawingState.trackRecentColor(hex)
                }
        }
    }

    // MARK: - Helpers

    private func shapeIcon(_ kind: ShapeKind) -> String {
        switch kind {
        case .rectangle: return "rectangle"
        case .roundedRectangle: return "rectangle.roundedtop"
        case .circle: return "circle"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .triangle: return "triangle"
        }
    }

    private func shapeTooltip(_ kind: ShapeKind) -> String {
        switch kind {
        case .rectangle: return "Rectangle"
        case .roundedRectangle: return "Rounded Rectangle"
        case .circle: return "Circle"
        case .line: return "Line"
        case .arrow: return "Arrow"
        case .triangle: return "Triangle"
        }
    }

    private func hexFromColor(_ color: Color) -> String {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        let r = Int(nsColor.redComponent * 255)
        let g = Int(nsColor.greenComponent * 255)
        let b = Int(nsColor.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Staggered Reveal Modifier

/// Animates a tool item sliding in/out horizontally with staggered timing.
/// Items collapse to the right (toward the divider) one by one.
private struct DrawingToolRevealModifier: ViewModifier {
    let visible: Bool
    let index: Int
    let total: Int

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(x: visible ? 0 : CGFloat((total - index)) * 14)
            .scaleEffect(visible ? 1 : 0.3, anchor: .trailing)
            .animation(
                .spring(response: 0.35, dampingFraction: 0.75)
                    .delay(visible ? Double(total - 1 - index) * 0.03 : Double(index) * 0.03),
                value: visible
            )
    }
}

extension View {
    fileprivate func drawingToolReveal(visible: Bool, index: Int, total: Int) -> some View {
        modifier(DrawingToolRevealModifier(visible: visible, index: index, total: total))
    }
}
