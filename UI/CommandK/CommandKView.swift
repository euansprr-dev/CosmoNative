// CosmoOS/UI/CommandK/CommandKView.swift
// Cosmo Cortex — Spotlight-inspired morphing Command-K interface
// Three modes: Compact (bubbles + recents) → Search Results → Expanded Domain

import SwiftUI

// MARK: - CommandKView

public struct CommandKView: View {

    // MARK: - Compatibility alias (MainView references CommandKView.CommandKTab)
    typealias CommandKTab = CosmoOS.CommandKTab

    // MARK: - State
    var initialTab: CommandKTab?
    var isActive: Bool
    @StateObject private var viewModel: CommandKViewModel
    @FocusState private var isSearchFocused: Bool
    @Namespace private var cortexNamespace
    @State private var isExpandedBrowserMounted = false
    @State private var domainTransitionTask: Task<Void, Never>?

    @MainActor
    init(
        initialTab: CommandKTab = .database,
        isActive: Bool = true
    ) {
        self.init(
            initialTab: initialTab,
            isActive: isActive,
            viewModel: CommandKViewModel()
        )
    }

    init(
        initialTab: CommandKTab = .database,
        isActive: Bool = true,
        viewModel: CommandKViewModel
    ) {
        if initialTab == .database {
            self.initialTab = nil
        } else {
            self.initialTab = initialTab
        }
        self.isActive = isActive
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    // MARK: - Body

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundLayer
                panelContainer(geometry: geometry)
            }
            .ignoresSafeArea()
            .onAppear {
                viewModel.initialExpandedTab = initialTab
                viewModel.setSurfaceActive(isActive)
                if isActive {
                    viewModel.initializeCortexMode()
                    isSearchFocused = true
                    scheduleExpandedBrowserMountIfNeeded()
                }
            }
            .onChange(of: isActive) { _, active in
                viewModel.setSurfaceActive(active)
                if active {
                    viewModel.initialExpandedTab = initialTab
                    viewModel.initializeCortexMode()
                    isSearchFocused = true
                    scheduleExpandedBrowserMountIfNeeded()
                } else {
                    domainTransitionTask?.cancel()
                    isExpandedBrowserMounted = false
                    isSearchFocused = false
                }
            }
            .onChange(of: viewModel.cortexMode) { _, mode in
                switch mode {
                case .expandedDomain(let tab):
                    isExpandedBrowserMounted = false
                    scheduleExpandedBrowserMount(for: tab)
                case .searchResults:
                    domainTransitionTask?.cancel()
                    isExpandedBrowserMounted = false
                case .compact:
                    isExpandedBrowserMounted = false
                }
            }
        }
        .onKeyPress(.escape) { handleEscape() }
        .onKeyPress(.downArrow) { viewModel.selectNext(); return .handled }
        .onKeyPress(.upArrow) { viewModel.selectPrevious(); return .handled }
        .onKeyPress(.return) { viewModel.openSelected(); return .handled }
        .onKeyPress(.tab) { handleTab() }
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        CortexOverlayBackdrop { closeWithDomainCollapseIfNeeded() }
    }

    // MARK: - Panel Container

    private func panelContainer(geometry: GeometryProxy) -> some View {
        VStack(spacing: DS.space12) {
            searchBarPill(geometry: geometry)
                .zIndex(2)
            contentPanel(geometry: geometry)
                .zIndex(1)
        }
    }

    // MARK: - Search Bar Pill (Spotlight-style)

    private func searchBarPill(geometry: GeometryProxy) -> some View {
        HStack(spacing: DS.space12) {
            // Back button in expanded mode
            if case .expandedDomain = viewModel.cortexMode {
                Button {
                    closeExpandedDomain()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(DS.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(DS.textSecondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .zIndex(2)
                .accessibilityLabel("Back to Command K menu")
            }

            // Search icon
            Image(systemName: searchIcon)
                .font(DS.title2)
                .foregroundStyle(isSearchFocused ? DS.accent : DS.textSecondary)
                .symbolEffect(.pulse, isActive: viewModel.currentPhase == .searching)
                .frame(width: 22)

            // Text field
            TextField(searchPlaceholder, text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(DS.title2)
                .foregroundStyle(DS.text)
                .focused($isSearchFocused)
                .onSubmit { viewModel.openSelected() }

            Spacer()

            // Type prefix badge
            if let prefixType = viewModel.activeTypePrefix {
                typePrefixBadge(prefixType)
            }

            // Task creation hint
            if viewModel.isTaskCreationMode {
                Text("Enter to create task")
                    .font(DS.caption)
                    .foregroundStyle(DS.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DS.accent.opacity(0.12), in: Capsule())
            }

            scopeMenu

            // Voice button
            voiceButton

            if !viewModel.query.isEmpty {
                clearQueryButton
            } else if viewModel.cortexMode == .compact {
                commandKeyBadge
            }

            // Loading spinner
            if viewModel.currentPhase == .searching {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(DS.textSecondary)
            }
        }
        .padding(.horizontal, DS.space20)
        .frame(width: searchBarWidth(for: geometry), height: CommandKMetrics.searchBarHeight)
        .background(
            RoundedRectangle(cornerRadius: CommandKMetrics.searchBarHeight / 2, style: .continuous)
                .fill(DS.surfaceElevated)
        )
        .clipShape(RoundedRectangle(cornerRadius: CommandKMetrics.searchBarHeight / 2, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CommandKMetrics.searchBarHeight / 2, style: .continuous)
                .strokeBorder(isSearchFocused ? DS.gilt.opacity(0.45) : DS.sepiaBorder, lineWidth: isSearchFocused ? 1 : 0.5)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 4)
    }

    // MARK: - Scope Menu (Decision 1C — Spaces as scope filter)

    private var scopeMenu: some View {
        Menu {
            Button("All") {
                if case .expandedDomain = viewModel.cortexMode { closeExpandedDomain() }
            }
            Divider()
            ForEach(CortexScope.allCases) { scope in
                Button(scope.title) { openExpandedDomain(scope.tab) }
            }
        } label: {
            HStack(spacing: DS.space4) {
                Text(scopeLabel)
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DS.textMuted)
            }
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space6)
            .background(DS.vellum, in: Capsule())
            .overlay(Capsule().strokeBorder(DS.sepiaBorder, lineWidth: 0.5))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Search scope")
    }

    private var scopeLabel: String {
        if case .expandedDomain(let tab) = viewModel.cortexMode { return tab.title }
        return "All"
    }

    private enum CortexScope: String, CaseIterable, Identifiable {
        case database, swipe, ideas, library
        var id: String { rawValue }
        var title: String {
            switch self {
            case .database: return "Database"
            case .swipe: return "Swipe File"
            case .ideas: return "Ideas"
            case .library: return "Library"
            }
        }
        var tab: CommandKTab {
            switch self {
            case .database: return .database
            case .swipe: return .swipeGallery
            case .ideas: return .ideas
            case .library: return .readwise
            }
        }
    }

    // MARK: - Domain Bubbles (inline in search bar)

    private var domainBubblesInline: some View {
        HStack(spacing: DS.space6) {
            ForEach(CommandKTab.allCases, id: \.rawValue) { tab in
                CortexInlineBubble(
                    tab: tab,
                    count: viewModel.domainCounts[tab] ?? 0,
                    namespace: cortexNamespace
                ) {
                    openExpandedDomain(tab)
                }
            }
        }
    }

    // MARK: - Content Panel

    @ViewBuilder
    private func contentPanel(geometry: GeometryProxy) -> some View {
        switch viewModel.cortexMode {
        case .compact, .searchResults, .expandedDomain:
            CortexMasterDetailView(
                viewModel: viewModel,
                isDomainHydrated: isMasterDetailDomainHydrated
            )
                .frame(height: contentPanelHeight(for: geometry))
                .frame(width: panelWidth(for: geometry))
                .cortexGlassPanel()
        }
    }

    private var isMasterDetailDomainHydrated: Bool {
        if case .expandedDomain = viewModel.cortexMode {
            return isExpandedBrowserMounted
        }
        return true
    }

    private func contentPanelHeight(for geometry: GeometryProxy) -> CGFloat {
        if case .expandedDomain = viewModel.cortexMode {
            return CommandKExpandedLayout.panelHeight(forAvailableHeight: geometry.size.height)
        }
        return min(geometry.size.height * 0.62, 560)
    }

    // MARK: - Compact Content

    private var compactContent: some View {
        VStack(spacing: 0) {
            if !viewModel.recentItems.isEmpty {
                recentsSection
                    .padding(DS.space20)
            }
            keyboardHintBar
                .padding(.horizontal, DS.space20)
                .padding(.bottom, DS.space12)
        }
    }

    private var keyboardHintBar: some View {
        HStack(spacing: DS.space16) {
            keyHint(keys: "↑↓", label: "Navigate")
            keyHint(keys: "↵", label: "Open")
            keyHint(keys: "⎋", label: "Close")
            Spacer()
        }
    }

    private func keyHint(keys: String, label: String) -> some View {
        HStack(spacing: DS.space4) {
            Text(keys)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(DS.textMuted)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(DS.glassCardFill.opacity(0.5), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(DS.border.opacity(0.15), lineWidth: 0.5)
                )
            Text(label)
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            Text("RECENTS")
                .font(DS.caption)
                .fontWeight(.medium)
                .foregroundStyle(DS.textMuted)
                .tracking(0.5)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: DS.space12)],
                spacing: DS.space12
            ) {
                ForEach(Array(viewModel.recentItems.enumerated()), id: \.element.id) { index, item in
                    CortexRecentCard(item: item) {
                        viewModel.openRecent(item)
                    } onDelete: {
                        viewModel.deleteRecent(item)
                    }
                    .transition(.opacity.combined(with: .offset(y: 6)))
                    .animation(CommandKAnimationPolicy.entranceAnimation(index: index), value: viewModel.recentItems.count)
                }
            }
        }
    }

    // MARK: - Expanded Domain Content

    @ViewBuilder
    private func expandedDomainContent(_ tab: CommandKTab) -> some View {
        CortexExpandedDomainShell(
            tab: tab,
            count: viewModel.domainCounts[tab] ?? 0,
            preview: viewModel.headerPreviews[tab] ?? CommandKHeaderPreviewComposer.fallback(for: tab),
            namespace: cortexNamespace
        ) {
            if isExpandedBrowserMounted {
                expandedBrowser(for: tab)
                    .transition(.opacity.animation(.easeOut(duration: 0.10)))
            } else {
                CortexExpandedDomainTransitionBody(tab: tab)
                    .transition(.opacity.animation(.easeOut(duration: 0.08)))
            }
        }
    }

    @ViewBuilder
    private func expandedBrowser(for tab: CommandKTab) -> some View {
        switch tab {
        case .database:
            CortexDatabaseBrowser(viewModel: viewModel)
        case .swipeGallery:
            CortexSwipeBrowser(viewModel: viewModel)
        case .ideas:
            CortexIdeasBrowser(viewModel: viewModel)
        case .readwise:
            CortexReadwiseBrowser(viewModel: viewModel)
        case .inquiry:
            CortexInquiryBrowser(viewModel: viewModel)
        }
    }

    // MARK: - Expanded Tab Chip

    private func expandedTabChip(_ tab: CommandKTab) -> some View {
        HStack(spacing: DS.space4) {
            Image(systemName: tab.icon)
                .font(DS.caption2)
            Text(tab.title)
                .font(DS.caption)
        }
        .foregroundStyle(tab.accentColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tab.accentColor.opacity(0.12), in: Capsule())
    }

    // MARK: - Voice Button

    private var voiceButton: some View {
        Button {
            viewModel.isVoiceActive.toggle()
        } label: {
            Image(systemName: viewModel.isVoiceActive ? "mic.fill" : "mic")
                .font(DS.callout)
                .foregroundStyle(viewModel.isVoiceActive ? DS.accent : DS.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(viewModel.isVoiceActive ? DS.accent.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    private var clearQueryButton: some View {
        Button {
            withAnimation(ProMotionSprings.snappy) {
                viewModel.query = ""
            }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(DS.textMuted)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear search")
    }

    private var commandKeyBadge: some View {
        Text("⌘ K")
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(DS.textSecondary)
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space8)
            .background(DS.glassCardFill.opacity(0.72), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(DS.glassBorder.opacity(0.72), lineWidth: 0.5)
            )
            .accessibilityHidden(true)
    }

    // MARK: - Type Prefix Badge

    @ViewBuilder
    private func typePrefixBadge(_ type: AtomType) -> some View {
        HStack(spacing: DS.space4) {
            Image(systemName: iconForType(type))
                .font(DS.caption2)
            Text(type.displayName)
                .font(DS.caption)
        }
        .foregroundStyle(entityColor(type))
        .padding(.horizontal, DS.space8)
        .padding(.vertical, DS.space4)
        .background(entityColor(type).opacity(0.15), in: Capsule())
    }

    // MARK: - Panel Sizing

    private func panelWidth(for geometry: GeometryProxy) -> CGFloat {
        let availableWidth = max(320, geometry.size.width - 96)

        switch viewModel.cortexMode {
        case .compact:
            return min(CommandKMetrics.compactWidth, availableWidth)
        case .searchResults:
            return min(CommandKMetrics.searchWidth, availableWidth)
        case .expandedDomain(let tab):
            let targetWidth: CGFloat = tab == .ideas ? 1120 : CommandKMetrics.expandedWidth
            return min(targetWidth, availableWidth)
        }
    }

    private func searchBarWidth(for geometry: GeometryProxy) -> CGFloat {
        let availableWidth = max(320, geometry.size.width - 160)

        switch viewModel.cortexMode {
        case .compact:
            return min(CommandKMetrics.compactSearchWidth, availableWidth)
        case .searchResults:
            return min(CommandKMetrics.expandedSearchWidth, availableWidth)
        case .expandedDomain:
            return min(CommandKMetrics.expandedSearchWidth, availableWidth)
        }
    }

    // MARK: - Helpers

    private var searchIcon: String {
        viewModel.isTaskCreationMode ? "plus.circle.fill" : "magnifyingglass"
    }

    private var searchPlaceholder: String {
        if case .expandedDomain(let tab) = viewModel.cortexMode {
            return tab.searchPlaceholder
        }
        return "Search your mind..."
    }

    private func entityColor(_ type: AtomType) -> Color {
        switch type {
        case .idea: return DS.entityIdea
        case .task: return DS.entityTask
        case .content: return DS.entityContent
        case .research: return DS.entityResearch
        case .connection: return DS.entityConnection
        case .project: return DS.entityIdea
        default: return DS.textSecondary
        }
    }

    private func iconForType(_ type: AtomType) -> String {
        switch type {
        case .idea: return "lightbulb.fill"
        case .task: return "checkmark.circle.fill"
        case .research: return "book.fill"
        case .content: return "doc.text.fill"
        case .connection: return "doc.fill"
        case .project: return "folder.fill"
        default: return "circle.fill"
        }
    }

    // MARK: - Keyboard Handlers

    private func handleEscape() -> KeyPress.Result {
        switch viewModel.cortexMode {
        case .expandedDomain:
            if viewModel.isMultiSelectActive {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.clearSelection()
                }
            } else {
                closeExpandedDomain()
            }
        case .searchResults:
            viewModel.query = ""
        case .compact:
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
        }
        return .handled
    }

    private func handleTab() -> KeyPress.Result {
        return .handled
    }

    private func closeWithDomainCollapseIfNeeded() {
        if case .expandedDomain = viewModel.cortexMode {
            closeExpandedDomain()
            DispatchQueue.main.asyncAfter(deadline: .now() + CommandKDomainTransitionPolicy.closeNotificationDelay) {
                NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
            }
        } else {
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
        }
    }

    private func openExpandedDomain(_ tab: CommandKTab) {
        domainTransitionTask?.cancel()
        isExpandedBrowserMounted = false

        withAnimation(ProMotionSprings.modal) {
            viewModel.transitionToExpanded(tab, loadDataImmediately: false)
        }

        scheduleExpandedBrowserMount(for: tab)
    }

    private func closeExpandedDomain() {
        domainTransitionTask?.cancel()

        withAnimation(.easeOut(duration: 0.08)) {
            isExpandedBrowserMounted = false
        }

        domainTransitionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(CommandKDomainTransitionPolicy.collapseCommitDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard case .expandedDomain = viewModel.cortexMode else { return }

            withAnimation(ProMotionSprings.modal) {
                viewModel.returnToCompact(refreshRecents: false)
            }

            try? await Task.sleep(nanoseconds: UInt64(0.18 * 1_000_000_000))
            guard !Task.isCancelled, viewModel.cortexMode == .compact else { return }
            await viewModel.loadRecentsForCompact()
        }
    }

    private func scheduleExpandedBrowserMountIfNeeded() {
        if case .expandedDomain(let tab) = viewModel.cortexMode {
            isExpandedBrowserMounted = false
            scheduleExpandedBrowserMount(for: tab)
        }
    }

    private func scheduleExpandedBrowserMount(for tab: CommandKTab) {
        domainTransitionTask?.cancel()
        domainTransitionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(CommandKDomainTransitionPolicy.browserMountDelay * 1_000_000_000))
            guard !Task.isCancelled,
                  case .expandedDomain(let currentTab) = viewModel.cortexMode,
                  currentTab == tab else { return }

            withAnimation(.easeOut(duration: 0.10)) {
                isExpandedBrowserMounted = true
            }

            let hydrationDelay = max(0, CommandKDomainTransitionPolicy.dataHydrationDelay - CommandKDomainTransitionPolicy.browserMountDelay)
            try? await Task.sleep(nanoseconds: UInt64(hydrationDelay * 1_000_000_000))
            guard !Task.isCancelled,
                  case .expandedDomain(let hydratedTab) = viewModel.cortexMode,
                  hydratedTab == tab else { return }
            viewModel.ensureExpandedDomainDataLoaded(tab)
        }
    }
}

