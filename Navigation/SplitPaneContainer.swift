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
                PaneDivider(isVertical: true) { delta in
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
    /// Height of the tab rail row (tab content + rail padding).
    static let tabRailHeight: CGFloat = 36

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

/// The tab rail + content deck. Tabs keep their opening-order position so
/// they don't shuffle when focus moves; only slot widths animate.
struct PaneDeckView: View {
    @ObservedObject var paneManager: PaneManager

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let layout = deckLayout(columnWidth: geo.size.width)

            VStack(spacing: PaneSlotPresentationPolicy.expandedSlotSpacing) {
                if paneManager.panes.count > 1 {
                    PaneTabRail(paneManager: paneManager, deckSpring: deckSpring)
                }
                slotRow(layout: layout)
                    .frame(maxHeight: .infinity)
            }
            .animation(deckSpring, value: deckSignature)
        }
    }

    // MARK: Slots

    private func slotRow(layout: DeckLayout) -> some View {
        HStack(spacing: 0) {
            ForEach(paneManager.panes, id: \.id) { pane in
                let slotWidth = layout.widths[pane.id] ?? 0
                PaneSlotView(
                    pane: pane,
                    isExpanded: layout.expandedIds.contains(pane.id),
                    isActive: paneManager.activePaneId == pane.id,
                    isContextOwner: paneManager.contextOwnerPaneId == pane.id,
                    expandedWidth: layout.contentWidths[pane.id] ?? slotWidth,
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

// MARK: - Pane Tab Rail

/// One glass strip naming every open pane — the Safari/Xcode tab grammar.
/// Tabs are flat capsules inside the glass (never glass-on-glass); the
/// focused tab's fill slides between positions via matched geometry.
private struct PaneTabRail: View {
    @ObservedObject var paneManager: PaneManager
    let deckSpring: Animation?

    @Namespace private var selectionNamespace

    // Drag-to-reorder (the Safari gesture): the dragged tab follows the
    // pointer rigidly while its neighbors spring around it. Reorders commit
    // live at half-tab thresholds — releasing never snaps to a surprise slot.
    @State private var draggedPaneId: String?
    @State private var dragIsTracking = false
    @State private var dragTranslation: CGFloat = 0
    @State private var dragBaseline: CGFloat = 0
    @State private var tabWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: DS.space4) {
            ForEach(Array(paneManager.panes.enumerated()), id: \.element.id) { index, pane in
                tab(for: pane, at: index)
            }
        }
        .padding(DS.space4)
        .frame(height: PaneSlotPresentationPolicy.tabRailHeight)
        .cosmoGlassPanel(role: .floatingAssistant, cornerRadius: 18)
    }

    private var focusedId: String? {
        paneManager.focusedPaneId ?? paneManager.panes.last?.id
    }

    // MARK: Tabs

    private func tab(for pane: PaneContent, at index: Int) -> some View {
        PaneTabView(
            pane: pane,
            position: index + 1,
            paneCount: paneManager.panes.count,
            isFocused: focusedId == pane.id,
            isPinned: paneManager.pinnedPaneId == pane.id,
            selectionNamespace: selectionNamespace,
            onFocus: {
                // A completed drag releases over the tab it moved — that
                // mouse-up must not read as a focus click.
                guard draggedPaneId == nil else { return }
                withAnimation(deckSpring) { paneManager.focusPane(pane.id) }
            },
            onClose: { withAnimation(deckSpring) { paneManager.closePane(pane) } },
            onTogglePin: { withAnimation(deckSpring) { paneManager.togglePin(pane.id) } },
            onCloseOthers: { withAnimation(deckSpring) { paneManager.closeOtherPanes(keeping: pane.id) } },
            onMove: { delta in
                withAnimation(deckSpring) { paneManager.movePane(pane.id, toIndex: index + delta) }
            }
        )
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            tabWidth = width
        }
        .offset(x: pane.id == draggedPaneId ? dragTranslation : 0)
        .zIndex(pane.id == draggedPaneId ? 1 : 0)
        // While tracking, the dragged tab is pinned to the pointer: its slot
        // change from a live reorder and its offset compensation must both
        // land in the same frame, unanimated. Neighbors animate normally.
        .transaction { transaction in
            if pane.id == draggedPaneId && dragIsTracking {
                transaction.animation = nil
            }
        }
        .simultaneousGesture(reorderGesture(for: pane))
    }

    // MARK: Reorder gesture

    private func reorderGesture(for pane: PaneContent) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if draggedPaneId != pane.id {
                    draggedPaneId = pane.id
                    dragBaseline = 0
                    dragIsTracking = true
                }
                updateDrag(for: pane, translation: value.translation.width)
            }
            .onEnded { _ in settleDrag() }
    }

    /// Commit a reorder every time the pointer crosses half a tab beyond the
    /// dragged tab's current slot; `dragBaseline` re-zeroes the translation
    /// after each commit so the tab never visually jumps.
    private func updateDrag(for pane: PaneContent, translation: CGFloat) {
        guard tabWidth > 0 else { return }
        let step = tabWidth + DS.space4
        var offset = translation - dragBaseline
        var index = paneManager.panes.firstIndex(where: { $0.id == pane.id }) ?? 0

        while offset > step / 2, index < paneManager.panes.count - 1 {
            paneManager.movePane(pane.id, toIndex: index + 1)
            index += 1
            dragBaseline += step
            offset -= step
        }
        while offset < -step / 2, index > 0 {
            paneManager.movePane(pane.id, toIndex: index - 1)
            index -= 1
            dragBaseline -= step
            offset += step
        }
        dragTranslation = offset
    }

    /// Spring the released tab home, keep it floating above its neighbors
    /// until the settle finishes, then release the drag state.
    private func settleDrag() {
        dragIsTracking = false
        withAnimation(deckSpring) { dragTranslation = 0 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !dragIsTracking else { return }
            draggedPaneId = nil
            dragBaseline = 0
        }
    }
}

