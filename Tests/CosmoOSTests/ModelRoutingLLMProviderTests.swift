// CosmoOS/Tests/CosmoOSTests/ModelRoutingLLMProviderTests.swift
// Per-model transport routing: Claude ids go direct when a key exists,
// everything else rides OpenRouter, and a missing transport degrades to a
// servable tier instead of a dead request.

import XCTest
@testable import CosmoOS

final class ModelRoutingLLMProviderTests: XCTestCase {
    func testClaudeModelsRouteDirectWhenAKeyExists() {
        XCTAssertEqual(
            ModelRoutingLLMProvider.route(model: "anthropic/claude-sonnet-5", hasAnthropic: true, hasOpenRouter: true),
            .anthropicDirect
        )
        XCTAssertEqual(
            ModelRoutingLLMProvider.route(model: "claude-sonnet-5", hasAnthropic: true, hasOpenRouter: false),
            .anthropicDirect
        )
        XCTAssertEqual(
            ModelRoutingLLMProvider.route(model: nil, hasAnthropic: true, hasOpenRouter: true),
            .anthropicDirect
        )
    }

    func testClaudeModelsFallBackToOpenRouterWithoutADirectKey() {
        XCTAssertEqual(
            ModelRoutingLLMProvider.route(model: "anthropic/claude-sonnet-5", hasAnthropic: false, hasOpenRouter: true),
            .openRouter
        )
    }

    func testOpenAIModelsAlwaysRouteThroughOpenRouter() {
        XCTAssertEqual(
            ModelRoutingLLMProvider.route(model: "openai/gpt-5.6-sol", hasAnthropic: true, hasOpenRouter: true),
            .openRouter
        )
        XCTAssertEqual(
            ModelRoutingLLMProvider.route(model: "google/gemini-3.5-flash", hasAnthropic: true, hasOpenRouter: true),
            .openRouter
        )
        XCTAssertEqual(
            ModelRoutingLLMProvider.route(model: "openai/gpt-5.6-sol", hasAnthropic: true, hasOpenRouter: false),
            .unservable
        )
    }

    func testServableTierDegradesToSonnetWhenOpenRouterIsMissing() {
        let anthropicOnly = ModelRoutingLLMProvider(anthropic: AnthropicProvider(apiKey: "k"), openRouter: nil)
        XCTAssertEqual(anthropicOnly.servableTier(.gpt56Sol), .sonnet5)
        XCTAssertEqual(anthropicOnly.servableTier(.sonnet5), .sonnet5)
        XCTAssertFalse(anthropicOnly.canServe(model: "openai/gpt-5.6-sol"))

        let both = ModelRoutingLLMProvider(
            anthropic: AnthropicProvider(apiKey: "k"),
            openRouter: OpenAIProvider(apiKey: "o", baseURL: "https://openrouter.ai/api/v1")
        )
        XCTAssertEqual(both.servableTier(.gpt56Sol), .gpt56Sol)
        XCTAssertTrue(both.canServe(model: "openai/gpt-5.6-terra"))
        XCTAssertEqual(both.providerType, .anthropic)
    }

    func testRoutingFactoryDropsEmptyKeys() {
        let provider = LLMProviderFactory.createRouting(anthropicAPIKey: "", openRouterAPIKey: "o")
        guard let router = provider as? ModelRoutingLLMProvider else {
            return XCTFail("expected a routing provider")
        }
        XCTAssertEqual(router.route(for: "anthropic/claude-sonnet-5"), .openRouter)
        XCTAssertEqual(router.providerType, .openRouter)
    }
}
