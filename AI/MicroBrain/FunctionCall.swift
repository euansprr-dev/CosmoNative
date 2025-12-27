// CosmoOS/AI/MicroBrain/FunctionCall.swift
// Data structures for FunctionGemma output parsing
// Part of the Micro-Brain architecture

import Foundation

// MARK: - Function Call

/// Represents a parsed function call from FunctionGemma output.
/// FunctionGemma outputs: <start_function_call>call:FUNC_NAME{params}<end_function_call>
public struct FunctionCall: Codable, Sendable, Equatable {
    /// The function name (e.g., "create_atom", "query_level_system")
    public let name: String

    /// Parameters as key-value pairs
    public let parameters: [String: FunctionParameter]

    /// Raw output from FunctionGemma (for debugging)
    public let rawOutput: String?

    public init(name: String, parameters: [String: FunctionParameter], rawOutput: String? = nil) {
        self.name = name
        self.parameters = parameters
        self.rawOutput = rawOutput
    }

    // MARK: - Convenience Accessors

    public func string(_ key: String) -> String? {
        parameters[key]?.stringValue
    }

    public func int(_ key: String) -> Int? {
        parameters[key]?.intValue
    }

    public func double(_ key: String) -> Double? {
        parameters[key]?.doubleValue
    }

    public func bool(_ key: String) -> Bool? {
        parameters[key]?.boolValue
    }

    public func array(_ key: String) -> [FunctionParameter]? {
        parameters[key]?.arrayValue
    }

    public func object(_ key: String) -> [String: FunctionParameter]? {
        parameters[key]?.objectValue
    }
}

// MARK: - Function Parameter

/// Type-safe parameter value from FunctionGemma output
public enum FunctionParameter: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([FunctionParameter])
    case object([String: FunctionParameter])
    case null

    // MARK: - Value Accessors

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var intValue: Int? {
        if case .int(let value) = self { return value }
        if case .double(let value) = self { return Int(value) }
        if case .string(let value) = self { return Int(value) }
        return nil
    }

    public var doubleValue: Double? {
        if case .double(let value) = self { return value }
        if case .int(let value) = self { return Double(value) }
        if case .string(let value) = self { return Double(value) }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        if case .string(let value) = self {
            return value.lowercased() == "true" || value == "1"
        }
        return nil
    }

    public var arrayValue: [FunctionParameter]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: FunctionParameter]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([FunctionParameter].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: FunctionParameter].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Could not decode FunctionParameter"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    // MARK: - JSON Conversion

    /// Convert to JSON-compatible Any value
    public var jsonValue: Any {
        switch self {
        case .string(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .bool(let value): return value
        case .array(let value): return value.map { $0.jsonValue }
        case .object(let value): return value.mapValues { $0.jsonValue }
        case .null: return NSNull()
        }
    }

    /// Create from JSON-compatible Any value
    public static func from(_ value: Any) -> FunctionParameter {
        switch value {
        case let string as String:
            return .string(string)
        case let int as Int:
            return .int(int)
        case let double as Double:
            return .double(double)
        case let bool as Bool:
            return .bool(bool)
        case let array as [Any]:
            return .array(array.map { from($0) })
        case let dict as [String: Any]:
            return .object(dict.mapValues { from($0) })
        default:
            return .null
        }
    }
}

// MARK: - Function Names

/// All function names supported by the CosmoOS Micro-Brain
public enum FunctionName: String, CaseIterable, Sendable {
    // Core CRUD
    case createAtom = "create_atom"
    case updateAtom = "update_atom"
    case deleteAtom = "delete_atom"
    case searchAtoms = "search_atoms"
    case batchCreate = "batch_create"

    // Navigation
    case navigate = "navigate"

    // Level System Queries
    case queryLevelSystem = "query_level_system"

    // Deep Work
    case startDeepWork = "start_deep_work"
    case stopDeepWork = "stop_deep_work"
    case extendDeepWork = "extend_deep_work"

    // Workout
    case logWorkout = "log_workout"

    // Correlation (triggers Claude API)
    case triggerCorrelationAnalysis = "trigger_correlation_analysis"

