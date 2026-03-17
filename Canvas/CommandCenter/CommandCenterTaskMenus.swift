import SwiftUI

struct CommandCenterReschedulePanel: View {
    let title: String
    var includeNoDate: Bool = true
    let onSelectDate: (Date?) -> Void

    @State private var manualInput = ""
    @State private var selectedDate = Date()
    @State private var hoveredOptionId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.text)

            TextField("Type a date", text: $manualInput)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundColor(DS.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(DS.surface)
                )
                .onSubmit {
                    guard let parsed = parseDateInput(manualInput) else { return }
                    onSelectDate(parsed)
                }

            VStack(spacing: 6) {
                ForEach(quickOptions) { option in
                    Button {
                        onSelectDate(option.date)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: option.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(option.tint)
                                .frame(width: 22, height: 22)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(DS.text)

                                if let subtitle = option.subtitle {
                                    Text(subtitle)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(DS.textMuted)
                                }
                            }

                            Spacer()

                            if let trailing = option.trailing {
                                Text(trailing)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(DS.textSecondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(hoveredOptionId == option.id ? DS.surfaceHover : Color.clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .onHover { isHovering in
                        hoveredOptionId = isHovering ? option.id : (hoveredOptionId == option.id ? nil : hoveredOptionId)
                    }
                }
            }

            Divider()
                .foregroundColor(DS.borderSubtle)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(monthLabel(for: selectedDate))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DS.text)

                    Spacer()

                    Text("Calendar")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.textMuted)
                }

                DatePicker(
                    "",
                    selection: $selectedDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(DS.accent)
                .environment(\.colorScheme, .light)
                .background(DS.surfaceElevated)
                .onChange(of: selectedDate) {
                    onSelectDate(selectedDate)
                }
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DS.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
        .shadow(color: .black.opacity(0.05), radius: 32, y: 16)
        .environment(\.colorScheme, .light)
    }

    private var quickOptions: [CommandCenterQuickDateOption] {
        var options: [CommandCenterQuickDateOption] = [
            .init(
                title: "Today",
                subtitle: "Move overdue work back into today",
                trailing: weekdayAbbrev(for: Date()),
                icon: "calendar",
                tint: DS.green,
                date: Date()
            ),
            .init(
                title: "Tomorrow",
                subtitle: "Push it one day forward",
                trailing: weekdayAbbrev(for: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()),
                icon: "sun.max",
                tint: DS.orange,
                date: Calendar.current.date(byAdding: .day, value: 1, to: Date())
            ),
            .init(
                title: "This weekend",
                subtitle: "Land it on the next Saturday",
                trailing: shortDate(for: nextWeekendDate()),
                icon: "sparkles",
                tint: DS.accent,
                date: nextWeekendDate()
            ),
            .init(
                title: "Next week",
                subtitle: "Move it to next Monday",
                trailing: shortDate(for: nextWeekStart()),
                icon: "arrow.right",
                tint: DS.textSecondary,
                date: nextWeekStart()
            )
        ]

        if includeNoDate {
            options.append(
                .init(
                    title: "No date",
                    subtitle: "Keep it unscheduled",
                    trailing: nil,
                    icon: "slash.circle",
                    tint: DS.textMuted,
                    date: nil
                )
            )
        }

        return options
    }

    private func monthLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private func weekdayAbbrev(for date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private func shortDate(for date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

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
        if format.contains("yyyy") {
            return date
        }

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

    @State private var showReschedule = false
    @State private var showHabitEditor = false
    @State private var showRepeatEditor = false
    @State private var hoveredAction: String?
    @State private var recurrenceRule: RecurrenceRule?
    @State private var recurrencePreset: CommandCenterRepeatPreset = .daily
    @State private var selectedDays: Set<DayOfWeek> = []
    @State private var isLoadingRecurrence = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.text)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let dueInfo = task.dueInfo {
                        Label(dueInfo, systemImage: "calendar")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(task.isOverdue ? PlannerumColors.overdue : DS.textMuted)
                    }

                    if recurrenceRule != nil || task.isRecurring {
                        Label(recurrenceRule?.shortDisplayText ?? "Repeats", systemImage: "repeat")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DS.accent)
                    }

                    if let currentHabit {
                        Label(currentHabit.title, systemImage: currentHabit.icon)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(currentHabit.accent)
                    }
                }
            }

            VStack(spacing: 6) {
                actionRow(
                    title: task.isCompleted ? "Mark incomplete" : "Complete task",
                    icon: task.isCompleted ? "circle" : "checkmark.circle",
                    tint: task.isCompleted ? DS.textSecondary : DS.green
                ) {
                    onToggleCompletion()
                    onDismiss()
                }

                actionRow(
                    title: "Reschedule",
                    icon: "calendar.badge.clock",
                    tint: PlannerumColors.overdue,
                    trailing: showReschedule ? "Hide" : "Pick"
                ) {
                    withAnimation(ProMotionSprings.snappy) {
                        showReschedule.toggle()
                        showHabitEditor = false
                        showRepeatEditor = false
                    }
                }

                actionRow(
                    title: "Habit",
                    icon: currentHabit?.icon ?? "repeat",
                    tint: currentHabit?.accent ?? DS.textSecondary,
                    trailing: currentHabit?.title ?? "None"
                ) {
                    withAnimation(ProMotionSprings.snappy) {
                        showHabitEditor.toggle()
                        showReschedule = false
                        showRepeatEditor = false
                    }
                }

                actionRow(
                    title: recurrenceRule == nil ? "Make recurring" : "Edit recurrence",
                    icon: "repeat",
                    tint: DS.accent,
                    trailing: recurrenceRule?.shortDisplayText ?? "New"
                ) {
                    withAnimation(ProMotionSprings.snappy) {
                        showRepeatEditor.toggle()
                        showReschedule = false
                    }
                }

                actionRow(
                    title: "Delete",
                    icon: "trash",
                    tint: DS.red
                ) {
                    onDelete()
                    onDismiss()
                }
            }

            if showReschedule {
                CommandCenterReschedulePanel(title: "Reschedule task") { date in
                    onReschedule(date)
                    onDismiss()
                }
                .padding(.top, 4)
            }

            if showHabitEditor {
                habitEditor
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if showRepeatEditor {
                repeatEditor
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .frame(width: 340)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DS.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
        .shadow(color: .black.opacity(0.05), radius: 32, y: 16)
        .environment(\.colorScheme, .light)
        .task {
            recurrenceRule = await loadRecurrenceRule()
            hydrateRepeatEditor()
            isLoadingRecurrence = false
        }
    }

    private var habitEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .foregroundColor(DS.borderSubtle)

            HStack {
                Text("Habit")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.text)

                Spacer()

                if let currentHabit {
                    Text(currentHabit.title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(currentHabit.accent)
                }
            }

            VStack(spacing: 4) {
                habitOption(
                    title: "No habit",
                    icon: "slash.circle",
                    tint: DS.textSecondary,
                    selected: currentHabit == nil
                ) {
                    onApplyHabit(nil)
                    onDismiss()
                }

                ForEach(availableHabits, id: \.id) { habit in
                    habitOption(
                        title: habit.title,
                        icon: habit.icon,
                        tint: habit.accent,
                        selected: currentHabit?.id == habit.id
                    ) {
                        onApplyHabit(habit.id)
                        onDismiss()
                    }
                }
            }
        }
    }

    private var repeatEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .foregroundColor(DS.borderSubtle)

            HStack {
                Text("Repeat")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.text)

                Spacer()

                if isLoadingRecurrence {
                    ProgressView()
                        .controlSize(.small)
                } else if let recurrenceRule {
                    Text(recurrenceRule.displayText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.textMuted)
                        .lineLimit(1)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                ForEach(CommandCenterRepeatPreset.allCases, id: \.self) { preset in
                    Button {
                        recurrencePreset = preset
                        if selectedDays.isEmpty {
                            selectedDays = defaultDays(for: preset)
                        }
                    } label: {
                        Text(preset.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(recurrencePreset == preset ? DS.textOnAccent : DS.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(recurrencePreset == preset ? DS.accent : DS.surface)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            if recurrencePreset.requiresDaySelection {
                HStack(spacing: 6) {
                    ForEach(DayOfWeek.allCases, id: \.self) { day in
                        Button {
                            if selectedDays.contains(day) {
                                selectedDays.remove(day)
                            } else {
                                selectedDays.insert(day)
                            }
                        } label: {
                            Text(day.shortName)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(selectedDays.contains(day) ? DS.textOnAccent : DS.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedDays.contains(day) ? DS.accent : DS.surface)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                if recurrenceRule != nil || task.isRecurring {
                    Button {
                        onApplyRecurrence(nil)
                        onDismiss()
                    } label: {
                        Text("Stop repeating")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(DS.red)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.textSecondary)
                }
                .buttonStyle(.plain)

                Button {
                    onApplyRecurrence(buildRule())
                    onDismiss()
                } label: {
                    Text("Apply")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(DS.textOnAccent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(DS.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func actionRow(
        title: String,
        icon: String,
        tint: Color,
        trailing: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let isRowHovered = hoveredAction == title

        return Button(action: action) {
            HStack(spacing: 0) {
                // Accent bar — matches BlockContextMenu pattern
                RoundedRectangle(cornerRadius: 1)
                    .fill(isRowHovered ? tint : Color.clear)
                    .frame(width: 2, height: 16)
                    .padding(.trailing, 8)

                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isRowHovered ? tint : tint.opacity(0.7))
                    .frame(width: 22, height: 22)

                Text(title)
                    .font(.system(size: 12, weight: isRowHovered ? .semibold : .medium))
                    .foregroundColor(DS.text)
                    .padding(.leading, 2)

                Spacer()

                if let trailing {
                    Text(trailing)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.textMuted)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isRowHovered ? DS.surfaceHover : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.1), value: isRowHovered)
        .onHover { isHovering in
            hoveredAction = isHovering ? title : (hoveredAction == title ? nil : hoveredAction)
        }
    }

    private func habitOption(
        title: String,
        icon: String,
        tint: Color,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(tint)
                    .frame(width: 22, height: 22)

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.text)

                Spacer()

                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(tint)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? DS.accentSoft : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func hydrateRepeatEditor() {
        guard let recurrenceRule else {
            recurrencePreset = .weekly
            selectedDays = defaultDays(for: .weekly)
            return
        }

        switch recurrenceRule.frequency {
        case .daily:
            recurrencePreset = .daily
        case .weekdays:
            recurrencePreset = .weekdays
        case .monthly:
            recurrencePreset = .monthly
        case .weekly, .biweekly:
            recurrencePreset = .weekly
        case .custom:
            recurrencePreset = .custom
        case .yearly:
            recurrencePreset = .monthly
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
        case .daily:
            return .daily()
        case .weekdays:
            return .weekdays()
        case .weekly:
            let orderedDays = selectedDays.isEmpty ? Array(defaultDays(for: .weekly)) : Array(selectedDays)
            return .weekly(on: orderedDays.sorted { $0.rawValue < $1.rawValue })
        case .monthly:
            let day = Calendar.current.component(.day, from: task.dueDate ?? Date())
            return .monthly(onDay: day)
        case .custom:
            let orderedDays = selectedDays.isEmpty ? Array(defaultDays(for: .custom)) : Array(selectedDays)
            return RecurrenceRule(
                frequency: .custom,
                interval: 1,
                daysOfWeek: orderedDays.sorted { $0.rawValue < $1.rawValue },
                dayOfMonth: nil,
                monthOfYear: nil,
                endCondition: .never
            )
        }
    }
}

private struct CommandCenterQuickDateOption: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let trailing: String?
    let icon: String
    let tint: Color
    let date: Date?
}

private enum CommandCenterRepeatPreset: CaseIterable {
    case daily
    case weekdays
    case weekly
    case monthly
    case custom

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
        case .weekly, .custom:
            return true
        case .daily, .weekdays, .monthly:
            return false
        }
    }
}
