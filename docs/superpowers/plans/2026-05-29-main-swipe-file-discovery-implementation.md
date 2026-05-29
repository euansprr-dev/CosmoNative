# Main Swipe File Discovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the long-term cross-platform core that powers the existing main Swipe File Discoverer and Creators sidebar destinations.

**Architecture:** Start with a platform-neutral discovery domain layer under `SwipeFile/Discovery`, then bind UI to that stable contract in later tasks. The first slice covers platform identity resolution, provider capability routing, normalized post snapshots, transcript/save states, and deterministic outlier scoring.

**Tech Stack:** Swift, SwiftUI-ready value models, XCTest, Xcode project integration.

---

### Task 1: Cross-Platform Discovery Core

**Files:**
- Create: `SwipeFile/Discovery/SocialDiscoveryModels.swift`
- Create: `SwipeFile/Discovery/SocialPlatformResolver.swift`
- Create: `SwipeFile/Discovery/SocialProviderRegistry.swift`
- Create: `SwipeFile/Discovery/SocialOutlierScorer.swift`
- Test: `Tests/CosmoOSTests/SocialDiscoveryCoreTests.swift`
- Modify: `CosmoOS.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add failing tests**

The test file verifies that supported profile URLs are resolved without guessing ambiguous handles, provider routing is capability-based, and outlier scores are based on median comparable reach with a minimum baseline size.

- [ ] **Step 2: Run targeted Xcode test to verify RED**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug test -only-testing:CosmoOSTests/SocialDiscoveryCoreTests
```

Expected: fail because `SocialPlatformResolver`, `SocialProviderRegistry`, `SocialPostSnapshot`, and `SocialOutlierScorer` do not exist.

- [ ] **Step 3: Implement minimal production core**

Create focused Swift files under `SwipeFile/Discovery`:

- `SocialDiscoveryModels.swift`: platform enums, provider capabilities, normalized creator/post/media/metric/transcript/save models.
- `SocialPlatformResolver.swift`: deterministic platform URL and platform-prefixed handle parser.
- `SocialProviderRegistry.swift`: first-match provider selection by platform and required capabilities.
- `SocialOutlierScorer.swift`: median comparable reach and grade calculation.

- [ ] **Step 4: Run targeted test to verify GREEN**

Run the same targeted Xcode test. Expected: `SocialDiscoveryCoreTests` passes.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/plans/2026-05-29-main-swipe-file-discovery-implementation.md Tests/CosmoOSTests/SocialDiscoveryCoreTests.swift SwipeFile/Discovery CosmoOS.xcodeproj/project.pbxproj
git commit -m "feat: add social discovery core"
```

### Task 2: Discoverer View Model And Query State

**Files:**
- Create: `SwipeFile/Discovery/SocialDiscoveryQuery.swift`
- Create: `SwipeFile/Discovery/SocialDiscoveryStore.swift`
- Create: `Tests/CosmoOSTests/SocialDiscoveryStoreTests.swift`

- [ ] **Step 1: Add tests for filter state**

Test platform, language, follower range, outlier threshold, posted window, sort, and pillar filters as value objects with stable defaults.

- [ ] **Step 2: Implement query and store contracts**

Keep provider execution behind protocols so Bright Data, Apify, official YouTube, X, LinkedIn, Instagram, and Substack integrations can be swapped without changing SwiftUI.

- [ ] **Step 3: Run targeted tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug test -only-testing:CosmoOSTests/SocialDiscoveryStoreTests
```

### Task 3: Creators Catalog Core

**Files:**
- Create: `SwipeFile/Discovery/SocialCreatorCatalog.swift`
- Create: `Tests/CosmoOSTests/SocialCreatorCatalogTests.swift`

- [ ] **Step 1: Add tests for creator import and post sorting**

Verify profile URL lookup, manually-added creators, creator feed snapshots, and sorting by top viewed, most liked, most commented, most reposted, and highest outlier.

- [ ] **Step 2: Implement creator catalog contracts**

Reuse `SocialPlatformIdentity`, `SocialDiscoveryProvider`, and `SocialPostSnapshot` so Creators and Discoverer share the same post card data.

### Task 4: Swipe File UI Binding

**Files:**
- Create/modify existing main Swipe File Discoverer and Creators view files once located in the app navigation.
- Modify existing save/add-to-board flow without changing the working All Swipes destination.

- [ ] **Step 1: Add view-model tests where possible**

Verify add-to-board actions update board membership while posts remain visible in All Swipes.

- [ ] **Step 2: Build Discoverer UI**

Implement dense, native macOS controls for search, platform chips, language, follower count, outlier threshold, posted window, topic pillars, masonry cards, detail sheet, and transcript fetch state.

- [ ] **Step 3: Build Creators UI**

Implement creator search/import, saved creator list, creator profile feed, performance sorting, and add-to-board actions using the same `SocialPostSnapshot` cards.
