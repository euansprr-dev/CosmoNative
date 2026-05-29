// CosmoOS/Data/Models/LevelSystem/ContentPipelineMetadata.swift
// Metadata structures for content creation and performance tracking
// Supports content drafts, phases, performance analytics, and client profiles

import Foundation
import SwiftUI

// MARK: - Content Phase

/// Phases in the content creation pipeline
public enum ContentPhase: String, Codable, CaseIterable, Sendable {
    case ideation           // Initial concept + outline building
    case draft              // First draft
    case polish             // Editing/refining
    case scheduled          // Ready for publish
    case published          // Live
    case analyzing          // Gathering performance data
    case archived           // Historical

    var displayName: String {
        switch self {
        case .ideation: return "Ideation"
        case .draft: return "Draft"
        case .polish: return "Polish"
        case .scheduled: return "Scheduled"
        case .published: return "Published"
        case .analyzing: return "Analyzing"
        case .archived: return "Archived"
        }
    }

    var iconName: String {
        switch self {
        case .ideation: return "lightbulb"
        case .draft: return "doc.text"
        case .polish: return "sparkles"
        case .scheduled: return "calendar.badge.clock"
        case .published: return "paperplane.fill"
        case .analyzing: return "chart.bar"
        case .archived: return "archivebox"
        }
    }

    /// Previous phase in the pipeline (visible flow: ideation → draft → polish → archived)
    var previousPhase: ContentPhase? {
        switch self {
        case .ideation: return nil
        case .draft: return .ideation
        case .polish: return .draft
        case .scheduled: return .polish   // legacy — hidden in UI
        case .published: return .scheduled // legacy — hidden in UI
        case .analyzing: return .published // legacy — hidden in UI
        case .archived: return .polish     // visible flow skips to polish
        }
    }

    /// Next phase in the pipeline (visible flow: ideation → draft → polish → archived)
    var nextPhase: ContentPhase? {
        switch self {
        case .ideation: return .draft
        case .draft: return .polish
        case .polish: return .archived     // visible flow skips to archived
        case .scheduled: return .published // legacy — hidden in UI
        case .published: return .analyzing // legacy — hidden in UI
        case .analyzing: return .archived  // legacy — hidden in UI
        case .archived: return nil
        }
    }

    /// XP earned for completing this phase
    var completionXP: Int {
        switch self {
        case .ideation: return 15
        case .draft: return 25
        case .polish: return 15
        case .scheduled: return 5
        case .published: return 20
        case .analyzing: return 0
        case .archived: return 0
        }
    }

    /// Whether this phase is visible in the UI pipeline bar
    /// Schedule, Published, and Analyzing are hidden for V1
    var isVisibleInPipeline: Bool {
        switch self {
        case .ideation, .draft, .polish, .archived: return true
        case .scheduled, .published, .analyzing: return false
        }
    }

    /// Only the phases shown in the UI pipeline bar
    static var visiblePhases: [ContentPhase] {
        allCases.filter(\.isVisibleInPipeline)
    }
}

// MARK: - Social Platform

/// Supported social media platforms
public enum SocialPlatform: String, Codable, CaseIterable, Sendable {
    case twitter
    case x
    case linkedin
    case instagram
    case tiktok
    case youtube
    case facebook
    case threads
    case substack
    case medium
    case other

    var displayName: String {
        switch self {
        case .twitter: return "Twitter/X"
        case .x: return "X"
        case .linkedin: return "LinkedIn"
        case .instagram: return "Instagram"
        case .tiktok: return "TikTok"
        case .youtube: return "YouTube"
        case .facebook: return "Facebook"
        case .threads: return "Threads"
        case .substack: return "Substack"
        case .medium: return "Medium"
        case .other: return "Other"
        }
    }

    var iconName: String {
        switch self {
        case .twitter: return "bird"
        case .x: return "xmark"
        case .linkedin: return "link"
        case .instagram: return "camera"
        case .tiktok: return "music.note"
        case .youtube: return "play.rectangle.fill"
        case .facebook: return "person.2"
        case .threads: return "at"
        case .substack: return "envelope"
        case .medium: return "doc.text"
        case .other: return "globe"
        }
    }

    /// Virality thresholds for this platform
    var viralityThreshold: (impressions: Int, engagementRate: Double) {
        switch self {
        case .twitter: return (100_000, 0.05)
        case .x: return (100_000, 0.05)
        case .linkedin: return (50_000, 0.03)
        case .instagram: return (50_000, 0.04)
        case .tiktok: return (100_000, 0.10)
        case .youtube: return (100_000, 0.05)
        case .facebook: return (50_000, 0.03)
        case .threads: return (25_000, 0.05)
        case .substack: return (10_000, 0.10)
        case .medium: return (10_000, 0.05)
        case .other: return (50_000, 0.05)
        }
    }
}

// MARK: - Content Draft Metadata

/// Metadata for contentDraft atoms - draft versions of content
struct ContentDraftMetadata: Codable, Sendable {
    /// UUID of the parent content atom
    let contentAtomUUID: String

    /// Version number
    let version: Int

    /// Current phase
    let phase: ContentPhase

    /// Word count of this draft
    let wordCount: Int

    /// When this draft was created
    let createdAt: Date

    /// Author notes about this version
    let authorNotes: String?

    /// Diff summary from previous version
    let diffSummary: String?

    /// Words added since last version
    let wordsAdded: Int

    /// Words removed since last version
    let wordsRemoved: Int

