import XCTest
@testable import CosmoOS

final class CosmoWindowContextSessionTests: XCTestCase {
    @MainActor
    func testConversationMemoryPreservesCreatedAtWhenLoadingHistory() async throws {
        let service = ConversationMemoryService.shared
        let conversationId = "cosmo-window-test-created-at-\(UUID().uuidString)"
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        var conversation = AgentConversation(
            id: conversationId,
            source: .inApp,
            createdAt: createdAt
        )
        conversation.append(.user("Keep my original timestamp."))

        await service.saveConversation(conversation)

        let maybeLoaded = await service.loadConversation(id: conversationId)
        guard let loaded = maybeLoaded else {
            await service.deleteConversation(id: conversationId)
            XCTFail("Expected saved conversation to load")
            return
        }
        await service.deleteConversation(id: conversationId)

        XCTAssertEqual(loaded.createdAt.timeIntervalSince1970, createdAt.timeIntervalSince1970, accuracy: 0.001)
    }

    @MainActor
    func testChatHistoryExcludesEmptyConversations() async throws {
        let service = ConversationMemoryService.shared
        let viewModel = CosmoWindowViewModel.shared
        let emptyId = "cosmo-window-test-empty-\(UUID().uuidString)"
        let filledId = "cosmo-window-test-filled-\(UUID().uuidString)"

        await service.saveConversation(AgentConversation(id: emptyId, source: .inApp))
        var filled = AgentConversation(id: filledId, source: .inApp)
        filled.append(.user("This chat should appear."))
        await service.saveConversation(filled)

        await viewModel.loadChatHistory()
        let containsEmpty = viewModel.chatHistoryEntries.contains { $0.id == emptyId }
        let containsFilled = viewModel.chatHistoryEntries.contains { $0.id == filledId }

        await service.deleteConversation(id: emptyId)
        await service.deleteConversation(id: filledId)

        XCTAssertFalse(containsEmpty)
        XCTAssertTrue(containsFilled)
    }

    func testWindowPersistencePreservesVisibleMessageTimestamps() {
        let userDate = Date(timeIntervalSince1970: 1_700_000_000)
        let assistantDate = Date(timeIntervalSince1970: 1_700_000_060)
        let visibleMessages: [CosmoWindowMessage] = [
            CosmoWindowMessage(type: .user, content: "Original prompt", timestamp: userDate),
            CosmoWindowMessage(type: .assistant, content: "Original response", timestamp: assistantDate)
        ]

        let merged = CosmoWindowViewModel.mergedConversationForPersistence(
            existing: nil,
            visibleMessages: visibleMessages,
            conversationId: "conversation-1",
            linkedAtomUUIDs: []
        )

        XCTAssertEqual(merged.messages.map(\.timestamp), [userDate, assistantDate])
    }

    @MainActor
    func testRefreshContextOnlyUpdatesMatchingActiveAtom() {
        let viewModel = CosmoWindowViewModel.shared
        var title = "Personal brand plan"
        let provider = TestCosmoContextProvider(
            atomUUID: "note-1",
            title: { title }
        )

        viewModel.updateContext(provider: provider)
        XCTAssertEqual(viewModel.activeContext.data.currentAtomTitle, "Personal brand plan")

        title = "Updated brand plan"
        viewModel.refreshContextIfCurrentAtomMatches(atomUUID: "other-note")
        XCTAssertEqual(viewModel.activeContext.data.currentAtomTitle, "Personal brand plan")

        viewModel.refreshContextIfCurrentAtomMatches(atomUUID: "note-1")
        XCTAssertEqual(viewModel.activeContext.data.currentAtomTitle, "Updated brand plan")
    }

    func testEditorCommandPayloadCarriesTargetEditorIDForNoteAppend() {
        let payload = EditorCommandPayload.insertText(
            "New section",
            position: .endOfDocument,
            targetEditorID: "note:note-1:body",
            allowInactive: true
        )

        XCTAssertEqual(payload["text"] as? String, "New section")
        XCTAssertEqual(payload["position"] as? String, "end")
        XCTAssertEqual(payload["targetEditorID"] as? String, "note:note-1:body")
        XCTAssertEqual(payload["allowInactive"] as? Bool, true)
    }

    func testProposedReplacementEditBuildsRemovedAndAddedDiffLines() {
        let edit = CosmoProposedEdit.replacement(
            targetTitle: "Personal brand plan",
            targetEditorID: "note:note-1:body",
            originalText: "Old positioning line",
            replacementText: "New positioning line",
            rationale: "Sharper positioning."
        )

        XCTAssertEqual(edit.operation, .replaceSelection)
        XCTAssertEqual(edit.diffLines.map(\.kind), [.removed, .added])
        XCTAssertEqual(edit.diffLines.map(\.text), ["Old positioning line", "New positioning line"])
    }

    @MainActor
    func testPlanningAgentProfileIsBundled() {
        let profile = CustomAgentProfileStore.defaultProfileForTests(id: "planning-agent")

        XCTAssertEqual(profile?.name, "Planning Agent")
        XCTAssertTrue(profile?.runtimePrompt.contains("planning partner") == true)
        XCTAssertTrue(profile?.toolBundles.contains(.strategy) == true)
        XCTAssertTrue(profile?.contextScopes.contains(.activeContext) == true)
        XCTAssertNil(profile?.preferredModelTier)
    }

    @MainActor
    func testNoteContextProviderIncludesSelectedTextForReplacementDiffs() {
        let atom = Atom.new(type: .note, title: "Personal brand plan")
        let provider = NoteContextProvider(
            atom: atom,
            titleRef: { "Personal brand plan" },
            contentRef: { "Old positioning line" },
            tagsRef: { [] },
            selectedTextRef: { "Old positioning line" }
        )

        let contextData = provider.contextData

        XCTAssertEqual(contextData.currentAtomUUID, atom.uuid)
        XCTAssertEqual(contextData.currentAtomTitle, "Personal brand plan")
        XCTAssertEqual(contextData.selectedText, "Old positioning line")
        XCTAssertTrue(contextData.toContextBlock().contains("Selected text: Old positioning line"))
    }

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

@MainActor
private final class TestCosmoContextProvider: CosmoContextProvider {
    let atomUUID: String
    let title: () -> String

    init(atomUUID: String, title: @escaping () -> String) {
        self.atomUUID = atomUUID
        self.title = title
    }

    var contextType: CosmoContextType { .noteFocusMode }

    var contextSummary: String {
        "Note: \(title())"
    }

    var contextData: CosmoContextData {
        CosmoContextData(
            currentAtomUUID: atomUUID,
            currentAtomType: "note",
            currentAtomTitle: title()
        )
    }

    var availableActions: [CosmoWindowAction] { [] }
}
