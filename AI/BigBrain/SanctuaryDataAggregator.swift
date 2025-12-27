// CosmoOS/AI/BigBrain/SanctuaryDataAggregator.swift
// Aggregates real Atom data to populate CorrelationDataContext for Claude analysis
// This is the critical missing piece - wiring database data to Claude prompts

import Foundation
import GRDB

// MARK: - Sanctuary Data Aggregator

/// Aggregates data from AtomRepository to build CorrelationDataContext.
///
/// This actor queries the database for real user data across all dimensions
/// and transforms it into the structured format that Claude expects.
///
/// Usage:
/// ```swift
/// let aggregator = SanctuaryDataAggregator.shared
/// let context = try await aggregator.buildContext(timeframeDays: 90)
/// let prompt = CorrelationRequestBuilder.build(dimensions: ["all"], context: context)
/// ```
@MainActor
public class SanctuaryDataAggregator {

    // MARK: - Singleton

    public static let shared = SanctuaryDataAggregator()

    // MARK: - Properties

    private let database = CosmoDatabase.shared

    private init() {}

    // MARK: - Main API

    /// Build a complete CorrelationDataContext from database data
    public func buildContext(timeframeDays: Int = 90) async throws -> CorrelationDataContext {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -timeframeDays, to: Date())!
        let cutoffISO = ISO8601DateFormatter().string(from: cutoffDate)

        async let physiological = buildPhysiologicalData(since: cutoffISO)
        async let behavioral = buildBehavioralData(since: cutoffISO)
        async let cognitive = buildCognitiveData(since: cutoffISO)
        async let creative = buildCreativeData(since: cutoffISO)
        async let reflection = buildReflectionData(since: cutoffISO)
        async let knowledge = buildKnowledgeData(since: cutoffISO)

