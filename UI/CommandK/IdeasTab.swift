// CosmoOS/UI/CommandK/IdeasTab.swift
// Ideas tab for Command-K overlay
// Indigo-accented gallery of idea atoms with cards, grouping, filters, and inline capture

import SwiftUI

// MARK: - IdeaGrouping

/// Grouping mode for the idea gallery
enum IdeaGrouping: String, CaseIterable {
    case status
    case client
    case format
    case recent

    var displayName: String {
        switch self {
        case .status: return "Status"
        case .client: return "Client"
        case .format: return "Format"
        case .recent: return "Recent"
        }
    }

    var iconName: String {
        switch self {
        case .status: return "circle.grid.3x3.fill"
        case .client: return "person.crop.circle.fill"
        case .format: return "rectangle.3.group"
        case .recent: return "clock.fill"
        }
    }
}

// MARK: - IdeaSortMode

/// Sort mode for the idea gallery
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

// MARK: - IdeasTab

/// Main gallery view shown when the Ideas tab is active in Command-K
struct IdeasTab: View {

    @ObservedObject var viewModel: CommandKViewModel
    let searchQuery: String

    // Animation state
    @State private var hasAppeared = false

    // Quick capture
    @State private var quickCaptureText = ""
    @FocusState private var isCaptureFocused: Bool
    @State private var isSubmitting = false

    // Local filter/sort state (will migrate to viewModel when wired)
    @State private var ideaGrouping: IdeaGrouping = .status
    @State private var ideaSortMode: IdeaSortMode = .recent
    @State private var ideaStatusFilter: IdeaStatus? = nil
    @State private var ideaFormatFilter: ContentFormat? = nil

    private let indigo = Color(hex: "#818CF8")

