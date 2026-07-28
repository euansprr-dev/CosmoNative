// CosmoOS/Navigation/SplitPaneContainer.swift
// Split-pane layout system — wraps main content with the pane deck column.
// Deck model: a tab rail names every open pane (the Safari/Xcode grammar);
// the focused pane fills the column, plus an optional pinned pane beside it.
// Every pane body stays mounted so state survives tab switches.

import SwiftUI
import AppKit

// MARK: - Split Pane Container

/// Top-level container that optionally splits the view into main content (left) and pane deck (right).
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
                PaneDivider(
                    isVertical: true,
                    onDragBegan: { paneManager.beginMainSplitDrag() },
                    onDragEnded: { paneManager.endMainSplitDrag() }
                ) { delta in
                    paneManager.updateMainSplit(delta: delta, totalWidth: geo.size.width)
                }
            }

            // RIGHT: Pane deck
            if paneManager.isActive {
                PaneDeckView(paneManager: paneManager)
                    .frame(width: paneColumnWidth, height: geo.size.height)
                    .clipped()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }
}

// MARK: - Pane Deck Policy

/// Layout constants shared by the deck and its slots. A pane that isn't
/// expanded collapses to zero width — its identity lives in the tab rail,
/// its body stays mounted off-slot so state survives the switch.
enum PaneSlotPresentationPolicy {
    static let minimumContentWidth: CGFloat = 420
    static let collapsedContentClearance: CGFloat = 60
    /// Gap between two expanded panes. Collapsed slots are zero-width and
    /// contribute no gap — two expanded panes separated by collapsed slots
    /// still read as one seam.
    static let expandedSlotSpacing: CGFloat = 6

    static func interSlotSpacing(leftIsExpanded: Bool, rightIsExpanded: Bool) -> CGFloat {
        (leftIsExpanded && rightIsExpanded) ? expandedSlotSpacing : 0
    }

    static func contentWidth(for expandedWidth: CGFloat) -> CGFloat {
        max(expandedWidth, minimumContentWidth)
    }

    static func contentOffset(isExpanded: Bool, expandedWidth: CGFloat) -> CGFloat {
        guard !isExpanded else { return 0 }
        return -(contentWidth(for: expandedWidth) + collapsedContentClearance)
    }
}

// MARK: - Pane Deck

/// The content deck. Panes keep their opening-order position so they don't
/// shuffle when focus moves; only slot widths animate. The focused pane's
/// environment carries the deck chrome payload — its own chrome row (or the
/// shell's standalone row) renders the tab strip, so tabs and mode tools
/// share one row of islands instead of stacking two bars.
struct PaneDeckView: View {
    @ObservedObject var paneManager: PaneManager

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Content layout widths from the last frame outside a continuous width
    /// stream (divider drag or window live resize). While a stream is live,
    /// pane bodies keep laying out at these widths and only the slot clip
    /// tracks the new width — a per-event content re-layout of a deep pane
    /// subtree (assistant pane ≈ 2^17 stack cost) queues transactions faster
    /// than they finish and wedges the app.
    @State private var restingContentWidths: [String: CGFloat] = [:]

    var body: some View {
        GeometryReader { geo in
            let layout = deckLayout(columnWidth: geo.size.width)
            slotRow(layout: layout)
                .animation(deckSpring, value: deckSignature)
                .onChange(of: layout.contentWidths) { _, widths in
                    guard !paneManager.isPaneContentLayoutFrozen else { return }
                    restingContentWidths = widths
                }
                // The width onChange can't refresh the snapshot when a freeze
                // ends — the thaw re-evaluation sees the same widths as the
                // last frozen frame. Without this, the NEXT freeze would trap
                // content at widths from before the previous one.
                .onChange(of: paneManager.isPaneContentLayoutFrozen) { _, frozen in
                    guard !frozen else { return }
                    restingContentWidths = layout.contentWidths
                }
                .onAppear { restingContentWidths = layout.contentWidths }
                .background(WindowLiveResizeObserver(
                    onBegan: { paneManager.beginWindowLiveResize() },
                    onEnded: { paneManager.endWindowLiveResize() }
                ))
        }
    }

    // MARK: Slots

