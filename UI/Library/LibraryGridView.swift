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

    private let minTileWidth: CGFloat = 156
    private let maxTileWidth: CGFloat = 180
    private let gridSpacing: CGFloat = 28

    var body: some View {
        GeometryReader { geometry in
            let horizontalPadding = CommandKMetrics.contentPadding
            let availableWidth = max(1, geometry.size.width - horizontalPadding * 2)
            let columnCount = max(2, Int((availableWidth + gridSpacing) / (minTileWidth + gridSpacing)))
            let rawTileWidth = (availableWidth - CGFloat(columnCount - 1) * gridSpacing) / CGFloat(columnCount)
            let tileWidth = min(maxTileWidth, max(minTileWidth, rawTileWidth))
            let columns = Array(
                repeating: GridItem(.fixed(tileWidth), spacing: gridSpacing, alignment: .top),
                count: columnCount
            )

            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        CosmoFinderTileView(
                            item: item,
                            tileWidth: tileWidth,
                            onOpen: { onItemTap(item) },
                            onDelete: onItemDelete,
                            isSelected: selectedUUIDs.contains(item.uuid),
                            onToggleSelection: onToggleSelection.map { closure in { closure(item.uuid) } }
                        )
                        .onTapGesture { onItemTap(item) }
                        .onTapGesture(count: 2) { onItemDoubleTap(item) }
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        .animation(
                            ProMotionSprings.cardEntrance.delay(Double(index % 16) * 0.02),
                            value: items.count
                        )
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Finder Tile View

struct CosmoFinderTileView: View {
    let item: LibraryItem
    let tileWidth: CGFloat
    let onOpen: () -> Void
    var onDelete: ((LibraryItem) -> Void)?
    var isSelected: Bool = false
    var onToggleSelection: (() -> Void)? = nil

    @State private var isHovered = false
    @State private var showDeleteAlert = false

    private var previewHeight: CGFloat {
        min(180, max(132, tileWidth))
    }

    var body: some View {
        VStack(spacing: 8) {
            previewWell
            labelStack
        }
        .frame(width: tileWidth, alignment: .top)
        .contentShape(.rect(cornerRadius: 12))
        .onHover { isHovered = $0 }
        .animation(ProMotionSprings.hover, value: isHovered)
        .contextMenu { contextMenuContent }
        .alert("Delete \"\(item.title)\"?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                onDelete?(item)
            }
        } message: {
            Text("This item will be moved to Recently Deleted for 30 days.")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.typeName)")
    }

    private var previewWell: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isHovered || isSelected ? DS.surfaceElevated : DS.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isSelected ? item.color.opacity(0.65) : DS.border.opacity(isHovered ? 0.75 : 0.35),
                            lineWidth: isSelected ? 1.4 : 1
                        )
                )
                .shadow(
                    color: .black.opacity(isHovered ? 0.12 : 0.035),
                    radius: isHovered ? 14 : 4,
                    x: 0,
                    y: isHovered ? 8 : 2
                )

            previewContent
                .padding(item.isLibraryFolder ? 0 : 12)

            if !item.isLibraryFolder {
                typeBadge
            }
        }
        .frame(width: tileWidth, height: previewHeight)
        .scaleEffect(isHovered ? 1.018 : 1)
    }

    @ViewBuilder
    private var previewContent: some View {
        if item.isLibraryFolder {
            FinderFolderGlyph(color: item.color, count: item.childCount)
                .frame(width: tileWidth * 0.58, height: previewHeight * 0.43)
        } else if let thumbnailURL = item.thumbnailURL, !thumbnailURL.isEmpty {
            SpotlightImageContent(urlString: thumbnailURL)
        } else if item.atomType == .connection {
            SpotlightConnectionPreview(preview: item.preview, accentColor: item.color)
        } else if let preview = item.preview, !preview.isEmpty {
            SpotlightPageContent(text: preview, accentColor: item.color)
        } else {
            SpotlightFauxPage(accentColor: item.color)
        }
    }

    private var labelStack: some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                if item.isLibraryFolder {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(item.color)
                        .accessibilityHidden(true)
                }

                Text(item.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)

            Text(metadataLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.textMuted)
                .lineLimit(1)
        }
        .frame(height: 44, alignment: .top)
    }

    private var metadataLabel: String {
        if item.isLibraryFolder {
            let count = item.childCount
            return "\(count) item\(count == 1 ? "" : "s") · \(item.relativeDate)"
        }
        if let provenance = item.provenanceSummary, !provenance.isEmpty {
            return provenance
        }
        return "\(item.typeName) · \(item.relativeDate)"
    }

    private var typeBadge: some View {
        Image(systemName: item.icon)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 16, height: 16)
            .background(item.color, in: Circle())
            .padding(7)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        Button {
            if item.isLibraryFolder {
                onOpen()
            } else {
                openInFocusMode()
            }
        } label: {
            Label(item.isLibraryFolder ? "Open Folder" : "Open in Focus Mode", systemImage: item.isLibraryFolder ? "folder" : "arrow.up.left.and.arrow.down.right")
        }

        if item.kind != .cluster {
            Button {
                openAsPane()
            } label: {
                Label("Open as Pane", systemImage: "rectangle.split.2x1")
            }
        }

        if item.kind == .atom {
            Button {
                addToCanvas()
            } label: {
                Label("Add to Canvas", systemImage: "plus.rectangle.on.rectangle")
            }
        }

        if onToggleSelection != nil {
            Divider()
            Button {
                onToggleSelection?()
            } label: {
                Label(isSelected ? "Deselect" : "Select", systemImage: isSelected ? "checkmark.circle.fill" : "circle")
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
        if item.kind == .thinkspace {
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.navigateToThinkspaceById,
                object: nil,
                userInfo: CosmoNotification.Navigation.ThinkspacePayload(thinkspaceId: item.uuid).userInfo
            )
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
            return
        }

        if item.isLibraryFolder {
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

private struct FinderFolderGlyph: View {
    let color: Color
    let count: Int

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let tabWidth = size.width * 0.38
            let tabHeight = size.height * 0.22

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(color.opacity(0.78))
                    .frame(width: tabWidth, height: tabHeight)
                    .offset(x: size.width * 0.08)

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color)
                    .frame(width: size.width, height: size.height * 0.78)
                    .offset(y: tabHeight * 0.72)
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.white.opacity(0.18))
                            .frame(height: size.height * 0.12)
                            .offset(y: tabHeight * 0.72)
                    }

                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.18), in: Capsule())
                        .offset(x: size.width * 0.72, y: size.height * 0.58)
                }
            }
            .shadow(color: color.opacity(0.25), radius: 8, x: 0, y: 4)
        }
        .accessibilityHidden(true)
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
            if item.atomType == .image, let nsImage = NSImage(contentsOfFile: thumbnailURL) {
                // Local image file — load directly, contained in GeometryReader to prevent overflow
                GeometryReader { geo in
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                .frame(height: previewHeight)
                .clipped()
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
