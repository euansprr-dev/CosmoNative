import AppKit
import XCTest
@testable import CosmoOS

@MainActor
final class RichTextPasteNormalizationTests: XCTestCase {
    func testPasteUsesCurrentTypingAttributesInsteadOfExternalRichTextFormatting() throws {
        let textView = CosmoTextView()
        let baseFont = NSFont.systemFont(ofSize: 17, weight: .regular)
        let baseColor = NSColor.labelColor
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 6

        textView.isRichText = true
        textView.font = baseFont
        textView.textColor = baseColor
        textView.typingAttributes = [
            .font: baseFont,
            .foregroundColor: baseColor,
            .paragraphStyle: paragraphStyle
        ]
        textView.textStorage?.setAttributedString(NSAttributedString(
            string: "Hello ",
            attributes: textView.typingAttributes
        ))
        textView.setSelectedRange(NSRange(location: 6, length: 0))

        let external = NSAttributedString(
            string: "tiny",
            attributes: [
                .font: NSFont.systemFont(ofSize: 7, weight: .regular),
                .foregroundColor: NSColor.systemRed
            ]
        )
        let rtfData = try external.data(
            from: NSRange(location: 0, length: external.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(rtfData, forType: .rtf)
        NSPasteboard.general.setString(external.string, forType: .string)

        textView.paste(nil)

        XCTAssertEqual(textView.string, "Hello tiny")

        let storage = try XCTUnwrap(textView.textStorage)
        let insertedRange = NSRange(location: 6, length: 4)
        storage.enumerateAttributes(in: insertedRange) { attributes, _, _ in
            guard let font = attributes[.font] as? NSFont else {
                XCTFail("Inserted text should have a font attribute")
                return
            }
            let color = attributes[.foregroundColor] as? NSColor
            XCTAssertEqual(font.pointSize, baseFont.pointSize)
            XCTAssertTrue(color?.isEqual(baseColor) == true)
            XCTAssertTrue(attributes[.paragraphStyle] is NSParagraphStyle)
        }
    }
}