    // MARK: - Sanctuary Dimension Navigation
    case openCognitiveDimension = "open_cognitive_dimension"
    case openCreativeDimension = "open_creative_dimension"
    case openPhysiologicalDimension = "open_physiological_dimension"
    case openBehavioralDimension = "open_behavioral_dimension"
    case openKnowledgeDimension = "open_knowledge_dimension"
    case openReflectionDimension = "open_reflection_dimension"
    case returnToSanctuaryHome = "return_to_sanctuary_home"

    // MARK: - Sanctuary Satellite Navigation
    case openPlannerum = "open_plannerum"
    case openThinkspace = "open_thinkspace"

    // MARK: - Sanctuary Knowledge Graph
    case zoomKnowledgeGraph = "zoom_knowledge_graph"
    case focusKnowledgeNode = "focus_knowledge_node"
    case searchKnowledgeNodes = "search_knowledge_nodes"
    case showClusterDetail = "show_cluster_detail"

    // MARK: - Sanctuary Panels
    case toggleTimelineView = "toggle_timeline_view"
    case showCorrelationInsights = "show_correlation_insights"
    case showPredictionsPanel = "show_predictions_panel"
    case expandMetricDetail = "expand_metric_detail"

    // MARK: - Sanctuary Quick Actions
    case quickLogMood = "quick_log_mood"
    case startMeditationSession = "start_meditation_session"
    case openJournalEntry = "open_journal_entry"

    /// Whether this function triggers the Big Brain (Claude API)
    public var requiresBigBrain: Bool {
        switch self {
        case .triggerCorrelationAnalysis:
            return true
        default:
            return false
        }
    }

    /// Whether this is a Sanctuary-related action
    public var isSanctuaryAction: Bool {
        switch self {
        case .openCognitiveDimension, .openCreativeDimension, .openPhysiologicalDimension,
             .openBehavioralDimension, .openKnowledgeDimension, .openReflectionDimension,
             .returnToSanctuaryHome, .openPlannerum, .openThinkspace,
             .zoomKnowledgeGraph, .focusKnowledgeNode,
             .searchKnowledgeNodes, .showClusterDetail, .toggleTimelineView,
             .showCorrelationInsights, .showPredictionsPanel, .expandMetricDetail,
             .quickLogMood, .startMeditationSession, .openJournalEntry:
            return true
        default:
            return false
        }
    }
}

// MARK: - Execution Result

/// Result of executing a FunctionCall
public enum ExecutionResult: Sendable {
    case created(Atom)
    case updated(Atom)
    case deleted(String)  // UUID of deleted atom
    case searched([Atom])
    case batched([Atom])
    case navigated(String)
    case queried(QueryResponse)
    case deepWorkStarted(String)  // Session ID
    case deepWorkStopped(DeepWorkSummary)
    case deepWorkExtended(Int)  // New duration
    case workoutLogged(Atom)
    case correlationTriggered(String)  // Correlation ID
    case error(String)

    // Sanctuary Actions
    case sanctuaryDimensionOpened(SanctuaryDimension)
    case sanctuaryHomeOpened
    case plannerumOpened
    case thinkspaceOpened
    case knowledgeGraphZoomed(direction: ZoomDirection)
    case knowledgeNodeFocused(nodeId: String)
    case knowledgeNodesSearched(query: String, resultCount: Int)
    case clusterDetailShown(clusterId: String)
    case panelToggled(panel: SanctuaryPanel, isVisible: Bool)
    case moodLogged(emoji: String, valence: Double, energy: Double)
    case meditationSessionStarted(sessionId: String)
    case journalEntryOpened

