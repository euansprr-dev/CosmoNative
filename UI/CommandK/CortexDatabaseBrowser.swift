// CosmoOS/UI/CommandK/CortexDatabaseBrowser.swift
// Spotlight-style document thumbnail grid with full content previews

import SwiftUI

struct CortexDatabaseBrowser: View {
    @ObservedObject var viewModel: CommandKViewModel
    @StateObject private var libraryVM = LibraryViewModel()
    @State private var hasAppeared = false
    @State private var selectedUUID: String?

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        content
        .task {
            await libraryVM.loadLibrary()
            if selectedUUID == nil {
                selectedUUID = visibleItems.first?.uuid
            }
            withAnimation(ProMotionSprings.cardEntrance) { hasAppeared = true }
        }
        .onChange(of: visibleItems.map(\.uuid)) { _, uuids in
            if selectedUUID == nil || !uuids.contains(selectedUUID ?? "") {
                selectedUUID = uuids.first
            }
        }
    }

    private var visibleItems: [LibraryItem] {
        CommandKDatabaseBrowserDataSource.visibleItems(
            allItems: libraryVM.allItems,
            displayItems: libraryVM.displayItems,
            recentlyDeletedItems: libraryVM.recentlyDeletedItems,
            isAtHome: libraryVM.isAtHome,
            showingRecentlyDeleted: libraryVM.showingRecentlyDeleted
        )
    }

    @ViewBuilder
    private var content: some View {
        if libraryVM.isLoading {
            skeletonGrid
        } else if visibleItems.isEmpty {
            emptyState
        } else {
            browserSurface
        }
    }

    private var selectedItem: LibraryItem? {
        if let selectedUUID, let item = visibleItems.first(where: { $0.uuid == selectedUUID }) {
            return item
        }
        return visibleItems.first
    }

    // MARK: - Thumbnail Grid

    private var browserSurface: some View {
        HStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                        CommandKDatabaseObjectCard(
                            item: item,
                            isSelected: item.uuid == selectedItem?.uuid
                        ) {
                            withAnimation(ProMotionSprings.snappy) {
                                selectedUUID = item.uuid
                            }
                        } onOpen: {
                            openItem(item)
                        } onDelete: {
                            libraryVM.softDeleteItem(uuid: item.uuid)
                        }
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 8)
                        .animation(index < 24 ? ProMotionSprings.staggered(index: index) : .none, value: hasAppeared)
                    }
                }
                .padding(DS.space16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().foregroundStyle(DS.glassBorder.opacity(0.72))

            if let selectedItem {
                CommandKDatabasePreviewPane(item: selectedItem) {
                    openItem(selectedItem)
                }
                .frame(width: 226)
            }
        }
        .frame(minHeight: 470)
    }

    // MARK: - Skeleton

    private var skeletonGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 14) {
            ForEach(0..<15, id: \.self) { _ in
                VStack(spacing: DS.space4) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DS.glassCardFill.opacity(0.3))
                        .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(DS.glassCardFill.opacity(0.2))
                        .frame(height: 10)
                }
            }
        }
        .padding(DS.space16)
    }

    private var emptyState: some View {
        VStack(spacing: DS.space8) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
            Text("No items yet")
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.space32)
    }

    // MARK: - Navigation

    private func openItem(_ item: LibraryItem) {
        if item.isFolder {
            libraryVM.navigateIntoFolder(item)
            return
        }
        if item.kind == .thinkspace {
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.navigateToThinkspaceById,
                object: nil,
                userInfo: CosmoNotification.Navigation.ThinkspacePayload(thinkspaceId: item.uuid).userInfo
            )
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.hideCommandK, object: nil)
            return
        }
        Task { try? await NodeGraphEngine.shared.recordAccess(atomUUID: item.uuid, type: .view) }
        NotificationCenter.default.post(
            name: CosmoNotification.NodeGraph.openAtomFromCommandK,
            object: nil, userInfo: ["atomUUID": item.uuid]
        )
        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.hideCommandK, object: nil)
    }
}

// MARK: - Polished Database Cards

