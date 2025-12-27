// CosmoOS/Data/Models/LevelSystem/CognitiveMetadata.swift
// Metadata structures for cognitive output tracking
// Supports deep work blocks, writing sessions, focus scores, and distraction events

import Foundation

// MARK: - Deep Work Block Metadata

/// Metadata for deepWorkBlock atoms
struct DeepWorkBlockMetadata: Codable, Sendable {
    /// When the deep work session started
    let startTime: Date

    /// When the deep work session ended
    let endTime: Date

    /// Duration in seconds
    let duration: TimeInterval

    /// Focus quality score (0-100) based on interruptions and flow
    let focusScore: Double

    /// Number of context switches during the block
    let contextSwitches: Int

    /// UUID of the project being worked on (if any)
    let projectUUID: String?

    /// UUIDs of tasks completed during this block
    let completedTaskUUIDs: [String]

    /// Words written during this block (if applicable)
    let wordsWritten: Int

    /// Tasks completed count
    let tasksCompleted: Int

    /// User self-rating (1-5, optional)
    let qualityRating: Int?

    /// What the user was working on (optional description)
    let workDescription: String?

    /// Apps used during the session (bundle IDs)
    let appsUsed: [String]

    /// Whether the block was completed without interruption
    let uninterrupted: Bool

    /// Planned duration (if set before starting)
    let plannedDuration: TimeInterval?

    /// XP earned from this block
    var estimatedXP: Int {
        let baseXP = Int(duration / 3600.0 * 25)  // 25 XP per hour
        let focusMultiplier = focusScore / 100.0
        return Int(Double(baseXP) * (1.0 + focusMultiplier))
    }

    init(
        startTime: Date,
        endTime: Date,
        duration: TimeInterval,
        focusScore: Double = 100,
        contextSwitches: Int = 0,
        projectUUID: String? = nil,
        completedTaskUUIDs: [String] = [],
        wordsWritten: Int = 0,
        tasksCompleted: Int = 0,
        qualityRating: Int? = nil,
        workDescription: String? = nil,
        appsUsed: [String] = [],
        uninterrupted: Bool = true,
        plannedDuration: TimeInterval? = nil
    ) {
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.focusScore = focusScore
        self.contextSwitches = contextSwitches
        self.projectUUID = projectUUID
        self.completedTaskUUIDs = completedTaskUUIDs
        self.wordsWritten = wordsWritten
        self.tasksCompleted = tasksCompleted
        self.qualityRating = qualityRating
        self.workDescription = workDescription
        self.appsUsed = appsUsed
        self.uninterrupted = uninterrupted
        self.plannedDuration = plannedDuration
    }
}

// MARK: - Writing Session Metadata

/// Type of writing session
enum WritingSessionType: String, Codable, Sendable {
    case drafting           // First draft creation
    case editing            // Revising existing content
    case research           // Research note-taking
    case journaling         // Personal journaling
    case ideation           // Brainstorming/idea capture
    case outlining          // Creating outlines
    case polishing          // Final polish pass
    case other

    var displayName: String {
        switch self {
        case .drafting: return "Drafting"
        case .editing: return "Editing"
        case .research: return "Research"
        case .journaling: return "Journaling"
        case .ideation: return "Ideation"
        case .outlining: return "Outlining"
        case .polishing: return "Polishing"
        case .other: return "Other"
        }
    }
}

/// Metadata for writingSession atoms
struct WritingSessionMetadata: Codable, Sendable {
    /// When the session started
    let startTime: Date

    /// When the session ended
    let endTime: Date

    /// Gross word count (total words typed)
    let wordCount: Int

    /// Net word count (accounting for deletions)
    let netWordCount: Int

    /// Total characters typed
    let charactersTyped: Int

    /// Average words per minute
    let averageWPM: Double

    /// Peak words per minute (highest 5-min window)
    let peakWPM: Double

    /// UUID of the content atom being worked on (if any)
    let contentAtomUUID: String?

    /// UUID of the idea being worked on (if any)
    let ideaAtomUUID: String?

    /// Type of writing session
    let sessionType: WritingSessionType

    /// Duration in seconds
    let duration: TimeInterval

    /// Pause time (time not actively typing, in seconds)
    let pauseTime: TimeInterval

