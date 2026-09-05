// CosmoOS/Canvas/CanvasView.swift
// SwiftUI wrapper for Metal canvas with floating blocks

import SwiftUI
import GRDB
import UniformTypeIdentifiers

enum CanvasKeyboardShortcutPolicy {
    static let tabKeyCode: UInt16 = 48

    static func shouldToggleMinimap(
        keyCode: UInt16,
        eventType: NSEvent.EventType,
        isActive: Bool,
        isCommandKVisible: Bool,
        hasFocusedEntity: Bool,
        isTextInputFocused: Bool
    ) -> Bool {
        keyCode == tabKeyCode &&
            eventType == .keyDown &&
            isActive &&
            !isCommandKVisible &&
            !hasFocusedEntity &&
            !isTextInputFocused
    }
}

enum CanvasImageDropController {
    static let supportedTypes: [UTType] = [
        .fileURL,
        .image,
        .png,
        .jpeg,
        .tiff,
        .heic
    ]

    static func accepts(_ types: [UTType]) -> Bool {
        types.contains { type in
            type == .fileURL || type.conforms(to: .image)
        }
    }

    static func imageTitle(originalFilename: String?) -> String {
        guard let originalFilename, !originalFilename.isEmpty else { return "Image" }
        return URL(fileURLWithPath: originalFilename).deletingPathExtension().lastPathComponent
    }

    static func firstImage(from providers: [NSItemProvider]) async -> (data: Data, originalFilename: String?)? {
        for provider in providers {
            if let fileImage = await imageFromFileURL(provider) {
                return fileImage
            }
            if let directImage = await imageData(provider) {
                return directImage
            }
        }
        return nil
    }

    /// Every file URL in the drop, for the non-image → file-portal path.
    static func fileURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            let item = await loadItem(provider, typeIdentifier: UTType.fileURL.identifier)
            if let url = item as? URL {
                urls.append(url)
            } else if let url = item as? NSURL {
                urls.append(url as URL)
            } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                urls.append(url)
            }
        }
        return urls
    }

    private static func imageFromFileURL(_ provider: NSItemProvider) async -> (data: Data, originalFilename: String?)? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return nil }

        let item = await loadItem(provider, typeIdentifier: UTType.fileURL.identifier)
        let url: URL?
        if let loadedURL = item as? URL {
            url = loadedURL
        } else if let loadedURL = item as? NSURL {
            url = loadedURL as URL
        } else if let data = item as? Data {
            url = URL(dataRepresentation: data, relativeTo: nil)
        } else {
            url = nil
        }

        guard let url,
              let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
              contentType.conforms(to: .image),
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        return (data, url.lastPathComponent)
    }

    private static func imageData(_ provider: NSItemProvider) async -> (data: Data, originalFilename: String?)? {
        let typeIdentifiers = provider.registeredTypeIdentifiers
            .compactMap(UTType.init)
            .filter { $0.conforms(to: .image) }

        for type in typeIdentifiers {
            if let data = await loadData(provider, typeIdentifier: type.identifier) {
                return (data, provider.suggestedName)
            }
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
           let data = await loadData(provider, typeIdentifier: UTType.image.identifier) {
            return (data, provider.suggestedName)
        }

        return nil
    }

    private static func loadItem(_ provider: NSItemProvider, typeIdentifier: String) async -> NSSecureCoding? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                continuation.resume(returning: item)
            }
        }
    }

    private static func loadData(_ provider: NSItemProvider, typeIdentifier: String) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    /// First http(s) URL in the drop. File URLs are the image/portal path's
    /// business and never count as web links here. Falls back to URL-shaped
    /// plain text: a browser-pane drag arrives as text only (WebKit keeps
    /// page-authored drag types in its private custom-pasteboard format).
    static func firstWebURL(from providers: [NSItemProvider]) async -> String? {
        for provider in providers {
            guard provider.canLoadObject(ofClass: URL.self) else { continue }
            let url: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { value, _ in
                    continuation.resume(returning: value)
                }
            }
            if let url, url.scheme?.hasPrefix("http") == true { return url.absoluteString }
        }
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) else { continue }
            let text: String? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: NSString.self) { value, _ in
                    continuation.resume(returning: value as? String)
                }
            }
            if let text, let link = webLink(inDraggedText: text) { return link }
        }
        return nil
    }

    /// A text drop is a link ONLY when it is nothing but the link (the
    /// text/uri-list shape: URL lines, `#` comments) — prose that merely
    /// contains a URL is not a link drag.
    nonisolated static func webLink(inDraggedText text: String) -> String? {
        let candidates = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        guard candidates.count == 1, let candidate = candidates.first else { return nil }
        let lower = candidate.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://"),
              !candidate.contains(where: \.isWhitespace) else { return nil }
        return candidate
    }

    /// Whether the drop carries actual image content (registered image UTIs,
    /// or a file URL pointing at an image) — without loading payload bytes.
    static func carriesImagePayload(_ providers: [NSItemProvider]) async -> Bool {
        if providers.contains(where: { provider in
            provider.registeredTypeIdentifiers
                .compactMap(UTType.init)
                .contains { $0.conforms(to: .image) }
        }) {
            return true
        }
        for url in await fileURLs(from: providers) {
            if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
               type.conforms(to: .image) {
                return true
            }
        }
        return false
    }
}

// TEMPORARY DEBUG — remove once browser-pane→canvas drag-out is verified.
// NSLog is dead on this machine; print() goes nowhere in a Finder-launched
// app. Appends to /tmp/cosmo-drop-debug.log (sandbox is off).
enum CanvasDropDebugLog {
    static func note(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: "/tmp/cosmo-drop-debug.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}

/// Decides what an external drop becomes, before any payload bytes load. Pure
/// so the ladder is test-pinned: an Instagram tile drag carries BOTH the post
/// permalink and its thumbnail image and must become a post swipe — while a
/// random image dragged off a webpage (which also names its source URL) must
/// KEEP landing as a plain image block.
enum CanvasExternalDropRouter {
    enum Decision: Equatable {
        /// Route through the swipe front door; the returned atom's block
        /// lands at the drop point.
        case swipeCapture(url: String)
        /// No usable web link — the existing image / file-portal pipeline.
        case imageOrFile
    }

    nonisolated static func decision(webURL: String?, carriesImage: Bool) -> Decision {
        guard let webURL else { return .imageOrFile }
        switch SwipeIntakeRouter.resolveURL(webURL) {
        case .postURL:
            // A known-platform permalink IS the artifact; a thumbnail riding
            // the same drag is just its preview.
            return .swipeCapture(url: webURL)
        case .pageFromURL:
            // A bare link becomes a page swipe; an image drag that merely
            // names where it came from stays an image drop.
            return carriesImage ? .imageOrFile : .swipeCapture(url: webURL)
        default:
            return .imageOrFile
        }
    }
}

struct CanvasView: View {
    /// The thinkspace ID this canvas displays — passed directly to avoid race conditions
    let thinkspaceId: String?
    /// Whether this canvas is the active (visible) destination.
    /// When false, event monitors and interactive notification handlers are gated.
    var isActive: Bool = true

    // Mirror isActive into @State so NSEvent monitor closures capture a mutable reference
    // (let properties captured by closures would be stale after the struct is re-created)
    @State private var canvasIsActive = true

    @State private var spatialEngine = SpatialEngine()
    @State private var connectManager = DragToConnectManager()
    @State private var drawingState = DrawingStateManager()
    @State private var clusterEngine = CanvasClusterEngine()
    @State private var renderPipeline = CanvasRenderPipeline()
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var blockFrameTracker: CanvasBlockFrameTracker
    @EnvironmentObject var crossDragManager: CrossThinkspaceDragManager

    /// 120Hz viewport state — gestures write here so CanvasView's body never
    /// re-evaluates on a pan/zoom frame. See CanvasViewportEngine.
    @State private var viewportState = CanvasViewportEngine()

    @State private var canvasSize: CGSize = .zero
    @State private var selectedBlockId: String?
    /// The inline assistant's editable surface for the currently selected
    /// text-bearing canvas block (note / sticky note).
    @State private var selectedBlockEditableSurface: CanvasBlockEditableSurface?
    /// The thinkspace ITSELF as the assistant's surface — the canvas digest the
    /// pane scopes to whenever no text block is selected. View-owned (the
    /// registry holds it weakly, per the context-truth invariant).
    @State private var thinkspaceEditableSurface: ThinkspaceEditableSurface?
    @State private var dragOffset: CGSize = .zero

    // Canvas pan/zoom values live on viewportState (single source of truth).
    // These compatibility accessors keep the many existing commit sites
    // (jumps, zoom buttons, session restore) reading naturally; writes route
    // through the state object so the quantized mirror stays in sync.
    private var canvasOffset: CGSize {
        get { viewportState.committedOffset }
        nonmutating set { viewportState.setCommittedOffset(newValue) }
    }
    private var canvasScale: CGFloat {
        get { viewportState.committedScale }
        nonmutating set { viewportState.setCommittedScale(newValue) }
    }

    @State private var scrollWheelMonitor: Any?
    @State private var keyMonitor: Any?
    @State private var isSpaceHeld = false
    @State private var spaceDownAt: Date?

    // Places — saved camera positions (Cmd+D capture, Cmd+Opt+1…9 jump)
    @State private var canvasPlaces: [CanvasPlace] = []
    @State private var showPlaceCapture = false
    @State private var placeNameDraft = ""




    // Thinkspaces being prewarmed into the snapshot cache (hover-predicted)
    @State private var prewarmInFlight: Set<String> = []

    // Flows — Living Workflows (drawn cluster→output behaviors)
    @State private var canvasFlows: [CanvasFlow] = []
    @State private var selectedFlowId: String?
    @State private var flowVerbPickerClusterId: String?
    /// A note/sticky was dropped on a concept block — the merge drop card.
    @State private var conceptMergeDrop: ConceptMergeDropCandidate?
    @State private var conceptMergeHoverPreview: ActiveConceptMergeHoverPreview?
    @State private var runningFlowIds: Set<String> = []
    @State private var firingFlowIds: Set<String> = []
    private let minScale: CGFloat = 0.25
    private let maxScale: CGFloat = 3.0
    private let zoomSensitivity: CGFloat = 0.012  // For scroll wheel

    // PERFORMANCE: Block + cluster drags live on an @Observable so a drag
    // frame invalidates only the hosts that are actually moving — never this
    // body. See CanvasInteractionState.
    @State private var interactionState = CanvasInteractionState()
    @State private var canvasClusterDropPreview: ActiveCanvasClusterDropPreview?
    @State private var clusterResizeSession: ActiveClusterResizeSession?
    /// Bumped whenever resize preview geometries change so the render
    /// pipeline can keep its cheap revision-keyed path during a resize
    /// session instead of re-signing every block (metadata dicts included).
    @State private var clusterResizeRevision = 0

    /// Stable (start/end-only) read of the dragged cluster id for body-side
    /// consumers — never touches the per-frame translation.
    private var draggingClusterId: UUID? { interactionState.draggingClusterId }

    // Inbox blocks state
    @State private var inboxBlocks: [InboxViewBlock] = []

    // PERFORMANCE: Same drag model for inbox blocks.
    @State private var inboxBlockDragState = ActiveCanvasDragState<UUID>()

    // Thinkspace sidebar state
    @State private var isSidebarVisible = false
    private let thinkspaceManager = ThinkspaceManager.shared

    // Zoom/pan persistence
    @State private var zoomPanSaveTask: Task<Void, Never>?

    // Thinkspace switch transition
    @State private var thinkspaceSwitchTask: Task<Void, Never>?
    @State private var canvasContentOpacity: Double = 1.0
    @State private var canvasContentScale: CGFloat = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // PERF: Debounced frame tracker update — only needed for right-click hit testing
    @State private var frameUpdateTask: Task<Void, Never>?

    // Block UUIDs consumed by non-canvas clusters — computed live from clusterEngine state.
    // No caching needed; iterating a handful of clusters is negligible.

    // Crystallization heatmap
    @State private var showCrystallizationHeatmap = false
    @StateObject private var crystallizationEngine = CrystallizationEngine.shared

    // Lasso synthesis workspace
    @State private var showSynthesisWorkspace = false
    @State private var synthesisSourceBlockIds: [String] = []

    // Cluster/zone creation popover
    @State private var showClusterPopover = false
    @State private var clusterPopoverBlockIds: [String] = []
    @State private var clusterPopoverPosition: CGPoint = .zero
    @State private var zonePopoverRect: CGRect = .zero

    // Minimap overlay
    @State private var showMinimap = false

    // Space shell — the active view lives in SpaceViewStore, per space, so a
    // switch to another space never carries this one's view along. The two
    // chrome models are the row's state for the library and deep-dive views.
    @State private var libraryChrome = ThinkspaceLibraryChromeModel()
    @State private var deepDiveChrome = DeepDiveStudyChromeModel()
    @State private var materialsStore = SpaceMaterialsStore()
    @State private var showingMaterialPicker = false
    @State private var creatingSpaceItem: SpaceCompositionKind?
    @State private var libraryInventory: [ChildDoc] = []
    @State private var libraryLoadTask: Task<Void, Never>?
    /// Library folder currently open — hoisted here so the navigation trail
    /// can drive it (back/forward walks in and out of folders).
    @State private var librarySelectedFolderID: UUID?

    /// The view this space is showing. Resolved through the store so every
    /// space remembers its own; a nil thinkspace (never mounted today) is a canvas.
    private var activeSpaceView: SpaceView {
        thinkspaceId.map { SpaceViewStore.shared.activeView(for: $0) } ?? .canvas
    }

    /// The canvas world takes gestures, drops and right-clicks only while it
    /// is the active view — every other view is a surface laid over it.
    private var isCanvasViewActive: Bool {
        activeSpaceView == .canvas && !(thinkspaceId.map { SpaceWorkspaceStore.shared.isPresenting(in: $0) } ?? false)
    }

    // Notification observer management - prevent duplicate registrations
    @State private var observersRegistered = false
    @State private var notificationObserverTokens: [NSObjectProtocol] = []

    // PERF: Cached set of block IDs with media content — avoids string ops per block per render
    @State private var mediaContentBlockIds: Set<String> = []

    /// Full live transform — for handlers and gesture closures only. Reading
    /// this inside a body makes that body re-evaluate on every gesture frame;
    /// body-side consumers go through `CanvasWorldTransformHost` /
    /// `CanvasLiveTransformReader` or `viewportState.quantizedTransform`.
    private var viewportTransform: CanvasViewportTransform {
        viewportState.transform
    }

    /// Block revision with the cluster-resize preview tick folded in. During
    /// a resize session the preview geometries replace block frames, so every
    /// geometry consumer (render snapshot, connection lines) must rebuild per
    /// preview change — but never fall back to the expensive full-signature
    /// path (which copies every metadata dict).
    private var geometryEffectiveBlockRevision: Int {
        clusterResizeSession == nil
            ? spatialEngine.blocksDataRevision
            : spatialEngine.blocksDataRevision &+ (clusterResizeRevision &* 1_000_000_007)
    }

    private func renderSnapshot(for blocks: [CanvasBlock]) -> CanvasRenderSnapshot {
        let signpost = CanvasPerformanceInstrumentation.signposter.beginInterval("render-snapshot")
        let blockRevision = geometryEffectiveBlockRevision
        let snapshot = renderPipeline.snapshot(
            blocks: blocks,
            blockDataRevision: blockRevision,
            transform: viewportState.quantizedTransform,
            preloadInset: CanvasViewportSnapshotPolicy.preloadInset(
                viewportSize: canvasSize,
                isLiveGesture: viewportState.isLiveGesture,
                blockCount: blocks.count
            ),
            userClusters: clusterEngine.userClusters,
            clusterDataRevision: clusterEngine.userClustersDataRevision,
            selectedBlockId: selectedBlockId,
            selectedClusterId: clusterEngine.selectedClusterId,
            draggingClusterId: draggingClusterId,
            resizingClusterId: clusterEngine.resizingClusterId
        )
        CanvasPerformanceInstrumentation.signposter.endInterval("render-snapshot", signpost)
        return snapshot
    }

    // MARK: - Canvas Content (broken out for type-checking performance)

    private var canvasContent: some View {
        GeometryReader { _ in
            let currentRenderedBlocks = renderedBlocks
            let snapshot = renderSnapshot(for: currentRenderedBlocks)

            ZStack {
                // Background always fills the screen (infinite canvas)
                canvasBackground

                // World layer: content is built here (bucket-quantized
                // snapshot), but the live pan/zoom transform is applied by
                // the host so gesture frames never re-enter this body.
                CanvasWorldTransformHost(viewportState: viewportState) {
                    canvasWorldLayer(snapshot: snapshot)
                }
                .opacity(canvasContentOpacity)
                .scaleEffect(canvasContentScale)
                // NOTE: no .blur here — animating a Gaussian blur over the whole
                // world (every block carries a multi-shadow stack) forced an
                // offscreen render + filter pass per frame during switches.
                // The transition is opacity + scale transforms only.
                // In library mode the world is only a backdrop behind the
                // browser overlay — kill hit-testing so covered blocks can't
                // capture right-clicks and show another document's menu.
                .allowsHitTesting(isCanvasViewActive)
                .accessibilityElement(children: .contain)
                .accessibilityHidden(!isCanvasViewActive)

                // Screen-space layers (outside the scaled container to
                // prevent frame clipping at non-100% zoom). The reader hands
                // them the live transform so only their bodies track it.
                CanvasLiveTransformReader(viewportState: viewportState) { liveTransform in
                    // Drawing elements layer
                    CanvasDrawingsLayer(
                        drawingState: drawingState,
                        transform: liveTransform
                    )

                    // Drawing gesture capture
                    CanvasDrawingGestureLayer(
                        drawingState: drawingState,
                        transform: liveTransform
                    )
                }
                // These layers render WORLD content (ink) in screen space —
                // they must exit/enter with the world fade. Left at full
                // opacity, the outgoing space's drawings visibly hung over
                // the incoming one until its own drawings loaded.
                .opacity(canvasContentOpacity)
                .allowsHitTesting(isCanvasViewActive)
                .accessibilityHidden(!isCanvasViewActive)

                // The space's other views ride over the canvas world. The
                // GeometryReader window + clip keeps them LAYOUT-INERT: the
                // dossier's fixed columns must never propose a size to this
                // ZStack (the union would misplace every overlay below).
                GeometryReader { window in
                    SpaceViewHost(
                        thinkspaceId: thinkspaceId,
                        activeView: activeSpaceView,
                        deepDiveChrome: deepDiveChrome,
                        contentLeadingInset: crossDragManager.sidebarTotalWidth
                    ) {
                        thinkspaceLibraryView
                    }
                    .frame(width: window.size.width, height: window.size.height, alignment: .topLeading)
                    .clipped()
                }
                .allowsHitTesting(!isCanvasViewActive)
                .zIndex(2000)

                if isCanvasViewActive, !spatialEngine.isLoading, spatialEngine.blocks.isEmpty,
                   clusterEngine.clusters.isEmpty, drawingState.drawings.isEmpty {
                    SpaceCanvasWelcome(purpose: currentSpace?.purpose,
                        createNote: { addFromChromeRow(.note) }, addMaterials: { addFromChromeRow(.existing) })
                        .padding(.leading, crossDragManager.sidebarTotalWidth)
                        .zIndex(1999)
                }

                // Space+drag pan overlay — sits above everything so dragging
                // works even over blocks and clusters (like Figma hand tool)
                if isSpaceHeld && isCanvasViewActive {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { value in
                                    viewportState.setSpacePan(value.translation)
                                }
                                .onEnded { value in
                                    let scale = viewportState.transform.effectiveScale
                                    canvasOffset.width += value.translation.width / scale
                                    canvasOffset.height += value.translation.height / scale
                                    viewportState.setSpacePan(.zero)
                                }
                        )
                        .onAppear { NSCursor.openHand.push() }
                        .onDisappear {
                            NSCursor.pop()
                            viewportState.setSpacePan(.zero)
                        }
                }
            }
            // Accept blocks dragged out of cluster grid/list/board views, images
            // from Finder/desktop/apps, and web links dragged out of a browser pane.
            .onDrop(of: CanvasDropDelegate.supportedTypes, delegate: CanvasDropDelegate(
                // Never place things on the canvas from an overlay mode — a
                // drop released over the library must not fall through here.
                isEnabled: { [self] in isCanvasViewActive },
                screenToCanvas: { [self] screenPos in screenToCanvasPosition(screenPos) },
                onClusterDrop: { [self] blockUUID, canvasPosition in
                    handleClusterToCanvasDrop(blockUUID: blockUUID, canvasPosition: canvasPosition)
                },
                onExternalDrop: { [self] providers, canvasPosition in
                    handleCanvasExternalDrop(providers: providers, canvasPosition: canvasPosition)
                },
                onTrayDrop: { [self] entityUuid, canvasPosition in
                    placeTrayMember(entityUuid: entityUuid, at: canvasPosition)
                }
            ))
            .overlay(alignment: .bottomTrailing) {
                zoomIndicator
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
            }
            .overlay(alignment: .bottomLeading) {
                CanvasLiveTransformReader(viewportState: viewportState) { liveTransform in
                    CanvasPerformanceOverlay(
                        transform: liveTransform,
                        blockCount: spatialEngine.blocks.count,
                        visibleBlockCount: snapshot.visibleBlockCount,
                        activeDragLabel: interactionState.activeBlockDragId ?? draggingClusterId?.uuidString,
                        pipeline: renderPipeline
                    )
                }
            }
            .overlay(alignment: .topTrailing) {
                // Drawing tools + view layers + unified inspector — canvas-mode chrome
                // only; the library is a browsing surface and hides them.
                if isCanvasViewActive {
                    VStack(alignment: .trailing, spacing: 12) {
                        CanvasDrawingToolbar(drawingState: drawingState)
                            // Sub-tool dropdown overlays the inspector slot below
                            .zIndex(1)

                        // Unified inspector slot (block OR cluster)
                        canvasInspectorPanel
                    }
                    .padding(.trailing, 16)
                    // Below the space chrome row — the row owns the baseline.
                    .padding(.top, SpaceChromeMetrics.contentTopInset)
                    .animation(ProMotionSprings.gentle, value: selectedBlockId)
                    .animation(ProMotionSprings.gentle, value: clusterEngine.selectedClusterId)
                    .transition(.opacity.combined(with: .offset(y: -10)))
                }
            }
            // The space chrome row — last overlay, so it is frontmost.
            .overlay(alignment: .top) {
                spaceChromeRow
            }
            // Thinkspace sidebar trigger + overlay disabled — UnifiedSidebar + peek rail handle navigation
            // PERF: Debounced frame tracker updates — only needed for right-click hit testing,
            // so 100ms delay is imperceptible. Previously ran 60-120x/sec during pan/zoom.
            .onChange(of: spatialEngine.blocks.count) { _, _ in
                scheduleFrameUpdate()
                clusterEngine.scheduleRecompute(blocks: spatialEngine.blocks)
                clusterEngine.updateUserClusterBounds(blocks: spatialEngine.blocks)
                rebuildMediaContentCache()
                ThinkspaceCanvasSnapshotCache.shared.store(
                    blocks: spatialEngine.blocks,
                    zoomLevel: canvasScale,
                    panOffset: canvasOffset,
                    thinkspaceId: thinkspaceId,
                    userClusters: clusterEngine.userClusters
                )
            }
            .onChange(of: canvasOffset) { _, _ in
                rememberCurrentSessionViewport()
                scheduleFrameUpdate()
                debouncedSaveZoomPan()
            }
            .onChange(of: canvasScale) { _, _ in
                rememberCurrentSessionViewport()
                scheduleFrameUpdate()
                debouncedSaveZoomPan()
            }
            // Any block mutation (moves from sync/undo/organize ops, loads
            // that keep the same count) must re-track hit-test geometry —
            // count alone misses position-only changes.
            .onChange(of: spatialEngine.blocksDataRevision) { _, _ in
                scheduleFrameUpdate()
            }
            // Cluster view-mode/membership/bounds changes alter which blocks
            // are hit-testable and where the expanded-cluster zones sit.
            .onChange(of: clusterEngine.userClustersDataRevision) { _, _ in
                scheduleFrameUpdate()
            }
            // Any non-canvas view covers the canvas with its own surface —
            // the right-click monitor must stand down (mirrors the world
            // layer's allowsHitTesting gate).
            .onChange(of: activeSpaceView) { _, view in
                if view == .library {
                    refreshLibraryInventory()
                    libraryChrome.refocusBrowser()
                }
            }
            .onChange(of: isCanvasViewActive, initial: true) { _, active in
                blockFrameTracker.isCanvasSurfaceActive = active
            }
        }
        // NOTE: Removed .drawingGroup() from here - it was breaking async image loading
        // in ResearchCard, InboxViewBlockView thumbnails, etc. GPU acceleration is applied
        // selectively to specific components (GridPatternView, RadialMenuView) instead.
    }

    // MARK: - Space chrome row

    /// The one chrome row every space wears: sidebar + trail, identity, the
    /// view switcher (only this space's enabled views, ⌘1…⌘n), the active
    /// view's own controls, then ＋ and ⋯.
    /// Hidden while empty, and on any view but the canvas (the library lists
    /// the same members with an honest "not on canvas" mark).
    /// A tray member lands on the canvas (drag-out, "Place here", library
    /// "Place on Canvas"). ⌘Z sends it back to the tray.
    private func placeTrayMember(entityUuid: String, at position: CGPoint) {
        CanvasTrayDragSession.draggingEntityUuid = nil
        Task { @MainActor in
            guard let block = await spatialEngine.placeMember(entityUuid: entityUuid, at: position) else { return }
            CosmoUndoManager.shared.register(
                PlaceMemberAction(entityUuid: entityUuid, position: position, placedBlockId: block.id, spatialEngine: spatialEngine)
            )
            refreshLibraryInventory()
        }
    }

    private var spaceChromeRow: some View {
        SpaceChromeRow(
            thinkspace: currentSpace,
            activeView: activeSpaceView,
            renderableViews: thinkspaceId.map { SpaceViewStore.shared.renderableViews(for: $0) } ?? [.canvas],
            libraryFolder: librarySelectedFolderID.flatMap { id in
                thinkspaceLibrarySnapshot.folders.first { $0.id == id }
            },
            libraryChrome: libraryChrome,
            deepDiveChrome: deepDiveChrome,
            // Past the pinned sidebar when it's open; the row's own side
            // inset already clears the window edge when it's hidden.
            leadingInset: crossDragManager.sidebarTotalWidth > 0
                ? max(0, crossDragManager.sidebarTotalWidth - CosmoChromeMetrics.sideInset)
                : 0,
            actions: spaceChromeActions,
            onSelectView: { view in
                guard let thinkspaceId else { return }
                SpaceWorkspaceStore.shared.showRoot(view, in: thinkspaceId)
            },
            availableWidth: canvasSize.width
        )
        .sheet(isPresented: $showingMaterialPicker) {
            if let thinkspaceId {
                if let target = SpaceWorkspaceStore.shared.selectedItem(in: thinkspaceId) {
                    SpaceWorkspaceItemPicker(spaceID: thinkspaceId, target: target,
                        purpose: target.spaceCompositionKind == .group ? .members : .references)
                } else { SpaceMaterialPicker(spaceID: thinkspaceId) }
            }
        }
        .sheet(item: $creatingSpaceItem) { kind in
            if let thinkspaceId { SpaceWorkspaceCreateSheet(spaceID: thinkspaceId, kind: kind) }
        }

    }

    private var currentSpace: Thinkspace? {
        if let current = thinkspaceManager.currentThinkspace, current.id == thinkspaceId {
            return current
        }
        return thinkspaceManager.thinkspaces.first { $0.id == thinkspaceId }
    }

    private var spaceChromeActions: SpaceChromeActions {
        SpaceChromeActions(
            rename: { newName in
                guard let space = currentSpace else { return }
                Task { await thinkspaceManager.rename(space, to: newName) }
            },
            openSettings: { presentSpaceComposer(edit: true) },
            openAsPane: {
                guard let thinkspaceId else { return }
                NotificationCenter.default.post(
                    name: CosmoNotification.Navigation.openAsPane,
                    object: nil,
                    userInfo: ["thinkspaceId": thinkspaceId]
                )
            },
            pickEmoji: { presentSpaceComposer(edit: true) },
            recolor: { hex in
                guard let space = currentSpace else { return }
                Task { await thinkspaceManager.updateColor(space, to: hex) }
            },
            delete: {
                guard let space = currentSpace else { return }
                Task { await thinkspaceManager.delete(space) }
            },
            addAtCamera: { kind in addFromChromeRow(kind) },
            organizeWorkspace: { requestOrganizeWorkspace() },
            savePlace: { presentPlaceCapture() },
            showPlaces: { _ = jumpToPlace(atRecencyIndex: 0) },
            exitFolder: { exitLibraryFolderFromChrome() },
            renameFolder: { id, name in materialsStore.rename(id, to: name) },
            dropToRoot: { uuid in
                guard let folderID = librarySelectedFolderID else { return false }
                removeLibraryItemFromFolder(itemUUID: uuid, clusterID: folderID)
                return true
            },
            selectedSourceIDs: {
                if let thinkspaceId, SpaceWorkspaceStore.shared.isPresenting(in: thinkspaceId) {
                    return SpaceWorkspaceStore.shared.inquirySources(in: thinkspaceId)
                }
                return activeSpaceView == .library ? libraryChrome.inquirySourceIDs : activeSpaceView == .canvas ? spatialEngine.blocks.filter { $0.isSelected }.map(\.entityUuid) : []
            }
        )
    }

    private func presentSpaceComposer(edit: Bool) {
        guard let thinkspaceId else { return }
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.presentSpaceComposer,
            object: nil,
            userInfo: ["mode": edit ? "edit" : "create", "thinkspaceId": thinkspaceId]
        )
    }

    private func exitLibraryFolderFromChrome() {
        guard librarySelectedFolderID != nil, let thinkspaceId else { return }
        withAnimation(ProMotionSprings.focusTransition) { librarySelectedFolderID = nil }
        NavigationTrail.shared.recordArrival(
            .spaceView(thinkspaceId: thinkspaceId, view: .library),
            title: "\(currentSpace?.identityLabel ?? "Space") · Library",
            glyph: SpaceView.library.trailGlyph
        )
    }

    /// ＋ from the chrome row: create at the camera centre (canvas), or the
    /// same creation without a position for the other views — the block
    /// still lands on this space's canvas, the library shows it at once.
    private func addFromChromeRow(_ kind: SpaceAddKind) {
        switch kind {
        case .existing:
            showingMaterialPicker = true
        case .group:
            creatingSpaceItem = .group
        case .file:
            presentFilePortalOpenPanel(at: viewportCenterCanvasPoint())
        case .question:
            if let thinkspaceId { SpaceInquiryRequest.start(spaceID: thinkspaceId, sources: spaceChromeActions.selectedSourceIDs()) }
        default:
            let entityType: EntityType
            switch kind {
            case .note: entityType = .note
            case .idea: entityType = .idea
            case .task: entityType = .task
            case .content: entityType = .content
            case .stickyNote: entityType = .stickyNote
            case .deepDive: entityType = .deepDive
            default: return
            }
            if isCanvasViewActive {
                NotificationCenter.default.post(name: CosmoNotification.Canvas.createEntityAtPosition, object: nil,
                    userInfo: ["type": entityType, "position": viewportCenterCanvasPoint()])
            } else if let thinkspaceId, let atomType = AtomType(rawValue: entityType.rawValue) {
                Task {
                    do {
                        let atom = try await SpaceMembershipService.create(type: atomType, title: "Untitled \(kind.title.lowercased())", in: thinkspaceId)
                        refreshLibraryInventory()
                        NotificationCenter.default.post(name: CosmoNotification.Navigation.openBlockInFocusMode, object: nil,
                                                        userInfo: ["atomUUID": atom.uuid])
                    } catch { materialsStore.errorMessage = "Couldn't create the document. Try again." }
                }
            }
        }
    }

