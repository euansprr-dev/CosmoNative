// CosmoOS/AI/CanvasClusterEngine.swift
// Auto-chunking cluster engine — discovers spatial clusters from graph edges + title similarity
// Also manages user-created clusters with AI synthesis

import SwiftUI
import NaturalLanguage

@MainActor
class CanvasClusterEngine: ObservableObject {

    // MARK: - Published State

    /// Auto-detected clusters (algorithmic)
    @Published var clusters: [CanvasCluster] = []

    /// User-created clusters (persistent, loaded from ThinkspaceMetadata)
    @Published var userClusters: [CanvasCluster] = []

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
        guard let index = userClusters.firstIndex(where: { $0.id == clusterId }) else { return }
        guard !userClusters[index].blockUUIDs.contains(blockUUID) else { return }
        userClusters[index].blockUUIDs.append(blockUUID)
        userClusters[index].updateBoundingRect(blocks: blocks)
        persistUserClusters(thinkspaceId: userClusters[index].thinkspaceId)
    }

    /// Remove a block from a user cluster
    func removeBlockFromCluster(blockUUID: String, clusterId: UUID, blocks: [CanvasBlock]) {
        guard let index = userClusters.firstIndex(where: { $0.id == clusterId }) else { return }
        userClusters[index].blockUUIDs.removeAll { $0 == blockUUID }
        if userClusters[index].blockUUIDs.isEmpty && !userClusters[index].isZone {
            // Non-zone clusters auto-delete when empty; zone clusters persist
            let thinkspaceId = userClusters[index].thinkspaceId
            userClusters.remove(at: index)
            persistUserClusters(thinkspaceId: thinkspaceId)
        } else {
            userClusters[index].updateBoundingRect(blocks: blocks)
            persistUserClusters(thinkspaceId: userClusters[index].thinkspaceId)
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

    /// Update bounding rects for all user clusters (call after block positions change)
    func updateUserClusterBounds(blocks: [CanvasBlock]) {
        for index in userClusters.indices {
            // List/board clusters don't auto-resize from block positions
            guard userClusters[index].viewMode == .canvas else { continue }
            // Zones with no blocks keep their manually-set boundingRect
            let hasMembers = blocks.contains { userClusters[index].blockUUIDs.contains($0.entityUuid) }
            if hasMembers {
                userClusters[index].updateBoundingRect(blocks: blocks)
            }
        }
    }

    /// Persist clusters after a move (public wrapper for persistUserClusters)
    func persistAfterMove() {
        guard let tsId = userClusters.first?.thinkspaceId else { return }
        persistUserClusters(thinkspaceId: tsId)
    }

    // MARK: - View Mode Management

    /// Transient state: which block is expanded in list mode (per cluster)
    @Published var expandedBlockUUIDs: [UUID: String] = [:]

    /// Switch cluster view mode. Auto-sizes for list/board if needed.
    func setViewMode(for clusterId: UUID, mode: ClusterViewMode, blocks: [CanvasBlock]) {
        guard let index = userClusters.firstIndex(where: { $0.id == clusterId }) else { return }
        userClusters[index].viewMode = mode

        // Auto-size for list/board modes if cluster is too small
        if mode != .canvas {
            let rect = userClusters[index].boundingRect
            let minWidth: CGFloat = mode == .board ? 500 : 320
            let minHeight: CGFloat = 300
            if rect.width < minWidth || rect.height < minHeight {
                let newWidth = max(rect.width, minWidth)
                let newHeight = max(rect.height, minHeight)
                userClusters[index].boundingRect.size = CGSize(width: newWidth, height: newHeight)
                userClusters[index].manualSizeOverride = CGSize(width: newWidth, height: newHeight)
            }
        }

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
                    taskMeta.status = newValue
                    if newValue == "completed" {
                        taskMeta.isCompleted = true
                        taskMeta.completedAt = ISO8601DateFormatter().string(from: Date())
                    } else {
                        taskMeta.isCompleted = false
                        taskMeta.completedAt = nil
                    }
                    atom = atom.withMetadata(taskMeta)

                case .content:
                    // Update content status in metadata dict
                    var metaDict = atom.metadataDict ?? [:]
                    metaDict["status"] = newValue
                    if let data = try? JSONSerialization.data(withJSONObject: metaDict),
                       let str = String(data: data, encoding: .utf8) {
                        atom.metadata = str
                    }

                case .idea:
                    if let status = IdeaStatus(rawValue: newValue) {
                        var ideaMeta = atom.ideaMetadata ?? IdeaMetadata()
                        ideaMeta.ideaStatus = status
                        atom = atom.withMetadata(ideaMeta)
                    }

                default:
                    return  // No-op for types without status
                }

                atom.updatedAt = ISO8601DateFormatter().string(from: Date())
                try await repo.update(atom)
            } catch {
                print("CanvasClusterEngine: updateBlockColumnValue failed: \(error)")
            }
        }
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

        userClusters[index].boundingRect = rect
        userClusters[index].manualSizeOverride = rect.size
    }

    /// Commit a resize — recompute bounds (respecting manual override) and persist.
    func commitClusterResize(id: UUID, blocks: [CanvasBlock]) {
        guard let index = userClusters.firstIndex(where: { $0.id == id }) else { return }
        resizingClusterId = nil
        resizeStartRect = nil
        // Recompute so block-fit + manual override are reconciled
        userClusters[index].updateBoundingRect(blocks: blocks)
        persistUserClusters(thinkspaceId: userClusters[index].thinkspaceId)
    }

    /// ID of the cluster a block is currently being dragged over (for visual feedback)
    @Published var dropTargetClusterId: UUID?

    /// Find which user cluster a canvas position falls within (exact bounds)
    func userCluster(containing point: CGPoint) -> CanvasCluster? {
        userClusters.first { $0.boundingRect.contains(point) }
    }

    /// Find the nearest user cluster within drop proximity of a point.
    /// Uses an expanded hit zone (80pt outset) so blocks dropped near a cluster get absorbed.
    func nearestDropTargetCluster(for point: CGPoint) -> CanvasCluster? {
        let dropInset: CGFloat = -80  // negative = outset
        return userClusters.first { $0.boundingRect.insetBy(dx: dropInset, dy: dropInset).contains(point) }
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

    /// Load user clusters from ThinkspaceMetadata
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
        } catch {
            print("CanvasClusterEngine: Failed to load user clusters: \(error)")
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
                atom.updatedAt = ISO8601DateFormatter().string(from: Date())
                try await repo.update(atom)
            } catch {
                print("CanvasClusterEngine: Failed to persist clusters: \(error)")
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
            userClusters[idx].synthesisUpdatedAt = ISO8601DateFormatter().string(from: Date())
            persistUserClusters(thinkspaceId: userClusters[idx].thinkspaceId)
        } catch {
            print("CanvasClusterEngine: Synthesis failed: \(error)")
        }
    }
}
