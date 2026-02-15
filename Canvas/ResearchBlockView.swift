// CosmoOS/Canvas/ResearchBlockView.swift
// Green-accented Research block for Thinkspace canvas
// Dark glass design matching Sanctuary aesthetic
// Features: Playable video preview, collapsible transcript & annotations dropdown

import SwiftUI

struct ResearchBlockView: View {
    let block: CanvasBlock

    @State private var isExpanded = false
    @State private var atom: Atom?
    @State private var isLoading = true
    @State private var isPlayerActive = false
    @State private var currentTimestamp: TimeInterval = 0
    @State private var isDropdownOpen = false
    @EnvironmentObject private var expansionManager: BlockExpansionManager

    // Green accent for research
    private let accentColor = CosmoColors.blockResearch

    // MARK: - Parsed Metadata

    private var platform: String? {
        guard let structured = atom?.structured,
              let data = structured.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return block.metadata["platform"]
        }
        return json["platform"] as? String ?? json["source_type"] as? String
    }

    private var author: String? {
        guard let structured = atom?.structured,
              let data = structured.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return block.metadata["author"]
        }
        return json["author"] as? String ?? json["channel"] as? String
    }

    private var duration: String? {
        guard let structured = atom?.structured,
              let data = structured.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return block.metadata["duration"]
        }
        return json["duration"] as? String ?? json["duration_string"] as? String
    }

    private var thumbnailURL: String? {
        guard let structured = atom?.structured,
              let data = structured.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return block.metadata["thumbnail"]
        }
        return json["thumbnail_url"] as? String ?? json["thumbnail"] as? String
    }

    /// Resolve the URL from atom data first, then fall back to block metadata
    private var resolvedURL: String? {
        // 1. Check loaded atom's url property
        if let url = atom?.url, !url.isEmpty { return url }
        // 2. Check atom's structured JSON
        if let structured = atom?.structured,
           let data = structured.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let url = json["url"] as? String, !url.isEmpty { return url }
            if let url = json["source_url"] as? String, !url.isEmpty { return url }
        }
        // 3. Fall back to block metadata
        if let url = block.metadata["url"], !url.isEmpty { return url }
        return nil
    }

    private var contentType: String {
        let url = resolvedURL?.lowercased() ?? ""
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

    private var isYouTubeContent: Bool {
        let url = resolvedURL?.lowercased() ?? ""
        return url.contains("youtube") || url.contains("youtu.be")
    }

    private var videoId: String? {
        extractYouTubeVideoId(from: resolvedURL)
    }

    /// Build a YouTube thumbnail URL from the video ID if no explicit thumbnail is available
    private var resolvedThumbnailURL: String? {
        // Check atom's thumbnailUrl first
        if let thumb = atom?.thumbnailUrl, !thumb.isEmpty { return thumb }
        if let thumb = thumbnailURL, !thumb.isEmpty { return thumb }
        if let vid = videoId {
            return "https://img.youtube.com/vi/\(vid)/hqdefault.jpg"
        }
        return nil
    }

    // MARK: - Body

    var body: some View {
        CosmoBlockWrapper(
            block: block,
            accentColor: accentColor,
            icon: "magnifyingglass",
            title: block.title,
            isExpanded: $isExpanded,
            onFocusMode: openFocusMode
        ) {
            researchContent
        }
        .onAppear {
            loadAtom()
        }
    }

    // MARK: - Research Content

    private var researchContent: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                // Header with metadata
                metadataHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                // Video area (replaces raw body text)
                videoArea
                    .padding(.horizontal, 16)

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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Metadata Header

    private var metadataHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Content type badge
            Text(contentType.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(accentColor)
                .tracking(0.8)

            // Title
            Text(block.title.isEmpty ? "Untitled Research" : block.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(2)

            // Metadata row
            metadataRow
        }
    }

    // MARK: - Video Area

    @ViewBuilder
    private var videoArea: some View {
        if isLoading {
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
                    AsyncImage(url: thumbURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(16/9, contentMode: .fill)
                        case .failure, .empty:
                            thumbnailPlaceholderBackground
                        @unknown default:
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
                        .foregroundColor(.white)
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
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                case .failure, .empty:
                    thumbnailPlaceholderBackground
                @unknown default:
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
                            .foregroundColor(.white)
                    }
                    Text("Open")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
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
                    .foregroundColor(accentColor.opacity(0.6))

                Text(contentType)
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.35))
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
                        colors: [accentColor.opacity(0.12), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: contentTypeIcon)
                .font(.system(size: 28))
                .foregroundColor(accentColor.opacity(0.4))
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
                        .foregroundColor(accentColor)

                    Text("Transcript & Notes")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.6))

                    Spacer()
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Dropdown content
            if isDropdownOpen {
                ResearchBlockDropdownView(
                    atomUUID: block.entityUuid,
                    atomBody: atom?.body
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Metadata Row

    private var metadataRow: some View {
        HStack(spacing: 6) {
            if let author = author {
                Text(author)
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.5))
                    .lineLimit(1)
            }

            if let platform = platform {
                if author != nil {
                    Text("\u{00B7}")
                        .foregroundColor(Color.white.opacity(0.3))
                }
                Text(platform)
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.5))
            }

            if let duration = duration {
                Text("\u{00B7}")
                    .foregroundColor(Color.white.opacity(0.3))
                Text(duration)
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.5))
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
                .foregroundColor(accentColor.opacity(0.7))
            }

            Spacer()

            // Timestamp
            if let created = block.metadata["created"] {
                Text(formatTimestamp(created))
                    .font(.system(size: 10))
                    .foregroundColor(Color.white.opacity(0.3))
            }
        }
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

    private func loadAtom() {
        Task {
            if let loaded = try? await AtomRepository.shared.fetch(id: block.entityId) {
                await MainActor.run {
                    atom = loaded
                    isLoading = false
                }
            } else {
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }

    // MARK: - Focus Mode

    private func openFocusMode() {
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
        if let date = ISO8601DateFormatter().date(from: timestamp) {
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
            CosmoColors.thinkspaceVoid
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
            .environmentObject(BlockExpansionManager())
        }
        .frame(width: 500, height: 400)
    }
}
#endif
