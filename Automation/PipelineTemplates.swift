// CosmoOS/Automation/PipelineTemplates.swift
// Pre-built workflow blueprints — one-click cluster + rule setups
// Each template creates multiple clusters with pre-wired automation rules

import Foundation
import SwiftUI

// MARK: - Template Definitions

enum PipelineTemplate: String, CaseIterable, Identifiable {
    case contentPipeline = "content_pipeline"
    case clientWorkspace = "client_workspace"
    case researchFunnel = "research_funnel"
    case weeklySprint = "weekly_sprint"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .contentPipeline: return "Content Pipeline"
        case .clientWorkspace: return "Client Workspace"
        case .researchFunnel: return "Research Funnel"
        case .weeklySprint: return "Weekly Sprint"
        }
    }

    var description: String {
        switch self {
        case .contentPipeline:
            return "4 clusters: Brainstorm → Draft → Review → Published. Content auto-advances between them."
        case .clientWorkspace:
            return "Full client pipeline: Swipes → Ideas → Content → Published. Filtered by client profile."
        case .researchFunnel:
            return "3 clusters: Captures → Analysis → Synthesized. Research flows through processing stages."
        case .weeklySprint:
            return "3 clusters: This Week → In Progress → Done. Time-based task management."
        }
    }

    var icon: String {
        switch self {
        case .contentPipeline: return "arrow.right.arrow.left.square"
        case .clientWorkspace: return "person.crop.rectangle.stack"
        case .researchFunnel: return "line.3.horizontal.decrease.circle"
        case .weeklySprint: return "calendar.badge.checkmark"
        }
    }

    var clusterCount: Int {
        switch self {
        case .contentPipeline: return 4
        case .clientWorkspace: return 4
        case .researchFunnel: return 3
        case .weeklySprint: return 3
        }
    }

    var requiresClient: Bool {
        self == .clientWorkspace
    }

    var accentColor: Color {
        switch self {
        case .contentPipeline: return Color(hex: "5B84B0")   // Steel blue (content)
        case .clientWorkspace: return Color(hex: "8B6BAB")   // Violet (connection)
        case .researchFunnel: return Color(hex: "4A8B72")    // Sage (research)
        case .weeklySprint: return Color(hex: "B06B6B")      // Rose (tasks)
        }
    }
}

// MARK: - Template Materializer

@MainActor
enum PipelineTemplateMaterializer {

    /// Materialize a template into clusters + rules on the current thinkspace
    /// Returns the created cluster IDs for flow line rendering
    static func materialize(
        template: PipelineTemplate,
        clientUUID: String? = nil,
        clientName: String? = nil,
        origin: CGPoint,
        thinkspaceId: String?,
        clusterEngine: CanvasClusterEngine,
        blocks: [CanvasBlock]
    ) async -> [UUID] {
        switch template {
        case .contentPipeline:
            return await materializeContentPipeline(origin: origin, thinkspaceId: thinkspaceId, clusterEngine: clusterEngine, blocks: blocks)
        case .clientWorkspace:
            return await materializeClientWorkspace(clientUUID: clientUUID, clientName: clientName ?? "Client", origin: origin, thinkspaceId: thinkspaceId, clusterEngine: clusterEngine, blocks: blocks)
        case .researchFunnel:
            return await materializeResearchFunnel(origin: origin, thinkspaceId: thinkspaceId, clusterEngine: clusterEngine, blocks: blocks)
        case .weeklySprint:
            return await materializeWeeklySprint(origin: origin, thinkspaceId: thinkspaceId, clusterEngine: clusterEngine, blocks: blocks)
        }
    }

    // MARK: - Content Pipeline

