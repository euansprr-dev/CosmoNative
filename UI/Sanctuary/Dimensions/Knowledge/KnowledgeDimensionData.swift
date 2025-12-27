// CosmoOS/UI/Sanctuary/Dimensions/Knowledge/KnowledgeDimensionData.swift
// Data Models - Knowledge graph and semantic constellation structures
// Phase 7: Following SANCTUARY_UI_SPEC_V2.md section 3.5

import SwiftUI

// MARK: - Node Type

public enum NodeType: String, Codable, Sendable, CaseIterable {
    case concept
    case paper
    case idea
    case bookmark
    case note

    public var displayName: String {
        switch self {
        case .concept: return "Concept"
        case .paper: return "Paper"
        case .idea: return "Idea"
        case .bookmark: return "Bookmark"
        case .note: return "Note"
        }
    }

    public var iconName: String {
        switch self {
        case .concept: return "cube.fill"
        case .paper: return "doc.text.fill"
        case .idea: return "lightbulb.fill"
        case .bookmark: return "bookmark.fill"
        case .note: return "note.text"
        }
    }

    public var color: String {
        switch self {
        case .concept: return "#8B5CF6"
        case .paper: return "#3B82F6"
        case .idea: return "#F59E0B"
        case .bookmark: return "#10B981"
        case .note: return "#6B7280"
        }
    }
}

// MARK: - Edge Type

public enum EdgeType: String, Codable, Sendable {
    case semantic
    case manual
    case citation
    case temporal

    public var displayName: String {
        switch self {
        case .semantic: return "Semantic"
        case .manual: return "Manual"
        case .citation: return "Citation"
        case .temporal: return "Temporal"
        }
    }
}

// MARK: - Capture Type

public enum CaptureType: String, Codable, Sendable, CaseIterable {
    case paper
    case idea
    case bookmark
    case note
    case highlight

    public var displayName: String {
        switch self {
        case .paper: return "Paper"
        case .idea: return "Idea"
        case .bookmark: return "Bookmark"
        case .note: return "Note"
        case .highlight: return "Highlight"
        }
    }

    public var iconName: String {
        switch self {
        case .paper: return "doc.text.fill"
        case .idea: return "lightbulb.fill"
        case .bookmark: return "link"
        case .note: return "note.text"
        case .highlight: return "highlighter"
        }
    }

    public var emoji: String {
        switch self {
        case .paper: return "📄"
        case .idea: return "💡"
        case .bookmark: return "🔗"
        case .note: return "📝"
        case .highlight: return "✨"
        }
    }
}

// MARK: - Cluster Status

public enum ClusterStatus: String, Codable, Sendable {
    case growing
    case stable
    case dormant
    case emerging

    public var displayName: String {
        switch self {
        case .growing: return "Growing"
        case .stable: return "Stable"
        case .dormant: return "Dormant"
        case .emerging: return "Emerging"
        }
    }

    public var color: Color {
        switch self {
        case .growing: return SanctuaryColors.Semantic.success
        case .stable: return SanctuaryColors.Semantic.info
        case .dormant: return SanctuaryColors.Text.tertiary
        case .emerging: return SanctuaryColors.XP.primary
        }
    }
}

// MARK: - Knowledge Node

public struct KnowledgeNode: Identifiable, Codable, Sendable {
    public let id: UUID
    public let title: String
    public let type: NodeType
    public let clusterID: UUID?
    public let createdDate: Date
    public let lastAccessedDate: Date
    public let accessCount: Int
    public let notes: [String]
    public let tags: [String]

    public init(
        id: UUID = UUID(),
        title: String,
        type: NodeType,
        clusterID: UUID? = nil,
        createdDate: Date,
        lastAccessedDate: Date,
        accessCount: Int,
        notes: [String] = [],
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.clusterID = clusterID
        self.createdDate = createdDate
        self.lastAccessedDate = lastAccessedDate
        self.accessCount = accessCount
        self.notes = notes
        self.tags = tags
    }

