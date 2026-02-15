// CosmoOS/SwipeFile/SwipeAnalysis.swift
// Data models for SwipeOS analysis system
// Stores hook analysis, emotional arcs, persuasion techniques, and structure maps

import SwiftUI
import Foundation

// MARK: - SwipeAnalysis (Primary Model)

/// Complete analysis of a swipe file, stored in Research atom's structured JSON
public struct SwipeAnalysis: Codable, Sendable, Equatable {

    // Hook Analysis
    public var hookText: String?
    public var hookType: SwipeHookType?
    public var hookScore: Double?           // 0.0-10.0
    public var hookWordCount: Int?

    // Structure Analysis
    public var frameworkType: SwipeFrameworkType?
    public var sections: [SwipeSection]?
    public var structureComplexity: Double?  // 0.0-1.0

    // Emotional Analysis
    public var dominantEmotion: SwipeEmotion?
    public var emotionalArc: [EmotionDataPoint]?
    public var sentimentScore: Double?      // -1.0 to 1.0

    // Persuasion Analysis
    public var persuasionTechniques: [PersuasionTechnique]?
    public var persuasionStack: [String: Double]?

    // Deep Analysis
    public var keyInsight: String?
    public var fingerprint: StructuralFingerprint?
    public var hookScoreReason: String?

    // Versioning
    public var analysisVersion: Int
    public var analyzedAt: String?
    public var isFullyAnalyzed: Bool

    // Taxonomy Classification
    public var primaryNarrative: NarrativeStyle?
    public var secondaryNarrative: NarrativeStyle?
    public var swipeContentFormat: ContentFormat?
    public var niche: String?
    public var creatorUUID: String?

    // Classification State
    public var classifiedAt: Date?
    public var classificationSource: ClassificationSource?
    public var classificationConfidence: Double?

    // Study State
    public var studiedAt: String?
    public var practiceAttempts: Int?
    public var userHookScore: Double?

    // Inline Transcript Data
    public var transcriptComments: [TranscriptComment]?
    public var transcriptSlides: [TranscriptSlide]?

    public init(
        hookText: String? = nil,
        hookType: SwipeHookType? = nil,
        hookScore: Double? = nil,
        hookWordCount: Int? = nil,
        frameworkType: SwipeFrameworkType? = nil,
        sections: [SwipeSection]? = nil,
        structureComplexity: Double? = nil,
        dominantEmotion: SwipeEmotion? = nil,
        emotionalArc: [EmotionDataPoint]? = nil,
        sentimentScore: Double? = nil,
        persuasionTechniques: [PersuasionTechnique]? = nil,
        persuasionStack: [String: Double]? = nil,
        keyInsight: String? = nil,
        fingerprint: StructuralFingerprint? = nil,
        hookScoreReason: String? = nil,
        analysisVersion: Int = 1,
        analyzedAt: String? = nil,
        isFullyAnalyzed: Bool = false,
        primaryNarrative: NarrativeStyle? = nil,
        secondaryNarrative: NarrativeStyle? = nil,
        swipeContentFormat: ContentFormat? = nil,
        niche: String? = nil,
        creatorUUID: String? = nil,
        classifiedAt: Date? = nil,
        classificationSource: ClassificationSource? = nil,
        classificationConfidence: Double? = nil,
        studiedAt: String? = nil,
        practiceAttempts: Int? = nil,
        userHookScore: Double? = nil,
        transcriptComments: [TranscriptComment]? = nil,
        transcriptSlides: [TranscriptSlide]? = nil
    ) {
        self.hookText = hookText
        self.hookType = hookType
        self.hookScore = hookScore
        self.hookWordCount = hookWordCount
        self.frameworkType = frameworkType
        self.sections = sections
        self.structureComplexity = structureComplexity
        self.dominantEmotion = dominantEmotion
        self.emotionalArc = emotionalArc
        self.sentimentScore = sentimentScore
        self.persuasionTechniques = persuasionTechniques
        self.persuasionStack = persuasionStack
        self.keyInsight = keyInsight
        self.fingerprint = fingerprint
        self.hookScoreReason = hookScoreReason
        self.analysisVersion = analysisVersion
        self.analyzedAt = analyzedAt
        self.isFullyAnalyzed = isFullyAnalyzed
        self.primaryNarrative = primaryNarrative
        self.secondaryNarrative = secondaryNarrative
        self.swipeContentFormat = swipeContentFormat
        self.niche = niche
        self.creatorUUID = creatorUUID
        self.classifiedAt = classifiedAt
        self.classificationSource = classificationSource
        self.classificationConfidence = classificationConfidence
        self.studiedAt = studiedAt
        self.practiceAttempts = practiceAttempts
        self.userHookScore = userHookScore
        self.transcriptComments = transcriptComments
        self.transcriptSlides = transcriptSlides
    }

