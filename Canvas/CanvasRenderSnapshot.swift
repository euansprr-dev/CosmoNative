import SwiftUI

struct CanvasPerformanceBudget: Equatable {
    static let promotionFrameBudgetMs = 8.33
    static let standardFrameBudgetMs = 16.67
    static let commandKKeystrokeBudgetMs = 16.0
    static let commandKWarmResultsBudgetMs = 50.0
}

struct CanvasRenderSnapshot: Equatable {
    static let empty = CanvasRenderSnapshot(
        blocksById: [:],
        visibleBlockIds: [],
        clusterConsumedBlockUUIDs: [],
        mediaContentBlockIds: [],
        renderableBlocks: [],
        selectedBlockId: nil,
        selectedClusterId: nil
    )

    let blocksById: [String: CanvasBlock]
    let visibleBlockIds: Set<String>
    let clusterConsumedBlockUUIDs: Set<String>
    let mediaContentBlockIds: Set<String>
    let renderableBlocks: [CanvasBlock]
    let selectedBlockId: String?
    let selectedClusterId: UUID?

    var visibleBlockCount: Int { visibleBlockIds.count }
}

struct CanvasSceneColorSignal: Equatable {
    let id: String
    let color: Color
    let rect: CGRect
    let isNearSidebar: Bool

    static func == (lhs: CanvasSceneColorSignal, rhs: CanvasSceneColorSignal) -> Bool {
        lhs.id == rhs.id
            && lhs.rect == rhs.rect
            && lhs.isNearSidebar == rhs.isNearSidebar
    }
}

enum CanvasSceneSignalBuilder {
    private static let viewportInset: CGFloat = 120
    private static let nearSidebarLimit: CGFloat = 740

    static func clusterSignals(
        clusters: [CanvasCluster],
        transform: CanvasViewportTransform,
        viewportSize: CGSize,
        draggingClusterId: UUID?,
        clusterDragTranslation: CGSize
    ) -> [CanvasSceneColorSignal] {
        let viewport = CGRect(origin: .zero, size: viewportSize).insetBy(dx: -viewportInset, dy: -viewportInset)

        return clusters.compactMap { cluster in
            let canvasRect: CGRect
            if draggingClusterId == cluster.id {
                canvasRect = cluster.boundingRect.offsetBy(
                    dx: clusterDragTranslation.width,
                    dy: clusterDragTranslation.height
                )
            } else {
                canvasRect = cluster.boundingRect
            }

            let rect = transform.canvasRectToScreen(canvasRect)
            guard rect.width > 1, rect.height > 1, rect.intersects(viewport) else { return nil }
            return CanvasSceneColorSignal(
                id: "\(cluster.id)",
                color: cluster.color,
                rect: rect,
                isNearSidebar: rect.minX <= nearSidebarLimit
            )
        }
    }

    static func blockSignals(
        blocks: [CanvasBlock],
        transform: CanvasViewportTransform,
        viewportSize: CGSize,
        activeBlockDrag: ActiveCanvasDragState<String>,
        draggingClusterId: UUID?,
        draggingClusterMemberUUIDs: Set<String>,
        clusterDragTranslation: CGSize,
        consumedBlockUUIDs: Set<String>
    ) -> [CanvasSceneColorSignal] {
        let viewport = CGRect(origin: .zero, size: viewportSize).insetBy(dx: -viewportInset, dy: -viewportInset)

        return blocks.compactMap { block in
            let isDraggedClusterMember = draggingClusterId != nil && draggingClusterMemberUUIDs.contains(block.entityUuid)
            guard !consumedBlockUUIDs.contains(block.entityUuid) || isDraggedClusterMember else { return nil }

            let position = livePosition(
                for: block,
                activeBlockDrag: activeBlockDrag,
                isDraggedClusterMember: isDraggedClusterMember,
                clusterDragTranslation: clusterDragTranslation
            )
            let rect = screenRect(for: block, position: position, transform: transform)
            guard rect.intersects(viewport) else { return nil }
            return CanvasSceneColorSignal(
                id: block.id,
                color: block.entityType.color,
                rect: rect,
                isNearSidebar: rect.minX <= nearSidebarLimit
            )
        }
    }

    private static func livePosition(
        for block: CanvasBlock,
        activeBlockDrag: ActiveCanvasDragState<String>,
        isDraggedClusterMember: Bool,
        clusterDragTranslation: CGSize
    ) -> CGPoint {
        if activeBlockDrag.activeId == block.id {
            return CGPoint(
                x: block.position.x + activeBlockDrag.translation.width,
                y: block.position.y + activeBlockDrag.translation.height
            )
        }

        if isDraggedClusterMember {
            return CGPoint(
                x: block.position.x + clusterDragTranslation.width,
                y: block.position.y + clusterDragTranslation.height
            )
        }

        return block.position
    }

