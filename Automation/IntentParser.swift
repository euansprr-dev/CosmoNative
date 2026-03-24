// CosmoOS/Automation/IntentParser.swift
// Natural language → structured automation rule parser
// Keyword-based extraction with fuzzy client name resolution
// No API call needed — runs instantly on-device

import Foundation

@MainActor
enum IntentParser {

    // MARK: - Full Rule Parsing

    /// Parse a natural language rule description into structured components
    /// Example: "When content for Josh reaches review, move here and ping me on Telegram"
    /// Returns: (triggers, conditions, actions, suggested name)
    static func parseRule(_ input: String) async -> ParsedRule {
        let lower = input.lowercased()
        let tokens = tokenize(lower)

        let triggers = extractTriggers(tokens: tokens, raw: lower)
        let conditions = await extractConditions(tokens: tokens, raw: lower)
        let actions = extractActions(tokens: tokens, raw: lower)
        let name = generateName(triggers: triggers, conditions: conditions, actions: actions)

        return ParsedRule(
            triggers: triggers,
            conditions: conditions,
            actions: actions,
            suggestedName: name,
            confidence: calculateConfidence(triggers: triggers, conditions: conditions, actions: actions)
        )
    }

    /// Parse a cluster intent description into automation rules
    /// Example: "Josh's content ready for review"
    /// Returns rules that will attract matching atoms to this cluster
    static func parseClusterIntent(_ intent: String, clusterId: String) async -> [AutomationRule] {
        let lower = intent.lowercased()
        let tokens = tokenize(lower)

        var conditions = await extractConditions(tokens: tokens, raw: lower)

        // If no atom type detected, infer from keywords
        if !conditions.contains(where: { $0.field == .atomType }) {
            if let inferredType = inferAtomType(from: tokens) {
                conditions.append(AutomationCondition(
                    field: .atomType,
                    op: .equals,
                    value: .string(inferredType)
                ))
            }
        }

        // Default trigger: when matching atoms are created
        let triggerType: AutomationTriggerType
        if conditions.contains(where: { $0.field == .atomType }),
           let typeCondition = conditions.first(where: { $0.field == .atomType }),
           let atomType = typeCondition.value.stringValue {
            triggerType = .atomTypeCreated
            let triggerConfig: [String: String] = ["atomType": atomType]

            let rule = AutomationRule.create(
                name: "Collect: \(intent)",
                scope: .global,
                scopeId: nil,
                triggerType: triggerType,
                triggerConfig: triggerConfig,
                conditions: conditions.filter { $0.field != .atomType }, // Type is in trigger, not condition
                actions: [
                    AutomationAction(
                        type: .moveToCluster,
                        config: ["clusterId": .string(clusterId)],
                        label: "Move to cluster"
                    )
                ]
            )
            return [rule]
        } else {
            // Generic: trigger on any atom created, filter by conditions
            let rule = AutomationRule.create(
                name: "Collect: \(intent)",
                scope: .global,
                triggerType: .atomCreated,
                conditions: conditions,
                actions: [
                    AutomationAction(
                        type: .moveToCluster,
                        config: ["clusterId": .string(clusterId)],
                        label: "Move to cluster"
                    )
                ]
            )
            return [rule]
        }
    }

    // MARK: - Trigger Extraction

    private static func extractTriggers(tokens: [String], raw: String) -> [ParsedTrigger] {
        var triggers: [ParsedTrigger] = []

        // Status change patterns
        let statusPatterns = [
            ("reaches", "status_changed"),
            ("changes to", "status_changed"),
            ("moves to", "status_changed"),
            ("enters", "status_changed"),
            ("becomes", "status_changed"),
            ("advances", "phase_advanced"),
        ]

        for (pattern, type) in statusPatterns {
            if raw.contains(pattern) {
                let targetStatus = extractWordAfter(pattern: pattern, in: raw)
                triggers.append(ParsedTrigger(
                    type: AutomationTriggerType(rawValue: type) ?? .statusChanged,
                    config: targetStatus.map { ["status": $0] } ?? [:],
                    description: "status changes\(targetStatus.map { " to \($0)" } ?? "")"
                ))
                break
            }
        }

        // Creation patterns
        let creationPatterns: [(String, String)] = [
            ("idea is created", "idea"),
            ("idea created", "idea"),
            ("new idea", "idea"),
            ("content is created", "content"),
            ("content created", "content"),
            ("new content", "content"),
            ("swipe is captured", "research"),
            ("swipe captured", "research"),
            ("new swipe", "research"),
            ("research is added", "research"),
            ("research added", "research"),
            ("task is created", "task"),
            ("task created", "task"),
            ("new task", "task"),
        ]

        for (pattern, atomType) in creationPatterns {
            if raw.contains(pattern) {
                triggers.append(ParsedTrigger(
                    type: .atomTypeCreated,
                    config: ["atomType": atomType],
                    description: "\(atomType) is created"
                ))
                break
            }
        }

        // Link patterns
        if raw.contains("linked") || raw.contains("connected") || raw.contains("link is created") {
            triggers.append(ParsedTrigger(type: .linkCreated, config: [:], description: "a link is created"))
        }

        // If no triggers found, default to atomCreated
        if triggers.isEmpty {
            triggers.append(ParsedTrigger(type: .atomCreated, config: [:], description: "any atom is created"))
        }

        return triggers
    }

