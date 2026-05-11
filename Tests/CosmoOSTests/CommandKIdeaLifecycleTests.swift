import XCTest
@testable import CosmoOS

@MainActor
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

    func testSectionBuilderKeepsClientColumnsSortedAndUnassignedLast() {
        let clientB = Atom.new(type: .clientProfile, title: "Ben", body: nil, metadata: nil)
        let clientA = Atom.new(type: .clientProfile, title: "Alice", body: nil, metadata: nil)
        let assigned = makeIdea(title: "Assigned idea", clientUUID: clientB.uuid)
        let unassigned = makeIdea(title: "Loose idea", clientUUID: nil)

        let sections = CortexIdeasSectionBuilder.sections(
            visibleIdeas: [unassigned, assigned],
            clientProfiles: [clientB, clientA]
        )

        XCTAssertEqual(sections.map(\.clientName), ["Alice", "Ben", "Unassigned"])
        XCTAssertEqual(sections[0].items.count, 0)
        XCTAssertEqual(sections[1].items.map(\.title), ["Assigned idea"])
        XCTAssertEqual(sections[2].clientUUID, nil)
        XCTAssertEqual(sections[2].items.map(\.title), ["Loose idea"])
    }

    func testIdeaGalleryItemPreservesIdeaFocusContextHooksAndOutline() throws {
        let outline = CodexOutlineModel(
            arcShape: nil,
            slides: [
                CodexOutlineSlide(
                    id: UUID(),
                    position: 1,
                    speechAct: nil,
                    readerDeltas: [],
                    frame: nil,
                    distance: nil,
                    techniques: [],
                    transition: nil,
                    note: "Set up the rental gap"
                ),
                CodexOutlineSlide(
                    id: UUID(),
                    position: 2,
                    speechAct: nil,
                    readerDeltas: [],
                    frame: "Show the offer mechanism",
                    distance: nil,
                    techniques: [],
                    transition: nil,
                    note: nil
                ),
            ]
        )
        let outlineJSON = try XCTUnwrap(String(data: JSONEncoder().encode(outline), encoding: .utf8))

        var atom = Atom.new(
            type: .idea,
            title: "Rental angle",
            body: "Use the local rent squeeze as the context for the claim.",
            metadata: nil
        )
        atom = atom.withUpdatedIdeaMetadata { metadata in
            metadata.context = "Creative direction: make the angle feel specific to renters."
            metadata.hooks = ["Find a home for rent for XYZ", "Renters are missing this one path"]
            metadata.codexOutline = outlineJSON
        }

        let item = try XCTUnwrap(atom.toIdeaGalleryItem())
        XCTAssertEqual(item.body, "Use the local rent squeeze as the context for the claim.")
        XCTAssertEqual(item.context, "Creative direction: make the angle feel specific to renters.")
        XCTAssertEqual(item.hooks, ["Find a home for rent for XYZ", "Renters are missing this one path"])
        XCTAssertEqual(item.outline, ["Set up the rental gap", "Show the offer mechanism"])
    }

    func testIdeaGalleryItemUsesBodyAsContextFallbackWhenMetadataContextIsEmpty() throws {
        var atom = Atom.new(
            type: .idea,
            title: "Fallback context",
            body: "The body should become preview context when metadata has no context.",
            metadata: nil
        )
        atom = atom.withUpdatedIdeaMetadata { metadata in
            metadata.context = "   "
        }

        let item = try XCTUnwrap(atom.toIdeaGalleryItem())
        XCTAssertEqual(item.context, "The body should become preview context when metadata has no context.")
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

    private func makeIdea(title: String, clientUUID: String?) -> IdeaGalleryItem {
        IdeaGalleryItem(
            id: title,
            atomUUID: title,
            entityId: Int64(abs(title.hashValue % 10_000)),
            title: title,
            body: nil,
            status: .spark,
            contentFormat: nil,
            platform: nil,
            clientName: nil,
            clientUUID: clientUUID,
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
}
