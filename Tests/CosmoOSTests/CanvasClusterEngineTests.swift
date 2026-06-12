import XCTest
@testable import CosmoOS

@MainActor
final class CanvasClusterEngineTests: XCTestCase {
    func testClusterPaletteDefinesOpaqueSystemBaseColors() {
        XCTAssertEqual(
            CanvasCluster.paletteHexes,
            [
                "5E5CE6",
                "AF52DE",
                "FF2D55",
                "FF9F0A",
                "34C759",
                "64D2FF",
                "0A84FF",
                "FF6B35",
            ]
        )
        XCTAssertEqual(CanvasCluster.palette.count, CanvasCluster.paletteHexes.count)
    }

    func testFitClusterRectForListAppliesMinimumSize() {
        let clusterId = UUID()
        let engine = CanvasClusterEngine()
        engine.userClusters = [
            makeCluster(
                id: clusterId,
                blockUUIDs: [],
                rect: CGRect(x: 0, y: 0, width: 120, height: 100),
                viewMode: .list
            )
        ]

        let fitted = engine.fitClusterRectForMode(
            clusterId: clusterId,
            mode: .list,
            blocks: [],
            viewportInCanvas: nil
        )

        assertEqualCGFloat(fitted?.width, 360, accuracy: 0.001)
        assertEqualCGFloat(fitted?.height, 280, accuracy: 0.001)
    }

    func testFitClusterRectForListAppliesMaximumSize() {
        let clusterId = UUID()
        let engine = CanvasClusterEngine()
        engine.userClusters = [
            makeCluster(
                id: clusterId,
                blockUUIDs: [],
                rect: CGRect(x: 0, y: 0, width: 4_000, height: 3_000),
                viewMode: .list
            )
        ]

        let fitted = engine.fitClusterRectForMode(
            clusterId: clusterId,
            mode: .list,
            blocks: [],
            viewportInCanvas: nil
        )

        assertEqualCGFloat(fitted?.width, 1_100, accuracy: 0.001)
        assertEqualCGFloat(fitted?.height, 1_200, accuracy: 0.001)
    }

    func testFitClusterRectRespectsManualOverrideWithinClamps() {
        let clusterId = UUID()
        let engine = CanvasClusterEngine()
        engine.userClusters = [
            makeCluster(
                id: clusterId,
                blockUUIDs: [],
                rect: CGRect(x: 0, y: 0, width: 400, height: 300),
                viewMode: .board,
                manual: CGSize(width: 900, height: 700)
            )
        ]

        let fitted = engine.fitClusterRectForMode(
            clusterId: clusterId,
            mode: .board,
            blocks: [],
            viewportInCanvas: nil
        )

        assertEqualCGFloat(fitted?.width, 900, accuracy: 0.001)
        assertEqualCGFloat(fitted?.height, 700, accuracy: 0.001)

        engine.userClusters[0].manualSizeOverride = CGSize(width: 5_000, height: 5_000)
        let clamped = engine.fitClusterRectForMode(
            clusterId: clusterId,
            mode: .board,
            blocks: [],
            viewportInCanvas: nil
        )

        assertEqualCGFloat(clamped?.width, 1_600, accuracy: 0.001)
        assertEqualCGFloat(clamped?.height, 1_200, accuracy: 0.001)
    }

    func testSetViewModeCanvasClearsManualOverrideAndAutoFitsMembers() {
        let clusterId = UUID()
        let blockUUID = "b-1"
        let block = makeBlock(uuid: blockUUID, type: .note, position: CGPoint(x: 500, y: 400), size: CGSize(width: 180, height: 120))
        let engine = CanvasClusterEngine()
        engine.userClusters = [
            makeCluster(
                id: clusterId,
                blockUUIDs: [blockUUID],
                rect: CGRect(x: 100, y: 100, width: 700, height: 500),
                viewMode: .board,
                manual: CGSize(width: 700, height: 500)
            )
        ]

        engine.setViewMode(for: clusterId, mode: .canvas, blocks: [block])

        guard let cluster = engine.userClusters.first(where: { $0.id == clusterId }) else {
            XCTFail("Expected cluster to exist")
            return
        }

        XCTAssertEqual(cluster.viewMode, .canvas)
        XCTAssertNil(cluster.manualSizeOverride)
        XCTAssertGreaterThan(cluster.boundingRect.width, block.size.width)
        XCTAssertGreaterThan(cluster.boundingRect.height, block.size.height)
    }

