import XCTest
import AppKit
import SwiftUI
@testable import CosmoOS

/// The manuscript-blanking bug: every click/selection in a focused continuous
/// editor re-ran full-document attribute passes (override stamp, focus-band
/// temporary-attribute clear, polish re-stamp), each of which dirtied the
/// storage and invalidated the entire document's display mid-frame — the text
/// visibly blinked, and could stay blank until the next click forced another
/// redraw cycle. These tests pin the invariant that a pass with nothing to
/// change performs ZERO storage edits.
final class EditorRedrawHygieneTests: XCTestCase {

    // MARK: - Focus band planning

    func testNoBandRequestedAndNonePaintedIsANoOp() {
        // The common case: focus band mode off, user clicks around.
        let plan = FocusBandPlanner.plan(
            requested: nil, fullLength: 500, lastApplied: nil, hasApplied: false, force: false
        )
        XCTAssertEqual(plan, .none)
    }

    func testNSNotFoundRequestIsTreatedAsNoBand() {
        let plan = FocusBandPlanner.plan(
            requested: NSRange(location: NSNotFound, length: 0),
            fullLength: 500, lastApplied: nil, hasApplied: false, force: false
        )
        XCTAssertEqual(plan, .none)
    }

    func testBandClearsOnceWhenRequestGoesAway() {
        let painted = NSRange(location: 10, length: 20)
        let clear = FocusBandPlanner.plan(
            requested: nil, fullLength: 500, lastApplied: painted, hasApplied: true, force: false
        )
        XCTAssertEqual(clear, .clear)
        // After the clear, further caret moves must be no-ops again.
        let after = FocusBandPlanner.plan(
            requested: nil, fullLength: 500, lastApplied: nil, hasApplied: false, force: false
        )
        XCTAssertEqual(after, .none)
    }

    func testSameBandIsNotRepainted() {
        let band = NSRange(location: 40, length: 60)
        let first = FocusBandPlanner.plan(
            requested: band, fullLength: 500, lastApplied: nil, hasApplied: false, force: false
        )
        XCTAssertEqual(first, .apply(band))
        let second = FocusBandPlanner.plan(
            requested: band, fullLength: 500, lastApplied: band, hasApplied: true, force: false
        )
        XCTAssertEqual(second, .none)
    }

    func testForceRepaintsSameBandAfterContentEdit() {
        let band = NSRange(location: 40, length: 60)
        let plan = FocusBandPlanner.plan(
            requested: band, fullLength: 500, lastApplied: band, hasApplied: true, force: true
        )
        XCTAssertEqual(plan, .apply(band))
    }

    func testDifferentBandRepaints() {
        let old = NSRange(location: 40, length: 60)
        let new = NSRange(location: 120, length: 30)
        let plan = FocusBandPlanner.plan(
            requested: new, fullLength: 500, lastApplied: old, hasApplied: true, force: false
        )
        XCTAssertEqual(plan, .apply(new))
    }

    func testBandRequestIsClampedToContent() {
        // Requested range spills past the end — clamp, minimum length 1.
        let plan = FocusBandPlanner.plan(
            requested: NSRange(location: 90, length: 400),
            fullLength: 100, lastApplied: nil, hasApplied: false, force: false
        )
        XCTAssertEqual(plan, .apply(NSRange(location: 90, length: 10)))
        // Fully out of bounds resolves to no band.
        let outOfBounds = FocusBandPlanner.plan(
            requested: NSRange(location: 100, length: 5),
            fullLength: 100, lastApplied: nil, hasApplied: false, force: false
        )
        XCTAssertEqual(outOfBounds, .none)
    }

    // MARK: - Storage override stamping

    @MainActor
    func testOverrideStampIsIdempotent() {
        let storage = NSTextStorage(
            attributedString: NSAttributedString(
                string: "Hello manuscript",
                attributes: [.foregroundColor: NSColor.systemBrown]
            )
        )
        let spy = EditSpy()
        storage.delegate = spy
        let override = NSColor.white

        let first = EditorStorageOverridePass.apply(
            to: storage, overrideTextColor: override, overrideFont: nil, appliesHeadingIndents: true
        )
        XCTAssertTrue(first, "first pass must stamp the override color")
        XCTAssertGreaterThan(spy.editCount, 0)

        spy.editCount = 0
        let second = EditorStorageOverridePass.apply(
            to: storage, overrideTextColor: override, overrideFont: nil, appliesHeadingIndents: true
        )
        XCTAssertFalse(second, "an already-stamped storage must not be re-edited")
        XCTAssertEqual(spy.editCount, 0, "steady-state pass performed storage edits — this re-invalidates the whole document on every click")

        let stamped = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(stamped, override)
    }

