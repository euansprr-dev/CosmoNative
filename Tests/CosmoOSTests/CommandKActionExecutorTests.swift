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
