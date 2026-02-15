// CosmoOS/UI/Sanctuary/Dimensions/Creative/CreativeDimensionData.swift
// Creative Dimension Data Models - "The Creator's Console"
// Phase 4: Following SANCTUARY_UI_SPEC_V2.md section 3.2

import Foundation
import SwiftUI

// MARK: - Growth Status

/// Status of growth trajectory
public enum GrowthStatus: String, Codable, CaseIterable, Sendable {
    case strong
    case moderate
    case weak
    case declining

    var displayName: String {
        rawValue.capitalized
    }

    var color: String {
        switch self {
        case .strong: return "#10B981"    // Green
        case .moderate: return "#F59E0B"  // Amber
        case .weak: return "#6B7280"      // Gray
        case .declining: return "#EF4444" // Red
        }
    }

    var iconName: String {
        switch self {
        case .strong: return "arrow.up.right"
        case .moderate: return "arrow.right"
        case .weak: return "minus"
        case .declining: return "arrow.down.right"
        }
    }
}

// MARK: - Time Range

/// Time range for performance graphs
public enum CreativeTimeRange: String, Codable, CaseIterable, Sendable {
    case week = "7d"
    case twoWeeks = "14d"
    case month = "30d"
    case twoMonths = "60d"
    case quarter = "90d"
    case year = "1Y"

    var displayName: String {
        rawValue
    }

    var days: Int {
        switch self {
        case .week: return 7
        case .twoWeeks: return 14
        case .month: return 30
        case .twoMonths: return 60
        case .quarter: return 90
        case .year: return 365
        }
    }
}

// MARK: - Platform

/// Content platforms
public enum ContentPlatform: String, Codable, CaseIterable, Sendable {
    case instagram = "Instagram"
    case youtube = "YouTube"
    case tiktok = "TikTok"
    case twitter = "Twitter"
    case linkedin = "LinkedIn"
    case threads = "Threads"

    var displayName: String {
        rawValue
    }

    var iconName: String {
        switch self {
        case .instagram: return "camera.fill"
        case .youtube: return "play.rectangle.fill"
        case .tiktok: return "music.note"
        case .twitter: return "at"
        case .linkedin: return "person.2.fill"
        case .threads: return "at.circle.fill"
        }
    }

    var colorHex: String {
        switch self {
        case .instagram: return "#E1306C"
        case .youtube: return "#FF0000"
        case .tiktok: return "#00F2EA"
        case .twitter: return "#1DA1F2"
        case .linkedin: return "#0077B5"
        case .threads: return "#000000"
        }
    }

    /// SwiftUI Color from hex
    var color: Color {
        Color(hex: colorHex)
    }

    var shortName: String {
        switch self {
        case .instagram: return "IG"
        case .youtube: return "YT"
        case .tiktok: return "TT"
        case .twitter: return "TW"
        case .linkedin: return "LI"
        case .threads: return "TH"
        }
    }
}

// MARK: - Content Type

/// Types of content
public enum ContentType: String, Codable, CaseIterable, Sendable {
    case reel
    case video
    case image
    case story
    case carousel
    case short
    case post
    case thread

    var displayName: String {
        rawValue.capitalized
    }

    var iconName: String {
        switch self {
        case .reel: return "film"
        case .video: return "play.rectangle.fill"
        case .image: return "photo"
        case .story: return "circle.dashed"
        case .carousel: return "square.stack"
        case .short: return "play.square.stack"
        case .post: return "doc.text"
        case .thread: return "text.bubble"
        }
    }
}

// MARK: - Weekday

/// Days of the week
public enum Weekday: Int, Codable, CaseIterable, Sendable {
    case monday = 1
    case tuesday = 2
    case wednesday = 3
    case thursday = 4
    case friday = 5
    case saturday = 6
    case sunday = 7

    var displayName: String {
        switch self {
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        case .sunday: return "Sunday"
        }
    }

    var shortName: String {
        String(displayName.prefix(3))
    }

    var initial: String {
        String(displayName.prefix(1))
    }

    /// Alias for displayName
    var fullName: String { displayName }
}

// MARK: - Factor Category

