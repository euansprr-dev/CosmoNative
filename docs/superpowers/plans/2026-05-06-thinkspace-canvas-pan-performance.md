# Thinkspace Canvas Pan Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Thinkspace panning sustain a 120 Hz target while preserving the current premium Oura-grade visual language.

**Architecture:** Move panning off the expensive SwiftUI graph/layout path. Keep block, cluster, connection, drawing, and glass-scene data in canvas coordinates, update retained/cached data only when model data changes, and let viewport changes apply as a cheap transform or a bounded Canvas draw pass.

**Tech Stack:** SwiftUI, AppKit, XCTest, `OSSignposter`, Instruments `SwiftUI` and `Time Profiler`, existing `CanvasViewportTransform`, existing `CanvasRenderPipeline`.

---

## Evidence Summary

The current slow pan is not caused by one visual effect in isolation. The exact root cause is that every pan tick mutates `@GestureState panOffset` in `Canvas/CanvasView.swift`, and that invalidates a broad SwiftUI transaction instead of applying a cheap retained transform.

The highest-confidence app-owned culprits are:

- `Canvas/CanvasRenderSnapshot.swift:224`: `CanvasRenderPipeline.snapshot(...)` rebuilds `CanvasRenderDataSignature` from every block and cluster every time the viewport changes, even when no block data changed.
- `Canvas/CanvasConnectionLinesLayer.swift:57-67`: `blockGeometrySignature` creates arrays of strings from every block on every body evaluation so `.onChange(of:)` can compare geometry.
- `Canvas/CanvasConnectionLinesLayer.swift:82-108`: every pan transforms cached canvas paths into new screen-space path dictionaries and rebuilds an invisible `ForEach` hit-test layer.
- `Core/Components/CosmoGlassPanel.swift:173-188`, `Canvas/CosmoBlockWrapper.swift:237-243`, `Canvas/CanvasClusterLayer.swift:142-148`, and `Navigation/MainView.swift:854-868`: every canvas block and cluster emits a moving `GeometryReader` preference for the glass scene system. During pan, those preferences change, get collected, sorted, capped, and can update sidebar material state.
- `Canvas/CanvasView.swift:417-418`: raw gesture pan also calls `publishSceneTintImmediately()`, so the canvas has both the preference-based glass-signal path and a manual scene-material path competing during pan.

The local sample captured during pan (`/tmp/cosmo-pan.sample.txt`) showed SwiftUI graph/layout work dominating the main thread. The strongest app-owned stack was `CanvasConnectionLinesLayer.body`, including `blockGeometrySignature`. The same sample also showed SwiftUI `GeometryReaderLayout` and `ZStack` layout work, consistent with the per-block/per-cluster glass signal preference path.

## File Structure

- Modify `Canvas/CanvasRenderSnapshot.swift`: add revision-gated render data caching and debug counters.
- Modify `Canvas/SpatialEngine.swift`: expose a block data revision that changes only when block model data changes, not when the viewport changes.
- Modify `AI/CanvasClusterEngine.swift`: expose a cluster data revision that changes only when cluster data changes.
- Modify `Canvas/CanvasView.swift`: pass data revisions into the render pipeline, stop doing pan-time glass work through two paths, and route canvas scene signals from existing transform math.
- Modify `Canvas/CanvasConnectionLinesLayer.swift`: remove string signatures, remove pan-time screen-path dictionaries, and replace per-edge SwiftUI hit-test views with one bounded hit-test layer.
- Modify `Canvas/CosmoBlockWrapper.swift`: allow canvas callers to suppress `GeometryReader`-based glass scene preferences.
- Modify `Canvas/CanvasClusterLayer.swift`: allow canvas callers to suppress `GeometryReader`-based glass scene preferences.
- Modify `Core/Components/CosmoGlassPanel.swift`: keep preference-based scene signals for non-canvas surfaces, but make canvas emission opt out.
- Modify `Navigation/MainView.swift`: continue using notification-driven canvas scene material, and avoid preference churn from canvas children.
- Create `Tests/CosmoOSTests/CanvasPanPerformanceTests.swift`: regression tests for revision-gated render data and numeric connection signatures.
- Create `Tests/CosmoOSTests/CanvasGlassSignalTests.swift`: regression tests for canvas-derived glass signals.

