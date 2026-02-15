// CosmoOS/UI/Sanctuary/Dimensions/Physiological/PhysiologicalDimensionData.swift
// Data Models - Biometric data structures for physiological dimension
// Phase 5: Following SANCTUARY_UI_SPEC_V2.md section 3.3

import SwiftUI

// MARK: - Resting Heart Rate Zone

public enum RestingHRZone: String, Codable, Sendable, CaseIterable {
    case athletic
    case average
    case elevated
    case high

    public var displayName: String {
        switch self {
        case .athletic: return "Athletic"
        case .average: return "Average"
        case .elevated: return "Elevated"
        case .high: return "High"
        }
    }

    public var color: String {
        switch self {
        case .athletic: return "#22C55E"
        case .average: return "#3B82F6"
        case .elevated: return "#F59E0B"
        case .high: return "#EF4444"
        }
    }
}

// MARK: - Strain Level

public enum StrainLevel: String, Codable, Sendable, CaseIterable {
    case low
    case moderate
    case high
    case extreme

    public var displayName: String {
        switch self {
        case .low: return "Low"
        case .moderate: return "Moderate"
        case .high: return "High"
        case .extreme: return "Extreme"
        }
    }

    public var color: String {
        switch self {
        case .low: return "#22C55E"
        case .moderate: return "#F59E0B"
        case .high: return "#F97316"
        case .extreme: return "#EF4444"
        }
    }
}

// MARK: - Cortisol Level

public enum CortisolLevel: String, Codable, Sendable, CaseIterable {
    case low
    case normal
    case elevated
    case high

    public var displayName: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .elevated: return "Elevated"
        case .high: return "High"
        }
    }

    public var color: String {
        switch self {
        case .low: return "#3B82F6"
        case .normal: return "#22C55E"
        case .elevated: return "#F59E0B"
        case .high: return "#EF4444"
        }
    }
}

// MARK: - Recovery Debt Level

public enum RecoveryDebtLevel: String, Codable, Sendable, CaseIterable {
    case none
    case low
    case moderate
    case high
    case critical

    public var displayName: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .moderate: return "Moderate"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }

    public var color: String {
        switch self {
        case .none: return "#22C55E"
        case .low: return "#84CC16"
        case .moderate: return "#F59E0B"
        case .high: return "#F97316"
        case .critical: return "#EF4444"
        }
    }
}

// MARK: - Muscle Group

public enum MuscleGroup: String, Codable, Sendable, CaseIterable, Identifiable {
    case neck
    case shoulders
    case chest
    case upperBack
    case lowerBack
    case biceps
    case triceps
    case forearms
    case core
    case obliques
    case glutes
    case quadriceps
    case hamstrings
    case calves

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .neck: return "Neck"
        case .shoulders: return "Shoulders"
        case .chest: return "Chest"
        case .upperBack: return "Upper Back"
        case .lowerBack: return "Lower Back"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .forearms: return "Forearms"
        case .core: return "Core"
        case .obliques: return "Obliques"
        case .glutes: return "Glutes"
        case .quadriceps: return "Quads"
        case .hamstrings: return "Hamstrings"
        case .calves: return "Calves"
        }
    }

    public var shortName: String {
        switch self {
        case .neck: return "NECK"
        case .shoulders: return "SHLD"
        case .chest: return "CHST"
        case .upperBack: return "UBACK"
        case .lowerBack: return "LBACK"
        case .biceps: return "BIC"
        case .triceps: return "TRI"
        case .forearms: return "FARM"
        case .core: return "CORE"
        case .obliques: return "OBL"
        case .glutes: return "GLUT"
        case .quadriceps: return "QUAD"
        case .hamstrings: return "HAM"
        case .calves: return "CALF"
        }
    }

    public var bodyPosition: (x: CGFloat, y: CGFloat) {
        switch self {
        case .neck: return (0.5, 0.12)
        case .shoulders: return (0.5, 0.18)
        case .chest: return (0.5, 0.28)
        case .upperBack: return (0.5, 0.25)
        case .lowerBack: return (0.5, 0.42)
        case .biceps: return (0.25, 0.32)
        case .triceps: return (0.75, 0.32)
        case .forearms: return (0.2, 0.42)
        case .core: return (0.5, 0.38)
        case .obliques: return (0.35, 0.38)
        case .glutes: return (0.5, 0.48)
        case .quadriceps: return (0.4, 0.62)
        case .hamstrings: return (0.6, 0.62)
        case .calves: return (0.5, 0.82)
        }
    }
}

