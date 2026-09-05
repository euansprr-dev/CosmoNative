// CosmoOS/Tests/CosmoOSTests/OpenAIProviderRequestTests.swift
// The OpenRouter request contract for the GPT-5.6 daily driver: reasoning
// effort per model, the tools+reasoning self-healing ladder, automatic prefix
// caching (prompt_cache_key, no stray cache_control), and the unchanged
// Anthropic-on-OpenRouter cache blocks.

import XCTest
@testable import CosmoOS

final class OpenAIProviderRequestTests: XCTestCase {
    private let sol = AgentModelTier.gpt56Sol.modelId
    private let sonnet = AgentModelTier.sonnet5.modelId

    private let tool = LLMToolDefinition(
        name: "answer_in_assistant_pane",
        description: "answer",
        parametersSchema: ["type": "object", "properties": [:] as [String: Any]]
    )

    override func setUp() {
        super.setUp()
        OpenAIReasoningToolCompatibility.shared.reset()
    }

    override func tearDown() {
        OpenAIReasoningToolCompatibility.shared.reset()
        super.tearDown()
    }

    // MARK: Tiers

    func testDailyDriverIsGPT56SolOnOpenRouter() {
        XCTAssertEqual(AgentModelTier.autoDefault, .gpt56Sol)
        XCTAssertEqual(AgentModelTier.gpt56Sol.modelId, "openai/gpt-5.6-sol")
        XCTAssertEqual(AgentModelTier.gpt56Terra.modelId, "openai/gpt-5.6-terra")
        XCTAssertEqual(AgentModelTier.gpt56Luna.modelId, "openai/gpt-5.6-luna")
        // The strategist alias rides the daily driver so every built-in skill
        // that pins it moves with the default.
        XCTAssertEqual(AgentModelTier.strategist.modelId, AgentModelTier.gpt56Sol.modelId)
        XCTAssertEqual(AgentModelTier.strategist.displayLabel, "GPT-5.6 Sol")
        XCTAssertTrue(AgentModelTier.strategist.isGPT56)
        XCTAssertFalse(AgentModelTier.sonnet5.isGPT56)
        XCTAssertEqual(CosmoInlineAssistantRequestShape.defaultModelTier, .autoDefault)
    }

    func testGPT56ChainsFallOverToAnthropic() {
        XCTAssertEqual(ModelFailoverChain.chain(for: .gpt56Sol).models.first?.modelId, sol)
        XCTAssertEqual(ModelFailoverChain.chain(for: .gpt56Sol).models.map(\.modelId).last, "anthropic/claude-haiku-4.5")
        XCTAssertTrue(ModelFailoverChain.chain(for: .gpt56Terra).models.map(\.modelId).contains(sonnet))
        XCTAssertEqual(ModelFailoverChain.chain(for: .strategist).models.first?.modelId, sol)
    }

    func testFailoverPlanNeverSwapsAnUnknownModelForTheChainHead() {
        let plan = FailoverLLMProvider.failoverPlan(chain: .defaultChain, requestedModel: "claude-sonnet-5")
        XCTAssertEqual(plan.models.map(\.modelId), ["claude-sonnet-5"])
        XCTAssertEqual(plan.startIndex, 0)

        let known = FailoverLLMProvider.failoverPlan(chain: .defaultChain, requestedModel: sonnet)
        XCTAssertEqual(known.startIndex, 1)
        XCTAssertEqual(known.models.count, ModelFailoverChain.defaultChain.models.count)
    }

    // MARK: Reasoning

    func testGPT56SendsMediumEffortByDefaultAndScopedEffortWhenSet() {
        let payload = OpenAIProvider.reasoningPayload(for: sol, hasTools: true)
        XCTAssertEqual(payload?["effort"] as? String, "medium")
        XCTAssertEqual(payload?["exclude"] as? Bool, true)

        let scoped = LLMEffortScope.$effort.withValue("low") {
            OpenAIProvider.reasoningPayload(for: sol, hasTools: true)
        }
        XCTAssertEqual(scoped?["effort"] as? String, "low")

        XCTAssertEqual(OpenAIProvider.reasoningEffort(for: AgentModelTier.gpt55Thinking.modelId), "high")
        XCTAssertNil(OpenAIProvider.reasoningEffort(for: AgentModelTier.gptChatLatest.modelId))
        XCTAssertNil(OpenAIProvider.reasoningPayload(for: sonnet, hasTools: true))
    }