    /// Mark as studied now
    public func markingStudied() -> SwipeAnalysis {
        var copy = self
        copy.studiedAt = ISO8601DateFormatter().string(from: Date())
        return copy
    }

    /// Increment practice attempts
    public func incrementingPractice() -> SwipeAnalysis {
        var copy = self
        copy.practiceAttempts = (copy.practiceAttempts ?? 0) + 1
        return copy
    }

    /// Update user's manual hook score
    public func withUserScore(_ score: Double) -> SwipeAnalysis {
        var copy = self
        copy.userHookScore = score
        return copy
    }

    /// Check if analysis is stale (older version)
    public var isStale: Bool {
        analysisVersion < 1
    }

    /// Effective hook score (user override or AI-generated)
    public var effectiveHookScore: Double {
        userHookScore ?? hookScore ?? 0
    }
}

// MARK: - SwipeHookType

/// Classification of hook/opening line technique
public enum SwipeHookType: String, Codable, Sendable, CaseIterable {
    case curiosityGap
    case boldClaim
    case question
    case story
    case statistic
    case controversy
    case contrast
    case howTo
    case list
    case challenge
    case hiddenGem
    case contrarian
    case personal
    case transformation

    public var displayName: String {
        switch self {
        case .curiosityGap: return "Curiosity Gap"
        case .boldClaim: return "Bold Claim"
        case .question: return "Question"
        case .story: return "Story"
        case .statistic: return "Statistic"
        case .controversy: return "Controversy"
        case .contrast: return "Contrast"
        case .howTo: return "How-To"
        case .list: return "List"
        case .challenge: return "Challenge"
        case .hiddenGem: return "Hidden Gem"
        case .contrarian: return "Contrarian"
        case .personal: return "Personal"
        case .transformation: return "Transformation"
        }
    }

    public var color: Color {
        switch self {
        case .curiosityGap:    return Color(hex: "#818CF8") // Soft indigo
        case .boldClaim:       return Color(hex: "#F97316") // Orange
        case .question:        return Color(hex: "#38BDF8") // Sky blue
        case .story:           return Color(hex: "#A78BFA") // Violet
        case .statistic:       return Color(hex: "#34D399") // Emerald
        case .controversy:     return Color(hex: "#FB7185") // Rose
        case .contrast:        return Color(hex: "#FBBF24") // Amber
        case .howTo:           return Color(hex: "#2DD4BF") // Teal
        case .list:            return Color(hex: "#60A5FA") // Blue
        case .challenge:       return Color(hex: "#F472B6") // Pink
        case .hiddenGem:       return Color(hex: "#FFD700") // Gold
        case .contrarian:      return Color(hex: "#E879F9") // Fuchsia
        case .personal:        return Color(hex: "#FB923C") // Soft orange
        case .transformation:  return Color(hex: "#4ADE80") // Green
        }
    }

    public var iconName: String {
        switch self {
        case .curiosityGap:    return "eye.fill"
        case .boldClaim:       return "exclamationmark.triangle.fill"
        case .question:        return "questionmark.circle.fill"
        case .story:           return "book.fill"
        case .statistic:       return "chart.bar.fill"
        case .controversy:     return "flame.fill"
        case .contrast:        return "arrow.left.arrow.right"
        case .howTo:           return "wrench.and.screwdriver.fill"
        case .list:            return "list.number"
        case .challenge:       return "flag.fill"
        case .hiddenGem:       return "diamond.fill"
        case .contrarian:      return "arrow.uturn.backward"
        case .personal:        return "person.fill"
        case .transformation:  return "arrow.triangle.2.circlepath"
        }
    }
}