/// Categories for causal factors
public enum FactorCategory: String, Codable, CaseIterable, Sendable {
    case timing
    case content
    case trend
    case creatorState = "creator_state"

    var displayName: String {
        switch self {
        case .timing: return "Timing"
        case .content: return "Content"
        case .trend: return "Trend"
        case .creatorState: return "Your Energy"
        }
    }

    var iconName: String {
        switch self {
        case .timing: return "clock.fill"
        case .content: return "doc.text.fill"
        case .trend: return "chart.line.uptrend.xyaxis"
        case .creatorState: return "heart.fill"
        }
    }

    var color: Color {
        switch self {
        case .timing: return Color.blue
        case .content: return Color.purple
        case .trend: return Color.green
        case .creatorState: return Color.pink
        }
    }
}

// Note: PostingDayStatus is defined in CreativePostingCalendar.swift

// MARK: - Posting Day

/// Data for a single calendar day
public struct PostingDay: Codable, Identifiable, Sendable {
    public let date: Date
    public let status: PostingDayStatus
    public let postCount: Int
    public let isToday: Bool

    /// Unique identifier based on date
    public var id: Date { date }

    public init(date: Date, status: PostingDayStatus, postCount: Int, isToday: Bool = false) {
        self.date = date
        self.status = status
        self.postCount = postCount
        self.isToday = isToday
    }
}

// MARK: - Performance Data Point

/// Single data point for performance graph
public struct PerformanceDataPoint: Codable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let reach: Int
    public let engagement: Double
    public let followers: Int

    public init(id: UUID = UUID(), date: Date, reach: Int, engagement: Double, followers: Int) {
        self.id = id
        self.date = date
        self.reach = reach
        self.engagement = engagement
        self.followers = followers
    }
}

// MARK: - Causal Factor

/// Factor contributing to post performance
public struct CausalFactor: Codable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let category: FactorCategory
    public let rating: Int                    // 1-5 stars
    public let value: String                  // Display value
    public let contribution: Double           // % contribution
    public let explanation: String

    public init(
        id: UUID = UUID(),
        name: String,
        category: FactorCategory,
        rating: Int,
        value: String,
        contribution: Double,
        explanation: String
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.rating = min(5, max(1, rating))
        self.value = value
        self.contribution = contribution
        self.explanation = explanation
    }

    /// Star display string
    public var starDisplay: String {
        String(repeating: "★", count: rating) + String(repeating: "☆", count: 5 - rating)
    }

    /// Alias for contribution (impact percentage)
    public var impact: Double { contribution }

    /// Confidence level based on rating (0-1)
    public var confidence: Double { Double(rating) / 5.0 }
}

// MARK: - Content Post

/// Individual content post with performance metrics
public struct ContentPost: Codable, Identifiable, Sendable {
    public let id: String
    public let platform: ContentPlatform
    public let type: ContentType
    public let thumbnailURL: URL?
    public let postedAt: Date
    public let caption: String?

    // Metrics
    public let reach: Int
    public let impressions: Int
    public let likes: Int
    public let comments: Int
    public let shares: Int
    public let saves: Int
    public let engagementRate: Double

    // Performance
    public let performanceVsAverage: Double   // % above/below
    public let isViral: Bool
    public let viralThresholdTime: TimeInterval?

    // Time series
    public let hourlyPerformance: [Int]
    public let peakTime: TimeInterval         // Hours after posting

    // Causal Analysis
    public let causalFactors: [CausalFactor]
    public let keyInsight: String?

    // Creator state correlations
    public let hrvAtPosting: Double?
    public let moodAtPosting: String?
    public let energyAtPosting: Double?

    /// Alias for caption (title of the post)
    public var title: String? { caption }

    /// Alias for engagementRate
    public var engagement: Double { engagementRate }

    /// Alias for type
    public var contentType: ContentType { type }

    /// Whether the post is trending (viral or high engagement)
    public var isTrending: Bool { isViral || performanceVsAverage > 50 }