    /// The canvas point under the middle of the viewport — where ＋ creates.
    private func viewportCenterCanvasPoint() -> CGPoint {
        screenToCanvasPosition(CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2))
    }

    /// Hand the workspace to the inline assistant — its canvas-scoped shelf
    /// leads with the Organize Workspace skill once the pane is up.
    private func requestOrganizeWorkspace() {
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.openInlineAssistantPane,
            object: nil
        )
    }

    // MARK: - Zoom Indicator
    private var zoomIndicator: some View {
        CanvasLiveTransformReader(viewportState: viewportState) { liveTransform in
            let scale = liveTransform.effectiveScale
            Group {
                if scale != 1.0 && isCanvasViewActive {
                    HStack(spacing: 8) {
                        // Zoom level display
                        Text("\(Int(scale * 100))%")
                            .font(DS.subheadline.weight(.medium).monospacedDigit())
                            .foregroundStyle(DS.textSecondary)

                        // Reset zoom button
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                canvasScale = 1.0
                            }
                        } label: {
                            Image(systemName: "1.magnifyingglass")
                                .font(DS.footnote.weight(.semibold))
                                .foregroundStyle(DS.textSecondary)
                                .frame(width: 22, height: 22)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Reset zoom to 100 percent")
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(DS.glassInputFill, in: Capsule())
                    .overlay(Capsule().strokeBorder(DS.glassBorder, lineWidth: 1))
                    .clipShape(Capsule())
                    .dsFloatingShadow()
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .animation(ProMotionSprings.gentle, value: scale != 1.0)
            .animation(ProMotionSprings.gentle, value: activeSpaceView)
        }
    }

    private var selectedInspectableBlock: CanvasBlock? {
        guard let selectedBlockId,
              let block = spatialEngine.blocks.first(where: { $0.id == selectedBlockId }),
              !block.entityUuid.isEmpty,
              block.entityType != .cosmoAI else {
            return nil
        }
        // Sticky notes may not have a backing atom (entityId == -1) — still inspectable
        if block.entityType == .stickyNote { return block }
        // All other types require a backing atom
        guard block.entityId > 0 else { return nil }
        return block
    }

    // MARK: - Unified Inspector Panel (top-right, below toolbar)

    @ViewBuilder
    private var canvasInspectorPanel: some View {
        if let selectedBlock = selectedInspectableBlock {
            CanvasSelectionInspector(
                block: selectedBlock,
                currentThinkspaceId: spatialEngine.currentThinkspaceId,
                onClose: { clearSelectedBlock() },
                onFocusMode: {
                    NotificationCenter.default.post(
                        name: .enterFocusMode,
                        object: nil,
                        userInfo: ["type": selectedBlock.entityType, "id": selectedBlock.entityId]
                    )
                },
                onOpenAsPane: {
                    NotificationCenter.default.post(
                        name: CosmoNotification.Navigation.openAsPane,
                        object: nil,
                        userInfo: ["type": selectedBlock.entityType, "id": selectedBlock.entityId]
                    )
                },
                onConnectTo: {
                    // Placeholder — connect-to interaction
                },
                onAIAssist: {
                    // Hand the block to the inline assistant as a context mention
                    // rather than spawning a block — the bar opens focused with
                    // the pill already seated, and the pill is removable.
                    NotificationCenter.default.post(
                        name: CosmoNotification.Navigation.attachInlineAssistantContext,
                        object: nil,
                        userInfo: ["atomUuid": selectedBlock.entityUuid]
                    )
                },
                onSave: {
                    // Placeholder — save/bookmark action
                },
                onDuplicate: {
                    NotificationCenter.default.post(
                        name: CosmoNotification.Canvas.duplicateBlock,
                        object: nil,
                        userInfo: ["blockId": selectedBlock.id]
                    )
                },
                onRemoveFromCanvas: {
                    NotificationCenter.default.post(
                        name: .removeBlockFromCanvas,
                        object: nil,
                        userInfo: ["blockId": selectedBlock.id]
                    )
                    clearSelectedBlock()
                },
                onRemoveFromThinkspace: {
                    NotificationCenter.default.post(
                        name: .removeAtomFromThinkspace,
                        object: nil,
                        userInfo: ["blockId": selectedBlock.id]
                    )
                    clearSelectedBlock()
                },
                onDelete: {
                    NotificationCenter.default.post(
                        name: .deleteAtomEntirely,
                        object: nil,
                        userInfo: ["blockId": selectedBlock.id]
                    )
                    clearSelectedBlock()
                }
            )
            .transition(.opacity)
        } else if let clusterId = clusterEngine.selectedClusterId,
                  let cluster = clusterEngine.userClusters.first(where: { $0.id == clusterId }) {
            ClusterInspectorPanel(
                cluster: cluster,
                onChangeColor: { colorIndex in
                    clusterEngine.changeClusterColor(id: clusterId, colorIndex: colorIndex)
                },
                onChangeViewMode: { mode in
                    clusterEngine.setViewMode(for: clusterId, mode: mode, blocks: spatialEngine.blocks)
                },
                onChangeBoardGrouping: { grouping in
                    clusterEngine.setBoardGrouping(for: clusterId, grouping: grouping)
                },
                onDelete: {
                    clusterEngine.removeUserCluster(id: clusterId)
                    clusterEngine.selectCluster(nil)
                },
                onDismiss: {
                    clusterEngine.selectCluster(nil)
                }
            )
            .transition(.opacity)
        }
    }

    private var inboxBlocksLayer: some View {
        ForEach(inboxBlocks, id: \.id) { block in
            let blockId = block.id
            InboxViewBlockView(
                block: block,
                onDragStart: {
                    inboxBlockDragState.begin(id: blockId, translation: .zero)
                },
                onDrag: { translation in
                    inboxBlockDragState.begin(id: blockId, translation: CGSize(
                        width: translation.width / effectiveScale,
                        height: translation.height / effectiveScale
                    ))
                },
                onDragEnd: {
                    // Commit offset to actual position
                    if let index = inboxBlocks.firstIndex(where: { $0.id == blockId }),
                       inboxBlockDragState.activeId == blockId {
                        let offset = inboxBlockDragState.translation
                        inboxBlocks[index].x += offset.width
                        inboxBlocks[index].y += offset.height
                    }
                    // Clear drag state and persist
                    inboxBlockDragState.clear()
                    saveInboxBlockPositions()
                }
            )
            .position(
                x: block.x + inboxBlockDragState.translation(for: blockId).width,
                y: block.y + inboxBlockDragState.translation(for: blockId).height
            )
            .zIndex(inboxBlockDragState.activeId == blockId ? 1000 : Double(block.zIndex))
            .transition(.asymmetric(
                insertion: .scale(scale: 0.95).combined(with: .opacity),
                removal: .scale(scale: 0.98).combined(with: .opacity)
            ))
        }
    }

    private var canvasBackground: some View {
        ZStack {
            // Static visual background with GPU acceleration. The moving grid stays
            // outside this drawingGroup so pan/zoom does not re-rasterize the full
            // viewport-sized background on every gesture tick.
            ZStack {
                // Layer 1: Warm parchment canvas base
                DS.canvas
                    .ignoresSafeArea()

                // Layer 2: Subtle aurora gradient zones (2-3% opacity)
                ThinkspaceAuroraView()
                    .ignoresSafeArea()
            }
            .drawingGroup()

            // Layer 3: Infinite tiling grid — warm gray dots. Reads the live
            // transform through the reader so pan frames re-draw only the grid.
            CanvasLiveTransformReader(viewportState: viewportState) { liveTransform in
                GridPatternView(
                    transform: liveTransform
                )
            }
                .ignoresSafeArea()

            // Layer 4: Film grain overlay — static pre-rendered texture (zero per-frame cost)
            FilmGrainOverlay(opacity: 0.025)
                .ignoresSafeArea()

            // Pan gesture layer - transparent but captures hits
            panGestureBackground
        }
    }

    /// Clusters whose zone intersects the preload rect, plus any cluster the
    /// user is actively touching (drag/resize/selection/drop target — their
    /// rects may be stale mid-gesture or needed by chrome). Offscreen
    /// clusters unmount entirely: no glass material, no member content.
    private var renderableClusters: [CanvasCluster] {
        let visibility = CanvasVisibilityIndex(
            transform: viewportState.quantizedTransform,
            preloadInset: CanvasViewportSnapshotPolicy.preloadInset(
                viewportSize: canvasSize,
                isLiveGesture: viewportState.isLiveGesture,
                blockCount: spatialEngine.blocks.count
            )
        )
        return clusterEngine.allClusters.filter { cluster in
            cluster.id == draggingClusterId ||
                cluster.id == clusterEngine.resizingClusterId ||
                cluster.id == clusterEngine.selectedClusterId ||
                cluster.id == clusterEngine.dropTargetClusterId ||
                cluster.id == canvasClusterDropPreview?.targetClusterId ||
                visibility.intersects(cluster.boundingRect)
        }
    }

    private func canvasWorldLayer(snapshot: CanvasRenderSnapshot) -> some View {
        ZStack {
            // Cluster zones (auto-chunked + user-created, behind blocks)
            CanvasClusterLayer(
                clusters: renderableClusters,
                blocks: spatialEngine.blocks,
                // Quantized: label/zone thresholds update on 0.125 zoom
                // buckets during a live pinch (exact again at commit) so the
                // cluster subtree stops re-evaluating on every gesture frame.
                effectiveScale: viewportState.quantizedTransform.effectiveScale,
                dropTargetClusterId: clusterEngine.dropTargetClusterId,
                selectedClusterId: clusterEngine.selectedClusterId,
                resizingClusterId: clusterEngine.resizingClusterId,
                interaction: interactionState,
                onRenameCluster: { id, newName in
                    clusterEngine.renameUserCluster(id: id, to: newName)
                },
                onRemoveCluster: { id in
                    clusterEngine.removeUserCluster(id: id)
                },
                onSelectCluster: { id in
                    clusterEngine.selectCluster(id)
                    clearCanvasClusterDropPreview()
                    // Deselect any selected block, including its visual flag.
                    if id != nil { clearSelectedBlock() }
                },
                onDragCluster: { id, translation in
                    handleClusterDrag(clusterId: id, translation: translation)
                },
                onDragEndCluster: { id, translation in
                    handleClusterDragEnd(clusterId: id, translation: translation)
                },
                onResizeCluster: { id, delta, edge in
                    handleClusterResize(clusterId: id, delta: delta, edge: edge)
                },
                onResizeEndCluster: { id in
                    handleClusterResizeEnd(clusterId: id)
                },
                onChangeViewMode: { id, mode in
                    clusterEngine.setViewMode(for: id, mode: mode, blocks: spatialEngine.blocks)
                },
                onChangeBoardGrouping: { id, grouping in
                    clusterEngine.setBoardGrouping(for: id, grouping: grouping)
                },
                onChangeColor: { id, colorIndex in
                    clusterEngine.changeClusterColor(id: id, colorIndex: colorIndex)
                },
                onChangeSortOrder: { id, order in
                    clusterEngine.setSortOrder(for: id, order: order)
                },
                onToggleListExpand: { clusterId, blockUUID in
                    clusterEngine.toggleListExpand(clusterId: clusterId, blockUUID: blockUUID)
                },
                onBoardColumnDrop: { event in
                    clusterEngine.applyBoardDrop(event: event, blocks: &spatialEngine.blocks)
                },
                onClusterViewDrop: { event in
                    // Transfer block between clusters (grid/list drag-and-drop)
                    if let target = clusterEngine.userClusters.first(where: { $0.id == event.targetClusterId }),
                       target.viewMode == .canvas,
                       let blockIndex = spatialEngine.blocks.firstIndex(where: { $0.entityUuid == event.blockUUID }),
                       let containedPosition = clusterEngine.containedDropPosition(
                        blockSize: spatialEngine.blocks[blockIndex].size,
                        inCluster: event.targetClusterId
                       ) {
                        spatialEngine.blocks[blockIndex].position = containedPosition
                        spatialEngine.updateBlockPosition(spatialEngine.blocks[blockIndex].id, position: containedPosition)
                    }
                    let sourceClusterId = clusterEngine.allClusters
                        .first(where: { $0.blockUUIDs.contains(event.blockUUID) && $0.id != event.targetClusterId })?.id
                    clusterEngine.transferBlock(
                        blockUUID: event.blockUUID,
                        from: sourceClusterId,
                        to: event.targetClusterId,
                        blocks: spatialEngine.blocks
                    )
                },
                onOpenFocusMode: { uuid in
                    if let block = spatialEngine.blocks.first(where: { $0.entityUuid == uuid }),
                       block.entityId > 0 {
                        NotificationCenter.default.post(
                            name: .enterFocusMode,
                            object: nil,
                            userInfo: [
                                "type": block.entityType,
                                "id": block.entityId
                            ]
                        )
                    }
                },
                onMagnify: { magnification in
                    viewportState.setClusterMagnification(magnification)
                },
                onMagnifyEnd: { magnification in
                    let newScale = canvasScale * magnification
                    canvasScale = min(max(newScale, minScale), maxScale)
                    viewportState.setClusterMagnification(1.0)
                },
                expandedBlockUUIDs: clusterEngine.expandedBlockUUIDs
            )
            // Skip the whole cluster subtree unless its render inputs changed
            // (the action closures above are excluded from equality).
            .equatable()
            .accessibilityHidden(!isCanvasViewActive)

            // Knowledge connection lines — above zone fills, under every
            // card. Blocks consumed by list/board/grid clusters render inside
            // the cluster's own UI, not at their canvas positions, so they
            // are excluded (their lines would point at empty canvas).
            CanvasConnectionLinesLayer(
                blocks: connectionLineBlocks(snapshot: snapshot),
                geometryInvalidationKey: CanvasConnectionGeometryInvalidationKey(
                    blockDataRevision: geometryEffectiveBlockRevision,
                    clusterDataRevision: clusterEngine.userClustersDataRevision
                ),
                interaction: interactionState,
                effectiveScale: viewportState.quantizedTransform.effectiveScale,
                isActive: canvasIsActive,
                isLiveGesture: viewportState.isLiveGesture
            )

            // Flows — ink lines from clusters to their outputs (Living Workflows)
            FlowLineLayer(
                flows: canvasFlows,
                clusters: clusterEngine.allClusters,
                firingFlowIds: firingFlowIds,
                runningFlowIds: runningFlowIds,
                onSelectFlow: { flow in
                    withAnimation(ProMotionSprings.snappy) {
                        selectedFlowId = flow.uuid
                    }
                },
                onMoveFlowEnd: { flowUUID, end in
                    moveFlowEnd(flowUUID, to: end)
                },
                onAcceptProposal: { flow in
                    acceptFlowProposal(flow)
                },
                onDiscardProposal: { flow in
                    discardFlowProposal(flow)
                }
            )
            .equatable()

            canvasClusterDropPreviewLayer
            blocksLayer(snapshot: snapshot)
            conceptMergeHoverPreviewLayer
            inboxBlocksLayer
                .accessibilityHidden(!isCanvasViewActive)

            // Drag-to-connect overlay shares the same raw canvas coordinates as blocks.
            DragToConnectOverlay(
                connectManager: connectManager,
                blocks: spatialEngine.blocks
            )
        }
    }

    private var thinkspaceLibrarySnapshot: ThinkspaceLibrarySnapshot {
        let composition = thinkspaceId.flatMap { SpaceWorkspaceStore.shared.snapshots[$0] }
        let groupIDs = Set(composition?.metadataByUUID.filter { $0.value.kind == .group }.map(\.key) ?? [])
        let migrated = composition?.legacyGroupMapping ?? [:]
        return ThinkspaceLibrarySnapshot.make(
            blocks: spatialEngine.blocks.filter { !groupIDs.contains($0.entityUuid) },
            clusters: clusterEngine.userClusters,
            inventory: libraryInventory.filter { !groupIDs.contains($0.entityUuid) },
            materialGroups: materialsStore.groups.filter { migrated[$0.id.uuidString] == nil }
        )
    }

    private var thinkspaceLibraryView: some View {
        ThinkspaceLibraryModeView(
            thinkspaceName: thinkspaceManager.currentThinkspace?.name ?? "Thinkspace",
            thinkspaceId: thinkspaceManager.currentThinkspace?.id ?? "",
            snapshot: thinkspaceLibrarySnapshot,
            selectedFolderID: $librarySelectedFolderID,
            actions: ThinkspaceLibraryActions(
                openItem: { openLibraryItem($0) },
                revealOnCanvas: { revealLibraryItemOnCanvas($0) },
                fileIntoFolder: { fileLibraryItemIntoFolder(itemUUID: $0, clusterID: $1) },
                removeFromFolder: { removeLibraryItemFromFolder(itemUUID: $0, clusterID: $1) },
                renameFolder: { materialsStore.rename($0, to: $1) },
                recolorFolder: { materialsStore.recolor($0, to: $1) },
                deleteFolder: { materialsStore.delete($0) },
                renameItem: { item, newName in renameLibraryItem(item, to: newName) },
                deleteItem: { item in deleteLibraryItem(item) },
                placeOnCanvas: { placeLibraryItemOnCanvas($0) },
                removeFromSpace: { removeLibraryMember($0) },
                startInquiry: { ids in if let thinkspaceId { SpaceInquiryRequest.start(spaceID: thinkspaceId, sources: ids) } }
            ),
            chrome: libraryChrome
        )
        .overlay(alignment: .bottom) {
            if let error = materialsStore.errorMessage {
                HStack {
                    Text(error).font(DS.callout)
                    Button("Retry") { refreshLibraryInventory() }
                }.padding(DS.space16).background(DS.surface, in: .rect(cornerRadius: 14)).padding(DS.space24)
            }
        }
        .onAppear {
            refreshLibraryInventory()
        }
        .onChange(of: migratedLibraryFolder, initial: true) { _, atom in
            guard let atom, let thinkspaceId else { return }
            librarySelectedFolderID = nil
            SpaceWorkspaceStore.shared.open(atom, in: thinkspaceId)
        }
    }

    private var migratedLibraryFolder: Atom? {
        guard let thinkspaceId, let folderID = librarySelectedFolderID,
              let snapshot = SpaceWorkspaceStore.shared.snapshots[thinkspaceId],
              let uuid = snapshot.legacyGroupMapping[folderID.uuidString] else { return nil }
        return snapshot.atomsByUUID[uuid]
    }

    /// File an on-canvas library item into a cluster ("folder") via drag-and-drop.
    /// Reuses the same atomic membership mutation the canvas drop uses, so the change
    /// persists; the computed `thinkspaceLibrarySnapshot` then refreshes the grid.
    private func fileLibraryItemIntoFolder(itemUUID: String, clusterID: UUID) {
        materialsStore.file(itemUUID, in: clusterID)
    }

    private func removeLibraryItemFromFolder(itemUUID: String, clusterID: UUID) {
        materialsStore.remove(itemUUID, from: clusterID)
    }

    /// "Place on Canvas" — a member with no position gets a spot at the camera,
    /// then the canvas view opens on it.
    private func placeLibraryItemOnCanvas(_ item: ThinkspaceLibraryItem) {
        guard !item.isOnCanvas, let thinkspaceId else { return }
        SpaceWorkspaceStore.shared.showRoot(.canvas, in: thinkspaceId)
        let position = viewportCenterCanvasPoint()
        Task { @MainActor in
            guard let block = await spatialEngine.placeMember(entityUuid: item.entityUuid, at: position) else { return }
            CosmoUndoManager.shared.register(
                PlaceMemberAction(entityUuid: item.entityUuid, position: position, placedBlockId: block.id, spatialEngine: spatialEngine)
            )
            refreshLibraryInventory()
            flyCameraToBlock(atomUUID: item.entityUuid)
        }
    }

    /// "Reveal on Canvas" — flip back to the canvas view, then glide the camera to the block.
    private func revealLibraryItemOnCanvas(_ item: ThinkspaceLibraryItem) {
        guard item.isOnCanvas, let thinkspaceId else { return }
        SpaceWorkspaceStore.shared.showRoot(.canvas, in: thinkspaceId)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            flyCameraToBlock(atomUUID: item.entityUuid)
        }
    }

    private func refreshLibraryInventory() {
        guard let activeThinkspaceId = thinkspaceId ?? spatialEngine.currentThinkspaceId else {
            libraryInventory = []
            return
        }

        libraryLoadTask?.cancel()
        libraryLoadTask = Task { @MainActor in
            await materialsStore.load(spaceID: activeThinkspaceId)
            await thinkspaceManager.fetchNavigationData(for: activeThinkspaceId)
            guard !Task.isCancelled else { return }
            libraryInventory = thinkspaceManager.navigationCache[activeThinkspaceId]?.blockInventory ?? []
        }
    }

    private func openLibraryItem(_ item: ThinkspaceLibraryItem) {
        guard item.entityId > 0 else { return }
        if let thinkspaceId, let atom = SpaceWorkspaceStore.shared.snapshots[thinkspaceId]?.atomsByUUID[item.entityUuid],
           atom.spaceCompositionKind != nil {
            SpaceWorkspaceStore.shared.open(atom, in: thinkspaceId)
            return
        }
        if item.entityType == .note, let thinkspaceId {
            Task { @MainActor in
                do {
                    guard let atom = try await AtomRepository.shared.fetch(uuid: item.entityUuid) else { return }
                    SpaceWorkspaceStore.shared.open(atom, in: thinkspaceId)
                } catch { SpaceWorkspaceStore.shared.report(error, in: thinkspaceId) }
            }
            return
        }
        NotificationCenter.default.post(
            name: .enterFocusMode,
            object: nil,
            userInfo: [
                "type": item.entityType,
                "id": item.entityId
            ]
        )
    }

    /// Delete from the library: the atom is tombstoned (the app's standard
    /// restorable delete — it cascades to canvas_blocks on sync), and any
    /// in-memory canvas block leaves immediately so both views agree now.
    /// Atomless sticky/note blocks (entityId <= 0) have nothing to tombstone
    /// — removing the block IS the delete the user asked for.
    private func removeLibraryMember(_ item: ThinkspaceLibraryItem) {
        guard let thinkspaceId else { return }
        CosmoUndoManager.shared.register(DetachAtomAction(entityUuid: item.entityUuid, thinkspaceId: thinkspaceId, spatialEngine: spatialEngine))
        Task {
            await spatialEngine.removeAtomFromThinkspace(entityUuid: item.entityUuid, thinkspaceId: thinkspaceId)
            refreshLibraryInventory()
        }
    }

    private func deleteLibraryItem(_ item: ThinkspaceLibraryItem) {
        Task { @MainActor in
            if let block = spatialEngine.blocks.first(where: { $0.entityUuid == item.entityUuid }) {
                await spatialEngine.removeBlock(block.id)
            }
            if !item.entityUuid.isEmpty {
                do {
                    try await AtomRepository.shared.delete(uuid: item.entityUuid)
                    CosmoUndoManager.shared.register(InlineUndoAction(
                        actionDescription: "Delete material",
                        undo: { try? await AtomRepository.shared.restore(uuid: item.entityUuid); SpaceMembershipService.notifyMembersChanged() },
                        redo: { try? await AtomRepository.shared.delete(uuid: item.entityUuid); SpaceMembershipService.notifyMembersChanged() }
                    ))
                } catch { materialsStore.errorMessage = "Couldn't delete the material. Try again." }
            }
            refreshLibraryInventory()
        }
    }

    /// Rename from the library (Enter on a selected document): the atom title
    /// is the source of truth; an on-canvas block mirrors it immediately so
    /// the two views never disagree.
    private func renameLibraryItem(_ item: ThinkspaceLibraryItem, to newName: String) {
        if let blockIndex = spatialEngine.blocks.firstIndex(where: { $0.entityUuid == item.entityUuid }) {
            do {
                try spatialEngine.updateBlockMetadata(
                    blockID: spatialEngine.blocks[blockIndex].id, patch: ["title": newName]
                )
            } catch {
                PersistenceHealth.note(.writeFailure, context: "canvas.rename", detail: "\(error)")
            }
        }
        Task { @MainActor in
            guard var atom = try? await AtomRepository.shared.fetch(uuid: item.entityUuid) else { return }
            atom.title = newName
            atom.updatedAt = ISO8601.string(from: Date())
            _ = try? await AtomRepository.shared.update(atom)
            refreshLibraryInventory()
        }
    }

    @ViewBuilder
    private var canvasClusterDropPreviewLayer: some View {
        if let preview = canvasClusterDropPreview,
           let block = spatialEngine.blocks.first(where: { $0.id == preview.blockId }),
           let cluster = clusterEngine.userClusters.first(where: { $0.id == preview.targetClusterId }) {
            CanvasClusterDropPreviewHost(
                block: block,
                clusterColor: cluster.color,
                interaction: interactionState
            )
            .allowsHitTesting(false)
        }
    }

    /// Merge indication while a mergeable source hovers a concept block —
    /// ring + "Merge into …" pill on the target, same drop-preview grammar
    /// as clusters. The target block doesn't move during the hover, so this
    /// renders from @State identity only (no per-frame work).
    @ViewBuilder
    private var conceptMergeHoverPreviewLayer: some View {
        if let preview = conceptMergeHoverPreview,
           let target = spatialEngine.blocks.first(where: { $0.id == preview.conceptBlockID }) {
            ConceptMergeHoverPreviewView(
                conceptTitle: preview.conceptTitle,
                size: target.size
            )
            .position(target.position)
            .allowsHitTesting(false)
        }
    }

    private var renderedBlocks: [CanvasBlock] {
        guard clusterResizeSession != nil else { return spatialEngine.blocks }
        return spatialEngine.blocks.map(renderedBlock(for:))
    }

    /// Blocks eligible for connection-line endpoints: everything that renders
    /// at its canvas position. NOT viewport-culled — lines to offscreen blocks
    /// must keep their visible segment while panning — but cluster-consumed
    /// blocks are excluded, mirroring `CanvasBlockFrameTracker`'s invariant
    /// that geometry consumers agree with what the canvas actually renders.
    private func connectionLineBlocks(snapshot: CanvasRenderSnapshot) -> [CanvasBlock] {
        let consumed = snapshot.clusterConsumedBlockUUIDs
        guard !consumed.isEmpty else { return renderedBlocks }
        return renderedBlocks.filter { !consumed.contains($0.entityUuid) }
    }

    private func renderedBlock(for block: CanvasBlock) -> CanvasBlock {
        guard let geometry = clusterResizeSession?.previewGeometries[block.id] else {
            return block
        }

        var rendered = block
        rendered.position = geometry.position
        rendered.size = geometry.size
        return rendered
    }

    private func blocksLayer(snapshot: CanvasRenderSnapshot) -> some View {
        // Zoom LOD rides the environment: only views that READ the tier
        // re-render when it flips (at quantized 0.125 buckets), and the
        // Equatable host boundary stays untouched.
        blocksForEach(snapshot: snapshot)
            .environment(
                \.canvasBlockRenderTier,
                CanvasBlockRenderTier.tier(
                    forEffectiveScale: viewportState.quantizedTransform.effectiveScale
                )
            )
    }

    private func blocksForEach(snapshot: CanvasRenderSnapshot) -> some View {
        ForEach(snapshot.renderableBlocks, id: \.id) { block in
            CanvasBlockTransformHost(
                block: block,
                interaction: interactionState,
                isClusterMember: selectedClusterMemberUUIDs.contains(block.entityUuid),
                heatmapOpacity: heatmapOpacity(for: block),
                isCrossThinkspaceDragging: crossDragManager.isOverSidebar && crossDragManager.draggedBlock?.id == block.id,
                staticContent: CanvasBlockStaticView(
                    block: block,
                    isMediaContent: snapshot.mediaContentBlockIds.contains(block.id),
                    isViewportActive: snapshot.visibleBlockIds.contains(block.id),
                    spaceID: thinkspaceId
                ),
                onDragChanged: { translation in
                    if NSEvent.modifierFlags.contains(.option) {
                        let blockCanvasX = block.position.x
                        let blockCanvasY = block.position.y
                        if !connectManager.isActive {
                            connectManager.beginConnection(from: block, center: CGPoint(x: blockCanvasX, y: blockCanvasY))
                        }
                        connectManager.updateDrag(to: CGPoint(
                            x: blockCanvasX + translation.width,
                            y: blockCanvasY + translation.height
                        ))
                        connectManager.checkTarget(
                            blocks: spatialEngine.blocks
                        )
                    } else {
                        handleDragOptimized(blockId: block.id, translation: translation)
                    }
                },
                onDragEnded: { translation in
                    if connectManager.isActive {
                        if let targetId = connectManager.hoveredTargetBlockId,
                           let targetBlock = spatialEngine.blocks.first(where: { $0.id == targetId }) {
                            connectManager.completeConnection(targetBlock: targetBlock)
                        } else {
                            connectManager.cancel()
                        }
                    } else {
                        handleDragEndOptimized(blockId: block.id, translation: translation)
                    }
                },
                onDoubleTap: { openBlockInFocusMode(block) }
            )
            .equatable()
            // Accessibility visibility lives outside the cached card subtree.
            // Explicit thought-card elements must leave the tree while a
            // workspace covers them, without tearing down their editor state.
            .accessibilityHidden(!isCanvasViewActive)
        }
    }

    /// Block UUIDs consumed by non-canvas clusters (list/board) — hidden from normal blocksLayer
    private var clusterConsumedBlockUUIDs: Set<String> {
        Set(clusterEngine.userClusters
            .filter { $0.viewMode != .canvas }
            .flatMap(\.blockUUIDs))
    }

    /// Block hit testing only needs to be suppressed while the cluster itself is actively
    /// dragging/resizing, or when an alternate cluster mode consumes the member blocks.
    private var selectedClusterMemberUUIDs: Set<String> {
        guard let clusterId = clusterEngine.selectedClusterId,
              let cluster = clusterEngine.userClusters.first(where: { $0.id == clusterId }) else {
            return []
        }

        let clusterGestureIsActive = draggingClusterId == clusterId || clusterEngine.resizingClusterId == clusterId
        guard cluster.viewMode != .canvas || clusterGestureIsActive else { return [] }
        return Set(cluster.blockUUIDs)
    }

    // blockView(for:) has been extracted into CanvasBlockContainer (see bottom of file)
    // for Equatable-based SwiftUI diffing — only changed blocks re-render.


    /// PERF: Rebuild the media content cache when blocks change
    private func rebuildMediaContentCache() {
        var ids = Set<String>()
        for block in spatialEngine.blocks where block.entityType == .research {
            let url = (block.metadata["url"] ?? "").lowercased()
            if url.contains("youtube") || url.contains("youtu.be") ||
               url.contains("instagram") || url.contains("tiktok") ||
               block.metadata["isSwipeFile"] == "true" {
                ids.insert(block.id)
            }
        }
        // Idempotent: a switch calls this after the authoritative apply; an
        // unchanged set must not invalidate the canvas body again.
        if ids != mediaContentBlockIds {
            mediaContentBlockIds = ids
        }
    }

    /// Block ids whose canvas-persisted content actually changed between the
    /// applied cached snapshot and the authoritative fetch — the targeted
    /// resync notification carries these so only affected note/sticky views
    /// re-run their load, instead of every mounted editor on every switch.
    static func changedCanvasBlockIds(
        previous: [CanvasBlock],
        fetched: [CanvasBlock]
    ) -> Set<String> {
        var previousById: [String: CanvasBlock] = [:]
        previousById.reserveCapacity(previous.count)
        for block in previous {
            previousById[block.id] = block
        }
        var changed: Set<String> = []
        for block in fetched {
            guard let old = previousById[block.id] else {
                changed.insert(block.id)
                continue
            }
            if old.metadata != block.metadata
                || old.title != block.title
                || old.entityUuid != block.entityUuid
                || old.entityId != block.entityId {
                changed.insert(block.id)
            }
        }
        return changed
    }

    @discardableResult
    private func applyCachedThinkspaceSnapshot(for thinkspaceId: String?) -> Bool {
        guard let cached = ThinkspaceCanvasSnapshotCache.shared.entry(for: thinkspaceId) else {
            return false
        }

        spatialEngine.blocks = cached.blocks
        // The engine context must move WITH the displayed blocks. If it lags
        // until the authoritative fetch lands, any save in the overlap window
        // re-homes blocks into the previous thinkspace (they vanish from theirs).
        // This also makes the rapid A→B→A revert guard compare against the
        // actually-applied snapshot, not a stale context.
        spatialEngine.currentDocumentType = "home"
        spatialEngine.currentDocumentId = 0
        spatialEngine.currentThinkspaceId = thinkspaceId
        clusterEngine.clusters = []
        clusterEngine.userClusters = cached.userClusters
        clusterEngine.selectedClusterId = nil
        let viewport = openingSessionViewport(for: thinkspaceId)
        canvasScale = viewport.zoomLevel
        canvasOffset = viewport.panOffset
        mediaContentBlockIds = cached.mediaContentBlockIds
        return true
    }

    private func prepareEmptyThinkspaceSwitchState(for thinkspaceId: String?) {
        spatialEngine.blocks = []
        // Keep the engine context in lockstep with the displayed (empty) state —
        // see applyCachedThinkspaceSnapshot.
        spatialEngine.currentDocumentType = "home"
        spatialEngine.currentDocumentId = 0
        spatialEngine.currentThinkspaceId = thinkspaceId
        clusterEngine.clusters = []
        clusterEngine.userClusters = []
        clusterEngine.selectedClusterId = nil
        drawingState.drawings = []
        applySessionThinkspaceViewport(for: thinkspaceId)
    }

    private func applySessionThinkspaceViewport(for thinkspaceId: String?) {
        let viewport = openingSessionViewport(for: thinkspaceId)
        canvasScale = viewport.zoomLevel
        canvasOffset = viewport.panOffset
        loadPlaces(for: thinkspaceId)
    }

    private func openingSessionViewport(for thinkspaceId: String?) -> CanvasSessionViewportState {
        CanvasSessionViewportStore.shared.openingViewport(
            for: thinkspaceId,
            persisted: persistedViewport(for: thinkspaceId)
        )
    }

    private func persistedViewport(for thinkspaceId: String?) -> CanvasSessionViewportState? {
        guard let tsId = thinkspaceId,
              let ts = thinkspaceManager.thinkspaces.first(where: { $0.id == tsId }) else {
            return nil
        }

        return CanvasSessionViewportState(
            zoomLevel: CGFloat(ts.zoomLevel),
            panOffset: ts.panOffset
        )
    }

    private func rememberCurrentSessionViewport(for thinkspaceId: String? = nil) {
        CanvasSessionViewportStore.shared.remember(
            CanvasSessionViewportState(zoomLevel: canvasScale, panOffset: canvasOffset),
            for: thinkspaceId ?? spatialEngine.currentThinkspaceId ?? self.thinkspaceId
        )
    }

    private func refreshLibraryInventoryForThinkspaceSwitch() {
        if !libraryInventory.isEmpty {
            libraryInventory = []
        }
        if librarySelectedFolderID != nil {
            librarySelectedFolderID = nil
        }
        // Idempotent — this runs twice per switch; the model loads prefs once.
        if let activeId = thinkspaceId ?? spatialEngine.currentThinkspaceId {
            libraryChrome.activate(thinkspaceId: activeId)
        }
        if activeSpaceView == .library {
            refreshLibraryInventory()
        }
    }

    /// Warm the snapshot cache for a thinkspace the user is likely to enter
    /// next (hovered sidebar row, most-recent spaces). Read-only:
    /// `fetchBlocksSnapshot` and `clustersSnapshot` touch no engine state, so
    /// this can run any time without disturbing the live canvas. By the time
    /// the user clicks, `applyCachedThinkspaceSnapshot` hits and entry is
    /// instant.
    private func prewarmThinkspaceSnapshot(_ targetId: String) {
        guard targetId != spatialEngine.currentThinkspaceId,
              ThinkspaceCanvasSnapshotCache.shared.entry(for: targetId) == nil,
              !prewarmInFlight.contains(targetId) else { return }
        prewarmInFlight.insert(targetId)
        Task { @MainActor in
            defer { prewarmInFlight.remove(targetId) }
            guard let blocks = await spatialEngine.fetchBlocksSnapshot(
                for: "home", documentId: 0, thinkspaceId: targetId
            ) else { return }
            let clusters = await CanvasClusterEngine.clustersSnapshot(
                thinkspaceId: targetId, blocks: blocks
            )
            // A real visit may have stored an authoritative entry meanwhile —
            // never clobber it with prefetched data.
            guard ThinkspaceCanvasSnapshotCache.shared.entry(for: targetId) == nil else { return }
            let viewport = openingSessionViewport(for: targetId)
            ThinkspaceCanvasSnapshotCache.shared.store(
                blocks: blocks,
                zoomLevel: viewport.zoomLevel,
                panOffset: viewport.panOffset,
                thinkspaceId: targetId,
                userClusters: clusters
            )
        }
    }

    private func animateThinkspaceContentIn() async {
        canvasContentScale = 0.97

        // Give freshly-swapped block views one frame to mount while content is
        // still invisible, so the enter spring animates an already-built tree
        // instead of paying view-creation cost on its first frame.
        try? await Task.sleep(for: .milliseconds(17))
        guard !Task.isCancelled else { return }

        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : ProMotionSprings.worldEnter) {
            canvasContentOpacity = 1.0
            canvasContentScale = 1.0
        }
    }

    private var panGestureBackground: some View {
        Color.clear
            .contentShape(Rectangle())
            .allowsHitTesting(drawingState.toolMode == .select && isCanvasViewActive)
            .onTapGesture(count: 2) {
                handleEmptyCanvasDoubleClick()
            }
            .onTapGesture {
                // Only deselect the previously selected block (not the whole array)
                if let prevId = selectedBlockId,
                   let prevIndex = spatialEngine.blocks.firstIndex(where: { $0.id == prevId }) {
                    spatialEngine.blocks[prevIndex].isSelected = false
                }
                selectedBlockId = nil
                clusterEngine.selectCluster(nil)
                drawingState.clearSelection()

                // Post notification AFTER state change is complete
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .blurAllBlocks, object: nil)
                }
            }
            .gesture(
                // Pan gesture — regular (not simultaneous) so ScrollViews inside
                // clusters and block drag gestures take priority over canvas panning.
                // Tap-to-deselect is a separate .onTapGesture and is unaffected.
                // Writes go to viewportState (not @GestureState) so each tick
                // invalidates only the transform hosts, never this body.
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        // Store raw translation - will be scaled when applied
                        viewportState.setGesturePan(value.translation)
                    }
                    .onEnded { value in
                        // Scale by 1/effectiveScale so panning feels natural at any zoom level
                        // When zoomed out, a 100px drag should move the canvas 100px on screen
                        let scale = viewportState.transform.effectiveScale
                        canvasOffset.width += value.translation.width / scale
                        canvasOffset.height += value.translation.height / scale
                        viewportState.setGesturePan(.zero)
                    }
            )
            .simultaneousGesture(
                // Trackpad pinch-to-zoom gesture
                MagnifyGesture()
                    .onChanged { value in
                        viewportState.setGestureMagnification(value.magnification)
                    }
                    .onEnded { value in
                        // Commit pinch scale without extra animation. The gesture
                        // magnification resets to 1.0 at end; animating this commit can
                        // produce a visible snap/bounce in drawing overlays.
                        let newScale = canvasScale * value.magnification
                        canvasScale = min(max(newScale, minScale), maxScale)
                        viewportState.setGestureMagnification(1.0)
                    }
            )
    }

    // Computed property for effective zoom level during gesture
    private var effectiveScale: CGFloat {
        viewportTransform.effectiveScale
    }

    // Scaled pan offset - divide by zoom so panning feels natural at any zoom level
    private var scaledPanOffset: CGSize {
        viewportTransform.scaledPanOffset
    }

    /// Convert screen coordinates to canvas coordinates (accounting for zoom and pan)
    /// Use this when creating blocks from screen positions (like right-click)
    private func screenToCanvasPosition(_ screenPos: CGPoint) -> CGPoint {
        viewportTransform.screenToCanvas(screenPos)
    }

    private func addCanvasObserver(
        forName name: Notification.Name,
        object: Any? = nil,
        queue: OperationQueue? = .main,
        activeOnly: Bool = false,
        using block: @escaping (Notification) -> Void
    ) {
        let handler: (Notification) -> Void
        if activeOnly {
            handler = { [self] notification in
                guard canvasIsActive else { return }
                block(notification)
            }
        } else {
            handler = block
        }
        let token = NotificationCenter.default.addObserver(
            forName: name,
            object: object,
            queue: queue,
            using: handler
        )
        notificationObserverTokens.append(token)
    }

    private func removeCanvasObservers() {
        for token in notificationObserverTokens {
            NotificationCenter.default.removeObserver(token)
        }
        notificationObserverTokens.removeAll()
        observersRegistered = false
    }

    private func updateCanvasSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0, canvasSize != size else { return }
        canvasSize = size
        viewportState.setViewportSize(size)
        scheduleFrameUpdate()
    }

    // MARK: - Body

    /// The canvas without an explicit thinkspace is the home space — one
    /// stable id so the assistant surface never goes nil.
    private var resolvedThinkspaceSurfaceId: String {
        thinkspaceId ?? "home"
    }

    var body: some View {
        GeometryReader { geometry in
            canvasContent
                .cosmoSurfaceKeyWindowActivation(
                    surfaceID: ThinkspaceEditableSurface.surfaceID(forThinkspaceId: resolvedThinkspaceSurfaceId)
                )
                .onAppear {
                    updateCanvasSize(geometry.size)
                    canvasIsActive = isActive

                    // Right-click hit-testing converts the click point with
                    // the live transform at click time — never a stale
                    // precomputed snapshot.
                    blockFrameTracker.liveTransformProvider = { [weak viewportState] in
                        viewportState?.transform
                    }
                    blockFrameTracker.isCanvasSurfaceActive = (isCanvasViewActive)

                // Register context provider for global Cosmo window. A hidden
                // launch prewarm must not claim the context — the user is
                // looking at another destination; registration happens when
                // the canvas becomes active instead.
                if isActive {
                    let provider = CanvasContextProvider(spatialEngine: spatialEngine, thinkspaceId: thinkspaceId)
                    CosmoWindowViewModel.shared.updateContext(provider: provider)
                    registerThinkspaceSurface()
                }

                // Load persisted blocks from database for this ThinkSpace
                Task { @MainActor in
                    let cachedSnapshotApplied = applyCachedThinkspaceSnapshot(for: thinkspaceId)

                    await spatialEngine.loadBlocks(for: "home", documentId: 0, thinkspaceId: thinkspaceId)
                    if cachedSnapshotApplied {
                        // Mounted editors may hold cached-snapshot text — re-sync from DB.
                        NotificationCenter.default.post(name: .canvasBlocksDidResync, object: nil)
                    }
                    CosmoWindowViewModel.shared.refreshContext()
                    drawingState.loadDrawings(thinkspaceId: thinkspaceId)
                    rebuildMediaContentCache()

                    // First visit in an app session opens at 100%; later visits
                    // restore the viewport remembered in this session.
                    applySessionThinkspaceViewport(for: thinkspaceId)

                    // Load user-created clusters — compute, then re-verify this
                    // initial load still owns the canvas before assigning. This
                    // task has NO cancellation link to thinkspace switches: a
                    // user who clicks another space during the initial load
                    // otherwise gets this space's clusters stamped onto it, and
                    // the snapshot store below would poison the cache with
                    // mixed state under the wrong key.
                    let initialClusters = await clusterEngine.computeUserClusters(
                        thinkspaceId: thinkspaceId,
                        blocks: spatialEngine.blocks
                    )
                    guard spatialEngine.currentThinkspaceId == thinkspaceId else { return }
                    if let initialClusters {
                        clusterEngine.userClusters = initialClusters
                    }
                    ThinkspaceCanvasSnapshotCache.shared.store(
                        blocks: spatialEngine.blocks,
                        zoomLevel: canvasScale,
                        panOffset: canvasOffset,
                        thinkspaceId: thinkspaceId,
                        userClusters: clusterEngine.userClusters
                    )

                    // Non-critical work trails the interactive path so the
                    // first presented frame never competes with it. A hidden
                    // launch prewarm additionally yields to remaining launch
                    // work before running it.
                    if !canvasIsActive {
                        try? await Task.sleep(for: .seconds(1))
                    }
                    if await repairLegacyBlocksIfNeeded() > 0,
                       spatialEngine.currentThinkspaceId == thinkspaceId {
                        // Repairs rewrote entity ids — don't leave a stale
                        // snapshot for the next visit. Same ownership guard:
                        // the launch prewarm slept 1s above, plenty of time
                        // for a real visit to have moved the canvas elsewhere.
                        ThinkspaceCanvasSnapshotCache.shared.store(
                            blocks: spatialEngine.blocks,
                            zoomLevel: canvasScale,
                            panOffset: canvasOffset,
                            thinkspaceId: thinkspaceId,
                            userClusters: clusterEngine.userClusters
                        )
                    }
                    refreshLibraryInventory()
                }

                // Load persisted inbox blocks
                loadInboxBlockPositions()

                // Register notification observers only once
                guard !observersRegistered else {
                    if isActive {
                        CanvasPendingPlacementQueue.shared.markCanvasReady()
                    }
                    return
                }
                observersRegistered = true

                // Listen for voice-driven placement commands
                addCanvasObserver(
                    forName: .placeBlocksOnCanvas,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handlePlaceBlocks(notification: notification, canvasSize: canvasSize)
                }

                // A ⌘K result dropped anywhere outside the palette is routed here
                // by the window-level catcher with its window-space release point;
                // convert it to canvas space and place exactly as a canvas drop.
                addCanvasObserver(
                    forName: CosmoNotification.NodeGraph.commandKAtomDropOnCanvas,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    guard isCanvasViewActive,
                          let uuids = notification.userInfo?["uuids"] as? [String],
                          let x = notification.userInfo?["x"] as? CGFloat,
                          let y = notification.userInfo?["y"] as? CGFloat else { return }
                    let canvasPosition = screenToCanvasPosition(CGPoint(x: x, y: y))
                    handleCommandKAtomDrop(uuids: uuids, canvasPosition: canvasPosition)
                }

                // Listen for move commands
                addCanvasObserver(
                    forName: .moveCanvasBlocks,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleMoveBlocks(notification: notification)
                }

                // Listen for arrangement commands (MAGICAL!)
                addCanvasObserver(
                    forName: .arrangeCanvasBlocks,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleArrangeBlocks(notification: notification, canvasSize: canvasSize)
                }

                // Listen for Cosmo AI block creation
                addCanvasObserver(
                    forName: CosmoNotification.Canvas.createCosmoAIBlock,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleCreateCosmoAIBlock(notification: notification)
                }

                // Listen for Note block creation
                addCanvasObserver(
                    forName: .createNoteBlock,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleCreateNoteBlock(notification: notification)
                }

                // Listen for block selection (from CosmoBlockWrapper)
                addCanvasObserver(
                    forName: CosmoNotification.Canvas.blockSelected,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    if let blockId = notification.userInfo?["blockId"] as? String {
                        handleTap(blockId: blockId)
                    }
                }

                // Fly the camera to frame a block (agent navigation: "show me where X is")
                addCanvasObserver(
                    forName: CosmoNotification.Canvas.focusBlock,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    if let atomUUID = notification.userInfo?["atomUUID"] as? String {
                        flyCameraToBlock(atomUUID: atomUUID)
                    }
                }

                // Listen for block removal
                addCanvasObserver(
                    forName: .removeBlock,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleRemoveBlock(notification: notification)
                }

                // Listen for "remove from canvas" (unplace; stays a member)
                addCanvasObserver(
                    forName: .removeBlockFromCanvas,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleRemoveBlockFromCanvas(notification: notification)
                }

                // Membership rows changed anywhere (Inbox routing, ⌘K filing,
                // promotion, sync) — the tray re-counts.
                addCanvasObserver(
                    forName: .canvasBlocksChanged,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] _ in
                        }

                // Listen for "remove from thinkspace" (detach all placements)
                addCanvasObserver(
                    forName: .removeAtomFromThinkspace,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleRemoveAtomFromThinkspace(notification: notification)
                }

                // Listen for full atom delete (→ Recently Deleted)
                addCanvasObserver(
                    forName: .deleteAtomEntirely,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleDeleteAtomEntirely(notification: notification)
                }

                // Listen for generic entity creation (from radial menu)
                addCanvasObserver(
                    forName: CosmoNotification.Canvas.createEntityAtPosition,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleCreateEntityAtPosition(notification: notification)
                }

                // Listen for calendar window opening
                addCanvasObserver(
                    forName: .openCalendarWindow,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleOpenCalendarWindow(notification: notification)
                }

                // Listen for idea board block creation (from Command-K)
                addCanvasObserver(
                    forName: Notification.Name("createIdeaBoardBlock"),
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    let clientUUID = notification.userInfo?["clientUUID"] as? String ?? ""
                    let clientName = notification.userInfo?["clientName"] as? String ?? "Client"
                    let position = screenToCanvasPosition(
                        CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                    )
                    let block = CanvasBlock(
                        position: position,
                        size: CGSize(width: 280, height: 400),
                        entityType: .ideaBoard,
                        entityId: -1,
                        entityUuid: UUID().uuidString,
                        title: clientName,
                        metadata: [
                            "clientUUID": clientUUID,
                            "clientName": clientName
                        ]
                    )
                    Task {
                        await spatialEngine.addBlock(block, persist: true)
                    }
                }

                // Listen for inbox block creation
                addCanvasObserver(
                    forName: CosmoNotification.Canvas.createInboxBlock,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleCreateInboxBlock(notification: notification)
                }

                addCanvasObserver(
                    forName: CosmoNotification.Canvas.refreshThinkspacePlacements,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleRefreshThinkspacePlacements(notification: notification)
                }

                // Listen for inbox block closure
                addCanvasObserver(
                    forName: CosmoNotification.Canvas.closeInboxBlock,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleCloseInboxBlock(notification: notification)
                }

                // Listen for inbox block position updates (drag)
                addCanvasObserver(
                    forName: CosmoNotification.Canvas.updateInboxBlockPosition,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleUpdateInboxBlockPosition(notification: notification)
                }

                // Listen for inbox block size updates (resize)
                addCanvasObserver(
                    forName: CosmoNotification.Canvas.updateInboxBlockSize,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleUpdateInboxBlockSize(notification: notification)
                }

                // Listen for block content updates (saves to database)
                addCanvasObserver(
                    forName: .updateBlockContent,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleUpdateBlockContent(notification: notification)
                }

                // Listen for block metadata updates (e.g., Note color)
                addCanvasObserver(
                    forName: .updateBlockMetadata,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleUpdateBlockMetadata(notification: notification)
                }
                
                // Listen for block entity linkage updates (freeform → atom-backed)
                addCanvasObserver(
                    forName: .updateBlockEntity,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleUpdateBlockEntity(notification: notification)
                }

                // Listen for block size updates (e.g., Note resize)
                addCanvasObserver(
                    forName: .updateBlockSize,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleUpdateBlockSize(notification: notification)
                }
                
                // Listen for save block size (after resize ends)
                addCanvasObserver(
                    forName: .saveBlockSize,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleSaveBlockSize(notification: notification)
                }

                // Listen for research block creation (from URL capture)
                addCanvasObserver(
                    forName: .createResearchBlock,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleCreateResearchBlock(notification: notification)
                }

                addCanvasObserver(
                    forName: .closeSelectedBlock,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] _ in
                    if let blockId = selectedBlockId {
                        removeBlockSafely(blockId)
                    }
                }

                addCanvasObserver(
                    forName: .openBlockInFocusMode,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] _ in
                    handleOpenSelectedBlockInFocusMode()
                }

                // Smart block reference handlers (by ID)
                addCanvasObserver(
                    forName: .deleteSpecificBlock,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleDeleteSpecificBlock(notification: notification)
                }

                addCanvasObserver(
                    forName: .duplicateBlock,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleDuplicateBlock(notification: notification)
                }

                addCanvasObserver(
                    forName: .moveBlockToTime,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleMoveBlockToTime(notification: notification)
                }

                // Smart block reference handlers (by content search)
                addCanvasObserver(
                    forName: .deleteBlockByContent,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleDeleteBlockByContent(notification: notification)
                }

                addCanvasObserver(
                    forName: .duplicateBlockByContent,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleDuplicateBlockByContent(notification: notification)
                }

                addCanvasObserver(
                    forName: .moveBlockByContentToTime,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleMoveBlockByContentToTime(notification: notification)
                }

                // Listen for entity placement from voice commands (LLM-First)
                addCanvasObserver(
                    forName: .placeEntityOnCanvas,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handlePlaceEntityOnCanvas(notification: notification)
                }

                addCanvasObserver(
                    forName: Notification.Name("com.cosmo.space.placeCreatedItem"),
                    object: nil, queue: .main, activeOnly: true
                ) { [self] notification in
                    guard let uuid = notification.userInfo?["atomUUID"] as? String,
                          let destination = notification.userInfo?["spaceID"] as? String,
                          destination == thinkspaceId,
                          destination == spatialEngine.currentThinkspaceId else { return }
                    let position = PositionResolver.shared.findNonOverlappingPosition(
                        near: viewportCenterCanvasPoint(), existingBlocks: spatialEngine.blocks, canvasSize: canvasSize)
                    Task { @MainActor in
                        guard await spatialEngine.placeMember(entityUuid: uuid, at: position) != nil else {
                            SpaceWorkspaceStore.shared.report(SpaceCompositionError.invalidPlacement, in: destination)
                            return
                        }
                        refreshLibraryInventory()
                    }
                }

                addCanvasObserver(
                    forName: Notification.Name("com.cosmo.space.importFiles"),
                    object: nil, queue: .main, activeOnly: true
                ) { [self] notification in
                    guard notification.userInfo?["spaceID"] as? String == thinkspaceId else { return }
                    presentFilePortalOpenPanel(at: viewportCenterCanvasPoint())
                }

                // Listen for block resize commands
                addCanvasObserver(
                    forName: .resizeSelectedBlock,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleResizeSelectedBlock(notification: notification)
                }

                // Listen for opening entity on canvas (from Cmd+K)
                addCanvasObserver(
                    forName: .openEntityOnCanvas,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handleOpenEntityOnCanvas(notification: notification)
                }

                // Listen for ambient pull-to-canvas
                addCanvasObserver(
                    forName: CosmoNotification.Canvas.pullAmbientToCanvas,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    handlePullAmbientToCanvas(notification: notification)
                }

                // Listen for lasso-enclosed blocks — show choice popover (cluster vs synthesize)
                addCanvasObserver(
                    forName: CosmoNotification.Canvas.lassoEnclosedBlocks,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    Task { @MainActor in
                        if let blockIds = notification.userInfo?["blockIds"] as? [String], blockIds.count >= 2 {
                            // Compute center position of lassoed blocks for popover placement
                            let lassoBlocks = spatialEngine.blocks.filter { blockIds.contains($0.id) }
                            let avgX = lassoBlocks.map(\.position.x).reduce(0, +) / max(CGFloat(lassoBlocks.count), 1)
                            let avgY = lassoBlocks.map(\.position.y).reduce(0, +) / max(CGFloat(lassoBlocks.count), 1)
                            let screenPoint = viewportTransform.canvasToScreen(CGPoint(x: avgX, y: avgY))

                            clusterPopoverBlockIds = blockIds
                            clusterPopoverPosition = CGPoint(x: screenPoint.x, y: screenPoint.y - 60)
                            withAnimation(ProMotionSprings.snappy) {
                                showClusterPopover = true
                            }
                            drawingState.toolMode = .select
                        }
                    }
                }

                // Listen for zone drawn — show zone creation popover
                addCanvasObserver(
                    forName: CosmoNotification.Canvas.zoneDrawn,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    Task { @MainActor in
                        if let rectX = notification.userInfo?["rectX"] as? CGFloat,
                           let rectY = notification.userInfo?["rectY"] as? CGFloat,
                           let rectW = notification.userInfo?["rectW"] as? CGFloat,
                           let rectH = notification.userInfo?["rectH"] as? CGFloat,
                           let popoverX = notification.userInfo?["popoverX"] as? CGFloat,
                           let popoverY = notification.userInfo?["popoverY"] as? CGFloat {
                            zonePopoverRect = CGRect(x: rectX, y: rectY, width: rectW, height: rectH)
                            clusterPopoverBlockIds = []  // Empty = zone mode
                            clusterPopoverPosition = CGPoint(x: popoverX, y: popoverY)
                            withAnimation(ProMotionSprings.snappy) {
                                showClusterPopover = true
                            }
                            drawingState.toolMode = .select
                        }
                    }
                }

                // Listen for cluster creation from context menu
                addCanvasObserver(
                    forName: CosmoNotification.Canvas.createClusterFromSelection,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    Task { @MainActor in
                        if let blockIds = notification.userInfo?["blockIds"] as? [String],
                           let position = notification.userInfo?["position"] as? CGPoint {
                            clusterPopoverBlockIds = blockIds
                            clusterPopoverPosition = position
                            withAnimation(ProMotionSprings.snappy) {
                                showClusterPopover = true
                            }
                        }
                    }
                }

                // Approved canvas-plan cluster ops (thinkspace copilot) — same
                // engine paths as the manual cluster flows, no popover.
                addCanvasObserver(
                    forName: CosmoNotification.Canvas.createClusterFromPlan,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    Task { @MainActor in
                        guard planTargetMatchesThisCanvas(notification.userInfo),
                              let name = notification.userInfo?["name"] as? String,
                              let blockUUIDs = notification.userInfo?["blockUUIDs"] as? [String] else { return }
                        applyPlannedClusterCreation(
                            name: name,
                            blockUUIDs: blockUUIDs,
                            intent: notification.userInfo?["intent"] as? String
                        )
                    }
                }

                addCanvasObserver(
                    forName: CosmoNotification.Canvas.moveBlocksToCluster,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    Task { @MainActor in
                        guard planTargetMatchesThisCanvas(notification.userInfo),
                              let clusterName = notification.userInfo?["clusterName"] as? String,
                              let blockUUIDs = notification.userInfo?["blockUUIDs"] as? [String] else { return }
                        applyPlannedClusterMove(clusterName: clusterName, blockUUIDs: blockUUIDs)
                    }
                }

                // After ALL of a plan's operations landed: clusters were derived
                // from wherever their members already sat, so freshly organized
                // regions routinely overlap. Resolve deterministically — packed
                // close, never overlapping. (The Task hop queues this behind the
                // per-operation tasks above, which use the same FIFO executor.)
                addCanvasObserver(
                    forName: CosmoNotification.Canvas.canvasPlanDidApply,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    Task { @MainActor in
                        guard planTargetMatchesThisCanvas(notification.userInfo) else { return }
                        resolvePlannedClusterOverlaps()
                    }
                }

                // Listen for cross-thinkspace block drop (block moved from another thinkspace)
                addCanvasObserver(
                    forName: CosmoNotification.Canvas.crossThinkspaceDropBlock,
                    object: nil,
                    queue: .main
                ) { [self] notification in
                    nonisolated(unsafe) let notification = notification
                    Task { @MainActor in
                        guard let targetThinkspaceId = notification.userInfo?["thinkspaceId"] as? String,
                              let blockId = notification.userInfo?["blockId"] as? String else { return }

                        guard let currentThinkspaceId = spatialEngine.currentThinkspaceId,
                              targetThinkspaceId == currentThinkspaceId else {
                            // Source canvas: the row was re-homed in the DB — drop the
                            // block from memory immediately so a save here can't act
                            // on a block that now belongs to another thinkspace.
                            spatialEngine.blocks.removeAll { $0.id == blockId }
                            return
                        }

                        let positionSpace = notification.userInfo?["positionSpace"] as? String
                        let screenPosition = notification.userInfo?["screenPosition"] as? CGPoint

                        // Reload blocks to pick up the transferred block
                        await spatialEngine.loadBlocks(for: "home", documentId: 0, thinkspaceId: currentThinkspaceId)
                        rebuildMediaContentCache()

                        applySessionThinkspaceViewport(for: currentThinkspaceId)

                        if positionSpace == "screen", let screenPosition {
                            let canvasPosition = screenToCanvasPosition(screenPosition)
                            spatialEngine.updateBlockPosition(blockId, position: canvasPosition)
                        }
                    }
                }

                // Listen for Cmd+V paste (routed via CosmoCommands pasteboard group)
                addCanvasObserver(
                    forName: .performCanvasPaste,
                    object: nil,
                    queue: .main,
                    activeOnly: true
                ) { [self] _ in
                    guard !appState.isCommandKVisible else { return }
                    Task { await handleCanvasPaste() }
                }

                // MARK: - Scroll Wheel Zoom (Mouse)
                // Set up scroll wheel event monitor for smooth mouse zoom
                // Uses Option+scroll for zoom to avoid conflicting with normal scrolling
                CanvasEscapeCoordinator.shared.register(id: "canvas-overlays") {
                    dismissTopCanvasOverlay()
                }
                scrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [self] event in
                    guard canvasIsActive else { return event }
                    let isOptionHeld = event.modifierFlags.contains(.option)

                    if isOptionHeld {
                        // Use scrollingDeltaY for zoom
                        let delta = event.scrollingDeltaY
                        if abs(delta) > 0.1 {  // Threshold to avoid micro-zooms
                            // A wheel streak rides the LIVE gesture path:
                            // writing the committed scale per tick re-ran the
                            // whole canvas body on every tick (momentum
                            // included). The engine commits once when the
                            // streak goes quiet.
                            let zoomFactor = 1.0 + (delta * zoomSensitivity)
                            viewportState.applyWheelZoomTick(factor: zoomFactor) { finalScale in
                                canvasScale = finalScale
                            }

                            // Consume the event when zooming
                            return nil
                        }
                    }
                    return event
                }

                // MARK: - Space+Drag Pan (Hand Tool)
                // Track space bar press to enable drag-to-pan over any element
                keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [self] event in
                    guard canvasIsActive else { return event }
                    guard !MainKeyboardShortcutPolicy.reservesDocumentKeyboard(in: event.window) else { return event }
                    if CanvasKeyboardShortcutPolicy.shouldToggleMinimap(
                        keyCode: event.keyCode,
                        eventType: event.type,
                        isActive: canvasIsActive,
                        isCommandKVisible: appState.isCommandKVisible,
                        hasFocusedEntity: appState.focusedEntity != nil,
                        isTextInputFocused: isTextInputFocused(in: event.window)
                    ) {
                        if !event.isARepeat {
                            withAnimation(ProMotionSprings.snappy) {
                                showMinimap.toggle()
                            }
                        }
                        return nil
                    }
                    if event.keyCode == 49 { // space bar
                        let pressed = event.type == .keyDown
                        if pressed != isSpaceHeld {
                            isSpaceHeld = pressed
                            if pressed { spaceDownAt = Date() }
                        }
                        // Quick tap (held space pans; a tap peeks) with a
                        // selected block → Quick Look it.
                        if !pressed,
                           let downAt = spaceDownAt,
                           Date().timeIntervalSince(downAt) < 0.3,
                           let blockId = selectedBlockId,
                           let block = spatialEngine.blocks.first(where: { $0.id == blockId }),
                           block.entityId > 0,
                           !isTextInputFocused(in: event.window),
                           !appState.isCommandKVisible,
                           appState.focusedEntity == nil {
                            NotificationCenter.default.post(
                                name: CosmoNotification.Navigation.peekEntity,
                                object: nil,
                                userInfo: ["type": block.entityType, "id": block.entityId]
                            )
                            return nil
                        }
                    }
                    // Cmd+D — save the current view as a Place
                    if event.type == .keyDown,
                       event.keyCode == 2,  // D key
                       event.modifierFlags.contains(.command),
                       !event.modifierFlags.contains(.shift),
                       !event.modifierFlags.contains(.option),
                       !isTextInputFocused(in: event.window),
                       !appState.isCommandKVisible,
                       appState.focusedEntity == nil {
                        presentPlaceCapture()
                        return nil
                    }
                    // Cmd+Opt+1…9 — jump to a Place by recency (canvas view only:
                    // a camera flight under the library is invisible)
                    if event.type == .keyDown,
                       event.modifierFlags.contains(.command),
                       event.modifierFlags.contains(.option),
                       isCanvasViewActive,
                       !isTextInputFocused(in: event.window) {
                        let digitKeyCodes: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]
                        if let digit = digitKeyCodes[event.keyCode],
                           jumpToPlace(atRecencyIndex: digit - 1) {
                            return nil
                        }
                    }
                    return event
                }

                // Observers are live — consume any placements that were queued
                // while the canvas wasn't mounted (replaces the 0.3s timer race).
                if isActive {
                    CanvasPendingPlacementQueue.shared.markCanvasReady()
                }
            }
            .onDisappear {
                viewportState.resetLiveGesture()
                rememberCurrentSessionViewport()
                // Clean up event monitors
                if let monitor = scrollWheelMonitor {
                    NSEvent.removeMonitor(monitor)
                    scrollWheelMonitor = nil
                }
                if let monitor = keyMonitor {
                    NSEvent.removeMonitor(monitor)
                    keyMonitor = nil
                }
                isSpaceHeld = false
                CanvasEscapeCoordinator.shared.unregister(id: "canvas-overlays")
                CanvasPendingPlacementQueue.shared.markCanvasNotReady()
                removeCanvasObservers()
                thinkspaceSwitchTask?.cancel()
                thinkspaceSwitchTask = nil
                libraryLoadTask?.cancel()
                libraryLoadTask = nil
            }
            .onChange(of: geometry.size) { _, newSize in
                updateCanvasSize(newSize)
            }
            .onChange(of: isActive) { _, newValue in
                canvasIsActive = newValue
                if !newValue {
                    DirtyEditorRegistry.shared.flushAll()
                    // Gestures can't finish once the canvas is hidden —
                    // replaces @GestureState auto-reset for interrupted pans.
                    viewportState.resetLiveGesture()
                }
                if !newValue && isSpaceHeld {
                    isSpaceHeld = false
                }
                if newValue {
                    // The canvas just became the visible destination — claim
                    // the Cosmo window context now (a hidden prewarm mount
                    // deliberately skipped this in onAppear).
                    let provider = CanvasContextProvider(spatialEngine: spatialEngine, thinkspaceId: thinkspaceId)
                    CosmoWindowViewModel.shared.updateContext(provider: provider)
                    registerThinkspaceSurface()
                }
                if newValue, observersRegistered {
                    CanvasPendingPlacementQueue.shared.markCanvasReady()
                } else if !newValue {
                    CanvasPendingPlacementQueue.shared.markCanvasNotReady()
                }
            }
            .onChange(of: thinkspaceId) { _, newId in
                thinkspaceSwitchTask?.cancel()
                // Commit visible drafts before starting a read for another
                // space; a rapid return must not fetch before its close save.
                DirtyEditorRegistry.shared.flushAll()
                // A switch mid-gesture must not carry the live pan into the
                // next space (replaces @GestureState auto-reset).
                viewportState.resetLiveGesture()
                if isActive {
                    // Re-scope the assistant to the space being switched to.
                    registerThinkspaceSurface()
                }
                let currentThinkspaceId = spatialEngine.currentThinkspaceId
                rememberCurrentSessionViewport(for: currentThinkspaceId)
                guard newId != spatialEngine.currentThinkspaceId else {
                    // Rapid revert (A→B→A before B applied): the loaded data is
                    // already correct but the exit animation left content hidden.
                    if canvasContentOpacity < 1 {
                        thinkspaceSwitchTask = Task { @MainActor in
                            await animateThinkspaceContentIn()
                        }
                    }
                    return
                }

                // NOTE: no screenshot capture on the switch path — cacheDisplay
                // rasterized the whole window on the main thread and was the
                // single most expensive moment of a switch. The Constellation
                // and thinkspace portals it fed were removed July 2026.

                // 1. Animate old content OUT (blocks still visible, receding into
                //    background).
                withAnimation(reduceMotion ? .easeOut(duration: 0.1) : ProMotionSprings.worldExit) {
                    canvasContentOpacity = 0
                    canvasContentScale = 0.97
                }

                // 2. Overlap the authoritative fetch (DB + atom JSON decode, all
                //    off-main) with the exit animation; warm snapshot applies the
                //    instant the exit completes, fetched data right behind it.
                thinkspaceSwitchTask = Task { @MainActor in
                    async let prefetchedBlocks = spatialEngine.fetchBlocksSnapshot(
                        for: "home", documentId: 0, thinkspaceId: newId
                    )
                    try? await Task.sleep(for: .milliseconds(reduceMotion ? 100 : 180))
                    guard !Task.isCancelled else { return }

                    // Signpost the swap moment — the world remount that follows
                    // this state change is where any switch hitch lives; this
                    // event lines Instruments traces up with it.
                    AppPerformanceInstrumentation.event("thinkspace-swap-apply")
                    let cachedThinkspaceSnapshotApplied = applyCachedThinkspaceSnapshot(for: newId)
                    if cachedThinkspaceSnapshotApplied {
                        drawingState.drawings = []
                        drawingState.loadDrawings(thinkspaceId: newId)
                        CosmoUndoManager.shared.clearHistory()
                        CosmoWindowViewModel.shared.refreshContext()
                        refreshLibraryInventoryForThinkspaceSwitch()
                        await animateThinkspaceContentIn()
                    } else {
                        prepareEmptyThinkspaceSwitchState(for: newId)
                    }

                    let fetchedBlocks = await prefetchedBlocks
                    guard !Task.isCancelled else { return }

                    // Apply the authoritative fetch only when it differs from
                    // what the cached snapshot already mounted — an identical
                    // world must not rebuild every block view mid-entry-spring.
                    let previousBlocks = spatialEngine.blocks
                    let fetchedBlocksDiffer = fetchedBlocks.map { $0 != previousBlocks } ?? false
                    spatialEngine.applyFetchedBlocks(
                        fetchedBlocksDiffer ? fetchedBlocks : nil,
                        for: "home", documentId: 0, thinkspaceId: newId
                    )
                    // The cached snapshot may have mounted stale sticky/note text —
                    // tell exactly the affected editors to re-sync now that
                    // authoritative data landed. (Atom-backed text corrects via
                    // the observation hub's absorb; this covers blocks whose
                    // content lives in canvas_blocks itself.)
                    if cachedThinkspaceSnapshotApplied,
                       let fetchedBlocks,
                       fetchedBlocksDiffer {
                        let changedIds = Self.changedCanvasBlockIds(
                            previous: previousBlocks, fetched: fetchedBlocks
                        )
                        if !changedIds.isEmpty {
                            NotificationCenter.default.post(
                                name: .canvasBlocksDidResync,
                                object: nil,
                                userInfo: ["blockIds": Array(changedIds)]
                            )
                        }
                    }
                    CosmoWindowViewModel.shared.refreshContext()

                    if !cachedThinkspaceSnapshotApplied {
                        drawingState.loadDrawings(thinkspaceId: newId)
                        CosmoUndoManager.shared.clearHistory()
                    }

                    // Compute clusters, then re-verify this switch still owns
                    // the canvas before assigning — a superseding switch can
                    // apply ANOTHER space's world during the await, and an
                    // unguarded assignment here stamped stale clusters onto
                    // it. Publish only on change (an identical set must not
                    // rebuild the cluster layer mid-entry-spring).
                    let refreshedClusters = await clusterEngine.computeUserClusters(
                        thinkspaceId: newId,
                        blocks: spatialEngine.blocks
                    )
                    guard !Task.isCancelled, spatialEngine.currentThinkspaceId == newId else { return }
                    if let refreshedClusters, refreshedClusters != clusterEngine.userClusters {
                        clusterEngine.userClusters = refreshedClusters
                    }

                    rebuildMediaContentCache()
                    refreshLibraryInventoryForThinkspaceSwitch()
                    ThinkspaceCanvasSnapshotCache.shared.store(
                        blocks: spatialEngine.blocks,
                        zoomLevel: canvasScale,
                        panOffset: canvasOffset,
                        thinkspaceId: newId,
                        userClusters: clusterEngine.userClusters
                    )

                    if !cachedThinkspaceSnapshotApplied {
                        // 3. Animate new content IN (emerging from background)
                        await animateThinkspaceContentIn()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Automation.createFlow)) { notification in
                guard let clusterId = notification.userInfo?["clusterId"] as? String else { return }
                withAnimation(ProMotionSprings.bouncy) {
                    flowVerbPickerClusterId = clusterId
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Canvas.prewarmThinkspace)) { notification in
                guard let targetId = notification.userInfo?["thinkspaceId"] as? String else { return }
                prewarmThinkspaceSnapshot(targetId)
            }
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.jumpToPlace)) { notification in
                guard let placeUUID = notification.userInfo?["placeUUID"] as? String,
                      let place = canvasPlaces.first(where: { $0.uuid == placeUUID }) else { return }
                flyToPlace(place)
            }
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.showLibraryFolder)) { notification in
                if let folderID = notification.userInfo?["folderID"] as? UUID {
                    if let thinkspaceId,
                       let snapshot = SpaceWorkspaceStore.shared.snapshots[thinkspaceId],
                       let uuid = snapshot.legacyGroupMapping[folderID.uuidString],
                       let atom = snapshot.atomsByUUID[uuid] {
                        librarySelectedFolderID = nil
                        SpaceWorkspaceStore.shared.open(atom, in: thinkspaceId)
                        return
                    }
                    if let thinkspaceId {
                        SpaceWorkspaceStore.shared.showRoot(.library, in: thinkspaceId)
                    }
                    withAnimation(ProMotionSprings.focusTransition) {
                        librarySelectedFolderID = folderID
                    }
                } else if librarySelectedFolderID != nil {
                    withAnimation(ProMotionSprings.focusTransition) {
                        librarySelectedFolderID = nil
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Automation.flowDidRun)) { notification in
                guard let tsId = notification.userInfo?["thinkspaceId"] as? String,
                      tsId == thinkspaceId,
                      let flowUUID = notification.userInfo?["flowUUID"] as? String else { return }
                // Pick up the staged proposal and fire the bead once.
                loadPlaces(for: thinkspaceId)
                firingFlowIds.insert(flowUUID)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(700))
                    firingFlowIds.remove(flowUUID)
                }
            }
            // Keyboard handler for ESC to collapse expanded blocks / dismiss overlays
            .onKeyPress(.escape) {
                if flowVerbPickerClusterId != nil {
                    withAnimation(ProMotionSprings.snappy) { flowVerbPickerClusterId = nil }
                    return .handled
                }
                if selectedFlowId != nil {
                    withAnimation(ProMotionSprings.snappy) { selectedFlowId = nil }
                    return .handled
                }
                if showPlaceCapture {
                    dismissPlaceCapture()
                    return .handled
                }
                if showMinimap {
                    withAnimation(ProMotionSprings.snappy) {
                        showMinimap = false
                    }
                    return .handled
                }
                if showClusterPopover {
                    withAnimation(ProMotionSprings.snappy) {
                        showClusterPopover = false
                    }
                    return .handled
                }
                return .ignored
            }
            // TAB: Toggle minimap navigator (skip when Command-K is open — Tab cycles tabs there)
            .onKeyPress(.tab) {
                guard !appState.isCommandKVisible else { return .ignored }
                guard appState.focusedEntity == nil else { return .ignored }
                withAnimation(ProMotionSprings.snappy) {
                    showMinimap.toggle()
                }
                return .handled
            }
            // Cmd+Shift+H: Toggle crystallization heatmap
            .onKeyPress(characters: .init(charactersIn: "hH")) { press in
                guard press.modifiers.contains(.command), press.modifiers.contains(.shift) else {
                    return .ignored
                }
                withAnimation(ProMotionSprings.snappy) {
                    showCrystallizationHeatmap.toggle()
                }
                return .handled
            }
            // Cmd+V paste is handled via .performCanvasPaste notification
            // (routed from CosmoCommands pasteboard CommandGroup)
            // Synthesis workspace overlay
            .sheet(isPresented: $showSynthesisWorkspace) {
                synthesisWorkspaceOverlay
                    .frame(minWidth: 900, minHeight: 600)
            }
            // Cluster creation popover
            .overlay {
                if showClusterPopover {
                    clusterCreationOverlay
                }
            }
            // Minimap navigator overlay
            .overlay {
                if showMinimap {
                    minimapOverlay
                }
            }
            // Place capture card (Cmd+D)
            .overlay(alignment: .top) {
                if showPlaceCapture {
                    PlaceCaptureCard(
                        name: $placeNameDraft,
                        onSave: { savePlaceFromDraft() },
                        onCancel: { dismissPlaceCapture() }
                    )
                    .padding(.top, 64)
                    .transition(.opacity)
                    .zIndex(300)
                }
            }
            // Concept merge drop card — anchored on the concept block a
            // note/sticky was just dropped onto
            .overlay {
                if let candidate = conceptMergeDrop {
                    ConceptMergeDropCard(
                        candidate: candidate,
                        onMerge: { beginConceptMerge(candidate) },
                        onCancel: {
                            withAnimation(ProMotionSprings.snappy) { conceptMergeDrop = nil }
                        }
                    )
                    .position(clampedScreenPosition(
                        forCanvasPoint: candidate.anchorPoint,
                        size: CGSize(width: 340, height: 170)
                    ))
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(320)
                }
            }
            // Flow verb picker — blooms beside the source cluster
            .overlay {
                if let clusterId = flowVerbPickerClusterId,
                   let cluster = clusterEngine.allClusters.first(where: { $0.id.uuidString == clusterId }) {
                    FlowVerbPicker(
                        clusterName: cluster.name,
                        onPick: { verb in
                            withAnimation(ProMotionSprings.snappy) {
                                flowVerbPickerClusterId = nil
                            }
                            createFlow(verb: verb, cluster: cluster)
                        },
                        onDismiss: {
                            withAnimation(ProMotionSprings.snappy) {
                                flowVerbPickerClusterId = nil
                            }
                        }
                    )
                    .position(clampedScreenPosition(
                        forCanvasPoint: CGPoint(x: cluster.boundingRect.maxX + 170, y: cluster.boundingRect.midY),
                        size: CGSize(width: 280, height: 170)
                    ))
                    .transition(.opacity)
                    .zIndex(310)
                }
            }
            // Flow inspector — the rule as a sentence, Run, ledger
            .overlay {
                if let flow = canvasFlows.first(where: { $0.uuid == selectedFlowId }),
                   let cluster = clusterEngine.allClusters.first(where: { $0.id.uuidString == flow.sourceClusterId }) {
                    FlowInspectorCard(
                        flow: flow,
                        clusterName: cluster.name,
                        isRunning: runningFlowIds.contains(flow.uuid),
                        onRun: { runFlow(flow) },
                        onChangeRunMode: { mode in
                            setFlowRunMode(flow, mode: mode, clusterName: cluster.name)
                        },
                        onDelete: { deleteFlow(flow) },
                        onRevealOutput: { revealFlowOutput($0) },
                        onDismiss: {
                            withAnimation(ProMotionSprings.snappy) {
                                selectedFlowId = nil
                            }
                        }
                    )
                    .position(clampedScreenPosition(
                        forCanvasPoint: FlowGeometry(clusterRect: cluster.boundingRect, end: flow.endPoint).midpoint,
                        size: CGSize(width: 340, height: 340)
                    ))
                    .transition(.opacity)
                    .zIndex(310)
                }
            }
        }
    }

    // MARK: - Synthesis Workspace

    @ViewBuilder
    private var synthesisWorkspaceOverlay: some View {
        SynthesisWorkspaceLoader(
            blockIds: synthesisSourceBlockIds,
            blocks: spatialEngine.blocks,
            onCreateConnection: { result in
                Task {
                    await createSynthesisConnection(result: result)
                }
                showSynthesisWorkspace = false
            },
            onDismiss: {
                showSynthesisWorkspace = false
            }
        )
    }

    private func createSynthesisConnection(result: LassoSynthesisResult) async {
        let atomRepo = AtomRepository.shared

        // Build synthesis metadata
        let synthMeta = SynthesisMetadata(
            sourceAtomUUIDs: result.sourceAtomUUIDs,
            themes: result.themes,
            openQuestions: result.openQuestions,
            evidenceSpans: result.evidenceSpans,
            synthesizedAt: ISO8601.string(from: Date())
        )

        let metadataJSON: String
        if let data = try? JSONEncoder().encode(synthMeta),
           let json = String(data: data, encoding: .utf8) {
            metadataJSON = json
        } else {
            metadataJSON = "{}"
        }

        // Create bidirectional links to all source atoms
        let links: [AtomLink] = result.sourceAtomUUIDs.map {
            AtomLink(linkType: .related, uuid: $0)
        }

        do {
            let connectionAtom = try await atomRepo.create(
                type: .connection,
                title: result.suggestedTitle,
                body: result.synthesizedArgument,
                metadata: metadataJSON,
                links: links
            )

            // Calculate center position of source blocks for placement
            let sourceBlocks = spatialEngine.blocks.filter { block in
                synthesisSourceBlockIds.contains(block.id)
            }
            let avgX = sourceBlocks.map(\.position.x).reduce(0, +) / max(CGFloat(sourceBlocks.count), 1)
            let avgY = sourceBlocks.map(\.position.y).reduce(0, +) / max(CGFloat(sourceBlocks.count), 1)
            let position = CGPoint(x: avgX, y: avgY + 300) // Place below source cluster

            let canvasBlock = CanvasBlock.fromAtom(connectionAtom, position: position)
            await spatialEngine.addBlock(canvasBlock, persist: true)

            print("Synthesis: Created connection '\(result.suggestedTitle)' linking \(result.sourceAtomUUIDs.count) sources")
        } catch {
            print("Synthesis: Failed to create connection — \(error)")
        }
    }

    // MARK: - Cluster Creation Overlay

    @ViewBuilder
    private var clusterCreationOverlay: some View {
        // Dismiss backdrop
        Color.clear
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(ProMotionSprings.snappy) {
                    showClusterPopover = false
                }
            }

        ClusterCreationPopover(
            blockIds: clusterPopoverBlockIds,
            position: clusterPopoverPosition,
            onCreateCluster: { name, colorIndex in
                let thinkspaceId = thinkspaceManager.currentThinkspace?.id
                if clusterPopoverBlockIds.isEmpty {
                    // Zone mode — create empty zone cluster
                    clusterEngine.createZoneCluster(
                        name: name,
                        colorIndex: colorIndex,
                        boundingRect: zonePopoverRect,
                        thinkspaceId: thinkspaceId
                    )
                } else {
                    // Lasso mode — convert block IDs to entity UUIDs for cluster membership
                    let blockUUIDs = spatialEngine.blocks
                        .filter { clusterPopoverBlockIds.contains($0.id) }
                        .map { $0.entityUuid }
                    clusterEngine.createUserCluster(
                        name: name,
                        colorIndex: colorIndex,
                        blockUUIDs: blockUUIDs,
                        blocks: spatialEngine.blocks,
                        thinkspaceId: thinkspaceId
                    )
                }
                withAnimation(ProMotionSprings.snappy) {
                    showClusterPopover = false
                }
            },
            onDismiss: {
                withAnimation(ProMotionSprings.snappy) {
                    showClusterPopover = false
                }
            }
        )
    }

    // MARK: - Minimap Overlay

    @ViewBuilder
    private var minimapOverlay: some View {
        CanvasLiveTransformReader(viewportState: viewportState) { liveTransform in
            minimapOverlayContent(currentViewport: liveTransform.visibleCanvasRect)
        }
    }

    @ViewBuilder
    private func minimapOverlayContent(currentViewport: CGRect) -> some View {
        CanvasMinimapOverlay(
            blocks: spatialEngine.blocks,
            clusters: clusterEngine.allClusters,
            currentViewport: currentViewport,
            onNavigate: { canvasPosition, animated in
                navigateTo(canvasPosition: canvasPosition, animated: animated)
            },
            onDismiss: {
                withAnimation(ProMotionSprings.snappy) {
                    showMinimap = false
                }
            },
            places: canvasPlaces,
            onJumpToPlace: { place in
                withAnimation(ProMotionSprings.snappy) {
                    showMinimap = false
                }
                flyToPlace(place)
            }
        )
    }

    private func isTextInputFocused(in window: NSWindow?) -> Bool {
        guard let responder = window?.firstResponder else { return false }

        if responder is NSTextView ||
            responder is NSTextField ||
            responder is NSSecureTextField {
            return true
        }

        let responderType = String(describing: type(of: responder))
        return responderType.contains("NSTextInputContext") ||
            responderType.contains("FieldEditor") ||
            responderType.contains("TextField") ||
            responderType.contains("TextEditor")
    }

    /// Compute current viewport rect in canvas coordinates
    private func computeCurrentViewport() -> CGRect {
        viewportTransform.visibleCanvasRect
    }

    /// Move viewport to center on a canvas position, optionally animated
    private func navigateTo(canvasPosition: CGPoint, animated: Bool = true) {
        let screenCenterX = canvasSize.width / 2
        let screenCenterY = canvasSize.height / 2
        let newOffset = CGSize(
            width: screenCenterX - canvasPosition.x,
            height: screenCenterY - canvasPosition.y
        )
        if animated {
            withAnimation(ProMotionSprings.snappy) {
                canvasOffset = newOffset
            }
        } else {
            canvasOffset = newOffset
        }
    }

    // MARK: - Places (saved camera positions)

    private func presentPlaceCapture() {
        placeNameDraft = defaultPlaceName()
        withAnimation(ProMotionSprings.bouncy) { showPlaceCapture = true }
    }

    private func dismissPlaceCapture() {
        withAnimation(ProMotionSprings.snappy) { showPlaceCapture = false }
        placeNameDraft = ""
    }

    /// Default name: the cluster nearest the viewport center, else "Place N".
    private func defaultPlaceName() -> String {
        let screenCenter = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let center = viewportTransform.screenToCanvas(screenCenter)
        let nearest = clusterEngine.allClusters.min { lhs, rhs in
            hypot(lhs.boundingRect.midX - center.x, lhs.boundingRect.midY - center.y) <
            hypot(rhs.boundingRect.midX - center.x, rhs.boundingRect.midY - center.y)
        }
        if let nearest,
           hypot(nearest.boundingRect.midX - center.x, nearest.boundingRect.midY - center.y) < 900,
           !nearest.name.isEmpty {
            return nearest.name
        }
        return "Place \(canvasPlaces.count + 1)"
    }

    private func savePlaceFromDraft() {
        let trimmed = placeNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let screenCenter = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let center = viewportTransform.screenToCanvas(screenCenter)
        let place = CanvasPlace(
            name: trimmed.isEmpty ? defaultPlaceName() : trimmed,
            center: center,
            zoom: Double(canvasScale)
        )
        canvasPlaces.append(place)
        dismissPlaceCapture()
        persistPlaces()
    }

    private func persistPlaces() {
        guard let tsId = thinkspaceId else { return }
        let places = canvasPlaces
        thinkspaceManager.updateCurrentPlaces(places)
        Task { await thinkspaceManager.savePlaces(places, for: tsId) }
    }

    private func loadPlaces(for thinkspaceId: String?) {
        guard let tsId = thinkspaceId else {
            canvasPlaces = []
            canvasFlows = []
            thinkspaceManager.updateCurrentPlaces([])
            return
        }
        Task { @MainActor in
            canvasPlaces = await thinkspaceManager.places(for: tsId)
            canvasFlows = await thinkspaceManager.flows(for: tsId)
            thinkspaceManager.updateCurrentPlaces(canvasPlaces)
        }
    }

    // MARK: - Flows (Living Workflows)

    private func persistFlows() {
        guard let tsId = thinkspaceId else { return }
        let flows = canvasFlows
        Task { await thinkspaceManager.saveFlows(flows, for: tsId) }
    }

    /// Create a flow with its end point placed beside the cluster; the line
    /// draws itself in and the inspector opens so Run is one click away.
    private func createFlow(verb: FlowVerb, cluster: CanvasCluster) {
        let end = CGPoint(x: cluster.boundingRect.maxX + 320, y: cluster.boundingRect.midY)
        let flow = CanvasFlow(verb: verb, sourceClusterId: cluster.id.uuidString, end: end)
        withAnimation(ProMotionSprings.gentle) {
            canvasFlows.append(flow)
            selectedFlowId = flow.uuid
        }
        persistFlows()
    }

    private func moveFlowEnd(_ flowUUID: String, to end: CGPoint) {
        guard let index = canvasFlows.firstIndex(where: { $0.uuid == flowUUID }) else { return }
        canvasFlows[index].endPoint = end
        persistFlows()
    }

    private func deleteFlow(_ flow: CanvasFlow) {
        withAnimation(ProMotionSprings.snappy) {
            canvasFlows.removeAll { $0.uuid == flow.uuid }
            selectedFlowId = nil
        }
        persistFlows()
        Task { await FlowCompiler.deleteRule(forFlowUUID: flow.uuid) }
    }

    /// Change how a flow fires — compiles to (or removes) its AutomationRule.
    private func setFlowRunMode(_ flow: CanvasFlow, mode: FlowRunMode, clusterName: String) {
        guard let index = canvasFlows.firstIndex(where: { $0.uuid == flow.uuid }) else { return }
        withAnimation(ProMotionSprings.snappy) {
            canvasFlows[index].runMode = mode
        }
        persistFlows()
        guard let tsId = thinkspaceId else { return }
        let updated = canvasFlows[index]
        Task { await FlowCompiler.sync(updated, clusterName: clusterName, thinkspaceId: tsId) }
    }

    /// Accept an autonomous run's staged output — the block lands at the
    /// flow's end and the dashed line inks back to solid.
    private func acceptFlowProposal(_ flow: CanvasFlow) {
        guard let index = canvasFlows.firstIndex(where: { $0.uuid == flow.uuid }),
              let atomUUID = flow.pendingOutputAtomUUID else { return }
        Task { @MainActor in
            guard let atom = try? await AtomRepository.shared.fetch(uuid: atomUUID) else {
                canvasFlows[index].pendingOutputAtomUUID = nil
                persistFlows()
                return
            }
            let block = CanvasBlock.fromAtom(atom, position: flow.endPoint)
            await spatialEngine.addBlock(block, persist: true)
            withAnimation(ProMotionSprings.gentle) {
                canvasFlows[index].pendingOutputAtomUUID = nil
            }
            persistFlows()
        }
    }

    /// Discard a staged output — the atom is deleted, the ledger keeps the record.
    private func discardFlowProposal(_ flow: CanvasFlow) {
        guard let index = canvasFlows.firstIndex(where: { $0.uuid == flow.uuid }),
              let atomUUID = flow.pendingOutputAtomUUID else { return }
        withAnimation(ProMotionSprings.snappy) {
            canvasFlows[index].pendingOutputAtomUUID = nil
        }
        persistFlows()
        Task { try? await AtomRepository.shared.delete(uuid: atomUUID) }
    }

    /// Run a flow: verb executes over the cluster's atoms, the bead travels
    /// the line once, and the output lands as a block at the flow's end.
    private func runFlow(_ flow: CanvasFlow) {
        guard !runningFlowIds.contains(flow.uuid) else { return }
        guard let cluster = clusterEngine.allClusters.first(where: { $0.id.uuidString == flow.sourceClusterId }) else { return }
        runningFlowIds.insert(flow.uuid)

        Task { @MainActor in
            defer { runningFlowIds.remove(flow.uuid) }
            do {
                let result = try await FlowEngine.run(flow, cluster: cluster, thinkspaceId: thinkspaceId)

                // The bead — the entire firing show
                firingFlowIds.insert(flow.uuid)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(700))
                    firingFlowIds.remove(flow.uuid)
                }

                // Land the output at the flow's end point
                let block = CanvasBlock.fromAtom(result.outputAtom, position: flow.endPoint)
                await spatialEngine.addBlock(block, persist: true)

                if let index = canvasFlows.firstIndex(where: { $0.uuid == flow.uuid }) {
                    canvasFlows[index].runCount += 1
                    canvasFlows[index].lastRunAt = Date()
                    persistFlows()
                }
            } catch {
                print("❌ Flow run failed: \(error)")
            }
        }
    }

    private func revealFlowOutput(_ atomUUID: String) {
        withAnimation(ProMotionSprings.snappy) { selectedFlowId = nil }
        if let block = spatialEngine.blocks.first(where: { $0.entityUuid == atomUUID }) {
            navigateTo(canvasPosition: block.position)
        }
    }

    /// Dismiss the topmost canvas overlay for an Escape press.
    /// Wired into CanvasEscapeCoordinator so MainView's global key monitor
    /// gives these overlays priority over pane-closing / thinkspace-exit.
    private func dismissTopCanvasOverlay() -> Bool {
        // The library's own ladder (search → rename → selection → folder)
        // runs before the shell sends the user home.
        if activeSpaceView == .library, libraryChrome.handleEscape() {
            return true
        }
        if showPlaceCapture {
            dismissPlaceCapture()
            return true
        }
        if flowVerbPickerClusterId != nil {
            withAnimation(ProMotionSprings.snappy) { flowVerbPickerClusterId = nil }
            return true
        }
        if selectedFlowId != nil {
            withAnimation(ProMotionSprings.snappy) { selectedFlowId = nil }
            return true
        }
        return false
    }

    /// Convert a canvas point to a screen position clamped inside the canvas
    /// bounds so floating cards never fall off the edge.
    private func clampedScreenPosition(forCanvasPoint point: CGPoint, size: CGSize) -> CGPoint {
        let screen = viewportTransform.canvasToScreen(point)
        return CGPoint(
            x: min(max(screen.x, size.width / 2 + 16), max(canvasSize.width - size.width / 2 - 16, size.width / 2 + 16)),
            y: min(max(screen.y, size.height / 2 + 16), max(canvasSize.height - size.height / 2 - 16, size.height / 2 + 16))
        )
    }

    @discardableResult
    private func jumpToPlace(atRecencyIndex index: Int) -> Bool {
        let ordered = canvasPlaces.sorted { $0.createdAt > $1.createdAt }
        guard ordered.indices.contains(index) else { return false }
        flyToPlace(ordered[index])
        return true
    }

    /// The Place flight: a zoom arc — ease out slightly, travel, settle in.
    /// A hard cut is disorienting; the arc keeps the jump spatial.
    private func flyToPlace(_ place: CanvasPlace) {
        let screenCenter = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let targetOffset = CGSize(
            width: screenCenter.x - place.center.x,
            height: screenCenter.y - place.center.y
        )
        let targetScale = max(minScale, min(maxScale, CGFloat(place.zoom)))
        if reduceMotion {
            canvasScale = targetScale
            canvasOffset = targetOffset
            return
        }
        withAnimation(ProMotionSprings.gentle) {
            canvasScale = min(canvasScale, targetScale) * 0.88
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(ProMotionSprings.modal) {
                canvasScale = targetScale
                canvasOffset = targetOffset
            }
        }
    }

    // MARK: - Crystallization Heatmap

    /// Returns opacity multiplier for a block when heatmap mode is active
    private func heatmapOpacity(for block: CanvasBlock) -> CGFloat {
        guard showCrystallizationHeatmap else { return 1.0 }
        let level = crystallizationEngine.levels[block.entityUuid] ?? .raw
        switch level {
        case .raw: return 0.3
        case .highlighted: return 0.5
        case .distilled: return 0.7
        case .connected: return 0.85
        case .crystallized: return 1.0
        }
    }

    // MARK: - Legacy Block Repair

    /// Repairs persisted canvas blocks that have invalid entity IDs (<= 0) by creating
    /// corresponding DB rows and updating the canvas_blocks record in-place.
    /// Returns the number of blocks that needed repair.
    @MainActor
    @discardableResult
    private func repairLegacyBlocksIfNeeded() async -> Int {
        let repairableTypes: Set<EntityType> = [.idea, .content, .research, .task, .connection]
        let indicesToRepair = spatialEngine.blocks.indices.filter { idx in
            let b = spatialEngine.blocks[idx]
            return repairableTypes.contains(b.entityType) && b.entityId <= 0
        }

        guard !indicesToRepair.isEmpty else { return 0 }

        print("🛠️ Repairing \(indicesToRepair.count) legacy canvas blocks with invalid entity IDs…")

        for idx in indicesToRepair {
            var block = spatialEngine.blocks[idx]

            // Capture values before async closures to avoid Swift concurrency issues
            let blockTitle = block.title
            let blockUuid = block.entityUuid

            do {
                // Route ALL repairs through AtomRepository — the legacy
                // ideas/content/tasks/research tables no longer sync or appear
                // in atom-based UI; rows created there were stranded (content
                // typed into a repaired block became invisible everywhere).
                let atomType: AtomType?
                let fallbackTitle: String
                switch block.entityType {
                case .idea: atomType = .idea; fallbackTitle = "New Idea"
                case .content: atomType = .content; fallbackTitle = "New Content"
                case .task: atomType = .task; fallbackTitle = "New Task"
                case .research: atomType = .research; fallbackTitle = "New Research"
                case .connection: atomType = .connection; fallbackTitle = "New Concept"
                default: atomType = nil; fallbackTitle = ""
                }

                if let atomType {
                    var atom = Atom.new(type: atomType, title: blockTitle.isEmpty ? fallbackTitle : blockTitle)
                    // Preserve the block UUID so future linking stays consistent
                    if !blockUuid.isEmpty { atom.uuid = blockUuid }
                    let saved = try await AtomRepository.shared.create(atom)
                    block.entityId = saved.id ?? -1
                    block.entityUuid = saved.uuid
                }

                // Apply updates in-memory + persist to canvas_blocks
                spatialEngine.blocks[idx] = block
                await spatialEngine.saveBlock(block)
                print("🛠️ Repaired block \(block.id) → \(block.entityType.rawValue) id=\(block.entityId)")
            } catch {
                print("❌ Failed to repair block \(block.id) (\(block.entityType.rawValue)): \(error)")
            }
        }
        return indicesToRepair.count
    }

    // MARK: - Computed Properties

    // MARK: - Calendar Window Handler
    private func handleOpenCalendarWindow(notification: Notification) {
        // Check if a calendar block already exists - focus it instead of creating duplicate
        if let existingCalendar = spatialEngine.blocks.first(where: { $0.entityType == .calendar }) {
            // Scroll canvas to center on existing calendar
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                canvasOffset = CGSize(
                    width: -existingCalendar.position.x + canvasSize.width / 2,
                    height: -existingCalendar.position.y + canvasSize.height / 2
                )
            }
            selectedBlockId = existingCalendar.id
            print("📅 Focused existing calendar window")
            return
        }

        // Calculate center position in canvas coordinates
        // Use window frame if canvasSize not available, accounting for any canvas offset
        let viewportSize: CGSize
        if canvasSize.width > 0 && canvasSize.height > 0 {
            viewportSize = canvasSize
        } else if let window = NSApp.keyWindow {
            viewportSize = window.contentView?.frame.size ?? CGSize(width: 1440, height: 900)
        } else {
            viewportSize = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        }

        // Center in current viewport, accounting for canvas pan offset
        let position = CGPoint(
            x: viewportSize.width / 2 - canvasOffset.width - scaledPanOffset.width,
            y: viewportSize.height / 2 - canvasOffset.height - scaledPanOffset.height
        )

        let block = CanvasBlock.calendarBlock(position: position)

        Task {
            await spatialEngine.addBlock(block, persist: true)
        }

        print("📅 Opened calendar window at \(position)")
    }

    // MARK: - Research Block Creation Handler
    private func handleCreateResearchBlock(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let researchId = userInfo["researchId"] as? Int64 else {
            return
        }

        // Get position from notification or use center
        let screenPosition: CGPoint
        if let pos = userInfo["position"] as? CGPoint {
            screenPosition = pos
        } else {
            screenPosition = CGPoint(
                x: canvasSize.width / 2,
                y: canvasSize.height / 2
            )
        }

        // Convert screen position to canvas position (accounting for zoom)
        let position = screenToCanvasPosition(screenPosition)

        let block = CanvasBlock(
            position: position,
            size: CGSize(width: 300, height: 280),
            entityType: .research,
            entityId: researchId,
            entityUuid: UUID().uuidString,
            title: "Research",
            subtitle: nil,
            metadata: ["created": ISO8601.string(from: Date())]
        )

        Task {
            await spatialEngine.addBlock(block, persist: true)
        }

        print("🔬 Created research block for ID \(researchId)")
    }

    // MARK: - Block Content Update Handler
    private func handleUpdateBlockContent(notification: Notification) {
        guard let blockId = notification.userInfo?["blockId"] as? String,
              let content = notification.userInfo?["content"] as? String else { return }
        let title = notification.userInfo?["title"] as? String
        Task { @MainActor in
            if let block = spatialEngine.blocks.first(where: { $0.id == blockId }),
               ![EntityType.note, .stickyNote, .content].contains(block.entityType) {
                if block.entityId == -1 && !content.isEmpty {
                    await createDatabaseEntryForBlock(block: block, content: content)
                } else if block.entityId != -1 {
                    await updateDatabaseEntry(block: block, content: content)
                }
                return
            }
            var patch = ["content": content]
            if let title { patch["title"] = title }
            do {
                try spatialEngine.updateBlockMetadata(blockID: blockId, patch: patch)
            } catch {
                PersistenceHealth.note(.writeFailure, context: "canvas.updateBlockContent", detail: "\(blockId): \(error)")
            }
        }
    }

    private func storeThinkspaceSnapshotCache() {
        ThinkspaceCanvasSnapshotCache.shared.store(
            blocks: spatialEngine.blocks, zoomLevel: canvasScale, panOffset: canvasOffset,
            thinkspaceId: spatialEngine.currentThinkspaceId, userClusters: clusterEngine.userClusters
        )
    }

    private func handleUpdateBlockMetadata(notification: Notification) {
        guard let metadata = notification.userInfo?["metadata"] as? [String: String] else { return }
        let blockId = notification.userInfo?["blockId"] as? String
        let entityUuid = notification.userInfo?["entityUuid"] as? String
        let alreadyPersisted = notification.userInfo?["alreadyPersisted"] as? Bool ?? false
        Task { @MainActor in
            do {
                let ids: [String]
                if let blockId {
                    ids = [blockId]
                } else if let entityUuid {
                    ids = try CosmoDatabase.shared.read { db in
                        try String.fetchAll(db, sql: "SELECT id FROM canvas_blocks WHERE entity_uuid = ? AND is_deleted = 0", arguments: [entityUuid])
                    }
                } else { return }
                for id in ids {
                    try spatialEngine.updateBlockMetadata(blockID: id, patch: metadata, alreadyPersisted: alreadyPersisted)
                }
            } catch {
                PersistenceHealth.note(.writeFailure, context: "canvas.updateBlockMetadata", detail: "\(error)")
            }
        }
    }

    // MARK: - Block Entity Linkage Update Handler
    private func handleUpdateBlockEntity(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let blockId = userInfo["blockId"] as? String,
              let entityId = userInfo["entityId"] as? Int64,
              let entityUuid = userInfo["entityUuid"] as? String else {
            return
        }

        Task { @MainActor in
            guard let blockIndex = spatialEngine.blocks.firstIndex(where: { $0.id == blockId }) else {
                return
            }

            spatialEngine.blocks[blockIndex].entityId = entityId
            spatialEngine.blocks[blockIndex].entityUuid = entityUuid
            if userInfo["alreadyPersisted"] as? Bool != true {
                await spatialEngine.saveBlock(spatialEngine.blocks[blockIndex])
            }
        }
    }

    // MARK: - Block Size Update Handler
    private func handleUpdateBlockSize(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let blockId = userInfo["blockId"] as? String,
              let size = userInfo["size"] as? CGSize else {
            return
        }
        
        // Find the block and update its size in memory
        guard let blockIndex = spatialEngine.blocks.firstIndex(where: { $0.id == blockId }) else {
            return
        }
        
        spatialEngine.blocks[blockIndex].size = size

        // Also update position if provided (for anchored resizing)
        if let position = userInfo["position"] as? CGPoint {
            spatialEngine.blocks[blockIndex].position = position
        }

        // Recompute cluster bounds so zones expand/shrink with resized blocks
        clusterEngine.updateUserClusterBounds(blocks: spatialEngine.blocks)
    }

    // MARK: - Zoom/Pan Persistence

    private func debouncedSaveZoomPan() {
        // Trailing-edge debounce: cancel any pending save and restart the timer.
        // Only saves once the user STOPS panning/zooming for 2 seconds.
        zoomPanSaveTask?.cancel()
        zoomPanSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.0))
            guard !Task.isCancelled else { return }
            zoomPanSaveTask = nil
            let blockIds = spatialEngine.blocks.map(\.id)
            await thinkspaceManager.saveCurrentState(
                zoomLevel: Double(canvasScale),
                panOffset: canvasOffset,
                blockIds: blockIds
            )
            ThinkspaceCanvasSnapshotCache.shared.store(
                blocks: spatialEngine.blocks,
                zoomLevel: canvasScale,
                panOffset: canvasOffset,
                thinkspaceId: thinkspaceId,
                userClusters: clusterEngine.userClusters
            )
        }
    }

    // MARK: - PERF: Debounced Frame Tracker

    /// Schedule a frame tracker update with 100ms debounce.
    /// The frame tracker is only used for right-click hit testing, so slight delay is fine.
    private func scheduleFrameUpdate() {
        frameUpdateTask?.cancel()
        frameUpdateTask = Task { @MainActor in
            let signpost = CanvasPerformanceInstrumentation.signposter.beginInterval("frame-tracker-update")
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            blockFrameTracker.update(
                blocks: spatialEngine.blocks,
                userClusters: clusterEngine.userClusters,
                transform: viewportTransform
            )
            CanvasPerformanceInstrumentation.signposter.endInterval("frame-tracker-update", signpost)
        }
    }

    // MARK: - Save Block Size Handler
    private func handleSaveBlockSize(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let blockId = userInfo["blockId"] as? String,
              let newSize = userInfo["size"] as? CGSize else {
            return
        }

        // Find the block and persist to database
        guard let blockIndex = spatialEngine.blocks.firstIndex(where: { $0.id == blockId }) else {
            return
        }

        // Register undo action if old size was provided
        if let oldSize = userInfo["oldSize"] as? CGSize {
            if oldSize != newSize {
                CosmoUndoManager.shared.register(
                    ResizeBlockAction(blockId: blockId, oldSize: oldSize, newSize: newSize, spatialEngine: spatialEngine)
                )
            }
        }

        // Update the spatial engine block with the new size before saving
        spatialEngine.blocks[blockIndex].size = newSize
        clusterEngine.updateUserClusterBounds(blocks: spatialEngine.blocks)
        clusterEngine.persistAfterMove()

        let block = spatialEngine.blocks[blockIndex]
        Task {
            await spatialEngine.saveBlock(block)
        }
    }

    // MARK: - Cluster-to-Canvas Drop

    private func handleClusterToCanvasDrop(blockUUID: String, canvasPosition: CGPoint) {
        // Find the source cluster containing this block
        guard let sourceCluster = clusterEngine.allClusters.first(where: { $0.blockUUIDs.contains(blockUUID) }) else { return }

        // Remove from source cluster (persists internally)
        clusterEngine.removeBlockFromCluster(blockUUID: blockUUID, clusterId: sourceCluster.id, blocks: spatialEngine.blocks)

        // Restore block's position and default size on the canvas
        if let blockIndex = spatialEngine.blocks.firstIndex(where: { $0.entityUuid == blockUUID }) {
            spatialEngine.blocks[blockIndex].position = canvasPosition
            spatialEngine.blocks[blockIndex].size = spatialEngine.blocks[blockIndex].defaultSize

            let block = spatialEngine.blocks[blockIndex]
            Task {
                await spatialEngine.saveBlock(block)
            }
        }

        clusterEngine.updateUserClusterBounds(blocks: spatialEngine.blocks)
        ClusterViewDragSession.sourceClusterId = nil
    }

    private func createDatabaseEntryForBlock(block: CanvasBlock, content: String) async {
        // Create database entry based on entity type
        // This makes the block searchable in Cmd+K
        do {
            switch block.entityType {
            case .idea:
                let idea = try await CosmoDatabase.shared.asyncWrite { db -> Idea in
                    var mutableIdea = Idea.new(
                        title: String(content.prefix(50)),
                        content: content
                    )
                    mutableIdea.uuid = block.entityUuid
                    try mutableIdea.insert(db)
                    mutableIdea.id = db.lastInsertedRowID
                    return mutableIdea
                }

                // Update block with real entity ID
                if let index = spatialEngine.blocks.firstIndex(where: { $0.id == block.id }) {
                    spatialEngine.blocks[index].entityId = idea.id ?? -1
                }
                print("💡 Created idea in database: \(idea.title ?? "Untitled")")

            case .note:
                // Notes now have backing atoms — update both block metadata and atom
                if let index = spatialEngine.blocks.firstIndex(where: { $0.id == block.id }) {
                    try spatialEngine.updateBlockMetadata(blockID: spatialEngine.blocks[index].id, patch: ["content": content])
                }
                // Also update the backing atom if it exists
                if block.entityId > 0 {
                    try await CosmoDatabase.shared.asyncWrite { db in
                        try db.execute(
                            sql: "UPDATE atoms SET body = ?, updated_at = ?, _local_version = _local_version + 1 WHERE id = ?",
                            arguments: [content, ISO8601.string(from: Date()), block.entityId]
                        )
                    }
                }
                print("📝 Saved note content")

            default:
                break
            }
        } catch {
            PersistenceHealth.note(.writeFailure, context: "canvas.createDatabaseEntryForBlock", detail: "block \(block.id) (\(block.entityType.rawValue)): \(error)")
            print("❌ Failed to create database entry: \(error)")
        }
    }

    private func updateDatabaseEntry(block: CanvasBlock, content: String) async {
        // Update existing database entry
        do {
            switch block.entityType {
            case .idea:
                try await CosmoDatabase.shared.asyncWrite { db in
                    if var idea = try Idea.fetchOne(db, key: block.entityId) {
                        idea.content = content
                        idea.updatedAt = ISO8601.string(from: Date())
                        try idea.save(db)
                    }
                }
                print("💡 Updated idea in database")

            case .note:
                if let index = spatialEngine.blocks.firstIndex(where: { $0.id == block.id }) {
                    try spatialEngine.updateBlockMetadata(blockID: spatialEngine.blocks[index].id, patch: ["content": content])
                }

            default:
                break
            }
        } catch {
            PersistenceHealth.note(.writeFailure, context: "canvas.updateDatabaseEntry", detail: "block \(block.id) (\(block.entityType.rawValue)): \(error)")
            print("❌ Failed to update database entry: \(error)")
        }
    }

    // MARK: - Entity Creation Handler
    private func handleCreateEntityAtPosition(notification: Notification) {
        // If Focus Mode is active, forward to Focus Mode's DocumentBlocksLayer
        if appState.focusedEntity != nil {
            print("📦 handleCreateEntityAtPosition: forwarding to Focus Mode")
            NotificationCenter.default.post(
                name: .createEntityInFocusMode,
                object: nil,
                userInfo: notification.userInfo
            )
            return
        }

        guard let userInfo = notification.userInfo,
              let entityType = userInfo["type"] as? EntityType else {
            print("⚠️ handleCreateEntityAtPosition: missing userInfo or entityType")
            return
        }

        print("📦 handleCreateEntityAtPosition: received \(entityType)")

        var screenPosition = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        if let pos = userInfo["position"] as? CGPoint {
            // Position is already in window coordinates, which matches the canvas
            // coordinate space (canvas fills full window width, extending behind sidebar)
            screenPosition = pos
        }

        // Convert screen position to canvas position (accounting for zoom)
        let position = screenToCanvasPosition(screenPosition)

        // Handle existing atom from database picker
        if let existingUUID = userInfo["existingAtomUUID"] as? String {
            Task {
                guard let atom = try? await AtomRepository.shared.fetch(uuid: existingUUID) else { return }
                let block = CanvasBlock.fromAtom(atom, position: position)
                await spatialEngine.addBlock(block, persist: true)
            }
            return
        }

        print("📦 Creating \(entityType) block at position: \(position)")

        // Optional prefilled content (e.g. “Save as Idea” from Cosmo AI)
        let prefillContent = userInfo["content"] as? String
        let prefillTitle = userInfo["title"] as? String

        // Create appropriate block based on entity type
        let block: CanvasBlock
        switch entityType {
        case .idea:
            // Create entity immediately so the block never shows "not found"
            createIdeaBlock(at: position, prefillContent: prefillContent, prefillTitle: prefillTitle)
            return
        case .content:
            createContentBlock(at: position, prefillBody: prefillContent, prefillTitle: prefillTitle)
            return
        case .task:
            createTaskBlock(at: position, prefillTitle: prefillTitle, prefillDescription: prefillContent)
            return
        case .research:
            createNewResearchBlock(at: position, prefillTitle: prefillTitle, prefillSummary: prefillContent)
            return
        case .connection:
            // Connection requires async database creation - handled separately
            createConnectionBlock(at: position)
            return
        case .deepDive:
            createDeepDiveBlock(at: position, prefillTitle: prefillTitle)
            return
        case .note:
            createAtomBackedNoteBlock(at: position, prefillTitle: prefillTitle, prefillBody: prefillContent)
            return
        case .stickyNote:
            block = CanvasBlock.stickyNoteBlock(position: position)
        case .cosmoAI:
            block = CanvasBlock.cosmoAIBlock(position: position)
        case .file:
            presentFilePortalOpenPanel(at: position)
            return
        default:
            // For other types, create a generic block
            block = CanvasBlock(
                position: position,
                size: CGSize(width: 280, height: 180),
                entityType: entityType,
                entityId: -1,
                entityUuid: UUID().uuidString,
                title: "New \(entityType)",
                subtitle: nil,
                metadata: ["created": ISO8601.string(from: Date())]
            )
        }

        Task {
            await spatialEngine.addBlock(block, persist: true)

        }

        print("✨ Created \(entityType) block at \(position)")
    }

    private func createAtomBackedNoteBlock(
        at position: CGPoint,
        prefillTitle: String? = nil,
        prefillBody: String? = nil
    ) {
        Task {
            do {
                let snapshot = RichDocumentPersistence.noteSnapshot(
                    existingMetadata: nil,
                    titleDocument: RichDocument.migrateLegacy(prefillTitle ?? ""),
                    bodyDocument: RichDocument.migrateLegacy(prefillBody ?? ""),
                    plainBodyText: prefillBody ?? ""
                )
                let createdAtom = try await AtomRepository.shared.create(
                    type: .note,
                    title: snapshot.atomTitle,
                    body: snapshot.atomBody,
                    metadata: snapshot.metadata
                )
                let block = CanvasBlock.fromAtom(createdAtom, position: position)
                await spatialEngine.addBlock(block, persist: true)
                print("📝 Created atom-backed note block at \(position) with atom \(createdAtom.uuid)")
            } catch {
                PersistenceHealth.note(.writeFailure, context: "canvas.createNoteBlock", detail: "falling back to freeform block: \(error)")
                let block = CanvasBlock.noteBlock(position: position, content: prefillBody ?? "")
                await spatialEngine.addBlock(block, persist: true)
                print("📝 Created note block at \(position) without backing atom: \(error)")
            }
        }
    }

    // MARK: - Gesture Handlers (Optimized)

    /// Optimized drag handler - updates only local @State, not @Published blocks array
    /// This prevents full view hierarchy re-renders during drag
    private func handleDragOptimized(blockId: String, translation: CGSize) {
        // Gesture translation is already in canvas space (the block's local coordinate space
        // inside the scaled container), so use it directly — no scale division needed.
        // Dividing by effectiveScale would double-scale since scaleEffect already transforms
        // the gesture coordinate space.
        interactionState.updateBlockDrag(id: blockId, translation: translation)

        // Deselect cluster during block drag, but don't open inspector —
        // selection (and inspector) is handled by handleTap on click only.
        clusterEngine.selectCluster(nil)

        if let block = spatialEngine.blocks.first(where: { $0.id == blockId }) {
            // Cross-thinkspace drag detection: check if cursor is over the sidebar
            checkCrossThinkspaceDrag(block: block, translation: translation)

            // Check if dragged block is near a cluster zone (for drop highlight)
            let draggedPosition = CGPoint(
                x: block.position.x + translation.width,
                y: block.position.y + translation.height
            )
            updateCanvasClusterDropPreview(for: block, draggedPosition: draggedPosition)

            // Mergeable source hovering a concept block: light the merge preview.
            updateConceptMergeHoverPreview(for: block, draggedPosition: draggedPosition)
        } else {
            clearCanvasClusterDropPreview()
            clearConceptMergeHoverPreview()
        }
    }

    /// Detect when a dragged block enters the sidebar zone for cross-thinkspace transfer
    private func checkCrossThinkspaceDrag(block: CanvasBlock, translation: CGSize) {
        let mouseLocation = NSEvent.mouseLocation
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }

        // Convert screen coords to window coords
        let windowPoint = window.convertPoint(fromScreen: mouseLocation)
        let sidebarWidth = crossDragManager.sidebarTotalWidth

        // Skip cross-thinkspace drag when sidebar is hidden (width == 0)
        guard sidebarWidth > 0 else {
            if !crossDragManager.isDragging {
                crossDragManager.beginDrag(block: block, sourceThinkspaceId: thinkspaceId)
            }
            return
        }

        if windowPoint.x < sidebarWidth {
            // Cursor is over the sidebar
            if !crossDragManager.isDragging {
                crossDragManager.beginDrag(block: block, sourceThinkspaceId: thinkspaceId)
            }
            crossDragManager.enterSidebar()

            // Update cursor position (flip Y for SwiftUI coords — use content view height, not window frame)
            let contentHeight = window.contentView?.bounds.height ?? window.frame.height
            let flippedY = contentHeight - windowPoint.y
            crossDragManager.updateCursorPosition(CGPoint(x: windowPoint.x, y: flippedY))
        } else if crossDragManager.isOverSidebar {
            // Cursor left the sidebar, return to normal canvas drag
            crossDragManager.exitSidebar()
        } else if !crossDragManager.isDragging {
            // Start tracking even when not over sidebar (so we have block info ready)
            crossDragManager.beginDrag(block: block, sourceThinkspaceId: thinkspaceId)
        }
    }

    /// Optimized drag end - commits position to @Published array and database
    private func handleDragEndOptimized(blockId: String, translation: CGSize) {
        clearCanvasClusterDropPreview()

        let isCrossThinkspaceDrop =
            crossDragManager.isDragging &&
            (crossDragManager.isOverSidebar || crossDragManager.hasThinkspaceSwitched)

        // Cross-thinkspace drag: if block is over the sidebar or we've already spring-loaded
        // into another thinkspace, let the shared manager finish the transfer.
        if isCrossThinkspaceDrop {
            interactionState.clearBlockDrag()
            // The crossDragManager's NSEvent mouseUp handler or completeDrop will handle the rest
            let fallbackPosition = crossDragManager.floatingPosition
            if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                let mouseLocation = NSEvent.mouseLocation
                let windowPoint = window.convertPoint(fromScreen: mouseLocation)
                let contentHeight = window.contentView?.bounds.height ?? window.frame.height
                let flippedY = contentHeight - windowPoint.y
                crossDragManager.completeDrop(screenPosition: CGPoint(x: windowPoint.x, y: flippedY))
            } else {
                crossDragManager.completeDrop(screenPosition: fallbackPosition)
            }
            return
        }

        // If cross drag was active but cursor is back on canvas, just cancel it
        if crossDragManager.isDragging {
            crossDragManager.cancel()
        }

        // Gesture translation is already in canvas space (scaleEffect transforms the
        // gesture coordinate space), so use it directly without dividing by effectiveScale.

        // PERF: Batch all state mutations into a single transaction so SwiftUI
        // coalesces them into one render pass instead of three separate evaluations.
        var oldPosition: CGPoint = .zero
        var newPosition: CGPoint = .zero
        var finalResolvedTargetClusterId: UUID?
        if let index = spatialEngine.blocks.firstIndex(where: { $0.id == blockId }) {
            oldPosition = spatialEngine.blocks[index].position
            let rawDropPosition = CGPoint(
                x: oldPosition.x + translation.width,
                y: oldPosition.y + translation.height
            )
            // Resolve fresh at drop (deterministic — same computation the live
            // preview ran, but with the final translation).
            let resolution = clusterEngine.resolveCanvasDrop(
                blockUUID: spatialEngine.blocks[index].entityUuid,
                point: rawDropPosition,
                blockSize: spatialEngine.blocks[index].size
            )

            finalResolvedTargetClusterId = resolution?.clusterId
            newPosition = resolution?.previewPosition ?? rawDropPosition
            // Batch: commit position + clear drag state in one pass
            spatialEngine.blocks[index].position = newPosition
            interactionState.clearBlockDrag()

            // Fire-and-forget position save to database
            spatialEngine.updateBlockPosition(blockId, position: newPosition)

            // Register undo action (only if position actually changed)
            if oldPosition != newPosition {
                CosmoUndoManager.shared.register(
                    MoveBlockAction(blockId: blockId, oldPosition: oldPosition, newPosition: newPosition, spatialEngine: spatialEngine)
                )
            }
        } else {
            // Block not found — still clear drag state
            interactionState.clearBlockDrag()
            clearConceptMergeHoverPreview()
        }

        // Update frame tracker after position change
        blockFrameTracker.update(
            blocks: spatialEngine.blocks,
            userClusters: clusterEngine.userClusters,
            transform: viewportTransform
        )
        ThinkspaceCanvasSnapshotCache.shared.store(
            blocks: spatialEngine.blocks,
            zoomLevel: canvasScale,
            panOffset: canvasOffset,
            thinkspaceId: thinkspaceId,
            userClusters: clusterEngine.userClusters
        )

        // Check cluster zone membership after drag
        if let block = spatialEngine.blocks.first(where: { $0.id == blockId }) {
            updateClusterMembership(for: block, resolvedTargetClusterId: finalResolvedTargetClusterId)
        }

        // A note/sticky released on a concept block offers the merge flow.
        detectConceptMergeDrop(blockId: blockId)
    }

    // MARK: - Concept merge drop (note/sticky/content → connection)

    /// The connection block whose (+12pt-inset) frame contains `center` —
    /// the single hit-test shared by the drag-hover preview and the drag-end
    /// detect, so the preview can never promise a drop the detect refuses.
    private func conceptMergeTargetBlock(under center: CGPoint, excluding blockId: String) -> CanvasBlock? {
        spatialEngine.blocks.first { block in
            guard block.entityType == .connection, block.id != blockId,
                  !block.entityUuid.isEmpty else { return false }
            let frame = CGRect(
                x: block.position.x - block.size.width / 2,
                y: block.position.y - block.size.height / 2,
                width: block.size.width,
                height: block.size.height
            ).insetBy(dx: -12, dy: -12)
            return frame.contains(center)
        }
    }

    /// A note, sticky, or content piece dropped so its center sits on a
    /// connection block offers to merge its content into the concept via the
    /// collaborator. Detection runs ONCE at drag end (never per gesture
    /// frame) and the block's position commit above stands either way —
    /// cancel just leaves the source where it was dropped.
    private func detectConceptMergeDrop(blockId: String) {
        clearConceptMergeHoverPreview()
        guard let dropped = spatialEngine.blocks.first(where: { $0.id == blockId }),
              let source = ConceptMergeSourceSnapshot(block: dropped),
              let target = conceptMergeTargetBlock(under: dropped.position, excluding: blockId)
        else { return }

        let noteTitle = source.title ?? ConceptNoteMergeComposer.untitledFallback(for: source.kind)
        let conceptTitle = target.title.isEmpty ? "this concept" : target.title
        withAnimation(ProMotionSprings.snappy) {
            conceptMergeDrop = ConceptMergeDropCandidate(
                source: source,
                noteTitle: noteTitle,
                conceptBlockID: target.id,
                conceptUUID: target.entityUuid,
                conceptTitle: conceptTitle,
                anchorPoint: target.position
            )
        }
    }

    /// Confirm on the drop card: stash the handoff (the focus mode consumes
    /// it after its surface registers) and open the concept.
    private func beginConceptMerge(_ candidate: ConceptMergeDropCandidate) {
        withAnimation(ProMotionSprings.snappy) { conceptMergeDrop = nil }
        ConceptMergeHandoff.stash(conceptUUID: candidate.conceptUUID, source: candidate.source)
        if let conceptBlock = spatialEngine.blocks.first(where: { $0.id == candidate.conceptBlockID }) {
            openBlockInFocusMode(conceptBlock)
        }
    }

    /// Per-frame during drag: a mergeable source hovering a concept block
    /// lights the merge preview (ring + pill on the target). The @State
    /// identity changes on enter/exit ONLY — never per gesture frame.
    private func updateConceptMergeHoverPreview(for block: CanvasBlock, draggedPosition: CGPoint) {
        guard ConceptMergeSourceSnapshot(block: block) != nil,
              let target = conceptMergeTargetBlock(under: draggedPosition, excluding: block.id) else {
            clearConceptMergeHoverPreview()
            return
        }
        let newPreview = ActiveConceptMergeHoverPreview(
            blockId: block.id,
            conceptBlockID: target.id,
            conceptTitle: target.title.isEmpty ? "this concept" : target.title
        )
        if conceptMergeHoverPreview != newPreview {
            withAnimation(ProMotionSprings.snappy) { conceptMergeHoverPreview = newPreview }
        }
    }

    private func clearConceptMergeHoverPreview() {
        if conceptMergeHoverPreview != nil {
            withAnimation(ProMotionSprings.snappy) { conceptMergeHoverPreview = nil }
        }
    }

    /// Update cluster membership when a block is dragged into/out of a user cluster zone.
    /// Uses a generous proximity check (80pt outset) so blocks dropped near a cluster get absorbed.
    private func updateClusterMembership(for block: CanvasBlock, resolvedTargetClusterId: UUID? = nil) {
        // Clear the visual drop target highlight
        clusterEngine.clearDropTarget()

        // Single atomic persist — avoids race between concurrent remove/add Tasks
        clusterEngine.updateMembership(
            blockUUID: block.entityUuid,
            targetClusterId: resolvedTargetClusterId,
            blockPosition: block.position,
            ejectInset: -40,  // 40pt grace zone before ejecting
            blocks: spatialEngine.blocks
        )
    }

    private func updateCanvasClusterDropPreview(for block: CanvasBlock, draggedPosition: CGPoint) {
        let resolution = clusterEngine.updateCanvasDropTarget(
            blockUUID: block.entityUuid,
            point: draggedPosition,
            blockSize: block.size
        )

        guard let resolution else {
            if canvasClusterDropPreview != nil { canvasClusterDropPreview = nil }
            return
        }

        // Per-frame ghost position rides the interaction observable (leaf host
        // re-evaluates); the @State identity below changes on enter/exit only.
        interactionState.updateDropPreviewPosition(resolution.previewPosition)

        let newPreview = ActiveCanvasClusterDropPreview(
            blockId: block.id,
            blockUUID: block.entityUuid,
            targetClusterId: resolution.clusterId
        )
        if canvasClusterDropPreview != newPreview {
            canvasClusterDropPreview = newPreview
        }
    }

    private func clearCanvasClusterDropPreview() {
        if canvasClusterDropPreview != nil { canvasClusterDropPreview = nil }
        clusterEngine.clearDropTarget()
    }

    // MARK: - Cluster Drag Handlers

    private func handleClusterResize(clusterId: UUID, delta: CGSize, edge: ClusterResizeEdge) {
        guard let cluster = clusterEngine.userClusters.first(where: { $0.id == clusterId }) else { return }

        if cluster.viewMode == .canvas {
            if clusterResizeSession?.clusterId != clusterId {
                let memberGeometries = Dictionary(
                    uniqueKeysWithValues: spatialEngine.blocks
                        .filter { cluster.blockUUIDs.contains($0.entityUuid) }
                        .map { block in
                            (
                                block.id,
                                CanvasBlockGeometry(position: block.position, size: block.size)
                            )
                        }
                )

                clusterResizeSession = ActiveClusterResizeSession(
                    clusterId: clusterId,
                    startRect: cluster.boundingRect,
                    previewGeometries: memberGeometries,
                    memberGeometries: memberGeometries
                )
            }
        } else {
            clusterResizeSession = nil
        }

        clusterEngine.resizeCluster(id: clusterId, delta: delta, edge: edge, blocks: spatialEngine.blocks)

        guard cluster.viewMode == .canvas,
              let currentRect = clusterEngine.userClusters.first(where: { $0.id == clusterId })?.boundingRect,
              let session = clusterResizeSession,
              session.clusterId == clusterId else { return }

        clusterResizeSession?.previewGeometries = CanvasClusterResizeMapper.previewGeometries(
            from: session.startRect,
            to: currentRect,
            edge: edge,
            members: session.memberGeometries
        )
        clusterResizeRevision &+= 1
    }

    private func handleClusterResizeEnd(clusterId: UUID) {
        clearClusterDragPreview(clusterId: clusterId)

        if let session = clusterResizeSession, session.clusterId == clusterId {
            for index in spatialEngine.blocks.indices {
                let blockId = spatialEngine.blocks[index].id
                guard let geometry = session.previewGeometries[blockId] else { continue }

                spatialEngine.blocks[index].position = geometry.position
                spatialEngine.blocks[index].size = geometry.size
                spatialEngine.updateBlockGeometry(
                    blockId,
                    position: geometry.position,
                    size: geometry.size
                )
            }

            blockFrameTracker.update(
                blocks: spatialEngine.blocks,
                userClusters: clusterEngine.userClusters,
                transform: viewportTransform
            )
            clusterResizeSession = nil
        }

        clusterEngine.commitClusterResize(id: clusterId, blocks: spatialEngine.blocks)
    }

    /// Handle live cluster drag — single state write instead of N per-block writes
    private func handleClusterDrag(clusterId: UUID, translation: CGSize) {
        // Don't drag while a resize gesture is active (handles fire both)
        guard clusterEngine.resizingClusterId == nil else { return }

        if interactionState.draggingClusterId != clusterId {
            interactionState.beginClusterDrag(
                id: clusterId,
                memberUUIDs: Set(clusterEngine.memberBlockUUIDs(for: clusterId))
            )
        }
        interactionState.updateClusterDrag(translation: translation)
    }

    /// Commit cluster drag — move all member blocks to their new positions
    private func handleClusterDragEnd(clusterId: UUID, translation: CGSize) {
        // Don't commit drag if a resize gesture was active
        guard clusterEngine.resizingClusterId == nil else { return }

        let memberUUIDs: Set<String> = {
            if interactionState.draggingClusterId == clusterId,
               !interactionState.draggingClusterMemberUUIDs.isEmpty {
                return interactionState.draggingClusterMemberUUIDs
            }
            return Set(clusterEngine.memberBlockUUIDs(for: clusterId))
        }()

        // Commit final positions
        for index in spatialEngine.blocks.indices {
            let block = spatialEngine.blocks[index]
            guard memberUUIDs.contains(block.entityUuid) else { continue }

            let newPosition = CGPoint(
                x: block.position.x + translation.width,
                y: block.position.y + translation.height
            )
            spatialEngine.blocks[index].position = newPosition
            spatialEngine.updateBlockPosition(block.id, position: newPosition)
        }

        // Move the cluster zone rect itself. This prevents list/board clusters from snapping
        // back to their previous origin and avoids grow-only recompute artifacts for canvas mode.
        clusterEngine.offsetClusterRect(id: clusterId, by: translation)

        // Clear cluster drag state
        interactionState.clearClusterDrag()

        // Persist moved cluster + member block positions
        clusterEngine.persistAfterMove()
    }

    /// Clears any live drag preview offsets for a specific cluster.
    private func clearClusterDragPreview(clusterId: UUID) {
        interactionState.updateClusterDrag(translation: .zero)
        if interactionState.draggingClusterId == clusterId {
            interactionState.clearClusterDrag()
        }
    }

    // Legacy handlers (kept for compatibility with other callers)
    private func handleDrag(blockId: String, translation: CGSize) {
        handleDragOptimized(blockId: blockId, translation: translation)
    }

    private func handleDragEnd(blockId: String) {
        if interactionState.activeBlockDragId == blockId {
            handleDragEndOptimized(blockId: blockId, translation: interactionState.blockDragTranslation)
        }
    }

    private func clearSelectedBlock() {
        if let selectedBlockId,
           let index = spatialEngine.blocks.firstIndex(where: { $0.id == selectedBlockId }) {
            spatialEngine.blocks[index].isSelected = false
        }
        selectedBlockId = nil
        // With no block selected, the thinkspace itself is what the user is
        // looking at — the assistant re-scopes to the canvas digest.
        if let thinkspaceEditableSurface {
            CosmoEditableSurfaceRegistry.shared.activateIfNeeded(surfaceID: thinkspaceEditableSurface.surfaceID)
        }
    }

    /// Registers (or re-registers after a thinkspace switch) the thinkspace
    /// surface and makes it the assistant's active scope. Called when the
    /// canvas becomes the visible destination and when the thinkspace changes.
    private func registerThinkspaceSurface() {
        let surfaceId = resolvedThinkspaceSurfaceId
        if let existing = thinkspaceEditableSurface,
           existing.surfaceID == ThinkspaceEditableSurface.surfaceID(forThinkspaceId: surfaceId) {
            CosmoEditableSurfaceRegistry.shared.activateIfNeeded(surfaceID: existing.surfaceID)
            return
        }
        if let previous = thinkspaceEditableSurface {
            CosmoEditableSurfaceRegistry.shared.unregister(previous)
        }
        let surface = ThinkspaceEditableSurface(
            thinkspaceId: surfaceId,
            spatialEngine: spatialEngine,
            clusterEngine: clusterEngine
        )
        thinkspaceEditableSurface = surface
        CosmoEditableSurfaceRegistry.shared.register(surface)
        CosmoInlineAssistantStore.shared.activateSessionIfIdle(surfaceID: surface.surfaceID)
    }

    // MARK: - Approved canvas-plan cluster ops

    /// Create a cluster from an approved organize plan — same engine path as
    /// the manual cluster popover, plus the plan's intent sentence.
    private func applyPlannedClusterCreation(name: String, blockUUIDs: [String], intent: String?) {
        let knownUUIDs = Set(spatialEngine.blocks.map(\.entityUuid))
        let members = blockUUIDs.filter { knownUUIDs.contains($0) }
        guard !members.isEmpty else { return }
        clusterEngine.createUserCluster(
            name: name,
            colorIndex: clusterEngine.userClusters.count % CanvasCluster.paletteHexes.count,
            blockUUIDs: members,
            blocks: spatialEngine.blocks,
            thinkspaceId: thinkspaceId,
            intent: intent
        )
    }

    /// True when a plan notification targets THIS canvas's thinkspace.
    /// Untargeted (legacy) payloads fall back to the old behavior: the active
    /// canvas handles them.
    private func planTargetMatchesThisCanvas(_ userInfo: [AnyHashable: Any]?) -> Bool {
        guard let target = userInfo?["thinkspaceId"] as? String, !target.isEmpty else {
            return true
        }
        return (thinkspaceId ?? "home") == target
    }

    /// INVARIANT (user-mandated): organizing the canvas never leaves cluster
    /// regions overlapping — packed close, never touching. The plan decides
    /// membership; this deterministic pass owns geometry. Zones (Command
    /// Center) are fixed obstacles: they push clusters but never move.
    /// SCOPE INVARIANT: operates ONLY on clusters belonging to this canvas's
    /// thinkspace and persists explicitly to it — an unscoped pass once let one
    /// thinkspace's clusters overwrite another's saved layout.
    private func resolvePlannedClusterOverlaps() {
        let currentScope = thinkspaceId ?? "home"
        let clusters = clusterEngine.userClusters.filter {
            ($0.thinkspaceId ?? "home") == currentScope
                && $0.boundingRect.width > 0
                && $0.boundingRect.height > 0
        }
        guard clusters.count > 1 else { return }

        let boxes = clusters.map {
            CanvasClusterLayoutResolver.Box(id: $0.id, rect: $0.boundingRect, isFixed: $0.isZone)
        }
        let displacements = CanvasClusterLayoutResolver.displacements(for: boxes)
        guard !displacements.isEmpty else { return }

        withAnimation(ProMotionSprings.gentle) {
            for cluster in clusters {
                guard let delta = displacements[cluster.id] else { continue }
                let memberUUIDs = Set(clusterEngine.memberBlockUUIDs(for: cluster.id))
                for index in spatialEngine.blocks.indices
                where memberUUIDs.contains(spatialEngine.blocks[index].entityUuid) {
                    let block = spatialEngine.blocks[index]
                    let newPosition = CGPoint(
                        x: block.position.x + delta.width,
                        y: block.position.y + delta.height
                    )
                    spatialEngine.blocks[index].position = newPosition
                    spatialEngine.updateBlockPosition(block.id, position: newPosition)
                }
                clusterEngine.offsetClusterRect(id: cluster.id, by: delta)
            }
        }
        clusterEngine.persistClusters(thinkspaceId: thinkspaceId)
    }

    /// Move blocks into an existing cluster, matched by name (the plan speaks
    /// in the digest's vocabulary, which lists clusters by name).
    private func applyPlannedClusterMove(clusterName: String, blockUUIDs: [String]) {
        let normalized = clusterName.lowercased().trimmingCharacters(in: .whitespaces)
        guard let cluster = clusterEngine.userClusters.first(where: {
            $0.name.lowercased().trimmingCharacters(in: .whitespaces) == normalized
        }) else { return }
        let knownUUIDs = Set(spatialEngine.blocks.map(\.entityUuid))
        for uuid in blockUUIDs where knownUUIDs.contains(uuid) {
            clusterEngine.addBlockToCluster(
                blockUUID: uuid,
                clusterId: cluster.id,
                blocks: spatialEngine.blocks
            )
        }
    }

    private func handleTap(blockId: String) {
        // Canvas selection is exclusive: a selected/highlighted cluster should
        // never stay active after the user selects a block.
        clearCanvasClusterDropPreview()
        clusterEngine.selectCluster(nil)

        // Only mutate the two blocks that actually changed (old selection + new selection)
        // to avoid copying/reassigning the entire blocks array and triggering a full canvas re-render.
        let previousId = selectedBlockId
        selectedBlockId = blockId

        // Deselect previous
        if let prevId = previousId, prevId != blockId,
           let prevIndex = spatialEngine.blocks.firstIndex(where: { $0.id == prevId }) {
            spatialEngine.blocks[prevIndex].isSelected = false
        }

        // Select new
        if let newIndex = spatialEngine.blocks.firstIndex(where: { $0.id == blockId }) {
            spatialEngine.blocks[newIndex].isSelected = true
        }

        // Selecting a text-bearing block makes it the inline assistant's editable
        // surface, so "tighten this sticky" works without opening focus mode.
        updateInlineEditableSurface(forBlockId: blockId)
    }

    private func updateInlineEditableSurface(forBlockId blockId: String) {
        guard let block = spatialEngine.blocks.first(where: { $0.id == blockId }),
              CanvasBlockEditableSurface.supports(block.entityType) else { return }

        if let existing = selectedBlockEditableSurface, existing.atomUUID == block.entityUuid {
            CosmoEditableSurfaceRegistry.shared.activate(surfaceID: existing.surfaceID)
            return
        }

        let atomUUID = block.entityUuid
        Task { @MainActor in
            guard let atom = try? await AtomRepository.shared.fetch(uuid: atomUUID),
                  // Guard against a selection change racing the fetch.
                  selectedBlockId == blockId else { return }
            if let previous = selectedBlockEditableSurface {
                CosmoEditableSurfaceRegistry.shared.unregister(previous)
            }
            let surface = CanvasBlockEditableSurface(atom: atom)
            selectedBlockEditableSurface = surface
            CosmoEditableSurfaceRegistry.shared.register(surface)
        }
    }

    /// Glide the camera to frame a block — the agent's spatial "show me" primitive.
    /// Pulses the block's selection so the eye lands on it after the glide.
    private func flyCameraToBlock(atomUUID: String) {
        guard let block = spatialEngine.blocks.first(where: { $0.entityUuid == atomUUID }) else { return }

        let blockCenter = CGPoint(
            x: block.position.x + block.size.width / 2,
            y: block.position.y + block.size.height / 2
        )

        // Frame at a readable zoom: keep the current scale when it's already
        // comfortable, otherwise settle at 1.0.
        var targetTransform = viewportTransform
        targetTransform.committedScale = (0.7...1.6).contains(canvasScale) ? canvasScale : 1.0
        targetTransform.gestureMagnification = 1.0
        targetTransform.gesturePanOffset = .zero

        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            canvasScale = targetTransform.committedScale
            canvasOffset = targetTransform.centeringOffset(for: blockCenter)
        }

        handleTap(blockId: block.id)
    }

    private func handleEmptyCanvasDoubleClick() {
        let newScale = CanvasZoomPolicy.emptySpaceDoubleClickScale(
            currentScale: canvasScale,
            minScale: minScale,
            maxScale: maxScale
        )
        guard newScale != canvasScale else { return }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            canvasScale = newScale
        }
    }

    private func openBlockInFocusMode(_ block: CanvasBlock) {
        AppPerformanceInstrumentation.trace("CANVAS openBlockInFocusMode \(block.entityType.rawValue)#\(block.entityId)")
        if block.entityType == .note, let thinkspaceId,
           let atom = SpaceWorkspaceStore.shared.snapshots[thinkspaceId]?.atomsByUUID[block.entityUuid] {
            SpaceWorkspaceStore.shared.open(atom, in: thinkspaceId)
            return
        }
        guard [.idea, .content, .research, .connection, .cosmoAI].contains(block.entityType) else {
            return
        }
        NotificationCenter.default.post(
            name: .enterFocusMode,
            object: nil,
            userInfo: ["type": block.entityType, "id": block.entityId]
        )
    }

    // MARK: - Voice Command Handlers
    private func handlePlaceBlocks(notification: Notification, canvasSize: CGSize) {
        guard let userInfo = notification.userInfo,
              let query = userInfo["query"] as? String,
              let entityTypeString = userInfo["entityType"] as? String,
              let quantity = userInfo["quantity"] as? Int else {
            return
        }

        // Ignore if Focus Mode is active (let DocumentBlocksLayer handle it)
        if appState.focusedEntity != nil {
            print("🚫 CanvasView ignoring placement command because Focus Mode is active")
            return
        }

        let entityType = EntityType(rawValue: entityTypeString) ?? .idea
        let layoutString = userInfo["layout"] as? String ?? "orbital"
        let layout = LayoutStyle(rawValue: layoutString) ?? .orbital

        // Optional: place relative to an anchor block ("to the right of this block", etc.)
        let anchorBlockId = userInfo["anchorBlockId"] as? String
        let placement = (userInfo["placement"] as? String)?.lowercased()
        let spacing = userInfo["spacing"] as? CGFloat ?? 360

        var centerOverride: CGPoint? = nil
        if let anchorBlockId,
           let placement,
           let anchor = spatialEngine.blocks.first(where: { $0.id == anchorBlockId }) {
            let dx = (anchor.size.width / 2) + spacing
            let dy = (anchor.size.height / 2) + spacing

            switch placement {
            case "right":
                centerOverride = CGPoint(x: anchor.position.x + dx, y: anchor.position.y)
            case "left":
                centerOverride = CGPoint(x: anchor.position.x - dx, y: anchor.position.y)
            case "above", "up", "top":
                centerOverride = CGPoint(x: anchor.position.x, y: anchor.position.y + dy)
            case "below", "under", "down", "bottom":
                centerOverride = CGPoint(x: anchor.position.x, y: anchor.position.y - dy)
            default:
                break
            }
        }

        Task {
            try? await spatialEngine.placeBlocks(
                query: query,
                entityType: entityType,
                quantity: quantity,
                layout: layout,
                canvasSize: canvasSize,
                centerOverride: centerOverride
            )
        }
    }

    private func handleMoveBlocks(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let directionString = userInfo["direction"] as? String else {
            return
        }

        let direction = Direction(rawValue: directionString) ?? .right
        let distance = userInfo["distance"] as? CGFloat ?? 100

        spatialEngine.moveBlocks(direction: direction, distance: distance)
    }

    // MARK: - Magical Arrangement Handler
    private func handleArrangeBlocks(notification: Notification, canvasSize: CGSize) {
        guard let userInfo = notification.userInfo,
              let styleString = userInfo["style"] as? String,
              let style = LayoutStyle(rawValue: styleString) else {
            return
        }

        // Instant, magical arrangement!
        spatialEngine.arrangeBlocks(style: style, canvasSize: canvasSize)
    }

    // MARK: - Cosmo AI Block Creation
    private func handleCreateCosmoAIBlock(notification: Notification) {
        // Skip if focus mode is active - FocusCanvasView handles it there
        guard appState.focusedEntity == nil else {
            print("⏭️ Skipping Cosmo AI block creation on main canvas - focus mode active")
            return
        }

        var screenPosition = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

        if let userInfo = notification.userInfo,
           let pos = userInfo["position"] as? CGPoint {
            screenPosition = pos
        }

        // Convert screen position to canvas position (accounting for zoom)
        let canvasPosition = screenToCanvasPosition(screenPosition)

        let query = notification.userInfo?["query"] as? String
        let mode = notification.userInfo?["mode"] as? String

        // Create the Cosmo AI block with query and mode for auto-execution
        let block = CanvasBlock.cosmoAIBlock(position: canvasPosition, query: query, mode: mode)

        Task {
            await spatialEngine.addBlock(block, persist: true)
        }

        if let query = query, !query.isEmpty {
            print("✨ Created Cosmo AI block with auto-query: \(query)")
        } else {
            print("✨ Created Cosmo AI block at \(canvasPosition)")
        }
    }

    // MARK: - Note Block Creation
    private func handleCreateNoteBlock(notification: Notification) {
        var screenPosition = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

        if let userInfo = notification.userInfo,
           let pos = userInfo["position"] as? CGPoint {
            screenPosition = pos
        }

        // Convert screen position to canvas position (accounting for zoom)
        let canvasPosition = screenToCanvasPosition(screenPosition)

        createAtomBackedNoteBlock(at: canvasPosition)
    }

    // MARK: - Block Removal

    /// Shared delete path for every block-removal entry point: registers undo and,
    /// for freeform note/sticky blocks with no backing atom, materializes one first
    /// so the text stays reachable after the canvas block is gone.
    private func removeBlockSafely(_ blockId: String) {
        guard let block = spatialEngine.blocks.first(where: { $0.id == blockId }) else {
            Task {
                await spatialEngine.removeBlock(blockId)
            }
            return
        }

        // Snapshot block before removal for undo
        CosmoUndoManager.shared.register(
            DeleteBlockAction(block: block, spatialEngine: spatialEngine)
        )

        Task { @MainActor in
            await materializeBackingAtomIfNeeded(for: block)
            await spatialEngine.removeBlock(blockId)
        }
    }

    /// Atomless sticky/note blocks keep their only copy of the text in
    /// canvas_blocks.note_content — soft-deleting the row would strand it.
    /// Create a backing atom first (same flow StickyNoteBlockView uses when
    /// opening focus mode) so the content remains reachable in the library.
    ///
    /// Returns the resolved backing atom's UUID (existing, freshly created, or
    /// the block's own uuid for already-backed blocks) so a delete path can
    /// tombstone it — or nil when there is nothing to back (empty atomless note).
    @discardableResult
    private func materializeBackingAtomIfNeeded(for block: CanvasBlock) async -> String? {
        guard block.entityType == .note || block.entityType == .stickyNote,
              block.entityId <= 0 else { return block.entityUuid.isEmpty ? nil : block.entityUuid }
        let content = block.metadata["content"] ?? ""
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return block.entityUuid.isEmpty ? nil : block.entityUuid
        }
        // A backing atom may already exist under this uuid (e.g. created on close)
        if !block.entityUuid.isEmpty,
           (try? await AtomRepository.shared.fetch(uuid: block.entityUuid)) != nil {
            return block.entityUuid
        }

        do {
            var newAtom = Atom.new(
                type: block.entityType == .stickyNote ? .stickyNote : .note,
                title: block.metadata["title"],
                body: content
            )
            let bodyDocument = RichDocumentPersistence.loadBlockDocument(
                key: RichDocumentMetadataKeys.bodyDocument,
                metadata: block.metadata,
                fallbackPlainText: content
            )
            let fields = RichDocumentPersistence.writeAtomDocuments(
                existingMetadata: newAtom.metadata,
                titleDocument: nil,
                bodyDocument: bodyDocument
            )
            newAtom.metadata = fields.metadata
            if !block.entityUuid.isEmpty {
                newAtom.uuid = block.entityUuid
            }
            let atomId = try await CosmoDatabase.shared.asyncWrite { db -> Int64 in
                try newAtom.insert(db)
                let insertedAtomId = db.lastInsertedRowID
                try db.execute(
                    sql: "UPDATE canvas_blocks SET entity_id = ?, entity_uuid = ? WHERE id = ?",
                    arguments: [insertedAtomId, newAtom.uuid, block.id]
                )
                return insertedAtomId
            }
            print("🗂️ Materialized backing atom \(atomId) before deleting block \(block.id)")
            return newAtom.uuid
        } catch {
            PersistenceHealth.note(.writeFailure, context: "canvas.deleteMaterialize", detail: "block \(block.id): \(error)")
            print("❌ Failed to materialize backing atom before delete: \(error)")
            return block.entityUuid.isEmpty ? nil : block.entityUuid
        }
    }

    private func handleRemoveBlock(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let blockId = userInfo["blockId"] as? String else {
            return
        }

        removeBlockSafely(blockId)
    }

    /// "Remove from thinkspace" tier: detach the atom from the CURRENT thinkspace
    /// (every placement of it in this space) but keep the atom alive in the
    /// Library and untouched in any other thinkspaces. Undoable — the atom is
    /// never tombstoned, so re-attaching can't strand a ghost block. Falls back
    /// to plain block removal for an atomless block, or when there's no thinkspace
    /// context (the home canvas) to scope to.
    /// "Remove from canvas" tier: the block leaves the world but the atom stays
    /// a member of this space (it waits in the tray). ⌘Z restores the exact
    /// placement. An atomless block has no membership to keep, so it falls
    /// through to plain removal.
    private func handleRemoveBlockFromCanvas(notification: Notification) {
        guard let blockId = notification.userInfo?["blockId"] as? String else { return }
        guard let block = spatialEngine.blocks.first(where: { $0.id == blockId }),
              !block.entityUuid.isEmpty,
              (spatialEngine.currentThinkspaceId ?? self.thinkspaceId) != nil else {
            removeBlockSafely(blockId)
            return
        }
        CosmoUndoManager.shared.register(UnplaceBlockAction(block: block, spatialEngine: spatialEngine))
        Task { @MainActor in
            _ = await spatialEngine.unplaceBlock(blockId)
            refreshLibraryInventory()
        }
    }

    private func handleRemoveAtomFromThinkspace(notification: Notification) {
        guard let blockId = notification.userInfo?["blockId"] as? String else { return }
        guard let block = spatialEngine.blocks.first(where: { $0.id == blockId }),
              !block.entityUuid.isEmpty,
              let thinkspaceId = spatialEngine.currentThinkspaceId ?? self.thinkspaceId else {
            removeBlockSafely(blockId)
            return
        }

        CosmoUndoManager.shared.register(
            DetachAtomAction(entityUuid: block.entityUuid, thinkspaceId: thinkspaceId, spatialEngine: spatialEngine)
        )
        let entityUuid = block.entityUuid
        Task { @MainActor in
            await spatialEngine.removeAtomFromThinkspace(entityUuid: entityUuid, thinkspaceId: thinkspaceId)
            refreshLibraryInventory()
        }
    }

    /// "Delete" tier: tombstone the atom (→ Recently Deleted) and drop its
    /// blocks everywhere. Mirrors `deleteLibraryItem` — the block leaves memory
    /// immediately, then the atom is soft-deleted (its cascade removes canvas
    /// placements on every device). An atomless note/sticky is materialized
    /// first so its typed text still lands in Recently Deleted (recoverable)
    /// instead of vanishing. Recovery is via Recently Deleted rather than ⌘Z
    /// (restoring the block alone would strand a ghost — tombstone-cascade law).
    private func handleDeleteAtomEntirely(notification: Notification) {
        guard let blockId = notification.userInfo?["blockId"] as? String else { return }
        guard let block = spatialEngine.blocks.first(where: { $0.id == blockId }) else {
            Task { await spatialEngine.removeBlock(blockId) }
            return
        }

        Task { @MainActor in
            let backingUuid = await materializeBackingAtomIfNeeded(for: block)
            await spatialEngine.removeBlock(blockId)
            if let backingUuid, !backingUuid.isEmpty {
                do {
                    try await AtomRepository.shared.delete(uuid: backingUuid)
                } catch {
                    PersistenceHealth.note(.writeFailure, context: "canvas.deleteAtomEntirely", detail: "atom \(backingUuid.prefix(8)): \(error)")
                }
            }
            refreshLibraryInventory()
        }
    }

    // MARK: - Inbox Block Handlers

    private func handleCreateInboxBlock(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let block = userInfo["block"] as? InboxViewBlock else {
            print("⚠️ No inbox block in notification")
            return
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            inboxBlocks.append(block)
        }

        // Persist immediately so the new block survives app restart
        saveInboxBlockPositions()

        print("📬 Created inbox block: \(block.title)")
    }

    private func handleCloseInboxBlock(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let blockId = userInfo["blockId"] as? String else {
            print("⚠️ No blockId in close notification")
            return
        }

        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            inboxBlocks.removeAll { $0.id.uuidString == blockId }
        }

        // Persist the removal so it doesn't reappear on app restart
        saveInboxBlockPositions()

        print("📪 Closed inbox block: \(blockId)")
    }

    private func handleRefreshThinkspacePlacements(notification: Notification) {
        let requestedThinkspaceId = notification.userInfo?["thinkspaceId"] as? String
        guard requestedThinkspaceId == thinkspaceId else { return }

        Task { @MainActor in
            await spatialEngine.loadBlocks(for: "home", documentId: 0, thinkspaceId: thinkspaceId)
            // Ownership guard: a thinkspace switch during the load must not
            // get this space's clusters stamped onto it.
            let refreshed = await clusterEngine.computeUserClusters(
                thinkspaceId: thinkspaceId,
                blocks: spatialEngine.blocks
            )
            guard spatialEngine.currentThinkspaceId == thinkspaceId else { return }
            if let refreshed {
                clusterEngine.userClusters = refreshed
            }
        }
    }

    private func handleUpdateInboxBlockPosition(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let blockIdString = userInfo["blockId"] as? String,
              let blockId = UUID(uuidString: blockIdString),
              let x = userInfo["x"] as? CGFloat,
              let y = userInfo["y"] as? CGFloat else {
            print("⚠️ Invalid inbox block position update")
            return
        }

        let isDragging = userInfo["isDragging"] as? Bool ?? false

        if let index = inboxBlocks.firstIndex(where: { $0.id == blockId }) {
            // Update position immediately (no animation during drag for smooth tracking)
            inboxBlocks[index].x = x
            inboxBlocks[index].y = y

            // Only save to UserDefaults when drag ends (not during drag)
            if !isDragging {
                saveInboxBlockPositions()
                print("📍 Saved inbox block position: \(blockIdString) -> (\(x), \(y))")
            }
        }
    }

    private func handleUpdateInboxBlockSize(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let blockIdString = userInfo["blockId"] as? String,
              let blockId = UUID(uuidString: blockIdString),
              let width = userInfo["width"] as? CGFloat,
              let height = userInfo["height"] as? CGFloat else {
            print("⚠️ Invalid inbox block size update")
            return
        }

        if let index = inboxBlocks.firstIndex(where: { $0.id == blockId }) {
            // Update size
            inboxBlocks[index].width = width
            inboxBlocks[index].height = height

            // Apply position adjustment to keep top-left corner anchored
            if let posAdjustX = userInfo["positionAdjustX"] as? CGFloat,
               let posAdjustY = userInfo["positionAdjustY"] as? CGFloat {
                inboxBlocks[index].x += posAdjustX
                inboxBlocks[index].y += posAdjustY
            }

            // Persist to UserDefaults
            saveInboxBlockPositions()
            print("📐 Saved inbox block size: \(blockIdString) -> (\(width) x \(height))")
        }
    }

    private func saveInboxBlockPositions() {
        do {
            let data = try JSONEncoder().encode(inboxBlocks)
            UserDefaults.standard.set(data, forKey: "inboxBlockPositions")
        } catch {
            PersistenceHealth.note(.writeFailure, context: "canvas.saveInboxBlockPositions", detail: "\(error)")
            print("⚠️ Failed to save inbox block positions: \(error)")
        }
    }

    private func loadInboxBlockPositions() {
        guard let data = UserDefaults.standard.data(forKey: "inboxBlockPositions") else { return }
        do {
            let blocks = try JSONDecoder().decode([InboxViewBlock].self, from: data)
            inboxBlocks = blocks
            print("📬 Loaded \(blocks.count) inbox blocks from storage")
        } catch {
            print("⚠️ Failed to load inbox block positions: \(error)")
        }
    }

    private func handleOpenSelectedBlockInFocusMode() {
        guard let blockId = selectedBlockId,
              let block = spatialEngine.blocks.first(where: { $0.id == blockId }) else {
            print("⚠️ No block selected to open in focus mode")
            return
        }

        // Only applicable types can enter focus mode
        if [.idea, .content, .research, .connection].contains(block.entityType) {
            NotificationCenter.default.post(
                name: .enterFocusMode,
                object: nil,
                userInfo: ["type": block.entityType, "id": block.entityId]
            )
        }
    }

    // MARK: - Smart Block Reference Handlers (by ID)

    private func handleDeleteSpecificBlock(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let blockId = userInfo["blockId"] as? String else {
            return
        }

        removeBlockSafely(blockId)
        print("🗑️ Deleted block by ID: \(blockId)")
    }

    /// Rebuild a duplicate with a fresh block id (copying the source would make
    /// saveBlock UPDATE the original row by id, moving it instead of duplicating).
    /// Freeform note/sticky/content blocks also get a fresh entityUuid so the
    /// duplicate-entity guards don't reject them; their content metadata rides along.
    private func duplicatedBlock(from block: CanvasBlock) -> CanvasBlock {
        let isFreeform = (block.entityType == .note || block.entityType == .stickyNote || block.entityType == .content)
            && block.entityId <= 0
        return CanvasBlock(
            id: UUID().uuidString,
            position: CGPoint(x: block.position.x + 50, y: block.position.y + 50),
            size: block.size,
            scale: block.scale,
            rotation: block.rotation,
            isPinned: false,
            zIndex: block.zIndex,
            entityType: block.entityType,
            entityId: isFreeform ? -1 : block.entityId,
            entityUuid: isFreeform ? UUID().uuidString : block.entityUuid,
            title: block.title,
            subtitle: block.subtitle,
            metadata: block.metadata
        )
    }

    private func handleDuplicateBlock(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let blockId = userInfo["blockId"] as? String,
              let block = spatialEngine.blocks.first(where: { $0.id == blockId }) else {
            return
        }

        let newBlock = duplicatedBlock(from: block)
        Task {
            await spatialEngine.addBlock(newBlock, persist: true)
        }
        print("📋 Duplicated block: \(blockId)")
    }

    private func handleMoveBlockToTime(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let blockId = userInfo["blockId"] as? String,
              let time = userInfo["time"] as? String else {
            return
        }

        // Post to scheduler system to handle time-based placement
        NotificationCenter.default.post(
            name: .voiceCreateScheduleBlock,
            object: nil,
            userInfo: [
                "blockId": blockId,
                "time": time
            ]
        )
        print("📍 Moving block \(blockId) to time: \(time)")
    }

    // MARK: - Smart Block Reference Handlers (by Content Search)

    private func handleDeleteBlockByContent(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let searchQuery = userInfo["searchQuery"] as? String else {
            return
        }

        let entityType = userInfo["entityType"] as? String

        // Find block matching search query
        if let matchingBlock = findBlockByContent(searchQuery, entityType: entityType) {
            removeBlockSafely(matchingBlock.id)
            print("🗑️ Deleted block matching '\(searchQuery)'")
        } else {
            print("⚠️ No block found matching '\(searchQuery)'")
        }
    }

    private func handleDuplicateBlockByContent(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let searchQuery = userInfo["searchQuery"] as? String else {
            return
        }

        let entityType = userInfo["entityType"] as? String

        // Find and duplicate block matching search query
        if let matchingBlock = findBlockByContent(searchQuery, entityType: entityType) {
            let newBlock = duplicatedBlock(from: matchingBlock)
            Task {
                await spatialEngine.addBlock(newBlock, persist: true)
            }
            print("📋 Duplicated block matching '\(searchQuery)'")
        } else {
            print("⚠️ No block found matching '\(searchQuery)'")
        }
    }

    private func handleMoveBlockByContentToTime(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let searchQuery = userInfo["searchQuery"] as? String,
              let time = userInfo["time"] as? String else {
            return
        }

        let entityType = userInfo["entityType"] as? String

        // Find block and move to calendar time
        if let matchingBlock = findBlockByContent(searchQuery, entityType: entityType) {
            NotificationCenter.default.post(
                name: .voiceCreateScheduleBlock,
                object: nil,
                userInfo: [
                    "blockId": matchingBlock.id,
                    "title": matchingBlock.title,
                    "time": time
                ]
            )
            print("📍 Moving block matching '\(searchQuery)' to time: \(time)")
        } else {
            print("⚠️ No block found matching '\(searchQuery)'")
        }
    }

    // MARK: - Voice Command Handlers (LLM-First)

    /// Handle placing a newly created entity on canvas from voice command
    private func handlePlaceEntityOnCanvas(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let entityType = userInfo["entityType"] as? String,
              let title = userInfo["title"] as? String else {
            print("⚠️ placeEntityOnCanvas: Missing required fields")
            return
        }

        let entityId = userInfo["entityId"] as? Int64 ?? -1
        let entityUUID = userInfo["entityUUID"] as? String ?? UUID().uuidString
        let content = userInfo["content"] as? String ?? ""
        let positionString = userInfo["position"] as? String ?? "center"
        let targetBlockQuery = userInfo["targetBlockQuery"] as? String

        // Resolve position using PositionResolver
        let canvasSize = spatialEngine.blocks.isEmpty
            ? CGSize(width: 1920, height: 1080)
            : CGSize(width: 1920, height: 1080) // Will be updated by canvas bounds

        let position = PositionResolver.shared.resolve(
            positionString,
            targetBlockQuery: targetBlockQuery,
            canvasSize: canvasSize,
            selectedBlock: spatialEngine.blocks.first { $0.isSelected },
            allBlocks: spatialEngine.blocks
        )

        // Find non-overlapping position
        let finalPosition = PositionResolver.shared.findNonOverlappingPosition(
            near: position,
            existingBlocks: spatialEngine.blocks,
            canvasSize: canvasSize
        )

        // Create the block
        let block = CanvasBlock(
            position: finalPosition,
            size: CGSize(width: 280, height: 200),
            entityType: EntityType(rawValue: entityType) ?? .idea,
            entityId: entityId,
            entityUuid: entityUUID,
            title: title,
            subtitle: content.isEmpty ? "Created by voice" : String(content.prefix(100)),
            metadata: ["created": ISO8601.string(from: Date())]
        )

        // Add to canvas with spring animation
        Task { @MainActor in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                spatialEngine.blocks.append(block)
            }
            await spatialEngine.saveBlock(block)
            print("✅ Placed \(entityType) block on canvas: \(title) at \(finalPosition)")
        }
    }

    /// Handle block resize from voice command
    private func handleResizeSelectedBlock(notification: Notification) {
        guard let selectedBlock = spatialEngine.blocks.first(where: { $0.isSelected }),
              let index = spatialEngine.blocks.firstIndex(where: { $0.id == selectedBlock.id }) else {
            print("⚠️ resizeSelectedBlock: No block selected")
            return
        }

        let width = notification.userInfo?["width"] as? CGFloat
        let height = notification.userInfo?["height"] as? CGFloat
        let scale = notification.userInfo?["scale"] as? CGFloat ?? 1.0

        // Calculate new size
        var newSize = selectedBlock.size
        if let w = width { newSize.width = w }
        if let h = height { newSize.height = h }
        if scale != 1.0 {
            newSize.width *= scale
            newSize.height *= scale
        }

        // Apply resize with animation
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            spatialEngine.blocks[index].size = newSize
        }

        // Recompute cluster bounds so zones expand/shrink with resized blocks
        clusterEngine.updateUserClusterBounds(blocks: spatialEngine.blocks)

        print("✅ Resized block to \(newSize)")
    }

    // MARK: - Entity Creation Helpers (Immediate DB-backed blocks)

    private func createIdeaBlock(at position: CGPoint, prefillContent: String? = nil, prefillTitle: String? = nil) {
        Task { @MainActor in
            do {
                let content = prefillContent ?? ""
                let titleFromContent: String = prefillTitle ?? {
                    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return "New Idea" }
                    let firstLine = trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? trimmed
                    return String(firstLine.prefix(60))
                }()

                let savedIdea = try await CosmoDatabase.shared.asyncWrite { db -> Idea in
                    var idea = Idea.new(title: titleFromContent, content: content)
                    try idea.insert(db)
                    idea.id = db.lastInsertedRowID
                    return idea
                }

                let block = CanvasBlock.fromIdea(savedIdea, position: position)
                await spatialEngine.addBlock(block, persist: true)
                print("💡 Created idea block: ID \(savedIdea.id ?? -1)")
            } catch {
                PersistenceHealth.note(.writeFailure, context: "canvas.createIdeaBlock", detail: "\(error)")
                print("❌ Failed to create idea in database: \(error)")

                // Fallback: create block without database entry (temporary)
                let fallbackBlock = CanvasBlock(
                    position: position,
                    size: CGSize(width: 280, height: 200),
                    entityType: .idea,
                    entityId: -1,
                    entityUuid: UUID().uuidString,
                    title: "New Idea",
                    subtitle: "Tap to edit…",
                    metadata: ["created": ISO8601.string(from: Date())]
                )
                await spatialEngine.addBlock(fallbackBlock, persist: false)
            }
        }
    }

    private func createContentBlock(at position: CGPoint, prefillBody: String? = nil, prefillTitle: String? = nil) {
        Task { @MainActor in
            do {
                let title = prefillTitle ?? "New Content"
                let savedAtom = try await AtomRepository.shared.createContent(
                    title: title,
                    body: prefillBody
                )

                let block = CanvasBlock.fromAtom(savedAtom, position: position)
                await spatialEngine.addBlock(block, persist: true)
                print("✅ Created content block: ID \(savedAtom.id ?? -1)")
            } catch {
                PersistenceHealth.note(.writeFailure, context: "canvas.createContentBlock", detail: "\(error)")
                print("❌ Failed to create content atom: \(error)")
            }
        }
    }

    private func createTaskBlock(at position: CGPoint, prefillTitle: String? = nil, prefillDescription: String? = nil) {
        Task { @MainActor in
            do {
                let title = prefillTitle ?? "New Task"
                let savedTask = try await CosmoDatabase.shared.asyncWrite { db -> CosmoTask in
                    var task = CosmoTask.new(title: title, status: "todo")
                    if let description = prefillDescription {
                        task.description = description
                    }
                    try task.insert(db)
                    task.id = db.lastInsertedRowID
                    return task
                }

                let block = CanvasBlock.fromTask(savedTask, position: position)
                await spatialEngine.addBlock(block, persist: true)
                print("✅ Created task block: ID \(savedTask.id ?? -1)")
            } catch {
                PersistenceHealth.note(.writeFailure, context: "canvas.createTaskBlock", detail: "\(error)")
                print("❌ Failed to create task in database: \(error)")

                let fallbackBlock = CanvasBlock(
                    position: position,
                    size: CGSize(width: 280, height: 140),
                    entityType: .task,
                    entityId: -1,
                    entityUuid: UUID().uuidString,
                    title: prefillTitle ?? "New Task",
                    subtitle: nil,
                    metadata: ["status": "todo", "created": ISO8601.string(from: Date())]
                )
                await spatialEngine.addBlock(fallbackBlock, persist: false)
            }
        }
    }

    private func createNewResearchBlock(at position: CGPoint, prefillTitle: String? = nil, prefillSummary: String? = nil) {
        Task { @MainActor in
            do {
                let title = prefillTitle ?? "New Research"
                let savedResearch = try await CosmoDatabase.shared.asyncWrite { db -> Research in
                    var research = Research.new(title: title, query: nil, url: nil, sourceType: .unknown)
                    if let summary = prefillSummary {
                        research.summary = summary
                    }
                    try research.insert(db)
                    research.id = db.lastInsertedRowID
                    return research
                }

                let block = CanvasBlock.fromResearch(savedResearch, position: position)
                await spatialEngine.addBlock(block, persist: true)
                print("🔬 Created research block: ID \(savedResearch.id ?? -1)")
            } catch {
                PersistenceHealth.note(.writeFailure, context: "canvas.createResearchBlock", detail: "\(error)")
                print("❌ Failed to create research in database: \(error)")

                let fallbackBlock = CanvasBlock(
                    position: position,
                    size: CGSize(width: 300, height: 220),
                    entityType: .research,
                    entityId: -1,
                    entityUuid: UUID().uuidString,
                    title: prefillTitle ?? "New Research",
                    subtitle: "Start researching…",
                    metadata: ["created": ISO8601.string(from: Date())]
                )
                await spatialEngine.addBlock(fallbackBlock, persist: false)
            }
        }
    }

    // MARK: - Connection Creation Helper

    /// Creates a new Connection in the database and adds a block for it
    private func createConnectionBlock(at position: CGPoint) {
        print("🔗 createConnectionBlock called at position: \(position)")

        Task { @MainActor in
            do {
                // Create connection in database
                print("🔗 Creating connection in database…")
                let savedConnection = try await CosmoDatabase.shared.asyncWrite { db -> Atom in
                    var connection = Atom.new(type: .connection, title: "New Concept")
                    try connection.insert(db)
                    connection.id = db.lastInsertedRowID
                    print("🔗 Connection inserted with id: \(connection.id ?? -999)")
                    return connection
                }

                print("🔗 Database write complete, connection id: \(savedConnection.id ?? -999)")

                // Create block with real connection ID
                let block = CanvasBlock(
                    position: position,
                    size: CGSize(width: 320, height: 280),
                    entityType: .connection,
                    entityId: savedConnection.id ?? -1,
                    entityUuid: savedConnection.uuid,
                    title: "New Concept",
                    subtitle: "Define your mental model…",
                    metadata: ["created": ISO8601.string(from: Date())]
                )

                await spatialEngine.addBlock(block, persist: true)
                print("🔗 Created connection block: ID \(savedConnection.id ?? -1)")

            } catch {
                PersistenceHealth.note(.writeFailure, context: "canvas.createConnectionBlock", detail: "\(error)")
                print("❌ Failed to create connection in database: \(error)")
                print("❌ Error details: \(error.localizedDescription)")

                // Fallback: create block without database entry (temporary)
                // This ensures the user sees something even if DB fails
                let fallbackBlock = CanvasBlock(
                    position: position,
                    size: CGSize(width: 320, height: 280),
                    entityType: .connection,
                    entityId: -1,
                    entityUuid: UUID().uuidString,
                    title: "New Concept",
                    subtitle: "Define your mental model…",
                    metadata: ["created": ISO8601.string(from: Date())]
                )

                await spatialEngine.addBlock(fallbackBlock, persist: false)
                print("⚠️ Created fallback connection block without database entry")
            }
        }
    }

    private func createDeepDiveBlock(at position: CGPoint, prefillTitle: String? = nil) {
        Task { @MainActor in
            do {
                let title = prefillTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
                let parentThinkspaceUUIDs = [thinkspaceId ?? spatialEngine.currentThinkspaceId].compactMap { $0 }
                let deepDive = try await InquiryRepository.shared.createDeepDive(
                    title: (title?.isEmpty == false) ? (title ?? "New Deep Dive") : "New Deep Dive",
                    parentThinkspaceUUIDs: parentThinkspaceUUIDs
                )
                await DeepDiveAliasRegistry.shared.refresh()

                let block = CanvasBlock.fromAtom(deepDive, position: position)
                await spatialEngine.addBlock(block, persist: true)

                NotificationCenter.default.post(
                    name: CosmoNotification.Inquiry.openDeepDive,
                    object: nil,
                    userInfo: ["uuid": deepDive.uuid]
                )
            } catch {
                PersistenceHealth.note(.writeFailure, context: "canvas.createDeepDiveBlock", detail: "\(error)")
                print("❌ Failed to create Deep Dive: \(error)")
            }
        }
    }

    // MARK: - Open Entity On Canvas (from Cmd+K)

    /// Opens an existing entity as a floating block on the canvas,
    /// or focuses/scrolls to it if it already exists.
    /// Supports two notification formats:
    ///   - `["type": EntityType, "id": Int64]` (from code paths that have both)
    ///   - `["atomUUID": String]` (from addSwipeToCanvas, addIdeaToCanvas, etc.)
    private func handleOpenEntityOnCanvas(notification: Notification) {
        guard let userInfo = notification.userInfo else {
            print("⚠️ handleOpenEntityOnCanvas: missing userInfo")
            return
        }

        // Path 1: Direct type + id (from code paths that have both)
        if let entityType = userInfo["type"] as? EntityType,
           let entityId = userInfo["id"] as? Int64 {
            Task { @MainActor in
                await openOrCreateBlock(entityType: entityType, entityId: entityId)
            }
            return
        }

        // Path 2: atomUUID (from addSwipeToCanvas, addIdeaToCanvas, etc.)
        if let atomUUID = userInfo["atomUUID"] as? String {
            Task {
                guard let atom = try? await AtomRepository.shared.fetch(uuid: atomUUID) else {
                    print("⚠️ handleOpenEntityOnCanvas: atom not found for UUID \(atomUUID)")
                    return
                }
                let entityType = EntityType(rawValue: atom.type.rawValue) ?? .research
                let entityId = atom.id ?? Int64(0)
                await openOrCreateBlock(entityType: entityType, entityId: entityId, atom: atom)
            }
            return
        }

        print("⚠️ handleOpenEntityOnCanvas: missing type/id or atomUUID")
    }

    /// Places atoms dragged out of the Command-K palette at the drop point.
    /// Multi-select drops cascade so nothing lands perfectly stacked.
    private func handleCommandKAtomDrop(uuids: [String], canvasPosition: CGPoint) {
        CommandKDragSession.shared.end()
        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)

        Task { @MainActor in
            for (index, uuid) in uuids.enumerated() {
                guard let atom = try? await AtomRepository.shared.fetch(uuid: uuid) else {
                    print("⚠️ handleCommandKAtomDrop: atom not found for UUID \(uuid)")
                    continue
                }
                let entityType = EntityType(rawValue: atom.type.rawValue) ?? .research
                let position = CGPoint(
                    x: canvasPosition.x + CGFloat(index) * 28,
                    y: canvasPosition.y + CGFloat(index) * 28
                )
                await openOrCreateBlock(
                    entityType: entityType,
                    entityId: atom.id ?? 0,
                    atom: atom,
                    at: position
                )
            }
        }
    }

    /// Creates or focuses an existing canvas block for the given entity.
    /// When an `atom` is provided, uses `CanvasBlock.fromAtom` for proper metadata and sizing.
    /// A non-nil `requestedPosition` (canvas space) expresses placement intent —
    /// drops land there, and an existing block MOVES there instead of the
    /// default scroll-to-and-focus behavior.
    @MainActor
    private func openOrCreateBlock(
        entityType: EntityType,
        entityId: Int64,
        atom: Atom? = nil,
        at requestedPosition: CGPoint? = nil
    ) async {
        // Check if a block for this entity already exists (match by entityId or by UUID)
        let existingBlock: CanvasBlock? = {
            if let atom = atom {
                return spatialEngine.blocks.first(where: {
                    ($0.entityType == entityType && $0.entityId == entityId) ||
                    $0.entityUuid == atom.uuid
                })
            }
            return spatialEngine.blocks.first(where: {
                $0.entityType == entityType && $0.entityId == entityId
            })
        }()

        if let existingBlock = existingBlock {
            if let requestedPosition {
                // Placement intent (drag/drop): move the block to the point.
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    spatialEngine.updateBlockPosition(existingBlock.id, position: requestedPosition)
                }
                selectedBlockId = existingBlock.id
                return
            }

            // Focus and scroll to existing block
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                canvasOffset = CGSize(
                    width: -existingBlock.position.x + canvasSize.width / 2,
                    height: -existingBlock.position.y + canvasSize.height / 2
                )
            }

            // Select it - batch update to avoid race conditions
            var updatedBlocks = spatialEngine.blocks
            for index in updatedBlocks.indices {
                updatedBlocks[index].isSelected = (updatedBlocks[index].id == existingBlock.id)
            }
            spatialEngine.blocks = updatedBlocks
            selectedBlockId = existingBlock.id

            print("📍 Focused existing \(entityType) block for entity ID \(entityId)")
            return
        }

        let resolvedAtom: Atom?
        if let atom {
            resolvedAtom = atom
        } else {
            resolvedAtom = try? await AtomRepository.shared.fetch(id: entityId)
        }

        // New blocks land at the requested point, else viewport center
        let position = requestedPosition ?? CGPoint(
            x: canvasSize.width / 2 - canvasOffset.width,
            y: canvasSize.height / 2 - canvasOffset.height
        )

        // Create block — use CanvasBlock.fromAtom when atom is available for rich metadata + proper sizing
        let block: CanvasBlock
        if let atom = resolvedAtom {
            block = CanvasBlock.fromAtom(atom, position: position)
        } else {
            // Fallback: no atom available, create with basic metadata
            switch entityType {
            case .idea, .content, .research, .connection:
                block = CanvasBlock(
                    position: position,
                    size: CGSize(width: 320, height: 280),
                    entityType: entityType,
                    entityId: entityId,
                    entityUuid: UUID().uuidString,
                    title: entityType.rawValue.capitalized,
                    subtitle: nil,
                    metadata: [:]
                )
            default:
                // For other types, open Focus Mode instead
                NotificationCenter.default.post(
                    name: .enterFocusMode,
                    object: nil,
                    userInfo: ["type": entityType, "id": entityId]
                )
                return
            }
        }

        await spatialEngine.addBlock(block, persist: true)
        selectedBlockId = block.id

        print("🆕 Created \(entityType) floating block for entity ID \(entityId)")
    }

    // MARK: - Cmd+V Paste to Canvas (Images + URLs)

    /// Handles Cmd+V paste: checks for image data first, then falls back to URL classification
    private func handleCanvasPaste() async {
        // Check for image data on clipboard first
        let pasteboard = NSPasteboard.general

        // Try image data (screenshots, copied images)
        if let imageData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            await createImageBlock(data: imageData, originalFilename: nil)
            return
        }

        // Try file URL (copied file from Finder) — images stay native image
        // blocks, every other file becomes a file portal.
        if let fileURLData = pasteboard.data(forType: .fileURL),
           let fileURL = URL(dataRepresentation: fileURLData, relativeTo: nil) {
            if let uti = try? fileURL.resourceValues(forKeys: [.contentTypeKey]).contentType,
               uti.conforms(to: .image),
               let data = try? Data(contentsOf: fileURL) {
                await createImageBlock(data: data, originalFilename: fileURL.lastPathComponent)
                return
            }
            if FilePortalImportService.acceptsFileURL(fileURL) {
                let position = CGPoint(
                    x: canvasSize.width / 2 - canvasOffset.width,
                    y: canvasSize.height / 2 - canvasOffset.height
                )
                await createFilePortalBlocks(fileURLs: [fileURL], position: position)
                return
            }
        }

        // Fall through to URL handling
        guard let clipboardString = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !clipboardString.isEmpty else { return }

        // Only handle URLs
        let lower = clipboardString.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return }

        // Classify URL
        let classifier = SwipeURLClassifier()
        let classification = classifier.classify(clipboardString)

        // Don't create blocks for raw text (shouldn't happen given URL guard, but be safe)
        guard classification.isUrl else { return }

        // Create atom based on classification
        var atom: Atom
        let isYouTube = classification.sourceType == .youtube || classification.sourceType == .youtubeShort

        if isYouTube {
            // YouTube → research atom (NOT swipe)
            atom = Research.new(
                title: "YouTube Video",
                url: clipboardString,
                sourceType: classification.sourceType
            )
            atom.processingStatus = "pending"
            if let videoId = classification.contentId {
                var richContent = ResearchRichContent()
                richContent.sourceType = classification.sourceType
                richContent.videoId = videoId
                atom.setRichContent(richContent)
            }
        } else {
            // Social platforms → swipe atom
            switch classification.sourceType {
            case .instagram, .instagramReel, .instagramPost, .instagramCarousel:
                let igType: ResearchRichContent.InstagramContentType = {
                    switch classification.sourceType {
                    case .instagramReel: return .reel
                    case .instagramCarousel: return .carousel
                    default: return .post
                    }
                }()
                atom = Atom.swipeFromInstagram(
                    instagramId: classification.contentId ?? "",
                    url: clipboardString,
                    hook: nil,
                    type: igType
                )
            case .twitter, .xPost:
                atom = Atom.swipeFromXPost(
                    tweetId: classification.contentId ?? "",
                    url: clipboardString,
                    hook: nil
                )
            case .threads:
                atom = Atom.swipeFromThreads(
                    threadId: classification.contentId ?? "",
                    url: clipboardString,
                    hook: nil
                )
            case .tiktok:
                atom = Atom.newSwipeFile(
                    url: clipboardString,
                    hook: nil,
                    sourceType: .tiktok,
                    contentSource: .clipboard
                )
            default:
                // Generic URL → research atom (not swipe)
                atom = Research.new(
                    title: "Research",
                    url: clipboardString,
                    sourceType: classification.sourceType
                )
                atom.processingStatus = "pending"
            }
        }

        // Save atom to database (return inserted copy to get auto-incremented ID)
        let atomToInsert = atom
        do {
            atom = try await CosmoDatabase.shared.asyncWrite { db in
                var inserted = atomToInsert
                try inserted.insert(db)
                return inserted
            }
        } catch {
            print("⚠️ [CanvasView] Failed to save pasted atom: \(error)")
            return
        }

        // Create block at center of current viewport
        let position = CGPoint(
            x: canvasSize.width / 2 - canvasOffset.width,
            y: canvasSize.height / 2 - canvasOffset.height
        )
        let block = CanvasBlock.fromAtom(atom, position: position)
        await spatialEngine.addBlock(block, persist: true)
        selectedBlockId = block.id
        rebuildMediaContentCache()
        

        if atom.isSwipeFileAtom {
            // A swipe pasted onto a canvas is still a capture: it joins an open
            // flow and refreshes the library. The block itself is the receipt.
            SwipeIntakeRouter.noteExternallyCreatedSwipe(atom, publishesReceipt: false)
        }

        print("📋 Pasted \(classification.sourceType.rawValue) URL → canvas block (uuid: \(atom.uuid))")

        // Trigger background processing
        let atomUUID = atom.uuid
        let sourceType = classification.sourceType
        Task {
            await processCanvasPastedAtom(uuid: atomUUID, sourceType: sourceType, contentId: classification.contentId)
        }
    }

    /// Handles dropping external content onto the canvas. A web link routes
    /// through the swipe front door and its block lands at the drop point;
    /// images keep the native image-block pipeline; every other file becomes
    /// a file portal.
    private func handleCanvasExternalDrop(providers: [NSItemProvider], canvasPosition: CGPoint) {
        Task {
            var webURL = await CanvasImageDropController.firstWebURL(from: providers)
            var viaSession = false
            if webURL == nil, let sessionURL = BrowserPaneLinkDragSession.consume() {
                // The pasteboard lost the link but the drag bridge kept it.
                webURL = sessionURL
                viaSession = true
            }
            let carriesImage = await CanvasImageDropController.carriesImagePayload(providers)
            let decision = CanvasExternalDropRouter.decision(webURL: webURL, carriesImage: carriesImage)
            CanvasDropDebugLog.note("handleExternalDrop: webURL=\(webURL ?? "nil") viaSession=\(viaSession) carriesImage=\(carriesImage) decision=\(decision)")
            if case .swipeCapture(let url) = decision {
                await createSwipeBlockFromDroppedURL(url, position: canvasPosition)
                return
            }

            if let image = await CanvasImageDropController.firstImage(from: providers) {
                CanvasDropDebugLog.note("handleExternalDrop: image path, \(image.data.count) bytes")
                await createImageBlock(
                    data: image.data,
                    originalFilename: image.originalFilename,
                    position: canvasPosition
                )
                return
            }

            let fileURLs = await CanvasImageDropController.fileURLs(from: providers)
                .filter { FilePortalImportService.acceptsFileURL($0) }
            guard !fileURLs.isEmpty else {
                CanvasDropDebugLog.note("handleExternalDrop: DEAD END — no web link, image data or portal-able files")
                print("⚠️ [CanvasView] Drop contained no web link, image data or portal-able files")
                return
            }
            await createFilePortalBlocks(fileURLs: fileURLs, position: canvasPosition)
        }
    }

    /// A link dropped onto the canvas is a capture AND a placement: the swipe
    /// is created through the ONE FRONT DOOR (dedup, receipt, undo, flow,
    /// analysis kick) and its block lands where the drag was released. Dedup
    /// adoption still places a block — dropping a post already in the library
    /// puts THAT swipe on the canvas rather than silently doing nothing.
    private func createSwipeBlockFromDroppedURL(_ url: String, position: CGPoint) async {
        CanvasDropDebugLog.note("createSwipeBlock: running front door for \(url)")
        guard let atom = await SwipeIntakeRouter.run(.url(url), captureMode: "canvas_drop") else {
            CanvasDropDebugLog.note("createSwipeBlock: front door returned NIL (capture failed) — error=\(SwipeIntakeReceiptCenter.shared.errorMessage ?? "none published")")
            return
        }
        let block = CanvasBlock.fromAtom(atom, position: position)
        await spatialEngine.addBlock(block, persist: true)
        selectedBlockId = block.id
        rebuildMediaContentCache()
        CanvasDropDebugLog.note("createSwipeBlock: placed block \(block.id) for atom \(atom.uuid) at \(position)")
        print("🔗 Dropped link → swipe canvas block (uuid: \(atom.uuid))")
    }

    /// Batch imports retain every successful item and place them without
    /// overlapping existing work. Switching Spaces cannot redirect the import.
    private func createFilePortalBlocks(fileURLs: [URL], position: CGPoint) async {
        guard let destination = spatialEngine.currentThinkspaceId else { return }
        let columns = max(1, min(4, Int(ceil(sqrt(Double(fileURLs.count))))))
        for (index, fileURL) in fileURLs.enumerated() {
            do {
                let imported = try await FilePortalImportService.shared.importFile(at: fileURL)
                try await SpaceMembershipService.add(imported.atom, to: destination)
                guard destination == spatialEngine.currentThinkspaceId else { continue }
                let anchor = CGPoint(x: position.x + CGFloat(index % columns) * 360,
                                     y: position.y + CGFloat(index / columns) * 380)
                let target = PositionResolver.shared.findNonOverlappingPosition(
                    near: anchor, existingBlocks: spatialEngine.blocks, canvasSize: canvasSize)
                if let block = await spatialEngine.placeMember(entityUuid: imported.atom.uuid, at: target) {
                    selectedBlockId = block.id
                }
            } catch {
                print("⚠️ [CanvasView] File portal import failed for \(fileURL.lastPathComponent): \(error.localizedDescription)")
                presentFilePortalImportError(error)
            }
        }
    }

    /// ⌘K / menu creation path: pick a file, portal it at the target position.
    private func presentFilePortalOpenPanel(at position: CGPoint) {
        let panel = NSOpenPanel()
        panel.title = isCanvasViewActive ? "Add File to Canvas" : "Add Material to Space"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls.filter { FilePortalImportService.acceptsFileURL($0) }
        guard !urls.isEmpty else { return }
        let place = isCanvasViewActive
        let destination = thinkspaceId
        let target = destination.flatMap { SpaceWorkspaceStore.shared.selectedItem(in: $0) }
        Task {
            if place { await createFilePortalBlocks(fileURLs: urls, position: position) }
            else if let destination {
                for url in urls {
                    do {
                        let imported = try await FilePortalImportService.shared.importFile(at: url)
                        if let target, target.spaceCompositionKind == .group {
                            try await SpaceCompositionService.addMembers([imported.atom.uuid], to: target.uuid, in: destination)
                        } else {
                            try await SpaceMembershipService.add(imported.atom, to: destination)
                            if let target {
                                try await SpaceCompositionService.attachReference(.init(sourceUUID: imported.atom.uuid,
                                    sourceTitle: imported.atom.title), to: target.uuid)
                            }
                        }
                    } catch { presentFilePortalImportError(error) }
                }
                refreshLibraryInventory()
            }
        }
    }

    /// User-initiated imports fail loudly (Finder-style alert), never silently.
    private func presentFilePortalImportError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn't import file"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    /// Saves image data to disk, creates an image atom, then places its canvas block.
    private func createImageBlock(data: Data, originalFilename: String?, position explicitPosition: CGPoint? = nil) async {
        do {
            let result = try ImageStore.save(data, originalFilename: originalFilename)
            let imageMeta = ImageMetadata(
                imagePath: result.path,
                originalFilename: originalFilename,
                width: result.width,
                height: result.height,
                fileSize: data.count
            )
            let metadataJson = try? JSONEncoder().encode(imageMeta)
            let metadataString = metadataJson.flatMap { String(data: $0, encoding: .utf8) }
            let atomToInsert = Atom.new(
                type: .image,
                title: CanvasImageDropController.imageTitle(originalFilename: originalFilename),
                body: result.path,
                metadata: metadataString
            )
            let atom = try await CosmoDatabase.shared.asyncWrite { db in
                var inserted = atomToInsert
                try inserted.insert(db)
                return inserted
            }
            let position = explicitPosition ?? CGPoint(
                x: canvasSize.width / 2 - canvasOffset.width,
                y: canvasSize.height / 2 - canvasOffset.height
            )
            let block = CanvasBlock.fromAtom(atom, position: position)
            await spatialEngine.addBlock(block, persist: true)
            selectedBlockId = block.id
            rebuildMediaContentCache()

            print("📋 Added image → canvas block (uuid: \(atom.uuid))")
        } catch {
            print("⚠️ [CanvasView] Failed to add image: \(error)")
        }
    }

    /// Background processing for a pasted atom — transcription, analysis, metadata enrichment
    private func processCanvasPastedAtom(uuid: String, sourceType: ResearchRichContent.SourceType, contentId: String?) async {
        let isYouTube = sourceType == .youtube || sourceType == .youtubeShort

        if isYouTube, let videoId = contentId {
            // YouTube research: fetch metadata + captions via YouTubeProcessor
            do {
                let ytData = try await YouTubeProcessor.shared.process(videoId: videoId)

                // Update atom with fetched data
                if var atom = try? await AtomRepository.shared.fetch(uuid: uuid) {
                    atom.title = ytData.title
                    atom.body = ytData.transcript.map(\.text).joined(separator: " ")
                    atom.thumbnailUrl = ytData.thumbnailURL?.absoluteString
                    atom.processingStatus = "complete"

                    // Update rich content with transcript
                    var richContent = atom.richContent ?? ResearchRichContent()
                    richContent.transcript = atom.body
                    richContent.transcriptStatus = ytData.transcriptStatus.rawValue
                    richContent.title = ytData.title
                    richContent.author = ytData.channelName
                    atom.setRichContent(richContent)

                    try await CosmoDatabase.shared.asyncWrite { db in
                        try atom.update(db)
                    }
                    print("✅ [CanvasView] YouTube processing complete for \(uuid)")
                }
            } catch {
                print("⚠️ [CanvasView] YouTube processing failed for \(uuid): \(error)")
                // Mark as complete even on failure so shimmer stops
                if var atom = try? await AtomRepository.shared.fetch(uuid: uuid) {
                    atom.processingStatus = "complete"
                    try? await CosmoDatabase.shared.asyncWrite { db in try atom.update(db) }
                }
            }
        } else {
            // Swipe processing: use existing pipeline
            SwipeProcessingService.shared.processSwipeInBackground(uuid: uuid)
            // SwipeProcessingService runs asynchronously — wait for it to finish
            // Poll briefly to detect completion for notification
            for _ in 0..<120 {
                try? await Task.sleep(for: .milliseconds(500))
                if !SwipeProcessingService.shared.isProcessing(uuid: uuid) { break }
            }
        }

        // Post completion notification so block views can refresh
        NotificationCenter.default.post(
            name: .canvasAtomProcessed,
            object: nil,
            userInfo: ["atomUUID": uuid]
        )
    }

    // MARK: - Ambient Pull-to-Canvas

    private func handlePullAmbientToCanvas(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let atomUUID = userInfo["atomUUID"] as? String,
              let sourceBlockUUID = userInfo["sourceBlockUUID"] as? String else { return }

        Task { @MainActor in
            guard let atom = try? await AtomRepository.shared.fetch(uuid: atomUUID) else {
                print("AmbientPull: atom not found for UUID \(atomUUID)")
                return
            }

            // Position 200px to the right of the source block
            let sourceBlock = spatialEngine.blocks.first(where: { $0.entityUuid == sourceBlockUUID })
            let position: CGPoint
            if let source = sourceBlock {
                position = CGPoint(
                    x: source.position.x + source.size.width + 200,
                    y: source.position.y
                )
            } else {
                position = CGPoint(
                    x: canvasSize.width / 2 - canvasOffset.width + 200,
                    y: canvasSize.height / 2 - canvasOffset.height
                )
            }

            // Create canvas block from atom
            let block = CanvasBlock.fromAtom(atom, position: position)

            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                spatialEngine.blocks.append(block)
            }
            await spatialEngine.saveBlock(block)

            // Create bidirectional AtomLink between source and pulled atom
            await createBidirectionalLink(sourceUUID: sourceBlockUUID, targetUUID: atomUUID)

            print("Ambient: Pulled \(atom.type.rawValue) '\(atom.title ?? "Untitled")' to canvas")
        }
    }

    /// Creates a bidirectional .related link between two atoms
    @MainActor
    private func createBidirectionalLink(sourceUUID: String, targetUUID: String) async {
        // Link source -> target
        if var sourceAtom = try? await AtomRepository.shared.fetch(uuid: sourceUUID) {
            var links = sourceAtom.linksList
            guard !links.contains(where: { $0.uuid == targetUUID && $0.type == AtomLinkType.related.rawValue }) else { return }
            links.append(AtomLink(linkType: .related, uuid: targetUUID))
            if let data = try? JSONEncoder().encode(links),
               let json = String(data: data, encoding: .utf8) {
                sourceAtom.links = json
                sourceAtom.updatedAt = ISO8601.string(from: Date())
                sourceAtom.localVersion += 1
                try? await AtomRepository.shared.update(sourceAtom)
            }
        }

        // Link target -> source
        if var targetAtom = try? await AtomRepository.shared.fetch(uuid: targetUUID) {
            var links = targetAtom.linksList
            guard !links.contains(where: { $0.uuid == sourceUUID && $0.type == AtomLinkType.related.rawValue }) else { return }
            links.append(AtomLink(linkType: .related, uuid: sourceUUID))
            if let data = try? JSONEncoder().encode(links),
               let json = String(data: data, encoding: .utf8) {
                targetAtom.links = json
                targetAtom.updatedAt = ISO8601.string(from: Date())
                targetAtom.localVersion += 1
                try? await AtomRepository.shared.update(targetAtom)
            }
        }
    }

    // MARK: - Content Search Helper

    private func findBlockByContent(_ query: String, entityType: String?) -> CanvasBlock? {
        let lowercaseQuery = query.lowercased()

        return spatialEngine.blocks.first { block in
            // Filter by entity type if specified
            if let typeString = entityType, typeString != "any" {
                if let type = EntityType(rawValue: typeString), block.entityType != type {
                    return false
                }
            }

            // Match against title or subtitle
            let titleMatch = block.title.lowercased().contains(lowercaseQuery)
            let subtitleMatch = block.subtitle?.lowercased().contains(lowercaseQuery) ?? false

            return titleMatch || subtitleMatch
        }
    }
}

