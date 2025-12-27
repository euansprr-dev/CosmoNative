// CosmoOS/Scheduler/Shared/SchedulerStyles.swift
// Premium animation system and visual styling for the Cosmo Scheduler
//
// Design Philosophy:
// - Every animation tuned for 120Hz ProMotion displays
// - Spring physics feel natural and responsive
// - Visual hierarchy guides attention without distraction
// - Consistent with Apple Human Interface Guidelines + Cosmo design language

import SwiftUI

// MARK: - Scheduler Animation Presets

/// Premium spring animations tuned for Apple Silicon + ProMotion
/// Response times optimized for perceptual immediacy at 120fps
public enum SchedulerSprings {

    // ═══════════════════════════════════════════════════════════════
    // INTERACTIVE SPRINGS - Used during direct manipulation
    // Low response time = feels immediate
    // ═══════════════════════════════════════════════════════════════

    /// Ultra-snappy for direct feedback (hover states, micro-interactions)
    /// Response: 0.15s | Damping: 0.9 | Feels: Crisp, immediate
    public static let instant = Animation.spring(response: 0.15, dampingFraction: 0.9)

    /// Snappy for interactive elements (buttons, toggles, selection)
    /// Response: 0.2s | Damping: 0.8 | Feels: Responsive, bouncy
    public static let snappy = Animation.spring(response: 0.2, dampingFraction: 0.8)

    /// Drag feedback during active gesture
    /// Response: 0.18s | Damping: 0.85 | Feels: Attached to finger
    public static let drag = Animation.interactiveSpring(response: 0.18, dampingFraction: 0.85, blendDuration: 0.1)

    // ═══════════════════════════════════════════════════════════════
    // TRANSITION SPRINGS - Used for state changes and navigation
    // Balanced response for smooth, deliberate motion
    // ═══════════════════════════════════════════════════════════════

    /// Standard transition for UI elements appearing/disappearing
    /// Response: 0.3s | Damping: 0.8 | Feels: Smooth, professional
    public static let standard = Animation.spring(response: 0.3, dampingFraction: 0.8)

    /// Mode switching (Plan <-> Today)
    /// Response: 0.35s | Damping: 0.85 | Feels: Deliberate, confident
    public static let modeSwitch = Animation.spring(response: 0.35, dampingFraction: 0.85)

    /// Expansion/collapse animations (block editor, drawer)
    /// Response: 0.35s | Damping: 0.78 | Feels: Opening, revealing
    public static let expand = Animation.spring(response: 0.35, dampingFraction: 0.78)

    /// Gentle for large surface transitions
    /// Response: 0.4s | Damping: 0.82 | Feels: Graceful, unhurried
    public static let gentle = Animation.spring(response: 0.4, dampingFraction: 0.82)

    // ═══════════════════════════════════════════════════════════════
    // BLOCK MANIPULATION SPRINGS - Tuned for schedule blocks
    // ═══════════════════════════════════════════════════════════════

    /// Block creation (new block appearing)
    /// Response: 0.35s | Damping: 0.72 | Feels: Popping into existence
    public static let blockCreate = Animation.spring(response: 0.35, dampingFraction: 0.72)

    /// Block move/reposition
    /// Response: 0.4s | Damping: 0.78 | Feels: Gliding to position
    public static let blockMove = Animation.spring(response: 0.4, dampingFraction: 0.78)

    /// Block resize (duration change)
    /// Response: 0.3s | Damping: 0.8 | Feels: Stretching, elastic
    public static let blockResize = Animation.spring(response: 0.3, dampingFraction: 0.8)

    /// Block deletion (fade + scale out)
    /// Duration: 0.25s | Feels: Quick, decisive
    public static let blockDelete = Animation.easeOut(duration: 0.25)

    /// Block completion animation
    /// Response: 0.4s | Damping: 0.65 | Feels: Satisfying, celebratory
    public static let blockComplete = Animation.spring(response: 0.4, dampingFraction: 0.65)

    // ═══════════════════════════════════════════════════════════════
    // VOICE COMMAND SPRINGS - For LLM-triggered actions
    // Slightly more pronounced to acknowledge voice input
    // ═══════════════════════════════════════════════════════════════

    /// Voice-created block appearance
    /// Response: 0.38s | Damping: 0.7 | Feels: Magical, responsive
    public static let voiceCreate = Animation.spring(response: 0.38, dampingFraction: 0.7)

