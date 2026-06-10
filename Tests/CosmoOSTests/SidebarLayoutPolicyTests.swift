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

    func testRouteSceneSignalsAreCappedToNearestVisibleSignals() {
        let signals = [
            makeSceneSignal(id: "hidden", minX: 10, width: 0, intensity: 1),
            makeSceneSignal(id: "near-low", minX: 330, intensity: 0.2),
            makeSceneSignal(id: "near-high", minX: 330, intensity: 0.9),
            makeSceneSignal(id: "far", minX: 900, intensity: 1),
            makeSceneSignal(id: "behind-sidebar", minX: 200, intensity: 0.4),
            makeSceneSignal(id: "six", minX: 360, intensity: 0.4),
            makeSceneSignal(id: "seven", minX: 370, intensity: 0.4),
            makeSceneSignal(id: "eight", minX: 380, intensity: 0.4),
            makeSceneSignal(id: "nine", minX: 390, intensity: 0.4),
            makeSceneSignal(id: "ten", minX: 400, intensity: 0.4),
        ]

        let capped = MainSidebarSceneSignalPolicy.routeSignals(
            from: signals,
            sidebarReservedWidth: 320
        )

        XCTAssertEqual(
            capped.map(\.id),
            ["behind-sidebar", "near-high", "near-low", "six", "seven", "eight", "nine", "ten"]
        )
    }

    func testRouteSceneSignalsIgnoreSubPixelGeometryJitter() {
        let current = [
            makeSceneSignal(id: "a", minX: 330.2, minY: 20.2, width: 100.2, height: 44.2)
        ]
        let jittered = [
            makeSceneSignal(id: "a", minX: 330.3, minY: 20.3, width: 100.3, height: 44.3)
        ]

        XCTAssertFalse(
            MainSidebarSceneSignalPolicy.shouldUpdateRouteSignals(
                current: current,
                next: jittered
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

    func testInboxStatsCountsInSinglePass() throws {
        let inboxTypes = try String(
            contentsOf: repositoryRoot.appendingPathComponent("UI/Inbox/InboxTypes.swift"),
            encoding: .utf8
        )
        let statsInitializer = try XCTUnwrap(
            inboxTypes.slice(
                from: "init(items: [InboxItem])",
                to: "}\n}\n\n// MARK: - Intelligence Grouping"
            )
        )

        XCTAssertFalse(statsInitializer.contains("items.filter"))
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
        XCTAssertTrue(openAtom.contains("let requestID = UUID()"))
        XCTAssertTrue(openAtom.contains("commandKNavigationRequestID = requestID"))
        XCTAssertTrue(openAtom.contains("try await Task.sleep(for: .milliseconds(150))"))
        XCTAssertTrue(openAtom.contains("guard commandKNavigationRequestID == requestID, !Task.isCancelled else { return }"))
        XCTAssertFalse(openAtom.contains("DispatchQueue.main.asyncAfter"))

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
        XCTAssertTrue(goToObject.contains("try await Task.sleep(for: .milliseconds(250))"))
        XCTAssertTrue(goToObject.contains("guard commandKNavigationRequestID == requestID, !Task.isCancelled else { return }"))
        XCTAssertFalse(goToObject.contains("DispatchQueue.main.asyncAfter"))
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
                of: "currentThinkspace = resolvedThinkspace",
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
                of: "currentThinkspace = resolvedThinkspace"
            )
        )
        let canvasNotificationRange = try XCTUnwrap(
            switchTo.range(
                of: "name: CosmoNotification.Canvas.thinkspaceChanged"
            )
        )
        let persistenceRange = try XCTUnwrap(
            switchTo.range(
                of: "await updateLastOpened(resolvedThinkspace)"
            )
        )

        XCTAssertLessThan(publishRange.lowerBound, persistenceRange.lowerBound)
        XCTAssertLessThan(canvasNotificationRange.lowerBound, persistenceRange.lowerBound)
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
                to: "await spatialEngine.loadBlocks(for: \"home\", documentId: 0, thinkspaceId: newId)"
            )
        )
        XCTAssertTrue(fastPath.contains("animateThinkspaceContentIn()"))
        XCTAssertFalse(fastPath.contains("spatialEngine.blocks = []"))

        let fastPathEntryRange = try XCTUnwrap(switchHandler.range(of: "animateThinkspaceContentIn()"))
        let authoritativeLoadRange = try XCTUnwrap(
            switchHandler.range(of: "await spatialEngine.loadBlocks(for: \"home\", documentId: 0, thinkspaceId: newId)")
        )
        XCTAssertLessThan(fastPathEntryRange.lowerBound, authoritativeLoadRange.lowerBound)
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

        let cancellationGuardRange = try XCTUnwrap(loadBlocks.range(of: "guard !Task.isCancelled, thinkspaceId == currentThinkspaceId else {"))
        let publishRange = try XCTUnwrap(loadBlocks.range(of: "self.blocks = deduped"))
        XCTAssertLessThan(cancellationGuardRange.lowerBound, publishRange.lowerBound)
    }

    func testSwipeStudyAutoTranscriptionProgressPublishesOnMainActor() throws {
        let swipeStudy = try String(
            contentsOf: repositoryRoot.appendingPathComponent("UI/FocusMode/SwipeStudy/SwipeStudyFocusModeView.swift"),
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

    private func makeSceneSignal(
        id: String,
        minX: CGFloat,
        minY: CGFloat = 0,
        width: CGFloat = 100,
        height: CGFloat = 44,
        intensity: Double = 1,
        source: CosmoGlassSceneSignalSource = .commandTask
    ) -> CosmoGlassSceneSignal {
        CosmoGlassSceneSignal(
            id: id,
            color: DS.accent,
            rect: CGRect(x: minX, y: minY, width: width, height: height),
            intensity: intensity,
            source: source
        )
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
