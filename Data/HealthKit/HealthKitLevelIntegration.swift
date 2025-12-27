import Foundation
import HealthKit

// MARK: - HealthKit Level Integration

/// Integrates Apple Watch health data with the Cosmo Level System
/// Connects Physiological dimension to real biometric data
public actor HealthKitLevelIntegration {

    private let atomFactory: HealthKitAtomFactory
    private let readinessCalculator: ReadinessCalculator
    private let configuration: HealthKitConfiguration
    private let xpEngine: XPCalculationEngine

    public init(
        atomFactory: HealthKitAtomFactory = HealthKitAtomFactory(),
        readinessCalculator: ReadinessCalculator = ReadinessCalculator(),
        configuration: HealthKitConfiguration = .shared,
        xpEngine: XPCalculationEngine = XPCalculationEngine()
    ) {
        self.atomFactory = atomFactory
        self.readinessCalculator = readinessCalculator
        self.configuration = configuration
        self.xpEngine = xpEngine
    }

    // MARK: - Daily Health Processing

    /// Process all health data for a day and generate XP events
    public func processDailyHealth(for date: Date) async throws -> HealthProcessingResult {
        var result = HealthProcessingResult(date: date)

        // 1. Fetch and convert health atoms
        let healthAtoms = try await atomFactory.fetchAndConvertDailyHealth(for: date)
        result.atomsCreated = healthAtoms

        // 2. Calculate XP for each health event
        let xpEvents = calculateHealthXP(from: healthAtoms)
        result.xpEvents = xpEvents
        result.totalXP = xpEvents.map { $0.finalAmount }.reduce(0, +)

        // 3. Calculate readiness score
        let readinessInputs = try await readinessCalculator.fetchReadinessInputs(for: date)
        let readinessScore = await readinessCalculator.calculateReadiness(readinessInputs)
        result.readinessScore = readinessScore

        // 4. Calculate NELO adjustment based on health metrics
        let neloAdjustment = calculateHealthNELO(
            readiness: readinessScore,
            atoms: healthAtoms
        )
        result.neloAdjustment = neloAdjustment

        // 5. Create readiness atom
        let readinessAtom = await readinessCalculator.createReadinessAtom(score: readinessScore)
        result.readinessAtom = readinessAtom

        return result
    }

    // MARK: - XP Calculation

    private func calculateHealthXP(from atoms: [Atom]) -> [XPAward] {
        var awards: [XPAward] = []

        for atom in atoms {
            let award = calculateXPForAtom(atom)
            if let award = award {
                awards.append(award)
            }
        }

        return awards
    }

    private func calculateXPForAtom(_ atom: Atom) -> XPAward? {
        switch atom.type {
        case .hrvReading:
            return calculateHRVXP(atom)
        case .sleepRecord:
            return calculateSleepXP(atom)
        case .workout:
            return calculateWorkoutXP(atom)
        case .recoveryScore:
            return calculateReadinessXP(atom)
        case .activityRing:
            return calculateActivityRingXP(atom)
        default:
            return nil
        }
    }

    private func calculateHRVXP(_ atom: Atom) -> XPAward? {
        guard let metadataString = atom.metadata,
              let data = metadataString.data(using: .utf8),
              let metadata = try? JSONDecoder().decode(HRVMeasurementMetadata.self, from: data) else {
            return nil
        }

        // Base XP for logging HRV
        var xp = 5

        // Bonus for high quality measurement
        if metadata.measurementType == .nighttime {
            xp += 5  // Nighttime measurements most reliable
        }

        // Bonus for being in top percentiles
        if let rank = metadata.percentileRank {
            if rank >= 0.90 {
                xp += 10  // Elite HRV bonus
            } else if rank >= 0.75 {
                xp += 5   // Good HRV bonus
            }
        }

        return XPAward(xp: xp, dimension: .physiological)
    }

    private func calculateSleepXP(_ atom: Atom) -> XPAward? {
        guard let metadataString = atom.metadata,
              let data = metadataString.data(using: .utf8),
              let metadata = try? JSONDecoder().decode(HKImportedSleepMetadata.self, from: data) else {
            return nil
        }

        // Base XP for logging sleep
        var xp = 10

        let durationHours = metadata.totalDuration / 3600

        // Bonus for optimal sleep duration (7-9 hours)
        if durationHours >= 7 && durationHours <= 9 {
            xp += 15  // Optimal duration bonus
        } else if durationHours >= 6 && durationHours < 7 {
            xp += 5   // Acceptable duration
        }

        // Bonus for high sleep efficiency
        if metadata.sleepEfficiency >= 0.90 {
            xp += 10  // Excellent efficiency
        } else if metadata.sleepEfficiency >= 0.85 {
            xp += 5   // Good efficiency
        }

        // Bonus for good deep sleep
        let totalSleep = metadata.deepSleepMinutes + metadata.remSleepMinutes + metadata.coreSleepMinutes
        let deepPercentage = totalSleep > 0 ? Double(metadata.deepSleepMinutes) / Double(totalSleep) : 0
        if deepPercentage >= 0.20 {
            xp += 10  // Excellent deep sleep
        } else if deepPercentage >= 0.15 {
            xp += 5   // Good deep sleep
        }

        // Bonus XP for optimal conditions
        if durationHours >= 7 && durationHours <= 9 && metadata.sleepEfficiency >= 0.90 {
            xp += 5  // Optimal sleep bonus
        } else if metadata.sleepEfficiency >= 0.90 {
            xp += 3  // Sleep efficiency bonus
        }

        return XPAward(xp: xp, dimension: .physiological)
    }

    private func calculateWorkoutXP(_ atom: Atom) -> XPAward? {
        guard let metadataString = atom.metadata,
              let data = metadataString.data(using: .utf8),
              let metadata = try? JSONDecoder().decode(HKImportedWorkoutMetadata.self, from: data) else {
            return nil
        }

        // Base XP for completing workout
        var xp = 20

        // Duration bonus
        let durationMinutes = metadata.duration / 60
        if durationMinutes >= 60 {
            xp += 15
        } else if durationMinutes >= 45 {
            xp += 10
        } else if durationMinutes >= 30 {
            xp += 5
        }

        // Strain score bonus (WHOOP-style 0-21)
        if metadata.strainScore >= 18 {
            xp += 25  // Extreme strain
        } else if metadata.strainScore >= 14 {
            xp += 15  // High strain
        } else if metadata.strainScore >= 10 {
            xp += 10  // Moderate strain
        }

        // Intensity bonus (based on average HR zones)
        if let avgZone = averageZone(from: metadata.zones) {
            if avgZone >= 4 {
                xp += 10  // High intensity
            } else if avgZone >= 3 {
                xp += 5   // Moderate intensity
            }
        }

        return XPAward(xp: xp, dimension: .physiological)
    }

    private func calculateReadinessXP(_ atom: Atom) -> XPAward? {
        guard let metadataString = atom.metadata,
              let data = metadataString.data(using: .utf8),
              let metadata = try? JSONDecoder().decode(HKReadinessScoreMetadata.self, from: data) else {
            return nil
        }

        // Base XP for checking readiness
        var xp = 5

        // Bonus for high readiness (indicates good recovery habits)
        if metadata.overallScore >= 85 {
            xp += 25  // Peak readiness bonus
        } else if metadata.overallScore >= 70 {
            xp += 10  // Good readiness bonus
        }

        return XPAward(xp: xp, dimension: .physiological)
    }

    private func calculateActivityRingXP(_ atom: Atom) -> XPAward? {
        guard let metadataString = atom.metadata,
              let data = metadataString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let allClosed = json["allRingsClosed"] as? Bool ?? false
        let moveProgress = json["moveProgress"] as? Double ?? 0
        let exerciseProgress = json["exerciseProgress"] as? Double ?? 0
        let standProgress = json["standProgress"] as? Double ?? 0

        // Base XP
        var xp = 5

        // Ring closure bonuses
        if moveProgress >= 1.0 { xp += 10 }
        if exerciseProgress >= 1.0 { xp += 10 }
        if standProgress >= 1.0 { xp += 5 }

        // All rings closed bonus
        if allClosed {
            xp += 20
        }

        return XPAward(xp: xp, dimension: .physiological)
    }

    private func averageZone(from zones: [HKHeartRateZone]) -> Double? {
        guard !zones.isEmpty else { return nil }
        let weightedSum = zones.reduce(0.0) { $0 + Double($1.zone) * $1.percentageOfWorkout }
        return weightedSum
    }

    // MARK: - NELO Calculation

    private func calculateHealthNELO(
        readiness: HKReadinessScoreMetadata,
        atoms: [Atom]
    ) -> NELOAdjustment {
        // NELO adjustments based on health performance vs expectations
        var change = 0
        var reasons: [String] = []

        // Readiness-based adjustment
        if readiness.overallScore >= 85 {
            change += 10
            reasons.append("Peak readiness (+10)")
        } else if readiness.overallScore >= 70 {
            change += 5
            reasons.append("Good readiness (+5)")
        } else if readiness.overallScore < 50 {
            change -= 5
            reasons.append("Low readiness (-5)")
        }

        // HRV trend adjustment
        if readiness.hrvContribution >= 85 {
            change += 8
            reasons.append("Excellent HRV (+8)")
        } else if readiness.hrvContribution < 50 {
            change -= 5
            reasons.append("Poor HRV (-5)")
        }

        // Sleep quality adjustment
        let sleepAtom = atoms.first { $0.type == .sleepRecord }
        if let sleepAtom = sleepAtom,
           let metadataString = sleepAtom.metadata,
           let data = metadataString.data(using: .utf8),
           let sleepMeta = try? JSONDecoder().decode(HKImportedSleepMetadata.self, from: data) {

            if sleepMeta.sleepEfficiency >= 0.90 {
                change += 5
                reasons.append("Excellent sleep efficiency (+5)")
            } else if sleepMeta.sleepEfficiency < 0.75 {
                change -= 5
                reasons.append("Poor sleep efficiency (-5)")
            }
        }

        // Workout performance
        let workoutAtoms = atoms.filter { $0.type == .workout }
        if !workoutAtoms.isEmpty {
            let avgStrain = workoutAtoms.compactMap { atom -> Double? in
                guard let metadataString = atom.metadata,
                      let data = metadataString.data(using: .utf8),
                      let meta = try? JSONDecoder().decode(HKImportedWorkoutMetadata.self, from: data) else {
                    return nil
                }
                return meta.strainScore
            }.reduce(0, +) / Double(workoutAtoms.count)

            if avgStrain >= 14 {
                change += 5
                reasons.append("High workout strain (+5)")
            }
        }

        return NELOAdjustment(
            dimension: "physiological",
            change: change,
            newNELO: 0,  // Will be set by caller
            reasons: reasons
        )
    }

    // MARK: - Background Observation

    /// Start observing HealthKit for real-time updates
    public func startBackgroundObservation() async throws {
        guard configuration.isHealthDataAvailable else {
            throw HealthKitError.notAvailable
        }

        try await configuration.enableBackgroundDelivery()

        // Set up observers for each background delivery type
        for type in configuration.backgroundDeliveryTypes {
            guard let sampleType = type as? HKSampleType else { continue }
            setupObserver(for: sampleType)
        }
    }

    private func setupObserver(for type: HKSampleType) {
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completionHandler, error in
            guard error == nil else {
                completionHandler()
                return
            }

            Task {
                await self?.handleNewSamples(for: type)
                completionHandler()
            }
        }

        configuration.healthStore.execute(query)
    }

    private func handleNewSamples(for type: HKSampleType) async {
        // Query the most recent sample and create atoms
        _ = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-3600),  // Last hour
            end: Date(),
            options: .strictStartDate
        )

        // Would integrate with atom factory to create real-time atoms
    }
}

