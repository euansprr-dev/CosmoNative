// CosmoOS/UI/FocusMode/Research/ResearchFocusModeState.swift
// Data models and state for Research Focus Mode
// December 2025 - Research Focus Mode with transcript annotations

import SwiftUI
import Foundation

// MARK: - Research Content Type

/// The type of research content being displayed
enum ResearchContentType: String, Codable, CaseIterable {
    case video      // YouTube, Vimeo, Loom
    case article    // Web articles, blog posts
    case pdf        // PDF documents
    case social     // Twitter/X, LinkedIn posts
    case generic    // Unknown or unsupported type

    var icon: String {
        switch self {
        case .video: return "play.rectangle.fill"
        case .article: return "doc.richtext.fill"
        case .pdf: return "doc.text.fill"
        case .social: return "bubble.left.and.bubble.right.fill"
        case .generic: return "link"
        }
    }

    var label: String {
        switch self {
        case .video: return "Video"
        case .article: return "Article"
        case .pdf: return "PDF"
        case .social: return "Social"
        case .generic: return "Link"
        }
    }
}

// MARK: - Research Source

/// Information about the source of research content
struct ResearchSource: Codable, Equatable {
    let url: String
    let platform: String?           // YouTube, Medium, etc.
    let author: String?
    let channelName: String?
    let publishedAt: Date?
    let duration: TimeInterval?     // For video content
    let thumbnailURL: String?

    /// Formatted duration string (mm:ss or hh:mm:ss)
    var durationString: String? {
        guard let duration = duration else { return nil }
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    /// Detect platform from URL
    static func detectPlatform(from url: String) -> String? {
        let urlLower = url.lowercased()
        if urlLower.contains("youtube.com") || urlLower.contains("youtu.be") {
            return "YouTube"
        } else if urlLower.contains("vimeo.com") {
            return "Vimeo"
        } else if urlLower.contains("loom.com") {
            return "Loom"
        } else if urlLower.contains("twitter.com") || urlLower.contains("x.com") {
            return "X"
        } else if urlLower.contains("linkedin.com") {
            return "LinkedIn"
        } else if urlLower.contains("medium.com") {
            return "Medium"
        } else if urlLower.contains("substack.com") {
            return "Substack"
        }
        return nil
    }

    /// Detect content type from URL and metadata
    static func detectContentType(from url: String, mimeType: String? = nil) -> ResearchContentType {
        let urlLower = url.lowercased()

        // Check mime type first
        if let mime = mimeType?.lowercased() {
            if mime.contains("video") { return .video }
            if mime.contains("pdf") { return .pdf }
        }

        // Check URL patterns
        if urlLower.contains("youtube.com") || urlLower.contains("youtu.be") ||
           urlLower.contains("vimeo.com") || urlLower.contains("loom.com") {
            return .video
        }

        if urlLower.hasSuffix(".pdf") {
            return .pdf
        }

        if urlLower.contains("twitter.com") || urlLower.contains("x.com") ||
           urlLower.contains("linkedin.com/posts") {
            return .social
        }

        if urlLower.contains("medium.com") || urlLower.contains("substack.com") ||
           urlLower.contains("/blog/") || urlLower.contains("/article/") {
            return .article
        }

        return .generic
    }
}

// MARK: - Text Highlight

/// A highlighted range within transcript text, linked to an annotation
struct TextHighlight: Identifiable, Codable, Equatable {
    let id: UUID
    let annotationID: UUID
    let startCharIndex: Int
    let endCharIndex: Int
    let annotationType: AnnotationType
    /// The original highlighted text for stale-detection after transcript re-processing
    let highlightedText: String

    init(
        id: UUID = UUID(),
        annotationID: UUID,
        startCharIndex: Int,
        endCharIndex: Int,
        annotationType: AnnotationType,
        highlightedText: String
    ) {
        self.id = id
        self.annotationID = annotationID
        self.startCharIndex = startCharIndex
        self.endCharIndex = endCharIndex
        self.annotationType = annotationType
        self.highlightedText = highlightedText
    }

    /// Check if this highlight is still valid against the current section text
    func isValid(in sectionText: String) -> Bool {
        let nsString = sectionText as NSString
        let range = NSRange(location: startCharIndex, length: endCharIndex - startCharIndex)
        guard range.location + range.length <= nsString.length else { return false }
        return nsString.substring(with: range) == highlightedText
    }
}

// MARK: - Transcript Section

/// A section of transcript with timestamp and associated annotations
struct TranscriptSection: Identifiable, Codable, Equatable {
    let id: UUID
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
    let speakerName: String?
    var annotations: [ResearchAnnotation]
    var highlights: [TextHighlight]

    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String,
        speakerName: String? = nil,
        annotations: [ResearchAnnotation] = [],
        highlights: [TextHighlight] = []
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.speakerName = speakerName
        self.annotations = annotations
        self.highlights = highlights
    }

