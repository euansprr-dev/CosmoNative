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
        preloadInset: CGFloat = 320,
        retainedBlockIds: Set<String> = []
    ) -> CanvasRenderSnapshot {
        // Hysteresis band: a block MOUNTS when it enters the preload (enter)
        // rect, but an already-mounted block only UNMOUNTS once it leaves the
        // larger exit rect. Without the band, every bucket crossing (and any
        // preload-inset change) churned the mounted set at the frontier —
        // each churned media card re-ran atom + media loads on remount.
        let enterVisibility = CanvasVisibilityIndex(transform: transform, preloadInset: preloadInset)
        let exitVisibility = CanvasVisibilityIndex(
            transform: transform,
            preloadInset: preloadInset * CanvasViewportSnapshotPolicy.retainInsetMultiplier
        )

        var visibleIDs = Set<String>()
        var renderable: [CanvasBlock] = []
        renderable.reserveCapacity(min(sortedBlocks.count, 128))
        let activeClusterBlockUUIDs = activeGestureBlockUUIDs(
            clusters: userClusters,
            draggingClusterId: draggingClusterId,
            resizingClusterId: resizingClusterId
        )

        for block in sortedBlocks {
            let entersNow = enterVisibility.isBlockVisible(block)
            let staysRetained = !entersNow
                && retainedBlockIds.contains(block.id)
                && exitVisibility.isBlockVisible(block)
            guard entersNow || staysRetained else { continue }
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

/// Deliberately NOT observable: `snapshot(...)` is called during body
/// evaluation and mutates its internal caches — tracked properties there
/// would register the calling body on its own cache writes. It's a pure
/// memo held via `@State` for lifetime only.
@MainActor
final class CanvasRenderPipeline {
    private var dataSignature: CanvasRenderDataSignature?
    private var dataRevisionSignature: CanvasRenderDataRevisionSignature?
    private var dataSnapshot: CanvasRenderDataSnapshot = .empty
    private var viewportSignature: CanvasRenderViewportSignature?
    private var viewportSnapshot: CanvasRenderSnapshot = .empty

    private(set) var lastRenderableBlocks: [CanvasBlock] = []
    /// Ids of the currently mounted block hosts — fed back into the next
    /// viewport rebuild as the hysteresis retained set.
    private var lastRenderableBlockIds: Set<String> = []
    private(set) var hasResolvedSnapshot = false
    private(set) var debugDataSnapshotBuildCount = 0
    private(set) var debugViewportSnapshotBuildCount = 0
    /// Debug telemetry for the perf HUD: how often the canvas body asked for a
    /// snapshot (≈ body evaluations) and how many block hosts each viewport
    /// rebuild mounted/unmounted. Plain counters — reading them is never
    /// observable-tracked, so the HUD can poll without invalidating anything.
    private(set) var debugSnapshotRequestCount = 0
    private(set) var debugTotalMounts = 0
    private(set) var debugTotalUnmounts = 0
    private(set) var debugLastSwapMounts = 0
    private(set) var debugLastSwapUnmounts = 0

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
        debugSnapshotRequestCount &+= 1
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
                preloadInset: preloadInset,
                retainedBlockIds: lastRenderableBlockIds
            )
            viewportSignature = nextViewportSignature
            recordMountChurn(from: lastRenderableBlocks, to: viewportSnapshot.renderableBlocks)
            lastRenderableBlocks = viewportSnapshot.renderableBlocks
            lastRenderableBlockIds = Set(viewportSnapshot.renderableBlocks.map(\.id))
            hasResolvedSnapshot = true
            debugViewportSnapshotBuildCount += 1
            CanvasPerformanceInstrumentation.signposter.endInterval("render-viewport-snapshot", signpost)
        }

        return viewportSnapshot
    }

    /// Track how many block hosts a viewport swap mounted/unmounted — the
    /// number the perf HUD watches to prove gesture start/end no longer
    /// churns the mounted set.
    private func recordMountChurn(from previous: [CanvasBlock], to next: [CanvasBlock]) {
        guard hasResolvedSnapshot else { return }
        let previousIds = Set(previous.map(\.id))
        let nextIds = Set(next.map(\.id))
        let mounts = nextIds.subtracting(previousIds).count
        let unmounts = previousIds.subtracting(nextIds).count
        debugLastSwapMounts = mounts
        debugLastSwapUnmounts = unmounts
        debugTotalMounts &+= mounts
        debugTotalUnmounts &+= unmounts
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
