// CosmoOS/UI/Library/LibraryView.swift
// Eden-style spatial library — the HOME of CosmoOS
// Replaces constellation graph with visual card grid, folders, and smart collections

import SwiftUI
import GRDB

// MARK: - Library View Mode

enum LibraryViewMode: String, CaseIterable {
    case grid
    case list

    var icon: String {
        switch self {
        case .grid: return "square.grid.2x2.fill"
        case .list: return "list.bullet"
        }
    }
}

// MARK: - Library Sort

enum LibrarySortMode: String, CaseIterable {
    case dateAdded
    case lastModified
    case name
    case type

    var displayName: String {
        switch self {
        case .dateAdded: return "Date Added"
        case .lastModified: return "Last Modified"
        case .name: return "Name"
        case .type: return "Type"
        }
    }
}

// MARK: - Breadcrumb

struct LibraryBreadcrumb: Identifiable, Equatable {
    let id: String
    let title: String
    let uuid: String? // nil for Home
}

// MARK: - LibraryView

struct LibraryView: View {
    @StateObject private var viewModel = LibraryViewModel()
    @State private var viewMode: LibraryViewMode = .grid
    @State private var sortMode: LibrarySortMode = .dateAdded
    @State private var searchText: String = ""
    @State private var showCreateMenu: Bool = false
    @State private var showConnectionDashboard: Bool = false