    /// Voice-triggered expand/shrink
    /// Response: 0.42s | Damping: 0.75 | Feels: Deliberate, understood
    public static let voiceResize = Animation.spring(response: 0.42, dampingFraction: 0.75)

    /// Voice-triggered move
    /// Response: 0.45s | Damping: 0.72 | Feels: Gliding smoothly
    public static let voiceMove = Animation.spring(response: 0.45, dampingFraction: 0.72)

    /// Voice-triggered delete
    /// Duration: 0.28s | Feels: Acknowledged, removed
    public static let voiceDelete = Animation.easeOut(duration: 0.28)

    // ═══════════════════════════════════════════════════════════════
    // STAGGER ANIMATIONS - For lists and grids
    // ═══════════════════════════════════════════════════════════════

    /// Staggered appearance for list items
    /// Delay: 0.04s per item | Feels: Cascading, elegant
    public static func staggered(index: Int, baseDelay: Double = 0.04) -> Animation {
        .spring(response: 0.32, dampingFraction: 0.78).delay(Double(index) * baseDelay)
    }

    /// Staggered appearance for grid items (faster cascade)
    /// Delay: 0.03s per item | Feels: Rapid reveal
    public static func gridStagger(index: Int) -> Animation {
        .spring(response: 0.28, dampingFraction: 0.8).delay(Double(index) * 0.03)
    }

    /// Staggered reorder animation
    /// Delay: 0.025s per item | Feels: Flowing
    public static func reorderStagger(index: Int) -> Animation {
        .spring(response: 0.25, dampingFraction: 0.82).delay(Double(index) * 0.025)
    }

    // ═══════════════════════════════════════════════════════════════
    // AMBIENT ANIMATIONS - For continuous effects
    // ═══════════════════════════════════════════════════════════════

    /// Pulsing glow effect (current time indicator)
    public static let pulseGlow = Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)

    /// Breathing scale effect (focus mode indicator)
    public static let breathe = Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true)

    /// Subtle hover scale
    public static let hoverScale = Animation.spring(response: 0.2, dampingFraction: 0.85)
}

// MARK: - Scheduler Colors

/// Color palette specifically for the scheduler UI
/// Extends CosmoColors with scheduler-specific semantic colors
public enum SchedulerColors {

    // ═══════════════════════════════════════════════════════════════
    // BLOCK TYPE COLORS - Visual differentiation by type
    // ═══════════════════════════════════════════════════════════════

    /// Task blocks - Coral for action/urgency
    public static let task = CosmoColors.coral

    /// Time blocks - Lavender for scheduled work
    public static let timeBlock = CosmoColors.lavender

    /// Event blocks - Sky blue for external items
    public static let event = CosmoColors.skyBlue

    /// Focus session blocks - Deep lavender for deep work
    public static let focus = Color(hex: "9B7ED8")

    /// Reminder blocks - Soft gold
    public static let reminder = Color(hex: "E8C87D")

    // ═══════════════════════════════════════════════════════════════
    // STATUS COLORS - Visual feedback for states
    // ═══════════════════════════════════════════════════════════════

    /// Completed state - Emerald success
    public static let completed = CosmoColors.emerald

    /// Overdue state - Soft red warning
    public static let overdue = CosmoColors.softRed

    /// In progress state - Sky blue active
    public static let inProgress = CosmoColors.skyBlue

    /// Cancelled state - Muted grey
    public static let cancelled = CosmoColors.textTertiary

    // ═══════════════════════════════════════════════════════════════
    // PRIORITY COLORS - Urgency indication
    // ═══════════════════════════════════════════════════════════════

    /// Urgent priority - Vivid coral
    public static let priorityUrgent = Color(hex: "E85D4C")

    /// High priority - Strong coral
    public static let priorityHigh = CosmoColors.coral

    /// Medium priority - Soft lavender
    public static let priorityMedium = CosmoColors.lavender

    /// Low priority - Muted grey
    public static let priorityLow = CosmoColors.textTertiary

    // ═══════════════════════════════════════════════════════════════
    // GRID COLORS - Calendar grid elements
    // ═══════════════════════════════════════════════════════════════

    /// Hour line color
    public static let hourLine = CosmoColors.glassGrey.opacity(0.3)

