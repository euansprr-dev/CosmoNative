// CosmoOS/Data/Models/LevelSystem/PhysiologyMetadata.swift
// Metadata structures for Apple Watch Ultra 3 health data
// Supports HRV, sleep, workouts, readiness, and other physiological metrics

import Foundation

// MARK: - HRV Measurement Metadata

/// Type of HRV measurement
enum HRVType: String, Codable, Sendable {
    case nighttime          // During sleep
    case resting            // Awake but at rest
    case recovery           // Post-workout
    case onDemand           // Manual measurement
}

/// Metadata for hrvMeasurement atoms
struct HRVMeasurementMetadata: Codable, Sendable {
    /// HRV value in milliseconds (SDNN)
    let hrvMs: Double

    /// Type of measurement
    let measurementType: HRVType

    /// Measurement confidence (0-1)
    let confidence: Double

    /// Context of measurement (e.g., "post-workout", "morning", "evening")
    let context: String?

    /// Device identifier
    let deviceId: String

    /// Percentile rank vs. population (age/gender adjusted)
    let percentileRank: Double?

    /// Comparison to personal 7-day baseline
    let vsBaseline: Double?

    /// Heart rate during measurement
    let heartRateDuringMeasurement: Int?

    /// Measurement duration in seconds
    let durationSeconds: Int?

    init(
        hrvMs: Double,
        measurementType: HRVType,
        confidence: Double = 1.0,
        context: String? = nil,
        deviceId: String = "unknown",
        percentileRank: Double? = nil,
        vsBaseline: Double? = nil,
        heartRateDuringMeasurement: Int? = nil,
        durationSeconds: Int? = nil
    ) {
        self.hrvMs = hrvMs
        self.measurementType = measurementType
        self.confidence = confidence
        self.context = context
        self.deviceId = deviceId
        self.percentileRank = percentileRank
        self.vsBaseline = vsBaseline
        self.heartRateDuringMeasurement = heartRateDuringMeasurement
        self.durationSeconds = durationSeconds
    }
}

// MARK: - Resting Heart Rate Metadata

/// Metadata for restingHR atoms
struct RestingHRMetadata: Codable, Sendable {
    /// Resting heart rate in BPM
    let bpm: Int

    /// Date of measurement
    let measurementDate: Date

    /// Comparison to 7-day average
    let vs7DayAverage: Double?

    /// Comparison to 30-day average
    let vs30DayAverage: Double?

    /// Device identifier
    let deviceId: String

    init(
        bpm: Int,
        measurementDate: Date = Date(),
        vs7DayAverage: Double? = nil,
        vs30DayAverage: Double? = nil,
        deviceId: String = "unknown"
    ) {
        self.bpm = bpm
        self.measurementDate = measurementDate
        self.vs7DayAverage = vs7DayAverage
        self.vs30DayAverage = vs30DayAverage
        self.deviceId = deviceId
    }
}

// MARK: - Sleep Cycle Metadata

/// Heart rate range during a period
struct HeartRateRange: Codable, Sendable {
    let min: Int
    let max: Int
    let average: Double

    init(min: Int, max: Int, average: Double) {
        self.min = min
        self.max = max
        self.average = average
    }
}

/// Metadata for sleepCycle atoms
struct SleepCycleMetadata: Codable, Sendable {
    /// When sleep started
    let sleepStart: Date

    /// When sleep ended
    let sleepEnd: Date

    /// Total time in bed (seconds)
    let totalDuration: TimeInterval

    /// Time in deep sleep (minutes)
    let deepSleepMinutes: Int

    /// Time in REM sleep (minutes)
    let remSleepMinutes: Int

    /// Time in core/light sleep (minutes)
    let coreSleepMinutes: Int

    /// Time awake during sleep period (minutes)
    let awakeMinutes: Int

    /// Sleep efficiency (0-1) = actual sleep / time in bed
    let sleepEfficiency: Double

    /// Average respiratory rate (breaths/min)
    let respiratoryRate: Double?

    /// Heart rate during sleep
    let heartRateDuringSleep: HeartRateRange

    /// HRV during sleep (if available)
    let hrvDuringSleep: Double?

    /// Blood oxygen levels during sleep (if available)
    let bloodOxygenAverage: Double?
    let bloodOxygenMin: Double?

