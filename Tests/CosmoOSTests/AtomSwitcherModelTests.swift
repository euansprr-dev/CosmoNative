import XCTest
@testable import CosmoOS

/// The Atom window switcher's pure grammar: how results group, how the
/// home assembles, how the keyboard travels, and what Esc means.
final class AtomSwitcherModelTests: XCTestCase {

    // MARK: - Search grouping

    func testSearchSectionsLeadWithTheBestTier() {
        let results = [
            ranked("note-1", .note, "Alpha planning", tier: .keywordInBody, relevance: 0.9),
            ranked("idea-1", .idea, "Alpha", tier: .exactTitle, relevance: 0.5),
            ranked("note-2", .note, "Alpha two", tier: .titlePrefix, relevance: 0.7)
        ]
        let sections = AtomSwitcherGrouping.searchSections(
            results: results, swipeUUIDs: [], thumbnails: [:], openUUID: nil, pinnedUUIDs: []
        )
        XCTAssertEqual(sections.map(\.title), ["Ideas", "Pages"])
        XCTAssertEqual(sections[1].rows.map(\.uuid), ["note-1", "note-2"], "rows keep the incoming ranked order")
        XCTAssertEqual(sections[1].count, 2)
    }

    func testSearchSectionsSplitSwipesFromResearchAndDedupe() {
        let results = [
            ranked("r-1", .research, "Captured page", tier: .titleMatch),
            ranked("s-1", .research, "Viral carousel", tier: .titleMatch),
            ranked("r-1", .research, "Captured page", tier: .semanticOnly)
        ]
        let sections = AtomSwitcherGrouping.searchSections(
            results: results, swipeUUIDs: ["s-1"], thumbnails: ["s-1": "https://x/y.jpg"],
            openUUID: "r-1", pinnedUUIDs: ["s-1"]
        )
        XCTAssertEqual(sections.map(\.title), ["Research", "Swipes"])
        XCTAssertEqual(sections[0].rows.count, 1, "the same atom never lists twice")
        XCTAssertTrue(sections[0].rows[0].isOpen)
        XCTAssertEqual(sections[0].rows[0].kindLabel, "Research")
        let swipe = sections[1].rows[0]
        XCTAssertTrue(swipe.isSwipe)
        XCTAssertTrue(swipe.isPinned)
        XCTAssertEqual(swipe.kindLabel, "Swipe")
        XCTAssertEqual(swipe.thumbnailURL, "https://x/y.jpg")
    }

    func testExcerptOnlySurvivesForBodyEvidence() {
        let title = ranked("a", .note, "Title hit", tier: .titleMatch, excerpt: "…title hit…")
        let body = ranked("b", .note, "Elsewhere", tier: .phraseInBody, excerpt: "…the phrase…")
        let sections = AtomSwitcherGrouping.searchSections(
            results: [title, body], swipeUUIDs: [], thumbnails: [:], openUUID: nil, pinnedUUIDs: []
        )
        let rows = sections.flatMap(\.rows)
        XCTAssertNil(rows.first { $0.uuid == "a" }?.excerpt)
        XCTAssertEqual(rows.first { $0.uuid == "b" }?.excerpt, "…the phrase…")
    }

    // MARK: - Home & browse

    func testHomeLeadsWithTheOpenItemAndNeverRepeats() {
        let open = row("open", .note, updatedAt: "2026-09-06T10:00:00Z")
        let recents = (0..<12).map { row("r\($0)", .idea, updatedAt: "2026-09-06T09:\(String(format: "%02d", 59 - $0)):00Z") }
        let pinned = [row("open", .note, updatedAt: "2026-09-06T10:00:00Z"), row("r0", .idea), row("p1", .content)]
        let sections = AtomSwitcherGrouping.homeSections(open: open, recents: recents, pinned: pinned)

        XCTAssertEqual(sections.map(\.id), ["continue", "pinned"])
        XCTAssertEqual(sections[0].rows.first?.uuid, "open")
        XCTAssertEqual(sections[0].rows.count, AtomSwitcherGrouping.continueCap)
        XCTAssertEqual(sections[1].rows.map(\.uuid), ["p1"], "pinned never repeats an item already in Continue")
    }

    func testHomeWithNothingIsEmptyNotSilent() {
        XCTAssertTrue(AtomSwitcherGrouping.homeSections(open: nil, recents: [], pinned: []).isEmpty)
    }

