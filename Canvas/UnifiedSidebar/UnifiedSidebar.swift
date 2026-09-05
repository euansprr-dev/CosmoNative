// CosmoOS/Canvas/UnifiedSidebar/UnifiedSidebar.swift
// The app sidebar — one floating glass panel, one row grammar.
//
// Anatomy (top → bottom): toggle · the five places · the open place's
// sections · you. Every row is `SidebarRow`; every section is a
// `SidebarSection` (the one header voice); exactly one row carries the
// selection wash at a time (the page you are on). The place rows above it
// mark the open section with weight and an accent glyph — never a second wash.
// March 2026 — Command Center navigation · Sept 2026 — the Apple pass

import SwiftUI
import AppKit

// MARK: - Navigation Destination

enum SidebarDestination: Equatable, Hashable {
    case commandCenter
    case inbox
    case discover(section: SwipeDiscoverySectionSelection)
    case swipeFile(section: SwipeLibrarySectionSelection)
    case ideas
    /// Studio › Pipeline — content by client, stage and date (never filed).
    case pipeline
    /// Studio › Clients — the index of client hubs.
    case clients
    /// One client's hub: their pipeline, calendar, ideas, swipes, dossier.
    case client(id: String)
    case thinkspace(id: String)
}

enum MainSidebarContentLayoutPolicy {
    static func contentLeadingInset(
        for destination: SidebarDestination,
        isSidebarVisible: Bool,
        isSidebarHidden _: Bool,
        isHoverRevealed _: Bool,
        isFocusModeActive: Bool,
        sidebarReservedWidth: CGFloat
    ) -> CGFloat {
        guard isSidebarVisible else { return 0 }

        if case .thinkspace = destination, !isFocusModeActive {
            return 0
        }

        return sidebarReservedWidth
    }
}

enum MainSidebarHoverRevealPolicy {
    static func isSidebarVisible(
        isSidebarHidden: Bool,
        isHoverRevealed: Bool
    ) -> Bool {
        !isSidebarHidden || isHoverRevealed
    }

    static func shouldCloseTransientReveal(
        isSidebarHidden: Bool,
        isHoverRevealed: Bool,
        isHoveringRevealTrigger: Bool,
        isHoveringSidebarPanel: Bool
    ) -> Bool {
        isSidebarHidden
            && isHoverRevealed
            && !isHoveringRevealTrigger
            && !isHoveringSidebarPanel
    }
}

enum MainSidebarButtonPolicy {
    static func shouldPersistTransientReveal(
        isSidebarHidden: Bool,
        isHoverRevealed: Bool
    ) -> Bool {
        isSidebarHidden && isHoverRevealed
    }
}

/// The five places. Declaration order is sidebar order.
enum SidebarContext: String, CaseIterable, Equatable, Hashable {
    case thinkspaces
    case commandCenter
    case content
    case swipeFile
    case inbox

    var title: String {
        switch self {
        case .thinkspaces: return "Spaces"
        case .commandCenter: return "Command"
        case .content: return "Content"
        case .swipeFile: return "Swipe File"
        case .inbox: return "Inbox"
        }
    }

    var cosmoIcon: CosmoIcon {
        switch self {
        case .thinkspaces: return .space
        case .commandCenter: return .command
        case .content: return .content
        case .swipeFile: return .swipe
        case .inbox: return .inbox
        }
    }

}

enum SidebarInboxRoute: Equatable, Hashable {
    case global
    case captureLanes
    case captureLane(id: String)
    case manageCommands
}

// MARK: - Sidebar Metrics

enum UnifiedSidebarMetrics {
    static let defaultExpandedWidth: CGFloat = 304
    static let minExpandedWidth: CGFloat = 288
    static let maxExpandedWidth: CGFloat = 336

    static let panelCornerRadius: CGFloat = 22
    /// Panel inset. Row radius is concentric with the panel: 22 − 14 = 8.
    static let outerPadding: CGFloat = 14
    static let rowRadius: CGFloat = 8

    /// The one row height (the source-list register).
    static let rowHeight: CGFloat = 30
    static let rowSpacing: CGFloat = 2
    /// Horizontal padding inside a row — labels and section headers share it.
    static let rowInset: CGFloat = 8
    static let glyphWidth: CGFloat = 20
    static let nestIndent: CGFloat = 18
    /// Glyph buttons in the header and footer.
    static let controlSize: CGFloat = 28

    static let hoverRevealTriggerWidth: CGFloat = 18
    static let resizeHandleWidth: CGFloat = 10
    static let floatingMargin: CGFloat = 8

