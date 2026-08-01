import AppKit
import SwiftUI
import XCTest
@testable import CosmoOS

final class ThemePaletteTests: XCTestCase {
    override func tearDown() {
        DS.palette = GreenhousePalette()
        super.tearDown()
    }

    func testThemeFamiliesResolveDayAndNightFaces() {
        XCTAssertEqual(ThemeFamily.allCases, [.mono, .greenhouse])

        XCTAssertEqual(ThemeFamily.mono.lightPalette.name, "Codex Mono")
        XCTAssertFalse(ThemeFamily.mono.lightPalette.isDark)
        XCTAssertEqual(ThemeFamily.mono.darkPalette.name, "Black Mono")
        XCTAssertTrue(ThemeFamily.mono.darkPalette.isDark)

        XCTAssertEqual(ThemeFamily.greenhouse.lightPalette.name, "Greenhouse")
        XCTAssertFalse(ThemeFamily.greenhouse.lightPalette.isDark)
        XCTAssertEqual(ThemeFamily.greenhouse.darkPalette.name, "Greenhouse Night")
        XCTAssertTrue(ThemeFamily.greenhouse.darkPalette.isDark)
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

        assertColor(DS.sidebarMaterialBorder, equalsHex: "000000", alpha: 0.058)
        assertColor(DS.sidebarMaterialHighlight, equalsHex: "FFFFFF", alpha: 0.64)
        assertColor(DS.sidebarMaterialShadow, equalsHex: "000000", alpha: 0.034)
    }

