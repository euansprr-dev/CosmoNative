// CosmoOS/UI/CommandK/UnifiedSearchResultsView.swift
// Unified cross-library search results view for Command-K
// Pinterest-style masonry grid using actual library cards

import SwiftUI

// MARK: - UnifiedSearchResultsView

struct UnifiedSearchResultsView: View {

    var viewModel: CommandKViewModel

    private let minCardWidth: CGFloat = 248
    private let cardSpacing: CGFloat = CommandKMetrics.cardSpacing

    var body: some View {
        if viewModel.unifiedFlatResults.isEmpty && viewModel.searchFeedback.matches(query: viewModel.query) {
            emptyState
        } else {
            GeometryReader { geometry in
                let columnCount = max(2, Int(geometry.size.width / (minCardWidth + cardSpacing)))
                let totalSpacing = CGFloat(columnCount - 1) * cardSpacing + (CommandKMetrics.contentPadding * 2)
                let cardWidth = (geometry.size.width - totalSpacing) / CGFloat(columnCount)

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 12) {
                            toolbarRow
                                .padding(.horizontal, CommandKMetrics.contentPadding)

                            MasonryLayout(columnCount: columnCount, spacing: cardSpacing) {
                                ForEach(Array(viewModel.unifiedCardItems.enumerated()), id: \.element.id) { index, item in
                                    unifiedCard(item, cardWidth: cardWidth)
                                        .id(item.selectionID)
                                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                                        .animation(
                                            ProMotionSprings.cardEntrance.delay(Double(index % 16) * 0.03),
                                            value: viewModel.unifiedCardItems.count
                                        )
                                }
                            }
                            .padding(.horizontal, CommandKMetrics.contentPadding)
                        }
                        .padding(.vertical, 16)
                    }
                    .onChange(of: viewModel.selectedResultIndex) { _, _ in
                        if viewModel.selectedResultIndex >= 0,
                           viewModel.selectedResultIndex < viewModel.unifiedFlatResults.count {
                            let result = viewModel.unifiedFlatResults[viewModel.selectedResultIndex]
                            let scrollId = result.selectionID
                            withAnimation(ProMotionSprings.snappy) {
                                proxy.scrollTo(scrollId, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Cards

    @ViewBuilder
    private func unifiedCard(_ item: UnifiedCardItem, cardWidth: CGFloat) -> some View {
        switch item {
        case .library(let libraryItem):
            SearchResultLibraryCard(
                item: libraryItem,
                isSelected: viewModel.selectedNodeId == libraryItem.uuid,
                cardWidth: cardWidth
            )
        case .swipe(let swipeItem):
            SearchResultSwipeCard(
                item: swipeItem,
                isSelected: viewModel.selectedNodeId == swipeItem.atomUUID,
                cardWidth: cardWidth
            )
        case .readwise(let result):
            readwiseCard(result, cardWidth: cardWidth)
                .contextMenu {
                    Button {
                        if let bookId = result.readwiseBookId {
                            viewModel.selectedReadwiseBookId = bookId
                        }
                    } label: {
                        Label("Open", systemImage: "book")
                    }
                }
        }
    }

    @ViewBuilder
    private func readwiseCard(_ result: UnifiedSearchResult, cardWidth _: CGFloat) -> some View {
        let isSelected = viewModel.selectedNodeId == result.id
        let cornerRadius = CommandKMetrics.cardCornerRadius

        Button {
            if let bookId = result.readwiseBookId {
                viewModel.selectedReadwiseBookId = bookId
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    DS.entityReadwise.opacity(0.08)

                    Image(systemName: result.icon)
                        .font(DS.pageTitle)
                        .foregroundStyle(DS.entityReadwise.opacity(0.6))
                }
                .frame(height: 100)

                Rectangle()
                    .fill(DS.entityReadwise.opacity(0.18))
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 8) {
                    Text(result.title)
                        .font(DS.headline)
                        .foregroundStyle(DS.text)
                        .lineLimit(2)

                    if let snippet = result.snippet, !snippet.isEmpty {
                        Text(snippet)
                            .font(DS.cardMeta)
                            .foregroundStyle(DS.textMuted)
                            .lineLimit(2)
                    }

                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "books.vertical.fill")
                                .font(DS.caption2)
                            Text("Readwise")
                                .font(DS.caption2)
                        }
                        .foregroundStyle(DS.entityReadwise)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(DS.entityReadwise.opacity(0.10))
                        .clipShape(Capsule())

                        Spacer()

                        if let subtitle = result.subtitle {
                            Text(subtitle)
                                .font(DS.footnote)
                                .foregroundStyle(DS.textMuted)
                        }
                    }
                }
                .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .commandKGalleryCardChrome(
                isHovered: false,
                isSelected: isSelected,
                accentColor: DS.entityReadwise,
                cornerRadius: cornerRadius
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Toolbar

    private var toolbarRow: some View {
        HStack(spacing: 8) {
            let total = viewModel.unifiedFlatResults.count
            Text("\(total) result\(total == 1 ? "" : "s") across all libraries")
                .font(DS.buttonText)
                .foregroundStyle(DS.textSecondary)

            if viewModel.isAIRanked {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(DS.caption2)
                    Text("AI ranked")
                        .font(DS.caption2)
                }
                .foregroundStyle(DS.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(DS.accentSoft)
                .clipShape(Capsule())
            }

            Spacer()
        }
        .padding(.bottom, 4)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "magnifyingglass")
                .font(DS.display)
                .foregroundStyle(DS.textMuted)

            Text("No results found")
                .font(DS.headline)
                .foregroundStyle(DS.textSecondary)

            VStack(spacing: 6) {
                Text("Try different keywords or use prefixes:")
                    .font(DS.cardMeta)
                    .foregroundStyle(DS.textMuted)

                HStack(spacing: 8) {
                    prefixHint("#idea")
                    prefixHint("#swipe")
                    prefixHint("#content")
                    prefixHint("task:")
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func prefixHint(_ text: String) -> some View {
        Text(text)
            .font(DS.footnote)
            .foregroundStyle(DS.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DS.glassCardFill)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(DS.glassBorder, lineWidth: 0.5)
            )
    }

}

// MARK: - Search Result Library Card

private struct SearchResultLibraryCard: View {
    let item: LibraryItem
    let isSelected: Bool
    let cardWidth: CGFloat
    @State private var showDeleteAlert = false

    var body: some View {
        LibraryCardView(item: item, cardWidth: cardWidth, isSelected: isSelected)
            .onTapGesture { openInFocusMode() }
            .contextMenu { contextMenuContent }
            .alert("Delete \"\(item.title)\"?", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { deleteItem() }
            } message: {
                Text("This item will be moved to Recently Deleted for 30 days.")
            }
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        Button {
            openInFocusMode()
        } label: {
            Label(
                item.kind == .thinkspace ? "Open Thinkspace" : "Open in Focus Mode",
                systemImage: item.kind == .thinkspace ? "rectangle.3.group" : "arrow.up.left.and.arrow.down.right"
            )
        }

        Button { openAsPane() } label: {
            Label("Open as Pane", systemImage: "rectangle.split.2x1")
        }

        if item.kind == .atom {
            Button { addToCanvas() } label: {
                Label("Add to Canvas", systemImage: "plus.rectangle.on.rectangle")
            }
        }

        Divider()

        Button(role: .destructive) {
            showDeleteAlert = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func openInFocusMode() {
        Task { try? await NodeGraphEngine.shared.recordAccess(atomUUID: item.uuid, type: .view) }

        if item.kind == .thinkspace {
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.navigateToThinkspaceById,
                object: nil,
                userInfo: CosmoNotification.Navigation.ThinkspacePayload(thinkspaceId: item.uuid).userInfo
            )
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
            return
        }

        guard let entityType = EntityType(rawValue: item.atomType.rawValue),
              item.entityId > 0 else { return }

        NotificationCenter.default.post(
            name: .enterFocusMode,
            object: nil,
            userInfo: ["type": entityType, "id": item.entityId]
        )
        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.hideCommandK, object: nil)
    }

    private func openAsPane() {
        if item.kind == .thinkspace {
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openAsPane,
                object: nil,
                userInfo: ["thinkspaceId": item.uuid]
            )
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
            return
        }

        if let entityType = EntityType(rawValue: item.atomType.rawValue) {
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openAsPane,
                object: nil,
                userInfo: ["type": entityType, "id": item.entityId]
            )
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
        }
    }

    private func addToCanvas() {
        guard item.kind == .atom else { return }
        NotificationCenter.default.post(
            name: CosmoNotification.NodeGraph.addToCanvas,
            object: nil,
            userInfo: ["atomUUID": item.uuid]
        )
    }

    private func deleteItem() {
        Task { try? await AtomRepository.shared.delete(uuid: item.uuid) }
    }
}

// MARK: - Search Result Swipe Card

private struct SearchResultSwipeCard: View {
    let item: SwipeGalleryItem
    let isSelected: Bool
    let cardWidth: CGFloat
    @State private var showDeleteAlert = false

    var body: some View {
        SwipeGalleryCardView(item: item, cardWidth: cardWidth, isSelected: isSelected)
            .onTapGesture { openInFocusMode() }
            .contextMenu { contextMenuContent }
            .alert("Delete Swipe?", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { deleteSwipe() }
            } message: {
                Text("This will permanently remove this swipe file.")
            }
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        Button { openInFocusMode() } label: {
            Label("Open in Focus Mode", systemImage: "arrow.up.left.and.arrow.down.right")
        }

        Button { openAsPane() } label: {
            Label("Open as Pane", systemImage: "rectangle.split.2x1")
        }

        Button { addToCanvas() } label: {
            Label("Add to Canvas", systemImage: "plus.rectangle.on.rectangle")
        }

        Divider()

        Button(role: .destructive) {
            showDeleteAlert = true
        } label: {
            Label("Delete Swipe", systemImage: "trash")
        }
    }

    private func openInFocusMode() {
        Task { try? await NodeGraphEngine.shared.recordAccess(atomUUID: item.atomUUID, type: .view) }

        NotificationCenter.default.post(
            name: .enterFocusMode,
            object: nil,
            userInfo: ["type": EntityType.research, "id": item.entityId, "commandKTab": "swipeGallery"]
        )
        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.hideCommandK, object: nil)
    }

    private func openAsPane() {
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.openAsPane,
            object: nil,
            userInfo: ["type": EntityType.research, "id": item.entityId]
        )
        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
    }

    private func addToCanvas() {
        NotificationCenter.default.post(
            name: Notification.Name("addSwipeToCanvas"),
            object: nil,
            userInfo: ["atomUUID": item.atomUUID]
        )
    }

    private func deleteSwipe() {
        Task { try? await SwipeFileEngine.shared.deleteSwipe(atomUUID: item.atomUUID) }
    }
}
