import Foundation
import HealthKit

// MARK: - HealthKit Configuration

/// Comprehensive HealthKit configuration for Apple Watch Ultra 3 integration
/// Follows Apple's best practices for health data privacy and performance
public struct HealthKitConfiguration: Sendable {

    // MARK: - Singleton Access

    public static let shared = HealthKitConfiguration()

    // MARK: - Health Store

    public let healthStore: HKHealthStore

    public var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private init() {
        self.healthStore = HKHealthStore()
    }

    // MARK: - Read Permission Types

    /// All HealthKit data types we request read access for
    public var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []

        // Heart metrics (critical for NELO)
        types.insert(HKQuantityType(.heartRate))
        types.insert(HKQuantityType(.heartRateVariabilitySDNN))
        types.insert(HKQuantityType(.restingHeartRate))
        types.insert(HKQuantityType(.walkingHeartRateAverage))
        types.insert(HKQuantityType(.heartRateRecoveryOneMinute))

        // Apple Watch Ultra 3 specific
        types.insert(HKQuantityType(.oxygenSaturation))
        types.insert(HKQuantityType(.respiratoryRate))

        // Wrist temperature (Ultra feature)
        if #available(iOS 16.0, macOS 13.0, watchOS 9.0, *) {
            types.insert(HKQuantityType(.appleSleepingWristTemperature))
        }

        // Sleep analysis
        types.insert(HKCategoryType(.sleepAnalysis))

        // Activity metrics
        types.insert(HKQuantityType(.activeEnergyBurned))
        types.insert(HKQuantityType(.basalEnergyBurned))
        types.insert(HKQuantityType(.appleExerciseTime))
        types.insert(HKQuantityType(.appleStandTime))
        types.insert(HKQuantityType(.appleMoveTime))
        types.insert(HKQuantityType(.stepCount))
        types.insert(HKQuantityType(.distanceWalkingRunning))
        types.insert(HKQuantityType(.distanceCycling))
        types.insert(HKQuantityType(.distanceSwimming))
        types.insert(HKQuantityType(.flightsClimbed))
        types.insert(HKQuantityType(.vo2Max))

        // Workouts
        types.insert(HKWorkoutType.workoutType())

        // Mindfulness
        types.insert(HKCategoryType(.mindfulSession))

        // Nutrition (optional)
        types.insert(HKQuantityType(.dietaryWater))
        types.insert(HKQuantityType(.dietaryCaffeine))

        // Body measurements
        types.insert(HKQuantityType(.bodyMass))
        types.insert(HKQuantityType(.bodyMassIndex))
        types.insert(HKQuantityType(.bodyFatPercentage))

        return types
    }

    // MARK: - Write Permission Types

    /// Types we may write (minimal - Cosmo is primarily a reader)
    public var writeTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = []

        // Mindfulness sessions (for deep work tracking)
        types.insert(HKCategoryType(.mindfulSession))

        return types
    }

    // MARK: - Background Delivery Types

    /// Types that should trigger background delivery for real-time atoms
    public var backgroundDeliveryTypes: Set<HKObjectType> {
        [
            HKQuantityType(.heartRateVariabilitySDNN),
            HKCategoryType(.sleepAnalysis),
            HKWorkoutType.workoutType(),
            HKQuantityType(.restingHeartRate),
        ]
    }

    // MARK: - Authorization

    /// Request authorization for all health data types
    public func requestAuthorization() async throws -> Bool {
        guard isHealthDataAvailable else {
            throw HealthKitError.notAvailable
        }

        do {
            try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)
            return true
        } catch {
            throw HealthKitError.authorizationFailed(error)
        }
    }

    /// Check authorization status for a specific type
    public func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
        healthStore.authorizationStatus(for: type)
    }

    /// Check if we have authorization for critical health types
    public var hasCriticalAuthorization: Bool {
        let criticalTypes: [HKObjectType] = [
            HKQuantityType(.heartRateVariabilitySDNN),
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.restingHeartRate)
        ]

        return criticalTypes.allSatisfy { type in
            authorizationStatus(for: type) == .sharingAuthorized
        }
    }

    // MARK: - Background Delivery Setup

    /// Enable background delivery for real-time health data
    public func enableBackgroundDelivery() async throws {
        for type in backgroundDeliveryTypes {
            guard let sampleType = type as? HKSampleType else { continue }

            try await healthStore.enableBackgroundDelivery(
                for: sampleType,
                frequency: .immediate
            )
        }
    }

    /// Disable background delivery
    public func disableBackgroundDelivery() async throws {
        try await healthStore.disableAllBackgroundDelivery()
    }
}

