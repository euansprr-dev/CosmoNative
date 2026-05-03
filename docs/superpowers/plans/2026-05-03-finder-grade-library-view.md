# Finder-Grade Library View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the approved Cosmo Finder library view: first-class project, thinkspace, and cluster folders with CMD-K-style document previews for standalone and contained documents.

**Architecture:** Keep production changes inside existing `UI/Library` files to avoid touching the already-dirty Xcode project. Add hierarchy behavior to `LibraryItem`/`LibraryViewModel`, replace the masonry grid with a fixed Finder-like icon grid, and reuse existing CMD-K thumbnail preview components. Add pure SwiftPM tests for hierarchy and cluster resolution behavior.

**Tech Stack:** Swift 6, SwiftUI, XCTest, existing `Atom`, `Thinkspace`, `CodableCluster`, `LibraryItem`, `Spotlight*` preview views, `DS` design tokens, `ProMotionSprings`.

---

### Task 1: Test Library Hierarchy Rules

**Files:**
- Create: `Tests/CosmoOSTests/LibraryHierarchyTests.swift`
- Modify: `UI/Library/LibraryView.swift`

- [ ] **Step 1: Write failing tests**

Add tests that define the desired behavior before production changes:

```swift
import XCTest
@testable import CosmoOS

final class LibraryHierarchyTests: XCTestCase {
    func testHomeItemsKeepProjectsAndStandaloneDocumentsButHideProjectOwnedAtomsAndThinkspaces() {
        let project = makeItem(uuid: "project-1", title: "Ben", kind: .project)
        let projectAtom = makeItem(uuid: "project-doc", title: "Draft", kind: .atom, projectUUID: "project-1")
        let standalone = makeItem(uuid: "loose-doc", title: "Loose", kind: .atom)
        let thinkspace = makeItem(uuid: "thinkspace-1", title: "Canvas", kind: .thinkspace, projectUUID: "project-1")

        let result = LibraryHierarchy.homeItems(
            from: [projectAtom, standalone, thinkspace, project],
            projectOwnedAtomUUIDs: ["project-doc"]
        )

        XCTAssertEqual(result.map(\.uuid), ["project-1"])
        XCTAssertEqual(result.standalone.map(\.uuid), ["loose-doc"])
    }

    func testProjectFolderShowsThinkspacesClustersAndDirectProjectAtoms() {
        let project = makeItem(uuid: "project-1", title: "Ben", kind: .project)
        let thinkspace = makeItem(uuid: "thinkspace-1", title: "Content Board", kind: .thinkspace, projectUUID: "project-1")
        let cluster = makeItem(uuid: "cluster-1", title: "For review", kind: .cluster, projectUUID: "project-1", thinkspaceUUIDs: ["thinkspace-1"])
        let projectAtom = makeItem(uuid: "project-doc", title: "Draft", kind: .atom, projectUUID: "project-1")
        let otherAtom = makeItem(uuid: "other", title: "Other", kind: .atom)

        let contents = LibraryHierarchy.contents(of: project, in: [otherAtom, projectAtom, cluster, thinkspace])

        XCTAssertEqual(contents.map(\.uuid), ["thinkspace-1", "cluster-1", "project-doc"])
    }

    func testThinkspaceFolderShowsClustersAndMemberAtoms() {
        let thinkspace = makeItem(uuid: "thinkspace-1", title: "Content Board", kind: .thinkspace)
        let cluster = makeItem(uuid: "cluster-1", title: "For review", kind: .cluster, thinkspaceUUIDs: ["thinkspace-1"])
        let member = makeItem(uuid: "doc-1", title: "Doc", kind: .atom, thinkspaceUUIDs: ["thinkspace-1"])
        let other = makeItem(uuid: "doc-2", title: "Other", kind: .atom)

        let contents = LibraryHierarchy.contents(of: thinkspace, in: [other, member, cluster])

        XCTAssertEqual(contents.map(\.uuid), ["cluster-1", "doc-1"])
    }

    func testClusterFolderShowsOnlyResolvedBlockAtomsInClusterOrder() {
        let cluster = makeItem(uuid: "cluster-1", title: "For review", kind: .cluster, clusterBlockUUIDs: ["doc-2", "missing", "doc-1"])
        let first = makeItem(uuid: "doc-1", title: "First", kind: .atom)
        let second = makeItem(uuid: "doc-2", title: "Second", kind: .atom)

        let contents = LibraryHierarchy.contents(of: cluster, in: [first, second])

        XCTAssertEqual(contents.map(\.uuid), ["doc-2", "doc-1"])
    }
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swift test --filter LibraryHierarchyTests
```