    init(
        contentAtomUUID: String,
        version: Int,
        phase: ContentPhase,
        wordCount: Int,
        createdAt: Date = Date(),
        authorNotes: String? = nil,
        diffSummary: String? = nil,
        wordsAdded: Int = 0,
        wordsRemoved: Int = 0
    ) {
        self.contentAtomUUID = contentAtomUUID
        self.version = version
        self.phase = phase
        self.wordCount = wordCount
        self.createdAt = createdAt
        self.authorNotes = authorNotes
        self.diffSummary = diffSummary
        self.wordsAdded = wordsAdded
        self.wordsRemoved = wordsRemoved
    }
}

// MARK: - Content Phase Metadata

/// Metadata for contentPhase atoms - phase transitions
struct ContentPhaseMetadata: Codable, Sendable {
    /// UUID of the content atom
    let contentAtomUUID: String

    /// Previous phase
    let fromPhase: ContentPhase

    /// New phase
    let toPhase: ContentPhase

    /// When the transition occurred
    let timestamp: Date

    /// Word count at transition
    let wordCountAtTransition: Int

    /// Time spent in previous phase (seconds)
    let timeSpentInPreviousPhase: TimeInterval

    /// XP earned for this transition
    let xpEarned: Int

    /// Notes about the transition
    let transitionNotes: String?

    init(
        contentAtomUUID: String,
        fromPhase: ContentPhase,
        toPhase: ContentPhase,
        timestamp: Date = Date(),
        wordCountAtTransition: Int,
        timeSpentInPreviousPhase: TimeInterval,
        xpEarned: Int = 0,
        transitionNotes: String? = nil
    ) {
        self.contentAtomUUID = contentAtomUUID
        self.fromPhase = fromPhase
        self.toPhase = toPhase
        self.timestamp = timestamp
        self.wordCountAtTransition = wordCountAtTransition
        self.timeSpentInPreviousPhase = timeSpentInPreviousPhase
        self.xpEarned = xpEarned
        self.transitionNotes = transitionNotes
    }
}

// MARK: - Content Performance Metadata

/// Metadata for contentPerformance atoms - analytics data
struct ContentPerformanceMetadata: Codable, Sendable {
    /// Platform where content was published
    let platform: SocialPlatform

    /// Post ID on the platform
    let postId: String

    /// When the content was published
    let publishedAt: Date

    /// Number of impressions
    let impressions: Int

    /// Reach (unique viewers)
    let reach: Int

    /// Total engagement (likes + comments + shares + saves)
    let engagement: Int

    /// Number of likes/reactions
    let likes: Int

    /// Number of comments
    let comments: Int

    /// Number of shares/retweets
    let shares: Int

    /// Number of saves/bookmarks
    let saves: Int

    /// Profile visits attributed to this content
    let profileVisits: Int?

    /// Follows gained from this content
    let followsGained: Int?

    /// Engagement rate (engagement / impressions)
    let engagementRate: Double

    /// Virality score (custom calculation)
    let viralityScore: Double?

    /// Whether this content is considered viral
    let isViral: Bool

    /// When this data was last updated
    let lastUpdated: Date

    /// Views (for video content)
    let views: Int?

    /// Watch time in seconds (for video content)
    let watchTimeSeconds: Int?

    /// Average watch percentage (for video content)
    let avgWatchPercentage: Double?

    /// Comparison to user's average performance
    let vsAveragePerformance: Double?

    init(
        platform: SocialPlatform,
        postId: String,
        publishedAt: Date,
        impressions: Int,
        reach: Int,
        engagement: Int,
        likes: Int,
        comments: Int,
        shares: Int,
        saves: Int,
        profileVisits: Int? = nil,
        followsGained: Int? = nil,
        engagementRate: Double,
        viralityScore: Double? = nil,
        isViral: Bool = false,
        lastUpdated: Date = Date(),
        views: Int? = nil,
        watchTimeSeconds: Int? = nil,
        avgWatchPercentage: Double? = nil,
        vsAveragePerformance: Double? = nil
    ) {
        self.platform = platform
        self.postId = postId
        self.publishedAt = publishedAt
        self.impressions = impressions
        self.reach = reach
        self.engagement = engagement
        self.likes = likes
        self.comments = comments
        self.shares = shares
        self.saves = saves
        self.profileVisits = profileVisits
        self.followsGained = followsGained
        self.engagementRate = engagementRate
        self.viralityScore = viralityScore
        self.isViral = isViral
        self.lastUpdated = lastUpdated
        self.views = views
        self.watchTimeSeconds = watchTimeSeconds
        self.avgWatchPercentage = avgWatchPercentage
        self.vsAveragePerformance = vsAveragePerformance
    }

    /// Calculate XP from this performance
    var estimatedXP: Int {
        var xp = 0

        // Base XP for publishing
        xp += 20

        // Impressions XP (5 XP per 10K)
        xp += (impressions / 10_000) * 5

        // Engagement bonus
        if engagementRate > 0.01 {
            xp += Int(engagementRate * 1000)  // 10 XP per 1%
        }

        // Viral bonus
        if isViral {
            xp += 500
        }

        return xp
    }
}

// MARK: - Content Publish Metadata

/// Metadata for contentPublish atoms - publish events
struct ContentPublishMetadata: Codable, Sendable {
    /// UUID of the content atom
    let contentAtomUUID: String

    /// Platform published to
    let platform: SocialPlatform

    /// Post ID on the platform
    let postId: String

    /// When the content was published
    let publishedAt: Date

    /// Post URL (if available)
    let postUrl: String?

