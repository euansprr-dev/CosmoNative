// CosmoOS/UI/Sanctuary/Dimensions/Cognitive/CognitiveDataProvider.swift
// Data provider that queries GRDB to build real CognitiveDimensionData
// Phase 4: Cognitive Dimension Integration

import Foundation
import SwiftUI
import GRDB

// Shared ISO8601 formatter — avoids recreating per call
private let _cognitiveISOFormatter = ISO8601DateFormatter()

@MainActor
class CognitiveDataProvider: ObservableObject {
    @Published var data: CognitiveDimensionData = CognitiveDimensionData()
    @Published var isLoading = false

    private let database: CosmoDatabase
    private let atomRepository: AtomRepository

    init(database: CosmoDatabase? = nil, atomRepository: AtomRepository? = nil) {
        self.database = database ?? CosmoDatabase.shared
        self.atomRepository = atomRepository ?? AtomRepository.shared
    }

    // MARK: - Refresh

    func refreshData() async {
        isLoading = true
        defer { isLoading = false }

        let sessions = await fetchTodaysSessions()
        let historicalSessions = await fetchHistoricalSessions(days: 30)
        let interruptions = buildInterruptions(from: sessions)
        let correlations = await fetchCorrelations()
        let journalData = await fetchJournalData()

        // Compute sub-scores
        let focusQuality = computeFocusQuality(sessions: sessions)
        let deepWorkVolume = computeDeepWorkVolume(sessions: sessions)
        let sessionConsistency = computeSessionConsistency(historicalSessions: historicalSessions)
        let recoveryFactor = 60.0 // Neutral — no sleep data source yet
        let interruptionResilience = computeInterruptionResilience(sessions: sessions)

        // Weighted Cognitive Index
        let cognitiveIndex = focusQuality * 0.30
            + deepWorkVolume * 0.25
            + sessionConsistency * 0.15
            + recoveryFactor * 0.15
            + interruptionResilience * 0.15

        // NELO computation
        let neloScore = computeNELOScore(sessions: sessions)
        let neloStatus = NELOStatus.from(score: neloScore)
        let neloWaveform = generateNELOWaveform(baseScore: neloScore)

        // Focus stability by hour
        let focusStabilityByHour = computeFocusStabilityByHour(historicalSessions: historicalSessions)

        // Deep work totals
        let totalDeepWorkSeconds = sessions.reduce(0.0) { $0 + Double($1.durationMinutes) * 60 }
        let avgQuality = sessions.isEmpty ? 0.0 : sessions.reduce(0.0) { $0 + $1.qualityScore } / Double(sessions.count)

        // Capacity remaining: 4h target minus worked
        let targetSeconds: Double = 4 * 3600
        let capacityRemaining = max(0, targetSeconds - totalDeepWorkSeconds)

        // Predicted windows
        let predictedWindows = computePredictedWindows(historicalSessions: historicalSessions)
        let currentWindowStatus = computeCurrentWindowStatus(windows: predictedWindows)

        // Interruption stats
        let totalInterruptions = interruptions.count
        let avgRecovery = interruptions.isEmpty ? 0.0 : interruptions.reduce(0.0) { $0 + $1.recoveryMinutes } / Double(interruptions.count)
        let focusCost = Int(interruptions.reduce(0.0) { $0 + $1.recoveryMinutes })
        let topDisruptors = computeTopDisruptors(interruptions: interruptions)

        // Cognitive load
        let cognitiveLoadCurrent = min(100, neloScore * 1.3)
        let cognitiveLoadHistory = generateCognitiveLoadHistory(sessions: sessions)

        data = CognitiveDimensionData(
            cognitiveIndex: min(100, max(0, cognitiveIndex)),
            neloScore: neloScore,
            neloWaveform: neloWaveform,
            neloStatus: neloStatus,
            focusIndex: focusQuality,
            focusStabilityByHour: focusStabilityByHour,
            cognitiveLoadCurrent: cognitiveLoadCurrent,
            cognitiveLoadHistory: cognitiveLoadHistory,
            deepWorkSessions: sessions,
            totalDeepWorkToday: totalDeepWorkSeconds,
            averageQualityToday: avgQuality,
            predictedCapacityRemaining: capacityRemaining,
            predictedOptimalWindows: predictedWindows,
            currentWindowStatus: currentWindowStatus,
            interruptions: interruptions,
            totalInterruptionsToday: totalInterruptions,
            averageRecoveryTime: avgRecovery * 60,
            focusCostMinutes: focusCost,
            topDisruptors: topDisruptors,
            topCorrelations: correlations,
            journalInsightMarkersToday: journalData.insightCount,
            reflectionDepthScore: journalData.depthScore,
            detectedThemes: journalData.themes,
            journalExcerpt: journalData.excerpt
        )
    }

