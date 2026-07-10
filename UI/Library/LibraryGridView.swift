// CosmoOS/UI/Library/LibraryGridView.swift
// Masonry card grid for the Library — Pinterest-style waterfall layout
// Shows thumbnails/previews per atom type with type badges and relative dates

import SwiftUI

struct LibraryGridView: View {
    let items: [LibraryItem]
    let onItemTap: (LibraryItem) -> Void
    let onItemDoubleTap: (LibraryItem) -> Void
    var onItemDelete: ((LibraryItem) -> Void)? = nil
    var selectedUUIDs: Set<String> = []
    var onToggleSelection: ((String) -> Void)? = nil

    // Responsive columns based on available width
    private let minCardWidth: CGFloat = 248
    private let cardSpacing: CGFloat = CommandKMetrics.cardSpacing

    var body: some View {
        GeometryReader { geometry in
            let columnCount = max(2, Int(geometry.size.width / (minCardWidth + cardSpacing)))
            let totalSpacing = CGFloat(columnCount - 1) * cardSpacing + (CommandKMetrics.contentPadding * 2)
            let cardWidth = (geometry.size.width - totalSpacing) / CGFloat(columnCount)

            ScrollView {
                MasonryLayout(columnCount: columnCount, spacing: cardSpacing) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        LibraryCardView(
                            item: item,
                            cardWidth: cardWidth,
                            onDelete: onItemDelete,
                            isSelected: selectedUUIDs.contains(item.uuid),
                            onToggleSelection: onToggleSelection.map { closure in { closure(item.uuid) } }
                        )
                            .onTapGesture { onItemTap(item) }
                            .onTapGesture(count: 2) { onItemDoubleTap(item) }
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            .animation(
                                ProMotionSprings.cardEntrance.delay(Double(index % 12) * 0.03),
                                value: items.count
                            )
                    }
                }
                .padding(CommandKMetrics.contentPadding)
            }
        }
    }
}

// MARK: - Masonry Layout (Pinterest-style waterfall)

struct MasonryLayout: Layout {
    let columnCount: Int
    let spacing: CGFloat

    struct CacheData {
        var sizes: [CGSize] = []
    }

    func makeCache(subviews: Subviews) -> CacheData {
        CacheData()
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheData) -> CGSize {
        let width = proposal.width ?? 800
        let columnWidth = (width - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount)
        var columnHeights = Array(repeating: CGFloat(0), count: columnCount)

        // Measure all subviews once and cache the results
        cache.sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)) }

        for size in cache.sizes {
            let shortestColumn = columnHeights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            columnHeights[shortestColumn] += size.height + spacing
        }

        let maxHeight = columnHeights.max() ?? 0
        return CGSize(width: width, height: max(0, maxHeight - spacing))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheData) {
        let columnWidth = (bounds.width - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount)
        var columnHeights = Array(repeating: CGFloat(0), count: columnCount)

        // Re-measure if cache is stale
        if cache.sizes.count != subviews.count {
            cache.sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)) }
        }

        for (index, subview) in subviews.enumerated() {
            let shortestColumn = columnHeights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            let x = bounds.minX + CGFloat(shortestColumn) * (columnWidth + spacing)
            let y = bounds.minY + columnHeights[shortestColumn]

            let size = cache.sizes[index]
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: columnWidth, height: size.height)
            )

            columnHeights[shortestColumn] += size.height + spacing
        }
    }
}

// MARK: - Library Card View

struct LibraryCardView: View {
    let item: LibraryItem
    let cardWidth: CGFloat
    var onDelete: ((LibraryItem) -> Void)?
    var isSelected: Bool = false
    var onToggleSelection: (() -> Void)? = nil
    @State private var isHovered: Bool = false
    @State private var showDeleteAlert: Bool = false

    private let cornerRadius = CommandKMetrics.cardCornerRadius

    /// Dynamic preview height based on content type
    private var previewHeight: CGFloat {
        if item.atomType == .image {
            return cardWidth * 3.0 / 4.0
        }
        if item.thumbnailURL != nil {
            // YouTube/website thumbnails — 16:9 aspect ratio
            return cardWidth * 9.0 / 16.0
        }
        switch item.atomType {
        case .project: return 104
        case .thinkspace: return 104
        case .connection: return 96
        default: return 118
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Preview area — dynamic height
            previewArea
                .frame(height: previewHeight)
                .clipped()

            // Info area
            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.text)
                    .lineLimit(2)

                if let provenance = item.provenanceSummary, !provenance.isEmpty {
                    Text(provenance)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.textMuted)
                        .lineLimit(1)
                }

                if let preview = item.preview, !preview.isEmpty, item.thumbnailURL != nil, item.atomType != .research {
                    // Only show body snippet if there's a thumbnail (otherwise it's already in preview area)
                    // Skip for research items — their body is raw transcript JSON
                    Text(preview)
                        .font(.system(size: 12))
                        .foregroundColor(DS.textMuted)
                        .lineLimit(2)
                }

