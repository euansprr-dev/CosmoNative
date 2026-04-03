// CosmoOS/UI/FocusMode/SwipeStudy/SwipeStudyFocusModeView.swift
// Swipe Study Focus Mode - Full-screen deep analysis workspace for swipe files
// February 2026

import SwiftUI
import WebKit
import Combine
import AVKit
import UserNotifications

extension Notification.Name {
    static let contentPhysicsExtractionComplete = Notification.Name("contentPhysicsExtractionComplete")
}

// MARK: - Swipe Study Focus Mode View

private enum TranscriptDisplayMode: String, CaseIterable, Identifiable {
    case cleaned
    case raw

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cleaned: return "Cleaned"
        case .raw: return "Raw"
        }
    }
}

struct SwipeStudyFocusModeView: View {
    let atom: Atom
    let onClose: () -> Void

    @State private var currentAtom: Atom?
    @State private var analysis: SwipeAnalysis?
    @State private var isAnalyzing = false
    @State private var isDeepAnalyzing = false
    @State private var isGeneratingProfile = false
    @State private var profileGenerationError: String?
    @State private var showWalkthroughSheet = false
    @State private var hasAppeared = false
    @State private var codexLookup = CodexConceptLookup()

    // YouTube player state
    @State private var isPlayerActive = false
    @State private var currentTimestamp: TimeInterval = 0
    @State private var videoDuration: TimeInterval = 0

    // Transcript state
    @State private var transcriptText: String = ""
    @State private var isFetchingTranscript = false
    @State private var transcriptFetchFailed = false

    // Instagram native player state
    @State private var igPlayer: AVPlayer?
    @State private var igIsPlaying: Bool = false
    @State private var igIsExtractingVideo: Bool = false
    @State private var igVideoFailed: Bool = false
    @State private var igMediaData: InstagramMediaData?

    // Carousel state
    @State private var carouselCurrentIndex: Int = 0
    @State private var isCarouselContent: Bool = false

    // Instagram transcript state
    @State private var instagramTranscript: String = ""
    @State private var transcriptSaveTask: Task<Void, Never>?
    @State private var showDeleteConfirmation = false

    // Slide-based transcript state (Instagram)
    @State private var transcriptSlides: [TranscriptSlide] = [TranscriptSlide(text: "", slideNumber: 1)]
    @State private var rawTranscriptSlides: [TranscriptSlide] = []
    @State private var transcriptSpeechSegments: [TranscriptSegment] = []
    @State private var transcriptionQuality: TranscriptionQuality?
    @State private var transcriptionWarnings: [String] = []
    @State private var transcriptDisplayMode: TranscriptDisplayMode = .cleaned
    @State private var slidesSaveTask: Task<Void, Never>?
    @State private var slideFocusRequestID: UUID?

    // Auto-transcription state
    @State private var isAutoTranscribing = false
    @State private var autoTranscriptionProgress: String = ""
    @State private var autoTranscriptionContentType: TranscriptionContentType?

    // Inline transcript comments
    @State private var transcriptComments: [TranscriptComment] = []
    @State private var commentsSaveTask: Task<Void, Never>?
    @State private var selectedCommentRange: NSRange?
    @State private var showCommentInput = false
    @State private var newCommentText: String = ""
    @State private var activeCommentId: UUID?
    @State private var activeCommentSlideIndex: Int?

    // Personal notes (legacy — retained for backward compat, loaded as first comment)
    @State private var personalNotes: String = ""
    @State private var notesSaveTask: Task<Void, Never>?

    // Edit Transcript sheet state
    @State private var showEditTranscript = false
    @State private var editTranscriptText: String = ""

    // Reclassification state
    @State private var isReclassifying = false
    @State private var reclassifySuggestion: SwipeAnalysis?

    // Taxonomy management sheet
    @State private var showTaxonomyManagement = false

    // Copy transcript feedback
    @State private var copiedTranscript = false

    private let gold = DS.entitySwipe

    @AppStorage("sidebarCollapsed") private var isSidebarHidden: Bool = false
    @Environment(\.isPaneContext) private var isPaneContext
    @Environment(\.isPaneActive) private var isPaneActive

    private var panelPadding: CGFloat { isPaneContext ? 16 : 24 }

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()

