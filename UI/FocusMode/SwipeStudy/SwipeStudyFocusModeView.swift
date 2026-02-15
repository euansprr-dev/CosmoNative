// CosmoOS/UI/FocusMode/SwipeStudy/SwipeStudyFocusModeView.swift
// Swipe Study Focus Mode - Full-screen deep analysis workspace for swipe files
// February 2026

import SwiftUI
import WebKit
import Combine
import AVKit

// MARK: - Swipe Study Focus Mode View

struct SwipeStudyFocusModeView: View {
    let atom: Atom
    let onClose: () -> Void

    @State private var currentAtom: Atom?
    @State private var analysis: SwipeAnalysis?
    @State private var isAnalyzing = false
    @State private var isDeepAnalyzing = false
    @State private var hasAppeared = false

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

    // Instagram transcript state
    @State private var instagramTranscript: String = ""
    @State private var transcriptSaveTask: Task<Void, Never>?
    @State private var showDeleteConfirmation = false

    // Slide-based transcript state (Instagram)
    @State private var transcriptSlides: [TranscriptSlide] = [TranscriptSlide(text: "", slideNumber: 1)]
    @State private var slidesSaveTask: Task<Void, Never>?

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

    private let gold = Color(hex: "#FFD700")

    var body: some View {
        ZStack {
            Color(hex: "#0A0A0F").ignoresSafeArea()

            if let displayAtom = currentAtom {
                VStack(spacing: 0) {
                    topBar(atom: displayAtom)

                    Divider().background(Color.white.opacity(0.1))

                    HStack(spacing: 0) {
                        leftPanel(atom: displayAtom)
                            .frame(maxWidth: .infinity)

                        Divider().background(Color.white.opacity(0.1))

                        rightPanel
                            .frame(width: NSScreen.main.map { $0.frame.width * 0.45 } ?? 600)
                            .clipped()
                    }
                }
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 8)
                .sheet(isPresented: $showEditTranscript) {
                    editTranscriptSheet
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    if isAnalyzing {
                        Text("Analyzing swipe file...")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
        }
        .onAppear { loadAtom() }
        .onKeyPress(.escape) {
            onClose()
            return .handled
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
            Button {
                onClose()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)

            Text(atom.title ?? "Swipe File")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)

            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10))
                Text("Teardown")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(gold)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(gold.opacity(0.15), in: Capsule())

            if analysis?.studiedAt != nil {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                    Text("Studied")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(Color(hex: "#22C55E"))
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
                            .font(.system(size: 10))
                        Text("Creator")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(gold.opacity(0.8))
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
                            .font(.system(size: 11, weight: .semibold))
                        Text("Retry")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(Color(hex: "#F97316"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(hex: "#F97316").opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            // Delete button
            Button {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(8)
                    .background(Color.white.opacity(0.06), in: Circle())
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

            Button {
                showTaxonomyManagement = true
            } label: {
                Image(systemName: "tag.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(8)
                    .background(Color.white.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Taxonomy Management")
            .sheet(isPresented: $showTaxonomyManagement) {
                TaxonomyManagementView()
            }

        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(height: 56)
        .background(
            LinearGradient(
                colors: [
                    Color(hex: "#0A0A0F").opacity(0.95),
                    Color(hex: "#0A0A0F").opacity(0.8),
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
            .padding(20)
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
            .clipShape(RoundedRectangle(cornerRadius: 12))
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
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.white.opacity(0.8))
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
            // Native video player
            ZStack {
                if igIsExtractingVideo && igPlayer == nil {
                    // Extracting state — thumbnail + spinner
                    igThumbnailView(atom: atom)
                        .frame(width: 280, height: 498)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            VStack(spacing: 8) {
                                ProgressView()
                                    .tint(.white)
                                Text("Loading video...")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.black.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        )
                } else if let player = igPlayer {
                    // Success state — native AVPlayer
                    ZStack {
                        VideoPlayer(player: player)
                            .disabled(true)

                        // Play/pause overlay
                        if !igIsPlaying {
                            Button {
                                toggleIGPlayback()
                            } label: {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 60, height: 60)
                                    .overlay(
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 24))
                                            .foregroundColor(.white)
                                            .offset(x: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }

                        // Refreshing overlay
                        if igIsExtractingVideo {
                            Rectangle()
                                .fill(.black.opacity(0.5))
                                .overlay(
                                    VStack(spacing: 8) {
                                        ProgressView()
                                            .tint(.white)
                                        Text("Refreshing video link...")
                                            .font(.system(size: 11))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                )
                        }
                    }
                    .frame(width: 280, height: 498)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
                    .onTapGesture {
                        toggleIGPlayback()
                    }
                } else if igVideoFailed {
                    // Failed state — thumbnail + open in browser
                    igThumbnailView(atom: atom)
                        .frame(width: 280, height: 498)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            VStack(spacing: 12) {
                                Image(systemName: "video.slash")
                                    .font(.system(size: 32))
                                    .foregroundColor(.white.opacity(0.5))
                                Text("Could not load video")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.6))
                                if let url = atom.url, let openURL = URL(string: url) {
                                    Button {
                                        NSWorkspace.shared.open(openURL)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.up.right.square")
                                                .font(.system(size: 11))
                                            Text("Open in Instagram")
                                                .font(.system(size: 12, weight: .medium))
                                        }
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(Color(hex: "#E4405F"), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.black.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        )
                } else {
                    // Initial state — placeholder
                    igThumbnailView(atom: atom)
                        .frame(width: 280, height: 498)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }

            // Playback controls (only when player is active)
            if igPlayer != nil {
                igPlaybackControls
            }

            // Metadata footer
            igMetadataFooter(atom: atom)
        }
        .onAppear {
            instagramTranscript = richContent?.transcript ?? ""
            loadSlides(from: richContent?.transcript ?? "")
            extractInstagramVideo(atom: atom)
        }
        .onDisappear {
            igPlayer?.pause()
            igPlayer = nil
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
                    .fill(Color.black.opacity(0.3))
            }
        } else if let thumbnailUrl = extractThumbnailUrl(from: atom),
                  let url = URL(string: thumbnailUrl) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.black.opacity(0.3))
            }
        } else {
            Rectangle()
                .fill(Color.black.opacity(0.3))
                .overlay(
                    Image(systemName: "camera.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.white.opacity(0.2))
                )
        }
    }

    // MARK: - IG Playback Controls

    private var igPlaybackControls: some View {
        VStack(spacing: 8) {
            // Timeline scrubber
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 4)

                    // Progress
                    Capsule()
                        .fill(gold)
                        .frame(width: igProgressWidth(in: geometry.size.width), height: 4)

                    // Scrubber dot
                    Circle()
                        .fill(.white)
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
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)

                Text(formatIGTime(currentTimestamp))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))

                Spacer()

                Text(formatIGTime(igMediaData?.duration ?? videoDuration))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .frame(width: 280)
        .padding(.horizontal, 8)
    }

    // MARK: - IG Metadata Footer

    private func igMetadataFooter(atom: Atom) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "camera.fill")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))

            if let username = igMediaData?.authorUsername {
                Text("@\(username)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            } else if let author = atom.richContent?.author, !author.isEmpty {
                Text("@\(author)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }

            Text("·")
                .foregroundColor(.white.opacity(0.3))

            Text("Reel")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(hex: "#E4405F"))
        }
        .frame(width: 280)
        .padding(.horizontal, 8)
    }

    // MARK: - IG Player Methods

    private func extractInstagramVideo(atom: Atom) {
        guard !igIsExtractingVideo else { return }
        igIsExtractingVideo = true

        Task {
            // Build original Instagram URL from atom
            guard let urlString = atom.url, let url = URL(string: urlString) else {
                igVideoFailed = true
                igIsExtractingVideo = false
                return
            }

            do {
                let mediaData = try await InstagramMediaCache.shared.getMedia(for: url)
                igMediaData = mediaData

                if let videoURL = mediaData.videoURL {
                    setupIGPlayer(videoURL: videoURL)
                    if let dur = mediaData.duration {
                        videoDuration = dur
                    }

                    // Auto-transcribe if slides are empty
                    let hasContent = transcriptSlides.contains { !$0.text.isEmpty }
                    if !hasContent {
                        await autoTranscribe(videoURL: videoURL, duration: mediaData.duration ?? 60)
                    }
                } else {
                    // Image post or extraction returned no video
                    igVideoFailed = true
                }
            } catch {
                print("SwipeStudy: Instagram video extraction failed: \(error)")
                igVideoFailed = true
            }

            igIsExtractingVideo = false
        }
    }

    // MARK: - Auto-Transcription

    private func autoTranscribe(videoURL: URL, duration: TimeInterval) async {
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
            case .mergingResults:
                self.autoTranscriptionProgress = "Merging results..."
            case .complete:
                self.autoTranscriptionProgress = "Complete"
            }
        }

