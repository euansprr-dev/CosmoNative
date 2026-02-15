// CosmoOS/UI/Sanctuary/Dimensions/Behavioral/BehavioralDataProvider.swift
// Data provider that queries GRDB to build real BehavioralDimensionData
// Sanctuary Phase: Behavioral Dimension Integration

import Foundation
import SwiftUI

@MainActor
class BehavioralDataProvider: ObservableObject {
    @Published var data: BehavioralDimensionData = .preview
    @Published var isLoading = false

    private let atomRepository: AtomRepository

    init(atomRepository: AtomRepository? = nil) {
        self.atomRepository = atomRepository ?? AtomRepository.shared
    }

    // MARK: - Main Refresh

    func refreshData() async {
        isLoading = true
        defer { isLoading = false }

        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)

        // Fetch all relevant atoms in parallel
        let deepWorkAtoms = (try? await atomRepository.fetchAll(type: .deepWorkBlock)) ?? []
        let taskAtoms = (try? await atomRepository.fetchAll(type: .task)) ?? []
        let scheduleBlocks = (try? await atomRepository.fetchAll(type: .scheduleBlock)) ?? []
        let workoutAtoms = (try? await atomRepository.fetchAll(type: .workoutSession)) ?? []
        let sleepAtoms = (try? await atomRepository.fetchAll(type: .sleepRecord)) ?? []
        let xpAtoms = (try? await atomRepository.fetchAll(type: .xpEvent)) ?? []
        let dimensionSnapshots = (try? await atomRepository.fetchAll(type: .dimensionSnapshot)) ?? []

        // Filter to today
        let todayDeepWork = deepWorkAtoms.filter { isOnDate($0.createdAt, date: todayStart) }
        let todayTasks = taskAtoms.filter { isOnDate($0.createdAt, date: todayStart) }
        let todayScheduleBlocks = scheduleBlocks.filter { isOnDate($0.createdAt, date: todayStart) }
        let todayWorkouts = workoutAtoms.filter { isOnDate($0.createdAt, date: todayStart) }
        let todaySleep = sleepAtoms.filter { isOnDate($0.createdAt, date: todayStart) }

        let completedTasks = todayTasks.filter {
            guard let meta = $0.metadataValue(as: TaskMetadata.self) else { return false }
            return meta.isCompleted == true
        }

        // Compute sub-scores
        let morningScoreValue = computeMorningScore(deepWorkAtoms: todayDeepWork, now: now)
        let deepWorkScoreValue = computeDeepWorkScore(sessions: todayDeepWork, blocks: todayScheduleBlocks)
        let sleepScoreValue = computeSleepScore(sleepAtoms: todaySleep)
        let taskScoreValue = computeTaskScore(completed: completedTasks.count, total: todayTasks.count)
        let screenScoreValue = 65.0 // Placeholder — no Screen Time API available
        let movementScoreValue = computeMovementScore(workouts: todayWorkouts)

        // Compute discipline index (weighted average, redistributing excluded weights)
        let weightedScores: [(score: Double, weight: Double)] = [
            (morningScoreValue, 0.15),
            (deepWorkScoreValue, 0.25),
            (sleepScoreValue, 0.15),
            (taskScoreValue, 0.20),
            (screenScoreValue, 0.10),
            (movementScoreValue, 0.15)
        ]
        let totalWeight = weightedScores.reduce(0.0) { $0 + $1.weight }
        let disciplineIndex = totalWeight > 0
            ? weightedScores.reduce(0.0) { $0 + $1.score * $1.weight } / totalWeight * 100
            : 50.0

        // Compute 7-day trend for discipline change
        let disciplineChange = await computeDisciplineChange(snapshots: dimensionSnapshots, currentIndex: disciplineIndex)

