// CosmoOS/UI/CommandK/CortexDetailPane.swift
// Raycast-style right preview pane. Phase 2: per-type rendering (media /
// connection / reading excerpt) + the INFORMATION metadata table, hydrated
// from a lazy AtomRepository fetch keyed to the current selection.

import AVKit
import SwiftUI

/// Maps the current Command-K selection to a uniform preview subject so the
/// detail pane never needs to know whether it came from Recents or search.
enum CortexDetailSubject {
    case empty
    case recent(RecentDisplayItem)
    case result(UnifiedSearchResult)
    case library(LibraryItem)
    case swipe(SwipeGalleryItem)
    case idea(IdeaGalleryItem)
    case readwise(ReadwiseLibraryBook)
    case action(CommandKAction)

    var title: String {
        switch self {
        case .empty: return ""
        case .recent(let i): return i.title
        case .result(let r): return r.title
        case .library(let item): return item.title
        case .swipe(let item): return item.title
        case .idea(let item): return item.title
        case .readwise(let book): return book.title
        case .action(let action): return action.title
        }
    }

    var typeLabel: String {
        switch self {
        case .empty: return ""
        case .recent(let i): return i.type.displayName
        case .result(let r): return r.source.displayName
        case .library(let item): return item.typeName
        case .swipe: return "Swipe File"
        case .idea: return "Idea"
        case .readwise(let book): return book.category.displayName
        case .action: return "Command"
        }
    }

    var metaLine: String? {
        switch self {
        case .empty: return nil
        case .recent(let i): return i.relativeDate
        case .result(let r): return r.subtitle
        case .library(let item): return item.relativeDate
        case .swipe(let item): return [item.creatorName ?? item.author, item.platformName].compactMap { $0 }.joined(separator: " · ")
        case .idea(let item): return [item.status.displayName, item.clientName].compactMap { $0 }.joined(separator: " · ")
        case .readwise(let book): return [book.author, "\(book.numHighlights) highlights"].compactMap { $0 }.joined(separator: " · ")
        case .action(let action): return action.scopedIdeaDestinationText ?? action.subtitle
        }
    }

    var accentColor: Color {
        switch self {
        case .empty: return DS.textSecondary
        case .recent(let i): return cortexEntityAccent(i.type)
        case .result(let r): return r.accentColor
        case .library(let item): return item.color
        case .swipe: return DS.entitySwipe
        case .idea: return DS.entityIdea
        case .readwise: return DS.entityReadwise
        case .action: return DS.accent
        }
    }

    var thumbnailURL: String? {
        if case .recent(let i) = self { return i.thumbnailURL }
        if case .library(let item) = self { return item.thumbnailURL }
        if case .swipe(let item) = self { return item.thumbnailUrl }
        if case .readwise(let book) = self { return book.coverImageUrl }
        return nil
    }

    var previewText: String? {
        switch self {
        case .recent(let i): return i.preview
        case .result(let r): return r.snippet ?? r.subtitle
        case .library(let item): return item.preview
        case .swipe(let item): return item.hookText
        case .idea(let item): return item.context ?? item.body ?? item.hooks.first
        case .readwise(let book): return book.highlights.first?.text ?? "\(book.numHighlights) saved highlights"
        case .action(let action): return action.scopedIdeaPreviewText ?? action.subtitle ?? action.payload.rawText
        default: return nil
        }
    }

    var atomUUID: String? {
        switch self {
        case .recent(let i): return i.id
        case .result(let r): return r.atomUUID
        case .library(let item): return item.kind == .thinkspace ? nil : item.uuid
        case .swipe(let item): return item.atomUUID
        case .idea(let item): return item.atomUUID
        default: return nil
        }
    }

    var selectionIdentity: String {
        switch self {
        case .empty: return "empty"
        case .recent(let item): return item.id
        case .result(let result): return result.selectionID
        case .library(let item): return item.uuid
        case .swipe(let item): return item.atomUUID
        case .idea(let item): return item.atomUUID
        case .readwise(let book): return "readwise-\(book.id)"
        case .action(let action): return action.id
        }
    }

    var renderSignature: String {
        [
            selectionIdentity,
            title,
            typeLabel,
            metaLine ?? "",
            previewText ?? "",
            atomUUID ?? ""
        ].joined(separator: "\u{1F}")
    }

    var isEmpty: Bool {
        if case .empty = self { return true }
        return false
    }

