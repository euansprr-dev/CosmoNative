import XCTest
@testable import CosmoOS

final class ContentFocusPaneLayoutPolicyTests: XCTestCase {
    func testPaneContextSuppressesMarginaliaRailsEvenWhenWideEnoughForFullLayout() {
        XCTAssertFalse(
            ContentFocusLayoutPolicy.showsMarginaliaRails(
                isPaneContext: true,
                zenMode: false,
                layoutMode: .full,
                availableWidth: 1_200
            )
        )
    }

    func testPaneImmersiveFillsPaneUsableWidth() {
        // Immersive (fraction 1) fills the pane's usable width (available − 48),
        // capped by its 1120 preset — the pane here is far narrower than that.
        let width = ContentFocusLayoutPolicy.manuscriptWidth(
            availableWidth: 720,
            preferredWritingWidth: ContentFocusModeView.WritingWidthMode.immersive.width,
            isPaneContext: true,
            zenMode: false,
            layoutMode: .regular,
            paneWidthFraction: ContentFocusModeView.WritingWidthMode.immersive.paneWidthFraction
        )

        XCTAssertEqual(width, 672)
    }

    /// The bug this fixes: in a pane narrower than the smallest preset (680),
    /// every width mode used to clamp to the same `available − 48`, so the
    /// setting did nothing. The four modes must now render distinct, increasing
    /// column widths for the same pane.
    func testPaneWidthModesProduceDistinctIncreasingWidths() {
        let paneWidth: CGFloat = 720
        func columnWidth(for mode: ContentFocusModeView.WritingWidthMode) -> CGFloat {
            ContentFocusLayoutPolicy.manuscriptWidth(
                availableWidth: paneWidth,
                preferredWritingWidth: mode.width,
                isPaneContext: true,
                zenMode: false,
                layoutMode: .regular,
                paneWidthFraction: mode.paneWidthFraction
            )
        }

        let narrow = columnWidth(for: .narrow)
        let comfort = columnWidth(for: .comfort)
        let wide = columnWidth(for: .wide)
        let immersive = columnWidth(for: .immersive)

        XCTAssertLessThan(narrow, comfort)
        XCTAssertLessThan(comfort, wide)
        XCTAssertLessThan(wide, immersive)
        // Immersive still fits inside the pane's usable width.
        XCTAssertLessThanOrEqual(immersive, paneWidth - 48)
    }

    /// When the pane is wide enough to seat a preset, the absolute preset caps
    /// the column so pane mode matches full-window measures (a preset-wide pane
    /// should not stretch `narrow` past 680).
    func testPaneWideEnoughForPresetHonoursAbsoluteWidth() {
        let width = ContentFocusLayoutPolicy.manuscriptWidth(
            availableWidth: 1_400,
            preferredWritingWidth: ContentFocusModeView.WritingWidthMode.narrow.width,
            isPaneContext: true,
            zenMode: false,
            layoutMode: .full,
            paneWidthFraction: ContentFocusModeView.WritingWidthMode.narrow.paneWidthFraction
        )

        // usable = 1352, scaled = 1352 × 0.58 ≈ 784, capped by the 680 preset.
        XCTAssertEqual(width, ContentFocusModeView.WritingWidthMode.narrow.width)
    }

    /// The owner-side twin of the pane bug: when a side pane squeezes the main
    /// Content Focus surface below the rail threshold (980), the rails hide but
    /// the old math still charged their 576pt allowance, flooring every preset
    /// at the same 360pt column — the Aa width setting did nothing. Rails-hidden
    /// must spread the modes fractionally, exactly like pane mode.
    func testSqueezedOwnerSurfaceWithHiddenRailsProducesDistinctIncreasingWidths() {
        let squeezedWidth: CGFloat = 760
        func columnWidth(for mode: ContentFocusModeView.WritingWidthMode) -> CGFloat {
            ContentFocusLayoutPolicy.manuscriptWidth(
                availableWidth: squeezedWidth,
                preferredWritingWidth: mode.width,
                isPaneContext: false,
                zenMode: false,
                layoutMode: .regular,
                paneWidthFraction: mode.paneWidthFraction
            )
        }

        let narrow = columnWidth(for: .narrow)
        let comfort = columnWidth(for: .comfort)
        let wide = columnWidth(for: .wide)
        let immersive = columnWidth(for: .immersive)

        XCTAssertLessThan(narrow, comfort)
        XCTAssertLessThan(comfort, wide)
        XCTAssertLessThan(wide, immersive)
        // Immersive fills the usable width between the outer spacers.
        XCTAssertEqual(immersive, squeezedWidth - 48)
    }

