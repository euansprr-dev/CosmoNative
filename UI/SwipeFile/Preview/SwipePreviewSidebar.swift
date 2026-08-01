import SwiftUI
import AVKit

// MARK: - Transcript resolution

/// What the preview shows for a swipe's words, resolved in the Study's order
/// of truth: cleaned slides → timestamped speech → prose. Pure so the order
/// is testable without a database (mirrors SwipeStudyModel.loadAtom).
enum SwipePreviewTranscript: Equatable {
    case slides([TranscriptSlide])
    case speech([TranscriptSegment])
    case prose(String)
    case empty

    /// A slide list "counts" only when at least one slide carries text —
    /// voiceover-only reels ship a placeholder blank slide, never content.
    /// Shared with Swipe Study's speech-tier decision.
    static func slidesCarryText(_ slides: [TranscriptSlide]) -> Bool {
        slides.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func resolve(
        analysis: SwipeAnalysis?,
        richTranscript: String?,
        richSegments: [TranscriptSegment]?,
        body: String?
    ) -> SwipePreviewTranscript {
        if let slides = analysis?.transcriptSlides, slidesCarryText(slides) {
            return .slides(slides)
        }
        if let speech = analysis?.transcriptSpeechSegments, !speech.isEmpty {
            return .speech(speech)
        }
        if let segments = richSegments, !segments.isEmpty {
            return .speech(segments)
        }
        if let transcript = richTranscript, !transcript.isEmpty {
            return .prose(transcript)
        }
        if let body, !body.isEmpty {
            // The Research flow stores a JSON TranscriptSegment array in body.
            if let data = body.data(using: .utf8),
               let segments = try? JSONDecoder().decode([TranscriptSegment].self, from: data),
               !segments.isEmpty {
                return .speech(segments)
            }
            return .prose(body)
        }
        return .empty
    }
}

/// Which tier Swipe Study's manuscript must hydrate from persisted analysis
/// state — the editor-state twin of `SwipePreviewTranscript.resolve`, kept in
/// this file so the two can't drift into disagreeing about the same swipe.
/// They share `slidesCarryText`, and the order of truth is identical:
/// slides-that-carry-text → timestamped speech → the prose fallback.
///
/// GUARD-TWIN of `SwipePreviewTranscript.resolve` — change together.
enum SwipeStudyTranscriptTier: Equatable {
    /// Slides carry the words. Speech segments ride along when the reel has
    /// both (voiceover-plus-text) so slide rows can still seek the video.
    case slides(slides: [TranscriptSlide], raw: [TranscriptSlide], speech: [TranscriptSegment])
    /// Talking-head / voiceover-only reel: the timestamped speech IS the
    /// transcript. The worker banks it with an EMPTY slide list on purpose.
    case speech([TranscriptSegment])
    /// The analysis banked no words — parse the prose transcript into slides.
    case proseFallback

    static func resolve(analysis: SwipeAnalysis?) -> SwipeStudyTranscriptTier {
        let savedSlides = analysis?.transcriptSlides ?? []
        let savedSpeech = analysis?.transcriptSpeechSegments ?? []

        if SwipePreviewTranscript.slidesCarryText(savedSlides) {
            let savedRaw = analysis?.rawTranscriptSlides ?? []
            return .slides(
                slides: savedSlides,
                raw: savedRaw.isEmpty ? savedSlides : savedRaw,
                speech: savedSpeech
            )
        }
        if !savedSpeech.isEmpty {
            return .speech(savedSpeech)
        }
        return .proseFallback
    }
}

/// One tap-to-seek request flowing from a speech row to the playing reel.
/// A fresh id per tap so seeking to the same timestamp twice still fires.
struct SwipePreviewSeekRequest: Equatable {
    let id: UUID
    let time: TimeInterval

