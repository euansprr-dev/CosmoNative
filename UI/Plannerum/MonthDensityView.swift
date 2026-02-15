// CosmoOS/UI/Plannerum/MonthDensityView.swift
// Plannerum Month Density - Heat map calendar with XP visualization
// PLANERIUM_SPEC.md Section 4.1 compliant

import SwiftUI
import Combine

// MARK: - Month Density View

/// The Month view in Plannerum - a density heat map showing XP and commitment levels.
///
/// From PLANERIUM_SPEC.md Section 4.1:
/// ```
/// GRID LAYOUT
/// ├── Cell size: 40x40pt
/// ├── Spacing: 4pt between cells
/// ├── Grid: 7 columns × 4-6 rows
/// └── Header row: Day abbreviations (M T W T F S S)
/// ```
public struct MonthDensityView: View {

    // MARK: - Properties

    let centerDate: Date
    let onDaySelect: (Date) -> Void
    let onNavigateMonth: ((Int) -> Void)?

    // MARK: - State

    @StateObject private var viewModel = MonthDensityViewModel()
    @State private var hoveredDay: Date?
    @State private var selectedDay: Date?

    // MARK: - Layout (From Spec Section 4.1)

    private enum Layout {
        static let cellSize: CGFloat = 40        // Spec: 40x40pt
        static let cellSpacing: CGFloat = 4      // Spec: 4pt between cells
        static let weekdayHeaderHeight: CGFloat = 28
        static let monthHeaderHeight: CGFloat = 56
    }

    // MARK: - Computed

    private var calendar: Calendar { Calendar.current }

    private var weekdays: [String] {
        ["M", "T", "W", "T", "F", "S", "S"]
    }

    private var weeks: [[Date?]] {
        generateWeeks(for: centerDate)
    }

    // MARK: - Init

