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
    public var clientUUID: String?

    // Classification State
    public var classifiedAt: Date?
    public var classificationSource: ClassificationSource?
    public var classificationConfidence: Double?

    // Study State
    public var studiedAt: String?
    public var practiceAttempts: Int?
    public var userHookScore: Double?

    // Deep Classification Intelligence
    public var hookMechanism: String?
    public var structuralRecipe: String?
    public var voiceMarkers: [String]?

    // Beat Pattern Intelligence
    public var normalizedBeats: [String]?
    public var beatFingerprint: String?

    // Inline Transcript Data
    public var transcriptComments: [TranscriptComment]?
    public var transcriptSlides: [TranscriptSlide]?
    public var rawTranscriptSlides: [TranscriptSlide]?
    public var transcriptSpeechSegments: [TranscriptSegment]?
    public var transcriptionQuality: TranscriptionQuality?
    public var transcriptionWarnings: [String]?

    /// Set when the user manually edits slides in Swipe Study. Terminal:
    /// auto-transcription must never re-run for a swipe with this flag —
    /// it would overwrite deliberate edits (e.g. user-pruned carousels).
    public var transcriptEditedByUser: Bool?

    // Extraction retry tracking (auto-retry on app launch, capped at 3)
    public var extractionRetryCount: Int?

    // Engagement Metrics (from platform APIs or manual entry)
    public var likesCount: Int?
    public var viewsCount: Int?
    public var commentsCount: Int?
    public var sharesCount: Int?
    public var engagementRate: Double?        // (likes + comments) / views * 100
    public var publishedAt: Date?             // Original post publish date
    public var postShortcode: String?         // Instagram shortcode for dedup

    // Per-client hook adaptations (auto-generated on swipe capture)
    public var clientAdaptations: [SwipeClientAdaptation]?

    private enum CodingKeys: String, CodingKey {
        case hookText
        case hookType
        case hookScore
        case hookWordCount
        case frameworkType
        case sections
        case structureComplexity
        case dominantEmotion
        case emotionalArc
        case sentimentScore
        case persuasionTechniques
        case persuasionStack
        case keyInsight
        case fingerprint
        case hookScoreReason
        case analysisVersion
        case analyzedAt
        case isFullyAnalyzed
        case primaryNarrative
        case secondaryNarrative
        case swipeContentFormat
        case niche
        case creatorUUID
        case clientUUID
        case classifiedAt
        case classificationSource
        case classificationConfidence
        case studiedAt
        case practiceAttempts
        case userHookScore
        case hookMechanism
        case structuralRecipe
        case voiceMarkers
        case normalizedBeats
        case beatFingerprint
        case transcriptComments
        case transcriptSlides
        case rawTranscriptSlides
        case transcriptSpeechSegments
        case transcriptionQuality
        case transcriptionWarnings
        case transcriptEditedByUser
        case extractionRetryCount
        case likesCount
        case viewsCount
        case commentsCount
        case sharesCount
        case engagementRate
        case publishedAt
        case postShortcode
        case clientAdaptations
    }

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
        clientUUID: String? = nil,
        classifiedAt: Date? = nil,
        classificationSource: ClassificationSource? = nil,
        classificationConfidence: Double? = nil,
        studiedAt: String? = nil,
        practiceAttempts: Int? = nil,
        userHookScore: Double? = nil,
        hookMechanism: String? = nil,
        structuralRecipe: String? = nil,
        voiceMarkers: [String]? = nil,
        normalizedBeats: [String]? = nil,
        beatFingerprint: String? = nil,
        transcriptComments: [TranscriptComment]? = nil,
        transcriptSlides: [TranscriptSlide]? = nil,
        rawTranscriptSlides: [TranscriptSlide]? = nil,
        transcriptSpeechSegments: [TranscriptSegment]? = nil,
        transcriptionQuality: TranscriptionQuality? = nil,
        transcriptionWarnings: [String]? = nil,
        likesCount: Int? = nil,
        viewsCount: Int? = nil,
        commentsCount: Int? = nil,
        sharesCount: Int? = nil,
        engagementRate: Double? = nil,
        publishedAt: Date? = nil,
        postShortcode: String? = nil
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
        self.clientUUID = clientUUID
        self.classifiedAt = classifiedAt
        self.classificationSource = classificationSource
        self.classificationConfidence = classificationConfidence
        self.studiedAt = studiedAt
        self.practiceAttempts = practiceAttempts
        self.userHookScore = userHookScore
        self.hookMechanism = hookMechanism
        self.structuralRecipe = structuralRecipe
        self.voiceMarkers = voiceMarkers
        self.normalizedBeats = normalizedBeats
        self.beatFingerprint = beatFingerprint
        self.transcriptComments = transcriptComments
        self.transcriptSlides = transcriptSlides
        self.rawTranscriptSlides = rawTranscriptSlides
        self.transcriptSpeechSegments = transcriptSpeechSegments
        self.transcriptionQuality = transcriptionQuality
        self.transcriptionWarnings = transcriptionWarnings
        self.likesCount = likesCount
        self.viewsCount = viewsCount
        self.commentsCount = commentsCount
        self.sharesCount = sharesCount
        self.engagementRate = engagementRate
        self.publishedAt = publishedAt
        self.postShortcode = postShortcode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        hookText = try container.decodeIfPresent(String.self, forKey: .hookText)
        hookType = try container.decodeIfPresent(SwipeHookType.self, forKey: .hookType)
        hookScore = try container.decodeIfPresent(Double.self, forKey: .hookScore)
        hookWordCount = try container.decodeIfPresent(Int.self, forKey: .hookWordCount)
        frameworkType = try container.decodeIfPresent(SwipeFrameworkType.self, forKey: .frameworkType)
        sections = try container.decodeIfPresent([SwipeSection].self, forKey: .sections)
        structureComplexity = try container.decodeIfPresent(Double.self, forKey: .structureComplexity)
        dominantEmotion = try container.decodeIfPresent(SwipeEmotion.self, forKey: .dominantEmotion)
        emotionalArc = try container.decodeIfPresent([EmotionDataPoint].self, forKey: .emotionalArc)
        sentimentScore = try container.decodeIfPresent(Double.self, forKey: .sentimentScore)
        persuasionTechniques = try container.decodeIfPresent([PersuasionTechnique].self, forKey: .persuasionTechniques)
        persuasionStack = try container.decodeIfPresent([String: Double].self, forKey: .persuasionStack)
        keyInsight = try container.decodeIfPresent(String.self, forKey: .keyInsight)
        fingerprint = try container.decodeIfPresent(StructuralFingerprint.self, forKey: .fingerprint)
        hookScoreReason = try container.decodeIfPresent(String.self, forKey: .hookScoreReason)
        analysisVersion = try container.decodeIfPresent(Int.self, forKey: .analysisVersion) ?? 1
        analyzedAt = try container.decodeIfPresent(String.self, forKey: .analyzedAt)
        isFullyAnalyzed = try container.decodeIfPresent(Bool.self, forKey: .isFullyAnalyzed) ?? false
        primaryNarrative = try container.decodeIfPresent(NarrativeStyle.self, forKey: .primaryNarrative)
        secondaryNarrative = try container.decodeIfPresent(NarrativeStyle.self, forKey: .secondaryNarrative)
        swipeContentFormat = try container.decodeIfPresent(ContentFormat.self, forKey: .swipeContentFormat)
        niche = try container.decodeIfPresent(String.self, forKey: .niche)
        creatorUUID = try container.decodeIfPresent(String.self, forKey: .creatorUUID)
        clientUUID = try container.decodeIfPresent(String.self, forKey: .clientUUID)
        classifiedAt = try container.decodeIfPresent(Date.self, forKey: .classifiedAt)
        classificationSource = try container.decodeIfPresent(ClassificationSource.self, forKey: .classificationSource)
        classificationConfidence = try container.decodeIfPresent(Double.self, forKey: .classificationConfidence)
        studiedAt = try container.decodeIfPresent(String.self, forKey: .studiedAt)
        practiceAttempts = try container.decodeIfPresent(Int.self, forKey: .practiceAttempts)
        userHookScore = try container.decodeIfPresent(Double.self, forKey: .userHookScore)
        hookMechanism = try container.decodeIfPresent(String.self, forKey: .hookMechanism)
        structuralRecipe = try container.decodeIfPresent(String.self, forKey: .structuralRecipe)
        voiceMarkers = try container.decodeIfPresent([String].self, forKey: .voiceMarkers)
        normalizedBeats = try container.decodeIfPresent([String].self, forKey: .normalizedBeats)
        beatFingerprint = try container.decodeIfPresent(String.self, forKey: .beatFingerprint)
        transcriptComments = try container.decodeIfPresent([TranscriptComment].self, forKey: .transcriptComments)
        transcriptSlides = try container.decodeIfPresent([TranscriptSlide].self, forKey: .transcriptSlides)
        rawTranscriptSlides = try container.decodeIfPresent([TranscriptSlide].self, forKey: .rawTranscriptSlides)
        transcriptSpeechSegments = try container.decodeIfPresent([TranscriptSegment].self, forKey: .transcriptSpeechSegments)
        transcriptionQuality = try container.decodeIfPresent(TranscriptionQuality.self, forKey: .transcriptionQuality)
        transcriptionWarnings = try container.decodeIfPresent([String].self, forKey: .transcriptionWarnings)
        transcriptEditedByUser = try container.decodeIfPresent(Bool.self, forKey: .transcriptEditedByUser)
        extractionRetryCount = try container.decodeIfPresent(Int.self, forKey: .extractionRetryCount)
        likesCount = try container.decodeIfPresent(Int.self, forKey: .likesCount)
        viewsCount = try container.decodeIfPresent(Int.self, forKey: .viewsCount)
        commentsCount = try container.decodeIfPresent(Int.self, forKey: .commentsCount)
        sharesCount = try container.decodeIfPresent(Int.self, forKey: .sharesCount)
        engagementRate = try container.decodeIfPresent(Double.self, forKey: .engagementRate)
        publishedAt = try container.decodeIfPresent(Date.self, forKey: .publishedAt)
        postShortcode = try container.decodeIfPresent(String.self, forKey: .postShortcode)
        clientAdaptations = try container.decodeIfPresent([SwipeClientAdaptation].self, forKey: .clientAdaptations)
    }

    /// Mark as studied now
    public func markingStudied() -> SwipeAnalysis {
        var copy = self
        copy.studiedAt = ISO8601.string(from: Date())
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

    /// Merge curated / user-owned fields from an existing analysis into this
    /// (freshly generated) one. EVERY persist after re-analysis must call this:
    /// a fresh SwipeAnalysis knows nothing about engagement metrics, study
    /// state, comments, or manual taxonomy overrides, and would silently wipe
    /// them otherwise.
    public func preservingCuratedFields(from existing: SwipeAnalysis?) -> SwipeAnalysis {
        guard let existing else { return self }
        var merged = self

        // Engagement block — only ever set at import; analysis never produces it.
        merged.likesCount = merged.likesCount ?? existing.likesCount
        merged.viewsCount = merged.viewsCount ?? existing.viewsCount
        merged.commentsCount = merged.commentsCount ?? existing.commentsCount
        merged.sharesCount = merged.sharesCount ?? existing.sharesCount
        merged.engagementRate = merged.engagementRate ?? existing.engagementRate
        merged.publishedAt = merged.publishedAt ?? existing.publishedAt
        merged.postShortcode = merged.postShortcode ?? existing.postShortcode

        // Study state + user inputs
        merged.studiedAt = merged.studiedAt ?? existing.studiedAt
        merged.practiceAttempts = merged.practiceAttempts ?? existing.practiceAttempts
        merged.userHookScore = merged.userHookScore ?? existing.userHookScore
        merged.clientAdaptations = merged.clientAdaptations ?? existing.clientAdaptations
        merged.extractionRetryCount = merged.extractionRetryCount ?? existing.extractionRetryCount
        merged.transcriptEditedByUser = merged.transcriptEditedByUser ?? existing.transcriptEditedByUser

        // Transcript artifacts — keep existing when the fresh analysis has none.
        if merged.transcriptComments?.isEmpty != false {
            merged.transcriptComments = existing.transcriptComments
        }
        if merged.transcriptSlides?.isEmpty != false {
            merged.transcriptSlides = existing.transcriptSlides
        }
        if merged.rawTranscriptSlides?.isEmpty != false {
            merged.rawTranscriptSlides = existing.rawTranscriptSlides
        }
        if merged.transcriptSpeechSegments?.isEmpty != false {
            merged.transcriptSpeechSegments = existing.transcriptSpeechSegments
        }
        merged.transcriptionQuality = merged.transcriptionQuality ?? existing.transcriptionQuality
        if merged.transcriptionWarnings?.isEmpty != false {
            merged.transcriptionWarnings = existing.transcriptionWarnings
        }

        // A manual taxonomy override beats a fresh AI classification.
        if existing.classificationSource == .aiOverridden,
           merged.classificationSource != .aiOverridden {
            merged.primaryNarrative = existing.primaryNarrative
            merged.secondaryNarrative = existing.secondaryNarrative
            merged.swipeContentFormat = existing.swipeContentFormat
            merged.niche = existing.niche
            merged.classificationSource = existing.classificationSource
            merged.classifiedAt = existing.classifiedAt
            merged.classificationConfidence = existing.classificationConfidence
        }

        return merged
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

// MARK: - SwipeClientAdaptation

/// Per-client hook adaptation stored on each swipe atom, auto-generated on capture.
public struct SwipeClientAdaptation: Codable, Sendable, Equatable {
    public let clientUUID: String
    public let clientName: String
    public let relevanceScore: Double
    public let hookVariations: [String]
    public let ideaTitle: String
    public let whyRelevant: String
    public let suggestedFramework: String?
    public let suggestedFormat: String?
    public let generatedAt: String

    public init(
        clientUUID: String,
        clientName: String,
        relevanceScore: Double,
        hookVariations: [String],
        ideaTitle: String,
        whyRelevant: String,
        suggestedFramework: String? = nil,
        suggestedFormat: String? = nil,
        generatedAt: String = ISO8601.string(from: Date())
    ) {
        self.clientUUID = clientUUID
        self.clientName = clientName
        self.relevanceScore = relevanceScore
        self.hookVariations = hookVariations
        self.ideaTitle = ideaTitle
        self.whyRelevant = whyRelevant
        self.suggestedFramework = suggestedFramework
        self.suggestedFormat = suggestedFormat
        self.generatedAt = generatedAt
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
    public let clientUUID: String?
    public let clientName: String?
    public let instagramId: String?
    // Engagement metrics (from imported posts with Apify data)
    public let likesCount: Int?
    public let viewsCount: Int?
    public let commentsCount: Int?
    public let boardIDs: [String]
    // Processing state (nil, "pending", "extracting", "extraction_failed", "complete")
    public let processingStatus: String?

    /// Pre-lowercased concatenation of searchable fields for fast filtering
    public let searchableText: String

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
        creatorName: String? = nil,
        clientUUID: String? = nil,
        clientName: String? = nil,
        instagramId: String? = nil,
        likesCount: Int? = nil,
        viewsCount: Int? = nil,
        commentsCount: Int? = nil,
        boardIDs: [String] = [],
        processingStatus: String? = nil
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
        self.clientUUID = clientUUID
        self.clientName = clientName
        self.instagramId = instagramId
        self.likesCount = likesCount
        self.viewsCount = viewsCount
        self.commentsCount = commentsCount
        self.boardIDs = boardIDs
        self.processingStatus = processingStatus
        self.searchableText = CommandKSearchMatcher.searchableText(
            from: [title, hookText, author, niche, creatorName]
        )
    }

    /// Platform display icon
    public var platformIcon: String {
        switch platform {
        case "youtube", "youtubeShort", "youtube_short": return "play.rectangle.fill"
        case "instagram", "instagramReel", "instagramPost", "instagramCarousel",
             "instagram_reel", "instagram_post", "instagram_carousel": return "camera.fill"
        case "xPost", "twitter", "x_post": return "at"
        case "threads": return "at.badge.plus"
        case "website": return "globe"
        case "rawNote", "raw_note", "clipboard": return "doc.on.clipboard"
        default: return "doc.fill"
        }
    }

    /// Platform display name
    public var platformName: String {
        switch platform {
        case "youtube": return "YouTube"
        case "youtubeShort", "youtube_short": return "YT Short"
        case "instagram", "instagramReel", "instagramPost", "instagramCarousel",
             "instagram_reel", "instagram_post", "instagram_carousel": return "Instagram"
        case "xPost", "twitter", "x_post": return "X"
        case "threads": return "Threads"
        case "website": return "Website"
        case "rawNote", "raw_note", "clipboard": return "Clipboard"
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

    /// Decode state of the swipeAnalysis key, distinguishing "absent" from
    /// "present but undecodable". Persist paths must refuse to write a default
    /// over `.corrupt` — that's how curated analyses get silently erased.
    var decodedSwipeAnalysis: JSONDecodeState<SwipeAnalysis> {
        guard type == .research else { return .absent }
        guard let structuredStr = structured, !structuredStr.isEmpty,
              let data = structuredStr.data(using: .utf8) else { return .absent }

        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            return .corrupt(SwipeAnalysisDecodeError.structuredNotAnObject)
        }
        guard dict["swipeAnalysis"] != nil else { return .absent }
        do {
            let wrapper = try JSONDecoder().decode(SwipeAnalysisWrapper.self, from: data)
            guard let analysis = wrapper.swipeAnalysis else { return .absent }
            return .value(analysis)
        } catch {
            return .corrupt(error)
        }
    }

    /// Decode SwipeAnalysis from this atom's structured JSON.
    /// Returns nil BOTH when the key is absent and when it is corrupt —
    /// writers must check `swipeAnalysisIsCorrupt` before persisting a
    /// `swipeAnalysis ?? SwipeAnalysis()` default.
    public var swipeAnalysis: SwipeAnalysis? {
        switch decodedSwipeAnalysis {
        case .absent:
            return nil
        case .value(let analysis):
            return analysis
        case .corrupt(let error):
            PersistenceHealth.note(
                .decodeFailure,
                context: "Atom.swipeAnalysis(\(uuid.prefix(8)))",
                detail: error.localizedDescription
            )
            return nil
        }
    }

    /// True when the swipeAnalysis key (or the whole structured column) holds
    /// data that fails to decode. `swipeAnalysis` returns nil in this state.
    public var swipeAnalysisIsCorrupt: Bool {
        decodedSwipeAnalysis.isCorrupt
    }

    /// Return a new atom with the SwipeAnalysis merged into structured JSON.
    /// Uses raw JSON dictionary to preserve sibling keys (autoMetadata, transcriptComments, etc.)
    /// that would otherwise be lost by typed Codable encoding.
    /// REFUSES to write (returns self + logs) when the existing column is
    /// non-empty but unparseable, or the existing swipeAnalysis key is corrupt —
    /// proceeding from an empty dict wiped every sibling key, and overwriting a
    /// corrupt key destroyed the only copy of the curated analysis.
    public func withSwipeAnalysis(_ analysis: SwipeAnalysis) -> Atom {
        var copy = self

        // Parse existing structured as raw dictionary to preserve all keys
        var dict: [String: Any] = [:]
        if let structuredStr = structured, !structuredStr.isEmpty {
            guard let data = structuredStr.data(using: .utf8),
                  let existing = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                PersistenceHealth.note(
                    .decodeFailure,
                    context: "Atom.withSwipeAnalysis(\(uuid.prefix(8)))",
                    detail: "existing structured unparseable; refusing overwrite that would drop its data"
                )
                return copy
            }
            if existing["swipeAnalysis"] != nil, decodedSwipeAnalysis.isCorrupt {
                PersistenceHealth.note(
                    .decodeFailure,
                    context: "Atom.withSwipeAnalysis(\(uuid.prefix(8)))",
                    detail: "existing swipeAnalysis key undecodable; refusing to replace it with a fresh analysis"
                )
                return copy
            }
            dict = existing
        }

        // Update only the swipeAnalysis key
        guard let analysisData = try? JSONEncoder().encode(analysis),
              let analysisObj = try? JSONSerialization.jsonObject(with: analysisData) else {
            PersistenceHealth.note(
                .writeFailure,
                context: "Atom.withSwipeAnalysis(\(uuid.prefix(8)))",
                detail: "analysis encode failed; keeping existing column"
            )
            return copy
        }
        dict["swipeAnalysis"] = analysisObj

        // Re-encode preserving all keys
        if let jsonData = try? JSONSerialization.data(withJSONObject: dict),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            copy.structured = jsonStr
        }

        return copy
    }

    /// Check if this research atom is a swipe file
    public var isSwipeFileAtom: Bool {
        guard type == .research else { return false }
        return researchMetadata?.isSwipeFile ?? false
    }

    /// Whether this swipe has engagement data (imported vs manually captured)
    public var hasEngagementData: Bool {
        swipeAnalysis?.likesCount != nil || swipeAnalysis?.viewsCount != nil
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
        var instagramId: String?

        if let structuredStr = structured,
           let data = structuredStr.data(using: .utf8),
           let outer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let autoMetaStr = outer["autoMetadata"] as? String,
           let autoMetaData = autoMetaStr.data(using: .utf8),
           let autoMeta = try? JSONSerialization.jsonObject(with: autoMetaData) as? [String: Any] {
            // sourceType from rich content (e.g. "instagram_reel", "youtube", etc.)
            platform = autoMeta["sourceType"] as? String
            author = autoMeta["author"] as? String
            duration = autoMeta["duration"] as? Int
            instagramId = autoMeta["instagramId"] as? String

            // Fix carousel detection from instagramType field (more reliable than carouselItems check)
            if let instagramType = autoMeta["instagramType"] as? String, instagramType == "carousel" {
                if platform == "instagram" || platform == "instagramPost" || platform == "instagram_post" {
                    platform = "instagram_carousel"
                }
            }

            // Fix reel detection from instagramType field
            if let instagramType = autoMeta["instagramType"] as? String, instagramType == "reel" {
                if platform == "instagram" || platform == "instagramPost" || platform == "instagram_post" {
                    platform = "instagram_reel"
                }
            }
        }

        thumbnailUrl = meta?.thumbnailUrl

        // Fallback to metadata contentSource
        if platform == nil || platform?.isEmpty == true {
            platform = meta?.contentSource
        }

        // Extract instagramId from richContent if not in autoMetadata
        if instagramId == nil, let richContent = self.richContent {
            instagramId = richContent.instagramId
        }

        // Fix carousel detection: if rich content has carousel items, upgrade platform + fill thumbnail
        if let rc = self.richContent,
           let items = rc.instagramData?.carouselItems, !items.isEmpty {
            // Upgrade platform if it was misclassified as post
            if platform == "instagramPost" || platform == "instagram_post" || platform == "instagram" {
                platform = "instagramCarousel"
            }
            // Use first carousel image as thumbnail if none set
            if thumbnailUrl == nil || thumbnailUrl?.isEmpty == true {
                if let firstImage = items.first(where: { $0.mediaType == .image }) ?? items.first {
                    thumbnailUrl = firstImage.mediaURL.absoluteString
                }
            }
        }

        // Fallback: generic "instagram" with a video duration → reel
        if platform == "instagram", let dur = duration, dur > 0 {
            platform = "instagram_reel"
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
            creatorName: author,
            instagramId: instagramId,
            likesCount: analysis?.likesCount,
            viewsCount: analysis?.viewsCount,
            commentsCount: analysis?.commentsCount,
            boardIDs: meta?.swipeBoardIDs ?? [],
            processingStatus: meta?.processingStatus
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
    case geminiVision   // Gemini Flash 2.0 vision OCR
}

// MARK: - Transcription Content Type

/// What kind of content was detected in the video
public enum TranscriptionContentType: String, Codable, Sendable, Equatable {
    case textOnly           // On-screen text only (no voiceover)
    case voiceoverOnly      // Speech only (no on-screen text)
    case voiceoverPlusText  // Both speech and on-screen text
    case empty              // Nothing detected
}

/// High-level quality marker for Instagram transcript capture.
public enum TranscriptionQuality: String, Codable, Sendable, Equatable {
    case accurate
    case degraded
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
        self.createdAt = createdAt ?? ISO8601.string(from: Date())
    }
}

// MARK: - Private Helpers

/// Decode failures for the swipeAnalysis structured key.
enum SwipeAnalysisDecodeError: Error, LocalizedError {
    case structuredNotAnObject

    var errorDescription: String? {
        switch self {
        case .structuredNotAnObject:
            return "structured column is not a JSON object"
        }
    }
}

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

// MARK: - Auto-Clustering Models

/// Layer 1 grouping: maps ContentFormat cases into broad format families
public enum FormatGroup: String, CaseIterable, Identifiable {
    case shortFormVideo
    case staticCarousel
    case text
    case longForm
    case uncategorized

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .shortFormVideo: return "Short-Form Video"
        case .staticCarousel: return "Carousels"
        case .text: return "Text"
        case .longForm: return "Long-Form"
        case .uncategorized: return "Uncategorized"
        }
    }

    public var icon: String {
        switch self {
        case .shortFormVideo: return "play.rectangle.fill"
        case .staticCarousel: return "square.stack.fill"
        case .text: return "text.alignleft"
        case .longForm: return "doc.richtext.fill"
        case .uncategorized: return "questionmark.folder.fill"
        }
    }

    public var color: Color {
        switch self {
        case .shortFormVideo: return Color(hex: "#EF4444")  // Red
        case .staticCarousel: return Color(hex: "#F59E0B")  // Amber
        case .text: return Color(hex: "#3B82F6")            // Blue
        case .longForm: return Color(hex: "#8B5CF6")        // Purple
        case .uncategorized: return Color(hex: "#6B7280")   // Gray
        }
    }

    public static func group(for format: ContentFormat?) -> FormatGroup {
        guard let f = format else { return .uncategorized }
        if ContentFormat.shortFormVideo.contains(f) || f == .reel { return .shortFormVideo }
        if ContentFormat.staticFormats.contains(f) { return .staticCarousel }
        if ContentFormat.textFormats.contains(f) { return .text }
        if ContentFormat.longFormFormats.contains(f) { return .longForm }
        return .uncategorized
    }
}

