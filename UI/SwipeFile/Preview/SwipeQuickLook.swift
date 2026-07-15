import SwiftUI
import AVKit

// MARK: - Frame store

/// Last-known media frames of on-screen cards, in page coordinates. A plain class
/// (not @Observable) — cells write on scroll, nothing re-renders; the quick look
/// and hero read a frame once at the moment they open or close. Main-thread only.
final class SwipeFrameStore {
    var frames: [String: CGRect] = [:]
}

/// Geometry shared by the quick look and the study hero so handoffs line up.
/// July 2026: the library quick look panel IS the post — sized to the medium's
/// honest aspect (9:16 reel, square carousel, 16:9 video) plus one footer bar.
enum SwipeQuickLookGeometry {
    static let footerHeight: CGFloat = 56

    static func panelFrame(in size: CGSize, aspect: SwipeCardAspect? = nil) -> CGRect {
        let maxWidth = max(320, size.width - 160)
        let maxHeight = size.height * 0.9

        var width: CGFloat
        var height: CGFloat

        switch aspect {
        case .vertical:
            // 9:16 reel — height-major, width re-clamped for narrow windows.
            let mediaHeight = min(maxHeight - footerHeight, 760)
            let mediaWidth = min(mediaHeight * 9 / 16, maxWidth)
            width = mediaWidth
            height = min(mediaWidth * 16 / 9, maxHeight - footerHeight) + footerHeight
        case .portrait:
            // Square carousel stage.
            let side = min(540, maxWidth, maxHeight - footerHeight)
            width = side
            height = side + footerHeight
        case .wide:
            let mediaWidth = min(760, maxWidth, (maxHeight - footerHeight) * 16 / 9)
            width = mediaWidth
            height = mediaWidth * 9 / 16 + footerHeight
        case .paper:
            width = min(480, maxWidth)
            height = min(520, maxHeight)
        case nil:
            // Legacy shape (Discover quick look).
            width = min(680, max(420, size.width - 160))
            height = min(maxHeight * 0.98, 780)
        }

        return CGRect(
            x: (size.width - width) / 2,
            y: (size.height - height) / 2,
            width: width,
            height: height
        )
    }
}

// MARK: - Quick look shell

/// Click-to-preview: the panel grows out of the clicked card's frame into a centered
/// glass panel ("the card becomes the page"). The page owns `expanded` so Esc, the
/// scrim, the close button, and Open Study all collapse through one path.
///
/// Continuity: `heroModel` renders the card's media inside the panel while it is
/// collapsed, crossfading with the real content as the frame springs — so the
/// thumbnail is what grows out of the grid and what lands back in it, never an
/// empty glass shell. The page hides the source card while the panel is up, so
/// the thumbnail visibly returns into the gap it left.
struct SwipeQuickLook<Content: View>: View {
    @Binding var expanded: Bool
    let sourceFrame: CGRect?
    var heroModel: SwipeCardModel?
    /// When set, the panel takes the medium's honest shape (reel/square/wide)
    /// instead of the legacy document shape.
    var panelAspect: SwipeCardAspect?
    let onRequestClose: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let target = SwipeQuickLookGeometry.panelFrame(in: proxy.size, aspect: panelAspect)
            let fallback = target.insetBy(
                dx: target.width * 0.04,
                dy: target.height * 0.04
            )
            // A card frame that scrolled out of the viewport is stale — fall
            // back to a centered fade rather than flying to a wrong point.
            let collapsed = sourceFrame.flatMap { $0.intersects(bounds) ? $0 : nil } ?? fallback
            let frame = expanded ? target : collapsed
            let scaleX = frame.width / max(target.width, 1)
            let scaleY = frame.height / max(target.height, 1)

            ZStack(alignment: .topLeading) {
                Color.black.opacity(expanded ? 0.30 : 0)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onRequestClose)

