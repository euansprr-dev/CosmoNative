// CosmoOS/Canvas/ThinkspaceLibraryView.swift
// Thinkspace Library mode — a Finder-grade browser for everything in a thinkspace.
// Folders (clusters) render as macOS-style folder icons in a fixed grid; documents
// render as a Pinterest-style masonry of real-aspect previews (16:9 YouTube,
// 9:16 reels, readable paper notes). Finder interaction grammar: click selects,
// double-click opens, right-click for actions, drag to file into folders.

import SwiftUI
import AppKit

// MARK: - Thinkspace Canvas Mode

enum ThinkspaceCanvasMode: String, CaseIterable, Identifiable {
    case canvas
    case library
    case deepDive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .canvas: return "Canvas"
        case .library: return "Library"
        case .deepDive: return "Deep Dive"
        }
    }

    var icon: String {
        switch self {
        case .canvas: return "square.grid.3x3"
        case .library: return "folder"
        case .deepDive: return "circle.hexagongrid.circle"
        }
    }
}

// MARK: - Models

struct ThinkspaceLibraryItem: Identifiable, Equatable {
    let id: String
    let title: String
    let entityType: EntityType
    let entityId: Int64
    let entityUuid: String
    let isOnCanvas: Bool
    let block: CanvasBlock?
}

struct ThinkspaceLibraryFolder: Identifiable, Equatable {
    let id: UUID
    let title: String
    let colorIndex: Int
    let items: [ThinkspaceLibraryItem]

    var color: Color {
        let index = ((colorIndex % CanvasCluster.palette.count) + CanvasCluster.palette.count) % CanvasCluster.palette.count
        return CanvasCluster.palette[index]
    }
}

struct ThinkspaceLibrarySnapshot: Equatable {
    let folders: [ThinkspaceLibraryFolder]
    let looseItems: [ThinkspaceLibraryItem]

    static func make(
        blocks: [CanvasBlock],
        clusters: [CanvasCluster],
        inventory: [ChildDoc]
    ) -> ThinkspaceLibrarySnapshot {
        var itemsByUUID: [String: ThinkspaceLibraryItem] = [:]

        for doc in inventory where !doc.entityUuid.isEmpty {
            itemsByUUID[doc.entityUuid] = ThinkspaceLibraryItem(
                id: doc.entityUuid,
                title: doc.title,
                entityType: doc.entityType,
                entityId: doc.entityId,
                entityUuid: doc.entityUuid,
                isOnCanvas: false,
                block: nil
            )
        }

        for block in blocks where !block.entityUuid.isEmpty {
            itemsByUUID[block.entityUuid] = ThinkspaceLibraryItem(
                id: block.entityUuid,
                title: block.title.isEmpty ? block.entityType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized : block.title,
                entityType: block.entityType,
                entityId: block.entityId,
                entityUuid: block.entityUuid,
                isOnCanvas: true,
                block: block
            )
        }

        let sortedClusters = clusters.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        let folders = sortedClusters.map { cluster in
            let items = cluster.blockUUIDs
                .compactMap { itemsByUUID[$0] }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            return ThinkspaceLibraryFolder(
                id: cluster.id,
                title: cluster.name,
                colorIndex: cluster.colorIndex,
                items: items
            )
        }

        let clusteredUUIDs = Set(clusters.flatMap(\.blockUUIDs))
        let looseItems = itemsByUUID.values
            .filter { !clusteredUUIDs.contains($0.entityUuid) }
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

        return ThinkspaceLibrarySnapshot(folders: folders, looseItems: looseItems)
    }
}

// MARK: - Atom Preview Store

/// Loads the real document behind each library item — body prose and metadata
/// (thumbnails, platform hints) straight from the atom store — so cards render
/// actual content even for items that only live in storage, never on canvas.
@MainActor
@Observable
final class ThinkspaceLibraryPreviewStore {
    struct AtomPreview: Equatable {
        var body: String?
        var metadata: [String: String]

        static let empty = AtomPreview(body: nil, metadata: [:])
    }

    private(set) var previews: [String: AtomPreview] = [:]
    private var inFlight: Set<String> = []

    func ensureLoaded(_ snapshot: ThinkspaceLibrarySnapshot) {
        let uuids = (snapshot.looseItems + snapshot.folders.flatMap(\.items)).map(\.entityUuid)
        let missing = uuids.filter { previews[$0] == nil && !inFlight.contains($0) }
        guard !missing.isEmpty else { return }
        inFlight.formUnion(missing)
        Task {
            let atoms = (try? await AtomRepository.shared.fetchBatch(uuids: missing)) ?? []
            var loaded: [String: AtomPreview] = [:]
            for atom in atoms {
                var metadata: [String: String] = [:]
                if let dict = atom.metadataDict {
                    for (key, value) in dict {
                        if let string = value as? String { metadata[key] = string }
                    }
                }
                let body = (atom.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                loaded[atom.uuid] = AtomPreview(body: body.isEmpty ? nil : body, metadata: metadata)
            }
            // Unresolved uuids still get an entry so they aren't refetched forever.
            for uuid in missing {
                previews[uuid] = loaded[uuid] ?? .empty
            }
            inFlight.subtract(missing)
        }
    }
}

// MARK: - Card Model

enum ThinkspaceLibraryPreviewKind: Equatable {
    case media(source: String)
    case page(text: String?)
    case connection(preview: String?)
    /// Non-document objects (portals, the live Cosmo block): an object motif
    /// well — a blank white "page" for something that isn't a page reads
    /// broken, not empty.
    case objectMotif(icon: String, tint: Color)
}

/// Everything a card needs to draw an item, resolved from the canvas block's
/// metadata first and the stored atom second — on-canvas and stored items
/// render the same honest preview of their actual content.
struct ThinkspaceLibraryCardModel {
    let item: ThinkspaceLibraryItem
    let metadata: [String: String]
    let bodyText: String?

