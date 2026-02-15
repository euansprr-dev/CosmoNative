// CosmoOS/UI/FocusMode/Research/ResearchCoreView.swift
// Anchored content display for Research Focus Mode
// Video player, article reader, PDF viewer with timeline markers
// December 2025 - Premium design matching Sanctuary aesthetic

import SwiftUI
import AVKit
import WebKit
import Combine

// MARK: - Research Core View

/// The anchored content component for Research Focus Mode.
/// Displays video player, article content, or PDF with timeline annotation markers.
struct ResearchCoreView: View {
    // MARK: - Properties

    /// The research atom being displayed
    let atom: Atom

    /// Current playback timestamp (for video)
    @Binding var currentTimestamp: TimeInterval

    /// All timeline markers
    let timelineMarkers: [TimelineMarker]

    /// Total duration (for video)
    let duration: TimeInterval

    /// Content type
    let contentType: ResearchContentType

    /// Source metadata
    let source: ResearchSource?

    /// Callback when timeline position changes
    let onSeek: (TimeInterval) -> Void

    /// Callback when marker is tapped
    let onMarkerTap: (TimelineMarker) -> Void

    /// Callback to copy URL
    let onCopyURL: () -> Void

    /// Callback to open in browser
    let onOpenInBrowser: () -> Void

    // MARK: - State

    @State private var isHovered = false
    @State private var showControls = true
    @State private var player: AVPlayer?

    // MARK: - Computed

