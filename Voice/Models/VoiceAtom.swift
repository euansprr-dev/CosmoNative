// CosmoOS/Voice/Models/VoiceAtom.swift
// Voice command representation throughout the pipeline

import Foundation

// MARK: - Voice Atom

/// Represents a voice command at any stage of processing.
/// This is THE intermediate representation between speech and Atom.
struct VoiceAtom: Sendable, Identifiable {
    let id: UUID
    let transcript: String
    let context: VoiceContext
    let timestamp: Date

    // Classification (set after intent classification)
    var intent: VoiceIntent?
    var confidence: Double = 0.0

    // Processing state
    var tier: ModelTier = .unknown
    var patternMatchResult: PatternMatchResult?
    var parsedAction: ParsedAction?

    // Result (set after execution)
    var resultAtoms: [Atom] = []
    var error: String?

    // Timing metrics
    var asrDurationMs: Int = 0
    var classificationDurationMs: Int = 0
    var modelDurationMs: Int = 0
    var executionDurationMs: Int = 0

    init(
        transcript: String,
        context: VoiceContext,
        timestamp: Date = Date()
    ) {
        self.id = UUID()
        self.transcript = transcript
        self.context = context
        self.timestamp = timestamp
    }

    /// Total processing time in milliseconds
    var totalDurationMs: Int {
        asrDurationMs + classificationDurationMs + modelDurationMs + executionDurationMs
    }

    /// Whether the command was processed successfully
    var isSuccess: Bool {
        error == nil && (parsedAction != nil || patternMatchResult != nil)
    }
}

// MARK: - Model Tier

/// The processing tier used to handle the voice command.
/// Micro-Brain Architecture: Pattern → FunctionGemma → Claude
enum ModelTier: String, Sendable, Codable {
    case unknown = "unknown"
    case pattern = "pattern"             // Tier 0: Regex matching (<50ms)
    case functionGemma = "functiongemma" // Tier 1: FunctionGemma 270M (<300ms) - Micro-Brain
    case claude = "claude"               // Tier 2: Claude Sonnet 4.5 (1-5s) - Big Brain

    // Legacy tiers (for backwards compatibility during migration)
    case qwen0_5B = "qwen_0.5b"          // DEPRECATED: Use functionGemma
    case hermes1_5B = "hermes_1.5b"      // DEPRECATED: Use functionGemma
    case gemini = "gemini"               // DEPRECATED: Use claude

    var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .pattern: return "Pattern Match"
        case .functionGemma: return "FunctionGemma"
        case .claude: return "Claude"
        case .qwen0_5B: return "Qwen 0.5B (Legacy)"
        case .hermes1_5B: return "Hermes 1.5B (Legacy)"
        case .gemini: return "Gemini (Legacy)"
        }
    }

    var targetLatencyMs: Int {
        switch self {
        case .unknown: return 0
        case .pattern: return 50
        case .functionGemma: return 300
        case .claude: return 5000
        case .qwen0_5B: return 300
        case .hermes1_5B: return 2000
        case .gemini: return 60000
        }
    }

    /// Whether this is a legacy tier that should be migrated
    var isLegacy: Bool {
        switch self {
        case .qwen0_5B, .hermes1_5B, .gemini:
            return true
        default:
            return false
        }
    }
}

// MARK: - Voice Intent

/// Classified intent of a voice command.
/// Used to route commands to the appropriate tier.
enum VoiceIntent: String, Sendable, Codable, CaseIterable {
    // Creation intents
    case createIdea = "create_idea"
    case createTask = "create_task"
    case createTaskTimed = "create_task_timed"
    case createProject = "create_project"
    case createScheduleBlock = "create_schedule_block"
    case createResearch = "create_research"
    case brainDump = "brain_dump"

    // Modification intents
    case updateStatus = "update_status"
    case updateTime = "update_time"
    case updatePriority = "update_priority"
    case updateProject = "update_project"
    case updateContent = "update_content"
    case delete = "delete"

    // Search intents
    case search = "search"
    case searchSemantic = "search_semantic"
    case navigate = "navigate"

