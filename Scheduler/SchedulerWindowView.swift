// CosmoOS/Scheduler/SchedulerWindowView.swift
// Wrapper view for displaying SchedulerView in canvas blocks
// Maintains compatibility with CanvasBlock entity type .calendar

import SwiftUI

/// Wrapper view that displays the Scheduler within a canvas block
/// Used when entityType == .calendar
struct CalendarWindowView: View {
    let block: CanvasBlock

    @State private var size: CGSize
    @State private var isResizing = false
    @State private var isHovered = false

    // Resize state for each edge/corner
    @State private var resizeEdge: ResizeEdge? = nil

    private let minWidth: CGFloat = 380
    private let minHeight: CGFloat = 400
    private let cornerRadius: CGFloat = 12
    private let resizeHandleSize: CGFloat = 8

    init(block: CanvasBlock) {
        self.block = block
        // Use block size if available, otherwise use default (wider and taller for better week view)
        let initialSize = block.size.width > 0 ? block.size : CGSize(width: 800, height: 580)
        _size = State(initialValue: initialSize)
    }

    var body: some View {
        SchedulerView()
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                // Subtle outline that's always visible
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [
                                CosmoColors.lavender.opacity(isHovered ? 0.25 : 0.12),
                                CosmoColors.glassGrey.opacity(isHovered ? 0.3 : 0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isHovered ? 1.5 : 1
                    )
            )
            .overlay(
                // Resize handles on all edges and corners
                ResizeHandlesOverlay(
                    size: $size,
                    isResizing: $isResizing,
                    resizeEdge: $resizeEdge,
                    minWidth: minWidth,
                    minHeight: minHeight,
                    cornerRadius: cornerRadius,
                    blockId: block.id
                )
            )
            .shadow(
                color: .black.opacity(isHovered ? 0.1 : 0.06),
                radius: isHovered ? 16 : 10,
                y: isHovered ? 6 : 4
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }
}

// MARK: - Resize Edge Enum

enum ResizeEdge: Equatable {
    case top, bottom, left, right
    case topLeft, topRight, bottomLeft, bottomRight
}

// MARK: - Resize Handles Overlay

struct ResizeHandlesOverlay: View {
    @Binding var size: CGSize
    @Binding var isResizing: Bool
    @Binding var resizeEdge: ResizeEdge?

    let minWidth: CGFloat
    let minHeight: CGFloat
    let cornerRadius: CGFloat
    let blockId: String

    private let edgeHandleThickness: CGFloat = 6
    private let cornerHandleSize: CGFloat = 12

    var body: some View {
        ZStack {
            // Edge handles
            EdgeResizeHandle(edge: .top, size: $size, isResizing: $isResizing, resizeEdge: $resizeEdge, minWidth: minWidth, minHeight: minHeight, blockId: blockId)
            EdgeResizeHandle(edge: .bottom, size: $size, isResizing: $isResizing, resizeEdge: $resizeEdge, minWidth: minWidth, minHeight: minHeight, blockId: blockId)
            EdgeResizeHandle(edge: .left, size: $size, isResizing: $isResizing, resizeEdge: $resizeEdge, minWidth: minWidth, minHeight: minHeight, blockId: blockId)
            EdgeResizeHandle(edge: .right, size: $size, isResizing: $isResizing, resizeEdge: $resizeEdge, minWidth: minWidth, minHeight: minHeight, blockId: blockId)

            // Corner handles
            CornerResizeHandle(corner: .topLeft, size: $size, isResizing: $isResizing, resizeEdge: $resizeEdge, minWidth: minWidth, minHeight: minHeight, blockId: blockId)
            CornerResizeHandle(corner: .topRight, size: $size, isResizing: $isResizing, resizeEdge: $resizeEdge, minWidth: minWidth, minHeight: minHeight, blockId: blockId)
            CornerResizeHandle(corner: .bottomLeft, size: $size, isResizing: $isResizing, resizeEdge: $resizeEdge, minWidth: minWidth, minHeight: minHeight, blockId: blockId)
            CornerResizeHandle(corner: .bottomRight, size: $size, isResizing: $isResizing, resizeEdge: $resizeEdge, minWidth: minWidth, minHeight: minHeight, blockId: blockId)
        }
    }
}

// MARK: - Edge Resize Handle

struct EdgeResizeHandle: View {
    let edge: ResizeEdge
    @Binding var size: CGSize
    @Binding var isResizing: Bool
    @Binding var resizeEdge: ResizeEdge?

    let minWidth: CGFloat
    let minHeight: CGFloat
    let blockId: String

    @State private var dragStart: CGSize = .zero
    @State private var isHovered = false

