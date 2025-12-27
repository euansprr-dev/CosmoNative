// CosmoOS/UI/Plannerum/PlannerumTokens.swift
// Plannerum Design System - Complete design tokens for the temporal realm
// Apple-level polish matching Sanctuary aesthetic

import SwiftUI
import QuartzCore

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - PLANNERIUM COLOR SYSTEM
// ═══════════════════════════════════════════════════════════════════════════════

/// Complete color palette for the Plannerium temporal interface
public struct PlannerumColors {

    // ─────────────────────────────────────────────────────────────────────────
    // PRIMARY PALETTE - The signature Plannerium violet
    // ─────────────────────────────────────────────────────────────────────────

    /// Primary violet - temporal essence (#8B5CF6)
    public static let primary = Color(red: 139/255, green: 92/255, blue: 246/255)

    /// Dark violet for emphasis (#7C3AED)
    public static let primaryDark = Color(red: 124/255, green: 58/255, blue: 237/255)

    /// Light violet for highlights (#A78BFA)
    public static let primaryLight = Color(red: 167/255, green: 139/255, blue: 250/255)

    /// Glow color for active states
    public static let glow = Color(red: 139/255, green: 92/255, blue: 246/255).opacity(0.6)

    // ─────────────────────────────────────────────────────────────────────────
    // NOW MARKER - The living present
    // ─────────────────────────────────────────────────────────────────────────

    /// Current time marker - pulsing green (#22C55E)
    public static let nowMarker = Color(red: 34/255, green: 197/255, blue: 94/255)

    /// Now marker glow
    public static let nowGlow = Color(red: 34/255, green: 197/255, blue: 94/255).opacity(0.5)

    // ─────────────────────────────────────────────────────────────────────────
    // OVERDUE - Urgency and warning
    // ─────────────────────────────────────────────────────────────────────────

    /// Overdue tasks - urgent red (#EF4444)
    public static let overdue = Color(red: 239/255, green: 68/255, blue: 68/255)

    /// Overdue glow
    public static let overdueGlow = Color(red: 239/255, green: 68/255, blue: 68/255).opacity(0.4)

    // ─────────────────────────────────────────────────────────────────────────
    // BLOCK TYPE COLORS - Dimension-aligned
    // ─────────────────────────────────────────────────────────────────────────

    /// Deep Work blocks - cognitive focus (Indigo #6366F1)
    public static let deepWork = Color(red: 99/255, green: 102/255, blue: 241/255)

    /// Creative blocks - creative output (Amber #F59E0B)
    public static let creative = Color(red: 245/255, green: 158/255, blue: 11/255)

    /// Output blocks - production work (Teal #14B8A6)
    public static let output = Color(red: 20/255, green: 184/255, blue: 166/255)

    /// Planning blocks - strategic thinking (Violet #8B5CF6)
    public static let planning = Color(red: 139/255, green: 92/255, blue: 246/255)

    /// Training blocks - learning & development (Pink #EC4899)
    public static let training = Color(red: 236/255, green: 72/255, blue: 153/255)

    /// Rest blocks - recovery & breaks (Emerald #10B981)
    public static let rest = Color(red: 16/255, green: 185/255, blue: 129/255)

    /// Administrative blocks - admin tasks (Blue #3B82F6)
    public static let administrative = Color(red: 59/255, green: 130/255, blue: 246/255)

    /// Meeting blocks - collaboration (Sky #0EA5E9)
    public static let meeting = Color(red: 14/255, green: 165/255, blue: 233/255)

    /// Review blocks - assessment (Slate #64748B)
    public static let review = Color(red: 100/255, green: 116/255, blue: 139/255)

    // ─────────────────────────────────────────────────────────────────────────
    // INBOX COLORS - Stream identification
    // ─────────────────────────────────────────────────────────────────────────

    /// Ideas inbox (knowledge dimension)
    public static let ideasInbox = Color(red: 139/255, green: 92/255, blue: 246/255)

    /// Tasks inbox (cognitive dimension)
    public static let tasksInbox = Color(red: 99/255, green: 102/255, blue: 241/255)

    /// Content inbox (creative dimension)
    public static let contentInbox = Color(red: 245/255, green: 158/255, blue: 11/255)

    /// Project inbox
    public static let projectInbox = Color(red: 20/255, green: 184/255, blue: 166/255)