    var body: some View {
        ZStack {
            // Void background
            Color(hex: "#0A0A0F")

            VStack(spacing: 0) {
                // Inline quick capture bar
                quickCaptureBar

                Divider().background(Color.white.opacity(0.15))

                // Stats row
                if !viewModel.ideaGalleryItems.isEmpty {
                    statsRow
                        .padding(.top, 4)
                }

                // Filter chips row
                filterChipsRow
                    .padding(.top, 8)

                Divider().background(Color.white.opacity(0.15))

                // Card grid (scrollable)
                if filteredItems.isEmpty {
                    emptyState
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 24) {
                            if ideaGrouping == .recent {
                                // Flat grid
                                flatGridSection
                            } else {
                                // Grouped sections
                                ForEach(Array(groupedItems.enumerated()), id: \.element.name) { groupIndex, group in
                                    IdeaGroupSection(
                                        title: group.name,
                                        count: group.items.count,
                                        accentColor: indigo
                                    ) {
                                        IdeaMasonryGrid(
                                            items: group.items,
                                            hasAppeared: hasAppeared,
                                            baseDelayOffset: groupIndex * 4,
                                            viewModel: viewModel
                                        )
                                        .padding(.horizontal, 24)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 24)
                        .padding(.top, 8)
                    }
                }
            }
        }
        .onAppear {
            if viewModel.ideaGalleryItems.isEmpty {
                Task {
                    await viewModel.loadIdeaGallery()
                }
            }
            withAnimation(ProMotionSprings.gentle) {
                hasAppeared = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ideaDeleted"))) { notification in
            if let uuid = notification.userInfo?["uuid"] as? String {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.ideaGalleryItems.removeAll { $0.atomUUID == uuid }
                }
            }
        }
    }

    // MARK: - Quick Capture Bar

    private var quickCaptureBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(indigo.opacity(0.7))

            TextField("Capture a new idea...", text: $quickCaptureText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .focused($isCaptureFocused)
                .onSubmit {
                    submitQuickCapture()
                }

            if !quickCaptureText.isEmpty {
                Button {
                    submitQuickCapture()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(indigo)
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting)
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 48)
        .background(Color(hex: "#12121A"))
    }

    private func submitQuickCapture() {
        let text = quickCaptureText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSubmitting else { return }

        isSubmitting = true

        Task {
            do {
                try await AtomRepository.shared.createEnrichedIdea(
                    title: text,
                    content: text,
                    captureSource: "keyboard"
                )
                await MainActor.run {
                    quickCaptureText = ""
                    isSubmitting = false
                }
                // Reload gallery to include new idea
                await viewModel.loadIdeaGallery(forceReload: true)
            } catch {
                await MainActor.run {
                    isSubmitting = false
                }
            }
        }
    }

    // MARK: - Filtered Items

    private var filteredItems: [IdeaGalleryItem] {
        var items = viewModel.ideaGalleryItems

        // Apply search filter
        if !searchQuery.isEmpty {
            let q = searchQuery.lowercased()
            items = items.filter { item in
                item.title.lowercased().contains(q) ||
                (item.body?.lowercased().contains(q) ?? false) ||
                (item.clientName?.lowercased().contains(q) ?? false) ||
                item.tags.contains { $0.lowercased().contains(q) }
            }
        }

        // Apply status filter
        if let statusFilter = ideaStatusFilter {
            items = items.filter { $0.status == statusFilter }
        }

        // Apply format filter
        if let formatFilter = ideaFormatFilter {
            items = items.filter { $0.contentFormat == formatFilter }
        }

        // Apply sort
        switch ideaSortMode {
        case .recent:
            items.sort { $0.updatedAt > $1.updatedAt }
        case .priority:
            items.sort { lhs, rhs in
                // Pinned first, then by status sort order
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                return lhs.status.sortOrder < rhs.status.sortOrder
            }
        case .insightScore:
            items.sort { ($0.insightScore ?? 0) > ($1.insightScore ?? 0) }
        }

        return items
    }

    // MARK: - Collection Stats

    private var totalIdeaCount: Int {
        viewModel.ideaGalleryItems.count
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

    private var topFormat: ContentFormat? {
        let formats: [ContentFormat] = viewModel.ideaGalleryItems.compactMap(\.contentFormat)
        let counts: [ContentFormat: Int] = Dictionary(formats.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max(by: { $0.value < $1.value })?.key
    }

    private var unlinkedIdeaCount: Int {
        viewModel.ideaGalleryItems.filter { ($0.matchingSwipeCount ?? 0) == 0 }.count
    }

    private var statsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                // Total count
                HStack(spacing: 4) {
                    Text("\(totalIdeaCount)")
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundColor(.white.opacity(0.8))
                    Text("ideas")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }

                // Divider
                statsDivider

                // Status breakdown
                ForEach(statusBreakdown, id: \.status) { entry in
                    HStack(spacing: 4) {
                        Text("\(entry.count)")
                            .font(.system(size: 13, weight: .bold).monospacedDigit())
                            .foregroundColor(entry.status.color)
                        Text(entry.status.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(entry.status.color.opacity(0.8))
                    }
                }

                // Top format badge
                if let format = topFormat {
                    statsDivider

                    HStack(spacing: 5) {
                        Image(systemName: format.icon)
                            .font(.system(size: 10))
                        Text(format.displayName)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(format.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(format.color.opacity(0.15))
                    )
                }

                // Unlinked count
                if unlinkedIdeaCount > 0 {
                    statsDivider

                    HStack(spacing: 4) {
                        Text("Unlinked:")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(indigo.opacity(0.5))
                        Text("\(unlinkedIdeaCount)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(indigo.opacity(0.5))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .strokeBorder(
                                indigo.opacity(0.3),
                                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                            )
                    )
                }

                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .frame(height: 44)
        .background(Color(hex: "#0A0A0F"))
    }

    private var statsDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 1, height: 20)
    }

    // MARK: - Grouped Items

    private var groupedItems: [(name: String, items: [IdeaGalleryItem])] {
        let items = filteredItems

        switch ideaGrouping {
        case .status:
            var groups: [IdeaStatus: [IdeaGalleryItem]] = [:]
            for item in items {
                groups[item.status, default: []].append(item)
            }
            var result = groups.map { (name: $0.key.displayName, items: $0.value) }
            // Sort by status pipeline order
            let statusOrder: [String: Int] = Dictionary(
                IdeaStatus.allCases.map { ($0.displayName, $0.sortOrder) },
                uniquingKeysWith: { first, _ in first }
            )
            result.sort { (statusOrder[$0.name] ?? 99) < (statusOrder[$1.name] ?? 99) }
            return result

        case .client:
            var groups: [String: [IdeaGalleryItem]] = [:]
            for item in items {
                let key = item.clientName ?? "Unassigned"
                groups[key, default: []].append(item)
            }
            var result = groups.map { (name: $0.key, items: $0.value) }
            result.sort { $0.items.count > $1.items.count }
            return result

        case .format:
            var groups: [String: [IdeaGalleryItem]] = [:]
            for item in items {
                let key = item.contentFormat?.displayName ?? "No Format"
                groups[key, default: []].append(item)
            }
            var result = groups.map { (name: $0.key, items: $0.value) }
            result.sort { $0.items.count > $1.items.count }
            return result

        case .recent:
            return [(name: "All Ideas", items: items)]
        }
    }

    // MARK: - Flat Grid Section

    private var flatGridSection: some View {
        IdeaMasonryGrid(
            items: filteredItems,
            hasAppeared: hasAppeared,
            viewModel: viewModel
        )
        .padding(.horizontal, 24)
    }

    // MARK: - Filter Chips

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // Status filter menu
                statusFilterMenu

                chipDivider

                // Format filter menu
                formatFilterMenu

                chipDivider

                // Sort mode menu
                sortMenu

                chipDivider

                // Grouping menu
                groupingMenu
            }
            .padding(.horizontal, 24)
        }
        .frame(height: 52)
    }

    private var chipDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(width: 1, height: 24)
    }

    private func chipLabel(_ text: String, icon: String? = nil, isActive: Bool = false) -> some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 10))
            }
            Text(text)
                .font(.system(size: 12, weight: .medium))
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
        }
        .foregroundColor(isActive ? .white : .white.opacity(0.7))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? indigo.opacity(0.25) : Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isActive ? indigo.opacity(0.6) : Color.white.opacity(0.12),
                            lineWidth: 1
                        )
                )
        )
    }

    private var statusFilterMenu: some View {
        Menu {
            Button("All Statuses") { ideaStatusFilter = nil }
            Divider()
            ForEach(IdeaStatus.allCases, id: \.rawValue) { status in
                Button {
                    ideaStatusFilter = ideaStatusFilter == status ? nil : status
                } label: {
                    Label(status.displayName, systemImage: status.iconName)
                }
            }
        } label: {
            chipLabel(
                ideaStatusFilter?.displayName ?? "Status",
                icon: ideaStatusFilter?.iconName ?? "circle.grid.3x3.fill",
                isActive: ideaStatusFilter != nil
            )
        }
        .menuStyle(.borderlessButton)
    }

    private var formatFilterMenu: some View {
        Menu {
            Button("All Formats") { ideaFormatFilter = nil }
            Divider()
            ForEach(ContentFormat.allCases, id: \.rawValue) { format in
                Button {
                    ideaFormatFilter = ideaFormatFilter == format ? nil : format
                } label: {
                    Label(format.displayName, systemImage: format.icon)
                }
            }
        } label: {
            chipLabel(
                ideaFormatFilter?.displayName ?? "Format",
                icon: ideaFormatFilter?.icon ?? "doc.text.fill",
                isActive: ideaFormatFilter != nil
            )
        }
        .menuStyle(.borderlessButton)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(IdeaSortMode.allCases, id: \.self) { mode in
                Button(mode.displayName) { ideaSortMode = mode }
            }
        } label: {
            chipLabel(ideaSortMode.displayName)
        }
        .menuStyle(.borderlessButton)
    }

    private var groupingMenu: some View {
        Menu {
            ForEach(IdeaGrouping.allCases, id: \.self) { mode in
                Button {
                    ideaGrouping = mode
                } label: {
                    Label(mode.displayName, systemImage: mode.iconName)
                }
            }
        } label: {
            chipLabel(ideaGrouping.displayName, icon: "rectangle.3.group")
        }
        .menuStyle(.borderlessButton)
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
                .foregroundColor(.white.opacity(0.6))

            Text("Start by capturing one above.")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.4))

            Spacer()
        }
    }
}

