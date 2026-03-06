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
    @State private var ideaClientFilter: String? = nil
    @State private var clientProfiles: [Atom] = []

    private let indigo = DS.entityIdea

    var body: some View {
        ZStack {
            DS.bg

            VStack(spacing: 0) {
                // Library-style filter bar
                filterBar

                Divider().background(DS.borderActive)

                // Content area — grid or list
                if filteredItems.isEmpty {
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
            withAnimation(ProMotionSprings.gentle) { hasAppeared = true }
        }
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

    // MARK: - Content View (Grid / List)

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.ideaViewMode {
        case .grid:
            GeometryReader { geometry in
                IdeaSectionedGrid(
                    items: filteredItems,
                    clientProfiles: clientProfiles,
                    hasAppeared: hasAppeared,
                    viewModel: viewModel,
                    availableWidth: geometry.size.width - 48
                )
            }
        case .list:
            IdeaClientListView(
                items: filteredItems,
                clientProfiles: clientProfiles,
                viewModel: viewModel,
                hasAppeared: hasAppeared
            )
        }
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

    private var filteredItems: [IdeaGalleryItem] {
        // Exclude activated ideas — they live in the content pipeline now
        var items = viewModel.ideaGalleryItems.filter { !Self.activatedStatuses.contains($0.status) }

        if !searchQuery.isEmpty {
            let q = searchQuery.lowercased()
            items = items.filter { item in
                item.title.lowercased().contains(q) ||
                (item.body?.lowercased().contains(q) ?? false) ||
                (item.clientName?.lowercased().contains(q) ?? false) ||
                item.tags.contains { $0.lowercased().contains(q) }
            }
        }

        if let statusFilter = ideaStatusFilter {
            items = items.filter { $0.status == statusFilter }
        }

        if let formatFilter = ideaFormatFilter {
            items = items.filter { $0.contentFormat == formatFilter }
        }

        if let clientFilter = ideaClientFilter {
            items = items.filter { $0.clientUUID == clientFilter }
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

        return items
    }

    // MARK: - Filter Bar (Library style)

    private var filterBar: some View {
        HStack(spacing: 12) {
            // Stats (pinned left)
            statsLabel

            // Filter dropdowns
            statusMenu
            formatMenu
            if !clientProfiles.isEmpty {
                clientMenu
            }

            filterSeparator

            // View mode toggle
            viewModeToggle

            sortMenu

            if hasActiveFilters {
                clearButton
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    // MARK: - View Mode Toggle

    private var viewModeToggle: some View {
        HStack(spacing: 4) {
            ForEach(IdeaViewMode.allCases, id: \.rawValue) { mode in
                ideaViewModeButton(mode)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(DS.surfaceElevated)
        )
    }

    @ViewBuilder
    private func ideaViewModeButton(_ mode: IdeaViewMode) -> some View {
        Button {
            withAnimation(ProMotionSprings.snappy) {
                viewModel.ideaViewMode = mode
            }
        } label: {
            Image(systemName: mode.icon)
                .font(.system(size: 13))
                .foregroundColor(viewModel.ideaViewMode == mode ? DS.text : DS.textMuted)
                .frame(width: 30, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(viewModel.ideaViewMode == mode ? DS.surfaceHover : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    private var filterSeparator: some View {
        Rectangle()
            .fill(DS.borderActive)
            .frame(width: 1, height: 20)
    }

    // MARK: - Stats Label

    private var statsLabel: some View {
        HStack(spacing: 8) {
            Text("\(viewModel.ideaGalleryItems.count)")
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .foregroundColor(DS.text)
            Text("ideas")
                .font(.system(size: 12, weight: .medium))
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
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? indigo.opacity(0.15) : DS.surfaceElevated)
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

    // MARK: - Client Menu

    private var clientMenu: some View {
        Menu {
            Button {
                ideaClientFilter = nil
            } label: {
                HStack {
                    Text("All Clients")
                    if ideaClientFilter == nil { Image(systemName: "checkmark") }
                }
            }
            Divider()
            ForEach(clientProfiles, id: \.uuid) { client in
                Button {
                    ideaClientFilter = ideaClientFilter == client.uuid ? nil : client.uuid
                } label: {
                    HStack {
                        Circle()
                            .fill(DS.clientColor(for: client.uuid))
                            .frame(width: 8, height: 8)
                        Text(client.title ?? "Client")
                        if ideaClientFilter == client.uuid {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            filterDropdownLabel(
                clientFilterLabel,
                isActive: ideaClientFilter != nil
            )
        }
        .menuStyle(.borderlessButton)
        .tint(DS.text)
    }

    private var clientFilterLabel: String {
        if let uuid = ideaClientFilter,
           let client = clientProfiles.first(where: { $0.uuid == uuid }) {
            return client.title ?? "Client"
        }
        return "Client"
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
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(DS.surfaceElevated)
            )
        }
        .menuStyle(.borderlessButton)
        .tint(DS.text)
    }

    // MARK: - Active Filters

    private var hasActiveFilters: Bool {
        ideaStatusFilter != nil || ideaFormatFilter != nil || ideaClientFilter != nil
    }

    private var clearButton: some View {
        Button {
            ideaStatusFilter = nil
            ideaFormatFilter = nil
            ideaClientFilter = nil
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                Text("Clear")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(indigo.opacity(0.8))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(indigo.opacity(0.1))
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

// MARK: - Masonry Grid (Compact)

// MARK: - Sectioned Grid (grouped by client profile)

private struct IdeaSectionedGrid: View {

    let items: [IdeaGalleryItem]
    let clientProfiles: [Atom]
    let hasAppeared: Bool
    var viewModel: CommandKViewModel?
    let availableWidth: CGFloat

    private let spacing: CGFloat = 10
    private let columnWidth: CGFloat = 160

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

        let sortedClients = clientProfiles
            .filter { grouped[$0.uuid] != nil }
            .sorted { ($0.title ?? "") < ($1.title ?? "") }

        for client in sortedClients {
            result.append(IdeaClientSection(
                id: client.uuid,
                clientName: client.title ?? "Client",
                clientUUID: client.uuid,
                color: DS.clientColor(for: client.uuid),
                items: grouped[client.uuid] ?? []
            ))
        }

        if !unassigned.isEmpty {
            result.append(IdeaClientSection(
                id: "__unassigned__",
                clientName: "Unassigned",
                clientUUID: nil,
                color: DS.textMuted,
                items: unassigned
            ))
        }

        return result
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if sections.isEmpty {
                emptyState
            } else if sections.count == 1 && sections[0].clientUUID == nil {
                // Only unassigned — show flat grid without section wrapper
                sectionMasonryGrid(items: sections[0].items, sectionColor: nil)
                    .padding(.horizontal, 24)
                    .padding(.bottom, viewModel?.isMultiSelectActive == true ? 84 : 24)
                    .padding(.top, 8)
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(sections) { section in
                        clientSectionContainer(section)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, viewModel?.isMultiSelectActive == true ? 84 : 24)
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Section Container

    @ViewBuilder
    private func clientSectionContainer(_ section: IdeaClientSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            sectionHeader(section)

            // Cards grid
            if !section.items.isEmpty {
                sectionMasonryGrid(
                    items: section.items,
                    sectionColor: section.clientUUID != nil ? section.color : nil
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .padding(.top, 4)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(section.clientUUID != nil ? section.color.opacity(0.04) : DS.surface.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    section.clientUUID != nil ? section.color.opacity(0.12) : DS.borderSubtle,
                    lineWidth: 1
                )
        )
    }

    @ViewBuilder
    private func sectionHeader(_ section: IdeaClientSection) -> some View {
        HStack(spacing: 8) {
            // Colored accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(section.color)
                .frame(width: 4, height: 18)

            Text(section.clientName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.text)

            Text("\(section.items.count)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundColor(section.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(section.color.opacity(0.12)))

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Masonry Grid (per section)

    @ViewBuilder
    private func sectionMasonryGrid(items: [IdeaGalleryItem], sectionColor: Color?) -> some View {
        let colCount = max(3, Int(availableWidth / (columnWidth + spacing)))

        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<colCount, id: \.self) { columnIndex in
                LazyVStack(spacing: spacing) {
                    ForEach(Array(columnItems(for: columnIndex, items: items, columnCount: colCount).enumerated()), id: \.element.id) { itemIndex, item in
                        IdeaGalleryCard(
                            item: item,
                            cardWidth: columnWidth,
                            appearDelay: Double(columnIndex + itemIndex * colCount) * 0.04,
                            hasAppeared: hasAppeared,
                            viewModel: viewModel,
                            sectionColor: sectionColor
                        )
                    }
                }
                .frame(width: columnWidth)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func columnItems(for column: Int, items: [IdeaGalleryItem], columnCount: Int) -> [IdeaGalleryItem] {
        var columnHeights = Array(repeating: CGFloat(0), count: columnCount)
        var columns: [[IdeaGalleryItem]] = Array(repeating: [], count: columnCount)

        for item in items {
            let shortestColumn = columnHeights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            columns[shortestColumn].append(item)
            columnHeights[shortestColumn] += IdeaGalleryCard.estimatedHeight(for: item, width: columnWidth) + spacing
        }

        guard column < columnCount else { return [] }
        return columns[column]
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "lightbulb")
                .font(.system(size: 32))
                .foregroundColor(DS.textMuted)
            Text("No ideas yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(DS.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 80)
    }
}

// MARK: - IdeaGalleryCard (Compact)

private struct IdeaGalleryCard: View {

    let item: IdeaGalleryItem
    let cardWidth: CGFloat
    let appearDelay: Double
    let hasAppeared: Bool
    var viewModel: CommandKViewModel?
    var sectionColor: Color? = nil

    @State private var isHovered = false
    @State private var isPressed = false
    @State private var showDeleteAlert = false

    private let indigo = DS.entityIdea

    private var cardFill: Color {
        sectionColor?.opacity(0.06) ?? DS.surfaceElevated
    }

    private var cardBorder: Color {
        if isHovered {
            return sectionColor?.opacity(0.35) ?? indigo.opacity(0.4)
        }
        return sectionColor?.opacity(0.15) ?? DS.borderActive
    }

    private var cardShadowColor: Color {
        if isHovered {
            return sectionColor?.opacity(0.15) ?? indigo.opacity(0.15)
        }
        return .clear
    }

    private var isSelected: Bool {
        viewModel?.selectedUUIDs.contains(item.atomUUID) ?? false
    }

    static func estimatedHeight(for item: IdeaGalleryItem, width: CGFloat) -> CGFloat {
        let padding: CGFloat = 16
        let statusRow: CGFloat = 20
        let spacing: CGFloat = 6
        let titleLines = min(ceil(CGFloat(item.title.count) / 18.0), 3)
        let titleHeight = titleLines * 16

        var bodyHeight: CGFloat = 0
        if let body = item.body, !body.isEmpty {
            let bodyLength = body.count
            let maxLines: CGFloat = bodyLength > 150 ? 5 : (bodyLength > 80 ? 4 : 3)
            let lineCount = min(ceil(CGFloat(bodyLength) / 22.0), maxLines)
            bodyHeight = lineCount * 13 + spacing
        }

        let formatRow: CGFloat = (item.contentFormat != nil || item.platform != nil) ? 16 + spacing : 0
        let clientRow: CGFloat = item.clientName != nil ? 20 + spacing : 0

        var tagHeight: CGFloat = 0
        if !item.tags.isEmpty {
            tagHeight = 20 + spacing
        }

        let bottomRow: CGFloat = 26

        return padding + statusRow + spacing + titleHeight + bodyHeight + formatRow + clientRow + tagHeight + spacing + bottomRow
    }

    private var bodyLineLimit: Int {
        guard let body = item.body else { return 3 }
        let length = body.count
        if length > 150 { return 5 }
        if length > 80 { return 4 }
        return 3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top row: status badge + pin indicator + analysis dot
            topRow

            // Title
            Text(item.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DS.text)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Body preview
            if let body = item.body, !body.isEmpty {
                Text(body)
                    .font(.system(size: 10))
                    .foregroundColor(DS.textSecondary)
                    .lineLimit(bodyLineLimit)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Tags
            if !item.tags.isEmpty {
                tagsRow
            }

            Spacer(minLength: 2)

            // Format + platform icons row
            formatPlatformRow

            // Client tag pill (only when not inside a client section)
            if sectionColor == nil, let clientName = item.clientName {
                clientPill(clientName)
            }

            // Bottom row: framework suggestion + matching swipes + insight ring
            bottomMetadataRow

            // Hover quick-action bar
            if isHovered {
                hoverActionBar
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(8)
        .frame(width: cardWidth)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(cardBorder, lineWidth: 1)
        )
        .cardSelectionOverlay(isSelected: isSelected, accentColor: sectionColor ?? indigo)
        .shadow(
            color: cardShadowColor,
            radius: isHovered ? 10 : 0,
            y: isHovered ? 3 : 0
        )
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .opacity(hasAppeared ? 1.0 : 0.0)
        .offset(y: hasAppeared ? 0 : 20)
        .animation(
            ProMotionSprings.snappy.delay(appearDelay),
            value: hasAppeared
        )
        .animation(ProMotionSprings.hover, value: isHovered)
        .animation(ProMotionSprings.press, value: isPressed)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
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
                    name: CosmoNotification.NodeGraph.closeCommandK,
                    object: nil
                )
            }
        }
        .onLongPressGesture(minimumDuration: 0.5, pressing: { pressing in
            isPressed = pressing
        }) {
            NotificationCenter.default.post(
                name: Notification.Name("addIdeaToCanvas"),
                object: nil,
                userInfo: ["atomUUID": item.atomUUID]
            )
        }
        .onDrag {
            NSItemProvider(object: item.atomUUID as NSString)
        }
        .contextMenu { ideaCardContextMenu }
        .alert(ideaDeleteAlertTitle, isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                batchDeleteIdeas()
            }
        } message: {
            Text(ideaDeleteAlertMessage)
        }
    }

    // MARK: - Top Row (extracted for type-checker)

    @ViewBuilder
    private var topRow: some View {
        HStack(spacing: 6) {
            statusBadge

            Spacer()

            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8))
                    .foregroundColor(indigo.opacity(0.7))
                    .rotationEffect(.degrees(-45))
            }

            analysisDot
        }
    }

    // MARK: - Tags Row

    private var tagsRow: some View {
        let visibleTags = Array(item.tags.prefix(3))
        return HStack(spacing: 3) {
            ForEach(visibleTags, id: \.self) { tag in
                Text("#\(tag)")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(indigo.opacity(0.7))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(indigo.opacity(0.1))
                    )
                    .lineLimit(1)
            }
            if item.tags.count > 3 {
                Text("+\(item.tags.count - 3)")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundColor(DS.textMuted)
            }
        }
    }

    // MARK: - Bottom Metadata Row

    @ViewBuilder
    private var bottomMetadataRow: some View {
        HStack(spacing: 5) {
            if let framework = item.suggestedFramework {
                frameworkPill(framework)
            }

            if let swipeCount = item.matchingSwipeCount, swipeCount > 0 {
                swipeCountBadge(swipeCount)
            }

            contentCountBadgeView

            Spacer(minLength: 2)

            if let score = item.insightScore {
                insightScoreRing(score)
            }
        }
    }

    @ViewBuilder
    private var contentCountBadgeView: some View {
        if item.contentCount > 0 {
            HStack(spacing: 2) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 7))
                Text("\(item.contentCount)")
                    .font(.system(size: 8, weight: .medium))
            }
            .foregroundColor(.blue)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.blue.opacity(0.2))
            )
        }
    }

    // MARK: - Status Badge

    private var statusBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: item.status.iconName)
                .font(.system(size: 7))
            Text(item.status.displayName)
                .font(.system(size: 8, weight: .medium))
        }
        .foregroundColor(item.status.color)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(item.status.color.opacity(0.2))
        )
    }

    // MARK: - Format + Platform Row

    @ViewBuilder
    private var formatPlatformRow: some View {
        HStack(spacing: 5) {
            if let format = item.contentFormat {
                HStack(spacing: 2) {
                    Image(systemName: format.icon)
                        .font(.system(size: 8))
                    Text(format.displayName)
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(format.color.opacity(0.8))
            }

            if item.contentFormat != nil && item.platform != nil {
                Text("\u{00B7}")
                    .font(.system(size: 9))
                    .foregroundColor(DS.textMuted)
            }

            if let platform = item.platform {
                HStack(spacing: 2) {
                    Image(systemName: platform.iconName)
                        .font(.system(size: 8))
                    Text(platform.displayName)
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(platform.color.opacity(0.8))
            }
        }
    }

    // MARK: - Client Pill

    private func clientPill(_ name: String) -> some View {
        let color = item.clientUUID.map { DS.clientColor(for: $0) } ?? DS.textSecondary
        return HStack(spacing: 2) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(name)
                .font(.system(size: 8, weight: .medium))
        }
        .foregroundColor(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
                .overlay(
                    Capsule()
                        .strokeBorder(color.opacity(0.3), lineWidth: 0.5)
                )
        )
        .lineLimit(1)
    }

    // MARK: - Framework Pill

    private func frameworkPill(_ framework: SwipeFrameworkType) -> some View {
        Text(framework.abbreviation)
            .font(.system(size: 7, weight: .bold))
            .foregroundColor(framework.color)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(framework.color.opacity(0.2))
            )
    }

    // MARK: - Swipe Count Badge

    private func swipeCountBadge(_ count: Int) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 6))
            Text("\(count)")
                .font(.system(size: 8, weight: .medium).monospacedDigit())
        }
        .foregroundColor(DS.entitySwipe.opacity(0.8))
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(DS.entitySwipe.opacity(0.12))
        )
    }

    // MARK: - Insight Score Ring

    private func insightScoreRing(_ score: Double) -> some View {
        ZStack {
            Circle()
                .strokeBorder(DS.borderActive, lineWidth: 2)
                .frame(width: 22, height: 22)

            Circle()
                .trim(from: 0, to: CGFloat(min(score, 1.0)))
                .stroke(
                    AngularGradient(
                        colors: [indigo.opacity(0.6), indigo],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .frame(width: 22, height: 22)
                .rotationEffect(.degrees(-90))

            Text(String(format: "%.0f", score * 100))
                .font(.system(size: 7, weight: .bold).monospacedDigit())
                .foregroundColor(indigo)
        }
    }

    // MARK: - Analysis Status Dot

    private var analysisDot: some View {
        Circle()
            .fill(analysisDotColor)
            .frame(width: 7, height: 7)
    }

    private var analysisDotColor: Color {
        if item.contentCount > 0 {
            return DS.entityIdea
        } else if item.insightScore != nil {
            return DS.green
        } else {
            return DS.textMuted
        }
    }

    // MARK: - Hover Quick-Action Bar

    private var hoverActionBar: some View {
        HStack(spacing: 6) {
            Button {
                viewModel?.quickAnalyzeIdea(item)
            } label: {
                analyzeButtonLabel()
            }
            .buttonStyle(.plain)

            Button {
                NotificationCenter.default.post(
                    name: .enterFocusMode,
                    object: nil,
                    userInfo: ["type": EntityType.idea, "id": item.entityId, "commandKTab": "ideas"]
                )
                NotificationCenter.default.post(
                    name: CosmoNotification.NodeGraph.closeCommandK,
                    object: nil
                )
            } label: {
                activateButtonLabel()
            }
            .buttonStyle(.plain)

            Button {
                changeStatus(to: .archived)
            } label: {
                archiveButtonLabel()
            }
            .buttonStyle(.plain)

            Button {
                showDeleteAlert = true
            } label: {
                deleteButtonLabel()
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func analyzeButtonLabel() -> some View {
        Image(systemName: "sparkles")
            .font(.system(size: 10))
            .foregroundColor(indigo)
            .frame(width: 24, height: 20)
            .background(indigo.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private func activateButtonLabel() -> some View {
        Image(systemName: "arrow.up.forward")
            .font(.system(size: 10))
            .foregroundColor(DS.textSecondary)
            .frame(width: 24, height: 20)
            .background(DS.border, in: RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private func archiveButtonLabel() -> some View {
        Image(systemName: "archivebox")
            .font(.system(size: 10))
            .foregroundColor(DS.textSecondary)
            .frame(width: 24, height: 20)
            .background(DS.border, in: RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private func deleteButtonLabel() -> some View {
        Image(systemName: "trash")
            .font(.system(size: 10))
            .foregroundColor(.red.opacity(0.7))
            .frame(width: 24, height: 20)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Selection-Aware Context Menu

    @ViewBuilder
    private var ideaCardContextMenu: some View {
        let selCount = viewModel?.selectedUUIDs.count ?? 0

        if isSelected && selCount > 1 {
            Button(role: .destructive) {
                showDeleteAlert = true
            } label: {
                Label("Delete \(selCount) Ideas", systemImage: "trash")
            }
        } else {
            Button {
                NotificationCenter.default.post(
                    name: .enterFocusMode,
                    object: nil,
                    userInfo: ["type": EntityType.idea, "id": item.entityId, "commandKTab": "ideas"]
                )
                NotificationCenter.default.post(
                    name: CosmoNotification.NodeGraph.closeCommandK,
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
    }

    private var ideaDeleteAlertTitle: String {
        let selCount = viewModel?.selectedUUIDs.count ?? 0
        if isSelected && selCount > 1 {
            return "Delete \(selCount) Ideas?"
        }
        return "Delete Idea?"
    }

    private var ideaDeleteAlertMessage: String {
        let selCount = viewModel?.selectedUUIDs.count ?? 0
        if isSelected && selCount > 1 {
            return "This will permanently remove \(selCount) ideas."
        }
        return "This will permanently remove this idea."
    }

    private func batchDeleteIdeas() {
        let uuidsToDelete: [String]
        if isSelected, let vm = viewModel, vm.selectedUUIDs.count > 1 {
            uuidsToDelete = Array(vm.selectedUUIDs)
        } else {
            uuidsToDelete = [item.atomUUID]
        }

        Task {
            for uuid in uuidsToDelete {
                try? await AtomRepository.shared.delete(uuid: uuid)
                NotificationCenter.default.post(
                    name: Notification.Name("ideaDeleted"),
                    object: nil,
                    userInfo: ["uuid": uuid]
                )
            }
        }

        withAnimation(ProMotionSprings.snappy) {
            viewModel?.clearSelection()
        }
    }

    // MARK: - Status Change

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
}

// MARK: - Client-Grouped List View

private struct IdeaClientListView: View {

    let items: [IdeaGalleryItem]
    let clientProfiles: [Atom]
    var viewModel: CommandKViewModel?
    let hasAppeared: Bool

    @State private var expandedSections: Set<String> = []
    @State private var dropTargetSectionId: String? = nil
    @State private var sectionsInitialized = false

    private let indigo = DS.entityIdea

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

        // Client sections sorted alphabetically
        let sortedClients = clientProfiles
            .filter { grouped[$0.uuid] != nil }
            .sorted { ($0.title ?? "") < ($1.title ?? "") }

        for client in sortedClients {
            result.append(IdeaClientSection(
                id: client.uuid,
                clientName: client.title ?? "Client",
                clientUUID: client.uuid,
                color: DS.clientColor(for: client.uuid),
                items: grouped[client.uuid] ?? []
            ))
        }

        // Also include client sections that exist in profiles but have no items currently
        // (so users can drop into them)
        let existingClientIDs = Set(result.map(\.id))
        for client in clientProfiles.sorted(by: { ($0.title ?? "") < ($1.title ?? "") }) {
            if !existingClientIDs.contains(client.uuid) {
                result.append(IdeaClientSection(
                    id: client.uuid,
                    clientName: client.title ?? "Client",
                    clientUUID: client.uuid,
                    color: DS.clientColor(for: client.uuid),
                    items: []
                ))
            }
        }

        // Unassigned section last
        result.append(IdeaClientSection(
            id: "__unassigned__",
            clientName: "Unassigned",
            clientUUID: nil,
            color: DS.textMuted,
            items: unassigned
        ))

        return result
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(sections) { section in
                    Section {
                        if expandedSections.contains(section.id) {
                            sectionContent(section)
                        }
                    } header: {
                        sectionHeader(section)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, viewModel?.isMultiSelectActive == true ? 84 : 24)
            .padding(.top, 8)
        }
        .onAppear {
            if !sectionsInitialized {
                expandedSections = Set(sections.map(\.id))
                sectionsInitialized = true
            }
        }
    }

    // MARK: - Section Header

    @ViewBuilder
    private func sectionHeader(_ section: IdeaClientSection) -> some View {
        let isExpanded = expandedSections.contains(section.id)
        let isDropTarget = dropTargetSectionId == section.id

        Button {
            withAnimation(ProMotionSprings.snappy) {
                if isExpanded {
                    expandedSections.remove(section.id)
                } else {
                    expandedSections.insert(section.id)
                }
            }
        } label: {
            sectionHeaderLabel(section: section, isExpanded: isExpanded)
        }
        .buttonStyle(.plain)
        .background(DS.bg)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isDropTarget ? section.color.opacity(0.6) : Color.clear, lineWidth: 2)
        )
        .onDrop(of: [.text], delegate: ClientSectionDropDelegate(
            targetClientUUID: section.clientUUID,
            sectionId: section.id,
            dropTargetSectionId: $dropTargetSectionId,
            onAssignToClient: { ideaUUID in
                assignIdeaToClient(ideaUUID: ideaUUID, clientUUID: section.clientUUID)
            }
        ))
        .animation(ProMotionSprings.snappy, value: isDropTarget)
    }

    @ViewBuilder
    private func sectionHeaderLabel(section: IdeaClientSection, isExpanded: Bool) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(section.color)
                .frame(width: 10, height: 10)

            Text(section.clientName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(DS.text)

            Text("\(section.items.count)")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundColor(DS.textMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(DS.surfaceElevated))

            Spacer()

            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DS.textMuted)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
    }

    // MARK: - Section Content

    @ViewBuilder
    private func sectionContent(_ section: IdeaClientSection) -> some View {
        if section.items.isEmpty {
            emptyDropZone(section: section)
        } else {
            ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                IdeaListRow(
                    item: item,
                    clientColor: section.color,
                    viewModel: viewModel
                )
                .onDrag {
                    NSItemProvider(object: item.atomUUID as NSString)
                }

                if index < section.items.count - 1 {
                    Divider()
                        .background(DS.borderActive)
                        .padding(.horizontal, 12)
                }
            }
        }
    }

    @ViewBuilder
    private func emptyDropZone(section: IdeaClientSection) -> some View {
        let isDropTarget = dropTargetSectionId == section.id
        HStack {
            Spacer()
            Text("Drop ideas here")
                .font(.system(size: 12))
                .foregroundColor(isDropTarget ? section.color : DS.textMuted)
            Spacer()
        }
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isDropTarget ? section.color.opacity(0.5) : DS.borderActive.opacity(0.5),
                    style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                )
        )
        .padding(.vertical, 4)
        .onDrop(of: [.text], delegate: ClientSectionDropDelegate(
            targetClientUUID: section.clientUUID,
            sectionId: section.id,
            dropTargetSectionId: $dropTargetSectionId,
            onAssignToClient: { ideaUUID in
                assignIdeaToClient(ideaUUID: ideaUUID, clientUUID: section.clientUUID)
            }
        ))
    }

    // MARK: - Client Assignment

    private func assignIdeaToClient(ideaUUID: String, clientUUID: String?) {
        Task {
            guard var atom = try? await AtomRepository.shared.fetch(uuid: ideaUUID) else { return }

            let oldClientUUID = atom.ideaMetadata?.clientUUID

            // Skip if already assigned to this client
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

            // Reload to reflect changes
            await viewModel?.loadIdeaGallery(forceReload: true)
        }
    }
}

// MARK: - Idea List Row

private struct IdeaListRow: View {

    let item: IdeaGalleryItem
    let clientColor: Color
    var viewModel: CommandKViewModel?

    @State private var isHovered = false
    @State private var showDeleteAlert = false

    private let indigo = DS.entityIdea

    private var isSelected: Bool {
        viewModel?.selectedUUIDs.contains(item.atomUUID) ?? false
    }

    var body: some View {
        HStack(spacing: 10) {
            // Status icon
            Image(systemName: item.status.iconName)
                .font(.system(size: 11))
                .foregroundColor(item.status.color)
                .frame(width: 20)

            // Title
            Text(item.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DS.text)
                .lineLimit(1)

            Spacer(minLength: 4)

            // Tags (first 2)
            tagsView

            // Format pill
            formatView

            // Insight score
            if let score = item.insightScore {
                Text(String(format: "%.0f", score * 100))
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundColor(indigo)
                    .frame(width: 24)
            }

            // Status badge
            Text(item.status.displayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(item.status.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(item.status.color.opacity(0.12)))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isSelected ? indigo.opacity(0.1) :
                    isHovered ? DS.surfaceHover : Color.clear
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
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
                    name: CosmoNotification.NodeGraph.closeCommandK,
                    object: nil
                )
            }
        }
        .onHover { hovering in isHovered = hovering }
        .contextMenu { listRowContextMenu }
        .alert("Delete Idea?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteIdea() }
        } message: {
            Text("This will permanently remove this idea.")
        }
    }

    // MARK: - Tags (extracted for type-checker)

    @ViewBuilder
    private var tagsView: some View {
        if !item.tags.isEmpty {
            HStack(spacing: 3) {
                ForEach(Array(item.tags.prefix(2)), id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(indigo.opacity(0.7))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(indigo.opacity(0.1)))
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Format (extracted for type-checker)

    @ViewBuilder
    private var formatView: some View {
        if let format = item.contentFormat {
            Text(format.displayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(format.color.opacity(0.8))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(format.color.opacity(0.1)))
                .lineLimit(1)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var listRowContextMenu: some View {
        Button {
            NotificationCenter.default.post(
                name: .enterFocusMode,
                object: nil,
                userInfo: ["type": EntityType.idea, "id": item.entityId, "commandKTab": "ideas"]
            )
            NotificationCenter.default.post(
                name: CosmoNotification.NodeGraph.closeCommandK,
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

        Button(role: .destructive) {
            showDeleteAlert = true
        } label: {
            Label("Delete Idea", systemImage: "trash")
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

// MARK: - Client Section Drop Delegate

private struct ClientSectionDropDelegate: DropDelegate {
    let targetClientUUID: String?   // nil = "Unassigned"
    let sectionId: String
    @Binding var dropTargetSectionId: String?
    let onAssignToClient: (String) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }

    func dropEntered(info: DropInfo) {
        withAnimation(ProMotionSprings.snappy) {
            dropTargetSectionId = sectionId
        }
    }

    func dropExited(info: DropInfo) {
        withAnimation(ProMotionSprings.snappy) {
            if dropTargetSectionId == sectionId {
                dropTargetSectionId = nil
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        withAnimation(ProMotionSprings.snappy) {
            dropTargetSectionId = nil
        }
        let providers = info.itemProviders(for: [.text])
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
                let ideaUUID: String?
                if let data = item as? Data {
                    ideaUUID = String(data: data, encoding: .utf8)
                } else if let text = item as? NSString {
                    ideaUUID = text as String
                } else {
                    ideaUUID = nil
                }
                guard let uuid = ideaUUID else { return }
                DispatchQueue.main.async {
                    onAssignToClient(uuid)
                }
            }
        }
        return true
    }
}

// MARK: - Preview

#Preview("Ideas Tab") {
    IdeasTab(viewModel: CommandKViewModel(), searchQuery: "")
        .frame(width: 900, height: 600)
}