// MARK: - Body Zone

public enum BodyZone: String, Codable, Sendable, CaseIterable {
    case head
    case chest
    case arms
    case core
    case legs

    public var displayName: String {
        switch self {
        case .head: return "Head"
        case .chest: return "Chest"
        case .arms: return "Arms"
        case .core: return "Core"
        case .legs: return "Legs"
        }
    }
}

// MARK: - Sleep Stage

public enum SleepStageType: String, Codable, Sendable, CaseIterable {
    case awake
    case rem
    case core
    case deep

    public var displayName: String {
        switch self {
        case .awake: return "Awake"
        case .rem: return "REM"
        case .core: return "Core"
        case .deep: return "Deep"
        }
    }

    public var color: String {
        switch self {
        case .awake: return "#F97316"
        case .rem: return "#8B5CF6"
        case .core: return "#3B82F6"
        case .deep: return "#1E40AF"
        }
    }
}

// MARK: - Display Workout Type

public enum DisplayWorkoutType: String, Codable, Sendable, CaseIterable {
    case strength
    case hiit
    case cardio
    case zone2
    case yoga
    case stretching
    case swimming
    case cycling
    case running
    case walking
    case rest

    public var displayName: String {
        switch self {
        case .strength: return "Strength"
        case .hiit: return "HIIT"
        case .cardio: return "Cardio"
        case .zone2: return "Zone 2"
        case .yoga: return "Yoga"
        case .stretching: return "Stretching"
        case .swimming: return "Swimming"
        case .cycling: return "Cycling"
        case .running: return "Running"
        case .walking: return "Walking"
        case .rest: return "Rest Day"
        }
    }

    public var iconName: String {
        switch self {
        case .strength: return "dumbbell.fill"
        case .hiit: return "flame.fill"
        case .cardio: return "heart.fill"
        case .zone2: return "figure.run"
        case .yoga: return "figure.yoga"
        case .stretching: return "figure.flexibility"
        case .swimming: return "figure.pool.swim"
        case .cycling: return "figure.outdoor.cycle"
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .rest: return "bed.double.fill"
        }
    }

    public var color: String {
        switch self {
        case .strength: return "#EF4444"
        case .hiit: return "#F97316"
        case .cardio: return "#EC4899"
        case .zone2: return "#22C55E"
        case .yoga: return "#8B5CF6"
        case .stretching: return "#06B6D4"
        case .swimming: return "#3B82F6"
        case .cycling: return "#84CC16"
        case .running: return "#10B981"
        case .walking: return "#14B8A6"
        case .rest: return "#6B7280"
        }
    }
}

// MARK: - HRV Data Point

public struct HRVDataPoint: Identifiable, Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let value: Double
    public let isResting: Bool

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        value: Double,
        isResting: Bool = true
    ) {
        self.id = id
        self.timestamp = timestamp
        self.value = value
        self.isResting = isResting
    }
}

// MARK: - Muscle Status

public struct MuscleStatus: Identifiable, Codable, Sendable {
    public let id: UUID
    public let muscleGroup: MuscleGroup
    public let recoveryPercent: Double
    public let lastWorked: Date?
    public let strain: StrainLevel

    public init(
        id: UUID = UUID(),
        muscleGroup: MuscleGroup,
        recoveryPercent: Double,
        lastWorked: Date? = nil,
        strain: StrainLevel = .low
    ) {
        self.id = id
        self.muscleGroup = muscleGroup
        self.recoveryPercent = min(100, max(0, recoveryPercent))
        self.lastWorked = lastWorked
        self.strain = strain
    }

