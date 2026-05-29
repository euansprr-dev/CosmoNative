import XCTest
@testable import CosmoOS

final class SidebarLayoutPolicyTests: XCTestCase {
    func testVisibleSidebarContextsUseRequestedTopLevelOrder() {
        XCTAssertEqual(
            SidebarContext.allCases.map(\.title),
            ["Home", "Command", "Inbox", "Swipe File"]
        )
    }

    func testRightClickRoutingUsesLatestSidebarWidthAfterMonitorSetup() {
        let state = MainRightClickRoutingState()
        state.updateSidebar(isHidden: false, interactionWidth: 0)

        let shouldBypassCanvasMenu = {
            state.shouldBypassCanvasMenuForSidebar(windowPoint: CGPoint(x: 180, y: 100))
        }

        XCTAssertFalse(shouldBypassCanvasMenu())

        state.updateSidebar(isHidden: false, interactionWidth: 320)

        XCTAssertTrue(shouldBypassCanvasMenu())
    }

    func testHoverRevealMakesHiddenSidebarVisibleWithoutPersistingLayoutState() {
        XCTAssertTrue(
            MainSidebarHoverRevealPolicy.isSidebarVisible(
                isSidebarHidden: true,
                isHoverRevealed: true
            )
        )
    }

    func testPersistentOpenSidebarStaysVisibleWithoutHoverReveal() {
        XCTAssertTrue(
            MainSidebarHoverRevealPolicy.isSidebarVisible(
                isSidebarHidden: false,
                isHoverRevealed: false
            )
        )
    }

    func testTransientHoverRevealClosesAfterLeavingTriggerAndPanel() {
        XCTAssertTrue(
            MainSidebarHoverRevealPolicy.shouldCloseTransientReveal(
                isSidebarHidden: true,
                isHoverRevealed: true,
                isHoveringRevealTrigger: false,
                isHoveringSidebarPanel: false
            )
        )
    }

    func testTransientHoverRevealStaysOpenWhileHoveringTriggerOrPanel() {
        XCTAssertFalse(
            MainSidebarHoverRevealPolicy.shouldCloseTransientReveal(
                isSidebarHidden: true,
                isHoverRevealed: true,
                isHoveringRevealTrigger: true,
                isHoveringSidebarPanel: false
            )
        )

        XCTAssertFalse(
            MainSidebarHoverRevealPolicy.shouldCloseTransientReveal(
                isSidebarHidden: true,
                isHoverRevealed: true,
                isHoveringRevealTrigger: false,
                isHoveringSidebarPanel: true
            )
        )
    }

    func testPersistentOpenSidebarDoesNotCloseWhenHoverLeaves() {
        XCTAssertFalse(
            MainSidebarHoverRevealPolicy.shouldCloseTransientReveal(
                isSidebarHidden: false,
                isHoverRevealed: false,
                isHoveringRevealTrigger: false,
                isHoveringSidebarPanel: false
            )
        )
    }

    func testSidebarButtonPersistsTransientHoverReveal() {
        XCTAssertTrue(
            MainSidebarButtonPolicy.shouldPersistTransientReveal(
                isSidebarHidden: true,
                isHoverRevealed: true
            )
        )
    }

    func testSidebarButtonClosesPersistentSidebar() {
        XCTAssertFalse(
            MainSidebarButtonPolicy.shouldPersistTransientReveal(
                isSidebarHidden: false,
                isHoverRevealed: false
            )
        )
    }

    func testCanvasDestinationsAllowContentBehindSidebar() {
        let inset = MainSidebarContentLayoutPolicy.contentLeadingInset(
            for: .thinkspace(id: "alpha"),
            isSidebarVisible: true,
            isSidebarHidden: false,
            isHoverRevealed: false,
            isFocusModeActive: false,
            sidebarReservedWidth: 320
        )

        XCTAssertEqual(inset, 0)
    }