// MARK: - SwipeFrameworkType

/// Content structure/framework classification
public enum SwipeFrameworkType: String, Codable, Sendable, CaseIterable {
    case aida
    case pas
    case bab
    case escalationArc
    case storyLoop
    case listicle
    case tutorial
    case caseStudy
    case interview
    case beforeAfter
    case mythBusting
    case dayInLife

    public var displayName: String {
        switch self {
        case .aida: return "AIDA"
        case .pas: return "PAS"
        case .bab: return "Before-After-Bridge"
        case .escalationArc: return "Escalation Arc"
        case .storyLoop: return "Story Loop"
        case .listicle: return "Listicle"
        case .tutorial: return "Tutorial"
        case .caseStudy: return "Case Study"
        case .interview: return "Interview"
        case .beforeAfter: return "Before/After"
        case .mythBusting: return "Myth Busting"
        case .dayInLife: return "Day in the Life"
        }
    }

    public var abbreviation: String {
        switch self {
        case .aida: return "AIDA"
        case .pas: return "PAS"
        case .bab: return "BAB"
        case .escalationArc: return "ESC"
        case .storyLoop: return "STORY"
        case .listicle: return "LIST"
        case .tutorial: return "TUT"
        case .caseStudy: return "CASE"
        case .interview: return "INT"
        case .beforeAfter: return "B/A"
        case .mythBusting: return "MYTH"
        case .dayInLife: return "DITL"
        }
    }

    public var description: String {
        switch self {
        case .aida: return "Attention → Interest → Desire → Action"
        case .pas: return "Problem → Agitate → Solve"
        case .bab: return "Before → After → Bridge"
        case .escalationArc: return "Progressive intensity build to climax"
        case .storyLoop: return "Setup → Conflict → Resolution"
        case .listicle: return "Numbered items with a unifying theme"
        case .tutorial: return "Step-by-step instructional format"
        case .caseStudy: return "Deep dive into a specific example"
        case .interview: return "Q&A or conversational format"
        case .beforeAfter: return "Contrasting two states of transformation"
        case .mythBusting: return "Debunking common misconceptions"
        case .dayInLife: return "Following a chronological personal narrative"
        }
    }

    public var color: Color {
        switch self {
        case .aida:           return Color(hex: "#818CF8")
        case .pas:            return Color(hex: "#FB7185")
        case .bab:            return Color(hex: "#FBBF24")
        case .escalationArc:  return Color(hex: "#F97316")
        case .storyLoop:      return Color(hex: "#A78BFA")
        case .listicle:       return Color(hex: "#60A5FA")
        case .tutorial:       return Color(hex: "#2DD4BF")
        case .caseStudy:      return Color(hex: "#34D399")
        case .interview:      return Color(hex: "#38BDF8")
        case .beforeAfter:    return Color(hex: "#FBBF24")
        case .mythBusting:    return Color(hex: "#FB7185")
        case .dayInLife:      return Color(hex: "#FB923C")
        }
    }
}

// MARK: - SwipeEmotion

/// Dominant emotional trigger classification
public enum SwipeEmotion: String, Codable, Sendable, CaseIterable {
    case curiosity
    case urgency
    case aspiration
    case fear
    case desire
    case awe
    case frustration
    case relief
    case belonging
    case exclusivity

    public var displayName: String {
        switch self {
        case .curiosity:    return "Curiosity"
        case .urgency:      return "Urgency"
        case .aspiration:   return "Aspiration"
        case .fear:         return "Fear"
        case .desire:       return "Desire"
        case .awe:          return "Awe"
        case .frustration:  return "Frustration"
        case .relief:       return "Relief"
        case .belonging:    return "Belonging"
        case .exclusivity:  return "Exclusivity"
        }
    }

