// CosmoOS/AI/CanvasClusterEngine.swift
// Auto-chunking cluster engine — discovers spatial clusters from graph edges + title similarity
// Also manages user-created clusters with AI synthesis

import SwiftUI
import NaturalLanguage

struct CanvasClusterDropResolution: Equatable {
    let clusterId: UUID
    let previewPosition: CGPoint
}

@MainActor
class CanvasClusterEngine: ObservableObject {

    // MARK: - Published State

    /// Auto-detected clusters (algorithmic)
    @Published var clusters: [CanvasCluster] = []

    /// User-created clusters (persistent, loaded from ThinkspaceMetadata)
    @Published var userClusters: [CanvasCluster] = [] {
        didSet { userClustersDataRevision &+= 1 }
    }
    private(set) var userClustersDataRevision = 0

    /// Combined clusters for rendering (user clusters take priority)
    var allClusters: [CanvasCluster] {
        userClusters + clusters
    }

    /// Currently selected cluster (for drag/selection)
    @Published var selectedClusterId: UUID?

    @AppStorage("canvasAutoClusters") var isEnabled: Bool = false

    // MARK: - Private

    private var recomputeTask: Task<Void, Never>?
    private let debounceInterval: TimeInterval = 5.0
    private let maxBlocks = 50
    private let mergeThreshold: Double = 0.55
    private let boundingPadding: CGFloat = 40

    private struct ModeSizing {
        let minWidth: CGFloat
        let minHeight: CGFloat
        let maxWidth: CGFloat
        let maxHeight: CGFloat
    }

    // MARK: - Public API

    /// Schedule a debounced recompute. Call this when block count or positions change.
    func scheduleRecompute(blocks: [CanvasBlock]) {
        recomputeTask?.cancel()
        recomputeTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(debounceInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await recompute(blocks: blocks)
        }
    }

    /// Immediately recompute clusters.
    func recompute(blocks: [CanvasBlock]) async {
        guard isEnabled, blocks.count >= 2, blocks.count <= maxBlocks else {
            clusters = []
            return
        }

        let uuids = blocks.map { $0.entityUuid }
        let blocksByUUID = Dictionary(blocks.map { ($0.entityUuid, $0) }, uniquingKeysWith: { a, _ in a })

        // Step 1: Fetch pairwise graph edges
        var edgeSet = Set<String>()
        do {
            let engine = GraphQueryEngine()
            let edges = try await engine.getEdgesForBlocks(uuids: uuids)
            for edge in edges {
                let key = [edge.sourceUUID, edge.targetUUID].sorted().joined(separator: ":")
                edgeSet.insert(key)
            }
        } catch {
            print("CanvasClusterEngine: edge fetch failed: \(error)")
        }

        guard !Task.isCancelled else { return }

        // Step 2: Build affinity matrix using graph edges + NL title similarity
        // Prefer sentence embedding (handles multi-word titles), fallback to word embedding
        let sentenceEmb = NLEmbedding.sentenceEmbedding(for: .english)
        let wordEmb = sentenceEmb == nil ? NLEmbedding.wordEmbedding(for: .english) : nil
        var affinity: [String: Double] = [:]

        for i in 0..<uuids.count {
            for j in (i + 1)..<uuids.count {
                let a = uuids[i]
                let b = uuids[j]
                let pairKey = [a, b].sorted().joined(separator: ":")

                // Graph edge boost
                let hasEdge = edgeSet.contains(pairKey)
                let edgeBoost: Double = hasEdge ? 0.3 : 0.0

                // Title similarity via NLEmbedding
                var titleSim: Double = 0.0
                let titleA = blocksByUUID[a]?.title ?? ""
                let titleB = blocksByUUID[b]?.title ?? ""

                if !titleA.isEmpty && !titleB.isEmpty {
                    if let emb = sentenceEmb {
                        let dist = emb.distance(between: titleA.lowercased(), and: titleB.lowercased())
                        if dist < 100 { // filter out NLDistanceNotFound
                            titleSim = max(0, 1.0 - dist)
                        }
                    } else if let emb = wordEmb {
                        // Word-level fallback: compare first significant word
                        let wordA = titleA.lowercased().split(separator: " ").first.map(String.init) ?? titleA.lowercased()
                        let wordB = titleB.lowercased().split(separator: " ").first.map(String.init) ?? titleB.lowercased()
                        let dist = emb.distance(between: wordA, and: wordB)
                        if dist < 100 {
                            titleSim = max(0, 1.0 - dist)
                        }
                    }
                }

                affinity[pairKey] = titleSim + edgeBoost
            }
        }

        guard !Task.isCancelled else { return }

        // Step 3: Agglomerative clustering (average linkage)
        var clusterMembers: [[String]] = uuids.map { [$0] }

        while clusterMembers.count > 1 {
            var bestI = -1
            var bestJ = -1
            var bestAffinity: Double = -1

            for i in 0..<clusterMembers.count {
                for j in (i + 1)..<clusterMembers.count {
                    let avg = averageLinkage(clusterA: clusterMembers[i], clusterB: clusterMembers[j], affinity: affinity)
                    if avg > bestAffinity {
                        bestAffinity = avg
                        bestI = i
                        bestJ = j
                    }
                }
            }

            guard bestAffinity >= mergeThreshold else { break }

            // Merge j into i, remove j
            clusterMembers[bestI].append(contentsOf: clusterMembers[bestJ])
            clusterMembers.remove(at: bestJ)
        }

        guard !Task.isCancelled else { return }

        // Step 4: Discard singletons
        let multiMember = clusterMembers.filter { $0.count > 1 }

        // Step 5: Build CanvasCluster objects
        var result: [CanvasCluster] = []
        for (index, members) in multiMember.enumerated() {
            let name = extractClusterName(members: members, blocksByUUID: blocksByUUID, index: index)
            let rect = computeBoundingRect(members: members, blocksByUUID: blocksByUUID)

            result.append(CanvasCluster(
                id: UUID(),
                name: name,
                blockUUIDs: members,
                colorIndex: index,
                boundingRect: rect,
                isCollapsed: false,
                isUserCreated: false
            ))
        }

        clusters = result
    }