    func testToolsPlusReasoningRejectionFlipsTheCompatibilityFlagAndLadders() {
        let rejection = #"{"error":{"message":"Function tools with reasoning_effort are not supported for gpt-5.6-sol in /v1/chat/completions. To use function tools, use /v1/responses or set reasoning_effort to 'none'.","code":400}}"#
        XCTAssertTrue(OpenAIReasoningToolCompatibility.isToolsWithReasoningRejection(statusCode: 400, body: rejection))
        XCTAssertFalse(OpenAIReasoningToolCompatibility.isToolsWithReasoningRejection(statusCode: 500, body: rejection))
        XCTAssertFalse(OpenAIReasoningToolCompatibility.isToolsWithReasoningRejection(statusCode: 400, body: "rate limited"))

        let next = OpenAIProvider.reasoningPlanAfterRejection(
            statusCode: 400, errorBody: rejection, model: sol, hasTools: true, currentPlan: .standard
        )
        XCTAssertEqual(next, .disabled)
        XCTAssertTrue(OpenAIReasoningToolCompatibility.shared.requiresNoReasoningWithTools)

        // Every later request with tools sends `none` up front…
        XCTAssertEqual(OpenAIProvider.reasoningPayload(for: sol, hasTools: true)?["effort"] as? String, "none")
        // …while tool-free requests keep their reasoning.
        XCTAssertEqual(OpenAIProvider.reasoningPayload(for: sol, hasTools: false)?["effort"] as? String, "medium")

        // The ladder ends: disabled → omitted → nil.
        let omitted = OpenAIProvider.reasoningPlanAfterRejection(
            statusCode: 400, errorBody: rejection, model: sol, hasTools: true, currentPlan: .disabled
        )
        XCTAssertEqual(omitted, .omitted)
        XCTAssertNil(OpenAIProvider.reasoningPayload(for: sol, hasTools: true, plan: .omitted))
        XCTAssertNil(OpenAIProvider.reasoningPlanAfterRejection(
            statusCode: 400, errorBody: rejection, model: sol, hasTools: true, currentPlan: .omitted
        ))
        // Non-GPT-5.6 models and tool-free requests never enter the ladder.
        XCTAssertNil(OpenAIProvider.reasoningPlanAfterRejection(
            statusCode: 400, errorBody: rejection, model: sonnet, hasTools: true, currentPlan: .standard
        ))
    }

    // MARK: Request body

    func testGPT56BodyUsesPlainSystemPromptCacheKeyAndNoCacheControl() {
        let prompt = SystemPrompt(cached: "IDENTITY", dynamic: "CONTEXT")
        let messages = OpenAIProvider.chatMessages(
            from: [.user("hi")],
            systemPrompt: prompt,
            model: sol,
            dropsSystemMessages: true,
            marksLastUserMessageForAnthropicCache: true
        )
        XCTAssertEqual(messages.first?["role"] as? String, "system")
        XCTAssertEqual(messages.first?["content"] as? String, "IDENTITY\n\nCONTEXT")
        // No Anthropic cache blocks on the user message for an OpenAI model.
        XCTAssertEqual(messages.last?["content"] as? String, "hi")

        let body = OpenAIProvider.requestBody(
            model: sol,
            chatMessages: messages,
            tools: [tool],
            cachesToolDefinitions: true,
            maxTokens: 16384,
            stream: true,
            includesUsage: true,
            toolChoice: nil,
            reasoning: OpenAIProvider.reasoningPayload(for: sol, hasTools: true),
            promptCacheKey: OpenAIProvider.promptCacheKey
        )
        XCTAssertEqual(body["prompt_cache_key"] as? String, "cosmoos-agent")
        XCTAssertEqual(body["max_tokens"] as? Int, 16384)
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual((body["reasoning"] as? [String: Any])?["effort"] as? String, "medium")
        let tools = body["tools"] as? [[String: Any]]
        XCTAssertEqual(tools?.count, 1)
        XCTAssertNil(tools?.last?["cache_control"])
    }

    func testAnthropicOnOpenRouterKeepsCacheBlocksAndToolBreakpoint() {
        let prompt = SystemPrompt(cached: "IDENTITY", dynamic: "CONTEXT")
        let messages = OpenAIProvider.chatMessages(
            from: [.user("hi")],
            systemPrompt: prompt,
            model: sonnet,
            dropsSystemMessages: true,
            marksLastUserMessageForAnthropicCache: true
        )
        let systemBlocks = messages.first?["content"] as? [[String: Any]]
        XCTAssertEqual(systemBlocks?.count, 2)
        XCTAssertNotNil(systemBlocks?.first?["cache_control"])
        XCTAssertNil(systemBlocks?.last?["cache_control"])
        let userBlocks = messages.last?["content"] as? [[String: Any]]
        XCTAssertNotNil(userBlocks?.first?["cache_control"])

        let body = OpenAIProvider.requestBody(
            model: sonnet,
            chatMessages: messages,
            tools: [tool],
            cachesToolDefinitions: true,
            maxTokens: 8192,
            stream: false,
            includesUsage: false,
            toolChoice: nil,
            reasoning: nil,
            promptCacheKey: OpenAIProvider.promptCacheKey
        )
        let tools = body["tools"] as? [[String: Any]]
        XCTAssertNotNil(tools?.last?["cache_control"])
        XCTAssertNil(body["reasoning"])
    }

    func testPlainCompletionPathKeepsSystemMessagesAndSkipsToolBreakpoint() {
        let messages = OpenAIProvider.chatMessages(
            from: [.system("sys"), .user("hi")],
            systemPrompt: nil,
            model: sonnet,
            dropsSystemMessages: false,
            marksLastUserMessageForAnthropicCache: false
        )
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.first?["role"] as? String, "system")
        XCTAssertEqual(messages.last?["content"] as? String, "hi")
        XCTAssertNil(OpenAIProvider.toolDictionaries([tool], model: sonnet, cachesDefinitions: false)?.last?["cache_control"])
    }

    func testMaxTokensAndCacheUsageParsing() {
        XCTAssertEqual(OpenAIProvider.maxTokens(for: sol), 16384)
        XCTAssertEqual(OpenAIProvider.maxTokens(for: AgentModelTier.gpt56Luna.modelId), 8192)
        XCTAssertEqual(OpenAIProvider.maxTokens(for: "openai/gpt-5.5"), 16384)

        let usage: [String: Any] = [
            "prompt_tokens": 12000,
            "prompt_tokens_details": ["cached_tokens": 9000, "cache_write_tokens": 400]
        ]
        let cache = OpenAIProvider.cacheTokens(fromUsage: usage)
        XCTAssertEqual(cache.read, 9000)
        XCTAssertEqual(cache.write, 400)
    }
}
