import SwiftUI

// MARK: - Aspect & processing

enum SwipeCardAspect: Equatable {
    /// 16:9 — YouTube videos, generic link previews.
    case wide
    /// 4:5 — Instagram posts and carousels.
    case portrait
    /// 9:16 (height-capped) — reels, shorts, TikTok.
    case vertical
    /// Text-only posts (X, Threads, Substack notes) rendered as a paper well.
    case paper
}

enum SwipeCardProcessing: Equatable {
    case ready
    case pending
    case failed
}

// MARK: - Model

/// Plain display model for `SwipeCard`. Both the library (`SwipeGalleryItem`) and
/// Discover (`SocialPostSnapshot`) adapt into this, so the card view and the
/// masonry height math have exactly one source of truth.
struct SwipeCardModel: Identifiable, Equatable {
    let id: String
    let mediaURL: URL?
    let mediaStableKey: String?
    var aspect: SwipeCardAspect
    let paperText: String?
    let hookText: String
    let creatorLine: String?
    let platformGlyph: String?
    /// Raw platform key ("instagram_reel", "youtube", …) — drives the honest
    /// vector mark (SwipePlatformGlyph); platformGlyph stays the SF fallback.
    var platformKey: String? = nil
    let platformColor: Color?
    let outlierLabel: String?
    let durationLabel: String?
    let scoreLabel: String?
    let scoreTint: Color?
    let metricsLine: String?
    let ageLabel: String?
    let isUnstudied: Bool
    let processing: SwipeCardProcessing
    /// What kind of artifact this is. Drives the honest aspect and the unit
    /// badge; `.post` behaves exactly as it did before the artifact spine.
    var kind: SwipeKind = .post
    /// What this swipe IS to the collector — the space it files under.
    var genre: SwipeGenre = .post
    /// True only in MIXED contexts (cross-genre search results, board detail):
    /// the card names its space. Inside a genre room the chip would repeat the
    /// masthead, so rooms leave this false.
    var showsGenreChip = false
    /// "14 sections" / "3 images" — the badge that tells you a card is a whole
    /// page or a set, not a single image. Nil for posts and single units.
    var unitBadge: String?
    /// Flow cards only: member thumbnails, step order, max 4 — the card's
    /// artwork becomes a step mosaic. Filled by the VIEW MODEL after the item
    /// map (members are sibling library rows; an item-local adapter can't see
    /// them). Empty ⇒ the card falls back to its own media/paper well.
    var mosaicURLs: [URL] = []
    var boardIDs: Set<String> = []
    /// Recency shelves drop the footer hook line — the thumbnail already
    /// carries the hook, so printing it twice reads as a stutter. Paper
    /// cards ignore this (their text IS the media).
    var showsHookLine = true

    // MARK: Height math (single source of truth for the masonry)

    static let verticalHeightCap: CGFloat = 420
    static let paperWellHeight: CGFloat = 150

    func mediaHeight(forWidth width: CGFloat) -> CGFloat {
        switch aspect {
        case .wide: return (width * 9 / 16).rounded()
        case .portrait: return (width * 5 / 4).rounded()
        case .vertical: return min((width * 16 / 9).rounded(), Self.verticalHeightCap)
        case .paper: return Self.paperWellHeight
        }
    }

    /// Paper cards carry their text in the well, so the footer is meta-only.
    /// Heights are the exact sum of the footer's fixed slots — see SwipeCardFooter.
    var footerHeight: CGFloat {
        if aspect == .paper || !showsHookLine { return metricsLine == nil ? 34 : 51 }
        return metricsLine == nil ? 74 : 91
    }

    func height(forWidth width: CGFloat) -> CGFloat {
        mediaHeight(forWidth: width) + footerHeight
    }

    /// Uniform-grid variant: every media well becomes 4:5 (center-cropped by the
    /// card's `scaledToFill`), so rows and footers align — the App Store rhythm.
    /// Paper posts keep their well; the honest aspect lives in the quick look.
    func poster() -> SwipeCardModel {
        var copy = self
        if copy.aspect != .paper {
            copy.aspect = .portrait
        }
        return copy
    }

    /// Shelf variant: no footer hook line (see `showsHookLine`).
    func hookless() -> SwipeCardModel {
        var copy = self
        copy.showsHookLine = false
        return copy
    }
}

// MARK: - Library adapter