    // MARK: - Average Linkage

    private func averageLinkage(clusterA: [String], clusterB: [String], affinity: [String: Double]) -> Double {
        var sum: Double = 0
        var count: Int = 0
        for a in clusterA {
            for b in clusterB {
                let key = [a, b].sorted().joined(separator: ":")
                sum += affinity[key] ?? 0
                count += 1
            }
        }
        return count > 0 ? sum / Double(count) : 0
    }

    // MARK: - Cluster Naming

    private func extractClusterName(members: [String], blocksByUUID: [String: CanvasBlock], index: Int) -> String {
        let titles = members.compactMap { blocksByUUID[$0]?.title }
        let combined = titles.joined(separator: " ")

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = combined

        var keywords: [String] = []
        tagger.enumerateTags(in: combined.startIndex..<combined.endIndex, unit: .word, scheme: .nameType) { tag, range in
            if tag != nil {
                keywords.append(String(combined[range]))
            }
            return true
        }

        if let best = keywords.first, !best.isEmpty {
            return best
        }

        // Fallback: most common significant word across titles
        let words = titles
            .flatMap { $0.split(separator: " ").map { String($0) } }
            .filter { $0.count > 3 }

        let freq = Dictionary(grouping: words, by: { $0.lowercased() })
            .sorted { $0.value.count > $1.value.count }

        if let topWord = freq.first?.value.first {
            return topWord
        }

        return "Cluster \(index + 1)"
    }

    // MARK: - Bounding Rect

    private func computeBoundingRect(members: [String], blocksByUUID: [String: CanvasBlock]) -> CGRect {
        let blocks = members.compactMap { blocksByUUID[$0] }
        guard !blocks.isEmpty else { return .zero }

        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        for block in blocks {
            let left = block.position.x - block.size.width / 2
            let right = block.position.x + block.size.width / 2
            let top = block.position.y - block.size.height / 2
            let bottom = block.position.y + block.size.height / 2

            minX = min(minX, left)
            minY = min(minY, top)
            maxX = max(maxX, right)
            maxY = max(maxY, bottom)
        }

        let topPadding = boundingPadding + CanvasCluster.titleTopPadding

        return CGRect(
            x: minX - boundingPadding,
            y: minY - topPadding,
            width: (maxX - minX) + boundingPadding * 2,
            height: (maxY - minY) + boundingPadding + topPadding
        )
    }

    // MARK: - User Cluster Management

    /// Create a user cluster from selected blocks
    func createUserCluster(name: String, colorIndex: Int, blockUUIDs: [String], blocks: [CanvasBlock], thinkspaceId: String?) {
        var cluster = CanvasCluster(
            id: UUID(),
            name: name,
            blockUUIDs: blockUUIDs,
            colorIndex: colorIndex,
            boundingRect: .zero,
            isCollapsed: false,
            isUserCreated: true,
            thinkspaceId: thinkspaceId
        )
        cluster.updateBoundingRect(blocks: blocks)
        userClusters.append(cluster)

        // Persist and synthesize in background
        persistUserClusters(thinkspaceId: thinkspaceId)
        Task {
            await synthesizeCluster(id: cluster.id, blocks: blocks)
        }
    }

    /// Create an empty zone cluster with a defined bounding rect and no blocks
    func createZoneCluster(name: String, colorIndex: Int, boundingRect: CGRect, thinkspaceId: String?) {
        let cluster = CanvasCluster(
            id: UUID(),
            name: name,
            blockUUIDs: [],
            colorIndex: colorIndex,
            boundingRect: boundingRect,
            isCollapsed: false,
            isUserCreated: true,
            thinkspaceId: thinkspaceId,
            manualSizeOverride: boundingRect.size,
            isZone: true
        )
        userClusters.append(cluster)
        persistUserClusters(thinkspaceId: thinkspaceId)
    }

    /// Remove a user cluster
    func removeUserCluster(id: UUID) {
        guard let index = userClusters.firstIndex(where: { $0.id == id }) else { return }
        let thinkspaceId = userClusters[index].thinkspaceId
        userClusters.remove(at: index)
        persistUserClusters(thinkspaceId: thinkspaceId)
    }

    /// Rename a user cluster
    func renameUserCluster(id: UUID, to newName: String) {
        guard let index = userClusters.firstIndex(where: { $0.id == id }) else { return }
        userClusters[index].name = newName
        persistUserClusters(thinkspaceId: userClusters[index].thinkspaceId)
    }

    /// Change a user cluster's color
    func changeClusterColor(id: UUID, colorIndex: Int) {
        guard let index = userClusters.firstIndex(where: { $0.id == id }) else { return }
        userClusters[index].colorIndex = colorIndex
        persistUserClusters(thinkspaceId: userClusters[index].thinkspaceId)
    }

    /// Add a block to a user cluster
    func addBlockToCluster(blockUUID: String, clusterId: UUID, blocks: [CanvasBlock]) {
        addBlockToClusterOnly(blockUUID: blockUUID, clusterId: clusterId, blocks: blocks)
        if let index = userClusters.firstIndex(where: { $0.id == clusterId }) {
            persistUserClusters(thinkspaceId: userClusters[index].thinkspaceId)
        }
    }

