// Canvas/CommandCenter/CommandCenterTaskMenus.swift
// Redesigned task action popover + reschedule panel
// Tabbed command palette with horizontal date chips + always-visible calendar
// March 2026

import SwiftUI

// MARK: - Standalone Reschedule Panel (for overdue batch actions)

struct CommandCenterReschedulePanel: View {
    let title: String
    var includeNoDate: Bool = true
    let onSelectDate: (Date?) -> Void

    @State private var manualInput = ""
    @State private var selectedDate = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            Text(title)
                .font(DS.buttonText)
                .foregroundStyle(DS.text)

            // Quick date chips
            quickDateChips { date in
                onSelectDate(date)
            }

            // Calendar
            inlineCalendar

            // Manual input (fallback, at bottom)
            TextField("Type a date...", text: $manualInput)
                .textFieldStyle(.plain)
                .font(DS.cardMeta)
                .foregroundStyle(DS.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(DS.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(DS.borderSubtle, lineWidth: 1))
                .onSubmit {
                    guard let parsed = parseDateInput(manualInput) else { return }
                    onSelectDate(parsed)
                }
        }
        .padding(12)
        .frame(width: 340)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.border, lineWidth: 1)
        )
        .dsFloatingShadow()
        .environment(\.colorScheme, .light)
    }

    // MARK: - Quick Date Chips

    @ViewBuilder
    private func quickDateChips(onSelect: @escaping (Date?) -> Void) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                dateChip("Today", icon: "sun.max", tint: DS.green, date: Date(), onSelect: onSelect)
                dateChip("Tomorrow", icon: "sunrise", tint: DS.orange, date: Calendar.current.date(byAdding: .day, value: 1, to: Date()), onSelect: onSelect)
                dateChip("Weekend", icon: "sparkles", tint: DS.accent, date: nextWeekendDate(), onSelect: onSelect)
                dateChip("+1 Wk", icon: "arrow.right", tint: DS.textSecondary, date: nextWeekStart(), onSelect: onSelect)
            }

            HStack(spacing: 6) {
                if includeNoDate {
                    dateChip("No date", icon: "slash.circle", tint: DS.textMuted, date: nil, onSelect: onSelect)
                }
                dateChip("Someday", icon: "archivebox", tint: DS.entityIdea, date: nil, onSelect: { _ in
                    // Someday = no date but with scheduling state
                    onSelect(nil)
                })
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func dateChip(_ label: String, icon: String, tint: Color, date: Date?, onSelect: @escaping (Date?) -> Void) -> some View {
        Button {
            onSelect(date)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(DS.caption2)
                Text(label)
                    .font(DS.caption2)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.08), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Inline Calendar

    private var inlineCalendar: some View {
        DatePicker(
            "",
            selection: $selectedDate,
            displayedComponents: [.date]
        )
        .datePickerStyle(.graphical)
        .labelsHidden()
        .tint(DS.accent)
        .environment(\.colorScheme, .light)
        .onChange(of: selectedDate) {
            onSelectDate(selectedDate)
        }
    }

    // MARK: - Date Helpers

    private func nextWeekendDate() -> Date? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let saturday = DayOfWeek.saturday.rawValue
        let delta = weekday <= saturday ? saturday - weekday : (7 - weekday) + saturday
        return calendar.date(byAdding: .day, value: delta, to: today)
    }

    private func nextWeekStart() -> Date? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let monday = DayOfWeek.monday.rawValue
        let delta = ((7 - weekday) + monday) % 7
        let normalized = delta == 0 ? 7 : delta
        return calendar.date(byAdding: .day, value: normalized, to: today)
    }

    private func parseDateInput(_ input: String) -> Date? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowercase = trimmed.lowercased()
        if lowercase == "today" { return Date() }
        if lowercase == "tomorrow" {
            return Calendar.current.date(byAdding: .day, value: 1, to: Date())
        }

        let weekdayMap: [String: DayOfWeek] = [
            "mon": .monday, "monday": .monday,
            "tue": .tuesday, "tues": .tuesday, "tuesday": .tuesday,
            "wed": .wednesday, "wednesday": .wednesday,
            "thu": .thursday, "thur": .thursday, "thurs": .thursday, "thursday": .thursday,
            "fri": .friday, "friday": .friday,
            "sat": .saturday, "saturday": .saturday,
            "sun": .sunday, "sunday": .sunday,
        ]

        if let weekday = weekdayMap[lowercase] {
            return nextDate(for: weekday)
        }

        let formats = ["M/d", "M/d/yyyy", "MMM d", "MMMM d", "MMM d yyyy", "MMMM d yyyy"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return normalizedDate(date, for: format)
            }
        }

        return nil
    }

    private func normalizedDate(_ date: Date, for format: String) -> Date {
        let calendar = Calendar.current
        if format.contains("yyyy") { return date }
        var components = calendar.dateComponents([.month, .day], from: date)
        components.year = calendar.component(.year, from: Date())
        let candidate = calendar.date(from: components) ?? date
        return candidate < calendar.startOfDay(for: Date())
            ? calendar.date(byAdding: .year, value: 1, to: candidate) ?? candidate
            : candidate
    }

    private func nextDate(for weekday: DayOfWeek) -> Date? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let current = calendar.component(.weekday, from: today)
        var delta = weekday.rawValue - current
        if delta < 0 { delta += 7 }
        return calendar.date(byAdding: .day, value: delta, to: today)
    }
}

