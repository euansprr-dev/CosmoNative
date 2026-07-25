// CosmoOS/UI/Ideas/IdeasHomePage.swift
// Ideas — the starting ground where you choose what to make next (July 2026
// Desk reinvention, all three phases). Two views behind one masthead
// switcher: the DESK (default) deals a curated hand — committed work, ranked
// proposals per creator with why-lines, the sparks tray — and ALL IDEAS is a
// Finder-grade management ledger (sort, status filters incl. Archived,
// multi-select, bulk verbs). Client pills scope both; search browses
// everything from anywhere; Space quick-looks; the sparks door opens the
// sorting ritual. The model lives in IdeasPageModel.swift, the engine in
// IdeasDeskEngine.swift, cards in IdeaDeskCards.swift, the ledger in
// IdeasAllView.swift, the panel and ritual in their own files. Manners are
// Mac — hover, tooltips, a full keyboard path, Esc always walks home.

import SwiftUI
import AppKit

// MARK: - View mode

enum IdeasViewMode: String, CaseIterable {
    case desk
    case all

    var label: String {
        switch self {
        case .desk: return "Desk"
        case .all: return "All Ideas"
        }
    }

    var help: String {
        switch self {
        case .desk: return "The desk — choose what to work on (⌘1)"
        case .all: return "Browse and manage every idea (⌘2)"
        }
    }
}

// MARK: - Page

struct IdeasHomePage: View {
    /// A ⌘K jump can land directly on a client's desk.
    @Binding var boardRequest: String?

