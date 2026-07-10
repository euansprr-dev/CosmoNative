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
                    .onDisappear {
                        // Fires when the slide-out transition completes — the
                        // deck is truly off screen, canvas captures are safe
                        // again. Guarded: if a pane reopened mid-transition, a
                        // stale instance's disappearance must not clear it.
                        if !paneManager.isActive {
                            PaneDeckPresentationState.shared.setOnScreen(false)
                        }
                    }
            }
        }
    }
}

// MARK: - Pane Deck

/// Width of a collapsed pane spine. Shared by the deck layout and the slot so
/// the spine never stretches to fill a slot that is mid-collapse.
enum PaneSlotPresentationPolicy {
    static let spineWidth: CGFloat = 44
    static let minimumContentWidth: CGFloat = 420
    static let collapsedContentClearance: CGFloat = 60
    /// Dwell is the commit gesture; the hover caption is the glance. 300ms is
    /// long enough to read a caption and retreat, short enough that a
    /// deliberate rest still feels instant. (Was 150ms when spines were
    /// anonymous bars and hover had nothing to say.)
    static let hoverDwellMilliseconds = 300
    static let defaultInterSlotSpacing: CGFloat = 6
    /// Extra width the hovered spine borrows from the focused pane — the page
    /// slides out from under the stack a touch before dwell commits.
    static let spineHoverReveal: CGFloat = 12
    /// Scale at which the page-edge sliver renders the pane's pixels. Small
    /// enough to read as texture (Stage Manager-style impression), large
    /// enough that a document's title strokes stay recognizable.
    static let sliverScale: CGFloat = 0.32
    /// Width of pane content (in points) the sliver capture needs to cover
    /// the spine at full hover reveal.
    static var sliverSourceWidth: CGFloat { (spineWidth + spineHoverReveal) / sliverScale }

    static func interSlotSpacing(leftIsExpanded: Bool, rightIsExpanded: Bool) -> CGFloat {
        if !leftIsExpanded && rightIsExpanded { return 0 }
        return defaultInterSlotSpacing
    }

    static func contentWidth(for expandedWidth: CGFloat) -> CGFloat {
        max(expandedWidth, minimumContentWidth)
    }

    static func contentOffset(isExpanded: Bool, expandedWidth: CGFloat) -> CGFloat {
        guard !isExpanded else { return 0 }
        return -(contentWidth(for: expandedWidth) + spineWidth + collapsedContentClearance)
    }
}

private let paneSpineWidth: CGFloat = PaneSlotPresentationPolicy.spineWidth

/// The focus + spine deck. Spines keep their opening-order position so they
/// don't shuffle when focus moves; only widths animate.
struct PaneDeckView: View {
    @ObservedObject var paneManager: PaneManager

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hoveredSpineId: String?

    private let spineWidth: CGFloat = paneSpineWidth

    var body: some View {
        GeometryReader { geo in
            let layout = deckLayout(columnWidth: geo.size.width)

            HStack(spacing: 0) {
                ForEach(Array(paneManager.panes.enumerated()), id: \.element.id) { index, pane in
                    let slotWidth = layout.widths[pane.id] ?? spineWidth
                    PaneSlotView(
                        pane: pane,
                        isExpanded: layout.expandedIds.contains(pane.id),
                        isPinned: paneManager.pinnedPaneId == pane.id,
                        isActive: paneManager.activePaneId == pane.id,
                        isContextOwner: paneManager.contextOwnerPaneId == pane.id,
                        isSpineHovered: hoveredSpineId == pane.id,
                        expandedWidth: layout.contentWidths[pane.id] ?? slotWidth,
                        slotWidth: slotWidth,
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
                        },
                        onSpineHover: { hovering in
                            if hovering {
                                hoveredSpineId = pane.id
                            } else if hoveredSpineId == pane.id {
                                hoveredSpineId = nil
                            }
                        }
                    )
                    .frame(width: slotWidth)

                    if index < paneManager.panes.count - 1 {
                        Color.clear
                            .frame(width: layout.spacingAfter[pane.id] ?? 0)
                            .allowsHitTesting(false)
                    }
                }
            }
            .animation(deckSpring, value: deckSignature)
            .overlayPreferenceValue(PaneSpineCaptionPreferenceKey.self) { captions in
                spineCaptionOverlay(captions)
            }
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
        return "\(ids)#\(paneManager.focusedPaneId ?? "")#\(paneManager.pinnedPaneId ?? "")#\(hoveredSpineId ?? "")"
    }