    /// Remove a block from a user cluster
    func removeBlockFromCluster(blockUUID: String, clusterId: UUID, blocks: [CanvasBlock]) {
        let thinkspaceId = removeBlockFromClusterOnly(blockUUID: blockUUID, clusterId: clusterId, blocks: blocks)
        if let tsId = thinkspaceId {
            persistUserClusters(thinkspaceId: tsId)
        }
    }

    /// Transfer a block between clusters in a single atomic persist.
    /// Avoids the race condition of separate remove + add persists.
    func transferBlock(blockUUID: String, from sourceClusterId: UUID?, to targetClusterId: UUID, blocks: [CanvasBlock]) {
        if let sourceClusterId {
            _ = removeBlockFromClusterOnly(blockUUID: blockUUID, clusterId: sourceClusterId, blocks: blocks)
        }
        addBlockToClusterOnly(blockUUID: blockUUID, clusterId: targetClusterId, blocks: blocks)
        let tsId = userClusters.first(where: { $0.id == targetClusterId })?.thinkspaceId
            ?? userClusters.first?.thinkspaceId
        persistUserClusters(thinkspaceId: tsId)
    }

    /// Update cluster membership after a canvas drag. Removes from old clusters,
    /// adds to target, and persists exactly once.
    func updateMembership(blockUUID: String, targetClusterId: UUID?, blockPosition: CGPoint, ejectInset: CGFloat, blocks: [CanvasBlock]) {
        if let targetClusterId {
            let sourceIds = userClusters
                .filter { $0.id != targetClusterId && $0.blockUUIDs.contains(blockUUID) }
                .map(\.id)
            for sourceId in sourceIds {
                _ = removeBlockFromClusterOnly(blockUUID: blockUUID, clusterId: sourceId, blocks: blocks)
            }
            addBlockToClusterOnly(blockUUID: blockUUID, clusterId: targetClusterId, blocks: blocks)
        } else {
            for cluster in userClusters {
                let expandedRect = cluster.boundingRect.insetBy(dx: ejectInset, dy: ejectInset)
                if cluster.blockUUIDs.contains(blockUUID) && !expandedRect.contains(blockPosition) {
                    _ = removeBlockFromClusterOnly(blockUUID: blockUUID, clusterId: cluster.id, blocks: blocks)
                }
            }
        }
        updateUserClusterBounds(blocks: blocks)
        persistAfterMove()
    }

    // MARK: - Non-persisting mutation helpers

    /// Add block to cluster without persisting. Returns the thinkspace ID for callers that batch persists.
    private func addBlockToClusterOnly(blockUUID: String, clusterId: UUID, blocks: [CanvasBlock]) {
        guard let index = userClusters.firstIndex(where: { $0.id == clusterId }) else { return }
        guard !userClusters[index].blockUUIDs.contains(blockUUID) else { return }
        userClusters[index].blockUUIDs.append(blockUUID)

        withAnimation(ProMotionSprings.gentle) {
            switch userClusters[index].viewMode {
            case .canvas:
                break
            case .grid:
                break
            case .list, .board:
                if let fitted = fitClusterRectForMode(
                    clusterId: clusterId,
                    mode: userClusters[index].viewMode,
                    blocks: blocks,
                    viewportInCanvas: nil
                ) {
                    userClusters[index].boundingRect = fitted
                }
            }
        }
    }

    /// Remove block from cluster without persisting. Returns the thinkspace ID
    /// so callers can batch the persist call.
    @discardableResult
    private func removeBlockFromClusterOnly(blockUUID: String, clusterId: UUID, blocks: [CanvasBlock]) -> String? {
        guard let index = userClusters.firstIndex(where: { $0.id == clusterId }) else { return nil }
        userClusters[index].blockUUIDs.removeAll { $0 == blockUUID }
        if userClusters[index].blockUUIDs.isEmpty && !userClusters[index].isZone {
            let thinkspaceId = userClusters[index].thinkspaceId
            userClusters.remove(at: index)
            return thinkspaceId
        } else {
            withAnimation(ProMotionSprings.gentle) {
                switch userClusters[index].viewMode {
                case .canvas:
                    // Canvas cluster rects are user-authoritative and grow-only;
                    // removing a member must not shrink the container.
                    break
                case .grid:
                    break
                case .list, .board:
                    if let fitted = fitClusterRectForMode(
                        clusterId: clusterId,
                        mode: userClusters[index].viewMode,
                        blocks: blocks,
                        viewportInCanvas: nil
                    ) {
                        userClusters[index].boundingRect = fitted
                    }
                }
            }
            return userClusters[index].thinkspaceId
        }
    }

    /// Select a cluster (deselects any previous selection)
    func selectCluster(_ id: UUID?) {
        selectedClusterId = id
    }

    /// Get the entity UUIDs of all blocks in a user cluster
    func memberBlockUUIDs(for clusterId: UUID) -> [String] {
        userClusters.first(where: { $0.id == clusterId })?.blockUUIDs ?? []
    }

    func clusterContaining(blockUUID: String) -> CanvasCluster? {
        userClusters.first(where: { $0.blockUUIDs.contains(blockUUID) })
    }

    /// Update bounding rects for all user clusters (call after block positions change)
    func updateUserClusterBounds(blocks: [CanvasBlock]) {
        // User-created cluster geometry is authoritative after creation or manual resize.
        // Membership and block moves should not stretch folders/clusters unexpectedly.
    }

    /// Persist clusters after a move (public wrapper for persistUserClusters)
    func persistAfterMove() {
        guard let tsId = userClusters.first?.thinkspaceId else { return }
        persistUserClusters(thinkspaceId: tsId)
    }

    /// Move a cluster rect directly in canvas space.
    /// Used for manual drag so the rect translates cleanly instead of re-fitting.
    func offsetClusterRect(id: UUID, by delta: CGSize) {
        guard let index = userClusters.firstIndex(where: { $0.id == id }) else { return }
        userClusters[index].boundingRect.origin.x += delta.width
        userClusters[index].boundingRect.origin.y += delta.height
    }