// MARK: - Floating Block View
struct FloatingBlockView: View {
    let block: CanvasBlock
    @State private var isHovered = false
    private let referenceSize = CGSize(width: 280, height: 180)

    private var contentScale: CGFloat {
        let area = max(block.size.width * block.size.height, 1)
        let referenceArea = referenceSize.width * referenceSize.height
        return max(sqrt(area / referenceArea), 0.5)
    }

    private var unscaledSize: CGSize {
        CGSize(
            width: block.size.width / contentScale,
            height: block.size.height / contentScale
        )
    }

    // Get the pastel color for this entity type
    private var blockColor: Color {
        switch block.entityType {
        case .idea: return DS.entityIdea
        case .content: return DS.entityContent
        case .task: return DS.entityTask
        case .research: return DS.entityResearch
        case .note: return DS.entityNote
        case .cosmoAI: return DS.accent
        default: return DS.textMuted
        }
    }

    var body: some View {
        WindowChromeView(
            title: block.title,
            icon: block.entityType.icon,
            iconColor: blockColor,
            onClose: {
                NotificationCenter.default.post(
                    name: .removeBlock,
                    object: nil,
                    userInfo: ["blockId": block.id]
                )
            },
            onMinimize: nil,
            onMaximize: {
                // Enter focus mode
                NotificationCenter.default.post(
                    name: .enterFocusMode,
                    object: nil,
                    userInfo: ["type": block.entityType, "id": block.entityId]
                )
            }
        ) {
            VStack(alignment: .leading, spacing: 8) {
                // Subtitle/content preview
                if let subtitle = block.subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(4)
                }

                Spacer()

                // Metadata footer
                HStack(spacing: 8) {
                    ForEach(Array(block.metadata.prefix(2)), id: \.key) { key, value in
                        Text("\(key): \(value)")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.textMuted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(DS.borderSubtle.opacity(0.4))
                            .clipShape(.rect(cornerRadius: DS.radiusXSmall))
                    }

                    Spacer()

                    if block.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.textMuted)
                    }
                }
            }
            .padding(12)
            .frame(width: unscaledSize.width, height: max(unscaledSize.height - 36, 0))
        }
        .frame(width: unscaledSize.width, height: unscaledSize.height)
        .scaleEffect(contentScale, anchor: .topLeading)
        .frame(width: block.size.width, height: block.size.height, alignment: .topLeading)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button {
                NotificationCenter.default.post(
                    name: .openEntity,
                    object: nil,
                    userInfo: ["type": block.entityType, "id": block.entityId]
                )
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
            }

            Button {
                NotificationCenter.default.post(
                    name: .enterFocusMode,
                    object: nil,
                    userInfo: ["type": block.entityType, "id": block.entityId]
                )
            } label: {
                Label("Focus Mode", systemImage: "arrow.up.left.and.arrow.down.right")
            }

            Divider()

            Button {
                NotificationCenter.default.post(
                    name: .toggleBlockPin,
                    object: nil,
                    userInfo: ["blockId": block.id]
                )
            } label: {
                Label(block.isPinned ? "Unpin" : "Pin to Home", systemImage: block.isPinned ? "pin.slash" : "pin")
            }

            Button {
                NotificationCenter.default.post(
                    name: .duplicateBlock,
                    object: nil,
                    userInfo: ["blockId": block.id]
                )
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }

            Divider()

            Button(role: .destructive) {
                NotificationCenter.default.post(
                    name: .removeBlock,
                    object: nil,
                    userInfo: ["blockId": block.id]
                )
            } label: {
                Label("Remove from Canvas", systemImage: "trash")
            }
        }
    }
}

