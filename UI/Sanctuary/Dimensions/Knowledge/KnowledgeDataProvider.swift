// CosmoOS/UI/Sanctuary/Dimensions/Knowledge/KnowledgeDataProvider.swift
// Data provider that queries GRDB + NodeGraph OS to build real KnowledgeDimensionData
// Replaces .preview with live Thinkspace graph data

import Foundation
import SwiftUI
import GRDB

@MainActor
class KnowledgeDataProvider: ObservableObject, DimensionScoring {
    nonisolated var dimensionId: String { "knowledge" }

    @Published var data: KnowledgeDimensionData = KnowledgeDimensionData.empty
    @Published var isLoading = false
    @Published var knowledgeIndex: DimensionIndex = .empty

    private let atomRepository: AtomRepository
    private let graphQuery: GraphQueryEngine
    private let graphEngine: NodeGraphEngine

    init(atomRepository: AtomRepository? = nil) {
        self.atomRepository = atomRepository ?? AtomRepository.shared
        self.graphQuery = GraphQueryEngine()
        self.graphEngine = NodeGraphEngine.shared
    }

    // MARK: - DimensionScoring

    func computeIndex() async -> DimensionIndex {
        let captureRate = await computeCaptureRate()
        let processingDepth = await computeProcessingDepth()
        let connectionDensity = await computeConnectionDensity()
        let researchConsistency = await computeResearchConsistency()
        let retrievalActivity = await computeRetrievalActivity()

        var subScores: [String: Double] = [:]
        subScores["captureRate"] = captureRate
        subScores["processingDepth"] = processingDepth
        subScores["connectionDensity"] = connectionDensity
        subScores["researchConsistency"] = researchConsistency
        subScores["retrievalActivity"] = retrievalActivity

        let score = captureRate * 0.20
                  + processingDepth * 0.20
                  + connectionDensity * 0.25
                  + researchConsistency * 0.20
                  + retrievalActivity * 0.15

        let trend = await computeKnowledgeTrend()
        let totalAtoms = (try? await atomRepository.totalCount()) ?? 0
        let confidence = totalAtoms > 10 ? 1.0 : max(0.3, Double(totalAtoms) / 10.0)

        let index = DimensionIndex(
            score: min(100, max(0, score)),
            confidence: confidence,
            trend: trend,
            subScores: subScores,
            dataAge: 0
        )
        knowledgeIndex = index
        return index
    }

    // MARK: - Refresh Data

    func refreshData() async {
        isLoading = true
        defer { isLoading = false }

        async let capturesResult = buildCaptureMetrics()
        async let constellationResult = buildConstellationData()
        async let researchResult = buildResearchTimeline()
        async let staminaResult = buildStaminaData()
        async let recentResult = buildRecentCaptures()
        async let clusterResult = buildClusterInsights()

        let captures = await capturesResult
        let constellation = await constellationResult
        let research = await researchResult
        let stamina = await staminaResult
        let recent = await recentResult
        let clusters = await clusterResult

        data = KnowledgeDimensionData(
            capturesToday: captures.capturesToday,
            capturesChange: captures.capturesChange,
            processedToday: captures.processedToday,
            connectionsToday: captures.connectionsToday,
            semanticDensity: captures.semanticDensity,
            nodes: constellation.nodes,
            edges: constellation.edges,
            clusters: constellation.clusters,
            nodePositions: constellation.positions,
            researchTimeline: research.timeline,
            peakResearchHour: research.peakHour,
            peakResearchMinutes: research.peakMinutes,
            totalResearchToday: research.totalToday,
            weeklyResearchData: research.weeklyData,
            weeklyTotalMinutes: research.weeklyTotal,
            knowledgeStamina: stamina.stamina,
            optimalWindowStart: stamina.optimalStart,
            optimalWindowEnd: stamina.optimalEnd,
            rechargeNeededMinutes: stamina.rechargeMinutes,
            staminaFactors: stamina.factors,
            recentCaptures: recent,
            growingClusters: clusters.growing,
            dormantClusters: clusters.dormant,
            emergingLinks: clusters.emerging,
            predictions: clusters.predictions
        )
    }

