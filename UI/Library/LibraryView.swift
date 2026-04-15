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
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Sync.atomsPulled)) { _ in
            viewModel.forceReload()
            Task { await viewModel.loadLibrary() }
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
                    .foregroundStyle(DS.textOnAccent)
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

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DS.text)
                    .lineLimit(1)

                if let provenance = item.provenanceSummary, !provenance.isEmpty {
                    Text(provenance)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.textMuted)
                        .lineLimit(1)
                }
            }

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

enum LibraryItemKind: String {
    case atom
    case project
    case thinkspace

    var sortRank: Int {
        switch self {
        case .project: return 0
        case .thinkspace: return 1
        case .atom: return 2
        }
    }
}

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
    let childCount: Int
    let createdAt: Date
    let updatedAt: Date
    let preview: String?
    let thumbnailURL: String?
    let statusBadge: String?
    let kind: LibraryItemKind
    let projectUUID: String?
    let projectName: String?
    let thinkspaceUUIDs: [String]
    let thinkspaceNames: [String]
    let nestedThinkspaceCount: Int
    let blockCount: Int

    var isFolder: Bool {
        kind == .project
    }

    var provenanceSummary: String? {
        switch kind {
        case .project:
            return nil
        case .thinkspace:
            return projectName
        case .atom:
            let segments = [projectName, thinkspaceNames.first].compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            return segments.isEmpty ? nil : segments.joined(separator: " / ")
        }
    }

    private static func relativeDateString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        if interval < 604800 { return "\(Int(interval / 86400))d" }
        return "\(Int(interval / 604800))w"
    }

    private static func parseISO8601Date(_ value: String) -> Date? {
        ISO8601.date(from: value)
    }

    /// Extract readable text from JSON body (slide-based content, structured data)
    private static func extractTextFromJSON(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }

        var texts: [String] = []

        if let dict = obj as? [String: Any] {
            // {"slides": [{"number": 1, "text": "..."}]} format
            if let slides = dict["slides"] as? [[String: Any]] {
                for slide in slides {
                    if let text = slide["text"] as? String, !text.isEmpty {
                        texts.append(text)
                    }
                }
            }
            // Direct text fields
            for key in ["text", "content", "body", "hook", "caption"] {
                if let val = dict[key] as? String, !val.isEmpty {
                    texts.append(val)
                }
            }
        } else if let arr = obj as? [[String: Any]] {
            // Array of slides directly
            for item in arr {
                if let text = item["text"] as? String, !text.isEmpty {
                    texts.append(text)
                }
            }
        }

        let result = texts.joined(separator: "\n\n")
        return result.isEmpty ? nil : result
    }

    /// Structured section preview for connections — labeled paragraphs create visual fingerprint
    private static func connectionPreviewText(atom: Atom) -> String? {
        let fields: [(String, String?)] = [
            ("IDEA", atom.idea),
            ("BELIEF", atom.personalBelief),
            ("GOAL", atom.goal),
            ("PROBLEMS", atom.problems),
            ("BENEFIT", atom.benefit),
            ("OBJECTIONS", atom.beliefsObjections),
            ("EXAMPLE", atom.example),
            ("PROCESS", atom.process),
            ("NOTES", atom.notes),
        ]
        let sections = fields.compactMap { label, value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return "\(label)\n\(value)"
        }
        return sections.isEmpty ? nil : sections.joined(separator: "\n\n")
    }

    init(atom: Atom, childCount: Int = 0, project: Atom? = nil, thinkspaces: [Thinkspace] = []) {
        let thinkspaceMetadata = atom.type == .thinkspace
            ? atom.metadataValue(as: ThinkspaceMetadata.self)
            : nil
        // 500 chars is enough to fill a thumbnail page at 4pt font — more kills perf
        let previewLimit = 500
        let previewText: String? = {
            if let body = atom.body, !body.isEmpty {
                // JSON body (slide-based content) — extract slide text
                let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
                    if let plain = Self.extractTextFromJSON(trimmed) {
                        return String(plain.prefix(previewLimit))
                    }
                }
                return String(body.prefix(previewLimit))
            }
            // Type-specific fallbacks from structured/metadata
            switch atom.type {
            case .connection:
                if let text = Self.connectionPreviewText(atom: atom) {
                    return String(text.prefix(previewLimit))
                }
                // Fallback: combinedText joins all connection fields + title
                let combined = atom.combinedText
                return combined.isEmpty ? nil : String(combined.prefix(previewLimit))
            case .research:
                let meta = atom.researchMetadata
                let parts = [meta?.findings, meta?.summary, meta?.hook].compactMap { $0 }.filter { !$0.isEmpty }
                return parts.isEmpty ? nil : String(parts.joined(separator: "\n\n").prefix(previewLimit))
            case .project:
                return atom.projectMetadata?.projectNotes.map { String($0.prefix(previewLimit)) }
            case .task:
                return atom.taskMetadata?.description.map { String($0.prefix(previewLimit)) }
            case .content:
                let meta = atom.metadataDict
                let parts = [
                    meta?["coreIdea"] as? String,
                    meta?["contentDescription"] as? String,
                    (meta?["hooks"] as? [String])?.joined(separator: "\n"),
                ].compactMap { $0 }.filter { !$0.isEmpty }
                return parts.isEmpty ? nil : String(parts.joined(separator: "\n\n").prefix(previewLimit))
            case .thinkspace:
                if let thinkspaceMetadata {
                    return "\(thinkspaceMetadata.blockIds.count) block\(thinkspaceMetadata.blockIds.count == 1 ? "" : "s")"
                }
                return nil
            default:
                return nil
            }
        }()

        self.id = atom.uuid
        self.uuid = atom.uuid
        self.entityId = atom.id ?? 0
        self.title = thinkspaceMetadata?.name ?? atom.title ?? "Untitled"
        self.atomType = atom.type
        self.preview = previewText
        self.statusBadge = nil
        self.projectUUID = project?.uuid
        self.projectName = project?.title
        self.thinkspaceUUIDs = thinkspaces.map(\.id)
        self.thinkspaceNames = thinkspaces.map(\.name)
        self.nestedThinkspaceCount = 0
        self.blockCount = thinkspaceMetadata?.blockIds.count ?? 0
        switch atom.type {
        case .project:
            self.kind = .project
        case .thinkspace:
            self.kind = .thinkspace
        default:
            self.kind = .atom
        }

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
        case .thinkspace:
            self.icon = "rectangle.3.group"
            self.color = project?.projectMetadata?.color.map { Color(hex: $0) } ?? DS.accent
            self.typeName = "Thinkspace"
        case .image:
            self.icon = "photo.fill"
            self.color = DS.entityImage
            self.typeName = "Image"
        default:
            self.icon = "circle.fill"
            self.color = Color(hex: "#6366F1")
            self.typeName = atom.type.displayName
        }

        self.childCount = childCount

        self.createdAt = Self.parseISO8601Date(atom.createdAt) ?? Date()

        if let date = Self.parseISO8601Date(atom.updatedAt) {
            self.updatedAt = date
            self.relativeDate = Self.relativeDateString(from: date)
        } else {
            self.updatedAt = Date()
            self.relativeDate = ""
        }
    }

    init(thinkspace: Thinkspace, project: Atom?, nestedThinkspaceCount: Int) {
        self.id = thinkspace.id
        self.uuid = thinkspace.id
        self.entityId = 0
        self.title = thinkspace.name
        self.atomType = .thinkspace
        self.icon = "rectangle.3.group"
        if let colorHex = project?.projectMetadata?.color {
            self.color = Color(hex: colorHex)
        } else {
            self.color = DS.accent
        }
        self.typeName = "Thinkspace"
        self.createdAt = thinkspace.lastOpened
        self.updatedAt = thinkspace.lastOpened
        self.relativeDate = Self.relativeDateString(from: thinkspace.lastOpened)
        self.kind = .thinkspace
        self.projectUUID = project?.uuid ?? thinkspace.projectUuid
        self.projectName = project?.title
        self.thinkspaceUUIDs = [thinkspace.id]
        self.thinkspaceNames = [thinkspace.name]
        self.nestedThinkspaceCount = nestedThinkspaceCount
        self.blockCount = thinkspace.blockCount
        self.childCount = nestedThinkspaceCount + thinkspace.blockCount
        self.preview = thinkspace.parentThinkspaceId == nil
            ? "\(thinkspace.blockCount) block\(thinkspace.blockCount == 1 ? "" : "s")"
            : "Nested space · \(thinkspace.blockCount) block\(thinkspace.blockCount == 1 ? "" : "s")"
        self.thumbnailURL = nil
        self.statusBadge = nestedThinkspaceCount > 0 ? "\(nestedThinkspaceCount) space\(nestedThinkspaceCount == 1 ? "" : "s")" : nil
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

    var searchableItems: [LibraryItem] {
        currentFolderUUID == nil ? allItems : displayItems
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
            if ThinkspaceManager.shared.thinkspaces.isEmpty {
                await ThinkspaceManager.shared.loadThinkspaces()
            }
            let projects = atoms.filter { $0.type == .project }
            let projectsByUUID = Dictionary(uniqueKeysWithValues: projects.map { ($0.uuid, $0) })
            let thinkspaces = ThinkspaceManager.shared.sidebarThinkspaces
            let thinkspacesByID = Dictionary(uniqueKeysWithValues: thinkspaces.map { ($0.id, $0) })
            let memberships = try await AtomRepository.shared.fetchThinkspaceMembership(
                for: atoms.filter { $0.type != .project }.map(\.uuid)
            )

            // Compute project-owned atom UUIDs (atoms on project thinkspaces or with project links)
            let projectThinkspaces = ThinkspaceManager.shared.thinkspaces.filter { $0.projectUuid != nil }
            let projectThinkspaceIds = projectThinkspaces.map(\.id)
            let projectUUIDs = projects.map(\.uuid)

            let (allOwned, perProject) = try await AtomRepository.shared.fetchProjectOwnedAtomUUIDs(
                projectThinkspaceIds: projectThinkspaceIds,
                projectUUIDs: projectUUIDs
            )
            projectOwnedAtomUUIDs = allOwned
            projectChildCounts = perProject.mapValues(\.count)

            let atomItems = atoms
                .filter { !$0.isDeleted && !$0.isSwipeFileAtom }
                .map { atom -> LibraryItem in
                    let atomThinkspaces = (memberships[atom.uuid] ?? []).compactMap { thinkspacesByID[$0] }
                    let resolvedProject: Atom? = {
                        if atom.type == .project { return atom }
                        if let explicitProjectUUID = atom.link(ofType: .project)?.uuid,
                           let project = projectsByUUID[explicitProjectUUID] {
                            return project
                        }
                        if let thinkspaceProjectUUID = atomThinkspaces.compactMap(\.projectUuid).first,
                           let project = projectsByUUID[thinkspaceProjectUUID] {
                            return project
                        }
                        return nil
                    }()

                    if atom.type == .project {
                        return LibraryItem(
                            atom: atom,
                            childCount: projectChildCounts[atom.uuid] ?? 0,
                            project: resolvedProject,
                            thinkspaces: []
                        )
                    }

                    return LibraryItem(
                        atom: atom,
                        project: resolvedProject,
                        thinkspaces: atomThinkspaces
                    )
                }

            let thinkspaceItems = thinkspaces.map { thinkspace in
                LibraryItem(
                    thinkspace: thinkspace,
                    project: thinkspace.projectUuid.flatMap { projectsByUUID[$0] },
                    nestedThinkspaceCount: ThinkspaceManager.shared.childThinkspaces(of: thinkspace.id).count
                )
            }

            allItems = atomItems + thinkspaceItems
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
            $0.kind != .thinkspace &&
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
        } else if item.kind == .thinkspace {
            openThinkspace(item)
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
        if item.kind == .thinkspace {
            openThinkspace(item)
            return
        }

        guard let entityType = EntityType(rawValue: item.atomType.rawValue),
              item.entityId > 0 else { return }

        NotificationCenter.default.post(
            name: .enterFocusMode,
            object: nil,
            userInfo: ["type": entityType, "id": item.entityId]
        )
    }

    func openThinkspace(_ item: LibraryItem) {
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.navigateToThinkspaceById,
            object: nil,
            userInfo: CosmoNotification.Navigation.ThinkspacePayload(thinkspaceId: item.uuid).userInfo
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
        let projectThinkspaces = allItems.filter {
            $0.kind == .thinkspace && $0.projectUUID == folderUUID
        }
        let projectAtoms = allItems.filter {
            $0.kind == .atom && $0.projectUUID == folderUUID
        }
        displayItems = projectThinkspaces + projectAtoms
        applySortToDisplay()
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
        allItems.sort(by: librarySortComparator)
    }

    private func applySortToDisplay() {
        displayItems.sort(by: librarySortComparator)
    }

    private func applyFilters() {
        guard currentFolderUUID == nil else { return }

        var items = allItems

        // When searching, show ALL atoms (including project-owned) so search finds them
        if !searchFilter.isEmpty {
            items = items.filter {
                $0.title.localizedCaseInsensitiveContains(searchFilter) ||
                ($0.preview?.localizedCaseInsensitiveContains(searchFilter) ?? false) ||
                ($0.provenanceSummary?.localizedCaseInsensitiveContains(searchFilter) ?? false)
            }
        } else {
            // At home level without search: exclude non-folder atoms owned by a project
            items = items.filter { item in
                if item.kind == .thinkspace {
                    return false
                }
                return item.isFolder || !projectOwnedAtomUUIDs.contains(item.uuid)
            }
        }

        // Folders first, then individual items
        let folders = items.filter(\.isFolder)
        let nonFolders = items.filter { !$0.isFolder }
        items = folders + nonFolders

        displayItems = items
    }

    private func librarySortComparator(lhs: LibraryItem, rhs: LibraryItem) -> Bool {
        if lhs.kind.sortRank != rhs.kind.sortRank {
            return lhs.kind.sortRank < rhs.kind.sortRank
        }

        switch sortMode {
        case .dateAdded:
            return lhs.createdAt > rhs.createdAt
        case .lastModified:
            return lhs.updatedAt > rhs.updatedAt
        case .name:
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        case .type:
            if lhs.typeName != rhs.typeName {
                return lhs.typeName < rhs.typeName
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
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
                try await AtomRepository.shared.hardDelete(uuid: uuid, confirmed: true)
                recentlyDeletedItems.removeAll { $0.uuid == uuid }
            } catch {
                print("⚠️ Permanent delete failed: \(error)")
            }
        }
    }

    func loadRecentlyDeleted() async {
        do {
            let userTypes: [AtomType] = [.content, .research, .connection, .project, .thinkspace]
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
