// CosmoOS/Automation/FlowCompiler.swift
// Compiles a flow's run mode into an AutomationRule — the rules engine stays
// the single source of autonomous behavior; the canvas flow is its visible
// skin. Rule uuid is deterministic ("flow-<flowUUID>") so the mapping is 1:1.

import Foundation
import GRDB

@MainActor
enum FlowCompiler {

    static func ruleUUID(for flowUUID: String) -> String {
        "flow-\(flowUUID)"
    }

    /// Sync a flow's run mode to the rules engine. Manual flows have no rule;
    /// arrival flows bind to the cluster's movedToCluster events; daily flows
    /// ride the dispatcher's schedule timer.
    static func sync(_ flow: CanvasFlow, clusterName: String, thinkspaceId: String) async {
        await deleteRule(forFlowUUID: flow.uuid)

        guard flow.runMode != .manual else {
            NotificationCenter.default.post(name: CosmoNotification.Automation.ruleDeleted, object: nil)
            return
        }

        let action = AutomationAction(
            type: .runFlow,
            config: [
                "flowUUID": .string(flow.uuid),
                "thinkspaceId": .string(thinkspaceId)
            ],
            label: "Run \(flow.verb.displayName) flow from \(clusterName)"
        )

        var rule: AutomationRule
        switch flow.runMode {
        case .onArrival:
            rule = AutomationRule.create(
                name: "Flow: \(flow.verb.displayName) from \(clusterName)",
                scope: .cluster,
                scopeId: flow.sourceClusterId,
                triggerType: .movedToCluster,
                triggerConfig: ["clusterId": flow.sourceClusterId],
                actions: [action],
                priority: 60,
                // Captures arrive in bursts (Telegram drains, drags of several
                // blocks) — one distillation per burst, not one per block.
                cooldownSeconds: 300
            )
        case .daily:
            rule = AutomationRule.create(
                name: "Flow: daily \(flow.verb.displayName) of \(clusterName)",
                scope: .global,
                triggerType: .schedule,
                triggerConfig: ["cron": "0 9 * * *"],
                actions: [action],
                priority: 60,
                cooldownSeconds: 0
            )
        case .manual:
            return
        }

        rule.uuid = ruleUUID(for: flow.uuid)

        do {
            var record = rule
            try await CosmoDatabase.shared.asyncWrite { db in
                try record.insert(db)
            }
            NotificationCenter.default.post(name: CosmoNotification.Automation.ruleCreated, object: nil)
        } catch {
            print("❌ FlowCompiler failed to save rule: \(error)")
        }
    }

    /// Remove the rule backing a flow (flow deleted or set to manual).
    static func deleteRule(forFlowUUID flowUUID: String) async {
        let uuid = ruleUUID(for: flowUUID)
        _ = try? await CosmoDatabase.shared.asyncWrite { db in
            try AutomationRule
                .filter(Column("uuid") == uuid)
                .deleteAll(db)
        }
    }
}