    /// Formatted date string
    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: postedAt)
    }

    /// Formatted time string
    public var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        return formatter.string(from: postedAt).lowercased()
    }

    /// Formatted reach (e.g., "45.2K")
    public var formattedReach: String {
        formatNumber(reach)
    }

    /// Performance label
    public var performanceLabel: String {
        if performanceVsAverage > 50 {
            return "▲ +\(Int(performanceVsAverage))%"
        } else if performanceVsAverage > 0 {
            return "▲ +\(Int(performanceVsAverage))%"
        } else if performanceVsAverage < -10 {
            return "▼ \(Int(performanceVsAverage))%"
        } else {
            return "─ Avg"
        }
    }

    /// Performance color
    public var performanceColor: String {
        if performanceVsAverage > 20 {
            return "#10B981"  // Green
        } else if performanceVsAverage > -10 {
            return "#6B7280"  // Gray
        } else {
            return "#EF4444"  // Red
        }
    }

    private func formatNumber(_ num: Int) -> String {
        if num >= 1_000_000 {
            return String(format: "%.1fM", Double(num) / 1_000_000)
        } else if num >= 1_000 {
            return String(format: "%.1fK", Double(num) / 1_000)
        }
        return "\(num)"
    }

    public init(
        id: String,
        platform: ContentPlatform,
        type: ContentType,
        thumbnailURL: URL? = nil,
        postedAt: Date,
        caption: String? = nil,
        reach: Int,
        impressions: Int,
        likes: Int,
        comments: Int,
        shares: Int,
        saves: Int,
        engagementRate: Double,
        performanceVsAverage: Double,
        isViral: Bool = false,
        viralThresholdTime: TimeInterval? = nil,
        hourlyPerformance: [Int] = [],
        peakTime: TimeInterval = 0,
        causalFactors: [CausalFactor] = [],
        keyInsight: String? = nil,
        hrvAtPosting: Double? = nil,
        moodAtPosting: String? = nil,
        energyAtPosting: Double? = nil
    ) {
        self.id = id
        self.platform = platform
        self.type = type
        self.thumbnailURL = thumbnailURL
        self.postedAt = postedAt
        self.caption = caption
        self.reach = reach
        self.impressions = impressions
        self.likes = likes
        self.comments = comments
        self.shares = shares
        self.saves = saves
        self.engagementRate = engagementRate
        self.performanceVsAverage = performanceVsAverage
        self.isViral = isViral
        self.viralThresholdTime = viralThresholdTime
        self.hourlyPerformance = hourlyPerformance
        self.peakTime = peakTime
        self.causalFactors = causalFactors
        self.keyInsight = keyInsight
        self.hrvAtPosting = hrvAtPosting
        self.moodAtPosting = moodAtPosting
        self.energyAtPosting = energyAtPosting
    }
}

// MARK: - Platform Metrics

/// Metrics for a single platform
public struct PlatformMetrics: Codable, Identifiable, Sendable {
    public let id: UUID
    public let platform: ContentPlatform
    public let followerCount: Int
    public let engagementRate: Double
    public let reachPercentage: Double        // % of total reach
    public let isConnected: Bool

    /// Formatted follower count
    public var formattedFollowers: String {
        if followerCount >= 1_000_000 {
            return String(format: "%.1fM", Double(followerCount) / 1_000_000)
        } else if followerCount >= 1_000 {
            return String(format: "%.1fK", Double(followerCount) / 1_000)
        }
        return "\(followerCount)"
    }

    /// Alias for followerCount
    public var followers: Int { followerCount }

    /// Estimated average reach based on followers and engagement
    public var averageReach: Int { Int(Double(followerCount) * (reachPercentage / 100.0)) }

    /// Estimated growth rate (derived from engagement)
    public var growth: Double { engagementRate * 0.5 }

    /// Estimated retention rate
    public var retentionRate: Double { min(100, engagementRate * 15) }

    /// Best posting day (default to Wednesday)
    public var bestPostingDay: Weekday { .wednesday }

    public init(
        id: UUID = UUID(),
        platform: ContentPlatform,
        followerCount: Int,
        engagementRate: Double,
        reachPercentage: Double,
        isConnected: Bool = true
    ) {
        self.id = id
        self.platform = platform
        self.followerCount = followerCount
        self.engagementRate = engagementRate
        self.reachPercentage = reachPercentage
        self.isConnected = isConnected
    }
}

