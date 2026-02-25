// CosmoOS/Agent/Proactive/AgentProactiveScheduler.swift
// Timer-based scheduler for proactive agent messages

import Foundation
import Combine

@MainActor
class AgentProactiveScheduler: ObservableObject {
    static let shared = AgentProactiveScheduler()

    // MARK: - Published Settings (UserDefaults-backed)

    @Published var morningBriefEnabled: Bool {
        didSet { UserDefaults.standard.set(morningBriefEnabled, forKey: "agent_proactive_morning_enabled") }
    }
    @Published var morningBriefHour: Int {
        didSet {
            UserDefaults.standard.set(morningBriefHour, forKey: "agent_proactive_morning_hour")
            rescheduleAll()
        }
    }
    @Published var morningBriefMinute: Int {
        didSet {
            UserDefaults.standard.set(morningBriefMinute, forKey: "agent_proactive_morning_minute")
            rescheduleAll()
        }
    }
    @Published var weeklyReviewEnabled: Bool {
        didSet { UserDefaults.standard.set(weeklyReviewEnabled, forKey: "agent_proactive_weekly_enabled") }
    }
    @Published var weeklyReviewDay: Int { // 1=Sunday, 7=Saturday
        didSet {
            UserDefaults.standard.set(weeklyReviewDay, forKey: "agent_proactive_weekly_day")
            rescheduleAll()
        }
    }
    @Published var weeklyReviewHour: Int {
        didSet {
            UserDefaults.standard.set(weeklyReviewHour, forKey: "agent_proactive_weekly_hour")
            rescheduleAll()
        }
    }
    @Published var streakAlertsEnabled: Bool {
        didSet { UserDefaults.standard.set(streakAlertsEnabled, forKey: "agent_proactive_streak_enabled") }
    }
    @Published var dndEnabled: Bool {
        didSet { UserDefaults.standard.set(dndEnabled, forKey: "agent_proactive_dnd_enabled") }
    }

    @Published var intelligentAlertsEnabled: Bool {
        didSet { UserDefaults.standard.set(intelligentAlertsEnabled, forKey: "agent_proactive_intelligent_enabled") }
    }

    @Published var heartbeatEnabled: Bool {
        didSet {
            UserDefaults.standard.set(heartbeatEnabled, forKey: "agent_proactive_heartbeat_enabled")
            rescheduleAll()
        }
    }
    @Published var heartbeatIntervalMinutes: Int {
        didSet {
            UserDefaults.standard.set(heartbeatIntervalMinutes, forKey: "agent_proactive_heartbeat_interval")
            rescheduleAll()
        }
    }

    private var morningTimer: Timer?
    private var weeklyTimer: Timer?
    private var streakTimer: Timer?
    private var intelligentAlertTimer: Timer?
    private var standingInstructionTimer: Timer?
    private var nightlyConsolidationTimer: Timer?
    private var performanceCalibrationTimer: Timer?
    private var heartbeatTimer: Timer?
    private var lastHeartbeatAt: Date?
    private var deferredMessages: [(chatId: String, tag: String)] = []

    private init() {
        morningBriefEnabled = UserDefaults.standard.bool(forKey: "agent_proactive_morning_enabled")
        morningBriefHour = UserDefaults.standard.object(forKey: "agent_proactive_morning_hour") as? Int ?? 8
        morningBriefMinute = UserDefaults.standard.object(forKey: "agent_proactive_morning_minute") as? Int ?? 0
        weeklyReviewEnabled = UserDefaults.standard.bool(forKey: "agent_proactive_weekly_enabled")
        weeklyReviewDay = UserDefaults.standard.object(forKey: "agent_proactive_weekly_day") as? Int ?? 1
        weeklyReviewHour = UserDefaults.standard.object(forKey: "agent_proactive_weekly_hour") as? Int ?? 18
        streakAlertsEnabled = UserDefaults.standard.bool(forKey: "agent_proactive_streak_enabled")
        dndEnabled = UserDefaults.standard.object(forKey: "agent_proactive_dnd_enabled") as? Bool ?? true
        intelligentAlertsEnabled = UserDefaults.standard.object(forKey: "agent_proactive_intelligent_enabled") as? Bool ?? true
        heartbeatEnabled = UserDefaults.standard.bool(forKey: "agent_proactive_heartbeat_enabled")
        heartbeatIntervalMinutes = UserDefaults.standard.object(forKey: "agent_proactive_heartbeat_interval") as? Int ?? 120
    }

