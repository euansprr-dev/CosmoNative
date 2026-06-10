import XCTest
@testable import CosmoOS

final class CanvasRenderSnapshotTests: XCTestCase {
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

        XCTAssertGreaterThan(
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

    func testConnectionGeometryInvalidationKeyUsesScalarBlockRevision() {
        let key = CanvasConnectionGeometryInvalidationKey(blockDataRevision: 42)
        let sameKey = CanvasConnectionGeometryInvalidationKey(blockDataRevision: 42)
        let changedKey = CanvasConnectionGeometryInvalidationKey(blockDataRevision: 43)

        XCTAssertEqual(key, sameKey)
        XCTAssertNotEqual(key, changedKey)
        XCTAssertEqual(key.blockDataRevision, 42)
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
