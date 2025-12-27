// CosmoOS/AI/LegacyStubs.swift
// Minimal stubs for legacy AI services that were deleted during Atom migration
// These provide backward compatibility until all references are fully migrated

import Foundation
import SwiftUI

// MARK: - Legacy Notification Names

extension Notification.Name {
    /// Legacy notification - use CosmoNotification.Voice.recordingStateChanged instead
    static let voiceRecordingStateChanged = CosmoNotification.Voice.recordingStateChanged

    /// Legacy notification - use CosmoNotification.Canvas.blockSelected instead
    static let blockSelected = CosmoNotification.Canvas.blockSelected

    /// Legacy notification - use CosmoNotification.Navigation.bringRelatedBlocks instead
    static let bringRelatedBlocks = CosmoNotification.Navigation.bringRelatedBlocks

    /// Legacy notification - use CosmoNotification.Navigation.exitFocusMode instead
    static let exitFocusMode = CosmoNotification.Navigation.exitFocusMode

    /// Legacy notification - use CosmoNotification.Canvas.placeBlocksOnCanvas instead
    static let placeBlocksOnCanvas = CosmoNotification.Canvas.placeBlocksOnCanvas

    /// Legacy notification - use CosmoNotification.AI.emergencyMemoryUnload instead
    static let emergencyMemoryUnload = CosmoNotification.AI.emergencyMemoryUnload

    /// Legacy notification - use CosmoNotification.Canvas.moveCanvasBlocks instead
    static let moveCanvasBlocks = CosmoNotification.Canvas.moveCanvasBlocks

    /// Legacy notification for opening calendar window
    static let openCalendarWindow = Notification.Name("openCalendarWindow")

    /// Legacy notification for voice-triggered schedule block creation
    static let voiceCreateScheduleBlock = Notification.Name("voiceCreateScheduleBlock")

    /// Legacy notification for showing command palette
    static let showCommandPalette = Notification.Name("showCommandPalette")

    /// Legacy notification for showing settings
    static let showSettings = Notification.Name("showSettings")

    /// Legacy notification for expanding selected block
    static let expandSelectedBlock = Notification.Name("expandSelectedBlock")
    static let closeSelectedBlock = Notification.Name("closeSelectedBlock")
    static let deleteSpecificBlock = Notification.Name("deleteSpecificBlock")
    static let moveBlockToTime = Notification.Name("moveBlockToTime")
    static let scheduleBlockCompleted = Notification.Name("scheduleBlockCompleted")
    static let createScheduleBlock = Notification.Name("createScheduleBlock")
    static let deleteBlockByContent = Notification.Name("deleteBlockByContent")
    static let expandBlockByContent = Notification.Name("expandBlockByContent")
    static let duplicateBlockByContent = Notification.Name("duplicateBlockByContent")
    static let moveBlockByContentToTime = Notification.Name("moveBlockByContentToTime")
    static let resizeSelectedBlock = Notification.Name("resizeSelectedBlock")
    static let placeEntityOnCanvas = Notification.Name("placeEntityOnCanvas")

    // Scheduler notifications
    static let scheduleBlockCreated = Notification.Name("scheduleBlockCreated")
    static let scheduleBlockUpdated = Notification.Name("scheduleBlockUpdated")
    static let scheduleBlockDeleted = Notification.Name("scheduleBlockDeleted")
    static let schedulerModeChanged = Notification.Name("schedulerModeChanged")
    static let scheduleBlockSelected = Notification.Name("scheduleBlockSelected")
    static let voiceMoveScheduleBlock = Notification.Name("voiceMoveScheduleBlock")
    static let voiceResizeScheduleBlock = Notification.Name("voiceResizeScheduleBlock")
    static let voiceDeleteScheduleBlock = Notification.Name("voiceDeleteScheduleBlock")
    static let voiceCompleteScheduleBlock = Notification.Name("voiceCompleteScheduleBlock")
    static let voiceSwitchSchedulerMode = Notification.Name("voiceSwitchSchedulerMode")
    static let voiceNavigateSchedulerDate = Notification.Name("voiceNavigateSchedulerDate")
}