    static func clampedExpandedWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, minExpandedWidth), maxExpandedWidth)
    }
}

// MARK: - Row Grammar

/// The one selection law for sidebar rows: a wash of the row's tint, no
/// stroke. Hover is the same quiet fill on every row.
enum SidebarRowFill {
    static func wash(_ tint: Color) -> Color {
        tint.opacity(DS.palette.isDark ? 0.18 : 0.12)
    }

    static var hover: Color {
        DS.surfaceHover.opacity(0.7)
    }

    static func resolve(isActive: Bool, isHovered: Bool, tint: Color) -> Color {
        if isActive { return wash(tint) }
        if isHovered { return hover }
        return .clear
    }
}

private struct SidebarRowChromeModifier: ViewModifier {
    let isActive: Bool
    let isHovered: Bool
    let tint: Color

    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: UnifiedSidebarMetrics.rowRadius, style: .continuous)
                .fill(SidebarRowFill.resolve(isActive: isActive, isHovered: isHovered, tint: tint))
        )
    }
}

extension View {
    func sidebarRowChrome(isActive: Bool, isHovered: Bool, tint: Color = DS.accent) -> some View {
        modifier(SidebarRowChromeModifier(isActive: isActive, isHovered: isHovered, tint: tint))
    }
}

/// What sits in a row's glyph column.
enum SidebarRowMark {
    case icon(CosmoIcon)
    case symbol(String)
    case emoji(String)
}

/// How loudly a row speaks.
enum SidebarRowProminence {
    /// A page: active = the selection wash.
    case standard
    /// A place (the five top rows): active = ink label + accent glyph, no wash —
    /// the wash belongs to the page row beneath it.
    case primary
    /// A creation row that closes a list ("New space…"): muted until hovered.
    case ghost
}

/// The one sidebar row. Height, inset, glyph column, type and selection are
/// fixed here so every list in the panel reads as one list.
struct SidebarRow: View {
    let title: String
    let mark: SidebarRowMark
    var count: Int? = nil
    var isActive: Bool = false
    var prominence: SidebarRowProminence = .standard
    var help: String? = nil
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space8) {
                glyph
                    .frame(width: UnifiedSidebarMetrics.glyphWidth, height: UnifiedSidebarMetrics.glyphWidth)
                    .accessibilityHidden(true)

                Text(title)
                    .font(labelFont)
                    .foregroundStyle(labelColor)
                    .lineLimit(1)

                Spacer(minLength: DS.space8)

                if let count, count > 0 {
                    Text("\(count)")
                        .font(DS.caption.monospacedDigit())
                        .foregroundStyle(isActive ? DS.textSecondary : DS.textMuted)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, UnifiedSidebarMetrics.rowInset)
            .frame(maxWidth: .infinity, minHeight: UnifiedSidebarMetrics.rowHeight, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: UnifiedSidebarMetrics.rowRadius, style: .continuous))
            .sidebarRowChrome(isActive: isActive && prominence == .standard, isHovered: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : ProMotionSprings.hover, value: isHovered)
        // A tooltip that repeats the label is noise (Finder rows carry none);
        // rows tooltip only when they have something to add.
        .help(help ?? "")
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    @ViewBuilder
    private var glyph: some View {
        switch mark {
        case .icon(let icon):
            Image(cosmo: icon)
                .font(DS.title3)
                .foregroundStyle(glyphColor)
                .accessibilityHidden(true)
        case .symbol(let name):
            Image(systemName: name)
                .font(DS.title3)
                .foregroundStyle(glyphColor)
        case .emoji(let emoji):
            Text(emoji)
                .font(DS.headline)
        }
    }

    private var labelFont: Font {
        if prominence == .primary && isActive {
            return DS.callout.weight(.semibold)
        }
        return DS.callout.weight(.medium)
    }

    private var labelColor: Color {
        switch prominence {
        case .ghost:
            return isHovered ? DS.textSecondary : DS.textMuted
        case .primary, .standard:
            return isActive ? DS.text : DS.textSecondary
        }
    }

    private var glyphColor: Color {
        switch prominence {
        case .ghost:
            return isHovered ? DS.textSecondary : DS.textMuted
        case .primary, .standard:
            return isActive ? DS.accent : DS.textSecondary
        }
    }
}

