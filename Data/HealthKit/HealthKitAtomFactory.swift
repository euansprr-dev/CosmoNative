import Foundation
import HealthKit

// MARK: - HealthKit Atom Factory

/// Converts HealthKit samples into Cosmo Atoms
/// Follows the "Everything is an Atom" principle
public actor HealthKitAtomFactory {

    private let healthStore: HKHealthStore
    private let configuration: HealthKitConfiguration

    public init(configuration: HealthKitConfiguration = .shared) {
        self.configuration = configuration
        self.healthStore = configuration.healthStore
    }

    // MARK: - Daily Health Fetch

    /// Fetch and convert all health data for a specific date
    public func fetchAndConvertDailyHealth(for date: Date) async throws -> [Atom] {
        var atoms: [Atom] = []

        // Fetch HRV measurements
        let hrvAtoms = try await fetchHRVMeasurements(for: .custom(
            start: Calendar.current.startOfDay(for: date),
            end: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date))!
        ))
        atoms.append(contentsOf: hrvAtoms)

        // Fetch sleep data
        if let sleepAtom = try await fetchSleepData(for: date) {
            atoms.append(sleepAtom)
        }

        // Fetch workouts
        let workoutAtoms = try await fetchWorkouts(for: .custom(
            start: Calendar.current.startOfDay(for: date),
            end: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date))!
        ))
        atoms.append(contentsOf: workoutAtoms)

        // Fetch resting heart rate
        if let restingHRAtom = try await fetchRestingHeartRate(for: date) {
            atoms.append(restingHRAtom)
        }

        // Fetch activity summary
        if let activityAtom = try await fetchActivitySummary(for: date) {
            atoms.append(activityAtom)
        }

        return atoms
    }

    // MARK: - HRV Measurement Conversion

    public func fetchHRVMeasurements(for window: HealthDataWindow) async throws -> [Atom] {
        let quantityType = HKQuantityType(.heartRateVariabilitySDNN)
        let interval = window.dateInterval

        let predicate = HKQuery.predicateForSamples(
            withStart: interval.start,
            end: interval.end,
            options: .strictStartDate
        )

        let samples = try await querySamples(
            type: quantityType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit
        )

        return samples.compactMap { sample -> Atom? in
            guard let quantitySample = sample as? HKQuantitySample else { return nil }
            return convertHRVSample(quantitySample)
        }
    }

    private func convertHRVSample(_ sample: HKQuantitySample) -> Atom {
        let hrvMs = sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))

        let measurementType = classifyHRVType(sample)
        let confidence = calculateHRVConfidence(sample)
        let context = inferHRVContext(sample)
        let percentile = HealthPercentileData.hrvPercentile(hrvMs: hrvMs, age: 30) // TODO: Get actual age

        let metadata = HKImportedHRVMetadata(
            hrvMs: hrvMs,
            measurementType: measurementType,
            confidence: confidence,
            context: context,
            deviceId: sample.device?.localIdentifier ?? "unknown",
            percentileRank: percentile
        )

        let metadataJSON: String
        if let data = try? JSONEncoder().encode(metadata),
           let json = String(data: data, encoding: .utf8) {
            metadataJSON = json
        } else {
            metadataJSON = "{}"
        }

        return Atom.new(
            type: .hrvReading,
            title: "HRV: \(Int(hrvMs))ms",
            body: generateHRVSummary(hrvMs: hrvMs, percentile: percentile),
            metadata: metadataJSON
        )
    }

    private func classifyHRVType(_ sample: HKQuantitySample) -> HRVMeasurementType {
        let hour = Calendar.current.component(.hour, from: sample.startDate)

        // Nighttime: 11 PM - 6 AM
        if hour >= 23 || hour < 6 {
            return .nighttime
        }

        // Check if during sleep (would need sleep data correlation)
        // For now, use time-based heuristics

        // Morning resting: 6 AM - 9 AM
        if hour >= 6 && hour < 9 {
            return .resting
        }

        return .spontaneous
    }

    private func calculateHRVConfidence(_ sample: HKQuantitySample) -> Double {
        // Confidence based on measurement conditions
        var confidence = 1.0

        // Device quality
        if sample.device?.name?.contains("Apple Watch") == true {
            confidence *= 0.95
        } else {
            confidence *= 0.8
        }

        // Duration of measurement
        let duration = sample.endDate.timeIntervalSince(sample.startDate)
        if duration < 60 {
            confidence *= 0.8  // Short measurement less reliable
        }

        return confidence
    }

    private func inferHRVContext(_ sample: HKQuantitySample) -> String {
        let hour = Calendar.current.component(.hour, from: sample.startDate)

        if hour >= 23 || hour < 6 {
            return "nighttime"
        } else if hour >= 6 && hour < 9 {
            return "morning"
        } else if hour >= 9 && hour < 12 {
            return "mid-morning"
        } else if hour >= 12 && hour < 14 {
            return "midday"
        } else if hour >= 14 && hour < 18 {
            return "afternoon"
        } else {
            return "evening"
        }
    }

    private func generateHRVSummary(hrvMs: Double, percentile: Double) -> String {
        let tier: String
        if percentile >= 0.90 {
            tier = "Elite"
        } else if percentile >= 0.75 {
            tier = "Excellent"
        } else if percentile >= 0.50 {
            tier = "Good"
        } else if percentile >= 0.25 {
            tier = "Average"
        } else {
            tier = "Below Average"
        }

        return "\(tier) HRV reading. Top \(Int((1 - percentile) * 100))% of population."
    }

    // MARK: - Sleep Data Conversion

    public func fetchSleepData(for date: Date) async throws -> Atom? {
        let sleepType = HKCategoryType(.sleepAnalysis)
        let calendar = Calendar.current

        // Sleep typically spans two calendar days, so look at 6PM previous day to noon current day
        let previousDay = calendar.date(byAdding: .day, value: -1, to: date)!
        let searchStart = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: previousDay)!
        let searchEnd = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)!

        let predicate = HKQuery.predicateForSamples(
            withStart: searchStart,
            end: searchEnd,
            options: .strictStartDate
        )

        let samples = try await queryCategorySamples(
            type: sleepType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit
        )

        guard !samples.isEmpty else { return nil }

        return convertSleepSamples(samples, for: date)
    }

    private func convertSleepSamples(_ samples: [HKCategorySample], for date: Date) -> Atom {
        let analysis = analyzeSleepSamples(samples)

        let metadata = HKImportedSleepMetadata(
            sleepStart: analysis.startTime,
            sleepEnd: analysis.endTime,
            totalDuration: analysis.duration,
            deepSleepMinutes: analysis.deepMinutes,
            remSleepMinutes: analysis.remMinutes,
            coreSleepMinutes: analysis.coreMinutes,
            awakeMinutes: analysis.awakeMinutes,
            sleepEfficiency: analysis.efficiency,
            respiratoryRate: analysis.avgRespiratoryRate,
            heartRateRange: analysis.heartRateRange
        )

        let metadataJSON: String
        if let data = try? JSONEncoder().encode(metadata),
           let json = String(data: data, encoding: .utf8) {
            metadataJSON = json
        } else {
            metadataJSON = "{}"
        }

        let durationHours = Int(analysis.duration / 3600)
        let durationMinutes = Int((analysis.duration.truncatingRemainder(dividingBy: 3600)) / 60)

        return Atom.new(
            type: .sleepRecord,
            title: "Sleep: \(durationHours)h \(durationMinutes)m",
            body: generateSleepSummary(analysis),
            metadata: metadataJSON
        )
    }

    private struct SleepAnalysis {
        let startTime: Date
        let endTime: Date
        let duration: TimeInterval
        let deepMinutes: Int
        let remMinutes: Int
        let coreMinutes: Int
        let awakeMinutes: Int
        let efficiency: Double
        let avgRespiratoryRate: Double?
        let heartRateRange: HKImportedHeartRateRange
    }

    private func analyzeSleepSamples(_ samples: [HKCategorySample]) -> SleepAnalysis {
        var deepMinutes = 0
        var remMinutes = 0
        var coreMinutes = 0
        var awakeMinutes = 0
        var inBedMinutes = 0

        var earliestStart = Date.distantFuture
        var latestEnd = Date.distantPast

        for sample in samples {
            let stage = SleepStage.from(healthKitValue: HKCategoryValueSleepAnalysis(rawValue: sample.value) ?? .asleepUnspecified)
            let duration = sample.endDate.timeIntervalSince(sample.startDate)
            let minutes = Int(duration / 60)

            if sample.startDate < earliestStart {
                earliestStart = sample.startDate
            }
            if sample.endDate > latestEnd {
                latestEnd = sample.endDate
            }

            switch stage {
            case .deep:
                deepMinutes += minutes
            case .rem:
                remMinutes += minutes
            case .core:
                coreMinutes += minutes
            case .awake:
                awakeMinutes += minutes
            case .inBed:
                inBedMinutes += minutes
            case .unknown:
                coreMinutes += minutes  // Default to core sleep
            }
        }

        let totalSleepMinutes = deepMinutes + remMinutes + coreMinutes
        let totalInBedMinutes = totalSleepMinutes + awakeMinutes + inBedMinutes
        let efficiency = totalInBedMinutes > 0 ? Double(totalSleepMinutes) / Double(totalInBedMinutes) : 0

        return SleepAnalysis(
            startTime: earliestStart,
            endTime: latestEnd,
            duration: TimeInterval(totalSleepMinutes * 60),
            deepMinutes: deepMinutes,
            remMinutes: remMinutes,
            coreMinutes: coreMinutes,
            awakeMinutes: awakeMinutes,
            efficiency: efficiency,
            avgRespiratoryRate: nil,  // Would need separate query
            heartRateRange: HKImportedHeartRateRange(min: 50, max: 70, average: 58)  // Placeholder
        )
    }

    private func generateSleepSummary(_ analysis: SleepAnalysis) -> String {
        let hours = Int(analysis.duration / 3600)
        let minutes = Int((analysis.duration.truncatingRemainder(dividingBy: 3600)) / 60)

        var summary = "Total sleep: \(hours)h \(minutes)m. "
        summary += "Deep: \(analysis.deepMinutes)m, REM: \(analysis.remMinutes)m. "
        summary += "Efficiency: \(Int(analysis.efficiency * 100))%."

        if analysis.efficiency >= 0.90 {
            summary += " Excellent sleep quality."
        } else if analysis.efficiency >= 0.80 {
            summary += " Good sleep quality."
        } else if analysis.efficiency >= 0.70 {
            summary += " Fair sleep quality."
        } else {
            summary += " Sleep quality needs improvement."
        }

        return summary
    }

    // MARK: - Workout Conversion

    public func fetchWorkouts(for window: HealthDataWindow) async throws -> [Atom] {
        let workoutType = HKWorkoutType.workoutType()
        let interval = window.dateInterval

        let predicate = HKQuery.predicateForSamples(
            withStart: interval.start,
            end: interval.end,
            options: .strictStartDate
        )

        let samples = try await querySamples(
            type: workoutType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit
        )

        var atoms: [Atom] = []
        for sample in samples {
            guard let workout = sample as? HKWorkout else { continue }
            let atom = await convertWorkout(workout)
            atoms.append(atom)
        }

        return atoms
    }

    private func convertWorkout(_ workout: HKWorkout) async -> Atom {
        let workoutType = CosmoWorkoutType.from(activityType: workout.workoutActivityType)
        let strainScore = calculateStrainScore(workout, type: workoutType)
        let zones = await fetchHeartRateZones(during: workout)

        let metadata = HKImportedWorkoutMetadata(
            workoutType: workoutType,
            duration: workout.duration,
            activeCalories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0,
            avgHeartRate: await fetchAverageHeartRate(during: workout),
            maxHeartRate: await fetchMaxHeartRate(during: workout),
            hrvRecovery: await fetchPostWorkoutHRV(workout),
            strainScore: strainScore,
            elevationGain: workout.totalFlightsClimbed?.doubleValue(for: .count()),
            distance: workout.totalDistance?.doubleValue(for: .meter()),
            zones: zones
        )

        let metadataJSON: String
        if let data = try? JSONEncoder().encode(metadata),
           let json = String(data: data, encoding: .utf8) {
            metadataJSON = json
        } else {
            metadataJSON = "{}"
        }

        let durationMinutes = Int(workout.duration / 60)

        return Atom.new(
            type: .workout,
            title: "\(workoutType.rawValue.capitalized) - \(durationMinutes)min",
            body: generateWorkoutSummary(workout, metadata: metadata),
            metadata: metadataJSON
        )
    }

    private func calculateStrainScore(_ workout: HKWorkout, type: CosmoWorkoutType) -> Double {
        // WHOOP-style strain score (0-21 scale)
        let baseDurationScore = min(workout.duration / 3600, 2.0) * 5  // Max 10 from duration
        let calorieScore = min((workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0) / 500, 5)  // Max 5
        let typeMultiplier = type.strainMultiplier

        let rawScore = (baseDurationScore + calorieScore) * typeMultiplier
        return min(rawScore, 21.0)
    }

    private func fetchAverageHeartRate(during workout: HKWorkout) async -> Int {
        let heartRateType = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )

        do {
            let samples = try await querySamples(
                type: heartRateType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit
            )

            let heartRates = samples.compactMap { sample -> Double? in
                guard let quantitySample = sample as? HKQuantitySample else { return nil }
                return quantitySample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            }

            guard !heartRates.isEmpty else { return 0 }
            return Int(heartRates.reduce(0, +) / Double(heartRates.count))
        } catch {
            return 0
        }
    }

    private func fetchMaxHeartRate(during workout: HKWorkout) async -> Int {
        let heartRateType = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )

        do {
            let samples = try await querySamples(
                type: heartRateType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit
            )

            let heartRates = samples.compactMap { sample -> Double? in
                guard let quantitySample = sample as? HKQuantitySample else { return nil }
                return quantitySample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            }

            return Int(heartRates.max() ?? 0)
        } catch {
            return 0
        }
    }

    private func fetchPostWorkoutHRV(_ workout: HKWorkout) async -> Double? {
        let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
        let recoveryWindow = workout.endDate.addingTimeInterval(1800)  // 30 min after workout

        let predicate = HKQuery.predicateForSamples(
            withStart: workout.endDate,
            end: recoveryWindow,
            options: .strictStartDate
        )

        do {
            let samples = try await querySamples(
                type: hrvType,
                predicate: predicate,
                limit: 1
            )

            guard let sample = samples.first as? HKQuantitySample else { return nil }
            return sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
        } catch {
            return nil
        }
    }

    private func fetchHeartRateZones(during workout: HKWorkout) async -> [HKHeartRateZone] {
        let heartRateType = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )

        do {
            let samples = try await querySamples(
                type: heartRateType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit
            )

            let heartRates = samples.compactMap { sample -> Int? in
                guard let quantitySample = sample as? HKQuantitySample else { return nil }
                return Int(quantitySample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
            }

            guard !heartRates.isEmpty else { return [] }

            let maxHR = 220 - 30  // Estimate, would use actual age
            return HKHeartRateZone.calculateZones(
                heartRateSamples: heartRates,
                maxHeartRate: maxHR,
                duration: workout.duration
            )
        } catch {
            return []
        }
    }

    private func generateWorkoutSummary(_ workout: HKWorkout, metadata: HKImportedWorkoutMetadata) -> String {
        var summary = "\(metadata.workoutType.rawValue.capitalized) workout. "

        let durationMinutes = Int(workout.duration / 60)
        summary += "Duration: \(durationMinutes) minutes. "

        if metadata.activeCalories > 0 {
            summary += "Calories: \(Int(metadata.activeCalories)). "
        }

        if metadata.avgHeartRate > 0 {
            summary += "Avg HR: \(metadata.avgHeartRate) bpm. "
        }

        summary += "Strain: \(String(format: "%.1f", metadata.strainScore))/21."

        return summary
    }

    // MARK: - Resting Heart Rate

    public func fetchRestingHeartRate(for date: Date) async throws -> Atom? {
        let restingHRType = HKQuantityType(.restingHeartRate)
        let dayStart = Calendar.current.startOfDay(for: date)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!

        let predicate = HKQuery.predicateForSamples(
            withStart: dayStart,
            end: dayEnd,
            options: .strictStartDate
        )

        let samples = try await querySamples(
            type: restingHRType,
            predicate: predicate,
            limit: 1,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
        )

        guard let sample = samples.first as? HKQuantitySample else { return nil }

        let bpm = Int(sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
        let percentile = HealthPercentileData.restingHRPercentile(bpm: bpm, age: 30)

        let metadata: [String: Any] = [
            "bpm": bpm,
            "percentile": percentile,
            "date": date.ISO8601Format()
        ]

        let metadataJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: metadata),
           let json = String(data: data, encoding: .utf8) {
            metadataJSON = json
        } else {
            metadataJSON = "{}"
        }

        return Atom.new(
            type: .restingHR,
            title: "Resting HR: \(bpm) bpm",
            body: "Resting heart rate in top \(Int((1 - percentile) * 100))% of population.",
            metadata: metadataJSON
        )
    }

    // MARK: - Activity Summary

    public func fetchActivitySummary(for date: Date) async throws -> Atom? {
        let calendar = Calendar.current
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        dateComponents.calendar = calendar

        let predicate = HKQuery.predicateForActivitySummary(with: dateComponents)

        let summaries = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKActivitySummary], Error>) in
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: summaries ?? [])
                }
            }
            healthStore.execute(query)
        }

        guard let summary = summaries.first else { return nil }

        let moveCalories = summary.activeEnergyBurned.doubleValue(for: .kilocalorie())
        let exerciseMinutes = summary.appleExerciseTime.doubleValue(for: .minute())
        let standHours = summary.appleStandHours.doubleValue(for: .count())

        let moveGoal = summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())
        let exerciseGoal = summary.appleExerciseTimeGoal.doubleValue(for: .minute())
        let standGoal = summary.appleStandHoursGoal.doubleValue(for: .count())

        let metadata: [String: Any] = [
            "moveCalories": moveCalories,
            "moveGoal": moveGoal,
            "moveProgress": moveGoal > 0 ? moveCalories / moveGoal : 0,
            "exerciseMinutes": exerciseMinutes,
            "exerciseGoal": exerciseGoal,
            "exerciseProgress": exerciseGoal > 0 ? exerciseMinutes / exerciseGoal : 0,
            "standHours": standHours,
            "standGoal": standGoal,
            "standProgress": standGoal > 0 ? standHours / standGoal : 0,
            "allRingsClosed": moveCalories >= moveGoal && exerciseMinutes >= exerciseGoal && standHours >= standGoal
        ]

        let metadataJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: metadata),
           let json = String(data: data, encoding: .utf8) {
            metadataJSON = json
        } else {
            metadataJSON = "{}"
        }

        let allClosed = moveCalories >= moveGoal && exerciseMinutes >= exerciseGoal && standHours >= standGoal

        return Atom.new(
            type: .activityRing,
            title: allClosed ? "All Rings Closed" : "Activity Rings",
            body: "Move: \(Int(moveCalories))/\(Int(moveGoal)) cal, Exercise: \(Int(exerciseMinutes))/\(Int(exerciseGoal)) min, Stand: \(Int(standHours))/\(Int(standGoal)) hr",
            metadata: metadataJSON
        )
    }

    // MARK: - Query Helpers

    private func querySamples(
        type: HKSampleType,
        predicate: NSPredicate,
        limit: Int,
        sortDescriptors: [NSSortDescriptor]? = nil
    ) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: limit,
                sortDescriptors: sortDescriptors
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            healthStore.execute(query)
        }
    }

    private func queryCategorySamples(
        type: HKCategoryType,
        predicate: NSPredicate,
        limit: Int
    ) async throws -> [HKCategorySample] {
        let samples = try await querySamples(type: type, predicate: predicate, limit: limit)
        return samples.compactMap { $0 as? HKCategorySample }
    }
}