    /// Active writing time (duration - pauseTime)
    var activeWritingTime: TimeInterval {
        max(0, duration - pauseTime)
    }

    /// Efficiency ratio (words / active minutes)
    var efficiency: Double {
        let activeMinutes = activeWritingTime / 60.0
        guard activeMinutes > 0 else { return 0 }
        return Double(netWordCount) / activeMinutes
    }

    /// XP earned estimate
    var estimatedXP: Int {
        // 1 XP per 100 words
        return max(1, netWordCount / 100)
    }

    init(
        startTime: Date,
        endTime: Date,
        wordCount: Int,
        netWordCount: Int,
        charactersTyped: Int,
        averageWPM: Double,
        peakWPM: Double,
        contentAtomUUID: String? = nil,
        ideaAtomUUID: String? = nil,
        sessionType: WritingSessionType,
        duration: TimeInterval,
        pauseTime: TimeInterval = 0
    ) {
        self.startTime = startTime
        self.endTime = endTime
        self.wordCount = wordCount
        self.netWordCount = netWordCount
        self.charactersTyped = charactersTyped
        self.averageWPM = averageWPM
        self.peakWPM = peakWPM
        self.contentAtomUUID = contentAtomUUID
        self.ideaAtomUUID = ideaAtomUUID
        self.sessionType = sessionType
        self.duration = duration
        self.pauseTime = pauseTime
    }
}

// MARK: - Word Count Entry Metadata

/// Metadata for wordCountEntry atoms - daily aggregates
struct WordCountEntryMetadata: Codable, Sendable {
    /// Date of this entry
    let date: Date

    /// Total words written today
    let totalWords: Int

    /// Net words (accounting for deletions)
    let netWords: Int

    /// Words by content type
    let wordsByType: [String: Int]  // WritingSessionType.rawValue: count

    /// Number of writing sessions today
    let sessionCount: Int

    /// Total active writing time (seconds)
    let totalActiveTime: TimeInterval

    /// Average WPM across all sessions
    let averageWPM: Double

    /// Best session WPM
    let bestSessionWPM: Double

    /// Comparison to 7-day average
    let vs7DayAverage: Double?

    /// Personal best flag
    let isPersonalBest: Bool

    init(
        date: Date,
        totalWords: Int,
        netWords: Int,
        wordsByType: [String: Int] = [:],
        sessionCount: Int,
        totalActiveTime: TimeInterval,
        averageWPM: Double,
        bestSessionWPM: Double,
        vs7DayAverage: Double? = nil,
        isPersonalBest: Bool = false
    ) {
        self.date = date
        self.totalWords = totalWords
        self.netWords = netWords
        self.wordsByType = wordsByType
        self.sessionCount = sessionCount
        self.totalActiveTime = totalActiveTime
        self.averageWPM = averageWPM
        self.bestSessionWPM = bestSessionWPM
        self.vs7DayAverage = vs7DayAverage
        self.isPersonalBest = isPersonalBest
    }
}

// MARK: - Focus Score Metadata

/// Metadata for focusScore atoms - attention quality snapshots
struct FocusScoreMetadata: Codable, Sendable {
    /// Timestamp of the snapshot
    let timestamp: Date

    /// Overall focus score (0-100)
    let score: Double

    /// Active app bundle ID at time of snapshot
    let activeAppBundleId: String

    /// Total screen time in minutes (today)
    let screenTimeMinutes: Int

    /// Productive time in minutes (today)
    let productiveMinutes: Int

    /// Distracted time in minutes (today)
    let distractedMinutes: Int

    /// Top distracting apps (bundle IDs)
    let topDistractions: [String]

    /// Time since last context switch (seconds)
    let timeSinceLastSwitch: TimeInterval

    /// Average focus session length today (seconds)
    let avgFocusSessionLength: TimeInterval

    /// Focus trend compared to yesterday
    let trend: Trend

    init(
        timestamp: Date,
        score: Double,
        activeAppBundleId: String,
        screenTimeMinutes: Int,
        productiveMinutes: Int,
        distractedMinutes: Int,
        topDistractions: [String] = [],
        timeSinceLastSwitch: TimeInterval = 0,
        avgFocusSessionLength: TimeInterval = 0,
        trend: Trend = .stable
    ) {
        self.timestamp = timestamp
        self.score = score
        self.activeAppBundleId = activeAppBundleId
        self.screenTimeMinutes = screenTimeMinutes
        self.productiveMinutes = productiveMinutes
        self.distractedMinutes = distractedMinutes
        self.topDistractions = topDistractions
        self.timeSinceLastSwitch = timeSinceLastSwitch
        self.avgFocusSessionLength = avgFocusSessionLength
        self.trend = trend
    }
}