    // MARK: - View Mode Management

    /// Transient state: which block is expanded in list mode (per cluster)
    @Published var expandedBlockUUIDs: [UUID: String] = [:]

    /// Switch cluster view mode. Auto-sizes for list/board if needed.
    func setViewMode(for clusterId: UUID, mode: ClusterViewMode, blocks: [CanvasBlock]) {
        guard let index = userClusters.firstIndex(where: { $0.id == clusterId }) else { return }
        guard !(userClusters[index].viewMode == .grid && mode == .grid) else { return }

        withAnimation(ProMotionSprings.gentle) {
            userClusters[index].viewMode = mode

            if mode == .canvas {
                userClusters[index].clearManualSize()
                userClusters[index].updateBoundingRect(blocks: blocks, growOnly: true)
            } else if let fitted = fitClusterRectForMode(clusterId: clusterId, mode: mode, blocks: blocks, viewportInCanvas: nil) {
                userClusters[index].boundingRect = fitted
                userClusters[index].manualSizeOverride = fitted.size
            }
        }

        persistUserClusters(thinkspaceId: userClusters[index].thinkspaceId)
    }

    /// Change board grouping mode for board view.
    func setBoardGrouping(for clusterId: UUID, grouping: ClusterBoardGrouping) {
        guard let index = userClusters.firstIndex(where: { $0.id == clusterId }) else { return }
        userClusters[index].boardGrouping = grouping
        persistUserClusters(thinkspaceId: userClusters[index].thinkspaceId)
    }

    /// Change sort order for list mode
    func setSortOrder(for clusterId: UUID, order: ClusterSortOrder) {
        guard let index = userClusters.firstIndex(where: { $0.id == clusterId }) else { return }
        userClusters[index].sortOrder = order
        persistUserClusters(thinkspaceId: userClusters[index].thinkspaceId)
    }

    /// Toggle expanded block in list mode
    func toggleListExpand(clusterId: UUID, blockUUID: String) {
        if expandedBlockUUIDs[clusterId] == blockUUID {
            expandedBlockUUIDs[clusterId] = nil
        } else {
            expandedBlockUUIDs[clusterId] = blockUUID
        }
    }

    /// Fit a list/board cluster into bounded dimensions while preserving manual override as a floor.
    func fitClusterRectForMode(
        clusterId: UUID,
        mode: ClusterViewMode,
        blocks: [CanvasBlock],
        viewportInCanvas: CGRect?
    ) -> CGRect? {
        guard let index = userClusters.firstIndex(where: { $0.id == clusterId }) else { return nil }
        let cluster = userClusters[index]
        var rect = cluster.boundingRect

        let sizing: ModeSizing = {
            switch mode {
            case .canvas:
                return .init(minWidth: 240, minHeight: 180, maxWidth: 2200, maxHeight: 1600)
            case .list:
                return .init(minWidth: 360, minHeight: 280, maxWidth: 1100, maxHeight: 1200)
            case .board:
                return .init(minWidth: 560, minHeight: 320, maxWidth: 1600, maxHeight: 1200)
            case .grid:
                return .init(minWidth: 600, minHeight: 400, maxWidth: 1600, maxHeight: 1200)
            }
        }()

        let memberBlocks = ClusterGridContent.orderedMemberBlocks(for: cluster, blocks: blocks)
        let memberCount = memberBlocks.count
        let adaptiveHeight: CGFloat
        switch mode {
        case .grid:
            // Measure actual masonry layout height instead of crude per-item formula
            let gridContentWidth = max(rect.width - 20, sizing.minWidth - 20)
            let measured = ClusterGridContent.estimatedGridHeight(blocks: memberBlocks, availableWidth: gridContentWidth)
            adaptiveHeight = max(400, measured + 70)  // 54pt title bar + 16pt padding
        case .board:
            let boardCols = cluster.boardColumns(from: blocks)
            let maxCards = boardCols.map(\.blocks.count).max() ?? 0
            adaptiveHeight = max(320, CGFloat(80 + maxCards * 42))
        case .list:
            adaptiveHeight = CGFloat(280 + Double(max(memberCount - 4, 0)) * 26)
        case .canvas:
            adaptiveHeight = 180
        }

        var width = rect.width
        var height = max(rect.height, adaptiveHeight)

        if let manual = cluster.manualSizeOverride {
            width = max(width, manual.width)
            height = max(height, manual.height)
        }

        width = min(max(width, sizing.minWidth), sizing.maxWidth)
        height = min(max(height, sizing.minHeight), sizing.maxHeight)

        rect.size = CGSize(width: width, height: height)

        if let viewport = viewportInCanvas {
            let margin: CGFloat = 24
            let minX = viewport.minX + margin
            let maxX = viewport.maxX - margin - rect.width
            let minY = viewport.minY + margin
            let maxY = viewport.maxY - margin - rect.height
            if minX <= maxX { rect.origin.x = min(max(rect.origin.x, minX), maxX) }
            if minY <= maxY { rect.origin.y = min(max(rect.origin.y, minY), maxY) }
        }

        return rect
    }