// MARK: - HRV Measurement Metadata (HealthKit Import)

public struct HKImportedHRVMetadata: Codable, Sendable {
    public let hrvMs: Double
    public let measurementType: HRVMeasurementType
    public let confidence: Double
    public let context: String
    public let deviceId: String
    public let percentileRank: Double

    public init(
        hrvMs: Double,
        measurementType: HRVMeasurementType,
        confidence: Double,
        context: String,
        deviceId: String,
        percentileRank: Double
    ) {
        self.hrvMs = hrvMs
        self.measurementType = measurementType
        self.confidence = confidence
        self.context = context
        self.deviceId = deviceId
        self.percentileRank = percentileRank
    }
}

// MARK: - Sleep Cycle Metadata (HealthKit Import)

public struct HKImportedSleepMetadata: Codable, Sendable {
    public let sleepStart: Date
    public let sleepEnd: Date
    public let totalDuration: TimeInterval
    public let deepSleepMinutes: Int
    public let remSleepMinutes: Int
    public let coreSleepMinutes: Int
    public let awakeMinutes: Int
    public let sleepEfficiency: Double
    public let respiratoryRate: Double?
    public let heartRateRange: HKImportedHeartRateRange

    public init(
        sleepStart: Date,
        sleepEnd: Date,
        totalDuration: TimeInterval,
        deepSleepMinutes: Int,
        remSleepMinutes: Int,
        coreSleepMinutes: Int,
        awakeMinutes: Int,
        sleepEfficiency: Double,
        respiratoryRate: Double?,
        heartRateRange: HKImportedHeartRateRange
    ) {
        self.sleepStart = sleepStart
        self.sleepEnd = sleepEnd
        self.totalDuration = totalDuration
        self.deepSleepMinutes = deepSleepMinutes
        self.remSleepMinutes = remSleepMinutes
        self.coreSleepMinutes = coreSleepMinutes
        self.awakeMinutes = awakeMinutes
        self.sleepEfficiency = sleepEfficiency
        self.respiratoryRate = respiratoryRate
        self.heartRateRange = heartRateRange
    }
}