    /// Client this was published for (if ghostwriting)
    let clientProfileUUID: String?

    /// Whether this was scheduled vs. immediate publish
    let wasScheduled: Bool

    /// Word count of published content
    let wordCount: Int

    /// Media type (text, image, video, carousel, etc.)
    let mediaType: ContentMediaType

    init(
        contentAtomUUID: String,
        platform: SocialPlatform,
        postId: String,
        publishedAt: Date = Date(),
        postUrl: String? = nil,
        clientProfileUUID: String? = nil,
        wasScheduled: Bool = false,
        wordCount: Int = 0,
        mediaType: ContentMediaType = .text
    ) {
        self.contentAtomUUID = contentAtomUUID
        self.platform = platform
        self.postId = postId
        self.publishedAt = publishedAt
        self.postUrl = postUrl
        self.clientProfileUUID = clientProfileUUID
        self.wasScheduled = wasScheduled
        self.wordCount = wordCount
        self.mediaType = mediaType
    }
}

/// Type of content media
enum ContentMediaType: String, Codable, CaseIterable, Sendable {
    case text
    case image
    case video
    case carousel
    case reel
    case story
    case thread
    case article
    case newsletter
    case other

    var displayName: String {
        switch self {
        case .text: return "Text"
        case .image: return "Image"
        case .video: return "Video"
        case .carousel: return "Carousel"
        case .reel: return "Reel"
        case .story: return "Story"
        case .thread: return "Thread"
        case .article: return "Article"
        case .newsletter: return "Newsletter"
        case .other: return "Other"
        }
    }
}

// MARK: - Profile Document

/// A document stored in the client profile's document library
struct ProfileDocument: Codable, Identifiable, Sendable {
    let id: UUID
    var category: ProfileDocumentCategory
    var title: String
    var content: String
    var filename: String?
    /// Platform (for reel/thread categories)
    var platform: String?
    /// Like count (for reel/thread categories)
    var likes: Int?
    /// Share count (for reel/thread categories)
    var shares: Int?
    /// Save count (for reel/thread categories)
    var saves: Int?
    /// Comment count (for reel/thread categories)
    var comments: Int?
    /// Lead count (for reel/thread categories)
    var leads: Int?
    /// Source Instagram URL if this document was auto-transcribed from a URL
    var sourceURL: String?
    /// Non-fatal warning shown when import quality was degraded.
    var warning: String?

    init(
        id: UUID = UUID(),
        category: ProfileDocumentCategory,
        title: String,
        content: String,
        filename: String? = nil,
        platform: String? = nil,
        likes: Int? = nil,
        shares: Int? = nil,
        saves: Int? = nil,
        comments: Int? = nil,
        leads: Int? = nil,
        sourceURL: String? = nil,
        warning: String? = nil
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.content = content
        self.filename = filename
        self.platform = platform
        self.likes = likes
        self.shares = shares
        self.saves = saves
        self.comments = comments
        self.leads = leads
        self.sourceURL = sourceURL
        self.warning = warning
    }
}

/// Categories for profile documents
enum ProfileDocumentCategory: String, Codable, CaseIterable, Sendable {
    case story           // Brand story / origin narrative
    case reel            // Top-performing reel with transcript + metrics
    case thread          // Top-performing thread/carousel with transcript + metrics
    case voiceGuide      // Voice/style guide document
    case underperformingReel    // Worst-performing reel for failure fingerprint
    case underperformingThread  // Worst-performing thread for failure fingerprint

    var displayName: String {
        switch self {
        case .story: return "Brand Story"
        case .reel: return "Reels"
        case .thread: return "Threads"
        case .voiceGuide: return "Voice Guide"
        case .underperformingReel: return "Underperforming Reels"
        case .underperformingThread: return "Underperforming Threads"
        }
    }

    var iconName: String {
        switch self {
        case .story: return "book.closed"
        case .reel, .underperformingReel: return "play.rectangle.fill"
        case .thread, .underperformingThread: return "text.below.photo.fill"
        case .voiceGuide: return "text.quote"
        }
    }

    /// Whether this category represents high-performing content with metrics
    var isHighPerformer: Bool {
        self == .reel || self == .thread
    }

    /// Whether this category represents underperforming content
    var isUnderperformer: Bool {
        self == .underperformingReel || self == .underperformingThread
    }

    /// Whether this category has performance metrics (likes, shares, etc.)
    var hasMetrics: Bool {
        isHighPerformer || isUnderperformer
    }

    /// Platform tag derived from category, used to filter posts by content format.
    var platformTag: String? {
        switch self {
        case .reel, .underperformingReel: return "reel"
        case .thread, .underperformingThread: return "thread"
        default: return nil
        }
    }

    /// The corresponding top-performer category for an underperformer
    var topPerformerCounterpart: ProfileDocumentCategory? {
        switch self {
        case .underperformingReel: return .reel
        case .underperformingThread: return .thread
        default: return nil
        }
    }

    /// The corresponding underperformer category for a top-performer
    var underperformerCounterpart: ProfileDocumentCategory? {
        switch self {
        case .reel: return .underperformingReel
        case .thread: return .underperformingThread
        default: return nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "topPerformer":
            // Legacy fallback: old topPerformer docs default to .reel
            self = .reel
        default:
            guard let value = ProfileDocumentCategory(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown category: \(rawValue)")
            }
            self = value
        }
    }
}

// MARK: - Intelligence Confidence

/// Confidence level for AI-generated metrics
enum ConfidenceLevel: String, Codable, Sendable {
    case high
    case medium
    case low