// MARK: - Expanded Domain Shell

private struct CortexExpandedDomainTransitionBody: View {
    let tab: CommandKTab

    var body: some View {
        ZStack {
            tab.accentColor.opacity(0.045)
            VStack(spacing: DS.space10) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(tab.accentColor.opacity(0.20))
                    .frame(width: 96, height: 6)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(DS.textMuted.opacity(0.12))
                    .frame(width: 156, height: 6)
            }
            .opacity(0.55)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

private struct CortexExpandedDomainShell<Content: View>: View {
    let tab: CommandKTab
    let count: Int
    let preview: CommandKHeaderPreviewContent
    let namespace: Namespace.ID
    let content: () -> Content

    init(
        tab: CommandKTab,
        count: Int,
        preview: CommandKHeaderPreviewContent,
        namespace: Namespace.ID,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.tab = tab
        self.count = count
        self.preview = preview
        self.namespace = namespace
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(bodyBackground)
        }
        .clipShape(.rect(cornerRadius: CommandKMetrics.overlayCornerRadius))
        .matchedGeometryEffect(id: "domain-card-\(tab.rawValue)", in: namespace)
    }

    private var header: some View {
        ZStack {
            CommandKHeaderScene(tab: tab, preview: preview)
            headerLegibilityScrim
            if tab == .database {
                databaseHeaderContent
            } else {
                headerContent
            }
        }
        .frame(height: headerHeight)
        .clipped()
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.22))
                .frame(height: 0.5)
        }
    }

    private var headerHeight: CGFloat {
        switch tab {
        case .ideas: return 164
        default: return 156
        }
    }

    private var headerLegibilityScrim: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.10),
                    Color.black.opacity(0.00),
                    Color.black.opacity(0.00),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            LinearGradient(
                colors: [
                    Color.black.opacity(0.00),
                    Color.black.opacity(tab == .ideas ? 0.12 : 0.08),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }

    private var headerContent: some View {
        HStack(alignment: .top) {
            titleBlock
                .padding(.leading, titleLeadingPadding)
                .padding(.top, titleTopPadding)

            Spacer()
        }
        .allowsHitTesting(false)
    }

    private var databaseHeaderContent: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            titleBlock
            databaseHeaderChips
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, 46)
        .padding(.top, 36)
        .allowsHitTesting(false)
    }

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: DS.space12) {
            if let icon = titleIconName {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .frame(width: 30, height: 34)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: DS.space8) {
                Text(tab.title)
                    .font(.system(size: 29, weight: .semibold))
                    .foregroundStyle(.white)

                Text("\(count.formatted(.number)) items")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.white.opacity(0.84))
            }
        }
        .shadow(color: Color.black.opacity(0.16), radius: 10, x: 0, y: 3)
    }

    private var titleIconName: String? {
        switch tab {
        case .swipeGallery, .readwise: return "folder.fill"
        default: return nil
        }
    }

    private var titleLeadingPadding: CGFloat {
        switch tab {
        case .database, .ideas: return 46
        default: return 34
        }
    }

    private var titleTopPadding: CGFloat {
        switch tab {
        case .ideas: return 48
        default: return 42
        }
    }

    private var databaseHeaderChips: some View {
        HStack(spacing: DS.space8) {
            shellChip("All Objects", icon: "square.grid.2x2", isActive: true)
            shellChip("Recent", icon: "clock", isActive: false)
        }
    }

    private var bodyBackground: some View {
        Group {
            if tab == .swipeGallery && DS.palette.isDark {
                LinearGradient(
                    colors: [Color(hex: "1D1B17"), Color(hex: "11100E")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else if tab == .swipeGallery {
                LinearGradient(
                    colors: [DS.vellum.opacity(0.96), DS.vellumDeep.opacity(0.82)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                DS.glassCardFill.opacity(0.12)
            }
        }
    }

    private func shellChip(_ title: String, icon: String, isActive: Bool) -> some View {
        HStack(spacing: DS.space8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 14, weight: .medium))
        }
        .foregroundStyle(isActive ? Color(hex: "18261D") : Color.white.opacity(0.9))
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(
            Capsule()
                .fill(isActive ? Color.white.opacity(0.88) : Color.white.opacity(0.16))
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(isActive ? 0.55 : 0.20), lineWidth: 0.5)
        )
    }
}

private struct CommandKHeaderScene: View {
    let tab: CommandKTab
    let preview: CommandKHeaderPreviewContent

    private var palette: CommandKHeaderMastheadPalette {
        CommandKHeaderMastheadPalette.palette(for: tab)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                CommandKHeaderMastheadBackground(palette: palette)

                Rectangle()
                    .fill(Color.black.opacity(0.16))
                    .frame(width: proxy.size.width * 0.32)
                    .frame(maxHeight: .infinity)
                    .position(x: proxy.size.width * 0.16, y: proxy.size.height / 2)

                CommandKHeaderContentPreview(preview: preview, palette: palette)
                    .frame(width: min(proxy.size.width * 0.54, 570), height: proxy.size.height * 0.70)
                    .position(x: proxy.size.width * 0.69, y: proxy.size.height * 0.52)
            }
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CommandKHeaderMastheadPalette {
    let background: [Color]
    let accent: Color
    let line: Color
    let cardFill: Color
    let cardStroke: Color
    let text: Color

    static func palette(for tab: CommandKTab) -> CommandKHeaderMastheadPalette {
        switch tab {
        case .database, .inquiry:
            return CommandKHeaderMastheadPalette(
                background: [Color(hex: "1D432A"), Color(hex: "163520"), Color(hex: "0B1C12")],
                accent: Color(hex: "A9CFB0"),
                line: Color(hex: "D6E6D4"),
                cardFill: Color(hex: "EFF5EC"),
                cardStroke: Color(hex: "DDEBDD"),
                text: Color(hex: "F6FBF3")
            )
        case .swipeGallery:
            return CommandKHeaderMastheadPalette(
                background: [Color(hex: "A16E34"), Color(hex: "7A4A1D"), Color(hex: "3A1E0A")],
                accent: Color(hex: "FFD08C"),
                line: Color(hex: "F7D9AA"),
                cardFill: Color(hex: "F8E8D0"),
                cardStroke: Color(hex: "F2D2A1"),
                text: Color(hex: "FFF9EF")
            )
        case .ideas:
            return CommandKHeaderMastheadPalette(
                background: [Color(hex: "4B4387"), Color(hex: "312B67"), Color(hex: "19163D")],
                accent: Color(hex: "CFC5FF"),
                line: Color(hex: "DDD7FF"),
                cardFill: Color(hex: "F3F0FA"),
                cardStroke: Color(hex: "D9D1F4"),
                text: Color(hex: "FAF8FF")
            )
        case .readwise:
            return CommandKHeaderMastheadPalette(
                background: [Color(hex: "A87338"), Color(hex: "7D4D24"), Color(hex: "43240D")],
                accent: Color(hex: "F1C48B"),
                line: Color(hex: "F2D8B4"),
                cardFill: Color(hex: "F4E4CE"),
                cardStroke: Color(hex: "E5C9A5"),
                text: Color(hex: "FFF7ED")
            )
        }
    }
}

private struct CommandKHeaderMastheadBackground: View {
    let palette: CommandKHeaderMastheadPalette

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: palette.background,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [palette.accent.opacity(0.20), .clear],
                    center: .center,
                    startRadius: 12,
                    endRadius: proxy.size.width * 0.44
                )
                .frame(width: proxy.size.width * 0.70, height: proxy.size.height * 1.65)
                .position(x: proxy.size.width * 0.69, y: proxy.size.height * 0.36)
                .blendMode(.screen)

                CommandKHeaderRuledTexture(color: palette.line)
            }
        }
    }
}

