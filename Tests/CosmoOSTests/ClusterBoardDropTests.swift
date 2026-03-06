import XCTest
@testable import CosmoOS

@MainActor
final class ClusterBoardDropTests: XCTestCase {
    func testSameClusterBoardDropUpdatesCanonicalStatus() {
        let clusterId = UUID()
        let blockUUID = "task-1"
        let engine = CanvasClusterEngine()
        engine.userClusters = [
            makeCluster(
                id: clusterId,
                blockUUIDs: [blockUUID],
                rect: CGRect(x: 0, y: 0, width: 600, height: 420)
            )
        ]

        var blocks = [
            makeBlock(uuid: blockUUID, type: .task, metadata: ["status": "pending"])
        ]

        engine.applyBoardDrop(
            event: BoardDropEvent(
                blockUUID: blockUUID,
                targetClusterId: clusterId,
                targetColumnValue: "done"
            ),
            blocks: &blocks
        )

        XCTAssertEqual(engine.userClusters.count, 1)
        XCTAssertEqual(engine.userClusters[0].blockUUIDs, [blockUUID])
        XCTAssertEqual(blocks[0].metadata["status"], "completed")
    }

    func testCrossClusterBoardDropMovesMembershipAndCanonicalizesStatus() {
        let sourceId = UUID()
        let targetId = UUID()
        let blockUUID = "task-2"
        let engine = CanvasClusterEngine()
        engine.userClusters = [
            makeCluster(
                id: sourceId,
                blockUUIDs: [blockUUID],
                rect: CGRect(x: 0, y: 0, width: 600, height: 420)
            ),
            makeCluster(
                id: targetId,
                blockUUIDs: [],
                rect: CGRect(x: 700, y: 0, width: 600, height: 420)
            )
        ]

        var blocks = [
            makeBlock(uuid: blockUUID, type: .task, metadata: ["status": "todo"])
        ]

        engine.applyBoardDrop(
            event: BoardDropEvent(
                blockUUID: blockUUID,
                targetClusterId: targetId,
                targetColumnValue: "in progress"
            ),
            blocks: &blocks
        )

        XCTAssertNil(engine.userClusters.first(where: { $0.id == sourceId }))
        XCTAssertEqual(engine.userClusters.first(where: { $0.id == targetId })?.blockUUIDs, [blockUUID])
        XCTAssertEqual(blocks[0].metadata["status"], "in_progress")

        let codablePayload = engine.userClusters.map(CodableCluster.init(from:))
        XCTAssertEqual(codablePayload.count, 1)
        XCTAssertEqual(codablePayload.first?.id, targetId.uuidString)
        XCTAssertEqual(codablePayload.first?.blockUUIDs, [blockUUID])
    }

    func testTypeGroupingDropDoesNotMutateStatusMetadata() {
        let sourceId = UUID()
        let targetId = UUID()
        let blockUUID = "idea-1"
        let engine = CanvasClusterEngine()

        var targetCluster = makeCluster(
            id: targetId,
            blockUUIDs: [],
            rect: CGRect(x: 700, y: 0, width: 600, height: 420)
        )
        targetCluster.boardGrouping = .type

        engine.userClusters = [
            makeCluster(
                id: sourceId,
                blockUUIDs: [blockUUID],
                rect: CGRect(x: 0, y: 0, width: 600, height: 420)
            ),
            targetCluster
        ]

        var blocks = [
            makeBlock(uuid: blockUUID, type: .idea, metadata: ["ideaStatus": "developing"])
        ]

        engine.applyBoardDrop(
            event: BoardDropEvent(
                blockUUID: blockUUID,
                targetClusterId: targetId,
                targetColumnValue: "task"
            ),
            blocks: &blocks
        )

        XCTAssertEqual(engine.userClusters.first(where: { $0.id == targetId })?.blockUUIDs, [blockUUID])
        XCTAssertEqual(blocks[0].metadata["ideaStatus"], "developing")
    }
}

private extension ClusterBoardDropTests {
    func makeCluster(
        id: UUID,
        blockUUIDs: [String],
        rect: CGRect
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
            manualSizeOverride: nil,
            isZone: false,
            zoneType: nil,
            viewMode: .board
        )
    }

    func makeBlock(uuid: String, type: EntityType, metadata: [String: String]) -> CanvasBlock {
        CanvasBlock(
            id: "block-\(uuid)",
            position: CGPoint(x: 100, y: 100),
            size: CGSize(width: 280, height: 180),
            entityType: type,
            entityId: 1,
            entityUuid: uuid,
            title: "Block",
            metadata: metadata
        )
    }
}