    // MARK: - Condition Extraction

    private static func extractConditions(tokens: [String], raw: String) async -> [AutomationCondition] {
        var conditions: [AutomationCondition] = []

        // Client detection — "for Josh", "Josh's", "client Josh", "linked to Josh"
        let clientPatterns = [
            "for ([a-zA-Z]+)",
            "([a-zA-Z]+)'s",
            "client ([a-zA-Z]+)",
            "linked to ([a-zA-Z]+)",
            "assigned to ([a-zA-Z]+)",
        ]

        for pattern in clientPatterns {
            if let match = raw.range(of: pattern, options: .regularExpression) {
                let captured = String(raw[match])
                // Extract the name part
                let name = captured
                    .replacingOccurrences(of: "for ", with: "")
                    .replacingOccurrences(of: "'s", with: "")
                    .replacingOccurrences(of: "client ", with: "")
                    .replacingOccurrences(of: "linked to ", with: "")
                    .replacingOccurrences(of: "assigned to ", with: "")
                    .trimmingCharacters(in: .whitespaces)

                // Skip common words that aren't client names
                let skipWords = Set(["the", "this", "that", "here", "there", "me", "my", "it", "review", "draft", "all", "new", "any", "each", "every"])
                if !skipWords.contains(name.lowercased()) && name.count > 1 {
                    // Try to resolve client UUID
                    if let clientUUID = await resolveClientUUID(name: name) {
                        conditions.append(AutomationCondition(
                            field: .atomClientUUID,
                            op: .equals,
                            value: .string(clientUUID)
                        ))
                    } else {
                        // Fall back to name-based matching
                        conditions.append(AutomationCondition(
                            field: .clientName,
                            op: .contains,
                            value: .string(name)
                        ))
                    }
                    break
                }
            }
        }

        // Atom type detection
        let typeMap: [String: String] = [
            "idea": "idea", "ideas": "idea",
            "content": "content",
            "swipe": "research", "swipes": "research",
            "research": "research",
            "task": "task", "tasks": "task",
            "note": "note", "notes": "note",
        ]

        for (keyword, atomType) in typeMap {
            if tokens.contains(keyword) {
                conditions.append(AutomationCondition(
                    field: .atomType,
                    op: .equals,
                    value: .string(atomType)
                ))
                break
            }
        }

        // Status conditions
        let statusKeywords: [String: String] = [
            "review": "polish",
            "draft": "draft",
            "brainstorm": "brainstorm",
            "published": "published",
            "archived": "archived",
            "spark": "spark",
            "developing": "developing",
            "ready": "ready",
        ]

        for (keyword, status) in statusKeywords {
            if tokens.contains(keyword) {
                conditions.append(AutomationCondition(
                    field: .atomStatus,
                    op: .equals,
                    value: .string(status)
                ))
                break
            }
        }

        // Source detection
        if raw.contains("telegram") || raw.contains("from tg") {
            conditions.append(AutomationCondition(
                field: .captureSource,
                op: .equals,
                value: .string("telegram")
            ))
        }

        return conditions
    }

    // MARK: - Action Extraction

