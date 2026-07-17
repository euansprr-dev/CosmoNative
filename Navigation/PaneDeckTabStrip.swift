// CosmoOS/Navigation/PaneDeckTabStrip.swift
// The deck tab strip — bare controls (no glass of their own) that live inside
// a host container: a CosmoChromeIsland in focus-mode chrome rows, or the
// browser pane's docked bar. Tabs carry each pane's identity (entity-tinted
// glyph + live title) and its close affordance; the focused tab's flat fill
// slides between positions.
//
// The width ladder has exactly two rungs, and every pane on it has a NAME:
//   1. titled   — every tab shows glyph + title; titles compress toward a
//                 floor as the pane narrows (the Safari squeeze).
//   2. overflow — the focused tab stays titled; siblings collapse into one
//                 "+N" menu listing their full titles (the macOS toolbar
//                 overflow grammar). Anonymous glyph chips do not exist.

import SwiftUI

// MARK: - Layout Policy

enum PaneTabStripPresentation: Equatable {
    /// Every tab shows glyph + title, each title capped at `titleCap`.
    case titled(titleCap: CGFloat)
    /// Focused tab titled at `focusedCap`; siblings live in the "+N" menu.
    case overflow(focusedCap: CGFloat)
}

/// Pure width math for the strip — the no-overlap guarantee. The strip never
/// measures itself (a hugging view can't observe offered space); it derives
/// everything from the focused pane's width minus the host row's control
/// reserve, and a hard `maxWidth` cap plus text truncation absorb any
/// estimate drift.
enum PaneTabStripLayoutPolicy {
    static let interTabGap: CGFloat = 4
    /// Non-title width of a titled tab: 16pt glyph slot + 6pt gap + 16pt
    /// horizontal padding, rounded up for the occasional pin mark.
    static let titledTabChrome: CGFloat = 40
    /// Below this a title stops being a name and becomes an ellipsis —
    /// the switch to the overflow rung.
    static let minTitleWidth: CGFloat = 56
    static let maxTitleWidth: CGFloat = 168
    static let soloTitleCap: CGFloat = 200
    /// The "+N ⌄" pill.
    static let overflowPillWidth: CGFloat = 44
    /// Estimated width of a typical mode's own islands (leading toggle +
    /// trailing cluster + insets). Dense rows pass `denseHostReserve`.
    static let defaultHostReserve: CGFloat = 340
    /// For rows with heavyweight controls (Content's ledger + writing
    /// cluster, the browser's address field).
    static let denseHostReserve: CGFloat = 440

    static func budget(paneWidth: CGFloat, hostReserve: CGFloat = defaultHostReserve) -> CGFloat {
        min(max(paneWidth - hostReserve, 140), 560)
    }

    static func presentation(budget: CGFloat, tabCount: Int) -> PaneTabStripPresentation {
        guard tabCount > 1 else { return .titled(titleCap: soloTitleCap) }

        let gaps = CGFloat(tabCount - 1) * interTabGap
        let titleSpace = budget - gaps - CGFloat(tabCount) * titledTabChrome
        let perTitle = titleSpace / CGFloat(tabCount)
        if perTitle >= minTitleWidth {
            return .titled(titleCap: min(maxTitleWidth, perTitle))
        }

        let focusedCap = budget - overflowPillWidth - interTabGap - titledTabChrome
        return .overflow(focusedCap: min(soloTitleCap, max(72, focusedCap)))
    }
}

// MARK: - Strip

struct PaneDeckTabStrip: View {
    let context: PaneDeckChromePayload
    /// Width the host row's own controls claim — dense rows pass
    /// `PaneTabStripLayoutPolicy.denseHostReserve`.
    var hostReserve: CGFloat = PaneTabStripLayoutPolicy.defaultHostReserve

    @Namespace private var selectionNamespace

