# Swipe File Destination Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a first-class Apple-grade Swipe File destination from the sidebar, backed by reusable swipe filtering state rather than Command K-only presentation state.

**Architecture:** Extract reusable swipe library filtering/shelf logic into `UI/SwipeFile`, test it independently, then add a full-window SwiftUI destination with masthead, smart filters, shelves, adaptive detail preview, grid/cluster/compact modes, Discover placeholder, and sidebar board placeholders. Existing swipe cards and Swipe Study focus-mode routing are reused where they are already strong.

**Tech Stack:** macOS SwiftUI, existing `DS` design tokens, `ProMotionSprings`, `AtomRepository`, `SwipeGalleryItem`, `SwipeGalleryCardView`, XCTest, Xcode project source membership via `xcodeproj`.

---

## File Structure

Create:

- `UI/SwipeFile/SwipeLibraryFilterState.swift`
  Filter state, smart presets, gallery mode, sidebar section selection, and small display helpers.
- `UI/SwipeFile/SwipeLibraryFiltering.swift`
  Pure filtering, sorting, facet, and shelf derivation helpers.
- `UI/SwipeFile/SwipeLibraryViewModel.swift`
  Main-actor loader/state owner for the full Swipe File destination.
- `UI/SwipeFile/SwipeFileHomeView.swift`
  Root full-window destination.
- `UI/SwipeFile/SwipeFileMasthead.swift`
  Title, stats, search, add, mode, and sort controls.
- `UI/SwipeFile/SwipeFilterBar.swift`
  Smart chips, full taxonomy menus, active filters, and clear button.
- `UI/SwipeFile/SwipeShelfSection.swift`
  Horizontal Apple Music-style shelves and shelf cards.
- `UI/SwipeFile/SwipeFileGalleryGrid.swift`
  Masonry grid plus compact list rendering.
- `UI/SwipeFile/SwipeFileClusteredView.swift`
  Clustered full-library view using `FormatSection`.
- `UI/SwipeFile/SwipeFileDetailPreview.swift`
  Adaptive scan-preview inspector.
- `UI/SwipeFile/SwipeFileEmptyState.swift`
  Empty library, no-results, board placeholder, and skeleton states.
- `UI/SwipeFile/SwipeFilePlaceholderDiscoverView.swift`
  Polished Discover placeholder.
- `Canvas/UnifiedSidebar/SidebarSwipeFileSection.swift`
  Swipe File subrows and board placeholder rows.
- `Tests/CosmoOSTests/SwipeLibraryFilteringTests.swift`
  Pure behavior tests.

Modify:

- `Canvas/UnifiedSidebar/UnifiedSidebar.swift`
  Add `.discover` and `.swipeFile(section:)` destinations, sidebar context, and body routing.
- `Canvas/UnifiedSidebar/SidebarNavSection.swift`
  Add Discover and Swipe File top-level rows.
- `Navigation/MainView.swift`
  Add shared `SwipeLibraryViewModel`, render Discover and Swipe File destinations, keep Command K as Search.
- `UI/CommandK/SwipeGalleryCardView.swift`
  Expose the card view to sibling UI modules if needed.
- `Tests/CosmoOSTests/SidebarLayoutPolicyTests.swift`
  Extend non-canvas destination reservation coverage.
- `CosmoOS.xcodeproj/project.pbxproj`
  Add new source and test files to targets.

## Task 1: Test Pure Swipe Library Filtering

**Files:**
- Create: `Tests/CosmoOSTests/SwipeLibraryFilteringTests.swift`
- Create: `UI/SwipeFile/SwipeLibraryFilterState.swift`
- Create: `UI/SwipeFile/SwipeLibraryFiltering.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/CosmoOSTests/SwipeLibraryFilteringTests.swift` with tests for:

```swift
import XCTest
@testable import CosmoOS

final class SwipeLibraryFilteringTests: XCTestCase {
    func testFearHooksPresetMatchesNarrativeHookTypesAndWarningKeywords() {
        let items = [
            makeItem(title: "Stop making this client mistake", hookType: .question, narrative: nil),
            makeItem(title: "Contrarian growth lesson", hookType: .contrarian, narrative: nil),
            makeItem(title: "A calm tutorial", hookType: .howTo, narrative: nil),
            makeItem(title: "Fear story", hookType: .story, narrative: .fearMongering),
        ]

        var filters = SwipeLibraryFilterState()
        filters.smartPreset = .fearHooks

        XCTAssertEqual(
            SwipeLibraryFiltering.filteredItems(from: items, filters: filters, query: "", sortMode: .recent).map(\.title),
            ["Stop making this client mistake", "Contrarian growth lesson", "Fear story"]
        )
    }

    func testSearchAndFiltersCombineConjunctively() {
        let items = [
            makeItem(title: "Thread fear hook", hookType: .boldClaim, format: .thread, creator: "Ava"),
            makeItem(title: "Reel fear hook", hookType: .boldClaim, format: .reel, creator: "Ava"),
            makeItem(title: "Thread curiosity hook", hookType: .curiosityGap, format: .thread, creator: "Ben"),
        ]

        var filters = SwipeLibraryFilterState()
        filters.formats = [.thread]
        filters.hookTypes = [.boldClaim]

        XCTAssertEqual(
            SwipeLibraryFiltering.filteredItems(from: items, filters: filters, query: "fear", sortMode: .recent).map(\.title),
            ["Thread fear hook"]
        )
    }

    func testShelvesAreDeterministicAndLimited() {
        let items = (0..<8).map { index in
            makeItem(
                title: "Swipe \(index)",
                hookScore: Double(10 - index),
                createdAt: "2026-05-\(String(format: "%02d", index + 1))T00:00:00Z"
            )
        }

        let shelves = SwipeLibraryFiltering.shelves(from: items, limit: 4)

        XCTAssertEqual(shelves.first?.id, .recentlyAdded)
        XCTAssertEqual(shelves.first?.items.count, 4)
        XCTAssertEqual(shelves.first?.items.first?.title, "Swipe 7")
        XCTAssertEqual(shelves.map(\.id), [.recentlyAdded, .highPerforming, .hooksToTry])
    }

    private func makeItem(
        title: String,
        hookScore: Double? = nil,
        hookType: SwipeHookType? = nil,
        narrative: NarrativeStyle? = nil,
        format: ContentFormat? = nil,
        creator: String? = nil,
        createdAt: String = "2026-05-01T00:00:00Z"
    ) -> SwipeGalleryItem {
        SwipeGalleryItem(
            atomUUID: UUID().uuidString,
            title: title,
            hookText: title,
            hookScore: hookScore,
            hookType: hookType,
            createdAt: createdAt,
            primaryNarrative: narrative,
            swipeContentFormat: format,
            creatorName: creator
        )
    }
}
```

- [ ] **Step 2: Run the failing tests**

Run:

```bash
xcodebuild test -project CosmoOS.xcodeproj -scheme CosmoOS -destination 'platform=macOS' -only-testing:CosmoOSTests/SwipeLibraryFilteringTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: compile failure because `SwipeLibraryFilterState` and `SwipeLibraryFiltering` do not exist.

- [ ] **Step 3: Implement the pure models and filtering**

Create `SwipeLibraryFilterState.swift` with:

```swift
import Foundation

enum SwipeLibraryMode: String, CaseIterable, Identifiable {
    case grid
    case clusters
    case compact
    var id: String { rawValue }
}

enum SwipeLibrarySmartPreset: String, CaseIterable, Identifiable {
    case all
    case fearHooks
    case curiosity
    case threads
    case reels
    case highScore
    var id: String { rawValue }
}

enum SwipeLibrarySectionSelection: Equatable, Hashable {
    case all
    case recentlyAdded
    case highHookScore
    case unstudied
    case board(String)
}

