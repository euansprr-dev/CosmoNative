import SwiftUI

struct InboxSpatialCanvasView: View {
    @Bindable var viewModel: InboxViewModel
    @State private var zoom: CGFloat = 1.0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            board
            inspector
        }
        .background(spatialBackground)
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Inbox.focusInboxItem)) { notification in
            guard let uuid = notification.userInfo?["uuid"] as? String else { return }
            viewModel.focusInboxItem(uuid: uuid)
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Inbox.focusDatabaseItem)) { notification in
            guard let uuid = notification.userInfo?["uuid"] as? String else { return }
            viewModel.focusDatabaseItem(uuid: uuid)
        }
    }

    private var board: some View {
        VStack(spacing: 0) {
            toolbar
            GeometryReader { proxy in
                ScrollView(.vertical) {
                    clusterGrid(width: proxy.size.width)
                        .padding(DS.space24)
                        .scaleEffect(zoom, anchor: .topLeading)
                        .frame(
                            width: proxy.size.width * zoom,
                            alignment: .topLeading
                        )
                        .animation(ProMotionSprings.gentle, value: zoom)
                }
            }
        }
    }

    /// 3 columns ≥1100pt, 2 columns ≥760pt, otherwise single column.
    /// Fixed `.flexible` columns guarantee a shared grid spine so cluster
    /// cards line up across the row instead of reflowing at variable widths.
    private func clusterGrid(width: CGFloat) -> some View {
        let usable = max(width - DS.space24 * 2, 0)
        let columnCount: Int = {
            if usable >= 1100 { return 3 }
            if usable >= 760 { return 2 }
            return 1
        }()
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: DS.space16, alignment: .top),
            count: columnCount
        )

        return LazyVGrid(columns: columns, alignment: .leading, spacing: DS.space16) {
            ForEach(Array(viewModel.softClusters.enumerated()), id: \.element.id) { index, cluster in
                InboxSoftClusterView(cluster: cluster, viewModel: viewModel)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    .animation(
                        ProMotionSprings.cardEntrance.delay(0.03 * Double(min(index, 4))),
                        value: viewModel.softClusters.map(\.id)
                    )
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: DS.space12) {
            Label("\(viewModel.softClusters.count) soft clusters", systemImage: "sparkles")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)

            if !viewModel.unplacedDatabaseItems.isEmpty {
                Label("\(viewModel.unplacedDatabaseItems.count) unplaced", systemImage: "tray.full")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            }

            Spacer()

            zoomControls
        }
        .padding(.horizontal, DS.space24)
        .padding(.vertical, DS.space10)
        .background(DS.surface.opacity(0.7))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DS.sepiaSubtle)
                .frame(height: 0.5)
        }
    }

    private var zoomControls: some View {
        HStack(spacing: DS.space8) {
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    zoom = max(0.82, zoom - 0.08)
                }
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Zoom out")

            Slider(value: $zoom, in: 0.82...1.18)
                .frame(width: 120)
                .controlSize(.mini)

            Button {
                withAnimation(ProMotionSprings.snappy) {
                    zoom = min(1.18, zoom + 0.08)
                }
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Zoom in")
        }
    }

    @ViewBuilder
    private var inspector: some View {
        if viewModel.selectedSpatialItem != nil {
            InboxSpatialInspector(viewModel: viewModel)
                .padding(.top, DS.space16)
                .padding(.trailing, DS.space20)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topTrailing)))
                .zIndex(2)
        }
    }

    private var spatialBackground: some View {
        DS.bg
    }
}

private struct InboxSoftClusterView: View {
    let cluster: InboxSoftCluster
    @Bindable var viewModel: InboxViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            header
            if !cluster.isCollapsed {
                Divider()
                    .background(DS.sepiaSubtle)
                cards
            }
        }
        .padding(DS.space16)
        .background(clusterBackground)
        .overlay(clusterBorder)
        .dsRestingShadow()
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DS.space10) {
            Image(systemName: cluster.kind.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(cluster.kind.accent)
                .frame(width: 28, height: 28)
                .background(cluster.kind.accent.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(cluster.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                Text("\(cluster.subtitle) · \(cluster.itemCount) item\(cluster.itemCount == 1 ? "" : "s")")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: DS.space8)

            if cluster.canBatchPlace {
                Button("Place all") {
                    Task { await viewModel.executeSoftCluster(cluster) }
                }
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(DS.accent)
            }

            Button {
                withAnimation(ProMotionSprings.gentle) {
                    viewModel.toggleSoftCluster(cluster)
                }
            } label: {
                Image(systemName: cluster.isCollapsed ? "chevron.down" : "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(cluster.isCollapsed ? "Expand cluster" : "Collapse cluster")
        }
    }

    /// Single-column stack — items are full-width inside the cluster card so
    /// preview text is actually readable and rows align flush across the row.
    private var cards: some View {
        LazyVStack(spacing: DS.space10) {
            ForEach(cluster.inboxItemIds, id: \.self) { uuid in
                if let item = viewModel.items.first(where: { $0.uuid == uuid }) {
                    InboxSpatialItemCard(
                        item: item,
                        isSelected: viewModel.selectedSpatialItem == .inboxItem(item.uuid),
                        isProcessing: viewModel.processingItemIds.contains(item.uuid),
                        onSelect: { viewModel.selectInboxItem(item) },
                        onAccept: { Task { await viewModel.acceptSuggestion(for: item) } }
                    )
                }
            }

            ForEach(cluster.databaseAtomIds, id: \.self) { uuid in
                if let item = viewModel.unplacedDatabaseItems.first(where: { $0.uuid == uuid }) {
                    InboxSpatialDatabaseCard(
                        item: item,
                        isSelected: viewModel.selectedSpatialItem == .databaseAtom(item.uuid),
                        onSelect: { viewModel.selectDatabaseItem(item) }
                    )
                }
            }
        }
    }

    private var clusterBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(DS.vellum)
    }

    private var clusterBorder: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(DS.sepiaBorder, lineWidth: 0.5)
    }
}
