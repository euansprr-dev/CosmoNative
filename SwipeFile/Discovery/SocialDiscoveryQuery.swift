import Foundation

struct SocialDiscoveryQuery: Equatable, Sendable {
    var searchText: String
    var platforms: Set<SocialPlatform>
    var languages: Set<String>
    var followerRange: SocialFollowerRange
    var minimumOutlierMultiplier: Double?
    var postedWindow: SocialPostedWindow
    var sort: SocialDiscoverySort
    var limit: Int

    init(
        searchText: String = "",
        platforms: Set<SocialPlatform> = [],
        languages: Set<String> = [],
        followerRange: SocialFollowerRange = .any,
        minimumOutlierMultiplier: Double? = nil,
        postedWindow: SocialPostedWindow = .lastThreeMonths,
        sort: SocialDiscoverySort = .highestOutlier,
        limit: Int = 1_000
    ) {
        self.searchText = searchText
        self.platforms = platforms
        self.languages = Set(languages.map { $0.lowercased() })
        self.followerRange = followerRange
        self.minimumOutlierMultiplier = minimumOutlierMultiplier
        self.postedWindow = postedWindow
        self.sort = sort
        self.limit = limit
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