    /// Floating glass caption beside the hovered spine — the title in reading
    /// orientation, where rotated spine text used to be.
    @ViewBuilder
    private func spineCaptionOverlay(_ captions: [PaneSpineCaptionValue]) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.clear
                ForEach(captions, id: \.paneId) { caption in
                    let rect = proxy[caption.bounds]
                    PaneSpineCaptionPill(caption: caption)
                        .fixedSize()
                        .alignmentGuide(.leading) { d in
                            -(max(8, rect.minX - 10 - d.width))
                        }
                        .alignmentGuide(.top) { _ in
                            -(rect.minY + 14)
                        }
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : ProMotionSprings.hover, value: captions.map(\.paneId))
        }
        .allowsHitTesting(false)
    }

    // MARK: Layout

    private struct DeckLayout {
        var widths: [String: CGFloat]
        var expandedIds: Set<String>
        /// Per-pane width the content body lays out at: a pane's own expanded
        /// target width. Collapsed spines pre-lay their content at the focused
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

        let spineCount = panes.count - expanded.count
        let spacingAfter = interSlotSpacing(for: panes, expandedIds: expanded)
        let totalSpacing = spacingAfter.values.reduce(0, +)
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

        var contentWidths: [String: CGFloat] = [:]
        for pane in panes {
            contentWidths[pane.id] = expanded.contains(pane.id)
                ? (widths[pane.id] ?? focusedWidth)
                : focusedWidth
        }

        // Page-edge hover reveal: the hovered spine borrows a little width
        // from the focused pane, so the page slides out from under the stack.
        // Content widths are computed above from the un-borrowed layout —
        // only clips move on hover, content never reflows.
        if let hovered = hoveredSpineId,
           !expanded.contains(hovered),
           let hoveredWidth = widths[hovered],
           let currentFocusedWidth = widths[focusedId],
           currentFocusedWidth - PaneSlotPresentationPolicy.spineHoverReveal > PaneSlotPresentationPolicy.minimumContentWidth {
            widths[hovered] = hoveredWidth + PaneSlotPresentationPolicy.spineHoverReveal
            widths[focusedId] = currentFocusedWidth - PaneSlotPresentationPolicy.spineHoverReveal
        }

        return DeckLayout(
            widths: widths,
            expandedIds: expanded,
            contentWidths: contentWidths,
            spacingAfter: spacingAfter
        )
    }

    private func interSlotSpacing(for panes: [PaneContent], expandedIds: Set<String>) -> [String: CGFloat] {
        guard panes.count > 1 else { return [:] }

        var spacing: [String: CGFloat] = [:]
        for index in panes.indices.dropLast() {
            let leftPane = panes[index]
            let rightPane = panes[index + 1]
            spacing[leftPane.id] = PaneSlotPresentationPolicy.interSlotSpacing(
                leftIsExpanded: expandedIds.contains(leftPane.id),
                rightIsExpanded: expandedIds.contains(rightPane.id)
            )
        }
        return spacing
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
    let isSpineHovered: Bool
    let expandedWidth: CGFloat
    let slotWidth: CGFloat
    let position: Int
    let onFocus: () -> Void
    let onClose: () -> Void
    let onSpineHover: (Bool) -> Void

    var body: some View {
        let contentWidth = PaneSlotPresentationPolicy.contentWidth(for: expandedWidth)

        ZStack(alignment: .leading) {
            PaneContentView(
                content: pane,
                isActive: isActive,
                isContextOwner: isContextOwner,
                onClose: onClose
            )
            .frame(width: contentWidth)
            // Invisible anchor tracking the content's frame — PaneManager
            // snapshots this region the instant before the pane collapses,
            // and the spine shows those pixels as its page edge.
            .background {
                PaneSpineSnapshotAnchor(paneId: pane.id)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            // NSView-backed editors and scroll views can keep painting through
            // opacity/clipping. Move collapsed content out of the spine slot
            // while keeping it mounted at its expanded layout width.
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
            .zIndex(isExpanded ? 1 : 0)
            // Collapsing content must outlive the width spring (~0.3s) — a fast
            // fade leaves the still-wide slot as a blank veil mid-slide.
            .animation(.easeOut(duration: isExpanded ? 0.12 : 0.3), value: isExpanded)

            PaneSpineView(
                pane: pane,
                position: position,
                isInteractive: !isExpanded,
                onFocus: onFocus,
                onClose: onClose,
                onHoverChange: onSpineHover
            )
            // Fixed spine width: the slot is wider than 44pt for most of the
            // collapse spring, and a maxWidth-infinity spine would stretch
            // across it as a half-screen glass sheet. Hover adds the reveal
            // (the slot widens in lockstep via the deck layout).
            .frame(width: paneSpineWidth + (isSpineHovered ? PaneSlotPresentationPolicy.spineHoverReveal : 0))
            .opacity(isExpanded ? 0 : 1)
            .allowsHitTesting(!isExpanded)
            .zIndex(isExpanded ? 0 : 1)
            .animation(.easeOut(duration: 0.15).delay(isExpanded ? 0 : 0.15), value: isExpanded)
        }
        .frame(width: slotWidth, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .leading)
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

/// A collapsed pane rendered as a page edge: the pane's own pixels (captured
/// the instant before collapse) peek out as a sliver of paper, tucked under
/// the focused pane — no glyph, no rotated label. The entity tint survives as
/// a thin binding rule. Hover pulls the page out a touch and floats a glass
/// caption with the title; click — or rest the pointer for a beat — to focus.
private struct PaneSpineView: View {
    let pane: PaneContent
    let position: Int
    /// False while the slot is expanded — the spine is then an invisible
    /// crossfade layer and must never react to hover or schedule dwell focus.
    let isInteractive: Bool
    let onFocus: () -> Void
    let onClose: () -> Void
    /// Reports hover to the deck, which widens this slot by the hover reveal.
    let onHoverChange: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var title: String = ""
    @State private var dwellTask: Task<Void, Never>?

    private var displayTitle: String {
        title.isEmpty ? PaneSpineInfo.fallbackTitle(for: pane) : title
    }

    var body: some View {
        pageEdge
            .overlay(alignment: .leading) { tintRule }
            .overlay(alignment: .top) { closeButton }
            .overlay(spineBorder)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onTapGesture(perform: onFocus)
            .onHover(perform: handleHover)
            .anchorPreference(
                key: PaneSpineCaptionPreferenceKey.self,
                value: .bounds,
                transform: captionPreference
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(displayTitle) pane, collapsed")
            .accessibilityAddTraits(.isButton)
            .task(id: pane.id) {
                title = await PaneSpineInfo.title(for: pane)
            }
            .onChange(of: isInteractive) { _, interactive in
                // The slot expanded under the pointer — hover-exit won't fire
                // for the now-hidden spine, so clear dwell and hover manually.
                if !interactive {
                    dwellTask?.cancel()
                    dwellTask = nil
                    isHovered = false
                    onHoverChange(false)
                }
            }
            .onDisappear {
                dwellTask?.cancel()
                dwellTask = nil
                onHoverChange(false)
            }
    }

    // MARK: Pieces

    /// The paper: pane background with the captured sliver of real content on
    /// top, fading into blank paper. Recessed under a faint wash at rest; the
    /// wash lifts on hover — the page pulled forward.
    private var pageEdge: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DS.bg)

            if let sliver = PaneSpineSnapshotStore.shared.slivers[pane.id] {
                sliverImage(sliver)
            } else {
                fallbackGlyph
            }

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DS.text.opacity(isHovered ? 0 : 0.04))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(reduceMotion ? nil : ProMotionSprings.hover, value: isHovered)
    }

    private func sliverImage(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [DS.bg.opacity(0), DS.bg],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 48)
            }
            .accessibilityHidden(true)
    }

    /// Pre-first-collapse only (no pixels captured yet): quiet paper with the
    /// type glyph — never a rotated label.
    private var fallbackGlyph: some View {
        Image(systemName: PaneSpineInfo.glyph(for: pane))
            .font(DS.subheadline)
            .foregroundStyle(PaneSpineInfo.tint(for: pane).opacity(0.85))
            .frame(width: paneSpineWidth, height: 44)
            .accessibilityHidden(true)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(DS.glassSectionFill))
                .contentShape(Circle().inset(by: -6))
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
        .opacity(isHovered ? 1 : 0)
        .allowsHitTesting(isHovered && isInteractive)
        .onHover { inside in
            // Pointer intent on the close affordance is "close", not "focus" —
            // hold the dwell while it's there, resume when it leaves.
            if inside {
                dwellTask?.cancel()
            } else if isHovered && isInteractive {
                scheduleDwell()
            }
        }
        .help("Close pane")
        .accessibilityLabel("Close pane")
        .animation(reduceMotion ? nil : ProMotionSprings.hover, value: isHovered)
    }

    private var tintRule: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(PaneSpineInfo.tint(for: pane))
            .frame(width: 2)
            .padding(.vertical, 8)
    }

    private var spineBorder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(DS.glassBorder, lineWidth: 0.5)
    }

    private func captionPreference(_ anchor: Anchor<CGRect>) -> [PaneSpineCaptionValue] {
        guard isHovered && isInteractive else { return [] }
        return [PaneSpineCaptionValue(
            paneId: pane.id,
            title: displayTitle,
            shortcut: "⌘⌃\(position)",
            tint: PaneSpineInfo.tint(for: pane),
            bounds: anchor
        )]
    }

    // MARK: Hover dwell

    /// Resting the pointer on a spine for a beat focuses it — reading the deck
    /// becomes pure pointer travel, no clicks. (Click still works instantly.)
    private func handleHover(_ hovering: Bool) {
        // Hover can fire for the hidden spine layer of an expanded slot
        // (allowsHitTesting doesn't tear down hover tracking) — never let it
        // schedule a dwell there or the deck refocuses under a resting pointer.
        let active = hovering && isInteractive
        withAnimation(reduceMotion ? nil : ProMotionSprings.hover) {
            isHovered = active
        }
        onHoverChange(active)
        dwellTask?.cancel()
        guard active else {
            dwellTask = nil
            return
        }
        scheduleDwell()
    }

    private func scheduleDwell() {
        dwellTask?.cancel()
        dwellTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(PaneSlotPresentationPolicy.hoverDwellMilliseconds))
            guard !Task.isCancelled else { return }
            onFocus()
        }
    }
}

