// CosmoOS/Canvas/CosmoBlockWrapper.swift
// Native floating block wrapper for Thinkspace — Greenhouse light mode
// No traffic lights, clean card aesthetic matching Sanctuary
// December 2025 - ProMotion springs, 3D tilt, selection toolbar
// March 2026 — Greenhouse light-mode rebrand

import SwiftUI

// MARK: - Environment: Suppress Canvas Selection Notifications

/// When set, block wrappers skip posting `CosmoNotification.Canvas.blockSelected`
/// on tap. Used by Connection Focus Mode (V3) to prevent Thinkspace's main
/// `CanvasView.handleTap` from racing with in-focus selection when Connection
/// is open as a side pane.
private struct CanvasBlockSelectionSuppressedKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var canvasBlockSelectionSuppressed: Bool {
        get { self[CanvasBlockSelectionSuppressedKey.self] }
        set { self[CanvasBlockSelectionSuppressedKey.self] = newValue }
    }
}

/// Surface style for a block wrapper. Most blocks use `.vellum` (aged parchment,
/// the default for the Akashic canvas). Photographic / chromatically-sensitive
/// blocks like Media opt into `.crisp` for pure white backgrounds.
enum BlockSurfaceStyle {
    case vellum
    case crisp
}

/// Akashic canvas wrapper — vellum surface, gilt corner ornament, tiered shadow
/// and accent-glow selection. Shared chrome for all floating block types.
struct CosmoBlockWrapper<Content: View>: View {
    let block: CanvasBlock
    let accentColor: Color
    let icon: String
    let title: String
    @ViewBuilder let content: () -> Content

    // Crystallization
    var crystallizationLevel: CrystallizationLevel = .raw

    // When true, the block grows vertically to fit content (no fixed height, no scaling)
    var autoHeight: Bool = false

    // Surface style — .vellum (default) or .crisp (pure white, for Media)
    var surfaceStyle: BlockSurfaceStyle = .vellum

    // When true, suppresses the gilt corner ornament (for blocks with their own chrome)
    var suppressGiltCorner: Bool = false

    // Optional callbacks
    var onClose: (() -> Void)? = nil
    var onFocusMode: (() -> Void)? = nil
    var onDuplicate: (() -> Void)? = nil
    var onAIAssist: (() -> Void)? = nil

    // State
    @State private var isHovered = false
    @State private var blockSize: CGSize
    @State private var isResizing = false
    @State private var isDragging = false
    @State private var hasAppeared = false

    @Environment(\.canvasBlockSelectionSuppressed) private var selectionNotificationsSuppressed

    // Selection is read from block, not a binding
    private var isSelected: Bool { block.isSelected }

    // Constants
    private let minWidth: CGFloat = 200
    private let minHeight: CGFloat = 150
    private let maxWidth: CGFloat = 1200
    private let maxHeight: CGFloat = 5000

    init(
        block: CanvasBlock,
        accentColor: Color,
        icon: String,
        title: String,
        autoHeight: Bool = false,
        surfaceStyle: BlockSurfaceStyle = .vellum,
        suppressGiltCorner: Bool = false,
        onClose: (() -> Void)? = nil,
        onFocusMode: (() -> Void)? = nil,
        onDuplicate: (() -> Void)? = nil,
        onAIAssist: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.block = block
        self.accentColor = accentColor
        self.icon = icon
        self.title = title
        self.autoHeight = autoHeight
        self.surfaceStyle = surfaceStyle
        self.suppressGiltCorner = suppressGiltCorner
        self.onClose = onClose
        self.onFocusMode = onFocusMode
        self.onDuplicate = onDuplicate
        self.onAIAssist = onAIAssist
        self.content = content
        self._blockSize = State(initialValue: block.size)
    }

    // MARK: - Computed Properties

    private var effectiveWidth: CGFloat {
        blockSize.width
    }