private struct CommandKDatabaseObjectCard: View {
    let item: LibraryItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: DS.space12) {
                HStack(spacing: DS.space8) {
                    Image(systemName: item.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(item.color)
                        .frame(width: 16)
                        .accessibilityHidden(true)
                    Text(item.typeName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DS.textSecondary)
                    Spacer()
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.textMuted)
                        .accessibilityHidden(true)
                }

                Text(item.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DS.text)
                    .lineLimit(2)
                    .frame(height: 38, alignment: .topLeading)

                CommandKLibraryThumbnail(item: item, cornerRadius: 8)
                    .frame(height: 136)

                HStack {
                    Text(item.relativeDate)
                    Spacer()
                    if item.childCount > 0 || item.blockCount > 0 {
                        Label("\(max(item.childCount, item.blockCount))", systemImage: "photo")
                            .labelStyle(.titleAndIcon)
                    }
                }
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(DS.textMuted)
            }
            .padding(14)
            .frame(height: 252)
            .background(cardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? item.color.opacity(0.62) : DS.glassBorder.opacity(0.64), lineWidth: isSelected ? 1.1 : 0.5)
            )
            .shadow(color: Color.black.opacity(isHovered ? 0.08 : 0.035), radius: isHovered ? 14 : 8, x: 0, y: isHovered ? 6 : 2)
            .scaleEffect(isHovered ? 1.006 : 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(ProMotionSprings.hover, value: isHovered)
        .commandKCardContextMenu(
            atomUUID: item.uuid,
            entityId: item.entityId,
            atomType: item.atomType,
            isThinkspace: item.kind == .thinkspace,
            allowsSpatialGoToObject: item.kind != .thinkspace,
            onDelete: onDelete
        )
        .accessibilityLabel("\(item.title), \(item.typeName)")
    }

    private var cardFill: some ShapeStyle {
        LinearGradient(
            colors: [
                DS.glassCardFill.opacity(isSelected ? 0.76 : 0.46),
                DS.vellum.opacity(isSelected ? 0.52 : 0.30),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct CommandKDatabasePreviewPane: View {
    let item: LibraryItem
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            HStack(spacing: DS.space8) {
                Image(systemName: item.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(item.color)
                    .accessibilityHidden(true)
                Text(item.typeName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.textSecondary)
                Spacer()
            }

            VStack(alignment: .leading, spacing: DS.space4) {
                Text(item.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(2)

                Text([item.relativeDate, item.statusBadge].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(DS.textMuted)
            }

            CommandKLibraryThumbnail(item: item, cornerRadius: 8)
                .frame(height: 174)
                .shadow(color: Color.black.opacity(0.10), radius: 16, x: 0, y: 8)

            quickActions

            metadata

            Spacer(minLength: 0)
        }
        .padding(DS.space16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DS.glassCardFill.opacity(0.22))
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text("Quick actions")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.textSecondary)

            VStack(spacing: DS.space6) {
                previewAction("Open", icon: "arrow.up.right.square", isPrimary: true, action: onOpen)
                previewAction("Attach", icon: "paperclip", isPrimary: false, action: {})
                previewAction("Canvas", icon: "square.grid.2x2", isPrimary: false, action: {})
            }
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            metadataRow("Linked to", value: item.provenanceSummary ?? "No spaces")
            metadataRow("Updated", value: item.relativeDate)
            if !item.thinkspaceNames.isEmpty {
                HStack(spacing: DS.space6) {
                    ForEach(item.thinkspaceNames.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.textSecondary)
                            .padding(.horizontal, DS.space8)
                            .padding(.vertical, 4)
                            .background(DS.vellumDeep.opacity(0.70), in: Capsule())
                    }
                }
            }
        }
        .font(.system(size: 11, weight: .regular))
        .foregroundStyle(DS.textMuted)
        .padding(DS.space12)
        .background(DS.glassCardFill.opacity(0.34), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.glassBorder.opacity(0.58), lineWidth: 0.5)
        )
    }

    private func metadataRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
        }
    }

    private func previewAction(_ title: String, icon: String, isPrimary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .opacity(isPrimary ? 0 : 0.65)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(isPrimary ? .white : DS.text)
            .padding(.horizontal, DS.space10)
            .frame(height: 34)
            .background(isPrimary ? item.color : DS.glassCardFill.opacity(0.34), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isPrimary ? Color.white.opacity(0.22) : DS.glassBorder.opacity(0.62), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

struct CommandKLibraryThumbnail: View {
    let item: LibraryItem
    var cornerRadius: CGFloat = 8

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(DS.glassCardFill.opacity(0.50))
            thumbnailContent
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(DS.glassBorder.opacity(0.64), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if let thumbnailURL = item.thumbnailURL, !thumbnailURL.isEmpty {
            SpotlightImageContent(urlString: thumbnailURL)
        } else if item.atomType == .connection {
            SpotlightConnectionPreview(preview: item.preview, accentColor: item.color)
        } else if let preview = item.preview, !preview.isEmpty,
                  item.atomType != .project, item.atomType != .thinkspace {
            SpotlightPageContent(text: preview, accentColor: item.color)
        } else if item.atomType == .project || item.atomType == .thinkspace {
            SpotlightFolderContent(item: item)
        } else {
            SpotlightFauxPage(accentColor: item.color)
        }
    }
}

enum CommandKDatabaseBrowserDataSource {
    static func visibleItems(
        allItems: [LibraryItem],
        displayItems: [LibraryItem],
        recentlyDeletedItems: [LibraryItem],
        isAtHome: Bool,
        showingRecentlyDeleted: Bool
    ) -> [LibraryItem] {
        if showingRecentlyDeleted {
            return recentlyDeletedItems
        }

        return isAtHome ? allItems : displayItems
    }
}

// MARK: - Spotlight Document Card

struct SpotlightDocCard: View {
    let item: LibraryItem
    let onTap: () -> Void
    var onDelete: (() -> Void)?
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: DS.space4) {
                spotlightThumbnail
                cardLabel
            }
        }
        .buttonStyle(.plain)
        .contentShape(.rect(cornerRadius: 8))
        .onHover { isHovered = $0 }
        .animation(ProMotionSprings.hover, value: isHovered)
        .accessibilityLabel(item.title)
        .commandKCardContextMenu(
            atomUUID: item.uuid,
            entityId: item.entityId,
            atomType: item.atomType,
            isThinkspace: item.kind == .thinkspace,
            allowsSpatialGoToObject: item.kind != .thinkspace,
            onDelete: onDelete
        )
    }

    private var cardLabel: some View {
        VStack(spacing: 1) {
            Text(item.title)
                .font(DS.caption2)
                .foregroundStyle(DS.text)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(item.typeName)
                .font(DS.caption2)
                .foregroundStyle(colorForType)
        }
    }

    // MARK: - Thumbnail

    private var spotlightThumbnail: some View {
        ZStack(alignment: .bottomTrailing) {
            thumbnailBackground
            typeBadge
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isHovered ? colorForType.opacity(0.4) : DS.border.opacity(0.15),
                    lineWidth: 0.5
                )
        )
        .shadow(
            color: .black.opacity(isHovered ? 0.12 : 0.04),
            radius: isHovered ? 8 : 3, x: 0,
            y: isHovered ? 3 : 1
        )
    }

    private var thumbnailBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DS.glassCardFill.opacity(isHovered ? 0.8 : 0.5))
            thumbnailContent
        }
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if let thumbnailURL = item.thumbnailURL, !thumbnailURL.isEmpty {
            SpotlightImageContent(urlString: thumbnailURL)
        } else if item.atomType == .connection {
            SpotlightConnectionPreview(preview: item.preview, accentColor: colorForType)
        } else if let preview = item.preview, !preview.isEmpty,
                  item.atomType != .project, item.atomType != .thinkspace {
            SpotlightPageContent(text: preview, accentColor: colorForType)
        } else if item.atomType == .project || item.atomType == .thinkspace {
            SpotlightFolderContent(item: item)
        } else {
            SpotlightFauxPage(accentColor: colorForType)
        }
    }

    private var typeBadge: some View {
        Image(systemName: item.icon)
            .font(.system(size: 7, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 14, height: 14)
            .background(colorForType, in: Circle())
            .padding(4)
            .accessibilityHidden(true)
    }

    private var colorForType: Color {
        switch item.atomType {
        case .idea: return DS.entityIdea
        case .task: return DS.entityTask
        case .research: return DS.entityResearch
        case .content: return DS.entityContent
        case .connection: return DS.entityConnection
        case .project: return DS.entityIdea
        case .image: return DS.entityImage
        default: return DS.textSecondary
        }
    }
}