    public var statusColor: Color {
        if recoveryPercent >= 80 {
            return Color(hex: "#22C55E") // Ready
        } else if recoveryPercent >= 60 {
            return Color(hex: "#84CC16") // Good
        } else if recoveryPercent >= 40 {
            return Color(hex: "#F59E0B") // Moderate
        } else {
            return Color(hex: "#EF4444") // Fatigued
        }
    }

    public var statusText: String {
        if recoveryPercent >= 80 {
            return "Ready"
        } else if recoveryPercent >= 60 {
            return "Good"
        } else if recoveryPercent >= 40 {
            return "Moderate"
        } else {
            return "Fatigued"
        }
    }
}

// MARK: - Zone Status

public struct ZoneStatus: Identifiable, Codable, Sendable {
    public let id: UUID
    public let zone: BodyZone
    public let healthPercent: Double
    public let issues: [String]

    public init(
        id: UUID = UUID(),
        zone: BodyZone,
        healthPercent: Double,
        issues: [String] = []
    ) {
        self.id = id
        self.zone = zone
        self.healthPercent = min(100, max(0, healthPercent))
        self.issues = issues
    }
}

// MARK: - Sleep Stage Event

public struct SleepStageEvent: Identifiable, Codable, Sendable {
    public let id: UUID
    public let stage: SleepStageType
    public let startTime: Date
    public let duration: TimeInterval

    public init(
        id: UUID = UUID(),
        stage: SleepStageType,
        startTime: Date,
        duration: TimeInterval
    ) {
        self.id = id
        self.stage = stage
        self.startTime = startTime
        self.duration = duration
    }

    public var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Sleep Session

public struct SleepSession: Identifiable, Codable, Sendable {
    public let id: UUID
    public let bedTime: Date
    public let wakeTime: Date
    public let totalDuration: TimeInterval
    public let deepSleep: TimeInterval
    public let coreSleep: TimeInterval
    public let remSleep: TimeInterval
    public let awakeTime: TimeInterval
    public let efficiency: Double
    public let score: Int
    public let stages: [SleepStageEvent]
    public let disturbanceCount: Int

    public init(
        id: UUID = UUID(),
        bedTime: Date,
        wakeTime: Date,
        totalDuration: TimeInterval,
        deepSleep: TimeInterval,
        coreSleep: TimeInterval,
        remSleep: TimeInterval,
        awakeTime: TimeInterval,
        efficiency: Double,
        score: Int,
        stages: [SleepStageEvent] = [],
        disturbanceCount: Int = 0
    ) {
        self.id = id
        self.bedTime = bedTime
        self.wakeTime = wakeTime
        self.totalDuration = totalDuration
        self.deepSleep = deepSleep
        self.coreSleep = coreSleep
        self.remSleep = remSleep
        self.awakeTime = awakeTime
        self.efficiency = efficiency
        self.score = score
        self.stages = stages
        self.disturbanceCount = disturbanceCount
    }

    public var formattedBedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        return formatter.string(from: bedTime).lowercased()
    }