    func testSetViewModeGridComputesInitialFixedManualSize() {
        let clusterId = UUID()
        let blocks = [
            makeBlock(uuid: "b-1", type: .note, position: CGPoint(x: 120, y: 120), size: CGSize(width: 180, height: 120)),
            makeBlock(uuid: "b-2", type: .research, position: CGPoint(x: 360, y: 120), size: CGSize(width: 320, height: 230))
        ]
        let engine = CanvasClusterEngine()
        engine.userClusters = [
            makeCluster(
                id: clusterId,
                blockUUIDs: blocks.map(\.entityUuid),
                rect: CGRect(x: 0, y: 0, width: 420, height: 260),
                viewMode: .canvas
            )
        ]

        engine.setViewMode(for: clusterId, mode: .grid, blocks: blocks)

        guard let cluster = engine.userClusters.first(where: { $0.id == clusterId }) else {
            XCTFail("Expected cluster to exist")
            return
        }

        XCTAssertEqual(cluster.viewMode, .grid)
        XCTAssertGreaterThanOrEqual(cluster.boundingRect.width, 600)
        XCTAssertGreaterThanOrEqual(cluster.boundingRect.height, 400)
        XCTAssertEqual(cluster.manualSizeOverride, cluster.boundingRect.size)
    }

    func testDocumentBlocksUsePageSizedCreationDefaults() {
        let note = CanvasBlock.noteBlock(position: .zero)
        let content = CanvasBlock(
            position: .zero,
            entityType: .content,
            entityId: 1,
            entityUuid: "content-1",
            title: "Draft"
        )

        XCTAssertEqual(note.size.width, CanvasBlock.documentBlockSize.width, accuracy: 0.001)
        XCTAssertEqual(note.size.height, CanvasBlock.documentBlockSize.height, accuracy: 0.001)
        XCTAssertEqual(note.defaultSize.width, CanvasBlock.documentLayoutSize.width, accuracy: 0.001)
        XCTAssertEqual(note.defaultSize.height, CanvasBlock.documentLayoutSize.height, accuracy: 0.001)
        XCTAssertEqual(content.defaultSize.width, CanvasBlock.documentLayoutSize.width, accuracy: 0.001)
        XCTAssertEqual(content.defaultSize.height, CanvasBlock.documentLayoutSize.height, accuracy: 0.001)
        XCTAssertEqual(CanvasBlock.documentBlockSize.width, 453.333, accuracy: 0.001)
        XCTAssertEqual(CanvasBlock.documentBlockSize.height, 586.667, accuracy: 0.001)
    }

    func testGridUsesFullDocumentFootprintForNoteAndContentBlocks() {
        let note = makeBlock(uuid: "note-1", type: .note, position: .zero, size: CanvasBlock.documentBlockSize)
        let content = makeBlock(uuid: "content-1", type: .content, position: .zero, size: CanvasBlock.documentBlockSize)

        XCTAssertEqual(ClusterGridContent.canonicalCellWidth(for: note), CanvasBlock.documentBlockSize.width, accuracy: 0.001)
        XCTAssertEqual(ClusterGridContent.canonicalCellHeight(for: note), CanvasBlock.documentBlockSize.height, accuracy: 0.001)
        XCTAssertEqual(ClusterGridContent.canonicalCellWidth(for: content), CanvasBlock.documentBlockSize.width, accuracy: 0.001)
        XCTAssertEqual(ClusterGridContent.canonicalCellHeight(for: content), CanvasBlock.documentBlockSize.height, accuracy: 0.001)
    }

    func testGridPacksTwoDocumentBlocksIntoOneRowWithOnlySpacingBetweenThem() {
        let note = makeBlock(uuid: "note-1", type: .note, position: .zero, size: CanvasBlock.documentBlockSize)
        let content = makeBlock(uuid: "content-1", type: .content, position: .zero, size: CanvasBlock.documentBlockSize)
        let availableWidth = CanvasBlock.documentBlockSize.width * 2 + 10

        let height = ClusterGridContent.estimatedGridHeight(blocks: [note, content], availableWidth: availableWidth)

        XCTAssertEqual(height, CanvasBlock.documentBlockSize.height, accuracy: 0.001)
    }