        autoTranscriptionContentType = result.contentType

        if result.contentType != .empty {
            var finalSlides = result.slides

            // Claude cleanup if OCR confidence is low
            if result.averageOCRConfidence < 0.7 && result.contentType != .voiceoverOnly {
                autoTranscriptionProgress = "Cleaning up text..."
                if let cleaned = await InstagramAutoTranscriber.shared.cleanupWithClaude(slides: finalSlides) {
                    finalSlides = cleaned
                }
            }

            transcriptSlides = finalSlides
            saveSlideTranscript()
        }

        isAutoTranscribing = false
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
            guard let urlString = (currentAtom ?? atom).url, let url = URL(string: urlString) else {
                igIsExtractingVideo = false
                return
            }

            // Invalidate cache, re-extract
            InstagramMediaCache.shared.invalidate(for: url)

            do {
                let fresh = try await InstagramMediaCache.shared.getMedia(for: url)
                igMediaData = fresh
                if let videoURL = fresh.videoURL {
                    let item = AVPlayerItem(url: videoURL)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("TRANSCRIPT")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.4))

                if let contentType = autoTranscriptionContentType {
                    contentTypeBadge(contentType)
                }

                Spacer()
                Text("\(transcriptSlides.count) slide\(transcriptSlides.count == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
            }

