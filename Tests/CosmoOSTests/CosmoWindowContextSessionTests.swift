import XCTest
@testable import CosmoOS

final class CosmoWindowContextSessionTests: XCTestCase {
    func testMentionedAtomBecomesPinnedContextSource() async throws {
        let atom = Atom.new(type: .content, title: "Walking Beam brief", body: "Locks on doors are required.")
        let source = CosmoWindowViewModel.contextSource(for: atom)

        XCTAssertEqual(source.kind, .content)
        XCTAssertEqual(source.title, "Walking Beam brief")
        XCTAssertEqual(source.atomUUID, atom.uuid)
        XCTAssertEqual(source.pinState, .pinned)
        XCTAssertEqual(source.id, "atom:\(atom.uuid)")
    }

    func testContextPackRequestUsesCurrentQuestionAndPinnedSources() {
        let request = CosmoWindowViewModel.contextRetrievalRequest(
            text: "does it mention locks on doors?",
            conversationId: "conversation-1",
            pinnedSourceIDs: ["source-1"],
            activeAtomUUID: "atom-1",
            activeClientUUID: nil
        )

        XCTAssertEqual(request.purpose, .factLookup)
        XCTAssertEqual(request.pinnedSourceIDs, ["source-1"])
        XCTAssertEqual(request.surface, .cosmoWindow)
    }

    func testContextIndexStoreRoundTripsContextSessionInMemory() async throws {
        let store = ContextIndexStore.inMemoryForTests()
        var session = ContextSession(
            id: "conversation-1",
            surface: .cosmoWindow,
            activeAtomUUID: "atom-1"
        )
        session.pinSourceID("source-1")
        session.pinSourceID("source-2")

        try await store.upsert(session: session)
        let loaded = try await store.session(id: "conversation-1")

        XCTAssertEqual(loaded?.surface, .cosmoWindow)
        XCTAssertEqual(loaded?.activeAtomUUID, "atom-1")
        XCTAssertEqual(loaded?.pinnedSourceIDs, ["source-1", "source-2"])
    }
}
