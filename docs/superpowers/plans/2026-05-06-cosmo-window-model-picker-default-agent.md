# OPTION+A Model Picker and Default Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the OPTION+A Cosmo Window model picker route to exact OpenRouter models and improve the normal default agent's collaboration, research, content, and cost behavior.

**Architecture:** Extend the existing model-tier path with explicit model preset cases to minimize churn. Keep Auto as intent-based routing, make explicit picker choices concrete OpenRouter IDs, update failover chains to respect the selected model, and extract the default agent prompt into named sections for maintainable personality and cost tuning.

**Tech Stack:** Swift 5, SwiftUI, OpenRouter Chat Completions through the existing `OpenAIProvider`, `UserDefaults`, XCTest.

---

## File Map

- Modify `Agent/Models/AgentTypes.swift`
  Adds exact model cases, display labels, picker metadata, current OpenRouter model IDs, and explicit failover chains.
- Modify `UI/CosmoWindow/CosmoWindowViewModel.swift`
  Makes the normal OPTION+A model selection label and profile fallback work with the expanded model cases.
- Modify `UI/CosmoWindow/CosmoWindowView.swift`
  Adds the requested model rows to the picker and keeps the row selection logic correct for Auto.
- Modify `Agent/Core/LLMProviderAdapter.swift`
  Improves max-token inference for GPT 5.5, GPT Chat Latest, Opus 4.7, and Gemini Flash Latest.
- Modify `Agent/Core/AgentContextAssembler.swift`
  Replaces the giant inline default prompt with a composed prompt from `CosmoDefaultAgentPrompt`.
- Create `Agent/Core/CosmoDefaultAgentPrompt.swift`
  Owns the normal agent personality, retrieval behavior, content collaboration behavior, and cost discipline prompt sections.
- Modify `Tests/CosmoOSTests/CosmoWindowRoutingTests.swift`
  Adds focused tests for exact model IDs, labels, failover first model, and picker options.
- Modify `Tests/CosmoOSTests/CosmoWindowMessageRenderingTests.swift`
  Adds focused prompt-composition coverage for the normal default agent prompt.

## Task 1: Exact Model Presets

**Files:**
- Modify: `Agent/Models/AgentTypes.swift`
- Test: `Tests/CosmoOSTests/CosmoWindowRoutingTests.swift`

- [ ] **Step 1: Add failing tests for requested model IDs**

Append these tests to `CosmoWindowRoutingTests`:

```swift
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
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -only-testing:CosmoOSTests/CosmoWindowRoutingTests test
```

Expected: compile failure because the four new enum cases and `displayLabel` do not exist.

- [ ] **Step 3: Add explicit cases and labels**

In `AgentModelTier`, replace the enum body with this expanded version while preserving existing raw values:

```swift
enum AgentModelTier: String, Codable, Sendable {
    case sensor
    case strategist
    case writer
    case gpt55Thinking
    case opus47
    case gptChatLatest
    case geminiFlashLatest

    var modelId: String {
        switch self {
        case .sensor: return "anthropic/claude-haiku-4.5"
        case .strategist: return "anthropic/claude-sonnet-4.5"
        case .writer: return "anthropic/claude-opus-4.6"
        case .gpt55Thinking: return "openai/gpt-5.5:thinking"
        case .opus47: return "anthropic/claude-opus-4.7"
        case .gptChatLatest: return "openai/gpt-chat-latest"
        case .geminiFlashLatest: return "~google/gemini-flash-latest"
        }
    }

    var displayLabel: String {
        switch self {
        case .sensor: return "Haiku"
        case .strategist: return "Sonnet"
        case .writer: return "Opus"
        case .gpt55Thinking: return "GPT 5.5 Thinking"
        case .opus47: return "Opus 4.7"
        case .gptChatLatest: return "GPT Chat Latest"
        case .geminiFlashLatest: return "Gemini Flash"
        }
    }

    var maxTokens: Int {
        switch self {
        case .sensor: return 4096
        case .strategist: return 8192
        case .writer: return 16384
        case .gpt55Thinking: return 16384
        case .opus47: return 16384
        case .gptChatLatest: return 8192
        case .geminiFlashLatest: return 8192
        }
    }

    var contextWindow: Int {
        switch self {
        case .sensor: return 200_000
        case .strategist: return 200_000
        case .writer: return 1_000_000
        case .gpt55Thinking: return 1_050_000
        case .opus47: return 1_000_000
        case .gptChatLatest: return 400_000
        case .geminiFlashLatest: return 1_048_576
        }
    }
}
```

