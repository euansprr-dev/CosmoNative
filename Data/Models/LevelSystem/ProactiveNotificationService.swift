import Foundation
import UserNotifications
import Combine

// MARK: - Notification Types

/// Types of proactive notifications Cosmo can send
public enum CosmoNotificationType: String, CaseIterable, Sendable {
    // Daily summaries
    case morningSummary             // Yesterday's recap + today's focus
    case eveningSummary             // End of day wrap-up

    // Streak notifications
    case streakAtRisk               // Streak about to break
    case streakBroken               // Streak was lost
    case streakMilestone            // Hit 7, 30, 60, 90, 180, 365 days
    case streakProtected            // Auto-freeze used

    // Level notifications
    case levelUp                    // Cosmo Index level up
    case dimensionLevelUp           // Dimension level up
    case neloMilestone              // Hit NELO tier threshold
    case neloRegression             // NELO dropped significantly

    // Badge notifications
    case badgeUnlocked              // New badge earned
    case badgeNearCompletion        // 90%+ progress on badge

    // Quest notifications
    case questsAvailable            // New daily quests ready
    case questNearCompletion        // Quest almost done
    case questsExpiring             // Quests about to expire

    // Health notifications
    case readinessUpdate            // Morning readiness score
    case hrvAnomaly                 // Unusual HRV pattern
    case recoveryRecommendation     // Suggest rest based on data

    // Deep work notifications
    case deepWorkReminder           // Nudge to start focus block
    case deepWorkComplete           // Focus block completed

    var category: NotificationCategory {
        switch self {
        case .morningSummary, .eveningSummary:
            return .summary
        case .streakAtRisk, .streakBroken, .streakMilestone, .streakProtected:
            return .streak
        case .levelUp, .dimensionLevelUp, .neloMilestone, .neloRegression:
            return .level
        case .badgeUnlocked, .badgeNearCompletion:
            return .badge
        case .questsAvailable, .questNearCompletion, .questsExpiring:
            return .quest
        case .readinessUpdate, .hrvAnomaly, .recoveryRecommendation:
            return .health
        case .deepWorkReminder, .deepWorkComplete:
            return .deepWork
        }
    }

    var priority: NotificationPriority {
        switch self {
        case .levelUp, .badgeUnlocked, .streakMilestone:
            return .high
        case .streakAtRisk, .morningSummary, .readinessUpdate:
            return .medium
        default:
            return .low
        }
    }
}

public enum NotificationCategory: String, Sendable {
    case summary
    case streak
    case level
    case badge
    case quest
    case health
    case deepWork
}

public enum NotificationPriority: Int, Comparable, Sendable {
    case low = 0
    case medium = 1
    case high = 2
    case critical = 3

