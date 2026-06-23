# Browser Favorites Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the fragile browser pin behavior with page-level, unlimited browser favorites that can be opened from the browser chrome, a first-run/start-page panel, and Command-K.

**Architecture:** Keep the existing `CosmoBrowserStore` actor as the persistence boundary, but change favorite identity from host-level to normalized page-level identity. The browser pane owns the live UI state, Command-K reads all stored favorites through the store, and browser opening continues through `CosmoNotification.Navigation.openWebBrowserPane`.

**Tech Stack:** macOS SwiftUI, WebKit, Swift Codable persistence, XCTest, existing CosmoOS DS/PeakUI components, Command-K unified search.

---

## Root Cause

The current pin system de-duplicates by `host`.

Affected code:
- `Navigation/CosmoWebBrowserPane.swift:211`
- `Navigation/CosmoWebBrowserPane.swift:356`
- `Navigation/CosmoWebBrowserPane.swift:1077`
- `Navigation/CosmoWebBrowserPane.swift:1203`
- `Navigation/CosmoWebBrowserPane.swift:1237`

That makes these all the same pin:

```text
https://www.instagram.com/josh/
https://www.instagram.com/euan/
https://www.instagram.com/p/example/
```

The existing tests only verify different-host pins, so the real Instagram workflow is not covered.

## File Structure

- Modify: `Navigation/CosmoWebBrowserPane.swift`
  - Add page-level favorite identity.
  - Change add/remove/is-favorited behavior to use the page key or id, not host.
  - Rename visible pin affordances to favorites/stars.
  - Add the favorites bar overflow and start-page panel.
- Modify: `UI/CommandK/CommandKViewModel.swift`
  - Rename browser search source labels from pins to favorites.
  - Ensure all favorites are searchable, including multiple same-host pages.
- Modify: `Tests/CosmoOSTests/PaneManagerBrowserPaneTests.swift`
  - Add same-host regression tests for store, session, state, and removal.
- Modify: `Tests/CosmoOSTests/CommandKSearchPipelineTests.swift`
  - Add multiple same-host favorites in unified search.

## Product Decisions

- Store unlimited favorites.
- Display a compact adaptive favorites bar under the browser toolbar.
- If the bar gets crowded, show the highest-priority favorites inline and put the rest in an overflow menu.
- Use star/favorite language in the browser UI. Keep `CosmoBrowserPinnedSite` as a compatibility type name only if renaming it would create too much churn in one pass.
- Command-K should index all favorites, but the visible group can keep a reasonable result cap for scanability.
- A renamed favorite must be searchable by its custom display name in Command-K and must open the exact saved URL. Example: a favorite saved from `https://www.instagram.com/joshvillareal/` and renamed to `Josh Instagram` should appear when searching `Josh Instagram` and open that exact Instagram URL.
- Existing saved pins migrate naturally. Previously replaced same-host pins cannot be recovered because only the last one exists on disk.

## Task 1: Lock the Same-Host Regression

**Files:**
- Modify: `Tests/CosmoOSTests/PaneManagerBrowserPaneTests.swift`

- [ ] **Step 1: Write failing store test**

Add:

```swift
func testBrowserStoreKeepsMultipleFavoritesOnSameHost() async throws {
    let stateURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("json")
    let store = CosmoBrowserStore(fileURL: stateURL)
    let first = CosmoBrowserPinnedSite(
        url: URL(string: "https://www.instagram.com/josh/")!,
        title: "Josh",
        displayName: "Josh"
    )
    let second = CosmoBrowserPinnedSite(
        url: URL(string: "https://www.instagram.com/euan/")!,
        title: "Euan",
        displayName: "Euan"
    )

    _ = try await store.upsertPin(first, for: CosmoBrowserProfile.standard.id)
    let pins = try await store.upsertPin(second, for: CosmoBrowserProfile.standard.id)

    XCTAssertEqual(pins.map(\.url), [second.url, first.url])
    XCTAssertEqual(Set(pins.map(\.displayName)), ["Josh", "Euan"])

    try? FileManager.default.removeItem(at: stateURL)
}
```

- [ ] **Step 2: Verify red**

Run:

```bash
xcodebuild -quiet -project CosmoOS.xcodeproj -scheme CosmoOS -destination 'platform=macOS' -only-testing:CosmoOSTests/PaneManagerBrowserPaneTests/testBrowserStoreKeepsMultipleFavoritesOnSameHost test
```

Expected: FAIL because `upsertPin` removes by host.

- [ ] **Step 3: Add state and removal regressions**

