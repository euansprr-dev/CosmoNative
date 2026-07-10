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

    // Timed goal notifications
    case timedGoalReached           // Task/habit time goal hit mid-session

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
        case .timedGoalReached:
            return .timedGoal
        }
    }

    var priority: NotificationPriority {
        switch self {
        // The goal alert fires DURING a deep work session by definition, so it must
        // bypass the deep-work deferral (and quiet hours — the user set the timer).
        case .timedGoalReached:
            return .critical
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
    case timedGoal
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
                "deepWork": true,
                "timedGoal": true
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

        // Timed goal category — actions mirror the in-app prompt
        let timedGoalCategory = UNNotificationCategory(
            identifier: NotificationCategory.timedGoal.rawValue,
            actions: [
                UNNotificationAction(identifier: "timed_goal_complete", title: "Mark Complete"),
                UNNotificationAction(identifier: "timed_goal_keep_going", title: "Keep Going")
            ],
            intentIdentifiers: []
        )

        // Merge with categories other services registered (SwipeFileEngine's
        // capture category) — setNotificationCategories REPLACES the whole set.
        let ownCategories: Set<UNNotificationCategory> = [
            summaryCategory,
            streakCategory,
            badgeCategory,
            questCategory,
            timedGoalCategory
        ]
        let ownIdentifiers = Set(ownCategories.map(\.identifier))
        UNUserNotificationCenter.current().getNotificationCategories { existing in
            let preserved = existing.filter { !ownIdentifiers.contains($0.identifier) }
            UNUserNotificationCenter.current().setNotificationCategories(preserved.union(ownCategories))
        }
    }
}
