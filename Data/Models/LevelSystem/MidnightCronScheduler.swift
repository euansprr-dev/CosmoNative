import Foundation
import Combine
import GRDB
#if os(iOS) || os(watchOS) || os(tvOS)
import BackgroundTasks
#endif

// MARK: - Cron Scheduler Configuration

/// Configuration for the midnight cron scheduler
public struct CronSchedulerConfiguration: Codable, Sendable {
    /// Hour to run cron (0-23). Default is 0 (midnight)
    public var cronHour: Int

    /// Minute to run cron (0-59). Default is 0
    public var cronMinute: Int

    /// Whether to catch up missed days on app launch
    public var catchUpOnLaunch: Bool

    /// Maximum days to catch up at once
    public var maxCatchUpDays: Int

    /// Whether to show summary overlay after cron
    public var showSummaryOverlay: Bool

    /// Delay before showing overlay (seconds)
    public var overlayDelay: TimeInterval

    public static var `default`: CronSchedulerConfiguration {
        CronSchedulerConfiguration(
            cronHour: 0,
            cronMinute: 0,
            catchUpOnLaunch: true,
            maxCatchUpDays: 7,
            showSummaryOverlay: true,
            overlayDelay: 2.0
        )
    }

    public init(
        cronHour: Int = 0,
        cronMinute: Int = 0,
        catchUpOnLaunch: Bool = true,
        maxCatchUpDays: Int = 7,
        showSummaryOverlay: Bool = true,
        overlayDelay: TimeInterval = 2.0
    ) {
        self.cronHour = cronHour
        self.cronMinute = cronMinute
        self.catchUpOnLaunch = catchUpOnLaunch
        self.maxCatchUpDays = maxCatchUpDays
        self.showSummaryOverlay = showSummaryOverlay
        self.overlayDelay = overlayDelay
    }
}

// MARK: - Cron Scheduler State

/// Current state of the cron scheduler
public struct CronSchedulerState: Sendable {
    public let lastRunDate: Date?
    public let nextScheduledRun: Date?
    public let missedDays: Int
    public let isRunning: Bool
    public let lastReport: DailyCronReport?

    public init(
        lastRunDate: Date? = nil,
        nextScheduledRun: Date? = nil,
        missedDays: Int = 0,
        isRunning: Bool = false,
        lastReport: DailyCronReport? = nil
    ) {
        self.lastRunDate = lastRunDate
        self.nextScheduledRun = nextScheduledRun
        self.missedDays = missedDays
        self.isRunning = isRunning
        self.lastReport = lastReport
    }
}

// MARK: - Cron Run Result

/// Result of a cron run triggered by the scheduler
public struct CronRunResult: Sendable {
    public let success: Bool
    public let reports: [DailyCronReport]
    public let summary: DailySummaryMetadata?
    public let error: String?
    public let shouldShowOverlay: Bool

    public init(
        success: Bool,
        reports: [DailyCronReport],
        summary: DailySummaryMetadata?,
        error: String?,
        shouldShowOverlay: Bool
    ) {
        self.success = success
        self.reports = reports
        self.summary = summary
        self.error = error
        self.shouldShowOverlay = shouldShowOverlay
    }
}

// MARK: - Midnight Cron Scheduler

/// Schedules and manages the daily cron job execution
/// Handles midnight triggers, app launch catch-up, and background execution
@MainActor
public final class MidnightCronScheduler: ObservableObject {

    // MARK: - Published State

    @Published public private(set) var state: CronSchedulerState = .init()
    @Published public var configuration: CronSchedulerConfiguration = .default

    // MARK: - Callbacks

    /// Called when cron completes and overlay should be shown
    public var onShowSummaryOverlay: ((DailySummaryMetadata) -> Void)?

    /// Called when cron run completes
    public var onCronComplete: ((CronRunResult) -> Void)?

    // MARK: - Private State

    private let cronEngine: DailyCronEngine
    private let summaryGenerator: DailySummaryGenerator
    private let notificationService: ProactiveNotificationService
    private var midnightTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // Background task identifier
    private static let backgroundTaskIdentifier = "com.cosmo.dailyCron"