    @MainActor
    func testOverrideStampPreservesEntityRuns() {
        let text = NSMutableAttributedString(
            string: "See note here",
            attributes: [.foregroundColor: NSColor.systemBrown]
        )
        let entityRange = NSRange(location: 4, length: 4)
        text.addAttribute(RichDocumentAttributeKeys.entityType, value: "note", range: entityRange)
        text.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: entityRange)
        let storage = NSTextStorage(attributedString: text)

        EditorStorageOverridePass.apply(
            to: storage, overrideTextColor: NSColor.white, overrideFont: nil, appliesHeadingIndents: true
        )

        let entityColor = storage.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor
        XCTAssertEqual(entityColor, NSColor.systemBlue, "mention/entity runs keep their own color")
        let bodyColor = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(bodyColor, NSColor.white)
    }

    @MainActor
    func testChecklistGlyphStaysClearAndDoesNotChurn() {
        let text = NSMutableAttributedString(
            string: "☐ buy oat milk",
            attributes: [.foregroundColor: NSColor.systemBrown]
        )
        text.addAttribute(.foregroundColor, value: NSColor.clear, range: NSRange(location: 0, length: 1))
        let storage = NSTextStorage(attributedString: text)
        let spy = EditSpy()
        storage.delegate = spy

        EditorStorageOverridePass.apply(
            to: storage, overrideTextColor: NSColor.white, overrideFont: nil, appliesHeadingIndents: true
        )
        let glyphColor = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(glyphColor, NSColor.clear, "the stored ☐ must never ink — the circle checkbox is painted over it")

        spy.editCount = 0
        let second = EditorStorageOverridePass.apply(
            to: storage, overrideTextColor: NSColor.white, overrideFont: nil, appliesHeadingIndents: true
        )
        XCTAssertFalse(second)
        XCTAssertEqual(spy.editCount, 0, "glyph reclear must not churn (re-ink + re-clear) on steady-state passes")
    }

    @MainActor
    func testClearColoredBodyTextIsReInked() {
        // Guarantee: ordinary text can never be stuck invisible. Only the
        // line-leading checklist glyph is allowed to stay clear.
        let text = NSMutableAttributedString(
            string: "ghost text",
            attributes: [.foregroundColor: NSColor.clear]
        )
        let storage = NSTextStorage(attributedString: text)

        let edited = EditorStorageOverridePass.apply(
            to: storage, overrideTextColor: NSColor.white, overrideFont: nil, appliesHeadingIndents: true
        )
        XCTAssertTrue(edited)
        let color = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, NSColor.white, "clear-colored body text must be re-inked to the override color")
    }

    @MainActor
    func testFontOverrideIsDiffAware() {
        let font = NSFont.systemFont(ofSize: 17)
        let storage = NSTextStorage(
            attributedString: NSAttributedString(
                string: "Body",
                attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.white]
            )
        )
        XCTAssertTrue(EditorStorageOverridePass.apply(
            to: storage, overrideTextColor: nil, overrideFont: font, appliesHeadingIndents: true
        ))
        XCTAssertFalse(EditorStorageOverridePass.apply(
            to: storage, overrideTextColor: nil, overrideFont: font, appliesHeadingIndents: true
        ))
        XCTAssertEqual(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont, font)
    }

    /// The config/override signature gating (and the diff-aware color compare)
    /// rely on SwiftUI-bridged NSColors comparing equal across body
    /// evaluations. If this ever breaks, configureTextView re-runs per update
    /// and re-triggers the full-document invalidation storm.
    func testBridgedSwiftUIColorsCompareEqualAcrossInstances() {
        let a = NSColor(Color(red: 0.94, green: 0.92, blue: 0.86))
        let b = NSColor(Color(red: 0.94, green: 0.92, blue: 0.86))
        XCTAssertEqual(a, b)
    }
}

private final class EditSpy: NSObject, NSTextStorageDelegate {
    var editCount = 0
    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        editCount += 1
    }
}
