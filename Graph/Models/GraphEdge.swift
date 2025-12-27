// CosmoOS/Graph/Models/GraphEdge.swift
// Graph edge model - represents relationships between nodes in NodeGraph OS
// Edges encode both structural (AtomLinks) and semantic (vector similarity) connections

import GRDB
import Foundation

// MARK: - GraphEdgeType Enum
/// Classification of edge types in the knowledge graph
public enum GraphEdgeType: String, Codable, CaseIterable, Sendable {

    // MARK: - Structural Edges (from AtomLinks)

    /// Direct AtomLink (project, parentIdea, etc.)
    case explicit

    /// Reference in Connection mental model
    case reference

    // MARK: - Semantic Edges (computed)

    /// Vector similarity > threshold (0.6)
    case semantic

    /// Shared keywords/concepts
    case conceptual

    /// Same project or dimension
    case contextual

    // MARK: - Derived Edges

    /// 2-hop inference (A→B→C implies A↔C with reduced weight)
    case transitive

    // MARK: - Display Properties

    /// Human-readable name
    public var displayName: String {
        switch self {
        case .explicit: return "Direct Link"
        case .reference: return "Reference"
        case .semantic: return "Semantic"
        case .conceptual: return "Conceptual"
        case .contextual: return "Contextual"
        case .transitive: return "Transitive"
        }
    }

    /// Whether this edge type is computed (vs explicit)
    public var isComputed: Bool {
        switch self {
        case .explicit, .reference:
            return false
        case .semantic, .conceptual, .contextual, .transitive:
            return true
        }
    }

    /// Base weight multiplier for this edge type
    public var baseWeight: Double {
        switch self {
        case .explicit: return 1.0
        case .reference: return 0.9
        case .semantic: return 0.8
        case .conceptual: return 0.6
        case .contextual: return 0.5
        case .transitive: return 0.4
        }
    }
}

// MARK: - GraphEdge Model
/// Represents an edge (relationship) between two nodes in the knowledge graph
public struct GraphEdge: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {

    // MARK: - GRDB Table Configuration
    public static let databaseTableName = "graph_edges"

    // ═══════════════════════════════════════════════════════════════
    // IDENTITY
    // ═══════════════════════════════════════════════════════════════

    /// Database row ID
    public var id: Int64?

    /// Source atom UUID (from node)
    public var sourceUUID: String

    /// Target atom UUID (to node)
    public var targetUUID: String

    // ═══════════════════════════════════════════════════════════════
    // EDGE PROPERTIES
    // ═══════════════════════════════════════════════════════════════

    /// Edge type classification (GraphEdgeType.rawValue)
    public var edgeType: String

    /// Original AtomLinkType if this is an explicit edge (e.g., "project", "parent_idea")
    public var linkType: String?

    /// Whether the edge is directed (false for semantic/conceptual edges)
    public var isDirected: Bool

    // ═══════════════════════════════════════════════════════════════
    // WEIGHT COMPONENTS - Stored separately for incremental update
    // Formula: combined = 0.55*semantic + 0.25*structural + 0.10*recency + 0.10*usage
    // ═══════════════════════════════════════════════════════════════

    /// Structural weight (0.0-1.0): From explicit AtomLinks
    public var structuralWeight: Double

    /// Semantic weight (0.0-1.0): From vector similarity
    public var semanticWeight: Double

    /// Recency weight (0.0-1.0): Time decay factor
    public var recencyWeight: Double

    /// Usage weight (0.0-1.0): Access frequency factor
    public var usageWeight: Double

    /// Final combined weight (0.0-1.0)
    public var combinedWeight: Double

    // ═══════════════════════════════════════════════════════════════
    // METADATA
    // ═══════════════════════════════════════════════════════════════

    /// When the weight was last computed (ISO8601)
    public var lastComputedAt: String

    /// When this edge was created (ISO8601)
    public var createdAt: String

    /// When this edge was last updated (ISO8601)
    public var updatedAt: String

    // MARK: - CodingKeys
    enum CodingKeys: String, ColumnExpression, CodingKey {
        case id
        case sourceUUID = "source_uuid"
        case targetUUID = "target_uuid"
        case edgeType = "edge_type"
        case linkType = "link_type"
        case isDirected = "is_directed"
        case structuralWeight = "structural_weight"
        case semanticWeight = "semantic_weight"
        case recencyWeight = "recency_weight"
        case usageWeight = "usage_weight"
        case combinedWeight = "combined_weight"
        case lastComputedAt = "last_computed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Weight Calculation Constants
extension GraphEdge {

    /// Weight component coefficients (must sum to 1.0)
    public static let semanticCoefficient: Double = 0.55
    public static let structuralCoefficient: Double = 0.25
    public static let recencyCoefficient: Double = 0.10
    public static let usageCoefficient: Double = 0.10