    public init(
        cronEngine: DailyCronEngine? = nil,
        summaryGenerator: DailySummaryGenerator? = nil,
        notificationService: ProactiveNotificationService? = nil
    ) {
        self.cronEngine = cronEngine ?? DailyCronEngine()
        self.summaryGenerator = summaryGenerator ?? DailySummaryGenerator()
        self.notificationService = notificationService ?? ProactiveNotificationService()
    }

    // MARK: - Lifecycle

    /// Call on app launch to check and run cron if needed
    public func onAppLaunch(database: any DatabaseWriter) async {
        await refreshState(database: database)

        // Check if we need to catch up
        if configuration.catchUpOnLaunch && state.missedDays > 0 {
            await runCatchUp(database: database)
        }

        // Schedule next midnight
        scheduleMidnightTimer()

        // Register background task
        registerBackgroundTask()
    }

    /// Call when app enters background
    public func onEnterBackground() {
        scheduleBackgroundTask()
    }

    /// Call when app becomes active
    public func onBecomeActive(database: any DatabaseWriter) async {
        await refreshState(database: database)

        // Check for missed runs while in background
        if state.missedDays > 0 {
            await runCatchUp(database: database)
        }

        // Reschedule timer
        scheduleMidnightTimer()
    }

    // MARK: - Manual Run

    /// Manually trigger cron run for today
    public func runNow(database: any DatabaseWriter) async -> CronRunResult {
        state = CronSchedulerState(
            lastRunDate: state.lastRunDate,
            nextScheduledRun: state.nextScheduledRun,
            missedDays: state.missedDays,
            isRunning: true,
            lastReport: state.lastReport
        )

        do {
            let result = try await runCronForDate(Date(), database: database)
            state = CronSchedulerState(
                lastRunDate: Date(),
                nextScheduledRun: nextMidnight(),
                missedDays: 0,
                isRunning: false,
                lastReport: result.reports.last
            )
            return result
        } catch {
            let result = CronRunResult(
                success: false,
                reports: [],
                summary: nil,
                error: error.localizedDescription,
                shouldShowOverlay: false
            )
            state = CronSchedulerState(
                lastRunDate: state.lastRunDate,
                nextScheduledRun: state.nextScheduledRun,
                missedDays: state.missedDays,
                isRunning: false,
                lastReport: state.lastReport
            )
            return result
        }
    }

    // MARK: - Private Methods

    private func refreshState(database: any DatabaseWriter) async {
        do {
            let lastRun = try await database.read { db in
                try self.cronEngine.lastCronRunDate(db: db)
            }

            let missed = try await database.read { db in
                try self.cronEngine.missedCronDays(db: db)
            }

            state = CronSchedulerState(
                lastRunDate: lastRun,
                nextScheduledRun: nextMidnight(),
                missedDays: missed,
                isRunning: false,
                lastReport: nil
            )
        } catch {
            print("Failed to refresh cron state: \(error)")
        }
    }

    private func runCatchUp(database: any DatabaseWriter) async {
        guard state.missedDays > 0 else { return }

        state = CronSchedulerState(
            lastRunDate: state.lastRunDate,
            nextScheduledRun: state.nextScheduledRun,
            missedDays: state.missedDays,
            isRunning: true,
            lastReport: state.lastReport
        )

        do {
            let daysToProcess = min(state.missedDays, configuration.maxCatchUpDays)
            var allReports: [DailyCronReport] = []
            var latestSummary: DailySummaryMetadata?

            // Process each missed day
            let calendar = Calendar.current
            var processDate = state.lastRunDate ?? calendar.startOfDay(for: Date())

            for _ in 0..<daysToProcess {
                if let nextDay = calendar.date(byAdding: .day, value: 1, to: processDate) {
                    processDate = nextDay
                    if processDate <= Date() {
                        let result = try await runCronForDate(processDate, database: database)
                        allReports.append(contentsOf: result.reports)
                        if result.summary != nil {
                            latestSummary = result.summary
                        }
                    }
                }
            }

            state = CronSchedulerState(
                lastRunDate: processDate,
                nextScheduledRun: nextMidnight(),
                missedDays: max(0, state.missedDays - daysToProcess),
                isRunning: false,
                lastReport: allReports.last
            )

            // Show overlay for the latest summary
            if configuration.showSummaryOverlay, let summary = latestSummary {
                DispatchQueue.main.asyncAfter(deadline: .now() + configuration.overlayDelay) {
                    self.onShowSummaryOverlay?(summary)
                }
            }

            let result = CronRunResult(
                success: true,
                reports: allReports,
                summary: latestSummary,
                error: nil,
                shouldShowOverlay: configuration.showSummaryOverlay && latestSummary != nil
            )
            onCronComplete?(result)

        } catch {
            print("Catch-up failed: \(error)")
            state = CronSchedulerState(
                lastRunDate: state.lastRunDate,
                nextScheduledRun: state.nextScheduledRun,
                missedDays: state.missedDays,
                isRunning: false,
                lastReport: state.lastReport
            )
        }
    }

