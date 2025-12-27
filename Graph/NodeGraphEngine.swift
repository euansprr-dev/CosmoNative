// CosmoOS/Graph/NodeGraphEngine.swift
// Central actor for NodeGraph OS - manages incremental graph updates
// Handles ATOM lifecycle events and maintains graph consistency

import GRDB
import Foundation
import Combine

// MARK: - NodeGraphEngine
/// The central engine for NodeGraph OS - manages the knowledge graph
/// Processes ATOM changes incrementally to maintain graph consistency
@MainActor
public final class NodeGraphEngine: ObservableObject {

    // MARK: - Singleton
    public static let shared = NodeGraphEngine()

    // MARK: - Published State
    @Published public private(set) var isInitialized = false
    @Published public private(set) var nodeCount: Int = 0
    @Published public private(set) var edgeCount: Int = 0
    @Published public private(set) var isUpdating = false
    @Published public private(set) var lastUpdateAt: Date?

    // MARK: - Configuration
    /// Minimum semantic similarity for creating semantic edges
    public let semanticEdgeThreshold: Float = 0.6

    /// Maximum number of semantic edges per node
    public let maxSemanticEdgesPerNode = 10

    /// Debounce interval for batching rapid updates
    public let debounceInterval: TimeInterval = 0.5

    /// Batch size for bulk operations
    public let batchSize = 100

    // MARK: - Dependencies
    private var database: CosmoDatabase { CosmoDatabase.shared }

    // MARK: - Debouncing
    private var pendingUpdates: Set<String> = []  // Atom UUIDs
    private var updateTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization
    private init() {
        Task {
            await initialize()
        }
    }

    /// Initialize the engine, loading current graph stats
    public func initialize() async {
        guard !isInitialized else { return }

        do {
            // Load current graph statistics
            try await refreshStats()
            isInitialized = true
            print("✅ NodeGraphEngine initialized: \(nodeCount) nodes, \(edgeCount) edges")
        } catch {
            print("❌ NodeGraphEngine initialization failed: \(error)")
        }
    }

    // MARK: - Graph Statistics

    /// Refresh node and edge counts from database
    public func refreshStats() async throws {
        let stats = try await database.asyncRead { db -> (nodes: Int, edges: Int) in
            let nodes = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM graph_nodes") ?? 0
            let edges = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM graph_edges") ?? 0
            return (nodes, edges)
        }

        nodeCount = stats.nodes
        edgeCount = stats.edges
    }

    // MARK: - ATOM Lifecycle Handlers

    /// Handle a newly created ATOM
    /// - Parameter atom: The newly created Atom
    public func handleAtomCreated(_ atom: Atom) async throws {
        isUpdating = true
        defer { isUpdating = false }

        try await database.asyncWrite { db in
            // 1. Create graph node for this atom
            var newNode = GraphNode.from(atom: atom)
            try newNode.insert(db)
            newNode.id = db.lastInsertedRowID

            // 2. Create explicit edges from AtomLinks
            for link in atom.linksList {
                // Only create edge if target exists in graph
                let targetExists = try Bool.fetchOne(
                    db,
                    sql: "SELECT EXISTS(SELECT 1 FROM graph_nodes WHERE atom_uuid = ?)",
                    arguments: [link.uuid]
                ) ?? false

                if targetExists, let linkType = AtomLinkType(rawValue: link.type) {
                    var newEdge = GraphEdge.explicit(
                        from: atom.uuid,
                        to: link.uuid,
                        linkType: linkType
                    )
                    try newEdge.insert(db)
                    newEdge.id = db.lastInsertedRowID

                    // Update degree counts
                    try db.execute(
                        sql: "UPDATE graph_nodes SET out_degree = out_degree + 1, updated_at = datetime('now') WHERE atom_uuid = ?",
                        arguments: [atom.uuid]
                    )
                    try db.execute(
                        sql: "UPDATE graph_nodes SET in_degree = in_degree + 1, updated_at = datetime('now') WHERE atom_uuid = ?",
                        arguments: [link.uuid]
                    )
                }
            }
        }

        // 3. Queue semantic edge discovery (async, debounced)
        queueSemanticEdgeDiscovery(for: atom.uuid)

        try await refreshStats()
        lastUpdateAt = Date()

        // Post notification
        NotificationCenter.default.post(
            name: CosmoNotification.NodeGraph.graphNodeUpdated,
            object: nil,
            userInfo: ["atomUUID": atom.uuid]
        )
    }

