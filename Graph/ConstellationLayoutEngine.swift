// CosmoOS/Graph/ConstellationLayoutEngine.swift
// Layout engine for NodeGraph OS constellation visualization
// Implements hybrid radial + force-directed positioning

import Foundation
import CoreGraphics

// MARK: - ConstellationLayoutEngine
/// Computes node positions for constellation visualization
/// Uses a hybrid approach: initial radial placement + force-directed refinement
public struct ConstellationLayoutEngine: Sendable {

    // MARK: - Configuration

    /// Radii for degree rings (focus=0, 1st=120, 2nd=220, 3rd=320)
    public static let degreeRadii: [CGFloat] = [0, 120, 220, 320]

    /// Minimum node separation
    public static let nodeSeparation: CGFloat = 80

    /// Number of force-directed iterations
    public static let forceIterations = 10

    /// Force damping factor
    public static let forceDamping: CGFloat = 0.8

    /// Repulsion strength between nodes
    public static let repulsionStrength: CGFloat = 5000

    /// Spring strength for edges
    public static let springStrength: CGFloat = 0.1

    /// Natural spring length
    public static let springLength: CGFloat = 100

    // MARK: - Layout Computation

    /// Compute layout for a constellation centered on a focus node
    /// - Parameters:
    ///   - neighborhood: The neighborhood result from GraphQueryEngine
    ///   - canvasSize: Size of the rendering canvas
    /// - Returns: Dictionary mapping atom UUIDs to positions
    public static func computeLayout(
        neighborhood: NeighborhoodResult,
        canvasSize: CGSize
    ) -> [String: CGPoint] {
        var positions: [String: CGPoint] = [:]
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

        // Phase 1: Place focus node at center
        positions[neighborhood.centerUUID] = center

        // Phase 2: Radial ring placement for each level
        for (level, neighbors) in neighborhood.levels.enumerated() {
            let radius = degreeRadii[min(level + 1, degreeRadii.count - 1)]
            let angleStep = neighbors.isEmpty ? 0 : (2 * .pi) / CGFloat(neighbors.count)

            for (index, neighbor) in neighbors.enumerated() {
                let angle = CGFloat(index) * angleStep - .pi / 2  // Start from top
                let x = center.x + radius * cos(angle)
                let y = center.y + radius * sin(angle)
                positions[neighbor.node.atomUUID] = CGPoint(x: x, y: y)
            }
        }

        // Phase 3: Force-directed refinement
        // Skip focus node (fixed at center)
        let mobileNodes = neighborhood.allUUIDs.filter { $0 != neighborhood.centerUUID }
        positions = applyForceDirected(
            positions: positions,
            mobileNodes: mobileNodes,
            center: center,
            iterations: forceIterations
        )

        return positions
    }

    /// Compute simple circular layout for a list of nodes
    /// - Parameters:
    ///   - nodeUUIDs: The UUIDs of nodes to position
    ///   - center: Center point of the layout
    ///   - radius: Radius of the circle
    /// - Returns: Dictionary mapping atom UUIDs to positions
    public static func computeCircularLayout(
        nodeUUIDs: [String],
        center: CGPoint,
        radius: CGFloat
    ) -> [String: CGPoint] {
        var positions: [String: CGPoint] = [:]
        let angleStep = nodeUUIDs.isEmpty ? 0 : (2 * .pi) / CGFloat(nodeUUIDs.count)

        for (index, uuid) in nodeUUIDs.enumerated() {
            let angle = CGFloat(index) * angleStep - .pi / 2
            let x = center.x + radius * cos(angle)
            let y = center.y + radius * sin(angle)
            positions[uuid] = CGPoint(x: x, y: y)
        }

        return positions
    }

    // MARK: - Force-Directed Algorithm

