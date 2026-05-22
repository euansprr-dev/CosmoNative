# Command A Continuity, Model Locking, and Context Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Command A preserve conversation continuity by locking the model per conversation, keeping full message history until the selected model's maximum context window requires compaction, and upgrading memory, retrieval, prompt caching, cost controls, observability, and evals into a serious long-running brainstorming system.

**Architecture:** Replace intent-based mid-conversation model routing with a conversation-scoped model lock. Replace fixed small message windows and early summarization with a token-budgeted context builder that includes the full canonical conversation until it approaches the selected model context limit. Add a layered memory system: working frame, artifact state, interaction decisions, preferences, retrieval evidence, and archival memory. Split stable cacheable prompt layers from per-turn dynamic context, then add cost/latency telemetry and continuity evals so regressions are caught before they reach the product.

**Tech Stack:** Swift 5, SwiftUI, existing `CosmoAgentService`, `AgentConversation`, `ConversationMemoryService`, `AgentModelTier`, OpenRouter providers, XCTest.

---

## Non-Negotiable Product Rules

1. Command A auto mode uses `AgentModelTier.geminiFlashLatest` for every turn unless the user manually selects another model.
2. Once a conversation has a selected model, every later turn in that conversation uses that same model.
3. Failover must not silently switch to another model inside a conversation. Retry the same model when appropriate; if it cannot complete, show an error and keep the model unchanged.
4. Compaction, summarization-as-replacement, or dropping older user/assistant turns is forbidden until the estimated prompt would exceed the selected model's usable context window.
5. Summaries may be generated for search, sidebar previews, and continuity metadata, but raw conversation turns must remain the primary prompt context while they fit.
6. The UI token counter must reflect the selected model's context window, not a generic message estimate.
7. Memory upgrades must not violate rule 4: summaries, artifact state, retrieval packs, and archival recall are additive while raw conversation context still fits.
8. Prompt caching must reduce cost without changing behavior. Cached blocks are stable identity/method/tool/profile material; dynamic blocks are the current turn, current artifact state, working frame, and retrieved evidence.
9. Cost controls must be transparent and predictable. The system can reduce duplicated static prompt cost with caching, but it cannot secretly change models or compact early to save money.
10. Continuity quality must be testable. Every major memory/context change needs regression fixtures for locked decisions, rejected directions, continuation requests, model lock, and no-early-compaction behavior.

## File Map

- Modify `Agent/Models/AgentTypes.swift`
  - Make Gemini 3 Flash the default auto model and add a same-model retry chain.
- Modify `Agent/Core/CosmoAgentService.swift`
  - Add conversation-scoped model locking and replace fixed 12/8/6/4 message windows with model-window-aware history assembly.
- Modify `Agent/Core/LLMProviderAdapter.swift`
  - Prevent failover chains from switching models when the conversation model lock is active.
- Modify `Agent/Memory/ConversationMemoryService.swift`
  - Stop using `summarizationThreshold = 15` as a trigger for replacing conversation context.
- Modify `Agent/Core/AgentContextAssembler.swift`
  - Keep conversation summaries additive only, add layered memory sections, and split stable cacheable prompt content from dynamic per-turn content.
- Create `Agent/Context/CommandAWorkingFrame.swift`
  - Stores the current objective, active artifact, locked decisions, open questions, rejected directions, and current section.
- Create `Agent/Context/CommandAArtifactState.swift`
  - Stores structured creative artifacts such as carousel slides, hooks, outlines, sections, approval status, and revision history.
- Create `Agent/Context/CommandAInteractionMemory.swift`
  - Stores accepted/rejected ideas, user feedback, constraints, and continuity-critical decisions.
- Create `Agent/Context/CommandAContextBudgeter.swift`
  - Builds the final prompt plan from raw history, stable prompt blocks, dynamic memory, retrieval packs, and model context limits.
- Create `Agent/Context/CommandAPromptCachePlanner.swift`
  - Assigns cache boundaries and TTLs to stable prompt blocks without caching per-turn state.
- Create `Agent/Telemetry/CommandAITelemetry.swift`
  - Records model, context tokens, cache hits, cache writes, retrieval counts, compaction events, cost estimates, and continuity warnings.
- Modify `UI/CosmoWindow/CosmoWindowViewModel.swift`
  - Persist the selected model per conversation, route Auto to Gemini 3 Flash, surface working frame, token budget, cache, and continuity diagnostics.
- Modify `UI/FocusMode/CosmoAI/CosmoAIFocusModeViewModel.swift`
  - Apply the same model lock and context-window rules to the focus AI panel.
- Modify `UI/FocusMode/CosmoAI/CosmoAIFocusModeView.swift`
  - Replace "Auto" semantics with "Gemini 3 Flash" as the default label unless no conversation has started.
- Test `Tests/CosmoOSTests/CosmoWindowRoutingTests.swift`
  - Covers default model locking and no cross-model failover.
- Create `Tests/CosmoOSTests/CommandAContinuityContextTests.swift`
  - Covers full-history retention and compaction thresholds.
- Create `Tests/CosmoOSTests/CommandAMemoryArchitectureTests.swift`
  - Covers working frame extraction, artifact state locking, accepted/rejected decision memory, and archival recall.
- Create `Tests/CosmoOSTests/CommandAPromptCachePlannerTests.swift`
  - Covers cacheable vs dynamic block separation.
- Create `Tests/CosmoOSTests/CommandAITelemetryTests.swift`
  - Covers cost/cache/context event emission.

## Task 1: Lock Auto Mode to Gemini 3 Flash

**Files:**
- Modify: `Agent/Models/AgentTypes.swift`
- Modify: `Agent/Core/CosmoAgentService.swift`
- Test: `Tests/CosmoOSTests/CosmoWindowRoutingTests.swift`

- [ ] **Step 1: Add failing tests for Auto model invariants**

Append to `Tests/CosmoOSTests/CosmoWindowRoutingTests.swift`:

```swift
func testAutoModeAlwaysDefaultsToGeminiFlashLatest() {
    for intent in AgentIntent.allCases {
        XCTAssertEqual(
            CosmoAgentService.defaultModelTier(for: intent),
            .geminiFlashLatest,
            "Auto mode must not switch models for intent \(intent.rawValue)"
        )
    }
}

func testGeminiFlashChainDoesNotFailOverToAnotherModel() {
    let chain = ModelFailoverChain.chain(for: .geminiFlashLatest, allowCrossModelFailover: false)
    XCTAssertEqual(chain.models.map(\.modelId), [AgentModelTier.geminiFlashLatest.modelId])
}
```

- [ ] **Step 2: Run the focused routing tests and verify failure**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoWindowRoutingTests
```

Expected: FAIL because `.capture`, `.plan`, `.correct`, `.analyze`, `.strategy`, `.debrief`, `.reflect`, `.execute`, and `.meta` still route away from Gemini 3 Flash.

- [ ] **Step 3: Change default model routing**

Replace `CosmoAgentService.defaultModelTier(for:)` with:

```swift
nonisolated static func defaultModelTier(for intent: AgentIntent) -> AgentModelTier {
    .geminiFlashLatest
}
```

- [ ] **Step 4: Add same-model failover chain support**

In `Agent/Models/AgentTypes.swift`, add an overload:

```swift
static func chain(for tier: AgentModelTier, allowCrossModelFailover: Bool) -> ModelFailoverChain {
    if !allowCrossModelFailover {
        return ModelFailoverChain(models: [
            FailoverModel(modelId: tier.modelId, maxRetries: 2, label: tier.displayLabel)
        ])
    }
    return chain(for: tier)
}
```

- [ ] **Step 5: Re-run the focused routing tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoWindowRoutingTests
```

Expected: PASS for the new Auto/Gemini tests and existing routing tests updated to the new invariant.

## Task 2: Persist a Conversation-Scoped Model Lock

**Files:**
- Modify: `Agent/Models/AgentTypes.swift`
- Modify: `Agent/Memory/ConversationMemoryService.swift`
- Modify: `Agent/Core/CosmoAgentService.swift`
- Test: `Tests/CosmoOSTests/CosmoWindowRoutingTests.swift`

- [ ] **Step 1: Add failing persistence test**

Append:

```swift
func testConversationModelLockPersistsManualSelection() {
    var conversation = AgentConversation(id: "conversation-1", source: .inApp)
    conversation.modelLock = .opus47

    XCTAssertEqual(conversation.effectiveModelTier(userOverride: nil), .opus47)
    XCTAssertEqual(conversation.effectiveModelTier(userOverride: .geminiFlashLatest), .geminiFlashLatest)
}
```

- [ ] **Step 2: Add model lock fields**

In `AgentConversation`, add:

```swift
var modelLock: AgentModelTier?

mutating func applyModelSelection(_ selected: AgentModelTier?) {
    modelLock = selected ?? modelLock ?? .geminiFlashLatest
}

func effectiveModelTier(userOverride: AgentModelTier?) -> AgentModelTier {
    userOverride ?? modelLock ?? .geminiFlashLatest
}
```

- [ ] **Step 3: Persist and restore the model lock**

In `ConversationMemoryService.saveConversation`, add `modelLock` to metadata:

```swift
"modelLock": conv.modelLock?.rawValue as Any
```

In `decodeConversation(from:)`, restore it:

```swift
if let rawModelLock = metaDict["modelLock"] as? String {
    conv.modelLock = AgentModelTier(rawValue: rawModelLock)
}
```

- [ ] **Step 4: Use the model lock in message processing**

After loading or creating a conversation in `CosmoAgentService.processMessage`, apply:

```swift
conversation.applyModelSelection(tierOverride)
let modelTier = conversation.effectiveModelTier(userOverride: tierOverride)
```

Use this `modelTier` for provider completion and same-model retry chain selection.

- [ ] **Step 5: Commit model locking**

```bash
git add Agent/Models/AgentTypes.swift Agent/Memory/ConversationMemoryService.swift Agent/Core/CosmoAgentService.swift Tests/CosmoOSTests/CosmoWindowRoutingTests.swift
git commit -m "fix: lock Command A model per conversation"
```

## Task 3: Remove Early Conversation Compaction

**Files:**
- Modify: `Agent/Core/CosmoAgentService.swift`
- Modify: `Agent/Memory/ConversationMemoryService.swift`
- Modify: `Agent/Core/AgentContextAssembler.swift`
- Create: `Tests/CosmoOSTests/CommandAContinuityContextTests.swift`

- [ ] **Step 1: Add failing full-history test**

Create `Tests/CosmoOSTests/CommandAContinuityContextTests.swift`:

```swift
import XCTest
@testable import CosmoOS

final class CommandAContinuityContextTests: XCTestCase {
    func testHistoryBuilderKeepsAllMessagesWhenUnderModelWindow() {
        var messages: [AgentMessage] = []
        for index in 1...40 {
            messages.append(.user("User decision \(index): keep slide \(index) direction."))
            messages.append(.assistant("Acknowledged decision \(index)."))
        }

        let window = CosmoAgentService.buildContextWindowForTests(
            messages,
            modelTier: .geminiFlashLatest,
            reservedOutputTokens: 8_192,
            reservedSystemTokens: 12_000
        )

        XCTAssertEqual(window.count, messages.count)
        XCTAssertTrue(window.first?.content.contains("User decision 1") == true)
    }
}
```

- [ ] **Step 2: Expose a testable context-window builder**

Replace the private fixed-window logic with:

```swift
nonisolated static func buildModelAwareHistoryWindow(
    _ messages: [AgentMessage],
    modelTier: AgentModelTier,
    reservedOutputTokens: Int,
    reservedSystemTokens: Int
) -> [AgentMessage] {
    let usableInputWindow = max(0, modelTier.contextWindow - reservedOutputTokens - reservedSystemTokens)
    var selected = messages

    while estimatedTokens(selected) > usableInputWindow, selected.count > 1 {
        selected.removeFirst()
    }

    return selected
}

nonisolated private static func estimatedTokens(_ messages: [AgentMessage]) -> Int {
    messages.reduce(0) { $0 + max(1, $1.content.count / 4) }
}
```