    // ─────────────────────────────────────────────────────────────────────────
    // TIMELINE COLORS
    // ─────────────────────────────────────────────────────────────────────────

    /// Open/unscheduled time
    public static let openTime = Color.white.opacity(0.03)

    /// Past time (dimmed)
    public static let pastTime = Color.white.opacity(0.015)

    /// Hour labels
    public static let hourLabel = Color.white.opacity(0.4)

    /// Hour grid lines
    public static let hourLine = Color.white.opacity(0.06)

    /// Half-hour lines (subtle)
    public static let halfHourLine = Color.white.opacity(0.03)

    // ─────────────────────────────────────────────────────────────────────────
    // SURFACE COLORS - Glass morphism
    // ─────────────────────────────────────────────────────────────────────────

    /// Primary background (void #0A0A0F)
    public static let voidPrimary = Color(red: 10/255, green: 10/255, blue: 15/255)

    /// Secondary background (#0C0C12)
    public static let voidSecondary = Color(red: 12/255, green: 12/255, blue: 18/255)

    /// Glass surface primary (#12121A)
    public static let glassPrimary = Color(red: 18/255, green: 18/255, blue: 26/255).opacity(0.9)

    /// Glass surface secondary (#18182A)
    public static let glassSecondary = Color(red: 24/255, green: 24/255, blue: 42/255).opacity(0.85)

    /// Glass border
    public static let glassBorder = Color.white.opacity(0.06)

    /// Glass border hover
    public static let glassBorderHover = Color.white.opacity(0.12)

    // ─────────────────────────────────────────────────────────────────────────
    // XP COLORS
    // ─────────────────────────────────────────────────────────────────────────

    /// XP primary gold (#FFD700)
    public static let xpGold = Color(red: 255/255, green: 215/255, blue: 0/255)

    /// Alias for xpGold
    public static let xpPrimary = xpGold

    /// Alias for voidPrimary
    public static let background = voidPrimary

    /// XP glow
    public static let xpGlow = Color(red: 255/255, green: 215/255, blue: 0/255).opacity(0.4)

    /// XP tracer particle (#FFC107)
    public static let xpTracer = Color(red: 255/255, green: 193/255, blue: 7/255)

    // ─────────────────────────────────────────────────────────────────────────
    // TEXT COLORS
    // ─────────────────────────────────────────────────────────────────────────

    public static let textPrimary = Color.white.opacity(0.95)
    public static let textSecondary = Color.white.opacity(0.75)
    public static let textTertiary = Color.white.opacity(0.55)
    public static let textMuted = Color.white.opacity(0.35)
    public static let textDisabled = Color.white.opacity(0.2)
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - PLANNERIUM LAYOUT SYSTEM
// ═══════════════════════════════════════════════════════════════════════════════

/// Layout constants for the Plannerium interface
public struct PlannerumLayout {

    // ─────────────────────────────────────────────────────────────────────────
    // MAIN STRUCTURE
    // ─────────────────────────────────────────────────────────────────────────

    /// Header height with XP module
    public static let headerHeight: CGFloat = 88

    /// Inbox rail width
    public static let inboxRailWidth: CGFloat = 260

    /// Inbox rail collapsed width
    public static let inboxRailCollapsed: CGFloat = 56

    /// Bottom focus bar height
    public static let focusBarHeight: CGFloat = 72

    /// Content padding (horizontal)
    public static let contentPadding: CGFloat = 24

    /// Section divider height
    public static let dividerHeight: CGFloat = 1

    // ─────────────────────────────────────────────────────────────────────────
    // DAY VIEW (TIMELINE)
    // ─────────────────────────────────────────────────────────────────────────

    /// Hour row height (pixels per hour)
    public static let hourRowHeight: CGFloat = 64

    /// Time label width
    public static let timeLabelWidth: CGFloat = 56

    /// Time block minimum height
    public static let blockMinHeight: CGFloat = 48

    /// Time block corner radius
    public static let blockCornerRadius: CGFloat = 12

    /// Time block accent bar width
    public static let blockAccentWidth: CGFloat = 4

    /// Now bar height
    public static let nowBarHeight: CGFloat = 2

    /// Now bar glow radius
    public static let nowBarGlowRadius: CGFloat = 40

    /// Now bar particle count
    public static let nowBarParticleCount: Int = 24

