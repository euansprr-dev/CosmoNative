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
