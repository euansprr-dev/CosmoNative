// CosmoOS/UI/CommandK/CommandKView.swift
// Cosmo Cortex — Spotlight-inspired morphing Command-K interface
// Three modes: Compact (bubbles + recents) → Search Results → Expanded Domain

import SwiftUI
import AppKit

// MARK: - CommandKView

public struct CommandKView: View {

    // MARK: - Compatibility alias (MainView references CommandKView.CommandKTab)
    typealias CommandKTab = CosmoOS.CommandKTab

    // MARK: - State
    var initialTab: CommandKTab?
    var isActive: Bool
    var searchFocusRequest: Int
    @State private var viewModel: CommandKViewModel
    @FocusState private var isSearchFocused: Bool
    @Namespace private var cortexNamespace
    @State private var searchText = ""
    @State private var isExpandedBrowserMounted = false
    @State private var domainTransitionTask: Task<Void, Never>?
    @State private var searchFocusTask: Task<Void, Never>?

    @MainActor
    init(
        initialTab: CommandKTab = .database,
        isActive: Bool = true,
        searchFocusRequest: Int = 0
    ) {
        self.init(
            initialTab: initialTab,
            isActive: isActive,
            searchFocusRequest: searchFocusRequest,
            viewModel: CommandKViewModel()
        )
    }

    init(
        initialTab: CommandKTab = .database,
        isActive: Bool = true,
        searchFocusRequest: Int = 0,
        viewModel: CommandKViewModel
    ) {
        if initialTab == .database {
            self.initialTab = nil
        } else {
            self.initialTab = initialTab
        }
        self.isActive = isActive
        self.searchFocusRequest = searchFocusRequest
        _viewModel = State(initialValue: viewModel)
    }

    // MARK: - Body