    init(time: TimeInterval) {
        self.id = UUID()
        self.time = time
    }
}

// MARK: - Preview sidebar

/// The Swipe File's preview rail — the Command Center rail grammar (flat
/// `DS.surface` on the page plane, one leading hairline, no glass, no
/// shadow) carrying the post at top and its words below. Selection drives
/// it: click or arrows retarget it in place, Space toggles, Esc closes,
/// double-click or Return zooms the card into full Swipe Study.
struct SwipePreviewSidebar: View {
    let item: SwipeGalleryItem
    let model: SwipeCardModel
    let onStudy: () -> Void
    let onAddToCanvas: () -> Void
    let onClose: () -> Void

    @State private var words: SwipePreviewTranscript = .empty
    @State private var isLoadingWords = true
    @State private var caption: String?
    @State private var originalURL: URL?
    @State private var seekRequest: SwipePreviewSeekRequest?

    /// The rail narrows before the catalog does — small panes keep a working grid.
    static func width(forContainerWidth total: CGFloat) -> CGFloat {
        total < 980 ? 300 : 340
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                if model.aspect != .paper {
                    mediaStage(in: geo.size)
                }
                detailScroll
                SwipeConceptBacklinks(atomUUID: item.atomUUID)
                    .padding(.horizontal, 14)
                    .padding(.vertical, DS.space6)
                artifactRetryRow
                footer
            }
            .id(item.id)
        }
        .background(DS.surface)
        .overlay(alignment: .leading) {
            Rectangle().fill(DS.borderSubtle).frame(width: 0.5)
        }
        .overlay(alignment: .topTrailing) { closeButton }
        .animation(ProMotionSprings.gentle, value: item.id)
        .task(id: item.id) { await loadWords() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Swipe preview")
    }

    // MARK: Media stage

    /// The post, honest and letterboxed, pinned above the scroll so a reel
    /// keeps playing while the transcript is read.
    private func mediaStage(in size: CGSize) -> some View {
        Group {
            switch model.aspect {
            case .vertical:
                SwipePreviewReelStage(item: item, model: model, seekRequest: seekRequest)
            case .portrait, .wide:
                SwipePreviewCarouselStage(item: item, model: model)
            case .paper:
                EmptyView()
            }
        }
        .frame(width: size.width, height: stageHeight(in: size))
        .clipped()
    }

    /// The stage is the medium's honest aspect at FULL rail width — edge to
    /// edge, no letterbox gutters. A tall reel earns a tall stage; the
    /// transcript below simply gets the rest and scrolls.
    private func stageHeight(in size: CGSize) -> CGFloat {
        switch model.aspect {
        case .vertical: return (size.width * 16 / 9).rounded()
        case .portrait: return (size.width * 5 / 4).rounded()
        case .wide: return (size.width * 9 / 16).rounded()
        case .paper: return 0
        }
    }

    // MARK: Detail scroll