/// A section: the one header voice (small caps + a trailing live count),
/// then rows at the one row spacing.
struct SidebarSection<Content: View>: View {
    let title: String
    var count: Int? = nil
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: UnifiedSidebarMetrics.rowSpacing) {
            header
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: DS.space8) {
            Text(title)
                .font(DS.smallCaps)
                .tracking(DS.smallCapsTracking)
                .foregroundStyle(DS.giltInk)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let count, count > 0 {
                Text("\(count)")
                    .font(DS.caption.monospacedDigit())
                    .foregroundStyle(DS.textMuted)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : ProMotionSprings.snappy, value: count)
            }
        }
        .padding(.horizontal, UnifiedSidebarMetrics.rowInset)
        .frame(height: 22)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The row a ghost row becomes when clicked: a name field in the row's own
/// geometry. Return commits, Escape cancels.
struct SidebarInlineCreateRow: View {
    let placeholder: String
    let symbol: String
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: symbol)
                .font(DS.title3)
                .foregroundStyle(DS.accent)
                .frame(width: UnifiedSidebarMetrics.glyphWidth, height: UnifiedSidebarMetrics.glyphWidth)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(DS.callout.weight(.medium))
                .foregroundStyle(DS.text)
                .focused(isFocused)
                .onSubmit(onSubmit)
                .onExitCommand(perform: onCancel)
        }
        .sidebarInlineFieldChrome()
    }
}

/// The chrome of a text field living in a row slot (create, rename): the
/// row's geometry, an elevated fill, the one focus ring.
private struct SidebarInlineFieldChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, UnifiedSidebarMetrics.rowInset)
            .frame(maxWidth: .infinity, minHeight: UnifiedSidebarMetrics.rowHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: UnifiedSidebarMetrics.rowRadius, style: .continuous)
                    .fill(DS.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: UnifiedSidebarMetrics.rowRadius, style: .continuous)
                    .stroke(DS.focusRing, lineWidth: 1)
            )
    }
}

extension View {
    func sidebarInlineFieldChrome() -> some View {
        modifier(SidebarInlineFieldChromeModifier())
    }
}

/// Glyph-only control for the header and footer (toggle, settings).
private struct SidebarGlyphButton: View {
    let title: String
    let symbol: String
    let help: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(title, systemImage: symbol, action: action)
            .labelStyle(.iconOnly)
            .font(DS.subheadline.weight(.semibold))
            .foregroundStyle(isHovered ? DS.text : DS.textSecondary)
            .frame(width: UnifiedSidebarMetrics.controlSize, height: UnifiedSidebarMetrics.controlSize)
            .background(
                RoundedRectangle(cornerRadius: UnifiedSidebarMetrics.rowRadius, style: .continuous)
                    .fill(isHovered ? SidebarRowFill.hover : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: UnifiedSidebarMetrics.rowRadius, style: .continuous))
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .animation(reduceMotion ? nil : ProMotionSprings.hover, value: isHovered)
            .help(help)
            .accessibilityLabel(title)
    }
}

// MARK: - Unified Sidebar

struct UnifiedSidebar: View {
    @Binding var currentDestination: SidebarDestination
    @Binding var inboxRoute: SidebarInboxRoute
    @Binding var activeContext: SidebarContext
    @Binding var panelWidth: CGFloat
    var thinkspaceManager: ThinkspaceManager
    var commandCenterViewModel: CommandCenterDashboardViewModel
    var pipelineModel: PipelinePageModel
    var cornerRadius: CGFloat = UnifiedSidebarMetrics.panelCornerRadius
    var sidebarButtonTitle: String = "Close sidebar"
    var sidebarButtonHelp: String = "Close sidebar"
    var onClose: () -> Void = {}
    var onNavigate: () -> Void = {}

    @EnvironmentObject var crossDragManager: CrossThinkspaceDragManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var inboxRepository = InboxRepository.shared

    @State private var showCompanionPicker = false
    @State private var companionVitality: CompanionVitality = .resting
    @State private var isCompanionHovered = false
    @State private var isResizeHandleHovered = false
    @State private var resizeStartWidth: CGFloat?
    @State private var isBrowsingSpaces = false

    private var outerPadding: CGFloat { UnifiedSidebarMetrics.outerPadding }

