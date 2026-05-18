import XCTest
@testable import CosmoOS

final class CosmoWindowRoutingTests: XCTestCase {
    func testExpandedAgentModelTiersUseExactOpenRouterIds() {
        XCTAssertEqual(AgentModelTier.gpt55Thinking.modelId, "openai/gpt-5.5")
        XCTAssertEqual(AgentModelTier.opus47.modelId, "anthropic/claude-opus-4.7")
        XCTAssertEqual(AgentModelTier.gptChatLatest.modelId, "openai/gpt-chat-latest")
        XCTAssertEqual(AgentModelTier.geminiFlashLatest.modelId, "~google/gemini-flash-latest")
    }

    func testExpandedAgentModelTiersExposeReadableLabels() {
        XCTAssertEqual(AgentModelTier.gpt55Thinking.displayLabel, "GPT 5.5 Thinking")
        XCTAssertEqual(AgentModelTier.opus47.displayLabel, "Opus 4.7")
        XCTAssertEqual(AgentModelTier.gptChatLatest.displayLabel, "GPT Chat Latest")
        XCTAssertEqual(AgentModelTier.geminiFlashLatest.displayLabel, "Gemini Flash")
    }

    func testExplicitModelFailoverChainsStartWithSelectedModel() {
        XCTAssertEqual(ModelFailoverChain.chain(for: .gpt55Thinking).models.first?.modelId, "openai/gpt-5.5")
        XCTAssertEqual(ModelFailoverChain.chain(for: .opus47).models.first?.modelId, "anthropic/claude-opus-4.7")
        XCTAssertEqual(ModelFailoverChain.chain(for: .gptChatLatest).models.first?.modelId, "openai/gpt-chat-latest")
        XCTAssertEqual(ModelFailoverChain.chain(for: .geminiFlashLatest).models.first?.modelId, "~google/gemini-flash-latest")
    }

    func testGeminiFlashLatestFailoverNeverFallsBackToOpus() {
        let modelIds = ModelFailoverChain.chain(for: .geminiFlashLatest).models.map(\.modelId)

        XCTAssertFalse(modelIds.contains { $0.contains("opus") })
    }

    func testOpenRouterSettingsCatalogIncludesNewModels() {
        let ids = Set(AgentProvider.openRouterModels.map(\.id))

        XCTAssertTrue(ids.contains("openai/gpt-5.5"))
        XCTAssertTrue(ids.contains("anthropic/claude-opus-4.7"))
        XCTAssertTrue(ids.contains("openai/gpt-chat-latest"))
        XCTAssertTrue(ids.contains("~google/gemini-flash-latest"))
        XCTAssertFalse(ids.contains("google/gemini-3.1-flash-lite-preview"))
    }

    func testGPT55ThinkingUsesOpenRouterReasoningParameter() {
        XCTAssertEqual(OpenAIProvider.reasoningEffort(for: AgentModelTier.gpt55Thinking.modelId), "high")
        XCTAssertNil(OpenAIProvider.reasoningEffort(for: AgentModelTier.gptChatLatest.modelId))
    }

    func testCosmoModelPickerOptionsIncludeRequestedModels() {
        let ids = Set(CosmoModelOption.all.map(\.id))

        XCTAssertTrue(ids.contains("gpt55Thinking"))
        XCTAssertTrue(ids.contains("opus47"))
        XCTAssertTrue(ids.contains("gptChatLatest"))
        XCTAssertTrue(ids.contains("geminiFlashLatest"))
    }

    func testAgentModelTierMaxTokensForNewModels() {
        XCTAssertEqual(AgentModelTier.gpt55Thinking.maxTokens, 16384)
        XCTAssertEqual(AgentModelTier.opus47.maxTokens, 16384)
        XCTAssertEqual(AgentModelTier.gptChatLatest.maxTokens, 8192)
        XCTAssertEqual(AgentModelTier.geminiFlashLatest.maxTokens, 8192)
    }

    func testDefaultModelTierKeepsCheapRoutesCheap() {
        XCTAssertEqual(CosmoAgentService.defaultModelTier(for: .capture), .sensor)
        XCTAssertEqual(CosmoAgentService.defaultModelTier(for: .query), .geminiFlashLatest)
        XCTAssertEqual(CosmoAgentService.defaultModelTier(for: .brainstorm), .geminiFlashLatest)
        XCTAssertEqual(CosmoAgentService.defaultModelTier(for: .draft), .geminiFlashLatest)
        XCTAssertEqual(CosmoAgentService.defaultModelTier(for: .analyze), .strategist)
    }