// MARK: - LocalLLM Stub

/// Stub for deleted LocalLLM - use FineTunedQwen05B or Hermes15B instead
@MainActor
class LocalLLM: ObservableObject {
    static let shared = LocalLLM()

    @Published var isReady: Bool = false
    @Published var isLoading: Bool = false

    private init() {}

    /// Deprecated - use new AI models instead
    func generate(prompt: String) async throws -> String {
        print("⚠️ LocalLLM.generate() is deprecated - use FineTunedQwen05B or Hermes15B")
        return ""
    }

    /// Deprecated - use new AI models instead
    func generate(prompt: String, maxTokens: Int) async -> String {
        print("⚠️ LocalLLM.generate() is deprecated - use FineTunedQwen05B or Hermes15B")
        return ""
    }

    /// Deprecated - use new AI models instead
    func loadModel() async {
        print("⚠️ LocalLLM.loadModel() is deprecated - models are loaded via new AI pipeline")
        isReady = true
    }

    /// Get diagnostics (stub returns empty dictionary)
    func getDiagnostics() -> LocalLLMDiagnostics {
        return LocalLLMDiagnostics()
    }

    /// Run smoke test (stub - always returns success)
    func runSmokeTest() async -> (success: Bool, message: String, time: TimeInterval) {
        return (true, "LocalLLM is deprecated - use new AI pipeline", 0.001)
    }

    /// Parse entity details from a string (stub)
    func parseEntityDetails(_ details: String) async -> (title: String, content: String?) {
        // Simple parsing: first line is title, rest is content
        let lines = details.components(separatedBy: "\n")
        let title = lines.first ?? details
        let content = lines.count > 1 ? lines.dropFirst().joined(separator: "\n") : nil
        return (title, content)
    }

    /// Preprocess pronouns in text (stub - returns input unchanged)
    func preprocessPronouns(in text: String) -> (String, [String]) {
        return (text, [])
    }
}

/// Diagnostics info for LocalLLM
public struct LocalLLMDiagnostics {
    var sessionInitialized: Bool = false
    var availabilityStatus: String = "Deprecated"
    var macOSVersion: String = ProcessInfo.processInfo.operatingSystemVersionString
    var foundationModelsAvailable: Bool = false
    var toolCount: Int = 0
    var lastError: String? = nil
    var recoverySteps: String? = nil
}

// MARK: - ResponseCache Stub

/// Stub for deleted ResponseCache
@MainActor
class ResponseCache {
    static let shared = ResponseCache()
    private init() {}

    func setupDatabaseObserver(database: CosmoDatabase) async {
        // Stub - no-op
    }

    func get(key: String) -> String? {
        return nil
    }

    func set(key: String, value: String) {
        // Stub - no-op
    }
}

// MARK: - InstantParser Stub

/// Stub for deleted InstantParser - date/time parsing
struct InstantParser {
    struct ParsedEvent {
        let title: String
        let startTime: Date
        let endTime: Date
        let isAllDay: Bool
    }

    func parse(_ text: String) -> ParsedEvent? {
        // Simple stub - parse basic patterns
        let now = Date()
        return ParsedEvent(
            title: text,
            startTime: now.addingTimeInterval(3600),
            endTime: now.addingTimeInterval(7200),
            isAllDay: false
        )
    }
}

// MARK: - ActionRegistry Stub

/// Stub for deleted ActionRegistry - undo/redo now handled differently
class ActionRegistry {
    enum ActionType {
        case undoLastAction
        case redoAction
        case createIdea
        case createTask
    }

    private let database: CosmoDatabase

    init(database: CosmoDatabase) {
        self.database = database
    }

    func execute(_ action: ActionType, parameters: [String: Any]) async throws {
        // Stub - no-op
        print("⚠️ ActionRegistry.execute() is deprecated")
    }
}

