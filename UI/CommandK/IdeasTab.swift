// CosmoOS/UI/CommandK/IdeasTab.swift
// Ideas tab for Command-K overlay
// Grid/list view with client-grouped list, drag-to-assign, compact cards

import SwiftUI
import UniformTypeIdentifiers

// MARK: - IdeaSortMode

enum IdeaSortMode: String, CaseIterable {
    case recent
    case priority
    case insightScore

    var displayName: String {
        switch self {
        case .recent: return "Recent"
        case .priority: return "Priority"
        case .insightScore: return "Insight Score"
        }
    }
}

// MARK: - IdeaClientSection

private struct IdeaClientSection: Identifiable {
    let id: String
    let clientName: String
    let clientUUID: String?   // nil for "Unassigned"
    let color: Color
    let items: [IdeaGalleryItem]
}

// MARK: - IdeasTab

struct IdeasTab: View {

    @ObservedObject var viewModel: CommandKViewModel
    let searchQuery: String

    @State private var hasAppeared = false

    // Filter/sort state
    @State private var ideaSortMode: IdeaSortMode = .recent
    @State private var ideaStatusFilter: IdeaStatus? = nil
    @State private var ideaFormatFilter: ContentFormat? = nil
    @State private var clientProfiles: [Atom] = []
    @State private var cachedFilteredItems: [IdeaGalleryItem] = []

    private let indigo = DS.entityIdea