    /// Number of times woken up
    let wakeUpCount: Int

    /// Time to fall asleep (minutes)
    let sleepLatencyMinutes: Int?

    /// Device identifier
    let deviceId: String

    /// Overall sleep quality score (0-100)
    var sleepQualityScore: Double {
        // Weighted calculation based on sleep science
        let efficiencyScore = sleepEfficiency * 30  // 30% weight
        let deepSleepScore = min(Double(deepSleepMinutes) / 90.0, 1.0) * 25  // 25% weight, target 90 min
        let remScore = min(Double(remSleepMinutes) / 90.0, 1.0) * 25  // 25% weight, target 90 min
        let durationScore = min(totalDuration / (7.5 * 3600), 1.0) * 20  // 20% weight, target 7.5 hours

        return efficiencyScore + deepSleepScore + remScore + durationScore
    }

    init(
        sleepStart: Date,
        sleepEnd: Date,
        totalDuration: TimeInterval,
        deepSleepMinutes: Int,
        remSleepMinutes: Int,
        coreSleepMinutes: Int,
        awakeMinutes: Int,
        sleepEfficiency: Double,
        respiratoryRate: Double? = nil,
        heartRateDuringSleep: HeartRateRange,
        hrvDuringSleep: Double? = nil,
        bloodOxygenAverage: Double? = nil,
        bloodOxygenMin: Double? = nil,
        wakeUpCount: Int = 0,
        sleepLatencyMinutes: Int? = nil,
        deviceId: String = "unknown"
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
        self.heartRateDuringSleep = heartRateDuringSleep
        self.hrvDuringSleep = hrvDuringSleep
        self.bloodOxygenAverage = bloodOxygenAverage
        self.bloodOxygenMin = bloodOxygenMin
        self.wakeUpCount = wakeUpCount
        self.sleepLatencyMinutes = sleepLatencyMinutes
        self.deviceId = deviceId
    }
}

// MARK: - Sleep Consistency Metadata

/// Metadata for sleepConsistency atoms - tracks sleep schedule adherence
struct SleepConsistencyMetadata: Codable, Sendable {
    /// Date of this record
    let date: Date

    /// Target bedtime from routine
    let targetBedtime: Date

    /// Actual bedtime
    let actualBedtime: Date

    /// Target wake time from routine
    let targetWakeTime: Date

    /// Actual wake time
    let actualWakeTime: Date

    /// Deviation from target bedtime (minutes, negative = earlier)
    let bedtimeDeviationMinutes: Int

    /// Deviation from target wake time (minutes, negative = earlier)
    let wakeDeviationMinutes: Int

    /// Overall consistency score (0-100)
    let consistencyScore: Double

    /// Current streak of consistent sleep days
    let streak: Int

    init(
        date: Date,
        targetBedtime: Date,
        actualBedtime: Date,
        targetWakeTime: Date,
        actualWakeTime: Date,
        bedtimeDeviationMinutes: Int,
        wakeDeviationMinutes: Int,
        consistencyScore: Double,
        streak: Int
    ) {
        self.date = date
        self.targetBedtime = targetBedtime
        self.actualBedtime = actualBedtime
        self.targetWakeTime = targetWakeTime
        self.actualWakeTime = actualWakeTime
        self.bedtimeDeviationMinutes = bedtimeDeviationMinutes
        self.wakeDeviationMinutes = wakeDeviationMinutes
        self.consistencyScore = consistencyScore
        self.streak = streak
    }
}

// MARK: - Readiness Score Metadata

/// Readiness recommendation based on score
enum ReadinessRecommendation: String, Codable, Sendable {
    case peakPerformance = "peak"
    case goodToGo = "good"
    case moderate = "moderate"
    case restRecommended = "rest_recommended"
    case restRequired = "rest_required"

    var displayName: String {
        switch self {
        case .peakPerformance: return "Peak Performance"
        case .goodToGo: return "Good to Go"
        case .moderate: return "Moderate"
        case .restRecommended: return "Rest Recommended"
        case .restRequired: return "Rest Required"
        }
    }

