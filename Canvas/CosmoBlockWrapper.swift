// CosmoOS/Canvas/CosmoBlockWrapper.swift
// Native floating block wrapper for Thinkspace - dark glass design
// No traffic lights, clean card aesthetic matching Sanctuary
// December 2025 - ProMotion springs, 3D tilt, selection toolbar

import SwiftUI

/// A native dark glass wrapper that provides clean, minimal chrome
/// for all floating block types on the Thinkspace canvas.
struct CosmoBlockWrapper<Content: View>: View {
    let block: CanvasBlock
    let accentColor: Color
    let icon: String
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    // Optional callbacks
    var onClose: (() -> Void)? = nil
    var onFocusMode: (() -> Void)? = nil
    var onDuplicate: (() -> Void)? = nil
    var onAIAssist: (() -> Void)? = nil

    // Environment
    @EnvironmentObject private var expansionManager: BlockExpansionManager

    // State
    @State private var isHovered = false
    @State private var blockSize: CGSize
    @State private var isResizing = false
    @State private var isDragging = false
    @State private var hoverLocation: CGPoint = CGPoint(x: 0.5, y: 0.5)

    // Selection is read from block, not a binding
    private var isSelected: Bool { block.isSelected }

    // Constants
    private let expandedScale: CGFloat = 1.5
    private let minWidth: CGFloat = 200
    private let minHeight: CGFloat = 150
    private let maxWidth: CGFloat = 1200
    private let maxHeight: CGFloat = 1000

    // Reference size for content scaling
    private let referenceWidth: CGFloat = 320
    private let referenceHeight: CGFloat = 280

    init(
        block: CanvasBlock,
        accentColor: Color,
        icon: String,
        title: String,
        isExpanded: Binding<Bool>,
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
        self._isExpanded = isExpanded
        self.onClose = onClose
        self.onFocusMode = onFocusMode
        self.onDuplicate = onDuplicate
        self.onAIAssist = onAIAssist
        self.content = content
        self._blockSize = State(initialValue: block.size)
    }

    // MARK: - Computed Properties

    private var effectiveWidth: CGFloat {
        isExpanded ? min(blockSize.width * expandedScale, maxWidth) : blockSize.width
    }

    private var effectiveHeight: CGFloat {
        isExpanded ? min(blockSize.height * expandedScale, maxHeight) : blockSize.height
    }

    private var contentScale: CGFloat {
        effectiveWidth / referenceWidth
    }

    // Onyx neutral shadow elevation
    private var currentOnyxElevation: OnyxElevation {
        if isDragging { return .floating }
        if isHovered { return .hovered }
        return .resting
    }

    // 3D tilt amount based on hover position
    private var tiltAxis: (x: CGFloat, y: CGFloat, z: CGFloat) {
        guard isHovered && !isExpanded && !isDragging && !isSelected else {
            return (0, 0, 0)
        }
        return (
            x: (hoverLocation.y - 0.5) * -2,
            y: (hoverLocation.x - 0.5) * 2,
            z: 0
        )
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // Main card
            VStack(spacing: 0) {
                // Content area - fills available space naturally
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .contentShape(Rectangle())
            }
            .frame(width: effectiveWidth, height: effectiveHeight)
            .background(blockBackground)
            .clipShape(RoundedRectangle(cornerRadius: OnyxLayout.cardCornerRadius))
            .overlay(blockBorder)
            // Simple edge resize overlay (safe implementation)
            .overlay {
                SimpleResizeOverlay(
                    size: $blockSize,
                    blockId: block.id,
                    minSize: CGSize(width: minWidth, height: minHeight),
                    maxSize: CGSize(width: maxWidth, height: maxHeight)
                )
            }
            // Onyx neutral dual-layer shadow + optional accent glow when selected
            .onyxShadow(currentOnyxElevation, accentGlow: isSelected ? accentColor : nil)
            .compositingGroup()
            // 3D tilt effect on hover (only when not selected)
            .rotation3DEffect(
                .degrees(isHovered && !isExpanded && !isDragging && !isSelected ? 1.5 : 0),
                axis: tiltAxis,
                perspective: 0.5
            )
            .scaleEffect(isHovered && !isExpanded && !isSelected ? 1.008 : 1.0)
            .offset(y: isHovered && !isExpanded && !isSelected ? -2 : 0)

            // Floating toolbar when selected
            // Always in view hierarchy, opacity controlled by selection state
            // This avoids view creation during animation which can cause crashes
            BlockSelectionToolbar(
                blockCount: 1,
                accentColor: accentColor,
                onAIAssist: onAIAssist ?? {},
                onColorChange: {},
                onSave: {},
                onEdit: {},
                onFocusMode: {
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
                },
                onDuplicate: onDuplicate ?? {},
                onDelete: {
                    CosmicHaptics.shared.play(.delete)
                    if let onClose = onClose {
                        onClose()
                    } else {
                        NotificationCenter.default.post(
                            name: .removeBlock,
                            object: nil,
                            userInfo: ["blockId": block.id]
                        )
                    }
                }
            )
            .offset(y: isSelected ? -52 : -44)
            .scaleEffect(isSelected ? 1.0 : 0.9)
            .opacity(isSelected ? 1 : 0)
            .allowsHitTesting(isSelected)
            .animation(ProMotionSprings.snappy, value: isSelected)
        }
        // ProMotion-optimized animations
        // NOTE: Removed animation on isSelected to avoid conflicts with toolbar transition
        .animation(ProMotionSprings.hover, value: isHovered)
        .animation(isExpanded ? ProMotionSprings.bouncy : ProMotionSprings.snappy, value: isExpanded)
        .onHover { hovering in
            // Direct state update - animation is handled by .animation modifier
            isHovered = hovering
            if !hovering {
                hoverLocation = CGPoint(x: 0.5, y: 0.5)
            }
        }
        .onTapGesture {
            // Single tap to select - post notification to CanvasView
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
    }

