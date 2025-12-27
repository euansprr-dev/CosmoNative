// CosmoOS/Voice/Pipeline/InsightExtractor.swift
// Extracts patterns and insights from journal entries and activity data

import Foundation
import NaturalLanguage
import GRDB

// MARK: - Insight Types

/// Types of pattern insights that can be extracted from analytics
enum PatternInsightCategory: String, Codable, Sendable {
    case pattern = "pattern"             // Recurring patterns in behavior/mood
    case correlation = "correlation"     // Correlations between activities
    case streak = "streak"               // Streak observations
    case productivity = "productivity"   // Productivity patterns
    case emotion = "emotion"             // Emotional patterns
    case growth = "growth"               // Growth and progress
    case suggestion = "suggestion"       // Actionable suggestions
    case milestone = "milestone"         // Milestone achievements
}

/// Confidence level for insights
enum PatternInsightConfidence: String, Codable, Sendable {
    case high = "high"       // > 0.8
    case medium = "medium"   // 0.5 - 0.8
    case low = "low"         // < 0.5
}

// MARK: - Insight Model

/// An extracted pattern insight from user data
struct PatternInsight: Codable, Sendable, Identifiable {
    let id: UUID
    let type: PatternInsightCategory
    let title: String
    let description: String
    let confidence: PatternInsightConfidence
    let evidenceCount: Int
    let relatedTopics: [String]
    let suggestedAction: String?
    let dimension: String?
    let createdAt: Date

    init(
        type: PatternInsightCategory,
        title: String,
        description: String,
        confidence: PatternInsightConfidence,
        evidenceCount: Int = 1,
        relatedTopics: [String] = [],
        suggestedAction: String? = nil,
        dimension: String? = nil
    ) {
        self.id = UUID()
        self.type = type
        self.title = title
        self.description = description
        self.confidence = confidence
        self.evidenceCount = evidenceCount
        self.relatedTopics = relatedTopics
        self.suggestedAction = suggestedAction
        self.dimension = dimension
        self.createdAt = Date()
    }
}

// MARK: - Insight Extractor

