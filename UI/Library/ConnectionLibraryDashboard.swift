// CosmoOS/UI/Library/ConnectionLibraryDashboard.swift
// Connection Library and Maturity Dashboard
// Surfaces maturity badges, profile tags, usage data, filters,
// and a "Connections to Develop" nudge section.
// February 2026

import SwiftUI
import GRDB

// MARK: - Connection Library Filter

enum ConnectionLibraryFilter: Equatable {
    case all
    case maturity(ConnectionMaturityLevel)
    case profile(String) // profile UUID

    var displayName: String {
        switch self {
        case .all: return "All"
        case .maturity(let level): return level.displayName
        case .profile: return "Profile"
        }
    }
}

// MARK: - Connection Library Sort

enum ConnectionLibrarySort: String, CaseIterable {
    case maturity
    case usageCount
    case lastModified
    case name

    var displayName: String {
        switch self {
        case .maturity: return "Maturity"
        case .usageCount: return "Most Used"
        case .lastModified: return "Last Modified"
        case .name: return "Name"
        }
    }
}

// MARK: - Connection Library Item

struct ConnectionLibraryItem: Identifiable, Equatable {
    let id: String
    let uuid: String
    let title: String
    let maturity: ConnectionMaturityLevel
    let filledSections: Int
    let totalSections: Int
    let usageCount: Int
    let linkedProfileIds: [String]
    let updatedAt: Date
    let preview: String?
    let ideaReferenceCount: Int // times referenced in ideas but never developed

    static func == (lhs: ConnectionLibraryItem, rhs: ConnectionLibraryItem) -> Bool {
        lhs.id == rhs.id
    }

    var relativeDate: String {
        let interval = Date().timeIntervalSince(updatedAt)
        if interval < 60 { return "now" }
        else if interval < 3600 { return "\(Int(interval / 60))m" }
        else if interval < 86400 { return "\(Int(interval / 3600))h" }
        else if interval < 604800 { return "\(Int(interval / 86400))d" }
        else { return "\(Int(interval / 604800))w" }
    }
}

// MARK: - Profile Display Info

struct ProfileDisplayInfo: Identifiable, Equatable {
    let id: String
    let uuid: String
    let name: String
}

// MARK: - Connection Library Dashboard View

struct ConnectionLibraryDashboard: View {
    @StateObject private var viewModel = ConnectionLibraryViewModel()
    @State private var searchText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            dashboardHeader

            Divider().background(DS.borderActive)

            // Filter chips
            filterBar
                .padding(.horizontal, 24)
                .padding(.vertical, 10)

            // Content
            if viewModel.isLoading {
                loadingView
            } else if viewModel.filteredItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        // Connections to Develop section
                        if !viewModel.connectionsToDevelop.isEmpty {
                            developSection
                        }

