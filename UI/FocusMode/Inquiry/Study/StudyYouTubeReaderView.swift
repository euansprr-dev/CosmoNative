// CosmoOS/UI/FocusMode/Inquiry/Study/StudyYouTubeReaderView.swift
// The YouTube study reader: just the video and its transcript — no
// recommendations, no comments, no feed. The Podcasts-app register: player
// pinned on top, the transcript flowing beneath as one selectable text with
// quiet timestamp links (click to seek). Player, transcript, and the floating
// thinking bar share ONE column (StudyMetrics.readerMeasure) so their edges
// align as a single manuscript. Any selection feeds the same capture
// mini-menu as every reader, and captures carry a timestamped citation back
// to the exact moment in the video.

import SwiftUI
import WebKit

@MainActor
struct StudyYouTubeReaderView: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    let tab: SourceTab
    @Binding var lastSelectedText: String
    @Binding var selectionTimestamp: Int?

    @State private var paragraphs: [YouTubeTranscriptParagraph] = []
    @State private var loadState: TranscriptLoadState = .loading
    @State private var searchQuery: String = ""
    @State private var seekScript: String?
    @State private var skeletonPulses = false
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var videoID: String? {
        tab.url.flatMap { YouTubeTranscriptService.videoID(from: $0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            playerSection
            Divider().overlay(DS.borderSubtle)
            transcriptSection
        }
        .background(DS.bg)
        // The thinking bar floats over the reader's foot — the transcript
        // dissolves into the page there so the bar lands on a calm zone,
        // never on live sentences.
        .overlay(alignment: .bottom) { bottomLandingFade }
        .background { findShortcut }
        .task(id: videoID) { await loadTranscript() }
    }

    /// One shared column: the player, the transcript, and the thinking bar
    /// all sit on `StudyMetrics.readerMeasure`, edges aligned.
    private func readerColumn<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: StudyMetrics.readerMeasure)
            .padding(.horizontal, DS.space24)
            .frame(maxWidth: .infinity)
    }

    private var bottomLandingFade: some View {
        LinearGradient(
            colors: [DS.bg.opacity(0), DS.bg.opacity(0.85), DS.bg],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 84)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var findShortcut: some View {
        Button("") { searchFocused = true }
            .keyboardShortcut("f", modifiers: [.command])
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }

    // MARK: - Player (the nocookie embed — video only)

    @ViewBuilder
    private var playerSection: some View {
        if let videoID {
            readerColumn {
                StudyYouTubePlayer(videoID: videoID, pendingSeekScript: $seekScript)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(.top, DS.space16)
            .padding(.bottom, DS.space12)
        } else {
            StudyTranscriptNotice(text: "Couldn't read a video id from this link.")
        }
    }

    // MARK: - Transcript

    @ViewBuilder
    private var transcriptSection: some View {
        switch loadState {
        case .loading:
            readerColumn { transcriptSkeleton }
                .frame(maxHeight: .infinity, alignment: .top)
        case .unavailable(let message):
            StudyTranscriptNotice(text: "\(message) Selections from the transcript aren't available, but the video plays and your thoughts still route from the bar below.")
        case .ready:
            VStack(spacing: 0) {
                readerColumn { transcriptHeader }
                readerColumn {
                    StudyTranscriptTextView(
                        paragraphs: visibleParagraphs,
                        lastSelectedText: $lastSelectedText,
                        selectionTimestamp: $selectionTimestamp,
                        onSeek: seek
                    )
                }
            }
        }
    }

    private var transcriptHeader: some View {
        HStack(spacing: DS.space8) {
            Text("TRANSCRIPT")
                .dsSmallCapsLabel()
            Text("\(paragraphs.count) passages")
                .font(DS.caption2)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(DS.textMuted)
            Spacer()
            searchField
        }
        .padding(.vertical, DS.space8)
    }

    /// Transcript-shaped placeholder: stamp + line bars in the reading
    /// column, with a gentle pulse gated on Reduce Motion.
    private var transcriptSkeleton: some View {
        VStack(alignment: .leading, spacing: DS.space20) {
            ForEach(0..<4, id: \.self) { block in
                VStack(alignment: .leading, spacing: DS.space8) {
                    Capsule().fill(DS.glassSectionFill).frame(width: 38, height: 8)
                    Capsule().fill(DS.glassSectionFill).frame(maxWidth: .infinity).frame(height: 10)
                    Capsule().fill(DS.glassSectionFill).frame(maxWidth: .infinity).frame(height: 10)
                    Capsule().fill(DS.glassSectionFill)
                        .frame(maxWidth: ([420, 520, 360, 470] as [CGFloat])[block], alignment: .leading)
                        .frame(height: 10)
                }
            }
        }
        .padding(.top, DS.space20)
        .opacity(skeletonPulses ? 0.55 : 1)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
            value: skeletonPulses
        )
        .onAppear { skeletonPulses = true }
        .accessibilityLabel("Loading transcript")
    }

    private var searchField: some View {
        HStack(spacing: DS.space6) {
            Image(systemName: "magnifyingglass")
                .font(DS.caption)
                .foregroundStyle(searchFocused ? DS.accent : DS.textMuted)
                .accessibilityHidden(true)
            TextField("Find in transcript", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(DS.footnote)
                .focused($searchFocused)
                .onExitCommand {
                    searchQuery = ""
                    searchFocused = false
                }
                .frame(width: 170)
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DS.caption)
                        .foregroundStyle(DS.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear transcript search")
            }
        }
        .padding(.horizontal, DS.space8)
        .padding(.vertical, 4)
        .background(DS.glassInputFill.opacity(searchFocused ? 1 : 0.6), in: Capsule())
        .overlay(Capsule().stroke(searchFocused ? DS.focusRing : DS.borderSubtle, lineWidth: 1))
        .animation(ProMotionSprings.hover, value: searchFocused)
    }

    private var visibleParagraphs: [YouTubeTranscriptParagraph] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return paragraphs }
        return paragraphs.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    // MARK: - Actions

    private func seek(to seconds: Double) {
        seekScript = "cosmoSeek(\(Int(seconds)));"
    }

    private func loadTranscript() async {
        guard let videoID else {
            loadState = .unavailable("Couldn't read a video id from this link.")
            return
        }
        loadState = .loading
        do {
            let segments = try await YouTubeTranscriptService.shared.transcript(forVideoID: videoID)
            paragraphs = YouTubeTranscriptService.paragraphs(from: segments)
            loadState = .ready
        } catch {
            loadState = .unavailable((error as? YouTubeTranscriptError)?.errorDescription ?? "The transcript couldn't be loaded.")
        }
    }

    private enum TranscriptLoadState: Equatable {
        case loading
        case ready
        case unavailable(String)
    }
}