    // MARK: - Capture Metrics

    private struct CaptureMetrics {
        let capturesToday: Int
        let capturesChange: Int
        let processedToday: Int
        let connectionsToday: Int
        let semanticDensity: Double
    }

    private func buildCaptureMetrics() async -> CaptureMetrics {
        let knowledgeTypes: [AtomType] = [.idea, .research, .connection, .note]

        var todayCount = 0
        var yesterdayCount = 0
        for type in knowledgeTypes {
            let atoms = (try? await atomRepository.fetchAll(type: type)) ?? []
            todayCount += atoms.filter { isToday($0.createdAt) }.count
            yesterdayCount += atoms.filter { isYesterday($0.createdAt) }.count
        }

        // Processed = nodes with embeddings
        let stats = try? await graphQuery.getStatistics()
        let embeddingCount = stats.map { Int(Double($0.nodeCount) * $0.embeddingCoverage) } ?? 0
        let todayProcessed = min(todayCount, embeddingCount)

        // Connections today = edges created today
        let edgeCount = stats?.edgeCount ?? 0
        let nodeCount = stats?.nodeCount ?? 0

        // Semantic density = avg connections / target (3 per node)
        let avgDegree = stats?.averageDegree ?? 0
        let density = min(avgDegree / 6.0, 1.0) // target: avg degree of 6 (3 in + 3 out)

        return CaptureMetrics(
            capturesToday: todayCount,
            capturesChange: todayCount - yesterdayCount,
            processedToday: todayProcessed,
            connectionsToday: min(todayCount, edgeCount > 0 ? todayCount : 0),
            semanticDensity: density
        )
    }

    // MARK: - Constellation Data

    private struct ConstellationData {
        let nodes: [KnowledgeNode]
        let edges: [KnowledgeEdge]
        let clusters: [KnowledgeCluster]
        let positions: [NodePosition]
    }