// MARK: - Canvas Controls
struct CanvasControls: View {
    var spatialEngine: SpatialEngine

    var body: some View {
        Button(action: { spatialEngine.clearCanvas() }) {
            Image(systemName: "trash")
                .font(.system(size: 16))
                .foregroundStyle(DS.textSecondary)
                .frame(width: 40, height: 40)
                .background(DS.surfaceElevated)
                .clipShape(.rect(cornerRadius: DS.radiusMedium - 2))
                .shadow(color: Color.black.opacity(0.08), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Grid Pattern View
struct GridPatternView: View {
    let transform: CanvasViewportTransform

    var body: some View {
        GeometryReader { geometry in
            let metrics = CanvasGridPatternMetrics(
                transform: transform,
                viewportSize: geometry.size
            )

            // Tiled-image grid: panning moves a cached tile pattern (pure
            // compositor translation) instead of rebuilding a ~1,400-ellipse
            // Path on the CPU every gesture frame. The tile only regenerates
            // when zoom crosses a ~2% spacing bucket; the correction scale
            // keeps dot geometry exact in between.
            if let plan = CanvasGridTilePlan(
                screenSpacing: metrics.screenSpacing,
                screenDotSize: metrics.screenDotSize,
                screenGridOrigin: metrics.screenGridOrigin,
                viewportSize: geometry.size
            ) {
                Image(nsImage: CanvasGridPatternCache.shared.image(
                    spacing: plan.tileSpacing,
                    dotSize: plan.tileDotSize,
                    tileMultiplier: plan.tileMultiplier
                ))
                .resizable(resizingMode: .tile)
                .interpolation(.medium)
                .frame(width: plan.frameSize.width, height: plan.frameSize.height)
                .scaleEffect(plan.correctionScale, anchor: .topLeading)
                .offset(x: plan.origin.x, y: plan.origin.y)
            }
        }
        .allowsHitTesting(false)
        .clipped()
    }
}

// MARK: - Thinkspace Aurora View (Subtle gradient zones)
struct ThinkspaceAuroraView: View {
    var body: some View {
        ZStack {
            // Top-left purple aurora
            RadialGradient(
                colors: [
                    DS.accent.opacity(0.015),
                    Color.clear
                ],
                center: UnitPoint(x: 0.1, y: 0.1),
                startRadius: 50,
                endRadius: 400
            )

            // Bottom-right green aurora
            RadialGradient(
                colors: [
                    DS.green.opacity(0.02),
                    Color.clear
                ],
                center: UnitPoint(x: 0.9, y: 0.85),
                startRadius: 50,
                endRadius: 350
            )

            // Center subtle blue
            RadialGradient(
                colors: [
                    CosmoColors.skyBlue.opacity(0.015),
                    Color.clear
                ],
                center: UnitPoint(x: 0.5, y: 0.5),
                startRadius: 100,
                endRadius: 500
            )
        }
    }
}

// MARK: - Thinkspace Film Grain (REMOVED — replaced with static FilmGrainOverlay)
// ThinkspaceFilmGrain was generating ~11,500 random ellipses per frame.
// Now uses FilmGrainOverlay from Core/FilmGrainOverlay.swift which pre-generates
// a tiled CGImage once and reuses it. Same visual effect, zero per-frame cost.

// MARK: - Per-Block Content
struct CanvasBlockStaticView: View, Equatable {
    let block: CanvasBlock
    let isMediaContent: Bool
    let isViewportActive: Bool
    var spaceID: String? = nil

    var body: some View {
        switch block.entityType {
        case .cosmoAI:
            CosmoAIBlockView(block: block)
        case .note:
            if let spaceID, let atom = compositionPortal {
                SpaceCompositionCanvasPortal(block: block, atom: atom, spaceID: spaceID)
            } else { NoteBlockView(block: block) }
        case .calendar:
            Text("Calendar")
                .font(DS.body)
                .foregroundStyle(DS.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .research:
            if isMediaContent {
                MediaBlockView(block: block, isViewportActive: isViewportActive)
            } else {
                ResearchBlockView(block: block, isViewportActive: isViewportActive)
            }
        case .connection:
            ConnectionBlockView(block: block)
        case .idea:
            IdeaBlockView(block: block)
        case .content:
            ContentBlockView(block: block)
        case .task:
            TaskBlockView(block: block)
        case .image:
            ImageBlockView(block: block)
        case .stickyNote:
            StickyNoteBlockView(block: block)
        case .liveQuery:
            LiveQueryBlockView(block: block)
        case .ideaBoard:
            IdeaBoardBlockView(block: block)
        case .template:
            TemplateBlockView(block: block)
        case .deepDive:
            DeepDivePortalBlockView(block: block)
        case .file:
            FilePortalBlockView(block: block, isViewportActive: isViewportActive)
        default:
            FloatingBlockView(block: block)
        }
    }

    private var compositionPortal: Atom? {
        guard let spaceID, let snapshot = SpaceWorkspaceStore.shared.snapshots[spaceID],
              let atom = snapshot.atomsByUUID[block.entityUuid], let kind = atom.spaceCompositionKind,
              kind != .page || !snapshot.children(of: atom.uuid).isEmpty else { return nil }
        return atom
    }
}

/// The canvas card opens the actual collection or composed work. Its small
/// contents preview never creates a second draft or an empty note wrapper.
private struct SpaceCompositionCanvasPortal: View {
    let block: CanvasBlock
    let atom: Atom
    let spaceID: String
    private var store: SpaceWorkspaceStore { .shared }
    private var items: [Atom] { store.items(in: atom, spaceID: spaceID) }
    private var kind: SpaceCompositionKind { atom.spaceCompositionKind ?? .page }
    private var images: [Atom] { Array(items.filter { $0.type == .image }.prefix(4)) }
    var body: some View {
        CosmoBlockWrapper(block: block, accentColor: DS.accent, icon: kind.symbol,
            title: atom.title ?? "Untitled", suppressGiltCorner: true, suppressAccentChip: true,
            onFocusMode: { store.open(atom, in: spaceID) }) {
            VStack(alignment: .leading, spacing: DS.space16) {
                HStack {
                    Text(kind.title.uppercased()).font(DS.caption2.weight(.medium)).tracking(1.2)
                    Spacer()
                    Text("\(items.count) \(kind == .group ? "items" : "sections")").font(DS.caption).monospacedDigit()
                }.foregroundStyle(DS.textMuted)
                if kind == .group, !images.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DS.space4) {
                        ForEach(images, id: \.uuid) { image in
                            SpaceCollectionPreview(atom: image, compact: true)
                                .frame(height: 76).clipShape(.rect(cornerRadius: 6))
                        }
                    }
                } else {
                VStack(alignment: .leading, spacing: DS.space12) {
                    ForEach(Array(items.prefix(3)), id: \.uuid) { child in
                        HStack(alignment: .top, spacing: DS.space8) {
                            Image(systemName: child.spaceCompositionKind?.symbol ?? (child.type == .image ? "photo" : "doc"))
                                .foregroundStyle(DS.textMuted).frame(width: 18)
                            Text(child.title ?? "Untitled").foregroundStyle(DS.textSecondary).lineLimit(2)
                        }.font(DS.callout)
                    }
                    if items.isEmpty {
                        Text(kind == .group ? "Bring images, notes and references together." : "Add pages and shape the work as it grows.")
                            .font(DS.callout).foregroundStyle(DS.textSecondary).lineLimit(3)
                    }
                }
                }
                Spacer(minLength: 0)
                Button("Open \(kind.title.lowercased())", systemImage: "arrow.up.right") { store.open(atom, in: spaceID) }
                    .buttonStyle(.plain).font(DS.callout.weight(.medium)).foregroundStyle(DS.accent)
                    .frame(minHeight: 44).help("Open \(atom.title ?? kind.title)")
            }.padding(DS.space20)
        }
    }
}

// MARK: - Per-Block Transform Host
struct CanvasBlockTransformHost<StaticContent: View>: View {
    let block: CanvasBlock
    /// Drag offsets are read inside this body (not passed as values) so a
    /// drag frame invalidates only the hosts that are actually moving —
    /// every other block reads just the stable start/end fields.
    let interaction: CanvasInteractionState
    let isClusterMember: Bool
    let heatmapOpacity: CGFloat
    let isCrossThinkspaceDragging: Bool
    let staticContent: StaticContent

    // Closures — excluded from Equatable comparison
    var onDragChanged: ((CGSize) -> Void)?
    var onDragEnded: ((CGSize) -> Void)?
    var onDoubleTap: (() -> Void)?

    var body: some View {
        let dragOffset = interaction.dragOffset(forBlockId: block.id, entityUuid: block.entityUuid)
        let isDragTarget = interaction.activeBlockDragId == block.id
        let isDraggingClusterMember = interaction.draggingClusterId != nil &&
            interaction.draggingClusterMemberUUIDs.contains(block.entityUuid)

        staticContent
            .position(
                x: block.position.x + dragOffset.width,
                y: block.position.y + dragOffset.height
            )
            .scaleEffect(block.scale)
            .rotationEffect(.degrees(block.rotation))
            .opacity(isCrossThinkspaceDragging ? 0 : block.opacity * heatmapOpacity)
            .zIndex(isDragTarget ? 1000 : Double(block.zIndex))
            .allowsHitTesting(!isClusterMember)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { gesture in
                        onDragChanged?(gesture.translation)
                    }
                    .onEnded { gesture in
                        onDragEnded?(gesture.translation)
                    }
            )
            .onTapGesture(count: 2) {
                onDoubleTap?()
            }
            .transition(.asymmetric(
                insertion: .scale(scale: 0.8).combined(with: .opacity),
                removal: .scale(scale: 0.95).combined(with: .opacity)
            ))
            .transaction { tx in
                if isDraggingClusterMember {
                    tx.animation = nil
                }
            }
    }
}

/// Used via `.equatable()` in the blocks ForEach: dragging one block (or any
/// unrelated canvas invalidation) skips every host whose render data is
/// unchanged — the recreated gesture closures no longer defeat diffing.
extension CanvasBlockTransformHost: Equatable where StaticContent: Equatable {
    static func == (lhs: CanvasBlockTransformHost, rhs: CanvasBlockTransformHost) -> Bool {
        // interaction is a shared reference read inside body via observation;
        // it never participates in parent-driven diffing.
        lhs.block == rhs.block &&
            lhs.isClusterMember == rhs.isClusterMember &&
            lhs.heatmapOpacity == rhs.heatmapOpacity &&
            lhs.isCrossThinkspaceDragging == rhs.isCrossThinkspaceDragging &&
            lhs.staticContent == rhs.staticContent
    }
}

/// Stable identity of an in-flight cluster drop preview — changes only when
/// the drag enters/leaves a cluster. The per-frame ghost position rides
/// CanvasInteractionState.dropPreviewPosition so gesture frames never
/// re-enter CanvasView.body.
private struct ActiveCanvasClusterDropPreview: Equatable {
    let blockId: String
    let blockUUID: String
    let targetClusterId: UUID
}

private struct ActiveClusterResizeSession {
    let clusterId: UUID
    let startRect: CGRect
    var previewGeometries: [String: CanvasBlockGeometry]
    let memberGeometries: [String: CanvasBlockGeometry]
}

// MARK: - Canvas Drop Delegate

/// Accepts internal cluster block drops, external image drops and web-link
/// drops (a post dragged out of a browser pane) onto the canvas background.
private struct CanvasDropDelegate: DropDelegate {
    static let supportedTypes: [UTType] = [.text, .url] + CanvasImageDropController.supportedTypes

    let isEnabled: () -> Bool
    let screenToCanvas: (CGPoint) -> CGPoint
    let onClusterDrop: (String, CGPoint) -> Void
    let onExternalDrop: ([NSItemProvider], CGPoint) -> Void
    /// A tray member dragged out onto the canvas: entity uuid + canvas point.
    let onTrayDrop: (String, CGPoint) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        guard isEnabled() else {
            CanvasDropDebugLog.note("validateDrop: REJECTED — canvas not enabled (overlay mode)")
            return false
        }
        if CanvasTrayDragSession.draggingEntityUuid != nil && info.hasItemsConforming(to: [.text]) {
            CanvasDropDebugLog.note("validateDrop: accepted as TRAY drag")
            return true
        }
        if ClusterViewDragSession.sourceClusterId != nil && info.hasItemsConforming(to: [.text]) {
            CanvasDropDebugLog.note("validateDrop: accepted as CLUSTER drag (sourceClusterId set)")
            return true
        }
        // Accept a ⌘K retrieve drag purely for the drop-cursor affordance —
        // actual placement is driven by CommandKDragSession's release poll
        // (the single source of truth), so performDrop only consumes here.
        if CommandKDragSession.shared.isActive && info.hasItemsConforming(to: [.text]) {
            CanvasDropDebugLog.note("validateDrop: accepted as ⌘K drag")
            return true
        }

        // Text is accepted because a browser-pane link drag reaches AppKit as
        // plain text at best (WebKit custom-pasteboard bundling) — and
        // sometimes as nothing readable at all, which is what the armed drag
        // session covers. Non-link text drops dead-end harmlessly downstream.
        let acceptsImage = info.hasItemsConforming(to: CanvasImageDropController.supportedTypes)
        let acceptsURL = info.hasItemsConforming(to: [.url])
        let acceptsText = info.hasItemsConforming(to: [.text])
        let sessionArmed = BrowserPaneLinkDragSession.isArmed
        CanvasDropDebugLog.note("validateDrop: image=\(acceptsImage) url=\(acceptsURL) text=\(acceptsText) sessionArmed=\(sessionArmed)")
        return acceptsImage || acceptsURL || acceptsText || sessionArmed
    }

    /// A ⌘K drag hovering back over the palette reads as "changed my mind":
    /// the palette un-ghosts, and the canvas behind it must stop being a
    /// drop target — otherwise releasing over the palette still drops behind.
    func dropUpdated(info: DropInfo) -> DropProposal? {
        if CommandKDragSession.shared.isActive && !CommandKDragSession.shared.isPointerOutsidePalette {
            return DropProposal(operation: .cancel)
        }
        return nil
    }

    func performDrop(info: DropInfo) -> Bool {
        guard isEnabled() else { return false }
        let canvasPosition = screenToCanvas(info.location)

        if CommandKDragSession.shared.isActive {
            // Placement is owned by the session's release poll; the canvas only
            // consumes the SwiftUI drop so it doesn't read as a failed drag.
            // Releasing over the palette is a miss, not a drop-behind.
            return CommandKDragSession.shared.isPointerOutsidePalette
        }

        if let draggingUuid = CanvasTrayDragSession.draggingEntityUuid {
            // The session is the truth (the pasteboard string is a courtesy
            // copy); either way the drop places exactly that member.
            for provider in info.itemProviders(for: [.text]) {
                _ = provider.loadObject(ofClass: NSString.self) { item, _ in
                    let payload = (item as? String).flatMap(CanvasTrayDragSession.entityUuid(from:)) ?? draggingUuid
                    DispatchQueue.main.async {
                        onTrayDrop(payload, canvasPosition)
                    }
                }
            }
            return true
        }

        if ClusterViewDragSession.sourceClusterId != nil {
            for provider in info.itemProviders(for: [.text]) {
                _ = provider.loadObject(ofClass: NSString.self) { item, _ in
                    guard let blockUUID = item as? String else { return }
                    DispatchQueue.main.async {
                        onClusterDrop(blockUUID, canvasPosition)
                    }
                }
            }
            return true
        }

        let externalProviders = info.itemProviders(for: [.url, .text] + CanvasImageDropController.supportedTypes)
        CanvasDropDebugLog.note("performDrop: \(externalProviders.count) provider(s); types=\(externalProviders.map(\.registeredTypeIdentifiers))")
        // Zero readable providers can still be a browser-pane link drag whose
        // payload only survived out-of-band (the armed session).
        guard !externalProviders.isEmpty || BrowserPaneLinkDragSession.isArmed else {
            CanvasDropDebugLog.note("performDrop: REJECTED — no matching providers, no armed session")
            return false
        }
        onExternalDrop(externalProviders, canvasPosition)
        return true
    }
}

/// Leaf host for the drop-preview ghost: the only view that reads the
/// per-frame dropPreviewPosition, so a drag frame over a cluster invalidates
/// just this body — CanvasView.body stays out of the gesture hot path.
/// Identity for the concept-merge hover indication. Changes on enter/exit
/// only — the per-frame drag path compares before writing (120fps law).
struct ActiveConceptMergeHoverPreview: Equatable {
    let blockId: String
    let conceptBlockID: String
    let conceptTitle: String
}

/// The merge drop indication drawn over a hovered concept block: a dashed
/// accent ring around its frame and a "Merge into …" pill above it.
private struct ConceptMergeHoverPreviewView: View {
    let conceptTitle: String
    let size: CGSize

    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(DS.accent.opacity(0.07))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        DS.accent.opacity(0.7),
                        style: StrokeStyle(lineWidth: 2, dash: [8, 5])
                    )
            )
            .overlay(alignment: .top) { mergePill.offset(y: -16) }
            .frame(width: size.width + 12, height: size.height + 12)
            .shadow(color: DS.accent.opacity(0.18), radius: 12, y: 6)
            .transition(.opacity)
            .accessibilityHidden(true)
    }

    private var mergePill: some View {
        HStack(spacing: DS.space6) {
            Image(systemName: "arrow.triangle.merge")
                .font(DS.caption.weight(.semibold))
                .accessibilityHidden(true)
            Text("Merge into \(conceptTitle)")
                .font(DS.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(DS.textOnAccent)
        .padding(.horizontal, DS.space10)
        .frame(height: 26)
        .background(DS.accent, in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
    }
}

private struct CanvasClusterDropPreviewHost: View {
    let block: CanvasBlock
    let clusterColor: Color
    let interaction: CanvasInteractionState

    var body: some View {
        CanvasClusterDropPreviewView(
            block: block,
            clusterColor: clusterColor,
            previewPosition: interaction.dropPreviewPosition
        )
    }
}

private struct CanvasClusterDropPreviewView: View {
    let block: CanvasBlock
    let clusterColor: Color
    let previewPosition: CGPoint

    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(clusterColor.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        clusterColor.opacity(0.65),
                        style: StrokeStyle(lineWidth: 2, dash: [8, 5])
                    )
            )
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(block.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.text)
                        .lineLimit(2)
                    Text("Drop preview")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(clusterColor.opacity(0.85))
                }
                .padding(14)
            }
            .frame(width: block.size.width, height: block.size.height)
            .position(
                x: previewPosition.x,
                y: previewPosition.y
            )
            .shadow(color: clusterColor.opacity(0.18), radius: 12, y: 6)
            .transition(.opacity)
    }
}

