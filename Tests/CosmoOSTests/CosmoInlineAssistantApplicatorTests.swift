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

    func testAcceptAppliesThroughExplicitProviderWithoutRegistryLookup() async {
        let surface = ApplyingEditableSurface(text: "Rent: $4,556/mo")
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

        await store.accept(operationID: operation.id, provider: surface)

        XCTAssertEqual(surface.text, "Rent: $5,000/mo")
        XCTAssertEqual(store.proposals.first?.operations.first?.status, .applied)
        XCTAssertNil(store.errorText)
    }

    func testAcceptThroughExplicitProviderAllowsLooseProposalSurfaceWhenTargetMatches() async {
        let surface = ApplyingEditableSurface(text: "Mortgage: $X/mo")
        let operation = CosmoAssistantProposalOperation.textReplacement(
            targetID: surface.targetID,
            anchorID: "body",
            originalText: "Mortgage: $X/mo",
            proposedText: "Mortgage: $5,300/mo",
            sourceHash: CosmoEditableSurfaceHasher.hash("Mortgage: $X/mo"),
            rationale: "Fill the mortgage placeholder."
        )
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        store.receive(proposal: proposal(with: operation, surfaceID: "test-surface-loose-label"))

        await store.accept(operationID: operation.id, provider: surface)

        XCTAssertEqual(surface.text, "Mortgage: $5,300/mo")
        XCTAssertEqual(store.proposals.first?.operations.first?.status, .applied)
        XCTAssertNil(store.errorText)
    }

    func testAcceptAppendsWhenSourceHashChangedAndOriginalTextDrifted() async {
        let registry = CosmoEditableSurfaceRegistry()
        let surface = ApplyingEditableSurface(text: "Rent: $4,700/mo")
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

        // Accepting is never blocked: a drifted original lands as an explicit
        // trailing append (shown that way in the review diff), never a conflict.
        XCTAssertEqual(surface.text, "Rent: $4,700/mo\n\nRent: $5,000/mo")
        XCTAssertEqual(store.proposals.first?.operations.first?.status, .applied)
        XCTAssertNil(store.errorText)
    }

    func testAcceptAppliesStaleHashWhenExactOriginalTextStillExists() async {
        let registry = CosmoEditableSurfaceRegistry()
        let surface = ApplyingEditableSurface(text: "Rent: $4,556/mo\nExpenses: $1,800/mo")
        registry.register(surface)

        let operation = CosmoAssistantProposalOperation.textReplacement(
            targetID: surface.targetID,
            anchorID: "body",
            originalText: "Expenses: $1,800/mo",
            proposedText: "Expenses: $2,100/mo",
            sourceHash: CosmoEditableSurfaceHasher.hash("Expenses: $1,800/mo"),
            rationale: "Update expenses."
        )
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        store.receive(proposal: proposal(with: operation, surfaceID: surface.surfaceID))

        await store.accept(operationID: operation.id, registry: registry)

        XCTAssertEqual(surface.text, "Rent: $4,556/mo\nExpenses: $2,100/mo")
        XCTAssertEqual(store.proposals.first?.operations.first?.status, .applied)
        XCTAssertNil(store.errorText)
    }

    func testAcceptCanRetryConflictedOperationWhenOriginalTextStillExists() async {
        let registry = CosmoEditableSurfaceRegistry()
        let surface = ApplyingEditableSurface(text: "Rent: $4,556/mo\nExpenses: $1,800/mo")
        registry.register(surface)

        let operation = CosmoAssistantProposalOperation(
            kind: .textReplacement,
            targetID: surface.targetID,
            anchorID: "body",
            originalText: "Expenses: $1,800/mo",
            proposedText: "Expenses: $2,100/mo",
            sourceHash: "stale-operation-hash",
            rationale: "Update expenses.",
            status: .conflicted
        )
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        store.receive(proposal: proposal(with: operation, surfaceID: surface.surfaceID))

        await store.accept(operationID: operation.id, registry: registry)

        XCTAssertEqual(surface.text, "Rent: $4,556/mo\nExpenses: $2,100/mo")
        XCTAssertEqual(store.proposals.first?.operations.first?.status, .applied)
    }

    func testAcceptAppliesSlideFallbackWhenModelOriginalHeaderIsStale() async {
        let registry = CosmoEditableSurfaceRegistry()
        let surface = ApplyingEditableSurface(text: """
        SLIDE 4
        Here is the setup.
        --
        SLIDE 5
        --
        SLIDE 6
        --
        """)
        registry.register(surface)

        let operation = CosmoAssistantProposalOperation(
            kind: .textReplacement,
            targetID: surface.targetID,
            anchorID: "slide-5",
            originalText: "SLIDE 6\n--",
            proposedText: "SLIDE 5\nFirst, I found an owner-listed home on Zillow.",
            sourceHash: "stale",
            rationale: "Convert step 1 to first person."
        )
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        store.receive(proposal: proposal(with: operation, surfaceID: surface.surfaceID))

        await store.accept(operationID: operation.id, registry: registry)

        XCTAssertTrue(surface.text.contains("SLIDE 5\nFirst, I found an owner-listed home on Zillow."))
        XCTAssertTrue(surface.text.contains("SLIDE 6\n--"))
        XCTAssertEqual(store.proposals.first?.operations.first?.status, .applied)
        XCTAssertNil(store.errorText)
    }

    func testAcceptPreservesSlideHeaderWhenProposalDropsIt() async {
        let registry = CosmoEditableSurfaceRegistry()
        let surface = ApplyingEditableSurface(text: """
        SLIDE 3
        Old hook line.
        --
        SLIDE 4
        Old body line.
        """)
        registry.register(surface)

        let operation = CosmoAssistantProposalOperation(
            kind: .textReplacement,
            targetID: surface.targetID,
            anchorID: "slide-3",
            originalText: "SLIDE 3\nOld hook line.",
            proposedText: "New hook line.",
            sourceHash: "stale",
            rationale: "Punch up the hook."
        )
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        store.receive(proposal: proposal(with: operation, surfaceID: surface.surfaceID))

        await store.accept(operationID: operation.id, registry: registry)

        XCTAssertTrue(
            surface.text.contains("SLIDE 3\nNew hook line."),
            "The document's own slide header must survive a headerless rewrite"
        )
        XCTAssertEqual(surface.text.components(separatedBy: "SLIDE 3").count - 1, 1)
        XCTAssertTrue(surface.text.contains("SLIDE 4\nOld body line."))
        XCTAssertEqual(store.proposals.first?.operations.first?.status, .applied)
    }

    func testAcceptStripsDuplicateSlideHeaderWhenSlideAlreadyNumbered() async {
        let registry = CosmoEditableSurfaceRegistry()
        let surface = ApplyingEditableSurface(text: """
        SLIDE 3
        Old hook line.
        --
        SLIDE 4
        """)
        registry.register(surface)

        let operation = CosmoAssistantProposalOperation(
            kind: .textReplacement,
            targetID: surface.targetID,
            anchorID: "slide-3",
            originalText: "Old hook line.",
            proposedText: "SLIDE 3\nNew hook line.",
            sourceHash: "stale",
            rationale: "Punch up the hook."
        )
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        store.receive(proposal: proposal(with: operation, surfaceID: surface.surfaceID))

        await store.accept(operationID: operation.id, registry: registry)

        XCTAssertTrue(surface.text.contains("SLIDE 3\nNew hook line."))
        XCTAssertEqual(
            surface.text.components(separatedBy: "SLIDE 3").count - 1, 1,
            "Re-stating the governing header must not duplicate it"
        )
        XCTAssertEqual(store.proposals.first?.operations.first?.status, .applied)
    }

    func testAcceptAppendsInsteadOfConflictingWhenOriginalTextVanished() async {
        let registry = CosmoEditableSurfaceRegistry()
        let surface = ApplyingEditableSurface(text: "Completely unrelated text.")
        registry.register(surface)

        let operation = CosmoAssistantProposalOperation.textReplacement(
            targetID: surface.targetID,
            anchorID: "body",
            originalText: "This text no longer exists anywhere",
            proposedText: "Fresh closing paragraph.",
            sourceHash: "stale",
            rationale: "Add a closer."
        )
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        store.receive(proposal: proposal(with: operation, surfaceID: surface.surfaceID))

        await store.accept(operationID: operation.id, registry: registry)

        XCTAssertEqual(surface.text, "Completely unrelated text.\n\nFresh closing paragraph.")
        XCTAssertEqual(
            store.proposals.first?.operations.first?.status, .applied,
            "Accept must always be able to apply — a drifted original appends, never conflicts"
        )
        XCTAssertNil(store.errorText)
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

    func testRevertAcceptedOperationAppliesInverseThroughRegisteredSurface() async {
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
        await store.revert(operationID: operation.id, registry: registry)

        XCTAssertEqual(surface.text, "Rent: $4,556/mo")
        XCTAssertEqual(store.proposals.first?.operations.first?.status, .reverted)
    }

    func testRevertAllOnlyRevertsAppliedOperations() async {
        let registry = CosmoEditableSurfaceRegistry()
        let surface = ApplyingEditableSurface(text: "Rent: $4,556/mo\nExpenses: $1,800/mo")
        registry.register(surface)

        let rent = CosmoAssistantProposalOperation.textReplacement(
            targetID: surface.targetID,
            anchorID: "body",
            originalText: "Rent: $4,556/mo",
            proposedText: "Rent: $5,000/mo",
            sourceHash: CosmoEditableSurfaceHasher.hash("Rent: $4,556/mo\nExpenses: $1,800/mo"),
            rationale: "Update rent."
        )
        let expenses = CosmoAssistantProposalOperation.textReplacement(
            targetID: surface.targetID,
            anchorID: "body",
            originalText: "Expenses: $1,800/mo",
            proposedText: "Expenses: $2,100/mo",
            sourceHash: CosmoEditableSurfaceHasher.hash("Rent: $5,000/mo\nExpenses: $1,800/mo"),
            rationale: "Update expenses."
        )
        let proposal = CosmoAssistantProposal(
            prompt: "Update slide 4",
            surfaceID: surface.surfaceID,
            title: "Slide 4 numbers",
            summary: "Update the rent and expenses.",
            operations: [rent, expenses]
        )
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        store.receive(proposal: proposal)

        await store.accept(operationID: rent.id, registry: registry)
        await store.accept(operationID: expenses.id, registry: registry)
        await store.revertAll(proposalID: proposal.id, registry: registry)

        XCTAssertEqual(surface.text, "Rent: $4,556/mo\nExpenses: $1,800/mo")
        XCTAssertEqual(store.proposals.first?.operations.map(\.status), [.reverted, .reverted])
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
        guard let placement = CosmoInlineTextEditResolver.placement(for: operation, in: text) else {
            return CosmoEditableOperationResult(operationID: operation.id, status: .conflicted, message: "Original text missing")
        }

        text.replaceSubrange(placement.range, with: placement.replacementText)
        return CosmoEditableOperationResult(operationID: operation.id, status: .applied, message: "Applied")
    }

    func reject(operation: CosmoAssistantProposalOperation) async -> CosmoEditableOperationResult {
        CosmoEditableOperationResult(operationID: operation.id, status: .rejected, message: "Rejected")
    }
}
