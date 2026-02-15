//
//  ActiveSessionTimerManager.swift
//  CosmoOS
//
//  Manages active focus sessions with timer state, quest progress,
//  and XP awarding. Integrates with DailyQuestEngine and XPCalculationEngine.
//

import Foundation
import Combine
import AppKit

// MARK: - Session State

/// Current state of a focus session
public enum SessionState: String, Codable, Sendable {
    case idle           // No active session
    case running        // Timer actively counting
    case paused         // Timer paused
    case completing     // Session ending, processing results
    case completed      // Session finished, XP awarded
}

// MARK: - Session Type

/// Types of focus sessions
public enum SessionType: String, Codable, CaseIterable, Sendable {
    case deepWork = "deepWork"
    case writing = "writing"
    case exercise = "exercise"
    case meditation = "meditation"
    case creative = "creative"
    case training = "training"

    public var displayName: String {
        switch self {
        case .deepWork: return "Deep Work"
        case .writing: return "Writing"
        case .exercise: return "Exercise"
        case .meditation: return "Meditation"
        case .creative: return "Creative"
        case .training: return "Training"
        }
    }

    public var iconName: String {
        switch self {
        case .deepWork: return "brain.head.profile"
        case .writing: return "pencil"
        case .exercise: return "figure.run"
        case .meditation: return "leaf"
        case .creative: return "paintbrush"
        case .training: return "book"
        }
    }

    public var dimension: String {
        switch self {
        case .deepWork: return "cognitive"
        case .writing: return "cognitive"
        case .exercise: return "physiological"
        case .meditation: return "reflection"
        case .creative: return "creative"
        case .training: return "knowledge"
        }
    }

    public var baseXPPerMinute: Double {
        switch self {
        case .deepWork: return 1.0
        case .writing: return 0.8
        case .exercise: return 0.7
        case .meditation: return 0.5
        case .creative: return 0.9
        case .training: return 0.75
        }
    }
}

// MARK: - Active Session

/// Represents an active focus session
public struct ActiveSession: Codable, Sendable {
    public let id: String
    public let taskId: String?
    public let taskTitle: String
    public let sessionType: SessionType
    public let targetMinutes: Int
    public let startedAt: Date
    public var pausedAt: Date?
    public var totalPausedSeconds: TimeInterval
    public var state: SessionState

    public init(
        id: String = UUID().uuidString,
        taskId: String?,
        taskTitle: String,
        sessionType: SessionType,
        targetMinutes: Int,
        startedAt: Date = Date()
    ) {
        self.id = id
        self.taskId = taskId
        self.taskTitle = taskTitle
        self.sessionType = sessionType
        self.targetMinutes = targetMinutes
        self.startedAt = startedAt
        self.pausedAt = nil
        self.totalPausedSeconds = 0
        self.state = .running
    }

    /// Elapsed active time (excluding pauses)
    public var elapsedActiveSeconds: TimeInterval {
        guard state != .idle else { return 0 }

        let now = Date()
        var elapsed = now.timeIntervalSince(startedAt) - totalPausedSeconds

        // If currently paused, subtract current pause duration
        if let pausedAt = pausedAt {
            elapsed -= now.timeIntervalSince(pausedAt)
        }

        return max(0, elapsed)
    }

    /// Elapsed active minutes
    public var elapsedActiveMinutes: Int {
        Int(elapsedActiveSeconds / 60)
    }

    /// Remaining seconds until target
    public var remainingSeconds: TimeInterval {
        let targetSeconds = TimeInterval(targetMinutes * 60)
        return max(0, targetSeconds - elapsedActiveSeconds)
    }

    /// Progress towards target (0-1)
    public var progress: Double {
        guard targetMinutes > 0 else { return 0 }
        return min(1.0, elapsedActiveSeconds / TimeInterval(targetMinutes * 60))
    }

    /// Whether target has been reached
    public var hasReachedTarget: Bool {
        elapsedActiveMinutes >= targetMinutes
    }
}

// MARK: - Session Result

/// Result of a completed session
public struct SessionResult: Sendable {
    public let session: ActiveSession
    public let completedAt: Date
    public let actualMinutes: Int
    public let xpAwarded: Int
    public let questsProgressed: [String]
    public let streakContributed: Bool

    public init(
        session: ActiveSession,
        completedAt: Date,
        actualMinutes: Int,
        xpAwarded: Int,
        questsProgressed: [String],
        streakContributed: Bool
    ) {
        self.session = session
        self.completedAt = completedAt
        self.actualMinutes = actualMinutes
        self.xpAwarded = xpAwarded
        self.questsProgressed = questsProgressed
        self.streakContributed = streakContributed
    }
}

// MARK: - ActiveSessionTimerManager

/// Manages active focus sessions with timer, quest progress, and XP
@MainActor
public final class ActiveSessionTimerManager: ObservableObject {

