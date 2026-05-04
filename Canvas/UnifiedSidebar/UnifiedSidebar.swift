// CosmoOS/Canvas/UnifiedSidebar/UnifiedSidebar.swift
// Main sidebar container — premium docked shell with persisted width
// March 2026 — Command Center navigation

import SwiftUI

// MARK: - Navigation Destination

enum SidebarDestination: Equatable, Hashable {
    case commandCenter
    case inbox
    case codex
    case thinkspace(id: String)
}

enum MainSidebarContentLayoutPolicy {
    static func contentLeadingInset(
        for destination: SidebarDestination,
        isSidebarVisible: Bool,
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

enum SidebarContext: String, CaseIterable, Equatable, Hashable {
    case thinkspaces
    case commandCenter
    case inbox
    case search

    var title: String {
        switch self {
        case .thinkspaces: return "Thinkspaces"
        case .commandCenter: return "Command"
        case .inbox: return "Inbox"
        case .search: return "Search"
        }
    }

    var shortTitle: String {
        switch self {
        case .thinkspaces: return "Home"
        case .commandCenter: return "Command"
        case .inbox: return "Inbox"
        case .search: return "Search"
        }
    }

    var icon: String {
        switch self {
        case .thinkspaces: return "house"
        case .commandCenter: return "target"
        case .inbox: return "tray"
        case .search: return "magnifyingglass"
        }
    }

    var activeIcon: String {
        switch self {
        case .thinkspaces: return "house.fill"
        case .commandCenter: return "target"
        case .inbox: return "tray.fill"
        case .search: return "magnifyingglass"
        }
    }
}

enum SidebarInboxRoute: Equatable, Hashable {
    case global
    case captureLanes
    case captureLane(id: String)
    case manageCommands
}

private enum SidebarSearchScope: String, CaseIterable, Identifiable {
    case all
    case thinkspaces
    case sources
    case notes
    case claims
    case questions
    case outputs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .thinkspaces: return "Thinkspaces"
        case .sources: return "Sources"
        case .notes: return "Notes"
        case .claims: return "Claims"
        case .questions: return "Questions"
        case .outputs: return "Outputs"
        }
    }

    var atomTypes: [AtomType]? {
        switch self {
        case .all:
            return nil
        case .thinkspaces:
            return [.thinkspace]
        case .sources:
            return [.research]
        case .notes:
            return [.note, .stickyNote, .journalEntry]
        case .claims:
            return [.extract]
        case .questions:
            return [.question]
        case .outputs:
            return [.content, .idea]
        }
    }
}

extension Notification.Name {
    static let sidebarCreateThinkspace = Notification.Name("com.cosmo.sidebar.createThinkspace")
    static let sidebarCreateCaptureLane = Notification.Name("com.cosmo.sidebar.createCaptureLane")
    static let sidebarSearchSubmitted = Notification.Name("com.cosmo.sidebar.searchSubmitted")
}

// MARK: - Sidebar Metrics

enum UnifiedSidebarMetrics {
    static let defaultExpandedWidth: CGFloat = 304
    static let minExpandedWidth: CGFloat = 288
    static let maxExpandedWidth: CGFloat = 336
    static let collapsedWidth: CGFloat = 56

    static let headerHeight: CGFloat = 94
    static let footerHeight: CGFloat = 60

    static let expandedOuterPadding: CGFloat = 14
    static let collapsedOuterPadding: CGFloat = 8
    static let contentVerticalPadding: CGFloat = 12
    static let sectionVerticalPaddingExpanded: CGFloat = 12
    static let sectionVerticalPaddingCollapsed: CGFloat = 8
    static let sectionHorizontalPaddingExpanded: CGFloat = 4
    static let sectionHorizontalPaddingCollapsed: CGFloat = 2

    static let moduleRadius: CGFloat = 12
    static let rowRadius: CGFloat = 10
    static let panelCornerRadius: CGFloat = 22