    /// Half-hour line color (lighter)
    public static let halfHourLine = CosmoColors.glassGrey.opacity(0.15)

    /// Quarter-hour line color (lightest)
    public static let quarterHourLine = CosmoColors.glassGrey.opacity(0.08)

    /// Today column highlight
    public static let todayHighlight = CosmoColors.skyBlue.opacity(0.06)

    /// Current time indicator
    public static let nowIndicator = CosmoColors.coral

    /// Selected block border
    public static let selectionBorder = CosmoColors.lavender

    /// Lavender (passthrough to CosmoColors)
    public static let lavender = CosmoColors.lavender

    /// Drag preview overlay
    public static let dragPreview = CosmoColors.lavender.opacity(0.3)

    // ═══════════════════════════════════════════════════════════════
    // SURFACE COLORS - Backgrounds and cards
    // ═══════════════════════════════════════════════════════════════

    /// Main scheduler background
    public static let background = CosmoColors.softWhite

    /// Block card background
    public static let cardBackground = Color.white

    /// Block card background (hover)
    public static let cardBackgroundHover = Color.white.opacity(0.95)

    /// Drawer background
    public static let drawerBackground = CosmoColors.softWhite

    /// Header background
    public static let headerBackground = CosmoColors.softWhite.opacity(0.98)

    // ═══════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /// Get color for block type
    public static func color(for blockType: ScheduleBlockType) -> Color {
        switch blockType {
        case .task: return task
        case .timeBlock: return timeBlock
        case .event: return event
        case .focus: return focus
        case .reminder: return reminder
        }
    }

    /// Get color for priority
    public static func color(for priority: ScheduleBlockPriority) -> Color {
        switch priority {
        case .urgent: return priorityUrgent
        case .high: return priorityHigh
        case .medium: return priorityMedium
        case .low: return priorityLow
        }
    }

    /// Get color for status
    public static func color(for status: ScheduleBlockStatus?) -> Color {
        guard let status = status else { return CosmoColors.textSecondary }
        switch status {
        case .todo: return CosmoColors.textSecondary
        case .inProgress: return inProgress
        case .done: return completed
        case .cancelled: return cancelled
        case .deferred: return CosmoColors.textTertiary
        }
    }
}

// MARK: - Scheduler Dimensions

/// Consistent dimensions for scheduler layout
public enum SchedulerDimensions {

    // ═══════════════════════════════════════════════════════════════
    // PLAN MODE GRID
    // ═══════════════════════════════════════════════════════════════

    /// Time column width (pinned left)
    public static let timeColumnWidth: CGFloat = 56

    /// Hour row height
    public static let hourHeight: CGFloat = 60

    /// Day header height
    public static let dayHeaderHeight: CGFloat = 52

    /// Minimum block height (15 minutes equivalent)
    public static let minBlockHeight: CGFloat = hourHeight / 4

    /// Block horizontal padding within day column
    public static let blockHorizontalPadding: CGFloat = 2

    /// Block vertical margin
    public static let blockVerticalMargin: CGFloat = 1

    /// Block corner radius
    public static let blockCornerRadius: CGFloat = 8

    /// Block accent seam width
    public static let blockAccentWidth: CGFloat = 3

    // ═══════════════════════════════════════════════════════════════
    // TODAY MODE LIST
    // ═══════════════════════════════════════════════════════════════

    /// Row height
    public static let todayRowHeight: CGFloat = 56

    /// Row horizontal padding
    public static let todayRowPadding: CGFloat = 16

    /// Checkbox size
    public static let checkboxSize: CGFloat = 24

    /// Group header height
    public static let groupHeaderHeight: CGFloat = 36

    // ═══════════════════════════════════════════════════════════════
    // COMMON
    // ═══════════════════════════════════════════════════════════════

    /// Header bar height
    public static let headerHeight: CGFloat = 56

    /// Mode toggle pill height
    public static let modeToggleHeight: CGFloat = 36

    /// Mode toggle corner radius
    public static let modeToggleRadius: CGFloat = 18

    /// Context drawer width
    public static let drawerWidth: CGFloat = 320

    /// Editor card width
    public static let editorCardWidth: CGFloat = 300

    /// Editor card max height
    public static let editorCardMaxHeight: CGFloat = 400

    /// Small button size
    public static let smallButtonSize: CGFloat = 32

    /// Medium button size
    public static let mediumButtonSize: CGFloat = 40
}