    /// Minimum semantic similarity threshold for creating semantic edges
    public static let semanticThreshold: Float = 0.6

    /// Recency half-life in days (after 7 days, recency weight is 0.5)
    public static let recencyHalfLifeDays: Double = 7.0

    /// Minimum recency weight floor (even old items have value)
    public static let recencyFloor: Double = 0.1
}

// MARK: - GraphEdge Factory
extension GraphEdge {

    /// Create a new explicit edge from an AtomLink
    static func explicit(
        from sourceUUID: String,
        to targetUUID: String,
        linkType: AtomLinkType
    ) -> GraphEdge {
        let now = ISO8601DateFormatter().string(from: Date())

        return GraphEdge(
            id: nil,
            sourceUUID: sourceUUID,
            targetUUID: targetUUID,
            edgeType: GraphEdgeType.explicit.rawValue,
            linkType: linkType.rawValue,
            isDirected: true,
            structuralWeight: 1.0,
            semanticWeight: 0.0,
            recencyWeight: 1.0,
            usageWeight: 0.0,
            combinedWeight: structuralCoefficient + recencyCoefficient, // Initial combined
            lastComputedAt: now,
            createdAt: now,
            updatedAt: now
        )
    }

    /// Create a new semantic edge from vector similarity
    public static func semantic(
        from sourceUUID: String,
        to targetUUID: String,
        similarity: Float
    ) -> GraphEdge {
        let now = ISO8601DateFormatter().string(from: Date())
        let semanticWeight = Double(similarity)

        return GraphEdge(
            id: nil,
            sourceUUID: sourceUUID,
            targetUUID: targetUUID,
            edgeType: GraphEdgeType.semantic.rawValue,
            linkType: nil,
            isDirected: false, // Semantic edges are bidirectional
            structuralWeight: 0.0,
            semanticWeight: semanticWeight,
            recencyWeight: 1.0,
            usageWeight: 0.0,
            combinedWeight: semanticCoefficient * semanticWeight + recencyCoefficient,
            lastComputedAt: now,
            createdAt: now,
            updatedAt: now
        )
    }

    /// Create a new contextual edge (same project/dimension)
    public static func contextual(
        from sourceUUID: String,
        to targetUUID: String,
        context: String // e.g., project UUID or dimension name
    ) -> GraphEdge {
        let now = ISO8601DateFormatter().string(from: Date())

        return GraphEdge(
            id: nil,
            sourceUUID: sourceUUID,
            targetUUID: targetUUID,
            edgeType: GraphEdgeType.contextual.rawValue,
            linkType: context,
            isDirected: false,
            structuralWeight: 0.7, // Shared context is moderately strong
            semanticWeight: 0.0,
            recencyWeight: 1.0,
            usageWeight: 0.0,
            combinedWeight: structuralCoefficient * 0.7 + recencyCoefficient,
            lastComputedAt: now,
            createdAt: now,
            updatedAt: now
        )
    }

    /// Create a new transitive edge (inferred 2-hop connection)
    public static func transitive(
        from sourceUUID: String,
        to targetUUID: String,
        viaUUID: String,
        inferredWeight: Double
    ) -> GraphEdge {
        let now = ISO8601DateFormatter().string(from: Date())
        let transitiveWeight = inferredWeight * 0.4 // Reduce weight for inferred edges

        return GraphEdge(
            id: nil,
            sourceUUID: sourceUUID,
            targetUUID: targetUUID,
            edgeType: GraphEdgeType.transitive.rawValue,
            linkType: viaUUID, // Store the intermediate node
            isDirected: false,
            structuralWeight: transitiveWeight,
            semanticWeight: 0.0,
            recencyWeight: 1.0,
            usageWeight: 0.0,
            combinedWeight: structuralCoefficient * transitiveWeight + recencyCoefficient,
            lastComputedAt: now,
            createdAt: now,
            updatedAt: now
        )
    }
}

// MARK: - GraphEdge Computed Properties
extension GraphEdge {

    /// The typed edge type (if valid)
    public var type: GraphEdgeType? {
        GraphEdgeType(rawValue: edgeType)
    }

    /// The typed AtomLinkType (if this is an explicit edge)
    var atomLinkType: AtomLinkType? {
        guard let linkType = linkType else { return nil }
        return AtomLinkType(rawValue: linkType)
    }

    /// Whether this is a computed (non-explicit) edge
    public var isComputed: Bool {
        type?.isComputed ?? false
    }

    /// Whether this edge involves a given node
    public func involves(uuid: String) -> Bool {
        sourceUUID == uuid || targetUUID == uuid
    }