Add a test-only wrapper:

```swift
nonisolated static func buildContextWindowForTests(
    _ messages: [AgentMessage],
    modelTier: AgentModelTier,
    reservedOutputTokens: Int,
    reservedSystemTokens: Int
) -> [AgentMessage] {
    buildModelAwareHistoryWindow(
        messages,
        modelTier: modelTier,
        reservedOutputTokens: reservedOutputTokens,
        reservedSystemTokens: reservedSystemTokens
    )
}
```

- [ ] **Step 3: Replace fixed small windows**

Replace calls to `buildTokenAwareWindow(conversation.messages)` and `buildLightweightWindow(conversation.messages)` in `CosmoAgentService` with:

```swift
let rawWindow = Self.buildModelAwareHistoryWindow(
    conversation.messages,
    modelTier: modelTier,
    reservedOutputTokens: modelTier.maxTokens,
    reservedSystemTokens: systemPrompt.estimatedTokenCount
)
```

Add to `SystemPrompt`:

```swift
var estimatedTokenCount: Int {
    max(1, (cached.count + dynamic.count) / 4)
}
```

- [ ] **Step 4: Stop summaries from replacing raw context before the window is full**

In `ConversationMemoryService.saveConversation`, remove automatic summary generation based only on message count:

```swift
// Do not summarize merely because the conversation has many messages.
// Summaries are created by explicit archival/compaction paths only.
```

In `AgentContextAssembler.conversationContext`, keep `conv.summary` as additive metadata only. Remove the branch that calls `summarizeConversation(conv)` when `conv.messages.count > summarizationThreshold`.

- [ ] **Step 5: Keep tool-result compression separate from user/assistant context**

Retain `compressOldToolResults` only for large tool payloads, but do not compress ordinary user/assistant turns. Add a test that a 40-turn brainstorming conversation keeps all user and assistant messages when under the model limit.

- [ ] **Step 6: Run continuity tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CommandAContinuityContextTests
```

Expected: PASS.

## Task 4: Apply the Same Rules to Focus AI

**Files:**
- Modify: `UI/FocusMode/CosmoAI/CosmoAIFocusModeViewModel.swift`
- Modify: `UI/FocusMode/CosmoAI/CosmoAIFocusModeView.swift`
- Test: `Tests/CosmoOSTests/CommandAContinuityContextTests.swift`

- [ ] **Step 1: Add test for focus-mode default model**

Append:

```swift
func testFocusModeUsesGeminiFlashWhenNoManualOverrideExists() {
    XCTAssertEqual(CosmoAIFocusModeViewModel.defaultModelTier(userOverride: nil), .geminiFlashLatest)
    XCTAssertEqual(CosmoAIFocusModeViewModel.defaultModelTier(userOverride: .opus47), .opus47)
}
```

- [ ] **Step 2: Add static model resolver**

In `CosmoAIFocusModeViewModel`, add:

```swift
nonisolated static func defaultModelTier(userOverride: AgentModelTier?) -> AgentModelTier {
    userOverride ?? .geminiFlashLatest
}
```

- [ ] **Step 3: Pass Gemini explicitly instead of nil Auto**

Replace:

```swift
tierOverride: modelOverride,
```

with:

```swift
tierOverride: Self.defaultModelTier(userOverride: modelOverride),
```

- [ ] **Step 4: Update menu labels**

In `CosmoAIFocusModeView`, change the first menu row from `Auto` to `Gemini 3 Flash` and update `modelLabel` so `nil` displays `Gemini 3 Flash`, not `Auto`.

- [ ] **Step 5: Run focus-related tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CommandAContinuityContextTests
```

Expected: PASS.

## Task 5: Add Context Window Telemetry

**Files:**
- Modify: `UI/CosmoWindow/CosmoWindowViewModel.swift`
- Modify: `UI/FocusMode/CosmoAI/CosmoAIFocusModeView.swift`
- Test: `Tests/CosmoOSTests/CommandAContinuityContextTests.swift`

- [ ] **Step 1: Add token budget display helper**

Create a helper on `AgentModelTier`:

```swift
var displayContextWindow: String {
    switch contextWindow {
    case 1_000_000...:
        return "1M"
    default:
        return "\(contextWindow / 1_000)K"
    }
}
```

- [ ] **Step 2: Show selected model budget in UI**

Replace generic token text with:

```swift
Text("\(tokenCount) / \(activeModelTier.displayContextWindow) tokens")
```

- [ ] **Step 3: Log compaction only when it actually happens**

When `buildModelAwareHistoryWindow` drops any turns, emit a context trace event:

```swift
ConsoleLog.warning(
    "Context window reached for \(modelTier.displayLabel); compacted \(droppedCount) oldest message(s)",
    subsystem: .llm
)
```

- [ ] **Step 4: Run routing and continuity tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoWindowRoutingTests -only-testing:CosmoOSTests/CommandAContinuityContextTests
```

Expected: PASS.

## Task 6: Add a Conversation Working Frame

**Files:**
- Create: `Agent/Context/CommandAWorkingFrame.swift`
- Modify: `Agent/Models/AgentTypes.swift`
- Modify: `Agent/Memory/ConversationMemoryService.swift`
- Modify: `Agent/Core/AgentContextAssembler.swift`
- Create: `Tests/CosmoOSTests/CommandAMemoryArchitectureTests.swift`

- [ ] **Step 1: Add failing working-frame tests**

Create `Tests/CosmoOSTests/CommandAMemoryArchitectureTests.swift`:

```swift
import XCTest
@testable import CosmoOS