/// Extracts insights from journal entries and user activity data.
/// Uses pattern recognition and NLP to identify trends.
actor InsightExtractor {
    static let shared = InsightExtractor()

    // Cache recent insights to avoid duplicates
    private var recentInsights: [PatternInsight] = []
    private let maxCachedInsights = 50

    // MARK: - Journal Analysis

    /// Analyze recent journal entries for patterns
    func analyzeJournalEntries(
        entries: [Atom],
        timeRange: TimeRange = .week
    ) async -> [PatternInsight] {
        var insights: [PatternInsight] = []

        // 1. Mood pattern analysis
        if let moodInsight = analyzeMoodPatterns(entries: entries) {
            insights.append(moodInsight)
        }

        // 2. Topic frequency analysis
        let topicInsights = analyzeTopicFrequency(entries: entries)
        insights.append(contentsOf: topicInsights)

        // 3. Time of day patterns
        if let timeInsight = analyzeTimePatterns(entries: entries) {
            insights.append(timeInsight)
        }

        // 4. Sentiment trends
        if let sentimentInsight = analyzeSentimentTrend(entries: entries) {
            insights.append(sentimentInsight)
        }

        // 5. Consistency patterns
        if let consistencyInsight = analyzeConsistencyPatterns(entries: entries) {
            insights.append(consistencyInsight)
        }

        // Cache and dedupe
        let newInsights = deduplicateInsights(insights)
        cacheInsights(newInsights)

        return newInsights
    }

    /// Analyze mood patterns from journal entries
    private func analyzeMoodPatterns(entries: [Atom]) -> PatternInsight? {
        let dateFormatter = ISO8601DateFormatter()
        let moodEntries = entries.compactMap { entry -> (Date, MoodCategory)? in
            guard let metadata = entry.metadata,
                  let data = metadata.data(using: .utf8),
                  let journalMeta = try? JSONDecoder().decode(JournalEntryMetadata.self, from: data),
                  let mood = journalMeta.mood,
                  let date = dateFormatter.date(from: entry.createdAt) else {
                return nil
            }
            return (date, mood)
        }

        guard moodEntries.count >= 3 else { return nil }

        // Count mood frequencies
        var moodCounts: [MoodCategory: Int] = [:]
        for (_, mood) in moodEntries {
            moodCounts[mood, default: 0] += 1
        }

        let total = Double(moodEntries.count)
        let (dominantMood, count) = moodCounts.max(by: { $0.value < $1.value }) ?? (.neutral, 0)
        let percentage = Int((Double(count) / total) * 100)

        if percentage >= 60 {
            let moodDescription: String
            let suggestion: String

            switch dominantMood {
            case .positive:
                moodDescription = "You've been in a positive mood \(percentage)% of the time this week. Great energy!"
                suggestion = "Consider journaling about what's contributing to this positive state."
            case .negative:
                moodDescription = "You've logged some challenging emotions lately (\(percentage)% of entries). Remember it's okay to have tough days."
                suggestion = "Consider adding gratitude entries or taking breaks to reset."
            case .neutral:
                moodDescription = "Your mood has been steady and neutral most of the time (\(percentage)%)."
                suggestion = "Try exploring what activities bring you joy or energy."
            case .mixed:
                moodDescription = "You've experienced a mix of emotions (\(percentage)% mixed entries)."
                suggestion = "Consider tracking specific triggers for different moods."
            }

            return PatternInsight(
                type: .emotion,
                title: "Mood Pattern: \(dominantMood.rawValue.capitalized)",
                description: moodDescription,
                confidence: percentage >= 70 ? .high : .medium,
                evidenceCount: count,
                suggestedAction: suggestion,
                dimension: "reflection"
            )
        }

        return nil
    }

    /// Analyze topic frequency
    private func analyzeTopicFrequency(entries: [Atom]) -> [PatternInsight] {
        var topicCounts: [String: Int] = [:]

        for entry in entries {
            guard let metadata = entry.metadata,
                  let data = metadata.data(using: .utf8),
                  let journalMeta = try? JSONDecoder().decode(JournalEntryMetadata.self, from: data) else {
                continue
            }

            if let topics = journalMeta.topics {
                for topic in topics {
                    topicCounts[topic, default: 0] += 1
                }
            }
        }

        // Find topics that appear frequently
        let frequentTopics = topicCounts.filter { $0.value >= 3 }
            .sorted { $0.value > $1.value }
            .prefix(3)

        return frequentTopics.map { topic, count in
            PatternInsight(
                type: .pattern,
                title: "Recurring Topic: \(topic.capitalized)",
                description: "You've mentioned '\(topic)' in \(count) entries recently. This seems to be on your mind.",
                confidence: count >= 5 ? .high : .medium,
                evidenceCount: count,
                relatedTopics: [topic],
                suggestedAction: "Consider dedicating focused time to explore this topic.",
                dimension: "knowledge"
            )
        }
    }

    /// Analyze time of day patterns
    private func analyzeTimePatterns(entries: [Atom]) -> PatternInsight? {
        let calendar = Calendar.current
        let dateFormatter = ISO8601DateFormatter()

        var timeSlotCounts: [String: Int] = [
            "morning": 0,    // 5-11
            "afternoon": 0,  // 12-16
            "evening": 0,    // 17-20
            "night": 0       // 21-4
        ]

        for entry in entries {
            guard let date = dateFormatter.date(from: entry.createdAt) else { continue }
            let hour = calendar.component(.hour, from: date)

            switch hour {
            case 5..<12:
                timeSlotCounts["morning", default: 0] += 1
            case 12..<17:
                timeSlotCounts["afternoon", default: 0] += 1
            case 17..<21:
                timeSlotCounts["evening", default: 0] += 1
            default:
                timeSlotCounts["night", default: 0] += 1
            }
        }

        guard let (peakTime, count) = timeSlotCounts.max(by: { $0.value < $1.value }),
              count >= 3 else {
            return nil
        }

        let percentage = Int((Double(count) / Double(entries.count)) * 100)

        return PatternInsight(
            type: .productivity,
            title: "Peak Journaling Time: \(peakTime.capitalized)",
            description: "\(percentage)% of your journal entries are in the \(peakTime). This seems to be your reflective time.",
            confidence: percentage >= 50 ? .high : .medium,
            evidenceCount: count,
            suggestedAction: "Consider scheduling important reflection during your \(peakTime) time.",
            dimension: "behavioral"
        )
    }

    /// Analyze sentiment trend over time
    private func analyzeSentimentTrend(entries: [Atom]) -> PatternInsight? {
        let sortedEntries = entries.sorted { $0.createdAt < $1.createdAt }

        guard sortedEntries.count >= 5 else { return nil }

        let sentiments = sortedEntries.compactMap { entry -> Double? in
            guard let metadata = entry.metadata,
                  let data = metadata.data(using: .utf8),
                  let journalMeta = try? JSONDecoder().decode(JournalEntryMetadata.self, from: data) else {
                return nil
            }
            return journalMeta.sentiment
        }

        guard sentiments.count >= 5 else { return nil }

        // Compare first half to second half
        let mid = sentiments.count / 2
        let firstHalf = sentiments[..<mid]
        let secondHalf = sentiments[mid...]

        let firstAvg = firstHalf.reduce(0, +) / Double(firstHalf.count)
        let secondAvg = secondHalf.reduce(0, +) / Double(secondHalf.count)

        let change = secondAvg - firstAvg

        if abs(change) >= 0.2 {
            let trend = change > 0 ? "improving" : "declining"
            let emoji = change > 0 ? "upward" : "needs attention"

            return PatternInsight(
                type: .emotion,
                title: "Sentiment Trend: \(emoji.capitalized)",
                description: "Your overall sentiment has been \(trend) over the past week. The shift is about \(Int(abs(change) * 100))%.",
                confidence: abs(change) >= 0.3 ? .high : .medium,
                evidenceCount: sentiments.count,
                suggestedAction: change < 0 ? "Consider what's contributing to this shift. Any changes you'd like to make?" : "Great progress! What's been working well?",
                dimension: "reflection"
            )
        }

        return nil
    }

    /// Analyze consistency patterns
    private func analyzeConsistencyPatterns(entries: [Atom]) -> PatternInsight? {
        let calendar = Calendar.current
        let dateFormatter = ISO8601DateFormatter()

        // Group entries by day
        var entriesByDay: [Date: Int] = [:]
        for entry in entries {
            guard let date = dateFormatter.date(from: entry.createdAt) else { continue }
            let day = calendar.startOfDay(for: date)
            entriesByDay[day, default: 0] += 1
        }

        let daysWithEntries = entriesByDay.count
        let totalDays = 7 // Assuming weekly analysis

        if daysWithEntries >= 5 {
            return PatternInsight(
                type: .streak,
                title: "Strong Journaling Habit",
                description: "You journaled on \(daysWithEntries) out of \(totalDays) days this week. Excellent consistency!",
                confidence: .high,
                evidenceCount: daysWithEntries,
                suggestedAction: "Keep it up! Your reflection practice is building momentum.",
                dimension: "behavioral"
            )
        } else if daysWithEntries <= 2 {
            return PatternInsight(
                type: .suggestion,
                title: "Journaling Opportunity",
                description: "You only journaled on \(daysWithEntries) days this week. Even brief entries help build the habit.",
                confidence: .medium,
                evidenceCount: daysWithEntries,
                suggestedAction: "Try setting a daily reminder for quick 1-minute check-ins.",
                dimension: "behavioral"
            )
        }

        return nil
    }

    // MARK: - Activity Analysis

    /// Analyze productivity patterns from activity data
    fileprivate func analyzeProductivity(
        focusSessions: [AnalyticsFocusData],
        tasks: [TaskData]
    ) async -> [PatternInsight] {
        var insights: [PatternInsight] = []

        // 1. Focus session patterns
        if let focusInsight = analyzeFocusPatterns(sessions: focusSessions) {
            insights.append(focusInsight)
        }

        // 2. Task completion patterns
        if let taskInsight = analyzeTaskPatterns(tasks: tasks) {
            insights.append(taskInsight)
        }

        // 3. Focus-productivity correlation
        if let correlationInsight = analyzeCorrelation(focus: focusSessions, tasks: tasks) {
            insights.append(correlationInsight)
        }

        return deduplicateInsights(insights)
    }

    private func analyzeFocusPatterns(sessions: [AnalyticsFocusData]) -> PatternInsight? {
        guard sessions.count >= 3 else { return nil }

        let totalMinutes = sessions.reduce(0) { $0 + $1.durationMinutes }
        let avgDuration = totalMinutes / sessions.count

        if avgDuration >= 45 {
            return PatternInsight(
                type: .productivity,
                title: "Deep Focus Achiever",
                description: "Your average focus session is \(avgDuration) minutes. You're building strong deep work capacity!",
                confidence: .high,
                evidenceCount: sessions.count,
                suggestedAction: "Consider extending to 90-minute sessions for even deeper work.",
                dimension: "cognitive"
            )
        } else if avgDuration < 25 {
            return PatternInsight(
                type: .suggestion,
                title: "Focus Building Opportunity",
                description: "Your focus sessions average \(avgDuration) minutes. Longer sessions can boost productivity.",
                confidence: .medium,
                evidenceCount: sessions.count,
                suggestedAction: "Try the Pomodoro technique: 25 minutes of focused work, then a 5-minute break.",
                dimension: "cognitive"
            )
        }

        return nil
    }

    private func analyzeTaskPatterns(tasks: [TaskData]) -> PatternInsight? {
        guard tasks.count >= 5 else { return nil }

        let completedTasks = tasks.filter { $0.isCompleted }
        let completionRate = Double(completedTasks.count) / Double(tasks.count)

        if completionRate >= 0.8 {
            return PatternInsight(
                type: .productivity,
                title: "High Completion Rate",
                description: "You completed \(Int(completionRate * 100))% of your tasks this week. Excellent execution!",
                confidence: .high,
                evidenceCount: completedTasks.count,
                suggestedAction: "Consider taking on more challenging tasks to grow.",
                dimension: "behavioral"
            )
        } else if completionRate < 0.5 {
            return PatternInsight(
                type: .suggestion,
                title: "Task Management Tip",
                description: "Your completion rate is \(Int(completionRate * 100))%. Consider breaking tasks into smaller steps.",
                confidence: .medium,
                evidenceCount: tasks.count,
                suggestedAction: "Try the 2-minute rule: if it takes less than 2 minutes, do it now.",
                dimension: "behavioral"
            )
        }

        return nil
    }

    private func analyzeCorrelation(focus: [AnalyticsFocusData], tasks: [TaskData]) -> PatternInsight? {
        guard focus.count >= 3, tasks.count >= 3 else { return nil }

        let focusMinutes = focus.reduce(0) { $0 + $1.durationMinutes }
        let completedTasks = tasks.filter { $0.isCompleted }.count

        // Simple correlation check
        if focusMinutes > 120 && completedTasks > 5 {
            return PatternInsight(
                type: .correlation,
                title: "Focus-Productivity Link",
                description: "When you log more focus time (\(focusMinutes)min), you complete more tasks (\(completedTasks)). There's a strong correlation!",
                confidence: .medium,
                evidenceCount: focus.count + tasks.count,
                suggestedAction: "Prioritize deep work sessions for your most important tasks.",
                dimension: "cognitive"
            )
        }

        return nil
    }

    // MARK: - Helpers

    /// Remove duplicate insights based on title similarity
    private func deduplicateInsights(_ insights: [PatternInsight]) -> [PatternInsight] {
        var unique: [PatternInsight] = []
        var seenTitles: Set<String> = []

        for insight in insights {
            let normalizedTitle = insight.title.lowercased()
            if !seenTitles.contains(normalizedTitle) {
                seenTitles.insert(normalizedTitle)
                unique.append(insight)
            }
        }

        // Also check against recent insights
        return unique.filter { insight in
            !recentInsights.contains { $0.title == insight.title }
        }
    }

    /// Cache recent insights
    private func cacheInsights(_ insights: [PatternInsight]) {
        recentInsights.append(contentsOf: insights)
        if recentInsights.count > maxCachedInsights {
            recentInsights.removeFirst(recentInsights.count - maxCachedInsights)
        }
    }

    /// Get recent insights
    func getRecentInsights() async -> [PatternInsight] {
        return recentInsights
    }

    /// Clear insight cache
    func clearCache() async {
        recentInsights.removeAll()
    }
}