    func testNonCanvasDestinationsReserveSidebarSpaceWithoutChangingShell() {
        let destinations: [SidebarDestination] = [
            .commandCenter,
            .inbox,
            .codex,
            .discover(section: .discover),
            .discover(section: .creators),
            .swipeFile(section: .all),
        ]

        for destination in destinations {
            let inset = MainSidebarContentLayoutPolicy.contentLeadingInset(
                for: destination,
                isSidebarVisible: true,
                isSidebarHidden: false,
                isHoverRevealed: false,
                isFocusModeActive: false,
                sidebarReservedWidth: 320
            )

            XCTAssertEqual(inset, 320)
        }
    }

    func testVisibleSidebarContextsUseSwipeFileTopLevelOrder() {
        XCTAssertEqual(
            SidebarContext.allCases.map(\.title),
            ["Home", "Command", "Inbox", "Swipe File"]
        )
    }

    func testTransientHoverRevealPushesCommandCenterContent() {
        let inset = MainSidebarContentLayoutPolicy.contentLeadingInset(
            for: .commandCenter,
            isSidebarVisible: true,
            isSidebarHidden: true,
            isHoverRevealed: true,
            isFocusModeActive: false,
            sidebarReservedWidth: 320
        )

        XCTAssertEqual(inset, 320)
    }

    func testPersistentCommandCenterSidebarReservesContentSpace() {
        let inset = MainSidebarContentLayoutPolicy.contentLeadingInset(
            for: .commandCenter,
            isSidebarVisible: true,
            isSidebarHidden: false,
            isHoverRevealed: false,
            isFocusModeActive: false,
            sidebarReservedWidth: 320
        )

        XCTAssertEqual(inset, 320)
    }

    func testHiddenSidebarDoesNotReserveContentSpace() {
        XCTAssertEqual(
            MainSidebarContentLayoutPolicy.contentLeadingInset(
                for: .commandCenter,
                isSidebarVisible: false,
                isSidebarHidden: true,
                isHoverRevealed: false,
                isFocusModeActive: false,
                sidebarReservedWidth: 320
            ),
            0
        )
    }

    func testFocusModeKeepsContentReservedBesideSidebar() {
        XCTAssertEqual(
            MainSidebarContentLayoutPolicy.contentLeadingInset(
                for: .thinkspace(id: "alpha"),
                isSidebarVisible: true,
                isSidebarHidden: false,
                isHoverRevealed: false,
                isFocusModeActive: true,
                sidebarReservedWidth: 320
            ),
            320
        )
    }

    func testRouteSceneSignalsFreezeDuringSidebarContentPush() {
        XCTAssertFalse(
            MainSidebarSceneSignalPolicy.shouldAcceptRouteSceneSignals(
                isContentPushAnimating: true
            )
        )
    }

    func testRouteSceneSignalsUpdateWhenSidebarContentPushIsStable() {
        XCTAssertTrue(
            MainSidebarSceneSignalPolicy.shouldAcceptRouteSceneSignals(
                isContentPushAnimating: false
            )
        )
    }

    func testMainContentPushUsesTransformInsteadOfAnimatingLayoutPadding() throws {
        let mainView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Navigation/MainView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(mainView.contains(".padding(.leading, contentPushOffset)"))
        XCTAssertTrue(mainView.contains(".offset(x: contentPushOffset)"))
    }

    func testThinkspacesSidebarHeaderMatchesContextSectionLabelTreatment() throws {
        let thinkspaceSection = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Canvas/UnifiedSidebar/SidebarThinkspaceSection.swift"),
            encoding: .utf8
        )
        let sectionHeader = try XCTUnwrap(
            thinkspaceSection.slice(
                from: "private var sectionHeader: some View",
                to: "// MARK: - New Thinkspace Row"
            )
        )