    var isConnection: Bool {
        if case .recent(let i) = self { return i.type == .connection }
        if case .result(let r) = self { return r.atomType == .connection }
        if case .library(let item) = self { return item.atomType == .connection }
        return false
    }

    var createdText: String? {
        switch self {
        case .library(let item): return cortexFormatDate(item.createdAt)
        case .swipe(let item): return cortexFormatISO(item.createdAt)
        case .idea(let item): return cortexFormatISO(item.createdAt)
        default: return nil
        }
    }

    var updatedText: String? {
        switch self {
        case .library(let item): return cortexFormatDate(item.updatedAt)
        case .idea(let item): return cortexFormatISO(item.updatedAt)
        default: return nil
        }
    }

    var linksCount: Int? {
        switch self {
        case .library(let item): return max(item.childCount, item.blockCount)
        default: return nil
        }
    }

    var preferredPreviewHeight: CGFloat {
        switch self {
        case .swipe: return 380
        default: return 220
        }
    }
}

/// Shared entity-accent mapping (mirrors the recents card palette).
func cortexEntityAccent(_ type: AtomType) -> Color {
    switch type {
    case .idea: return DS.entityIdea
    case .task: return DS.entityTask
    case .research: return DS.entityResearch
    case .content: return DS.entityContent
    case .connection: return DS.entityConnection
    case .project: return DS.entityIdea
    case .image: return DS.entityImage
    default: return DS.textSecondary
    }
}

struct CortexDetailPane: View {
    let subject: CortexDetailSubject

    @State private var atom: Atom?
    @State private var detailScrollMetrics = CortexScrollMetrics()

    var body: some View {
        Group {
            if case .empty = subject { emptyState } else { loaded }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(DS.space24)
        .task(id: subject.atomUUID) { await loadAtom() }
    }

    private func loadAtom() async {
        atom = nil
        guard let id = subject.atomUUID else { return }
        atom = try? await AtomRepository.shared.fetch(uuid: id)
    }

    private var emptyState: some View {
        VStack(spacing: DS.space10) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(DS.giltMuted)
            Text("Select something to preview")
                .font(DS.dateSerif)
                .italic()
                .foregroundStyle(DS.inkFaded)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loaded: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space16) {
                CortexPreviewBlock(subject: subject, atom: atom)
                    .frame(maxWidth: .infinity)
                    .frame(height: previewHeight)
                    .clipShape(.rect(cornerRadius: DS.radiusMedium))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                            .strokeBorder(DS.sepiaSubtle, lineWidth: 0.5)
                    )

                Text(subject.title)
                    .font(DS.spaceTitleSerif)
                    .foregroundStyle(DS.text)
                    .lineLimit(3)

                CortexInformationTable(
                    typeLabel: subject.typeLabel,
                    created: subject.createdText ?? cortexFormatISO(atom?.createdAt),
                    updated: subject.updatedText ?? cortexFormatISO(atom?.updatedAt),
                    links: subject.linksCount ?? atom?.linksList.count,
                    fallbackMeta: subject.metaLine
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CortexScrollViewIntrospector { metrics in
                detailScrollMetrics = metrics
            })
        }
        .scrollIndicators(.hidden)
        .cortexThinScrollbar(metrics: detailScrollMetrics)
    }

    private var previewHeight: CGFloat {
        if atom?.toSwipeGalleryItem() != nil { return 380 }
        return subject.preferredPreviewHeight
    }
}

/// Per-type preview: media → image, connection → section map, text → a
/// serif reading excerpt, otherwise a faux page.
private struct CortexPreviewBlock: View {
    let subject: CortexDetailSubject
    let atom: Atom?

    var body: some View {
        if let item = atom?.toSwipeGalleryItem() {
            CortexSwipeDomainPreview(item: item, atom: atom)
        } else {
            switch subject {
            case .library(let item):
                CommandKLibraryThumbnail(item: item, cornerRadius: DS.radiusMedium)
                    .background(CommandKPreviewPaper.fill)
            case .swipe(let item):
                CortexSwipeDomainPreview(item: item, atom: atom)
            case .idea(let item):
                CortexIdeaDomainPreview(item: item)
            case .readwise(let book):
                CortexReadwiseDomainPreview(book: book)
            case .action(let action):
                if action.scopedIdeaClientName != nil {
                    genericPreview
                } else {
                    CommandKActionVisualPreview(
                        action: action,
                        identity: CommandKVisualIdentity.action(action)
                    )
                }
            case .result(let result) where result.resultKind == .browserPin:
                CommandKActionVisualPreview(
                    action: CommandKAction(
                        kind: .openBrowser,
                        title: result.title,
                        subtitle: result.subtitle,
                        icon: result.icon,
                        payload: CommandKActionPayload(url: result.browserURL?.absoluteString, title: result.browserTitle)
                    ),
                    identity: CommandKVisualIdentity.result(result)
                )
            default:
                genericPreview
            }
        }
    }

