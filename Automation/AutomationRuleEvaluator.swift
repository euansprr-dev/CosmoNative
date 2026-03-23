// CosmoOS/Automation/AutomationRuleEvaluator.swift
// Pure condition evaluation engine — no side effects

import Foundation

struct AutomationRuleEvaluator: Sendable {

    /// Evaluate whether a rule's conditions are met given the context
    func evaluate(rule: AutomationRule, context: AutomationContext) -> Bool {
        let conditions = rule.parsedConditions
        guard !conditions.isEmpty else { return true } // No conditions = always matches

        switch rule.conditionLogic {
        case .all:
            return conditions.allSatisfy { evaluateCondition($0, context: context) }
        case .any:
            return conditions.contains { evaluateCondition($0, context: context) }
        }
    }

    /// Check if the trigger config matches the event
    func triggerMatches(rule: AutomationRule, event: AutomationEvent) -> Bool {
        guard rule.triggerType == event.triggerType else { return false }

        let config = rule.parsedTriggerConfig

        switch rule.triggerType {
        case .atomTypeCreated:
            // Config specifies which atom type to match
            guard let requiredType = config["atomType"] else { return true }
            return event.atomType == requiredType

        case .statusChanged:
            // Optionally filter to a specific target status
            if let targetStatus = config["status"] {
                return event.newValue == targetStatus
            }
            return true

        case .phaseAdvanced:
            // Any forward phase movement
            return true

        case .linkCreated, .linkRemoved:
            // Optionally filter by link type
            if let linkType = config["linkType"] {
                return event.newValue == linkType
            }
            return true

        case .movedToCluster:
            // Optionally filter by target cluster ID
            if let clusterId = config["clusterId"] {
                return event.newValue == clusterId
            }
            return true

        case .addedToThinkspace:
            // Optionally filter by thinkspace ID
            if let tsId = config["thinkspaceId"] {
                return event.thinkspaceId == tsId
            }
            return true

        default:
            return true
        }
    }

    /// Check if a rule's scope matches the event context
    func scopeMatches(rule: AutomationRule, context: AutomationContext) -> Bool {
        switch rule.scope {
        case .global:
            return true

        case .thinkspace:
            guard let scopeId = rule.scopeId else { return true }
            return context.thinkspaceId == scopeId

        case .cluster:
            guard let scopeId = rule.scopeId else { return true }
            return context.clusterMembership.contains(scopeId)
        }
    }

    // MARK: - Condition Evaluation

    private func evaluateCondition(_ condition: AutomationCondition, context: AutomationContext) -> Bool {
        let result = evaluateRaw(condition, context: context)
        return condition.negate ? !result : result
    }

    private func evaluateRaw(_ condition: AutomationCondition, context: AutomationContext) -> Bool {
        let atom = context.atom

        switch condition.field {
        // MARK: Atom Properties
        case .atomType:
            return compareString(atom.type, op: condition.op, value: condition.value)

        case .atomTitle:
            return compareString(atom.title, op: condition.op, value: condition.value)

        case .atomBody:
            return compareString(atom.body, op: condition.op, value: condition.value)

        case .atomStatus, .ideaStatus, .contentPhase, .taskStatus:
            return compareString(atom.status ?? "", op: condition.op, value: condition.value)

        case .taskIntent:
            // Would need to extract from metadata — treat as status for now
            return compareString(atom.status ?? "", op: condition.op, value: condition.value)

        case .atomClientUUID:
            return compareString(atom.clientUUID ?? "", op: condition.op, value: condition.value)

        case .atomPlatform:
            return compareString(atom.platform ?? "", op: condition.op, value: condition.value)

        case .atomContentFormat:
            return compareString(atom.contentFormat ?? "", op: condition.op, value: condition.value)

        case .atomTag:
            return evaluateTag(atom.tags, op: condition.op, value: condition.value)

        case .captureSource:
            return compareString(atom.captureSource ?? "", op: condition.op, value: condition.value)

        // MARK: Spatial Context
        case .isInCluster:
            let isInCluster = !context.clusterMembership.isEmpty
            if case .bool(let expected) = condition.value {
                return isInCluster == expected
            }
            // If value is a cluster ID string, check membership
            if case .string(let clusterId) = condition.value {
                return context.clusterMembership.contains(clusterId)
            }
            return isInCluster

        case .clusterName:
            let names = Array(context.clusterNames.values)
            return evaluateArrayContains(names, op: condition.op, value: condition.value)

        case .clusterColorIndex:
            // Not commonly used in conditions, but supported
            return false

        case .thinkspaceId:
            return compareString(context.thinkspaceId ?? "", op: condition.op, value: condition.value)

        case .thinkspaceName:
            // Would need thinkspace name in context — not currently available
            return false

        // MARK: Link Context
        case .hasLinkOfType:
            return evaluateArrayContains(atom.linkTypes, op: condition.op, value: condition.value)

        case .linkedAtomType:
            return evaluateArrayContains(context.linkedAtomTypes, op: condition.op, value: condition.value)

        case .linkCount:
            return compareNumber(Double(atom.linkCount), op: condition.op, value: condition.value)

        // MARK: Time Context
        case .dayOfWeek:
            let day = Calendar.current.component(.weekday, from: Date())
            return compareNumber(Double(day), op: condition.op, value: condition.value)

        case .hourOfDay:
            let hour = Calendar.current.component(.hour, from: Date())
            return compareNumber(Double(hour), op: condition.op, value: condition.value)

        case .timeSinceCreated:
            return compareTimeSince(atom.createdAt, op: condition.op, value: condition.value)

        case .timeSinceUpdated:
            return compareTimeSince(atom.updatedAt, op: condition.op, value: condition.value)

        // MARK: Graph Metrics
        case .pageRank, .inDegree, .outDegree:
            // Would need graph data in context — not currently passed
            return false
        }
    }