// MARK: - Scheduler Shadows

/// Consistent shadow styles for depth hierarchy
public enum SchedulerShadows {

    /// Subtle shadow for resting blocks
    public static func idle(color: Color = .black) -> some View {
        EmptyView()
            .shadow(color: color.opacity(0.06), radius: 3, x: 0, y: 1)
            .shadow(color: color.opacity(0.04), radius: 8, x: 0, y: 4)
    }

    /// Elevated shadow for hover state
    public static func hover(color: Color = .black) -> some View {
        EmptyView()
            .shadow(color: color.opacity(0.08), radius: 6, x: 0, y: 2)
            .shadow(color: color.opacity(0.06), radius: 16, x: 0, y: 8)
    }

    /// Lifted shadow for drag state
    public static func drag(color: Color) -> some View {
        EmptyView()
            .shadow(color: color.opacity(0.2), radius: 12, x: 0, y: 4)
            .shadow(color: color.opacity(0.12), radius: 24, x: 0, y: 12)
    }

    /// Selected block glow
    public static func selected(color: Color) -> some View {
        EmptyView()
            .shadow(color: color.opacity(0.25), radius: 8, x: 0, y: 0)
            .shadow(color: color.opacity(0.15), radius: 16, x: 0, y: 0)
    }

    /// Card shadow for editor/drawer
    public static func card() -> some View {
        EmptyView()
            .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 10)
            .shadow(color: .black.opacity(0.04), radius: 40, x: 0, y: 20)
    }
}

// MARK: - Scheduler Haptics

/// Haptic feedback patterns for interactions
public enum SchedulerHaptics {

    /// Light tap feedback (selection, hover)
    public static func light() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    /// Medium impact (drag start, mode switch)
    public static func medium() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
    }

    /// Strong impact (completion, delete)
    public static func strong() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }

    /// Success feedback
    public static func success() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    /// Warning feedback
    public static func warning() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
}

// MARK: - View Modifiers

/// Premium block styling modifier
struct SchedulerBlockStyle: ViewModifier {
    let blockType: ScheduleBlockType
    let isSelected: Bool
    let isHovered: Bool
    let isDragging: Bool

    func body(content: Self.Content) -> some View {
        let accentColor = SchedulerColors.color(for: blockType)

        content
            .background(
                RoundedRectangle(cornerRadius: SchedulerDimensions.blockCornerRadius)
                    .fill(isDragging ? SchedulerColors.cardBackgroundHover : SchedulerColors.cardBackground)
            )
            .overlay(
                // Accent seam on left edge
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accentColor)
                        .frame(width: SchedulerDimensions.blockAccentWidth)
                    Spacer()
                }
                .clipShape(RoundedRectangle(cornerRadius: SchedulerDimensions.blockCornerRadius))
            )
            .overlay(
                // Selection border
                RoundedRectangle(cornerRadius: SchedulerDimensions.blockCornerRadius)
                    .stroke(isSelected ? SchedulerColors.selectionBorder : Color.clear, lineWidth: 2)
            )
            .shadow(color: isDragging ? accentColor.opacity(0.2) : .black.opacity(0.06), radius: isDragging ? 12 : 3, x: 0, y: isDragging ? 4 : 1)
            .shadow(color: isDragging ? accentColor.opacity(0.12) : .black.opacity(0.04), radius: isDragging ? 24 : 8, x: 0, y: isDragging ? 12 : 4)
            .scaleEffect(isDragging ? 1.02 : (isHovered ? 1.005 : 1.0))
            .animation(isDragging ? SchedulerSprings.drag : SchedulerSprings.hoverScale, value: isDragging)
            .animation(SchedulerSprings.hoverScale, value: isHovered)
    }
}

extension View {
    /// Apply premium block styling
    func schedulerBlockStyle(
        blockType: ScheduleBlockType,
        isSelected: Bool = false,
        isHovered: Bool = false,
        isDragging: Bool = false
    ) -> some View {
        modifier(SchedulerBlockStyle(
            blockType: blockType,
            isSelected: isSelected,
            isHovered: isHovered,
            isDragging: isDragging
        ))
    }
}

/// Today list row style modifier
struct TodayRowStyle: ViewModifier {
    let isCompleted: Bool
    let isOverdue: Bool
    let isHovered: Bool