    @ViewBuilder
    private var genericPreview: some View {
        if let url = subject.thumbnailURL, !url.isEmpty {
            SpotlightImageContent(urlString: url)
        } else if subject.isConnection {
            SpotlightConnectionPreview(preview: subject.previewText, accentColor: subject.accentColor)
        } else if let text = readingText, !text.isEmpty {
            readingCard(text)
        } else {
            SpotlightFauxPage(accentColor: subject.accentColor)
        }
    }

    private var readingText: String? {
        let t = atom?.body ?? subject.previewText
        guard let t, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return t
    }

    private func readingCard(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(DS.dateSerif)
                .foregroundStyle(CommandKPreviewPaper.text)
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.space16)
        }
        .scrollIndicators(.hidden)
        .background(CommandKPreviewPaper.fill)
    }
}

private struct CortexSwipeDomainPreview: View {
    let item: SwipeGalleryItem
    let atom: Atom?

    @State private var selectedMediaIndex = 0

    private var mediaItems: [CortexSwipePreviewMedia] {
        CortexSwipePreviewMedia.resolve(for: item, atom: atom)
    }

    private var selectedMedia: CortexSwipePreviewMedia {
        mediaItems[min(max(selectedMediaIndex, 0), max(mediaItems.count - 1, 0))]
    }

    var body: some View {
        VStack(spacing: DS.space10) {
            swipeToolbar
            mediaStage
            slideControls
        }
        .padding(DS.space12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.vellum)
        .onChange(of: item.id) { _, _ in selectedMediaIndex = 0 }
    }

    private var swipeToolbar: some View {
        HStack(spacing: DS.space8) {
            HStack(spacing: DS.space6) {
                Image(systemName: selectedMedia.style.iconName)
                    .font(.system(size: 11, weight: .semibold))
                Text(selectedMedia.style.label)
                    .font(DS.smallCaps)
            }
            .foregroundStyle(DS.giltMuted)

            Spacer(minLength: DS.space8)

            if mediaItems.count > 1 {
                Text("\(selectedMediaIndex + 1) / \(mediaItems.count)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DS.textMuted)
            } else if let duration = item.duration, duration > 0 {
                Text(formatDuration(duration))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DS.textMuted)
            }
        }
    }

    private var mediaStage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                .fill(DS.vellumDeep)