    var description: String {
        switch self {
        case .peakPerformance:
            return "You're primed for peak performance. Push hard today."
        case .goodToGo:
            return "Solid recovery. Normal training recommended."
        case .moderate:
            return "Recovery in progress. Light activity only."
        case .restRecommended:
            return "Your body needs rest. Focus on recovery."
        case .restRequired:
            return "Critical recovery needed. Rest completely."
        }
    }

    var colorHex: String {
        switch self {
        case .peakPerformance: return "#22C55E"  // Green
        case .goodToGo: return "#84CC16"          // Lime
        case .moderate: return "#EAB308"          // Yellow
        case .restRecommended: return "#F97316"   // Orange
        case .restRequired: return "#EF4444"      // Red
        }
    }
}

/// Metadata for readinessScore atoms
struct ReadinessScoreMetadata: Codable, Sendable {
    /// Date of the readiness calculation
    let date: Date

    /// Overall readiness score (0-100)
    let overallScore: Double

    /// HRV contribution to score (0-100)
    let hrvContribution: Double

    /// Sleep contribution to score (0-100)
    let sleepContribution: Double

    /// Recovery contribution to score (0-100)
    let recoveryContribution: Double

    /// Strain balance (recovery vs recent strain)
    let strainBalance: Double

    /// Recommendation based on score
    let recommendation: ReadinessRecommendation

    /// Factors that contributed positively
    let positiveFactors: [String]

    /// Factors that contributed negatively
    let negativeFactors: [String]

    /// Suggested activities for the day
    let suggestedActivities: [String]

    init(
        date: Date,
        overallScore: Double,
        hrvContribution: Double,
        sleepContribution: Double,
        recoveryContribution: Double,
        strainBalance: Double,
        recommendation: ReadinessRecommendation,
        positiveFactors: [String] = [],
        negativeFactors: [String] = [],
        suggestedActivities: [String] = []
    ) {
        self.date = date
        self.overallScore = overallScore
        self.hrvContribution = hrvContribution
        self.sleepContribution = sleepContribution
        self.recoveryContribution = recoveryContribution
        self.strainBalance = strainBalance
        self.recommendation = recommendation
        self.positiveFactors = positiveFactors
        self.negativeFactors = negativeFactors
        self.suggestedActivities = suggestedActivities
    }
}

// MARK: - Workout Session Metadata

/// Type of workout
enum WorkoutType: String, Codable, CaseIterable, Sendable {
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
    case traditionalStrength
    case dance
    case cooldown
    case coreTraining
    case flexibility
    case mindAndBody
    case other

    var displayName: String {
        switch self {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .walking: return "Walking"
        case .hiking: return "Hiking"
        case .strength: return "Strength"
        case .hiit: return "HIIT"
        case .yoga: return "Yoga"
        case .pilates: return "Pilates"
        case .rowing: return "Rowing"
        case .elliptical: return "Elliptical"
        case .stairClimbing: return "Stair Climbing"
        case .crossTraining: return "Cross Training"
        case .functionalStrength: return "Functional Strength"
        case .traditionalStrength: return "Traditional Strength"
        case .dance: return "Dance"
        case .cooldown: return "Cooldown"
        case .coreTraining: return "Core Training"
        case .flexibility: return "Flexibility"
        case .mindAndBody: return "Mind and Body"
        case .other: return "Other"
        }
    }

    var iconName: String {
        switch self {
        case .running: return "figure.run"
        case .cycling: return "figure.outdoor.cycle"
        case .swimming: return "figure.pool.swim"
        case .walking: return "figure.walk"
        case .hiking: return "figure.hiking"
        case .strength, .traditionalStrength, .functionalStrength: return "dumbbell.fill"
        case .hiit: return "bolt.heart.fill"
        case .yoga, .mindAndBody: return "figure.mind.and.body"
        case .pilates: return "figure.pilates"
        case .rowing: return "figure.rower"
        case .elliptical: return "figure.elliptical"
        case .stairClimbing: return "figure.stairs"
        case .crossTraining: return "figure.cross.training"
        case .dance: return "figure.dance"
        case .cooldown: return "figure.cooldown"
        case .coreTraining: return "figure.core.training"
        case .flexibility: return "figure.flexibility"
        case .other: return "figure.mixed.cardio"
        }
    }
}

