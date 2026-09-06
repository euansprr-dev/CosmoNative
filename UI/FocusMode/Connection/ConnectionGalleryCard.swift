// CosmoOS/UI/FocusMode/Connection/ConnectionGalleryCard.swift
// The Gallery: one more masonry card on the concept board holding the
// concept's media references — swipes, YouTube videos, dropped images.
// Tiles are STATIC thumbnails only (players live in the lightbox); the card
// is also the primary drop target for swipe-card drags.
// July 2026

import SwiftUI

// MARK: - Thumbnail resolution

/// Shared thumbnail truth for concept media: gallery tiles, section strips,
/// item chips, covers, and the lightbox fallback all resolve through here.
enum ConceptMediaThumbnailResolver {

    /// Remote thumbnail for an atom-backed ref, mirroring the canvas
    /// MediaBlockView's resolution order.
    @MainActor
    static func thumbnailURL(for atom: Atom) -> URL? {
        if let thumb = atom.thumbnailUrl, !thumb.isEmpty, let url = URL(string: thumb) {
            return url
        }
        if let thumb = atom.richContent?.thumbnailUrl, !thumb.isEmpty, let url = URL(string: thumb) {
            return url
        }
        if let items = atom.richContent?.instagramData?.carouselItems, let first = items.first {
            let shortcode = atom.url.flatMap(URL.init(string:))
                .flatMap { InstagramExtractor.shared.extractShortcode(from: $0) }
            return InstagramCarouselImageCache.displayURL(for: first, shortcode: shortcode)
        }
        if let videoId = atom.richContent?.videoId, !videoId.isEmpty {
            return URL(string: "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg")
        }
        return nil
    }

    static func stableKey(for item: ConnectionMediaItem) -> String {
        "concept-media-\(item.atomUUID ?? item.id.uuidString)"
    }

    /// Duration chip text for video media, when the source knows it.
    static func durationLabel(for atom: Atom?) -> String? {
        guard let seconds = atom?.richContent?.duration, seconds > 0 else { return nil }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }
}

// MARK: - Local asset thumbnails

/// Downsampled local-file thumbnails with a shared cache — owned assets must
/// never decode full-resolution on the board.
@MainActor
final class ConceptLocalThumbnailCache {
    static let shared = ConceptLocalThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 200
    }

    func cached(path: String) -> NSImage? {
        cache.object(forKey: path as NSString)
    }

    func image(path: String, maxPixel: CGFloat) async -> NSImage? {
        let key = path as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let loaded = await Task.detached(priority: .utility) { () -> NSImage? in
            let url = URL(fileURLWithPath: path)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }.value
        if let loaded { cache.setObject(loaded, forKey: key) }
        return loaded
    }
}

/// Async local-file thumbnail view (poster or image asset).
struct ConceptLocalThumbnail: View {
    let path: String
    var maxPixel: CGFloat = 400

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .accessibilityHidden(true)
            } else {
                Rectangle().fill(DS.glassSectionFill)
            }
        }
        .task(id: path) {
            if let hit = ConceptLocalThumbnailCache.shared.cached(path: path) {
                image = hit
                return
            }
            image = await ConceptLocalThumbnailCache.shared.image(path: path, maxPixel: maxPixel)
        }
    }
}

// MARK: - Gallery card

struct ConnectionGalleryCard: View {
    /// Ordered media refs (state.orderedMedia).
    let media: [ConnectionMediaItem]
    /// Source atoms for atom-backed refs, keyed by uuid.
    let atoms: [String: Atom]
    var isSelected: Bool = false
    /// URL captures in flight — one skeleton tile each.
    var pendingCaptureCount: Int = 0
    /// attach_media staged candidates — dashed ghost tiles with ✓/✗.
    var stagedAtoms: [Atom] = []
    /// Tiles ⌘-queued for the compare strip.
    var compareSelection: Set<UUID> = []
    let actions: ConnectionWorkspaceActions

    @State private var isHovered = false
    @State private var isDropTargeted = false
    @State private var isExpanded = false

    private static let collapsedTileLimit = 6
    private let accent = Color(hex: "#D97706") // gallery amber, sibling of examples

    private var visibleMedia: [ConnectionMediaItem] {
        isExpanded ? media : Array(media.prefix(Self.collapsedTileLimit))
    }