    private var detailScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space16) {
                titleBlock
                if model.aspect == .paper {
                    paperSection
                } else {
                    transcriptSection
                }
                captionSection
            }
            .padding(DS.space12)
            // Paper posts have no media stage — clear the floating close button.
            .padding(.top, model.aspect == .paper ? 40 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Text(item.title)
                .font(DS.headline)
                .foregroundStyle(DS.text)
                .lineLimit(4)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            metaRow
            if let engagement = engagementLine {
                Text(engagement)
                    .font(DS.caption.monospacedDigit())
                    .foregroundStyle(DS.textMuted)
            }
        }
    }

    /// Creator identity leads — the preview is the sanctioned identity
    /// surface, so the platform mark keeps its brand color here.
    private var metaRow: some View {
        HStack(spacing: 6) {
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
            if let duration = model.durationLabel {
                Text("· \(duration)")
                    .font(DS.caption.monospacedDigit())
                    .foregroundStyle(DS.textMuted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var identityLine: String {
        model.creatorLine
            ?? SocialPlatform.fromLibraryKey(item.platform)?.displayName
            ?? "Swipe"
    }

    private var engagementLine: String? {
        var parts: [String] = []
        if let views = item.viewsCount, views > 0 { parts.append("\(SwipeFormatting.count(views)) views") }
        if let likes = item.likesCount, likes > 0 { parts.append("\(SwipeFormatting.count(likes)) likes") }
        if let comments = item.commentsCount, comments > 0 { parts.append("\(SwipeFormatting.count(comments)) comments") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Transcript

    @ViewBuilder
    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            SwipeStudyRailHeader(label: "TRANSCRIPT", count: transcriptCount)
            switch words {
            case .slides(let slides):
                ForEach(Array(slides.enumerated()), id: \.element.id) { index, slide in
                    SwipePreviewSlideCard(number: index + 1, slide: slide)
                }
            case .speech(let segments):
                speechRows(segments)
            case .prose(let text):
                SwipePreviewProseCard(text: text)
            case .empty:
                if isLoadingWords {
                    loadingSkeleton
                } else {
                    emptyTranscriptRow
                }
            }
        }
    }

    /// Same card chrome, placeholder bars — never a spinner, and never the
    /// teaching row flashing before the fetch lands.
    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            ForEach(0..<3, id: \.self) { row in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(DS.glassSectionFill)
                    .frame(height: 12)
                    .frame(maxWidth: row == 2 ? 140 : .infinity, alignment: .leading)
            }
        }
        .padding(DS.space12)
        .background(SwipeTranscriptCardPalette.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(SwipeTranscriptCardPalette.border, lineWidth: 0.5)
        )
        .accessibilityHidden(true)
    }

    /// Paper posts carry their text as the post itself — one section, no echo.
    private var paperSection: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            SwipeStudyRailHeader(label: "POST")
            SwipePreviewProseCard(text: paperText)
        }
    }

    private var paperText: String {
        if case .prose(let text) = words, !text.isEmpty { return text }
        return model.paperText ?? model.hookText
    }

    private var transcriptCount: Int? {
        switch words {
        case .slides(let slides): return slides.count
        case .speech(let segments): return segments.count
        case .prose, .empty: return nil
        }
    }

    private func speechRows(_ segments: [TranscriptSegment]) -> some View {
        SwipeSpeechTranscriptCard(
            segments: segments,
            canSeek: model.aspect == .vertical,
            onSeek: { seekRequest = SwipePreviewSeekRequest(time: $0.start) }
        )
    }

    /// Absence teaches — never a silently missing section.
    private var emptyTranscriptRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.space8) {
            Image(systemName: emptyTranscriptGlyph)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
            Text(emptyTranscriptMessage)
                .font(DS.footnote)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(DS.space10)
        .background(DS.glassSectionFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var emptyTranscriptGlyph: String {
        switch model.processing {
        case .pending: return "clock"
        case .failed: return "exclamationmark.triangle"
        case .ready: return "text.quote"
        }
    }

    private var emptyTranscriptMessage: String {
        switch model.processing {
        case .pending: return "Processing — the transcript will appear here shortly."
        case .failed: return "Extraction failed — open Study to retry."
        case .ready: return "No transcript yet — open Study to transcribe."
        }
    }

    @ViewBuilder
    private var captionSection: some View {
        if let caption, !caption.isEmpty {
            VStack(alignment: .leading, spacing: DS.space10) {
                SwipeStudyRailHeader(label: "CAPTION")
                Text(caption)
                    .font(DS.callout)
                    .foregroundStyle(DS.textSecondary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(DS.space12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SwipeTranscriptCardPalette.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(SwipeTranscriptCardPalette.border, lineWidth: 0.5)
                    )
            }
        }
    }

    // MARK: Chrome

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(model.aspect == .paper ? DS.textSecondary : .white)
                .frame(width: 26, height: 26)
                .background(
                    model.aspect == .paper ? Color.clear : .black.opacity(0.35),
                    in: Circle()
                )
                .overlay(
                    Circle().strokeBorder(
                        model.aspect == .paper ? DS.glassBorder : .clear,
                        lineWidth: 0.5
                    )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(10)
        .help("Close (Esc)")
        .accessibilityLabel("Close preview")
    }

    /// The artifact kinds' Retry seat — the manual twin of the heal sweep.
    /// Posts have their own Railway-first Retry in Study; a page or frame
    /// whose decomposition failed used to be a silent dead end.
    @ViewBuilder
    private var artifactRetryRow: some View {
        let status = item.processingStatus ?? ""
        if item.kind == .page || item.kind == .frame,
           status == "partial" || status == "extraction_failed" {
            HStack(spacing: DS.space8) {
                Image(systemName: "exclamationmark.arrow.circlepath")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.textMuted)
                    .accessibilityHidden(true)
                Text(status == "extraction_failed" ? "Couldn't capture this one" : "Reading didn't finish")
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
                Spacer(minLength: DS.space8)
                Button("Retry") { retryArtifact() }
                    .buttonStyle(.plain)
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.accent)
                    .help("Re-run the capture and analysis")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, DS.space6)
            .overlay(alignment: .top) {
                Rectangle().fill(DS.borderSubtle).frame(height: 0.5)
            }
        }
    }

    private func retryArtifact() {
        let uuid = item.id
        let kind = item.kind
        Task { @MainActor in
            // A manual retry always runs: erase the sweep's strikes first.
            var ledger = SwipeHealLedger.load()
            ledger.clear(uuid)
            ledger.save()
            guard let atom = try? await AtomRepository.shared.fetch(uuid: uuid) else { return }
            let note = atom.body?.trimmed
            switch kind {
            case .page:
                let url = atom.swipeArtifact?.capturedURL ?? atom.researchMetadata?.url
                guard let url, let pageURL = URL(string: url) else { return }
                await SwipePageDecomposition.run(swipeUUID: uuid, url: pageURL, note: note)
            case .frame:
                await SwipeFrameDecomposition.run(swipeUUID: uuid, note: note)
            default:
                break
            }
        }
    }

    private var footer: some View {
        HStack(spacing: DS.space8) {
            SwipeQuickLookIconButton(
                systemImage: "square.grid.2x2",
                help: "Add to Canvas",
                action: onAddToCanvas
            )
            AddToConceptMenu(atomUUID: item.atomUUID)
            if let originalURL {
                SwipeQuickLookIconButton(systemImage: "safari", help: "Open original post") {
                    NSWorkspace.shared.open(originalURL)
                }
            }

            Spacer(minLength: DS.space12)

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
        .frame(height: 56)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.borderSubtle).frame(height: 0.5)
        }
    }

    // MARK: Loading

    /// One atom fetch per item: transcript, caption, and the original link.
    /// Read-only — the preview never touches the editing lock, the dirty
    /// registry, or any persist path (those belong to Study).
    private func loadWords() async {
        // Belt-and-braces: card onAppear normally prewarmed this swipe's
        // media already; entry points that skip the grid (hero Preview,
        // shelf clicks) kick it here so the stage finds warm caches.
        SwipeStudyPrewarmer.shared.prewarm(uuid: item.id)
        words = .empty
        isLoadingWords = true
        defer { isLoadingWords = false }
        caption = nil
        originalURL = nil
        seekRequest = nil
        guard let atom = try? await AtomRepository.shared.fetch(uuid: item.id) else { return }
        words = SwipePreviewTranscript.resolve(
            analysis: atom.swipeAnalysis,
            richTranscript: atom.richContent?.transcript,
            richSegments: atom.richContent?.transcriptSegments,
            body: atom.body
        )
        caption = atom.richContent?.instagramData?.caption
        originalURL = atom.url.flatMap(URL.init(string:))
            ?? atom.richContent?.instagramData?.originalURL
    }
}