        XCTAssertTrue(sectionHeader.contains("Text(\"Thinkspaces\")"))
        XCTAssertTrue(sectionHeader.contains(".font(.system(size: 10, weight: .semibold))"))
        XCTAssertTrue(sectionHeader.contains(".textCase(.uppercase)"))
        XCTAssertTrue(sectionHeader.contains(".foregroundStyle(DS.textMuted)"))
        XCTAssertTrue(sectionHeader.contains(".padding(.horizontal, 8)"))
        XCTAssertTrue(sectionHeader.contains(".padding(.top, 4)"))
    }

    func testContentFocusSidebarSurfacesDoNotHardTruncateWritingContext() throws {
        let contentFocusView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("UI/FocusMode/Content/ContentFocusModeView.swift"),
            encoding: .utf8
        )
        let sidebarContent = try String(
            contentsOf: repositoryRoot.appendingPathComponent("UI/FocusMode/Content/ContentOutlineSidebarContent.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(
            contentFocusView.contains("ForEach(Array(viewModel.state.hooks.prefix(3).enumerated())")
        )
        XCTAssertFalse(contentFocusView.contains("ForEach(supportingSwipeAtoms.prefix(3)"))
        XCTAssertFalse(contentFocusView.contains(".lineLimit(coreIdeaExpanded ? nil : 4)"))

        XCTAssertFalse(sidebarContent.contains(".lineLimit(3)"))
        XCTAssertFalse(sidebarContent.contains(".lineLimit(4)"))
        XCTAssertFalse(sidebarContent.contains("swipes.prefix(3)"))
        XCTAssertFalse(sidebarContent.contains("inheritedConnectionAtoms.prefix(3)"))
    }

    func testFocusModeSwipeAndBlueprintClicksOpenPaneWhenRequested() throws {
        let mainView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Navigation/MainView.swift"),
            encoding: .utf8
        )
        let ideaFocusView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("UI/FocusMode/Ideas/IdeaFocusModeView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(mainView.contains("let shouldOpenAsPane = notification.userInfo?[\"asPane\"] as? Bool == true"))
        XCTAssertTrue(mainView.contains("handleOpenBlockInFocusMode("))
        XCTAssertTrue(mainView.contains("asPane: shouldOpenAsPane"))
        XCTAssertTrue(mainView.contains("if asPane {"))
        XCTAssertTrue(mainView.contains("paneManager.openPane(.entity(EntitySelection(id: entityId, type: entityType)))"))
        XCTAssertTrue(ideaFocusView.contains("openAtomInPane(blueprint.uuid)"))
    }

    func testContentFocusMarginaliaRailsUseIndependentSmallScrollbars() throws {
        let contentFocusView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("UI/FocusMode/Content/ContentFocusModeView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(contentFocusView.contains("@State private var leftMarginScrollMetrics = ManuscriptScrollMetrics()"))
        XCTAssertTrue(contentFocusView.contains("@State private var rightMarginScrollMetrics = ManuscriptScrollMetrics()"))
        XCTAssertTrue(contentFocusView.contains("private func scriptoriumMarginScroll<Content: View>("))
        XCTAssertTrue(contentFocusView.contains("ScrollView {\n            content()"))
        XCTAssertTrue(contentFocusView.contains("PremiumManuscriptScrollbar(metrics: metrics.wrappedValue)"))
        XCTAssertTrue(contentFocusView.contains("scriptoriumMarginScroll(width: 260"))
        XCTAssertTrue(contentFocusView.contains("scriptoriumMarginScroll(width: 220"))
        XCTAssertTrue(contentFocusView.contains(".scrollIndicators(.hidden)"))
    }

    func testIdeaFocusHooksUseMultilineEditorsForSavedAndDraftHooks() throws {
        let ideaFocusView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("UI/FocusMode/Ideas/IdeaFocusModeView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(ideaFocusView.contains("private struct HookLineEditor: NSViewRepresentable"))
        XCTAssertTrue(ideaFocusView.contains("HookLineEditor("))
        XCTAssertTrue(ideaFocusView.contains("let isShiftReturn"))
        XCTAssertTrue(ideaFocusView.contains("insertText(\"\\n\", replacementRange: selectedRange())"))
        XCTAssertFalse(ideaFocusView.contains("TextField(\"add another\", text: $newHookText)"))
        XCTAssertFalse(ideaFocusView.contains("Text(hook)\n                .font(DS.callout)"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private extension String {
    func slice(from startMarker: String, to endMarker: String) -> String? {
        guard
            let startRange = range(of: startMarker),
            let endRange = range(of: endMarker, range: startRange.upperBound..<endIndex)
        else {
            return nil
        }

        return String(self[startRange.lowerBound..<endRange.lowerBound])
    }
}
