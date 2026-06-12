import Combine
import Foundation

final class SocialDiscoveryStore: ObservableObject {
    @Published var query: SocialDiscoveryQuery
    @Published private(set) var posts: [SocialPostSnapshot]

    private let now: () -> Date

    init(
        query: SocialDiscoveryQuery = SocialDiscoveryQuery(),
        posts: [SocialPostSnapshot] = [],
        now: @escaping () -> Date = Date.init
    ) {
        self.query = query
        self.posts = posts
        self.now = now
    }

    var visiblePosts: [SocialPostSnapshot] {
        posts
            .filter(matchesQuery)
            .sorted(by: isRankedBefore)
    }

    func replacePosts(_ posts: [SocialPostSnapshot]) {
        self.posts = posts
    }

    private func matchesQuery(_ post: SocialPostSnapshot) -> Bool {
        if !query.platforms.isEmpty, !query.platforms.contains(post.platform) {
            return false
        }

        if !matchesFormat(post) {
            return false
        }

        if !query.languages.isEmpty {
            guard let language = post.detectedLanguage?.lowercased(), query.languages.contains(language) else {
                return false
            }
        }

        if !query.followerRange.contains(post.author.followerCount) {
            return false
        }

        if let minimumOutlierMultiplier = query.minimumOutlierMultiplier {
            guard let outlierMultiplier = post.derived.outlierMultiplier,
                  outlierMultiplier >= minimumOutlierMultiplier else {
                return false
            }
        }

        if !query.postedWindow.contains(post.publishedAt, now: now()) {
            return false
        }

        if !matchesTopicTerms(post) {
            return false
        }

        return matchesSearchText(post)
    }

    /// Any-match over the pillar's term set — a topic scope, not a search.
    private func matchesTopicTerms(_ post: SocialPostSnapshot) -> Bool {
        guard !query.topicTerms.isEmpty else { return true }

        let haystacks = [post.title, post.body]
            .compactMap { $0?.lowercased() }
        guard !haystacks.isEmpty else { return false }

        return query.topicTerms.contains { term in
            haystacks.contains { $0.localizedStandardContains(term) }
        }
    }

    private func matchesFormat(_ post: SocialPostSnapshot) -> Bool {
        switch post.platform {
        case .youtube: return query.youtubeFormat.matches(post.format)
        case .substack: return query.substackFormat.matches(post.format)
        case .instagram: return query.instagramFormat.matches(post.format)
        default: return true
        }
    }

    private func matchesSearchText(_ post: SocialPostSnapshot) -> Bool {
        let searchText = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !searchText.isEmpty else { return true }

        return [
            post.title,
            post.body,
            post.author.handle,
            post.author.displayName
        ]
        .compactMap { $0?.lowercased() }
        .contains { $0.localizedStandardContains(searchText) }
    }

    private func isRankedBefore(_ lhs: SocialPostSnapshot, _ rhs: SocialPostSnapshot) -> Bool {
        switch query.sort {
        case .highestOutlier:
            return compare(lhs, rhs, by: { $0.derived.outlierMultiplier ?? 0 }, descending: true)
        case .newest:
            return compare(lhs, rhs, by: { $0.publishedAt ?? .distantPast }, descending: true)
        case .mostViewed:
            return compare(lhs, rhs, by: { $0.metrics.views ?? 0 }, descending: true)
        case .mostLiked:
            return compare(lhs, rhs, by: { $0.metrics.likes ?? 0 }, descending: true)
        case .mostCommented:
            return compare(lhs, rhs, by: { $0.metrics.comments ?? 0 }, descending: true)
        case .mostShared:
            return compare(lhs, rhs, by: { $0.metrics.shares ?? $0.metrics.reposts ?? 0 }, descending: true)
        }
    }

    private func compare<T: Comparable>(
        _ lhs: SocialPostSnapshot,
        _ rhs: SocialPostSnapshot,
        by value: (SocialPostSnapshot) -> T,
        descending: Bool
    ) -> Bool {
        let leftValue = value(lhs)
        let rightValue = value(rhs)

        if leftValue != rightValue {
            return descending ? leftValue > rightValue : leftValue < rightValue
        }

        return tieBreak(lhs, rhs)
    }

    private func tieBreak(_ lhs: SocialPostSnapshot, _ rhs: SocialPostSnapshot) -> Bool {
        let leftReach = reach(lhs)
        let rightReach = reach(rhs)

        if leftReach != rightReach {
            return leftReach > rightReach
        }

        let leftDate = lhs.publishedAt ?? .distantPast
        let rightDate = rhs.publishedAt ?? .distantPast

        if leftDate != rightDate {
            return leftDate > rightDate
        }

        return lhs.id < rhs.id
    }

    private func reach(_ post: SocialPostSnapshot) -> Int {
        post.metrics.views ?? post.metrics.impressions ?? post.metrics.likes ?? 0
    }
}
