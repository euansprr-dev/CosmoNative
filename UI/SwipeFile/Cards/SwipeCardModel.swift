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
    let aspect: SwipeCardAspect
    let paperText: String?
    let hookText: String
    let creatorLine: String?
    let platformGlyph: String?
    let platformColor: Color?
    let outlierLabel: String?
    let durationLabel: String?
    let scoreLabel: String?
    let scoreTint: Color?
    let metricsLine: String?
    let ageLabel: String?
    let isUnstudied: Bool
    let processing: SwipeCardProcessing
    var boardIDs: Set<String> = []

    // MARK: Height math (single source of truth for the masonry)

    static let verticalHeightCap: CGFloat = 560
    static let paperWellHeight: CGFloat = 170

    func mediaHeight(forWidth width: CGFloat) -> CGFloat {
        switch aspect {
        case .wide: return (width * 9 / 16).rounded()
        case .portrait: return (width * 5 / 4).rounded()
        case .vertical: return min((width * 16 / 9).rounded(), Self.verticalHeightCap)
        case .paper: return Self.paperWellHeight
        }
    }

    /// Paper cards carry their text in the well, so the footer is meta-only.
    var footerHeight: CGFloat {
        if aspect == .paper { return 40 }
        return metricsLine == nil ? 78 : 98
    }

    func height(forWidth width: CGFloat) -> CGFloat {
        mediaHeight(forWidth: width) + footerHeight
    }
}

// MARK: - Library adapter

extension SwipeCardModel {
    init(item: SwipeGalleryItem) {
        let platform = SocialPlatform.fromLibraryKey(item.platform)
        let mediaURL = item.thumbnailUrl.flatMap(URL.init(string:))

        let aspect: SwipeCardAspect
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

        let processing: SwipeCardProcessing
        switch item.processingStatus {
        case nil, "complete": processing = .ready
        case "extraction_failed": processing = .failed
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
            platformColor: platform?.swipeBrandColor,
            outlierLabel: nil,
            durationLabel: item.duration.map(SwipeFormatting.duration(seconds:)),
            scoreLabel: item.hookScore.map { String(format: "%.1f", $0) },
            scoreTint: item.hookScore != nil ? item.scoreColor : nil,
            metricsLine: nil,
            ageLabel: ISO8601.date(from: item.createdAt).map { SwipeFormatting.compactAge(from: $0) },
            isUnstudied: !item.isStudied,
            processing: processing,
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