    public var isActive: Bool {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return lastAccessedDate > sevenDaysAgo
    }

    public var daysSinceAccess: Int {
        Calendar.current.dateComponents([.day], from: lastAccessedDate, to: Date()).day ?? 0
    }
}

// MARK: - Knowledge Edge

public struct KnowledgeEdge: Identifiable, Codable, Sendable {
    public let id: UUID
    public let sourceNodeID: UUID
    public let targetNodeID: UUID
    public let strength: Double
    public let edgeType: EdgeType
    public let createdDate: Date
    public let description: String?

    public init(
        id: UUID = UUID(),
        sourceNodeID: UUID,
        targetNodeID: UUID,
        strength: Double,
        edgeType: EdgeType,
        createdDate: Date,
        description: String? = nil
    ) {
        self.id = id
        self.sourceNodeID = sourceNodeID
        self.targetNodeID = targetNodeID
        self.strength = min(1, max(0, strength))
        self.edgeType = edgeType
        self.createdDate = createdDate
        self.description = description
    }

    public var strengthLabel: String {
        if strength >= 0.8 { return "Strong" }
        if strength >= 0.5 { return "Medium" }
        return "Weak"
    }
}

// MARK: - Knowledge Cluster

public struct KnowledgeCluster: Identifiable, Codable, Sendable {
    public let id: UUID
    public let name: String
    public let nodeIDs: [UUID]
    public let density: Double
    public let colorHex: String
    public let lastActivityDate: Date
    public let growthRate: Double
    public let status: ClusterStatus

    public init(
        id: UUID = UUID(),
        name: String,
        nodeIDs: [UUID],
        density: Double,
        colorHex: String,
        lastActivityDate: Date,
        growthRate: Double,
        status: ClusterStatus
    ) {
        self.id = id
        self.name = name
        self.nodeIDs = nodeIDs
        self.density = min(1, max(0, density))
        self.colorHex = colorHex
        self.lastActivityDate = lastActivityDate
        self.growthRate = growthRate
        self.status = status
    }

    public var nodeCount: Int { nodeIDs.count }

    public var isDormant: Bool {
        let fourteenDaysAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        return lastActivityDate < fourteenDaysAgo
    }

    public var daysSinceActivity: Int {
        Calendar.current.dateComponents([.day], from: lastActivityDate, to: Date()).day ?? 0
    }
}

// MARK: - Knowledge Capture

public struct KnowledgeCapture: Identifiable, Codable, Sendable {
    public let id: UUID
    public let title: String
    public let type: CaptureType
    public let timestamp: Date
    public let tags: [String]
    public let connectionCount: Int
    public let sourceURL: String?
    public let preview: String

    public init(
        id: UUID = UUID(),
        title: String,
        type: CaptureType,
        timestamp: Date,
        tags: [String],
        connectionCount: Int,
        sourceURL: String? = nil,
        preview: String
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.timestamp = timestamp
        self.tags = tags
        self.connectionCount = connectionCount
        self.sourceURL = sourceURL
        self.preview = preview
    }

    public var timeAgo: String {
        let interval = Date().timeIntervalSince(timestamp)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60)) min ago" }
        if interval < 86400 { return "\(Int(interval / 3600)) hours ago" }
        return "\(Int(interval / 86400)) days ago"
    }
}

// MARK: - Stamina Factor

public struct StaminaFactor: Identifiable, Codable, Sendable {
    public let id: UUID
    public let name: String
    public let impact: Double
    public let isPositive: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        impact: Double,
        isPositive: Bool
    ) {
        self.id = id
        self.name = name
        self.impact = impact
        self.isPositive = isPositive
    }

    public var impactString: String {
        "\(isPositive ? "+" : "-")\(Int(abs(impact)))%"
    }
}

// MARK: - Emerging Connection

public struct EmergingConnection: Identifiable, Codable, Sendable {
    public let id: UUID
    public let sourceCluster: String
    public let targetCluster: String
    public let strength: Double
    public let description: String

