// CosmoOS/Graph/WeightCalculator.swift
// Relevance weight calculation for NodeGraph OS
// Implements the 4-component formula: 0.55*semantic + 0.25*structural + 0.10*recency + 0.10*usage

import Foundation

// MARK: - WeightCalculator
/// Calculates relevance weights for graph edges and search results
/// Formula: TOTAL = 0.55×semantic + 0.25×structural + 0.10×recency + 0.10×usage
public struct WeightCalculator: Sendable {

    // MARK: - Coefficients
    /// Weight coefficients (must sum to 1.0)
    public static let coefficients = WeightCoefficients(
        semantic: 0.55,
        structural: 0.25,
        recency: 0.10,
        usage: 0.10
    )

    // MARK: - Recency Configuration
    /// Half-life for recency decay in days
    public static let recencyHalfLifeDays: Double = 7.0

    /// Minimum recency weight (floor)
    public static let recencyFloor: Double = 0.1

    /// Boost for items updated today
    public static let todayBoost: Double = 1.0

    // MARK: - Structural Weight Values
    /// Predefined structural weights by relationship type
    public static let structuralWeights = StructuralWeights(
        explicitLink: 1.0,      // Direct AtomLink
        sharedProject: 0.7,     // Same project
        canvasProximity: 0.6,   // Near on canvas (base, multiplied by distance decay)
        transitive: 0.4,        // 2-hop inference
        sharedConcepts: 0.35,   // Common keywords/tags
        sameCategory: 0.3,      // Same AtomCategory
        sameDimension: 0.25     // Same Sanctuary dimension
    )

    // MARK: - Combined Weight Calculation

    /// Calculate combined relevance weight from components
    /// - Parameters:
    ///   - semantic: Semantic similarity (0.0-1.0)
    ///   - structural: Structural relevance (0.0-1.0)
    ///   - recency: Recency decay factor (0.0-1.0)
    ///   - usage: Usage frequency factor (0.0-1.0)
    /// - Returns: Combined weight clamped to 0.0-1.0
    public static func combine(
        semantic: Double,
        structural: Double,
        recency: Double,
        usage: Double
    ) -> Double {
        let combined = coefficients.semantic * clamp(semantic)
            + coefficients.structural * clamp(structural)
            + coefficients.recency * clamp(recency)
            + coefficients.usage * clamp(usage)

        return clamp(combined)
    }

    /// Calculate combined weight from a WeightComponents struct
    public static func combine(_ components: WeightComponents) -> Double {
        return combine(
            semantic: components.semantic,
            structural: components.structural,
            recency: components.recency,
            usage: components.usage
        )
    }

    // MARK: - Semantic Weight

    /// Convert vector similarity to semantic weight
    /// - Parameter similarity: Cosine similarity from VectorDatabase (0.0-1.0)
    /// - Returns: Semantic weight (direct mapping, already normalized)
    public static func semanticWeight(from similarity: Float) -> Double {
        return clamp(Double(similarity))
    }

    /// Calculate semantic weight from BM25 score (fallback)
    /// - Parameter bm25Score: BM25 score from FTS5
    /// - Returns: Normalized semantic weight (score / 25.0, clamped)
    public static func semanticWeight(fromBM25 bm25Score: Double) -> Double {
        // BM25 scores typically range 0-25+ for good matches
        // Normalize to 0-1 range
        return clamp(bm25Score / 25.0)
    }

    // MARK: - Structural Weight

    /// Calculate structural weight from relationship type
    /// - Parameter relationshipType: The type of relationship
    /// - Returns: Structural weight based on predefined values
    public static func structuralWeight(for relationshipType: StructuralRelationType) -> Double {
        switch relationshipType {
        case .explicitLink:
            return structuralWeights.explicitLink
        case .sharedProject:
            return structuralWeights.sharedProject
        case .canvasProximity(let distance):
            return structuralWeights.canvasProximity * canvasDistanceDecay(distance)
        case .transitive:
            return structuralWeights.transitive
        case .sharedConcepts(let count):
            return min(structuralWeights.sharedConcepts * Double(count), 1.0)
        case .sameCategory:
            return structuralWeights.sameCategory
        case .sameDimension:
            return structuralWeights.sameDimension
        case .none:
            return 0.0
        }
    }