    init(item: ThinkspaceLibraryItem, preview: ThinkspaceLibraryPreviewStore.AtomPreview?) {
        self.item = item
        var merged = preview?.metadata ?? [:]
        if let blockMetadata = item.block?.metadata {
            merged.merge(blockMetadata) { _, fromBlock in fromBlock }
        }
        self.metadata = merged
        let blockText = ((item.block?.metadata["content"]) ?? item.block?.subtitle ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.bodyText = blockText.isEmpty ? preview?.body : blockText
    }

    /// Remote URL or local path for a visual preview; derives YouTube thumbnails from the source URL.
    var thumbnailSource: String? {
        if let thumb = metadata["thumbnail"], !thumb.isEmpty { return thumb }
        if let path = metadata["imagePath"], !path.isEmpty { return path }
        if let videoId = Self.youTubeVideoID(from: metadata["url"]) {
            return "https://img.youtube.com/vi/\(videoId)/hqdefault.jpg"
        }
        return nil
    }

    var previewKind: ThinkspaceLibraryPreviewKind {
        if item.entityType == .connection { return .connection(preview: bodyText) }
        if let source = thumbnailSource { return .media(source: source) }
        switch item.entityType {
        case .portal:
            return .objectMotif(icon: "rectangle.portrait.on.rectangle.portrait", tint: item.entityType.color)
        case .cosmoAI, .cosmo:
            return .objectMotif(icon: "circle.hexagongrid.circle", tint: DS.gilt)
        default:
            return .page(text: bodyText)
        }
    }

    /// Card media ratio (width / height) — videos full 16:9, reels tall, posts
    /// portrait; text documents are always a portrait page (the iOS file grammar).
    var previewAspect: CGFloat {
        switch previewKind {
        case .media: return mediaAspect
        case .page: return 90.0 / 116.0
        case .connection, .objectMotif: return 4.0 / 5.0
        }
    }

    private var mediaAspect: CGFloat {
        if item.entityType == .image { return 4.0 / 5.0 }
        let platform = (metadata["platform"] ?? "").lowercased()
        let url = (metadata["url"] ?? "").lowercased()
        if platform.contains("reel") || platform.contains("short") || platform.contains("tiktok") {
            return 9.0 / 16.0
        }
        if url.contains("/shorts/") { return 9.0 / 16.0 }
        if platform.contains("carousel") || platform == "instagram" || platform.contains("instagram_post") {
            return 4.0 / 5.0
        }
        return 16.0 / 9.0
    }

    /// Short kind label for the metadata row — platform when known, entity type otherwise.
    var kindLabel: String {
        let platform = (metadata["platform"] ?? "").lowercased()
        let url = (metadata["url"] ?? "").lowercased()
        if platform.contains("youtube") || url.contains("youtube") || url.contains("youtu.be") { return "YouTube" }
        if platform.contains("instagram") { return "Instagram" }
        if platform.contains("tiktok") { return "TikTok" }
        if platform.contains("twitter") || platform.contains("x_post") { return "X" }
        switch item.entityType {
        case .research: return metadata["isSwipeFile"] == "true" ? "Swipe" : "Research"
        case .stickyNote: return "Sticky Note"
        case .cosmoAI: return "Cosmo"
        default:
            return item.entityType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// True for video-bearing media — gets a small play badge on the card.
    var isVideoMedia: Bool {
        let platform = (metadata["platform"] ?? "").lowercased()
        let url = (metadata["url"] ?? "").lowercased()
        return platform.contains("youtube") || platform.contains("reel") || platform.contains("short")
            || platform.contains("tiktok") || url.contains("youtube") || url.contains("youtu.be")
    }

    static func youTubeVideoID(from urlString: String?) -> String? {
        guard let urlString, !urlString.isEmpty, let url = URL(string: urlString) else { return nil }
        let host = (url.host ?? "").lowercased()
        guard host.contains("youtube.com") || host.contains("youtu.be") else { return nil }
        if host.contains("youtu.be") {
            let id = url.pathComponents.dropFirst().first ?? ""
            return id.isEmpty ? nil : id
        }
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let v = items.first(where: { $0.name == "v" })?.value, !v.isEmpty {
            return v
        }
        let components = url.pathComponents
        if let index = components.firstIndex(where: { $0 == "shorts" || $0 == "embed" }),
           index + 1 < components.count {
            return components[index + 1]
        }
        return nil
    }
}

// MARK: - Actions

/// Everything the library can do to the canvas, bundled so the view stays declarative.
struct ThinkspaceLibraryActions {
    var openItem: (ThinkspaceLibraryItem) -> Void
    var revealOnCanvas: (ThinkspaceLibraryItem) -> Void
    var fileIntoFolder: (String, UUID) -> Void
    var removeFromFolder: (String, UUID) -> Void
    var renameFolder: (UUID, String) -> Void
    var recolorFolder: (UUID, Int) -> Void
    var deleteFolder: (UUID) -> Void
}

// MARK: - Sort

private enum ThinkspaceLibrarySort: String, CaseIterable, Identifiable {
    case name
    case kind

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "Name"
        case .kind: return "Kind"
        }
    }
}

// MARK: - Root View

struct ThinkspaceLibraryModeView: View {
    let thinkspaceName: String
    let thinkspaceId: String
    let snapshot: ThinkspaceLibrarySnapshot
    /// Hoisted to CanvasView so the universal navigation trail can walk in
    /// and out of folders (there is no in-page breadcrumb).
    @Binding var selectedFolderID: UUID?
    let actions: ThinkspaceLibraryActions

