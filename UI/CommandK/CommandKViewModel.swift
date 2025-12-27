// CosmoOS/UI/CommandK/CommandKViewModel.swift
// ViewModel for Command-K overlay - manages search state and constellation
// Powers the NodeGraph OS Command-K interface
// Phase 4: Multi-select filters, HybridSearchEngine integration, filter counts

import SwiftUI
import Combine

// MARK: - SearchPhase
/// Current phase of the search process
public enum SearchPhase: Sendable {
    case idle           // No search active
    case instant        // Instant (cached) results shown
    case searching      // Full search in progress
    case complete       // Search complete
}

// MARK: - CommandKViewModel
/// ViewModel for the Command-K overlay
/// Manages query state, results, and constellation visualization
@MainActor
public final class CommandKViewModel: ObservableObject {

    // MARK: - Published State

    /// Current search query
    @Published public var query: String = ""

    /// Current search results
    @Published public private(set) var results: [RankedResult] = []

    /// Selected result/node UUID
    @Published public var selectedNodeId: String?

    /// Current search phase
    @Published public private(set) var currentPhase: SearchPhase = .idle

    /// Whether voice input is active
    @Published public var isVoiceActive: Bool = false

    /// Multi-select type filters
    @Published public var selectedTypeFilters: Set<AtomType> = []

    /// Filter counts by type (computed from unfiltered results)
    @Published public private(set) var filterCounts: [AtomType: Int] = [:]

    /// Constellation nodes for visualization
    @Published public private(set) var constellationNodes: [ConstellationNode] = []

    /// Constellation edges for visualization
    @Published public private(set) var constellationEdges: [ConstellationEdge] = []

    /// Hovered node UUID for graph highlighting
    @Published public var hoveredNodeId: String?

    /// Error message (if any)
    @Published public var errorMessage: String?

    // MARK: - Configuration

    /// Debounce delay for search queries
    private let searchDebounce: TimeInterval = 0.15

    /// Maximum results to display
    private let maxResults = 25

    /// Canvas size for constellation layout
    public var constellationSize: CGSize = CGSize(width: 600, height: 400)

    // MARK: - Dependencies

    private let hybridSearch = HybridSearchEngine.shared
    private let queryEngine = GraphQueryEngine()
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?

    /// Unfiltered results for computing filter counts
    private var unfilteredResults: [RankedResult] = []

    // MARK: - Initialization

    public init() {
        setupQueryDebounce()
        setupFilterObserver()
    }

    // MARK: - Query Handling

