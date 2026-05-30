import XCTest
@testable import CosmoOS

final class SocialDiscoveryCoreTests: XCTestCase {
    func testResolvesSupportedProfileURLsWithoutGuessingPlatform() throws {
        XCTAssertEqual(
            SocialPlatformResolver.resolve(input: "https://www.instagram.com/alexhormozi/"),
            SocialPlatformIdentity(platform: .instagram, handle: "alexhormozi", profileURL: URL(string: "https://www.instagram.com/alexhormozi/"))
        )
        XCTAssertEqual(
            SocialPlatformResolver.resolve(input: "https://www.youtube.com/@mkbhd"),
            SocialPlatformIdentity(platform: .youtube, handle: "mkbhd", profileURL: URL(string: "https://www.youtube.com/@mkbhd"))
        )
        XCTAssertEqual(
            SocialPlatformResolver.resolve(input: "https://x.com/naval/status/123"),
            SocialPlatformIdentity(platform: .x, handle: "naval", profileURL: URL(string: "https://x.com/naval/status/123"))
        )
        XCTAssertEqual(
            SocialPlatformResolver.resolve(input: "https://paulgraham.substack.com/p/how-to-do-great-work"),
            SocialPlatformIdentity(platform: .substack, handle: "paulgraham", profileURL: URL(string: "https://paulgraham.substack.com/p/how-to-do-great-work"))
        )
    }

    func testResolvesPlatformPrefixedHandlesAndRejectsAmbiguousPlainHandles() {
        XCTAssertEqual(
            SocialPlatformResolver.resolve(input: "linkedin:@sahilbloom"),
            SocialPlatformIdentity(platform: .linkedin, handle: "sahilbloom", profileURL: nil)
        )
        XCTAssertNil(SocialPlatformResolver.resolve(input: "@sahilbloom"))
        XCTAssertNil(SocialPlatformResolver.resolve(input: "sahilbloom"))
    }

    func testDiscoveryRemoteStoreNormalizesBareRailwayDomains() {
        XCTAssertEqual(
            SocialDiscoveryRemoteStore.normalizedDiscoveryAPIBaseURL("cosmonative-production.up.railway.app"),
            "https://cosmonative-production.up.railway.app"
        )
        XCTAssertEqual(
            SocialDiscoveryRemoteStore.normalizedDiscoveryAPIBaseURL("https://cosmonative-production.up.railway.app/"),
            "https://cosmonative-production.up.railway.app"
        )
    }

    func testProviderRegistryChoosesProviderByPlatformAndCapability() {
        let registry = SocialProviderRegistry(providers: [
            StubSocialProvider(id: "youtube-official", platforms: [.youtube], capabilities: [.creatorLookup, .keywordDiscovery]),
            StubSocialProvider(id: "bright-data", platforms: Set(SocialPlatform.allCases), capabilities: [.creatorLookup, .creatorCatalog, .engagementMetrics])
        ])

        XCTAssertEqual(
            registry.provider(for: .youtube, requiring: [.keywordDiscovery])?.id,
            "youtube-official"
        )
        XCTAssertEqual(
            registry.provider(for: .instagram, requiring: [.creatorCatalog, .engagementMetrics])?.id,
            "bright-data"
        )
        XCTAssertNil(registry.provider(for: .substack, requiring: [.nativeTranscript]))
    }

    func testOutlierScoreUsesMedianComparableReachAndIgnoresCurrentPost() {
        let current = SocialPostSnapshot.fixture(
            id: "current",
            platform: .instagram,
            format: .shortVideo,
            metrics: .init(views: 1_600_000, likes: 120_000, comments: 1_200, shares: 900, saves: nil, reposts: nil, impressions: nil)
        )
        let baseline = [
            SocialPostSnapshot.fixture(id: "a", platform: .instagram, format: .shortVideo, metrics: .init(views: 100_000)),
            SocialPostSnapshot.fixture(id: "b", platform: .instagram, format: .shortVideo, metrics: .init(views: 95_000)),
            SocialPostSnapshot.fixture(id: "current", platform: .instagram, format: .shortVideo, metrics: .init(views: 9_999_999)),
            SocialPostSnapshot.fixture(id: "c", platform: .instagram, format: .shortVideo, metrics: .init(views: 102_000)),
            SocialPostSnapshot.fixture(id: "d", platform: .instagram, format: .shortVideo, metrics: .init(views: 98_000)),
            SocialPostSnapshot.fixture(id: "e", platform: .instagram, format: .shortVideo, metrics: .init(views: 105_000)),
            SocialPostSnapshot.fixture(id: "wrong-platform", platform: .youtube, format: .shortVideo, metrics: .init(views: 1))
        ]

        let result = SocialOutlierScorer.score(post: current, creatorPosts: baseline)

        XCTAssertEqual(result.baselineReach, 100_000)
        XCTAssertEqual(result.comparablePostCount, 5)
        XCTAssertEqual(try XCTUnwrap(result.multiplier), 16.0, accuracy: 0.001)
        XCTAssertEqual(result.grade, .a)
    }

    func testOutlierScoreRequiresFiveComparablePostsForConfidentGrade() {
        let current = SocialPostSnapshot.fixture(
            id: "current",
            platform: .youtube,
            format: .longVideo,
            metrics: .init(views: 500_000)
        )
        let baseline = [
            SocialPostSnapshot.fixture(id: "a", platform: .youtube, format: .longVideo, metrics: .init(views: 100_000)),
            SocialPostSnapshot.fixture(id: "b", platform: .youtube, format: .longVideo, metrics: .init(views: 100_000)),
            SocialPostSnapshot.fixture(id: "c", platform: .youtube, format: .longVideo, metrics: .init(views: 100_000)),
            SocialPostSnapshot.fixture(id: "d", platform: .youtube, format: .longVideo, metrics: .init(views: 100_000))
        ]

        let result = SocialOutlierScorer.score(post: current, creatorPosts: baseline)

        XCTAssertNil(result.baselineReach)
        XCTAssertEqual(result.comparablePostCount, 4)
        XCTAssertNil(result.multiplier)
        XCTAssertEqual(result.grade, .insufficientData)
    }
}

private struct StubSocialProvider: SocialDiscoveryProvider {
    let id: String
    let platforms: Set<SocialPlatform>
    let capabilities: Set<SocialProviderCapability>

    func supports(platform: SocialPlatform) -> Bool {
        platforms.contains(platform)
    }
}

private extension SocialPostSnapshot {
    static func fixture(
        id: String,
        platform: SocialPlatform,
        format: SocialContentFormat,
        metrics: SocialEngagementMetrics
    ) -> SocialPostSnapshot {
        SocialPostSnapshot(
            id: id,
            platform: platform,
            provider: "fixture",
            providerPostID: id,
            canonicalURL: URL(string: "https://example.com/\(id)")!,
            title: nil,
            body: "fixture body",
            media: [],
            author: .init(platformID: "creator-1", handle: "creator", displayName: "Creator", avatarURL: nil, followerCount: 100_000),
            publishedAt: Date(timeIntervalSince1970: 1_800_000_000),
            detectedLanguage: "en",
            format: format,
            metrics: metrics,
            derived: .empty,
            transcriptState: .none,
            saveState: .unsaved,
            rawProviderPayload: nil
        )
    }
}