            if let displayAtom = currentAtom {
                VStack(spacing: 0) {
                    topBar(atom: displayAtom)

                    Divider().background(DS.borderActive)

                    GeometryReader { geo in
                        let isCompact = geo.size.width < 900 || isPaneContext

                        if isCompact {
                            ScrollView {
                                VStack(spacing: 0) {
                                    leftPanel(atom: displayAtom)
                                    Divider().background(DS.borderActive)
                                    rightPanel
                                }
                            }
                        } else {
                            HStack(spacing: 0) {
                                leftPanel(atom: displayAtom)
                                    .frame(maxWidth: .infinity)

                                Divider().background(DS.borderActive)

                                rightPanel
                                    .frame(width: geo.size.width * 0.42)
                                    .clipped()
                            }
                        }
                    }
                }
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 8)
                .sheet(isPresented: $showEditTranscript) {
                    editTranscriptSheet
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView().tint(DS.textMuted)
                    if isAnalyzing {
                        Text("Analyzing swipe file...")
                            .font(DS.callout)
                            .foregroundStyle(DS.textSecondary)
                    }
                }
            }
        }
        .onAppear {
            AtomRepository.shared.acquireEditingLock(uuid: atom.uuid)
            // Fetch fresh atom from DB — the injected `atom` may be a stale snapshot
            // (e.g., transcript was saved but parent view still holds the old value)
            Task {
                if let id = atom.id, let fresh = try? await AtomRepository.shared.fetch(id: id) {
                    loadAtom(using: fresh)
                } else {
                    loadAtom()
                }
            }
            // Load Codex concept lookup for interactive tags
            if !codexLookup.isLoaded {
                Task {
                    let codexAtoms = try? await AtomRepository.shared.fetchAll(type: .research)
                    if let codexAtom = codexAtoms?.first(where: { $0.metadataDict?["isCodexSynthesis"] as? Bool == true }),
                       let body = codexAtom.body, body.count > 10000 {
                        codexLookup.parse(codexBody: body)
                    }
                }
            }
            // Register context provider for global Cosmo window
            let provider = SwipeStudyContextProvider(atom: atom, analysisRef: { [self] in self.analysis }, transcriptRef: { [self] in self.transcriptText.isEmpty ? self.instagramTranscript : self.transcriptText })
            if !isPaneContext || isPaneActive {
                CosmoWindowViewModel.shared.updateContext(provider: provider)
            }
        }
        .onDisappear {
            AtomRepository.shared.releaseEditingLock(uuid: atom.uuid)
        }
        .onReceive(NotificationCenter.default.publisher(for: .contentPhysicsExtractionComplete)) { notification in
            guard let uuid = notification.userInfo?["uuid"] as? String,
                  uuid == atom.uuid else { return }
            Task {
                if let refreshed = try? await AtomRepository.shared.fetch(uuid: uuid) {
                    currentAtom = refreshed
                    isGeneratingProfile = false
                }
            }
        }
        .onChange(of: isPaneActive) { _, isActive in
            if isActive {
                let provider = SwipeStudyContextProvider(atom: atom, analysisRef: { [self] in self.analysis }, transcriptRef: { [self] in self.transcriptText.isEmpty ? self.instagramTranscript : self.transcriptText })
                CosmoWindowViewModel.shared.updateContext(provider: provider)
            }
        }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .overlay {
            if showTaxonomyManagement {
                ZStack {
                    FloatingOverlayBackdrop { showTaxonomyManagement = false }
                    TaxonomyManagementView(onClose: { showTaxonomyManagement = false })
                        .frame(maxWidth: 520, maxHeight: 560)
                        .floatingOverlayPanel()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
    }

    // MARK: - Source Type Detection

    /// Detect source type from multiple sources — richContent, metadata, URL patterns
    private func detectSourceType(for atom: Atom) -> ResearchRichContent.SourceType? {
        // 1. richContent.sourceType (canonical)
        if let st = atom.richContent?.sourceType {
            return st
        }

        // 2. metadata researchType field
        if let rt = atom.researchType {
            if let st = ResearchRichContent.SourceType(rawValue: rt) {
                return st
            }
        }

        // 3. richContent.videoId implies YouTube
        if let vid = atom.richContent?.videoId, !vid.isEmpty {
            return .youtube
        }

        // 4. richContent.instagramId implies Instagram
        if let igId = atom.richContent?.instagramId, !igId.isEmpty {
            return .instagram
        }

        // 5. URL pattern matching
        if let url = atom.url?.lowercased() {
            if url.contains("youtube.com") || url.contains("youtu.be") {
                return url.contains("/shorts/") ? .youtubeShort : .youtube
            }
            if url.contains("instagram.com") {
                if url.contains("/reel") { return .instagramReel }
                if url.contains("/p/") { return .instagramPost }
                return .instagram
            }
        }

        return nil
    }

    /// Extract videoId from atom — richContent or URL pattern
    private func extractVideoId(from atom: Atom) -> String? {
        if let vid = atom.richContent?.videoId, !vid.isEmpty {
            return vid
        }
        guard let url = atom.url else { return nil }
        // youtube.com/watch?v=ID or youtu.be/ID or /shorts/ID
        if let match = url.range(of: #"(?:v=|youtu\.be/|/shorts/)([A-Za-z0-9_-]{11})"#, options: .regularExpression) {
            let fullMatch = String(url[match])
            // Extract just the ID (last 11 chars)
            let id = String(fullMatch.suffix(11))
            return id
        }
        return nil
    }

    // MARK: - Top Bar

    private func topBar(atom: Atom) -> some View {
        HStack(spacing: 12) {
            // Main sidebar toggle (standalone only)
            if !isPaneContext {
                Button {
                    withAnimation(ProMotionSprings.sidebar) {
                        isSidebarHidden.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isSidebarHidden ? DS.textMuted : DS.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(DS.border, in: Circle())
                }
                .buttonStyle(.plain)
                .help(isSidebarHidden ? "Show sidebar (⌘\\)" : "Hide sidebar (⌘\\)")
            }

            if !isPaneContext {
                Button {
                    onClose()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(DS.buttonText)
                        Text("Back")
                            .font(DS.callout)
                    }
                    .foregroundStyle(DS.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(DS.border, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            Text(atom.title ?? "Swipe File")
                .font(DS.title2)
                .foregroundStyle(DS.text)
                .lineLimit(1)

            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(DS.caption2)
                Text("Teardown")
                    .font(DS.caption)
            }
            .foregroundStyle(gold)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(gold.opacity(0.15), in: Capsule())

            if analysis?.studiedAt != nil {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(DS.footnote)
                    Text("Studied")
                        .font(DS.caption)
                }
                .foregroundStyle(DS.green)
            }

            // Creator link — tappable to open creator profile
            if let creatorUUID = analysis?.creatorUUID, !creatorUUID.isEmpty {
                Button {
                    NotificationCenter.default.post(
                        name: Notification.Name("openCreatorProfile"),
                        object: nil,
                        userInfo: ["creatorUUID": creatorUUID]
                    )
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.crop.rectangle.fill")
                            .font(DS.caption2)
                        Text("Creator")
                            .font(DS.caption)
                    }
                    .foregroundStyle(gold.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(gold.opacity(0.1), in: Capsule())
                    .overlay(Capsule().strokeBorder(gold.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Retry button — only visible when transcript/analysis failed
            if transcriptFetchFailed {
                Button {
                    retryAnalysis()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(DS.caption)
                        Text("Retry")
                            .font(DS.buttonText)
                    }
                    .foregroundStyle(DS.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(DS.orange.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            // Copy swipe + profile
            Button {
                copySwipeWithProfile()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(DS.subheadline)
                    .foregroundStyle(DS.textMuted)
                    .padding(8)
                    .background(DS.border, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Copy swipe + physics profile")

            // Delete button
            Button {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(DS.subheadline)
                    .foregroundStyle(DS.textMuted)
                    .padding(8)
                    .background(DS.border, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Delete swipe")
            .alert("Delete Swipe?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    deleteSwipe()
                }
            } message: {
                Text("This will permanently remove this swipe file and all its analysis data.")
            }

            // Pane close button
            if isPaneContext {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(DS.buttonText)
                        .foregroundStyle(DS.textMuted)
                        .frame(width: 28, height: 28)
                        .background(DS.border, in: Circle())
                }
                .buttonStyle(.plain)
            }

            Button {
                showTaxonomyManagement = true
            } label: {
                Image(systemName: "tag.fill")
                    .font(DS.subheadline)
                    .foregroundStyle(DS.textSecondary)
                    .padding(8)
                    .background(DS.border, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Taxonomy Management")

        }
        .padding(.horizontal, panelPadding)
        .padding(.vertical, 10)
        .frame(height: 56)
        .background(
            LinearGradient(
                colors: [
                    DS.bg.opacity(0.95),
                    DS.bg.opacity(0.8),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Left Panel

    private func leftPanel(atom: Atom) -> some View {
        let sourceType = detectSourceType(for: atom)
        let isInstagram = sourceType == .instagram || sourceType == .instagramReel
            || sourceType == .instagramPost || sourceType == .instagramCarousel

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                contentDisplay(atom: atom)
                if isInstagram {
                    slideTranscriptEditor(atom: atom)
                } else {
                    transcriptSection(atom: atom)
                }
            }
            .padding(panelPadding)
        }
    }

    @ViewBuilder
    private func contentDisplay(atom: Atom) -> some View {
        let sourceType = detectSourceType(for: atom)

        switch sourceType {
        case .youtube, .youtubeShort:
            youtubeContentDisplay(atom: atom)
        case .instagram, .instagramReel, .instagramPost, .instagramCarousel:
            instagramContentDisplay(atom: atom, richContent: atom.richContent)
        default:
            defaultContentDisplay(atom: atom)
        }
    }

    // MARK: - YouTube Content Display

    @ViewBuilder
    private func youtubeContentDisplay(atom: Atom) -> some View {
        let videoId = extractVideoId(from: atom)

        if isPlayerActive, let videoId = videoId {
            YouTubeFocusModePlayer(
                videoId: videoId,
                currentTime: $currentTimestamp,
                onDurationLoaded: { duration in
                    videoDuration = duration
                },
                onSeek: { time in
                    currentTimestamp = time
                }
            )
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusMedium))
        } else {
            if let thumbnailUrl = extractThumbnailUrl(from: atom),
               let url = URL(string: thumbnailUrl) {
                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        isPlayerActive = true
                    }
                } label: {
                    ZStack {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(16 / 9, contentMode: .fit)
                            case .failure, .empty:
                                thumbnailPlaceholder
                            @unknown default:
                                thumbnailPlaceholder
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: DS.radiusMedium))

                        Image(systemName: "play.circle.fill")
                            .font(DS.display)
                            .foregroundStyle(DS.text)
                            .shadow(color: .black.opacity(0.4), radius: 8)
                    }
                }
                .buttonStyle(.plain)
            } else {
                thumbnailPlaceholder
            }
        }
    }

    // MARK: - Instagram Content Display (Native AVPlayer)

    @ViewBuilder
    private func instagramContentDisplay(atom: Atom, richContent: ResearchRichContent?) -> some View {
        VStack(spacing: 12) {
            // Carousel or video content
            if isCarouselContent, let items = igMediaData?.carouselItems, !items.isEmpty {
                carouselImagePager(items: items)
            } else if isCarouselContent, let items = richContent?.instagramData?.carouselItems, !items.isEmpty {
                carouselImagePager(items: items)
            } else if isCarouselContent {
                // Carousel/post with no items loaded yet — show square placeholder
                ZStack {
                    igThumbnailView(atom: atom)

                    if igIsExtractingVideo {
                        VStack(spacing: 8) {
                            ProgressView()
                                .tint(DS.accent)
                            Text("Loading carousel...")
                                .font(DS.footnote)
                                .foregroundStyle(DS.textSecondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(DS.bg.opacity(0.7))
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(DS.display)
                                .foregroundStyle(DS.textSecondary)
                            Text("Carousel images not loaded")
                                .font(DS.subheadline)
                                .foregroundStyle(DS.textSecondary)
                            if let url = atom.url, let openURL = URL(string: url) {
                                Button {
                                    NSWorkspace.shared.open(openURL)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.up.right.square")
                                            .font(DS.footnote)
                                        Text("Open in Instagram")
                                            .font(DS.buttonText)
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(DS.red, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(DS.bg.opacity(0.7))
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 400)
                .clipShape(RoundedRectangle(cornerRadius: DS.radiusLarge))
            } else {
            // Native video player (reels only)
            ZStack {
                if igIsExtractingVideo && igPlayer == nil {
                    // Extracting state — thumbnail + spinner
                    igThumbnailView(atom: atom)
                        .aspectRatio(9.0 / 16.0, contentMode: .fit)
                        .frame(maxWidth: 320)
                        .clipShape(RoundedRectangle(cornerRadius: DS.radiusLarge))
                        .overlay(
                            VStack(spacing: 8) {
                                ProgressView()
                                    .tint(.white)
                                Text("Loading video...")
                                    .font(DS.footnote)
                                    .foregroundStyle(DS.textSecondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.black.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: DS.radiusLarge))
                        )
                } else if let player = igPlayer {
                    // Success state — native AVPlayer with macOS controls
                    ZStack {
                        VideoPlayer(player: player)

                        // Refreshing overlay
                        if igIsExtractingVideo {
                            Rectangle()
                                .fill(DS.bg.opacity(0.7))
                                .overlay(
                                    VStack(spacing: 8) {
                                        ProgressView()
                                            .tint(DS.accent)
                                        Text("Refreshing video link...")
                                            .font(DS.footnote)
                                            .foregroundStyle(DS.textSecondary)
                                    }
                                )
                        }
                    }
                    .aspectRatio(9.0 / 16.0, contentMode: .fit)
                        .frame(maxWidth: 320)
                    .clipShape(RoundedRectangle(cornerRadius: DS.radiusLarge))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusLarge)
                            .strokeBorder(DS.borderActive, lineWidth: 0.5)
                    )
                } else if igVideoFailed {
                    // Failed state — thumbnail + open in browser
                    igThumbnailView(atom: atom)
                        .aspectRatio(9.0 / 16.0, contentMode: .fit)
                        .frame(maxWidth: 320)
                        .clipShape(RoundedRectangle(cornerRadius: DS.radiusLarge))
                        .overlay(
                            VStack(spacing: 12) {
                                Image(systemName: "video.slash")
                                    .font(DS.display)
                                    .foregroundStyle(DS.textSecondary)
                                Text("Could not load video")
                                    .font(DS.subheadline)
                                    .foregroundStyle(DS.textSecondary)
                                if let url = atom.url, let openURL = URL(string: url) {
                                    Button {
                                        NSWorkspace.shared.open(openURL)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.up.right.square")
                                                .font(DS.footnote)
                                            Text("Open in Instagram")
                                                .font(DS.buttonText)
                                        }
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(DS.red, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.black.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: DS.radiusLarge))
                        )
                } else {
                    // Initial state — placeholder
                    igThumbnailView(atom: atom)
                        .aspectRatio(9.0 / 16.0, contentMode: .fit)
                        .frame(maxWidth: 320)
                        .clipShape(RoundedRectangle(cornerRadius: DS.radiusLarge))
                }
            }

            // Native AVPlayerView controls handle playback — no custom scrubber needed
            } // end else (video player branch)

            // Metadata footer
            igMetadataFooter(atom: atom)
        }
        .onAppear {
            instagramTranscript = richContent?.transcript ?? ""
            // Prefer structured slides from swipeAnalysis (preserves correct slide boundaries)
            if let savedSlides = (currentAtom ?? atom).swipeAnalysis?.transcriptSlides, !savedSlides.isEmpty {
                transcriptSlides = savedSlides
                rawTranscriptSlides = (currentAtom ?? atom).swipeAnalysis?.rawTranscriptSlides ?? savedSlides
                transcriptSpeechSegments = (currentAtom ?? atom).swipeAnalysis?.transcriptSpeechSegments ?? []
                transcriptionQuality = (currentAtom ?? atom).swipeAnalysis?.transcriptionQuality
                transcriptionWarnings = (currentAtom ?? atom).swipeAnalysis?.transcriptionWarnings ?? []
            } else {
                loadSlides(from: richContent?.transcript ?? "")
            }
            // Pre-detect carousel/post from URL pattern (avoids "loading video" flash).
            // Only use URL — sourceType can be stale. Extraction is the source of truth.
            if let url = atom.url?.lowercased(),
               url.contains("/p/") && !url.contains("/reel/") {
                isCarouselContent = true
            }
            // Only extract if player doesn't already exist (avoid re-downloading on view reappear)
            if igPlayer == nil {
                extractInstagramVideo(atom: atom)
            }
        }
        .onDisappear {
            igPlayer?.pause()
            // Flush any pending debounced slide save immediately so edits aren't lost
            if slidesSaveTask != nil {
                slidesSaveTask?.cancel()
                slidesSaveTask = nil
                saveSlideTranscript()
            }
        }
    }

    // MARK: - IG Thumbnail View

    @ViewBuilder
    private func igThumbnailView(atom: Atom) -> some View {
        if let thumbURL = igMediaData?.thumbnailURL {
            AsyncImage(url: thumbURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(DS.borderSubtle)
            }
        } else if let thumbnailUrl = extractThumbnailUrl(from: atom),
                  let url = URL(string: thumbnailUrl) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(DS.borderSubtle)
            }
        } else {
            Rectangle()
                .fill(Color.black.opacity(0.3))
                .overlay(
                    Image(systemName: "camera.fill")
                        .font(DS.display)
                        .foregroundStyle(DS.textMuted)
                )
        }
    }

    // MARK: - Carousel Image Pager

    @ViewBuilder
    private func carouselImagePager(items: [CarouselItem]) -> some View {
        let safeIndex = min(max(carouselCurrentIndex, 0), items.count - 1)

        VStack(spacing: 8) {
            ZStack {
                // Current image
                carouselItemView(item: items[safeIndex])

                // Navigation arrows
                HStack {
                    // Left arrow
                    if safeIndex > 0 {
                        Button {
                            withAnimation(ProMotionSprings.snappy) {
                                carouselCurrentIndex -= 1
                            }
                        } label: {
                            carouselNavArrow(systemName: "chevron.left")
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    // Right arrow
                    if safeIndex < items.count - 1 {
                        Button {
                            withAnimation(ProMotionSprings.snappy) {
                                carouselCurrentIndex += 1
                            }
                        } label: {
                            carouselNavArrow(systemName: "chevron.right")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 400)
            .background(DS.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusLarge)
                    .strokeBorder(DS.borderActive, lineWidth: 0.5)
            )

            // Dot indicators + counter
            HStack(spacing: 6) {
                ForEach(0..<items.count, id: \.self) { index in
                    Circle()
                        .fill(index == safeIndex ? gold : DS.textMuted)
                        .frame(width: index == safeIndex ? 8 : 6,
                               height: index == safeIndex ? 8 : 6)
                        .animation(ProMotionSprings.snappy, value: carouselCurrentIndex)
                }
            }

            Text("\(safeIndex + 1) / \(items.count)")
                .font(DS.footnote)
                .foregroundStyle(DS.textSecondary)
        }
    }

    @ViewBuilder
    private func carouselItemView(item: CarouselItem) -> some View {
        AsyncImage(url: item.mediaURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .failure:
                Rectangle()
                    .fill(DS.borderSubtle)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "photo")
                                .font(DS.title1)
                                .foregroundStyle(DS.textMuted)
                            Text("Failed to load")
                                .font(DS.footnote)
                                .foregroundStyle(DS.textMuted)
                        }
                    )
            case .empty:
                Rectangle()
                    .fill(DS.borderSubtle)
                    .overlay(
                        ProgressView()
                            .tint(.white)
                    )
            @unknown default:
                Rectangle()
                    .fill(DS.borderSubtle)
            }
        }
        .frame(maxWidth: 400, maxHeight: 400)
    }

    private func carouselNavArrow(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(DS.title2)
            .foregroundStyle(DS.text)
            .frame(width: 36, height: 36)
            .background(.regularMaterial)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.1), radius: 4)
    }

    // MARK: - IG Playback Controls

    private var igPlaybackControls: some View {
        VStack(spacing: 8) {
            // Timeline scrubber
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(DS.borderActive)
                        .frame(height: 4)

                    // Progress
                    Capsule()
                        .fill(gold)
                        .frame(width: igProgressWidth(in: geometry.size.width), height: 4)

                    // Scrubber dot
                    Circle()
                        .fill(DS.surfaceElevated)
                        .frame(width: 12, height: 12)
                        .offset(x: igProgressWidth(in: geometry.size.width) - 6)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let ratio = max(0, min(1, value.location.x / geometry.size.width))
                                    let dur = igMediaData?.duration ?? videoDuration
                                    let time = dur * ratio
                                    currentTimestamp = time
                                    igPlayer?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
                                }
                        )
                }
            }
            .frame(height: 12)
            .padding(.horizontal, 4)

            // Time display + play/pause
            HStack {
                // Play/pause button
                Button {
                    toggleIGPlayback()
                } label: {
                    Image(systemName: igIsPlaying ? "pause.fill" : "play.fill")
                        .font(DS.subheadline)
                        .foregroundStyle(DS.text)
                }
                .buttonStyle(.plain)

                Text(formatIGTime(currentTimestamp))
                    .font(DS.footnote)
                    .foregroundStyle(DS.textSecondary)

                Spacer()

                Text(formatIGTime(igMediaData?.duration ?? videoDuration))
                    .font(DS.footnote)
                    .foregroundStyle(DS.textSecondary)
            }
        }
        .frame(maxWidth: 320)
        .padding(.horizontal, 8)
    }

    // MARK: - IG Metadata Footer

    private func igMetadataFooter(atom: Atom) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "camera.fill")
                .font(DS.footnote)
                .foregroundStyle(DS.textSecondary)

            if let username = igMediaData?.authorUsername {
                Text("@\(username)")
                    .font(DS.buttonText)
                    .foregroundStyle(DS.textSecondary)
            } else if let author = atom.richContent?.author, !author.isEmpty {
                Text("@\(author)")
                    .font(DS.buttonText)
                    .foregroundStyle(DS.textSecondary)
            }

            Text("·")
                .foregroundStyle(DS.textMuted)

            Text(contentTypeLabel(atom: atom))
                .font(DS.caption)
                .foregroundStyle(isCarouselContent ? gold : DS.red)
        }
        .frame(maxWidth: isCarouselContent ? 400 : 320)
        .padding(.horizontal, 8)
    }

    // MARK: - IG Player Methods

    private func extractInstagramVideo(atom: Atom) {
        guard !igIsExtractingVideo else { return }
        igIsExtractingVideo = true

        Task {
            let expectedUUID = atom.uuid
            // Build original Instagram URL from atom
            guard let urlString = atom.url, let url = URL(string: urlString) else {
                if isViewingAtom(uuid: expectedUUID) {
                    igVideoFailed = true
                    igIsExtractingVideo = false
                }
                return
            }

            guard isViewingAtom(uuid: expectedUUID) else {
                return
            }

            let shortcode = InstagramExtractor.shared.extractShortcode(from: url)

            // Fast path: check stored carousel items (regardless of content type label —
            // older atoms may have been saved as .image even if they contain carousel items)
            if let storedIGData = atom.richContent?.instagramData,
               let items = storedIGData.carouselItems, !items.isEmpty {
                isCarouselContent = true
                // Populate igMediaData so the carousel pager has items to display
                igMediaData = InstagramMediaData(
                    originalURL: url,
                    contentType: .carousel,
                    videoURL: nil,
                    thumbnailURL: nil,
                    duration: nil,
                    authorUsername: storedIGData.authorUsername,
                    caption: storedIGData.caption,
                    carouselItems: items,
                    extractedAt: storedIGData.extractedAt ?? Date()
                )
                carouselCurrentIndex = min(carouselCurrentIndex, items.count - 1)
            }

            // Fast path: if we already have the video downloaded locally, skip extraction entirely
            if let shortcode, let localURL = InstagramVideoLocalCache.localVideoURL(forShortcode: shortcode) {
                guard isViewingAtom(uuid: expectedUUID) else { return }
                print("SwipeStudy: Using cached local video for \(shortcode)")
                isCarouselContent = false // This is a video, not a carousel
                setupIGPlayer(videoURL: localURL)

                // Auto-transcribe only if no transcript exists and not already processing in background
                let hasSlideContent = transcriptSlides.contains { !$0.text.isEmpty }
                let hasTranscript = !transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let hasSavedBody = !((currentAtom ?? atom).body ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let hasTranscriptStatus = (currentAtom ?? atom).richContent?.transcriptStatus == "available"
                let isBackgroundProcessing = SwipeProcessingService.shared.isProcessing(uuid: (currentAtom ?? atom).uuid)
                if !hasSlideContent && !hasTranscript && !hasSavedBody && !hasTranscriptStatus && !isBackgroundProcessing {
                    await autoTranscribe(videoURL: localURL, duration: videoDuration > 0 ? videoDuration : 60)
                } else if isBackgroundProcessing {
                    pollForBackgroundCompletion()
                }

                igIsExtractingVideo = false
                return
            }

            // Slow path: extract media data from Instagram, then download video
            do {
                let mediaData = try await InstagramMediaCache.shared.getMedia(for: url)
                guard isViewingAtom(uuid: expectedUUID) else { return }
                igMediaData = mediaData
                if let items = mediaData.carouselItems, !items.isEmpty {
                    carouselCurrentIndex = min(carouselCurrentIndex, items.count - 1)
                }
                await persistInstagramMediaToAtom(mediaData, expectedAtomUUID: expectedUUID)

                // Persist caption to atom if we got one from live extraction but atom doesn't have it
                if let caption = mediaData.caption, !caption.isEmpty,
                   (currentAtom ?? atom).richContent?.instagramData?.caption == nil {
                    persistCaptionToAtom(caption, expectedAtomUUID: expectedUUID)
                }

                // Carousel branch — show image pager instead of video player
                // Check carousel items regardless of content type label (embed page may return .image for carousels)
                if let items = mediaData.carouselItems, !items.isEmpty {
                    isCarouselContent = true
                    igIsExtractingVideo = false

                    let existingSlideCount = transcriptSlides.filter { !$0.text.isEmpty }.count
                    let isBackgroundProcessing = SwipeProcessingService.shared.isProcessing(uuid: (currentAtom ?? atom).uuid)

                    // Check 1: No transcript at all — initial transcription needed
                    let hasSlideContent = existingSlideCount > 0
                    let hasTranscript = !transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let hasSavedBody = !((currentAtom ?? atom).body ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let hasTranscriptStatus = (currentAtom ?? atom).richContent?.transcriptStatus == "available"
                    let needsInitialTranscription = !hasSlideContent && !hasTranscript && !hasSavedBody && !hasTranscriptStatus && !isBackgroundProcessing

                    // Check 2: More slides discovered than currently transcribed (incomplete carousel)
                    let hasMoreSlides = items.count > existingSlideCount && existingSlideCount > 0
                    let isDegraded = (currentAtom ?? atom).swipeAnalysis?.transcriptionQuality == .degraded
                    let needsReTranscription = (hasMoreSlides || isDegraded) && !isBackgroundProcessing

                    if needsInitialTranscription || needsReTranscription {
                        guard isViewingAtom(uuid: expectedUUID) else { return }
                        if needsReTranscription {
                            print("SwipeStudy: Auto-re-transcribing carousel — extracted \(items.count) items but only \(existingSlideCount) transcribed")
                        }
                        await autoTranscribeCarousel(items: items)
                    }
                    return
                }

                if let videoURL = mediaData.videoURL {
                    isCarouselContent = false // Has video → reel, not carousel
                    let playableURL = await InstagramVideoLocalCache.resolvePlayableURL(from: videoURL, shortcode: shortcode)
                    guard isViewingAtom(uuid: expectedUUID) else { return }
                    setupIGPlayer(videoURL: playableURL)
                    if let dur = mediaData.duration {
                        videoDuration = dur
                    }

                    // Auto-transcribe only if no transcript exists and not already processing in background
                    let hasSlideContent = transcriptSlides.contains { !$0.text.isEmpty }
                    let hasTranscript = !transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let hasSavedBody = !((currentAtom ?? atom).body ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let hasTranscriptStatus = (currentAtom ?? atom).richContent?.transcriptStatus == "available"
                    let isBackgroundProcessing = SwipeProcessingService.shared.isProcessing(uuid: (currentAtom ?? atom).uuid)
                    if !hasSlideContent && !hasTranscript && !hasSavedBody && !hasTranscriptStatus && !isBackgroundProcessing {
                        guard isViewingAtom(uuid: expectedUUID) else { return }
                        await autoTranscribe(videoURL: playableURL, duration: mediaData.duration ?? 60)
                    } else if isBackgroundProcessing {
                        pollForBackgroundCompletion()
                    }
                } else if let thumbnailURL = mediaData.thumbnailURL {
                    // Image post — no video but has thumbnail. Show as single-image carousel.
                    print("SwipeStudy: Instagram image post (no video), showing thumbnail as image content")
                    let singleItem = CarouselItem(
                        index: 0,
                        mediaType: .image,
                        mediaURL: thumbnailURL
                    )
                    // Update igMediaData with a synthetic carousel item so the pager can display it
                    igMediaData = InstagramMediaData(
                        originalURL: mediaData.originalURL,
                        contentType: .carousel,
                        videoURL: nil,
                        thumbnailURL: thumbnailURL,
                        duration: nil,
                        authorUsername: mediaData.authorUsername,
                        caption: mediaData.caption,
                        carouselItems: [singleItem],
                        extractedAt: mediaData.extractedAt
                    )
                    isCarouselContent = true

                    // Auto-transcribe the single image
                    let hasSlideContent = transcriptSlides.contains { !$0.text.isEmpty }
                    let hasTranscript = !transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let hasSavedBody = !((currentAtom ?? atom).body ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let hasTranscriptStatus = (currentAtom ?? atom).richContent?.transcriptStatus == "available"
                    let isBackgroundProcessing = SwipeProcessingService.shared.isProcessing(uuid: (currentAtom ?? atom).uuid)
                    if !hasSlideContent && !hasTranscript && !hasSavedBody && !hasTranscriptStatus && !isBackgroundProcessing {
                        guard isViewingAtom(uuid: expectedUUID) else { return }
                        await autoTranscribeCarousel(items: [singleItem])
                    }
                } else if isPostURL(urlString) {
                    // Post/carousel URL with no video — expected. Show as carousel placeholder.
                    print("SwipeStudy: Instagram post extraction returned no media — showing carousel placeholder")
                    isCarouselContent = true
                } else {
                    // Reel URL but no video — truly failed
                    print("SwipeStudy: Instagram extraction returned no video URL and no thumbnail")
                    igVideoFailed = true
                }
            } catch {
                guard isViewingAtom(uuid: expectedUUID) else { return }
                print("SwipeStudy: Instagram video extraction failed: \(error)")
                if isPostURL(urlString) {
                    // Post/carousel URL — don't show "Could not load video"
                    isCarouselContent = true
                } else {
                    igVideoFailed = true
                }
            }

            igIsExtractingVideo = false
        }
    }

    /// Check if URL is an Instagram post/carousel (not a reel). Post URLs use /p/, reels use /reel/.
    private func isPostURL(_ urlString: String) -> Bool {
        let lower = urlString.lowercased()
        return lower.contains("/p/") && !lower.contains("/reel/")
    }

    /// Determine the content type label for the metadata footer
    private func contentTypeLabel(atom: Atom) -> String {
        if isCarouselContent { return "Carousel" }
        if let url = atom.url?.lowercased(), url.contains("/p/") { return "Post" }
        return "Reel"
    }

    // MARK: - Re-Transcribe

    /// Force re-run auto-transcription (user tapped "Re-transcribe" button)
    private func retranscribeInstagram(atom: Atom) {
        guard !isAutoTranscribing else { return }

        // Carousel branch — re-transcribe carousel images
        if isCarouselContent {
            Task {
                let expectedUUID = (currentAtom ?? atom).uuid
                var items = igMediaData?.carouselItems ?? currentAtom?.richContent?.instagramData?.carouselItems ?? atom.richContent?.instagramData?.carouselItems ?? []

                if let urlString = (currentAtom ?? atom).url,
                   let url = URL(string: urlString),
                   let mediaData = try? await InstagramMediaCache.shared.getMedia(for: url),
                   let refreshedItems = mediaData.carouselItems,
                   !refreshedItems.isEmpty {
                    guard isViewingAtom(uuid: expectedUUID) else { return }
                    igMediaData = mediaData
                    carouselCurrentIndex = min(carouselCurrentIndex, refreshedItems.count - 1)
                    await persistInstagramMediaToAtom(mediaData, expectedAtomUUID: expectedUUID)
                    items = refreshedItems
                }

                guard isViewingAtom(uuid: expectedUUID) else { return }
                guard !items.isEmpty else { return }
                await autoTranscribeCarousel(items: items)
            }
            return
        }

        // If we already have a player URL, re-transcribe directly
        if let player = igPlayer, let currentItem = player.currentItem,
           let asset = currentItem.asset as? AVURLAsset {
            let duration = igMediaData?.duration ?? videoDuration
            Task {
                await autoTranscribe(videoURL: asset.url, duration: duration > 0 ? duration : 60)
            }
            return
        }

        // Otherwise re-extract video + transcribe
        guard let urlString = atom.url, let url = URL(string: urlString) else { return }
        Task {
            let expectedUUID = (currentAtom ?? atom).uuid
            do {
                let mediaData = try await InstagramMediaCache.shared.getMedia(for: url)
                guard isViewingAtom(uuid: expectedUUID) else { return }
                igMediaData = mediaData
                if let videoURL = mediaData.videoURL {
                    let playableURL = await InstagramVideoLocalCache.resolvePlayableURL(from: videoURL)
                    guard isViewingAtom(uuid: expectedUUID) else { return }
                    await autoTranscribe(videoURL: playableURL, duration: mediaData.duration ?? 60)
                }
            } catch {
                print("SwipeStudy: Re-transcribe failed: \(error)")
            }
        }
    }

    // MARK: - Auto-Transcription

    private func autoTranscribe(videoURL: URL, duration: TimeInterval) async {
        let expectedUUID = (currentAtom ?? atom).uuid
        isAutoTranscribing = true
        autoTranscriptionProgress = "Starting transcription..."

        let result = await InstagramAutoTranscriber.shared.transcribe(
            videoURL: videoURL,
            duration: duration
        ) { [self] progress in
            switch progress {
            case .extractingFrames(let pct):
                self.autoTranscriptionProgress = "Extracting frames... \(Int(pct * 100))%"
            case .recognizingText(let pct):
                self.autoTranscriptionProgress = "Reading text... \(Int(pct * 100))%"
            case .recognizingSpeech(let pct):
                self.autoTranscriptionProgress = "Recognizing speech... \(Int(pct * 100))%"
            case .analyzingWithAI(let pct):
                self.autoTranscriptionProgress = "AI analyzing frames... \(Int(pct * 100))%"
            case .mergingResults:
                self.autoTranscriptionProgress = "Merging results..."
            case .complete:
                self.autoTranscriptionProgress = "Complete"
            }
        }

        guard isViewingAtom(uuid: expectedUUID) else { return }
        autoTranscriptionContentType = result.contentType

        if result.contentType != .empty {
            applyTranscriptionResult(result)
            await saveSlideTranscriptAsync()

            // Auto-run analysis after successful auto-transcription so the right panel
            // populates without requiring a manual "Analyze" click.
            if shouldAutoAnalyzeAfterTranscription() {
                triggerManualAnalysis()
            }
        }

        isAutoTranscribing = false
    }

    /// Poll for background processing completion and reload atom when done
    private func pollForBackgroundCompletion() {
        autoTranscriptionProgress = "Processing in background..."
        isAutoTranscribing = true

        Task {
            let uuid = (currentAtom ?? atom).uuid
            while SwipeProcessingService.shared.isProcessing(uuid: uuid) {
                try? await Task.sleep(for: .seconds(2))
            }

            guard isViewingAtom(uuid: uuid) else { return }

            // Reload atom with fresh data
            if let fresh = try? await AtomRepository.shared.fetch(uuid: uuid) {
                currentAtom = fresh
                if let transcript = fresh.richContent?.transcript, !transcript.isEmpty {
                    transcriptText = transcript
                    instagramTranscript = transcript
                }
                if let urlString = fresh.url,
                   let url = URL(string: urlString),
                   let instagramData = fresh.richContent?.instagramData,
                   let items = instagramData.carouselItems,
                   !items.isEmpty {
                    igMediaData = InstagramMediaData(
                        originalURL: instagramData.originalURL,
                        contentType: .carousel,
                        videoURL: instagramData.extractedMediaURL,
                        thumbnailURL: URL(string: fresh.thumbnailUrl ?? "") ?? igMediaData?.thumbnailURL,
                        duration: igMediaData?.duration,
                        authorUsername: instagramData.authorUsername,
                        caption: instagramData.caption,
                        carouselItems: items,
                        extractedAt: instagramData.extractedAt ?? Date()
                    )
                    carouselCurrentIndex = min(carouselCurrentIndex, items.count - 1)
                    if url.path.lowercased().contains("/p/") {
                        isCarouselContent = true
                    }
                }
                if let sa = fresh.swipeAnalysis {
                    analysis = sa
                    // Prefer structured slides from swipeAnalysis over plain text split
                    if let slides = sa.transcriptSlides, !slides.isEmpty {
                        transcriptSlides = slides
                        if let rawSlides = sa.rawTranscriptSlides, !rawSlides.isEmpty {
                            rawTranscriptSlides = rawSlides
                        } else {
                            rawTranscriptSlides = slides
                        }
                        transcriptSpeechSegments = sa.transcriptSpeechSegments ?? []
                        transcriptionQuality = sa.transcriptionQuality
                        transcriptionWarnings = sa.transcriptionWarnings ?? []
                        cleanAllSlideLineBreaks()
                    } else if let transcript = fresh.richContent?.transcript, !transcript.isEmpty {
                        loadSlides(from: transcript)
                    }
                } else if let transcript = fresh.richContent?.transcript, !transcript.isEmpty {
                    loadSlides(from: transcript)
                }
                // Detect carousel from updated atom
                if fresh.richContent?.sourceType == .instagramCarousel {
                    isCarouselContent = true
                }
            }

            isAutoTranscribing = false
            autoTranscriptionProgress = ""
        }
    }

    /// Auto-transcribe carousel images (mirrors autoTranscribe but for image slides)
    private func autoTranscribeCarousel(items: [CarouselItem]) async {
        let expectedUUID = (currentAtom ?? atom).uuid
        isAutoTranscribing = true
        autoTranscriptionProgress = "Starting carousel transcription..."

        let result = await InstagramAutoTranscriber.shared.transcribeCarousel(
            items: items
        ) { [self] progress in
            switch progress {
            case .recognizingText(let pct):
                self.autoTranscriptionProgress = "Reading slide text... \(Int(pct * 100))%"
            case .analyzingWithAI(let pct):
                self.autoTranscriptionProgress = "AI analyzing slides... \(Int(pct * 100))%"
            case .complete:
                self.autoTranscriptionProgress = "Complete"
            default:
                break
            }
        }

        guard isViewingAtom(uuid: expectedUUID) else { return }
        autoTranscriptionContentType = result.contentType

        if !result.cleanedSlides.isEmpty || !result.rawSlides.isEmpty {
            applyTranscriptionResult(result)
            let hasText = result.cleanedSlides.contains {
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if hasText {
                await saveSlideTranscriptAsync()
            }

            if hasText && shouldAutoAnalyzeAfterTranscription() {
                triggerManualAnalysis()
            }
        }

        isAutoTranscribing = false
    }

    private func shouldAutoAnalyzeAfterTranscription() -> Bool {
        guard transcriptSlides.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return false
        }
        guard !isAnalyzing, !isDeepAnalyzing else { return false }
        // Always re-analyze after auto-transcription completes, even if a previous analysis
        // exists. The previous analysis may have used the caption as the hook instead of the
        // first transcribed slide text.
        return true
    }

    private func setupIGPlayer(videoURL: URL) {
        let item = AVPlayerItem(url: videoURL)
        let player = AVPlayer(playerItem: item)

        // Periodic time observer
        player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { time in
            self.currentTimestamp = time.seconds
        }

        // Handle playback errors (expired URL)
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            self.refreshIGVideo()
        }

        igPlayer = player

        // Load actual duration from the video file for scrubbing
        // (igMediaData?.duration may be nil in the fast-path when using a cached local file)
        Task {
            let asset = AVURLAsset(url: videoURL)
            if let dur = try? await asset.load(.duration), dur.seconds > 0.5 {
                videoDuration = dur.seconds
            }
        }
    }

    private func toggleIGPlayback() {
        if igIsPlaying {
            igPlayer?.pause()
        } else {
            igPlayer?.play()
        }
        igIsPlaying.toggle()
    }

    private func refreshIGVideo() {
        guard !igIsExtractingVideo else { return }
        igIsExtractingVideo = true

        Task {
            let expectedUUID = (currentAtom ?? atom).uuid
            guard let urlString = (currentAtom ?? atom).url, let url = URL(string: urlString) else {
                igIsExtractingVideo = false
                return
            }

            // Invalidate cache, re-extract
            InstagramMediaCache.shared.invalidate(for: url)

            do {
                let fresh = try await InstagramMediaCache.shared.getMedia(for: url)
                guard isViewingAtom(uuid: expectedUUID) else { return }
                igMediaData = fresh
                if let videoURL = fresh.videoURL {
                    let playableURL = await InstagramVideoLocalCache.resolvePlayableURL(from: videoURL)
                    guard isViewingAtom(uuid: expectedUUID) else { return }
                    let item = AVPlayerItem(url: playableURL)
                    igPlayer?.replaceCurrentItem(with: item)
                    // Resume from saved position
                    if currentTimestamp > 0 {
                        await igPlayer?.seek(to: CMTime(seconds: currentTimestamp, preferredTimescale: 600))
                    }
                }
            } catch {
                print("SwipeStudy: Instagram video refresh failed: \(error)")
            }

            igIsExtractingVideo = false
        }
    }

    private func igProgressWidth(in width: CGFloat) -> CGFloat {
        let dur = igMediaData?.duration ?? videoDuration
        guard dur > 0 else { return 0 }
        return width * (currentTimestamp / dur)
    }

    private func formatIGTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    // MARK: - Slide Transcript Editor (Instagram)

    @ViewBuilder
    private func slideTranscriptEditor(atom: Atom) -> some View {
        let displayedSlides = displayedTranscriptSlides
        let isShowingRaw = transcriptDisplayMode == .raw

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("TRANSCRIPT")
                    .dsSectionLabel()

                if let contentType = autoTranscriptionContentType {
                    contentTypeBadge(contentType)
                }

                Spacer()

                Picker("", selection: $transcriptDisplayMode) {
                    ForEach(TranscriptDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)

                // Re-transcribe button
                if !isAutoTranscribing {
                    Button {
                        retranscribeInstagram(atom: atom)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.trianglehead.clockwise")
                                .font(DS.caption2)
                            Text("Re-transcribe")
                                .font(DS.caption2)
                        }
                        .foregroundStyle(DS.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(DS.border, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                // Copy transcript button
                Button {
                    let formatted = displayedSlides.map { slide in
                        "Slide \(slide.slideNumber)\n\(slide.text)"
                    }.joined(separator: "\n\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(formatted, forType: .string)
                    copiedTranscript = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copiedTranscript = false
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: copiedTranscript ? "checkmark" : "doc.on.doc")
                            .font(DS.caption2)
                        Text(copiedTranscript ? "Copied" : "Copy")
                            .font(DS.caption2)
                    }
                    .foregroundStyle(copiedTranscript ? DS.green : DS.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(DS.border, in: Capsule())
                }
                .buttonStyle(.plain)

                Text("\(displayedSlides.count) slide\(displayedSlides.count == 1 ? "" : "s")")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }

            // Auto-transcription progress
            if isAutoTranscribing {
                autoTranscriptionProgressView
            }

            transcriptionWarningBanner

            if isShowingRaw {
                ForEach(displayedSlides) { slide in
                    rawTranscriptSlideCard(slide: slide)
                }
                Text("Raw capture is read-only. Switch back to Cleaned to edit the transcript.")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            } else {
                ForEach(transcriptSlides) { slide in
                    let index = indexForSlide(withID: slide.id) ?? 0
                    let slideComments = commentsForSlide(index)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Slide \(index + 1)")
                                .font(DS.caption2)
                                .foregroundStyle(gold.opacity(0.6))

                            if let source = slide.source {
                                slideSourceBadge(source)
                            }

                            if !slideComments.isEmpty {
                                Text("\(slideComments.count)")
                                    .font(DS.caption2)
                                    .foregroundStyle(DS.textOnAccent)
                                    .frame(width: 16, height: 16)
                                    .background(gold, in: Circle())
                            }

                            Spacer()

                            Button {
                                withAnimation(ProMotionSprings.snappy) {
                                    if activeCommentSlideIndex == index {
                                        activeCommentSlideIndex = nil
                                    } else {
                                        activeCommentSlideIndex = index
                                        newCommentText = ""
                                    }
                                }
                            } label: {
                                Image(systemName: "bubble.left")
                                    .font(DS.footnote)
                                    .foregroundStyle(activeCommentSlideIndex == index ? gold : DS.textMuted)
                            }
                            .buttonStyle(.plain)

                            Text("\(slide.text.count)/450")
                                .font(DS.caption2.monospacedDigit())
                                .foregroundStyle(slide.text.count > 450 ? DS.red : DS.textMuted)
                            if transcriptSlides.count > 1 {
                                Button {
                                    withAnimation(ProMotionSprings.snappy) {
                                        removeSlide(withID: slide.id)
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(DS.subheadline)
                                        .foregroundStyle(DS.textMuted)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        SlideTextEditor(
                            slideID: slide.id,
                            text: bindingForSlideText(slide.id),
                            focusRequestID: $slideFocusRequestID,
                            onNewSlide: {
                                insertSlide(after: slide.id)
                            }
                        )

                        if activeCommentSlideIndex == index {
                            slideCommentInput(slideIndex: index)
                        }

                        if !slideComments.isEmpty {
                            slideCommentThread(comments: slideComments)
                        }
                    }
                    .padding(10)
                    .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusSmall)
                            .stroke(activeCommentSlideIndex == index ? gold.opacity(0.3) : DS.border, lineWidth: 1)
                    )
                }

                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        let newSlide = TranscriptSlide(text: "", slideNumber: transcriptSlides.count + 1)
                        transcriptSlides.append(newSlide)
                        slideFocusRequestID = newSlide.id
                    }
                    debounceSaveSlides()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(DS.footnote)
                        Text("Add Slide")
                            .font(DS.caption)
                    }
                    .foregroundStyle(gold.opacity(0.7))
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)

                Text("Return adds a line break. Press Command-Return to add a new slide below the current one.")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }

            // Caption section — check live extraction first, then persisted data
            if let caption = igMediaData?.caption ?? atom.richContent?.instagramData?.caption, !caption.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CAPTION")
                        .dsSectionLabel()

                    Text(caption)
                        .font(DS.callout)
                        .foregroundStyle(DS.textSecondary)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.radiusSmall)
                                .stroke(DS.border, lineWidth: 1)
                        )
                }
            }

            // Analyze button
            if !slidesTranscriptText.isEmpty {
                Button {
                    saveSlideTranscript()
                    triggerManualAnalysis()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(DS.subheadline)
                        Text(analysis == nil ? "Analyze" : "Re-analyze")
                            .font(DS.buttonText)
                    }
                    .foregroundStyle(DS.textOnAccent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(gold, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var slidesTranscriptText: String {
        transcriptSlides.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    private var displayedTranscriptSlides: [TranscriptSlide] {
        switch transcriptDisplayMode {
        case .cleaned:
            return transcriptSlides
        case .raw:
            let rawSlides = rawTranscriptSlides.isEmpty ? transcriptSlides : rawTranscriptSlides
            return rawSlides.isEmpty ? [TranscriptSlide(text: "", slideNumber: 1)] : rawSlides
        }
    }

    private var shouldShowTranscriptionWarning: Bool {
        transcriptionQuality == .degraded || !transcriptionWarnings.isEmpty
    }

    private var transcriptionWarningText: String {
        transcriptionWarnings.isEmpty
            ? "Transcript quality was degraded. Review the raw capture before editing."
            : transcriptionWarnings.joined(separator: " ")
    }

    @ViewBuilder
    private var transcriptionWarningBanner: some View {
        if shouldShowTranscriptionWarning {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(DS.footnote)
                    .foregroundStyle(DS.orange)

                Text(transcriptionWarningText)
                    .font(DS.footnote)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                Text("Degraded")
                    .font(DS.caption2)
                    .foregroundStyle(DS.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(DS.orange.opacity(0.12), in: Capsule())
            }
            .padding(10)
            .background(DS.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .stroke(DS.orange.opacity(0.2), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func rawTranscriptSlideCard(slide: TranscriptSlide) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Slide \(slide.slideNumber)")
                    .font(DS.caption2)
                    .foregroundStyle(gold.opacity(0.6))

                if let source = slide.source {
                    slideSourceBadge(source)
                }

                Spacer()

                if let timestamp = slide.timestamp {
                    Text(formatTime(timestamp))
                        .font(DS.caption2.monospacedDigit())
                        .foregroundStyle(DS.textMuted)
                }
            }

            Text(slide.text.isEmpty ? "No text captured for this slide." : slide.text)
                .font(DS.callout)
                .foregroundStyle(slide.text.isEmpty ? DS.textMuted : DS.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .stroke(DS.border, lineWidth: 1)
        )
    }

    private func loadSlides(from transcript: String) {
        guard !transcript.isEmpty else {
            transcriptSlides = [TranscriptSlide(text: "", slideNumber: 1)]
            rawTranscriptSlides = transcriptSlides
            transcriptSpeechSegments = []
            transcriptionQuality = nil
            transcriptionWarnings = []
            return
        }
        // Try to decode persisted slides from JSON
        if let data = transcript.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([TranscriptSlide].self, from: data) {
            transcriptSlides = decoded
            rawTranscriptSlides = decoded
            transcriptSpeechSegments = []
            transcriptionQuality = nil
            transcriptionWarnings = []
            cleanAllSlideLineBreaks()
            return
        }
        // Fallback: split by double-newline into slides
        let parts = transcript.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if parts.count > 1 {
            transcriptSlides = parts.enumerated().map { i, text in
                TranscriptSlide(text: text, slideNumber: i + 1)
            }
        } else {
            transcriptSlides = [TranscriptSlide(text: transcript, slideNumber: 1)]
        }
        rawTranscriptSlides = transcriptSlides
        transcriptSpeechSegments = []
        transcriptionQuality = nil
        transcriptionWarnings = []
        cleanAllSlideLineBreaks()
    }

    private func applyTranscriptionResult(_ result: TranscriptionResult) {
        transcriptSlides = result.cleanedSlides.isEmpty ? [TranscriptSlide(text: "", slideNumber: 1)] : result.cleanedSlides
        rawTranscriptSlides = result.rawSlides.isEmpty ? transcriptSlides : result.rawSlides
        transcriptSpeechSegments = result.speechSegments
        transcriptionQuality = result.quality
        transcriptionWarnings = result.warnings
        transcriptDisplayMode = .cleaned
        cleanAllSlideLineBreaks()
    }

    /// Clean up mid-sentence line breaks in slide text.
    /// Joins lines that are clearly continuation of a sentence, but preserves
    /// list items, bullet points, and lines after colons. Then splits any
    /// merged list items and adds blank lines between logical sections.
    private func cleanSlideLineBreaks(_ text: String) -> String {
        // Phase 1: Split merged list items within single lines
        var working = text
        // Split "Label: +24% Label: +26%" patterns (stat lists)
        working = working.replacingOccurrences(
            of: #"(%\s+)(?=[A-Z][a-z])"#,
            with: "%\n",
            options: .regularExpression
        )
        // Split mid-line dash list items: " - Item" → newline
        working = working.replacingOccurrences(
            of: #"(?<=\S)\s+- (?=[A-Z])"#,
            with: "\n- ",
            options: .regularExpression
        )

        let lines = working.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count > 1 else { return working.trimmingCharacters(in: .whitespacesAndNewlines) }

        let bulletPattern = #"^[→▸►•·\-\*\+]\s"#
        let numberedPattern = #"^\d+[\.\)\-]\s"#

        // Phase 2: Join/preserve line breaks
        var merged: [String] = [lines[0]]
        for i in 1..<lines.count {
            let prev = merged.last ?? ""
            let next = lines[i]
            // Always preserve line break if next line is a list/bullet item
            let nextIsBullet = next.range(of: bulletPattern, options: .regularExpression) != nil
            let nextIsNumbered = next.range(of: numberedPattern, options: .regularExpression) != nil
            if nextIsBullet || nextIsNumbered {
                merged.append(next)
                continue
            }
            // Preserve line break after sentence-ending punctuation or colons
            let lastChar = prev.last
            let endsWithPunctuation = lastChar == "." || lastChar == "!" || lastChar == "?" || prev.hasSuffix("…") || lastChar == ":"
            if prev.isEmpty || endsWithPunctuation {
                merged.append(next)
            } else {
                merged[merged.count - 1] = prev + " " + next
            }
        }

        return merged.joined(separator: "\n")
    }

    /// Apply line break cleanup to all transcript slides
    private func cleanAllSlideLineBreaks() {
        for i in transcriptSlides.indices {
            transcriptSlides[i].text = cleanSlideLineBreaks(transcriptSlides[i].text)
        }
    }

    private func renumberSlides() {
        for i in transcriptSlides.indices {
            transcriptSlides[i].slideNumber = i + 1
        }
    }

    private func indexForSlide(withID slideID: UUID) -> Int? {
        transcriptSlides.firstIndex { $0.id == slideID }
    }

    private func bindingForSlideText(_ slideID: UUID) -> Binding<String> {
        Binding(
            get: {
                transcriptSlides.first(where: { $0.id == slideID })?.text ?? ""
            },
            set: { newValue in
                guard let index = indexForSlide(withID: slideID) else { return }
                transcriptSlides[index].text = String(newValue.prefix(TranscriptSlide.characterLimit))
                debounceSaveSlides()
            }
        )
    }

    private func insertSlide(after slideID: UUID) {
        let insertionIndex = (indexForSlide(withID: slideID) ?? transcriptSlides.count - 1) + 1
        let newSlide = TranscriptSlide(text: "", slideNumber: insertionIndex + 1)
        withAnimation(ProMotionSprings.snappy) {
            transcriptSlides.insert(newSlide, at: min(insertionIndex, transcriptSlides.count))
            renumberSlides()
            slideFocusRequestID = newSlide.id
        }
        for i in transcriptComments.indices {
            if transcriptComments[i].startIndex >= insertionIndex {
                transcriptComments[i].startIndex += 1
                transcriptComments[i].endIndex += 1
            }
        }
        if let activeCommentSlideIndex, activeCommentSlideIndex >= insertionIndex {
            self.activeCommentSlideIndex = activeCommentSlideIndex + 1
        }
        debounceSaveSlides()
        debounceSaveComments()
    }

    private func removeSlide(withID slideID: UUID) {
        guard let index = indexForSlide(withID: slideID) else { return }
        transcriptSlides.remove(at: index)
        renumberSlides()
        transcriptComments.removeAll { $0.startIndex == index }
        for i in transcriptComments.indices {
            if transcriptComments[i].startIndex > index {
                transcriptComments[i].startIndex -= 1
                transcriptComments[i].endIndex -= 1
            }
        }
        if slideFocusRequestID == slideID {
            slideFocusRequestID = nil
        }
        if let activeCommentSlideIndex {
            if activeCommentSlideIndex == index {
                self.activeCommentSlideIndex = nil
            } else if activeCommentSlideIndex > index {
                self.activeCommentSlideIndex = activeCommentSlideIndex - 1
            } else if activeCommentSlideIndex >= transcriptSlides.count {
                self.activeCommentSlideIndex = max(0, transcriptSlides.count - 1)
            }
        }
        debounceSaveSlides()
        debounceSaveComments()
    }

    // MARK: - Auto-Transcription UI Helpers

    @ViewBuilder
    private var autoTranscriptionProgressView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.6)
                .tint(gold)
            Text(autoTranscriptionProgress)
                .font(DS.footnote)
                .foregroundStyle(DS.textSecondary)
            Spacer()
        }
        .padding(10)
        .background(gold.opacity(0.06), in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .stroke(gold.opacity(0.15), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func contentTypeBadge(_ type: TranscriptionContentType) -> some View {
        let (icon, label): (String, String) = {
            switch type {
            case .textOnly: return ("text.viewfinder", "Text Only")
            case .voiceoverOnly: return ("waveform", "Voice Only")
            case .voiceoverPlusText: return ("person.wave.2", "Voice + Text")
            case .empty: return ("questionmark.circle", "No Content")
            }
        }()

        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(DS.caption2)
            Text(label)
                .font(DS.caption2)
        }
        .foregroundStyle(gold.opacity(0.8))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(gold.opacity(0.1), in: Capsule())
    }

    @ViewBuilder
    private func slideSourceBadge(_ source: TranscriptSlideSource) -> some View {
        let (icon, label): (String, String) = {
            switch source {
            case .manual: return ("pencil", "Manual")
            case .visionOCR: return ("eye", "OCR")
            case .speechAudio: return ("waveform", "Speech")
            case .merged: return ("arrow.triangle.merge", "Merged")
            case .aiCleaned: return ("sparkles", "AI")
            case .geminiVision: return ("eye.trianglebadge.exclamationmark", "Gemini")
            }
        }()

        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(DS.caption2)
            Text(label)
                .font(DS.caption2)
        }
        .foregroundStyle(DS.textMuted)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(DS.border, in: Capsule())
    }

    // MARK: - Slide Comment Helpers

    /// Get comments for a specific slide index, using startIndex mapped to slide boundaries
    private func commentsForSlide(_ slideIndex: Int) -> [TranscriptComment] {
        transcriptComments.filter { $0.startIndex == slideIndex }
    }

    @ViewBuilder
    private func slideCommentInput(slideIndex: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "bubble.left.fill")
                .font(DS.caption2)
                .foregroundStyle(gold.opacity(0.5))

            TextField("Add a comment...", text: $newCommentText)
                .textFieldStyle(.plain)
                .font(DS.subheadline)
                .foregroundStyle(DS.text)
                .onSubmit {
                    addComment(toSlide: slideIndex)
                }

            Button(action: { addComment(toSlide: slideIndex) }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(DS.title3)
                    .foregroundStyle(newCommentText.trimmingCharacters(in: .whitespaces).isEmpty ? DS.textMuted : gold)
            }
            .buttonStyle(.plain)
            .disabled(newCommentText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 6))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private func slideCommentThread(comments: [TranscriptComment]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(comments) { comment in
                slideCommentCard(comment)
            }
        }
    }

    @ViewBuilder
    private func slideCommentCard(_ comment: TranscriptComment) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "bubble.left.fill")
                .font(DS.caption2)
                .foregroundStyle(gold.opacity(0.4))
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(comment.text)
                    .font(DS.footnote)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(formatCommentDate(comment.createdAt))
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }

            Spacer()

            Button {
                withAnimation(ProMotionSprings.snappy) {
                    deleteComment(comment)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 6))
    }

    private func addComment(toSlide slideIndex: Int) {
        let text = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let comment = TranscriptComment(
            startIndex: slideIndex,
            endIndex: slideIndex,
            text: text
        )

        withAnimation(ProMotionSprings.snappy) {
            transcriptComments.append(comment)
            newCommentText = ""
            activeCommentSlideIndex = nil
        }
        debounceSaveComments()
    }

    private func deleteComment(_ comment: TranscriptComment) {
        transcriptComments.removeAll { $0.id == comment.id }
        debounceSaveComments()
    }

    private func debounceSaveComments() {
        commentsSaveTask?.cancel()
        commentsSaveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, var current = currentAtom else { return }

            // Store comments in structured JSON
            if let data = try? JSONEncoder().encode(transcriptComments),
               let jsonStr = String(data: data, encoding: .utf8) {
                // Merge with existing structured data if present
                var structuredDict: [String: Any] = [:]
                if let existingStr = current.structured,
                   let existingData = existingStr.data(using: .utf8),
                   let existing = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
                    structuredDict = existing
                }
                structuredDict["transcriptComments"] = jsonStr
                if let merged = try? JSONSerialization.data(withJSONObject: structuredDict),
                   let mergedStr = String(data: merged, encoding: .utf8) {
                    current.structured = mergedStr
                }
            }

            try? await AtomRepository.shared.update(current)
            currentAtom = current
        }
    }

    private func loadCommentsFromAtom(_ atom: Atom) {
        guard let structuredStr = atom.structured,
              let data = structuredStr.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let commentsJsonStr = dict["transcriptComments"] as? String,
              let commentsData = commentsJsonStr.data(using: .utf8),
              let loaded = try? JSONDecoder().decode([TranscriptComment].self, from: commentsData)
        else {
            // Migrate legacy personalNotes as first comment if present
            if !personalNotes.isEmpty {
                transcriptComments = [
                    TranscriptComment(startIndex: 0, endIndex: 0, text: personalNotes)
                ]
            }
            return
        }
        transcriptComments = loaded
    }

    private func formatCommentDate(_ dateStr: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateStr) else { return dateStr }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }

    private func debounceSaveSlides() {
        slidesSaveTask?.cancel()
        slidesSaveTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            saveSlideTranscript()
        }
    }

    /// Awaitable save — used from autoTranscribe to guarantee write completes before analysis starts.
    private func saveSlideTranscriptAsync() async {
        guard var current = currentAtom else {
            print("SwipeStudy: saveSlideTranscript — currentAtom is nil, cannot save")
            return
        }
        let combined = slidesTranscriptText
        current.body = combined
        var richContent = current.richContent ?? ResearchRichContent()
        richContent.transcript = combined
        richContent.transcriptStatus = "available"
        if let hook = canonicalHookFromSlides() {
            current.hook = String(hook.prefix(200))
            current.title = String(hook.prefix(120))
            richContent.title = String(hook.prefix(120))
        }
        current.setRichContent(richContent)

        // Persist slides + comments into swipeAnalysis so they survive analysis rewrites
        var sa = current.swipeAnalysis ?? SwipeAnalysis(analysisVersion: 0, isFullyAnalyzed: false)
        // Sync hookText with the canonical hook from slides
        if let hook = canonicalHookFromSlides() {
            sa.hookText = String(hook.prefix(500))
        }
        sa.transcriptSlides = transcriptSlides
        sa.rawTranscriptSlides = rawTranscriptSlides.isEmpty ? transcriptSlides : rawTranscriptSlides
        sa.transcriptSpeechSegments = transcriptSpeechSegments
        sa.transcriptionQuality = transcriptionQuality
        sa.transcriptionWarnings = transcriptionWarnings
        sa.transcriptComments = transcriptComments
        current = current.withSwipeAnalysis(sa)

        transcriptText = combined
        instagramTranscript = combined
        currentAtom = current

        do {
            let saved = try await AtomRepository.shared.update(current)
            currentAtom = saved
            print("SwipeStudy: Transcript saved (\(combined.count) chars, \(transcriptSlides.count) slides, body: \(saved.body?.count ?? 0) chars)")
        } catch {
            print("SwipeStudy: ERROR saving transcript: \(error)")
        }
    }

    /// Persist caption from live extraction to atom's richContent so it's available on next open.
    private func persistCaptionToAtom(_ caption: String) {
        guard var current = currentAtom else { return }
        var richContent = current.richContent ?? ResearchRichContent()
        if var igData = richContent.instagramData {
            igData.caption = caption
            richContent.instagramData = igData
        } else if let urlString = current.url, let url = URL(string: urlString) {
            var igData = InstagramData(originalURL: url, contentType: .reel)
            igData.caption = caption
            richContent.instagramData = igData
        }
        current.setRichContent(richContent)
        currentAtom = current
        Task {
            try? await AtomRepository.shared.update(current)
        }
    }

    private func persistCaptionToAtom(_ caption: String, expectedAtomUUID: String) {
        guard var current = currentAtom, current.uuid == expectedAtomUUID else { return }
        var richContent = current.richContent ?? ResearchRichContent()
        if var igData = richContent.instagramData {
            igData.caption = caption
            richContent.instagramData = igData
        } else if let urlString = current.url, let url = URL(string: urlString) {
            var igData = InstagramData(originalURL: url, contentType: .reel)
            igData.caption = caption
            richContent.instagramData = igData
        }
        current.setRichContent(richContent)
        currentAtom = current
        Task {
            guard currentAtom?.uuid == expectedAtomUUID else { return }
            try? await AtomRepository.shared.update(current)
        }
    }

    private func persistInstagramMediaToAtom(_ mediaData: InstagramMediaData, expectedAtomUUID: String) async {
        guard var current = currentAtom, current.uuid == expectedAtomUUID else { return }

        // Skip media refresh if processing is still in progress — avoid version conflict race
        guard current.metadataDict?["processingStatus"] as? String == "complete" else { return }

        var richContent = current.richContent ?? ResearchRichContent()
        var igData = richContent.instagramData ?? InstagramData(
            originalURL: mediaData.originalURL,
            contentType: mediaData.contentType
        )
        var didChange = false

        if igData.authorUsername != mediaData.authorUsername, let author = mediaData.authorUsername {
            igData.authorUsername = author
            richContent.author = author
            didChange = true
        }

        if igData.caption != mediaData.caption, let caption = mediaData.caption {
            igData.caption = caption
            didChange = true
        }

        if igData.extractedMediaURL != mediaData.videoURL {
            igData.extractedMediaURL = mediaData.videoURL
            didChange = true
        }

        if igData.extractedAt != mediaData.extractedAt {
            igData.extractedAt = mediaData.extractedAt
            didChange = true
        }

        if let items = mediaData.carouselItems, !items.isEmpty {
            let existingCount = igData.carouselItems?.count ?? 0
            let existingSignature = (igData.carouselItems ?? []).map {
                "\($0.index)|\($0.mediaType.rawValue)|\($0.mediaURL.absoluteString)"
            }
            let incomingSignature = items.map {
                "\($0.index)|\($0.mediaType.rawValue)|\($0.mediaURL.absoluteString)"
            }
            if existingCount < items.count ||
                igData.carouselItems?.isEmpty == true ||
                existingSignature != incomingSignature {
                igData.carouselItems = items
                didChange = true
            }
            if richContent.sourceType != .instagramCarousel {
                richContent.sourceType = .instagramCarousel
                richContent.instagramType = "carousel"
                didChange = true
            }
        }

        let resolvedThumbnail = mediaData.thumbnailURL?.absoluteString
            ?? mediaData.carouselItems?.first(where: { $0.mediaType == .image })?.mediaURL.absoluteString
            ?? mediaData.carouselItems?.first?.mediaURL.absoluteString

        if let resolvedThumbnail,
           resolvedThumbnail != current.thumbnailUrl || resolvedThumbnail != richContent.thumbnailUrl {
            current.thumbnailUrl = resolvedThumbnail
            richContent.thumbnailUrl = resolvedThumbnail
            didChange = true
        }

        guard didChange else { return }

        richContent.instagramData = igData
        current.setRichContent(richContent)
        currentAtom = current

        do {
            currentAtom = try await AtomRepository.shared.update(current)
        } catch {
            print("SwipeStudy: Failed to persist refreshed Instagram media: \(error)")
        }
    }

    private func isViewingAtom(uuid: String) -> Bool {
        currentAtom?.uuid == uuid
    }

    /// Fire-and-forget save — used from debounced manual edits.
    private func saveSlideTranscript() {
        guard var current = currentAtom else { return }
        let combined = slidesTranscriptText
        current.body = combined
        var richContent = current.richContent ?? ResearchRichContent()
        richContent.transcript = combined
        richContent.transcriptStatus = "available"
        if let hook = canonicalHookFromSlides() {
            current.hook = String(hook.prefix(200))
            current.title = String(hook.prefix(120))
            richContent.title = String(hook.prefix(120))
        }
        current.setRichContent(richContent)

        // Persist slides + comments into swipeAnalysis so they survive analysis rewrites
        var sa = current.swipeAnalysis ?? SwipeAnalysis(analysisVersion: 0, isFullyAnalyzed: false)
        // Sync hookText with the canonical hook from slides
        if let hook = canonicalHookFromSlides() {
            sa.hookText = String(hook.prefix(500))
        }
        sa.transcriptSlides = transcriptSlides
        sa.rawTranscriptSlides = rawTranscriptSlides.isEmpty ? transcriptSlides : rawTranscriptSlides
        sa.transcriptSpeechSegments = transcriptSpeechSegments
        sa.transcriptionQuality = transcriptionQuality
        sa.transcriptionWarnings = transcriptionWarnings
        sa.transcriptComments = transcriptComments
        current = current.withSwipeAnalysis(sa)

        transcriptText = combined
        instagramTranscript = combined
        currentAtom = current
        Task {
            do {
                let saved = try await AtomRepository.shared.update(current)
                currentAtom = saved
            } catch {
                print("SwipeStudy: ERROR saving transcript (debounced): \(error)")
            }
        }
    }

    private func canonicalHookFromSlides() -> String? {
        for slide in transcriptSlides {
            let normalized = slide.text
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty {
                return normalized
            }
        }
        return nil
    }

    // (buildInstagramEmbedUrl removed — native AVPlayer replaces WKWebView embed)

    private func debounceSaveTranscript(_ transcript: String) {
        transcriptSaveTask?.cancel()
        transcriptSaveTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, var current = currentAtom else { return }

            var richContent = current.richContent ?? ResearchRichContent()
            richContent.transcript = transcript
            current.setRichContent(richContent)

            if !transcript.isEmpty {
                current.body = transcript
            }

            try? await AtomRepository.shared.update(current)
            currentAtom = current
        }
    }

    // MARK: - Default Content Display

    @ViewBuilder
    private func defaultContentDisplay(atom: Atom) -> some View {
        if let thumbnailUrl = extractThumbnailUrl(from: atom),
           let url = URL(string: thumbnailUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(16 / 9, contentMode: .fit)
                case .failure, .empty:
                    thumbnailPlaceholder
                @unknown default:
                    thumbnailPlaceholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusMedium))
        } else {
            thumbnailPlaceholder
        }
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: DS.radiusMedium)
            .fill(DS.borderSubtle)
            .frame(height: 200)
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                        .font(DS.display)
                        .foregroundStyle(gold.opacity(0.4))
                    Text("Swipe File")
                        .font(DS.callout)
                        .foregroundStyle(DS.textMuted)
                }
            )
    }

    // MARK: - Universal Analyze Button

    /// Gold analyze button — visible when text content exists but no deep analysis has been run.
    /// Works for Instagram reels, raw text, web articles — any content with a transcript.
    @ViewBuilder
    private var analyzeButton: some View {
        let hasDeepAnalysis = (analysis?.analysisVersion ?? 0) >= 2
        if !isDeepAnalyzing && !hasDeepAnalysis {
            Button {
                triggerManualAnalysis()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(DS.footnote)
                    Text("Analyze with Claude")
                        .font(DS.buttonText)
                }
                .foregroundStyle(DS.textOnAccent)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(gold, in: Capsule())
            }
            .buttonStyle(.plain)
        } else if isDeepAnalyzing {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.5)
                    .tint(gold)
                Text("Analyzing...")
                    .font(DS.subheadline)
                    .foregroundStyle(DS.textMuted)
            }
        }
    }

    /// Trigger NLP + AI classification on whatever text is currently available
    private func triggerManualAnalysis() {
        // Determine the best available text, prioritizing current slide transcript.
        let text: String = {
            let slides = slidesTranscriptText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !slides.isEmpty { return slides }
            let transcript = transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !transcript.isEmpty { return transcript }
            return instagramTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        }()
        guard !text.isEmpty else { return }

        transcriptText = text
        instagramTranscript = text

        Task {
            var atomForAnalysis = currentAtom ?? atom
            atomForAnalysis.body = text
            atomForAnalysis.processingStatus = "complete"

            var richContent = atomForAnalysis.richContent ?? ResearchRichContent()
            richContent.transcript = text
            richContent.transcriptStatus = "available"
            if let hook = canonicalHookFromSlides() {
                atomForAnalysis.hook = String(hook.prefix(200))
                atomForAnalysis.title = String(hook.prefix(120))
                richContent.title = String(hook.prefix(120))
            }
            atomForAnalysis.setRichContent(richContent)
            try? await AtomRepository.shared.update(atomForAnalysis)
            currentAtom = atomForAnalysis

            // Capture current slides/comments so analysis writes don't discard them
            let savedSlides = transcriptSlides
            let savedRawSlides = rawTranscriptSlides.isEmpty ? transcriptSlides : rawTranscriptSlides
            let savedSpeechSegments = transcriptSpeechSegments
            let savedTranscriptionQuality = transcriptionQuality
            let savedTranscriptionWarnings = transcriptionWarnings
            let savedComments = transcriptComments

            // Phase 1: Run NLP on current atom
            isAnalyzing = true
            var nlpResult = await SwipeAnalyzer.shared.analyze(atom: atomForAnalysis)
            nlpResult.transcriptSlides = savedSlides
            nlpResult.rawTranscriptSlides = savedRawSlides
            nlpResult.transcriptSpeechSegments = savedSpeechSegments
            nlpResult.transcriptionQuality = savedTranscriptionQuality
            nlpResult.transcriptionWarnings = savedTranscriptionWarnings
            nlpResult.transcriptComments = savedComments
            analysis = nlpResult
            isAnalyzing = false

            // Save NLP results (with slides preserved)
            let updated = atomForAnalysis.withSwipeAnalysis(nlpResult)
            try? await AtomRepository.shared.update(updated)
            currentAtom = updated

            // Phase 2: AI classification + deep analysis (single Claude call)
            isDeepAnalyzing = true
            let classifiedResult = await SwipeClassificationEngine.shared.classifyAndAnalyze(
                atom: currentAtom ?? atom
            )

            if classifiedResult.isFullyAnalyzed {
                var enriched = SwipeClassificationEngine.shared.mergeClassification(
                    classifiedResult, into: nlpResult
                )
                enriched.transcriptSlides = savedSlides
                enriched.rawTranscriptSlides = savedRawSlides
                enriched.transcriptSpeechSegments = savedSpeechSegments
                enriched.transcriptionQuality = savedTranscriptionQuality
                enriched.transcriptionWarnings = savedTranscriptionWarnings
                enriched.transcriptComments = savedComments
                withAnimation(ProMotionSprings.snappy) {
                    analysis = enriched
                }
                let updated2 = (currentAtom ?? atom).withSwipeAnalysis(enriched)
                try? await AtomRepository.shared.update(updated2)
                currentAtom = updated2
            }
            isDeepAnalyzing = false

            // Notify the swipe gallery to reload so the card reflects the updated hookType
            NotificationCenter.default.post(name: .researchCreated, object: nil,
                                            userInfo: ["uuid": (currentAtom ?? atom).uuid])
        }
    }

    // MARK: - Transcript Section

    @ViewBuilder
    private func transcriptSection(atom: Atom) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("TRANSCRIPT")
                    .font(DS.callout)
                    .tracking(1.2)
                    .foregroundStyle(DS.textMuted)

                if isFetchingTranscript {
                    ProgressView()
                        .scaleEffect(0.5)
                        .tint(gold)
                }

                Spacer()

                if let richContent = atom.richContent,
                   let author = richContent.author, !author.isEmpty {
                    Text(author)
                        .font(DS.caption)
                        .foregroundStyle(DS.textMuted)
                }
            }

            if !transcriptText.isEmpty {
                Text(transcriptText)
                    .font(DS.navTitle)
                    .foregroundStyle(DS.text)
                    .lineSpacing(6)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Analyze button for non-Instagram content with transcript
                analyzeButton

                // Edit Transcript link — allows correcting auto-transcription errors
                Button {
                    editTranscriptText = transcriptText
                    showEditTranscript = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(DS.caption2)
                        Text("Edit Transcript")
                            .font(DS.caption)
                    }
                    .foregroundStyle(DS.textMuted)
                }
                .buttonStyle(.plain)
            } else if isFetchingTranscript {
                // Shimmer placeholder for transcript loading
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(0..<6, id: \.self) { i in
                        ShimmerLine(width: i == 5 ? 0.6 : (i % 2 == 0 ? 1.0 : 0.85))
                    }
                }
                .padding(.vertical, 4)
            } else {
                Text("No transcript available")
                    .font(DS.callout)
                    .foregroundStyle(DS.textMuted)
                    .padding(.vertical, 12)
            }

            // Caption section — check live extraction first, then persisted data
            if let caption = igMediaData?.caption ?? atom.richContent?.instagramData?.caption, !caption.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CAPTION")
                        .dsSectionLabel()

                    Text(caption)
                        .font(DS.callout)
                        .foregroundStyle(DS.textSecondary)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.radiusSmall)
                                .stroke(DS.border, lineWidth: 1)
                        )
                }
            }
        }
    }

    // MARK: - Right Panel

    private var rightPanel: some View {
        ScrollView {
            VStack(spacing: 16) {
                if isAnalyzing {
                    analysisShimmer
                } else if let analysis = analysis {
                    HookAnalysisCard(analysis: analysis)

                    // Key Insight from Claude deep analysis
                    if let insight = analysis.keyInsight, !insight.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .font(DS.subheadline)
                                .foregroundStyle(gold)
                            Text(insight)
                                .font(DS.callout)
                                .foregroundStyle(DS.text)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(gold.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(gold.opacity(0.2), lineWidth: 1)
                        )
                    } else if isDeepAnalyzing {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.5)
                                .tint(gold)
                            Text("Claude is analyzing structure...")
                                .font(DS.subheadline)
                                .foregroundStyle(DS.textMuted)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 10))
                    }

                    // Structure Map — always visible, placeholder when empty
                    if let sections = analysis.sections, !sections.isEmpty {
                        StructureMapView(
                            frameworkType: analysis.frameworkType,
                            sections: sections,
                            onSectionTap: { position in
                                let timestamp = position * videoDuration
                                currentTimestamp = timestamp
                                if !isPlayerActive { isPlayerActive = true }
                            }
                        )
                    } else {
                        emptyAnalysisCard(
                            title: "STRUCTURE",
                            icon: "rectangle.3.group",
                            message: "Transcript required for structural breakdown"
                        )
                    }

                    // Content Physics Profile (replaces legacy Emotional Arc + Persuasion Stack)
                    if let physicsProfile = currentAtom?.bestPhysicsProfile {
                        ContentPhysicsSection(profile: physicsProfile)
                            .environment(\.codexLookup, codexLookup)

                        // Walkthrough section (only for Codex-language profiles)
                        if let walkthrough = currentAtom?.blueprintWalkthrough {
                            walkthroughCard(walkthrough)
                        }

                        reExtractProfileButton
                    } else {
                        generateCodexProfileCard
                    }

                    // Taxonomy Classification
                    TaxonomySection(
                        analysis: Binding(
                            get: { self.analysis },
                            set: { self.analysis = $0 }
                        ),
                        currentAtom: Binding(
                            get: { self.currentAtom },
                            set: { self.currentAtom = $0 }
                        ),
                        isReclassifying: $isReclassifying,
                        reclassifySuggestion: $reclassifySuggestion,
                        onReclassify: { reclassifySwipe() },
                        onAcceptReclassification: { acceptReclassification() },
                        onRejectReclassification: { rejectReclassification() },
                        onSaveTaxonomyChange: { saveTaxonomyOverride() },
                        onOpenCreatorProfile: { creatorUUID in
                            NotificationCenter.default.post(
                                name: Notification.Name("openCreatorProfile"),
                                object: nil,
                                userInfo: ["creatorUUID": creatorUUID]
                            )
                        },
                        onLinkCreator: { uuid, name in
                            // Update the swipe's creator link in the analysis
                            saveTaxonomyOverride()
                        }
                    )

                    SimilarSwipesSection(
                        currentHookType: analysis.hookType,
                        currentFingerprint: analysis.fingerprint,
                        currentEntityId: atom.id ?? -1,
                        onSwipeTap: { newEntityId in
                            reloadWithEntity(newEntityId)
                        }
                    )

                    // Instagram Analysis placeholder
                    if isInstagramSource {
                        instagramAnalysisPlaceholder
                    }
                } else {
                    noAnalysisPlaceholder
                }
            }
            .padding(panelPadding)
        }
    }

    /// Styled placeholder for analysis cards that need more data
    // MARK: - Re-Extract Profile Button

    @ViewBuilder
    private var reExtractProfileButton: some View {
        HStack {
            if let atom = currentAtom, !atom.hasCodexProfile {
                // Has legacy profile but no Codex profile — prompt upgrade
                Text("Legacy profile — re-extract for Codex language")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }
            Spacer()
            Button {
                Task { await generateCodexProfile() }
            } label: {
                Label(
                    isGeneratingProfile ? "Extracting..." : "Re-extract with Codex",
                    systemImage: "book.and.wrench"
                )
                .font(DS.caption2)
                .foregroundStyle(DS.entitySwipe)
            }
            .buttonStyle(.plain)
            .disabled(isGeneratingProfile)
        }
        .padding(.top, DS.space4)
    }

    // MARK: - Generate Codex Profile

    @ViewBuilder
    private var generateCodexProfileCard: some View {
        VStack(spacing: DS.space12) {
            HStack {
                Text("CONTENT PHYSICS")
                    .font(DS.caption)
                    .tracking(1.2)
                    .foregroundStyle(DS.textMuted)
                Spacer()
            }

            if isGeneratingProfile {
                VStack(spacing: DS.space10) {
                    ProgressView()
                        .scaleEffect(1.1)
                    Text("Analyzing with Codex language...")
                        .font(DS.callout)
                        .foregroundStyle(DS.textMuted)
                    Text("Full physics profile + slide-by-slide walkthrough using unified Content Physics language")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, DS.space20)
            } else {
                generateCodexProfileContent
            }
        }
        .frame(maxWidth: .infinity)
        .padding(DS.space16)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusMedium).stroke(DS.border, lineWidth: 1))
    }

    @ViewBuilder
    private var generateCodexProfileContent: some View {
        VStack(spacing: DS.space10) {
            Image(systemName: "book.and.wrench")
                .font(.system(size: 28))
                .foregroundStyle(DS.entitySwipe)

            Text("No physics profile yet")
                .font(DS.callout)
                .foregroundStyle(DS.text)

            Text("Generate the complete Content Physics profile using the Exemplar Codex language — physics profile + full walkthrough (~$2)")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            if let error = profileGenerationError {
                Text(error)
                    .font(DS.caption2)
                    .foregroundStyle(DS.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await generateCodexProfile() }
            } label: {
                Label("Generate Codex Profile", systemImage: "book.and.wrench")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.space16)
                    .padding(.vertical, DS.space8)
                    .background(DS.entitySwipe, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, DS.space16)
    }

    // MARK: - Walkthrough Card

    @ViewBuilder
    private func walkthroughCard(_ walkthrough: String) -> some View {
        VStack(spacing: DS.space12) {
            HStack {
                Image(systemName: "text.book.closed")
                    .foregroundStyle(DS.entitySwipe)
                Text("WALKTHROUGH")
                    .font(DS.caption)
                    .tracking(1.2)
                    .foregroundStyle(DS.textMuted)
                Spacer()
                Button {
                    showWalkthroughSheet = true
                } label: {
                    Label("Expand", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(DS.caption2)
                        .foregroundStyle(DS.entitySwipe)
                }
                .buttonStyle(.plain)
            }

            // Preview — first 500 chars
            Text(String(walkthrough.prefix(500)) + (walkthrough.count > 500 ? "..." : ""))
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
                .lineLimit(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .padding(DS.space16)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusMedium).stroke(DS.border, lineWidth: 1))
        .sheet(isPresented: $showWalkthroughSheet) {
            walkthroughFullSheet(walkthrough)
        }
    }

    @ViewBuilder
    private func walkthroughFullSheet(_ walkthrough: String) -> some View {
        NavigationStack {
            ScrollView {
                Text(walkthrough)
                    .font(DS.caption)
                    .foregroundStyle(DS.text)
                    .padding(DS.space20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .navigationTitle("Blueprint Walkthrough")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showWalkthroughSheet = false }
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(walkthrough, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
    }

    private func generateCodexProfile() async {
        guard let atom = currentAtom else { return }
        isGeneratingProfile = true
        profileGenerationError = nil

        let atomUUID = atom.uuid
        let atomTitle = atom.title ?? "Swipe"
        // Check for existing Codex profile (version 2) — use extractedAt for change detection
        let oldExtractedAt = atom.codexProfile?.extractedAt ?? atom.contentPhysicsProfile?.extractedAt

        // Fire the API call — defaults to Codex language extraction
        do {
            let apiKey: String = APIKeys.supabaseServiceRoleKey ?? ""
            let baseURL = "https://cosmonative-production.up.railway.app"
            let url = URL(string: "\(baseURL)/api/writing/codex/extract-single")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "swipeUUID": atomUUID,
                "useCodexLanguage": true,
            ] as [String: Any])
            request.timeoutInterval = 900 // 15 min — Codex extraction is heavier

            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

            if statusCode != 200 {
                let body = String(data: data, encoding: .utf8) ?? ""
                profileGenerationError = "Error (\(statusCode)): \(String(body.prefix(150)))"
                isGeneratingProfile = false
                return
            }
        } catch {
            profileGenerationError = error.localizedDescription
            isGeneratingProfile = false
            return
        }

        // Background poll — detached Task survives view navigation
        // User can leave the page, extraction continues, notification fires when done
        Task.detached { [atomUUID, atomTitle, oldExtractedAt] in
            for attempt in 1...450 { // Poll up to 15 min (2s × 450) — Codex extraction is heavier
                try? await Task.sleep(for: .seconds(2))
                if let refreshed = try? await AtomRepository.shared.fetch(uuid: atomUUID),
                   let profile = refreshed.codexProfile ?? refreshed.contentPhysicsProfile,
                   profile.extractedAt != oldExtractedAt || oldExtractedAt == nil {
                    // Extraction complete — notify the app
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .contentPhysicsExtractionComplete,
                            object: nil,
                            userInfo: ["uuid": atomUUID, "title": atomTitle]
                        )
                        // macOS notification
                        Self.showExtractionNotification(title: atomTitle)
                    }
                    print("🔬 Extraction complete for \"\(atomTitle)\" after \(attempt * 2)s")
                    return
                }
                if attempt % 15 == 0 {
                    print("🔬 Still waiting for extraction... \(attempt * 2)s elapsed")
                }
            }
            print("🔬 Extraction poll timed out for \"\(atomTitle)\" after 15 min")
        }

        // User can navigate away — polling continues in background
        isGeneratingProfile = false
    }

    private static func showExtractionNotification(title: String) {
        let content = UNMutableNotificationContent()
        content.title = "Content Physics Extraction Complete"
        content.body = "Profile updated for \"\(title)\""
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "extraction-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Copy Swipe + Profile

    private func copySwipeWithProfile() {
        guard let atom = currentAtom else { return }
        var text = "=== SWIPE: \(atom.title ?? "Untitled") ===\n\n"

        // Full body
        if let body = atom.body, !body.isEmpty {
            text += "--- BODY ---\n\(body)\n\n"
        }

        // Existing analysis (hook, beats, score, framework, voice)
        if let structured = atom.structured,
           let data = structured.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let sa = json["swipeAnalysis"] as? [String: Any] {
            if let hookText = sa["hookText"] as? String { text += "Hook: \(hookText)\n" }
            if let hookType = sa["hookType"] as? String { text += "Hook Type: \(hookType)\n" }
            if let hookScore = sa["hookScore"] as? Double { text += "Hook Score: \(hookScore)/10\n" }
            if let hookMechanism = sa["hookMechanism"] as? String { text += "Hook Mechanism: \(hookMechanism)\n" }
            if let hookReason = sa["hookScoreReason"] as? String { text += "Hook Score Reason: \(hookReason)\n" }
            if let beatFP = sa["beatFingerprint"] as? String { text += "Beats: \(beatFP)\n" }
            if let framework = sa["frameworkType"] as? String { text += "Framework: \(framework)\n" }
            if let recipe = sa["structuralRecipe"] as? String { text += "Structural Recipe: \(recipe)\n" }
            if let voice = sa["voiceMarkers"] as? [String] { text += "Voice: \(voice.joined(separator: ", "))\n" }
            if let emotion = sa["dominantEmotion"] as? String { text += "Dominant Emotion: \(emotion)\n" }
            text += "\n"
        }

        // Content Physics — EVERYTHING
        if let p = atom.contentPhysicsProfile {
            text += "--- CONTENT PHYSICS ---\n"

            // Arc
            if let arc = p.arcQuarks {
                text += "Arc: \(arc.shape ?? "")\n"
                if let reversals = arc.winLossReversals { text += "Win/Loss Reversals: \(reversals)\n" }
                if let sparse = arc.sparseDensePattern { text += "Sparse/Dense: \(sparse)\n" }
                if let iet = arc.internalExternalTension, iet.present == true {
                    text += "Internal/External Tension: \(iet.description ?? "") (peak @slide \(iet.peakSlide ?? 0))\n"
                }
                if let df = arc.dominantFrame {
                    text += "Dominant Frame: \(df.type ?? "")\(df.mechanism.map { " — \($0)" } ?? "")\n"
                }
            }

            // Physics Events
            if let brk = p.physicsEvents?.symmetryBreak {
                text += "Symmetry Break: @slide \(brk.slideNumber ?? 0)\n"
                if let pattern = brk.patternEstablished { text += "  Pattern: \(pattern)\n" }
                if let what = brk.whatBreaks { text += "  Breaks: \(what)\n" }
                if let why = brk.whyDevastating { text += "  Why: \(why)\n" }
            }
            if let pt = p.physicsEvents?.phaseTransition {
                text += "Phase Transition: \(pt.frameBefore ?? "") → \(pt.frameAfter ?? "") @slide \(pt.slideNumber ?? 0)\n"
                if let recontext = pt.recontextualization { text += "  Recontextualization: \(recontext)\n" }
            }
            if let pg = p.physicsEvents?.peakGravity {
                text += "Peak Gravity: \(pg.activeLoops ?? 0) loops @slide \(pg.slideNumber ?? 0)\n"
            }
            if let er = p.physicsEvents?.energyResolution {
                text += "Energy: \(er.proportional == true ? "Proportional" : "Disproportional")\n"
                if let assessment = er.assessment { text += "  Assessment: \(assessment)\n" }
            }

            // Slide Quarks (full detail)
            if let quarks = p.slideQuarks, !quarks.isEmpty {
                text += "\nSlide Quarks:\n"
                for q in quarks {
                    text += "  \(q.slideNumber): \(q.speechAct.type ?? "")"
                    if let mechanism = q.speechAct.mechanism { text += " — \(mechanism)" }
                    text += "\n"
                    if let deltas = q.readerDeltas {
                        for d in deltas {
                            text += "    Reader: \(d.type ?? "")"
                            if let m = d.mechanism { text += " — \(m)" }
                            text += "\n"
                        }
                    }
                    if let proof = q.proofType {
                        text += "    Proof: \(proof.type ?? "")\(proof.mechanism.map { " — \($0)" } ?? "")\n"
                    }
                    if let motivation = q.motivation {
                        text += "    Motivation: \(motivation.type ?? "")\(motivation.mechanism.map { " — \($0)" } ?? "")\n"
                    }
                    if let compression = q.compression {
                        text += "    Compression: \(compression.type)\(compression.size.map { " (\($0))" } ?? "")\(compression.mechanism.map { " — \($0)" } ?? "")\n"
                    }
                    if let frame = q.frame {
                        text += "    Frame: \(frame.type ?? "")\(frame.mechanism.map { " — \($0)" } ?? "")\n"
                    }
                    if let ed = q.experientialDistance {
                        text += "    Distance: \(ed.type ?? "")\(ed.mechanism.map { " — \($0)" } ?? "")\n"
                    }
                    if let techs = q.techniques, !techs.isEmpty {
                        text += "    Techniques: \(techs.map { "\($0.technique)\($0.usage.map { ": \($0)" } ?? "")" }.joined(separator: " | "))\n"
                    }
                }
            }

            // Transitions (full detail)
            if let transitions = p.transitions, !transitions.isEmpty {
                text += "\nTransitions:\n"
                for t in transitions {
                    text += "  \(t.from)→\(t.to): \(t.type)\(t.doubleHelix == true ? " 🧬" : "")\n"
                    if let mechanism = t.mechanism { text += "    \(mechanism)\n" }
                    if let dh = t.doubleHelixDetail { text += "    Double helix: \(dh)\n" }
                }
            }

            // Reader Journey
            if let sim = p.readerSimulation, !sim.isEmpty {
                text += "\nReader Journey:\n"
                for s in sim {
                    text += "  After slide \(s.afterSlide):"
                    if let emotion = s.dominantEmotion { text += " [\(emotion)]" }
                    if let investment = s.investmentLevel { text += " invest=\(investment)" }
                    text += "\n"
                    if let questions = s.activeQuestions, !questions.isEmpty {
                        text += "    Questions: \(questions.joined(separator: "; "))\n"
                    }
                    if let assumptions = s.builtAssumptions, !assumptions.isEmpty {
                        text += "    Assumptions: \(assumptions.joined(separator: "; "))\n"
                    }
                    if let prediction = s.prediction { text += "    Predicts: \(prediction)\n" }
                }
            } else if let rsv = p.rsv?.trajectoryPoints, !rsv.isEmpty {
                text += "\nRSV Trajectory:\n"
                for pt in rsv {
                    text += "  @slide \(pt.afterSlide): \(pt.openLoops?.count ?? 0) loops, trust=\(pt.trust ?? "?"), tension=\(pt.tension?.level ?? "?")/\(pt.tension?.type ?? "?"), frame=\"\(pt.frame ?? "?")\", energy=\(pt.energyBalance ?? "?")\n"
                    if let loops = pt.openLoops?.loops, !loops.isEmpty {
                        text += "    Loops: \(loops.joined(separator: "; "))\n"
                    }
                }
            }

            // Rhythm
            if let r = p.rhythm {
                text += "\nRhythm & Pacing:\n"
                if let density = r.densityWaveform { text += "  Density waveform: \(density.map { String(Int($0)) }.joined(separator: ", "))\n" }
                if let energy = r.energyCurve { text += "  Energy curve: \(energy.map { String(Int($0)) }.joined(separator: ", "))\n" }
                if let info = r.informationRate { text += "  Information rate: \(info.map { String(Int($0)) }.joined(separator: ", "))\n" }
                if let silence = r.silenceSlides { text += "  Silence slides: \(silence.map(String.init).joined(separator: ", "))\n" }
                if let momentum = r.momentumMechanism { text += "  Momentum: \(momentum)\n" }
                if let pattern = r.pacingPattern { text += "  Pattern: \(pattern)\n" }
            }

            // Long-Range Bonds
            if let inter = p.longRangeInteractions {
                if let bonds = inter.setupPayoffBonds, !bonds.isEmpty {
                    text += "\nLong-Range Bonds:\n"
                    for b in bonds {
                        text += "  Slide \(b.setupSlide) → Slide \(b.payoffSlide) (\(b.distance ?? 0) apart)\n"
                        if let planted = b.planted { text += "    Planted: \(planted)\n" }
                        if let harvested = b.harvested { text += "    Harvested: \(harvested)\n" }
                    }
                }
                if let echoes = inter.echoPatterns, !echoes.isEmpty {
                    text += "\nEcho Patterns:\n"
                    for e in echoes {
                        text += "  \"\(e.quarkType)\" @ slides \(e.positions?.map(String.init).joined(separator: ", ") ?? "")\n"
                        if let transform = e.transformation { text += "    Transformation: \(transform)\n" }
                    }
                }
                if let interferences = inter.interferences, !interferences.isEmpty {
                    text += "\nInterference Effects:\n"
                    for i in interferences {
                        text += "  @slides \(i.slides?.map(String.init).joined(separator: ",") ?? ""): \(i.forces.joined(separator: " + "))\n"
                        if let effect = i.emergentEffect { text += "    → \(effect)\n" }
                    }
                }
                if let absences = inter.deliberateAbsences, !absences.isEmpty {
                    text += "\nDeliberate Absences:\n"
                    for a in absences {
                        text += "  ⊘ \(a.what)\n"
                        if let effect = a.effect { text += "    Effect: \(effect)\n" }
                    }
                }
                if let chains = inter.callbackChains, !chains.isEmpty {
                    text += "\nCallback Chains:\n"
                    for c in chains {
                        text += "  \"\(c.element)\" — \(c.transformationArc ?? "")\n"
                        if let appearances = c.appearances {
                            for app in appearances {
                                text += "    @slide \(app.slide): \(app.meaning ?? "")\n"
                            }
                        }
                    }
                }
            }

            // Novel Discoveries
            if let novels = p.novelDiscoveries, !novels.isEmpty {
                text += "\nNovel Discoveries:\n"
                for n in novels {
                    text += "  • \(n.stringValue ?? n.dictValue.map { "\($0)" } ?? "?")\n"
                }
            }

            // Entanglement Pairs
            if let pairs = p.longRangeInteractions?.entanglementPairs, !pairs.isEmpty {
                text += "\nEntanglement Pairs:\n"
                for pair in pairs {
                    text += "  Slide \(pair.slideA) ⟷ Slide \(pair.slideB) (entangled)\n"
                    if let ifA = pair.ifARemoved { text += "    If \(pair.slideA) removed: \(ifA)\n" }
                    if let ifB = pair.ifBRemoved { text += "    If \(pair.slideB) removed: \(ifB)\n" }
                }
            }

            // Superposition
            if let rsvPoints = p.rsv?.trajectoryPoints {
                let superPoints = rsvPoints.filter { ($0.superpositionCount ?? 0) > 0 }
                if !superPoints.isEmpty {
                    text += "\nSuperposition:\n"
                    for pt in superPoints {
                        text += "  @slide \(pt.afterSlide): \(pt.superpositionCount ?? 0) interpretations"
                        if let sups = pt.superpositions, !sups.isEmpty { text += " (\(sups.joined(separator: ", ")))" }
                        text += "\n"
                    }
                    if let collapse = superPoints.last(where: { ($0.superpositionCount ?? 0) <= 1 }),
                       let peak = superPoints.max(by: { ($0.superpositionCount ?? 0) < ($1.superpositionCount ?? 0) }) {
                        text += "  Collapse: from \(peak.superpositionCount ?? 0) interpretations → 1 at slide \(collapse.afterSlide)\n"
                    }
                }
            }

            // Resonance Frequencies
            if let quarks = p.slideQuarks {
                let resonant = quarks.filter { $0.resonanceFrequency != nil }
                if !resonant.isEmpty {
                    text += "\nResonance Frequencies:\n"
                    for q in resonant {
                        if let r = q.resonanceFrequency {
                            text += "  📡 Slide \(q.slideNumber): \(r.detail ?? "") — \(r.unspokenExperience ?? "") (reach: \(r.estimatedReach ?? "?"))\n"
                        }
                    }
                }
            }

            // Antimatter
            if let antimatter = p.antimatter, !antimatter.isEmpty {
                text += "\nAntimatter:\n"
                for a in antimatter {
                    text += "  ☢️ \(a)\n"
                }
            }

            // The Fabric (full)
            if let fabric = p.deepFabric, !fabric.isEmpty {
                text += "\nThe Fabric:\n\(fabric)\n"
            }
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func emptyAnalysisCard(title: String, icon: String, message: String) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(title)
                    .dsSectionLabel()
                Spacer()
            }

            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(DS.title1)
                    .foregroundStyle(DS.textMuted)
                Text(message)
                    .font(DS.subheadline)
                    .foregroundStyle(DS.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .padding(16)
        .background(DS.surfaceCard, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
        .dsGradientBorder(cornerRadius: DS.radiusMedium)
    }

    // MARK: - Instagram Source Check

    private var isInstagramSource: Bool {
        let sourceType = detectSourceType(for: currentAtom ?? atom)
        return sourceType == .instagram || sourceType == .instagramReel
            || sourceType == .instagramPost || sourceType == .instagramCarousel
    }

    // MARK: - Instagram Analysis Placeholder

    private var instagramAnalysisPlaceholder: some View {
        VStack(spacing: 12) {
            HStack {
                Text("INSTAGRAM ANALYSIS")
                    .dsSectionLabel()
                Spacer()
            }

            VStack(spacing: 8) {
                Image(systemName: "camera.fill")
                    .font(DS.title1)
                    .foregroundStyle(DS.textMuted)
                Text("Instagram Analysis")
                    .font(DS.callout)
                    .foregroundStyle(DS.textMuted)
                Text("Coming Soon")
                    .font(DS.footnote)
                    .foregroundStyle(DS.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
        .padding(16)
        .background(DS.surfaceCard, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
        .dsGradientBorder(cornerRadius: DS.radiusMedium)
    }

    // MARK: - Analysis Shimmer Skeleton

    private var analysisShimmer: some View {
        VStack(spacing: 16) {
            // Hook analysis skeleton
            VStack(alignment: .leading, spacing: 12) {
                ShimmerLine(width: 0.75, height: 18)
                HStack(spacing: 8) {
                    ShimmerPill(width: 90)
                    ShimmerPill(width: 70)
                }
                HStack(spacing: 10) {
                    ShimmerCircle(size: 36)
                    VStack(alignment: .leading, spacing: 4) {
                        ShimmerLine(width: 0.4, height: 12)
                        ShimmerLine(width: 0.25, height: 10)
                    }
                }
            }
            .padding(16)
            .background(DS.surfaceCard, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
            .dsGradientBorder(cornerRadius: DS.radiusMedium)

            // Structure map skeleton
            VStack(alignment: .leading, spacing: 12) {
                ShimmerLine(width: 0.35, height: 12)
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 8) {
                        ShimmerCircle(size: 8)
                        ShimmerLine(width: 0.7, height: 12)
                    }
                }
            }
            .padding(16)
            .background(DS.surfaceCard, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
            .dsGradientBorder(cornerRadius: DS.radiusMedium)

            // Emotional arc skeleton
            VStack(alignment: .leading, spacing: 12) {
                ShimmerLine(width: 0.3, height: 12)
                ShimmerLine(width: 1.0, height: 80)
            }
            .padding(16)
            .background(DS.surfaceCard, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
            .dsGradientBorder(cornerRadius: DS.radiusMedium)
        }
    }

    private var noAnalysisPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(DS.pageTitle)
                .foregroundStyle(gold.opacity(0.4))
            Text("No analysis available")
                .font(DS.navTitle)
                .foregroundStyle(DS.textSecondary)
            Text("Analysis will run automatically when content is available")
                .font(DS.subheadline)
                .foregroundStyle(DS.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(DS.surfaceCard, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
        .dsGradientBorder(cornerRadius: DS.radiusMedium)
    }

    // MARK: - Notes Section (Removed — replaced by per-slide inline commenting)

    // MARK: - Data Loading

    private func loadAtom(using sourceAtom: Atom? = nil) {
        let atom = sourceAtom ?? self.atom
        resetLoadedAtomState()
        currentAtom = atom
        personalNotes = extractPersonalNotes(from: atom)
        loadCommentsFromAtom(atom)

        // Load existing transcript — try richContent.transcript first, then decode body as JSON segments
        if let transcript = atom.richContent?.transcript, !transcript.isEmpty {
            transcriptText = transcript
        } else if let body = atom.body, !body.isEmpty {
            // Body may be JSON-encoded TranscriptSegment array (Research flow stores it this way)
            if let data = body.data(using: .utf8),
               let segments = try? JSONDecoder().decode([TranscriptSegment].self, from: data) {
                transcriptText = segments.map(\.text).joined(separator: " ")
            } else {
                transcriptText = body
            }
        } else {
            transcriptText = ""
        }

        // Load saved slide-based transcript for Instagram content.
        // Primary source: swipeAnalysis.transcriptSlides (survives analysis rewrites).
        // Fallback: parse transcriptText as JSON slides or split by \n\n.
        if let savedSlides = atom.swipeAnalysis?.transcriptSlides,
           !savedSlides.isEmpty,
           savedSlides.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            transcriptSlides = savedSlides
            rawTranscriptSlides = atom.swipeAnalysis?.rawTranscriptSlides ?? savedSlides
            transcriptSpeechSegments = atom.swipeAnalysis?.transcriptSpeechSegments ?? []
            transcriptionQuality = atom.swipeAnalysis?.transcriptionQuality
            transcriptionWarnings = atom.swipeAnalysis?.transcriptionWarnings ?? []
            instagramTranscript = transcriptText
            print("SwipeStudy: Loaded \(savedSlides.count) slides from swipeAnalysis.transcriptSlides")
        } else if !transcriptText.isEmpty {
            loadSlides(from: transcriptText)
            instagramTranscript = transcriptText
        }

        // Load saved comments from swipeAnalysis
        if let savedComments = atom.swipeAnalysis?.transcriptComments, !savedComments.isEmpty {
            transcriptComments = savedComments
        }

        // Check if analysis is already complete and up-to-date — skip re-analysis
        let cachedAnalysis = atom.swipeAnalysis
        let analysisUpToDate = cachedAnalysis?.isFullyAnalyzed == true
            && (cachedAnalysis?.analysisVersion ?? 0) >= SwipeClassificationEngine.currentSchemaVersion

        if analysisUpToDate, let cached = cachedAnalysis {
            // Analysis is valid — show immediately without re-running
            analysis = cached
            withAnimation(ProMotionSprings.snappy) {
                hasAppeared = true
            }

            // Mark as studied if not already
            if cached.studiedAt == nil {
                var studied = cached.markingStudied()
                analysis = studied
                let updated = atom.withSwipeAnalysis(studied)
                Task {
                    try? await AtomRepository.shared.update(updated)
                    currentAtom = updated
                }
            }

            // Still fetch transcript for display if YouTube and missing
            Task {
                let sourceType = detectSourceType(for: atom)
                if (sourceType == .youtube || sourceType == .youtubeShort),
                   transcriptText.isEmpty,
                   let videoId = extractVideoId(from: atom) {
                    await fetchTranscript(videoId: videoId)
                }
            }
            return
        }

        // Phase 1: Shimmer — analysis is needed
        isAnalyzing = true

        Task {
            let loadStart = ContinuousClock.now
            let sourceType = detectSourceType(for: atom)

            // Phase 2: Fetch transcript if YouTube + missing
            var transcriptFetched = false
            if (sourceType == .youtube || sourceType == .youtubeShort),
               transcriptText.isEmpty,
               let videoId = extractVideoId(from: atom) {
                await fetchTranscript(videoId: videoId)
                transcriptFetched = !transcriptText.isEmpty
            }

            // Phase 3: Fast NLP analysis
            let atomForAnalysis = currentAtom ?? atom
            let existingAnalysis = atomForAnalysis.swipeAnalysis
            let existingIsSparse = existingAnalysis != nil
                && (existingAnalysis?.sections == nil || existingAnalysis?.sections?.isEmpty == true)
                && (existingAnalysis?.persuasionTechniques == nil || existingAnalysis?.persuasionTechniques?.isEmpty == true)

            let shouldRunLocalNLP = existingAnalysis == nil
                || transcriptFetched
                || existingIsSparse

            // Capture slides/comments so analysis writes don't discard them
            let savedSlides = transcriptSlides
            let savedRawSlides = rawTranscriptSlides.isEmpty ? transcriptSlides : rawTranscriptSlides
            let savedSpeechSegments = transcriptSpeechSegments
            let savedTranscriptionQuality = transcriptionQuality
            let savedTranscriptionWarnings = transcriptionWarnings
            let savedComments = transcriptComments

            var currentAnalysis: SwipeAnalysis
            if shouldRunLocalNLP {
                currentAnalysis = await SwipeAnalyzer.shared.analyze(atom: atomForAnalysis)
            } else {
                currentAnalysis = existingAnalysis!
            }
            // Always carry slides/comments through
            currentAnalysis.transcriptSlides = savedSlides
            currentAnalysis.rawTranscriptSlides = savedRawSlides
            currentAnalysis.transcriptSpeechSegments = savedSpeechSegments
            currentAnalysis.transcriptionQuality = savedTranscriptionQuality
            currentAnalysis.transcriptionWarnings = savedTranscriptionWarnings
            currentAnalysis.transcriptComments = savedComments

            // Enforce minimum shimmer duration for polish (600ms)
            let elapsed = ContinuousClock.now - loadStart
            if elapsed < .milliseconds(600) {
                try? await Task.sleep(for: .milliseconds(600) - elapsed)
            }

            // Reveal NLP results immediately
            analysis = currentAnalysis
            isAnalyzing = false

            withAnimation(ProMotionSprings.snappy) {
                hasAppeared = true
            }

            // Mark as studied
            if currentAnalysis.studiedAt == nil {
                currentAnalysis = currentAnalysis.markingStudied()
                analysis = currentAnalysis
            }

            // Save NLP results
            if shouldRunLocalNLP {
                let updated = (currentAtom ?? atom).withSwipeAnalysis(currentAnalysis)
                try? await AtomRepository.shared.update(updated)
                currentAtom = updated
            }

            // Phase 4: AI classification + deep analysis via SwipeClassificationEngine
            let needsDeepAnalysis = (currentAnalysis.analysisVersion < SwipeClassificationEngine.currentSchemaVersion + 1)
                || (transcriptFetched && currentAnalysis.sections == nil)

            if needsDeepAnalysis, !transcriptText.isEmpty {
                isDeepAnalyzing = true

                let classifiedResult = await SwipeClassificationEngine.shared.classifyAndAnalyze(
                    atom: currentAtom ?? atom
                )

                if classifiedResult.isFullyAnalyzed {
                    var enriched = SwipeClassificationEngine.shared.mergeClassification(
                        classifiedResult, into: currentAnalysis
                    )
                    enriched.transcriptSlides = savedSlides
                    enriched.rawTranscriptSlides = savedRawSlides
                    enriched.transcriptSpeechSegments = savedSpeechSegments
                    enriched.transcriptionQuality = savedTranscriptionQuality
                    enriched.transcriptionWarnings = savedTranscriptionWarnings
                    enriched.transcriptComments = savedComments
                    withAnimation(ProMotionSprings.snappy) {
                        analysis = enriched
                    }

                    // Persist enriched analysis
                    let updated = (currentAtom ?? atom).withSwipeAnalysis(enriched)
                    try? await AtomRepository.shared.update(updated)
                    currentAtom = updated
                }

                isDeepAnalyzing = false
            } else if currentAnalysis.fingerprint == nil, currentAnalysis.emotionalArc != nil {
                // Build fingerprint from existing NLP data if none exists
                let fp = StructuralFingerprint.from(analysis: currentAnalysis)
                currentAnalysis.fingerprint = fp
                analysis = currentAnalysis
                let updated = (currentAtom ?? atom).withSwipeAnalysis(currentAnalysis)
                try? await AtomRepository.shared.update(updated)
                currentAtom = updated
            }
        }
    }

    private func resetLoadedAtomState() {
        transcriptSaveTask?.cancel()
        slidesSaveTask?.cancel()
        commentsSaveTask?.cancel()
        notesSaveTask?.cancel()

        analysis = nil
        isAnalyzing = false
        isDeepAnalyzing = false
        personalNotes = ""
        transcriptComments = []
        selectedCommentRange = nil
        showCommentInput = false
        newCommentText = ""
        activeCommentId = nil
        activeCommentSlideIndex = nil
        isPlayerActive = false
        currentTimestamp = 0
        videoDuration = 0
        instagramTranscript = ""
        transcriptText = ""
        isFetchingTranscript = false
        transcriptFetchFailed = false
        transcriptSlides = [TranscriptSlide(text: "", slideNumber: 1)]
        rawTranscriptSlides = []
        transcriptSpeechSegments = []
        transcriptionQuality = nil
        transcriptionWarnings = []
        transcriptDisplayMode = .cleaned
        slideFocusRequestID = nil
        isAutoTranscribing = false
        autoTranscriptionProgress = ""
        autoTranscriptionContentType = nil
        copiedTranscript = false
        carouselCurrentIndex = 0
        isCarouselContent = false

        igPlayer?.pause()
        igPlayer = nil
        igIsPlaying = false
        igIsExtractingVideo = false
        igVideoFailed = false
        igMediaData = nil
    }

    /// Fetch YouTube transcript using YouTubeProcessor (yt-dlp) — same path as Research focus mode
    private func fetchTranscript(videoId: String) async {
        isFetchingTranscript = true
        transcriptFetchFailed = false
        defer { isFetchingTranscript = false }

        // Use YouTubeProcessor.fetchCaptions (yt-dlp) — the same working path as Research
        if let segments = await YouTubeProcessor.shared.fetchCaptions(videoId: videoId) {
            let fullText = segments.map(\.text).joined(separator: " ")
            transcriptText = fullText

            // Also fetch metadata for title/author
            let metadata = try? await YouTubeProcessor.shared.fetchMetadata(videoId: videoId)

            // Update atom with fetched transcript
            guard var current = currentAtom else { return }
            var richContent = current.richContent ?? ResearchRichContent()
            richContent.transcript = fullText
            richContent.transcriptStatus = "available"
            if let author = metadata?.channelName {
                richContent.author = author
            }
            if let title = metadata?.title, (current.title == nil || current.title == "YouTube Video") {
                current.title = title
            }
            current.setRichContent(richContent)
            current.body = segments.jsonString
            current.processingStatus = "complete"

            try? await AtomRepository.shared.update(current)
            currentAtom = current
        } else {
            print("SwipeStudy: yt-dlp caption fetch returned nil for \(videoId)")
            transcriptFetchFailed = true
        }
    }

    /// Delete this swipe file and close the focus mode
    private func deleteSwipe() {
        let uuid = (currentAtom ?? atom).uuid
        Task {
            try? await SwipeFileEngine.shared.deleteSwipe(atomUUID: uuid)
            onClose()
        }
    }

    /// Retry transcript fetch + full analysis from scratch
    private func retryAnalysis() {
        transcriptFetchFailed = false
        isAnalyzing = true
        analysis = nil
        transcriptText = ""

        Task {
            let sourceType = detectSourceType(for: currentAtom ?? atom)

            // Re-fetch transcript
            if (sourceType == .youtube || sourceType == .youtubeShort),
               let videoId = extractVideoId(from: currentAtom ?? atom) {
                await fetchTranscript(videoId: videoId)
            }

            // Run NLP analysis
            let atomForAnalysis = currentAtom ?? atom
            let result = await SwipeAnalyzer.shared.analyze(atom: atomForAnalysis)
            analysis = result
            isAnalyzing = false

            // Save
            let updated = atomForAnalysis.withSwipeAnalysis(result)
            try? await AtomRepository.shared.update(updated)
            currentAtom = updated

            // AI classification + deep analysis if we got a transcript
            if !transcriptText.isEmpty {
                isDeepAnalyzing = true
                let classifiedResult = await SwipeClassificationEngine.shared.classifyAndAnalyze(
                    atom: currentAtom ?? atom
                )

                if classifiedResult.isFullyAnalyzed {
                    let enriched = SwipeClassificationEngine.shared.mergeClassification(
                        classifiedResult, into: result
                    )
                    withAnimation(ProMotionSprings.snappy) {
                        analysis = enriched
                    }
                    let updated2 = (currentAtom ?? atom).withSwipeAnalysis(enriched)
                    try? await AtomRepository.shared.update(updated2)
                    currentAtom = updated2
                }
                isDeepAnalyzing = false
            }
        }
    }

    private func reloadWithEntity(_ newEntityId: Int64) {
        hasAppeared = false
        resetLoadedAtomState()
        currentAtom = nil

        Task {
            try? await Task.sleep(for: .milliseconds(100))
            if let fetched = try? await AtomRepository.shared.fetch(id: newEntityId) {
                loadAtom(using: fetched)
            }
        }
    }

    // (needsTranscription removed — unified two-panel layout for all Instagram swipes)

    // MARK: - Edit Transcript Sheet

    private var editTranscriptSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Edit Transcript")
                    .font(DS.title2)
                    .foregroundStyle(DS.text)
                Spacer()
                Button("Cancel") {
                    showEditTranscript = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.textSecondary)
            }

            TextEditor(text: $editTranscriptText)
                .font(DS.navTitle)
                .foregroundStyle(DS.text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 200, maxHeight: 400)
                .padding(12)
                .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(DS.border, lineWidth: 1)
                )

            HStack {
                Text("\(editTranscriptText.split(separator: " ").count) words")
                    .font(DS.subheadline)
                    .foregroundStyle(DS.textMuted)
                Spacer()
                Button {
                    saveEditedTranscript()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(DS.subheadline)
                        Text("Save & Re-analyze")
                            .font(DS.callout)
                    }
                    .foregroundStyle(DS.textOnAccent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(gold, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(editTranscriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
        .background(DS.bg)
    }

    private func saveEditedTranscript() {
        let newTranscript = editTranscriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newTranscript.isEmpty else { return }

        showEditTranscript = false
        transcriptText = newTranscript

        Task {
            guard var current = currentAtom else { return }
            current.body = newTranscript
            var richContent = current.richContent ?? ResearchRichContent()
            richContent.transcript = newTranscript
            richContent.transcriptStatus = "available"
            current.setRichContent(richContent)
            try? await AtomRepository.shared.update(current)
            currentAtom = current

            // Re-run analysis
            triggerManualAnalysis()
        }
    }

    // MARK: - Reclassification

    private func reclassifySwipe() {
        guard let atom = currentAtom else { return }
        isReclassifying = true
        reclassifySuggestion = nil

        Task {
            let result = await SwipeClassificationEngine.shared.classifyAndAnalyze(atom: atom)
            if result.isFullyAnalyzed {
                reclassifySuggestion = result
            }
            isReclassifying = false
        }
    }

    private func acceptReclassification() {
        guard let suggestion = reclassifySuggestion,
              let current = analysis else { return }

        let merged = SwipeClassificationEngine.shared.mergeClassification(suggestion, into: current)
        analysis = merged

        let updated = (currentAtom ?? atom).withSwipeAnalysis(merged)
        Task {
            try? await AtomRepository.shared.update(updated)
            currentAtom = updated
        }

        reclassifySuggestion = nil
    }

    private func rejectReclassification() {
        reclassifySuggestion = nil
    }

    private func saveTaxonomyOverride() {
        guard var current = analysis else { return }
        current.classificationSource = .aiOverridden
        current.classifiedAt = Date()
        analysis = current

        let updated = (currentAtom ?? atom).withSwipeAnalysis(current)
        Task {
            try? await AtomRepository.shared.update(updated)
            currentAtom = updated
        }
    }

    // MARK: - Helpers

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    private func extractThumbnailUrl(from atom: Atom?) -> String? {
        guard let atom = atom else { return nil }

        // 1. Try metadata thumbnailUrl
        if let metadataStr = atom.metadata,
           let data = metadataStr.data(using: .utf8),
           let meta = try? JSONDecoder().decode(ResearchMetadata.self, from: data),
           let url = meta.thumbnailUrl, !url.isEmpty {
            return url
        }

        // 2. Try richContent thumbnailUrl
        if let url = atom.richContent?.thumbnailUrl, !url.isEmpty {
            return url
        }

        // 3. Generate from videoId for YouTube content
        if let videoId = extractVideoId(from: atom) {
            return "https://img.youtube.com/vi/\(videoId)/maxresdefault.jpg"
        }

        return nil
    }

    private func extractPersonalNotes(from atom: Atom) -> String {
        guard let metadataStr = atom.metadata,
              let data = metadataStr.data(using: .utf8),
              let meta = try? JSONDecoder().decode(ResearchMetadata.self, from: data) else { return "" }
        return meta.personalNotes ?? ""
    }

    private func extractTags(from atom: Atom?) -> [String]? {
        guard let atom = atom,
              let metadataStr = atom.metadata,
              let data = metadataStr.data(using: .utf8),
              let meta = try? JSONDecoder().decode(ResearchMetadata.self, from: data) else { return nil }
        return meta.tags
    }

    private func debounceSaveNotes(_ notes: String) {
        notesSaveTask?.cancel()
        notesSaveTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, var current = currentAtom else { return }

            var meta: ResearchMetadata
            if let metadataStr = current.metadata,
               let data = metadataStr.data(using: .utf8),
               let existing = try? JSONDecoder().decode(ResearchMetadata.self, from: data) {
                meta = existing
            } else {
                meta = ResearchMetadata()
            }
            meta.personalNotes = notes

            if let encoded = try? JSONEncoder().encode(meta),
               let jsonStr = String(data: encoded, encoding: .utf8) {
                current.metadata = jsonStr
                try? await AtomRepository.shared.update(current)
                currentAtom = current
            }
        }
    }
}

// MARK: - Shimmer Components

/// Animated shimmer line for skeleton loading states
private struct ShimmerLine: View {
    let width: CGFloat // 0.0 - 1.0 proportion
    var height: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: height / 2)
                .fill(DS.border)
                .frame(width: geo.size.width * width, height: height)
                .overlay(
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(DS.border)
                        .frame(width: geo.size.width * width, height: height)
                        .modifier(ShimmerEffect())
                )
        }
        .frame(height: height)
    }
}

/// Animated shimmer pill for tag-like skeleton elements
private struct ShimmerPill: View {
    let width: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(DS.border)
            .frame(width: width, height: 20)
            .modifier(ShimmerEffect())
    }
}

/// Animated shimmer circle for avatar-like skeleton elements
private struct ShimmerCircle: View {
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(DS.border)
            .frame(width: size, height: size)
            .modifier(ShimmerEffect())
    }
}

/// Shimmer animation modifier — sweeps a subtle highlight across the view.
/// Phase sweeps from -0.3 → 1.3 so the highlight enters and exits smoothly.
/// All gradient stop locations are clamped to [0, 1] to avoid SwiftUI warnings.
private struct ShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = -0.3

    func body(content: Content) -> some View {
        let leading  = max(0, min(1, phase - 0.15))
        let center   = max(0, min(1, phase))
        let trailing = max(0, min(1, phase + 0.15))

        content
            .overlay(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: leading),
                        .init(color: Color.white.opacity(0.1), location: center),
                        .init(color: .clear, location: trailing)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
            )
            .onAppear {
                withAnimation(
                    .linear(duration: 1.5)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 1.3
                }
            }
    }
}

// MARK: - Taxonomy Section

/// Editable taxonomy classification panel for the swipe study right panel
private struct TaxonomySection: View {
    @Binding var analysis: SwipeAnalysis?
    @Binding var currentAtom: Atom?
    @Binding var isReclassifying: Bool
    @Binding var reclassifySuggestion: SwipeAnalysis?
    let onReclassify: () -> Void
    let onAcceptReclassification: () -> Void
    let onRejectReclassification: () -> Void
    let onSaveTaxonomyChange: () -> Void
    var onOpenCreatorProfile: ((String) -> Void)? = nil
    var onLinkCreator: ((String, String) -> Void)? = nil

    @State private var creatorSearchText = ""
    @State private var creatorSearchResults: [(name: String, uuid: String)] = []
    @State private var showCreatorSearch = false
    @State private var linkedCreatorName: String?

    private let gold = DS.entitySwipe

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("TAXONOMY")
                    .dsSectionLabel()

                Spacer()

                classificationSourceBadge

                reclassifyButton
            }

            // Reclassification suggestion banner
            if let suggestion = reclassifySuggestion {
                reclassifySuggestionBanner(suggestion)
            }

            // Dimension rows
            VStack(spacing: 10) {
                narrativeRow
                secondaryNarrativeRow
                contentFormatRow
                nicheRow
                creatorRow
            }
        }
        .padding(16)
        .background(DS.surfaceCard, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
        .dsGradientBorder(cornerRadius: DS.radiusMedium)
    }

    // MARK: - Classification Source Badge

    @ViewBuilder
    private var classificationSourceBadge: some View {
        if let source = analysis?.classificationSource {
            HStack(spacing: 3) {
                Image(systemName: source == .ai ? "checkmark.circle.fill" : "pencil.circle.fill")
                    .font(DS.caption2)
                Text(source == .ai ? "AI" : "Manual")
                    .font(DS.caption2)
            }
            .foregroundStyle(source == .ai ? DS.green : DS.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill((source == .ai ? DS.green : DS.orange).opacity(0.12))
            )
        }

        if let confidence = analysis?.classificationConfidence {
            Text("\(Int(confidence * 100))%")
                .font(DS.caption2.monospacedDigit())
                .foregroundStyle(DS.textMuted)
        }
    }

    // MARK: - Reclassify Button

    private var reclassifyButton: some View {
        Button {
            onReclassify()
        } label: {
            HStack(spacing: 4) {
                if isReclassifying {
                    ProgressView()
                        .scaleEffect(0.4)
                        .tint(gold)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(DS.caption2)
                }
                Text("Reclassify")
                    .font(DS.caption2)
            }
            .foregroundStyle(gold.opacity(0.8))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(gold.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isReclassifying)
    }

    // MARK: - Reclassification Suggestion Banner

    private func reclassifySuggestionBanner(_ suggestion: SwipeAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(DS.caption2)
                    .foregroundStyle(gold)
                Text("AI Suggestion")
                    .font(DS.caption)
                    .foregroundStyle(gold)
            }

            VStack(alignment: .leading, spacing: 4) {
                if let narrative = suggestion.primaryNarrative {
                    suggestionRow("Narrative", value: narrative.displayName, color: narrative.color)
                }
                if let format = suggestion.swipeContentFormat {
                    suggestionRow("Format", value: format.displayName, color: format.color)
                }
                if let niche = suggestion.niche {
                    suggestionRow("Niche", value: niche, color: DS.textSecondary)
                }
            }

            HStack(spacing: 8) {
                Button {
                    onAcceptReclassification()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(DS.caption2)
                        Text("Accept")
                            .font(DS.caption)
                    }
                    .foregroundStyle(DS.textOnAccent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(gold, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    onRejectReclassification()
                } label: {
                    Text("Keep Current")
                        .font(DS.caption)
                        .foregroundStyle(DS.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(DS.border, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(gold.opacity(0.06), in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .stroke(gold.opacity(0.2), lineWidth: 1)
        )
    }

    private func suggestionRow(_ label: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label + ":")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
            Text(value)
                .font(DS.caption2)
                .foregroundStyle(color)
        }
    }

    // MARK: - Dimension Rows

    private var narrativeRow: some View {
        taxonomyDropdownRow(
            label: "Narrative",
            icon: analysis?.classificationSource == .ai ? "checkmark.circle.fill" : "pencil.circle.fill",
            iconColor: analysis?.classificationSource == .ai ? DS.green : DS.orange
        ) {
            Menu {
                ForEach(NarrativeStyle.allCases, id: \.rawValue) { style in
                    Button {
                        analysis?.primaryNarrative = style
                        onSaveTaxonomyChange()
                    } label: {
                        narrativePickerLabel(style)
                    }
                }
            } label: {
                narrativeDropdownLabel
            }
            .menuStyle(.borderlessButton)
        }
    }

    @ViewBuilder
    private func narrativePickerLabel(_ style: NarrativeStyle) -> some View {
        HStack {
            Image(systemName: style.icon)
            Text(style.displayName)
            if analysis?.primaryNarrative == style {
                Spacer()
                Image(systemName: "checkmark")
            }
        }
    }

    private var narrativeDropdownLabel: some View {
        let narrative = analysis?.primaryNarrative
        return HStack(spacing: 4) {
            if let n = narrative {
                Circle()
                    .fill(n.color)
                    .frame(width: 6, height: 6)
                Text(n.displayName)
                    .font(DS.caption)
                    .foregroundStyle(n.color)
            } else {
                Text("Select...")
                    .font(DS.footnote)
                    .foregroundStyle(DS.textMuted)
            }
            Image(systemName: "chevron.down")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 6))
    }

    private var secondaryNarrativeRow: some View {
        taxonomyDropdownRow(label: "Secondary", icon: nil, iconColor: .clear) {
            Menu {
                Button("None") {
                    analysis?.secondaryNarrative = nil
                    onSaveTaxonomyChange()
                }
                Divider()
                ForEach(NarrativeStyle.allCases, id: \.rawValue) { style in
                    Button {
                        analysis?.secondaryNarrative = style
                        onSaveTaxonomyChange()
                    } label: {
                        secondaryPickerLabel(style)
                    }
                }
            } label: {
                secondaryDropdownLabel
            }
            .menuStyle(.borderlessButton)
        }
    }

    @ViewBuilder
    private func secondaryPickerLabel(_ style: NarrativeStyle) -> some View {
        HStack {
            Image(systemName: style.icon)
            Text(style.displayName)
            if analysis?.secondaryNarrative == style {
                Spacer()
                Image(systemName: "checkmark")
            }
        }
    }

    private var secondaryDropdownLabel: some View {
        let narrative = analysis?.secondaryNarrative
        return HStack(spacing: 4) {
            if let n = narrative {
                Circle()
                    .fill(n.color)
                    .frame(width: 6, height: 6)
                Text(n.displayName)
                    .font(DS.caption)
                    .foregroundStyle(n.color)
            } else {
                Text("None")
                    .font(DS.footnote)
                    .foregroundStyle(DS.textMuted)
            }
            Image(systemName: "chevron.down")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 6))
    }

    private var contentFormatRow: some View {
        taxonomyDropdownRow(
            label: "Format",
            icon: analysis?.classificationSource == .ai ? "checkmark.circle.fill" : "pencil.circle.fill",
            iconColor: analysis?.classificationSource == .ai ? DS.green : DS.orange
        ) {
            Menu {
                ForEach(ContentFormat.allCases, id: \.rawValue) { format in
                    Button {
                        analysis?.swipeContentFormat = format
                        onSaveTaxonomyChange()
                    } label: {
                        formatPickerLabel(format)
                    }
                }
            } label: {
                formatDropdownLabel
            }
            .menuStyle(.borderlessButton)
        }
    }

    @ViewBuilder
    private func formatPickerLabel(_ format: ContentFormat) -> some View {
        HStack {
            Image(systemName: format.icon)
            Text(format.displayName)
            if analysis?.swipeContentFormat == format {
                Spacer()
                Image(systemName: "checkmark")
            }
        }
    }

    private var formatDropdownLabel: some View {
        let format = analysis?.swipeContentFormat
        return HStack(spacing: 4) {
            if let f = format {
                Circle()
                    .fill(f.color)
                    .frame(width: 6, height: 6)
                Text(f.displayName)
                    .font(DS.caption)
                    .foregroundStyle(f.color)
            } else {
                Text("Select...")
                    .font(DS.footnote)
                    .foregroundStyle(DS.textMuted)
            }
            Image(systemName: "chevron.down")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 6))
    }

    private var nicheRow: some View {
        taxonomyDropdownRow(label: "Niche", icon: nil, iconColor: .clear) {
            HStack(spacing: 4) {
                if let niche = analysis?.niche, !niche.isEmpty {
                    Text(niche)
                        .font(DS.caption)
                        .foregroundStyle(gold.opacity(0.8))
                } else {
                    Text("No niche")
                        .font(DS.footnote)
                        .foregroundStyle(DS.textMuted)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var creatorRow: some View {
        taxonomyDropdownRow(label: "Creator", icon: nil, iconColor: .clear) {
            if let creatorUUID = analysis?.creatorUUID, !creatorUUID.isEmpty {
                // Linked creator — tappable to open profile, with unlink button
                creatorLinkedView(creatorUUID: creatorUUID)
            } else if showCreatorSearch {
                // Autocomplete search field
                creatorSearchField
            } else {
                // Not linked — tap to search
                creatorUnlinkedView
            }
        }
    }

    @ViewBuilder
    private func creatorLinkedView(creatorUUID: String) -> some View {
        HStack(spacing: 4) {
            Button {
                onOpenCreatorProfile?(creatorUUID)
            } label: {
                creatorLinkedLabel(creatorUUID: creatorUUID)
            }
            .buttonStyle(.plain)

            // Unlink button
            Button {
                analysis?.creatorUUID = nil
                onSaveTaxonomyChange()
                linkedCreatorName = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func creatorLinkedLabel(creatorUUID: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "person.fill")
                .font(DS.caption2)
                .foregroundStyle(gold.opacity(0.7))
            Text(linkedCreatorName ?? "Creator")
                .font(DS.caption)
                .foregroundStyle(gold.opacity(0.9))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(gold.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(gold.opacity(0.2), lineWidth: 1)
        )
        .onAppear {
            if linkedCreatorName == nil {
                loadCreatorName(uuid: creatorUUID)
            }
        }
    }

    private var creatorUnlinkedView: some View {
        Button {
            showCreatorSearch = true
            loadAllCreators()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                Text("Link creator")
                    .font(DS.footnote)
                    .foregroundStyle(DS.textMuted)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var creatorSearchField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                TextField("Search creators...", text: $creatorSearchText)
                    .textFieldStyle(.plain)
                    .font(DS.footnote)
                    .foregroundStyle(DS.text)
                    .onChange(of: creatorSearchText) { _ in filterCreators() }
                Button {
                    showCreatorSearch = false
                    creatorSearchText = ""
                    creatorSearchResults = []
                } label: {
                    Image(systemName: "xmark")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DS.border, in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(gold.opacity(0.3), lineWidth: 1)
            )

            // Results dropdown
            if !creatorSearchResults.isEmpty {
                VStack(spacing: 0) {
                    ForEach(creatorSearchResults.prefix(5), id: \.uuid) { creator in
                        creatorResultRow(creator)
                    }

                    // Create new option
                    if !creatorSearchText.isEmpty {
                        Divider().background(DS.border)
                        creatorCreateNewRow
                    }
                }
                .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(DS.borderActive, lineWidth: 1)
                )
            } else if !creatorSearchText.isEmpty {
                // No matches — show create option
                VStack(spacing: 0) {
                    creatorCreateNewRow
                }
                .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(DS.borderActive, lineWidth: 1)
                )
            }
        }
    }

    @ViewBuilder
    private func creatorResultRow(_ creator: (name: String, uuid: String)) -> some View {
        Button {
            selectCreator(name: creator.name, uuid: creator.uuid)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.fill")
                    .font(DS.caption2)
                    .foregroundStyle(gold.opacity(0.6))
                Text(creator.name)
                    .font(DS.caption)
                    .foregroundStyle(DS.text)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var creatorCreateNewRow: some View {
        Button {
            createAndLinkCreator(name: creatorSearchText)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(DS.caption2)
                    .foregroundStyle(gold)
                Text("Create \"\(creatorSearchText)\"")
                    .font(DS.caption)
                    .foregroundStyle(gold)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Creator Search Helpers

    private func loadCreatorName(uuid: String) {
        Task {
            if let atom = try? await AtomRepository.shared.fetch(uuid: uuid) {
                await MainActor.run {
                    linkedCreatorName = atom.title ?? "Unknown"
                }
            }
        }
    }

    private func loadAllCreators() {
        Task {
            let creators = try? await AtomRepository.shared.fetchCreators()
            let results = (creators ?? []).compactMap { atom -> (name: String, uuid: String)? in
                guard let name = atom.title, !name.isEmpty else { return nil }
                return (name: name, uuid: atom.uuid)
            }
            await MainActor.run {
                creatorSearchResults = results
            }
        }
    }

    private func filterCreators() {
        if creatorSearchText.isEmpty {
            loadAllCreators()
            return
        }
        let q = creatorSearchText.lowercased()
        Task {
            let creators = try? await AtomRepository.shared.fetchCreators()
            let results = (creators ?? []).compactMap { atom -> (name: String, uuid: String)? in
                guard let name = atom.title, !name.isEmpty else { return nil }
                let handle = atom.metadataValue(as: CreatorMetadata.self)?.handle ?? ""
                if name.lowercased().contains(q) || handle.lowercased().contains(q) {
                    return (name: name, uuid: atom.uuid)
                }
                return nil
            }
            await MainActor.run {
                creatorSearchResults = results
            }
        }
    }

    private func selectCreator(name: String, uuid: String) {
        analysis?.creatorUUID = uuid
        linkedCreatorName = name
        showCreatorSearch = false
        creatorSearchText = ""
        creatorSearchResults = []
        onSaveTaxonomyChange()
        onLinkCreator?(uuid, name)
    }

    private func createAndLinkCreator(name: String) {
        Task {
            let metaString: String? = {
                guard let data = try? JSONEncoder().encode(CreatorMetadata(isActive: true)),
                      let str = String(data: data, encoding: .utf8) else { return nil }
                return str
            }()
            let newCreator = Atom(
                uuid: UUID().uuidString,
                type: .creator,
                title: name,
                body: nil,
                structured: nil,
                metadata: metaString,
                createdAt: ISO8601DateFormatter().string(from: Date()),
                updatedAt: ISO8601DateFormatter().string(from: Date()),
                isDeleted: false,
                localVersion: 0,
                serverVersion: 0,
                syncVersion: 0
            )
            try? await AtomRepository.shared.create(newCreator)
            await MainActor.run {
                selectCreator(name: name, uuid: newCreator.uuid)
            }
        }
    }

    // MARK: - Taxonomy Row Helper

    private func taxonomyDropdownRow<Content: View>(
        label: String,
        icon: String?,
        iconColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(DS.caption2)
                        .foregroundStyle(iconColor)
                }
                Text(label)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textSecondary)
            }
            .frame(width: 80, alignment: .leading)

            content()

            Spacer()
        }
    }
}

// MARK: - Preview

#if DEBUG
struct SwipeStudyFocusModeView_Previews: PreviewProvider {
    static var previews: some View {
        let previewAtom = Atom(
            id: 1,
            uuid: UUID().uuidString,
            type: .research,
            title: "Preview Swipe",
            body: nil,
            structured: nil,
            metadata: nil,
            links: nil,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            isDeleted: false,
            localVersion: 0,
            serverVersion: 0,
            syncVersion: 0
        )
        SwipeStudyFocusModeView(
            atom: previewAtom,
            onClose: {}
        )
        .frame(width: 1200, height: 800)
    }
}
#endif

// MARK: - Slide Text Editor

/// A text editor for a single transcript slide.
/// Command-Return creates a new slide; Return inserts a newline.
private struct SlideTextEditor: NSViewRepresentable {
    let slideID: UUID
    @Binding var text: String
    @Binding var focusRequestID: UUID?
    var onNewSlide: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = NSColor(DS.text)
        textView.backgroundColor = .clear
        textView.insertionPointColor = NSColor(DS.text)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isVerticallyResizable = true
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 4, height: 4)

        // Add visual spacing between paragraphs (lines separated by \n)
        // This is display-only — doesn't modify stored text
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = 6
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor(DS.text),
            .paragraphStyle: paragraphStyle,
        ]
        textView.delegate = context.coordinator

        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false

        // Set initial text with paragraph spacing
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: textView.typingAttributes))

        context.coordinator.textView = textView
        context.coordinator.lastSyncedText = text

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        if textView.string != text {
            let selectedRange = textView.selectedRange()
            let isFirstResponder = textView.window?.firstResponder === textView
            // Apply paragraph spacing via attributed string so it persists through updates
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.paragraphSpacing = 6
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor(DS.text),
                .paragraphStyle: paragraphStyle,
            ]
            textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attrs))
            context.coordinator.lastSyncedText = text
            if isFirstResponder {
                let clampedLocation = min(selectedRange.location, text.utf16.count)
                let remainingLength = max(0, text.utf16.count - clampedLocation)
                let clampedLength = min(selectedRange.length, remainingLength)
                textView.setSelectedRange(NSRange(location: clampedLocation, length: clampedLength))
            }
        }

        if focusRequestID == slideID,
           textView.window?.firstResponder !== textView {
            textView.window?.makeFirstResponder(textView)
            let caretLocation = textView.string.utf16.count
            textView.setSelectedRange(NSRange(location: caretLocation, length: 0))
            focusRequestID = nil
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        let width = proposal.width ?? 260
        guard let textView = nsView.documentView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return CGSize(width: width, height: 60)
        }
        textContainer.containerSize = NSSize(width: width - 8, height: CGFloat.greatestFiniteMagnitude)
        let fullRange = NSRange(location: 0, length: textView.textStorage?.length ?? 0)
        layoutManager.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return CGSize(width: width, height: max(60, ceil(usedRect.height) + 12))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onNewSlide: onNewSlide)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onNewSlide: () -> Void
        weak var textView: NSTextView?
        var lastSyncedText: String = ""

        init(text: Binding<String>, onNewSlide: @escaping () -> Void) {
            self.text = text
            self.onNewSlide = onNewSlide
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Command-Return inserts a new slide beneath the current one.
                if NSEvent.modifierFlags.contains(.command) {
                    onNewSlide()
                    return true
                }
            }
            return false
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            lastSyncedText = textView.string
            text.wrappedValue = textView.string
        }
    }
}