Add tests that prove exact-page identity:

```swift
func testBrowserStateMarksOnlyExactCurrentPageAsFavorited() {
    let first = URL(string: "https://www.instagram.com/josh/")!
    let second = URL(string: "https://www.instagram.com/euan/")!
    let state = CosmoWebBrowserState(initialURL: first, title: "Josh")

    state.pins = [
        CosmoBrowserPinnedSite(url: first, title: "Josh", displayName: "Josh")
    ]
    XCTAssertTrue(state.isCurrentSitePinned)

    state.applySnapshot(url: second, title: "Euan", isLoading: false, estimatedProgress: 1, canGoBack: true, canGoForward: false)
    XCTAssertFalse(state.isCurrentSitePinned)
}
```

Expected before implementation: FAIL because `isCurrentSitePinned` checks host only.

## Task 2: Introduce Page-Level Favorite Identity

**Files:**
- Modify: `Navigation/CosmoWebBrowserPane.swift`

- [ ] **Step 1: Add canonical favorite key**

Add to `CosmoBrowserPinnedSite`:

```swift
var pageKey: String {
    Self.pageKey(for: url)
}

static func pageKey(for url: URL) -> String {
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    components?.scheme = components?.scheme?.lowercased()
    components?.host = components?.host?.lowercased()
    components?.fragment = nil
    components?.queryItems = components?.queryItems?
        .filter { item in
            let name = item.name.lowercased()
            return !name.hasPrefix("utm_") && name != "fbclid" && name != "gclid"
        }
        .sorted { $0.name < $1.name }
    var key = components?.url?.absoluteString ?? url.absoluteString
    while key.hasSuffix("/") {
        key.removeLast()
    }
    return key
}
```

- [ ] **Step 2: Update session/store dedupe**

Replace host-based add dedupe:

```swift
pins.removeAll { $0.host == pin.host }
```

with page-key dedupe:

```swift
pins.removeAll { $0.pageKey == pin.pageKey }
```

Apply the same change in `CosmoBrowserSession.pinCurrentSite`, `CosmoBrowserStore.upsertPin`, and `CosmoWebBrowserState.pinCurrentSite`.

- [ ] **Step 3: Change removal to selected favorite id**

Replace:

```swift
func removePin(host: String, for profileID: String) throws -> [CosmoBrowserPinnedSite]
```

with:

```swift
func removePin(id: UUID, for profileID: String) throws -> [CosmoBrowserPinnedSite] {
    var pins = snapshot.pinnedSitesByProfile[profileID] ?? []
    pins.removeAll { $0.id == id }
    snapshot.pinnedSitesByProfile[profileID] = pins
    try persist()
    return pins
}
```

Update `CosmoWebBrowserState.unpin(_:)` to call `removePin(id: pin.id, for: profileID)`.

- [ ] **Step 4: Change exact favorited state**

Replace host check:

```swift
let host = CosmoBrowserPinnedSite.normalizedHost(for: currentURL)
return pins.contains { $0.host == host }
```

with:

```swift
let pageKey = CosmoBrowserPinnedSite.pageKey(for: currentURL)
return pins.contains { $0.pageKey == pageKey }
```

- [ ] **Step 5: Run browser tests**

Run:

```bash
xcodebuild -quiet -project CosmoOS.xcodeproj -scheme CosmoOS -destination 'platform=macOS' -only-testing:CosmoOSTests/PaneManagerBrowserPaneTests test
```

Expected: all browser tests pass, including the new same-host regressions.

## Task 3: Make Favorites Feel Native In The Browser

**Files:**
- Modify: `Navigation/CosmoWebBrowserPane.swift`

- [ ] **Step 1: Rename visible affordances**

Change toolbar button:

```swift
CosmoBrowserToolbarButton(
    systemName: browserState.isCurrentSitePinned ? "star.fill" : "star",
    help: browserState.isCurrentSitePinned ? "Remove Favorite" : "Add Favorite",
    action: browserState.toggleCurrentFavorite
)
```

Keep the backing method named `pinCurrentSite` only until all behavior tests are green, then rename to `toggleCurrentFavorite` if the diff stays readable.

- [ ] **Step 2: Make the favorites bar adaptive**

Convert `pinnedSitesBar` to `favoritesBar`:

```swift
private var favoriteLimitForBar: Int { 8 }

private var visibleFavorites: [CosmoBrowserPinnedSite] {
    Array(browserState.pins.prefix(favoriteLimitForBar))
}

private var overflowFavorites: [CosmoBrowserPinnedSite] {
    Array(browserState.pins.dropFirst(favoriteLimitForBar))
}
```

