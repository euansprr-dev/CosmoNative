// CosmoOS/UI/Sanctuary/Dimensions/Cognitive/CognitiveDimensionData.swift
// Cognitive Dimension Data Models - "The Mind Core"
// Phase 3: Following SANCTUARY_UI_SPEC_V2.md section 3.1

import Foundation
import GRDB

// MARK: - NELO Status

/// Status derived from Neuro-Energetic Load Oscillation score
public enum NELOStatus: String, Codable, CaseIterable, Sendable {
    case balanced   // Optimal range (35-55)
    case elevated   // High cognitive load (>55)
    case depleted   // Low energy (<35)

    /// Color for UI display
    var color: String {
        switch self {
        case .balanced: return "#10B981"  // Green
        case .elevated: return "#F59E0B"  // Amber
        case .depleted: return "#EF4444"  // Red
        }
    }

    /// Human-readable description
    var displayName: String {
        rawValue.capitalized
    }

    /// Icon for status display
    var iconName: String {
        switch self {
        case .balanced: return "checkmark.circle.fill"
        case .elevated: return "exclamationmark.triangle.fill"
        case .depleted: return "battery.25"
        }
    }

    /// Initialize from NELO score value
    public static func from(score: Double) -> NELOStatus {
        switch score {
        case ..<35: return .depleted
        case 35...55: return .balanced
        default: return .elevated
        }
    }
}

// MARK: - Window Status

/// Status of predicted cognitive windows
public enum CognitiveWindowStatus: String, Codable, CaseIterable, Sendable {
    case inWindow     // Currently in an optimal window
    case approaching  // Window coming up within 30 minutes
    case passed       // Optimal windows for today have passed
    case scheduled    // Future window scheduled

    var displayName: String {
        switch self {
        case .inWindow: return "In Window"
        case .approaching: return "Approaching"
        case .passed: return "Passed"
        case .scheduled: return "Scheduled"
        }
    }
}

// MARK: - Task Type

/// Types of deep work tasks
public enum CognitiveTaskType: String, Codable, CaseIterable, Sendable {
    case coding
    case writing
    case research
    case planning
    case reading
    case design
    case analysis
    case meeting

    var displayName: String {
        rawValue.capitalized
    }

    var iconName: String {
        switch self {
        case .coding: return "chevron.left.forwardslash.chevron.right"
        case .writing: return "pencil.line"
        case .research: return "magnifyingglass"
        case .planning: return "map"
        case .reading: return "book.fill"
        case .design: return "paintbrush.fill"
        case .analysis: return "chart.bar.fill"
        case .meeting: return "person.2.fill"
        }
    }

    /// Color for task type visualization
    var colorHex: String {
        switch self {
        case .coding: return "#6366F1"   // Indigo
        case .writing: return "#8B5CF6"  // Purple
        case .research: return "#22C55E" // Green
        case .planning: return "#F59E0B" // Amber
        case .reading: return "#3B82F6"  // Blue
        case .design: return "#EC4899"   // Pink
        case .analysis: return "#14B8A6" // Teal
        case .meeting: return "#F97316"  // Orange
        }
    }
}

// MARK: - Interruption Source

/// Sources of cognitive interruptions
public enum InterruptionSource: String, Codable, CaseIterable, Sendable {
    case slack
    case meeting
    case notification
    case selfInitiated = "self"
    case email
    case phone
    case person
    case system

    var displayName: String {
        switch self {
        case .slack: return "Slack"
        case .meeting: return "Meeting"
        case .notification: return "Notification"
        case .selfInitiated: return "Self"
        case .email: return "Email"
        case .phone: return "Phone"
        case .person: return "Person"
        case .system: return "System"
        }
    }

    var iconName: String {
        switch self {
        case .slack: return "bubble.left.and.bubble.right.fill"
        case .meeting: return "video.fill"
        case .notification: return "bell.fill"
        case .selfInitiated: return "person.fill"
        case .email: return "envelope.fill"
        case .phone: return "phone.fill"
        case .person: return "person.wave.2.fill"
        case .system: return "gear"
        }
    }