// MARK: - Content Window

/// Optimal posting window
public struct ContentWindow: Codable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let startTime: DateComponents
    public let endTime: DateComponents
    public let platform: ContentPlatform
    public let confidence: Double
    public let predictedReachBoost: Double
    public let predictedEngagementBoost: Double
    public let reason: String

    /// Formatted time range
    public var formattedTimeRange: String {
        guard let startHour = startTime.hour,
              let startMinute = startTime.minute,
              let endHour = endTime.hour,
              let endMinute = endTime.minute else {
            return "Unknown"
        }

        func format(hour: Int, minute: Int) -> String {
            let h = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour)
            let suffix = hour >= 12 ? "pm" : "am"
            if minute == 0 {
                return "\(h):\(String(format: "%02d", minute))\(suffix)"
            }
            return "\(h):\(String(format: "%02d", minute))\(suffix)"
        }

        return "\(format(hour: startHour, minute: startMinute)) - \(format(hour: endHour, minute: endMinute))"
    }

    /// Alias for predictedReachBoost
    public var predictedBoost: Double { predictedReachBoost }

    public init(
        id: UUID = UUID(),
        date: Date,
        startTime: DateComponents,
        endTime: DateComponents,
        platform: ContentPlatform,
        confidence: Double,
        predictedReachBoost: Double,
        predictedEngagementBoost: Double,
        reason: String
    ) {
        self.id = id
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.platform = platform
        self.confidence = confidence
        self.predictedReachBoost = predictedReachBoost
        self.predictedEngagementBoost = predictedEngagementBoost
        self.reason = reason
    }
}

// MARK: - Scheduled Post

/// Suggested scheduled post
public struct ScheduledPost: Codable, Identifiable, Sendable {
    public let id: UUID
    public let scheduledTime: Date
    public let platform: ContentPlatform
    public let type: ContentType
    public let windowType: String             // "Primary", "Secondary", "Evening"
    public let confidence: Double

    /// Formatted time
    public var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        return formatter.string(from: scheduledTime).lowercased()
    }

    /// Alias for formattedTime
    public var formattedScheduledTime: String { formattedTime }

    /// Title based on platform and type
    public var title: String { "\(platform.displayName) \(type.displayName)" }

    /// Predicted reach (estimated based on confidence)
    public var predictedReach: Int? { Int(confidence * 1000) }

    public init(
        id: UUID = UUID(),
        scheduledTime: Date,
        platform: ContentPlatform,
        type: ContentType,
        windowType: String,
        confidence: Double
    ) {
        self.id = id
        self.scheduledTime = scheduledTime
        self.platform = platform
        self.type = type
        self.windowType = windowType
        self.confidence = confidence
    }
}

// MARK: - Creative Dimension Data

/// Complete data model for Creative Dimension
public struct CreativeDimensionData: Sendable {

    // MARK: - Hero Metrics

    public var totalReach: Int
    public var reachTrend: Double             // % change vs period
    public var reachSparkline: [Int]          // Last 30 days
    public var engagementRate: Double
    public var engagementTrend: Double
    public var engagementSparkline: [Double]
    public var followerCount: Int
    public var followerGrowth: Int            // This period
    public var followerSparkline: [Int]
    public var growthRate: Double             // % per week
    public var growthStatus: GrowthStatus

    // MARK: - Performance Graph

    public var performanceTimeSeries: [PerformanceDataPoint]
    public var selectedTimeRange: CreativeTimeRange

    // MARK: - Posting Calendar

    public var postingCalendar: [Date: PostingDay]
    public var postingStreak: Int
    public var longestStreak: Int
    public var bestPostingTime: DateComponents
    public var mostActiveDay: Weekday
    public var averagePostsPerWeek: Double

    // MARK: - Posts

    public var recentPosts: [ContentPost]
    public var viralPosts: [ContentPost]
    public var underperformingPosts: [ContentPost]

    // MARK: - Platform Breakdown

    public var platformMetrics: [PlatformMetrics]

    // MARK: - Retention Analysis