            // Auto-transcription progress
            if isAutoTranscribing {
                autoTranscriptionProgressView
            }

            ForEach(Array(transcriptSlides.enumerated()), id: \.element.id) { index, slide in
                let slideComments = commentsForSlide(index)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Slide \(index + 1)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(gold.opacity(0.6))

                        // Source badge
                        if let source = slide.source {
                            slideSourceBadge(source)
                        }

                        // Comment count badge
                        if !slideComments.isEmpty {
                            Text("\(slideComments.count)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.black)
                                .frame(width: 16, height: 16)
                                .background(gold, in: Circle())
                        }

                        Spacer()

                        // Comment button
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
                                .font(.system(size: 11))
                                .foregroundColor(activeCommentSlideIndex == index ? gold : .white.opacity(0.3))
                        }
                        .buttonStyle(.plain)

                        Text("\(slide.text.count)/450")
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundColor(slide.text.count > 450 ? .red : .white.opacity(0.3))
                        if transcriptSlides.count > 1 {
                            Button {
                                withAnimation(ProMotionSprings.snappy) {
                                    transcriptSlides.remove(at: index)
                                    renumberSlides()
                                    debounceSaveSlides()
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.3))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    SlideTextEditor(
                        text: Binding(
                            get: { transcriptSlides[safe: index]?.text ?? "" },
                            set: { newValue in
                                guard index < transcriptSlides.count else { return }
                                transcriptSlides[index].text = String(newValue.prefix(450))
                                debounceSaveSlides()
                            }
                        ),
                        onNewSlide: {
                            let newSlide = TranscriptSlide(text: "", slideNumber: transcriptSlides.count + 1)
                            withAnimation(ProMotionSprings.snappy) {
                                transcriptSlides.insert(newSlide, at: index + 1)
                                renumberSlides()
                            }
                        }
                    )
                    .frame(minHeight: 60)

                    // Inline comment input for this slide
                    if activeCommentSlideIndex == index {
                        slideCommentInput(slideIndex: index)
                    }

                    // Expandable comment thread
                    if !slideComments.isEmpty {
                        slideCommentThread(comments: slideComments)
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(activeCommentSlideIndex == index ? gold.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 1)
                )
            }

            Button {
                withAnimation(ProMotionSprings.snappy) {
                    transcriptSlides.append(TranscriptSlide(text: "", slideNumber: transcriptSlides.count + 1))
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 11))
                    Text("Add Slide")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(gold.opacity(0.7))
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            // Analyze button
            if !slidesTranscriptText.isEmpty {
                Button {
                    saveSlideTranscript()
                    triggerManualAnalysis()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12))
                        Text(analysis == nil ? "Analyze" : "Re-analyze")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.black)
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

