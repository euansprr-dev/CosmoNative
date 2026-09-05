// CosmoOS/Tests/CosmoOSTests/CosmoAssistantMarkdownRendererTests.swift
// The pane's Markdown renderer: raw syntax never reaches the screen, block
// structure becomes real typography, and document pills survive the parse.

import AppKit
import XCTest
@testable import CosmoOS

final class CosmoAssistantMarkdownRendererTests: XCTestCase {
    private let palette = CosmoAssistantMarkdownRenderer.Palette(
        text: .black,
        secondary: .darkGray,
        muted: .gray,
        accent: .systemBlue,
        accentSoft: .systemBlue,
        blockFill: .lightGray,
        blockBorder: .gray,
        inlineCodeFill: .lightGray
    )
    private let pricing = CosmoAssistantSourceRef(uuid: "uuid-pricing", title: "Pricing psychology", kind: "research")

    private func render(_ markdown: String, refs: [CosmoAssistantSourceRef] = [], streaming: Bool = false) -> NSAttributedString {
        CosmoAssistantMarkdownRenderer.render(markdown: markdown, sourceRefs: refs, isStreaming: streaming, palette: palette).attributed
    }

    private func weight(of font: NSFont) -> CGFloat {
        let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        return traits?[.weight] as? CGFloat ?? 0
    }

    private func font(at location: Int, in attributed: NSAttributedString) -> NSFont? {
        attributed.attribute(.font, at: location, effectiveRange: nil) as? NSFont
    }

    // MARK: Inline

    func testBoldRendersAsWeightNotAsterisks() {
        let attributed = render("The hook is **the number** here.")
        XCTAssertFalse(attributed.string.contains("*"))
        XCTAssertEqual(attributed.string, "The hook is the number here.")
        let boldLocation = (attributed.string as NSString).range(of: "the number").location
        let plainLocation = (attributed.string as NSString).range(of: "The hook").location
        XCTAssertGreaterThan(weight(of: font(at: boldLocation, in: attributed)!), weight(of: font(at: plainLocation, in: attributed)!))
    }

