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

struct CanvasRenderDataSnapshot {
    static let empty = CanvasRenderDataSnapshot(
        blocksById: [:],
        clusterConsumedBlockUUIDs: [],
        mediaContentBlockIds: [],
        sortedBlocks: [],
        userClusters: []
    )

    let blocksById: [String: CanvasBlock]
    let clusterConsumedBlockUUIDs: Set<String>
    let mediaContentBlockIds: Set<String>
    let sortedBlocks: [CanvasBlock]
    let userClusters: [CanvasCluster]

    static func build(
        blocks: [CanvasBlock],
        userClusters: [CanvasCluster]
    ) -> CanvasRenderDataSnapshot {
        CanvasRenderDataSnapshot(
            blocksById: Dictionary(blocks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            clusterConsumedBlockUUIDs: clusterConsumedBlockUUIDs(from: userClusters),
            mediaContentBlockIds: mediaContentBlockIds(from: blocks),
            sortedBlocks: blocks.sorted { lhs, rhs in
                if lhs.zIndex == rhs.zIndex { return lhs.id < rhs.id }
                return lhs.zIndex < rhs.zIndex
            },
            userClusters: userClusters
        )
    }

    func renderSnapshot(
        transform: CanvasViewportTransform,
        selectedBlockId: String?,
        selectedClusterId: UUID?,
        draggingClusterId: UUID?,
        resizingClusterId: UUID?,
        preloadInset: CGFloat = 320
    ) -> CanvasRenderSnapshot {
        let visibility = CanvasVisibilityIndex(transform: transform, preloadInset: preloadInset)

        var visibleIDs = Set<String>()
        var renderable: [CanvasBlock] = []
        renderable.reserveCapacity(min(sortedBlocks.count, 128))
        let activeClusterBlockUUIDs = activeGestureBlockUUIDs(
            clusters: userClusters,
            draggingClusterId: draggingClusterId,
            resizingClusterId: resizingClusterId
        )

        for block in sortedBlocks {
            guard visibility.isBlockVisible(block) else { continue }
            visibleIDs.insert(block.id)

            let isClusterGestureMember = activeClusterBlockUUIDs.contains(block.entityUuid)
            guard !clusterConsumedBlockUUIDs.contains(block.entityUuid) || isClusterGestureMember else { continue }
            renderable.append(block)
        }

        return CanvasRenderSnapshot(
            blocksById: blocksById,
            visibleBlockIds: visibleIDs,
            clusterConsumedBlockUUIDs: clusterConsumedBlockUUIDs,
            mediaContentBlockIds: mediaContentBlockIds,
            renderableBlocks: renderable,
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

    private func activeGestureBlockUUIDs(
        clusters: [CanvasCluster],
        draggingClusterId: UUID?,
        resizingClusterId: UUID?
    ) -> Set<String> {
        guard let activeClusterId = draggingClusterId ?? resizingClusterId,
              let cluster = clusters.first(where: { $0.id == activeClusterId }) else {
            return []
        }
        guard cluster.viewMode == .canvas else { return [] }
        return Set(cluster.blockUUIDs)
    }
}

private struct CanvasRenderDataSignature: Equatable {
    let blockKeys: [BlockKey]
    let clusterKeys: [ClusterKey]

    init(blocks: [CanvasBlock], userClusters: [CanvasCluster]) {
        self.blockKeys = blocks.map(BlockKey.init)
        self.clusterKeys = userClusters.map(ClusterKey.init)
    }

    struct BlockKey: Equatable {
        let id: String
        let position: CGPoint
        let size: CGSize
        let scale: Double
        let rotation: Double
        let isPinned: Bool
        let zIndex: Int
        let entityType: EntityType
        let entityId: Int64
        let entityUuid: String
        let isSelected: Bool
        let opacity: Double
        let title: String
        let subtitle: String?
        let metadata: [String: String]

        init(block: CanvasBlock) {
            self.id = block.id
            self.position = block.position
            self.size = block.size
            self.scale = block.scale
            self.rotation = block.rotation
            self.isPinned = block.isPinned
            self.zIndex = block.zIndex
            self.entityType = block.entityType
            self.entityId = block.entityId
            self.entityUuid = block.entityUuid
            self.isSelected = block.isSelected
            self.opacity = block.opacity
            self.title = block.title
            self.subtitle = block.subtitle
            self.metadata = block.metadata
        }
    }

    struct ClusterKey: Equatable {
        let id: UUID
        let blockUUIDs: [String]
        let viewMode: ClusterViewMode

        init(cluster: CanvasCluster) {
            self.id = cluster.id
            self.blockUUIDs = cluster.blockUUIDs
            self.viewMode = cluster.viewMode
        }
    }
}

private struct CanvasRenderDataRevisionSignature: Equatable {
    let blockDataRevision: Int
    let clusterDataRevision: Int
}

private struct CanvasRenderViewportSignature: Equatable {
    let transform: CanvasViewportTransform
    let preloadInset: CGFloat
    let selectedBlockId: String?
    let selectedClusterId: UUID?
    let draggingClusterId: UUID?
    let resizingClusterId: UUID?
}

@MainActor
final class CanvasRenderPipeline: ObservableObject {
    private var dataSignature: CanvasRenderDataSignature?
    private var dataRevisionSignature: CanvasRenderDataRevisionSignature?
    private var dataSnapshot: CanvasRenderDataSnapshot = .empty
    private var viewportSignature: CanvasRenderViewportSignature?
    private var viewportSnapshot: CanvasRenderSnapshot = .empty

    private(set) var lastRenderableBlocks: [CanvasBlock] = []
    private(set) var hasResolvedSnapshot = false
    private(set) var debugDataSnapshotBuildCount = 0
    private(set) var debugViewportSnapshotBuildCount = 0

    func snapshot(
        blocks: [CanvasBlock],
        blockDataRevision: Int? = nil,
        transform: CanvasViewportTransform,
        preloadInset: CGFloat = 320,
        userClusters: [CanvasCluster],
        clusterDataRevision: Int? = nil,
        selectedBlockId: String?,
        selectedClusterId: UUID?,
        draggingClusterId: UUID?,
        resizingClusterId: UUID?
    ) -> CanvasRenderSnapshot {
        let shouldRebuildData: Bool
        if let blockDataRevision, let clusterDataRevision {
            let nextRevisionSignature = CanvasRenderDataRevisionSignature(
                blockDataRevision: blockDataRevision,
                clusterDataRevision: clusterDataRevision
            )
            shouldRebuildData = dataRevisionSignature != nextRevisionSignature
            if shouldRebuildData {
                dataRevisionSignature = nextRevisionSignature
                dataSignature = nil
            }
        } else {
            let nextDataSignature = CanvasRenderDataSignature(blocks: blocks, userClusters: userClusters)
            shouldRebuildData = dataSignature != nextDataSignature
            if shouldRebuildData {
                dataSignature = nextDataSignature
                dataRevisionSignature = nil
            }
        }

        if shouldRebuildData {
            let signpost = CanvasPerformanceInstrumentation.signposter.beginInterval("render-data-snapshot")
            dataSnapshot = CanvasRenderDataSnapshot.build(blocks: blocks, userClusters: userClusters)
            viewportSignature = nil
            debugDataSnapshotBuildCount += 1
            CanvasPerformanceInstrumentation.signposter.endInterval("render-data-snapshot", signpost)
        }

        let nextViewportSignature = CanvasRenderViewportSignature(
            transform: transform,
            preloadInset: preloadInset,
            selectedBlockId: selectedBlockId,
            selectedClusterId: selectedClusterId,
            draggingClusterId: draggingClusterId,
            resizingClusterId: resizingClusterId
        )
        if viewportSignature != nextViewportSignature {
            let signpost = CanvasPerformanceInstrumentation.signposter.beginInterval("render-viewport-snapshot")
            viewportSnapshot = dataSnapshot.renderSnapshot(
                transform: transform,
                selectedBlockId: selectedBlockId,
                selectedClusterId: selectedClusterId,
                draggingClusterId: draggingClusterId,
                resizingClusterId: resizingClusterId,
                preloadInset: preloadInset
            )
            viewportSignature = nextViewportSignature
            lastRenderableBlocks = viewportSnapshot.renderableBlocks
            hasResolvedSnapshot = true
            debugViewportSnapshotBuildCount += 1
            CanvasPerformanceInstrumentation.signposter.endInterval("render-viewport-snapshot", signpost)
        }

        return viewportSnapshot
    }
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
        CanvasRenderDataSnapshot
            .build(blocks: blocks, userClusters: userClusters)
            .renderSnapshot(
                transform: transform,
                selectedBlockId: selectedBlockId,
                selectedClusterId: selectedClusterId,
                draggingClusterId: draggingClusterId,
                resizingClusterId: resizingClusterId,
                preloadInset: preloadInset
            )
    }
}

@MainActor
final class ThinkspaceCanvasSnapshotCache {
    static let shared = ThinkspaceCanvasSnapshotCache()

    struct Entry {
        let thinkspaceId: String?
        let blocks: [CanvasBlock]
        let userClusters: [CanvasCluster]
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

    func store(
        blocks: [CanvasBlock],
        zoomLevel: CGFloat,
        panOffset: CGSize,
        thinkspaceId: String?,
        userClusters: [CanvasCluster] = []
    ) {
        let entry = Entry(
            thinkspaceId: thinkspaceId,
            blocks: blocks,
            userClusters: userClusters,
            zoomLevel: zoomLevel,
            panOffset: panOffset,
            mediaContentBlockIds: CanvasRenderDataSnapshot.build(
                blocks: blocks,
                userClusters: userClusters
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