---

### Task 1: Add Pan Performance Regression Tests

**Files:**
- Create: `Tests/CosmoOSTests/CanvasPanPerformanceTests.swift`
- Modify: `Canvas/CanvasRenderSnapshot.swift`
- Modify: `Canvas/CanvasConnectionLinesLayer.swift`

- [ ] **Step 1: Write failing tests for viewport-only pan**

Create `Tests/CosmoOSTests/CanvasPanPerformanceTests.swift`:

```swift
import XCTest
@testable import CosmoOS

@MainActor
final class CanvasPanPerformanceTests: XCTestCase {
    func testRenderPipelineDoesNotRebuildDataSnapshotForViewportOnlyPan() {
        let blocks = Self.makeBlocks(count: 120)
        let pipeline = CanvasRenderPipeline()

        _ = pipeline.snapshot(
            blocks: blocks,
            dataRevision: 1,
            transform: CanvasViewportTransform(
                viewportSize: CGSize(width: 1440, height: 900),
                committedOffset: .zero
            ),
            userClusters: [],
            clusterRevision: 1,
            selectedBlockId: nil,
            selectedClusterId: nil,
            draggingClusterId: nil,
            resizingClusterId: nil
        )

        _ = pipeline.snapshot(
            blocks: blocks,
            dataRevision: 1,
            transform: CanvasViewportTransform(
                viewportSize: CGSize(width: 1440, height: 900),
                committedOffset: CGSize(width: -300, height: -120)
            ),
            userClusters: [],
            clusterRevision: 1,
            selectedBlockId: nil,
            selectedClusterId: nil,
            draggingClusterId: nil,
            resizingClusterId: nil
        )

        XCTAssertEqual(pipeline.debugCounters.dataSnapshotBuildCount, 1)
        XCTAssertEqual(pipeline.debugCounters.dataSignatureBuildCount, 1)
        XCTAssertEqual(pipeline.debugCounters.viewportSnapshotBuildCount, 2)
    }

    func testConnectionGeometryKeysAreNumericAndStableAcrossViewportPan() {
        let blocks = Self.makeBlocks(count: 40)

        let first = CanvasConnectionGeometryKey.keys(for: blocks)
        let second = CanvasConnectionGeometryKey.keys(for: blocks)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, blocks.count)
    }

    private static func makeBlocks(count: Int) -> [CanvasBlock] {
        (0..<count).map { index in
            CanvasBlock(
                id: "block-\(index)",
                position: CGPoint(x: CGFloat(index % 12) * 260, y: CGFloat(index / 12) * 210),
                size: CGSize(width: 220, height: 160),
                zIndex: index,
                entityType: .idea,
                entityId: Int64(index + 1),
                entityUuid: "uuid-\(index)",
                title: "Block \(index)"
            )
        }
    }
}
```

- [ ] **Step 2: Run tests and verify they fail for missing API**

Run:

```bash
xcodebuild test -project CosmoOS.xcodeproj -scheme CosmoOS -only-testing:CosmoOSTests/CanvasPanPerformanceTests
```

Expected: build fails because `dataRevision`, `clusterRevision`, `debugCounters`, and `CanvasConnectionGeometryKey` do not exist yet.

- [ ] **Step 3: Add render pipeline debug counters**

In `Canvas/CanvasRenderSnapshot.swift`, add near `CanvasRenderPipeline`:

```swift
struct CanvasRenderPipelineDebugCounters: Equatable {
    var dataSignatureBuildCount = 0
    var dataSnapshotBuildCount = 0
    var viewportSnapshotBuildCount = 0
}
```

Then add inside `CanvasRenderPipeline`:

```swift
#if DEBUG
private(set) var debugCounters = CanvasRenderPipelineDebugCounters()
#endif
```

Expose a non-`#if` read property if tests need to compile in the Xcode test configuration:

```swift
var debugCountersForTesting: CanvasRenderPipelineDebugCounters {
    #if DEBUG
    debugCounters
    #else
    CanvasRenderPipelineDebugCounters()
    #endif
}
```

Use one property name consistently in the test and implementation.

- [ ] **Step 4: Add numeric connection geometry key type**

In `Canvas/CanvasConnectionLinesLayer.swift`, above `CanvasConnectionLinesLayer`:

```swift
struct CanvasConnectionGeometryKey: Equatable {
    let entityUuid: String
    let positionX: Int
    let positionY: Int
    let width: Int
    let height: Int
    let scale: Int

    init(block: CanvasBlock) {
        self.entityUuid = block.entityUuid
        self.positionX = Int((block.position.x * 1000).rounded())
        self.positionY = Int((block.position.y * 1000).rounded())
        self.width = Int((block.size.width * 1000).rounded())
        self.height = Int((block.size.height * 1000).rounded())
        self.scale = Int((block.scale * 1000).rounded())
    }

    static func keys(for blocks: [CanvasBlock]) -> [CanvasConnectionGeometryKey] {
        blocks.map(CanvasConnectionGeometryKey.init)
    }
}
```

- [ ] **Step 5: Run tests again**

Run:

```bash
xcodebuild test -project CosmoOS.xcodeproj -scheme CosmoOS -only-testing:CosmoOSTests/CanvasPanPerformanceTests
```

Expected: still fails until Task 2 wires the revision-gated snapshot API.

### Task 2: Remove Render Data Signature Work From Pan Frames

**Files:**
- Modify: `Canvas/CanvasRenderSnapshot.swift`
- Modify: `Canvas/SpatialEngine.swift`
- Modify: `AI/CanvasClusterEngine.swift`
- Modify: `Canvas/CanvasView.swift`
- Test: `Tests/CosmoOSTests/CanvasPanPerformanceTests.swift`

- [ ] **Step 1: Add block revision to SpatialEngine**

In `Canvas/SpatialEngine.swift`, change the block storage to bump a revision when the block array changes:

```swift
@Published var blocks: [CanvasBlock] = [] {
    didSet {
        guard blocks != oldValue else { return }
        blocksRevision &+= 1
    }
}

@Published private(set) var blocksRevision: Int = 0
```

If `CanvasBlock` equality makes this too expensive for large arrays, replace the guard with unconditional increment. Viewport pan does not mutate `blocks`, so either option keeps pan off this path.

- [ ] **Step 2: Add cluster revision to CanvasClusterEngine**

In `AI/CanvasClusterEngine.swift`, change cluster storage to bump a revision:

```swift
@Published var clusters: [CanvasCluster] = [] {
    didSet { clusterRevision &+= 1 }
}

@Published var userClusters: [CanvasCluster] = [] {
    didSet { clusterRevision &+= 1 }
}

@Published private(set) var clusterRevision: Int = 0
```

- [ ] **Step 3: Change the render pipeline API**

In `Canvas/CanvasRenderSnapshot.swift`, replace the signature-driven invalidation with revision-driven invalidation:

```swift
@MainActor
final class CanvasRenderPipeline: ObservableObject {
    private var dataRevision: Int?
    private var clusterRevision: Int?
    private var dataSnapshot: CanvasRenderDataSnapshot = .empty
    private var viewportSignature: CanvasRenderViewportSignature?
    private var viewportSnapshot: CanvasRenderSnapshot = .empty

    #if DEBUG
    private(set) var debugCounters = CanvasRenderPipelineDebugCounters()
    #endif

    func snapshot(
        blocks: [CanvasBlock],
        dataRevision: Int,
        transform: CanvasViewportTransform,
        userClusters: [CanvasCluster],
        clusterRevision: Int,
        selectedBlockId: String?,
        selectedClusterId: UUID?,
        draggingClusterId: UUID?,
        resizingClusterId: UUID?
    ) -> CanvasRenderSnapshot {
        if self.dataRevision != dataRevision || self.clusterRevision != clusterRevision {
            #if DEBUG
            debugCounters.dataSignatureBuildCount += 1
            debugCounters.dataSnapshotBuildCount += 1
            #endif
            let signpost = CanvasPerformanceInstrumentation.signposter.beginInterval("render-data-snapshot")
            dataSnapshot = CanvasRenderDataSnapshot.build(blocks: blocks, userClusters: userClusters)
            self.dataRevision = dataRevision
            self.clusterRevision = clusterRevision
            viewportSignature = nil
            CanvasPerformanceInstrumentation.signposter.endInterval("render-data-snapshot", signpost)
        }

        let nextViewportSignature = CanvasRenderViewportSignature(
            transform: transform,
            selectedBlockId: selectedBlockId,
            selectedClusterId: selectedClusterId,
            draggingClusterId: draggingClusterId,
            resizingClusterId: resizingClusterId
        )

        if viewportSignature != nextViewportSignature {
            #if DEBUG
            debugCounters.viewportSnapshotBuildCount += 1
            #endif
            let signpost = CanvasPerformanceInstrumentation.signposter.beginInterval("render-viewport-snapshot")
            viewportSnapshot = dataSnapshot.renderSnapshot(
                transform: transform,
                selectedBlockId: selectedBlockId,
                selectedClusterId: selectedClusterId,
                draggingClusterId: draggingClusterId,
                resizingClusterId: resizingClusterId
            )
            viewportSignature = nextViewportSignature
            lastRenderableBlocks = viewportSnapshot.renderableBlocks
            hasResolvedSnapshot = true
            CanvasPerformanceInstrumentation.signposter.endInterval("render-viewport-snapshot", signpost)
        }

        return viewportSnapshot
    }
}
```

Remove `CanvasRenderDataSignature` if it is no longer used.

- [ ] **Step 4: Pass revisions from CanvasView**

In `Canvas/CanvasView.swift`, update `renderSnapshot(for:)`:

```swift
let snapshot = renderPipeline.snapshot(
    blocks: blocks,
    dataRevision: spatialEngine.blocksRevision,
    transform: viewportTransform,
    userClusters: clusterEngine.userClusters,
    clusterRevision: clusterEngine.clusterRevision,
    selectedBlockId: selectedBlockId,
    selectedClusterId: clusterEngine.selectedClusterId,
    draggingClusterId: draggingClusterId,
    resizingClusterId: clusterEngine.resizingClusterId
)
```

- [ ] **Step 5: Run the focused tests**

Run:

```bash
xcodebuild test -project CosmoOS.xcodeproj -scheme CosmoOS -only-testing:CosmoOSTests/CanvasPanPerformanceTests
```

Expected: `testRenderPipelineDoesNotRebuildDataSnapshotForViewportOnlyPan` passes.

### Task 3: Make Connection Rendering Viewport-Cheap

**Files:**
- Modify: `Canvas/CanvasConnectionLinesLayer.swift`
- Test: `Tests/CosmoOSTests/CanvasPanPerformanceTests.swift`

- [ ] **Step 1: Replace string geometry signature**

Replace:

```swift
private var blockGeometrySignature: [String] { ... }
```

with:

```swift
private var blockGeometrySignature: [CanvasConnectionGeometryKey] {
    CanvasConnectionGeometryKey.keys(for: blocks)
}
```

- [ ] **Step 2: Keep paths in canvas coordinates inside the visual renderer**

Change `CanvasConnectionVisualRenderer` to receive `cachedCanvasPaths` and `transform` instead of pre-transformed `screenPaths`.

The body should draw like this:

```swift
Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, _ in
    var canvasContext = context
    canvasContext.concatenate(transform.canvasToScreenAffineTransform())

    for edge in edges {
        guard let path = cachedCanvasPaths[edge.deduplicationKey] else { continue }
        let lineWidth = lineWidth(for: edge)
        canvasContext.stroke(path, with: .color(color(for: edge)), style: StrokeStyle(lineWidth: lineWidth))
    }
}
```

Keep line width visually identical by preserving the existing line-width math.

- [ ] **Step 3: Remove screen-path dictionaries from `body`**

Delete these pan-time allocations:

```swift
let screenPaths = cachedCanvasPaths.mapValues { $0.applying(xform) }
let screenEndpoints = cachedCanvasEndpoints.mapValues { ep in ... }
```

Compute screen endpoints only for the selected delete button, not for every edge every frame:

```swift
private func screenEndpoints(for edge: GraphEdge) -> (start: CGPoint, end: CGPoint)? {
    guard let endpoints = cachedCanvasEndpoints[edge.deduplicationKey] else { return nil }
    let xform = transform.canvasToScreenAffineTransform()
    return (endpoints.start.applying(xform), endpoints.end.applying(xform))
}
```

- [ ] **Step 4: Replace per-edge SwiftUI hit areas with one hit-test layer**

Add a single transparent hit-test layer that uses `cachedCanvasEndpoints` and `transform`:

```swift
CanvasConnectionHitTestLayer(
    edges: cachedVisibleEdges,
    endpoints: cachedCanvasEndpoints,
    transform: transform,
    hitTestWidth: Constants.hitTestWidth,
    onSelect: { edge in
        selectedEdgeKey = edge.deduplicationKey
    }
)
```

Implement it as `NSViewRepresentable` in the same file so pointer events are handled without a `ForEach` of invisible SwiftUI paths. Its `NSView.mouseDown(with:)` should convert the event location into canvas space and choose the closest segment within `hitTestWidth / transform.effectiveScale`.

- [ ] **Step 5: Run tests**

Run:

```bash
xcodebuild test -project CosmoOS.xcodeproj -scheme CosmoOS -only-testing:CosmoOSTests/CanvasPanPerformanceTests
```

Expected: focused tests pass. Also manually verify connection selection and delete button still work.

### Task 4: Remove Canvas Glass Preference Churn During Pan

**Files:**
- Modify: `Core/Components/CosmoGlassPanel.swift`
- Modify: `Canvas/CosmoBlockWrapper.swift`
- Modify: `Canvas/CanvasClusterLayer.swift`
- Modify: `Canvas/CanvasView.swift`
- Modify: `Navigation/MainView.swift`
- Create: `Tests/CosmoOSTests/CanvasGlassSignalTests.swift`

- [ ] **Step 1: Write a failing canvas glass-signal test**

Create `Tests/CosmoOSTests/CanvasGlassSignalTests.swift`:

```swift
import XCTest
@testable import CosmoOS

final class CanvasGlassSignalTests: XCTestCase {
    func testCanvasSceneSignalsComeFromViewportMath() {
        let block = CanvasBlock(
            id: "visible",
            position: CGPoint(x: 260, y: 260),
            size: CGSize(width: 300, height: 180),
            entityType: .image,
            entityId: 1,
            entityUuid: "visible-uuid",
            title: "Visible"
        )
        let transform = CanvasViewportTransform(
            viewportSize: CGSize(width: 1000, height: 800),
            committedOffset: .zero
        )

        let signals = CanvasSceneSignalBuilder.blockSignals(
            blocks: [block],
            transform: transform,
            viewportSize: transform.viewportSize,
            activeBlockDrag: ActiveCanvasDragState<String>(),
            draggingClusterId: nil,
            draggingClusterMemberUUIDs: [],
            clusterDragTranslation: .zero,
            consumedBlockUUIDs: []
        )

        XCTAssertEqual(signals.map(\.id), ["visible"])
        XCTAssertTrue(signals[0].rect.width > 1)
        XCTAssertTrue(signals[0].isNearSidebar)
    }
}
```

- [ ] **Step 2: Add opt-out to `cosmoGlassSceneSignal`**