/// One tab: the pane's identity glyph in its entity tint + the live title.
/// Hover swaps the glyph for the close affordance (the Safari gesture).
/// The focused tab wears the elevated fill; a pinned pane is also on screen,
/// so its tab keeps a quieter version of the same fill plus the pin mark.
private struct PaneTabView: View {
    let pane: PaneContent
    let position: Int
    let paneCount: Int
    let isFocused: Bool
    let isPinned: Bool
    let selectionNamespace: Namespace.ID
    let onFocus: () -> Void
    let onClose: () -> Void
    let onTogglePin: () -> Void
    let onCloseOthers: () -> Void
    /// Move this tab by a slot delta (−1 left, +1 right) — the keyboard-
    /// reachable path to the same reorder the drag gesture performs.
    let onMove: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var title: String = ""

    private var displayTitle: String {
        title.isEmpty ? PaneInfo.fallbackTitle(for: pane) : title
    }

    var body: some View {
        Button(action: onFocus) {
            tabLabel
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : ProMotionSprings.hover) {
                isHovered = hovering
            }
        }
        .contextMenu { tabMenu }
        .help("\(displayTitle) (⌘⌃\(position))")
        .accessibilityLabel("\(displayTitle) pane")
        .accessibilityAddTraits(isFocused ? [.isSelected] : [])
        .task(id: pane.id) {
            title = await PaneInfo.title(for: pane)
        }
    }

    // MARK: Pieces

    private var tabLabel: some View {
        HStack(spacing: DS.space6) {
            leadingMark
            Text(displayTitle)
                .font(DS.buttonText)
                .foregroundStyle(isFocused ? DS.text : DS.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(DS.caption2)
                    .foregroundStyle(DS.accent)
                    .accessibilityLabel("Pinned")
            }
        }
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space6)
        .frame(maxWidth: .infinity)
        .background { hoverFill }
        .background { selectionFill }
        .contentShape(Capsule())
    }

    /// Constant-structure hover wash — opacity-driven, never inserted.
    private var hoverFill: some View {
        Capsule()
            .fill(DS.glassSectionFill)
            .opacity(isHovered && !isFocused && !isPinned ? 1 : 0)
    }

    /// The focused tab's fill slides between rail positions (matched
    /// geometry); a pinned-but-unfocused tab keeps a quieter static fill
    /// because its pane is still on screen.
    @ViewBuilder
    private var selectionFill: some View {
        if isFocused {
            Capsule()
                .fill(DS.surfaceElevated)
                .matchedGeometryEffect(id: "pane-tab-selection", in: selectionNamespace)
        } else if isPinned {
            Capsule().fill(DS.surfaceElevated.opacity(0.55))
        }
    }

    /// 16pt identity slot: entity-tinted glyph at rest, close button on hover.
    private var leadingMark: some View {
        ZStack {
            Image(systemName: PaneInfo.glyph(for: pane))
                .font(DS.caption.weight(.medium))
                .foregroundStyle(PaneInfo.tint(for: pane).opacity(isFocused ? 1 : 0.7))
                .opacity(isHovered ? 0 : 1)
                .accessibilityHidden(true)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Circle().inset(by: -8))
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
            .help("Close pane")
            .accessibilityLabel("Close \(displayTitle)")
        }
        .frame(width: 16, height: 16)
    }

    @ViewBuilder
    private var tabMenu: some View {
        Button(isPinned ? "Unpin Pane" : "Pin Pane", action: onTogglePin)
        Divider()
        Button("Move Pane Left") { onMove(-1) }
            .disabled(position == 1)
        Button("Move Pane Right") { onMove(1) }
            .disabled(position == paneCount)
        Divider()
        Button("Close Pane", action: onClose)
        Button("Close Other Panes", action: onCloseOthers)
            .disabled(paneCount == 1)
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
        case .webBrowser(let url, let title): return title ?? url.host() ?? "Web"
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
