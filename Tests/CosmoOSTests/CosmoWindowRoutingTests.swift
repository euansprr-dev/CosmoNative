import XCTest
@testable import CosmoOS

final class CosmoWindowRoutingTests: XCTestCase {
    func testExpandedAgentModelTiersUseExactOpenRouterIds() {
        XCTAssertEqual(AgentModelTier.gpt55Thinking.modelId, "openai/gpt-5.5:thinking")
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
        XCTAssertEqual(ModelFailoverChain.chain(for: .gpt55Thinking).models.first?.modelId, "openai/gpt-5.5:thinking")
        XCTAssertEqual(ModelFailoverChain.chain(for: .opus47).models.first?.modelId, "anthropic/claude-opus-4.7")
        XCTAssertEqual(ModelFailoverChain.chain(for: .gptChatLatest).models.first?.modelId, "openai/gpt-chat-latest")
        XCTAssertEqual(ModelFailoverChain.chain(for: .geminiFlashLatest).models.first?.modelId, "~google/gemini-flash-latest")
    }

    func testOpenRouterSettingsCatalogIncludesNewModels() {
        let ids = Set(AgentProvider.openRouterModels.map(\.id))

        XCTAssertTrue(ids.contains("openai/gpt-5.5:thinking"))
        XCTAssertTrue(ids.contains("anthropic/claude-opus-4.7"))
        XCTAssertTrue(ids.contains("openai/gpt-chat-latest"))
        XCTAssertTrue(ids.contains("~google/gemini-flash-latest"))
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
        XCTAssertEqual(CosmoAgentService.defaultModelTier(for: .query), .sensor)
        XCTAssertEqual(CosmoAgentService.defaultModelTier(for: .brainstorm), .gptChatLatest)
        XCTAssertEqual(CosmoAgentService.defaultModelTier(for: .draft), .writer)
        XCTAssertEqual(CosmoAgentService.defaultModelTier(for: .analyze), .strategist)
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
}
