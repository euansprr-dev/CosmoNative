import XCTest
@testable import CosmoOS

final class CommandKActionRegistryTests: XCTestCase {
    func testSwipeContextExposesSwipeSelectionAndActiveState() {
        let subject = CortexDetailSubject.swipe(
            SwipeGalleryItem(
                atomUUID: "swipe-1",
                title: "Property Hook",
                hookText: "Buy near a military base",
                hookScore: 8.4,
                platform: "instagram",
                thumbnailUrl: "https://example.com/thumb.jpg",
                author: "creator"
            )
        )

        let context = CommandKActionContext(
            query: "",
            subject: subject,
            hydratedAtom: nil,
            mode: .compact,
            activeInquirySessionUUID: "session-1",
            activeContentDraftUUID: "content-1"
        )

        XCTAssertEqual(context.selectionKind, .swipe)
        XCTAssertEqual(context.selectedAtomUUID, "swipe-1")
        XCTAssertTrue(context.hasActiveInquirySession)
        XCTAssertTrue(context.hasActiveContentDraft)
    }

    func testActionWithTitleKeepsStableIdentityAndIntent() {
        let first = CommandKContextualAction(
            id: .openFocusMode,
            category: .primary,
            title: "Open",
            subtitle: nil,
            systemImage: "arrow.up.left.and.arrow.down.right",
            shortcut: .returnKey,
            role: .normal,
            availability: .enabled,
            intent: .openAtom(uuid: "atom-1")
        )

        let second = first.withTitle("Open in Focus Mode")

        XCTAssertEqual(second.id, first.id)
        XCTAssertEqual(second.intent, first.intent)
        XCTAssertEqual(second.title, "Open in Focus Mode")
    }

    func testRegistryReturnsUniversalObjectActionsForAtomSelection() {
        let subject = CortexDetailSubject.recent(
            RecentDisplayItem(
                id: "atom-1",
                title: "Launch Notes",
                type: .research,
                entityId: 42,
                relativeDate: "2h",
                thumbnailURL: nil,
                preview: "Notes"
            )
        )
        let context = CommandKActionContext(
            query: "",
            subject: subject,
            hydratedAtom: nil,
            mode: .compact,
            activeInquirySessionUUID: nil,
            activeContentDraftUUID: nil
        )

        let actions = CommandKActionRegistry().actions(for: context)
        let ids = actions.map(\.id)

        XCTAssertEqual(ids.first, .openFocusMode)
        XCTAssertTrue(ids.contains(.openAsPane))
        XCTAssertTrue(ids.contains(.addToCanvas))
        XCTAssertTrue(ids.contains(.goToObject))
        XCTAssertTrue(ids.contains(.copyCosmoLink))
    }

    func testRegistryDisablesInquiryAttachWhenNoActiveInquiryExists() {
        let subject = CortexDetailSubject.recent(
            RecentDisplayItem(
                id: "atom-1",
                title: "Source",
                type: .research,
                entityId: 1,
                relativeDate: "1d",
                thumbnailURL: nil,
                preview: nil
            )
        )
        let context = CommandKActionContext(
            query: "",
            subject: subject,
            hydratedAtom: nil,
            mode: .compact,
            activeInquirySessionUUID: nil,
            activeContentDraftUUID: nil
        )

        let action = CommandKActionRegistry().actions(for: context).first { $0.id == .addToActiveInquiry }

        XCTAssertEqual(action?.availability, .disabled(reason: "No active inquiry session"))
    }

    func testRegistryReturnsSwipeActionsForSwipeSelection() {
        let subject = CortexDetailSubject.swipe(
            SwipeGalleryItem(
                atomUUID: "swipe-1",
                title: "Swipe",
                hookText: "Hook",
                hookScore: 8,
                platform: "instagram",
                thumbnailUrl: nil,
                author: nil
            )
        )
        let context = CommandKActionContext(
            query: "",
            subject: subject,
            hydratedAtom: nil,
            mode: .expandedDomain(.swipeGallery),
            activeInquirySessionUUID: "inquiry-1",
            activeContentDraftUUID: "content-1"
        )

        let actions = CommandKActionRegistry().actions(for: context)
        let ids = actions.map(\.id)

        XCTAssertTrue(ids.contains(.openSwipeStudy))
        XCTAssertTrue(ids.contains(.analyzeSwipeHook))
        XCTAssertTrue(ids.contains(.attachSwipeToCurrentDraft))
        XCTAssertTrue(ids.contains(.useSwipeAsBlueprint))
        XCTAssertTrue(ids.contains(.createIdeaFromSwipe))
    }

    func testTaskSelectionGetsTaskOperations() {
        let subject = CortexDetailSubject.recent(
            RecentDisplayItem(
                id: "task-1",
                title: "Write reel",
                type: .task,
                entityId: 1,
                relativeDate: "today",
                thumbnailURL: nil,
                preview: nil
            )
        )
        let context = CommandKActionContext(
            query: "",
            subject: subject,
            hydratedAtom: nil,
            mode: .compact,
            activeInquirySessionUUID: nil,
            activeContentDraftUUID: nil
        )

        let ids = CommandKActionRegistry().actions(for: context).map(\.id)

        XCTAssertTrue(ids.contains(.startFocusTask))
        XCTAssertTrue(ids.contains(.markTaskDone))
        XCTAssertTrue(ids.contains(.deferTask))
        XCTAssertTrue(ids.contains(.scheduleTaskTomorrow))
    }

    func testCommandKPresentationBringsPreservedPaletteForward() {
        var state = CommandKPresentationState(
            isVisible: false,
            isPreservedBehindFocusMode: true
        )

        state.apply(.present)

        XCTAssertTrue(state.isVisible)
        XCTAssertFalse(state.isPreservedBehindFocusMode)
        XCTAssertTrue(state.isVisibleToApp)
    }

    func testCommandKPresentationCanReopenAfterClose() {
        var state = CommandKPresentationState(
            isVisible: true,
            isPreservedBehindFocusMode: false
        )

        state.apply(.preserveBehindFocusMode)
        state.apply(.close)
        state.apply(.present)

        XCTAssertTrue(state.isVisible)
        XCTAssertFalse(state.isPreservedBehindFocusMode)
        XCTAssertTrue(state.isVisibleToApp)
    }

    func testCommandKPresentationRequestsSearchFocusEachTimeItIsPresented() {
        var state = CommandKPresentationState(
            isVisible: false,
            isPreservedBehindFocusMode: false
        )

        state.apply(.present)
        let firstFocusRequest = state.searchFocusRequest
        state.apply(.close)
        state.apply(.present)

        XCTAssertGreaterThan(firstFocusRequest, 0)
        XCTAssertGreaterThan(state.searchFocusRequest, firstFocusRequest)
    }

    func testInstantSwipeCaptureCreatesPendingInstagramAtomWithoutMediaExtraction() throws {
        let atom = try CommandKInstantSwipeCapture().pendingAtom(
            for: "https://www.instagram.com/p/DXCBs_uDKau/"
        )

        XCTAssertTrue(atom.isSwipeFile)
        XCTAssertEqual(atom.processingStatus, "pending")
        XCTAssertEqual(atom.title, "Instagram Post")
        XCTAssertEqual(atom.richContent?.sourceType, .instagramPost)
        XCTAssertEqual(atom.richContent?.instagramId, "DXCBs_uDKau")
        XCTAssertNil(atom.richContent?.instagramData?.carouselItems)
        XCTAssertNil(atom.richContent?.instagramData?.extractedMediaURL)
    }
}