- [ ] **Step 4: Re-run the focused tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -only-testing:CosmoOSTests/CosmoWindowRoutingTests test
```

Expected: the new model ID and label tests pass, or the command reaches the next planned failure for failover coverage.

## Task 2: Respect Explicit Models in Failover

**Files:**
- Modify: `Agent/Models/AgentTypes.swift`
- Test: `Tests/CosmoOSTests/CosmoWindowRoutingTests.swift`

- [ ] **Step 1: Add failing failover tests**

Append:

```swift
func testExplicitModelFailoverChainsStartWithSelectedModel() {
    XCTAssertEqual(ModelFailoverChain.chain(for: .gpt55Thinking).models.first?.modelId, "openai/gpt-5.5:thinking")
    XCTAssertEqual(ModelFailoverChain.chain(for: .opus47).models.first?.modelId, "anthropic/claude-opus-4.7")
    XCTAssertEqual(ModelFailoverChain.chain(for: .gptChatLatest).models.first?.modelId, "openai/gpt-chat-latest")
    XCTAssertEqual(ModelFailoverChain.chain(for: .geminiFlashLatest).models.first?.modelId, "~google/gemini-flash-latest")
}
```

- [ ] **Step 2: Run the focused tests and verify failover expectations fail**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -only-testing:CosmoOSTests/CosmoWindowRoutingTests/testExplicitModelFailoverChainsStartWithSelectedModel test
```

Expected: failure because `ModelFailoverChain.chain(for:)` still only knows the old three cases.

- [ ] **Step 3: Add explicit failover chains**

Replace the `ModelFailoverChain` static chains and switch with:

```swift
static let writerChain = ModelFailoverChain(models: [
    FailoverModel(modelId: "anthropic/claude-opus-4.6", maxRetries: 3, label: "Opus"),
    FailoverModel(modelId: "openai/gpt-5.4", maxRetries: 1, label: "GPT 5.4"),
])

static let defaultChain = ModelFailoverChain(models: [
    FailoverModel(modelId: "anthropic/claude-sonnet-4.5", maxRetries: 1, label: "Sonnet"),
    FailoverModel(modelId: "anthropic/claude-haiku-4.5", maxRetries: 1, label: "Haiku"),
    FailoverModel(modelId: "~google/gemini-flash-latest", maxRetries: 1, label: "Gemini Flash"),
])

static let sensorChain = ModelFailoverChain(models: [
    FailoverModel(modelId: "anthropic/claude-haiku-4.5", maxRetries: 1, label: "Haiku"),
    FailoverModel(modelId: "~google/gemini-flash-latest", maxRetries: 1, label: "Gemini Flash"),
])

static let gpt55ThinkingChain = ModelFailoverChain(models: [
    FailoverModel(modelId: "openai/gpt-5.5:thinking", maxRetries: 1, label: "GPT 5.5 Thinking"),
    FailoverModel(modelId: "openai/gpt-chat-latest", maxRetries: 1, label: "GPT Chat Latest"),
])

static let opus47Chain = ModelFailoverChain(models: [
    FailoverModel(modelId: "anthropic/claude-opus-4.7", maxRetries: 2, label: "Opus 4.7"),
    FailoverModel(modelId: "anthropic/claude-opus-4.6", maxRetries: 1, label: "Opus 4.6"),
    FailoverModel(modelId: "openai/gpt-5.5:thinking", maxRetries: 1, label: "GPT 5.5 Thinking"),
])

static let gptChatLatestChain = ModelFailoverChain(models: [
    FailoverModel(modelId: "openai/gpt-chat-latest", maxRetries: 1, label: "GPT Chat Latest"),
    FailoverModel(modelId: "~google/gemini-flash-latest", maxRetries: 1, label: "Gemini Flash"),
])

static let geminiFlashLatestChain = ModelFailoverChain(models: [
    FailoverModel(modelId: "~google/gemini-flash-latest", maxRetries: 1, label: "Gemini Flash"),
    FailoverModel(modelId: "openai/gpt-chat-latest", maxRetries: 1, label: "GPT Chat Latest"),
])

static func chain(for tier: AgentModelTier) -> ModelFailoverChain {
    switch tier {
    case .writer: return .writerChain
    case .strategist: return .defaultChain
    case .sensor: return .sensorChain
    case .gpt55Thinking: return .gpt55ThinkingChain
    case .opus47: return .opus47Chain
    case .gptChatLatest: return .gptChatLatestChain
    case .geminiFlashLatest: return .geminiFlashLatestChain
    }
}
```

