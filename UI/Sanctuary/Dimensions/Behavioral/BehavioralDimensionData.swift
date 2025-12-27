// CosmoOS/UI/Sanctuary/Dimensions/Behavioral/BehavioralDimensionData.swift
// Data Models - Discipline and behavioral tracking structures
// Phase 6: Following SANCTUARY_UI_SPEC_V2.md section 3.4

import SwiftUI

// MARK: - Score Trend

public enum ScoreTrend: String, Codable, Sendable {
    case up
    case down
    case stable

    public var iconName: String {
        switch self {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .stable: return "arrow.right"
        }
    }

    public var color: Color {
        switch self {
        case .up: return SanctuaryColors.Semantic.success
        case .down: return SanctuaryColors.Semantic.error
        case .stable: return SanctuaryColors.Text.tertiary
        }
    }
}

// MARK: - Component Status

public enum ComponentStatus: String, Codable, Sendable, CaseIterable {
    case excellent
    case good
    case needsWork
    case atRisk

    public var displayName: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .needsWork: return "Needs Work"
        case .atRisk: return "At Risk"
        }
    }

    public var color: String {
        switch self {
        case .excellent: return "#22C55E"
        case .good: return "#3B82F6"
        case .needsWork: return "#F59E0B"
        case .atRisk: return "#EF4444"
        }
    }

    public var iconFill: Double {
        switch self {
        case .excellent: return 1.0
        case .good: return 0.75
        case .needsWork: return 0.5
        case .atRisk: return 0.25
        }
    }
}

// MARK: - Streak Category

public enum StreakCategory: String, Codable, Sendable, CaseIterable {
    case sleep
    case focus
    case exercise
    case morning
    case tasks
    case screen
    case custom

    public var displayName: String {
        switch self {
        case .sleep: return "Sleep"
        case .focus: return "Deep Work"
        case .exercise: return "Exercise"
        case .morning: return "Morning Routine"
        case .tasks: return "Task Zero"
        case .screen: return "Screen Limit"
        case .custom: return "Custom"
        }
    }

    public var iconName: String {
        switch self {
        case .sleep: return "moon.fill"
        case .focus: return "brain.head.profile"
        case .exercise: return "figure.run"
        case .morning: return "sunrise.fill"
        case .tasks: return "checkmark.circle.fill"
        case .screen: return "iphone.slash"
        case .custom: return "star.fill"
        }
    }

    public var color: String {
        switch self {
        case .sleep: return "#8B5CF6"
        case .focus: return "#3B82F6"
        case .exercise: return "#22C55E"
        case .morning: return "#F59E0B"
        case .tasks: return "#EC4899"
        case .screen: return "#06B6D4"
        case .custom: return "#6B7280"
        }
    }
}

// MARK: - Day Status

public enum DayStatus: String, Codable, Sendable {
    case success
    case partial
    case failure
    case pending
    case rest

    public var iconName: String {
        switch self {
        case .success: return "circle.fill"
        case .partial: return "circle.lefthalf.filled"
        case .failure: return "circle"
        case .pending: return "circle.dotted"
        case .rest: return "minus"
        }
    }

    public var color: Color {
        switch self {
        case .success: return SanctuaryColors.Semantic.success
        case .partial: return SanctuaryColors.Semantic.warning
        case .failure: return SanctuaryColors.Semantic.error
        case .pending: return SanctuaryColors.Text.tertiary
        case .rest: return SanctuaryColors.Text.tertiary.opacity(0.5)
        }
    }
}

// MARK: - Event Type

public enum BehavioralEventType: String, Codable, Sendable {
    case wake
    case sleep
    case deepWorkStart
    case deepWorkEnd
    case walk
    case task
    case screen
    case exercise
    case meal
    case custom

    public var displayName: String {
        switch self {
        case .wake: return "Wake"
        case .sleep: return "Sleep"
        case .deepWorkStart: return "DW Start"
        case .deepWorkEnd: return "DW End"
        case .walk: return "Walk"
        case .task: return "Task"
        case .screen: return "Screen"
        case .exercise: return "Exercise"
        case .meal: return "Meal"
        case .custom: return "Event"
        }
    }

