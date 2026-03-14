import XCTest
@testable import CosmoOS

@MainActor
final class CanvasClusterEngineTests: XCTestCase {
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

        XCTAssertEqual(fitted?.width, 360, accuracy: 0.001)
        XCTAssertEqual(fitted?.height, 280, accuracy: 0.001)
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

        XCTAssertEqual(fitted?.width, 1_100, accuracy: 0.001)
        XCTAssertEqual(fitted?.height, 1_200, accuracy: 0.001)
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

        XCTAssertEqual(fitted?.width, 900, accuracy: 0.001)
        XCTAssertEqual(fitted?.height, 700, accuracy: 0.001)

        engine.userClusters[0].manualSizeOverride = CGSize(width: 5_000, height: 5_000)
        let clamped = engine.fitClusterRectForMode(
            clusterId: clusterId,
            mode: .board,
            blocks: [],
            viewportInCanvas: nil
        )

        XCTAssertEqual(clamped?.width, 1_600, accuracy: 0.001)
        XCTAssertEqual(clamped?.height, 1_200, accuracy: 0.001)
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

        XCTAssertEqual(fitted?.origin.x, 24, accuracy: 0.001)
        XCTAssertEqual(fitted?.origin.y, 24, accuracy: 0.001)
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
        XCTAssertEqual(resolution?.previewPosition.x, 530, accuracy: 0.001)
        XCTAssertEqual(resolution?.previewPosition.y, 128, accuracy: 0.001)
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
        XCTAssertEqual(rect?.origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(rect?.origin.y, 0, accuracy: 0.001)
        XCTAssertEqual(rect?.width, 500, accuracy: 0.001)
        XCTAssertEqual(rect?.height, 360, accuracy: 0.001)
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
        XCTAssertEqual(rect?.origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(rect?.origin.y, 0, accuracy: 0.001)
        XCTAssertEqual(rect?.width, 430, accuracy: 0.001)
        XCTAssertEqual(rect?.height, 360, accuracy: 0.001)
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
        XCTAssertEqual(rect?.origin.x, -30, accuracy: 0.001)
        XCTAssertEqual(rect?.origin.y, -48, accuracy: 0.001)
        XCTAssertEqual(rect?.width, 760, accuracy: 0.001)
        XCTAssertEqual(rect?.height, 248, accuracy: 0.001)
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

        XCTAssertEqual(preview["block-1"]?.position.x, 150, accuracy: 0.001)
        XCTAssertEqual(preview["block-1"]?.position.y, 120, accuracy: 0.001)
        XCTAssertEqual(preview["block-1"]?.size.width, 270, accuracy: 0.001)
        XCTAssertEqual(preview["block-1"]?.size.height, 120, accuracy: 0.001)
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

        XCTAssertEqual(preview["block-1"]?.position.x, 100, accuracy: 0.001)
        XCTAssertEqual(preview["block-1"]?.position.y, 30, accuracy: 0.001)
        XCTAssertEqual(preview["block-1"]?.size.width, 180, accuracy: 0.001)
        XCTAssertEqual(preview["block-1"]?.size.height, 180, accuracy: 0.001)
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

        XCTAssertEqual(preview["block-1"]?.position.x, -50, accuracy: 0.001)
        XCTAssertEqual(preview["block-1"]?.position.y, 30, accuracy: 0.001)
        XCTAssertEqual(preview["block-1"]?.size.width, 270, accuracy: 0.001)
        XCTAssertEqual(preview["block-1"]?.size.height, 180, accuracy: 0.001)
    }
}

private extension CanvasClusterEngineTests {
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