                // Bottom row: type badge + date
                HStack {
                    typeBadgeLabel
                    Spacer()
                    Text(item.relativeDate)
                        .font(.system(size: 11))
                        .foregroundColor(DS.textMuted)
                }
            }
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .commandKGalleryCardChrome(
            isHovered: isHovered,
            isSelected: isSelected,
            accentColor: item.color,
            cornerRadius: cornerRadius
        )
        .cardSelectionOverlay(isSelected: isSelected, accentColor: item.color)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovered)
        .onHover { hovering in isHovered = hovering }
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                openInFocusMode()
            } label: {
                Label(item.kind == .thinkspace ? "Open Thinkspace" : "Open in Focus Mode", systemImage: item.kind == .thinkspace ? "rectangle.3.group" : "arrow.up.left.and.arrow.down.right")
            }
            Button {
                openAsPane()
            } label: {
                Label("Open as Pane", systemImage: "rectangle.split.2x1")
            }
            if item.kind == .atom {
                Button {
                    addToCanvas()
                } label: {
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
        .alert("Delete \"\(item.title)\"?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                onDelete?(item)
            }
        } message: {
            Text("This item will be moved to Recently Deleted for 30 days.")
        }
    }

    // MARK: - Type Badge

    @ViewBuilder
    private var typeBadgeLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: item.icon)
                .font(.system(size: 10))
            Text(item.typeName)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(item.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(item.color.opacity(0.10))
        .clipShape(Capsule())
    }

    // MARK: - Preview Area

    @ViewBuilder
    private var previewArea: some View {
        ZStack(alignment: .topLeading) {
            item.color.opacity(0.08)

            previewContent

            Rectangle()
                .fill(item.color.opacity(0.18))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        if let thumbnailURL = item.thumbnailURL {
            if item.atomType == .image, !thumbnailURL.hasPrefix("http") {
                // Local image file — async downsampled decode (the old sync
                // NSImage(contentsOfFile:) ran on the main thread per render),
                // contained in GeometryReader to prevent overflow
                LocalFileThumbnail(path: thumbnailURL) { image in
                    GeometryReader { geo in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                    .frame(height: previewHeight)
                    .clipped()
                } placeholder: {
                    fallbackPreview
                }
            } else if let url = URL(string: thumbnailURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        GeometryReader { geo in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width, height: geo.size.height)
                        }
                        .frame(height: previewHeight)
                        .clipped()
                    case .failure:
                        fallbackPreview
                    case .empty:
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(DS.textMuted)
                    @unknown default:
                        fallbackPreview
                    }
                }
            } else {
                fallbackPreview
            }
        } else {
            fallbackPreview
        }
    }

    @ViewBuilder
    private var fallbackPreview: some View {
        switch item.atomType {
        case .idea:
            ideaPreview
        case .content:
            contentPreview
        case .research:
            researchPreview
        case .connection:
            connectionPreview
        case .project:
            projectPreview
        case .thinkspace:
            thinkspacePreview
        default:
            defaultPreview
        }
    }

    // MARK: - Type Previews

    @ViewBuilder
    private var ideaPreview: some View {
        VStack(spacing: 8) {
            if let preview = item.preview, !preview.isEmpty {
                Text(preview)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 30))
                    .foregroundColor(item.color.opacity(0.72))
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var contentPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let preview = item.preview, !preview.isEmpty {
                Text(preview)
                    .font(.system(size: 13))
                    .foregroundColor(DS.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 32))
                        .foregroundColor(item.color.opacity(0.6))
                    Spacer()
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var researchPreview: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Image(systemName: "book.fill")
                .font(.system(size: 30))
                .foregroundColor(item.color.opacity(0.6))
            Text("Research")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.textSecondary)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var connectionPreview: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(item.color.opacity(0.7))

            if let preview = item.preview, !preview.isEmpty {
                Text(String(preview.prefix(60)))
                    .font(.system(size: 11))
                    .foregroundColor(DS.textMuted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var projectPreview: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.surfaceElevated.opacity(0.72))
                .frame(width: 68, height: 52)
                .overlay(
                    Image(systemName: "folder.fill")
                        .font(.system(size: 28))
                        .foregroundColor(item.color)
                )

            if item.childCount > 0 {
                Text("\(item.childCount) items")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.textMuted)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var thinkspacePreview: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.surfaceElevated.opacity(0.72))
                .frame(width: 68, height: 52)
                .overlay(
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 24))
                        .foregroundColor(item.color)
                )

            HStack(spacing: 10) {
                Label("\(item.nestedThinkspaceCount)", systemImage: "rectangle.stack")
                Label("\(item.blockCount)", systemImage: "square.on.square")
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(DS.textMuted)

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var defaultPreview: some View {
        VStack {
            Spacer(minLength: 0)
            Image(systemName: item.icon)
                .font(.system(size: 32))
                .foregroundColor(item.color.opacity(0.5))
            Spacer(minLength: 0)
        }
    }

    // MARK: - Actions

    private func openInFocusMode() {
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
}

// MARK: - Previews

#Preview("Library Grid View") {
    LibraryGridView(
        items: [],
        onItemTap: { _ in },
        onItemDoubleTap: { _ in }
    )
    .frame(width: 900, height: 600)
}
