// CosmoOS/Canvas/Drawing/CanvasDrawingToolbar.swift
// Minimal icon toolbar for canvas drawing tools — sits left of the settings cog

import SwiftUI

struct CanvasDrawingToolbar: View {
    @ObservedObject var drawingState: DrawingStateManager
    @State private var showColorPicker = false
    @State private var toolsVisible = true

    // Tool items in display order (right-to-left when collapsed)
    private var toolItems: [(CanvasToolMode, String)] {
        [
            (.select, "cursorarrow"),
            (.shape, "square"),
            (.draw, "pencil.tip"),
            (.text, "textformat"),
            (.erase, "eraser"),
        ]
    }

    // MARK: - Preset Colors

    private let presetColors: [(String, Color)] = [
        ("#FFFFFF", .white),
        ("#FF3B30", Color(red: 1.0, green: 0.23, blue: 0.19)),
        ("#FF9500", Color(red: 1.0, green: 0.58, blue: 0.0)),
        ("#FFCC00", Color(red: 1.0, green: 0.8, blue: 0.0)),
        ("#34C759", Color(red: 0.2, green: 0.78, blue: 0.35)),
        ("#00C7BE", Color(red: 0.0, green: 0.78, blue: 0.75)),
        ("#007AFF", Color(red: 0.0, green: 0.48, blue: 1.0)),
        ("#AF52DE", Color(red: 0.69, green: 0.32, blue: 0.87)),
    ]

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            // Secondary picker (shape/weight) — appears further left
            secondaryPicker

            // Tool icons + color/width
            toolRow

            // Divider line (clickable toggle)
            dividerToggle
        }
    }

    // MARK: - Tool Row

    private var toolRow: some View {
        HStack(spacing: 0) {
            // Color dot
            colorButton
                .drawingToolReveal(
                    visible: toolsVisible,
                    index: toolItems.count + 1,
                    total: toolItems.count + 2
                )

            // Width buttons
            widthButtons
                .drawingToolReveal(
                    visible: toolsVisible,
                    index: toolItems.count,
                    total: toolItems.count + 2
                )

            // Tool buttons (select, shape, draw, text, erase)
            ForEach(Array(toolItems.enumerated()), id: \.offset) { index, item in
                let (mode, icon) = item
                toolIcon(mode, icon: icon)
                    .drawingToolReveal(
                        visible: toolsVisible,
                        index: toolItems.count - 1 - index,
                        total: toolItems.count + 2
                    )
            }
        }
        .clipped()
    }

    // MARK: - Tool Icon

    private func toolIcon(_ mode: CanvasToolMode, icon: String) -> some View {
        Button {
            withAnimation(ProMotionSprings.snappy) {
                if drawingState.toolMode == mode {
                    // Tapping active tool deselects to select mode
                    drawingState.toolMode = .select
                } else {
                    drawingState.toolMode = mode
                }
                drawingState.selectedDrawingId = nil
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(drawingState.toolMode == mode ? .white : DS.textMuted)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Color Button

    private var colorButton: some View {
        Button {
            showColorPicker.toggle()
        } label: {
            Circle()
                .fill(CanvasDrawing.colorFromHex(drawingState.currentStrokeColor))
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(DS.textMuted, lineWidth: 1))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showColorPicker) {
            colorPickerPopover
        }
    }

    // MARK: - Width Buttons

    private var widthButtons: some View {
        HStack(spacing: 0) {
            ForEach([(1.0, "S"), (2.0, "M"), (4.0, "L")], id: \.1) { width, label in
                Button {
                    drawingState.currentStrokeWidth = CGFloat(width)
                } label: {
                    Text(label)
                        .font(.system(size: 10, weight: drawingState.currentStrokeWidth == CGFloat(width) ? .bold : .regular))
                        .foregroundColor(drawingState.currentStrokeWidth == CGFloat(width) ? .white : DS.textMuted)
                        .frame(width: 20, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Divider Toggle

    private var dividerToggle: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                toolsVisible.toggle()
            }
        } label: {
            Rectangle()
                .fill(DS.textMuted.opacity(0.4))
                .frame(width: 1, height: 16)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .contentShape(Rectangle().size(width: 20, height: 28))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Secondary Picker

    @ViewBuilder
    private var secondaryPicker: some View {
        Group {
            if toolsVisible && drawingState.toolMode == .shape {
                shapePicker
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if toolsVisible && drawingState.toolMode == .text {
                weightPicker
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(ProMotionSprings.snappy, value: drawingState.toolMode)
        .animation(ProMotionSprings.snappy, value: toolsVisible)
    }

    private var shapePicker: some View {
        HStack(spacing: 0) {
            ForEach(ShapeKind.allCases, id: \.self) { kind in
                Button {
                    drawingState.currentShapeKind = kind
                } label: {
                    Image(systemName: shapeIcon(kind))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(drawingState.currentShapeKind == kind ? .white : DS.textMuted)
                        .frame(width: 24, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // Small separator before tool icons
            Rectangle()
                .fill(DS.textMuted.opacity(0.25))
                .frame(width: 1, height: 12)
                .padding(.horizontal, 4)
        }
    }

    private var weightPicker: some View {
        HStack(spacing: 0) {
            ForEach(DrawingTextWeight.allCases, id: \.self) { weight in
                Button {
                    drawingState.currentTextWeight = weight
                } label: {
                    Text(weight.rawValue)
                        .font(.system(size: 11, weight: drawingState.currentTextWeight == weight ? .bold : .regular))
                        .foregroundColor(drawingState.currentTextWeight == weight ? .white : DS.textMuted)
                        .frame(width: 22, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // Small separator before tool icons
            Rectangle()
                .fill(DS.textMuted.opacity(0.25))
                .frame(width: 1, height: 12)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Color Picker Popover

    private var colorPickerPopover: some View {
        VStack(spacing: 8) {
            Text("Color")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.textSecondary)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 6), count: 4), spacing: 6) {
                ForEach(presetColors, id: \.0) { hex, color in
                    Button {
                        drawingState.currentStrokeColor = hex
                        showColorPicker = false
                    } label: {
                        Circle()
                            .fill(color)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .stroke(
                                        drawingState.currentStrokeColor == hex ? Color.white : Color.clear,
                                        lineWidth: 2
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().opacity(0.3)

            // Fill toggle
            fillToggle
        }
        .padding(12)
        .frame(width: 160)
        .background(CosmoColors.thinkspaceTertiary)
    }

    @ViewBuilder
    private var fillToggle: some View {
        HStack {
            Text("Fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.textSecondary)
            Spacer()
            Toggle("", isOn: Binding(
                get: { drawingState.currentFillColor != nil },
                set: { enabled in
                    drawingState.currentFillColor = enabled ? drawingState.currentStrokeColor : nil
                }
            ))
            .toggleStyle(.switch)
            .scaleEffect(0.7)
        }
    }

    // MARK: - Helpers

    private func shapeIcon(_ kind: ShapeKind) -> String {
        switch kind {
        case .rectangle: return "rectangle"
        case .circle: return "circle"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .triangle: return "triangle"
        }
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