    private let handleThickness: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color.clear)
                .frame(
                    width: isHorizontal ? geometry.size.width - 24 : handleThickness,
                    height: isHorizontal ? handleThickness : geometry.size.height - 24
                )
                .contentShape(Rectangle())
                .position(handlePosition(in: geometry.size))
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if !isResizing {
                                dragStart = size
                                isResizing = true
                                resizeEdge = edge
                            }
                            updateSize(translation: value.translation)
                        }
                        .onEnded { _ in
                            isResizing = false
                            resizeEdge = nil
                            saveSize()
                        }
                )
                .onHover { hovering in
                    isHovered = hovering
                    if hovering {
                        setCursor()
                    } else {
                        NSCursor.arrow.set()
                    }
                }
        }
    }

    private var isHorizontal: Bool {
        edge == .top || edge == .bottom
    }

    private func handlePosition(in parentSize: CGSize) -> CGPoint {
        switch edge {
        case .top: return CGPoint(x: parentSize.width / 2, y: handleThickness / 2)
        case .bottom: return CGPoint(x: parentSize.width / 2, y: parentSize.height - handleThickness / 2)
        case .left: return CGPoint(x: handleThickness / 2, y: parentSize.height / 2)
        case .right: return CGPoint(x: parentSize.width - handleThickness / 2, y: parentSize.height / 2)
        default: return .zero
        }
    }

    private func updateSize(translation: CGSize) {
        switch edge {
        case .top:
            size.height = max(minHeight, dragStart.height - translation.height)
        case .bottom:
            size.height = max(minHeight, dragStart.height + translation.height)
        case .left:
            size.width = max(minWidth, dragStart.width - translation.width)
        case .right:
            size.width = max(minWidth, dragStart.width + translation.width)
        default:
            break
        }

        // Update block size in real-time
        NotificationCenter.default.post(
            name: .updateBlockSize,
            object: nil,
            userInfo: ["blockId": blockId, "size": size]
        )
    }

    private func setCursor() {
        switch edge {
        case .top, .bottom:
            NSCursor.resizeUpDown.set()
        case .left, .right:
            NSCursor.resizeLeftRight.set()
        default:
            break
        }
    }

    private func saveSize() {
        NotificationCenter.default.post(
            name: .saveBlockSize,
            object: nil,
            userInfo: ["blockId": blockId, "size": size]
        )
    }
}

// MARK: - Corner Resize Handle

struct CornerResizeHandle: View {
    let corner: ResizeEdge
    @Binding var size: CGSize
    @Binding var isResizing: Bool
    @Binding var resizeEdge: ResizeEdge?

    let minWidth: CGFloat
    let minHeight: CGFloat
    let blockId: String

    @State private var dragStart: CGSize = .zero
    @State private var isHovered = false

    private let handleSize: CGFloat = 14

    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 2)
                .fill(isHovered || resizeEdge == corner ? CosmoColors.lavender.opacity(0.3) : Color.clear)
                .frame(width: handleSize, height: handleSize)
                .contentShape(Rectangle())
                .position(handlePosition(in: geometry.size))
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if !isResizing {
                                dragStart = size
                                isResizing = true
                                resizeEdge = corner
                            }
                            updateSize(translation: value.translation)
                        }
                        .onEnded { _ in
                            isResizing = false
                            resizeEdge = nil
                            saveSize()
                        }
                )
                .onHover { hovering in
                    isHovered = hovering
                    if hovering {
                        setCursor()
                    } else {
                        NSCursor.arrow.set()
                    }
                }
        }
    }

    private func handlePosition(in parentSize: CGSize) -> CGPoint {
        let offset: CGFloat = handleSize / 2
        switch corner {
        case .topLeft: return CGPoint(x: offset, y: offset)
        case .topRight: return CGPoint(x: parentSize.width - offset, y: offset)
        case .bottomLeft: return CGPoint(x: offset, y: parentSize.height - offset)
        case .bottomRight: return CGPoint(x: parentSize.width - offset, y: parentSize.height - offset)
        default: return .zero
        }
    }

    private func updateSize(translation: CGSize) {
        switch corner {
        case .topLeft:
            size.width = max(minWidth, dragStart.width - translation.width)
            size.height = max(minHeight, dragStart.height - translation.height)
        case .topRight:
            size.width = max(minWidth, dragStart.width + translation.width)
            size.height = max(minHeight, dragStart.height - translation.height)
        case .bottomLeft:
            size.width = max(minWidth, dragStart.width - translation.width)
            size.height = max(minHeight, dragStart.height + translation.height)
        case .bottomRight:
            size.width = max(minWidth, dragStart.width + translation.width)
            size.height = max(minHeight, dragStart.height + translation.height)
        default:
            break
        }

        // Update block size in real-time
        NotificationCenter.default.post(
            name: .updateBlockSize,
            object: nil,
            userInfo: ["blockId": blockId, "size": size]
        )
    }

    private func setCursor() {
        switch corner {
        case .topLeft, .bottomRight:
            // Diagonal NW-SE cursor
            NSCursor.resizeUpDown.set()
        case .topRight, .bottomLeft:
            // Diagonal NE-SW cursor
            NSCursor.resizeLeftRight.set()
        default:
            break
        }
    }

    private func saveSize() {
        NotificationCenter.default.post(
            name: .saveBlockSize,
            object: nil,
            userInfo: ["blockId": blockId, "size": size]
        )
    }
}

/// Alias for clarity - both names work
typealias SchedulerWindowView = CalendarWindowView