                ZStack {
                    content()
                        .opacity(expanded ? 1 : 0)
                    if let heroModel {
                        SwipeQuickLookHeroThumbnail(model: heroModel)
                            .opacity(expanded ? 0 : 1)
                            .allowsHitTesting(false)
                    }
                }
                // INVARIANT: the panel's LAYOUT size never animates — it is
                // always laid out at the settled target, and the card→panel
                // flight is transforms only (scale + position). Springing the
                // frame itself re-laid-out the AppKit-backed glass layer ~60×/s
                // through transient (and overshooting) sizes, and that layer
                // latches a transient size until its next invalidation — which
                // is what left previews clipped at rest: media cropped at the
                // top, the footer's Open Study button spilling past the panel.
                // (Pure-SwiftUI layout of this content is proven correct; the
                // desync lived entirely in the glass layer. July 2026.)
                .frame(width: target.width, height: target.height)
                .cosmoGlassPanel(
                    role: .floatingAssistant,
                    // Collapsed radius is compensated for the down-scale so the
                    // shrunk panel still lands on the card with its 14pt corners.
                    cornerRadius: expanded ? 24 : 14 / max(scaleX, 0.05)
                )
                .scaleEffect(x: scaleX, y: scaleY)
                .position(x: frame.midX, y: frame.midY)
            }
        }
        .onAppear(perform: expandOnMount)
        .onExitCommand(perform: onRequestClose)
    }

    private func expandOnMount() {
        guard !expanded else { return }
        if reduceMotion {
            expanded = true
            return
        }
        withAnimation(ProMotionSprings.modal) { expanded = true }
    }
}

/// The continuity layer: the card's media (already cached by the grid, so it
/// mounts without a flash) filling the collapsed panel.
private struct SwipeQuickLookHeroThumbnail: View {
    let model: SwipeCardModel

