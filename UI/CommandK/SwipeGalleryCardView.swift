// CosmoOS/UI/CommandK/SwipeGalleryCardView.swift
// Canonical swipe gallery card — the single source of truth for swipe card rendering.
// Reused across Command-K gallery, Creator Profile, Similar Swipes, and any future swipe grids.

import SwiftUI
import AVFoundation
import AppKit

// MARK: - SwipeGalleryCardView

struct SwipeGalleryCardView: View {
    let item: SwipeGalleryItem
    let cardWidth: CGFloat
    var isSelected: Bool = false
    var isPressed: Bool = false

    @State private var isHovered = false
    @State private var localThumbnail: NSImage?

    /// Whether this item has any displayable thumbnail (remote URL or local video fallback)
    private var hasThumbnail: Bool {
        item.thumbnailUrl != nil || localThumbnail != nil || item.instagramId != nil
    }

    /// Height of the info section below the preview (title + subtitle + badge + padding)
    private let infoSectionHeight: CGFloat = 96

    private var previewHeight: CGFloat {
        if hasThumbnail {
            switch previewAspect {
            case .wide:
                return cardWidth * 9 / 16
            case .vertical:
                return min(cardWidth * 16 / 9, 384)
            case .portrait:
                return cardWidth * 5 / 4
            }
        }
        return 92
    }

    private var totalCardHeight: CGFloat {
        previewHeight + infoSectionHeight
    }

    static func estimatedHeight(for item: SwipeGalleryItem, cardWidth: CGFloat) -> CGFloat {
        let infoHeight: CGFloat = 96
        let hasThumbnail = item.thumbnailUrl != nil || item.instagramId != nil
        let previewHeight: CGFloat
        if hasThumbnail {
            switch previewAspect(for: item) {
            case .wide:
                previewHeight = cardWidth * 9 / 16
            case .vertical:
                previewHeight = min(cardWidth * 16 / 9, 384)
            case .portrait:
                previewHeight = cardWidth * 5 / 4
            }
        } else {
            previewHeight = 80
        }
        return previewHeight + infoHeight
    }

    private enum PreviewAspect {
        case wide
        case portrait
        case vertical
    }

    private var previewAspect: PreviewAspect {
        Self.previewAspect(for: item)
    }

    private static func previewAspect(for item: SwipeGalleryItem) -> PreviewAspect {
        switch item.platform {
        case "youtube":
            return .wide
        case "youtubeShort", "youtube_short", "instagramReel", "instagram_reel":
            return .vertical
        case "instagramCarousel", "instagram_carousel", "instagramPost", "instagram_post":
            return .portrait
        case "instagram":
            if item.swipeContentFormat?.isVideoFormat == true {
                return .vertical
            }
            return .portrait
        default:
            if item.swipeContentFormat?.isVideoFormat == true {
                return .vertical
            }
            return .wide
        }
    }

    private static let platformColors: [String: Color] = [
        "youtube": Color(hex: "#FF4444"),
        "youtubeShort": Color(hex: "#FF4444"),
        "youtube_short": Color(hex: "#FF4444"),
        "instagram": Color(hex: "#C13584"),
        "instagramReel": Color(hex: "#C13584"),
        "instagramPost": Color(hex: "#C13584"),
        "instagramCarousel": Color(hex: "#C13584"),
        "instagram_reel": Color(hex: "#C13584"),
        "instagram_post": Color(hex: "#C13584"),
        "instagram_carousel": Color(hex: "#C13584"),
        "xPost": Color(hex: "#1DA1F2"),
        "twitter": Color(hex: "#1DA1F2"),
        "x_post": Color(hex: "#1DA1F2"),
        "threads": Color(hex: "#AAAAAA"),
        "website": Color(hex: "#8FC7A2"),
    ]
    private static let defaultPlatformColor = Color(hex: "#8FC7A2")