    public init(
        centerDate: Date,
        onDaySelect: @escaping (Date) -> Void,
        onNavigateMonth: ((Int) -> Void)? = nil
    ) {
        self.centerDate = centerDate
        self.onDaySelect = onDaySelect
        self.onNavigateMonth = onNavigateMonth
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            // Month header with navigation
            monthHeader

            // Weekday labels
            weekdayHeader

            // Calendar grid
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: Layout.cellSpacing) {
                    ForEach(weeks.indices, id: \.self) { weekIndex in
                        let week = weeks[weekIndex]
                        weekRow(week: week)
                            .id(weekStableId(week: week, index: weekIndex))
                    }
                }
                .padding(.horizontal, PlannerumLayout.contentPadding)
                .padding(.vertical, PlannerumLayout.spacingSM)
            }

            // Month summary with XP forecast
            monthSummary
        }
        .onAppear {
            Task {
                await viewModel.loadMonthData(for: centerDate)
            }
        }
        .onChange(of: centerDate) { _, newDate in
            Task {
                await viewModel.loadMonthData(for: newDate)
            }
        }
    }

    // MARK: - Month Header

    private var monthHeader: some View {
        HStack {
            // Previous month
            Button(action: { onNavigateMonth?(-1) }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(PlannerumColors.textTertiary)
                    .frame(width: 40, height: 40)
                    .background(PlannerumColors.glassSecondary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            // Month title
            VStack(spacing: 2) {
                Text(PlannerumFormatters.monthYear.string(from: centerDate))
                    .font(PlannerumTypography.subheader)
                    .foregroundColor(OnyxColors.Text.primary)
                    .tracking(0.5)

                // Month XP stats
                if viewModel.totalXP > 0 || viewModel.projectedXP > 0 {
                    HStack(spacing: 8) {
                        if viewModel.totalXP > 0 {
                            Text("\(viewModel.totalXP) XP earned")
                                .foregroundColor(PlannerumColors.nowMarker)
                        }
                        if viewModel.projectedXP > 0 {
                            Text("· \(viewModel.projectedXP) projected")
                                .foregroundColor(PlannerumColors.textMuted)
                        }
                    }
                    .font(PlannerumTypography.caption)
                }
            }

            Spacer()

            // Next month
            Button(action: { onNavigateMonth?(1) }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(PlannerumColors.textTertiary)
                    .frame(width: 40, height: 40)
                    .background(PlannerumColors.glassSecondary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, PlannerumLayout.contentPadding)
        .padding(.vertical, PlannerumLayout.spacingMD)
    }

    // MARK: - Weekday Header

    private var weekdayHeader: some View {
        HStack(spacing: Layout.cellSpacing) {
            ForEach(weekdays, id: \.self) { day in
                Text(day)
                    .font(PlannerumTypography.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(PlannerumColors.textMuted)
                    .frame(width: Layout.cellSize, height: Layout.weekdayHeaderHeight)
            }
        }
        .padding(.horizontal, PlannerumLayout.contentPadding)
    }

    // MARK: - Week Row

    private func weekRow(week: [Date?]) -> some View {
        HStack(spacing: Layout.cellSpacing) {
            ForEach(Array(week.enumerated()), id: \.offset) { _, date in
                if let date = date {
                    dayCell(date: date)
                } else {
                    // Empty placeholder for days outside month
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: Layout.cellSize, height: Layout.cellSize)
                }
            }
        }
    }

    // MARK: - Day Cell (Spec Section 4.1)

    private func dayCell(date: Date) -> some View {
        let dayData = viewModel.dayData[calendar.startOfDay(for: date)] ?? MonthDayData.empty
        let isToday = calendar.isDateInToday(date)
        let isCurrentMonth = calendar.isDate(date, equalTo: centerDate, toGranularity: .month)
        let isPast = date < calendar.startOfDay(for: Date())
        let isFuture = date > calendar.startOfDay(for: Date())
        let isHovered = hoveredDay.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: date) } ?? false

        return Button(action: {
            withAnimation(PlannerumSprings.select) {
                selectedDay = date
            }
            onDaySelect(date)
        }) {
            ZStack {
                // Background with XP-based heat map
                RoundedRectangle(cornerRadius: PlannerumLayout.cornerRadiusSM)
                    .fill(heatMapColor(for: dayData, isPast: isPast, isCurrentMonth: isCurrentMonth))

                // Glass overlay
                RoundedRectangle(cornerRadius: PlannerumLayout.cornerRadiusSM)
                    .fill(PlannerumColors.glassPrimary)
                    .opacity(isCurrentMonth ? 0.3 : 0.15)

                // Border - Today gets glowing green (Spec: 2px #22C55E)
                RoundedRectangle(cornerRadius: PlannerumLayout.cornerRadiusSM)
                    .strokeBorder(
                        isToday ? PlannerumColors.nowMarker :
                        isSelected ? PlannerumColors.primary.opacity(0.6) :
                        isHovered ? PlannerumColors.glassBorder.opacity(0.5) :
                        PlannerumColors.glassBorder.opacity(isCurrentMonth ? 0.3 : 0.15),
                        lineWidth: isToday ? 2 : 1
                    )

                // Content
                VStack(spacing: 1) {
                    // Day number
                    Text("\(calendar.component(.day, from: date))")
                        .font(.system(size: 12, weight: isToday ? .bold : .medium))
                        .foregroundColor(dayTextColor(isToday: isToday, isCurrentMonth: isCurrentMonth, isPast: isPast))

                    // XP indicator or density
                    if dayData.xpEarned > 0 || dayData.xpProjected > 0 {
                        xpIndicator(for: dayData, isPast: isPast)
                    } else if dayData.blockCount > 0 {
                        densityIndicator(for: dayData)
                    } else if isFuture && isCurrentMonth {
                        // Unplanned future (Spec: small dot)
                        Circle()
                            .fill(PlannerumColors.textMuted.opacity(0.3))
                            .frame(width: 3, height: 3)
                    }
                }

                // Today glow effect
                if isToday {
                    RoundedRectangle(cornerRadius: PlannerumLayout.cornerRadiusSM)
                        .strokeBorder(PlannerumColors.nowMarker.opacity(0.3), lineWidth: 4)
                        .blur(radius: 4)
                }

                // Completed overlay
                if isPast && dayData.completionRate == 1.0 && dayData.blockCount > 0 {
                    completedCheckmark
                }
            }
            .frame(width: Layout.cellSize, height: Layout.cellSize)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(PlannerumSprings.hover) {
                hoveredDay = hovering ? date : nil
            }
        }
        .scaleEffect(isHovered ? 1.1 : (isSelected ? 1.05 : 1.0))
        .animation(PlannerumSprings.hover, value: isHovered)
        .animation(PlannerumSprings.select, value: isSelected)
        .zIndex(isHovered || isSelected ? 1 : 0)
    }

    // MARK: - XP Indicator

    private func xpIndicator(for dayData: MonthDayData, isPast: Bool) -> some View {
        Group {
            if isPast && dayData.xpEarned > 0 {
                // Actual XP earned (Spec: XP label for past)
                Text(formatXP(dayData.xpEarned))
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(PlannerumColors.nowMarker)
            } else if dayData.xpProjected > 0 {
                // Projected XP (Spec: XP label for future)
                Text(formatXP(dayData.xpProjected))
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundColor(PlannerumColors.textMuted)
            }
        }
    }

    // MARK: - Density Indicator

    private func densityIndicator(for dayData: MonthDayData) -> some View {
        HStack(spacing: 1) {
            ForEach(0..<min(dayData.blockCount, 3), id: \.self) { i in
                let blockType = dayData.blockTypes.indices.contains(i) ? dayData.blockTypes[i] : .deepWork
                Circle()
                    .fill(blockType.color)
                    .frame(width: 4, height: 4)
            }
            if dayData.blockCount > 3 {
                Text("+")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundColor(PlannerumColors.textMuted)
            }
        }
    }

    private var completedCheckmark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PlannerumLayout.cornerRadiusSM)
                .fill(PlannerumColors.nowMarker.opacity(0.1))

            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(PlannerumColors.nowMarker.opacity(0.5))
        }
    }

    // MARK: - Month Summary

    private var monthSummary: some View {
        VStack(spacing: PlannerumLayout.spacingSM) {
            // Legend
            HStack(spacing: 16) {
                legendItem(color: TimeBlockType.deepWork.color, label: "Deep Work")
                legendItem(color: TimeBlockType.creative.color, label: "Creative")
                legendItem(color: TimeBlockType.rest.color, label: "Rest")
                legendItem(color: TimeBlockType.meeting.color, label: "Meeting")
            }

            // Soft gradient divider (no hard cuts per plan)
            LinearGradient(
                colors: [Color.clear, PlannerumColors.glassBorder.opacity(0.4), Color.clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)

            // Stats row
            HStack {
                // Block count
                statItem(
                    icon: "square.stack.3d.up",
                    value: "\(viewModel.totalBlocks)",
                    label: "blocks"
                )

                Spacer()

                // Total duration
                statItem(
                    icon: "clock",
                    value: viewModel.totalDuration,
                    label: "scheduled"
                )

                Spacer()

                // Completion rate
                if viewModel.completionRate > 0 {
                    statItem(
                        icon: "checkmark.circle.fill",
                        value: "\(Int(viewModel.completionRate * 100))%",
                        label: "completed",
                        color: PlannerumColors.nowMarker
                    )
                }
            }
        }
        .padding(.horizontal, PlannerumLayout.contentPadding)
        .padding(.vertical, PlannerumLayout.spacingMD)
        // NO hard background - floats on realm atmosphere
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(PlannerumTypography.caption)
                .foregroundColor(PlannerumColors.textMuted)
        }
    }

    private func statItem(icon: String, value: String, label: String, color: Color = PlannerumColors.textSecondary) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(PlannerumTypography.blockDetail)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(PlannerumColors.textMuted)
            }
        }
    }

    // MARK: - Heat Map Color (Spec Section 4.1)

    /// Returns heat map color based on XP earned
    /// Spec: Low XP: dim gray, Medium XP: soft violet, High XP: bright violet with glow
    private func heatMapColor(for dayData: MonthDayData, isPast: Bool, isCurrentMonth: Bool) -> Color {
        guard isCurrentMonth else { return Color.clear }

        if isPast {
            // Heat map based on XP earned
            let xp = dayData.xpEarned
            if xp == 0 {
                return PlannerumColors.textMuted.opacity(0.05) // Dim gray
            } else if xp < 50 {
                return PlannerumColors.primary.opacity(0.1) // Low: soft violet
            } else if xp < 150 {
                return PlannerumColors.primary.opacity(0.2) // Medium: violet
            } else {
                return PlannerumColors.primary.opacity(0.35) // High: bright violet
            }
        } else {
            // Future: based on scheduled density
            let density = min(dayData.totalHours / 8.0, 1.0)
            return PlannerumColors.primary.opacity(density * 0.15)
        }
    }

    private func dayTextColor(isToday: Bool, isCurrentMonth: Bool, isPast: Bool) -> Color {
        if isToday {
            return PlannerumColors.nowMarker
        }
        if !isCurrentMonth {
            return PlannerumColors.textMuted.opacity(0.4)
        }
        if isPast {
            return PlannerumColors.textTertiary
        }
        return PlannerumColors.textSecondary
    }

    private func formatXP(_ xp: Int) -> String {
        if xp >= 1000 {
            return String(format: "%.1fk", Double(xp) / 1000.0)
        }
        return "\(xp)"
    }

    private func weekStableId(week: [Date?], index: Int) -> Int {
        week.first??.hashValue ?? index
    }

    // MARK: - Generate Weeks

    private func generateWeeks(for date: Date) -> [[Date?]] {
        var weeks: [[Date?]] = []
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)

        guard let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart)
        else {
            return []
        }

        // Find the first Monday on or before the month start
        var weekStart = monthStart
        while calendar.component(.weekday, from: weekStart) != 2 {  // 2 = Monday
            weekStart = calendar.date(byAdding: .day, value: -1, to: weekStart)!
        }

        // Generate weeks until we pass the month end
        while weekStart <= monthEnd || calendar.isDate(weekStart, equalTo: monthEnd, toGranularity: .weekOfYear) {
            var week: [Date?] = []
            for dayOffset in 0..<7 {
                let day = calendar.date(byAdding: .day, value: dayOffset, to: weekStart)!
                week.append(day)
            }
            weeks.append(week)
            weekStart = calendar.date(byAdding: .day, value: 7, to: weekStart)!

            // Safety: limit to 6 weeks
            if weeks.count >= 6 { break }
        }

        return weeks
    }
}