    private static func extractActions(tokens: [String], raw: String) -> [AutomationAction] {
        var actions: [AutomationAction] = []

        // Movement actions
        if raw.contains("move") && (raw.contains("here") || raw.contains("this cluster") || raw.contains("cluster")) {
            actions.append(AutomationAction(
                type: .moveToCluster,
                config: [:], // clusterId filled by caller
                label: "Move to cluster"
            ))
        }

        // Status change actions
        if raw.contains("set status") || raw.contains("change status") || raw.contains("mark as") {
            let targetStatus = extractWordAfter(pattern: "set status to", in: raw)
                ?? extractWordAfter(pattern: "change status to", in: raw)
                ?? extractWordAfter(pattern: "mark as", in: raw)
                ?? "developing"
            actions.append(AutomationAction(
                type: .setStatus,
                config: ["status": .string(targetStatus)],
                label: "Set status to \(targetStatus)"
            ))
        }

        // Pipeline advancement
        if raw.contains("advance") || raw.contains("next phase") || raw.contains("move to next") {
            actions.append(AutomationAction(
                type: .advancePipeline,
                config: [:],
                label: "Advance pipeline phase"
            ))
        }

        // Notification actions
        if raw.contains("notify") || raw.contains("alert") || raw.contains("ping") || raw.contains("tell me") {
            if raw.contains("telegram") || raw.contains("tg") {
                actions.append(AutomationAction(
                    type: .sendTelegram,
                    config: ["message": .string("⚡ {{atom.title}} — automation fired")],
                    label: "Send Telegram notification"
                ))
            } else {
                actions.append(AutomationAction(
                    type: .showNotification,
                    config: ["message": .string("{{atom.title}} matched a rule")],
                    label: "Show notification"
                ))
            }
        }

        // Analysis actions
        if raw.contains("analyz") || raw.contains("enrich") || raw.contains("run analysis") {
            actions.append(AutomationAction(
                type: .runAnalysis,
                config: ["analysisType": .string("fullAnalysis")],
                label: "Run full analysis"
            ))
        }

        // Outline generation
        if raw.contains("outline") || raw.contains("generate outline") {
            actions.append(AutomationAction(
                type: .generateOutline,
                config: [:],
                label: "Generate outline"
            ))
        }

        // Archive
        if raw.contains("archive") || raw.contains("remove") || raw.contains("clean up") {
            actions.append(AutomationAction(
                type: .archiveAtom,
                config: [:],
                label: "Archive"
            ))
        }

        // XP
        if raw.contains("award") || raw.contains("xp") || raw.contains("points") {
            actions.append(AutomationAction(
                type: .awardXP,
                config: ["amount": .number(10), "dimension": .string("creative")],
                label: "Award 10 XP"
            ))
        }

        // Task creation
        if raw.contains("create task") || raw.contains("add task") || raw.contains("remind") {
            actions.append(AutomationAction(
                type: .createTask,
                config: ["title": .string("Review {{atom.title}}")],
                label: "Create review task"
            ))
        }

        // Default: show notification if nothing else matched
        if actions.isEmpty {
            actions.append(AutomationAction(
                type: .showNotification,
                config: ["message": .string("Rule fired for {{atom.title}}")],
                label: "Show notification"
            ))
        }

        return actions
    }

    // MARK: - Client Resolution

    private static func resolveClientUUID(name: String) async -> String? {
        guard !name.isEmpty else { return nil }

        do {
            let clients = try await AtomRepository.shared.fetchAll(type: .clientProfile)
            // Fuzzy match: case-insensitive contains
            let match = clients.first { client in
                guard let title = client.title else { return false }
                return title.localizedCaseInsensitiveContains(name)
            }
            return match?.uuid
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    private static func tokenize(_ input: String) -> [String] {
        input.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
    }

    private static func extractWordAfter(pattern: String, in text: String) -> String? {
        guard let range = text.range(of: pattern) else { return nil }
        let after = text[range.upperBound...]
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces)
            .first?
            .trimmingCharacters(in: .punctuationCharacters)
        return after?.isEmpty == true ? nil : after
    }

    private static func inferAtomType(from tokens: [String]) -> String? {
        let typeMap: [String: String] = [
            "idea": "idea", "ideas": "idea",
            "content": "content", "post": "content", "posts": "content",
            "swipe": "research", "swipes": "research",
            "research": "research",
            "task": "task", "tasks": "task",
            "note": "note", "notes": "note",
        ]
        for token in tokens {
            if let type = typeMap[token] { return type }
        }
        return nil
    }

    private static func generateName(triggers: [ParsedTrigger], conditions: [AutomationCondition], actions: [AutomationAction]) -> String {
        let triggerPart = triggers.first?.description ?? "event"
        let actionPart = actions.first?.label ?? "action"
        return "\(triggerPart) → \(actionPart)"
    }

    private static func calculateConfidence(triggers: [ParsedTrigger], conditions: [AutomationCondition], actions: [AutomationAction]) -> Double {
        var score = 0.0
        if !triggers.isEmpty { score += 0.3 }
        if !conditions.isEmpty { score += 0.3 }
        if !actions.isEmpty { score += 0.3 }
        if triggers.count + conditions.count + actions.count > 3 { score += 0.1 }
        return min(score, 1.0)
    }
}

// MARK: - Parsed Types

struct ParsedRule {
    let triggers: [ParsedTrigger]
    let conditions: [AutomationCondition]
    let actions: [AutomationAction]
    let suggestedName: String
    let confidence: Double // 0-1, how confident the parser is

    /// Convert to an AutomationRule ready for creation
    func toRule(scope: AutomationScope = .global, scopeId: String? = nil, clusterId: String? = nil) -> AutomationRule {
        let trigger = triggers.first ?? ParsedTrigger(type: .atomCreated, config: [:], description: "atom created")

        // If there's a moveToCluster action without a clusterId, fill it from the caller
        var finalActions = actions
        if let cid = clusterId {
            finalActions = actions.map { action in
                if action.type == .moveToCluster && action.configString("clusterId") == nil {
                    return AutomationAction(
                        type: .moveToCluster,
                        config: ["clusterId": .string(cid)],
                        label: action.label
                    )
                }
                return action
            }
        }

        return AutomationRule.create(
            name: suggestedName,
            scope: scope,
            scopeId: scopeId,
            triggerType: trigger.type,
            triggerConfig: trigger.config,
            conditions: conditions,
            actions: finalActions
        )
    }
}

struct ParsedTrigger {
    let type: AutomationTriggerType
    let config: [String: String]
    let description: String
}