    @State private var selectedEntryID: String?
    @State private var searchText = ""
    @State private var sortOrder: ThinkspaceLibrarySort = .name
    @State private var previewStore = ThinkspaceLibraryPreviewStore()
    /// The staggered tile cascade is an arrival flourish — first mount only.
    /// Folder enter/exit swaps content with the section transition instead,
    /// so navigation never replays the entrance.
    @State private var hasCompletedEntranceCascade = false
    /// Drives the thin Cortex scrollbar (same chrome as Command-K and the
    /// content manuscript) in place of the chunky native overlay scroller.
    @State private var scrollMetrics = CortexScrollMetrics()
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {
            background
            content
        }
        .background(keyboardShortcuts)
        .onAppear {
            previewStore.ensureLoaded(snapshot)
            Task { @MainActor in hasCompletedEntranceCascade = true }
        }
        .onChange(of: snapshot) { _, newValue in previewStore.ensureLoaded(newValue) }
    }

    // MARK: Layout

    private var background: some View {
        DS.canvas
            .ignoresSafeArea()
            .filmGrain()
            .contentShape(Rectangle())
            .onTapGesture { clearSelection() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 22) {
            ThinkspaceLibraryHeader(
                folder: selectedFolder,
                thinkspaceName: thinkspaceName,
                searchText: $searchText,
                sortOrder: $sortOrder,
                searchFocused: $searchFocused
            )
            .padding(.horizontal, 48)
            browserScroll
        }
        .padding(.top, 36)
    }

