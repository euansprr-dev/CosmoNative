import XCTest
@testable import CosmoOS

/// Lifecycle tests for the interactive /riff directions card: staging, the
/// transient in-document preview, one-click apply, in-document promote,
/// dismiss, and undo. The preview must never persist; the card must survive a
/// session round-trip.
@MainActor
final class RiffDirectionsCardTests: XCTestCase {

    private func makeRiff(targetOriginalText: String = "I bought a duplex.") -> CraftRiffResult {
        CraftRiffResult(
            beatLabel: "Slide 1 hook",
            targetOriginalText: targetOriginalText,
            variations: [
                CraftRiffVariation(text: "The duplex cost me $0.", mechanism: "number-first", borrowedFrom: "Duplex reel", numbers: "480K views"),
                CraftRiffVariation(text: "Everyone said no bank would touch me.", mechanism: "objection-first", borrowedFrom: "none", numbers: "")
            ],
            bet: "Variation 1 — the number does the work."
        )
    }

    private func makeStore(
        persistence: CosmoInlineAssistantSessionPersistence = .inMemory()
    ) -> CosmoInlineAssistantStore {
        CosmoInlineAssistantStore(agentBridge: .mock, sessionPersistence: persistence)
    }

    private func stage(
        riff: CraftRiffResult,
        in store: CosmoInlineAssistantStore,
        surface: RiffTestEditableSurface
    ) -> CosmoAssistantRiffDirectionsCard {
        store.receiveRiffDirections(
            riff: riff,
            snapshot: surface.editableSnapshot(),
            receiptLine: "≈$0.30 · 24.8K in (0% cached) · 7.2K out",
            fallbackMarkdown: "fallback markdown"
        )
        return store.riffDirectionCards.last!
    }

    // MARK: - Staging

    func testReceiveRiffDirectionsAppendsCardAndLinkedMessage() {
        let store = makeStore()
        let surface = RiffTestEditableSurface()
        let card = stage(riff: makeRiff(), in: store, surface: surface)

        XCTAssertEqual(card.status, .pending)
        XCTAssertEqual(card.surfaceID, surface.surfaceID)
        XCTAssertEqual(store.paneMessages.last?.riffCardID, card.id)
        XCTAssertEqual(store.paneMessages.last?.content, "fallback markdown")
        XCTAssertEqual(store.riffDirectionsCard(id: card.id), card)
    }

    // MARK: - Preview

    func testPreviewStagesTransientFlaggedProposalAndSwapsInPlace() {
        let store = makeStore()
        let registry = CosmoEditableSurfaceRegistry()
        let surface = RiffTestEditableSurface()
        registry.register(surface)
        let card = stage(riff: makeRiff(), in: store, surface: surface)

        store.previewRiffVariation(cardID: card.id, index: 1, registry: registry)
        let firstPreview = store.proposals.last
        XCTAssertEqual(store.proposals.filter { $0.isRiffPreview == true }.count, 1)
        XCTAssertEqual(firstPreview?.operations.first?.proposedText, "The duplex cost me $0.")
        XCTAssertEqual(store.riffPreview?.variationIndex, 1)

        // Moving to another block swaps the operation under the SAME proposal id
        // (the in-document diff updates in place, no editor churn).
        store.previewRiffVariation(cardID: card.id, index: 2, registry: registry)
        XCTAssertEqual(store.proposals.filter { $0.isRiffPreview == true }.count, 1)
        XCTAssertEqual(store.proposals.last?.id, firstPreview?.id)
        XCTAssertEqual(store.proposals.last?.operations.first?.proposedText, "Everyone said no bank would touch me.")

        store.endRiffPreview()
        XCTAssertNil(store.riffPreview)
        XCTAssertTrue(store.proposals.allSatisfy { $0.isRiffPreview != true })
    }

