import Foundation
import SwiftUI
import GRDB

@MainActor
final class SpatialPlacementPlanner {
    static let shared = SpatialPlacementPlanner()

    private let database = CosmoDatabase.shared
    private let atomRepository = AtomRepository.shared

    private let clusterSpacing: CGFloat = 56
    private let blockSpacing: CGFloat = 28
    private let defaultCanvasBounds = CGRect(x: 80, y: 80, width: 1_800, height: 1_240)

    private init() {}

    struct Snapshot {
        let thinkspaceId: String
        let thinkspaceName: String
        let blocks: [CanvasBlockRecord]
        let clusters: [CodableCluster]
        let canvasBounds: CGRect
    }

    func loadSnapshot(thinkspaceId: String, thinkspaceName: String? = nil) async -> Snapshot? {
        do {
            guard let thinkspaceAtom = try await atomRepository.fetch(uuid: thinkspaceId) else {
                return nil
            }

            let metadata = thinkspaceAtom.metadataValue(as: ThinkspaceMetadata.self) ?? ThinkspaceMetadata()
            let blocks = try await database.asyncRead { db in
                try CanvasBlockRecord
                    .filter(Column("thinkspace_id") == thinkspaceId)
                    .filter(Column("is_deleted") == false)
                    .fetchAll(db)
            }

            let clusterRects = metadata.clusters.compactMap(persistedRect(for:))
            let blockRects = blocks.map(blockRect(for:))
            let bounds = derivedCanvasBounds(blockRects: blockRects, clusterRects: clusterRects)

            return Snapshot(
                thinkspaceId: thinkspaceId,
                thinkspaceName: thinkspaceName ?? metadata.name,
                blocks: blocks,
                clusters: metadata.clusters,
                canvasBounds: bounds
            )
        } catch {
            print("⚠️ [SpatialPlacementPlanner] Snapshot load failed: \(error)")
            return nil
        }
    }