    public var color: Color {
        switch self {
        case .curiosity:    return Color(hex: "#818CF8") // Indigo — wonder
        case .urgency:      return Color(hex: "#EF4444") // Red — pressure
        case .aspiration:   return Color(hex: "#FBBF24") // Amber — warmth
        case .fear:         return Color(hex: "#F97316") // Orange — alert
        case .desire:       return Color(hex: "#EC4899") // Pink — want
        case .awe:          return Color(hex: "#A78BFA") // Violet — transcendence
        case .frustration:  return Color(hex: "#FB7185") // Rose — tension
        case .relief:       return Color(hex: "#34D399") // Emerald — calm
        case .belonging:    return Color(hex: "#38BDF8") // Sky — connection
        case .exclusivity:  return Color(hex: "#FFD700") // Gold — premium
        }
    }

    public var iconName: String {
        switch self {
        case .curiosity:    return "eye.fill"
        case .urgency:      return "clock.badge.exclamationmark.fill"
        case .aspiration:   return "star.fill"
        case .fear:         return "exclamationmark.shield.fill"
        case .desire:       return "heart.fill"
        case .awe:          return "sparkles"
        case .frustration:  return "bolt.fill"
        case .relief:       return "leaf.fill"
        case .belonging:    return "person.3.fill"
        case .exclusivity:  return "lock.fill"
        }
    }
}

// MARK: - SwipeSection

/// A labeled section within the content structure
public struct SwipeSection: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(label)-\(startIndex)" }
    public var label: String
    public var startIndex: Int
    public var endIndex: Int
    public var purpose: String
    public var emotion: SwipeEmotion?
    public var sizePercent: Double?

    public init(label: String, startIndex: Int = 0, endIndex: Int = 0, purpose: String, emotion: SwipeEmotion? = nil, sizePercent: Double? = nil) {
        self.label = label
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.purpose = purpose
        self.emotion = emotion
        self.sizePercent = sizePercent
    }

    /// Relative size of this section (0.0-1.0) within total content length
    public func relativeSize(totalLength: Int) -> Double {
        if let sp = sizePercent, sp > 0 { return sp }
        guard totalLength > 0 else { return 0 }
        return Double(endIndex - startIndex) / Double(totalLength)
    }
}

// MARK: - EmotionDataPoint

/// Single point on the emotional arc timeline
public struct EmotionDataPoint: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(position)-\(emotion.rawValue)" }
    public var position: Double     // 0.0-1.0 (normalized content position)
    public var intensity: Double    // 0.0-1.0
    public var emotion: SwipeEmotion

    public init(position: Double, intensity: Double, emotion: SwipeEmotion) {
        self.position = min(max(position, 0), 1)
        self.intensity = min(max(intensity, 0), 1)
        self.emotion = emotion
    }
}

// MARK: - PersuasionTechnique

/// Detected persuasion technique with intensity and text locations
public struct PersuasionTechnique: Codable, Sendable, Equatable, Identifiable {
    public var id: String { type.rawValue }
    public var type: PersuasionType
    public var intensity: Double        // 0.0-1.0
    public var textRanges: [SwipeTextRange]?
    public var example: String?

    public init(type: PersuasionType, intensity: Double, textRanges: [SwipeTextRange]? = nil, example: String? = nil) {
        self.type = type
        self.intensity = min(max(intensity, 0), 1)
        self.textRanges = textRanges
        self.example = example
    }
}

// MARK: - PersuasionType

/// Categories of persuasion techniques (Cialdini + extended)
public enum PersuasionType: String, Codable, Sendable, CaseIterable {
    case socialProof
    case curiosityGap
    case contrastEffect
    case authority
    case scarcity
    case urgency
    case reciprocity
    case storytelling
    case lossAversion
    case exclusivity
    case anchoring
    case framing