                        // Main grid
                        connectionGrid
                    }
                    .padding(24)
                }
            }
        }
        .background(DS.bg)
        .task {
            await viewModel.loadConnections()
        }
        .onChange(of: searchText) { newText in
            viewModel.filterBySearch(newText)
        }
    }

    // MARK: - Header

    private var dashboardHeader: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color(hex: "#8B5CF6").opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(hex: "#8B5CF6"))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Concept Library")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(DS.text)
                Text("\(viewModel.allItems.count) concepts")
                    .font(.system(size: 13))
                    .foregroundColor(DS.textMuted)
            }

            Spacer()

            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundColor(DS.textMuted)
                TextField("Search concepts...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(DS.text)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(DS.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(DS.border)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(DS.borderActive, lineWidth: 1)
                    )
            )
            .frame(maxWidth: 280)

            // Sort menu
            Menu {
                ForEach(ConnectionLibrarySort.allCases, id: \.rawValue) { mode in
                    Button {
                        viewModel.sortMode = mode
                        viewModel.applyFilters()
                    } label: {
                        HStack {
                            Text(mode.displayName)
                            if viewModel.sortMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(viewModel.sortMode.displayName)
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
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // All filter
                filterChip(label: "All", isSelected: viewModel.activeFilter == .all) {
                    viewModel.activeFilter = .all
                    viewModel.applyFilters()
                }

                // Divider
                Rectangle()
                    .fill(DS.borderActive)
                    .frame(width: 1, height: 20)

                // Maturity filters
                ForEach(ConnectionMaturityLevel.allCases, id: \.rawValue) { level in
                    filterChip(
                        label: level.displayName,
                        isSelected: viewModel.activeFilter == .maturity(level),
                        color: maturityColor(level)
                    ) {
                        viewModel.activeFilter = .maturity(level)
                        viewModel.applyFilters()
                    }
                }

                // Profile filters
                if !viewModel.profiles.isEmpty {
                    Rectangle()
                        .fill(DS.borderActive)
                        .frame(width: 1, height: 20)

                    ForEach(viewModel.profiles) { profile in
                        filterChip(
                            label: profile.name,
                            isSelected: viewModel.activeFilter == .profile(profile.uuid),
                            color: CosmoColors.skyBlue
                        ) {
                            viewModel.activeFilter = .profile(profile.uuid)
                            viewModel.applyFilters()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func filterChip(label: String, isSelected: Bool, color: Color = Color.white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? color : DS.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? color.opacity(0.15) : DS.borderSubtle)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? color.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Connections to Develop

    private var developSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "#F59E0B"))
                Text("Concepts to Develop")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.text)
                Spacer()
                Text("\(viewModel.connectionsToDevelop.count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "#F59E0B"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color(hex: "#F59E0B").opacity(0.15))
                    )
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.connectionsToDevelop) { item in
                        developNudgeCard(item)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(hex: "#F59E0B").opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color(hex: "#F59E0B").opacity(0.12), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func developNudgeCard(_ item: ConnectionLibraryItem) -> some View {
        Button {
            openConnectionFocusMode(item)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#8B5CF6"))
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DS.text)
                        .lineLimit(1)
                }

                maturityBadge(item.maturity)

                Text("Referenced \(item.ideaReferenceCount)x but still a stub. Develop it to improve your content.")
                    .font(.system(size: 11))
                    .foregroundColor(DS.textMuted)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                sectionProgressBar(filled: item.filledSections, total: item.totalSections)
            }
            .padding(14)
            .frame(width: 260, alignment: .leading)
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

    // MARK: - Connection Grid

    private var connectionGrid: some View {
        let columns = [
            GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 16)
        ]

        return LazyVGrid(columns: columns, spacing: 16) {
            ForEach(viewModel.filteredItems) { item in
                connectionCard(item)
            }
        }
    }

    @ViewBuilder
    private func connectionCard(_ item: ConnectionLibraryItem) -> some View {
        ConnectionLibraryCard(
            item: item,
            profiles: viewModel.profiles,
            onTap: { openConnectionFocusMode(item) },
            onAssignProfile: { profileUUID in
                viewModel.assignProfile(profileUUID, to: item)
            },
            onCreateContent: {
                createContentFromConnection(item)
            }
        )
    }

    // MARK: - Helpers

    private func maturityColor(_ level: ConnectionMaturityLevel) -> Color {
        switch level {
        case .seed: return Color.gray
        case .developing: return Color(hex: "#F59E0B")
        case .mature: return Color(hex: "#22C55E")
        case .proven: return Color(hex: "#FFD700")
        }
    }

    @ViewBuilder
    private func maturityBadge(_ level: ConnectionMaturityLevel) -> some View {
        let color = maturityColor(level)
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(level.displayName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(color.opacity(0.12))
        )
    }

    @ViewBuilder
    private func sectionProgressBar(filled: Int, total: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<total, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i < filled ? Color(hex: "#8B5CF6") : DS.borderActive)
                    .frame(height: 4)
            }
        }
        .frame(height: 4)
    }

    private func openConnectionFocusMode(_ item: ConnectionLibraryItem) {
        NotificationCenter.default.post(
            name: .enterFocusMode,
            object: nil,
            userInfo: ["type": "connection", "id": item.uuid]
        )
    }

    private func createContentFromConnection(_ item: ConnectionLibraryItem) {
        NotificationCenter.default.post(
            name: CosmoNotification.NodeGraph.addToCanvas,
            object: nil,
            userInfo: ["atomUUID": item.uuid]
        )
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "link.circle")
                .font(.system(size: 48))
                .foregroundColor(Color(hex: "#8B5CF6").opacity(0.2))
            Text("No concepts yet")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(DS.textSecondary)
            Text("Create concepts to build your knowledge framework")
                .font(.system(size: 13))
                .foregroundColor(DS.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingView: some View {
        VStack {
            ProgressView()
                .scaleEffect(1.2)
                .tint(DS.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Connection Library Card

private struct ConnectionLibraryCard: View {
    let item: ConnectionLibraryItem
    let profiles: [ProfileDisplayInfo]
    let onTap: () -> Void
    let onAssignProfile: (String) -> Void
    let onCreateContent: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top row: title + maturity
            topRow

            // Preview text
            if let preview = item.preview, !preview.isEmpty {
                Text(preview)
                    .font(.system(size: 12))
                    .foregroundColor(DS.textMuted)
                    .lineLimit(2)
            }

            // Section progress
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(item.filledSections)/\(item.totalSections) sections")
                        .font(.system(size: 11))
                        .foregroundColor(DS.textMuted)
                    Spacer()
                    if item.usageCount > 0 {
                        usageCountBadge
                    }
                }
                sectionProgressBar
            }

            // Profile pills
            if !item.linkedProfileIds.isEmpty {
                profilePills
            }

            // Bottom row: date
            HStack {
                Text(item.relativeDate)
                    .font(.system(size: 11))
                    .foregroundColor(DS.textMuted)
                Spacer()
            }
        }
        .padding(14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(isHovered ? 0.35 : 0.15), radius: isHovered ? 12 : 6, y: isHovered ? 6 : 3)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovered)
        .onHover { hovering in isHovered = hovering }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .contextMenu {
            contextMenuContent
        }
    }

    // MARK: - Top Row

    @ViewBuilder
    private var topRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "#8B5CF6"))

            Text(item.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.text)
                .lineLimit(1)

            Spacer()

            maturityPill
        }
    }

    // MARK: - Maturity Pill

    @ViewBuilder
    private var maturityPill: some View {
        let color = maturityPillColor
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(item.maturity.displayName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(color.opacity(0.12))
        )
    }

    private var maturityPillColor: Color {
        switch item.maturity {
        case .seed: return Color.gray
        case .developing: return Color(hex: "#F59E0B")
        case .mature: return Color(hex: "#22C55E")
        case .proven: return Color(hex: "#FFD700")
        }
    }

    // MARK: - Usage Count Badge

    @ViewBuilder
    private var usageCountBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 8))
            Text("\(item.usageCount) uses")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(Color(hex: "#A78BFA"))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(Color(hex: "#A78BFA").opacity(0.1))
        )
    }

    // MARK: - Section Progress Bar

    @ViewBuilder
    private var sectionProgressBar: some View {
        HStack(spacing: 3) {
            ForEach(0..<item.totalSections, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i < item.filledSections ? Color(hex: "#8B5CF6") : DS.borderActive)
                    .frame(height: 4)
            }
        }
        .frame(height: 4)
    }

    // MARK: - Profile Pills

    @ViewBuilder
    private var profilePills: some View {
        let matchingProfiles = profiles.filter { item.linkedProfileIds.contains($0.uuid) }
        if !matchingProfiles.isEmpty {
            HStack(spacing: 6) {
                ForEach(matchingProfiles) { profile in
                    profilePillLabel(profile)
                }
            }
        }
    }

    @ViewBuilder
    private func profilePillLabel(_ profile: ProfileDisplayInfo) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 9))
            Text(profile.name)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(CosmoColors.skyBlue)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(CosmoColors.skyBlue.opacity(0.1))
        )
    }

    // MARK: - Card Background

    private var cardBackground: some View {
        ZStack {
            DS.surfaceElevated
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isHovered ? DS.borderActive : DS.border,
                    lineWidth: 1
                )
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuContent: some View {
        Button {
            onTap()
        } label: {
            Label("Open in Focus Mode", systemImage: "arrow.up.left.and.arrow.down.right")
        }

        if !profiles.isEmpty {
            Menu("Assign to Profile") {
                ForEach(profiles) { profile in
                    Button {
                        onAssignProfile(profile.uuid)
                    } label: {
                        Label(profile.name, systemImage: item.linkedProfileIds.contains(profile.uuid) ? "checkmark.circle.fill" : "person.crop.circle")
                    }
                }
            }
        }

        Button {
            onCreateContent()
        } label: {
            Label("Add to Canvas", systemImage: "plus.rectangle.on.rectangle")
        }
    }
}

