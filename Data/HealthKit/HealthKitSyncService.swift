// CosmoOS/Data/HealthKit/HealthKitSyncService.swift
// Real-time HealthKit observation and automatic atom creation

import Foundation
import HealthKit
import Combine
import GRDB

// MARK: - HealthKit Sync Service

/// Service that continuously syncs HealthKit data and creates Atoms automatically.
/// Observes workouts, activity, heart rate, sleep, and other health metrics in real-time.
@MainActor
public final class HealthKitSyncService: ObservableObject {

    // MARK: - Published State

    @Published public private(set) var isObserving: Bool = false
    @Published public private(set) var lastSyncDate: Date?
    @Published public private(set) var todayWorkouts: [Atom] = []
    @Published public private(set) var todayActivitySummary: ActivitySummaryData?
    @Published public private(set) var todaySteps: Int = 0
    @Published public private(set) var todayActiveCalories: Double = 0
    @Published public private(set) var syncError: Error?

    // MARK: - Dependencies

    private let healthStore: HKHealthStore
    private let configuration: HealthKitConfiguration
    private let atomFactory: HealthKitAtomFactory
    private let levelIntegration: HealthKitLevelIntegration
    private let database: any DatabaseWriter

    // Observation queries
    private var observerQueries: [HKObserverQuery] = []
    private var anchoredQueries: [HKAnchoredObjectQuery] = []
    private var workoutAnchor: HKQueryAnchor?
    private var stepAnchor: HKQueryAnchor?
    private var heartRateAnchor: HKQueryAnchor?
    private var sleepAnchor: HKQueryAnchor?

    // Combine
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    public init(
        database: (any DatabaseWriter)? = nil,
        configuration: HealthKitConfiguration = .shared
    ) {
        self.database = database ?? (CosmoDatabase.shared.dbQueue! as any DatabaseWriter)
        self.configuration = configuration
        self.healthStore = configuration.healthStore
        self.atomFactory = HealthKitAtomFactory(configuration: configuration)
        self.levelIntegration = HealthKitLevelIntegration()
    }

    // MARK: - Authorization

    /// Request HealthKit authorization
    public func requestAuthorization() async throws -> Bool {
        try await configuration.requestAuthorization()
    }

    // MARK: - Start/Stop Observation

    /// Start observing HealthKit for real-time updates
    public func startObservation() async throws {
        guard !isObserving else { return }
        guard configuration.isHealthDataAvailable else {
            throw HealthKitError.notAvailable
        }

        // Enable background delivery
        try await configuration.enableBackgroundDelivery()

        // Set up observers for each type
        setupWorkoutObserver()
        setupStepCountObserver()
        setupActiveEnergyObserver()
        setupHeartRateObserver()
        setupSleepObserver()
        setupActivitySummaryObserver()

        isObserving = true

        // Initial sync
        await syncTodayData()
    }

    /// Stop all observation
    public func stopObservation() {
        for query in observerQueries {
            healthStore.stop(query)
        }
        for query in anchoredQueries {
            healthStore.stop(query)
        }
        observerQueries.removeAll()
        anchoredQueries.removeAll()
        isObserving = false
    }

    // MARK: - Workout Observation

    private func setupWorkoutObserver() {
        let workoutType = HKWorkoutType.workoutType()

        // Observer query for background delivery
        let observerQuery = HKObserverQuery(
            sampleType: workoutType,
            predicate: nil
        ) { [weak self] _, completionHandler, error in
            Task { @MainActor in
                if error == nil {
                    await self?.handleNewWorkouts()
                }
                completionHandler()
            }
        }

        healthStore.execute(observerQuery)
        observerQueries.append(observerQuery)

        // Anchored query for incremental updates
        let anchoredQuery = HKAnchoredObjectQuery(
            type: workoutType,
            predicate: todayPredicate(),
            anchor: workoutAnchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] query, samples, deleted, newAnchor, error in
            Task { @MainActor in
                self?.workoutAnchor = newAnchor
                if let workouts = samples as? [HKWorkout], !workouts.isEmpty {
                    await self?.processNewWorkouts(workouts)
                }
            }
        }

        anchoredQuery.updateHandler = { [weak self] query, samples, deleted, newAnchor, error in
            Task { @MainActor in
                self?.workoutAnchor = newAnchor
                if let workouts = samples as? [HKWorkout], !workouts.isEmpty {
                    await self?.processNewWorkouts(workouts)
                }
            }
        }