// MARK: - Slide card (read-only)

/// A cleaned transcript slide, read-only — the Study's card chrome without
/// any of its editing machinery.
private struct SwipePreviewSlideCard: View {
    let number: Int
    let slide: TranscriptSlide

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            HStack {
                Text(String(format: "%02d", number))
                    .font(DS.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(DS.textMuted)
                Spacer()
                if let timestamp = slide.timestamp {
                    Text(SwipeStudyRawSlideCard.formatTime(timestamp))
                        .font(DS.caption2.monospacedDigit())
                        .foregroundStyle(DS.textMuted)
                }
            }
            Text(slide.text)
                .font(DS.callout)
                .foregroundStyle(SwipeTranscriptCardPalette.text)
                .lineSpacing(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DS.space12)
        .background(SwipeTranscriptCardPalette.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(SwipeTranscriptCardPalette.border, lineWidth: 0.5)
        )
    }
}

// MARK: - Speech transcript card (shared: preview rail + Swipe Study)

/// Timestamped speech rows in one transcript-palette card — the voice of a
/// voiceover-only reel, whose transcript has no slides. Shared by the
/// preview rail and the Study manuscript so the two surfaces read as one.
struct SwipeSpeechTranscriptCard: View {
    let segments: [TranscriptSegment]
    let canSeek: Bool
    let onSeek: (TranscriptSegment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(segments) { segment in
                SwipePreviewSpeechRow(
                    segment: segment,
                    canSeek: canSeek,
                    onSeek: { onSeek(segment) }
                )
            }
        }
        .padding(.vertical, DS.space4)
        .background(SwipeTranscriptCardPalette.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(SwipeTranscriptCardPalette.border, lineWidth: 0.5)
        )
    }
}

