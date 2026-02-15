// CosmoOS/Graph/GraphQueryEngine.swift
// Query engine for NodeGraph OS - provides neighborhood traversal and relevance search
// Powers Command-K search and constellation visualization

import GRDB
import Foundation

// MARK: - GraphQueryEngine
/// Query engine for the NodeGraph OS knowledge graph
/// Provides neighborhood traversal, top-K search, and filtering capabilities
public struct GraphQueryEngine: Sendable {

    // MARK: - Configuration
    /// Default limit for search results
    public let defaultLimit = 20

    /// Maximum depth for neighborhood traversal
    public let maxTraversalDepth = 3

    /// Minimum combined weight for including edges
    public let minEdgeWeight: Double = 0.1

    // MARK: - Initialization
    public init() {}

    // MARK: - Database Access
    @MainActor
    private var database: CosmoDatabase { CosmoDatabase.shared }

    // MARK: - Node Queries

    /// Fetch a single graph node by atom UUID
    @MainActor
    public func fetchNode(atomUUID: String) async throws -> GraphNode? {
        return try await database.asyncRead { db in
            try GraphNode.fetchOne(
                db,
                sql: "SELECT * FROM graph_nodes WHERE atom_uuid = ?",
                arguments: [atomUUID]
            )
        }
    }

    /// Fetch multiple graph nodes by atom UUIDs
    @MainActor
    public func fetchNodes(atomUUIDs: [String]) async throws -> [GraphNode] {
        guard !atomUUIDs.isEmpty else { return [] }

        let placeholders = atomUUIDs.map { _ in "?" }.joined(separator: ", ")
        return try await database.asyncRead { db in
            try GraphNode.fetchAll(
                db,
                sql: "SELECT * FROM graph_nodes WHERE atom_uuid IN (\(placeholders))",
                arguments: StatementArguments(atomUUIDs)
            )
        }
    }

    /// Fetch nodes by type
    @MainActor
    public func fetchNodes(ofType type: AtomType, limit: Int? = nil) async throws -> [GraphNode] {
        let limitClause = limit.map { "LIMIT \($0)" } ?? ""
        return try await database.asyncRead { db in
            try GraphNode.fetchAll(
                db,
                sql: """
                    SELECT * FROM graph_nodes
                    WHERE atom_type = ?
                    ORDER BY page_rank DESC, last_accessed_at DESC NULLS LAST
                    \(limitClause)
                """,
                arguments: [type.rawValue]
            )
        }
    }

    /// Fetch nodes by category
    @MainActor
    func fetchNodes(inCategory category: AtomCategory, limit: Int? = nil) async throws -> [GraphNode] {
        let limitClause = limit.map { "LIMIT \($0)" } ?? ""
        return try await database.asyncRead { db in
            try GraphNode.fetchAll(
                db,
                sql: """
                    SELECT * FROM graph_nodes
                    WHERE atom_category = ?
                    ORDER BY page_rank DESC, last_accessed_at DESC NULLS LAST
                    \(limitClause)
                """,
                arguments: [category.rawValue]
            )
        }
    }

    // MARK: - Neighborhood Traversal