    var displayName: String {
        rawValue.capitalized
    }

    var color: Color {
        switch self {
        case .high: return .green
        case .medium: return .yellow
        case .low: return .orange
        }
    }
}

/// Confidence tracking for a specific metric in the intelligence model
struct MetricConfidence: Codable, Sendable {
    let metricPath: String
    let confidence: ConfidenceLevel
    let reasoning: String
}

/// User override for a generated metric value
struct IntelligenceOverride: Codable, Sendable {
    let metricPath: String
    let userValue: String
    let generatedValue: String
    let overrideDate: Date
}

// MARK: - Failure Fingerprint

/// Severity level for failure rules
enum FailureRuleSeverity: String, Codable, Sendable {
    case high       // Strong statistical signal, consistently correlates with poor performance
    case medium     // Moderate signal, some correlation with poor performance
    case low        // Weak but notable signal

    var displayName: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .high: return .red
        case .medium: return .orange
        case .low: return .yellow
        }
    }
}

/// A single failure rule extracted from comparing top vs underperforming content
struct FailureRule: Codable, Identifiable, Sendable {
    let id: UUID
    /// Dimension being measured (e.g., "Hook Length", "Reading Level", "Beat Count")
    let dimension: String
    /// Metric value from top performers (e.g., "11 words avg")
    let bestMetric: String
    /// Metric value from underperformers (e.g., "22 words avg")
    let worstMetric: String
    /// Percentage or absolute delta between best and worst
    let delta: String
    /// Plain-English rule statement (e.g., "AVOID hooks over 15 words")
    let rule: String
    /// How strongly this correlates with poor performance
    let severity: FailureRuleSeverity

    init(
        id: UUID = UUID(),
        dimension: String,
        bestMetric: String,
        worstMetric: String,
        delta: String,
        rule: String,
        severity: FailureRuleSeverity
    ) {
        self.id = id
        self.dimension = dimension
        self.bestMetric = bestMetric
        self.worstMetric = worstMetric
        self.delta = delta
        self.rule = rule
        self.severity = severity
    }
}

/// Failure patterns extracted by comparing top-performing vs underperforming content
struct FailureFingerprint: Codable, Sendable {
    /// All extracted failure rules
    var rules: [FailureRule]
    /// When this fingerprint was generated
    var generatedAt: Date
    /// Number of top-performing documents analyzed
    var topPerformerCount: Int
    /// Number of underperforming documents analyzed
    var underperformerCount: Int

    init(
        rules: [FailureRule] = [],
        generatedAt: Date = Date(),
        topPerformerCount: Int = 0,
        underperformerCount: Int = 0
    ) {
        self.rules = rules
        self.generatedAt = generatedAt
        self.topPerformerCount = topPerformerCount
        self.underperformerCount = underperformerCount
    }

    /// Rules filtered by severity
    func rules(severity: FailureRuleSeverity) -> [FailureRule] {
        rules.filter { $0.severity == severity }
    }

    /// Format rules as directive strings for prompt injection
    func asDirectives() -> [String] {
        rules.map { $0.rule }
    }
}

// MARK: - Client Intelligence Model

/// AI-generated intelligence model from profile documents
struct ClientIntelligenceModel: Codable, Sendable {
    var generatedAt: Date
    var documentCount: DocumentCount
    var voiceFingerprint: IntelligenceVoiceFingerprint
    var performanceFingerprint: IntelligencePerformanceFingerprint
    var audienceModel: IntelligenceAudienceModel
    var nicheAndPositioning: IntelligenceNichePositioning
    var userOverrides: [IntelligenceOverride]
    var confidenceScores: [MetricConfidence]

    // Format-specific fingerprints (optional for backward compat)
    var reelVoiceFingerprint: IntelligenceVoiceFingerprint?
    var reelPerformanceFingerprint: IntelligencePerformanceFingerprint?
    var threadVoiceFingerprint: IntelligenceVoiceFingerprint?
    var threadPerformanceFingerprint: IntelligencePerformanceFingerprint?

    // Failure fingerprints (optional — requires underperformer documents)
    var failureFingerprint: FailureFingerprint?
    var reelFailureFingerprint: FailureFingerprint?
    var threadFailureFingerprint: FailureFingerprint?

    init(
        generatedAt: Date = Date(),
        documentCount: DocumentCount = DocumentCount(),
        voiceFingerprint: IntelligenceVoiceFingerprint = IntelligenceVoiceFingerprint(),
        performanceFingerprint: IntelligencePerformanceFingerprint = IntelligencePerformanceFingerprint(),
        audienceModel: IntelligenceAudienceModel = IntelligenceAudienceModel(),
        nicheAndPositioning: IntelligenceNichePositioning = IntelligenceNichePositioning(),
        userOverrides: [IntelligenceOverride] = [],
        confidenceScores: [MetricConfidence] = [],
        reelVoiceFingerprint: IntelligenceVoiceFingerprint? = nil,
        reelPerformanceFingerprint: IntelligencePerformanceFingerprint? = nil,
        threadVoiceFingerprint: IntelligenceVoiceFingerprint? = nil,
        threadPerformanceFingerprint: IntelligencePerformanceFingerprint? = nil,
        failureFingerprint: FailureFingerprint? = nil,
        reelFailureFingerprint: FailureFingerprint? = nil,
        threadFailureFingerprint: FailureFingerprint? = nil
    ) {
        self.generatedAt = generatedAt
        self.documentCount = documentCount
        self.voiceFingerprint = voiceFingerprint
        self.performanceFingerprint = performanceFingerprint
        self.audienceModel = audienceModel
        self.nicheAndPositioning = nicheAndPositioning
        self.userOverrides = userOverrides
        self.confidenceScores = confidenceScores
        self.reelVoiceFingerprint = reelVoiceFingerprint
        self.reelPerformanceFingerprint = reelPerformanceFingerprint
        self.threadVoiceFingerprint = threadVoiceFingerprint
        self.threadPerformanceFingerprint = threadPerformanceFingerprint
        self.failureFingerprint = failureFingerprint
        self.reelFailureFingerprint = reelFailureFingerprint
        self.threadFailureFingerprint = threadFailureFingerprint
    }
}

