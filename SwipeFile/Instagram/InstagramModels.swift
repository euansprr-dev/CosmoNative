// CosmoOS/SwipeFile/Instagram/InstagramModels.swift
// Data models for Instagram content extraction and display
// Per Instagram Research PRD Addendum

import Foundation

// MARK: - Instagram Content Type

/// Type of Instagram content
enum InstagramContentType: String, Codable, Sendable, CaseIterable, Equatable {
    case reel           // Single vertical video (9:16)
    case videoPost      // Single video in feed format (varies)
    case carousel       // Multiple images/videos
    case image          // Single image
    case story          // Story (if supported)

    var isVideo: Bool {
        switch self {
        case .reel, .videoPost: return true
        case .carousel: return false // May contain videos, but treated differently
        case .image, .story: return false
        }
    }

    /// Whether this content type uses side-by-side layout
    var usesSideBySideLayout: Bool {
        switch self {
        case .reel, .story: return true
        case .videoPost: return true // Will check aspect ratio at runtime
        case .carousel, .image: return false
        }
    }
}

// MARK: - Instagram Media Data

/// Extracted media data from Instagram
struct InstagramMediaData: Codable, Sendable, Equatable {
    let originalURL: URL
    let contentType: InstagramContentType
    let videoURL: URL?              // Direct CDN URL for video
    let thumbnailURL: URL?
    let duration: TimeInterval?
    let authorUsername: String?
    let caption: String?
    let carouselItems: [CarouselItem]?
    let extractedAt: Date

    /// Check if CDN URL has expired (24-hour cache)
    var isExpired: Bool {
        Date().timeIntervalSince(extractedAt) > 24 * 60 * 60  // 24 hours
    }

    init(
        originalURL: URL,
        contentType: InstagramContentType,
        videoURL: URL? = nil,
        thumbnailURL: URL? = nil,
        duration: TimeInterval? = nil,
        authorUsername: String? = nil,
        caption: String? = nil,
        carouselItems: [CarouselItem]? = nil,
        extractedAt: Date = Date()
    ) {
        self.originalURL = originalURL
        self.contentType = contentType
        self.videoURL = videoURL
        self.thumbnailURL = thumbnailURL
        self.duration = duration
        self.authorUsername = authorUsername
        self.caption = caption
        self.carouselItems = carouselItems
        self.extractedAt = extractedAt
    }
}

// MARK: - Carousel Item

/// A single item in an Instagram carousel
struct CarouselItem: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let index: Int
    let mediaType: CarouselMediaType
    let mediaURL: URL
    let thumbnailURL: URL?
    let duration: TimeInterval?  // For videos

    init(
        id: UUID = UUID(),
        index: Int,
        mediaType: CarouselMediaType,
        mediaURL: URL,
        thumbnailURL: URL? = nil,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.index = index
        self.mediaType = mediaType
        self.mediaURL = mediaURL
        self.thumbnailURL = thumbnailURL
        self.duration = duration
    }
}

/// Media type within a carousel
enum CarouselMediaType: String, Codable, Sendable, Equatable {
    case image
    case video
}

// MARK: - Instagram Data (Stored in Research Atom)

/// Instagram-specific data stored in research atom
struct InstagramData: Codable, Sendable, Equatable {
    let originalURL: URL
    let contentType: InstagramContentType

    var authorUsername: String?
    var caption: String?
    var extractedMediaURL: URL?
    var extractedAt: Date?
    var carouselItems: [CarouselItem]?

    // Manual transcript (for reels/videos without auto-transcript)
    var manualTranscript: ManualTranscript?

    // Aspect ratio for layout decisions
    var aspectRatio: Double?  // height/width - > 1.0 means vertical

    init(
        originalURL: URL,
        contentType: InstagramContentType,
        authorUsername: String? = nil,
        caption: String? = nil,
        extractedMediaURL: URL? = nil,
        extractedAt: Date? = nil,
        carouselItems: [CarouselItem]? = nil,
        manualTranscript: ManualTranscript? = nil,
        aspectRatio: Double? = nil
    ) {
        self.originalURL = originalURL
        self.contentType = contentType
        self.authorUsername = authorUsername
        self.caption = caption
        self.extractedMediaURL = extractedMediaURL
        self.extractedAt = extractedAt
        self.carouselItems = carouselItems
        self.manualTranscript = manualTranscript
        self.aspectRatio = aspectRatio
    }