final class CommandAMemoryArchitectureTests: XCTestCase {
    func testWorkingFramePreservesLockedDecisionsAndCurrentSection() {
        var frame = CommandAWorkingFrame(conversationID: "conversation-1")
        frame.currentObjective = "Brainstorm an Instagram carousel about forecasting homeopathy demand."
        frame.activeArtifactID = "artifact-carousel-1"
        frame.currentSection = "second half of the post"
        frame.lockDecision("Slides 1-3 are approved and must not be rewritten.")
        frame.rejectDirection("Do not restart from the original hook.")

        let prompt = frame.promptBlock

        XCTAssertTrue(prompt.contains("Current objective: Brainstorm an Instagram carousel"))
        XCTAssertTrue(prompt.contains("Current section: second half of the post"))
        XCTAssertTrue(prompt.contains("LOCKED: Slides 1-3 are approved and must not be rewritten."))
        XCTAssertTrue(prompt.contains("REJECTED: Do not restart from the original hook."))
    }
}
```

- [ ] **Step 2: Run the memory architecture tests and verify failure**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CommandAMemoryArchitectureTests
```

Expected: FAIL because `CommandAWorkingFrame` does not exist.

- [ ] **Step 3: Implement the working frame model**

Create `Agent/Context/CommandAWorkingFrame.swift`:

```swift
import Foundation

struct CommandAWorkingFrame: Codable, Equatable, Sendable {
    var conversationID: String
    var currentObjective: String
    var activeArtifactID: String?
    var currentSection: String?
    var lockedDecisions: [String]
    var openQuestions: [String]
    var rejectedDirections: [String]
    var updatedAt: Date

    init(
        conversationID: String,
        currentObjective: String = "",
        activeArtifactID: String? = nil,
        currentSection: String? = nil,
        lockedDecisions: [String] = [],
        openQuestions: [String] = [],
        rejectedDirections: [String] = [],
        updatedAt: Date = Date()
    ) {
        self.conversationID = conversationID
        self.currentObjective = currentObjective
        self.activeArtifactID = activeArtifactID
        self.currentSection = currentSection
        self.lockedDecisions = lockedDecisions
        self.openQuestions = openQuestions
        self.rejectedDirections = rejectedDirections
        self.updatedAt = updatedAt
    }

    mutating func lockDecision(_ decision: String) {
        appendUnique(decision, to: &lockedDecisions)
        updatedAt = Date()
    }

    mutating func addOpenQuestion(_ question: String) {
        appendUnique(question, to: &openQuestions)
        updatedAt = Date()
    }

    mutating func rejectDirection(_ direction: String) {
        appendUnique(direction, to: &rejectedDirections)
        updatedAt = Date()
    }

    private func appendUnique(_ value: String, to array: inout [String]) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !array.contains(trimmed) else { return }
        array.append(trimmed)
    }

    var promptBlock: String {
        var lines = ["[COMMAND A WORKING FRAME]"]
        if !currentObjective.isEmpty {
            lines.append("Current objective: \(currentObjective)")
        }
        if let activeArtifactID, !activeArtifactID.isEmpty {
            lines.append("Active artifact: \(activeArtifactID)")
        }
        if let currentSection, !currentSection.isEmpty {
            lines.append("Current section: \(currentSection)")
        }
        for decision in lockedDecisions {
            lines.append("LOCKED: \(decision)")
        }
        for question in openQuestions {
            lines.append("OPEN: \(question)")
        }
        for direction in rejectedDirections {
            lines.append("REJECTED: \(direction)")
        }
        return lines.joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Add working frame to conversation persistence**

In `AgentConversation`, add:

```swift
var workingFrame: CommandAWorkingFrame?
```

In `ConversationMemoryService.saveConversation`, encode `workingFrame` into `structuredDict`:

```swift
if let workingFrame = conv.workingFrame,
   let data = try? JSONEncoder().encode(workingFrame),
   let json = try? JSONSerialization.jsonObject(with: data) {
    structuredDict["workingFrame"] = json
}
```

In `decodeConversation(from:)`, restore it:

```swift
if let frameObject = structuredDict["workingFrame"],
   let data = try? JSONSerialization.data(withJSONObject: frameObject),
   let frame = try? JSONDecoder().decode(CommandAWorkingFrame.self, from: data) {
    conv.workingFrame = frame
}
```

- [ ] **Step 5: Inject the working frame into dynamic prompt context**

In `AgentContextAssembler.assembleSystemPrompt`, before conversation history, append:

```swift
if let frame = conversation?.workingFrame {
    dynamicSections.append((priority: 0, content: frame.promptBlock))
    usedTokens += estimateTokens(frame.promptBlock)
}
```

- [ ] **Step 6: Run memory architecture tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CommandAMemoryArchitectureTests
```

Expected: PASS.

## Task 7: Add Structured Artifact State for Brainstorming

**Files:**
- Create: `Agent/Context/CommandAArtifactState.swift`
- Modify: `Agent/Models/AgentTypes.swift`
- Modify: `Agent/Core/AgentContextAssembler.swift`
- Test: `Tests/CosmoOSTests/CommandAMemoryArchitectureTests.swift`

- [ ] **Step 1: Add failing artifact-state tests**

Append:

```swift
func testArtifactStateMarksApprovedSectionsAsLocked() {
    var artifact = CommandAArtifactState(
        id: "artifact-carousel-1",
        kind: .carousel,
        title: "Homeopathy forecasting carousel"
    )
    artifact.upsertSection(number: 1, title: "Hook", body: "Demand is seasonal.", status: .approved)
    artifact.upsertSection(number: 4, title: "Second part", body: "Explore inventory risk.", status: .drafting)

    let prompt = artifact.promptBlock

    XCTAssertTrue(prompt.contains("Section 1 [approved, locked] Hook"))
    XCTAssertTrue(prompt.contains("Section 4 [drafting] Second part"))
}
```

- [ ] **Step 2: Implement artifact state**

Create `Agent/Context/CommandAArtifactState.swift`:

```swift
import Foundation

enum CommandAArtifactKind: String, Codable, Sendable, Equatable {
    case carousel
    case post
    case thread
    case script
    case outline
    case note
}

enum CommandAArtifactSectionStatus: String, Codable, Sendable, Equatable {
    case drafting
    case proposed
    case approved
    case rejected

    var promptLabel: String {
        switch self {
        case .approved: return "approved, locked"
        case .drafting: return "drafting"
        case .proposed: return "proposed"
        case .rejected: return "rejected"
        }
    }
}

struct CommandAArtifactSection: Codable, Equatable, Sendable, Identifiable {
    var id: String { "\(number)" }
    var number: Int
    var title: String
    var body: String
    var status: CommandAArtifactSectionStatus
}

struct CommandAArtifactState: Codable, Equatable, Sendable {
    var id: String
    var kind: CommandAArtifactKind
    var title: String
    var sections: [CommandAArtifactSection]
    var updatedAt: Date

    init(id: String, kind: CommandAArtifactKind, title: String, sections: [CommandAArtifactSection] = [], updatedAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.title = title
        self.sections = sections
        self.updatedAt = updatedAt
    }

    mutating func upsertSection(number: Int, title: String, body: String, status: CommandAArtifactSectionStatus) {
        let section = CommandAArtifactSection(number: number, title: title, body: body, status: status)
        if let index = sections.firstIndex(where: { $0.number == number }) {
            sections[index] = section
        } else {
            sections.append(section)
            sections.sort { $0.number < $1.number }
        }
        updatedAt = Date()
    }

    var promptBlock: String {
        var lines = ["[ACTIVE ARTIFACT STATE]", "\(kind.rawValue): \(title)", "Artifact ID: \(id)"]
        for section in sections.sorted(by: { $0.number < $1.number }) {
            lines.append("Section \(section.number) [\(section.status.promptLabel)] \(section.title)")
            lines.append(section.body)
        }
        return lines.joined(separator: "\n")
    }
}
```

- [ ] **Step 3: Persist artifact state**

In `AgentConversation`, add:

```swift
var artifactStates: [CommandAArtifactState] = []
```

Persist and restore it in `ConversationMemoryService` using the same `structuredDict` JSON encoding pattern as `workingFrame`.

- [ ] **Step 4: Inject active artifact state immediately after the working frame**

In `AgentContextAssembler.assembleSystemPrompt`, add:

```swift
if let artifactID = conversation?.workingFrame?.activeArtifactID,
   let artifact = conversation?.artifactStates.first(where: { $0.id == artifactID }) {
    dynamicSections.append((priority: 0, content: artifact.promptBlock))
    usedTokens += estimateTokens(artifact.promptBlock)
}
```

- [ ] **Step 5: Add a continuity guard instruction**

Append this dynamic block when any artifact has approved sections:

```swift
let lockedSections = conversation?.artifactStates.flatMap { artifact in
    artifact.sections.filter { $0.status == .approved }.map { "\(artifact.title) section \($0.number)" }
} ?? []
if !lockedSections.isEmpty {
    dynamicSections.append((priority: 0, content: "[CONTINUITY GUARD]\nDo not rewrite or replace approved/locked sections unless the user explicitly asks. Locked sections: \(lockedSections.joined(separator: ", "))"))
}
```

- [ ] **Step 6: Run memory architecture tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CommandAMemoryArchitectureTests
```

Expected: PASS.

## Task 8: Add Interaction Memory and Archival Recall

**Files:**
- Create: `Agent/Context/CommandAInteractionMemory.swift`
- Modify: `Agent/Context/CosmoMemoryService.swift`
- Modify: `Agent/Core/AgentContextAssembler.swift`
- Test: `Tests/CosmoOSTests/CommandAMemoryArchitectureTests.swift`

- [ ] **Step 1: Add failing interaction-memory test**

Append:

```swift
func testInteractionMemorySeparatesAcceptedAndRejectedDirections() {
    var memory = CommandAInteractionMemory(conversationID: "conversation-1")
    memory.accept("Use forecasting angle for the first half.")
    memory.reject("Do not turn it into a generic marketing carousel.")

    let prompt = memory.promptBlock

    XCTAssertTrue(prompt.contains("ACCEPTED: Use forecasting angle"))
    XCTAssertTrue(prompt.contains("REJECTED: Do not turn it into"))
}
```

- [ ] **Step 2: Implement interaction memory**

Create `Agent/Context/CommandAInteractionMemory.swift`:

```swift
import Foundation

struct CommandAInteractionMemory: Codable, Equatable, Sendable {
    var conversationID: String
    var acceptedDirections: [String] = []
    var rejectedDirections: [String] = []
    var userCorrections: [String] = []
    var updatedAt: Date = Date()

    mutating func accept(_ value: String) {
        appendUnique(value, to: &acceptedDirections)
    }

    mutating func reject(_ value: String) {
        appendUnique(value, to: &rejectedDirections)
    }

    mutating func correct(_ value: String) {
        appendUnique(value, to: &userCorrections)
    }

    private mutating func appendUnique(_ value: String, to array: inout [String]) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !array.contains(trimmed) else { return }
        array.append(trimmed)
        updatedAt = Date()
    }

    var promptBlock: String {
        var lines = ["[INTERACTION MEMORY]"]
        acceptedDirections.forEach { lines.append("ACCEPTED: \($0)") }
        rejectedDirections.forEach { lines.append("REJECTED: \($0)") }
        userCorrections.forEach { lines.append("CORRECTION: \($0)") }
        return lines.joined(separator: "\n")
    }
}
```

- [ ] **Step 3: Persist interaction memory on conversation**

In `AgentConversation`, add:

```swift
var interactionMemory: CommandAInteractionMemory?
```

Persist and restore it in `ConversationMemoryService` using the same structured JSON approach as the working frame.

- [ ] **Step 4: Upgrade archival memory to structured entries**

In `CosmoMemoryService`, add:

```swift
struct CommandAArchivalMemoryEntry: Codable, Equatable, Sendable, Identifiable {
    var id: UUID = UUID()
    var conversationID: String
    var text: String
    var tags: [String]
    var createdAt: Date = Date()
}
```

Add:

```swift
private var commandAArchivalEntries: [CommandAArchivalMemoryEntry] = []

func addCommandAArchivalMemory(_ entry: CommandAArchivalMemoryEntry) async throws {
    commandAArchivalEntries.append(entry)
}

