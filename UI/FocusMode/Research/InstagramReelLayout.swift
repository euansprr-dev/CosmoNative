// CosmoOS/UI/FocusMode/Research/InstagramReelLayout.swift
// Side-by-side layout for Instagram reels and vertical video content
// Per Instagram Research PRD Addendum

import SwiftUI
import AVKit

// MARK: - Instagram Reel Layout

/// Side-by-side layout for Instagram reels with video on left and transcript on right
struct InstagramReelLayout: View {
    let atom: Atom
    @Binding var currentTimestamp: TimeInterval
    let duration: TimeInterval?
    let instagramData: InstagramData
    let onSeek: (TimeInterval) -> Void
    let onAddSection: (TimeInterval) -> Void
    let onSectionTap: (ManualTranscriptSection) -> Void
    let onAnnotationAdd: (UUID, InstagramAnnotation.AnnotationType) -> Void
    let onAnnotationEdit: (InstagramAnnotation, RichDocument) -> Void
    let onAnnotationDelete: (UUID) -> Void

    @State private var isPlaying = false
    @State private var player: AVPlayer?
    @State private var isRefreshing = false
    // Playback ticks land on the clock, not the currentTimestamp binding — a
    // 10Hz write into the view model re-rendered the whole focus mode per tick.
    @State private var clock = ReelPlaybackClock()
    @State private var timeObserverToken: Any?
    @State private var playbackFailureObserver: NSObjectProtocol?

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            // Left panel: Video player (9:16 aspect ratio)
            leftVideoPanel
                .frame(width: 320)

