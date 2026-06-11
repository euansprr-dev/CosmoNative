// CosmoOS/Navigation/SplitPaneContainer.swift
// Split-pane layout system — wraps main content with the pane deck column.
// Deck model: one focused pane at reading width (plus an optional pinned pane);
// every other pane collapses to a 44pt spine. Panes queue for attention
// instead of competing for space.

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

// MARK: - Pane Deck

/// The focus + spine deck. Spines keep their opening-order position so they
/// don't shuffle when focus moves; only widths animate.
struct PaneDeckView: View {
    @ObservedObject var paneManager: PaneManager

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let spineWidth: CGFloat = 44
    private let slotSpacing: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let layout = deckLayout(columnWidth: geo.size.width)

            HStack(spacing: slotSpacing) {
                ForEach(Array(paneManager.panes.enumerated()), id: \.element.id) { index, pane in
                    let slotWidth = layout.widths[pane.id] ?? spineWidth
                    PaneSlotView(
                        pane: pane,
                        isExpanded: layout.expandedIds.contains(pane.id),
                        isPinned: paneManager.pinnedPaneId == pane.id,
                        isActive: paneManager.activePaneId == pane.id,
                        isContextOwner: paneManager.contextOwnerPaneId == pane.id,
                        expandedWidth: layout.focusedWidth,
                        position: index + 1,
                        onFocus: {
                            withAnimation(deckSpring) {
                                paneManager.focusPane(pane.id)
                            }
                        },
                        onClose: {
                            withAnimation(deckSpring) {
                                paneManager.closePane(pane)
                            }
                        }
                    )
                    .frame(width: slotWidth)
                }
            }
            .animation(deckSpring, value: deckSignature)
        }
        .padding(.vertical, 0)
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
        var focusedWidth: CGFloat
    }

    private func deckLayout(columnWidth: CGFloat) -> DeckLayout {
        let panes = paneManager.panes
        guard !panes.isEmpty else {
            return DeckLayout(widths: [:], expandedIds: [], focusedWidth: 0)
        }

        // There is always exactly one focused pane when panes exist.
        let focusedId = paneManager.focusedPaneId ?? panes.last!.id
        var expanded: Set<String> = [focusedId]
        if let pinned = paneManager.pinnedPaneId,
           pinned != focusedId,
           panes.contains(where: { $0.id == pinned }) {
            expanded.insert(pinned)
        }

        let spineCount = panes.count - expanded.count
        let totalSpacing = slotSpacing * CGFloat(max(panes.count - 1, 0))
        let available = max(columnWidth - CGFloat(spineCount) * spineWidth - totalSpacing, 0)

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
                    widths[pane.id] = spineWidth
                }
            }
        } else {
            focusedWidth = available
            for pane in panes {
                widths[pane.id] = expanded.contains(pane.id) ? available : spineWidth
            }
        }

        return DeckLayout(widths: widths, expandedIds: expanded, focusedWidth: focusedWidth)
    }
}

// MARK: - Pane Slot

/// One deck slot. The pane body is always rendered (state survives collapse),
/// laid out at expanded width and clipped by the slot — content never reflows
/// during the slide. Structure is constant; only values animate.
private struct PaneSlotView: View {
    let pane: PaneContent
    let isExpanded: Bool
    let isPinned: Bool
    let isActive: Bool
    let isContextOwner: Bool
    let expandedWidth: CGFloat
    let position: Int
    let onFocus: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            PaneContentView(
                content: pane,
                isActive: isActive,
                isContextOwner: isContextOwner,
                onClose: onClose
            )
            .frame(width: max(expandedWidth, 420))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            // The content's layout must NEVER animate — only the slot clip
            // slides. Animating text-view widths relayouts every frame and
            // tanks the deck to single-digit FPS with long notes.
            .transaction { $0.animation = nil }
            .opacity(isExpanded ? 1 : 0)
            .allowsHitTesting(isExpanded)
            .accessibilityHidden(!isExpanded)
            .animation(.easeOut(duration: 0.1), value: isExpanded)

