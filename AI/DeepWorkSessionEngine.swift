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

// MARK: - Deep Work Session (Internal Model)

/// Represents a live deep work session with distraction tracking (engine-internal model)
struct ActiveDeepWorkSession: Codable, Sendable {
    let id: String
    let taskUUID: String?
    let taskTitle: String
    let intent: TaskIntent
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
        plannedMinutes: Int
    ) {
        self.id = UUID().uuidString
        self.taskUUID = taskUUID
        self.taskTitle = taskTitle
        self.intent = intent
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
        max(0, TimeInterval(plannedMinutes * 60) - elapsedActiveSeconds)
    }

    var progress: Double {
        guard plannedMinutes > 0 else { return 0 }
        return min(1.0, elapsedActiveSeconds / TimeInterval(plannedMinutes * 60))
    }
}

// MARK: - DeepWorkSessionEngine

@MainActor
class DeepWorkSessionEngine: ObservableObject {

    // MARK: - Published State

    @Published var activeSession: ActiveDeepWorkSession?
    @Published var focusScore: Double = 100
    @Published var distractionCount: Int = 0
    @Published var elapsedSeconds: Int = 0
    @Published var isTimerRunning: Bool = false
    @Published var showExtensionPrompt: Bool = false
    @Published var sessionResult: DeepWorkSessionResult?

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
            plannedMinutes: plannedMinutes
        )

        activeSession = session
        focusScore = 100
        distractionCount = 0
        elapsedSeconds = 0
        isTimerRunning = true
        showExtensionPrompt = false
        sessionResult = nil

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

        // Find atoms created during this session
        let outputAtomUUIDs = await findOutputAtoms(since: session.startedAt)

        // Calculate XP: base 15 + (focusScore/100 * plannedMinutes/30 * 10)
        let xpEarned = 15 + Int((focusScore / 100.0) * (Double(session.plannedMinutes) / 30.0) * 10.0)

        // Create session metadata
        let sessionMetadata = DeepWorkSessionMetadata(
            taskUUID: session.taskUUID,
            startedAt: ISO8601DateFormatter().string(from: session.startedAt),
            endedAt: ISO8601DateFormatter().string(from: Date()),
            plannedMinutes: session.plannedMinutes,
            actualMinutes: actualMinutes,
            focusScore: focusScore,
            distractionCount: distractionCount,
            intent: session.intent.rawValue,
            outputAtomUUIDs: outputAtomUUIDs,
            xpEarned: xpEarned,
            notes: notes
        )

        // Save session atom
        await saveSessionAtom(session: session, metadata: sessionMetadata)

        // Update parent task metadata
        if let taskUUID = session.taskUUID {
            await updateTaskSessionTracking(taskUUID: taskUUID, actualMinutes: actualMinutes)
        }

        // Award XP with dimension routing
        let allocations = await awardXP(amount: xpEarned, session: session)

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
            xpEarned: xpEarned,
            notes: notes,
            dimensionAllocations: allocations
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
                "xpEarned": xpEarned,
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
        guard let session = activeSession, session.state == .running else { return }

        elapsedSeconds = Int(session.elapsedActiveSeconds)

        // Check if target reached
        if session.remainingSeconds <= 0 && !showExtensionPrompt {
            showExtensionPrompt = true
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
        let startISO = ISO8601DateFormatter().string(from: startDate)
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
            taskMeta.lastSessionAt = ISO8601DateFormatter().string(from: Date())

            if let data = try? JSONEncoder().encode(taskMeta),
               let json = String(data: data, encoding: .utf8) {
                taskAtom.metadata = json
                _ = try await atomRepository.update(taskAtom)
            }
        } catch {
            print("DeepWorkSessionEngine: Failed to update task session tracking - \(error)")
        }
    }

    private func awardXP(amount: Int, session: ActiveDeepWorkSession) async -> [DimensionXPAllocation] {
        let allocations = DimensionXPRouter.routeXP(
            intent: session.intent,
            baseXP: amount,
            focusScore: focusScore
        )

        for alloc in allocations {
            await awardDimensionXP(amount: alloc.xp, dimension: alloc.dimension, session: session)
        }

        return allocations
    }

    private func awardDimensionXP(amount: Int, dimension: String, session: ActiveDeepWorkSession) async {
        let metadata: [String: Any] = [
            "xpAmount": amount,
            "source": "deepWorkSession",
            "sessionId": session.id,
            "intent": session.intent.rawValue,
            "dimension": dimension
        ]

        let metadataString: String
        if let data = try? JSONSerialization.data(withJSONObject: metadata),
           let json = String(data: data, encoding: .utf8) {
            metadataString = json
        } else {
            metadataString = "{}"
        }

        let atom = Atom.new(
            type: .xpEvent,
            title: "+\(amount) XP",
            body: "Deep work session: \(session.taskTitle)",
            metadata: metadataString
        )

        do {
            try await atomRepository.create(atom)

            NotificationCenter.default.post(
                name: .xpAwarded,
                object: nil,
                userInfo: [
                    "amount": amount,
                    "source": "deepWorkSession",
                    "dimension": dimension
                ]
            )
        } catch {
            print("DeepWorkSessionEngine: Failed to award XP - \(error)")
        }
    }

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
    let xpEarned: Int
    let notes: String?
    let dimensionAllocations: [DimensionXPAllocation]
}