    // Level System Query intents
    case queryLevel = "query_level"
    case queryStreak = "query_streak"
    case queryBadge = "query_badge"
    case queryXP = "query_xp"
    case queryHealth = "query_health"
    case queryReadiness = "query_readiness"
    case querySummary = "query_summary"

    // Generative intents (require Gemini)
    case generateIdeas = "generate_ideas"
    case generateContent = "generate_content"
    case synthesizeConnections = "synthesize_connections"
    case analyzePattern = "analyze_pattern"

    // Unknown
    case unknown = "unknown"

    /// Whether this intent requires generative AI (Gemini)
    var isGenerative: Bool {
        switch self {
        case .generateIdeas, .generateContent, .synthesizeConnections, .analyzePattern:
            return true
        default:
            return false
        }
    }

    /// Whether this intent is a level system query
    var isQuery: Bool {
        switch self {
        case .queryLevel, .queryStreak, .queryBadge, .queryXP,
             .queryHealth, .queryReadiness, .querySummary:
            return true
        default:
            return false
        }
    }

    /// Whether this intent is simple enough for pattern matching
    var isPatternMatchable: Bool {
        switch self {
        case .createIdea, .createTask, .createProject, .navigate, .delete,
             .updateStatus, .queryLevel, .queryStreak, .queryBadge, .queryXP,
             .queryHealth, .queryReadiness, .querySummary:
            return true
        default:
            return false
        }
    }

    /// Suggested tier for this intent (Micro-Brain architecture)
    var suggestedTier: ModelTier {
        if isGenerative { return .claude }
        if isPatternMatchable { return .pattern }
        // Everything else goes to FunctionGemma (Micro-Brain)
        return .functionGemma
    }
}

// MARK: - Voice Context

/// Context snapshot at the time of voice command.
/// Provides necessary information for resolving references like "this" or "that".
public struct VoiceContext: Sendable, Codable {
    public let section: AppSection
    public let editingAtomUuid: String?
    public let selectedAtomUuids: [String]
    public let recentAtomUuids: [String]
    public let currentProjectUuid: String?
    public let currentDate: Date

    public init(
        section: AppSection = .today,
        editingAtomUuid: String? = nil,
        selectedAtomUuids: [String] = [],
        recentAtomUuids: [String] = [],
        currentProjectUuid: String? = nil,
        currentDate: Date = Date()
    ) {
        self.section = section
        self.editingAtomUuid = editingAtomUuid
        self.selectedAtomUuids = selectedAtomUuids
        self.recentAtomUuids = recentAtomUuids
        self.currentProjectUuid = currentProjectUuid
        self.currentDate = currentDate
    }

    /// The most relevant atom for "this" or "that" references
    public var contextualAtomUuid: String? {
        editingAtomUuid ?? selectedAtomUuids.first ?? recentAtomUuids.first
    }

    /// Current project name (for Claude context)
    /// Would be populated from project lookup by UUID
    public var currentProjectName: String? {
        // TODO: Look up project name from UUID via AtomRepository
        nil
    }
}

/// App sections for navigation context
public enum AppSection: String, Sendable, Codable {
    case today = "today"
    case ideas = "ideas"
    case tasks = "tasks"
    case projects = "projects"
    case research = "research"
    case schedule = "schedule"
    case settings = "settings"
    case home = "home"
    case focus = "focus"
    case editor = "editor"
}

// MARK: - Voice Result

/// Result of processing a voice command.
struct VoiceResult: Sendable {
    let success: Bool
    let atoms: [Atom]
    let message: String?
    let spokenResponse: String?       // For TTS feedback
    let queryResponse: QueryResponse? // For level system query results
    let synthesizedContent: String?   // For Claude generative responses
    let parsedAction: ParsedAction?   // For MicroBrain action results
    let error: String?
    let tier: ModelTier
    let durationMs: Int

    init(
        success: Bool,
        atoms: [Atom] = [],
        message: String? = nil,
        spokenResponse: String? = nil,
        queryResponse: QueryResponse? = nil,
        synthesizedContent: String? = nil,
        parsedAction: ParsedAction? = nil,
        error: String? = nil,
        tier: ModelTier = .unknown,
        durationMs: Int = 0
    ) {
        self.success = success
        self.atoms = atoms
        self.message = message
        self.spokenResponse = spokenResponse
        self.queryResponse = queryResponse
        self.synthesizedContent = synthesizedContent
        self.parsedAction = parsedAction
        self.error = error
        self.tier = tier
        self.durationMs = durationMs
    }