    func testGlassPanelRolesUseSoftLiquidGlassShadows() {
        DS.palette = CodexMonoPalette()

        XCTAssertEqual(CosmoGlassPanelRole.globalSidebar.shadowRadius, 18, accuracy: 0.001)
        XCTAssertEqual(CosmoGlassPanelRole.globalSidebar.shadowYOffset, 6, accuracy: 0.001)
        XCTAssertEqual(CosmoGlassPanelRole.focusSidebar.shadowRadius, 12, accuracy: 0.001)
        XCTAssertEqual(CosmoGlassPanelRole.focusSidebar.shadowYOffset, 4, accuracy: 0.001)
        XCTAssertEqual(CosmoGlassPanelRole.floatingAssistant.shadowRadius, 18, accuracy: 0.001)
        XCTAssertEqual(CosmoGlassPanelRole.floatingAssistant.shadowYOffset, 6, accuracy: 0.001)
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

    func testBlackMonoUsesImmersiveDarkFocusTokens() throws {
        DS.palette = BlackMonoPalette()

        XCTAssertTrue(DS.usesImmersiveFocusAppearance)
        assertColor(DS.focusImmersiveBackground, equalsHex: "000000")
        assertColor(DS.focusImmersiveSurface, equalsHex: "0B0B0D")
        assertColor(DS.focusImmersiveSurfaceElevated, equalsHex: "101012")
        assertColor(DS.focusImmersiveText, equalsHex: "F5F5F7")
        assertColor(DS.focusImmersiveTextSecondary, equalsHex: "B7B7C0")
        assertColor(DS.focusImmersiveTextMuted, equalsHex: "7C7D86")
        assertColor(DS.focusImmersiveBorder, equalsHex: "242428")

        assertColor(DS.documentSurface, equalsHex: "FFFFFF")
        assertColor(DS.documentText, equalsHex: "1A1A1F")
    }

    func testCodexMonoDoesNotUseImmersiveFocusTokens() {
        DS.palette = CodexMonoPalette()

        XCTAssertFalse(DS.usesImmersiveFocusAppearance)
        assertColor(DS.focusImmersiveBackground, equalsHex: "FDFDFC")
        assertColor(DS.focusImmersiveText, equalsHex: "1F2024")
    }

    func testSwipeLibraryBackgroundMatchesCommandCenterRootInCodexMono() {
        DS.palette = CodexMonoPalette()

        assertColor(DS.swipeLibraryBackground, equalsHex: "FDFDFC")
        assertColor(DS.bg, equalsHex: "FDFDFC")
    }

    func testBlackMonoInvertsMonoChromeToBlackAndWhite() throws {
        let palette = BlackMonoPalette()

        assertColor(palette.bg, equalsHex: "000000")
        assertColor(palette.surface, equalsHex: "050505")
        assertColor(palette.surfaceElevated, equalsHex: "0B0B0D")
        assertColor(palette.surfaceCard, equalsHex: "101012")
        assertColor(palette.canvas, equalsHex: "000000")
        assertColor(palette.text, equalsHex: "F5F5F7")
        assertColor(palette.textSecondary, equalsHex: "B7B7C0")
        assertColor(palette.textMuted, equalsHex: "7C7D86")
        assertColor(palette.accent, equalsHex: "F5F5F7")
        assertColor(palette.textOnAccent, equalsHex: "000000")
    }

    func testBlackMonoUsesReadableDarkSpotlightGlass() throws {
        let palette = BlackMonoPalette()

        assertColor(palette.glassCardFill, equalsHex: "0B0B0D", alpha: 0.940)
        assertColor(palette.glassInputFill, equalsHex: "000000", alpha: 0.960)
        assertColor(palette.glassInputFillFocused, equalsHex: "000000", alpha: 0.985)
        assertColor(palette.glassSectionFill, equalsHex: "101012", alpha: 0.840)
        assertColor(palette.glassBorder, equalsHex: "FFFFFF", alpha: 0.120)
        assertColor(palette.glassBorderFocused, equalsHex: "FFFFFF", alpha: 0.32)
    }

    func testBlackMonoUsesNeutralOrnamentsAndLightGraySeparators() throws {
        DS.palette = BlackMonoPalette()

        assertColor(DS.gilt, equalsHex: "D9D9DF")
        assertColor(DS.giltSoft, equalsHex: "151517")
        assertColor(DS.giltMuted, equalsHex: "8F9098")
        assertColor(DS.border, equalsHex: "242428")
        assertColor(DS.borderSubtle, equalsHex: "17171A")
        assertColor(DS.borderActive, equalsHex: "F5F5F7")
    }

    func testBlackMonoUsesDarkCommandCenterSeparatorsAndReadableMastheadText() throws {
        DS.palette = BlackMonoPalette()

        assertColor(DS.commandCenterTitleText, equalsHex: "F5F5F7")
        assertColor(DS.commandCenterSecondaryText, equalsHex: "B7B7C0")
        assertColor(DS.commandCenterMutedText, equalsHex: "7C7D86")
        assertColor(DS.commandCenterOrnamentText, equalsHex: "7C7D86")
        assertColor(DS.commandCenterSeparator, equalsHex: "17171A")
        assertColor(DS.commandCenterSeparatorStrong, equalsHex: "242428")
        assertColor(DS.commandCenterSelectedRowFill, equalsHex: "101012")

        assertColor(DS.documentSepiaSubtle, equalsHex: "F5F4F0")
        assertColor(DS.documentSurface, equalsHex: "FFFFFF")
    }

    func testBlackMonoUsesDarkCommandChromeInsteadOfDocumentVellum() throws {
        DS.palette = BlackMonoPalette()

        assertColor(DS.commandChromePanelFill, equalsHex: "0B0B0D")
        assertColor(DS.commandChromeProminentFill, equalsHex: "101012")
        assertColor(DS.commandChromeBorder, equalsHex: "242428")
        assertColor(DS.commandChromeProminentBorder, equalsHex: "242428")
        assertColor(DS.commandChromeControlFill, equalsHex: "171717")
        assertColor(DS.commandChromeControlBorder, equalsHex: "242428")
        assertColor(DS.commandChromeSeparator, equalsHex: "17171A")
        assertColor(DS.commandChromeSeparatorStrong, equalsHex: "242428")

        assertColor(DS.documentSepiaSubtle, equalsHex: "F5F4F0")
        assertColor(DS.documentSepiaBorder, equalsHex: "E8E8EC")
    }

    func testBlackMonoUsesDarkDashboardReportChromeInsteadOfDocumentPaper() throws {
        DS.palette = BlackMonoPalette()

        assertColor(DashboardReportChrome.insetFill, equalsHex: "101012")
        assertColor(DashboardReportChrome.controlFill, equalsHex: "171717")
        assertColor(DashboardReportChrome.cardFill, equalsHex: "0B0B0D")
        assertColor(DashboardReportChrome.border, equalsHex: "242428")
        assertColor(DashboardReportChrome.subtleBorder, equalsHex: "242428")
        assertColor(DashboardReportChrome.primaryText, equalsHex: "F5F5F7")
        assertColor(DashboardReportChrome.secondaryText, equalsHex: "B7B7C0")
        assertColor(DashboardReportChrome.mutedText, equalsHex: "7C7D86")
        assertColor(DashboardReportChrome.heatmapEmptyFill, equalsHex: "0B0B0D")
        assertColor(DashboardReportChrome.heatmapLowFill, equalsHex: "171717")
        assertColor(DS.commandCenterRailStabilizingFill, equalsHex: "0B0B0D", alpha: 0.94)

        assertColor(DS.documentSurface, equalsHex: "FFFFFF")
        assertColor(DS.documentVellumDeep, equalsHex: "F8F7F4")
    }

    func testDashboardReportChromePreservesGreenhousePaperTreatment() {
        DS.palette = GreenhousePalette()

        assertColor(DashboardReportChrome.insetFill, equalsHex: "EDE5D8")
        assertColor(DashboardReportChrome.controlFill, equalsHex: "F3EDE4")
        assertColor(DashboardReportChrome.cardFill, equalsHex: "F5F4F0")
        assertColor(DashboardReportChrome.border, equalsHex: "DDD5C8")
        assertColor(DashboardReportChrome.subtleBorder, equalsHex: "E8E1D6")
        assertColor(DashboardReportChrome.primaryText, equalsHex: "2C2A26")
        // 757165, not the old 7A7568: the July 30 jury retune collapsed
        // inkFaded onto textMuted's rung — document ink and UI ink are ONE
        // warm ladder now (a due chip must never sit at a different grey
        // than a meta line of the same rank).
        assertColor(DashboardReportChrome.mutedText, equalsHex: "757165")
        assertColor(DashboardReportChrome.heatmapEmptyFill, equalsHex: "EDE5D8")
        assertColor(DashboardReportChrome.heatmapLowFill, equalsHex: "F5EDD8")
    }

    func testSwipeLibraryBackgroundMatchesCommandCenterRootInBlackMono() throws {
        DS.palette = BlackMonoPalette()

        assertColor(DS.swipeLibraryBackground, equalsHex: "000000")
        assertColor(DS.bg, equalsHex: "000000")
    }

    func testBlackMonoKeepsCanvasClustersBrightLikeLightMono() throws {
        DS.palette = BlackMonoPalette()

        assertColor(
            DS.canvasClusterSurfaceFill(isDropTarget: false, isUserCreated: true, usesExpandedContent: true),
            equalsHex: "FFFFFF",
            alpha: 0.038
        )
        assertColor(
            DS.canvasClusterSurfaceFill(isDropTarget: false, isUserCreated: true, usesExpandedContent: false),
            equalsHex: "FFFFFF",
            alpha: 0.032
        )
        XCTAssertEqual(
            DS.canvasClusterAccentWashOpacity(isDropTarget: false, isUserCreated: true, usesExpandedContent: true),
            0.245,
            accuracy: 0.001
        )
        XCTAssertEqual(
            DS.canvasClusterAccentWashOpacity(isDropTarget: false, isUserCreated: true, usesExpandedContent: false),
            0.215,
            accuracy: 0.001
        )
        XCTAssertEqual(
            DS.canvasClusterStrokeOpacity(isSelected: false, isHovered: false, isDropTarget: false),
            0.68,
            accuracy: 0.001
        )
    }

    func testBlackMonoUsesMonoGlobalPanelMaterialAndReadableSidebarGlass() throws {
        DS.palette = BlackMonoPalette()

        XCTAssertEqual(CosmoGlassPanelRole.globalSidebar.shadowRadius, 18, accuracy: 0.001)
        XCTAssertEqual(CosmoGlassPanelRole.globalSidebar.shadowYOffset, 6, accuracy: 0.001)

        assertColor(DS.sidebarMaterialBorder, equalsHex: "FFFFFF", alpha: 0.16)
        assertColor(DS.sidebarMaterialHighlight, equalsHex: "FFFFFF", alpha: 0.18)
        assertColor(DS.sidebarMaterialShadow, equalsHex: "000000", alpha: 0.075)
    }

    func testBlackMonoKeepsSemanticSignalColorsDifferentiated() throws {
        let palette = BlackMonoPalette()

        assertColor(palette.green, equalsHex: "3DDC84")
        assertColor(palette.orange, equalsHex: "F59E0B")
        assertColor(palette.red, equalsHex: "F87171")
        assertColor(palette.info, equalsHex: "60A5FA")
        assertColor(palette.greenSoft, equalsHex: "06170D")
        assertColor(palette.orangeSoft, equalsHex: "1A1000")
        assertColor(palette.redSoft, equalsHex: "1A0505")
        assertColor(palette.infoSoft, equalsHex: "06111F")
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
