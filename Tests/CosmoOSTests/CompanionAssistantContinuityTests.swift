import XCTest
@testable import CosmoOS

@MainActor
final class CompanionAssistantContinuityTests: XCTestCase {
    @objc func testCompactPaneRoundTripKeepsDraftContextAndStream() {
        let store = CosmoInlineAssistantStore(agentBridge: .mock, sessionPersistence: .inMemory())
        let coordinator = CompanionAssistantCoordinator()
        let panes = PaneManager()
        store.composerText = "An unfinished thought"
        store.composerSelection = NSRange(location: 3, length: 5)
        store.selectedSkillID = "selected-skill"
        store.receivePaneAnswerDelta("An answer in progress")
        let messageID = store.paneMessages.first?.id

        coordinator.openCompact(store: store)
        XCTAssertTrue(coordinator.openPane(using: panes, store: store))
        coordinator.returnToCompact(closePane: { panes.closePane(at: 0) }, store: store)

        XCTAssertEqual(coordinator.host, .compact)
        XCTAssertEqual(store.composerText, "An unfinished thought")
        XCTAssertEqual(store.composerSelection, NSRange(location: 3, length: 5))
        XCTAssertEqual(store.selectedSkillID, "selected-skill")
        XCTAssertEqual(store.paneMessages.first?.id, messageID)
        XCTAssertEqual(store.streamedAnswerText, "An answer in progress")
        XCTAssertTrue(panes.panes.isEmpty)
    }

    @objc func testFullDeckRetainsCompactChatAndEveryExistingPane() {
        let store = CosmoInlineAssistantStore(agentBridge: .mock, sessionPersistence: .inMemory())
        let coordinator = CompanionAssistantCoordinator()
        let panes = PaneManager()
        for index in 0..<6 { panes.openPane(.thinkspace(thinkspaceId: "test-\(index)")) }
        let ids = panes.panes.map(\.id)
        coordinator.openCompact(store: store)

        XCTAssertFalse(coordinator.openPane(using: panes, store: store))
        XCTAssertEqual(coordinator.host, .compact)
        XCTAssertNotNil(coordinator.message)
        XCTAssertEqual(panes.panes.map(\.id), ids)
    }

    @objc func testDismissedRunDoesNotReopenOnAutomaticAnswerButExplicitPaneWorks() {
        let store = CosmoInlineAssistantStore(agentBridge: .mock, sessionPersistence: .inMemory())
        let coordinator = CompanionAssistantCoordinator()
        let panes = PaneManager()
        coordinator.openCompact(store: store)
        store.isProcessing = true
        coordinator.dismiss(store: store)
        coordinator.receive(.ensureVisible, panes: panes, store: store)
        XCTAssertEqual(coordinator.host, .resting)
        coordinator.receive(.pane, panes: panes, store: store)
        XCTAssertEqual(coordinator.host, .pane)
    }

    @objc func testUnsentDraftSurvivesStoreRecreation() {
        let persistence = CosmoInlineAssistantSessionPersistence.inMemory()
        let first = CosmoInlineAssistantStore(agentBridge: .mock, sessionPersistence: persistence)
        first.composerText = "未完成の考え 🌱"
        first.composerSelection = NSRange(location: 2, length: 3)
        first.savePresentationDraft()
        let restored = CosmoInlineAssistantStore(agentBridge: .mock, sessionPersistence: persistence)
        XCTAssertEqual(restored.composerText, first.composerText)
        XCTAssertEqual(restored.composerSelection, first.composerSelection)
    }

    @objc func testPassiveFocusCannotStealADraft() {
        let store = CosmoInlineAssistantStore(agentBridge: .mock, sessionPersistence: .inMemory())
        store.composerText = "Keep this with this conversation"
        let scope = store.currentScopeSurfaceID
        store.activateSessionIfIdle(surfaceID: "note:another-document")
        XCTAssertEqual(store.currentScopeSurfaceID, scope)
        XCTAssertFalse(store.composerText.isEmpty)
    }

    @objc func testClearingTheLastDraftCharacterPersists() {
        let persistence = CosmoInlineAssistantSessionPersistence.inMemory()
        let store = CosmoInlineAssistantStore(agentBridge: .mock, sessionPersistence: persistence)
        store.composerText = "A"
        store.savePresentationDraft()
        store.composerText = ""
        store.savePresentationDraft()
        let restored = CosmoInlineAssistantStore(agentBridge: .mock, sessionPersistence: persistence)
        XCTAssertEqual(restored.composerText, "")
    }

    @objc func testCorruptSelectionOffsetsCannotOverflow() {
        let range = MentionComposerTextSelectionPolicy.clamped(NSRange(location: Int.max, length: Int.max), in: "A short draft")
        XCTAssertEqual(range, NSRange(location: 13, length: 0))
    }

    @objc func testLegacyAssistantPaneIsActivatedInsteadOfDuplicated() {
        let panes = PaneManager()
        panes.openPane(.cosmoWindow)
        XCTAssertTrue(panes.openOrActivateInlineAssistant())
        XCTAssertEqual(panes.panes.map(\.id), ["cosmoWindow"])
        XCTAssertEqual(panes.focusedPaneId, "cosmoWindow")
    }

    @objc func testCompactGeometryNeverExtendsBeyondTheWindow() {
        for size in [CGSize(width: 300, height: 400), CGSize(width: 1440, height: 900)] {
            let compact = CompanionAssistantPlacement.compactSize(in: size)
            XCTAssertLessThanOrEqual(compact.width + 32, size.width)
            XCTAssertLessThanOrEqual(compact.height + 80, size.height)
        }
    }

    @objc func testPortableMergeKeepsBothDevicesMessagesAndStableIdentity() {
        let a = CompanionConversationRecord.Message(id: "a", role: "user", text: "A", createdAt: Date(timeIntervalSince1970: 1))
        let b = CompanionConversationRecord.Message(id: "b", role: "assistant", text: "B", createdAt: Date(timeIntervalSince1970: 2))
        let first = CompanionConversationRecord(id: "thread", origin: "Mac", title: "A", messages: [a], updatedAt: a.createdAt)
        let second = CompanionConversationRecord(id: "thread", origin: "Mac", title: "A", messages: [a, b], updatedAt: b.createdAt)
        XCTAssertEqual(first.merging(second).messages, [a, b])
        XCTAssertEqual(second.merging(first).messages, [a, b])
    }
}