    public var iconName: String {
        switch self {
        case .wake: return "sun.max.fill"
        case .sleep: return "moon.fill"
        case .deepWorkStart, .deepWorkEnd: return "brain.head.profile"
        case .walk: return "figure.walk"
        case .task: return "checkmark.circle"
        case .screen: return "iphone"
        case .exercise: return "figure.run"
        case .meal: return "fork.knife"
        case .custom: return "star"
        }
    }
}

// MARK: - Event Status

public enum EventStatus: String, Codable, Sendable {
    case success
    case partial
    case violation

    public var color: Color {
        switch self {
        case .success: return SanctuaryColors.Semantic.success
        case .partial: return SanctuaryColors.Semantic.warning
        case .violation: return SanctuaryColors.Semantic.error
        }
    }
}

// MARK: - Routine Trend

public enum RoutineTrend: String, Codable, Sendable {
    case improving
    case stable
    case declining

    public var displayName: String {
        switch self {
        case .improving: return "Improving"
        case .stable: return "Stable"
        case .declining: return "Declining"
        }
    }
}

// MARK: - Component Score

public struct ComponentScore: Identifiable, Codable, Sendable {
    public let id: UUID
    public let name: String
    public let currentScore: Double
    public let trend: ScoreTrend
    public let changePercent: Double
    public let status: ComponentStatus

    public init(
        id: UUID = UUID(),
        name: String,
        currentScore: Double,
        trend: ScoreTrend,
        changePercent: Double,
        status: ComponentStatus
    ) {
        self.id = id
        self.name = name
        self.currentScore = min(100, max(0, currentScore))
        self.trend = trend
        self.changePercent = changePercent
        self.status = status
    }

    public var statusDots: Int {
        if currentScore >= 80 { return 2 }
        if currentScore >= 60 { return 1 }
        return 0
    }
}

// MARK: - Day Routine Data

public struct DayRoutineData: Identifiable, Codable, Sendable {
    public let id: UUID
    public let dayOfWeek: Int // 0 = Sunday, 6 = Saturday
    public let actualTime: Date?
    public let status: DayStatus

    public init(
        id: UUID = UUID(),
        dayOfWeek: Int,
        actualTime: Date?,
        status: DayStatus
    ) {
        self.id = id
        self.dayOfWeek = dayOfWeek
        self.actualTime = actualTime
        self.status = status
    }

    public var formattedTime: String {
        guard let time = actualTime else { return "--" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter.string(from: time)
    }

    public var dayLabel: String {
        let days = ["S", "M", "T", "W", "T", "F", "S"]
        return days[dayOfWeek % 7]
    }
}

// MARK: - Routine Tracker

public struct RoutineTracker: Identifiable, Codable, Sendable {
    public let id: UUID
    public let name: String
    public let targetTime: Date
    public let toleranceMinutes: Int
    public let weekData: [DayRoutineData]
    public let consistency: Double
    public let averageTime: Date
    public let trend: RoutineTrend

    public init(
        id: UUID = UUID(),
        name: String,
        targetTime: Date,
        toleranceMinutes: Int,
        weekData: [DayRoutineData],
        consistency: Double,
        averageTime: Date,
        trend: RoutineTrend
    ) {
        self.id = id
        self.name = name
        self.targetTime = targetTime
        self.toleranceMinutes = toleranceMinutes
        self.weekData = weekData
        self.consistency = min(100, max(0, consistency))
        self.averageTime = averageTime
        self.trend = trend
    }

    public var formattedTarget: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        return formatter.string(from: targetTime).lowercased()
    }

    public var formattedAverage: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        return formatter.string(from: averageTime).lowercased()
    }

    public var toleranceString: String {
        "±\(toleranceMinutes)min"
    }
}

// MARK: - Streak

public struct Streak: Identifiable, Codable, Sendable {
    public let id: UUID
    public let name: String
    public let category: StreakCategory
    public let currentDays: Int
    public let personalBest: Int
    public let daysToNextMilestone: Int
    public let isEndangered: Bool
    public let lastCompletedDate: Date
    public let xpPerDay: Int
    public let milestoneXP: Int

