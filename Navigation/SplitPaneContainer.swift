// CosmoOS/Navigation/SplitPaneContainer.swift
// Split-pane layout system — wraps main content with resizable pane column
// Supports up to 4 panes stacked vertically on the right

import SwiftUI
import AppKit

// MARK: - Split Pane Container

/// Top-level container that optionally splits the view into main content (left) and pane column (right).
/// Always renders main content to preserve view identity/state across pane open/close.
struct SplitPaneContainer<MainContent: View>: View {
    @ObservedObject var paneManager: PaneManager
    let mainContent: MainContent

    init(paneManager: PaneManager, @ViewBuilder mainContent: () -> MainContent) {
        self.paneManager = paneManager
        self.mainContent = mainContent()
    }

    var body: some View {
        GeometryReader { geo in
            splitLayout(geo: geo)
        }
    }

    // MARK: - Split Layout

    @ViewBuilder
    private func splitLayout(geo: GeometryProxy) -> some View {
        let dividerWidth: CGFloat = paneManager.isActive ? 6 : 0
        let mainWidth = geo.size.width * paneManager.mainSplitRatio
        let paneColumnWidth = max(0, geo.size.width - mainWidth - dividerWidth)

        HStack(spacing: 0) {
            // LEFT: Main content (always rendered)
            mainContent
                .frame(width: mainWidth, height: geo.size.height)
                .clipped()

            // Vertical divider between main and pane column
            if paneManager.isActive {
                PaneDivider(isVertical: true) { delta in
                    paneManager.updateMainSplit(delta: delta, totalWidth: geo.size.width)
                }
            }

            // RIGHT: Pane column
            if paneManager.isActive {
                PaneColumnView(
                    paneManager: paneManager,
                    totalHeight: geo.size.height
                )
                .frame(width: paneColumnWidth, height: geo.size.height)
                .clipped()
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }
}

// MARK: - Pane Column View

/// Vertical stack of panes with resizable dividers between them.
struct PaneColumnView: View {
    @ObservedObject var paneManager: PaneManager
    let totalHeight: CGFloat

    private let dividerThickness: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let dividerCount = CGFloat(max(paneManager.panes.count - 1, 0))
            let availableHeight = geo.size.height - dividerCount * dividerThickness

            VStack(spacing: 0) {
                ForEach(Array(paneManager.panes.enumerated()), id: \.element.id) { index, pane in
                    let isActive = paneManager.activePaneId == pane.id
                    let isContextOwner = paneManager.contextOwnerPaneId == pane.id
                    let paneHeight = availableHeight * paneManager.paneSizes[safe: index, default: 1.0]

                    PaneContentView(
                        content: pane,
                        isActive: isActive,
                        isContextOwner: isContextOwner,
                        onClose: {
                            withAnimation(ProMotionSprings.snappy) {
                                paneManager.closePane(at: index)
                            }
                        }
                    )
                    .frame(height: max(paneHeight, 0))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        paneManager.activatePane(pane.id)
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity.combined(with: .scale(scale: 0.95))
                    ))

                    // Horizontal divider between panes (not after the last)
                    if index < paneManager.panes.count - 1 {
                        PaneDivider(isVertical: false) { delta in
                            paneManager.updateDivider(at: index, delta: delta, totalHeight: geo.size.height)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Pane Divider

/// Draggable resize handle between panes.
/// Vertical dividers separate left/right (used between main content and pane column).
/// Horizontal dividers separate top/bottom (used between stacked panes).
struct PaneDivider: View {
    let isVertical: Bool
    let onDrag: (CGFloat) -> Void

    @State private var isHovered = false
    @State private var isDragging = false

    /// Track the last drag translation to compute deltas
    @State private var lastDragValue: CGFloat = 0

    private let thickness: CGFloat = 6

    var body: some View {
        ZStack {
            // Invisible hit area
            Color.clear
                .frame(
                    width: isVertical ? thickness : nil,
                    height: isVertical ? nil : thickness
                )

            // 1px divider line
            Rectangle()
                .fill(DS.borderSubtle)
                .frame(
                    width: isVertical ? 1 : nil,
                    height: isVertical ? nil : 1
                )

            // Centered grab handle pill
            handlePill
        }
        .contentShape(Rectangle().inset(by: -4)) // Larger hit target
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
            if hovering {
                pushResizeCursor()
            } else if !isDragging {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        lastDragValue = 0
                        pushResizeCursor()
                    }
                    let currentValue = isVertical ? value.translation.width : value.translation.height
                    let delta = currentValue - lastDragValue
                    lastDragValue = currentValue
                    onDrag(delta)
                }
                .onEnded { _ in
                    isDragging = false
                    lastDragValue = 0
                    if !isHovered {
                        NSCursor.pop()
                    }
                }
        )
    }

    // MARK: - Handle Pill

    @ViewBuilder
    private var handlePill: some View {
        let handleColor: Color = {
            if isDragging { return DS.accent.opacity(0.6) }
            if isHovered { return DS.textMuted.opacity(0.5) }
            return DS.textMuted.opacity(0.2)
        }()

        let handleWidth: CGFloat = isVertical ? 3 : (isHovered || isDragging ? 36 : 32)
        let handleHeight: CGFloat = isVertical ? (isHovered || isDragging ? 36 : 32) : 3

        RoundedRectangle(cornerRadius: 1.5)
            .fill(handleColor)
            .frame(width: handleWidth, height: handleHeight)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .animation(.easeInOut(duration: 0.15), value: isDragging)
    }

    private func pushResizeCursor() {
        if isVertical {
            NSCursor.resizeLeftRight.push()
        } else {
            NSCursor.resizeUpDown.push()
        }
    }
}