    static let commandPillHeight: CGFloat = 34
    static let standardRowHeight: CGFloat = 42
    static let thinkspaceRowHeight: CGFloat = 38
    static let railHitTarget: CGFloat = 32
    static let hoverRevealTriggerWidth: CGFloat = 18
    static let iconSize: CGFloat = 16
    static let resizeHandleWidth: CGFloat = 8
    static let floatingMargin: CGFloat = 8

    static func clampedExpandedWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, minExpandedWidth), maxExpandedWidth)
    }
}

// MARK: - Sidebar Feature Flags

// MARK: - Shared Sidebar Chrome

struct UnifiedSidebarSection<Content: View>: View {
    let isCollapsed: Bool
    let showsDivider: Bool
    let content: Content

    init(
        isCollapsed: Bool,
        showsDivider: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.isCollapsed = isCollapsed
        self.showsDivider = showsDivider
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(
                    .horizontal,
                    isCollapsed
                        ? UnifiedSidebarMetrics.sectionHorizontalPaddingCollapsed
                        : UnifiedSidebarMetrics.sectionHorizontalPaddingExpanded
                )
                .padding(
                    .vertical,
                    isCollapsed
                        ? UnifiedSidebarMetrics.sectionVerticalPaddingCollapsed
                        : UnifiedSidebarMetrics.sectionVerticalPaddingExpanded
                )

            if showsDivider {
                Rectangle()
                    .fill(DS.sepiaSubtle)
                    .frame(height: 0.5)
                    .padding(.leading, isCollapsed ? 14 : 6)
                    .padding(.trailing, 6)
            }
        }
    }
}

private struct UnifiedSidebarRowChromeModifier: ViewModifier {
    let isActive: Bool
    let isHovered: Bool
    let cornerRadius: CGFloat
    let activeFill: Color
    let hoverFill: Color
    let activeBorder: Color

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isActive ? activeFill.opacity(0.78) : (isHovered ? hoverFill.opacity(0.58) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(isActive ? activeBorder.opacity(0.7) : DS.sidebarMaterialHighlight.opacity(isHovered ? 0.16 : 0), lineWidth: 0.75)
            )
            .overlay(alignment: .topLeading) {
                if isActive {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    DS.sidebarMaterialHighlight.opacity(0.22),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.55
                        )
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    func unifiedSidebarRowChrome(
        isActive: Bool,
        isHovered: Bool,
        cornerRadius: CGFloat = UnifiedSidebarMetrics.rowRadius,
        activeFill: Color = DS.accentSoft,
        hoverFill: Color = DS.surfaceHover,
        activeBorder: Color = DS.sidebarMaterialBorder
    ) -> some View {
        modifier(
            UnifiedSidebarRowChromeModifier(
                isActive: isActive,
                isHovered: isHovered,
                cornerRadius: cornerRadius,
                activeFill: activeFill,
                hoverFill: hoverFill,
                activeBorder: activeBorder
            )
        )
    }
}

// MARK: - Unified Sidebar

struct UnifiedSidebar: View {
    @Binding var currentDestination: SidebarDestination
    @Binding var inboxRoute: SidebarInboxRoute
    @Binding var activeContext: SidebarContext
    @Binding var panelWidth: CGFloat
    @ObservedObject var thinkspaceManager: ThinkspaceManager
    @ObservedObject var commandCenterViewModel: CommandCenterDashboardViewModel
    var sceneTint: CosmoGlassSceneTint = .fallback
    var sceneMaterial: CosmoGlassSceneMaterial? = nil
    var cornerRadius: CGFloat = UnifiedSidebarMetrics.panelCornerRadius
    var sidebarButtonTitle: String = "Close sidebar"
    var sidebarButtonHelp: String = "Close sidebar"
    var onClose: () -> Void = {}
    var onNavigate: () -> Void = {}