    /// Calculate structural weight from AtomLinkType
    static func structuralWeight(for linkType: AtomLinkType) -> Double {
        switch linkType {
        // Core structural links (highest weight)
        case .project, .parentIdea:
            return structuralWeights.explicitLink
        // Direct references (high weight)
        case .connection, .originIdea, .promotedTo:
            return structuralWeights.explicitLink * 0.9
        // Content pipeline links (medium-high)
        case .writingToContent, .draftToContent, .contentToClient, .clientContent,
             .publishSource, .performanceOf:
            return structuralWeights.explicitLink * 0.85
        // Task and work-related links (medium)
        case .deepWorkTask, .deepWorkProject, .routineInstance, .focusToDeepWork,
             .recurrenceParent:
            return structuralWeights.explicitLink * 0.8
        // Reflection links (lower weight)
        case .journalSource, .clarityOf, .reflectionSession, .analysisSource,
             .emotionalContext:
            return structuralWeights.explicitLink * 0.7
        // Knowledge graph semantic links (conceptual weight)
        case .semanticCluster, .semanticMember, .conceptLink, .autoLinkSource,
             .autoLinkTarget, .insightSource:
            return structuralWeights.sharedConcepts
        // Transitive/generic links (lower weight)
        case .related, .linksTo, .linkedFrom:
            return structuralWeights.transitive
        // Default for all other link types
        default:
            return structuralWeights.explicitLink * 0.75
        }
    }

    /// Canvas distance decay function
    /// - Parameter distance: Distance in canvas units
    /// - Returns: Decay factor (1.0 at 0, approaching 0 at infinity)
    private static func canvasDistanceDecay(_ distance: Double) -> Double {
        // Exponential decay with characteristic distance of 500 units
        let characteristicDistance: Double = 500
        return exp(-distance / characteristicDistance)
    }

    // MARK: - Recency Weight

    /// Calculate recency weight from days since update
    /// - Parameter daysSince: Number of days since last update
    /// - Returns: Recency weight (exponential decay with floor)
    public static func recencyWeight(daysSince: Double) -> Double {
        guard daysSince >= 0 else { return todayBoost }

        // Items updated today get full boost
        if daysSince < 1 {
            return todayBoost
        }

        // Exponential decay: exp(-ln(2) * days / half_life)
        let decay = exp(-log(2.0) * daysSince / recencyHalfLifeDays)
        return max(recencyFloor, decay)
    }

    /// Calculate recency weight from a date
    public static func recencyWeight(from date: Date) -> Double {
        let daysSince = Date().timeIntervalSince(date) / 86400.0
        return recencyWeight(daysSince: daysSince)
    }

    /// Calculate recency weight from ISO8601 string
    public static func recencyWeight(fromISO8601 dateString: String) -> Double {
        guard let date = ISO8601DateFormatter().date(from: dateString) else {
            return recencyFloor
        }
        return recencyWeight(from: date)
    }

    // MARK: - Usage Weight

    /// Calculate usage weight from access events
    /// - Parameters:
    ///   - viewCount: Number of view events
    ///   - editCount: Number of edit events
    ///   - searchCount: Number of search result clicks
    ///   - referenceCount: Number of times referenced from other atoms
    /// - Returns: Usage weight (sigmoid normalized)
    public static func usageWeight(
        viewCount: Int,
        editCount: Int,
        searchCount: Int,
        referenceCount: Int
    ) -> Double {
        // Weighted sum of access types
        let weightedSum =
            Double(viewCount) * 0.5 +
            Double(editCount) * 1.0 +
            Double(searchCount) * 0.3 +
            Double(referenceCount) * 0.7

        // Sigmoid normalization centered at 3
        // sigmoid(x - 3) maps: 0 -> 0.05, 3 -> 0.5, 10 -> 0.999
        return sigmoid(weightedSum - 3.0)
    }

    /// Calculate usage weight from simple access count
    /// - Parameter accessCount: Total access count
    /// - Returns: Usage weight (log-scaled)
    public static func usageWeight(accessCount: Int) -> Double {
        guard accessCount > 0 else { return 0.0 }

        // Logarithmic scaling to prevent outlier dominance
        // log(1 + count) / log(1 + 100) normalizes ~100 accesses to ~1.0
        let normalized = log(1.0 + Double(accessCount)) / log(101.0)
        return clamp(normalized)
    }

    // MARK: - Helper Functions

    /// Clamp value to 0.0-1.0 range
    private static func clamp(_ value: Double) -> Double {
        return max(0.0, min(1.0, value))
    }

    /// Sigmoid function
    private static func sigmoid(_ x: Double) -> Double {
        return 1.0 / (1.0 + exp(-x))
    }
}

// MARK: - Supporting Types

/// Weight coefficients for the relevance formula
public struct WeightCoefficients: Sendable {
    public let semantic: Double
    public let structural: Double
    public let recency: Double
    public let usage: Double

    public init(semantic: Double, structural: Double, recency: Double, usage: Double) {
        // Validate sum equals 1.0 (with tolerance for floating point)
        let sum = semantic + structural + recency + usage
        assert(abs(sum - 1.0) < 0.001, "Weight coefficients must sum to 1.0")

        self.semantic = semantic
        self.structural = structural
        self.recency = recency
        self.usage = usage
    }
}