    var colorHex: String {
        switch self {
        case .slack: return "#4A154B"     // Slack purple
        case .meeting: return "#0B57D0"   // Google blue
        case .notification: return "#EF4444"
        case .selfInitiated: return "#6B7280"
        case .email: return "#F59E0B"
        case .phone: return "#22C55E"
        case .person: return "#8B5CF6"
        case .system: return "#3B82F6"
        }
    }
}

// MARK: - Deep Work Session

/// Represents a focused work session
public struct DeepWorkSession: Codable, Identifiable, Sendable {
    public let id: UUID
    public let startTime: Date
    public var endTime: Date?
    public let taskType: CognitiveTaskType
    public var qualityScore: Double      // 0-100
    public var flowMinutes: Int          // Time in flow state
    public var interruptionCount: Int
    public var notes: String?

    /// Duration in minutes
    public var durationMinutes: Int {
        let end = endTime ?? Date()
        return Int(end.timeIntervalSince(startTime) / 60)
    }

    /// Whether session is currently active
    public var isActive: Bool {
        endTime == nil
    }

    /// Flow percentage (flow minutes / total duration)
    public var flowPercentage: Double {
        guard durationMinutes > 0 else { return 0 }
        return min(100, Double(flowMinutes) / Double(durationMinutes) * 100)
    }

    public init(
        id: UUID = UUID(),
        startTime: Date = Date(),
        endTime: Date? = nil,
        taskType: CognitiveTaskType,
        qualityScore: Double = 0,
        flowMinutes: Int = 0,
        interruptionCount: Int = 0,
        notes: String? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.taskType = taskType
        self.qualityScore = qualityScore
        self.flowMinutes = flowMinutes
        self.interruptionCount = interruptionCount
        self.notes = notes
    }
}

// MARK: - Cognitive Window

/// Predicted optimal performance window
public struct CognitiveWindow: Codable, Identifiable, Sendable {
    public let id: UUID
    public let startTime: DateComponents
    public let endTime: DateComponents
    public let confidence: Double        // 0-100
    public let isPrimary: Bool
    public let recommendedTaskTypes: [CognitiveTaskType]
    public let basedOn: [String]         // Contributing factors

    /// Duration in minutes
    public var durationMinutes: Int {
        guard let startHour = startTime.hour,
              let startMinute = startTime.minute,
              let endHour = endTime.hour,
              let endMinute = endTime.minute else {
            return 0
        }

        let startTotal = startHour * 60 + startMinute
        let endTotal = endHour * 60 + endMinute
        return max(0, endTotal - startTotal)
    }

    /// Formatted time range (e.g., "2:00pm - 4:00pm")
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
                return "\(h):00\(suffix)"
            }
            return "\(h):\(String(format: "%02d", minute))\(suffix)"
        }

        return "\(format(hour: startHour, minute: startMinute)) - \(format(hour: endHour, minute: endMinute))"
    }

    public init(
        id: UUID = UUID(),
        startTime: DateComponents,
        endTime: DateComponents,
        confidence: Double,
        isPrimary: Bool,
        recommendedTaskTypes: [CognitiveTaskType],
        basedOn: [String]
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.isPrimary = isPrimary
        self.recommendedTaskTypes = recommendedTaskTypes
        self.basedOn = basedOn
    }
}

// MARK: - Interruption