    @EnvironmentObject var crossDragManager: CrossThinkspaceDragManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hoveredFooterItem: String?
    @State private var hoveredHeaderItem: String?
    @State private var hoveredContext: SidebarContext?
    @State private var isResizeHandleHovered = false
    @State private var resizeStartWidth: CGFloat?

    private var sidebarWidth: CGFloat {
        panelWidth
    }

    private var outerPadding: CGFloat {
        UnifiedSidebarMetrics.expandedOuterPadding
    }

    private var motionAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.2, dampingFraction: 0.92)
    }

    private var userFirstName: String {
        NSFullUserName().components(separatedBy: " ").first ?? "User"
    }

    private var monogram: String {
        String(userFirstName.prefix(1)).uppercased()
    }

    var body: some View {
        CosmoGlassPanel(
            sceneTint: sceneTint,
            sceneMaterial: sceneMaterial,
            role: .globalSidebar,
            cornerRadius: cornerRadius
        ) {
            VStack(spacing: 0) {
                sidebarHeader

                ScrollView(.vertical) {
                    Group {
                        sidebarBody
                    }
                    .id(activeContext)
                    .transition(.opacity)
                    .padding(.horizontal, outerPadding)
                    .padding(.vertical, UnifiedSidebarMetrics.contentVerticalPadding)
                }
                .scrollIndicators(.hidden)

                sidebarFooter
            }
        }
        .frame(width: sidebarWidth)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .trailing) {
            resizeHandle
                .padding(.trailing, 2)
        }
        .animation(motionAnimation, value: panelWidth)
        .animation(motionAnimation, value: activeContext)
        .onAppear {
            let persistedWidth = UnifiedSidebarMetrics.clampedExpandedWidth(
                StatePersistence.shared.getSidebarWidth()
            )
            panelWidth = persistedWidth
        }
        .onChange(of: panelWidth) { _, newWidth in
            let clamped = UnifiedSidebarMetrics.clampedExpandedWidth(newWidth)
            if clamped != newWidth {
                panelWidth = clamped
                return
            }
            StatePersistence.shared.saveSidebarWidth(clamped)
        }
    }

    // MARK: - Header

    private var sidebarHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cosmo")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.text)
                        .lineLimit(1)

                    Text(activeContext.title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DS.textMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                newMenu

                Button(sidebarButtonTitle, systemImage: "sidebar.left") {
                    withAnimation(motionAnimation) {
                        onClose()
                    }
                }
                .labelStyle(.iconOnly)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.textMuted)
                .frame(width: UnifiedSidebarMetrics.railHitTarget, height: UnifiedSidebarMetrics.railHitTarget)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(hoveredHeaderItem == "close" ? DS.surfaceHover : Color.clear)
                )
                .buttonStyle(.plain)
                .onHover { hoveredHeaderItem = $0 ? "close" : nil }
                .help(sidebarButtonHelp)
                .accessibilityLabel(sidebarButtonTitle)
            }

            contextTabRow
        }
        .padding(.horizontal, outerPadding)
        .frame(height: UnifiedSidebarMetrics.headerHeight)
    }

    @ViewBuilder
    private var newMenu: some View {
        Menu {
            switch activeContext {
            case .thinkspaces:
                Button {
                    NotificationCenter.default.post(name: .sidebarCreateThinkspace, object: nil)
                } label: {
                    Label("New Thinkspace", systemImage: "folder.badge.plus")
                }
            case .commandCenter:
                Button {
                    currentDestination = .commandCenter
                    onNavigate()
                    NotificationCenter.default.post(
                        name: Notification.Name("com.cosmo.commandCenter.quickAddTask"),
                        object: nil
                    )
                } label: {
                    Label("New Task", systemImage: "checkmark.circle")
                }
            case .inbox:
                Button {
                    inboxRoute = .global
                    currentDestination = .inbox
                    onNavigate()
                } label: {
                    Label("Capture Thought", systemImage: "tray.and.arrow.down")
                }
                Button {
                    NotificationCenter.default.post(name: .sidebarCreateCaptureLane, object: nil)
                } label: {
                    Label("New Capture Lane", systemImage: "tray.2")
                }
            case .search:
                Button {
                    NotificationCenter.default.post(name: .showCommandPalette, object: nil)
                } label: {
                    Label("Open Search", systemImage: "magnifyingglass")
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.accent)
                .frame(width: UnifiedSidebarMetrics.railHitTarget, height: UnifiedSidebarMetrics.railHitTarget)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(hoveredHeaderItem == "new" ? DS.accentSoft.opacity(0.86) : DS.accentSoft)
                )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .onHover { hoveredHeaderItem = $0 ? "new" : nil }
        .help("New")
    }

    private var contextTabRow: some View {
        HStack(spacing: 4) {
            ForEach(SidebarContext.allCases, id: \.rawValue) { context in
                contextTab(context)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func contextTab(_ context: SidebarContext) -> some View {
        let isActive = activeContext == context
        let isHovered = hoveredContext == context

        return Button {
            withAnimation(motionAnimation) {
                activeContext = context
            }
        } label: {
            Image(systemName: isActive ? context.activeIcon : context.icon)
                .font(.system(size: 14, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? DS.accent : DS.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isActive ? DS.accentSoft : (isHovered ? DS.surfaceHover : Color.clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredContext = $0 ? context : nil }
        .help(context.title)
        .accessibilityLabel(context.title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - Body

    @ViewBuilder
    private var sidebarBody: some View {
        switch activeContext {
        case .thinkspaces:
            UnifiedSidebarSection(isCollapsed: false) {
                SidebarThinkspaceSection(
                    manager: thinkspaceManager,
                    currentDestination: $currentDestination,
                    isCollapsed: false,
                    onNavigate: onNavigate
                )
            }
        case .commandCenter:
            UnifiedSidebarSection(isCollapsed: false) {
                SidebarCommandCenterContext(
                    viewModel: commandCenterViewModel,
                    currentDestination: $currentDestination,
                    onNavigate: onNavigate
                )
            }
        case .inbox:
            UnifiedSidebarSection(isCollapsed: false) {
                SidebarInboxContext(
                    currentDestination: $currentDestination,
                    inboxRoute: $inboxRoute,
                    onNavigate: onNavigate
                )
            }
        case .search:
            UnifiedSidebarSection(isCollapsed: false) {
                SidebarSearchContext(
                    currentDestination: $currentDestination,
                    onNavigate: onNavigate,
                    onEscape: onClose
                )
            }
        }
    }

    // MARK: - Footer

    private var sidebarFooter: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(DS.glassBorder)
                .frame(height: 0.5)
                .padding(.horizontal, outerPadding)

            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DS.accentSoft)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(monogram)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(DS.accent)
                    )

                Text(userFirstName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button("Settings", systemImage: "gearshape") {
                    NotificationCenter.default.post(
                        name: .showSettings,
                        object: nil
                    )
                }
                .labelStyle(.iconOnly)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DS.textSecondary)
                .frame(width: UnifiedSidebarMetrics.railHitTarget, height: UnifiedSidebarMetrics.railHitTarget)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(hoveredFooterItem == "settings" ? DS.surfaceHover : Color.clear)
                )
                .buttonStyle(.plain)
                .onHover { hoveredFooterItem = $0 ? "settings" : nil }
                .help("Settings")
            }
            .padding(.horizontal, outerPadding)
            .frame(height: UnifiedSidebarMetrics.footerHeight)
        }
    }

    // MARK: - Resize Handle

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: UnifiedSidebarMetrics.resizeHandleWidth)
            .contentShape(Rectangle())
            .overlay(alignment: .center) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(isResizeHandleHovered ? DS.borderActive : DS.sidebarMaterialBorder)
                    .frame(width: 2, height: 52)
                    .opacity(isResizeHandleHovered || resizeStartWidth != nil ? 1 : 0.5)
                    .padding(.trailing, 2)
            }
            .onHover { hovering in
                isResizeHandleHovered = hovering
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if resizeStartWidth == nil {
                            resizeStartWidth = panelWidth
                        }

                        guard let startWidth = resizeStartWidth else { return }
                        panelWidth = UnifiedSidebarMetrics.clampedExpandedWidth(
                            startWidth + value.translation.width
                        )
                    }
                    .onEnded { _ in
                        resizeStartWidth = nil
                    }
            )
    }
}

