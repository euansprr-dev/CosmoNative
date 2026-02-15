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

    private var morningTimer: Timer?
    private var weeklyTimer: Timer?
    private var streakTimer: Timer?
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
    }

    // MARK: - Schedule All

    func scheduleAll() {
        scheduleMorningBrief()
        scheduleWeeklyReview()
        scheduleStreakCheck()
    }

    func rescheduleAll() {
        morningTimer?.invalidate()
        weeklyTimer?.invalidate()
        streakTimer?.invalidate()
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
        guard let chatId = TelegramBridgeService.shared.activeChatId else { return }

        // Check DND — defer if active
        if dndEnabled && isInDNDMode() {
            deferredMessages.append((chatId: chatId, tag: "morning"))
            return
        }

        let brief = await AgentBriefGenerator.shared.generateMorningBrief()
        await TelegramBridgeService.shared.sendMessage(chatId: chatId, text: brief)
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
        guard let chatId = TelegramBridgeService.shared.activeChatId else { return }

        if dndEnabled && isInDNDMode() {
            deferredMessages.append((chatId: chatId, tag: "weekly"))
            return
        }

        let review = await AgentBriefGenerator.shared.generateWeeklyReview()
        await TelegramBridgeService.shared.sendMessage(chatId: chatId, text: review)
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
        guard let chatId = TelegramBridgeService.shared.activeChatId else { return }

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
                let review = await AgentBriefGenerator.shared.generateWeeklyReview()
                await TelegramBridgeService.shared.sendMessage(chatId: msg.chatId, text: review)
            default:
                // Morning brief or any other deferred message
                let brief = await AgentBriefGenerator.shared.generateMorningBrief()
                await TelegramBridgeService.shared.sendMessage(chatId: msg.chatId, text: brief)
            }
        }
    }
}
