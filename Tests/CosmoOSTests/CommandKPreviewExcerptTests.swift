// Tests/CosmoOSTests/CommandKPreviewExcerptTests.swift
// ⌘K preview invariant (July 9 2026 freeze): preview surfaces must never
// typeset unbounded text — one transcript-sized atom body in a SwiftUI Text
// froze the app inside a single CoreText layout pass. Every ⌘K preview
// string is clamped through CommandKPreviewExcerpt at the leaf views and
// the display-model choke points.

import XCTest
@testable import CosmoOS

final class CommandKPreviewExcerptTests: XCTestCase {

    func testShortTextPassesThroughUntouched() {
        let text = "A short note body"
        XCTAssertEqual(CommandKPreviewExcerpt.clamp(text, limit: 500), text)
    }

    func testTextAtExactLimitPassesThroughWithoutEllipsis() {
        let text = String(repeating: "a", count: 500)
        XCTAssertEqual(CommandKPreviewExcerpt.clamp(text, limit: 500), text)
    }

    func testOversizedTextIsClampedWithEllipsis() {
        let transcript = String(repeating: "word ", count: 200_000) // ~1MB body
        let clamped = CommandKPreviewExcerpt.clamp(transcript, limit: 500)
        XCTAssertEqual(clamped.count, 501) // 500 chars + ellipsis
        XCTAssertTrue(clamped.hasSuffix("…"))
    }

    func testOptionalVariantPreservesNil() {
        XCTAssertNil(CommandKPreviewExcerpt.clampOptional(nil, limit: 500))
        XCTAssertEqual(CommandKPreviewExcerpt.clampOptional("hi", limit: 500), "hi")
    }

    /// Recents cards feed SpotlightPageContent (4pt texture tiles) — the
    /// composer must never hand them a full atom body.
    @MainActor
    func testRecentDisplayItemPreviewIsBounded() {
        var atom = Atom.new(type: .research, title: "Video research")
        atom.body = String(repeating: "transcript line. ", count: 60_000) // ~1MB
        let items = CommandKRecentComposer.compose(
            opened: [.init(atom: atom, openedAt: ISO8601.string(from: Date()), accessCount: 3)],
            limit: 5
        )
        let preview = items.first?.preview
        XCTAssertNotNil(preview)
        XCTAssertLessThanOrEqual(
            preview?.count ?? 0,
            CommandKPreviewExcerpt.thumbnailLimit + 1,
            "Recents preview must be clamped to a thumbnail excerpt"
        )
    }
}