Render `visibleFavorites` as compact chips and `overflowFavorites` inside a trailing `Menu` with `ellipsis.circle`.

- [ ] **Step 3: Use PeakUI chrome**

Keep the bar as inner chrome:

```swift
.background(DS.surfaceElevated, in: Capsule())
.overlay(Capsule().stroke(DS.borderSubtle, lineWidth: 1))
.animation(ProMotionSprings.focusTransition, value: browserState.pins)
```

Do not add new glass inside the browser's existing chrome.

- [ ] **Step 4: Update context menu language**

Use:

```swift
Label("Open Favorite", systemImage: "arrow.up.forward.app")
Label("Rename Favorite", systemImage: "pencil")
Label("Remove Favorite", systemImage: "trash")
```

## Task 4: Add A Browser Start Page / Quick Access Panel

**Files:**
- Modify: `Navigation/CosmoWebBrowserPane.swift`

- [ ] **Step 1: Add start-page state**

Add to `CosmoWebBrowserState`:

```swift
@Published var showsStartPage: Bool
```

Initialize:

```swift
self.showsStartPage = initialURL == CosmoBrowserURLResolver.defaultHomeURL
```

Set `showsStartPage = false` in `load(_:)` and `commitAddressText()`.

- [ ] **Step 2: Add start page view**

Create a private SwiftUI view in the same file for the first pass:

```swift
private struct CosmoBrowserStartPage: View {
    let favorites: [CosmoBrowserPinnedSite]
    let recentHistory: [CosmoBrowserHistoryItem]
    let onOpen: (URL, String?) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space16) {
                Text("Favorites")
                    .font(DS.pageTitle)
                    .foregroundStyle(DS.text)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: DS.space10)], spacing: DS.space10) {
                    ForEach(favorites) { favorite in
                        Button {
                            onOpen(favorite.url, favorite.displayName)
                        } label: {
                            favoriteTile(favorite)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !recentHistory.isEmpty {
                    Text("Recent")
                        .font(DS.title2)
                        .foregroundStyle(DS.text)
                    recentList
                }
            }
            .padding(DS.space20)
        }
        .background(DS.bg)
    }
}
```

Extract helper subviews inside `CosmoBrowserStartPage` so no body grows too large.

- [ ] **Step 3: Show start page instead of blank Google**

In the main ZStack, render:

```swift
if browserState.showsStartPage {
    CosmoBrowserStartPage(
        favorites: browserState.pins,
        recentHistory: browserState.recentHistory,
        onOpen: { url, title in browserState.load(url) }
    )
    .transition(.opacity)
} else {
    CosmoBrowserWebView(state: browserState)
        .id(browserState.webViewIdentity)
        .background(DS.bg)
}
```

## Task 5: Make Command-K Favorites First-Class

**Files:**
- Modify: `UI/CommandK/CommandKViewModel.swift`
- Modify: `Tests/CosmoOSTests/CommandKSearchPipelineTests.swift`

- [ ] **Step 1: Add same-host Command-K test**

Add:

```swift
func testUnifiedSearchReturnsMultipleBrowserFavoritesOnSameHost() {
    let pins = [
        CosmoBrowserPinnedSite(url: URL(string: "https://www.instagram.com/josh/")!, title: "Josh", displayName: "Josh"),
        CosmoBrowserPinnedSite(url: URL(string: "https://www.instagram.com/euan/")!, title: "Euan", displayName: "Euan")
    ]

    let output = CommandKUnifiedSearchComposer.buildOutput(
        query: "instagram",
        hybridResults: [],
        swipeGalleryItems: [],
        ideaGalleryItems: [],
        readwiseBooks: [],
        browserPins: pins
    )

    XCTAssertEqual(output.flatResults.filter { $0.source == .browser }.count, 2)
    XCTAssertEqual(Set(output.flatResults.compactMap(\.browserURL)), Set(pins.map(\.url)))
}
```

- [ ] **Step 2: Add renamed favorite exact-open Command-K test**

Add:

```swift
func testUnifiedSearchFindsRenamedBrowserFavoriteAndPreservesExactURL() {
    let url = URL(string: "https://www.instagram.com/joshvillareal/")!
    let pin = CosmoBrowserPinnedSite(
        url: url,
        title: "Josh Villareal (@joshvillareal)",
        displayName: "Josh Instagram"
    )

    let output = CommandKUnifiedSearchComposer.buildOutput(
        query: "Josh Instagram",
        hybridResults: [],
        swipeGalleryItems: [],
        ideaGalleryItems: [],
        readwiseBooks: [],
        browserPins: [pin]
    )

    let result = output.flatResults.first
    XCTAssertEqual(result?.source, .browser)
    XCTAssertEqual(result?.resultKind, .browserPin)
    XCTAssertEqual(result?.title, "Josh Instagram")
    XCTAssertEqual(result?.browserURL, url)
    XCTAssertEqual(result?.browserTitle, "Josh Instagram")
    XCTAssertGreaterThan(result?.relevance ?? 0, 1.0)
}
```

- [ ] **Step 3: Verify Command-K browser favorite open notification keeps exact URL**

Add or update the existing open-selected test to use the renamed favorite:

```swift
@MainActor
func testOpenSelectedRenamedBrowserFavoriteOpensExactBrowserURL() async {
    let url = URL(string: "https://www.instagram.com/joshvillareal/")!
    let result = UnifiedSearchResult(
        id: "browser-pin-josh-instagram",
        source: .browser,
        resultKind: .browserPin,
        title: "Josh Instagram",
        subtitle: "instagram.com · Browser Favorite",
        snippet: url.absoluteString,
        icon: "star.fill",
        accentColor: DS.entityResearch,
        relevance: 1.4,
        atomUUID: nil,
        atomType: nil,
        thinkspaceId: nil,
        projectUUID: nil,
        projectName: nil,
        thinkspaceNames: [],
        readwiseBookId: nil,
        browserURL: url,
        browserTitle: "Josh Instagram"
    )
    let viewModel = CommandKViewModel()
    let expectation = expectation(description: "renamed browser favorite notification")
    let token = NotificationCenter.default.addObserver(
        forName: CosmoNotification.Navigation.openWebBrowserPane,
        object: nil,
        queue: nil
    ) { notification in
        XCTAssertEqual(notification.userInfo?["url"] as? URL, url)
        XCTAssertEqual(notification.userInfo?["title"] as? String, "Josh Instagram")
        expectation.fulfill()
    }

    viewModel.isUnifiedSearchActive = true
    viewModel.unifiedFlatResults = [result]
    viewModel.selectedResultIndex = 0

    viewModel.openSelected()
    await fulfillment(of: [expectation], timeout: 1)
    NotificationCenter.default.removeObserver(token)
}
```

- [ ] **Step 4: Rename Command-K labels**

Change:

```swift
case .browser: return "Browser Pins"
case .browser: return "pin.fill"
```

to:

```swift
case .browser: return "Browser Favorites"
case .browser: return "star.fill"
```

- [ ] **Step 5: Improve result copy**

Change browser favorite result title from:

```swift
title: "Open this page in browser"
```

to:

```swift
title: pin.displayName
subtitle: "\(pin.host) · Browser Favorite"
```

Update tests accordingly.

## Task 6: Verification

**Files:**
- No code edits.

- [ ] **Step 1: Run browser tests**

```bash
xcodebuild -quiet -project CosmoOS.xcodeproj -scheme CosmoOS -destination 'platform=macOS' -only-testing:CosmoOSTests/PaneManagerBrowserPaneTests test
```

Expected: all pass.

- [ ] **Step 2: Run Command-K tests**

```bash
xcodebuild -quiet -project CosmoOS.xcodeproj -scheme CosmoOS -destination 'platform=macOS' -only-testing:CosmoOSTests/CommandKSearchPipelineTests test
```

Expected: all pass.

- [ ] **Step 3: Build app**

```bash
xcodebuild -quiet -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug build
```

Expected: build succeeds.

- [ ] **Step 4: Manual verification**

Open the browser and verify:

1. Open `https://www.instagram.com/josh/`, star it.
2. Navigate to `https://www.instagram.com/euan/`, star it.
3. Both favorites remain visible or accessible through overflow.
4. The star is filled only on the exact favorited page.
5. Removing one Instagram favorite does not remove the other.
6. Command-K search for `instagram` shows both favorites.
7. Rename Josh's favorite to `Josh Instagram`.
8. Command-K search for `Josh Instagram` shows that favorite by its custom name.
9. Opening the Command-K result opens the exact saved Instagram URL, not just `instagram.com`.

## Future Follow-Ups

- Add a dedicated browser favorites manager sheet with drag reorder and folders.
- Add sidebar integration as a compact "Browser Favorites" section if it does not overcrowd the global sidebar.
- Add Command Center browser widgets only after the base favorite model is reliable.