    var body: some View {
        Group {
            if model.aspect == .paper {
                Text(model.paperText ?? model.hookText)
                    .font(DS.callout)
                    .foregroundStyle(DS.textSecondary)
                    .lineSpacing(3)
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(DS.glassSectionFill)
            } else {
                CachedAsyncImage(url: model.mediaURL, stableKey: model.mediaStableKey) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty, .failure:
                        Rectangle().fill(DS.glassSectionFill)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .accessibilityHidden(true)
    }
}

// MARK: - Library content (the post, bigger — nothing else)

/// The minimal preview: the panel is the post at its honest aspect — a playing
/// reel, a swipeable square carousel, or the text page — with one footer bar:
/// who made it, and Open Study. Analysis lives in Study, not here.
struct SwipeQuickLookLibraryContent: View {
    let item: SwipeGalleryItem
    let model: SwipeCardModel
    let onStudy: () -> Void
    let onAddToCanvas: () -> Void
    let onClose: () -> Void

    var body: some View {
        // Explicit sizing — the stage gets exactly panel-minus-footer, so no
        // flexible-layout negotiation (or an overgrown AVPlayerView/image) can
        // ever swallow the footer or spill past the panel.
        // NOTE: no .contextMenu on the stage — macOS contextMenu sizes its
        // content at IDEAL size (ignoring the proposal), which let image
        // stages blow past the panel and swallow the footer.
        GeometryReader { geo in
            let stageHeight = max(0, geo.size.height - SwipeQuickLookGeometry.footerHeight)
            VStack(spacing: 0) {
                stage
                    .frame(width: geo.size.width, height: stageHeight)
                    .clipped()
                    .overlay(alignment: .topTrailing) { closeButton }
                footer
                    .frame(width: geo.size.width)
            }
        }
    }

    @ViewBuilder
    private var stage: some View {
        switch model.aspect {
        case .vertical:
            SwipeQuickLookReelStage(item: item, model: model)
        case .portrait, .wide:
            // The pager degrades to the still stage when no slides exist, so
            // multi-image posts page and single-image posts just show.
            SwipeQuickLookCarouselStage(item: item, model: model)
        case .paper:
            ScrollView {
                Text(model.paperText ?? model.hookText)
                    .font(DS.body)
                    .foregroundStyle(DS.text)
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.never)
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(.black.opacity(0.35), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(10)
        .help("Close (Esc)")
        .accessibilityLabel("Close preview")
    }

    /// Creator identity leads — the quick look is the sanctioned identity
    /// surface, so the platform mark keeps its brand color here.
    private var footer: some View {
        HStack(spacing: 8) {
            SwipePlatformGlyph(source: model.platformKey)
                .frame(width: 13, height: 13)
                .foregroundStyle(model.platformColor ?? DS.textMuted)
            Text(identityLine)
                .font(DS.subheadline.weight(.medium))
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
            if let age = model.ageLabel {
                Text("· \(age)")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            }

            Spacer(minLength: DS.space12)

            SwipeQuickLookIconButton(
                systemImage: "square.grid.2x2",
                help: "Add to Canvas",
                action: onAddToCanvas
            )

            Button(action: onStudy) {
                HStack(spacing: 7) {
                    Image(systemName: "book")
                        .font(DS.caption.weight(.bold))
                        .accessibilityHidden(true)
                    Text("Open Study")
                        .font(DS.callout.weight(.semibold))
                }
                .foregroundStyle(DS.textOnAccent)
                .padding(.horizontal, 16)
                .frame(height: 34)
                .background(DS.accent, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Open in Swipe Study (⏎)")
        }
        .padding(.horizontal, 14)
        .frame(height: SwipeQuickLookGeometry.footerHeight)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.glassBorder).frame(height: 0.5)
        }
    }

    private var identityLine: String {
        model.creatorLine
            ?? SocialPlatform.fromLibraryKey(item.platform)?.displayName
            ?? "Swipe"
    }
}

// MARK: - Reel stage (plays in place)

/// The reel, playing. Local cache first (instant), then the stored media URL
/// resolved through the local cache (downloads once), thumbnail while anything
/// is in flight. Loops; pauses the moment the preview closes.
private struct SwipeQuickLookReelStage: View {
    let item: SwipeGalleryItem
    let model: SwipeCardModel

    @State private var player: AVPlayer?
    @State private var isResolving = false
    @State private var resolveFailed = false
    @State private var loopObserver: NSObjectProtocol?

    var body: some View {
        ZStack {
            if let player {
                // CosmoVideoPlayerView (AVPlayerView), never SwiftUI VideoPlayer.
                // Floating controls: always discoverable in a preview.
                CosmoVideoPlayerView(player: player, controlsStyle: .floating)
            } else {
                SwipeQuickLookStillStage(model: model)
                if isResolving {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                        .padding(10)
                        .background(.black.opacity(0.35), in: Circle())
                }
            }
        }
        .task(id: item.id) {
            await resolveAndPlay()
        }
        .onDisappear(perform: teardown)
    }

    private func resolveAndPlay() async {
        teardown()
        resolveFailed = false

        // Fast path: the reel is already on disk.
        if let shortcode = item.instagramId,
           let localURL = InstagramVideoLocalCache.localVideoURL(forShortcode: shortcode) {
            start(with: localURL)
            return
        }

        // Slow path: stored media URL → resolve through the local cache.
        isResolving = true
        defer { isResolving = false }
        guard let atom = try? await AtomRepository.shared.fetch(uuid: item.id),
              let mediaURL = atom.richContent?.instagramData?.extractedMediaURL else {
            resolveFailed = true
            return
        }
        let playable = await InstagramVideoLocalCache.resolvePlayableURL(
            from: mediaURL,
            shortcode: item.instagramId
        )
        start(with: playable)
    }

    private func start(with url: URL) {
        let avItem = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: avItem)
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: avItem,
            queue: .main
        ) { _ in
            avPlayer.seek(to: .zero)
            avPlayer.play()
        }
        player = avPlayer
        avPlayer.play()
    }

    private func teardown() {
        player?.pause()
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
        }
        loopObserver = nil
        player = nil
    }
}

// MARK: - Carousel stage (square pager)

/// The carousel, swipeable, on a square stage. Slides load from the persisted
/// carousel items (local image cache first); a single-image post shows its one
/// image the same way.
private struct SwipeQuickLookCarouselStage: View {
    let item: SwipeGalleryItem
    let model: SwipeCardModel

    @State private var slides: [CarouselItem] = []
    @State private var index = 0
    @State private var isHovered = false