    private var widthAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.15) : ProMotionSprings.sidebar
    }

    /// Switching places swaps the section list; the swap is a quick
    /// cross-fade, not a slide — the panel itself never moves.
    private var contextAnimation: Animation? {
        reduceMotion ? nil : ProMotionSprings.snappy
    }

    // NSFullUserName() is a directory-services call — resolve once, not per
    // footer body pass.
    private static let cachedUserFirstName =
        NSFullUserName().components(separatedBy: " ").first ?? "User"

    var body: some View {
        CosmoGlassPanel(role: .globalSidebar, cornerRadius: cornerRadius) {
            VStack(spacing: 0) {
                sidebarHeader

                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: DS.space16) {
                        placeRows
                        WorkbenchStripView()
                        sidebarBody
                            .id(activeContext)
                            .transition(.opacity)
                    }
                    .padding(.horizontal, outerPadding)
                    .padding(.top, DS.space4)
                    .padding(.bottom, DS.space16)
                }
                .scrollIndicators(.hidden)

                sidebarFooter
            }
        }
        .frame(width: panelWidth)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .trailing) {
            resizeHandle
                .padding(.trailing, 2)
        }
        .animation(widthAnimation, value: panelWidth)
        .animation(contextAnimation, value: activeContext)
        .onAppear {
            panelWidth = UnifiedSidebarMetrics.clampedExpandedWidth(
                StatePersistence.shared.getSidebarWidth()
            )
        }
        .onChange(of: panelWidth) { _, newWidth in
            let clamped = UnifiedSidebarMetrics.clampedExpandedWidth(newWidth)
            if clamped != newWidth {
                panelWidth = clamped
                return
            }
            // Mid-drag frames don't persist — saveSidebarWidth re-encodes the
            // whole UI-state blob, and the drag writes once per pointer frame.
            // The resize handle's .onEnded records the final width.
            guard resizeStartWidth == nil else { return }
            StatePersistence.shared.saveSidebarWidth(clamped)
        }
        .onChange(of: currentDestination) { _, destination in
            if case .thinkspace = destination { isBrowsingSpaces = false }
        }
    }

    // MARK: - Header

    /// Keep the toggle at the trailing edge with breathing room inside
    /// the panel and clear of its resize handle.
    private var sidebarHeader: some View {
        HStack(spacing: 0) {
            Spacer(minLength: DS.space8)
            SidebarGlyphButton(
                title: sidebarButtonTitle,
                symbol: "sidebar.left",
                help: sidebarButtonHelp
            ) {
                withAnimation(widthAnimation) { onClose() }
            }
            .padding(.trailing, DS.space4)
        }
        .padding(.horizontal, outerPadding)
        .padding(.top, DS.space10)
        .padding(.bottom, DS.space10)
    }

    // MARK: - Places

    private var placeRows: some View {
        VStack(spacing: UnifiedSidebarMetrics.rowSpacing) {
            ForEach(SidebarContext.allCases, id: \.rawValue) { context in
                let isActive = activeContext == context
                SidebarRow(
                    title: context.title,
                    mark: .icon(context.cosmoIcon),
                    count: context == .inbox ? inboxRepository.unreadCount : nil,
                    isActive: isActive,
                    prominence: .primary
                ) {
                    open(context)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func open(_ context: SidebarContext) {
        withAnimation(contextAnimation) {
            activeContext = context
            switch context {
            case .content: currentDestination = .ideas
            case .swipeFile: currentDestination = .swipeFile(section: .home)
            case .commandCenter: currentDestination = .commandCenter
            case .inbox:
                inboxRoute = .global
                currentDestination = .inbox
            case .thinkspaces:
                if let id = thinkspaceManager.currentThinkspace?.id {
                    currentDestination = .thinkspace(id: id)
                }
            }
        }
        onNavigate()
    }

    // MARK: - Body

    @ViewBuilder
    private var sidebarBody: some View {
        switch activeContext {
        case .thinkspaces:
            if !isBrowsingSpaces, case .thinkspace(let id) = currentDestination,
               let space = thinkspaceManager.thinkspaces.first(where: { $0.id == id }) {
                SpaceContentsNavigator(spaceID: id, name: space.identityLabel) {
                    withAnimation(contextAnimation) { isBrowsingSpaces = true }
                }
            } else {
                SidebarThinkspaceSection(
                    manager: thinkspaceManager,
                    currentDestination: $currentDestination,
                    onNavigate: {
                        withAnimation(contextAnimation) { isBrowsingSpaces = false }
                        onNavigate()
                    }
                )
            }
        case .commandCenter:
            SidebarCommandCenterContext(
                viewModel: commandCenterViewModel,
                currentDestination: $currentDestination,
                onNavigate: onNavigate
            )
        case .content:
            SidebarContentContext(
                pipelineModel: pipelineModel,
                currentDestination: $currentDestination,
                onNavigate: onNavigate
            )
        case .swipeFile:
            SidebarSwipeFileContext(
                currentDestination: $currentDestination,
                onNavigate: onNavigate
            )
        case .inbox:
            SidebarInboxContext(
                currentDestination: $currentDestination,
                inboxRoute: $inboxRoute,
                onNavigate: onNavigate
            )
        }
    }

    // MARK: - Footer

    private var sidebarFooter: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(DS.glassBorder)
                .frame(height: 0.5)
                .padding(.horizontal, outerPadding)

            HStack(spacing: DS.space8) {
                companionButton
                Spacer(minLength: DS.space8)
                SidebarGlyphButton(title: "Settings", symbol: "gearshape", help: "Settings (⌘,)") {
                    NotificationCenter.default.post(name: .showSettings, object: nil)
                }
            }
            .padding(.horizontal, outerPadding)
            .padding(.vertical, DS.space8)
        }
    }

    /// The companion IS the profile mark — click to choose another.
    private var companionButton: some View {
        let companion = CompanionStore.shared.companion
        return Button {
            showCompanionPicker = true
        } label: {
            HStack(spacing: DS.space8) {
                CompanionMark(companion: companion, size: 24, vitality: companionVitality)
                Text(Self.cachedUserFirstName)
                    .font(DS.callout.weight(.medium))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
            }
            .padding(.leading, DS.space2)
            .padding(.trailing, DS.space8)
            .frame(height: UnifiedSidebarMetrics.controlSize)
            .background(
                RoundedRectangle(cornerRadius: UnifiedSidebarMetrics.rowRadius, style: .continuous)
                    .fill(isCompanionHovered ? SidebarRowFill.hover : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: UnifiedSidebarMetrics.rowRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isCompanionHovered = $0 }
        .animation(reduceMotion ? nil : ProMotionSprings.hover, value: isCompanionHovered)
        .help("\(companion.name) \(companion.species) — open your companion’s world")
        .popover(isPresented: $showCompanionPicker, arrowEdge: .top) {
            CompanionPickerPopover()
        }
        .accessibilityLabel("Your companion, \(companion.accessibilityDescription). Open your companion’s world.")
        .task {
            await CompanionStore.shared.hydrate()
            companionVitality = await CompanionVitality.current()
        }
    }

    // MARK: - Resize Handle

    /// Invisible at rest (the split-view law); the grip appears on hover.
    private var resizeHandle: some View {
        let isLive = isResizeHandleHovered || resizeStartWidth != nil
        return Rectangle()
            .fill(Color.clear)
            .frame(width: UnifiedSidebarMetrics.resizeHandleWidth)
            .contentShape(Rectangle())
            .overlay(alignment: .center) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(DS.borderActive)
                    .frame(width: 2, height: 52)
                    .opacity(isLive ? 1 : 0)
                    .padding(.trailing, 2)
            }
            .onHover { hovering in
                withAnimation(reduceMotion ? nil : ProMotionSprings.hover) {
                    isResizeHandleHovered = hovering
                }
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if resizeStartWidth == nil {
                            resizeStartWidth = panelWidth
                        }
                        guard let startWidth = resizeStartWidth else { return }
                        // Seat idiom (SplitPaneContainer): a spring re-targeted
                        // every pointer frame never settles — the width must
                        // track the cursor exactly, so the per-frame write is
                        // explicitly un-animated. Open/close keep their springs
                        // (they animate isSidebarHidden, a different value).
                        withTransaction(\.disablesAnimations, true) {
                            panelWidth = UnifiedSidebarMetrics.clampedExpandedWidth(
                                startWidth + value.translation.width
                            )
                        }
                    }
                    .onEnded { _ in
                        resizeStartWidth = nil
                        StatePersistence.shared.saveSidebarWidth(
                            UnifiedSidebarMetrics.clampedExpandedWidth(panelWidth)
                        )
                    }
            )
    }
}

// MARK: - Command Center Context

private struct SidebarCommandCenterContext: View {
    var viewModel: CommandCenterDashboardViewModel
    @Binding var currentDestination: SidebarDestination
    var onNavigate: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            SidebarSection(title: "Smart lists") {
                ForEach(DashboardViewMode.smartLists, id: \.self) { mode in
                    modeRow(mode)
                }
            }
            SidebarSection(title: "Planning") {
                ForEach(DashboardViewMode.planningLists, id: \.self) { mode in
                    modeRow(mode)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            // IfNeeded variants: this context REMOUNTS on every switch to the
            // Command Center sidebar (the section is keyed on activeContext) —
            // the unguarded loads paid two full task-table scans + a per-row
            // decode pass per switch. Freshness after the first load is owned
            // by the DashboardAtomRefreshSignature observation and the habit
            // engine's definitions publisher.
            await viewModel.loadAreasIfNeeded()
            await viewModel.loadAnytimeTasksIfNeeded()
            await viewModel.loadSomedayTasksIfNeeded()
            await viewModel.loadHabitsIfNeeded()
        }
    }

    private func modeRow(_ mode: DashboardViewMode) -> some View {
        SidebarRow(
            title: mode.label,
            mark: .icon(mode.cosmoIcon),
            count: badgeCount(for: mode),
            isActive: currentDestination == .commandCenter
                && viewModel.viewMode == mode
                && viewModel.selectedProjectUUID == nil
                && viewModel.selectedAreaUUID == nil
                && !viewModel.showReports
        ) {
            withAnimation(ProMotionSprings.snappy) {
                if currentDestination != .commandCenter {
                    currentDestination = .commandCenter
                }
                viewModel.selectedProjectUUID = nil
                viewModel.selectedAreaUUID = nil
                viewModel.showReports = false
                viewModel.viewMode = mode
            }
            onNavigate()
        }
    }

    private func badgeCount(for mode: DashboardViewMode) -> Int? {
        let count: Int
        switch mode {
        case .today: count = viewModel.todayActiveCount
        case .upcoming: count = viewModel.upcomingTotalCount
        case .anytime: count = viewModel.anytimeTasks.count
        case .someday: count = viewModel.somedayTasks.count
        case .logbook: count = viewModel.completedTodayTasks.count
        case .habits, .reports, .queue, .project, .area: count = 0
        }
        return count > 0 ? count : nil
    }
}

// MARK: - Content Context

/// The Studio's lenses, one row each — the page's own switcher, mirrored.
private struct SidebarContentContext: View {
    var pipelineModel: PipelinePageModel
    @Binding var currentDestination: SidebarDestination
    var onNavigate: () -> Void = {}

    private var isOnPipeline: Bool {
        switch currentDestination {
        case .pipeline, .client: return true
        default: return false
        }
    }

    var body: some View {
        SidebarSection(title: "Studio") {
            SidebarRow(
                title: "Ideas",
                mark: .icon(.idea),
                isActive: currentDestination == .ideas,
                help: "Ideas — choose what to make (⌘1)"
            ) {
                withAnimation(ProMotionSprings.snappy) { currentDestination = .ideas }
                NotificationCenter.default.post(name: CosmoNotification.Navigation.openIdeas, object: nil)
                onNavigate()
            }
            SidebarRow(
                title: "Pipeline",
                mark: .icon(.pipeline),
                isActive: isOnPipeline && pipelineModel.view != .calendar,
                help: "Pipeline — content by stage (⌘2)"
            ) {
                openPipeline(.board)
            }
            SidebarRow(
                title: "Calendar",
                mark: .icon(.calendar),
                isActive: isOnPipeline && pipelineModel.view == .calendar,
                help: "Calendar — the month plan (⌘3)"
            ) {
                openPipeline(.calendar)
            }
            SidebarRow(
                title: "Clients",
                mark: .icon(.clients),
                isActive: currentDestination == .clients,
                help: "Clients — hubs, dossiers, cadence"
            ) {
                NotificationCenter.default.post(name: CosmoNotification.Navigation.openClients, object: nil)
                onNavigate()
            }
        }
    }

    /// One door for both pipeline lenses: MainView lands on `.pipeline` and
    /// the workspace picks the tab from the view.
    private func openPipeline(_ view: PipelineView) {
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.openPipeline,
            object: nil,
            userInfo: ["view": view.rawValue]
        )
        onNavigate()
    }
}