    public var averageRetentionCurve: [Double]  // % at each quartile
    public var averageWatchTime: Double         // Percentage
    public var dropOffPoint: Double             // Percentage

    // MARK: - Predictions

    public var predictedWindows: [ContentWindow]
    public var suggestedSchedule: [ScheduledPost]
    public var trendingTopics: [String]

    // MARK: - Computed Properties

    /// Formatted total reach
    public var formattedReach: String {
        if totalReach >= 1_000_000 {
            return String(format: "%.1fM", Double(totalReach) / 1_000_000)
        } else if totalReach >= 1_000 {
            return String(format: "%.1fK", Double(totalReach) / 1_000)
        }
        return "\(totalReach)"
    }

    /// Formatted follower count
    public var formattedFollowers: String {
        if followerCount >= 1_000_000 {
            return String(format: "%.1fM", Double(followerCount) / 1_000_000)
        } else if followerCount >= 1_000 {
            return String(format: "%.1fK", Double(followerCount) / 1_000)
        }
        return "\(followerCount)"
    }

    /// Formatted best posting time
    public var formattedBestTime: String {
        guard let hour = bestPostingTime.hour,
              let minute = bestPostingTime.minute else {
            return "Unknown"
        }
        let h = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour)
        let suffix = hour >= 12 ? "pm" : "am"
        return "\(h):\(String(format: "%02d", minute))\(suffix)"
    }

    /// Next scheduled post
    public var nextScheduledPost: ScheduledPost? {
        suggestedSchedule.first
    }

    // MARK: - Aliases for View Compatibility

    /// Alias for postingCalendar
    public var postingHistory: [Date: PostingDay] { postingCalendar }

    /// Alias for postingStreak
    public var currentStreak: Int { postingStreak }

    /// Alias for suggestedSchedule
    public var scheduledPosts: [ScheduledPost] { suggestedSchedule }

    /// Alias for predictedWindows
    public var optimalWindows: [ContentWindow] { predictedWindows }

    /// Top performing posts (sorted by performance vs average)
    public var topPerformers: [ContentPost] {
        recentPosts.sorted { $0.performanceVsAverage > $1.performanceVsAverage }.prefix(5).map { $0 }
    }

    // MARK: - Initialization

    public init(
        totalReach: Int = 0,
        reachTrend: Double = 0,
        reachSparkline: [Int] = [],
        engagementRate: Double = 0,
        engagementTrend: Double = 0,
        engagementSparkline: [Double] = [],
        followerCount: Int = 0,
        followerGrowth: Int = 0,
        followerSparkline: [Int] = [],
        growthRate: Double = 0,
        growthStatus: GrowthStatus = .moderate,
        performanceTimeSeries: [PerformanceDataPoint] = [],
        selectedTimeRange: CreativeTimeRange = .month,
        postingCalendar: [Date: PostingDay] = [:],
        postingStreak: Int = 0,
        longestStreak: Int = 0,
        bestPostingTime: DateComponents = DateComponents(hour: 15, minute: 15),
        mostActiveDay: Weekday = .wednesday,
        averagePostsPerWeek: Double = 0,
        recentPosts: [ContentPost] = [],
        viralPosts: [ContentPost] = [],
        underperformingPosts: [ContentPost] = [],
        platformMetrics: [PlatformMetrics] = [],
        averageRetentionCurve: [Double] = [],
        averageWatchTime: Double = 0,
        dropOffPoint: Double = 0,
        predictedWindows: [ContentWindow] = [],
        suggestedSchedule: [ScheduledPost] = [],
        trendingTopics: [String] = []
    ) {
        self.totalReach = totalReach
        self.reachTrend = reachTrend
        self.reachSparkline = reachSparkline
        self.engagementRate = engagementRate
        self.engagementTrend = engagementTrend
        self.engagementSparkline = engagementSparkline
        self.followerCount = followerCount
        self.followerGrowth = followerGrowth
        self.followerSparkline = followerSparkline
        self.growthRate = growthRate
        self.growthStatus = growthStatus
        self.performanceTimeSeries = performanceTimeSeries
        self.selectedTimeRange = selectedTimeRange
        self.postingCalendar = postingCalendar
        self.postingStreak = postingStreak
        self.longestStreak = longestStreak
        self.bestPostingTime = bestPostingTime
        self.mostActiveDay = mostActiveDay
        self.averagePostsPerWeek = averagePostsPerWeek
        self.recentPosts = recentPosts
        self.viralPosts = viralPosts
        self.underperformingPosts = underperformingPosts
        self.platformMetrics = platformMetrics
        self.averageRetentionCurve = averageRetentionCurve
        self.averageWatchTime = averageWatchTime
        self.dropOffPoint = dropOffPoint
        self.predictedWindows = predictedWindows
        self.suggestedSchedule = suggestedSchedule
        self.trendingTopics = trendingTopics
    }
}

