import XCTest
@testable import CosmoOS

final class SwipeLibraryFilteringTests: XCTestCase {
    func testDiscoveryFilterPresentationMatchesRequestedDefaultControls() {
        let query = SocialDiscoveryQuery()

        XCTAssertEqual(
            SwipeDiscoveryFilterPresentation.primaryPlatforms,
            [.x, .youtube, .substack, .instagram, .tiktok, .linkedin]
        )
        XCTAssertEqual(SwipeDiscoveryFilterPresentation.minimumOutlierOptions, [nil, 3, 5, 10, 20])
        XCTAssertEqual(SwipeDiscoveryFilterPresentation.summary(for: query), "All · Last 3 months · Any score")
        XCTAssertEqual(
            SwipeDiscoveryFilterPresentation.summary(for: SocialDiscoveryQuery(minimumOutlierMultiplier: 10)),
            "All · Last 3 months · 10×"
        )
    }

    func testDiscoverySidebarSectionsAreDistinctDestinations() {
        XCTAssertEqual(
            SwipeDiscoverySectionSelection.allCases.map(\.title),
            ["Discover", "Creators"]
        )
    }

    func testFearHooksPresetMatchesNarrativeHookTypesAndWarningKeywords() {
        let items = [
            makeItem(title: "Stop making this client mistake", hookType: .question, narrative: nil),
            makeItem(title: "Contrarian growth lesson", hookType: .contrarian, narrative: nil),
            makeItem(title: "A calm tutorial", hookType: .howTo, narrative: nil),
            makeItem(title: "Fear story", hookType: .story, narrative: .fearMongering),
        ]

        var filters = SwipeLibraryFilterState()
        filters.smartPreset = .fearHooks

        XCTAssertEqual(
            SwipeLibraryFiltering.filteredItems(from: items, filters: filters, query: "", sortMode: .recent).map(\.title),
            ["Stop making this client mistake", "Contrarian growth lesson", "Fear story"]
        )
    }

    func testSearchAndFiltersCombineConjunctively() {
        let items = [
            makeItem(title: "Thread fear hook", hookType: .boldClaim, format: .thread, creator: "Ava"),
            makeItem(title: "Reel fear hook", hookType: .boldClaim, format: .reel, creator: "Ava"),
            makeItem(title: "Thread curiosity hook", hookType: .curiosityGap, format: .thread, creator: "Ben"),
        ]

        var filters = SwipeLibraryFilterState()
        filters.formats = [.thread]
        filters.hookTypes = [.boldClaim]

        XCTAssertEqual(
            SwipeLibraryFiltering.filteredItems(from: items, filters: filters, query: "fear", sortMode: .recent).map(\.title),
            ["Thread fear hook"]
        )
    }

    func testShelvesAreDeterministicAndLimited() {
        let items = (0..<8).map { index in
            makeItem(
                title: "Swipe \(index)",
                hookScore: Double(10 - index),
                createdAt: "2026-05-\(String(format: "%02d", index + 1))T00:00:00Z"
            )
        }

        let shelves = SwipeLibraryFiltering.shelves(from: items, limit: 4)

        XCTAssertEqual(shelves.first?.id, .recentlyAdded)
        XCTAssertEqual(shelves.first?.items.count, 4)
        XCTAssertEqual(shelves.first?.items.first?.title, "Swipe 7")
        XCTAssertEqual(shelves.map(\.id), [.recentlyAdded, .highPerforming, .hooksToTry])
    }

    func testVisibleItemsIdentityChangesOnlyWhenVisibleIDsChange() {
        let first = makeItem(atomUUID: "a", title: "A")
        let second = makeItem(atomUUID: "b", title: "B")
        let sameIDsWithDifferentTitles = [
            makeItem(atomUUID: "a", title: "A updated"),
            makeItem(atomUUID: "b", title: "B updated")
        ]

        XCTAssertEqual(
            SwipeLibraryVisibleItemsIdentity(items: [first, second]),
            SwipeLibraryVisibleItemsIdentity(items: sameIDsWithDifferentTitles)
        )
        XCTAssertNotEqual(
            SwipeLibraryVisibleItemsIdentity(items: [first, second]),
            SwipeLibraryVisibleItemsIdentity(items: [second, first])
        )
    }

