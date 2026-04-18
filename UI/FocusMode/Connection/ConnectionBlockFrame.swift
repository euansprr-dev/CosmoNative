// CosmoOS/UI/FocusMode/Connection/ConnectionBlockFrame.swift
// April 2026 — Connection Focus Mode V3 "The Crucible, Dissolved"
//
// Thin wrapper that positions any intrinsic Connection panel (masthead,
// station card, collaborator, insights, crystal, source card, etc.) as a
// draggable, selectable block on the Connection canvas.
//
// Intentionally NOT reusing `CosmoBlockWrapper` — that type:
//   - expects a `CanvasBlock` domain value
//   - posts `CosmoNotification.Canvas.blockSelected` which races with
//     Thinkspace's `CanvasView.handleTap` when Connection focus mode is
//     open as a pane next to the main canvas
//   - carries gilt-corner chrome tuned for Thinkspace density
//
// Selection is communicated via a plain closure. No notifications.
//
// V3 Phase 3 additions:
//   - `allowResize` + `onResize` — opt-in resize handle in bottom-right.
//   - Reads `\.connectionSpacePanActive` from environment to suppress drags
//     while the user holds space (pan-the-canvas mode).

import SwiftUI

// MARK: - Environment — Space-Pan

private struct ConnectionSpacePanActiveKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// When true, Connection block frames short-circuit their drag gesture so
    /// drags flow to `InfiniteCanvasView`'s pan gesture instead.
    var connectionSpacePanActive: Bool {
        get { self[ConnectionSpacePanActiveKey.self] }
        set { self[ConnectionSpacePanActiveKey.self] = newValue }
    }
}

// MARK: - Chrome Mode

/// Visual treatment applied to a block.
enum ConnectionBlockChrome {
    /// Transparent; the wrapped view supplies its own backdrop. Used for the
    /// masthead which sits on the canvas like a ritual object without a card.
    case none
    /// Hairline rule with soft surfaceCard fill — the default for station,
    /// collaborator, insights, usage blocks.
    case hairline
    /// Sepia parchment fill for source / manuscript blocks — evokes `TheWellView`.
    case paper
}

// MARK: - Connection Block Frame

/// Wraps arbitrary content in a draggable, selectable block frame.
struct ConnectionBlockFrame<Content: View>: View {
    let blockId: String
    let position: CGPoint
    let size: CGSize?
    let chrome: ConnectionBlockChrome
    let isSelected: Bool
    let allowDrag: Bool
    let allowResize: Bool
    let minSize: CGSize
    let maxSize: CGSize
    let onSelect: () -> Void
    let onPositionChange: (CGPoint) -> Void
    let onResize: (CGSize) -> Void
    let content: () -> Content

    @Environment(\.connectionSpacePanActive) private var spacePanActive
    @State private var dragOffset: CGSize = .zero
    @State private var resizeDelta: CGSize = .zero
    @State private var isHovered: Bool = false

    init(
        blockId: String,
        position: CGPoint,
        size: CGSize? = nil,
        chrome: ConnectionBlockChrome = .hairline,
        isSelected: Bool = false,
        allowDrag: Bool = true,
        allowResize: Bool = false,
        minSize: CGSize = CGSize(width: 200, height: 140),
        maxSize: CGSize = CGSize(width: 900, height: 900),
        onSelect: @escaping () -> Void = {},
        onPositionChange: @escaping (CGPoint) -> Void = { _ in },
        onResize: @escaping (CGSize) -> Void = { _ in },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.blockId = blockId
        self.position = position
        self.size = size
        self.chrome = chrome
        self.isSelected = isSelected
        self.allowDrag = allowDrag
        self.allowResize = allowResize
        self.minSize = minSize
        self.maxSize = maxSize
        self.onSelect = onSelect
        self.onPositionChange = onPositionChange
        self.onResize = onResize
        self.content = content
    }

    private var effectiveSize: CGSize? {
        guard let base = size else { return nil }
        let w = (base.width + resizeDelta.width).clamped(to: minSize.width ... maxSize.width)
        let h = (base.height + resizeDelta.height).clamped(to: minSize.height ... maxSize.height)
        return CGSize(width: w, height: h)
    }

    var body: some View {
        content()
            .frame(width: effectiveSize?.width, height: effectiveSize?.height)
            .background(backdrop)
            .overlay(border)
            .overlay(alignment: .bottomTrailing) { resizeHandle }
            .shadow(
                color: shadowColor,
                radius: isHovered || isSelected ? 16 : 8,
                x: 0,
                y: 4
            )
            .position(
                x: position.x + dragOffset.width,
                y: position.y + dragOffset.height
            )
            .onHover { hovering in
                withAnimation(ProMotionSprings.hover) {
                    isHovered = hovering
                }
            }
            .simultaneousGesture(TapGesture().onEnded { onSelect() })
            .gesture((allowDrag && !spacePanActive) ? dragGesture : nil)
    }

    // MARK: - Visuals

    @ViewBuilder
    private var backdrop: some View {
        switch chrome {
        case .none:
            Color.clear
        case .hairline:
            RoundedRectangle(cornerRadius: 14)
                .fill(DS.surfaceCard)
        case .paper:
            RoundedRectangle(cornerRadius: 12)
                .fill(DS.vellum.opacity(0.95))
        }
    }

    @ViewBuilder
    private var border: some View {
        switch chrome {
        case .none:
            EmptyView()
        case .hairline, .paper:
            RoundedRectangle(cornerRadius: chrome == .paper ? 12 : 14)
                .stroke(borderColor, lineWidth: isSelected ? 1.5 : 1)
        }
    }

    private var borderColor: Color {
        if isSelected {
            return DS.accent.opacity(0.6)
        }
        if isHovered {
            return DS.border.opacity(0.8)
        }
        return DS.borderSubtle
    }

    private var shadowColor: Color {
        if isSelected {
            return DS.accent.opacity(0.12)
        }
        return Color.black.opacity(isHovered ? 0.08 : 0.04)
    }

    // MARK: - Resize Handle

    @ViewBuilder
    private var resizeHandle: some View {
        if allowResize && isSelected && size != nil {
            Image(systemName: "arrow.down.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DS.accent.opacity(0.75))
                .frame(width: 18, height: 18)
                .background(DS.surfaceCard, in: Circle())
                .overlay(Circle().stroke(DS.accent.opacity(0.4), lineWidth: 0.6))
                .padding(6)
                .contentShape(Rectangle())
                .gesture(resizeGesture)
                .accessibilityLabel("Resize block")
        }
    }

    // MARK: - Drag

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                let newPosition = CGPoint(
                    x: position.x + value.translation.width,
                    y: position.y + value.translation.height
                )
                dragOffset = .zero
                onPositionChange(newPosition)
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                resizeDelta = value.translation
            }
            .onEnded { value in
                guard let base = size else {
                    resizeDelta = .zero
                    return
                }
                let w = (base.width + value.translation.width).clamped(to: minSize.width ... maxSize.width)
                let h = (base.height + value.translation.height).clamped(to: minSize.height ... maxSize.height)
                resizeDelta = .zero
                onResize(CGSize(width: w, height: h))
            }
    }
}

// MARK: - Helpers

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