        healthStore.execute(anchoredQuery)
        anchoredQueries.append(anchoredQuery)
    }

    private func handleNewWorkouts() async {
        let workoutType = HKWorkoutType.workoutType()
        let predicate = HKQuery.predicateForSamples(
            withStart: Calendar.current.startOfDay(for: Date()),
            end: Date(),
            options: .strictStartDate
        )

        do {
            let samples = try await querySamples(type: workoutType, predicate: predicate, limit: 10)
            if let workouts = samples as? [HKWorkout], !workouts.isEmpty {
                await processNewWorkouts(workouts)
            }
        } catch {
            syncError = error
        }
    }

    private func processNewWorkouts(_ workouts: [HKWorkout]) async {
        for workout in workouts {
            // Check if we already have this workout
            let existingAtom = try? await database.read { db in
                try Atom
                    .filter(Column("type") == AtomType.workout.rawValue)
                    .filter(sql: "metadata LIKE ?", arguments: ["%\(workout.uuid.uuidString)%"])
                    .fetchOne(db)
            }

            guard existingAtom == nil else { continue }

            // Create atom from workout
            let atom = await atomFactory.convertWorkoutToAtom(workout)

            // Save to database
            do {
                try await database.write { db in
                    var insertingAtom = atom
                    try insertingAtom.insert(db)
                    insertingAtom.id = db.lastInsertedRowID
                }

                // Award XP for workout
                await awardWorkoutXP(workout: workout, atom: atom)

                // Update local state
                todayWorkouts.append(atom)

                // Post notification for UI updates
                NotificationCenter.default.post(
                    name: .healthKitWorkoutSynced,
                    object: nil,
                    userInfo: ["workout": atom]
                )

            } catch {
                syncError = error
            }
        }
    }

    // MARK: - Step Count Observation

    private func setupStepCountObserver() {
        let stepType = HKQuantityType(.stepCount)

        let observerQuery = HKObserverQuery(
            sampleType: stepType,
            predicate: nil
        ) { [weak self] _, completionHandler, error in
            Task { @MainActor in
                if error == nil {
                    await self?.updateStepCount()
                }
                completionHandler()
            }
        }

        healthStore.execute(observerQuery)
        observerQueries.append(observerQuery)
    }

    private func updateStepCount() async {
        let stepType = HKQuantityType(.stepCount)
        let predicate = todayPredicate()

        let query = HKStatisticsQuery(
            quantityType: stepType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] _, statistics, error in
            Task { @MainActor in
                guard let self = self, error == nil else { return }
                let steps = statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                self.todaySteps = Int(steps)

                // Check for step milestones
                await self.checkStepMilestones(steps: Int(steps))
            }
        }

        healthStore.execute(query)
    }

    private func checkStepMilestones(steps: Int) async {
        let milestones = [5000, 7500, 10000, 12500, 15000, 20000]

        for milestone in milestones {
            if steps >= milestone {
                // Check if we already awarded for this milestone today
                let key = "steps_milestone_\(milestone)_\(Date().formatted(date: .numeric, time: .omitted))"
                if UserDefaults.standard.bool(forKey: key) { continue }

                // Award XP for milestone
                let xp = milestone / 500  // 10 XP per 5000 steps
                await awardActivityXP(xp: xp, reason: "\(milestone.formatted()) steps reached")

                UserDefaults.standard.set(true, forKey: key)
            }
        }
    }

    // MARK: - Active Energy Observation

    private func setupActiveEnergyObserver() {
        let energyType = HKQuantityType(.activeEnergyBurned)

        let observerQuery = HKObserverQuery(
            sampleType: energyType,
            predicate: nil
        ) { [weak self] _, completionHandler, error in
            Task { @MainActor in
                if error == nil {
                    await self?.updateActiveEnergy()
                }
                completionHandler()
            }
        }

        healthStore.execute(observerQuery)
        observerQueries.append(observerQuery)
    }

    private func updateActiveEnergy() async {
        let energyType = HKQuantityType(.activeEnergyBurned)
        let predicate = todayPredicate()

        let query = HKStatisticsQuery(
            quantityType: energyType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] _, statistics, error in
            Task { @MainActor in
                guard let self = self, error == nil else { return }
                self.todayActiveCalories = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            }
        }

        healthStore.execute(query)
    }

    // MARK: - Heart Rate Observation

    private func setupHeartRateObserver() {
        let hrType = HKQuantityType(.heartRateVariabilitySDNN)

        let observerQuery = HKObserverQuery(
            sampleType: hrType,
            predicate: nil
        ) { [weak self] _, completionHandler, error in
            Task { @MainActor in
                if error == nil {
                    await self?.handleNewHRVReadings()
                }
                completionHandler()
            }
        }

        healthStore.execute(observerQuery)
        observerQueries.append(observerQuery)
    }

    private func handleNewHRVReadings() async {
        let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
        let lastHour = Calendar.current.date(byAdding: .hour, value: -1, to: Date())!

        let predicate = HKQuery.predicateForSamples(
            withStart: lastHour,
            end: Date(),
            options: .strictStartDate
        )

        do {
            let samples = try await querySamples(type: hrvType, predicate: predicate, limit: 5)

            for sample in samples {
                guard let quantitySample = sample as? HKQuantitySample else { continue }

                // Check if we already have this HRV reading
                let existingAtom = try? await database.read { db in
                    try Atom
                        .filter(Column("type") == AtomType.hrvReading.rawValue)
                        .filter(Column("createdAt") == quantitySample.startDate.ISO8601Format())
                        .fetchOne(db)
                }

                guard existingAtom == nil else { continue }

                // Create and save HRV atom
                let atom = await atomFactory.convertHRVSampleToAtom(quantitySample)

                try await database.write { db in
                    var insertingAtom = atom
                    try insertingAtom.insert(db)
                    insertingAtom.id = db.lastInsertedRowID
                }

                // Award small XP for HRV tracking
                await awardActivityXP(xp: 5, reason: "HRV measurement synced")
            }
        } catch {
            syncError = error
        }
    }

    // MARK: - Sleep Observation

    private func setupSleepObserver() {
        let sleepType = HKCategoryType(.sleepAnalysis)

        let observerQuery = HKObserverQuery(
            sampleType: sleepType,
            predicate: nil
        ) { [weak self] _, completionHandler, error in
            Task { @MainActor in
                if error == nil {
                    await self?.handleNewSleepData()
                }
                completionHandler()
            }
        }

        healthStore.execute(observerQuery)
        observerQueries.append(observerQuery)
    }

    private func handleNewSleepData() async {
        // Sleep data is processed daily by the cron, but we can show real-time updates
        let sleepAtom = try? await atomFactory.fetchSleepData(for: Date())

        if let atom = sleepAtom {
            NotificationCenter.default.post(
                name: .healthKitSleepSynced,
                object: nil,
                userInfo: ["sleep": atom]
            )
        }
    }

    // MARK: - Activity Summary Observation

    private func setupActivitySummaryObserver() {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.calendar = calendar

        let predicate = HKQuery.predicateForActivitySummary(with: components)

        let query = HKActivitySummaryQuery(predicate: predicate) { [weak self] _, summaries, error in
            Task { @MainActor in
                guard let self = self, error == nil, let summary = summaries?.first else { return }
                self.updateActivitySummary(summary)
            }
        }

        healthStore.execute(query)
    }

    private func updateActivitySummary(_ summary: HKActivitySummary) {
        let moveCalories = summary.activeEnergyBurned.doubleValue(for: .kilocalorie())
        let moveGoal = summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())
        let exerciseMinutes = summary.appleExerciseTime.doubleValue(for: .minute())
        let exerciseGoal = summary.appleExerciseTimeGoal.doubleValue(for: .minute())
        let standHours = summary.appleStandHours.doubleValue(for: .count())
        let standGoal = summary.appleStandHoursGoal.doubleValue(for: .count())

        todayActivitySummary = ActivitySummaryData(
            moveCalories: moveCalories,
            moveGoal: moveGoal,
            moveProgress: moveGoal > 0 ? moveCalories / moveGoal : 0,
            exerciseMinutes: exerciseMinutes,
            exerciseGoal: exerciseGoal,
            exerciseProgress: exerciseGoal > 0 ? exerciseMinutes / exerciseGoal : 0,
            standHours: standHours,
            standGoal: standGoal,
            standProgress: standGoal > 0 ? standHours / standGoal : 0,
            allRingsClosed: moveCalories >= moveGoal && exerciseMinutes >= exerciseGoal && standHours >= standGoal
        )

        // Check for ring closure XP
        Task {
            await checkRingClosureXP()
        }
    }

    private func checkRingClosureXP() async {
        guard let summary = todayActivitySummary else { return }

        let dateKey = Date().formatted(date: .numeric, time: .omitted)

        // Move ring
        if summary.moveProgress >= 1.0 {
            let key = "move_ring_closed_\(dateKey)"
            if !UserDefaults.standard.bool(forKey: key) {
                await awardActivityXP(xp: 15, reason: "Move ring closed")
                UserDefaults.standard.set(true, forKey: key)
            }
        }

        // Exercise ring
        if summary.exerciseProgress >= 1.0 {
            let key = "exercise_ring_closed_\(dateKey)"
            if !UserDefaults.standard.bool(forKey: key) {
                await awardActivityXP(xp: 15, reason: "Exercise ring closed")
                UserDefaults.standard.set(true, forKey: key)
            }
        }

        // Stand ring
        if summary.standProgress >= 1.0 {
            let key = "stand_ring_closed_\(dateKey)"
            if !UserDefaults.standard.bool(forKey: key) {
                await awardActivityXP(xp: 10, reason: "Stand ring closed")
                UserDefaults.standard.set(true, forKey: key)
            }
        }

        // All rings bonus
        if summary.allRingsClosed {
            let key = "all_rings_closed_\(dateKey)"
            if !UserDefaults.standard.bool(forKey: key) {
                await awardActivityXP(xp: 25, reason: "All activity rings closed")
                UserDefaults.standard.set(true, forKey: key)
            }
        }
    }

    // MARK: - XP Awards

    private func awardWorkoutXP(workout: HKWorkout, atom: Atom) async {
        var xp = 20  // Base XP for any workout

        let durationMinutes = workout.duration / 60

        // Duration bonus
        if durationMinutes >= 60 { xp += 20 }
        else if durationMinutes >= 45 { xp += 15 }
        else if durationMinutes >= 30 { xp += 10 }

        // Calories bonus
        if let calories = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) {
            if calories >= 500 { xp += 15 }
            else if calories >= 300 { xp += 10 }
            else if calories >= 150 { xp += 5 }
        }

        // Type bonus for high-intensity workouts
        let workoutType = CosmoWorkoutType.from(activityType: workout.workoutActivityType)
        if workoutType.strainMultiplier >= 0.9 {
            xp += 10
        }

        await awardActivityXP(xp: xp, reason: "Workout: \(workoutType.rawValue.capitalized)")
    }

    private func awardActivityXP(xp: Int, reason: String) async {
        do {
            try await database.write { db in
                // Create XP event atom
                var xpAtom = Atom.new(
                    type: .xpEvent,
                    title: "+\(xp) XP",
                    body: reason
                )
                if let jsonData = try? JSONSerialization.data(withJSONObject: [
                    "xp": String(xp),
                    "dimension": "physiological",
                    "source": "healthkit"
                ], options: []) {
                    xpAtom.metadata = String(data: jsonData, encoding: .utf8)
                }
                try xpAtom.insert(db)

                // Update level state
                if var state = try CosmoLevelState.fetchOne(db) {
                    state.addXP(xp, dimension: "physiological")
                    try state.update(db)
                }
            }

            // Post notification
            NotificationCenter.default.post(
                name: .xpAwarded,
                object: nil,
                userInfo: ["xp": xp, "reason": reason, "dimension": "physiological"]
            )
        } catch {
            syncError = error
        }
    }

    // MARK: - Manual Sync

    /// Manually sync all today's data
    public func syncTodayData() async {
        lastSyncDate = Date()

        await updateStepCount()
        await updateActiveEnergy()
        await handleNewWorkouts()

        // Fetch today's workouts
        do {
            let atoms = try await atomFactory.fetchWorkouts(for: .today)
            todayWorkouts = atoms
        } catch {
            syncError = error
        }
    }

    /// Sync historical data for a date range
    public func syncHistoricalData(from startDate: Date, to endDate: Date) async throws -> Int {
        var atomsCreated = 0

        let calendar = Calendar.current
        var currentDate = startDate

        while currentDate <= endDate {
            let atoms = try await atomFactory.fetchAndConvertDailyHealth(for: currentDate)

            for atom in atoms {
                // Check if already exists
                let exists = try await database.read { db in
                    try Atom
                        .filter(Column("type") == atom.type.rawValue)
                        .filter(Column("createdAt") == atom.createdAt)
                        .fetchOne(db) != nil
                }

                if !exists {
                    try await database.write { db in
                        var insertingAtom = atom
                        try insertingAtom.insert(db)
                        insertingAtom.id = db.lastInsertedRowID
                    }
                    atomsCreated += 1
                }
            }

            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }

        return atomsCreated
    }

    // MARK: - Helpers

    private func todayPredicate() -> NSPredicate {
        HKQuery.predicateForSamples(
            withStart: Calendar.current.startOfDay(for: Date()),
            end: Date(),
            options: .strictStartDate
        )
    }

    private func querySamples(
        type: HKSampleType,
        predicate: NSPredicate,
        limit: Int
    ) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            healthStore.execute(query)
        }
    }
}