    // Drag-to-reorder (the Safari gesture): the dragged tab follows the
    // pointer rigidly while its neighbors spring around it. Reorders commit
    // one slot per crossing, using the displaced neighbor's real width —
    // titled tabs are not equal-width, so the step is per-neighbor.
    @State private var draggedPaneId: String?
    @State private var dragIsTracking = false
    @State private var dragTranslation: CGFloat = 0
    @State private var dragBaseline: CGFloat = 0
    @State private var measuredTabWidths: [String: CGFloat] = [:]

    /// Resolved atom/thinkspace titles, keyed by pane id. Resolved centrally
    /// so the overflow menu can name every hidden pane without running its
    /// own async work inside a lazily-built Menu.
    @State private var resolvedTitles: [String: String] = [:]

    private var budget: CGFloat {
        PaneTabStripLayoutPolicy.budget(paneWidth: context.paneWidth, hostReserve: hostReserve)
    }

    private var presentation: PaneTabStripPresentation {
        PaneTabStripLayoutPolicy.presentation(budget: budget, tabCount: context.tabs.count)
    }

    var body: some View {
        HStack(spacing: PaneTabStripLayoutPolicy.interTabGap) {
            stripContent
        }
        .frame(maxWidth: budget, alignment: .leading)
        .task(id: tabIdsSignature) {
            await resolveTitles()
        }
    }

    @ViewBuilder
    private var stripContent: some View {
        switch presentation {
        case .titled(let titleCap):
            ForEach(context.tabs) { tab in
                tabView(for: tab, titleCap: titleCap)
            }
        case .overflow(let focusedCap):
            if let focused = context.tabs.first(where: \.isFocused) ?? context.tabs.last {
                tabView(for: focused, titleCap: focusedCap)
                PaneDeckOverflowMenu(
                    hiddenTabs: context.tabs.filter { $0.id != focused.id },
                    titleProvider: { displayTitle(for: $0) },
                    onFocus: { context.actions.focus($0) }
                )
            }
        }
    }

    // MARK: Titles

    private var tabIdsSignature: String {
        context.tabs.map(\.id).joined(separator: "|")
    }

    private func resolveTitles() async {
        for tab in context.tabs {
            let title = await PaneInfo.title(for: tab.content)
            resolvedTitles[tab.id] = title
        }
    }

    private func displayTitle(for tab: PaneDeckTab) -> String {
        // Browser tabs read the live page title from the registry — the
        // observable read keeps the strip current as the page navigates.
        if tab.content.webURL != nil,
           let liveTitle = BrowserPaneRegistry.shared.displayTitle(for: tab.id),
           !liveTitle.isEmpty {
            return liveTitle
        }
        if let resolved = resolvedTitles[tab.id], !resolved.isEmpty {
            return resolved
        }
        return PaneInfo.fallbackTitle(for: tab.content)
    }

    // MARK: Tabs

