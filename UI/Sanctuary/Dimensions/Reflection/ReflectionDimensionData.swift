// CosmoOS/UI/Sanctuary/Dimensions/Reflection/ReflectionDimensionData.swift
// Data Models - Emotional landscape, journaling, meditation, and grail insights
// Phase 8: Following SANCTUARY_UI_SPEC_V2.md section 3.6

import SwiftUI

// MARK: - Mood Source

public enum MoodSource: String, Codable, Sendable {
    case manual
    case journal
    case inferred

    public var displayName: String {
        switch self {
        case .manual: return "Manual Entry"
        case .journal: return "From Journal"
        case .inferred: return "AI Inferred"
        }
    }
}

// MARK: - Trend Direction

public enum TrendDirection: String, Codable, Sendable {
    case improving
    case stable
    case declining

    public var displayName: String {
        switch self {
        case .improving: return "Improving"
        case .stable: return "Stable"
        case .declining: return "Declining"
        }
    }

    public var iconName: String {
        switch self {
        case .improving: return "arrow.up.right"
        case .stable: return "arrow.right"
        case .declining: return "arrow.down.right"
        }
    }

    public var color: Color {
        switch self {
        case .improving: return SanctuaryColors.Semantic.success
        case .stable: return SanctuaryColors.Text.secondary
        case .declining: return SanctuaryColors.Semantic.error
        }
    }
}

// MARK: - Emotional Data Point

public struct EmotionalDataPoint: Identifiable, Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let valence: Double // -1 (negative) to +1 (positive)
    public let energy: Double // -1 (low) to +1 (high)
    public let emoji: String
    public let note: String?
    public let source: MoodSource

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        valence: Double,
        energy: Double,
        emoji: String,
        note: String? = nil,
        source: MoodSource
    ) {
        self.id = id
        self.timestamp = timestamp
        self.valence = max(-1, min(1, valence))
        self.energy = max(-1, min(1, energy))
        self.emoji = emoji
        self.note = note
        self.source = source
    }

    public var quadrantLabel: String {
        if valence >= 0 && energy >= 0 { return "High Energy Positive" }
        if valence < 0 && energy >= 0 { return "High Energy Negative" }
        if valence >= 0 && energy < 0 { return "Low Energy Positive" }
        return "Low Energy Negative"
    }
}

// MARK: - Emotional State

public struct EmotionalState: Codable, Sendable {
    public let valence: Double
    public let energy: Double
    public let description: String
    public let emoji: String
    public let comparedToAverage: String

    public init(
        valence: Double,
        energy: Double,
        description: String,
        emoji: String,
        comparedToAverage: String
    ) {
        self.valence = max(-1, min(1, valence))
        self.energy = max(-1, min(1, energy))
        self.description = description
        self.emoji = emoji
        self.comparedToAverage = comparedToAverage
    }

    public var valenceLabel: String {
        if valence >= 0.3 { return "Positive" }
        if valence <= -0.3 { return "Negative" }
        return "Neutral"
    }

    public var energyLabel: String {
        if energy >= 0.3 { return "High Energy" }
        if energy <= -0.3 { return "Low Energy" }
        return "Moderate Energy"
    }

    /// Dominant mood based on valence and energy
    public var dominantMood: String {
        if valence >= 0.3 && energy >= 0.3 { return "Excited" }
        if valence >= 0.3 && energy <= -0.3 { return "Calm" }
        if valence <= -0.3 && energy >= 0.3 { return "Tense" }
        if valence <= -0.3 && energy <= -0.3 { return "Low" }
        return "Neutral"
    }

    /// Label (alias for description)
    public var label: String { description }
}

// MARK: - Hourly Mood

public struct HourlyMood: Identifiable, Codable, Sendable {
    public let id: UUID
    public let hour: Int
    public let valence: Double
    public let energy: Double
    public let emoji: String
    public let label: String

    public init(
        id: UUID = UUID(),
        hour: Int,
        valence: Double,
        energy: Double,
        emoji: String,
        label: String
    ) {
        self.id = id
        self.hour = hour
        self.valence = valence
        self.energy = energy
        self.emoji = emoji
        self.label = label
    }

    public var timeLabel: String {
        if hour == 0 { return "12am" }
        if hour == 12 { return "12pm" }
        if hour < 12 { return "\(hour)am" }
        return "\(hour - 12)pm"
    }

