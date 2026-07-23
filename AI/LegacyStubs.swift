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

    /// Section navigation (previously declared in the deleted CosmoCore.swift)
    static let navigateToSection = Notification.Name("navigateToSection")

    /// Entity open requests (previously declared in the deleted CosmoChatView.swift);
    /// posted by canvas blocks + LinkedContactsSection, observed in CosmoApp.
    static let openEntity = Notification.Name("openEntity")

    /// Canvas block set changed (previously declared in the deleted CosmoCore.swift)
    static let canvasBlocksChanged = Notification.Name("com.cosmo.canvasBlocksChanged")

    static let closeSelectedBlock = Notification.Name("closeSelectedBlock")
    static let deleteSpecificBlock = Notification.Name("deleteSpecificBlock")
    static let moveBlockToTime = Notification.Name("moveBlockToTime")
    static let scheduleBlockCompleted = Notification.Name("scheduleBlockCompleted")
    static let createScheduleBlock = Notification.Name("createScheduleBlock")
    static let deleteBlockByContent = Notification.Name("deleteBlockByContent")
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

    // Transcript availability status for retry functionality
    var transcriptStatus: String?  // "available", "unavailable", "pending"

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
public struct TranscriptSegment: Codable, Identifiable, Equatable, Sendable {
    public var id: String { "\(start)-\(end)" }
    public let start: Double
    public let end: Double
    public let text: String
    public let speaker: String?
    public let confidence: Double?

    public init(start: Double, end: Double, text: String, speaker: String? = nil, confidence: Double? = nil) {
        self.start = start
        self.end = end
        self.text = text
        self.speaker = speaker
        self.confidence = confidence
    }

    // Legacy compatibility aliases
    public var startTime: Double { start }
    public var endTime: Double { end }

    /// Formatted time for display (e.g., "1:23")
    public var formattedTime: String {
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
