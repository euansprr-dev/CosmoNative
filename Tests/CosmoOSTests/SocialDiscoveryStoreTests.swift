import XCTest
@testable import CosmoOS

final class SocialDiscoveryStoreTests: XCTestCase {
    func testQueryDefaultsMatchHighSignalDiscoveryFeed() {
        let query = SocialDiscoveryQuery()

        XCTAssertTrue(query.platforms.isEmpty)
        XCTAssertTrue(query.languages.isEmpty)
        XCTAssertEqual(query.followerRange, .any)
        XCTAssertEqual(query.minimumOutlierMultiplier, 10)
        XCTAssertEqual(query.postedWindow, .lastThreeMonths)
        XCTAssertEqual(query.sort, .highestOutlier)
    }

    func testStoreFiltersByPlatformLanguageFollowersOutlierAndPostedWindow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = SocialDiscoveryStore(now: { now })

        let matching = SocialPostSnapshot.fixture(
            id: "matching",
            platform: .instagram,
            language: "en",
            followerCount: 150_000,
            publishedAt: now.addingTimeInterval(-10 * 24 * 60 * 60),
            metrics: .init(views: 1_200_000, likes: 90_000),
            derived: .init(outlierMultiplier: 21, outlierGrade: .s, engagementRate: 0.08)
        )

        store.replacePosts([
            matching,
            .fixture(id: "wrong-platform", platform: .youtube, language: "en", followerCount: 150_000, publishedAt: now, derived: .init(outlierMultiplier: 22, outlierGrade: .s, engagementRate: nil)),
            .fixture(id: "wrong-language", platform: .instagram, language: "es", followerCount: 150_000, publishedAt: now, derived: .init(outlierMultiplier: 22, outlierGrade: .s, engagementRate: nil)),
            .fixture(id: "too-small", platform: .instagram, language: "en", followerCount: 5_000, publishedAt: now, derived: .init(outlierMultiplier: 22, outlierGrade: .s, engagementRate: nil)),
            .fixture(id: "not-outlier", platform: .instagram, language: "en", followerCount: 150_000, publishedAt: now, derived: .init(outlierMultiplier: 4, outlierGrade: .c, engagementRate: nil)),
            .fixture(id: "too-old", platform: .instagram, language: "en", followerCount: 150_000, publishedAt: now.addingTimeInterval(-120 * 24 * 60 * 60), derived: .init(outlierMultiplier: 22, outlierGrade: .s, engagementRate: nil))
        ])

        store.query = SocialDiscoveryQuery(
            searchText: "",
            platforms: [.instagram],
            languages: ["en"],
            followerRange: .range(min: 100_000, max: 200_000),
            minimumOutlierMultiplier: 10,
            postedWindow: .lastThreeMonths,
            sort: .highestOutlier
        )

        XCTAssertEqual(store.visiblePosts.map(\.id), ["matching"])
    }

    func testStoreSortsByOutlierThenReachForStableDiscoveryRanking() {
        let store = SocialDiscoveryStore(now: { Date(timeIntervalSince1970: 1_800_000_000) })

        store.query = SocialDiscoveryQuery(postedWindow: .allTime, sort: .highestOutlier)
        store.replacePosts([
            .fixture(id: "lower-outlier", metrics: .init(views: 2_000_000), derived: .init(outlierMultiplier: 15, outlierGrade: .a, engagementRate: nil)),
            .fixture(id: "same-outlier-more-reach", metrics: .init(views: 3_000_000), derived: .init(outlierMultiplier: 20, outlierGrade: .s, engagementRate: nil)),
            .fixture(id: "same-outlier-less-reach", metrics: .init(views: 1_000_000), derived: .init(outlierMultiplier: 20, outlierGrade: .s, engagementRate: nil))
        ])

        XCTAssertEqual(
            store.visiblePosts.map(\.id),
            ["same-outlier-more-reach", "same-outlier-less-reach", "lower-outlier"]
        )
    }
}

private extension SocialPostSnapshot {
    static func fixture(
        id: String,
        platform: SocialPlatform = .instagram,
        language: String? = "en",
        followerCount: Int? = 100_000,
        publishedAt: Date? = Date(timeIntervalSince1970: 1_800_000_000),
        metrics: SocialEngagementMetrics = .init(views: 100_000, likes: 10_000),
        derived: SocialDerivedMetrics = .empty
    ) -> SocialPostSnapshot {
        SocialPostSnapshot(
            id: id,
            platform: platform,
            provider: "fixture",
            providerPostID: id,
            canonicalURL: URL(string: "https://example.com/\(id)")!,
            title: nil,
            body: "fixture \(id)",
            media: [],
            author: .init(platformID: "creator-\(id)", handle: "creator_\(id)", displayName: "Creator \(id)", avatarURL: nil, followerCount: followerCount),
            publishedAt: publishedAt,
            detectedLanguage: language,
            format: .shortVideo,
            metrics: metrics,
            derived: derived,
            transcriptState: .none,
            saveState: .unsaved,
            rawProviderPayload: nil
        )
    }
}
