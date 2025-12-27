// CosmoOS/UI/Sanctuary/Dimensions/Creative/CreativePostingCalendar.swift
// Posting Calendar - Calendar heatmap with posting history
// Phase 4: Following SANCTUARY_UI_SPEC_V2.md section 3.2

import SwiftUI

// MARK: - Posting Calendar

/// Calendar heatmap showing posting history with status indicators
public struct CreativePostingCalendar: View {

    // MARK: - Properties

    let postingDays: [PostingDay]
    let currentStreak: Int
    let bestPostingTime: String
    let mostActiveDay: Weekday
    let averagePostsPerWeek: Double
    let onDayTap: ((PostingDay) -> Void)?

    @State private var isVisible: Bool = false
    @State private var selectedMonth: Date = Date()
    @State private var hoveredDay: Date?

    private let calendar = Calendar.current
    private let weekdaySymbols = ["S", "M", "T", "W", "T", "F", "S"]

    // MARK: - Initialization

    public init(
        postingDays: [PostingDay],
        currentStreak: Int,
        bestPostingTime: String,
        mostActiveDay: Weekday,
        averagePostsPerWeek: Double,
        onDayTap: ((PostingDay) -> Void)? = nil
    ) {
        self.postingDays = postingDays
        self.currentStreak = currentStreak
        self.bestPostingTime = bestPostingTime
        self.mostActiveDay = mostActiveDay
        self.averagePostsPerWeek = averagePostsPerWeek
        self.onDayTap = onDayTap
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            header

            // Stats row
            statsRow

            // Calendar
            calendarGrid

            // Legend
            legend
        }
        .padding(SanctuaryLayout.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                        .stroke(SanctuaryColors.Glass.border, lineWidth: 1)
                )
        )
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 20)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(0.4)) {
                isVisible = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("POSTING CALENDAR")
                .font(SanctuaryTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            Spacer()

            // Month navigation
            HStack(spacing: SanctuaryLayout.Spacing.md) {
                Button(action: previousMonth) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(SanctuaryColors.Text.secondary)
                }
                .buttonStyle(PlainButtonStyle())

                Text(monthYearString)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(SanctuaryColors.Text.primary)
                    .frame(width: 100)

                Button(action: nextMonth) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(SanctuaryColors.Text.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: SanctuaryLayout.Spacing.xl) {
            // Streak
            HStack(spacing: SanctuaryLayout.Spacing.xs) {
                Text("🔥")
                    .font(.system(size: 14))

                Text("Streak: \(currentStreak) days")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(SanctuaryColors.Text.primary)
            }
            .padding(.horizontal, SanctuaryLayout.Spacing.md)
            .padding(.vertical, SanctuaryLayout.Spacing.sm)
            .background(
                Capsule()
                    .fill(SanctuaryColors.Dimensions.creative.opacity(0.15))
            )

            // Best time
            VStack(alignment: .leading, spacing: 2) {
                Text("Best Time")
                    .font(.system(size: 9))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Text(bestPostingTime)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(SanctuaryColors.Text.primary)
            }

            // Most active day
            VStack(alignment: .leading, spacing: 2) {
                Text("Most Active")
                    .font(.system(size: 9))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Text(mostActiveDay.fullName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(SanctuaryColors.Text.primary)
            }

            // Avg posts/week
            VStack(alignment: .leading, spacing: 2) {
                Text("Avg/Week")
                    .font(.system(size: 9))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Text(String(format: "%.1f posts", averagePostsPerWeek))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(SanctuaryColors.Text.primary)
            }

            Spacer()
        }
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        VStack(spacing: SanctuaryLayout.Spacing.xs) {
            // Weekday headers
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, SanctuaryLayout.Spacing.xs)

            // Day grid
            let days = daysInMonth()
            let columns = 7
            let rows = (days.count + 6) / 7

            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        if index < days.count {
                            dayCell(for: days[index])
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }
                    }
                }
            }
        }
    }

    private func dayCell(for dayInfo: DayInfo) -> some View {
        let isToday = calendar.isDateInToday(dayInfo.date)
        let postingDay = postingDays.first { calendar.isDate($0.date, inSameDayAs: dayInfo.date) }
        let isHovered = hoveredDay == postingDay?.id

        return ZStack {
            // Background
            RoundedRectangle(cornerRadius: 4)
                .fill(cellBackgroundColor(for: postingDay, isToday: isToday))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isToday ? SanctuaryColors.Text.primary : Color.clear, lineWidth: 1)
                )

            // Day number
            VStack(spacing: 1) {
                if dayInfo.isCurrentMonth {
                    Text("\(calendar.component(.day, from: dayInfo.date))")
                        .font(.system(size: 10, weight: isToday ? .bold : .regular))
                        .foregroundColor(dayForegroundColor(for: postingDay, isToday: isToday, isCurrentMonth: true))

                    // Status indicator
                    if let day = postingDay {
                        statusIndicator(for: day.status)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 32)
        .scaleEffect(isHovered ? 1.1 : 1.0)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            if let day = postingDay {
                hoveredDay = hovering ? day.id : nil
            }
        }
        .onTapGesture {
            if let day = postingDay {
                onDayTap?(day)
            }
        }
    }

    private func cellBackgroundColor(for postingDay: PostingDay?, isToday: Bool) -> Color {
        guard let day = postingDay else {
            return Color.clear
        }

        switch day.status {
        case .posted:
            return SanctuaryColors.Dimensions.creative.opacity(0.3)
        case .viral:
            return SanctuaryColors.XP.primary.opacity(0.4)
        case .skipped:
            return SanctuaryColors.Semantic.error.opacity(0.15)
        case .scheduled:
            return SanctuaryColors.Semantic.info.opacity(0.2)
        case .rest:
            return SanctuaryColors.Glass.highlight
        case .future:
            return SanctuaryColors.Text.tertiary.opacity(0.1)
        }
    }

    private func dayForegroundColor(for postingDay: PostingDay?, isToday: Bool, isCurrentMonth: Bool) -> Color {
        if !isCurrentMonth {
            return SanctuaryColors.Text.tertiary.opacity(0.5)
        }
        if isToday {
            return SanctuaryColors.Text.primary
        }
        if postingDay?.status == .viral {
            return SanctuaryColors.XP.primary
        }
        return SanctuaryColors.Text.secondary
    }

    @ViewBuilder
    private func statusIndicator(for status: PostingDayStatus) -> some View {
        switch status {
        case .posted:
            RoundedRectangle(cornerRadius: 1)
                .fill(SanctuaryColors.Dimensions.creative)
                .frame(width: 6, height: 6)
        case .viral:
            Image(systemName: "star.fill")
                .font(.system(size: 6))
                .foregroundColor(SanctuaryColors.XP.primary)
        case .skipped:
            RoundedRectangle(cornerRadius: 1)
                .stroke(SanctuaryColors.Semantic.error, lineWidth: 1)
                .frame(width: 6, height: 6)
        case .scheduled:
            Circle()
                .fill(SanctuaryColors.Semantic.info)
                .frame(width: 4, height: 4)
                .overlay(
                    Circle()
                        .stroke(SanctuaryColors.Semantic.info.opacity(0.5), lineWidth: 2)
                        .frame(width: 6, height: 6)
                )
        case .rest:
            EmptyView()
        case .future:
            Circle()
                .stroke(SanctuaryColors.Text.tertiary.opacity(0.3), lineWidth: 1)
                .frame(width: 4, height: 4)
        }
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: SanctuaryLayout.Spacing.lg) {
            legendItem(symbol: "square.fill", label: "Posted", color: SanctuaryColors.Dimensions.creative)
            legendItem(symbol: "square", label: "Skipped", color: SanctuaryColors.Semantic.error)
            legendItem(symbol: "star.fill", label: "Viral", color: SanctuaryColors.XP.primary)
            legendItem(symbol: "circle.dotted", label: "Scheduled", color: SanctuaryColors.Semantic.info)
            legendItem(symbol: "circle.dashed", label: "Today", color: SanctuaryColors.Text.primary)

            Spacer()
        }
    }

    private func legendItem(symbol: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 8))
                .foregroundColor(color)

            Text(label)
                .font(.system(size: 10))
                .foregroundColor(SanctuaryColors.Text.tertiary)
        }
    }

    // MARK: - Helpers

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: selectedMonth)
    }

    private func previousMonth() {
        withAnimation(SanctuarySprings.snappy) {
            selectedMonth = calendar.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
        }
    }

    private func nextMonth() {
        withAnimation(SanctuarySprings.snappy) {
            selectedMonth = calendar.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
        }
    }

    private func daysInMonth() -> [DayInfo] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedMonth),
              let monthFirstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start) else {
            return []
        }

        var days: [DayInfo] = []
        var currentDate = monthFirstWeek.start

        // Add days from previous month to fill first week
        while currentDate < monthInterval.start {
            days.append(DayInfo(date: currentDate, isCurrentMonth: false))
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }

        // Add days of current month
        while currentDate < monthInterval.end {
            days.append(DayInfo(date: currentDate, isCurrentMonth: true))
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }

        // Fill remaining days of last week
        let remainder = days.count % 7
        if remainder > 0 {
            let toAdd = 7 - remainder
            for _ in 0..<toAdd {
                days.append(DayInfo(date: currentDate, isCurrentMonth: false))
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
            }
        }

        return days
    }
}