// MARK: - Inbox Context

private struct SidebarInboxContext: View {
    @Binding var currentDestination: SidebarDestination
    @Binding var inboxRoute: SidebarInboxRoute
    var onNavigate: () -> Void = {}

    @ObservedObject private var inboxRepository = InboxRepository.shared
    @ObservedObject private var destinationRepository = CaptureDestinationRepository.shared
    @State private var isCreatingLane = false
    @State private var newLaneName = ""
    @State private var pendingDeleteLane: CaptureDestination?
    @FocusState private var isLaneNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            SidebarSection(title: "Capture") {
                SidebarRow(
                    title: "Global Inbox",
                    mark: .icon(.inbox),
                    count: inboxRepository.unreadCount,
                    isActive: currentDestination == .inbox && inboxRoute == .global
                ) {
                    open(.global)
                }
                SidebarRow(
                    title: "Capture Lanes",
                    mark: .icon(.captureLanes),
                    count: laneCount,
                    isActive: currentDestination == .inbox && inboxRoute == .captureLanes
                ) {
                    open(.captureLanes)
                }
                SidebarRow(
                    title: "Commands",
                    mark: .icon(.commands),
                    isActive: currentDestination == .inbox && inboxRoute == .manageCommands,
                    help: "The capture aliases that route thoughts into lanes"
                ) {
                    open(.manageCommands)
                }
            }

