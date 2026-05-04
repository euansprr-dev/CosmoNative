import SwiftUI
import XCTest
@testable import CosmoOS

final class CanvasSceneSignalBuilderTests: XCTestCase {
    func testBlockSignalsUseViewportAndLiveDragPosition() {
        let transform = CanvasViewportTransform(
            viewportSize: CGSize(width: 1_000, height: 800),
            committedOffset: .zero,
            committedScale: 1
        )
        let dragged = CanvasBlock(
            id: "dragged",
            position: CGPoint(x: -500, y: 400),
            size: CGSize(width: 120, height: 120),
            entityType: .idea,
            entityId: 1,
            entityUuid: "dragged-uuid",
            title: "Dragged"
        )
        let hidden = CanvasBlock(
            id: "hidden",
            position: CGPoint(x: 2_000, y: 400),
            size: CGSize(width: 120, height: 120),
            entityType: .note,
            entityId: 2,
            entityUuid: "hidden-uuid",
            title: "Hidden"
        )

        var activeDrag = ActiveCanvasDragState<String>()
        activeDrag.begin(id: dragged.id, translation: CGSize(width: 520, height: 0))

        let signals = CanvasSceneSignalBuilder.blockSignals(
            blocks: [dragged, hidden],
            transform: transform,
            viewportSize: transform.viewportSize,
            activeBlockDrag: activeDrag,
            draggingClusterId: nil,
            draggingClusterMemberUUIDs: [],
            clusterDragTranslation: .zero,
            consumedBlockUUIDs: []
        )

        XCTAssertEqual(signals.map(\.id), [dragged.id])
        XCTAssertTrue(signals[0].isNearSidebar)
    }

    func testBlockSignalsExcludeConsumedClusterMembersUnlessLiveDragged() {
        let transform = CanvasViewportTransform(
            viewportSize: CGSize(width: 1_000, height: 800),
            committedOffset: .zero,
            committedScale: 1
        )
        let block = CanvasBlock(
            id: "grid-member",
            position: CGPoint(x: 500, y: 400),
            size: CGSize(width: 120, height: 120),
            entityType: .idea,
            entityId: 1,
            entityUuid: "grid-member-uuid",
            title: "Grid member"
        )

        let consumedSignals = CanvasSceneSignalBuilder.blockSignals(
            blocks: [block],
            transform: transform,
            viewportSize: transform.viewportSize,
            activeBlockDrag: ActiveCanvasDragState<String>(),
            draggingClusterId: nil,
            draggingClusterMemberUUIDs: [],
            clusterDragTranslation: .zero,
            consumedBlockUUIDs: [block.entityUuid]
        )

        XCTAssertTrue(consumedSignals.isEmpty)

        let draggedSignals = CanvasSceneSignalBuilder.blockSignals(
            blocks: [block],
            transform: transform,
            viewportSize: transform.viewportSize,
            activeBlockDrag: ActiveCanvasDragState<String>(),
            draggingClusterId: UUID(),
            draggingClusterMemberUUIDs: [block.entityUuid],
            clusterDragTranslation: .zero,
            consumedBlockUUIDs: [block.entityUuid]
        )

        XCTAssertEqual(draggedSignals.map(\.id), [block.id])
    }
}
