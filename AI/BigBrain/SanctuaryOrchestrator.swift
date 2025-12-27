// CosmoOS/AI/BigBrain/SanctuaryOrchestrator.swift
// Orchestrates the full Sanctuary analysis pipeline:
// 1. Aggregates data from AtomRepository
// 2. Gets pre-computed correlations from CausalityEngine
// 3. Sends to Claude for deep analysis
// 4. Saves insights back as Atoms

import Foundation

// MARK: - Sanctuary Orchestrator

/// Orchestrates the complete Sanctuary correlation analysis pipeline.
///
/// This is the main entry point for triggering Claude-powered analysis.
/// It integrates:
/// - `SanctuaryDataAggregator`: Collects real data from the database
/// - `CausalityEngine`: Pre-computes statistical correlations
/// - `ClaudeAPIClient`: Sends prompts for deep analysis
/// - `AtomRepository`: Saves insights back to database
///
/// Usage:
/// ```swift
/// let orchestrator = SanctuaryOrchestrator.shared
/// let result = try await orchestrator.runAnalysis(trigger: .scheduled)
/// ```
@MainActor
public class SanctuaryOrchestrator {

    // MARK: - Singleton

    public static let shared = SanctuaryOrchestrator()

    // MARK: - Dependencies

    private let dataAggregator = SanctuaryDataAggregator.shared
    private lazy var causalityEngine = CausalityEngine()
    private let claudeClient = ClaudeAPIClient.shared
    private let atomRepository = AtomRepository.shared

    // MARK: - State

    private var isRunning = false
    private var lastRunDate: Date?
    private var lastResult: CorrelationAnalysisResult?

    private init() {}

    // MARK: - Main Entry Points

    /// Run a full correlation analysis with Claude
    public func runAnalysis(
        trigger: CorrelationTrigger,
        dimensions: [LevelDimension] = LevelDimension.allCases,
        timeframeDays: Int = 90
    ) async throws -> CorrelationAnalysisResult {
        guard !isRunning else {
            throw SanctuaryError.analysisInProgress
        }

        isRunning = true
        defer { isRunning = false }

        print("[SanctuaryOrchestrator] Starting analysis with trigger: \(trigger.rawValue)")

        // Step 1: Aggregate data from database
        print("[SanctuaryOrchestrator] Step 1: Aggregating data...")
        let enhancedContext = try await dataAggregator.buildEnhancedContext(
            timeframeDays: timeframeDays,
            includeRawJournals: true,
            maxJournalEntries: 15
        )

        // Step 2: Get pre-computed correlations from CausalityEngine
        print("[SanctuaryOrchestrator] Step 2: Getting pre-computed correlations...")
        let causalityInsights = try await causalityEngine.getActiveInsights()
        let preComputedCorrelations = causalityInsights.map { insight in
            PreComputedCorrelation(
                metric1: insight.sourceMetric,
                metric2: insight.targetMetric,
                pearsonR: insight.coefficient,
                pValue: 0.05, // CausalityEngine ensures p < 0.05
                sampleSize: insight.occurrences,
                dimension1: getDimension(for: insight.sourceMetric),
                dimension2: getDimension(for: insight.targetMetric)
            )
        }

        // Step 3: Build enhanced prompt for Claude
        print("[SanctuaryOrchestrator] Step 3: Building Claude prompt...")
        let dimensionStrings = dimensions.isEmpty ? ["all"] : dimensions.map { $0.rawValue }
        let prompt = CorrelationRequestBuilder.buildEnhanced(
            dimensions: dimensionStrings,
            context: enhancedContext,
            preComputedCorrelations: preComputedCorrelations.isEmpty ? nil : preComputedCorrelations
        )

        // Step 4: Send to Claude for analysis
        print("[SanctuaryOrchestrator] Step 4: Sending to Claude API...")
        let claudeResponse = try await claudeClient.generate(prompt: prompt)

        // Step 5: Parse Claude's response
        print("[SanctuaryOrchestrator] Step 5: Parsing Claude response...")
        let correlations = try parseClaudeResponse(claudeResponse)

        // Step 6: Save correlations as Atoms
        print("[SanctuaryOrchestrator] Step 6: Saving insights to database...")
        try await saveCorrelationInsights(correlations, trigger: trigger)

        // Build result
        let result = CorrelationAnalysisResult(
            correlations: correlations,
            trigger: trigger,
            analyzedAt: ISO8601DateFormatter().string(from: Date()),
            dimensionsAnalyzed: dimensionStrings,
            dataPointsConsidered: calculateDataPoints(from: enhancedContext)
        )

        lastRunDate = Date()
        lastResult = result

        print("[SanctuaryOrchestrator] Analysis complete: \(correlations.count) insights found")

        return result
    }