    private var effectiveHeight: CGFloat {
        blockSize.height
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // Main card — tap gestures constrained to card bounds
            VStack(spacing: 0) {
                // Content area
                if autoHeight {
                    // Auto-height mode: content flows naturally, no scaling
                    content()
                        .frame(width: effectiveWidth, alignment: .topLeading)
                        .contentShape(Rectangle())
                } else {
                    // Fixed-size mode: content fills block dimensions directly
                    content()
                        .frame(width: effectiveWidth, height: effectiveHeight, alignment: .topLeading)
                        .contentShape(Rectangle())
                }

                // Crystallization indicator (only shown when level > raw)
                if crystallizationLevel > .raw {
                    CrystallizationIndicator(
                        level: crystallizationLevel,
                        accentColor: accentColor
                    )
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .frame(width: effectiveWidth, height: autoHeight ? nil : effectiveHeight)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            BlockRenderedSizeCache.shared.update(blockId: block.id, size: geo.size)
                        }
                        .onChange(of: geo.size) { _, newSize in
                            BlockRenderedSizeCache.shared.update(blockId: block.id, size: newSize)
                        }
                }
            )
            .background(blockBackground)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusMedium))
            .overlay(blockBorder)
            .overlay(alignment: .topTrailing) {
                blockAccentChip
            }
            .overlay(alignment: .topLeading) {
                if !suppressGiltCorner {
                    GiltCornerBracket()
                        .stroke(DS.gilt, lineWidth: 0.8)
                        .frame(width: 12, height: 12)
                        .padding(7)
                        .opacity(isHovered || isSelected ? 0.85 : 0.55)
                        .allowsHitTesting(false)
                }
            }
            // Simple edge resize overlay (safe implementation)
            .overlay {
                SimpleResizeOverlay(
                    size: $blockSize,
                    blockId: block.id,
                    minSize: CGSize(width: minWidth, height: minHeight),
                    maxSize: CGSize(width: maxWidth, height: maxHeight)
                )
            }
            // PERF: Fixed shadow during drag — avoids GPU shadow recomputation per frame.
            // Resting / hover / drag tiers use soft natural-light shadow pair.
            .shadow(
                color: .black.opacity(isDragging ? 0.10 : (isHovered ? 0.06 : 0.04)),
                radius: isDragging ? 20 : (isHovered ? 16 : 8),
                x: 0,
                y: isDragging ? 8 : (isHovered ? 4 : 2)
            )
            .shadow(
                color: .black.opacity(isDragging ? 0.05 : (isHovered ? 0.03 : 0.02)),
                radius: isDragging ? 4 : (isHovered ? 4 : 2),
                x: 0,
                y: isDragging ? 2 : (isHovered ? 2 : 1)
            )
            // Accent glow layer — lights up on selection to echo CommandCenter affordance
            .shadow(
                color: isSelected ? DS.accentGlow.opacity(0.6) : .clear,
                radius: isSelected ? 14 : 0,
                x: 0,
                y: 0
            )
            .animation(isDragging ? nil : ProMotionSprings.hover, value: isDragging)
            // Per design language: card hover is depth change, not scale.
            .contentShape(RoundedRectangle(cornerRadius: DS.radiusMedium))
            .onTapGesture {
                // Single tap to select - post notification to CanvasView, unless
                // we're inside Connection Focus Mode (which handles selection locally).
                guard !selectionNotificationsSuppressed else { return }
                NotificationCenter.default.post(
                    name: CosmoNotification.Canvas.blockSelected,
                    object: nil,
                    userInfo: ["blockId": block.id]
                )
            }
            .onTapGesture(count: 2) {
                // Double-tap to enter focus mode
                CosmicHaptics.shared.play(.focusEnter)
                if let onFocusMode = onFocusMode {
                    onFocusMode()
                } else {
                    NotificationCenter.default.post(
                        name: .enterFocusMode,
                        object: nil,
                        userInfo: ["type": block.entityType, "id": block.entityId]
                    )
                }
            }

            // Block selection toolbar removed — actions now live in the
            // unified CanvasSelectionInspector panel (top-right corner)
        }
        // ProMotion-optimized animations
        // NOTE: Removed animation on isSelected to avoid conflicts with toolbar transition
        .animation(ProMotionSprings.hover, value: isHovered)
        // Entrance: gentle fade + spring-up on first paint
        .opacity(hasAppeared ? 1.0 : 0.0)
        .offset(y: hasAppeared ? 0 : 6)
        .onChange(of: block.size) { _, newSize in
            guard !isResizing, blockSize != newSize else { return }
            blockSize = newSize
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            guard !hasAppeared else { return }
            withAnimation(ProMotionSprings.cardEntrance) {
                hasAppeared = true
            }
        }
    }

    // MARK: - Background

    /// Base surface fill — vellum (warm parchment) for most blocks,
    /// crisp white for media/photographic content.
    private var baseSurface: Color {
        switch surfaceStyle {
        case .vellum: return DS.vellum
        case .crisp:  return DS.surfaceElevated
        }
    }

    @ViewBuilder
    private var blockBackground: some View {
        let shape = RoundedRectangle(cornerRadius: DS.radiusMedium)
        if isSelected {
            ZStack {
                shape.fill(baseSurface)
                shape.fill(accentColor.opacity(DS.palette.isDark ? 0.060 : 0.045))
            }
        } else {
            shape.fill(baseSurface)
        }
    }

    private var blockAccentChip: some View {
        Capsule(style: .continuous)
            .fill(accentColor.opacity(blockAccentOpacity))
            .frame(width: isSelected ? 34 : 28, height: isSelected ? 4 : 3)
            .padding(8)
            .shadow(
                color: isSelected ? accentColor.opacity(0.26) : .clear,
                radius: 5,
                x: 0,
                y: 0
            )
            .allowsHitTesting(false)
    }

    private var blockAccentOpacity: Double {
        if isSelected { return 0.92 }
        if isHovered { return 0.70 }
        return DS.palette.isDark ? 0.48 : 0.40
    }

    // MARK: - Border

    private var blockBorder: some View {
        let shape = RoundedRectangle(cornerRadius: DS.radiusMedium)
        return ZStack {
            if isSelected {
                // Selected: accent stroke + warm inner sepia line for richness
                shape.stroke(accentColor.opacity(0.78), lineWidth: 1.25)
            } else if crystallizationLevel > .raw {
                // Crystallization levels keep accent-tinted borders
                shape.stroke(
                    crystallizationBorderColor,
                    lineWidth: crystallizationLevel >= .distilled ? 1.5 : 1
                )
            } else if isHovered {
                shape.stroke(DS.sepiaBorder, lineWidth: 1)
            } else {
                shape.stroke(DS.sepiaBorder, lineWidth: 0.5)
            }

            // Outer glow for connected+ levels
            if crystallizationLevel >= .connected && !isSelected {
                shape.stroke(
                    accentColor.opacity(crystallizationLevel == .crystallized ? 0.34 : 0.18),
                    lineWidth: 2
                )
                .blur(radius: crystallizationLevel == .crystallized ? 8 : 4)
            }

            if isSelected {
                shape.stroke(accentColor.opacity(0.22), lineWidth: 3)
                    .blur(radius: 6)
            }
        }
    }

    private var crystallizationBorderColor: Color {
        switch crystallizationLevel {
        case .raw:
            return DS.sepiaBorder // fallback, handled by gradient above
        case .highlighted:
            return accentColor.opacity(0.15)
        case .distilled:
            return accentColor.opacity(0.25)
        case .connected:
            return accentColor.opacity(0.4)
        case .crystallized:
            return accentColor.opacity(0.6)
        }
    }
}