// MARK: - Distraction Event Metadata

/// Type of distraction
enum DistractionType: String, Codable, Sendable {
    case appSwitch              // Switched to non-productive app
    case notification           // Notification interrupted
    case manualCheck            // User manually checked something
    case longBreak              // Extended break during work
    case siteVisit              // Visited distracting website
    case other

    var displayName: String {
        switch self {
        case .appSwitch: return "App Switch"
        case .notification: return "Notification"
        case .manualCheck: return "Manual Check"
        case .longBreak: return "Long Break"
        case .siteVisit: return "Site Visit"
        case .other: return "Other"
        }
    }
}

/// Metadata for distractionEvent atoms
struct DistractionEventMetadata: Codable, Sendable {
    /// When the distraction occurred
    let timestamp: Date

    /// Type of distraction
    let distractionType: DistractionType

    /// Duration of distraction (seconds)
    let duration: TimeInterval

    /// App that caused the distraction (bundle ID)
    let appBundleId: String?

    /// URL visited (if applicable)
    let url: String?

    /// What was being worked on when distracted
    let activeTaskUUID: String?

    /// Deep work block that was interrupted (if any)
    let deepWorkBlockUUID: String?

    /// Whether this broke a focus streak
    let brokeFocusStreak: Bool

    /// Focus streak length before break (seconds)
    let focusStreakLength: TimeInterval?

    init(
        timestamp: Date,
        distractionType: DistractionType,
        duration: TimeInterval,
        appBundleId: String? = nil,
        url: String? = nil,
        activeTaskUUID: String? = nil,
        deepWorkBlockUUID: String? = nil,
        brokeFocusStreak: Bool = false,
        focusStreakLength: TimeInterval? = nil
    ) {
        self.timestamp = timestamp
        self.distractionType = distractionType
        self.duration = duration
        self.appBundleId = appBundleId
        self.url = url
        self.activeTaskUUID = activeTaskUUID
        self.deepWorkBlockUUID = deepWorkBlockUUID
        self.brokeFocusStreak = brokeFocusStreak
        self.focusStreakLength = focusStreakLength
    }
}

// MARK: - Routine Definition Metadata

/// Metadata for routineDefinition atoms
struct RoutineDefinitionMetadata: Codable, Sendable {
    /// Routine name
    let name: String

    /// Days this routine applies to (0 = Sunday, 6 = Saturday)
    let daysOfWeek: [Int]

    /// Blocks in this routine
    let blocks: [RoutineBlock]

    /// Whether this routine is currently active
    let isActive: Bool

    /// When this routine was created
    let createdAt: Date

    /// Last modified date
    let lastModified: Date

    init(
        name: String,
        daysOfWeek: [Int],
        blocks: [RoutineBlock],
        isActive: Bool = true,
        createdAt: Date = Date(),
        lastModified: Date = Date()
    ) {
        self.name = name
        self.daysOfWeek = daysOfWeek
        self.blocks = blocks
        self.isActive = isActive
        self.createdAt = createdAt
        self.lastModified = lastModified
    }
}

/// A block within a routine
struct RoutineBlock: Codable, Sendable {
    /// Block label
    let label: String

    /// Start time (HH:mm format)
    let startTime: String

    /// End time (HH:mm format)
    let endTime: String

    /// Categories this block belongs to
    let categories: [String]

    /// Description
    let description: String?

    /// Color (hex)
    let color: String?

    /// Whether this block generates XP when completed
    let generatesXP: Bool

    /// XP value for completing this block
    let xpValue: Int

    init(
        label: String,
        startTime: String,
        endTime: String,
        categories: [String] = [],
        description: String? = nil,
        color: String? = nil,
        generatesXP: Bool = true,
        xpValue: Int = 10
    ) {
        self.label = label
        self.startTime = startTime
        self.endTime = endTime
        self.categories = categories
        self.description = description
        self.color = color
        self.generatesXP = generatesXP
        self.xpValue = xpValue
    }
}