            // Right panel: Transcript & annotations
            rightTranscriptPanel
                .frame(maxWidth: .infinity)
        }
        .onAppear {
            clock.tick(currentTimestamp)
            clock.updateSections(sectionWindows, fallbackDuration: duration)
            setupPlayer()
        }
        .onChange(of: sectionWindows) { _, windows in
            clock.updateSections(windows, fallbackDuration: duration)
        }
        .onDisappear {
            // The view model's copy feeds saveState — sync it once on exit.
            currentTimestamp = clock.currentTimestamp
            teardownPlayer()
        }
    }

    private var sectionWindows: [ReelPlaybackClock.SectionWindow] {
        (instagramData.manualTranscript?.sections ?? []).map {
            ReelPlaybackClock.SectionWindow(id: $0.id, start: $0.startTime, end: $0.endTime)
        }
    }

    // MARK: - Left Video Panel

    private var leftVideoPanel: some View {
        VStack(spacing: 12) {
            // Video container with corner dots
            ZStack {
                // Video player
                videoPlayerView
                    .frame(width: 280, height: 498)  // 9:16 aspect ratio
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(DS.borderActive, lineWidth: 0.5)
                    )

                // Corner connection dots
                connectionDots
            }

            // Native AVPlayerView controls handle playback

            // Metadata footer
            metadataFooter
        }
    }

    private var videoPlayerView: some View {
        ZStack {
            if let player = player {
                // AVPlayerView, not SwiftUI VideoPlayer — the latter aborts the
                // app on first metadata instantiation (see CosmoVideoPlayerView).
                CosmoVideoPlayerView(player: player)
            } else if let thumbnailURL = instagramData.extractedMediaURL {
                // Show thumbnail while loading
                AsyncImage(url: thumbnailURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(DS.surface.opacity(0.6))
                        .overlay(
                            ProgressView()
                                .tint(.white)
                        )
                }
            } else {
                // Placeholder for failed extraction
                Rectangle()
                    .fill(DS.surface.opacity(0.6))
                    .overlay(
                        VStack(spacing: 12) {
                            Image(systemName: "video.slash")
                                .font(.system(size: 32))
                                .foregroundColor(DS.textSecondary)
                            Text("Could not load video")
                                .font(.system(size: 12))
                                .foregroundColor(DS.textSecondary)
                        }
                    )
            }

            // Refreshing indicator
            if isRefreshing {
                Rectangle()
                    .fill(.black.opacity(0.5))
                    .overlay(
                        VStack(spacing: 8) {
                            ProgressView()
                                .tint(.white)
                            Text("Refreshing video link…")
                                .font(.system(size: 11))
                                .foregroundColor(DS.textSecondary)
                        }
                    )
            }
        }
    }

    private var connectionDots: some View {
        GeometryReader { geometry in
            // Top dot
            Circle()
                .fill(CosmoColors.emerald.opacity(0.6))
                .frame(width: 6, height: 6)
                .position(x: geometry.size.width / 2, y: 0)

            // Bottom dot
            Circle()
                .fill(CosmoColors.emerald.opacity(0.6))
                .frame(width: 6, height: 6)
                .position(x: geometry.size.width / 2, y: geometry.size.height)

            // Left dot
            Circle()
                .fill(CosmoColors.emerald.opacity(0.6))
                .frame(width: 6, height: 6)
                .position(x: 0, y: geometry.size.height / 2)

            // Right dot (connects to transcript)
            Circle()
                .fill(CosmoColors.emerald)
                .frame(width: 8, height: 8)
                .position(x: geometry.size.width, y: geometry.size.height / 2)
                .overlay(
                    // Subtle pulse animation
                    Circle()
                        .stroke(CosmoColors.emerald.opacity(0.3), lineWidth: 2)
                        .frame(width: 14, height: 14)
                        .position(x: geometry.size.width, y: geometry.size.height / 2)
                )
        }
        .allowsHitTesting(false)
    }

    private var playbackControls: some View {
        VStack(spacing: 8) {
            // Timeline with markers
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(DS.borderActive)
                        .frame(height: 4)

                    // Progress
                    Capsule()
                        .fill(CosmoColors.emerald)
                        .frame(width: progressWidth(in: geometry.size.width), height: 4)

                    // Section markers
                    ForEach(instagramData.manualTranscript?.sections ?? []) { section in
                        markerDot(for: section, in: geometry.size.width)
                    }

                    // Scrubber
                    Circle()
                        .fill(.white)
                        .frame(width: 12, height: 12)
                        .offset(x: progressWidth(in: geometry.size.width) - 6)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let ratio = value.location.x / geometry.size.width
                                    let time = (duration ?? 60) * max(0, min(1, ratio))
                                    onSeek(time)
                                }
                        )
                }
            }
            .frame(height: 12)
            .padding(.horizontal, 4)

            // Time display
            HStack {
                Text(formatTime(currentTimestamp))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(DS.textSecondary)

                Spacer()

                Text(formatTime(duration ?? 0))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(DS.textSecondary)
            }
        }
        .padding(.horizontal, 8)
    }

    private func markerDot(for section: ManualTranscriptSection, in width: CGFloat) -> some View {
        let ratio = section.startTime / (duration ?? 60)
        let xOffset = width * ratio

        return Circle()
            .fill(DS.accent)
            .frame(width: 6, height: 6)
            .offset(x: xOffset - 3)
            .onTapGesture {
                onSectionTap(section)
            }
    }

    private func progressWidth(in width: CGFloat) -> CGFloat {
        guard let duration = duration, duration > 0 else { return 0 }
        return width * (currentTimestamp / duration)
    }

    private var metadataFooter: some View {
        HStack(spacing: 8) {
            // Instagram icon
            Image(systemName: "camera.fill")
                .font(.system(size: 11))
                .foregroundColor(DS.textSecondary)

            // Username
            if let username = instagramData.authorUsername {
                Text("@\(username)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.textSecondary)
            }

            Text("·")
                .foregroundColor(DS.textMuted)

            // Type badge
            Text("Reel")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(hex: "#E4405F"))  // Instagram pink
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Right Transcript Panel

    private var rightTranscriptPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            transcriptHeader

            // Transcript sections
            ScrollView {
                VStack(spacing: 12) {
                    if let transcript = instagramData.manualTranscript {
                        ForEach(transcript.sections) { section in
                            ManualTranscriptSectionView(
                                section: section,
                                isActive: clock.activeSectionIDs.contains(section.id),
                                onTap: { onSectionTap(section) },
                                onAddAnnotation: { type in
                                    // The view model stamps annotations from its
                                    // own copy — sync it at action time.
                                    currentTimestamp = clock.currentTimestamp
                                    onAnnotationAdd(section.id, type)
                                },
                                onAnnotationEdit: onAnnotationEdit,
                                onAnnotationDelete: onAnnotationDelete
                            )
                        }
                    } else {
                        emptyTranscriptState
                    }

                    // Add section button
                    addSectionButton
                }
                .padding()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DS.surface.opacity(0.5))
        )
    }

    private var transcriptHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Transcript & Annotations")
                    .dsSmallCapsLabel()

                Text("Manual transcription · \(sectionCount) sections · \(annotationCount) annotations")
                    .font(.system(size: 11))
                    .foregroundColor(DS.textMuted)
            }

            Spacer()

            // Add section at current time
            Button {
                onAddSection(clock.currentTimestamp)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text("Add Section")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(DS.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(DS.borderActive, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    private var emptyTranscriptState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.system(size: 28))
                .foregroundColor(DS.textMuted)

            Text("No transcript yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(DS.textSecondary)

            Text("Press S while watching to add a section at the current timestamp")
                .font(.system(size: 12))
                .foregroundColor(DS.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }

    private var addSectionButton: some View {
        ReelAddSectionButton(clock: clock, onAddSection: onAddSection)
    }

    // MARK: - Helpers

    private var sectionCount: Int {
        instagramData.manualTranscript?.sections.count ?? 0
    }

    private var annotationCount: Int {
        instagramData.manualTranscript?.sections.reduce(0) { $0 + $1.annotations.count } ?? 0
    }

    private func formatTime(_ time: TimeInterval) -> String {
        formatReelTime(time)
    }

    private func setupPlayer() {
        guard let videoURL = instagramData.extractedMediaURL else {
            // Try to refresh if expired
            if instagramData.isExpired {
                refreshVideo()
            }
            return
        }

        let item = AVPlayerItem(url: videoURL)
        player = AVPlayer(playerItem: item)

        // Observe playback time — token stashed so teardown can remove it
        // (AVFoundation requires removeTimeObserver before player release).
        timeObserverToken = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [clock] time in
            MainActor.assumeIsolated {
                clock.tick(time.seconds)
            }
        }

        // Handle playback errors (expired URL)
        playbackFailureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [self] _ in
            self.refreshVideo()
        }
    }

    private func teardownPlayer() {
        if let timeObserverToken {
            player?.removeTimeObserver(timeObserverToken)
        }
        timeObserverToken = nil
        if let playbackFailureObserver {
            NotificationCenter.default.removeObserver(playbackFailureObserver)
        }
        playbackFailureObserver = nil
        player?.pause()
        player = nil
    }

    private func togglePlayback() {
        if isPlaying {
            player?.pause()
        } else {
            player?.play()
        }
        isPlaying.toggle()
    }

    private func refreshVideo() {
        guard !isRefreshing else { return }
        isRefreshing = true

        Task {
            do {
                let fresh = try await InstagramMediaCache.shared.getMedia(for: instagramData.originalURL)
                if let videoURL = fresh.videoURL {
                    let item = AVPlayerItem(url: videoURL)
                    player?.replaceCurrentItem(with: item)
                    // Resume playback from same position
                    let resumeAt = clock.currentTimestamp
                    if resumeAt > 0 {
                        await player?.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600))
                    }
                }
            } catch {
                print("Failed to refresh Instagram video: \(error)")
            }
            isRefreshing = false
        }
    }
}