    /// The width a pane body lays out at right now. Frozen while a divider
    /// drag or window live resize streams widths; live otherwise. Panes
    /// opened mid-stream fall through to the live layout.
    private func contentWidth(for paneId: String, layout: DeckLayout) -> CGFloat? {
        if paneManager.isPaneContentLayoutFrozen, let resting = restingContentWidths[paneId] {
            return resting
        }
        return layout.contentWidths[paneId]
    }

    private func slotRow(layout: DeckLayout) -> some View {
        let focusedId = paneManager.focusedPaneId ?? paneManager.panes.last?.id
        let payload = deckChromePayload(layout: layout, focusedId: focusedId)

        return HStack(spacing: 0) {
            ForEach(paneManager.panes, id: \.id) { pane in
                let slotWidth = layout.widths[pane.id] ?? 0
                PaneSlotView(
                    pane: pane,
                    isExpanded: layout.expandedIds.contains(pane.id),
                    isActive: paneManager.activePaneId == pane.id,
                    isContextOwner: paneManager.contextOwnerPaneId == pane.id,
                    deckChrome: pane.id == focusedId ? payload : nil,
                    expandedWidth: contentWidth(for: pane.id, layout: layout) ?? slotWidth,
                    slotWidth: slotWidth,
                    onClose: {
                        withAnimation(deckSpring) {
                            paneManager.closePane(pane)
                        }
                    }
                )
                .frame(width: slotWidth)

                if pane.id != paneManager.panes.last?.id {
                    Color.clear
                        .frame(width: layout.spacingAfter[pane.id] ?? 0)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: Deck chrome payload

    /// The focused pane's chrome handoff: every tab in deck order plus the
    /// deck mutations, pre-wrapped in the deck spring.
    private func deckChromePayload(layout: DeckLayout, focusedId: String?) -> PaneDeckChromePayload {
        let tabs = paneManager.panes.enumerated().map { index, pane in
            PaneDeckTab(
                content: pane,
                isFocused: pane.id == focusedId,
                isPinned: paneManager.pinnedPaneId == pane.id,
                position: index + 1
            )
        }
        let paneWidth = focusedId.flatMap { contentWidth(for: $0, layout: layout) }
            ?? PaneSlotPresentationPolicy.minimumContentWidth

        return PaneDeckChromePayload(
            tabs: tabs,
            actions: PaneDeckChromeActions(
                focus: { id in
                    withAnimation(deckSpring) { paneManager.focusPane(id) }
                },
                close: { id in
                    guard let pane = paneManager.panes.first(where: { $0.id == id }) else { return }
                    withAnimation(deckSpring) { paneManager.closePane(pane) }
                },
                togglePin: { id in
                    withAnimation(deckSpring) { paneManager.togglePin(id) }
                },
                move: { id, delta in
                    guard let index = paneManager.panes.firstIndex(where: { $0.id == id }) else { return }
                    withAnimation(deckSpring) { paneManager.movePane(id, toIndex: index + delta) }
                },
                closeOthers: { id in
                    withAnimation(deckSpring) { paneManager.closeOtherPanes(keeping: id) }
                }
            ),
            paneWidth: PaneDeckChromePayload.quantizedWidth(paneWidth)
        )
    }

    private var deckSpring: Animation? {
        reduceMotion ? .easeOut(duration: 0.12) : ProMotionSprings.focusTransition
    }

    /// One value that changes whenever the deck arrangement changes,
    /// so width changes animate as a single choreographed move.
    private var deckSignature: String {
        let ids = paneManager.panes.map(\.id).joined(separator: "|")
        return "\(ids)#\(paneManager.focusedPaneId ?? "")#\(paneManager.pinnedPaneId ?? "")"
    }

    // MARK: Layout

    private struct DeckLayout {
        var widths: [String: CGFloat]
        var expandedIds: Set<String>
        /// Per-pane width the content body lays out at: a pane's own expanded
        /// target width. Collapsed panes pre-lay their content at the focused
        /// width (what they'd get when focused) so expansion never reflows;
        /// a pinned pane lays out at its 40% slot, not the focused pane's 60%.
        var contentWidths: [String: CGFloat]
        var spacingAfter: [String: CGFloat]
    }

    private func deckLayout(columnWidth: CGFloat) -> DeckLayout {
        let panes = paneManager.panes
        guard !panes.isEmpty else {
            return DeckLayout(widths: [:], expandedIds: [], contentWidths: [:], spacingAfter: [:])
        }

        // There is always exactly one focused pane when panes exist.
        let focusedId = paneManager.focusedPaneId ?? panes.last!.id
        var expanded: Set<String> = [focusedId]
        if let pinned = paneManager.pinnedPaneId,
           pinned != focusedId,
           panes.contains(where: { $0.id == pinned }) {
            expanded.insert(pinned)
        }

        let spacingAfter = interSlotSpacing(for: panes, expandedIds: expanded)
        let totalSpacing = spacingAfter.values.reduce(0, +)
        let available = max(columnWidth - totalSpacing, 0)

        var widths: [String: CGFloat] = [:]
        let focusedWidth: CGFloat
        if expanded.count == 2 {
            focusedWidth = (available * 0.6).rounded()
            for pane in panes {
                if pane.id == focusedId {
                    widths[pane.id] = focusedWidth
                } else if expanded.contains(pane.id) {
                    widths[pane.id] = available - focusedWidth
                } else {
                    widths[pane.id] = 0
                }
            }
        } else {
            focusedWidth = available
            for pane in panes {
                widths[pane.id] = expanded.contains(pane.id) ? available : 0
            }
        }

        var contentWidths: [String: CGFloat] = [:]
        for pane in panes {
            contentWidths[pane.id] = expanded.contains(pane.id)
                ? (widths[pane.id] ?? focusedWidth)
                : focusedWidth
        }

        return DeckLayout(
            widths: widths,
            expandedIds: expanded,
            contentWidths: contentWidths,
            spacingAfter: spacingAfter
        )
    }

    /// Gaps only ever separate two *visible* panes: each expanded pane except
    /// the last expanded one carries the seam. Collapsed slots are zero-width
    /// and must not leave phantom gaps where a hidden pane sits.
    private func interSlotSpacing(for panes: [PaneContent], expandedIds: Set<String>) -> [String: CGFloat] {
        let expandedInOrder = panes.filter { expandedIds.contains($0.id) }
        guard expandedInOrder.count > 1 else { return [:] }

        var spacing: [String: CGFloat] = [:]
        for pane in expandedInOrder.dropLast() {
            spacing[pane.id] = PaneSlotPresentationPolicy.expandedSlotSpacing
        }
        return spacing
    }
}

// MARK: - Window Live Resize Observer

/// Invisible AppKit shim that reports the hosting window's live-resize span.
/// `viewWillStartLiveResize`/`viewDidEndLiveResize` arrive on every NSView in
/// the resizing window, so this needs no notification plumbing and is scoped
/// to the deck's own window for free.
private struct WindowLiveResizeObserver: NSViewRepresentable {
    let onBegan: () -> Void
    let onEnded: () -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onBegan = onBegan
        view.onEnded = onEnded
        return view
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {
        nsView.onBegan = onBegan
        nsView.onEnded = onEnded
    }

    final class ObserverView: NSView {
        var onBegan: () -> Void = {}
        var onEnded: () -> Void = {}

        override func viewWillStartLiveResize() {
            super.viewWillStartLiveResize()
            onBegan()
        }

        override func viewDidEndLiveResize() {
            super.viewDidEndLiveResize()
            onEnded()
        }

        // Leaving the window mid-resize would swallow the end callback and
        // freeze pane content forever — thaw on the way out.
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if window?.inLiveResize == true, newWindow !== window {
                onEnded()
            }
            super.viewWillMove(toWindow: newWindow)
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

// MARK: - Pane Slot

/// One deck slot. The pane body is always rendered (state survives collapse),
/// laid out at expanded width and clipped by the slot — content never reflows
/// during the slide. Structure is constant; only values animate.
private struct PaneSlotView: View {
    let pane: PaneContent
    let isExpanded: Bool
    let isActive: Bool
    let isContextOwner: Bool
    /// Non-nil only for the focused pane — its chrome row hosts the tab strip.
    let deckChrome: PaneDeckChromePayload?
    let expandedWidth: CGFloat
    let slotWidth: CGFloat
    let onClose: () -> Void

    var body: some View {
        let contentWidth = PaneSlotPresentationPolicy.contentWidth(for: expandedWidth)

        PaneContentView(
            content: pane,
            isActive: isActive,
            isContextOwner: isContextOwner,
            onClose: onClose
        )
        .environment(\.paneDeckChrome, deckChrome)
        .frame(width: contentWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        // NSView-backed editors and scroll views can keep painting through
        // opacity/clipping. Move collapsed content out of the slot while
        // keeping it mounted at its expanded layout width.
        .offset(x: PaneSlotPresentationPolicy.contentOffset(
            isExpanded: isExpanded,
            expandedWidth: expandedWidth
        ))
        // The content's layout must NEVER animate — only the slot clip
        // slides. Animating text-view widths relayouts every frame and
        // tanks the deck to single-digit FPS with long notes.
        .transaction { $0.animation = nil }
        .opacity(isExpanded ? 1 : 0)
        .allowsHitTesting(isExpanded)
        .accessibilityHidden(!isExpanded)
        // Collapsing content must outlive the width spring (~0.3s) — a fast
        // fade leaves the still-wide slot as a blank veil mid-slide.
        .animation(.easeOut(duration: isExpanded ? 0.12 : 0.3), value: isExpanded)
        .frame(width: slotWidth, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Pane Info

/// Glyph, tint, and title resolution for any pane content.
@MainActor
enum PaneInfo {

    static func glyph(for content: PaneContent) -> String {
        switch content {
        case .entity(let entity): return entity.type.icon
        case .thinkspace: return "rectangle.3.group"
        case .commandCenter: return "square.grid.2x2"
        case .swipeGallery: return "bookmark"
        case .webBrowser: return "globe"
        case .cosmoWindow: return "brain.head.profile"
        case .collaborator: return "person.2"
        case .inlineAssistant: return "sparkles"
        }
    }

    static func tint(for content: PaneContent) -> Color {
        switch content {
        case .entity(let entity): return entity.type.color
        case .thinkspace: return DS.accent
        case .commandCenter: return DS.accent
        case .swipeGallery: return DS.entityIdea
        case .webBrowser: return DS.textSecondary
        case .cosmoWindow, .collaborator, .inlineAssistant: return DS.accent
        }
    }

    static func fallbackTitle(for content: PaneContent) -> String {
        switch content {
        case .entity(let entity):
            return entity.type.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        case .thinkspace: return "Thinkspace"
        case .commandCenter: return "Command Center"
        case .swipeGallery: return "Swipe File"
        case .webBrowser(_, let url, let title): return title ?? url.host() ?? "Web"
        case .cosmoWindow: return "Cosmo"
        case .collaborator: return "Collaborator"
        case .inlineAssistant: return "Assistant"
        }
    }

    /// Resolve the real title (atom title for entities, thinkspace name for canvases).
    static func title(for content: PaneContent) async -> String {
        switch content {
        case .entity(let entity):
            if let atom = try? await AtomRepository.shared.fetch(id: entity.id),
               let atomTitle = atom.title, !atomTitle.isEmpty {
                return atomTitle
            }
            return fallbackTitle(for: content)
        case .thinkspace(let thinkspaceId):
            if let atom = try? await AtomRepository.shared.fetch(uuid: thinkspaceId),
               let atomTitle = atom.title, !atomTitle.isEmpty {
                return atomTitle
            }
            return fallbackTitle(for: content)
        default:
            return fallbackTitle(for: content)
        }
    }
}

// MARK: - Pane Divider

/// Draggable resize handle between main content and the pane column.
struct PaneDivider: View {
    let isVertical: Bool
    var onDragBegan: (() -> Void)? = nil
    var onDragEnded: (() -> Void)? = nil
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
                        onDragBegan?()
                    }
                    let currentValue = isVertical ? value.translation.width : value.translation.height
                    let delta = currentValue - lastDragValue
                    lastDragValue = currentValue
                    onDrag(delta)
                }
                .onEnded { _ in
                    isDragging = false
                    lastDragValue = 0
                    onDragEnded?()
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