            SidebarSection(title: "Lanes", count: destinationRepository.destinations.count) {
                ForEach(destinationRepository.destinations) { destination in
                    laneRow(destination)
                }
                if isCreatingLane {
                    SidebarInlineCreateRow(
                        placeholder: "Lane name",
                        symbol: "tray.badge.plus",
                        text: $newLaneName,
                        isFocused: $isLaneNameFocused,
                        onSubmit: createLane,
                        onCancel: cancelCreatingLane
                    )
                } else {
                    SidebarRow(title: "New lane…", mark: .symbol("plus"), prominence: .ghost, help: "New capture lane") {
                        beginCreatingLane()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            _ = try? await destinationRepository.fetchActive()
            _ = try? await inboxRepository.countUnread()
        }
        .confirmationDialog(
            "Delete \(pendingDeleteLane?.name ?? "lane")?",
            isPresented: deleteLaneDialogBinding,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let pendingDeleteLane else { return }
                deleteLane(pendingDeleteLane)
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteLane = nil
            }
        } message: {
            Text("The lane leaves the sidebar, stays visible in History, and can be restored from there.")
        }
    }

    private var laneCount: Int? {
        let count = destinationRepository.destinations.reduce(0) { $0 + $1.itemCount }
        return count > 0 ? count : nil
    }