    private func tabView(for tab: PaneDeckTab, titleCap: CGFloat) -> some View {
        PaneDeckTabView(
            tab: tab,
            displayTitle: displayTitle(for: tab),
            titleCap: titleCap,
            tabCount: context.tabs.count,
            selectionNamespace: selectionNamespace,
            onFocus: {
                // A completed drag releases over the tab it moved — that
                // mouse-up must not read as a focus click.
                guard draggedPaneId == nil else { return }
                context.actions.focus(tab.id)
            },
            onClose: { context.actions.close(tab.id) },
            onTogglePin: { context.actions.togglePin(tab.id) },
            onMove: { delta in context.actions.move(tab.id, delta) },
            onCloseOthers: { context.actions.closeOthers(tab.id) }
        )
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            measuredTabWidths[tab.id] = width
        }
        .offset(x: tab.id == draggedPaneId ? dragTranslation : 0)
        .zIndex(tab.id == draggedPaneId ? 1 : 0)
        // While tracking, the dragged tab is pinned to the pointer: its slot
        // change from a live reorder and its offset compensation must both
        // land in the same frame, unanimated. Neighbors animate normally.
        .transaction { transaction in
            if tab.id == draggedPaneId && dragIsTracking {
                transaction.animation = nil
            }
        }
        .simultaneousGesture(reorderGesture(for: tab))
    }

    // MARK: Reorder gesture

    private func reorderGesture(for tab: PaneDeckTab) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if draggedPaneId != tab.id {
                    draggedPaneId = tab.id
                    dragBaseline = 0
                    dragIsTracking = true
                }
                updateDrag(tabId: tab.id, translation: value.translation.width)
            }
            .onEnded { _ in settleDrag() }
    }

    /// Commit at most one reorder per drag event: the payload refreshes
    /// through the environment after each move, so multi-step math against a
    /// stale tab order would drift. The threshold is half the displaced
    /// neighbor's width; `dragBaseline` re-zeroes the translation after each
    /// commit so the dragged tab never visually jumps.
    private func updateDrag(tabId: String, translation: CGFloat) {
        guard let index = context.tabs.firstIndex(where: { $0.id == tabId }) else { return }
        var offset = translation - dragBaseline
        let gap = PaneTabStripLayoutPolicy.interTabGap
        let fallbackWidth = PaneTabStripLayoutPolicy.titledTabChrome + PaneTabStripLayoutPolicy.minTitleWidth

        if offset > 0, index < context.tabs.count - 1 {
            let neighborId = context.tabs[index + 1].id
            let step = (measuredTabWidths[neighborId] ?? fallbackWidth) + gap
            if offset > step / 2 {
                context.actions.move(tabId, 1)
                dragBaseline += step
                offset -= step
            }
        } else if offset < 0, index > 0 {
            let neighborId = context.tabs[index - 1].id
            let step = (measuredTabWidths[neighborId] ?? fallbackWidth) + gap
            if offset < -step / 2 {
                context.actions.move(tabId, -1)
                dragBaseline -= step
                offset += step
            }
        }
        dragTranslation = offset
    }

    /// Spring the released tab home, keep it floating above its neighbors
    /// until the settle finishes, then release the drag state.
    private func settleDrag() {
        dragIsTracking = false
        withAnimation(ProMotionSprings.focusTransition) { dragTranslation = 0 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !dragIsTracking else { return }
            draggedPaneId = nil
            dragBaseline = 0
        }
    }
}

// MARK: - Tab