        return CorrelationDataContext(
            timeframeDays: timeframeDays,
            physiological: try await physiological,
            behavioral: try await behavioral,
            cognitive: try await cognitive,
            creative: try await creative,
            reflection: try await reflection,
            knowledge: try await knowledge
        )
    }

    /// Build context for specific dimensions only
    public func buildContext(
        dimensions: [LevelDimension],
        timeframeDays: Int = 90
    ) async throws -> CorrelationDataContext {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -timeframeDays, to: Date())!
        let cutoffISO = ISO8601DateFormatter().string(from: cutoffDate)

        var physiological: PhysiologicalData? = nil
        var behavioral: BehavioralData? = nil
        var cognitive: CognitiveData? = nil
        var creative: CreativeData? = nil
        var reflection: ReflectionData? = nil
        var knowledge: KnowledgeData? = nil

        for dimension in dimensions {
            switch dimension {
            case .physiological:
                physiological = try await buildPhysiologicalData(since: cutoffISO)
            case .behavioral:
                behavioral = try await buildBehavioralData(since: cutoffISO)
            case .cognitive:
                cognitive = try await buildCognitiveData(since: cutoffISO)
            case .creative:
                creative = try await buildCreativeData(since: cutoffISO)
            case .reflection:
                reflection = try await buildReflectionData(since: cutoffISO)
            case .knowledge:
                knowledge = try await buildKnowledgeData(since: cutoffISO)
            }
        }

        return CorrelationDataContext(
            timeframeDays: timeframeDays,
            physiological: physiological,
            behavioral: behavioral,
            cognitive: cognitive,
            creative: creative,
            reflection: reflection,
            knowledge: knowledge
        )
    }

    // MARK: - Dimension Builders

    /// Build physiological dimension data from HRV, sleep, readiness atoms
    private func buildPhysiologicalData(since cutoffISO: String) async throws -> PhysiologicalData {
        // Fetch HRV measurements
        let hrvAtoms = try await fetchAtoms(
            types: [.hrvMeasurement, .hrvReading],
            since: cutoffISO
        )

        // Fetch sleep data
        let sleepAtoms = try await fetchAtoms(
            types: [.sleepCycle, .sleepRecord],
            since: cutoffISO
        )

        // Fetch readiness scores
        let readinessAtoms = try await fetchAtoms(
            types: [.readinessScore, .recoveryScore],
            since: cutoffISO
        )

        // Calculate HRV trend
        let hrvValues = hrvAtoms.compactMap { atom -> Double? in
            guard let metadata = atom.metadataDict,
                  let hrv = metadata["hrv"] as? Double ?? metadata["value"] as? Double else {
                return nil
            }
            return hrv
        }
        let hrvTrend = calculateTrend(values: hrvValues)

        // Calculate average resting HR
        let hrValues = hrvAtoms.compactMap { atom -> Int? in
            guard let metadata = atom.metadataDict,
                  let hr = metadata["restingHR"] as? Int ?? metadata["heartRate"] as? Int else {
                return nil
            }
            return hr
        }
        let avgRestingHR = hrValues.isEmpty ? 65 : hrValues.reduce(0, +) / hrValues.count

        // Calculate sleep stats
        let sleepHours = sleepAtoms.compactMap { atom -> Double? in
            guard let metadata = atom.metadataDict,
                  let duration = metadata["duration"] as? Double ?? metadata["durationMinutes"] as? Double else {
                return nil
            }
            // Convert minutes to hours if needed
            return duration > 24 ? duration / 60.0 : duration
        }
        let avgSleepHours = sleepHours.isEmpty ? 7.5 : sleepHours.reduce(0, +) / Double(sleepHours.count)
        let sleepQualityTrend = calculateSleepQualityTrend(sleepAtoms: sleepAtoms)

        // Calculate readiness summary
        let readinessScores = readinessAtoms.compactMap { atom -> Int? in
            guard let metadata = atom.metadataDict,
                  let score = metadata["score"] as? Int ?? metadata["readinessScore"] as? Int else {
                return nil
            }
            return score
        }
        let readinessScoreSummary = summarizeReadinessScores(scores: readinessScores)

        // Determine recovery pattern
        let recoveryPattern = analyzeRecoveryPattern(
            hrvAtoms: hrvAtoms,
            sleepAtoms: sleepAtoms,
            readinessAtoms: readinessAtoms
        )

        return PhysiologicalData(
            hrvTrend: hrvTrend,
            avgRestingHR: avgRestingHR,
            sleepQualityTrend: sleepQualityTrend,
            avgSleepHours: avgSleepHours,
            readinessScoreSummary: readinessScoreSummary,
            recoveryPattern: recoveryPattern
        )
    }

    /// Build behavioral dimension data from deep work, streaks, tasks
    private func buildBehavioralData(since cutoffISO: String) async throws -> BehavioralData {
        // Fetch deep work blocks
        let deepWorkAtoms = try await fetchAtoms(
            types: [.deepWorkBlock],
            since: cutoffISO
        )

        // Fetch tasks for completion rate
        let taskAtoms = try await fetchAtoms(
            types: [.task],
            since: cutoffISO
        )

        // Fetch streak events
        let streakAtoms = try await fetchAtoms(
            types: [.streakEvent],
            since: cutoffISO
        )

        // Calculate average deep work minutes per day
        let totalMinutes = deepWorkAtoms.compactMap { atom -> Int? in
            guard let metadata = atom.metadataDict,
                  let duration = metadata["durationMinutes"] as? Int ?? metadata["duration"] as? Int else {
                return nil
            }
            return duration
        }.reduce(0, +)

        let dayCount = max(1, calculateDayCount(since: cutoffISO))
        let avgDeepWorkMinutes = totalMinutes / dayCount

        // Focus session count
        let focusSessionCount = deepWorkAtoms.count

        // Task completion rate
        let completedTasks = taskAtoms.filter { atom in
            guard let metadata = atom.metadataDict else { return false }
            return metadata["status"] as? String == "completed" ||
                   metadata["isCompleted"] as? Bool == true
        }.count
        let taskCompletionRate = taskAtoms.isEmpty ? 0.0 : Double(completedTasks) / Double(taskAtoms.count)

        // Active streaks
        let activeStreaks = extractActiveStreaks(from: streakAtoms)

        // Streak breaks count
        let streakBreaks = streakAtoms.filter { atom in
            guard let metadata = atom.metadataDict else { return false }
            return metadata["eventType"] as? String == "break" ||
                   metadata["broken"] as? Bool == true
        }.count

        // Most productive hours (analyze deep work start times)
        let mostProductiveHours = analyzeMostProductiveHours(deepWorkAtoms: deepWorkAtoms)

        return BehavioralData(
            avgDeepWorkMinutes: avgDeepWorkMinutes,
            focusSessionCount: focusSessionCount,
            taskCompletionRate: taskCompletionRate,
            activeStreaks: activeStreaks,
            streakBreaks: streakBreaks,
            mostProductiveHours: mostProductiveHours
        )
    }

    /// Build cognitive dimension data from ideas, tasks, writing sessions
    private func buildCognitiveData(since cutoffISO: String) async throws -> CognitiveData {
        // Fetch ideas
        let ideaAtoms = try await fetchAtoms(
            types: [.idea],
            since: cutoffISO
        )

        // Fetch tasks
        let taskAtoms = try await fetchAtoms(
            types: [.task],
            since: cutoffISO
        )

        // Fetch writing sessions
        let writingAtoms = try await fetchAtoms(
            types: [.writingSession, .wordCountEntry],
            since: cutoffISO
        )

        // Fetch XP events
        let xpAtoms = try await fetchAtoms(
            types: [.xpEvent],
            since: cutoffISO
        )

        // Fetch dimension snapshots for level
        let dimensionAtoms = try await fetchAtoms(
            types: [.dimensionSnapshot],
            since: cutoffISO
        )

        // Calculate totals
        let ideasCreated = ideaAtoms.count
        let tasksCreated = taskAtoms.count
        let writingSessions = writingAtoms.filter { $0.type == .writingSession }.count

        // Total words written
        let totalWordsWritten = writingAtoms.compactMap { atom -> Int? in
            guard let metadata = atom.metadataDict,
                  let words = metadata["wordCount"] as? Int ?? metadata["words"] as? Int else {
                return nil
            }
            return words
        }.reduce(0, +)

        // Total XP earned (for cognitive dimension)
        let xpEarned = xpAtoms.compactMap { atom -> Int? in
            guard let metadata = atom.metadataDict else { return nil }
            // Only count cognitive XP
            if metadata["dimension"] as? String == "cognitive" {
                return metadata["amount"] as? Int ?? metadata["xp"] as? Int
            }
            return nil
        }.reduce(0, +)

        // Get current cognitive dimension level
        let dimensionLevel = extractDimensionLevel(from: dimensionAtoms, dimension: .cognitive)

        return CognitiveData(
            ideasCreated: ideasCreated,
            tasksCreated: tasksCreated,
            writingSessions: writingSessions,
            totalWordsWritten: totalWordsWritten,
            xpEarned: xpEarned,
            dimensionLevel: dimensionLevel
        )
    }

    /// Build creative dimension data from content performance
    private func buildCreativeData(since cutoffISO: String) async throws -> CreativeData {
        // Fetch published content
        let publishAtoms = try await fetchAtoms(
            types: [.contentPublish],
            since: cutoffISO
        )

        // Fetch content performance
        let performanceAtoms = try await fetchAtoms(
            types: [.contentPerformance],
            since: cutoffISO
        )

        // Fetch content drafts for pipeline status
        let draftAtoms = try await fetchAtoms(
            types: [.contentDraft, .content],
            since: cutoffISO
        )

        // Count published content
        let contentPublished = publishAtoms.count

        // Calculate total reach
        let totalReach = performanceAtoms.compactMap { atom -> Int? in
            guard let metadata = atom.metadataDict,
                  let reach = metadata["reach"] as? Int ?? metadata["impressions"] as? Int else {
                return nil
            }
            return reach
        }.reduce(0, +)

        // Count viral posts (>10K reach)
        let viralPosts = performanceAtoms.filter { atom in
            guard let metadata = atom.metadataDict,
                  let reach = metadata["reach"] as? Int ?? metadata["impressions"] as? Int else {
                return false
            }
            return reach > 10000
        }.count

        // Calculate engagement rate
        let engagementData = performanceAtoms.compactMap { atom -> (engagement: Int, reach: Int)? in
            guard let metadata = atom.metadataDict,
                  let engagement = metadata["engagement"] as? Int ?? metadata["likes"] as? Int,
                  let reach = metadata["reach"] as? Int ?? metadata["impressions"] as? Int,
                  reach > 0 else {
                return nil
            }
            return (engagement, reach)
        }
        let totalEngagement = engagementData.map { $0.engagement }.reduce(0, +)
        let totalReachForRate = engagementData.map { $0.reach }.reduce(0, +)
        let engagementRate = totalReachForRate > 0 ? Double(totalEngagement) / Double(totalReachForRate) : 0.0

        // Extract best performing topics
        let bestTopics = extractBestTopics(from: performanceAtoms)

        // Calculate pipeline status
        let pipelineStatus = calculatePipelineStatus(drafts: draftAtoms)

        return CreativeData(
            contentPublished: contentPublished,
            totalReach: totalReach,
            viralPosts: viralPosts,
            engagementRate: engagementRate,
            bestTopics: bestTopics,
            pipelineStatus: pipelineStatus
        )
    }

    /// Build reflection dimension data from journal entries
    private func buildReflectionData(since cutoffISO: String) async throws -> ReflectionData {
        // Fetch journal entries
        let journalAtoms = try await fetchAtoms(
            types: [.journalEntry],
            since: cutoffISO
        )

        // Fetch journal insights
        let insightAtoms = try await fetchAtoms(
            types: [.journalInsight, .emotionalState],
            since: cutoffISO
        )

        // Fetch clarity scores
        let clarityAtoms = try await fetchAtoms(
            types: [.clarityScore],
            since: cutoffISO
        )

        // Count journal entries
        let journalEntryCount = journalAtoms.count

        // Analyze sentiment trend
        let sentimentTrend = analyzeSentimentTrend(journalAtoms: journalAtoms, insightAtoms: insightAtoms)

        // Extract key themes from journal entries
        let keyThemes = extractKeyThemes(from: journalAtoms)

        // Count gratitude entries
        let gratitudeCount = journalAtoms.filter { atom in
            guard let metadata = atom.metadataDict else { return false }
            return metadata["entryType"] as? String == "gratitude" ||
                   atom.body?.lowercased().contains("grateful") == true
        }.count

        // Count challenge entries
        let challengeCount = journalAtoms.filter { atom in
            guard let metadata = atom.metadataDict else { return false }
            return metadata["entryType"] as? String == "challenge" ||
                   metadata["entryType"] as? String == "struggle"
        }.count

        // Analyze clarity score trend
        let clarityScoreTrend = analyzeClarityTrend(clarityAtoms: clarityAtoms)

        return ReflectionData(
            journalEntryCount: journalEntryCount,
            sentimentTrend: sentimentTrend,
            keyThemes: keyThemes,
            gratitudeCount: gratitudeCount,
            challengeCount: challengeCount,
            clarityScoreTrend: clarityScoreTrend
        )
    }

    /// Build knowledge dimension data from research and connections
    private func buildKnowledgeData(since cutoffISO: String) async throws -> KnowledgeData {
        // Fetch research items
        let researchAtoms = try await fetchAtoms(
            types: [.research],
            since: cutoffISO
        )

        // Fetch connections
        let connectionAtoms = try await fetchAtoms(
            types: [.connection, .connectionLink],
            since: cutoffISO
        )

        // Fetch semantic clusters
        let clusterAtoms = try await fetchAtoms(
            types: [.semanticCluster],
            since: cutoffISO
        )

        // Fetch dimension snapshots for level
        let dimensionAtoms = try await fetchAtoms(
            types: [.dimensionSnapshot],
            since: cutoffISO
        )

        // Count research items
        let researchItemsSaved = researchAtoms.count

        // Count connections made
        let connectionsMade = connectionAtoms.count

        // Estimate learning sessions (research + deep reading)
        let learningSessions = researchAtoms.filter { atom in
            guard let metadata = atom.metadataDict else { return false }
            return metadata["processingStatus"] as? String == "completed" ||
                   metadata["isRead"] as? Bool == true
        }.count

        // Extract topics explored
        let topicsExplored = extractTopicsExplored(
            researchAtoms: researchAtoms,
            clusterAtoms: clusterAtoms
        )

        // Get knowledge dimension level
        let dimensionLevel = extractDimensionLevel(from: dimensionAtoms, dimension: .knowledge)

        return KnowledgeData(
            researchItemsSaved: researchItemsSaved,
            connectionsMade: connectionsMade,
            learningSessions: learningSessions,
            topicsExplored: topicsExplored,
            dimensionLevel: dimensionLevel
        )
    }

    // MARK: - Database Queries

    /// Fetch atoms of specified types since a date
    private func fetchAtoms(types: [AtomType], since cutoffISO: String) async throws -> [Atom] {
        guard database.isReady else {
            return []
        }

        let typeStrings = types.map { $0.rawValue }

        return try await database.asyncRead { db in
            try Atom
                .filter(typeStrings.contains(Column("type")))
                .filter(Column("is_deleted") == false)
                .filter(Column("created_at") >= cutoffISO)
                .order(Column("created_at").desc)
                .fetchAll(db)
        }
    }

    // MARK: - Analysis Helpers

    /// Calculate trend direction from a series of values
    private func calculateTrend(values: [Double]) -> String {
        guard values.count >= 2 else { return "stable" }

        // Simple linear regression slope
        let n = Double(values.count)
        let sumX = (0..<values.count).map { Double($0) }.reduce(0, +)
        let sumY = values.reduce(0, +)
        let sumXY = zip(0..<values.count, values).map { Double($0) * $1 }.reduce(0, +)
        let sumX2 = (0..<values.count).map { Double($0 * $0) }.reduce(0, +)

        let slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX)

        if slope > 0.1 {
            return "increasing"
        } else if slope < -0.1 {
            return "decreasing"
        } else {
            return "stable"
        }
    }

    /// Calculate sleep quality trend
    private func calculateSleepQualityTrend(sleepAtoms: [Atom]) -> String {
        let qualityScores = sleepAtoms.compactMap { atom -> Double? in
            guard let metadata = atom.metadataDict else { return nil }
            return metadata["quality"] as? Double ?? metadata["score"] as? Double
        }
        return calculateTrend(values: qualityScores)
    }

    /// Summarize readiness scores
    private func summarizeReadinessScores(scores: [Int]) -> String {
        guard !scores.isEmpty else { return "No data" }

        let avg = scores.reduce(0, +) / scores.count
        let high = scores.filter { $0 >= 80 }.count
        let low = scores.filter { $0 < 60 }.count

        return "Avg: \(avg), High days: \(high), Low days: \(low)"
    }

    /// Analyze recovery pattern
    private func analyzeRecoveryPattern(
        hrvAtoms: [Atom],
        sleepAtoms: [Atom],
        readinessAtoms: [Atom]
    ) -> String {
        // Simplified pattern detection
        let hrvTrend = calculateTrend(values: hrvAtoms.compactMap { atom in
            atom.metadataDict?["hrv"] as? Double ?? atom.metadataDict?["value"] as? Double
        })

        let sleepTrend = calculateTrend(values: sleepAtoms.compactMap { atom in
            atom.metadataDict?["duration"] as? Double ?? atom.metadataDict?["durationMinutes"] as? Double
        })

        if hrvTrend == "increasing" && sleepTrend == "increasing" {
            return "Improving recovery"
        } else if hrvTrend == "decreasing" || sleepTrend == "decreasing" {
            return "Recovery declining"
        } else {
            return "Stable recovery"
        }
    }

    /// Calculate number of days in timeframe
    private func calculateDayCount(since cutoffISO: String) -> Int {
        guard let cutoffDate = ISO8601DateFormatter().date(from: cutoffISO) else {
            return 90
        }
        return Calendar.current.dateComponents([.day], from: cutoffDate, to: Date()).day ?? 90
    }

    /// Extract active streaks from streak events
    private func extractActiveStreaks(from streakAtoms: [Atom]) -> [String] {
        var activeStreaks: [String] = []

        for atom in streakAtoms {
            guard let metadata = atom.metadataDict,
                  let streakName = metadata["name"] as? String ?? metadata["streakType"] as? String,
                  metadata["active"] as? Bool != false,
                  metadata["broken"] as? Bool != true else {
                continue
            }
            if !activeStreaks.contains(streakName) {
                activeStreaks.append(streakName)
            }
        }

        return activeStreaks.isEmpty ? ["None active"] : activeStreaks
    }

    /// Analyze most productive hours from deep work sessions
    private func analyzeMostProductiveHours(deepWorkAtoms: [Atom]) -> String {
        var hourCounts: [Int: Int] = [:]

        for atom in deepWorkAtoms {
            if let metadata = atom.metadataDict,
               let startTime = metadata["startTime"] as? String {
                // Extract hour from time string
                let components = startTime.components(separatedBy: ":")
                if let hour = Int(components.first ?? "") {
                    hourCounts[hour, default: 0] += 1
                }
            } else if let createdAt = ISO8601DateFormatter().date(from: atom.createdAt) {
                let hour = Calendar.current.component(.hour, from: createdAt)
                hourCounts[hour, default: 0] += 1
            }
        }

        guard !hourCounts.isEmpty else { return "No data" }

        // Find peak hours
        let sortedHours = hourCounts.sorted { $0.value > $1.value }
        let topHours = sortedHours.prefix(2).map { "\($0.key):00" }

        return topHours.joined(separator: ", ")
    }

    /// Extract dimension level from snapshots
    private func extractDimensionLevel(from snapshots: [Atom], dimension: LevelDimension) -> Int {
        // Find most recent snapshot for this dimension
        for atom in snapshots {
            if let metadata = atom.metadataDict,
               metadata["dimension"] as? String == dimension.rawValue,
               let level = metadata["level"] as? Int {
                return level
            }
        }
        return 1 // Default level
    }

    /// Extract best performing topics from content performance
    private func extractBestTopics(from performanceAtoms: [Atom]) -> [String] {
        var topicPerformance: [String: Int] = [:]

        for atom in performanceAtoms {
            guard let metadata = atom.metadataDict,
                  let topic = metadata["topic"] as? String ?? metadata["category"] as? String,
                  let reach = metadata["reach"] as? Int ?? metadata["impressions"] as? Int else {
                continue
            }
            topicPerformance[topic, default: 0] += reach
        }

        let sortedTopics = topicPerformance.sorted { $0.value > $1.value }
        return Array(sortedTopics.prefix(3).map { $0.key })
    }

    /// Calculate pipeline status from drafts
    private func calculatePipelineStatus(drafts: [Atom]) -> String {
        let inProgress = drafts.filter { atom in
            guard let metadata = atom.metadataDict else { return false }
            return metadata["status"] as? String == "in_progress" ||
                   metadata["status"] as? String == "draft"
        }.count

        let readyToPublish = drafts.filter { atom in
            guard let metadata = atom.metadataDict else { return false }
            return metadata["status"] as? String == "ready" ||
                   metadata["status"] as? String == "scheduled"
        }.count

        return "\(inProgress) in progress, \(readyToPublish) ready"
    }

    /// Analyze sentiment trend from journal entries
    private func analyzeSentimentTrend(journalAtoms: [Atom], insightAtoms: [Atom]) -> String {
        // Check insights first
        let sentiments = insightAtoms.compactMap { atom -> Double? in
            guard let metadata = atom.metadataDict,
                  let sentiment = metadata["sentiment"] as? Double else {
                return nil
            }
            return sentiment
        }

        if !sentiments.isEmpty {
            return calculateTrend(values: sentiments)
        }

        // Fallback to journal metadata
        let journalSentiments = journalAtoms.compactMap { atom -> Double? in
            guard let metadata = atom.metadataDict,
                  let sentiment = metadata["sentiment"] as? Double else {
                return nil
            }
            return sentiment
        }

        return journalSentiments.isEmpty ? "neutral" : calculateTrend(values: journalSentiments)
    }

    /// Extract key themes from journal entries
    private func extractKeyThemes(from journalAtoms: [Atom]) -> [String] {
        var themeCounts: [String: Int] = [:]

        for atom in journalAtoms {
            // Check metadata for topics
            if let metadata = atom.metadataDict,
               let topics = metadata["topics"] as? [String] {
                for topic in topics {
                    themeCounts[topic, default: 0] += 1
                }
            }

            // Also check entry type
            if let metadata = atom.metadataDict,
               let entryType = metadata["entryType"] as? String {
                themeCounts[entryType, default: 0] += 1
            }
        }

        let sortedThemes = themeCounts.sorted { $0.value > $1.value }
        return Array(sortedThemes.prefix(5).map { $0.key })
    }

    /// Analyze clarity score trend
    private func analyzeClarityTrend(clarityAtoms: [Atom]) -> String {
        let scores = clarityAtoms.compactMap { atom -> Double? in
            guard let metadata = atom.metadataDict,
                  let score = metadata["score"] as? Double ?? metadata["clarity"] as? Double else {
                return nil
            }
            return score
        }
        return scores.isEmpty ? "no data" : calculateTrend(values: scores)
    }

    /// Extract topics explored from research
    private func extractTopicsExplored(researchAtoms: [Atom], clusterAtoms: [Atom]) -> [String] {
        var topics: Set<String> = []

        // From research
        for atom in researchAtoms {
            if let metadata = atom.metadataDict,
               let topic = metadata["topic"] as? String ?? metadata["category"] as? String {
                topics.insert(topic)
            }
            // Also try tags
            if let metadata = atom.metadataDict,
               let tags = metadata["tags"] as? [String] {
                topics.formUnion(tags)
            }
        }

        // From clusters
        for atom in clusterAtoms {
            if let title = atom.title {
                topics.insert(title)
            }
        }

        return Array(topics.prefix(5))
    }
}