    /// Update atom metadata when a card is dragged between board columns
    func updateBlockColumnValue(blockUUID: String, newValue: String, clusterId: UUID) {
        guard let clusterIndex = userClusters.firstIndex(where: { $0.id == clusterId }) else { return }
        let members = Set(userClusters[clusterIndex].blockUUIDs)
        guard members.contains(blockUUID) else { return }

        Task {
            do {
                let repo = AtomRepository.shared
                guard var atom = try await repo.fetch(uuid: blockUUID) else { return }

                // Determine what to update based on atom type
                switch atom.type {
                case .task:
                    var taskMeta = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
                    let canonical = Self.normalizedBoardColumnValue(for: .task, rawValue: newValue)
                    taskMeta.status = canonical
                    if canonical == "completed" {
                        taskMeta.isCompleted = true
                        taskMeta.completedAt = PlannerumFormatters.iso8601.string(from: Date())
                    } else {
                        taskMeta.isCompleted = false
                        taskMeta.completedAt = nil
                    }
                    atom = atom.withMetadata(taskMeta)

                case .content:
                    // Update content status in metadata dict
                    var metaDict = atom.metadataDict ?? [:]
                    let canonical = Self.normalizedBoardColumnValue(for: .content, rawValue: newValue)
                    metaDict["status"] = canonical
                    metaDict["currentStep"] = Self.contentStepForPhase(canonical)
                    if let data = try? JSONSerialization.data(withJSONObject: metaDict),
                       let str = String(data: data, encoding: .utf8) {
                        atom.metadata = str
                    }

                case .idea:
                    let canonical = Self.normalizedBoardColumnValue(for: .idea, rawValue: newValue)
                    if let status = IdeaStatus(rawValue: canonical) {
                        var ideaMeta = atom.ideaMetadata ?? IdeaMetadata()
                        ideaMeta.ideaStatus = status
                        atom = atom.withMetadata(ideaMeta)
                    }

                default:
                    return  // No-op for types without status
                }

                atom.updatedAt = ISO8601.string(from: Date())
                try await repo.update(atom)
            } catch {
                print("CanvasClusterEngine: updateBlockColumnValue failed: \(error)")
            }
        }
    }

    /// Apply a board drop event, including cross-cluster transfer and immediate local metadata update.
    func applyBoardDrop(
        event: BoardDropEvent,
        blocks: inout [CanvasBlock],
        mutateLocalMetadata: ((String, String, EntityType) -> Void)? = nil
    ) {
        guard userClusters.contains(where: { $0.id == event.targetClusterId }) else { return }

        let sourceClusterId = userClusters.first(where: { $0.blockUUIDs.contains(event.blockUUID) })?.id
        let blockIndex = blocks.firstIndex(where: { $0.entityUuid == event.blockUUID })
        let entityType = blockIndex.map { blocks[$0].entityType }
        let isTypeGroupingDrop = Self.isTypeGroupingColumn(event.targetColumnValue)
        let canonical: String? = {
            guard !isTypeGroupingDrop else { return nil }
            return Self.normalizedBoardColumnValue(for: entityType ?? .idea, rawValue: event.targetColumnValue)
        }()

        // Membership transfer (supports cross-cluster drop)
        if let sourceId = sourceClusterId, sourceId != event.targetClusterId,
           let sourceIndex = userClusters.firstIndex(where: { $0.id == sourceId }) {
            userClusters[sourceIndex].blockUUIDs.removeAll { $0 == event.blockUUID }
            if userClusters[sourceIndex].blockUUIDs.isEmpty && !userClusters[sourceIndex].isZone {
                userClusters.remove(at: sourceIndex)
            }
        }

        if let targetIndex = userClusters.firstIndex(where: { $0.id == event.targetClusterId }) {
            if !userClusters[targetIndex].blockUUIDs.contains(event.blockUUID) {
                userClusters[targetIndex].blockUUIDs.append(event.blockUUID)
            }
        }

        // Immediate in-memory update for visible board/list rows.
        if let idx = blockIndex {
            if let canonical {
                applyLocalBoardValue(canonical, to: &blocks[idx])
                mutateLocalMetadata?(event.blockUUID, canonical, blocks[idx].entityType)
                persistAtomColumnValue(blockUUID: event.blockUUID, entityType: blocks[idx].entityType, canonicalValue: canonical)
            }
        } else {
            if let canonical {
                persistAtomColumnValue(blockUUID: event.blockUUID, entityType: nil, canonicalValue: canonical)
            }
        }

        let thinkspaceId = userClusters.first(where: { $0.id == event.targetClusterId })?.thinkspaceId
            ?? sourceClusterId.flatMap { id in userClusters.first(where: { $0.id == id })?.thinkspaceId }
        persistUserClusters(thinkspaceId: thinkspaceId)
    }

    // MARK: - Cluster Resize

    /// The cluster currently being resized (for live preview)
    @Published var resizingClusterId: UUID?

    /// Rect captured at the start of a resize gesture (before any delta applied)
    private var resizeStartRect: CGRect?

    /// Apply a live resize to a cluster from a specific edge/corner.
    /// `delta` is the cumulative DragGesture translation from drag start.
    func resizeCluster(id: UUID, delta: CGSize, edge: ClusterResizeEdge, blocks: [CanvasBlock]) {
        guard let index = userClusters.firstIndex(where: { $0.id == id }) else { return }

        // Capture starting rect on first call of this resize gesture
        if resizingClusterId != id {
            resizingClusterId = id
            resizeStartRect = userClusters[index].boundingRect
        }

        guard let startRect = resizeStartRect else { return }
        var rect = startRect
        let minSize = CanvasCluster.minimumSize

        switch edge {
        case .right:
            rect.size.width = max(minSize.width, startRect.width + delta.width)
        case .left:
            let newWidth = max(minSize.width, startRect.width - delta.width)
            rect.origin.x = startRect.maxX - newWidth
            rect.size.width = newWidth
        case .bottom:
            rect.size.height = max(minSize.height, startRect.height + delta.height)
        case .top:
            let newHeight = max(minSize.height, startRect.height - delta.height)
            rect.origin.y = startRect.maxY - newHeight
            rect.size.height = newHeight
        case .bottomRight:
            rect.size.width = max(minSize.width, startRect.width + delta.width)
            rect.size.height = max(minSize.height, startRect.height + delta.height)
        case .topLeft:
            let newWidth = max(minSize.width, startRect.width - delta.width)
            let newHeight = max(minSize.height, startRect.height - delta.height)
            rect.origin.x = startRect.maxX - newWidth
            rect.origin.y = startRect.maxY - newHeight
            rect.size.width = newWidth
            rect.size.height = newHeight
        case .topRight:
            rect.size.width = max(minSize.width, startRect.width + delta.width)
            let newHeight = max(minSize.height, startRect.height - delta.height)
            rect.origin.y = startRect.maxY - newHeight
            rect.size.height = newHeight
        case .bottomLeft:
            let newWidth = max(minSize.width, startRect.width - delta.width)
            rect.origin.x = startRect.maxX - newWidth
            rect.size.width = newWidth
            rect.size.height = max(minSize.height, startRect.height + delta.height)
        }

        var updated = userClusters[index]
        updated.boundingRect = rect
        updated.manualSizeOverride = rect.size
        userClusters[index] = updated
    }