// MARK: - Speech row (tap to seek)

/// A timestamped speech segment. On reels the timestamp is a door — tapping
/// seeks the playing video; rows stay monochrome until hover says they act.
private struct SwipePreviewSpeechRow: View {
    let segment: TranscriptSegment
    let canSeek: Bool
    let onSeek: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: { if canSeek { onSeek() } }) {
            HStack(alignment: .firstTextBaseline, spacing: DS.space8) {
                Text(segment.formattedTime)
                    .font(DS.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(canSeek && isHovered ? DS.accent : DS.textMuted)
                    .frame(width: 38, alignment: .leading)
                Text(segment.text)
                    .font(DS.callout)
                    .foregroundStyle(SwipeTranscriptCardPalette.text)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space4)
            .background(
                canSeek && isHovered ? DS.glassSectionFill : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canSeek)
        .onHover { isHovered = $0 }
        .animation(ProMotionSprings.hover, value: isHovered)
        .help(canSeek ? "Jump to \(segment.formattedTime)" : "")
        .accessibilityLabel("\(segment.formattedTime), \(segment.text)")
    }
}

// MARK: - Prose card

private struct SwipePreviewProseCard: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DS.callout)
            .foregroundStyle(SwipeTranscriptCardPalette.text)
            .lineSpacing(3)
            .textSelection(.enabled)
            .padding(DS.space12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SwipeTranscriptCardPalette.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(SwipeTranscriptCardPalette.border, lineWidth: 0.5)
            )
    }
}

// MARK: - Reel stage (plays in place)

/// The reel, playing. Local cache first (instant), then the stored media URL
/// resolved through the local cache (downloads once), thumbnail while anything
/// is in flight. Loops; pauses the moment the preview closes. Transcript
/// speech rows seek it through `seekRequest`.
private struct SwipePreviewReelStage: View {
    let item: SwipeGalleryItem
    let model: SwipeCardModel
    let seekRequest: SwipePreviewSeekRequest?

    @State private var player: AVPlayer?
    @State private var isResolving = false
    @State private var resolveFailed = false
    @State private var loopObserver: NSObjectProtocol?