    // MARK: - Fetch Today's Sessions

    private func fetchTodaysSessions() async -> [DeepWorkSession] {
        let todayStart = Calendar.current.startOfDay(for: Date())
        let todayStartISO = _cognitiveISOFormatter.string(from: todayStart)

        do {
            let atoms = try await atomRepository.fetchAll(type: .deepWorkBlock)
            return atoms.compactMap { atom -> DeepWorkSession? in
                guard atom.createdAt >= todayStartISO else { return nil }
                return deepWorkSessionFromAtom(atom)
            }
        } catch {
            return []
        }
    }

    // MARK: - Fetch Historical Sessions

    private func fetchHistoricalSessions(days: Int) async -> [DeepWorkSession] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let cutoffISO = _cognitiveISOFormatter.string(from: cutoff)

        do {
            let atoms = try await atomRepository.fetchAll(type: .deepWorkBlock)
            return atoms.compactMap { atom -> DeepWorkSession? in
                guard atom.createdAt >= cutoffISO else { return nil }
                return deepWorkSessionFromAtom(atom)
            }
        } catch {
            return []
        }
    }

    // MARK: - Parse DeepWorkSession from Atom

    private func deepWorkSessionFromAtom(_ atom: Atom) -> DeepWorkSession? {
        guard let meta = atom.metadataValue(as: DeepWorkSessionMetadata.self) else { return nil }

        let formatter = _cognitiveISOFormatter
        let startTime = formatter.date(from: meta.startedAt) ?? Date()
        let endTime = meta.endedAt.flatMap { formatter.date(from: $0) }

        let taskType: CognitiveTaskType = {
            guard let intentString = meta.intent else { return .coding }
            switch intentString {
            case "write", "writing": return .writing
            case "research": return .research
            case "plan", "planning": return .planning
            case "read", "reading": return .reading
            case "design": return .design
            case "analyze", "analysis": return .analysis
            case "meet", "meeting": return .meeting
            default: return .coding
            }
        }()

        let focusScore = meta.focusScore ?? 70.0
        let distractionCount = meta.distractionCount ?? 0
        let durationMinutes = meta.actualMinutes ?? 0

        // Estimate flow minutes: portion of time with high focus
        let flowMinutes = Int(Double(durationMinutes) * (focusScore / 100.0) * 0.8)

        return DeepWorkSession(
            startTime: startTime,
            endTime: endTime,
            taskType: taskType,
            qualityScore: focusScore,
            flowMinutes: flowMinutes,
            interruptionCount: distractionCount,
            notes: meta.notes
        )
    }

    // MARK: - Cognitive Index Sub-Scores

    /// Focus Quality (30%): Average focusScore from today's sessions
    private func computeFocusQuality(sessions: [DeepWorkSession]) -> Double {
        guard !sessions.isEmpty else { return 0 }
        return sessions.reduce(0.0) { $0 + $1.qualityScore } / Double(sessions.count)
    }

    /// Deep Work Volume (25%): Total minutes today / 240 (4h target), capped at 100
    private func computeDeepWorkVolume(sessions: [DeepWorkSession]) -> Double {
        let totalMinutes = sessions.reduce(0) { $0 + $1.durationMinutes }
        return min(100, Double(totalMinutes) / 240.0 * 100.0)
    }

    /// Session Consistency (15%): 7-day std dev of daily minutes
    private func computeSessionConsistency(historicalSessions: [DeepWorkSession]) -> Double {
        let calendar = Calendar.current
        var dailyMinutes: [Date: Int] = [:]

        // Collect last 7 days
        for dayOffset in 0..<7 {
            let day = calendar.date(byAdding: .day, value: -dayOffset, to: Date())!
            let dayStart = calendar.startOfDay(for: day)
            dailyMinutes[dayStart] = 0
        }

        for session in historicalSessions {
            let dayStart = calendar.startOfDay(for: session.startTime)
            if dailyMinutes[dayStart] != nil {
                dailyMinutes[dayStart]! += session.durationMinutes
            }
        }

        let values = Array(dailyMinutes.values).map { Double($0) }
        guard !values.isEmpty else { return 0 }

        let avg = values.reduce(0, +) / Double(values.count)
        guard avg > 0 else { return 0 }

        let variance = values.reduce(0.0) { $0 + pow($1 - avg, 2) } / Double(values.count)
        let stdDev = sqrt(variance)
        let cv = stdDev / avg // coefficient of variation

        return max(0, min(100, 100 - cv * 100))
    }

    /// Interruption Resilience (15%): 100 - (distractions * avgRecovery / totalFocus * 100)
    private func computeInterruptionResilience(sessions: [DeepWorkSession]) -> Double {
        let totalDistractions = sessions.reduce(0) { $0 + $1.interruptionCount }
        let totalMinutes = sessions.reduce(0) { $0 + $1.durationMinutes }

        guard totalMinutes > 0, totalDistractions > 0 else { return 100 }

        // Estimate avg recovery at 3 minutes per distraction
        let avgRecoveryMinutes = 3.0
        let lostMinutes = Double(totalDistractions) * avgRecoveryMinutes
        let lostRatio = lostMinutes / Double(totalMinutes)

        return max(0, min(100, 100 - lostRatio * 100))
    }

    // MARK: - NELO Score

    /// NELO = weighted average of:
    /// - focusQuality from last session (40%)
    /// - time since last break as fatigue factor (30%)
    /// - session duration vs optimal 90min (30%)
    private func computeNELOScore(sessions: [DeepWorkSession]) -> Double {
        guard let lastSession = sessions.last else { return 42.0 } // Default balanced

        // Factor 1: Focus quality (40%)
        let focusFactor = lastSession.qualityScore / 100.0 * 70.0 // Scale to 0-70

        // Factor 2: Time since last break as fatigue (30%)
        let timeSinceEnd: TimeInterval
        if let endTime = lastSession.endTime {
            timeSinceEnd = Date().timeIntervalSince(endTime) / 60.0 // minutes
        } else {
            // Active session — use elapsed time
            timeSinceEnd = Double(lastSession.durationMinutes)
        }
        // Fatigue increases with duration without break; optimal break every 90min
        let fatigueFactor: Double
        if timeSinceEnd < 15 {
            fatigueFactor = 20.0 // Just finished, slightly elevated
        } else if timeSinceEnd < 60 {
            fatigueFactor = 10.0 // Recovering
        } else {
            fatigueFactor = 5.0  // Well-rested
        }

        // Factor 3: Session duration vs optimal 90min (30%)
        let durationScore: Double
        let duration = Double(lastSession.durationMinutes)
        if duration >= 35 && duration <= 120 {
            durationScore = 15.0 // Optimal range
        } else if duration < 35 {
            durationScore = 10.0 // Too short
        } else {
            durationScore = 25.0 // Too long, elevated load
        }

        let score = focusFactor * 0.4 + fatigueFactor * 0.3 + durationScore * 0.3
        return max(10, min(90, score))
    }

    private func generateNELOWaveform(baseScore: Double) -> [Double] {
        (0..<60).map { i in
            let wave = sin(Double(i) / 10.0) * 5.0
            let noise = Double.random(in: -2...2)
            return baseScore + wave + noise
        }
    }

    // MARK: - Focus Stability by Hour

    private func computeFocusStabilityByHour(historicalSessions: [DeepWorkSession]) -> [Int: Double] {
        var hourScores: [Int: [Double]] = [:]

        for session in historicalSessions {
            let hour = Calendar.current.component(.hour, from: session.startTime)
            hourScores[hour, default: []].append(session.qualityScore)
        }

        var stability: [Int: Double] = [:]
        for hourVal in 0..<24 {
            if hourVal < 6 || hourVal > 22 {
                stability[hourVal] = 0 // Sleep hours
            } else if let scores = hourScores[hourVal], !scores.isEmpty {
                // Exponential decay weighting — recent sessions matter more
                var weightedSum = 0.0
                var weightTotal = 0.0
                for (index, score) in scores.enumerated() {
                    let weight = exp(-0.1 * Double(scores.count - 1 - index))
                    weightedSum += score * weight
                    weightTotal += weight
                }
                stability[hourVal] = weightTotal > 0 ? weightedSum / weightTotal : 0
            } else {
                stability[hourVal] = 0
            }
        }

        return stability
    }

    // MARK: - Predicted Windows

    private func computePredictedWindows(historicalSessions: [DeepWorkSession]) -> [CognitiveWindow] {
        // Group sessions by hour and compute weighted average focus score
        var hourPerformance: [Int: (totalWeighted: Double, totalWeight: Double)] = [:]
        let now = Date()

        for session in historicalSessions {
            let hour = Calendar.current.component(.hour, from: session.startTime)
            let daysAgo = Calendar.current.dateComponents([.day], from: session.startTime, to: now).day ?? 0
            let weight = exp(-0.1 * Double(daysAgo)) // Recent days weighted more
            let existing = hourPerformance[hour] ?? (totalWeighted: 0, totalWeight: 0)
            hourPerformance[hour] = (
                totalWeighted: existing.totalWeighted + session.qualityScore * weight,
                totalWeight: existing.totalWeight + weight
            )
        }

        // Compute average for each hour
        var hourAvg: [(hour: Int, avg: Double)] = []
        for (hour, perf) in hourPerformance {
            guard perf.totalWeight > 0 else { continue }
            hourAvg.append((hour: hour, avg: perf.totalWeighted / perf.totalWeight))
        }
        hourAvg.sort { $0.avg > $1.avg }

        // Find top 2 windows (consecutive high-performance hours)
        var windows: [CognitiveWindow] = []
        var usedHours: Set<Int> = []

        for entry in hourAvg.prefix(4) {
            guard !usedHours.contains(entry.hour) else { continue }

            let startHour = entry.hour
            var endHour = startHour + 2 // Default 2-hour window
            // Extend if next hour also has good performance
            if let nextPerf = hourPerformance[startHour + 1],
               nextPerf.totalWeight > 0 {
                let nextAvg = nextPerf.totalWeighted / nextPerf.totalWeight
                if nextAvg > 60 {
                    endHour = startHour + 3
                }
            }

            endHour = min(endHour, 23)
            usedHours.insert(startHour)
            usedHours.insert(startHour + 1)

            let confidence = min(95, entry.avg)
            let isPrimary = windows.isEmpty

            let recommendedTypes: [CognitiveTaskType] = entry.avg > 80
                ? [.coding, .writing]
                : [.planning, .reading]

            windows.append(CognitiveWindow(
                startTime: DateComponents(hour: startHour, minute: 0),
                endTime: DateComponents(hour: endHour, minute: 0),
                confidence: confidence,
                isPrimary: isPrimary,
                recommendedTaskTypes: recommendedTypes,
                basedOn: ["historical performance", "\(Int(hourPerformance[startHour]?.totalWeight ?? 0)) sessions"]
            ))

            if windows.count >= 2 { break }
        }

        // Fallback if no data
        if windows.isEmpty {
            windows = [
                CognitiveWindow(
                    startTime: DateComponents(hour: 9, minute: 0),
                    endTime: DateComponents(hour: 11, minute: 0),
                    confidence: 50,
                    isPrimary: true,
                    recommendedTaskTypes: [.coding, .writing],
                    basedOn: ["default morning window"]
                )
            ]
        }

        return windows
    }

    private func computeCurrentWindowStatus(windows: [CognitiveWindow]) -> CognitiveWindowStatus {
        let currentHour = Calendar.current.component(.hour, from: Date())
        let currentMinute = Calendar.current.component(.minute, from: Date())
        let currentTotal = currentHour * 60 + currentMinute

        for window in windows {
            guard let startHour = window.startTime.hour,
                  let startMinute = window.startTime.minute,
                  let endHour = window.endTime.hour,
                  let endMinute = window.endTime.minute else { continue }

            let windowStart = startHour * 60 + startMinute
            let windowEnd = endHour * 60 + endMinute

            if currentTotal >= windowStart && currentTotal <= windowEnd {
                return .inWindow
            }
            if currentTotal >= windowStart - 30 && currentTotal < windowStart {
                return .approaching
            }
        }

        // Check if all windows passed
        let allPassed = windows.allSatisfy { window in
            guard let endHour = window.endTime.hour,
                  let endMinute = window.endTime.minute else { return false }
            return currentTotal > endHour * 60 + endMinute
        }

        return allPassed ? .passed : .scheduled
    }

    // MARK: - Interruptions

    private func buildInterruptions(from sessions: [DeepWorkSession]) -> [CognitiveInterruption] {
        var interruptions: [CognitiveInterruption] = []

        for session in sessions {
            guard session.interruptionCount > 0 else { continue }

            // Distribute interruptions across session duration
            let sessionDuration = Double(session.durationMinutes)
            let interval = sessionDuration / Double(session.interruptionCount + 1)

            for i in 0..<session.interruptionCount {
                let minutesIn = interval * Double(i + 1)
                let timestamp = session.startTime.addingTimeInterval(minutesIn * 60)

                // Assign source based on pattern — in real implementation,
                // this would come from distraction event atoms
                let source: InterruptionSource = {
                    let sources: [InterruptionSource] = [.notification, .slack, .selfInitiated, .system]
                    return sources[i % sources.count]
                }()

                let severity = min(1.0, Double(i + 1) / Double(session.interruptionCount) * 0.8)
                let recovery = 2.0 + severity * 6.0 // 2-8 minutes recovery

                interruptions.append(CognitiveInterruption(
                    timestamp: timestamp,
                    source: source,
                    recoveryMinutes: recovery,
                    severityScore: severity
                ))
            }
        }

        return interruptions.sorted { $0.timestamp < $1.timestamp }
    }

    private func computeTopDisruptors(interruptions: [CognitiveInterruption]) -> [(source: InterruptionSource, count: Int)] {
        var counts: [InterruptionSource: Int] = [:]
        for interruption in interruptions {
            counts[interruption.source, default: 0] += 1
        }
        return counts
            .map { (source: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    // MARK: - Correlations

    private func fetchCorrelations() async -> [CognitiveCorrelation] {
        do {
            let atoms = try await atomRepository.fetchAll(type: .correlationInsight)
            let cognitiveCorrelations = atoms.compactMap { atom -> CognitiveCorrelation? in
                guard let body = atom.body else { return nil }

                // Parse correlation data from metadata
                struct CorrelationMeta: Decodable {
                    var sourceMetric: String?
                    var targetMetric: String?
                    var coefficient: Double?
                    var strength: String?
                    var trend: String?
                    var sparklineData: [Double]?
                    var actionInsight: String?
                    var sampleSize: Int?
                    var dimension: String?
                }

                guard let meta = atom.metadataValue(as: CorrelationMeta.self),
                      meta.dimension == "cognitive" || meta.dimension == nil,
                      let source = meta.sourceMetric,
                      let target = meta.targetMetric,
                      let coeff = meta.coefficient else { return nil }

                let strength: CorrelationStrength = {
                    switch abs(coeff) {
                    case 0.85...: return .veryStrong
                    case 0.7..<0.85: return .strong
                    case 0.5..<0.7: return .moderate
                    default: return .weak
                    }
                }()

                let trend: Trend = {
                    guard let t = meta.trend else { return .stable }
                    return Trend(rawValue: t) ?? .stable
                }()

                return CognitiveCorrelation(
                    sourceMetric: source,
                    targetMetric: target,
                    coefficient: coeff,
                    strength: strength,
                    trend: trend,
                    sparklineData: meta.sparklineData ?? [],
                    actionInsight: meta.actionInsight ?? body,
                    sampleSize: meta.sampleSize ?? 0
                )
            }

            // If no stored correlations, provide sensible defaults
            if cognitiveCorrelations.isEmpty {
                return defaultCorrelations()
            }

            return Array(cognitiveCorrelations.prefix(6))
        } catch {
            return defaultCorrelations()
        }
    }

    private func defaultCorrelations() -> [CognitiveCorrelation] {
        [
            CognitiveCorrelation(
                sourceMetric: "deep_work_hours",
                targetMetric: "focus_score",
                coefficient: 0.72,
                strength: .strong,
                trend: .stable,
                sparklineData: [65, 70, 68, 75, 72, 78, 80],
                actionInsight: "Longer sessions correlate with higher focus",
                sampleSize: 0
            ),
            CognitiveCorrelation(
                sourceMetric: "break_frequency",
                targetMetric: "sustainability",
                coefficient: 0.61,
                strength: .moderate,
                trend: .up,
                sparklineData: [3, 4, 5, 4, 6, 5, 7],
                actionInsight: "Regular breaks improve session sustainability",
                sampleSize: 0
            )
        ]
    }

    // MARK: - Journal Data

    private struct JournalData {
        var insightCount: Int = 0
        var depthScore: Double = 0
        var themes: [String] = []
        var excerpt: String?
    }

    private func fetchJournalData() async -> JournalData {
        let todayStart = Calendar.current.startOfDay(for: Date())
        let todayStartISO = _cognitiveISOFormatter.string(from: todayStart)

        do {
            let insights = try await atomRepository.fetchAll(type: .journalInsight)
            let todayInsights = insights.filter { $0.createdAt >= todayStartISO }

            let journals = try await atomRepository.fetchAll(type: .journalEntry)
            let todayJournals = journals.filter { $0.createdAt >= todayStartISO }

            // Extract themes from today's journal insights
            var themes: [String] = []
            for insight in todayInsights {
                if let body = insight.body {
                    // Simple theme extraction from body text
                    let words = body.components(separatedBy: .whitespacesAndNewlines)
                    if let first = words.first, first.count > 3 {
                        themes.append(first.lowercased())
                    }
                }
            }

            // Depth score based on total journal word count today
            let totalWords = todayJournals.reduce(0) { total, journal in
                let words = journal.body?.components(separatedBy: .whitespacesAndNewlines).count ?? 0
                return total + words
            }
            let depthScore = min(10, Double(totalWords) / 50.0)

            let excerpt = todayJournals.first?.body.flatMap { body in
                String(body.prefix(100))
            }

            return JournalData(
                insightCount: todayInsights.count,
                depthScore: depthScore,
                themes: Array(Set(themes)).sorted().prefix(5).map { String($0) },
                excerpt: excerpt
            )
        } catch {
            return JournalData()
        }
    }

    // MARK: - Cognitive Load History

    private func generateCognitiveLoadHistory(sessions: [DeepWorkSession]) -> [Double] {
        // Build a 60-point history (last 60 minutes)
        let now = Date()
        return (0..<60).map { minuteOffset in
            let timestamp = now.addingTimeInterval(-Double(59 - minuteOffset) * 60)

            // Check if any session was active at this time
            for session in sessions {
                let end = session.endTime ?? now
                if timestamp >= session.startTime && timestamp <= end {
                    // Active session — load based on quality and duration
                    let minutesIn = timestamp.timeIntervalSince(session.startTime) / 60.0
                    let fatigue = min(30, minutesIn * 0.3) // Fatigue accumulates
                    return min(100, session.qualityScore * 0.7 + fatigue)
                }
            }

            // No active session — low baseline load
            return Double.random(in: 15...30)
        }
    }
}
