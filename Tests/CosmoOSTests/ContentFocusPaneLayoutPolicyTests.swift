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

    func testPaneContextUsesPaneWidthForManuscriptInsteadOfFullWindowRailBudget() {
        let width = ContentFocusLayoutPolicy.manuscriptWidth(
            availableWidth: 720,
            preferredWritingWidth: 860,
            isPaneContext: true,
            zenMode: false,
            layoutMode: .regular
        )

        XCTAssertEqual(width, 672)
    }

    func testFullWindowKeepsSideRailAllowance() {
        let width = ContentFocusLayoutPolicy.manuscriptWidth(
            availableWidth: 1_200,
            preferredWritingWidth: 860,
            isPaneContext: false,
            zenMode: false,
            layoutMode: .full
        )

        XCTAssertEqual(width, 620)
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