/// One tab: the pane's identity glyph in its entity tint + the live title.
/// Hover swaps the glyph for the close affordance (the Safari gesture).
private struct PaneDeckTabView: View {
    let tab: PaneDeckTab
    let displayTitle: String
    let titleCap: CGFloat
    let tabCount: Int
    let selectionNamespace: Namespace.ID
    let onFocus: () -> Void
    let onClose: () -> Void
    let onTogglePin: () -> Void
    let onMove: (Int) -> Void
    let onCloseOthers: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

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
        .help("\(displayTitle) (⌘⌃\(tab.position))")
        .accessibilityLabel("\(displayTitle) pane")
        .accessibilityAddTraits(tab.isFocused ? [.isSelected] : [])
    }

    // MARK: Pieces

    private var tabLabel: some View {
        HStack(spacing: DS.space6) {
            leadingMark
            Text(displayTitle)
                .font(DS.buttonText)
                .foregroundStyle(tab.isFocused ? DS.text : DS.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: titleCap, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if tab.isPinned {
                Image(systemName: "pin.fill")
                    .font(DS.caption2)
                    .foregroundStyle(DS.accent)
                    .accessibilityLabel("Pinned")
            }
        }
        .padding(.horizontal, DS.space8)
        .frame(height: 28)
        .background { hoverFill }
        .background { selectionFill }
        .contentShape(Capsule())
    }

    /// Constant-structure hover wash — opacity-driven, never inserted.
    /// `glassCardFill` is the sanctioned flat hover wash for controls that
    /// live on glass (the Atom-bar glyph treatment).
    private var hoverFill: some View {
        Capsule()
            .fill(DS.glassCardFill)
            .opacity(isHovered && !tab.isFocused && !tab.isPinned ? 0.9 : 0)
    }

    /// The focused tab's fill slides between strip positions (matched
    /// geometry); a pinned-but-unfocused tab keeps a quieter static fill
    /// because its pane is still on screen beside the focused one.
    @ViewBuilder
    private var selectionFill: some View {
        if tab.isFocused {
            Capsule()
                .fill(DS.surfaceElevated)
                .matchedGeometryEffect(id: "pane-tab-selection", in: selectionNamespace)
        } else if tab.isPinned {
            Capsule().fill(DS.surfaceElevated.opacity(0.55))
        }
    }

    /// 16pt identity slot: entity-tinted glyph at rest, close button on hover.
    private var leadingMark: some View {
        ZStack {
            Image(systemName: PaneInfo.glyph(for: tab.content))
                .font(DS.caption.weight(.medium))
                .foregroundStyle(PaneInfo.tint(for: tab.content).opacity(tab.isFocused ? 1 : 0.7))
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
        Button(tab.isPinned ? "Unpin Pane" : "Pin Pane", action: onTogglePin)
        Divider()
        Button("Move Pane Left") { onMove(-1) }
            .disabled(tab.position == 1)
        Button("Move Pane Right") { onMove(1) }
            .disabled(tab.position == tabCount)
        Divider()
        Button("Close Pane", action: onClose)
        Button("Close Other Panes", action: onCloseOthers)
            .disabled(tabCount == 1)
    }
}

// MARK: - Overflow Menu

/// The ladder's bottom rung: when compressed titles would stop being names,
/// the non-focused tabs collapse into one "+N" pill whose menu lists every
/// hidden pane with its glyph and FULL title — the macOS toolbar-overflow
/// grammar. Nothing on the strip is ever anonymous.
private struct PaneDeckOverflowMenu: View {
    let hiddenTabs: [PaneDeckTab]
    let titleProvider: (PaneDeckTab) -> String
    let onFocus: (String) -> Void

    @State private var isHovered = false

    var body: some View {
        Menu {
            ForEach(hiddenTabs) { tab in
                Button {
                    onFocus(tab.id)
                } label: {
                    Label(menuTitle(for: tab), systemImage: PaneInfo.glyph(for: tab.content))
                }
            }
        } label: {
            HStack(spacing: DS.space2) {
                Text("+\(hiddenTabs.count)")
                    .font(DS.caption.weight(.medium).monospacedDigit())
                Image(systemName: "chevron.down")
                    .font(DS.caption2.weight(.semibold))
            }
            .foregroundStyle(DS.textSecondary)
            .padding(.horizontal, DS.space8)
            .frame(height: 28)
            .background {
                Capsule()
                    .fill(DS.glassCardFill)
                    .opacity(isHovered ? 0.9 : 0)
            }
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .help("Show all panes")
        .accessibilityLabel("Show \(hiddenTabs.count) more panes")
    }

    private func menuTitle(for tab: PaneDeckTab) -> String {
        tab.isPinned ? "\(titleProvider(tab)) (Pinned)" : titleProvider(tab)
    }
}

// MARK: - Standalone Chrome

/// The shell-owned row for panes whose surface has no chrome row of its own
/// (canvas, Command Center, Swipe library, assistant, collaborator) — and
/// the migration fallback so no pane kind is ever tab-less. Mounted STACKED
/// above the content, never overlaid: these surfaces carry top-anchored
/// mastheads a floating island could cover.
struct PaneDeckStandaloneChrome: View {
    let context: PaneDeckChromePayload

    var body: some View {
        HStack(spacing: 0) {
            CosmoChromeIsland {
                PaneDeckTabStrip(context: context)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.space12)
        .padding(.top, DS.space8)
        .padding(.bottom, DS.space4)
    }
}