    func testScopeComposesWithFiltersAndQuery() {
        let items = [
            makeItem(atomUUID: "a", title: "Fear thread on boards", hookType: .boldClaim, format: .thread, boardIDs: ["thread-hooks"]),
            makeItem(atomUUID: "b", title: "Fear thread off boards", hookType: .boldClaim, format: .thread),
            makeItem(atomUUID: "c", title: "Calm reel on boards", hookType: .howTo, format: .reel, boardIDs: ["thread-hooks"]),
        ]

        var filters = SwipeLibraryFilterState()
        filters.formats = [.thread]

        XCTAssertEqual(
            SwipeLibraryFiltering.filteredItems(
                from: items,
                scope: .board("thread-hooks"),
                filters: filters,
                query: "fear",
                sortMode: .recent
            ).map(\.atomUUID),
            ["a"]
        )
    }

    func testScopeDoesNotLeakIntoFilterState() {
        let items = [
            makeItem(atomUUID: "studied", title: "Studied", isStudied: true),
            makeItem(atomUUID: "fresh", title: "Fresh"),
        ]

        let unstudied = SwipeLibraryFiltering.filteredItems(
            from: items,
            scope: .unstudied,
            filters: SwipeLibraryFilterState(),
            query: "",
            sortMode: .recent
        )
        XCTAssertEqual(unstudied.map(\.atomUUID), ["fresh"])

        // Same filter state, scope back to all: nothing was mutated by scoping.
        let all = SwipeLibraryFiltering.filteredItems(
            from: items,
            scope: .all,
            filters: SwipeLibraryFilterState(),
            query: "",
            sortMode: .recent
        )
        XCTAssertEqual(all.count, 2)
    }

    func testHighHookScoreScope() {
        let items = [
            makeItem(atomUUID: "high", title: "High", hookScore: 8.4),
            makeItem(atomUUID: "low", title: "Low", hookScore: 5.0),
        ]
        XCTAssertEqual(
            SwipeLibraryFiltering.filteredItems(
                from: items, scope: .highHookScore, filters: SwipeLibraryFilterState(), query: "", sortMode: .recent
            ).map(\.atomUUID),
            ["high"]
        )
    }

    func testTopicTermsScopeDiscoveryFeed() {
        let now = Date()
        let posts = [
            makePost(id: "a", body: "How deep work changed my productivity forever", publishedAt: now),
            makePost(id: "b", body: "My favourite pasta recipe", publishedAt: now),
            makePost(id: "c", title: "Dopamine and the psychology of attention", body: nil, publishedAt: now),
        ]

        var query = SocialDiscoveryQuery()
        query.topicTerms = SwipeDiscoverPillar.productivity.searchTerms

        let store = SocialDiscoveryStore(query: query, posts: posts, now: { now })
        XCTAssertEqual(store.visiblePosts.map(\.id), ["a"])

        query.topicTerms = []
        let unscoped = SocialDiscoveryStore(query: query, posts: posts, now: { now })
        XCTAssertEqual(unscoped.visiblePosts.count, 3)
    }

    private func makePost(
        id: String,
        title: String? = nil,
        body: String?,
        publishedAt: Date
    ) -> SocialPostSnapshot {
        SocialPostSnapshot(
            id: id,
            platform: .youtube,
            provider: "test",
            providerPostID: id,
            canonicalURL: URL(string: "https://example.com/\(id)")!,
            title: title,
            body: body,
            media: [],
            author: SocialCreatorSnapshot(
                platformID: "creator-\(id)",
                handle: "creator",
                displayName: "Creator",
                avatarURL: nil,
                followerCount: 10_000
            ),
            publishedAt: publishedAt,
            detectedLanguage: nil,
            format: .longVideo,
            metrics: SocialEngagementMetrics(views: 100, likes: 10, comments: 1, shares: nil, saves: nil, reposts: nil, impressions: nil),
            derived: SocialDerivedMetrics(outlierMultiplier: 3, outlierGrade: .a, engagementRate: nil),
            transcriptState: .none,
            saveState: .unsaved,
            rawProviderPayload: nil
        )
    }

    private func makeItem(
        atomUUID: String = UUID().uuidString,
        title: String,
        hookScore: Double? = nil,
        hookType: SwipeHookType? = nil,
        narrative: NarrativeStyle? = nil,
        format: ContentFormat? = nil,
        creator: String? = nil,
        createdAt: String = "2026-05-01T00:00:00Z",
        isStudied: Bool = false,
        boardIDs: [String] = []
    ) -> SwipeGalleryItem {
        SwipeGalleryItem(
            atomUUID: atomUUID,
            title: title,
            hookText: title,
            hookScore: hookScore,
            hookType: hookType,
            createdAt: createdAt,
            isStudied: isStudied,
            primaryNarrative: narrative,
            swipeContentFormat: format,
            creatorName: creator,
            boardIDs: boardIDs
        )
    }
}