    public var formattedWakeTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        return formatter.string(from: wakeTime).lowercased()
    }

    public var formattedDuration: String {
        let hours = Int(totalDuration) / 3600
        let minutes = (Int(totalDuration) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    public var deepSleepPercent: Double {
        guard totalDuration > 0 else { return 0 }
        return (deepSleep / totalDuration) * 100
    }

    public var remSleepPercent: Double {
        guard totalDuration > 0 else { return 0 }
        return (remSleep / totalDuration) * 100
    }

    public var scoreRating: String {
        if score >= 90 { return "Excellent" }
        if score >= 80 { return "Good" }
        if score >= 70 { return "Fair" }
        if score >= 60 { return "Poor" }
        return "Very Poor"
    }
}

// MARK: - Recovery Breakdown

public struct RecoveryBreakdown: Codable, Sendable {
    public let sleepContribution: Double
    public let hrvContribution: Double
    public let strainContribution: Double
    public let consistencyBonus: Double

    public init(
        sleepContribution: Double,
        hrvContribution: Double,
        strainContribution: Double,
        consistencyBonus: Double
    ) {
        self.sleepContribution = sleepContribution
        self.hrvContribution = hrvContribution
        self.strainContribution = strainContribution
        self.consistencyBonus = consistencyBonus
    }

    public var total: Double {
        sleepContribution + hrvContribution + strainContribution + consistencyBonus
    }
}

// MARK: - Activity Rings

public struct ActivityRings: Codable, Sendable {
    public let moveCalories: Int
    public let moveGoal: Int
    public let exerciseMinutes: Int
    public let exerciseGoal: Int
    public let standHours: Int
    public let standGoal: Int

    public init(
        moveCalories: Int,
        moveGoal: Int,
        exerciseMinutes: Int,
        exerciseGoal: Int,
        standHours: Int,
        standGoal: Int
    ) {
        self.moveCalories = moveCalories
        self.moveGoal = moveGoal
        self.exerciseMinutes = exerciseMinutes
        self.exerciseGoal = exerciseGoal
        self.standHours = standHours
        self.standGoal = standGoal
    }

    public var moveProgress: Double {
        guard moveGoal > 0 else { return 0 }
        return min(1.0, Double(moveCalories) / Double(moveGoal))
    }

    public var exerciseProgress: Double {
        guard exerciseGoal > 0 else { return 0 }
        return min(1.0, Double(exerciseMinutes) / Double(exerciseGoal))
    }

    public var standProgress: Double {
        guard standGoal > 0 else { return 0 }
        return min(1.0, Double(standHours) / Double(standGoal))
    }
}

// MARK: - Hourly Activity

public struct HourlyActivity: Identifiable, Codable, Sendable {
    public let id: UUID
    public let hour: Int
    public let steps: Int
    public let activeCalories: Int
    public let standMinutes: Int

    public init(
        id: UUID = UUID(),
        hour: Int,
        steps: Int,
        activeCalories: Int,
        standMinutes: Int
    ) {
        self.id = id
        self.hour = hour
        self.steps = steps
        self.activeCalories = activeCalories
        self.standMinutes = standMinutes
    }
}

// MARK: - Workout Session

public struct WorkoutSession: Identifiable, Codable, Sendable {
    public let id: UUID
    public let type: DisplayWorkoutType
    public let date: Date
    public let duration: TimeInterval
    public let calories: Int
    public let heartRateAvg: Int?
    public let heartRateMax: Int?
    public let intensity: Double // 0-5 stars
    public let notes: String?
    public let musclesWorked: [MuscleGroup]

    public init(
        id: UUID = UUID(),
        type: DisplayWorkoutType,
        date: Date,
        duration: TimeInterval,
        calories: Int,
        heartRateAvg: Int? = nil,
        heartRateMax: Int? = nil,
        intensity: Double = 3.0,
        notes: String? = nil,
        musclesWorked: [MuscleGroup] = []
    ) {
        self.id = id
        self.type = type
        self.date = date
        self.duration = duration
        self.calories = calories
        self.heartRateAvg = heartRateAvg
        self.heartRateMax = heartRateMax
        self.intensity = min(5, max(0, intensity))
        self.notes = notes
        self.musclesWorked = musclesWorked
    }

    public var formattedDuration: String {
        let minutes = Int(duration) / 60
        return "\(minutes)min"
    }

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }

    public var intensityStars: String {
        let filled = Int(intensity.rounded())
        let empty = 5 - filled
        return String(repeating: "●", count: filled) + String(repeating: "○", count: empty)
    }
}

// MARK: - Physiological Correlation

public struct PhysiologicalCorrelation: Identifiable, Codable, Sendable {
    public let id: UUID
    public let sourceMetric: String
    public let targetMetric: String
    public let correlationCoefficient: Double
    public let impactPercent: Double
    public let timeframe: String
    public let confidence: Double