    public init(
        id: UUID = UUID(),
        name: String,
        category: StreakCategory,
        currentDays: Int,
        personalBest: Int,
        daysToNextMilestone: Int,
        isEndangered: Bool = false,
        lastCompletedDate: Date,
        xpPerDay: Int = 10,
        milestoneXP: Int = 100
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.currentDays = currentDays
        self.personalBest = personalBest
        self.daysToNextMilestone = daysToNextMilestone
        self.isEndangered = isEndangered
        self.lastCompletedDate = lastCompletedDate
        self.xpPerDay = xpPerDay
        self.milestoneXP = milestoneXP
    }

    public var isPersonalBest: Bool {
        currentDays >= personalBest && currentDays > 0
    }

    public var progress: Double {
        let nextMilestone = currentDays + daysToNextMilestone
        guard nextMilestone > 0 else { return 0 }
        return Double(currentDays) / Double(nextMilestone)
    }

    public var statusText: String {
        if isPersonalBest {
            return "PERSONAL BEST!"
        } else if isEndangered {
            return "AT RISK"
        } else {
            return "Best: \(personalBest) days • To beat: \(personalBest - currentDays)"
        }
    }
}

// MARK: - Streak Record

public struct StreakRecord: Identifiable, Codable, Sendable {
    public let id: UUID
    public let category: StreakCategory
    public let days: Int
    public let achievedDate: Date

    public init(
        id: UUID = UUID(),
        category: StreakCategory,
        days: Int,
        achievedDate: Date
    ) {
        self.id = id
        self.category = category
        self.days = days
        self.achievedDate = achievedDate
    }
}

// MARK: - Behavioral Event

public struct BehavioralEvent: Identifiable, Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let eventType: BehavioralEventType
    public let status: EventStatus
    public let details: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        eventType: BehavioralEventType,
        status: EventStatus,
        details: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.eventType = eventType
        self.status = status
        self.details = details
    }

    public var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter.string(from: timestamp)
    }

    public var hour: Int {
        Calendar.current.component(.hour, from: timestamp)
    }
}

// MARK: - Behavior Violation

public struct BehaviorViolation: Identifiable, Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let category: StreakCategory
    public let description: String
    public let impact: String

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        category: StreakCategory,
        description: String,
        impact: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.description = description
        self.impact = impact
    }
}

// MARK: - Level Up Action

public struct LevelUpAction: Identifiable, Codable, Sendable {
    public let id: UUID
    public let action: String
    public let xpReward: Int
    public let daysRequired: Int

    public init(
        id: UUID = UUID(),
        action: String,
        xpReward: Int,
        daysRequired: Int
    ) {
        self.id = id
        self.action = action
        self.xpReward = xpReward
        self.daysRequired = daysRequired
    }
}

// MARK: - Level Up Path

public struct LevelUpPath: Codable, Sendable {
    public let currentLevel: Int
    public let nextLevel: Int
    public let xpNeeded: Int
    public let xpProgress: Int
    public let fastestActions: [LevelUpAction]
    public let estimatedDays: Int

    public init(
        currentLevel: Int,
        nextLevel: Int,
        xpNeeded: Int,
        xpProgress: Int,
        fastestActions: [LevelUpAction],
        estimatedDays: Int
    ) {
        self.currentLevel = currentLevel
        self.nextLevel = nextLevel
        self.xpNeeded = xpNeeded
        self.xpProgress = xpProgress
        self.fastestActions = fastestActions
        self.estimatedDays = estimatedDays
    }

    public var progress: Double {
        guard xpNeeded > 0 else { return 0 }
        return Double(xpProgress) / Double(xpNeeded)
    }

    public var xpRemaining: Int {
        max(0, xpNeeded - xpProgress)
    }
}

// MARK: - Behavioral Prediction

public struct BehavioralPrediction: Identifiable, Codable, Sendable {
    public let id: UUID
    public let condition: String
    public let prediction: String
    public let basedOn: String
    public let confidence: Double
    public let actions: [String]