// MARK: - Health Processing Result

public struct HealthProcessingResult: Sendable {
    public let date: Date
    public var atomsCreated: [Atom] = []
    public var xpEvents: [XPAward] = []
    public var totalXP: Int = 0
    public var readinessScore: HKReadinessScoreMetadata?
    public var readinessAtom: Atom?
    public var neloAdjustment: NELOAdjustment?

    public init(date: Date) {
        self.date = date
    }

    public var summary: String {
        var lines: [String] = []
        lines.append("Health Processing for \(date.formatted(date: .abbreviated, time: .omitted))")
        lines.append("Atoms created: \(atomsCreated.count)")
        lines.append("Total XP: \(totalXP)")
        if let readiness = readinessScore {
            lines.append("Readiness: \(Int(readiness.overallScore))% (\(readiness.scoreCategory))")
        }
        if let nelo = neloAdjustment, nelo.change != 0 {
            lines.append("NELO change: \(nelo.change > 0 ? "+" : "")\(nelo.change)")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - NELO Adjustment

public struct NELOAdjustment: Sendable {
    public let dimension: String
    public let change: Int
    public var newNELO: Int
    public let reasons: [String]

    public init(dimension: String, change: Int, newNELO: Int, reasons: [String]) {
        self.dimension = dimension
        self.change = change
        self.newNELO = newNELO
        self.reasons = reasons
    }
}

// MARK: - XP Award Extension

extension XPAward {
    /// Convenience initializer for HealthKit XP awards
    init(
        xp: Int,
        dimension: LevelDimension,
        multiplier: Double = 1.0
    ) {
        self.init(
            baseAmount: xp,
            finalAmount: Int(Double(xp) * multiplier),
            multiplier: multiplier,
            streakMultiplier: 1.0,
            dimension: dimension
        )
    }
}

// MARK: - Health Service

/// High-level health service that coordinates all health-related functionality
@MainActor
public final class HealthKitService: ObservableObject {

    @Published public private(set) var isAuthorized: Bool = false
    @Published public private(set) var latestReadiness: HKReadinessScoreMetadata?
    @Published public private(set) var todayHealthAtoms: [Atom] = []
    @Published public private(set) var isProcessing: Bool = false

    private let integration: HealthKitLevelIntegration
    private let configuration: HealthKitConfiguration

    public init() {
        self.integration = HealthKitLevelIntegration()
        self.configuration = .shared
    }

    /// Request HealthKit authorization
    public func requestAuthorization() async throws {
        isAuthorized = try await configuration.requestAuthorization()
    }

    /// Process today's health data
    public func processTodayHealth() async throws -> HealthProcessingResult {
        isProcessing = true
        defer { isProcessing = false }

        let result = try await integration.processDailyHealth(for: Date())

        await MainActor.run {
            self.todayHealthAtoms = result.atomsCreated
            self.latestReadiness = result.readinessScore
        }

        return result
    }

    /// Start background observation
    public func startBackgroundObservation() async throws {
        try await integration.startBackgroundObservation()
    }

    /// Get quick readiness summary
    public var readinessSummary: String {
        guard let readiness = latestReadiness else {
            return "No readiness data available"
        }
        return "\(Int(readiness.overallScore))% - \(readiness.scoreCategory)"
    }
}
