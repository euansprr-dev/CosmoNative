//
//  DeepWorkSessionEngine.swift
//  CosmoOS
//
//  Enhanced deep work session engine with timer, focus scoring,
//  and distraction detection via NSWorkspace app-switch monitoring.
//

import Foundation
import Combine
import AppKit

// MARK: - Session State

/// Current state of a focus session (formerly lived beside the retired session timer manager)
public enum SessionState: String, Codable, Sendable {
    case idle           // No active session
    case running        // Timer actively counting
    case paused         // Timer paused
    case completing     // Session ending, processing results
    case completed      // Session finished
}

// MARK: - Deep Work Session (Internal Model)

/// Represents a live deep work session with distraction tracking (engine-internal model)
struct ActiveDeepWorkSession: Codable, Sendable {
    let id: String
    let taskUUID: String?
    let taskTitle: String
    let intent: TaskIntent
    let intentUUID: String?
    let intentTitleSnapshot: String?
    let habitUUID: String?
    let habitTitleSnapshot: String?
    var plannedMinutes: Int
    let startedAt: Date

    var pausedAt: Date?
    var totalPausedSeconds: TimeInterval
    var state: SessionState

    struct DistractionEvent: Codable, Sendable {
        let timestamp: Date
        let fromApp: String?
    }

    var distractionEvents: [DistractionEvent]

    init(
        taskUUID: String?,
        taskTitle: String,
        intent: TaskIntent,
        intentUUID: String?,
        intentTitleSnapshot: String?,
        habitUUID: String?,
        habitTitleSnapshot: String?,
        plannedMinutes: Int
    ) {
        self.id = UUID().uuidString
        self.taskUUID = taskUUID
        self.taskTitle = taskTitle
        self.intent = intent
        self.intentUUID = intentUUID
        self.intentTitleSnapshot = intentTitleSnapshot
        self.habitUUID = habitUUID
        self.habitTitleSnapshot = habitTitleSnapshot
        self.plannedMinutes = plannedMinutes
        self.startedAt = Date()
        self.pausedAt = nil
        self.totalPausedSeconds = 0
        self.state = .running
        self.distractionEvents = []
    }

    /// Elapsed active seconds (excluding pauses)
    var elapsedActiveSeconds: TimeInterval {
        guard state != .idle else { return 0 }
        let now = Date()
        var elapsed = now.timeIntervalSince(startedAt) - totalPausedSeconds
        if let pausedAt = pausedAt {
            elapsed -= now.timeIntervalSince(pausedAt)
        }
        return max(0, elapsed)
    }

    var remainingSeconds: TimeInterval {
        guard plannedMinutes > 0 else { return 0 }
        return max(0, TimeInterval(plannedMinutes * 60) - elapsedActiveSeconds)
    }

    var progress: Double {
        guard plannedMinutes > 0 else { return 0 }
        return min(1.0, elapsedActiveSeconds / TimeInterval(plannedMinutes * 60))
    }

    var isOpenEnded: Bool {
        plannedMinutes <= 0
    }
}

// MARK: - Timed Goal (time-based tasks & habits)

/// Surfaced when the active session crosses a time goal — the task's
/// `timeGoalMinutes` (per occurrence day for recurring tasks, lifetime for
/// one-offs) or a minutes-based habit's daily target. One prompt per session.
struct TimedGoalPrompt: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case task
        case habit
    }

    let id: String              // session id — guarantees once-per-session
    let kind: Kind
    let taskUUID: String?
    let habitUUID: String?
    let title: String
    let goalMinutes: Int
}

/// Goal state resolved once at session start: what the goal is and how much
/// already counted toward it before this session began.
private struct TimedTaskGoalContext {
    let taskUUID: String
    let taskTitle: String
    let goalMinutes: Int
    /// Seconds tracked toward the goal before this session (occurrence-day
    /// tracked time for recurring tasks, lifetime totalFocusMinutes for one-offs).
    let priorSeconds: TimeInterval
    let isRecurring: Bool
    var hasFiredPrompt: Bool

    func cumulativeSeconds(elapsed: TimeInterval) -> TimeInterval {
        priorSeconds + elapsed
    }

    func goalReached(elapsed: TimeInterval) -> Bool {
        cumulativeSeconds(elapsed: elapsed) >= TimeInterval(goalMinutes * 60)
    }
}