    /// Whether this hour was a highlight (high positive valence)
    public var isHighlight: Bool { valence >= 0.5 }
}

// MARK: - Daily Mood

public struct DailyMood: Identifiable, Codable, Sendable {
    public let id: UUID
    public let date: Date
    public let averageValence: Double
    public let averageEnergy: Double
    public let dominantEmoji: String

    public init(
        id: UUID = UUID(),
        date: Date,
        averageValence: Double,
        averageEnergy: Double,
        dominantEmoji: String
    ) {
        self.id = id
        self.date = date
        self.averageValence = averageValence
        self.averageEnergy = averageEnergy
        self.dominantEmoji = dominantEmoji
    }

    public var dayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}

// MARK: - Daily Meditation

public struct DailyMeditation: Identifiable, Codable, Sendable {
    public let id: UUID
    public let dayOfWeek: String
    public let minutes: Int
    public let date: Date
    public let goalMinutes: Int
    public let isToday: Bool

    public init(
        id: UUID = UUID(),
        dayOfWeek: String,
        minutes: Int,
        date: Date = Date(),
        goalMinutes: Int = 15,
        isToday: Bool = false
    ) {
        self.id = id
        self.dayOfWeek = dayOfWeek
        self.minutes = minutes
        self.date = date
        self.goalMinutes = goalMinutes
        self.isToday = isToday
    }

    /// Alias for dayOfWeek
    public var dayLabel: String { dayOfWeek }

    /// Whether the goal was completed
    public var completedGoal: Bool { minutes >= goalMinutes }

    public var formattedTime: String {
        if minutes == 0 { return "--" }
        return "\(minutes)"
    }
}

// MARK: - Reflection Theme

public struct ReflectionTheme: Identifiable, Codable, Sendable {
    public let id: UUID
    public let name: String
    public let mentionCount: Int
    public let weeklyChange: Int
    public let trend: TrendDirection
    public let colorHex: String
    public let relatedKeywords: [String]
    public let lastMentioned: Date

    public init(
        id: UUID = UUID(),
        name: String,
        mentionCount: Int,
        weeklyChange: Int,
        trend: TrendDirection,
        colorHex: String,
        relatedKeywords: [String],
        lastMentioned: Date
    ) {
        self.id = id
        self.name = name
        self.mentionCount = mentionCount
        self.weeklyChange = weeklyChange
        self.trend = trend
        self.colorHex = colorHex
        self.relatedKeywords = relatedKeywords
        self.lastMentioned = lastMentioned
    }

    public var changeLabel: String {
        if weeklyChange > 0 { return "+\(weeklyChange) this week" }
        if weeklyChange < 0 { return "\(weeklyChange) this week" }
        return "stable"
    }

    /// Alias for mentionCount (frequency of theme occurrence)
    public var frequency: Int { mentionCount }

    /// Growth rate based on weekly change relative to mention count
    public var growthRate: Double {
        guard mentionCount > 0 else { return 0 }
        return Double(weeklyChange) / Double(mentionCount)
    }

    /// Alias for lastMentioned (when theme was last seen)
    public var lastSeen: Date { lastMentioned }

    /// First seen date (estimated from mention count and weekly change)
    public var firstSeen: Date {
        // Estimate first seen based on total mentions and average weekly mentions
        let weeksBack = mentionCount / max(1, abs(weeklyChange) + 1)
        return Calendar.current.date(byAdding: .weekOfYear, value: -weeksBack, to: lastMentioned) ?? lastMentioned
    }
}

// MARK: - Theme History

public struct ThemeHistory: Identifiable, Codable, Sendable {
    public let id: UUID
    public let themeName: String
    public let weeklyData: [Int]

    public init(
        id: UUID = UUID(),
        themeName: String,
        weeklyData: [Int]
    ) {
        self.id = id
        self.themeName = themeName
        self.weeklyData = weeklyData
    }
}

// MARK: - Emerging Theme

public struct EmergingTheme: Identifiable, Codable, Sendable {
    public let id: UUID
    public let name: String
    public let mentionsThisWeek: Int
    public let description: String

