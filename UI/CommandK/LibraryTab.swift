// CosmoOS/UI/CommandK/LibraryTab.swift
// Library tab for Command-K overlay — Eden-style card grid integrated with semantic search
// Shows all atoms as browsable cards, smart collections, and folder navigation

import SwiftUI

// MARK: - LibraryTab

struct LibraryTab: View {

    @ObservedObject var viewModel: CommandKViewModel
    let searchQuery: String
    @StateObject private var libraryViewModel = LibraryViewModel()
    @State private var viewMode: LibraryViewMode = .grid
    @State private var sortMode: LibrarySortMode = .dateAdded
    @State private var typeFilter: AtomType? = nil
    @State private var clientFilter: String? = nil
    @State private var clientProfiles: [Atom] = []
    @State private var clientLinkedUUIDs: Set<String> = []
    @State private var showResearchURLInput = false
    @State private var researchURLText = ""
    @StateObject private var incubationEngine = IncubationEngine.shared

    // MARK: - Filtered Items (Search-Library Bridge)

    private var filteredItems: [LibraryItem] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        var items: [LibraryItem]
        if trimmed.isEmpty {
            items = libraryViewModel.displayItems
        } else {
            // Local text filtering — reliable for all queries
            items = libraryViewModel.allItems.filter {
                $0.title.localizedCaseInsensitiveContains(trimmed) ||
                ($0.preview?.localizedCaseInsensitiveContains(trimmed) ?? false) ||
                $0.typeName.localizedCaseInsensitiveContains(trimmed)
            }
        }
        if let typeFilter {
            items = items.filter { $0.atomType == typeFilter }
        }
        if clientFilter != nil {
            items = items.filter { clientLinkedUUIDs.contains($0.uuid) }
        }
        return items
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Toolbar row (sort + view toggle + recently deleted + type filter)
                toolbarRow

                Divider().background(DS.borderActive)

                // Breadcrumbs (when inside a folder)
                if !libraryViewModel.showingRecentlyDeleted && libraryViewModel.breadcrumbs.count > 1 {
                    breadcrumbBar
                }