// MARK: - Block Selection Toolbar

/// Floating toolbar that appears above selected block(s)
struct BlockSelectionToolbar: View {
    let blockCount: Int
    let accentColor: Color
    let onAIAssist: () -> Void
    let onColorChange: () -> Void
    let onSave: () -> Void
    let onEdit: () -> Void
    let onFocusMode: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    @State private var hoveredAction: ToolbarAction?

    enum ToolbarAction: String, CaseIterable {
        case aiAssist = "sparkles"
        case color = "paintpalette.fill"
        case save = "bookmark.fill"
        case edit = "pencil"
        case focusMode = "arrow.up.left.and.arrow.down.right"
        case duplicate = "doc.on.doc.fill"
        case delete = "trash.fill"

        var label: String {
            switch self {
            case .aiAssist: return "AI"
            case .color: return "Color"
            case .save: return "Save"
            case .edit: return "Edit"
            case .focusMode: return "Focus"
            case .duplicate: return "Copy"
            case .delete: return "Delete"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Selected count
            Text("\(blockCount) selected")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.textSecondary)
                .padding(.horizontal, 12)

            // Divider
            Rectangle()
                .fill(DS.borderActive)
                .frame(width: 1, height: 20)

            // Action buttons
            ForEach(ToolbarAction.allCases, id: \.self) { action in
                Button {
                    executeAction(action)
                } label: {
                    Image(systemName: action.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(
                            action == .delete
                                ? Color(hex: "FF5F57")
                                : (hoveredAction == action ? DS.text : DS.textSecondary)
                        )
                        .frame(width: 32, height: 32)
                        .background(
                            hoveredAction == action
                                ? DS.borderActive
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    // Direct state update - animation is handled by view modifier
                    hoveredAction = hovering ? action : nil
                }
                .help(action.label)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: hoveredAction)
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DS.border, lineWidth: 1)
        )
        .dsFloatingShadow()
    }