    private var browserScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if !visibleFolders.isEmpty { folderSection }
                if !currentVisibleItems.isEmpty { itemSection }
            }
            .padding(.top, 6)
            .padding(.bottom, 110)
            // The page gutter lives INSIDE the scroll clip: edge cards get
            // 48pt of slack, so hover lift/scale never clips against the
            // viewport bounds.
            .padding(.horizontal, 48)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .animation(ProMotionSprings.gentle, value: snapshot)
            .animation(ProMotionSprings.snappy, value: sortOrder)
            // Folder enter/exit plays the same dialect as document opens:
            // one focusTransition drives the section swap.
            .animation(ProMotionSprings.focusTransition, value: selectedFolderID)
            .background(CortexScrollViewIntrospector { scrollMetrics = $0 })
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .all)
        // Child gestures (cards, folders) take precedence; this only catches
        // clicks on empty space between and below cards — Finder's deselect.
        .onTapGesture { clearSelection() }
        .cortexThinScrollbar(metrics: scrollMetrics)
        .overlay {
            if shouldShowEmptyState { emptyState }
        }
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ThinkspaceLibrarySectionHeader(title: "Folders", count: visibleFolders.count)
            LazyVGrid(columns: folderColumns, alignment: .leading, spacing: 14) {
                ForEach(Array(visibleFolders.enumerated()), id: \.element.id) { index, folder in
                    folderTile(folder, appearIndex: index)
                        .transition(libraryEntryTransition)
                }
            }
        }
        .transition(.opacity)
    }

    /// Finder-style settle: arriving content rises in a touch; departing
    /// content simply fades so the two never fight for attention.
    private var libraryEntryTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 10)),
            removal: .opacity
        )
    }

    private func folderTile(_ folder: ThinkspaceLibraryFolder, appearIndex: Int) -> some View {
        ThinkspaceLibraryFolderTile(
            folder: folder,
            appearIndex: appearIndex,
            cascadeOnAppear: !hasCompletedEntranceCascade,
            isSelected: selectedEntryID == folder.id.uuidString,
            onSelect: { select(folder.id.uuidString) },
            onOpen: { openFolder(folder) },
            onFileItem: { actions.fileIntoFolder($0, folder.id) },
            onRename: { actions.renameFolder(folder.id, $0) },
            onRecolor: { actions.recolorFolder(folder.id, $0) },
            onDelete: { deleteFolder(folder) }
        )
    }

    private var itemSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if selectedFolder == nil && !visibleFolders.isEmpty {
                ThinkspaceLibrarySectionHeader(title: "Documents", count: currentVisibleItems.count)
            }
            ThinkspaceLibraryMasonry(targetColumnWidth: 232, spacing: 20) {
                ForEach(Array(currentVisibleItems.enumerated()), id: \.element.id) { index, item in
                    itemCard(item, appearIndex: visibleFolders.count + index)
                        .transition(libraryEntryTransition)
                }
            }
        }
    }

    private func itemCard(_ item: ThinkspaceLibraryItem, appearIndex: Int) -> some View {
        ThinkspaceLibraryItemCard(
            model: cardModel(for: item),
            folders: snapshot.folders,
            currentFolder: selectedFolder,
            appearIndex: appearIndex,
            cascadeOnAppear: !hasCompletedEntranceCascade,
            isSelected: selectedEntryID == item.id,
            onSelect: { select(item.id) },
            onOpen: { actions.openItem(item) },
            actions: actions
        )
    }

    private func cardModel(for item: ThinkspaceLibraryItem) -> ThinkspaceLibraryCardModel {
        ThinkspaceLibraryCardModel(item: item, preview: previewStore.previews[item.entityUuid])
    }

    private var folderColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 148, maximum: 178), spacing: 14, alignment: .top)]
    }

    // MARK: Derived state

    private var selectedFolder: ThinkspaceLibraryFolder? {
        selectedFolderID.flatMap { id in snapshot.folders.first { $0.id == id } }
    }

    private var visibleFolders: [ThinkspaceLibraryFolder] {
        guard selectedFolder == nil else { return [] }
        guard !trimmedSearch.isEmpty else { return snapshot.folders }
        return snapshot.folders.filter { folder in
            matches(folder.title) || folder.items.contains(where: { matches($0.title) })
        }
    }

    private var currentVisibleItems: [ThinkspaceLibraryItem] {
        let base = selectedFolder == nil ? snapshot.looseItems : (selectedFolder?.items ?? [])
        return sorted(filteredItems(base))
    }

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shouldShowEmptyState: Bool {
        visibleFolders.isEmpty && currentVisibleItems.isEmpty
    }

    private func filteredItems(_ items: [ThinkspaceLibraryItem]) -> [ThinkspaceLibraryItem] {
        guard !trimmedSearch.isEmpty else { return items }
        return items.filter { item in
            matches(item.title)
                || matches(item.block?.subtitle ?? "")
                || matches(cardModel(for: item).bodyText ?? "")
        }
    }

    private func sorted(_ items: [ThinkspaceLibraryItem]) -> [ThinkspaceLibraryItem] {
        switch sortOrder {
        case .name:
            return items
        case .kind:
            return items.sorted { lhs, rhs in
                let lhsKind = cardModel(for: lhs).kindLabel
                let rhsKind = cardModel(for: rhs).kindLabel
                if lhsKind != rhsKind { return lhsKind < rhsKind }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }

    private func matches(_ value: String) -> Bool {
        value.localizedCaseInsensitiveContains(trimmedSearch)
    }

    // MARK: Selection & navigation

    private func select(_ entryID: String) {
        withAnimation(ProMotionSprings.snappy) { selectedEntryID = entryID }
    }

    private func clearSelection() {
        withAnimation(ProMotionSprings.snappy) { selectedEntryID = nil }
    }

    // Folders are places: opening one records a trail moment, so the app's
    // universal back/forward arrows walk in and out of folders — the library
    // has no breadcrumb of its own.
    private func openFolder(_ folder: ThinkspaceLibraryFolder) {
        withAnimation(ProMotionSprings.focusTransition) {
            selectedFolderID = folder.id
            selectedEntryID = nil
        }
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
            selectedEntryID = nil
        }
        NavigationTrail.shared.recordArrival(
            .sidebar(.thinkspace(id: thinkspaceId)),
            title: thinkspaceName,
            glyph: "rectangle.3.group"
        )
    }

    private func deleteFolder(_ folder: ThinkspaceLibraryFolder) {
        if selectedFolderID == folder.id { selectedFolderID = nil }
        if selectedEntryID == folder.id.uuidString { selectedEntryID = nil }
        NavigationTrail.shared.prune { moment in
            if case .libraryFolder(_, let folderID) = moment.destination {
                return folderID == folder.id
            }
            return false
        }
        actions.deleteFolder(folder.id)
    }

    // MARK: Keyboard

    private var keyboardShortcuts: some View {
        Group {
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
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func handleEscape() {
        if searchFocused || !searchText.isEmpty {
            searchText = ""
            searchFocused = false
        } else if selectedEntryID != nil {
            clearSelection()
        } else if selectedFolderID != nil {
            exitFolder()
        }
    }

    private func openSelection() {
        guard let selectedEntryID else { return }
        if let folder = snapshot.folders.first(where: { $0.id.uuidString == selectedEntryID }) {
            openFolder(folder)
        } else if let item = currentVisibleItems.first(where: { $0.id == selectedEntryID }) {
            actions.openItem(item)
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        ThinkspaceLibraryEmptyState(
            icon: trimmedSearch.isEmpty ? (selectedFolder == nil ? "square.grid.2x2" : "folder") : "magnifyingglass",
            title: emptyTitle,
            message: emptyMessage
        )
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    private var emptyTitle: String {
        if !trimmedSearch.isEmpty { return "No matches for “\(trimmedSearch)”" }
        if selectedFolder != nil { return "This folder is empty" }
        return "This Thinkspace is empty"
    }

    private var emptyMessage: String {
        if !trimmedSearch.isEmpty {
            return "Try a document title, folder, or phrase from this Thinkspace."
        }
        if selectedFolder != nil {
            return "Drag any document onto this folder to file it."
        }
        return "Add blocks on the canvas or press ⌘K to capture something — everything lands here."
    }
}

// MARK: - Header

private struct ThinkspaceLibraryHeader: View {
    let folder: ThinkspaceLibraryFolder?
    let thinkspaceName: String
    @Binding var searchText: String
    @Binding var sortOrder: ThinkspaceLibrarySort
    var searchFocused: FocusState<Bool>.Binding

    @State private var sortHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            titleBlock
            Spacer(minLength: 24)
            sortMenu
            searchField
        }
    }

    // No breadcrumb: the universal back/forward arrows own folder navigation.
    // Inside a folder the title carries the folder name; the thinkspace name
    // stays present as quiet marginalia above it.
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            if folder != nil {
                Text(thinkspaceName)
                    .font(DS.caption.weight(.medium))
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
            }
            Text(folder?.title ?? thinkspaceName)
                .font(DS.pageTitle)
                .foregroundStyle(DS.text)
                .lineLimit(1)
        }
        .animation(ProMotionSprings.gentle, value: folder?.id)
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $sortOrder) {
                ForEach(ThinkspaceLibrarySort.allCases) { order in
                    Text(order.title).tag(order)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(DS.caption.weight(.semibold))
                    .accessibilityHidden(true)
                Text(sortOrder.title)
                    .font(DS.footnote.weight(.medium))
            }
            .foregroundStyle(sortHovered ? DS.text : DS.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(sortHovered ? DS.glassInputFillFocused : DS.glassInputFill, in: Capsule())
            .overlay(Capsule().strokeBorder(DS.glassBorder, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .onHover { sortHovered = $0 }
        .animation(ProMotionSprings.hover, value: sortHovered)
        .help("Sort documents")
        .accessibilityLabel("Sort by \(sortOrder.title)")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(DS.callout.weight(.medium))
                .foregroundStyle(searchFocused.wrappedValue ? DS.accent : DS.textMuted)
                .accessibilityHidden(true)
            TextField("Find in library", text: $searchText)
                .textFieldStyle(.plain)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .focused(searchFocused)
                .frame(width: 220)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DS.caption)
                        .foregroundStyle(DS.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .dsGlassInput(isFocused: searchFocused.wrappedValue, cornerRadius: 18)
        .animation(ProMotionSprings.gentle, value: searchFocused.wrappedValue)
        .help("Find in library (⌘F)")
    }
}

// MARK: - Section Header

private struct ThinkspaceLibrarySectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        // The one ledger-header voice — same grammar as the Today task list
        // and the Inbox queue.
        CosmoSectionHeader(label: title, detail: "\(count)")
            .accessibilityLabel("\(title), \(count) items")
    }
}

// MARK: - Folder Tile

private struct ThinkspaceLibraryFolderTile: View {
    let folder: ThinkspaceLibraryFolder
    var appearIndex: Int = 0
    /// False after the library's first mount — folder navigation swaps
    /// content with the section transition, never a replayed cascade.
    var cascadeOnAppear: Bool = true
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onFileItem: (String) -> Void
    let onRename: (String) -> Void
    let onRecolor: (Int) -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var isDropTarget = false
    @State private var hasAppeared = false
    @State private var isRenaming = false
    @State private var draftName = ""
    @FocusState private var renameFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        tile
            .scaleEffect(isDropTarget ? 1.05 : 1)
            .animation(ProMotionSprings.hover, value: isHovered)
            .animation(ProMotionSprings.snappy, value: isSelected)
            .opacity(hasAppeared || reduceMotion ? 1 : 0)
            .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.96)
            .onHover { isHovered = $0 }
            .onAppear(perform: animateEntrance)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityLabel("\(folder.title) folder, \(folder.items.count) items. Drop a document here to file it.")
    }

    private var tile: some View {
        VStack(spacing: 10) {
            LibraryFolderIcon(color: folder.color, hasContents: !folder.items.isEmpty)
                .frame(width: 112, height: 82)
                .scaleEffect(isHovered && !isDropTarget ? 1.02 : 1)
            label
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(tileBackground)
        .overlay(tileRing)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .gesture(tapGestures)
        .dropDestination(for: String.self) { items, _ in
            guard let uuid = items.first,
                  !folder.items.contains(where: { $0.entityUuid == uuid }) else { return false }
            onFileItem(uuid)
            return true
        } isTargeted: { targeting in
            withAnimation(ProMotionSprings.bouncy) { isDropTarget = targeting }
        }
        // contextMenu must wrap the drop destination — the other way round, the
        // drop machinery swallows right-clicks and the menu never appears.
        .contextMenu { menuItems }
        .help("Open \(folder.title)")
    }

    private var tileBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(isSelected ? DS.accentSoft : DS.text.opacity(isHovered ? 0.045 : 0))
    }

    private var tileRing: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(
                isDropTarget ? folder.color.opacity(0.6) : DS.accent.opacity(isSelected ? 0.35 : 0),
                lineWidth: isDropTarget ? 2 : 1
            )
    }

    private var tapGestures: some Gesture {
        SimultaneousGesture(
            TapGesture(count: 2).onEnded { if !isRenaming { onOpen() } },
            TapGesture().onEnded { if !isRenaming { onSelect() } }
        )
    }

    @ViewBuilder
    private var label: some View {
        VStack(spacing: 3) {
            if isRenaming {
                renameField
            } else {
                Text(folder.title)
                    .font(DS.callout.weight(.medium))
                    .foregroundStyle(DS.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            Text("\(folder.items.count) item\(folder.items.count == 1 ? "" : "s")")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .monospacedDigit()
        }
        .frame(height: 44, alignment: .top)
    }

    private var renameField: some View {
        TextField("Folder name", text: $draftName)
            .textFieldStyle(.plain)
            .font(DS.callout.weight(.medium))
            .multilineTextAlignment(.center)
            .focused($renameFocused)
            .onSubmit(commitRename)
            .onExitCommand(perform: cancelRename)
            .onChange(of: renameFocused) { _, focused in
                if !focused && isRenaming { commitRename() }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(DS.focusRing, lineWidth: 1)
            )
            .frame(maxWidth: 136)
    }

    @ViewBuilder
    private var menuItems: some View {
        Button("Open", systemImage: "folder") { onOpen() }
        Button("Rename…", systemImage: "pencil") { beginRename() }
        colorMenu
        Divider()
        Button("Delete Folder", systemImage: "trash", role: .destructive) { onDelete() }
    }

    private var colorMenu: some View {
        Menu("Color") {
            ForEach(Array(CanvasCluster.palette.enumerated()), id: \.offset) { index, color in
                Button {
                    onRecolor(index)
                } label: {
                    Label {
                        Text(LibraryFolderSwatch.name(at: index))
                    } icon: {
                        Image(nsImage: LibraryFolderSwatch.image(for: color, selected: index == normalizedColorIndex))
                    }
                }
            }
        }
    }

    private var normalizedColorIndex: Int {
        let count = CanvasCluster.palette.count
        return ((folder.colorIndex % count) + count) % count
    }

    private func beginRename() {
        draftName = folder.title
        isRenaming = true
        DispatchQueue.main.async { renameFocused = true }
    }

    private func commitRename() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != folder.title {
            onRename(trimmed)
        }
        isRenaming = false
    }

    private func cancelRename() {
        isRenaming = false
    }

    private func animateEntrance() {
        guard cascadeOnAppear, !reduceMotion, !hasAppeared else { hasAppeared = true; return }
        withAnimation(ProMotionSprings.cascade(index: min(appearIndex, 8))) { hasAppeared = true }
    }
}

