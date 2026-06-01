import Foundation

struct SocialDiscoveryQuery: Equatable, Sendable {
    var searchText: String
    var platforms: Set<SocialPlatform>
    var languages: Set<String>
    var youtubeFormat: YouTubeFormatFilter
    var substackFormat: SubstackFormatFilter
    var instagramFormat: InstagramFormatFilter
    var followerRange: SocialFollowerRange
    var minimumOutlierMultiplier: Double?
    var postedWindow: SocialPostedWindow
    var sort: SocialDiscoverySort
    var limit: Int

    init(
        searchText: String = "",
        platforms: Set<SocialPlatform> = [],
        languages: Set<String> = [],
        youtubeFormat: YouTubeFormatFilter = .all,
        substackFormat: SubstackFormatFilter = .all,
        instagramFormat: InstagramFormatFilter = .all,
        followerRange: SocialFollowerRange = .any,
        minimumOutlierMultiplier: Double? = nil,
        postedWindow: SocialPostedWindow = .lastThreeMonths,
        sort: SocialDiscoverySort = .highestOutlier,
        limit: Int = 1_000
    ) {
        self.searchText = searchText
        self.platforms = platforms
        self.languages = Set(languages.map { $0.lowercased() })
        self.youtubeFormat = youtubeFormat
        self.substackFormat = substackFormat
        self.instagramFormat = instagramFormat
        self.followerRange = followerRange
        self.minimumOutlierMultiplier = minimumOutlierMultiplier
        self.postedWindow = postedWindow
        self.sort = sort
        self.limit = limit
    }

    /// True when no per-platform format lens is narrowing the feed.
    var usesDefaultFormats: Bool {
        youtubeFormat == .all && substackFormat == .all && instagramFormat == .all
    }
}

/// Per-platform content-format lenses. Each maps a human label to the underlying
/// `SocialContentFormat` the providers emit, so the feed actually narrows.
enum YouTubeFormatFilter: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case videos
    case shorts
    case all

    var label: String {
        switch self {
        case .all: return "All"
        case .videos: return "Videos"
        case .shorts: return "Shorts"
        }
    }

    func matches(_ format: SocialContentFormat) -> Bool {
        switch self {
        case .all: return true
        case .videos: return format == .longVideo
        case .shorts: return format == .shortVideo
        }
    }
}

enum SubstackFormatFilter: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case articles
    case notes
    case all

    var label: String {
        switch self {
        case .all: return "All"
        case .articles: return "Articles"
        case .notes: return "Notes"
        }
    }

    func matches(_ format: SocialContentFormat) -> Bool {
        switch self {
        case .all: return true
        case .articles: return format == .newsletter
        case .notes: return format == .text
        }
    }
}

enum InstagramFormatFilter: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case reels
    case carousels
    case photos
    case all

    var label: String {
        switch self {
        case .all: return "All"
        case .reels: return "Reels"
        case .carousels: return "Carousels"
        case .photos: return "Photos"
        }
    }

    func matches(_ format: SocialContentFormat) -> Bool {
        switch self {
        case .all: return true
        case .reels: return format == .shortVideo
        case .carousels: return format == .carousel
        case .photos: return format == .image
        }
    }
}

enum SocialFollowerRange: Equatable, Sendable {
    case any
    case range(min: Int?, max: Int?)

    func contains(_ followerCount: Int?) -> Bool {
        switch self {
        case .any:
            return true
        case let .range(min, max):
            guard let followerCount else { return false }
            if let min, followerCount < min { return false }
            if let max, followerCount > max { return false }
            return true
        }
    }

    var minValue: Int? {
        if case let .range(min, _) = self { return min }
        return nil
    }

    var maxValue: Int? {
        if case let .range(_, max) = self { return max }
        return nil
    }

    /// Builds a range from optional bounds, collapsing to `.any` when both are nil.
    static func bounded(min: Int?, max: Int?) -> SocialFollowerRange {
        if min == nil && max == nil { return .any }
        return .range(min: min, max: max)
    }

    /// Parses loose follower input like "20k", "1.5m", or "50,000" into a count.
    /// Returns nil for empty/blank input (meaning "no bound").
    static func parseFollowerInput(_ raw: String) -> Int? {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: ",", with: "")
        guard !cleaned.isEmpty else { return nil }

        let multiplier: Double
        var numberPart = cleaned
        if let suffix = cleaned.last, "kmb".contains(suffix) {
            numberPart = String(cleaned.dropLast())
            switch suffix {
            case "k": multiplier = 1_000
            case "m": multiplier = 1_000_000
            default: multiplier = 1_000_000_000
            }
        } else {
            multiplier = 1
        }

        guard let value = Double(numberPart), value >= 0 else { return nil }
        return Int((value * multiplier).rounded())
    }
}

enum SocialPostedWindow: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case lastWeek
    case lastMonth
    case lastThreeMonths
    case lastYear
    case allTime

    func contains(_ publishedAt: Date?, now: Date) -> Bool {
        guard self != .allTime else { return true }
        guard let publishedAt else { return false }
        return publishedAt >= now.addingTimeInterval(-duration)
    }

    private var duration: TimeInterval {
        let day: TimeInterval = 24 * 60 * 60

        switch self {
        case .lastWeek:
            return 7 * day
        case .lastMonth:
            return 31 * day
        case .lastThreeMonths:
            return 92 * day
        case .lastYear:
            return 365 * day
        case .allTime:
            return .infinity
        }
    }
}

enum SocialDiscoverySort: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case highestOutlier
    case newest
    case mostViewed
    case mostLiked
    case mostCommented
    case mostShared
}
