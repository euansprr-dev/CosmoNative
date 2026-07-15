// CosmoOS/UI/FocusMode/Inquiry/Study/StudyYouTubeReaderView.swift
// The YouTube study reader: just the video and its transcript — no
// recommendations, no comments, no feed. The Podcasts-app register: player
// pinned on top, the transcript flowing beneath as one selectable text with
// quiet timestamp links (click to seek). Player, transcript, and the floating
// thinking bar share ONE column (StudyMetrics.readerMeasure) so their edges
// align as a single manuscript. Any selection raises the floating Capture
// pill shared by every reader, and captures carry a timestamped citation
// back to the exact moment in the video.

import SwiftUI
import WebKit

@MainActor
struct StudyYouTubeReaderView: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    let tab: SourceTab
    @Binding var lastSelectedText: String
    @Binding var selectionTimestamp: Int?
    /// Selection rect in SwiftUI `.global` space — anchors the reader's
    /// floating capture pill to the highlighted passage.
    var selectionAnchor: Binding<CGRect?>? = nil

    @State private var paragraphs: [YouTubeTranscriptParagraph] = []
    @State private var loadState: TranscriptLoadState = .loading
    @State private var searchQuery: String = ""
    @State private var seekScript: String?
    /// The player's live playback position (whole seconds), reported back over
    /// a WK message handler. Drives the "now-speaking" transcript highlight and
    /// the page-turning auto-scroll.
    @State private var currentTime: Double = 0
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
                StudyYouTubePlayer(videoID: videoID, pendingSeekScript: $seekScript, currentTime: $currentTime)
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
                        currentTime: currentTime,
                        reduceMotion: reduceMotion,
                        lastSelectedText: $lastSelectedText,
                        selectionTimestamp: $selectionTimestamp,
                        selectionAnchor: selectionAnchor,
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
    /// Live playback position in seconds — the player ticks it back so the
    /// transcript can follow along.
    @Binding var currentTime: Double

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // A weak proxy keeps the content controller from strongly retaining the
        // coordinator in a cycle; it forwards each time tick on the main thread.
        let proxy = TimeScriptProxy()
        proxy.coordinator = context.coordinator
        context.coordinator.timeProxy = proxy
        configuration.userContentController.add(proxy, name: "cosmoTime")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(Self.playerHTML(videoID: videoID), baseURL: URL(string: "https://www.youtube-nocookie.com"))
        context.coordinator.loadedVideoID = videoID
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.currentTimeBinding = $currentTime
        if context.coordinator.loadedVideoID != videoID {
            webView.loadHTMLString(Self.playerHTML(videoID: videoID), baseURL: URL(string: "https://www.youtube-nocookie.com"))
            context.coordinator.loadedVideoID = videoID
        }
        if let script = pendingSeekScript {
            webView.evaluateJavaScript(script)
            Task { @MainActor in pendingSeekScript = nil }
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "cosmoTime")
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        var loadedVideoID: String?
        var currentTimeBinding: Binding<Double>?
        var timeProxy: TimeScriptProxy?

        func report(time seconds: Double) {
            // The message handler already lands on the main thread; write straight
            // through, skipping no-op repeats of the same whole second.
            guard let binding = currentTimeBinding, binding.wrappedValue != seconds else { return }
            binding.wrappedValue = seconds
        }
    }

    /// Weak forwarder for the `cosmoTime` script messages — avoids the retain
    /// cycle `WKUserContentController → handler → coordinator`.
    final class TimeScriptProxy: NSObject, WKScriptMessageHandler {
        weak var coordinator: Coordinator?
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let seconds = (message.body as? NSNumber)?.doubleValue else { return }
            MainActor.assumeIsolated { coordinator?.report(time: seconds) }
        }
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
        // Tick the current second back to Swift — only on change, so the
        // transcript highlight and page-turn fire at most once per second.
        var cosmoLastSecond = -1;
        setInterval(function() {
            if (player && player.getCurrentTime) {
                var s = Math.floor(player.getCurrentTime());
                if (s !== cosmoLastSecond) {
                    cosmoLastSecond = s;
                    if (window.webkit && window.webkit.messageHandlers.cosmoTime) {
                        window.webkit.messageHandlers.cosmoTime.postMessage(s);
                    }
                }
            }
        }, 400);
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
    /// The player's live position — the paragraph whose window contains it is
    /// the one being spoken, and it wears the lane wash.
    var currentTime: Double = 0
    var reduceMotion: Bool = false
    @Binding var lastSelectedText: String
    @Binding var selectionTimestamp: Int?
    var selectionAnchor: Binding<CGRect?>? = nil
    let onSeek: (Double) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let textView = TranscriptWashTextView()
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
        guard let textView = scroll.documentView as? TranscriptWashTextView else { return }
        if context.coordinator.renderedParagraphIDs != paragraphs.map(\.id) {
            context.coordinator.apply(paragraphs: paragraphs, to: textView)
        }
        context.coordinator.followPlayback(time: currentTime, textView: textView, scroll: scroll, reduceMotion: reduceMotion)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: StudyTranscriptTextView
        var renderedParagraphIDs: [Int] = []
        /// (character offset of paragraph start, paragraph start seconds)
        private var timestampIndex: [(location: Int, start: Double)] = []
        /// Per-paragraph spans for the now-speaking highlight: `full` covers the
        /// stamp + body (the wash range), `body` is just the sentence text (the
        /// run we brighten). `start` is the moment the paragraph begins.
        private var paragraphSpans: [(full: NSRange, body: NSRange, start: Double)] = []
        private var activeIndex: Int?

        // The transcript's resting register vs. the spoken paragraph.
        private let restingBody = NSColor(DS.text).withAlphaComponent(0.88)
        private let spokenBody = NSColor(DS.text)

        init(parent: StudyTranscriptTextView) {
            self.parent = parent
        }

        func apply(paragraphs: [YouTubeTranscriptParagraph], to textView: TranscriptWashTextView) {
            let result = NSMutableAttributedString()
            var index: [(Int, Double)] = []
            var spans: [(full: NSRange, body: NSRange, start: Double)] = []

            let bodyStyle = NSMutableParagraphStyle()
            bodyStyle.lineSpacing = 5
            bodyStyle.paragraphSpacing = 14

            let bodyFont = NSFont(name: "New York", size: 15) ?? NSFont.systemFont(ofSize: 15)
            let stampFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

            for paragraph in paragraphs {
                let paragraphStart = result.length
                index.append((paragraphStart, paragraph.start))
                let stamp = NSAttributedString(
                    string: paragraph.timestampLabel + "  ",
                    attributes: [
                        .font: stampFont,
                        .link: URL(string: "cosmo-seek://\(Int(paragraph.start))") as Any,
                        .paragraphStyle: bodyStyle
                    ]
                )
                result.append(stamp)
                let bodyStart = result.length
                let bodyLength = (paragraph.text as NSString).length
                let body = NSAttributedString(
                    string: paragraph.text + "\n",
                    attributes: [
                        .font: bodyFont,
                        .foregroundColor: restingBody,
                        .paragraphStyle: bodyStyle
                    ]
                )
                result.append(body)
                // Wash range excludes the trailing newline so it doesn't bleed
                // into the gap before the next paragraph.
                spans.append((
                    full: NSRange(location: paragraphStart, length: bodyStart + bodyLength - paragraphStart),
                    body: NSRange(location: bodyStart, length: bodyLength),
                    start: paragraph.start
                ))
            }

            textView.textStorage?.setAttributedString(result)
            timestampIndex = index
            paragraphSpans = spans
            renderedParagraphIDs = paragraphs.map(\.id)
            // Fresh text: drop the old highlight so followPlayback re-lands it.
            activeIndex = nil
            textView.activeWashRange = nil
        }

        // MARK: - Follow the spoken paragraph

        /// Move the lane wash to whichever paragraph owns `time`, brighten its
        /// text, and — only when that paragraph has slipped past the fold —
        /// turn the page so the next stretch comes into view.
        func followPlayback(time: Double, textView: TranscriptWashTextView, scroll: NSScrollView, reduceMotion: Bool) {
            guard !paragraphSpans.isEmpty else { return }
            // The spoken paragraph is the last one whose start is at or before now.
            var target = 0
            for (i, span) in paragraphSpans.enumerated() {
                if span.start <= time { target = i } else { break }
            }
            guard target != activeIndex else { return }
            let previous = activeIndex
            activeIndex = target

            if let previous { setBody(previous, color: restingBody, in: textView) }
            setBody(target, color: spokenBody, in: textView)
            textView.activeWashRange = paragraphSpans[target].full
            textView.washInk = NSColor(DS.accent)

            // Don't yank the page on the first landing (initial load / seek back
            // to the top) — only turn once playback has carried us forward.
            if previous != nil {
                pageToActiveIfNeeded(index: target, textView: textView, scroll: scroll, reduceMotion: reduceMotion)
            }
        }

        private func setBody(_ index: Int, color: NSColor, in textView: TranscriptWashTextView) {
            guard index >= 0, index < paragraphSpans.count, let storage = textView.textStorage else { return }
            let range = paragraphSpans[index].body
            guard range.location + range.length <= storage.length else { return }
            storage.addAttribute(.foregroundColor, value: color, range: range)
        }

        /// Page-turn scroll: if the spoken paragraph is fully in the readable
        /// band we leave the page still; once it drops below the fold (or the
        /// user seeked back above it) we glide it up near the top, revealing the
        /// next part in one smooth move rather than a continuous crawl.
        private func pageToActiveIfNeeded(index: Int, textView: TranscriptWashTextView, scroll: NSScrollView, reduceMotion: Bool) {
            // Never fight a live selection — the reader is citing a passage.
            guard textView.selectedRange().length == 0 else { return }
            guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: paragraphSpans[index].full, actualCharacterRange: nil)
            let origin = textView.textContainerOrigin
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
                .offsetBy(dx: origin.x, dy: origin.y)

            let visible = scroll.documentVisibleRect
            // The floating thinking bar covers the foot, so the readable band
            // ends above it.
            let readableBottom = visible.maxY - StudyMetrics.panelBottomInset
            if rect.maxY <= readableBottom && rect.minY >= visible.minY { return }

            let topPadding: CGFloat = 28
            let maxOffset = max(0, textView.bounds.height - visible.height)
            let targetY = min(max(0, rect.minY - topPadding), maxOffset)
            guard abs(targetY - visible.minY) > 1 else { return }

            let clip = scroll.contentView
            let destination = NSPoint(x: visible.minX, y: targetY)
            if reduceMotion {
                clip.setBoundsOrigin(destination)
                scroll.reflectScrolledClipView(clip)
            } else {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.6
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    clip.animator().setBoundsOrigin(destination)
                } completionHandler: {
                    scroll.reflectScrolledClipView(clip)
                }
            }
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
            let parent = self.parent
            guard range.length > 0 else {
                // Collapsed selection dismisses the floating capture pill.
                Task { @MainActor in
                    parent.lastSelectedText = ""
                    parent.selectionTimestamp = nil
                    parent.selectionAnchor?.wrappedValue = nil
                }
                return
            }
            let nsString = textView.string as NSString
            guard range.location + range.length <= nsString.length else { return }
            let selected = nsString.substring(with: range)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !selected.isEmpty else { return }
            // Nearest paragraph start at or before the selection = the moment
            // this passage begins in the video.
            let start = timestampIndex.last(where: { $0.location <= range.location })?.start
            let anchor = SelectionAnchorSpace.globalRect(
                fromScreen: textView.firstRect(forCharacterRange: range, actualRange: nil),
                for: textView
            )
            Task { @MainActor in
                parent.lastSelectedText = selected
                parent.selectionTimestamp = start.map { Int($0) }
                parent.selectionAnchor?.wrappedValue = anchor
            }
        }
    }
}

