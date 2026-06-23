# Atom Window Unified Toolbar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Atom window's separate opaque titlebar with an Atom-only unified Liquid Glass command toolbar hosted by the active focus-mode toolbar where possible.

**Architecture:** Introduce an optional Atom chrome environment context provided only by `AtomWindowRootView`. Focus-mode toolbars render Atom command controls only when that context exists, so standalone focus modes remain unchanged.

**Tech Stack:** SwiftUI, XCTest source-boundary tests, CosmoOS DS tokens, `cosmoGlassPanel`, macOS 26 Liquid Glass.

---

## File Structure

- Modify `UI/AtomWindow/AtomWindowRootView.swift`: remove the opened-atom outer header, provide the Atom chrome context, and restyle empty/loading/generic fallback chrome.
- Create `UI/AtomWindow/AtomWindowChromeContext.swift`: optional environment value plus shared Atom chrome command clusters.
- Modify `UI/AtomWindow/AtomSearchOverlay.swift`: move search overlay to Command-K-style glass surfaces.
- Modify focus-mode toolbar files:
  - `UI/FocusMode/Notes/NoteFocusModeView.swift`
  - `UI/FocusMode/Content/ContentFocusModeView.swift`
  - `UI/FocusMode/Connection/ConnectionWorkspaceToolbar.swift`
  - `UI/FocusMode/Ideas/IdeaWorkspaceToolbar.swift`
  - `UI/FocusMode/Research/ResearchFocusModeView.swift`
  - `UI/FocusMode/SwipeStudy/SwipeStudyFocusModeView.swift`
  - `UI/FocusMode/CosmoAI/CosmoAIFocusModeView.swift`
- Add tests in `Tests/CosmoOSTests/AtomWindowChromeContextTests.swift`.
- Extend `Tests/CosmoOSTests/FocusModeAppearanceTests.swift` with Atom-only chrome boundary assertions.

### Task 1: Atom Chrome Context Contract

**Files:**
- Create: `UI/AtomWindow/AtomWindowChromeContext.swift`
- Test: `Tests/CosmoOSTests/AtomWindowChromeContextTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import CosmoOS

final class AtomWindowChromeContextTests: XCTestCase {
    func testContextDefaultsToAbsentOutsideAtomWindow() {
        XCTAssertNil(AtomWindowChromeContext.defaultValue)
    }

    func testVisibleControlsReflectCurrentAtomCapabilities() {
        let state = AtomWindowChromeState(
            title: "Call Notes",
            typeIcon: "note.text",
            typeColor: .note,
            canGoBack: true,
            canGoForward: false,
            canBookmark: true,
            isBookmarked: false
        )

        XCTAssertEqual(state.title, "Call Notes")
        XCTAssertTrue(state.canGoBack)
        XCTAssertFalse(state.canGoForward)
        XCTAssertTrue(state.canBookmark)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project CosmoOS.xcodeproj -scheme CosmoOS -only-testing:CosmoOSTests/AtomWindowChromeContextTests`

Expected: fail because `AtomWindowChromeContext` and `AtomWindowChromeState` do not exist.

- [ ] **Step 3: Implement minimal context**

Create `AtomWindowChromeContext.swift` with `AtomWindowChromeState`, `AtomWindowChromeActions`, `AtomWindowChromeContext`, and `EnvironmentValues.atomWindowChromeContext`.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project CosmoOS.xcodeproj -scheme CosmoOS -only-testing:CosmoOSTests/AtomWindowChromeContextTests`

Expected: pass.

### Task 2: Atom Root Becomes the Host

**Files:**
- Modify: `UI/AtomWindow/AtomWindowRootView.swift`
- Modify: `UI/AtomWindow/AtomSearchOverlay.swift`

- [ ] **Step 1: Write boundary tests**

Add assertions that `AtomWindowRootView` sets `.environment(\.atomWindowChromeContext` and no longer renders `AtomWindowHeaderBar` above opened focus content.

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project CosmoOS.xcodeproj -scheme CosmoOS -only-testing:CosmoOSTests/FocusModeAppearanceTests`

Expected: fail on missing Atom chrome context usage.

- [ ] **Step 3: Implement host changes**

Root renders `atomContent` directly for opened atoms, supplies the context via environment, and uses a fallback `AtomWindowUnifiedToolbar` for empty/loading/generic states.

- [ ] **Step 4: Restyle search**

Search overlay uses `cosmoGlassPanel(role: .globalSidebar, cornerRadius: 28)`, removes the dark scrim, keeps filter chips and keyboard behavior.

- [ ] **Step 5: Run tests**

Run: `xcodebuild test -project CosmoOS.xcodeproj -scheme CosmoOS -only-testing:CosmoOSTests/FocusModeAppearanceTests`

Expected: pass.

### Task 3: Focus-Mode Toolbar Integration

**Files:**
- Modify the seven focus-mode toolbar/root files listed in File Structure.

- [ ] **Step 1: Write boundary tests**

Add source assertions that each focus mode reads `@Environment(\.atomWindowChromeContext)` and only renders `AtomWindowChromeControls` inside an `if let atomChrome` branch.

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project CosmoOS.xcodeproj -scheme CosmoOS -only-testing:CosmoOSTests/FocusModeAppearanceTests`

Expected: fail until each focus mode adopts the optional context.

- [ ] **Step 3: Add Atom controls to focus-mode toolbars**

Notes/Content/Connection/Idea/Research/SwipeStudy/CosmoAI append the shared compact Atom controls into their existing glass toolbar rows only when context exists.

- [ ] **Step 4: Preserve standalone behavior**

Leave existing `isPaneContext`, `isPeekContext`, and `!isPaneContext` branches intact. Atom controls are additive and optional.

- [ ] **Step 5: Run tests**

Run: `xcodebuild test -project CosmoOS.xcodeproj -scheme CosmoOS -only-testing:CosmoOSTests/FocusModeAppearanceTests`

Expected: pass.

### Task 4: Final Verification

**Files:** all changed implementation and test files.

- [ ] **Step 1: Run focused tests**

Run: `xcodebuild test -project CosmoOS.xcodeproj -scheme CosmoOS -only-testing:CosmoOSTests/AtomWindowChromeContextTests -only-testing:CosmoOSTests/FocusModeAppearanceTests`

Expected: pass.

- [ ] **Step 2: Run full build**

Run: `xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug build`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Inspect diff**

Run: `git diff --stat && git diff -- UI/AtomWindow UI/FocusMode Tests/CosmoOSTests`

Expected: changes are scoped to Atom chrome, focus-mode optional integration, tests, and docs.