    // MARK: - Schedule All

    func scheduleAll() {
        scheduleMorningBrief()
        scheduleWeeklyReview()
        scheduleStreakCheck()
        scheduleIntelligentAlerts()
        scheduleStandingInstructions()
        scheduleNightlyConsolidation()
        schedulePerformanceCalibration()
        scheduleHeartbeat()
    }

    func rescheduleAll() {
        morningTimer?.invalidate()
        weeklyTimer?.invalidate()
        streakTimer?.invalidate()
        intelligentAlertTimer?.invalidate()
        standingInstructionTimer?.invalidate()
        nightlyConsolidationTimer?.invalidate()
        performanceCalibrationTimer?.invalidate()
        heartbeatTimer?.invalidate()
        scheduleAll()
    }

    // MARK: - Morning Brief

    private func scheduleMorningBrief() {
        guard morningBriefEnabled else { return }

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = morningBriefHour
        components.minute = morningBriefMinute

        var nextFire = calendar.date(from: components) ?? Date()
        if nextFire <= Date() {
            nextFire = calendar.date(byAdding: .day, value: 1, to: nextFire) ?? Date()
        }

        let interval = nextFire.timeIntervalSinceNow

        morningTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.fireMorningBrief()
                // Schedule next day
                self?.scheduleMorningBrief()
            }
        }
    }

    private func fireMorningBrief() async {
        guard let chatId = await resolveChatId() else {
            print("[ProactiveScheduler] Morning brief skipped: no activeChatId available")
            logDeliveryAttempt(type: "morning_brief", success: false)
            return
        }

        // Check DND — defer if active
        if dndEnabled && isInDNDMode() {
            deferredMessages.append((chatId: chatId, tag: "morning"))
            return
        }

        let brief = await AgentBriefGenerator.shared.generateMorningBrief()
        await TelegramBridgeService.shared.sendLongMessage(chatId: chatId, text: brief)
        logDeliveryAttempt(type: "morning_brief", success: true)
    }

    // MARK: - Weekly Review

    private func scheduleWeeklyReview() {
        guard weeklyReviewEnabled else { return }

        let calendar = Calendar.current
        var components = DateComponents()
        components.weekday = weeklyReviewDay
        components.hour = weeklyReviewHour
        components.minute = 0

        guard let nextFire = calendar.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime) else { return }

        let interval = nextFire.timeIntervalSinceNow

        weeklyTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.fireWeeklyReview()
                self?.scheduleWeeklyReview()
            }
        }
    }

    private func fireWeeklyReview() async {
        guard let chatId = await resolveChatId() else {
            print("[ProactiveScheduler] Weekly review skipped: no activeChatId available")
            logDeliveryAttempt(type: "weekly_review", success: false)
            return
        }

        if dndEnabled && isInDNDMode() {
            deferredMessages.append((chatId: chatId, tag: "weekly"))
            return
        }

        // Use WeeklyStrategyReview for richer analysis with performance data
        let review = await WeeklyStrategyReview().generate()
        await TelegramBridgeService.shared.sendLongMessage(chatId: chatId, text: review)
        logDeliveryAttempt(type: "weekly_review", success: true)
    }

    // MARK: - Streak Check

    private func scheduleStreakCheck() {
        guard streakAlertsEnabled else { return }

        // Check every hour for at-risk streaks
        streakTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkStreaks()
            }
        }
    }

    private func checkStreaks() async {
        guard let chatId = await resolveChatId() else { return }

        // Query quest atoms for active streaks
        let snapshots = (try? await AtomRepository.shared.fetchAll(type: .dimensionSnapshot)) ?? []
        guard let latestSnapshot = snapshots.first else { return }

        // Parse streak data from the latest snapshot
        guard let structured = latestSnapshot.structured,
              let data = structured.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let quests = json["quests"] as? [[String: Any]] else { return }

        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: Date())

        // Only alert in the evening (after 6 PM) for incomplete streaks
        guard currentHour >= 18 else { return }

        for quest in quests {
            guard let title = quest["title"] as? String,
                  let streak = quest["streak"] as? Int,
                  streak > 0,
                  let completedToday = quest["completedToday"] as? Bool,
                  !completedToday else { continue }

            let alert = AgentBriefGenerator.shared.generateStreakAlert(questTitle: title, currentStreak: streak)
            await TelegramBridgeService.shared.sendMessage(chatId: chatId, text: alert)
        }
    }

    // MARK: - Intelligent Alerts

    private func scheduleIntelligentAlerts() {
        guard intelligentAlertsEnabled else { return }

        // Check every 2 hours for pattern discoveries, performance alerts, etc.
        intelligentAlertTimer = Timer.scheduledTimer(withTimeInterval: 7200, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.fireIntelligentAlerts()
            }
        }
    }

    private func fireIntelligentAlerts() async {
        guard let chatId = await resolveChatId() else { return }

        if dndEnabled && isInDNDMode() {
            return // Don't send intelligent alerts during focus sessions
        }

        let alerts = await IntelligentAlertEngine.shared.evaluateAll()
        for alert in alerts.prefix(2) { // Max 2 alerts per cycle to avoid spam
            await TelegramBridgeService.shared.sendLongMessage(chatId: chatId, text: alert)
            logDeliveryAttempt(type: "intelligent_alert", success: true)
        }
    }

    // MARK: - Standing Instructions

    private func scheduleStandingInstructions() {
        // Check every 5 minutes for due standing instructions
        standingInstructionTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.fireStandingInstructions()
            }
        }
        // Also fire immediately on schedule to catch any due instructions
        Task { @MainActor in
            await fireStandingInstructions()
        }
    }

    private func fireStandingInstructions() async {
        if dndEnabled && isInDNDMode() {
            return // Don't execute standing instructions during focus sessions
        }
        await StandingInstructionEngine.shared.checkAndExecuteDue()
    }

    // MARK: - Nightly Lesson Consolidation

    /// Schedule nightly consolidation of writing lessons at 3 AM.
    /// Prunes low-confidence lessons, merges duplicates, and logs results.
    private func scheduleNightlyConsolidation() {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 3
        components.minute = 0

        var nextFire = calendar.date(from: components) ?? Date()
        if nextFire <= Date() {
            nextFire = calendar.date(byAdding: .day, value: 1, to: nextFire) ?? Date()
        }

        let interval = nextFire.timeIntervalSinceNow

        nightlyConsolidationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.fireNightlyConsolidation()
                self?.scheduleNightlyConsolidation()
            }
        }
    }

    private func fireNightlyConsolidation() async {
        print("[ProactiveScheduler] Running nightly lesson consolidation")

        // Load all lessons including low-confidence ones
        let allLessons = await LessonExtractor.shared.loadLessons(clientUUID: nil, minConfidence: 0.0)

        var pruned = 0
        for lesson in allLessons {
            // Prune lessons with confidence below 0.1
            if lesson.confidence < 0.1 {
                await LessonExtractor.shared.updateConfidence(lessonID: lesson.id, confirmed: false)
                pruned += 1
                continue
            }

            // Decay stale lessons that haven't been confirmed in 30+ days
            let daysSinceConfirmed = Calendar.current.dateComponents(
                [.day], from: lesson.lastConfirmedAt, to: Date()
            ).day ?? 0
            if daysSinceConfirmed > 30 && lesson.confidence > 0.3 {
                await LessonExtractor.shared.updateConfidence(lessonID: lesson.id, confirmed: false)
            }
        }

        print("[ProactiveScheduler] Consolidation complete: \(allLessons.count) lessons reviewed, \(pruned) pruned")
        logDeliveryAttempt(type: "nightly_consolidation", success: true)
    }

    // MARK: - Performance Calibration

    /// Schedule periodic performance calibration — runs every 6 hours to match
    /// synced social metrics against content scorecard predictions.
    private func schedulePerformanceCalibration() {
        performanceCalibrationTimer = Timer.scheduledTimer(withTimeInterval: 21600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.firePerformanceCalibration()
            }
        }
    }

    private func firePerformanceCalibration() async {
        let syncService = SocialSyncService.shared
        let recentPosts = syncService.allRecentPosts

        // Match synced posts to published content atoms by caption/title similarity
        for post in recentPosts.prefix(10) {
            guard let caption = post.caption, !caption.isEmpty else { continue }

            // Search for matching content atoms
            do {
                let results = try await HybridSearchEngine.shared.search(
                    query: String(caption.prefix(100)),
                    limit: 3
                )

                // Find a content atom that matches
                guard let match = results.first(where: { $0.entityType == .content }),
                      let uuid = match.entityUUID, let contentUUID = UUID(uuidString: uuid) else {
                    continue
                }

                // Calibrate scorecard from actual engagement
                await ContentScorecardEngine().calibrateFromPerformance(
                    contentUUID: contentUUID,
                    actualEngagement: [
                        "views": Double(post.views),
                        "likes": Double(post.likes),
                        "comments": Double(post.comments),
                        "shares": Double(post.shares),
                        "saves": Double(post.saves)
                    ]
                )
            } catch {
                print("[ProactiveScheduler] Performance calibration search failed: \(error.localizedDescription)")
            }
        }

        logDeliveryAttempt(type: "performance_calibration", success: true)
    }

    // MARK: - Heartbeat Daemon

    private func scheduleHeartbeat() {
        guard heartbeatEnabled else { return }

        let intervalSeconds = TimeInterval(heartbeatIntervalMinutes) * 60.0
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.fireHeartbeat()
            }
        }
    }

    private func fireHeartbeat() async {
        guard let chatId = await resolveChatId() else { return }

        // Skip during DND / deep work sessions
        if dndEnabled && isInDNDMode() { return }

        // Evaluate whether there's anything noteworthy
        guard let pulse = await evaluateHeartbeatPulse() else {
            // Nothing noteworthy — stay silent
            print("[Heartbeat] Silent — nothing noteworthy")
            lastHeartbeatAt = Date()
            return
        }

        await TelegramBridgeService.shared.sendLongMessage(chatId: chatId, text: pulse)
        lastHeartbeatAt = Date()
        logDeliveryAttempt(type: "heartbeat", success: true)
    }

    /// Evaluate noteworthy events since last heartbeat. Returns nil if nothing to report (silent).
    private func evaluateHeartbeatPulse() async -> String? {
        let since = lastHeartbeatAt ?? Date().addingTimeInterval(-Double(heartbeatIntervalMinutes) * 60.0)
        let isoFormatter = ISO8601DateFormatter()
        let sinceStr = isoFormatter.string(from: since)
        var findings: [String] = []

        // 1. Count new swipes since last heartbeat
        let allSwipes = (try? await AtomRepository.shared.fetchAll(type: .research)) ?? []
        let newSwipes = allSwipes.filter { atom in
            let meta = atom.metadataDict ?? [:]
            guard meta["subtype"] as? String == "swipe_file" else { return false }
            return atom.createdAt > sinceStr
        }
        if !newSwipes.isEmpty {
            findings.append("\(newSwipes.count) new swipe\(newSwipes.count == 1 ? "" : "s") captured")
        }

        // 2. Count standing instructions that executed since last heartbeat
        let instructions = (try? await StandingInstructionEngine.shared.fetchAll()) ?? []
        var executedCount = 0
        for atom in instructions {
            let meta = atom.metadataDict ?? [:]
            let history = meta["executionHistory"] as? [[String: Any]] ?? []
            for entry in history {
                if let ts = entry["timestamp"] as? String, ts > sinceStr {
                    executedCount += 1
                }
            }
        }
        if executedCount > 0 {
            findings.append("\(executedCount) standing instruction\(executedCount == 1 ? "" : "s") executed")
        }

        // 3. Count content pieces updated since last heartbeat
        let allContent = (try? await AtomRepository.shared.fetchAll(type: .content)) ?? []
        let updatedContent = allContent.filter { $0.updatedAt > sinceStr }
        if !updatedContent.isEmpty {
            findings.append("\(updatedContent.count) content piece\(updatedContent.count == 1 ? "" : "s") updated")
        }

        // 4. Count overdue tasks (tasks with dueDate in the past that aren't completed)
        let allTasks = (try? await AtomRepository.shared.fetchAll(type: .task)) ?? []
        let nowStr = isoFormatter.string(from: Date())
        let overdueTasks = allTasks.filter { atom in
            let meta = atom.metadataDict ?? [:]
            guard let dueDate = meta["dueDate"] as? String, !dueDate.isEmpty else { return false }
            guard dueDate < nowStr else { return false }
            let status = meta["status"] as? String ?? ""
            return status != "completed" && status != "archived"
        }
        if !overdueTasks.isEmpty {
            findings.append("\(overdueTasks.count) overdue task\(overdueTasks.count == 1 ? "" : "s")")
        }

        // 5. Count content in draft phase (stale drafts)
        let staleDrafts = allContent.filter { atom in
            let meta = atom.metadataDict ?? [:]
            let phase = meta["phase"] as? String ?? ""
            return phase == "draft" || phase == "brainstorm"
        }
        if staleDrafts.count > 2 {
            findings.append("\(staleDrafts.count) drafts waiting for attention")
        }

        // If nothing noteworthy, return nil (stay silent)
        guard !findings.isEmpty else { return nil }

        // Format the summary
        var summary = "Pulse check:\n"
        for finding in findings {
            summary += "- \(finding)\n"
        }
        summary += "\nAnything you'd like me to look into?"

        return summary
    }

    // MARK: - DND Check

    private func isInDNDMode() -> Bool {
        // Check if a deep work session is active via notification or UserDefaults
        let sessionActive = UserDefaults.standard.bool(forKey: "deep_work_session_active")
        return sessionActive
    }

    // MARK: - Deliver Deferred Messages

    func deliverDeferredMessages() async {
        guard !deferredMessages.isEmpty else { return }

        let messages = deferredMessages
        deferredMessages.removeAll()

        for msg in messages {
            switch msg.tag {
            case "weekly":
                let review = await WeeklyStrategyReview().generate()
                await TelegramBridgeService.shared.sendLongMessage(chatId: msg.chatId, text: review)
            default:
                // Morning brief or any other deferred message
                let brief = await AgentBriefGenerator.shared.generateMorningBrief()
                await TelegramBridgeService.shared.sendLongMessage(chatId: msg.chatId, text: brief)
            }
        }
    }

    // MARK: - Chat ID Resolution

    /// Resolve the active Telegram chat ID with a retry if nil (app may have just launched).
    private func resolveChatId() async -> String? {
        if let chatId = TelegramBridgeService.shared.activeChatId {
            return chatId
        }
        // Retry once after 5 seconds in case Telegram hasn't connected yet
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        if let chatId = TelegramBridgeService.shared.activeChatId {
            return chatId
        }
        // Last resort: check UserDefaults for a previously stored chat ID
        return UserDefaults.standard.string(forKey: "agent_telegram_chat_id")
    }

    // MARK: - Delivery Logging

    /// Log proactive message delivery attempts for debugging.
    private func logDeliveryAttempt(type: String, success: Bool) {
        var log = UserDefaults.standard.array(forKey: "proactive_delivery_log") as? [[String: Any]] ?? []
        let entry: [String: Any] = [
            "type": type,
            "success": success,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        log.append(entry)
        // Keep only last 50 entries
        if log.count > 50 {
            log = Array(log.suffix(50))
        }
        UserDefaults.standard.set(log, forKey: "proactive_delivery_log")
    }
}