/// Layer 2 cluster: a narrative grouping within a format group
public struct SwipeCluster: Identifiable {
    public let id: String
    public let formatGroup: FormatGroup
    public let narrative: NarrativeStyle?
    public var items: [SwipeGalleryItem]

    public var displayName: String {
        narrative?.displayName ?? "Other"
    }

    public var itemCount: Int { items.count }
    public var isOtherBucket: Bool { narrative == nil }

    public var narrativeColor: Color {
        narrative?.color ?? Color(hex: "#6B7280")
    }

    public var narrativeIcon: String {
        narrative?.icon ?? "folder.fill"
    }
}

/// Layer 1 section: a format group containing narrative clusters
public struct FormatSection: Identifiable {
    public let id: String
    public let formatGroup: FormatGroup
    public var clusters: [SwipeCluster]

    public var totalItemCount: Int {
        clusters.reduce(0) { $0 + $1.itemCount }
    }
}

/// Builds 2-level clustered sections from a flat list of gallery items.
/// Groups with < minClusterSize items in a narrative merge into "Other".
public func buildClusteredSections(
    from items: [SwipeGalleryItem],
    minClusterSize: Int = 5
) -> [FormatSection] {
    // Layer 1: group by format
    var formatBuckets: [FormatGroup: [SwipeGalleryItem]] = [:]
    for item in items {
        let group = FormatGroup.group(for: item.swipeContentFormat)
        formatBuckets[group, default: []].append(item)
    }

    // Build sections in stable order
    let groupOrder: [FormatGroup] = [.shortFormVideo, .staticCarousel, .text, .longForm, .uncategorized]

    var sections: [FormatSection] = []
    for group in groupOrder {
        guard let groupItems = formatBuckets[group], !groupItems.isEmpty else { continue }

        // Layer 2: sub-group by narrative
        var narrativeBuckets: [NarrativeStyle: [SwipeGalleryItem]] = [:]
        var noNarrative: [SwipeGalleryItem] = []

        for item in groupItems {
            if let narrative = item.primaryNarrative {
                narrativeBuckets[narrative, default: []].append(item)
            } else {
                noNarrative.append(item)
            }
        }

        var clusters: [SwipeCluster] = []
        var otherItems = noNarrative

        // Promote narrative groups that meet threshold, merge rest into Other
        for (narrative, narrativeItems) in narrativeBuckets {
            if narrativeItems.count >= minClusterSize {
                clusters.append(SwipeCluster(
                    id: "\(group.rawValue)-\(narrative.rawValue)",
                    formatGroup: group,
                    narrative: narrative,
                    items: narrativeItems
                ))
            } else {
                otherItems.append(contentsOf: narrativeItems)
            }
        }

        // Sort named clusters by item count descending
        clusters.sort { $0.itemCount > $1.itemCount }

        // Add "Other" bucket if non-empty
        if !otherItems.isEmpty {
            clusters.append(SwipeCluster(
                id: "\(group.rawValue)-other",
                formatGroup: group,
                narrative: nil,
                items: otherItems
            ))
        }

        sections.append(FormatSection(
            id: group.rawValue,
            formatGroup: group,
            clusters: clusters
        ))
    }

    return sections
}