        // Build component scores
        let morningScore = buildComponentScore(name: "MORNING", score: morningScoreValue * 100, snapshots: dimensionSnapshots, key: "morning")
        let deepWorkScore = buildComponentScore(name: "DEEP WORK", score: deepWorkScoreValue * 100, snapshots: dimensionSnapshots, key: "deepWork")
        let sleepScore = buildComponentScore(name: "SLEEP", score: sleepScoreValue * 100, snapshots: dimensionSnapshots, key: "sleep")
        let movementScore = buildComponentScore(name: "MOVEMENT", score: movementScoreValue * 100, snapshots: dimensionSnapshots, key: "movement")
        let screenScore = buildComponentScore(name: "SCREEN", score: screenScoreValue, snapshots: dimensionSnapshots, key: "screen")
        let taskScore = buildComponentScore(name: "TASKS", score: taskScoreValue * 100, snapshots: dimensionSnapshots, key: "tasks")

        // Build routine trackers
        let morningRoutine = buildMorningRoutineTracker(deepWorkAtoms: deepWorkAtoms, now: now)
        let sleepSchedule = buildSleepScheduleTracker(sleepAtoms: sleepAtoms, now: now)
        let wakeSchedule = buildWakeScheduleTracker(deepWorkAtoms: deepWorkAtoms, now: now)

        // Build streaks
        let activeStreaks = computeActiveStreaks(
            deepWorkAtoms: deepWorkAtoms,
            taskAtoms: taskAtoms,
            sleepAtoms: sleepAtoms,
            workoutAtoms: workoutAtoms,
            now: now
        )
        let endangeredStreaks = activeStreaks.filter { $0.isEndangered }
        let regularStreaks = activeStreaks.filter { !$0.isEndangered }

        // Build daily operations data
        let deepWorkMinutesToday = computeDeepWorkMinutes(sessions: todayDeepWork)
        let plannedMinutesToday = computePlannedMinutes(blocks: todayScheduleBlocks)
        let walksToday = todayWorkouts.filter { atom in
            let body = (atom.body ?? "").lowercased()
            return body.contains("walk") || body.contains("walking")
        }.count

        // Build timeline events
        let todayEvents = buildTimelineEvents(
            deepWork: todayDeepWork,
            tasks: completedTasks,
            workouts: todayWorkouts,
            sleep: todaySleep,
            now: now
        )

        // Build level up path from XP data
        let levelUpPath = buildLevelUpPath(xpAtoms: xpAtoms)

        // Build predictions
        let predictions = buildPredictions(activeStreaks: regularStreaks)

