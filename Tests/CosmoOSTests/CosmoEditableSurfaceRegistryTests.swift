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