    public init(
        id: UUID = UUID(),
        name: String,
        mentionsThisWeek: Int,
        description: String
    ) {
        self.id = id
        self.name = name
        self.mentionsThisWeek = mentionsThisWeek
        self.description = description
    }
}

// MARK: - Insight Journey Step

public struct InsightJourneyStep: Identifiable, Codable, Sendable {
    public let id: UUID
    public let date: Date
    public let description: String
    public let entryID: UUID?
    public let isBreakthrough: Bool

    public init(
        id: UUID = UUID(),
        date: Date,
        description: String,
        entryID: UUID? = nil,
        isBreakthrough: Bool = false
    ) {
        self.id = id
        self.date = date
        self.description = description
        self.entryID = entryID
        self.isBreakthrough = isBreakthrough
    }

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    /// Alias for date
    public var timestamp: Date { date }

    /// Content (alias for description)
    public var content: String { description }

    /// Type derived from isBreakthrough
    public var type: String {
        if isBreakthrough { return "insight" }
        return "observation"
    }
}

// MARK: - Dimension Link

public struct DimensionLink: Identifiable, Codable, Sendable {
    public let id: UUID
    public let dimensionName: String
    public let description: String
    public let strength: Double

    public init(
        id: UUID = UUID(),
        dimensionName: String,
        description: String,
        strength: Double
    ) {
        self.id = id
        self.dimensionName = dimensionName
        self.description = description
        self.strength = min(1, max(0, strength))
    }

    /// Alias for dimensionName
    public var dimension: String { dimensionName }

    /// Alias for description
    public var connection: String { description }
}

// MARK: - Grail Insight

public struct GrailInsight: Identifiable, Codable, Sendable {
    public let id: UUID
    public let content: String
    public let discoveredDate: Date
    public let sourceEntryID: UUID
    public let sourceEntryTitle: String
    public let sourceWordCount: Int
    public let journey: [InsightJourneyStep]
    public let crossDimensionLinks: [DimensionLink]
    public let isPinned: Bool
    public let tags: [String]

    public init(
        id: UUID = UUID(),
        content: String,
        discoveredDate: Date,
        sourceEntryID: UUID,
        sourceEntryTitle: String,
        sourceWordCount: Int,
        journey: [InsightJourneyStep],
        crossDimensionLinks: [DimensionLink],
        isPinned: Bool = false,
        tags: [String] = []
    ) {
        self.id = id
        self.content = content
        self.discoveredDate = discoveredDate
        self.sourceEntryID = sourceEntryID
        self.sourceEntryTitle = sourceEntryTitle
        self.sourceWordCount = sourceWordCount
        self.journey = journey
        self.crossDimensionLinks = crossDimensionLinks
        self.isPinned = isPinned
        self.tags = tags
    }

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: discoveredDate)
    }

    public var preview: String {
        if content.count <= 80 { return content }
        return String(content.prefix(80)) + "..."
    }

    /// Alias for discoveredDate
    public var discoveredAt: Date { discoveredDate }

    /// Alias for content
    public var insight: String { content }

    /// Alias for crossDimensionLinks
    public var dimensionLinks: [DimensionLink] { crossDimensionLinks }

    /// Source type (derived from source entry title)
    public var sourceType: String { "Journal Entry" }
}

// MARK: - Insight Pattern

public struct InsightPattern: Identifiable, Codable, Sendable {
    public let id: UUID
    public let description: String
    public let conditions: [String]
    public let confidence: Double

    public init(
        id: UUID = UUID(),
        description: String,
        conditions: [String],
        confidence: Double
    ) {
        self.id = id
        self.description = description
        self.conditions = conditions
        self.confidence = min(1, max(0, confidence))
    }
}

// MARK: - Reflection Prediction

public struct ReflectionPrediction: Identifiable, Codable, Sendable {
    public let id: UUID
    public let condition: String
    public let prediction: String
    public let patternEmerging: String?
    public let confidence: Double
    public let actions: [String]

    public init(
        id: UUID = UUID(),
        condition: String,
        prediction: String,
        patternEmerging: String? = nil,
        confidence: Double,
        actions: [String]
    ) {
        self.id = id
        self.condition = condition
        self.prediction = prediction
        self.patternEmerging = patternEmerging
        self.confidence = min(1, max(0, confidence))
        self.actions = actions
    }