    // ─────────────────────────────────────────────────────────────────────────
    // WEEK VIEW (ARC)
    // ─────────────────────────────────────────────────────────────────────────

    /// Day orb size
    public static let dayOrbSize: CGFloat = 72

    /// Day orb hover size
    public static let dayOrbSizeHover: CGFloat = 84

    /// Arc curve depth
    public static let arcHeight: CGFloat = 140

    /// Satellite orb size
    public static let satelliteSize: CGFloat = 14

    // ─────────────────────────────────────────────────────────────────────────
    // MONTH VIEW (DENSITY)
    // ─────────────────────────────────────────────────────────────────────────

    /// Day cell size
    public static let dayCellSize: CGFloat = 48

    /// Day cell spacing
    public static let dayCellSpacing: CGFloat = 6

    /// Week row height
    public static let weekRowHeight: CGFloat = 56

    // ─────────────────────────────────────────────────────────────────────────
    // INBOX RAIL
    // ─────────────────────────────────────────────────────────────────────────

    /// Inbox stream row height
    public static let inboxRowHeight: CGFloat = 48

    /// Inbox icon size
    public static let inboxIconSize: CGFloat = 20

    /// Inbox item row height (expanded)
    public static let inboxItemRowHeight: CGFloat = 40

    /// Inbox item max visible
    public static let inboxMaxVisibleItems: Int = 5

    /// Overdue section max items
    public static let overdueMaxItems: Int = 3

    // ─────────────────────────────────────────────────────────────────────────
    // SPACING SCALE
    // ─────────────────────────────────────────────────────────────────────────

    public static let spacingXXS: CGFloat = 2
    public static let spacingXS: CGFloat = 4
    public static let spacingSM: CGFloat = 8
    public static let spacingMD: CGFloat = 12
    public static let spacingLG: CGFloat = 16
    public static let spacingXL: CGFloat = 24
    public static let spacingXXL: CGFloat = 32
    public static let spacing3XL: CGFloat = 48

    // ─────────────────────────────────────────────────────────────────────────
    // CORNER RADIUS SCALE
    // ─────────────────────────────────────────────────────────────────────────

    public static let cornerRadiusSM: CGFloat = 6
    public static let cornerRadiusMD: CGFloat = 10
    public static let cornerRadiusLG: CGFloat = 14
    public static let cornerRadiusXL: CGFloat = 18
    public static let cornerRadiusFull: CGFloat = 999

    /// Legacy aliases
    public static let radiusSM = cornerRadiusSM
    public static let radiusMD = cornerRadiusMD
    public static let radiusLG = cornerRadiusLG
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - PLANNERIUM TYPOGRAPHY
// ═══════════════════════════════════════════════════════════════════════════════

/// Typography system for Plannerium
public struct PlannerumTypography {

    /// Page header - "PLANNERIUM"
    public static let header = Font.system(size: 26, weight: .bold, design: .rounded)

    /// Subheader - "Shape your next chapter"
    public static let subheader = Font.system(size: 14, weight: .medium, design: .rounded)

    /// Section header - "INBOXES", "OVERDUE"
    public static let sectionHeader = Font.system(size: 10, weight: .heavy)

    /// Day label in timeline
    public static let dayLabel = Font.system(size: 18, weight: .semibold, design: .rounded)

    /// Hour label in timeline
    public static let hourLabel = Font.system(size: 12, weight: .medium, design: .monospaced)

    /// Block title
    public static let blockTitle = Font.system(size: 15, weight: .semibold)

    /// Block subtitle
    public static let blockSubtitle = Font.system(size: 12, weight: .regular)

    /// Block time
    public static let blockTime = Font.system(size: 11, weight: .medium, design: .monospaced)

    /// Block detail
    public static let blockDetail = Font.system(size: 12, weight: .regular)

    /// Inbox stream title
    public static let inboxTitle = Font.system(size: 14, weight: .semibold, design: .rounded)

    /// Inbox item title
    public static let inboxItemTitle = Font.system(size: 13, weight: .medium)

    /// Inbox count badge
    public static let inboxCount = Font.system(size: 11, weight: .bold, design: .rounded)

    /// Focus bar title
    public static let focusTitle = Font.system(size: 16, weight: .semibold, design: .rounded)

    /// Timer display
    public static let timer = Font.system(size: 20, weight: .bold, design: .monospaced)