// MARK: - HealthKit Error

public enum HealthKitError: LocalizedError {
    case notAvailable
    case authorizationFailed(Error)
    case queryFailed(Error)
    case noData
    case invalidSample
    case processingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device"
        case .authorizationFailed(let error):
            return "HealthKit authorization failed: \(error.localizedDescription)"
        case .queryFailed(let error):
            return "HealthKit query failed: \(error.localizedDescription)"
        case .noData:
            return "No health data available for the requested period"
        case .invalidSample:
            return "Invalid health sample received"
        case .processingFailed(let reason):
            return "Health data processing failed: \(reason)"
        }
    }
}

// MARK: - Health Data Window

/// Time windows for health data queries
public enum HealthDataWindow: Sendable {
    case today
    case yesterday
    case last7Days
    case last30Days
    case last90Days
    case custom(start: Date, end: Date)

    public var dateInterval: DateInterval {
        let calendar = Calendar.current
        let now = Date()

        switch self {
        case .today:
            let start = calendar.startOfDay(for: now)
            return DateInterval(start: start, end: now)

        case .yesterday:
            let todayStart = calendar.startOfDay(for: now)
            let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!
            return DateInterval(start: yesterdayStart, end: todayStart)

        case .last7Days:
            let start = calendar.date(byAdding: .day, value: -7, to: now)!
            return DateInterval(start: start, end: now)

        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -30, to: now)!
            return DateInterval(start: start, end: now)

        case .last90Days:
            let start = calendar.date(byAdding: .day, value: -90, to: now)!
            return DateInterval(start: start, end: now)

        case .custom(let start, let end):
            return DateInterval(start: start, end: end)
        }
    }
}

// MARK: - HRV Measurement Type

public enum HRVMeasurementType: String, Codable, Sendable {
    case nighttime      // During sleep - most reliable
    case resting        // Awake but resting
    case recovery       // Post-workout
    case spontaneous    // Any other time

    public var qualityWeight: Double {
        switch self {
        case .nighttime: return 1.0    // Highest quality
        case .resting: return 0.9
        case .recovery: return 0.8
        case .spontaneous: return 0.6
        }
    }
}

// MARK: - Sleep Stage

public enum SleepStage: String, Codable, Sendable {
    case awake
    case rem
    case core       // Light sleep (stages 1-2)
    case deep       // Deep sleep (stages 3-4)
    case inBed      // In bed but not asleep
    case unknown

    public static func from(healthKitValue: HKCategoryValueSleepAnalysis) -> SleepStage {
        switch healthKitValue {
        case .awake:
            return .awake
        case .asleepREM:
            return .rem
        case .asleepCore:
            return .core
        case .asleepDeep:
            return .deep
        case .inBed:
            return .inBed
        case .asleepUnspecified:
            return .unknown
        @unknown default:
            return .unknown
        }
    }
}

// MARK: - Workout Type Mapping

public enum CosmoWorkoutType: String, Codable, Sendable, CaseIterable {
    case running
    case cycling
    case swimming
    case walking
    case hiking
    case strength
    case hiit
    case yoga
    case pilates
    case rowing
    case elliptical
    case stairClimbing
    case crossTraining
    case functionalStrength
    case coreTraining
    case flexibility
    case cooldown
    case mindfulness
    case other

