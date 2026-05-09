import AppKit
import XCTest
@testable import CosmoOS

final class EditorLayoutMetricsTests: XCTestCase {
    func testSingleLineHeightMatchesBaseFontMetrics() {
        let expected = expectedSingleLineHeight(
            fontSize: 34,
            compact: false,
            baseFontWeight: .semibold
        )

        XCTAssertEqual(
            EditorLayoutMetrics.singleLineHeight(
                fontSize: 34,
                compact: false,
                baseFontWeight: .semibold
            ),
            expected,
            accuracy: 0.001
        )
    }

    func testHeadingStyledSingleLineCanNeedMoreHeightThanBaseMetric() {
        let baseHeight = EditorLayoutMetrics.singleLineHeight(
            fontSize: 34,
            compact: false,
            baseFontWeight: .semibold
        )
        let document = RichDocument(blocks: [
            RichBlock(kind: .heading3, inlines: [.text("Burger King")])
        ])
        let attributed = RichDocumentSerializer.attributedString(
            from: document,
            fontSize: 34,
            darkMode: false,
            singleLine: true,
            baseFontWeight: .semibold
        )

        XCTAssertGreaterThan(
            measuredSingleLineHeight(
                for: attributed,
                fontSize: 34,
                compact: false
            ),
            baseHeight
        )
    }

    func testTitleHeightMatchesConfiguredLineCount() {
        let expected = expectedTitleHeight(
            fontSize: 28,
            compact: true,
            baseFontWeight: .semibold,
            lineCount: 2
        )

        XCTAssertEqual(
            EditorLayoutMetrics.titleHeight(
                fontSize: 28,
                compact: true,
                baseFontWeight: .semibold,
                lineCount: 2
            ),
            expected,
            accuracy: 0.001
        )
    }

    func testTitleHeightIncreasesWithAdditionalLines() {
        let singleLine = EditorLayoutMetrics.titleHeight(
            fontSize: 32,
            compact: false,
            baseFontWeight: .bold,
            lineCount: 1
        )
        let tripleLine = EditorLayoutMetrics.titleHeight(
            fontSize: 32,
            compact: false,
            baseFontWeight: .bold,
            lineCount: 3
        )

        XCTAssertGreaterThan(tripleLine, singleLine)
    }

    func testOutlineSlideEditorKeepsSingleLineRowsCompact() {
        XCTAssertEqual(
            IdeaOutlineLayoutMetrics.editorHeight(forMeasuredHeight: 17),
            IdeaOutlineLayoutMetrics.minimumEditorHeight
        )
    }

    func testOutlineSlideEditorAllowsIntentionalMultilineRows() {
        XCTAssertEqual(
            IdeaOutlineLayoutMetrics.editorHeight(forMeasuredHeight: 52),
            52
        )

        XCTAssertEqual(
            IdeaOutlineLayoutMetrics.editorHeight(forMeasuredHeight: 140),
            IdeaOutlineLayoutMetrics.maximumEditorHeight
        )
    }

    private func expectedSingleLineHeight(
        fontSize: CGFloat,
        compact: Bool,
        baseFontWeight: NSFont.Weight
    ) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: baseFontWeight)
        let inset = EditorLayoutMetrics.singleLineVerticalInset(fontSize: fontSize, compact: compact)
        return ceil(font.ascender - font.descender + font.leading + inset * 2 + 2)
    }

    private func measuredSingleLineHeight(
        for attributedString: NSAttributedString,
        fontSize: CGFloat,
        compact: Bool
    ) -> CGFloat {
        let storage = NSTextStorage(attributedString: attributedString)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: NSSize(width: 2000, height: CGFloat.greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 1
        textContainer.lineBreakMode = NSLineBreakMode.byClipping

        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        layoutManager.ensureLayout(for: textContainer)

        let inset = EditorLayoutMetrics.singleLineVerticalInset(fontSize: fontSize, compact: compact)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return ceil(usedRect.height + inset * 2)
    }

    private func expectedTitleHeight(
        fontSize: CGFloat,
        compact: Bool,
        baseFontWeight: NSFont.Weight,
        lineCount: Int
    ) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: baseFontWeight)
        let inset = EditorLayoutMetrics.titleVerticalInset(fontSize: fontSize, compact: compact)
        return ceil((font.ascender - font.descender + font.leading) * CGFloat(max(1, lineCount)) + inset * 2 + 2)
    }
}
