import Foundation

struct SocialPlatformIdentity: Equatable, Hashable, Sendable {
    let platform: SocialPlatform
    let handle: String
    let profileURL: URL?
}

enum SocialProviderCapability: String, CaseIterable, Codable, Hashable, Sendable {
    case keywordDiscovery
    case creatorLookup
    case creatorCatalog
    case postLookup
    case engagementMetrics
    case nativeTranscript
}

protocol SocialDiscoveryProvider: Sendable {
    var id: String { get }
    var capabilities: Set<SocialProviderCapability> { get }

    func supports(platform: SocialPlatform) -> Bool
}

enum SocialContentFormat: String, CaseIterable, Codable, Hashable, Sendable {
    case shortVideo
    case longVideo
    case image
    case carousel
    case text
    case newsletter
    case link
    case unknown
}

struct SocialCreatorSnapshot: Codable, Equatable, Hashable, Sendable {
    let platformID: String
    let handle: String
    let displayName: String
    let avatarURL: URL?
    let followerCount: Int?

    init(
        platformID: String,
        handle: String,
        displayName: String,
        avatarURL: URL?,
        followerCount: Int?
    ) {
        self.platformID = platformID
        self.handle = handle
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.followerCount = followerCount
    }
}

struct SocialMediaAsset: Codable, Equatable, Hashable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable {
        case image
        case video
        case thumbnail
        case document
    }

    let kind: Kind
    let url: URL
    let width: Int?
    let height: Int?
    let duration: TimeInterval?

    init(kind: Kind, url: URL, width: Int? = nil, height: Int? = nil, duration: TimeInterval? = nil) {
        self.kind = kind
        self.url = url
        self.width = width
        self.height = height
        self.duration = duration
    }
}

struct SocialEngagementMetrics: Codable, Equatable, Hashable, Sendable {
    let views: Int?
    let likes: Int?
    let comments: Int?
    let shares: Int?
    let saves: Int?
    let reposts: Int?
    let impressions: Int?

    init(
        views: Int? = nil,
        likes: Int? = nil,
        comments: Int? = nil,
        shares: Int? = nil,
        saves: Int? = nil,
        reposts: Int? = nil,
        impressions: Int? = nil
    ) {
        self.views = views
        self.likes = likes
        self.comments = comments
        self.shares = shares
        self.saves = saves
        self.reposts = reposts
        self.impressions = impressions
    }
}

struct SocialDerivedMetrics: Codable, Equatable, Hashable, Sendable {
    static let empty = SocialDerivedMetrics(
        outlierMultiplier: nil,
        outlierGrade: .insufficientData,
        engagementRate: nil
    )

    let outlierMultiplier: Double?
    let outlierGrade: SocialOutlierGrade
    let engagementRate: Double?
}

enum SocialTranscriptState: Codable, Equatable, Hashable, Sendable {
    case none
    case available(String)
    case unavailable(reason: String)
    case failed(reason: String)
}

enum SocialSaveState: String, Codable, Hashable, Sendable {
    case unsaved
    case saved
}

struct SocialPostSnapshot: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let platform: SocialPlatform
    let provider: String
    let providerPostID: String
    let canonicalURL: URL
    let title: String?
    let body: String?
    let media: [SocialMediaAsset]
    let author: SocialCreatorSnapshot
    let publishedAt: Date?
    let detectedLanguage: String?
    let format: SocialContentFormat
    let metrics: SocialEngagementMetrics
    let derived: SocialDerivedMetrics
    let transcriptState: SocialTranscriptState
    let saveState: SocialSaveState
    let rawProviderPayload: Data?

    init(
        id: String,
        platform: SocialPlatform,
        provider: String,
        providerPostID: String,
        canonicalURL: URL,
        title: String?,
        body: String?,
        media: [SocialMediaAsset],
        author: SocialCreatorSnapshot,
        publishedAt: Date?,
        detectedLanguage: String?,
        format: SocialContentFormat,
        metrics: SocialEngagementMetrics,
        derived: SocialDerivedMetrics,
        transcriptState: SocialTranscriptState,
        saveState: SocialSaveState,
        rawProviderPayload: Data?
    ) {
        self.id = id
        self.platform = platform
        self.provider = provider
        self.providerPostID = providerPostID
        self.canonicalURL = canonicalURL
        self.title = title
        self.body = body
        self.media = media
        self.author = author
        self.publishedAt = publishedAt
        self.detectedLanguage = detectedLanguage
        self.format = format
        self.metrics = metrics
        self.derived = derived
        self.transcriptState = transcriptState
        self.saveState = saveState
        self.rawProviderPayload = rawProviderPayload
    }
}
