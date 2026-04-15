// CosmoOS/Automation/AutomationRule.swift
// GRDB model + enums for the automation engine
// Rules are stored as AtomType.automation atoms for sync, with a performance index table

import GRDB
import Foundation

// MARK: - AutomationRule (GRDB Performance Index)

/// Fast-lookup index for automation rules, parallel to the automation Atom.
/// Pattern follows graph_nodes/graph_edges — canonical data in atoms, optimized index here.
struct AutomationRule: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "automation_rules"

    var id: Int64?
    var uuid: String                      // Matches companion Atom UUID
    var name: String
    var isEnabled: Bool

    // Scope
    var scope: AutomationScope
    var scopeId: String?                  // Thinkspace/cluster UUID (nil for global)

    // Trigger
    var triggerType: AutomationTriggerType
    var triggerConfig: String             // JSON — trigger-specific params

    // Conditions
    var conditions: String?               // JSON array of AutomationCondition
    var conditionLogic: ConditionLogic

    // Actions
    var actions: String                   // JSON array of AutomationAction

    // Execution control
    var priority: Int                     // Lower = higher priority (conflict resolution)
    var cooldownSeconds: Int              // Min seconds between firings (0 = none)
    var lastFiredAt: String?
    var fireCount: Int64
    var maxFires: Int64?                  // nil = unlimited

    // System
    var isBuiltIn: Bool
    var createdAt: String
    var updatedAt: String

    // MARK: - GRDB Columns

    enum Columns: String, ColumnExpression {
        case id, uuid, name, isEnabled
        case scope, scopeId
        case triggerType, triggerConfig
        case conditions, conditionLogic
        case actions
        case priority, cooldownSeconds, lastFiredAt, fireCount, maxFires
        case isBuiltIn, createdAt, updatedAt
    }

    // MARK: - Convenience

    /// Decode the conditions JSON into typed array
    var parsedConditions: [AutomationCondition] {
        guard let data = conditions?.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([AutomationCondition].self, from: data)) ?? []
    }

    /// Decode the actions JSON into typed array
    var parsedActions: [AutomationAction] {
        guard let data = actions.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([AutomationAction].self, from: data)) ?? []
    }

    /// Decode trigger config into dictionary
    var parsedTriggerConfig: [String: String] {
        guard let data = triggerConfig.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    /// Check if the rule is within its cooldown period
    var isInCooldown: Bool {
        guard cooldownSeconds > 0, let lastFired = lastFiredAt else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: lastFired) else { return false }
        return Date().timeIntervalSince(date) < Double(cooldownSeconds)
    }

    /// Check if the rule has hit its max fires limit
    var isExhausted: Bool {
        guard let max = maxFires else { return false }
        return fireCount >= max
    }

    /// Whether this rule can currently fire
    var canFire: Bool {
        isEnabled && !isInCooldown && !isExhausted
    }

    // MARK: - Factory

    static func create(
        name: String,
        scope: AutomationScope = .global,
        scopeId: String? = nil,
        triggerType: AutomationTriggerType,
        triggerConfig: [String: String] = [:],
        conditions: [AutomationCondition] = [],
        conditionLogic: ConditionLogic = .all,
        actions: [AutomationAction],
        priority: Int = 50,
        cooldownSeconds: Int = 1,
        isBuiltIn: Bool = false
    ) -> AutomationRule {
        let uuid = UUID().uuidString
        let now = ISO8601DateFormatter().string(from: Date())
        let encoder = JSONEncoder()

        let triggerJSON = (try? String(data: encoder.encode(triggerConfig), encoding: .utf8)) ?? "{}"
        let conditionsJSON = conditions.isEmpty ? nil : (try? String(data: encoder.encode(conditions), encoding: .utf8))
        let actionsJSON = (try? String(data: encoder.encode(actions), encoding: .utf8)) ?? "[]"

        return AutomationRule(
            id: nil,
            uuid: uuid,
            name: name,
            isEnabled: true,
            scope: scope,
            scopeId: scopeId,
            triggerType: triggerType,
            triggerConfig: triggerJSON,
            conditions: conditionsJSON,
            conditionLogic: conditionLogic,
            actions: actionsJSON,
            priority: priority,
            cooldownSeconds: cooldownSeconds,
            lastFiredAt: nil,
            fireCount: 0,
            maxFires: nil,
            isBuiltIn: isBuiltIn,
            createdAt: now,
            updatedAt: now
        )
    }
}

// MARK: - Automation Scope

enum AutomationScope: String, Codable, Sendable, CaseIterable {
    case global       // Fires for any thinkspace
    case thinkspace   // Only within a specific thinkspace
    case cluster      // Only for atoms within a specific cluster
}

// MARK: - Condition Logic