    private func executeAction(_ action: ToolbarAction) {
        CosmicHaptics.shared.play(.selection)
        switch action {
        case .aiAssist: onAIAssist()
        case .color: onColorChange()
        case .save: onSave()
        case .edit: onEdit()
        case .focusMode: onFocusMode()
        case .duplicate: onDuplicate()
        case .delete: onDelete()
        }
    }
}

// MARK: - Simple Resize Overlay (Safe Implementation)

/// Minimal edge resize - just bottom-right corner for simplicity and stability
struct SimpleResizeOverlay: View {
    @Binding var size: CGSize
    let blockId: String
    let minSize: CGSize
    let maxSize: CGSize

    @State private var isDragging = false
    @State private var dragStartSize: CGSize = .zero

    private let handleSize: CGFloat = 20

    var body: some View {
        // Bottom-right corner resize handle
        VStack {
            Spacer()
            HStack {
                Spacer()
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: handleSize, height: handleSize)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                if !isDragging {
                                    isDragging = true
                                    dragStartSize = size
                                }

                                let newWidth = max(minSize.width, min(maxSize.width,
                                    dragStartSize.width + value.translation.width))
                                let newHeight = max(minSize.height, min(maxSize.height,
                                    dragStartSize.height + value.translation.height))

                                size = CGSize(width: newWidth, height: newHeight)
                            }
                            .onEnded { _ in
                                isDragging = false
                                // Save the new size
                                NotificationCenter.default.post(
                                    name: .saveBlockSize,
                                    object: nil,
                                    userInfo: ["blockId": blockId, "size": size, "oldSize": dragStartSize]
                                )
                            }
                    )
                    .onHover { hovering in
                        if hovering {
                            NSCursor.crosshair.set()
                        } else if !isDragging {
                            NSCursor.arrow.set()
                        }
                    }
            }
        }

        // Right edge resize
        HStack {
            Spacer()
            Rectangle()
                .fill(Color.clear)
                .frame(width: 8)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                dragStartSize = size
                            }
                            let newWidth = max(minSize.width, min(maxSize.width,
                                dragStartSize.width + value.translation.width))
                            size = CGSize(width: newWidth, height: size.height)
                        }
                        .onEnded { _ in
                            isDragging = false
                            NotificationCenter.default.post(
                                name: .saveBlockSize,
                                object: nil,
                                userInfo: ["blockId": blockId, "size": size, "oldSize": dragStartSize]
                            )
                        }
                )
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeLeftRight.set()
                    } else if !isDragging {
                        NSCursor.arrow.set()
                    }
                }
        }
        .padding(.vertical, handleSize)

        // Bottom edge resize
        VStack {
            Spacer()
            Rectangle()
                .fill(Color.clear)
                .frame(height: 8)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                dragStartSize = size
                            }
                            let newHeight = max(minSize.height, min(maxSize.height,
                                dragStartSize.height + value.translation.height))
                            size = CGSize(width: size.width, height: newHeight)
                        }
                        .onEnded { _ in
                            isDragging = false
                            NotificationCenter.default.post(
                                name: .saveBlockSize,
                                object: nil,
                                userInfo: ["blockId": blockId, "size": size, "oldSize": dragStartSize]
                            )
                        }
                )
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeUpDown.set()
                    } else if !isDragging {
                        NSCursor.arrow.set()
                    }
                }
        }
        .padding(.horizontal, handleSize)
    }
}

// MARK: - Native Edge Resize Overlay (macOS-style) - DEPRECATED

/// Invisible edge/corner resize zones like native macOS windows
struct NativeEdgeResizeOverlay: View {
    @Binding var size: CGSize
    @Binding var isResizing: Bool
    let blockId: String
    let minWidth: CGFloat
    let minHeight: CGFloat
    let maxWidth: CGFloat
    let maxHeight: CGFloat

    // Edge detection zone size (larger for easier grabbing)
    private let edgeSize: CGFloat = 10
    private let cornerSize: CGFloat = 16