    func planForExistingCluster(
        title: String,
        atomType: AtomType,
        thinkspaceId: String,
        thinkspaceName: String,
        cluster: CodableCluster,
        relatedAtomUUIDs: [String]
    ) async -> InboxPlacementPlan? {
        guard let snapshot = await loadSnapshot(thinkspaceId: thinkspaceId, thinkspaceName: thinkspaceName),
              let clusterRect = persistedRect(for: cluster) else {
            return nil
        }

        let viewMode = clusterViewMode(for: cluster)
        let blockSize = defaultBlockSize(for: atomType)

        if viewMode == .canvas {
            let memberUUIDs = Set(cluster.blockUUIDs)
            let memberBlockRects = snapshot.blocks
                .filter { memberUUIDs.contains($0.entityUuid ?? "") }
                .map(blockRect(for:))

            let anchor = relatedAnchor(
                relatedAtomUUIDs: relatedAtomUUIDs,
                blocks: snapshot.blocks,
                fallback: CGPoint(x: clusterRect.midX, y: clusterRect.midY)
            )

            if let position = findCanvasPosition(
                for: blockSize,
                in: clusterRect,
                occupiedRects: memberBlockRects,
                anchor: anchor
            ) {
                return InboxPlacementPlan(
                    targetThinkspaceId: thinkspaceId,
                    targetThinkspaceName: thinkspaceName,
                    targetClusterId: cluster.id,
                    targetClusterName: cluster.name,
                    clusterViewMode: viewMode.rawValue,
                    blockPositionX: position.x,
                    blockPositionY: position.y,
                    clusterRect: inboxRect(from: clusterRect),
                    operations: [
                        InboxPlacementOperation(kind: .createAtom, description: "Create a new \(atomType.displayName.lowercased())"),
                        InboxPlacementOperation(kind: .placeBlock, description: "Place the block inside \(cluster.name)")
                    ],
                    summary: "Place \(title) inside \(thinkspaceName) › \(cluster.name)"
                )
            }

            let expandedRect = CGRect(
                x: clusterRect.minX,
                y: clusterRect.minY,
                width: max(clusterRect.width, blockSize.width + 96),
                height: clusterRect.height + blockSize.height + 96
            )
            let resizedPosition = CGPoint(
                x: expandedRect.midX,
                y: expandedRect.maxY - (CanvasCluster.titleTopPadding + blockSize.height / 2 + 20)
            )

            return InboxPlacementPlan(
                targetThinkspaceId: thinkspaceId,
                targetThinkspaceName: thinkspaceName,
                targetClusterId: cluster.id,
                targetClusterName: cluster.name,
                clusterViewMode: viewMode.rawValue,
                blockPositionX: resizedPosition.x,
                blockPositionY: resizedPosition.y,
                clusterRect: inboxRect(from: expandedRect),
                operations: [
                    InboxPlacementOperation(kind: .resizeCluster, description: "Expand \(cluster.name) to make room"),
                    InboxPlacementOperation(kind: .createAtom, description: "Create a new \(atomType.displayName.lowercased())"),
                    InboxPlacementOperation(kind: .placeBlock, description: "Place the block inside \(cluster.name)")
                ],
                summary: "Resize \(cluster.name) and place \(title) inside it"
            )
        }

        let fallbackPosition = CGPoint(x: clusterRect.midX, y: clusterRect.midY)
        return InboxPlacementPlan(
            targetThinkspaceId: thinkspaceId,
            targetThinkspaceName: thinkspaceName,
            targetClusterId: cluster.id,
            targetClusterName: cluster.name,
            clusterViewMode: viewMode.rawValue,
            blockPositionX: fallbackPosition.x,
            blockPositionY: fallbackPosition.y,
            clusterRect: inboxRect(from: clusterRect),
            operations: [
                InboxPlacementOperation(kind: .createAtom, description: "Create a new \(atomType.displayName.lowercased())"),
                InboxPlacementOperation(kind: .placeBlock, description: "Add it to the \(cluster.name) \(viewMode.rawValue) cluster")
            ],
            summary: "Add \(title) to \(thinkspaceName) › \(cluster.name)"
        )
    }

    func planForThinkspacePlacement(
        title: String,
        atomType: AtomType,
        thinkspaceId: String,
        thinkspaceName: String,
        relatedAtomUUIDs: [String]
    ) async -> InboxPlacementPlan? {
        guard let snapshot = await loadSnapshot(thinkspaceId: thinkspaceId, thinkspaceName: thinkspaceName) else {
            return nil
        }

        let blockSize = defaultBlockSize(for: atomType)
        let occupiedRects = snapshot.blocks.map(blockRect(for:))
        let anchor = relatedAnchor(
            relatedAtomUUIDs: relatedAtomUUIDs,
            blocks: snapshot.blocks,
            fallback: CGPoint(x: snapshot.canvasBounds.midX, y: snapshot.canvasBounds.midY)
        )
        let position = findLooseCanvasPosition(
            for: blockSize,
            occupiedRects: occupiedRects,
            bounds: snapshot.canvasBounds,
            anchor: anchor
        )

        return InboxPlacementPlan(
            targetThinkspaceId: thinkspaceId,
            targetThinkspaceName: thinkspaceName,
            targetClusterId: nil,
            targetClusterName: nil,
            clusterViewMode: nil,
            blockPositionX: position.x,
            blockPositionY: position.y,
            clusterRect: nil,
            operations: [
                InboxPlacementOperation(kind: .createAtom, description: "Create a new \(atomType.displayName.lowercased())"),
                InboxPlacementOperation(kind: .placeBlock, description: "Place it on the \(thinkspaceName) canvas")
            ],
            summary: "Place \(title) on \(thinkspaceName)"
        )
    }