            CortexSwipeMediaSurface(media: selectedMedia, fallbackIcon: item.platformIcon)
                .aspectRatio(selectedMedia.style.aspectRatio, contentMode: .fit)
                .frame(maxWidth: selectedMedia.style.maxWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, DS.space4)
        }
        .clipShape(.rect(cornerRadius: DS.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                .strokeBorder(DS.sepiaSubtle, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var slideControls: some View {
        if mediaItems.count > 1 {
            HStack(spacing: DS.space12) {
                mediaStepButton(systemName: "chevron.left", label: "Previous slide") {
                    selectedMediaIndex = max(selectedMediaIndex - 1, 0)
                }
                .disabled(selectedMediaIndex == 0)

                HStack(spacing: DS.space4) {
                    ForEach(Array(mediaItems.enumerated()), id: \.element.id) { index, media in
                        Button {
                            selectedMediaIndex = index
                        } label: {
                            Circle()
                                .fill(index == selectedMediaIndex ? DS.gilt : DS.sepiaSubtle)
                                .frame(width: 6, height: 6)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 24, height: 24)
                        .accessibilityLabel("Slide \(index + 1)")
                        .accessibilityValue(media.accessibilityLabel)
                    }
                }

                mediaStepButton(systemName: "chevron.right", label: "Next slide") {
                    selectedMediaIndex = min(selectedMediaIndex + 1, mediaItems.count - 1)
                }
                .disabled(selectedMediaIndex >= mediaItems.count - 1)
            }
        } else {
            Text([item.creatorName ?? item.author, item.platformName].compactMap { $0 }.joined(separator: " · "))
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .lineLimit(1)
        }
    }

    private func mediaStepButton(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 34, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(DS.textSecondary)
        .background(DS.vellumDeep.opacity(0.72), in: Capsule())
        .overlay(Capsule().strokeBorder(DS.sepiaSubtle, lineWidth: 0.5))
        .accessibilityLabel(label)
        .help(label)
    }

    private func formatDuration(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct CortexSwipeMediaSurface: View {
    let media: CortexSwipePreviewMedia
    let fallbackIcon: String

    var body: some View {
        switch media.kind {
        case .image(let url):
            CortexSwipeImageSurface(url: url, stableKey: media.id)
        case .video(let url, let thumbnailURL):
            CortexSwipeVideoSurface(url: url, thumbnailURL: thumbnailURL, stableKey: media.id)
        case .placeholder:
            CortexSwipeMediaPlaceholder(iconName: fallbackIcon)
        }
    }
}

private struct CortexSwipeImageSurface: View {
    let url: URL
    let stableKey: String

    var body: some View {
        CachedAsyncImage(url: url, stableKey: stableKey) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                ProgressView()
                    .scaleEffect(0.72)
                    .tint(DS.textMuted)
            case .failure:
                CortexSwipeMediaPlaceholder(iconName: "photo")
            }
        }
    }
}

private struct CortexSwipeVideoSurface: View {
    let url: URL?
    let thumbnailURL: URL?
    let stableKey: String

    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
            } else if let thumbnailURL {
                CortexSwipeImageSurface(url: thumbnailURL, stableKey: stableKey)
                playOverlay
            } else {
                CortexSwipeMediaPlaceholder(iconName: "play.rectangle.fill")
                playOverlay
            }
        }
        .background(DS.inkWash)
        .onAppear(perform: configurePlayer)
        .onChange(of: url) { _, _ in configurePlayer() }
        .onDisappear { player?.pause() }
    }

    private var playOverlay: some View {
        Image(systemName: "play.circle.fill")
            .font(.system(size: 42, weight: .semibold))
            .foregroundStyle(DS.textOnAccent.opacity(0.92))
            .shadow(color: DS.inkWash.opacity(0.28), radius: 10, x: 0, y: 4)
            .accessibilityHidden(true)
    }

    private func configurePlayer() {
        guard let url else {
            player = nil
            return
        }
        player = AVPlayer(url: url)
    }
}

private struct CortexSwipeMediaPlaceholder: View {
    let iconName: String

    var body: some View {
        ZStack {
            DS.entitySwipe.opacity(0.12)
            Image(systemName: iconName)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(DS.entitySwipe.opacity(0.72))
                .accessibilityHidden(true)
        }
    }
}

private struct CortexSwipePreviewMedia: Identifiable, Equatable {
    enum Kind: Equatable {
        case image(URL)
        case video(url: URL?, thumbnailURL: URL?)
        case placeholder
    }

    enum Style: Equatable {
        case square
        case portraitVideo
        case landscapeVideo

        var aspectRatio: CGFloat {
            switch self {
            case .square: return 1
            case .portraitVideo: return 9.0 / 16.0
            case .landscapeVideo: return 16.0 / 9.0
            }
        }

        var maxWidth: CGFloat {
            switch self {
            case .square: return 326
            case .portraitVideo: return 206
            case .landscapeVideo: return 420
            }
        }

        var label: String {
            switch self {
            case .square: return "Carousel"
            case .portraitVideo: return "Video"
            case .landscapeVideo: return "Video"
            }
        }

        var iconName: String {
            switch self {
            case .square: return "square.on.square"
            case .portraitVideo, .landscapeVideo: return "play.rectangle.fill"
            }
        }
    }

    let id: String
    let kind: Kind
    let style: Style

    var accessibilityLabel: String {
        switch kind {
        case .image: return "Image"
        case .video: return "Video"
        case .placeholder: return "Preview"
        }
    }

