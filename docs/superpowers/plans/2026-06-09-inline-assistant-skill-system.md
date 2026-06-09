# Inline Assistant Skill System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the first working slice of customizable, slash-selectable, model-aware inline assistant skills.

**Architecture:** Keep the existing inline assistant runtime, but add a skill definition/registry layer above it. Explicit slash-selected skills override heuristic routing, and skill-preferred model tiers feed into the existing `tierOverride` plumbing. The composer gets a slash parser/menu path parallel to the current `@` context menu.

**Tech Stack:** Swift, SwiftUI/AppKit bridge, XCTest, existing Cosmo inline assistant + agent service.

---

## File Structure

- Modify `UI/InlineAssistant/CosmoInlineAssistantModels.swift`
  - Add skill pane policy, skill definition, skill persistence, skill registry, slash parser, and selected-skill routing support.
  - Add preferred model metadata to the inline skill plan.
- Modify `UI/InlineAssistant/CosmoInlineAssistantStore.swift`
  - Track selected slash skill per submission and persisted session.
  - Parse slash skill commands during submit.
- Modify `UI/InlineAssistant/CosmoInlineAssistantAgentBridge.swift`
  - Pass the selected skill ID into request preparation.
- Modify `UI/CosmoWindow/CosmoWindowViewModel.swift`
  - Accept selected skill ID and use skill-preferred model tier before the default sensor fallback.
- Modify `UI/InlineAssistant/CosmoInlineAssistantBar.swift`
  - Add slash menu state, parser sync, and selection behavior alongside the existing `@` context menu.
- Modify `Tests/CosmoOSTests/CosmoInlineAssistantRoutingTests.swift`
  - Cover registry, custom persistence, slash parsing, explicit skill override, and model policy.

## Task 1: Skill Definition, Registry, Parser, and Model Policy

- [x] **Step 1: Write failing tests**

Add tests to `Tests/CosmoOSTests/CosmoInlineAssistantRoutingTests.swift`:

```swift
func testInlineSkillRegistryIncludesBuiltInsAndCustomSkills() {
    let custom = CosmoInlineSkillDefinition.custom(
        name: "Ben Carousel Expansion",
        icon: "rectangle.stack.badge.plus",
        summary: "Expands a draft using Ben's best-performing carousel structure.",
        triggerPhrases: ["ben carousel", "best performing breakdown"],
        route: .action,
        preferredModelTier: .strategist,
        requiredContext: [.activeSurface, .clientProfile, .swipes, .bestPerformingContent],
        toolBundles: [.workspaceEditing, .clientFactLookup, .swipes, .strategy, .writing],
        instructions: ["Stage added slides as reviewed diffs."],
        outputContract: "reviewed_diff",
        tokenBudget: 2200,
        requiresReviewedDiff: true,
        panePolicy: .neverForAction
    )
    let store = CosmoInlineSkillStore.inMemory(customSkills: [custom])
    let registry = CosmoInlineSkillRegistry(store: store)

    XCTAssertNotNil(registry.skill(id: "factFill"))
    XCTAssertEqual(registry.skill(id: custom.id)?.name, "Ben Carousel Expansion")
}

func testSlashSkillParserExtractsSkillCommandAndRemainingPrompt() {
    let registry = CosmoInlineSkillRegistry(store: .inMemory())
    let parsed = CosmoInlineSlashSkillParser.extractCommand(
        from: "/Fact Fill replace the placeholders in slide 1",
        registry: registry
    )

    XCTAssertEqual(parsed?.skillID, "factFill")
    XCTAssertEqual(parsed?.remainingPrompt, "replace the placeholders in slide 1")
}

func testSelectedSlashSkillOverridesHeuristicRouting() {
    let plan = CosmoInlineAssistantSkillRuntime.plan(
        for: "replace the placeholders in slide 1",
        surfaceKind: .text,
        selectedSkillID: "voiceVariations",
        registry: CosmoInlineSkillRegistry(store: .inMemory())
    )

    XCTAssertEqual(plan.primarySkill.name, "Voice Variations")
    XCTAssertEqual(plan.route, .answer)
}

func testSkillPreferredModelTierIsExposedOnPlan() {
    let plan = CosmoInlineAssistantSkillRuntime.plan(
        for: "give me feedback on this",
        surfaceKind: .text,
        selectedSkillID: "contentReview",
        registry: CosmoInlineSkillRegistry(store: .inMemory())
    )

    XCTAssertEqual(plan.preferredModelTier, .strategist)
}
```

Run:

```bash
xcodebuild test -quiet -project CosmoOS.xcodeproj -scheme CosmoOS -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:CosmoOSTests/CosmoInlineAssistantRoutingTests/testInlineSkillRegistryIncludesBuiltInsAndCustomSkills -only-testing:CosmoOSTests/CosmoInlineAssistantRoutingTests/testSlashSkillParserExtractsSkillCommandAndRemainingPrompt -only-testing:CosmoOSTests/CosmoInlineAssistantRoutingTests/testSelectedSlashSkillOverridesHeuristicRouting -only-testing:CosmoOSTests/CosmoInlineAssistantRoutingTests/testSkillPreferredModelTierIsExposedOnPlan
```

Expected: FAIL because the new types and APIs do not exist yet.

- [x] **Step 2: Implement the minimal model layer**