// MARK: - Mini Document Page (full text at thumbnail scale)

struct SpotlightPageContent: View {
    let text: String
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Colored header accent bar
            RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                .fill(accentColor.opacity(0.4))
                .frame(height: 2)

            // Full text rendered tiny — creates document texture
            Text(text)
                .font(.system(size: 4, weight: .regular))
                .foregroundStyle(Color(white: 0.25))
                .multilineTextAlignment(.leading)
                .lineSpacing(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white.opacity(0.9))
        )
        .padding(4)
    }
}

// MARK: - Connection Preview (miniature section cards)

struct SpotlightConnectionPreview: View {
    let preview: String?
    let accentColor: Color

    // Section definitions matching the connection focus mode
    private static let sectionDefs: [(key: String, label: String, color: Color)] = [
        ("IDEA", "Idea", Color(hex: "#6B6EA8")),
        ("BELIEF", "Belief", Color(hex: "#5B84B0")),
        ("GOAL", "Goal", Color(hex: "#38B764")),
        ("PROBLEMS", "Problems", Color(hex: "#D97706")),
        ("BENEFIT", "Benefits", Color(hex: "#38B764").opacity(0.8)),
        ("OBJECTIONS", "Objections", Color(hex: "#8B6BAB")),
        ("EXAMPLE", "Examples", Color(hex: "#D17B4F")),
        ("PROCESS", "Process", Color(hex: "#5B84B0").opacity(0.8)),
        ("NOTES", "Notes", Color(hex: "#9B8A6E")),
    ]