    /// Get the immediate neighbors of a node (1-hop)
    @MainActor
    public func getNeighbors(
        of atomUUID: String,
        direction: EdgeDirection = .both,
        edgeTypes: [GraphEdgeType]? = nil,
        limit: Int? = nil
    ) async throws -> [NeighborResult] {
        let directionClause: String
        switch direction {
        case .outgoing:
            directionClause = "e.source_uuid = ?"
        case .incoming:
            directionClause = "e.target_uuid = ?"
        case .both:
            directionClause = "(e.source_uuid = ? OR e.target_uuid = ?)"
        }

        var argumentsArray: [String] = [atomUUID]
        if direction == .both {
            argumentsArray.append(atomUUID)
        }

        var typeFilterClause = ""
        if let types = edgeTypes, !types.isEmpty {
            let placeholders = types.map { _ in "?" }.joined(separator: ", ")
            typeFilterClause = "AND e.edge_type IN (\(placeholders))"
            argumentsArray.append(contentsOf: types.map { $0.rawValue })
        }

        let limitClause = limit.map { "LIMIT \($0)" } ?? ""

        // Capture immutable copies for Sendable closure
        let capturedArguments = argumentsArray
        let capturedTypeFilter = typeFilterClause
        let capturedMinWeight = minEdgeWeight

        let rows = try await database.asyncRead { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT
                        n.*,
                        e.edge_type,
                        e.link_type,
                        e.combined_weight,
                        e.source_uuid AS edge_source,
                        e.target_uuid AS edge_target
                    FROM graph_edges e
                    JOIN graph_nodes n ON (
                        CASE
                            WHEN e.source_uuid = ? THEN n.atom_uuid = e.target_uuid
                            ELSE n.atom_uuid = e.source_uuid
                        END
                    )
                    WHERE \(directionClause) \(capturedTypeFilter)
                    AND e.combined_weight >= ?
                    ORDER BY e.combined_weight DESC
                    \(limitClause)
                """,
                arguments: StatementArguments([atomUUID] + capturedArguments + [capturedMinWeight])
            )
        }

        return rows.compactMap { row in
            guard let node = try? GraphNode(row: row) else { return nil }
            return NeighborResult(
                node: node,
                edgeType: GraphEdgeType(rawValue: row["edge_type"] as? String ?? "") ?? .explicit,
                linkType: row["link_type"] as? String,
                weight: row["combined_weight"] as? Double ?? 0.0,
                direction: (row["edge_source"] as? String) == atomUUID ? .outgoing : .incoming
            )
        }
    }

    /// Get N-hop neighborhood (constellation expansion)
    @MainActor
    public func getNeighborhood(
        of atomUUID: String,
        depth: Int = 2,
        maxNodesPerLevel: Int = 10
    ) async throws -> NeighborhoodResult {
        var visited = Set<String>([atomUUID])
        var levelNodes: [[NeighborResult]] = []
        var currentLevel = [atomUUID]

        for _ in 0..<min(depth, maxTraversalDepth) {
            var nextLevelResults: [NeighborResult] = []

            for nodeUUID in currentLevel {
                let neighbors = try await getNeighbors(
                    of: nodeUUID,
                    direction: .both,
                    limit: maxNodesPerLevel
                )

                for neighbor in neighbors {
                    if !visited.contains(neighbor.node.atomUUID) {
                        visited.insert(neighbor.node.atomUUID)
                        nextLevelResults.append(neighbor)
                    }
                }
            }

            // Sort by weight and limit
            nextLevelResults.sort { $0.weight > $1.weight }
            let limited = Array(nextLevelResults.prefix(maxNodesPerLevel))
            levelNodes.append(limited)

            currentLevel = limited.map { $0.node.atomUUID }

            if currentLevel.isEmpty { break }
        }

        return NeighborhoodResult(
            centerUUID: atomUUID,
            levels: levelNodes
        )
    }

    // MARK: - Top-K Relevance Search

    /// Search for most relevant nodes based on combined relevance scoring
    @MainActor
    func topKRelevant(
        limit: Int? = nil,
        typeFilter: [AtomType]? = nil,
        categoryFilter: [AtomCategory]? = nil,
        excludeUUIDs: [String]? = nil
    ) async throws -> [GraphNode] {
        var conditions: [String] = []
        var argumentsArray: [String] = []

        if let types = typeFilter, !types.isEmpty {
            let placeholders = types.map { _ in "?" }.joined(separator: ", ")
            conditions.append("atom_type IN (\(placeholders))")
            argumentsArray.append(contentsOf: types.map { $0.rawValue })
        }

        if let categories = categoryFilter, !categories.isEmpty {
            let placeholders = categories.map { _ in "?" }.joined(separator: ", ")
            conditions.append("atom_category IN (\(placeholders))")
            argumentsArray.append(contentsOf: categories.map { $0.rawValue })
        }

        if let excludes = excludeUUIDs, !excludes.isEmpty {
            let placeholders = excludes.map { _ in "?" }.joined(separator: ", ")
            conditions.append("atom_uuid NOT IN (\(placeholders))")
            argumentsArray.append(contentsOf: excludes)
        }

        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        let limitValue = limit ?? defaultLimit

        // Capture immutable copy for Sendable closure
        let capturedArguments = argumentsArray

        return try await database.asyncRead { db in
            try GraphNode.fetchAll(
                db,
                sql: """
                    SELECT * FROM graph_nodes
                    \(whereClause)
                    ORDER BY page_rank DESC, access_count DESC, last_accessed_at DESC NULLS LAST
                    LIMIT ?
                """,
                arguments: StatementArguments(capturedArguments + [limitValue])
            )
        }
    }

    /// Get recently accessed nodes (hot context)
    @MainActor
    public func recentlyAccessed(limit: Int = 10) async throws -> [GraphNode] {
        return try await database.asyncRead { db in
            try GraphNode.fetchAll(
                db,
                sql: """
                    SELECT * FROM graph_nodes
                    WHERE last_accessed_at IS NOT NULL
                    ORDER BY last_accessed_at DESC
                    LIMIT ?
                """,
                arguments: [limit]
            )
        }
    }

    /// Get highest PageRank nodes (hub nodes)
    @MainActor
    public func hubNodes(limit: Int = 10) async throws -> [GraphNode] {
        return try await database.asyncRead { db in
            try GraphNode.fetchAll(
                db,
                sql: """
                    SELECT * FROM graph_nodes
                    ORDER BY page_rank DESC
                    LIMIT ?
                """,
                arguments: [limit]
            )
        }
    }

    /// Get most connected nodes (by degree)
    @MainActor
    public func mostConnected(limit: Int = 10) async throws -> [GraphNode] {
        return try await database.asyncRead { db in
            try GraphNode.fetchAll(
                db,
                sql: """
                    SELECT * FROM graph_nodes
                    ORDER BY (in_degree + out_degree) DESC
                    LIMIT ?
                """,
                arguments: [limit]
            )
        }
    }

    // MARK: - Edge Queries

    /// Get edges between two nodes
    @MainActor
    public func getEdges(from sourceUUID: String, to targetUUID: String) async throws -> [GraphEdge] {
        return try await database.asyncRead { db in
            try GraphEdge.fetchAll(
                db,
                sql: """
                    SELECT * FROM graph_edges
                    WHERE (source_uuid = ? AND target_uuid = ?)
                       OR (source_uuid = ? AND target_uuid = ? AND is_directed = 0)
                    ORDER BY combined_weight DESC
                """,
                arguments: [sourceUUID, targetUUID, targetUUID, sourceUUID]
            )
        }
    }

    /// Get all edges for a node
    @MainActor
    public func getEdges(for atomUUID: String, direction: EdgeDirection = .both) async throws -> [GraphEdge] {
        let whereClause: String
        switch direction {
        case .outgoing:
            whereClause = "source_uuid = ?"
        case .incoming:
            whereClause = "target_uuid = ?"
        case .both:
            whereClause = "source_uuid = ? OR target_uuid = ?"
        }

        var argumentsArray: [String] = [atomUUID]
        if direction == .both {
            argumentsArray.append(atomUUID)
        }

        // Capture immutable copy for Sendable closure
        let capturedArguments = argumentsArray

        return try await database.asyncRead { db in
            try GraphEdge.fetchAll(
                db,
                sql: """
                    SELECT * FROM graph_edges
                    WHERE \(whereClause)
                    ORDER BY combined_weight DESC
                """,
                arguments: StatementArguments(capturedArguments)
            )
        }
    }

    /// Get strongest edges in the graph
    @MainActor
    public func strongestEdges(limit: Int = 20) async throws -> [GraphEdge] {
        return try await database.asyncRead { db in
            try GraphEdge.fetchAll(
                db,
                sql: """
                    SELECT * FROM graph_edges
                    ORDER BY combined_weight DESC
                    LIMIT ?
                """,
                arguments: [limit]
            )
        }
    }

    /// Batch query for edges where both source AND target are in the provided UUID set
    @MainActor
    public func getEdgesForBlocks(uuids: [String]) async throws -> [GraphEdge] {
        guard uuids.count >= 2 else { return [] }
        let placeholders = uuids.map { _ in "?" }.joined(separator: ", ")
        let capturedUuids = uuids
        return try await database.asyncRead { db in
            try GraphEdge.fetchAll(
                db,
                sql: """
                    SELECT * FROM graph_edges
                    WHERE source_uuid IN (\(placeholders))
                    AND target_uuid IN (\(placeholders))
                    ORDER BY combined_weight DESC
                    LIMIT 50
                """,
                arguments: StatementArguments(capturedUuids + capturedUuids)
            )
        }
    }

    // MARK: - Path Finding

    /// Find shortest path between two nodes (BFS)
    @MainActor
    public func shortestPath(
        from sourceUUID: String,
        to targetUUID: String,
        maxDepth: Int = 5
    ) async throws -> [String]? {
        // BFS to find shortest path
        var queue: [[String]] = [[sourceUUID]]
        var visited = Set<String>([sourceUUID])

        while !queue.isEmpty {
            let path = queue.removeFirst()
            let current = path.last!

            if current == targetUUID {
                return path
            }

            if path.count >= maxDepth {
                continue
            }

            // Get neighbors
            let neighbors = try await getNeighbors(of: current, direction: .both)

            for neighbor in neighbors {
                if !visited.contains(neighbor.node.atomUUID) {
                    visited.insert(neighbor.node.atomUUID)
                    queue.append(path + [neighbor.node.atomUUID])
                }
            }
        }

        return nil
    }

    // MARK: - Cluster Queries

    /// Get nodes in a cluster
    @MainActor
    public func getNodesInCluster(_ clusterHint: String, limit: Int? = nil) async throws -> [GraphNode] {
        let limitClause = limit.map { "LIMIT \($0)" } ?? ""
        return try await database.asyncRead { db in
            try GraphNode.fetchAll(
                db,
                sql: """
                    SELECT * FROM graph_nodes
                    WHERE cluster_hint = ?
                    ORDER BY page_rank DESC
                    \(limitClause)
                """,
                arguments: [clusterHint]
            )
        }
    }

    /// Get distinct cluster hints
    @MainActor
    public func getClusters() async throws -> [String] {
        return try await database.asyncRead { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT cluster_hint FROM graph_nodes
                    WHERE cluster_hint IS NOT NULL
                    ORDER BY cluster_hint
                """
            )
        }
    }

    // MARK: - Statistics

    /// Get graph statistics
    @MainActor
    public func getStatistics() async throws -> GraphStatistics {
        return try await database.asyncRead { db in
            let nodeCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM graph_nodes") ?? 0
            let edgeCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM graph_edges") ?? 0
            let avgDegree = try Double.fetchOne(db, sql: "SELECT AVG(in_degree + out_degree) FROM graph_nodes") ?? 0
            let maxDegree = try Int.fetchOne(db, sql: "SELECT MAX(in_degree + out_degree) FROM graph_nodes") ?? 0
            let avgPageRank = try Double.fetchOne(db, sql: "SELECT AVG(page_rank) FROM graph_nodes") ?? 0
            let embeddingCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM graph_nodes WHERE has_embedding = 1") ?? 0

            let typeDistribution = try Row.fetchAll(
                db,
                sql: "SELECT atom_type, COUNT(*) as count FROM graph_nodes GROUP BY atom_type ORDER BY count DESC"
            ).reduce(into: [String: Int]()) { result, row in
                if let type = row["atom_type"] as? String, let count = row["count"] as? Int {
                    result[type] = count
                }
            }

            return GraphStatistics(
                nodeCount: nodeCount,
                edgeCount: edgeCount,
                averageDegree: avgDegree,
                maxDegree: maxDegree,
                averagePageRank: avgPageRank,
                embeddingCoverage: nodeCount > 0 ? Double(embeddingCount) / Double(nodeCount) : 0,
                typeDistribution: typeDistribution
            )
        }
    }
}