// MARK: - Empty Data

extension CreativeDimensionData {
    public static var empty: CreativeDimensionData {
        CreativeDimensionData()
    }

    public var isEmpty: Bool {
        totalReach == 0 && recentPosts.isEmpty && followerCount == 0
    }
}

// MARK: - Preview Data

#if DEBUG
extension CreativeDimensionData {

    /// Preview data for SwiftUI previews
    public static var preview: CreativeDimensionData {
        let calendar = Calendar.current
        let now = Date()

        // Generate sparkline data
        let reachSparkline = (0..<30).map { _ in Int.random(in: 20000...50000) }
        let engagementSparkline = (0..<30).map { _ in Double.random(in: 3.5...5.5) }
        let followerSparkline = (0..<30).map { i in 22500 + i * 30 + Int.random(in: -20...50) }

        // Generate performance time series
        let performanceData = (0..<30).map { i -> PerformanceDataPoint in
            let date = calendar.date(byAdding: .day, value: -29 + i, to: now)!
            return PerformanceDataPoint(
                date: date,
                reach: Int.random(in: 30000...120000),
                engagement: Double.random(in: 3.0...6.0),
                followers: 22500 + i * 30
            )
        }

        // Sample posts
        let samplePosts = [
            ContentPost(
                id: "1",
                platform: .instagram,
                type: .reel,
                postedAt: calendar.date(byAdding: .day, value: -2, to: now)!,
                caption: "Building the future of productivity",
                reach: 45247,
                impressions: 67892,
                likes: 2147,
                comments: 234,
                shares: 89,
                saves: 189,
                engagementRate: 4.8,
                performanceVsAverage: 156,
                isViral: true,
                viralThresholdTime: 6 * 3600,
                hourlyPerformance: [1000, 8000, 25000, 38000, 42000, 44000, 45000],
                peakTime: 1,
                causalFactors: [
                    CausalFactor(name: "Post Time", category: .timing, rating: 5, value: "3:42pm", contribution: 0.35, explanation: "Optimal window"),
                    CausalFactor(name: "Content Length", category: .content, rating: 4, value: "32 sec", contribution: 0.25, explanation: "Ideal duration"),
                    CausalFactor(name: "Trending Audio", category: .trend, rating: 3, value: "+12%", contribution: 0.20, explanation: "Boost from audio"),
                    CausalFactor(name: "Your Energy", category: .creatorState, rating: 4, value: "HRV: 52ms", contribution: 0.20, explanation: "Good mood")
                ],
                keyInsight: "Posted during peak follower activity window with trending audio. Your HRV was elevated, correlating with higher creative output.",
                hrvAtPosting: 52,
                moodAtPosting: "Good",
                energyAtPosting: 78
            ),
            ContentPost(
                id: "2",
                platform: .instagram,
                type: .reel,
                postedAt: calendar.date(byAdding: .day, value: -4, to: now)!,
                reach: 32147,
                impressions: 48320,
                likes: 1542,
                comments: 187,
                shares: 56,
                saves: 143,
                engagementRate: 4.5,
                performanceVsAverage: 42,
                hourlyPerformance: [800, 5000, 18000, 28000, 30000, 31500, 32000],
                peakTime: 1.5
            ),
            ContentPost(
                id: "3",
                platform: .youtube,
                type: .video,
                postedAt: calendar.date(byAdding: .day, value: -6, to: now)!,
                reach: 28742,
                impressions: 35890,
                likes: 1287,
                comments: 98,
                shares: 45,
                saves: 89,
                engagementRate: 4.2,
                performanceVsAverage: 0,
                hourlyPerformance: [500, 3000, 12000, 20000, 25000, 27000, 28000],
                peakTime: 2
            ),
            ContentPost(
                id: "4",
                platform: .instagram,
                type: .reel,
                postedAt: calendar.date(byAdding: .day, value: -8, to: now)!,
                reach: 15342,
                impressions: 21480,
                likes: 687,
                comments: 54,
                shares: 23,
                saves: 45,
                engagementRate: 3.8,
                performanceVsAverage: -23,
                hourlyPerformance: [300, 2000, 8000, 12000, 14000, 15000, 15300],
                peakTime: 1
            ),
            ContentPost(
                id: "5",
                platform: .tiktok,
                type: .short,
                postedAt: calendar.date(byAdding: .day, value: -10, to: now)!,
                reach: 12847,
                impressions: 18920,
                likes: 542,
                comments: 43,
                shares: 18,
                saves: 32,
                engagementRate: 3.5,
                performanceVsAverage: -31,
                hourlyPerformance: [200, 1500, 6000, 10000, 11500, 12500, 12800],
                peakTime: 1
            )
        ]

        // Platform metrics
        let platforms = [
            PlatformMetrics(platform: .instagram, followerCount: 23418, engagementRate: 4.8, reachPercentage: 67),
            PlatformMetrics(platform: .youtube, followerCount: 12142, engagementRate: 6.2, reachPercentage: 24),
            PlatformMetrics(platform: .tiktok, followerCount: 8247, engagementRate: 8.1, reachPercentage: 9)
        ]

        // Suggested schedule
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        let schedule = [
            ScheduledPost(
                scheduledTime: calendar.date(bySettingHour: 15, minute: 15, second: 0, of: tomorrow)!,
                platform: .instagram,
                type: .reel,
                windowType: "Primary window",
                confidence: 89
            ),
            ScheduledPost(
                scheduledTime: calendar.date(bySettingHour: 17, minute: 0, second: 0, of: tomorrow)!,
                platform: .youtube,
                type: .short,
                windowType: "Secondary window",
                confidence: 72
            ),
            ScheduledPost(
                scheduledTime: calendar.date(bySettingHour: 19, minute: 30, second: 0, of: tomorrow)!,
                platform: .tiktok,
                type: .short,
                windowType: "Evening engagement peak",
                confidence: 68
            )
        ]

        // Predicted windows
        let windows = [
            ContentWindow(
                date: tomorrow,
                startTime: DateComponents(hour: 15, minute: 15),
                endTime: DateComponents(hour: 16, minute: 40),
                platform: .instagram,
                confidence: 91,
                predictedReachBoost: 34,
                predictedEngagementBoost: 28,
                reason: "Peak follower activity"
            )
        ]

        return CreativeDimensionData(
            totalReach: 847234,
            reachTrend: 12.3,
            reachSparkline: reachSparkline,
            engagementRate: 4.7,
            engagementTrend: 0.3,
            engagementSparkline: engagementSparkline,
            followerCount: 23418,
            followerGrowth: 847,
            followerSparkline: followerSparkline,
            growthRate: 2.1,
            growthStatus: .strong,
            performanceTimeSeries: performanceData,
            selectedTimeRange: .month,
            postingStreak: 12,
            longestStreak: 28,
            bestPostingTime: DateComponents(hour: 15, minute: 15),
            mostActiveDay: .wednesday,
            averagePostsPerWeek: 4.2,
            recentPosts: samplePosts,
            viralPosts: [samplePosts[0]],
            underperformingPosts: [samplePosts[3], samplePosts[4]],
            platformMetrics: platforms,
            averageRetentionCurve: [100, 85, 72, 58, 48, 42, 38, 35],
            averageWatchTime: 68,
            dropOffPoint: 32,
            predictedWindows: windows,
            suggestedSchedule: schedule,
            trendingTopics: ["productivity tips", "morning routines", "focus hacks"]
        )
    }
}
#endif