/// Color swatches for the folder context menu — pre-rendered NSImages so the
/// menu shows real color (SwiftUI menus render SF Symbols as template/mono).
private enum LibraryFolderSwatch {
    // Mirrors CanvasCluster.paletteHexes order.
    private static let paletteNames = ["Indigo", "Purple", "Pink", "Orange", "Green", "Cyan", "Blue", "Coral"]

    static func name(at index: Int) -> String {
        guard index >= 0, index < paletteNames.count else { return "Color \(index + 1)" }
        return paletteNames[index]
    }

    static func image(for color: Color, selected: Bool) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor(color).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5)).fill()
            if selected {
                NSColor.white.setStroke()
                let check = NSBezierPath()
                check.lineWidth = 1.6
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                check.move(to: NSPoint(x: rect.midX - 3.4, y: rect.midY + 0.2))
                check.line(to: NSPoint(x: rect.midX - 1.2, y: rect.midY - 2.4))
                check.line(to: NSPoint(x: rect.midX + 3.6, y: rect.midY + 2.8))
                check.stroke()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}

// MARK: - Folder Icon (macOS-style)

/// A faithful macOS folder silhouette: back panel with a top-left tab, paper
/// peeking out when the folder has contents, and a lighter front face.
private struct LibraryFolderIcon: View {
    let color: Color
    let hasContents: Bool

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let radius = h * 0.11
            ZStack(alignment: .bottom) {
                backPanel
                if hasContents { paper(size: geo.size, radius: radius) }
                frontFace(height: h * 0.78, radius: radius)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        // Premium, not gamey: a tight neutral contact shadow plus only a whisper
        // of color cast directly below — never an all-around bloom.
        .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
        .shadow(color: color.opacity(0.13), radius: 5, y: 4)
        .accessibilityHidden(true)
    }

