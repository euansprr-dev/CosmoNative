import XCTest
@testable import CosmoOS

final class CanvasRenderSnapshotTests: XCTestCase {
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
            boundingRect: CGRect(x: 440, y: 340, width: 260, height: 180),
            colorIndex: 0,
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
            boundingRect: CGRect(x: 440, y: 340, width: 360, height: 280),
            colorIndex: 0,
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
            boundingRect: CGRect(x: 440, y: 340, width: 360, height: 280),
            colorIndex: 0,
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
        XCTAssertEqual(snapshot.renderableBlocks.map(\.id), [block.id])
    }
}