    func testSettingGridModeAgainDoesNotRefitExistingGridRect() {
        let clusterId = UUID()
        let blocks = (0..<12).map { index in
            makeBlock(
                uuid: "b-\(index)",
                type: .note,
                position: CGPoint(x: CGFloat(index * 220), y: 120),
                size: CGSize(width: 180, height: 120)
            )
        }
        let rect = CGRect(x: 40, y: 80, width: 620, height: 420)
        let manual = CGSize(width: 620, height: 420)
        let engine = CanvasClusterEngine()
        engine.userClusters = [
            makeCluster(
                id: clusterId,
                blockUUIDs: blocks.map(\.entityUuid),
                rect: rect,
                viewMode: .grid,
                manual: manual
            )
        ]

        engine.setViewMode(for: clusterId, mode: .grid, blocks: blocks)

        let cluster = engine.userClusters.first(where: { $0.id == clusterId })
        XCTAssertEqual(cluster?.boundingRect, rect)
        XCTAssertEqual(cluster?.manualSizeOverride, manual)
    }

    func testFitClusterRectClampsToViewportMargins() {
        let clusterId = UUID()
        let engine = CanvasClusterEngine()
        engine.userClusters = [
            makeCluster(
                id: clusterId,
                blockUUIDs: [],
                rect: CGRect(x: -300, y: -200, width: 900, height: 700),
                viewMode: .list
            )
        ]

        let fitted = engine.fitClusterRectForMode(
            clusterId: clusterId,
            mode: .list,
            blocks: [],
            viewportInCanvas: CGRect(x: 0, y: 0, width: 1_000, height: 800)
        )

        assertEqualCGFloat(fitted?.origin.x, 24, accuracy: 0.001)
        assertEqualCGFloat(fitted?.origin.y, 24, accuracy: 0.001)
    }

    func testUserClusterContainingPrefersClosestOverlappingCluster() {
        let outerId = UUID()
        let innerId = UUID()
        let engine = CanvasClusterEngine()
        engine.userClusters = [
            makeCluster(
                id: outerId,
                blockUUIDs: [],
                rect: CGRect(x: 0, y: 0, width: 400, height: 300),
                viewMode: .canvas
            ),
            makeCluster(
                id: innerId,
                blockUUIDs: [],
                rect: CGRect(x: 300, y: 0, width: 200, height: 300),
                viewMode: .canvas
            )
        ]

        let resolved = engine.userCluster(containing: CGPoint(x: 350, y: 150))

        XCTAssertEqual(resolved?.id, innerId)
    }

    func testResolveCanvasDropExcludesSourceClusterAndClampsPreviewInsideTarget() {
        let sourceId = UUID()
        let targetId = UUID()
        let blockUUID = "moving-block"
        let engine = CanvasClusterEngine()
        engine.userClusters = [
            makeCluster(
                id: sourceId,
                blockUUIDs: [blockUUID],
                rect: CGRect(x: 0, y: 0, width: 320, height: 260),
                viewMode: .canvas
            ),
            makeCluster(
                id: targetId,
                blockUUIDs: [],
                rect: CGRect(x: 420, y: 0, width: 400, height: 320),
                viewMode: .canvas
            )
        ]

        let resolution = engine.resolveCanvasDrop(
            blockUUID: blockUUID,
            point: CGPoint(x: 390, y: 60),
            blockSize: CGSize(width: 180, height: 120)
        )

        XCTAssertEqual(resolution?.clusterId, targetId)
        assertEqualCGFloat(resolution?.previewPosition.x, 530, accuracy: 0.001)
        assertEqualCGFloat(resolution?.previewPosition.y, 128, accuracy: 0.001)
    }

    func testUpdateUserClusterBoundsPreservesCanvasRectWhenMembersStayInside() {
        let clusterId = UUID()
        let block = makeBlock(
            uuid: "b-1",
            type: .note,
            position: CGPoint(x: 180, y: 180),
            size: CGSize(width: 180, height: 120)
        )

        let engine = CanvasClusterEngine()
        engine.userClusters = [
            makeCluster(
                id: clusterId,
                blockUUIDs: [block.entityUuid],
                rect: CGRect(x: 0, y: 0, width: 500, height: 360),
                viewMode: .canvas
            )
        ]

        engine.updateUserClusterBounds(blocks: [block])

        let rect = engine.userClusters.first(where: { $0.id == clusterId })?.boundingRect
        assertEqualCGFloat(rect?.origin.x, 0, accuracy: 0.001)
        assertEqualCGFloat(rect?.origin.y, 0, accuracy: 0.001)
        assertEqualCGFloat(rect?.width, 500, accuracy: 0.001)
        assertEqualCGFloat(rect?.height, 360, accuracy: 0.001)
    }