// MARK: - Task Action Popover (tabbed command palette)

struct CommandCenterTaskActionPopover: View {
    let task: TaskViewModel
    let currentHabit: HabitDefinition?
    let availableHabits: [HabitDefinition]
    let loadRecurrenceRule: () async -> RecurrenceRule?
    let onToggleCompletion: () -> Void
    let onReschedule: (Date?) -> Void
    let onApplyHabit: (String?) -> Void
    let onApplyRecurrence: (RecurrenceRule?) -> Void
    let onDelete: () -> Void
    let onDismiss: () -> Void

    @State private var activeTab: ActionTab = .schedule
    @State private var recurrenceRule: RecurrenceRule?
    @State private var recurrencePreset: CommandCenterRepeatPreset = .weekly
    @State private var selectedDays: Set<DayOfWeek> = []
    @State private var isLoadingRecurrence = true
    @State private var manualDateInput = ""
    @State private var calendarDate = Date()

    private enum ActionTab: String {
        case schedule, recurrence, habit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: title + metadata
            header
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            // Divider
            Rectangle().fill(DS.borderSubtle).frame(height: 1)

            // Tab strip + action buttons
            tabStrip
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

            // Divider
            Rectangle().fill(DS.borderSubtle).frame(height: 1)

            // Tab content — fixed min height prevents popover resize crash on macOS
            tabContent
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: 200, alignment: .top)
        }
        .frame(width: 300)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.border, lineWidth: 1)
        )
        .dsFloatingShadow()
        .environment(\.colorScheme, .light)
        .animation(nil, value: activeTab)
        .task {
            recurrenceRule = await loadRecurrenceRule()
            hydrateRepeatEditor()
            isLoadingRecurrence = false
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(task.title)
                    .font(DS.headline)
                    .foregroundStyle(DS.text)
                    .lineLimit(1)

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                        .frame(width: 18, height: 18)
                        .background(DS.surface, in: Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                if let dueInfo = task.dueInfo {
                    metaBadge(dueInfo, icon: "calendar", color: task.isOverdue ? DS.red : DS.textMuted)
                }
                if recurrenceRule != nil || task.isRecurring {
                    metaBadge(recurrenceRule?.shortDisplayText ?? "Repeats", icon: "repeat", color: DS.accent)
                }
                if let currentHabit {
                    metaBadge(currentHabit.title, icon: currentHabit.icon, color: currentHabit.accent)
                }
            }
        }
    }

    @ViewBuilder
    private func metaBadge(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(DS.caption2)
            Text(text)
                .font(DS.caption2)
        }
        .foregroundStyle(color)
    }

    // MARK: - Tab Strip

    private var tabStrip: some View {
        HStack(spacing: 2) {
            // Complete button (standalone action, not a tab)
            Button {
                onToggleCompletion()
                onDismiss()
            } label: {
                Image(systemName: task.isCompleted ? "arrow.uturn.backward" : "checkmark")
                    .font(DS.caption2)
                    .foregroundStyle(task.isCompleted ? DS.textSecondary : DS.green)
                    .frame(width: 28, height: 28)
                    .background((task.isCompleted ? DS.surface : DS.green.opacity(0.1)), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "Mark incomplete" : "Complete task")

            // Schedule tab
            tabButton("calendar", label: "Schedule", tab: .schedule)

            // Recurrence tab
            tabButton("repeat", label: "Repeat", tab: .recurrence)

            // Habit tab
            tabButton("tag", label: "Habit", tab: .habit)

            Spacer()

            // Delete button (standalone action)
            Button {
                onDelete()
                onDismiss()
            } label: {
                Image(systemName: "trash")
                    .font(DS.caption2)
                    .foregroundStyle(DS.red.opacity(0.7))
                    .frame(width: 28, height: 28)
                    .background(DS.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete task")
        }
    }

    @ViewBuilder
    private func tabButton(_ icon: String, label: String, tab: ActionTab) -> some View {
        let isActive = activeTab == tab

        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                activeTab = tab
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(DS.caption2)
                Text(label)
                    .font(DS.caption2)
            }
            .foregroundStyle(isActive ? DS.accent : DS.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                isActive ? DS.accentSoft : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .schedule:
            scheduleContent
        case .recurrence:
            recurrenceContent
        case .habit:
            habitContent
        }
    }

    // MARK: - Schedule Tab

    private var scheduleContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Quick date chips — 2 rows
            VStack(spacing: 6) {
                HStack(spacing: 5) {
                    quickChip("Today", icon: "sun.max", tint: DS.green, date: Date())
                    quickChip("Tomorrow", icon: "sunrise", tint: DS.orange, date: Calendar.current.date(byAdding: .day, value: 1, to: Date()))
                    quickChip("Wknd", icon: "sparkles", tint: DS.accent, date: nextWeekendDate())
                    quickChip("+1 Wk", icon: "arrow.right", tint: DS.textSecondary, date: nextWeekStart())
                }

                HStack(spacing: 5) {
                    quickChip("Someday", icon: "archivebox", tint: DS.entityIdea, date: nil)
                    quickChip("No date", icon: "slash.circle", tint: DS.textMuted, date: nil)
                    Spacer()
                }
            }

            // Calendar
            DatePicker("", selection: $calendarDate, displayedComponents: [.date])
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(DS.accent)
                .environment(\.colorScheme, .light)
                .onChange(of: calendarDate) {
                    onReschedule(calendarDate)
                    onDismiss()
                }

            // Manual input
            TextField("Type a date...", text: $manualDateInput)
                .textFieldStyle(.plain)
                .font(DS.footnote)
                .foregroundStyle(DS.text)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(DS.surface, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(DS.borderSubtle, lineWidth: 1))
                .onSubmit {
                    guard let parsed = parseDateInput(manualDateInput) else { return }
                    onReschedule(parsed)
                    onDismiss()
                }
        }
    }

    @ViewBuilder
    private func quickChip(_ label: String, icon: String, tint: Color, date: Date?) -> some View {
        Button {
            onReschedule(date)
            onDismiss()
        } label: {
            HStack(spacing: 2) {
                Image(systemName: icon)
                    .font(DS.caption2)
                Text(label)
                    .font(DS.caption2)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(tint.opacity(0.08), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Schedule \(label)")
    }

    // MARK: - Recurrence Tab

    private var recurrenceContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isLoadingRecurrence {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Spacer()
                }
            } else {
                // Preset chips
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 6)], spacing: 6) {
                    ForEach(CommandCenterRepeatPreset.allCases, id: \.self) { preset in
                        Button {
                            recurrencePreset = preset
                            if selectedDays.isEmpty {
                                selectedDays = defaultDays(for: preset)
                            }
                        } label: {
                            Text(preset.label)
                                .font(DS.caption2)
                                .foregroundStyle(recurrencePreset == preset ? DS.textOnAccent : DS.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(
                                    recurrencePreset == preset ? DS.accent : DS.surface,
                                    in: RoundedRectangle(cornerRadius: 7)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(recurrencePreset == preset ? Color.clear : DS.borderSubtle, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Day selector (weekly/custom)
                if recurrencePreset.requiresDaySelection {
                    HStack(spacing: 4) {
                        ForEach(DayOfWeek.allCases, id: \.self) { day in
                            Button {
                                if selectedDays.contains(day) {
                                    selectedDays.remove(day)
                                } else {
                                    selectedDays.insert(day)
                                }
                            } label: {
                                Text(day.shortName)
                                    .font(DS.caption2)
                                    .foregroundStyle(selectedDays.contains(day) ? DS.textOnAccent : DS.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(
                                        selectedDays.contains(day) ? DS.accent : DS.surface,
                                        in: RoundedRectangle(cornerRadius: 6)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Action row
                HStack(spacing: 8) {
                    if recurrenceRule != nil || task.isRecurring {
                        Button("Stop repeating") {
                            onApplyRecurrence(nil)
                            onDismiss()
                        }
                        .font(DS.caption2)
                        .foregroundStyle(DS.red)
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Button("Apply") {
                        onApplyRecurrence(buildRule())
                        onDismiss()
                    }
                    .font(DS.caption2)
                    .foregroundStyle(DS.textOnAccent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(DS.accent, in: Capsule())
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Habit Tab

    private var habitContent: some View {
        VStack(spacing: 4) {
            habitChip(title: "None", icon: "slash.circle", tint: DS.textSecondary, selected: currentHabit == nil) {
                onApplyHabit(nil)
                onDismiss()
            }

            ForEach(availableHabits, id: \.id) { habit in
                habitChip(title: habit.title, icon: habit.icon, tint: habit.accent, selected: currentHabit?.id == habit.id) {
                    onApplyHabit(habit.id)
                    onDismiss()
                }
            }
        }
    }

    @ViewBuilder
    private func habitChip(title: String, icon: String, tint: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(DS.caption)
                    .foregroundStyle(tint)
                    .frame(width: 18)

                Text(title)
                    .font(DS.caption)
                    .foregroundStyle(DS.text)

                Spacer()

                if selected {
                    Image(systemName: "checkmark")
                        .font(DS.caption2)
                        .foregroundStyle(tint)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                selected ? tint.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Date Helpers

    private func nextWeekendDate() -> Date? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let saturday = DayOfWeek.saturday.rawValue
        let delta = weekday <= saturday ? saturday - weekday : (7 - weekday) + saturday
        return calendar.date(byAdding: .day, value: delta, to: today)
    }

    private func nextWeekStart() -> Date? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let monday = DayOfWeek.monday.rawValue
        let delta = ((7 - weekday) + monday) % 7
        let normalized = delta == 0 ? 7 : delta
        return calendar.date(byAdding: .day, value: normalized, to: today)
    }

    private func parseDateInput(_ input: String) -> Date? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowercase = trimmed.lowercased()
        if lowercase == "today" { return Date() }
        if lowercase == "tomorrow" {
            return Calendar.current.date(byAdding: .day, value: 1, to: Date())
        }

        let weekdayMap: [String: DayOfWeek] = [
            "mon": .monday, "monday": .monday,
            "tue": .tuesday, "tues": .tuesday, "tuesday": .tuesday,
            "wed": .wednesday, "wednesday": .wednesday,
            "thu": .thursday, "thur": .thursday, "thurs": .thursday, "thursday": .thursday,
            "fri": .friday, "friday": .friday,
            "sat": .saturday, "saturday": .saturday,
            "sun": .sunday, "sunday": .sunday,
        ]

        if let weekday = weekdayMap[lowercase] {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let current = calendar.component(.weekday, from: today)
            var delta = weekday.rawValue - current
            if delta < 0 { delta += 7 }
            return calendar.date(byAdding: .day, value: delta, to: today)
        }

        let formats = ["M/d", "M/d/yyyy", "MMM d", "MMMM d", "MMM d yyyy", "MMMM d yyyy"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                let calendar = Calendar.current
                if format.contains("yyyy") { return date }
                var components = calendar.dateComponents([.month, .day], from: date)
                components.year = calendar.component(.year, from: Date())
                let candidate = calendar.date(from: components) ?? date
                return candidate < calendar.startOfDay(for: Date())
                    ? calendar.date(byAdding: .year, value: 1, to: candidate) ?? candidate
                    : candidate
            }
        }

        return nil
    }

    // MARK: - Recurrence Logic

    private func hydrateRepeatEditor() {
        guard let recurrenceRule else {
            recurrencePreset = .weekly
            selectedDays = defaultDays(for: .weekly)
            return
        }

        switch recurrenceRule.frequency {
        case .daily: recurrencePreset = .daily
        case .weekdays: recurrencePreset = .weekdays
        case .monthly: recurrencePreset = .monthly
        case .weekly, .biweekly: recurrencePreset = .weekly
        case .custom: recurrencePreset = .custom
        case .yearly: recurrencePreset = .monthly
        }

        if let days = recurrenceRule.daysOfWeek {
            selectedDays = Set(days)
        } else {
            selectedDays = defaultDays(for: recurrencePreset)
        }
    }

    private func defaultDays(for preset: CommandCenterRepeatPreset) -> Set<DayOfWeek> {
        switch preset {
        case .daily, .monthly:
            let weekday = Calendar.current.component(.weekday, from: task.dueDate ?? Date())
            return Set(DayOfWeek.allCases.filter { $0.rawValue == weekday })
        case .weekdays:
            return Set(DayOfWeek.weekdays)
        case .weekly, .custom:
            let weekday = Calendar.current.component(.weekday, from: task.dueDate ?? Date())
            return Set(DayOfWeek.allCases.filter { $0.rawValue == weekday })
        }
    }

    private func buildRule() -> RecurrenceRule {
        switch recurrencePreset {
        case .daily: return .daily()
        case .weekdays: return .weekdays()
        case .weekly:
            let orderedDays = selectedDays.isEmpty ? Array(defaultDays(for: .weekly)) : Array(selectedDays)
            return .weekly(on: orderedDays.sorted { $0.rawValue < $1.rawValue })
        case .monthly:
            let day = Calendar.current.component(.day, from: task.dueDate ?? Date())
            return .monthly(onDay: day)
        case .custom:
            let orderedDays = selectedDays.isEmpty ? Array(defaultDays(for: .custom)) : Array(selectedDays)
            return RecurrenceRule(
                frequency: .custom, interval: 1,
                daysOfWeek: orderedDays.sorted { $0.rawValue < $1.rawValue },
                dayOfMonth: nil, monthOfYear: nil,
                endCondition: .never
            )
        }
    }
}

// MARK: - Repeat Preset Enum

private enum CommandCenterRepeatPreset: CaseIterable {
    case daily, weekdays, weekly, monthly, custom

    var label: String {
        switch self {
        case .daily: return "Daily"
        case .weekdays: return "Weekdays"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .custom: return "Custom"
        }
    }

    var requiresDaySelection: Bool {
        switch self {
        case .weekly, .custom: return true
        case .daily, .weekdays, .monthly: return false
        }
    }
}