    public init(
        id: UUID = UUID(),
        sourceCluster: String,
        targetCluster: String,
        strength: Double,
        description: String
    ) {
        self.id = id
        self.sourceCluster = sourceCluster
        self.targetCluster = targetCluster
        self.strength = min(1, max(0, strength))
        self.description = description
    }
}

// MARK: - Hourly Research

public struct HourlyResearch: Identifiable, Codable, Sendable {
    public let id: UUID
    public let hour: Int
    public let minutes: Int
    public let isActive: Bool

    public init(
        id: UUID = UUID(),
        hour: Int,
        minutes: Int,
        isActive: Bool = false
    ) {
        self.id = id
        self.hour = hour
        self.minutes = minutes
        self.isActive = isActive
    }

    public var intensity: Double {
        min(1, Double(minutes) / 60)
    }
}

// MARK: - Daily Research

public struct DailyResearch: Identifiable, Codable, Sendable {
    public let id: UUID
    public let dayOfWeek: String
    public let totalMinutes: Int

    public init(
        id: UUID = UUID(),
        dayOfWeek: String,
        totalMinutes: Int
    ) {
        self.id = id
        self.dayOfWeek = dayOfWeek
        self.totalMinutes = totalMinutes
    }

    public var formattedTime: String {
        let hours = totalMinutes / 60
        let mins = totalMinutes % 60
        return "\(hours)h\(mins > 0 ? "\(mins)m" : "")"
    }
}

// MARK: - Knowledge Prediction

public struct KnowledgePrediction: Identifiable, Codable, Sendable {
    public let id: UUID
    public let condition: String
    public let prediction: String
    public let confidence: Double
    public let suggestedExploration: String?
    public let actions: [String]

    public init(
        id: UUID = UUID(),
        condition: String,
        prediction: String,
        confidence: Double,
        suggestedExploration: String? = nil,
        actions: [String]
    ) {
        self.id = id
        self.condition = condition
        self.prediction = prediction
        self.confidence = min(1, max(0, confidence))
        self.suggestedExploration = suggestedExploration
        self.actions = actions
    }
}

// MARK: - Node Position (for constellation)

public struct NodePosition: Identifiable, Codable, Sendable {
    public let id: UUID
    public let nodeID: UUID
    public let x: Double
    public let y: Double
    public let z: Double

    public init(
        id: UUID = UUID(),
        nodeID: UUID,
        x: Double,
        y: Double,
        z: Double
    ) {
        self.id = id
        self.nodeID = nodeID
        self.x = x
        self.y = y
        self.z = z
    }
}

// MARK: - Knowledge Dimension Data

public struct KnowledgeDimensionData: Codable, Sendable {
    // Flow Metrics
    public let capturesToday: Int
    public let capturesChange: Int
    public let processedToday: Int
    public let connectionsToday: Int
    public let semanticDensity: Double

    // Constellation Graph
    public let nodes: [KnowledgeNode]
    public let edges: [KnowledgeEdge]
    public let clusters: [KnowledgeCluster]
    public let nodePositions: [NodePosition]

    // Research Activity
    public let researchTimeline: [HourlyResearch]
    public let peakResearchHour: Int
    public let peakResearchMinutes: Int
    public let totalResearchToday: Int
    public let weeklyResearchData: [DailyResearch]
    public let weeklyTotalMinutes: Int

    // Knowledge Stamina
    public let knowledgeStamina: Double
    public let optimalWindowStart: Int
    public let optimalWindowEnd: Int
    public let rechargeNeededMinutes: Int
    public let staminaFactors: [StaminaFactor]

    // Recent Captures
    public let recentCaptures: [KnowledgeCapture]

    // Cluster Insights
    public let growingClusters: [KnowledgeCluster]
    public let dormantClusters: [KnowledgeCluster]
    public let emergingLinks: [EmergingConnection]