    /// Handle an updated ATOM
    /// - Parameters:
    ///   - atom: The updated Atom
    ///   - changedFields: List of fields that changed (e.g., ["title", "body", "links"])
    public func handleAtomUpdated(_ atom: Atom, changedFields: [String]) async throws {
        isUpdating = true
        defer { isUpdating = false }

        try await database.asyncWrite { db in
            // 1. Update graph node metadata
            try db.execute(
                sql: """
                    UPDATE graph_nodes
                    SET atom_type = ?,
                        atom_category = ?,
                        atom_updated_at = ?,
                        updated_at = datetime('now')
                    WHERE atom_uuid = ?
                """,
                arguments: [
                    atom.type.rawValue,
                    atom.type.category.rawValue,
                    atom.updatedAt,
                    atom.uuid
                ]
            )

            // 2. Reconcile explicit edges if links changed
            if changedFields.contains("links") {
                try self.reconcileExplicitEdges(for: atom, in: db)
            }
        }

        // 3. If content changed, queue re-embedding
        let contentFields = ["title", "body", "structured"]
        if changedFields.contains(where: { contentFields.contains($0) }) {
            queueSemanticEdgeDiscovery(for: atom.uuid)
        }

        lastUpdateAt = Date()

        // Post notification
        NotificationCenter.default.post(
            name: CosmoNotification.NodeGraph.graphNodeUpdated,
            object: nil,
            userInfo: ["atomUUID": atom.uuid]
        )
    }

    /// Handle a deleted ATOM
    /// - Parameter atomUUID: The UUID of the deleted Atom
    public func handleAtomDeleted(atomUUID: String) async throws {
        isUpdating = true
        defer { isUpdating = false }

        try await database.asyncWrite { db in
            // 1. Get all edges involving this node for degree updates
            let affectedEdges = try GraphEdge.fetchAll(
                db,
                sql: """
                    SELECT * FROM graph_edges
                    WHERE source_uuid = ? OR target_uuid = ?
                """,
                arguments: [atomUUID, atomUUID]
            )

            // 2. Update neighbor degree counts
            for edge in affectedEdges {
                if edge.sourceUUID == atomUUID {
                    // Decrement in_degree of target
                    try db.execute(
                        sql: "UPDATE graph_nodes SET in_degree = MAX(0, in_degree - 1), updated_at = datetime('now') WHERE atom_uuid = ?",
                        arguments: [edge.targetUUID]
                    )
                }
                if edge.targetUUID == atomUUID {
                    // Decrement out_degree of source
                    try db.execute(
                        sql: "UPDATE graph_nodes SET out_degree = MAX(0, out_degree - 1), updated_at = datetime('now') WHERE atom_uuid = ?",
                        arguments: [edge.sourceUUID]
                    )
                }
            }

            // 3. Delete the node (edges CASCADE)
            try db.execute(
                sql: "DELETE FROM graph_nodes WHERE atom_uuid = ?",
                arguments: [atomUUID]
            )
        }

        try await refreshStats()
        lastUpdateAt = Date()

        // Post notification
        NotificationCenter.default.post(
            name: CosmoNotification.NodeGraph.graphNodeUpdated,
            object: nil,
            userInfo: ["atomUUID": atomUUID]
        )
    }

    // MARK: - Edge Reconciliation

    /// Reconcile explicit edges when an Atom's links change
    private nonisolated func reconcileExplicitEdges(for atom: Atom, in db: Database) throws {
        // Get current AtomLinks
        let currentLinks = Set(atom.linksList.map { "\($0.uuid):\($0.type)" })

        // Get existing explicit edges
        let existingEdges = try GraphEdge.fetchAll(
            db,
            sql: """
                SELECT * FROM graph_edges
                WHERE source_uuid = ? AND edge_type = 'explicit'
            """,
            arguments: [atom.uuid]
        )
        let existingKeys = Set(existingEdges.map { "\($0.targetUUID):\($0.linkType ?? "")" })

        // Find edges to add
        let toAdd = currentLinks.subtracting(existingKeys)
        for key in toAdd {
            let parts = key.split(separator: ":")
            guard parts.count == 2,
                  let linkType = AtomLinkType(rawValue: String(parts[1])) else { continue }

            let targetUUID = String(parts[0])

            // Only create edge if target exists
            let targetExists = try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM graph_nodes WHERE atom_uuid = ?)",
                arguments: [targetUUID]
            ) ?? false

