// CosmoOS/Canvas/MediaBlockView.swift
// Borderless media block for Thinkspace canvas
// Renders research/swipe blocks WITHOUT CosmoBlockWrapper chrome
// Shows video/carousel at native aspect ratio with transcript dropdown
// Uses same media loading as SwipeStudyFocusModeView
// February 2026

import SwiftUI
import AVFoundation
import AVKit

struct MediaBlockView: View {
    let block: CanvasBlock

    @State private var atom: Atom?
    @State private var isLoading = true
    @State private var isHovered = false
    @State private var isDropdownOpen = false
    @State private var isPlayerActive = false
    @State private var currentTimestamp: TimeInterval = 0
    // Instagram local video
    @State private var localVideoURL: URL?
    @State private var igPlayer: AVPlayer?
    @State private var igIsPlaying = false
    // Generated thumbnail from local video
    @State private var generatedThumbnail: NSImage?
    // Carousel items loaded from richContent
    @State private var carouselItems: [CarouselItem]?
    @State private var carouselIndex: Int = 0
    // Resizable block size
    @State private var blockSize: CGSize

    @EnvironmentObject private var expansionManager: BlockExpansionManager

    // Resize constraints
    private let minWidth: CGFloat = 160
    private let minHeight: CGFloat = 150
    private let maxWidth: CGFloat = 800
    private let maxHeight: CGFloat = 1000

    // Text reserve below media area (title + separator + transcript toggle)
    private let textReserve: CGFloat = 65

    init(block: CanvasBlock) {
        self.block = block
        self._blockSize = State(initialValue: block.size)
    }

    /// Aspect ratio of the media area (width / height), 0 = no lock
    private var mediaAspectRatio: CGFloat {
        switch mediaType {
        case .reel: return 9.0 / 16.0
        case .youtube: return 16.0 / 9.0
        case .carousel: return 1.0
        case .generic: return 0
        }
    }

    // MARK: - Media Type Detection

    private var mediaType: CanvasBlock.MediaType {
        if let atom = atom {
            return CanvasBlock.detectMediaType(atom: atom)
        }
        let url = block.metadata["url"] ?? ""
        return CanvasBlock.detectMediaTypeFromURL(url)
    }

    // MARK: - Parsed Metadata

    private var platform: String? {
        if let sourceType = atom?.richContent?.sourceType {
            switch sourceType {
            case .instagram, .instagramReel, .instagramCarousel: return "Instagram"
            case .youtube, .youtubeShort: return "YouTube"
            case .tiktok: return "TikTok"
            case .twitter: return "Twitter"
            default: return sourceType.rawValue.capitalized
            }
        }
        return block.metadata["platform"]
    }

    private var author: String? {
        if let igAuthor = atom?.richContent?.instagramData?.authorUsername, !igAuthor.isEmpty {
            return igAuthor
        }
        return block.metadata["author"]
    }

    private var resolvedURL: String? {
        if let url = atom?.url, !url.isEmpty { return url }
        if let url = block.metadata["url"], !url.isEmpty { return url }
        return nil
    }

    private var isYouTubeContent: Bool {
        let url = resolvedURL?.lowercased() ?? ""
        return url.contains("youtube") || url.contains("youtu.be")
    }

    private var videoId: String? {
        extractYouTubeVideoId(from: resolvedURL)
    }

    private var isSwipeFile: Bool {
        block.metadata["isSwipeFile"] == "true" || atom?.isSwipeFileAtom == true
    }

    private var isInstagramContent: Bool {
        let url = resolvedURL?.lowercased() ?? ""
        return url.contains("instagram")
    }

    private var accentColor: Color {
        isSwipeFile ? Color(hex: "FFD700") : CosmoColors.blockResearch
    }