// MARK: - Supporting Types

/// Direction for edge traversal
public enum EdgeDirection: Sendable {
    case outgoing
    case incoming
    case both
}

/// Result of neighbor query
public struct NeighborResult: Sendable {
    public let node: GraphNode
    public let edgeType: GraphEdgeType
    public let linkType: String?
    public let weight: Double
    public let direction: EdgeDirection
}

/// Result of neighborhood traversal
public struct NeighborhoodResult: Sendable {
    public let centerUUID: String
    public let levels: [[NeighborResult]]

    /// All nodes in the neighborhood (flattened)
    public var allNodes: [GraphNode] {
        levels.flatMap { $0.map { $0.node } }
    }

    /// All node UUIDs including center
    public var allUUIDs: [String] {
        [centerUUID] + levels.flatMap { $0.map { $0.node.atomUUID } }
    }

    /// Total node count including center
    public var totalCount: Int {
        1 + levels.reduce(0) { $0 + $1.count }
    }
}

/// Graph statistics
public struct GraphStatistics: Sendable {
    public let nodeCount: Int
    public let edgeCount: Int
    public let averageDegree: Double
    public let maxDegree: Int
    public let averagePageRank: Double
    public let embeddingCoverage: Double
    public let typeDistribution: [String: Int]

    /// Graph density (edges / possible edges)
    public var density: Double {
        guard nodeCount > 1 else { return 0 }
        let possibleEdges = nodeCount * (nodeCount - 1)
        return Double(edgeCount) / Double(possibleEdges)
    }
}
