# Inquiry Source Radar and Thinking Dock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first production slice of branch-aware source recommendations and one-route inquiry capture in the Inquiry Workspace.

**Architecture:** Extend the existing inquiry session structured JSON instead of adding a parallel store. Keep ranking/provider logic local and deterministic for V1, then layer no-key academic providers into the same normalized candidate model. Surface the results in the existing source pane and replace duplicate input affordances with a single bottom dock.

**Tech Stack:** Swift 5, SwiftUI, `@Observable`, existing `AtomRepository` / `InquiryRepository`, URLSession for OpenAlex/Crossref, XCTest.

---

## File Map

- Modify `Data/Models/InquiryWorkspaceModels.swift`
  Adds `InquirySourceCandidate`, `InquiryRecommendationBatch`, provider status, evidence role, import status, and `InquiryRouteReceipt` persistence.
- Modify `AI/InquiryPlacementEngine.swift`
  Adds `InquiryDockPrefixParser`, `InquirySourceRecommendationEngine`, local source matching, OpenAlex/Crossref fetchers, and deterministic ranking helpers. This avoids Xcode project churn in this first slice.
- Modify `UI/FocusMode/Inquiry/InquiryWorkspaceViewModel.swift`
  Adds active-batch selection, recommendation refresh/import/queue/dismiss actions, dock submission, route receipts, and `/sources` handling.
- Modify `UI/FocusMode/Inquiry/Panes/InquirySourcePane.swift`
  Turns the empty center state into Source Radar, with loading/provider state, source cards, and import/queue/dismiss actions.
- Modify `UI/FocusMode/Inquiry/Panes/InquiryCopilotPane.swift`
  Removes the second primary text input from the right pane and shows compact route receipts instead.
- Modify `UI/FocusMode/Inquiry/InquiryWorkspaceView.swift`
  Adds the bottom Thinking Dock across research/read/write/map layouts.
- Modify `Tests/CosmoOSTests/InquiryPlacementEngineTests.swift`
  Adds parser/ranker/batch decoding coverage without adding a new project file.

## Task 1: Persistent Source Recommendation State

**Files:**
- Modify: `Data/Models/InquiryWorkspaceModels.swift`
- Test: `Tests/CosmoOSTests/InquiryPlacementEngineTests.swift`

- [ ] **Step 1: Add a decoding test before model changes**

Append this test to `InquiryPlacementEngineTests`:

```swift
func testInquirySessionStructuredDecodesMissingRecommendationFields() throws {
    let json = #"{"researchTree":{"nodes":{},"edges":[],"rootNodeId":"root","rootQuestionNodeIds":[]}}"#.data(using: .utf8)!
    let structured = try JSONDecoder().decode(InquirySessionStructured.self, from: json)

    XCTAssertTrue(structured.recommendationBatches.isEmpty)
    XCTAssertTrue(structured.routeReceipts.isEmpty)
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -only-testing:CosmoOSTests/InquiryPlacementEngineTests/testInquirySessionStructuredDecodesMissingRecommendationFields test`

Expected: compile failure because `recommendationBatches` and `routeReceipts` do not exist yet.

- [ ] **Step 3: Add recommendation models and fields**

Add the model types near `InquiryOperationalTask`, then add these fields to `InquirySessionStructured`:

```swift
var recommendationBatches: [InquiryRecommendationBatch]
var routeReceipts: [InquiryRouteReceipt]
```

Decode them with:

```swift
recommendationBatches = try container.decodeIfPresent([InquiryRecommendationBatch].self, forKey: .recommendationBatches) ?? []
routeReceipts = try container.decodeIfPresent([InquiryRouteReceipt].self, forKey: .routeReceipts) ?? []
```

- [ ] **Step 4: Re-run the focused test**

Run the same `xcodebuild ... test` command.

Expected: the new test passes or the command reaches the next unrelated project issue.

## Task 2: Prefix Parser and Recommendation Engine

**Files:**
- Modify: `AI/InquiryPlacementEngine.swift`
- Test: `Tests/CosmoOSTests/InquiryPlacementEngineTests.swift`

- [ ] **Step 1: Add tests for explicit dock prefixes**

Add tests for:

```swift
XCTAssertEqual(InquiryDockPrefixParser.parse("claim: breath holds raise CO2").intent, .claim)
XCTAssertEqual(InquiryDockPrefixParser.parse("counter: this paper contradicts it").intent, .counterevidence)
XCTAssertEqual(InquiryDockPrefixParser.parse("/sources").intent, .refreshSources)
XCTAssertEqual(InquiryDockPrefixParser.parse("https://example.com/a").intent, .openSource)
```

- [ ] **Step 2: Add deterministic parser implementation**

Implement `InquiryDockPrefixParser` with explicit string-prefix matching for the approved prefixes: `q:`, `root:`, `branch:`, `note:`, `claim:`, `maybe:`, `evidence:`, `counter:`, `source:`, `term:`, `practice:`, `output:`, `/challenge`, `/summarize`, and `/sources`.