// MARK: - Supporting Types

enum TimeRange {
    case day
    case week
    case month
    case quarter
    case year
}

private struct AnalyticsFocusData: Sendable {
    let id: String
    let startedAt: Date
    let endedAt: Date?
    let durationMinutes: Int
    let type: String

    init(id: String, startedAt: Date, endedAt: Date?, durationMinutes: Int, type: String) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationMinutes = durationMinutes
        self.type = type
    }
}

struct TaskData: Sendable {
    let id: String
    let title: String
    let isCompleted: Bool
    let completedAt: Date?
    let priority: String?

    init(id: String, title: String, isCompleted: Bool, completedAt: Date?, priority: String?) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.priority = priority
    }
}

// MARK: - Insight Atom Creation

extension InsightExtractor {

    /// Save insights as Atoms for persistence
    func saveInsightsAsAtoms(
        insights: [PatternInsight],
        database: any DatabaseWriter
    ) async throws {
        for insight in insights {
            let metadataDict: [String: Any] = [
                "insightType": insight.type.rawValue,
                "confidence": insight.confidence.rawValue,
                "evidenceCount": insight.evidenceCount,
                "relatedTopics": insight.relatedTopics,
                "suggestedAction": insight.suggestedAction ?? "",
                "dimension": insight.dimension ?? ""
            ]

            let metadataJson = try JSONSerialization.data(withJSONObject: metadataDict)

            try await database.write { db in
                let atom = Atom.new(
                    type: .journalInsight,
                    title: insight.title,
                    body: insight.description,
                    metadata: String(data: metadataJson, encoding: .utf8)
                )
                try atom.insert(db)
            }
        }
    }
}
