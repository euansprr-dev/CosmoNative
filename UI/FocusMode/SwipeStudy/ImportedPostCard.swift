// CosmoOS/UI/FocusMode/SwipeStudy/ImportedPostCard.swift
// Individual post card for the creator import grid
// Shows thumbnail, engagement overlay, content type badge, and selection state

import SwiftUI

struct ImportedPostCard: View {
    let post: ImportedPost
    let isSelected: Bool
    let isDuplicate: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onToggle) {
            ZStack(alignment: .topLeading) {
                thumbnailLayer
                engagementOverlay
                contentTypeBadge
                selectionIndicator
                if isDuplicate { duplicateBadge }
            }
            .clipShape(.rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? DS.entitySwipe : Color.clear,
                        lineWidth: isSelected ? 2 : 0
                    )
            )
            .shadow(color: .black.opacity(isHovered ? 0.12 : 0.06), radius: isHovered ? 8 : 4, y: 2)
            .scaleEffect(isHovered && !isDuplicate ? 1.02 : 1.0)
            .opacity(isDuplicate ? 0.5 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovered)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(isDuplicate)
        .onHover { isHovered = $0 }
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnailLayer: some View {
        if let url = post.thumbnailUrl {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 180)
                        .clipped()
                case .failure:
                    placeholderView
                case .empty:
                    ProgressView()
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                        .background(DS.bg)
                @unknown default:
                    placeholderView
                }
            }
        } else {
            placeholderView
        }
    }

    @ViewBuilder
    private var placeholderView: some View {
        Rectangle()
            .fill(DS.bg)
            .frame(height: 180)
            .overlay {
                Image(systemName: post.contentType.isVideo ? "video.fill" : "photo.fill")
                    .font(.title2)
                    .foregroundStyle(DS.textSecondary.opacity(0.5))
            }
    }

    // MARK: - Engagement Overlay

    @ViewBuilder
    private var engagementOverlay: some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                engagementPill(
                    icon: "heart.fill",
                    value: formatCount(post.engagement.likesCount)
                )
                if let views = post.engagement.viewsCount {
                    engagementPill(
                        icon: "play.fill",
                        value: formatCount(views)
                    )
                }
                engagementPill(
                    icon: "bubble.left.fill",
                    value: formatCount(post.engagement.commentsCount)
                )
                Spacer()
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private func engagementPill(icon: String, value: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.black.opacity(0.65), in: Capsule())
    }

    // MARK: - Content Type Badge

    @ViewBuilder
    private var contentTypeBadge: some View {
        HStack {
            Spacer()
            contentTypeIcon
                .padding(6)
        }
    }

    @ViewBuilder
    private var contentTypeIcon: some View {
        let (icon, label) = contentTypeInfo
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            if let count = post.carouselMediaCount {
                Text("\(count)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
            } else {
                Text(label)
                    .font(.system(size: 9, weight: .bold))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.black.opacity(0.55), in: Capsule())
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
                    ZStack {
                        Circle()
                            .fill(isSelected ? DS.entitySwipe : .white.opacity(0.8))
                            .frame(width: 22, height: 22)
                        Circle()
                            .strokeBorder(isSelected ? DS.entitySwipe : .gray.opacity(0.4), lineWidth: 1.5)
                            .frame(width: 22, height: 22)
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(8)
                    Spacer()
                }
                Spacer()
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
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DS.accent.opacity(0.85), in: Capsule())
                    .padding(6)
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
