import AppKit
import SwiftUI
import XCTest
@testable import CosmoOS

final class DocumentPaperThemeTests: XCTestCase {
    override func tearDown() {
        DS.palette = GreenhousePalette()
        super.tearDown()
    }

    func testObsidianKeepsDocumentPaperWhiteWithLightThemeInk() {
        DS.palette = ObsidianPalette()

        assertColor(DS.documentSurface, equalsHex: "FFFFFF")
        assertColor(DS.documentText, equalsHex: "1A1A1F")
        assertColor(DS.documentTextSecondary, equalsHex: "6B6B78")
        assertColor(DS.documentBorderSubtle, equalsHex: "E8E8EC")
    }

    func testDarkThemesKeepVellumConnectionSurfacesLight() {
        DS.palette = MidnightStudyPalette()

        assertColor(DS.vellum, equalsHex: "F3EDE4")
        assertColor(DS.vellumDeep, equalsHex: "EDE5D8")
        assertColor(DS.inkWash, equalsHex: "2C2A26")
        assertColor(DS.inkFaded, equalsHex: "7A7568")
    }

    func testRichDocumentLightModeUsesDocumentInkInDarkTheme() {
        DS.palette = ObsidianPalette()
        let document = RichDocument(blocks: [
            RichBlock(kind: .paragraph, inlines: [.text("Paper text")])
        ])

        let attributed = RichDocumentSerializer.attributedString(
            from: document,
            fontSize: 16,
            darkMode: false
        )

        let color = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        assertColor(color, equalsHex: "1A1A1F")
    }

    private func assertColor(_ color: Color, equalsHex hex: String, file: StaticString = #filePath, line: UInt = #line) {
        assertColor(NSColor(color), equalsHex: hex, file: file, line: line)
    }

    private func assertColor(_ color: NSColor?, equalsHex hex: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let rgb = color?.usingColorSpace(.sRGB) else {
            XCTFail("Expected an sRGB color", file: file, line: line)
            return
        }

        let expected = hexRGB(hex)
        XCTAssertEqual(rgb.redComponent, expected.red, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(rgb.greenComponent, expected.green, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(rgb.blueComponent, expected.blue, accuracy: 0.001, file: file, line: line)
    }

    private func hexRGB(_ hex: String) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        return (
            CGFloat((value >> 16) & 0xFF) / 255,
            CGFloat((value >> 8) & 0xFF) / 255,
            CGFloat(value & 0xFF) / 255
        )
    }
}