func searchCommandAArchivalMemory(query: String, limit: Int = 5) async throws -> [CommandAArchivalMemoryEntry] {
    let terms = query.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 }
    guard !terms.isEmpty else { return Array(commandAArchivalEntries.suffix(limit)) }
    return commandAArchivalEntries
        .filter { entry in
            let haystack = ([entry.text] + entry.tags).joined(separator: " ").lowercased()
            return terms.contains { haystack.contains($0) }
        }
        .suffix(limit)
}
```

- [ ] **Step 5: Inject interaction and archival memory as additive context**

In `AgentContextAssembler.assembleSystemPrompt`, after artifact state:

```swift
if let interactionMemory = conversation?.interactionMemory {
    dynamicSections.append((priority: 0, content: interactionMemory.promptBlock))
    usedTokens += estimateTokens(interactionMemory.promptBlock)
}
```

Only retrieve archival memory when the raw conversation still fits and there is budget remaining after raw history reservations.

- [ ] **Step 6: Run memory tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CommandAMemoryArchitectureTests
```

Expected: PASS.

## Task 9: Add Context Budgeter With Explicit Prompt Plan

**Files:**
- Create: `Agent/Context/CommandAContextBudgeter.swift`
- Modify: `Agent/Core/CosmoAgentService.swift`
- Modify: `Agent/Core/AgentContextAssembler.swift`
- Test: `Tests/CosmoOSTests/CommandAContinuityContextTests.swift`

- [ ] **Step 1: Add failing prompt-plan test**

Append to `CommandAContinuityContextTests`:

```swift
func testContextBudgeterPrioritizesRawHistoryBeforeRecallMemory() {
    let plan = CommandAContextBudgeter.plan(
        modelTier: .geminiFlashLatest,
        systemTokens: 10_000,
        outputTokens: 8_192,
        rawHistoryTokens: 20_000,
        workingFrameTokens: 500,
        artifactTokens: 1_000,
        retrievalTokens: 2_000,
        archivalRecallTokens: 5_000
    )

    XCTAssertTrue(plan.includesRawHistory)
    XCTAssertTrue(plan.includesWorkingFrame)
    XCTAssertTrue(plan.includesArtifactState)
    XCTAssertTrue(plan.includesRetrieval)
    XCTAssertTrue(plan.includesArchivalRecall)
    XCTAssertFalse(plan.requiresCompaction)
}
```

- [ ] **Step 2: Implement prompt planning**

Create `Agent/Context/CommandAContextBudgeter.swift`:

```swift
import Foundation

struct CommandAContextPromptPlan: Equatable, Sendable {
    var modelTier: AgentModelTier
    var usableInputTokens: Int
    var totalRequestedTokens: Int
    var includesWorkingFrame: Bool
    var includesArtifactState: Bool
    var includesRawHistory: Bool
    var includesRetrieval: Bool
    var includesArchivalRecall: Bool
    var requiresCompaction: Bool
}

enum CommandAContextBudgeter {
    static func plan(
        modelTier: AgentModelTier,
        systemTokens: Int,
        outputTokens: Int,
        rawHistoryTokens: Int,
        workingFrameTokens: Int,
        artifactTokens: Int,
        retrievalTokens: Int,
        archivalRecallTokens: Int
    ) -> CommandAContextPromptPlan {
        let usableInput = max(0, modelTier.contextWindow - outputTokens)
        let requiredCore = systemTokens + workingFrameTokens + artifactTokens + rawHistoryTokens
        let optionalRetrieval = retrievalTokens
        let optionalRecall = archivalRecallTokens
        let totalRequested = requiredCore + optionalRetrieval + optionalRecall
        let canFitAll = totalRequested <= usableInput
        let canFitRetrieval = requiredCore + optionalRetrieval <= usableInput

        return CommandAContextPromptPlan(
            modelTier: modelTier,
            usableInputTokens: usableInput,
            totalRequestedTokens: totalRequested,
            includesWorkingFrame: workingFrameTokens > 0,
            includesArtifactState: artifactTokens > 0,
            includesRawHistory: rawHistoryTokens > 0,
            includesRetrieval: retrievalTokens > 0 && canFitRetrieval,
            includesArchivalRecall: archivalRecallTokens > 0 && canFitAll,
            requiresCompaction: requiredCore > usableInput
        )
    }
}
```

- [ ] **Step 3: Use prompt plan before assembling LLM messages**

In `CosmoAgentService.processSimpleMessage`, compute the prompt plan before history selection and pass the model tier into `buildModelAwareHistoryWindow`. Only drop raw messages when `plan.requiresCompaction == true`.

- [ ] **Step 4: Run context tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CommandAContinuityContextTests
```

Expected: PASS.

## Task 10: Add Prompt Cache Planner

**Files:**
- Create: `Agent/Context/CommandAPromptCachePlanner.swift`
- Modify: `Agent/Core/AgentContextAssembler.swift`
- Modify: `Cosmo/ResearchService.swift`
- Modify: `Agent/Core/LLMProviderAdapter.swift`
- Create: `Tests/CosmoOSTests/CommandAPromptCachePlannerTests.swift`

- [ ] **Step 1: Add failing cache-planner tests**

Create `Tests/CosmoOSTests/CommandAPromptCachePlannerTests.swift`:

```swift
import XCTest
@testable import CosmoOS

final class CommandAPromptCachePlannerTests: XCTestCase {
    func testCachePlannerOnlyCachesStableBlocks() {
        let blocks = [
            CommandAPromptBlock(kind: .identity, text: "identity"),
            CommandAPromptBlock(kind: .tools, text: "tools"),
            CommandAPromptBlock(kind: .clientProfile, text: "profile"),
            CommandAPromptBlock(kind: .workingFrame, text: "current task"),
            CommandAPromptBlock(kind: .rawHistory, text: "latest messages")
        ]

        let planned = CommandAPromptCachePlanner.plan(blocks)
        let cachedKinds = planned.filter(\.cacheControl).map(\.kind)

        XCTAssertEqual(cachedKinds, [.identity, .tools, .clientProfile])
        XCTAssertFalse(planned.first { $0.kind == .workingFrame }!.cacheControl)
        XCTAssertFalse(planned.first { $0.kind == .rawHistory }!.cacheControl)
    }
}
```

- [ ] **Step 2: Implement prompt block and cache planner**

Create `Agent/Context/CommandAPromptCachePlanner.swift`:

```swift
import Foundation