    private var backPanel: some View {
        LibraryFolderBackShape()
            .fill(
                LinearGradient(
                    colors: [color.opacity(0.96), color.opacity(0.86)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .overlay(LibraryFolderBackShape().fill(Color.black.opacity(0.10)))
    }

    private func paper(size: CGSize, radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius * 0.45, style: .continuous)
            .fill(DS.surfaceCard)
            .overlay(
                RoundedRectangle(cornerRadius: radius * 0.45, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
            )
            .frame(width: size.width * 0.82, height: size.height * 0.76)
            .offset(y: -size.height * 0.07)
    }

    private func frontFace(height: CGFloat, radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [color, color.opacity(0.93)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.16), .white.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            )
            .overlay(alignment: .top) {
                Capsule()
                    .fill(Color.white.opacity(0.30))
                    .frame(height: 1)
                    .padding(.horizontal, radius)
                    .padding(.top, 1.5)
            }
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
            )
            .frame(height: height)
    }
}

/// Back panel of a macOS folder: full body with a rounded tab on the top-left
/// that slopes down into the body's top edge.
private struct LibraryFolderBackShape: Shape {
    func path(in rect: CGRect) -> Path {
        let tabWidth = rect.width * 0.40
        let tabHeight = rect.height * 0.14
        let slope = rect.width * 0.10
        let radius = rect.height * 0.11
        let tabRadius = radius * 0.6

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tabRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + tabRadius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + tabWidth - tabRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + tabWidth + slope, y: rect.minY + tabHeight),
            control: CGPoint(x: rect.minX + tabWidth + slope * 0.35, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY + tabHeight))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + tabHeight + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY + tabHeight)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Item Card

private struct ThinkspaceLibraryItemCard: View {
    let model: ThinkspaceLibraryCardModel
    let folders: [ThinkspaceLibraryFolder]
    let currentFolder: ThinkspaceLibraryFolder?
    var appearIndex: Int = 0
    /// False after the library's first mount — see ThinkspaceLibraryFolderTile.
    var cascadeOnAppear: Bool = true
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let actions: ThinkspaceLibraryActions

    @State private var isHovered = false
    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var item: ThinkspaceLibraryItem { model.item }