    private func runCronForDate(_ date: Date, database: any DatabaseWriter) async throws -> CronRunResult {
        // Get previous level state (for comparison)
        let previousState = try await database.read { db in
            try CosmoLevelState.fetchOne(db)
        }

        // Run the cron
        let report = try await database.write { db in
            try self.cronEngine.runDailyCron(db: db, forDate: date)
        }

        // Get current level state
        let currentState = try await database.read { db in
            try CosmoLevelState.fetchOne(db)
        }

        // Generate summary if we have both states
        var summary: DailySummaryMetadata?
        if let prev = previousState, let curr = currentState {
            let summaryAtom = try await database.write { db in
                try self.summaryGenerator.generateDailySummary(
                    db: db,
                    for: date,
                    previousLevelState: prev,
                    currentLevelState: curr,
                    cronReport: report
                )
            }

            // Parse summary metadata
            if let metadataString = summaryAtom.metadata,
               let data = metadataString.data(using: .utf8) {
                summary = try? JSONDecoder().decode(DailySummaryMetadata.self, from: data)
            }

            // Save the summary atom
            try await database.write { db in
                var insertingAtom = summaryAtom
                try insertingAtom.insert(db)
                insertingAtom.id = db.lastInsertedRowID
            }

            // Schedule morning notification with summary
            if let summary = summary {
                await notificationService.scheduleMorningSummary(summary: summary)
            }
        }

        return CronRunResult(
            success: report.allSucceeded,
            reports: [report],
            summary: summary,
            error: nil,
            shouldShowOverlay: configuration.showSummaryOverlay && summary != nil
        )
    }

    // MARK: - Timer Management

    private func scheduleMidnightTimer() {
        // Cancel existing timer
        midnightTimer?.invalidate()

        // Calculate time until next cron
        let midnight = nextMidnight()
        let interval = midnight.timeIntervalSinceNow

        guard interval > 0 else {
            // Already past midnight, run immediately
            return
        }

        midnightTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                // We'd need a database reference here - in practice, this would be injected
                // For now, just update state
                self?.state = CronSchedulerState(
                    lastRunDate: self?.state.lastRunDate,
                    nextScheduledRun: self?.nextMidnight(),
                    missedDays: (self?.state.missedDays ?? 0) + 1,
                    isRunning: false,
                    lastReport: self?.state.lastReport
                )

                // Reschedule for next midnight
                self?.scheduleMidnightTimer()
            }
        }
    }

    private func nextMidnight() -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = configuration.cronHour
        components.minute = configuration.cronMinute

        var targetTime = calendar.date(from: components)!

        // If we've passed today's target time, schedule for tomorrow
        if targetTime <= Date() {
            targetTime = calendar.date(byAdding: .day, value: 1, to: targetTime)!
        }

        return targetTime
    }

    // MARK: - Background Tasks

    #if os(iOS) || os(watchOS) || os(tvOS)
    private func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundTaskIdentifier,
            using: nil
        ) { task in
            self.handleBackgroundTask(task as! BGProcessingTask)
        }
    }

    private func scheduleBackgroundTask() {
        let request = BGProcessingTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.earliestBeginDate = nextMidnight()
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Failed to schedule background task: \(error)")
        }
    }

    private func handleBackgroundTask(_ task: BGProcessingTask) {
        // Set up expiration handler
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        // In a real implementation, we'd run the cron here
        // For now, just mark the task complete
        task.setTaskCompleted(success: true)

        // Schedule the next occurrence
        scheduleBackgroundTask()
    }
    #else
    private func registerBackgroundTask() {
        // Background tasks not available on macOS
    }

    private func scheduleBackgroundTask() {
        // Background tasks not available on macOS
    }
    #endif
}
