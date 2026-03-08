// CosmoOS/Data/Models/LevelSystem/DimensionIndexEngine.swift
// Computes real-time dimension scores and overall Sanctuary level
// Part of Sanctuary Dimensions PRD - WP0

import SwiftUI
import Combine

// MARK: - Trend

enum DimensionTrend: String, Codable {
    case rising
    case stable
    case falling

    var icon: String {
        switch self {
        case .rising: return "arrow.up.right"
        case .stable: return "arrow.right"
        case .falling: return "arrow.down.right"
        }
    }

    var color: Color {
        switch self {
        case .rising: return SanctuaryColors.Semantic.success
        case .stable: return SanctuaryColors.Text.tertiary
        case .falling: return SanctuaryColors.Semantic.danger
        }
    }
}

// MARK: - DimensionIndex

struct DimensionIndex: Equatable {
    let score: Double           // 0-100
    let confidence: Double      // 0-1 (how much data backs this)
    let trend: DimensionTrend   // rising, stable, falling
    let subScores: [String: Double]  // component breakdown
    let dataAge: TimeInterval   // freshness of underlying data

    static let empty = DimensionIndex(
        score: 0,
        confidence: 0,
        trend: .stable,
        subScores: [:],
        dataAge: .infinity
    )
}

// MARK: - DimensionScoring Protocol

@MainActor
protocol DimensionScoring: AnyObject {
    var dimensionId: String { get }
    func computeIndex() async -> DimensionIndex
}

// MARK: - DimensionIndexEngine

@MainActor
class DimensionIndexEngine: ObservableObject {
    static let shared = DimensionIndexEngine()

    @Published var dimensionIndices: [LevelDimension: DimensionIndex] = [:]
    @Published var sanctuaryLevel: Double = 0
    @Published var overallTrend: DimensionTrend = .stable

    // Weights from PRD
    private let weights: [LevelDimension: Double] = [
        .cognitive: 0.20,
        .creative: 0.20,
        .physiological: 0.15,
        .behavioral: 0.20,
        .knowledge: 0.15,
        .reflection: 0.10
    ]

    private var scoringProviders: [LevelDimension: DimensionScoring] = [:]
    private var refreshTimer: Timer?
    private var previousLevel: Double = 0

    func register(_ provider: DimensionScoring, for dimension: LevelDimension) {
        scoringProviders[dimension] = provider
    }

    func startTracking() {
        // Refresh every 60 seconds (dimension data changes slowly)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.recalculate()
            }
        }
        Task { await recalculate() }
    }

    func stopTracking() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func recalculate() async {
        // Keep this sequential for now to avoid Swift 6 sendability issues
        // with the shared ObservableObject-backed providers.
        var newIndices: [LevelDimension: DimensionIndex] = [:]
        for (dimension, provider) in scoringProviders {
            newIndices[dimension] = await provider.computeIndex()
        }

        // Preserve existing indices for dimensions without providers
        for dimension in LevelDimension.allCases {
            if newIndices[dimension] == nil {
                newIndices[dimension] = dimensionIndices[dimension] ?? .empty
            }
        }

        dimensionIndices = newIndices

        // Compute weighted harmonic mean
        let validIndices = newIndices.compactMap { (dim, index) -> (LevelDimension, DimensionIndex)? in
            guard index.confidence >= 0.3 else { return nil }
            return (dim, index)
        }

        previousLevel = sanctuaryLevel
        sanctuaryLevel = computeHarmonicMean(validIndices)

        // Determine overall trend
        let delta = sanctuaryLevel - previousLevel
        if delta > 1.0 {
            overallTrend = .rising
        } else if delta < -1.0 {
            overallTrend = .falling
        } else {
            overallTrend = .stable
        }
    }

    // Weighted harmonic mean computation
    // H = sum(w_i) / sum(w_i / x_i) — punishes imbalance
    private func computeHarmonicMean(_ indices: [(LevelDimension, DimensionIndex)]) -> Double {
        guard !indices.isEmpty else { return 0 }

        var weightSum: Double = 0
        var reciprocalSum: Double = 0

        for (dimension, index) in indices {
            let w = weights[dimension] ?? 0.15
            let score = max(index.score, 0.01) // Avoid division by zero
            weightSum += w
            reciprocalSum += w / score
        }

        guard reciprocalSum > 0 else { return 0 }
        return weightSum / reciprocalSum
    }

    /// Get the index for a specific dimension
    func index(for dimension: LevelDimension) -> DimensionIndex {
        dimensionIndices[dimension] ?? .empty
    }
}

