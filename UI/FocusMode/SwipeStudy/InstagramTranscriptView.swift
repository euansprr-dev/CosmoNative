// CosmoOS/UI/FocusMode/SwipeStudy/InstagramTranscriptView.swift
// Manual transcript entry view for Instagram swipe files
// Shown when a swipe has no transcript and needs manual transcription
// February 2026

import SwiftUI
import AppKit
import AVKit

struct InstagramTranscriptView: View {
    let atom: Atom
    let onAnalysisComplete: (Atom) -> Void

    @State private var transcript: String = ""
    @State private var isAnalyzing = false
    @State private var analysisError: String?

    // Native IG player state
    @State private var igPlayer: AVPlayer?
    @State private var igIsPlaying: Bool = false
    @State private var igIsExtractingVideo: Bool = false
    @State private var igVideoFailed: Bool = false
    @State private var igMediaData: InstagramMediaData?
    @State private var igCurrentTime: TimeInterval = 0

    // Auto-transcription state
    @State private var isAutoTranscribing = false
    @State private var autoTranscriptionProgress: String = ""
    @State private var autoTranscriptionContentType: TranscriptionContentType?

    private let gold = Color(hex: "#FFD700")

    private var wordCount: Int {
        transcript.split(separator: " ").count
    }

    private var canAnalyze: Bool {
        wordCount >= 10 && !isAnalyzing
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // URL display with Open in Browser
                urlSection

                // Instagram embed (if shortcode available)
                embedSection

                // Transcript editor
                transcriptEditor

                // Word count + Run Analysis
                actionBar
            }
            .padding(24)
        }
        .onAppear {
            // Pre-populate with existing body if available
            if let existingBody = atom.body, !existingBody.isEmpty {
                transcript = existingBody
            }
        }
    }

    // MARK: - URL Section

    private var urlSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "#E879F9"))

            if let url = atom.url {
                Text(url)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                if let urlString = atom.url, let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "safari")
                        .font(.system(size: 11))
                    Text("Open in Browser")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Native Video Section

    @ViewBuilder
    private var embedSection: some View {
        VStack(spacing: 12) {
            ZStack {
                if igIsExtractingVideo && igPlayer == nil {
                    // Extracting state — thumbnail placeholder + spinner
                    igThumbnailPlaceholder
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
                    // Success — native AVPlayer
                    ZStack {
                        VideoPlayer(player: player)
                            .disabled(true)

                        if !igIsPlaying {
                            Button {
                                togglePlayback()
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

                        if igIsExtractingVideo {
                            Rectangle()
                                .fill(.black.opacity(0.5))
                                .overlay(
                                    VStack(spacing: 8) {
                                        ProgressView().tint(.white)
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
                        togglePlayback()
                    }
                } else if igVideoFailed {
                    // Failed — thumbnail + open in browser
                    igThumbnailPlaceholder
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
                                if let urlString = atom.url, let openURL = URL(string: urlString) {
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
                    igThumbnailPlaceholder
                        .frame(width: 280, height: 498)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .frame(maxWidth: .infinity)

            // Playback controls
            if igPlayer != nil {
                igPlaybackControls
            }

            // Metadata footer
            igMetadataFooter
        }
        .onAppear {
            extractVideo()
        }
        .onDisappear {
            igPlayer?.pause()
            igPlayer = nil
        }
    }

    // MARK: - IG Thumbnail

    private var igThumbnailPlaceholder: some View {
        Group {
            if let thumbURL = igMediaData?.thumbnailURL {
                AsyncImage(url: thumbURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color.black.opacity(0.3))
                }
            } else if let thumbnailUrl = atom.richContent?.thumbnailUrl, !thumbnailUrl.isEmpty,
                      let url = URL(string: thumbnailUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color.black.opacity(0.3))
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
    }

    // MARK: - IG Playback Controls

    private var igPlaybackControls: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 4)

                    Capsule()
                        .fill(gold)
                        .frame(width: igProgressWidth(in: geometry.size.width), height: 4)

                    Circle()
                        .fill(.white)
                        .frame(width: 12, height: 12)
                        .offset(x: igProgressWidth(in: geometry.size.width) - 6)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let ratio = max(0, min(1, value.location.x / geometry.size.width))
                                    let dur = igMediaData?.duration ?? 60
                                    let time = dur * ratio
                                    igCurrentTime = time
                                    igPlayer?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
                                }
                        )
                }
            }
            .frame(height: 12)
            .padding(.horizontal, 4)

            HStack {
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: igIsPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)

                Text(formatTime(igCurrentTime))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))

                Spacer()

                Text(formatTime(igMediaData?.duration ?? 0))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .frame(width: 280)
        .padding(.horizontal, 8)
    }

    // MARK: - IG Metadata Footer

    private var igMetadataFooter: some View {
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

    private func extractVideo() {
        guard !igIsExtractingVideo else { return }
        igIsExtractingVideo = true

        Task {
            guard let urlString = atom.url, let url = URL(string: urlString) else {
                igVideoFailed = true
                igIsExtractingVideo = false
                return
            }

            do {
                let mediaData = try await InstagramMediaCache.shared.getMedia(for: url)
                igMediaData = mediaData

                if let videoURL = mediaData.videoURL {
                    setupPlayer(videoURL: videoURL)

                    // Auto-transcribe if transcript is empty
                    if transcript.isEmpty {
                        await autoTranscribe(videoURL: videoURL, duration: mediaData.duration ?? 60)
                    }
                } else {
                    igVideoFailed = true
                }
            } catch {
                print("InstagramTranscriptView: Video extraction failed: \(error)")
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
            var slides = result.slides

            // Claude cleanup if OCR confidence is low
            if result.averageOCRConfidence < 0.7 && result.contentType != .voiceoverOnly {
                autoTranscriptionProgress = "Cleaning up text..."
                if let cleaned = await InstagramAutoTranscriber.shared.cleanupWithClaude(slides: slides) {
                    slides = cleaned
                }
            }

            // Combine slide texts into the transcript TextEditor
            transcript = slides.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n\n")
        }

        isAutoTranscribing = false
    }

    private func setupPlayer(videoURL: URL) {
        let item = AVPlayerItem(url: videoURL)
        let player = AVPlayer(playerItem: item)

        player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { time in
            self.igCurrentTime = time.seconds
        }

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            self.refreshVideo()
        }

        igPlayer = player
    }

    private func togglePlayback() {
        if igIsPlaying {
            igPlayer?.pause()
        } else {
            igPlayer?.play()
        }
        igIsPlaying.toggle()
    }

    private func refreshVideo() {
        guard !igIsExtractingVideo else { return }
        igIsExtractingVideo = true

        Task {
            guard let urlString = atom.url, let url = URL(string: urlString) else {
                igIsExtractingVideo = false
                return
            }

            InstagramMediaCache.shared.invalidate(for: url)

            do {
                let fresh = try await InstagramMediaCache.shared.getMedia(for: url)
                igMediaData = fresh
                if let videoURL = fresh.videoURL {
                    let item = AVPlayerItem(url: videoURL)
                    igPlayer?.replaceCurrentItem(with: item)
                    if igCurrentTime > 0 {
                        await igPlayer?.seek(to: CMTime(seconds: igCurrentTime, preferredTimescale: 600))
                    }
                }
            } catch {
                print("InstagramTranscriptView: Video refresh failed: \(error)")
            }

            igIsExtractingVideo = false
        }
    }

    private func igProgressWidth(in width: CGFloat) -> CGFloat {
        let dur = igMediaData?.duration ?? 0
        guard dur > 0 else { return 0 }
        return width * (igCurrentTime / dur)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    // MARK: - Transcript Editor

    private var transcriptEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TRANSCRIPT")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.4))

                if let contentType = autoTranscriptionContentType {
                    igContentTypeBadge(contentType)
                }

                Spacer()
            }

            // Auto-transcription progress
            if isAutoTranscribing {
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

            ZStack(alignment: .topLeading) {
                TextEditor(text: $transcript)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.9))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 180, maxHeight: 320)
                    .padding(12)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                if transcript.isEmpty {
                    Text("Watch the reel above and type out the script here...")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.2))
                        .padding(.leading, 16)
                        .padding(.top, 20)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 16) {
            // Word count indicator
            HStack(spacing: 4) {
                Image(systemName: "character.cursor.ibeam")
                    .font(.system(size: 10))
                Text("\(wordCount) words")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(wordCount >= 10 ? .white.opacity(0.5) : Color(hex: "#F97316").opacity(0.8))

            if wordCount > 0 && wordCount < 10 {
                Text("(need at least 10 words)")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#F97316").opacity(0.6))
            }

            Spacer()

            if let error = analysisError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#EF4444").opacity(0.8))
                    .lineLimit(1)
            }

            // Run Analysis button
            if isAnalyzing {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .tint(gold)
                    Text("Analyzing...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            } else {
                Button {
                    runAnalysis()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11))
                        Text("Run Analysis")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(canAnalyze ? .black : .white.opacity(0.3))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        canAnalyze ? gold : Color.white.opacity(0.06),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canAnalyze)
            }
        }
    }

    // MARK: - Content Type Badge

    @ViewBuilder
    private func igContentTypeBadge(_ type: TranscriptionContentType) -> some View {
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

    // MARK: - Analysis

    private func runAnalysis() {
        guard canAnalyze else { return }

        isAnalyzing = true
        analysisError = nil

        Task {
            // a) Save transcript to atom.body
            var updatedAtom = atom
            updatedAtom.body = transcript

            // Update richContent with transcript
            var richContent = updatedAtom.richContent ?? ResearchRichContent()
            richContent.transcript = transcript
            richContent.transcriptStatus = "available"
            updatedAtom.setRichContent(richContent)

            // b) Update processing status
            updatedAtom.processingStatus = "complete"

            // Save the intermediate state
            _ = try? await AtomRepository.shared.update(updatedAtom)

            // c) Run analysis (SwipeAnalyzer as primary, SwipeClassificationEngine as future upgrade)
            // TODO: Call SwipeClassificationEngine.shared.classifyAndAnalyze(atom:) when WP2 is merged
            let nlpResult = await SwipeAnalyzer.shared.analyze(atom: updatedAtom)

            // d) Mark analysis complete
            var analysis = nlpResult
            analysis.analyzedAt = ISO8601DateFormatter().string(from: Date())

            // e) Save the updated atom with analysis
            updatedAtom = updatedAtom.withSwipeAnalysis(analysis)
            _ = try? await AtomRepository.shared.update(updatedAtom)

            // Run deep analysis in parallel
            let deepResult = await SwipeAnalyzer.shared.deepAnalyze(
                title: updatedAtom.title ?? "Untitled",
                transcript: transcript
            )

            if let deepResult = deepResult {
                let enriched = SwipeAnalyzer.shared.mergeDeepAnalysis(deepResult, into: analysis)
                updatedAtom = updatedAtom.withSwipeAnalysis(enriched)
                _ = try? await AtomRepository.shared.update(updatedAtom)
            }

            // f) Transition to full analysis view
            await MainActor.run {
                isAnalyzing = false
                onAnalysisComplete(updatedAtom)
            }
        }
    }
}