    /// Formatted start time string
    var startTimeString: String {
        formatTimestamp(startTime)
    }

    /// Formatted end time string
    var endTimeString: String {
        formatTimestamp(endTime)
    }

    private func formatTimestamp(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Research Annotation

/// An annotation attached to a specific point in research content
struct ResearchAnnotation: Identifiable, Codable, Equatable {
    let id: UUID
    let type: AnnotationType
    var content: String
    let timestamp: TimeInterval
    let createdAt: Date
    var updatedAt: Date
    var linkedAtomUUIDs: [String]
    /// Custom offset from default position (nil = auto-positioned in column)
    var customOffset: CGPoint?
    /// The transcript text that was highlighted to create this annotation (if any)
    var highlightedText: String?
    /// The section this annotation's highlight belongs to
    var sectionID: UUID?

    init(
        id: UUID = UUID(),
        type: AnnotationType,
        content: String,
        timestamp: TimeInterval,
        linkedAtomUUIDs: [String] = [],
        customOffset: CGPoint? = nil,
        highlightedText: String? = nil,
        sectionID: UUID? = nil
    ) {
        self.id = id
        self.type = type
        self.content = content
        self.timestamp = timestamp
        self.createdAt = Date()
        self.updatedAt = Date()
        self.linkedAtomUUIDs = linkedAtomUUIDs
        self.customOffset = customOffset
        self.highlightedText = highlightedText
        self.sectionID = sectionID
    }

    /// Formatted timestamp string
    var timestampString: String {
        let minutes = Int(timestamp) / 60
        let seconds = Int(timestamp) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Whether this annotation has been dragged from its default position
    var hasCustomPosition: Bool {
        guard let offset = customOffset else { return false }
        return abs(offset.x) > 5 || abs(offset.y) > 5
    }
}

// MARK: - Annotation Type

/// Types of annotations that can be attached to research content
enum AnnotationType: String, Codable, CaseIterable {
    case note       // General notes
    case question   // Questions raised
    case insight    // Key insights extracted

    var icon: String {
        switch self {
        case .note: return "note.text"
        case .question: return "questionmark.circle.fill"
        case .insight: return "lightbulb.fill"
        }
    }

    var label: String {
        switch self {
        case .note: return "Note"
        case .question: return "Question"
        case .insight: return "Insight"
        }
    }

    var color: Color {
        switch self {
        case .note: return Color(hex: "#22C55E")      // Green
        case .question: return Color(hex: "#F59E0B") // Orange/Amber
        case .insight: return Color(hex: "#8B5CF6")  // Purple
        }
    }

    /// NSColor equivalent for use with NSAttributedString
    var nsColor: NSColor {
        switch self {
        case .note: return NSColor(red: 0.133, green: 0.773, blue: 0.369, alpha: 1.0)
        case .question: return NSColor(red: 0.961, green: 0.620, blue: 0.043, alpha: 1.0)
        case .insight: return NSColor(red: 0.545, green: 0.361, blue: 0.965, alpha: 1.0)
        }
    }

    /// Whether annotations branch left or right in the transcript spine
    var branchDirection: BranchDirection {
        switch self {
        case .note: return .right
        case .question: return .left
        case .insight: return .right
        }
    }
}

/// Direction for annotation branches
enum BranchDirection {
    case left
    case right
}

// MARK: - Timeline Marker

/// A marker on the video timeline representing an annotation
struct TimelineMarker: Identifiable {
    let id: UUID
    let timestamp: TimeInterval
    let type: AnnotationType
    let annotationID: UUID

    /// Position as percentage of total duration (0.0 - 1.0)
    func position(totalDuration: TimeInterval) -> CGFloat {
        guard totalDuration > 0 else { return 0 }
        return CGFloat(timestamp / totalDuration)
    }
}

// MARK: - Research Agent Result

/// Result from a Research Agent (Perplexity) query
struct ResearchAgentResult: Identifiable, Codable, Equatable {
    let id: UUID
    let query: String
    let summary: String
    let citations: [Citation]
    let relatedQuestions: [String]
    let createdAt: Date
    var status: ResearchAgentStatus

    struct Citation: Codable, Equatable {
        let title: String
        let url: String
        let snippet: String?
    }

    init(
        id: UUID = UUID(),
        query: String,
        summary: String,
        citations: [Citation] = [],
        relatedQuestions: [String] = [],
        status: ResearchAgentStatus = .complete
    ) {
        self.id = id
        self.query = query
        self.summary = summary
        self.citations = citations
        self.relatedQuestions = relatedQuestions
        self.createdAt = Date()
        self.status = status
    }
}

/// Status of a Research Agent query
enum ResearchAgentStatus: String, Codable {
    case pending    // Queued for execution
    case running    // Currently searching
    case complete   // Finished successfully
    case failed     // Failed with error
}

// MARK: - Research Focus Mode State

/// Complete state for a Research Focus Mode session
struct ResearchFocusModeState: Codable {
    let atomUUID: String
    var contentType: ResearchContentType
    var source: ResearchSource?
    var transcriptSections: [TranscriptSection]
    var annotations: [ResearchAnnotation]
    var agentResults: [ResearchAgentResult]
    var viewportState: CanvasViewportState
    var floatingPanelIDs: [UUID]
    var currentTimestamp: TimeInterval
    var lastModified: Date

    init(atomUUID: String) {
        self.atomUUID = atomUUID
        self.contentType = .generic
        self.source = nil
        self.transcriptSections = []
        self.annotations = []
        self.agentResults = []
        self.viewportState = CanvasViewportState()
        self.floatingPanelIDs = []
        self.currentTimestamp = 0
        self.lastModified = Date()
    }

    /// All annotations across all transcript sections
    var allAnnotations: [ResearchAnnotation] {
        transcriptSections.flatMap { $0.annotations } + annotations
    }

    /// Generate timeline markers from annotations
    var timelineMarkers: [TimelineMarker] {
        allAnnotations.map { annotation in
            TimelineMarker(
                id: UUID(),
                timestamp: annotation.timestamp,
                type: annotation.type,
                annotationID: annotation.id
            )
        }
    }

    /// Get annotations for a specific transcript section
    func annotations(for sectionID: UUID) -> [ResearchAnnotation] {
        transcriptSections.first { $0.id == sectionID }?.annotations ?? []
    }

    // MARK: - Annotation Mutations

    mutating func addAnnotation(_ annotation: ResearchAnnotation, toSection sectionID: UUID) {
        if let index = transcriptSections.firstIndex(where: { $0.id == sectionID }) {
            transcriptSections[index].annotations.append(annotation)
            lastModified = Date()
        }
    }

    mutating func addStandaloneAnnotation(_ annotation: ResearchAnnotation) {
        annotations.append(annotation)
        lastModified = Date()
    }

    mutating func updateAnnotationContent(id: UUID, content: String) {
        for i in transcriptSections.indices {
            if let j = transcriptSections[i].annotations.firstIndex(where: { $0.id == id }) {
                transcriptSections[i].annotations[j].content = content
                transcriptSections[i].annotations[j].updatedAt = Date()
                lastModified = Date()
                return
            }
        }
        if let idx = annotations.firstIndex(where: { $0.id == id }) {
            annotations[idx].content = content
            annotations[idx].updatedAt = Date()
            lastModified = Date()
        }
    }

    mutating func updateAnnotationPosition(id: UUID, offset: CGPoint) {
        for i in transcriptSections.indices {
            if let j = transcriptSections[i].annotations.firstIndex(where: { $0.id == id }) {
                transcriptSections[i].annotations[j].customOffset = offset
                transcriptSections[i].annotations[j].updatedAt = Date()
                lastModified = Date()
                return
            }
        }
        if let idx = annotations.firstIndex(where: { $0.id == id }) {
            annotations[idx].customOffset = offset
            annotations[idx].updatedAt = Date()
            lastModified = Date()
        }
    }

    mutating func removeAnnotation(id: UUID) {
        // Remove highlights linked to this annotation
        removeHighlightsForAnnotation(annotationID: id)
        // Remove from transcript sections
        for i in transcriptSections.indices {
            transcriptSections[i].annotations.removeAll { $0.id == id }
        }
        // Remove from standalone annotations
        annotations.removeAll { $0.id == id }
        lastModified = Date()
    }

    // MARK: - Highlight Mutations

    mutating func addHighlight(_ highlight: TextHighlight, toSection sectionID: UUID) {
        if let index = transcriptSections.firstIndex(where: { $0.id == sectionID }) {
            transcriptSections[index].highlights.append(highlight)
            lastModified = Date()
        }
    }

    mutating func removeHighlightsForAnnotation(annotationID: UUID) {
        for i in transcriptSections.indices {
            transcriptSections[i].highlights.removeAll { $0.annotationID == annotationID }
        }
    }
}

// MARK: - Persistence

extension ResearchFocusModeState {
    /// Generate persistence key for this state
    static func persistenceKey(atomUUID: String) -> String {
        "researchFocusMode_\(atomUUID)"
    }

    /// Save state to UserDefaults
    func save() {
        let key = Self.persistenceKey(atomUUID: atomUUID)
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }

    /// Load state from UserDefaults
    static func load(atomUUID: String) -> ResearchFocusModeState? {
        let key = persistenceKey(atomUUID: atomUUID)
        guard let data = UserDefaults.standard.data(forKey: key),
              let state = try? JSONDecoder().decode(ResearchFocusModeState.self, from: data) else {
            return nil
        }
        return state
    }
}