private struct CommandKHeaderRuledTexture: View {
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ForEach(0..<7, id: \.self) { index in
                Rectangle()
                    .fill(color.opacity(index == 0 ? 0.06 : 0.035))
                    .frame(height: 0.6)
                    .position(
                        x: proxy.size.width / 2,
                        y: proxy.size.height * CGFloat(index + 1) / 8
                    )
            }
        }
    }
}

private struct CommandKHeaderContentPreview: View {
    let preview: CommandKHeaderPreviewContent
    let palette: CommandKHeaderMastheadPalette

    var body: some View {
        Group {
            switch preview.signal {
            case .objectIndex:
                CommandKHeaderObjectIndex(preview: preview, palette: palette)
            case .swipeThumbnails:
                CommandKHeaderVisualStrip(preview: preview, palette: palette, tileStyle: .swipe)
            case .ideaSnippets:
                CommandKHeaderIdeaSnippetStrip(preview: preview, palette: palette)
            case .libraryCovers:
                CommandKHeaderVisualStrip(preview: preview, palette: palette, tileStyle: .cover)
            }
        }
    }
}

private struct CommandKHeaderObjectIndex: View {
    let preview: CommandKHeaderPreviewContent
    let palette: CommandKHeaderMastheadPalette

    var body: some View {
        VStack(spacing: 7) {
            if preview.items.isEmpty {
                CommandKHeaderSkeletonRows(palette: palette)
            } else {
                ForEach(preview.items.prefix(3)) { item in
                    CommandKHeaderObjectRow(item: item, palette: palette)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(contentPanel)
    }

    private var contentPanel: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.black.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.6)
            )
    }
}