/// Format view selector for the intelligence model UI
enum IntelligenceFormatView: String, CaseIterable {
    case overall = "Overall"
    case reels = "Reels"
    case threads = "Threads"
}

/// Document count by category
struct DocumentCount: Codable, Sendable {
    var story: Int
    var reels: Int
    var threads: Int
    var voiceGuide: Int
    var underperformingReels: Int
    var underperformingThreads: Int

    init(story: Int = 0, reels: Int = 0, threads: Int = 0, voiceGuide: Int = 0,
         underperformingReels: Int = 0, underperformingThreads: Int = 0) {
        self.story = story
        self.reels = reels
        self.threads = threads
        self.voiceGuide = voiceGuide
        self.underperformingReels = underperformingReels
        self.underperformingThreads = underperformingThreads
    }

    /// Whether underperformer data is available for failure fingerprint generation
    var hasUnderperformers: Bool {
        underperformingReels > 0 || underperformingThreads > 0
    }

    private enum CodingKeys: String, CodingKey {
        case story, reels, threads, voiceGuide
        case underperformingReels, underperformingThreads
        case legacyTopPerformers = "topPerformers"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        story = try container.decodeIfPresent(Int.self, forKey: .story) ?? 0
        reels = try container.decodeIfPresent(Int.self, forKey: .reels) ?? 0
        threads = try container.decodeIfPresent(Int.self, forKey: .threads) ?? 0
        voiceGuide = try container.decodeIfPresent(Int.self, forKey: .voiceGuide) ?? 0
        underperformingReels = try container.decodeIfPresent(Int.self, forKey: .underperformingReels) ?? 0
        underperformingThreads = try container.decodeIfPresent(Int.self, forKey: .underperformingThreads) ?? 0
        // Legacy: map old topPerformers count to reels
        if reels == 0 && threads == 0,
           let legacy = try container.decodeIfPresent(Int.self, forKey: .legacyTopPerformers) {
            reels = legacy
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(story, forKey: .story)
        try container.encode(reels, forKey: .reels)
        try container.encode(threads, forKey: .threads)
        try container.encode(voiceGuide, forKey: .voiceGuide)
        try container.encode(underperformingReels, forKey: .underperformingReels)
        try container.encode(underperformingThreads, forKey: .underperformingThreads)
    }
}

/// Voice analysis extracted from content documents
struct IntelligenceVoiceFingerprint: Codable, Sendable {
    var avgSentenceLength: Double
    var maxSentenceLength: Int
    var sentenceStarterDistribution: [String: Double]
    var readingLevel: String
    var powerWords: [String]
    var emotionalToneDistribution: [String: Double]
    var punctuationStyle: String
    var ctaPattern: String
    var signaturePhrases: [String]
    var blacklistedPhrases: [String]
    var paragraphLength: String
    var formattingQuirks: [String]

    init(
        avgSentenceLength: Double = 0,
        maxSentenceLength: Int = 0,
        sentenceStarterDistribution: [String: Double] = [:],
        readingLevel: String = "",
        powerWords: [String] = [],
        emotionalToneDistribution: [String: Double] = [:],
        punctuationStyle: String = "",
        ctaPattern: String = "",
        signaturePhrases: [String] = [],
        blacklistedPhrases: [String] = [],
        paragraphLength: String = "",
        formattingQuirks: [String] = []
    ) {
        self.avgSentenceLength = avgSentenceLength
        self.maxSentenceLength = maxSentenceLength
        self.sentenceStarterDistribution = sentenceStarterDistribution
        self.readingLevel = readingLevel
        self.powerWords = powerWords
        self.emotionalToneDistribution = emotionalToneDistribution
        self.punctuationStyle = punctuationStyle
        self.ctaPattern = ctaPattern
        self.signaturePhrases = signaturePhrases
        self.blacklistedPhrases = blacklistedPhrases
        self.paragraphLength = paragraphLength
        self.formattingQuirks = formattingQuirks
    }
}

/// Performance patterns extracted from top-performing content
struct IntelligencePerformanceFingerprint: Codable, Sendable {
    var hookTypePerformance: [String: Double]
    var bestBeatPatterns: [String]
    var optimalLength: String
    var bestTopics: [String]
    var engagementTriggers: [String]
    var formatComparison: [String: Double]

    init(
        hookTypePerformance: [String: Double] = [:],
        bestBeatPatterns: [String] = [],
        optimalLength: String = "",
        bestTopics: [String] = [],
        engagementTriggers: [String] = [],
        formatComparison: [String: Double] = [:]
    ) {
        self.hookTypePerformance = hookTypePerformance
        self.bestBeatPatterns = bestBeatPatterns
        self.optimalLength = optimalLength
        self.bestTopics = bestTopics
        self.engagementTriggers = engagementTriggers
        self.formatComparison = formatComparison
    }
}

/// Audience model derived from content analysis
struct IntelligenceAudienceModel: Codable, Sendable {
    var primaryAudience: String
    var topPainPoints: [String]
    var aspirationalOutcomes: [String]
    var commonObjections: [String]
    var audienceLanguage: [String]

