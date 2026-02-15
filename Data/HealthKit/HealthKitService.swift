// CosmoOS/Data/HealthKit/HealthKitService.swift
// Facade service for querying HealthKit data to populate dimension views
// Complements HealthKitSyncService (real-time observation) with on-demand queries

import Foundation
import HealthKit

// MARK: - Health Tier

/// Describes the data richness available based on user's Apple devices
public enum HealthTier: String, Sendable {
    case none           // HealthKit not connected or unavailable
    case iPhoneOnly     // Basic health data (steps, sleep analysis)
    case withWatch      // Full health data including HRV, detailed sleep stages
}

// MARK: - Query Result Types

public struct SleepQueryResult: Sendable {
    public let bedtime: Date
    public let wakeTime: Date
    public let totalHours: Double
    public let deepSleepMinutes: Int
    public let remSleepMinutes: Int
    public let coreSleepMinutes: Int
    public let awakeMinutes: Int
    public let efficiency: Double   // 0-100
}

public struct ActivityQueryResult: Sendable {
    public let steps: Int
    public let activeCalories: Double
    public let exerciseMinutes: Int
    public let standHours: Int
    public let flightsClimbed: Int
    public let walkingDistance: Double  // meters
}

// MARK: - HealthKit Query Service

/// On-demand query service for building dimension view data.
/// Uses the shared HealthKitConfiguration for authorization and health store access.
/// Named HealthKitQueryService to avoid collision with HealthKitService in HealthKitLevelIntegration.swift.
@MainActor
public final class HealthKitQueryService: ObservableObject {

    public static let shared = HealthKitQueryService()

    @Published public var hasAccess: Bool = false
    @Published public var tier: HealthTier = .none
    @Published public var isLoading: Bool = false

    private let healthStore: HKHealthStore
    private let configuration: HealthKitConfiguration

    // MARK: - Initialization

    public init(configuration: HealthKitConfiguration = .shared) {
        self.configuration = configuration
        self.healthStore = configuration.healthStore
    }

    public var isHealthKitAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - Authorization

    public func requestAccess() async {
        guard isHealthKitAvailable else {
            tier = .none
            return
        }

        do {
            let authorized = try await configuration.requestAuthorization()
            hasAccess = authorized
            if authorized {
                await detectTier()
            }
        } catch {
            hasAccess = false
            tier = .none
        }
    }

    // MARK: - Tier Detection

    /// Detect whether user has Watch data or only iPhone data
    public func detectTier() async {
        guard isHealthKitAvailable else {
            tier = .none
            return
        }

        // Check for HRV data in the last 48 hours — HRV requires Apple Watch
        let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
        let cutoff = Calendar.current.date(byAdding: .hour, value: -48, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: cutoff, end: Date(), options: .strictStartDate)

        let hrvSample = await fetchLatestSampleRaw(sampleType: hrvType, predicate: predicate)

        if hrvSample != nil {
            tier = .withWatch
        } else {
            // Check if we have any step data at all (iPhone minimum)
            let stepType = HKQuantityType(.stepCount)
            let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            let stepPredicate = HKQuery.predicateForSamples(withStart: weekAgo, end: Date(), options: .strictStartDate)
            let stepSample = await fetchLatestSampleRaw(sampleType: stepType, predicate: stepPredicate)

            tier = stepSample != nil ? .iPhoneOnly : .none
        }
    }

    // MARK: - Step Count

    public func fetchTodaySteps() async -> Int {
        let value = await fetchTodayCumulativeSum(type: .stepCount, unit: .count())
        return Int(value)
    }

    // MARK: - Activity Data

    public func fetchTodayActivity() async -> ActivityQueryResult {
        async let steps = fetchTodayCumulativeSum(type: .stepCount, unit: .count())
        async let calories = fetchTodayCumulativeSum(type: .activeEnergyBurned, unit: .kilocalorie())
        async let exercise = fetchTodayCumulativeSum(type: .appleExerciseTime, unit: .minute())
        async let stand = fetchTodayCumulativeSum(type: .appleStandTime, unit: .count())
        async let flights = fetchTodayCumulativeSum(type: .flightsClimbed, unit: .count())
        async let distance = fetchTodayCumulativeSum(type: .distanceWalkingRunning, unit: .meter())

        let s = await steps
        let c = await calories
        let e = await exercise
        let st = await stand
        let f = await flights
        let d = await distance

        return ActivityQueryResult(
            steps: Int(s),
            activeCalories: c,
            exerciseMinutes: Int(e),
            standHours: Int(st),
            flightsClimbed: Int(f),
            walkingDistance: d
        )
    }

    // MARK: - Sleep Data