    private var sections: [(label: String, color: Color, hasContent: Bool)] {
        guard let preview, !preview.isEmpty else {
            // No data — show all sections as empty
            return Self.sectionDefs.map { ($0.label, $0.color, false) }
        }
        let blocks = Set(preview.components(separatedBy: "\n\n").compactMap {
            $0.components(separatedBy: "\n").first
        })
        return Self.sectionDefs.map { def in
            (def.label, def.color, blocks.contains(def.key))
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                sectionBar(section)
            }
            Spacer(minLength: 0)
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(white: 0.12))
        )
        .padding(4)
    }

    private func sectionBar(_ section: (label: String, color: Color, hasContent: Bool)) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(section.color)
                .frame(width: 3, height: 3)
            Text(section.label)
                .font(.system(size: 3.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.7))
            Spacer(minLength: 0)
            if section.hasContent {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(section.color.opacity(0.3))
                    .frame(width: 8, height: 3)
            }
        }
        .padding(.horizontal, 3)
        .padding(.vertical, section.hasContent ? 3 : 2)
        .background(
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.white.opacity(section.hasContent ? 0.08 : 0.04))
        )
    }
}

// MARK: - Faux Page (empty atoms — simulates blank document)

struct SpotlightFauxPage: View {
    let accentColor: Color

    private let lineWidths: [CGFloat] = [1.0, 0.85, 0.92, 0.7, 0.95, 0.6, 0.88, 0.45]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                .fill(accentColor.opacity(0.3))
                .frame(height: 2)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(lineWidths.enumerated()), id: \.offset) { _, fraction in
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(Color(white: 0.25).opacity(0.15))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 2)
                        .scaleEffect(x: fraction, anchor: .leading)
                }
            }
            .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white.opacity(0.9))
        )
        .padding(4)
    }
}

// MARK: - Image Thumbnail

struct SpotlightImageContent: View {
    let urlString: String

    var body: some View {
        GeometryReader { geo in
            Group {
                if urlString.hasPrefix("http") {
                    asyncThumbnail
                } else {
                    localThumbnail
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .clipShape(.rect(cornerRadius: 4))
        .padding(4)
    }

    private var asyncThumbnail: some View {
        CachedAsyncImage(url: URL(string: urlString)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            case .empty:
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(DS.textMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failure:
                SpotlightFauxPage(accentColor: DS.textMuted)
            }
        }
    }

    @ViewBuilder
    private var localThumbnail: some View {
        if let nsImage = NSImage(contentsOfFile: urlString) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .accessibilityLabel("Image thumbnail")
        } else {
            SpotlightFauxPage(accentColor: DS.textMuted)
        }
    }
}

// MARK: - Folder / Thinkspace Preview

private struct SpotlightFolderContent: View {
    let item: LibraryItem

    var body: some View {
        VStack(spacing: DS.space4) {
            Image(systemName: item.atomType == .thinkspace ? "rectangle.3.group" : "folder.fill")
                .font(.system(size: 24))
                .foregroundStyle(item.color.opacity(0.7))
                .accessibilityHidden(true)

            Text(countLabel)
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white.opacity(0.9))
                .padding(4)
        )
    }

    private var countLabel: String {
        if item.atomType == .thinkspace {
            return "\(item.blockCount) block\(item.blockCount == 1 ? "" : "s")"
        }
        return "\(item.childCount) item\(item.childCount == 1 ? "" : "s")"
    }
}

// MARK: - Masonry Layout (kept for CortexSwipeBrowser)

struct CortexMasonryLayout: Layout {
    let columns: Int
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        let result = arrangeSubviews(width: width, subviews: subviews)
        return CGSize(width: width, height: result.totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            guard index < result.positions.count else { break }
            let pos = result.positions[index]
            subview.place(
                at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y),
                proposal: ProposedViewSize(width: result.columnWidth, height: nil)
            )
        }
    }

    private struct ArrangeResult {
        let positions: [CGPoint]
        let columnWidth: CGFloat
        let totalHeight: CGFloat
    }

    private func arrangeSubviews(width: CGFloat, subviews: Subviews) -> ArrangeResult {
        let totalSpacing = spacing * CGFloat(columns - 1)
        let columnWidth = max(1, (width - totalSpacing) / CGFloat(columns))
        var columnHeights = Array(repeating: CGFloat(0), count: columns)
        var positions: [CGPoint] = []

        for subview in subviews {
            let shortestCol = columnHeights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            let x = CGFloat(shortestCol) * (columnWidth + spacing)
            let y = columnHeights[shortestCol]
            positions.append(CGPoint(x: x, y: y))

            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            columnHeights[shortestCol] += size.height + spacing
        }

        let maxHeight = columnHeights.max() ?? 0
        return ArrangeResult(positions: positions, columnWidth: columnWidth, totalHeight: maxHeight)
    }
}