    /// Run a quick analysis for a specific trigger event
    public func runEventTriggeredAnalysis(event: CorrelationTrigger) async throws -> CorrelationAnalysisResult {
        // Event-specific analysis with shorter timeframe
        let timeframe: Int
        let dimensions: [LevelDimension]

        switch event {
        case .newJournal:
            timeframe = 14
            dimensions = [.reflection, .cognitive, .behavioral]
        case .sleepData:
            timeframe = 7
            dimensions = [.physiological, .cognitive]
        case .hrvShift:
            timeframe = 7
            dimensions = [.physiological, .cognitive, .behavioral]
        case .contentPerformance:
            timeframe = 30
            dimensions = [.creative, .cognitive]
        case .streakChange:
            timeframe = 30
            dimensions = [.behavioral]
        case .scheduled, .manual:
            timeframe = 90
            dimensions = LevelDimension.allCases
        }

        return try await runAnalysis(
            trigger: event,
            dimensions: dimensions,
            timeframeDays: timeframe
        )
    }

    // MARK: - Trigger Detection

    /// Check if analysis should be triggered based on recent events
    public func checkAndTriggerAnalysis() async throws -> CorrelationAnalysisResult? {
        // Check journal trigger: 3+ entries in 24 hours
        if let trigger = try await checkJournalTrigger() {
            return try await runEventTriggeredAnalysis(event: trigger)
        }

        // Check HRV shift trigger: >15% deviation from 7-day baseline
        if let trigger = try await checkHRVShiftTrigger() {
            return try await runEventTriggeredAnalysis(event: trigger)
        }

        // Check scheduled trigger: midnight nightly
        if shouldRunScheduledAnalysis() {
            return try await runAnalysis(trigger: .scheduled)
        }

        return nil
    }

    private func checkJournalTrigger() async throws -> CorrelationTrigger? {
        let cutoff = Calendar.current.date(byAdding: .hour, value: -24, to: Date())!
        let cutoffISO = ISO8601DateFormatter().string(from: cutoff)

        let recentJournals = try await atomRepository.fetch(type: .journalEntry) { atom in
            atom.createdAt >= cutoffISO
        }

        if recentJournals.count >= 3 {
            return .newJournal
        }

        return nil
    }

    private func checkHRVShiftTrigger() async throws -> CorrelationTrigger? {
        // Get last 7 days of HRV
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let cutoffISO = ISO8601DateFormatter().string(from: cutoff)

        let hrvAtoms = try await atomRepository.fetchAll(types: [.hrvMeasurement, .hrvReading])
            .filter { $0.createdAt >= cutoffISO }

        guard hrvAtoms.count >= 5 else { return nil }

        // Calculate baseline (first 5 days) vs recent (last 2 days)
        let sorted = hrvAtoms.sorted { $0.createdAt < $1.createdAt }
        let baselineAtoms = sorted.dropLast(2)
        let recentAtoms = sorted.suffix(2)

        let baselineHRV = baselineAtoms.compactMap { atom -> Double? in
            atom.metadataDict?["hrv"] as? Double ?? atom.metadataDict?["value"] as? Double
        }
        let recentHRV = recentAtoms.compactMap { atom -> Double? in
            atom.metadataDict?["hrv"] as? Double ?? atom.metadataDict?["value"] as? Double
        }

        guard !baselineHRV.isEmpty, !recentHRV.isEmpty else { return nil }

        let baselineAvg = baselineHRV.reduce(0, +) / Double(baselineHRV.count)
        let recentAvg = recentHRV.reduce(0, +) / Double(recentHRV.count)

        let percentChange = abs(recentAvg - baselineAvg) / baselineAvg

        if percentChange > 0.15 {
            return .hrvShift
        }

        return nil
    }

    private func shouldRunScheduledAnalysis() -> Bool {
        // Run once per day at midnight
        guard let lastRun = lastRunDate else { return true }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lastRunDay = calendar.startOfDay(for: lastRun)

        return today > lastRunDay
    }

    // MARK: - Response Parsing

    private func parseClaudeResponse(_ response: String) throws -> [ClaudeCorrelationOutput] {
        // Extract JSON from response (Claude sometimes wraps it)
        let jsonString: String
        if let startIndex = response.firstIndex(of: "["),
           let endIndex = response.lastIndex(of: "]") {
            jsonString = String(response[startIndex...endIndex])
        } else {
            jsonString = response
        }

        guard let data = jsonString.data(using: .utf8) else {
            throw SanctuaryError.invalidClaudeResponse("Failed to convert response to data")
        }

        do {
            return try JSONDecoder().decode([ClaudeCorrelationOutput].self, from: data)
        } catch {
            print("[SanctuaryOrchestrator] JSON parsing error: \(error)")
            print("[SanctuaryOrchestrator] Response was: \(response.prefix(500))")
            throw SanctuaryError.invalidClaudeResponse("Failed to parse JSON: \(error.localizedDescription)")
        }
    }

    // MARK: - Persistence