enum ConditionLogic: String, Codable, Sendable {
    case all  // AND — all conditions must be true
    case any  // OR — at least one condition must be true
}

// MARK: - Trigger Types

enum AutomationTriggerType: String, Codable, CaseIterable, Sendable {
    // Atom lifecycle
    case atomCreated = "atom_created"
    case atomUpdated = "atom_updated"
    case atomDeleted = "atom_deleted"
    case atomTypeCreated = "atom_type_created"     // config: {"atomType": "idea"}

    // Status transitions
    case statusChanged = "status_changed"
    case phaseAdvanced = "phase_advanced"

    // Link events
    case linkCreated = "link_created"
    case linkRemoved = "link_removed"

    // Spatial events
    case movedToCluster = "moved_to_cluster"
    case removedFromCluster = "removed_from_cluster"
    case addedToThinkspace = "added_to_thinkspace"

    // Time-based
    case schedule = "schedule"                       // config: {"cron": "0 9 * * *"}

    // Threshold-based
    case bodyLengthExceeds = "body_length_exceeds"     // config: {"threshold": "200"}
    case linkCountReaches = "link_count_reaches"       // config: {"count": "3"}

    // Entity events
    case clientAssigned = "client_assigned"             // Atom linked to a client profile
    case analysisComplete = "analysis_complete"         // IdeaInsightEngine finished

    // Compound
    case atomPropertyMatch = "atom_property_match"

    /// Human-readable description for UI
    var displayName: String {
        switch self {
        case .atomCreated: return "Any atom is created"
        case .atomUpdated: return "Any atom is updated"
        case .atomDeleted: return "An atom is deleted"
        case .atomTypeCreated: return "A specific type is created"
        case .statusChanged: return "Status changes"
        case .phaseAdvanced: return "Pipeline phase advances"
        case .linkCreated: return "A link is created"
        case .linkRemoved: return "A link is removed"
        case .movedToCluster: return "Block moves to cluster"
        case .removedFromCluster: return "Block leaves cluster"
        case .addedToThinkspace: return "Block added to thinkspace"
        case .schedule: return "On a schedule"
        case .bodyLengthExceeds: return "Body length exceeds threshold"
        case .linkCountReaches: return "Link count reaches threshold"
        case .clientAssigned: return "Client assigned"
        case .analysisComplete: return "Analysis completed"
        case .atomPropertyMatch: return "Atom matches criteria"
        }
    }
}

// MARK: - Conditions

struct AutomationCondition: Codable, Sendable, Equatable {
    var field: ConditionField
    var op: ConditionOperator
    var value: ConditionValue
    var negate: Bool

    init(field: ConditionField, op: ConditionOperator, value: ConditionValue, negate: Bool = false) {
        self.field = field
        self.op = op
        self.value = value
        self.negate = negate
    }
}

enum ConditionField: String, Codable, Sendable, CaseIterable {
    // Atom properties
    case atomType = "atom_type"
    case atomTitle = "atom_title"
    case atomBody = "atom_body"
    case atomStatus = "atom_status"
    case ideaStatus = "idea_status"
    case contentPhase = "content_phase"
    case taskIntent = "task_intent"
    case taskStatus = "task_status"
    case atomClientUUID = "atom_client_uuid"
    case atomPlatform = "atom_platform"
    case atomContentFormat = "atom_content_format"
    case atomTag = "atom_tag"
    case captureSource = "capture_source"

    // Spatial context
    case isInCluster = "is_in_cluster"
    case clusterName = "cluster_name"
    case clusterColorIndex = "cluster_color_index"
    case thinkspaceId = "thinkspace_id"
    case thinkspaceName = "thinkspace_name"

    // Link context
    case hasLinkOfType = "has_link_of_type"
    case linkedAtomType = "linked_atom_type"
    case linkCount = "link_count"

    // Time context
    case dayOfWeek = "day_of_week"
    case hourOfDay = "hour_of_day"
    case timeSinceCreated = "time_since_created"
    case timeSinceUpdated = "time_since_updated"

    // Content metrics
    case bodyLength = "body_length"
    case linkedSwipeCount = "linked_swipe_count"
    case clientName = "client_name"              // Fuzzy match by name, not UUID
    case createdToday = "created_today"          // Bool — was created today
    case createdThisWeek = "created_this_week"   // Bool — was created this week

    // Graph metrics
    case pageRank = "page_rank"
    case inDegree = "in_degree"
    case outDegree = "out_degree"