// MARK: - Month Day Data

public struct MonthDayData {
    public var blockCount: Int
    public var totalHours: Double
    public var completedCount: Int
    public var blockTypes: [TimeBlockType]
    public var xpEarned: Int      // Actual XP for past days
    public var xpProjected: Int   // Projected XP for future days

    public var completionRate: Double {
        guard blockCount > 0 else { return 0 }
        return Double(completedCount) / Double(blockCount)
    }

    public static var empty: MonthDayData {
        MonthDayData(
            blockCount: 0,
            totalHours: 0,
            completedCount: 0,
            blockTypes: [],
            xpEarned: 0,
            xpProjected: 0
        )
    }
}

// MARK: - Month Density View Model

@MainActor
public class MonthDensityViewModel: ObservableObject {

    @Published public var dayData: [Date: MonthDayData] = [:]
    @Published public var isLoading = false

    private var calendar = Calendar.current

    public var totalBlocks: Int {
        dayData.values.reduce(0) { $0 + $1.blockCount }
    }

    public var totalDuration: String {
        let hours = dayData.values.reduce(0.0) { $0 + $1.totalHours }
        if hours >= 1 {
            return String(format: "%.0fh", hours)
        }
        return "\(Int(hours * 60))m"
    }

    public var completionRate: Double {
        let total = dayData.values.reduce(0) { $0 + $1.blockCount }
        let completed = dayData.values.reduce(0) { $0 + $1.completedCount }
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    public var totalXP: Int {
        dayData.values.reduce(0) { $0 + $1.xpEarned }
    }

    public var projectedXP: Int {
        let today = calendar.startOfDay(for: Date())
        return dayData.filter { $0.key >= today }.values.reduce(0) { $0 + $1.xpProjected }
    }

    public func loadMonthData(for date: Date) async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Get month boundaries
            let month = calendar.component(.month, from: date)
            let year = calendar.component(.year, from: date)
            guard let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                  let monthEnd = calendar.date(byAdding: DateComponents(month: 1), to: monthStart)
            else { return }

            // Fetch all schedule blocks
            let atoms = try await AtomRepository.shared.fetchAll(type: .scheduleBlock)
                .filter { !$0.isDeleted }

            // Fetch XP events for the month
            let xpAtoms = try await AtomRepository.shared.fetchAll(type: .xpEvent)
                .filter { !$0.isDeleted }

            var result: [Date: MonthDayData] = [:]
            let today = calendar.startOfDay(for: Date())

            // Process each day in the month
            var currentDate = monthStart
            while currentDate < monthEnd {
                let dayStart = calendar.startOfDay(for: currentDate)
                let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
                let isPast = dayStart < today

                // Get blocks for this day
                let dayBlocks = atoms.compactMap { atom -> (TimeBlockType, TimeInterval, Bool)? in
                    guard let metadata = atom.metadataValue(as: ScheduleBlockMetadata.self),
                          let startTimeStr = metadata.startTime,
                          let startTime = PlannerumFormatters.iso8601.date(from: startTimeStr),
                          startTime >= dayStart && startTime < dayEnd
                    else {
                        return nil
                    }

                    let endTimeStr = metadata.endTime ?? startTimeStr
                    let endTime = PlannerumFormatters.iso8601.date(from: endTimeStr) ?? startTime.addingTimeInterval(3600)

                    let blockType = TimeBlockType.from(string: metadata.blockType ?? "deep_work")
                    let duration = endTime.timeIntervalSince(startTime)
                    let isCompleted = metadata.isCompleted ?? false

                    return (blockType, duration, isCompleted)
                }

                // Calculate XP for this day
                let dayXPEarned: Int
                if isPast {
                    dayXPEarned = xpAtoms.reduce(0) { total, atom in
                        guard let createdAtDate = PlannerumFormatters.iso8601.date(from: atom.createdAt),
                              createdAtDate >= dayStart && createdAtDate < dayEnd,
                              let metadata = atom.metadataValue(as: MonthXPEventMetadata.self)
                        else { return total }
                        return total + (metadata.xpAmount ?? 0)
                    }
                } else {
                    dayXPEarned = 0
                }

                // Calculate projected XP for future
                let dayXPProjected: Int
                if !isPast && !dayBlocks.isEmpty {
                    dayXPProjected = dayBlocks.reduce(0) { total, block in
                        let durationMinutes = Int(block.1 / 60)
                        return total + PlannerumXP.estimateXP(blockType: block.0, durationMinutes: durationMinutes)
                    }
                } else {
                    dayXPProjected = 0
                }

                if !dayBlocks.isEmpty || dayXPEarned > 0 {
                    let totalHours = dayBlocks.reduce(0.0) { $0 + $1.1 / 3600.0 }
                    let completedCount = dayBlocks.filter { $0.2 }.count
                    let blockTypes = dayBlocks.map { $0.0 }

                    result[dayStart] = MonthDayData(
                        blockCount: dayBlocks.count,
                        totalHours: totalHours,
                        completedCount: completedCount,
                        blockTypes: blockTypes,
                        xpEarned: dayXPEarned,
                        xpProjected: dayXPProjected
                    )
                }

                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
            }

            dayData = result

        } catch {
            print("MonthDensityViewModel: Failed to load month data - \(error)")
        }
    }
}

// MARK: - Month XP Event Metadata (Local)

private struct MonthXPEventMetadata: Codable {
    var xpAmount: Int?
    var dimension: String?
    var source: String?
}

// MARK: - Preview

#if DEBUG
struct MonthDensityView_Previews: PreviewProvider {
    static var previews: some View {
        MonthDensityView(
            centerDate: Date(),
            onDaySelect: { _ in },
            onNavigateMonth: { _ in }
        )
        .frame(width: 400, height: 500)
        .background(PlannerumColors.voidPrimary)
        .preferredColorScheme(.dark)
    }
}
#endif