    func testBrowseCapsRowsButCountsEverything() {
        let rows = (0..<(AtomSwitcherGrouping.browseCap + 5)).map {
            row("n\($0)", .note, updatedAt: "2026-01-01T00:00:\(String(format: "%02d", $0 % 60))Z")
        }
        let sections = AtomSwitcherGrouping.browseSections(rows: rows)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].rows.count, AtomSwitcherGrouping.browseCap)
        XCTAssertEqual(sections[0].count, AtomSwitcherGrouping.browseCap + 5)
    }

    func testBrowseOrdersNewestFirstAndSplitsSwipes() {
        let rows = [
            row("old", .research, updatedAt: "2026-01-01T00:00:00Z"),
            row("new", .research, updatedAt: "2026-02-01T00:00:00Z"),
            row("swipe", .research, isSwipe: true, updatedAt: "2026-03-01T00:00:00Z")
        ]
        let sections = AtomSwitcherGrouping.browseSections(rows: rows)
        XCTAssertEqual(sections.map(\.title), ["Research", "Swipes"])
        XCTAssertEqual(sections[0].rows.map(\.uuid), ["new", "old"])
    }

    // MARK: - Scope

    func testScopeCyclesWrapBothWays() {
        XCTAssertEqual(AtomSwitcherScope.everything.cycled(by: -1), AtomSwitcherScope.allCases.last)
        XCTAssertEqual(AtomSwitcherScope.allCases.last?.cycled(by: 1), .everything)
        XCTAssertEqual(AtomSwitcherScope.pages.cycled(by: 1), .ideas)
    }

    func testScopeDigitsAreOneBasedInDeclarationOrder() {
        XCTAssertEqual(AtomSwitcherScope.everything.shortcutDigit, 1)
        XCTAssertEqual(AtomSwitcherScope.media.shortcutDigit, AtomSwitcherScope.allCases.count)
        XCTAssertLessThanOrEqual(AtomSwitcherScope.allCases.count, 9, "⌘1–⌘9 must cover every scope")
    }

    func testScopeMembership() {
        XCTAssertTrue(AtomSwitcherScope.everything.includes(.journalEntry))
        XCTAssertFalse(AtomSwitcherScope.everything.includes(.thinkspace))
        XCTAssertTrue(AtomSwitcherScope.media.includes(.file))
        XCTAssertFalse(AtomSwitcherScope.pages.includes(.idea))
        XCTAssertEqual(AtomSwitcherScope.pages.placeholder, "Search pages")
        XCTAssertEqual(AtomSwitcherScope.everything.placeholder, "Search everything")
    }

    // MARK: - Keyboard

    func testSelectionTravelSeedsAndClamps() {
        let rows = ["a", "b", "c"].map { row($0, .note) }
        XCTAssertEqual(AtomSwitcherGrouping.nextSelection(from: nil, in: rows, offset: 1), "a")
        XCTAssertEqual(AtomSwitcherGrouping.nextSelection(from: nil, in: rows, offset: -1), "c")
        XCTAssertEqual(AtomSwitcherGrouping.nextSelection(from: "a", in: rows, offset: -1), "a")
        XCTAssertEqual(AtomSwitcherGrouping.nextSelection(from: "b", in: rows, offset: 1), "c")
        XCTAssertEqual(AtomSwitcherGrouping.nextSelection(from: "c", in: rows, offset: 1), "c")
        XCTAssertEqual(AtomSwitcherGrouping.nextSelection(from: "zzz", in: rows, offset: 1), "a", "a vanished selection re-seeds")
        XCTAssertNil(AtomSwitcherGrouping.nextSelection(from: "a", in: [], offset: 1))
    }

    func testEscapeLadder() {
        XCTAssertEqual(AtomSwitcherEscape.resolve(queryIsEmpty: false, hasOpenItem: true), .clearQuery)
        XCTAssertEqual(AtomSwitcherEscape.resolve(queryIsEmpty: false, hasOpenItem: false), .clearQuery)
        XCTAssertEqual(AtomSwitcherEscape.resolve(queryIsEmpty: true, hasOpenItem: true), .returnToOpenItem)
        XCTAssertEqual(AtomSwitcherEscape.resolve(queryIsEmpty: true, hasOpenItem: false), .closeWindow)
    }

    // MARK: - Hybrid family mapping

    func testHybridFamiliesMapToRealKindsOrDrop() {
        XCTAssertEqual(AtomSwitcherGrouping.atomType(for: .note), .note, "pages must never demote to ideas")
        XCTAssertEqual(AtomSwitcherGrouping.atomType(for: .journal), .journalEntry)
        XCTAssertEqual(AtomSwitcherGrouping.atomType(for: .file), .file)
        XCTAssertNil(AtomSwitcherGrouping.atomType(for: .thinkspace))
        XCTAssertNil(AtomSwitcherGrouping.atomType(for: .cosmoAI))
    }

    // MARK: - Helpers

    private func ranked(
        _ uuid: String, _ type: AtomType, _ title: String,
        tier: LexicalTier, relevance: Double = 0.5, excerpt: String? = nil
    ) -> RankedResult {
        RankedResult(
            atomUUID: uuid, atomType: type, title: title,
            snippet: "body", matchedExcerpt: excerpt,
            structuralWeight: relevance, recencyWeight: 0.5, usageWeight: 0.5,
            lexicalTier: tier, updatedAt: "2026-09-06T00:00:00Z"
        )
    }

    private func row(
        _ uuid: String, _ type: AtomType, isSwipe: Bool = false,
        updatedAt: String = "2026-09-06T00:00:00Z"
    ) -> AtomSwitcherRow {
        AtomSwitcherRow(
            uuid: uuid, type: type, isSwipe: isSwipe, title: uuid,
            excerpt: nil, snippet: nil, updatedAt: updatedAt, thumbnailURL: nil
        )
    }
}
