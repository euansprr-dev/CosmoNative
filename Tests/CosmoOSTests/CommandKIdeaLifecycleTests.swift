import XCTest
@testable import CosmoOS

final class CommandKIdeaLifecycleTests: XCTestCase {
    func testMatchesIdeaCreationNotificationFromTelegramAgentPayload() {
        let atom = Atom.new(type: .idea, title: "TG capture", body: nil, metadata: nil)
        let notification = Notification(
            name: CosmoNotification.Entity.created,
            object: nil,
            userInfo: ["atom": atom, "uuid": atom.uuid, "type": "idea"]
        )

        XCTAssertTrue(CommandKViewModel.notificationTargetsIdeaGallery(notification))
        XCTAssertEqual(CommandKViewModel.ideaUUID(from: notification), atom.uuid)
        XCTAssertFalse(CommandKViewModel.notificationRemovesIdeaFromGallery(notification))
    }

    func testMatchesLegacyIdeaDeletedNotificationWithoutTypeMetadata() {
        let notification = Notification(
            name: CommandKViewModel.legacyIdeaDeletedNotification,
            object: nil,
            userInfo: ["uuid": "idea-123"]
        )

        XCTAssertTrue(CommandKViewModel.notificationTargetsIdeaGallery(notification))
        XCTAssertEqual(CommandKViewModel.ideaUUID(from: notification), "idea-123")
        XCTAssertTrue(CommandKViewModel.notificationRemovesIdeaFromGallery(notification))
    }

    func testIgnoresNonIdeaEntityNotification() {
        let atom = Atom.new(type: .task, title: "Task", body: nil, metadata: nil)
        let notification = Notification(
            name: CosmoNotification.Entity.updated,
            object: nil,
            userInfo: ["atom": atom, "uuid": atom.uuid, "type": "task"]
        )

        XCTAssertFalse(CommandKViewModel.notificationTargetsIdeaGallery(notification))
        XCTAssertEqual(CommandKViewModel.ideaUUID(from: notification), atom.uuid)
    }
}