// MARK: - Teaching notice

private struct StudyTranscriptNotice: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DS.dateSerif)
            .foregroundStyle(DS.textMuted)
            .lineSpacing(4)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, DS.space24)
            .padding(.vertical, DS.space16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Player (WKWebView hosting the IFrame API — video only, seekable)

private struct StudyYouTubePlayer: NSViewRepresentable {
    let videoID: String
    @Binding var pendingSeekScript: String?

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(Self.playerHTML(videoID: videoID), baseURL: URL(string: "https://www.youtube-nocookie.com"))
        context.coordinator.loadedVideoID = videoID
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedVideoID != videoID {
            webView.loadHTMLString(Self.playerHTML(videoID: videoID), baseURL: URL(string: "https://www.youtube-nocookie.com"))
            context.coordinator.loadedVideoID = videoID
        }
        if let script = pendingSeekScript {
            webView.evaluateJavaScript(script)
            Task { @MainActor in pendingSeekScript = nil }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var loadedVideoID: String?
    }

    /// A bare IFrame-API player: the video, nothing else. `cosmoSeek(s)`
    /// jumps playback — the transcript's timestamp links call it.
    private static func playerHTML(videoID: String) -> String {
        """
        <!doctype html><html><head><meta name=viewport content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;padding:0;background:transparent;height:100%;overflow:hidden}#player{width:100%;height:100%}</style>
        </head><body>
        <div id="player"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
        var player;
        function onYouTubeIframeAPIReady() {
            player = new YT.Player('player', {
                videoId: '\(videoID)',
                host: 'https://www.youtube-nocookie.com',
                playerVars: { 'playsinline': 1, 'rel': 0, 'modestbranding': 1 }
            });
        }
        function cosmoSeek(seconds) {
            if (player && player.seekTo) {
                player.seekTo(seconds, true);
                if (player.playVideo) { player.playVideo(); }
            }
        }
        </script>
        </body></html>
        """
    }
}

// MARK: - Transcript text (ONE selectable text view — selection crosses passages)

/// The whole transcript is a single NSTextView (the one-text-view law), so
/// highlighting works across any span. Timestamps render as quiet links that
/// seek the player; the selection's own timestamp rides up alongside the
/// selected text so captures can cite the exact moment.
private struct StudyTranscriptTextView: NSViewRepresentable {
    let paragraphs: [YouTubeTranscriptParagraph]
    @Binding var lastSelectedText: String
    @Binding var selectionTimestamp: Int?
    let onSeek: (Double) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.drawsBackground = false
        textView.delegate = context.coordinator
        textView.linkTextAttributes = [
            .foregroundColor: NSColor(DS.textMuted),
            .cursor: NSCursor.pointingHand
        ]
        textView.textContainerInset = NSSize(width: 0, height: 12)
        textView.textContainer?.widthTracksTextView = true

        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        // Clearance for the floating thinking bar: the last passage scrolls
        // up into readable space instead of ending beneath the instrument.
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: StudyMetrics.panelBottomInset, right: 0)

        context.coordinator.apply(paragraphs: paragraphs, to: textView)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scroll.documentView as? NSTextView else { return }
        if context.coordinator.renderedParagraphIDs != paragraphs.map(\.id) {
            context.coordinator.apply(paragraphs: paragraphs, to: textView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: StudyTranscriptTextView
        var renderedParagraphIDs: [Int] = []
        /// (character offset of paragraph start, paragraph start seconds)
        private var timestampIndex: [(location: Int, start: Double)] = []

        init(parent: StudyTranscriptTextView) {
            self.parent = parent
        }

        func apply(paragraphs: [YouTubeTranscriptParagraph], to textView: NSTextView) {
            let result = NSMutableAttributedString()
            var index: [(Int, Double)] = []

            let bodyStyle = NSMutableParagraphStyle()
            bodyStyle.lineSpacing = 5
            bodyStyle.paragraphSpacing = 14

            let bodyFont = NSFont(name: "New York", size: 15) ?? NSFont.systemFont(ofSize: 15)
            let stampFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

            for paragraph in paragraphs {
                index.append((result.length, paragraph.start))
                let stamp = NSAttributedString(
                    string: paragraph.timestampLabel + "  ",
                    attributes: [
                        .font: stampFont,
                        .link: URL(string: "cosmo-seek://\(Int(paragraph.start))") as Any,
                        .paragraphStyle: bodyStyle
                    ]
                )
                result.append(stamp)
                let body = NSAttributedString(
                    string: paragraph.text + "\n",
                    attributes: [
                        .font: bodyFont,
                        .foregroundColor: NSColor(DS.text).withAlphaComponent(0.88),
                        .paragraphStyle: bodyStyle
                    ]
                )
                result.append(body)
            }

            textView.textStorage?.setAttributedString(result)
            timestampIndex = index
            renderedParagraphIDs = paragraphs.map(\.id)
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL, url.scheme == "cosmo-seek",
                  let seconds = Double(url.host ?? "") else { return false }
            parent.onSeek(seconds)
            return true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            guard range.length > 0 else { return }
            let nsString = textView.string as NSString
            guard range.location + range.length <= nsString.length else { return }
            let selected = nsString.substring(with: range)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !selected.isEmpty else { return }
            // Nearest paragraph start at or before the selection = the moment
            // this passage begins in the video.
            let start = timestampIndex.last(where: { $0.location <= range.location })?.start
            let parent = self.parent
            Task { @MainActor in
                parent.lastSelectedText = selected
                parent.selectionTimestamp = start.map { Int($0) }
            }
        }
    }
}