// MARK: - Playback Clock

/// 10Hz playback ticks land here instead of view state: only the leaf that
/// reads `currentTimestamp` re-renders per tick, and the transcript reads the
/// segment-granularity `activeSectionIDs` bucket, which changes only at
/// section boundaries.
@Observable @MainActor
final class ReelPlaybackClock {
    struct SectionWindow: Equatable {
        let id: UUID
        let start: TimeInterval
        let end: TimeInterval?
    }

    var currentTimestamp: TimeInterval = 0
    var activeSectionIDs: Set<UUID> = []

    private var windows: [SectionWindow] = []
    private var fallbackDuration: TimeInterval?

    func updateSections(_ windows: [SectionWindow], fallbackDuration: TimeInterval?) {
        self.windows = windows
        self.fallbackDuration = fallbackDuration
        refreshActiveSections()
    }

    func tick(_ seconds: TimeInterval) {
        currentTimestamp = seconds
        refreshActiveSections()
    }

    private func refreshActiveSections() {
        let active = Set(
            windows
                .filter {
                    currentTimestamp >= $0.start
                        && currentTimestamp < ($0.end ?? fallbackDuration ?? .infinity)
                }
                .map(\.id)
        )
        if active != activeSectionIDs {
            activeSectionIDs = active
        }
    }
}