enum CommandAPromptBlockKind: String, Codable, Sendable, Equatable {
    case identity
    case methodology
    case tools
    case clientProfile
    case preferences
    case workingFrame
    case artifactState
    case interactionMemory
    case retrieval
    case rawHistory
    case currentTurn
}

struct CommandAPromptBlock: Equatable, Sendable {
    var kind: CommandAPromptBlockKind
    var text: String
}

struct CommandAPlannedPromptBlock: Equatable, Sendable {
    var kind: CommandAPromptBlockKind
    var text: String
    var cacheControl: Bool
    var ttl: String?
}

enum CommandAPromptCachePlanner {
    private static let cacheableKinds: Set<CommandAPromptBlockKind> = [
        .identity,
        .methodology,
        .tools,
        .clientProfile,
        .preferences
    ]

    static func plan(_ blocks: [CommandAPromptBlock]) -> [CommandAPlannedPromptBlock] {
        blocks.map { block in
            let cacheable = cacheableKinds.contains(block.kind)
            return CommandAPlannedPromptBlock(
                kind: block.kind,
                text: block.text,
                cacheControl: cacheable,
                ttl: cacheable ? "1h" : nil
            )
        }
    }
}
```

- [ ] **Step 3: Convert system prompt assembly to block kinds**

In `AgentContextAssembler`, keep returning `SystemPrompt` for existing provider compatibility, but internally build `CommandAPromptBlock` values so the stable/dynamic split is explicit. Map cached blocks into `SystemPrompt.cached` and dynamic blocks into `SystemPrompt.dynamic`.

- [ ] **Step 4: Preserve OpenRouter/Anthropic cache boundaries**

Ensure `ResearchService.generateWithCaching` and provider adapters continue to pass cache controls only on planned cacheable blocks. Do not cache `workingFrame`, `artifactState`, `interactionMemory`, `retrieval`, `rawHistory`, or `currentTurn`.

- [ ] **Step 5: Run cache planner tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CommandAPromptCachePlannerTests
```

Expected: PASS.

## Task 11: Add Cost, Cache, and Continuity Telemetry

**Files:**
- Create: `Agent/Telemetry/CommandAITelemetry.swift`
- Modify: `Cosmo/ResearchService.swift`
- Modify: `Agent/Core/LLMProviderAdapter.swift`
- Modify: `UI/CosmoWindow/CosmoWindowViewModel.swift`
- Modify: `UI/FocusMode/CosmoAI/CosmoAIFocusModeViewModel.swift`
- Create: `Tests/CosmoOSTests/CommandAITelemetryTests.swift`

- [ ] **Step 1: Add failing telemetry tests**

Create `Tests/CosmoOSTests/CommandAITelemetryTests.swift`:

```swift
import XCTest
@testable import CosmoOS

final class CommandAITelemetryTests: XCTestCase {
    func testTelemetryRecordsCacheAndCompactionSeparately() {
        var telemetry = CommandAITelemetry(conversationID: "conversation-1")
        telemetry.recordUsage(promptTokens: 20_000, completionTokens: 500, cachedTokens: 12_000, modelID: "google/gemini-3-flash-preview")
        telemetry.recordCompaction(droppedMessages: 0, reason: "none")

        XCTAssertEqual(telemetry.lastUsage?.cachedTokens, 12_000)
        XCTAssertEqual(telemetry.compactionEvents.first?.droppedMessages, 0)
        XCTAssertEqual(telemetry.cacheHitRate, 0.6, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Implement telemetry model**

Create `Agent/Telemetry/CommandAITelemetry.swift`:

```swift
import Foundation

struct CommandAIUsageEvent: Codable, Equatable, Sendable {
    var promptTokens: Int
    var completionTokens: Int
    var cachedTokens: Int
    var modelID: String
    var createdAt: Date = Date()
}

struct CommandAICompactionEvent: Codable, Equatable, Sendable {
    var droppedMessages: Int
    var reason: String
    var createdAt: Date = Date()
}

struct CommandAITelemetry: Codable, Equatable, Sendable {
    var conversationID: String
    var usageEvents: [CommandAIUsageEvent] = []
    var compactionEvents: [CommandAICompactionEvent] = []
    var continuityWarnings: [String] = []

    var lastUsage: CommandAIUsageEvent? { usageEvents.last }

    var cacheHitRate: Double {
        guard let usage = lastUsage, usage.promptTokens > 0 else { return 0 }
        return Double(usage.cachedTokens) / Double(usage.promptTokens)
    }

    mutating func recordUsage(promptTokens: Int, completionTokens: Int, cachedTokens: Int, modelID: String) {
        usageEvents.append(CommandAIUsageEvent(promptTokens: promptTokens, completionTokens: completionTokens, cachedTokens: cachedTokens, modelID: modelID))
    }

    mutating func recordCompaction(droppedMessages: Int, reason: String) {
        compactionEvents.append(CommandAICompactionEvent(droppedMessages: droppedMessages, reason: reason))
    }

    mutating func warnContinuity(_ message: String) {
        continuityWarnings.append(message)
    }
}
```

- [ ] **Step 3: Capture usage from provider responses**

In `ResearchService.logUsage` and provider adapter usage parsing, publish `CommandAIUsageEvent` with prompt tokens, completion tokens, cached tokens, and actual model ID. Keep this local and private; do not send it externally.

- [ ] **Step 4: Surface telemetry in Command A diagnostics**

Add a compact diagnostics row in Command A:

```text
Gemini 3 Flash · 22K / 1M context · 60% cache hit · no compaction
```

If compaction ever occurs, show:

```text
Context compacted after reaching Gemini 3 Flash window: N old messages dropped
```

- [ ] **Step 5: Run telemetry tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CommandAITelemetryTests
```

