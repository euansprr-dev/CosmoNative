// CosmoOS/Canvas/ResearchBlockView.swift
// Green-accented Research block for Thinkspace canvas
// Clean light design matching Greenhouse aesthetic
// Features: Playable video preview, collapsible transcript & annotations dropdown

import SwiftUI

struct ResearchBlockView: View {
    let block: CanvasBlock
    let isViewportActive: Bool

    @State private var atom: Atom?
    @State private var isLoading = true
    @State private var isProcessing = false
    @State private var isPlayerActive = false
    @State private var currentTimestamp: TimeInterval = 0
    @State private var isDropdownOpen = false
    // PERF: Cached parsed metadata — computed once in loadAtom(), not on every render
    @State private var platform: String?
    @State private var author: String?
    @State private var duration: String?
    @State private var resolvedURL: String?
    @State private var contentType: String = "Research"
    @State private var isYouTubeContent: Bool = false
    @State private var videoId: String?
    @State private var resolvedThumbnailURL: String?
    @State private var loadTask: Task<Void, Never>?

    // Accent color: bronze for swipe files, green for research
    private var isSwipeFile: Bool {
        atom?.isSwipeFileAtom ?? (block.metadata["isSwipeFile"] == "true")
    }

    private var accentColor: Color {
        isSwipeFile ? DS.entitySwipe : DS.entityResearch
    }

    init(block: CanvasBlock, isViewportActive: Bool = true) {
        self.block = block
        self.isViewportActive = isViewportActive
        // Seed from block metadata for instant thumbnail rendering (before async loadAtom)
        let url = (block.metadata["url"] ?? "").lowercased()
        let isYT = url.contains("youtube") || url.contains("youtu.be")
        self._isYouTubeContent = State(initialValue: isYT)
        if isYT, let vid = Self.extractYouTubeVideoIdStatic(from: block.metadata["url"]) {
            self._videoId = State(initialValue: vid)
            self._resolvedThumbnailURL = State(initialValue: block.metadata["thumbnail"] ?? "https://img.youtube.com/vi/\(vid)/hqdefault.jpg")
        } else {
            self._resolvedThumbnailURL = State(initialValue: block.metadata["thumbnail"])
        }
    }

    // MARK: - Body

    var body: some View {
        CosmoBlockWrapper(
            block: block,
            accentColor: accentColor,
            icon: "magnifyingglass",
            title: atom?.title ?? block.title,
            onFocusMode: openFocusMode
        ) {
            researchContent
        }
        .onAppear {
            syncViewportActivity()
        }
        .onChange(of: isViewportActive) { _, _ in
            syncViewportActivity()
        }
        .onReceive(NotificationCenter.default.publisher(for: .canvasAtomProcessed)) { notification in
            guard let uuid = notification.userInfo?["atomUUID"] as? String,
                  uuid == atom?.uuid || uuid == block.entityUuid else { return }
            syncViewportActivity(forceReload: true)
        }
        .onDisappear {
            deactivateViewportContent()
        }
    }

    // MARK: - Research Content