    private var overflowCount: Int {
        max(0, media.count - Self.collapsedTileLimit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            header
            if media.isEmpty && pendingCaptureCount == 0 && stagedAtoms.isEmpty {
                emptyPrompt
            } else {
                tileGrid
            }
        }
        .padding(DS.space16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(DS.surfaceElevated)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(cardBorder)
        .shadow(
            color: .black.opacity(isHovered ? 0.10 : 0.05),
            radius: isHovered ? 10 : 4,
            y: isHovered ? 4 : 1
        )
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .dropDestination(for: AtomDragPayload.self) { payloads, _ in
            guard !payloads.isEmpty else { return false }
            actions.onDropMediaAtoms(payloads.map(\.atomUUID), nil)
            return true
        } isTargeted: { targeted in
            withAnimation(ProMotionSprings.hover) { isDropTargeted = targeted }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Gallery, \(media.count) media items")
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(
                isDropTargeted ? accent.opacity(0.8)
                    : (isSelected ? accent.opacity(0.55) : (isHovered ? DS.border : DS.borderSubtle)),
                lineWidth: isDropTargeted ? 1.6 : (isSelected ? 1.2 : 1)
            )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(DS.caption.weight(.medium))
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            Text("Gallery")
                .font(DS.subheadline.weight(.semibold))
                .foregroundStyle(DS.text)
            if !media.isEmpty {
                Text("\(media.count)")
                    .font(DS.caption.monospacedDigit())
                    .foregroundStyle(DS.textMuted)
            }
            Spacer(minLength: 0)
            if overflowCount > 0 {
                Button(isExpanded ? "Show less" : "Show all") {
                    withAnimation(ProMotionSprings.gentle) { isExpanded.toggle() }
                }
                .buttonStyle(.plain)
                .font(DS.caption.weight(.medium))
                .foregroundStyle(accent)
                .accessibilityLabel(isExpanded ? "Show fewer media" : "Show all media")
            }
            if compareSelection.count >= 2 {
                Button("Compare (\(compareSelection.count))") {
                    actions.onPresentCompare()
                }
                .buttonStyle(.plain)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(accent)
                .help("Compare the ⌘-selected media side by side")
                .accessibilityLabel("Compare \(compareSelection.count) selected media")
            }
            Button(action: actions.onAddMediaTapped) {
                Image(systemName: "plus")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .help("Add media from your library")
            .accessibilityLabel("Add media from your library")
        }
    }

    // MARK: - Empty state

    private var emptyPrompt: some View {
        Text("Drop swipes or images here, or paste a YouTube link")
            .font(DS.callout)
            .foregroundStyle(DS.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, DS.space12)
    }

    // MARK: - Tiles

    /// Non-lazy two-column grid: tile count is capped, and the masonry needs
    /// honest intrinsic heights from its children.
    private var tileGrid: some View {
        let columns = [GridItem(.flexible(), spacing: DS.space8), GridItem(.flexible(), spacing: DS.space8)]
        return LazyVGrid(columns: columns, spacing: DS.space8) {
            ForEach(visibleMedia) { item in
                ConceptMediaTile(
                    item: item,
                    atom: item.atomUUID.flatMap { atoms[$0] },
                    actions: actions,
                    isCompareSelected: compareSelection.contains(item.id)
                )
            }
            ForEach(0..<pendingCaptureCount, id: \.self) { _ in
                skeletonTile
            }
            ForEach(stagedAtoms, id: \.uuid) { staged in
                ConceptStagedMediaTile(
                    atom: staged,
                    accent: accent,
                    onAccept: { actions.onAcceptStagedMedia(staged.uuid) },
                    onReject: { actions.onRejectStagedMedia(staged.uuid) }
                )
            }
        }
    }

    /// A capture in flight — quiet shimmer, no chrome.
    private var skeletonTile: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(DS.glassSectionFill)
            .aspectRatio(1, contentMode: .fill)
            .overlay(ProgressView().controlSize(.small))
            .accessibilityLabel("Capturing media")
    }
}

// MARK: - Staged (ghost) tile

/// An attach_media candidate awaiting review: dashed accent border, sparkles
/// mark, and its own ✓/✗ — the media twin of the staged-insert ghost row.
struct ConceptStagedMediaTile: View {
    let atom: Atom
    let accent: Color
    let onAccept: () -> Void
    let onReject: () -> Void