    private func saveCorrelationInsights(
        _ correlations: [ClaudeCorrelationOutput],
        trigger: CorrelationTrigger
    ) async throws {
        for correlation in correlations {
            // Create metadata
            let metadata: [String: Any] = [
                "type": correlation.type,
                "dimensions": correlation.dimensions,
                "variables": correlation.variables,
                "direction": correlation.direction,
                "strength": correlation.strength,
                "pearsonR": correlation.pearsonR as Any,
                "effectSize": correlation.effectSize,
                "mechanism": correlation.mechanism,
                "action": correlation.action,
                "confidence": correlation.confidence,
                "supportingData": correlation.supportingData,
                "atomTypes": correlation.atomTypes,
                "trigger": trigger.rawValue,
                "generatedBy": "claude_sonnet_4.5",
                "generatedAt": ISO8601DateFormatter().string(from: Date())
            ]

            let metadataString = try? String(
                data: JSONSerialization.data(withJSONObject: metadata),
                encoding: .utf8
            )

            // Check if this correlation already exists (by matching variables)
            let existingAtoms = try await atomRepository.search(
                query: correlation.variables.joined(separator: " "),
                types: [.correlationInsight]
            )

            let existingMatch = existingAtoms.first { atom in
                guard let atomMeta = atom.metadataDict,
                      let atomVariables = atomMeta["variables"] as? [String] else {
                    return false
                }
                return Set(atomVariables) == Set(correlation.variables)
            }

            if let existing = existingMatch {
                // Update existing
                _ = try await atomRepository.update(uuid: existing.uuid) { atom in
                    atom.body = correlation.insight
                    atom.metadata = metadataString
                }
            } else {
                // Create new
                _ = try await atomRepository.create(
                    type: .correlationInsight,
                    title: "\(correlation.dimensions.first ?? "Cross")-Dimensional Insight",
                    body: correlation.insight,
                    metadata: metadataString
                )
            }
        }
    }

    // MARK: - Helpers

    private func getDimension(for metric: String) -> String? {
        let dimensionMap: [String: String] = [
            "hrv": "physiological",
            "hrv_rmssd": "physiological",
            "resting_hr": "physiological",
            "sleep_hours": "physiological",
            "deep_sleep_minutes": "physiological",
            "readiness_score": "physiological",
            "deep_work_minutes": "cognitive",
            "focus_score": "cognitive",
            "tasks_completed": "behavioral",
            "words_written": "creative",
            "content_reach": "creative",
            "journal_entries": "reflection",
            "emotional_valence": "reflection"
        ]
        return dimensionMap[metric]
    }

    private func calculateDataPoints(from context: EnhancedCorrelationContext) -> Int {
        var count = 0
        let base = context.baseContext

        if base.physiological != nil { count += 6 }
        if base.behavioral != nil { count += 6 }
        if base.cognitive != nil { count += 6 }
        if base.creative != nil { count += 6 }
        if base.reflection != nil { count += 6 }
        if base.knowledge != nil { count += 5 }

        count += context.recentJournalEntries.count

        return count
    }

    // MARK: - Status

    /// Get the last analysis result
    public func getLastResult() -> CorrelationAnalysisResult? {
        return lastResult
    }

    /// Check if analysis is currently running
    public func isAnalysisRunning() -> Bool {
        return isRunning
    }

    /// Get time since last analysis
    public func timeSinceLastAnalysis() -> TimeInterval? {
        guard let lastRun = lastRunDate else { return nil }
        return Date().timeIntervalSince(lastRun)
    }
}

// MARK: - Errors

public enum SanctuaryError: Error, LocalizedError {
    case analysisInProgress
    case invalidClaudeResponse(String)
    case dataAggregationFailed(String)
    case noDataAvailable

    public var errorDescription: String? {
        switch self {
        case .analysisInProgress:
            return "A Sanctuary analysis is already in progress"
        case .invalidClaudeResponse(let details):
            return "Invalid response from Claude: \(details)"
        case .dataAggregationFailed(let details):
            return "Failed to aggregate data: \(details)"
        case .noDataAvailable:
            return "Not enough data available for analysis"
        }
    }
}

// MARK: - Notification Integration

extension SanctuaryOrchestrator {

    /// Register for trigger events
    public func setupTriggerObservers() {
        // These would be called from various parts of the app:
        // - JournalEntryView.onSave() → checkAndTriggerAnalysis()
        // - HealthKitSync.onNewHRVData() → checkAndTriggerAnalysis()
        // - AppDelegate.applicationDidEnterBackground() → scheduled analysis
    }

    /// Called when a new journal entry is saved
    public func onJournalEntrySaved() async {
        do {
            _ = try await checkAndTriggerAnalysis()
        } catch {
            print("[SanctuaryOrchestrator] Trigger check failed: \(error)")
        }
    }

    /// Called when new HRV data arrives from HealthKit
    public func onNewHRVData() async {
        do {
            _ = try await checkAndTriggerAnalysis()
        } catch {
            print("[SanctuaryOrchestrator] Trigger check failed: \(error)")
        }
    }

    /// Called at midnight for scheduled analysis
    public func onMidnight() async {
        do {
            _ = try await runAnalysis(trigger: .scheduled)
        } catch {
            print("[SanctuaryOrchestrator] Scheduled analysis failed: \(error)")
        }
    }
}