// MARK: - SafetyMonitor Stub

/// Stub for deleted SafetyMonitor - safety checks now integrated into voice pipeline
@MainActor
public class SafetyMonitor: ObservableObject {
    /// Shared singleton
    public static let shared = SafetyMonitor()

    @Published public var isEnabled: Bool = true

    private init() {}

    /// Check if memory can be allocated (stub returns true)
    public func canAllocate(bytes: Int) -> Bool {
        return true
    }

    /// Check if memory can be allocated in MB (stub returns true)
    public func canAllocate(mb: Int) -> Bool {
        return true
    }

    /// Check if content is safe (always returns true for stub)
    public func checkSafety(_ content: String) async -> Bool {
        return true
    }

    /// Deprecated - safety monitoring is now handled differently
    public func startMonitoring() {
        print("⚠️ SafetyMonitor.startMonitoring() is deprecated")
    }

    public func stopMonitoring() {
        print("⚠️ SafetyMonitor.stopMonitoring() is deprecated")
    }
}

// MARK: - MLXEmbeddingService Stub

/// Stub for deleted MLXEmbeddingService - use VectorDatabase.shared for embeddings
@MainActor
class MLXEmbeddingService: ObservableObject {
    static let shared = MLXEmbeddingService()

    @Published var isReady: Bool = false
    @Published var isLoading: Bool = false

    private init() {}

    /// Deprecated - use VectorDatabase.shared.embed() instead
    func embed(_ text: String) async throws -> [Float] {
        print("⚠️ MLXEmbeddingService.embed() is deprecated - use VectorDatabase.shared")
        return []
    }

    /// Deprecated - embeddings are now managed by VectorDatabase
    func loadModel() async {
        print("⚠️ MLXEmbeddingService.loadModel() is deprecated")
        isReady = true
    }

    /// Deprecated - similarity search is now in VectorDatabase
    func findSimilar(_ embedding: [Float], topK: Int = 5) async throws -> [(uuid: String, score: Float)] {
        print("⚠️ MLXEmbeddingService.findSimilar() is deprecated - use VectorDatabase.shared")
        return []
    }
}

// MARK: - ConfidenceCalibrator Stub

/// Stub for deleted ConfidenceCalibrator
@MainActor
class ConfidenceCalibrator: ObservableObject {
    static let shared = ConfidenceCalibrator()

    private init() {}

    func calibrate(_ score: Double) -> Double {
        return score
    }

    func recordOutcome(predicted: Double, actual: Bool) {
        // No-op stub
    }
}

// MARK: - EntityMentionTracker Stub

/// Stub for deleted EntityMentionTracker
@MainActor
class EntityMentionTracker: ObservableObject {
    static let shared = EntityMentionTracker()

    private init() {}

    func trackMention(entityUuid: String, entityType: String) {
        // No-op stub
    }

    func getMentionCount(entityUuid: String) -> Int {
        return 0
    }
}

// MARK: - LLMCommandResult

/// Result from LLM command execution
public struct LLMCommandResult: Sendable {
    public let success: Bool
    public let message: String?
    public let entityUuid: String?
    public let entityType: String?
    public let action: String?
    public let title: String?
    public let targetBlockQuery: String?
    public let position: String?
    public let layout: String?

    public init(success: Bool, message: String? = nil, entityUuid: String? = nil, entityType: String? = nil, action: String? = nil, title: String? = nil, targetBlockQuery: String? = nil, position: String? = nil, layout: String? = nil) {
        self.success = success
        self.message = message
        self.entityUuid = entityUuid
        self.entityType = entityType
        self.action = action
        self.title = title
        self.targetBlockQuery = targetBlockQuery
        self.position = position
        self.layout = layout
    }

    public static let failure = LLMCommandResult(success: false)
}

// MARK: - SourceReference

/// Reference to a source document/entity for context
public struct SourceReference: Codable, Identifiable, Equatable, Sendable {
    public var id: String { uuid }
    public let uuid: String
    public let entityId: Int64?
    public let title: String
    public let entityType: String
    public let excerpt: String?
    public let relevanceScore: Double?