    /// XP display
    public static let xpDisplay = Font.system(size: 18, weight: .bold, design: .monospaced)

    /// XP label
    public static let xpLabel = Font.system(size: 12, weight: .semibold)

    /// Caption text
    public static let caption = Font.system(size: 11, weight: .regular)

    /// Overdue badge
    public static let overdueBadge = Font.system(size: 10, weight: .heavy)

    /// Letter spacing
    public static let trackingWide: CGFloat = 2
    public static let trackingNormal: CGFloat = 0
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - PLANNERIUM ANIMATION SYSTEM
// ═══════════════════════════════════════════════════════════════════════════════

/// Spring configurations for Plannerium animations
public struct PlannerumSprings {

    /// Micro interaction (instant feedback)
    public static let micro = Animation.spring(response: 0.12, dampingFraction: 0.85)

    /// Quick hover response
    public static let hover = Animation.spring(response: 0.18, dampingFraction: 0.8)

    /// Selection toggle
    public static let select = Animation.spring(response: 0.22, dampingFraction: 0.82)

    /// Block drag animation
    public static let drag = Animation.spring(response: 0.25, dampingFraction: 0.7)

    /// Block drop animation
    public static let drop = Animation.spring(response: 0.35, dampingFraction: 0.75)

    /// Expansion/collapse
    public static let expand = Animation.spring(response: 0.32, dampingFraction: 0.78)

    /// View mode transition
    public static let viewMode = Animation.spring(response: 0.45, dampingFraction: 0.8)

    /// Entry transition from Sanctuary
    public static let entry = Animation.spring(response: 0.55, dampingFraction: 0.78)

    /// Exit transition to Sanctuary
    public static let exit = Animation.spring(response: 0.45, dampingFraction: 0.82)

    /// XP tracer flight
    public static let xpTracer = Animation.spring(response: 0.8, dampingFraction: 0.65)

    /// Now bar pulse (continuous)
    public static let nowPulse = Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true)
}

/// Core Animation timing functions for Metal/GPU animations
public struct PlannerumTimingFunctions {

    /// Primary easing curve
    nonisolated(unsafe) public static let primary = CAMediaTimingFunction(controlPoints: 0.2, 0.0, 0.0, 1.0)

    /// XP tracer flight curve
    nonisolated(unsafe) public static let xpTracer = CAMediaTimingFunction(controlPoints: 0.0, 0.0, 0.2, 1.0)

    /// Now pulse curve
    nonisolated(unsafe) public static let nowPulse = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.6, 1.0)

    /// Block drag curve
    nonisolated(unsafe) public static let drag = CAMediaTimingFunction(controlPoints: 0.1, 0.0, 0.3, 1.0)
}

/// Duration standards for animations
public struct PlannerumDurations {
    public static let micro: Double = 0.12
    public static let fast: Double = 0.2
    public static let normal: Double = 0.3
    public static let slow: Double = 0.45
    public static let xpFlight: Double = 0.8
    public static let viewTransition: Double = 0.5
    public static let nowPulse: Double = 2.0
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - TIME BLOCK TYPE
// ═══════════════════════════════════════════════════════════════════════════════

/// Types of time blocks in Plannerium with XP associations
public enum TimeBlockType: String, CaseIterable, Identifiable, Codable {
    case deepWork = "Deep Work"
    case creative = "Creative"
    case output = "Output"
    case planning = "Planning"
    case training = "Training"
    case rest = "Rest"
    case administrative = "Admin"
    case meeting = "Meeting"
    case review = "Review"

    public var id: String { rawValue }

    /// Display name
    public var displayName: String { rawValue }

    /// Associated dimension for XP
    public var dimension: String {
        switch self {
        case .deepWork: return "cognitive"
        case .creative: return "creative"
        case .output: return "behavioral"
        case .planning: return "cognitive"
        case .training: return "knowledge"
        case .rest: return "physiological"
        case .administrative: return "behavioral"
        case .meeting: return "behavioral"
        case .review: return "reflection"
        }
    }

    /// Color for this block type
    public var color: Color {
        switch self {
        case .deepWork: return PlannerumColors.deepWork
        case .creative: return PlannerumColors.creative
        case .output: return PlannerumColors.output
        case .planning: return PlannerumColors.planning
        case .training: return PlannerumColors.training
        case .rest: return PlannerumColors.rest
        case .administrative: return PlannerumColors.administrative
        case .meeting: return PlannerumColors.meeting
        case .review: return PlannerumColors.review
        }
    }