    /// Timeframe for the prediction
    public var timeframe: String {
        if confidence > 0.7 { return "This week" }
        if confidence > 0.4 { return "Soon" }
        return "Eventually"
    }
}

// MARK: - Reflection Dimension Data

public struct ReflectionDimensionData: Codable, Sendable {
    // Emotional Landscape
    public let emotionalDataPoints: [EmotionalDataPoint]
    public let todayMood: EmotionalState
    public let averageValence: Double
    public let averageEnergy: Double
    public let valenceTrend: TrendDirection
    public let moodTimeline: [HourlyMood]
    public let weeklyMoodData: [DailyMood]

    // Journaling
    public let journalStreak: Int
    public let journalPersonalBest: Int
    public let wordsToday: Int
    public let wordsAverage: Int
    public let depthScore: Double
    public let todayEntryPreview: String
    public let todayEntryWordCount: Int

    // Meditation
    public let meditationToday: Int // minutes
    public let meditationGoal: Int
    public let meditationThisWeek: Int
    public let meditationWeekData: [DailyMeditation]
    public let meditationStreak: Int
    public let averageSessionLength: Int

    // Themes
    public let recurringThemes: [ReflectionTheme]
    public let themeEvolution: [ThemeHistory]
    public let emergingThemes: [EmergingTheme]

    // Grail Insights
    public let grailInsights: [GrailInsight]
    public let totalGrails: Int
    public let grailsThisMonth: Int
    public let pinnedGrails: [GrailInsight]

    // Predictions
    public let predictions: [ReflectionPrediction]
    public let insightPatterns: [InsightPattern]

    public init(
        emotionalDataPoints: [EmotionalDataPoint],
        todayMood: EmotionalState,
        averageValence: Double,
        averageEnergy: Double,
        valenceTrend: TrendDirection,
        moodTimeline: [HourlyMood],
        weeklyMoodData: [DailyMood],
        journalStreak: Int,
        journalPersonalBest: Int,
        wordsToday: Int,
        wordsAverage: Int,
        depthScore: Double,
        todayEntryPreview: String,
        todayEntryWordCount: Int,
        meditationToday: Int,
        meditationGoal: Int,
        meditationThisWeek: Int,
        meditationWeekData: [DailyMeditation],
        meditationStreak: Int,
        averageSessionLength: Int,
        recurringThemes: [ReflectionTheme],
        themeEvolution: [ThemeHistory],
        emergingThemes: [EmergingTheme],
        grailInsights: [GrailInsight],
        totalGrails: Int,
        grailsThisMonth: Int,
        pinnedGrails: [GrailInsight],
        predictions: [ReflectionPrediction],
        insightPatterns: [InsightPattern]
    ) {
        self.emotionalDataPoints = emotionalDataPoints
        self.todayMood = todayMood
        self.averageValence = averageValence
        self.averageEnergy = averageEnergy
        self.valenceTrend = valenceTrend
        self.moodTimeline = moodTimeline
        self.weeklyMoodData = weeklyMoodData
        self.journalStreak = journalStreak
        self.journalPersonalBest = journalPersonalBest
        self.wordsToday = wordsToday
        self.wordsAverage = wordsAverage
        self.depthScore = depthScore
        self.todayEntryPreview = todayEntryPreview
        self.todayEntryWordCount = todayEntryWordCount
        self.meditationToday = meditationToday
        self.meditationGoal = meditationGoal
        self.meditationThisWeek = meditationThisWeek
        self.meditationWeekData = meditationWeekData
        self.meditationStreak = meditationStreak
        self.averageSessionLength = averageSessionLength
        self.recurringThemes = recurringThemes
        self.themeEvolution = themeEvolution
        self.emergingThemes = emergingThemes
        self.grailInsights = grailInsights
        self.totalGrails = totalGrails
        self.grailsThisMonth = grailsThisMonth
        self.pinnedGrails = pinnedGrails
        self.predictions = predictions
        self.insightPatterns = insightPatterns
    }

    // MARK: - Computed Properties

    /// Alias for recurringThemes for convenience
    public var themes: [ReflectionTheme] { recurringThemes }

    public var latestGrail: GrailInsight? {
        grailInsights.sorted { $0.discoveredDate > $1.discoveredDate }.first
    }