- [ ] **Step 4: Re-run failover tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -only-testing:CosmoOSTests/CosmoWindowRoutingTests/testExplicitModelFailoverChainsStartWithSelectedModel test
```

Expected: pass.

## Task 3: Update OpenRouter Settings Catalog

**Files:**
- Modify: `Agent/Models/AgentTypes.swift`
- Test: `Tests/CosmoOSTests/CosmoWindowRoutingTests.swift`

- [ ] **Step 1: Add a failing settings catalog test**

Append:

```swift
func testOpenRouterSettingsCatalogIncludesNewModels() {
    let ids = Set(AgentProvider.openRouterModels.map(\.id))

    XCTAssertTrue(ids.contains("openai/gpt-5.5:thinking"))
    XCTAssertTrue(ids.contains("anthropic/claude-opus-4.7"))
    XCTAssertTrue(ids.contains("openai/gpt-chat-latest"))
    XCTAssertTrue(ids.contains("~google/gemini-flash-latest"))
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -only-testing:CosmoOSTests/CosmoWindowRoutingTests/testOpenRouterSettingsCatalogIncludesNewModels test
```

Expected: failure because `AgentProvider.openRouterModels` still lists older models.

- [ ] **Step 3: Update `AgentProvider.openRouterModels`**

Change the start of the static list to:

```swift
static let openRouterModels: [(id: String, label: String)] = [
    ("openai/gpt-5.5:thinking", "GPT 5.5 Thinking"),
    ("anthropic/claude-opus-4.7", "Claude Opus 4.7"),
    ("openai/gpt-chat-latest", "GPT Chat Latest"),
    ("~google/gemini-flash-latest", "Gemini Flash Latest"),
    ("anthropic/claude-sonnet-4.5", "Claude Sonnet 4.5"),
    ("anthropic/claude-opus-4.6", "Claude Opus 4.6"),
    ("anthropic/claude-haiku-4.5", "Claude Haiku 4.5"),
    ("google/gemini-3.1-flash-lite-preview", "Gemini 3.1 Flash Lite"),
    ("google/gemini-3-flash-preview", "Gemini 3 Flash Preview"),
    ("google/gemini-2.0-flash-001", "Gemini 2.0 Flash"),
    ("google/gemini-2.5-pro-preview", "Gemini 2.5 Pro"),
    ("deepseek/deepseek-chat", "DeepSeek V3"),
    ("deepseek/deepseek-r1", "DeepSeek R1"),
    ("meta-llama/llama-3.3-70b-instruct", "Llama 3.3 70B"),
    ("mistralai/mistral-large-latest", "Mistral Large"),
    ("qwen/qwen-2.5-72b-instruct", "Qwen 2.5 72B"),
]
```

- [ ] **Step 4: Re-run the focused test**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -only-testing:CosmoOSTests/CosmoWindowRoutingTests/testOpenRouterSettingsCatalogIncludesNewModels test
```

Expected: pass.

## Task 4: Make OPTION+A Picker Show and Store the Expanded Models

**Files:**
- Modify: `UI/CosmoWindow/CosmoWindowViewModel.swift`
- Modify: `UI/CosmoWindow/CosmoWindowView.swift`
- Test: `Tests/CosmoOSTests/CosmoWindowRoutingTests.swift`

- [ ] **Step 1: Add tests for picker options**

Append:

```swift
func testCosmoModelPickerOptionsIncludeRequestedModels() {
    let ids = Set(CosmoModelOption.all.map(\.id))

    XCTAssertTrue(ids.contains("gpt55Thinking"))
    XCTAssertTrue(ids.contains("opus47"))
    XCTAssertTrue(ids.contains("gptChatLatest"))
    XCTAssertTrue(ids.contains("geminiFlashLatest"))
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -only-testing:CosmoOSTests/CosmoWindowRoutingTests/testCosmoModelPickerOptionsIncludeRequestedModels test
```

Expected: compile failure because `CosmoModelOption` is still private to `CosmoWindowView.swift`.

- [ ] **Step 3: Update `currentModelLabel`**

In `CosmoWindowViewModel.currentModelLabel`, replace the switch with:

```swift
var currentModelLabel: String {
    modelOverride?.displayLabel ?? "Auto"
}
```

- [ ] **Step 4: Keep custom-agent preferred model fallback sane**

In `selectAgentProfile(_:)`, replace the current assignment with:

```swift
func selectAgentProfile(_ profile: CustomAgentProfile?) {
    selectedAgentProfileID = profile?.id
    if modelOverride == nil {
        modelOverride = profile?.preferredModelTier
    }
}
```

This preserves an explicit user-selected model and only applies a custom agent's preferred model when the picker is still Auto.

- [ ] **Step 5: Move `CosmoModelOption` out of private scope**

Move the struct from `UI/CosmoWindow/CosmoWindowView.swift` to the bottom of `UI/CosmoWindow/CosmoWindowViewModel.swift` and remove `private`:

```swift
struct CosmoModelOption: Identifiable {
    let id: String
    let tier: AgentModelTier?
    let title: String
    let detail: String
    let icon: String

    static let all: [CosmoModelOption] = [
        CosmoModelOption(id: "auto", tier: nil, title: "Auto", detail: "Route by task and cost", icon: "wand.and.stars"),
        CosmoModelOption(id: "gptChatLatest", tier: .gptChatLatest, title: "GPT Chat Latest", detail: "Best everyday collaborator", icon: "bubble.left.and.bubble.right"),
        CosmoModelOption(id: "geminiFlashLatest", tier: .geminiFlashLatest, title: "Gemini Flash", detail: "Fast and cheaper general work", icon: "bolt"),
        CosmoModelOption(id: "gpt55Thinking", tier: .gpt55Thinking, title: "GPT 5.5 Thinking", detail: "Deep reasoning and hard planning", icon: "brain.head.profile"),
        CosmoModelOption(id: "opus47", tier: .opus47, title: "Opus 4.7", detail: "Deep writing and synthesis", icon: "sparkles"),
        CosmoModelOption(id: "haiku", tier: .sensor, title: "Haiku", detail: "Fast capture and lightweight help", icon: "speedometer"),
        CosmoModelOption(id: "sonnet", tier: .strategist, title: "Sonnet", detail: "Balanced planning and analysis", icon: "point.3.connected.trianglepath.dotted"),
        CosmoModelOption(id: "opus", tier: .writer, title: "Opus 4.6", detail: "Legacy premium writing route", icon: "text.badge.star"),
    ]
}
```

- [ ] **Step 6: Update `CosmoWindowView` to use the moved struct**

Delete the old private `CosmoModelOption` declaration from `CosmoWindowView.swift`. Leave `CosmoModelPickerPopover` using `CosmoModelOption.all`.

- [ ] **Step 7: Fix Auto row selection**

In `CosmoModelPickerPopover.modelRow(_:)`, replace:

```swift
let isSelected = option.tier?.rawValue == selectedTier?.rawValue
```

with:

```swift
let isSelected = option.tier?.rawValue == selectedTier?.rawValue || (option.tier == nil && selectedTier == nil)
```

- [ ] **Step 8: Re-run the focused picker tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -only-testing:CosmoOSTests/CosmoWindowRoutingTests/testCosmoModelPickerOptionsIncludeRequestedModels test
```

Expected: pass.

## Task 5: Improve OpenAI-Compatible Max Token Inference

**Files:**
- Modify: `Agent/Core/LLMProviderAdapter.swift`
- Test: `Tests/CosmoOSTests/CosmoWindowRoutingTests.swift`

- [ ] **Step 1: Add max-token helper tests**

Append:

```swift
func testAgentModelTierMaxTokensForNewModels() {
    XCTAssertEqual(AgentModelTier.gpt55Thinking.maxTokens, 16384)
    XCTAssertEqual(AgentModelTier.opus47.maxTokens, 16384)
    XCTAssertEqual(AgentModelTier.gptChatLatest.maxTokens, 8192)
    XCTAssertEqual(AgentModelTier.geminiFlashLatest.maxTokens, 8192)
}
```

- [ ] **Step 2: Run the focused test**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -only-testing:CosmoOSTests/CosmoWindowRoutingTests/testAgentModelTierMaxTokensForNewModels test
```

Expected: pass after Task 1. If it fails, fix `AgentModelTier.maxTokens` before continuing.

- [ ] **Step 3: Add a shared resolver inside `OpenAIProvider`**

Inside `OpenAIProvider`, before `complete(messages:tools:model:)`, add:

```swift
private func maxTokens(for model: String) -> Int {
    let lower = model.lowercased()
    if lower.contains("gpt-5.5") { return 16384 }
    if lower.contains("gpt-chat-latest") { return 8192 }
    if lower.contains("opus") { return 16384 }
    if lower.contains("sonnet") { return 8192 }
    if lower.contains("gemini-flash-latest") { return 8192 }
    if lower.contains("gemini-3") { return 8192 }
    return 4096
}
```

- [ ] **Step 4: Use the helper in both non-streaming request builders**

In `OpenAIProvider.complete(messages:tools:model:)`, replace the `baseMaxTokens` if/else block with:

```swift
let baseMaxTokens = maxTokens(for: resolvedModel)
```

In `OpenAIProvider.complete(messages:tools:model:systemPrompt:)`, replace the `resolvedMaxTokens` if/else block with:

```swift
let resolvedMaxTokens = maxTokens(for: resolvedModel)
```

- [ ] **Step 5: Use the helper in streaming request builder**

In `completeStreaming(messages:tools:model:onChunk:)`, replace:

```swift
let resolvedMaxTokens: Int
if resolvedModel.contains("opus") { resolvedMaxTokens = 16384 }
else if resolvedModel.contains("sonnet") { resolvedMaxTokens = 8192 }
else { resolvedMaxTokens = 4096 }
```

with:

```swift
let resolvedMaxTokens = maxTokens(for: resolvedModel)
```

- [ ] **Step 6: Build the test target**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -only-testing:CosmoOSTests/CosmoWindowRoutingTests test
```

Expected: pass, or fail only on the next planned prompt tests.

## Task 6: Extract and Upgrade the Default Agent Prompt

**Files:**
- Create: `Agent/Core/CosmoDefaultAgentPrompt.swift`
- Modify: `Agent/Core/AgentContextAssembler.swift`
- Test: `Tests/CosmoOSTests/CosmoWindowMessageRenderingTests.swift`

- [ ] **Step 1: Add failing prompt tests**

Append to `CosmoWindowMessageRenderingTests`:

```swift
func testDefaultAgentPromptIncludesGeneralCollaboratorBehavior() {
    let prompt = CosmoDefaultAgentPrompt.text

    XCTAssertTrue(prompt.contains("general collaborator for knowledge work"))
    XCTAssertTrue(prompt.contains("brainstorm with concrete options"))
    XCTAssertTrue(prompt.contains("retrieve information before answering"))
}

func testDefaultAgentPromptIncludesCostDiscipline() {
    let prompt = CosmoDefaultAgentPrompt.text

    XCTAssertTrue(prompt.contains("Cost discipline"))
    XCTAssertTrue(prompt.contains("Use cheaper models"))
    XCTAssertTrue(prompt.contains("Escalate only when"))
}
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -only-testing:CosmoOSTests/CosmoWindowMessageRenderingTests/testDefaultAgentPromptIncludesGeneralCollaboratorBehavior -only-testing:CosmoOSTests/CosmoWindowMessageRenderingTests/testDefaultAgentPromptIncludesCostDiscipline test
```

Expected: compile failure because `CosmoDefaultAgentPrompt` does not exist.

- [ ] **Step 3: Create `CosmoDefaultAgentPrompt.swift`**

Create `Agent/Core/CosmoDefaultAgentPrompt.swift` with:

```swift
import Foundation

enum CosmoDefaultAgentPrompt {
    static let text: String = [
        identity,
        collaborationStyle,
        retrievalBehavior,
        brainstormingBehavior,
        contentBehavior,
        toolUsePolicy,
        antiHallucination,
        writingQuality,
        costDiscipline,
        swipeAdaptation,
        insightMemory,
    ].joined(separator: "\n\n")

    private static let identity = """
    You are Cosmo, the user's personal creative strategist, research partner, and general collaborator for knowledge work. You help them brainstorm, retrieve information, shape ideas, make decisions, and create content with the judgment of a skilled human collaborator.
    """

    private static let collaborationStyle = """
    COLLABORATION STYLE:
    - Talk like a real person: direct, thoughtful, and specific.
    - Start from what the user said. Do not replace their idea with your own agenda.
    - Brainstorm with concrete options, tradeoffs, and a clear recommendation when one option is stronger.
    - Push back gently when an idea is weak, vague, risky, or unsupported.
    - Keep casual work concise. Expand only when the user asks for depth or the task genuinely needs it.
    - Avoid generic encouragement. Move the work forward.
    """

    private static let retrievalBehavior = """
    RETRIEVAL AND RESEARCH:
    - Retrieve information before answering when the user asks about current facts, sources, statistics, their workspace data, swipes, ideas, content, clients, schedules, or anything that depends on stored context.
    - If the user asks for latest/current information, use web research tools before answering.
    - If a first search is weak, broaden the query or use a listing tool before saying the data is missing.
    - Cite specific titles, source names, or retrieved facts naturally in the answer.
    - If evidence is thin, say so plainly.
    """

    private static let brainstormingBehavior = """
    BRAINSTORMING:
    - Offer useful raw material, not polished theater.
    - Give several directions only when variety helps. Otherwise, give the strongest path first.
    - For content ideas, include the angle, why it might work, and the first usable hook or opening.
    - For planning, turn ambiguity into the next concrete move.
    - For strategy, separate facts, assumptions, and recommendations.
    """

    private static let contentBehavior = """
    CONTENT AND WRITING:
    - When asked for a draft, deliver a usable draft instead of asking for every preference first.
    - Make reasonable creative decisions based on client profiles, swipes, prior content, and the user's stated direction.
    - Do not invent client facts, numbers, stories, credentials, methods, or results.
    - Use [PLACEHOLDER] brackets for missing factual details and briefly flag what is missing.
    - Avoid empty frameworks. If a framework is useful, fill it in.
    """

    private static let toolUsePolicy = """
    TOOL USE:
    - Use tools when the answer depends on Cosmo data or external facts.
    - Never mention internal tool names in the final answer.
    - For destructive actions, explain the intended action and require confirmation when the action could remove or overwrite user work.
    - When the user gives feedback about your behavior, acknowledge it, adjust, and store the preference when appropriate.
    - When the user gives a writing rule, lesson, or creative principle to remember, save it as a lesson rather than a generic preference.
    """

    private static let antiHallucination = """
    ANTI-HALLUCINATION:
    - Never fabricate statistics, revenue figures, deal counts, performance metrics, client niches, or personal history.
    - Never merge clients with similar names. Resolve the client through profile data.
    - When tools return no data, say what you searched and what was missing.
    - Distinguish known facts from inference.
    """

    private static let writingQuality = """
    WRITING QUALITY:
    - Do not use generic openers like "In today's world", "Are you tired of", "Imagine this", or "Picture this".
    - Do not use hollow phrases like "unlock your potential", "game-changer", "revolutionize", "supercharge", or "skyrocket".
    - Prefer specific claims, concrete stories, contrarian observations, and plain language.
    - Match the user's format. Do not over-format a casual chat response.
    """

    private static let costDiscipline = """
    COST DISCIPLINE:
    - Use cheaper models and smaller context when the task is simple, casual, or purely classificatory.
    - Escalate only when the task needs deep reasoning, long-context synthesis, careful writing, or multi-step tool use.
    - Do not run broad retrieval when the user is only making a quick capture.
    - Prefer summaries and focused context over dumping every available record into the prompt.
    - Reuse saved analyses and learned lessons before re-analyzing the same material.
    """

    private static let swipeAdaptation = """
    SWIPE ADAPTATION:
    When the user asks for ideas based on swipes for a specific client, adapt swipes for that client rather than only searching by keyword. Present each idea with a source swipe title, why it works, and usable hook variations. If the adaptation engine returns no results, report that honestly instead of inventing substitutes.
    """

    private static let insightMemory = """
    INSIGHT MEMORY:
    Save durable findings after deep analysis of swipes, content, client patterns, or strategy. Check saved analyses before repeating expensive analysis.
    """
}
```

- [ ] **Step 4: Replace the inline default prompt**

In `AgentContextAssembler`, replace the current body of `static let defaultIdentityPrompt` with:

```swift
static let defaultIdentityPrompt: String = CosmoDefaultAgentPrompt.text
```

- [ ] **Step 5: Add the new prompt file to the Xcode project**

Modify `CosmoOS.xcodeproj/project.pbxproj` with these three exact entries:

Add to the `PBXBuildFile` section:

```text
		CED50BAC7C8849A1A2B5D792 /* CosmoDefaultAgentPrompt.swift in Sources */ = {isa = PBXBuildFile; fileRef = BFB65727C62E4B84AF9062CB /* CosmoDefaultAgentPrompt.swift */; };
```

Add to the `PBXFileReference` section:

```text
		BFB65727C62E4B84AF9062CB /* CosmoDefaultAgentPrompt.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CosmoDefaultAgentPrompt.swift; sourceTree = "<group>"; };
```

Add to the `Agent/Core` group directly after `AgentContextAssembler.swift`:

```text
				BFB65727C62E4B84AF9062CB /* CosmoDefaultAgentPrompt.swift */,
```

Add to the app `PBXSourcesBuildPhase` directly after `AgentContextAssembler.swift in Sources`:

```text
				CED50BAC7C8849A1A2B5D792 /* CosmoDefaultAgentPrompt.swift in Sources */,
```

- [ ] **Step 6: Re-run prompt tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -only-testing:CosmoOSTests/CosmoWindowMessageRenderingTests/testDefaultAgentPromptIncludesGeneralCollaboratorBehavior -only-testing:CosmoOSTests/CosmoWindowMessageRenderingTests/testDefaultAgentPromptIncludesCostDiscipline test
```

Expected: pass.

## Task 7: Make Auto Routing Cheaper Without Breaking Quality

**Files:**
- Modify: `Agent/Core/CosmoAgentService.swift`
- Test: `Tests/CosmoOSTests/CosmoWindowRoutingTests.swift`

- [ ] **Step 1: Add intent routing tests**

Append:

```swift
func testDefaultModelTierKeepsCheapRoutesCheap() {
    XCTAssertEqual(CosmoAgentService.defaultModelTier(for: .capture), .sensor)
    XCTAssertEqual(CosmoAgentService.defaultModelTier(for: .query), .sensor)
    XCTAssertEqual(CosmoAgentService.defaultModelTier(for: .brainstorm), .gptChatLatest)
    XCTAssertEqual(CosmoAgentService.defaultModelTier(for: .draft), .writer)
    XCTAssertEqual(CosmoAgentService.defaultModelTier(for: .analyze), .strategist)
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -only-testing:CosmoOSTests/CosmoWindowRoutingTests/testDefaultModelTierKeepsCheapRoutesCheap test
```

Expected: compile failure because `defaultModelTier(for:)` does not exist.

- [ ] **Step 3: Add a testable routing helper**

In `CosmoAgentService`, add this nonisolated helper near `maxToolIterations(for:)`:

```swift
nonisolated static func defaultModelTier(for intent: AgentIntent) -> AgentModelTier {
    switch intent {
    case .capture, .plan, .query, .correct:
        return .sensor
    case .brainstorm:
        return .gptChatLatest
    case .analyze, .strategy, .debrief, .reflect, .execute, .meta:
        return .strategist
    case .draft:
        return .writer
    }
}
```

- [ ] **Step 4: Use the helper in `processSimpleMessage`**

Replace the existing intent switch that computes `modelTier` with:

```swift
let modelTier: AgentModelTier
if let override = tierOverride {
    modelTier = override
} else {
    modelTier = Self.defaultModelTier(for: intent)
}
```

- [ ] **Step 5: Re-run the focused test**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -only-testing:CosmoOSTests/CosmoWindowRoutingTests/testDefaultModelTierKeepsCheapRoutesCheap test
```

Expected: pass.

## Task 8: Verification

**Files:**
- No new files.

- [ ] **Step 1: Run Cosmo Window focused tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -only-testing:CosmoOSTests/CosmoWindowRoutingTests -only-testing:CosmoOSTests/CosmoWindowMessageRenderingTests test
```

Expected: all Cosmo Window tests pass.

- [ ] **Step 2: Confirm the new prompt file is in the app source phase**

Run:

```bash
rg -n "CosmoDefaultAgentPrompt.swift in Sources|CosmoDefaultAgentPrompt.swift" CosmoOS.xcodeproj/project.pbxproj
```

Expected: at least four matches: one build-file entry, one file-reference entry, one `Agent/Core` group child, and one app source-phase entry.

- [ ] **Step 3: Build the app target**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS build
```

Expected: build succeeds.

- [ ] **Step 4: Manual smoke test in the app**

Run the app, open OPTION+A, and verify:

```text
Auto
GPT Chat Latest
Gemini Flash
GPT 5.5 Thinking
Opus 4.7
Haiku
Sonnet
Opus 4.6
```

Expected: selecting each row closes the popover, updates the chip label, and the next assistant response metadata shows the selected label.

## Implementation Notes

- Do not replace custom-agent model preference storage in this pass. Existing custom agents continue to decode old `AgentModelTier` raw values.
- Do not add live OpenRouter tests. The verified endpoint IDs are documented in the design spec; unit tests should stay deterministic.
- Do not make GPT 5.5 Thinking the Auto default. It is powerful and expensive, and OpenRouter reasoning tokens are billed as output tokens when emitted.
- Keep the Flash Lite router as-is for fast capture and simple routing. This plan changes the normal agent picker and Auto routing, not the router classifier.