    var body: some View {
        ZStack {
            Color.black
            if let player {
                // CosmoVideoPlayerView (AVPlayerView), never SwiftUI VideoPlayer.
                // Floating controls: always discoverable in a preview.
                CosmoVideoPlayerView(player: player, controlsStyle: .floating)
            } else {
                SwipePreviewStillStage(model: model)
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
        .onChange(of: seekRequest) { _, request in
            guard let request, let player else { return }
            player.seek(to: CMTime(seconds: request.time, preferredTimescale: 600))
            player.play()
        }
        .onDisappear(perform: teardown)
    }

    private func resolveAndPlay() async {
        teardown()
        resolveFailed = false

        // Fast path: the reel is already on disk (the prewarmer fills this
        // from the durable mirror as cards scroll by).
        if let shortcode = item.instagramId,
           let localURL = InstagramVideoLocalCache.localVideoURL(forShortcode: shortcode) {
            start(with: localURL)
            return
        }

        // Slow path — same source order as SwipeStudyPrewarmer: durable
        // Supabase mirror first, the stored CDN URL (expires in days) as the
        // fallback for freshly captured swipes.
        isResolving = true
        defer { isResolving = false }
        guard let atom = try? await AtomRepository.shared.fetch(uuid: item.id) else {
            resolveFailed = true
            return
        }
        let shortcode = item.instagramId
            ?? atom.richContent?.instagramId
            ?? atom.url.flatMap(URL.init(string:)).flatMap {
                InstagramExtractor.shared.extractShortcode(from: $0)
            }
        if let shortcode,
           let localURL = InstagramVideoLocalCache.localVideoURL(forShortcode: shortcode) {
            start(with: localURL)
            return
        }
        let source = SwipeStudyPrewarmer.videoStorageURL(from: atom.metadata)
            ?? atom.richContent?.instagramData?.extractedMediaURL
        guard let source else {
            resolveFailed = true
            return
        }
        let playable = await InstagramVideoLocalCache.resolvePlayableURL(
            from: source,
            shortcode: shortcode
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

// MARK: - Carousel stage (pager)

/// The carousel, swipeable. Slides load from the persisted carousel items
/// (local image cache first); a single-image post shows its one image the
/// same way.
private struct SwipePreviewCarouselStage: View {
    let item: SwipeGalleryItem
    let model: SwipeCardModel

    @State private var slides: [CarouselItem] = []
    @State private var index = 0
    @State private var isHovered = false

    var body: some View {
        ZStack {
            if slides.isEmpty {
                SwipePreviewStillStage(model: model)
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
            var items = atom?.richContent?.instagramData?.carouselItems ?? []
            if items.isEmpty,
               let mirrored = SwipeCarouselCloudMirror.mirroredCarouselItems(from: atom?.metadata) {
                // Phone-captured swipes may only have the worker's durable
                // Supabase copies — same fallback the Study stage uses.
                items = mirrored
            }
            slides = items
            index = 0
        }
        .onHover { isHovered = $0 }
    }

    private func slideImage(_ slide: CarouselItem) -> some View {
        let displayURL = InstagramCarouselImageCache.displayURL(for: slide, shortcode: item.instagramId)
        let cacheKey = InstagramCarouselImageCache.stableKey(for: slide, shortcode: item.instagramId)
        // Never crop a slide (they carry text) — off-aspect slides letterbox
        // on the media's honest black, which reads as cinema, not white gaps.
        return ZStack {
            Color.black
            CachedAsyncImage(url: displayURL, stableKey: cacheKey) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .empty, .failure:
                    ProgressView().controlSize(.small).tint(.white)
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

/// The medium's thumbnail filling the stage edge to edge. The stage already
/// carries the medium's honest aspect, so the fill crops at most a sliver;
/// residual mismatch sits on media black, never a white gutter.
private struct SwipePreviewStillStage: View {
    let model: SwipeCardModel

    var body: some View {
        ZStack {
            Color.black
            CachedAsyncImage(url: model.mediaURL, stableKey: model.mediaStableKey) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .empty, .failure:
                    SwipePlatformGlyph(source: model.platformKey)
                        .frame(width: 24, height: 24)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .accessibilityLabel("Swipe media preview")
    }
}