    public var displayName: String {
        switch self {
        case .socialProof:    return "Social Proof"
        case .curiosityGap:   return "Curiosity Gap"
        case .contrastEffect: return "Contrast Effect"
        case .authority:      return "Authority"
        case .scarcity:       return "Scarcity"
        case .urgency:        return "Urgency"
        case .reciprocity:    return "Reciprocity"
        case .storytelling:   return "Storytelling"
        case .lossAversion:   return "Loss Aversion"
        case .exclusivity:    return "Exclusivity"
        case .anchoring:      return "Anchoring"
        case .framing:        return "Framing"
        }
    }

    public var color: Color {
        switch self {
        case .socialProof:    return Color(hex: "#60A5FA") // Blue
        case .curiosityGap:   return Color(hex: "#818CF8") // Indigo
        case .contrastEffect: return Color(hex: "#FBBF24") // Amber
        case .authority:      return Color(hex: "#34D399") // Emerald
        case .scarcity:       return Color(hex: "#EF4444") // Red
        case .urgency:        return Color(hex: "#F97316") // Orange
        case .reciprocity:    return Color(hex: "#2DD4BF") // Teal
        case .storytelling:   return Color(hex: "#A78BFA") // Violet
        case .lossAversion:   return Color(hex: "#FB7185") // Rose
        case .exclusivity:    return Color(hex: "#FFD700") // Gold
        case .anchoring:      return Color(hex: "#38BDF8") // Sky
        case .framing:        return Color(hex: "#E879F9") // Fuchsia
        }
    }

    public var iconName: String {
        switch self {
        case .socialProof:    return "person.3.fill"
        case .curiosityGap:   return "eye.fill"
        case .contrastEffect: return "arrow.left.arrow.right"
        case .authority:      return "checkmark.seal.fill"
        case .scarcity:       return "hourglass"
        case .urgency:        return "clock.badge.exclamationmark.fill"
        case .reciprocity:    return "arrow.triangle.2.circlepath"
        case .storytelling:   return "text.book.closed.fill"
        case .lossAversion:   return "exclamationmark.triangle.fill"
        case .exclusivity:    return "lock.fill"
        case .anchoring:      return "scope"
        case .framing:        return "rectangle.3.group.fill"
        }
    }
}

// MARK: - SwipeTextRange

/// A range within the content text where a technique appears
public struct SwipeTextRange: Codable, Sendable, Equatable {
    public var start: Int
    public var end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }

    /// Length of the range
    public var length: Int { end - start }
}

// MARK: - StructuralFingerprint

/// Numeric fingerprint for cross-swipe structural comparison via cosine similarity
public struct StructuralFingerprint: Codable, Sendable, Equatable {
    /// 4 quartile sentiment averages (-1.0 to 1.0)
    public let sentimentArc: [Double]
    /// 4 quartile intensity averages (0.0 to 1.0)
    public let intensityArc: [Double]
    /// 12 values — one per PersuasionType (ordered by CaseIterable)
    public let techniqueWeights: [Double]
    public let sectionCount: Int
    public let hookType: SwipeHookType?
    public let frameworkType: SwipeFrameworkType?

    public init(
        sentimentArc: [Double],
        intensityArc: [Double],
        techniqueWeights: [Double],
        sectionCount: Int,
        hookType: SwipeHookType?,
        frameworkType: SwipeFrameworkType?
    ) {
        self.sentimentArc = sentimentArc
        self.intensityArc = intensityArc
        self.techniqueWeights = techniqueWeights
        self.sectionCount = sectionCount
        self.hookType = hookType
        self.frameworkType = frameworkType
    }

    /// Build the 20-element numeric vector for similarity comparison
    public var vector: [Double] {
        var v: [Double] = []
        // 4 sentiment quartiles
        v.append(contentsOf: sentimentArc.prefix(4))
        while v.count < 4 { v.append(0) }
        // 4 intensity quartiles
        v.append(contentsOf: intensityArc.prefix(4))
        while v.count < 8 { v.append(0) }
        // 12 technique weights
        v.append(contentsOf: techniqueWeights.prefix(12))
        while v.count < 20 { v.append(0) }
        return v
    }

