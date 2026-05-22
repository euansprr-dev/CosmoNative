import AppKit
import SwiftUI
import XCTest
@testable import CosmoOS

final class ThemePaletteTests: XCTestCase {
    override func tearDown() {
        DS.palette = GreenhousePalette()
        super.tearDown()
    }

    func testCodexMonoThemeIsRegistered() {
        XCTAssertTrue(CosmoAppTheme.allCases.contains(.codexMono))
        XCTAssertEqual(CosmoAppTheme.codexMono.displayName, "Codex Mono")
        XCTAssertFalse(CosmoAppTheme.codexMono.isDark)
    }

    func testCodexMonoPaletteUsesPremiumMonochromeChrome() {
        let palette = CodexMonoPalette()

        assertColor(palette.bg, equalsHex: "FDFDFC")
        assertColor(palette.surface, equalsHex: "F7F7F8")
        assertColor(palette.surfaceElevated, equalsHex: "FFFFFF")
        assertColor(palette.text, equalsHex: "1F2024")
        assertColor(palette.textSecondary, equalsHex: "5F6068")
        assertColor(palette.accent, equalsHex: "1F2024")
        assertColor(palette.borderSubtle, equalsHex: "F0F0F2")
    }

    func testCodexMonoUsesLighterSpotlightStyleGlassForMenusAndSidebar() {
        let palette = CodexMonoPalette()

        assertColor(palette.surfaceHover, equalsHex: "F1F1F2")
        assertColor(palette.accentSoft, equalsHex: "F5F5F6")
        assertColor(palette.vellum, equalsHex: "FBFBFC")
        assertColor(palette.vellumDeep, equalsHex: "F4F4F5")

        assertColor(palette.glassCardFill, equalsHex: "FFFFFF", alpha: 0.950)
        assertColor(palette.glassInputFill, equalsHex: "FFFFFF", alpha: 0.970)
        assertColor(palette.glassInputFillFocused, equalsHex: "FFFFFF", alpha: 0.996)
        assertColor(palette.glassSectionFill, equalsHex: "FFFFFF", alpha: 0.860)
        assertColor(palette.glassBorder, equalsHex: "000000", alpha: 0.050)
        assertColor(palette.glassBorderFocused, equalsHex: "000000", alpha: 0.20)
    }

    func testCodexMonoUsesLighterNativeSidebarMaterialChrome() {
        DS.palette = CodexMonoPalette()

        assertColor(DS.sidebarMaterialBase, equalsHex: "FFFFFF", alpha: 0.665)
        XCTAssertEqual(DS.sidebarMaterialNativeOpacity, 0.650, accuracy: 0.001)
        assertColor(DS.sidebarMaterialFallback, equalsHex: "FFFFFF")
        assertColor(DS.sidebarMaterialBorder, equalsHex: "000000", alpha: 0.058)
        assertColor(DS.sidebarMaterialHighlight, equalsHex: "FFFFFF", alpha: 0.64)
        assertColor(DS.sidebarMaterialInnerShade, equalsHex: "000000", alpha: 0.0)
        assertColor(DS.sidebarMaterialShadow, equalsHex: "000000", alpha: 0.034)
    }

    func testCodexMonoUsesPopoverMaterialForSpotlightWeightGlobalChrome() {
        DS.palette = CodexMonoPalette()

        XCTAssertEqual(CosmoGlassPanelRole.globalSidebar.material, .popover)
    }

    func testCodexMonoGlobalPanelsUseStrongerSpotlightShadow() {
        DS.palette = CodexMonoPalette()

        XCTAssertEqual(CosmoGlassPanelRole.globalSidebar.shadowRadius, 40, accuracy: 0.001)
        XCTAssertEqual(CosmoGlassPanelRole.globalSidebar.shadowYOffset, 11, accuracy: 0.001)
        XCTAssertEqual(CosmoGlassPanelRole.globalSidebar.sideShadowOpacity, 0.074, accuracy: 0.001)
    }

    func testCodexMonoKeepsSemanticSignalColorsDifferentiated() {
        let palette = CodexMonoPalette()

        assertColor(palette.green, equalsHex: "2F7D5B")
        assertColor(palette.orange, equalsHex: "F26A3D")
        assertColor(palette.red, equalsHex: "D92D20")
        assertColor(palette.info, equalsHex: "2563EB")
        assertColor(palette.greenSoft, equalsHex: "EAF6EF")
        assertColor(palette.orangeSoft, equalsHex: "FFF1EA")
        assertColor(palette.redSoft, equalsHex: "FDEDEC")
        assertColor(palette.infoSoft, equalsHex: "EAF1FF")
    }

    func testCodexMonoKeepsDocumentSurfacesLight() {
        DS.palette = CodexMonoPalette()

        assertColor(DS.documentSurface, equalsHex: "FFFFFF")
        assertColor(DS.documentText, equalsHex: "1F2024")
        assertColor(DS.documentBorderSubtle, equalsHex: "F0F0F2")
    }

    private func assertColor(_ color: Color, equalsHex hex: String, alpha: CGFloat = 1.0, file: StaticString = #filePath, line: UInt = #line) {
        assertColor(NSColor(color), equalsHex: hex, alpha: alpha, file: file, line: line)
    }

    private func assertColor(_ color: NSColor?, equalsHex hex: String, alpha: CGFloat = 1.0, file: StaticString = #filePath, line: UInt = #line) {
        guard let rgb = color?.usingColorSpace(.sRGB) else {
            XCTFail("Expected an sRGB color", file: file, line: line)
            return
        }

        let expected = hexRGB(hex)
        XCTAssertEqual(rgb.redComponent, expected.red, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(rgb.greenComponent, expected.green, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(rgb.blueComponent, expected.blue, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(rgb.alphaComponent, alpha, accuracy: 0.001, file: file, line: line)
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