    private var transcriptText: String {
        // Match SwipeStudyFocusModeView's transcript loading logic:
        // 1. richContent.transcript (primary for Instagram/swipe)
        // 2. atom.body as JSON-encoded TranscriptSegment array
        // 3. atom.body as raw text
        if let transcript = atom?.richContent?.transcript, !transcript.isEmpty {
            return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let body = atom?.body, !body.isEmpty {
            // Body may be JSON-encoded TranscriptSegment array
            if let data = body.data(using: .utf8),
               let segments = try? JSONDecoder().decode([TranscriptSegment].self, from: data) {
                return segments.map(\.text).joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return body.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // Card + badge — selection tap on card, NO double-tap here
            // (CanvasView already handles double-tap for focus mode)
            // Removing count:2 eliminates disambiguation delay that blocks
            // child interactions (play buttons, video pause, transcript toggle)
            ZStack(alignment: .topTrailing) {
                mainCard
                swipeBadge
            }
            .frame(width: blockSize.width, height: blockSize.height)
            .onTapGesture {
                NotificationCenter.default.post(
                    name: CosmoNotification.Canvas.blockSelected,
                    object: nil,
                    userInfo: ["blockId": block.id]
                )
            }

            // Floating toolbar when selected — outside tap gesture scope
            BlockSelectionToolbar(
                blockCount: 1,
                accentColor: accentColor,
                onAIAssist: {},
                onColorChange: {},
                onSave: {},
                onEdit: {},
                onFocusMode: {
                    CosmicHaptics.shared.play(.focusEnter)
                    openFocusMode()
                },
                onDuplicate: {},
                onDelete: {
                    CosmicHaptics.shared.play(.delete)
                    NotificationCenter.default.post(
                        name: .removeBlock,
                        object: nil,
                        userInfo: ["blockId": block.id]
                    )
                }
            )
            .offset(y: block.isSelected ? -52 : -44)
            .scaleEffect(block.isSelected ? 1.0 : 0.9)
            .opacity(block.isSelected ? 1 : 0)
            .allowsHitTesting(block.isSelected)
            .animation(ProMotionSprings.snappy, value: block.isSelected)
        }
        .onAppear {
            loadAtom()
        }
        // Enforce aspect ratio during resize for reel/carousel/youtube
        .onChange(of: blockSize) { _, newSize in
            let ratio = mediaAspectRatio
            guard ratio > 0 else { return }
            // Width-primary: compute ideal height from width
            let idealMediaHeight = newSize.width / ratio
            let transcriptExtra: CGFloat = isDropdownOpen ? 160 : 0
            let idealHeight = idealMediaHeight + textReserve + transcriptExtra
            let clamped = min(max(idealHeight, CGFloat(minHeight)), maxHeight)
            if abs(clamped - newSize.height) > 1 {
                blockSize = CGSize(width: newSize.width, height: clamped)
            }
        }
    }

    // MARK: - Main Card

    private var mainCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Media area
            mediaArea
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: DS.radiusMedium,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: DS.radiusMedium
                    )
                )