    /// Commit a resize — persist the new size directly without recomputing from blocks.
    /// The manualSizeOverride was already set during resizeCluster(), and updateBoundingRect
    /// would fight the user's resize by re-centering around block positions.
    func commitClusterResize(id: UUID, blocks: [CanvasBlock]) {
        guard let index = userClusters.firstIndex(where: { $0.id == id }) else { return }
        resizingClusterId = nil
        resizeStartRect = nil
        persistUserClusters(thinkspaceId: userClusters[index].thinkspaceId)
    }

    /// ID of the cluster a block is currently being dragged over (for visual feedback)
    @Published var dropTargetClusterId: UUID?

    /// Find which user cluster a canvas position falls within (exact bounds)
    func userCluster(containing point: CGPoint) -> CanvasCluster? {
        resolvedDropTargetCluster(for: point, proximity: 0)
    }

    /// Find the nearest user cluster within drop proximity of a point.
    /// Uses an expanded hit zone (80pt outset) so blocks dropped near a cluster get absorbed.
    func nearestDropTargetCluster(for point: CGPoint) -> CanvasCluster? {
        resolvedDropTargetCluster(for: point, proximity: 80)
    }

    /// Resolve a cross-cluster canvas transfer target and the exact preview position to show/commit.
    /// The source cluster is excluded so transfers remain stable even if cluster bounds overlap.
    func resolveCanvasDrop(
        blockUUID: String,
        point: CGPoint,
        blockSize: CGSize,
        proximity: CGFloat = 80
    ) -> CanvasClusterDropResolution? {
        let sourceClusterId = clusterContaining(blockUUID: blockUUID)?.id
        guard let target = resolvedDropTargetCluster(
            for: point,
            excludingClusterId: sourceClusterId,
            proximity: proximity
        ) else {
            return nil
        }

        return CanvasClusterDropResolution(
            clusterId: target.id,
            previewPosition: clampedPreviewPosition(
                for: point,
                blockSize: blockSize,
                in: target
            )
        )
    }

    /// Clamp a block position into a target cluster without changing that cluster's size.
    /// Used by non-canvas filing paths before membership changes, so a block never
    /// stretches the target toward its old canvas position.
    func containedDropPosition(
        preferredPoint: CGPoint? = nil,
        blockSize: CGSize,
        inCluster clusterId: UUID
    ) -> CGPoint? {
        guard let cluster = userClusters.first(where: { $0.id == clusterId }) else { return nil }
        return clampedPreviewPosition(
            for: preferredPoint ?? rectCenter(cluster.boundingRect),
            blockSize: blockSize,
            in: cluster
        )
    }

    /// Update canvas transfer preview/highlight during a drag and return the resolved target.
    func updateCanvasDropTarget(
        blockUUID: String,
        point: CGPoint,
        blockSize: CGSize,
        proximity: CGFloat = 80
    ) -> CanvasClusterDropResolution? {
        let resolution = resolveCanvasDrop(
            blockUUID: blockUUID,
            point: point,
            blockSize: blockSize,
            proximity: proximity
        )
        let targetId = resolution?.clusterId
        if dropTargetClusterId != targetId {
            dropTargetClusterId = targetId
        }
        return resolution
    }

    /// Update the drop target highlight during a drag. Call on every drag move.
    func updateDropTarget(for point: CGPoint) {
        let target = nearestDropTargetCluster(for: point)
        if dropTargetClusterId != target?.id {
            dropTargetClusterId = target?.id
        }
    }

    /// Clear the drop target (call on drag end / cancel)
    func clearDropTarget() {
        dropTargetClusterId = nil
    }