    func testPreviewNeverPersistsButCardsDo() throws {
        let spy = PersistenceSpy()
        let store = makeStore(persistence: spy.persistence)
        let registry = CosmoEditableSurfaceRegistry()
        let surface = RiffTestEditableSurface()
        registry.register(surface)
        let card = stage(riff: makeRiff(), in: store, surface: surface)

        store.previewRiffVariation(cardID: card.id, index: 1, registry: registry)
        // Force a save while the preview is live.
        store.dismissRiffDirections(cardID: card.id)

        let session = try XCTUnwrap(spy.lastSession)
        XCTAssertTrue(session.proposals.allSatisfy { $0.isRiffPreview != true })
        XCTAssertEqual(session.riffDirectionCards?.count, 1)
        XCTAssertEqual(session.riffDirectionCards?.first?.status, .dismissed)
    }

    // MARK: - Apply

    func testApplyRiffVariationAppliesAndSettlesCardWithoutExtraPaneMessage() async {
        let store = makeStore()
        let registry = CosmoEditableSurfaceRegistry()
        let surface = RiffTestEditableSurface()
        registry.register(surface)
        let card = stage(riff: makeRiff(), in: store, surface: surface)
        let messageCount = store.paneMessages.count

        await store.applyRiffVariation(cardID: card.id, index: 1, registry: registry)

        let settled = store.riffDirectionsCard(id: card.id)
        XCTAssertEqual(settled?.status, .applied)
        XCTAssertEqual(settled?.appliedVariationIndex, 1)
        XCTAssertEqual(surface.appliedOperations.count, 1)
        XCTAssertEqual(surface.appliedOperations.first?.proposedText, "The duplex cost me $0.")
        XCTAssertEqual(store.paneMessages.count, messageCount, "The riff card IS the receipt — no extra proposal message")

        let appliedProposal = store.proposal(id: settled!.appliedProposalID!)
        XCTAssertNotEqual(appliedProposal?.isRiffPreview, true)
        XCTAssertTrue(appliedProposal?.operations.contains { $0.status == .applied || $0.status == .accepted } ?? false)
    }

    func testApplyForNewBeatStagesInsertion() async {
        let store = makeStore()
        let registry = CosmoEditableSurfaceRegistry()
        let surface = RiffTestEditableSurface()
        registry.register(surface)
        let card = stage(riff: makeRiff(targetOriginalText: ""), in: store, surface: surface)

        await store.applyRiffVariation(cardID: card.id, index: 2, registry: registry)

        XCTAssertEqual(surface.appliedOperations.first?.kind, .textInsertion)
        XCTAssertEqual(store.riffDirectionsCard(id: card.id)?.status, .applied)
    }

    // MARK: - In-document promote / peek close

    func testAcceptingPreviewHunkInDocumentPromotesCard() async {
        let store = makeStore()
        let registry = CosmoEditableSurfaceRegistry()
        let surface = RiffTestEditableSurface()
        registry.register(surface)
        let card = stage(riff: makeRiff(), in: store, surface: surface)

        store.previewRiffVariation(cardID: card.id, index: 2, registry: registry)
        let operationID = store.proposals.last!.operations.first!.id

        // The user clicks ✓ on the woven preview hunk inside the document.
        await store.accept(operationID: operationID, provider: surface)

        let settled = store.riffDirectionsCard(id: card.id)
        XCTAssertEqual(settled?.status, .applied)
        XCTAssertEqual(settled?.appliedVariationIndex, 2)
        XCTAssertNil(store.riffPreview)
        XCTAssertTrue(store.proposals.allSatisfy { $0.isRiffPreview != true }, "Promoted proposal keeps its record, unflagged")
        XCTAssertNotNil(settled?.appliedProposalID)
    }