            PaneSpineView(
                pane: pane,
                position: position,
                onFocus: onFocus,
                onClose: onClose
            )
            .opacity(isExpanded ? 0 : 1)
            .allowsHitTesting(!isExpanded)
            .animation(.easeOut(duration: 0.1), value: isExpanded)
        }
        .overlay(alignment: .topLeading) {
            if isPinned && isExpanded {
                pinnedBadge
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var pinnedBadge: some View {
        Image(systemName: "pin.fill")
            .font(DS.caption2)
            .foregroundStyle(DS.accent)
            .padding(5)
            .background(Circle().fill(DS.accentSoft))
            .padding(8)
            .help("Pinned — stays open beside the focused pane (⌘⌥P)")
            .accessibilityLabel("Pinned pane")
    }
}

// MARK: - Pane Spine

/// A collapsed pane: 44pt bar with the type glyph up top, the title running
/// vertically, and the entity tint as a leading rule. Click — or rest the
/// pointer on it — to focus. Hover reveals the close affordance.
private struct PaneSpineView: View {
    let pane: PaneContent
    let position: Int
    let onFocus: () -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var title: String = ""
    @State private var dwellTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 10) {
            topGlyph
            verticalTitle
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(spineBackground)
        .overlay(alignment: .leading) { tintRule }
        .overlay(spineBorder)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture(perform: onFocus)
        .onHover(perform: handleHover)
        .help("\(title.isEmpty ? PaneSpineInfo.fallbackTitle(for: pane) : title) (⌘⌃\(position))")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title.isEmpty ? PaneSpineInfo.fallbackTitle(for: pane) : title) pane, collapsed")
        .accessibilityAddTraits(.isButton)
        .task(id: pane.id) {
            title = await PaneSpineInfo.title(for: pane)
        }
        .onDisappear {
            dwellTask?.cancel()
            dwellTask = nil
        }
    }

    // MARK: Pieces

    private var topGlyph: some View {
        ZStack {
            Image(systemName: PaneSpineInfo.glyph(for: pane))
                .font(DS.subheadline)
                .foregroundStyle(PaneSpineInfo.tint(for: pane))
                .opacity(isHovered ? 0 : 1)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(DS.glassSectionFill))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
            .help("Close pane")
            .accessibilityLabel("Close pane")
        }
        .frame(width: 28, height: 28)
        .animation(reduceMotion ? nil : ProMotionSprings.hover, value: isHovered)
    }

    private var verticalTitle: some View {
        Text(title.isEmpty ? PaneSpineInfo.fallbackTitle(for: pane) : title)
            .font(DS.subheadline.weight(.medium))
            .foregroundStyle(isHovered ? DS.text : DS.textSecondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: 168, alignment: .leading)
            .rotationEffect(.degrees(90), anchor: .center)
            .frame(width: 28, height: 176)
    }

    private var tintRule: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(PaneSpineInfo.tint(for: pane))
            .frame(width: 2)
            .padding(.vertical, 8)
    }

    private var spineBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isHovered ? DS.glassSectionFill : DS.glassCardFill)
    }

    private var spineBorder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(DS.glassBorder, lineWidth: 0.5)
    }

    // MARK: Hover dwell

    /// Resting the pointer on a spine for a beat focuses it — reading the deck
    /// becomes pure pointer travel, no clicks. (Click still works instantly.)
    private func handleHover(_ hovering: Bool) {
        withAnimation(reduceMotion ? nil : ProMotionSprings.hover) {
            isHovered = hovering
        }
        dwellTask?.cancel()
        guard hovering else {
            dwellTask = nil
            return
        }
        dwellTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            onFocus()
        }
    }
}

// MARK: - Spine Info

/// Glyph, tint, and title resolution for any pane content.
@MainActor
enum PaneSpineInfo {

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