    private var platformAccentColor: Color {
        Self.platformColors[item.platform ?? ""] ?? Self.defaultPlatformColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            previewArea
                .frame(height: previewHeight)
                .clipped()

            infoSection
        }
        .frame(height: totalCardHeight)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: CommandKMetrics.cardCornerRadius, style: .continuous))
        .commandKGalleryCardChrome(
            isHovered: isHovered,
            isSelected: isSelected,
            accentColor: DS.entitySwipe
        )
        .cardSelectionOverlay(isSelected: isSelected, accentColor: DS.entitySwipe)
        .scaleEffect(isPressed ? 0.985 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovered)
        .animation(ProMotionSprings.press, value: isPressed)
        .onHover { hovering in isHovered = hovering }
        .onAppear {
            if item.thumbnailUrl == nil && item.instagramId != nil {
                generateLocalThumbnail()
            }
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.hookText ?? item.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.text)
                .lineLimit(2)

            subtitleLabel
            engagementRow
            bottomRowLabel
        }
        .padding(14)
    }

    @ViewBuilder
    private var engagementRow: some View {
        if item.likesCount != nil || item.viewsCount != nil {
            HStack(spacing: 6) {
                if let likes = item.likesCount {
                    engagementPill(icon: "heart.fill", value: formatEngagement(likes))
                }
                if let views = item.viewsCount {
                    engagementPill(icon: "play.fill", value: formatEngagement(views))
                }
                if let comments = item.commentsCount, comments > 0 {
                    engagementPill(icon: "bubble.left.fill", value: formatEngagement(comments))
                }
                Spacer()
            }
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
        .foregroundStyle(DS.entitySwipe)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(DS.entitySwipe.opacity(0.1), in: Capsule())
    }

    private func formatEngagement(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    // MARK: - Preview Area

    @ViewBuilder
    private var previewArea: some View {
        ZStack {
            platformAccentColor.opacity(0.08)

            previewContent

            VStack {
                HStack(alignment: .top) {
                    platformBadge
                    Spacer()
                    scoreBadge
                }

                Spacer()

                if let duration = item.duration, duration > 0 {
                    HStack {
                        Spacer()
                        durationBadge(duration)
                    }
                }
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private var platformBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: item.platformIcon)
                .font(.system(size: 9))
            Text(item.platformName)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(DS.text)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(DS.surfaceElevated))
        .overlay(
            Capsule()
                .stroke(DS.borderSubtle, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var scoreBadge: some View {
        if let score = item.hookScore {
            Text(String(format: "%.1f", score))
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(DS.textOnAccent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(item.scoreColor.opacity(0.85)))
        }
    }

    @ViewBuilder
    private func durationBadge(_ duration: Int) -> some View {
        Text(formatDuration(duration))
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(DS.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(DS.surfaceElevated))
            .overlay(
                Capsule()
                    .stroke(DS.borderSubtle, lineWidth: 1)
            )
    }

    // MARK: - Preview Content

    @ViewBuilder
    private var previewContent: some View {
        if let localThumb = localThumbnail {
            Image(nsImage: localThumb)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: previewHeight)
                .clipped()
        } else if let thumbnailUrl = item.thumbnailUrl, let url = URL(string: thumbnailUrl) {
            CachedAsyncImage(url: url, stableKey: item.instagramId) { phase in
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
                }
            }
        } else {
            fallbackPreview
        }
    }

    @ViewBuilder
    private var fallbackPreview: some View {
        VStack(spacing: 8) {
            if let hookText = item.hookText, !hookText.isEmpty {
                Text(hookText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                Image(systemName: item.platformIcon)
                    .font(.system(size: 30))
                    .foregroundStyle(platformAccentColor.opacity(0.5))
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Labels

    @ViewBuilder
    private var subtitleLabel: some View {
        let parts = [item.author, item.platformName].compactMap { $0 }.filter { !$0.isEmpty }

        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.system(size: 12))
                .foregroundStyle(DS.textMuted)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var bottomRowLabel: some View {
        HStack {
            if let hookType = item.hookType {
                hookTypeBadgeLabel(hookType)
            } else if item.processingStatus == "extraction_failed"
                        || item.processingStatus == SwipeProcessingService.statusNeedsManualRetry {
                extractionFailedBadge
            } else {
                processingBadge
            }

            Spacer()

            Text(relativeDate)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.textMuted)
        }
    }

    @ViewBuilder
    private func hookTypeBadgeLabel(_ hookType: SwipeHookType) -> some View {
        HStack(spacing: 4) {
            Image(systemName: hookType.iconName)
                .font(.system(size: 10))
            Text(hookType.displayName)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(hookType.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(hookType.color.opacity(0.12))
        .clipShape(Capsule())
    }

    private var extractionFailedBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 10))
            Text("Retry")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(Color(hex: "#EAB308"))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color(hex: "#EAB308").opacity(0.12))
        .clipShape(Capsule())
    }

    private var processingBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.system(size: 10))
            Text("Pending")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(Color(hex: "#64748B"))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color(hex: "#64748B").opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Helpers

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var relativeDate: String {
        guard let date = item.createdAtDate else { return item.createdAt }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func formatDuration(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // MARK: - Local Thumbnail Generation

    /// In-flight deduplication to prevent concurrent thumbnail generation for the same shortcode
    private static var inflightThumbnails: Set<String> = []
    private static let inflightLock = NSLock()

    /// Try to generate a thumbnail from the local Instagram video cache
    private func generateLocalThumbnail() {
        guard localThumbnail == nil,
              let shortcode = item.instagramId, !shortcode.isEmpty else { return }

        // Deduplicate: skip if already in-flight for this shortcode
        Self.inflightLock.lock()
        let isNew = Self.inflightThumbnails.insert(shortcode).inserted
        Self.inflightLock.unlock()
        guard isNew else { return }

        Task.detached(priority: .utility) {
            defer {
                Self.inflightLock.lock()
                Self.inflightThumbnails.remove(shortcode)
                Self.inflightLock.unlock()
            }
            if let image = await Self.thumbnailFromCache(shortcode: shortcode) {
                await MainActor.run { localThumbnail = image }
                return
            }
            if let image = await Self.extractAndCacheThumbnail(shortcode: shortcode) {
                await MainActor.run { localThumbnail = image }
            }
        }
    }

    /// Check disk cache, then try generating from cached video
    static func thumbnailFromCache(shortcode: String) async -> NSImage? {
        let thumbCache = thumbnailCacheDir()
        let thumbPath = thumbCache.appendingPathComponent("thumb-\(shortcode).jpg")
        if FileManager.default.fileExists(atPath: thumbPath.path),
           let cached = NSImage(contentsOf: thumbPath) {
            return cached
        }

        guard let videoURL = InstagramVideoLocalCache.localVideoURL(forShortcode: shortcode) else {
            return nil
        }

        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 600)

        do {
            let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

            if let tiffData = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
                try? FileManager.default.createDirectory(at: thumbCache, withIntermediateDirectories: true)
                try? jpegData.write(to: thumbPath)
            }

            return image
        } catch {
            return nil
        }
    }

    /// Re-extract media from Instagram to get fresh URLs, download first image, cache it
    static func extractAndCacheThumbnail(shortcode: String) async -> NSImage? {
        let igURL = URL(string: "https://www.instagram.com/p/\(shortcode)/")!

        do {
            let mediaData = try await InstagramMediaCache.shared.getMedia(for: igURL)

            let imageURL: URL?
            if let items = mediaData.carouselItems, !items.isEmpty,
               let first = items.first(where: { $0.mediaType == .image }) ?? items.first {
                imageURL = first.mediaURL
            } else {
                imageURL = mediaData.thumbnailURL
            }

            guard let downloadURL = imageURL else { return nil }
            let (data, _) = try await URLSession.shared.data(from: downloadURL)
            guard let nsImage = NSImage(data: data) else { return nil }

            let thumbCache = thumbnailCacheDir()
            let thumbPath = thumbCache.appendingPathComponent("thumb-\(shortcode).jpg")
            if let tiffData = nsImage.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
                try? FileManager.default.createDirectory(at: thumbCache, withIntermediateDirectories: true)
                try? jpegData.write(to: thumbPath)
            }

            return nsImage
        } catch {
            return nil
        }
    }

    private static func thumbnailCacheDir() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Cosmo/ThumbnailCache", isDirectory: true)
    }
}
