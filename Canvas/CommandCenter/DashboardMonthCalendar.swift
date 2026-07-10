// Canvas/CommandCenter/DashboardMonthCalendar.swift
// Compact month calendar for the Command Center Dashboard
// Click a day to filter tasks for that date
// March 2026

import SwiftUI

struct DashboardMonthCalendar: View {

    var viewModel: CommandCenterDashboardViewModel

    @State private var displayedMonth: Date = Date()
    @State private var hoveredDay: Int?

    private let weekdays = ["M", "T", "W", "T", "F", "S", "S"]
    private let cellSize: CGFloat = 30
    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            monthHeader
            weekdayLabels
            dayGrid
        }
    }

    // MARK: - Month Header

    private var monthHeader: some View {
        HStack {
            Text(monthYearText)
                .font(DS.headline)
                .foregroundColor(DS.text)

            Spacer()

            Button { changeMonth(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(DS.caption)
                    .foregroundColor(DS.textSecondary)
            }
            .buttonStyle(.plain)

            if !calendar.isDate(displayedMonth, equalTo: Date(), toGranularity: .month) {
                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        displayedMonth = Date()
                        viewModel.selectedDate = Date()
                    }
                } label: {
                    Text("Today")
                        .font(DS.caption2).fontWeight(.medium)
                        .foregroundColor(DS.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DS.accentSoft, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            Button { changeMonth(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(DS.caption)
                    .foregroundColor(DS.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Weekday Labels

    private var weekdayLabels: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdays.enumerated()), id: \.offset) { _, day in
                Text(day)
                    .font(DS.caption2).fontWeight(.medium)
                    .foregroundStyle(DS.textMuted)
                    .frame(width: cellSize, height: 16)
            }
        }
    }

    // MARK: - Day Grid

    private var dayGrid: some View {
        let weeks = generateWeeks()

        return VStack(spacing: 2) {
            ForEach(0..<weeks.count, id: \.self) { weekIndex in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { dayIndex in
                        let date = weeks[weekIndex][dayIndex]
                        dayCell(date: date)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(date: Date?) -> some View {
        if let date = date {
            let isSelected = calendar.isDate(date, inSameDayAs: viewModel.selectedDate)
            let isToday = calendar.isDateInToday(date)
            let dayNumber = calendar.component(.day, from: date)
            let isHovered = hoveredDay == dayNumber && !isSelected

            Button {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.selectedDate = date
                }
            } label: {
                VStack(spacing: 1) {
                    Text("\(dayNumber)")
                        .font(DS.subheadline).fontWeight(isToday ? .bold : .regular)
                        .foregroundColor(dayTextColor(isSelected: isSelected, isToday: isToday))

                    // Task density dot
                    Circle()
                        .fill(isToday && !isSelected ? DS.accent : DS.textMuted.opacity(0.3))
                        .frame(width: 3, height: 3)
                        .opacity(isToday ? 1 : 0)
                }
                .frame(width: cellSize, height: cellSize)
                .background(
                    ZStack {
                        if isSelected {
                            Circle()
                                .fill(DS.accent)
                                .frame(width: 28, height: 28)
                        } else if isHovered {
                            Circle()
                                .stroke(DS.borderActive, lineWidth: 1)
                                .frame(width: 28, height: 28)
                        }
                    }
                )
                .animation(.easeOut(duration: 0.1), value: isHovered)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                hoveredDay = hovering ? dayNumber : (hoveredDay == dayNumber ? nil : hoveredDay)
            }
        } else {
            Color.clear
                .frame(width: cellSize, height: cellSize)
        }
    }

    private func dayTextColor(isSelected: Bool, isToday: Bool) -> Color {
        if isSelected { return .white }
        if isToday { return DS.accent }
        return DS.text
    }

    // MARK: - Week Generation

    private func generateWeeks() -> [[Date?]] {
        let components = calendar.dateComponents([.year, .month], from: displayedMonth)
        guard let firstOfMonth = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else {
            return []
        }

        // Monday = 1 in ISO, Sunday = 7
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        // Convert to Monday-based offset (Mon=0, Tue=1, ..., Sun=6)
        let offset = (firstWeekday + 5) % 7

        var weeks: [[Date?]] = []
        var currentWeek: [Date?] = Array(repeating: nil, count: offset)

        for day in range {
            if let date = calendar.date(bySetting: .day, value: day, of: firstOfMonth) {
                currentWeek.append(date)
                if currentWeek.count == 7 {
                    weeks.append(currentWeek)
                    currentWeek = []
                }
            }
        }

        // Pad final week
        if !currentWeek.isEmpty {
            while currentWeek.count < 7 {
                currentWeek.append(nil)
            }
            weeks.append(currentWeek)
        }

        return weeks
    }

    // MARK: - Helpers

    private var monthYearText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: displayedMonth)
    }

    private func changeMonth(by value: Int) {
        withAnimation(ProMotionSprings.snappy) {
            if let newMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) {
                displayedMonth = newMonth
            }
        }
    }
}
