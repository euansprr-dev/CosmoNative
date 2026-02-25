// CosmoOS/UI/CommandK/IdeasTab.swift
// Ideas tab for Command-K overlay
// Unified filter bar matching Library style — dropdowns for all filters, flat grid display

import SwiftUI

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

// MARK: - IdeasTab

struct IdeasTab: View {

    @ObservedObject var viewModel: CommandKViewModel
    let searchQuery: String

    @State private var hasAppeared = false

    // Filter/sort state
    @State private var ideaSortMode: IdeaSortMode = .recent
    @State private var ideaStatusFilter: IdeaStatus? = nil
    @State private var ideaFormatFilter: ContentFormat? = nil

    private let indigo = Color(hex: "#818CF8")

    var body: some View {
        ZStack {
            DS.bg

            VStack(spacing: 0) {
                // Library-style filter bar
                filterBar

                Divider().background(DS.borderActive)

                // Card grid
                if filteredItems.isEmpty {
                    emptyState
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        IdeaMasonryGrid(
                            items: filteredItems,
                            hasAppeared: hasAppeared,
                            viewModel: viewModel
                        )
                        .padding(.horizontal, 24)
                        .padding(.bottom, viewModel.isMultiSelectActive ? 84 : 24)
                        .padding(.top, 8)
                    }
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

            Spacer()

            // Filter dropdowns
            statusMenu
            formatMenu

            filterSeparator

            sortMenu

            if hasActiveFilters {
                clearButton
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
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
        .foregroundColor(isActive ? DS.text : DS.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? indigo.opacity(0.15) : DS.border)
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
            .foregroundColor(DS.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(DS.border)
            )
        }
        .menuStyle(.borderlessButton)
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

    private func columnItems(for column: Int) -> [IdeaGalleryItem] {
        var columnHeights = Array(repeating: CGFloat(0), count: columnCount)
        var columns: [[IdeaGalleryItem]] = Array(repeating: [], count: columnCount)

        for item in items {
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

    private var isSelected: Bool {
        viewModel?.selectedUUIDs.contains(item.atomUUID) ?? false
    }

    static func estimatedHeight(for item: IdeaGalleryItem, width: CGFloat) -> CGFloat {
        let padding: CGFloat = 20
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
                .foregroundColor(DS.text)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Body preview
            if let body = item.body, !body.isEmpty {
                Text(body)
                    .font(.system(size: 11))
                    .foregroundColor(DS.textSecondary)
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
                .fill(DS.border)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isHovered ? indigo.opacity(0.4) : DS.borderActive,
                    lineWidth: 1
                )
        )
        .cardSelectionOverlay(isSelected: isSelected, accentColor: indigo)
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
                    .foregroundColor(DS.textMuted)
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
                    .foregroundColor(DS.textMuted)
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
        .foregroundColor(DS.textSecondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(DS.border)
                .overlay(
                    Capsule()
                        .strokeBorder(DS.borderActive, lineWidth: 0.5)
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
            Circle()
                .strokeBorder(DS.borderActive, lineWidth: 2)
                .frame(width: 26, height: 26)

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
            return Color(hex: "#818CF8")
        } else if item.insightScore != nil {
            return Color(hex: "#22C55E")
        } else {
            return DS.textMuted
        }
    }

    // MARK: - Hover Quick-Action Bar

    private var hoverActionBar: some View {
        HStack(spacing: 8) {
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
            .foregroundColor(DS.textSecondary)
            .frame(width: 28, height: 22)
            .background(DS.border, in: RoundedRectangle(cornerRadius: 5))
    }

    @ViewBuilder
    private func archiveButtonLabel() -> some View {
        Image(systemName: "archivebox")
            .font(.system(size: 11))
            .foregroundColor(DS.textSecondary)
            .frame(width: 28, height: 22)
            .background(DS.border, in: RoundedRectangle(cornerRadius: 5))
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

// MARK: - Preview

#Preview("Ideas Tab") {
    IdeasTab(viewModel: CommandKViewModel(), searchQuery: "")
        .frame(width: 900, height: 600)
}