    private func loadSlides(from transcript: String) {
        guard !transcript.isEmpty else {
            transcriptSlides = [TranscriptSlide(text: "", slideNumber: 1)]
            return
        }
        // Try to decode persisted slides from JSON
        if let data = transcript.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([TranscriptSlide].self, from: data) {
            transcriptSlides = decoded
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
    }

    private func renumberSlides() {
        for i in transcriptSlides.indices {
            transcriptSlides[i].slideNumber = i + 1
        }
    }

    // MARK: - Auto-Transcription UI Helpers

    @ViewBuilder
    private var autoTranscriptionProgressView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.6)
                .tint(gold)
            Text(autoTranscriptionProgress)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))
            Spacer()
        }
        .padding(10)
        .background(gold.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
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
                .font(.system(size: 8))
            Text(label)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundColor(gold.opacity(0.8))
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
            }
        }()

        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 7))
            Text(label)
                .font(.system(size: 8, weight: .medium))
        }
        .foregroundColor(.white.opacity(0.4))
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(Color.white.opacity(0.06), in: Capsule())
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
                .font(.system(size: 10))
                .foregroundColor(gold.opacity(0.5))

            TextField("Add a comment...", text: $newCommentText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.9))
                .onSubmit {
                    addComment(toSlide: slideIndex)
                }

            Button(action: { addComment(toSlide: slideIndex) }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(newCommentText.trimmingCharacters(in: .whitespaces).isEmpty ? .white.opacity(0.2) : gold)
            }
            .buttonStyle(.plain)
            .disabled(newCommentText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
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
                .font(.system(size: 8))
                .foregroundColor(gold.opacity(0.4))
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(comment.text)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)

                Text(formatCommentDate(comment.createdAt))
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.2))
            }

            Spacer()

            Button {
                withAnimation(ProMotionSprings.snappy) {
                    deleteComment(comment)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.white.opacity(0.2))
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 6))
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

    private func saveSlideTranscript() {
        guard var current = currentAtom else { return }
        let combined = slidesTranscriptText
        current.body = combined
        var richContent = current.richContent ?? ResearchRichContent()
        richContent.transcript = combined
        richContent.transcriptStatus = "available"
        current.setRichContent(richContent)
        transcriptText = combined
        Task {
            try? await AtomRepository.shared.update(current)
            currentAtom = current
        }
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
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            thumbnailPlaceholder
        }
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.white.opacity(0.04))
            .frame(height: 200)
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 32))
                        .foregroundColor(gold.opacity(0.4))
                    Text("Swipe File")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.3))
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
                        .font(.system(size: 11))
                    Text("Analyze with Claude")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.black)
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
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
    }

    /// Trigger NLP + AI classification on whatever text is currently available
    private func triggerManualAnalysis() {
        // Determine the best available text
        let text = !instagramTranscript.isEmpty ? instagramTranscript : transcriptText
        guard !text.isEmpty else { return }

        // Update body/transcript so NLP + Claude see the content
        if !instagramTranscript.isEmpty, transcriptText.isEmpty {
            transcriptText = instagramTranscript
        }

        Task {
            // Phase 1: Run NLP on current atom
            isAnalyzing = true
            let atomForAnalysis = currentAtom ?? atom
            let nlpResult = await SwipeAnalyzer.shared.analyze(atom: atomForAnalysis)
            analysis = nlpResult
            isAnalyzing = false

            // Save NLP results
            let updated = atomForAnalysis.withSwipeAnalysis(nlpResult)
            try? await AtomRepository.shared.update(updated)
            currentAtom = updated

            // Phase 2: AI classification + deep analysis (single Claude call)
            isDeepAnalyzing = true
            let classifiedResult = await SwipeClassificationEngine.shared.classifyAndAnalyze(
                atom: currentAtom ?? atom
            )

            if classifiedResult.isFullyAnalyzed {
                let enriched = SwipeClassificationEngine.shared.mergeClassification(
                    classifiedResult, into: nlpResult
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

    // MARK: - Transcript Section

    @ViewBuilder
    private func transcriptSection(atom: Atom) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("TRANSCRIPT")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.4))

                if isFetchingTranscript {
                    ProgressView()
                        .scaleEffect(0.5)
                        .tint(gold)
                }

                Spacer()

                if let richContent = atom.richContent,
                   let author = richContent.author, !author.isEmpty {
                    Text(author)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.3))
                }
            }

            if !transcriptText.isEmpty {
                Text(transcriptText)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.8))
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
                            .font(.system(size: 10))
                        Text("Edit Transcript")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.35))
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
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.25))
                    .padding(.vertical, 12)
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
                                .font(.system(size: 12))
                                .foregroundColor(gold)
                            Text(insight)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.85))
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
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
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

                    // Emotional Arc — always visible, placeholder when empty
                    if let arc = analysis.emotionalArc, !arc.isEmpty {
                        EmotionalArcView(
                            dataPoints: arc,
                            dominantEmotion: analysis.dominantEmotion,
                            onSeek: { position in
                                // Convert normalized position (0-1) to timestamp using video duration
                                let timestamp = position * videoDuration
                                currentTimestamp = timestamp
                                if !isPlayerActive {
                                    isPlayerActive = true
                                }
                            },
                            transcriptText: transcriptText
                        )
                    } else {
                        emptyAnalysisCard(
                            title: "EMOTIONAL ARC",
                            icon: "waveform.path.ecg",
                            message: "Transcript required for emotional progression"
                        )
                    }

                    // Persuasion Stack — always visible, placeholder when empty
                    if let techniques = analysis.persuasionTechniques, !techniques.isEmpty {
                        PersuasionStackView(techniques: techniques)
                    } else {
                        emptyAnalysisCard(
                            title: "PERSUASION STACK",
                            icon: "chart.bar.fill",
                            message: "Transcript required for persuasion analysis"
                        )
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
            .padding(16)
        }
    }

    /// Styled placeholder for analysis cards that need more data
    private func emptyAnalysisCard(title: String, icon: String, message: String) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
            }

            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.12))
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.2))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .padding(16)
        .background(Color(hex: "#1A1A25"), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
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
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
            }

            VStack(spacing: 8) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.white.opacity(0.12))
                Text("Instagram Analysis")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.35))
                Text("Coming Soon")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.2))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
        .padding(16)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
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
            .background(Color(hex: "#1A1A25"), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )

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
            .background(Color(hex: "#1A1A25"), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )

            // Emotional arc skeleton
            VStack(alignment: .leading, spacing: 12) {
                ShimmerLine(width: 0.3, height: 12)
                ShimmerLine(width: 1.0, height: 80)
            }
            .padding(16)
            .background(Color(hex: "#1A1A25"), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
    }

    private var noAnalysisPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 28))
                .foregroundColor(gold.opacity(0.4))
            Text("No analysis available")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
            Text("Analysis will run automatically when content is available")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.3))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color(hex: "#1A1A25"), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Notes Section (Removed — replaced by per-slide inline commenting)

    // MARK: - Data Loading

    private func loadAtom() {
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

            var currentAnalysis: SwipeAnalysis
            if shouldRunLocalNLP {
                currentAnalysis = await SwipeAnalyzer.shared.analyze(atom: atomForAnalysis)
            } else {
                currentAnalysis = existingAnalysis!
            }

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
                    let enriched = SwipeClassificationEngine.shared.mergeClassification(
                        classifiedResult, into: currentAnalysis
                    )
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
        currentAtom = nil
        analysis = nil
        personalNotes = ""
        isPlayerActive = false
        currentTimestamp = 0
        videoDuration = 0
        instagramTranscript = ""
        transcriptText = ""
        transcriptFetchFailed = false
        // Reset IG player state
        igPlayer?.pause()
        igPlayer = nil
        igIsPlaying = false
        igIsExtractingVideo = false
        igVideoFailed = false
        igMediaData = nil

        Task {
            try? await Task.sleep(for: .milliseconds(100))
            if let fetched = try? await AtomRepository.shared.fetch(id: newEntityId) {
                currentAtom = fetched
                analysis = fetched.swipeAnalysis
                personalNotes = extractPersonalNotes(from: fetched)
                transcriptText = fetched.richContent?.transcript ?? fetched.body ?? ""

                if var existing = analysis, existing.studiedAt == nil {
                    existing = existing.markingStudied()
                    analysis = existing
                    let updated = fetched.withSwipeAnalysis(existing)
                    try? await AtomRepository.shared.update(updated)
                    currentAtom = updated
                }

                withAnimation(ProMotionSprings.snappy) {
                    hasAppeared = true
                }
            }
        }
    }

    // (needsTranscription removed — unified two-panel layout for all Instagram swipes)

    // MARK: - Edit Transcript Sheet

    private var editTranscriptSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Edit Transcript")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button("Cancel") {
                    showEditTranscript = false
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.5))
            }

            TextEditor(text: $editTranscriptText)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.9))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 200, maxHeight: 400)
                .padding(12)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

            HStack {
                Text("\(editTranscriptText.split(separator: " ").count) words")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                Button {
                    saveEditedTranscript()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                        Text("Save & Re-analyze")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.black)
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
        .background(Color(hex: "#0A0A0F"))
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
                .fill(Color.white.opacity(0.06))
                .frame(width: geo.size.width * width, height: height)
                .overlay(
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(Color.white.opacity(0.06))
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
            .fill(Color.white.opacity(0.06))
            .frame(width: width, height: 20)
            .modifier(ShimmerEffect())
    }
}