    // MARK: - Singleton

    public static let shared = ActiveSessionTimerManager()

    // MARK: - Published State

    @Published public private(set) var currentSession: ActiveSession?
    @Published public private(set) var state: SessionState = .idle
    @Published public private(set) var elapsedSeconds: TimeInterval = 0
    @Published public private(set) var lastResult: SessionResult?

    // MARK: - Dependencies

    private let questEngine: DailyQuestEngine
    private let atomRepository: AtomRepository

    // MARK: - Timer

    private var timer: Timer?
    private var autoSaveTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Persistence Keys

    private enum PersistenceKeys {
        static let activeSession = "com.cosmo.activeSession"
    }

    // MARK: - Initialization

    init(
        questEngine: DailyQuestEngine = DailyQuestEngine(),
        atomRepository: AtomRepository? = nil
    ) {
        self.questEngine = questEngine
        self.atomRepository = atomRepository ?? AtomRepository.shared

        // Restore session if app was backgrounded
        restoreSession()

        // Listen for app lifecycle
        setupAppLifecycleObservers()
    }

    deinit {
        timer?.invalidate()
        autoSaveTimer?.invalidate()
    }

    // MARK: - Session Lifecycle

    /// Start a new focus session
    public func startSession(
        taskId: String?,
        taskTitle: String,
        sessionType: SessionType,
        targetMinutes: Int
    ) {
        // End any existing session
        if currentSession != nil {
            endSession(completed: false)
        }

        let session = ActiveSession(
            taskId: taskId,
            taskTitle: taskTitle,
            sessionType: sessionType,
            targetMinutes: targetMinutes
        )

        currentSession = session
        state = .running
        elapsedSeconds = 0

        startTimer()
        startAutoSave()
        persistSession()

        // Post notification
        NotificationCenter.default.post(
            name: .focusSessionStarted,
            object: nil,
            userInfo: [
                "sessionId": session.id,
                "taskId": taskId ?? "",
                "sessionType": sessionType.rawValue
            ]
        )
    }

    /// Pause the current session
    public func pauseSession() {
        guard var session = currentSession, session.state == .running else { return }

        session.pausedAt = Date()
        session.state = .paused
        currentSession = session
        state = .paused

        stopTimer()
        persistSession()

        NotificationCenter.default.post(name: .focusSessionPaused, object: nil)
    }

    /// Resume the current session
    public func resumeSession() {
        guard var session = currentSession,
              session.state == .paused,
              let pausedAt = session.pausedAt else { return }

        // Add pause duration to total
        session.totalPausedSeconds += Date().timeIntervalSince(pausedAt)
        session.pausedAt = nil
        session.state = .running
        currentSession = session
        state = .running

        startTimer()
        persistSession()

        NotificationCenter.default.post(name: .focusSessionResumed, object: nil)
    }

    /// End the current session
    public func endSession(completed: Bool = true) {
        guard let session = currentSession else { return }

        state = .completing

        Task {
            let result = await processSessionCompletion(session: session, userCompleted: completed)
            lastResult = result

            // Clear session
            currentSession = nil
            state = .idle
            elapsedSeconds = 0

            stopTimer()
            stopAutoSave()
            clearPersistedSession()

            // Post completion notification
            NotificationCenter.default.post(
                name: .focusSessionCompleted,
                object: nil,
                userInfo: [
                    "sessionId": session.id,
                    "xpAwarded": result.xpAwarded,
                    "actualMinutes": result.actualMinutes,
                    "completed": completed
                ]
            )
        }
    }

    /// Cancel the current session without awarding XP
    public func cancelSession() {
        currentSession = nil
        state = .idle
        elapsedSeconds = 0

        stopTimer()
        stopAutoSave()
        clearPersistedSession()

        NotificationCenter.default.post(name: .focusSessionCancelled, object: nil)
    }

    // MARK: - Session Processing

    private func processSessionCompletion(session: ActiveSession, userCompleted: Bool) async -> SessionResult {
        let completedAt = Date()
        let actualMinutes = session.elapsedActiveMinutes

        // Calculate XP
        var xpAmount = calculateXP(for: session, actualMinutes: actualMinutes)

        // Apply completion bonus if user completed the full target
        if userCompleted && session.hasReachedTarget {
            xpAmount = Int(Double(xpAmount) * 1.25) // 25% completion bonus
        }

        // Update quest progress
        var questsProgressed: [String] = []
        // Would integrate with DailyQuestEngine here

        // Check streak contribution
        let streakContributed = actualMinutes >= 25 // 25min minimum for streak

        // Create deepWorkBlock atom
        await createSessionAtom(session: session, actualMinutes: actualMinutes, xpAmount: xpAmount)

        // Award XP
        await awardXP(amount: xpAmount, source: session.sessionType, sessionId: session.id)

        return SessionResult(
            session: session,
            completedAt: completedAt,
            actualMinutes: actualMinutes,
            xpAwarded: xpAmount,
            questsProgressed: questsProgressed,
            streakContributed: streakContributed
        )
    }