    private func laneRow(_ destination: CaptureDestination) -> some View {
        // Same law as the iOS lanes: an emoji typed into the lane name IS
        // the icon, and the label sheds it. Never a keyword guess over the
        // lane's own explicitly chosen mark.
        let identity = CollectionEmoji.resolve(name: destination.name, matchKeywords: false)
        let alias = destination.aliases.first.map { "Capture with \"\($0):\"" }
        return SidebarRow(
            title: identity.label,
            mark: identity.emoji.map { SidebarRowMark.emoji($0) } ?? SidebarRowMark.symbol(destination.icon),
            count: destination.itemCount,
            isActive: currentDestination == .inbox && inboxRoute == .captureLane(id: destination.uuid),
            help: alias
        ) {
            open(.captureLane(id: destination.uuid))
        }
        .contextMenu {
            Button {
                open(.captureLane(id: destination.uuid))
            } label: {
                Label("Open Lane", systemImage: "arrow.right.circle")
            }
            Divider()
            Button(role: .destructive) {
                pendingDeleteLane = destination
            } label: {
                Label("Delete Lane", systemImage: "trash")
            }
        }
    }

    private func beginCreatingLane() {
        withAnimation(ProMotionSprings.snappy) {
            isCreatingLane = true
            newLaneName = ""
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            isLaneNameFocused = true
        }
    }

    private func cancelCreatingLane() {
        withAnimation(ProMotionSprings.snappy) {
            isCreatingLane = false
            newLaneName = ""
        }
    }

    private func createLane() {
        let trimmed = newLaneName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { cancelCreatingLane(); return }
        Task {
            if let lane = try? await destinationRepository.createLane(named: trimmed) {
                withAnimation(ProMotionSprings.snappy) {
                    newLaneName = ""
                    isCreatingLane = false
                    open(.captureLane(id: lane.uuid))
                }
            }
        }
    }

    private var deleteLaneDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteLane != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteLane = nil
                }
            }
        )
    }

    private func deleteLane(_ destination: CaptureDestination) {
        Task {
            do {
                try await destinationRepository.archive(uuid: destination.uuid)
                await MainActor.run {
                    withAnimation(ProMotionSprings.gentle) {
                        if currentDestination == .inbox && inboxRoute == .captureLane(id: destination.uuid) {
                            inboxRoute = .captureLanes
                        }
                        pendingDeleteLane = nil
                    }
                }
            } catch {
                print("SidebarInboxContext.deleteLane failed: \(error)")
                PersistenceHealth.note(.writeFailure, context: "SidebarInboxContext.deleteLane", detail: error.localizedDescription)
            }
        }
    }

    private func open(_ route: SidebarInboxRoute) {
        withAnimation(ProMotionSprings.snappy) {
            inboxRoute = route
            currentDestination = .inbox
        }
        onNavigate()
    }
}

// MARK: - Swipe File Context