        // Assemble the data
        data = BehavioralDimensionData(
            disciplineIndex: min(100, max(0, disciplineIndex)),
            disciplineChange: disciplineChange,
            morningScore: morningScore,
            deepWorkScore: deepWorkScore,
            sleepScore: sleepScore,
            movementScore: movementScore,
            screenScore: screenScore,
            taskScore: taskScore,
            morningRoutine: morningRoutine,
            sleepSchedule: sleepSchedule,
            wakeSchedule: wakeSchedule,
            activeStreaks: regularStreaks,
            endangeredStreaks: endangeredStreaks,
            personalBests: [],
            dopamineDelay: 30 * 60, // Placeholder — no system hook for first screen unlock
            dopamineTarget: 30 * 60,
            walksCompleted: walksToday,
            walksGoal: 3,
            screenTimeAfter10pm: 0, // Placeholder — no Screen Time API
            screenLimit: 20 * 60,
            tasksCompleted: completedTasks.count,
            tasksTotal: max(todayTasks.count, 1),
            todayEvents: todayEvents,
            violations: [],
            levelUpPath: levelUpPath,
            predictions: predictions
        )
    }

    // MARK: - Sub-Score Computations

    /// Morning Routine (15%): How close first deep work session started to 7:00 AM target
    private func computeMorningScore(deepWorkAtoms: [Atom], now: Date) -> Double {
        let calendar = Calendar.current
        let targetHour = 7
        let targetMinute = 0

        guard let earliest = deepWorkAtoms.compactMap({ parseDate($0.createdAt) }).min() else {
            return 0.5 // No sessions today — neutral score
        }

        let hour = calendar.component(.hour, from: earliest)
        let minute = calendar.component(.minute, from: earliest)
        let actualMinutes = hour * 60 + minute
        let targetMinutes = targetHour * 60 + targetMinute

        let diffMinutes = abs(actualMinutes - targetMinutes)

        // Within 15 min = excellent (1.0), within 30 = good (0.8), within 60 = fair (0.6), beyond = 0.4
        if diffMinutes <= 15 { return 1.0 }
        if diffMinutes <= 30 { return 0.85 }
        if diffMinutes <= 60 { return 0.65 }
        if diffMinutes <= 120 { return 0.45 }
        return 0.3
    }

    /// Deep Work Execution (25%): Actual deep work minutes vs planned
    private func computeDeepWorkScore(sessions: [Atom], blocks: [Atom]) -> Double {
        let actualMinutes = computeDeepWorkMinutes(sessions: sessions)
        let plannedMinutes = computePlannedMinutes(blocks: blocks)

        guard plannedMinutes > 0 else {
            // No plan — score based on absolute minutes
            if actualMinutes >= 120 { return 0.9 }
            if actualMinutes >= 60 { return 0.7 }
            if actualMinutes >= 30 { return 0.5 }
            return 0.3
        }

        let ratio = Double(actualMinutes) / Double(plannedMinutes)
        return min(1.0, ratio)
    }

    /// Sleep Discipline (15%): Check sleep records for bedtime consistency
    private func computeSleepScore(sleepAtoms: [Atom]) -> Double {
        guard !sleepAtoms.isEmpty else {
            return 0.5 // No sleep data — neutral
        }
        // If sleep records exist, score based on count (basic heuristic)
        return 0.75
    }

    /// Task Completion (20%): completed / total
    private func computeTaskScore(completed: Int, total: Int) -> Double {
        guard total > 0 else { return 0.5 }
        return Double(completed) / Double(total)
    }

    /// Movement (15%): Check for workout sessions
    private func computeMovementScore(workouts: [Atom]) -> Double {
        if workouts.count >= 2 { return 0.9 }
        if workouts.count == 1 { return 0.75 }
        return 0.5
    }

    // MARK: - Deep Work Minutes

    private func computeDeepWorkMinutes(sessions: [Atom]) -> Int {
        sessions.reduce(0) { total, atom in
            if let meta = atom.metadataValue(as: DeepWorkSessionMetadata.self) {
                return total + (meta.actualMinutes ?? meta.plannedMinutes)
            }
            return total
        }
    }

    private func computePlannedMinutes(blocks: [Atom]) -> Int {
        blocks.reduce(0) { total, atom in
            if let meta = atom.metadataValue(as: ScheduleBlockMetadata.self) {
                return total + (meta.durationMinutes ?? 0)
            }
            return total
        }
    }

    // MARK: - Discipline Change

    private func computeDisciplineChange(snapshots: [Atom], currentIndex: Double) async -> Double {
        // Look for last week's behavioral snapshot
        let calendar = Calendar.current
        let lastWeek = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let lastWeekStart = calendar.startOfDay(for: lastWeek)

        let lastWeekSnapshot = snapshots.first { atom in
            guard let date = parseDate(atom.createdAt) else { return false }
            let snapshotDay = calendar.startOfDay(for: date)
            return snapshotDay == lastWeekStart
        }

        if let snapshot = lastWeekSnapshot,
           let bodyStr = snapshot.body,
           let body = Double(bodyStr) {
            return currentIndex - body
        }

        return 0.0
    }

    // MARK: - Component Score Builder

    private func buildComponentScore(name: String, score: Double, snapshots: [Atom], key: String) -> ComponentScore {
        let clampedScore = min(100, max(0, score))

        let status: ComponentStatus
        if clampedScore >= 80 { status = .excellent }
        else if clampedScore >= 60 { status = .good }
        else if clampedScore >= 40 { status = .needsWork }
        else { status = .atRisk }

        return ComponentScore(
            name: name,
            currentScore: clampedScore,
            trend: .stable,
            changePercent: 0,
            status: status
        )
    }

    // MARK: - Routine Trackers

    private func buildMorningRoutineTracker(deepWorkAtoms: [Atom], now: Date) -> RoutineTracker {
        let calendar = Calendar.current
        let targetTime = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: now) ?? now

        let weekData = buildWeekRoutineData(atoms: deepWorkAtoms, now: now, useEarliestTime: true)
        let consistency = Double(weekData.filter { $0.status == .success }.count) / max(1, Double(weekData.count)) * 100

        let avgTime = weekData.compactMap { $0.actualTime }.reduce(into: 0.0) { sum, date in
            sum += Double(calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date))
        }
        let avgCount = Double(weekData.compactMap { $0.actualTime }.count)
        let avgMinutes = avgCount > 0 ? avgTime / avgCount : 7 * 60
        let avgDate = calendar.date(bySettingHour: Int(avgMinutes) / 60, minute: Int(avgMinutes) % 60, second: 0, of: now) ?? now

        return RoutineTracker(
            name: "MORNING ROUTINE",
            targetTime: targetTime,
            toleranceMinutes: 30,
            weekData: weekData,
            consistency: consistency,
            averageTime: avgDate,
            trend: consistency >= 70 ? .improving : (consistency >= 40 ? .stable : .declining)
        )
    }

    private func buildSleepScheduleTracker(sleepAtoms: [Atom], now: Date) -> RoutineTracker {
        let calendar = Calendar.current
        let targetTime = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: now) ?? now

        // Generate placeholder week data since sleep tracking may be sparse
        let weekData = (0..<7).map { dayOffset -> DayRoutineData in
            let dayOfWeek = (calendar.component(.weekday, from: now) - 1 + dayOffset) % 7
            return DayRoutineData(
                dayOfWeek: dayOfWeek,
                actualTime: nil,
                status: dayOffset == 6 ? .pending : .partial
            )
        }

        return RoutineTracker(
            name: "SLEEP SCHEDULE",
            targetTime: targetTime,
            toleranceMinutes: 30,
            weekData: weekData,
            consistency: 50,
            averageTime: calendar.date(bySettingHour: 23, minute: 15, second: 0, of: now) ?? now,
            trend: .stable
        )
    }

    private func buildWakeScheduleTracker(deepWorkAtoms: [Atom], now: Date) -> RoutineTracker {
        let calendar = Calendar.current
        let targetTime = calendar.date(bySettingHour: 6, minute: 30, second: 0, of: now) ?? now

        let weekData = buildWeekRoutineData(atoms: deepWorkAtoms, now: now, useEarliestTime: true)
        let consistency = Double(weekData.filter { $0.status == .success }.count) / max(1, Double(weekData.count)) * 100

        return RoutineTracker(
            name: "WAKE SCHEDULE",
            targetTime: targetTime,
            toleranceMinutes: 30,
            weekData: weekData,
            consistency: consistency,
            averageTime: calendar.date(bySettingHour: 6, minute: 35, second: 0, of: now) ?? now,
            trend: consistency >= 70 ? .improving : .stable
        )
    }

    private func buildWeekRoutineData(atoms: [Atom], now: Date, useEarliestTime: Bool) -> [DayRoutineData] {
        let calendar = Calendar.current

        return (0..<7).map { dayOffset -> DayRoutineData in
            let dayDate = calendar.date(byAdding: .day, value: -(6 - dayOffset), to: now) ?? now
            let dayStart = calendar.startOfDay(for: dayDate)
            let dayOfWeek = (calendar.component(.weekday, from: dayDate) - 1) % 7

            let dayAtoms = atoms.filter { isOnDate($0.createdAt, date: dayStart) }

            if dayOffset == 6 && calendar.isDateInToday(dayDate) && dayAtoms.isEmpty {
                return DayRoutineData(dayOfWeek: dayOfWeek, actualTime: nil, status: .pending)
            }

            guard let time = dayAtoms.compactMap({ parseDate($0.createdAt) }).min() else {
                return DayRoutineData(dayOfWeek: dayOfWeek, actualTime: nil, status: dayAtoms.isEmpty ? .failure : .partial)
            }

            let hour = calendar.component(.hour, from: time)
            let status: DayStatus = hour <= 8 ? .success : (hour <= 10 ? .partial : .failure)

            return DayRoutineData(dayOfWeek: dayOfWeek, actualTime: time, status: status)
        }
    }

    // MARK: - Streaks

    private func computeActiveStreaks(
        deepWorkAtoms: [Atom],
        taskAtoms: [Atom],
        sleepAtoms: [Atom],
        workoutAtoms: [Atom],
        now: Date
    ) -> [Streak] {
        var streaks: [Streak] = []

        // Deep Work streak — consecutive days with at least one deep work session
        let dwStreak = computeConsecutiveDayStreak(atoms: deepWorkAtoms, from: now)
        streaks.append(Streak(
            name: "DEEP WORK",
            category: .focus,
            currentDays: dwStreak,
            personalBest: max(dwStreak, 7),
            daysToNextMilestone: nextMilestoneDays(current: dwStreak),
            isEndangered: dwStreak > 0 && dwStreak <= 2,
            lastCompletedDate: now,
            xpPerDay: 15,
            milestoneXP: 150
        ))

        // Task Zero streak — consecutive days with all tasks completed
        let taskStreak = computeTaskZeroStreak(taskAtoms: taskAtoms, from: now)
        streaks.append(Streak(
            name: "TASK ZERO",
            category: .tasks,
            currentDays: taskStreak,
            personalBest: max(taskStreak, 7),
            daysToNextMilestone: nextMilestoneDays(current: taskStreak),
            lastCompletedDate: now,
            xpPerDay: 10,
            milestoneXP: 200
        ))

        // Exercise streak
        let exerciseStreak = computeConsecutiveDayStreak(atoms: workoutAtoms, from: now)
        if exerciseStreak > 0 {
            streaks.append(Streak(
                name: "EXERCISE",
                category: .exercise,
                currentDays: exerciseStreak,
                personalBest: max(exerciseStreak, 5),
                daysToNextMilestone: nextMilestoneDays(current: exerciseStreak),
                isEndangered: exerciseStreak <= 2,
                lastCompletedDate: now,
                xpPerDay: 12,
                milestoneXP: 100
            ))
        }

        // Sleep streak
        let sleepStreak = computeConsecutiveDayStreak(atoms: sleepAtoms, from: now)
        if sleepStreak > 0 {
            streaks.append(Streak(
                name: "SLEEP BEFORE 11PM",
                category: .sleep,
                currentDays: sleepStreak,
                personalBest: max(sleepStreak, 7),
                daysToNextMilestone: nextMilestoneDays(current: sleepStreak),
                lastCompletedDate: now,
                xpPerDay: 12,
                milestoneXP: 100
            ))
        }

        return streaks
    }

    private func computeConsecutiveDayStreak(atoms: [Atom], from date: Date) -> Int {
        let calendar = Calendar.current
        // Pre-compute a Set of day-start dates for O(1) lookups instead of O(n) per day
        let atomDays: Set<Date> = Set(atoms.compactMap { atom in
            guard let parsed = parseDate(atom.createdAt) else { return nil }
            return calendar.startOfDay(for: parsed)
        })

        var streak = 0
        var checkDate = calendar.startOfDay(for: date)

        for _ in 0..<365 {
            if atomDays.contains(checkDate) {
                streak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
            } else {
                break
            }
        }

        return streak
    }

    private func computeTaskZeroStreak(taskAtoms: [Atom], from date: Date) -> Int {
        let calendar = Calendar.current
        // Pre-group tasks by day for O(1) lookups
        var tasksByDay: [Date: [Atom]] = [:]
        for atom in taskAtoms {
            guard let parsed = parseDate(atom.createdAt) else { continue }
            let day = calendar.startOfDay(for: parsed)
            tasksByDay[day, default: []].append(atom)
        }

        var streak = 0
        var checkDate = calendar.startOfDay(for: date)

        for _ in 0..<365 {
            guard let dayTasks = tasksByDay[checkDate], !dayTasks.isEmpty else { break }

            let allCompleted = dayTasks.allSatisfy { atom in
                guard let meta = atom.metadataValue(as: TaskMetadata.self) else { return false }
                return meta.isCompleted == true
            }

            if allCompleted {
                streak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
            } else {
                break
            }
        }

        return streak
    }

    private func nextMilestoneDays(current: Int) -> Int {
        let milestones = [7, 14, 21, 30, 60, 90, 180, 365]
        for m in milestones {
            if current < m { return m - current }
        }
        return 365 - (current % 365)
    }

    // MARK: - Timeline Events

    private func buildTimelineEvents(
        deepWork: [Atom],
        tasks: [Atom],
        workouts: [Atom],
        sleep: [Atom],
        now: Date
    ) -> [BehavioralEvent] {
        var events: [BehavioralEvent] = []

        for atom in deepWork {
            if let date = parseDate(atom.createdAt) {
                let meta = atom.metadataValue(as: DeepWorkSessionMetadata.self)
                events.append(BehavioralEvent(
                    timestamp: date,
                    eventType: .deepWorkStart,
                    status: .success,
                    details: "Deep work: \(meta?.plannedMinutes ?? 0) min planned"
                ))
            }
        }

        for atom in tasks {
            if let date = parseDate(atom.createdAt) {
                events.append(BehavioralEvent(
                    timestamp: date,
                    eventType: .task,
                    status: .success,
                    details: "Task completed"
                ))
            }
        }

        for atom in workouts {
            if let date = parseDate(atom.createdAt) {
                let isWalk = (atom.body ?? "").lowercased().contains("walk")
                events.append(BehavioralEvent(
                    timestamp: date,
                    eventType: isWalk ? .walk : .exercise,
                    status: .success,
                    details: isWalk ? "Walk" : "Workout"
                ))
            }
        }

        return events.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Level Up Path

    private func buildLevelUpPath(xpAtoms: [Atom]) -> LevelUpPath {
        // Sum behavioral XP from events
        let totalXP = xpAtoms.reduce(0) { total, atom in
            total + (Int(atom.body ?? "") ?? 0)
        }

        let currentLevel = totalXP / 500
        let xpInLevel = totalXP % 500

        return LevelUpPath(
            currentLevel: max(1, currentLevel),
            nextLevel: max(2, currentLevel + 1),
            xpNeeded: 500,
            xpProgress: xpInLevel,
            fastestActions: [
                LevelUpAction(
                    action: "Maintain deep work streak for 7 days",
                    xpReward: 150,
                    daysRequired: 7
                ),
                LevelUpAction(
                    action: "Complete all daily tasks for 5 consecutive days",
                    xpReward: 200,
                    daysRequired: 5
                )
            ],
            estimatedDays: max(1, (500 - xpInLevel) / max(1, 30))
        )
    }

    // MARK: - Predictions

    private func buildPredictions(activeStreaks: [Streak]) -> [BehavioralPrediction] {
        guard let longestStreak = activeStreaks.max(by: { $0.currentDays < $1.currentDays }) else {
            return []
        }

        return [
            BehavioralPrediction(
                condition: "You maintain \(longestStreak.name) for \(longestStreak.daysToNextMilestone) more days",
                prediction: "\(longestStreak.name) streak reaches \(longestStreak.currentDays + longestStreak.daysToNextMilestone) days, earning +\(longestStreak.milestoneXP) XP milestone bonus",
                basedOn: "Current streak: \(longestStreak.currentDays) days, personal best: \(longestStreak.personalBest) days",
                confidence: min(0.95, 0.5 + Double(longestStreak.currentDays) * 0.03),
                actions: ["View Streak Details", "Set Reminder"]
            )
        ]
    }

    // MARK: - Date Helpers

    private let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private let iso8601FormatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func parseDate(_ string: String) -> Date? {
        iso8601Formatter.date(from: string) ?? iso8601FormatterNoFrac.date(from: string)
    }

    private func isOnDate(_ dateString: String, date: Date) -> Bool {
        guard let parsed = parseDate(dateString) else { return false }
        return Calendar.current.startOfDay(for: parsed) == date
    }
}