// MARK: - Metal Canvas Representable
struct MetalCanvasViewRepresentable: NSViewRepresentable {
    let blocks: [CanvasBlock]
    let gridEnabled: Bool

    func makeNSView(context: Context) -> MetalCanvasView {
        let view = MetalCanvasView(frame: .zero)
        view.gridEnabled = gridEnabled
        return view
    }

    func updateNSView(_ nsView: MetalCanvasView, context: Context) {
        nsView.blocks = blocks
        nsView.gridEnabled = gridEnabled
    }
}

// MARK: - Notifications
extension Notification.Name {
    // Note: placeBlocksOnCanvas, moveCanvasBlocks, closeSelectedBlock, and resizeSelectedBlock are defined in VoiceNotifications.swift
    // Unified with CosmoNotification.Navigation to prevent mismatched notification names
    static let enterFocusMode = CosmoNotification.Navigation.enterFocusMode
    static let openBlockInFocusMode = CosmoNotification.Navigation.openBlockInFocusMode
    static let openEntityOnCanvas = CosmoNotification.Navigation.openEntityOnCanvas
    static let createEntityInFocusMode = CosmoNotification.Navigation.createEntityInFocusMode
    static let switchToThinkspace = CosmoNotification.Navigation.switchToThinkspace

    static let toggleBlockPin = Notification.Name("toggleBlockPin")
    static let duplicateBlock = Notification.Name("duplicateBlock")
    static let removeBlock = Notification.Name("removeBlock")
    /// Detach an atom from every canvas/thinkspace (all its placements) while
    /// keeping the atom alive in the Library. userInfo: ["blockId": String].
    static let removeAtomFromThinkspace = Notification.Name("removeAtomFromThinkspace")
    /// "Remove from canvas": unplace one block — it stays a member of the
    /// space and waits in the tray. userInfo: ["blockId": String].
    static let removeBlockFromCanvas = Notification.Name("removeBlockFromCanvas")
    /// Tombstone an atom (→ Recently Deleted) and drop its blocks everywhere.
    /// userInfo: ["blockId": String].
    static let deleteAtomEntirely = Notification.Name("deleteAtomEntirely")
    static let arrangeCanvasBlocks = Notification.Name("arrangeCanvasBlocks")
    static let createNoteBlock = Notification.Name("createNoteBlock")
    static let addSwipeToCanvas = Notification.Name("addSwipeToCanvas")
    static let canvasAtomProcessed = Notification.Name("canvasAtomProcessed")
}