    init(
        primaryAudience: String = "",
        topPainPoints: [String] = [],
        aspirationalOutcomes: [String] = [],
        commonObjections: [String] = [],
        audienceLanguage: [String] = []
    ) {
        self.primaryAudience = primaryAudience
        self.topPainPoints = topPainPoints
        self.aspirationalOutcomes = aspirationalOutcomes
        self.commonObjections = commonObjections
        self.audienceLanguage = audienceLanguage
    }
}

/// Niche positioning extracted from brand story and content
struct IntelligenceNichePositioning: Codable, Sendable {
    var specificNiche: String
    var uniqueAngle: String
    var coreBeliefs: [String]
    var enemies: [String]
    var uniqueMechanism: String

    init(
        specificNiche: String = "",
        uniqueAngle: String = "",
        coreBeliefs: [String] = [],
        enemies: [String] = [],
        uniqueMechanism: String = ""
    ) {
        self.specificNiche = specificNiche
        self.uniqueAngle = uniqueAngle
        self.coreBeliefs = coreBeliefs
        self.enemies = enemies
        self.uniqueMechanism = uniqueMechanism
    }
}

// MARK: - Top Post

/// A top-performing post with transcript and metrics for voice extraction
struct TopPost: Codable, Identifiable, Sendable {
    let id: UUID
    var transcript: String
    var platform: String
    var likes: Int
    var shares: Int
    var leads: Int
    var views: Int
    var datePosted: String

    init(
        id: UUID = UUID(),
        transcript: String = "",
        platform: String = "",
        likes: Int = 0,
        shares: Int = 0,
        leads: Int = 0,
        views: Int = 0,
        datePosted: String = ""
    ) {
        self.id = id
        self.transcript = transcript
        self.platform = platform
        self.likes = likes
        self.shares = shares
        self.leads = leads
        self.views = views
        self.datePosted = datePosted
    }
}

// MARK: - Voice Profile

/// Extracted voice patterns from top-performing content
struct VoiceProfile: Codable, Sendable {
    var avgSentenceLength: Double
    var hookStyleDistribution: [String: Int]
    var ctaPatterns: [String]
    var recurringPhrases: [String]
    var emotionalRange: String
    var readingLevel: String
    var stylisticQuirks: [String]

    init(
        avgSentenceLength: Double = 0,
        hookStyleDistribution: [String: Int] = [:],
        ctaPatterns: [String] = [],
        recurringPhrases: [String] = [],
        emotionalRange: String = "",
        readingLevel: String = "",
        stylisticQuirks: [String] = []
    ) {
        self.avgSentenceLength = avgSentenceLength
        self.hookStyleDistribution = hookStyleDistribution
        self.ctaPatterns = ctaPatterns
        self.recurringPhrases = recurringPhrases
        self.emotionalRange = emotionalRange
        self.readingLevel = readingLevel
        self.stylisticQuirks = stylisticQuirks
    }
}

// MARK: - Client Profile Metadata

/// Metadata for clientProfile atoms - ghostwriting clients
struct ClientProfileMetadata: Codable, Sendable {
    /// Unique client identifier
    let clientId: String

    /// Client display name
    let clientName: String

    /// Platforms this client is active on
    let platforms: [SocialPlatform]

    /// Total lifetime reach for this client
    let totalReach: Int

    /// Average engagement rate across all content
    let avgEngagementRate: Double

    /// Total content pieces created for this client
    let contentCount: Int

    /// Viral post count
    let viralPostCount: Int

    /// Whether this client relationship is currently active
    let activeStatus: Bool

    /// When this client was added
    let clientSince: Date

    /// Last content published for this client
    let lastContentDate: Date?

    /// Notes about the client
    let notes: String?

    /// Client industry/niche
    let industry: String?

    /// Target audience description
    let targetAudience: String?

    // MARK: - Brand Context (WP3 extension)

    /// The client's origin story / brand narrative
    var brandStory: String?

    /// The client's long-term vision or mission
    var brandVision: String?

    /// Core beliefs or values that drive content
    var coreBeliefs: [String]?

    /// Notes about the client's voice, tone, and style
    var voiceNotes: String?

    /// What makes this client's perspective unique
    var uniqueAngle: String?

    // MARK: - Performance Context

    /// UUIDs of top-performing posts for reference
    var topPerformingPostIds: [String]?

    /// Transcripts or text of top-performing content
    var topPerformingTranscripts: [String]?

    /// Content formats that perform best for this client (raw ContentFormat values)
    var bestFormats: [String]?

    // MARK: - Posting Context

    /// Posting frequency description (e.g., "3x/week", "daily")
    var postingFrequency: String?

    /// Preferred posting times (e.g., ["9:00 AM EST", "6:00 PM EST"])
    var preferredPostTimes: [String]?

    // MARK: - Identity (merged from ClientMetadata)

    /// Primary social handle (e.g., "@creator")
    var handle: String?

    /// Client's niche / content vertical
    var niche: String?

    /// Whether this is a personal brand (vs. company/agency)
    var isPersonalBrand: Bool?

    /// Signature phrases, catchphrases, recurring openers, trademark expressions
    var signaturePhrases: [String]?