private struct CommandKHeaderObjectRow: View {
    let item: CommandKHeaderPreviewItem
    let palette: CommandKHeaderMastheadPalette

    var body: some View {
        HStack(spacing: 10) {
            CommandKHeaderGlyph(systemImage: item.systemImage, palette: palette)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.text.opacity(0.95))
                    .lineLimit(1)

                Text([item.subtitle, item.detail].compactMap { $0 }.joined(separator: " / "))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.text.opacity(0.58))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private enum CommandKHeaderVisualTileStyle {
    case swipe
    case cover
}

private struct CommandKHeaderVisualStrip: View {
    let preview: CommandKHeaderPreviewContent
    let palette: CommandKHeaderMastheadPalette
    let tileStyle: CommandKHeaderVisualTileStyle

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if preview.items.isEmpty {
                ForEach(0..<5, id: \.self) { _ in
                    CommandKHeaderSkeletonTile(palette: palette, tileStyle: tileStyle)
                }
            } else {
                ForEach(preview.items.prefix(5)) { item in
                    CommandKHeaderVisualTile(item: item, palette: palette, tileStyle: tileStyle)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            CommandKHeaderMetricStack(metrics: preview.metrics, palette: palette)
                .offset(x: 4, y: -6)
        }
    }
}

private struct CommandKHeaderVisualTile: View {
    let item: CommandKHeaderPreviewItem
    let palette: CommandKHeaderMastheadPalette
    let tileStyle: CommandKHeaderVisualTileStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CommandKHeaderThumbnail(
                urlString: item.thumbnailURL,
                systemImage: item.systemImage,
                palette: palette
            )
            .frame(width: tileWidth, height: imageHeight)