    public static func from(activityType: HKWorkoutActivityType) -> CosmoWorkoutType {
        switch activityType {
        case .running, .trackAndField:
            return .running
        case .cycling, .handCycling:
            return .cycling
        case .swimming, .surfingSports, .waterFitness:
            return .swimming
        case .walking:
            return .walking
        case .hiking:
            return .hiking
        case .traditionalStrengthTraining, .functionalStrengthTraining:
            return .strength
        case .highIntensityIntervalTraining, .crossTraining, .mixedCardio:
            return .hiit
        case .yoga:
            return .yoga
        case .pilates:
            return .pilates
        case .rowing:
            return .rowing
        case .elliptical:
            return .elliptical
        case .stairClimbing, .stairs:
            return .stairClimbing
        case .coreTraining:
            return .coreTraining
        case .flexibility:
            return .flexibility
        case .cooldown:
            return .cooldown
        case .mindAndBody:
            return .mindfulness
        default:
            return .other
        }
    }

    public var strainMultiplier: Double {
        switch self {
        case .hiit, .running, .swimming, .rowing:
            return 1.0      // High strain
        case .cycling, .stairClimbing, .elliptical:
            return 0.85
        case .strength, .functionalStrength, .crossTraining:
            return 0.8
        case .hiking, .walking:
            return 0.6
        case .yoga, .pilates:
            return 0.4
        case .flexibility, .cooldown:
            return 0.2
        case .mindfulness:
            return 0.1
        case .coreTraining:
            return 0.5
        case .other:
            return 0.5
        }
    }
}

// MARK: - Heart Rate Zone (HealthKit)

public struct HKHeartRateZone: Codable, Sendable {
    public let zone: Int           // 1-5
    public let name: String
    public let lowerBound: Int     // BPM
    public let upperBound: Int     // BPM
    public let timeInZone: TimeInterval
    public let percentageOfWorkout: Double

    public init(
        zone: Int,
        name: String,
        lowerBound: Int,
        upperBound: Int,
        timeInZone: TimeInterval,
        percentageOfWorkout: Double
    ) {
        self.zone = zone
        self.name = name
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.timeInZone = timeInZone
        self.percentageOfWorkout = percentageOfWorkout
    }

    public static func calculateZones(
        heartRateSamples: [Int],
        maxHeartRate: Int,
        duration: TimeInterval
    ) -> [HKHeartRateZone] {
        let zones = [
            (1, "Recovery", 0.50, 0.60),
            (2, "Fat Burn", 0.60, 0.70),
            (3, "Cardio", 0.70, 0.80),
            (4, "Hard", 0.80, 0.90),
            (5, "Peak", 0.90, 1.00)
        ]

        var zoneData: [Int: TimeInterval] = [:]
        let sampleDuration = duration / Double(heartRateSamples.count)

        for hr in heartRateSamples {
            let percentage = Double(hr) / Double(maxHeartRate)
            let zoneNumber = zones.first { percentage >= $0.2 && percentage < $0.3 }?.0 ?? 5
            zoneData[zoneNumber, default: 0] += sampleDuration
        }

        return zones.map { zone in
            let lower = Int(Double(maxHeartRate) * zone.2)
            let upper = Int(Double(maxHeartRate) * zone.3)
            let time = zoneData[zone.0] ?? 0

            return HKHeartRateZone(
                zone: zone.0,
                name: zone.1,
                lowerBound: lower,
                upperBound: upper,
                timeInZone: time,
                percentageOfWorkout: time / duration
            )
        }
    }
}

// MARK: - Readiness Recommendation (HealthKit)

public enum HKReadinessRecommendation: Codable, Sendable {
    case peakPerformance(String)
    case goodToGo(String)
    case moderate(String)
    case restRecommended(String)
    case restRequired(String)