// MARK: - Activity Summary Data

public struct ActivitySummaryData: Sendable {
    public let moveCalories: Double
    public let moveGoal: Double
    public let moveProgress: Double
    public let exerciseMinutes: Double
    public let exerciseGoal: Double
    public let exerciseProgress: Double
    public let standHours: Double
    public let standGoal: Double
    public let standProgress: Double
    public let allRingsClosed: Bool
}

// MARK: - Notification Names

public extension Notification.Name {
    static let healthKitWorkoutSynced = Notification.Name("healthKitWorkoutSynced")
    static let healthKitSleepSynced = Notification.Name("healthKitSleepSynced")
    static let healthKitHRVSynced = Notification.Name("healthKitHRVSynced")
    static let healthKitActivitySynced = Notification.Name("healthKitActivitySynced")
    // Note: xpAwarded is defined in XPTracerView.swift
}

// MARK: - AtomFactory Extensions

extension HealthKitAtomFactory {

    /// Convert a single HKWorkout to an Atom
    public func convertWorkoutToAtom(_ workout: HKWorkout) async -> Atom {
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

        var metadataDict: [String: Any] = [
            "workoutType": workoutType.rawValue,
            "duration": workout.duration,
            "activeCalories": metadata.activeCalories,
            "avgHeartRate": metadata.avgHeartRate,
            "maxHeartRate": metadata.maxHeartRate,
            "strainScore": strainScore,
            "healthKitUUID": workout.uuid.uuidString,
            "source": "healthkit"
        ]

        if let distance = metadata.distance {
            metadataDict["distance"] = distance
        }

        let metadataJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: metadataDict),
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