struct SwipeLibraryFilterState: Equatable {
    var smartPreset: SwipeLibrarySmartPreset = .all
    var platforms: Set<String> = []
    var hookTypes: Set<SwipeHookType> = []
    var frameworks: Set<SwipeFrameworkType> = []
    var narratives: Set<NarrativeStyle> = []
    var formats: Set<ContentFormat> = []
    var creator: String?
    var niche: String?
    var onlyStudied = false
    var onlyUnstudied = false
    var minimumHookScore: Double?
}
```

Create `SwipeLibraryFiltering.swift` with pure static helpers for filtering, sorting, shelves, and fear-preset matching.

- [ ] **Step 4: Run tests again**

Expected: `SwipeLibraryFilteringTests` pass.

## Task 2: Add Navigation Policy Coverage

**Files:**
- Modify: `Canvas/UnifiedSidebar/UnifiedSidebar.swift`
- Modify: `Tests/CosmoOSTests/SidebarLayoutPolicyTests.swift`

- [ ] **Step 1: Write failing sidebar tests**

Extend `testNonCanvasDestinationsReserveSidebarSpaceWithoutChangingShell` to include:

```swift
let destinations: [SidebarDestination] = [
    .commandCenter,
    .inbox,
    .codex,
    .discover,
    .swipeFile(section: .all),
]
```

- [ ] **Step 2: Run the failing sidebar test**

Expected: compile failure because the new destinations do not exist.

- [ ] **Step 3: Add destination cases**

Add `SidebarDestination.discover` and `SidebarDestination.swipeFile(section: SwipeLibrarySectionSelection)`.

- [ ] **Step 4: Run sidebar test again**

Expected: pass.

## Task 3: Build Swipe Library View Model

**Files:**
- Create: `UI/SwipeFile/SwipeLibraryViewModel.swift`

- [ ] **Step 1: Implement view model**

Create a `@MainActor final class SwipeLibraryViewModel: ObservableObject` with published items, filtered items, clustered sections, shelves, filters, search query, sort mode, mode, selected item, selected section, available creators/niches, and loading state. Reuse the detached generation pattern from Command K.

- [ ] **Step 2: Verify compile with targeted tests**

Run the filtering and sidebar tests.

## Task 4: Build Full Swipe File Surface

**Files:**
- Create: `UI/SwipeFile/SwipeFileHomeView.swift`
- Create: `UI/SwipeFile/SwipeFileMasthead.swift`
- Create: `UI/SwipeFile/SwipeFilterBar.swift`
- Create: `UI/SwipeFile/SwipeShelfSection.swift`
- Create: `UI/SwipeFile/SwipeFileGalleryGrid.swift`
- Create: `UI/SwipeFile/SwipeFileClusteredView.swift`
- Create: `UI/SwipeFile/SwipeFileDetailPreview.swift`
- Create: `UI/SwipeFile/SwipeFileEmptyState.swift`
- Modify: `UI/CommandK/SwipeGalleryCardView.swift`

- [ ] **Step 1: Expose canonical swipe card**

Change `SwipeGalleryCardView` from internal to reusable where necessary and preserve its existing behavior.

- [ ] **Step 2: Implement masthead, filters, shelves, grid, clustered, compact, empty, and preview views**

Use `DS` tokens, `ProMotionSprings`, button/menu controls, stable dimensions, and adaptive layout. Cards select into the preview; double-click opens Swipe Study.

- [ ] **Step 3: Compile through targeted tests**

Run filtering/sidebar tests.

## Task 5: Build Discover and Sidebar Sections

**Files:**
- Create: `UI/SwipeFile/SwipeFilePlaceholderDiscoverView.swift`
- Create: `Canvas/UnifiedSidebar/SidebarSwipeFileSection.swift`
- Modify: `Canvas/UnifiedSidebar/SidebarNavSection.swift`
- Modify: `Canvas/UnifiedSidebar/UnifiedSidebar.swift`

- [ ] **Step 1: Implement Discover placeholder**

Create a polished non-interactive destination for future high-performing post discovery.

- [ ] **Step 2: Implement Swipe File sidebar section**

Add subrows for `All Swipes`, `Recently Added`, `High Hook Score`, `Unstudied`, and board placeholders.

- [ ] **Step 3: Add top-level rows**

Add `Discover` and `Swipe File` to the top-level navigation.

## Task 6: Route Destinations in MainView

**Files:**
- Modify: `Navigation/MainView.swift`

- [ ] **Step 1: Add shared view model**

Add `@StateObject private var swipeLibraryViewModel = SwipeLibraryViewModel()`.

- [ ] **Step 2: Render new destinations**

Render `SwipeFileHomeView(viewModel: swipeLibraryViewModel)` for `.swipeFile`, and `SwipeFilePlaceholderDiscoverView()` for `.discover`.

- [ ] **Step 3: Sync sidebar context**

Ensure new non-canvas destinations reserve sidebar space and update sidebar context correctly.

## Task 7: Add Files to Xcode Project

**Files:**
- Modify: `CosmoOS.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add source references**

Use the `xcodeproj` Ruby library to add new `UI/SwipeFile`, `Canvas/UnifiedSidebar`, and test files to the correct targets.

- [ ] **Step 2: Run tests**

Run:

```bash
xcodebuild test -project CosmoOS.xcodeproj -scheme CosmoOS -destination 'platform=macOS' -only-testing:CosmoOSTests/SwipeLibraryFilteringTests -only-testing:CosmoOSTests/SidebarLayoutPolicyTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

## Task 8: Final Build and Visual QA

**Files:**
- All changed files

- [ ] **Step 1: Full build**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

- [ ] **Step 2: Fix compiler issues without reducing scope**

Fix any local compile errors caused by the new files.

- [ ] **Step 3: Report final verification**

Summarize tests/build status and any known unrelated build blockers.