In `Core/Components/CosmoGlassPanel.swift`, change the extension signature:

```swift
func cosmoGlassSceneSignal(
    id: String,
    source: CosmoGlassSceneSignalSource,
    color: Color,
    intensity: Double = 1,
    allowsDeepDiffusion: Bool = false,
    isEnabled: Bool = true
) -> some View {
    background {
        if isEnabled {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CosmoGlassSceneSignalPreferenceKey.self,
                    value: [
                        CosmoGlassSceneSignal(
                            id: id,
                            color: color,
                            rect: proxy.frame(in: .named(CosmoGlassSceneMaterial.coordinateSpaceName)),
                            intensity: intensity,
                            source: source,
                            allowsDeepDiffusion: allowsDeepDiffusion
                        )
                    ]
                )
            }
        }
    }
}
```

- [ ] **Step 3: Thread opt-out through block and cluster views**

In `Canvas/CosmoBlockWrapper.swift`, add:

```swift
var emitsGlassSceneSignal: Bool = true
```

Pass it to `.cosmoGlassSceneSignal(..., isEnabled: emitsGlassSceneSignal)`.

In `Canvas/CanvasClusterLayer.swift`, add:

```swift
var emitsGlassSceneSignals: Bool = true
```

Pass it to cluster `.cosmoGlassSceneSignal(..., isEnabled: emitsGlassSceneSignals)`.

- [ ] **Step 4: Disable preference emitters from the main canvas**

In `Canvas/CanvasView.swift`, pass `emitsGlassSceneSignals: false` to `CanvasClusterLayer`.

For block wrappers, thread `emitsGlassSceneSignal: false` through each concrete block view that uses `CosmoBlockWrapper`. If this is too broad for one task, start with `CanvasBlockStaticView` and add an `emitsGlassSceneSignal` parameter passed to the concrete block views.

- [ ] **Step 5: Keep canvas scene material visually equivalent**

Keep using `CanvasView.currentCanvasSceneMaterial(...)`, `visibleClusterSignals()`, and `visibleBlockSignals()` as the canvas source of truth. Leave non-canvas surfaces, such as Command Center and Inbox, on the existing preference mechanism.

In `Canvas/CanvasView.swift`, throttle raw-pan material publishing to at most 30 Hz unless the selected/near-sidebar signal set changes:

```swift
private let sceneTintPanThrottle: Duration = .milliseconds(33)
```

Use that interval in `publishSceneTintImmediately()` while `panOffset != .zero || spacePanOffset != .zero`.

- [ ] **Step 6: Run tests**

Run:

```bash
xcodebuild test -project CosmoOS.xcodeproj -scheme CosmoOS -only-testing:CosmoOSTests/CanvasGlassSignalTests
```

Expected: tests pass and canvas sidebar diffusion still changes as nearby blocks/clusters move across the sidebar edge.

### Task 5: Move Pan Toward a Retained Transform Path

**Files:**
- Modify: `Canvas/CanvasView.swift`
- Modify: `Canvas/CanvasBlockTransformHost.swift` if extracted, otherwise the `CanvasBlockTransformHost` section in `Canvas/CanvasView.swift`
- Modify: `Canvas/CanvasClusterLayer.swift`
- Modify: `Canvas/Drawing/CanvasDrawingsLayer.swift`
- Modify: `Canvas/CanvasConnectionLinesLayer.swift`

- [ ] **Step 1: Extract a content transform host**

Create a small view in `Canvas/CanvasView.swift` or a new `Canvas/CanvasContentTransformHost.swift`:

```swift
struct CanvasContentTransformHost<Content: View>: View {
    let transform: CanvasViewportTransform
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .transformEffect(transform.contentToScreenAffineTransform())
    }
}
```

- [ ] **Step 2: Stop baking viewport offset into every block position**

Change `CanvasBlockTransformHost` so the static block position is canvas-space only:

```swift
.position(
    x: block.position.x + dragOffset.width,
    y: block.position.y + dragOffset.height
)
```