    public var meditationProgress: Double {
        guard meditationGoal > 0 else { return 0 }
        return min(1, Double(meditationToday) / Double(meditationGoal))
    }

    public var journalWordProgress: Double {
        guard wordsAverage > 0 else { return 0 }
        return Double(wordsToday) / Double(wordsAverage)
    }

    public var wordPercentVsAverage: Int {
        guard wordsAverage > 0 else { return 0 }
        return Int(((Double(wordsToday) / Double(wordsAverage)) - 1) * 100)
    }

    /// Alias for todayMood
    public var currentEmotionalState: EmotionalState { todayMood }

    /// Week average emotional state
    public var weekAverageState: EmotionalState {
        EmotionalState(
            valence: averageValence,
            energy: averageEnergy,
            description: "Week Average",
            emoji: "📊",
            comparedToAverage: "same"
        )
    }

    /// Alias for journalStreak
    public var journalingStreak: Int { journalStreak }

    /// Alias for journalPersonalBest
    public var longestJournalingStreak: Int { journalPersonalBest }

    /// Alias for wordsToday
    public var todayWordCount: Int { wordsToday }

    /// Alias for wordsAverage
    public var averageWordCount: Int { wordsAverage }

    /// Alias for depthScore
    public var todayDepthScore: Double { depthScore }

    /// Journaling consistency (computed from streak / 30 days)
    public var journalingConsistency: Double { min(1.0, Double(journalStreak) / 30.0) }

    /// Alias for meditationToday
    public var todayMeditationMinutes: Int { meditationToday }

    /// Alias for meditationGoal
    public var meditationGoalMinutes: Int { meditationGoal }

    /// Total meditation sessions (estimated)
    public var totalMeditationSessions: Int { meditationStreak * 7 }

    /// Alias for meditationThisWeek
    public var totalMeditationMinutes: Int { meditationThisWeek }

    /// Alias for meditationWeekData
    public var weeklyMeditationData: [DailyMeditation] { meditationWeekData }

    /// Preferred meditation time (computed from averageSessionLength)
    public var preferredMeditationTime: String {
        if averageSessionLength < 10 { return "Morning" }
        return "Evening"
    }

    /// Alias for valenceTrend
    public var emotionalTrend: TrendDirection { valenceTrend }

    /// Alias for moodTimeline
    public var todayMoodTimeline: [HourlyMood] { moodTimeline }

    /// Alias for totalGrails
    public var totalGrailInsights: Int { totalGrails }
}

// MARK: - Empty Factory

extension ReflectionDimensionData {
    public var isEmpty: Bool {
        journalStreak == 0 && emotionalDataPoints.isEmpty && totalGrails == 0
    }

    public static var empty: ReflectionDimensionData {
        ReflectionDimensionData(
            emotionalDataPoints: [],
            todayMood: EmotionalState(valence: 0, energy: 0, description: "No data yet", emoji: "🔘", comparedToAverage: "N/A"),
            averageValence: 0,
            averageEnergy: 0,
            valenceTrend: .stable,
            moodTimeline: [],
            weeklyMoodData: [],
            journalStreak: 0,
            journalPersonalBest: 0,
            wordsToday: 0,
            wordsAverage: 0,
            depthScore: 0,
            todayEntryPreview: "",
            todayEntryWordCount: 0,
            meditationToday: 0,
            meditationGoal: 15,
            meditationThisWeek: 0,
            meditationWeekData: [],
            meditationStreak: 0,
            averageSessionLength: 0,
            recurringThemes: [],
            themeEvolution: [],
            emergingThemes: [],
            grailInsights: [],
            totalGrails: 0,
            grailsThisMonth: 0,
            pinnedGrails: [],
            predictions: [],
            insightPatterns: []
        )
    }
}

// MARK: - Preview Data

