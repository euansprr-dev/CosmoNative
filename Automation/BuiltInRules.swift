// CosmoOS/Automation/BuiltInRules.swift
// Factory for 5 default hygiene rules — shipped disabled, suggested on first meaningful use

import Foundation
import GRDB

enum BuiltInRules {

    /// All built-in rule definitions. Created disabled by default.
    static func allRules() -> [AutomationRule] {
        [
            autoEnrichIdeas(),
            staleContentNudge(),
            sparkAutoAdvance(),
            autoLinkClusterNeighbors(),
            telegramCaptureRouting(),
        ]
    }

    /// Seed built-in rules into the database if they don't already exist
    @MainActor
    static func seedIfNeeded() async {
        guard let db = CosmoDatabase.shared.dbQueue else { return }

        do {
            let existingCount = try await db.read { db in
                try AutomationRule
                    .filter(sql: "isBuiltIn = 1")
                    .fetchCount(db)
            }

            guard existingCount == 0 else { return }

            let rules = allRules()
            try await db.write { db in
                for var rule in rules {
                    try rule.insert(db)
                }
            }

            print("⚡ [BuiltInRules] Seeded \(rules.count) built-in rules (all disabled)")
        } catch {
            print("⚡ [BuiltInRules] Failed to seed: \(error.localizedDescription)")
        }
    }

    // MARK: - Rule Definitions

    /// When an idea is created with body > 50 chars, trigger quick enrichment analysis
    private static func autoEnrichIdeas() -> AutomationRule {
        AutomationRule.create(
            name: "Auto-enrich ideas",
            scope: .global,
            triggerType: .atomTypeCreated,
            triggerConfig: ["atomType": "idea"],
            conditions: [
                AutomationCondition(
                    field: .atomBody,
                    op: .isSet,
                    value: .bool(true)
                )
            ],
            actions: [
                AutomationAction(
                    type: .runAnalysis,
                    config: ["analysisType": .string("quickEnrich")],
                    label: "Run quick enrichment"
                )
            ],
            priority: 80,
            cooldownSeconds: 30,
            isBuiltIn: true
        )
    }

    /// Daily check: content atoms stuck in the same phase for 48+ hours get a notification
    private static func staleContentNudge() -> AutomationRule {
        AutomationRule.create(
            name: "Stale content nudge",
            scope: .global,
            triggerType: .schedule,
            triggerConfig: ["cron": "0 9 * * *", "intervalSeconds": "86400"],
            conditions: [
                AutomationCondition(
                    field: .atomType,
                    op: .equals,
                    value: .string("content")
                ),
                AutomationCondition(
                    field: .timeSinceUpdated,
                    op: .greaterThan,
                    value: .number(172800) // 48 hours in seconds
                )
            ],
            actions: [
                AutomationAction(
                    type: .showNotification,
                    config: ["message": .string("{{atom.title}} has been in {{atom.status}} for over 2 days")],
                    label: "Show stale content notification"
                )
            ],
            priority: 90,
            cooldownSeconds: 86400, // Once per day per atom
            isBuiltIn: true
        )
    }

    /// When an idea body exceeds 200 chars and has at least 1 linked swipe,
    /// auto-advance from spark to developing
    private static func sparkAutoAdvance() -> AutomationRule {
        AutomationRule.create(
            name: "Spark auto-advance",
            scope: .global,
            triggerType: .atomUpdated,
            triggerConfig: [:],
            conditions: [
                AutomationCondition(
                    field: .atomType,
                    op: .equals,
                    value: .string("idea")
                ),
                AutomationCondition(
                    field: .ideaStatus,
                    op: .equals,
                    value: .string("spark")
                ),
                AutomationCondition(
                    field: .hasLinkOfType,
                    op: .contains,
                    value: .string("idea_to_swipe")
                )
            ],
            actions: [
                AutomationAction(
                    type: .setStatus,
                    config: ["status": .string("developing")],
                    label: "Advance to developing"
                )
            ],
            priority: 70,
            cooldownSeconds: 60,
            isBuiltIn: true
        )
    }

    /// When two unlinked compatible blocks coexist in the same cluster,
    /// suggest a link after a cooldown period
    private static func autoLinkClusterNeighbors() -> AutomationRule {
        AutomationRule.create(
            name: "Auto-link cluster neighbors",
            scope: .global,
            triggerType: .movedToCluster,
            triggerConfig: [:],
            conditions: [
                AutomationCondition(
                    field: .isInCluster,
                    op: .equals,
                    value: .bool(true)
                )
            ],
            actions: [
                AutomationAction(
                    type: .showNotification,
                    config: ["message": .string("Consider linking {{atom.title}} to nearby blocks in this cluster")],
                    label: "Suggest linking neighbors"
                )
            ],
            priority: 95,
            cooldownSeconds: 300, // 5 min per pair
            isBuiltIn: true
        )
    }

    /// When an atom is created from Telegram with a clientUUID,
    /// place it on the client's thinkspace if one exists
    private static func telegramCaptureRouting() -> AutomationRule {
        AutomationRule.create(
            name: "Telegram capture routing",
            scope: .global,
            triggerType: .atomCreated,
            triggerConfig: [:],
            conditions: [
                AutomationCondition(
                    field: .captureSource,
                    op: .equals,
                    value: .string("telegram")
                ),
                AutomationCondition(
                    field: .atomClientUUID,
                    op: .isSet,
                    value: .bool(true)
                )
            ],
            actions: [
                AutomationAction(
                    type: .placeOnCanvas,
                    config: [:],
                    label: "Place on client's thinkspace"
                )
            ],
            priority: 40,
            cooldownSeconds: 0,
            isBuiltIn: true
        )
    }
}

// MARK: - First-Use Prompt

extension BuiltInRules {

    /// Key for tracking whether the user has been prompted
    private static let promptShownKey = "automation_builtin_prompt_shown"

    /// Check if we should show the "Enable smart behaviors?" prompt
    static var shouldShowPrompt: Bool {
        !UserDefaults.standard.bool(forKey: promptShownKey)
    }

    /// Mark the prompt as shown
    static func markPromptShown() {
        UserDefaults.standard.set(true, forKey: promptShownKey)
    }

    /// Enable a set of built-in rules by their UUIDs
    static func enableRules(uuids: [String]) async {
        for uuid in uuids {
            try? await AutomationDispatcher.shared.toggleRule(uuid: uuid)
        }
    }
}