Let `CanvasContentTransformHost` move and scale the whole group.

- [ ] **Step 3: Move cluster layer to the same content transform**

Change `CanvasClusterLayer` to accept canvas-space rects and remove `canvasOffset`, `scaledPanOffset`, and `effectiveScale` from its per-cluster positioning where possible. Keep `effectiveScale` only for UI details that truly need scale-aware sizing.

- [ ] **Step 4: Keep overlays that need screen space outside the transform**

Keep these as screen-space overlays:

- drawing gesture capture
- radial menu
- inspectors
- bottom controls
- connection delete button

The visual content and decorative connection lines should be canvas-space content.

- [ ] **Step 5: Manual visual check**

Verify all of these still align at scale `0.5`, `1.0`, and `2.0`:

- block positions
- cluster bounds
- connection lines
- drawing strokes
- lasso selection
- right-click menu placement
- minimap navigation

### Task 6: Verification Protocol

**Files:**
- No source changes unless failures reveal missing instrumentation.

- [ ] **Step 1: Run focused tests**

Run:

```bash
xcodebuild test -project CosmoOS.xcodeproj -scheme CosmoOS \
  -only-testing:CosmoOSTests/CanvasPanPerformanceTests \
  -only-testing:CosmoOSTests/CanvasGlassSignalTests \
  -only-testing:CosmoOSTests/CanvasViewportTransformTests \
  -only-testing:CosmoOSTests/CanvasRenderSnapshotTests
```

Expected: all selected tests pass.

- [ ] **Step 2: Run a clean build**

Run:

```bash
xcodebuild build -project CosmoOS.xcodeproj -scheme CosmoOS
```

Expected: build succeeds.

- [ ] **Step 3: Capture before/after pan samples**

For the before and after builds, run:

```bash
PID="$(pgrep -x CosmoOS | head -1)"
sample "$PID" 12 -file /tmp/cosmo-pan-after.sample.txt
```

During the 12 seconds, pan continuously across a dense thinkspace.

Expected after fixes:

- `CanvasConnectionLinesLayer.body` is no longer a visible top app-owned stack during pan.
- `CanvasConnectionLinesLayer.blockGeometrySignature` does not appear in pan samples.
- SwiftUI `GeometryReaderLayout` and preference update work from canvas glass signals is materially reduced.

- [ ] **Step 4: Capture SwiftUI hitches**

Run:

```bash
PID="$(pgrep -x CosmoOS | head -1)"
rm -rf /tmp/cosmo-swiftui-after.trace
xctrace record --template 'SwiftUI' --attach "$PID" --time-limit 12s --output /tmp/cosmo-swiftui-after.trace
xctrace export --input /tmp/cosmo-swiftui-after.trace --toc > /tmp/cosmo-swiftui-after-toc.xml
```

During the 12 seconds, pan continuously.

Expected after fixes:

- No repeated hitches over 16.67 ms during steady pan.
- No pan-time updates dominated by connection line body work.
- If 120 Hz is available on the display, steady pan should fit the 8.33 ms frame budget.

- [ ] **Step 5: Visual parity check**

Compare before/after at the same thinkspace and zoom levels:

- background parchment, aurora, and grain remain visually equivalent
- cluster glass surfaces remain visually equivalent
- block shadows, selected glow, and accent chips remain visually equivalent
- sidebar glass diffusion remains visually equivalent but may update at a lower rate during fast pan
- connections, drawings, and hit testing remain aligned

If visual parity fails, adjust only the rendering path for the failing element. Do not restore the per-frame GeometryReader preference path on canvas blocks/clusters.

## Stop Conditions

Stop and re-evaluate before broad refactors if Task 4 and Task 3 do not materially improve the pan sample. At that point, the remaining root cause is the larger architectural issue: SwiftUI is still asked to reposition too many child views during pan. The next move is to render the canvas content through retained AppKit/CALayer or Metal-backed layers while keeping SwiftUI for inspectors, controls, and block editing surfaces.