    private static func screenRect(
        for block: CanvasBlock,
        position: CGPoint,
        transform: CanvasViewportTransform
    ) -> CGRect {
        let center = transform.canvasToScreen(position)
        let scale = transform.effectiveScale
        let size = CGSize(
            width: block.size.width * scale,
            height: block.size.height * scale
        )
        return CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

enum CanvasRenderSnapshotBuilder {
    static func build(
        blocks: [CanvasBlock],
        transform: CanvasViewportTransform,
        userClusters: [CanvasCluster],
        selectedBlockId: String?,
        selectedClusterId: UUID?,
        draggingClusterId: UUID?,
        resizingClusterId: UUID?,
        preloadInset: CGFloat = 320
    ) -> CanvasRenderSnapshot {
        let visibility = CanvasVisibilityIndex(transform: transform, preloadInset: preloadInset)
        let blocksById = Dictionary(blocks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let consumedUUIDs = clusterConsumedBlockUUIDs(from: userClusters)
        let mediaIDs = mediaContentBlockIds(from: blocks)

        var visibleIDs = Set<String>()
        var renderable: [CanvasBlock] = []
        renderable.reserveCapacity(min(blocks.count, 128))

        for block in blocks {
            guard visibility.isBlockVisible(block) else { continue }
            visibleIDs.insert(block.id)

            let isClusterGestureMember = clusterGestureConsumes(
                block: block,
                clusters: userClusters,
                draggingClusterId: draggingClusterId,
                resizingClusterId: resizingClusterId
            )
            guard !consumedUUIDs.contains(block.entityUuid) || isClusterGestureMember else { continue }
            renderable.append(block)
        }

        return CanvasRenderSnapshot(
            blocksById: blocksById,
            visibleBlockIds: visibleIDs,
            clusterConsumedBlockUUIDs: consumedUUIDs,
            mediaContentBlockIds: mediaIDs,
            renderableBlocks: renderable.sorted { lhs, rhs in
                if lhs.zIndex == rhs.zIndex { return lhs.id < rhs.id }
                return lhs.zIndex < rhs.zIndex
            },
            selectedBlockId: selectedBlockId,
            selectedClusterId: selectedClusterId
        )
    }

    private static func clusterConsumedBlockUUIDs(from clusters: [CanvasCluster]) -> Set<String> {
        var consumed = Set<String>()
        for cluster in clusters where cluster.viewMode != .canvas {
            consumed.formUnion(cluster.blockUUIDs)
        }
        return consumed
    }

    private static func clusterGestureConsumes(
        block: CanvasBlock,
        clusters: [CanvasCluster],
        draggingClusterId: UUID?,
        resizingClusterId: UUID?
    ) -> Bool {
        guard let activeClusterId = draggingClusterId ?? resizingClusterId,
              let cluster = clusters.first(where: { $0.id == activeClusterId }) else {
            return false
        }
        guard cluster.viewMode == .canvas else { return false }
        return cluster.blockUUIDs.contains(block.entityUuid)
    }

    private static func mediaContentBlockIds(from blocks: [CanvasBlock]) -> Set<String> {
        var ids = Set<String>()
        for block in blocks where block.entityType == .research {
            let url = (block.metadata["url"] ?? "").lowercased()
            if url.contains("youtube") ||
                url.contains("youtu.be") ||
                url.contains("instagram") ||
                url.contains("tiktok") ||
                block.metadata["isSwipeFile"] == "true" {
                ids.insert(block.id)
            }
        }
        return ids
    }
}

@MainActor
final class ThinkspaceCanvasSnapshotCache {
    static let shared = ThinkspaceCanvasSnapshotCache()

    struct Entry {
        let thinkspaceId: String?
        let blocks: [CanvasBlock]
        let zoomLevel: CGFloat
        let panOffset: CGSize
        let mediaContentBlockIds: Set<String>
        let storedAt: Date
    }

    private var entries: [String: Entry] = [:]
    private let limit = 8

    private init() {}

    func entry(for thinkspaceId: String?) -> Entry? {
        entries[key(for: thinkspaceId)]
    }

    func store(blocks: [CanvasBlock], zoomLevel: CGFloat, panOffset: CGSize, thinkspaceId: String?) {
        let entry = Entry(
            thinkspaceId: thinkspaceId,
            blocks: blocks,
            zoomLevel: zoomLevel,
            panOffset: panOffset,
            mediaContentBlockIds: CanvasRenderSnapshotBuilder.build(
                blocks: blocks,
                transform: CanvasViewportTransform(viewportSize: CGSize(width: 1, height: 1), committedOffset: .zero),
                userClusters: [],
                selectedBlockId: nil,
                selectedClusterId: nil,
                draggingClusterId: nil,
                resizingClusterId: nil
            ).mediaContentBlockIds,
            storedAt: Date()
        )
        entries[key(for: thinkspaceId)] = entry
        trimIfNeeded()
    }

    func invalidate(thinkspaceId: String?) {
        entries.removeValue(forKey: key(for: thinkspaceId))
    }

    private func trimIfNeeded() {
        guard entries.count > limit else { return }
        let keysToRemove = entries
            .sorted { $0.value.storedAt < $1.value.storedAt }
            .prefix(entries.count - limit)
            .map(\.key)
        for key in keysToRemove {
            entries.removeValue(forKey: key)
        }
    }

    private func key(for thinkspaceId: String?) -> String {
        thinkspaceId ?? "__default__"
    }
}