    /// True while a result card is being dragged OUT of the palette (cursor
    /// beyond the panel) — the overlay ghosts so the canvas underneath can
    /// receive the drop. Dragging back over the panel restores it, keeping
    /// in-palette drop targets (thinkspace filing) live.
    private var isDragGhosted: Bool {
        CommandKDragSession.shared.isActive && CommandKDragSession.shared.isPointerOutsidePalette
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundLayer
                    .opacity(isDragGhosted ? 0 : 1)
                panelContainer(geometry: geometry)
                    .opacity(isDragGhosted ? 0.12 : 1)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .global)
                    } action: { frame in
                        CommandKDragSession.shared.paletteFrameInWindow = frame
                    }
            }
            // The ghosted overlay must not eat the drop or fire tap-to-close;
            // this session-scoped gate lives INSIDE the ⌘K subtree — the
            // ancestor gate in MainView (dead-clicks invariant) stays intact.
            .allowsHitTesting(!isDragGhosted)
            .animation(ProMotionSprings.snappy, value: isDragGhosted)
            .ignoresSafeArea()
            .onAppear {
                searchText = viewModel.query
                viewModel.initialExpandedTab = initialTab
                viewModel.setSurfaceActive(isActive)
                if isActive {
                    viewModel.initializeCortexMode()
                    requestSearchFocus()
                    scheduleExpandedBrowserMountIfNeeded()
                }
            }
            .onChange(of: isActive) { _, active in
                viewModel.setSurfaceActive(active)
                if active {
                    viewModel.initialExpandedTab = initialTab
                    viewModel.initializeCortexMode()
                    requestSearchFocus()
                    scheduleExpandedBrowserMountIfNeeded()
                } else {
                    domainTransitionTask?.cancel()
                    searchFocusTask?.cancel()
                    isExpandedBrowserMounted = false
                    isSearchFocused = false
                    viewModel.isActionPanelPresented = false
                }
            }
            .onChange(of: searchFocusRequest) { _, _ in
                requestSearchFocus()
            }
            .onChange(of: viewModel.isActionPanelPresented) { _, presented in
                // The panel's own field takes focus while it is up; hand the
                // keyboard back to the main search field once it dismisses.
                if !presented { requestSearchFocus() }
            }
            .onChange(of: viewModel.isComposerFocused) { _, focused in
                // Same hand-back contract as the actions panel: leaving the
                // composer returns the keyboard to the search field.
                if focused {
                    isSearchFocused = false
                } else {
                    requestSearchFocus()
                }
            }
            .onChange(of: searchText) { _, newValue in
                viewModel.updateQuery(newValue)
            }
            .onChange(of: viewModel.querySyncToken) { _, _ in
                if searchText != viewModel.query {
                    searchText = viewModel.query
                }
            }
            .onChange(of: isSearchFocused) { _, focused in
                // Drain the field editor's undo stack the moment editing ends so
                // no undo action can outlive the field's backing (see
                // clearSearchFieldUndoStack — prevents the ⌘Z use-after-free crash).
                if !focused { clearSearchFieldUndoStack() }
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
            .onDisappear {
                searchFocusTask?.cancel()
                clearSearchFieldUndoStack()
            }
        }
        .onKeyPress(.escape) { handleEscape() }
        .onKeyPress(.downArrow) {
            guard !viewModel.isActionPanelPresented else { return .ignored }
            viewModel.selectNext()
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard !viewModel.isActionPanelPresented else { return .ignored }
            viewModel.selectPrevious()
            return .handled
        }
        .onKeyPress { handleCommandReturn($0) }
        .onKeyPress(.return) {
            guard !viewModel.isActionPanelPresented else { return .ignored }
            viewModel.openSelected()
            return .handled
        }
        .onKeyPress(keys: [.tab]) { handleTab($0) }
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        CortexOverlayBackdrop { closeWithDomainCollapseIfNeeded() }
    }

    // MARK: - Panel Container

    private func panelContainer(geometry: GeometryProxy) -> some View {
        GlassEffectContainer(spacing: DS.space12) {
            VStack(spacing: DS.space12) {
                searchBarPill(geometry: geometry)
                    .zIndex(2)
                contentPanel(geometry: geometry)
                    .zIndex(3)
            }
        }
    }

    @MainActor
    private func requestSearchFocus() {
        guard isActive else { return }

        // Animated insertion can drop the first FocusState write before the field is attached.
        searchFocusTask?.cancel()
        isSearchFocused = true
        searchFocusTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, isActive else { return }
            isSearchFocused = true

            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled, isActive else { return }
            isSearchFocused = true
        }
    }

    /// Clears the shared field editor's undo stack when the Command-K search
    /// field gives up focus or the overlay tears down.
    ///
    /// The search field is a SwiftUI `TextField` backed by the window's shared
    /// field editor (an `NSTextView`). `NSUndoManager` does **not** retain the
    /// targets of registered undo actions, so if that backing is deallocated
    /// during the overlay's focus/dismissal churn while typed-text undo actions
    /// remain registered, a later ⌘Z (`undo:` → `-[NSUndoManager undoNestedGroup]`
    /// → `-[_NSUndoStack popAndInvoke]`) messages a freed target and hard-crashes
    /// the app (EXC_BAD_ACCESS). Draining the field editor's undo stack the moment
    /// Command-K is done editing removes that dangling state.
    ///
    /// This only touches the shared *field editor* (used by single-line text
    /// fields); the document editor is its own `NSTextView` with a separate undo
    /// manager and is unaffected.
    private func clearSearchFieldUndoStack() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let fieldEditor = window.fieldEditor(false, for: nil) as? NSTextView else { return }
        fieldEditor.undoManager?.removeAllActions()
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
                .help("Back to all results (Esc)")
                .accessibilityLabel("Back to Command K menu")
            }

            // Search icon
            Image(systemName: searchIcon)
                .font(DS.title2)
                .foregroundStyle(isSearchFocused ? DS.accent : DS.textSecondary)
                .frame(width: 22)

            // Text field
            TextField(searchPlaceholder, text: $searchText)
                .textFieldStyle(.plain)
                .font(DS.title2)
                .foregroundStyle(DS.text)
                .focused($isSearchFocused)
                .onSubmit { submitSearchField() }

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

            if !searchText.isEmpty {
                clearQueryButton
            } else if viewModel.cortexMode == .compact {
                commandKeyBadge
            }

        }
        .padding(.horizontal, DS.space20)
        .frame(width: searchBarWidth(for: geometry), height: CommandKMetrics.searchBarHeight)
        .cortexSearchBarPanel(glassID: "cortex-pill", in: cortexNamespace)
        .overlay(
            RoundedRectangle(cornerRadius: CommandKMetrics.searchBarHeight / 2, style: .continuous)
                .strokeBorder(isSearchFocused ? DS.focusRing : Color.clear, lineWidth: isSearchFocused ? 1 : 0)
        )
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
                    .contentTransition(.opacity)
                Image(systemName: "chevron.down")
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(DS.textMuted)
            }
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space6)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .animation(ProMotionSprings.snappy, value: scopeLabel)
        .help("Scope the search (⇥ cycles scopes)")
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
                .cortexGlassPanel(glassID: "cortex-panel", in: cortexNamespace)
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

    private var clearQueryButton: some View {
        Button {
            withAnimation(ProMotionSprings.snappy) {
                searchText = ""
            }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(DS.textMuted)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help("Clear the search")
        .accessibilityLabel("Clear search")
    }

    private var commandKeyBadge: some View {
        Text("⌘K")
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
        case .expandedDomain:
            // Ideas lost its extra-wide board panel when the browse moved to
            // the Ideas surface — every domain shares the one expanded width.
            return min(CommandKMetrics.expandedWidth, availableWidth)
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
        return "Search your mind…"
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
        case .idea: return "lightbulb"
        case .task: return "checkmark.circle"
        case .research: return "book"
        case .content: return "paperplane"
        case .connection: return "point.3.connected.trianglepath.dotted"
        case .project: return "folder"
        default: return "circle"
        }
    }

    // MARK: - Keyboard Handlers

    private func handleEscape() -> KeyPress.Result {
        // Composer focus peels first: Esc steps out of the form back to the
        // search field; the palette stays. Mirrored in MainView's monitor.
        if viewModel.isComposerFocused {
            viewModel.isComposerFocused = false
            return .handled
        }

        if viewModel.isActionPanelPresented {
            viewModel.isActionPanelPresented = false
            return .handled
        }

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
            searchText = ""
        case .compact:
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
        }
        return .handled
    }

    private func handleCommandReturn(_ press: KeyPress) -> KeyPress.Result {
        guard press.key == .return else { return .ignored }
        guard !viewModel.isActionPanelPresented else { return .ignored }
        if press.modifiers.contains(.command) {
            openSelectedAsPaneFromShortcut()
            return .handled
        }
        if press.modifiers.contains(.option) {
            viewModel.placeSelectedOnCanvas()
            return .handled
        }
        return .ignored
    }

    private func submitSearchField() {
        // Return belongs to the actions panel while it is up, even if the main
        // field somehow kept focus — otherwise it opens the item underneath.
        guard !viewModel.isActionPanelPresented else { return }
        let modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command) {
            openSelectedAsPaneFromShortcut()
        } else if modifiers.contains(.option) {
            viewModel.placeSelectedOnCanvas()
        } else {
            viewModel.openSelected()
        }
    }

    private func openSelectedAsPaneFromShortcut() {
        Task { @MainActor in
            await viewModel.openSelectedAsPane()
        }
    }

    private func handleTab(_ press: KeyPress) -> KeyPress.Result {
        guard !viewModel.isActionPanelPresented else { return .ignored }

        // A visible composer owns Tab: step from the search field into the
        // form's first field (Shift-Tab keeps the scope cycle).
        if viewModel.isComposerSubjectSelected,
           !viewModel.isComposerFocused,
           !press.modifiers.contains(.shift) {
            viewModel.isComposerFocused = true
            return .handled
        }
        guard !viewModel.isComposerFocused else { return .ignored }

        let scopes = CortexScope.allCases
        let offset = press.modifiers.contains(.shift) ? -1 : 1

        if case .expandedDomain(let currentTab) = viewModel.cortexMode,
           let index = scopes.firstIndex(where: { $0.tab == currentTab }) {
            let next = scopes[(index + offset + scopes.count) % scopes.count]
            openExpandedDomain(next.tab)
        } else if let edge = offset > 0 ? scopes.first : scopes.last {
            openExpandedDomain(edge.tab)
        }
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

// MARK: - Preview

#Preview("Cortex - Compact") {
    CommandKView()
        .frame(width: 1200, height: 800)
}

#Preview("Cortex - Expanded") {
    CommandKView(initialTab: .swipeGallery)
        .frame(width: 1200, height: 800)
}