extension SwipeCardModel {
    init(item: SwipeGalleryItem) {
        let platform = SocialPlatform.fromLibraryKey(item.platform)
        let mediaURL = item.thumbnailUrl.flatMap(URL.init(string:))

        // ASPECT TWINS: this switch and iOS `Atom.cardAspect`
        // (CosmoCoreKit/Sources/Models/SwipeCapture.swift) change together.
        let aspect: SwipeCardAspect
        switch item.kind {
        case .frame:
            // A screenshot's honest shape is its own. We do not know it until
            // the image loads, so the card claims the portrait slot — the
            // safest bet for phone screenshots, which is most of them — and
            // the media well letterboxes anything wider onto the warm fill.
            aspect = mediaURL == nil ? .paper : .portrait
        case .page:
            // A page is tall by definition; the card shows its hero slice.
            aspect = mediaURL == nil ? .paper : .portrait
        case .flow:
            // A flow's artwork is a mosaic of its steps — square reads as a
            // container rather than as any one member.
            aspect = mediaURL == nil ? .paper : .portrait
        case .note:
            aspect = .paper
        case .post:
            if mediaURL == nil && item.instagramId == nil {
                aspect = .paper
            } else {
                switch item.platform {
                case "youtube":
                    aspect = .wide
                case "youtubeShort", "youtube_short", "instagramReel", "instagram_reel", "tiktok":
                    aspect = .vertical
                case "instagram", "instagramPost", "instagram_post", "instagramCarousel", "instagram_carousel":
                    aspect = .portrait
                default:
                    aspect = mediaURL == nil ? .paper : .wide
                }
            }
        }

        let processing: SwipeCardProcessing
        switch item.processingStatus {
        case nil, "complete": processing = .ready
        // Retired swipes read as failed, not pending — nothing is coming, so a
        // pending spinner would promise work that will never happen.
        case "extraction_failed", SwipeProcessingService.statusNeedsManualRetry: processing = .failed
        default: processing = .pending
        }

        let hook = (item.hookText?.isEmpty == false ? item.hookText : nil) ?? item.title

        self.init(
            id: item.id,
            mediaURL: mediaURL,
            mediaStableKey: item.instagramId.map { "ig-carousel-\($0)-0" },
            aspect: aspect,
            paperText: aspect == .paper ? hook : nil,
            hookText: hook,
            creatorLine: item.creatorName ?? item.author,
            platformGlyph: platform?.iconName,
            platformKey: item.platform,
            platformColor: platform?.swipeBrandColor,
            outlierLabel: nil,
            durationLabel: item.duration.map(SwipeFormatting.duration(seconds:)),
            scoreLabel: item.hookScore.map { String(format: "%.1f", $0) },
            scoreTint: nil,
            metricsLine: nil,
            ageLabel: item.createdAtDate.map { SwipeFormatting.compactAge(from: $0) },
            isUnstudied: !item.isStudied,
            processing: processing,
            kind: item.kind,
            genre: item.genre,
            // A single-image frame needs no badge — the card IS the image. The
            // badge exists to say "there is more here than you can see".
            unitBadge: item.unitCount > 1 ? item.kind.unitCountLabel(item.unitCount) : nil,
            boardIDs: Set(item.boardIDs)
        )
    }
}

// MARK: - Discover adapter

extension SwipeCardModel {
    init(post: SocialPostSnapshot) {
        let thumbnail = post.media.first(where: { $0.kind == .thumbnail || $0.kind == .image })

        let aspect: SwipeCardAspect
        if thumbnail == nil {
            aspect = .paper
        } else {
            switch post.platform {
            case .youtube: aspect = post.format == .shortVideo ? .vertical : .wide
            case .instagram: aspect = post.format == .shortVideo ? .vertical : .portrait
            case .tiktok: aspect = .vertical
            default: aspect = post.format == .shortVideo ? .vertical : .wide
            }
        }

        let text = post.body ?? post.title ?? post.canonicalURL.absoluteString

        var metrics: [String] = []
        if let views = post.metrics.views { metrics.append("\(SwipeFormatting.count(views)) views") }
        if let likes = post.metrics.likes { metrics.append("\(SwipeFormatting.count(likes)) likes") }
        if metrics.isEmpty, let comments = post.metrics.comments {
            metrics.append("\(SwipeFormatting.count(comments)) comments")
        }

        let multiplier = post.derived.outlierMultiplier

        self.init(
            id: post.id,
            mediaURL: thumbnail?.url,
            mediaStableKey: post.providerPostID.isEmpty ? nil : "\(post.platform.rawValue)-\(post.providerPostID)",
            aspect: aspect,
            paperText: aspect == .paper ? text : nil,
            hookText: text,
            creatorLine: post.author.displayName,
            platformGlyph: post.platform.iconName,
            platformKey: post.platform.rawValue,
            platformColor: post.platform.swipeBrandColor,
            outlierLabel: multiplier.flatMap { $0 >= 2 ? "\(Int($0.rounded()))×" : nil },
            durationLabel: thumbnail?.duration.map { SwipeFormatting.duration(seconds: Int($0)) },
            scoreLabel: nil,
            scoreTint: nil,
            metricsLine: aspect == .paper ? nil : (metrics.isEmpty ? nil : metrics.joined(separator: " · ")),
            ageLabel: post.publishedAt.map { SwipeFormatting.compactAge(from: $0) },
            isUnstudied: false,
            processing: .ready
        )
    }
}
