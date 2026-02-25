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
    private let minCardWidth: CGFloat = 220
    private let cardSpacing: CGFloat = 16

    var body: some View {
        GeometryReader { geometry in
            let columnCount = max(2, Int(geometry.size.width / (minCardWidth + cardSpacing)))
            let totalSpacing = CGFloat(columnCount - 1) * cardSpacing + 48 // 24px padding each side
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
                .padding(24)
            }
        }
    }
}

// MARK: - Masonry Layout (Pinterest-style waterfall)

private struct MasonryLayout: Layout {
    let columnCount: Int
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 800
        let columnWidth = (width - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount)
        var columnHeights = Array(repeating: CGFloat(0), count: columnCount)

        for subview in subviews {
            let shortestColumn = columnHeights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            columnHeights[shortestColumn] += size.height + spacing
        }

        let maxHeight = columnHeights.max() ?? 0
        return CGSize(width: width, height: max(0, maxHeight - spacing))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columnWidth = (bounds.width - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount)
        var columnHeights = Array(repeating: CGFloat(0), count: columnCount)

        for subview in subviews {
            let shortestColumn = columnHeights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            let x = bounds.minX + CGFloat(shortestColumn) * (columnWidth + spacing)
            let y = bounds.minY + columnHeights[shortestColumn]

            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: columnWidth, height: nil)
            )

            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            columnHeights[shortestColumn] += size.height + spacing
        }
    }
}

// MARK: - Library Card View

private struct LibraryCardView: View {
    let item: LibraryItem
    let cardWidth: CGFloat
    var onDelete: ((LibraryItem) -> Void)?
    var isSelected: Bool = false
    var onToggleSelection: (() -> Void)? = nil
    @State private var isHovered: Bool = false
    @State private var showDeleteAlert: Bool = false

    /// Dynamic preview height based on content type
    private var previewHeight: CGFloat {
        if item.thumbnailURL != nil {
            // YouTube/website thumbnails — 16:9 aspect ratio
            return cardWidth * 9.0 / 16.0
        }
        switch item.atomType {
        case .project: return 90
        case .connection: return 100
        default: return 110
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Preview area — dynamic height
            previewArea
                .frame(height: previewHeight)
                .clipped()

            // Info area
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.text)
                    .lineLimit(2)

                if let preview = item.preview, !preview.isEmpty, item.thumbnailURL != nil {
                    // Only show body snippet if there's a thumbnail (otherwise it's already in preview area)
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
            .padding(12)
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .cardSelectionOverlay(isSelected: isSelected, accentColor: DS.accent)
        .shadow(color: .black.opacity(isHovered ? 0.4 : 0.2), radius: isHovered ? 16 : 8, y: isHovered ? 8 : 4)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovered)
        .onHover { hovering in isHovered = hovering }
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                openInFocusMode()
            } label: {
                Label("Open in Focus Mode", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            Button {
                addToCanvas()
            } label: {
                Label("Add to Canvas", systemImage: "plus.rectangle.on.rectangle")
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
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(item.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(item.color.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Preview Area

    @ViewBuilder
    private var previewArea: some View {
        ZStack {
            LinearGradient(
                colors: [item.color.opacity(0.15), item.color.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            previewContent
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        if let thumbnailURL = item.thumbnailURL,
           let url = URL(string: thumbnailURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
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
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 32))
                    .foregroundColor(Color(hex: "#FFD60A").opacity(0.6))
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var contentPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let preview = item.preview, !preview.isEmpty {
                Text(preview)
                    .font(.system(size: 12))
                    .foregroundColor(DS.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
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
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            Image(systemName: "book.fill")
                .font(.system(size: 32))
                .foregroundColor(item.color.opacity(0.6))

            if let preview = item.preview, !preview.isEmpty {
                Text(String(preview.prefix(60)))
                    .font(.system(size: 10))
                    .foregroundColor(DS.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var connectionPreview: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)

            // Connection-specific visual — two linked circles
            HStack(spacing: -6) {
                Circle()
                    .fill(Color(hex: "#8B5CF6").opacity(0.3))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "#8B5CF6").opacity(0.7))
                    )
                Circle()
                    .fill(Color(hex: "#6366F1").opacity(0.3))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "#6366F1").opacity(0.7))
                    )
            }
            .overlay(
                // Link line between them
                Rectangle()
                    .fill(Color(hex: "#8B5CF6").opacity(0.4))
                    .frame(width: 20, height: 2)
            )

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
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            Image(systemName: "folder.fill")
                .font(.system(size: 36))
                .foregroundColor(item.color.opacity(0.6))

            if item.childCount > 0 {
                Text("\(item.childCount) items")
                    .font(.system(size: 11))
                    .foregroundColor(DS.textMuted)
            }
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

    // MARK: - Card Background

    private var cardBackground: some View {
        ZStack {
            DS.surfaceElevated
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isHovered ? DS.borderActive : DS.border,
                    lineWidth: 1
                )
        }
    }

    // MARK: - Actions

    private func openInFocusMode() {
        let entityType: String
        switch item.atomType {
        case .idea: entityType = "idea"
        case .task: entityType = "task"
        case .content: entityType = "content"
        case .research: entityType = "research"
        case .connection: entityType = "connection"
        case .project: entityType = "project"
        default: entityType = "idea"
        }

        NotificationCenter.default.post(
            name: .enterFocusMode,
            object: nil,
            userInfo: ["type": entityType, "id": item.uuid]
        )
    }

    private func addToCanvas() {
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
