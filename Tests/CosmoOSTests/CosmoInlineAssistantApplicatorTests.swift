import XCTest
@testable import CosmoOS

@MainActor
final class CosmoInlineAssistantApplicatorTests: XCTestCase {
    func testAcceptAppliesOperationThroughRegisteredSurface() async {
        let registry = CosmoEditableSurfaceRegistry()
        let surface = ApplyingEditableSurface(text: "Rent: $4,556/mo")
        registry.register(surface)

        let operation = CosmoAssistantProposalOperation.textReplacement(
            targetID: surface.targetID,
            anchorID: "body",
            originalText: "Rent: $4,556/mo",
            proposedText: "Rent: $5,000/mo",
            sourceHash: CosmoEditableSurfaceHasher.hash("Rent: $4,556/mo"),
            rationale: "Update the example rent."
        )
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        store.receive(proposal: proposal(with: operation, surfaceID: surface.surfaceID))

        await store.accept(operationID: operation.id, registry: registry)

        XCTAssertEqual(surface.text, "Rent: $5,000/mo")
        XCTAssertEqual(store.proposals.first?.operations.first?.status, .applied)
    }

    func testAcceptMarksConflictWhenSourceHashChanged() async {
        let registry = CosmoEditableSurfaceRegistry()
        let surface = ApplyingEditableSurface(text: "Rent: $4,556/mo")
        registry.register(surface)

        let operation = CosmoAssistantProposalOperation.textReplacement(
            targetID: surface.targetID,
            anchorID: "body",
            originalText: "Rent: $4,556/mo",
            proposedText: "Rent: $5,000/mo",
            sourceHash: "stale-hash",
            rationale: "Update the example rent."
        )
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        store.receive(proposal: proposal(with: operation, surfaceID: surface.surfaceID))

        await store.accept(operationID: operation.id, registry: registry)

        XCTAssertEqual(surface.text, "Rent: $4,556/mo")
        XCTAssertEqual(store.proposals.first?.operations.first?.status, .conflicted)
    }

    func testRejectMarksOperationRejected() async {
        let registry = CosmoEditableSurfaceRegistry()
        let surface = ApplyingEditableSurface(text: "Rent: $4,556/mo")
        registry.register(surface)

        let operation = CosmoAssistantProposalOperation.textReplacement(
            targetID: surface.targetID,
            anchorID: "body",
            originalText: "Rent: $4,556/mo",
            proposedText: "Rent: $5,000/mo",
            sourceHash: CosmoEditableSurfaceHasher.hash("Rent: $4,556/mo"),
            rationale: "Update the example rent."
        )
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        store.receive(proposal: proposal(with: operation, surfaceID: surface.surfaceID))

        await store.reject(operationID: operation.id, registry: registry)

        XCTAssertEqual(surface.text, "Rent: $4,556/mo")
        XCTAssertEqual(store.proposals.first?.operations.first?.status, .rejected)
    }

    private func proposal(
        with operation: CosmoAssistantProposalOperation,
        surfaceID: String
    ) -> CosmoAssistantProposal {
        CosmoAssistantProposal(
            prompt: "Update rent",
            surfaceID: surfaceID,
            title: "Slide 4 numbers",
            summary: "Update the rent line.",
            operations: [operation]
        )
    }
}

@MainActor
private final class ApplyingEditableSurface: CosmoEditableSurfaceProvider {
    let surfaceID = "test:surface"
    let targetID = "test:surface:body"
    var text: String

    init(text: String) {
        self.text = text
    }

    func editableSnapshot() -> CosmoEditableSourceSnapshot {
        CosmoEditableSourceSnapshot(
            surfaceID: surfaceID,
            targetID: targetID,
            kind: .text,
            title: "Test Surface",
            text: text,
            sourceHash: CosmoEditableSurfaceHasher.hash(text),
            anchors: [.init(id: "body", label: "Body", utf16Start: 0, utf16Length: text.utf16.count)]
        )
    }

    func apply(operation: CosmoAssistantProposalOperation) async throws -> CosmoEditableOperationResult {
        guard let original = operation.originalText,
              let proposed = operation.proposedText,
              let range = text.range(of: original)
        else {
            return CosmoEditableOperationResult(operationID: operation.id, status: .conflicted, message: "Original text missing")
        }

        text.replaceSubrange(range, with: proposed)
        return CosmoEditableOperationResult(operationID: operation.id, status: .applied, message: "Applied")
    }

    func reject(operation: CosmoAssistantProposalOperation) async -> CosmoEditableOperationResult {
        CosmoEditableOperationResult(operationID: operation.id, status: .rejected, message: "Rejected")
    }
}
