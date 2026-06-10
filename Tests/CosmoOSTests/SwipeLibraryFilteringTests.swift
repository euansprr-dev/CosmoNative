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

    private func makeItem(
        atomUUID: String = UUID().uuidString,
        title: String,
        hookScore: Double? = nil,
        hookType: SwipeHookType? = nil,
        narrative: NarrativeStyle? = nil,
        format: ContentFormat? = nil,
        creator: String? = nil,
        createdAt: String = "2026-05-01T00:00:00Z"
    ) -> SwipeGalleryItem {
        SwipeGalleryItem(
            atomUUID: atomUUID,
            title: title,
            hookText: title,
            hookScore: hookScore,
            hookType: hookType,
            createdAt: createdAt,
            primaryNarrative: narrative,
            swipeContentFormat: format,
            creatorName: creator
        )
    }
}
