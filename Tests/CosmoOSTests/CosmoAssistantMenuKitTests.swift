import XCTest
@testable import CosmoOS

final class CosmoAssistantMenuKitTests: XCTestCase {

    // MARK: - Kind-scope parser

    func testScopeParserMatchesEveryKindPrefixIncludingPlurals() {
        let cases: [(String, CosmoInlineContextScope)] = [
            ("idea hook", .idea),
            ("ideas hook", .idea),
            ("swipe gym", .swipe),
            ("swipes gym", .swipe),
            ("note plan", .note),
            ("notes plan", .note),
            ("profile josh", .profile),
            ("profiles josh", .profile),
            ("content reel", .content),
            ("research dscr", .research),
            ("IDEA hook", .idea)
        ]

        for (raw, expected) in cases {
            let parse = CosmoInlineContextScopeParser.parse(raw)
            XCTAssertEqual(parse.scope, expected, "raw: \(raw)")
        }

        XCTAssertEqual(CosmoInlineContextScopeParser.parse("idea hook").query, "hook")
        XCTAssertEqual(CosmoInlineContextScopeParser.parse("ideas hook").scopeTokenLength, 5)
    }

    func testScopeParserPassesThroughUnknownFirstTokens() {
        let parse = CosmoInlineContextScopeParser.parse("josh profile deck")
        XCTAssertNil(parse.scope)
        XCTAssertEqual(parse.query, "josh profile deck")
        XCTAssertEqual(parse.scopeTokenLength, 0)
    }

    func testScopeParserBareKindTokenScopesWithEmptyQuery() {
        let parse = CosmoInlineContextScopeParser.parse("idea")
        XCTAssertEqual(parse.scope, .idea)
        XCTAssertEqual(parse.query, "")
    }

    func testScopeParserLeadingWhitespaceNeverScopes() {
        // "@ idea" is a search for "idea", not a scope.
        let parse = CosmoInlineContextScopeParser.parse(" idea")
        XCTAssertNil(parse.scope)
        XCTAssertEqual(parse.query, "idea")
    }

    func testScopeParserEmptyInput() {
        let parse = CosmoInlineContextScopeParser.parse("")
        XCTAssertNil(parse.scope)
        XCTAssertEqual(parse.query, "")
    }

    // MARK: - Key router

    func testKeyRouterRoutesNavigationKeysOnlyWhileMenuVisible() {
        XCTAssertEqual(CosmoAssistantMenuKeyRouter.action(keyCode: 126, isMenuVisible: true), .moveUp)
        XCTAssertEqual(CosmoAssistantMenuKeyRouter.action(keyCode: 125, isMenuVisible: true), .moveDown)
        XCTAssertEqual(CosmoAssistantMenuKeyRouter.action(keyCode: 36, isMenuVisible: true), .commit)
        XCTAssertEqual(CosmoAssistantMenuKeyRouter.action(keyCode: 48, isMenuVisible: true), .commit)

        // With no menu open, everything passes through — Return submits and
        // Tab keeps accepting the ghost-chip suggestion.
        for keyCode: UInt16 in [126, 125, 36, 48] {
            XCTAssertEqual(
                CosmoAssistantMenuKeyRouter.action(keyCode: keyCode, isMenuVisible: false),
                .passthrough
            )
        }

        // Unrelated keys pass through even while the menu is open (typing).
        XCTAssertEqual(CosmoAssistantMenuKeyRouter.action(keyCode: 0, isMenuVisible: true), .passthrough)
    }

    // MARK: - Highlight policy

    func testHighlightPolicyClampsWithoutWrapping() {
        XCTAssertEqual(CosmoAssistantMenuHighlightPolicy.moved(0, by: -1, count: 5), 0)
        XCTAssertEqual(CosmoAssistantMenuHighlightPolicy.moved(4, by: 1, count: 5), 4)
        XCTAssertEqual(CosmoAssistantMenuHighlightPolicy.moved(2, by: 1, count: 5), 3)
        XCTAssertEqual(CosmoAssistantMenuHighlightPolicy.moved(2, by: -1, count: 5), 1)
        XCTAssertEqual(CosmoAssistantMenuHighlightPolicy.moved(3, by: 1, count: 0), 0)
        XCTAssertEqual(CosmoAssistantMenuHighlightPolicy.clamped(9, count: 3), 2)
        XCTAssertEqual(CosmoAssistantMenuHighlightPolicy.clamped(-2, count: 3), 0)
    }

    // MARK: - Token wash policy

    func testTokenWashCoversActiveScopeTokenOnly() {
        // Caret at the end of "@idea hook" — the wash covers "@idea" only.
        let text = "tighten @idea hook"
        let selection = NSRange(location: (text as NSString).length, length: 0)

        let washes = CosmoInlineComposerTokenWashPolicy.washes(
            text: text, selection: selection, armedSkillName: nil
        )

        XCTAssertEqual(washes.count, 1)
        XCTAssertEqual(washes[0].range, NSRange(location: 8, length: 5))
        XCTAssertEqual(washes[0].kind, .scope(.idea))
    }

    func testTokenWashSkipsUnscopedMentions() {
        let text = "tighten @josh deck"
        let selection = NSRange(location: (text as NSString).length, length: 0)

        let washes = CosmoInlineComposerTokenWashPolicy.washes(
            text: text, selection: selection, armedSkillName: nil
        )

        XCTAssertTrue(washes.isEmpty)
    }

    func testTokenWashMarksArmedSkillTokenAtWordBoundaries() {
        let text = "/Content Review tighten the hook"
        let washes = CosmoInlineComposerTokenWashPolicy.washes(
            text: text,
            selection: NSRange(location: 0, length: 0),
            armedSkillName: "Content Review"
        )

        XCTAssertEqual(washes.count, 1)
        XCTAssertEqual(washes[0].range, NSRange(location: 0, length: 15))
        XCTAssertEqual(washes[0].kind, .skill)
    }

    func testTokenWashIgnoresSkillTokenEmbeddedInsideAWord() {
        let text = "see https://example.com/review for details"
        let washes = CosmoInlineComposerTokenWashPolicy.washes(
            text: text,
            selection: NSRange(location: 0, length: 0),
            armedSkillName: "review"
        )

        XCTAssertTrue(washes.isEmpty)
    }

    // MARK: - Skill recency store

    func testRecencyStoreOrdersByMostRecentUseAndHonorsLimit() {
        let suite = "cosmo-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = CosmoInlineSkillRecencyStore(defaults: defaults)
        let base = Date(timeIntervalSince1970: 1_000_000)
        store.recordUse("alpha", at: base)
        store.recordUse("beta", at: base.addingTimeInterval(60))
        store.recordUse("gamma", at: base.addingTimeInterval(120))
        // Re-using an old skill bumps it to the front.
        store.recordUse("alpha", at: base.addingTimeInterval(180))

        XCTAssertEqual(store.recentIDs(limit: 2), ["alpha", "gamma"])
        XCTAssertEqual(store.recentIDs(limit: 10), ["alpha", "gamma", "beta"])
    }
}