    @State private var isHovered = false

    var body: some View {
        ZStack {
            thumbnail
                .aspectRatio(1, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipShape(.rect(cornerRadius: 8))
                .opacity(0.75)
            reviewControls
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(accent.opacity(0.7), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
        )
        .overlay(alignment: .topLeading) {
            Image(systemName: "sparkles")
                .font(.caption2)
                .foregroundStyle(.white)
                .padding(DS.space4)
                .background(accent.opacity(0.8), in: .circle)
                .padding(DS.space4)
                .accessibilityHidden(true)
        }
        .onHover { isHovered = $0 }
        .help(atom.title ?? "Suggested media")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggested media: \(atom.title ?? "Untitled"). Accept or dismiss.")
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = ConceptMediaThumbnailResolver.thumbnailURL(for: atom) {
            CachedAsyncImage(url: url, stableKey: "concept-staged-\(atom.uuid)") { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    Rectangle().fill(DS.glassSectionFill)
                @unknown default:
                    Rectangle().fill(DS.glassSectionFill)
                }
            }
        } else {
            Rectangle().fill(DS.glassSectionFill)
        }
    }

    private var reviewControls: some View {
        HStack(spacing: DS.space8) {
            Button(action: onAccept) {
                Image(systemName: "checkmark")
                    .font(DS.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(accent, in: .circle)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Add to gallery")
            .accessibilityLabel("Accept suggested media")
            Button(action: onReject) {
                Image(systemName: "xmark")
                    .font(DS.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(.black.opacity(0.5), in: .circle)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .accessibilityLabel("Dismiss suggested media")
        }
    }
}

// MARK: - Tile

struct ConceptMediaTile: View {
    let item: ConnectionMediaItem
    let atom: Atom?
    let actions: ConnectionWorkspaceActions
    /// Square by default (gallery); section strips use a shorter tile.
    var tileAspect: CGFloat = 1
    /// Queued for the compare strip (⌘-click toggles).
    var isCompareSelected: Bool = false

    @State private var isHovered = false

    var body: some View {
        Button {
            // ⌘-click queues for comparison instead of opening the Stage.
            if NSEvent.modifierFlags.contains(.command) {
                actions.onToggleCompareSelection(item.id)
            } else {
                actions.onOpenMedia(item.id)
            }
        } label: {
            thumbnail
                .aspectRatio(tileAspect, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipShape(.rect(cornerRadius: 8))
                .overlay(alignment: .bottomLeading) { platformBadge }
                .overlay(alignment: .center) { playBadge }
                .overlay(alignment: .topTrailing) { kindBadge }
                .overlay(alignment: .topLeading) { coverBadge }
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isCompareSelected ? DS.accent : (isHovered ? DS.border : DS.borderSubtle),
                            lineWidth: isCompareSelected ? 2 : 1
                        )
                )
                .contentShape(.rect(cornerRadius: 8))
                .scaleEffect(isHovered ? 1.02 : 1)
                .animation(ProMotionSprings.hover, value: isHovered)
        }
        .buttonStyle(.plain)
        // Sibling of the tile button (never inside its label) so the pill's
        // click can't double as an open.
        .imageSaveAffordance(saveRequest, isHovered: isHovered, inset: 8)
        .onHover { isHovered = $0 }
        .contextMenu { contextMenu }
        .help(tileTitle)
        .accessibilityLabel("Open \(tileTitle)")
    }

    /// Stills only: the owned original when this concept holds the file,
    /// else the cloud mirror, else the source atom's media.
    private var saveRequest: ImageSaveRequest? {
        guard item.kind == .image else { return nil }
        if let path = item.assetPath, !MediaAssetStore.isVideoPath(path), FileManager.default.fileExists(atPath: path) {
            return ImageSaveRequest(.file(URL(fileURLWithPath: path)), title: item.assetTitle ?? tileTitle)
        }
        if let remote = item.assetRemoteURL, let url = URL(string: remote) {
            return ImageSaveRequest(.remote(url), title: item.assetTitle ?? tileTitle)
        }
        if let atom, let url = ConceptMediaThumbnailResolver.thumbnailURL(for: atom) {
            return ImageSaveRequest(.remote(url), title: tileTitle)
        }
        return nil
    }

    private var tileTitle: String {
        if let caption = item.caption, !caption.isEmpty { return caption }
        if let atom, let title = atom.title, !title.isEmpty { return title }
        return item.assetTitle ?? "Media"
    }

    // MARK: Thumbnail

    @ViewBuilder
    private var thumbnail: some View {
        if let poster = item.thumbnailAssetPath {
            ConceptLocalThumbnail(path: poster)
        } else if let path = item.assetPath, !MediaAssetStore.isVideoPath(path) {
            ConceptLocalThumbnail(path: path)
        } else if let atom, let url = ConceptMediaThumbnailResolver.thumbnailURL(for: atom) {
            CachedAsyncImage(url: url, stableKey: ConceptMediaThumbnailResolver.stableKey(for: item)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(DS.glassSectionFill)
            .overlay(
                Image(systemName: item.kind == .video ? "video" : "photo")
                    .font(DS.title3)
                    .foregroundStyle(DS.textMuted)
                    .accessibilityHidden(true)
            )
    }

    // MARK: Badges

    @ViewBuilder
    private var playBadge: some View {
        if item.kind == .video {
            Image(systemName: "play.fill")
                .font(DS.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(DS.space8)
                .background(.black.opacity(0.45), in: .circle)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var kindBadge: some View {
        if item.kind == .carousel {
            Image(systemName: "square.stack.fill")
                .font(.caption2)
                .foregroundStyle(.white)
                .padding(DS.space4)
                .background(.black.opacity(0.45), in: .rect(cornerRadius: 4))
                .padding(DS.space4)
                .accessibilityHidden(true)
        } else if let duration = ConceptMediaThumbnailResolver.durationLabel(for: atom) {
            Text(duration)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, DS.space4)
                .padding(.vertical, 2)
                .background(.black.opacity(0.45), in: .rect(cornerRadius: 4))
                .padding(DS.space4)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var coverBadge: some View {
        if item.isCover {
            Image(systemName: "star.fill")
                .font(.caption2)
                .foregroundStyle(.white)
                .padding(DS.space4)
                .background(.black.opacity(0.45), in: .circle)
                .padding(DS.space4)
                .accessibilityLabel("Cover image")
        }
    }

    @ViewBuilder
    private var platformBadge: some View {
        if let glyph = platformGlyphName {
            Image(systemName: glyph)
                .font(.caption2)
                .foregroundStyle(.white)
                .padding(DS.space4)
                .background(.black.opacity(0.45), in: .circle)
                .padding(DS.space4)
                .accessibilityHidden(true)
        }
    }

    private var platformGlyphName: String? {
        switch atom?.richContent?.sourceType {
        case .youtube, .youtubeShort: return "play.rectangle.fill"
        case .instagram, .instagramReel, .instagramPost, .instagramCarousel: return "camera.fill"
        case .tiktok: return "music.note"
        case .twitter, .xPost: return "text.bubble.fill"
        default: return nil
        }
    }

    // MARK: Context menu

    @ViewBuilder
    private var contextMenu: some View {
        if let saveRequest {
            ImageSaveMenuItems(request: saveRequest)
            Divider()
        }
        Button("Open") { actions.onOpenMedia(item.id) }
        if let atomUUID = item.atomUUID {
            Button("Open as Pane") { actions.onOpenMediaAsPane(atomUUID) }
        }
        Divider()
        Button(item.isCover ? "Remove Cover" : "Set as Cover") {
            actions.onToggleMediaCover(item.id)
        }
        Menu("Show on Section") {
            Button("Gallery only") { actions.onAnchorMedia(item.id, nil) }
            Divider()
            ForEach(ConnectionSectionType.allCases.filter { $0 != .conceptName }, id: \.self) { type in
                Button {
                    actions.onAnchorMedia(item.id, type)
                } label: {
                    if item.anchorSection == type {
                        Label(type.displayName, systemImage: "checkmark")
                    } else {
                        Text(type.displayName)
                    }
                }
            }
        }
        Divider()
        Button("Detach", role: .destructive) { actions.onDetachMedia(item.id) }
    }
}
