// CosmoOS/AI/BigBrain/LivingIntelligenceEngine.swift
// Living Intelligence Engine - Makes Sanctuary feel telepathic and alive
//
// Philosophy:
// - Sanctuary is not a report that regenerates. It's a living neural dashboard.
// - Good insights persist and strengthen. Bad insights decay and vanish.
// - Only NEW data triggers analysis. We never recompute what we already know.
// - The system feels like it "knows" you - telepathic, not mechanical.
//
// Architecture:
// 1. Delta Detection: Only analyze data created since last sync
// 2. Intelligent Merge: New insights enhance existing ones, not replace
// 3. Lifecycle States: fresh → validated → established → stale → removed
// 4. Priority Scoring: Surface the most relevant insights dynamically
// 5. Novelty Detection: Mark truly new discoveries for user attention

import Foundation
import GRDB
import Combine

// MARK: - Insight Lifecycle State

/// Lifecycle state of an insight - determines display priority and styling
public enum InsightLifecycleState: String, Codable, Sendable {
    case fresh          // Just discovered (< 24h), show "NEW" badge
    case validated      // Confirmed by new data, high confidence
    case established    // Proven pattern (5+ validations), trustworthy
    case stale          // No validation in 7+ days, may be outdated
    case decaying       // Actively losing confidence, will be removed
    case removed        // Marked for cleanup (not displayed)

    /// Visual treatment for UI
    public var displayPriority: Int {
        switch self {
        case .fresh: return 100       // Always show new discoveries first
        case .validated: return 80
        case .established: return 60
        case .stale: return 20
        case .decaying: return 10
        case .removed: return 0
        }
    }

    /// Show "NEW" badge
    public var isNovel: Bool { self == .fresh }

    /// Show confidence warning
    public var isDecaying: Bool { self == .stale || self == .decaying }
}

// MARK: - Living Insight

/// An insight with full lifecycle tracking
public struct LivingInsight: Codable, Sendable, Identifiable {
    public let id: String                    // UUID
    public let sourceCorrelation: String?    // CausalityEngine correlation UUID if applicable
    public let claudeInsightId: String?      // Claude-generated insight ID if applicable

    // Core content
    public var type: LivingInsightType
    public var title: String
    public var description: String
    public var mechanism: String?            // WHY this correlation exists
    public var action: String?               // What user can do

    // Lifecycle
    public var lifecycleState: InsightLifecycleState
    public var createdAt: Date
    public var lastValidatedAt: Date
    public var lastModifiedAt: Date
    public var validationCount: Int          // Times confirmed by new data
    public var confidenceScore: Double       // 0-1, computed from multiple factors

    // Statistical backing
    public var pearsonR: Double?
    public var effectSize: Double?
    public var sampleSize: Int?
    public var pValue: Double?

    // Dimensions involved
    public var dimensions: [LevelDimension]
    public var variables: [String]           // Metric names

    // Display metadata
    public var isPinned: Bool                // User pinned, never auto-remove
    public var isDismissed: Bool             // User dismissed, don't show again
    public var viewCount: Int                // Times displayed
    public var lastViewedAt: Date?

    // Source tracking
    public var sourceType: InsightSourceType
    public var atomTypes: [AtomType]         // Which Atom types this relates to

    // Priority for display (computed)
    public var displayScore: Double {
        var score = Double(lifecycleState.displayPriority)

        // Boost for high confidence
        score += confidenceScore * 20

        // Boost for cross-dimensional (more interesting)
        if dimensions.count >= 2 { score += 15 }

        // Boost for actionable insights
        if action != nil { score += 10 }

        // Penalty for frequently viewed (show variety)
        score -= min(Double(viewCount) * 0.5, 20)

        // Boost for pinned
        if isPinned { score += 50 }

        return score
    }
}

/// Type of insight (for UI treatment)
/// Note: Named LivingInsightType to avoid conflict with other LivingInsightType enums
public enum LivingInsightType: String, Codable, Sendable {
    case correlation        // Statistical correlation discovered
    case prediction         // Forward-looking prediction
    case warning           // Declining trend or concern
    case achievement       // Milestone reached
    case pattern           // Behavioral pattern detected
    case recommendation    // Actionable suggestion
}