    /// Human-readable display name
    var displayName: String {
        switch self {
        case .atomType: return "Type"
        case .atomTitle: return "Title"
        case .atomBody: return "Body"
        case .atomStatus: return "Status"
        case .ideaStatus: return "Idea status"
        case .contentPhase: return "Content phase"
        case .taskIntent: return "Task intent"
        case .taskStatus: return "Task status"
        case .atomClientUUID: return "Client"
        case .atomPlatform: return "Platform"
        case .atomContentFormat: return "Content format"
        case .atomTag: return "Tag"
        case .captureSource: return "Capture source"
        case .isInCluster: return "Is in cluster"
        case .clusterName: return "Cluster name"
        case .clusterColorIndex: return "Cluster color"
        case .thinkspaceId: return "Thinkspace"
        case .thinkspaceName: return "Thinkspace name"
        case .hasLinkOfType: return "Has link type"
        case .linkedAtomType: return "Linked to type"
        case .linkCount: return "Link count"
        case .dayOfWeek: return "Day of week"
        case .hourOfDay: return "Hour of day"
        case .timeSinceCreated: return "Time since created"
        case .timeSinceUpdated: return "Time since updated"
        case .bodyLength: return "Body length"
        case .linkedSwipeCount: return "Linked swipe count"
        case .clientName: return "Client name"
        case .createdToday: return "Created today"
        case .createdThisWeek: return "Created this week"
        case .pageRank: return "PageRank"
        case .inDegree: return "In-degree"
        case .outDegree: return "Out-degree"
        }
    }
}

enum ConditionOperator: String, Codable, Sendable, CaseIterable {
    case equals = "equals"
    case notEquals = "not_equals"
    case contains = "contains"
    case notContains = "not_contains"
    case greaterThan = "greater_than"
    case lessThan = "less_than"
    case isSet = "is_set"
    case isNotSet = "is_not_set"
    case `in` = "in"
    case notIn = "not_in"

    var displayName: String {
        switch self {
        case .equals: return "is"
        case .notEquals: return "is not"
        case .contains: return "contains"
        case .notContains: return "does not contain"
        case .greaterThan: return "is greater than"
        case .lessThan: return "is less than"
        case .isSet: return "is set"
        case .isNotSet: return "is not set"
        case .in: return "is one of"
        case .notIn: return "is not one of"
        }
    }
}

enum ConditionValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case stringArray([String])

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case type, value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "string":
            self = .string(try container.decode(String.self, forKey: .value))
        case "number":
            self = .number(try container.decode(Double.self, forKey: .value))
        case "bool":
            self = .bool(try container.decode(Bool.self, forKey: .value))
        case "stringArray":
            self = .stringArray(try container.decode([String].self, forKey: .value))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown ConditionValue type: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let v):
            try container.encode("string", forKey: .type)
            try container.encode(v, forKey: .value)
        case .number(let v):
            try container.encode("number", forKey: .type)
            try container.encode(v, forKey: .value)
        case .bool(let v):
            try container.encode("bool", forKey: .type)
            try container.encode(v, forKey: .value)
        case .stringArray(let v):
            try container.encode("stringArray", forKey: .type)
            try container.encode(v, forKey: .value)
        }
    }

    /// Extract string value (returns nil for non-string types)
    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    /// Extract number value (returns nil for non-number types)
    var numberValue: Double? {
        if case .number(let v) = self { return v }
        return nil
    }

    /// Extract bool value (returns nil for non-bool types)
    var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }

    /// Extract string array (returns nil for non-array types)
    var stringArrayValue: [String]? {
        if case .stringArray(let v) = self { return v }
        return nil
    }
}

// MARK: - Actions

enum AutomationActionType: String, Codable, CaseIterable, Sendable {
    // Status mutations
    case setStatus = "set_status"
    case setField = "set_field"
    case addTag = "add_tag"
    case removeTag = "remove_tag"

    // Spatial actions
    case moveToCluster = "move_to_cluster"
    case removeFromCluster = "remove_from_cluster"
    case placeOnCanvas = "place_on_canvas"
    case moveToThinkspace = "move_to_thinkspace"

    // Link actions
    case createLink = "create_link"
    case removeLink = "remove_link"

    // Creation
    case createAtom = "create_atom"
    case duplicateAtom = "duplicate_atom"

    // Notifications
    case showNotification = "show_notification"
    case sendTelegram = "send_telegram"

    // AI actions
    case runAnalysis = "run_analysis"
    case askCosmo = "ask_cosmo"

    // Pipeline actions
    case advancePipeline = "advance_pipeline"    // Move content to next phase
    case generateOutline = "generate_outline"    // Auto-generate outline for content
    case assignToClient = "assign_to_client"     // Link atom to client profile
    case archiveAtom = "archive_atom"            // Soft-delete / archive

    // Task creation
    case createTask = "create_task"              // Create a task linked to triggering atom

    // Gamification
    case awardXP = "award_xp"                   // Award XP for automated action

    // Template instantiation
    case instantiateTemplate = "instantiate_template"  // Spawn a template instance