    private func resolvedDropTargetCluster(
        for point: CGPoint,
        excludingClusterId: UUID? = nil,
        proximity: CGFloat,
        eligibleModes: Set<ClusterViewMode>? = nil
    ) -> CanvasCluster? {
        let candidates = userClusters.filter { cluster in
            guard cluster.id != excludingClusterId else { return false }
            if let eligibleModes, !eligibleModes.contains(cluster.viewMode) {
                return false
            }
            return distance(from: point, to: cluster.boundingRect) <= proximity
        }

        return candidates.min { lhs, rhs in
            let lhsDistance = distance(from: point, to: lhs.boundingRect)
            let rhsDistance = distance(from: point, to: rhs.boundingRect)
            if abs(lhsDistance - rhsDistance) > 0.001 {
                return lhsDistance < rhsDistance
            }

            let lhsCenterDistance = squaredDistance(from: point, to: rectCenter(lhs.boundingRect))
            let rhsCenterDistance = squaredDistance(from: point, to: rectCenter(rhs.boundingRect))
            if abs(lhsCenterDistance - rhsCenterDistance) > 0.001 {
                return lhsCenterDistance < rhsCenterDistance
            }

            let lhsArea = lhs.boundingRect.width * lhs.boundingRect.height
            let rhsArea = rhs.boundingRect.width * rhs.boundingRect.height
            if abs(lhsArea - rhsArea) > 0.001 {
                return lhsArea < rhsArea
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func clampedPreviewPosition(
        for point: CGPoint,
        blockSize: CGSize,
        in cluster: CanvasCluster
    ) -> CGPoint {
        let horizontalInset = max(24, blockSize.width / 2 + 20)
        let bottomInset = max(24, blockSize.height / 2 + 20)
        let topInset = max(bottomInset, blockSize.height / 2 + CanvasCluster.titleTopPadding + 20)

        let minX = cluster.boundingRect.minX + horizontalInset
        let maxX = cluster.boundingRect.maxX - horizontalInset
        let minY = cluster.boundingRect.minY + topInset
        let maxY = cluster.boundingRect.maxY - bottomInset

        let resolvedX = clamp(point.x, min: minX, max: maxX)
        let resolvedY = clamp(point.y, min: minY, max: maxY)

        return CGPoint(x: resolvedX, y: resolvedY)
    }

    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx: CGFloat
        if point.x < rect.minX {
            dx = rect.minX - point.x
        } else if point.x > rect.maxX {
            dx = point.x - rect.maxX
        } else {
            dx = 0
        }

        let dy: CGFloat
        if point.y < rect.minY {
            dy = rect.minY - point.y
        } else if point.y > rect.maxY {
            dy = point.y - rect.maxY
        } else {
            dy = 0
        }

        return hypot(dx, dy)
    }

    private func rectCenter(_ rect: CGRect) -> CGPoint {
        CGPoint(x: rect.midX, y: rect.midY)
    }

    private func squaredDistance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return (dx * dx) + (dy * dy)
    }

    private func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        guard minValue <= maxValue else { return (minValue + maxValue) / 2 }
        return Swift.min(Swift.max(value, minValue), maxValue)
    }

    /// Load user clusters from ThinkspaceMetadata
    /// Read-only cluster snapshot for prefetching a thinkspace the user is
    /// about to enter — same source as `loadUserClusters` but touches no
    /// engine state and skips the fit pass (the authoritative load right
    /// after a real switch corrects degenerate grid/list/board rects).
    static func clustersSnapshot(thinkspaceId: String, blocks: [CanvasBlock]) async -> [CanvasCluster] {
        guard let atom = try? await AtomRepository.shared.fetch(uuid: thinkspaceId),
              let metadata = atom.metadataValue(as: ThinkspaceMetadata.self) else { return [] }
        return metadata.clusters.map { $0.toCanvasCluster(blocks: blocks, thinkspaceId: thinkspaceId) }
    }

    func loadUserClusters(thinkspaceId: String?, blocks: [CanvasBlock]) async {
        guard let tsId = thinkspaceId else {
            userClusters = []
            return
        }

        do {
            let repo = AtomRepository.shared
            guard let atom = try await repo.fetch(uuid: tsId),
                  let metadata = atom.metadataValue(as: ThinkspaceMetadata.self) else {
                userClusters = []
                return
            }

            userClusters = metadata.clusters.map { $0.toCanvasCluster(blocks: blocks, thinkspaceId: tsId) }
            for idx in userClusters.indices where shouldFitLoadedCluster(userClusters[idx]) {
                let id = userClusters[idx].id
                let mode = userClusters[idx].viewMode
                if let fitted = fitClusterRectForMode(clusterId: id, mode: mode, blocks: blocks, viewportInCanvas: nil) {
                    userClusters[idx].boundingRect = fitted
                    // Don't overwrite manualSizeOverride — it should only be set by
                    // explicit user resize, not recalculated on every load.
                }
            }
        } catch {
            print("CanvasClusterEngine: Failed to load user clusters: \(error)")
        }
    }

    private func shouldFitLoadedCluster(_ cluster: CanvasCluster) -> Bool {
        switch cluster.viewMode {
        case .canvas:
            return false
        case .grid:
            return cluster.boundingRect.width <= 0 || cluster.boundingRect.height <= 0
        case .list, .board:
            return true
        }
    }

    /// Persist user clusters to ThinkspaceMetadata
    private func persistUserClusters(thinkspaceId: String?) {
        guard let tsId = thinkspaceId else { return }

        let codable = userClusters
            .filter { $0.isUserCreated }
            .map { CodableCluster(from: $0) }

        Task {
            do {
                let repo = AtomRepository.shared
                guard var atom = try await repo.fetch(uuid: tsId) else { return }

                var metadata = atom.metadataValue(as: ThinkspaceMetadata.self) ?? ThinkspaceMetadata()
                metadata.clusters = codable

                if let json = try? JSONEncoder().encode(metadata),
                   let str = String(data: json, encoding: .utf8) {
                    atom.metadata = str
                }
                atom.updatedAt = ISO8601.string(from: Date())
                try await repo.update(atom)
            } catch {
                print("CanvasClusterEngine: Failed to persist clusters: \(error)")
            }
        }
    }

    // MARK: - Board Value Normalization

    func normalizedBoardColumnValue(for type: EntityType, rawValue: String) -> String {
        Self.normalizedBoardColumnValue(for: type, rawValue: rawValue)
    }

