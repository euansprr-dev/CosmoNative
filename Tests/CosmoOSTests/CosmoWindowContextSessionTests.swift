import XCTest
@testable import CosmoOS

final class CosmoWindowContextSessionTests: XCTestCase {
    @MainActor
    func testBeginNewGlobalChatSessionClearsVisibleStateSynchronously() {
        let viewModel = CosmoWindowViewModel.shared
        let previousMessages = [
            CosmoWindowMessage.user("First prompt"),
            CosmoWindowMessage.assistant("First response")
        ]
        viewModel.messages = previousMessages
        viewModel.error = "Old error"
        viewModel.isProcessing = true
        viewModel.historySearchText = "old search"
        viewModel.processingStartedAt = Date()

        let transition = viewModel.beginNewGlobalChatSession(
            newConversationId: "cosmo-window-test-new-chat"
        )

        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertNil(viewModel.error)
        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertEqual(viewModel.historySearchText, "")
        XCTAssertNil(viewModel.processingStartedAt)
        XCTAssertEqual(transition.previousMessages.map(\.content), ["First prompt", "First response"])
    }

    func testMentionedAtomBecomesPinnedContextSource() async throws {
        let atom = Atom.new(type: .content, title: "Walking Beam brief", body: "Locks on doors are required.")
        let source = CosmoWindowViewModel.contextSource(for: atom)

        XCTAssertEqual(source.kind, .content)
        XCTAssertEqual(source.title, "Walking Beam brief")
        XCTAssertEqual(source.atomUUID, atom.uuid)
        XCTAssertEqual(source.pinState, .pinned)
        XCTAssertEqual(source.id, "atom:\(atom.uuid)")
    }

    func testClientProfileIndexableBodyIncludesMetadataAndFullTopPosts() {
        let topPost = String(repeating: "Josh performer detail. ", count: 80)
        let metadata = ClientProfileMetadata(
            clientId: "josh-profile-context",
            clientName: "Josh",
            platforms: [.instagram],
            brandStory: "Josh helps operators build sober living systems.",
            voiceNotes: "Plainspoken, tactical, direct.",
            topPerformingPosts: [
                TopPost(
                    transcript: topPost,
                    platform: "instagram",
                    likes: 100,
                    shares: 20,
                    leads: 4,
                    views: 50_000
                )
            ]
        )
        let atom = Atom
            .new(type: .clientProfile, title: "Josh")
            .withMetadata(metadata)

        let body = ContextIndexStore.indexableBody(for: atom)

        XCTAssertTrue(body.contains("Josh helps operators build sober living systems."))
        XCTAssertTrue(body.contains("Plainspoken, tactical, direct."))
        XCTAssertTrue(body.contains(topPost))
    }

    func testIndexableBodyPreservesElementStructureFromRichDocument() {
        let definition = DocumentElementDefinition(
            title: "Pain Points",
            systemIcon: "exclamationmark.triangle"
        )
        let document = RichDocument(blocks: [
            .paragraph("Audience notes"),
            RichBlock.element(definition, children: [
                .paragraph("They feel scattered and low-energy.")
            ], isCollapsed: true)
        ])
        let fields = RichDocumentPersistence.writeAtomDocuments(
            existingMetadata: nil,
            bodyDocument: document
        )
        let atom = Atom.new(
            type: .note,
            title: "Target Audience",
            body: fields.body,
            metadata: fields.metadata
        )

        let body = ContextIndexStore.indexableBody(for: atom)

        XCTAssertTrue(body.contains(#"<element title="Pain Points" icon="exclamationmark.triangle" collapsed="true">"#))
        XCTAssertTrue(body.contains("They feel scattered and low-energy."))
        XCTAssertTrue(body.contains("</element>"))
    }

    @MainActor
    func testContentContextProviderExposesActiveClientProfileUUID() {
        var state = ContentFocusModeState(atomUUID: "content-1")
        state.clientProfileUUID = "client-profile-1"
        let atom = Atom.new(type: .content, title: "Draft")
        let provider = ContentContextProvider(
            atom: atom,
            stateRef: { state },
            phaseRef: { .draft }
        )

        let contextData = provider.contextData

        XCTAssertEqual(contextData.activeClientUUID, "client-profile-1")
        XCTAssertTrue(contextData.toContextBlock().contains("Active client UUID: client-profile-1"))
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
