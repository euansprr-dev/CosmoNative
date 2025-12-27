import Foundation
import HealthKit

// MARK: - Readiness Calculator

/// Calculates daily readiness score based on multiple health inputs
/// Inspired by WHOOP recovery score and Oura readiness
/// Based on peer-reviewed research from Harvard, Stanford, and sports science literature
public actor ReadinessCalculator {

    private let healthStore: HKHealthStore
    private let atomFactory: HealthKitAtomFactory

    public init(
        healthStore: HKHealthStore = HealthKitConfiguration.shared.healthStore,
        atomFactory: HealthKitAtomFactory = HealthKitAtomFactory()
    ) {
        self.healthStore = healthStore
        self.atomFactory = atomFactory
    }

    // MARK: - Readiness Inputs

    public struct ReadinessInputs: Sendable {
        public let recentHRV: [Double]              // Last 7 days SDNN values
        public let baselineHRV: Double              // 30-day average
        public let lastNightSleep: HKImportedSleepMetadata?
        public let sleepConsistency: Double         // 0-100
        public let recentWorkouts: [HKImportedWorkoutMetadata]
        public let restingHR: Double
        public let baselineRestingHR: Double
        public let respiratoryRate: Double?
        public let bloodOxygen: Double?
        public let wristTemperatureDeviation: Double?

        public init(
            recentHRV: [Double],
            baselineHRV: Double,
            lastNightSleep: HKImportedSleepMetadata?,
            sleepConsistency: Double,
            recentWorkouts: [HKImportedWorkoutMetadata],
            restingHR: Double,
            baselineRestingHR: Double,
            respiratoryRate: Double? = nil,
            bloodOxygen: Double? = nil,
            wristTemperatureDeviation: Double? = nil
        ) {
            self.recentHRV = recentHRV
            self.baselineHRV = baselineHRV
            self.lastNightSleep = lastNightSleep
            self.sleepConsistency = sleepConsistency
            self.recentWorkouts = recentWorkouts
            self.restingHR = restingHR
            self.baselineRestingHR = baselineRestingHR
            self.respiratoryRate = respiratoryRate
            self.bloodOxygen = bloodOxygen
            self.wristTemperatureDeviation = wristTemperatureDeviation
        }
    }

    // MARK: - Readiness Calculation

    /// Calculate comprehensive readiness score
    /// Returns a score from 0-100 with detailed breakdown
    public func calculateReadiness(_ inputs: ReadinessInputs) -> HKReadinessScoreMetadata {
        // Component weights based on research
        // HRV is the strongest predictor of recovery status
        let weights = ReadinessWeights()

        // 1. HRV Contribution (40% weight)
        let hrvScore = calculateHRVScore(
            recent: inputs.recentHRV,
            baseline: inputs.baselineHRV
        )

        // 2. Sleep Contribution (30% weight)
        let sleepScore = calculateSleepScore(
            lastNight: inputs.lastNightSleep,
            consistency: inputs.sleepConsistency
        )

        // 3. Recovery Contribution (20% weight)
        let recoveryScore = calculateRecoveryScore(
            restingHR: inputs.restingHR,
            baseline: inputs.baselineRestingHR,
            recentStrain: inputs.recentWorkouts.map { $0.strainScore }
        )

        // 4. Strain Balance (10% weight)
        let strainBalance = calculateStrainBalance(inputs.recentWorkouts)

        // 5. Bonus/Penalty Modifiers (Apple Watch Ultra 3 specific)
        let modifiers = calculateModifiers(
            respiratoryRate: inputs.respiratoryRate,
            bloodOxygen: inputs.bloodOxygen,
            wristTempDeviation: inputs.wristTemperatureDeviation
        )

        // Weighted composite
        let rawScore = (
            hrvScore * weights.hrv +
            sleepScore * weights.sleep +
            recoveryScore * weights.recovery +
            strainBalance * weights.strainBalance
        )

        // Apply modifiers (can boost or penalize by up to 10%)
        let adjustedScore = rawScore * (1.0 + modifiers)

        // Clamp to 0-100
        let finalScore = min(100, max(0, adjustedScore))

        return HKReadinessScoreMetadata(
            date: Date(),
            overallScore: finalScore,
            hrvContribution: hrvScore,
            sleepContribution: sleepScore,
            recoveryContribution: recoveryScore,
            strainBalance: strainBalance,
            recommendation: generateRecommendation(finalScore, inputs: inputs)
        )
    }

    // MARK: - HRV Score

    private func calculateHRVScore(recent: [Double], baseline: Double) -> Double {
        guard !recent.isEmpty, baseline > 0 else { return 50 }  // Neutral score if no data

        // Calculate trend (are we improving or declining?)
        let recentAvg = recent.reduce(0, +) / Double(recent.count)
        let hrvTrend = (recentAvg - baseline) / baseline

        // Score based on trend
        // +30% above baseline = 100 score
        // At baseline = 70 score
        // -30% below baseline = 30 score
        let trendScore = mapToScore(hrvTrend, range: -0.3...0.3, outputRange: 30...100)

        // Also consider variance (high variance = less reliable recovery)
        let variance = calculateVariance(recent)
        let stabilityPenalty = min(variance / baseline * 50, 15)  // Max 15 point penalty

        return max(0, trendScore - stabilityPenalty)
    }

    private func calculateVariance(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let squaredDiffs = values.map { pow($0 - mean, 2) }
        return sqrt(squaredDiffs.reduce(0, +) / Double(values.count - 1))
    }

    // MARK: - Sleep Score

    private func calculateSleepScore(lastNight: HKImportedSleepMetadata?, consistency: Double) -> Double {
        guard let sleep = lastNight else { return 40 }  // Low score if no sleep data

        var score = 0.0

        // Duration score (7-9 hours optimal)
        let durationHours = sleep.totalDuration / 3600
        let durationScore: Double
        switch durationHours {
        case 7.0...9.0:
            durationScore = 100
        case 6.0..<7.0, 9.0..<10.0:
            durationScore = 80
        case 5.0..<6.0, 10.0..<11.0:
            durationScore = 60
        case 4.0..<5.0:
            durationScore = 40
        default:
            durationScore = 20
        }
        score += durationScore * 0.35  // 35% of sleep score

        // Efficiency score
        let efficiencyScore = sleep.sleepEfficiency * 100
        score += efficiencyScore * 0.25  // 25% of sleep score

        // Deep sleep score (15-25% is optimal)
        let totalSleepMinutes = sleep.deepSleepMinutes + sleep.remSleepMinutes + sleep.coreSleepMinutes
        let deepPercentage = totalSleepMinutes > 0 ? Double(sleep.deepSleepMinutes) / Double(totalSleepMinutes) : 0
        let deepScore: Double
        switch deepPercentage {
        case 0.15...0.25:
            deepScore = 100
        case 0.10..<0.15, 0.25..<0.30:
            deepScore = 80
        case 0.05..<0.10:
            deepScore = 60
        default:
            deepScore = 40
        }
        score += deepScore * 0.20  // 20% of sleep score

        // REM score (20-25% is optimal)
        let remPercentage = totalSleepMinutes > 0 ? Double(sleep.remSleepMinutes) / Double(totalSleepMinutes) : 0
        let remScore: Double
        switch remPercentage {
        case 0.20...0.25:
            remScore = 100
        case 0.15..<0.20, 0.25..<0.30:
            remScore = 80
        case 0.10..<0.15:
            remScore = 60
        default:
            remScore = 40
        }
        score += remScore * 0.10  // 10% of sleep score

        // Consistency score
        score += consistency * 0.10  // 10% of sleep score

        return score
    }

    // MARK: - Recovery Score

    private func calculateRecoveryScore(
        restingHR: Double,
        baseline: Double,
        recentStrain: [Double]
    ) -> Double {
        guard baseline > 0 else { return 50 }

        // Resting HR deviation (lower than baseline = good recovery)
        let hrDeviation = (restingHR - baseline) / baseline
        let hrScore = mapToScore(-hrDeviation, range: -0.15...0.15, outputRange: 30...100)

        // Recent strain load (accumulated strain in last 3 days)
        let recentStrainLoad = recentStrain.prefix(3).reduce(0, +)
        let strainPenalty: Double
        switch recentStrainLoad {
        case 0..<15:
            strainPenalty = 0
        case 15..<25:
            strainPenalty = 10
        case 25..<35:
            strainPenalty = 20
        case 35..<45:
            strainPenalty = 30
        default:
            strainPenalty = 40
        }

        return max(0, hrScore - strainPenalty)
    }

    // MARK: - Strain Balance

    private func calculateStrainBalance(_ workouts: [HKImportedWorkoutMetadata]) -> Double {
        guard !workouts.isEmpty else { return 70 }  // Neutral if no recent workouts

        // Calculate 7-day strain load
        let totalStrain = workouts.reduce(0.0) { $0 + $1.strainScore }

        // Optimal weekly strain: 30-60 (moderate, sustainable)
        // Too low (<20): Not challenging enough
        // Too high (>80): Overtraining risk
        let balanceScore: Double
        switch totalStrain {
        case 30...60:
            balanceScore = 100  // Optimal
        case 20..<30, 60..<70:
            balanceScore = 80   // Good
        case 10..<20, 70..<80:
            balanceScore = 60   // Fair
        case 0..<10:
            balanceScore = 50   // Undertrained
        default:
            balanceScore = 30   // Overtrained risk
        }

        return balanceScore
    }

    // MARK: - Apple Watch Ultra 3 Modifiers

    private func calculateModifiers(
        respiratoryRate: Double?,
        bloodOxygen: Double?,
        wristTempDeviation: Double?
    ) -> Double {
        var modifier = 0.0

        // Respiratory rate (12-20 breaths/min is normal)
        if let rr = respiratoryRate {
            if rr < 12 || rr > 20 {
                modifier -= 0.03  // 3% penalty for abnormal
            }
        }

        // Blood oxygen (95-100% is healthy)
        if let spo2 = bloodOxygen {
            if spo2 < 95 {
                modifier -= 0.05  // 5% penalty for low oxygen
            } else if spo2 >= 98 {
                modifier += 0.02  // 2% bonus for excellent
            }
        }

        // Wrist temperature (deviation from personal baseline)
        // High deviation can indicate illness
        if let tempDev = wristTempDeviation {
            if abs(tempDev) > 1.0 {  // More than 1C deviation
                modifier -= 0.05  // 5% penalty
            } else if abs(tempDev) > 0.5 {
                modifier -= 0.02  // 2% penalty
            }
        }

        return modifier
    }

    // MARK: - Recommendation Generation

    private func generateRecommendation(
        _ score: Double,
        inputs: ReadinessInputs
    ) -> HKReadinessRecommendation {
        switch score {
        case 85...100:
            return .peakPerformance(
                "You're primed for peak performance. Push hard today - your body is fully recovered."
            )

        case 70..<85:
            var message = "Solid recovery. Normal training recommended."
            if inputs.sleepConsistency < 70 {
                message += " Focus on sleep consistency for better gains."
            }
            return .goodToGo(message)

        case 50..<70:
            var message = "Recovery in progress. Light activity only."
            if let sleep = inputs.lastNightSleep, sleep.totalDuration < 6 * 3600 {
                message += " Prioritize sleep tonight."
            }
            if inputs.recentHRV.last ?? 0 < inputs.baselineHRV * 0.85 {
                message += " HRV is below baseline - stress management recommended."
            }
            return .moderate(message)

        case 30..<50:
            var message = "Your body needs rest. Focus on recovery."
            let recentStrain = inputs.recentWorkouts.prefix(3).map { $0.strainScore }.reduce(0, +)
            if recentStrain > 40 {
                message += " Recent training load is high - active recovery only."
            }
            return .restRecommended(message)

        default:
            return .restRequired(
                "Critical recovery needed. Rest completely today. If symptoms persist, consider consulting a healthcare provider."
            )
        }
    }

    // MARK: - Helper Functions

    private func mapToScore(_ value: Double, range: ClosedRange<Double>, outputRange: ClosedRange<Double> = 0...100) -> Double {
        let clampedValue = min(max(value, range.lowerBound), range.upperBound)
        let normalized = (clampedValue - range.lowerBound) / (range.upperBound - range.lowerBound)
        return outputRange.lowerBound + normalized * (outputRange.upperBound - outputRange.lowerBound)
    }

    // MARK: - Fetch All Inputs

    /// Fetch all required inputs from HealthKit for readiness calculation
    public func fetchReadinessInputs(for date: Date) async throws -> ReadinessInputs {
        async let hrvData = fetchHRVHistory(days: 7)
        async let hrvBaseline = fetchHRVBaseline(days: 30)
        async let sleepData = fetchLastNightSleep(for: date)
        async let sleepConsistency = calculateSleepConsistency(days: 7)
        async let recentWorkouts = fetchRecentWorkouts(days: 7)
        async let restingHRData = fetchRestingHR(for: date)
        async let restingHRBaseline = fetchRestingHRBaseline(days: 30)
        async let respiratoryRate = fetchRespiratoryRate(for: date)
        async let bloodOxygen = fetchBloodOxygen(for: date)
        async let wristTemp = fetchWristTemperature(for: date)

        return try await ReadinessInputs(
            recentHRV: hrvData,
            baselineHRV: hrvBaseline,
            lastNightSleep: sleepData,
            sleepConsistency: sleepConsistency,
            recentWorkouts: recentWorkouts,
            restingHR: restingHRData,
            baselineRestingHR: restingHRBaseline,
            respiratoryRate: respiratoryRate,
            bloodOxygen: bloodOxygen,
            wristTemperatureDeviation: wristTemp
        )
    }

    // MARK: - HealthKit Queries

    private func fetchHRVHistory(days: Int) async throws -> [Double] {
        let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate)!

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrvType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let values = (samples ?? []).compactMap { sample -> Double? in
                    guard let quantitySample = sample as? HKQuantitySample else { return nil }
                    return quantitySample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
                }

                continuation.resume(returning: values)
            }

            healthStore.execute(query)
        }
    }

    private func fetchHRVBaseline(days: Int) async throws -> Double {
        let hrvValues = try await fetchHRVHistory(days: days)
        guard !hrvValues.isEmpty else { return 60 }  // Default baseline
        return hrvValues.reduce(0, +) / Double(hrvValues.count)
    }

    private func fetchLastNightSleep(for date: Date) async throws -> HKImportedSleepMetadata? {
        // Would integrate with HealthKitAtomFactory
        // For now, return nil - actual implementation would query sleep data
        return nil
    }

    private func calculateSleepConsistency(days: Int) async throws -> Double {
        // Would calculate variance in sleep/wake times
        return 75  // Placeholder
    }

    private func fetchRecentWorkouts(days: Int) async throws -> [HKImportedWorkoutMetadata] {
        // Would integrate with HealthKitAtomFactory
        return []
    }

    private func fetchRestingHR(for date: Date) async throws -> Double {
        let restingHRType = HKQuantityType(.restingHeartRate)
        let dayStart = Calendar.current.startOfDay(for: date)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!

        let predicate = HKQuery.predicateForSamples(
            withStart: dayStart,
            end: dayEnd,
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: restingHRType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                if let sample = samples?.first as? HKQuantitySample {
                    let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    continuation.resume(returning: bpm)
                } else {
                    continuation.resume(returning: 60)  // Default
                }
            }

            healthStore.execute(query)
        }
    }

    private func fetchRestingHRBaseline(days: Int) async throws -> Double {
        // Similar to HRV baseline calculation
        return 58  // Placeholder
    }

    private func fetchRespiratoryRate(for date: Date) async throws -> Double? {
        let rrType = HKQuantityType(.respiratoryRate)
        let dayStart = Calendar.current.startOfDay(for: date)

        let predicate = HKQuery.predicateForSamples(
            withStart: dayStart,
            end: date,
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: rrType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                if let sample = samples?.first as? HKQuantitySample {
                    let rate = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    continuation.resume(returning: rate)
                } else {
                    continuation.resume(returning: nil)
                }
            }

            healthStore.execute(query)
        }
    }

    private func fetchBloodOxygen(for date: Date) async throws -> Double? {
        let spo2Type = HKQuantityType(.oxygenSaturation)
        let dayStart = Calendar.current.startOfDay(for: date)

        let predicate = HKQuery.predicateForSamples(
            withStart: dayStart,
            end: date,
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: spo2Type,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                if let sample = samples?.first as? HKQuantitySample {
                    let spo2 = sample.quantity.doubleValue(for: .percent()) * 100
                    continuation.resume(returning: spo2)
                } else {
                    continuation.resume(returning: nil)
                }
            }

            healthStore.execute(query)
        }
    }

    private func fetchWristTemperature(for date: Date) async throws -> Double? {
        guard #available(iOS 16.0, macOS 13.0, watchOS 9.0, *) else {
            return nil
        }

        let tempType = HKQuantityType(.appleSleepingWristTemperature)
        let dayStart = Calendar.current.startOfDay(for: date)

        let predicate = HKQuery.predicateForSamples(
            withStart: Calendar.current.date(byAdding: .day, value: -1, to: dayStart)!,
            end: dayStart,
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: tempType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                if let sample = samples?.first as? HKQuantitySample {
                    let tempDeviation = sample.quantity.doubleValue(for: .degreeCelsius())
                    continuation.resume(returning: tempDeviation)
                } else {
                    continuation.resume(returning: nil)
                }
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Create Readiness Atom

    /// Create a readiness score atom for storage
    public func createReadinessAtom(score: HKReadinessScoreMetadata) -> Atom {
        let metadataJSON: String
        if let data = try? JSONEncoder().encode(score),
           let json = String(data: data, encoding: .utf8) {
            metadataJSON = json
        } else {
            metadataJSON = "{}"
        }

        let scoreEmoji: String
        switch score.overallScore {
        case 85...100: scoreEmoji = "Peak"
        case 70..<85: scoreEmoji = "Good"
        case 50..<70: scoreEmoji = "Moderate"
        case 30..<50: scoreEmoji = "Low"
        default: scoreEmoji = "Rest"
        }

        return Atom.new(
            type: .recoveryScore,
            title: "Readiness: \(Int(score.overallScore))% (\(scoreEmoji))",
            body: score.recommendation.message,
            metadata: metadataJSON
        )
    }
}

