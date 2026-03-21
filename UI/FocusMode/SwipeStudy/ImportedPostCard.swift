// CosmoOS/UI/FocusMode/SwipeStudy/ImportedPostCard.swift
// Individual post card for the creator import grid
// Shows thumbnail, engagement overlay, content type badge, and selection state

import SwiftUI

struct ImportedPostCard: View {
    let post: ImportedPost
    let isSelected: Bool
    let isDuplicate: Bool
    let onToggle: () -> Void
    var cardWidth: CGFloat = 220

    @State private var isHovered = false

    /// Thumbnail height based on content type aspect ratio, matching SwipeGalleryCardView
    private var thumbnailHeight: CGFloat {
        switch post.contentType {
        case .reel, .story:
            return min(cardWidth * 16 / 9, 420)
        case .carousel:
            return cardWidth * 5 / 4
        case .image, .videoPost:
            return cardWidth
        }
    }

    /// Estimated total card height for masonry distribution
    static func estimatedHeight(for post: ImportedPost, cardWidth: CGFloat) -> CGFloat {
        let thumbH: CGFloat
        switch post.contentType {
        case .reel, .story:
            thumbH = min(cardWidth * 16 / 9, 420)
        case .carousel:
            thumbH = cardWidth * 5 / 4
        case .image, .videoPost:
            thumbH = cardWidth
        }
        return thumbH
    }

    var body: some View {
        Button(action: onToggle) {
            cardContent
                .commandKGalleryCardChrome(
                    isHovered: isHovered,
                    isSelected: isSelected,
                    accentColor: DS.entitySwipe,
                    cornerRadius: CommandKMetrics.cardCornerRadius
                )
                .contentShape(.rect(cornerRadius: CommandKMetrics.cardCornerRadius))
                .scaleEffect(isHovered && !isDuplicate ? 1.02 : 1.0)
                .saturation(isDuplicate ? 0.3 : 1.0)
                .opacity(isDuplicate ? 0.6 : 1.0)
                .animation(ProMotionSprings.hover, value: isHovered)
                .animation(ProMotionSprings.snappy, value: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(isDuplicate)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var cardContent: some View {
        ZStack(alignment: .topLeading) {
            thumbnailLayer
            bottomGradient
            engagementOverlay
            contentTypeBadge
            selectionIndicator
            if isDuplicate { duplicateBadge }
        }
        .clipShape(.rect(cornerRadius: CommandKMetrics.cardCornerRadius))
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnailLayer: some View {
        if let url = post.thumbnailUrl {
            CachedAsyncImage(url: url, stableKey: post.shortcode) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: thumbnailHeight)
                        .clipped()
                case .failure:
                    placeholderView
                case .empty:
                    ProgressView()
                        .frame(height: thumbnailHeight)
                        .frame(maxWidth: .infinity)
                        .background(DS.surface)
                }
            }
        } else {
            placeholderView
        }
    }

    @ViewBuilder
    private var placeholderView: some View {
        Rectangle()
            .fill(DS.surface)
            .frame(height: thumbnailHeight)
            .overlay {
                Image(systemName: post.contentType.isVideo ? "video.fill" : "photo.fill")
                    .font(.title2)
                    .foregroundStyle(DS.textSecondary.opacity(0.5))
            }
    }

    // MARK: - Bottom Gradient

    @ViewBuilder
    private var bottomGradient: some View {
        VStack {
            Spacer()
            LinearGradient(
                colors: [.clear, .black.opacity(0.25)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 60)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Engagement Overlay

    @ViewBuilder
    private var engagementOverlay: some View {
        VStack {
            Spacer()
            HStack(spacing: 6) {
                engagementPill(
                    icon: "heart.fill",
                    value: formatCount(post.engagement.likesCount)
                )
                viewsPill
                engagementPill(
                    icon: "bubble.left.fill",
                    value: formatCount(post.engagement.commentsCount)
                )
                Spacer()
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private var viewsPill: some View {
        if let views = post.engagement.viewsCount {
            engagementPill(
                icon: "play.fill",
                value: formatCount(views)
            )
        }
    }

    @ViewBuilder
    private func engagementPill(icon: String, value: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(DS.caption2)
            Text(value)
                .font(DS.caption2)
        }
        .foregroundStyle(DS.text)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(DS.surfaceElevated.opacity(0.92), in: Capsule())
    }

    // MARK: - Content Type Badge

    @ViewBuilder
    private var contentTypeBadge: some View {
        HStack {
            Spacer()
            contentTypeLabel
                .padding(8)
        }
    }

    @ViewBuilder
    private var contentTypeLabel: some View {
        let (icon, label) = contentTypeInfo
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(DS.caption2)
            contentTypeBadgeText(label)
        }
        .foregroundStyle(DS.text)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(DS.surfaceElevated.opacity(0.92), in: Capsule())
    }

    @ViewBuilder
    private func contentTypeBadgeText(_ label: String) -> some View {
        if let count = post.carouselMediaCount {
            Text("\(count)")
                .font(DS.caption2)
        } else {
            Text(label)
                .font(DS.caption2)
        }
    }

    private var contentTypeInfo: (String, String) {
        switch post.contentType {
        case .reel: return ("play.rectangle.fill", "Reel")
        case .carousel: return ("square.stack.fill", "Slides")
        case .image: return ("photo.fill", "Photo")
        case .videoPost: return ("video.fill", "Video")
        case .story: return ("circle.dashed", "Story")
        }
    }

    // MARK: - Selection Indicator

    @ViewBuilder
    private var selectionIndicator: some View {
        if !isDuplicate {
            VStack {
                HStack {
                    selectionCircle
                        .padding(8)
                    Spacer()
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var selectionCircle: some View {
        ZStack {
            Circle()
                .fill(isSelected ? DS.entitySwipe : DS.surfaceElevated)
                .frame(width: 22, height: 22)
            Circle()
                .strokeBorder(isSelected ? DS.entitySwipe : DS.borderSubtle, lineWidth: 1.5)
                .frame(width: 22, height: 22)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(DS.caption)
                    .foregroundStyle(DS.textOnAccent)
            }
        }
    }

    // MARK: - Duplicate Badge

    @ViewBuilder
    private var duplicateBadge: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Text("Already saved")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textOnAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DS.accent.opacity(0.85), in: Capsule())
                    .padding(8)
            }
        }
    }

    // MARK: - Helpers

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}