    public init(
        id: UUID = UUID(),
        condition: String,
        prediction: String,
        basedOn: String,
        confidence: Double,
        actions: [String]
    ) {
        self.id = id
        self.condition = condition
        self.prediction = prediction
        self.basedOn = basedOn
        self.confidence = confidence
        self.actions = actions
    }
}

// MARK: - Behavioral Dimension Data

public struct BehavioralDimensionData: Codable, Sendable {
    // Discipline Index
    public let disciplineIndex: Double
    public let disciplineChange: Double

    // Component Scores
    public let morningScore: ComponentScore
    public let deepWorkScore: ComponentScore
    public let sleepScore: ComponentScore
    public let movementScore: ComponentScore
    public let screenScore: ComponentScore
    public let taskScore: ComponentScore

    // Routine Tracking
    public let morningRoutine: RoutineTracker
    public let sleepSchedule: RoutineTracker
    public let wakeSchedule: RoutineTracker

    // Streaks
    public let activeStreaks: [Streak]
    public let endangeredStreaks: [Streak]
    public let personalBests: [StreakRecord]

    // Daily Operations
    public let dopamineDelay: TimeInterval
    public let dopamineTarget: TimeInterval
    public let walksCompleted: Int
    public let walksGoal: Int
    public let screenTimeAfter10pm: TimeInterval
    public let screenLimit: TimeInterval
    public let tasksCompleted: Int
    public let tasksTotal: Int

    // Timeline
    public let todayEvents: [BehavioralEvent]
    public let violations: [BehaviorViolation]

    // Progression
    public let levelUpPath: LevelUpPath
    public let predictions: [BehavioralPrediction]

    public init(
        disciplineIndex: Double,
        disciplineChange: Double,
        morningScore: ComponentScore,
        deepWorkScore: ComponentScore,
        sleepScore: ComponentScore,
        movementScore: ComponentScore,
        screenScore: ComponentScore,
        taskScore: ComponentScore,
        morningRoutine: RoutineTracker,
        sleepSchedule: RoutineTracker,
        wakeSchedule: RoutineTracker,
        activeStreaks: [Streak],
        endangeredStreaks: [Streak],
        personalBests: [StreakRecord],
        dopamineDelay: TimeInterval,
        dopamineTarget: TimeInterval,
        walksCompleted: Int,
        walksGoal: Int,
        screenTimeAfter10pm: TimeInterval,
        screenLimit: TimeInterval,
        tasksCompleted: Int,
        tasksTotal: Int,
        todayEvents: [BehavioralEvent],
        violations: [BehaviorViolation],
        levelUpPath: LevelUpPath,
        predictions: [BehavioralPrediction]
    ) {
        self.disciplineIndex = disciplineIndex
        self.disciplineChange = disciplineChange
        self.morningScore = morningScore
        self.deepWorkScore = deepWorkScore
        self.sleepScore = sleepScore
        self.movementScore = movementScore
        self.screenScore = screenScore
        self.taskScore = taskScore
        self.morningRoutine = morningRoutine
        self.sleepSchedule = sleepSchedule
        self.wakeSchedule = wakeSchedule
        self.activeStreaks = activeStreaks
        self.endangeredStreaks = endangeredStreaks
        self.personalBests = personalBests
        self.dopamineDelay = dopamineDelay
        self.dopamineTarget = dopamineTarget
        self.walksCompleted = walksCompleted
        self.walksGoal = walksGoal
        self.screenTimeAfter10pm = screenTimeAfter10pm
        self.screenLimit = screenLimit
        self.tasksCompleted = tasksCompleted
        self.tasksTotal = tasksTotal
        self.todayEvents = todayEvents
        self.violations = violations
        self.levelUpPath = levelUpPath
        self.predictions = predictions
    }

    // MARK: - Computed Properties

    public var allComponentScores: [ComponentScore] {
        [morningScore, deepWorkScore, sleepScore, movementScore, screenScore, taskScore]
    }

    public var dopamineDelayMinutes: Int {
        Int(dopamineDelay / 60)
    }

    public var dopamineTargetMinutes: Int {
        Int(dopamineTarget / 60)
    }