    private func buildConstellationData() async -> ConstellationData {
        // Fetch top hub nodes for the constellation visualization
        let hubNodes = (try? await graphQuery.hubNodes(limit: 30)) ?? []
        let recentNodes = (try? await graphQuery.recentlyAccessed(limit: 20)) ?? []

        // Merge and deduplicate
        var seenUUIDs = Set<String>()
        var allGraphNodes: [GraphNode] = []
        for node in hubNodes + recentNodes {
            if seenUUIDs.insert(node.atomUUID).inserted {
                allGraphNodes.append(node)
            }
        }

        // Limit to 40 nodes for performance
        if allGraphNodes.count > 40 {
            allGraphNodes = Array(allGraphNodes.prefix(40))
        }

        // Map GraphNode -> KnowledgeNode
        let knowledgeNodes: [KnowledgeNode] = allGraphNodes.map { gn in
            let nodeType = mapAtomTypeToNodeType(gn.atomType)
            let lastAccessed: Date = {
                if let dateStr = gn.lastAccessedAt {
                    return parseDate(dateStr) ?? Date.distantPast
                }
                return Date.distantPast
            }()

            return KnowledgeNode(
                id: UUID(uuidString: gn.atomUUID) ?? UUID(),
                title: gn.atomType.capitalized,
                type: nodeType,
                clusterID: nil,
                createdDate: parseDate(gn.createdAt) ?? Date(),
                lastAccessedDate: lastAccessed,
                accessCount: gn.accessCount,
                tags: gn.clusterHint.map { [$0] } ?? []
            )
        }

        // Build edges from graph_edges between visible nodes
        let uuids = allGraphNodes.map { $0.atomUUID }
        let graphEdges = (try? await graphQuery.getEdgesForBlocks(uuids: uuids)) ?? []

        let knowledgeEdges: [KnowledgeEdge] = graphEdges.compactMap { ge in
            guard let sourceUUID = UUID(uuidString: ge.sourceUUID),
                  let targetUUID = UUID(uuidString: ge.targetUUID) else { return nil }

            let edgeType: EdgeType = {
                switch ge.edgeType {
                case GraphEdgeType.semantic.rawValue: return .semantic
                case GraphEdgeType.explicit.rawValue: return .manual
                default: return .temporal
                }
            }()

            return KnowledgeEdge(
                sourceNodeID: sourceUUID,
                targetNodeID: targetUUID,
                strength: ge.combinedWeight,
                edgeType: edgeType,
                createdDate: parseDate(ge.createdAt) ?? Date()
            )
        }

        // Build clusters from cluster_hint groupings
        let clusterHints = (try? await graphQuery.getClusters()) ?? []
        var knowledgeClusters: [KnowledgeCluster] = []
        let clusterColors = ["#8B5CF6", "#3B82F6", "#F59E0B", "#10B981", "#EC4899", "#6366F1", "#EF4444"]

        for (index, hint) in clusterHints.prefix(7).enumerated() {
            let clusterNodes = (try? await graphQuery.getNodesInCluster(hint, limit: 50)) ?? []
            let nodeIDs = clusterNodes.compactMap { UUID(uuidString: $0.atomUUID) }

            let lastActivity: Date = clusterNodes.compactMap { node in
                node.lastAccessedAt.flatMap { parseDate($0) }
            }.max() ?? Date.distantPast

            let daysSinceActivity = Calendar.current.dateComponents([.day], from: lastActivity, to: Date()).day ?? 0

            let status: ClusterStatus = {
                if daysSinceActivity > 14 { return .dormant }
                if clusterNodes.count < 3 { return .emerging }
                if daysSinceActivity < 3 { return .growing }
                return .stable
            }()

            let density = clusterNodes.count > 1
                ? Double(clusterNodes.reduce(0) { $0 + $1.totalDegree }) / Double(clusterNodes.count * 2)
                : 0

            knowledgeClusters.append(KnowledgeCluster(
                name: hint.capitalized,
                nodeIDs: nodeIDs,
                density: min(1.0, density),
                colorHex: clusterColors[index % clusterColors.count],
                lastActivityDate: lastActivity,
                growthRate: Double(clusterNodes.filter { isThisWeek($0.createdAt) }.count),
                status: status
            ))
        }

        // Assign cluster IDs to nodes
        var updatedNodes = knowledgeNodes
        for (clusterIndex, cluster) in knowledgeClusters.enumerated() {
            for nodeID in cluster.nodeIDs {
                if let nodeIndex = updatedNodes.firstIndex(where: { $0.id == nodeID }) {
                    updatedNodes[nodeIndex] = KnowledgeNode(
                        id: updatedNodes[nodeIndex].id,
                        title: updatedNodes[nodeIndex].title,
                        type: updatedNodes[nodeIndex].type,
                        clusterID: cluster.id,
                        createdDate: updatedNodes[nodeIndex].createdDate,
                        lastAccessedDate: updatedNodes[nodeIndex].lastAccessedDate,
                        accessCount: updatedNodes[nodeIndex].accessCount,
                        notes: updatedNodes[nodeIndex].notes,
                        tags: updatedNodes[nodeIndex].tags
                    )
                    _ = clusterIndex // suppress unused warning
                }
            }
        }

        // Generate 2D positions using force-directed-ish layout
        let positions = generatePositions(for: updatedNodes, edges: knowledgeEdges)

        return ConstellationData(
            nodes: updatedNodes,
            edges: knowledgeEdges,
            clusters: knowledgeClusters,
            positions: positions
        )
    }

    private func generatePositions(for nodes: [KnowledgeNode], edges: [KnowledgeEdge]) -> [NodePosition] {
        guard !nodes.isEmpty else { return [] }

        // Simple circular layout with cluster grouping
        var positions: [NodePosition] = []
        let nodeCount = nodes.count
        let radius = 100.0 + Double(nodeCount) * 2.0

        for (index, node) in nodes.enumerated() {
            let angle = Double(index) * (2 * .pi / Double(nodeCount))
            let jitter = Double.random(in: -15...15)
            positions.append(NodePosition(
                nodeID: node.id,
                x: cos(angle) * (radius + jitter),
                y: sin(angle) * (radius + jitter),
                z: Double.random(in: -20...20)
            ))
        }

        return positions
    }