    var body: some View {
        ZStack {
            if showConnectionDashboard {
                VStack(spacing: 0) {
                    // Back button
                    HStack {
                        Button {
                            withAnimation(ProMotionSprings.snappy) {
                                showConnectionDashboard = false
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Library")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(DS.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    ConnectionLibraryDashboard()
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                mainLibraryContent
            }
        }
        .background(DS.bg)
        .task {
            await viewModel.loadLibrary()
        }
        .onChange(of: sortMode) { newSort in
            viewModel.applySortMode(newSort)
        }
        .onChange(of: searchText) { newText in
            viewModel.filterBySearch(newText)
        }
    }

    private var mainLibraryContent: some View {
        VStack(spacing: 0) {
            // Top bar
            topBar

            Divider().background(DS.borderActive)

            // Breadcrumbs (when inside a folder)
            if viewModel.breadcrumbs.count > 1 {
                breadcrumbBar
            }

            // Smart Collections (at top of home level)
            if viewModel.isAtHome && !viewModel.smartCollections.isEmpty {
                smartCollectionsRow
            }

            // Main content
            if viewModel.isLoading {
                loadingView
            } else if viewModel.displayItems.isEmpty {
                emptyState
            } else {
                switch viewMode {
                case .grid:
                    LibraryGridView(
                        items: viewModel.displayItems,
                        onItemTap: { viewModel.handleItemTap($0) },
                        onItemDoubleTap: { viewModel.openInFocusMode($0) }
                    )
                case .list:
                    libraryListView
                }
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 16) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(DS.textMuted)

                TextField("Search library...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundColor(DS.text)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(DS.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(DS.border)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(DS.borderActive, lineWidth: 1)
                    )
            )
            .frame(maxWidth: 400)

            Spacer()

            // View toggle
            HStack(spacing: 4) {
                ForEach(LibraryViewMode.allCases, id: \.rawValue) { mode in
                    Button {
                        withAnimation(ProMotionSprings.snappy) {
                            viewMode = mode
                        }
                    } label: {
                        Image(systemName: mode.icon)
                            .font(.system(size: 13))
                            .foregroundColor(viewMode == mode ? DS.text : DS.textMuted)
                            .frame(width: 30, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(viewMode == mode ? DS.borderActive : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(DS.border)
            )

            // Sort dropdown
            Menu {
                ForEach(LibrarySortMode.allCases, id: \.rawValue) { mode in
                    Button {
                        sortMode = mode
                    } label: {
                        HStack {
                            Text(mode.displayName)
                            if sortMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(sortMode.displayName)
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                }
                .foregroundColor(DS.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(DS.border)
                )
            }

            // Create button
            Menu {
                Button { viewModel.createAtom(type: .connection) } label: {
                    Label("Connection", systemImage: "link.circle")
                }
                Button { viewModel.createAtom(type: .project) } label: {
                    Label("Project", systemImage: "folder")
                }
                Button { viewModel.createAtom(type: .idea) } label: {
                    Label("Idea", systemImage: "lightbulb")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white) // White on accent bg — exception
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(DS.accent)
                    )
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    // MARK: - Breadcrumbs

    private var breadcrumbBar: some View {
        HStack(spacing: 4) {
            ForEach(Array(viewModel.breadcrumbs.enumerated()), id: \.element.id) { index, crumb in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .foregroundColor(DS.textMuted)
                }

                Button {
                    viewModel.navigateToBreadcrumb(crumb)
                } label: {
                    Text(crumb.title)
                        .font(.system(size: 13, weight: index == viewModel.breadcrumbs.count - 1 ? .semibold : .regular))
                        .foregroundColor(index == viewModel.breadcrumbs.count - 1 ? DS.text : DS.textSecondary)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(DS.borderSubtle)
    }

    // MARK: - Smart Collections

    private var smartCollectionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(viewModel.smartCollections) { collection in
                    smartCollectionCard(collection)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func smartCollectionCard(_ collection: SmartCollection) -> some View {
        Button {
            if case .connectionDashboard = collection.filterType {
                withAnimation(ProMotionSprings.snappy) {
                    showConnectionDashboard = true
                }
            } else {
                viewModel.openSmartCollection(collection)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: collection.icon)
                    .font(.system(size: 14))
                    .foregroundColor(collection.color)
                    .frame(width: 32, height: 32)
                    .background(collection.color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(collection.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DS.text)
                    Text("\(collection.count) items")
                        .font(.system(size: 11))
                        .foregroundColor(DS.textMuted)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(DS.borderSubtle)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(DS.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - List View

    private var libraryListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.displayItems) { item in
                    libraryListRow(item)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private func libraryListRow(_ item: LibraryItem) -> some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: item.icon)
                .font(.system(size: 14))
                .foregroundColor(item.color)
                .frame(width: 28)

            // Title
            Text(item.title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(DS.text)
                .lineLimit(1)

            Spacer()

            // Type badge
            Text(item.typeName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(item.color.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(item.color.opacity(0.1))
                .clipShape(Capsule())

            // Date
            Text(item.relativeDate)
                .font(.system(size: 12))
                .foregroundColor(DS.textMuted)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.handleItemTap(item)
        }
        .onTapGesture(count: 2) {
            viewModel.openInFocusMode(item)
        }

        Divider().background(DS.border)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(DS.textMuted)

            Text("Your library is empty")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(DS.textSecondary)

            Text("Create your first note, idea, or project to get started")
                .font(.system(size: 13))
                .foregroundColor(DS.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack {
            ProgressView()
                .scaleEffect(1.2)
                .tint(DS.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Smart Collection

struct SmartCollection: Identifiable {
    let id: String
    let title: String
    let icon: String
    let color: Color
    let count: Int
    let filterType: SmartCollectionType

    enum SmartCollectionType {
        case byClient(String)
        case byStatus
        case byTopic(String)
        case recentlyActive
        case connectionDashboard
    }
}

// MARK: - Library Item

struct LibraryItem: Identifiable {
    let id: String
    let uuid: String
    let entityId: Int64
    let title: String
    let atomType: AtomType
    let icon: String
    let color: Color
    let typeName: String
    let relativeDate: String
    let isFolder: Bool
    let childCount: Int
    let updatedAt: Date
    let preview: String?
    let thumbnailURL: String?
    let statusBadge: String?

    init(atom: Atom, childCount: Int = 0) {
        self.id = atom.uuid
        self.uuid = atom.uuid
        self.entityId = atom.id ?? 0
        self.title = atom.title ?? "Untitled"
        self.atomType = atom.type
        self.isFolder = atom.type == .project
        self.preview = atom.body.flatMap { String($0.prefix(100)) }
        self.statusBadge = nil

        // Populate thumbnail URL from research metadata, YouTube video ID, or image path
        if atom.type == .image, let imagePath = atom.imageMetadata?.imagePath {
            self.thumbnailURL = imagePath
        } else if let thumbUrl = atom.thumbnailUrl, !thumbUrl.isEmpty {
            self.thumbnailURL = thumbUrl
        } else if let videoId = atom.videoId, !videoId.isEmpty {
            self.thumbnailURL = "https://img.youtube.com/vi/\(videoId)/mqdefault.jpg"
        } else {
            self.thumbnailURL = nil
        }

        // Type-specific formatting
        switch atom.type {
        case .idea:
            self.icon = "lightbulb.fill"
            self.color = Color(hex: "#CAB8E8")
            self.typeName = "Idea"
        case .task:
            self.icon = "checkmark.circle.fill"
            self.color = Color(hex: "#F4AFA0")
            self.typeName = "Task"
        case .content:
            self.icon = "doc.text.fill"
            self.color = Color(hex: "#A8CCE8")
            self.typeName = "Content"
        case .research:
            self.icon = "book.fill"
            self.color = Color(hex: "#8FC7A2")
            self.typeName = "Research"
        case .connection:
            self.icon = "link.circle.fill"
            self.color = Color(hex: "#8B5CF6")
            self.typeName = "Connection"
        case .project:
            self.icon = "folder.fill"
            self.color = Color(hex: "#6366F1")
            self.typeName = "Project"
        case .image:
            self.icon = "photo.fill"
            self.color = DS.entityImage
            self.typeName = "Image"
        default:
            self.icon = "circle.fill"
            self.color = Color(hex: "#6366F1")
            self.typeName = atom.type.displayName
        }

        // Child count for folders
        self.childCount = childCount

        // Relative date
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: atom.updatedAt) {
            self.updatedAt = date
            let interval = Date().timeIntervalSince(date)
            if interval < 60 { self.relativeDate = "now" }
            else if interval < 3600 { self.relativeDate = "\(Int(interval / 60))m" }
            else if interval < 86400 { self.relativeDate = "\(Int(interval / 3600))h" }
            else if interval < 604800 { self.relativeDate = "\(Int(interval / 86400))d" }
            else { self.relativeDate = "\(Int(interval / 604800))w" }
        } else {
            self.updatedAt = Date()
            self.relativeDate = ""
        }
    }
}

// MARK: - LibraryViewModel

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var allItems: [LibraryItem] = []
    @Published var displayItems: [LibraryItem] = []
    @Published var breadcrumbs: [LibraryBreadcrumb] = [
        LibraryBreadcrumb(id: "home", title: "Home", uuid: nil)
    ]
    @Published var smartCollections: [SmartCollection] = []
    @Published var isLoading: Bool = false
    @Published var currentFolderUUID: String? = nil
    @Published var showingRecentlyDeleted: Bool = false
    @Published var recentlyDeletedItems: [LibraryItem] = []

    private var searchFilter: String = ""
    private var sortMode: LibrarySortMode = .dateAdded
    private var libraryLoaded = false

    /// UUIDs of atoms that belong to a project (via thinkspace or link) — excluded from top-level
    private var projectOwnedAtomUUIDs: Set<String> = []

    /// Per-project child counts (for folder card badges)
    private var projectChildCounts: [String: Int] = [:]

    var isAtHome: Bool {
        currentFolderUUID == nil
    }

    // MARK: - Load

    func forceReload() {
        libraryLoaded = false
    }

    func loadLibrary() async {
        guard !libraryLoaded else { return }
        isLoading = true
        do {
            // Fetch all user-facing atoms (ideas excluded — they live in the Ideas tab)
            let userTypes: [AtomType] = [.content, .research, .connection, .project, .image]
            let atoms = try await AtomRepository.shared.fetchAll(types: userTypes)

            // Compute project-owned atom UUIDs (atoms on project thinkspaces or with project links)
            let projectThinkspaces = ThinkspaceManager.shared.thinkspaces.filter { $0.projectUuid != nil }
            let projectThinkspaceIds = projectThinkspaces.map(\.id)
            let projectAtoms = atoms.filter { $0.type == .project }
            let projectUUIDs = projectAtoms.map(\.uuid)

            let (allOwned, perProject) = try await AtomRepository.shared.fetchProjectOwnedAtomUUIDs(
                projectThinkspaceIds: projectThinkspaceIds,
                projectUUIDs: projectUUIDs
            )
            projectOwnedAtomUUIDs = allOwned
            projectChildCounts = perProject.mapValues(\.count)

            allItems = atoms.filter { !$0.isDeleted && !$0.isSwipeFileAtom }.map { atom in
                if atom.type == .project, let count = projectChildCounts[atom.uuid] {
                    return LibraryItem(atom: atom, childCount: count)
                }
                return LibraryItem(atom: atom)
            }
            applySort()
            applyFilters()

            // Build smart collections
            await buildSmartCollections(atoms: atoms)
            libraryLoaded = true
        } catch {
            print("⚠️ Library load failed: \(error)")
        }
        isLoading = false
    }

    // MARK: - Smart Collections

    private func buildSmartCollections(atoms: [Atom]) async {
        var collections: [SmartCollection] = []

        // Recently Active (modified in last 7 days)
        let recentCount = allItems.filter {
            $0.updatedAt.timeIntervalSinceNow > -604800
        }.count
        if recentCount > 0 {
            collections.append(SmartCollection(
                id: "recent",
                title: "Recently Active",
                icon: "clock.fill",
                color: Color(hex: "#6366F1"),
                count: recentCount,
                filterType: .recentlyActive
            ))
        }

        // In Progress (non-archived content + active tasks)
        let inProgressCount = atoms.filter { atom in
            if atom.type == .content {
                let body = atom.body ?? ""
                return !body.contains("archived") && !body.contains("published")
            }
            if atom.type == .task {
                let body = atom.body ?? ""
                return !body.contains("done") && !body.contains("archived")
            }
            return false
        }.count
        if inProgressCount > 0 {
            collections.append(SmartCollection(
                id: "inprogress",
                title: "In Progress",
                icon: "arrow.triangle.2.circlepath",
                color: CosmoColors.coral,
                count: inProgressCount,
                filterType: .byStatus
            ))
        }

        // By Client (if client profiles exist)
        let clientAtoms = try? await AtomRepository.shared.fetchAll(type: .clientProfile)
        if let clients = clientAtoms, !clients.isEmpty {
            for client in clients.prefix(4) {
                let clientName = client.title ?? "Client"
                let linkedCount = atoms.filter { atom in
                    atom.linksList.contains { $0.uuid == client.uuid }
                }.count
                if linkedCount > 0 {
                    collections.append(SmartCollection(
                        id: "client-\(client.uuid)",
                        title: clientName,
                        icon: "person.fill",
                        color: CosmoColors.skyBlue,
                        count: linkedCount,
                        filterType: .byClient(client.uuid)
                    ))
                }
            }
        }

        smartCollections = collections
    }

    // MARK: - Navigation

    func handleItemTap(_ item: LibraryItem) {
        if item.isFolder {
            navigateIntoFolder(item)
        } else {
            openInFocusMode(item)
        }
    }

    func navigateIntoFolder(_ item: LibraryItem) {
        currentFolderUUID = item.uuid
        breadcrumbs.append(LibraryBreadcrumb(id: item.uuid, title: item.title, uuid: item.uuid))

        Task {
            await loadFolderContents(item.uuid)
        }
    }

    func navigateToBreadcrumb(_ crumb: LibraryBreadcrumb) {
        if crumb.uuid == nil {
            // Home
            currentFolderUUID = nil
            breadcrumbs = [LibraryBreadcrumb(id: "home", title: "Home", uuid: nil)]
            applyFilters()
        } else if let idx = breadcrumbs.firstIndex(where: { $0.id == crumb.id }) {
            breadcrumbs = Array(breadcrumbs.prefix(through: idx))
            currentFolderUUID = crumb.uuid
            Task {
                await loadFolderContents(crumb.uuid!)
            }
        }
    }

    func openInFocusMode(_ item: LibraryItem) {
        let entityType: String
        switch item.atomType {
        case .idea: entityType = "idea"
        case .task: entityType = "task"
        case .content: entityType = "content"
        case .research: entityType = "research"
        case .connection: entityType = "connection"
        case .project: entityType = "project"
        default: entityType = "idea"
        }

        NotificationCenter.default.post(
            name: .enterFocusMode,
            object: nil,
            userInfo: ["type": entityType, "id": item.uuid]
        )
    }

    func openSmartCollection(_ collection: SmartCollection) {
        breadcrumbs.append(LibraryBreadcrumb(id: collection.id, title: collection.title, uuid: nil))

        switch collection.filterType {
        case .recentlyActive:
            displayItems = allItems
                .filter { $0.updatedAt.timeIntervalSinceNow > -604800 }
                .sorted { $0.updatedAt > $1.updatedAt }
        case .byStatus:
            displayItems = allItems.filter { $0.atomType == .content || $0.atomType == .task }
        case .byClient(let clientUUID):
            Task {
                let linked = try? await AtomRepository.shared.search(metadataKey: "clientUUID", value: clientUUID)
                if let atoms = linked {
                    displayItems = atoms.map { LibraryItem(atom: $0) }
                }
            }
        case .byTopic:
            break
        case .connectionDashboard:
            displayItems = allItems.filter { $0.atomType == .connection }
        }
    }

    // MARK: - Folder Contents

    private func loadFolderContents(_ folderUUID: String) async {
        do {
            // 1. Get atoms with explicit project links
            let linkedAtoms = try await AtomRepository.shared.fetchByProject(projectUuid: folderUUID)

            // 2. Get atoms on project thinkspaces (canvas_blocks)
            let projectThinkspaceIds = ThinkspaceManager.shared.thinkspacesForProject(folderUUID).map(\.id)
            let thinkspaceAtomUUIDs = try await AtomRepository.shared.fetchAtomUUIDsInThinkspaces(projectThinkspaceIds)

            // 3. Merge: start with linked atoms, then add thinkspace atoms not already included
            var seenUUIDs = Set(linkedAtoms.map(\.uuid))
            var allAtoms = linkedAtoms.filter { !$0.isDeleted && $0.type != .project && $0.type != .thinkspace }

            let missingUUIDs = thinkspaceAtomUUIDs.subtracting(seenUUIDs)
            for uuid in missingUUIDs {
                if let atom = try await AtomRepository.shared.fetch(uuid: uuid),
                   !atom.isDeleted && atom.type != .project && atom.type != .thinkspace {
                    allAtoms.append(atom)
                    seenUUIDs.insert(uuid)
                }
            }

            displayItems = allAtoms.filter { !$0.isSwipeFileAtom }.map { LibraryItem(atom: $0) }
            applySortToDisplay()
        } catch {
            print("⚠️ Folder load failed: \(error)")
        }
    }

    // MARK: - Sort & Filter

    func applySortMode(_ mode: LibrarySortMode) {
        sortMode = mode
        applySort()
        applyFilters()
    }

    func filterBySearch(_ query: String) {
        searchFilter = query
        applyFilters()
    }

    private func applySort() {
        switch sortMode {
        case .dateAdded:
            allItems.sort { $0.updatedAt > $1.updatedAt }
        case .lastModified:
            allItems.sort { $0.updatedAt > $1.updatedAt }
        case .name:
            allItems.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .type:
            allItems.sort { $0.typeName < $1.typeName }
        }
    }

    private func applySortToDisplay() {
        switch sortMode {
        case .dateAdded, .lastModified:
            displayItems.sort { $0.updatedAt > $1.updatedAt }
        case .name:
            displayItems.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .type:
            displayItems.sort { $0.typeName < $1.typeName }
        }
    }

    private func applyFilters() {
        guard currentFolderUUID == nil else { return }

        var items = allItems

        // When searching, show ALL atoms (including project-owned) so search finds them
        if !searchFilter.isEmpty {
            items = items.filter {
                $0.title.localizedCaseInsensitiveContains(searchFilter) ||
                ($0.preview?.localizedCaseInsensitiveContains(searchFilter) ?? false)
            }
        } else {
            // At home level without search: exclude non-folder atoms owned by a project
            items = items.filter { item in
                item.isFolder || !projectOwnedAtomUUIDs.contains(item.uuid)
            }
        }

        // Folders first, then individual items
        let folders = items.filter(\.isFolder)
        let nonFolders = items.filter { !$0.isFolder }
        items = folders + nonFolders

        displayItems = items
    }

    // MARK: - Delete & Restore

    func softDeleteItem(uuid: String) {
        Task {
            do {
                try await AtomRepository.shared.delete(uuid: uuid)
                allItems.removeAll { $0.uuid == uuid }
                applyFilters()
            } catch {
                print("⚠️ Delete failed: \(error)")
            }
        }
    }

    func restoreItem(uuid: String) {
        Task {
            do {
                try await CosmoDatabase.shared.asyncWrite { db in
                    try db.execute(
                        sql: "UPDATE atoms SET is_deleted = 0, updated_at = ? WHERE uuid = ?",
                        arguments: [ISO8601DateFormatter().string(from: Date()), uuid]
                    )
                }
                // Reload to pick up restored item
                if let atom = try? await AtomRepository.shared.fetch(uuid: uuid) {
                    allItems.insert(LibraryItem(atom: atom), at: 0)
                }
                recentlyDeletedItems.removeAll { $0.uuid == uuid }
                applyFilters()
            } catch {
                print("⚠️ Restore failed: \(error)")
            }
        }
    }

    func permanentlyDelete(uuid: String) {
        Task {
            do {
                try await AtomRepository.shared.hardDelete(uuid: uuid)
                recentlyDeletedItems.removeAll { $0.uuid == uuid }
            } catch {
                print("⚠️ Permanent delete failed: \(error)")
            }
        }
    }

    func loadRecentlyDeleted() async {
        do {
            let userTypes: [AtomType] = [.content, .research, .connection, .project]
            let typeStrings = userTypes.map { $0.rawValue }
            let thirtyDaysAgo = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-30 * 86400))

            let atoms = try await CosmoDatabase.shared.asyncRead { db in
                try Atom
                    .filter(typeStrings.contains(Column("type")))
                    .filter(Atom.CodingKeys.isDeleted == true)
                    .filter(Column("updated_at") >= thirtyDaysAgo)
                    .order(Atom.CodingKeys.updatedAt.desc)
                    .fetchAll(db)
            }

            recentlyDeletedItems = atoms.filter { !$0.isSwipeFileAtom }.map { LibraryItem(atom: $0) }
        } catch {
            print("⚠️ Recently deleted load failed: \(error)")
        }
    }

    // MARK: - Create

    func createAtom(type: AtomType) {
        Task {
            let atom = Atom.new(type: type, title: "Untitled \(type.displayName)")
            let created = try? await AtomRepository.shared.create(atom)
            if let created = created {
                allItems.insert(LibraryItem(atom: created), at: 0)
                applyFilters()

                // Open in focus mode
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.openInFocusMode(LibraryItem(atom: created))
                }
            }
        }
    }

    func createResearch(url: String) {
        Task {
            let title = URL(string: url)?.host ?? "Research"
            let created = try? await AtomRepository.shared.createResearch(title: title, url: url)
            if let created = created {
                allItems.insert(LibraryItem(atom: created), at: 0)
                applyFilters()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.openInFocusMode(LibraryItem(atom: created))
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Library View") {
    LibraryView()
        .frame(width: 1000, height: 700)
}