    // Visual feedback
    case highlightCluster = "highlight_cluster"
    case pulseBlock = "pulse_block"

    /// Whether this action modifies spatial state (canvas blocks, clusters)
    var isSpatialAction: Bool {
        switch self {
        case .moveToCluster, .removeFromCluster, .placeOnCanvas, .moveToThinkspace,
             .highlightCluster, .pulseBlock, .instantiateTemplate:
            return true
        default:
            return false
        }
    }

    /// Whether this action affects the content pipeline
    var isPipelineAction: Bool {
        switch self {
        case .advancePipeline, .generateOutline, .archiveAtom:
            return true
        default:
            return false
        }
    }

    var displayName: String {
        switch self {
        case .setStatus: return "Set status"
        case .setField: return "Set field"
        case .addTag: return "Add tag"
        case .removeTag: return "Remove tag"
        case .moveToCluster: return "Move to cluster"
        case .removeFromCluster: return "Remove from cluster"
        case .placeOnCanvas: return "Place on canvas"
        case .moveToThinkspace: return "Move to thinkspace"
        case .createLink: return "Create link"
        case .removeLink: return "Remove link"
        case .createAtom: return "Create atom"
        case .duplicateAtom: return "Duplicate"
        case .showNotification: return "Show notification"
        case .sendTelegram: return "Send Telegram message"
        case .runAnalysis: return "Run analysis"
        case .askCosmo: return "Ask Cosmo"
        case .advancePipeline: return "Advance pipeline phase"
        case .generateOutline: return "Generate outline"
        case .assignToClient: return "Assign to client"
        case .archiveAtom: return "Archive"
        case .createTask: return "Create task"
        case .awardXP: return "Award XP"
        case .instantiateTemplate: return "Instantiate template"
        case .highlightCluster: return "Highlight cluster"
        case .pulseBlock: return "Pulse block"
        }
    }
}

struct AutomationAction: Codable, Sendable, Equatable {
    var type: AutomationActionType
    var config: [String: ConditionValue]
    var label: String?

    init(type: AutomationActionType, config: [String: ConditionValue] = [:], label: String? = nil) {
        self.type = type
        self.config = config
        self.label = label
    }

    /// Get a string config value by key
    func configString(_ key: String) -> String? {
        config[key]?.stringValue
    }

    /// Get a number config value by key
    func configNumber(_ key: String) -> Double? {
        config[key]?.numberValue
    }
}

// MARK: - Automation Event

/// Typed event dispatched through the automation pipeline
struct AutomationEvent: Sendable {
    let triggerType: AutomationTriggerType
    let atomUUID: String
    let atomType: String?
    let thinkspaceId: String?
    let previousValue: String?
    let newValue: String?
    let isFromSync: Bool                 // True if this event came from cloud sync catch-up
    let timestamp: Date

    init(
        triggerType: AutomationTriggerType,
        atomUUID: String,
        atomType: String? = nil,
        thinkspaceId: String? = nil,
        previousValue: String? = nil,
        newValue: String? = nil,
        isFromSync: Bool = false
    ) {
        self.triggerType = triggerType
        self.atomUUID = atomUUID
        self.atomType = atomType
        self.thinkspaceId = thinkspaceId
        self.previousValue = previousValue
        self.newValue = newValue
        self.isFromSync = isFromSync
        self.timestamp = Date()
    }
}

// MARK: - Natural Language Description

extension AutomationRule {
    /// Generate a human-readable description of this rule for display in the management UI
    var naturalLanguageDescription: String {
        var parts: [String] = []

        // Trigger
        let triggerDesc: String
        switch triggerType {
        case .atomTypeCreated:
            let atomType = parsedTriggerConfig["atomType"] ?? "atom"
            triggerDesc = "When \(atomType) is created"
        case .statusChanged:
            let status = parsedTriggerConfig["status"] ?? "any status"
            triggerDesc = "When status changes to \(status)"
        case .linkCreated:
            triggerDesc = "When a link is created"
        case .movedToCluster:
            triggerDesc = "When block moves to cluster"
        case .schedule:
            triggerDesc = "On schedule"
        default:
            triggerDesc = "When \(triggerType.displayName.lowercased())"
        }
        parts.append(triggerDesc)

        // Conditions
        let conds = parsedConditions
        if !conds.isEmpty {
            let condDescs = conds.map { cond in
                "\(cond.field.displayName) \(cond.op.displayName) \(cond.value.stringValue ?? "...")"
            }
            parts.append("if \(condDescs.joined(separator: " and "))")
        }

        // Actions
        let acts = parsedActions
        if !acts.isEmpty {
            let actDescs = acts.map { $0.label ?? $0.type.displayName }
            parts.append("→ \(actDescs.joined(separator: ", "))")
        }

        return parts.joined(separator: " ")
    }
}