    public static func < (lhs: NotificationPriority, rhs: NotificationPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Notification Content

/// Content for a Cosmo notification
public struct CosmoNotificationContent: Sendable {
    public let id: String
    public let type: CosmoNotificationType
    public let title: String
    public let subtitle: String?
    public let body: String
    public let badge: Int?
    public let sound: NotificationSound
    public let userInfo: [String: String]
    public let actions: [NotificationAction]
    public let scheduledTime: Date?
    public let expiresAt: Date?

    public enum NotificationSound: String, Sendable {
        case `default`
        case celebration
        case warning
        case subtle
        case none

        var soundName: UNNotificationSoundName? {
            switch self {
            case .default: return UNNotificationSoundName("default")
            case .celebration: return UNNotificationSoundName("celebration.caf")
            case .warning: return UNNotificationSoundName("warning.caf")
            case .subtle: return UNNotificationSoundName("subtle.caf")
            case .none: return nil
            }
        }
    }

    public struct NotificationAction: Sendable {
        public let id: String
        public let title: String
        public let destructive: Bool

        public init(id: String, title: String, destructive: Bool = false) {
            self.id = id
            self.title = title
            self.destructive = destructive
        }
    }

    public init(
        id: String = UUID().uuidString,
        type: CosmoNotificationType,
        title: String,
        subtitle: String? = nil,
        body: String,
        badge: Int? = nil,
        sound: NotificationSound = .default,
        userInfo: [String: String] = [:],
        actions: [NotificationAction] = [],
        scheduledTime: Date? = nil,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.badge = badge
        self.sound = sound
        self.userInfo = userInfo
        self.actions = actions
        self.scheduledTime = scheduledTime
        self.expiresAt = expiresAt
    }
}

// MARK: - Notification Preferences

/// User preferences for notifications
public struct NotificationPreferences: Codable, Sendable {
    public var enabled: Bool
    public var quietHoursStart: Int  // Hour (0-23)
    public var quietHoursEnd: Int    // Hour (0-23)
    public var categories: [String: Bool]  // Category -> enabled
    public var deliveryStyle: DeliveryStyle

    public enum DeliveryStyle: String, Codable, Sendable {
        case immediate      // Show immediately
        case scheduled      // Show at scheduled time
        case intelligent    // AI-determined best time
    }

    public static var `default`: NotificationPreferences {
        NotificationPreferences(
            enabled: true,
            quietHoursStart: 22,
            quietHoursEnd: 7,
            categories: [
                "summary": true,
                "streak": true,
                "level": true,
                "badge": true,
                "quest": true,
                "health": true,
                "deepWork": true
            ],
            deliveryStyle: .intelligent
        )
    }

    public func isCategoryEnabled(_ category: NotificationCategory) -> Bool {
        categories[category.rawValue] ?? true
    }

    public func isQuietHours(at date: Date = Date()) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)

        if quietHoursStart < quietHoursEnd {
            // e.g., 22:00 - 07:00 (spanning midnight)
            return hour >= quietHoursStart || hour < quietHoursEnd
        } else {
            // e.g., 10:00 - 22:00 (same day)
            return hour >= quietHoursStart && hour < quietHoursEnd
        }
    }
}

// MARK: - Proactive Notification Service

/// Service that manages all proactive notifications for Cosmo
@MainActor
public final class ProactiveNotificationService: ObservableObject {

    // MARK: - Singleton

    public static let shared = ProactiveNotificationService()

    // MARK: - Published State

    @Published public var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published public var preferences: NotificationPreferences = .default
    @Published public var pendingNotifications: [CosmoNotificationContent] = []

    // MARK: - Private State

    private let notificationCenter = UNUserNotificationCenter.current()
    private var cancellables = Set<AnyCancellable>()

    // Flow protection - delay notifications during deep work
    private var isInDeepWork: Bool = false
    private var deferredNotifications: [CosmoNotificationContent] = []

    public init() {
        setupNotificationCategories()
        checkAuthorizationStatus()
    }

    // MARK: - Authorization