// MARK: - Spine Caption

/// Payload a hovered spine publishes for the deck-level caption overlay.
private struct PaneSpineCaptionValue {
    let paneId: String
    let title: String
    let shortcut: String
    let tint: Color
    let bounds: Anchor<CGRect>
}

private struct PaneSpineCaptionPreferenceKey: PreferenceKey {
    static let defaultValue: [PaneSpineCaptionValue] = []
    static func reduce(value: inout [PaneSpineCaptionValue], nextValue: () -> [PaneSpineCaptionValue]) {
        value.append(contentsOf: nextValue())
    }
}

/// The hovered spine's title in reading orientation — a small floating glass
/// capsule beside the page edge, where rotated spine text used to be.
private struct PaneSpineCaptionPill: View {
    let caption: PaneSpineCaptionValue

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(caption.tint)
                .frame(width: 6, height: 6)
            Text(caption.title)
                .font(DS.subheadline.weight(.medium))
                .foregroundStyle(DS.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 220, alignment: .leading)
            Text(caption.shortcut)
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
        .accessibilityHidden(true)
    }
}

// MARK: - Page-Edge Snapshot Store

/// The spine is a page edge: it shows the pane's real pixels, captured the
/// instant before a focus change collapses the pane (PaneManager calls
/// `capture` while the old layout is still on screen). Same window-layer
/// `cacheDisplay` path as canvas thumbnails — the scale-not-crop semantics
/// this relies on are pinned by CanvasScreenshotScaledCaptureTests.
@MainActor
@Observable
final class PaneSpineSnapshotStore {
    static let shared = PaneSpineSnapshotStore()