/// Heart rate zone during workout
struct WorkoutHRZone: Codable, Sendable {
    let zone: Int           // 1-5
    let name: String        // "Recovery", "Aerobic", "Threshold", "VO2 Max", "Anaerobic"
    let minBPM: Int
    let maxBPM: Int
    let durationMinutes: Int
    let percentage: Double  // % of total workout time

    static let zoneNames = ["Recovery", "Aerobic", "Threshold", "VO2 Max", "Anaerobic"]
}

/// Metadata for workoutSession atoms
struct WorkoutSessionMetadata: Codable, Sendable {
    /// Type of workout
    let workoutType: WorkoutType

    /// Duration in seconds
    let duration: TimeInterval

    /// Active calories burned
    let activeCalories: Double

    /// Total calories burned (including basal)
    let totalCalories: Double?

    /// Average heart rate during workout
    let avgHeartRate: Int

    /// Maximum heart rate during workout
    let maxHeartRate: Int

    /// Minimum heart rate during workout
    let minHeartRate: Int?

    /// HRV recovery after workout (if measured)
    let hrvRecovery: Double?

    /// Strain score (0-21 scale, WHOOP-style)
    let strainScore: Double

    /// Elevation gain in meters
    let elevationGain: Double?

    /// Distance in meters
    let distance: Double?

    /// Average pace (seconds per km, for running/walking)
    let avgPaceSecondsPerKm: Double?

    /// Heart rate zones
    let zones: [WorkoutHRZone]

    /// Average cadence (for running/cycling)
    let avgCadence: Double?

    /// Average power (for cycling)
    let avgPower: Double?

    /// Indoor or outdoor
    let isIndoor: Bool

    /// Device identifier
    let deviceId: String

    /// Start time
    let startTime: Date

    /// End time
    let endTime: Date

    init(
        workoutType: WorkoutType,
        duration: TimeInterval,
        activeCalories: Double,
        totalCalories: Double? = nil,
        avgHeartRate: Int,
        maxHeartRate: Int,
        minHeartRate: Int? = nil,
        hrvRecovery: Double? = nil,
        strainScore: Double = 0,
        elevationGain: Double? = nil,
        distance: Double? = nil,
        avgPaceSecondsPerKm: Double? = nil,
        zones: [WorkoutHRZone] = [],
        avgCadence: Double? = nil,
        avgPower: Double? = nil,
        isIndoor: Bool = false,
        deviceId: String = "unknown",
        startTime: Date,
        endTime: Date
    ) {
        self.workoutType = workoutType
        self.duration = duration
        self.activeCalories = activeCalories
        self.totalCalories = totalCalories
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.minHeartRate = minHeartRate
        self.hrvRecovery = hrvRecovery
        self.strainScore = strainScore
        self.elevationGain = elevationGain
        self.distance = distance
        self.avgPaceSecondsPerKm = avgPaceSecondsPerKm
        self.zones = zones
        self.avgCadence = avgCadence
        self.avgPower = avgPower
        self.isIndoor = isIndoor
        self.deviceId = deviceId
        self.startTime = startTime
        self.endTime = endTime
    }
}

// MARK: - Meal Log Metadata

/// Metadata for mealLog atoms
struct MealLogMetadata: Codable, Sendable {
    /// Time of meal
    let mealTime: Date

    /// Type of meal
    let mealType: MealType

    /// Description of what was eaten
    let description: String?

    /// Estimated calories (if available)
    let estimatedCalories: Int?

    /// Macros (if tracked)
    let proteinGrams: Double?
    let carbsGrams: Double?
    let fatGrams: Double?

    /// How the user felt after (optional)
    let energyLevel: Int?  // 1-5

    /// Photos attached (UUIDs of photo atoms)
    let photoAtomUUIDs: [String]

    init(
        mealTime: Date,
        mealType: MealType,
        description: String? = nil,
        estimatedCalories: Int? = nil,
        proteinGrams: Double? = nil,
        carbsGrams: Double? = nil,
        fatGrams: Double? = nil,
        energyLevel: Int? = nil,
        photoAtomUUIDs: [String] = []
    ) {
        self.mealTime = mealTime
        self.mealType = mealType
        self.description = description
        self.estimatedCalories = estimatedCalories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.energyLevel = energyLevel
        self.photoAtomUUIDs = photoAtomUUIDs
    }
}