    // MARK: - Intelligence Model (Client Intelligence Engine)

    /// AI-generated intelligence model from profile documents
    var intelligenceModel: ClientIntelligenceModel?

    /// Document library for this profile
    var documents: [ProfileDocument]?

    /// Primary platform for content creation
    var primaryPlatform: SocialPlatform?

    /// Preserved legacy field values after migration
    var legacyFields: [String: String]?

    // MARK: - Voice Intelligence (WP5 extension)

    /// Top-performing posts with full transcripts and metrics
    var topPerformingPosts: [TopPost]?

    /// AI-extracted voice patterns from top-performing content
    var extractedVoicePatterns: VoiceProfile?

    /// Preferred beat patterns (e.g., ["preferred:BoldClaim>Discovery>Proof>CTA"])
    var preferredBeatPatterns: [String]?

    init(
        clientId: String,
        clientName: String,
        platforms: [SocialPlatform],
        totalReach: Int = 0,
        avgEngagementRate: Double = 0,
        contentCount: Int = 0,
        viralPostCount: Int = 0,
        activeStatus: Bool = true,
        clientSince: Date = Date(),
        lastContentDate: Date? = nil,
        notes: String? = nil,
        industry: String? = nil,
        targetAudience: String? = nil,
        brandStory: String? = nil,
        brandVision: String? = nil,
        coreBeliefs: [String]? = nil,
        voiceNotes: String? = nil,
        uniqueAngle: String? = nil,
        topPerformingPostIds: [String]? = nil,
        topPerformingTranscripts: [String]? = nil,
        bestFormats: [String]? = nil,
        postingFrequency: String? = nil,
        preferredPostTimes: [String]? = nil,
        handle: String? = nil,
        niche: String? = nil,
        isPersonalBrand: Bool? = nil,
        signaturePhrases: [String]? = nil,
        intelligenceModel: ClientIntelligenceModel? = nil,
        documents: [ProfileDocument]? = nil,
        primaryPlatform: SocialPlatform? = nil,
        legacyFields: [String: String]? = nil,
        topPerformingPosts: [TopPost]? = nil,
        extractedVoicePatterns: VoiceProfile? = nil,
        preferredBeatPatterns: [String]? = nil
    ) {
        self.clientId = clientId
        self.clientName = clientName
        self.platforms = platforms
        self.totalReach = totalReach
        self.avgEngagementRate = avgEngagementRate
        self.contentCount = contentCount
        self.viralPostCount = viralPostCount
        self.activeStatus = activeStatus
        self.clientSince = clientSince
        self.lastContentDate = lastContentDate
        self.notes = notes
        self.industry = industry
        self.targetAudience = targetAudience
        self.brandStory = brandStory
        self.brandVision = brandVision
        self.coreBeliefs = coreBeliefs
        self.voiceNotes = voiceNotes
        self.uniqueAngle = uniqueAngle
        self.topPerformingPostIds = topPerformingPostIds
        self.topPerformingTranscripts = topPerformingTranscripts
        self.bestFormats = bestFormats
        self.postingFrequency = postingFrequency
        self.preferredPostTimes = preferredPostTimes
        self.handle = handle
        self.niche = niche
        self.isPersonalBrand = isPersonalBrand
        self.signaturePhrases = signaturePhrases
        self.intelligenceModel = intelligenceModel
        self.documents = documents
        self.primaryPlatform = primaryPlatform
        self.legacyFields = legacyFields
        self.topPerformingPosts = topPerformingPosts
        self.extractedVoicePatterns = extractedVoicePatterns
        self.preferredBeatPatterns = preferredBeatPatterns
    }

    // MARK: - Resilient Decoding

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Required fields with fallbacks for older saved profiles
        clientId = try container.decodeIfPresent(String.self, forKey: .clientId) ?? UUID().uuidString
        clientName = try container.decodeIfPresent(String.self, forKey: .clientName) ?? ""
        platforms = try container.decodeIfPresent([SocialPlatform].self, forKey: .platforms) ?? []
        totalReach = try container.decodeIfPresent(Int.self, forKey: .totalReach) ?? 0
        avgEngagementRate = try container.decodeIfPresent(Double.self, forKey: .avgEngagementRate) ?? 0
        contentCount = try container.decodeIfPresent(Int.self, forKey: .contentCount) ?? 0
        viralPostCount = try container.decodeIfPresent(Int.self, forKey: .viralPostCount) ?? 0
        activeStatus = try container.decodeIfPresent(Bool.self, forKey: .activeStatus) ?? true
        clientSince = try container.decodeIfPresent(Date.self, forKey: .clientSince) ?? Date()
        lastContentDate = try container.decodeIfPresent(Date.self, forKey: .lastContentDate)