    public init(uuid: String = UUID().uuidString, entityId: Int64? = nil, title: String, entityType: String, excerpt: String? = nil, relevanceScore: Double? = nil) {
        self.uuid = uuid
        self.entityId = entityId
        self.title = title
        self.entityType = entityType
        self.excerpt = excerpt
        self.relevanceScore = relevanceScore
    }

    /// Convenience init with old argument order for backward compatibility
    public init(entityType: String, entityId: Int64, title: String, relevanceScore: Float? = nil) {
        self.uuid = UUID().uuidString
        self.entityId = entityId
        self.title = title
        self.entityType = entityType
        self.excerpt = nil
        self.relevanceScore = relevanceScore.map { Double($0) }
    }
}

// MARK: - SynthesisResult

/// Result from AI synthesis/generation
public struct SynthesisResult: Sendable {
    public let content: String
    public let sources: [SourceReference]
    public let confidence: Double
    public let tokensUsed: Int
    public let latencyMs: Double
    public let suggestedActions: [SuggestedAction]?

    public init(
        content: String,
        sources: [SourceReference] = [],
        confidence: Double = 1.0,
        tokensUsed: Int = 0,
        latencyMs: Double = 0,
        suggestedActions: [SuggestedAction]? = nil
    ) {
        self.content = content
        self.sources = sources
        self.confidence = confidence
        self.tokensUsed = tokensUsed
        self.latencyMs = latencyMs
        self.suggestedActions = suggestedActions
    }
}

// MARK: - ActionType

/// Type of suggested action
public enum ActionType: String, Codable, CaseIterable, Sendable {
    case createIdea = "createIdea"
    case addToSwipeFile = "addToSwipeFile"
    case createConnection = "createConnection"
    case createTask = "createTask"
    case createContent = "createContent"
    case navigate = "navigate"
    case other = "other"
}

// MARK: - SuggestedAction

/// AI-suggested action for the user
public struct SuggestedAction: Codable, Identifiable, Equatable, Sendable {
    public var id: String { actionId }
    public let actionId: String
    public let actionType: String
    public let title: String
    public let description: String?
    public let entityUuid: String?
    public let priority: Int

    // Convenience static factory methods for common action types
    public static func createIdea(title: String, description: String? = nil) -> SuggestedAction {
        SuggestedAction(actionType: "createIdea", title: title, description: description)
    }

    public static func addToSwipeFile(title: String, description: String? = nil) -> SuggestedAction {
        SuggestedAction(actionType: "addToSwipeFile", title: title, description: description)
    }

    public init(actionId: String = UUID().uuidString, actionType: String, title: String, description: String? = nil, entityUuid: String? = nil, priority: Int = 0) {
        self.actionId = actionId
        self.actionType = actionType
        self.title = title
        self.description = description
        self.entityUuid = entityUuid
        self.priority = priority
    }

    // Init with enum type (used by GeminiSynthesisEngine)
    public init(type: ActionType, title: String, description: String? = nil) {
        self.actionId = UUID().uuidString
        self.actionType = type.rawValue
        self.title = title
        self.description = description
        self.entityUuid = nil
        self.priority = 0
    }

    // Legacy init for backward compatibility with string type
    public init(type: String, title: String, description: String? = nil) {
        self.actionId = UUID().uuidString
        self.actionType = type
        self.title = title
        self.description = description
        self.entityUuid = nil
        self.priority = 0
    }
}

// MARK: - GeminiPrompts Stub

/// Stub for deleted GeminiPrompts
public enum GeminiPrompts {
    public static func systemPrompt(for intent: ClassifiedVoiceIntent) -> String {
        "You are a helpful AI assistant."
    }

    public static func prompt(
        for intent: ClassifiedVoiceIntent,
        query: String,
        context: String
    ) -> String {
        """
        Query: \(query)

        Context:
        \(context)

        Please synthesize a helpful response based on the intent: \(intent.rawValue).
        """
    }