private struct SidebarSwipeFileContext: View {
    @Binding var currentDestination: SidebarDestination
    var onNavigate: () -> Void = {}

    @State private var isCreatingBoard = false
    @State private var draftBoardName = ""
    @State private var countsRefreshTask: Task<Void, Never>?
    @FocusState private var isBoardNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            // The swipe file's rooms: Posts is the always-present landing;
            // every other genre earns its row by having content. A posts-only
            // library shows exactly one row — the spaces reveal themselves as
            // the collection grows (same progressive-disclosure law as the
            // genre facet).
            SidebarSection(title: "Saved") {
                SidebarRow(
                    title: "Posts",
                    mark: .icon(.swipe),
                    isActive: currentDestination == .swipeFile(section: .home)
                        || currentDestination == .swipeFile(section: .all),
                    help: "Posts — up next, new saves and everything"
                ) {
                    open(.home)
                }
                ForEach(SwipeSpaceStore.shared.visibleSpaces, id: \.rawValue) { genre in
                    SidebarRow(
                        title: genre.pluralName,
                        mark: .symbol(genre.iconName),
                        count: SwipeSpaceStore.shared.counts[genre],
                        isActive: currentDestination == .swipeFile(section: .genre(genre))
                    ) {
                        open(.genre(genre))
                    }
                }
            }

            SidebarSection(title: "Explore") {
                discoveryRow(.discover, icon: .discover)
                discoveryRow(.creators, icon: .creators)
            }

            SidebarSection(title: "Boards", count: SwipeBoardStore.shared.boards.count) {
                SidebarRow(
                    title: "All Boards",
                    mark: .icon(.boards),
                    isActive: currentDestination == .swipeFile(section: .boards)
                ) {
                    open(.boards)
                }
                ForEach(SwipeBoardStore.shared.boards) { board in
                    SidebarRow(
                        title: board.name,
                        mark: .symbol(board.icon),
                        count: SwipeBoardStore.shared.counts[board.uuid],
                        isActive: currentDestination == .swipeFile(section: .board(board.uuid))
                    ) {
                        open(.board(board.uuid))
                    }
                }
                if isCreatingBoard {
                    SidebarInlineCreateRow(
                        placeholder: "Board name",
                        symbol: "rectangle.stack.badge.plus",
                        text: $draftBoardName,
                        isFocused: $isBoardNameFocused,
                        onSubmit: createBoard,
                        onCancel: cancelCreatingBoard
                    )
                } else {
                    SidebarRow(title: "New board…", mark: .symbol("plus"), prominence: .ghost, help: "New board") {
                        beginCreatingBoard()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await SwipeBoardStore.shared.loadIfNeeded()
            await SwipeBoardStore.shared.refreshCountsFromDatabase()
            await SwipeSpaceStore.shared.loadIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.SwipeFile.libraryDidChange)) { _ in
            // Coalesce bursts: heal sweeps / classifiers post this once per
            // touched swipe, and each refresh is a full swipe-table read.
            countsRefreshTask?.cancel()
            countsRefreshTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                await SwipeBoardStore.shared.refreshCountsFromDatabase()
                await SwipeSpaceStore.shared.refreshCountsFromDatabase()
            }
        }
    }

    private func discoveryRow(_ section: SwipeDiscoverySectionSelection, icon: CosmoIcon) -> some View {
        SidebarRow(
            title: section.title,
            mark: .icon(icon),
            isActive: currentDestination == .discover(section: section),
            help: section.subtitle
        ) {
            withAnimation(ProMotionSprings.snappy) {
                currentDestination = .discover(section: section)
            }
            onNavigate()
        }
    }

    private func beginCreatingBoard() {
        withAnimation(ProMotionSprings.snappy) {
            isCreatingBoard = true
            draftBoardName = ""
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            isBoardNameFocused = true
        }
    }

    private func cancelCreatingBoard() {
        withAnimation(ProMotionSprings.snappy) {
            isCreatingBoard = false
            draftBoardName = ""
        }
    }

    private func createBoard() {
        let trimmed = draftBoardName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { cancelCreatingBoard(); return }

        withAnimation(ProMotionSprings.snappy) {
            draftBoardName = ""
            isCreatingBoard = false
        }
        Task {
            if let board = await SwipeBoardStore.shared.create(name: trimmed) {
                open(.board(board.uuid))
            }
        }
    }

    private func open(_ section: SwipeLibrarySectionSelection) {
        withAnimation(ProMotionSprings.snappy) {
            currentDestination = .swipeFile(section: section)
        }
        onNavigate()
    }
}