    private var videoURL: URL? {
        guard let urlString = source?.url else { return nil }
        return URL(string: urlString)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            headerBar

            // Main content area
            contentArea
                .frame(maxHeight: contentType == .video ? 360 : 500)

            // Timeline (video only)
            if contentType == .video {
                timelineSection
            }
        }
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(isHovered ? 0.2 : 0.1), lineWidth: 1)
        )
        .shadow(
            color: Color.black.opacity(0.3),
            radius: isHovered ? 20 : 12,
            y: isHovered ? 8 : 4
        )
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                isHovered = hovering
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            // Content type badge
            HStack(spacing: 6) {
                Image(systemName: contentType.icon)
                    .font(.system(size: 12, weight: .medium))
                Text(contentType.label)
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.8)
            }
            .foregroundColor(accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(accentColor.opacity(0.15), in: Capsule())

            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                // Copy URL button
                Button(action: onCopyURL) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                        Text("Copy")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(Color.white.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)

                // Open in browser button
                Button(action: onOpenInBrowser) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 11))
                        Text("Open")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(Color.white.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.03))
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title and metadata
            titleSection

            // Actual content
            switch contentType {
            case .video:
                videoContent
            case .article:
                articleContent
            case .pdf:
                pdfContent
            case .social:
                socialContent
            case .generic:
                genericContent
            }
        }
        .padding(16)
    }

    // MARK: - Title Section

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title
            Text(atom.title ?? "Untitled Research")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(2)

            // Metadata row
            HStack(spacing: 8) {
                if let author = source?.author ?? source?.channelName {
                    Text(author)
                        .font(.system(size: 13))
                        .foregroundColor(Color.white.opacity(0.6))
                }

                if let platform = source?.platform {
                    Text("·")
                        .foregroundColor(Color.white.opacity(0.4))
                    Text(platform)
                        .font(.system(size: 13))
                        .foregroundColor(Color.white.opacity(0.6))
                }

                if let durationStr = source?.durationString {
                    Text("·")
                        .foregroundColor(Color.white.opacity(0.4))
                    Text(durationStr)
                        .font(.system(size: 13))
                        .foregroundColor(Color.white.opacity(0.6))
                }
            }
        }
    }

    // MARK: - Video Content

    private var videoContent: some View {
        ZStack {
            if let videoId = extractYouTubeVideoId(from: source?.url) {
                // YouTube video with interactive player
                YouTubeFocusModePlayer(
                    videoId: videoId,
                    currentTime: $currentTimestamp,
                    onDurationLoaded: { loadedDuration in
                        // Duration is communicated back from the player
                        print("📹 Video duration loaded: \(loadedDuration)s")
                    },
                    onSeek: onSeek
                )
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if let thumbnailURL = source?.thumbnailURL, let url = URL(string: thumbnailURL) {
                // Fallback: Show thumbnail with open button for non-YouTube videos
                ZStack {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(16/9, contentMode: .fill)
                        case .failure, .empty:
                            videoPlaceholder
                        @unknown default:
                            videoPlaceholder
                        }
                    }
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Open externally button
                    Button(action: onOpenInBrowser) {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.6))
                                    .frame(width: 64, height: 64)

                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                            }
                            Text("Open Video")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .buttonStyle(.plain)
                }
            } else {
                videoPlaceholder
            }
        }
    }

    private var videoPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.white.opacity(0.05))
            .frame(height: 240)
            .overlay(
                VStack(spacing: 12) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(accentColor.opacity(0.5))

                    Text("Video content")
                        .font(.system(size: 13))
                        .foregroundColor(Color.white.opacity(0.4))
                }
            )
    }

    /// Extract YouTube video ID from various URL formats
    private func extractYouTubeVideoId(from urlString: String?) -> String? {
        guard let urlString = urlString else { return nil }

        // Pattern 1: youtube.com/watch?v=VIDEO_ID
        if let range = urlString.range(of: "v=") {
            let startIndex = range.upperBound
            let endIndex = urlString[startIndex...].firstIndex(of: "&") ?? urlString.endIndex
            return String(urlString[startIndex..<endIndex])
        }

        // Pattern 2: youtu.be/VIDEO_ID
        if urlString.contains("youtu.be/") {
            let components = urlString.components(separatedBy: "youtu.be/")
            if components.count > 1 {
                let idPart = components[1]
                let endIndex = idPart.firstIndex(of: "?") ?? idPart.firstIndex(of: "&") ?? idPart.endIndex
                return String(idPart[..<endIndex])
            }
        }

        // Pattern 3: youtube.com/embed/VIDEO_ID
        if let range = urlString.range(of: "/embed/") {
            let startIndex = range.upperBound
            let endIndex = urlString[startIndex...].firstIndex(of: "?") ?? urlString.endIndex
            return String(urlString[startIndex..<endIndex])
        }

        return nil
    }

    // MARK: - Article Content

    private var articleContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Thumbnail if available
            if let thumbnailURL = source?.thumbnailURL, let url = URL(string: thumbnailURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    default:
                        EmptyView()
                    }
                }
            }

            // Article body preview
            if let body = atom.body, !body.isEmpty {
                Text(body)
                    .font(.system(size: 14))
                    .foregroundColor(Color.white.opacity(0.7))
                    .lineLimit(10)
            }
        }
    }

    // MARK: - PDF Content

    private var pdfContent: some View {
        VStack(spacing: 12) {
            // PDF preview placeholder
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .frame(height: 300)
                .overlay(
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 48))
                            .foregroundColor(accentColor.opacity(0.5))

                        Text("PDF Document")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.6))

                        Button("Open PDF") {
                            onOpenInBrowser()
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(accentColor.opacity(0.2), in: Capsule())
                        .foregroundColor(accentColor)
                    }
                )
        }
    }

    // MARK: - Social Content

    private var socialContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Social post card
            HStack(alignment: .top, spacing: 12) {
                // Author avatar placeholder
                Circle()
                    .fill(accentColor.opacity(0.2))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(accentColor)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    // Author
                    if let author = source?.author {
                        Text(author)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    // Platform badge
                    if let platform = source?.platform {
                        Text("@\(platform.lowercased())")
                            .font(.system(size: 12))
                            .foregroundColor(Color.white.opacity(0.5))
                    }
                }

                Spacer()
            }

            // Post content
            if let body = atom.body, !body.isEmpty {
                Text(body)
                    .font(.system(size: 15))
                    .foregroundColor(Color.white.opacity(0.85))
                    .lineLimit(8)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Generic Content

    private var genericContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // URL display
            if let url = source?.url {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.system(size: 12))
                        .foregroundColor(accentColor)

                    Text(url)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }

            // Body preview
            if let body = atom.body, !body.isEmpty {
                Text(body)
                    .font(.system(size: 14))
                    .foregroundColor(Color.white.opacity(0.7))
                    .lineLimit(6)
            }

            // Open in browser prompt
            Button("Open in Browser") {
                onOpenInBrowser()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(accentColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
            .foregroundColor(accentColor)
        }
    }

    // MARK: - Timeline Section

    private var timelineSection: some View {
        VStack(spacing: 8) {
            // Progress bar with markers
            TimelineProgressView(
                currentTime: currentTimestamp,
                duration: duration,
                markers: timelineMarkers,
                onSeek: onSeek,
                onMarkerTap: onMarkerTap
            )

            // Time display
            HStack {
                Text(formatTimestamp(currentTimestamp))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.5))

                Spacer()

                Text(formatTimestamp(duration))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.2))
    }

    // MARK: - Helpers

    private var accentColor: Color {
        CosmoColors.blockResearch
    }

    private var panelBackground: some View {
        ZStack {
            Color(hex: "#1A1A25")

            LinearGradient(
                colors: [
                    accentColor.opacity(0.03),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func formatTimestamp(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Timeline Progress View

/// Interactive timeline with annotation markers
struct TimelineProgressView: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let markers: [TimelineMarker]
    let onSeek: (TimeInterval) -> Void
    let onMarkerTap: (TimelineMarker) -> Void

    @State private var isDragging = false
    @State private var dragProgress: CGFloat = 0

    private var progress: CGFloat {
        guard duration > 0 else { return 0 }
        return isDragging ? dragProgress : CGFloat(currentTime / duration)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track background
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 4)

                // Progress fill
                RoundedRectangle(cornerRadius: 2)
                    .fill(CosmoColors.blockResearch)
                    .frame(width: geometry.size.width * progress, height: 4)

                // Annotation markers
                ForEach(markers) { marker in
                    TimelineMarkerView(marker: marker)
                        .position(
                            x: geometry.size.width * marker.position(totalDuration: duration),
                            y: 2
                        )
                        .onTapGesture {
                            onMarkerTap(marker)
                        }
                }

                // Playhead
                Circle()
                    .fill(Color.white)
                    .frame(width: isDragging ? 14 : 10, height: isDragging ? 14 : 10)
                    .shadow(color: Color.black.opacity(0.3), radius: 4)
                    .position(
                        x: geometry.size.width * progress,
                        y: 2
                    )
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        dragProgress = min(max(value.location.x / geometry.size.width, 0), 1)
                    }
                    .onEnded { _ in
                        isDragging = false
                        let newTime = duration * Double(dragProgress)
                        onSeek(newTime)
                    }
            )
        }
        .frame(height: 20)
    }
}