    /// Owned by MainView (not this view) so launch prewarming can load it
    /// before the first visit and revisits keep their data.
    let model: IdeasPageModel
    @State private var viewMode: IdeasViewMode = .desk
    @State private var selectedClientId: String?
    @State private var searchQuery = ""
    @State private var contextPillVisible = false
    /// Scroll-home is request-token driven through the ScrollViewReader.
    /// NEVER bind a `ScrollPosition` here: the binding writes back on every
    /// scroll frame, invalidating the whole page body per frame — the
    /// canvas-120fps law (gesture frames must not re-enter body) applies to
    /// scrolling too.
    @State private var scrollHomeRequest = 0
    @State private var hasAppeared = false
    /// Keyboard cursor across the visible cards/rows (arrows move, ⏎ opens,
    /// P pins, Space previews).
    @State private var cursorID: String?
    /// The content column's live width — desk tiling follows it.
    @State private var contentWidth: CGFloat = 0
    // Ledger state (the All view)
    @State private var ledgerSort: IdeasLedgerSort = .newest
    @State private var ledgerFilter: IdeasLedgerFilter = .live
    @State private var selection: Set<String> = []
    @State private var selectionAnchor: String?
    // Overlays
    @State private var quickLookID: String?
    @State private var showTriage = false
    @FocusState private var searchFocused: Bool
    @FocusState private var pageFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            SwipePageBackground()
            scrollContent
            overlays
        }
        .task {
            await model.start()
            consumeBoardRequest()
            if !hasAppeared {
                try? await Task.sleep(for: .milliseconds(16))
                withAnimation(reduceMotion ? nil : ProMotionSprings.gentle) { hasAppeared = true }
            }
            pageFocused = true
        }
        .onDisappear { model.stop() }
        .onChange(of: boardRequest) { _, _ in consumeBoardRequest() }
        .onChange(of: viewMode) { _, _ in clearTransientState() }
        .onChange(of: isSearching) { _, _ in clearTransientState() }
        .onExitCommand(perform: handleEscape)
        .background(keyboardLayer)
        .overlay(alignment: .bottom) { bulkBar }
        .overlay(alignment: .bottom) { undoToast }
        .overlay(alignment: .bottom) { SwipeSaveToast(message: toastBinding) }
    }

    // MARK: Scroll scaffold

    private var scrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.space24) {
                    headerGroup
                        .id("ideas-top")
                    content
                }
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { contentWidth = $0 }
                .padding(.horizontal, 48)
                .padding(.top, 36)
                .padding(.bottom, 72)
                .swipeContentMeasure()
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            // Transform to the Bool we care about — the action then fires
            // only when the threshold is CROSSED, not on every frame.
            .onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y > 88 }) { _, shouldShow in
                if shouldShow != contextPillVisible {
                    contextPillVisible = shouldShow
                }
            }
            .overlay(alignment: .top) { contextPill }
            .focusable()
            .focusEffectDisabled()
            .focused($pageFocused)
            .onMoveCommand { direction in moveCursor(direction) }
            .onKeyPress(.return) { openCursor() ? .handled : .ignored }
            .onKeyPress(.space) { toggleQuickLook() ? .handled : .ignored }
            .onKeyPress(.delete) { archiveSelection() ? .handled : .ignored }
            .onKeyPress(KeyEquivalent("p")) { pinCursor() ? .handled : .ignored }
            .onChange(of: cursorID) { _, new in
                guard let new else { return }
                withAnimation(ProMotionSprings.gentle) { proxy.scrollTo(new, anchor: nil) }
            }
            .onChange(of: scrollHomeRequest) { _, _ in
                withAnimation(ProMotionSprings.gentle) {
                    proxy.scrollTo("ideas-top", anchor: .top)
                }
            }
        }
    }

    /// Masthead + scope pills + (in the ledger) the filter/sort rail — the
    /// chrome group holds together at space12; content separates at space24.
    private var headerGroup: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            masthead
            if model.clientGroups.count > 1 {
                clientPills
            }
            if viewMode == .all && !isSearching {
                // The rail aligns with the ledger's measure, centered inside
                // the page measure — chrome and content share one left edge.
                ledgerControls
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Content routing

    @ViewBuilder
    private var content: some View {
        if model.isLoaded && model.searchCorpus.isEmpty {
            IdeasEmptyState(
                icon: "lightbulb",
                headline: "Ideas take shape here",
                teachingLine: "Capture one with ⌘N, or open a swipe and spin an idea out of it."
            )
        } else if isSearching {
            IdeasAllView(
                model: model,
                scopedClientId: nil,
                searchResults: searched,
                filter: .live,
                sort: ledgerSort,
                selection: $selection,
                selectionAnchor: $selectionAnchor,
                cursorID: $cursorID,
                hasAppeared: hasAppeared,
                onOpen: { open($0) },
                onOpenAsPane: { openAsPane($0) },
                onQuickLook: { quickLookID = $0.atomUUID }
            )
        } else if viewMode == .desk {
            deskView
        } else {
            IdeasAllView(
                model: model,
                scopedClientId: selectedClientId,
                searchResults: nil,
                filter: ledgerFilter,
                sort: ledgerSort,
                selection: $selection,
                selectionAnchor: $selectionAnchor,
                cursorID: $cursorID,
                hasAppeared: hasAppeared,
                onOpen: { open($0) },
                onOpenAsPane: { openAsPane($0) },
                onQuickLook: { quickLookID = $0.atomUUID }
            )
        }
    }

    private var deskView: some View {
        IdeasDeskView(
            model: model,
            scopedClientId: selectedClientId,
            contentWidth: contentWidth,
            hasAppeared: hasAppeared,
            cursorID: cursorID,
            onOpen: { open($0) },
            onOpenAsPane: { openAsPane($0) },
            onOpenClientDesk: { clientId in
                withAnimation(ProMotionSprings.snappy) {
                    selectedClientId = clientId
                    cursorID = nil
                }
                scrollHome()
            },
            onOpenAll: { clientId in
                withAnimation(ProMotionSprings.snappy) {
                    viewMode = .all
                    selectedClientId = clientId
                }
                scrollHome()
            },
            onSortSparks: {
                withAnimation(ProMotionSprings.snappy) { showTriage = true }
            }
        )
    }

    // MARK: Overlays (quick look · ritual)

    @ViewBuilder
    private var overlays: some View {
        if showTriage {
            IdeaTriageSheet(
                model: model,
                onOpenIdea: { open($0) },
                onClose: {
                    withAnimation(ProMotionSprings.snappy) { showTriage = false }
                    pageFocused = true
                }
            )
        } else if let idea = quickLookIdea {
            IdeaQuickLookPanel(
                idea: idea,
                model: model,
                onOpen: {
                    quickLookID = nil
                    open(idea)
                },
                onOpenAsPane: {
                    quickLookID = nil
                    openAsPane(idea)
                },
                onClose: {
                    withAnimation(ProMotionSprings.snappy) { quickLookID = nil }
                }
            )
        }
    }

    private var quickLookIdea: IdeaGalleryItem? {
        guard let quickLookID else { return nil }
        return model.searchCorpus.first { $0.atomUUID == quickLookID }
    }

    // MARK: Masthead (a bare title + the view switcher — the masthead law)

    private var masthead: some View {
        HStack(alignment: .center, spacing: DS.space12) {
            SwipeMasthead(title: "Ideas")
            Spacer(minLength: DS.space16)
            CosmoSegmentedSwitcher(
                options: IdeasViewMode.allCases,
                label: { $0.label },
                help: { $0.help },
                selection: $viewMode
            )
            SwipeLibrarySearchField(
                text: $searchQuery,
                isFocused: $searchFocused,
                placeholder: "Find in ideas"
            )
        }
    }

    private var contextPill: some View {
        SwipeContextPill(
            title: "Ideas",
            detail: contextDetail,
            visible: contextPillVisible
        ) {
            scrollHome()
        }
        .padding(.top, DS.space12)
    }

    private var contextDetail: String? {
        if let activeClientName { return activeClientName }
        guard viewMode == .all else { return nil }
        return ledgerFilter == .live ? "All ideas" : ledgerFilter.label
    }

    private var activeClientName: String? {
        guard let selectedClientId else { return nil }
        return model.clientGroups.first { $0.id == selectedClientId }?.name
    }

    // MARK: Client pills (App Store objects: identity, not abstract filters)

    private var clientPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.space8) {
                ForEach(model.clientGroups) { group in
                    ClientObjectPill(
                        name: group.name,
                        tint: group.clientUUID.map { DS.clientColor(for: $0) } ?? DS.textMuted,
                        isSelected: selectedClientId == group.id
                    ) {
                        withAnimation(ProMotionSprings.snappy) {
                            // Tap the selected client again to come home.
                            selectedClientId = selectedClientId == group.id ? nil : group.id
                            cursorID = nil
                            selection.removeAll()
                        }
                    }
                }
            }
            .padding(.vertical, DS.space4)
        }
        .scrollClipDisabled()
    }

    // MARK: Ledger controls (filters ride the masthead group)

    private var ledgerControls: some View {
        let counts = ledgerCounts
        return HStack(spacing: DS.space8) {
            ForEach(IdeasLedgerFilter.allCases, id: \.self) { filter in
                StatusFilterChip(
                    label: filter.label,
                    count: counts[filter] ?? 0,
                    isSelected: ledgerFilter == filter
                ) {
                    withAnimation(ProMotionSprings.snappy) {
                        ledgerFilter = filter
                        selection.removeAll()
                        cursorID = nil
                    }
                }
            }
            Spacer(minLength: DS.space12)
            sortMenu
        }
    }

    /// Every chip count in ONE pass over the corpus (five separate filter
    /// walks per body evaluation is how a header gets slow).
    private var ledgerCounts: [IdeasLedgerFilter: Int] {
        func scoped(_ idea: IdeaGalleryItem) -> Bool {
            guard let selectedClientId else { return true }
            if selectedClientId == "__unassigned__" { return idea.clientUUID == nil }
            return idea.clientUUID == selectedClientId
        }
        var counts: [IdeasLedgerFilter: Int] = [.live: 0, .spark: 0, .developing: 0, .ready: 0, .archived: 0]
        for idea in model.ideas where scoped(idea) {
            counts[.live, default: 0] += 1
            switch idea.status {
            case .spark: counts[.spark, default: 0] += 1
            case .developing: counts[.developing, default: 0] += 1
            case .ready: counts[.ready, default: 0] += 1
            default: break
            }
        }
        for idea in model.archivedIdeas where scoped(idea) {
            counts[.archived, default: 0] += 1
        }
        return counts
    }

    private var sortMenu: some View {
        Menu {
            ForEach(IdeasLedgerSort.allCases, id: \.self) { sort in
                Button {
                    withAnimation(ProMotionSprings.snappy) { ledgerSort = sort }
                } label: {
                    if ledgerSort == sort {
                        Label(sort.label, systemImage: "checkmark")
                    } else {
                        Text(sort.label)
                    }
                }
                .help(sort.help)
            }
        } label: {
            HStack(spacing: DS.space4) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(DS.caption.weight(.medium))
                    .accessibilityHidden(true)
                Text(ledgerSort.label)
                    .font(DS.callout.weight(.medium))
            }
            .foregroundStyle(DS.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Sort the ledger")
    }

    // MARK: Search (tokens match in any order, every honest field — archived included)

    private var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var searched: [IdeaGalleryItem] {
        let tokens = searchQuery.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !tokens.isEmpty else { return model.searchCorpus }
        return model.searchCorpus.filter { idea in
            let haystack = ([
                idea.title,
                idea.body,
                idea.hooks.joined(separator: " "),
                idea.clientName,
                idea.contentFormat?.displayName,
                idea.platform?.displayName,
                idea.status.displayName,
            ] as [String?])
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }

    // MARK: Keyboard manners

    private var keyboardLayer: some View {
        Group {
            Button("") { searchFocused = true }.keyboardShortcut("f", modifiers: .command)
            Button("") { model.createIdea(clientUUID: selectedClientId == "__unassigned__" ? nil : selectedClientId) }
                .keyboardShortcut("n", modifiers: .command)
            Button("") { Task { await model.load() } }.keyboardShortcut("r", modifiers: .command)
            Button("") { switchMode(.desk) }.keyboardShortcut("1", modifiers: .command)
            Button("") { switchMode(.all) }.keyboardShortcut("2", modifiers: .command)
            Button("") { selectAll() }.keyboardShortcut("a", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func switchMode(_ mode: IdeasViewMode) {
        guard viewMode != mode else { return }
        withAnimation(ProMotionSprings.focusTransition) {
            viewMode = mode
        }
    }

    private func clearTransientState() {
        selection.removeAll()
        selectionAnchor = nil
        cursorID = nil
        quickLookID = nil
    }

    private func handleEscape() {
        if quickLookID != nil {
            withAnimation(ProMotionSprings.snappy) { quickLookID = nil }
        } else if searchFocused {
            searchFocused = false
            pageFocused = true
        } else if !searchQuery.isEmpty {
            withAnimation(ProMotionSprings.snappy) { searchQuery = "" }
        } else if !selection.isEmpty {
            withAnimation(ProMotionSprings.snappy) {
                selection.removeAll()
                selectionAnchor = nil
            }
        } else if cursorID != nil {
            cursorID = nil
        } else if selectedClientId != nil {
            withAnimation(ProMotionSprings.snappy) { selectedClientId = nil }
        } else if viewMode == .all {
            switchMode(.desk)
        }
    }

    /// The cursor map: the VISIBLE cards/rows, sectioned. Desk zones read as
    /// rows of cards (←→ walks, ↑↓ jumps zones); the ledger reads as rows
    /// (↑↓ walks, ←→ jumps sections).
    private var cursorSections: [[String]] {
        if isSearching { return [searched.map(\.atomUUID)] }
        if viewMode == .desk {
            return IdeasDeskLayout(contentWidth: contentWidth)
                .cursorSections(model: model, scopedClientId: selectedClientId)
        }
        return IdeasLedger.sections(
            model: model,
            scopedClientId: selectedClientId,
            filter: ledgerFilter,
            sort: ledgerSort,
            searchResults: nil
        ).map { $0.items.map(\.atomUUID) }
    }

    private func moveCursor(_ direction: MoveCommandDirection) {
        let sections = cursorSections.filter { !$0.isEmpty }
        let order = sections.flatMap(\.self)
        guard !order.isEmpty else { return }
        // The ledger walks rows vertically; the desk walks cards horizontally.
        let rowAxis = viewMode == .all || isSearching
        let isStep = rowAxis
            ? (direction == .up || direction == .down)
            : (direction == .left || direction == .right)
        let forward = direction == .down || direction == .right

        var next: String?
        if let current = cursorID, order.contains(current) {
            if isStep {
                if let index = order.firstIndex(of: current), order.indices.contains(index + (forward ? 1 : -1)) {
                    next = order[index + (forward ? 1 : -1)]
                }
            } else if sections.count > 1,
                      let sectionIndex = sections.firstIndex(where: { $0.contains(current) }),
                      sections.indices.contains(sectionIndex + (forward ? 1 : -1)) {
                next = sections[sectionIndex + (forward ? 1 : -1)].first
            }
        } else {
            next = forward ? order.first : order.last
        }
        guard let next else { return }
        cursorID = next

        // Ledger selection follows the cursor (⇧ extends from the anchor).
        if rowAxis {
            let shiftHeld = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
            if shiftHeld, let anchor = selectionAnchor,
               let a = order.firstIndex(of: anchor), let b = order.firstIndex(of: next) {
                selection = Set(order[min(a, b)...max(a, b)])
            } else {
                selection = [next]
                selectionAnchor = next
            }
        }
        // Quick Look follows the cursor while open.
        if quickLookID != nil { quickLookID = next }
    }

    private func openCursor() -> Bool {
        guard quickLookID == nil || quickLookIdea != nil else { return false }
        guard let id = quickLookID ?? cursorID,
              let idea = model.searchCorpus.first(where: { $0.atomUUID == id }) else { return false }
        if quickLookID != nil { quickLookID = nil }
        open(idea)
        return true
    }

    private func pinCursor() -> Bool {
        guard !searchFocused,
              let cursorID,
              let idea = model.ideas.first(where: { $0.atomUUID == cursorID }) else { return false }
        model.togglePin(idea)
        return true
    }

    private func toggleQuickLook() -> Bool {
        guard !searchFocused else { return false }
        if quickLookID != nil {
            withAnimation(ProMotionSprings.snappy) { quickLookID = nil }
            return true
        }
        guard let target = cursorID ?? selection.first,
              model.searchCorpus.contains(where: { $0.atomUUID == target }) else { return false }
        withAnimation(ProMotionSprings.snappy) { quickLookID = target }
        return true
    }

    /// ⌫ in the ledger: archive the selection (recoverable — never delete).
    private func archiveSelection() -> Bool {
        guard viewMode == .all || isSearching, !searchFocused else { return false }
        let items = selectedLedgerItems.filter { $0.status != .archived }
        guard !items.isEmpty else { return false }
        model.bulkArchive(items)
        selection.removeAll()
        selectionAnchor = nil
        return true
    }

    private func selectAll() {
        guard viewMode == .all || isSearching else { return }
        selection = Set(cursorSections.flatMap(\.self))
    }

    private var selectedLedgerItems: [IdeaGalleryItem] {
        let order = cursorSections.flatMap(\.self)
        return order.compactMap { id in
            guard selection.contains(id) else { return nil }
            return model.searchCorpus.first { $0.atomUUID == id }
        }
    }

    // MARK: Bulk bar (the selection's floating verbs)

    @ViewBuilder
    private var bulkBar: some View {
        if (viewMode == .all || isSearching), selection.count > 1 {
            HStack(spacing: DS.space12) {
                Text("\(selection.count) selected")
                    .font(DS.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(DS.text)
                    .contentTransition(.numericText())
                if !model.assignableClients.isEmpty {
                    Menu("Assign") {
                        ForEach(model.assignableClients, id: \.uuid) { client in
                            Button(client.name) {
                                model.bulkAssign(selectedLedgerItems, to: client.uuid)
                                selection.removeAll()
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .font(DS.subheadline.weight(.semibold))
                    .foregroundStyle(DS.accent)
                    .help("Assign the selection to a client")
                }
                Button("Archive") {
                    _ = archiveSelection()
                }
                .buttonStyle(.plain)
                .font(DS.subheadline.weight(.semibold))
                .foregroundStyle(DS.accent)
                .help("Archive the selection (⌫)")
                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        selection.removeAll()
                        selectionAnchor = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(DS.caption.weight(.semibold))
                        .foregroundStyle(DS.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Clear selection (Esc)")
                .accessibilityLabel("Clear selection")
            }
            .padding(.horizontal, 16)
            .frame(height: 34)
            .glassEffect(.regular, in: .capsule)
            .padding(.bottom, 24)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    // MARK: Actions

    private func scrollHome() {
        scrollHomeRequest += 1
    }

    private func open(_ idea: IdeaGalleryItem) {
        guard idea.entityId > 0 else { return }
        NotificationCenter.default.post(
            name: .enterFocusMode,
            object: nil,
            userInfo: ["type": EntityType.idea, "id": idea.entityId]
        )
    }

    private func openAsPane(_ idea: IdeaGalleryItem) {
        guard idea.entityId > 0 else { return }
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.openAsPane,
            object: nil,
            userInfo: ["type": EntityType.idea, "id": idea.entityId]
        )
    }

    private func consumeBoardRequest() {
        guard let request = boardRequest else { return }
        boardRequest = nil
        withAnimation(ProMotionSprings.snappy) {
            // A ⌘K jump lands on the client's DESK — the deciding surface.
            viewMode = .desk
            selectedClientId = model.clientGroups.contains { $0.id == request } ? request : selectedClientId
        }
    }

    // MARK: Toasts

    private var toastBinding: Binding<String?> {
        Binding(
            get: { model.toastMessage },
            set: { model.toastMessage = $0 }
        )
    }

    /// One undo toast slot: a pending delete outranks a pending pass (both
    /// at once is a race the delete should win — it's the destructive one).
    @ViewBuilder
    private var undoToast: some View {
        if model.pendingDelete != nil {
            undoCapsule(message: "Idea deleted") { model.undoDelete() }
        } else if model.pendingPass != nil {
            undoCapsule(message: "Passed — moved to archive") { model.undoPass() }
        }
    }

    private func undoCapsule(message: String, undo: @escaping () -> Void) -> some View {
        HStack(spacing: DS.space12) {
            Text(message)
                .font(DS.subheadline.weight(.medium))
                .foregroundStyle(DS.text)
            Button("Undo", action: undo)
                .buttonStyle(.plain)
                .font(DS.subheadline.weight(.semibold))
                .foregroundStyle(DS.accent)
                .keyboardShortcut("z", modifiers: .command)
                .help("Undo (⌘Z)")
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, 24)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

// MARK: - Status filter chip (the one pill language, filter-sized)

private struct StatusFilterChip: View {
    let label: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space4) {
                Text(label)
                    .font(DS.caption.weight(.medium))
                Text("\(count)")
                    .font(DS.caption2.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? DS.entityIdea : DS.textMuted)
                    .contentTransition(.numericText())
            }
            .foregroundStyle(isSelected ? DS.text : DS.textSecondary)
            .padding(.horizontal, DS.space10)
            .frame(height: 26)
            .background(isSelected ? AnyShapeStyle(DS.entityIdea.opacity(0.14)) : AnyShapeStyle(DS.surfaceElevated))
            .clipShape(.capsule)
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? DS.entityIdea.opacity(0.42) : DS.palette.sepiaBorder,
                    lineWidth: isSelected ? 1 : 0.5
                )
            )
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.02 : 1)
        .animation(ProMotionSprings.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .help("Show \(label.lowercased()) ideas")
        .accessibilityLabel("\(label), \(count) ideas")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Client pill (the App Store object pill)

/// A client as a thing with identity — elevated surface, soft shadow, emoji
/// or color-dot mark. Selection is the app's one selection language.
private struct ClientObjectPill: View {
    let name: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        let identity = CollectionEmoji.resolve(name: name, matchKeywords: false)
        Button(action: action) {
            HStack(spacing: DS.space8) {
                if let emoji = identity.emoji {
                    Text(emoji)
                        .font(.system(size: 14))
                } else {
                    Circle()
                        .fill(tint)
                        .frame(width: 8, height: 8)
                }
                Text(identity.label)
                    .font(DS.callout.weight(.medium))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, DS.space16)
            .frame(height: 34)
            .background(isSelected ? AnyShapeStyle(tint.opacity(0.14)) : AnyShapeStyle(DS.surfaceElevated))
            .clipShape(.capsule)
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? tint.opacity(0.42) : DS.palette.sepiaBorder,
                    lineWidth: isSelected ? 1 : 0.5
                )
            )
            .shadow(color: .black.opacity(isSelected ? 0 : 0.07), radius: 5, y: 2)
            .contentShape(.capsule)
        }
        .buttonStyle(IdeaCardPressStyle())
        .scaleEffect(isHovered ? 1.02 : 1)
        .animation(ProMotionSprings.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .help(isSelected ? "Back to the whole studio" : "\(identity.label)'s ideas")
        .accessibilityLabel("\(identity.label) ideas")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Empty state (absence teaches the fix)

struct IdeasEmptyState: View {
    let icon: String
    let headline: String
    let teachingLine: String

    var body: some View {
        VStack(spacing: DS.space10) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(DS.entityIdea.opacity(0.45))
            Text(headline)
                .font(DS.headline)
                .foregroundStyle(DS.textSecondary)
            Text(teachingLine)
                .font(DS.subheadline)
                .foregroundStyle(DS.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 72)
        .accessibilityElement(children: .combine)
    }
}