    // Predictions
    public let predictions: [KnowledgePrediction]

    public init(
        capturesToday: Int,
        capturesChange: Int,
        processedToday: Int,
        connectionsToday: Int,
        semanticDensity: Double,
        nodes: [KnowledgeNode],
        edges: [KnowledgeEdge],
        clusters: [KnowledgeCluster],
        nodePositions: [NodePosition],
        researchTimeline: [HourlyResearch],
        peakResearchHour: Int,
        peakResearchMinutes: Int,
        totalResearchToday: Int,
        weeklyResearchData: [DailyResearch],
        weeklyTotalMinutes: Int,
        knowledgeStamina: Double,
        optimalWindowStart: Int,
        optimalWindowEnd: Int,
        rechargeNeededMinutes: Int,
        staminaFactors: [StaminaFactor],
        recentCaptures: [KnowledgeCapture],
        growingClusters: [KnowledgeCluster],
        dormantClusters: [KnowledgeCluster],
        emergingLinks: [EmergingConnection],
        predictions: [KnowledgePrediction]
    ) {
        self.capturesToday = capturesToday
        self.capturesChange = capturesChange
        self.processedToday = processedToday
        self.connectionsToday = connectionsToday
        self.semanticDensity = semanticDensity
        self.nodes = nodes
        self.edges = edges
        self.clusters = clusters
        self.nodePositions = nodePositions
        self.researchTimeline = researchTimeline
        self.peakResearchHour = peakResearchHour
        self.peakResearchMinutes = peakResearchMinutes
        self.totalResearchToday = totalResearchToday
        self.weeklyResearchData = weeklyResearchData
        self.weeklyTotalMinutes = weeklyTotalMinutes
        self.knowledgeStamina = knowledgeStamina
        self.optimalWindowStart = optimalWindowStart
        self.optimalWindowEnd = optimalWindowEnd
        self.rechargeNeededMinutes = rechargeNeededMinutes
        self.staminaFactors = staminaFactors
        self.recentCaptures = recentCaptures
        self.growingClusters = growingClusters
        self.dormantClusters = dormantClusters
        self.emergingLinks = emergingLinks
        self.predictions = predictions
    }

    // MARK: - Computed Properties

    public var activeNodeCount: Int {
        nodes.filter { $0.isActive }.count
    }

    public var dormantNodeCount: Int {
        nodes.filter { !$0.isActive }.count
    }

    public var totalNodeCount: Int {
        nodes.count
    }

    public var totalEdgeCount: Int {
        edges.count
    }

    public var formattedResearchToday: String {
        let hours = totalResearchToday / 60
        let mins = totalResearchToday % 60
        return "\(hours)h \(mins)m"
    }

    public var formattedWeeklyTotal: String {
        let hours = weeklyTotalMinutes / 60
        let mins = weeklyTotalMinutes % 60
        return "\(hours)h \(mins)m"
    }

    public var densityLabel: String {
        if semanticDensity >= 0.8 { return "HIGH" }
        if semanticDensity >= 0.5 { return "MEDIUM" }
        return "LOW"
    }

    public var optimalWindowFormatted: String {
        "\(optimalWindowStart)pm - \(optimalWindowEnd)pm"
    }
}

// MARK: - Preview Data