    /// Icon for this block type
    public var icon: String {
        switch self {
        case .deepWork: return "brain.head.profile"
        case .creative: return "paintbrush.pointed.fill"
        case .output: return "arrow.up.doc.fill"
        case .planning: return "map.fill"
        case .training: return "book.fill"
        case .rest: return "leaf.fill"
        case .administrative: return "tray.full.fill"
        case .meeting: return "person.2.fill"
        case .review: return "eye.fill"
        }
    }

    /// Base XP per hour for this block type
    public var baseXPPerHour: Int {
        switch self {
        case .deepWork: return 30
        case .creative: return 28
        case .output: return 25
        case .planning: return 22
        case .training: return 20
        case .rest: return 10
        case .administrative: return 12
        case .meeting: return 8
        case .review: return 18
        }
    }

    /// Category multiplier for XP calculation
    public var categoryMultiplier: Double {
        switch self {
        case .deepWork: return 1.3
        case .creative: return 1.25
        case .output: return 1.2
        case .planning: return 1.15
        case .training: return 1.1
        case .rest: return 0.8
        case .administrative: return 0.9
        case .meeting: return 0.7
        case .review: return 1.0
        }
    }

    /// Short label for compact displays
    public var shortLabel: String {
        switch self {
        case .deepWork: return "Deep"
        case .creative: return "Create"
        case .output: return "Output"
        case .planning: return "Plan"
        case .training: return "Train"
        case .rest: return "Rest"
        case .administrative: return "Admin"
        case .meeting: return "Meet"
        case .review: return "Review"
        }
    }