    /// paneId → downsampled page-edge image, sized for direct display.
    private(set) var slivers: [String: NSImage] = [:]

    @ObservationIgnored
    private var anchors: [String: WeakAnchor] = [:]

    private struct WeakAnchor {
        weak var view: NSView?
    }

    func register(_ view: NSView, for paneId: String) {
        anchors[paneId] = WeakAnchor(view: view)
    }

    /// Snapshot the leading strip of a pane's rendered pixels. The caller
    /// must invoke this BEFORE the collapse mutation, while the pane is still
    /// laid out expanded. Skipped when a covering overlay is up — the capture
    /// composites the window's layer tree, and a stale page edge beats a
    /// corrupted one.
    func capture(paneId: String) {
        guard let anchor = anchors[paneId]?.view,
              let window = anchor.window,
              let contentView = window.contentView,
              !ConstellationPresentationState.shared.isOnScreen,
              !CommandKPalettePresentationState.shared.isOnScreen else { return }

        let full = anchor.convert(anchor.bounds, to: contentView)
        guard full.width > 100, full.height > 100 else { return }

        let rect = CGRect(
            x: full.minX,
            y: full.minY,
            width: min(PaneSlotPresentationPolicy.sliverSourceWidth, full.width),
            height: full.height
        )
        let scale = PaneSlotPresentationPolicy.sliverScale
        let displaySize = CGSize(
            width: (rect.width * scale).rounded(),
            height: (rect.height * scale).rounded()
        )
        // 2x pixels at the display size — Retina-crisp at a fraction of the
        // memory of a full capture (the sliver never shows more than this).
        guard displaySize.width >= 1, displaySize.height >= 1,
              let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(displaySize.width * 2),
                pixelsHigh: Int(displaySize.height * 2),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .calibratedRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
              ) else { return }
        rep.size = rect.size
        contentView.cacheDisplay(in: rect, to: rep)

        let image = NSImage(size: displaySize)
        image.addRepresentation(rep)
        slivers[paneId] = image
    }

    func discard(paneId: String) {
        slivers[paneId] = nil
        anchors[paneId] = nil
    }

    func discardAll() {
        slivers.removeAll()
        anchors.removeAll()
    }
}

/// Invisible AppKit anchor that lets the store convert a pane's content frame
/// into window coordinates for capture.
private struct PaneSpineSnapshotAnchor: NSViewRepresentable {
    let paneId: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let id = paneId
        DispatchQueue.main.async {
            PaneSpineSnapshotStore.shared.register(view, for: id)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
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