    /// Convenience for single atom result
    init(success: Bool, atom: Atom, tier: ModelTier = .unknown, durationMs: Int = 0) {
        self.success = success
        self.atoms = [atom]
        self.message = nil
        self.spokenResponse = nil
        self.queryResponse = nil
        self.synthesizedContent = nil
        self.parsedAction = nil
        self.error = nil
        self.tier = tier
        self.durationMs = durationMs
    }

    /// Convenience for query result
    static func query(_ response: QueryResponse, tier: ModelTier = .pattern, durationMs: Int = 0) -> VoiceResult {
        VoiceResult(
            success: true,
            spokenResponse: response.spokenText,
            queryResponse: response,
            tier: tier,
            durationMs: durationMs
        )
    }

    /// Convenience for error result
    static func failure(_ error: String, tier: ModelTier = .unknown) -> VoiceResult {
        VoiceResult(success: false, error: error, tier: tier)
    }
}

// MARK: - Query Response

/// Response from a level system query
public struct QueryResponse: Sendable {
    public let queryType: ParsedAction.QueryType
    public let spokenText: String           // Natural language for TTS
    public let displayTitle: String         // Short title for UI
    public let displaySubtitle: String?     // Additional context
    public let metrics: [QueryMetric]       // Key-value metrics to display
    public let action: QueryAction?         // Optional follow-up action

    public init(
        queryType: ParsedAction.QueryType,
        spokenText: String,
        displayTitle: String,
        displaySubtitle: String? = nil,
        metrics: [QueryMetric] = [],
        action: QueryAction? = nil
    ) {
        self.queryType = queryType
        self.spokenText = spokenText
        self.displayTitle = displayTitle
        self.displaySubtitle = displaySubtitle
        self.metrics = metrics
        self.action = action
    }
}

/// A single metric in a query response
public struct QueryMetric: Sendable {
    public let label: String
    public let value: String
    public let icon: String?         // SF Symbol name
    public let color: String?        // Color name for theming
    public let trend: MetricTrend?

    public enum MetricTrend: String, Sendable {
        case up = "up"
        case down = "down"
        case stable = "stable"
    }

    public init(label: String, value: String, icon: String? = nil, color: String? = nil, trend: MetricTrend? = nil) {
        self.label = label
        self.value = value
        self.icon = icon
        self.color = color
        self.trend = trend
    }
}

/// Optional action suggested after a query
public struct QueryAction: Sendable {
    public let title: String
    public let destination: String    // Navigation destination or action identifier

    public init(title: String, destination: String) {
        self.title = title
        self.destination = destination
    }
}

// MARK: - Pattern Match Result

/// Result from Tier 0 pattern matching.
struct PatternMatchResult: Sendable {
    let action: ParsedAction.ActionType
    let atomType: AtomType?
    let title: String?
    let matchedPattern: String
    let confidence: Double
    let queryType: ParsedAction.QueryType?
    let dimension: String?
    let timePeriod: String?
    let entityName: String?
    let metadata: [String: String]?  // Additional context for routing

    init(
        action: ParsedAction.ActionType,
        atomType: AtomType? = nil,
        title: String? = nil,
        matchedPattern: String,
        confidence: Double = 1.0,
        queryType: ParsedAction.QueryType? = nil,
        dimension: String? = nil,
        timePeriod: String? = nil,
        entityName: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.action = action
        self.atomType = atomType
        self.title = title
        self.matchedPattern = matchedPattern
        self.confidence = confidence
        self.queryType = queryType
        self.dimension = dimension
        self.timePeriod = timePeriod
        self.entityName = entityName
        self.metadata = metadata
    }

    /// Convert to ParsedAction
    func toParsedAction() -> ParsedAction {
        ParsedAction(
            action: action,
            atomType: atomType,
            title: title,
            queryType: queryType,
            dimension: dimension
        )
    }
}