    /// Create from string (for ATOM metadata parsing)
    public static func from(string: String) -> TimeBlockType {
        switch string.lowercased() {
        case "deepwork", "deep_work", "deep work": return .deepWork
        case "creative": return .creative
        case "output": return .output
        case "planning": return .planning
        case "training": return .training
        case "rest": return .rest
        case "admin", "administrative": return .administrative
        case "meeting": return .meeting
        case "review": return .review
        default: return .deepWork
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - INBOX STREAM TYPE
// ═══════════════════════════════════════════════════════════════════════════════

/// Types of inbox streams in Plannerium
public enum InboxStreamType: Hashable, Identifiable {
    case ideas
    case tasks
    case content
    case overdue
    case project(uuid: String, name: String)

    public var id: String {
        switch self {
        case .ideas: return "ideas"
        case .tasks: return "tasks"
        case .content: return "content"
        case .overdue: return "overdue"
        case .project(let uuid, _): return "project-\(uuid)"
        }
    }

    public var displayName: String {
        switch self {
        case .ideas: return "Ideas"
        case .tasks: return "Tasks"
        case .content: return "Content"
        case .overdue: return "Overdue"
        case .project(_, let name): return name
        }
    }

    public var icon: String {
        switch self {
        case .ideas: return "lightbulb.fill"
        case .tasks: return "checkmark.circle.fill"
        case .content: return "doc.text.fill"
        case .overdue: return "exclamationmark.triangle.fill"
        case .project: return "folder.fill"
        }
    }

    public var color: Color {
        switch self {
        case .ideas: return PlannerumColors.ideasInbox
        case .tasks: return PlannerumColors.tasksInbox
        case .content: return PlannerumColors.contentInbox
        case .overdue: return PlannerumColors.overdue
        case .project: return PlannerumColors.projectInbox
        }
    }

    public var atomType: String? {
        switch self {
        case .ideas: return "idea"
        case .tasks: return "task"
        case .content: return "content"
        case .overdue: return nil  // All types
        case .project: return nil  // All types for project
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - SHARED DATE FORMATTERS
// ═══════════════════════════════════════════════════════════════════════════════

/// Thread-safe, reusable DateFormatters to prevent per-render allocation
public enum PlannerumFormatters {

    /// Time format: "HH:mm" (e.g., "14:30")
    public static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// Time with seconds: "HH:mm:ss"
    public static let timeWithSeconds: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// Week range format: "MMMM d" (e.g., "December 22")
    public static let weekRange: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d"
        return f
    }()

    /// Day name short: "EEE" (e.g., "Sun")
    public static let dayNameShort: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    /// Day name full: "EEEE" (e.g., "Sunday")
    public static let dayNameFull: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    /// Day number: "d" (e.g., "22")
    public static let dayNumber: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    /// Full day format: "EEEE, MMMM d" (e.g., "Sunday, December 22")
    public static let dayFull: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    /// Month year: "MMMM yyyy" (e.g., "December 2025")
    public static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    /// Month short: "MMM" (e.g., "Dec")
    public static let monthShort: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()

    /// Quarter format: "Q'Q' yyyy" (e.g., "Q4 2025")
    public static let quarter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "'Q'Q yyyy"
        return f
    }()

    /// ISO 8601 for ATOM storage
    public static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Relative time formatter
    public static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - GLASS MATERIAL PRESETS
// ═══════════════════════════════════════════════════════════════════════════════

/// Predefined glass material configurations
public struct PlannerumGlass {

    /// Timeline surface glass
    public struct Timeline {
        public static let background = PlannerumColors.glassPrimary
        public static let blur: CGFloat = 32
        public static let cornerRadius: CGFloat = 16
        public static let borderOpacity: Double = 0.06
    }

    /// Block surface glass
    public struct Block {
        public static let background = Color(red: 20/255, green: 20/255, blue: 30/255).opacity(0.85)
        public static let blur: CGFloat = 24
        public static let glowRadius: CGFloat = 20
        public static let glowOpacity: Double = 0.15
    }

    /// Inbox item glass
    public struct InboxItem {
        public static let background = Color(red: 20/255, green: 20/255, blue: 32/255).opacity(0.8)
        public static let blur: CGFloat = 16
        public static let cornerRadius: CGFloat = 8
    }

    /// Focus bar glass
    public struct FocusBar {
        public static let background = Color(red: 12/255, green: 12/255, blue: 18/255).opacity(0.95)
        public static let blur: CGFloat = 40
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - ACCESSIBILITY TOKENS
// ═══════════════════════════════════════════════════════════════════════════════

/// Accessibility configuration for Plannerium
public struct PlannerumAccessibility {

    /// Minimum touch target size
    public static let minTouchTarget: CGFloat = 44

    /// Focus ring width
    public static let focusRingWidth: CGFloat = 2

    /// Focus ring color
    public static let focusRingColor = PlannerumColors.primary

    /// High contrast mode colors
    public struct HighContrast {
        public static let text = Color.white
        public static let background = Color.black
        public static let border = Color.white.opacity(0.3)
    }

    /// Reduced motion alternatives
    public struct ReducedMotion {
        public static let transition = Animation.easeInOut(duration: 0.2)
        public static let hover = Animation.easeInOut(duration: 0.1)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - XP CALCULATION HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

/// XP calculation utilities for Plannerium
public struct PlannerumXP {

    /// Calculate estimated XP for a block
    public static func estimateXP(
        blockType: TimeBlockType,
        durationMinutes: Int,
        difficulty: Double = 1.0,
        isStreakActive: Bool = false,
        isCoreObjective: Bool = false
    ) -> Int {
        let baseXP = Double(blockType.baseXPPerHour) * (Double(durationMinutes) / 60.0)
        var multiplier = blockType.categoryMultiplier * difficulty

        if isStreakActive {
            multiplier *= 1.2  // 20% streak bonus
        }

        if isCoreObjective {
            multiplier *= 1.5  // 50% core objective bonus
        }

        return Int(baseXP * multiplier)
    }

    /// Format XP for display
    public static func formatXP(_ xp: Int) -> String {
        if xp >= 1000 {
            return String(format: "%.1fK", Double(xp) / 1000.0)
        }
        return "\(xp)"
    }

    /// Calculate completion percentage
    public static func completionPercentage(completed: Int, total: Int) -> Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - TIME UTILITIES
// ═══════════════════════════════════════════════════════════════════════════════

/// Time formatting utilities
public struct PlannerumTimeUtils {

    /// Format duration for display
    public static func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60

        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }

    /// Format duration for timer display
    public static func formatTimer(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    /// Get relative time string
    public static func relativeTime(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)

        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }

    /// Check if date is in the past
    public static func isPast(_ date: Date) -> Bool {
        date < Date()
    }

    /// Check if date is today
    public static func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    /// Get start of day
    public static func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    /// Get end of day
    public static func endOfDay(_ date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: 1, to: startOfDay(date))!
    }
}