    // MARK: - Research Timeline

    private struct ResearchTimelineData {
        let timeline: [HourlyResearch]
        let peakHour: Int
        let peakMinutes: Int
        let totalToday: Int
        let weeklyData: [DailyResearch]
        let weeklyTotal: Int
    }

    private func buildResearchTimeline() async -> ResearchTimelineData {
        // Fetch deep work blocks with research intent from this week
        let deepWorkAtoms = (try? await atomRepository.fetchAll(type: .deepWorkBlock)) ?? []

        let calendar = Calendar.current
        let todaySessions = deepWorkAtoms.filter { isToday($0.createdAt) && isResearchIntent($0) }
        let weekSessions = deepWorkAtoms.filter { isThisWeek($0.createdAt) && isResearchIntent($0) }

        // Build hourly heatmap for today
        var hourlyMinutes = [Int](repeating: 0, count: 24)
        for session in todaySessions {
            let duration = extractDuration(session)
            if let date = parseDate(session.createdAt) {
                let hour = calendar.component(.hour, from: date)
                hourlyMinutes[hour] += duration
            }
        }

        let currentHour = calendar.component(.hour, from: Date())
        let timeline = (0..<24).map { hour in
            HourlyResearch(
                hour: hour,
                minutes: hourlyMinutes[hour],
                isActive: hour == currentHour && hourlyMinutes[hour] > 0
            )
        }

        // Find peak hour
        let peakHour = hourlyMinutes.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
        let peakMinutes = hourlyMinutes[peakHour]
        let totalToday = hourlyMinutes.reduce(0, +)

        // Build weekly breakdown
        let dayNames = ["S", "M", "T", "W", "T", "F", "S"]
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()

        var weeklyData: [DailyResearch] = []
        var weeklyTotal = 0
        for dayOffset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfWeek) else { continue }
            let daySessions = weekSessions.filter { atom in
                guard let date = parseDate(atom.createdAt) else { return false }
                return calendar.isDate(date, inSameDayAs: day)
            }
            let dayMinutes = daySessions.reduce(0) { $0 + extractDuration($1) }
            weeklyTotal += dayMinutes
            weeklyData.append(DailyResearch(
                dayOfWeek: dayNames[dayOffset % 7],
                totalMinutes: dayMinutes
            ))
        }

        return ResearchTimelineData(
            timeline: timeline,
            peakHour: peakHour,
            peakMinutes: peakMinutes,
            totalToday: totalToday,
            weeklyData: weeklyData,
            weeklyTotal: weeklyTotal
        )
    }

    // MARK: - Stamina Data

    private struct StaminaData {
        let stamina: Double
        let optimalStart: Int
        let optimalEnd: Int
        let rechargeMinutes: Int
        let factors: [StaminaFactor]
    }

    private func buildStaminaData() async -> StaminaData {
        // Compute stamina from deep work session patterns
        let deepWorkAtoms = (try? await atomRepository.fetchAll(type: .deepWorkBlock)) ?? []
        let recentSessions = deepWorkAtoms.filter { isThisWeek($0.createdAt) }

        // Average session duration as stamina proxy (target: 90 min)
        let durations = recentSessions.map { extractDuration($0) }
        let avgDuration = durations.isEmpty ? 0 : durations.reduce(0, +) / durations.count
        let stamina = min(100.0, Double(avgDuration) / 90.0 * 100.0)

        // Find optimal research window from peak hours
        let calendar = Calendar.current
        var hourCounts = [Int](repeating: 0, count: 24)
        for session in recentSessions {
            if let date = parseDate(session.createdAt) {
                let hour = calendar.component(.hour, from: date)
                hourCounts[hour] += extractDuration(session)
            }
        }

        // Find 2-hour window with most minutes
        var bestStart = 14
        var bestTotal = 0
        for h in 0..<23 {
            let windowTotal = hourCounts[h] + hourCounts[h + 1]
            if windowTotal > bestTotal {
                bestTotal = windowTotal
                bestStart = h
            }
        }

        // Build stamina factors
        var factors: [StaminaFactor] = []
        let sessionCount = recentSessions.count
        if sessionCount >= 5 {
            factors.append(StaminaFactor(name: "Consistent Sessions", impact: 15, isPositive: true))
        }
        if avgDuration > 60 {
            factors.append(StaminaFactor(name: "Deep Focus", impact: 10, isPositive: true))
        }
        if sessionCount == 0 {
            factors.append(StaminaFactor(name: "No Recent Sessions", impact: 20, isPositive: false))
        }

        let rechargeNeeded = max(0, 90 - avgDuration)

        return StaminaData(
            stamina: stamina,
            optimalStart: bestStart,
            optimalEnd: min(23, bestStart + 2),
            rechargeMinutes: rechargeNeeded,
            factors: factors
        )
    }

    // MARK: - Recent Captures

    private func buildRecentCaptures() async -> [KnowledgeCapture] {
        let recentAtoms = (try? await atomRepository.fetchRecent(limit: 10)) ?? []

        return recentAtoms.compactMap { atom in
            let captureType: CaptureType = {
                switch atom.type {
                case .idea: return .idea
                case .research: return .paper
                case .connection: return .bookmark
                case .note: return .note
                default: return .note
                }
            }()

            let tags: [String] = {
                if let meta = atom.metadata, let data = meta.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let tagArray = json["tags"] as? [String] {
                    return tagArray
                }
                return []
            }()

            // Count connections from links
            let connectionCount = atom.linksList.count

            return KnowledgeCapture(
                id: UUID(uuidString: atom.uuid) ?? UUID(),
                title: atom.title ?? "Untitled",
                type: captureType,
                timestamp: parseDate(atom.createdAt) ?? Date(),
                tags: tags,
                connectionCount: connectionCount,
                sourceURL: nil,
                preview: String((atom.body ?? "").prefix(200))
            )
        }
    }

    // MARK: - Cluster Insights

    private struct ClusterInsightsData {
        let growing: [KnowledgeCluster]
        let dormant: [KnowledgeCluster]
        let emerging: [EmergingConnection]
        let predictions: [KnowledgePrediction]
    }

    private func buildClusterInsights() async -> ClusterInsightsData {
        let clusterHints = (try? await graphQuery.getClusters()) ?? []

        var growing: [KnowledgeCluster] = []
        var dormant: [KnowledgeCluster] = []
        let clusterColors = ["#8B5CF6", "#3B82F6", "#F59E0B", "#10B981", "#EC4899"]

        for (index, hint) in clusterHints.prefix(10).enumerated() {
            let clusterNodes = (try? await graphQuery.getNodesInCluster(hint, limit: 50)) ?? []
            let nodeIDs = clusterNodes.compactMap { UUID(uuidString: $0.atomUUID) }

            let lastActivity: Date = clusterNodes.compactMap { node in
                node.lastAccessedAt.flatMap { parseDate($0) }
            }.max() ?? Date.distantPast

            let recentGrowth = clusterNodes.filter { isThisWeek($0.createdAt) }.count
            let daysSinceActivity = Calendar.current.dateComponents([.day], from: lastActivity, to: Date()).day ?? 0

            let status: ClusterStatus = daysSinceActivity > 14 ? .dormant : (recentGrowth > 0 ? .growing : .stable)

            let density = clusterNodes.count > 1
                ? Double(clusterNodes.reduce(0) { $0 + $1.totalDegree }) / Double(clusterNodes.count * 2)
                : 0

            let cluster = KnowledgeCluster(
                name: hint.capitalized,
                nodeIDs: nodeIDs,
                density: min(1.0, density),
                colorHex: clusterColors[index % clusterColors.count],
                lastActivityDate: lastActivity,
                growthRate: Double(recentGrowth),
                status: status
            )

            switch status {
            case .growing: growing.append(cluster)
            case .dormant: dormant.append(cluster)
            default: break
            }
        }

        // Build emerging connections between clusters
        var emerging: [EmergingConnection] = []
        if clusterHints.count >= 2 {
            // Check for cross-cluster edges
            for i in 0..<min(clusterHints.count - 1, 3) {
                for j in (i + 1)..<min(clusterHints.count, 4) {
                    let nodesA = (try? await graphQuery.getNodesInCluster(clusterHints[i], limit: 10)) ?? []
                    let nodesB = (try? await graphQuery.getNodesInCluster(clusterHints[j], limit: 10)) ?? []
                    let allUUIDs = nodesA.map { $0.atomUUID } + nodesB.map { $0.atomUUID }
                    let crossEdges = (try? await graphQuery.getEdgesForBlocks(uuids: allUUIDs)) ?? []

                    // Filter to only cross-cluster edges
                    let uuidsA = Set(nodesA.map { $0.atomUUID })
                    let uuidsB = Set(nodesB.map { $0.atomUUID })
                    let bridgeEdges = crossEdges.filter { edge in
                        (uuidsA.contains(edge.sourceUUID) && uuidsB.contains(edge.targetUUID)) ||
                        (uuidsB.contains(edge.sourceUUID) && uuidsA.contains(edge.targetUUID))
                    }

                    if !bridgeEdges.isEmpty {
                        let avgStrength = bridgeEdges.reduce(0.0) { $0 + $1.combinedWeight } / Double(bridgeEdges.count)
                        emerging.append(EmergingConnection(
                            sourceCluster: clusterHints[i].capitalized,
                            targetCluster: clusterHints[j].capitalized,
                            strength: avgStrength,
                            description: "\(bridgeEdges.count) cross-cluster connection\(bridgeEdges.count == 1 ? "" : "s")"
                        ))
                    }
                }
            }
        }

        // Build predictions
        var predictions: [KnowledgePrediction] = []
        let stats = try? await graphQuery.getStatistics()
        if let stats = stats, stats.nodeCount > 5 {
            let avgDeg = stats.averageDegree
            if avgDeg < 2.0 {
                predictions.append(KnowledgePrediction(
                    condition: "Average connections per node is \(String(format: "%.1f", avgDeg))",
                    prediction: "Creating more cross-topic links would strengthen your knowledge graph",
                    confidence: 0.75,
                    suggestedExploration: "Try connecting recent research to existing ideas",
                    actions: ["Find Gaps", "Auto-Connect", "Explore Graph"]
                ))
            }
            if !growing.isEmpty {
                let topCluster = growing.first!
                predictions.append(KnowledgePrediction(
                    condition: "Your \"\(topCluster.name)\" cluster is actively growing",
                    prediction: "Continue adding to this cluster to build deep expertise",
                    confidence: 0.82,
                    suggestedExploration: "Explore adjacent topics to bridge clusters",
                    actions: ["Expand Cluster", "Find Related", "Cluster Analytics"]
                ))
            }
        }

        return ClusterInsightsData(
            growing: growing,
            dormant: dormant,
            emerging: emerging,
            predictions: predictions
        )
    }

    // MARK: - Dimension Index Sub-Scores

    private func computeCaptureRate() async -> Double {
        let knowledgeTypes: [AtomType] = [.idea, .research, .connection, .note]
        var weekCount = 0
        for type in knowledgeTypes {
            let atoms = (try? await atomRepository.fetchAll(type: type)) ?? []
            weekCount += atoms.filter { isThisWeek($0.createdAt) }.count
        }
        // Target: 30 captures per week
        return min(100, Double(weekCount) / 30.0 * 100)
    }

    private func computeProcessingDepth() async -> Double {
        let stats = try? await graphQuery.getStatistics()
        let coverage = stats?.embeddingCoverage ?? 0
        return coverage * 100
    }

    private func computeConnectionDensity() async -> Double {
        let stats = try? await graphQuery.getStatistics()
        let avgDegree = stats?.averageDegree ?? 0
        // Target: average degree of 3
        return min(100, avgDegree / 3.0 * 100)
    }

    private func computeResearchConsistency() async -> Double {
        let deepWorkAtoms = (try? await atomRepository.fetchAll(type: .deepWorkBlock)) ?? []
        let weekSessions = deepWorkAtoms.filter { isThisWeek($0.createdAt) && isResearchIntent($0) }
        let researchMinutes = weekSessions.reduce(0) { $0 + extractDuration($1) }
        // Target: 300 min (5h) per week
        return min(100, Double(researchMinutes) / 300.0 * 100)
    }

    private func computeRetrievalActivity() async -> Double {
        let recentNodes = (try? await graphQuery.recentlyAccessed(limit: 50)) ?? []
        let stats = try? await graphQuery.getStatistics()
        let totalNodes = max(stats?.nodeCount ?? 1, 1)
        // What fraction of the graph was accessed recently
        return min(100, Double(recentNodes.count) / Double(totalNodes) * 100)
    }

    private func computeKnowledgeTrend() async -> DimensionTrend {
        // Compare this week's captures to last week
        let knowledgeTypes: [AtomType] = [.idea, .research, .connection, .note]
        var thisWeekCount = 0
        var lastWeekCount = 0

        for type in knowledgeTypes {
            let atoms = (try? await atomRepository.fetchAll(type: type)) ?? []
            thisWeekCount += atoms.filter { isThisWeek($0.createdAt) }.count
            lastWeekCount += atoms.filter { isLastWeek($0.createdAt) }.count
        }

        if thisWeekCount > lastWeekCount + 2 { return .rising }
        if thisWeekCount < lastWeekCount - 2 { return .falling }
        return .stable
    }

    // MARK: - Helpers

    private func mapAtomTypeToNodeType(_ atomType: String) -> NodeType {
        switch atomType {
        case "idea": return .idea
        case "research": return .paper
        case "connection": return .bookmark
        case "note": return .note
        default: return .concept
        }
    }

    private func isResearchIntent(_ atom: Atom) -> Bool {
        guard let meta = atom.metadata, let data = meta.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        let intent = json["intent"] as? String
        return intent == "research" || intent == nil // default deep work counts
    }

    private func extractDuration(_ atom: Atom) -> Int {
        guard let meta = atom.metadata, let data = meta.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return 30 }
        return (json["durationMinutes"] as? Int) ?? (json["duration"] as? Int) ?? 30
    }

    private func parseDate(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }

    private func isToday(_ dateString: String) -> Bool {
        guard let date = parseDate(dateString) else { return false }
        return Calendar.current.isDateInToday(date)
    }

    private func isYesterday(_ dateString: String) -> Bool {
        guard let date = parseDate(dateString) else { return false }
        return Calendar.current.isDateInYesterday(date)
    }

    private func isThisWeek(_ dateString: String) -> Bool {
        guard let date = parseDate(dateString) else { return false }
        return Calendar.current.isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
    }

    private func isLastWeek(_ dateString: String) -> Bool {
        guard let date = parseDate(dateString) else { return false }
        guard let lastWeek = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date()) else { return false }
        return Calendar.current.isDate(date, equalTo: lastWeek, toGranularity: .weekOfYear)
    }
}

// MARK: - KnowledgeDimensionData Empty Factory

extension KnowledgeDimensionData {
    public static var empty: KnowledgeDimensionData {
        KnowledgeDimensionData(
            capturesToday: 0,
            capturesChange: 0,
            processedToday: 0,
            connectionsToday: 0,
            semanticDensity: 0,
            nodes: [],
            edges: [],
            clusters: [],
            nodePositions: [],
            researchTimeline: (0..<24).map { HourlyResearch(hour: $0, minutes: 0) },
            peakResearchHour: 0,
            peakResearchMinutes: 0,
            totalResearchToday: 0,
            weeklyResearchData: [],
            weeklyTotalMinutes: 0,
            knowledgeStamina: 0,
            optimalWindowStart: 0,
            optimalWindowEnd: 0,
            rechargeNeededMinutes: 0,
            staminaFactors: [],
            recentCaptures: [],
            growingClusters: [],
            dormantClusters: [],
            emergingLinks: [],
            predictions: []
        )
    }
}