    var body: some View {
        ZStack {
            // Corner resize zones (higher priority - larger hit areas)
            // Bottom-right corner
            EdgeResizeZone(
                edge: .bottomRight,
                size: $size,
                isResizing: $isResizing,
                blockId: blockId,
                minWidth: minWidth, minHeight: minHeight,
                maxWidth: maxWidth, maxHeight: maxHeight
            )
            .frame(width: cornerSize, height: cornerSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

            // Bottom-left corner
            EdgeResizeZone(
                edge: .bottomLeft,
                size: $size,
                isResizing: $isResizing,
                blockId: blockId,
                minWidth: minWidth, minHeight: minHeight,
                maxWidth: maxWidth, maxHeight: maxHeight
            )
            .frame(width: cornerSize, height: cornerSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            // Top-right corner
            EdgeResizeZone(
                edge: .topRight,
                size: $size,
                isResizing: $isResizing,
                blockId: blockId,
                minWidth: minWidth, minHeight: minHeight,
                maxWidth: maxWidth, maxHeight: maxHeight
            )
            .frame(width: cornerSize, height: cornerSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            // Top-left corner
            EdgeResizeZone(
                edge: .topLeft,
                size: $size,
                isResizing: $isResizing,
                blockId: blockId,
                minWidth: minWidth, minHeight: minHeight,
                maxWidth: maxWidth, maxHeight: maxHeight
            )
            .frame(width: cornerSize, height: cornerSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Edge resize zones
            // Right edge
            EdgeResizeZone(
                edge: .right,
                size: $size,
                isResizing: $isResizing,
                blockId: blockId,
                minWidth: minWidth, minHeight: minHeight,
                maxWidth: maxWidth, maxHeight: maxHeight
            )
            .frame(width: edgeSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(.vertical, cornerSize)

            // Left edge
            EdgeResizeZone(
                edge: .left,
                size: $size,
                isResizing: $isResizing,
                blockId: blockId,
                minWidth: minWidth, minHeight: minHeight,
                maxWidth: maxWidth, maxHeight: maxHeight
            )
            .frame(width: edgeSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.vertical, cornerSize)

            // Bottom edge
            EdgeResizeZone(
                edge: .bottom,
                size: $size,
                isResizing: $isResizing,
                blockId: blockId,
                minWidth: minWidth, minHeight: minHeight,
                maxWidth: maxWidth, maxHeight: maxHeight
            )
            .frame(height: edgeSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, cornerSize)

            // Top edge
            EdgeResizeZone(
                edge: .top,
                size: $size,
                isResizing: $isResizing,
                blockId: blockId,
                minWidth: minWidth, minHeight: minHeight,
                maxWidth: maxWidth, maxHeight: maxHeight
            )
            .frame(height: edgeSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, cornerSize)
        }
    }
}

// MARK: - Edge Resize Zone

/// Individual invisible resize zone for an edge or corner
struct EdgeResizeZone: View {
    enum Edge {
        case top, bottom, left, right
        case topLeft, topRight, bottomLeft, bottomRight

        var resizesWidth: Bool {
            switch self {
            case .top, .bottom: return false
            default: return true
            }
        }

        var resizesHeight: Bool {
            switch self {
            case .left, .right: return false
            default: return true
            }
        }

        var widthMultiplier: CGFloat {
            switch self {
            case .left, .topLeft, .bottomLeft: return -1
            case .right, .topRight, .bottomRight: return 1
            default: return 0
            }
        }

        var heightMultiplier: CGFloat {
            switch self {
            case .top, .topLeft, .topRight: return -1
            case .bottom, .bottomLeft, .bottomRight: return 1
            default: return 0
            }
        }
    }

    let edge: Edge
    @Binding var size: CGSize
    @Binding var isResizing: Bool
    let blockId: String
    let minWidth: CGFloat
    let minHeight: CGFloat
    let maxWidth: CGFloat
    let maxHeight: CGFloat

    @State private var dragStart: CGSize = .zero
    @State private var isHovered: Bool = false

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    if !isHovered {
                        isHovered = true
                        DispatchQueue.main.async {
                            setCursor(for: edge)
                        }
                    }
                case .ended:
                    if isHovered && !isResizing {
                        isHovered = false
                        DispatchQueue.main.async {
                            NSCursor.arrow.set()
                        }
                    }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if !isResizing {
                            dragStart = size
                            isResizing = true
                        }

                        var newSize = dragStart

                        if edge.resizesWidth {
                            let delta = value.translation.width * edge.widthMultiplier
                            newSize.width = min(maxWidth, max(minWidth, dragStart.width + delta))
                        }

                        if edge.resizesHeight {
                            let delta = value.translation.height * edge.heightMultiplier
                            newSize.height = min(maxHeight, max(minHeight, dragStart.height + delta))
                        }

                        size = newSize
                    }
                    .onEnded { _ in
                        let finalSize = size
                        let finalBlockId = blockId
                        isResizing = false
                        isHovered = false

                        let oldSize = dragStart
                        DispatchQueue.main.async {
                            NSCursor.arrow.set()
                            NotificationCenter.default.post(
                                name: .saveBlockSize,
                                object: nil,
                                userInfo: ["blockId": finalBlockId, "size": finalSize, "oldSize": oldSize]
                            )
                        }
                    }
            )
    }

    private func setCursor(for edge: Edge) {
        switch edge {
        case .left, .right:
            NSCursor.resizeLeftRight.set()
        case .top, .bottom:
            NSCursor.resizeUpDown.set()
        case .topLeft, .bottomRight:
            NSCursor.crosshair.set()
        case .topRight, .bottomLeft:
            NSCursor.crosshair.set()
        }
    }
}

// MARK: - Legacy Compatibility Aliases
typealias BlockResizeHandlesOverlay = NativeEdgeResizeOverlay

// MARK: - Legacy Compatibility - BlockResizeHandle
// Keep for backward compatibility with existing code

struct BlockResizeHandle: View {
    @Binding var size: CGSize
    @Binding var isResizing: Bool
    let blockId: String

    let minWidth: CGFloat
    let minHeight: CGFloat
    let maxWidth: CGFloat
    let maxHeight: CGFloat

    @State private var dragStart: CGSize = .zero
    @State private var isHovered = false

    var body: some View {
        ZStack {
            Color.clear
                .frame(width: 20, height: 20)

            Image(systemName: "arrow.up.backward.and.arrow.down.forward")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(isHovered || isResizing ? DS.text : DS.textMuted)
                .rotationEffect(.degrees(90))
                .frame(width: 14, height: 14)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(DS.borderSubtle.opacity(isHovered || isResizing ? 0.8 : 0.5))
                )
                .scaleEffect(isResizing ? 1.1 : (isHovered ? 1.05 : 1.0))
        }
        .offset(x: -8, y: -8)
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if !isResizing {
                        dragStart = size
                        isResizing = true
                    }

                    let newWidth = min(maxWidth, max(minWidth, dragStart.width + value.translation.width))
                    let newHeight = min(maxHeight, max(minHeight, dragStart.height + value.translation.height))

                    size = CGSize(width: newWidth, height: newHeight)

                    NotificationCenter.default.post(
                        name: .updateBlockSize,
                        object: nil,
                        userInfo: ["blockId": blockId, "size": size]
                    )
                }
                .onEnded { _ in
                    isResizing = false

                    NotificationCenter.default.post(
                        name: .saveBlockSize,
                        object: nil,
                        userInfo: ["blockId": blockId, "size": size, "oldSize": dragStart]
                    )
                }
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }

            if hovering {
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
        .animation(.spring(response: 0.2), value: isResizing)
        .animation(.spring(response: 0.2), value: isHovered)
    }
}

// MARK: - Preview

#if DEBUG
struct CosmoBlockWrapper_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            DS.canvas
                .ignoresSafeArea()

            // Create block then modify for preview
            let previewBlock: CanvasBlock = {
                var block = CanvasBlock(
                    position: CGPoint(x: 200, y: 200),
                    size: CGSize(width: 320, height: 280),
                    entityType: .idea,
                    entityId: 1,
                    entityUuid: "preview",
                    title: "Sample Idea"
                )
                block.isSelected = true  // Preview in selected state
                return block
            }()

            CosmoBlockWrapper(
                block: previewBlock,
                accentColor: DS.entityContent,
                icon: "doc.text.fill",
                title: "Sample Idea"
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    // Placeholder heading
                    Text("Heading")
                        .font(.system(size: 24, weight: .regular, design: .serif))
                        .italic()
                        .foregroundColor(DS.textMuted)

                    // Placeholder body
                    Text("Press / for commands...")
                        .font(.system(size: 14))
                        .foregroundColor(DS.textMuted)

                    Spacer()
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: 600, height: 500)
    }
}
#endif