    static func resolve(for item: SwipeGalleryItem, atom: Atom?) -> [Self] {
        let richContent = atom?.richContent
        let itemShortcode = item.instagramId.flatMap { $0.isEmpty ? nil : $0 }
        let atomShortcode = atom.flatMap(Self.shortcode)
        let shortcode = itemShortcode ?? atomShortcode

        if let carouselItems = richContent?.instagramData?.carouselItems, !carouselItems.isEmpty {
            return carouselItems
                .sorted { $0.index < $1.index }
                .map { media(from: $0, shortcode: shortcode) }
        }

        let style = inferredStyle(for: item, richContent: richContent)
        if style != .square,
           let media = videoMedia(for: item, atom: atom, richContent: richContent, style: style) {
            return [media]
        }

        if let thumbnailURL = thumbnailURL(for: item, atom: atom, richContent: richContent) {
            return [Self(id: "thumb-\(thumbnailURL.absoluteString)", kind: .image(thumbnailURL), style: style)]
        }

        return [Self(id: "placeholder-\(item.id)", kind: .placeholder, style: style)]
    }

    private static func videoMedia(
        for item: SwipeGalleryItem,
        atom: Atom?,
        richContent: ResearchRichContent?,
        style: Style
    ) -> Self? {
        let playableURL = videoURL(for: item, richContent: richContent)
        let thumbnailURL = thumbnailURL(for: item, atom: atom, richContent: richContent)
        guard playableURL != nil || thumbnailURL != nil else { return nil }

        let id = playableURL?.absoluteString ?? thumbnailURL?.absoluteString ?? item.id
        return Self(
            id: "video-\(id)",
            kind: .video(url: playableURL, thumbnailURL: thumbnailURL),
            style: style
        )
    }

    private static func media(from item: CarouselItem, shortcode: String?) -> Self {
        let id = InstagramCarouselImageCache.stableKey(for: item, shortcode: shortcode)
        let displayURL = InstagramCarouselImageCache.displayURL(for: item, shortcode: shortcode)
        switch item.mediaType {
        case .image:
            return Self(id: id, kind: .image(displayURL), style: .square)
        case .video:
            return Self(
                id: id,
                kind: .video(url: item.mediaURL, thumbnailURL: item.thumbnailURL ?? displayURL),
                style: .square
            )
        }
    }

    private static func shortcode(from atom: Atom) -> String? {
        guard let urlString = atom.url,
              let url = URL(string: urlString) else {
            return nil
        }
        let pathComponents = url.pathComponents
        for marker in ["p", "reel", "tv"] {
            if let markerIndex = pathComponents.firstIndex(of: marker) {
                let shortcodeIndex = pathComponents.index(after: markerIndex)
                guard shortcodeIndex < pathComponents.endIndex else { continue }
                let shortcode = pathComponents[shortcodeIndex]
                if !shortcode.isEmpty { return shortcode }
            }
        }
        return nil
    }

    private static func inferredStyle(
        for item: SwipeGalleryItem,
        richContent: ResearchRichContent?
    ) -> Style {
        if isCarousel(item: item, richContent: richContent) || isInstagramPost(item: item, richContent: richContent) {
            return .square
        }

        if isLandscapeVideo(item: item, richContent: richContent) {
            return .landscapeVideo
        }

        if isVideo(item: item, richContent: richContent) {
            return .portraitVideo
        }

        return .square
    }

    private static func isCarousel(item: SwipeGalleryItem, richContent: ResearchRichContent?) -> Bool {
        let platform = item.platform?.lowercased() ?? ""
        return platform.contains("carousel")
            || item.swipeContentFormat == .carousel
            || richContent?.sourceType == .instagramCarousel
            || richContent?.instagramType == "carousel"
            || richContent?.instagramData?.contentType == .carousel
    }

    private static func isInstagramPost(item: SwipeGalleryItem, richContent: ResearchRichContent?) -> Bool {
        let platform = item.platform?.lowercased() ?? ""
        return platform.contains("instagrampost")
            || platform.contains("instagram_post")
            || richContent?.sourceType == .instagramPost
            || richContent?.instagramData?.contentType == .image
    }

    private static func isLandscapeVideo(item: SwipeGalleryItem, richContent: ResearchRichContent?) -> Bool {
        let platform = item.platform?.lowercased() ?? ""
        return platform == "youtube" || richContent?.sourceType == .youtube
    }

    private static func isVideo(item: SwipeGalleryItem, richContent: ResearchRichContent?) -> Bool {
        let platform = item.platform?.lowercased() ?? ""
        return platform.contains("reel")
            || platform.contains("short")
            || item.swipeContentFormat?.isVideoFormat == true
            || richContent?.sourceType == .instagramReel
            || richContent?.sourceType == .youtubeShort
            || richContent?.instagramType == "reel"
            || richContent?.instagramData?.contentType.isVideo == true
    }