#if DEBUG
extension ReflectionDimensionData {
    public static var preview: ReflectionDimensionData {
        let now = Date()
        let calendar = Calendar.current

        // Emotional data points (for landscape)
        let emotionalDataPoints: [EmotionalDataPoint] = [
            EmotionalDataPoint(timestamp: calendar.date(byAdding: .day, value: -6, to: now)!, valence: -0.3, energy: 0.2, emoji: "😤", source: .journal),
            EmotionalDataPoint(timestamp: calendar.date(byAdding: .day, value: -5, to: now)!, valence: 0.4, energy: 0.6, emoji: "😊", source: .manual),
            EmotionalDataPoint(timestamp: calendar.date(byAdding: .day, value: -4, to: now)!, valence: -0.5, energy: 0.1, emoji: "😔", source: .journal),
            EmotionalDataPoint(timestamp: calendar.date(byAdding: .day, value: -3, to: now)!, valence: 0.2, energy: -0.2, emoji: "😌", source: .manual),
            EmotionalDataPoint(timestamp: calendar.date(byAdding: .day, value: -2, to: now)!, valence: 0.5, energy: 0.3, emoji: "😊", source: .journal),
            EmotionalDataPoint(timestamp: calendar.date(byAdding: .day, value: -1, to: now)!, valence: 0.7, energy: 0.8, emoji: "😄", source: .manual),
            EmotionalDataPoint(timestamp: now, valence: 0.6, energy: 0.5, emoji: "😌", note: "Feeling calm and positive", source: .manual)
        ]

        // Today's mood
        let todayMood = EmotionalState(
            valence: 0.6,
            energy: 0.5,
            description: "Positive & Calm",
            emoji: "😌",
            comparedToAverage: "Better than usual"
        )

        // Mood timeline
        let moodTimeline: [HourlyMood] = [
            HourlyMood(hour: 6, valence: -0.2, energy: -0.5, emoji: "😴", label: "low"),
            HourlyMood(hour: 8, valence: 0.1, energy: 0.0, emoji: "😐", label: "rising"),
            HourlyMood(hour: 10, valence: 0.5, energy: 0.4, emoji: "😊", label: "good"),
            HourlyMood(hour: 12, valence: 0.8, energy: 0.7, emoji: "😄", label: "peak"),
            HourlyMood(hour: 14, valence: 0.4, energy: 0.2, emoji: "😌", label: "calm"),
            HourlyMood(hour: 16, valence: 0.5, energy: 0.3, emoji: "😊", label: "good"),
            HourlyMood(hour: 18, valence: 0.3, energy: 0.0, emoji: "😌", label: "relax"),
            HourlyMood(hour: 20, valence: 0.6, energy: 0.5, emoji: "😌", label: "now")
        ]

        // Meditation week data
        let meditationWeekData: [DailyMeditation] = [
            DailyMeditation(dayOfWeek: "M", minutes: 15),
            DailyMeditation(dayOfWeek: "T", minutes: 10),
            DailyMeditation(dayOfWeek: "W", minutes: 18),
            DailyMeditation(dayOfWeek: "T", minutes: 22),
            DailyMeditation(dayOfWeek: "F", minutes: 12),
            DailyMeditation(dayOfWeek: "S", minutes: 0),
            DailyMeditation(dayOfWeek: "S", minutes: 0)
        ]

        // Recurring themes
        let themes: [ReflectionTheme] = [
            ReflectionTheme(name: "PURPOSE", mentionCount: 47, weeklyChange: 12, trend: .improving, colorHex: "#EC4899", relatedKeywords: ["meaning", "mission", "calling"], lastMentioned: now),
            ReflectionTheme(name: "GROWTH", mentionCount: 38, weeklyChange: 0, trend: .stable, colorHex: "#10B981", relatedKeywords: ["learning", "progress", "development"], lastMentioned: now),
            ReflectionTheme(name: "BALANCE", mentionCount: 31, weeklyChange: 8, trend: .improving, colorHex: "#3B82F6", relatedKeywords: ["harmony", "equilibrium", "peace"], lastMentioned: now),
            ReflectionTheme(name: "CREATION", mentionCount: 24, weeklyChange: -5, trend: .declining, colorHex: "#F59E0B", relatedKeywords: ["making", "building", "art"], lastMentioned: calendar.date(byAdding: .day, value: -2, to: now)!)
        ]

        // Emerging theme
        let emergingThemes: [EmergingTheme] = [
            EmergingTheme(name: "Intentional Rest", mentionsThisWeek: 6, description: "New pattern detected")
        ]

        // Grail insights
        let grailJourney: [InsightJourneyStep] = [
            InsightJourneyStep(date: calendar.date(byAdding: .day, value: -3, to: now)!, description: "Noticed frustration when team missed deadline"),
            InsightJourneyStep(date: calendar.date(byAdding: .day, value: -2, to: now)!, description: "Journaled about \"needing to do everything myself\""),
            InsightJourneyStep(date: calendar.date(byAdding: .day, value: -1, to: now)!, description: "Connected this to childhood responsibility patterns"),
            InsightJourneyStep(date: now, description: "BREAKTHROUGH - Realized control = anxiety management", isBreakthrough: true)
        ]

        let dimensionLinks: [DimensionLink] = [
            DimensionLink(dimensionName: "Behavioral", description: "Delegation tasks avoided (pattern detected)", strength: 0.78),
            DimensionLink(dimensionName: "Cognitive", description: "Focus drops when team tasks pending", strength: 0.65),
            DimensionLink(dimensionName: "Physiological", description: "HRV lower on days with pending delegations", strength: 0.72)
        ]

        let grailInsights: [GrailInsight] = [
            GrailInsight(
                content: "I realized my resistance to delegation stems from a fear of losing control, not from distrust of others. The control itself is an illusion I use to manage anxiety about outcomes I can't predict.",
                discoveredDate: now,
                sourceEntryID: UUID(),
                sourceEntryTitle: "Morning Reflection - Work Anxiety",
                sourceWordCount: 1247,
                journey: grailJourney,
                crossDimensionLinks: dimensionLinks,
                isPinned: true,
                tags: ["control", "anxiety", "delegation"]
            ),
            GrailInsight(
                content: "Purpose isn't found, it's cultivated through consistent action aligned with values.",
                discoveredDate: calendar.date(byAdding: .day, value: -6, to: now)!,
                sourceEntryID: UUID(),
                sourceEntryTitle: "Weekly Reflection",
                sourceWordCount: 892,
                journey: [],
                crossDimensionLinks: [],
                tags: ["purpose", "values"]
            ),
            GrailInsight(
                content: "My creative blocks mirror my sleep patterns - they're symptoms, not causes.",
                discoveredDate: calendar.date(byAdding: .day, value: -20, to: now)!,
                sourceEntryID: UUID(),
                sourceEntryTitle: "Late Night Thoughts",
                sourceWordCount: 654,
                journey: [],
                crossDimensionLinks: [],
                tags: ["creativity", "sleep"]
            )
        ]

        // Predictions
        let predictions: [ReflectionPrediction] = [
            ReflectionPrediction(
                condition: "You maintain journaling streak for 5 more days",
                prediction: "Journal Streak badge \"Deep Diver\" unlocks (+200 XP), depth score projected +0.5",
                patternEmerging: "Your most insightful entries happen on mornings after 7+ hours sleep",
                confidence: 0.74,
                actions: ["Open Journal", "Start Meditation", "Emotional Analytics"]
            )
        ]

        // Insight patterns
        let insightPatterns: [InsightPattern] = [
            InsightPattern(description: "Breakthroughs occur after 3+ consecutive journal days", conditions: ["7+ hours sleep", "Morning entry", "400+ words"], confidence: 0.82)
        ]

        return ReflectionDimensionData(
            emotionalDataPoints: emotionalDataPoints,
            todayMood: todayMood,
            averageValence: 0.4,
            averageEnergy: 0.3,
            valenceTrend: .improving,
            moodTimeline: moodTimeline,
            weeklyMoodData: [],
            journalStreak: 18,
            journalPersonalBest: 23,
            wordsToday: 847,
            wordsAverage: 632,
            depthScore: 7.8,
            todayEntryPreview: "Today I felt a shift in my approach to creative work. Instead of forcing output, I...",
            todayEntryWordCount: 847,
            meditationToday: 12,
            meditationGoal: 15,
            meditationThisWeek: 84,
            meditationWeekData: meditationWeekData,
            meditationStreak: 5,
            averageSessionLength: 14,
            recurringThemes: themes,
            themeEvolution: [],
            emergingThemes: emergingThemes,
            grailInsights: grailInsights,
            totalGrails: 12,
            grailsThisMonth: 3,
            pinnedGrails: grailInsights.filter { $0.isPinned },
            predictions: predictions,
            insightPatterns: insightPatterns
        )
    }
}
#endif