// MARK: - Readiness Weights

private struct ReadinessWeights {
    let hrv: Double = 0.40        // 40% - Primary recovery indicator
    let sleep: Double = 0.30      // 30% - Foundation of recovery
    let recovery: Double = 0.20   // 20% - Cardiac recovery status
    let strainBalance: Double = 0.10  // 10% - Training load balance
}

// MARK: - Readiness Score Metadata (HealthKit)

public struct HKReadinessScoreMetadata: Codable, Sendable {
    public let date: Date
    public let overallScore: Double
    public let hrvContribution: Double
    public let sleepContribution: Double
    public let recoveryContribution: Double
    public let strainBalance: Double
    public let recommendation: HKReadinessRecommendation

    public init(
        date: Date,
        overallScore: Double,
        hrvContribution: Double,
        sleepContribution: Double,
        recoveryContribution: Double,
        strainBalance: Double,
        recommendation: HKReadinessRecommendation
    ) {
        self.date = date
        self.overallScore = overallScore
        self.hrvContribution = hrvContribution
        self.sleepContribution = sleepContribution
        self.recoveryContribution = recoveryContribution
        self.strainBalance = strainBalance
        self.recommendation = recommendation
    }

    public var scoreCategory: String {
        switch overallScore {
        case 85...100: return "Peak Performance"
        case 70..<85: return "Good to Go"
        case 50..<70: return "Moderate"
        case 30..<50: return "Rest Recommended"
        default: return "Rest Required"
        }
    }

    public var canPushHard: Bool {
        overallScore >= 70
    }
}