    func testItalicCodeStrikethroughAndLinks() {
        let attributed = render("Use *this* and `apply 2` but ~~not that~~, see [docs](https://example.com/x).")
        let string = attributed.string as NSString
        XCTAssertFalse(attributed.string.contains("`"))
        XCTAssertFalse(attributed.string.contains("~~"))

        let italic = font(at: string.range(of: "this").location, in: attributed)!
        XCTAssertTrue(italic.fontDescriptor.symbolicTraits.contains(.italic))

        let codeLocation = string.range(of: "apply 2").location
        XCTAssertEqual(attributed.attribute(.cosmoProseInlineCode, at: codeLocation, effectiveRange: nil) as? Bool, true)
        XCTAssertTrue(font(at: codeLocation, in: attributed)!.isFixedPitch)

        let strikeLocation = string.range(of: "not that").location
        XCTAssertEqual(attributed.attribute(.strikethroughStyle, at: strikeLocation, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)

        let linkLocation = string.range(of: "docs").location
        XCTAssertEqual((attributed.attribute(.link, at: linkLocation, effectiveRange: nil) as? URL)?.absoluteString, "https://example.com/x")
    }

    // MARK: Blocks

    func testHeadingsParagraphsAndSoftBreaks() {
        let attributed = render("## Hook\nSLIDE 1\nFirst line\n\nSecond paragraph")
        let string = attributed.string as NSString
        XCTAssertFalse(attributed.string.contains("#"))
        let heading = font(at: string.range(of: "Hook").location, in: attributed)!
        XCTAssertEqual(heading.pointSize, 17)
        // Soft line breaks inside a paragraph are kept — slide copy relies on them.
        XCTAssertTrue(attributed.string.contains("SLIDE 1\nFirst line"))
        XCTAssertTrue(attributed.string.contains("Second paragraph"))
        let body = font(at: string.range(of: "Second").location, in: attributed)!
        XCTAssertEqual(body.pointSize, CosmoAssistantMarkdownRenderer.bodySize)
    }

    func testListsCarryMarkersAndHangingIndents() {
        let attributed = render("- one\n- two\n\n1. first\n2. second")
        XCTAssertTrue(attributed.string.contains("•\tone"))
        XCTAssertTrue(attributed.string.contains("1.\tfirst"))
        XCTAssertTrue(attributed.string.contains("2.\tsecond"))
        let string = attributed.string as NSString
        let style = attributed.attribute(.paragraphStyle, at: string.range(of: "one").location, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(style?.headIndent, CosmoAssistantMarkdownRenderer.listMarkerWidth)
        XCTAssertEqual(style?.firstLineHeadIndent, 0)
    }

    func testNestedListIndentsByDepth() {
        let blocks = CosmoAssistantMarkdownRenderer.parseBlocks(from: "- outer\n  - inner")
        let kinds = blocks.map(\.kind)
        XCTAssertEqual(kinds.count, 2)
        XCTAssertEqual(kinds.first, .listItem(depth: 0, ordinal: nil))
        XCTAssertEqual(kinds.last, .listItem(depth: 1, ordinal: nil))
    }

    func testCodeBlockAndQuoteCarryBlockDecorations() {
        let attributed = render("```\nlet x = 1\n```\n\n> quoted copy")
        let string = attributed.string as NSString
        XCTAssertFalse(attributed.string.contains("```"))
        let codeLocation = string.range(of: "let x").location
        XCTAssertEqual(attributed.attribute(.cosmoProseBlock, at: codeLocation, effectiveRange: nil) as? String, CosmoProseBlockDecoration.code.rawValue)
        XCTAssertTrue(font(at: codeLocation, in: attributed)!.isFixedPitch)

        let quoteLocation = string.range(of: "quoted copy").location
        XCTAssertEqual(attributed.attribute(.cosmoProseBlock, at: quoteLocation, effectiveRange: nil) as? String, CosmoProseBlockDecoration.quote.rawValue)
        XCTAssertFalse(attributed.string.contains(">"))
    }

    func testTableBecomesTextTableBlocks() {
        let attributed = render("| Option | Cost |\n| --- | --- |\n| Sol | $2 |\n| Terra | $2 |")
        let string = attributed.string as NSString
        XCTAssertFalse(attributed.string.contains("|"))
        let cellLocation = string.range(of: "Terra").location
        let style = attributed.attribute(.paragraphStyle, at: cellLocation, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(style?.textBlocks.count, 1)
        XCTAssertTrue(style?.textBlocks.first is NSTextTableBlock)
        let headerLocation = string.range(of: "Option").location
        XCTAssertGreaterThan(weight(of: font(at: headerLocation, in: attributed)!), weight(of: font(at: cellLocation, in: attributed)!))
    }

    func testReceiptLineRendersAsMutedCaption() {
        let attributed = render("Done.\n\n_≈$0.28 · 13.3K in (0% cached) · 7.1K out_")
        let string = attributed.string as NSString
        XCTAssertFalse(attributed.string.contains("_"))
        let receipt = font(at: string.range(of: "13.3K").location, in: attributed)!
        XCTAssertEqual(receipt.pointSize, 11)
    }

    // MARK: Pills

    func testExplicitMarkerBecomesAPillInsideMarkdown() {
        let result = CosmoAssistantMarkdownRenderer.render(
            markdown: "**Reuse** [[uuid-pricing]] for the anchor.",
            sourceRefs: [pricing],
            isStreaming: false,
            palette: palette
        )
        XCTAssertEqual(result.linkedRefUUIDs, ["uuid-pricing"])
        XCTAssertFalse(result.attributed.string.contains("[["))
        var pills = 0
        result.attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: result.attributed.length)) { value, range, _ in
            guard let attachment = value as? CosmoMentionPillAttachment else { return }
            pills += 1
            XCTAssertEqual(attachment.sourceRef?.uuid, "uuid-pricing")
            XCTAssertEqual(result.attributed.attribute(.link, at: range.location, effectiveRange: nil) as? String, "uuid-pricing")
        }
        XCTAssertEqual(pills, 1)
    }

    func testTitleAutoLinksAfterParseButNeverInsideCode() {
        let result = CosmoAssistantMarkdownRenderer.render(
            markdown: "Run `Pricing psychology` later; Pricing psychology already covers this.",
            sourceRefs: [pricing],
            isStreaming: false,
            palette: palette
        )
        XCTAssertEqual(result.linkedRefUUIDs, ["uuid-pricing"])
        // The inline-code occurrence stays literal; the prose occurrence became the pill.
        XCTAssertTrue(result.attributed.string.contains("Pricing psychology"))
        var pillLocations: [Int] = []
        result.attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: result.attributed.length)) { value, range, _ in
            if value is CosmoMentionPillAttachment { pillLocations.append(range.location) }
        }
        XCTAssertEqual(pillLocations.count, 1)
        let codeRange = (result.attributed.string as NSString).range(of: "Pricing psychology")
        XCTAssertEqual(result.attributed.attribute(.cosmoProseInlineCode, at: codeRange.location, effectiveRange: nil) as? Bool, true)
    }

    // MARK: Streaming

    func testStreamingHidesTrailingPartialMarkerAndKeepsPartialEmphasis() {
        let attributed = render("See **the note** and [[uuid-pri", refs: [pricing], streaming: true)
        // CommonMark drops a paragraph's trailing whitespace — the marker is gone, the prose is intact.
        XCTAssertEqual(attributed.string, "See the note and")
        XCTAssertEqual(CosmoAssistantMarkdownRenderer.hidingTrailingPartialMarker(in: "a [[b]] c"), "a [[b]] c")
    }

    func testEmptyAndPlainInputs() {
        XCTAssertEqual(render("").length, 0)
        XCTAssertEqual(render("Just prose.").string, "Just prose.")
    }

    // MARK: Cache

    @MainActor
    func testRenderCacheServesRepeatRendersAndEvicts() {
        let cache = CosmoAssistantAnswerRenderCache(capacity: 2)
        let a = CosmoInlineAssistantPaneMessage(role: .assistant, content: "**a**")
        let b = CosmoInlineAssistantPaneMessage(role: .assistant, content: "**b**")
        let c = CosmoInlineAssistantPaneMessage(role: .assistant, content: "**c**")
        let first = cache.rendered(for: a)
        XCTAssertEqual(cache.rendered(for: a).key, first.key)
        XCTAssertEqual(cache.count, 1)
        _ = cache.rendered(for: b)
        _ = cache.rendered(for: c)
        XCTAssertEqual(cache.count, 2)
    }
}