    /// Apply force-directed layout refinement
    private static func applyForceDirected(
        positions: [String: CGPoint],
        mobileNodes: [String],
        center: CGPoint,
        iterations: Int
    ) -> [String: CGPoint] {
        var currentPositions = positions
        var velocities: [String: CGPoint] = [:]

        for uuid in mobileNodes {
            velocities[uuid] = .zero
        }

        for _ in 0..<iterations {
            var forces: [String: CGPoint] = [:]
            for uuid in mobileNodes {
                forces[uuid] = .zero
            }

            // Calculate repulsion forces between all node pairs
            for i in 0..<mobileNodes.count {
                for j in (i + 1)..<mobileNodes.count {
                    let uuid1 = mobileNodes[i]
                    let uuid2 = mobileNodes[j]

                    guard let pos1 = currentPositions[uuid1],
                          let pos2 = currentPositions[uuid2] else { continue }

                    let delta = CGPoint(x: pos2.x - pos1.x, y: pos2.y - pos1.y)
                    let distance = max(1, sqrt(delta.x * delta.x + delta.y * delta.y))

                    // Coulomb repulsion
                    let repulsion = repulsionStrength / (distance * distance)
                    let normalized = CGPoint(x: delta.x / distance, y: delta.y / distance)

                    forces[uuid1]!.x -= normalized.x * repulsion
                    forces[uuid1]!.y -= normalized.y * repulsion
                    forces[uuid2]!.x += normalized.x * repulsion
                    forces[uuid2]!.y += normalized.y * repulsion
                }
            }

            // Calculate spring forces toward center (to maintain structure)
            for uuid in mobileNodes {
                guard let pos = currentPositions[uuid] else { continue }

                let delta = CGPoint(x: center.x - pos.x, y: center.y - pos.y)
                let distance = sqrt(delta.x * delta.x + delta.y * delta.y)

                if distance > springLength {
                    let attraction = springStrength * (distance - springLength)
                    forces[uuid]!.x += (delta.x / distance) * attraction
                    forces[uuid]!.y += (delta.y / distance) * attraction
                }
            }

            // Apply forces with damping
            for uuid in mobileNodes {
                guard let force = forces[uuid],
                      let velocity = velocities[uuid],
                      var position = currentPositions[uuid] else { continue }

                var newVelocity = CGPoint(
                    x: (velocity.x + force.x) * forceDamping,
                    y: (velocity.y + force.y) * forceDamping
                )

                // Clamp velocity
                let maxVelocity: CGFloat = 50
                let speed = sqrt(newVelocity.x * newVelocity.x + newVelocity.y * newVelocity.y)
                if speed > maxVelocity {
                    newVelocity.x *= maxVelocity / speed
                    newVelocity.y *= maxVelocity / speed
                }

                position.x += newVelocity.x
                position.y += newVelocity.y

                velocities[uuid] = newVelocity
                currentPositions[uuid] = position
            }
        }

        // Post-process: ensure minimum separation
        currentPositions = ensureMinimumSeparation(
            positions: currentPositions,
            mobileNodes: mobileNodes,
            minDistance: nodeSeparation
        )

        return currentPositions
    }

    /// Ensure minimum separation between nodes
    private static func ensureMinimumSeparation(
        positions: [String: CGPoint],
        mobileNodes: [String],
        minDistance: CGFloat
    ) -> [String: CGPoint] {
        var currentPositions = positions

        for _ in 0..<5 {  // Multiple passes
            for i in 0..<mobileNodes.count {
                for j in (i + 1)..<mobileNodes.count {
                    let uuid1 = mobileNodes[i]
                    let uuid2 = mobileNodes[j]

                    guard var pos1 = currentPositions[uuid1],
                          var pos2 = currentPositions[uuid2] else { continue }

                    let delta = CGPoint(x: pos2.x - pos1.x, y: pos2.y - pos1.y)
                    let distance = sqrt(delta.x * delta.x + delta.y * delta.y)

                    if distance < minDistance && distance > 0 {
                        let overlap = (minDistance - distance) / 2
                        let normalized = CGPoint(x: delta.x / distance, y: delta.y / distance)

                        pos1.x -= normalized.x * overlap
                        pos1.y -= normalized.y * overlap
                        pos2.x += normalized.x * overlap
                        pos2.y += normalized.y * overlap

                        currentPositions[uuid1] = pos1
                        currentPositions[uuid2] = pos2
                    }
                }
            }
        }

        return currentPositions
    }

    // MARK: - Animation Support

    /// Interpolate between two layouts
    /// - Parameters:
    ///   - from: Starting positions
    ///   - to: Target positions
    ///   - progress: Animation progress (0.0-1.0)
    /// - Returns: Interpolated positions
    public static func interpolate(
        from: [String: CGPoint],
        to: [String: CGPoint],
        progress: CGFloat
    ) -> [String: CGPoint] {
        var result: [String: CGPoint] = [:]

        // Ease function (ease-out cubic)
        let easedProgress = 1 - pow(1 - progress, 3)

        for (uuid, toPoint) in to {
            if let fromPoint = from[uuid] {
                result[uuid] = CGPoint(
                    x: fromPoint.x + (toPoint.x - fromPoint.x) * easedProgress,
                    y: fromPoint.y + (toPoint.y - fromPoint.y) * easedProgress
                )
            } else {
                // New node - fade in from center
                result[uuid] = toPoint
            }
        }

        return result
    }

    // MARK: - Node Sizing