/// Daily-minutes goal of a time-based habit the session is attributed to.
/// Progress is derived from synced deep-work blocks; no completion record is
/// ever written for minutes habits (prevents cross-device double-credit).
private struct TimedHabitGoalContext {
    let habitUUID: String
    let habitTitle: String
    let goalMinutes: Int
    let priorSeconds: TimeInterval
    var hasFiredPrompt: Bool

    func goalReached(elapsed: TimeInterval) -> Bool {
        priorSeconds + elapsed >= TimeInterval(goalMinutes * 60)
    }
}

// MARK: - DeepWorkSessionEngine

@MainActor
class DeepWorkSessionEngine: ObservableObject {

    // MARK: - Singleton

    static let shared = DeepWorkSessionEngine()

    // MARK: - Published State

    @Published var activeSession: ActiveDeepWorkSession?
    @Published var focusScore: Double = 100
    @Published var distractionCount: Int = 0
    @Published var elapsedSeconds: Int = 0
    @Published var isTimerRunning: Bool = false
    @Published var showExtensionPrompt: Bool = false
    @Published var sessionResult: DeepWorkSessionResult?
    @Published var timedGoalPrompt: TimedGoalPrompt?

    private var taskGoalContext: TimedTaskGoalContext?
    private var habitGoalContext: TimedHabitGoalContext?

    // MARK: - Dependencies

    private let atomRepository: AtomRepository

    // MARK: - Timer

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastAppSwitchTime: Date?
    private var workspaceObserver: Any?

    // MARK: - Initialization

    init(atomRepository: AtomRepository? = nil) {
        self.atomRepository = atomRepository ?? AtomRepository.shared
    }