    func planForNewCluster(
        title: String,
        atomType: AtomType,
        thinkspaceId: String,
        thinkspaceName: String,
        clusterName: String,
        relatedAtomUUIDs: [String]
    ) async -> InboxPlacementPlan? {
        guard let snapshot = await loadSnapshot(thinkspaceId: thinkspaceId, thinkspaceName: thinkspaceName) else {
            return nil
        }

        let clusterSize = CGSize(width: 560, height: 380)
        let occupiedRects = snapshot.blocks.map(blockRect(for:)) + snapshot.clusters.compactMap(persistedRect(for:))
        let anchor = relatedAnchor(
            relatedAtomUUIDs: relatedAtomUUIDs,
            blocks: snapshot.blocks,
            fallback: CGPoint(x: snapshot.canvasBounds.midX, y: snapshot.canvasBounds.midY)
        )
        let clusterRect = findClusterRect(
            size: clusterSize,
            occupiedRects: occupiedRects,
            bounds: snapshot.canvasBounds,
            preferredCenter: anchor
        )
        let blockSize = defaultBlockSize(for: atomType)
        let blockPosition = CGPoint(
            x: clusterRect.midX,
            y: clusterRect.minY + CanvasCluster.titleTopPadding + 28 + (blockSize.height / 2)
        )

        return InboxPlacementPlan(
            targetThinkspaceId: thinkspaceId,
            targetThinkspaceName: thinkspaceName,
            targetClusterId: UUID().uuidString,
            targetClusterName: clusterName,
            clusterViewMode: ClusterViewMode.canvas.rawValue,
            blockPositionX: blockPosition.x,
            blockPositionY: blockPosition.y,
            clusterRect: inboxRect(from: clusterRect),
            operations: [
                InboxPlacementOperation(kind: .createCluster, description: "Create the \(clusterName) cluster in \(thinkspaceName)"),
                InboxPlacementOperation(kind: .createAtom, description: "Create a new \(atomType.displayName.lowercased())"),
                InboxPlacementOperation(kind: .placeBlock, description: "Place the block inside \(clusterName)")
            ],
            summary: "Create \(thinkspaceName) › \(clusterName) and place \(title)"
        )
    }

    func planForNewThinkspace(
        title: String,
        atomType: AtomType,
        thinkspaceName: String,
        starterClusterName: String = "Overview"
    ) -> InboxPlacementPlan {
        let clusterRect = CGRect(x: 160, y: 140, width: 620, height: 420)
        let blockSize = defaultBlockSize(for: atomType)
        let blockPosition = CGPoint(
            x: clusterRect.midX,
            y: clusterRect.minY + CanvasCluster.titleTopPadding + 28 + (blockSize.height / 2)
        )

        return InboxPlacementPlan(
            targetThinkspaceId: nil,
            targetThinkspaceName: thinkspaceName,
            targetClusterId: UUID().uuidString,
            targetClusterName: starterClusterName,
            clusterViewMode: ClusterViewMode.canvas.rawValue,
            blockPositionX: blockPosition.x,
            blockPositionY: blockPosition.y,
            clusterRect: inboxRect(from: clusterRect),
            operations: [
                InboxPlacementOperation(kind: .createThinkspace, description: "Create the \(thinkspaceName) thinkspace"),
                InboxPlacementOperation(kind: .createCluster, description: "Seed it with an \(starterClusterName) cluster"),
                InboxPlacementOperation(kind: .createAtom, description: "Create a new \(atomType.displayName.lowercased())"),
                InboxPlacementOperation(kind: .placeBlock, description: "Place the block into \(starterClusterName)")
            ],
            summary: "Create \(thinkspaceName) with a starter cluster for \(title)"
        )
    }

    private func defaultBlockSize(for atomType: AtomType) -> CGSize {
        switch atomType {
        case .task:
            return CGSize(width: 280, height: 120)
        case .project:
            return CGSize(width: 320, height: 240)
        case .research:
            return CGSize(width: 320, height: 340)
        case .idea:
            return CGSize(width: 280, height: 180)
        case .image:
            return CGSize(width: 320, height: 240)
        default:
            return CGSize(width: 220, height: 310)
        }
    }