/// Represents a cognitive interruption event
public struct CognitiveInterruption: Codable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let source: InterruptionSource
    public let app: String?
    public var recoveryMinutes: Double
    public let severityScore: Double     // 0-1

    /// Formatted time (e.g., "10:32am")
    public var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        return formatter.string(from: timestamp).lowercased()
    }

    /// Color based on severity
    public var severityColor: String {
        switch severityScore {
        case 0..<0.3: return "#10B981"   // Green - minor
        case 0.3..<0.7: return "#F59E0B" // Amber - moderate
        default: return "#EF4444"         // Red - severe
        }
    }

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        source: InterruptionSource,
        app: String? = nil,
        recoveryMinutes: Double,
        severityScore: Double
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.app = app
        self.recoveryMinutes = recoveryMinutes
        self.severityScore = min(1, max(0, severityScore))
    }
}

// MARK: - Cognitive Correlation

/// Correlation specific to cognitive metrics
public struct CognitiveCorrelation: Codable, Identifiable, Sendable {
    public let id: UUID
    public let sourceMetric: String
    public let targetMetric: String
    public let coefficient: Double       // -1 to 1
    public let strength: CorrelationStrength
    public let trend: Trend
    public let sparklineData: [Double]   // Last 7 days
    public let actionInsight: String     // "When X > Y, then Z"
    public let sampleSize: Int

    /// Formatted coefficient (e.g., "r = 0.73")
    public var formattedCoefficient: String {
        "r = \(String(format: "%.2f", coefficient))"
    }

    /// Human-readable title (e.g., "HRV → Focus")
    public var title: String {
        "\(formatMetricName(sourceMetric)) → \(formatMetricName(targetMetric))"
    }

    private func formatMetricName(_ name: String) -> String {
        name.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    public init(
        id: UUID = UUID(),
        sourceMetric: String,
        targetMetric: String,
        coefficient: Double,
        strength: CorrelationStrength,
        trend: Trend,
        sparklineData: [Double],
        actionInsight: String,
        sampleSize: Int
    ) {
        self.id = id
        self.sourceMetric = sourceMetric
        self.targetMetric = targetMetric
        self.coefficient = min(1, max(-1, coefficient))
        self.strength = strength
        self.trend = trend
        self.sparklineData = sparklineData
        self.actionInsight = actionInsight
        self.sampleSize = sampleSize
    }
}

// MARK: - Cognitive Dimension Data

/// Complete data model for the Cognitive Dimension view
public struct CognitiveDimensionData: Sendable {

    // MARK: - Core Metrics

    /// Overall cognitive index (0-100)
    public var cognitiveIndex: Double

    /// Neuro-Energetic Load Oscillation score
    public var neloScore: Double

    /// Real-time waveform data for NELO visualization
    public var neloWaveform: [Double]

    /// Current NELO status
    public var neloStatus: NELOStatus

    /// Current focus quality (0-100)
    public var focusIndex: Double

    // MARK: - Focus Stability (24-hour breakdown)

    /// Focus stability percentage by hour (0-23)
    public var focusStabilityByHour: [Int: Double]

    /// Current cognitive load (0-100)
    public var cognitiveLoadCurrent: Double

    /// Cognitive load history (last 60 minutes)
    public var cognitiveLoadHistory: [Double]

    // MARK: - Deep Work Sessions

    /// Today's deep work sessions
    public var deepWorkSessions: [DeepWorkSession]

    /// Total deep work time today
    public var totalDeepWorkToday: TimeInterval

    /// Average quality score today
    public var averageQualityToday: Double

    /// Predicted remaining capacity
    public var predictedCapacityRemaining: TimeInterval

    // MARK: - Predictions

    /// Predicted optimal windows
    public var predictedOptimalWindows: [CognitiveWindow]

    /// Current window status
    public var currentWindowStatus: CognitiveWindowStatus

    // MARK: - Interruptions

    /// Today's interruptions
    public var interruptions: [CognitiveInterruption]

    /// Total interruption count
    public var totalInterruptionsToday: Int

    /// Average recovery time in minutes
    public var averageRecoveryTime: TimeInterval

    /// Estimated minutes lost to interruptions
    public var focusCostMinutes: Int

    /// Top disruptors ranked by count
    public var topDisruptors: [(source: InterruptionSource, count: Int)]

    // MARK: - Correlations