            Text(item.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.text.opacity(0.84))
                .lineLimit(2)
                .frame(width: tileWidth, alignment: .leading)
        }
        .frame(width: tileWidth, height: tileHeight, alignment: .top)
    }

    private var tileWidth: CGFloat {
        switch tileStyle {
        case .swipe: return 94
        case .cover: return 64
        }
    }

    private var imageHeight: CGFloat {
        switch tileStyle {
        case .swipe: return 58
        case .cover: return 82
        }
    }

    private var tileHeight: CGFloat {
        switch tileStyle {
        case .swipe: return 92
        case .cover: return 116
        }
    }
}

private struct CommandKHeaderThumbnail: View {
    let urlString: String?
    let systemImage: String
    let palette: CommandKHeaderMastheadPalette

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                CachedAsyncImage(url: url, stableKey: urlString) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty, .failure:
                        thumbnailPlaceholder
                    }
                }
            } else {
                thumbnailPlaceholder
            }
        }
        .clipShape(.rect(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.7)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 5)
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [palette.cardFill.opacity(0.34), Color.white.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(palette.text.opacity(0.62))
        }
    }
}

private struct CommandKHeaderIdeaSnippetStrip: View {
    let preview: CommandKHeaderPreviewContent
    let palette: CommandKHeaderMastheadPalette

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ],
            spacing: 8
        ) {
            if preview.items.isEmpty {
                ForEach(0..<4, id: \.self) { _ in
                    CommandKHeaderSkeletonIdea(palette: palette)
                }
            } else {
                ForEach(preview.items.prefix(4)) { item in
                    CommandKHeaderIdeaSnippet(item: item, palette: palette)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            CommandKHeaderMetricStack(metrics: preview.metrics, palette: palette)
                .offset(x: 6, y: -8)
        }
    }
}