    public func fetchLastNightSleep() async -> SleepQueryResult? {
        let sleepType = HKCategoryType(.sleepAnalysis)

        // Look for sleep samples in the last 24 hours
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .hour, value: -24, to: endDate)!

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )

        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, _ in
                continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            healthStore.execute(query)
        }

        guard !samples.isEmpty else { return nil }

        // Aggregate sleep stages
        var deepMinutes = 0
        var remMinutes = 0
        var coreMinutes = 0
        var awakeMinutes = 0
        var earliestBedtime: Date?
        var latestWake: Date?

        for sample in samples {
            let durationMinutes = Int(sample.endDate.timeIntervalSince(sample.startDate) / 60)
            let value = HKCategoryValueSleepAnalysis(rawValue: sample.value)

            switch value {
            case .asleepDeep:
                deepMinutes += durationMinutes
            case .asleepREM:
                remMinutes += durationMinutes
            case .asleepCore, .asleepUnspecified:
                coreMinutes += durationMinutes
            case .awake:
                awakeMinutes += durationMinutes
            case .inBed:
                break // Don't count in-bed as sleep
            default:
                break
            }

            // Track overall sleep window
            if value != .inBed {
                if earliestBedtime == nil || sample.startDate < earliestBedtime! {
                    earliestBedtime = sample.startDate
                }
                if latestWake == nil || sample.endDate > latestWake! {
                    latestWake = sample.endDate
                }
            }
        }

        guard let bedtime = earliestBedtime, let wakeTime = latestWake else { return nil }

        let totalSleepMinutes = deepMinutes + remMinutes + coreMinutes
        let totalHours = Double(totalSleepMinutes) / 60.0
        let timeInBedMinutes = Double(wakeTime.timeIntervalSince(bedtime)) / 60.0
        let efficiency = timeInBedMinutes > 0 ? (Double(totalSleepMinutes) / timeInBedMinutes) * 100 : 0

        return SleepQueryResult(
            bedtime: bedtime,
            wakeTime: wakeTime,
            totalHours: totalHours,
            deepSleepMinutes: deepMinutes,
            remSleepMinutes: remMinutes,
            coreSleepMinutes: coreMinutes,
            awakeMinutes: awakeMinutes,
            efficiency: min(100, efficiency)
        )
    }

    // MARK: - HRV

    public func fetchLatestHRV() async -> Double? {
        let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
        let sample = await fetchLatestQuantitySample(type: hrvType)
        return sample?.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
    }

    /// Fetch HRV trend for the last N days (one value per day)
    public func fetchHRVTrend(days: Int = 7) async -> [(date: Date, value: Double)] {
        let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: Date(),
            options: .strictStartDate
        )

        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrvType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, _ in
                continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }

        // Group by day, take daily average
        let calendar = Calendar.current
        var grouped: [Date: [Double]] = [:]

        for sample in samples {
            let dayStart = calendar.startOfDay(for: sample.startDate)
            let value = sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
            grouped[dayStart, default: []].append(value)
        }

        return grouped.sorted { $0.key < $1.key }.map { date, values in
            let avg = values.reduce(0, +) / Double(values.count)
            return (date: date, value: avg)
        }
    }

    // MARK: - Resting Heart Rate

    public func fetchRestingHR() async -> Double? {
        let rhrType = HKQuantityType(.restingHeartRate)
        let sample = await fetchLatestQuantitySample(type: rhrType)
        return sample?.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
    }

    // MARK: - Respiratory Rate

    public func fetchRespiratoryRate() async -> Double? {
        let rrType = HKQuantityType(.respiratoryRate)
        let sample = await fetchLatestQuantitySample(type: rrType)
        return sample?.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
    }

    // MARK: - Recent Workouts

    public func fetchRecentWorkouts(days: Int = 7) async -> [HKWorkout] {
        let workoutType = HKWorkoutType.workoutType()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: Date(),
            options: .strictStartDate
        )

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: 20,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, results, _ in
                continuation.resume(returning: (results as? [HKWorkout]) ?? [])
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Sleep Trend (last 7 nights)

    public func fetchSleepTrend(days: Int = 7) async -> [Int] {
        var scores: [Int] = []
        let calendar = Calendar.current

        for dayOffset in (1...days).reversed() {
            let targetDate = calendar.date(byAdding: .day, value: -dayOffset, to: Date())!
            let dayStart = calendar.startOfDay(for: targetDate)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

            let sleepType = HKCategoryType(.sleepAnalysis)
            let predicate = HKQuery.predicateForSamples(
                withStart: dayStart,
                end: dayEnd,
                options: .strictStartDate
            )

            let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: sleepType,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: nil
                ) { _, results, _ in
                    continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
                }
                healthStore.execute(query)
            }

            if samples.isEmpty {
                scores.append(0)
            } else {
                // Simple score: total sleep minutes / 4.8 (8 hours = 100)
                var totalSleepMinutes = 0
                for sample in samples {
                    let value = HKCategoryValueSleepAnalysis(rawValue: sample.value)
                    if value == .asleepDeep || value == .asleepREM || value == .asleepCore || value == .asleepUnspecified {
                        totalSleepMinutes += Int(sample.endDate.timeIntervalSince(sample.startDate) / 60)
                    }
                }
                let score = min(100, Int(Double(totalSleepMinutes) / 4.8))
                scores.append(score)
            }
        }

        return scores
    }

    // MARK: - Private Helpers

    private func fetchTodayCumulativeSum(type: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double {
        let quantityType = HKQuantityType(type)
        let predicate = HKQuery.predicateForSamples(
            withStart: Calendar.current.startOfDay(for: Date()),
            end: Date(),
            options: .strictStartDate
        )

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                let value = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }

    private func fetchLatestQuantitySample(type: HKQuantityType) async -> HKQuantitySample? {
        let dayStart = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        let predicate = HKQuery.predicateForSamples(
            withStart: dayStart,
            end: Date(),
            options: .strictStartDate
        )

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, results, _ in
                continuation.resume(returning: results?.first as? HKQuantitySample)
            }
            healthStore.execute(query)
        }
    }

    private func fetchLatestSampleRaw(sampleType: HKSampleType, predicate: NSPredicate) async -> HKSample? {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sampleType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, results, _ in
                continuation.resume(returning: results?.first)
            }
            healthStore.execute(query)
        }
    }
}