// MARK: - Pending Placement Queue

/// Holds canvas placement notifications (`.openEntityOnCanvas`,
/// `createIdeaBoardBlock`, cross-thinkspace drops, …) until the canvas is
/// mounted, active, and has its observers registered. Replaces the fixed
/// 0.3s timers that raced canvas mount and silently dropped placements.
/// When a canvas is already live, `enqueue` posts immediately — the
/// notification path is unchanged for the mounted case.
@MainActor
final class CanvasPendingPlacementQueue {
    static let shared = CanvasPendingPlacementQueue()

    private var pending: [(name: Notification.Name, userInfo: [String: Any])] = []
    private var isCanvasReady = false

    private init() {}

    func enqueue(name: Notification.Name, userInfo: [String: Any]) {
        pending.append((name: name, userInfo: userInfo))
        drainIfReady()
    }

    /// Called by CanvasView once its observers are registered and it is active.
    func markCanvasReady() {
        isCanvasReady = true
        drainIfReady()
    }

    func markCanvasNotReady() {
        isCanvasReady = false
    }

    private func drainIfReady() {
        guard isCanvasReady, !pending.isEmpty else { return }
        let items = pending
        pending.removeAll()
        for item in items {
            NotificationCenter.default.post(name: item.name, object: nil, userInfo: item.userInfo)
        }
    }
}