- [ ] **Step 3: Add ranking test**

Construct three candidates and assert a title/token match with `.review` outranks an unrelated weak candidate for the same branch query.

- [ ] **Step 4: Add `InquirySourceRecommendationEngine`**

Implement:

```swift
@MainActor
final class InquirySourceRecommendationEngine {
    static let shared = InquirySourceRecommendationEngine()

    func recommend(
        profile: InquiryBranchResearchProfile,
        existingSourceRefs: [InquirySourceRef],
        localSources: [Atom]
    ) async -> InquiryRecommendationBatch
}
```

The engine returns local matches immediately, attempts OpenAlex and Crossref with no API key, merges by URL/title, ranks deterministically, and caps the batch to twelve candidates.

## Task 3: View Model Wiring

**Files:**
- Modify: `UI/FocusMode/Inquiry/InquiryWorkspaceViewModel.swift`

- [ ] **Step 1: Add batch accessors**

Add:

```swift
var activeRecommendationBatch: InquiryRecommendationBatch?
var activeSourceCandidates: [InquirySourceCandidate]
var isRefreshingSources: Bool
```

- [ ] **Step 2: Refresh recommendations for the active branch**

Implement `refreshSourceRecommendations()` using `activeQuestionTitle`, ancestors, claims/evidence, existing `sourceRefs`, and `AtomRepository.shared.fetchAll(type: .research)`.

- [ ] **Step 3: Import, queue, and dismiss candidates**

Implement `importSourceCandidate(_:)`, `queueSourceCandidate(_:)`, and `dismissSourceCandidate(_:)`. Import uses `InquiryRepository.shared.createOrFindURLSource` and then the existing `openTab` / `upsertSourceRef` path.

- [ ] **Step 4: Submit Thinking Dock text**

Implement `submitDockText(_:)` so URLs open as sources, `/sources` refreshes Source Radar, explicit extract prefixes save the correct `ExtractKind`, branch/question prefixes use existing branch creation/routing card flows, and ordinary text saves a note then routes it.

## Task 4: Source Radar UI

**Files:**
- Modify: `UI/FocusMode/Inquiry/Panes/InquirySourcePane.swift`

- [ ] **Step 1: Add radar surface**

Replace the empty state with a Source Radar view that shows:

```text
SOURCE RADAR
Top sources for active branch
provider chips: Local / OpenAlex / Crossref
candidate cards with score, evidence role, provider, year, reason
```

- [ ] **Step 2: Add card actions**

Each candidate card has icon buttons for Open/Import, Queue, and Dismiss. These call the view model methods from Task 3.

- [ ] **Step 3: Keep the URL row**

The existing URL row stays available as a manual override; Source Radar is the default when no source tab is open.

## Task 5: One Thinking Dock

**Files:**
- Modify: `UI/FocusMode/Inquiry/InquiryWorkspaceView.swift`
- Modify: `UI/FocusMode/Inquiry/Panes/InquiryCopilotPane.swift`

- [ ] **Step 1: Add bottom dock**

Add `InquiryThinkingDock` below the pane row for all non-review modes. Bind it to a local `@State private var draft`, show route chips, and submit via `await viewModel.submitDockText(draft)`.

- [ ] **Step 2: Remove duplicate primary copilot input**

In `InquiryCopilotPane`, remove the bottom ask-input row from the main layout and show route receipts in its place so the workspace has one obvious input.

## Task 6: Verification

**Files:**
- Test: `Tests/CosmoOSTests/InquiryPlacementEngineTests.swift`

- [ ] **Step 1: Run focused tests**

Run: `xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -only-testing:CosmoOSTests/InquiryPlacementEngineTests test`

- [ ] **Step 2: Run app build**

Run: `xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug build`

- [ ] **Step 3: Manual UI check**

Launch the app, open an inquiry session, verify Source Radar appears before a source is opened, `/sources` refreshes, a candidate imports into session sources, and the bottom dock saves a `claim:` and a normal note under the active branch.

## Self-Review

Spec coverage: the plan covers branch-specific recommendation batches, local/external source candidates, route receipts, explicit prefixes, one input surface, Source Radar UI, import/queue/dismiss actions, and build/test verification.

Placeholder scan: no task depends on undefined user input or a later unspecified implementation. The only allowed provider limitation is explicit: OpenAlex and Crossref are first no-key providers; YouTube/PubMed/arXiv remain next-layer integrations from the approved spec.

Type consistency: the plan uses `InquirySourceCandidate`, `InquiryRecommendationBatch`, `InquiryRouteReceipt`, `InquiryDockPrefixParser`, `InquiryBranchResearchProfile`, and `InquirySourceRecommendationEngine` consistently across model, engine, view model, UI, and tests.