    var body: some View {
        draggableCard
            .scaleEffect(isHovered ? 1.012 : 1)
            .animation(ProMotionSprings.hover, value: isHovered)
            .animation(ProMotionSprings.snappy, value: isSelected)
            .opacity(hasAppeared || reduceMotion ? 1 : 0)
            .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.96)
            .onHover { isHovered = $0 }
            .onAppear(perform: animateEntrance)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityLabel("\(item.title), \(model.kindLabel), \(item.isOnCanvas ? "on canvas" : "stored")")
    }

    // On-canvas items can be dragged into folders; stored items aren't draggable.
    @ViewBuilder
    private var draggableCard: some View {
        if item.block != nil {
            card.draggable(item.entityUuid) { ThinkspaceLibraryDragPreview(model: model) }
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 9) {
            mediaWell
            textBlock
        }
        .contentShape(Rectangle())
        .gesture(tapGestures)
        .contextMenu { menuItems }
    }

    private var tapGestures: some Gesture {
        SimultaneousGesture(
            TapGesture(count: 2).onEnded { onOpen() },
            TapGesture().onEnded { onSelect() }
        )
    }

    /// The document IS the object (the Files grammar): a page or thumbnail of
    /// its actual content, never framed in a card. Text pages wear their kind
    /// tint on the edge — the border carries identity; media stays neutral.
    private var mediaWell: some View {
        LibraryCardObject(model: model)
            .overlay(selectionRing)
            .overlay(alignment: .topTrailing) { quickOpenButton }
            .cardShadow(isHovered: isHovered)
    }

    private var selectionRing: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(DS.accent.opacity(isSelected ? 0.55 : 0), lineWidth: 2)
    }

    private var quickOpenButton: some View {
        Button(action: onOpen) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.text)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .opacity(isHovered ? 1 : 0)
        .allowsHitTesting(isHovered)
        .padding(8)
        .help("Open in Focus Mode (⌘O)")
        .accessibilityLabel("Open \(item.title) in Focus Mode")
    }

    // Name and kind sit centered beneath the object — Finder's icon-view
    // grammar, matching the iOS file tile.
    private var textBlock: some View {
        VStack(spacing: 3) {
            Text(item.title)
                .font(DS.callout.weight(.medium))
                .foregroundStyle(DS.text)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    isSelected ? DS.accentSoft : .clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
            metaRow
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 2)
    }

    private var metaRow: some View {
        Text("\(model.kindLabel) · \(item.isOnCanvas ? "On canvas" : "Stored")")
            .font(DS.caption)
            .foregroundStyle(DS.textMuted)
            .lineLimit(1)
    }

    @ViewBuilder
    private var menuItems: some View {
        Button("Open", systemImage: "arrow.up.left.and.arrow.down.right") { onOpen() }
        if item.isOnCanvas {
            Button("Reveal on Canvas", systemImage: "scope") { actions.revealOnCanvas(item) }
        }
        moveMenuItems
        copyLinkItem
    }

    @ViewBuilder
    private var moveMenuItems: some View {
        if item.isOnCanvas {
            let targets = folders.filter { $0.id != currentFolder?.id }
            if !targets.isEmpty || currentFolder != nil { Divider() }
            if !targets.isEmpty {
                Menu("Move to Folder") {
                    ForEach(targets) { folder in
                        Button(folder.title) { actions.fileIntoFolder(item.entityUuid, folder.id) }
                    }
                }
            }
            if let current = currentFolder {
                Button("Remove from “\(current.title)”", systemImage: "folder.badge.minus") {
                    actions.removeFromFolder(item.entityUuid, current.id)
                }
            }
        }
    }

    @ViewBuilder
    private var copyLinkItem: some View {
        if let url = model.metadata["url"], !url.isEmpty {
            Divider()
            Button("Copy Link", systemImage: "link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)
            }
        }
    }

    private func animateEntrance() {
        guard cascadeOnAppear, !reduceMotion, !hasAppeared else { hasAppeared = true; return }
        withAnimation(ProMotionSprings.cascade(index: min(appearIndex, 8))) { hasAppeared = true }
    }
}

// MARK: - Card Object

/// The document rendered as an object — its page or thumbnail with the kind
/// edge and play badge. Shared by the grid card and the drag preview, so
/// dragging feels like carrying the real thing (Finder's grammar), never a
/// stand-in chip.
private struct LibraryCardObject: View {
    let model: ThinkspaceLibraryCardModel

    private var item: ThinkspaceLibraryItem { model.item }

    var body: some View {
        Color.clear
            .aspectRatio(model.previewAspect, contentMode: .fit)
            .overlay { previewContent }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(objectEdge)
            .overlay(alignment: .bottomLeading) { playBadge }
    }

    private var objectEdge: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(edgeColor, lineWidth: isPage ? 1 : 0.5)
    }

    private var isPage: Bool {
        if case .page = model.previewKind { return true }
        return false
    }

    private var edgeColor: Color {
        isPage ? item.entityType.color.opacity(0.45) : DS.glassBorder
    }

    @ViewBuilder
    private var playBadge: some View {
        if model.isVideoMedia, case .media = model.previewKind {
            Image(systemName: "play.fill")
                .font(DS.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.black.opacity(0.55), in: Circle())
                .padding(8)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch model.previewKind {
        case .media(let source):
            LibraryMediaThumbnail(source: source, accent: item.entityType.color)
        case .page(let text):
            LibraryPagePreview(
                title: item.title,
                text: text,
                // Notes carry their page personality onto the card — paper
                // tone, cover, icon — via the read-through style cache.
                pageStyle: item.entityType == .note
                    ? NotePageStyleCache.shared.style(for: item.entityUuid)
                    : nil
            )
        case .connection(let preview):
            LibraryConnectionPreview(preview: preview)
        case .objectMotif(let icon, let tint):
            LibraryObjectMotifWell(icon: icon, tint: tint)
        }
    }
}

// MARK: - Drag Preview

/// The card itself at grid scale — you drag the actual thumbnail with its
/// name beneath, exactly what Finder does when you pick up a file.
private struct ThinkspaceLibraryDragPreview: View {
    let model: ThinkspaceLibraryCardModel

    var body: some View {
        VStack(spacing: 8) {
            LibraryCardObject(model: model)
                .cardShadow(isHovered: true)
            Text(model.item.title)
                .font(DS.callout.weight(.medium))
                .foregroundStyle(DS.text)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(DS.canvas.opacity(0.88), in: Capsule())
        }
        .frame(width: 212)
        // Slack so the object's shadow survives the drag snapshot's bounds.
        .padding(14)
    }
}

// MARK: - Preview Content

private struct LibraryMediaThumbnail: View {
    let source: String
    let accent: Color

    var body: some View {
        Group {
            if source.hasPrefix("http") {
                remote
            } else {
                local
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .accessibilityHidden(true)
    }

    private var remote: some View {
        CachedAsyncImage(url: URL(string: source)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            case .empty:
                Rectangle().fill(DS.glassSectionFill)
            case .failure:
                LibraryMediaFallback(accent: accent)
            }
        }
    }

    private var local: some View {
        // Async + downsampled: the old sync NSImage(contentsOfFile:) decoded
        // full-resolution files on the main thread during grid scrolling.
        LocalFileThumbnail(path: source) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            LibraryMediaFallback(accent: accent)
        }
    }
}

