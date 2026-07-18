// CosmoOS/UI/FocusMode/SwipeStudy/SwipeStudyStagePane.swift
// The media stage: Instagram reel player / carousel pager / YouTube player /
// thumbnail fallback, with one quiet metadata row beneath. Content is the
// hero — no section label, no ornament.
// July 2026

import SwiftUI
import AVKit

struct SwipeStudyStagePane: View {
    @Bindable var model: SwipeStudyModel
    let atom: Atom

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            stage
            metadataRow
            processingStatusLine
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Stage

    @ViewBuilder
    private var stage: some View {
        let sourceType = model.detectSourceType(for: atom)
        Group {
            switch sourceType {
            case .youtube, .youtubeShort:
                youtubeStage
            case .instagram, .instagramReel, .instagramPost, .instagramCarousel:
                instagramStage
            default:
                thumbnailStage
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - YouTube

    @ViewBuilder
    private var youtubeStage: some View {
        if model.isPlayerActive, let videoId = model.extractVideoId(from: atom) {
            YouTubeFocusModePlayer(
                videoId: videoId,
                currentTime: $model.currentTimestamp,
                onDurationLoaded: { model.videoDuration = $0 },
                onSeek: { model.currentTimestamp = $0 }
            )
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else if let thumbnailUrl = model.extractThumbnailUrl(from: atom),
                  let url = URL(string: thumbnailUrl) {
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    model.isPlayerActive = true
                }
            } label: {
                ZStack {
                    stageImage(url: url, stableKey: "swipe-stage-\(atom.uuid)")
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Image(systemName: "play.circle.fill")
                        .font(DS.display.weight(.regular))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 8)
                        .accessibilityHidden(true)
                }
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Play video")
            .accessibilityLabel("Play video")
        } else {
            stagePlaceholder
        }
    }

    // MARK: - Instagram

    @ViewBuilder
    private var instagramStage: some View {
        VStack(spacing: DS.space10) {
            if model.isCarouselContent,
               let items = model.igMediaData?.carouselItems ?? atom.richContent?.instagramData?.carouselItems,
               !items.isEmpty {
                SwipeStudyCarouselPager(model: model, items: items)
            } else if model.isCarouselContent {
                carouselLoadingState
            } else {
                reelPlayer
            }
        }
        .onAppear {
            model.prepareInstagramStage()
        }
        .onDisappear {
            model.igPlayer?.pause()
        }
    }

    @ViewBuilder
    private var reelPlayer: some View {
        ZStack {
            if model.igIsExtractingVideo && model.igPlayer == nil {
                igThumbnail
                    .overlay(loadingOverlay("Loading video…"))
            } else if let player = model.igPlayer {
                // CosmoVideoPlayerView (AVPlayerView), never SwiftUI VideoPlayer:
                // it mounts eagerly when extraction finishes, and SwiftUI's
                // VideoPlayer aborts the app on first metadata instantiation.
                ZStack {
                    CosmoVideoPlayerView(player: player)
                    if model.igIsExtractingVideo {
                        loadingOverlay("Refreshing video link…")
                    }
                }
            } else if model.igVideoFailed {
                igThumbnail
                    .overlay(failedOverlay)
            } else {
                igThumbnail
            }
        }
        .aspectRatio(9.0 / 16.0, contentMode: .fit)
        .frame(maxWidth: 320)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(DS.glassBorder, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.07), radius: 16, x: 0, y: 10)
    }

    @ViewBuilder
    private var igThumbnail: some View {
        if let thumbURL = model.igMediaData?.thumbnailURL
            ?? model.extractThumbnailUrl(from: atom).flatMap(URL.init(string:)) {
            stageImage(url: thumbURL, stableKey: "swipe-ig-thumb-\(atom.uuid)")
                .aspectRatio(contentMode: .fill)
        } else {
            Rectangle().fill(DS.glassSectionFill)
        }
    }

    /// No slide list yet. The thumbnail IS the post's first page, so it shows
    /// clean at full opacity — loading is a quiet line BELOW the stage, in the
    /// pager's upgrade-hint grammar. A scrim only ever covers the empty glass
    /// placeholder, never real content.
    private var carouselLoadingState: some View {
        VStack(spacing: DS.space8) {
            ZStack {
                igThumbnail
                if !hasCarouselThumbnail {
                    carouselPlaceholderState
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 400)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(DS.glassBorder, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.07), radius: 16, x: 0, y: 10)

            if hasCarouselThumbnail && isCarouselLoading {
                HStack(spacing: DS.space6) {
                    ProgressView().controlSize(.small).tint(DS.textMuted)
                    Text("Loading slides…")
                        .font(DS.footnote)
                        .foregroundStyle(DS.textMuted)
                }
                .transition(.opacity)
            }
        }
        .animation(ProMotionSprings.gentle, value: isCarouselLoading)
    }

    private var hasCarouselThumbnail: Bool {
        (model.igMediaData?.thumbnailURL
            ?? model.extractThumbnailUrl(from: atom).flatMap(URL.init(string:))) != nil
    }

    private var isCarouselLoading: Bool {
        model.igIsExtractingVideo || model.isAutoTranscribing
    }

    /// Nothing displayable at all — the only case that earns stage chrome.
    @ViewBuilder
    private var carouselPlaceholderState: some View {
        if isCarouselLoading {
            loadingOverlay("Loading carousel…")
        } else {
            VStack(spacing: DS.space10) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(DS.display.weight(.regular))
                    .foregroundStyle(DS.textMuted)
                    .accessibilityHidden(true)
                Text("Carousel images not loaded")
                    .font(DS.subheadline)
                    .foregroundStyle(DS.textSecondary)
                if let url = atom.url, let openURL = URL(string: url) {
                    Button("Open on Instagram") {
                        model.openInstagramURLInPane(openURL)
                    }
                    .buttonStyle(.plain)
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.accent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.bg.opacity(0.72))
        }
    }

    private func loadingOverlay(_ message: String) -> some View {
        VStack(spacing: DS.space8) {
            ProgressView().controlSize(.small).tint(.white)
            Text(message)
                .font(DS.footnote)
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.42))
    }