    public init(
        id: UUID = UUID(),
        sourceMetric: String,
        targetMetric: String,
        correlationCoefficient: Double,
        impactPercent: Double,
        timeframe: String,
        confidence: Double
    ) {
        self.id = id
        self.sourceMetric = sourceMetric
        self.targetMetric = targetMetric
        self.correlationCoefficient = correlationCoefficient
        self.impactPercent = impactPercent
        self.timeframe = timeframe
        self.confidence = confidence
    }

    public var isPositive: Bool {
        correlationCoefficient >= 0
    }

    public var strengthLabel: String {
        let absR = abs(correlationCoefficient)
        if absR >= 0.7 { return "Strong" }
        if absR >= 0.4 { return "Moderate" }
        return "Weak"
    }
}

// MARK: - Health Prediction

public struct HealthPrediction: Identifiable, Codable, Sendable {
    public let id: UUID
    public let condition: String
    public let prediction: String
    public let impact: String
    public let confidence: Double
    public let basedOn: [String]
    public let actions: [String]

    public init(
        id: UUID = UUID(),
        condition: String,
        prediction: String,
        impact: String,
        confidence: Double,
        basedOn: [String],
        actions: [String]
    ) {
        self.id = id
        self.condition = condition
        self.prediction = prediction
        self.impact = impact
        self.confidence = confidence
        self.basedOn = basedOn
        self.actions = actions
    }
}

// MARK: - Physiological Dimension Data

public struct PhysiologicalDimensionData: Codable, Sendable {
    // Core Vitals
    public let currentHRV: Double
    public let hrvVariabilityMs: Double
    public let hrvTrend: [HRVDataPoint]
    public let restingHeartRate: Int
    public let rhrZone: RestingHRZone

    // Recovery
    public let recoveryScore: Double
    public let recoveryFactors: RecoveryBreakdown
    public let readinessScore: Double
    public let peakPerformanceWindowStart: Date
    public let peakPerformanceWindowEnd: Date
    public let workoutRecommendation: DisplayWorkoutType?

    // Sleep
    public let lastNightSleep: SleepSession
    public let sleepDebt: TimeInterval
    public let sleepTrend: [Int] // Last 7 days scores

    // Body Scanner
    public let muscleRecoveryMap: [MuscleStatus]
    public let bodyZoneStatus: [ZoneStatus]
    public let stressLevel: Double
    public let cortisolEstimate: CortisolLevel
    public let breathingRatePerMin: Double

    // Activity
    public let hourlyActivity: [HourlyActivity]
    public let dailyRings: ActivityRings
    public let stepCount: Int
    public let activeCalories: Int
    public let workouts: [WorkoutSession]
    public let weeklyVolumeLoad: Double
    public let recoveryDebt: RecoveryDebtLevel

    // Correlations
    public let correlations: [PhysiologicalCorrelation]
    public let predictions: [HealthPrediction]