// MARK: - Cosmo Context Provider

@MainActor
class CanvasContextProvider: CosmoContextProvider {
    private weak var spatialEngine: SpatialEngine?
    private let initialThinkspaceId: String?

    init(spatialEngine: SpatialEngine, thinkspaceId: String? = nil) {
        self.spatialEngine = spatialEngine
        self.initialThinkspaceId = thinkspaceId
    }

    var contextType: CosmoContextType { .thinkspaceCanvas }

    var contextSummary: String {
        let count = spatialEngine?.blocks.count ?? 0
        if let title = currentThinkspaceTitle {
            return "\(title) - \(count) blocks on canvas"
        }
        return "\(count) blocks on canvas"
    }

    private var currentThinkspaceId: String? {
        spatialEngine?.currentThinkspaceId ?? initialThinkspaceId
    }

    private var currentThinkspaceTitle: String? {
        guard let id = currentThinkspaceId else { return nil }
        return ThinkspaceManager.shared.thinkspaces.first(where: { $0.id == id })?.name
            ?? ThinkspaceManager.shared.currentThinkspace.flatMap { $0.id == id ? $0.name : nil }
    }

    var contextData: CosmoContextData {
        guard let blocks = spatialEngine?.blocks else {
            var viewData = ["blockCount": "0"]
            if let id = currentThinkspaceId {
                viewData["currentThinkspaceUUID"] = id
                viewData["targetThinkspaceUUID"] = id
                viewData["thinkspaceUUID"] = id
            }
            return CosmoContextData(
                currentAtomUUID: currentThinkspaceId,
                currentAtomType: currentThinkspaceId == nil ? nil : "thinkspace",
                currentAtomTitle: currentThinkspaceTitle,
                viewSpecificData: viewData
            )
        }

        var viewData: [String: String] = [
            "blockCount": "\(blocks.count)"
        ]
        if let id = currentThinkspaceId {
            viewData["currentThinkspaceUUID"] = id
            viewData["targetThinkspaceUUID"] = id
            viewData["thinkspaceUUID"] = id
        }
        if let title = currentThinkspaceTitle {
            viewData["currentThinkspaceTitle"] = title
        }

        // Summarize block types
        var typeCounts: [String: Int] = [:]
        for block in blocks {
            let type = block.entityType.rawValue
            typeCounts[type, default: 0] += 1
        }
        viewData["blockTypes"] = typeCounts.map { "\($0.key): \($0.value)" }.joined(separator: ", ")

        // Include titles of visible blocks (up to 20)
        let titles = blocks.prefix(20).compactMap { $0.title }.filter { !$0.isEmpty }
        if !titles.isEmpty {
            viewData["blockTitles"] = titles.joined(separator: " | ")
        }

        return CosmoContextData(
            currentAtomUUID: currentThinkspaceId,
            currentAtomType: currentThinkspaceId == nil ? nil : "thinkspace",
            currentAtomTitle: currentThinkspaceTitle,
            viewSpecificData: viewData,
            visibleItemCount: blocks.count
        )
    }