#if DEBUG
extension KnowledgeDimensionData {
    public static var preview: KnowledgeDimensionData {
        let now = Date()
        let calendar = Calendar.current

        // Generate clusters
        let mlCluster = KnowledgeCluster(
            name: "Machine Learning",
            nodeIDs: [],
            density: 0.89,
            colorHex: "#8B5CF6",
            lastActivityDate: now,
            growthRate: 8,
            status: .growing
        )

        let swiftCluster = KnowledgeCluster(
            name: "Swift/iOS",
            nodeIDs: [],
            density: 0.72,
            colorHex: "#F59E0B",
            lastActivityDate: calendar.date(byAdding: .day, value: -2, to: now)!,
            growthRate: 3,
            status: .stable
        )

        let productivityCluster = KnowledgeCluster(
            name: "Productivity",
            nodeIDs: [],
            density: 0.65,
            colorHex: "#10B981",
            lastActivityDate: calendar.date(byAdding: .day, value: -5, to: now)!,
            growthRate: 2,
            status: .stable
        )

        let cookingCluster = KnowledgeCluster(
            name: "Cooking Recipes",
            nodeIDs: [],
            density: 0.45,
            colorHex: "#EC4899",
            lastActivityDate: calendar.date(byAdding: .day, value: -23, to: now)!,
            growthRate: 0,
            status: .dormant
        )

        // Generate nodes
        let nodes: [KnowledgeNode] = [
            KnowledgeNode(title: "GPT", type: .concept, clusterID: mlCluster.id, createdDate: calendar.date(byAdding: .month, value: -1, to: now)!, lastAccessedDate: calendar.date(byAdding: .hour, value: -2, to: now)!, accessCount: 47, notes: ["GPT-4 shows emergent reasoning capabilities at scale"], tags: ["LLM", "Transformers"]),
            KnowledgeNode(title: "BERT", type: .concept, clusterID: mlCluster.id, createdDate: calendar.date(byAdding: .month, value: -2, to: now)!, lastAccessedDate: calendar.date(byAdding: .day, value: -1, to: now)!, accessCount: 32, tags: ["NLP", "Transformers"]),
            KnowledgeNode(title: "Attention Mechanism", type: .concept, clusterID: mlCluster.id, createdDate: calendar.date(byAdding: .month, value: -3, to: now)!, lastAccessedDate: calendar.date(byAdding: .hour, value: -5, to: now)!, accessCount: 58, tags: ["Core", "Architecture"]),
            KnowledgeNode(title: "SwiftUI", type: .concept, clusterID: swiftCluster.id, createdDate: calendar.date(byAdding: .month, value: -6, to: now)!, lastAccessedDate: calendar.date(byAdding: .day, value: -3, to: now)!, accessCount: 89, tags: ["iOS", "UI"]),
            KnowledgeNode(title: "Deep Work", type: .idea, clusterID: productivityCluster.id, createdDate: calendar.date(byAdding: .month, value: -2, to: now)!, lastAccessedDate: calendar.date(byAdding: .day, value: -1, to: now)!, accessCount: 23, tags: ["Focus", "Productivity"])
        ]

        // Generate edges
        let edges: [KnowledgeEdge] = [
            KnowledgeEdge(sourceNodeID: nodes[0].id, targetNodeID: nodes[1].id, strength: 0.89, edgeType: .semantic, createdDate: now, description: "Same architecture family"),
            KnowledgeEdge(sourceNodeID: nodes[0].id, targetNodeID: nodes[2].id, strength: 0.94, edgeType: .semantic, createdDate: now, description: "Core mechanism"),
            KnowledgeEdge(sourceNodeID: nodes[1].id, targetNodeID: nodes[2].id, strength: 0.87, edgeType: .semantic, createdDate: now)
        ]

        // Generate positions for constellation
        let positions: [NodePosition] = nodes.enumerated().map { index, node in
            let angle = Double(index) * (2 * .pi / Double(nodes.count))
            let radius = 100.0 + Double.random(in: -20...20)
            return NodePosition(
                nodeID: node.id,
                x: cos(angle) * radius,
                y: sin(angle) * radius,
                z: Double.random(in: -30...30)
            )
        }

        // Generate research timeline
        let researchTimeline: [HourlyResearch] = (0..<24).map { hour in
            let minutes: Int
            let isActive: Bool
            switch hour {
            case 6...9: minutes = Int.random(in: 0...15); isActive = false
            case 10...12: minutes = Int.random(in: 20...45); isActive = true
            case 13: minutes = Int.random(in: 5...15); isActive = false
            case 14...16: minutes = Int.random(in: 30...55); isActive = true
            case 17...18: minutes = Int.random(in: 10...25); isActive = false
            case 19...21: minutes = Int.random(in: 15...30); isActive = false
            default: minutes = 0; isActive = false
            }
            return HourlyResearch(hour: hour, minutes: minutes, isActive: isActive)
        }

        // Generate weekly research
        let weeklyResearch: [DailyResearch] = [
            DailyResearch(dayOfWeek: "M", totalMinutes: 112),
            DailyResearch(dayOfWeek: "T", totalMinutes: 138),
            DailyResearch(dayOfWeek: "W", totalMinutes: 105),
            DailyResearch(dayOfWeek: "T", totalMinutes: 151),
            DailyResearch(dayOfWeek: "F", totalMinutes: 135)
        ]

        // Generate captures
        let recentCaptures: [KnowledgeCapture] = [
            KnowledgeCapture(title: "Attention Is All You Need", type: .paper, timestamp: calendar.date(byAdding: .hour, value: -2, to: now)!, tags: ["ML", "Transformers"], connectionCount: 12, preview: "The dominant sequence transduction models are based on complex recurrent or convolutional neural networks..."),
            KnowledgeCapture(title: "Connect deep work sessions to HRV recovery patterns", type: .idea, timestamp: calendar.date(byAdding: .minute, value: -45, to: now)!, tags: ["Productivity"], connectionCount: 3, preview: "Hypothesis: HRV above 50ms correlates with 23% better focus sessions"),
            KnowledgeCapture(title: "SwiftUI Navigation Stack Best Practices", type: .bookmark, timestamp: calendar.date(byAdding: .minute, value: -15, to: now)!, tags: ["iOS", "Swift"], connectionCount: 7, sourceURL: "https://developer.apple.com/documentation/swiftui/navigationstack", preview: "NavigationStack provides a way to manage navigation state...")
        ]

        // Generate stamina factors
        let staminaFactors: [StaminaFactor] = [
            StaminaFactor(name: "Sleep Quality", impact: 15, isPositive: true),
            StaminaFactor(name: "Caffeine", impact: 8, isPositive: true),
            StaminaFactor(name: "Afternoon Slump", impact: 12, isPositive: false)
        ]

        // Generate emerging links
        let emergingLinks: [EmergingConnection] = [
            EmergingConnection(sourceCluster: "ML", targetCluster: "Productivity", strength: 0.67, description: "Focus optimization via attention mechanisms")
        ]

        // Generate predictions
        let predictions: [KnowledgePrediction] = [
            KnowledgePrediction(
                condition: "You continue current research velocity in \"Transformers\" cluster",
                prediction: "Knowledge Dimension will level up in ~4 days (currently 340/500 XP)",
                confidence: 0.79,
                suggestedExploration: "\"Mixture of Experts\" paper would bridge 3 existing clusters",
                actions: ["Read Suggestion", "Find Gaps", "Cluster Analytics"]
            )
        ]

        return KnowledgeDimensionData(
            capturesToday: 47,
            capturesChange: 12,
            processedToday: 23,
            connectionsToday: 12,
            semanticDensity: 0.78,
            nodes: nodes,
            edges: edges,
            clusters: [mlCluster, swiftCluster, productivityCluster, cookingCluster],
            nodePositions: positions,
            researchTimeline: researchTimeline,
            peakResearchHour: 14,
            peakResearchMinutes: 42,
            totalResearchToday: 135,
            weeklyResearchData: weeklyResearch,
            weeklyTotalMinutes: 641,
            knowledgeStamina: 72,
            optimalWindowStart: 2,
            optimalWindowEnd: 4,
            rechargeNeededMinutes: 45,
            staminaFactors: staminaFactors,
            recentCaptures: recentCaptures,
            growingClusters: [mlCluster],
            dormantClusters: [cookingCluster],
            emergingLinks: emergingLinks,
            predictions: predictions
        )
    }
}
#endif