// MARK: - Heart Rate Range (HealthKit Import)

public struct HKImportedHeartRateRange: Codable, Sendable {
    public let min: Int
    public let max: Int
    public let average: Int

    public init(min: Int, max: Int, average: Int) {
        self.min = min
        self.max = max
        self.average = average
    }
}

// MARK: - Workout Session Metadata (HealthKit Import)

public struct HKImportedWorkoutMetadata: Codable, Sendable {
    public let workoutType: CosmoWorkoutType
    public let duration: TimeInterval
    public let activeCalories: Double
    public let avgHeartRate: Int
    public let maxHeartRate: Int
    public let hrvRecovery: Double?
    public let strainScore: Double
    public let elevationGain: Double?
    public let distance: Double?
    public let zones: [HKHeartRateZone]

    public init(
        workoutType: CosmoWorkoutType,
        duration: TimeInterval,
        activeCalories: Double,
        avgHeartRate: Int,
        maxHeartRate: Int,
        hrvRecovery: Double?,
        strainScore: Double,
        elevationGain: Double?,
        distance: Double?,
        zones: [HKHeartRateZone]
    ) {
        self.workoutType = workoutType
        self.duration = duration
        self.activeCalories = activeCalories
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.hrvRecovery = hrvRecovery
        self.strainScore = strainScore
        self.elevationGain = elevationGain
        self.distance = distance
        self.zones = zones
    }
}