private struct CommandKHeaderIdeaSnippet: View {
    let item: CommandKHeaderPreviewItem
    let palette: CommandKHeaderMastheadPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.subtitle ?? "Idea")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(palette.accent.opacity(0.82))
                .lineLimit(1)

            Text(item.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.text.opacity(0.95))
                .lineLimit(2)
        }
        .padding(10)
        .frame(height: 58, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.6)
        )
    }
}

private struct CommandKHeaderMetricStack: View {
    let metrics: [CommandKHeaderPreviewMetric]
    let palette: CommandKHeaderMastheadPalette

    var body: some View {
        HStack(spacing: 6) {
            ForEach(metrics.prefix(2)) { metric in
                Text(metric.value)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.text.opacity(0.86))
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(Color.black.opacity(0.14), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
            }
        }
    }
}

private struct CommandKHeaderGlyph: View {
    let systemImage: String
    let palette: CommandKHeaderMastheadPalette

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(palette.accent.opacity(0.86))
            .frame(width: 22, height: 22)
            .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct CommandKHeaderSkeletonRows: View {
    let palette: CommandKHeaderMastheadPalette

    var body: some View {
        VStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { index in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 22, height: 22)

                    VStack(alignment: .leading, spacing: 5) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(palette.text.opacity(0.30))
                            .frame(width: CGFloat(124 - index * 18), height: 4)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(palette.text.opacity(0.18))
                            .frame(width: CGFloat(82 - index * 8), height: 3)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}

private struct CommandKHeaderSkeletonTile: View {
    let palette: CommandKHeaderMastheadPalette
    let tileStyle: CommandKHeaderVisualTileStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.10))
                .frame(width: tileWidth, height: imageHeight)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(palette.text.opacity(0.22))
                .frame(width: tileWidth * 0.74, height: 4)
        }
    }

    private var tileWidth: CGFloat { tileStyle == .cover ? 64 : 94 }
    private var imageHeight: CGFloat { tileStyle == .cover ? 82 : 58 }
}

