import XCTest
@testable import CosmoOS

final class SwipeLibraryFilteringTests: XCTestCase {
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

    private func makeItem(
        title: String,
        hookScore: Double? = nil,
        hookType: SwipeHookType? = nil,
        narrative: NarrativeStyle? = nil,
        format: ContentFormat? = nil,
        creator: String? = nil,
        createdAt: String = "2026-05-01T00:00:00Z"
    ) -> SwipeGalleryItem {
        SwipeGalleryItem(
            atomUUID: UUID().uuidString,
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