    /// Cosine similarity to another fingerprint (0.0 to 1.0)
    public func similarity(to other: StructuralFingerprint) -> Double {
        let a = self.vector
        let b = other.vector
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dot = 0.0
        var magA = 0.0
        var magB = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            magA += a[i] * a[i]
            magB += b[i] * b[i]
        }

        let denom = sqrt(magA) * sqrt(magB)
        guard denom > 0 else { return 0 }
        // Clamp to [0, 1] — negative cosine similarity treated as 0
        return max(0, dot / denom)
    }

    /// Build a fingerprint from a SwipeAnalysis
    public static func from(analysis: SwipeAnalysis) -> StructuralFingerprint {
        // Sentiment quartiles from emotional arc
        let sentimentQuartiles: [Double]
        let intensityQuartiles: [Double]
        if let arc = analysis.emotionalArc, arc.count >= 4 {
            sentimentQuartiles = quartileAverages(arc.map { point in
                switch point.emotion {
                case .aspiration, .desire, .awe, .relief: return point.intensity
                case .fear, .frustration, .urgency: return -point.intensity
                default: return 0
                }
            })
            intensityQuartiles = quartileAverages(arc.map(\.intensity))
        } else {
            sentimentQuartiles = [0, 0, 0, 0]
            intensityQuartiles = [0, 0, 0, 0]
        }

        // Technique weights — ordered by PersuasionType.allCases
        let techniqueMap = Dictionary(
            uniqueKeysWithValues: (analysis.persuasionTechniques ?? []).map { ($0.type, $0.intensity) }
        )
        let techniqueWeights = PersuasionType.allCases.map { techniqueMap[$0] ?? 0 }

        return StructuralFingerprint(
            sentimentArc: sentimentQuartiles,
            intensityArc: intensityQuartiles,
            techniqueWeights: techniqueWeights,
            sectionCount: analysis.sections?.count ?? 0,
            hookType: analysis.hookType,
            frameworkType: analysis.frameworkType
        )
    }

    /// Divide an array into 4 quartiles and average each
    private static func quartileAverages(_ values: [Double]) -> [Double] {
        guard !values.isEmpty else { return [0, 0, 0, 0] }
        let n = values.count
        let q = max(n / 4, 1)
        var result: [Double] = []
        for i in 0..<4 {
            let start = i * q
            let end = (i == 3) ? n : min((i + 1) * q, n)
            guard start < end else { result.append(0); continue }
            let slice = values[start..<end]
            result.append(slice.reduce(0, +) / Double(slice.count))
        }
        return result
    }
}

// MARK: - SwipeGalleryItem

/// Lightweight model for displaying swipes in the Command-K gallery
public struct SwipeGalleryItem: Identifiable, Sendable {
    public let id: String
    public let atomUUID: String
    public let title: String
    public let hookText: String?
    public let hookScore: Double?
    public let hookType: SwipeHookType?
    public let dominantEmotion: SwipeEmotion?
    public let frameworkType: SwipeFrameworkType?
    public let platform: String?
    public let thumbnailUrl: String?
    public let author: String?
    public let duration: Int?
    public let createdAt: String
    public let isStudied: Bool
    public let entityId: Int64
    // Taxonomy fields
    public let primaryNarrative: NarrativeStyle?
    public let swipeContentFormat: ContentFormat?
    public let niche: String?
    public let creatorName: String?

    public init(
        atomUUID: String,
        title: String,
        hookText: String? = nil,
        hookScore: Double? = nil,
        hookType: SwipeHookType? = nil,
        dominantEmotion: SwipeEmotion? = nil,
        frameworkType: SwipeFrameworkType? = nil,
        platform: String? = nil,
        thumbnailUrl: String? = nil,
        author: String? = nil,
        duration: Int? = nil,
        createdAt: String = "",
        isStudied: Bool = false,
        entityId: Int64 = -1,
        primaryNarrative: NarrativeStyle? = nil,
        swipeContentFormat: ContentFormat? = nil,
        niche: String? = nil,
        creatorName: String? = nil
    ) {
        self.id = atomUUID
        self.atomUUID = atomUUID
        self.title = title
        self.hookText = hookText
        self.hookScore = hookScore
        self.hookType = hookType
        self.dominantEmotion = dominantEmotion
        self.frameworkType = frameworkType
        self.platform = platform
        self.thumbnailUrl = thumbnailUrl
        self.author = author
        self.duration = duration
        self.createdAt = createdAt
        self.isStudied = isStudied
        self.entityId = entityId
        self.primaryNarrative = primaryNarrative
        self.swipeContentFormat = swipeContentFormat
        self.niche = niche
        self.creatorName = creatorName
    }