    deinit {
        timer?.invalidate()
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    // MARK: - Session Lifecycle

    func startSession(
        taskUUID: String?,
        taskTitle: String,
        intent: TaskIntent,
        intentUUID: String? = nil,
        intentTitleSnapshot: String? = nil,
        habitUUID: String? = nil,
        habitTitleSnapshot: String? = nil,
        plannedMinutes: Int
    ) {
        // End any existing session without saving
        if activeSession != nil {
            stopTimer()
            stopDistractionDetection()
        }

        let session = ActiveDeepWorkSession(
            taskUUID: taskUUID,
            taskTitle: taskTitle,
            intent: intent,
            intentUUID: intentUUID,
            intentTitleSnapshot: intentTitleSnapshot,
            habitUUID: habitUUID,
            habitTitleSnapshot: habitTitleSnapshot,
            plannedMinutes: plannedMinutes
        )

        activeSession = session
        focusScore = 100
        distractionCount = 0
        elapsedSeconds = 0
        isTimerRunning = true
        showExtensionPrompt = false
        sessionResult = nil
        timedGoalPrompt = nil
        taskGoalContext = nil
        habitGoalContext = nil

        if let taskUUID {
            Task { [weak self] in
                await self?.loadTimedGoalContext(taskUUID: taskUUID, sessionId: session.id)
            }
        }
        if let habitUUID {
            Task { [weak self] in
                await self?.loadHabitGoalContext(habitUUID: habitUUID, sessionId: session.id)
            }
        }

        startTimer()
        startDistractionDetection()

        NotificationCenter.default.post(
            name: .deepWorkSessionStarted,
            object: nil,
            userInfo: ["sessionId": session.id]
        )
    }

    func pauseSession() {
        guard var session = activeSession, session.state == .running else { return }

        session.pausedAt = Date()
        session.state = .paused
        activeSession = session
        isTimerRunning = false

        stopTimer()

        NotificationCenter.default.post(name: .deepWorkSessionPaused, object: nil)
    }

    func resumeSession() {
        guard var session = activeSession,
              session.state == .paused,
              let pausedAt = session.pausedAt else { return }

        session.totalPausedSeconds += Date().timeIntervalSince(pausedAt)
        session.pausedAt = nil
        session.state = .running
        activeSession = session
        isTimerRunning = true
        showExtensionPrompt = false

        startTimer()

        NotificationCenter.default.post(name: .deepWorkSessionResumed, object: nil)
    }

    func extendSession(minutes: Int) {
        guard var session = activeSession else { return }

        session.plannedMinutes += minutes
        activeSession = session
        showExtensionPrompt = false

        if !isTimerRunning {
            activeSession?.state = .running
            activeSession?.pausedAt = nil
            isTimerRunning = true
            startTimer()
        }

        NotificationCenter.default.post(
            name: .deepWorkSessionExtended,
            object: nil,
            userInfo: ["addedMinutes": minutes]
        )
    }

    func endSession(notes: String? = nil) async {
        guard let session = activeSession else { return }

        stopTimer()
        stopDistractionDetection()

        let actualMinutes = Int(session.elapsedActiveSeconds / 60)
        let effectivePlannedMinutes = session.isOpenEnded ? max(actualMinutes, 1) : session.plannedMinutes

        // Find atoms created during this session
        let outputAtomUUIDs = await findOutputAtoms(since: session.startedAt)

        _ = effectivePlannedMinutes

        // Create session metadata
        let sessionMetadata = DeepWorkSessionMetadata(
            taskUUID: session.taskUUID,
            startedAt: ISO8601.string(from: session.startedAt),
            endedAt: ISO8601.string(from: Date()),
            plannedMinutes: session.plannedMinutes,
            actualMinutes: actualMinutes,
            focusScore: focusScore,
            distractionCount: distractionCount,
            intent: session.intent.rawValue,
            intentUUID: session.intentUUID,
            intentTitleSnapshot: session.intentTitleSnapshot,
            habitUUID: session.habitUUID,
            habitTitleSnapshot: session.habitTitleSnapshot,
            outputAtomUUIDs: outputAtomUUIDs,
            xpEarned: nil,
            notes: notes
        )

        // Save session atom
        await saveSessionAtom(session: session, metadata: sessionMetadata)

        // Update parent task metadata
        if let taskUUID = session.taskUUID {
            await updateTaskSessionTracking(taskUUID: taskUUID, actualMinutes: actualMinutes)
        }

        // Timed-task goal: ending a session past the goal completes the task/occurrence.
        // completeTimedGoalTask dedupes against already-completed state, so a "Mark
        // complete" tap from the prompt or another device can't double-complete.
        if let context = taskGoalContext,
           context.taskUUID == session.taskUUID,
           context.goalReached(elapsed: session.elapsedActiveSeconds) {
            let cumulativeMinutes = Int(context.cumulativeSeconds(elapsed: session.elapsedActiveSeconds) / 60)
            await completeTimedGoalTask(context, cumulativeMinutes: cumulativeMinutes)
        }
        taskGoalContext = nil
        habitGoalContext = nil
        timedGoalPrompt = nil

        // Build result for summary card
        let result = DeepWorkSessionResult(
            sessionId: session.id,
            taskTitle: session.taskTitle,
            intent: session.intent,
            plannedMinutes: session.plannedMinutes,
            actualMinutes: actualMinutes,
            focusScore: focusScore,
            distractionCount: distractionCount,
            outputAtomCount: outputAtomUUIDs.count,
            notes: notes
        )

        sessionResult = result
        activeSession = nil
        isTimerRunning = false
        showExtensionPrompt = false
        elapsedSeconds = 0

        NotificationCenter.default.post(
            name: .deepWorkSessionEnded,
            object: nil,
            userInfo: [
                "sessionId": session.id,
                "actualMinutes": actualMinutes,
                "focusScore": focusScore
            ]
        )
    }

    func dismissResult() {
        sessionResult = nil
    }

    // MARK: - Timer

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.timerTick()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func timerTick() {
        guard let session = activeSession, session.state == .running else { return }

        // Only update Published property when integer seconds actually change
        let newSeconds = Int(session.elapsedActiveSeconds)
        guard newSeconds != elapsedSeconds else { return }
        elapsedSeconds = newSeconds

        // Check if target reached
        if !session.isOpenEnded && session.remainingSeconds <= 0 && !showExtensionPrompt {
            showExtensionPrompt = true
        }

        // Timed-task goal: fire once when cumulative tracked time crosses the goal
        if var context = taskGoalContext,
           !context.hasFiredPrompt,
           context.goalReached(elapsed: session.elapsedActiveSeconds) {
            context.hasFiredPrompt = true
            taskGoalContext = context
            fireTimedGoalPrompt(
                TimedGoalPrompt(
                    id: session.id,
                    kind: .task,
                    taskUUID: context.taskUUID,
                    habitUUID: nil,
                    title: context.taskTitle,
                    goalMinutes: context.goalMinutes
                )
            )
        }

        // Time-based habit daily goal (task prompt wins when both cross this tick)
        if var context = habitGoalContext,
           !context.hasFiredPrompt,
           context.goalReached(elapsed: session.elapsedActiveSeconds) {
            context.hasFiredPrompt = true
            habitGoalContext = context
            if timedGoalPrompt == nil {
                fireTimedGoalPrompt(
                    TimedGoalPrompt(
                        id: session.id,
                        kind: .habit,
                        taskUUID: nil,
                        habitUUID: context.habitUUID,
                        title: context.habitTitle,
                        goalMinutes: context.goalMinutes
                    )
                )
            }
        }
    }

    // MARK: - Timed Goal

    /// "Mark complete" from the goal prompt (in-app popup or system notification):
    /// completes the task/occurrence with the cumulative tracked minutes, then ends
    /// the session so the deep-work block records this sitting. Habit prompts have
    /// no completion to write (derived progress) — they just wrap up the session.
    func markTimedGoalComplete() async {
        let promptKind = timedGoalPrompt?.kind
        timedGoalPrompt = nil

        if promptKind == .habit {
            await endSession()
            return
        }

        guard let context = taskGoalContext, let session = activeSession else { return }
        let cumulativeMinutes = Int(context.cumulativeSeconds(elapsed: session.elapsedActiveSeconds) / 60)
        taskGoalContext = nil  // endSession must not attempt a second completion
        await completeTimedGoalTask(context, cumulativeMinutes: cumulativeMinutes)
        await endSession()
    }

    /// "Keep going" — dismiss the prompt; the session continues and ending it
    /// later still auto-completes the task.
    func dismissTimedGoalPrompt() {
        timedGoalPrompt = nil
    }

    private func loadTimedGoalContext(taskUUID: String, sessionId: String) async {
        do {
            guard let atom = try await atomRepository.fetch(uuid: taskUUID),
                  let meta = atom.metadataValue(as: TaskMetadata.self),
                  let goalMinutes = meta.timeGoalMinutes, goalMinutes > 0 else { return }

            let isRecurring = meta.recurrence != nil
            let priorMinutes: Int
            if isRecurring {
                priorMinutes = await trackedMinutesToday(forTaskUUID: taskUUID)
            } else {
                priorMinutes = meta.totalFocusMinutes ?? 0
            }

            // The session may have been swapped while we were loading.
            guard activeSession?.id == sessionId else { return }

            taskGoalContext = TimedTaskGoalContext(
                taskUUID: taskUUID,
                taskTitle: atom.title ?? "Task",
                goalMinutes: goalMinutes,
                priorSeconds: TimeInterval(priorMinutes * 60),
                isRecurring: isRecurring,
                hasFiredPrompt: priorMinutes >= goalMinutes  // already met: no re-prompt
            )

            // A timed session is the moment the background "time's up"
            // notification becomes relevant — ask lazily, not at launch.
            if ProactiveNotificationService.shared.authorizationStatus == .notDetermined {
                _ = await ProactiveNotificationService.shared.requestAuthorization()
            }
        } catch {
            print("DeepWorkSessionEngine: Failed to load timed goal context - \(error)")
        }
    }

    /// Minutes tracked on this task today, from deep-work-block atoms (synced, so
    /// sessions from other devices count).
    private func trackedMinutesToday(forTaskUUID taskUUID: String) async -> Int {
        do {
            let atoms = try await atomRepository.fetchAll(type: .deepWorkBlock)
            let todayStart = Calendar.current.startOfDay(for: Date())
            return atoms.reduce(into: 0) { partial, atom in
                guard let session = CommandCenterHabitPersistence.deepWorkSession(from: atom),
                      session.startedAt >= todayStart,
                      session.taskUUID == taskUUID else { return }
                partial += session.minutes
            }
        } catch {
            return 0
        }
    }

    private func loadHabitGoalContext(habitUUID: String, sessionId: String) async {
        guard let habit = CommandCenterHabitEngine.shared.definition(for: habitUUID),
              habit.isTimeBased,
              let goalMinutes = habit.dailyTargetMinutes, goalMinutes > 0 else { return }

        let priorMinutes = await trackedMinutesToday(forHabitUUID: habitUUID)
        guard activeSession?.id == sessionId else { return }

        habitGoalContext = TimedHabitGoalContext(
            habitUUID: habitUUID,
            habitTitle: habit.title,
            goalMinutes: goalMinutes,
            priorSeconds: TimeInterval(priorMinutes * 60),
            hasFiredPrompt: priorMinutes >= goalMinutes  // already met today: no re-prompt
        )
    }

    /// Minutes tracked toward a habit today across all its sessions (synced).
    private func trackedMinutesToday(forHabitUUID habitUUID: String) async -> Int {
        do {
            let atoms = try await atomRepository.fetchAll(type: .deepWorkBlock)
            let todayStart = Calendar.current.startOfDay(for: Date())
            return atoms.reduce(into: 0) { partial, atom in
                guard let session = CommandCenterHabitPersistence.deepWorkSession(from: atom),
                      session.startedAt >= todayStart,
                      session.habitUUID == habitUUID else { return }
                partial += session.minutes
            }
        } catch {
            return 0
        }
    }

    private func fireTimedGoalPrompt(_ prompt: TimedGoalPrompt) {
        timedGoalPrompt = prompt
        NotificationCenter.default.post(
            name: .timedGoalReached,
            object: nil,
            userInfo: ["sessionId": prompt.id]
        )

        // App in the background: mirror the prompt as an actionable system notification.
        if !NSApp.isActive {
            var userInfo: [String: String] = ["goalMinutes": "\(prompt.goalMinutes)"]
            if let taskUUID = prompt.taskUUID { userInfo["taskUUID"] = taskUUID }
            let content = CosmoNotificationContent(
                type: .timedGoalReached,
                title: "Time's up",
                body: "\(prompt.title) hit \(prompt.goalMinutes) min",
                sound: .celebration,
                userInfo: userInfo,
                actions: [
                    .init(id: "timed_goal_complete", title: "Mark Complete"),
                    .init(id: "timed_goal_keep_going", title: "Keep Going")
                ]
            )
            Task {
                await ProactiveNotificationService.shared.schedule(content)
            }
        }
    }

    /// Complete the task/occurrence a reached goal belongs to. Dedupes against
    /// already-completed state so prompt taps, session end, and other devices can
    /// race safely. Returns whether a completion was actually written.
    @discardableResult
    private func completeTimedGoalTask(_ context: TimedTaskGoalContext, cumulativeMinutes: Int) async -> Bool {
        let writeContext = "DeepWorkSessionEngine.timedGoalComplete(\(context.taskUUID.prefix(8)))"
        do {
            if context.isRecurring {
                guard let atom = try await atomRepository.fetch(uuid: context.taskUUID),
                      let meta = atom.metadataValue(as: TaskMetadata.self) else { return false }
                let todayKey = RecurringSeriesEngine.dayKey(for: Date())
                guard !(meta.completedOccurrences ?? []).contains(where: { $0.day == todayKey }) else { return false }
                try await RecurringSeriesEngine.shared.complete(
                    templateUUID: context.taskUUID,
                    occurrenceDay: Date(),
                    trackedMinutes: cumulativeMinutes
                )
            } else {
                var applied = false
                let result = try await atomRepository.update(uuid: context.taskUUID) { atom in
                    let meta: TaskMetadata
                    switch atom.decodedMetadata(as: TaskMetadata.self) {
                    case .absent: meta = TaskMetadata()
                    case .value(let value): meta = value
                    case .corrupt:
                        PersistenceHealth.note(.decodeFailure, context: writeContext, detail: "task metadata undecodable; refusing completion write")
                        return
                    }
                    guard meta.isCompleted != true else { return }
                    var updated = meta
                    updated.isCompleted = true
                    updated.completedAt = PlannerumFormatters.iso8601.string(from: Date())
                    guard let merged = atom.mergingTaskMetadata(updated, context: writeContext) else { return }
                    atom = merged
                    applied = true
                }
                guard applied, result != nil else { return false }
            }

            // Habit credit only after the completion actually persisted (dashboard contract).
            await CommandCenterHabitEngine.shared.recordTaskCompletion(taskUUID: context.taskUUID)
            NotificationCenter.default.post(
                name: .timedGoalTaskCompleted,
                object: nil,
                userInfo: ["taskUUID": context.taskUUID]
            )
            return true
        } catch {
            PersistenceHealth.note(.writeFailure, context: writeContext, detail: error.localizedDescription)
            return false
        }
    }

    // MARK: - Distraction Detection

    private func startDistractionDetection() {
        lastAppSwitchTime = Date()

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleAppSwitch(notification)
            }
        }
    }

    private func stopDistractionDetection() {
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
    }

    private func handleAppSwitch(_ notification: Notification) {
        guard var session = activeSession, session.state == .running else { return }

        let now = Date()

        // Grace period: ignore switches within 5 seconds of the last one
        if let lastSwitch = lastAppSwitchTime,
           now.timeIntervalSince(lastSwitch) < 5 {
            lastAppSwitchTime = now
            return
        }

        lastAppSwitchTime = now

        // Get the activated app name
        let appName: String?
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            appName = app.localizedName
        } else {
            appName = nil
        }

        // Log distraction event
        let event = ActiveDeepWorkSession.DistractionEvent(
            timestamp: now,
            fromApp: appName
        )
        session.distractionEvents.append(event)
        activeSession = session

        distractionCount = session.distractionEvents.count
        recalculateFocusScore()
    }

    // MARK: - Focus Score

    private func recalculateFocusScore() {
        guard let session = activeSession else { return }

        var score: Double = 100

        // Deduct 3 per app switch
        score -= Double(session.distractionEvents.count) * 3

        // Deduct 1 per minute of total pause time over 2 minutes
        let pauseMinutes = session.totalPausedSeconds / 60.0
        if pauseMinutes > 2 {
            score -= (pauseMinutes - 2)
        }

        focusScore = max(0, min(100, score))
    }

    // MARK: - Session Data

    private func findOutputAtoms(since startDate: Date) async -> [String] {
        let startISO = ISO8601.string(from: startDate)
        do {
            // Fetch all user-facing atoms created after session start
            let userTypes: [AtomType] = [.idea, .task, .research, .content, .connection]
            let atoms = try await atomRepository.fetchAll(types: userTypes)
            return atoms
                .filter { $0.createdAt >= startISO }
                .map { $0.uuid }
        } catch {
            print("DeepWorkSessionEngine: Failed to find output atoms - \(error)")
            return []
        }
    }

    private func saveSessionAtom(session: ActiveDeepWorkSession, metadata: DeepWorkSessionMetadata) async {
        let metadataString: String
        if let data = try? JSONEncoder().encode(metadata),
           let json = String(data: data, encoding: .utf8) {
            metadataString = json
        } else {
            metadataString = "{}"
        }

        let atom = Atom.new(
            type: .deepWorkBlock,
            title: session.taskTitle,
            body: "\(metadata.actualMinutes ?? 0) minutes of \(session.intent.displayName)",
            metadata: metadataString
        )

        do {
            try await atomRepository.create(atom)
        } catch {
            print("DeepWorkSessionEngine: Failed to save session atom - \(error)")
        }
    }

    private func updateTaskSessionTracking(taskUUID: String, actualMinutes: Int) async {
        do {
            guard var taskAtom = try await atomRepository.fetch(uuid: taskUUID) else { return }

            var taskMeta = taskAtom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
            taskMeta.totalFocusMinutes = (taskMeta.totalFocusMinutes ?? 0) + actualMinutes
            taskMeta.sessionCount = (taskMeta.sessionCount ?? 0) + 1
            taskMeta.lastSessionAt = PlannerumFormatters.iso8601.string(from: Date())

            if let data = try? JSONEncoder().encode(taskMeta),
               let json = String(data: data, encoding: .utf8) {
                taskAtom.metadata = json
                _ = try await atomRepository.update(taskAtom)
            }
        } catch {
            print("DeepWorkSessionEngine: Failed to update task session tracking - \(error)")
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when the active session crosses a time goal (task or habit).
    static let timedGoalReached = Notification.Name("timedGoalReached")
    /// Posted after a timed goal auto/prompt completion persisted — dashboards
    /// should refresh task collections.
    static let timedGoalTaskCompleted = Notification.Name("timedGoalTaskCompleted")
}

// MARK: - Session Result

/// Immutable result displayed in the summary card after a session ends
struct DeepWorkSessionResult: Sendable {
    let sessionId: String
    let taskTitle: String
    let intent: TaskIntent
    let plannedMinutes: Int
    let actualMinutes: Int
    let focusScore: Double
    let distractionCount: Int
    let outputAtomCount: Int
    let notes: String?
}