    /// Request notification permissions
    public func requestAuthorization() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(
                options: [.alert, .badge, .sound, .criticalAlert]
            )
            await MainActor.run {
                authorizationStatus = granted ? .authorized : .denied
            }
            return granted
        } catch {
            print("Notification authorization error: \(error)")
            return false
        }
    }

    /// Check current authorization status
    private func checkAuthorizationStatus() {
        Task {
            let settings = await notificationCenter.notificationSettings()
            await MainActor.run {
                authorizationStatus = settings.authorizationStatus
            }
        }
    }

    // MARK: - Notification Scheduling

    /// Schedule a notification
    public func schedule(_ notification: CosmoNotificationContent) async {
        // Check preferences
        guard preferences.enabled,
              preferences.isCategoryEnabled(notification.type.category) else {
            return
        }

        // Check quiet hours for non-critical
        if notification.type.priority < .high && preferences.isQuietHours() {
            // Defer to after quiet hours
            let deferredNotification = deferToAfterQuietHours(notification)
            await scheduleInternal(deferredNotification)
            return
        }

        // Check deep work protection
        if isInDeepWork && notification.type.priority < .critical {
            deferredNotifications.append(notification)
            return
        }

        await scheduleInternal(notification)
    }

    private func scheduleInternal(_ notification: CosmoNotificationContent) async {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        if let subtitle = notification.subtitle {
            content.subtitle = subtitle
        }
        content.body = notification.body
        if let badge = notification.badge {
            content.badge = NSNumber(value: badge)
        }
        if let soundName = notification.sound.soundName {
            content.sound = UNNotificationSound(named: soundName)
        }
        content.userInfo = notification.userInfo.merging(
            ["type": notification.type.rawValue],
            uniquingKeysWith: { $1 }
        )
        content.categoryIdentifier = notification.type.category.rawValue

        let trigger: UNNotificationTrigger?
        if let scheduledTime = notification.scheduledTime {
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: scheduledTime
            )
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        } else {
            trigger = nil  // Deliver immediately
        }

        let request = UNNotificationRequest(
            identifier: notification.id,
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
            await MainActor.run {
                pendingNotifications.append(notification)
            }
        } catch {
            print("Failed to schedule notification: \(error)")
        }
    }

    /// Cancel a scheduled notification
    public func cancel(_ notificationId: String) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [notificationId])
        pendingNotifications.removeAll { $0.id == notificationId }
    }

    /// Cancel all notifications of a type
    public func cancelAll(ofType type: CosmoNotificationType) {
        let ids = pendingNotifications.filter { $0.type == type }.map { $0.id }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ids)
        pendingNotifications.removeAll { $0.type == type }
    }

    // MARK: - Morning Summary

    /// Schedule morning summary notification
    public func scheduleMorningSummary(summary: DailySummaryMetadata) async {
        let content = buildMorningSummaryContent(summary: summary)
        await schedule(content)
    }

    private func buildMorningSummaryContent(summary: DailySummaryMetadata) -> CosmoNotificationContent {
        let subtitle = buildMorningSubtitle(summary: summary)
        let body = buildMorningBody(summary: summary)

        return CosmoNotificationContent(
            type: .morningSummary,
            title: "Good Morning",
            subtitle: subtitle,
            body: body,
            sound: .subtle,
            userInfo: [
                "summaryDate": ISO8601DateFormatter().string(from: summary.summaryDate)
            ],
            actions: [
                .init(id: "view_summary", title: "View Summary"),
                .init(id: "start_focus", title: "Start Focus")
            ],
            scheduledTime: nextMorningTime()
        )
    }

    private func buildMorningSubtitle(summary: DailySummaryMetadata) -> String {
        if !summary.levelUps.isEmpty {
            return "You leveled up yesterday!"
        }
        if summary.totalXPGained >= 500 {
            return "Outstanding progress yesterday"
        }
        if let readiness = summary.readinessScore, readiness >= 85 {
            return "Readiness: \(Int(readiness))% - Peak day ahead"
        }
        return "+\(summary.totalXPGained) XP yesterday"
    }

    private func buildMorningBody(summary: DailySummaryMetadata) -> String {
        var parts: [String] = []

        // Streak info
        if summary.currentOverallStreak > 0 {
            parts.append("\(summary.currentOverallStreak)-day streak")
        }

        // Today's focus
        if let focus = summary.tomorrowFocus {
            parts.append("Focus: \(focus)")
        }

        // Quests
        parts.append("\(summary.questsCompleted)/\(summary.totalQuests) quests available")

        return parts.joined(separator: " • ")
    }

    private func nextMorningTime() -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 7
        components.minute = 0

        var morningTime = calendar.date(from: components)!

        // If it's already past morning, schedule for tomorrow
        if morningTime < Date() {
            morningTime = calendar.date(byAdding: .day, value: 1, to: morningTime)!
        }

        return morningTime
    }

    // MARK: - Streak Notifications

    /// Schedule streak at-risk warning
    public func scheduleStreakWarning(
        dimension: String,
        currentStreak: Int,
        hoursRemaining: Int,
        action: String
    ) async {
        let content = CosmoNotificationContent(
            type: .streakAtRisk,
            title: "\(dimension.capitalized) Streak at Risk",
            subtitle: "\(currentStreak)-day streak needs action",
            body: "\(action) in the next \(hoursRemaining) hours to keep your streak alive.",
            sound: .warning,
            userInfo: [
                "dimension": dimension,
                "streak": "\(currentStreak)"
            ],
            actions: [
                .init(id: "take_action", title: action),
                .init(id: "use_freeze", title: "Use Freeze")
            ]
        )

        await schedule(content)
    }

    /// Notify streak broken
    public func notifyStreakBroken(dimension: String, previousStreak: Int) async {
        let content = CosmoNotificationContent(
            type: .streakBroken,
            title: "\(dimension.capitalized) Streak Ended",
            subtitle: "\(previousStreak)-day streak",
            body: "Start rebuilding today. Every streak starts with day one.",
            sound: .subtle,
            userInfo: [
                "dimension": dimension,
                "previousStreak": "\(previousStreak)"
            ]
        )

        await schedule(content)
    }

    /// Celebrate streak milestone
    public func celebrateStreakMilestone(dimension: String, days: Int) async {
        let milestone = streakMilestoneName(days)
        let content = CosmoNotificationContent(
            type: .streakMilestone,
            title: "\(milestone) Streak!",
            subtitle: "\(dimension.capitalized): \(days) days",
            body: "Your consistency is building something remarkable.",
            sound: .celebration,
            userInfo: [
                "dimension": dimension,
                "days": "\(days)"
            ]
        )

        await schedule(content)
    }

    private func streakMilestoneName(_ days: Int) -> String {
        switch days {
        case 7: return "Week"
        case 14: return "Two Week"
        case 30: return "Monthly"
        case 60: return "Two Month"
        case 90: return "Quarterly"
        case 180: return "Six Month"
        case 365: return "Annual"
        default: return "\(days)-Day"
        }
    }

    // MARK: - Level Notifications

    /// Notify level up
    public func notifyLevelUp(
        dimension: String,
        previousLevel: Int,
        newLevel: Int,
        title: String?
    ) async {
        let isOverall = dimension == "overall"
        let headline = isOverall ? "Cosmo Index Level Up!" : "\(dimension.capitalized) Level Up!"
        let subtitle = isOverall && title != nil ? title : "\(previousLevel) → \(newLevel)"

        let content = CosmoNotificationContent(
            type: isOverall ? .levelUp : .dimensionLevelUp,
            title: headline,
            subtitle: subtitle,
            body: "Your dedication is paying off. Keep building momentum.",
            sound: .celebration,
            userInfo: [
                "dimension": dimension,
                "newLevel": "\(newLevel)"
            ]
        )

        await schedule(content)
    }

    /// Notify NELO tier change
    public func notifyNELOTierChange(newTier: String, nelo: Int) async {
        let content = CosmoNotificationContent(
            type: .neloMilestone,
            title: "New NELO Tier: \(newTier)",
            subtitle: "Rating: \(nelo)",
            body: "Your performance places you among the top performers.",
            sound: .celebration,
            userInfo: [
                "tier": newTier,
                "nelo": "\(nelo)"
            ]
        )

        await schedule(content)
    }

    // MARK: - Badge Notifications

    /// Notify badge unlocked
    public func notifyBadgeUnlocked(
        badgeName: String,
        tier: String,
        xpReward: Int
    ) async {
        let content = CosmoNotificationContent(
            type: .badgeUnlocked,
            title: "Badge Unlocked!",
            subtitle: badgeName,
            body: "\(tier) badge • +\(xpReward) XP reward",
            badge: 1,
            sound: .celebration,
            userInfo: [
                "badge": badgeName,
                "tier": tier,
                "xp": "\(xpReward)"
            ],
            actions: [
                .init(id: "view_badge", title: "View Badge"),
                .init(id: "share", title: "Share")
            ]
        )

        await schedule(content)
    }

    /// Notify badge near completion
    public func notifyBadgeNearCompletion(
        badgeName: String,
        progress: Double,
        remaining: String
    ) async {
        let content = CosmoNotificationContent(
            type: .badgeNearCompletion,
            title: "Badge Almost Yours",
            subtitle: badgeName,
            body: "\(Int(progress * 100))% complete • \(remaining)",
            sound: .subtle,
            userInfo: [
                "badge": badgeName,
                "progress": "\(progress)"
            ]
        )

        await schedule(content)
    }

    // MARK: - Quest Notifications

    /// Notify new quests available
    public func notifyQuestsAvailable(count: Int, totalXP: Int) async {
        let content = CosmoNotificationContent(
            type: .questsAvailable,
            title: "Daily Quests Ready",
            subtitle: "\(count) quests • \(totalXP) XP available",
            body: "Complete today's challenges to level up faster.",
            sound: .subtle,
            actions: [
                .init(id: "view_quests", title: "View Quests")
            ],
            scheduledTime: nextMorningTime()
        )

        await schedule(content)
    }

    /// Notify quests expiring
    public func notifyQuestsExpiring(incompleteCount: Int, hoursRemaining: Int) async {
        let content = CosmoNotificationContent(
            type: .questsExpiring,
            title: "Quests Expiring Soon",
            subtitle: "\(incompleteCount) incomplete",
            body: "Complete your quests in the next \(hoursRemaining) hours.",
            sound: .warning,
            actions: [
                .init(id: "view_quests", title: "View Quests")
            ]
        )

        await schedule(content)
    }

    // MARK: - Health Notifications

    /// Notify morning readiness score
    public func notifyReadinessScore(
        score: Int,
        recommendation: String
    ) async {
        let emoji = score >= 85 ? "peak" : (score >= 60 ? "good" : "recovery")
        let title = score >= 85 ? "Peak Day Ahead" : (score >= 60 ? "Good to Go" : "Recovery Day")

        let content = CosmoNotificationContent(
            type: .readinessUpdate,
            title: title,
            subtitle: "Readiness: \(score)%",
            body: recommendation,
            sound: .subtle,
            userInfo: [
                "score": "\(score)",
                "type": emoji
            ],
            scheduledTime: nextMorningTime()
        )

        await schedule(content)
    }

    // MARK: - Deep Work Management

    /// Enter deep work mode - defer notifications
    public func enterDeepWork() {
        isInDeepWork = true
    }

    /// Exit deep work mode - deliver deferred notifications
    public func exitDeepWork() async {
        isInDeepWork = false

        // Deliver deferred notifications
        for notification in deferredNotifications {
            await schedule(notification)
        }
        deferredNotifications.removeAll()
    }

    // MARK: - Helpers

    private func deferToAfterQuietHours(_ notification: CosmoNotificationContent) -> CosmoNotificationContent {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = preferences.quietHoursEnd
        components.minute = 0

        var deliveryTime = calendar.date(from: components)!

        // If quiet hours end is already passed, deliver tomorrow
        if deliveryTime < Date() {
            deliveryTime = calendar.date(byAdding: .day, value: 1, to: deliveryTime)!
        }

        return CosmoNotificationContent(
            id: notification.id,
            type: notification.type,
            title: notification.title,
            subtitle: notification.subtitle,
            body: notification.body,
            badge: notification.badge,
            sound: notification.sound,
            userInfo: notification.userInfo,
            actions: notification.actions,
            scheduledTime: deliveryTime,
            expiresAt: notification.expiresAt
        )
    }

    private func setupNotificationCategories() {
        // Summary category
        let summaryCategory = UNNotificationCategory(
            identifier: "summary",
            actions: [
                UNNotificationAction(identifier: "view_summary", title: "View Summary"),
                UNNotificationAction(identifier: "start_focus", title: "Start Focus")
            ],
            intentIdentifiers: []
        )

        // Streak category
        let streakCategory = UNNotificationCategory(
            identifier: "streak",
            actions: [
                UNNotificationAction(identifier: "take_action", title: "Take Action"),
                UNNotificationAction(identifier: "use_freeze", title: "Use Freeze")
            ],
            intentIdentifiers: []
        )

        // Badge category
        let badgeCategory = UNNotificationCategory(
            identifier: "badge",
            actions: [
                UNNotificationAction(identifier: "view_badge", title: "View Badge"),
                UNNotificationAction(identifier: "share", title: "Share")
            ],
            intentIdentifiers: []
        )

        // Quest category
        let questCategory = UNNotificationCategory(
            identifier: "quest",
            actions: [
                UNNotificationAction(identifier: "view_quests", title: "View Quests")
            ],
            intentIdentifiers: []
        )

        notificationCenter.setNotificationCategories([
            summaryCategory,
            streakCategory,
            badgeCategory,
            questCategory
        ])
    }
}
