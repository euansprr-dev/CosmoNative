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

protocol DimensionScoring {
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
        // Compute all dimensions in parallel instead of sequentially
        let providers = scoringProviders
        let results = await withTaskGroup(of: (LevelDimension, DimensionIndex).self) { group in
            for (dimension, provider) in providers {
                group.addTask { @MainActor in
                    let index = await provider.computeIndex()
                    return (dimension, index)
                }
            }
            var collected: [LevelDimension: DimensionIndex] = [:]
            for await (dimension, index) in group {
                collected[dimension] = index
            }
            return collected
        }
        var newIndices = results

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