    /// Get the "other" node UUID given one side
    public func other(than uuid: String) -> String? {
        if sourceUUID == uuid { return targetUUID }
        if targetUUID == uuid { return sourceUUID }
        return nil
    }

    /// Unique key for deduplication (order-independent for undirected)
    public var deduplicationKey: String {
        if isDirected {
            return "\(sourceUUID):\(targetUUID):\(edgeType)"
        } else {
            let sorted = [sourceUUID, targetUUID].sorted()
            return "\(sorted[0]):\(sorted[1]):\(edgeType)"
        }
    }
}

// MARK: - GraphEdge Weight Calculation
extension GraphEdge {

    /// Compute the combined weight from individual components
    public static func computeCombinedWeight(
        structural: Double,
        semantic: Double,
        recency: Double,
        usage: Double
    ) -> Double {
        let combined = semanticCoefficient * semantic
            + structuralCoefficient * structural
            + recencyCoefficient * recency
            + usageCoefficient * usage

        return max(0.0, min(1.0, combined))
    }

    /// Compute recency weight based on days since last update
    public static func computeRecencyWeight(daysSince: Double) -> Double {
        guard daysSince >= 0 else { return 1.0 }

        // Exponential decay with half-life
        let decay = exp(-log(2.0) * daysSince / recencyHalfLifeDays)
        return max(recencyFloor, decay)
    }

    /// Compute recency weight from a date
    public static func computeRecencyWeight(from date: Date) -> Double {
        let daysSince = Date().timeIntervalSince(date) / 86400.0
        return computeRecencyWeight(daysSince: daysSince)
    }

    /// Create a copy with recomputed weights
    public func recomputingWeights(
        structural: Double? = nil,
        semantic: Double? = nil,
        recency: Double? = nil,
        usage: Double? = nil
    ) -> GraphEdge {
        var copy = self
        let now = ISO8601DateFormatter().string(from: Date())

        if let structural = structural { copy.structuralWeight = structural }
        if let semantic = semantic { copy.semanticWeight = semantic }
        if let recency = recency { copy.recencyWeight = recency }
        if let usage = usage { copy.usageWeight = usage }

        copy.combinedWeight = Self.computeCombinedWeight(
            structural: copy.structuralWeight,
            semantic: copy.semanticWeight,
            recency: copy.recencyWeight,
            usage: copy.usageWeight
        )
        copy.lastComputedAt = now
        copy.updatedAt = now

        return copy
    }

    /// Create a copy with updated semantic weight (from re-embedding)
    public func withSemanticWeight(_ similarity: Float) -> GraphEdge {
        return recomputingWeights(semantic: Double(similarity))
    }

    /// Create a copy with decayed recency
    public func withDecayedRecency(daysSince: Double) -> GraphEdge {
        let newRecency = Self.computeRecencyWeight(daysSince: daysSince)
        return recomputingWeights(recency: newRecency)
    }

    /// Create a copy with boosted usage weight
    public func boostingUsage(by amount: Double = 0.1) -> GraphEdge {
        let newUsage = min(1.0, usageWeight + amount)
        return recomputingWeights(usage: newUsage)
    }
}

// MARK: - GraphEdge Queries
extension GraphEdge {

    /// Column references for type-safe queries
    static let sourceUUIDColumn = Column(CodingKeys.sourceUUID)
    static let targetUUIDColumn = Column(CodingKeys.targetUUID)
    static let edgeTypeColumn = Column(CodingKeys.edgeType)
    static let linkTypeColumn = Column(CodingKeys.linkType)
    static let isDirectedColumn = Column(CodingKeys.isDirected)
    static let combinedWeightColumn = Column(CodingKeys.combinedWeight)
    static let semanticWeightColumn = Column(CodingKeys.semanticWeight)
    static let structuralWeightColumn = Column(CodingKeys.structuralWeight)
    static let recencyWeightColumn = Column(CodingKeys.recencyWeight)
    static let usageWeightColumn = Column(CodingKeys.usageWeight)
    static let lastComputedAtColumn = Column(CodingKeys.lastComputedAt)
    static let createdAtColumn = Column(CodingKeys.createdAt)
    static let updatedAtColumn = Column(CodingKeys.updatedAt)
}

// MARK: - Edge Direction Helper
extension GraphEdge {

    /// Returns both (source, target) and (target, source) for undirected edges
    /// For directed edges, only returns (source, target)
    public var nodePairs: [(source: String, target: String)] {
        if isDirected {
            return [(source: sourceUUID, target: targetUUID)]
        } else {
            return [
                (source: sourceUUID, target: targetUUID),
                (source: targetUUID, target: sourceUUID)
            ]
        }
    }
}