    func testUpdateUserClusterBoundsExpandsOnlyNeededEdgeWhenMemberLeavesCluster() {
        let clusterId = UUID()
        let block = makeBlock(
            uuid: "b-1",
            type: .note,
            position: CGPoint(x: 300, y: 180),
            size: CGSize(width: 180, height: 120)
        )

        let engine = CanvasClusterEngine()
        engine.userClusters = [
            makeCluster(
                id: clusterId,
                blockUUIDs: [block.entityUuid],
                rect: CGRect(x: 0, y: 0, width: 280, height: 360),
                viewMode: .canvas
            )
        ]

        engine.updateUserClusterBounds(blocks: [block])

        let rect = engine.userClusters.first(where: { $0.id == clusterId })?.boundingRect
        assertEqualCGFloat(rect?.origin.x, 0, accuracy: 0.001)
        assertEqualCGFloat(rect?.origin.y, 0, accuracy: 0.001)
        assertEqualCGFloat(rect?.width, 430, accuracy: 0.001)
        assertEqualCGFloat(rect?.height, 360, accuracy: 0.001)
    }

    func testRemoveBlockFromCanvasClusterKeepsContainerRect() {
        let clusterId = UUID()
        let firstBlock = makeBlock(
            uuid: "b-1",
            type: .note,
            position: CGPoint(x: 100, y: 100),
            size: CGSize(width: 180, height: 120)
        )
        let secondBlock = makeBlock(
            uuid: "b-2",
            type: .note,
            position: CGPoint(x: 600, y: 100),
            size: CGSize(width: 180, height: 120)
        )

        let engine = CanvasClusterEngine()
        engine.userClusters = [
            makeCluster(
                id: clusterId,
                blockUUIDs: [firstBlock.entityUuid, secondBlock.entityUuid],
                rect: CGRect(x: -30, y: -48, width: 760, height: 248),
                viewMode: .canvas
            )
        ]

        engine.removeBlockFromCluster(
            blockUUID: secondBlock.entityUuid,
            clusterId: clusterId,
            blocks: [firstBlock, secondBlock]
        )

        let rect = engine.userClusters.first(where: { $0.id == clusterId })?.boundingRect
        assertEqualCGFloat(rect?.origin.x, -30, accuracy: 0.001)
        assertEqualCGFloat(rect?.origin.y, -48, accuracy: 0.001)
        assertEqualCGFloat(rect?.width, 760, accuracy: 0.001)
        assertEqualCGFloat(rect?.height, 248, accuracy: 0.001)
    }

    func testAddBlockToGridClusterAppendsWithoutResizingContainer() {
        let clusterId = UUID()
        let firstBlock = makeBlock(uuid: "b-1", type: .note, position: CGPoint(x: 100, y: 100), size: CGSize(width: 180, height: 120))
        let newBlock = makeBlock(uuid: "b-2", type: .research, position: CGPoint(x: 500, y: 100), size: CGSize(width: 320, height: 230))
        let rect = CGRect(x: 20, y: 40, width: 640, height: 420)
        let manual = CGSize(width: 640, height: 420)
        let engine = CanvasClusterEngine()
        engine.userClusters = [
            makeCluster(
                id: clusterId,
                blockUUIDs: [firstBlock.entityUuid],
                rect: rect,
                viewMode: .grid,
                manual: manual
            )
        ]

        engine.addBlockToCluster(
            blockUUID: newBlock.entityUuid,
            clusterId: clusterId,
            blocks: [newBlock, firstBlock]
        )

        let cluster = engine.userClusters.first(where: { $0.id == clusterId })
        XCTAssertEqual(cluster?.blockUUIDs, [firstBlock.entityUuid, newBlock.entityUuid])
        XCTAssertEqual(cluster?.boundingRect, rect)
        XCTAssertEqual(cluster?.manualSizeOverride, manual)
    }