    public init(
        currentHRV: Double,
        hrvVariabilityMs: Double,
        hrvTrend: [HRVDataPoint],
        restingHeartRate: Int,
        rhrZone: RestingHRZone,
        recoveryScore: Double,
        recoveryFactors: RecoveryBreakdown,
        readinessScore: Double,
        peakPerformanceWindowStart: Date,
        peakPerformanceWindowEnd: Date,
        workoutRecommendation: DisplayWorkoutType?,
        lastNightSleep: SleepSession,
        sleepDebt: TimeInterval,
        sleepTrend: [Int],
        muscleRecoveryMap: [MuscleStatus],
        bodyZoneStatus: [ZoneStatus],
        stressLevel: Double,
        cortisolEstimate: CortisolLevel,
        breathingRatePerMin: Double,
        hourlyActivity: [HourlyActivity],
        dailyRings: ActivityRings,
        stepCount: Int,
        activeCalories: Int,
        workouts: [WorkoutSession],
        weeklyVolumeLoad: Double,
        recoveryDebt: RecoveryDebtLevel,
        correlations: [PhysiologicalCorrelation],
        predictions: [HealthPrediction]
    ) {
        self.currentHRV = currentHRV
        self.hrvVariabilityMs = hrvVariabilityMs
        self.hrvTrend = hrvTrend
        self.restingHeartRate = restingHeartRate
        self.rhrZone = rhrZone
        self.recoveryScore = recoveryScore
        self.recoveryFactors = recoveryFactors
        self.readinessScore = readinessScore
        self.peakPerformanceWindowStart = peakPerformanceWindowStart
        self.peakPerformanceWindowEnd = peakPerformanceWindowEnd
        self.workoutRecommendation = workoutRecommendation
        self.lastNightSleep = lastNightSleep
        self.sleepDebt = sleepDebt
        self.sleepTrend = sleepTrend
        self.muscleRecoveryMap = muscleRecoveryMap
        self.bodyZoneStatus = bodyZoneStatus
        self.stressLevel = stressLevel
        self.cortisolEstimate = cortisolEstimate
        self.breathingRatePerMin = breathingRatePerMin
        self.hourlyActivity = hourlyActivity
        self.dailyRings = dailyRings
        self.stepCount = stepCount
        self.activeCalories = activeCalories
        self.workouts = workouts
        self.weeklyVolumeLoad = weeklyVolumeLoad
        self.recoveryDebt = recoveryDebt
        self.correlations = correlations
        self.predictions = predictions
    }

    // MARK: - Computed Properties