    private func calculateXP(for session: ActiveSession, actualMinutes: Int) -> Int {
        let baseXP = Double(actualMinutes) * session.sessionType.baseXPPerMinute

        // Diminishing returns for very long sessions
        let effectiveMinutes = min(Double(actualMinutes), 120) // Cap at 2 hours
        let adjustedXP = baseXP * (1.0 - (effectiveMinutes / 400.0)) // Slight reduction for longer sessions

        return max(1, Int(adjustedXP))
    }

    private func createSessionAtom(session: ActiveSession, actualMinutes: Int, xpAmount: Int) async {
        let metadata: [String: Any] = [
            "sessionType": session.sessionType.rawValue,
            "targetMinutes": session.targetMinutes,
            "durationMinutes": actualMinutes,
            "xpAwarded": xpAmount,
            "taskId": session.taskId ?? "",
            "dimension": session.sessionType.dimension
        ]

        let metadataJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: metadata),
           let json = String(data: data, encoding: .utf8) {
            metadataJSON = json
        } else {
            metadataJSON = "{}"
        }

        let atom = Atom.new(
            type: .deepWorkBlock,
            title: session.taskTitle,
            body: "\(actualMinutes) minutes of \(session.sessionType.displayName)",
            metadata: metadataJSON
        )

        do {
            try await atomRepository.create(atom)
        } catch {
            print("ActiveSessionTimerManager: Failed to save session atom - \(error)")
        }
    }

    private func awardXP(amount: Int, source: SessionType, sessionId: String) async {
        let metadata: [String: Any] = [
            "xpAmount": amount,
            "source": "focusSession",
            "sessionType": source.rawValue,
            "sessionId": sessionId,
            "dimension": source.dimension
        ]

        let metadataJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: metadata),
           let json = String(data: data, encoding: .utf8) {
            metadataJSON = json
        } else {
            metadataJSON = "{}"
        }

        let atom = Atom.new(
            type: .xpEvent,
            title: "+\(amount) XP",
            body: "Focus session: \(source.displayName)",
            metadata: metadataJSON
        )

        do {
            try await atomRepository.create(atom)

            // Post XP notification
            NotificationCenter.default.post(
                name: .xpAwarded,
                object: nil,
                userInfo: [
                    "amount": amount,
                    "source": "focusSession",
                    "dimension": source.dimension
                ]
            )
        } catch {
            print("ActiveSessionTimerManager: Failed to save XP event - \(error)")
        }
    }

    // MARK: - Timer Management

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
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
        guard let session = currentSession, session.state == .running else { return }

        elapsedSeconds = session.elapsedActiveSeconds

        // Check if target reached
        if session.hasReachedTarget {
            // Could trigger notification or auto-complete
            NotificationCenter.default.post(name: .focusSessionTargetReached, object: nil)
        }
    }

    // MARK: - Auto-Save

    private func startAutoSave() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.persistSession()
            }
        }
    }

    private func stopAutoSave() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
    }

    // MARK: - Persistence

    private func persistSession() {
        guard let session = currentSession else {
            clearPersistedSession()
            return
        }

        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: PersistenceKeys.activeSession)
        }
    }

    private func restoreSession() {
        guard let data = UserDefaults.standard.data(forKey: PersistenceKeys.activeSession),
              let session = try? JSONDecoder().decode(ActiveSession.self, from: data) else {
            return
        }

        // Check if session is still valid (not too old)
        let maxAge: TimeInterval = 4 * 60 * 60 // 4 hours
        if Date().timeIntervalSince(session.startedAt) > maxAge {
            clearPersistedSession()
            return
        }

        currentSession = session
        state = session.state
        elapsedSeconds = session.elapsedActiveSeconds

        if session.state == .running {
            startTimer()
            startAutoSave()
        }
    }

    private func clearPersistedSession() {
        UserDefaults.standard.removeObject(forKey: PersistenceKeys.activeSession)
    }

    // MARK: - App Lifecycle

    private func setupAppLifecycleObservers() {
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.persistSession()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                // Refresh elapsed time when app becomes active
                if let session = self?.currentSession {
                    self?.elapsedSeconds = session.elapsedActiveSeconds
                }
            }
            .store(in: &cancellables)
    }
}

// MARK: - Notification Names
// Note: focusSessionStarted, focusSessionPaused defined in ActiveFocusBar.swift

public extension Notification.Name {
    static let focusSessionResumed = Notification.Name("com.cosmo.focusSessionResumed")
    static let focusSessionCancelled = Notification.Name("com.cosmo.focusSessionCancelled")
    static let focusSessionTargetReached = Notification.Name("com.cosmo.focusSessionTargetReached")
}
