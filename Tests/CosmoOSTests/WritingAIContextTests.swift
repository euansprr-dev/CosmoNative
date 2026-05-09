import XCTest
@testable import CosmoOS

@MainActor
final class WritingAIContextTests: XCTestCase {
    @MainActor
    func testContextBuilderBudgetsLongDraftAndRoutesWriterTier() async {
        let longDraft = String(repeating: "opening proof ", count: 700)
            + String(repeating: "middle detail ", count: 700)
            + String(repeating: "closing CTA ", count: 700)

        let pack = await WritingAIContextBuilder().build(for: makeRequest(draftText: longDraft))

        XCTAssertEqual(pack.modelTier, .writer)
        XCTAssertLessThan(pack.draftExcerpt.count, longDraft.count)
        XCTAssertTrue(pack.draftExcerpt.contains("[...middle omitted for budget...]"))
    }

    @MainActor
    func testClientProfileRetrieverReturnsRelevantLimitedProfileChunks() async {
        let profile = ClientProfileMetadata(
            clientId: "ben",
            clientName: "Ben A",
            platforms: [.instagram],
            documents: [
                ProfileDocument(
                    category: .voiceGuide,
                    title: "Voice guide",
                    content: "Plainspoken, direct, and concise. Avoid jargon."
                ),
                ProfileDocument(
                    category: .story,
                    title: "Foreclosure auction origin",
                    content: "Ben learned the foreclosure auction market by helping landlords handle distressed assets. " + String(repeating: "foreclosure auction proof ", count: 80)
                )
            ]
        )
        let atom = Atom
            .new(type: .clientProfile, title: "Ben A")
            .withMetadata(profile)

        let references = await ClientProfileRetriever().retrieve(
            query: "foreclosure auction story",
            profileAtom: atom,
            limit: 2
        )

        XCTAssertEqual(references.first?.source, .clientProfile)
        XCTAssertTrue(references.first?.title.contains("Foreclosure auction origin") == true)
        XCTAssertLessThanOrEqual(references.first?.excerpt.count ?? 0, 1_400)
    }

    @MainActor
    func testBestPostRetrieverUsesClientTopPostsBeforeGlobalSearch() async {
        let profile = ClientProfileMetadata(
            clientId: "ben",
            clientName: "Ben A",
            platforms: [.instagram],
            topPerformingPosts: [
                TopPost(
                    transcript: "The foreclosure auction mistake most investors make is treating proof like trivia.",
                    platform: "instagram",
                    likes: 1200,
                    shares: 310,
                    leads: 42,
                    views: 95_000
                )
            ]
        )
        let atom = Atom
            .new(type: .clientProfile, title: "Ben A")
            .withMetadata(profile)

        let references = await BestPostRetriever().retrieve(
            query: "foreclosure auction proof",
            profileAtom: atom,
            matchedSwipeAtoms: [],
            limit: 1
        )

        XCTAssertEqual(references.count, 1)
        XCTAssertEqual(references.first?.source, .bestPosts)
        XCTAssertTrue(references.first?.detail?.lowercased().contains("views 95000") == true)
    }

    func testModelRoutingKeepsSmallSelectionEditsOnStrategistAndLongDraftsOnWriter() {
        XCTAssertEqual(
            WritingAIContextBuilder.modelTier(forDraftCharacterCount: 500, action: .tighten),
            .strategist
        )
        XCTAssertEqual(
            WritingAIContextBuilder.modelTier(forDraftCharacterCount: 500, action: .critique),
            .writer
        )
        XCTAssertEqual(
            WritingAIContextBuilder.modelTier(forDraftCharacterCount: 12_001, action: nil),
            .writer
        )
    }

    func testSafeEditEligibilityOnlyAllowsApprovedSelectionReplacement() {
        let selectedTextReplacement = WritingAIResponse(
            title: "Rewrite",
            body: "Sharper line",
            references: [],
            proposedReplacement: "Sharper line",
            editTarget: .selection,
            modelTier: .strategist
        )
        let draftPreview = WritingAIResponse(
            title: "Full rewrite",
            body: "Full draft suggestion",
            references: [],
            proposedReplacement: "Full draft suggestion",
            editTarget: .draftPreview,
            modelTier: .writer
        )

        XCTAssertTrue(selectedTextReplacement.canReplaceSelection)
        XCTAssertFalse(draftPreview.canReplaceSelection)
    }

    func testWritingRequestsCanCarrySharedContextPack() {
        let request = ContextRetrievalRequest(
            query: "draft from the brief",
            conversationID: "conversation-1",
            surface: .writingMode,
            purpose: .writing,
            pinnedSourceIDs: ["source-1"],
            activeAtomUUID: "content-1",
            activeClientUUID: "client-1",
            maxChunks: 8,
            tokenBudget: 5_000
        )

        XCTAssertEqual(request.surface, .writingMode)
        XCTAssertEqual(request.purpose, .writing)
        XCTAssertEqual(request.pinnedSourceIDs, ["source-1"])
    }

    func testWritingContextMergeKeepsUserDirectionFirst() {
        let merged = AgentToolExecutor.mergeWritingContext(
            "Make this sharper.",
            contextBlock: "[COSMO CONTEXT PACK]\nRetrieved source evidence."
        )

        XCTAssertEqual(
            merged,
            "Make this sharper.\n\n[COSMO CONTEXT PACK]\nRetrieved source evidence."
        )
    }

    private func makeRequest(
        prompt: String = "Critique this draft",
        action: WritingAIQuickAction? = nil,
        selectedText: String = "",
        draftText: String = "A short draft"
    ) -> WritingAIRequest {
        WritingAIRequest(
            prompt: prompt,
            action: action,
            selectedText: selectedText,
            selectionContext: "",
            draftText: draftText,
            contentTitle: "Newsletter draft",
            contentDescription: "Write a sharper proof-driven newsletter.",
            contentFormat: .newsletter,
            currentStep: .draft,
            clientProfileAtom: nil,
            sourceIdeaAtom: nil,
            matchedSwipeAtoms: [],
            framework: nil,
            outline: [],
            hooks: []
        )
    }
}
