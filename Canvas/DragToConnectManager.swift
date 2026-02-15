// CosmoOS/Canvas/DragToConnectManager.swift
// Manages Option+drag connection gesture between canvas blocks

import SwiftUI

@MainActor
final class DragToConnectManager: ObservableObject {
    @Published var isActive = false
    @Published var sourceBlock: CanvasBlock?
    @Published var sourceCenter: CGPoint = .zero
    @Published var currentDragPoint: CGPoint = .zero
    @Published var hoveredTargetBlockId: String?
    @Published var connectionComplete = false

    /// Begin a connection drag from a source block
    func beginConnection(from block: CanvasBlock, center: CGPoint) {
        isActive = true
        sourceBlock = block
        sourceCenter = center
        currentDragPoint = center
        hoveredTargetBlockId = nil
        connectionComplete = false
    }

    /// Update the drag point during the gesture
    func updateDrag(to point: CGPoint) {
        currentDragPoint = point
    }

    /// Cancel the connection drag
    func cancel() {
        withAnimation(.spring(response: 0.2)) {
            isActive = false
            sourceBlock = nil
            hoveredTargetBlockId = nil
            connectionComplete = false
        }
    }

    /// Complete the connection between source and target blocks
    func completeConnection(targetBlock: CanvasBlock) {
        guard let sourceBlock = sourceBlock,
              sourceBlock.id != targetBlock.id else {
            cancel()
            return
        }

        connectionComplete = true

        // Create bidirectional AtomLink on both atoms
        Task {
            do {
                guard let sourceAtom = try await AtomRepository.shared.fetch(uuid: sourceBlock.entityUuid),
                      let targetAtom = try await AtomRepository.shared.fetch(uuid: targetBlock.entityUuid) else {
                    cancel()
                    return
                }

                // Add related link on source atom (if not already linked)
                var finalSource = sourceAtom
                if !sourceAtom.linksList.contains(where: { $0.uuid == targetAtom.uuid }) {
                    let newLink = AtomLink.related(targetAtom.uuid, entityType: AtomType(rawValue: targetBlock.entityType.rawValue))
                    finalSource = sourceAtom.addingLink(newLink)
                    try await AtomRepository.shared.update(finalSource)
                }

                // Add related link on target atom (if not already linked)
                var finalTarget = targetAtom
                if !targetAtom.linksList.contains(where: { $0.uuid == sourceAtom.uuid }) {
                    let reverseLink = AtomLink.related(sourceAtom.uuid, entityType: AtomType(rawValue: sourceBlock.entityType.rawValue))
                    finalTarget = targetAtom.addingLink(reverseLink)
                    try await AtomRepository.shared.update(finalTarget)
                }

                // Tell NodeGraphEngine to reconcile edges (creates graph_edges rows)
                try await NodeGraphEngine.shared.handleAtomUpdated(finalSource, changedFields: ["links"])
                try await NodeGraphEngine.shared.handleAtomUpdated(finalTarget, changedFields: ["links"])

                // Force connection lines layer to re-fetch edges now that both
                // atoms have been processed and edges are committed to the DB.
                // handleAtomUpdated posts graphNodeUpdated after each call, but
                // the first notification may fire before the second atom's edges
                // are written — so we post one final notification after both complete.
                NotificationCenter.default.post(
                    name: CosmoNotification.NodeGraph.graphNodeUpdated,
                    object: nil,
                    userInfo: ["atomUUID": finalSource.uuid]
                )

                // Notify block content to refresh
                NotificationCenter.default.post(
                    name: CosmoNotification.Canvas.updateBlockContent,
                    object: nil,
                    userInfo: ["blockId": sourceBlock.id, "action": "linked"]
                )

                // If target is a Cosmo AI block, refresh its context
                if targetBlock.entityType == .cosmoAI {
                    NotificationCenter.default.post(
                        name: CosmoNotification.Canvas.updateBlockContent,
                        object: nil,
                        userInfo: ["blockId": targetBlock.id, "action": "refreshContext"]
                    )
                }

                // Brief celebration then reset
                try await Task.sleep(for: .milliseconds(500))
                await MainActor.run {
                    cancel()
                }
            } catch {
                print("DragToConnect: Failed to create link: \(error)")
                cancel()
            }
        }
    }

    /// Hit-test current drag point against block frames to find hover target
    func checkTarget(
        blocks: [CanvasBlock],
        canvasOffset: CGSize,
        scaledPanOffset: CGSize,
        effectiveScale: CGFloat,
        screenCenter: CGPoint
    ) {
        guard isActive, let source = sourceBlock else { return }

        let threshold: CGFloat = 30
        var closestId: String?
        var closestDistance: CGFloat = .infinity

        for block in blocks {
            guard block.id != source.id else { continue }

            // Calculate block screen position
            let blockX = block.position.x + canvasOffset.width + scaledPanOffset.width
            let blockY = block.position.y + canvasOffset.height + scaledPanOffset.height

            // Apply scale around screen center
            let scaledX = screenCenter.x + (blockX - screenCenter.x) * effectiveScale
            let scaledY = screenCenter.y + (blockY - screenCenter.y) * effectiveScale

            let blockCenter = CGPoint(x: scaledX, y: scaledY)
            let halfWidth = block.size.width * effectiveScale * block.scale / 2
            let halfHeight = block.size.height * effectiveScale * block.scale / 2

            // Expanded hit area
            let hitRect = CGRect(
                x: blockCenter.x - halfWidth - threshold,
                y: blockCenter.y - halfHeight - threshold,
                width: (halfWidth + threshold) * 2,
                height: (halfHeight + threshold) * 2
            )

            if hitRect.contains(currentDragPoint) {
                let distance = hypot(currentDragPoint.x - blockCenter.x, currentDragPoint.y - blockCenter.y)
                if distance < closestDistance {
                    closestDistance = distance
                    closestId = block.id
                }
            }
        }

        hoveredTargetBlockId = closestId
    }
}