// MARK: - Sidebar Context Shared Views

private struct SidebarContextLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .textCase(.uppercase)
            .foregroundStyle(DS.textMuted)
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SidebarContextRow: View {
    let title: String
    let icon: String
    var count: Int?
    var subtitle: String?
    var isActive: Bool
    var tint: Color = DS.textSecondary
    var activeTint: Color = DS.accent
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? activeTint : tint)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                        .foregroundStyle(isActive ? DS.text : DS.textSecondary)
                        .lineLimit(1)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DS.textMuted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(isActive ? activeTint : DS.textMuted)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: subtitle == nil ? 34 : 42, alignment: .leading)
            .contentShape(Rectangle())
            .unifiedSidebarRowChrome(
                isActive: isActive,
                isHovered: isHovered,
                activeFill: activeTint.opacity(DS.palette.isDark ? 0.18 : 0.12),
                hoverFill: DS.bg
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - Command Center Context

private struct SidebarCommandCenterContext: View {
    @ObservedObject var viewModel: CommandCenterDashboardViewModel
    @Binding var currentDestination: SidebarDestination
    var onNavigate: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                SidebarContextLabel(title: "Smart Lists")
                ForEach(DashboardViewMode.smartLists, id: \.self) { mode in
                    smartListRow(mode)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                SidebarContextLabel(title: "Planning")
                planningRow("Habits", icon: "repeat", isActive: false)
                planningRow("Reports", icon: "chart.bar", isActive: viewModel.showReports)
                planningRow("Objectives", icon: "scope", isActive: false)
            }

            if !viewModel.areas.isEmpty || !viewModel.projects.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    SidebarContextLabel(title: "Areas & Projects")
                    ForEach(viewModel.areas, id: \.uuid) { area in
                        areaRow(area)
                    }
                    ForEach(projectsWithoutArea, id: \.uuid) { project in
                        projectRow(project, isIndented: false)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await viewModel.loadAreas()
            await viewModel.loadProjects()
            await viewModel.loadAnytimeTasks()
            await viewModel.loadSomedayTasks()
            await viewModel.loadHabits()
        }
    }

    private func smartListRow(_ mode: DashboardViewMode) -> some View {
        SidebarContextRow(
            title: mode.label,
            icon: mode.icon,
            count: badgeCount(for: mode),
            isActive: currentDestination == .commandCenter &&
                viewModel.viewMode == mode &&
                viewModel.selectedProjectUUID == nil &&
                viewModel.selectedAreaUUID == nil &&
                !viewModel.showReports,
            activeTint: mode.activeTint
        ) {
            openCommandCenter()
            withAnimation(ProMotionSprings.snappy) {
                viewModel.selectedProjectUUID = nil
                viewModel.selectedAreaUUID = nil
                viewModel.showReports = false
                viewModel.viewMode = mode
            }
        }
    }

    private func planningRow(_ title: String, icon: String, isActive: Bool) -> some View {
        SidebarContextRow(title: title, icon: icon, isActive: currentDestination == .commandCenter && isActive) {
            openCommandCenter()
            withAnimation(ProMotionSprings.snappy) {
                viewModel.selectedProjectUUID = nil
                viewModel.selectedAreaUUID = nil
                switch title {
                case "Reports":
                    viewModel.showReports = true
                case "Habits":
                    viewModel.showReports = false
                case "Objectives":
                    viewModel.showReports = false
                    viewModel.viewMode = .today
                default:
                    break
                }
            }
        }
    }

    private func areaRow(_ area: Atom) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SidebarContextRow(
                title: area.title ?? "Untitled Area",
                icon: "square.stack",
                isActive: currentDestination == .commandCenter && viewModel.selectedAreaUUID == area.uuid
            ) {
                openCommandCenter()
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.selectedProjectUUID = nil
                    viewModel.selectedAreaUUID = area.uuid
                    viewModel.viewMode = .area
                    viewModel.showReports = false
                }
            }

            ForEach(projectsForArea(area.uuid), id: \.uuid) { project in
                projectRow(project, isIndented: true)
            }
        }
    }

    private func projectRow(_ project: Atom, isIndented: Bool) -> some View {
        SidebarContextRow(
            title: project.title ?? "Untitled Project",
            icon: "folder",
            isActive: currentDestination == .commandCenter && viewModel.selectedProjectUUID == project.uuid,
            tint: DS.textMuted
        ) {
            openCommandCenter()
            withAnimation(ProMotionSprings.snappy) {
                viewModel.selectedAreaUUID = nil
                viewModel.selectedProjectUUID = project.uuid
                viewModel.viewMode = .project
                viewModel.showReports = false
            }
        }
        .padding(.leading, isIndented ? 16 : 0)
    }

    private var projectsWithoutArea: [Atom] {
        viewModel.projects.filter { project in
            project.metadataValue(as: ProjectMetadata.self)?.areaUUID == nil
        }
    }

    private func projectsForArea(_ areaUUID: String) -> [Atom] {
        viewModel.projects.filter { project in
            project.metadataValue(as: ProjectMetadata.self)?.areaUUID == areaUUID
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
        case .project, .area: count = 0
        }
        return count > 0 ? count : nil
    }

    private func openCommandCenter() {
        withAnimation(ProMotionSprings.snappy) {
            if currentDestination != .commandCenter {
                currentDestination = .commandCenter
            }
        }
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
    @FocusState private var isLaneNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                SidebarContextLabel(title: "Capture")
                SidebarContextRow(
                    title: "Global Inbox",
                    icon: "tray.and.arrow.down",
                    count: inboxRepository.unreadCount,
                    isActive: currentDestination == .inbox && inboxRoute == .global,
                    tint: DS.accent
                ) {
                    open(.global)
                }
                SidebarContextRow(
                    title: "Capture Lanes",
                    icon: "tray.2",
                    count: laneCount,
                    isActive: currentDestination == .inbox && inboxRoute == .captureLanes,
                    tint: DS.textSecondary
                ) {
                    open(.captureLanes)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    SidebarContextLabel(title: "Lanes")
                    Spacer()
                    Button("New lane", systemImage: "plus") {
                        withAnimation(ProMotionSprings.snappy) {
                            isCreatingLane = true
                            newLaneName = ""
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isLaneNameFocused = true
                        }
                    }
                    .labelStyle(.iconOnly)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.accent)
                    .frame(width: 24, height: 24)
                    .background(DS.accentSoft, in: .rect(cornerRadius: 8))
                    .buttonStyle(.plain)
                    .help("New Capture Lane")
                }

                if isCreatingLane {
                    newLaneRow
                }

                ForEach(destinationRepository.destinations) { destination in
                    laneRow(destination)
                }

                if destinationRepository.destinations.isEmpty && !isCreatingLane {
                    emptyLaneState
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                SidebarContextLabel(title: "Telegram Commands")
                SidebarContextRow(
                    title: "Manage Commands",
                    icon: "terminal",
                    isActive: currentDestination == .inbox && inboxRoute == .manageCommands
                ) {
                    open(.manageCommands)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            _ = try? await destinationRepository.fetchActive()
            _ = try? await inboxRepository.countUnread()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sidebarCreateCaptureLane)) { _ in
            open(.captureLanes)
            withAnimation(ProMotionSprings.snappy) {
                isCreatingLane = true
                newLaneName = ""
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isLaneNameFocused = true
            }
        }
    }

    private var laneCount: Int? {
        let count = destinationRepository.destinations.reduce(0) { $0 + $1.itemCount }
        return count > 0 ? count : nil
    }

    private var newLaneRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.badge.plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.accent)
                .frame(width: 22, height: 22)
                .background(DS.accentSoft, in: .rect(cornerRadius: 7))

            TextField("Lane name", text: $newLaneName)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.text)
                .focused($isLaneNameFocused)
                .onSubmit { createLane() }

            Button("Cancel", systemImage: "xmark") {
                withAnimation(ProMotionSprings.snappy) {
                    isCreatingLane = false
                    newLaneName = ""
                }
            }
            .labelStyle(.iconOnly)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(DS.textMuted)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .background(DS.bg, in: .rect(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(DS.borderSubtle, lineWidth: 1)
        )
    }

    private func laneRow(_ destination: CaptureDestination) -> some View {
        let alias = destination.aliases.first.map { "\($0):" }
        return SidebarContextRow(
            title: destination.name,
            icon: destination.icon,
            count: destination.itemCount,
            subtitle: alias,
            isActive: currentDestination == .inbox && inboxRoute == .captureLane(id: destination.uuid),
            tint: DS.textSecondary
        ) {
            open(.captureLane(id: destination.uuid))
        }
    }

    private var emptyLaneState: some View {
        Text("No capture lanes yet")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(DS.textMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func createLane() {
        let trimmed = newLaneName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
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

    private func open(_ route: SidebarInboxRoute) {
        withAnimation(ProMotionSprings.snappy) {
            inboxRoute = route
            currentDestination = .inbox
        }
        onNavigate()
    }
}

// MARK: - Search Context

private struct SidebarSearchContext: View {
    @Binding var currentDestination: SidebarDestination
    var onNavigate: () -> Void = {}
    var onEscape: () -> Void = {}

    @AppStorage("unifiedSidebarRecentSearches") private var recentSearchesStorage: String = ""
    @State private var query = ""
    @State private var selectedScope: SidebarSearchScope = .all
    @State private var recentAtoms: [Atom] = []
    @State private var results: [AtomSearchResult] = []
    @State private var isSearching = false
    @FocusState private var isSearchFocused: Bool

    private let searchEngine = AtomSearchEngine()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            searchField
            scopeChips

            if !results.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    SidebarContextLabel(title: "Results")
                    ForEach(results.prefix(6)) { result in
                        atomRow(result.atom, subtitle: result.snippet ?? result.atom.type.displayName)
                    }
                }
            } else {
                recentQuerySection
                recentAtomsSection
                suggestedSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await loadRecentAtoms()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                isSearchFocused = true
            }
        }
        .onChange(of: selectedScope) { _, _ in
            performSearch()
        }
        .onChange(of: query) { _, _ in
            performSearch()
        }
        .onExitCommand {
            handleEscape()
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.textMuted)

            TextField("Search everything...", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.text)
                .focused($isSearchFocused)
                .onSubmit { submitSearch() }
                .onExitCommand { handleEscape() }

            if isSearching {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.62)
            } else if !query.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") {
                    query = ""
                    results = []
                }
                .labelStyle(.iconOnly)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.textMuted)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 36)
        .background(DS.surfaceElevated, in: .rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSearchFocused ? DS.borderActive : DS.borderSubtle, lineWidth: 1)
        )
    }

    private var scopeChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(SidebarSearchScope.allCases) { scope in
                    Button {
                        withAnimation(ProMotionSprings.snappy) {
                            selectedScope = scope
                        }
                    } label: {
                        Text(scope.title)
                            .font(.system(size: 11, weight: selectedScope == scope ? .semibold : .medium))
                            .foregroundStyle(selectedScope == scope ? DS.accent : DS.textMuted)
                            .padding(.horizontal, 9)
                            .frame(height: 26)
                            .background(
                                selectedScope == scope ? DS.accentSoft : DS.bg,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.never)
    }

    @ViewBuilder
    private var recentQuerySection: some View {
        if !recentQueries.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                SidebarContextLabel(title: "Recent Searches")
                ForEach(recentQueries, id: \.self) { recent in
                    SidebarContextRow(
                        title: recent,
                        icon: "clock.arrow.circlepath",
                        isActive: false,
                        tint: DS.textMuted
                    ) {
                        query = recent
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var recentAtomsSection: some View {
        if !recentAtoms.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                SidebarContextLabel(title: "Recent")
                ForEach(recentAtoms.prefix(5), id: \.uuid) { atom in
                    atomRow(atom, subtitle: atom.type.displayName)
                }
            }
        }
    }

    private var suggestedSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SidebarContextLabel(title: "Suggested")
            suggestedRow("Open Loops", icon: "circle.dotted")
            suggestedRow("Weakest Claims", icon: "exclamationmark.bubble")
            suggestedRow("Recent Sources", icon: "doc.text.magnifyingglass")
            suggestedRow("Most Common Problems", icon: "point.3.connected.trianglepath.dotted")
            suggestedRow("My Daily Review", icon: "sun.max")
        }
    }

    private func suggestedRow(_ title: String, icon: String) -> some View {
        SidebarContextRow(title: title, icon: icon, isActive: false, tint: DS.textMuted) {
            query = title
        }
    }

    private func atomRow(_ atom: Atom, subtitle: String) -> some View {
        SidebarContextRow(
            title: atom.title?.isEmpty == false ? atom.title! : "Untitled",
            icon: atom.type.iconName,
            subtitle: subtitle,
            isActive: false,
            tint: DS.textSecondary
        ) {
            open(atom)
        }
    }

    private var recentQueries: [String] {
        recentSearchesStorage
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private func performSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            isSearching = false
            return
        }

        isSearching = true
        Task {
            var options = AtomSearchOptions.default
            options.types = selectedScope.atomTypes
            options.limit = 8
            let found = (try? await searchEngine.search(query: trimmed, options: options)) ?? []
            await MainActor.run {
                guard query.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else { return }
                results = found
                isSearching = false
            }
        }
    }

    private func submitSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        saveRecentQuery(trimmed)
        NotificationCenter.default.post(
            name: .sidebarSearchSubmitted,
            object: nil,
            userInfo: ["query": trimmed, "scope": selectedScope.rawValue]
        )
    }

    private func open(_ atom: Atom) {
        saveRecentQuery(query.trimmingCharacters(in: .whitespacesAndNewlines))
        if atom.type == .thinkspace {
            currentDestination = .thinkspace(id: atom.uuid)
            onNavigate()
            return
        }
        Task {
            try? await NodeGraphEngine.shared.recordAccess(atomUUID: atom.uuid, type: .view)
        }
        NotificationCenter.default.post(
            name: CosmoNotification.NodeGraph.openAtomFromCommandK,
            object: nil,
            userInfo: ["atomUUID": atom.uuid]
        )
        onNavigate()
    }

    private func handleEscape() {
        if query.isEmpty {
            onEscape()
        } else {
            query = ""
            results = []
        }
    }

    private func saveRecentQuery(_ rawQuery: String) {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let updated = ([trimmed] + recentQueries.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame })
            .prefix(6)
        recentSearchesStorage = updated.joined(separator: "\n")
    }

    private func loadRecentAtoms() async {
        let atoms = (try? await AtomRepository.shared.fetchRecent(limit: 8)) ?? []
        await MainActor.run {
            recentAtoms = atoms
        }
    }
}