// MARK: - Shared Dimension Workspace Coordination

@MainActor
final class DimensionWorkspaceCoordinator: ObservableObject {
    static let shared = DimensionWorkspaceCoordinator()

    @Published private(set) var activeLoads: Set<LevelDimension> = []

    let cognitiveProvider = CognitiveDataProvider()
    let creativeProvider = CreativeDimensionDataProvider()
    let physiologicalProvider = PhysiologicalDataProvider()
    let behavioralProvider = BehavioralDataProvider()
    let knowledgeProvider = KnowledgeDataProvider()
    let reflectionProvider = ReflectionDataProvider()

    private let engine = DimensionIndexEngine.shared
    private var hasStarted = false
    private var cancellables = Set<AnyCancellable>()

    private init() {
        bindProviderUpdates()
    }

    func start() async {
        guard !hasStarted else { return }

        engine.register(cognitiveProvider, for: .cognitive)
        engine.register(creativeProvider, for: .creative)
        engine.register(physiologicalProvider, for: .physiological)
        engine.register(behavioralProvider, for: .behavioral)
        engine.register(knowledgeProvider, for: .knowledge)
        engine.register(reflectionProvider, for: .reflection)
        engine.startTracking()
        hasStarted = true
    }

    func loadIfNeeded(_ dimension: LevelDimension) async {
        await start()
        guard shouldRefresh(dimension) else { return }
        await refresh(dimension)
    }

    func refresh(_ dimension: LevelDimension) async {
        activeLoads.insert(dimension)
        defer { activeLoads.remove(dimension) }

        switch dimension {
        case .cognitive:
            await cognitiveProvider.refreshData()
        case .creative:
            await creativeProvider.refreshData()
        case .physiological:
            if !physiologicalProvider.isConnected {
                await physiologicalProvider.connect()
            }
            await physiologicalProvider.refreshData()
        case .behavioral:
            await behavioralProvider.refreshData()
        case .knowledge:
            await knowledgeProvider.refreshData()
        case .reflection:
            await reflectionProvider.refreshData()
        }

        await engine.recalculate()
    }

    func isLoading(_ dimension: LevelDimension) -> Bool {
        if activeLoads.contains(dimension) {
            return true
        }

        switch dimension {
        case .cognitive:
            return cognitiveProvider.isLoading
        case .creative:
            return creativeProvider.isLoading
        case .physiological:
            return physiologicalProvider.isLoading
        case .behavioral:
            return behavioralProvider.isLoading
        case .knowledge:
            return knowledgeProvider.isLoading
        case .reflection:
            return reflectionProvider.isLoading
        }
    }

    func lastRefreshDate(for dimension: LevelDimension) -> Date? {
        switch dimension {
        case .cognitive:
            return cognitiveProvider.lastRefreshDate
        case .creative:
            return creativeProvider.lastRefreshDate
        case .physiological:
            return physiologicalProvider.lastRefreshDate
        case .behavioral:
            return behavioralProvider.lastRefreshDate
        case .knowledge:
            return knowledgeProvider.lastRefreshDate
        case .reflection:
            return reflectionProvider.lastRefreshDate
        }
    }

