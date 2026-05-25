# Command-K Spotlight Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Command-K feel like Spotlight: no visible spinner lifecycle, no phase-driven preview flash, stable row identity, and continuous result refinement as typing and background enrichment complete.

**Architecture:** Treat search as a continuously refined snapshot, not a visible loading state machine. Keep fast local results on screen, let slower enrichment publish only when result content actually changes, and move completion state out of the main observed SwiftUI tree so `.searching -> .complete` cannot invalidate the rail or preview. Show empty state only as a real content result, not as the absence of a spinner.

**Tech Stack:** SwiftUI macOS, Combine, XCTest, existing Command-K search pipeline and view model.

---

## Research Notes

Apple's search guidance emphasizes continuous refinement while typing. The visible UI should feel responsive because results update as text becomes more specific, not because a loading control starts and stops. Apple Support describes Spotlight as direct entry plus immediate actions: open Spotlight, start typing, press Return to open or run the selected action. Sources:

- Apple HIG Searching: `https://developer.apple.com/design/human-interface-guidelines/searching`
- Apple HIG Search Fields: `https://developer.apple.com/design/human-interface-guidelines/search-fields`
- Apple Core Spotlight search interface: `https://developer.apple.com/documentation/corespotlight/building-a-search-interface-for-your-app`
- Apple Support Spotlight on Mac: `https://support.apple.com/en-euro/guide/mac-pro/apd10f8d1038/mac`

Local root cause:

- `CommandKViewModel.currentPhase` is `@Published`, so every phase transition emits `objectWillChange`.
- `CortexSearchBar` and the older `CommandKView` search bar add/remove `ProgressView` when `currentPhase == .searching`.
- Both search bars pulse the magnifying glass with `.symbolEffect(.pulse, isActive: viewModel.currentPhase == .searching)`.
- `CortexSearchResultsView` conditionally inserts/removes a loading row from `currentPhase`.
- `CortexResultRail` changes its hint text from `"Searching..."` to `"No matches yet."` from `currentPhase`.
- The visible flash happens when typing stops because the phase flips from `.searching` to `.instant` or `.complete`, even if the first row and preview subject are unchanged.

## File Structure

- Modify `UI/CommandK/CommandKViewModel.swift`
  - Make `currentPhase` non-published.
  - Add a small published `CommandKSearchFeedback` value that only changes when user-visible feedback should change.
  - Keep result snapshots and selected identity stable.

- Modify `UI/CommandK/CortexSearchBar.swift`
  - Remove spinner and phase-driven symbol pulse.
  - Preserve fixed trailing layout so controls do not shift.

- Modify `UI/CommandK/CommandKView.swift`
  - Remove legacy search bar spinner and phase-driven symbol pulse.
  - Keep clear button, command key badge, voice button behavior unchanged.

- Modify `UI/CommandK/CortexSearchResultsView.swift`
  - Remove loading row.
  - Show empty state from `viewModel.searchFeedback == .empty(query)` only.

- Modify `UI/CommandK/CortexResultRail.swift`
  - Remove phase-driven `"Searching..."` hint.
  - Show empty state only when `searchFeedback` says the current query is complete with no visible matches.

- Modify `UI/CommandK/UnifiedSearchResultsView.swift`
  - Remove `currentPhase` dependency from empty-state logic.
  - Use `searchFeedback` instead.

- Modify `Tests/CosmoOSTests/CommandKSearchPipelineTests.swift`
  - Add regression tests proving phase completion does not emit view invalidation and no loading chrome is exposed.

## Task 1: Make Search Phase Non-Visual

**Files:**
- Modify: `UI/CommandK/CommandKViewModel.swift`
- Test: `Tests/CosmoOSTests/CommandKSearchPipelineTests.swift`

- [ ] **Step 1: Write the failing phase invalidation test**

Add this test near the existing scoped-idea selection stability tests:

```swift
@MainActor
func testSearchPhaseChangesDoNotInvalidateCommandKSurface() async {
    let viewModel = CommandKViewModel(
        userCommandStore: CommandKUserCommandStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json"),
            seedBuiltIns: false
        )
    )
    defer { viewModel.setSurfaceActive(false) }

    var invalidationCount = 0
    let cancellable = viewModel.objectWillChange
        .sink { invalidationCount += 1 }
    defer { cancellable.cancel() }

    viewModel.testingSetSearchPhase(.searching)
    viewModel.testingSetSearchPhase(.instant)
    viewModel.testingSetSearchPhase(.complete)

    XCTAssertEqual(invalidationCount, 0)
    XCTAssertEqual(viewModel.currentPhase, .complete)
}
```

- [ ] **Step 2: Run the failing test**

Run:

```bash
xcodebuild test -scheme CosmoOS -destination 'platform=macOS' -only-testing:CosmoOSTests/CommandKSearchPipelineTests/testSearchPhaseChangesDoNotInvalidateCommandKSurface CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected before implementation: the test cannot compile because `testingSetSearchPhase(_:)` does not exist.

- [ ] **Step 3: Implement non-published phase storage**

In `CommandKViewModel`, change:

```swift
@Published public private(set) var currentPhase: SearchPhase = .idle
```

to:

```swift
public private(set) var currentPhase: SearchPhase = .idle
```

Add this test hook inside `CommandKViewModel` near `setCurrentPhase(_:)`:

```swift
#if DEBUG
func testingSetSearchPhase(_ phase: SearchPhase) {
    setCurrentPhase(phase)
}
#endif
```

Keep `setCurrentPhase(_:)` as the only mutator:

```swift
private func setCurrentPhase(_ phase: SearchPhase) {
    if currentPhase != phase {
        currentPhase = phase
    }
}
```

- [ ] **Step 4: Run the test again**

Run:

```bash
xcodebuild test -scheme CosmoOS -destination 'platform=macOS' -only-testing:CosmoOSTests/CommandKSearchPipelineTests/testSearchPhaseChangesDoNotInvalidateCommandKSurface CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: PASS.

## Task 2: Add Explicit Search Feedback State

**Files:**
- Modify: `UI/CommandK/CommandKViewModel.swift`
- Test: `Tests/CosmoOSTests/CommandKSearchPipelineTests.swift`

- [ ] **Step 1: Write feedback tests**

Add these tests near the phase invalidation test:

```swift
@MainActor
func testVisibleResultsClearSearchFeedbackImmediately() async {
    let viewModel = CommandKViewModel(
        userCommandStore: CommandKUserCommandStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json"),
            seedBuiltIns: false
        )
    )
    defer { viewModel.setSurfaceActive(false) }

    viewModel.testingSetSearchFeedback(.empty(query: "missing"))
    await viewModel.performSearch(query: "idea Euan: stable draft")

    XCTAssertEqual(viewModel.searchFeedback, .none)
    XCTAssertEqual(viewModel.primaryAction?.kind, .createIdea)
}

@MainActor
func testSearchFeedbackPublishesEmptyOnlyForCurrentEmptyQuery() async {
    let viewModel = CommandKViewModel(
        userCommandStore: CommandKUserCommandStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json"),
            seedBuiltIns: false
        )
    )
    defer { viewModel.setSurfaceActive(false) }

    viewModel.query = "unlikely-\(UUID().uuidString)"
    viewModel.testingRefreshSearchFeedback(for: viewModel.query)

    XCTAssertEqual(viewModel.searchFeedback, .empty(query: viewModel.query))

    viewModel.query = "idea Euan: new draft"
    viewModel.testingRefreshSearchFeedback(for: viewModel.query)

    XCTAssertEqual(viewModel.searchFeedback, .none)
}
```

- [ ] **Step 2: Run the failing tests**

Run:

```bash
xcodebuild test -scheme CosmoOS -destination 'platform=macOS' -only-testing:CosmoOSTests/CommandKSearchPipelineTests/testVisibleResultsClearSearchFeedbackImmediately -only-testing:CosmoOSTests/CommandKSearchPipelineTests/testSearchFeedbackPublishesEmptyOnlyForCurrentEmptyQuery CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected before implementation: compile failure because `CommandKSearchFeedback`, `searchFeedback`, and test hooks do not exist.

- [ ] **Step 3: Add feedback model**

In `CommandKViewModel.swift`, near `SearchPhase`, add:

```swift
public enum CommandKSearchFeedback: Equatable, Sendable {
    case none
    case empty(query: String)
}
```

Inside `CommandKViewModel`, add:

```swift
@Published public private(set) var searchFeedback: CommandKSearchFeedback = .none
```

Add helpers near the other setter helpers:

```swift
private func setSearchFeedback(_ feedback: CommandKSearchFeedback) {
    if searchFeedback != feedback {
        searchFeedback = feedback
    }
}

private func refreshSearchFeedback(for query: String) {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        setSearchFeedback(.none)
        return
    }

    let hasVisibleMatches =
        primaryAction != nil ||
        !userCommandRows.isEmpty ||
        unifiedGroupedResults.contains { !$0.results.isEmpty } ||
        !unifiedFlatResults.isEmpty

    setSearchFeedback(hasVisibleMatches ? .none : .empty(query: trimmed))
}

#if DEBUG
func testingSetSearchFeedback(_ feedback: CommandKSearchFeedback) {
    setSearchFeedback(feedback)
}

func testingRefreshSearchFeedback(for query: String) {
    refreshSearchFeedback(for: query)
}
#endif
```

- [ ] **Step 4: Wire feedback clearing and empty publishing**

In `performSearch(query:)`, immediately after parsing the action and before result work:

```swift
setSearchFeedback(.none)
```

After every call to `updateActiveSearchSelection()` that follows a result publication, add:

```swift
refreshSearchFeedback(for: queryForSearch)
```

In the empty-query branch, add:

```swift
setSearchFeedback(.none)
```

In `updateUnifiedSearch(...)`, after `updateActiveSearchSelection()`, add:

```swift
refreshSearchFeedback(for: query)
```

Do not call `refreshSearchFeedback` in the `preserveVisibleResultsWhenEmpty` early return branch, because that branch intentionally keeps existing visible results.

- [ ] **Step 5: Run feedback tests**

Run:

```bash
xcodebuild test -scheme CosmoOS -destination 'platform=macOS' -only-testing:CosmoOSTests/CommandKSearchPipelineTests/testVisibleResultsClearSearchFeedbackImmediately -only-testing:CosmoOSTests/CommandKSearchPipelineTests/testSearchFeedbackPublishesEmptyOnlyForCurrentEmptyQuery CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: PASS.

## Task 3: Remove Spinner-Driven Search Chrome

**Files:**
- Modify: `UI/CommandK/CortexSearchBar.swift`
- Modify: `UI/CommandK/CommandKView.swift`
- Test: `Tests/CosmoOSTests/CommandKSearchPipelineTests.swift`

- [ ] **Step 1: Add a pure policy test**

Add this small policy test:

```swift
func testCommandKSearchChromeDoesNotExposeLoadingIndicatorForTyping() {
    XCTAssertFalse(CommandKSearchChromePolicy.showsTypingProgressIndicator)
}
```

- [ ] **Step 2: Add policy type**

Create the policy in `CommandKViewModel.swift` near `CommandKSearchFeedback`:

```swift
enum CommandKSearchChromePolicy {
    static let showsTypingProgressIndicator = false
}
```

- [ ] **Step 3: Remove search icon pulse from `CortexSearchBar`**

Replace:

```swift
.symbolEffect(.pulse, isActive: viewModel.currentPhase == .searching)
```

with no symbol effect. The final search icon modifier chain should be:

```swift
Image(systemName: viewModel.isTaskCreationMode ? "plus.circle.fill" : "magnifyingglass")
    .font(DS.title2)
    .foregroundStyle(viewModel.isTaskCreationMode ? DS.accent : (isSearchFocused.wrappedValue ? DS.accent : DS.textSecondary))
    .frame(width: 22)
```

- [ ] **Step 4: Remove `CortexSearchBar` spinner**

Delete this block:

```swift
if viewModel.currentPhase == .searching {
    ProgressView()
        .scaleEffect(0.8)
        .tint(DS.textSecondary)
}
```

Keep the voice button and prefix badges unchanged.

- [ ] **Step 5: Remove legacy `CommandKView` search icon pulse and spinner**

In `CommandKView.swift`, remove both search icon `.symbolEffect(.pulse, isActive: viewModel.currentPhase == .searching)` calls and delete the loading spinner block:

```swift
if viewModel.currentPhase == .searching {
    ProgressView()
        .scaleEffect(0.7)
        .tint(DS.textSecondary)
}
```

- [ ] **Step 6: Run policy test**

Run:

```bash
xcodebuild test -scheme CosmoOS -destination 'platform=macOS' -only-testing:CosmoOSTests/CommandKSearchPipelineTests/testCommandKSearchChromeDoesNotExposeLoadingIndicatorForTyping CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: PASS.

## Task 4: Remove Phase-Driven Result Loading Rows

**Files:**
- Modify: `UI/CommandK/CortexSearchResultsView.swift`
- Modify: `UI/CommandK/CortexResultRail.swift`
- Modify: `UI/CommandK/UnifiedSearchResultsView.swift`
- Test: `Tests/CosmoOSTests/CommandKSearchPipelineTests.swift`

- [ ] **Step 1: Add feedback visibility tests**

Add:

```swift
func testSearchFeedbackEmptyMatchesOnlyCurrentQuery() {
    XCTAssertTrue(CommandKSearchFeedback.empty(query: "alpha").matches(query: " alpha "))
    XCTAssertFalse(CommandKSearchFeedback.empty(query: "alpha").matches(query: "beta"))
    XCTAssertFalse(CommandKSearchFeedback.none.matches(query: "alpha"))
}
```

- [ ] **Step 2: Add matcher helper**

In `CommandKSearchFeedback`, add:

```swift
func matches(query: String) -> Bool {
    guard case .empty(let expectedQuery) = self else { return false }
    return expectedQuery == query.trimmingCharacters(in: .whitespacesAndNewlines)
}
```

- [ ] **Step 3: Update `CortexSearchResultsView`**

Replace:

```swift
if viewModel.currentPhase == .searching {
    loadingState
} else if viewModel.primaryAction == nil,
          viewModel.unifiedGroupedResults.allSatisfy({ $0.results.isEmpty }) && viewModel.currentPhase == .complete {
    emptyState
}
```

with:

```swift
if viewModel.primaryAction == nil,
   viewModel.unifiedGroupedResults.allSatisfy({ $0.results.isEmpty }),
   viewModel.searchFeedback.matches(query: viewModel.query) {
    emptyState
}
```

Delete the unused `loadingState` view from this file.

- [ ] **Step 4: Update `CortexResultRail`**

Replace:

```swift
railHint(viewModel.currentPhase == .searching ? "Searching..." : "No matches yet.")
```

with:

```swift
if viewModel.searchFeedback.matches(query: viewModel.query) {
    railHint("No matches yet.")
}
```

If SwiftUI requires a view in the empty branch, use:

```swift
Color.clear.frame(height: 1)
```

- [ ] **Step 5: Update `UnifiedSearchResultsView`**

Replace:

```swift
if viewModel.unifiedFlatResults.isEmpty && viewModel.currentPhase != .searching {
```

with:

```swift
if viewModel.unifiedFlatResults.isEmpty && viewModel.searchFeedback.matches(query: viewModel.query) {
```

- [ ] **Step 6: Run feedback matcher test**

Run:

```bash
xcodebuild test -scheme CosmoOS -destination 'platform=macOS' -only-testing:CosmoOSTests/CommandKSearchPipelineTests/testSearchFeedbackEmptyMatchesOnlyCurrentQuery CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: PASS.

## Task 5: Verify Stable First Selection Through Completion

**Files:**
- Modify: `Tests/CosmoOSTests/CommandKSearchPipelineTests.swift`

- [ ] **Step 1: Add a regression for phase completion with same selection**

Add:

```swift
@MainActor
func testSearchCompletionKeepsFirstSelectionAndPreviewIdentityStable() async throws {
    let viewModel = CommandKViewModel(
        userCommandStore: CommandKUserCommandStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json"),
            seedBuiltIns: false
        )
    )
    defer { viewModel.setSurfaceActive(false) }

    await viewModel.performSearch(query: "idea Euan:")
    let selectedID = try XCTUnwrap(viewModel.selectedNodeId)
    let actionID = try XCTUnwrap(viewModel.primaryAction?.id)
    XCTAssertEqual(selectedID, actionID)

    var selectionEvents: [String?] = []
    let cancellable = viewModel.$selectedNodeId
        .dropFirst()
        .sink { selectionEvents.append($0) }
    defer { cancellable.cancel() }

    viewModel.testingSetSearchPhase(.searching)
    viewModel.testingSetSearchPhase(.complete)

    XCTAssertEqual(viewModel.selectedNodeId, selectedID)
    XCTAssertEqual(viewModel.primaryAction?.id, actionID)
    XCTAssertTrue(selectionEvents.isEmpty)
}
```

- [ ] **Step 2: Run the new test**

Run:

```bash
xcodebuild test -scheme CosmoOS -destination 'platform=macOS' -only-testing:CosmoOSTests/CommandKSearchPipelineTests/testSearchCompletionKeepsFirstSelectionAndPreviewIdentityStable CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: PASS after Tasks 1-4.

## Task 6: Full Focused Verification

**Files:**
- No production changes.

- [ ] **Step 1: Run focused Command-K tests**

Run:

```bash
xcodebuild test -scheme CosmoOS -destination 'platform=macOS' -only-testing:CosmoOSTests/CommandKSearchPipelineTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 2: Manual behavior pass**

Launch the app through the normal local app workflow. Open Command-K and verify:

```text
1. Type "idea Euan:" and pause.
Expected: no spinner appears or disappears; first row remains highlighted; preview remains mounted.

2. Continue typing "turn onboarding calls into a story bank" and pause.
Expected: row subtitle/preview text updates, but highlight and preview shell do not flash.

3. Search for "ideas" and pause.
Expected: best result remains selected; enrichment may reorder only if the semantic first result actually changes.

4. Search for a guaranteed miss.
Expected: no loading row flashes; after search settles, "No matches yet." appears once.
```

- [ ] **Step 3: Confirm no direct phase-driven UI dependencies remain**

Run:

```bash
rg -n "currentPhase|ProgressView\\(\\)|symbolEffect\\(\\.pulse" UI/CommandK/CortexSearchBar.swift UI/CommandK/CommandKView.swift UI/CommandK/CortexSearchResultsView.swift UI/CommandK/CortexResultRail.swift UI/CommandK/UnifiedSearchResultsView.swift
```

Expected:

```text
No `currentPhase == .searching` usage in visible Command-K search chrome or result rows.
No search-bar `ProgressView()` tied to typing.
No phase-driven `.symbolEffect(.pulse, ...)` on the search icon.
```

## Non-Goals

- Do not change ranking logic.
- Do not change scoped idea parsing or execution.
- Do not remove background semantic enrichment.
- Do not hide real empty states.
- Do not add a different spinner, skeleton row, or loading badge in another place.

## Rollback Plan

If this causes regressions, revert only these planned changes:

- `currentPhase` non-published conversion
- `CommandKSearchFeedback`
- search bar spinner and pulse removals
- result loading row removals
- associated tests

The previous stable identity and scoped idea work should remain intact.