        // Optional fields
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        industry = try container.decodeIfPresent(String.self, forKey: .industry)
        targetAudience = try container.decodeIfPresent(String.self, forKey: .targetAudience)
        brandStory = try container.decodeIfPresent(String.self, forKey: .brandStory)
        brandVision = try container.decodeIfPresent(String.self, forKey: .brandVision)
        coreBeliefs = try container.decodeIfPresent([String].self, forKey: .coreBeliefs)
        voiceNotes = try container.decodeIfPresent(String.self, forKey: .voiceNotes)
        uniqueAngle = try container.decodeIfPresent(String.self, forKey: .uniqueAngle)
        topPerformingPostIds = try container.decodeIfPresent([String].self, forKey: .topPerformingPostIds)
        topPerformingTranscripts = try container.decodeIfPresent([String].self, forKey: .topPerformingTranscripts)
        bestFormats = try container.decodeIfPresent([String].self, forKey: .bestFormats)
        postingFrequency = try container.decodeIfPresent(String.self, forKey: .postingFrequency)
        preferredPostTimes = try container.decodeIfPresent([String].self, forKey: .preferredPostTimes)
        handle = try container.decodeIfPresent(String.self, forKey: .handle)
        niche = try container.decodeIfPresent(String.self, forKey: .niche)
        isPersonalBrand = try container.decodeIfPresent(Bool.self, forKey: .isPersonalBrand)
        signaturePhrases = try container.decodeIfPresent([String].self, forKey: .signaturePhrases)
        intelligenceModel = try container.decodeIfPresent(ClientIntelligenceModel.self, forKey: .intelligenceModel)
        documents = try container.decodeIfPresent([ProfileDocument].self, forKey: .documents)
        primaryPlatform = try container.decodeIfPresent(SocialPlatform.self, forKey: .primaryPlatform)
        legacyFields = try container.decodeIfPresent([String: String].self, forKey: .legacyFields)
        topPerformingPosts = try container.decodeIfPresent([TopPost].self, forKey: .topPerformingPosts)
        extractedVoicePatterns = try container.decodeIfPresent(VoiceProfile.self, forKey: .extractedVoicePatterns)
        preferredBeatPatterns = try container.decodeIfPresent([String].self, forKey: .preferredBeatPatterns)
    }
}

// MARK: - Knowledge Graph Metadata

/// Metadata for semanticCluster atoms - auto-grouped concepts
struct SemanticClusterMetadata: Codable, Sendable {
    /// Cluster name/topic
    let clusterName: String

    /// UUIDs of atoms in this cluster
    let memberAtomUUIDs: [String]

    /// Centroid embedding (for similarity calculations)
    let centroidEmbedding: [Float]?

    /// Keywords that define this cluster
    let keywords: [String]

    /// When the cluster was created
    let createdAt: Date

    /// When the cluster was last updated
    let lastUpdated: Date

    /// Confidence score for this cluster (0-1)
    let confidence: Double

    /// Parent cluster UUID (for hierarchical clustering)
    let parentClusterUUID: String?

    init(
        clusterName: String,
        memberAtomUUIDs: [String],
        centroidEmbedding: [Float]? = nil,
        keywords: [String] = [],
        createdAt: Date = Date(),
        lastUpdated: Date = Date(),
        confidence: Double = 1.0,
        parentClusterUUID: String? = nil
    ) {
        self.clusterName = clusterName
        self.memberAtomUUIDs = memberAtomUUIDs
        self.centroidEmbedding = centroidEmbedding
        self.keywords = keywords
        self.createdAt = createdAt
        self.lastUpdated = lastUpdated
        self.confidence = confidence
        self.parentClusterUUID = parentClusterUUID
    }
}

/// Metadata for autoLinkSuggestion atoms - AI-suggested links
struct AutoLinkSuggestionMetadata: Codable, Sendable {
    /// Source atom UUID
    let sourceAtomUUID: String

    /// Target atom UUID (suggested link)
    let targetAtomUUID: String

    /// Similarity score (0-1)
    let similarityScore: Double

    /// Reason for the suggestion
    let reason: String

    /// Link type suggested
    let suggestedLinkType: String  // AtomLinkType.rawValue

    /// Whether the user accepted this suggestion
    let wasAccepted: Bool?

    /// When this suggestion was generated
    let generatedAt: Date

    /// When the user responded (if any)
    let respondedAt: Date?

    init(
        sourceAtomUUID: String,
        targetAtomUUID: String,
        similarityScore: Double,
        reason: String,
        suggestedLinkType: String,
        wasAccepted: Bool? = nil,
        generatedAt: Date = Date(),
        respondedAt: Date? = nil
    ) {
        self.sourceAtomUUID = sourceAtomUUID
        self.targetAtomUUID = targetAtomUUID
        self.similarityScore = similarityScore
        self.reason = reason
        self.suggestedLinkType = suggestedLinkType
        self.wasAccepted = wasAccepted
        self.generatedAt = generatedAt
        self.respondedAt = respondedAt
    }
}

/// Metadata for insightExtraction atoms - AI-extracted insights
struct InsightExtractionMetadata: Codable, Sendable {
    /// Source atom UUID this insight was extracted from
    let sourceAtomUUID: String

    /// Type of insight
    let insightType: InsightType

    /// The extracted insight text
    let insightText: String

    /// Confidence in this extraction (0-1)
    let confidence: Double

    /// Keywords related to this insight
    let keywords: [String]

    /// Suggested actions based on this insight
    let suggestedActions: [String]

    /// Linked atom UUIDs (related content)
    let linkedAtomUUIDs: [String]

    /// When this insight was extracted
    let extractedAt: Date

    init(
        sourceAtomUUID: String,
        insightType: InsightType,
        insightText: String,
        confidence: Double,
        keywords: [String] = [],
        suggestedActions: [String] = [],
        linkedAtomUUIDs: [String] = [],
        extractedAt: Date = Date()
    ) {
        self.sourceAtomUUID = sourceAtomUUID
        self.insightType = insightType
        self.insightText = insightText
        self.confidence = confidence
        self.keywords = keywords
        self.suggestedActions = suggestedActions
        self.linkedAtomUUIDs = linkedAtomUUIDs
        self.extractedAt = extractedAt
    }
}

// Note: InsightType is now defined in ReflectionMetadata.swift