In `CosmoInlineAssistantModels.swift`:

- Add `CosmoInlineSkillPanePolicy`.
- Add optional `preferredModelTier`, `panePolicy`, `icon`, `summary`, and `triggerPhrases` to `CosmoInlineAssistantSkill`.
- Add `CosmoInlineSkillDefinition`.
- Add `CosmoInlineSkillStore` with `inMemory` and `userDefaults` storage.
- Add `CosmoInlineSkillRegistry`.
- Add `CosmoInlineSlashSkillParser`.
- Extend `CosmoInlineAssistantSkillPlan` with `definitionID`, `preferredModelTier`, and `panePolicy`.
- Extend `CosmoInlineAssistantSkillRuntime.plan` with optional `selectedSkillID` and `registry`.

- [x] **Step 3: Run tests and fix compile errors**

Run the focused test command from Step 1. Expected: PASS.

## Task 2: Submission and Model Routing Integration

- [x] **Step 1: Write failing tests**

Add tests:

```swift
func testStoreSubmitUsesSlashSelectedSkillRoute() async {
    let bridge = CosmoInlineAssistantAgentBridge { prompt, route, store in
        XCTAssertEqual(prompt, "replace the placeholders in slide 1")
        XCTAssertEqual(route, .answer)
        XCTAssertEqual(store.activeSubmissionSkillID, "voiceVariations")
    }
    let store = CosmoInlineAssistantStore(agentBridge: bridge)
    store.composerText = "/Voice Variations replace the placeholders in slide 1"

    await store.submit()
}

func testPreparedInlineRequestUsesSkillModelBeforeSensorDefault() async {
    let viewModel = CosmoWindowViewModel.shared
    let request = await viewModel.prepareInlineAssistantAgentRequest(
        prompt: "give me feedback on this",
        route: .answer,
        snapshot: nil,
        inlineContextAtoms: [],
        selectedSkillID: "contentReview"
    )

    XCTAssertEqual(request.tierOverride, .strategist)
}
```

Expected: FAIL until the store and view model accept selected skill IDs.

- [x] **Step 2: Implement selected skill submission**

In `CosmoInlineAssistantStore.swift`:

- Add `selectedSkillID`.
- Add `activeSubmissionSkillID`.
- Persist `selectedSkillID` in `CosmoInlineAssistantPersistedSession`.
- During `submit`, parse slash skill command first.
- Use the parsed prompt for agent execution.
- Use selected skill routing for route classification.
- Clear one-shot selected skill after submit unless the token remains in composer/session.

In `CosmoInlineAssistantAgentBridge.swift`:

- Pass `store.activeSubmissionSkillID` to `prepareInlineAssistantAgentRequest`.

In `CosmoWindowViewModel.swift`:

- Add `selectedSkillID` parameter to `prepareInlineAssistantAgentRequest`.
- Pass it to `CosmoInlineAssistantSkillRuntime.plan`.
- Choose tier as `modelOverride ?? skillPlan.preferredModelTier ?? activeProfile?.preferredModelTier ?? .sensor`.

- [x] **Step 3: Run focused tests**

Run the new two tests. Expected: PASS.

## Task 3: Slash Menu UI

- [x] **Step 1: Write parser/presentation tests**

Add tests for active slash parsing:

```swift
func testActiveSlashSkillMentionOnlyTriggersAtCommandBoundary() {
    XCTAssertEqual(
        CosmoInlineSlashSkillParser.activeCommand(in: "/voi", selectedRange: NSRange(location: 4, length: 0))?.query,
        "voi"
    )
    XCTAssertNil(
        CosmoInlineSlashSkillParser.activeCommand(in: "http://example.com", selectedRange: NSRange(location: 7, length: 0))
    )
}
```

- [x] **Step 2: Implement slash menu in `CosmoInlineAssistantBar`**

Add:

- `isSkillMenuVisible`
- `skillSearchText`
- slash parser sync in text changes
- `CosmoInlineAssistantSkillMenu`
- rows for built-in/custom skills and `/clear`
- `Create Skill...` row that opens the pane with a builder prompt seed

The first slice may render selected slash skills as plain slash tokens rather than rich pills. The model/store layer must still track `selectedSkillID`.

- [x] **Step 3: Run inline routing tests**

Run:

```bash
xcodebuild test -quiet -project CosmoOS.xcodeproj -scheme CosmoOS -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:CosmoOSTests/CosmoInlineAssistantRoutingTests
```

Expected: PASS.

## Task 4: Build Verification

- [x] **Step 1: Build app**

Run:

```bash
xcodebuild build -quiet -project CosmoOS.xcodeproj -scheme CosmoOS -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Expected: exit 0.

- [x] **Step 2: Review changed files**

Run:

```bash
git diff -- UI/InlineAssistant/CosmoInlineAssistantModels.swift UI/InlineAssistant/CosmoInlineAssistantStore.swift UI/InlineAssistant/CosmoInlineAssistantAgentBridge.swift UI/InlineAssistant/CosmoInlineAssistantBar.swift UI/CosmoWindow/CosmoWindowViewModel.swift Tests/CosmoOSTests/CosmoInlineAssistantRoutingTests.swift
```

Expected: changes are scoped to the skill registry, slash selection, model policy, and tests.