    public static func synthesisPrompt(
        query: String,
        context: String,
        intent: ClassifiedVoiceIntent
    ) -> String {
        prompt(for: intent, query: query, context: context)
    }
}

// MARK: - ResearchRichContent

/// Rich content metadata for research items
public struct ResearchRichContent: Codable, Equatable, Sendable {
    // MARK: - Nested Types

    /// Source type for research content
    public enum SourceType: String, Codable, CaseIterable, Sendable {
        case youtube = "youtube"
        case youtubeShort = "youtube_short"
        case podcast = "podcast"
        case article = "article"
        case book = "book"
        case twitter = "twitter"
        case xPost = "x_post"
        case instagram = "instagram"
        case instagramReel = "instagram_reel"
        case instagramPost = "instagram_post"
        case instagramCarousel = "instagram_carousel"
        case tiktok = "tiktok"
        case threads = "threads"
        case rawNote = "raw_note"
        case website = "website"
        case loom = "loom"
        case pdf = "pdf"
        case other = "other"
        case unknown = "unknown"

        var displayName: String { rawValue.capitalized }
    }

    /// Instagram-specific content type
    public enum InstagramContentType: String, Codable, CaseIterable, Sendable {
        case post = "post"
        case reel = "reel"
        case story = "story"
        case carousel = "carousel"
    }

    var title: String?
    var description: String?
    var author: String?
    var publishedAt: String?
    var thumbnailUrl: String?
    var duration: Int?
    var platform: String?
    var transcript: String?
    var transcriptSegments: [TranscriptSegment]?
    var summary: String?
    var keyPoints: [String]?
    var tags: [String]?
    var embedHtml: String?
    var sourceType: SourceType?
    var instagramContentType: InstagramContentType?

    // Platform-specific IDs
    var videoId: String?
    var tweetId: String?
    var loomId: String?
    var instagramId: String?
    var threadsId: String?
    var instagramType: String?

    // User additions
    var personalNotes: String?

    // Screenshot storage
    var screenshotBase64: String?

    // Formatted transcript (can be stored directly or computed from segments)
    var formattedTranscript: String?

    // Transcript sections (grouped segments)
    var transcriptSections: [TranscriptSectionData]?

    // Instagram-specific extended data (per PRD)
    var instagramData: InstagramData?

    init(
        title: String? = nil,
        description: String? = nil,
        author: String? = nil,
        publishedAt: String? = nil,
        thumbnailUrl: String? = nil,
        duration: Int? = nil,
        platform: String? = nil,
        transcript: String? = nil,
        transcriptSegments: [TranscriptSegment]? = nil,
        summary: String? = nil,
        keyPoints: [String]? = nil,
        tags: [String]? = nil,
        embedHtml: String? = nil,
        sourceType: SourceType? = nil,
        instagramType: InstagramContentType? = nil,
        videoId: String? = nil,
        tweetId: String? = nil,
        loomId: String? = nil,
        personalNotes: String? = nil,
        screenshotBase64: String? = nil,
        formattedTranscript: String? = nil,
        transcriptSections: [TranscriptSectionData]? = nil,
        instagramData: InstagramData? = nil
    ) {
        self.title = title
        self.description = description
        self.author = author
        self.publishedAt = publishedAt
        self.thumbnailUrl = thumbnailUrl
        self.duration = duration
        self.platform = platform
        self.transcript = transcript
        self.transcriptSegments = transcriptSegments
        self.summary = summary
        self.keyPoints = keyPoints
        self.tags = tags
        self.embedHtml = embedHtml
        self.sourceType = sourceType
        self.instagramContentType = instagramType
        self.instagramType = instagramType?.rawValue
        self.videoId = videoId
        self.tweetId = tweetId
        self.loomId = loomId
        self.personalNotes = personalNotes
        self.screenshotBase64 = screenshotBase64
        self.formattedTranscript = formattedTranscript
        self.transcriptSections = transcriptSections
        self.instagramData = instagramData
    }
}