    var body: some View {
        ZStack {
            if slides.isEmpty {
                SwipeQuickLookStillStage(model: model)
            } else {
                slideImage(slides[min(index, slides.count - 1)])
                arrows
            }
        }
        .overlay(alignment: .bottom) {
            if slides.count > 1 {
                pageCounter
            }
        }
        .task(id: item.id) {
            let atom = try? await AtomRepository.shared.fetch(uuid: item.id)
            slides = atom?.richContent?.instagramData?.carouselItems ?? []
            index = 0
        }
        .onHover { isHovered = $0 }
    }

    private func slideImage(_ slide: CarouselItem) -> some View {
        let displayURL = InstagramCarouselImageCache.displayURL(for: slide, shortcode: item.instagramId)
        let cacheKey = InstagramCarouselImageCache.stableKey(for: slide, shortcode: item.instagramId)
        // Letterboxed on the warm fill, never cropped — a preview shows the
        // whole slide. The ZStack takes exactly the stage's explicit frame.
        return ZStack {
            DS.glassSectionFill
            CachedAsyncImage(url: displayURL, stableKey: cacheKey) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .empty, .failure:
                    ProgressView().controlSize(.small)
                }
            }
        }
        .id(slide.index)
        .transition(.opacity)
        .animation(ProMotionSprings.snappy, value: index)
    }

    private var arrows: some View {
        HStack {
            if index > 0 {
                arrow("chevron.left", label: "Previous slide") {
                    withAnimation(ProMotionSprings.snappy) { index -= 1 }
                }
            }
            Spacer()
            if index < slides.count - 1 {
                arrow("chevron.right", label: "Next slide") {
                    withAnimation(ProMotionSprings.snappy) { index += 1 }
                }
            }
        }
        .padding(.horizontal, DS.space8)
        .opacity(isHovered ? 1 : 0.65)
        .animation(ProMotionSprings.hover, value: isHovered)
    }

    private func arrow(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(DS.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.black.opacity(0.35), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private var pageCounter: some View {
        Text("\(index + 1) of \(slides.count)")
            .font(DS.caption.monospacedDigit())
            .foregroundStyle(.white)
            .contentTransition(.numericText())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.black.opacity(0.35), in: Capsule())
            .padding(.bottom, 10)
            .animation(ProMotionSprings.gentle, value: index)
    }
}

// MARK: - Still stage (thumbnail fill)

/// The medium's thumbnail on the stage — letterboxed on the warm fill, never
/// cropped: a preview must show the whole post.
private struct SwipeQuickLookStillStage: View {
    let model: SwipeCardModel

    var body: some View {
        ZStack {
            DS.glassSectionFill
            CachedAsyncImage(url: model.mediaURL, stableKey: model.mediaStableKey) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .empty, .failure:
                    SwipePlatformGlyph(source: model.platformKey)
                        .frame(width: 24, height: 24)
                        .foregroundStyle(DS.textMuted)
                }
            }
        }
        .accessibilityLabel("Swipe media preview")
    }
}

// MARK: - Media well (natural aspect — Discover quick look)

/// Quick-look media at the post's own aspect ratio — width-fit, height-capped,
/// edge-to-edge fill on a warm well. No black letterbox.
struct SwipeQuickLookMedia: View {
    let url: URL?
    let stableKey: String?
    let aspect: SwipeCardAspect
    var fallbackGlyph: String?

    /// The well breathes with the medium: reels get a tall stage, posts a
    /// squarer one, videos a wide one.
    private var wellHeight: CGFloat {
        switch aspect {
        case .wide: 320
        case .portrait: 380
        case .vertical: 440
        case .paper: 320
        }
    }

    var body: some View {
        CachedAsyncImage(url: url, stableKey: stableKey) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            case .empty, .failure:
                Rectangle()
                    .fill(.clear)
                    .overlay {
                        Image(systemName: fallbackGlyph ?? "photo")
                            .font(DS.title2)
                            .foregroundStyle(DS.textMuted)
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: wellHeight)
        .background(DS.glassSectionFill)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Icon button

struct SwipeQuickLookIconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(hovering ? DS.text : DS.textSecondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(hovering ? DS.glassInputFill : Color.clear))
                .overlay(Circle().strokeBorder(DS.glassBorder, lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { value in withAnimation(ProMotionSprings.hover) { hovering = value } }
        .help(help)
        .accessibilityLabel(help)
    }
}
