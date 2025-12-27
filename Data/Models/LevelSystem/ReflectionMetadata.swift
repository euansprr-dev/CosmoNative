// CosmoOS/Data/Models/LevelSystem/ReflectionMetadata.swift
// Metadata structures for reflection and self-analysis tracking
// Supports journal insights, emotional states, clarity scoring, and LLM analysis chunks

import Foundation

// MARK: - Insight Types

/// Types of insights that can be extracted from journals and reflections
enum InsightType: String, Codable, Sendable, CaseIterable {
    case goal               // Future-oriented objectives
    case fear               // Concerns and anxieties
    case belief             // Core beliefs and values
    case pattern            // Recurring behaviors/thoughts
    case breakthrough       // Sudden realizations
    case gratitude          // Appreciation moments
    case frustration        // Pain points and blockers
    case aspiration         // Long-term dreams
    case lesson             // Learned lessons
    case question           // Unresolved questions
    case decision           // Important choices made
    case commitment         // Promises to self
    case realization        // New understandings
    case contradiction      // Conflicting thoughts
    case progress           // Forward movement noted
    case opportunity        // An opportunity identified
    case blocker            // Something blocking progress (alias for frustration)
    case relationship       // Insight about a relationship
    case other              // Other/uncategorized

    var displayName: String {
        switch self {
        case .goal: return "Goal"
        case .fear: return "Fear"
        case .belief: return "Belief"
        case .pattern: return "Pattern"
        case .breakthrough: return "Breakthrough"
        case .gratitude: return "Gratitude"
        case .frustration: return "Frustration"
        case .aspiration: return "Aspiration"
        case .lesson: return "Lesson"
        case .question: return "Question"
        case .decision: return "Decision"
        case .commitment: return "Commitment"
        case .realization: return "Realization"
        case .contradiction: return "Contradiction"
        case .progress: return "Progress"
        case .opportunity: return "Opportunity"
        case .blocker: return "Blocker"
        case .relationship: return "Relationship"
        case .other: return "Other"
        }
    }