/// Source of the insight
public enum InsightSourceType: String, Codable, Sendable {
    case causalityEngine   // Local statistical analysis
    case claudeAnalysis    // Claude API deep analysis
    case semanticAnalysis  // NLP extraction
    case healthKit         // HealthKit data patterns
    case userFeedback      // User confirmed/created
}

// MARK: - Intelligence Sync State

/// Tracks what data has been analyzed
/// Note: Named IntelligenceSyncState to avoid conflict with SyncEngine.IntelligenceSyncState
public struct IntelligenceSyncState: Codable, Sendable {
    public let lastSyncAt: Date
    public let lastDataCutoff: Date          // Oldest data analyzed in last sync
    public let atomsAnalyzedCount: Int
    public let insightsGenerated: Int
    public let insightsValidated: Int
    public let insightsRemoved: Int
    public let claudeCallMade: Bool
    public let claudeTokensUsed: Int?
    public let syncDurationMs: Int

    /// Should we run Claude analysis?
    public static func shouldRunClaudeAnalysis(
        newAtomCount: Int,
        hoursSinceLastClaudeCall: Double
    ) -> Bool {
        // Run Claude if:
        // 1. At least 5 new atoms to analyze, OR
        // 2. It's been 12+ hours since last Claude call
        return newAtomCount >= 5 || hoursSinceLastClaudeCall >= 12
    }
}

// MARK: - Living Intelligence Engine

/// The core engine that makes Sanctuary feel alive.
///
/// Design principles:
/// 1. **Never regenerate everything** - Only analyze delta since last sync
/// 2. **Insights are living entities** - They grow stronger with validation or decay
/// 3. **Smart merging** - New insights enhance existing ones, not replace
/// 4. **Telepathic feel** - Surface the right insight at the right time
///
/// Sync cycle (every 12 hours):
/// 1. Load sync state - what have we already analyzed?
/// 2. Query new atoms since lastDataCutoff
/// 3. Run CausalityEngine on new data (local, fast)
/// 4. If enough new data OR 12h since Claude: run Claude analysis
/// 5. Merge new insights with existing (intelligent diff)
/// 6. Update lifecycle states (fresh → validated → stale)
/// 7. Save sync state
@MainActor
public class LivingIntelligenceEngine: ObservableObject {

    // MARK: - Singleton

    public static let shared = LivingIntelligenceEngine()

    // MARK: - Published State

    @Published public private(set) var insights: [LivingInsight] = []
    @Published public private(set) var lastIntelligenceSyncState: IntelligenceSyncState?
    @Published public private(set) var isSyncing: Bool = false
    @Published public private(set) var hasNewInsights: Bool = false
    @Published public private(set) var newInsightCount: Int = 0

    /// Alias for lastIntelligenceSyncState for convenience
    public var lastSyncState: IntelligenceSyncState? { lastIntelligenceSyncState }

    // MARK: - Dependencies

    private let database = CosmoDatabase.shared
    private lazy var causalityEngine = CausalityEngine()
    private let orchestrator = SanctuaryOrchestrator.shared

    // MARK: - Configuration

    /// How often to run full sync (12 hours)
    public static let syncIntervalHours: TimeInterval = 12

    /// Minimum new atoms to justify Claude call
    public static let minAtomsForClaudeCall: Int = 5

    /// Days without validation before insight becomes stale
    public static let staleDays: Int = 7

    /// Days without validation before insight starts decaying
    public static let decayStartDays: Int = 14

    /// Decay threshold for removal
    public static let removalConfidenceThreshold: Double = 0.2

    // MARK: - Timers

    private var syncTimer: Timer?
    private var lastClaudeCallDate: Date?

    private init() {}

    // MARK: - Lifecycle

    /// Start the Living Intelligence system
    public func start() async {
        // Load existing insights
        await loadInsights()

        // Load last sync state
        await loadIntelligenceSyncState()

        // Check if we need to sync now
        if shouldSyncNow() {
            await runSync()
        }

        // Schedule 12-hour sync timer
        scheduleSyncTimer()
    }