// MARK: - Day Info

private struct DayInfo {
    let date: Date
    let isCurrentMonth: Bool
}

// MARK: - Posting Day Status

public enum PostingDayStatus: String, Codable, Sendable {
    case posted
    case skipped
    case viral
    case scheduled
    case rest
    case future  // From CreativeDimensionData

    var displaySymbol: String {
        switch self {
        case .posted: return "■"
        case .skipped: return "□"
        case .viral: return "★"
        case .scheduled: return "◐"
        case .rest: return "·"
        case .future: return "○"
        }
    }

    var colorHex: String {
        switch self {
        case .posted: return "#10B981"
        case .skipped: return "#4B5563"
        case .viral: return "#F59E0B"
        case .scheduled: return "#6366F1"
        case .future, .rest: return "#374151"
        }
    }
}

// MARK: - Streak Display

/// Streak indicator component
public struct CreativeStreakIndicator: View {

    let currentStreak: Int
    let longestStreak: Int
    let isActive: Bool

    @State private var isAnimating: Bool = false

    public init(currentStreak: Int, longestStreak: Int, isActive: Bool = true) {
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.isActive = isActive
    }

    public var body: some View {
        HStack(spacing: SanctuaryLayout.Spacing.md) {
            // Fire icon with animation
            Text("🔥")
                .font(.system(size: 24))
                .scaleEffect(isAnimating ? 1.1 : 1.0)
                .animation(
                    isActive ?
                        .easeInOut(duration: 0.5).repeatForever(autoreverses: true) :
                        .default,
                    value: isAnimating
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("\(currentStreak) day streak")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.primary)

                Text("Best: \(longestStreak) days")
                    .font(.system(size: 11))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }

            Spacer()

            // Progress to next milestone
            streakProgress
        }
        .padding(SanctuaryLayout.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(
                    LinearGradient(
                        colors: [
                            SanctuaryColors.Dimensions.creative.opacity(0.15),
                            SanctuaryColors.XP.primary.opacity(0.1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(SanctuaryColors.Glass.border, lineWidth: 1)
                )
        )
        .onAppear {
            if isActive {
                isAnimating = true
            }
        }
    }

    private var streakProgress: some View {
        let nextMilestone = nextStreakMilestone
        let progress = Double(currentStreak) / Double(nextMilestone)

        return VStack(alignment: .trailing, spacing: 4) {
            Text("\(nextMilestone - currentStreak) to go")
                .font(.system(size: 10))
                .foregroundColor(SanctuaryColors.Text.tertiary)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(SanctuaryColors.Glass.highlight)
                    .frame(width: 60, height: 4)

                Capsule()
                    .fill(SanctuaryColors.XP.primary)
                    .frame(width: 60 * progress, height: 4)
            }

            Text("\(nextMilestone) day goal")
                .font(.system(size: 9))
                .foregroundColor(SanctuaryColors.Text.tertiary)
        }
    }

    private var nextStreakMilestone: Int {
        let milestones = [7, 14, 30, 60, 90, 180, 365]
        return milestones.first { $0 > currentStreak } ?? 365
    }
}

// MARK: - Compact Calendar

/// Smaller calendar for embedding in other views
public struct CreativeCalendarCompact: View {

