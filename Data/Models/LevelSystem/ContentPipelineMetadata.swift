// CosmoOS/Data/Models/LevelSystem/ContentPipelineMetadata.swift
// Metadata structures for content creation and performance tracking
// Supports content drafts, phases, performance analytics, and client profiles

import Foundation

// MARK: - Content Phase

/// Phases in the content creation pipeline
public enum ContentPhase: String, Codable, CaseIterable, Sendable {
    case ideation           // Initial concept
    case outline            // Structure defined
    case draft              // First draft
    case polish             // Editing/refining
    case scheduled          // Ready for publish
    case published          // Live
    case analyzing          // Gathering performance data
    case archived           // Historical

    var displayName: String {
        switch self {
        case .ideation: return "Ideation"
        case .outline: return "Outline"
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
        case .outline: return "list.bullet"
        case .draft: return "doc.text"
        case .polish: return "sparkles"
        case .scheduled: return "calendar.badge.clock"
        case .published: return "paperplane.fill"
        case .analyzing: return "chart.bar"
        case .archived: return "archivebox"
        }
    }

    /// Next phase in the pipeline
    var nextPhase: ContentPhase? {
        switch self {
        case .ideation: return .outline
        case .outline: return .draft
        case .draft: return .polish
        case .polish: return .scheduled
        case .scheduled: return .published
        case .published: return .analyzing
        case .analyzing: return .archived
        case .archived: return nil
        }
    }

    /// XP earned for completing this phase
    var completionXP: Int {
        switch self {
        case .ideation: return 5
        case .outline: return 10
        case .draft: return 25
        case .polish: return 15
        case .scheduled: return 5
        case .published: return 20
        case .analyzing: return 0
        case .archived: return 0
        }
    }
}

// MARK: - Social Platform

/// Supported social media platforms
public enum SocialPlatform: String, Codable, CaseIterable, Sendable {
    case twitter
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
        targetAudience: String? = nil
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