enum MealType: String, Codable, CaseIterable, Sendable {
    case breakfast
    case lunch
    case dinner
    case snack
    case other

    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - Breathing Session Metadata

/// Metadata for breathingSession atoms
struct BreathingSessionMetadata: Codable, Sendable {
    /// Duration in seconds
    let duration: TimeInterval

    /// Type of breathing exercise
    let exerciseType: BreathingExerciseType

    /// Heart rate at start
    let heartRateStart: Int?

    /// Heart rate at end
    let heartRateEnd: Int?

    /// HRV change during session
    let hrvChange: Double?

    /// Number of breaths
    let breathCount: Int?

    /// Device used
    let deviceId: String

    /// Timestamp
    let timestamp: Date

    init(
        duration: TimeInterval,
        exerciseType: BreathingExerciseType = .mindfulness,
        heartRateStart: Int? = nil,
        heartRateEnd: Int? = nil,
        hrvChange: Double? = nil,
        breathCount: Int? = nil,
        deviceId: String = "unknown",
        timestamp: Date = Date()
    ) {
        self.duration = duration
        self.exerciseType = exerciseType
        self.heartRateStart = heartRateStart
        self.heartRateEnd = heartRateEnd
        self.hrvChange = hrvChange
        self.breathCount = breathCount
        self.deviceId = deviceId
        self.timestamp = timestamp
    }
}

enum BreathingExerciseType: String, Codable, Sendable {
    case mindfulness
    case boxBreathing
    case relaxation
    case focus
    case sleep
    case other

    var displayName: String {
        switch self {
        case .mindfulness: return "Mindfulness"
        case .boxBreathing: return "Box Breathing"
        case .relaxation: return "Relaxation"
        case .focus: return "Focus"
        case .sleep: return "Sleep"
        case .other: return "Other"
        }
    }
}

// MARK: - Blood Oxygen Metadata

/// Metadata for bloodOxygen atoms
struct BloodOxygenMetadata: Codable, Sendable {
    /// SpO2 percentage (typically 95-100%)
    let spo2Percentage: Double

    /// Measurement context
    let context: BloodOxygenContext

    /// Measurement confidence (0-1)
    let confidence: Double

    /// Device identifier
    let deviceId: String

    /// Timestamp
    let timestamp: Date

    init(
        spo2Percentage: Double,
        context: BloodOxygenContext = .onDemand,
        confidence: Double = 1.0,
        deviceId: String = "unknown",
        timestamp: Date = Date()
    ) {
        self.spo2Percentage = spo2Percentage
        self.context = context
        self.confidence = confidence
        self.deviceId = deviceId
        self.timestamp = timestamp
    }
}

enum BloodOxygenContext: String, Codable, Sendable {
    case duringSleep
    case onDemand
    case postWorkout
    case atAltitude
    case other

    var displayName: String {
        switch self {
        case .duringSleep: return "During Sleep"
        case .onDemand: return "On Demand"
        case .postWorkout: return "Post Workout"
        case .atAltitude: return "At Altitude"
        case .other: return "Other"
        }
    }
}

// MARK: - Body Temperature Metadata

/// Metadata for bodyTemperature atoms (wrist temperature deviation)
struct BodyTemperatureMetadata: Codable, Sendable {
    /// Temperature deviation from baseline (Celsius)
    let deviationCelsius: Double

    /// Context of measurement
    let context: TemperatureContext

    /// Device identifier
    let deviceId: String

    /// Timestamp
    let timestamp: Date

    init(
        deviationCelsius: Double,
        context: TemperatureContext = .duringSleep,
        deviceId: String = "unknown",
        timestamp: Date = Date()
    ) {
        self.deviationCelsius = deviationCelsius
        self.context = context
        self.deviceId = deviceId
        self.timestamp = timestamp
    }
}

enum TemperatureContext: String, Codable, Sendable {
    case duringSleep
    case cycleTracking  // For menstrual cycle tracking
    case illness
    case other

    var displayName: String {
        switch self {
        case .duringSleep: return "During Sleep"
        case .cycleTracking: return "Cycle Tracking"
        case .illness: return "Illness"
        case .other: return "Other"
        }
    }
}