    /// Check if extracted URL has expired
    var isExpired: Bool {
        guard let extractedAt = extractedAt else { return true }
        return Date().timeIntervalSince(extractedAt) > 24 * 60 * 60
    }

    /// Whether this content should use side-by-side layout
    var usesSideBySideLayout: Bool {
        switch contentType {
        case .reel, .story:
            return true
        case .videoPost:
            // Check aspect ratio - vertical videos use side-by-side
            if let ratio = aspectRatio {
                return ratio > 1.0  // Vertical
            }
            return false
        case .carousel, .image:
            return false
        }
    }
}

// MARK: - Manual Transcript

/// Manual transcript for Instagram content (no auto-transcript available)
struct ManualTranscript: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    let researchAtomID: String
    var sections: [ManualTranscriptSection]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        researchAtomID: String,
        sections: [ManualTranscriptSection] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.researchAtomID = researchAtomID
        self.sections = sections
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Manual Transcript Section

/// A section of manually transcribed content with timing
struct ManualTranscriptSection: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var startTime: TimeInterval
    var endTime: TimeInterval?  // nil = until next section or end
    var text: String
    var annotations: [InstagramAnnotation]

    // Not persisted - UI state only
    var isEditing: Bool {
        get { false }
        set { }  // Ignored for Codable
    }

    enum CodingKeys: String, CodingKey {
        case id, startTime, endTime, text, annotations
    }

    static func == (lhs: ManualTranscriptSection, rhs: ManualTranscriptSection) -> Bool {
        lhs.id == rhs.id &&
        lhs.startTime == rhs.startTime &&
        lhs.endTime == rhs.endTime &&
        lhs.text == rhs.text &&
        lhs.annotations == rhs.annotations
    }

    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval? = nil,
        text: String,
        annotations: [InstagramAnnotation] = []
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.annotations = annotations
    }

    /// Formatted time range for display
    var displayTimeRange: String {
        let start = formatTime(startTime)
        if let end = endTime {
            return "\(start) - \(formatTime(end))"
        }
        return "\(start) - ..."
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

// MARK: - Instagram Annotation

/// Annotation on Instagram content (per-section or per-slide)
struct InstagramAnnotation: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var type: AnnotationType
    var content: String
    var timestamp: TimeInterval?  // For video annotations
    var slideIndex: Int?          // For carousel annotations
    var linkedAtomUUIDs: [String]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        type: AnnotationType,
        content: String,
        timestamp: TimeInterval? = nil,
        slideIndex: Int? = nil,
        linkedAtomUUIDs: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.content = content
        self.timestamp = timestamp
        self.slideIndex = slideIndex
        self.linkedAtomUUIDs = linkedAtomUUIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Annotation type (matches existing research annotation types)
    enum AnnotationType: String, Codable, Sendable, Equatable {
        case note       // Green - observations, connections
        case question   // Orange - things to investigate
        case insight    // Purple - realizations, synthesis
    }
}

// MARK: - Research Layout Type

/// Layout type for research content
enum ResearchLayoutType: String, Codable, Sendable, Equatable {
    case standard       // Top-down (video/content above, transcript below)
    case sideBySide     // Left-right (video left, transcript right) - for reels
    case carousel       // Carousel viewer with per-slide notes
}

// MARK: - Extraction Error

/// Errors during Instagram extraction
enum InstagramExtractionError: LocalizedError {
    case invalidURL
    case invalidResponse
    case couldNotExtract
    case contentNotVideo
    case urlExpired
    case privateContent
    case deletedContent
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Instagram URL"
        case .invalidResponse:
            return "Could not parse Instagram response"
        case .couldNotExtract:
            return "Could not extract media from Instagram"
        case .contentNotVideo:
            return "Content is not a video"
        case .urlExpired:
            return "Media URL has expired"
        case .privateContent:
            return "This content is private"
        case .deletedContent:
            return "This content has been deleted"
        case .rateLimited:
            return "Too many requests - try again later"
        }
    }
}
