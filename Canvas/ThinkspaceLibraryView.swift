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

// MARK: - Item presentation helpers

enum ThinkspaceLibraryPreviewKind: Equatable {
    case media(source: String)
    case page(text: String)
    case connection(preview: String?)
    case blank
}

extension ThinkspaceLibraryItem {
    var metadata: [String: String] { block?.metadata ?? [:] }

    var bodyText: String? {
        let text = metadata["content"] ?? block?.subtitle ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
        if entityType == .connection { return .connection(preview: bodyText) }
        if let source = thumbnailSource { return .media(source: source) }
        if let text = bodyText { return .page(text: text) }
        return .blank
    }

    /// Card media ratio (width / height) — videos full 16:9, reels tall, posts portrait.
    var previewAspect: CGFloat {
        switch previewKind {
        case .media: return mediaAspect
        case .page: return 1.0
        case .connection: return 4.0 / 5.0
        case .blank: return 16.0 / 10.0
        }
    }

    private var mediaAspect: CGFloat {
        if entityType == .image { return 4.0 / 5.0 }
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
        switch entityType {
        case .research: return metadata["isSwipeFile"] == "true" ? "Swipe" : "Research"
        case .stickyNote: return "Sticky Note"
        case .cosmoAI: return "Cosmo"
        default:
            return entityType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
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
    let snapshot: ThinkspaceLibrarySnapshot
    let actions: ThinkspaceLibraryActions

    @State private var selectedFolderID: UUID?
    @State private var selectedEntryID: String?
    @State private var searchText = ""
    @State private var sortOrder: ThinkspaceLibrarySort = .name
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {
            background
            content
        }
        .background(keyboardShortcuts)
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
                thinkspaceName: thinkspaceName,
                folder: selectedFolder,
                subtitle: subtitleText,
                searchText: $searchText,
                sortOrder: $sortOrder,
                searchFocused: $searchFocused,
                onBack: exitFolder,
                onDropOutOfFolder: handleDropOutOfFolder
            )
            browserScroll
        }
        .padding(.horizontal, 48)
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
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .animation(ProMotionSprings.gentle, value: snapshot)
            .animation(ProMotionSprings.snappy, value: sortOrder)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        // Child gestures (cards, folders) take precedence; this only catches
        // clicks on empty space between and below cards — Finder's deselect.
        .onTapGesture { clearSelection() }
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
                }
            }
        }
    }

    private func folderTile(_ folder: ThinkspaceLibraryFolder, appearIndex: Int) -> some View {
        ThinkspaceLibraryFolderTile(
            folder: folder,
            appearIndex: appearIndex,
            isSelected: selectedEntryID == folder.id.uuidString,
            onSelect: { select(folder.id.uuidString) },
            onOpen: { openFolder(folder) },
            onFileItem: { actions.fileIntoFolder($0, folder.id) },
            onRename: { actions.renameFolder(folder.id, $0) },
            onDelete: { deleteFolder(folder) }
        )
    }

    private var itemSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if selectedFolder == nil && !visibleFolders.isEmpty {
                ThinkspaceLibrarySectionHeader(title: "Documents", count: currentVisibleItems.count)
            }
            ThinkspaceLibraryMasonry(targetColumnWidth: 264, spacing: 20) {
                ForEach(Array(currentVisibleItems.enumerated()), id: \.element.id) { index, item in
                    itemCard(item, appearIndex: visibleFolders.count + index)
                }
            }
        }
    }

    private func itemCard(_ item: ThinkspaceLibraryItem, appearIndex: Int) -> some View {
        ThinkspaceLibraryItemCard(
            item: item,
            folders: snapshot.folders,
            currentFolder: selectedFolder,
            appearIndex: appearIndex,
            isSelected: selectedEntryID == item.id,
            onSelect: { select(item.id) },
            onOpen: { actions.openItem(item) },
            actions: actions
        )
    }

    private var folderColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 148, maximum: 178), spacing: 14, alignment: .top)]
    }

    // MARK: Derived state

    private var itemCount: Int {
        snapshot.looseItems.count + snapshot.folders.reduce(0) { $0 + $1.items.count }
    }

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

    private var subtitleText: String {
        if let folder = selectedFolder {
            return "\(folder.items.count) item\(folder.items.count == 1 ? "" : "s")"
        }
        let folderCount = snapshot.folders.count
        if folderCount > 0 {
            return "\(folderCount) folder\(folderCount == 1 ? "" : "s") · \(itemCount) item\(itemCount == 1 ? "" : "s")"
        }
        return "\(itemCount) item\(itemCount == 1 ? "" : "s")"
    }

    private var shouldShowEmptyState: Bool {
        visibleFolders.isEmpty && currentVisibleItems.isEmpty
    }

    private func filteredItems(_ items: [ThinkspaceLibraryItem]) -> [ThinkspaceLibraryItem] {
        guard !trimmedSearch.isEmpty else { return items }
        return items.filter { item in
            matches(item.title) || matches(item.block?.subtitle ?? "") || matches(item.block?.metadata["content"] ?? "")
        }
    }

    private func sorted(_ items: [ThinkspaceLibraryItem]) -> [ThinkspaceLibraryItem] {
        switch sortOrder {
        case .name:
            return items
        case .kind:
            return items.sorted { lhs, rhs in
                if lhs.kindLabel != rhs.kindLabel { return lhs.kindLabel < rhs.kindLabel }
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

    private func openFolder(_ folder: ThinkspaceLibraryFolder) {
        withAnimation(ProMotionSprings.focusTransition) {
            selectedFolderID = folder.id
            selectedEntryID = nil
        }
    }

    private func exitFolder() {
        withAnimation(ProMotionSprings.focusTransition) {
            selectedFolderID = nil
            selectedEntryID = nil
        }
    }

    private func deleteFolder(_ folder: ThinkspaceLibraryFolder) {
        if selectedFolderID == folder.id { selectedFolderID = nil }
        if selectedEntryID == folder.id.uuidString { selectedEntryID = nil }
        actions.deleteFolder(folder.id)
    }

    private func handleDropOutOfFolder(_ itemUUID: String) -> Bool {
        guard let folder = selectedFolder else { return false }
        actions.removeFromFolder(itemUUID, folder.id)
        return true
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
    let thinkspaceName: String
    let folder: ThinkspaceLibraryFolder?
    let subtitle: String
    @Binding var searchText: String
    @Binding var sortOrder: ThinkspaceLibrarySort
    var searchFocused: FocusState<Bool>.Binding
    let onBack: () -> Void
    let onDropOutOfFolder: (String) -> Bool

    @State private var rootCrumbTargeted = false
    @State private var sortHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if folder != nil { breadcrumb }
            HStack(alignment: .center, spacing: 10) {
                titleBlock
                Spacer(minLength: 24)
                sortMenu
                searchField
            }
        }
    }

    // Root crumb doubles as a drop target: dragging a document onto it un-files it.
    private var breadcrumb: some View {
        HStack(spacing: 6) {
            Button(action: onBack) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(DS.caption.weight(.semibold))
                        .accessibilityHidden(true)
                    Text(thinkspaceName)
                }
                .font(DS.subheadline.weight(.medium))
                .foregroundStyle(DS.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(rootCrumbTargeted ? DS.accentSoft : .clear, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Back to \(thinkspaceName) (⌘↑)")
            .accessibilityLabel("Back to \(thinkspaceName)")
            .dropDestination(for: String.self) { items, _ in
                guard let uuid = items.first else { return false }
                return onDropOutOfFolder(uuid)
            } isTargeted: { targeting in
                withAnimation(ProMotionSprings.snappy) { rootCrumbTargeted = targeting }
            }

            Text("/")
                .font(DS.subheadline)
                .foregroundStyle(DS.textMuted)
            Text(folder?.title ?? "")
                .font(DS.subheadline.weight(.medium))
                .foregroundStyle(DS.text)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(folder?.title ?? thinkspaceName)
                .font(DS.pageTitle)
                .foregroundStyle(DS.text)
                .lineLimit(1)
            Text(subtitle)
                .font(DS.subheadline)
                .foregroundStyle(DS.textMuted)
                .monospacedDigit()
        }
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
        HStack(spacing: 10) {
            Text(title)
                .font(DS.subheadline.weight(.semibold))
                .foregroundStyle(DS.textSecondary)
            Text("\(count)")
                .font(DS.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(DS.textMuted)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(DS.glassInputFill, in: Capsule())
                .overlay(Capsule().strokeBorder(DS.glassBorder, lineWidth: 0.5))
            Rectangle()
                .fill(DS.glassBorder)
                .frame(height: 0.5)
                .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(count) items")
    }
}

// MARK: - Folder Tile

private struct ThinkspaceLibraryFolderTile: View {
    let folder: ThinkspaceLibraryFolder
    var appearIndex: Int = 0
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onFileItem: (String) -> Void
    let onRename: (String) -> Void
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
        .contextMenu { menuItems }
        .dropDestination(for: String.self) { items, _ in
            guard let uuid = items.first else { return false }
            onFileItem(uuid)
            return true
        } isTargeted: { targeting in
            withAnimation(ProMotionSprings.bouncy) { isDropTarget = targeting }
        }
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
        Divider()
        Button("Delete Folder", systemImage: "trash", role: .destructive) { onDelete() }
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
        guard !reduceMotion, !hasAppeared else { hasAppeared = true; return }
        withAnimation(ProMotionSprings.cascade(index: min(appearIndex, 8))) { hasAppeared = true }
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
        .shadow(color: color.opacity(0.28), radius: 9, y: 5)
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
                            colors: [.white.opacity(0.28), .white.opacity(0.03)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            )
            .overlay(alignment: .top) {
                Capsule()
                    .fill(Color.white.opacity(0.45))
                    .frame(height: 1)
                    .padding(.horizontal, radius)
                    .padding(.top, 1.5)
            }
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.75)
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
    let item: ThinkspaceLibraryItem
    let folders: [ThinkspaceLibraryFolder]
    let currentFolder: ThinkspaceLibraryFolder?
    var appearIndex: Int = 0
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let actions: ThinkspaceLibraryActions

    @State private var isHovered = false
    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .accessibilityLabel("\(item.title), \(item.kindLabel), \(item.isOnCanvas ? "on canvas" : "stored")")
    }

    // On-canvas items can be dragged into folders; stored items aren't draggable.
    @ViewBuilder
    private var draggableCard: some View {
        if item.block != nil {
            card.draggable(item.entityUuid) { ThinkspaceLibraryDragPreview(item: item) }
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

    private var mediaWell: some View {
        Color.clear
            .aspectRatio(item.previewAspect, contentMode: .fit)
            .overlay { previewContent }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .glassCard(isHovered: isHovered, tint: item.entityType.color, cornerRadius: 14)
            .overlay(selectionRing)
            .overlay(alignment: .topTrailing) { quickOpenButton }
            .overlay(alignment: .bottomLeading) { playBadge }
            .cardShadow(isHovered: isHovered)
    }

    @ViewBuilder
    private var playBadge: some View {
        if item.isVideoMedia, case .media = item.previewKind {
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
        switch item.previewKind {
        case .media(let source):
            LibraryMediaThumbnail(source: source, accent: item.entityType.color)
        case .page(let text):
            LibraryPagePreview(text: text, accent: item.entityType.color)
        case .connection(let preview):
            LibraryConnectionPreview(preview: preview)
        case .blank:
            LibraryBlankPreview(icon: item.entityType.icon, accent: item.entityType.color)
        }
    }

    private var selectionRing: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
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

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title)
                .font(DS.headline)
                .foregroundStyle(DS.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    isSelected ? DS.accentSoft : .clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
            metaRow
                .padding(.horizontal, 6)
        }
        .padding(.horizontal, 2)
    }

    private var metaRow: some View {
        HStack(spacing: 5) {
            Image(systemName: item.entityType.icon)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(item.entityType.color)
                .accessibilityHidden(true)
            Text(item.kindLabel)
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
            Text("·")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
            Text(item.isOnCanvas ? "On canvas" : "Stored")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        }
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
        if let url = item.metadata["url"], !url.isEmpty {
            Divider()
            Button("Copy Link", systemImage: "link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)
            }
        }
    }

    private func animateEntrance() {
        guard !reduceMotion, !hasAppeared else { hasAppeared = true; return }
        withAnimation(ProMotionSprings.cascade(index: min(appearIndex, 8))) { hasAppeared = true }
    }
}

// MARK: - Drag Preview

private struct ThinkspaceLibraryDragPreview: View {
    let item: ThinkspaceLibraryItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.entityType.icon)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(item.entityType.color)
                .accessibilityHidden(true)
            Text(item.title)
                .font(DS.caption)
                .foregroundStyle(DS.text)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: 220)
        .glassCard(isHovered: true, tint: item.entityType.color, cornerRadius: 12)
        .cardShadow(isHovered: true)
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
                LibraryBlankPreview(icon: "photo", accent: accent)
            }
        }
    }

    @ViewBuilder
    private var local: some View {
        if let nsImage = LibraryLocalImageCache.image(at: source) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            LibraryBlankPreview(icon: "photo", accent: accent)
        }
    }
}

private enum LibraryLocalImageCache {
    static let cache = NSCache<NSString, NSImage>()

    static func image(at path: String) -> NSImage? {
        if let hit = cache.object(forKey: path as NSString) { return hit }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}

/// A readable paper preview — actual document text at caption size, like Notes' gallery.
private struct LibraryPagePreview: View {
    let text: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(accent.opacity(0.45))
                .frame(width: 28, height: 3)
                .padding(.bottom, 9)
            Text(text)
                .font(DS.caption)
                .foregroundStyle(CommandKPreviewPaper.textSecondary)
                .lineSpacing(2.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        }
        .padding(14)
        .background(CommandKPreviewPaper.fill)
        .accessibilityHidden(true)
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

private struct LibraryBlankPreview: View {
    let icon: String
    let accent: Color

    var body: some View {
        ZStack {
            Rectangle().fill(accent.opacity(0.06))
            Image(systemName: icon)
                .font(DS.title2)
                .foregroundStyle(accent.opacity(0.55))
                .frame(width: 48, height: 48)
                .background(DS.surfaceCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(DS.glassBorder, lineWidth: 0.5)
                )
        }
        .accessibilityHidden(true)
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
