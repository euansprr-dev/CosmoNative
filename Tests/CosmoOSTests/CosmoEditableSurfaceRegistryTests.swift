import XCTest
@testable import CosmoOS

@MainActor
final class CosmoEditableSurfaceRegistryTests: XCTestCase {
    func testRegistryReturnsMostRecentActiveProvider() async throws {
        let registry = CosmoEditableSurfaceRegistry()
        let first = TestEditableSurface(surfaceID: "note:1", targetID: "note:1:body", title: "First")
        let second = TestEditableSurface(surfaceID: "content:2", targetID: "content:2:draft", title: "Second")

        registry.register(first)
        XCTAssertEqual(registry.activeSurface?.surfaceID, "note:1")

        registry.register(second)
        XCTAssertEqual(registry.activeSurface?.surfaceID, "content:2")

        registry.unregister(surfaceID: "content:2")
        XCTAssertEqual(registry.activeSurface?.surfaceID, "note:1")
    }

    /// The switcher regression: only one pane can own the window context, so
    /// registration used to be gated on ownership and every other open document
    /// was invisible. Presence registration must list them all.
    func testPresenceRegistrationListsEveryOpenDocument() {
        let registry = CosmoEditableSurfaceRegistry()
        let active = TestEditableSurface(surfaceID: "content:1", targetID: "content:1:draft", title: "Active")
        let background = TestEditableSurface(surfaceID: "note:2", targetID: "note:2:body", title: "Background")
        let alsoBackground = TestEditableSurface(surfaceID: "idea:3", targetID: "idea:3:body", title: "Also")

        registry.register(active)
        registry.registerPresence(background)
        registry.registerPresence(alsoBackground)

        XCTAssertEqual(
            Set(registry.liveSurfaceListings().map(\.surfaceID)),
            ["content:1", "note:2", "idea:3"]
        )
        XCTAssertEqual(registry.liveSurfaceListings().map(\.title).first, "Active")
    }

    /// A document opening in a background pane must not steal focus from the one
    /// the user is working in — that would retarget the assistant's scope.
    func testPresenceRegistrationNeverBecomesActiveSurface() {
        let registry = CosmoEditableSurfaceRegistry()
        let active = TestEditableSurface(surfaceID: "content:1", targetID: "content:1:draft", title: "Active")
        let background = TestEditableSurface(surfaceID: "note:2", targetID: "note:2:body", title: "Background")

        registry.register(active)
        registry.registerPresence(background)

        XCTAssertEqual(registry.activeSurface?.surfaceID, "content:1")
    }

    /// Re-registering presence for a surface already at the front (the view
    /// re-appearing, a pane re-expanding) must not demote it.
    func testPresenceRegistrationDoesNotDemoteTheActiveSurface() {
        let registry = CosmoEditableSurfaceRegistry()
        let surface = TestEditableSurface(surfaceID: "content:1", targetID: "content:1:draft", title: "Active")
        let other = TestEditableSurface(surfaceID: "note:2", targetID: "note:2:body", title: "Other")

        registry.registerPresence(other)
        registry.register(surface)
        registry.registerPresence(surface)

        XCTAssertEqual(registry.activeSurface?.surfaceID, "content:1")
    }

    /// Switching panes promotes a background document to active, and the menu
    /// order follows (most recently active first).
    func testPromotingBackgroundSurfaceReordersListings() {
        let registry = CosmoEditableSurfaceRegistry()
        let first = TestEditableSurface(surfaceID: "content:1", targetID: "content:1:draft", title: "First")
        let second = TestEditableSurface(surfaceID: "note:2", targetID: "note:2:body", title: "Second")

        registry.register(first)
        registry.registerPresence(second)
        XCTAssertEqual(registry.liveSurfaceListings().map(\.surfaceID), ["content:1", "note:2"])

        registry.activate(surfaceID: "note:2")
        XCTAssertEqual(registry.liveSurfaceListings().map(\.surfaceID), ["note:2", "content:1"])
        XCTAssertEqual(registry.activeSurface?.surfaceID, "note:2")
    }

    func testSnapshotContainsStableHash() {
        let surface = TestEditableSurface(surfaceID: "note:1", targetID: "note:1:body", title: "Note")
        let snapshot = surface.editableSnapshot()

        XCTAssertEqual(snapshot.sourceHash, CosmoEditableSurfaceHasher.hash("Original text"))
        XCTAssertEqual(snapshot.anchors.first?.id, "body")
    }
}

@MainActor
private final class TestEditableSurface: CosmoEditableSurfaceProvider {
    let surfaceID: String
    let targetID: String
    let title: String

    init(surfaceID: String, targetID: String, title: String) {
        self.surfaceID = surfaceID
        self.targetID = targetID
        self.title = title
    }

    func editableSnapshot() -> CosmoEditableSourceSnapshot {
        CosmoEditableSourceSnapshot(
            surfaceID: surfaceID,
            targetID: targetID,
            kind: .text,
            title: title,
            text: "Original text",
            sourceHash: CosmoEditableSurfaceHasher.hash("Original text"),
            anchors: [.init(id: "body", label: "Body", utf16Start: 0, utf16Length: 13)]
        )
    }

    func apply(operation: CosmoAssistantProposalOperation) async throws -> CosmoEditableOperationResult {
        CosmoEditableOperationResult(operationID: operation.id, status: .applied, message: "Applied")
    }

    func reject(operation: CosmoAssistantProposalOperation) async -> CosmoEditableOperationResult {
        CosmoEditableOperationResult(operationID: operation.id, status: .rejected, message: "Rejected")
    }
}