// MARK: - The transcript's own washing text view (now-speaking highlight)

/// A TextKit-1 NSTextView that paints the Capture-Anywhere lane wash behind the
/// paragraph currently being spoken — the same soft rounded ink-at-0.10 register
/// as `WashTextView`, translated from a one-line token to a whole passage. The
/// wash is drawn under the glyphs (before `super.draw`), per line fragment, with
/// enough vertical bleed that a multi-line paragraph reads as one continuous
/// rounded band instead of stacked pills.
final class TranscriptWashTextView: NSTextView {
    /// Character range (stamp + body) of the spoken paragraph, or nil when
    /// nothing is playing.
    var activeWashRange: NSRange? {
        didSet { if activeWashRange != oldValue { needsDisplay = true } }
    }
    var washInk: NSColor = NSColor(DS.accent)

    // Same whisper of a wash as the capture field: expand each line rect a
    // touch, round it, fill at a tenth. The taller vertical bleed lets adjacent
    // line rects overlap into one shape.
    private static let washInset = CGSize(width: -4, height: -3.5)
    private static let washCornerRadius: CGFloat = 8
    private static let washAlpha: CGFloat = 0.10

    override func draw(_ dirtyRect: NSRect) {
        drawActiveWash()
        super.draw(dirtyRect)
    }

    private func drawActiveWash() {
        guard let range = activeWashRange, range.length > 0,
              let layoutManager, let container = textContainer else { return }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return }

        let origin = textContainerOrigin
        washInk.withAlphaComponent(Self.washAlpha).setFill()
        layoutManager.enumerateEnclosingRects(
            forGlyphRange: glyphRange,
            withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
            in: container
        ) { rect, _ in
            let washed = rect
                .offsetBy(dx: origin.x, dy: origin.y)
                .insetBy(dx: Self.washInset.width, dy: Self.washInset.height)
            NSBezierPath(
                roundedRect: washed,
                xRadius: Self.washCornerRadius,
                yRadius: Self.washCornerRadius
            ).fill()
        }
    }
}