            // Title + metadata section
            titleSection
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 6)

            // Thin separator
            Rectangle()
                .fill(DS.borderSubtle)
                .frame(height: 1)
                .padding(.horizontal, 8)

            // Collapsible transcript dropdown
            transcriptDropdown
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .fill(DS.surface)
                if block.isSelected {
                    RoundedRectangle(cornerRadius: DS.radiusMedium)
                        .fill(accentColor.opacity(0.03))
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .stroke(
                    block.isSelected
                        ? accentColor.opacity(0.5)
                        : (isHovered ? DS.borderActive : DS.border),
                    lineWidth: block.isSelected ? 1.5 : 1
                )
        )
        .shadow(
            color: block.isSelected
                ? accentColor.opacity(0.3)
                : (isHovered ? Color.black.opacity(0.4) : Color.black.opacity(0.2)),
            radius: block.isSelected ? 12 : (isHovered ? 16 : 8),
            y: block.isSelected ? 0 : (isHovered ? 6 : 3)
        )
        // Resize overlay (same as CosmoBlockWrapper)
        .overlay {
            SimpleResizeOverlay(
                size: $blockSize,
                blockId: block.id,
                minSize: CGSize(width: minWidth, height: minHeight),
                maxSize: CGSize(width: maxWidth, height: maxHeight)
            )
        }
        .onHover { hovering in
            withAnimation(ProMotionSprings.snappy) {
                isHovered = hovering
            }
        }
    }

    // MARK: - Swipe Badge

    @ViewBuilder
    private var swipeBadge: some View {
        if isSwipeFile {
            HStack(spacing: 3) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 8))
                Text("SWIPE")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.5)
            }
            .foregroundColor(Color(hex: "FFD700"))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color(hex: "FFD700").opacity(0.15))
            )
            .overlay(
                Capsule()
                    .stroke(Color(hex: "FFD700").opacity(0.3), lineWidth: 0.5)
            )
            .padding(.top, 8)
            .padding(.trailing, 8)
            .zIndex(10)
        }
    }

    // MARK: - Media Area

    @ViewBuilder
    private var mediaArea: some View {
        if isLoading {
            loadingPlaceholder
        } else if isPlayerActive, isYouTubeContent, let vid = videoId {
            // YouTube inline player
            youtubePlayer(videoId: vid)
        } else if isPlayerActive, let player = igPlayer {
            // Instagram reel inline player
            igVideoPlayer(player: player)
        } else if let items = carouselItems, !items.isEmpty {
            // Carousel: show first image (same as focus mode)
            carouselImageView(items: items)
        } else if let thumbnail = generatedThumbnail {
            // Generated thumbnail from local video file
            localThumbnailView(image: thumbnail)
        } else if let thumbURL = resolvedThumbnailURL {
            // Remote thumbnail URL
            thumbnailWithPlayButton(url: thumbURL)
        } else {
            iconPlaceholder
        }
    }

    // MARK: - Resolved Thumbnail URL (remote fallbacks)

    private var resolvedThumbnailURL: URL? {
        // 1. ResearchMetadata.thumbnailUrl
        if let thumb = atom?.thumbnailUrl, !thumb.isEmpty, let url = URL(string: thumb) { return url }
        // 2. RichContent thumbnailUrl
        if let thumb = atom?.richContent?.thumbnailUrl, !thumb.isEmpty, let url = URL(string: thumb) { return url }
        // 3. YouTube: construct from video ID
        if let vid = videoId, let url = URL(string: "https://img.youtube.com/vi/\(vid)/hqdefault.jpg") { return url }
        return nil
    }

    // MARK: - Loading Placeholder

    private var loadingPlaceholder: some View {
        CosmicShimmer(entityColor: accentColor, cornerRadius: 0)
            .frame(maxWidth: .infinity)
            .frame(height: mediaAreaHeight)
    }

    // MARK: - YouTube Player

    private func youtubePlayer(videoId: String) -> some View {
        YouTubeFocusModePlayer(
            videoId: videoId,
            currentTime: $currentTimestamp,
            onDurationLoaded: { _ in },
            onSeek: { time in currentTimestamp = time }
        )
        .frame(maxWidth: .infinity)
        .frame(height: mediaAreaHeight)
        .transition(.opacity)
    }

    // MARK: - Instagram Video Player (AVPlayer — same as focus mode)

    private func igVideoPlayer(player: AVPlayer) -> some View {
        ZStack {
            VideoPlayer(player: player)
                .disabled(true)

            if !igIsPlaying {
                Button {
                    player.play()
                    igIsPlaying = true
                } label: {
                    playButtonOverlay
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: mediaAreaHeight)
        .onTapGesture {
            if igIsPlaying {
                player.pause()
                igIsPlaying = false
            } else {
                player.play()
                igIsPlaying = true
            }
        }
    }

    // MARK: - Carousel Image View (same approach as focus mode)

    private func carouselImageView(items: [CarouselItem]) -> some View {
        ZStack {
            let safeIndex = min(carouselIndex, items.count - 1)
            AsyncImage(url: items[safeIndex].mediaURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: mediaAreaHeight)
                        .clipped()
                case .failure:
                    thumbnailFallback
                case .empty:
                    Rectangle()
                        .fill(Color.black.opacity(0.3))
                        .overlay(ProgressView().tint(.white))
                @unknown default:
                    thumbnailFallback
                }
            }

            // Carousel nav arrows (if multiple items)
            if items.count > 1 {
                HStack {
                    if carouselIndex > 0 {
                        Button {
                            withAnimation { carouselIndex -= 1 }
                        } label: {
                            carouselNavArrow(systemName: "chevron.left")
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    if carouselIndex < items.count - 1 {
                        Button {
                            withAnimation { carouselIndex += 1 }
                        } label: {
                            carouselNavArrow(systemName: "chevron.right")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)

                // Page dots
                VStack {
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(0..<min(items.count, 10), id: \.self) { i in
                            Circle()
                                .fill(i == carouselIndex ? Color.white : Color.white.opacity(0.4))
                                .frame(width: 4, height: 4)
                        }
                    }
                    .padding(.bottom, 6)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: mediaAreaHeight)
    }

    private func carouselNavArrow(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 22, height: 22)
            .background(.ultraThinMaterial)
            .clipShape(Circle())
    }

    // MARK: - Local Video Thumbnail

    private func localThumbnailView(image: NSImage) -> some View {
        ZStack {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: mediaAreaHeight)
                .clipped()

            Color.black.opacity(0.15)

            // Play button
            Button {
                if let url = localVideoURL {
                    let item = AVPlayerItem(url: url)
                    igPlayer = AVPlayer(playerItem: item)
                    isPlayerActive = true
                }
            } label: {
                playButtonOverlay
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .frame(height: mediaAreaHeight)
    }

    // MARK: - Remote Thumbnail with Play Button

    private func thumbnailWithPlayButton(url: URL) -> some View {
        Button {
            if isYouTubeContent {
                withAnimation(ProMotionSprings.snappy) {
                    isPlayerActive = true
                }
            } else if let localURL = localVideoURL {
                let item = AVPlayerItem(url: localURL)
                igPlayer = AVPlayer(playerItem: item)
                withAnimation(ProMotionSprings.snappy) {
                    isPlayerActive = true
                }
            } else if let urlString = resolvedURL, let openURL = URL(string: urlString) {
                NSWorkspace.shared.open(openURL)
            }
        } label: {
            ZStack {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .frame(height: mediaAreaHeight)
                            .clipped()
                    case .failure:
                        thumbnailFallback
                    case .empty:
                        Rectangle()
                            .fill(Color.black.opacity(0.3))
                            .overlay(ProgressView().tint(.white))
                    @unknown default:
                        thumbnailFallback
                    }
                }

                Color.black.opacity(0.2)
                playButtonOverlay
            }
            .frame(maxWidth: .infinity)
            .frame(height: mediaAreaHeight)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Play Button Overlay

    private var playButtonOverlay: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.5))
                .frame(width: playButtonSize, height: playButtonSize)
                .blur(radius: 1)

            Circle()
                .fill(Color.black.opacity(0.6))
                .frame(width: playButtonSize, height: playButtonSize)

            Image(systemName: "play.fill")
                .font(.system(size: playIconSize))
                .foregroundColor(.white)
                .offset(x: 1)
        }
    }

    private var playButtonSize: CGFloat {
        switch mediaType {
        case .reel: return 40
        case .youtube: return 48
        case .carousel: return 44
        case .generic: return 48
        }
    }

    private var playIconSize: CGFloat {
        switch mediaType {
        case .reel: return 16
        case .youtube: return 20
        case .carousel: return 18
        case .generic: return 20
        }
    }

    // MARK: - Thumbnail Fallback

    private var thumbnailFallback: some View {
        ZStack {
            LinearGradient(
                colors: [accentColor.opacity(0.12), DS.borderSubtle],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: mediaTypeIcon)
                .font(.system(size: 28))
                .foregroundColor(accentColor.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .frame(height: mediaAreaHeight)
    }

    // MARK: - Icon Placeholder (no thumbnail at all)

    private var iconPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 0)
                .fill(accentColor.opacity(0.06))

            VStack(spacing: 8) {
                Image(systemName: mediaTypeIcon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(accentColor.opacity(0.5))

                if let plat = platform {
                    Text(plat)
                        .font(.system(size: 10))
                        .foregroundColor(DS.textMuted)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: mediaAreaHeight)
    }

    // MARK: - Title Section

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(block.title.isEmpty ? "Untitled" : block.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            authorSourceRow
        }
    }

    @ViewBuilder
    private var authorSourceRow: some View {
        HStack(spacing: 4) {
            if let auth = author, !auth.isEmpty {
                Text(auth)
                    .font(.system(size: 10))
                    .foregroundColor(DS.textMuted)
                    .lineLimit(1)
            }

            if author != nil && platform != nil {
                Text("\u{00B7}")
                    .font(.system(size: 10))
                    .foregroundColor(DS.textMuted)
            }

            if let plat = platform, !plat.isEmpty {
                Text(plat)
                    .font(.system(size: 10))
                    .foregroundColor(DS.textMuted)
                    .lineLimit(1)
            }

            Spacer()
        }
    }

    // MARK: - Transcript Dropdown

    private var transcriptDropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    isDropdownOpen.toggle()
                }
            } label: {
                transcriptToggleLabel
            }
            .buttonStyle(.plain)

            if isDropdownOpen {
                transcriptContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var transcriptToggleLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: isDropdownOpen ? "chevron.up" : "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(accentColor)

            Text("Transcript")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.textSecondary)

            Spacer()

            if !transcriptText.isEmpty {
                let count = transcriptText.count
                Text("\(count > 1000 ? "\(count / 1000)k+" : "\(count)") chars")
                    .font(.system(size: 9))
                    .foregroundColor(DS.textMuted)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var transcriptContent: some View {
        if transcriptText.isEmpty {
            HStack {
                Spacer()
                Text("No transcript available")
                    .font(.system(size: 10))
                    .foregroundColor(DS.textMuted)
                    .italic()
                Spacer()
            }
            .padding(.vertical, 8)
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                Text(transcriptText)
                    .font(.system(size: 10))
                    .foregroundColor(DS.textSecondary)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: max(blockSize.height - mediaAreaHeight - 80, 60))
            .padding(.top, 2)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Computed Helpers

    private var mediaAreaHeight: CGFloat {
        // When transcript dropdown is open, shrink media to make room for transcript content
        let transcriptReserve: CGFloat = isDropdownOpen ? 160 : 0
        return max(blockSize.height - textReserve - transcriptReserve, 80)
    }

    private var mediaTypeIcon: String {
        switch mediaType {
        case .reel: return "play.rectangle.fill"
        case .youtube: return "play.rectangle.fill"
        case .carousel: return "square.stack.fill"
        case .generic: return "doc.richtext.fill"
        }
    }

    // MARK: - Data Loading (same approach as SwipeStudyFocusModeView)

    private func loadAtom() {
        Task {
            guard let loaded = try? await AtomRepository.shared.fetch(id: block.entityId) else {
                await MainActor.run { isLoading = false }
                return
            }

            await MainActor.run { atom = loaded }

            // Load media using the same approach as SwipeStudyFocusModeView
            await loadMedia(atom: loaded)

            await MainActor.run { isLoading = false }
        }
    }

    private func loadMedia(atom: Atom) async {
        let richContent = atom.richContent

        // 1. Carousel: load items from stored richContent (same as focus mode fast path)
        if let igData = richContent?.instagramData,
           let items = igData.carouselItems, !items.isEmpty {
            await MainActor.run { carouselItems = items }
            return
        }

        // 2. Instagram reel: check local video cache (same as focus mode fast path)
        if isInstagramContent || richContent?.sourceType == .instagramReel || richContent?.sourceType == .instagram {
            if let urlString = atom.url, let url = URL(string: urlString) {
                let shortcode = InstagramExtractor.shared.extractShortcode(from: url)
                if let shortcode, let localURL = InstagramVideoLocalCache.localVideoURL(forShortcode: shortcode) {
                    // Generate thumbnail from local video
                    let thumbnail = await generateVideoThumbnail(from: localURL)
                    await MainActor.run {
                        localVideoURL = localURL
                        generatedThumbnail = thumbnail
                    }
                    return
                }
            }
        }

        // 3. YouTube: thumbnail URL is already handled by resolvedThumbnailURL
        // 4. Other content: falls through to resolvedThumbnailURL or iconPlaceholder
    }

    /// Generate a thumbnail image from a local video file using AVAssetImageGenerator
    private func generateVideoThumbnail(from url: URL) async -> NSImage? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 800) // Limit for performance

        let time = CMTime(seconds: 0.5, preferredTimescale: 600) // Grab frame at 0.5s

        do {
            let (cgImage, _) = try await generator.image(at: time)
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            print("MediaBlockView: Failed to generate thumbnail: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Focus Mode

    private func openFocusMode() {
        NotificationCenter.default.post(
            name: .enterFocusMode,
            object: nil,
            userInfo: [
                "type": EntityType.research,
                "id": block.entityId
            ]
        )
    }

    // MARK: - YouTube Video ID Extraction

    private func extractYouTubeVideoId(from urlString: String?) -> String? {
        guard let urlString = urlString else { return nil }

        if let range = urlString.range(of: "v=") {
            let startIndex = range.upperBound
            let endIndex = urlString[startIndex...].firstIndex(of: "&") ?? urlString.endIndex
            return String(urlString[startIndex..<endIndex])
        }

        if urlString.contains("youtu.be/") {
            let components = urlString.components(separatedBy: "youtu.be/")
            if components.count > 1 {
                let idPart = components[1]
                let endIndex = idPart.firstIndex(of: "?") ?? idPart.firstIndex(of: "&") ?? idPart.endIndex
                return String(idPart[..<endIndex])
            }
        }

        if let range = urlString.range(of: "/embed/") {
            let startIndex = range.upperBound
            let endIndex = urlString[startIndex...].firstIndex(of: "?") ?? urlString.endIndex
            return String(urlString[startIndex..<endIndex])
        }

        return nil
    }
}

// MARK: - Preview

#if DEBUG
struct MediaBlockView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            CosmoColors.thinkspaceVoid
                .ignoresSafeArea()

            HStack(spacing: 24) {
                MediaBlockView(
                    block: CanvasBlock(
                        position: CGPoint(x: 100, y: 200),
                        size: CGSize(width: 220, height: 420),
                        entityType: .research,
                        entityId: 1,
                        entityUuid: "preview-reel",
                        title: "Viral Hook Breakdown",
                        metadata: [
                            "url": "https://instagram.com/reel/abc123",
                            "isSwipeFile": "true",
                            "platform": "Instagram"
                        ]
                    )
                )

                MediaBlockView(
                    block: CanvasBlock(
                        position: CGPoint(x: 400, y: 200),
                        size: CGSize(width: 320, height: 230),
                        entityType: .research,
                        entityId: 2,
                        entityUuid: "preview-yt",
                        title: "Dan Koe - How to Reinvent Your Life in 2026",
                        metadata: [
                            "url": "https://youtube.com/watch?v=example",
                            "platform": "YouTube",
                            "author": "Dan Koe",
                            "duration": "42:18"
                        ]
                    )
                )

                MediaBlockView(
                    block: CanvasBlock(
                        position: CGPoint(x: 700, y: 200),
                        size: CGSize(width: 300, height: 350),
                        entityType: .research,
                        entityId: 3,
                        entityUuid: "preview-carousel",
                        title: "10 Design Principles Every Creator Needs",
                        metadata: [
                            "url": "https://instagram.com/p/xyz789",
                            "platform": "Instagram",
                            "author": "@designhub"
                        ]
                    )
                )
            }
        }
        .environmentObject(BlockExpansionManager())
        .frame(width: 1000, height: 500)
    }
}
#endif