    public var screenTimeMinutes: Int {
        Int(screenTimeAfter10pm / 60)
    }

    public var screenLimitMinutes: Int {
        Int(screenLimit / 60)
    }

    public var isScreenOverLimit: Bool {
        screenTimeAfter10pm > screenLimit
    }

    public var taskProgress: Double {
        guard tasksTotal > 0 else { return 0 }
        return Double(tasksCompleted) / Double(tasksTotal)
    }
}

// MARK: - Preview Data

#if DEBUG
extension BehavioralDimensionData {
    public static var preview: BehavioralDimensionData {
        let calendar = Calendar.current
        let now = Date()

        // Generate week data for routines
        func generateWeekData(targetHour: Int, targetMinute: Int) -> [DayRoutineData] {
            let variations = [(-8, .success), (1, .success), (75, .failure), (-2, .success), (-15, .success), (11, .success), (0, .pending)] as [(Int, DayStatus)]

            return (0..<7).map { dayOffset in
                let (minuteOffset, status) = variations[dayOffset]
                var components = calendar.dateComponents([.year, .month, .day], from: now)
                components.day! -= (6 - dayOffset)
                components.hour = targetHour
                components.minute = targetMinute + minuteOffset

                return DayRoutineData(
                    dayOfWeek: (calendar.component(.weekday, from: now) - 1 + dayOffset) % 7,
                    actualTime: status != .pending ? calendar.date(from: components) : nil,
                    status: status
                )
            }
        }

        // Component scores
        let morningScore = ComponentScore(name: "MORNING", currentScore: 92, trend: .up, changePercent: 5, status: .excellent)
        let deepWorkScore = ComponentScore(name: "DEEP WORK", currentScore: 84, trend: .stable, changePercent: 0, status: .good)
        let sleepScore = ComponentScore(name: "SLEEP", currentScore: 73, trend: .down, changePercent: -4, status: .needsWork)
        let movementScore = ComponentScore(name: "MOVEMENT", currentScore: 81, trend: .up, changePercent: 3, status: .good)
        let screenScore = ComponentScore(name: "SCREEN", currentScore: 62, trend: .down, changePercent: -8, status: .atRisk)
        let taskScore = ComponentScore(name: "TASKS", currentScore: 88, trend: .up, changePercent: 2, status: .excellent)

        // Routine trackers
        let morningRoutine = RoutineTracker(
            name: "MORNING ROUTINE",
            targetTime: calendar.date(bySettingHour: 6, minute: 30, second: 0, of: now)!,
            toleranceMinutes: 15,
            weekData: generateWeekData(targetHour: 6, targetMinute: 30),
            consistency: 71,
            averageTime: calendar.date(bySettingHour: 6, minute: 34, second: 0, of: now)!,
            trend: .improving
        )

        let sleepSchedule = RoutineTracker(
            name: "SLEEP SCHEDULE",
            targetTime: calendar.date(bySettingHour: 23, minute: 0, second: 0, of: now)!,
            toleranceMinutes: 30,
            weekData: generateWeekData(targetHour: 22, targetMinute: 50),
            consistency: 67,
            averageTime: calendar.date(bySettingHour: 22, minute: 56, second: 0, of: now)!,
            trend: .stable
        )

        let wakeSchedule = RoutineTracker(
            name: "WAKE SCHEDULE",
            targetTime: calendar.date(bySettingHour: 6, minute: 30, second: 0, of: now)!,
            toleranceMinutes: 30,
            weekData: generateWeekData(targetHour: 6, targetMinute: 30),
            consistency: 71,
            averageTime: calendar.date(bySettingHour: 6, minute: 28, second: 0, of: now)!,
            trend: .improving
        )

        // Streaks
        let activeStreaks: [Streak] = [
            Streak(name: "DEEP WORK", category: .focus, currentDays: 12, personalBest: 18, daysToNextMilestone: 2, lastCompletedDate: now, xpPerDay: 15, milestoneXP: 150),
            Streak(name: "TASK ZERO", category: .tasks, currentDays: 21, personalBest: 21, daysToNextMilestone: 9, lastCompletedDate: now, xpPerDay: 10, milestoneXP: 200),
            Streak(name: "SLEEP BEFORE 11PM", category: .sleep, currentDays: 8, personalBest: 14, daysToNextMilestone: 2, lastCompletedDate: now, xpPerDay: 12, milestoneXP: 100),
            Streak(name: "MORNING ROUTINE", category: .morning, currentDays: 5, personalBest: 23, daysToNextMilestone: 2, lastCompletedDate: now, xpPerDay: 10, milestoneXP: 75)
        ]

        let endangeredStreaks: [Streak] = [
            Streak(name: "Screen Limit", category: .screen, currentDays: 3, personalBest: 12, daysToNextMilestone: 4, isEndangered: true, lastCompletedDate: now),
            Streak(name: "Exercise", category: .exercise, currentDays: 2, personalBest: 8, daysToNextMilestone: 5, isEndangered: true, lastCompletedDate: now)
        ]

        // Today's events
        let todayEvents: [BehavioralEvent] = [
            BehavioralEvent(timestamp: calendar.date(bySettingHour: 6, minute: 22, second: 0, of: now)!, eventType: .wake, status: .success, details: "Wake 6:22"),
            BehavioralEvent(timestamp: calendar.date(bySettingHour: 10, minute: 15, second: 0, of: now)!, eventType: .deepWorkStart, status: .success, details: "DW Start"),
            BehavioralEvent(timestamp: calendar.date(bySettingHour: 14, minute: 30, second: 0, of: now)!, eventType: .walk, status: .success, details: "Walk #1"),
            BehavioralEvent(timestamp: calendar.date(bySettingHour: 18, minute: 45, second: 0, of: now)!, eventType: .walk, status: .success, details: "Walk #2"),
            BehavioralEvent(timestamp: calendar.date(bySettingHour: 22, minute: 32, second: 0, of: now)!, eventType: .screen, status: .violation, details: "Screen Over")
        ]

        // Level up path
        let levelUpPath = LevelUpPath(
            currentLevel: 17,
            nextLevel: 18,
            xpNeeded: 500,
            xpProgress: 160,
            fastestActions: [
                LevelUpAction(action: "Complete Task Zero streak (7 more days)", xpReward: 350, daysRequired: 7)
            ],
            estimatedDays: 7
        )

        // Predictions
        let predictions: [BehavioralPrediction] = [
            BehavioralPrediction(
                condition: "You sleep before 11pm for 3 more consecutive nights",
                prediction: "Sleep streak reaches 11 days, unlocking \"Night Owl Reformed\" badge (+150 XP)",
                basedOn: "Current streak momentum, your historical pattern shows 89% success at this point",
                confidence: 0.82,
                actions: ["Set 10:30pm Reminder", "Streak Analytics", "Adjust Goals"]
            )
        ]

        return BehavioralDimensionData(
            disciplineIndex: 78.4,
            disciplineChange: 2.3,
            morningScore: morningScore,
            deepWorkScore: deepWorkScore,
            sleepScore: sleepScore,
            movementScore: movementScore,
            screenScore: screenScore,
            taskScore: taskScore,
            morningRoutine: morningRoutine,
            sleepSchedule: sleepSchedule,
            wakeSchedule: wakeSchedule,
            activeStreaks: activeStreaks,
            endangeredStreaks: endangeredStreaks,
            personalBests: [],
            dopamineDelay: 47 * 60,
            dopamineTarget: 30 * 60,
            walksCompleted: 2,
            walksGoal: 3,
            screenTimeAfter10pm: 32 * 60,
            screenLimit: 20 * 60,
            tasksCompleted: 6,
            tasksTotal: 8,
            todayEvents: todayEvents,
            violations: [
                BehaviorViolation(
                    timestamp: calendar.date(bySettingHour: 22, minute: 32, second: 0, of: now)!,
                    category: .screen,
                    description: "Screen time exceeded after 10pm",
                    impact: "2 violations this week"
                )
            ],
            levelUpPath: levelUpPath,
            predictions: predictions
        )
    }
}
#endif