    static func normalizedBoardColumnValue(for type: EntityType, rawValue: String) -> String {
        switch type {
        case .task:
            return canonicalTaskStatus(rawValue)
        case .content:
            return canonicalContentPhase(rawValue)
        case .idea:
            return canonicalIdeaStatus(rawValue)
        default:
            return rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    nonisolated static func canonicalTaskStatus(_ rawValue: String) -> String {
        let key = normalizedKey(rawValue)
        switch key {
        case "todo", "to_do", "pending":
            return "todo"
        case "inprogress", "in_progress", "active", "doing":
            return "in_progress"
        case "completed", "done", "complete":
            return "completed"
        default:
            return "todo"
        }
    }

    nonisolated static func canonicalContentPhase(_ rawValue: String) -> String {
        let key = normalizedKey(rawValue)
        switch key {
        case "ideation", "brainstorm":
            return "ideation"
        case "draft":
            return "draft"
        case "polish":
            return "polish"
        case "archived", "archive":
            return "archived"
        default:
            return "ideation"
        }
    }

    nonisolated static func canonicalIdeaStatus(_ rawValue: String) -> String {
        let key = normalizedKey(rawValue)
        switch key {
        case "spark":
            return "spark"
        case "developing":
            return "developing"
        case "ready", "inproduction", "published":
            return "ready"
        case "archived", "archive":
            return "archived"
        default:
            return "spark"
        }
    }

    nonisolated static func contentStepForPhase(_ phase: String) -> String {
        switch canonicalContentPhase(phase) {
        case "ideation": return "brainstorm"
        case "draft": return "draft"
        case "polish": return "polish"
        case "archived": return "polish"
        default: return "brainstorm"
        }
    }

    nonisolated private static func normalizedKey(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    nonisolated private static func isTypeGroupingColumn(_ rawValue: String) -> Bool {
        let key = normalizedKey(rawValue)
        switch key {
        case "idea", "content", "connection", "research", "task", "project", "note", "cosmo_ai", "swipe_file":
            return true
        default:
            return false
        }
    }

    private func applyLocalBoardValue(_ canonical: String, to block: inout CanvasBlock) {
        switch block.entityType {
        case .task:
            block.metadata["status"] = canonical
        case .content:
            block.metadata["status"] = canonical
            block.metadata["currentStep"] = Self.contentStepForPhase(canonical)
        case .idea:
            block.metadata["ideaStatus"] = canonical
        default:
            block.metadata["status"] = canonical
        }
    }

    private func persistAtomColumnValue(blockUUID: String, entityType: EntityType?, canonicalValue: String) {
        Task {
            do {
                let repo = AtomRepository.shared
                guard var atom = try await repo.fetch(uuid: blockUUID) else { return }
                let resolvedType = entityType ?? EntityType(rawValue: atom.type.rawValue) ?? .idea

                switch resolvedType {
                case .task:
                    var taskMeta = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
                    let canonical = Self.canonicalTaskStatus(canonicalValue)
                    taskMeta.status = canonical
                    taskMeta.isCompleted = canonical == "completed"
                    taskMeta.completedAt = canonical == "completed"
                        ? PlannerumFormatters.iso8601.string(from: Date())
                        : nil
                    atom = atom.withMetadata(taskMeta)

                case .content:
                    var metaDict = atom.metadataDict ?? [:]
                    let canonical = Self.canonicalContentPhase(canonicalValue)
                    metaDict["status"] = canonical
                    metaDict["currentStep"] = Self.contentStepForPhase(canonical)
                    if let data = try? JSONSerialization.data(withJSONObject: metaDict),
                       let str = String(data: data, encoding: .utf8) {
                        atom.metadata = str
                    }

                case .idea:
                    let canonical = Self.canonicalIdeaStatus(canonicalValue)
                    if let status = IdeaStatus(rawValue: canonical) {
                        var ideaMeta = atom.ideaMetadata ?? IdeaMetadata()
                        ideaMeta.ideaStatus = status
                        atom = atom.withMetadata(ideaMeta)
                    }

                default:
                    return
                }

                atom.updatedAt = ISO8601.string(from: Date())
                try await repo.update(atom)
            } catch {
                print("CanvasClusterEngine: persistAtomColumnValue failed: \(error)")
            }
        }
    }

    // MARK: - AI Cluster Synthesis

    /// Generate an AI summary for a user cluster
    func synthesizeCluster(id: UUID, blocks: [CanvasBlock]) async {
        guard let index = userClusters.firstIndex(where: { $0.id == id }) else { return }
        let cluster = userClusters[index]

        // Gather block titles and bodies
        let memberBlocks = blocks.filter { cluster.blockUUIDs.contains($0.entityUuid) }
        guard !memberBlocks.isEmpty else { return }

        var context = ""
        for block in memberBlocks {
            let title = block.title.isEmpty ? block.entityType.rawValue : block.title
            context += "- \(title)\n"
        }

        // Also fetch atom bodies for richer context
        let repo = AtomRepository.shared
        for block in memberBlocks {
            if let atom = try? await repo.fetch(uuid: block.entityUuid) {
                let body = (atom.body ?? "").prefix(300)
                if !body.isEmpty {
                    context += "  Content: \(body)\n"
                }
            }
        }

        let prompt = """
        You are summarizing a cluster of related knowledge blocks in a thinkspace canvas.
        The cluster is named "\(cluster.name)".

        Blocks in this cluster:
        \(context)

        Provide a concise 1-2 sentence summary of what this cluster is about and its key themes.
        Just return the summary text, no formatting or labels.
        """

        do {
            let summary = try await ResearchService.shared.generateWithCaching(
                systemBlocks: [(content: "You are a concise summarizer for knowledge clusters.", cacheControl: false)],
                messages: [["role": "user", "content": prompt]],
                model: "anthropic/claude-3-haiku-20240307",
                maxTokens: 200,
                temperature: 0.3
            )
            guard let idx = userClusters.firstIndex(where: { $0.id == id }) else { return }
            userClusters[idx].synthesis = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            userClusters[idx].synthesisUpdatedAt = ISO8601.string(from: Date())
            persistUserClusters(thinkspaceId: userClusters[idx].thinkspaceId)
        } catch {
            print("CanvasClusterEngine: Synthesis failed: \(error)")
        }
    }
}