    /// Calculate node size based on relevance/importance
    /// - Parameters:
    ///   - pageRank: Node's PageRank score (0.0-1.0)
    ///   - degree: Node's total degree
    ///   - isSelected: Whether the node is selected
    ///   - isHovered: Whether the node is hovered
    /// - Returns: Node radius in points
    public static func nodeSize(
        pageRank: Double,
        degree: Int,
        isSelected: Bool = false,
        isHovered: Bool = false
    ) -> CGFloat {
        let minSize: CGFloat = 24
        let maxSize: CGFloat = 72

        // Base size from PageRank
        var size = minSize + CGFloat(pageRank) * (maxSize - minSize) * 0.6

        // Boost from degree (capped)
        let degreeBoost = CGFloat(min(degree, 10)) / 10.0 * 10
        size += degreeBoost

        // State multipliers
        if isSelected {
            size *= 1.2
        } else if isHovered {
            size *= 1.1
        }

        return min(maxSize, max(minSize, size))
    }

    // MARK: - Edge Rendering Support

    /// Calculate bezier curve control point for edge
    /// - Parameters:
    ///   - from: Start point
    ///   - to: End point
    /// - Returns: Control point for quadratic bezier
    public static func edgeControlPoint(from: CGPoint, to: CGPoint) -> CGPoint {
        let midpoint = CGPoint(
            x: (from.x + to.x) / 2,
            y: (from.y + to.y) / 2
        )

        let distance = sqrt(pow(to.x - from.x, 2) + pow(to.y - from.y, 2))
        let curveAmount = min(distance * 0.3, 80)

        // Perpendicular offset
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = sqrt(dx * dx + dy * dy)

        guard length > 0 else { return midpoint }

        let perpX = -dy / length * curveAmount
        let perpY = dx / length * curveAmount

        return CGPoint(
            x: midpoint.x + perpX,
            y: midpoint.y + perpY
        )
    }
}

// MARK: - ConstellationNode
/// Represents a node in the constellation with computed visual properties
public struct ConstellationNode: Identifiable, Sendable {
    public let id: String
    public let atomUUID: String
    public let atomType: AtomType
    public let title: String

    public var position: CGPoint
    public var radius: CGFloat
    public var glowIntensity: CGFloat  // From relevance (0.0-1.0)

    public var isSelected: Bool = false
    public var isHovered: Bool = false

    /// Color based on dimension
    public var dimensionColor: String {
        switch atomType.category {
        case .core:
            return "#6366F1"  // Cognitive (Indigo)
        case .contentPipeline:
            return "#F59E0B"  // Creative (Amber)
        case .knowledge:
            return "#8B5CF6"  // Knowledge (Purple)
        case .reflection:
            return "#EC4899"  // Reflection (Pink)
        case .cognitive:
            return "#3B82F6"  // Behavioral (Blue)
        case .physiology:
            return "#10B981"  // Physiological (Teal)
        case .leveling, .system, .sanctuary:
            return "#6366F1"  // Default
        }
    }

    public init(
        atomUUID: String,
        atomType: AtomType,
        title: String,
        position: CGPoint,
        pageRank: Double,
        degree: Int
    ) {
        self.id = atomUUID
        self.atomUUID = atomUUID
        self.atomType = atomType
        self.title = title
        self.position = position
        self.radius = ConstellationLayoutEngine.nodeSize(pageRank: pageRank, degree: degree)
        self.glowIntensity = CGFloat(pageRank)
    }
}

// MARK: - ConstellationEdge
/// Represents an edge in the constellation with visual properties
public struct ConstellationEdge: Identifiable, Sendable {
    public let id: String
    public let sourceUUID: String
    public let targetUUID: String
    public let weight: Double
    public let edgeType: GraphEdgeType

    public var sourcePosition: CGPoint
    public var targetPosition: CGPoint
    public var controlPoint: CGPoint

    /// Line width based on weight
    public var lineWidth: CGFloat {
        if weight < 0.3 { return 1.0 }
        if weight < 0.6 { return 1.5 }
        if weight < 0.8 { return 2.0 }
        return 2.5
    }

    /// Opacity based on weight
    public var opacity: CGFloat {
        if weight < 0.3 { return 0.2 }
        if weight < 0.6 { return 0.4 }
        if weight < 0.8 { return 0.6 }
        return 0.8
    }

    /// Animation speed multiplier based on weight
    public var flowSpeed: CGFloat {
        if weight < 0.3 { return 0.5 }
        if weight < 0.6 { return 1.0 }
        if weight < 0.8 { return 1.5 }
        return 2.0
    }

    public init(
        sourceUUID: String,
        targetUUID: String,
        weight: Double,
        edgeType: GraphEdgeType,
        sourcePosition: CGPoint,
        targetPosition: CGPoint
    ) {
        self.id = "\(sourceUUID):\(targetUUID)"
        self.sourceUUID = sourceUUID
        self.targetUUID = targetUUID
        self.weight = weight
        self.edgeType = edgeType
        self.sourcePosition = sourcePosition
        self.targetPosition = targetPosition
        self.controlPoint = ConstellationLayoutEngine.edgeControlPoint(
            from: sourcePosition,
            to: targetPosition
        )
    }
}