// MARK: - Connection Library ViewModel

@MainActor
final class ConnectionLibraryViewModel: ObservableObject {
    @Published var allItems: [ConnectionLibraryItem] = []
    @Published var filteredItems: [ConnectionLibraryItem] = []
    @Published var connectionsToDevelop: [ConnectionLibraryItem] = []
    @Published var profiles: [ProfileDisplayInfo] = []
    @Published var activeFilter: ConnectionLibraryFilter = .all
    @Published var sortMode: ConnectionLibrarySort = .maturity
    @Published var isLoading = false

    private var searchFilter = ""
    private let coDevEngine = ConnectionCoDevEngine()

    // MARK: - Load

    func loadConnections() async {
        isLoading = true

        do {
            // Fetch all connection atoms
            let connectionAtoms = try await AtomRepository.shared.fetchAll(type: .connection)
            let nonDeleted = connectionAtoms.filter { !$0.isDeleted }

            // Fetch client profiles for display
            let profileAtoms = try await AtomRepository.shared.fetchAll(type: .clientProfile)
            profiles = profileAtoms.compactMap { atom in
                guard let name = atom.title, !name.isEmpty else { return nil }
                return ProfileDisplayInfo(id: atom.uuid, uuid: atom.uuid, name: name)
            }

            // Build library items
            var items: [ConnectionLibraryItem] = []
            for atom in nonDeleted {
                let item = await buildLibraryItem(from: atom)
                items.append(item)
            }

            allItems = items
            applyFilters()

            // Build "Connections to Develop"
            connectionsToDevelop = items.filter { item in
                item.maturity == .seed && item.ideaReferenceCount > 0
            }.sorted { $0.ideaReferenceCount > $1.ideaReferenceCount }

        } catch {
            print("[ConnectionLibrary] Load failed: \(error)")
        }

        isLoading = false
    }