    private var researchContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Header with metadata — gilt corner bracket from the wrapper
                // replaces the old accent identity strip.
                metadataHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 10)

                // Warm sepia rule separating header from body
                Rectangle()
                    .fill(DS.sepiaSubtle)
                    .frame(height: 0.5)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                // Video area (replaces raw body text) — wrapped with filmstrip sprockets
                HStack(alignment: .center, spacing: 8) {
                    VStack(spacing: 10) {
                        ForEach(0..<3) { _ in
                            Circle()
                                .fill(DS.inkFaded.opacity(0.35))
                                .frame(width: 3, height: 3)
                        }
                    }
                    .frame(width: 6)

                    videoArea
                }
                .padding(.horizontal, 12)

                // Dropdown toggle for Transcript & Notes
                dropdownSection
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                Spacer(minLength: 8)

                // Footer
                footerRow
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Metadata Header

    private var metadataHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Content type badge — warm gilt label matches CommandCenter section labels
            Text(isSwipeFile ? "SWIPE FILE" : contentType.uppercased())
                .font(DS.smallCaps)
                .foregroundStyle(DS.giltMuted)

            // Title
            Text((atom?.title ?? block.title).isEmpty ? "Untitled Research" : (atom?.title ?? block.title))
                .font(DS.headline)
                .foregroundStyle(DS.text)
                .lineLimit(2)

            // Metadata row
            metadataRow
        }
    }

    // MARK: - Video Area

    @ViewBuilder
    private var videoArea: some View {
        if !isViewportActive {
            CosmicShimmer(entityColor: accentColor, cornerRadius: 10)
                .frame(height: 158)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else if isLoading {
            // Shimmer loading state
            CosmicShimmer(entityColor: accentColor, cornerRadius: 10)
                .frame(height: 158)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else if isPlayerActive, let vid = videoId {
            // Active YouTube player
            YouTubeFocusModePlayer(
                videoId: vid,
                currentTime: $currentTimestamp,
                onDurationLoaded: { _ in },
                onSeek: { time in
                    currentTimestamp = time
                }
            )
            .frame(height: 158)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .transition(.opacity)
        } else if isYouTubeContent, let vid = videoId {
            // YouTube thumbnail with play button overlay
            videoThumbnailWithPlay(videoId: vid)
        } else if let urlString = resolvedThumbnailURL, let url = URL(string: urlString) {
            // Non-YouTube: thumbnail with "Open" button
            nonYouTubeThumbnail(url: url)
        } else {
            // No thumbnail available: icon placeholder
            videoIconPlaceholder
        }
    }

    /// YouTube thumbnail at 16:9 with centered play button
    private func videoThumbnailWithPlay(videoId: String) -> some View {
        let thumbURL = resolvedThumbnailURL.flatMap { URL(string: $0) }

        return Button {
            withAnimation(ProMotionSprings.snappy) {
                isPlayerActive = true
            }
        } label: {
            ZStack {
                // Thumbnail image
                if let thumbURL = thumbURL {
                    CachedAsyncImage(url: thumbURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(16/9, contentMode: .fill)
                        case .failure, .empty:
                            thumbnailPlaceholderBackground
                        }
                    }
                } else {
                    thumbnailPlaceholderBackground
                }

                // Dark scrim for contrast
                Color.black.opacity(0.25)

                // Play button overlay
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.55))
                        .frame(width: 48, height: 48)

                    Image(systemName: "play.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .offset(x: 2) // Optical center
                }
            }
            .frame(height: 158)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    /// Non-YouTube content: show thumbnail with an "Open" button
    private func nonYouTubeThumbnail(url: URL) -> some View {
        ZStack {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                case .failure, .empty:
                    thumbnailPlaceholderBackground
                }
            }

            Color.black.opacity(0.3)

            // Open externally button
            Button {
                if let urlString = resolvedURL, let openURL = URL(string: urlString) {
                    NSWorkspace.shared.open(openURL)
                }
            } label: {
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.55))
                            .frame(width: 44, height: 44)

                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                    }
                    Text("Open")
                        .font(DS.caption)
                        .foregroundStyle(DS.text)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(height: 158)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// Icon placeholder when no thumbnail is available
    private var videoIconPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(accentColor.opacity(0.08))

            VStack(spacing: 8) {
                Image(systemName: contentTypeIcon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(accentColor.opacity(0.6))

                Text(contentType)
                    .font(DS.footnote)
                    .foregroundStyle(DS.textMuted)
            }
        }
        .frame(height: 158)
    }

    /// Simple dark gradient placeholder behind thumbnail area
    private var thumbnailPlaceholderBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [accentColor.opacity(0.12), DS.surfaceElevated],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: contentTypeIcon)
                .font(.system(size: 28))
                .foregroundStyle(accentColor.opacity(0.4))
        }
    }

    // MARK: - Dropdown Section

    private var dropdownSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Toggle button
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    isDropdownOpen.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isDropdownOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.gilt)

                    Text("TRANSCRIPT · NOTES")
                        .font(DS.smallCaps)
                        .foregroundStyle(DS.giltMuted)

                    Spacer()

                    if isProcessing && !isDropdownOpen {
                        HStack(spacing: 3) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("Processing…")
                                .font(.system(size: 9))
                                .foregroundStyle(DS.textMuted)
                        }
                    }
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Dropdown content
            if isDropdownOpen && isViewportActive {
                if isProcessing && (atom?.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(spacing: 6) {
                        CosmicShimmer(entityColor: accentColor, cornerRadius: 4)
                            .frame(height: 16)
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("AI is processing…")
                                .font(.system(size: 9))
                                .foregroundStyle(DS.textMuted)
                        }
                    }
                    .padding(.vertical, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    ResearchBlockDropdownView(
                        atomUUID: block.entityUuid,
                        atomBody: atom?.body
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Metadata Row

    private var metadataRow: some View {
        HStack(spacing: 6) {
            if let author = author {
                Text(author)
                    .font(DS.footnote)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            }

            if let platform = platform {
                if author != nil {
                    Text("\u{00B7}")
                        .foregroundStyle(DS.textMuted)
                }
                Text(platform)
                    .font(DS.footnote)
                    .foregroundStyle(DS.textSecondary)
            }

            if let duration = duration {
                Text("\u{00B7}")
                    .foregroundStyle(DS.textMuted)
                Text(duration)
                    .font(DS.footnote)
                    .foregroundStyle(DS.textSecondary)
            }

            // Swipe: hook type pill
            if isSwipeFile,
               let hookTypeRaw = block.metadata["hookType"],
               let hookType = SwipeHookType(rawValue: hookTypeRaw) {
                HStack(spacing: 3) {
                    Image(systemName: hookType.iconName)
                        .font(.system(size: 8))
                    Text(hookType.displayName)
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(hookType.color)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(hookType.color.opacity(0.12), in: Capsule())
            }
        }
    }

    // MARK: - Footer

    private var footerRow: some View {
        HStack {
            // URL indicator
            if let url = resolvedURL {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.system(size: 10))
                    Text(extractDomain(from: url))
                        .font(.system(size: 10))
                        .lineLimit(1)
                }
                .foregroundStyle(accentColor.opacity(0.7))
            }

            // Swipe: hook score
            if isSwipeFile,
               let scoreStr = block.metadata["hookScore"],
               let score = Double(scoreStr) {
                HStack(spacing: 3) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 9))
                    Text(String(format: "%.0f", score))
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(hookScoreColor(score))
            }

            // Engagement badge (from creator import)
            if isSwipeFile, let likes = atom?.swipeAnalysis?.likesCount, likes > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 8))
                    Text(formatEngagement(likes))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                }
                .foregroundStyle(DS.entitySwipe)
            }

            // Processing indicator
            if isProcessing {
                HStack(spacing: 3) {
                    Circle()
                        .fill(DS.orange)
                        .frame(width: 4, height: 4)
                    Text("Processing")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DS.orange)
                }
            }

            Spacer()

            // Timestamp
            if let created = block.metadata["created"] {
                Text(formatTimestamp(created))
                    .font(.system(size: 10))
                    .foregroundStyle(DS.textMuted)
            }
        }
    }

    private func hookScoreColor(_ score: Double) -> Color {
        if score >= 8.0 { return DS.green }
        if score >= 5.0 { return DS.orange }
        return DS.textMuted
    }

    private func formatEngagement(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }

    // MARK: - Content Type Icon

    private var contentTypeIcon: String {
        switch contentType {
        case "Video": return "play.rectangle.fill"
        case "PDF": return "doc.text.fill"
        case "Social": return "bubble.left.and.bubble.right.fill"
        case "Article": return "doc.richtext.fill"
        default: return "magnifyingglass"
        }
    }

    // MARK: - Data Loading

    private func syncViewportActivity(forceReload: Bool = false) {
        guard isViewportActive else {
            deactivateViewportContent()
            return
        }

        if forceReload || atom == nil {
            loadAtom(forceReload: forceReload)
        }
    }

    private func deactivateViewportContent() {
        loadTask?.cancel()
        loadTask = nil
        isPlayerActive = false
    }

    private func loadAtom(forceReload: Bool = false) {
        guard isViewportActive else { return }
        guard forceReload || atom == nil else { return }

        loadTask?.cancel()
        isLoading = true

        loadTask = Task {
            defer {
                Task { @MainActor in
                    loadTask = nil
                }
            }

            // Try by ID first, fall back to UUID (handles paste where ID may be stale)
            var loaded: Atom? = try? await AtomRepository.shared.fetch(id: block.entityId)
            if loaded == nil, !block.entityUuid.isEmpty {
                loaded = try? await AtomRepository.shared.fetch(uuid: block.entityUuid)
            }
            if let loaded {
                guard !Task.isCancelled else { return }

                // PERF: Parse structured JSON once, cache all derived metadata
                let parsed = Self.parseMetadata(atom: loaded, block: block)
                await MainActor.run {
                    atom = loaded
                    platform = parsed.platform
                    author = parsed.author
                    duration = parsed.duration
                    resolvedURL = parsed.resolvedURL
                    contentType = parsed.contentType
                    isYouTubeContent = parsed.isYouTube
                    videoId = parsed.videoId
                    resolvedThumbnailURL = parsed.thumbnailURL
                    let status = loaded.processingStatus
                    isProcessing = status != nil && status != "complete"
                    isLoading = false
                }
            } else {
                guard !Task.isCancelled else { return }

                // Fall back to block metadata when atom not found
                let url = block.metadata["url"]
                let urlLower = (url ?? "").lowercased()
                let vid = extractYouTubeVideoId(from: url)
                await MainActor.run {
                    platform = block.metadata["platform"]
                    author = block.metadata["author"]
                    duration = block.metadata["duration"]
                    resolvedURL = url
                    isYouTubeContent = urlLower.contains("youtube") || urlLower.contains("youtu.be")
                    videoId = vid
                    contentType = Self.computeContentType(url: urlLower)
                    resolvedThumbnailURL = block.metadata["thumbnail"] ?? vid.map { "https://img.youtube.com/vi/\($0)/hqdefault.jpg" }
                    isLoading = false
                }
            }
        }
    }

    /// Parse all metadata from atom's structured JSON in one pass (called once on load)
    private static func parseMetadata(atom: Atom, block: CanvasBlock) -> (platform: String?, author: String?, duration: String?, resolvedURL: String?, contentType: String, isYouTube: Bool, videoId: String?, thumbnailURL: String?) {
        var json: [String: Any]?
        if let structured = atom.structured,
           let data = structured.data(using: .utf8) {
            json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }

        let platform = json?["platform"] as? String ?? json?["source_type"] as? String ?? block.metadata["platform"]
        let author = json?["author"] as? String ?? json?["channel"] as? String ?? block.metadata["author"]
        let duration = json?["duration"] as? String ?? json?["duration_string"] as? String ?? block.metadata["duration"]

        // Resolve URL
        var resolvedURL: String?
        if let url = atom.url, !url.isEmpty { resolvedURL = url }
        else if let url = json?["url"] as? String, !url.isEmpty { resolvedURL = url }
        else if let url = json?["source_url"] as? String, !url.isEmpty { resolvedURL = url }
        else if let url = block.metadata["url"], !url.isEmpty { resolvedURL = url }

        let urlLower = (resolvedURL ?? "").lowercased()
        let isYouTube = urlLower.contains("youtube") || urlLower.contains("youtu.be")
        let contentType = computeContentType(url: urlLower)

        // Video ID
        var videoId: String?
        if let urlStr = resolvedURL {
            if let range = urlStr.range(of: "v=") {
                let start = range.upperBound
                let end = urlStr[start...].firstIndex(of: "&") ?? urlStr.endIndex
                videoId = String(urlStr[start..<end])
            } else if urlStr.contains("youtu.be/") {
                let parts = urlStr.components(separatedBy: "youtu.be/")
                if parts.count > 1 {
                    let idPart = parts[1]
                    let end = idPart.firstIndex(of: "?") ?? idPart.firstIndex(of: "&") ?? idPart.endIndex
                    videoId = String(idPart[..<end])
                }
            }
        }

        // Thumbnail URL
        var thumbnailURL: String?
        if let thumb = atom.thumbnailUrl, !thumb.isEmpty { thumbnailURL = thumb }
        else if let thumb = json?["thumbnail_url"] as? String ?? json?["thumbnail"] as? String, !thumb.isEmpty { thumbnailURL = thumb }
        else if let vid = videoId { thumbnailURL = "https://img.youtube.com/vi/\(vid)/hqdefault.jpg" }

        return (platform, author, duration, resolvedURL, contentType, isYouTube, videoId, thumbnailURL)
    }

    private static func computeContentType(url: String) -> String {
        if url.contains("youtube") || url.contains("youtu.be") || url.contains("vimeo") || url.contains("loom") {
            return "Video"
        } else if url.hasSuffix(".pdf") {
            return "PDF"
        } else if url.contains("twitter") || url.contains("x.com") || url.contains("linkedin") {
            return "Social"
        } else if !url.isEmpty {
            return "Article"
        }
        return "Research"
    }

    // MARK: - Focus Mode

    private func openFocusMode() {
        guard block.entityId > 0 else {
            print("⚠️ ResearchBlockView.openFocusMode: no backing atom (entityId=\(block.entityId)), skipping")
            return
        }
        NotificationCenter.default.post(
            name: .enterFocusMode,
            object: nil,
            userInfo: [
                "type": EntityType.research,
                "id": block.entityId
            ]
        )
    }

    // MARK: - YouTube Video ID Extraction

    private func extractYouTubeVideoId(from urlString: String?) -> String? {
        Self.extractYouTubeVideoIdStatic(from: urlString)
    }

    private static func extractYouTubeVideoIdStatic(from urlString: String?) -> String? {
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

    // MARK: - Helpers

    private func formatTimestamp(_ timestamp: String) -> String {
        if let date = ISO8601.date(from: timestamp) {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: date, relativeTo: Date())
        }
        return timestamp
    }

    private func extractDomain(from url: String) -> String {
        guard let urlObj = URL(string: url), let host = urlObj.host else {
            return url
        }
        return host.replacingOccurrences(of: "www.", with: "")
    }
}

// MARK: - Preview

#if DEBUG
struct ResearchBlockView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            DS.canvas
                .ignoresSafeArea()

            ResearchBlockView(
                block: CanvasBlock(
                    position: CGPoint(x: 200, y: 200),
                    size: CGSize(width: 320, height: 280),
                    entityType: .research,
                    entityId: 1,
                    entityUuid: "preview",
                    title: "Dan Koe - How to Reinvent Your Life",
                    metadata: [
                        "url": "https://youtube.com/watch?v=example",
                        "platform": "YouTube",
                        "author": "Dan Koe",
                        "duration": "42:18"
                    ]
                )
            )
        }
        .frame(width: 500, height: 400)
    }
}
#endif
