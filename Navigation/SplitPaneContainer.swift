// CosmoOS/Navigation/SplitPaneContainer.swift
// Split-pane layout system — wraps main content with resizable pane column
// Supports up to 4 panes stacked vertically on the right

import SwiftUI
import AppKit

// MARK: - Split Pane Container

/// Top-level container that optionally splits the view into main content (left) and pane column (right).
/// When no panes are open, renders main content at full width.
struct SplitPaneContainer<MainContent: View>: View {
    @ObservedObject var paneManager: PaneManager
    let mainContent: MainContent

    init(paneManager: PaneManager, @ViewBuilder mainContent: () -> MainContent) {
        self.paneManager = paneManager
        self.mainContent = mainContent()
    }

    var body: some View {
        GeometryReader { geo in
            if paneManager.isActive {
                splitLayout(geo: geo)
            } else {
                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Split Layout

    @ViewBuilder
    private func splitLayout(geo: GeometryProxy) -> some View {
        let dividerWidth: CGFloat = 6
        let mainWidth = geo.size.width * paneManager.mainSplitRatio
        let paneColumnWidth = geo.size.width - mainWidth - dividerWidth

        HStack(spacing: 0) {
            // LEFT: Main content
            mainContent
                .frame(width: mainWidth, height: geo.size.height)
                .clipped()

            // Vertical divider between main and pane column
            PaneDivider(isVertical: true) { delta in
                paneManager.updateMainSplit(delta: delta, totalWidth: geo.size.width)
            }

            // RIGHT: Pane column
            PaneColumnView(
                paneManager: paneManager,
                totalHeight: geo.size.height
            )
            .frame(width: max(0, paneColumnWidth), height: geo.size.height)
            .clipped()
        }
    }
}

// MARK: - Pane Column View

/// Vertical stack of panes with resizable dividers between them.
struct PaneColumnView: View {
    @ObservedObject var paneManager: PaneManager
    let totalHeight: CGFloat

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                ForEach(Array(paneManager.panes.enumerated()), id: \.element.id) { index, pane in
                    let isActive = paneManager.activePaneId == pane.id
                    let paneHeight = geo.size.height * paneManager.paneSizes[safe: index, default: 1.0]

                    PaneContentView(
                        content: pane,
                        isActive: isActive,
                        onClose: {
                            withAnimation(ProMotionSprings.snappy) {
                                paneManager.closePane(at: index)
                            }
                        }
                    )
                    .frame(height: paneHeight)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        paneManager.activatePane(pane.id)
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95)),
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
        Rectangle()
            .fill(fillColor)
            .frame(
                width: isVertical ? thickness : nil,
                height: isVertical ? nil : thickness
            )
            .contentShape(Rectangle().inset(by: -4)) // Larger hit target
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isHovered = hovering
                }
                if hovering {
                    pushResizeCursor()
                } else if !isDragging {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
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

    private var fillColor: Color {
        if isDragging {
            return CosmoColors.thinkspacePurple.opacity(0.5)
        } else if isHovered {
            return CosmoColors.thinkspacePurple.opacity(0.3)
        } else {
            return Color.white.opacity(0.06)
        }
    }

    private func pushResizeCursor() {
        if isVertical {
            NSCursor.resizeLeftRight.push()
        } else {
            NSCursor.resizeUpDown.push()
        }
    }
}
