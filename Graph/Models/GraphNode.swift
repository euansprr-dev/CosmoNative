// CosmoOS/Graph/Models/GraphNode.swift
// Graph node model - represents an ATOM in the NodeGraph OS constellation
// Each node references an Atom by UUID and caches relevance/position metadata

import GRDB
import Foundation

// MARK: - GraphNode Model
/// Represents a node in the knowledge graph constellation
/// Each GraphNode wraps an Atom, adding graph-specific metadata for visualization and ranking
public struct GraphNode: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {

    // MARK: - GRDB Table Configuration
    public static let databaseTableName = "graph_nodes"

    // ═══════════════════════════════════════════════════════════════
    // IDENTITY - References the Atom
    // ═══════════════════════════════════════════════════════════════

    /// Database row ID
    public var id: Int64?

    /// Foreign key to atoms.uuid - THE canonical identifier
    public var atomUUID: String

    /// Denormalized AtomType for O(1) filtering (e.g., "idea", "task")
    public var atomType: String

    /// Denormalized AtomCategory for clustering (e.g., "core", "physiology")
    public var atomCategory: String

    // ═══════════════════════════════════════════════════════════════
    // POSITION HINTS - For constellation visualization
    // ═══════════════════════════════════════════════════════════════

    /// Cached X position in 2D constellation projection
    public var positionX: Double?

    /// Cached Y position in 2D constellation projection
    public var positionY: Double?

    /// Semantic cluster assignment (e.g., "work", "health", "creative")
    public var clusterHint: String?

    // ═══════════════════════════════════════════════════════════════
    // RELEVANCE CACHE - Pre-computed for ranking
    // ═══════════════════════════════════════════════════════════════

    /// PageRank score (0.0-1.0), computed periodically
    public var pageRank: Double

    /// Count of incoming edges
    public var inDegree: Int

    /// Count of outgoing edges
    public var outDegree: Int

    /// Usage frequency counter
    public var accessCount: Int

    /// Last time this node was accessed (ISO8601)
    public var lastAccessedAt: String?

    // ═══════════════════════════════════════════════════════════════
    // EMBEDDING STATE - Vector availability
    // ═══════════════════════════════════════════════════════════════

    /// Whether a vector embedding exists for this node
    public var hasEmbedding: Bool

    /// When the embedding was last updated (ISO8601)
    public var embeddingUpdatedAt: String?

    // ═══════════════════════════════════════════════════════════════
    // TIMESTAMPS
    // ═══════════════════════════════════════════════════════════════

    /// When this graph node was created (ISO8601)
    public var createdAt: String

    /// When this graph node was last updated (ISO8601)
    public var updatedAt: String

    /// When the source atom was last updated (for staleness detection)
    public var atomUpdatedAt: String

    // MARK: - CodingKeys
    enum CodingKeys: String, ColumnExpression, CodingKey {
        case id
        case atomUUID = "atom_uuid"
        case atomType = "atom_type"
        case atomCategory = "atom_category"
        case positionX = "position_x"
        case positionY = "position_y"
        case clusterHint = "cluster_hint"
        case pageRank = "page_rank"
        case inDegree = "in_degree"
        case outDegree = "out_degree"
        case accessCount = "access_count"
        case lastAccessedAt = "last_accessed_at"
        case hasEmbedding = "has_embedding"
        case embeddingUpdatedAt = "embedding_updated_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case atomUpdatedAt = "atom_updated_at"
    }
}

// MARK: - GraphNode Factory
extension GraphNode {

    /// Create a new GraphNode from an Atom
    /// - Parameter atom: The source Atom to create a node for
    /// - Returns: A new GraphNode with sensible defaults
    public static func from(atom: Atom) -> GraphNode {
        let now = ISO8601DateFormatter().string(from: Date())

        return GraphNode(
            id: nil,
            atomUUID: atom.uuid,
            atomType: atom.type.rawValue,
            atomCategory: atom.type.category.rawValue,
            positionX: nil,
            positionY: nil,
            clusterHint: nil,
            pageRank: 0.0,
            inDegree: 0,
            outDegree: 0,
            accessCount: 0,
            lastAccessedAt: nil,
            hasEmbedding: false,
            embeddingUpdatedAt: nil,
            createdAt: now,
            updatedAt: now,
            atomUpdatedAt: atom.updatedAt
        )
    }

    /// Create a new GraphNode with explicit values
    public static func new(
        atomUUID: String,
        atomType: AtomType,
        atomUpdatedAt: String? = nil
    ) -> GraphNode {
        let now = ISO8601DateFormatter().string(from: Date())

        return GraphNode(
            id: nil,
            atomUUID: atomUUID,
            atomType: atomType.rawValue,
            atomCategory: atomType.category.rawValue,
            positionX: nil,
            positionY: nil,
            clusterHint: nil,
            pageRank: 0.0,
            inDegree: 0,
            outDegree: 0,
            accessCount: 0,
            lastAccessedAt: nil,
            hasEmbedding: false,
            embeddingUpdatedAt: nil,
            createdAt: now,
            updatedAt: now,
            atomUpdatedAt: atomUpdatedAt ?? now
        )
    }
}