// MARK: - Masonry Grid

private struct IdeaMasonryGrid: View {

    let items: [IdeaGalleryItem]
    let hasAppeared: Bool
    var baseDelayOffset: Int = 0
    var viewModel: CommandKViewModel?

    private let columnCount = 3
    private let spacing: CGFloat = 12
    private let columnWidth: CGFloat = 200

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<columnCount, id: \.self) { columnIndex in
                LazyVStack(spacing: spacing) {
                    ForEach(Array(columnItems(for: columnIndex).enumerated()), id: \.element.id) { itemIndex, item in
                        IdeaGalleryCard(
                            item: item,
                            cardWidth: columnWidth,
                            appearDelay: Double(baseDelayOffset + columnIndex + itemIndex * columnCount) * 0.04,
                            hasAppeared: hasAppeared,
                            viewModel: viewModel
                        )
                    }
                }
                .frame(width: columnWidth)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 24)
    }

    /// Distribute items across columns using shortest-column-first for balanced heights
    private func columnItems(for column: Int) -> [IdeaGalleryItem] {
        var columnHeights = Array(repeating: CGFloat(0), count: columnCount)
        var columns: [[IdeaGalleryItem]] = Array(repeating: [], count: columnCount)

        for item in items {
            // Find the shortest column
            let shortestColumn = columnHeights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            columns[shortestColumn].append(item)
            columnHeights[shortestColumn] += IdeaGalleryCard.estimatedHeight(for: item, width: columnWidth) + spacing
        }

        return columns[column]
    }
}