    private static func materializeContentPipeline(origin: CGPoint, thinkspaceId: String?, clusterEngine: CanvasClusterEngine, blocks: [CanvasBlock]) async -> [UUID] {
        let clusterWidth: CGFloat = 300
        let clusterHeight: CGFloat = 400
        let gap: CGFloat = 60

        let stages: [(name: String, colorIndex: Int, intent: String)] = [
            ("Brainstorm", 0, "Ideas in brainstorm phase"),       // Indigo
            ("Draft", 4, "Content in draft phase"),               // Forest green
            ("Review", 3, "Content ready for review"),            // Amber
            ("Published", 5, "Published content"),                // Cyan
        ]

        var clusterIds: [UUID] = []

        for (i, stage) in stages.enumerated() {
            let x = origin.x + CGFloat(i) * (clusterWidth + gap)
            let rect = CGRect(x: x, y: origin.y, width: clusterWidth, height: clusterHeight)

            clusterEngine.createZoneCluster(
                name: stage.name,
                colorIndex: stage.colorIndex,
                boundingRect: rect,
                thinkspaceId: thinkspaceId
            )

            let clusterId = clusterEngine.userClusters.last!.id
            clusterIds.append(clusterId)

            // Set intent
            if var idx = clusterEngine.userClusters.firstIndex(where: { $0.id == clusterId }) {
                clusterEngine.userClusters[idx].intent = stage.intent
            }
        }

        // Create flow rules between clusters
        for i in 0..<(clusterIds.count - 1) {
            let fromId = clusterIds[i].uuidString
            let toId = clusterIds[i + 1].uuidString
            let phases = ["brainstorm", "draft", "polish", "published"]

            let rule = AutomationRule.create(
                name: "\(stages[i].name) → \(stages[i + 1].name)",
                scope: .cluster,
                scopeId: fromId,
                triggerType: .phaseAdvanced,
                conditions: [
                    AutomationCondition(field: .contentPhase, op: .equals, value: .string(phases[min(i + 1, phases.count - 1)]))
                ],
                actions: [
                    AutomationAction(type: .moveToCluster, config: ["clusterId": .string(toId)], label: "Move to \(stages[i + 1].name)")
                ]
            )
            try? await AutomationDispatcher.shared.createRule(rule)
        }

        return clusterIds
    }

    // MARK: - Client Workspace

    private static func materializeClientWorkspace(clientUUID: String?, clientName: String, origin: CGPoint, thinkspaceId: String?, clusterEngine: CanvasClusterEngine, blocks: [CanvasBlock]) async -> [UUID] {
        let clusterWidth: CGFloat = 300
        let clusterHeight: CGFloat = 400
        let gap: CGFloat = 60

        let stages: [(name: String, colorIndex: Int, intent: String)] = [
            ("\(clientName) Swipes", 7, "\(clientName)'s swipe files"),
            ("\(clientName) Ideas", 0, "\(clientName)'s ideas"),
            ("\(clientName) Content", 4, "\(clientName)'s content in progress"),
            ("\(clientName) Published", 5, "\(clientName)'s published content"),
        ]

        var clusterIds: [UUID] = []

        for (i, stage) in stages.enumerated() {
            let x = origin.x + CGFloat(i) * (clusterWidth + gap)
            let rect = CGRect(x: x, y: origin.y, width: clusterWidth, height: clusterHeight)

            clusterEngine.createZoneCluster(
                name: stage.name,
                colorIndex: stage.colorIndex,
                boundingRect: rect,
                thinkspaceId: thinkspaceId
            )

            let clusterId = clusterEngine.userClusters.last!.id
            clusterIds.append(clusterId)

            if var idx = clusterEngine.userClusters.firstIndex(where: { $0.id == clusterId }) {
                clusterEngine.userClusters[idx].intent = stage.intent
            }

            // Create client-filtered collection rule
            var conditions: [AutomationCondition] = []
            if let uuid = clientUUID {
                conditions.append(AutomationCondition(field: .atomClientUUID, op: .equals, value: .string(uuid)))
            } else {
                conditions.append(AutomationCondition(field: .clientName, op: .contains, value: .string(clientName)))
            }

            // Swipes cluster collects research
            if i == 0 {
                let rule = AutomationRule.create(
                    name: "Collect \(clientName) swipes",
                    scope: .global,
                    triggerType: .atomTypeCreated,
                    triggerConfig: ["atomType": "research"],
                    conditions: conditions,
                    actions: [AutomationAction(type: .moveToCluster, config: ["clusterId": .string(clusterId.uuidString)], label: "Move to \(stage.name)")]
                )
                try? await AutomationDispatcher.shared.createRule(rule)
            }

            // Ideas cluster collects ideas
            if i == 1 {
                let rule = AutomationRule.create(
                    name: "Collect \(clientName) ideas",
                    scope: .global,
                    triggerType: .atomTypeCreated,
                    triggerConfig: ["atomType": "idea"],
                    conditions: conditions,
                    actions: [AutomationAction(type: .moveToCluster, config: ["clusterId": .string(clusterId.uuidString)], label: "Move to \(stage.name)")]
                )
                try? await AutomationDispatcher.shared.createRule(rule)
            }

            // Content cluster collects content
            if i == 2 {
                let rule = AutomationRule.create(
                    name: "Collect \(clientName) content",
                    scope: .global,
                    triggerType: .atomTypeCreated,
                    triggerConfig: ["atomType": "content"],
                    conditions: conditions,
                    actions: [AutomationAction(type: .moveToCluster, config: ["clusterId": .string(clusterId.uuidString)], label: "Move to \(stage.name)")]
                )
                try? await AutomationDispatcher.shared.createRule(rule)
            }
        }

        return clusterIds
    }

