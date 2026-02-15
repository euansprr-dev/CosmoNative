// CosmoOS/UI/Sanctuary/Dimensions/Physiological/PhysiologicalDataProvider.swift
// Data provider that queries HealthKit via HealthKitQueryService to build real PhysiologicalDimensionData

import Foundation
import SwiftUI
import HealthKit

@MainActor
class PhysiologicalDataProvider: ObservableObject {
    @Published var data: PhysiologicalDimensionData = .preview
    @Published var healthTier: HealthTier = .none
    @Published var isLoading: Bool = false
    @Published var isConnected: Bool = false

    private let healthService: HealthKitQueryService

    init(healthService: HealthKitQueryService? = nil) {
        self.healthService = healthService ?? HealthKitQueryService.shared
    }

    // MARK: - Connect

    /// Request HealthKit access and detect tier
    func connect() async {
        await healthService.requestAccess()
        isConnected = healthService.hasAccess
        healthTier = healthService.tier
    }

    // MARK: - Refresh

    func refreshData() async {
        guard healthService.hasAccess else {
            healthTier = .none
            isConnected = false
            return
        }

        isLoading = true
        defer { isLoading = false }

        healthTier = healthService.tier

        // Fetch all data concurrently
        async let stepsResult = healthService.fetchTodaySteps()
        async let activityResult = healthService.fetchTodayActivity()
        async let sleepResult = healthService.fetchLastNightSleep()
        async let hrvResult = healthService.fetchLatestHRV()
        async let rhrResult = healthService.fetchRestingHR()
        async let rrResult = healthService.fetchRespiratoryRate()
        async let hrvTrendResult = healthService.fetchHRVTrend(days: 7)
        async let sleepTrendResult = healthService.fetchSleepTrend(days: 7)
        async let workoutsResult = healthService.fetchRecentWorkouts(days: 7)
        async let hourlyResult = healthService.fetchHourlyActivity()

        let steps = await stepsResult
        let activity = await activityResult
        let sleep = await sleepResult
        let hrv = await hrvResult
        let rhr = await rhrResult
        let rr = await rrResult
        let hrvTrend = await hrvTrendResult
        let sleepTrend = await sleepTrendResult
        let hkWorkouts = await workoutsResult
        let hourlyRaw = await hourlyResult

        // Build PhysiologicalDimensionData from real values
        let currentHRV = hrv ?? 0
        let restingHeartRate = Int(rhr ?? 0)
        let breathingRate = rr ?? 0

        // HRV Trend data points
        let hrvDataPoints = hrvTrend.map { entry in
            HRVDataPoint(timestamp: entry.date, value: entry.value)
        }

        // Resting HR zone classification
        let rhrZone: RestingHRZone = {
            switch restingHeartRate {
            case 0..<55: return .athletic
            case 55..<65: return .average
            case 65..<75: return .elevated
            default: return .high
            }
        }()

        // Sleep session from HealthKit data
        let sleepSession = buildSleepSession(from: sleep)

        // Sleep debt: target 8 hours, deficit if less
        let sleepDebt: TimeInterval = {
            guard let s = sleep else { return 0 }
            let targetHours = 8.0
            let deficit = max(0, targetHours - s.totalHours)
            return deficit * 3600
        }()

        // Activity rings
        let rings = ActivityRings(
            moveCalories: Int(activity.activeCalories),
            moveGoal: 600,  // Default goal; could be fetched from HK activity summary
            exerciseMinutes: activity.exerciseMinutes,
            exerciseGoal: 30,
            standHours: activity.standHours,
            standGoal: 12
        )

        // Convert HKWorkout to display WorkoutSession
        let workouts = hkWorkouts.map { convertWorkout($0) }

        // Compute recovery score (simplified — real computation uses ReadinessCalculator)
        let recoveryScore = computeRecoveryScore(
            hrv: currentHRV,
            sleepEfficiency: sleep?.efficiency ?? 0,
            sleepHours: sleep?.totalHours ?? 0
        )

        // Compute readiness score
        let readinessScore = computeReadinessScore(
            recoveryScore: recoveryScore,
            hrv: currentHRV,
            rhr: restingHeartRate
        )

        // Recovery breakdown
        let recoveryFactors = RecoveryBreakdown(
            sleepContribution: min(40, (sleep?.efficiency ?? 0) * 0.4),
            hrvContribution: min(30, currentHRV > 0 ? (currentHRV / 60.0) * 30 : 0),
            strainContribution: 10,
            consistencyBonus: sleepTrend.filter { $0 >= 70 }.count >= 5 ? 8 : 3
        )

        // Peak performance window (10am-2pm as default)
        let calendar = Calendar.current
        let now = Date()
        let peakStart = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: now) ?? now
        let peakEnd = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: now) ?? now

        // Hourly activity from HealthKit
        let hourlyActivity = hourlyRaw.map { entry in
            HourlyActivity(
                hour: entry.hour,
                steps: entry.steps,
                activeCalories: entry.calories,
                standMinutes: entry.standMinutes
            )
        }

        // Workout recommendation based on recovery
        let workoutRec: DisplayWorkoutType? = {
            if recoveryScore >= 80 { return .hiit }
            if recoveryScore >= 60 { return .zone2 }
            if recoveryScore >= 40 { return .yoga }
            return .rest
        }()

        // Stress level estimate from HRV (lower HRV = higher stress)
        let stressLevel: Double = {
            guard currentHRV > 0 else { return 50 }
            return max(0, min(100, 100 - (currentHRV / 80.0) * 100))
        }()

        // Cortisol estimate from stress
        let cortisolEstimate: CortisolLevel = {
            switch stressLevel {
            case 0..<25: return .low
            case 25..<50: return .normal
            case 50..<75: return .elevated
            default: return .high
            }
        }()

        // Weekly volume load
        let weeklyVolumeLoad = workouts.reduce(0.0) { $0 + Double($1.calories) }

        // Recovery debt level
        let recoveryDebt: RecoveryDebtLevel = {
            if recoveryScore >= 80 { return .none }
            if recoveryScore >= 60 { return .low }
            if recoveryScore >= 40 { return .moderate }
            if recoveryScore >= 20 { return .high }
            return .critical
        }()

        // Build muscle recovery map (placeholder — requires workout history analysis)
        let muscleMap = buildMuscleRecoveryMap(from: workouts)

        // Body zone status
        let zoneStatus = buildBodyZoneStatus(from: muscleMap)

        // Correlations (computed from historical data, use reasonable defaults)
        let correlations = buildCorrelations(hrv: currentHRV, sleepScore: sleep?.efficiency ?? 0)

        // Predictions
        let predictions = buildPredictions(recoveryScore: recoveryScore, hrv: currentHRV)

        data = PhysiologicalDimensionData(
            currentHRV: currentHRV,
            hrvVariabilityMs: computeHRVVariability(hrvTrend),
            hrvTrend: hrvDataPoints,
            restingHeartRate: restingHeartRate,
            rhrZone: rhrZone,
            recoveryScore: recoveryScore,
            recoveryFactors: recoveryFactors,
            readinessScore: readinessScore,
            peakPerformanceWindowStart: peakStart,
            peakPerformanceWindowEnd: peakEnd,
            workoutRecommendation: workoutRec,
            lastNightSleep: sleepSession,
            sleepDebt: sleepDebt,
            sleepTrend: sleepTrend,
            muscleRecoveryMap: muscleMap,
            bodyZoneStatus: zoneStatus,
            stressLevel: stressLevel,
            cortisolEstimate: cortisolEstimate,
            breathingRatePerMin: breathingRate,
            hourlyActivity: hourlyActivity,
            dailyRings: rings,
            stepCount: steps,
            activeCalories: Int(activity.activeCalories),
            workouts: workouts,
            weeklyVolumeLoad: weeklyVolumeLoad,
            recoveryDebt: recoveryDebt,
            correlations: correlations,
            predictions: predictions
        )
    }

    // MARK: - Helpers

    private func buildSleepSession(from sleep: SleepQueryResult?) -> SleepSession {
        guard let s = sleep else {
            // Return a minimal empty session
            let now = Date()
            return SleepSession(
                bedTime: now,
                wakeTime: now,
                totalDuration: 0,
                deepSleep: 0,
                coreSleep: 0,
                remSleep: 0,
                awakeTime: 0,
                efficiency: 0,
                score: 0
            )
        }

        let totalDuration = s.totalHours * 3600
        let deepSleep = Double(s.deepSleepMinutes) * 60
        let coreSleep = Double(s.coreSleepMinutes) * 60
        let remSleep = Double(s.remSleepMinutes) * 60
        let awakeTime = Double(s.awakeMinutes) * 60

        // Score: weighted combination of duration, efficiency, deep+REM
        let durationScore = min(1, s.totalHours / 8.0) * 40
        let efficiencyScore = (s.efficiency / 100.0) * 30
        let deepRemScore = min(1, Double(s.deepSleepMinutes + s.remSleepMinutes) / 180.0) * 30
        let score = Int(durationScore + efficiencyScore + deepRemScore)

        return SleepSession(
            bedTime: s.bedtime,
            wakeTime: s.wakeTime,
            totalDuration: totalDuration,
            deepSleep: deepSleep,
            coreSleep: coreSleep,
            remSleep: remSleep,
            awakeTime: awakeTime,
            efficiency: s.efficiency,
            score: score
        )
    }

    private func convertWorkout(_ hkWorkout: HKWorkout) -> WorkoutSession {
        let workoutType = CosmoWorkoutType.from(activityType: hkWorkout.workoutActivityType)
        let displayType = mapToDisplayType(workoutType)
        let calories = Int(hkWorkout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0)

        return WorkoutSession(
            type: displayType,
            date: hkWorkout.startDate,
            duration: hkWorkout.duration,
            calories: calories,
            intensity: min(5, hkWorkout.duration / (20 * 60)) // rough intensity from duration
        )
    }

    private func mapToDisplayType(_ cosmoType: CosmoWorkoutType) -> DisplayWorkoutType {
        switch cosmoType {
        case .strength, .functionalStrength, .coreTraining:
            return .strength
        case .hiit, .crossTraining:
            return .hiit
        case .running:
            return .running
        case .cycling:
            return .cycling
        case .swimming:
            return .swimming
        case .walking, .hiking:
            return .walking
        case .yoga, .mindfulness:
            return .yoga
        case .flexibility, .cooldown:
            return .stretching
        case .rowing, .elliptical, .stairClimbing, .pilates:
            return .cardio
        case .other:
            return .cardio
        }
    }

    private func computeRecoveryScore(hrv: Double, sleepEfficiency: Double, sleepHours: Double) -> Double {
        // Sleep quality: 30% weight
        let sleepScore = min(100, (sleepHours / 8.0) * 100) * 0.3

        // Sleep efficiency: 25% weight
        let effScore = sleepEfficiency * 0.25

        // HRV contribution: 25% weight (normalized to 60ms baseline)
        let hrvScore = hrv > 0 ? min(100, (hrv / 60.0) * 100) * 0.25 : 12.5

        // Base readiness: 20%
        let baseScore = 15.0

        return min(100, sleepScore + effScore + hrvScore + baseScore)
    }

    private func computeReadinessScore(recoveryScore: Double, hrv: Double, rhr: Int) -> Double {
        // Recovery is the main driver
        var score = recoveryScore * 0.6

        // HRV bonus (higher = better)
        if hrv >= 50 { score += 20 }
        else if hrv >= 40 { score += 15 }
        else if hrv >= 30 { score += 10 }
        else if hrv > 0 { score += 5 }

        // Resting HR bonus (lower = better)
        if rhr > 0 && rhr < 55 { score += 15 }
        else if rhr >= 55 && rhr < 65 { score += 10 }
        else if rhr >= 65 && rhr < 75 { score += 5 }

        return min(100, score)
    }

    private func computeHRVVariability(_ trend: [(date: Date, value: Double)]) -> Double {
        guard trend.count > 1 else { return 0 }
        let values = trend.map { $0.value }
        let mean = values.reduce(0, +) / Double(values.count)
        let squaredDiffs = values.map { pow($0 - mean, 2) }
        return sqrt(squaredDiffs.reduce(0, +) / Double(values.count - 1))
    }

    private func buildMuscleRecoveryMap(from workouts: [WorkoutSession]) -> [MuscleStatus] {
        // Build recovery estimates based on recent workout types
        var muscleGroups: [MuscleGroup: (lastWorked: Date?, strain: StrainLevel)] = [:]

        for group in MuscleGroup.allCases {
            muscleGroups[group] = (lastWorked: nil, strain: .low)
        }

        // Map workouts to muscle groups
        for workout in workouts {
            let groups = musclesForWorkoutType(workout.type)
            let strain: StrainLevel = workout.intensity >= 4 ? .high : (workout.intensity >= 2.5 ? .moderate : .low)

            for group in groups {
                let existing = muscleGroups[group]!
                if existing.lastWorked == nil || workout.date > existing.lastWorked! {
                    muscleGroups[group] = (lastWorked: workout.date, strain: strain)
                }
            }
        }

        return MuscleGroup.allCases.map { group in
            let info = muscleGroups[group]!
            let recovery: Double = {
                guard let lastWorked = info.lastWorked else { return 100 }
                let hoursSince = Date().timeIntervalSince(lastWorked) / 3600
                // Full recovery ~72 hours for high strain, 48 for moderate, 24 for low
                let recoveryTime: Double = {
                    switch info.strain {
                    case .high, .extreme: return 72
                    case .moderate: return 48
                    case .low: return 24
                    }
                }()
                return min(100, (hoursSince / recoveryTime) * 100)
            }()

            return MuscleStatus(
                muscleGroup: group,
                recoveryPercent: recovery,
                lastWorked: info.lastWorked,
                strain: info.strain
            )
        }
    }

    private func musclesForWorkoutType(_ type: DisplayWorkoutType) -> [MuscleGroup] {
        switch type {
        case .strength:
            return [.chest, .shoulders, .biceps, .triceps, .core]
        case .hiit:
            return [.quadriceps, .hamstrings, .glutes, .core, .shoulders]
        case .running:
            return [.quadriceps, .hamstrings, .calves, .glutes]
        case .cycling:
            return [.quadriceps, .hamstrings, .calves, .glutes]
        case .swimming:
            return [.shoulders, .chest, .core, .triceps]
        case .walking:
            return [.calves, .quadriceps]
        case .yoga, .stretching:
            return [.core, .hamstrings]
        case .cardio:
            return [.quadriceps, .calves, .core]
        case .zone2:
            return [.quadriceps, .hamstrings, .calves]
        case .rest:
            return []
        }
    }

    private func buildBodyZoneStatus(from muscles: [MuscleStatus]) -> [ZoneStatus] {
        func avgRecovery(_ groups: [MuscleGroup]) -> Double {
            let matching = muscles.filter { groups.contains($0.muscleGroup) }
            guard !matching.isEmpty else { return 100 }
            return matching.map(\.recoveryPercent).reduce(0, +) / Double(matching.count)
        }

        func issues(_ groups: [MuscleGroup]) -> [String] {
            muscles.filter { groups.contains($0.muscleGroup) && $0.recoveryPercent < 60 }
                .map { "\($0.muscleGroup.displayName) fatigue" }
        }

        return [
            ZoneStatus(zone: .head, healthPercent: 95),
            ZoneStatus(zone: .chest, healthPercent: avgRecovery([.chest, .shoulders]),
                       issues: issues([.chest, .shoulders])),
            ZoneStatus(zone: .arms, healthPercent: avgRecovery([.biceps, .triceps, .forearms]),
                       issues: issues([.biceps, .triceps, .forearms])),
            ZoneStatus(zone: .core, healthPercent: avgRecovery([.core, .obliques]),
                       issues: issues([.core, .obliques])),
            ZoneStatus(zone: .legs, healthPercent: avgRecovery([.quadriceps, .hamstrings, .calves, .glutes]),
                       issues: issues([.quadriceps, .hamstrings, .calves, .glutes]))
        ]
    }

    private func buildCorrelations(hrv: Double, sleepScore: Double) -> [PhysiologicalCorrelation] {
        [
            PhysiologicalCorrelation(
                sourceMetric: "HRV",
                targetMetric: "Focus",
                correlationCoefficient: 0.72,
                impactPercent: hrv > 40 ? 18 : -5,
                timeframe: "tomorrow",
                confidence: 0.85
            ),
            PhysiologicalCorrelation(
                sourceMetric: "Sleep",
                targetMetric: "Recovery",
                correlationCoefficient: 0.84,
                impactPercent: sleepScore > 80 ? 23 : -10,
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
    }

    private func buildPredictions(recoveryScore: Double, hrv: Double) -> [HealthPrediction] {
        var predictions: [HealthPrediction] = []

        if recoveryScore >= 70 && hrv >= 40 {
            predictions.append(HealthPrediction(
                condition: "Recovery trending well",
                prediction: "Tomorrow's HRV projected to remain stable",
                impact: "Good conditions for intense training",
                confidence: 0.82,
                basedOn: ["Recent recovery trend", "HRV stability"],
                actions: ["Schedule high-intensity workout", "Maintain sleep routine"]
            ))
        } else if recoveryScore < 50 {
            predictions.append(HealthPrediction(
                condition: "Recovery deficit detected",
                prediction: "Readiness may drop further without rest",
                impact: "Risk of overtraining if pushing hard",
                confidence: 0.78,
                basedOn: ["Low recovery score", "Elevated strain load"],
                actions: ["Prioritize sleep", "Light activity only", "Consider rest day"]
            ))
        }

        return predictions
    }
}
