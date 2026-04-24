import XCTest
@testable import CosmoOS

final class CommandKIdeaLifecycleTests: XCTestCase {
    private var isoNow: String {
        ISO8601DateFormatter().string(from: Date())
    }

    func testLedgerLayoutKeepsPreviewCollapsedUntilColumnExpanded() {
        let items = (0..<7).map { index in
            IdeaGalleryItem(
                id: "idea-\(index)",
                atomUUID: "idea-\(index)",
                entityId: Int64(index),
                title: "Idea \(index)",
                body: nil,
                status: .spark,
                contentFormat: nil,
                platform: nil,
                clientName: "Client",
                clientUUID: "client-1",
                tags: [],
                insightScore: nil,
                matchingSwipeCount: nil,
                suggestedFramework: nil,
                isPinned: false,
                contentCount: 0,
                createdAt: isoNow,
                updatedAt: isoNow
            )
        }

        XCTAssertEqual(
            CortexIdeasLedgerLayout.visibleItems(from: items, isExpanded: false, previewLimit: 5).count,
            5
        )
        XCTAssertEqual(
            CortexIdeasLedgerLayout.visibleItems(from: items, isExpanded: true, previewLimit: 5).count,
            7
        )
    }

    func testCaptureNormalizationTrimsWhitespaceOnlyDrafts() {
        XCTAssertNil(CortexIdeasCapture.normalizedTitle(from: "   \n "))
        XCTAssertEqual(CortexIdeasCapture.normalizedTitle(from: "  greenhouse hook  "), "greenhouse hook")
    }

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