    private func setupQueryDebounce() {
        $query
            .debounce(for: .seconds(searchDebounce), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] query in
                Task {
                    await self?.performSearch(query: query)
                }
            }
            .store(in: &cancellables)
    }

    private func setupFilterObserver() {
        $selectedTypeFilters
            .dropFirst()
            .sink { [weak self] _ in
                self?.applyFiltersToResults()
            }
            .store(in: &cancellables)
    }

    /// Perform search with current query using HybridSearchEngine
    public func performSearch(query: String) async {
        // Cancel previous search
        searchTask?.cancel()

        // Handle empty query - show hot context
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            await showHotContext()
            return
        }

        currentPhase = .searching

        // Check cache first
        let cacheKey = QueryResultCache.cacheKey(
            query: query,
            contextType: FocusContextDetector.shared.currentContext.type.rawValue,
            focusAtomUUID: FocusContextDetector.shared.currentContext.focusAtomUUID,
            typeFilter: nil  // Cache unfiltered, apply filters client-side
        )

        if let cached = await QueryResultCache.shared.get(for: cacheKey) {
            unfilteredResults = cached
            computeFilterCounts()
            applyFiltersToResults()
            currentPhase = .instant
            await updateConstellation()
            return
        }

        // Perform hybrid search (BM25 + vector similarity)
        searchTask = Task {
            do {
                // Use HybridSearchEngine for semantic + keyword search
                let hybridResults = try await hybridSearch.search(
                    query: query,
                    context: nil,
                    limit: maxResults * 2,  // Get more for filtering
                    entityTypes: nil  // Don't filter at search level, do it client-side for counts
                )

                // Convert HybridSearchEngine.SearchResult to RankedResult
                var rankedResults: [RankedResult] = []
                for result in hybridResults {
                    // Map EntityType to AtomType
                    let atomType = entityTypeToAtomType(result.entityType)

                    // Fetch full atom data for UUID
                    let atomUUID = await fetchAtomUUID(entityType: result.entityType, entityId: result.entityId)

                    rankedResults.append(RankedResult(
                        atomUUID: atomUUID ?? "\(result.entityType.rawValue)-\(result.entityId)",
                        atomType: atomType,
                        title: result.title,
                        snippet: result.preview,
                        semanticWeight: result.vectorSimilarity,
                        structuralWeight: result.bm25Score / 25.0,  // Normalize
                        recencyWeight: 0.5,  // Default
                        usageWeight: 0.5,    // Default
                        updatedAt: ISO8601DateFormatter().string(from: Date()),
                        accessCount: 0
                    ))
                }

                // Apply context boosts
                let context = FocusContextDetector.shared.currentContext
                let typeBoosts = FocusContextDetector.shared.getTypeBoosts()
                rankedResults = ContextAwareSearchAdapter.applyContextBoosts(
                    to: rankedResults,
                    context: context,
                    typeBoosts: typeBoosts
                )

                // Sort by combined score
                rankedResults.sort()

                // Update state
                if !Task.isCancelled {
                    unfilteredResults = rankedResults
                    computeFilterCounts()
                    applyFiltersToResults()
                    currentPhase = .complete

                    // Cache unfiltered results
                    await QueryResultCache.shared.set(rankedResults, for: cacheKey)

                    // Update constellation
                    await updateConstellation()
                }
            } catch {
                if !Task.isCancelled {
                    // Fallback to graph-based search if hybrid fails
                    await fallbackToGraphSearch(query: query)
                }
            }
        }
    }

    /// Fallback to graph-based search if HybridSearchEngine fails
    private func fallbackToGraphSearch(query: String) async {
        do {
            let nodes = try await queryEngine.topKRelevant(
                limit: maxResults * 2,
                typeFilter: nil,
                excludeUUIDs: nil
            )

            let atomUUIDs = nodes.map { $0.atomUUID }
            let atomData = await fetchAtomData(uuids: atomUUIDs)

            var rankedResults = nodes.compactMap { node -> RankedResult? in
                guard let type = node.type else { return nil }
                let atomInfo = atomData[node.atomUUID]

                return RankedResult(
                    atomUUID: node.atomUUID,
                    atomType: type,
                    title: atomInfo?.title ?? "Untitled",
                    snippet: atomInfo?.snippet,
                    semanticWeight: 0.0,
                    structuralWeight: node.pageRank,
                    recencyWeight: WeightCalculator.recencyWeight(fromISO8601: node.atomUpdatedAt),
                    usageWeight: WeightCalculator.usageWeight(accessCount: node.accessCount),
                    updatedAt: node.updatedAt,
                    accessCount: node.accessCount
                )
            }

            rankedResults.sort()
            unfilteredResults = rankedResults
            computeFilterCounts()
            applyFiltersToResults()
            currentPhase = .complete
            await updateConstellation()

        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
            currentPhase = .idle
        }
    }

    /// Compute filter counts from unfiltered results
    private func computeFilterCounts() {
        var counts: [AtomType: Int] = [:]
        for result in unfilteredResults {
            counts[result.atomType, default: 0] += 1
        }
        filterCounts = counts
    }

    /// Apply current filters to unfiltered results
    private func applyFiltersToResults() {
        if selectedTypeFilters.isEmpty {
            results = Array(unfilteredResults.prefix(maxResults))
        } else {
            results = Array(unfilteredResults
                .filter { selectedTypeFilters.contains($0.atomType) }
                .prefix(maxResults))
        }
    }

    /// Fetch atom UUID from entity type and ID
    private func fetchAtomUUID(entityType: EntityType, entityId: Int64) async -> String? {
        // Try to fetch the atom to get its UUID
        if let atom = try? await AtomRepository.shared.fetch(id: entityId) {
            return atom.uuid
        }
        return nil
    }

    /// Map EntityType to AtomType
    private func entityTypeToAtomType(_ entityType: EntityType) -> AtomType {
        switch entityType {
        case .idea: return .idea
        case .task: return .task
        case .research: return .research
        case .content: return .content
        case .connection: return .connection
        case .project: return .project
        case .journal: return .journalEntry
        case .note: return .idea  // Map notes to ideas
        default: return .idea
        }
    }

    /// Fetch atom data (title, snippet) for a list of UUIDs
    private func fetchAtomData(uuids: [String]) async -> [String: AtomInfo] {
        var result: [String: AtomInfo] = [:]

        for uuid in uuids {
            if let atom = try? await AtomRepository.shared.fetch(uuid: uuid) {
                result[uuid] = AtomInfo(
                    title: atom.title ?? "Untitled",
                    snippet: atom.body?.prefix(100).description
                )
            }
        }

        return result
    }

    /// Lightweight struct for atom display info
    private struct AtomInfo {
        let title: String
        let snippet: String?
    }

    /// Show hot context when query is empty
    private func showHotContext() async {
        currentPhase = .searching

        do {
            // Get recently accessed nodes
            let recentNodes = try await queryEngine.recentlyAccessed(limit: 15)

            // Get focus neighborhood if we have a focus
            var neighborhoodNodes: [GraphNode] = []
            if let focusUUID = FocusContextDetector.shared.currentContext.focusAtomUUID {
                if let cached = await HotContextCache.shared.get(for: focusUUID) {
                    neighborhoodNodes = cached.allNodes
                } else {
                    let neighborhood = try await queryEngine.getNeighborhood(of: focusUUID, depth: 1)
                    neighborhoodNodes = neighborhood.allNodes
                    await HotContextCache.shared.set(neighborhood, for: focusUUID)
                }
            }

            // Combine and deduplicate nodes
            var seen = Set<String>()
            var allNodes: [GraphNode] = []

            for node in recentNodes + neighborhoodNodes {
                guard !seen.contains(node.atomUUID), node.type != nil else { continue }
                seen.insert(node.atomUUID)
                allNodes.append(node)
            }

            // Fetch atom data for real titles
            let atomUUIDs = allNodes.map { $0.atomUUID }
            let atomData = await fetchAtomData(uuids: atomUUIDs)

            // Build results with real titles
            var combinedResults: [RankedResult] = []
            for node in allNodes {
                guard let type = node.type else { continue }
                let atomInfo = atomData[node.atomUUID]

                combinedResults.append(RankedResult(
                    atomUUID: node.atomUUID,
                    atomType: type,
                    title: atomInfo?.title ?? "Untitled",
                    snippet: atomInfo?.snippet,
                    semanticWeight: 0.0,
                    structuralWeight: node.pageRank,
                    recencyWeight: WeightCalculator.recencyWeight(fromISO8601: node.atomUpdatedAt),
                    usageWeight: WeightCalculator.usageWeight(accessCount: node.accessCount),
                    updatedAt: node.updatedAt,
                    accessCount: node.accessCount
                ))
            }

            combinedResults.sort()
            unfilteredResults = combinedResults
            computeFilterCounts()
            applyFiltersToResults()
            currentPhase = .complete

            await updateConstellation()

        } catch {
            errorMessage = "Failed to load hot context: \(error.localizedDescription)"
            currentPhase = .idle
        }
    }

    // MARK: - Constellation

    /// Update constellation visualization from current results
    private func updateConstellation() async {
        guard !results.isEmpty else {
            constellationNodes = []
            constellationEdges = []
            return
        }

        // Get the focus node (first result or current context focus)
        let centerUUID = FocusContextDetector.shared.currentContext.focusAtomUUID
            ?? results.first?.atomUUID
            ?? ""

        // Fetch neighborhood for constellation
        do {
            let neighborhood = try await queryEngine.getNeighborhood(
                of: centerUUID,
                depth: 2,
                maxNodesPerLevel: 10
            )

            // Compute layout
            let positions = ConstellationLayoutEngine.computeLayout(
                neighborhood: neighborhood,
                canvasSize: constellationSize
            )

            // Collect all node UUIDs for title lookup
            var allNodeUUIDs: [String] = [centerUUID]
            for level in neighborhood.levels {
                for neighbor in level {
                    allNodeUUIDs.append(neighbor.node.atomUUID)
                }
            }

            // Fetch titles for all nodes
            let atomData = await fetchAtomData(uuids: allNodeUUIDs)

            // Create nodes
            var nodes: [ConstellationNode] = []

            // Add center node
            if let centerNode = try? await queryEngine.fetchNode(atomUUID: centerUUID),
               let centerType = centerNode.type {
                let centerTitle = atomData[centerUUID]?.title ?? "Untitled"
                nodes.append(ConstellationNode(
                    atomUUID: centerUUID,
                    atomType: centerType,
                    title: centerTitle,
                    position: positions[centerUUID] ?? CGPoint(x: constellationSize.width / 2, y: constellationSize.height / 2),
                    pageRank: centerNode.pageRank,
                    degree: centerNode.totalDegree
                ))
            }

            // Add neighbor nodes
            for level in neighborhood.levels {
                for neighbor in level {
                    guard let type = neighbor.node.type,
                          let position = positions[neighbor.node.atomUUID] else { continue }

                    let nodeTitle = atomData[neighbor.node.atomUUID]?.title ?? "Untitled"
                    nodes.append(ConstellationNode(
                        atomUUID: neighbor.node.atomUUID,
                        atomType: type,
                        title: nodeTitle,
                        position: position,
                        pageRank: neighbor.node.pageRank,
                        degree: neighbor.node.totalDegree
                    ))
                }
            }

            // Create edges
            var edges: [ConstellationEdge] = []
            for level in neighborhood.levels {
                for neighbor in level {
                    guard let sourcePos = positions[centerUUID],
                          let targetPos = positions[neighbor.node.atomUUID] else { continue }

                    edges.append(ConstellationEdge(
                        sourceUUID: centerUUID,
                        targetUUID: neighbor.node.atomUUID,
                        weight: neighbor.weight,
                        edgeType: neighbor.edgeType,
                        sourcePosition: sourcePos,
                        targetPosition: targetPos
                    ))
                }
            }

            constellationNodes = nodes
            constellationEdges = edges

        } catch {
            print("⚠️ Failed to update constellation: \(error)")
        }
    }

    // MARK: - Selection

    /// Select a result by UUID
    public func select(uuid: String) {
        selectedNodeId = uuid

        // Record access
        Task {
            try? await NodeGraphEngine.shared.recordAccess(atomUUID: uuid, type: .view)
        }
    }

    /// Open the selected result
    public func openSelected() {
        guard let uuid = selectedNodeId else { return }

        // Record access
        Task {
            try? await NodeGraphEngine.shared.recordAccess(atomUUID: uuid, type: .view)
        }

        // Post notification to open
        NotificationCenter.default.post(
            name: CosmoNotification.NodeGraph.openAtomFromCommandK,
            object: nil,
            userInfo: ["atomUUID": uuid]
        )

        // Close Command-K
        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
    }

    /// Navigate selection up
    public func selectPrevious() {
        guard !results.isEmpty else { return }

        if let current = selectedNodeId,
           let index = results.firstIndex(where: { $0.atomUUID == current }),
           index > 0 {
            selectedNodeId = results[index - 1].atomUUID
        } else {
            selectedNodeId = results.last?.atomUUID
        }
    }

    /// Navigate selection down
    public func selectNext() {
        guard !results.isEmpty else { return }

        if let current = selectedNodeId,
           let index = results.firstIndex(where: { $0.atomUUID == current }),
           index < results.count - 1 {
            selectedNodeId = results[index + 1].atomUUID
        } else {
            selectedNodeId = results.first?.atomUUID
        }
    }

    // MARK: - Filter

    /// Toggle a type filter (multi-select)
    public func toggleTypeFilter(_ type: AtomType) {
        if selectedTypeFilters.contains(type) {
            selectedTypeFilters.remove(type)
        } else {
            selectedTypeFilters.insert(type)
        }
    }

    /// Clear all type filters
    public func clearTypeFilters() {
        selectedTypeFilters.removeAll()
    }

    /// Check if a type filter is active
    public func isTypeFilterActive(_ type: AtomType) -> Bool {
        selectedTypeFilters.contains(type)
    }

    /// Available filter types with their display info
    public var filterTypes: [AtomType] {
        [.idea, .task, .research, .content, .connection, .project]
    }

    /// Get count for a specific filter type
    public func countForType(_ type: AtomType) -> Int {
        filterCounts[type] ?? 0
    }

    /// Total count across all types
    public var totalCount: Int {
        unfilteredResults.count
    }

    // MARK: - Hover

    /// Set hovered node for graph highlighting
    public func setHoveredNode(_ uuid: String?) {
        hoveredNodeId = uuid
    }

    /// Check if a node or its edges should be highlighted
    public func isNodeHighlighted(_ uuid: String) -> Bool {
        guard let hoveredId = hoveredNodeId else { return false }

        // Highlight the hovered node
        if uuid == hoveredId { return true }

        // Highlight connected nodes
        return constellationEdges.contains { edge in
            (edge.sourceUUID == hoveredId && edge.targetUUID == uuid) ||
            (edge.targetUUID == hoveredId && edge.sourceUUID == uuid)
        }
    }

    /// Check if an edge should be highlighted
    public func isEdgeHighlighted(_ edge: ConstellationEdge) -> Bool {
        guard let hoveredId = hoveredNodeId else { return false }
        return edge.sourceUUID == hoveredId || edge.targetUUID == hoveredId
    }

    // MARK: - Cleanup

    /// Clear search state
    public func clear() {
        query = ""
        results = []
        unfilteredResults = []
        filterCounts = [:]
        selectedNodeId = nil
        hoveredNodeId = nil
        currentPhase = .idle
        constellationNodes = []
        constellationEdges = []
        errorMessage = nil
        selectedTypeFilters.removeAll()
    }
}