Expected: PASS.

## Task 12: Add Continuity Regression Evals

**Files:**
- Create: `Tests/CosmoOSTests/CommandAContinuityEvalTests.swift`
- Modify: `Tests/CosmoOSTests/CommandAContinuityContextTests.swift`

- [ ] **Step 1: Add locked-slide continuity eval**

Create `Tests/CosmoOSTests/CommandAContinuityEvalTests.swift`:

```swift
import XCTest
@testable import CosmoOS

final class CommandAContinuityEvalTests: XCTestCase {
    func testLockedApprovedSlidesRemainVisibleInPromptPlan() {
        var frame = CommandAWorkingFrame(conversationID: "conversation-1")
        frame.currentObjective = "Brainstorm a carousel"
        frame.currentSection = "slides 4-6"
        frame.lockDecision("Slides 1-3 are approved.")

        var artifact = CommandAArtifactState(id: "artifact-1", kind: .carousel, title: "Forecasting post")
        artifact.upsertSection(number: 1, title: "Hook", body: "Approved hook", status: .approved)
        artifact.upsertSection(number: 2, title: "Setup", body: "Approved setup", status: .approved)
        artifact.upsertSection(number: 3, title: "Tension", body: "Approved tension", status: .approved)
        artifact.upsertSection(number: 4, title: "Next", body: "Draft next section", status: .drafting)

        let prompt = [frame.promptBlock, artifact.promptBlock].joined(separator: "\n\n")

        XCTAssertTrue(prompt.contains("Slides 1-3 are approved."))
        XCTAssertTrue(prompt.contains("Section 1 [approved, locked]"))
        XCTAssertTrue(prompt.contains("Section 4 [drafting]"))
    }
}
```

- [ ] **Step 2: Add no-early-compaction eval**

Append:

```swift
func testNoEarlyCompactionAcrossLongBrainstormUnderGeminiWindow() {
    var messages: [AgentMessage] = []
    for index in 1...120 {
        messages.append(.user("Brainstorm turn \(index): decision \(index) must stay visible."))
        messages.append(.assistant("Decision \(index) acknowledged without rewriting prior approved material."))
    }

    let window = CosmoAgentService.buildContextWindowForTests(
        messages,
        modelTier: .geminiFlashLatest,
        reservedOutputTokens: 8_192,
        reservedSystemTokens: 20_000
    )

    XCTAssertEqual(window.count, messages.count)
    XCTAssertTrue(window.first?.content.contains("Brainstorm turn 1") == true)
}
```

- [ ] **Step 3: Add rejected-direction eval**

Append:

```swift
func testRejectedDirectionsStayInInteractionMemory() {
    var interaction = CommandAInteractionMemory(conversationID: "conversation-1")
    interaction.reject("Do not reinvent slides 1-3.")
    interaction.accept("Continue with the second half only.")

    let prompt = interaction.promptBlock

    XCTAssertTrue(prompt.contains("REJECTED: Do not reinvent slides 1-3."))
    XCTAssertTrue(prompt.contains("ACCEPTED: Continue with the second half only."))
}
```

- [ ] **Step 4: Run continuity evals**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CommandAContinuityEvalTests
```

Expected: PASS.

## Task 13: Final Integrated Verification

**Files:**
- Modify as needed based on failures from earlier tasks.

- [ ] **Step 1: Run all Command A routing, memory, cache, telemetry, and eval tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test \
  -only-testing:CosmoOSTests/CosmoWindowRoutingTests \
  -only-testing:CosmoOSTests/CommandAContinuityContextTests \
  -only-testing:CosmoOSTests/CommandAMemoryArchitectureTests \
  -only-testing:CosmoOSTests/CommandAPromptCachePlannerTests \
  -only-testing:CosmoOSTests/CommandAITelemetryTests \
  -only-testing:CosmoOSTests/CommandAContinuityEvalTests
```

Expected: PASS.

- [ ] **Step 2: Manually verify a real Command A brainstorming session**

Use this script in the app:

```text
I want to brainstorm an Instagram carousel about forecasting demand.
Slides 1-3 direction: hook with seasonal demand, setup with inventory risk, tension with last-minute buying.
I like that. Lock slides 1-3.
Now let's brainstorm the second half.
Maybe slide 4 should talk about ordering before panic buying starts.
Show me what that line would look like.
```

Expected:
- The diagnostics row stays on Gemini 3 Flash.
- The model does not switch in OpenRouter logs unless the user manually changed the model.
- The response only develops slide 4 or the second half.
- Slides 1-3 remain visible in artifact state as approved/locked.
- No compaction event is shown unless the prompt reaches the Gemini context limit.
- Prompt cache hit rate improves after repeated turns with stable identity/tool/profile blocks.

- [ ] **Step 3: Commit the full continuity upgrade**

```bash
git add Agent/Models/AgentTypes.swift Agent/Core/CosmoAgentService.swift Agent/Core/AgentContextAssembler.swift Agent/Core/LLMProviderAdapter.swift Agent/Memory/ConversationMemoryService.swift Agent/Context Agent/Telemetry UI/CosmoWindow UI/FocusMode/CosmoAI Tests/CosmoOSTests
git commit -m "feat: upgrade Command A continuity and memory"
```

## Self-Review Notes

- This plan explicitly covers the two user requirements: fixed Gemini 3 Flash default and no compaction before model-window exhaustion.
- It treats silent failover as a model switch, so failover becomes same-model retry only unless the user explicitly changes the model.
- It preserves summaries as additive metadata, but removes summary replacement triggered by arbitrary message counts.
- It updates both the global Command A window and the Cosmo AI focus panel, because both currently route through `CosmoAgentService` but have separate UI state.
- It includes the broader architecture previously discussed: working frame, structured artifact state, interaction memory, archival recall, explicit context budgeting, prompt cache planning, cost/cache telemetry, and continuity evals.
- The memory architecture is deliberately additive until the model window is full, so it improves continuity without reintroducing premature compaction.