    private func derivedCanvasBounds(blockRects: [CGRect], clusterRects: [CGRect]) -> CGRect {
        let allRects = blockRects + clusterRects
        guard var union = allRects.first else {
            return defaultCanvasBounds
        }

        for rect in allRects.dropFirst() {
            union = union.union(rect)
        }

        return union.insetBy(dx: -360, dy: -280)
    }

    private func persistedRect(for cluster: CodableCluster) -> CGRect? {
        guard let originX = cluster.originX,
              let originY = cluster.originY,
              let width = cluster.rectWidth,
              let height = cluster.rectHeight,
              width > 0,
              height > 0 else {
            return nil
        }

        return CGRect(x: originX, y: originY, width: width, height: height)
    }

    private func clusterViewMode(for cluster: CodableCluster) -> ClusterViewMode {
        guard let raw = cluster.viewMode,
              let mode = ClusterViewMode(rawValue: raw) else {
            return .canvas
        }
        return mode
    }

    private func blockRect(for block: CanvasBlockRecord) -> CGRect {
        let width = CGFloat(block.width ?? 220)
        let height = CGFloat(block.height ?? 310)
        return CGRect(
            x: CGFloat(block.positionX) - (width / 2),
            y: CGFloat(block.positionY) - (height / 2),
            width: width,
            height: height
        )
    }

    private func relatedAnchor(
        relatedAtomUUIDs: [String],
        blocks: [CanvasBlockRecord],
        fallback: CGPoint
    ) -> CGPoint {
        let related = blocks.filter { relatedAtomUUIDs.contains($0.entityUuid ?? "") }
        guard !related.isEmpty else { return fallback }

        let x = related.reduce(CGFloat.zero) { $0 + CGFloat($1.positionX) } / CGFloat(related.count)
        let y = related.reduce(CGFloat.zero) { $0 + CGFloat($1.positionY) } / CGFloat(related.count)
        return CGPoint(x: x, y: y)
    }

    private func findCanvasPosition(
        for blockSize: CGSize,
        in clusterRect: CGRect,
        occupiedRects: [CGRect],
        anchor: CGPoint
    ) -> CGPoint? {
        let usableInset: CGFloat = 24
        let topInset = CanvasCluster.titleTopPadding + 18
        let usableRect = CGRect(
            x: clusterRect.minX + usableInset,
            y: clusterRect.minY + topInset,
            width: clusterRect.width - (usableInset * 2),
            height: max(0, clusterRect.height - topInset - usableInset)
        )

        guard usableRect.width >= blockSize.width, usableRect.height >= blockSize.height else {
            return nil
        }

        let positions = gridCenters(
            within: usableRect,
            itemSize: blockSize,
            stepX: blockSize.width + blockSpacing,
            stepY: blockSize.height + blockSpacing
        ).sorted { lhs, rhs in
            distanceSquared(lhs, anchor) < distanceSquared(rhs, anchor)
        }

        for position in positions {
            let rect = rect(center: position, size: blockSize).insetBy(dx: -12, dy: -12)
            if !occupiedRects.contains(where: { $0.intersects(rect) }) {
                return position
            }
        }

        return nil
    }

    private func findLooseCanvasPosition(
        for blockSize: CGSize,
        occupiedRects: [CGRect],
        bounds: CGRect,
        anchor: CGPoint
    ) -> CGPoint {
        let positions = gridCenters(
            within: bounds,
            itemSize: blockSize,
            stepX: blockSize.width + blockSpacing,
            stepY: blockSize.height + blockSpacing
        ).sorted { lhs, rhs in
            distanceSquared(lhs, anchor) < distanceSquared(rhs, anchor)
        }

        for position in positions {
            let rect = rect(center: position, size: blockSize).insetBy(dx: -12, dy: -12)
            if !occupiedRects.contains(where: { $0.intersects(rect) }) {
                return position
            }
        }

        return anchor
    }