    // MARK: - Research Funnel

    private static func materializeResearchFunnel(origin: CGPoint, thinkspaceId: String?, clusterEngine: CanvasClusterEngine, blocks: [CanvasBlock]) async -> [UUID] {
        let clusterWidth: CGFloat = 320
        let clusterHeight: CGFloat = 380
        let gap: CGFloat = 60

        let stages: [(name: String, colorIndex: Int, intent: String)] = [
            ("Captures", 4, "New research captures"),
            ("Analysis", 0, "Research being analyzed"),
            ("Synthesized", 5, "Synthesized insights"),
        ]

        var clusterIds: [UUID] = []

        for (i, stage) in stages.enumerated() {
            let x = origin.x + CGFloat(i) * (clusterWidth + gap)
            let rect = CGRect(x: x, y: origin.y, width: clusterWidth, height: clusterHeight)

            clusterEngine.createZoneCluster(
                name: stage.name,
                colorIndex: stage.colorIndex,
                boundingRect: rect,
                thinkspaceId: thinkspaceId
            )

            let clusterId = clusterEngine.userClusters.last!.id
            clusterIds.append(clusterId)

            if var idx = clusterEngine.userClusters.firstIndex(where: { $0.id == clusterId }) {
                clusterEngine.userClusters[idx].intent = stage.intent
            }
        }

        // Auto-collect new research into Captures
        let captureRule = AutomationRule.create(
            name: "Collect research captures",
            scope: .global,
            triggerType: .atomTypeCreated,
            triggerConfig: ["atomType": "research"],
            actions: [AutomationAction(type: .moveToCluster, config: ["clusterId": .string(clusterIds[0].uuidString)], label: "Move to Captures")]
        )
        try? await AutomationDispatcher.shared.createRule(captureRule)

        return clusterIds
    }

    // MARK: - Weekly Sprint

    private static func materializeWeeklySprint(origin: CGPoint, thinkspaceId: String?, clusterEngine: CanvasClusterEngine, blocks: [CanvasBlock]) async -> [UUID] {
        let clusterWidth: CGFloat = 280
        let clusterHeight: CGFloat = 400
        let gap: CGFloat = 50

        let stages: [(name: String, colorIndex: Int)] = [
            ("This Week", 6),      // Blue
            ("In Progress", 3),    // Amber
            ("Done", 4),           // Forest green
        ]

        var clusterIds: [UUID] = []

        for (i, stage) in stages.enumerated() {
            let x = origin.x + CGFloat(i) * (clusterWidth + gap)
            let rect = CGRect(x: x, y: origin.y, width: clusterWidth, height: clusterHeight)

            clusterEngine.createZoneCluster(
                name: stage.name,
                colorIndex: stage.colorIndex,
                boundingRect: rect,
                thinkspaceId: thinkspaceId
            )

            let clusterId = clusterEngine.userClusters.last!.id
            clusterIds.append(clusterId)
        }

        // Auto-collect tasks created this week
        let weeklyRule = AutomationRule.create(
            name: "Collect this week's tasks",
            scope: .cluster,
            scopeId: clusterIds[0].uuidString,
            triggerType: .atomTypeCreated,
            triggerConfig: ["atomType": "task"],
            conditions: [
                AutomationCondition(field: .createdThisWeek, op: .equals, value: .bool(true))
            ],
            actions: [AutomationAction(type: .moveToCluster, config: ["clusterId": .string(clusterIds[0].uuidString)], label: "Move to This Week")]
        )
        try? await AutomationDispatcher.shared.createRule(weeklyRule)

        return clusterIds
    }
}