private struct CommandKHeaderSkeletonIdea: View {
    let palette: CommandKHeaderMastheadPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(palette.accent.opacity(0.32))
                .frame(width: 42, height: 4)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(palette.text.opacity(0.24))
                .frame(width: 126, height: 5)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(palette.text.opacity(0.16))
                .frame(width: 96, height: 5)
        }
        .padding(10)
        .frame(height: 58, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Inline Bubble (inside search bar)

/// Small circular bubble shown inline in the search bar (compact mode).
/// Tapping expands to full domain view.
private struct CortexInlineBubble: View {
    let tab: CommandKTab
    let count: Int
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isHovered ? tab.accentColor.opacity(0.18) : tab.accentColor.opacity(0.08))

                Circle()
                    .stroke(isHovered ? tab.accentColor.opacity(0.35) : DS.border.opacity(0.2), lineWidth: 0.5)

                Image(systemName: tab.icon)
                    .font(DS.caption)
                    .foregroundStyle(tab.accentColor)
            }
            .frame(width: 32, height: 32)
            .contentShape(Circle())
            .matchedGeometryEffect(id: "cortexDomain-\(tab.rawValue)", in: namespace)
            .overlay(alignment: .top) {
                // Count badge on hover
                if isHovered && count > 0 {
                    Text("\(count)")
                        .font(DS.caption2)
                        .foregroundStyle(tab.accentColor)
                        .padding(.horizontal, DS.space4)
                        .padding(.vertical, 1)
                        .background(tab.accentColor.opacity(0.15), in: Capsule())
                        .offset(y: -14)
                        .transition(.opacity.combined(with: .offset(y: 4)))
                }
            }
        }
        .buttonStyle(.borderless)
        .onHover { isHovered = $0 }
        .animation(ProMotionSprings.hover, value: isHovered)
        .accessibilityLabel("\(tab.title), \(count) items")
    }
}

// MARK: - Preview

#Preview("Cortex - Compact") {
    CommandKView()
        .frame(width: 1200, height: 800)
}

#Preview("Cortex - Expanded") {
    CommandKView(initialTab: .swipeGallery)
        .frame(width: 1200, height: 800)
}