    func body(content: Self.Content) -> some View {
        content
            .padding(.horizontal, SchedulerDimensions.todayRowPadding)
            .frame(height: SchedulerDimensions.todayRowHeight)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? CosmoColors.glassGrey.opacity(0.08) : Color.clear)
            )
            .opacity(isCompleted ? 0.6 : 1.0)
            .animation(SchedulerSprings.instant, value: isHovered)
            .animation(SchedulerSprings.blockComplete, value: isCompleted)
    }
}

extension View {
    /// Apply today list row styling
    func todayRowStyle(
        isCompleted: Bool = false,
        isOverdue: Bool = false,
        isHovered: Bool = false
    ) -> some View {
        modifier(TodayRowStyle(
            isCompleted: isCompleted,
            isOverdue: isOverdue,
            isHovered: isHovered
        ))
    }
}

// MARK: - Transition Definitions

/// Custom transitions for scheduler elements
public extension AnyTransition {

    /// Block appearance transition (scale + opacity)
    static var blockAppear: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.92).combined(with: .opacity),
            removal: .scale(scale: 0.96).combined(with: .opacity)
        )
    }

    /// Row slide transition
    static var rowSlide: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        )
    }

    /// Drawer slide from right
    static var drawerSlide: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
    }

    /// Editor card pop
    static var editorPop: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.9).combined(with: .opacity),
            removal: .scale(scale: 0.95).combined(with: .opacity)
        )
    }

    /// Mode switch cross-fade
    static var modeSwitch: AnyTransition {
        .opacity.animation(SchedulerSprings.modeSwitch)
    }
}

// MARK: - Time Formatting

/// Scheduler-specific time formatting utilities
public struct SchedulerTimeFormat {

    /// Format hour for time column (12-hour format)
    public static func hourLabel(_ hour: Int) -> String {
        if hour == 0 || hour == 24 {
            return "12 AM"
        } else if hour == 12 {
            return "12 PM"
        } else if hour < 12 {
            return "\(hour) AM"
        } else {
            return "\(hour - 12) PM"
        }
    }

    /// Format time for display
    public static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    /// Format date for header
    public static func formatHeaderDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: date)
    }

    /// Format day for week header
    public static func formatDayHeader(_ date: Date) -> (weekday: String, day: String) {
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.dateFormat = "EEE"

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "d"

        return (weekdayFormatter.string(from: date).uppercased(), dayFormatter.string(from: date))
    }

    /// Format duration string
    public static func formatDuration(minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let mins = minutes % 60
        if mins == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(mins)m"
    }

    /// Relative time string ("in 2 hours", "3 hours ago")
    public static func relativeTime(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Grid Position Calculation

/// Utilities for converting between time and pixel positions
public struct SchedulerGridCalculator {

    /// Calculate Y position for a given time
    public static func yPosition(for date: Date, hourHeight: CGFloat = SchedulerDimensions.hourHeight) -> CGFloat {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return CGFloat(hour) * hourHeight + CGFloat(minute) / 60.0 * hourHeight
    }

    /// Calculate time for a given Y position
    public static func time(for yPosition: CGFloat, baseDate: Date, hourHeight: CGFloat = SchedulerDimensions.hourHeight) -> Date {
        let totalMinutes = yPosition / hourHeight * 60
        let hours = Int(totalMinutes) / 60
        let minutes = Int(totalMinutes) % 60

        var components = Calendar.current.dateComponents([.year, .month, .day], from: baseDate)
        components.hour = hours
        components.minute = minutes

        return Calendar.current.date(from: components) ?? baseDate
    }

    /// Calculate block height for duration
    public static func blockHeight(durationMinutes: Int, hourHeight: CGFloat = SchedulerDimensions.hourHeight) -> CGFloat {
        CGFloat(durationMinutes) / 60.0 * hourHeight
    }

    /// Snap time to nearest interval
    public static func snapToInterval(_ date: Date, intervalMinutes: Int = 15) -> Date {
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: date)
        let snappedMinute = (minute / intervalMinutes) * intervalMinutes

        var components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        components.minute = snappedMinute

        return calendar.date(from: components) ?? date
    }

    /// Get day index (0-6) for date relative to week start
    public static func dayIndex(for date: Date, weekStart: Date) -> Int {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: weekStart, to: date).day ?? 0
        return max(0, min(6, days))
    }
}