    /// Stop the engine
    public func stop() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    // MARK: - Sync Logic

    /// Check if sync is needed
    private func shouldSyncNow() -> Bool {
        guard let lastSync = lastIntelligenceSyncState?.lastSyncAt else {
            return true // Never synced
        }

        let hoursSinceSync = Date().timeIntervalSince(lastSync) / 3600
        return hoursSinceSync >= Self.syncIntervalHours
    }

    /// Schedule the 12-hour sync timer
    private func scheduleSyncTimer() {
        syncTimer?.invalidate()

        // Calculate next sync time
        let nextSyncDate: Date
        if let lastSync = lastIntelligenceSyncState?.lastSyncAt {
            nextSyncDate = lastSync.addingTimeInterval(Self.syncIntervalHours * 3600)
        } else {
            // First run: schedule 12 hours from now instead of immediately
            nextSyncDate = Date().addingTimeInterval(Self.syncIntervalHours * 3600)
        }

        // Minimum 60 seconds between syncs to prevent tight loops
        let delay = max(60, nextSyncDate.timeIntervalSinceNow)

        syncTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.runSync()
                // Schedule next sync
                self?.scheduleSyncTimer()
            }
        }

        print("[LivingIntelligence] Next sync scheduled for: \(nextSyncDate)")
    }

    /// Run the full sync cycle
    public func runSync(force: Bool = false) async {
        guard !isSyncing else {
            print("[LivingIntelligence] Sync already in progress, skipping")
            return
        }

        isSyncing = true
        let startTime = Date()
        print("[LivingIntelligence] Starting sync cycle...")

        defer {
            isSyncing = false
        }

        do {
            // Step 1: Determine data cutoff
            let dataCutoff = lastIntelligenceSyncState?.lastDataCutoff ?? Date.distantPast
            print("[LivingIntelligence] Analyzing data since: \(dataCutoff)")

            // Step 2: Count new atoms
            let newAtomCount = try await countNewAtoms(since: dataCutoff)
            print("[LivingIntelligence] Found \(newAtomCount) new atoms")

            guard newAtomCount > 0 || force else {
                print("[LivingIntelligence] No new data, skipping sync")
                // Still update sync state to prevent immediate re-trigger
                let skipSyncState = IntelligenceSyncState(
                    lastSyncAt: Date(),
                    lastDataCutoff: dataCutoff,
                    atomsAnalyzedCount: 0,
                    insightsGenerated: 0,
                    insightsValidated: 0,
                    insightsRemoved: 0,
                    claudeCallMade: false,
                    claudeTokensUsed: nil,
                    syncDurationMs: 0
                )
                lastIntelligenceSyncState = skipSyncState
                return
            }

            // Step 3: Run CausalityEngine (always, it's fast and local)
            let causalityInsights = try await runCausalityAnalysis()
            print("[LivingIntelligence] CausalityEngine found \(causalityInsights.count) correlations")

            // Step 4: Decide if we should call Claude
            let hoursSinceClaude = lastClaudeCallDate.map {
                Date().timeIntervalSince($0) / 3600
            } ?? 24

            var claudeInsights: [ClaudeCorrelationOutput] = []
            var claudeCallMade = false
            let claudeTokens: Int? = nil

            if IntelligenceSyncState.shouldRunClaudeAnalysis(
                newAtomCount: newAtomCount,
                hoursSinceLastClaudeCall: hoursSinceClaude
            ) || force {
                print("[LivingIntelligence] Running Claude analysis...")
                do {
                    let result = try await orchestrator.runAnalysis(
                        trigger: .scheduled,
                        timeframeDays: 30  // Shorter window for delta analysis
                    )
                    claudeInsights = result.correlations
                    claudeCallMade = true
                    lastClaudeCallDate = Date()
                    print("[LivingIntelligence] Claude returned \(claudeInsights.count) insights")
                } catch {
                    print("[LivingIntelligence] Claude analysis failed: \(error)")
                }
            }

            // Step 5: Merge insights
            let (validated, newCount, removed) = await mergeInsights(
                causalityInsights: causalityInsights,
                claudeInsights: claudeInsights
            )
            print("[LivingIntelligence] Merge result: \(validated) validated, \(newCount) new, \(removed) removed")

            // Step 6: Update lifecycle states
            await updateLifecycleStates()

            // Step 7: Save sync state
            let syncDuration = Int(Date().timeIntervalSince(startTime) * 1000)
            let syncState = IntelligenceSyncState(
                lastSyncAt: Date(),
                lastDataCutoff: Date(),
                atomsAnalyzedCount: newAtomCount,
                insightsGenerated: newCount,
                insightsValidated: validated,
                insightsRemoved: removed,
                claudeCallMade: claudeCallMade,
                claudeTokensUsed: claudeTokens,
                syncDurationMs: syncDuration
            )

            await saveIntelligenceSyncState(syncState)
            lastIntelligenceSyncState = syncState

            // Step 8: Update published state
            hasNewInsights = newCount > 0
            newInsightCount = newCount

            // Auto-clear "new" flag after delay
            if newCount > 0 {
                Task {
                    try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                    await MainActor.run {
                        self.hasNewInsights = false
                    }
                }
            }

            print("[LivingIntelligence] Sync complete in \(syncDuration)ms")

        } catch {
            print("[LivingIntelligence] Sync failed: \(error)")
        }
    }

    // MARK: - Data Queries

    private func countNewAtoms(since cutoff: Date) async throws -> Int {
        guard database.isReady else { return 0 }

        return try await database.asyncRead { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM atoms
                WHERE created_at > ?
                AND is_deleted = 0
            """, arguments: [cutoff.ISO8601Format()]) ?? 0
        }
    }

    private func runCausalityAnalysis() async throws -> [CorrelationInsight] {
        try await causalityEngine.getActiveInsights()
    }

    // MARK: - Insight Merging

    /// Intelligent merge of new insights with existing ones
    private func mergeInsights(
        causalityInsights: [CorrelationInsight],
        claudeInsights: [ClaudeCorrelationOutput]
    ) async -> (validated: Int, new: Int, removed: Int) {
        var validated = 0
        var newCount = 0
        let removed = 0

        // Create lookup for existing insights by variable combination
        var existingByVariables: [Set<String>: LivingInsight] = [:]
        for insight in insights {
            existingByVariables[Set(insight.variables)] = insight
        }

        // Process CausalityEngine insights
        for causalityInsight in causalityInsights {
            let variables = Set([causalityInsight.sourceMetric, causalityInsight.targetMetric])

            if var existing = existingByVariables[variables] {
                // VALIDATE: This insight is confirmed by new data
                existing.validationCount += 1
                existing.lastValidatedAt = Date()
                existing.confidenceScore = min(1.0, existing.confidenceScore + 0.05)

                // Update stats if significantly different
                if abs(existing.pearsonR ?? 0 - causalityInsight.coefficient) > 0.1 {
                    existing.pearsonR = (existing.pearsonR ?? 0 + causalityInsight.coefficient) / 2
                    existing.effectSize = (existing.effectSize ?? 0 + causalityInsight.effectSize) / 2
                }

                // Update lifecycle
                if existing.lifecycleState == .stale || existing.lifecycleState == .decaying {
                    existing.lifecycleState = .validated
                } else if existing.validationCount >= 5 {
                    existing.lifecycleState = .established
                }

                existingByVariables[variables] = existing
                validated += 1

            } else {
                // NEW: This is a genuinely new insight
                let newInsight = LivingInsight(
                    id: UUID().uuidString,
                    sourceCorrelation: causalityInsight.uuid,
                    claudeInsightId: nil,
                    type: causalityInsight.coefficient < 0 ? .warning : .correlation,
                    title: "\(causalityInsight.sourceMetric.capitalized) ↔ \(causalityInsight.targetMetric.capitalized)",
                    description: causalityInsight.humanDescription,
                    mechanism: nil,
                    action: causalityInsight.actionableAdvice,
                    lifecycleState: .fresh,
                    createdAt: Date(),
                    lastValidatedAt: Date(),
                    lastModifiedAt: Date(),
                    validationCount: 1,
                    confidenceScore: min(0.9, Double(causalityInsight.occurrences) / 50.0),
                    pearsonR: causalityInsight.coefficient,
                    effectSize: causalityInsight.effectSize,
                    sampleSize: causalityInsight.occurrences,
                    pValue: nil,
                    dimensions: determineDimensions(
                        source: causalityInsight.sourceMetric,
                        target: causalityInsight.targetMetric
                    ),
                    variables: [causalityInsight.sourceMetric, causalityInsight.targetMetric],
                    isPinned: false,
                    isDismissed: false,
                    viewCount: 0,
                    lastViewedAt: nil,
                    sourceType: .causalityEngine,
                    atomTypes: []
                )

                existingByVariables[variables] = newInsight
                newCount += 1
            }
        }

        // Process Claude insights
        for claudeInsight in claudeInsights {
            let variables = Set(claudeInsight.variables)

            if var existing = existingByVariables[variables] {
                // ENHANCE: Claude provides richer context to existing insight
                existing.mechanism = claudeInsight.mechanism
                existing.action = claudeInsight.action

                // Claude's confidence might override local stats
                if let claudePearson = claudeInsight.pearsonR {
                    existing.pearsonR = claudePearson
                }
                existing.effectSize = claudeInsight.effectSize
                existing.confidenceScore = confidenceFromString(claudeInsight.confidence)

                existing.lastModifiedAt = Date()
                existingByVariables[variables] = existing

            } else {
                // NEW from Claude
                let dimensions = claudeInsight.dimensions.compactMap { LevelDimension(rawValue: $0) }
                let atomTypes = claudeInsight.atomTypes.compactMap { AtomType(rawValue: $0) }

                let newInsight = LivingInsight(
                    id: claudeInsight.id,
                    sourceCorrelation: nil,
                    claudeInsightId: claudeInsight.id,
                    type: insightTypeFromClaudeType(claudeInsight.type),
                    title: claudeInsight.variables.joined(separator: " ↔ "),
                    description: claudeInsight.insight,
                    mechanism: claudeInsight.mechanism,
                    action: claudeInsight.action,
                    lifecycleState: .fresh,
                    createdAt: Date(),
                    lastValidatedAt: Date(),
                    lastModifiedAt: Date(),
                    validationCount: 1,
                    confidenceScore: confidenceFromString(claudeInsight.confidence),
                    pearsonR: claudeInsight.pearsonR,
                    effectSize: claudeInsight.effectSize,
                    sampleSize: nil,
                    pValue: nil,
                    dimensions: dimensions,
                    variables: claudeInsight.variables,
                    isPinned: false,
                    isDismissed: false,
                    viewCount: 0,
                    lastViewedAt: nil,
                    sourceType: .claudeAnalysis,
                    atomTypes: atomTypes
                )

                existingByVariables[variables] = newInsight
                newCount += 1
            }
        }

        // Rebuild insights array
        insights = Array(existingByVariables.values)
            .filter { !$0.isDismissed && $0.lifecycleState != .removed }
            .sorted { $0.displayScore > $1.displayScore }

        // Persist
        await saveInsights()

        return (validated, newCount, removed)
    }

    // MARK: - Lifecycle Management

    /// Update lifecycle states based on time since last validation
    private func updateLifecycleStates() async {
        let now = Date()
        var modified = false

        for i in insights.indices {
            let daysSinceValidation = now.timeIntervalSince(insights[i].lastValidatedAt) / 86400

            let previousState = insights[i].lifecycleState

            // Fresh → Validated (after 24h)
            if insights[i].lifecycleState == .fresh &&
               now.timeIntervalSince(insights[i].createdAt) > 86400 {
                insights[i].lifecycleState = .validated
                modified = true
            }

            // Validated → Established (after 5 validations)
            if insights[i].lifecycleState == .validated &&
               insights[i].validationCount >= 5 {
                insights[i].lifecycleState = .established
                modified = true
            }

            // Any → Stale (after 7 days without validation)
            if daysSinceValidation >= Double(Self.staleDays) &&
               insights[i].lifecycleState != .stale &&
               insights[i].lifecycleState != .decaying &&
               insights[i].lifecycleState != .fresh {
                insights[i].lifecycleState = .stale
                modified = true
            }

            // Stale → Decaying (after 14 days)
            if daysSinceValidation >= Double(Self.decayStartDays) &&
               insights[i].lifecycleState == .stale {
                insights[i].lifecycleState = .decaying
                insights[i].confidenceScore *= 0.9 // Apply decay
                modified = true
            }

            // Decaying → Removed (confidence below threshold)
            if insights[i].lifecycleState == .decaying &&
               insights[i].confidenceScore < Self.removalConfidenceThreshold &&
               !insights[i].isPinned {
                insights[i].lifecycleState = .removed
                modified = true
            }

            if insights[i].lifecycleState != previousState {
                print("[LivingIntelligence] Insight '\(insights[i].id.prefix(8))' transitioned: \(previousState) → \(insights[i].lifecycleState)")
            }
        }

        // Filter out removed
        insights = insights.filter { $0.lifecycleState != .removed }

        if modified {
            await saveInsights()
        }
    }

    // MARK: - User Actions

    /// Pin an insight (prevents auto-removal)
    public func pinInsight(_ id: String) async {
        if let index = insights.firstIndex(where: { $0.id == id }) {
            insights[index].isPinned = true
            await saveInsights()
        }
    }

    /// Dismiss an insight (won't show again)
    public func dismissInsight(_ id: String) async {
        if let index = insights.firstIndex(where: { $0.id == id }) {
            insights[index].isDismissed = true
            await saveInsights()
        }
    }

    /// Mark an insight as viewed
    public func markViewed(_ id: String) async {
        if let index = insights.firstIndex(where: { $0.id == id }) {
            insights[index].viewCount += 1
            insights[index].lastViewedAt = Date()
            // Don't save immediately to avoid too many writes
        }
    }

    // MARK: - Getters

    /// Get top N insights for display
    public func getTopInsights(limit: Int = 5) -> [LivingInsight] {
        Array(insights.prefix(limit))
    }

    /// Get insights for a specific dimension
    public func getInsights(for dimension: LevelDimension) -> [LivingInsight] {
        insights.filter { $0.dimensions.contains(dimension) }
    }

    /// Get only fresh (new) insights
    public func getFreshInsights() -> [LivingInsight] {
        insights.filter { $0.lifecycleState == .fresh }
    }

    /// Get actionable insights (have an action)
    public func getActionableInsights() -> [LivingInsight] {
        insights.filter { $0.action != nil }
    }

    // MARK: - Persistence

    private func loadInsights() async {
        guard database.isReady else { return }

        do {
            let atoms = try await database.asyncRead { db in
                try Atom
                    .filter(Column("type") == AtomType.livingInsight.rawValue)
                    .filter(Column("is_deleted") == false)
                    .fetchAll(db)
            }

            insights = atoms.compactMap { atom -> LivingInsight? in
                guard let data = atom.metadata?.data(using: .utf8),
                      let insight = try? JSONDecoder().decode(LivingInsight.self, from: data) else {
                    return nil
                }
                return insight
            }.sorted { $0.displayScore > $1.displayScore }

            print("[LivingIntelligence] Loaded \(insights.count) insights")

        } catch {
            print("[LivingIntelligence] Failed to load insights: \(error)")
        }
    }

    private func saveInsights() async {
        guard database.isReady else { return }

        // Capture insights before entering the async closure
        let insightsToSave = await MainActor.run { self.insights }

        do {
            try await database.asyncWrite { db in
                for insight in insightsToSave {
                    guard let metadataData = try? JSONEncoder().encode(insight),
                          let metadataString = String(data: metadataData, encoding: .utf8) else {
                        continue
                    }

                    // Upsert
                    if var existing = try Atom
                        .filter(Column("uuid") == insight.id)
                        .fetchOne(db) {
                        existing.metadata = metadataString
                        existing.body = insight.description
                        existing.updatedAt = Date().ISO8601Format()
                        try existing.save(db)
                    } else {
                        var atom = Atom.new(
                            type: .livingInsight,
                            title: insight.title,
                            body: insight.description
                        )
                        atom.uuid = insight.id
                        atom.metadata = metadataString
                        try atom.insert(db)
                    }
                }

                // Mark removed insights as deleted
                let activeIds = insightsToSave.map { $0.id }
                if !activeIds.isEmpty {
                    try db.execute(sql: """
                        UPDATE atoms SET is_deleted = 1
                        WHERE type = ?
                        AND uuid NOT IN (\(activeIds.map { "'\($0)'" }.joined(separator: ", ")))
                    """, arguments: [AtomType.livingInsight.rawValue])
                }
            }
        } catch {
            print("[LivingIntelligence] Failed to save insights: \(error)")
        }
    }

    private func loadIntelligenceSyncState() async {
        guard database.isReady else { return }

        do {
            let atom = try await database.asyncRead { db in
                try Atom
                    .filter(Column("type") == AtomType.syncState.rawValue)
                    .order(Column("created_at").desc)
                    .fetchOne(db)
            }

            if let atom = atom,
               let data = atom.metadata?.data(using: .utf8),
               let state = try? JSONDecoder().decode(IntelligenceSyncState.self, from: data) {
                lastIntelligenceSyncState = state
                lastClaudeCallDate = state.claudeCallMade ? state.lastSyncAt : nil
                print("[LivingIntelligence] Loaded sync state from \(state.lastSyncAt)")
            }
        } catch {
            print("[LivingIntelligence] Failed to load sync state: \(error)")
        }
    }

    private func saveIntelligenceSyncState(_ state: IntelligenceSyncState) async {
        guard database.isReady else { return }

        do {
            try await database.asyncWrite { db in
                guard let metadataData = try? JSONEncoder().encode(state),
                      let metadataString = String(data: metadataData, encoding: .utf8) else {
                    return
                }

                var atom = Atom.new(
                    type: .syncState,
                    title: "Living Intelligence Sync - \(state.lastSyncAt.formatted())"
                )
                atom.metadata = metadataString
                try atom.insert(db)

                // Clean up old sync states (keep last 10)
                try db.execute(sql: """
                    DELETE FROM atoms WHERE type = ? AND uuid NOT IN (
                        SELECT uuid FROM atoms WHERE type = ?
                        ORDER BY created_at DESC LIMIT 10
                    )
                """, arguments: [AtomType.syncState.rawValue, AtomType.syncState.rawValue])
            }
        } catch {
            print("[LivingIntelligence] Failed to save sync state: \(error)")
        }
    }

    // MARK: - Helpers

    private func determineDimensions(source: String, target: String) -> [LevelDimension] {
        let metricDimensions: [String: LevelDimension] = [
            "hrv": .physiological,
            "hrv_rmssd": .physiological,
            "resting_hr": .physiological,
            "sleep_hours": .physiological,
            "deep_sleep_minutes": .physiological,
            "readiness_score": .physiological,
            "workout_minutes": .physiological,
            "deep_work_minutes": .cognitive,
            "focus_score": .cognitive,
            "tasks_completed": .behavioral,
            "words_written": .creative,
            "content_reach": .creative,
            "content_engagement": .creative,
            "journal_entries": .reflection,
            "emotional_valence": .reflection,
            "xp_earned": .knowledge
        ]

        var dims: Set<LevelDimension> = []
        if let d1 = metricDimensions[source] { dims.insert(d1) }
        if let d2 = metricDimensions[target] { dims.insert(d2) }
        return Array(dims)
    }

    private func confidenceFromString(_ s: String) -> Double {
        switch s.lowercased() {
        case "high": return 0.9
        case "medium": return 0.6
        case "low": return 0.3
        default: return 0.5
        }
    }

    private func insightTypeFromClaudeType(_ type: String) -> LivingInsightType {
        switch type.lowercased() {
        case "cross_dimensional": return .correlation
        case "temporal": return .pattern
        case "warning": return .warning
        case "recommendation": return .recommendation
        default: return .correlation
        }
    }
}

// MARK: - AtomType Extension
// livingInsight and syncState cases are now defined in AtomType enum in Atom.swift
