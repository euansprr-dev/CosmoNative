import XCTest
@testable import CosmoOS

/// Begin Writing promotes an idea into a content atom — the assistant session
/// must follow it: transcript + ledger + resolved receipts carry to the content
/// surface with a phase divider, while reviewable idea edits stay behind.
@MainActor
final class CosmoInlineAssistantPromotionCarryTests: XCTestCase {
    private let ideaSurfaceID = "idea:idea-1"
    private let contentSurfaceID = "content:content-1"

    private func makeStore(
        persistence: CosmoInlineAssistantSessionPersistence
    ) -> CosmoInlineAssistantStore {
        CosmoInlineAssistantStore(
            agentBridge: CosmoInlineAssistantAgentBridge { _, _, _ in },
            sessionPersistence: persistence
        )
    }

    private func makeProposal(
        surfaceID: String,
        operationStatus: CosmoProposalStatus
    ) -> CosmoAssistantProposal {
        CosmoAssistantProposal(
            prompt: "tighten the angle",
            surfaceID: surfaceID,
            title: "Tighten the angle",
            summary: "Sharper framing",
            operations: [
                CosmoAssistantProposalOperation(
                    kind: .textReplacement,
                    targetID: "\(surfaceID):body",
                    anchorID: "body",
                    originalText: "old",
                    proposedText: "new",
                    sourceHash: "hash",
                    rationale: "sharper",
                    status: operationStatus
                )
            ]
        )
    }

    private func seedIdeaSession(
        into persistence: CosmoInlineAssistantSessionPersistence,
        pendingProposal: CosmoAssistantProposal,
        appliedProposal: CosmoAssistantProposal
    ) {
        let ledgerRecord = CosmoInlineTurnRecord(
            userAsk: "What hooks would work here?",
            route: .answer,
            skillID: nil,
            answerDigest: "Three curiosity hooks."
        )
        persistence.save(CosmoInlineAssistantPersistedSession(
            surfaceID: ideaSurfaceID,
            paneMessages: [
                .init(role: .user, content: "What hooks would work here?"),
                .init(role: .assistant, content: "Three curiosity hooks."),
                .init(role: .assistant, content: "", proposalID: appliedProposal.id),
                .init(role: .assistant, content: "", proposalID: pendingProposal.id),
            ],
            proposals: [appliedProposal, pendingProposal],
            selectedContextAtoms: [],
            selectedSkillID: "brainstorm",
            selectedSkillIsExplicit: true,
            lastSubmissionRoute: .answer,
            ledger: [ledgerRecord]
        ))
    }

    func testCarryMovesTranscriptAndLedgerAndAppendsPhaseDivider() {
        let persistence = CosmoInlineAssistantSessionPersistence.inMemory()
        let pending = makeProposal(surfaceID: ideaSurfaceID, operationStatus: .pending)
        let applied = makeProposal(surfaceID: ideaSurfaceID, operationStatus: .applied)
        seedIdeaSession(into: persistence, pendingProposal: pending, appliedProposal: applied)
        let store = makeStore(persistence: persistence)

        let carried = store.carrySessionIntoPromotedContent(
            fromSurfaceID: ideaSurfaceID,
            toSurfaceID: contentSurfaceID,
            paneNote: "Begin Writing — continued from the idea"
        )

        XCTAssertTrue(carried)
        let destination = persistence.load(surfaceID: contentSurfaceID)
        XCTAssertNotNil(destination)
        // Conversation + resolved receipt carried; pending receipt stayed behind.
        XCTAssertEqual(
            destination?.paneMessages.compactMap(\.proposalID),
            [applied.id]
        )
        XCTAssertTrue(destination?.paneMessages.contains {
            $0.role == .user && $0.content == "What hooks would work here?"
        } ?? false)
        // The phase divider is the final message, rendered as a section label.
        XCTAssertEqual(destination?.paneMessages.last?.role, .system)
        XCTAssertEqual(destination?.paneMessages.last?.content, "Begin Writing — continued from the idea")
        // Only the resolved proposal travels — no phantom accept/reject bar.
        XCTAssertEqual(destination?.proposals.map(\.id), [applied.id])
        // The ledger (Session So Far) follows; phase-scoped picks reset.
        XCTAssertEqual(destination?.ledger?.count, 1)
        XCTAssertNil(destination?.selectedSkillID)
        XCTAssertNil(destination?.lastSubmissionRoute)
        XCTAssertNil(destination?.inquiryQuestionProposals)
    }

    func testCarryLeavesIdeaSessionIntact() {
        let persistence = CosmoInlineAssistantSessionPersistence.inMemory()
        let pending = makeProposal(surfaceID: ideaSurfaceID, operationStatus: .pending)
        let applied = makeProposal(surfaceID: ideaSurfaceID, operationStatus: .applied)
        seedIdeaSession(into: persistence, pendingProposal: pending, appliedProposal: applied)
        let store = makeStore(persistence: persistence)

        store.carrySessionIntoPromotedContent(
            fromSurfaceID: ideaSurfaceID,
            toSurfaceID: contentSurfaceID,
            paneNote: "Begin Writing"
        )

        let source = persistence.load(surfaceID: ideaSurfaceID)
        XCTAssertEqual(source?.paneMessages.count, 4)
        XCTAssertEqual(source?.proposals.count, 2)
        XCTAssertEqual(source?.selectedSkillID, "brainstorm")
    }

    func testCarryCapturesLiveSessionWhenSourceIsActive() {
        let persistence = CosmoInlineAssistantSessionPersistence.inMemory()
        let store = makeStore(persistence: persistence)
        store.activateSession(surfaceID: ideaSurfaceID)
        store.paneMessages = [
            .init(role: .user, content: "Research this angle"),
            .init(role: .assistant, content: "Here's what I found."),
        ]

        let carried = store.carrySessionIntoPromotedContent(
            fromSurfaceID: ideaSurfaceID,
            toSurfaceID: contentSurfaceID,
            paneNote: "Begin Writing"
        )

        XCTAssertTrue(carried)
        let destination = persistence.load(surfaceID: contentSurfaceID)
        XCTAssertEqual(destination?.paneMessages.first?.content, "Research this angle")
        XCTAssertEqual(destination?.paneMessages.count, 3)
    }

    func testCarryRefusesGlobalSameSurfaceAndEmptySources() {
        let persistence = CosmoInlineAssistantSessionPersistence.inMemory()
        let store = makeStore(persistence: persistence)

        XCTAssertFalse(store.carrySessionIntoPromotedContent(
            fromSurfaceID: ideaSurfaceID, toSurfaceID: ideaSurfaceID, paneNote: "n"
        ))
        XCTAssertFalse(store.carrySessionIntoPromotedContent(
            fromSurfaceID: "", toSurfaceID: contentSurfaceID, paneNote: "n"
        ))
        XCTAssertFalse(store.carrySessionIntoPromotedContent(
            fromSurfaceID: ideaSurfaceID, toSurfaceID: "", paneNote: "n"
        ))
        // No persisted idea session → nothing to carry, no destination written.
        XCTAssertFalse(store.carrySessionIntoPromotedContent(
            fromSurfaceID: ideaSurfaceID, toSurfaceID: contentSurfaceID, paneNote: "n"
        ))
        XCTAssertNil(persistence.load(surfaceID: contentSurfaceID))
    }
}