    func testRemoveBlockFromGridClusterDoesNotResizeContainer() {
        let clusterId = UUID()
        let firstBlock = makeBlock(uuid: "b-1", type: .note, position: CGPoint(x: 100, y: 100), size: CGSize(width: 180, height: 120))
        let secondBlock = makeBlock(uuid: "b-2", type: .note, position: CGPoint(x: 500, y: 100), size: CGSize(width: 180, height: 120))
        let rect = CGRect(x: 20, y: 40, width: 640, height: 420)
        let manual = CGSize(width: 640, height: 420)
        let engine = CanvasClusterEngine()
        engine.userClusters = [
            makeCluster(
                id: clusterId,
                blockUUIDs: [firstBlock.entityUuid, secondBlock.entityUuid],
                rect: rect,
                viewMode: .grid,
                manual: manual
            )
        ]

        engine.removeBlockFromCluster(
            blockUUID: firstBlock.entityUuid,
            clusterId: clusterId,
            blocks: [firstBlock, secondBlock]
        )

        let cluster = engine.userClusters.first(where: { $0.id == clusterId })
        XCTAssertEqual(cluster?.blockUUIDs, [secondBlock.entityUuid])
        XCTAssertEqual(cluster?.boundingRect, rect)
        XCTAssertEqual(cluster?.manualSizeOverride, manual)
    }

    func testTransferBlockBetweenGridClustersAppendsWithoutResizingEitherContainer() {
        let sourceId = UUID()
        let targetId = UUID()
        let remainingBlock = makeBlock(uuid: "source-remaining", type: .note, position: CGPoint(x: 100, y: 100), size: CGSize(width: 180, height: 120))
        let movingBlock = makeBlock(uuid: "moving", type: .note, position: CGPoint(x: 320, y: 100), size: CGSize(width: 180, height: 120))
        let targetBlock = makeBlock(uuid: "target-existing", type: .task, position: CGPoint(x: 700, y: 100), size: CGSize(width: 180, height: 120))
        let sourceRect = CGRect(x: 20, y: 40, width: 640, height: 420)
        let targetRect = CGRect(x: 800, y: 40, width: 700, height: 460)
        let sourceManual = sourceRect.size
        let targetManual = targetRect.size
        let engine = CanvasClusterEngine()
        engine.userClusters = [
            makeCluster(
                id: sourceId,
                blockUUIDs: [remainingBlock.entityUuid, movingBlock.entityUuid],
                rect: sourceRect,
                viewMode: .grid,
                manual: sourceManual
            ),
            makeCluster(
                id: targetId,
                blockUUIDs: [targetBlock.entityUuid],
                rect: targetRect,
                viewMode: .grid,
                manual: targetManual
            )
        ]

        engine.transferBlock(
            blockUUID: movingBlock.entityUuid,
            from: sourceId,
            to: targetId,
            blocks: [targetBlock, movingBlock, remainingBlock]
        )

        let source = engine.userClusters.first(where: { $0.id == sourceId })
        let target = engine.userClusters.first(where: { $0.id == targetId })
        XCTAssertEqual(source?.blockUUIDs, [remainingBlock.entityUuid])
        XCTAssertEqual(source?.boundingRect, sourceRect)
        XCTAssertEqual(source?.manualSizeOverride, sourceManual)
        XCTAssertEqual(target?.blockUUIDs, [targetBlock.entityUuid, movingBlock.entityUuid])
        XCTAssertEqual(target?.boundingRect, targetRect)
        XCTAssertEqual(target?.manualSizeOverride, targetManual)
    }

    func testGridContentOrdersMembersByClusterMembershipOrder() {
        let a = makeBlock(uuid: "a", type: .note, position: .zero, size: CGSize(width: 180, height: 120))
        let b = makeBlock(uuid: "b", type: .task, position: .zero, size: CGSize(width: 180, height: 120))
        let c = makeBlock(uuid: "c", type: .research, position: .zero, size: CGSize(width: 320, height: 230))
        let cluster = makeCluster(
            id: UUID(),
            blockUUIDs: [a.entityUuid, c.entityUuid, b.entityUuid],
            rect: CGRect(x: 0, y: 0, width: 640, height: 420),
            viewMode: .grid
        )

        let ordered = ClusterGridContent.orderedMemberBlocks(for: cluster, blocks: [b, a, c])

        XCTAssertEqual(ordered.map(\.entityUuid), [a.entityUuid, c.entityUuid, b.entityUuid])
    }

