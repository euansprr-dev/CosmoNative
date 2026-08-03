import SwiftUI
import XCTest
@testable import CosmoOS

/// Guards the observable-palette theme architecture: theme swaps re-render
/// token-wearing views IN PLACE (Observation through ThemePaletteStore), and
/// the app root never again nukes the whole tree's identity per switch.
final class ThemeObservationTests: XCTestCase {
    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    override func tearDown() {
        DS.palette = GreenhousePalette()
        super.tearDown()
    }

    // MARK: - Observation mechanics

    func testReadingAColorTokenRegistersAPaletteDependency() {
        DS.palette = GreenhousePalette()

        let fired = expectation(description: "palette swap fires observation")
        withObservationTracking {
            _ = DS.accent
        } onChange: {
            fired.fulfill()
        }

        DS.palette = BlackMonoPalette()
        wait(for: [fired], timeout: 1.0)
        XCTAssertEqual(DS.palette.name, "Black Mono")
    }

    func testReadingADerivedDocumentTokenRegistersAPaletteDependency() {
        DS.palette = GreenhousePalette()

        // Derived tokens branch on palette identity internally — they must
        // still route every read through the store, never a cached snapshot.
        let fired = expectation(description: "derived token read fires observation")
        withObservationTracking {
            _ = DS.documentText
        } onChange: {
            fired.fulfill()
        }

        DS.palette = GreenhouseNightPalette()
        wait(for: [fired], timeout: 1.0)
    }

    func testPaletteSetterForwardsToTheStore() {
        DS.palette = CodexMonoPalette()
        XCTAssertEqual(ThemePaletteStore.shared.palette.name, "Codex Mono")
        XCTAssertEqual(DS.palette.name, "Codex Mono")
    }

    // MARK: - Source pins

    /// The app root must never regain the `.id(themeRefreshID)` tree nuke —
    /// it destroyed every @State per theme switch (canvas unmounted, ⌘K index
    /// rebuilt, panes closed). Only the color scheme flips at the root.
    func testAppRootDoesNotNukeTreeIdentityOnThemeChange() throws {
        let source = try String(
            contentsOf: packageRoot.appendingPathComponent("Core/CosmoApp.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(
            source.contains("themeRefreshID"),
            "CosmoApp must not regenerate MainView identity on theme change"
        )
        XCTAssertTrue(
            source.contains(".preferredColorScheme"),
            "CosmoApp must keep driving the color scheme from the theme"
        )
    }

    /// The flagship editor bakes palette ink at setup (textColor and
    /// insertionPointColor set once; hydration passes are diff-aware no-ops),
    /// so it is the one subtree that still recreates on a theme swap.
    func testFlagshipEditorRecreatesOnThemeChange() throws {
        let source = try String(
            contentsOf: packageRoot.appendingPathComponent("Editor/CosmoDocumentEditor.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(
            source.contains(".recreateOnThemeChange()"),
            "CosmoDocumentEditor must remake its TextKit stack when the palette swaps"
        )
    }

    /// The grain texture polarity is keyed on isDark and used to ride the
    /// app-root nuke's re-mount; it must now regenerate itself.
    func testFilmGrainRegeneratesOnThemeChange() throws {
        let source = try String(
            contentsOf: packageRoot.appendingPathComponent("Core/FilmGrainOverlay.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(
            source.contains("CosmoNotification.Theme.changed"),
            "FilmGrainOverlay must regenerate its texture on theme change"
        )
    }

    /// Theme.changed must keep posting — the floating NSPanel controllers and
    /// FilmGrainOverlay refresh over the notification, not Observation.
    func testThemeManagerStillPostsThemeChanged() throws {
        let source = try String(
            contentsOf: packageRoot.appendingPathComponent("Core/Theming/ThemeManager.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(
            source.contains("NotificationCenter.default.post(name: CosmoNotification.Theme.changed"),
            "ThemeManager must keep posting Theme.changed for AppKit-side observers"
        )
    }
}