// MARK: - GraphNode Computed Properties
extension GraphNode {

    /// The typed AtomType (if valid)
    public var type: AtomType? {
        AtomType(rawValue: atomType)
    }

    /// The typed AtomCategory (if valid)
    var category: AtomCategory? {
        AtomCategory(rawValue: atomCategory)
    }

    /// Total degree (in + out)
    public var totalDegree: Int {
        inDegree + outDegree
    }

    /// Whether this node has a cached position
    public var hasPosition: Bool {
        positionX != nil && positionY != nil
    }

    /// Position as a CGPoint (if available)
    public var position: CGPoint? {
        guard let x = positionX, let y = positionY else { return nil }
        return CGPoint(x: x, y: y)
    }

    /// Whether the node data is stale compared to the atom
    /// - Parameter atomUpdatedAt: The atom's current updatedAt value
    /// - Returns: True if the atom has been updated since this node was synced
    public func isStale(comparedTo atomUpdatedAt: String) -> Bool {
        self.atomUpdatedAt < atomUpdatedAt
    }
}

// MARK: - GraphNode Mutations
extension GraphNode {

    /// Create a copy with updated position
    public func withPosition(x: Double, y: Double) -> GraphNode {
        var copy = self
        copy.positionX = x
        copy.positionY = y
        copy.updatedAt = ISO8601DateFormatter().string(from: Date())
        return copy
    }

    /// Create a copy with updated degree counts
    public func withDegrees(inDegree: Int, outDegree: Int) -> GraphNode {
        var copy = self
        copy.inDegree = inDegree
        copy.outDegree = outDegree
        copy.updatedAt = ISO8601DateFormatter().string(from: Date())
        return copy
    }

    /// Create a copy with incremented in-degree
    public func incrementingInDegree() -> GraphNode {
        var copy = self
        copy.inDegree += 1
        copy.updatedAt = ISO8601DateFormatter().string(from: Date())
        return copy
    }

    /// Create a copy with decremented in-degree
    public func decrementingInDegree() -> GraphNode {
        var copy = self
        copy.inDegree = max(0, copy.inDegree - 1)
        copy.updatedAt = ISO8601DateFormatter().string(from: Date())
        return copy
    }

    /// Create a copy with incremented out-degree
    public func incrementingOutDegree() -> GraphNode {
        var copy = self
        copy.outDegree += 1
        copy.updatedAt = ISO8601DateFormatter().string(from: Date())
        return copy
    }

    /// Create a copy with decremented out-degree
    public func decrementingOutDegree() -> GraphNode {
        var copy = self
        copy.outDegree = max(0, copy.outDegree - 1)
        copy.updatedAt = ISO8601DateFormatter().string(from: Date())
        return copy
    }

    /// Create a copy with updated PageRank
    public func withPageRank(_ pageRank: Double) -> GraphNode {
        var copy = self
        copy.pageRank = max(0.0, min(1.0, pageRank))
        copy.updatedAt = ISO8601DateFormatter().string(from: Date())
        return copy
    }

    /// Create a copy with embedding marked as available
    public func withEmbedding() -> GraphNode {
        var copy = self
        copy.hasEmbedding = true
        copy.embeddingUpdatedAt = ISO8601DateFormatter().string(from: Date())
        copy.updatedAt = copy.embeddingUpdatedAt!
        return copy
    }

    /// Create a copy with recorded access
    public func recordingAccess() -> GraphNode {
        var copy = self
        copy.accessCount += 1
        copy.lastAccessedAt = ISO8601DateFormatter().string(from: Date())
        copy.updatedAt = copy.lastAccessedAt!
        return copy
    }

    /// Create a copy synced with atom updates
    public func syncedWith(atom: Atom) -> GraphNode {
        var copy = self
        copy.atomType = atom.type.rawValue
        copy.atomCategory = atom.type.category.rawValue
        copy.atomUpdatedAt = atom.updatedAt
        copy.updatedAt = ISO8601DateFormatter().string(from: Date())
        return copy
    }
}

// MARK: - GraphNode Queries
extension GraphNode {

    /// Column reference for type-safe queries
    static let atomUUIDColumn = Column(CodingKeys.atomUUID)
    static let atomTypeColumn = Column(CodingKeys.atomType)
    static let atomCategoryColumn = Column(CodingKeys.atomCategory)
    static let pageRankColumn = Column(CodingKeys.pageRank)
    static let inDegreeColumn = Column(CodingKeys.inDegree)
    static let outDegreeColumn = Column(CodingKeys.outDegree)
    static let accessCountColumn = Column(CodingKeys.accessCount)
    static let lastAccessedAtColumn = Column(CodingKeys.lastAccessedAt)
    static let hasEmbeddingColumn = Column(CodingKeys.hasEmbedding)
    static let clusterHintColumn = Column(CodingKeys.clusterHint)
    static let createdAtColumn = Column(CodingKeys.createdAt)
    static let updatedAtColumn = Column(CodingKeys.updatedAt)
}
