// CosmoOS/Canvas/ThinkspaceLibraryView.swift
// Thinkspace Library — a Finder-grade browser for everything in a thinkspace.
// One chrome row on the app's island baseline (trail + breadcrumb + lenses +
// sort + search), three lenses (Icons / List / Gallery), and the full Finder
// selection grammar: multi-select, marquee, arrow keys, type-to-select,
// Space to peek, Enter to rename. The lenses live in Canvas/Library/.

import SwiftUI
import AppKit

struct ThinkspaceLibraryModeView: View {
    let thinkspaceName: String
    let thinkspaceId: String
    let snapshot: ThinkspaceLibrarySnapshot
    /// Hoisted to CanvasView so the universal navigation trail can walk in
    /// and out of folders (the breadcrumb is the in-page echo of it).
    @Binding var selectedFolderID: UUID?
    let actions: ThinkspaceLibraryActions
    /// Extra leading room for the chrome row only: clears the pinned sidebar
    /// when it's open and the sidebar toggle button when it's hidden. The
    /// content itself stays full-bleed — the glass sidebar floats over it.
    var chromeLeadingInset: CGFloat = 0

    @State private var selection = ThinkspaceLibrarySelectionModel()
    @State private var prefs = ThinkspaceLibraryPrefs()
    @State private var prefsLoadedFor: String?
    @State private var searchText = ""
    /// Inside a folder, search can look through just the folder or everything.
    @State private var searchEntireThinkspace = false
    @State private var kindFilter: String?
    @State private var previewStore = ThinkspaceLibraryPreviewStore()
    /// The staggered tile cascade is an arrival flourish — first mount only.
    @State private var hasCompletedEntranceCascade = false
    @State private var scrollMetrics = CortexScrollMetrics()
    /// Set after keyboard moves so the scroll can chase the focused cell.
    @State private var keyboardScrollTarget: String?
    @FocusState private var searchFocused: Bool
    @FocusState private var browserFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            background
            VStack(alignment: .leading, spacing: DS.space12) {
                toolbar
                    .padding(.leading, chromeLeadingInset)
                    .animation(ProMotionSprings.gentle, value: chromeLeadingInset)
                if isSearching { searchChipsRow }
                lensContent
            }
            .animation(ProMotionSprings.gentle, value: isSearching)
        }
        .background(keyboardShortcutButtons)
        .onAppear(perform: prepare)
        .onChange(of: thinkspaceId) { _, _ in prepare() }
        .onChange(of: snapshot) { _, newValue in previewStore.ensureLoaded(newValue) }
        .onChange(of: prefs) { _, newValue in newValue.save(thinkspaceId: thinkspaceId) }
        .onChange(of: visibleIDs) { _, _ in syncSelection() }
        .onChange(of: searchFocused) { _, focused in
            if !focused { browserFocused = true }
        }
        // Clearing the query (✕, Esc, or deleting text) retires its filters —
        // a kind chip must never keep filtering an unsearched page invisibly.
        .onChange(of: isSearching) { _, searching in
            if !searching {
                kindFilter = nil
                searchEntireThinkspace = false
            }
        }
    }

    private func prepare() {
        if prefsLoadedFor != thinkspaceId {
            prefs = ThinkspaceLibraryPrefs.load(thinkspaceId: thinkspaceId)
            prefsLoadedFor = thinkspaceId
        }
        previewStore.ensureLoaded(snapshot)
        syncSelection()
        browserFocused = true
        Task { @MainActor in hasCompletedEntranceCascade = true }
    }

    // MARK: Chrome

    private var background: some View {
        DS.canvas
            .ignoresSafeArea()
            .filmGrain()
            .contentShape(Rectangle())
            .onTapGesture {
                clearSelection()
                browserFocused = true
            }
    }

    private var toolbar: some View {
        ThinkspaceLibraryToolbar(
            thinkspaceName: thinkspaceName,
            folder: selectedFolder,
            viewMode: viewModeBinding,
            searchText: $searchText,
            searchFocused: $searchFocused,
            sortField: prefs.sortField,
            sortAscending: prefs.sortAscending,
            grouping: prefs.grouping,
            iconScale: prefs.iconScale,
            onSelectSort: selectSort,
            onSelectGrouping: { grouping in
                withAnimation(ProMotionSprings.snappy) { prefs.grouping = grouping }
            },
            onSelectIconScale: { scale in
                withAnimation(ProMotionSprings.gentle) { prefs.iconScale = scale }
            },
            onExitFolder: exitFolder,
            onRenameFolder: actions.renameFolder,
            onDropToRoot: { uuid in
                guard let folder = selectedFolder else { return false }
                actions.removeFromFolder(uuid, folder.id)
                return true
            }
        )
    }

    private var viewModeBinding: Binding<ThinkspaceLibraryViewMode> {
        Binding(
            get: { prefs.viewMode },
            set: { mode in
                withAnimation(ProMotionSprings.focusTransition) { prefs.viewMode = mode }
            }
        )
    }

    /// Re-picking the active field flips direction (Finder); a new field
    /// arrives in its natural direction (names A→Z, dates newest-first).
    private func selectSort(_ field: ThinkspaceLibrarySortField) {
        withAnimation(ProMotionSprings.snappy) {
            if prefs.sortField == field {
                prefs.sortAscending.toggle()
            } else {
                prefs.sortField = field
                prefs.sortAscending = field.defaultAscending
            }
        }
    }

    // MARK: Search chips (scope + kind — only while searching)

    private var searchChipsRow: some View {
        HStack(spacing: DS.space8) {
            if selectedFolder != nil {
                LibraryFilterChip(
                    title: "This Folder",
                    isSelected: !searchEntireThinkspace,
                    tint: DS.accent
                ) { searchEntireThinkspace = false }
                LibraryFilterChip(
                    title: "All of \(thinkspaceName)",
                    isSelected: searchEntireThinkspace,
                    tint: DS.accent
                ) { searchEntireThinkspace = true }
                if !availableKinds.isEmpty {
                    Rectangle()
                        .fill(DS.glassBorder)
                        .frame(width: 1, height: 16)
                }
            }
            ForEach(availableKinds, id: \.self) { kind in
                LibraryFilterChip(
                    title: kind,
                    isSelected: kindFilter == kind,
                    tint: DS.accent
                ) {
                    kindFilter = kindFilter == kind ? nil : kind
                }
            }
            Spacer()
        }
        .padding(.horizontal, DS.space48)
        .transition(.opacity.combined(with: .offset(y: -6)))
        .animation(ProMotionSprings.gentle, value: availableKinds)
    }

    // MARK: Lens content

    @ViewBuilder
    private var lensContent: some View {
        if prefs.viewMode == .gallery {
            galleryLens
        } else {
            browserScroll
        }
    }

    private var galleryLens: some View {
        ThinkspaceLibraryGalleryView(
            items: currentVisibleItems,
            provenance: provenanceLabel,
            context: lensContext
        )
        .padding(.horizontal, DS.space48)
        .padding(.bottom, DS.space24)
        .coordinateSpace(name: ThinkspaceLibrarySpace.name)
        .onTapGesture {
            clearSelection()
            browserFocused = true
        }
        .focusable()
        .focusEffectDisabled()
        .focused($browserFocused)
        .overlay { if shouldShowEmptyState { emptyState } }
        .modifier(LibraryKeyboardModifier(
            selection: selection,
            onMoveScroll: { keyboardScrollTarget = $0 },
            onPeek: peekSelection,
            onRename: beginRenameSelection,
            onEscape: handleEscape
        ))
    }

    private var browserScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                lensSections
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    // The backplane matches the sections' true size, so the
                    // rubber band starts anywhere between and around cells.
                    .background { marqueeBackplane }
                    .overlay(alignment: .topLeading) { marqueeOverlay }
                    .coordinateSpace(name: ThinkspaceLibrarySpace.name)
                    .padding(.top, DS.space6)
                    .padding(.bottom, 110)
                // The page gutter lives INSIDE the scroll clip: edge cells get
                // slack, so hover lift never clips against the viewport.
                .padding(.horizontal, DS.space48)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .animation(ProMotionSprings.gentle, value: snapshot)
                .animation(ProMotionSprings.snappy, value: sortSignature)
                // Folder enter/exit plays the same dialect as document opens.
                .animation(ProMotionSprings.focusTransition, value: selectedFolderID)
                .background(CortexScrollViewIntrospector { scrollMetrics = $0 })
            }
            .scrollIndicators(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .cortexThinScrollbar(metrics: scrollMetrics)
            // Finder's deselect: a click on any empty area of the browser —
            // beside the grid, below the last row — clears the selection.
            // Cell gestures are descendants, so they always win over this.
            .onTapGesture {
                clearSelection()
                browserFocused = true
            }
            .focusable()
            .focusEffectDisabled()
            .focused($browserFocused)
            .overlay { if shouldShowEmptyState { emptyState } }
            .modifier(LibraryKeyboardModifier(
                selection: selection,
                onMoveScroll: { keyboardScrollTarget = $0 },
                onPeek: peekSelection,
                onRename: beginRenameSelection,
                onEscape: handleEscape
            ))
            .onChange(of: keyboardScrollTarget) { _, target in
                guard let target else { return }
                proxy.scrollTo(target, anchor: nil)
                keyboardScrollTarget = nil
            }
        }
    }

    @ViewBuilder
    private var lensSections: some View {
        switch prefs.viewMode {
        case .icons:
            ThinkspaceLibraryIconsView(
                folders: visibleFolders,
                sections: itemSections,
                scale: prefs.iconScale,
                cascadeOnAppear: !hasCompletedEntranceCascade,
                context: lensContext
            )
        case .list:
            ThinkspaceLibraryListView(
                folders: visibleFolders,
                sections: itemSections,
                sortField: prefs.sortField,
                sortAscending: prefs.sortAscending,
                provenance: provenanceLabel,
                dateLabel: { item in
                    cardModel(for: item).updatedAt.map(ThinkspaceLibraryDateLabel.label(for:)) ?? "—"
                },
                onSelectSortColumn: selectSort,
                context: lensContext
            )
        case .gallery:
            EmptyView()
        }
    }

    // MARK: Marquee (rubber-band selection on empty space)

    private var marqueeBackplane: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                clearSelection()
                browserFocused = true
            }
            .gesture(marqueeGesture)
    }

    private var marqueeGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(ThinkspaceLibrarySpace.name))
            .onChanged { value in
                browserFocused = true
                let rect = CGRect(
                    x: min(value.startLocation.x, value.location.x),
                    y: min(value.startLocation.y, value.location.y),
                    width: abs(value.location.x - value.startLocation.x),
                    height: abs(value.location.y - value.startLocation.y)
                )
                let additive = NSApp.currentEvent?.modifierFlags.contains(.command) ?? false
                selection.marqueeChanged(rect, additive: additive)
            }
            .onEnded { _ in selection.marqueeEnded() }
    }

    @ViewBuilder
    private var marqueeOverlay: some View {
        if let rect = selection.marqueeRect {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(DS.accent.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(DS.accent.opacity(0.4), lineWidth: 1)
                )
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: Lens context

    private var lensContext: ThinkspaceLibraryLensContext {
        ThinkspaceLibraryLensContext(
            selection: selection,
            actions: actions,
            folders: snapshot.folders,
            currentFolder: selectedFolder,
            cardModel: cardModel(for:),
            openFolder: openFolder,
            selectedItems: { selectedItems },
            fileSelectionIntoFolder: { folderID in
                for item in selectedItems where item.isOnCanvas {
                    actions.fileIntoFolder(item.entityUuid, folderID)
                }
            },
            deleteFolder: deleteFolder
        )
    }

    private func cardModel(for item: ThinkspaceLibraryItem) -> ThinkspaceLibraryCardModel {
        ThinkspaceLibraryCardModel(item: item, preview: previewStore.previews[item.entityUuid])
    }

    // MARK: Derived state

    private var selectedFolder: ThinkspaceLibraryFolder? {
        selectedFolderID.flatMap { id in snapshot.folders.first { $0.id == id } }
    }

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool { !trimmedSearch.isEmpty }

    /// Token search: every token must appear somewhere in the item's honest
    /// text (title, subtitle, body) — any order, case-insensitive.
    private func matchesSearch(_ item: ThinkspaceLibraryItem) -> Bool {
        let tokens = trimmedSearch.lowercased().split(separator: " ")
        guard !tokens.isEmpty else { return true }
        let haystack = [
            item.title,
            item.block?.subtitle ?? "",
            cardModel(for: item).bodyText ?? ""
        ].joined(separator: " ").lowercased()
        return tokens.allSatisfy { haystack.contains($0) }
    }

    /// While searching, folders leave the stage — results are documents with
    /// provenance (Finder's grammar). At rest, root shows folders + loose items.
    private var visibleFolders: [ThinkspaceLibraryFolder] {
        guard selectedFolder == nil, !isSearching else { return [] }
        return snapshot.folders
    }

    private var searchPool: [ThinkspaceLibraryItem] {
        if let folder = selectedFolder {
            return searchEntireThinkspace ? snapshot.allItems : folder.items
        }
        return isSearching ? snapshot.allItems : snapshot.looseItems
    }

    private var searchResults: [ThinkspaceLibraryItem] {
        guard isSearching else { return searchPool }
        return searchPool.filter(matchesSearch)
    }

    /// Kinds present in the current results — the filter chips derive from
    /// what's actually there, so a chip never leads to an empty screen.
    private var availableKinds: [String] {
        guard isSearching else { return [] }
        var counts: [String: Int] = [:]
        for item in searchResults {
            counts[cardModel(for: item).kindLabel, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.map(\.key)
    }

    private var currentVisibleItems: [ThinkspaceLibraryItem] {
        var items = searchResults
        if let kindFilter {
            items = items.filter { cardModel(for: $0).kindLabel == kindFilter }
        }
        return ThinkspaceLibrarySorter.sort(
            items,
            field: prefs.sortField,
            ascending: prefs.sortAscending,
            kindLabel: { cardModel(for: $0).kindLabel },
            date: { item in
                prefs.sortField == .dateAdded
                    ? previewStore.addedDate(for: item.entityUuid)
                    : previewStore.modifiedDate(for: item.entityUuid)
            }
        )
    }

    /// One section normally; kind-titled sections when grouping is on.
    private var itemSections: [(title: String, items: [ThinkspaceLibraryItem])] {
        let items = currentVisibleItems
        guard !items.isEmpty else { return [] }
        let fallbackTitle = isSearching ? "Results" : "Documents"
        guard prefs.grouping == .kind else { return [(fallbackTitle, items)] }
        var buckets: [String: [ThinkspaceLibraryItem]] = [:]
        for item in items {
            buckets[cardModel(for: item).kindLabel, default: []].append(item)
        }
        return buckets.keys.sorted().map { ($0, buckets[$0] ?? []) }
    }

    private func provenanceLabel(_ item: ThinkspaceLibraryItem) -> String {
        if isSearching, searchEntireThinkspace || selectedFolder == nil,
           let folderTitle = snapshot.folderTitle(for: item.id) {
            return folderTitle
        }
        return item.isOnCanvas ? "On canvas" : "Stored"
    }

    private var selectedItems: [ThinkspaceLibraryItem] {
        selection.selectedIDs.compactMap { id in
            currentVisibleItems.first { $0.id == id }
                ?? snapshot.allItems.first { $0.id == id }
        }
    }

    private var sortSignature: String {
        "\(prefs.sortField.rawValue)-\(prefs.sortAscending)-\(prefs.grouping.rawValue)-\(kindFilter ?? "")"
    }

    /// Everything selectable in visual order — folders first, then sections.
    private var visibleIDs: [String] {
        visibleFolders.map(\.id.uuidString) + itemSections.flatMap { $0.items.map(\.id) }
    }

    private func syncSelection() {
        var titles: [String: String] = [:]
        for folder in visibleFolders { titles[folder.id.uuidString] = folder.title }
        for section in itemSections {
            for item in section.items { titles[item.id] = item.title }
        }
        selection.syncVisible(ids: visibleIDs, titles: titles)
    }

    private var shouldShowEmptyState: Bool {
        visibleFolders.isEmpty && currentVisibleItems.isEmpty
    }

    // MARK: Selection helpers

    private func clearSelection() {
        withAnimation(ProMotionSprings.snappy) { selection.clear() }
    }

    private func peekSelection() {
        guard let primary = selection.primaryID,
              let item = snapshot.allItems.first(where: { $0.id == primary }),
              item.entityId > 0 else { return }
        PeekController.shared.peek(.entity(EntitySelection(id: item.entityId, type: item.entityType)))
    }

    private func beginRenameSelection() {
        guard selection.count == 1, let primary = selection.primaryID else { return }
        selection.renamingID = primary
    }

    private func openSelection() {
        guard let primary = selection.primaryID else { return }
        if let folder = snapshot.folders.first(where: { $0.id.uuidString == primary }) {
            openFolder(folder)
        } else if let item = snapshot.allItems.first(where: { $0.id == primary }) {
            actions.openItem(item)
        }
    }

    /// ⌘⌫, Finder's shortcut: deletes everything selected — documents
    /// tombstone (restorable), folders dissolve (their contents survive).
    private func deleteSelection() {
        guard selection.renamingID == nil, !selection.isEmpty else { return }
        let ids = selection.selectedIDs
        selection.clear()
        for id in ids {
            if let folder = snapshot.folders.first(where: { $0.id.uuidString == id }) {
                deleteFolder(folder)
            } else if let item = snapshot.allItems.first(where: { $0.id == id }) {
                actions.deleteItem(item)
            }
        }
    }

    // MARK: Folder navigation (trail-recorded — folders are places)

    private func openFolder(_ folder: ThinkspaceLibraryFolder) {
        withAnimation(ProMotionSprings.focusTransition) {
            selectedFolderID = folder.id
            selection.clear()
        }
        searchEntireThinkspace = false
        NavigationTrail.shared.recordArrival(
            .libraryFolder(thinkspaceId: thinkspaceId, folderID: folder.id),
            title: folder.title,
            glyph: "folder"
        )
    }

    private func exitFolder() {
        guard selectedFolderID != nil else { return }
        withAnimation(ProMotionSprings.focusTransition) {
            selectedFolderID = nil
            selection.clear()
        }
        NavigationTrail.shared.recordArrival(
            .sidebar(.thinkspace(id: thinkspaceId)),
            title: thinkspaceName,
            glyph: "rectangle.3.group"
        )
    }

    private func deleteFolder(_ folder: ThinkspaceLibraryFolder) {
        if selectedFolderID == folder.id { selectedFolderID = nil }
        NavigationTrail.shared.prune { moment in
            if case .libraryFolder(_, let folderID) = moment.destination {
                return folderID == folder.id
            }
            return false
        }
        actions.deleteFolder(folder.id)
    }

    // MARK: Keyboard

    /// Command-key paths as hidden buttons (the app's shortcut idiom);
    /// character-level keys live in LibraryKeyboardModifier.
    private var keyboardShortcutButtons: some View {
        Group {
            // Esc fallback for when the browser isn't the focused responder
            // (menus, toolbar) — the focused path handles it in onKeyPress.
            Button(action: handleEscape) {}
                .keyboardShortcut(.escape, modifiers: [])
            Button(action: openSelection) {}
                .keyboardShortcut("o", modifiers: .command)
            Button(action: openSelection) {}
                .keyboardShortcut(.downArrow, modifiers: .command)
            Button(action: exitFolder) {}
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button(action: { searchFocused = true }) {}
                .keyboardShortcut("f", modifiers: .command)
            Button(action: { withAnimation(ProMotionSprings.snappy) { selection.selectAll() } }) {}
                .keyboardShortcut("a", modifiers: .command)
            Button(action: deleteSelection) {}
                .keyboardShortcut(.delete, modifiers: .command)
            viewModeShortcuts
            scaleShortcuts
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var viewModeShortcuts: some View {
        ForEach(Array(ThinkspaceLibraryViewMode.allCases.enumerated()), id: \.element) { index, mode in
            Button {
                withAnimation(ProMotionSprings.focusTransition) { prefs.viewMode = mode }
            } label: {}
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
        }
    }

    private var scaleShortcuts: some View {
        Group {
            Button {
                if let up = prefs.iconScale.stepUp {
                    withAnimation(ProMotionSprings.gentle) { prefs.iconScale = up }
                }
            } label: {}
                .keyboardShortcut("=", modifiers: .command)
            Button {
                if let down = prefs.iconScale.stepDown {
                    withAnimation(ProMotionSprings.gentle) { prefs.iconScale = down }
                }
            } label: {}
                .keyboardShortcut("-", modifiers: .command)
        }
    }

    private func handleEscape() {
        if searchFocused || !searchText.isEmpty {
            searchText = ""
            kindFilter = nil
            searchFocused = false
            browserFocused = true
        } else if selection.renamingID != nil {
            selection.renamingID = nil
        } else if !selection.isEmpty {
            clearSelection()
        } else if selectedFolderID != nil {
            exitFolder()
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        ThinkspaceLibraryEmptyState(
            icon: isSearching ? "magnifyingglass" : (selectedFolder == nil ? "square.grid.2x2" : "folder"),
            title: emptyTitle,
            message: emptyMessage
        )
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    private var emptyTitle: String {
        if isSearching { return "No matches for “\(trimmedSearch)”" }
        if selectedFolder != nil { return "This folder is empty" }
        return "This Thinkspace is empty"
    }

    private var emptyMessage: String {
        if isSearching {
            if selectedFolder != nil && !searchEntireThinkspace {
                return "Words match in any order. Try fewer words, or search all of \(thinkspaceName)."
            }
            return "Words match in any order — try fewer or different words."
        }
        if selectedFolder != nil {
            return "Drag any document onto this folder to file it."
        }
        return "Add blocks on the canvas or press ⌘K to capture something — everything lands here."
    }
}

// MARK: - Keyboard modifier (arrows, space, return, type-to-select)

/// The character-level keyboard grammar, shared by the scroll lenses and the
/// gallery. Requires the host to be focusable; command-key shortcuts stay in
/// the hidden-button idiom on the root.
private struct LibraryKeyboardModifier: ViewModifier {
    let selection: ThinkspaceLibrarySelectionModel
    let onMoveScroll: (String) -> Void
    let onPeek: () -> Void
    let onRename: () -> Void
    let onEscape: () -> Void

    func body(content: Content) -> some View {
        content
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow], phases: .down) { press in
                let direction: ThinkspaceLibrarySelectionModel.MoveDirection = switch press.key {
                case .upArrow: .up
                case .downArrow: .down
                case .leftArrow: .left
                default: .right
                }
                let extend = press.modifiers.contains(.shift)
                if let target = selection.move(direction, extend: extend) {
                    onMoveScroll(target)
                }
                return .handled
            }
            .onKeyPress(.space, phases: .down) { _ in
                guard selection.renamingID == nil else { return .ignored }
                onPeek()
                return .handled
            }
            .onKeyPress(.return, phases: .down) { _ in
                guard selection.renamingID == nil, selection.count == 1 else { return .ignored }
                onRename()
                return .handled
            }
            .onKeyPress(.escape, phases: .down) { _ in
                onEscape()
                return .handled
            }
            .onKeyPress(characters: .alphanumerics, phases: .down) { press in
                guard selection.renamingID == nil,
                      press.modifiers.isDisjoint(with: [.command, .control, .option]) else {
                    return .ignored
                }
                if let target = selection.typeToSelect(press.characters) {
                    onMoveScroll(target)
                    return .handled
                }
                return .ignored
            }
    }
}

// MARK: - Filter chip (scope + kind)

private struct LibraryFilterChip: View {
    let title: String
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DS.footnote.weight(.semibold))
                .foregroundStyle(isSelected ? tint : (isHovered ? DS.text : DS.textSecondary))
                .padding(.horizontal, DS.space12)
                .frame(height: 26)
                .background(chipFill, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? tint.opacity(0.42) : DS.glassBorder,
                        lineWidth: 1
                    )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .animation(ProMotionSprings.snappy, value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var chipFill: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(tint.opacity(0.14)) }
        return AnyShapeStyle(isHovered ? DS.glassInputFillFocused : DS.glassInputFill)
    }
}

// MARK: - Empty State

struct ThinkspaceLibraryEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: DS.space16) {
            Image(systemName: icon)
                .font(DS.title1)
                .foregroundStyle(DS.textMuted)
                .frame(width: 68, height: 68)
                .dsGlassSection(cornerRadius: 20)
                .accessibilityHidden(true)
            Text(title)
                .font(DS.headline)
                .foregroundStyle(DS.text)
            Text(message)
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
    }
}