    public var message: String {
        switch self {
        case .peakPerformance(let msg): return msg
        case .goodToGo(let msg): return msg
        case .moderate(let msg): return msg
        case .restRecommended(let msg): return msg
        case .restRequired(let msg): return msg
        }
    }

    public var color: String {
        switch self {
        case .peakPerformance: return "green"
        case .goodToGo: return "teal"
        case .moderate: return "yellow"
        case .restRecommended: return "orange"
        case .restRequired: return "red"
        }
    }

    public var canPushHard: Bool {
        switch self {
        case .peakPerformance, .goodToGo: return true
        default: return false
        }
    }
}

// MARK: - Health Percentile Data

/// Population percentile data for health metrics
/// Based on WHOOP, Oura, and academic research
public struct HealthPercentileData: Sendable {

    // HRV percentiles by age group (SDNN in ms)
    public static func hrvPercentile(hrvMs: Double, age: Int) -> Double {
        // Simplified - real implementation would use age-stratified tables
        let thresholds: [(percentile: Double, hrv: Double)] = [
            (0.01, 20),   // 1st percentile
            (0.05, 30),   // 5th
            (0.10, 35),   // 10th
            (0.25, 45),   // 25th
            (0.50, 60),   // 50th (median)
            (0.75, 80),   // 75th
            (0.90, 100),  // 90th
            (0.95, 120),  // 95th
            (0.99, 150),  // 99th
        ]

        // Age adjustment: HRV naturally decreases with age
        let ageAdjustment = age < 30 ? 1.0 : (1.0 - Double(age - 30) * 0.01)
        let adjustedHRV = hrvMs / ageAdjustment

        for (i, threshold) in thresholds.enumerated() {
            if adjustedHRV <= threshold.hrv {
                if i == 0 { return threshold.percentile }
                let prev = thresholds[i - 1]
                let ratio = (adjustedHRV - prev.hrv) / (threshold.hrv - prev.hrv)
                return prev.percentile + ratio * (threshold.percentile - prev.percentile)
            }
        }

        return 0.99
    }

    // Resting heart rate percentiles
    public static func restingHRPercentile(bpm: Int, age: Int) -> Double {
        // Lower is better for resting HR
        let thresholds: [(percentile: Double, bpm: Int)] = [
            (0.99, 40),   // 99th - elite athlete
            (0.95, 48),
            (0.90, 52),
            (0.75, 58),
            (0.50, 65),   // Median
            (0.25, 72),
            (0.10, 80),
            (0.05, 85),
            (0.01, 95),
        ]

        for (i, threshold) in thresholds.enumerated() {
            if bpm <= threshold.bpm {
                if i == 0 { return threshold.percentile }
                let prev = thresholds[i - 1]
                let ratio = Double(bpm - prev.bpm) / Double(threshold.bpm - prev.bpm)
                return prev.percentile - ratio * (prev.percentile - threshold.percentile)
            }
        }

        return 0.01
    }

    // Sleep efficiency percentiles
    public static func sleepEfficiencyPercentile(efficiency: Double) -> Double {
        // efficiency is 0-1
        let thresholds: [(percentile: Double, efficiency: Double)] = [
            (0.01, 0.65),
            (0.05, 0.70),
            (0.10, 0.75),
            (0.25, 0.80),
            (0.50, 0.85),
            (0.75, 0.90),
            (0.90, 0.93),
            (0.95, 0.95),
            (0.99, 0.98),
        ]

        for (i, threshold) in thresholds.enumerated() {
            if efficiency <= threshold.efficiency {
                if i == 0 { return threshold.percentile }
                let prev = thresholds[i - 1]
                let ratio = (efficiency - prev.efficiency) / (threshold.efficiency - prev.efficiency)
                return prev.percentile + ratio * (threshold.percentile - prev.percentile)
            }
        }

        return 0.99
    }
}