    var availableActions: [CosmoWindowAction] { [] }
}

// MARK: - Canvas Block Editable Surface

/// Atom-backed inline-assistant surface for text-bearing canvas blocks.
/// Applies resolve against the *fresh* atom body and persist through the
/// repository; the block views' GRDB observation picks the change up, so the
/// canvas re-renders without any direct view coupling.
@MainActor
final class CanvasBlockEditableSurface: CosmoEditableSurfaceProvider {
    let atomUUID: String
    private let title: String
    private var loadedText: String

    static func supports(_ entityType: EntityType) -> Bool {
        entityType == .note || entityType == .stickyNote
    }

    static func surfaceID(for atomUUID: String) -> String {
        "canvasBlock:\(atomUUID)"
    }

    init(atom: Atom) {
        self.atomUUID = atom.uuid
        self.title = atom.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.loadedText = RichDocumentPersistence.loadAtomDocument(
            field: .body,
            metadata: atom.metadata,
            fallbackPlainText: atom.body
        ).plainText
    }

    var surfaceID: String { Self.surfaceID(for: atomUUID) }

    func editableSnapshot() -> CosmoEditableSourceSnapshot {
        CosmoEditableSourceSnapshot(
            surfaceID: surfaceID,
            targetID: "\(surfaceID):body",
            kind: .text,
            title: title.isEmpty ? "Canvas note" : title,
            text: loadedText,
            sourceHash: CosmoEditableSurfaceHasher.hash(loadedText),
            anchors: [
                .init(id: "body", label: "Body", utf16Start: 0, utf16Length: loadedText.utf16.count)
            ]
        )
    }

    func apply(operation: CosmoAssistantProposalOperation) async throws -> CosmoEditableOperationResult {
        guard operation.targetID == "\(surfaceID):body" else {
            return CosmoEditableOperationResult(
                operationID: operation.id, status: .conflicted, message: "Target changed"
            )
        }
        guard let atom = try? await AtomRepository.shared.fetch(uuid: atomUUID) else {
            return CosmoEditableOperationResult(
                operationID: operation.id, status: .conflicted, message: "This block's atom is no longer available"
            )
        }

        var bodyText = RichDocumentPersistence.loadAtomDocument(
            field: .body,
            metadata: atom.metadata,
            fallbackPlainText: atom.body
        ).plainText

        guard let placement = CosmoInlineTextEditResolver.placement(for: operation, in: bodyText) else {
            return CosmoEditableOperationResult(
                operationID: operation.id, status: .conflicted, message: "Original text not found"
            )
        }
        bodyText.replaceSubrange(placement.range, with: placement.replacementText)

        // Same plain-text round-trip the Note focus mode apply uses: regenerate the
        // body document from the edited plain text and persist both fields together.
        let written = RichDocumentPersistence.writeAtomDocuments(
            existingMetadata: atom.metadata,
            bodyDocument: RichDocument.migrateLegacy(bodyText)
        )
        var updated = atom
        updated.body = written.body
        updated.metadata = written.metadata
        _ = try await AtomRepository.shared.update(updated)

        loadedText = bodyText
        return CosmoEditableOperationResult(operationID: operation.id, status: .applied, message: "Applied")
    }

    func reject(operation: CosmoAssistantProposalOperation) async -> CosmoEditableOperationResult {
        CosmoEditableOperationResult(operationID: operation.id, status: .rejected, message: "Rejected")
    }
}