    // MARK: - Comparison Helpers

    private func compareString(_ actual: String, op: ConditionOperator, value: ConditionValue) -> Bool {
        switch op {
        case .equals:
            guard let expected = value.stringValue else { return false }
            return actual.lowercased() == expected.lowercased()

        case .notEquals:
            guard let expected = value.stringValue else { return false }
            return actual.lowercased() != expected.lowercased()

        case .contains:
            guard let substring = value.stringValue else { return false }
            return actual.lowercased().contains(substring.lowercased())

        case .notContains:
            guard let substring = value.stringValue else { return false }
            return !actual.lowercased().contains(substring.lowercased())

        case .isSet:
            return !actual.isEmpty

        case .isNotSet:
            return actual.isEmpty

        case .in:
            guard let array = value.stringArrayValue else { return false }
            return array.contains { $0.lowercased() == actual.lowercased() }

        case .notIn:
            guard let array = value.stringArrayValue else { return false }
            return !array.contains { $0.lowercased() == actual.lowercased() }

        case .greaterThan, .lessThan:
            return false // Not applicable to strings
        }
    }

    private func compareNumber(_ actual: Double, op: ConditionOperator, value: ConditionValue) -> Bool {
        guard let expected = value.numberValue else { return false }

        switch op {
        case .equals:
            return actual == expected
        case .notEquals:
            return actual != expected
        case .greaterThan:
            return actual > expected
        case .lessThan:
            return actual < expected
        case .isSet:
            return true
        case .isNotSet:
            return false
        default:
            return false
        }
    }

    private func evaluateTag(_ tags: [String], op: ConditionOperator, value: ConditionValue) -> Bool {
        switch op {
        case .contains:
            guard let tag = value.stringValue else { return false }
            return tags.contains { $0.lowercased() == tag.lowercased() }
        case .notContains:
            guard let tag = value.stringValue else { return false }
            return !tags.contains { $0.lowercased() == tag.lowercased() }
        case .isSet:
            return !tags.isEmpty
        case .isNotSet:
            return tags.isEmpty
        default:
            return false
        }
    }

    private func evaluateArrayContains(_ array: [String], op: ConditionOperator, value: ConditionValue) -> Bool {
        switch op {
        case .contains, .equals:
            guard let target = value.stringValue else { return false }
            return array.contains { $0.lowercased() == target.lowercased() }
        case .notContains, .notEquals:
            guard let target = value.stringValue else { return false }
            return !array.contains { $0.lowercased() == target.lowercased() }
        case .isSet:
            return !array.isEmpty
        case .isNotSet:
            return array.isEmpty
        default:
            return false
        }
    }

    private func compareTimeSince(_ dateString: String, op: ConditionOperator, value: ConditionValue) -> Bool {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let date = formatter.date(from: dateString) else {
            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: dateString) else { return false }
            let seconds = Date().timeIntervalSince(date)
            return compareNumber(seconds, op: op, value: value)
        }

        let seconds = Date().timeIntervalSince(date)
        return compareNumber(seconds, op: op, value: value)
    }
}