    // MARK: - Background

    private var blockBackground: some View {
        ZStack {
            // Flat Onyx raised surface
            OnyxColors.Elevation.raised

            // Subtle inner glow when selected
            if isSelected {
                RoundedRectangle(cornerRadius: OnyxLayout.cardCornerRadius)
                    .fill(accentColor.opacity(0.03))
            }
        }
    }

    // MARK: - Border

    private var blockBorder: some View {
        RoundedRectangle(cornerRadius: OnyxLayout.cardCornerRadius)
            .stroke(
                isSelected
                    ? accentColor.opacity(0.5)
                    : Color.white.opacity(isHovered ? 0.10 : 0.06),
                lineWidth: 1
            )
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
                .foregroundColor(Color.white.opacity(0.6))
                .padding(.horizontal, 12)

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.1))
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
                                : (hoveredAction == action ? Color.white : Color.white.opacity(0.7))
                        )
                        .frame(width: 32, height: 32)
                        .background(
                            hoveredAction == action
                                ? Color.white.opacity(0.1)
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
        .background(toolbarBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .onyxShadow(.floating)
    }

    private var toolbarBackground: some View {
        OnyxColors.Elevation.floating
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
                                    userInfo: ["blockId": blockId, "size": size]
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
                                userInfo: ["blockId": blockId, "size": size]
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
                                userInfo: ["blockId": blockId, "size": size]
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

                        DispatchQueue.main.async {
                            NSCursor.arrow.set()
                            NotificationCenter.default.post(
                                name: .saveBlockSize,
                                object: nil,
                                userInfo: ["blockId": finalBlockId, "size": finalSize]
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
                .foregroundColor(isHovered || isResizing ? Color.white.opacity(0.8) : Color.white.opacity(0.4))
                .rotationEffect(.degrees(90))
                .frame(width: 14, height: 14)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(CosmoColors.thinkspaceTertiary.opacity(isHovered || isResizing ? 0.8 : 0.5))
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
                        userInfo: ["blockId": blockId, "size": size]
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
    @State static var isExpanded = false

    static var previews: some View {
        ZStack {
            CosmoColors.thinkspaceVoid
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
                accentColor: CosmoColors.blockContent,
                icon: "doc.text.fill",
                title: "Sample Idea",
                isExpanded: $isExpanded
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    // Placeholder heading
                    Text("Heading")
                        .font(.system(size: 24, weight: .regular, design: .serif))
                        .italic()
                        .foregroundColor(Color.white.opacity(0.4))

                    // Placeholder body
                    Text("Press / for commands...")
                        .font(.system(size: 14))
                        .foregroundColor(Color.white.opacity(0.3))

                    Spacer()
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .environmentObject(BlockExpansionManager())
        }
        .frame(width: 600, height: 500)
    }
}
#endif