// MARK: - IdeaGalleryCard

private struct IdeaGalleryCard: View {

    let item: IdeaGalleryItem
    let cardWidth: CGFloat
    let appearDelay: Double
    let hasAppeared: Bool
    var viewModel: CommandKViewModel?

    @State private var isHovered = false
    @State private var isPressed = false
    @State private var showDeleteAlert = false

    private let indigo = Color(hex: "#818CF8")

    /// Estimate card height based on content for masonry distribution
    static func estimatedHeight(for item: IdeaGalleryItem, width: CGFloat) -> CGFloat {
        let padding: CGFloat = 20 // vertical padding
        let statusRow: CGFloat = 22
        let spacing: CGFloat = 8
        let titleLines = min(ceil(CGFloat(item.title.count) / 22.0), 3)
        let titleHeight = titleLines * 18

        var bodyHeight: CGFloat = 0
        if let body = item.body, !body.isEmpty {
            let bodyLength = body.count
            let maxLines: CGFloat = bodyLength > 200 ? 8 : (bodyLength > 100 ? 5 : 3)
            let lineCount = min(ceil(CGFloat(bodyLength) / 28.0), maxLines)
            bodyHeight = lineCount * 15 + spacing
        }

        let formatRow: CGFloat = (item.contentFormat != nil || item.platform != nil) ? 18 + spacing : 0
        let clientRow: CGFloat = item.clientName != nil ? 22 + spacing : 0

        var tagHeight: CGFloat = 0
        if !item.tags.isEmpty {
            tagHeight = 24 + spacing
        }

        let bottomRow: CGFloat = 30

        return padding + statusRow + spacing + titleHeight + bodyHeight + formatRow + clientRow + tagHeight + spacing + bottomRow
    }

    /// Dynamic line limit based on body text length
    private var bodyLineLimit: Int {
        guard let body = item.body else { return 3 }
        let length = body.count
        if length > 200 { return 8 }
        if length > 100 { return 5 }
        return 3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row: status badge + pin indicator + analysis dot
            HStack(spacing: 6) {
                statusBadge

                Spacer()

                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundColor(indigo.opacity(0.7))
                        .rotationEffect(.degrees(-45))
                }

                analysisDot
            }