    var iconName: String {
        switch self {
        case .goal: return "target"
        case .fear: return "exclamationmark.triangle"
        case .belief: return "heart.fill"
        case .pattern: return "repeat"
        case .breakthrough: return "lightbulb.fill"
        case .gratitude: return "hands.clap.fill"
        case .frustration: return "cloud.bolt.fill"
        case .aspiration: return "star.fill"
        case .lesson: return "book.fill"
        case .question: return "questionmark.circle.fill"
        case .decision: return "arrow.triangle.branch"
        case .commitment: return "checkmark.seal.fill"
        case .realization: return "sparkles"
        case .contradiction: return "arrow.left.arrow.right"
        case .progress: return "chart.line.uptrend.xyaxis"
        case .opportunity: return "flag.fill"
        case .blocker: return "xmark.octagon.fill"
        case .relationship: return "person.2.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }

    /// XP value for extracting this type of insight
    var xpValue: Int {
        switch self {
        case .breakthrough, .realization: return 15
        case .goal, .decision, .commitment, .opportunity: return 10
        case .pattern, .lesson, .progress, .relationship: return 8
        case .belief, .aspiration, .question: return 5
        case .gratitude, .frustration, .fear, .contradiction, .blocker: return 3
        case .other: return 2
        }
    }
}

// MARK: - Emotion System

/// Primary emotion categories based on Plutchik's Wheel of Emotions
enum Emotion: String, Codable, Sendable, CaseIterable {
    // Primary emotions
    case joy
    case trust
    case fear
    case surprise
    case sadness
    case disgust
    case anger
    case anticipation

    // Secondary emotions (combinations)
    case love           // joy + trust
    case submission     // trust + fear
    case awe            // fear + surprise
    case disapproval    // surprise + sadness
    case remorse        // sadness + disgust
    case contempt       // disgust + anger
    case aggressiveness // anger + anticipation
    case optimism       // anticipation + joy

    // Tertiary/nuanced emotions
    case serenity       // mild joy
    case acceptance     // mild trust
    case apprehension   // mild fear
    case distraction    // mild surprise
    case pensiveness    // mild sadness
    case boredom        // mild disgust
    case annoyance      // mild anger
    case interest       // mild anticipation

    // Complex states
    case gratitude
    case pride
    case shame
    case guilt
    case envy
    case hope
    case anxiety
    case confusion
    case determination
    case relief
    case neutral

    var displayName: String {
        rawValue.capitalized
    }

    /// Emotional valence (-1 = negative, 0 = neutral, 1 = positive)
    var baseValence: Double {
        switch self {
        case .joy, .love, .optimism, .serenity, .gratitude, .pride, .hope, .relief:
            return 0.8
        case .trust, .acceptance, .interest, .anticipation, .determination:
            return 0.5
        case .surprise, .distraction, .awe:
            return 0.2
        case .neutral, .confusion:
            return 0.0
        case .pensiveness, .apprehension, .boredom, .annoyance, .submission:
            return -0.3
        case .sadness, .fear, .disgust, .anger, .anxiety, .shame, .guilt, .envy:
            return -0.6
        case .disapproval, .remorse, .contempt, .aggressiveness:
            return -0.8
        }
    }

    /// Base arousal level (0 = calm, 1 = activated)
    var baseArousal: Double {
        switch self {
        case .serenity, .pensiveness, .boredom, .acceptance, .neutral:
            return 0.2
        case .sadness, .trust, .disgust, .relief:
            return 0.3
        case .joy, .anticipation, .interest, .hope, .gratitude, .pride:
            return 0.5
        case .love, .optimism, .determination, .guilt, .shame, .envy:
            return 0.6
        case .surprise, .fear, .anger, .anxiety, .apprehension, .confusion:
            return 0.7
        case .awe, .aggressiveness, .contempt, .remorse, .disapproval, .annoyance, .distraction, .submission:
            return 0.8
        }
    }
}

/// Source of emotional state detection
enum EmotionalStateSource: String, Codable, Sendable {
    case journal        // Extracted from journal text
    case voice          // Detected from voice analysis
    case inferred       // Inferred from behavior
    case manual         // User self-reported
    case physiological  // Inferred from HRV/vitals
    case contextual     // Based on time/activity context

    var displayName: String {
        switch self {
        case .journal: return "Journal"
        case .voice: return "Voice"
        case .inferred: return "Inferred"
        case .manual: return "Self-Reported"
        case .physiological: return "Physiological"
        case .contextual: return "Contextual"
        }
    }

    var confidenceMultiplier: Double {
        switch self {
        case .manual: return 1.0          // User knows best
        case .journal: return 0.9         // Rich text data
        case .voice: return 0.85          // Good signal but noisy
        case .physiological: return 0.8   // Objective but indirect
        case .inferred: return 0.6        // Pattern-based
        case .contextual: return 0.5      // Most uncertain
        }
    }
}

// MARK: - Journal Insight Metadata

/// Metadata for journalInsight atoms - insights extracted from journal entries
struct JournalInsightMetadata: Codable, Sendable {
    /// UUID of the source journal atom
    let journalAtomUUID: String

    /// Type of insight extracted
    let insightType: InsightType

    /// The extracted text/quote from the journal
    let extractedText: String

    /// AI confidence in this extraction (0-1)
    let confidence: Double

    /// Suggested action based on this insight
    let suggestedAction: String?

    /// UUIDs of related atoms this insight connects to
    let linkedAtomUUIDs: [String]

    /// Emotional valence of this insight (-1 to 1)
    let emotionalValence: Double

    /// Keywords/tags extracted
    let keywords: [String]

    /// Whether the user has acknowledged/reviewed this insight
    let acknowledged: Bool

    /// When this insight was extracted
    let extractedAt: Date

    /// Model that extracted this insight
    let extractionModel: String

    /// Position in the source journal (for context)
    let sourcePosition: TextPosition?

    /// XP earned from this insight
    var estimatedXP: Int {
        let baseXP = insightType.xpValue
        let confidenceBonus = confidence > 0.9 ? 2 : 0
        return baseXP + confidenceBonus
    }

    init(
        journalAtomUUID: String,
        insightType: InsightType,
        extractedText: String,
        confidence: Double,
        suggestedAction: String? = nil,
        linkedAtomUUIDs: [String] = [],
        emotionalValence: Double = 0,
        keywords: [String] = [],
        acknowledged: Bool = false,
        extractedAt: Date = Date(),
        extractionModel: String = "local",
        sourcePosition: TextPosition? = nil
    ) {
        self.journalAtomUUID = journalAtomUUID
        self.insightType = insightType
        self.extractedText = extractedText
        self.confidence = confidence
        self.suggestedAction = suggestedAction
        self.linkedAtomUUIDs = linkedAtomUUIDs
        self.emotionalValence = emotionalValence
        self.keywords = keywords
        self.acknowledged = acknowledged
        self.extractedAt = extractedAt
        self.extractionModel = extractionModel
        self.sourcePosition = sourcePosition
    }
}

/// Position within source text for reference
struct TextPosition: Codable, Sendable {
    let startOffset: Int
    let endOffset: Int
    let paragraphIndex: Int?

    init(startOffset: Int, endOffset: Int, paragraphIndex: Int? = nil) {
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.paragraphIndex = paragraphIndex
    }
}

// MARK: - Emotional State Metadata

/// Metadata for emotionalState atoms - sentiment snapshots
struct EmotionalStateMetadata: Codable, Sendable {
    /// When this emotional state was captured
    let timestamp: Date

    /// Primary emotion detected
    let primaryEmotion: Emotion

    /// Secondary emotions present
    let secondaryEmotions: [Emotion]

    /// Overall emotional valence (-1 = very negative to 1 = very positive)
    let valence: Double

    /// Arousal level (0 = calm to 1 = highly activated)
    let arousal: Double

    /// Dominance/control (0 = submissive to 1 = dominant)
    let dominance: Double

    /// How this state was detected
    let source: EmotionalStateSource

    /// Optional context notes
    let contextNotes: String?

    /// Related atom UUIDs (journal, task, etc.)
    let relatedAtomUUIDs: [String]

    /// AI confidence in detection (0-1)
    let confidence: Double

    /// Duration this state persisted (if known)
    let duration: TimeInterval?

    /// Trigger event (if identifiable)
    let trigger: String?

    /// Comparison to baseline
    let vsBaseline: Double?

    /// Circadian phase when captured
    let circadianPhase: CircadianPhase?

    /// Composite emotional energy score
    var emotionalEnergy: Double {
        // Combine arousal and absolute valence for "emotional intensity"
        (arousal + abs(valence)) / 2.0
    }

    /// Whether this is a positive state
    var isPositive: Bool {
        valence > 0.1
    }

    /// Whether this is an activated/alert state
    var isActivated: Bool {
        arousal > 0.5
    }

    init(
        timestamp: Date = Date(),
        primaryEmotion: Emotion,
        secondaryEmotions: [Emotion] = [],
        valence: Double,
        arousal: Double,
        dominance: Double = 0.5,
        source: EmotionalStateSource,
        contextNotes: String? = nil,
        relatedAtomUUIDs: [String] = [],
        confidence: Double = 0.8,
        duration: TimeInterval? = nil,
        trigger: String? = nil,
        vsBaseline: Double? = nil,
        circadianPhase: CircadianPhase? = nil
    ) {
        self.timestamp = timestamp
        self.primaryEmotion = primaryEmotion
        self.secondaryEmotions = secondaryEmotions
        self.valence = valence
        self.arousal = arousal
        self.dominance = dominance
        self.source = source
        self.contextNotes = contextNotes
        self.relatedAtomUUIDs = relatedAtomUUIDs
        self.confidence = confidence
        self.duration = duration
        self.trigger = trigger
        self.vsBaseline = vsBaseline
        self.circadianPhase = circadianPhase
    }
}

/// Circadian rhythm phase
enum CircadianPhase: String, Codable, Sendable {
    case earlyMorning       // 5-8am
    case morning            // 8-11am
    case lateMorning        // 11am-1pm
    case earlyAfternoon     // 1-3pm
    case lateAfternoon      // 3-6pm
    case evening            // 6-9pm
    case night              // 9pm-12am
    case lateNight          // 12-5am

    var displayName: String {
        switch self {
        case .earlyMorning: return "Early Morning"
        case .morning: return "Morning"
        case .lateMorning: return "Late Morning"
        case .earlyAfternoon: return "Early Afternoon"
        case .lateAfternoon: return "Late Afternoon"
        case .evening: return "Evening"
        case .night: return "Night"
        case .lateNight: return "Late Night"
        }
    }

    static func from(hour: Int) -> CircadianPhase {
        switch hour {
        case 5..<8: return .earlyMorning
        case 8..<11: return .morning
        case 11..<13: return .lateMorning
        case 13..<15: return .earlyAfternoon
        case 15..<18: return .lateAfternoon
        case 18..<21: return .evening
        case 21..<24: return .night
        default: return .lateNight
        }
    }
}

// MARK: - Clarity Score Metadata

/// Metadata for clarityScore atoms - journal quality metrics
struct ClarityScoreMetadata: Codable, Sendable {
    /// UUID of the journal being scored
    let journalAtomUUID: String

    /// Overall clarity score (0-100)
    let overallClarity: Double

    /// Coherent thought progression score (0-100)
    let structureScore: Double

    /// Concrete vs vague language score (0-100)
    let specificityScore: Double

    /// Leads to clear actions score (0-100)
    let actionabilityScore: Double

    /// Self-awareness quality score (0-100)
    let emotionalAccuracy: Double

    /// Insights per 100 words
    let insightDensity: Double

    /// Word count of the journal
    let wordCount: Int

    /// Reading complexity level
    let readingLevel: ReadingLevel

    /// Vocabulary diversity (unique words / total words)
    let vocabularyDiversity: Double

    /// Temporal orientation (past/present/future focus)
    let temporalOrientation: TemporalOrientation

    /// Self vs other focus ratio
    let selfFocusRatio: Double

    /// When this score was calculated
    let scoredAt: Date

    /// Model that calculated the score
    let scoringModel: String

    /// Comparison to user's average
    let vsUserAverage: Double?

    /// Whether this is a personal best
    let isPersonalBest: Bool

    /// XP earned from clarity
    var estimatedXP: Int {
        // 1 XP per 10 clarity points, bonus for high scores
        let baseXP = Int(overallClarity / 10.0)
        let highClarityBonus = overallClarity > 80 ? 5 : 0
        let personalBestBonus = isPersonalBest ? 10 : 0
        return baseXP + highClarityBonus + personalBestBonus
    }

    init(
        journalAtomUUID: String,
        overallClarity: Double,
        structureScore: Double,
        specificityScore: Double,
        actionabilityScore: Double,
        emotionalAccuracy: Double,
        insightDensity: Double,
        wordCount: Int,
        readingLevel: ReadingLevel = .intermediate,
        vocabularyDiversity: Double = 0.5,
        temporalOrientation: TemporalOrientation = .present,
        selfFocusRatio: Double = 0.5,
        scoredAt: Date = Date(),
        scoringModel: String = "local",
        vsUserAverage: Double? = nil,
        isPersonalBest: Bool = false
    ) {
        self.journalAtomUUID = journalAtomUUID
        self.overallClarity = overallClarity
        self.structureScore = structureScore
        self.specificityScore = specificityScore
        self.actionabilityScore = actionabilityScore
        self.emotionalAccuracy = emotionalAccuracy
        self.insightDensity = insightDensity
        self.wordCount = wordCount
        self.readingLevel = readingLevel
        self.vocabularyDiversity = vocabularyDiversity
        self.temporalOrientation = temporalOrientation
        self.selfFocusRatio = selfFocusRatio
        self.scoredAt = scoredAt
        self.scoringModel = scoringModel
        self.vsUserAverage = vsUserAverage
        self.isPersonalBest = isPersonalBest
    }
}

/// Reading complexity level
enum ReadingLevel: String, Codable, Sendable {
    case elementary     // Grade 1-5
    case intermediate   // Grade 6-8
    case highSchool     // Grade 9-12
    case collegiate     // College level
    case advanced       // Graduate/professional

    var displayName: String {
        switch self {
        case .elementary: return "Elementary"
        case .intermediate: return "Intermediate"
        case .highSchool: return "High School"
        case .collegiate: return "Collegiate"
        case .advanced: return "Advanced"
        }
    }

    var gradeRange: ClosedRange<Int> {
        switch self {
        case .elementary: return 1...5
        case .intermediate: return 6...8
        case .highSchool: return 9...12
        case .collegiate: return 13...16
        case .advanced: return 17...20
        }
    }
}

/// Temporal orientation of journal content
enum TemporalOrientation: String, Codable, Sendable {
    case past           // Reflecting on past events
    case present        // Describing current state
    case future         // Planning/anticipating
    case mixed          // Balanced across time

    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - Analysis Chunk Metadata

/// Metadata for analysisChunk atoms - LLM analysis segments
struct AnalysisChunkMetadata: Codable, Sendable {
    /// UUID of the source atom being analyzed
    let sourceAtomUUID: String

    /// Type of source atom
    let sourceAtomType: String

    /// Type of analysis performed
    let analysisType: AnalysisType

    /// The analysis output/content
    let analysisContent: String

    /// Summary of the analysis (shorter form)
    let summary: String?

    /// Key points extracted
    let keyPoints: [String]

    /// Suggested actions from analysis
    let suggestedActions: [ReflectionSuggestedAction]

    /// Related atoms discovered during analysis
    let discoveredLinks: [String]

    /// Tags generated from analysis
    let generatedTags: [String]

    /// Sentiment of the analyzed content
    let sentimentScore: Double?

    /// Entities extracted (people, places, concepts)
    let extractedEntities: [ReflectionExtractedEntity]

    /// When this analysis was performed
    let analyzedAt: Date

    /// Model used for analysis
    let analysisModel: String

    /// Processing time in seconds
    let processingTime: TimeInterval

    /// Token count used
    let tokenCount: Int?

    /// Analysis confidence (0-1)
    let confidence: Double

    /// Whether this analysis has been reviewed by user
    let reviewed: Bool

    /// User feedback on analysis quality
    let userFeedback: AnalysisFeedback?

    init(
        sourceAtomUUID: String,
        sourceAtomType: String,
        analysisType: AnalysisType,
        analysisContent: String,
        summary: String? = nil,
        keyPoints: [String] = [],
        suggestedActions: [ReflectionSuggestedAction] = [],
        discoveredLinks: [String] = [],
        generatedTags: [String] = [],
        sentimentScore: Double? = nil,
        extractedEntities: [ReflectionExtractedEntity] = [],
        analyzedAt: Date = Date(),
        analysisModel: String = "local",
        processingTime: TimeInterval = 0,
        tokenCount: Int? = nil,
        confidence: Double = 0.8,
        reviewed: Bool = false,
        userFeedback: AnalysisFeedback? = nil
    ) {
        self.sourceAtomUUID = sourceAtomUUID
        self.sourceAtomType = sourceAtomType
        self.analysisType = analysisType
        self.analysisContent = analysisContent
        self.summary = summary
        self.keyPoints = keyPoints
        self.suggestedActions = suggestedActions
        self.discoveredLinks = discoveredLinks
        self.generatedTags = generatedTags
        self.sentimentScore = sentimentScore
        self.extractedEntities = extractedEntities
        self.analyzedAt = analyzedAt
        self.analysisModel = analysisModel
        self.processingTime = processingTime
        self.tokenCount = tokenCount
        self.confidence = confidence
        self.reviewed = reviewed
        self.userFeedback = userFeedback
    }
}

/// Type of analysis performed
enum AnalysisType: String, Codable, Sendable {
    case summarization      // Create summary
    case insightExtraction  // Extract insights
    case entityExtraction   // Extract entities
    case sentimentAnalysis  // Analyze sentiment
    case themeIdentification // Identify themes
    case actionExtraction   // Extract action items
    case linkSuggestion     // Suggest connections
    case patternDetection   // Detect patterns
    case clarityAssessment  // Assess writing clarity
    case emotionalAnalysis  // Deep emotional analysis
    case goalExtraction     // Extract goals
    case reflectionPrompt   // Generate reflection prompts
    case comprehensive      // Full multi-aspect analysis

    var displayName: String {
        switch self {
        case .summarization: return "Summary"
        case .insightExtraction: return "Insights"
        case .entityExtraction: return "Entities"
        case .sentimentAnalysis: return "Sentiment"
        case .themeIdentification: return "Themes"
        case .actionExtraction: return "Actions"
        case .linkSuggestion: return "Links"
        case .patternDetection: return "Patterns"
        case .clarityAssessment: return "Clarity"
        case .emotionalAnalysis: return "Emotions"
        case .goalExtraction: return "Goals"
        case .reflectionPrompt: return "Prompts"
        case .comprehensive: return "Full Analysis"
        }
    }
}

/// A suggested action from reflection analysis
struct ReflectionSuggestedAction: Codable, Sendable {
    let action: String
    let priority: ActionPriority
    let category: String?
    let deadline: Date?
    let linkedAtomUUID: String?

    init(
        action: String,
        priority: ActionPriority = .medium,
        category: String? = nil,
        deadline: Date? = nil,
        linkedAtomUUID: String? = nil
    ) {
        self.action = action
        self.priority = priority
        self.category = category
        self.deadline = deadline
        self.linkedAtomUUID = linkedAtomUUID
    }
}

/// Priority level for suggested actions
enum ActionPriority: String, Codable, Sendable {
    case low
    case medium
    case high
    case urgent

    var displayName: String {
        rawValue.capitalized
    }

    var sortOrder: Int {
        switch self {
        case .urgent: return 0
        case .high: return 1
        case .medium: return 2
        case .low: return 3
        }
    }
}

/// An entity extracted from content
struct ReflectionExtractedEntity: Codable, Sendable {
    let text: String
    let entityType: ExtractedEntityType
    let confidence: Double
    let linkedAtomUUID: String?

    init(
        text: String,
        entityType: ExtractedEntityType,
        confidence: Double = 0.8,
        linkedAtomUUID: String? = nil
    ) {
        self.text = text
        self.entityType = entityType
        self.confidence = confidence
        self.linkedAtomUUID = linkedAtomUUID
    }
}

/// Type of extracted entity from NLP analysis
enum ExtractedEntityType: String, Codable, Sendable {
    case person
    case place
    case organization
    case concept
    case event
    case date
    case project
    case tool
    case emotion
    case goal
    case metric
    case other

    var displayName: String {
        rawValue.capitalized
    }

    var iconName: String {
        switch self {
        case .person: return "person.fill"
        case .place: return "mappin.circle.fill"
        case .organization: return "building.2.fill"
        case .concept: return "lightbulb.fill"
        case .event: return "calendar"
        case .date: return "clock.fill"
        case .project: return "folder.fill"
        case .tool: return "wrench.fill"
        case .emotion: return "heart.fill"
        case .goal: return "target"
        case .metric: return "chart.bar.fill"
        case .other: return "tag.fill"
        }
    }
}

/// User feedback on analysis quality
struct AnalysisFeedback: Codable, Sendable {
    let rating: Int  // 1-5
    let helpful: Bool
    let accurate: Bool
    let comments: String?
    let submittedAt: Date

    init(
        rating: Int,
        helpful: Bool,
        accurate: Bool,
        comments: String? = nil,
        submittedAt: Date = Date()
    ) {
        self.rating = rating
        self.helpful = helpful
        self.accurate = accurate
        self.comments = comments
        self.submittedAt = submittedAt
    }
}

// MARK: - Emotional Trend Metadata

/// Metadata for tracking emotional trends over time
struct EmotionalTrendMetadata: Codable, Sendable {
    /// Date range for this trend analysis
    let startDate: Date
    let endDate: Date

    /// Average valence over period
    let averageValence: Double

    /// Average arousal over period
    let averageArousal: Double

    /// Most frequent emotion
    let dominantEmotion: Emotion

    /// Emotional stability (inverse of variance)
    let stability: Double

    /// Trend direction for valence
    let valenceTrend: Trend

    /// Significant emotional events
    let significantEvents: [EmotionalEvent]

    /// Time of day patterns
    let circadianPatterns: [CircadianPhase: Emotion]

    /// Day of week patterns
    let weekdayPatterns: [Int: Double]  // Day (0=Sunday) to avg valence

    /// Correlation with other metrics
    let correlations: EmotionalCorrelations

    init(
        startDate: Date,
        endDate: Date,
        averageValence: Double,
        averageArousal: Double,
        dominantEmotion: Emotion,
        stability: Double,
        valenceTrend: Trend,
        significantEvents: [EmotionalEvent] = [],
        circadianPatterns: [CircadianPhase: Emotion] = [:],
        weekdayPatterns: [Int: Double] = [:],
        correlations: EmotionalCorrelations = EmotionalCorrelations()
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.averageValence = averageValence
        self.averageArousal = averageArousal
        self.dominantEmotion = dominantEmotion
        self.stability = stability
        self.valenceTrend = valenceTrend
        self.significantEvents = significantEvents
        self.circadianPatterns = circadianPatterns
        self.weekdayPatterns = weekdayPatterns
        self.correlations = correlations
    }
}

/// A significant emotional event
struct EmotionalEvent: Codable, Sendable {
    let timestamp: Date
    let emotion: Emotion
    let valence: Double
    let trigger: String?
    let sourceAtomUUID: String?

    init(
        timestamp: Date,
        emotion: Emotion,
        valence: Double,
        trigger: String? = nil,
        sourceAtomUUID: String? = nil
    ) {
        self.timestamp = timestamp
        self.emotion = emotion
        self.valence = valence
        self.trigger = trigger
        self.sourceAtomUUID = sourceAtomUUID
    }
}

/// Correlations between emotions and other metrics
struct EmotionalCorrelations: Codable, Sendable {
    var sleepQuality: Double?           // Correlation with sleep
    var hrvBaseline: Double?            // Correlation with HRV
    var productivityScore: Double?      // Correlation with focus
    var socialInteraction: Double?      // Correlation with connections
    var exerciseFrequency: Double?      // Correlation with workouts

    init(
        sleepQuality: Double? = nil,
        hrvBaseline: Double? = nil,
        productivityScore: Double? = nil,
        socialInteraction: Double? = nil,
        exerciseFrequency: Double? = nil
    ) {
        self.sleepQuality = sleepQuality
        self.hrvBaseline = hrvBaseline
        self.productivityScore = productivityScore
        self.socialInteraction = socialInteraction
        self.exerciseFrequency = exerciseFrequency
    }
}

// MARK: - Reflection Session Metadata

/// Metadata for structured reflection sessions
struct ReflectionSessionMetadata: Codable, Sendable {
    /// When the reflection session occurred
    let sessionDate: Date

    /// Duration of the session
    let duration: TimeInterval

    /// Type of reflection session
    let sessionType: ReflectionSessionType

    /// Prompts used during session
    let promptsUsed: [String]

    /// Journal atom created during session (if any)
    let journalAtomUUID: String?

    /// Insights extracted count
    let insightsExtracted: Int

    /// Actions identified count
    let actionsIdentified: Int

    /// User satisfaction rating (1-5)
    let satisfactionRating: Int?

    /// Emotional state at start
    let startingEmotion: Emotion?

    /// Emotional state at end
    let endingEmotion: Emotion?

    /// Whether this completed a streak
    let completedStreak: Bool

    /// XP earned from this session
    var estimatedXP: Int {
        let baseXP = sessionType.baseXP
        let durationBonus = Int(min(duration / 60.0, 30)) // Up to 30 bonus XP for 30 min
        let insightBonus = insightsExtracted * 2
        let streakBonus = completedStreak ? 10 : 0
        return baseXP + durationBonus + insightBonus + streakBonus
    }

    init(
        sessionDate: Date = Date(),
        duration: TimeInterval,
        sessionType: ReflectionSessionType,
        promptsUsed: [String] = [],
        journalAtomUUID: String? = nil,
        insightsExtracted: Int = 0,
        actionsIdentified: Int = 0,
        satisfactionRating: Int? = nil,
        startingEmotion: Emotion? = nil,
        endingEmotion: Emotion? = nil,
        completedStreak: Bool = false
    ) {
        self.sessionDate = sessionDate
        self.duration = duration
        self.sessionType = sessionType
        self.promptsUsed = promptsUsed
        self.journalAtomUUID = journalAtomUUID
        self.insightsExtracted = insightsExtracted
        self.actionsIdentified = actionsIdentified
        self.satisfactionRating = satisfactionRating
        self.startingEmotion = startingEmotion
        self.endingEmotion = endingEmotion
        self.completedStreak = completedStreak
    }
}

/// Type of reflection session
enum ReflectionSessionType: String, Codable, Sendable {
    case morningIntention   // Morning planning
    case eveningReview      // End of day review
    case weeklyReflection   // Weekly retrospective
    case monthlyReview      // Monthly deep dive
    case gratitude          // Gratitude journaling
    case emotionalProcessing // Processing difficult emotions
    case goalSetting        // Setting/reviewing goals
    case problemSolving     // Working through challenges
    case freeform           // Unstructured reflection

    var displayName: String {
        switch self {
        case .morningIntention: return "Morning Intention"
        case .eveningReview: return "Evening Review"
        case .weeklyReflection: return "Weekly Reflection"
        case .monthlyReview: return "Monthly Review"
        case .gratitude: return "Gratitude"
        case .emotionalProcessing: return "Emotional Processing"
        case .goalSetting: return "Goal Setting"
        case .problemSolving: return "Problem Solving"
        case .freeform: return "Freeform"
        }
    }

    var baseXP: Int {
        switch self {
        case .monthlyReview: return 50
        case .weeklyReflection: return 30
        case .goalSetting: return 25
        case .emotionalProcessing: return 20
        case .morningIntention, .eveningReview: return 15
        case .gratitude, .problemSolving: return 10
        case .freeform: return 5
        }
    }

    var suggestedDuration: TimeInterval {
        switch self {
        case .monthlyReview: return 45 * 60      // 45 min
        case .weeklyReflection: return 30 * 60  // 30 min
        case .goalSetting: return 20 * 60       // 20 min
        case .emotionalProcessing: return 15 * 60
        case .morningIntention: return 10 * 60  // 10 min
        case .eveningReview: return 10 * 60
        case .gratitude: return 5 * 60          // 5 min
        case .problemSolving: return 15 * 60
        case .freeform: return 10 * 60
        }
    }
}
