// CosmoOS/Data/Models/LevelSystem/PerformancePredictionEngine.swift
// Performance Prediction Engine - Machine learning-style predictions from historical Atoms
// Predicts content performance and tracks prediction accuracy

import Foundation
import GRDB

// MARK: - Performance Prediction Engine

/// Predicts content performance based on historical Atom data.
/// Uses weighted historical analysis for predictions and tracks accuracy over time.
///
/// **Atom-First Architecture:**
/// - Predictions are stored as `.performancePrediction` metadata in content Atoms
/// - Prediction results are recorded as part of content performance tracking
/// - All historical data comes from `.contentPerformance` Atoms
actor PerformancePredictionEngine {

    // MARK: - Dependencies

    private let database: any DatabaseWriter

    // MARK: - Initialization

    @MainActor
    init(database: (any DatabaseWriter)? = nil) {
        self.database = database ?? (CosmoDatabase.shared.dbQueue! as any DatabaseWriter)
    }

    // MARK: - Prediction Generation

    /// Predict performance for new content
    func predictPerformance(
        platform: SocialPlatform,
        wordCount: Int,
        clientUUID: String? = nil
    ) async -> PerformancePrediction {

        // Get historical performance data
        let historicalData = await getHistoricalData(platform: platform, clientUUID: clientUUID)

        guard !historicalData.isEmpty else {
            // No historical data - return baseline prediction
            return baselinePrediction(for: platform)
        }

        // Calculate weighted averages (more recent = higher weight)
        let weightedReach = calculateWeightedAverage(
            data: historicalData.map { ($0.publishedAt, Double($0.impressions)) }
        )

        let weightedEngagement = calculateWeightedAverage(
            data: historicalData.map { ($0.publishedAt, $0.engagementRate) }
        )

        // Apply word count adjustment
        let avgWordCount = historicalData.reduce(0) { $0 + $1.wordCount } / historicalData.count
        let wordCountFactor = calculateWordCountFactor(
            targetWordCount: wordCount,
            avgWordCount: avgWordCount
        )

        // Apply time-of-day adjustment (if we have enough data)
        let timeOfDayFactor = calculateTimeOfDayFactor(
            historicalData: historicalData,
            predictedPostTime: Date()
        )

        // Calculate final prediction
        let predictedReach = Int(weightedReach * wordCountFactor * timeOfDayFactor)
        let predictedEngagement = weightedEngagement * wordCountFactor

        // Calculate confidence based on data quantity and recency
        let confidence = calculateConfidence(dataCount: historicalData.count)

        return PerformancePrediction(
            reach: predictedReach,
            engagementRate: predictedEngagement,
            viralProbability: calculateViralProbability(
                reach: predictedReach,
                engagement: predictedEngagement,
                platform: platform
            ),
            confidence: confidence,
            factors: PredictionFactors(
                wordCountFactor: wordCountFactor,
                timeOfDayFactor: timeOfDayFactor,
                historicalDataPoints: historicalData.count,
                platform: platform
            )
        )
    }

    /// Predict performance based on content type and historical patterns
    func predictByContentType(
        platform: SocialPlatform,
        mediaType: ContentMediaType,
        clientUUID: String? = nil
    ) async -> PerformancePrediction {

        let historicalData = await getHistoricalDataByMediaType(
            platform: platform,
            mediaType: mediaType,
            clientUUID: clientUUID
        )

        guard !historicalData.isEmpty else {
            return baselinePrediction(for: platform)
        }

        let avgReach = historicalData.reduce(0) { $0 + $1.impressions } / historicalData.count
        let avgEngagement = historicalData.reduce(0.0) { $0 + $1.engagementRate } / Double(historicalData.count)

        return PerformancePrediction(
            reach: avgReach,
            engagementRate: avgEngagement,
            viralProbability: calculateViralProbability(
                reach: avgReach,
                engagement: avgEngagement,
                platform: platform
            ),
            confidence: calculateConfidence(dataCount: historicalData.count),
            factors: PredictionFactors(
                wordCountFactor: 1.0,
                timeOfDayFactor: 1.0,
                historicalDataPoints: historicalData.count,
                platform: platform
            )
        )
    }

    // MARK: - Prediction Result Recording

    /// Record the result of a prediction for accuracy tracking
    func recordPredictionResult(
        contentUUID: String,
        predicted: Int,
        actual: Int
    ) async {
        let accuracy = predicted > 0 ? Double(actual) / Double(predicted) : 0
        let absoluteError = abs(actual - predicted)
        let percentError = predicted > 0 ? Double(absoluteError) / Double(predicted) : 0

        // Store prediction result as part of a system atom
        let resultMetadata = PredictionResultMetadata(
            contentUUID: contentUUID,
            predictedReach: predicted,
            actualReach: actual,
            accuracyRatio: accuracy,
            absoluteError: absoluteError,
            percentError: percentError,
            recordedAt: Date()
        )

        do {
            try await database.write { db in
                var atom = Atom.new(
                    type: .systemEvent,
                    title: "Prediction Result",
                    body: accuracy >= 0.8 ? "Accurate prediction" : (accuracy >= 0.5 ? "Moderate accuracy" : "Needs improvement")
                )
                if let data = try? JSONEncoder().encode(resultMetadata) {
                    atom.metadata = String(data: data, encoding: .utf8)
                }
                if let linkData = try? JSONEncoder().encode([
                    AtomLink(type: "content", uuid: contentUUID, entityType: "content")
                ]) {
                    atom.links = String(data: linkData, encoding: .utf8)
                }
                try atom.insert(db)
            }
        } catch {
            // Silently fail - prediction recording is non-critical
        }
    }

    // MARK: - Accuracy Analysis

    /// Get overall prediction accuracy
    func getOverallAccuracy() async throws -> PredictionAccuracyReport {
        let threeMonthsAgo = Calendar.current.date(byAdding: .month, value: -3, to: Date())!

        return try await database.read { db in
            let resultAtoms = try Atom
                .filter(Column("type") == AtomType.systemEvent.rawValue)
                .filter(Column("title") == "Prediction Result")
                .filter(Column("created_at") >= threeMonthsAgo.ISO8601Format())
                .fetchAll(db)

            guard !resultAtoms.isEmpty else {
                return PredictionAccuracyReport(
                    totalPredictions: 0,
                    avgAccuracyRatio: 0,
                    avgPercentError: 0,
                    within10Percent: 0,
                    within25Percent: 0,
                    within50Percent: 0,
                    overPredicted: 0,
                    underPredicted: 0
                )
            }

            var totalAccuracy = 0.0
            var totalError = 0.0
            var within10 = 0
            var within25 = 0
            var within50 = 0
            var over = 0
            var under = 0

            for atom in resultAtoms {
                guard let metadata = try? JSONDecoder().decode(
                    PredictionResultMetadata.self,
                    from: (atom.metadata ?? "{}").data(using: .utf8) ?? Data()
                ) else { continue }

                totalAccuracy += metadata.accuracyRatio
                totalError += metadata.percentError

                if metadata.percentError <= 0.10 { within10 += 1 }
                if metadata.percentError <= 0.25 { within25 += 1 }
                if metadata.percentError <= 0.50 { within50 += 1 }

                if metadata.actualReach > metadata.predictedReach {
                    under += 1  // We under-predicted
                } else if metadata.actualReach < metadata.predictedReach {
                    over += 1   // We over-predicted
                }
            }

            let count = Double(resultAtoms.count)

            return PredictionAccuracyReport(
                totalPredictions: resultAtoms.count,
                avgAccuracyRatio: totalAccuracy / count,
                avgPercentError: totalError / count,
                within10Percent: Double(within10) / count,
                within25Percent: Double(within25) / count,
                within50Percent: Double(within50) / count,
                overPredicted: over,
                underPredicted: under
            )
        }
    }

    // MARK: - Private Helpers

    private func getHistoricalData(
        platform: SocialPlatform,
        clientUUID: String?
    ) async -> [HistoricalPerformancePoint] {
        let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: Date())!

        do {
            return try await database.read { db in
                let query = Atom
                    .filter(Column("type") == AtomType.contentPerformance.rawValue)
                    .filter(Column("created_at") >= sixMonthsAgo.ISO8601Format())
                    .filter(sql: "json_extract(metadata, '$.platform') = ?", arguments: [platform.rawValue])

                let atoms = try query.order(Column("created_at").desc).limit(100).fetchAll(db)

                return atoms.compactMap { atom -> HistoricalPerformancePoint? in
                    guard let metadata = atom.metadataValue(as: ContentPerformanceMetadata.self) else {
                        return nil
                    }

                    // If client filter is specified, check the linked content
                    if let clientUUID = clientUUID {
                        guard let contentUUID = atom.link(ofType: "content")?.uuid else { return nil }

                        let contentAtom = try? Atom
                            .filter(Column("uuid") == contentUUID)
                            .fetchOne(db)

                        guard contentAtom?.links?.contains(clientUUID) == true else { return nil }
                    }

                    return HistoricalPerformancePoint(
                        impressions: metadata.impressions,
                        engagementRate: metadata.engagementRate,
                        isViral: metadata.isViral,
                        publishedAt: metadata.publishedAt,
                        wordCount: 0  // Would need to fetch from content atom
                    )
                }
            }
        } catch {
            return []
        }
    }

    private func getHistoricalDataByMediaType(
        platform: SocialPlatform,
        mediaType: ContentMediaType,
        clientUUID: String?
    ) async -> [HistoricalPerformancePoint] {
        // Similar to above but filtered by media type
        let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: Date())!

        do {
            return try await database.read { db in
                let atoms = try Atom
                    .filter(Column("type") == AtomType.contentPublish.rawValue)
                    .filter(Column("created_at") >= sixMonthsAgo.ISO8601Format())
                    .filter(sql: "json_extract(metadata, '$.platform') = ?", arguments: [platform.rawValue])
                    .filter(sql: "json_extract(metadata, '$.mediaType') = ?", arguments: [mediaType.rawValue])
                    .limit(50)
                    .fetchAll(db)

                // For each publish atom, find its performance data
                return atoms.compactMap { publishAtom -> HistoricalPerformancePoint? in
                    guard let contentUUID = publishAtom.link(ofType: "content")?.uuid else { return nil }

                    // Find performance atom for this content
                    guard let perfAtom = try? Atom
                        .filter(Column("type") == AtomType.contentPerformance.rawValue)
                        .filter(sql: "links LIKE ?", arguments: ["%\(contentUUID)%"])
                        .order(Column("created_at").desc)
                        .fetchOne(db),
                          let metadata = perfAtom.metadataValue(as: ContentPerformanceMetadata.self) else {
                        return nil
                    }

                    return HistoricalPerformancePoint(
                        impressions: metadata.impressions,
                        engagementRate: metadata.engagementRate,
                        isViral: metadata.isViral,
                        publishedAt: metadata.publishedAt,
                        wordCount: 0
                    )
                }
            }
        } catch {
            return []
        }
    }

    private func baselinePrediction(for platform: SocialPlatform) -> PerformancePrediction {
        // Default predictions based on platform type
        let baseline: (reach: Int, engagement: Double)

        switch platform {
        case .twitter:
            baseline = (5_000, 0.02)
        case .linkedin:
            baseline = (3_000, 0.025)
        case .instagram:
            baseline = (8_000, 0.04)
        case .tiktok:
            baseline = (15_000, 0.08)
        case .youtube:
            baseline = (10_000, 0.03)
        case .facebook:
            baseline = (4_000, 0.02)
        case .threads:
            baseline = (2_000, 0.03)
        case .substack:
            baseline = (1_000, 0.10)
        case .medium:
            baseline = (1_500, 0.05)
        case .other:
            baseline = (2_000, 0.03)
        }

        return PerformancePrediction(
            reach: baseline.reach,
            engagementRate: baseline.engagement,
            viralProbability: 0.01,  // 1% baseline viral probability
            confidence: 0.2,  // Low confidence without historical data
            factors: PredictionFactors(
                wordCountFactor: 1.0,
                timeOfDayFactor: 1.0,
                historicalDataPoints: 0,
                platform: platform
            )
        )
    }

    private func calculateWeightedAverage(data: [(Date, Double)]) -> Double {
        guard !data.isEmpty else { return 0 }

        let now = Date()
        var weightedSum = 0.0
        var totalWeight = 0.0

        for (date, value) in data {
            let daysAgo = now.timeIntervalSince(date) / 86400
            // Exponential decay: recent data weighted more heavily
            let weight = exp(-daysAgo / 30)  // 30-day half-life
            weightedSum += value * weight
            totalWeight += weight
        }

        return totalWeight > 0 ? weightedSum / totalWeight : 0
    }

    private func calculateWordCountFactor(targetWordCount: Int, avgWordCount: Int) -> Double {
        guard avgWordCount > 0 else { return 1.0 }

        let ratio = Double(targetWordCount) / Double(avgWordCount)

        // Slight penalty for very short or very long content
        if ratio < 0.5 { return 0.8 }
        if ratio > 2.0 { return 0.9 }
        return 1.0
    }

    private func calculateTimeOfDayFactor(
        historicalData: [HistoricalPerformancePoint],
        predictedPostTime: Date
    ) -> Double {
        // Simple time-of-day analysis
        let hour = Calendar.current.component(.hour, from: predictedPostTime)

        // Peak hours (8-10 AM, 12-2 PM, 6-8 PM)
        let peakHours = [8, 9, 10, 12, 13, 14, 18, 19, 20]

        if peakHours.contains(hour) {
            return 1.15  // 15% boost during peak hours
        } else if hour >= 23 || hour <= 5 {
            return 0.7  // 30% penalty for late night/early morning
        }

        return 1.0
    }

    private func calculateViralProbability(
        reach: Int,
        engagement: Double,
        platform: SocialPlatform
    ) -> Double {
        let threshold = platform.viralityThreshold

        let reachRatio = Double(reach) / Double(threshold.impressions)
        let engagementRatio = engagement / threshold.engagementRate

        // Logistic function to calculate probability
        let combined = (reachRatio + engagementRatio) / 2
        let probability = 1 / (1 + exp(-5 * (combined - 0.7)))

        return min(0.95, max(0.01, probability))
    }

    private func calculateConfidence(dataCount: Int) -> Double {
        // Confidence increases with more data, asymptotically approaching 1.0
        let confidence = 1 - exp(-Double(dataCount) / 20)
        return min(0.95, max(0.1, confidence))
    }
}

// MARK: - Supporting Types

struct PerformancePrediction: Sendable {
    let reach: Int
    let engagementRate: Double
    let viralProbability: Double
    let confidence: Double
    let factors: PredictionFactors
}

struct PredictionFactors: Sendable {
    let wordCountFactor: Double
    let timeOfDayFactor: Double
    let historicalDataPoints: Int
    let platform: SocialPlatform
}

struct HistoricalPerformancePoint {
    let impressions: Int
    let engagementRate: Double
    let isViral: Bool
    let publishedAt: Date
    let wordCount: Int
}

struct PredictionResultMetadata: Codable, Sendable {
    let contentUUID: String
    let predictedReach: Int
    let actualReach: Int
    let accuracyRatio: Double
    let absoluteError: Int
    let percentError: Double
    let recordedAt: Date
}

struct PredictionAccuracyReport: Sendable {
    let totalPredictions: Int
    let avgAccuracyRatio: Double
    let avgPercentError: Double
    let within10Percent: Double  // Percentage of predictions within 10%
    let within25Percent: Double
    let within50Percent: Double
    let overPredicted: Int
    let underPredicted: Int

    var isAccurate: Bool {
        within25Percent >= 0.5  // 50%+ predictions within 25% = accurate
    }
}