    /// Human-readable confirmation message
    public var confirmationMessage: String {
        switch self {
        case .created(let atom):
            return "Created \(atom.type.rawValue): \(atom.title ?? "untitled")"
        case .updated(let atom):
            return "Updated \(atom.type.rawValue): \(atom.title ?? "untitled")"
        case .deleted:
            return "Deleted successfully"
        case .searched(let atoms):
            return "Found \(atoms.count) result\(atoms.count == 1 ? "" : "s")"
        case .batched(let atoms):
            return "Created \(atoms.count) item\(atoms.count == 1 ? "" : "s")"
        case .navigated(let destination):
            return "Navigating to \(destination)"
        case .queried(let response):
            return response.spokenText
        case .deepWorkStarted:
            return "Deep work session started"
        case .deepWorkStopped(let summary):
            return "Deep work completed: \(summary.durationMinutes) minutes, +\(summary.xpEarned) XP"
        case .deepWorkExtended(let minutes):
            return "Deep work extended by \(minutes) minutes"
        case .workoutLogged:
            return "Workout logged"
        case .correlationTriggered:
            return "Correlation analysis triggered"
        case .error(let message):
            return "Error: \(message)"

        // Sanctuary Actions
        case .sanctuaryDimensionOpened(let dimension):
            return "Opening \(dimension.displayName) dimension"
        case .sanctuaryHomeOpened:
            return "Returning to Sanctuary home"
        case .plannerumOpened:
            return "Opening Plannerum - your planning command chamber"
        case .thinkspaceOpened:
            return "Opening Thinkspace - your creative canvas"
        case .knowledgeGraphZoomed(let direction):
            return "Zooming \(direction == .in ? "in" : "out") on knowledge graph"
        case .knowledgeNodeFocused(let nodeId):
            return "Focusing on node \(nodeId)"
        case .knowledgeNodesSearched(let query, let count):
            return "Found \(count) nodes matching '\(query)'"
        case .clusterDetailShown(let clusterId):
            return "Showing cluster \(clusterId)"
        case .panelToggled(let panel, let isVisible):
            return "\(isVisible ? "Showing" : "Hiding") \(panel.displayName)"
        case .moodLogged(let emoji, _, _):
            return "Logged mood: \(emoji)"
        case .meditationSessionStarted:
            return "Starting meditation session"
        case .journalEntryOpened:
            return "Opening journal entry"
        }
    }
}

// MARK: - Sanctuary Types

/// The six dimensions of the Sanctuary
public enum SanctuaryDimension: String, Codable, Sendable, CaseIterable {
    case cognitive
    case creative
    case physiological
    case behavioral
    case knowledge
    case reflection

    public var displayName: String {
        rawValue.capitalized
    }
}

// Note: ZoomDirection is defined in SanctuaryHaptics.swift

/// Sanctuary panels that can be toggled
public enum SanctuaryPanel: String, Codable, Sendable {
    case timeline
    case correlationInsights
    case predictions
    case metricDetail

    public var displayName: String {
        switch self {
        case .timeline: return "Timeline"
        case .correlationInsights: return "Correlation Insights"
        case .predictions: return "Predictions"
        case .metricDetail: return "Metric Detail"
        }
    }
}

// Note: DeepWorkSummary is defined in InsightProcessor.swift

// MARK: - Micro-Brain Query Response

/// Response from a level system query (Micro-Brain format)
/// Note: Different from VoiceAtom.QueryResponse which is the canonical format
public struct MicroBrainQueryResponse: Codable, Sendable {
    public let queryType: String
    public let spokenText: String
    public let metrics: [String: Double]?
    public let details: [String: String]?

    public init(
        queryType: String,
        spokenText: String,
        metrics: [String: Double]? = nil,
        details: [String: String]? = nil
    ) {
        self.queryType = queryType
        self.spokenText = spokenText
        self.metrics = metrics
        self.details = details
    }
}

// MARK: - Micro-Brain Errors

public enum MicroBrainError: Error, LocalizedError, Sendable {
    case modelNotLoaded
    case invalidOutput(String)
    case parsingFailed(String)
    case unknownFunction(String)
    case invalidParameters(String)
    case executionFailed(String)
    case timeout

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "FunctionGemma model is not loaded"
        case .invalidOutput(let output):
            return "Invalid model output: \(output.prefix(100))"
        case .parsingFailed(let reason):
            return "Failed to parse function call: \(reason)"
        case .unknownFunction(let name):
            return "Unknown function: \(name)"
        case .invalidParameters(let reason):
            return "Invalid parameters: \(reason)"
        case .executionFailed(let reason):
            return "Execution failed: \(reason)"
        case .timeout:
            return "FunctionGemma inference timed out"
        }
    }
}
