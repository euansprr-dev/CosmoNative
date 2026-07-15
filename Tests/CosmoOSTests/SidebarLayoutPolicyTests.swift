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

    func testContentFocusDoesNotReintroduceLegacyTruncationPatterns() throws {
        // The legacy collapsible sidebar (ContentOutlineSidebarContent) was removed
        // in the Scriptorium V2 pass. Content outline marginalia may clamp, but
        // expansion must be an explicit slide-number disclosure rather than a
        // hidden focus side effect. These guards keep old truncation idioms from
        // coming back.
        let contentFocusView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("UI/FocusMode/Content/ContentFocusModeView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(
            contentFocusView.contains("ForEach(Array(viewModel.state.hooks.prefix(3).enumerated())")
        )
        XCTAssertFalse(contentFocusView.contains("ForEach(supportingSwipeAtoms.prefix(3)"))
        XCTAssertFalse(contentFocusView.contains(".lineLimit(coreIdeaExpanded ? nil : 4)"))
        XCTAssertFalse(contentFocusView.contains(".lineLimit(focusedOutlineItemID == item.id ? nil : 2)"))
        XCTAssertFalse(contentFocusView.contains("ContentOutlineSidebarContent"))
    }

    func testContentFocusOutlineUsesSlideNumberDisclosureForExpansion() throws {
        let contentFocusView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("UI/FocusMode/Content/ContentFocusModeView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(contentFocusView.contains("@State private var expandedOutlineItemIDs: Set<UUID> = []"))
        XCTAssertTrue(contentFocusView.contains("@State private var hoveredOutlineItemID: UUID?"))
        XCTAssertTrue(contentFocusView.contains("toggleOutlineItemExpansion(item.id)"))
        XCTAssertTrue(contentFocusView.contains("ContentOutlineMarginaliaExpansionPolicy.lineLimit"))
        XCTAssertTrue(contentFocusView.contains("private func toggleOutlineItemExpansion(_ id: UUID)"))
        XCTAssertTrue(contentFocusView.contains("hoveredOutlineItemID = hovering ? item.id : nil"))
        XCTAssertTrue(contentFocusView.contains(".frame(width: 24, height: 24, alignment: .topLeading)"))
    }

    func testContentOutlineMarginaliaExpansionPolicyTogglesOneSlideAtATime() {
        let firstID = UUID()
        let secondID = UUID()

        var expanded = ContentOutlineMarginaliaExpansionPolicy.toggled(firstID, in: [])

        XCTAssertTrue(expanded.contains(firstID))
        XCTAssertFalse(expanded.contains(secondID))
        XCTAssertNil(ContentOutlineMarginaliaExpansionPolicy.lineLimit(for: firstID, expandedIDs: expanded))
        XCTAssertEqual(ContentOutlineMarginaliaExpansionPolicy.lineLimit(for: secondID, expandedIDs: expanded), 2)

        expanded = ContentOutlineMarginaliaExpansionPolicy.toggled(firstID, in: expanded)

        XCTAssertFalse(expanded.contains(firstID))
        XCTAssertEqual(ContentOutlineMarginaliaExpansionPolicy.lineLimit(for: firstID, expandedIDs: expanded), 2)
    }

    func testInboxQueueStaysFreeOfDashboardChrome() throws {
        // June 2026 rebuild: the stats bar, filter rows, and intelligence
        // groups were retired with the old dashboard UI. Guard against them
        // creeping back into the queue's supporting types.
        let inboxTypes = try String(
            contentsOf: repositoryRoot.appendingPathComponent("UI/Inbox/InboxTypes.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(inboxTypes.contains("struct InboxStats"))
        XCTAssertFalse(inboxTypes.contains("enum InboxSortOrder"))
        XCTAssertFalse(inboxTypes.contains("struct InboxItemGroup"))

        // The view model owns the only derived count the masthead needs.
        let viewModel = try String(
            contentsOf: repositoryRoot.appendingPathComponent("UI/Inbox/InboxViewModel.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(viewModel.contains("var suggestedCount: Int"))
        XCTAssertFalse(viewModel.contains("unplacedDatabaseItems"))
    }

    func testFocusModeSwipeAndBlueprintClicksOpenPaneWhenRequested() throws {
        let mainView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Navigation/MainView.swift"),
            encoding: .utf8
        )
        let ideaInspectorView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("UI/FocusMode/Ideas/IdeaInspectorView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(mainView.contains("let shouldOpenAsPane = notification.userInfo?[\"asPane\"] as? Bool == true"))
        XCTAssertTrue(mainView.contains("handleOpenBlockInFocusMode("))
        XCTAssertTrue(mainView.contains("asPane: shouldOpenAsPane"))
        XCTAssertTrue(mainView.contains("if asPane {"))
        XCTAssertTrue(mainView.contains("paneManager.openPane(.entity(EntitySelection(id: entityId, type: entityType)))"))
        // Idea v3 (July 2026): the blueprint panel was removed with the
        // framework/research rail; swipe rows keep routing pane-opens
        // through IdeaWorkspaceActions back to the host's openAtomInPane.
        XCTAssertTrue(ideaInspectorView.contains("onOpenAtomInPane(swipe.uuid)"))
        XCTAssertFalse(ideaInspectorView.contains("onOpenAtomInPane(blueprint.uuid)"))
    }

    func testBrowserPaneOpenDismissesCommandK() throws {
        let mainView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Navigation/MainView.swift"),
            encoding: .utf8
        )
        guard let observerRange = mainView.range(of: "CosmoNotification.Navigation.openWebBrowserPane") else {
            XCTFail("MainView must observe browser pane requests")
            return
        }
        guard let nextObserverRange = mainView[observerRange.upperBound...].range(of: ".onReceive") else {
            XCTFail("Browser pane observer should be followed by another notification observer")
            return
        }

        let observerBody = mainView[observerRange.lowerBound..<nextObserverRange.lowerBound]

        XCTAssertTrue(observerBody.contains("showCommandK || commandKBehindFocusMode"))
        XCTAssertTrue(observerBody.contains("closeCommandK()"))
        XCTAssertFalse(
            observerBody.contains("if didOpenOrActivateBrowserPane, showCommandK || commandKBehindFocusMode"),
            "Browser pane requests from Command-K must always dismiss Command-K; missed pane activation should not leave an invisible overlay/focus trap."
        )
    }

    func testCloseCommandKClearsFocusedCommandKResponderBeforeDismissal() throws {
        let mainView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Navigation/MainView.swift"),
            encoding: .utf8
        )
        guard let closeRange = mainView.range(of: "private func closeCommandK(clearViewModel: Bool = true)") else {
            XCTFail("MainView should centralize Command-K dismissal in closeCommandK")
            return
        }
        guard let nextFunctionRange = mainView[closeRange.upperBound...].range(of: "private func preserveCommandKBehindFocusMode") else {
            XCTFail("closeCommandK should be followed by preserveCommandKBehindFocusMode")
            return
        }

        let closeBody = mainView[closeRange.lowerBound..<nextFunctionRange.lowerBound]

        XCTAssertTrue(closeBody.contains("if showCommandK"))
        XCTAssertTrue(closeBody.contains("FocusModeEditorBlur.clearFirstResponder(in: NSApp.keyWindow)"))
        XCTAssertLessThan(
            try XCTUnwrap(closeBody.range(of: "FocusModeEditorBlur.clearFirstResponder(in: NSApp.keyWindow)")?.lowerBound),
            try XCTUnwrap(closeBody.range(of: "applyCommandKPresentation(.close")?.lowerBound)
        )
    }

    func testHiddenCommandKDoesNotKeepFullScreenHostMountedAbovePanes() throws {
        let mainView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Navigation/MainView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            mainView.contains("if showCommandK {\n                    CommandKView("),
            "Only the visible Command-K presentation should mount the full-window CommandKView host."
        )
        XCTAssertFalse(
            mainView.contains("if showCommandK || commandKBehindFocusMode {\n                    CommandKView("),
            "Preserving Command-K behind focus mode must not preserve a full-screen invisible host above browser panes."
        )
        XCTAssertTrue(
            mainView.contains("\n            .allowsHitTesting(showCommandK)\n            .zIndex(200)"),
            "The Command-K hit-test gate must live on the persistent wrapper outside the conditional — a gate inside the branch goes stale during the removal transition and a stranded snapshot swallows every click (dead-clicks-after-dismiss bug)."
        )
        XCTAssertFalse(
            mainView.contains(".animation(.spring(response: 0.3, dampingFraction: 0.8), value: showCommandK)"),
            "Command-K insert/removal must have a single animation driver (applyCommandKPresentation's withAnimation); a competing implicit driver can interrupt the removal transition and strand the click-catching snapshot."
        )
    }

    func testAsyncNavigationFetchesCancelAndIgnoreStaleResults() throws {
        let mainView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Navigation/MainView.swift"),
            encoding: .utf8
        )
        let paneContentView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Navigation/PaneContentView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(mainView.contains("@State private var focusModeNavigationTask: Task<Void, Never>?"))
        XCTAssertTrue(mainView.contains("@State private var focusModeNavigationRequestID = UUID()"))
        XCTAssertTrue(mainView.contains("@State private var thinkspaceSwitchTask: Task<Void, Never>?"))
        XCTAssertTrue(mainView.contains("@State private var thinkspaceSwitchRequestID = UUID()"))
        XCTAssertTrue(mainView.contains("@State private var creatorProfileLoadTask: Task<Void, Never>?"))
        XCTAssertTrue(mainView.contains("@State private var creatorProfileLoadRequestID = UUID()"))

        let focusNavigation = try XCTUnwrap(
            mainView.slice(
                from: "private func handleOpenBlockInFocusMode(",
                to: "private func recordFocusModeAccess"
            )
        )
        XCTAssertTrue(focusNavigation.contains("focusModeNavigationTask?.cancel()"))
        XCTAssertTrue(focusNavigation.contains("let requestID = UUID()"))
        XCTAssertTrue(focusNavigation.contains("focusModeNavigationRequestID = requestID"))
        XCTAssertTrue(focusNavigation.contains("guard focusModeNavigationRequestID == requestID, !Task.isCancelled else { return }"))

        let thinkspaceSwitch = try XCTUnwrap(
            mainView.slice(
                from: ".onReceive(NotificationCenter.default.publisher(for: .switchToThinkspace))",
                to: ".onReceive(NotificationCenter.default.publisher(for: Notification.Name(\"openCreatorDatabase\")))"
            )
        )
        XCTAssertTrue(thinkspaceSwitch.contains("thinkspaceSwitchTask?.cancel()"))
        XCTAssertTrue(thinkspaceSwitch.contains("let requestID = UUID()"))
        XCTAssertTrue(thinkspaceSwitch.contains("thinkspaceSwitchRequestID = requestID"))
        XCTAssertTrue(thinkspaceSwitch.contains("guard thinkspaceSwitchRequestID == requestID, !Task.isCancelled else { return }"))

        let creatorProfile = try XCTUnwrap(
            mainView.slice(
                from: ".onReceive(NotificationCenter.default.publisher(for: Notification.Name(\"openCreatorProfile\")))",
                to: ".animation(.spring(response: 0.25, dampingFraction: 0.85), value: showCreatorDatabase)"
            )
        )
        XCTAssertTrue(creatorProfile.contains("creatorProfileLoadTask?.cancel()"))
        XCTAssertTrue(creatorProfile.contains("let requestID = UUID()"))
        XCTAssertTrue(creatorProfile.contains("creatorProfileLoadRequestID = requestID"))
        XCTAssertTrue(creatorProfile.contains("guard creatorProfileLoadRequestID == requestID, !Task.isCancelled else { return }"))

        XCTAssertTrue(paneContentView.contains("guard !Task.isCancelled else { return }"))
    }

    func testCommandKNavigationPostsAreCancellableAndStaleGuarded() throws {
        let mainView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Navigation/MainView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(mainView.contains("@State private var commandKNavigationTask: Task<Void, Never>?"))
        XCTAssertTrue(mainView.contains("@State private var commandKNavigationRequestID = UUID()"))

        let openAtom = try XCTUnwrap(
            mainView.slice(
                from: "private func handleOpenAtomFromCommandK(atomUUID: String)",
                to: "private func handleGoToObjectFromCommandK(atomUUID: String)"
            )
        )
        XCTAssertTrue(openAtom.contains("commandKNavigationTask?.cancel()"))
        // July 2026: the open is delegated to FocusNavigationCoordinator, which
        // preloads the atom before presenting (no artificial delay) and owns
        // cancellation + staleness for every focus-mode entry.
        XCTAssertTrue(openAtom.contains("FocusNavigationCoordinator.shared.open(atomUUID: atomUUID)"))
        XCTAssertFalse(openAtom.contains("Task.sleep"))
        XCTAssertFalse(openAtom.contains("DispatchQueue.main.asyncAfter"))

        let coordinator = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Navigation/FocusNavigationCoordinator.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(coordinator.contains("openTask?.cancel()"))
        XCTAssertTrue(coordinator.contains("guard requestID == request, !Task.isCancelled else { return }"))

        let goToObject = try XCTUnwrap(
            mainView.slice(
                from: "private func handleGoToObjectFromCommandK(atomUUID: String)",
                to: "private func mapAtomTypeToEntityType"
            )
        )
        XCTAssertTrue(goToObject.contains("commandKNavigationTask?.cancel()"))
        XCTAssertTrue(goToObject.contains("let requestID = UUID()"))
        XCTAssertTrue(goToObject.contains("commandKNavigationRequestID = requestID"))
        XCTAssertTrue(goToObject.contains("try await Task.sleep(for: .milliseconds(350))"))
        XCTAssertTrue(goToObject.contains("guard commandKNavigationRequestID == requestID, !Task.isCancelled else { return }"))
        XCTAssertFalse(goToObject.contains("DispatchQueue.main.asyncAfter"))
        // June 2026: unplaced atoms open in focus mode — the inbox shows only
        // explicit captures, never database objects.
        XCTAssertTrue(goToObject.contains(".enterFocusMode"))
        XCTAssertFalse(goToObject.contains("focusDatabaseItem"))
    }

    func testThinkspaceDestinationSwitchesCancelBeforePublishingStaleCanvasChanges() throws {
        let mainView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Navigation/MainView.swift"),
            encoding: .utf8
        )
        let manager = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Canvas/ThinkspaceManager.swift"),
            encoding: .utf8
        )

        let destinationChange = try XCTUnwrap(
            mainView.slice(
                from: ".onChange(of: currentDestination)",
                to: ".onReceive(NotificationCenter.default.publisher(for: .addSwipeToCanvas))"
            )
        )
        XCTAssertTrue(destinationChange.contains("switchToThinkspaceForDestination(id: id)"))
        XCTAssertFalse(destinationChange.contains("Task { await thinkspaceManager.switchTo(ts) }"))

        let helper = try XCTUnwrap(
            mainView.slice(
                from: "private func switchToThinkspaceForDestination(id: String)",
                to: "private func updateSidebarInteractionWidth"
            )
        )
        XCTAssertTrue(helper.contains("guard thinkspaceManager.currentThinkspace?.id != id else { return }"))
        XCTAssertTrue(helper.contains("thinkspaceSwitchTask?.cancel()"))
        XCTAssertTrue(helper.contains("let requestID = UUID()"))
        XCTAssertTrue(helper.contains("thinkspaceSwitchRequestID = requestID"))
        XCTAssertTrue(helper.contains("guard thinkspaceSwitchRequestID == requestID, !Task.isCancelled else { return }"))

        let switchTo = try XCTUnwrap(
            manager.slice(
                from: "func switchTo(_ thinkspace: Thinkspace) async",
                to: "func switchToDefault()"
            )
        )
        XCTAssertTrue(switchTo.contains("guard !Task.isCancelled else { return }"))
        let publishGuardRange = try XCTUnwrap(switchTo.range(of: "guard !Task.isCancelled else { return }"))
        let publishRange = try XCTUnwrap(
            switchTo.range(
                of: "currentThinkspace = thinkspace",
                range: publishGuardRange.upperBound..<switchTo.endIndex
            )
        )
        XCTAssertLessThan(publishGuardRange.lowerBound, publishRange.lowerBound)
    }

    func testThinkspaceSwitchPublishesCanvasBeforeLastOpenedPersistence() throws {
        let manager = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Canvas/ThinkspaceManager.swift"),
            encoding: .utf8
        )
        let switchTo = try XCTUnwrap(
            manager.slice(
                from: "func switchTo(_ thinkspace: Thinkspace) async",
                to: "func switchToDefault()"
            )
        )

        let publishRange = try XCTUnwrap(
            switchTo.range(
                of: "currentThinkspace = thinkspace"
            )
        )
        let canvasNotificationRange = try XCTUnwrap(
            switchTo.range(
                of: "name: CosmoNotification.Canvas.thinkspaceChanged"
            )
        )
        let persistenceRange = try XCTUnwrap(
            switchTo.range(
                of: "await updateLastOpened(thinkspace)"
            )
        )
        // The Deep Dive profile resolution is a DB round-trip (it can even
        // create the profile atom) — it must trail the published route, never
        // gate it.
        let profileResolutionRange = try XCTUnwrap(
            switchTo.range(
                of: "resolveDeepDiveProfile"
            )
        )

        XCTAssertLessThan(publishRange.lowerBound, persistenceRange.lowerBound)
        XCTAssertLessThan(canvasNotificationRange.lowerBound, persistenceRange.lowerBound)
        XCTAssertLessThan(canvasNotificationRange.lowerBound, profileResolutionRange.lowerBound)
    }

    func testThinkspaceSwitchShowsCachedSnapshotBeforeAuthoritativeLoad() throws {
        let canvasView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Canvas/CanvasView.swift"),
            encoding: .utf8
        )
        let switchHandler = try XCTUnwrap(
            canvasView.slice(
                from: ".onChange(of: thinkspaceId)",
                to: "// Keyboard handler for ESC"
            )
        )

        XCTAssertTrue(switchHandler.contains("let cachedThinkspaceSnapshotApplied = applyCachedThinkspaceSnapshot(for: newId)"))
        XCTAssertTrue(switchHandler.contains("if cachedThinkspaceSnapshotApplied {"))

        let fastPath = try XCTUnwrap(
            switchHandler.slice(
                from: "if cachedThinkspaceSnapshotApplied {",
                to: "spatialEngine.applyFetchedBlocks("
            )
        )
        XCTAssertTrue(fastPath.contains("animateThinkspaceContentIn()"))
        XCTAssertFalse(fastPath.contains("spatialEngine.blocks = []"))

        let fastPathEntryRange = try XCTUnwrap(
            switchHandler.range(of: "if cachedThinkspaceSnapshotApplied {")
        )
        let authoritativeApplyRange = try XCTUnwrap(
            switchHandler.range(of: "spatialEngine.applyFetchedBlocks(")
        )
        XCTAssertLessThan(fastPathEntryRange.lowerBound, authoritativeApplyRange.lowerBound)
    }

    func testThinkspaceDrawingLoadsIgnoreStaleSwitchResults() throws {
        let drawingState = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Canvas/Drawing/DrawingStateManager.swift"),
            encoding: .utf8
        )
        let loadDrawings = try XCTUnwrap(
            drawingState.slice(
                from: "func loadDrawings(thinkspaceId: String?)",
                to: "// MARK: - Selection"
            )
        )

        let staleGuardRange = try XCTUnwrap(loadDrawings.range(of: "guard self.currentThinkspaceId == thinkspaceId else { return }"))
        let publishRange = try XCTUnwrap(loadDrawings.range(of: "self.drawings = records.map { CanvasDrawing(from: $0) }"))
        XCTAssertLessThan(staleGuardRange.lowerBound, publishRange.lowerBound)
    }

    func testThinkspaceBlockLoadsIgnoreCancelledSwitchResults() throws {
        let spatialEngine = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Canvas/SpatialEngine.swift"),
            encoding: .utf8
        )
        let loadBlocks = try XCTUnwrap(
            spatialEngine.slice(
                from: "func loadBlocks(for documentType: String = \"home\", documentId: Int64 = 0, thinkspaceId: String? = nil) async",
                to: "// MARK: - Save Block to Database"
            )
        )

        let cancellationGuardRange = try XCTUnwrap(loadBlocks.range(of: "guard let deduped, !Task.isCancelled, thinkspaceId == currentThinkspaceId else {"))
        let publishRange = try XCTUnwrap(loadBlocks.range(of: "self.blocks = deduped"))
        XCTAssertLessThan(cancellationGuardRange.lowerBound, publishRange.lowerBound)
    }

    func testSwipeStudyAutoTranscriptionProgressPublishesOnMainActor() throws {
        // The auto-transcription pipeline moved to SwipeStudyModel in the
        // July 2026 rebuild; the pins follow the code.
        let swipeStudy = try String(
            contentsOf: repositoryRoot.appendingPathComponent("UI/FocusMode/SwipeStudy/SwipeStudyModel.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(swipeStudy.contains("private func publishAutoTranscriptionProgress(_ message: String, expectedUUID: String)"))
        XCTAssertTrue(swipeStudy.contains("Task { @MainActor in"))
        XCTAssertTrue(swipeStudy.contains("guard autoTranscriptionProgress != message else { return }"))

        let videoProgress = try XCTUnwrap(
            swipeStudy.slice(
                from: "let result = await InstagramAutoTranscriber.shared.transcribe(",
                to: "guard isViewingAtom(uuid: expectedUUID) else { return }"
            )
        )
        XCTAssertTrue(videoProgress.contains("publishAutoTranscriptionProgress("))
        XCTAssertFalse(videoProgress.contains("self.autoTranscriptionProgress ="))

        let carouselProgress = try XCTUnwrap(
            swipeStudy.slice(
                from: "let result = await InstagramAutoTranscriber.shared.transcribeCarousel(",
                to: "guard isViewingAtom(uuid: expectedUUID) else { return }"
            )
        )
        XCTAssertTrue(carouselProgress.contains("publishAutoTranscriptionProgress("))
        XCTAssertFalse(carouselProgress.contains("self.autoTranscriptionProgress ="))
    }

    func testCanvasOpenEntityFocusesExistingBlocksBeforeFetchingAtomMetadata() throws {
        let canvasView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Canvas/CanvasView.swift"),
            encoding: .utf8
        )

        let notificationHandler = try XCTUnwrap(
            canvasView.slice(
                from: "private func handleOpenEntityOnCanvas(notification: Notification)",
                to: "private func openOrCreateBlock("
            )
        )
        let directPath = try XCTUnwrap(
            notificationHandler.slice(
                from: "if let entityType = userInfo[\"type\"] as? EntityType",
                to: "// Path 2: atomUUID"
            )
        )
        XCTAssertFalse(directPath.contains("AtomRepository.shared.fetch(id: entityId)"))
        XCTAssertTrue(directPath.contains("await openOrCreateBlock(entityType: entityType, entityId: entityId)"))

        let openOrCreate = try XCTUnwrap(
            canvasView.slice(
                from: "private func openOrCreateBlock(",
                to: "// MARK: - Cmd+V Paste to Canvas"
            )
        )
        let existingReturn = try XCTUnwrap(openOrCreate.range(of: "return\n        }\n\n        let resolvedAtom"))
        let metadataFetch = try XCTUnwrap(openOrCreate.range(of: "AtomRepository.shared.fetch(id: entityId)"))
        XCTAssertLessThan(existingReturn.lowerBound, metadataFetch.lowerBound)
    }

    func testContentFocusMarginaliaRailsScrollSilentlyWithSingleManuscriptScrollbar() throws {
        // Scriptorium V2 policy: the manuscript owns the page's only visible
        // scrollbar. Margins still scroll, but silently — no per-margin
        // PremiumManuscriptScrollbar, no margin scroll metrics.
        let contentFocusView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("UI/FocusMode/Content/ContentFocusModeView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(contentFocusView.contains("private func scriptoriumMarginScroll<Content: View>("))
        XCTAssertTrue(contentFocusView.contains("scriptoriumMarginScroll(width: 260"))
        XCTAssertTrue(contentFocusView.contains("scriptoriumMarginScroll(width: 220"))
        XCTAssertTrue(contentFocusView.contains(".scrollIndicators(.hidden)"))

        XCTAssertFalse(contentFocusView.contains("leftMarginScrollMetrics"))
        XCTAssertFalse(contentFocusView.contains("rightMarginScrollMetrics"))
        // Exactly one PremiumManuscriptScrollbar mount: the manuscript's.
        let scrollbarMounts = contentFocusView.components(separatedBy: "PremiumManuscriptScrollbar(metrics:").count - 1
        XCTAssertEqual(scrollbarMounts, 1)
    }

    func testIdeaFocusHooksUseMultilineEditorsForSavedAndDraftHooks() throws {
        let ideaFocusView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("UI/FocusMode/Ideas/IdeaFocusModeView.swift"),
            encoding: .utf8
        )
        // Idea v2: the AppKit-backed editors live in IdeaManuscriptEditors.swift.
        let manuscriptEditors = try String(
            contentsOf: repositoryRoot.appendingPathComponent("UI/FocusMode/Ideas/IdeaManuscriptEditors.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(manuscriptEditors.contains("struct HookLineEditor: NSViewRepresentable"))
        XCTAssertTrue(ideaFocusView.contains("HookLineEditor("))
        XCTAssertTrue(manuscriptEditors.contains("let isShiftReturn"))
        XCTAssertTrue(manuscriptEditors.contains("insertText(\"\\n\", replacementRange: selectedRange())"))
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