    private func findClusterRect(
        size: CGSize,
        occupiedRects: [CGRect],
        bounds: CGRect,
        preferredCenter: CGPoint
    ) -> CGRect {
        let candidateCenters = spiralCenters(around: preferredCenter, in: bounds, size: size)
        var bestRect = CGRect(
            x: preferredCenter.x - (size.width / 2),
            y: preferredCenter.y - (size.height / 2),
            width: size.width,
            height: size.height
        )
        var bestPenalty = Double.greatestFiniteMagnitude

        for center in candidateCenters {
            let rect = clampRectToBounds(
                CGRect(
                    x: center.x - (size.width / 2),
                    y: center.y - (size.height / 2),
                    width: size.width,
                    height: size.height
                ),
                bounds: bounds
            )
            let penalty = occupancyPenalty(for: rect, occupiedRects: occupiedRects)
            if penalty < bestPenalty {
                bestPenalty = penalty
                bestRect = rect
            }
            if penalty < 0.01 {
                break
            }
        }

        return bestRect
    }

    private func spiralCenters(around center: CGPoint, in bounds: CGRect, size: CGSize) -> [CGPoint] {
        var centers: [CGPoint] = [center]
        let radiusStep: CGFloat = 180

        for ring in 1...18 {
            let radius = CGFloat(ring) * radiusStep
            let samples = max(8, ring * 6)
            for sample in 0..<samples {
                let angle = (Double(sample) / Double(samples)) * Double.pi * 2
                let candidate = CGPoint(
                    x: center.x + (CGFloat(cos(angle)) * radius),
                    y: center.y + (CGFloat(sin(angle)) * radius)
                )
                let candidateRect = CGRect(
                    x: candidate.x - (size.width / 2),
                    y: candidate.y - (size.height / 2),
                    width: size.width,
                    height: size.height
                )
                let clamped = clampRectToBounds(candidateRect, bounds: bounds)
                centers.append(CGPoint(x: clamped.midX, y: clamped.midY))
            }
        }

        return centers
    }

    private func gridCenters(within bounds: CGRect, itemSize: CGSize, stepX: CGFloat, stepY: CGFloat) -> [CGPoint] {
        guard bounds.width >= itemSize.width, bounds.height >= itemSize.height else { return [] }

        let minX = bounds.minX + (itemSize.width / 2)
        let maxX = bounds.maxX - (itemSize.width / 2)
        let minY = bounds.minY + (itemSize.height / 2)
        let maxY = bounds.maxY - (itemSize.height / 2)

        var centers: [CGPoint] = []
        var y = minY
        while y <= maxY {
            var x = minX
            while x <= maxX {
                centers.append(CGPoint(x: x, y: y))
                x += max(stepX, 40)
            }
            y += max(stepY, 40)
        }
        return centers
    }

    private func occupancyPenalty(for rect: CGRect, occupiedRects: [CGRect]) -> Double {
        let area = max(rect.width * rect.height, 1)
        let overlap = occupiedRects.reduce(CGFloat.zero) { partial, occupied in
            partial + rect.intersection(occupied).area
        }
        return Double(overlap / area)
    }

    private func clampRectToBounds(_ rect: CGRect, bounds: CGRect) -> CGRect {
        var clamped = rect
        clamped.origin.x = min(max(clamped.origin.x, bounds.minX), bounds.maxX - clamped.width)
        clamped.origin.y = min(max(clamped.origin.y, bounds.minY), bounds.maxY - clamped.height)
        return clamped
    }

    private func rect(center: CGPoint, size: CGSize) -> CGRect {
        CGRect(
            x: center.x - (size.width / 2),
            y: center.y - (size.height / 2),
            width: size.width,
            height: size.height
        )
    }

    private func distanceSquared(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return (dx * dx) + (dy * dy)
    }

    private func inboxRect(from rect: CGRect) -> InboxPlacementRect {
        InboxPlacementRect(
            originX: rect.origin.x,
            originY: rect.origin.y,
            width: rect.width,
            height: rect.height
        )
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}