    private static func videoURL(for item: SwipeGalleryItem, richContent: ResearchRichContent?) -> URL? {
        if let shortcode = item.instagramId,
           let localURL = InstagramVideoLocalCache.localVideoURL(forShortcode: shortcode) {
            return localURL
        }
        return richContent?.instagramData?.extractedMediaURL
    }

    private static func thumbnailURL(
        for item: SwipeGalleryItem,
        atom: Atom?,
        richContent: ResearchRichContent?
    ) -> URL? {
        [
            item.thumbnailUrl,
            atom?.thumbnailUrl,
            richContent?.thumbnailUrl,
            richContent?.instagramData?.carouselItems?.first(where: { $0.mediaType == .image })?.mediaURL.absoluteString,
            richContent?.instagramData?.carouselItems?.first?.mediaURL.absoluteString
        ]
        .compactMap { $0 }
        .first(where: { !$0.isEmpty })
        .flatMap(URL.init(string:))
    }
}

private struct CortexIdeaDomainPreview: View {
    let item: IdeaGalleryItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space12) {
                if let contextText {
                    previewSection("CONTEXT", text: contextText)
                }
                if !item.hooks.isEmpty {
                    previewList("HOOKS", values: Array(item.hooks.prefix(3)))
                }
                if !item.outline.isEmpty {
                    previewList("OUTLINE", values: Array(item.outline.prefix(4)))
                }
                if contextText == nil, item.hooks.isEmpty, item.outline.isEmpty {
                    Text(item.body ?? "No idea context captured yet.")
                        .font(DS.dateSerif)
                        .italic()
                        .foregroundStyle(DS.inkFaded)
                }
            }
            .padding(DS.space16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(CommandKPreviewPaper.fill)
    }

    private var contextText: String? {
        item.context ?? item.body
    }

    private func previewSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Text(title)
                .font(DS.smallCaps)
                .foregroundStyle(DS.entityIdea)
            Text(text)
                .font(DS.callout)
                .foregroundStyle(CommandKPreviewPaper.text)
                .lineSpacing(3)
                .lineLimit(6)
        }
    }

    private func previewList(_ title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Text(title)
                .font(DS.smallCaps)
                .foregroundStyle(DS.entityIdea)
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                HStack(alignment: .top, spacing: DS.space8) {
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DS.entityIdea)
                        .frame(width: 18, height: 18)
                        .background(DS.entityIdea.opacity(0.10), in: Circle())
                    Text(value)
                        .font(DS.caption)
                        .foregroundStyle(CommandKPreviewPaper.textSecondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

private struct CortexReadwiseDomainPreview: View {
    let book: ReadwiseLibraryBook

    var body: some View {
        HStack(alignment: .top, spacing: DS.space18) {
            cover
                .frame(width: 96, height: 144)
            VStack(alignment: .leading, spacing: DS.space12) {
                Text(book.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(CommandKPreviewPaper.text)
                    .lineLimit(3)
                if let author = book.author {
                    Text(author)
                        .font(DS.callout)
                        .foregroundStyle(CommandKPreviewPaper.textSecondary)
                }
                Text(book.highlights.first?.text ?? "\(book.numHighlights) saved highlights.")
                    .font(DS.dateSerif)
                    .foregroundStyle(CommandKPreviewPaper.text)
                    .lineSpacing(4)
                    .lineLimit(5)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.space18)
        .background(CommandKPreviewPaper.fill)
    }

    private var cover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(DS.vellumDeep)
            if let coverURL = book.coverImageUrl, let url = URL(string: coverURL) {
                CachedAsyncImage(url: url, stableKey: "\(book.id)") { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty:
                        ProgressView().scaleEffect(0.6).tint(DS.textMuted)
                    case .failure:
                        fallbackCover
                    }
                }
            } else {
                fallbackCover
            }
        }
        .clipShape(.rect(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(DS.sepiaBorder, lineWidth: 0.5)
        )
    }

    private var fallbackCover: some View {
        Text(book.title.prefix(28).description)
            .font(.system(size: 11, weight: .semibold, design: .serif))
            .foregroundStyle(DS.entityReadwise)
            .multilineTextAlignment(.center)
            .lineLimit(4)
            .padding(DS.space10)
    }
}