    /// Platform display icon
    public var platformIcon: String {
        switch platform {
        case "youtube", "youtubeShort": return "play.rectangle.fill"
        case "instagram", "instagramReel", "instagramPost", "instagramCarousel": return "camera.fill"
        case "xPost", "twitter": return "at"
        case "threads": return "at.badge.plus"
        case "website": return "globe"
        case "rawNote", "clipboard": return "doc.on.clipboard"
        default: return "doc.fill"
        }
    }

    /// Platform display name
    public var platformName: String {
        switch platform {
        case "youtube": return "YouTube"
        case "youtubeShort": return "YT Short"
        case "instagram", "instagramReel", "instagramPost", "instagramCarousel": return "Instagram"
        case "xPost", "twitter": return "X"
        case "threads": return "Threads"
        case "website": return "Website"
        case "rawNote", "clipboard": return "Clipboard"
        default: return "Unknown"
        }
    }

    /// Hook score color
    public var scoreColor: Color {
        guard let score = hookScore else { return Color(hex: "#64748B") }
        if score >= 8.0 { return Color(hex: "#10B981") }  // Emerald
        if score >= 5.0 { return Color(hex: "#3B82F6") }  // Blue
        return Color(hex: "#64748B")                        // Slate
    }
}

// MARK: - Atom SwipeAnalysis Extension

extension Atom {

    /// Decode SwipeAnalysis from this atom's structured JSON
    public var swipeAnalysis: SwipeAnalysis? {
        guard type == .research else { return nil }
        guard let structuredStr = structured,
              let data = structuredStr.data(using: .utf8) else { return nil }

        // Try to decode a wrapper that contains swipeAnalysis
        if let wrapper = try? JSONDecoder().decode(SwipeAnalysisWrapper.self, from: data) {
            return wrapper.swipeAnalysis
        }
        return nil
    }

    /// Return a new atom with the SwipeAnalysis merged into structured JSON
    public func withSwipeAnalysis(_ analysis: SwipeAnalysis) -> Atom {
        var copy = self

        // Parse existing structured data or create new
        var wrapper: SwipeAnalysisWrapper
        if let structuredStr = structured,
           let data = structuredStr.data(using: .utf8),
           let existing = try? JSONDecoder().decode(SwipeAnalysisWrapper.self, from: data) {
            wrapper = existing
        } else {
            wrapper = SwipeAnalysisWrapper(existingStructured: structured)
        }

        wrapper.swipeAnalysis = analysis

        if let encoded = try? JSONEncoder().encode(wrapper),
           let jsonStr = String(data: encoded, encoding: .utf8) {
            copy.structured = jsonStr
        }

        return copy
    }

    /// Check if this research atom is a swipe file
    public var isSwipeFileAtom: Bool {
        guard type == .research else { return false }
        return researchMetadata?.isSwipeFile ?? false
    }