/// Individual weight components before combination
public struct WeightComponents: Sendable {
    public var semantic: Double
    public var structural: Double
    public var recency: Double
    public var usage: Double

    public init(
        semantic: Double = 0.0,
        structural: Double = 0.0,
        recency: Double = 1.0,
        usage: Double = 0.0
    ) {
        self.semantic = semantic
        self.structural = structural
        self.recency = recency
        self.usage = usage
    }

    /// Calculate combined weight
    public var combined: Double {
        WeightCalculator.combine(self)
    }
}

/// Predefined structural weight values
public struct StructuralWeights: Sendable {
    public let explicitLink: Double
    public let sharedProject: Double
    public let canvasProximity: Double
    public let transitive: Double
    public let sharedConcepts: Double
    public let sameCategory: Double
    public let sameDimension: Double

    public init(
        explicitLink: Double,
        sharedProject: Double,
        canvasProximity: Double,
        transitive: Double,
        sharedConcepts: Double,
        sameCategory: Double,
        sameDimension: Double
    ) {
        self.explicitLink = explicitLink
        self.sharedProject = sharedProject
        self.canvasProximity = canvasProximity
        self.transitive = transitive
        self.sharedConcepts = sharedConcepts
        self.sameCategory = sameCategory
        self.sameDimension = sameDimension
    }
}

/// Types of structural relationships
public enum StructuralRelationType: Sendable {
    case explicitLink
    case sharedProject
    case canvasProximity(distance: Double)
    case transitive
    case sharedConcepts(count: Int)
    case sameCategory
    case sameDimension
    case none
}

// MARK: - Ranked Result

/// A search result with relevance scoring breakdown
public struct RankedResult: Identifiable, Sendable {
    public let id: String
    public let atomUUID: String
    public let atomType: AtomType
    public let title: String
    public let snippet: String?

    // Weight components
    public let semanticWeight: Double
    public let structuralWeight: Double
    public let recencyWeight: Double
    public let usageWeight: Double

    // Combined relevance
    public let relevance: Double

    // Metadata
    public let updatedAt: String
    public let accessCount: Int

    public init(
        atomUUID: String,
        atomType: AtomType,
        title: String,
        snippet: String? = nil,
        semanticWeight: Double = 0.0,
        structuralWeight: Double = 0.0,
        recencyWeight: Double = 1.0,
        usageWeight: Double = 0.0,
        updatedAt: String,
        accessCount: Int = 0
    ) {
        self.id = atomUUID
        self.atomUUID = atomUUID
        self.atomType = atomType
        self.title = title
        self.snippet = snippet
        self.semanticWeight = semanticWeight
        self.structuralWeight = structuralWeight
        self.recencyWeight = recencyWeight
        self.usageWeight = usageWeight
        self.relevance = WeightCalculator.combine(
            semantic: semanticWeight,
            structural: structuralWeight,
            recency: recencyWeight,
            usage: usageWeight
        )
        self.updatedAt = updatedAt
        self.accessCount = accessCount
    }

    /// Relevance as percentage (0-100)
    public var relevancePercent: Int {
        Int(relevance * 100)
    }
}

// MARK: - Tie-Breaking

extension RankedResult: Comparable {
    /// Compare results for ranking with tie-breaking
    /// Order: relevance (desc) → recency (desc) → type priority → alphabetical → ID
    public static func < (lhs: RankedResult, rhs: RankedResult) -> Bool {
        // Primary: relevance (higher is better)
        if abs(lhs.relevance - rhs.relevance) > 0.001 {
            return lhs.relevance > rhs.relevance
        }

        // Secondary: recency (more recent is better)
        if abs(lhs.recencyWeight - rhs.recencyWeight) > 0.001 {
            return lhs.recencyWeight > rhs.recencyWeight
        }

        // Tertiary: type priority
        let lhsPriority = typePriority(lhs.atomType)
        let rhsPriority = typePriority(rhs.atomType)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority // Lower number = higher priority
        }

        // Quaternary: alphabetical by title
        if lhs.title != rhs.title {
            return lhs.title < rhs.title
        }

        // Final: stable ID ordering
        return lhs.atomUUID < rhs.atomUUID
    }

    /// Type priority for tie-breaking (lower = higher priority)
    private static func typePriority(_ type: AtomType) -> Int {
        switch type {
        case .task: return 1
        case .idea: return 2
        case .content: return 3
        case .research: return 4
        case .connection: return 5
        case .project: return 6
        default: return 10
        }
    }
}