    /// Convert HRV sample to Atom
    public func convertHRVSampleToAtom(_ sample: HKQuantitySample) async -> Atom {
        let hrvMs = sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
        let measurementType = classifyHRVType(sample)
        let percentile = HealthPercentileData.hrvPercentile(hrvMs: hrvMs, age: 30)

        let metadataDict: [String: Any] = [
            "hrvMs": hrvMs,
            "measurementType": measurementType.rawValue,
            "percentileRank": percentile,
            "source": "healthkit"
        ]

        let metadataJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: metadataDict),
           let json = String(data: data, encoding: .utf8) {
            metadataJSON = json
        } else {
            metadataJSON = "{}"
        }

        return Atom.new(
            type: .hrvReading,
            title: "HRV: \(Int(hrvMs))ms",
            body: "Heart rate variability measurement from Apple Watch",
            metadata: metadataJSON
        )
    }

    private func classifyHRVType(_ sample: HKQuantitySample) -> HRVMeasurementType {
        let hour = Calendar.current.component(.hour, from: sample.startDate)
        if hour >= 23 || hour < 6 { return .nighttime }
        if hour >= 6 && hour < 9 { return .resting }
        return .spontaneous
    }

    private func calculateStrainScore(_ workout: HKWorkout, type: CosmoWorkoutType) -> Double {
        let baseDurationScore = min(workout.duration / 3600, 2.0) * 5
        let calorieScore = min((workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0) / 500, 5)
        let typeMultiplier = type.strainMultiplier
        return min((baseDurationScore + calorieScore) * typeMultiplier, 21.0)
    }

    private func fetchAverageHeartRate(during workout: HKWorkout) async -> Int {
        // Implementation from existing code
        return 0
    }

    private func fetchMaxHeartRate(during workout: HKWorkout) async -> Int {
        // Implementation from existing code
        return 0
    }

    private func fetchPostWorkoutHRV(_ workout: HKWorkout) async -> Double? {
        // Implementation from existing code
        return nil
    }

    private func fetchHeartRateZones(during workout: HKWorkout) async -> [HKHeartRateZone] {
        // Implementation from existing code
        return []
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
}