    /// A wide zen window still seats every absolute preset exactly — the
    /// fractional spread only bites when the usable band is narrower than the
    /// preset.
    func testWideZenWindowSeatsAbsolutePresets() {
        for mode in ContentFocusModeView.WritingWidthMode.allCases {
            let width = ContentFocusLayoutPolicy.manuscriptWidth(
                availableWidth: 1_600,
                preferredWritingWidth: mode.width,
                isPaneContext: false,
                zenMode: true,
                layoutMode: .full,
                paneWidthFraction: mode.paneWidthFraction
            )
            XCTAssertEqual(width, mode.width)
        }
    }

    func testFullWindowKeepsSideRailAllowance() {
        let width = ContentFocusLayoutPolicy.manuscriptWidth(
            availableWidth: 1_200,
            preferredWritingWidth: 860,
            isPaneContext: false,
            zenMode: false,
            layoutMode: .full
        )

        // Ghost margin + rail + gaps on either side of the manuscript:
        // 2 × (240 + 24) + 48 = 576 → 1200 − 576 = 624.
        XCTAssertEqual(width, 624)
    }

    func testManuscriptNeverExceedsBandScrollColumnOnVeryWideWindows() {
        let width = ContentFocusLayoutPolicy.manuscriptWidth(
            availableWidth: 2_000,
            preferredWritingWidth: 860,
            isPaneContext: false,
            zenMode: false,
            layoutMode: .full
        )

        // The band caps at 1244 (+48 outer spacers) — the manuscript must fit
        // the scroll column between the ghost margin and the rail.
        XCTAssertEqual(width, ContentFocusLayoutPolicy.scriptoriumBandMaxWidth - 2 * (ContentFocusLayoutPolicy.marginaliaRailWidth + 24))
    }

    func testZenModeDoesNotApplyDocumentWideBackgroundWash() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let focusViewURL = packageRoot.appendingPathComponent("UI/FocusMode/Content/ContentFocusModeView.swift")
        let source = try String(contentsOf: focusViewURL, encoding: .utf8)

        XCTAssertFalse(source.contains("DS.inkWash\n                .opacity(zenMode ?"))
    }

    func testZenModeDoesNotHideWordCharacterCounter() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let focusViewURL = packageRoot.appendingPathComponent("UI/FocusMode/Content/ContentFocusModeView.swift")
        let source = try String(contentsOf: focusViewURL, encoding: .utf8)

        XCTAssertFalse(source.contains(".opacity(localDraftContent.isEmpty || zenMode ? 0 : 1)"))
    }

    func testZenModePromotesTitleToFixedHeaderAndReducesEditorDeadSpace() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let focusViewURL = packageRoot.appendingPathComponent("UI/FocusMode/Content/ContentFocusModeView.swift")
        let source = try String(contentsOf: focusViewURL, encoding: .utf8)

        XCTAssertTrue(source.contains("scriptoriumFixedTitleHeader"))
        XCTAssertTrue(source.contains("manuscriptEditorHeightOffset"))
        XCTAssertTrue(source.contains("if !zenMode {\n                manuscriptTitleEditor"))
    }

    func testManuscriptTextColumnReservesCustomScrollbarGutter() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let focusViewURL = packageRoot.appendingPathComponent("UI/FocusMode/Content/ContentFocusModeView.swift")
        let source = try String(contentsOf: focusViewURL, encoding: .utf8)

        XCTAssertTrue(source.contains("manuscriptScrollbarGutter"))
        XCTAssertTrue(source.contains("let textWidth = ContentFocusLayoutPolicy.manuscriptTextWidth"))
        XCTAssertTrue(source.contains(".frame(width: textWidth, alignment: .leading)"))
        XCTAssertTrue(source.contains(".padding(.trailing, scrollbarGutter)"))
    }
}