    /// Top cognitive correlations
    public var topCorrelations: [CognitiveCorrelation]

    // MARK: - Journal Integration

    /// Insight markers extracted from journal today
    public var journalInsightMarkersToday: Int

    /// Reflection depth score (0-10)
    public var reflectionDepthScore: Double

    /// Detected themes from journal
    public var detectedThemes: [String]

    /// Journal excerpt
    public var journalExcerpt: String?

    // MARK: - Computed Properties

    /// Formatted total deep work (e.g., "5h 57m")
    public var formattedDeepWork: String {
        let hours = Int(totalDeepWorkToday / 3600)
        let minutes = Int((totalDeepWorkToday.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    /// Formatted capacity remaining (e.g., "2h")
    public var formattedCapacityRemaining: String {
        let hours = Int(predictedCapacityRemaining / 3600)
        let minutes = Int((predictedCapacityRemaining.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        }
        return "\(minutes)m"
    }

    /// Active session (if any)
    public var activeSession: DeepWorkSession? {
        deepWorkSessions.first { $0.isActive }
    }

    /// Primary optimal window (if any)
    public var primaryWindow: CognitiveWindow? {
        predictedOptimalWindows.first { $0.isPrimary }
    }

    /// Current hour stability (0-100)
    public var currentHourStability: Double {
        let hour = Calendar.current.component(.hour, from: Date())
        return focusStabilityByHour[hour] ?? 0
    }

    // MARK: - Initialization

    public init(
        cognitiveIndex: Double = 0,
        neloScore: Double = 42.3,
        neloWaveform: [Double] = [],
        neloStatus: NELOStatus = .balanced,
        focusIndex: Double = 0,
        focusStabilityByHour: [Int: Double] = [:],
        cognitiveLoadCurrent: Double = 0,
        cognitiveLoadHistory: [Double] = [],
        deepWorkSessions: [DeepWorkSession] = [],
        totalDeepWorkToday: TimeInterval = 0,
        averageQualityToday: Double = 0,
        predictedCapacityRemaining: TimeInterval = 0,
        predictedOptimalWindows: [CognitiveWindow] = [],
        currentWindowStatus: CognitiveWindowStatus = .scheduled,
        interruptions: [CognitiveInterruption] = [],
        totalInterruptionsToday: Int = 0,
        averageRecoveryTime: TimeInterval = 0,
        focusCostMinutes: Int = 0,
        topDisruptors: [(source: InterruptionSource, count: Int)] = [],
        topCorrelations: [CognitiveCorrelation] = [],
        journalInsightMarkersToday: Int = 0,
        reflectionDepthScore: Double = 0,
        detectedThemes: [String] = [],
        journalExcerpt: String? = nil
    ) {
        self.cognitiveIndex = cognitiveIndex
        self.neloScore = neloScore
        self.neloWaveform = neloWaveform
        self.neloStatus = neloStatus
        self.focusIndex = focusIndex
        self.focusStabilityByHour = focusStabilityByHour
        self.cognitiveLoadCurrent = cognitiveLoadCurrent
        self.cognitiveLoadHistory = cognitiveLoadHistory
        self.deepWorkSessions = deepWorkSessions
        self.totalDeepWorkToday = totalDeepWorkToday
        self.averageQualityToday = averageQualityToday
        self.predictedCapacityRemaining = predictedCapacityRemaining
        self.predictedOptimalWindows = predictedOptimalWindows
        self.currentWindowStatus = currentWindowStatus
        self.interruptions = interruptions
        self.totalInterruptionsToday = totalInterruptionsToday
        self.averageRecoveryTime = averageRecoveryTime
        self.focusCostMinutes = focusCostMinutes
        self.topDisruptors = topDisruptors
        self.topCorrelations = topCorrelations
        self.journalInsightMarkersToday = journalInsightMarkersToday
        self.reflectionDepthScore = reflectionDepthScore
        self.detectedThemes = detectedThemes
        self.journalExcerpt = journalExcerpt
    }
}

// MARK: - Cognitive Prediction

/// Prediction for optimal cognitive performance
public struct CognitivePrediction: Codable, Sendable {
    public let id: UUID
    public let message: String
    public let confidence: Double        // 0-100
    public let basedOn: [String]         // Contributing factors
    public let recommendedAction: String?
    public let impact: String?           // e.g., "+23% productivity"

    public init(
        id: UUID = UUID(),
        message: String,
        confidence: Double,
        basedOn: [String],
        recommendedAction: String? = nil,
        impact: String? = nil
    ) {
        self.id = id
        self.message = message
        self.confidence = confidence
        self.basedOn = basedOn
        self.recommendedAction = recommendedAction
        self.impact = impact
    }
}

// MARK: - Focus Stability Segment

/// Segment for 24-hour focus stability ring
public struct FocusStabilitySegment: Identifiable, Sendable {
    public let id: Int  // Hour (0-23)
    public let hour: Int
    public let stability: Double  // 0-100
    public let isSleep: Bool
    public let isCurrentHour: Bool

    /// Color based on stability score
    public var color: String {
        if isSleep { return "#4B5563" }  // Gray for sleep

        switch stability {
        case 80...: return "#10B981"     // Green - stable
        case 50..<80: return "#F59E0B"   // Yellow - moderate
        default: return "#EF4444"         // Red - unstable
        }
    }

    public init(hour: Int, stability: Double, isSleep: Bool, isCurrentHour: Bool) {
        self.id = hour
        self.hour = hour
        self.stability = stability
        self.isSleep = isSleep
        self.isCurrentHour = isCurrentHour
    }
}

// MARK: - Preview Data

#if DEBUG
extension CognitiveDimensionData {

    /// Preview data for SwiftUI previews
    public static var preview: CognitiveDimensionData {
        let now = Date()
        let calendar = Calendar.current

        // Generate focus stability by hour
        var stability: [Int: Double] = [:]
        for hour in 0..<24 {
            if hour < 6 || hour > 22 {
                stability[hour] = 0  // Sleep
            } else if hour >= 9 && hour <= 11 {
                stability[hour] = Double.random(in: 85...95)
            } else if hour >= 14 && hour <= 16 {
                stability[hour] = Double.random(in: 80...92)
            } else {
                stability[hour] = Double.random(in: 50...75)
            }
        }

        // Sample deep work sessions
        let sessions: [DeepWorkSession] = [
            DeepWorkSession(
                startTime: calendar.date(bySettingHour: 9, minute: 30, second: 0, of: now)!,
                endTime: calendar.date(bySettingHour: 11, minute: 45, second: 0, of: now)!,
                taskType: .coding,
                qualityScore: 87,
                flowMinutes: 95,
                interruptionCount: 2
            ),
            DeepWorkSession(
                startTime: calendar.date(bySettingHour: 14, minute: 0, second: 0, of: now)!,
                endTime: calendar.date(bySettingHour: 17, minute: 42, second: 0, of: now)!,
                taskType: .writing,
                qualityScore: 92,
                flowMinutes: 180,
                interruptionCount: 1
            )
        ]

        // Sample windows
        let windows: [CognitiveWindow] = [
            CognitiveWindow(
                startTime: DateComponents(hour: 14, minute: 0),
                endTime: DateComponents(hour: 16, minute: 0),
                confidence: 89,
                isPrimary: true,
                recommendedTaskTypes: [.coding, .writing],
                basedOn: ["HRV pattern", "sleep quality", "historical performance"]
            ),
            CognitiveWindow(
                startTime: DateComponents(hour: 9, minute: 30),
                endTime: DateComponents(hour: 11, minute: 0),
                confidence: 72,
                isPrimary: false,
                recommendedTaskTypes: [.planning, .reading],
                basedOn: ["morning routine", "caffeine timing"]
            )
        ]

        // Sample interruptions
        let interruptions: [CognitiveInterruption] = [
            CognitiveInterruption(
                timestamp: calendar.date(bySettingHour: 10, minute: 15, second: 0, of: now)!,
                source: .slack,
                app: "Slack",
                recoveryMinutes: 4.2,
                severityScore: 0.6
            ),
            CognitiveInterruption(
                timestamp: calendar.date(bySettingHour: 10, minute: 45, second: 0, of: now)!,
                source: .slack,
                app: "Slack",
                recoveryMinutes: 3.8,
                severityScore: 0.5
            ),
            CognitiveInterruption(
                timestamp: calendar.date(bySettingHour: 12, minute: 30, second: 0, of: now)!,
                source: .meeting,
                recoveryMinutes: 8.5,
                severityScore: 0.8
            )
        ]

        // Sample correlations
        let correlations: [CognitiveCorrelation] = [
            CognitiveCorrelation(
                sourceMetric: "HRV",
                targetMetric: "Focus",
                coefficient: 0.73,
                strength: .strong,
                trend: .up,
                sparklineData: [42, 48, 45, 52, 55, 51, 58],
                actionInsight: "When HRV >45ms, focus +23%",
                sampleSize: 42
            ),
            CognitiveCorrelation(
                sourceMetric: "Sleep",
                targetMetric: "Clarity",
                coefficient: 0.68,
                strength: .strong,
                trend: .up,
                sparklineData: [6.5, 7.2, 6.8, 7.5, 7.8, 7.2, 8.1],
                actionInsight: "When sleep >7h, clarity +31%",
                sampleSize: 38
            ),
            CognitiveCorrelation(
                sourceMetric: "Caffeine",
                targetMetric: "Alertness",
                coefficient: 0.45,
                strength: .moderate,
                trend: .stable,
                sparklineData: [2, 3, 2, 2, 3, 2, 2],
                actionInsight: "Optimal: 2pm caffeine",
                sampleSize: 28
            ),
            CognitiveCorrelation(
                sourceMetric: "Breaks",
                targetMetric: "Sustainability",
                coefficient: 0.61,
                strength: .strong,
                trend: .up,
                sparklineData: [3, 4, 5, 4, 6, 5, 7],
                actionInsight: "Every 90min, sustain +18%",
                sampleSize: 35
            )
        ]

        // Generate NELO waveform
        var waveform: [Double] = []
        for i in 0..<60 {
            let base = 42.3
            let wave = sin(Double(i) / 10) * 5
            let noise = Double.random(in: -2...2)
            waveform.append(base + wave + noise)
        }

        return CognitiveDimensionData(
            cognitiveIndex: 78.4,
            neloScore: 42.3,
            neloWaveform: waveform,
            neloStatus: .balanced,
            focusIndex: 91,
            focusStabilityByHour: stability,
            cognitiveLoadCurrent: 65,
            cognitiveLoadHistory: Array(repeating: 0, count: 60).map { _ in Double.random(in: 40...80) },
            deepWorkSessions: sessions,
            totalDeepWorkToday: 5 * 3600 + 57 * 60,  // 5h 57m
            averageQualityToday: 89,
            predictedCapacityRemaining: 2 * 3600,    // 2h
            predictedOptimalWindows: windows,
            currentWindowStatus: .inWindow,
            interruptions: interruptions,
            totalInterruptionsToday: 8,
            averageRecoveryTime: 4.2 * 60,           // 4.2 minutes
            focusCostMinutes: 34,
            topDisruptors: [
                (.slack, 5),
                (.meeting, 2),
                (.notification, 1)
            ],
            topCorrelations: correlations,
            journalInsightMarkersToday: 7,
            reflectionDepthScore: 8.2,
            detectedThemes: ["delegation", "focus blocks", "morning routine"],
            journalExcerpt: "Recurring focus on delegation patterns..."
        )
    }
}
#endif
