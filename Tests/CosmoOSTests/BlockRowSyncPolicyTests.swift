import XCTest
@testable import CosmoOS

/// The document owns a block row's kind: a text-view content sync may never
/// change it in either direction. Regression coverage for the "deleted bullet
/// resurrects and permanently breaks heading transforms" bug — a stale "• "
/// re-emission racing the style-shed used to re-impose the list kind over the
/// fresh paragraph, desyncing the row (document: bullet, view: plain) forever.
final class BlockRowSyncPolicyTests: XCTestCase {
    func testStaleBulletParseNeverResurrectsListKindOverParagraph() {
        // The row was just shed from bullet → paragraph; the text view's stale
        // "• " snapshot re-emits and parses as a bullet.
        let existing = RichBlock(kind: .paragraph, inlines: [.text("")])
        let staleParse = RichBlock(kind: .bulletList, inlines: [.text("")])

        let reconciled = BlockRowSyncPolicy.reconciled(parsed: [staleParse], existingBlock: existing)

        XCTAssertEqual(reconciled.count, 1)
        XCTAssertEqual(reconciled[0].kind, .paragraph)
        XCTAssertEqual(reconciled[0].id, existing.id)
    }

    func testStaleNumberedListParseNeverResurrectsListKindOverParagraph() {
        let existing = RichBlock(kind: .paragraph, inlines: [.text("")])
        let staleParse = RichBlock(kind: .numberedList, inlines: [.text("")])

        let reconciled = BlockRowSyncPolicy.reconciled(parsed: [staleParse], existingBlock: existing)

        XCTAssertEqual(reconciled[0].kind, .paragraph)
        XCTAssertEqual(reconciled[0].id, existing.id)
    }

    func testFirstCharacterInEmptyHeadingKeepsHeadingKind() {
        // An empty heading has no attributed run to inherit — the first typed
        // character parses as a paragraph and must not downgrade the heading.
        let existing = RichBlock(kind: .heading1, inlines: [.text("")])
        let parse = RichBlock(kind: .paragraph, inlines: [.text("J")])

        let reconciled = BlockRowSyncPolicy.reconciled(parsed: [parse], existingBlock: existing)

        XCTAssertEqual(reconciled[0].kind, .heading1)
        XCTAssertEqual(reconciled[0].id, existing.id)
        XCTAssertNotNil(reconciled[0].heading)
        XCTAssertEqual(reconciled[0].plainInlineText, "J")
    }

    func testSameKindParseKeepsIdentityAndRowOnlyFields() {
        var existing = RichBlock(kind: .toggle, inlines: [.text("Header")])
        existing.toggleCollapsed = true
        existing.children = [RichBlock(kind: .paragraph, inlines: [.text("child")])]
        let parse = RichBlock(kind: .toggle, inlines: [.text("Header!")])

        let reconciled = BlockRowSyncPolicy.reconciled(parsed: [parse], existingBlock: existing)

        XCTAssertEqual(reconciled[0].id, existing.id)
        XCTAssertEqual(reconciled[0].toggleCollapsed, true)
        XCTAssertEqual(reconciled[0].children.count, 1)
        XCTAssertEqual(reconciled[0].plainInlineText, "Header!")
    }

    func testImposedChecklistKindKeepsExistingCheckedState() {
        var existing = RichBlock(kind: .checklist, inlines: [.text("Task")])
        existing.checked = true
        let parse = RichBlock(kind: .paragraph, inlines: [.text("Task")])

        let reconciled = BlockRowSyncPolicy.reconciled(parsed: [parse], existingBlock: existing)

        XCTAssertEqual(reconciled[0].kind, .checklist)
        XCTAssertEqual(reconciled[0].checked, true)
    }

    func testHeadingTransformSurvivesAfterKindLockedSync() throws {
        // End-to-end at the document layer: shed a bullet, absorb a stale
        // bullet re-emission through the sync policy, then slash-transform to
        // a heading — the transform must land.
        var document = RichDocument(blocks: [
            RichBlock(kind: .bulletList, inlines: [.text("")])
        ])
        let path = BlockPath.root(index: 0)

        // Backspace style-shed: bullet → paragraph.
        document = try BlockOperations.transformBlock(in: document, at: path, to: .paragraph).document
        XCTAssertEqual(document.blocks[0].kind, .paragraph)

        // Stale "• " re-emission races in through the row sync.
        let stale = RichBlock(kind: .bulletList, inlines: [.text("")])
        let reconciled = BlockRowSyncPolicy.reconciled(parsed: [stale], existingBlock: document.blocks[0])
        document = try BlockOperations.replaceBlocks(in: document, at: path, with: reconciled).document
        XCTAssertEqual(document.blocks[0].kind, .paragraph)

        // Slash-menu heading transform now succeeds instead of being sabotaged.
        let result = try BlockOperations.apply(
            .transform(.heading2),
            in: document,
            at: path,
            livePlainText: "",
            triggerAlreadyRemoved: true
        )
        XCTAssertEqual(result.document.blocks[0].kind, .heading2)
        XCTAssertNotNil(result.document.blocks[0].heading)
    }
}