            // Title
            Text(item.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Body preview — dynamic line limit based on content length
            if let body = item.body, !body.isEmpty {
                Text(body)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(bodyLineLimit)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Tags
            if !item.tags.isEmpty {
                tagsRow
            }

            Spacer(minLength: 4)

            // Format + platform icons row
            formatPlatformRow

            // Client tag pill
            if let clientName = item.clientName {
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
        .padding(10)
        .frame(width: cardWidth)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isHovered ? indigo.opacity(0.4) : Color.white.opacity(0.12),
                    lineWidth: 1
                )
        )
        .shadow(
            color: isHovered ? indigo.opacity(0.15) : .clear,
            radius: isHovered ? 12 : 0,
            y: isHovered ? 4 : 0
        )
        .scaleEffect(isPressed ? 0.95 : (isHovered ? 1.03 : 1.0))
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
            // Open in Idea Focus Mode
            NotificationCenter.default.post(
                name: .enterFocusMode,
                object: nil,
                userInfo: ["type": EntityType.idea, "id": item.entityId]
            )
            // Close Command-K
            NotificationCenter.default.post(
                name: CosmoNotification.NodeGraph.closeCommandK,
                object: nil
            )
        }
        .onLongPressGesture(minimumDuration: 0.5, pressing: { pressing in
            isPressed = pressing
        }) {
            // Add to canvas
            NotificationCenter.default.post(
                name: Notification.Name("addIdeaToCanvas"),
                object: nil,
                userInfo: ["atomUUID": item.atomUUID]
            )
        }
        .contextMenu {
            // Open in Focus Mode
            Button {
                NotificationCenter.default.post(
                    name: .enterFocusMode,
                    object: nil,
                    userInfo: ["type": EntityType.idea, "id": item.entityId]
                )
                NotificationCenter.default.post(
                    name: CosmoNotification.NodeGraph.closeCommandK,
                    object: nil
                )
            } label: {
                Label("Open", systemImage: "arrow.up.left.and.arrow.down.right")
            }

            // Add to Canvas
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

            // Change Status submenu
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

            // Delete
            Button(role: .destructive) {
                showDeleteAlert = true
            } label: {
                Label("Delete Idea", systemImage: "trash")
            }
        }
        .alert("Delete Idea?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    try? await AtomRepository.shared.delete(uuid: item.atomUUID)
                    NotificationCenter.default.post(
                        name: Notification.Name("ideaDeleted"),
                        object: nil,
                        userInfo: ["uuid": item.atomUUID]
                    )
                }
            }
        } message: {
            Text("This will permanently remove this idea.")
        }
    }

    // MARK: - Tags Row

    private var tagsRow: some View {
        let visibleTags = Array(item.tags.prefix(3))
        return HStack(spacing: 4) {
            ForEach(visibleTags, id: \.self) { tag in
                Text("#\(tag)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(indigo.opacity(0.7))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(indigo.opacity(0.1))
                    )
                    .lineLimit(1)
            }
            if item.tags.count > 3 {
                Text("+\(item.tags.count - 3)")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
    }

    // MARK: - Bottom Metadata Row

    @ViewBuilder
    private var bottomMetadataRow: some View {
        HStack(spacing: 6) {
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
            HStack(spacing: 3) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 8))
                Text("\(item.contentCount)")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(.blue)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.blue.opacity(0.2))
            )
        }
    }

    // MARK: - Status Badge

    private var statusBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: item.status.iconName)
                .font(.system(size: 8))
            Text(item.status.displayName)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundColor(item.status.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(item.status.color.opacity(0.2))
        )
    }

    // MARK: - Format + Platform Row

    private var formatPlatformRow: some View {
        HStack(spacing: 6) {
            if let format = item.contentFormat {
                HStack(spacing: 3) {
                    Image(systemName: format.icon)
                        .font(.system(size: 9))
                    Text(format.displayName)
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(format.color.opacity(0.8))
            }

            if item.contentFormat != nil && item.platform != nil {
                Text("\u{00B7}")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
            }

            if let platform = item.platform {
                HStack(spacing: 3) {
                    Image(systemName: platform.iconName)
                        .font(.system(size: 9))
                    Text(platform.displayName)
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(platform.color.opacity(0.8))
            }
        }
    }

    // MARK: - Client Pill

    private func clientPill(_ name: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 8))
            Text(name)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundColor(.white.opacity(0.7))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.08))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                )
        )
        .lineLimit(1)
    }

    // MARK: - Framework Pill

    private func frameworkPill(_ framework: SwipeFrameworkType) -> some View {
        Text(framework.abbreviation)
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(framework.color)
            .padding(.horizontal, 5)
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
                .font(.system(size: 7))
            Text("\(count)")
                .font(.system(size: 9, weight: .medium).monospacedDigit())
        }
        .foregroundColor(Color(hex: "#FFD700").opacity(0.8))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Color(hex: "#FFD700").opacity(0.12))
        )
    }

    // MARK: - Insight Score Ring

    private func insightScoreRing(_ score: Double) -> some View {
        ZStack {
            // Background ring
            Circle()
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 2)
                .frame(width: 26, height: 26)

            // Progress ring
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
                .frame(width: 26, height: 26)
                .rotationEffect(.degrees(-90))

            // Score text
            Text(String(format: "%.0f", score * 100))
                .font(.system(size: 8, weight: .bold).monospacedDigit())
                .foregroundColor(indigo)
        }
    }

    // MARK: - Analysis Status Dot

    private var analysisDot: some View {
        Circle()
            .fill(analysisDotColor)
            .frame(width: 8, height: 8)
    }

    private var analysisDotColor: Color {
        if item.contentCount > 0 {
            return Color(hex: "#818CF8") // Purple: activated (has content)
        } else if item.insightScore != nil {
            return Color(hex: "#22C55E") // Green: analyzed
        } else {
            return Color.white.opacity(0.3) // Gray: unanalyzed
        }
    }

    // MARK: - Hover Quick-Action Bar

    private var hoverActionBar: some View {
        HStack(spacing: 8) {
            // Analyze
            Button {
                viewModel?.quickAnalyzeIdea(item)
            } label: {
                analyzeButtonLabel()
            }
            .buttonStyle(.plain)

            // Activate (open in focus mode)
            Button {
                NotificationCenter.default.post(
                    name: .enterFocusMode,
                    object: nil,
                    userInfo: ["type": EntityType.idea, "id": item.entityId]
                )
                NotificationCenter.default.post(
                    name: CosmoNotification.NodeGraph.closeCommandK,
                    object: nil
                )
            } label: {
                activateButtonLabel()
            }
            .buttonStyle(.plain)

            // Archive
            Button {
                changeStatus(to: .archived)
            } label: {
                archiveButtonLabel()
            }
            .buttonStyle(.plain)

            // Delete
            Button {
                showDeleteAlert = true
            } label: {
                deleteButtonLabel()
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func analyzeButtonLabel() -> some View {
        Image(systemName: "sparkles")
            .font(.system(size: 11))
            .foregroundColor(indigo)
            .frame(width: 28, height: 22)
            .background(indigo.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
    }

    @ViewBuilder
    private func activateButtonLabel() -> some View {
        Image(systemName: "arrow.up.forward")
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.7))
            .frame(width: 28, height: 22)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
    }

    @ViewBuilder
    private func archiveButtonLabel() -> some View {
        Image(systemName: "archivebox")
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.5))
            .frame(width: 28, height: 22)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
    }

    @ViewBuilder
    private func deleteButtonLabel() -> some View {
        Image(systemName: "trash")
            .font(.system(size: 11))
            .foregroundColor(.red.opacity(0.7))
            .frame(width: 28, height: 22)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
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

// MARK: - IdeaGroupSection

private struct IdeaGroupSection<Content: View>: View {

    let title: String
    let count: Int
    var accentColor: Color = Color(hex: "#818CF8")
    let content: () -> Content

    init(
        title: String,
        count: Int,
        accentColor: Color = Color(hex: "#818CF8"),
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.count = count
        self.accentColor = accentColor
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 8) {
                Text(title.uppercased())
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.4))

                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(accentColor.opacity(0.7))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(accentColor.opacity(0.15))
                    )

                Spacer()
            }
            .padding(.horizontal, 24)

            // Content
            content()
        }
    }
}
