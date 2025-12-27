// CosmoOS/Voice/Pipeline/DeepWorkVoiceCommands.swift
// Voice commands for deep work sessions and workout logging

import Foundation
import GRDB

// MARK: - Deep Work Voice Command Patterns

/// Extension to PatternMatcher for deep work and workout voice commands.
/// These patterns enable fast voice control for:
/// - Starting/stopping deep work sessions
/// - Logging workouts
/// - Focus mode controls
extension PatternMatcher {

    /// Deep work and health action patterns
    nonisolated static var deepWorkPatterns: [CommandPattern] {
        [
            // ===== DEEP WORK START =====
            CommandPattern(
                regex: #"^(start|begin|enter|go\s+into)\s+(deep\s*work|focus\s*mode|flow\s*state|focus\s*session)\s*(for\s+(\d+)\s*(hours?|h|minutes?|mins?|m))?\s*$"#,
                action: .create,
                atomType: .scheduleBlock,
                extractor: { _ in
                    return PatternMatchResult(
                        action: .create,
                        atomType: .scheduleBlock,
                        title: "Deep Work",
                        matchedPattern: "start_deep_work",
                        confidence: 0.95
                    )
                },
                metadataExtractor: { match in
                    let durationValue = match[4]
                    let durationUnit = match[5].lowercased()

                    var durationMinutes = 60
                    if !durationValue.isEmpty, let value = Int(durationValue) {
                        if durationUnit.starts(with: "h") {
                            durationMinutes = value * 60
                        } else {
                            durationMinutes = value
                        }
                    }

                    return [
                        "blockType": VoiceAnyCodable("focus"),
                        "durationMinutes": VoiceAnyCodable(durationMinutes),
                        "startNow": VoiceAnyCodable(true)
                    ]
                }
            ),
            CommandPattern(
                regex: #"^(i('?m| am)\s+going\s+(into|to)\s+(deep\s*work|focus|flow))\s*$"#,
                action: .create,
                atomType: .scheduleBlock,
                extractor: { _ in
                    PatternMatchResult(
                        action: .create,
                        atomType: .scheduleBlock,
                        title: "Deep Work",
                        matchedPattern: "going_deep_work",
                        confidence: 0.9
                    )
                },
                metadataExtractor: { _ in
                    [
                        "blockType": VoiceAnyCodable("focus"),
                        "durationMinutes": VoiceAnyCodable(60),
                        "startNow": VoiceAnyCodable(true)
                    ]
                }
            ),
            CommandPattern(
                regex: #"^(deep\s*work|focus\s*mode)\s*(for\s+(\d+)\s*(hours?|h|minutes?|mins?|m))?\s*$"#,
                action: .create,
                atomType: .scheduleBlock,
                extractor: { _ in
                    return PatternMatchResult(
                        action: .create,
                        atomType: .scheduleBlock,
                        title: "Deep Work",
                        matchedPattern: "deep_work_simple",
                        confidence: 0.9
                    )
                },
                metadataExtractor: { match in
                    let durationValue = match[3]
                    let durationUnit = match[4].lowercased()

                    var durationMinutes = 60
                    if !durationValue.isEmpty, let value = Int(durationValue) {
                        if durationUnit.starts(with: "h") {
                            durationMinutes = value * 60
                        } else {
                            durationMinutes = value
                        }
                    }

                    return [
                        "blockType": VoiceAnyCodable("focus"),
                        "durationMinutes": VoiceAnyCodable(durationMinutes),
                        "startNow": VoiceAnyCodable(true)
                    ]
                }
            ),

            // ===== DEEP WORK STOP =====
            CommandPattern(
                regex: #"^(stop|end|finish|exit|leave)\s+(deep\s*work|focus\s*mode|flow\s*state|focus\s*session|focus)\s*$"#,
                action: .update,
                extractor: { _ in
                    PatternMatchResult(
                        action: .update,
                        matchedPattern: "stop_deep_work",
                        confidence: 0.95
                    )
                },
                metadataExtractor: { _ in
                    [
                        "status": VoiceAnyCodable("completed"),
                        "endNow": VoiceAnyCodable(true)
                    ]
                }
            ),
            CommandPattern(
                regex: #"^(i('?m| am)\s+done\s+(with\s+)?(deep\s*work|focus|flow))\s*$"#,
                action: .update,
                extractor: { _ in
                    PatternMatchResult(
                        action: .update,
                        matchedPattern: "done_deep_work",
                        confidence: 0.9
                    )
                },
                metadataExtractor: { _ in
                    [
                        "status": VoiceAnyCodable("completed"),
                        "endNow": VoiceAnyCodable(true)
                    ]
                }
            ),

            // ===== EXTEND DEEP WORK =====
            CommandPattern(
                regex: #"^(extend|add|continue)\s+(deep\s*work|focus)?\s*(for\s+)?(\d+)\s*(more\s+)?(hours?|h|minutes?|mins?|m)\s*$"#,
                action: .update,
                extractor: { _ in
                    return PatternMatchResult(
                        action: .update,
                        matchedPattern: "extend_deep_work",
                        confidence: 0.9
                    )
                },
                metadataExtractor: { match in
                    let durationValue = match[4]
                    let durationUnit = match[6].lowercased()

                    var additionalMinutes = 30
                    if let value = Int(durationValue) {
                        if durationUnit.starts(with: "h") {
                            additionalMinutes = value * 60
                        } else {
                            additionalMinutes = value
                        }
                    }

                    return [
                        "extendMinutes": VoiceAnyCodable(additionalMinutes)
                    ]
                }
            ),

            // ===== WORKOUT LOGGING =====
            CommandPattern(
                regex: #"^(log|record|add)\s+(a\s+)?workout\s*(.*)$"#,
                action: .create,
                atomType: .workout,
                extractor: { match in
                    let workoutDetails = match[3].trimmingCharacters(in: .whitespaces)
                    let title = workoutDetails.isEmpty ? "Workout" : workoutDetails.capitalized

                    return PatternMatchResult(
                        action: .create,
                        atomType: .workout,
                        title: title,
                        matchedPattern: "log_workout",
                        confidence: 0.95
                    )
                },
                metadataExtractor: { _ in
                    [
                        "startedAt": VoiceAnyCodable(ISO8601DateFormatter().string(from: Date())),
                        "source": VoiceAnyCodable("voice")
                    ]
                }
            ),
            CommandPattern(
                regex: #"^(i\s+)?(just\s+)?(did|finished|completed)\s+(a\s+)?(workout|exercise|training|gym|run|walk|cycle|swim)\s*(.*)$"#,
                action: .create,
                atomType: .workout,
                extractor: { match in
                    let workoutType = match[5].capitalized
                    let details = match[6].trimmingCharacters(in: .whitespaces)
                    let title = details.isEmpty ? workoutType : "\(workoutType): \(details)"

                    return PatternMatchResult(
                        action: .create,
                        atomType: .workout,
                        title: title,
                        matchedPattern: "did_workout",
                        confidence: 0.9
                    )
                },
                metadataExtractor: { match in
                    let workoutType = match[5].lowercased()

                    return [
                        "workoutType": VoiceAnyCodable(workoutType),
                        "completedAt": VoiceAnyCodable(ISO8601DateFormatter().string(from: Date())),
                        "source": VoiceAnyCodable("voice")
                    ]
                }
            ),
            CommandPattern(
                regex: #"^(i\s+)?(went\s+for|had)\s+(a\s+)?(\d+)?\s*(minute|min|hour|km|mile)?\s*(run|walk|jog|swim|cycle|ride|hike)\s*$"#,
                action: .create,
                atomType: .workout,
                extractor: { match in
                    let amount = match[4]
                    let unit = match[5]
                    let activity = match[6].capitalized

                    var title = activity
                    if !amount.isEmpty {
                        title = "\(amount) \(unit) \(activity)"
                    }

                    return PatternMatchResult(
                        action: .create,
                        atomType: .workout,
                        title: title,
                        matchedPattern: "went_for_workout",
                        confidence: 0.9
                    )
                },
                metadataExtractor: { match in
                    let amount = match[4]
                    let unit = match[5].lowercased()
                    let activity = match[6].lowercased()

                    var metadata: [String: VoiceAnyCodable] = [
                        "workoutType": VoiceAnyCodable(activity),
                        "completedAt": VoiceAnyCodable(ISO8601DateFormatter().string(from: Date())),
                        "source": VoiceAnyCodable("voice")
                    ]

                    if let value = Int(amount) {
                        if unit.contains("min") {
                            metadata["durationMinutes"] = VoiceAnyCodable(value)
                        } else if unit.contains("hour") {
                            metadata["durationMinutes"] = VoiceAnyCodable(value * 60)
                        } else if unit.contains("km") {
                            metadata["distanceKm"] = VoiceAnyCodable(Double(value))
                        } else if unit.contains("mile") {
                            metadata["distanceKm"] = VoiceAnyCodable(Double(value) * 1.60934)
                        }
                    }

                    return metadata
                }
            ),

            // ===== STRENGTH WORKOUT LOGGING =====
            CommandPattern(
                regex: #"^(log|record|add)\s+(\d+)\s*(reps?|sets?)\s+(of\s+)?(.+)$"#,
                action: .create,
                atomType: .workout,
                extractor: { match in
                    let count = match[2]
                    let countType = match[3].lowercased()
                    let exercise = match[5].capitalized

                    let title = "\(count) \(countType) of \(exercise)"

                    return PatternMatchResult(
                        action: .create,
                        atomType: .workout,
                        title: title,
                        matchedPattern: "log_reps",
                        confidence: 0.9
                    )
                },
                metadataExtractor: { match in
                    let count = Int(match[2]) ?? 0
                    let countType = match[3].lowercased()
                    let exercise = match[5].lowercased()

                    var metadata: [String: VoiceAnyCodable] = [
                        "workoutType": VoiceAnyCodable("strength"),
                        "exercise": VoiceAnyCodable(exercise),
                        "completedAt": VoiceAnyCodable(ISO8601DateFormatter().string(from: Date())),
                        "source": VoiceAnyCodable("voice")
                    ]

                    if countType.contains("rep") {
                        metadata["reps"] = VoiceAnyCodable(count)
                    } else if countType.contains("set") {
                        metadata["sets"] = VoiceAnyCodable(count)
                    }

                    return metadata
                }
            ),

            // ===== BREAK/REST COMMANDS =====
            CommandPattern(
                regex: #"^(take\s+a|need\s+a)\s+(break|rest)\s*(for\s+(\d+)\s*(minutes?|mins?|m))?\s*$"#,
                action: .create,
                atomType: .scheduleBlock,
                extractor: { _ in
                    return PatternMatchResult(
                        action: .create,
                        atomType: .scheduleBlock,
                        title: "Break",
                        matchedPattern: "take_break",
                        confidence: 0.9
                    )
                },
                metadataExtractor: { match in
                    let durationValue = match[4]
                    var durationMinutes = 15

                    if !durationValue.isEmpty, let value = Int(durationValue) {
                        durationMinutes = value
                    }

                    return [
                        "blockType": VoiceAnyCodable("break"),
                        "durationMinutes": VoiceAnyCodable(durationMinutes),
                        "startNow": VoiceAnyCodable(true)
                    ]
                }
            ),

            // ===== POMODORO COMMANDS =====
            CommandPattern(
                regex: #"^(start|begin)\s+(a\s+)?pomodoro\s*$"#,
                action: .create,
                atomType: .scheduleBlock,
                extractor: { _ in
                    PatternMatchResult(
                        action: .create,
                        atomType: .scheduleBlock,
                        title: "Pomodoro",
                        matchedPattern: "start_pomodoro",
                        confidence: 0.95
                    )
                },
                metadataExtractor: { _ in
                    [
                        "blockType": VoiceAnyCodable("focus"),
                        "pomodoroMode": VoiceAnyCodable(true),
                        "durationMinutes": VoiceAnyCodable(25),
                        "startNow": VoiceAnyCodable(true)
                    ]
                }
            ),
        ]
    }
}