// MARK: - Timeline Marker View

/// Individual marker on the timeline
struct TimelineMarkerView: View {
    let marker: TimelineMarker

    @State private var isHovered = false

    var body: some View {
        Circle()
            .fill(marker.type.color)
            .frame(width: isHovered ? 10 : 6, height: isHovered ? 10 : 6)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: marker.type.color.opacity(0.5), radius: isHovered ? 6 : 2)
            .onHover { hovering in
                withAnimation(ProMotionSprings.hover) {
                    isHovered = hovering
                }
            }
    }
}

// MARK: - YouTube Focus Mode Player

/// YouTube player with bidirectional communication for Focus Mode
/// Supports playback control, seeking, and time synchronization
struct YouTubeFocusModePlayer: NSViewRepresentable {
    let videoId: String
    @Binding var currentTime: TimeInterval
    let onDurationLoaded: (TimeInterval) -> Void
    let onSeek: (TimeInterval) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []

        // Set up JavaScript message handling
        let contentController = config.userContentController
        contentController.add(context.coordinator, name: "playerReady")
        contentController.add(context.coordinator, name: "timeUpdate")
        contentController.add(context.coordinator, name: "durationLoaded")
        contentController.add(context.coordinator, name: "stateChange")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Only load once
        guard !context.coordinator.hasLoaded else { return }
        context.coordinator.hasLoaded = true

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                html, body {
                    width: 100%;
                    height: 100%;
                    background: #000;
                    overflow: hidden;
                }
                #player {
                    position: absolute;
                    top: 0;
                    left: 0;
                    width: 100%;
                    height: 100%;
                }
            </style>
        </head>
        <body>
            <div id="player"></div>

            <script>
                var tag = document.createElement('script');
                tag.src = "https://www.youtube.com/iframe_api";
                var firstScriptTag = document.getElementsByTagName('script')[0];
                firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);

                var player;
                var timeUpdateInterval;

                function onYouTubeIframeAPIReady() {
                    player = new YT.Player('player', {
                        videoId: '\(videoId)',
                        playerVars: {
                            'playsinline': 1,
                            'rel': 0,
                            'modestbranding': 1,
                            'enablejsapi': 1,
                            'origin': 'https://cosmoos.local'
                        },
                        events: {
                            'onReady': onPlayerReady,
                            'onStateChange': onPlayerStateChange
                        }
                    });
                }

                function onPlayerReady(event) {
                    var duration = player.getDuration();
                    window.webkit.messageHandlers.playerReady.postMessage({});
                    window.webkit.messageHandlers.durationLoaded.postMessage({ duration: duration });

                    // Start time update interval
                    timeUpdateInterval = setInterval(function() {
                        if (player && player.getCurrentTime) {
                            var currentTime = player.getCurrentTime();
                            window.webkit.messageHandlers.timeUpdate.postMessage({ time: currentTime });
                        }
                    }, 250);
                }

                function onPlayerStateChange(event) {
                    window.webkit.messageHandlers.stateChange.postMessage({ state: event.data });
                }

                function seekTo(time) {
                    if (player && player.seekTo) {
                        player.seekTo(time, true);
                    }
                }

                function playVideo() {
                    if (player && player.playVideo) {
                        player.playVideo();
                    }
                }

                function pauseVideo() {
                    if (player && player.pauseVideo) {
                        player.pauseVideo();
                    }
                }
            </script>
        </body>
        </html>
        """
        nsView.loadHTMLString(html, baseURL: URL(string: "https://cosmoos.local"))
    }

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: YouTubeFocusModePlayer
        var hasLoaded = false
        var webView: WKWebView?

        init(parent: YouTubeFocusModePlayer) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }

            switch message.name {
            case "playerReady":
                print("📹 YouTube player ready")

            case "durationLoaded":
                if let duration = body["duration"] as? Double {
                    DispatchQueue.main.async {
                        self.parent.onDurationLoaded(duration)
                    }
                }

            case "timeUpdate":
                if let time = body["time"] as? Double {
                    DispatchQueue.main.async {
                        self.parent.currentTime = time
                    }
                }

            case "stateChange":
                if let state = body["state"] as? Int {
                    // YT.PlayerState: -1 (unstarted), 0 (ended), 1 (playing), 2 (paused), 3 (buffering), 5 (cued)
                    print("📹 Player state: \(state)")
                }

            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            self.webView = webView
        }

        func seek(to time: TimeInterval) {
            webView?.evaluateJavaScript("seekTo(\(time))") { _, error in
                if let error = error {
                    print("⚠️ Seek error: \(error)")
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ResearchCoreView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            CosmoColors.thinkspaceVoid
                .ignoresSafeArea()

            ResearchCoreView(
                atom: Atom.new(
                    type: .research,
                    title: "Dan Koe - How to Reinvent Your Life in 6-12 Months",
                    body: "Identity is not fixed — it's a story you tell yourself. Real transformation comes from subtraction, not addition. Remove what doesn't serve your vision."
                ),
                currentTimestamp: .constant(810), // 13:30
                timelineMarkers: [
                    TimelineMarker(id: UUID(), timestamp: 120, type: .note, annotationID: UUID()),
                    TimelineMarker(id: UUID(), timestamp: 480, type: .question, annotationID: UUID()),
                    TimelineMarker(id: UUID(), timestamp: 1200, type: .insight, annotationID: UUID()),
                    TimelineMarker(id: UUID(), timestamp: 2100, type: .note, annotationID: UUID())
                ],
                duration: 2538, // 42:18
                contentType: .video,
                source: ResearchSource(
                    url: "https://youtube.com/watch?v=example",
                    platform: "YouTube",
                    author: "Dan Koe",
                    channelName: "Dan Koe",
                    publishedAt: Date(),
                    duration: 2538,
                    thumbnailURL: nil
                ),
                onSeek: { time in print("Seek to: \(time)") },
                onMarkerTap: { marker in print("Marker tapped: \(marker.type)") },
                onCopyURL: { print("Copy URL") },
                onOpenInBrowser: { print("Open in browser") }
            )
            .frame(width: 600)
            .padding(40)
        }
    }
}
#endif