/// Leaf reader of the clock — only this label pays the per-tick re-render.
private struct ReelAddSectionButton: View {
    let clock: ReelPlaybackClock
    let onAddSection: (TimeInterval) -> Void

    var body: some View {
        Button {
            onAddSection(clock.currentTimestamp)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14))
                Text("Add Section at \(formatReelTime(clock.currentTimestamp))")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(CosmoColors.emerald)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(CosmoColors.emerald.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private func formatReelTime(_ time: TimeInterval) -> String {
    let minutes = Int(time) / 60
    let seconds = Int(time) % 60
    return "\(minutes):\(String(format: "%02d", seconds))"
}

// MARK: - Manual Transcript Section View

struct ManualTranscriptSectionView: View {
    let section: ManualTranscriptSection
    let isActive: Bool
    let onTap: () -> Void
    let onAddAnnotation: (InstagramAnnotation.AnnotationType) -> Void
    let onAnnotationEdit: (InstagramAnnotation, RichDocument) -> Void
    let onAnnotationDelete: (UUID) -> Void

    @State private var isEditing = false
    @State private var editText: String = ""
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header with timestamp
            HStack {
                Text(section.displayTimeRange)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(isActive ? CosmoColors.emerald : DS.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        isActive
                            ? CosmoColors.emerald.opacity(0.15)
                            : DS.border,
                        in: Capsule()
                    )

                Spacer()

                if isHovering {
                    HStack(spacing: 4) {
                        Button {
                            isEditing = true
                            editText = section.text
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 10))
                                .foregroundColor(DS.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Section content
            if isEditing {
                TextEditor(text: $editText)
                    .font(.system(size: 13))
                    .foregroundColor(DS.text)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 60)
                    .padding(8)
                    .background(DS.border, in: RoundedRectangle(cornerRadius: 8))

                HStack {
                    Button("Cancel") {
                        isEditing = false
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(DS.textSecondary)

                    Spacer()

                    Button("Save") {
                        // TODO: Save changes
                        isEditing = false
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(CosmoColors.emerald)
                }
                .font(.system(size: 12, weight: .medium))
            } else {
                Text("\"\(section.text)\"")
                    .font(.system(size: 13))
                    .foregroundColor(DS.text)
                    .italic()
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Annotations
            ForEach(section.annotations) { annotation in
                AnnotationBubbleView(
                    annotation: annotation,
                    onEdit: { updatedDocument in onAnnotationEdit(annotation, updatedDocument) },
                    onDelete: { onAnnotationDelete(annotation.id) }
                )
            }

            // Add annotation buttons (on hover)
            if isHovering && !isEditing {
                HStack(spacing: 8) {
                    annotationButton(type: .note, icon: "note.text", color: CosmoColors.emerald)
                    annotationButton(type: .question, icon: "questionmark.circle", color: .orange)
                    annotationButton(type: .insight, icon: "lightbulb.fill", color: .purple)
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isActive ? DS.border : DS.borderSubtle)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isActive ? CosmoColors.emerald.opacity(0.3) : Color.clear,
                            lineWidth: 1
                        )
                )
        )
        .onTapGesture {
            onTap()
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private func annotationButton(type: InstagramAnnotation.AnnotationType, icon: String, color: Color) -> some View {
        Button {
            onAddAnnotation(type)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color)
                .padding(6)
                .background(color.opacity(0.15), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Annotation Bubble View

struct AnnotationBubbleView: View {
    let annotation: InstagramAnnotation
    let onEdit: (RichDocument) -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var document: RichDocument = .empty

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                // Type label
                Text(annotation.type.rawValue)
                    .font(DS.smallCaps)
                    .foregroundStyle(annotationColor)

                // Content
                CosmoDocumentEditor(
                    document: $document,
                    fontSize: 12,
                    compact: true,
                    placeholder: "Add note…",
                    allowSlashCommands: false,
                    allowMentions: true,
                    allowSelectionMenu: false,
                    allowImages: false,
                    onDocumentChange: { document, _ in
                        onEdit(document)
                    }
                )
                .frame(minHeight: 28)
            }

            Spacer()

            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(DS.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(annotationColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .onAppear {
            document = annotation.resolvedDocument
        }
        .onChange(of: annotation) { _, updated in
            document = updated.resolvedDocument
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var annotationColor: Color {
        switch annotation.type {
        case .note: return CosmoColors.emerald
        case .question: return .orange
        case .insight: return .purple
        }
    }
}