    func freshnessLabel(for dimension: LevelDimension) -> String {
        guard let lastRefreshDate = lastRefreshDate(for: dimension) else {
            return "Not loaded"
        }

        let elapsed = Int(Date().timeIntervalSince(lastRefreshDate))
        if elapsed < 60 {
            return "Updated just now"
        }
        if elapsed < 3600 {
            return "Updated \(elapsed / 60)m ago"
        }
        return "Updated \(elapsed / 3600)h ago"
    }

    func index(for dimension: LevelDimension) -> DimensionIndex {
        engine.index(for: dimension)
    }

    func navigateToDimension(_ dimension: LevelDimension) {
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.navigateToDimension,
            object: nil,
            userInfo: CosmoNotification.Navigation.DimensionPayload(dimension: dimension).userInfo
        )
    }

    func openDimensionAsPane(_ dimension: LevelDimension) {
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.openDimensionAsPane,
            object: nil,
            userInfo: CosmoNotification.Navigation.DimensionPayload(dimension: dimension).userInfo
        )
    }

    func navigateToCommandCenter() {
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.navigateToCommandCenter,
            object: nil
        )
    }

    func navigateToThinkspace(preferredId: String? = nil) {
        let manager = ThinkspaceManager.shared
        let targetId = preferredId
            ?? manager.currentThinkspace?.id
            ?? manager.sidebarThinkspaces.first?.id

        guard let targetId else { return }

        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.navigateToThinkspaceById,
            object: nil,
            userInfo: CosmoNotification.Navigation.ThinkspacePayload(thinkspaceId: targetId).userInfo
        )
    }

    func openAtomInFocusMode(uuid: String) {
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.openBlockInFocusMode,
            object: nil,
            userInfo: ["atomUUID": uuid]
        )
    }

    func openAtomAsPane(uuid: String) async {
        guard let atom = try? await AtomRepository.shared.fetch(uuid: uuid),
              let atomId = atom.id
        else {
            return
        }

        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.openAsPane,
            object: nil,
            userInfo: [
                "type": entityType(for: atom.type),
                "id": atomId
            ]
        )
    }

    func showCommandPalette() {
        NotificationCenter.default.post(name: CosmoNotification.Navigation.showCommandPalette, object: nil)
    }

    func showSettings() {
        NotificationCenter.default.post(name: CosmoNotification.Navigation.showSettings, object: nil)
    }

    func openCreatorDatabase() {
        NotificationCenter.default.post(name: Notification.Name("openCreatorDatabase"), object: nil)
    }

    func startQuickDeepWorkSession() {
        DeepWorkSessionEngine.shared.startSession(
            taskUUID: nil,
            taskTitle: "Dimension Session",
            intent: .deepThink,
            plannedMinutes: 45
        )
    }

    private func shouldRefresh(_ dimension: LevelDimension) -> Bool {
        guard let date = lastRefreshDate(for: dimension) else { return true }
        return Date().timeIntervalSince(date) > 300
    }

    private func entityType(for atomType: AtomType) -> EntityType {
        switch atomType {
        case .idea:
            return .idea
        case .task, .scheduleBlock:
            return .task
        case .content, .contentDraft, .contentPerformance:
            return .content
        case .research:
            return .research
        case .connection, .clientProfile:
            return .connection
        case .project:
            return .project
        case .note, .journalEntry, .journalInsight:
            return .note
        case .thinkspace:
            return .thinkspace
        default:
            return .idea
        }
    }

    private func bindProviderUpdates() {
        let publishers = [
            cognitiveProvider.objectWillChange.eraseToAnyPublisher(),
            creativeProvider.objectWillChange.eraseToAnyPublisher(),
            physiologicalProvider.objectWillChange.eraseToAnyPublisher(),
            behavioralProvider.objectWillChange.eraseToAnyPublisher(),
            knowledgeProvider.objectWillChange.eraseToAnyPublisher(),
            reflectionProvider.objectWillChange.eraseToAnyPublisher(),
            engine.objectWillChange.eraseToAnyPublisher()
        ]

        publishers.forEach { publisher in
            publisher
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &cancellables)
        }
    }
}