// MARK: - Cosmo Context Provider

@MainActor
class SwipeStudyContextProvider: CosmoContextProvider {
    private let atom: Atom
    private let analysisRef: () -> SwipeAnalysis?
    private let transcriptRef: () -> String

    init(atom: Atom, analysisRef: @escaping () -> SwipeAnalysis?, transcriptRef: @escaping () -> String) {
        self.atom = atom
        self.analysisRef = analysisRef
        self.transcriptRef = transcriptRef
    }

    var contextType: CosmoContextType { .swipeStudy }

    var contextSummary: String {
        let analysis = analysisRef()
        let hookLabel = analysis?.hookType?.rawValue ?? "unanalyzed"
        return "Studying: \(atom.title ?? "Untitled") — \(hookLabel)"
    }

    var contextData: CosmoContextData {
        let analysis = analysisRef()
        let transcript = transcriptRef()
        var viewData: [String: String] = [:]

        if let hookType = analysis?.hookType {
            viewData["hookType"] = hookType.rawValue
        }
        if let hookScore = analysis?.hookScore {
            viewData["hookScore"] = String(format: "%.1f", hookScore)
        }
        if let framework = analysis?.frameworkType {
            viewData["framework"] = framework.rawValue
        }
        if !transcript.isEmpty {
            viewData["transcript"] = String(transcript.prefix(1000))
        }
        if let creatorUUID = analysis?.creatorUUID {
            viewData["creatorUUID"] = creatorUUID
        }

        return CosmoContextData(
            currentAtomUUID: atom.uuid,
            currentAtomType: "swipeFile",
            currentAtomTitle: atom.title,
            viewSpecificData: viewData
        )
    }

    var availableActions: [CosmoWindowAction] { [] }
}