                // Due for Review (incubation queue)
                if !incubationEngine.dueAtoms.isEmpty
                    && !libraryViewModel.showingRecentlyDeleted
                    && searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                    dueForReviewRow
                }

                // Main content
                if libraryViewModel.showingRecentlyDeleted {
                    recentlyDeletedView
                } else if libraryViewModel.isLoading {
                    loadingView
                } else if filteredItems.isEmpty {
                    emptyState
                        .contentShape(Rectangle())
                        .contextMenu { backgroundContextMenu }
                } else {
                    ZStack {
                        // Transparent background to catch right-clicks on empty space
                        Color.clear
                            .contentShape(Rectangle())
                            .contextMenu { backgroundContextMenu }

                        switch viewMode {
                        case .grid:
                            LibraryGridView(
                                items: filteredItems,
                                onItemTap: { handleItemTap($0) },
                                onItemDoubleTap: { handleItemDoubleTap($0) },
                                onItemDelete: { libraryViewModel.softDeleteItem(uuid: $0.uuid) },
                                selectedUUIDs: viewModel.selectedUUIDs,
                                onToggleSelection: { uuid in
                                    withAnimation(ProMotionSprings.snappy) {
                                        viewModel.toggleSelection(uuid)
                                    }
                                }
                            )
                        case .list:
                            libraryListView
                        }
                    }
                }
            }

            // Floating selection bar
            if viewModel.isMultiSelectActive {
                VStack {
                    Spacer()
                    SelectionBar(viewModel: viewModel, accentColor: DS.accent) {
                        batchDeleteLibraryItems()
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(DS.bg)
        .animation(ProMotionSprings.snappy, value: viewModel.isMultiSelectActive)
        .task {
            await libraryViewModel.loadLibrary()
            // Load client profiles for filter
            if let profiles = try? await AtomRepository.shared.fetchAll(type: .clientProfile) {
                clientProfiles = profiles
            }
        }
        .onChange(of: sortMode) { newSort in
            libraryViewModel.applySortMode(newSort)
        }
        .onChange(of: clientFilter) { _, newClient in
            Task {
                if let clientUUID = newClient {
                    var linked: Set<String> = []
                    for item in libraryViewModel.allItems {
                        if let atom = try? await AtomRepository.shared.fetch(uuid: item.uuid) {
                            if atom.linksList.contains(where: { $0.uuid == clientUUID }) {
                                linked.insert(item.uuid)
                            }
                        }
                    }
                    clientLinkedUUIDs = linked
                } else {
                    clientLinkedUUIDs = []
                }
            }
        }
        .overlay {
            if showResearchURLInput {
                researchURLOverlay
            }
        }
    }

    // MARK: - Toolbar Row

    private var toolbarRow: some View {
        HStack(spacing: 12) {
            Spacer()

            // View toggle
            HStack(spacing: 4) {
                ForEach(LibraryViewMode.allCases, id: \.rawValue) { mode in
                    viewModeButton(mode)
                }
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(DS.surfaceElevated)
            )

            // Recently Deleted button
            recentlyDeletedButton

            // Sort dropdown
            sortDropdown

            // Type filter dropdown
            typeFilterMenu

            // Client profile filter
            if !clientProfiles.isEmpty {
                clientProfileFilterMenu
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func viewModeButton(_ mode: LibraryViewMode) -> some View {
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
                        .fill(viewMode == mode ? DS.surfaceHover : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    private var recentlyDeletedButton: some View {
        Button {
            withAnimation(ProMotionSprings.snappy) {
                libraryViewModel.showingRecentlyDeleted.toggle()
                if libraryViewModel.showingRecentlyDeleted {
                    Task {
                        await libraryViewModel.loadRecentlyDeleted()
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                Text("Recently Deleted")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(libraryViewModel.showingRecentlyDeleted ? Color(hex: "#EF4444") : DS.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(libraryViewModel.showingRecentlyDeleted ? Color(hex: "#EF4444").opacity(0.15) : DS.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                libraryViewModel.showingRecentlyDeleted ? Color(hex: "#EF4444").opacity(0.3) : Color.clear,
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var sortDropdown: some View {
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
            .foregroundColor(DS.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(DS.surfaceHover)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(DS.borderSubtle, lineWidth: 1)
                    )
            )
        }
    }

    private var typeFilterMenu: some View {
        Menu {
            Button {
                typeFilter = nil
            } label: {
                HStack {
                    Text("All Types")
                    if typeFilter == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Divider()

            Button {
                typeFilter = .content
            } label: {
                HStack {
                    Label("Content", systemImage: "doc.text.fill")
                    if typeFilter == .content {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Button {
                typeFilter = .connection
            } label: {
                HStack {
                    Label("Connection", systemImage: "link.circle.fill")
                    if typeFilter == .connection {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Button {
                typeFilter = .research
            } label: {
                HStack {
                    Label("Research", systemImage: "book.fill")
                    if typeFilter == .research {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 11))
                Text(typeFilter?.displayName ?? "All Types")
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
            }
            .foregroundColor(typeFilter != nil ? DS.accent : DS.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(typeFilter != nil ? DS.accent.opacity(0.12) : DS.surfaceHover)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                typeFilter != nil ? DS.accent.opacity(0.3) : DS.borderSubtle,
                                lineWidth: 1
                            )
                    )
            )
        }
        .tint(DS.text)
    }

    // MARK: - Background Context Menu

    @ViewBuilder
    private var backgroundContextMenu: some View {
        Button {
            libraryViewModel.createAtom(type: .content)
        } label: {
            Label("New Content", systemImage: "doc.text.fill")
        }

        Button {
            libraryViewModel.createAtom(type: .connection)
        } label: {
            Label("New Connection", systemImage: "link.circle.fill")
        }

        Button {
            showResearchURLInput = true
        } label: {
            Label("New Research", systemImage: "book.fill")
        }
    }

    // MARK: - Research URL Overlay

    private var researchURLOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    showResearchURLInput = false
                    researchURLText = ""
                }

            VStack(spacing: 16) {
                HStack {
                    Text("New Research")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(DS.text)
                    Spacer()
                    Button {
                        showResearchURLInput = false
                        researchURLText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(DS.textMuted)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.system(size: 13))
                        .foregroundColor(DS.textMuted)

                    TextField("Paste URL...", text: $researchURLText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundColor(DS.text)
                        .onSubmit { createResearchFromURL() }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(DS.bg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(DS.borderActive, lineWidth: 1)
                        )
                )

                HStack {
                    Spacer()

                    Button {
                        showResearchURLInput = false
                        researchURLText = ""
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(DS.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(DS.border)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        createResearchFromURL()
                    } label: {
                        Text("Create")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(researchURLText.trimmingCharacters(in: .whitespaces).isEmpty ? DS.accent.opacity(0.4) : DS.accent)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(researchURLText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 420)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(DS.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(DS.border, lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        }
    }

    private func createResearchFromURL() {
        let url = researchURLText.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { return }

        showResearchURLInput = false
        researchURLText = ""
        libraryViewModel.createResearch(url: url)
    }

    // MARK: - Breadcrumbs

    private var breadcrumbBar: some View {
        HStack(spacing: 4) {
            ForEach(Array(libraryViewModel.breadcrumbs.enumerated()), id: \.element.id) { index, crumb in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .foregroundColor(DS.textMuted)
                }

                Button {
                    libraryViewModel.navigateToBreadcrumb(crumb)
                } label: {
                    Text(crumb.title)
                        .font(.system(size: 13, weight: index == libraryViewModel.breadcrumbs.count - 1 ? .semibold : .regular))
                        .foregroundColor(index == libraryViewModel.breadcrumbs.count - 1 ? DS.text : DS.textSecondary)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(DS.surfaceElevated)
    }

    // MARK: - Client Profile Filter

    private var clientProfileFilterMenu: some View {
        Menu {
            Button {
                clientFilter = nil
            } label: {
                HStack {
                    Text("All Clients")
                    if clientFilter == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Divider()

            ForEach(clientProfiles, id: \.uuid) { client in
                Button {
                    clientFilter = client.uuid
                } label: {
                    HStack {
                        Text(client.title ?? "Client")
                        if clientFilter == client.uuid {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.fill")
                    .font(.system(size: 11))
                Text(clientFilterLabel)
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
            }
            .foregroundColor(clientFilter != nil ? DS.accent : DS.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(clientFilter != nil ? DS.accent.opacity(0.12) : DS.surfaceHover)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                clientFilter != nil ? DS.accent.opacity(0.3) : DS.borderSubtle,
                                lineWidth: 1
                            )
                    )
            )
        }
        .tint(DS.text)
    }

    private var clientFilterLabel: String {
        if let uuid = clientFilter,
           let client = clientProfiles.first(where: { $0.uuid == uuid }) {
            return client.title ?? "Client"
        }
        return "Client"
    }

    // MARK: - List View

    private var libraryListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredItems) { item in
                    libraryListRow(item)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private func libraryListRow(_ item: LibraryItem) -> some View {
        let isRowSelected = viewModel.selectedUUIDs.contains(item.uuid)

        HStack(spacing: 12) {
            if isRowSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(DS.accent)
                    .frame(width: 28)
            } else {
                Image(systemName: item.icon)
                    .font(.system(size: 14))
                    .foregroundColor(item.color)
                    .frame(width: 28)
            }

            Text(item.title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(DS.text)
                .lineLimit(1)

            Spacer()

            Text(item.typeName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(item.color.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(item.color.opacity(0.1))
                .clipShape(Capsule())

            Text(item.relativeDate)
                .font(.system(size: 12))
                .foregroundColor(DS.textMuted)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isRowSelected ? DS.accent.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { handleItemDoubleTap(item) }
        .onTapGesture { handleItemTap(item) }
        .contextMenu { libraryListRowContextMenu(item) }

        Divider().background(DS.border)
    }

    @ViewBuilder
    private func libraryListRowContextMenu(_ item: LibraryItem) -> some View {
        let selCount = viewModel.selectedUUIDs.count
        let isRowSelected = viewModel.selectedUUIDs.contains(item.uuid)

        if isRowSelected && selCount > 1 {
            Button(role: .destructive) {
                batchDeleteLibraryItems()
            } label: {
                Label("Delete \(selCount) Items", systemImage: "trash")
            }
        } else {
            Button {
                libraryViewModel.openInFocusMode(item)
            } label: {
                Label("Open in Focus Mode", systemImage: "arrow.up.left.and.arrow.down.right")
            }

            Button {
                if let entityType = EntityType(rawValue: item.atomType.rawValue) {
                    NotificationCenter.default.post(
                        name: CosmoNotification.Navigation.openAsPane,
                        object: nil,
                        userInfo: ["type": entityType, "id": item.entityId]
                    )
                    NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
                }
            } label: {
                Label("Open as Pane", systemImage: "rectangle.split.2x1")
            }

            Button {
                NotificationCenter.default.post(
                    name: CosmoNotification.NodeGraph.addToCanvas,
                    object: nil,
                    userInfo: ["atomUUID": item.uuid]
                )
            } label: {
                Label("Add to Canvas", systemImage: "plus.rectangle.on.rectangle")
            }

            Divider()

            Button(role: .destructive) {
                libraryViewModel.softDeleteItem(uuid: item.uuid)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Recently Deleted View

    private var recentlyDeletedView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "trash")
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "#EF4444"))
                Text("Recently Deleted")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DS.text)

                Spacer()

                Text("Items are permanently deleted after 30 days")
                    .font(.system(size: 12))
                    .foregroundColor(DS.textMuted)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            Divider().background(DS.border)

            if libraryViewModel.recentlyDeletedItems.isEmpty {
                recentlyDeletedEmptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(libraryViewModel.recentlyDeletedItems) { item in
                            recentlyDeletedRow(item)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
    }

    @ViewBuilder
    private func recentlyDeletedRow(_ item: LibraryItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .font(.system(size: 14))
                .foregroundColor(item.color.opacity(0.5))
                .frame(width: 28)

            Text(item.title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(DS.textSecondary)
                .lineLimit(1)

            Spacer()

            Text(item.typeName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(item.color.opacity(0.5))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(item.color.opacity(0.08))
                .clipShape(Capsule())

            Button {
                libraryViewModel.restoreItem(uuid: item.uuid)
            } label: {
                Text("Restore")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(DS.accent.opacity(0.15))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                libraryViewModel.permanentlyDelete(uuid: item.uuid)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "#EF4444").opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())

        Divider().background(DS.border)
    }

    private var recentlyDeletedEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "trash.slash")
                .font(.system(size: 40))
                .foregroundColor(DS.textMuted)

            Text("No recently deleted items")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(DS.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                Image(systemName: "tray")
                    .font(.system(size: 48))
                    .foregroundColor(DS.textMuted)

                Text("Your library is empty")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DS.textSecondary)

                Text("Create your first note, idea, or project to get started")
                    .font(.system(size: 13))
                    .foregroundColor(DS.textMuted)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundColor(DS.textMuted)

                Text("No results found")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DS.textSecondary)

                Text("Try a different search term")
                    .font(.system(size: 13))
                    .foregroundColor(DS.textMuted)
            }
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

    // MARK: - Item Actions

    private func handleItemTap(_ item: LibraryItem) {
        if NSEvent.modifierFlags.contains(.shift) && !item.isFolder {
            withAnimation(ProMotionSprings.snappy) {
                viewModel.toggleSelection(item.uuid)
            }
            return
        }

        if viewModel.isMultiSelectActive && !item.isFolder {
            withAnimation(ProMotionSprings.snappy) {
                viewModel.clearSelection()
            }
            return
        }

        if item.isFolder {
            libraryViewModel.navigateIntoFolder(item)
        } else {
            // Single click: add as floating block to the current canvas/focus mode
            NotificationCenter.default.post(
                name: CosmoNotification.NodeGraph.addItemToCurrentCanvas,
                object: nil,
                userInfo: ["atomUUID": item.uuid, "atomType": item.atomType.rawValue, "title": item.title]
            )
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
        }
    }

    private func handleItemDoubleTap(_ item: LibraryItem) {
        if item.isFolder {
            libraryViewModel.navigateIntoFolder(item)
        } else {
            // Double click: open in focus mode (existing behavior)
            viewModel.select(uuid: item.uuid)
            viewModel.openSelected()
        }
    }

    // MARK: - Batch Delete

    private func batchDeleteLibraryItems() {
        let uuids = Array(viewModel.selectedUUIDs)
        for uuid in uuids {
            libraryViewModel.softDeleteItem(uuid: uuid)
        }
        withAnimation(ProMotionSprings.snappy) {
            viewModel.clearSelection()
        }
    }

    // MARK: - Due for Review Row

    private var dueForReviewRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(hex: "#F59E0B"))
                Text("Due for Review")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.text)

                Text("\(incubationEngine.dueAtoms.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "#F59E0B"))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color(hex: "#F59E0B").opacity(0.15))
                    )

                Spacer()
            }
            .padding(.horizontal, 24)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(incubationEngine.dueAtoms.prefix(10), id: \.uuid) { atom in
                        dueReviewCard(for: atom)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func dueReviewCard(for atom: Atom) -> some View {
        let daysOverdue = daysOverdueForAtom(atom)

        Button {
            viewModel.select(uuid: atom.uuid)
            viewModel.openSelected()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: atom.type.iconName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "#F59E0B"))

                VStack(alignment: .leading, spacing: 2) {
                    Text(atom.title ?? "Untitled")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.text)
                        .lineLimit(1)

                    Text(daysOverdue > 0 ? "due \(daysOverdue)d ago" : "due today")
                        .font(.system(size: 10))
                        .foregroundColor(DS.textMuted)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: "#F59E0B").opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(hex: "#F59E0B").opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func daysOverdueForAtom(_ atom: Atom) -> Int {
        guard let rq = atom.reviewQueueMetadata else { return 0 }
        let formatter = ISO8601DateFormatter()
        guard let dueDate = formatter.date(from: rq.dueAt) else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: dueDate, to: Date()).day ?? 0
        return max(0, days)
    }
}

// MARK: - Preview

#Preview("Library Tab") {
    LibraryTab(viewModel: CommandKViewModel(), searchQuery: "")
        .frame(width: 900, height: 600)
}