    // MARK: - Build Item

    private func buildLibraryItem(from atom: Atom) async -> ConnectionLibraryItem {
        // Parse sections
        var filledSections = 0
        if let structured = atom.structured,
           let data = ConnectionStructuredData.fromJSON(structured) {
            filledSections = data.sections.filter { !$0.items.isEmpty }.count
        }

        // Get linked source count
        let sourceCount = await countLinkedSources(for: atom.uuid)

        // Usage count from metadata
        let usageCount = atom.connectionUsageCount

        // Linked profiles
        let linkedProfiles = atom.connectionLinkedProfileIds

        // Compute maturity
        let maturity = coDevEngine.computeMaturity(
            connection: atom,
            sourceCount: sourceCount,
            contentUsageCount: usageCount,
            profileCount: linkedProfiles.count
        )

        // Count idea references
        let ideaRefCount = await countIdeaReferences(for: atom)

        // Parse date
        let formatter = ISO8601DateFormatter()
        let updatedAt = formatter.date(from: atom.updatedAt) ?? Date()

        let preview = atom.body.flatMap { String($0.prefix(120)) }

        return ConnectionLibraryItem(
            id: atom.uuid,
            uuid: atom.uuid,
            title: atom.title ?? "Untitled Concept",
            maturity: maturity,
            filledSections: filledSections,
            totalSections: 8,
            usageCount: usageCount,
            linkedProfileIds: linkedProfiles,
            updatedAt: updatedAt,
            preview: preview,
            ideaReferenceCount: ideaRefCount
        )
    }

    private func countLinkedSources(for connectionUUID: String) async -> Int {
        do {
            let queryEngine = GraphQueryEngine()
            let neighbors = try await queryEngine.getNeighbors(of: connectionUUID, direction: .both, limit: 50)
            return neighbors.count
        } catch {
            return 0
        }
    }

    private func countIdeaReferences(for atom: Atom) async -> Int {
        let title = atom.title ?? ""
        guard !title.isEmpty else { return 0 }

        do {
            let ideaAtoms = try await AtomRepository.shared.fetchAll(type: .idea)
            var count = 0
            let lowercaseTitle = title.lowercased()
            for idea in ideaAtoms {
                let body = (idea.body ?? "").lowercased()
                let ideaTitle = (idea.title ?? "").lowercased()
                if body.contains(lowercaseTitle) || ideaTitle.contains(lowercaseTitle) {
                    count += 1
                }
            }
            return count
        } catch {
            return 0
        }
    }

    // MARK: - Filter & Sort

    func filterBySearch(_ query: String) {
        searchFilter = query
        applyFilters()
    }

    func applyFilters() {
        var items = allItems

        // Apply filter
        switch activeFilter {
        case .all:
            break
        case .maturity(let level):
            items = items.filter { $0.maturity == level }
        case .profile(let profileUUID):
            items = items.filter { $0.linkedProfileIds.contains(profileUUID) }
        }

        // Apply search
        if !searchFilter.isEmpty {
            items = items.filter {
                $0.title.localizedCaseInsensitiveContains(searchFilter) ||
                ($0.preview?.localizedCaseInsensitiveContains(searchFilter) ?? false)
            }
        }

        // Apply sort
        switch sortMode {
        case .maturity:
            items.sort { $0.maturity.sortOrder > $1.maturity.sortOrder }
        case .usageCount:
            items.sort { $0.usageCount > $1.usageCount }
        case .lastModified:
            items.sort { $0.updatedAt > $1.updatedAt }
        case .name:
            items.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }

        filteredItems = items
    }

    // MARK: - Actions

    func assignProfile(_ profileUUID: String, to item: ConnectionLibraryItem) {
        Task {
            guard var atom = try? await AtomRepository.shared.fetch(uuid: item.uuid) else { return }
            var ids = atom.connectionLinkedProfileIds
            if ids.contains(profileUUID) {
                ids.removeAll { $0 == profileUUID }
            } else {
                ids.append(profileUUID)
            }
            atom.setConnectionLinkedProfileIds(ids)

            try? await CosmoDatabase.shared.asyncWrite { db in
                try db.execute(
                    sql: "UPDATE atoms SET metadata = ?, updated_at = ? WHERE uuid = ?",
                    arguments: [atom.metadata, ISO8601.string(from: Date()), item.uuid]
                )
            }

            // Refresh
            await loadConnections()
        }
    }
}

// MARK: - Previews

#Preview("Connection Library Dashboard") {
    ConnectionLibraryDashboard()
        .frame(width: 900, height: 700)
}