/// Animated shimmer circle for avatar-like skeleton elements
private struct ShimmerCircle: View {
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Color.white.opacity(0.06))
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

    private let gold = Color(hex: "#FFD700")

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("TAXONOMY")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.4))

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
        .background(Color(hex: "#1A1A25"), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Classification Source Badge

    @ViewBuilder
    private var classificationSourceBadge: some View {
        if let source = analysis?.classificationSource {
            HStack(spacing: 3) {
                Image(systemName: source == .ai ? "checkmark.circle.fill" : "pencil.circle.fill")
                    .font(.system(size: 9))
                Text(source == .ai ? "AI" : "Manual")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(source == .ai ? Color(hex: "#22C55E") : Color(hex: "#FBBF24"))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill((source == .ai ? Color(hex: "#22C55E") : Color(hex: "#FBBF24")).opacity(0.12))
            )
        }

        if let confidence = analysis?.classificationConfidence {
            Text("\(Int(confidence * 100))%")
                .font(.system(size: 9, weight: .bold).monospacedDigit())
                .foregroundColor(.white.opacity(0.4))
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
                        .font(.system(size: 9))
                }
                Text("Reclassify")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(gold.opacity(0.8))
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
                    .font(.system(size: 10))
                    .foregroundColor(gold)
                Text("AI Suggestion")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(gold)
            }

            VStack(alignment: .leading, spacing: 4) {
                if let narrative = suggestion.primaryNarrative {
                    suggestionRow("Narrative", value: narrative.displayName, color: narrative.color)
                }
                if let format = suggestion.swipeContentFormat {
                    suggestionRow("Format", value: format.displayName, color: format.color)
                }
                if let niche = suggestion.niche {
                    suggestionRow("Niche", value: niche, color: .white.opacity(0.7))
                }
            }

            HStack(spacing: 8) {
                Button {
                    onAcceptReclassification()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                        Text("Accept")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(gold, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    onRejectReclassification()
                } label: {
                    Text("Keep Current")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(gold.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(gold.opacity(0.2), lineWidth: 1)
        )
    }

    private func suggestionRow(_ label: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label + ":")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(color)
        }
    }

    // MARK: - Dimension Rows

    private var narrativeRow: some View {
        taxonomyDropdownRow(
            label: "Narrative",
            icon: analysis?.classificationSource == .ai ? "checkmark.circle.fill" : "pencil.circle.fill",
            iconColor: analysis?.classificationSource == .ai ? Color(hex: "#22C55E") : Color(hex: "#FBBF24")
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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(n.color)
            } else {
                Text("Select...")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.3))
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(n.color)
            } else {
                Text("None")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.3))
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }

    private var contentFormatRow: some View {
        taxonomyDropdownRow(
            label: "Format",
            icon: analysis?.classificationSource == .ai ? "checkmark.circle.fill" : "pencil.circle.fill",
            iconColor: analysis?.classificationSource == .ai ? Color(hex: "#22C55E") : Color(hex: "#FBBF24")
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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(f.color)
            } else {
                Text("Select...")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.3))
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }

    private var nicheRow: some View {
        taxonomyDropdownRow(label: "Niche", icon: nil, iconColor: .clear) {
            HStack(spacing: 4) {
                if let niche = analysis?.niche, !niche.isEmpty {
                    Text(niche)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(gold.opacity(0.8))
                } else {
                    Text("No niche")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
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
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func creatorLinkedLabel(creatorUUID: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "person.fill")
                .font(.system(size: 9))
                .foregroundColor(gold.opacity(0.7))
            Text(linkedCreatorName ?? "Creator")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(gold.opacity(0.9))
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
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
                Text("Link creator")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var creatorSearchField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
                TextField("Search creators...", text: $creatorSearchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.white)
                    .onChange(of: creatorSearchText) { _ in filterCreators() }
                Button {
                    showCreatorSearch = false
                    creatorSearchText = ""
                    creatorSearchResults = []
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
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
                        Divider().background(Color.white.opacity(0.08))
                        creatorCreateNewRow
                    }
                }
                .background(Color(hex: "#1A1A25"), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
            } else if !creatorSearchText.isEmpty {
                // No matches — show create option
                VStack(spacing: 0) {
                    creatorCreateNewRow
                }
                .background(Color(hex: "#1A1A25"), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
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
                    .font(.system(size: 9))
                    .foregroundColor(gold.opacity(0.6))
                Text(creator.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
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
                    .font(.system(size: 9))
                    .foregroundColor(gold)
                Text("Create \"\(creatorSearchText)\"")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(gold)
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
                        .font(.system(size: 9))
                        .foregroundColor(iconColor)
                }
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
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
/// Enter creates a new slide (via callback), Shift+Enter inserts a newline.
private struct SlideTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onNewSlide: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .white.withAlphaComponent(0.85)
        textView.backgroundColor = .clear
        textView.insertionPointColor = .white
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.delegate = context.coordinator

        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false

        textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onNewSlide: onNewSlide)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onNewSlide: () -> Void

        init(text: Binding<String>, onNewSlide: @escaping () -> Void) {
            self.text = text
            self.onNewSlide = onNewSlide
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Enter without Shift → new slide
                if !NSEvent.modifierFlags.contains(.shift) {
                    onNewSlide()
                    return true
                }
            }
            return false
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

