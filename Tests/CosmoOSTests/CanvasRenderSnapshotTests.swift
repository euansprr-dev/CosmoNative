import XCTest
@testable import CosmoOS

final class CanvasRenderSnapshotTests: XCTestCase {
    // NOTE July 2026: the switch-time outgoing screenshot capture (and its
    // CanvasScreenshotCapturePolicy) was removed — cacheDisplay rasterizes the
    // whole window on the main thread and made every thinkspace switch hitch.
    // Constellation/portal previews now capture lazily at presentation time.
    func testThinkspaceSwitchPathNeverCapturesScreenshots() throws {
        let canvasView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Canvas/CanvasView.swift"),
            encoding: .utf8
        )
        let switchHandler = try XCTUnwrap(
            canvasView.slice(
                from: ".onChange(of: thinkspaceId)",
                to: ".onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Automation.createFlow))"
            )
        )
        XCTAssertFalse(switchHandler.contains("captureCanvasScreenshot("))
    }

    func testCompositorTransformMatchesViewportScreenMapping() {
        let transform = CanvasViewportTransform(
            viewportSize: CGSize(width: 1_200, height: 800),
            committedOffset: CGSize(width: -240, height: 96),
            gesturePanOffset: CGSize(width: 36, height: -18),
            committedScale: 1.4,
            gestureMagnification: 0.75
        )
        let compositor = CanvasCompositorTransform(viewportTransform: transform)
        let canvasPoint = CGPoint(x: 420, y: 260)
        let screenPoint = compositor.screenPoint(forCanvasPoint: canvasPoint)
        let expected = transform.canvasToScreen(canvasPoint)

        XCTAssertEqual(screenPoint.x, expected.x, accuracy: 0.001)
        XCTAssertEqual(screenPoint.y, expected.y, accuracy: 0.001)
        XCTAssertEqual(compositor.contentOffset, transform.contentOffset)
        XCTAssertEqual(compositor.effectiveScale, transform.effectiveScale)
    }

    func testCommittedOnlyTransformStripsTransientGestureState() {
        let liveTransform = CanvasViewportTransform(
            viewportSize: CGSize(width: 1_200, height: 800),
            committedOffset: CGSize(width: -240, height: 96),
            gesturePanOffset: CGSize(width: 36, height: -18),
            committedScale: 1.4,
            gestureMagnification: 0.75
        )

        let snapshotTransform = liveTransform.committedOnly()

        XCTAssertEqual(snapshotTransform.viewportSize, liveTransform.viewportSize)
        XCTAssertEqual(snapshotTransform.committedOffset, liveTransform.committedOffset)
        XCTAssertEqual(snapshotTransform.gesturePanOffset, .zero)
        XCTAssertEqual(snapshotTransform.committedScale, liveTransform.committedScale)
        XCTAssertEqual(snapshotTransform.gestureMagnification, 1)
        XCTAssertEqual(snapshotTransform.contentOffset, liveTransform.committedOffset)
        XCTAssertEqual(snapshotTransform.effectiveScale, liveTransform.committedScale)
    }

    func testGridPatternPlaneAlignsToCanvasTileCoordinates() {
        let transform = CanvasViewportTransform(
            viewportSize: CGSize(width: 1_000, height: 800),
            committedOffset: CGSize(width: -123, height: 77),
            committedScale: 1.25
        )
        let metrics = CanvasGridPatternMetrics(
            transform: transform,
            viewportSize: transform.viewportSize
        )
        let paddedVisibleRect = transform.visibleCanvasRect.insetBy(
            dx: -metrics.tileSize * 2,
            dy: -metrics.tileSize * 2
        )

        XCTAssertEqual(metrics.planeOrigin.x.truncatingRemainder(dividingBy: metrics.tileSize), 0, accuracy: 0.001)
        XCTAssertEqual(metrics.planeOrigin.y.truncatingRemainder(dividingBy: metrics.tileSize), 0, accuracy: 0.001)
        XCTAssertLessThanOrEqual(metrics.planeOrigin.x, paddedVisibleRect.minX)
        XCTAssertLessThanOrEqual(metrics.planeOrigin.y, paddedVisibleRect.minY)
        XCTAssertGreaterThanOrEqual(metrics.planeOrigin.x + metrics.planeSize.width, paddedVisibleRect.maxX)
        XCTAssertGreaterThanOrEqual(metrics.planeOrigin.y + metrics.planeSize.height, paddedVisibleRect.maxY)
        XCTAssertEqual(metrics.rawDotSize, 2.5, accuracy: 0.001)
    }

    func testGridPatternKeepsMinimumScreenDotSizeAtLowZoom() {
        let transform = CanvasViewportTransform(
            viewportSize: CGSize(width: 1_000, height: 800),
            committedOffset: .zero,
            committedScale: 0.25
        )
        let metrics = CanvasGridPatternMetrics(
            transform: transform,
            viewportSize: transform.viewportSize
        )

        XCTAssertEqual(metrics.rawDotSize * transform.effectiveScale, 1.0, accuracy: 0.001)
    }

    func testGridPatternExposesScreenSpaceDrawingMetricsAtLowZoom() {
        let transform = CanvasViewportTransform(
            viewportSize: CGSize(width: 1_000, height: 800),
            committedOffset: CGSize(width: -123, height: 77),
            committedScale: 0.25
        )
        let metrics = CanvasGridPatternMetrics(
            transform: transform,
            viewportSize: transform.viewportSize
        )
        let canvasOriginOnScreen = transform.canvasToScreen(.zero)

        XCTAssertEqual(metrics.screenSpacing, 10, accuracy: 0.001)
        XCTAssertEqual(metrics.screenDotSize, 1, accuracy: 0.001)
        XCTAssertEqual(metrics.screenGridOrigin.x, canvasOriginOnScreen.x, accuracy: 0.001)
        XCTAssertEqual(metrics.screenGridOrigin.y, canvasOriginOnScreen.y, accuracy: 0.001)
    }

    func testLiveViewportSnapshotPolicyUsesLargerPreloadWithoutPerFramePanBuckets() {
        let baseTransform = CanvasViewportTransform(
            viewportSize: CGSize(width: 1_000, height: 800),
            committedOffset: .zero,
            gesturePanOffset: CGSize(width: 80, height: 0),
            committedScale: 1
        )
        let nearbyTransform = CanvasViewportTransform(
            viewportSize: CGSize(width: 1_000, height: 800),
            committedOffset: .zero,
            gesturePanOffset: CGSize(width: 160, height: 0),
            committedScale: 1
        )
        let farTransform = CanvasViewportTransform(
            viewportSize: CGSize(width: 1_000, height: 800),
            committedOffset: .zero,
            gesturePanOffset: CGSize(width: 760, height: 0),
            committedScale: 1
        )

        let baseSnapshotTransform = CanvasViewportSnapshotPolicy.snapshotTransform(
            for: baseTransform,
            isLiveGesture: true
        )
        let nearbySnapshotTransform = CanvasViewportSnapshotPolicy.snapshotTransform(
            for: nearbyTransform,
            isLiveGesture: true
        )
        let farSnapshotTransform = CanvasViewportSnapshotPolicy.snapshotTransform(
            for: farTransform,
            isLiveGesture: true
        )

        // LAW (mounting stability): gesture start/end must not change the
        // preload inset — a live/idle split churned the mounted set at every
        // gesture boundary.
        XCTAssertEqual(
            CanvasViewportSnapshotPolicy.preloadInset(
                viewportSize: baseTransform.viewportSize,
                isLiveGesture: true,
                blockCount: 100
            ),
            CanvasViewportSnapshotPolicy.preloadInset(
                viewportSize: baseTransform.viewportSize,
                isLiveGesture: false,
                blockCount: 100
            )
        )
        XCTAssertEqual(baseSnapshotTransform.contentOffset, nearbySnapshotTransform.contentOffset)
        XCTAssertNotEqual(baseSnapshotTransform.contentOffset, farSnapshotTransform.contentOffset)
    }

    /// Hysteresis: a mounted block just outside the enter rect (but inside the
    /// exit rect) stays mounted after a pan; a block never mounted at that
    /// position does not mount. Gesture boundaries can therefore never churn
    /// the mounted set.
    @MainActor
    func testRenderPipelineRetainsMountedBlocksInsideExitBand() {
        let inset: CGFloat = 400
        // Viewport 1000×800 at origin: visible canvas x ∈ [0, 1000],
        // enter rect x ∈ [-400, 1400], exit rect (×1.75) x ∈ [-700, 1700].
        let block = CanvasBlock(
            id: "frontier",
            position: CGPoint(x: 1_000, y: 400),
            size: CGSize(width: 60, height: 60),
            entityType: .idea,
            entityId: 1,
            entityUuid: "frontier-uuid",
            title: "Frontier"
        )
        let pipeline = CanvasRenderPipeline()
        let originTransform = CanvasViewportTransform(
            viewportSize: CGSize(width: 1_000, height: 800),
            committedOffset: .zero
        )
        // Positive offset moves the world right, so the visible rect shifts
        // LEFT to x ∈ [-600, 400]: enter reaches 800 (block at 970–1030 is
        // out), exit reaches 1100 (block is still in).
        let pannedTransform = CanvasViewportTransform(
            viewportSize: CGSize(width: 1_000, height: 800),
            committedOffset: CGSize(width: 600, height: 0)
        )

        let first = pipeline.snapshot(
            blocks: [block],
            blockDataRevision: 1,
            transform: originTransform,
            preloadInset: inset,
            userClusters: [],
            clusterDataRevision: 1,
            selectedBlockId: nil,
            selectedClusterId: nil,
            draggingClusterId: nil,
            resizingClusterId: nil
        )
        XCTAssertTrue(first.visibleBlockIds.contains("frontier"))

        // Fresh pipeline at the panned position never mounted the block —
        // whether it renders there depends only on the ENTER rect.
        let freshPipeline = CanvasRenderPipeline()
        let freshAtPanned = freshPipeline.snapshot(
            blocks: [block],
            blockDataRevision: 1,
            transform: pannedTransform,
            preloadInset: inset,
            userClusters: [],
            clusterDataRevision: 1,
            selectedBlockId: nil,
            selectedClusterId: nil,
            draggingClusterId: nil,
            resizingClusterId: nil
        )

        let retained = pipeline.snapshot(
            blocks: [block],
            blockDataRevision: 1,
            transform: pannedTransform,
            preloadInset: inset,
            userClusters: [],
            clusterDataRevision: 1,
            selectedBlockId: nil,
            selectedClusterId: nil,
            draggingClusterId: nil,
            resizingClusterId: nil
        )

        if freshAtPanned.visibleBlockIds.contains("frontier") {
            XCTFail("Test geometry broken: block should be outside the enter rect after the pan")
        }
        XCTAssertTrue(
            retained.visibleBlockIds.contains("frontier"),
            "Previously mounted block inside the exit band must stay mounted"
        )
        XCTAssertEqual(retained.renderableBlocks.map(\.id), ["frontier"])
    }

    /// Zoom LOD thresholds sit BETWEEN the live 0.125 quantization buckets,
    /// so a pinch flips tiers only at bucket crossings, never per frame.
    func testBlockRenderTierThresholdsAlignWithZoomBuckets() {
        XCTAssertEqual(CanvasBlockRenderTier.tier(forEffectiveScale: 1.0), .full)
        XCTAssertEqual(CanvasBlockRenderTier.tier(forEffectiveScale: 0.5), .full)
        XCTAssertEqual(CanvasBlockRenderTier.tier(forEffectiveScale: 0.375), .poster)
        XCTAssertEqual(CanvasBlockRenderTier.tier(forEffectiveScale: 0.25), .poster)
        XCTAssertEqual(CanvasBlockRenderTier.tier(forEffectiveScale: 0.125), .minimal)

        // Thresholds must not coincide with a bucket value exactly — a bucket
        // landing ON a threshold would make the tier at that bucket depend on
        // floating-point noise.
        let buckets: [CGFloat] = stride(from: 0.125, through: 3.0, by: 0.125).map { $0 }
        XCTAssertFalse(buckets.contains(CanvasBlockRenderTier.posterThreshold))
        XCTAssertFalse(buckets.contains(CanvasBlockRenderTier.minimalThreshold))
    }

    @MainActor
    func testRenderPipelineRebuildsViewportWhenPreloadInsetChanges() {
        let blocks = [
            CanvasBlock(
                id: "origin",
                position: CGPoint(x: 500, y: 400),
                size: CGSize(width: 200, height: 120),
                entityType: .idea,
                entityId: 1,
                entityUuid: "origin-uuid",
                title: "Origin"
            ),
            CanvasBlock(
                id: "warm-belt",
                position: CGPoint(x: 1_760, y: 400),
                size: CGSize(width: 200, height: 120),
                entityType: .idea,
                entityId: 2,
                entityUuid: "warm-belt-uuid",
                title: "Warm Belt"
            )
        ]
        let pipeline = CanvasRenderPipeline()
        let transform = CanvasViewportTransform(
            viewportSize: CGSize(width: 1_000, height: 800),
            committedOffset: .zero
        )

        let coldSnapshot = pipeline.snapshot(
            blocks: blocks,
            blockDataRevision: 1,
            transform: transform,
            preloadInset: 320,
            userClusters: [],
            clusterDataRevision: 1,
            selectedBlockId: nil,
            selectedClusterId: nil,
            draggingClusterId: nil,
            resizingClusterId: nil
        )

        let warmSnapshot = pipeline.snapshot(
            blocks: blocks,
            blockDataRevision: 1,
            transform: transform,
            preloadInset: 900,
            userClusters: [],
            clusterDataRevision: 1,
            selectedBlockId: nil,
            selectedClusterId: nil,
            draggingClusterId: nil,
            resizingClusterId: nil
        )

        XCTAssertFalse(coldSnapshot.visibleBlockIds.contains("warm-belt"))
        XCTAssertTrue(warmSnapshot.visibleBlockIds.contains("warm-belt"))
        XCTAssertEqual(pipeline.debugDataSnapshotBuildCount, 1)
        XCTAssertEqual(pipeline.debugViewportSnapshotBuildCount, 2)
    }

    @MainActor
    func testRenderPipelineDoesNotRebuildDataSnapshotForViewportOnlyPan() {
        let blocks = [
            CanvasBlock(
                id: "origin",
                position: CGPoint(x: 500, y: 400),
                size: CGSize(width: 200, height: 120),
                zIndex: 2,
                entityType: .research,
                entityId: 1,
                entityUuid: "origin-uuid",
                title: "Origin",
                metadata: ["url": "https://youtu.be/abc"]
            ),
            CanvasBlock(
                id: "after-pan",
                position: CGPoint(x: 1_800, y: 400),
                size: CGSize(width: 200, height: 120),
                zIndex: 1,
                entityType: .idea,
                entityId: 2,
                entityUuid: "after-pan-uuid",
                title: "After pan"
            )
        ]
        let pipeline = CanvasRenderPipeline()

        _ = pipeline.snapshot(
            blocks: blocks,
            blockDataRevision: 1,
            transform: CanvasViewportTransform(
                viewportSize: CGSize(width: 1_000, height: 800),
                committedOffset: .zero
            ),
            userClusters: [],
            clusterDataRevision: 1,
            selectedBlockId: nil,
            selectedClusterId: nil,
            draggingClusterId: nil,
            resizingClusterId: nil
        )

        _ = pipeline.snapshot(
            blocks: blocks,
            blockDataRevision: 1,
            transform: CanvasViewportTransform(
                viewportSize: CGSize(width: 1_000, height: 800),
                committedOffset: CGSize(width: -1_300, height: 0)
            ),
            userClusters: [],
            clusterDataRevision: 1,
            selectedBlockId: nil,
            selectedClusterId: nil,
            draggingClusterId: nil,
            resizingClusterId: nil
        )

        XCTAssertEqual(pipeline.debugDataSnapshotBuildCount, 1)
        XCTAssertEqual(pipeline.debugViewportSnapshotBuildCount, 2)
    }

    func testConnectionGeometrySignatureUsesNumericBlockKeys() {
        let block = CanvasBlock(
            id: "block",
            position: CGPoint(x: 10.1254, y: 20.9876),
            size: CGSize(width: 220.25, height: 310.75),
            scale: 1.25,
            entityType: .idea,
            entityId: 1,
            entityUuid: "block-uuid",
            title: "Block"
        )
        var moved = block
        moved.position.x += 1

        let signature = CanvasConnectionGeometrySignature(blocks: [block])
        let sameSignature = CanvasConnectionGeometrySignature(blocks: [block])
        let movedSignature = CanvasConnectionGeometrySignature(blocks: [moved])

        XCTAssertEqual(signature, sameSignature)
        XCTAssertNotEqual(signature, movedSignature)
        XCTAssertEqual(signature.blockKeys.first?.positionX, 10_125)
        XCTAssertEqual(signature.blockKeys.first?.positionY, 20_988)
        XCTAssertEqual(signature.blockKeys.first?.width, 220_250)
        XCTAssertEqual(signature.blockKeys.first?.height, 310_750)
        XCTAssertEqual(signature.blockKeys.first?.scale, 1_250)
    }

    func testConnectionGeometryInvalidationKeyTracksBlockAndClusterRevisions() {
        let key = CanvasConnectionGeometryInvalidationKey(blockDataRevision: 42, clusterDataRevision: 7)
        let sameKey = CanvasConnectionGeometryInvalidationKey(blockDataRevision: 42, clusterDataRevision: 7)
        let blockChangedKey = CanvasConnectionGeometryInvalidationKey(blockDataRevision: 43, clusterDataRevision: 7)
        // Cluster changes (view-mode switches consume/release member blocks)
        // must invalidate endpoints even when block data hasn't changed —
        // otherwise lines keep pointing at canvas positions that no longer render.
        let clusterChangedKey = CanvasConnectionGeometryInvalidationKey(blockDataRevision: 42, clusterDataRevision: 8)

        XCTAssertEqual(key, sameKey)
        XCTAssertNotEqual(key, blockChangedKey)
        XCTAssertNotEqual(key, clusterChangedKey)
        XCTAssertEqual(key.blockDataRevision, 42)
        XCTAssertEqual(key.clusterDataRevision, 7)
    }

    func testConnectionDragSignatureTracksBlockAndClusterDrags() {
        let idle = CanvasConnectionDragSignature(
            blockDragId: nil, blockTranslation: .zero,
            clusterDragId: nil, clusterTranslation: .zero
        )
        let blockDrag = CanvasConnectionDragSignature(
            blockDragId: "block-1", blockTranslation: CGSize(width: 40, height: 12),
            clusterDragId: nil, clusterTranslation: .zero
        )
        // Cluster-zone drags move member blocks live — endpoint recomputation
        // must see them as a change, not just single-block drags.
        let clusterDrag = CanvasConnectionDragSignature(
            blockDragId: nil, blockTranslation: .zero,
            clusterDragId: UUID(), clusterTranslation: CGSize(width: -25, height: 60)
        )

        XCTAssertNotEqual(idle, blockDrag)
        XCTAssertNotEqual(idle, clusterDrag)
        XCTAssertNotEqual(blockDrag, clusterDrag)
        XCTAssertEqual(idle, CanvasConnectionDragSignature(
            blockDragId: nil, blockTranslation: .zero,
            clusterDragId: nil, clusterTranslation: .zero
        ))
    }

    func testConnectionLinesLayerRendersInWorldWithConsumedBlocksExcluded() throws {
        let canvasViewSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Canvas/CanvasView.swift"),
            encoding: .utf8
        )
        let layerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Canvas/CanvasConnectionLinesLayer.swift"),
            encoding: .utf8
        )

        // The layer must be fed the filtered block set (no cluster-consumed
        // blocks — their lines would point at empty canvas)…
        XCTAssertTrue(canvasViewSource.contains("blocks: connectionLineBlocks(snapshot: snapshot)"))
        XCTAssertTrue(canvasViewSource.contains("clusterConsumedBlockUUIDs"))
        // …and live in the world layer (canvas space), not the screen-space
        // transform reader that painted lines OVER every card.
        XCTAssertFalse(layerSource.contains("transformEffect"))
        XCTAssertTrue(layerSource.contains("dragOffset(forBlockId:"))
    }

    func testConnectionPulseTimerRunsOnlyWhenVisibleEdgesExist() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Canvas/CanvasConnectionLinesLayer.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("CanvasConnectionPulsePolicy.shouldRun"))
        XCTAssertTrue(source.contains("visibleEdgeCount > 0"))
        XCTAssertTrue(source.contains("updatePulseTimer()"))
    }

    func testRenderDataSnapshotReusesDataAcrossViewportFiltering() {
        let visibleAtOrigin = CanvasBlock(
            id: "origin",
            position: CGPoint(x: 500, y: 400),
            size: CGSize(width: 200, height: 120),
            zIndex: 2,
            entityType: .research,
            entityId: 1,
            entityUuid: "origin-uuid",
            title: "Origin",
            metadata: ["url": "https://youtu.be/abc"]
        )
        let visibleAfterPan = CanvasBlock(
            id: "after-pan",
            position: CGPoint(x: 1_800, y: 400),
            size: CGSize(width: 200, height: 120),
            zIndex: 1,
            entityType: .idea,
            entityId: 2,
            entityUuid: "after-pan-uuid",
            title: "After pan"
        )

        let dataSnapshot = CanvasRenderDataSnapshot.build(
            blocks: [visibleAtOrigin, visibleAfterPan],
            userClusters: []
        )

        let originSnapshot = dataSnapshot.renderSnapshot(
            transform: CanvasViewportTransform(
                viewportSize: CGSize(width: 1_000, height: 800),
                committedOffset: .zero
            ),
            selectedBlockId: nil,
            selectedClusterId: nil,
            draggingClusterId: nil,
            resizingClusterId: nil
        )

        let pannedSnapshot = dataSnapshot.renderSnapshot(
            transform: CanvasViewportTransform(
                viewportSize: CGSize(width: 1_000, height: 800),
                committedOffset: CGSize(width: -1_300, height: 0)
            ),
            selectedBlockId: nil,
            selectedClusterId: nil,
            draggingClusterId: nil,
            resizingClusterId: nil
        )

        XCTAssertEqual(dataSnapshot.blocksById.count, 2)
        XCTAssertEqual(dataSnapshot.mediaContentBlockIds, [visibleAtOrigin.id])
        XCTAssertEqual(originSnapshot.renderableBlocks.map(\.id), [visibleAtOrigin.id])
        XCTAssertEqual(pannedSnapshot.renderableBlocks.map(\.id), [visibleAfterPan.id])
    }

    func testSnapshotBuildsStableVisibleAndMediaSets() {
        let transform = CanvasViewportTransform(
            viewportSize: CGSize(width: 1_000, height: 800),
            committedOffset: .zero,
            committedScale: 1
        )
        let visibleResearch = CanvasBlock(
            id: "visible-research",
            position: CGPoint(x: 500, y: 400),
            size: CGSize(width: 200, height: 120),
            entityType: .research,
            entityId: 1,
            entityUuid: "visible-research-uuid",
            title: "Visible research",
            metadata: ["url": "https://youtube.com/watch?v=abc"]
        )
        let hiddenIdea = CanvasBlock(
            id: "hidden-idea",
            position: CGPoint(x: 3_000, y: 3_000),
            size: CGSize(width: 200, height: 120),
            entityType: .idea,
            entityId: 2,
            entityUuid: "hidden-idea-uuid",
            title: "Hidden idea"
        )

        let snapshot = CanvasRenderSnapshotBuilder.build(
            blocks: [hiddenIdea, visibleResearch],
            transform: transform,
            userClusters: [],
            selectedBlockId: visibleResearch.id,
            selectedClusterId: nil,
            draggingClusterId: nil,
            resizingClusterId: nil
        )

        XCTAssertEqual(snapshot.visibleBlockIds, [visibleResearch.id])
        XCTAssertEqual(snapshot.renderableBlocks.map(\.id), [visibleResearch.id])
        XCTAssertEqual(snapshot.mediaContentBlockIds, [visibleResearch.id])
        XCTAssertEqual(snapshot.blocksById[hiddenIdea.id]?.title, "Hidden idea")
        XCTAssertEqual(snapshot.selectedBlockId, visibleResearch.id)
    }

    func testSnapshotHidesBlocksConsumedByNonCanvasClusters() {
        let block = CanvasBlock(
            id: "clustered-block",
            position: CGPoint(x: 500, y: 400),
            size: CGSize(width: 200, height: 120),
            entityType: .idea,
            entityId: 1,
            entityUuid: "clustered-uuid",
            title: "Clustered"
        )
        let cluster = CanvasCluster(
            id: UUID(),
            name: "List cluster",
            blockUUIDs: [block.entityUuid],
            colorIndex: 0,
            boundingRect: CGRect(x: 440, y: 340, width: 260, height: 180),
            isCollapsed: false,
            isUserCreated: true,
            viewMode: .list
        )

        let snapshot = CanvasRenderSnapshotBuilder.build(
            blocks: [block],
            transform: CanvasViewportTransform(
                viewportSize: CGSize(width: 1_000, height: 800),
                committedOffset: .zero
            ),
            userClusters: [cluster],
            selectedBlockId: nil,
            selectedClusterId: nil,
            draggingClusterId: nil,
            resizingClusterId: nil
        )

        XCTAssertEqual(snapshot.clusterConsumedBlockUUIDs, [block.entityUuid])
        XCTAssertTrue(snapshot.renderableBlocks.isEmpty)
    }

    func testSnapshotKeepsGridClusterMembersConsumedDuringResize() {
        let block = CanvasBlock(
            id: "grid-block",
            position: CGPoint(x: 500, y: 400),
            size: CGSize(width: 200, height: 120),
            entityType: .idea,
            entityId: 1,
            entityUuid: "grid-uuid",
            title: "Grid member"
        )
        let clusterId = UUID()
        let cluster = CanvasCluster(
            id: clusterId,
            name: "Grid cluster",
            blockUUIDs: [block.entityUuid],
            colorIndex: 0,
            boundingRect: CGRect(x: 440, y: 340, width: 360, height: 280),
            isCollapsed: false,
            isUserCreated: true,
            viewMode: .grid
        )

        let snapshot = CanvasRenderSnapshotBuilder.build(
            blocks: [block],
            transform: CanvasViewportTransform(
                viewportSize: CGSize(width: 1_000, height: 800),
                committedOffset: .zero
            ),
            userClusters: [cluster],
            selectedBlockId: nil,
            selectedClusterId: clusterId,
            draggingClusterId: nil,
            resizingClusterId: clusterId
        )

        XCTAssertEqual(snapshot.clusterConsumedBlockUUIDs, [block.entityUuid])
        XCTAssertTrue(snapshot.renderableBlocks.isEmpty)
    }

    func testSnapshotStillRendersCanvasClusterMembersDuringResize() {
        let block = CanvasBlock(
            id: "canvas-block",
            position: CGPoint(x: 500, y: 400),
            size: CGSize(width: 200, height: 120),
            entityType: .idea,
            entityId: 1,
            entityUuid: "canvas-uuid",
            title: "Canvas member"
        )
        let clusterId = UUID()
        let cluster = CanvasCluster(
            id: clusterId,
            name: "Canvas cluster",
            blockUUIDs: [block.entityUuid],
            colorIndex: 0,
            boundingRect: CGRect(x: 440, y: 340, width: 360, height: 280),
            isCollapsed: false,
            isUserCreated: true,
            viewMode: .canvas
        )

        let snapshot = CanvasRenderSnapshotBuilder.build(
            blocks: [block],
            transform: CanvasViewportTransform(
                viewportSize: CGSize(width: 1_000, height: 800),
                committedOffset: .zero
            ),
            userClusters: [cluster],
            selectedBlockId: nil,
            selectedClusterId: clusterId,
            draggingClusterId: nil,
            resizingClusterId: clusterId
        )

        XCTAssertTrue(snapshot.clusterConsumedBlockUUIDs.isEmpty)
        XCTAssertEqual(snapshot.renderableBlocks.map { $0.id }, [block.id])
    }

    private var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            let candidate = url.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("CosmoOS.xcodeproj").path) {
                return candidate
            }
            url = candidate
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}

private extension String {
    func slice(from startMarker: String, to endMarker: String) -> String? {
        guard
            let startRange = range(of: startMarker),
            let endRange = range(of: endMarker, range: startRange.upperBound..<endIndex)
        else {
            return nil
        }
        return String(self[startRange.upperBound..<endRange.lowerBound])
    }
}