    /// Build a SwipeGalleryItem from this atom
    public func toSwipeGalleryItem() -> SwipeGalleryItem? {
        guard type == .research, isSwipeFileAtom else { return nil }

        let analysis = swipeAnalysis
        let meta = researchMetadata

        // Extract platform from structured rich content
        var platform: String?
        var thumbnailUrl: String?
        var author: String?
        var duration: Int?

        if let structuredStr = structured,
           let data = structuredStr.data(using: .utf8) {
            if let richContent = try? JSONDecoder().decode(ResearchRichContentMinimal.self, from: data) {
                platform = richContent.autoMetadata?.sourceType ?? meta?.contentSource
                thumbnailUrl = meta?.thumbnailUrl
                author = richContent.autoMetadata?.author
                duration = richContent.autoMetadata?.duration
            }
        }

        if platform == nil {
            platform = meta?.contentSource
        }

        return SwipeGalleryItem(
            atomUUID: uuid,
            title: title ?? meta?.hook ?? "Untitled Swipe",
            hookText: meta?.hook ?? analysis?.hookText,
            hookScore: analysis?.hookScore,
            hookType: analysis?.hookType,
            dominantEmotion: analysis?.dominantEmotion,
            frameworkType: analysis?.frameworkType,
            platform: platform,
            thumbnailUrl: thumbnailUrl ?? meta?.thumbnailUrl,
            author: author,
            duration: duration,
            createdAt: createdAt,
            isStudied: analysis?.studiedAt != nil,
            entityId: id ?? -1,
            primaryNarrative: analysis?.primaryNarrative,
            swipeContentFormat: analysis?.swipeContentFormat,
            niche: analysis?.niche,
            creatorName: author
        )
    }

}

// MARK: - Transcript Slide Source

/// Provenance tracking for auto-transcribed slides
public enum TranscriptSlideSource: String, Codable, Sendable, Equatable {
    case manual         // User typed it
    case visionOCR      // Vision framework text recognition
    case speechAudio    // SFSpeechRecognizer transcription
    case merged         // Combined OCR + speech
    case aiCleaned      // Post-processed by Claude
}

// MARK: - Transcription Content Type

/// What kind of content was detected in the video
public enum TranscriptionContentType: String, Codable, Sendable, Equatable {
    case textOnly           // On-screen text only (no voiceover)
    case voiceoverOnly      // Speech only (no on-screen text)
    case voiceoverPlusText  // Both speech and on-screen text
    case empty              // Nothing detected
}

// MARK: - TranscriptSlide

/// A single slide in a slide-based transcript (Instagram carousel/reel visual cuts)
public struct TranscriptSlide: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var text: String
    public var slideNumber: Int
    public var timestamp: TimeInterval?
    public var endTimestamp: TimeInterval?
    public var source: TranscriptSlideSource?

    public init(id: UUID = UUID(), text: String = "", slideNumber: Int = 1,
                timestamp: TimeInterval? = nil, endTimestamp: TimeInterval? = nil,
                source: TranscriptSlideSource? = nil) {
        self.id = id
        self.text = text
        self.slideNumber = slideNumber
        self.timestamp = timestamp
        self.endTimestamp = endTimestamp
        self.source = source
    }

    /// Maximum character limit per slide
    public static let characterLimit = 450
}

// MARK: - TranscriptComment

/// An inline comment attached to a text range in a transcript
public struct TranscriptComment: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var startIndex: Int    // Character offset in transcript
    public var endIndex: Int      // Character offset end
    public var text: String       // Comment text
    public var createdAt: String  // ISO8601

    public init(id: UUID = UUID(), startIndex: Int, endIndex: Int, text: String, createdAt: String? = nil) {
        self.id = id
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.text = text
        self.createdAt = createdAt ?? ISO8601DateFormatter().string(from: Date())
    }
}

// MARK: - Private Helpers

/// Wrapper to embed SwipeAnalysis alongside existing structured data
private struct SwipeAnalysisWrapper: Codable {
    var swipeAnalysis: SwipeAnalysis?
    var existingRaw: String?

    init(existingStructured: String? = nil) {
        self.existingRaw = existingStructured
    }

    enum CodingKeys: String, CodingKey {
        case swipeAnalysis
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        swipeAnalysis = try container.decodeIfPresent(SwipeAnalysis.self, forKey: .swipeAnalysis)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(swipeAnalysis, forKey: .swipeAnalysis)
    }
}

/// Minimal decoder for extracting source type from ResearchRichContent
private struct ResearchRichContentMinimal: Codable {
    var autoMetadata: AutoMetadataMinimal?

    struct AutoMetadataMinimal: Codable {
        var sourceType: String?
        var author: String?
        var duration: Int?
    }
}