    func testAutoModelRoutingNeverUsesOpusWriterTier() {
        let autoIntents: [AgentIntent] = [
            .capture, .brainstorm, .plan, .query, .execute, .debrief,
            .reflect, .correct, .meta, .strategy, .draft, .analyze
        ]

        XCTAssertFalse(autoIntents.contains { CosmoAgentService.defaultModelTier(for: $0) == .writer })
    }

    func testExplicitPickerStillAllowsOpus() {
        let opusOption = CosmoModelOption.all.first { $0.id == "opus" }
        let opus47Option = CosmoModelOption.all.first { $0.id == "opus47" }

        XCTAssertEqual(opusOption?.tier, .writer)
        XCTAssertEqual(opus47Option?.tier, .opus47)
    }

    func testBypassesFlashRouterForFollowUpAboutCapturedContent() {
        let recentAssistant = [
            "Captured Instagram swipe.",
            "Saved idea: The hook is worth adapting."
        ]

        XCTAssertTrue(
            CosmoWindowViewModel.shouldBypassFlashRouter(
                text: "turn this into a carousel",
                recentAssistantContents: recentAssistant
            )
        )
    }

    func testDoesNotBypassFlashRouterWithoutCaptureHistory() {
        XCTAssertFalse(
            CosmoWindowViewModel.shouldBypassFlashRouter(
                text: "turn this into a carousel",
                recentAssistantContents: ["I can help think through that."]
            )
        )
    }

    func testProfileInspectionRequestsBypassFlashRouter() {
        XCTAssertTrue(FlashLiteRouter.shouldForceAgentFallback("check out Josh's content profile"))
        XCTAssertTrue(FlashLiteRouter.shouldForceAgentFallback("show me Josh's best performing posts"))
    }

    func testAgentContextAtomMergePreservesPinnedProfilesWhenMentionsArePresent() {
        XCTAssertEqual(
            CosmoAgentService.mergedContextAtomUUIDs(
                existing: ["profile-1", "content-1"],
                mentioned: ["content-1", "swipe-1"]
            ),
            ["profile-1", "content-1", "swipe-1"]
        )
    }
}

@MainActor
final class ClientProfileToolTests: XCTestCase {
    private var createdUUIDs: [String] = []

    override func tearDown() async throws {
        let uuids = createdUUIDs.reversed()
        createdUUIDs.removeAll()

        for uuid in uuids {
            try? await AtomRepository.shared.hardDelete(uuid: uuid, confirmed: true)
        }

        try await super.tearDown()
    }

    func testGetClientProfileReturnsCompleteTopPostsAndDocuments() async throws {
        let fullPost = String(repeating: "Josh full performer sentence. ", count: 80)
        let fullDocument = String(repeating: "Josh document transcript sentence. ", count: 90)
        let profile = ClientProfileMetadata(
            clientId: UUID().uuidString,
            clientName: "Josh Profile Tool Test",
            platforms: [.instagram],
            topPerformingTranscripts: [fullPost],
            documents: [
                ProfileDocument(
                    category: .reel,
                    title: "Best reel",
                    content: fullDocument,
                    platform: "instagram",
                    likes: 12,
                    shares: 3,
                    saves: 4,
                    comments: 5,
                    leads: 6,
                    sourceURL: "https://example.com/reel"
                )
            ],
            topPerformingPosts: [
                TopPost(
                    transcript: fullPost,
                    platform: "instagram",
                    likes: 100,
                    shares: 20,
                    leads: 7,
                    views: 12_000,
                    datePosted: "2026-05-01"
                )
            ]
        )

        let created = try await AtomRepository.shared.create(
            Atom.new(type: .clientProfile, title: "Josh Profile Tool Test").withMetadata(profile)
        )
        createdUUIDs.append(created.uuid)

        let result = try await AgentToolExecutor.shared.execute(
            toolName: "get_client_profile",
            arguments: ["client_name": "Josh Profile Tool Test"]
        )
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any]
        )

        let posts = try XCTUnwrap(payload["topPerformingPosts"] as? [[String: Any]])
        XCTAssertEqual(posts.first?["transcript"] as? String, fullPost)

        let transcripts = payload["topPerformingTranscripts"] as? [String]
        XCTAssertEqual(transcripts?.first, fullPost)

        let documents = try XCTUnwrap(payload["documents"] as? [[String: Any]])
        XCTAssertEqual(documents.first?["content"] as? String, fullDocument)
        XCTAssertEqual(documents.first?["sourceURL"] as? String, "https://example.com/reel")
    }
}