Expected: FAIL because `LibraryHierarchy` and `.cluster` do not exist yet.

- [ ] **Step 3: Add minimal hierarchy model support**

In `UI/Library/LibraryView.swift`, add `.cluster` to `LibraryItemKind`, add cluster metadata fields to `LibraryItem`, add a test helper initializer under `#if DEBUG`, and add `LibraryHierarchy` pure functions:

```swift
enum LibraryItemKind: String {
    case atom
    case project
    case thinkspace
    case cluster
}

enum LibraryHierarchy {
    static func homeItems(from items: [LibraryItem], projectOwnedAtomUUIDs: Set<String>) -> (items: [LibraryItem], standalone: [LibraryItem]) { ... }
    static func contents(of folder: LibraryItem, in items: [LibraryItem]) -> [LibraryItem] { ... }
}
```

- [ ] **Step 4: Run tests and verify GREEN**

Run:

```bash
swift test --filter LibraryHierarchyTests
```

Expected: PASS.

### Task 2: Load Cluster Folder Items

**Files:**
- Modify: `UI/Library/LibraryView.swift`
- Test: `Tests/CosmoOSTests/LibraryHierarchyTests.swift`

- [ ] **Step 1: Add failing test for cluster item construction**

Add a test that creates a `CodableCluster` and `Thinkspace`, then asserts the produced `LibraryItem` is a cluster folder with block UUIDs and provenance.

- [ ] **Step 2: Run test and verify RED**

Run `swift test --filter LibraryHierarchyTests`.

Expected: FAIL because the cluster initializer does not exist.

- [ ] **Step 3: Implement cluster initializer and ViewModel loading**

Add `init(cluster:thinkspace:project:)` to `LibraryItem`. In `LibraryViewModel.loadLibrary()`, fetch thinkspace atoms, decode `ThinkspaceMetadata.clusters`, build cluster `LibraryItem`s, and include them in `allItems`.

- [ ] **Step 4: Run tests and verify GREEN**

Run `swift test --filter LibraryHierarchyTests`.

Expected: PASS.

### Task 3: Replace Masonry With Finder Icon Grid

**Files:**
- Modify: `UI/Library/LibraryGridView.swift`
- Modify: `UI/Library/LibraryView.swift`

- [ ] **Step 1: Keep hierarchy tests green before visual change**

Run `swift test --filter LibraryHierarchyTests`.

- [ ] **Step 2: Replace `MasonryLayout` usage with adaptive `LazyVGrid`**

Use fixed tile dimensions, folder-first order from `LibraryViewModel`, and stable spacing:

```swift
private let minTileWidth: CGFloat = 156
private let maxTileWidth: CGFloat = 180
private let gridSpacing: CGFloat = 28
```

- [ ] **Step 3: Add `CosmoFinderTileView`**

Render folder tiles for `.project`, `.thinkspace`, and `.cluster`; render document thumbnails for atoms by reusing `SpotlightPageContent`, `SpotlightImageContent`, `SpotlightConnectionPreview`, and `SpotlightFauxPage`.

- [ ] **Step 4: Preserve context menus and open behavior**

Move the existing context menu actions from `LibraryCardView` into the new tile view so open, open as pane, add to canvas, and delete still work.

### Task 4: Wire Navigation And Chrome

**Files:**
- Modify: `UI/Library/LibraryView.swift`

- [ ] **Step 1: Update folder navigation**

Make project, thinkspace, and cluster single-click navigation use `LibraryHierarchy.contents(of:in:)`. Keep double-click opening for thinkspaces through `openInFocusMode`.

- [ ] **Step 2: Replace standalone horizontal rail**

Remove the home-only standalone rail and let standalone documents render in the same icon grid after folders.

- [ ] **Step 3: Calm the top bar**

Update placeholder text to "Search anything...", use icon-only view controls, and keep create/sort controls visually secondary.

### Task 5: Verify Build And Behavior

**Files:**
- Test: `Tests/CosmoOSTests/LibraryHierarchyTests.swift`
- Modify as needed: `UI/Library/LibraryView.swift`, `UI/Library/LibraryGridView.swift`

- [ ] **Step 1: Run focused tests**

Run:

```bash
swift test --filter LibraryHierarchyTests
```

Expected: PASS.

- [ ] **Step 2: Run a wider build check**

Run:

```bash
swift test --filter CosmoOSTests
```

Expected: PASS or report unrelated pre-existing failures separately.

- [ ] **Step 3: Review changed files**

Run:

```bash
git diff -- UI/Library/LibraryView.swift UI/Library/LibraryGridView.swift Tests/CosmoOSTests/LibraryHierarchyTests.swift
```

Expected: Only library and test changes.