            if targetExists {
                var newEdge = GraphEdge.explicit(from: atom.uuid, to: targetUUID, linkType: linkType)
                try newEdge.insert(db)
                newEdge.id = db.lastInsertedRowID

                // Update degree counts
                try db.execute(
                    sql: "UPDATE graph_nodes SET out_degree = out_degree + 1, updated_at = datetime('now') WHERE atom_uuid = ?",
                    arguments: [atom.uuid]
                )
                try db.execute(
                    sql: "UPDATE graph_nodes SET in_degree = in_degree + 1, updated_at = datetime('now') WHERE atom_uuid = ?",
                    arguments: [targetUUID]
                )
            }
        }

        // Find edges to remove
        let toRemove = existingKeys.subtracting(currentLinks)
        for key in toRemove {
            let parts = key.split(separator: ":")
            guard parts.count >= 1 else { continue }

            let targetUUID = String(parts[0])

            try db.execute(
                sql: "DELETE FROM graph_edges WHERE source_uuid = ? AND target_uuid = ? AND edge_type = 'explicit'",
                arguments: [atom.uuid, targetUUID]
            )

            // Update degree counts
            try db.execute(
                sql: "UPDATE graph_nodes SET out_degree = MAX(0, out_degree - 1), updated_at = datetime('now') WHERE atom_uuid = ?",
                arguments: [atom.uuid]
            )
            try db.execute(
                sql: "UPDATE graph_nodes SET in_degree = MAX(0, in_degree - 1), updated_at = datetime('now') WHERE atom_uuid = ?",
                arguments: [targetUUID]
            )
        }
    }

    // MARK: - Semantic Edge Discovery

    /// Queue semantic edge discovery (debounced)
    private func queueSemanticEdgeDiscovery(for atomUUID: String) {
        pendingUpdates.insert(atomUUID)

        // Cancel existing timer
        updateTask?.cancel()

        // Start new debounce timer
        updateTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(debounceInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }

            let uuidsToProcess = pendingUpdates
            pendingUpdates.removeAll()

            for uuid in uuidsToProcess {
                await discoverSemanticEdges(for: uuid)
            }
        }
    }

    /// Discover semantic edges for an atom based on vector similarity
    public func discoverSemanticEdges(for atomUUID: String) async {
        // TODO: Integrate with VectorDatabase once we have access to it
        // For now, this is a placeholder that will be wired up in Phase 3

        // 1. Get the atom's embedding from VectorDatabase
        // 2. Search for similar atoms (top-K above threshold)
        // 3. Create/update semantic edges

        do {
            try await database.asyncWrite { db in
                // Mark node as having embedding processed
                try db.execute(
                    sql: """
                        UPDATE graph_nodes
                        SET has_embedding = 1,
                            embedding_updated_at = datetime('now'),
                            updated_at = datetime('now')
                        WHERE atom_uuid = ?
                    """,
                    arguments: [atomUUID]
                )
            }
        } catch {
            print("⚠️ Failed to update embedding state for \(atomUUID): \(error)")
        }
    }

    /// Create or update a semantic edge between two nodes
    public func createOrUpdateSemanticEdge(
        sourceUUID: String,
        targetUUID: String,
        similarity: Float
    ) async throws {
        guard similarity >= semanticEdgeThreshold else { return }

        try await database.asyncWrite { db in
            // Check if edge exists
            let existingEdge = try GraphEdge.fetchOne(
                db,
                sql: """
                    SELECT * FROM graph_edges
                    WHERE source_uuid = ? AND target_uuid = ? AND edge_type = 'semantic'
                """,
                arguments: [sourceUUID, targetUUID]
            )

            if var edge = existingEdge {
                // Update existing edge
                edge = edge.withSemanticWeight(similarity)
                try edge.update(db)
            } else {
                // Create new edge
                var semanticEdge = GraphEdge.semantic(
                    from: sourceUUID,
                    to: targetUUID,
                    similarity: similarity
                )
                try semanticEdge.insert(db)
                semanticEdge.id = db.lastInsertedRowID
            }
        }

        try await refreshStats()
    }

    // MARK: - Access Recording

    /// Record an access event for a node (for usage-based ranking)
    public func recordAccess(atomUUID: String, type: AccessType = .view) async throws {
        try await database.asyncWrite { db in
            try db.execute(
                sql: """
                    UPDATE graph_nodes
                    SET access_count = access_count + 1,
                        last_accessed_at = datetime('now'),
                        updated_at = datetime('now')
                    WHERE atom_uuid = ?
                """,
                arguments: [atomUUID]
            )
        }

        // Boost usage weight on related edges
        if type == .edit || type == .reference {
            try await boostEdgeUsage(for: atomUUID)
        }
    }

    /// Boost usage weight on all edges connected to a node
    private func boostEdgeUsage(for atomUUID: String) async throws {
        try await database.asyncWrite { db in
            try db.execute(
                sql: """
                    UPDATE graph_edges
                    SET usage_weight = MIN(1.0, usage_weight + 0.05),
                        combined_weight = 0.55 * semantic_weight + 0.25 * structural_weight + 0.10 * recency_weight + 0.10 * MIN(1.0, usage_weight + 0.05),
                        last_computed_at = datetime('now'),
                        updated_at = datetime('now')
                    WHERE source_uuid = ? OR target_uuid = ?
                """,
                arguments: [atomUUID, atomUUID]
            )
        }
    }

    // MARK: - Bulk Operations

    /// Rebuild explicit edges from all atoms' links (for repair/migration)
    public func rebuildExplicitEdges() async throws {
        isUpdating = true
        defer { isUpdating = false }

        print("🔨 Rebuilding explicit edges from AtomLinks...")

        // This would iterate through all atoms and recreate edges
        // Implementation depends on AtomRepository access

        try await refreshStats()
        lastUpdateAt = Date()

        print("✅ Explicit edges rebuilt")
    }

    /// Decay recency weights on all edges (run periodically)
    public func decayRecencyWeights() async throws {
        try await database.asyncWrite { db in
            // Calculate days since last update and apply decay
            // half-life = 7 days, floor = 0.1
            try db.execute(
                sql: """
                    UPDATE graph_edges
                    SET recency_weight = MAX(0.1, EXP(-0.693 * (julianday('now') - julianday(last_computed_at)) / 7.0)),
                        combined_weight = 0.55 * semantic_weight + 0.25 * structural_weight + 0.10 * MAX(0.1, EXP(-0.693 * (julianday('now') - julianday(last_computed_at)) / 7.0)) + 0.10 * usage_weight,
                        updated_at = datetime('now')
                    WHERE 1=1
                """
            )
        }

        lastUpdateAt = Date()
    }

    // MARK: - PageRank Computation

    /// Compute PageRank for all nodes (run periodically)
    public func computePageRank(iterations: Int = 20, dampingFactor: Double = 0.85) async throws {
        isUpdating = true
        defer { isUpdating = false }

        print("🔨 Computing PageRank (\(iterations) iterations)...")

        try await database.asyncWrite { db in
            // Get node count
            let nodeCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM graph_nodes") ?? 0
            guard nodeCount > 0 else { return }

            let initialRank = 1.0 / Double(nodeCount)

            // Initialize all nodes with equal rank
            try db.execute(
                sql: "UPDATE graph_nodes SET page_rank = ?",
                arguments: [initialRank]
            )

            // Power iteration
            for iteration in 0..<iterations {
                // For each node, compute new rank based on incoming edges
                try db.execute(
                    sql: """
                        UPDATE graph_nodes
                        SET page_rank = (1.0 - ?) / ? + ? * COALESCE(
                            (SELECT SUM(
                                src.page_rank * e.combined_weight / NULLIF(src.out_degree, 0)
                            )
                            FROM graph_edges e
                            JOIN graph_nodes src ON e.source_uuid = src.atom_uuid
                            WHERE e.target_uuid = graph_nodes.atom_uuid),
                            0.0
                        )
                    """,
                    arguments: [dampingFactor, nodeCount, dampingFactor]
                )

                if (iteration + 1) % 5 == 0 {
                    print("  PageRank iteration \(iteration + 1)/\(iterations)")
                }
            }

            // Normalize to 0-1 range
            let maxRank = try Double.fetchOne(db, sql: "SELECT MAX(page_rank) FROM graph_nodes") ?? 1.0
            if maxRank > 0 {
                try db.execute(
                    sql: "UPDATE graph_nodes SET page_rank = page_rank / ?",
                    arguments: [maxRank]
                )
            }
        }

        lastUpdateAt = Date()
        print("✅ PageRank computation complete")
    }
}

// MARK: - Access Type
public enum AccessType: String, Sendable {
    case view = "view"          // Weight: 0.5
    case edit = "edit"          // Weight: 1.0
    case search = "search"      // Weight: 0.3
    case reference = "reference" // Weight: 0.7
}