    func testAltModeClusterMoveHitTestingAllowsHeaderAndBorderChromeOnly() {
        let rect = CGRect(x: 100, y: 200, width: 640, height: 420)

        XCTAssertTrue(
            CanvasClusterMoveHitTesting.allowsDragStart(
                at: CGPoint(x: 260, y: 222),
                in: rect,
                hasAltContent: true
            )
        )
        XCTAssertTrue(
            CanvasClusterMoveHitTesting.allowsDragStart(
                at: CGPoint(x: 108, y: 360),
                in: rect,
                hasAltContent: true
            )
        )
        XCTAssertFalse(
            CanvasClusterMoveHitTesting.allowsDragStart(
                at: CGPoint(x: 260, y: 360),
                in: rect,
                hasAltContent: true
            )
        )
    }

    func testPersistedCanvasClusterRectRemainsAuthoritativeWhenMembersFitInside() {
        let block = makeBlock(
            uuid: "b-1",
            type: .note,
            position: CGPoint(x: 180, y: 180),
            size: CGSize(width: 180, height: 120)
        )

        let codable = CodableCluster(
            id: UUID().uuidString,
            name: "Cluster",
            blockUUIDs: [block.entityUuid],
            colorIndex: 0,
            originX: 0,
            originY: 0,
            rectWidth: 500,
            rectHeight: 360
        )

        let cluster = codable.toCanvasCluster(blocks: [block], thinkspaceId: nil)

        XCTAssertEqual(cluster.boundingRect.origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(cluster.boundingRect.origin.y, 0, accuracy: 0.001)
        XCTAssertEqual(cluster.boundingRect.width, 500, accuracy: 0.001)
        XCTAssertEqual(cluster.boundingRect.height, 360, accuracy: 0.001)
    }

    func testPersistedCanvasClusterRectExpandsWhenMemberFallsOutside() {
        let block = makeBlock(
            uuid: "b-1",
            type: .note,
            position: CGPoint(x: 320, y: 180),
            size: CGSize(width: 180, height: 120)
        )

        let codable = CodableCluster(
            id: UUID().uuidString,
            name: "Cluster",
            blockUUIDs: [block.entityUuid],
            colorIndex: 0,
            originX: 0,
            originY: 0,
            rectWidth: 300,
            rectHeight: 280
        )

        let cluster = codable.toCanvasCluster(blocks: [block], thinkspaceId: nil)

        XCTAssertEqual(cluster.boundingRect.origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(cluster.boundingRect.origin.y, 0, accuracy: 0.001)
        XCTAssertEqual(cluster.boundingRect.width, 450, accuracy: 0.001)
        XCTAssertEqual(cluster.boundingRect.height, 280, accuracy: 0.001)
    }

    func testPersistedGridClusterRectRemainsAuthoritativeRegardlessOfMemberPositions() {
        let block = makeBlock(
            uuid: "b-1",
            type: .note,
            position: CGPoint(x: 2_400, y: 1_800),
            size: CGSize(width: 180, height: 120)
        )
        let manual = CGSize(width: 620, height: 420)

        let codable = CodableCluster(
            id: UUID().uuidString,
            name: "Grid Cluster",
            blockUUIDs: [block.entityUuid],
            colorIndex: 0,
            originX: 40,
            originY: 80,
            rectWidth: Double(manual.width),
            rectHeight: Double(manual.height),
            manualWidth: Double(manual.width),
            manualHeight: Double(manual.height),
            viewMode: ClusterViewMode.grid.rawValue
        )

        let cluster = codable.toCanvasCluster(blocks: [block], thinkspaceId: nil)

        XCTAssertEqual(cluster.boundingRect, CGRect(origin: CGPoint(x: 40, y: 80), size: manual))
        XCTAssertEqual(cluster.manualSizeOverride, manual)
    }

    func testCanvasClusterResizeMapperScalesHorizontalEdgeFromOppositeAnchor() {
        let preview = CanvasClusterResizeMapper.previewGeometries(
            from: CGRect(x: 0, y: 0, width: 400, height: 300),
            to: CGRect(x: 0, y: 0, width: 600, height: 300),
            edge: .right,
            members: [
                "block-1": CanvasBlockGeometry(
                    position: CGPoint(x: 100, y: 120),
                    size: CGSize(width: 180, height: 120)
                )
            ]
        )

        assertEqualCGFloat(preview["block-1"]?.position.x, 150, accuracy: 0.001)
        assertEqualCGFloat(preview["block-1"]?.position.y, 120, accuracy: 0.001)
        assertEqualCGFloat(preview["block-1"]?.size.width, 270, accuracy: 0.001)
        assertEqualCGFloat(preview["block-1"]?.size.height, 120, accuracy: 0.001)
    }

    func testCanvasClusterResizeMapperScalesVerticalEdgeFromOppositeAnchor() {
        let preview = CanvasClusterResizeMapper.previewGeometries(
            from: CGRect(x: 0, y: 0, width: 400, height: 300),
            to: CGRect(x: 0, y: -150, width: 400, height: 450),
            edge: .top,
            members: [
                "block-1": CanvasBlockGeometry(
                    position: CGPoint(x: 100, y: 120),
                    size: CGSize(width: 180, height: 120)
                )
            ]
        )

        assertEqualCGFloat(preview["block-1"]?.position.x, 100, accuracy: 0.001)
        assertEqualCGFloat(preview["block-1"]?.position.y, 30, accuracy: 0.001)
        assertEqualCGFloat(preview["block-1"]?.size.width, 180, accuracy: 0.001)
        assertEqualCGFloat(preview["block-1"]?.size.height, 180, accuracy: 0.001)
    }

    func testCanvasClusterResizeMapperScalesCornerFromOppositeAnchor() {
        let preview = CanvasClusterResizeMapper.previewGeometries(
            from: CGRect(x: 0, y: 0, width: 400, height: 300),
            to: CGRect(x: -200, y: -150, width: 600, height: 450),
            edge: .topLeft,
            members: [
                "block-1": CanvasBlockGeometry(
                    position: CGPoint(x: 100, y: 120),
                    size: CGSize(width: 180, height: 120)
                )
            ]
        )

        assertEqualCGFloat(preview["block-1"]?.position.x, -50, accuracy: 0.001)
        assertEqualCGFloat(preview["block-1"]?.position.y, 30, accuracy: 0.001)
        assertEqualCGFloat(preview["block-1"]?.size.width, 270, accuracy: 0.001)
        assertEqualCGFloat(preview["block-1"]?.size.height, 180, accuracy: 0.001)
    }

    func testThinkspaceLibrarySnapshotGroupsClusteredAndInventoryItems() {
        let cluster = makeCluster(
            id: UUID(),
            blockUUIDs: ["clustered-visible", "clustered-inventory"],
            rect: CGRect(x: 0, y: 0, width: 400, height: 300),
            viewMode: .canvas
        )
        var visibleBlock = makeBlock(uuid: "clustered-visible", type: .note, position: .zero, size: CGSize(width: 180, height: 120))
        visibleBlock.title = "Visible Note"
        let inventoryOnly = ChildDoc(
            id: "doc-1",
            entityType: .research,
            entityId: 2,
            entityUuid: "clustered-inventory",
            title: "Stored Source",
            outlineReferenceCount: 0
        )
        let looseInventory = ChildDoc(
            id: "doc-2",
            entityType: .task,
            entityId: 3,
            entityUuid: "loose-inventory",
            title: "Loose Task",
            outlineReferenceCount: 0
        )

        let snapshot = ThinkspaceLibrarySnapshot.make(
            blocks: [visibleBlock],
            clusters: [cluster],
            inventory: [inventoryOnly, looseInventory]
        )

        XCTAssertEqual(snapshot.folders.count, 1)
        XCTAssertEqual(snapshot.folders[0].items.map(\.title), ["Stored Source", "Visible Note"])
        XCTAssertEqual(snapshot.looseItems.map(\.title), ["Loose Task"])
        XCTAssertTrue(snapshot.folders[0].items.contains { $0.entityUuid == "clustered-inventory" && !$0.isOnCanvas })
    }

    func testCommandKPrimaryTabsExcludeInquiry() {
        XCTAssertFalse(CommandKTab.allCases.contains(.inquiry))
    }

    // MARK: - ThinkspaceLibrarySnapshot (Library mode)

    func testThinkspaceLibrarySnapshotPartitionsClusteredAndLooseBlocks() {
        let a = makeBlock(uuid: "a", type: .note, position: .zero, size: CGSize(width: 100, height: 100))
        let b = makeBlock(uuid: "b", type: .idea, position: .zero, size: CGSize(width: 100, height: 100))
        let c = makeBlock(uuid: "c", type: .content, position: .zero, size: CGSize(width: 100, height: 100))
        let cluster = makeCluster(
            id: UUID(),
            blockUUIDs: ["a"],
            rect: CGRect(x: 0, y: 0, width: 300, height: 200),
            viewMode: .canvas
        )

        let snapshot = ThinkspaceLibrarySnapshot.make(blocks: [a, b, c], clusters: [cluster], inventory: [])

        XCTAssertEqual(snapshot.folders.count, 1)
        XCTAssertEqual(snapshot.folders.first?.items.map(\.entityUuid), ["a"])
        XCTAssertEqual(Set(snapshot.looseItems.map(\.entityUuid)), ["b", "c"])
        // A clustered item must never also appear in the loose tray.
        XCTAssertFalse(snapshot.looseItems.contains { $0.entityUuid == "a" })
        // On-canvas blocks are flagged so the tile reads "On canvas".
        XCTAssertTrue(snapshot.folders.first?.items.first?.isOnCanvas ?? false)
    }

    func testThinkspaceLibrarySnapshotFolderReflectsMembershipChange() {
        let blocks = [
            makeBlock(uuid: "a", type: .note, position: .zero, size: CGSize(width: 100, height: 100)),
            makeBlock(uuid: "b", type: .idea, position: .zero, size: CGSize(width: 100, height: 100)),
            makeBlock(uuid: "c", type: .content, position: .zero, size: CGSize(width: 100, height: 100)),
        ]
        let clusterId = UUID()
        let rect = CGRect(x: 0, y: 0, width: 300, height: 200)

        let before = ThinkspaceLibrarySnapshot.make(
            blocks: blocks,
            clusters: [makeCluster(id: clusterId, blockUUIDs: [], rect: rect, viewMode: .canvas)],
            inventory: []
        )
        XCTAssertTrue(before.folders.first?.items.isEmpty ?? false)
        XCTAssertEqual(Set(before.looseItems.map(\.entityUuid)), ["a", "b", "c"])

        // Filing "a" and "b" into the folder (what drag-to-file persists via the cluster
        // engine) must move them out of the loose tray and into the folder.
        let after = ThinkspaceLibrarySnapshot.make(
            blocks: blocks,
            clusters: [makeCluster(id: clusterId, blockUUIDs: ["a", "b"], rect: rect, viewMode: .canvas)],
            inventory: []
        )
        XCTAssertEqual(Set(after.folders.first?.items.map(\.entityUuid) ?? []), ["a", "b"])
        XCTAssertEqual(after.looseItems.map(\.entityUuid), ["c"])
    }
}

private extension CanvasClusterEngineTests {

    func assertEqualCGFloat(
        _ expression1: @autoclosure () throws -> CGFloat?,
        _ expression2: @autoclosure () throws -> CGFloat,
        accuracy: CGFloat,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) rethrows {
        guard let value = try expression1() else {
            XCTFail("Expected non-nil CGFloat. \(message())", file: file, line: line)
            return
        }

        let expected = try expression2()
        XCTAssertEqual(value, expected, accuracy: accuracy, message(), file: file, line: line)
    }

    func makeCluster(
        id: UUID,
        blockUUIDs: [String],
        rect: CGRect,
        viewMode: ClusterViewMode,
        manual: CGSize? = nil
    ) -> CanvasCluster {
        CanvasCluster(
            id: id,
            name: "Cluster",
            blockUUIDs: blockUUIDs,
            colorIndex: 0,
            boundingRect: rect,
            isCollapsed: false,
            isUserCreated: true,
            thinkspaceId: nil,
            synthesis: nil,
            synthesisUpdatedAt: nil,
            manualSizeOverride: manual,
            isZone: false,
            zoneType: nil,
            viewMode: viewMode
        )
    }

    func makeBlock(
        uuid: String,
        type: EntityType,
        position: CGPoint,
        size: CGSize
    ) -> CanvasBlock {
        CanvasBlock(
            id: "block-\(uuid)",
            position: position,
            size: size,
            entityType: type,
            entityId: 1,
            entityUuid: uuid,
            title: "Block",
            metadata: [:]
        )
    }
}