// MARK: - Deep Work Session Handler

/// Handles deep work session state and commands.
/// Manages active focus sessions and workout tracking.
actor DeepWorkSessionHandler {
    static let shared = DeepWorkSessionHandler()

    // Current session state
    private var activeSession: FocusSession?

    struct FocusSession {
        let id: UUID
        let startedAt: Date
        let plannedDuration: TimeInterval
        let type: FocusType
        var pausedAt: Date?
        var totalPausedTime: TimeInterval = 0

        enum FocusType: String, Sendable {
            case deepWork = "deep_work"
            case pomodoro = "pomodoro"
            case focusBlock = "focus_block"
        }

        var elapsedTime: TimeInterval {
            let now = Date()
            let elapsed = now.timeIntervalSince(startedAt) - totalPausedTime
            if let pauseStart = pausedAt {
                return elapsed - now.timeIntervalSince(pauseStart)
            }
            return elapsed
        }

        var remainingTime: TimeInterval {
            max(0, plannedDuration - elapsedTime)
        }

        var isExpired: Bool {
            remainingTime <= 0
        }
    }

    // MARK: - Session Management

    /// Start a new focus session
    func startSession(type: FocusSession.FocusType, duration: TimeInterval) async -> FocusSession {
        // End any existing session
        if activeSession != nil {
            _ = await endSession()
        }

        let session = FocusSession(
            id: UUID(),
            startedAt: Date(),
            plannedDuration: duration,
            type: type
        )

        activeSession = session

        // Post notification for UI
        NotificationCenter.default.post(
            name: .deepWorkSessionStarted,
            object: nil,
            userInfo: ["session": session]
        )

        return session
    }

    /// End the current focus session
    func endSession() async -> FocusSession? {
        guard let session = activeSession else { return nil }

        activeSession = nil

        // Post notification for UI and XP calculation
        NotificationCenter.default.post(
            name: .deepWorkSessionEnded,
            object: nil,
            userInfo: [
                "session": session,
                "actualDuration": session.elapsedTime
            ]
        )

        return session
    }

    /// Pause the current session
    func pauseSession() async {
        guard var session = activeSession, session.pausedAt == nil else { return }
        session.pausedAt = Date()
        activeSession = session

        NotificationCenter.default.post(
            name: .deepWorkSessionPaused,
            object: nil,
            userInfo: ["session": session]
        )
    }

    /// Resume a paused session
    func resumeSession() async {
        guard var session = activeSession, let pauseStart = session.pausedAt else { return }

        session.totalPausedTime += Date().timeIntervalSince(pauseStart)
        session.pausedAt = nil
        activeSession = session

        NotificationCenter.default.post(
            name: .deepWorkSessionResumed,
            object: nil,
            userInfo: ["session": session]
        )
    }

    /// Extend the current session
    func extendSession(by minutes: Int) async {
        guard let session = activeSession else { return }

        // Create new session with extended duration
        let newSession = FocusSession(
            id: session.id,
            startedAt: session.startedAt,
            plannedDuration: session.plannedDuration + TimeInterval(minutes * 60),
            type: session.type,
            pausedAt: session.pausedAt,
            totalPausedTime: session.totalPausedTime
        )

        activeSession = newSession

        NotificationCenter.default.post(
            name: .deepWorkSessionExtended,
            object: nil,
            userInfo: [
                "session": newSession,
                "addedMinutes": minutes
            ]
        )
    }

    /// Get current session state
    func getCurrentSession() async -> FocusSession? {
        return activeSession
    }

    /// Check if in active focus session
    func isInFocusMode() async -> Bool {
        guard let currentSession = activeSession else { return false }
        return !currentSession.isExpired && currentSession.pausedAt == nil
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let deepWorkSessionStarted = Notification.Name("deepWorkSessionStarted")
    static let deepWorkSessionEnded = Notification.Name("deepWorkSessionEnded")
    static let deepWorkSessionPaused = Notification.Name("deepWorkSessionPaused")
    static let deepWorkSessionResumed = Notification.Name("deepWorkSessionResumed")
    static let deepWorkSessionExtended = Notification.Name("deepWorkSessionExtended")
}

// MARK: - XP Integration

extension DeepWorkSessionHandler {

    /// Calculate XP earned for a completed focus session
    func calculateFocusXP(session: FocusSession) -> Int {
        let minutesWorked = Int(session.elapsedTime / 60)

        // Base XP: 2 XP per minute of focus
        var xp = minutesWorked * 2

        // Bonus for completing the full planned duration
        if session.elapsedTime >= session.plannedDuration {
            xp += 25  // Completion bonus
        }

        // Bonus for long sessions (60+ minutes)
        if minutesWorked >= 60 {
            xp += 50  // Deep work bonus
        }

        // Pomodoro bonus
        if session.type == .pomodoro {
            xp += 10
        }

        return xp
    }
}

// MARK: - Voice Workout Handler

/// Handles voice-logged workouts and integrates with HealthKit.
/// Voice entries are supplementary to HealthKit data - they add context or log
/// workouts that weren't tracked by Apple Watch.
actor VoiceWorkoutHandler {
    @MainActor static let shared = VoiceWorkoutHandler()

    private let healthKitSync: HealthKitSyncService?
    private let database: any DatabaseWriter

    @MainActor
    init(database: (any DatabaseWriter)? = nil) {
        self.database = database ?? (CosmoDatabase.shared.dbQueue! as any DatabaseWriter)
        // HealthKit sync is initialized elsewhere
        self.healthKitSync = nil
    }

    /// Process a voice-logged workout
    /// Returns nil if this workout was already synced from HealthKit
    func processVoiceWorkout(
        type: String,
        durationMinutes: Int?,
        details: String?
    ) async throws -> Atom? {

        // Check if there's a recent HealthKit workout that matches
        if let recentMatch = try await findRecentHealthKitWorkout(type: type, durationMinutes: durationMinutes) {
            // Already synced from HealthKit, just add voice context
            return try await enrichExistingWorkout(recentMatch, with: details)
        }

        // No HealthKit match - create a manual workout atom
        return try await createManualWorkoutAtom(
            type: type,
            durationMinutes: durationMinutes,
            details: details
        )
    }

    /// Find a recent HealthKit workout that might match this voice entry
    private func findRecentHealthKitWorkout(type: String, durationMinutes: Int?) async throws -> Atom? {
        let oneHourAgo = Calendar.current.date(byAdding: .hour, value: -2, to: Date())!

        return try await database.read { db in
            try Atom
                .filter(Column("type") == AtomType.workout.rawValue)
                .filter(Column("createdAt") >= oneHourAgo.ISO8601Format())
                .filter(sql: "metadata LIKE ? AND metadata LIKE ?",
                        arguments: ["%\"source\":\"healthkit\"%", "%\(type.lowercased())%"])
                .order(Column("createdAt").desc)
                .fetchOne(db)
        }
    }

    /// Enrich an existing HealthKit workout with voice context
    private func enrichExistingWorkout(_ atom: Atom, with details: String?) async throws -> Atom? {
        guard let details = details, !details.isEmpty else { return nil }

        // Update the atom with additional voice context
        try await database.write { db in
            var updatedAtom = atom
            updatedAtom.body = (atom.body ?? "") + "\n\nVoice note: \(details)"
            try updatedAtom.update(db)
        }

        return atom
    }

    /// Create a manual workout atom (not from HealthKit)
    private func createManualWorkoutAtom(
        type: String,
        durationMinutes: Int?,
        details: String?
    ) async throws -> Atom {

        let workoutTitle: String
        if let duration = durationMinutes {
            workoutTitle = "\(type.capitalized) - \(duration)min"
        } else {
            workoutTitle = type.capitalized
        }

        let metadata: [String: Any] = [
            "workoutType": type.lowercased(),
            "durationMinutes": durationMinutes ?? 0,
            "source": "voice",
            "isManualEntry": true
        ]

        let metadataJSON = try JSONSerialization.data(withJSONObject: metadata)

        let atom = try await database.write { db -> Atom in
            var newAtom = Atom.new(
                type: .workout,
                title: workoutTitle,
                body: details ?? "Manual workout logged via voice"
            )
            newAtom.metadata = String(data: metadataJSON, encoding: .utf8)
            try newAtom.insert(db)

            // Award XP for manual workout logging
            var xp = 10  // Base XP for logging
            if let duration = durationMinutes {
                if duration >= 60 { xp += 15 }
                else if duration >= 30 { xp += 10 }
                else if duration >= 15 { xp += 5 }
            }

            // Update level state
            if var state = try CosmoLevelState.fetchOne(db) {
                state.addXP(xp, dimension: "physiological")
                try state.update(db)
            }

            return newAtom
        }

        return atom
    }

    /// Log workout from voice command with smart HealthKit integration
    func logWorkoutFromVoice(
        action: ParsedAction,
        database: any DatabaseWriter
    ) async throws -> Atom {
        // Extract workout details from parsed action
        let workoutType = extractWorkoutType(from: action)
        let durationMinutes = extractDuration(from: action)
        let details = action.title

        // Check for HealthKit match or create manual entry
        if let result = try await processVoiceWorkout(
            type: workoutType,
            durationMinutes: durationMinutes,
            details: details
        ) {
            return result
        }

        // Fallback: create basic workout atom
        return try await createManualWorkoutAtom(
            type: workoutType,
            durationMinutes: durationMinutes,
            details: details
        )
    }

    private func extractWorkoutType(from action: ParsedAction) -> String {
        if let metadata = action.metadata,
           let typeValue = metadata["workoutType"]?.value as? String {
            return typeValue
        }
        return action.title?.lowercased() ?? "workout"
    }

    private func extractDuration(from action: ParsedAction) -> Int? {
        if let metadata = action.metadata,
           let duration = metadata["durationMinutes"]?.value as? Int {
            return duration
        }
        return nil
    }
}

// MARK: - HealthKit Workout Integration

/// Coordinates between voice commands and HealthKit for workout tracking
actor WorkoutIntegrationCoordinator {
    static let shared = WorkoutIntegrationCoordinator()

    /// Get today's workouts from all sources (HealthKit + manual)
    func getTodayWorkouts(database: any DatabaseWriter) async throws -> [Atom] {
        let todayStart = Calendar.current.startOfDay(for: Date())

        return try await database.read { db in
            try Atom
                .filter(Column("type") == AtomType.workout.rawValue)
                .filter(Column("createdAt") >= todayStart.ISO8601Format())
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    /// Get workout summary for voice response
    func getWorkoutSummaryForVoice(database: any DatabaseWriter) async throws -> QueryResponse {
        let workouts = try await getTodayWorkouts(database: database)

        if workouts.isEmpty {
            return QueryResponse(
                queryType: .todayHealth,
                spokenText: "You haven't logged any workouts today yet.",
                displayTitle: "No Workouts Today",
                displaySubtitle: nil,
                metrics: []
            )
        }

        let totalMinutes = workouts.reduce(0) { total, workout in
            guard let metadataString = workout.metadata,
                  let data = metadataString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let duration = json["duration"] as? Double ?? json["durationMinutes"] as? Double else {
                return total
            }
            return total + Int(duration / 60)
        }

        let totalCalories = workouts.reduce(0.0) { total, workout in
            guard let metadataString = workout.metadata,
                  let data = metadataString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let calories = json["activeCalories"] as? Double else {
                return total
            }
            return total + calories
        }

        let spokenText = "You've done \(workouts.count) workout\(workouts.count == 1 ? "" : "s") today, " +
            "totaling \(totalMinutes) minutes and \(Int(totalCalories)) calories burned."

        return QueryResponse(
            queryType: .todayHealth,
            spokenText: spokenText,
            displayTitle: "\(workouts.count) Workouts Today",
            displaySubtitle: "\(totalMinutes) minutes total",
            metrics: [
                QueryMetric(label: "Workouts", value: "\(workouts.count)", icon: "figure.run", color: "green", trend: nil),
                QueryMetric(label: "Duration", value: "\(totalMinutes)min", icon: "clock.fill", color: "blue", trend: nil),
                QueryMetric(label: "Calories", value: "\(Int(totalCalories))", icon: "flame.fill", color: "orange", trend: nil)
            ],
            action: QueryAction(title: "View Details", destination: "workouts")
        )
    }
}
