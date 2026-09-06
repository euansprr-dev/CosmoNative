import XCTest
@testable import CosmoOS

final class CommandKActionExecutorTests: XCTestCase {
    @MainActor
    func testOpenAtomPostsExistingCommandKNotification() async throws {
        let recorder = NotificationRecorder(name: CosmoNotification.NodeGraph.openAtomFromCommandK)
        let executor = CommandKActionExecutor()

        try await executor.execute(.openAtom(uuid: "atom-1"))

        XCTAssertEqual(recorder.notifications.count, 1)
        XCTAssertEqual(recorder.notifications.first?.userInfo?["atomUUID"] as? String, "atom-1")
    }

    @MainActor
    func testStartInquiryPostsInquiryNotification() async throws {
        let recorder = NotificationRecorder(name: CosmoNotification.Inquiry.startInquiry)
        let executor = CommandKActionExecutor()

        try await executor.execute(.startInquiry(anchorUUID: "atom-1", anchorType: "Research"))

        XCTAssertEqual(recorder.notifications.count, 1)
        XCTAssertEqual(recorder.notifications.first?.userInfo?["anchorUUID"] as? String, "atom-1")
        XCTAssertEqual(recorder.notifications.first?.userInfo?["anchorType"] as? String, "Research")
    }

    @MainActor
    func testOpenSelectedAsPanePostsPanePayloadForSelectedRecent() async throws {
        let paneRecorder = NotificationRecorder(name: CosmoNotification.Navigation.openAsPane)
        let closeRecorder = NotificationRecorder(name: CosmoNotification.NodeGraph.closeCommandK)
        let viewModel = CommandKViewModel()
        defer { viewModel.setSurfaceActive(false) }
        viewModel.recentItems = [
            RecentDisplayItem(
                id: "note-1",
                title: "Launch Notes",
                type: .note,
                entityId: 42,
                relativeDate: "2h",
                thumbnailURL: nil,
                preview: nil
            )
        ]
        viewModel.selectedNodeId = "note-1"

        await viewModel.openSelectedAsPane()

        XCTAssertEqual(paneRecorder.notifications.count, 1)
        XCTAssertEqual(paneRecorder.notifications.first?.userInfo?["type"] as? EntityType, .note)
        XCTAssertEqual(paneRecorder.notifications.first?.userInfo?["id"] as? Int64, 42)
        XCTAssertEqual(closeRecorder.notifications.count, 1)
    }

    @MainActor
    func testPostNotificationIntentClosesCommandK() async throws {
        let peekRecorder = NotificationRecorder(name: CosmoNotification.Navigation.peekEntity)
        let closeRecorder = NotificationRecorder(name: CosmoNotification.NodeGraph.closeCommandK)
        let executor = CommandKActionExecutor()

        try await executor.execute(.postNotification(
            name: CosmoNotification.Navigation.peekEntity,
            userInfo: ["uuid": "atom-1"]
        ))

        XCTAssertEqual(peekRecorder.notifications.count, 1)
        XCTAssertEqual(peekRecorder.notifications.first?.userInfo?["uuid"] as? String, "atom-1")
        XCTAssertEqual(closeRecorder.notifications.count, 1)
    }

    @MainActor
    func testAddToCanvasIntentWaitsForMutationBeforeDismissal() async throws {
        let addRecorder = NotificationRecorder(name: CosmoNotification.NodeGraph.addToCanvas)
        let closeRecorder = NotificationRecorder(name: CosmoNotification.NodeGraph.closeCommandK)
        let executor = CommandKActionExecutor()

        try await executor.execute(.addToCanvas(uuid: "atom-1"))

        XCTAssertEqual(addRecorder.notifications.count, 1)
        XCTAssertEqual(closeRecorder.notifications.count, 0)
    }

    @MainActor
    func testOpenSwipeGalleryAsPanePostsPanePayload() async throws {
        let paneRecorder = NotificationRecorder(name: CosmoNotification.Navigation.openAsPane)
        let closeRecorder = NotificationRecorder(name: CosmoNotification.NodeGraph.closeCommandK)
        let executor = CommandKActionExecutor()

        try await executor.execute(.openSwipeGalleryAsPane)

        XCTAssertEqual(paneRecorder.notifications.count, 1)
        XCTAssertEqual(paneRecorder.notifications.first?.userInfo?["swipeGallery"] as? Bool, true)
        XCTAssertEqual(closeRecorder.notifications.count, 1)
    }

    @MainActor
    func testOpenSelectedAsPanePostsSwipeGalleryPaneForSelectedCommand() async throws {
        let paneRecorder = NotificationRecorder(name: CosmoNotification.Navigation.openAsPane)
        let viewModel = CommandKViewModel(
            userCommandStore: CommandKUserCommandStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("json"),
                seedBuiltIns: false
            )
        )
        defer { viewModel.setSurfaceActive(false) }
        let action = CommandKAction(
            kind: .openSwipeGallery,
            title: "Open Swipe Gallery",
            subtitle: "Open All Swipes full screen",
            icon: "rectangle.stack.fill",
            payload: CommandKActionPayload(rawText: "open swipe gallery")
        )
        viewModel.primaryAction = action
        viewModel.selectedNodeId = action.id

        await viewModel.openSelectedAsPane()

        XCTAssertEqual(paneRecorder.notifications.count, 1)
        XCTAssertEqual(paneRecorder.notifications.first?.userInfo?["swipeGallery"] as? Bool, true)
    }
}

private final class NotificationRecorder {
    private(set) var notifications: [Notification] = []
    private var token: NSObjectProtocol?

    init(name: Notification.Name) {
        token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] notification in
            self?.notifications.append(notification)
        }
    }

    deinit {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