    let postingDays: [PostingDay]
    let weeksToShow: Int

    public init(postingDays: [PostingDay], weeksToShow: Int = 4) {
        self.postingDays = postingDays
        self.weeksToShow = weeksToShow
    }

    private let calendar = Calendar.current

    public var body: some View {
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -(weeksToShow * 7), to: endDate) ?? endDate

        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xs) {
            // Mini grid
            HStack(spacing: 2) {
                ForEach(0..<(weeksToShow * 7), id: \.self) { dayOffset in
                    let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate) ?? startDate
                    let postingDay = postingDays.first { calendar.isDate($0.date, inSameDayAs: date) }

                    RoundedRectangle(cornerRadius: 2)
                        .fill(compactCellColor(for: postingDay))
                        .frame(width: 8, height: 8)
                }
            }

            // Summary
            HStack(spacing: SanctuaryLayout.Spacing.sm) {
                Text("\(postedCount) posted")
                    .font(.system(size: 9))
                    .foregroundColor(SanctuaryColors.Dimensions.creative)

                Text("•")
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Text("\(viralCount) viral")
                    .font(.system(size: 9))
                    .foregroundColor(SanctuaryColors.XP.primary)
            }
        }
    }

    private func compactCellColor(for postingDay: PostingDay?) -> Color {
        guard let day = postingDay else {
            return SanctuaryColors.Glass.highlight
        }

        switch day.status {
        case .posted:
            return SanctuaryColors.Dimensions.creative.opacity(0.6)
        case .viral:
            return SanctuaryColors.XP.primary
        case .skipped:
            return SanctuaryColors.Semantic.error.opacity(0.4)
        case .scheduled:
            return SanctuaryColors.Semantic.info.opacity(0.4)
        case .rest:
            return SanctuaryColors.Glass.highlight
        case .future:
            return SanctuaryColors.Text.tertiary.opacity(0.2)
        }
    }

    private var postedCount: Int {
        postingDays.filter { $0.status == .posted || $0.status == .viral }.count
    }

    private var viralCount: Int {
        postingDays.filter { $0.status == .viral }.count
    }
}

// MARK: - Preview

#if DEBUG
struct CreativePostingCalendar_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                CreativePostingCalendar(
                    postingDays: Array(CreativeDimensionData.preview.postingHistory.values),
                    currentStreak: 12,
                    bestPostingTime: "3:15 PM",
                    mostActiveDay: .tuesday,
                    averagePostsPerWeek: 4.2
                )

                CreativeStreakIndicator(
                    currentStreak: 12,
                    longestStreak: 28,
                    isActive: true
                )

                CreativeCalendarCompact(
                    postingDays: Array(CreativeDimensionData.preview.postingHistory.values),
                    weeksToShow: 8
                )
            }
            .padding()
        }
        .frame(minWidth: 800, minHeight: 700)
    }
}
#endif