/// The object motif well: a tinted mark centered on a quiet wash — the honest
/// face of a non-document object (portal, live Cosmo block). Title and kind
/// live in the caption below, so the well carries only the identity.
private struct LibraryObjectMotifWell: View {
    let icon: String
    let tint: Color

    var body: some View {
        ZStack {
            Rectangle().fill(tint.opacity(0.07))
            Image(systemName: icon)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(tint.opacity(0.75))
        }
        .accessibilityHidden(true)
    }
}

/// Quiet stand-in when a thumbnail can't load — a skeleton-toned well, not chrome.
private struct LibraryMediaFallback: View {
    let accent: Color

    var body: some View {
        ZStack {
            Rectangle().fill(DS.glassSectionFill)
            Image(systemName: "photo")
                .font(DS.title2)
                .foregroundStyle(accent.opacity(0.35))
        }
        .accessibilityHidden(true)
    }
}

/// The document's actual first page at file-object scale — real title and
/// prose, the way Files (and the iOS library) render a page. Never an icon.
private struct LibraryPagePreview: View {
    let title: String
    let text: String?
    /// A personalized note's page style — paper tone, icon, cover — so the
    /// card is a faithful miniature. nil for every other page kind.
    var pageStyle: NoteDocumentStyle? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let icon = pageStyle?.pageIcon {
                NotePageIconView(
                    icon: icon,
                    style: pageStyle ?? .default,
                    darkMode: DS.palette.isDark,
                    size: 16
                )
            }
            Text(title)
                .font(DS.compactTitleSerif)
                .foregroundStyle(CommandKPreviewPaper.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(text?.isEmpty == false ? text ?? "" : " ")
                .font(DS.caption)
                .foregroundStyle(CommandKPreviewPaper.textSecondary)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        }
        .padding(16)
        .padding(.top, coverHeight > 0 ? coverHeight - 8 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(paperFill)
        .background(alignment: .top) { coverBand }
        .accessibilityHidden(true)
    }

    private var paperFill: Color {
        pageStyle?.paperTone.pageColor(darkMode: DS.palette.isDark) ?? CommandKPreviewPaper.fill
    }

    private var coverHeight: CGFloat {
        (pageStyle?.cover ?? NoteDocumentStyle.Cover.none) == NoteDocumentStyle.Cover.none ? 0 : 22
    }

    @ViewBuilder
    private var coverBand: some View {
        if let pageStyle, pageStyle.cover != .none {
            NotePageCoverBand(
                style: pageStyle,
                darkMode: DS.palette.isDark,
                height: coverHeight
            )
        }
    }
}

/// Miniature of the connection workspace — its section stack at readable scale.
/// Section colors mirror the connection focus mode's editorial palette.
private struct LibraryConnectionPreview: View {
    let preview: String?

    private static let sectionDefs: [(key: String, label: String, hex: String)] = [
        ("IDEA", "Idea", "#6B6EA8"),
        ("BELIEF", "Belief", "#5B84B0"),
        ("GOAL", "Goal", "#38B764"),
        ("PROBLEMS", "Problems", "#D97706"),
        ("BENEFIT", "Benefits", "#34A36A"),
        ("OBJECTIONS", "Objections", "#8B6BAB"),
        ("EXAMPLE", "Examples", "#D17B4F"),
        ("PROCESS", "Process", "#5E8BB5"),
        ("NOTES", "Notes", "#9B8A6E"),
    ]

    private var sections: [(label: String, color: Color, hasContent: Bool)] {
        let filledKeys: Set<String>
        if let preview, !preview.isEmpty {
            filledKeys = Set(preview.components(separatedBy: "\n\n").compactMap {
                $0.components(separatedBy: "\n").first
            })
        } else {
            filledKeys = []
        }
        return Self.sectionDefs.map { def in
            (def.label, Color(hex: def.hex), filledKeys.contains(def.key))
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                sectionRow(section)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color(white: 0.13))
        .accessibilityHidden(true)
    }

    private func sectionRow(_ section: (label: String, color: Color, hasContent: Bool)) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(section.color)
                .frame(width: 5, height: 5)
            Text(section.label)
                .font(DS.caption)
                .foregroundStyle(Color.white.opacity(0.72))
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(section.color.opacity(section.hasContent ? 0.45 : 0))
                .frame(width: 18, height: 5)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(section.hasContent ? 0.09 : 0.04))
        )
    }
}

// MARK: - Masonry Layout (Pinterest-style waterfall)

/// Computes its own column count from the proposed width, so callers never
/// need a GeometryReader. Each item flows into the currently shortest column.
struct ThinkspaceLibraryMasonry: Layout {
    var targetColumnWidth: CGFloat = 264
    var spacing: CGFloat = 20

    private func columnCount(for width: CGFloat) -> Int {
        max(2, Int((width + spacing) / (targetColumnWidth + spacing)))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 800
        let count = columnCount(for: width)
        let columnWidth = (width - CGFloat(count - 1) * spacing) / CGFloat(count)
        var heights = Array(repeating: CGFloat(0), count: count)

        for subview in subviews {
            let shortest = heights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            heights[shortest] += size.height + spacing
        }

        return CGSize(width: width, height: max(0, (heights.max() ?? 0) - spacing))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let count = columnCount(for: bounds.width)
        let columnWidth = (bounds.width - CGFloat(count - 1) * spacing) / CGFloat(count)
        var heights = Array(repeating: CGFloat(0), count: count)

        for subview in subviews {
            let shortest = heights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            let x = bounds.minX + CGFloat(shortest) * (columnWidth + spacing)
            let y = bounds.minY + heights[shortest]

            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: columnWidth, height: nil)
            )

            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            heights[shortest] += size.height + spacing
        }
    }
}

// MARK: - Empty State

private struct ThinkspaceLibraryEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
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