// MARK: - SwipeContentSource

/// Source where swipe file content was captured from
public enum SwipeContentSource: String, Codable, Sendable {
    case clipboard = "clipboard"
    case share = "share"
    case manualEntry = "manual_entry"
    case import_ = "import"
}

// MARK: - TranscriptSegment

/// A segment of transcribed content with timing
struct TranscriptSegment: Codable, Identifiable, Equatable, Sendable {
    var id: String { "\(start)-\(end)" }
    let start: Double
    let end: Double
    let text: String
    let speaker: String?
    let confidence: Double?

    init(start: Double, end: Double, text: String, speaker: String? = nil, confidence: Double? = nil) {
        self.start = start
        self.end = end
        self.text = text
        self.speaker = speaker
        self.confidence = confidence
    }

    // Legacy compatibility aliases
    var startTime: Double { start }
    var endTime: Double { end }

    /// Formatted time for display (e.g., "1:23")
    var formattedTime: String {
        let minutes = Int(start) / 60
        let seconds = Int(start) % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

// MARK: - TranscriptSectionData

/// Section grouping for transcript segments
struct TranscriptSectionData: Codable, Identifiable, Equatable, Sendable {
    var id: String { title }
    let title: String
    let startTime: Double
    let endTime: Double
    let summary: String?
    let segments: [TranscriptSegment]?

    init(title: String, startTime: Double, endTime: Double, summary: String? = nil, segments: [TranscriptSegment]? = nil) {
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.summary = summary
        self.segments = segments
    }
}

// MARK: - SwipeEmotionTone

/// Emotion tone classification for swipe file content
enum SwipeEmotionTone: String, Codable, CaseIterable, Sendable {
    case neutral = "neutral"
    case excited = "excited"
    case curious = "curious"
    case urgent = "urgent"
    case empathetic = "empathetic"
    case authoritative = "authoritative"
    case playful = "playful"
    case inspiring = "inspiring"

    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - DaemonXPCClientProtocol

/// Protocol for daemon XPC client communication (stub)
@MainActor
public protocol DaemonXPCClientProtocol: AnyObject {
    var isConnected: Bool { get }
}

// MARK: - SwipeStructureType

/// Structure type for swipe file content
enum SwipeStructureType: String, Codable, CaseIterable, Sendable {
    case hook = "hook"
    case story = "story"
    case listicle = "listicle"
    case tutorial = "tutorial"
    case controversial = "controversial"
    case personal = "personal"
    case other = "other"

    var displayName: String { rawValue.capitalized }
}

// MARK: - StreamingGardener Stub

/// Stub for deleted StreamingGardener
@MainActor
public class StreamingGardener: ObservableObject {
    public static let shared = StreamingGardener()

    public init() {}

    public func process(_ text: String) async -> String {
        return text
    }

    /// Process a chunk of streaming text with context
    public func processChunk(_ chunk: Any, hotContext: Any?) async {
        // Stub - no-op
    }

    /// Execute hypotheses based on processed chunks with context
    public func executeHypotheses(hotContext: Any?) async {
        // Stub - no-op
    }
}

// MARK: - AutocompleteService Stub

/// Stub for deleted AutocompleteService
@MainActor
public class AutocompleteService: ObservableObject {
    public static let shared = AutocompleteService()

    @Published public var suggestions: [String] = []
    @Published public var isLoading: Bool = false

    public init() {}

    public func getSuggestions(for text: String) async -> [String] {
        return []
    }

    /// Handle typing input for autocomplete with context
    public func onTypingInput(_ text: String, cursorPosition: Int, hotContext: Any?) async {
        // Stub - no-op
    }
}

// MARK: - VoiceCommandRouter

/// Voice command router with Tier 0 instant pattern matching
/// Handles navigation commands and delegates complex commands to VoiceCommandPipeline
@MainActor
public class VoiceCommandRouter: ObservableObject {
    public static let shared = VoiceCommandRouter()

    public init() {}

    public struct RouteResult {
        public let action: String
        public let llmResult: LLMCommandResult?
        public init(action: String = "no-op", llmResult: LLMCommandResult? = nil) {
            self.action = action
            self.llmResult = llmResult
        }
    }

    // MARK: - Tier 0: Instant Navigation Patterns
    /// Single-word or simple phrase navigation commands
    private let navigationPatterns: [(patterns: [String], destination: String)] = [
        // Planarium / Planning
        (["plan", "planner", "planarium", "planning", "schedule", "calendar", "today"], "plannerum"),
        // Sanctuary / Home
        (["sanctuary", "home", "dashboard", "hub", "main"], "sanctuary"),
        // Thinkspace / Canvas
        (["thinkspace", "think", "canvas", "workspace", "space", "board"], "thinkspace"),
    ]

    public func route(_ command: String) async throws -> RouteResult {
        return try await route(command, context: nil)
    }

    public func route(_ command: String, context: Any?) async throws -> RouteResult {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        print("🎯 VoiceCommandRouter: Processing command: \"\(trimmed)\"")

        // Tier 0: Check for instant navigation patterns
        if let destination = matchNavigationPattern(trimmed) {
            print("✅ Tier 0 match: Navigation to \(destination)")
            postNavigationNotification(destination: destination)
            return RouteResult(action: "navigate:\(destination)")
        }

        // Check for "go to X" or "open X" patterns
        if let destination = matchGoToPattern(trimmed) {
            print("✅ Tier 0 match: 'Go to' navigation to \(destination)")
            postNavigationNotification(destination: destination)
            return RouteResult(action: "navigate:\(destination)")
        }

        // No Tier 0 match - delegate to VoiceCommandPipeline for Tier 1/2
        print("📤 No Tier 0 match, would delegate to VoiceCommandPipeline")
        // TODO: Integrate with VoiceCommandPipeline for FunctionGemma/Claude routing
        return RouteResult(action: "unhandled")
    }

    // MARK: - Pattern Matching

    /// Match single-word navigation commands
    private func matchNavigationPattern(_ command: String) -> String? {
        // Single word commands
        let words = command.split(separator: " ").map { String($0) }
        if words.count == 1 {
            let word = words[0]
            for (patterns, destination) in navigationPatterns {
                if patterns.contains(word) {
                    return destination
                }
            }
        }
        return nil
    }

    /// Match "go to X" or "open X" patterns
    private func matchGoToPattern(_ command: String) -> String? {
        // Patterns: "go to X", "open X", "show X", "navigate to X", "take me to X"
        let prefixes = ["go to ", "goto ", "open ", "show ", "navigate to ", "take me to ", "switch to "]

        for prefix in prefixes {
            if command.hasPrefix(prefix) {
                let target = String(command.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                // Match the target against navigation patterns
                for (patterns, destination) in navigationPatterns {
                    if patterns.contains(target) {
                        return destination
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Navigation

    private func postNavigationNotification(destination: String) {
        NotificationCenter.default.post(
            name: .voiceNavigationRequested,
            object: nil,
            userInfo: ["destination": destination]
        )
    }
}

// MARK: - ConnectionAutoLinker Stub

/// Stub for deleted ConnectionAutoLinker
@MainActor
public class ConnectionAutoLinker: ObservableObject {
    public static let shared = ConnectionAutoLinker()

    public init() {}

    func autoLink(atom: Atom) async {
        // No-op stub
    }
}

// MARK: - SmartRetrievalEngine Stub

/// Stub for deleted SmartRetrievalEngine
@MainActor
public class SmartRetrievalEngine: ObservableObject {
    public static let shared = SmartRetrievalEngine()

    @Published public var isReady: Bool = false

    public init() {}

    func search(query: String, topK: Int = 5) async throws -> [Atom] {
        return []
    }

    public func initialize() async {
        isReady = true
    }
}