    func testRejectingPreviewHunkClosesPeekAndKeepsCardPending() async {
        let store = makeStore()
        let registry = CosmoEditableSurfaceRegistry()
        let surface = RiffTestEditableSurface()
        registry.register(surface)
        let card = stage(riff: makeRiff(), in: store, surface: surface)

        store.previewRiffVariation(cardID: card.id, index: 1, registry: registry)
        let operationID = store.proposals.last!.operations.first!.id

        await store.reject(operationID: operationID, registry: registry)

        XCTAssertEqual(store.riffDirectionsCard(id: card.id)?.status, .pending)
        XCTAssertNil(store.riffPreview)
        XCTAssertTrue(store.proposals.allSatisfy { $0.isRiffPreview != true })
        XCTAssertTrue(surface.appliedOperations.isEmpty)
    }

    // MARK: - Dismiss / undo

    func testDismissEndsPreviewAndMarksCard() {
        let store = makeStore()
        let registry = CosmoEditableSurfaceRegistry()
        let surface = RiffTestEditableSurface()
        registry.register(surface)
        let card = stage(riff: makeRiff(), in: store, surface: surface)

        store.previewRiffVariation(cardID: card.id, index: 1, registry: registry)
        store.dismissRiffDirections(cardID: card.id)

        XCTAssertEqual(store.riffDirectionsCard(id: card.id)?.status, .dismissed)
        XCTAssertNil(store.riffPreview)
        XCTAssertTrue(store.proposals.allSatisfy { $0.isRiffPreview != true })
    }

    func testUndoReopensCardForAnotherPick() async {
        let store = makeStore()
        let registry = CosmoEditableSurfaceRegistry()
        let surface = RiffTestEditableSurface()
        registry.register(surface)
        let card = stage(riff: makeRiff(), in: store, surface: surface)

        await store.applyRiffVariation(cardID: card.id, index: 1, registry: registry)
        XCTAssertEqual(store.riffDirectionsCard(id: card.id)?.status, .applied)

        await store.undoRiffVariation(cardID: card.id, registry: registry)

        let reopened = store.riffDirectionsCard(id: card.id)
        XCTAssertEqual(reopened?.status, .pending)
        XCTAssertNil(reopened?.appliedVariationIndex)
        XCTAssertNil(reopened?.appliedProposalID)
        XCTAssertEqual(surface.appliedOperations.count, 2, "Apply + inverse revert both went through the surface")
    }
}

// MARK: - Test doubles

/// Non-learnable surface prefix keeps the edit-learning loop out of these tests.
@MainActor
private final class RiffTestEditableSurface: CosmoEditableSurfaceProvider {
    let surfaceID = "riffdoc:test"
    private(set) var appliedOperations: [CosmoAssistantProposalOperation] = []

    var text = "SLIDE 1\nI bought a duplex.\n\nSLIDE 2\nEveryone told me it was impossible."

    func editableSnapshot() -> CosmoEditableSourceSnapshot {
        CosmoEditableSourceSnapshot(
            surfaceID: surfaceID,
            targetID: "\(surfaceID):body",
            kind: .text,
            title: "Riff test doc",
            text: text,
            sourceHash: CosmoEditableSurfaceHasher.hash(text),
            anchors: []
        )
    }

    func apply(operation: CosmoAssistantProposalOperation) async throws -> CosmoEditableOperationResult {
        appliedOperations.append(operation)
        return CosmoEditableOperationResult(operationID: operation.id, status: .applied, message: "Applied")
    }

    func reject(operation: CosmoAssistantProposalOperation) async -> CosmoEditableOperationResult {
        CosmoEditableOperationResult(operationID: operation.id, status: .rejected, message: "Rejected")
    }
}

/// Captures every persisted session blob so tests can assert what was saved.
private final class PersistenceSpy: @unchecked Sendable {
    private(set) var lastData: Data?

    var persistence: CosmoInlineAssistantSessionPersistence {
        CosmoInlineAssistantSessionPersistence(
            loadData: { _ in nil },
            saveData: { [weak self] _, data in self?.lastData = data },
            deleteData: { _ in }
        )
    }

    var lastSession: CosmoInlineAssistantPersistedSession? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return lastData.flatMap { try? decoder.decode(CosmoInlineAssistantPersistedSession.self, from: $0) }
    }
}