    private var failedOverlay: some View {
        VStack(spacing: DS.space10) {
            Image(systemName: "video.slash")
                .font(DS.display.weight(.regular))
                .foregroundStyle(.white.opacity(0.9))
                .accessibilityHidden(true)
            Text("Couldn't load video")
                .font(DS.subheadline)
                .foregroundStyle(.white.opacity(0.9))
            if let url = atom.url, let openURL = URL(string: url) {
                Button("Open on Instagram") {
                    model.openInstagramURLInPane(openURL)
                }
                .buttonStyle(.plain)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.5))
    }

    // MARK: - Default / fallback

    @ViewBuilder
    private var thumbnailStage: some View {
        if let thumbnailUrl = model.extractThumbnailUrl(from: atom),
           let url = URL(string: thumbnailUrl) {
            stageImage(url: url, stableKey: "swipe-stage-\(atom.uuid)")
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            stagePlaceholder
        }
    }

    private var stagePlaceholder: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(DS.glassSectionFill)
            .frame(height: 200)
            .overlay(
                Image(systemName: "doc.text")
                    .font(DS.title1.weight(.regular))
                    .foregroundStyle(DS.textMuted)
                    .accessibilityHidden(true)
            )
    }

    private func stageImage(url: URL, stableKey: String) -> some View {
        CachedAsyncImage(url: url, stableKey: stableKey) { phase in
            switch phase {
            case .success(let image):
                image.resizable()
            case .failure, .empty:
                Rectangle().fill(DS.glassSectionFill)
            @unknown default:
                Rectangle().fill(DS.glassSectionFill)
            }
        }
    }

    // MARK: - Metadata row

    @ViewBuilder
    private var metadataRow: some View {
        HStack(spacing: DS.space6) {
            if let author = model.igMediaData?.authorUsername ?? atom.richContent?.author,
               !author.isEmpty {
                Text("@\(author.replacingOccurrences(of: "@", with: ""))")
                    .foregroundStyle(DS.textSecondary)
                Text("·").foregroundStyle(DS.textMuted)
            }
            Text(kindLabel)
                .foregroundStyle(DS.textMuted)
            if let urlString = atom.url, let url = URL(string: urlString) {
                Text("·").foregroundStyle(DS.textMuted)
                Button {
                    if model.isInstagramSwipe(atom) {
                        model.openInstagramURLInPane(url)
                    } else {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text(model.isInstagramSwipe(atom) ? "View on Instagram" : "Open source")
                        .foregroundStyle(DS.accent)
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help("Open the original post")
            }
            Spacer(minLength: 0)
        }
        .font(DS.subheadline)
        .frame(maxWidth: .infinity)
    }

    private var kindLabel: String {
        if model.isInstagramSwipe(atom) {
            return model.contentTypeLabel(atom: atom)
        }
        return model.sourceDescriptor(for: atom)
    }

    // MARK: - Processing status

    /// Status-specific processing copy; a stale swipe (>30 min) gets a Retry.
    @ViewBuilder
    private var processingStatusLine: some View {
        if let copy = SwipeStudyModel.processingCopy(for: atom.processingStatus) {
            HStack(spacing: DS.space8) {
                ProgressView().controlSize(.small)
                Text(SwipeStudyModel.isProcessingStale(atom) ? "Taking longer than usual" : copy)
                    .font(DS.footnote)
                    .foregroundStyle(DS.textMuted)
                if SwipeStudyModel.isProcessingStale(atom) {
                    Button("Retry") { model.retranscribeInstagram() }
                        .buttonStyle(.plain)
                        .font(DS.footnote.weight(.medium))
                        .foregroundStyle(DS.accent)
                        .accessibilityLabel("Retry processing")
                }
            }
        }
    }
}

// MARK: - Carousel pager

struct SwipeStudyCarouselPager: View {
    @Bindable var model: SwipeStudyModel
    let items: [CarouselItem]

    @State private var isHovered = false

    var body: some View {
        let safeIndex = min(max(model.carouselCurrentIndex, 0), items.count - 1)
        let shortcode = model.currentInstagramShortcode()

        VStack(spacing: DS.space8) {
            ZStack {
                carouselItemView(item: items[safeIndex], shortcode: shortcode)
                navigationArrows(safeIndex: safeIndex)
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 400)
            .background(DS.glassSectionFill)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(DS.glassBorder, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.07), radius: 16, x: 0, y: 10)
            .onHover { isHovered = $0 }

            pageLine(safeIndex: safeIndex)

            if model.isUpgradingCarousel {
                HStack(spacing: DS.space6) {
                    ProgressView().controlSize(.small).tint(DS.textMuted)
                    Text(model.carouselUpgradeHintText(loadedCount: items.count))
                        .font(DS.footnote)
                        .foregroundStyle(DS.textMuted)
                }
                .transition(.opacity)
            }
        }
        .animation(ProMotionSprings.gentle, value: model.isUpgradingCarousel)
    }

    private func navigationArrows(safeIndex: Int) -> some View {
        HStack {
            if safeIndex > 0 {
                arrow("chevron.left", label: "Previous slide") {
                    withAnimation(ProMotionSprings.snappy) { model.carouselCurrentIndex -= 1 }
                }
            }
            Spacer()
            if safeIndex < items.count - 1 {
                arrow("chevron.right", label: "Next slide") {
                    withAnimation(ProMotionSprings.snappy) { model.carouselCurrentIndex += 1 }
                }
            }
        }
        .padding(.horizontal, DS.space8)
        .opacity(isHovered || items.count > 1 ? 1 : 0)
    }

    private func arrow(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(DS.title3.weight(.semibold))
                .foregroundStyle(DS.text)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .help(label)
        .accessibilityLabel(label)
    }

    private func pageLine(safeIndex: Int) -> some View {
        Text("\(safeIndex + 1) of \(items.count)")
            .font(DS.caption.monospacedDigit())
            .foregroundStyle(DS.textMuted)
            .contentTransition(.numericText())
            .animation(ProMotionSprings.gentle, value: safeIndex)
    }

    @ViewBuilder
    private func carouselItemView(item: CarouselItem, shortcode: String?) -> some View {
        let displayURL = InstagramCarouselImageCache.displayURL(for: item, shortcode: shortcode)
        let cacheKey = InstagramCarouselImageCache.stableKey(for: item, shortcode: shortcode)

        CachedAsyncImage(url: displayURL, stableKey: cacheKey) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .failure:
                Rectangle()
                    .fill(DS.glassSectionFill)
                    .overlay(
                        Image(systemName: "photo")
                            .font(DS.title1)
                            .foregroundStyle(DS.textMuted)
                            .accessibilityHidden(true)
                    )
            case .empty:
                Rectangle()
                    .fill(DS.glassSectionFill)
                    .overlay(ProgressView().controlSize(.small))
            @unknown default:
                Rectangle().fill(DS.glassSectionFill)
            }
        }
        .frame(maxWidth: 400, maxHeight: 400)
    }
}