    var body: some View {
        ZStack {
            DS.surface

            VStack(spacing: 0) {
                // Library-style filter bar
                filterBar

                Divider().background(DS.borderSubtle)

                // Content area — grid or list
                if cachedFilteredItems.isEmpty {
                    emptyState
                } else {
                    contentView
                }
            }

            // Floating selection bar
            if viewModel.isMultiSelectActive {
                VStack {
                    Spacer()
                    SelectionBar(viewModel: viewModel, accentColor: indigo) {
                        batchDeleteSelectedIdeas()
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(ProMotionSprings.snappy, value: viewModel.isMultiSelectActive)
        .onAppear {
            if viewModel.ideaGalleryItems.isEmpty {
                Task { await viewModel.loadIdeaGallery() }
            }
            recomputeFilteredItems()
            withAnimation(ProMotionSprings.gentle) { hasAppeared = true }
        }
        .onChange(of: viewModel.ideaGalleryItems.count) { recomputeFilteredItems() }
        .onChange(of: searchQuery) { recomputeFilteredItems() }
        .onChange(of: ideaStatusFilter) { recomputeFilteredItems() }
        .onChange(of: ideaFormatFilter) { recomputeFilteredItems() }
        .onChange(of: ideaSortMode) { recomputeFilteredItems() }
        .task {
            if let profiles = try? await AtomRepository.shared.fetchAll(type: .clientProfile) {
                clientProfiles = profiles
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ideaDeleted"))) { notification in
            if let uuid = notification.userInfo?["uuid"] as? String {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.ideaGalleryItems.removeAll { $0.atomUUID == uuid }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ideaActivated"))) { notification in
            if let uuid = notification.userInfo?["uuid"] as? String {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.ideaGalleryItems.removeAll { $0.atomUUID == uuid }
                }
            }
        }
    }

    // MARK: - Content View

    private var contentView: some View {
        IdeaBoardView(
            items: cachedFilteredItems,
            clientProfiles: clientProfiles,
            viewModel: viewModel,
            hasAppeared: hasAppeared
        )
    }

    // MARK: - Batch Delete

    private func batchDeleteSelectedIdeas() {
        let uuids = Array(viewModel.selectedUUIDs)
        Task {
            for uuid in uuids {
                try? await AtomRepository.shared.delete(uuid: uuid)
                NotificationCenter.default.post(
                    name: Notification.Name("ideaDeleted"),
                    object: nil,
                    userInfo: ["uuid": uuid]
                )
            }
        }
        withAnimation(ProMotionSprings.snappy) {
            viewModel.ideaGalleryItems.removeAll { uuids.contains($0.atomUUID) }
            viewModel.clearSelection()
        }
    }

    // MARK: - Filtered Items

    /// Statuses that represent activated/post-activation ideas — hidden from the library
    private static let activatedStatuses: Set<IdeaStatus> = [.inProduction, .published, .archived]

    private func recomputeFilteredItems() {
        var items = viewModel.ideaGalleryItems.filter { !Self.activatedStatuses.contains($0.status) }

        if !searchQuery.isEmpty {
            items = items.filter { Self.matchesSearch($0, query: searchQuery) }
        }

        if let statusFilter = ideaStatusFilter {
            items = items.filter { $0.status == statusFilter }
        }

        if let formatFilter = ideaFormatFilter {
            items = items.filter { $0.contentFormat == formatFilter }
        }

        switch ideaSortMode {
        case .recent:
            items.sort { $0.updatedAt > $1.updatedAt }
        case .priority:
            items.sort { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                return lhs.status.sortOrder < rhs.status.sortOrder
            }
        case .insightScore:
            items.sort { ($0.insightScore ?? 0) > ($1.insightScore ?? 0) }
        }

        cachedFilteredItems = items
    }

    // MARK: - Filter Bar (Library style)

    private var filterBar: some View {
        HStack(spacing: CommandKMetrics.toolbarSpacing) {
            // Stats (pinned left)
            statsLabel

            // Filter dropdowns
            statusMenu
            formatMenu

            filterSeparator

            sortMenu

            if hasActiveFilters {
                clearButton
            }

            Spacer()
        }
        .padding(.horizontal, CommandKMetrics.contentPadding)
        .padding(.vertical, 12)
    }

    private var filterSeparator: some View {
        Rectangle()
            .fill(DS.borderSubtle)
            .frame(width: 1, height: 22)
    }

    // MARK: - Stats Label

    private var statsLabel: some View {
        HStack(spacing: 8) {
            Text("\(viewModel.ideaGalleryItems.count)")
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundColor(DS.text)
            Text("ideas")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DS.textSecondary)

            // Compact status breakdown
            ForEach(statusBreakdown, id: \.status) { entry in
                HStack(spacing: 3) {
                    Circle()
                        .fill(entry.status.color)
                        .frame(width: 6, height: 6)
                    Text("\(entry.count)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundColor(entry.status.color)
                }
            }
        }
    }

    private var statusBreakdown: [(status: IdeaStatus, count: Int)] {
        var counts: [IdeaStatus: Int] = [:]
        for item in viewModel.ideaGalleryItems {
            counts[item.status, default: 0] += 1
        }
        return counts
            .map { (status: $0.key, count: $0.value) }
            .sorted { $0.status.sortOrder < $1.status.sortOrder }
    }

    nonisolated static func matchesSearch(_ item: IdeaGalleryItem, query: String) -> Bool {
        CommandKSearchMatcher.matches(query, inAny: [item.title, item.body, item.clientName] + item.tags.map(Optional.some))
    }

    // MARK: - Dropdown Helper

    @ViewBuilder
    private func filterDropdownLabel(_ title: String, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 10))
        }
        .foregroundColor(DS.text)
        .commandKToolbarChip(
            isActive: isActive,
            activeFill: indigo.opacity(0.12),
            activeBorder: indigo.opacity(0.18)
        )
    }

    // MARK: - Status Menu

    private var statusMenu: some View {
        Menu {
            Button {
                ideaStatusFilter = nil
            } label: {
                HStack {
                    Text("All Statuses")
                    if ideaStatusFilter == nil { Image(systemName: "checkmark") }
                }
            }
            Divider()
            ForEach(IdeaStatus.allCases, id: \.rawValue) { status in
                Button {
                    ideaStatusFilter = ideaStatusFilter == status ? nil : status
                } label: {
                    HStack {
                        Image(systemName: status.iconName)
                        Text(status.displayName)
                        if ideaStatusFilter == status {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            filterDropdownLabel(
                ideaStatusFilter?.displayName ?? "Status",
                isActive: ideaStatusFilter != nil
            )
        }
        .menuStyle(.borderlessButton)
        .tint(DS.text)
    }

    // MARK: - Format Menu

    private var formatMenu: some View {
        Menu {
            Button {
                ideaFormatFilter = nil
            } label: {
                HStack {
                    Text("All Formats")
                    if ideaFormatFilter == nil { Image(systemName: "checkmark") }
                }
            }
            Divider()
            ForEach(ContentFormat.allCases, id: \.rawValue) { format in
                Button {
                    ideaFormatFilter = ideaFormatFilter == format ? nil : format
                } label: {
                    HStack {
                        Image(systemName: format.icon)
                        Text(format.displayName)
                        if ideaFormatFilter == format {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            filterDropdownLabel(
                ideaFormatFilter?.displayName ?? "Format",
                isActive: ideaFormatFilter != nil
            )
        }
        .menuStyle(.borderlessButton)
        .tint(DS.text)
    }

    // MARK: - Sort Menu

    private var sortMenu: some View {
        Menu {
            ForEach(IdeaSortMode.allCases, id: \.self) { mode in
                Button {
                    ideaSortMode = mode
                } label: {
                    HStack {
                        Text(mode.displayName)
                        if ideaSortMode == mode {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(ideaSortMode.displayName)
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
            }
            .foregroundColor(DS.text)
            .commandKToolbarChip()
        }
        .menuStyle(.borderlessButton)
        .tint(DS.text)
    }

    // MARK: - Active Filters

    private var hasActiveFilters: Bool {
        ideaStatusFilter != nil || ideaFormatFilter != nil
    }

    private var clearButton: some View {
        Button {
            ideaStatusFilter = nil
            ideaFormatFilter = nil
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                Text("Clear")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(indigo.opacity(0.8))
            .commandKToolbarChip(
                isActive: true,
                activeFill: indigo.opacity(0.10),
                activeBorder: indigo.opacity(0.18)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "lightbulb.fill")
                .font(.system(size: 48))
                .foregroundColor(indigo.opacity(0.3))

            Text("No ideas yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(DS.textSecondary)

            Text("Start by capturing one above.")
                .font(.system(size: 14))
                .foregroundColor(DS.textMuted)

            Spacer()
        }
    }
}

// MARK: - Board View (Kanban by Client Profile)

private struct IdeaBoardView: View {

    let items: [IdeaGalleryItem]
    let clientProfiles: [Atom]
    var viewModel: CommandKViewModel?
    let hasAppeared: Bool

    @State private var dropTargetSectionId: String?
    @State private var addingIdeaInColumn: String?
    @State private var newIdeaTitle = ""
    @FocusState private var addIdeaFocused: Bool

    private let columnWidth: CGFloat = 282
    private let columnSpacing: CGFloat = 12

    // MARK: - Sections

    private var sections: [IdeaClientSection] {
        var grouped: [String: [IdeaGalleryItem]] = [:]
        var unassigned: [IdeaGalleryItem] = []

        for item in items {
            if let clientUUID = item.clientUUID {
                grouped[clientUUID, default: []].append(item)
            } else {
                unassigned.append(item)
            }
        }

        var result: [IdeaClientSection] = []

        // Client columns (alphabetical, including empty profiles)
        let sortedClients = clientProfiles.sorted { ($0.title ?? "") < ($1.title ?? "") }
        for client in sortedClients {
            result.append(IdeaClientSection(
                id: client.uuid,
                clientName: client.title ?? "Client",
                clientUUID: client.uuid,
                color: DS.clientColor(for: client.uuid),
                items: grouped[client.uuid] ?? []
            ))
        }

        // Unassigned column last
        result.append(IdeaClientSection(
            id: "__unassigned__",
            clientName: "Unassigned",
            clientUUID: nil,
            color: DS.entityIdea,
            items: unassigned
        ))

        return result
    }

    // MARK: - Body

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: columnSpacing) {
                ForEach(sections) { section in
                    boardColumn(section)
                }
            }
            .padding(.horizontal, CommandKMetrics.contentPadding)
            .padding(.vertical, 12)
            .padding(.bottom, viewModel?.isMultiSelectActive == true ? 84 : 16)
        }
    }

    // MARK: - Column

    @ViewBuilder
    private func boardColumn(_ section: IdeaClientSection) -> some View {
        let isDropTarget = dropTargetSectionId == section.id

        VStack(alignment: .leading, spacing: 0) {
            columnHeader(section)

            Divider()
                .background(section.color.opacity(0.2))

            // Cards
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(
                        Array(section.items.enumerated()),
                        id: \.element.id
                    ) { index, item in
                        IdeaBoardCard(
                            item: item,
                            columnColor: section.color,
                            viewModel: viewModel,
                            hasAppeared: hasAppeared,
                            appearDelay: Double(index) * 0.04
                        )
                        .draggable(item.atomUUID)
                    }

                    if section.items.isEmpty {
                        emptyColumnPlaceholder(section)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }

            addIdeaButton(section: section)
        }
        .frame(width: columnWidth)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                .fill(isDropTarget ? section.color.opacity(0.05) : DS.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                .stroke(
                    isDropTarget ? section.color.opacity(0.45) : DS.border,
                    lineWidth: isDropTarget ? 2 : 1
                )
        )
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        .shadow(color: .black.opacity(0.02), radius: 2, y: 1)
        .animation(ProMotionSprings.snappy, value: isDropTarget)
        .dropDestination(for: String.self) { droppedItems, _ in
            guard let ideaUUID = droppedItems.first else { return false }
            assignIdeaToClient(ideaUUID: ideaUUID, clientUUID: section.clientUUID)
            return true
        } isTargeted: { targeted in
            withAnimation(ProMotionSprings.snappy) {
                dropTargetSectionId = targeted ? section.id : nil
            }
        }
    }

    // MARK: - Column Header

    @ViewBuilder
    private func columnHeader(_ section: IdeaClientSection) -> some View {
        HStack(spacing: 8) {
            // Colored profile name badge — long-press to drag idea board to canvas
            Text(section.clientName.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(section.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(section.color.opacity(0.10))
                )
                .onLongPressGesture(minimumDuration: 0.4) {
                    // Post notification to create an idea board block on canvas
                    NotificationCenter.default.post(
                        name: Notification.Name("addIdeaBoardToCanvas"),
                        object: nil,
                        userInfo: [
                            "clientUUID": section.clientUUID ?? "",
                            "clientName": section.clientName
                        ]
                    )
                }
                .help("Long-press to add \(section.clientName)'s idea board to canvas")

            // Count badge
            Text("\(section.items.count)")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(section.color.opacity(0.8))

            Spacer()

            // Column menu (...)
            columnOptionsMenu(section)

            // Quick-add "+" button
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    addingIdeaInColumn = section.id
                    newIdeaTitle = ""
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    addIdeaFocused = true
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(section.color)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(section.color.opacity(0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(section.color.opacity(0.16), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Column Options Menu

    @ViewBuilder
    private func columnOptionsMenu(_ section: IdeaClientSection) -> some View {
        Menu {
            Button {
                NotificationCenter.default.post(
                    name: Notification.Name("addIdeaBoardToCanvas"),
                    object: nil,
                    userInfo: [
                        "clientUUID": section.clientUUID ?? "",
                        "clientName": section.clientName
                    ]
                )
            } label: {
                Label("Add to Canvas", systemImage: "square.grid.3x3.topleft.filled")
            }

            Divider()

            Button {} label: {
                Label("Sort by Recent", systemImage: "clock")
            }

            Button {} label: {
                Label("Sort by Status", systemImage: "arrow.up.arrow.down")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.textMuted)
                .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Empty Placeholder

    @ViewBuilder
    private func emptyColumnPlaceholder(_ section: IdeaClientSection) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "lightbulb")
                .font(.system(size: 20))
                .foregroundColor(section.color.opacity(0.3))
            Text("Drop ideas here")
                .font(.system(size: 12))
                .foregroundColor(DS.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Add Idea Button

    @ViewBuilder
    private func addIdeaButton(section: IdeaClientSection) -> some View {
        if addingIdeaInColumn == section.id {
            inlineAddIdeaField(section: section)
        } else {
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    addingIdeaInColumn = section.id
                    newIdeaTitle = ""
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    addIdeaFocused = true
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(section.color)
                    Text("New idea")
                        .font(.system(size: 13))
                        .foregroundColor(DS.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)
        }
    }

    private func inlineAddIdeaField(section: IdeaClientSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("", text: $newIdeaTitle,
                      prompt: Text("Idea title").foregroundColor(DS.textMuted))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(DS.text)
                .focused($addIdeaFocused)
                .onSubmit { submitNewIdea(section: section) }
                .onExitCommand {
                    withAnimation(ProMotionSprings.snappy) {
                        addingIdeaInColumn = nil
                        newIdeaTitle = ""
                    }
                }

            HStack(spacing: 8) {
                Button { submitNewIdea(section: section) } label: {
                    Text("Add idea")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.textOnAccent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(section.color, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        addingIdeaInColumn = nil
                        newIdeaTitle = ""
                    }
                } label: {
                    Text("Cancel")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(section.color.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private func submitNewIdea(section: IdeaClientSection) {
        let title = newIdeaTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        Task {
            await viewModel?.createIdeaForClient(title: title, clientUUID: section.clientUUID)
        }

        withAnimation(ProMotionSprings.snappy) {
            newIdeaTitle = ""
            addingIdeaInColumn = nil
        }
    }

    // MARK: - Client Assignment

    private func assignIdeaToClient(ideaUUID: String, clientUUID: String?) {
        Task {
            guard var atom = try? await AtomRepository.shared.fetch(uuid: ideaUUID) else { return }

            let oldClientUUID = atom.ideaMetadata?.clientUUID
            if oldClientUUID == clientUUID { return }

            // Remove old client links
            if let oldUUID = oldClientUUID {
                atom = atom.removingLinks(ofType: .ideaToClient)
                if var oldClient = try? await AtomRepository.shared.fetch(uuid: oldUUID) {
                    oldClient = oldClient.removingLink(ofType: .clientToIdea, toUUID: ideaUUID)
                    oldClient.updatedAt = ISO8601DateFormatter().string(from: Date())
                    oldClient.localVersion += 1
                    _ = try? await AtomRepository.shared.update(oldClient)
                }
            }

            // Update idea metadata
            atom = atom.withUpdatedIdeaMetadata { meta in
                meta.clientUUID = clientUUID
            }

            // Add new client links
            if let newUUID = clientUUID {
                atom = atom.addingLink(.ideaToClient(newUUID))
                if var newClient = try? await AtomRepository.shared.fetch(uuid: newUUID) {
                    newClient = newClient.addingLink(.clientToIdea(ideaUUID))
                    newClient.updatedAt = ISO8601DateFormatter().string(from: Date())
                    newClient.localVersion += 1
                    _ = try? await AtomRepository.shared.update(newClient)
                }
            }

            atom.updatedAt = ISO8601DateFormatter().string(from: Date())
            atom.localVersion += 1
            _ = try? await AtomRepository.shared.update(atom)

            await viewModel?.loadIdeaGallery(forceReload: true)
        }
    }
}

// MARK: - Board Card (Compact)

private struct IdeaBoardCard: View {

    let item: IdeaGalleryItem
    let columnColor: Color
    var viewModel: CommandKViewModel?
    let hasAppeared: Bool
    let appearDelay: Double

    @State private var isHovered = false
    @State private var showDeleteAlert = false

    private var isSelected: Bool {
        viewModel?.selectedUUIDs.contains(item.atomUUID) ?? false
    }

    var body: some View {
        HStack(spacing: 10) {
            // Format icon
            formatIcon

            // Content
            VStack(alignment: .leading, spacing: 2) {
                if let format = item.contentFormat {
                    Text(format.displayName.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(columnColor.opacity(0.7))
                        .tracking(0.3)
                }

                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.text)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            // Status dot
            Circle()
                .fill(item.status.color)
                .frame(width: 7, height: 7)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    isSelected ? columnColor.opacity(0.12) :
                    isHovered ? columnColor.opacity(0.06) :
                    DS.surfaceElevated
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isSelected ? columnColor.opacity(0.5) :
                    isHovered ? columnColor.opacity(0.25) :
                    DS.borderSubtle,
                    lineWidth: 1
                )
        )
        .shadow(
            color: isHovered ? columnColor.opacity(0.1) : .clear,
            radius: isHovered ? 6 : 0,
            y: isHovered ? 2 : 0
        )
        .opacity(hasAppeared ? 1.0 : 0.0)
        .offset(y: hasAppeared ? 0 : 12)
        .animation(
            ProMotionSprings.snappy.delay(appearDelay),
            value: hasAppeared
        )
        .animation(ProMotionSprings.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
        .onTapGesture { handleTap() }
        .contextMenu { boardCardContextMenu }
        .alert("Delete Idea?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteIdea() }
        } message: {
            Text("This will permanently remove this idea.")
        }
    }

    // MARK: - Format Icon

    @ViewBuilder
    private var formatIcon: some View {
        let iconName = item.contentFormat?.icon ?? "lightbulb"
        Image(systemName: iconName)
            .font(.system(size: 14))
            .foregroundColor(columnColor.opacity(0.7))
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(columnColor.opacity(0.08))
            )
    }

    // MARK: - Tap Handler

    private func handleTap() {
        if NSEvent.modifierFlags.contains(.shift) {
            withAnimation(ProMotionSprings.snappy) {
                viewModel?.toggleSelection(item.atomUUID)
            }
        } else if viewModel?.isMultiSelectActive == true {
            withAnimation(ProMotionSprings.snappy) {
                viewModel?.clearSelection()
            }
        } else {
            NotificationCenter.default.post(
                name: .enterFocusMode,
                object: nil,
                userInfo: ["type": EntityType.idea, "id": item.entityId, "commandKTab": "ideas"]
            )
            NotificationCenter.default.post(
                name: CosmoNotification.NodeGraph.hideCommandK,
                object: nil
            )
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var boardCardContextMenu: some View {
        Button {
            NotificationCenter.default.post(
                name: .enterFocusMode,
                object: nil,
                userInfo: ["type": EntityType.idea, "id": item.entityId, "commandKTab": "ideas"]
            )
            NotificationCenter.default.post(
                name: CosmoNotification.NodeGraph.hideCommandK,
                object: nil
            )
        } label: {
            Label("Open", systemImage: "arrow.up.left.and.arrow.down.right")
        }

        Button {
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openAsPane, object: nil,
                userInfo: ["type": EntityType.idea, "id": item.entityId]
            )
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
        } label: {
            Label("Open as Pane", systemImage: "rectangle.split.2x1")
        }

        Button {
            NotificationCenter.default.post(
                name: Notification.Name("addIdeaToCanvas"),
                object: nil,
                userInfo: ["atomUUID": item.atomUUID]
            )
        } label: {
            Label("Add to Canvas", systemImage: "plus.rectangle.on.rectangle")
        }

        Divider()

        Menu("Change Status") {
            ForEach(IdeaStatus.allCases, id: \.rawValue) { status in
                Button {
                    changeStatus(to: status)
                } label: {
                    Label(status.displayName, systemImage: status.iconName)
                }
                .disabled(item.status == status)
            }
        }

        Divider()

        Button(role: .destructive) {
            showDeleteAlert = true
        } label: {
            Label("Delete Idea", systemImage: "trash")
        }
    }

    // MARK: - Actions

    private func changeStatus(to newStatus: IdeaStatus) {
        Task {
            _ = try? await AtomRepository.shared.update(uuid: item.atomUUID) { atom in
                atom = atom.withUpdatedIdeaMetadata { meta in
                    meta.ideaStatus = newStatus
                    meta.statusChangedAt = ISO8601DateFormatter().string(from: Date())
                }
            }
        }
    }

    private func deleteIdea() {
        Task {
            try? await AtomRepository.shared.delete(uuid: item.atomUUID)
            NotificationCenter.default.post(
                name: Notification.Name("ideaDeleted"),
                object: nil,
                userInfo: ["uuid": item.atomUUID]
            )
        }
    }
}

// MARK: - Preview

#Preview("Ideas Tab") {
    IdeasTab(viewModel: CommandKViewModel(), searchQuery: "")
        .frame(width: 900, height: 600)
}