    public var formattedPeakWindow: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        let start = formatter.string(from: peakPerformanceWindowStart).lowercased()
        let end = formatter.string(from: peakPerformanceWindowEnd).lowercased()
        return "\(start)-\(end)"
    }

    public var hrvStatus: String {
        if currentHRV >= 50 { return "Excellent" }
        if currentHRV >= 40 { return "Good" }
        if currentHRV >= 30 { return "Fair" }
        return "Low"
    }

    public var recoveryStatus: String {
        if recoveryScore >= 80 { return "Strong" }
        if recoveryScore >= 60 { return "Moderate" }
        if recoveryScore >= 40 { return "Recovering"
        }
        return "Fatigued"
    }

    public var readinessStatus: String {
        if readinessScore >= 80 { return "High" }
        if readinessScore >= 60 { return "Moderate" }
        if readinessScore >= 40 { return "Low" }
        return "Very Low"
    }

    public var formattedSleepDebt: String {
        let hours = Int(sleepDebt) / 3600
        let minutes = (Int(sleepDebt) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Empty Factory

extension PhysiologicalDimensionData {
    public static var empty: PhysiologicalDimensionData {
        let now = Date()
        return PhysiologicalDimensionData(
            currentHRV: 0,
            hrvVariabilityMs: 0,
            hrvTrend: [],
            restingHeartRate: 0,
            rhrZone: .average,
            recoveryScore: 0,
            recoveryFactors: RecoveryBreakdown(
                sleepContribution: 0,
                hrvContribution: 0,
                strainContribution: 0,
                consistencyBonus: 0
            ),
            readinessScore: 0,
            peakPerformanceWindowStart: now,
            peakPerformanceWindowEnd: now,
            workoutRecommendation: nil,
            lastNightSleep: SleepSession(
                bedTime: now,
                wakeTime: now,
                totalDuration: 0,
                deepSleep: 0,
                coreSleep: 0,
                remSleep: 0,
                awakeTime: 0,
                efficiency: 0,
                score: 0,
                stages: [],
                disturbanceCount: 0
            ),
            sleepDebt: 0,
            sleepTrend: [],
            muscleRecoveryMap: [],
            bodyZoneStatus: [],
            stressLevel: 0,
            cortisolEstimate: .normal,
            breathingRatePerMin: 0,
            hourlyActivity: [],
            dailyRings: ActivityRings(
                moveCalories: 0,
                moveGoal: 0,
                exerciseMinutes: 0,
                exerciseGoal: 0,
                standHours: 0,
                standGoal: 0
            ),
            stepCount: 0,
            activeCalories: 0,
            workouts: [],
            weeklyVolumeLoad: 0,
            recoveryDebt: .none,
            correlations: [],
            predictions: []
        )
    }

    public var isEmpty: Bool {
        currentHRV == 0 && recoveryScore == 0 && stepCount == 0
    }
}

// MARK: - Preview Data

#if DEBUG
extension PhysiologicalDimensionData {
    public static var preview: PhysiologicalDimensionData {
        let calendar = Calendar.current
        let now = Date()

        // Generate HRV trend
        let hrvTrend = (0..<7).map { dayOffset -> HRVDataPoint in
            let date = calendar.date(byAdding: .day, value: -6 + dayOffset, to: now) ?? now
            let value = Double.random(in: 40...55)
            return HRVDataPoint(timestamp: date, value: value)
        }

        // Generate muscle recovery map
        let muscleMap: [MuscleStatus] = [
            MuscleStatus(muscleGroup: .chest, recoveryPercent: 94, lastWorked: calendar.date(byAdding: .day, value: -3, to: now), strain: .low),
            MuscleStatus(muscleGroup: .shoulders, recoveryPercent: 87, lastWorked: calendar.date(byAdding: .day, value: -2, to: now), strain: .low),
            MuscleStatus(muscleGroup: .biceps, recoveryPercent: 91, lastWorked: calendar.date(byAdding: .day, value: -3, to: now), strain: .low),
            MuscleStatus(muscleGroup: .triceps, recoveryPercent: 88, lastWorked: calendar.date(byAdding: .day, value: -2, to: now), strain: .low),
            MuscleStatus(muscleGroup: .core, recoveryPercent: 94, strain: .low),
            MuscleStatus(muscleGroup: .quadriceps, recoveryPercent: 72, lastWorked: calendar.date(byAdding: .day, value: -1, to: now), strain: .moderate),
            MuscleStatus(muscleGroup: .hamstrings, recoveryPercent: 68, lastWorked: calendar.date(byAdding: .day, value: -1, to: now), strain: .moderate),
            MuscleStatus(muscleGroup: .calves, recoveryPercent: 45, lastWorked: now, strain: .high),
            MuscleStatus(muscleGroup: .glutes, recoveryPercent: 52, lastWorked: calendar.date(byAdding: .day, value: -1, to: now), strain: .moderate)
        ]

        // Generate body zone status
        let zoneStatus: [ZoneStatus] = [
            ZoneStatus(zone: .head, healthPercent: 92),
            ZoneStatus(zone: .chest, healthPercent: 88),
            ZoneStatus(zone: .arms, healthPercent: 90),
            ZoneStatus(zone: .core, healthPercent: 94),
            ZoneStatus(zone: .legs, healthPercent: 65, issues: ["Calf fatigue", "Quad soreness"])
        ]

        // Generate sleep session
        let bedTime = calendar.date(bySettingHour: 23, minute: 24, second: 0, of: calendar.date(byAdding: .day, value: -1, to: now)!)!
        let wakeTime = calendar.date(bySettingHour: 6, minute: 48, second: 0, of: now)!
        let sleepSession = SleepSession(
            bedTime: bedTime,
            wakeTime: wakeTime,
            totalDuration: 7 * 3600 + 24 * 60,
            deepSleep: 1 * 3600 + 48 * 60,
            coreSleep: 3 * 3600 + 12 * 60,
            remSleep: 42 * 60,
            awakeTime: 12 * 60,
            efficiency: 91,
            score: 87,
            disturbanceCount: 2
        )

        // Generate activity rings
        let rings = ActivityRings(
            moveCalories: 482,
            moveGoal: 620,
            exerciseMinutes: 47,
            exerciseGoal: 30,
            standHours: 12,
            standGoal: 12
        )

        // Generate workouts
        let workouts: [WorkoutSession] = [
            WorkoutSession(
                type: .strength,
                date: calendar.date(byAdding: .day, value: -1, to: now)!,
                duration: 65 * 60,
                calories: 420,
                heartRateAvg: 125,
                heartRateMax: 165,
                intensity: 4,
                musclesWorked: [.chest, .shoulders, .triceps]
            ),
            WorkoutSession(
                type: .hiit,
                date: calendar.date(byAdding: .day, value: -3, to: now)!,
                duration: 42 * 60,
                calories: 380,
                heartRateAvg: 145,
                heartRateMax: 178,
                intensity: 5
            ),
            WorkoutSession(
                type: .zone2,
                date: calendar.date(byAdding: .day, value: -5, to: now)!,
                duration: 55 * 60,
                calories: 520,
                heartRateAvg: 135,
                heartRateMax: 152,
                intensity: 4,
                musclesWorked: [.quadriceps, .hamstrings, .calves]
            )
        ]

        // Generate correlations
        let correlations: [PhysiologicalCorrelation] = [
            PhysiologicalCorrelation(
                sourceMetric: "HRV",
                targetMetric: "Focus",
                correlationCoefficient: 0.72,
                impactPercent: 18,
                timeframe: "tomorrow",
                confidence: 0.85
            ),
            PhysiologicalCorrelation(
                sourceMetric: "Sleep",
                targetMetric: "Recovery",
                correlationCoefficient: 0.84,
                impactPercent: 23,
                timeframe: "next day",
                confidence: 0.91
            ),
            PhysiologicalCorrelation(
                sourceMetric: "Workout",
                targetMetric: "Next Day HRV",
                correlationCoefficient: -0.45,
                impactPercent: -8,
                timeframe: "recovery",
                confidence: 0.78
            ),
            PhysiologicalCorrelation(
                sourceMetric: "Stress",
                targetMetric: "Sleep Quality",
                correlationCoefficient: -0.67,
                impactPercent: -15,
                timeframe: "same night",
                confidence: 0.82
            )
        ]

        // Generate predictions
        let predictions: [HealthPrediction] = [
            HealthPrediction(
                condition: "Complete tomorrow's planned Zone 2 run (55min)",
                prediction: "Saturday HRV projected to reach 54ms (+12%)",
                impact: "Optimal for cognitive work",
                confidence: 0.87,
                basedOn: ["23 similar training cycles", "Your personal recovery pattern (1.2 days avg)"],
                actions: ["Schedule Zone 2", "See Analysis", "Remind Before Bed"]
            )
        ]

        return PhysiologicalDimensionData(
            currentHRV: 48,
            hrvVariabilityMs: 12,
            hrvTrend: hrvTrend,
            restingHeartRate: 54,
            rhrZone: .athletic,
            recoveryScore: 78,
            recoveryFactors: RecoveryBreakdown(
                sleepContribution: 35,
                hrvContribution: 25,
                strainContribution: 12,
                consistencyBonus: 6
            ),
            readinessScore: 82,
            peakPerformanceWindowStart: calendar.date(bySettingHour: 10, minute: 0, second: 0, of: now)!,
            peakPerformanceWindowEnd: calendar.date(bySettingHour: 14, minute: 0, second: 0, of: now)!,
            workoutRecommendation: .zone2,
            lastNightSleep: sleepSession,
            sleepDebt: 45 * 60,
            sleepTrend: [82, 78, 85, 91, 76, 88, 87],
            muscleRecoveryMap: muscleMap,
            bodyZoneStatus: zoneStatus,
            stressLevel: 34,
            cortisolEstimate: .low,
            breathingRatePerMin: 14.2,
            hourlyActivity: [],
            dailyRings: rings,
            stepCount: 8247,
            activeCalories: 482,
            workouts: workouts,
            weeklyVolumeLoad: 12450,
            recoveryDebt: .low,
            correlations: correlations,
            predictions: predictions
        )
    }
}
#endif