// MARK: - Extended Context Builder

extension SanctuaryDataAggregator {

    /// Build an enhanced context with raw journal entries for deeper analysis
    public func buildEnhancedContext(
        timeframeDays: Int = 90,
        includeRawJournals: Bool = true,
        maxJournalEntries: Int = 10
    ) async throws -> EnhancedCorrelationContext {
        // Get base context
        let baseContext = try await buildContext(timeframeDays: timeframeDays)

        // Fetch recent journal entries if requested
        var journalEntries: [JournalEntrySummary] = []
        if includeRawJournals {
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -timeframeDays, to: Date())!
            let cutoffISO = ISO8601DateFormatter().string(from: cutoffDate)

            let journalAtoms = try await fetchAtoms(
                types: [.journalEntry],
                since: cutoffISO
            )

            journalEntries = journalAtoms.prefix(maxJournalEntries).map { atom in
                let entryType = (atom.metadataDict?["entryType"] as? String) ?? "freeform"
                return JournalEntrySummary(
                    date: atom.createdAt,
                    type: entryType,
                    content: atom.body ?? atom.title ?? ""
                )
            }
        }

        return EnhancedCorrelationContext(
            baseContext: baseContext,
            recentJournalEntries: journalEntries,
            generatedAt: ISO8601DateFormatter().string(from: Date())
        )
    }
}

// MARK: - Enhanced Context Types

/// Extended context that includes raw journal entries for deeper analysis
public struct EnhancedCorrelationContext: Codable, Sendable {
    public let baseContext: CorrelationDataContext
    public let recentJournalEntries: [JournalEntrySummary]
    public let generatedAt: String
}

/// Summary of a journal entry for Claude
public struct JournalEntrySummary: Codable, Sendable {
    public let date: String
    public let type: String
    public let content: String

    public init(date: String, type: String, content: String) {
        self.date = date
        self.type = type
        self.content = content
    }
}
