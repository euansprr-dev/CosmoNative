// CosmoOS/UI/CommandK/Forms/CommandKComposerFields.swift
// Per-shape field stacks for the Command-K composer pane, mirroring the iOS
// plus-orb sheets (IdeaComposerView, TaskComposerView, CaptureSheet) with Mac
// manners: hover, tooltips, Tab chains, menus instead of sheets.
//
// Every form is built on the shared chassis (CommandKComposerRows.swift):
// boxless hero fields on the pane paper, ONE grouped rows container below,
// the single section-label voice, tint-wash chips. One sheet of paper.

import SwiftUI

// MARK: - Idea (title · idea text · brand/format/platform · hooks · outline)

struct CommandKIdeaComposerFields: View {
    let pane: CommandKComposerPane
    let clients: [CommandKComposerClient]
    @Binding var hookDraft: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            CommandKComposerHeroTitleField(
                placeholder: "Idea title",
                text: pane.binding(.title),
                accent: DS.entityIdea,
                focus: pane.focusBinding,
                onSubmit: pane.commit
            )
            CommandKComposerHeroEditor(
                placeholder: "What's the idea?",
                text: pane.binding(.body, manualEdit: true),
                accent: DS.entityIdea,
                focus: pane.focusBinding,
                field: .body,
                minHeight: 56
            )
            chipRow
            CommandKComposerInspiredBySection(pane: pane)
            CommandKComposerHooksSection(pane: pane, hookDraft: $hookDraft)
            CommandKComposerOutlineSection(pane: pane)
        }
    }

    private var chipRow: some View {
        HStack(spacing: DS.space8) {
            CommandKComposerMenuChip(
                icon: "person.crop.square",
                label: brandLabel,
                isSet: !pane.binding(.client).wrappedValue.isEmpty,
                tint: DS.entityIdea,
                help: "Brand this idea belongs to"
            ) {
                Button("No brand") { setClient(nil) }
                ForEach(clients) { client in
                    Button(client.name) { setClient(client) }
                }
            }
            CommandKComposerMenuChip(
                icon: "rectangle.3.group",
                label: formatLabel,
                isSet: !pane.binding(.format).wrappedValue.isEmpty,
                tint: DS.entityIdea,
                help: "Content format"
            ) {
                Button("Any format") { pane.binding(.format, manualEdit: true).wrappedValue = "" }
                ForEach(ContentFormat.allCases, id: \.self) { candidate in
                    Button(candidate.displayName) {
                        pane.binding(.format, manualEdit: true).wrappedValue = candidate.rawValue
                    }
                }
            }
            CommandKComposerMenuChip(
                icon: "antenna.radiowaves.left.and.right",
                label: platformLabel,
                isSet: !pane.binding(.platform).wrappedValue.isEmpty,
                tint: DS.entityIdea,
                help: "Target platform"
            ) {
                Button("Any platform") { pane.binding(.platform, manualEdit: true).wrappedValue = "" }
                ForEach(IdeaPlatform.allCases, id: \.self) { candidate in
                    Button(candidate.displayName) {
                        pane.binding(.platform, manualEdit: true).wrappedValue = candidate.rawValue
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var brandLabel: String {
        let name = pane.binding(.client).wrappedValue
        return name.isEmpty ? "Brand" : name
    }

    private var formatLabel: String {
        ContentFormat(rawValue: pane.binding(.format).wrappedValue)?.displayName ?? "Format"
    }

    private var platformLabel: String {
        IdeaPlatform(rawValue: pane.binding(.platform).wrappedValue)?.displayName ?? "Platform"
    }

    private func setClient(_ client: CommandKComposerClient?) {
        pane.mutateDraft { draft in
            draft.form.setValue(client?.name ?? "", for: .client)
            draft.clientUUID = client?.uuid
        }
    }
}

// MARK: - Task (title · notes · schedule · details · checklist)

/// The parseable facets of the quick-add grammar. A manual touch on a row
/// takes that facet away from the parser; dismissing a chip suppresses it.
enum CommandKTaskQuickAddFacet: Hashable {
    case due, time, recurrence, duration, priority, intent, habit
}

struct CommandKTaskComposerFields: View {
    let pane: CommandKComposerPane

    @State private var checklistDraft = ""

    // Quick-add grammar (TaskInputParser — the Command Center's parser).
    @State private var parsed: ParsedTaskInput?
    @State private var suppressedFacets: Set<CommandKTaskQuickAddFacet> = []
    @State private var manualFacets: Set<CommandKTaskQuickAddFacet> = []

    private var calendar: Calendar { .current }
    private var today: Date { calendar.startOfDay(for: .now) }
    private var tomorrow: Date { calendar.date(byAdding: .day, value: 1, to: today) ?? today }
    private var draft: CommandKComposerDraft? { pane.viewModel.composerDraft }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            VStack(alignment: .leading, spacing: DS.space8) {
                CommandKComposerHeroTitleField(
                    placeholder: "Task title — try \u{201C}gym tomorrow at 6pm for 1h\u{201D}",
                    text: pane.binding(.title),
                    accent: DS.entityTask,
                    focus: pane.focusBinding,
                    onSubmit: pane.commit
                )
                if hasParsedChips {
                    quickAddChipsRow
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            CommandKComposerHeroEditor(
                placeholder: "Notes",
                text: pane.binding(.notes, manualEdit: true),
                accent: DS.entityTask,
                focus: pane.focusBinding,
                field: .notes,
                minHeight: 22,
                lineLimit: 1...6
            )
            scheduleSection
            detailsSection
            checklistSection
        }
        .onAppear(perform: reparse)
        .onChange(of: pane.binding(.title).wrappedValue) { _, _ in reparse() }
    }

    // MARK: Quick-add grammar (parse → chips → mirrored rows)

    private var hasParsedChips: Bool {
        guard let parsed else { return false }
        return parsed.dueDate != nil || parsed.scheduledTime != nil
            || parsed.recurrenceRule != nil || parsed.durationMinutes != nil
            || parsed.priority != nil || parsed.intent != nil || parsed.habitUUID != nil
    }

    private var quickAddChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.space6) {
                if let parsed {
                    if let day = parsed.dueDate {
                        quickAddChip(.due, icon: "calendar", label: relativeDayLabel(day))
                    }
                    if let time = parsed.scheduledTime {
                        quickAddChip(.time, icon: "clock", label: time.formatted(date: .omitted, time: .shortened))
                    }
                    if let rule = parsed.recurrenceRule {
                        quickAddChip(.recurrence, icon: "repeat", label: rule.shortDisplayText)
                    }
                    if let minutes = parsed.durationMinutes {
                        quickAddChip(.duration, icon: "hourglass", label: Self.minutesLabel(minutes))
                    }
                    if let priority = parsed.priority {
                        quickAddChip(.priority, icon: "flag", label: priority.displayName)
                    }
                    if let intent = parsed.intent {
                        quickAddChip(.intent, icon: intent.iconName, label: intent.displayName)
                    }
                    if let habitTitle = parsed.habitTitle {
                        quickAddChip(
                            .habit,
                            icon: parsed.habitIcon ?? "flame",
                            label: habitTitle,
                            tint: parsed.habitColorHex.map { Color(hex: $0) } ?? DS.entityTask
                        )
                    }
                }
            }
        }
    }

    /// One whole-chip target: clicking dismisses the capture — the phrase
    /// stays in the title as plain text (the iOS composer's rule).
    private func quickAddChip(
        _ facet: CommandKTaskQuickAddFacet,
        icon: String,
        label: String,
        tint: Color = DS.entityTask
    ) -> some View {
        Button {
            suppressedFacets.insert(facet)
            reparse()
        } label: {
            HStack(spacing: DS.space6) {
                Image(systemName: icon)
                    .font(DS.caption2)
                    .accessibilityHidden(true)
                Text(label)
                    .font(DS.caption.weight(.medium))
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(DS.caption2.weight(.semibold))
                    .imageScale(.small)
                    .foregroundStyle(tint.opacity(0.55))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space6)
            .background(tint.opacity(0.10), in: .capsule)
            .overlay(Capsule().strokeBorder(tint.opacity(0.18), lineWidth: 0.5))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help("Remove \(label)")
        .accessibilityLabel("Remove \(label)")
    }

    private func relativeDayLabel(_ day: Date) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInTomorrow(day) { return "Tomorrow" }
        let sameYear = calendar.isDate(day, equalTo: .now, toGranularity: .year)
        return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            + (sameYear ? "" : day.formatted(.dateTime.year()))
    }

    private func reparse() {
        let title = pane.binding(.title).wrappedValue
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            withAnimation(ProMotionSprings.snappy) { parsed = nil }
            applyParsed(nil)
            return
        }
        var result = TaskInputParser.parse(title)
        if suppressedFacets.contains(.due) { result.dueDate = nil }
        if suppressedFacets.contains(.time) { result.scheduledTime = nil }
        if suppressedFacets.contains(.recurrence) { result.recurrenceRule = nil }
        if suppressedFacets.contains(.duration) { result.durationMinutes = nil }
        if suppressedFacets.contains(.priority) { result.priority = nil }
        if suppressedFacets.contains(.intent) {
            result.intent = nil
            result.intentUUID = nil
        }
        if suppressedFacets.contains(.habit) {
            result.habitUUID = nil
            result.habitTitle = nil
            result.habitIcon = nil
            result.habitColorHex = nil
            result.habitAssignmentSource = nil
        }
        withAnimation(ProMotionSprings.snappy) { parsed = result }
        applyParsed(result)
    }

    /// Mirror parsed facets into the rows below. Manual edits win per facet;
    /// the cleaned title only replaces the raw one when nothing is suppressed
    /// (a suppressed facet's phrase must survive in the saved title).
    private func applyParsed(_ result: ParsedTaskInput?) {
        pane.mutateDraft { draft in
            if !manualFacets.contains(.due) {
                if let day = result?.dueDate {
                    draft.form.setValue(ISO8601.string(from: calendar.startOfDay(for: day)), for: .date)
                } else {
                    draft.form.setValue("", for: .date)
                }
            }
            if !manualFacets.contains(.time) {
                draft.scheduledTime = result?.scheduledTime
            }
            if !manualFacets.contains(.recurrence) {
                draft.recurrenceRule = result?.recurrenceRule
            }
            if !manualFacets.contains(.duration) {
                draft.durationMinutes = result?.durationMinutes
            }
            if !manualFacets.contains(.priority), let priority = result?.priority {
                draft.form.setValue(priority.rawValue, for: .priority)
            }
            if !manualFacets.contains(.intent), let intent = result?.intent {
                draft.form.setValue(intent.rawValue, for: .intent)
            }
            draft.suppressHabit = suppressedFacets.contains(.habit)
            if let result, suppressedFacets.isEmpty {
                let cleaned = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let raw = draft.form.value(for: .title)
                draft.cleanedTitle = (!cleaned.isEmpty && cleaned != raw) ? cleaned : nil
            } else {
                draft.cleanedTitle = nil
            }
        }
    }

    private func markManual(_ facet: CommandKTaskQuickAddFacet) {
        manualFacets.insert(facet)
    }

    // MARK: Schedule

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            CommandKComposerSectionLabel(label: "Schedule")
            CommandKComposerRowGroup {
                quickChipsRow
                dueDateRow
                plannedForRow
                repeatsRow
                if needsDaySelection {
                    dayPickerRow
                }
            }
        }
    }

    private var quickChipsRow: some View {
        CommandKComposerCustomRow {
            HStack(spacing: DS.space8) {
                CommandKComposerChoiceChip(
                    label: "Today",
                    isOn: isDue(today),
                    tint: DS.entityTask,
                    help: "Due today"
                ) { toggleDue(today) }
                CommandKComposerChoiceChip(
                    label: "Tomorrow",
                    isOn: isDue(tomorrow),
                    tint: DS.entityTask,
                    help: "Due tomorrow"
                ) { toggleDue(tomorrow) }
                Spacer(minLength: 0)
            }
        }
    }

    private var dueDateRow: some View {
        CommandKComposerRow(icon: "calendar", label: "Due date", help: "When this is due") {
            if let dueDate {
                HStack(spacing: DS.space6) {
                    DatePicker(
                        "Due date",
                        selection: Binding(
                            get: { dueDate },
                            set: { setDue(calendar.startOfDay(for: $0)) }
                        ),
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .font(DS.callout)
                    CommandKComposerRemoveButton(label: "Clear due date") {
                        markManual(.due)
                        pane.binding(.date, manualEdit: true).wrappedValue = ""
                    }
                }
            } else {
                Button {
                    setDue(today)
                } label: {
                    CommandKComposerRowValueLabel(text: "None", isSet: false, tint: DS.entityTask)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Set due date")
            }
        }
    }

    private var plannedForRow: some View {
        CommandKComposerRow(icon: "star", label: "Planned for", help: "The day you plan to work on this") {
            if let focusDate = draft?.focusDate {
                HStack(spacing: DS.space6) {
                    DatePicker(
                        "Planned for",
                        selection: Binding(
                            get: { focusDate },
                            set: { newValue in
                                let day = calendar.startOfDay(for: newValue)
                                pane.mutateDraft { $0.focusDate = day }
                            }
                        ),
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .font(DS.callout)
                    CommandKComposerRemoveButton(label: "Clear planned date") {
                        pane.mutateDraft { $0.focusDate = nil }
                    }
                }
            } else {
                Button {
                    pane.mutateDraft { $0.focusDate = today }
                } label: {
                    CommandKComposerRowValueLabel(text: "None", isSet: false, tint: DS.entityTask)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Set planned date")
            }
        }
    }

    private var repeatsRow: some View {
        CommandKComposerRow(icon: "repeat", label: "Repeats", help: "Make this a repeating task") {
            Menu {
                Button("Never") { setRule(nil) }
                Divider()
                Button("Daily") { setRule(.daily()) }
                Button("Weekdays") { setRule(.weekdays()) }
                Button("Weekly") { setRule(.weekly(on: [anchorWeekday])) }
                Button("Monthly") { setRule(.monthly(onDay: anchorDayOfMonth)) }
                Button("Custom days") {
                    setRule(RecurrenceRule(
                        frequency: .custom,
                        interval: 1,
                        daysOfWeek: [anchorWeekday],
                        dayOfMonth: nil,
                        monthOfYear: nil,
                        endCondition: .never
                    ))
                }
            } label: {
                CommandKComposerRowValueLabel(
                    text: draft?.recurrenceRule?.shortDisplayText ?? "Never",
                    isSet: draft?.recurrenceRule != nil,
                    tint: DS.entityTask
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var needsDaySelection: Bool {
        guard let frequency = draft?.recurrenceRule?.frequency else { return false }
        return frequency == .weekly || frequency == .custom
    }

    private var dayPickerRow: some View {
        CommandKComposerCustomRow {
            HStack(spacing: DS.space4) {
                ForEach(DayOfWeek.allCases) { day in
                    dayChip(day)
                }
            }
        }
    }

    private func dayChip(_ day: DayOfWeek) -> some View {
        let isOn = draft?.recurrenceRule?.daysOfWeek?.contains(day) == true
        return Button {
            toggleDay(day)
        } label: {
            Text(day.shortName)
                .font(DS.caption2.weight(isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? DS.entityTask : DS.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.space6)
                .background(
                    isOn ? DS.entityTask.opacity(0.13) : DS.glassSectionFill.opacity(0.65),
                    in: .rect(cornerRadius: 6, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isOn ? DS.entityTask.opacity(0.35) : DS.glassBorder, lineWidth: isOn ? 1 : 0.5)
                )
        }
        .buttonStyle(.plain)
        .help("Repeat on \(day.shortName)")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private func toggleDay(_ day: DayOfWeek) {
        guard let rule = draft?.recurrenceRule else { return }
        var days = Set(rule.daysOfWeek ?? [])
        if days.contains(day) {
            days.remove(day)
        } else {
            days.insert(day)
        }
        guard !days.isEmpty else { return } // a weekly rule needs at least one day
        setRule(RecurrenceRule(
            frequency: rule.frequency,
            interval: rule.interval,
            daysOfWeek: days.sorted { $0.rawValue < $1.rawValue },
            dayOfMonth: rule.dayOfMonth,
            monthOfYear: rule.monthOfYear,
            endCondition: rule.endCondition
        ))
    }

    private func setRule(_ rule: RecurrenceRule?) {
        markManual(.recurrence)
        pane.mutateDraft { $0.recurrenceRule = rule }
    }

    /// Weekday of the anchor (due date if set, else today) — the default day
    /// a weekly rule starts on, same seed the detail panel uses.
    private var anchorWeekday: DayOfWeek {
        let weekday = calendar.component(.weekday, from: dueDate ?? today)
        return DayOfWeek(rawValue: weekday) ?? .monday
    }

    private var anchorDayOfMonth: Int {
        calendar.component(.day, from: dueDate ?? today)
    }

    // MARK: Details

    private static let durationPresets = [15, 25, 45, 60, 90, 120]
    private static let timeGoalPresets = [15, 25, 30, 45, 60, 90, 120]

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            CommandKComposerSectionLabel(label: "Details")
            CommandKComposerRowGroup {
                priorityRow
                durationRow
                timeGoalRow
                intentRow
            }
        }
    }

    private var priorityRow: some View {
        CommandKComposerCustomRow {
            HStack(spacing: DS.space6) {
                ForEach([TaskPriority.low, .medium, .high], id: \.self) { priority in
                    priorityButton(priority)
                }
            }
        }
    }

    private func priorityButton(_ priority: TaskPriority) -> some View {
        let isActive = pane.binding(.priority).wrappedValue == priority.rawValue
        return Button {
            markManual(.priority)
            pane.binding(.priority, manualEdit: true).wrappedValue = isActive ? "" : priority.rawValue
        } label: {
            Text(priority.displayName)
                .font(DS.caption.weight(isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? priority.color : DS.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.space6)
                .background(
                    isActive ? priority.color.opacity(0.12) : DS.glassSectionFill.opacity(0.65),
                    in: .rect(cornerRadius: DS.radiusSmall, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous)
                        .strokeBorder(isActive ? priority.color.opacity(0.3) : DS.glassBorder, lineWidth: isActive ? 1 : 0.5)
                )
        }
        .buttonStyle(.plain)
        .help("\(priority.displayName) priority")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private var durationRow: some View {
        CommandKComposerRow(icon: "hourglass", label: "Duration", help: "Scheduling estimate") {
            Menu {
                Button("None") {
                    markManual(.duration)
                    pane.mutateDraft { $0.durationMinutes = nil }
                }
                Divider()
                ForEach(Self.durationPresets, id: \.self) { minutes in
                    Button(Self.minutesLabel(minutes)) {
                        markManual(.duration)
                        pane.mutateDraft { $0.durationMinutes = minutes }
                    }
                }
            } label: {
                CommandKComposerRowValueLabel(
                    text: draft?.durationMinutes.map(Self.minutesLabel) ?? "None",
                    isSet: draft?.durationMinutes != nil,
                    tint: DS.entityTask
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var timeGoalRow: some View {
        CommandKComposerRow(icon: "timer", label: "Time goal", help: "Track this much time to complete the task") {
            Menu {
                Button("None") { pane.mutateDraft { $0.timeGoalMinutes = nil } }
                Divider()
                ForEach(Self.timeGoalPresets, id: \.self) { minutes in
                    Button(Self.minutesLabel(minutes)) {
                        pane.mutateDraft { $0.timeGoalMinutes = minutes }
                    }
                }
            } label: {
                CommandKComposerRowValueLabel(
                    text: draft?.timeGoalMinutes.map(Self.minutesLabel) ?? "None",
                    isSet: draft?.timeGoalMinutes != nil,
                    tint: DS.entityTask
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var intentRow: some View {
        CommandKComposerRow(icon: "scope", label: "Intent", help: "What opens when you start this task") {
            Menu {
                ForEach(TaskIntent.allCases.filter { $0 != .custom }, id: \.self) { intent in
                    Button {
                        markManual(.intent)
                        pane.binding(.intent, manualEdit: true).wrappedValue = intent == .general ? "" : intent.rawValue
                    } label: {
                        Label(intent.displayName, systemImage: intent.iconName)
                    }
                }
            } label: {
                CommandKComposerRowValueLabel(
                    text: selectedIntent?.displayName ?? "General",
                    isSet: selectedIntent != nil,
                    tint: DS.entityTask
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var selectedIntent: TaskIntent? {
        let raw = pane.binding(.intent).wrappedValue
        guard !raw.isEmpty, let intent = TaskIntent(rawValue: raw), intent != .general else { return nil }
        return intent
    }

    static func minutesLabel(_ minutes: Int) -> String {
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        if minutes > 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
    }

    // MARK: Checklist

    private var checklistSection: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            CommandKComposerSectionLabel(label: "Checklist", count: draft?.checklist.count ?? 0)
            CommandKComposerRowGroup {
                ForEach(draft?.checklist ?? []) { item in
                    checklistRow(item)
                }
                checklistGhostRow
            }
        }
    }

    private func checklistRow(_ item: ChecklistItem) -> some View {
        CommandKComposerCustomRow {
            HStack(spacing: DS.space10) {
                Image(systemName: "circle")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(item.title)
                    .font(DS.callout)
                    .foregroundStyle(DS.text)
                Spacer(minLength: 0)
                CommandKComposerRemoveButton(label: "Remove \(item.title)") {
                    pane.mutateDraft { draft in
                        draft.checklist.removeAll { $0.id == item.id }
                    }
                }
            }
        }
    }

    private var checklistGhostRow: some View {
        CommandKComposerCustomRow {
            HStack(spacing: DS.space10) {
                Image(systemName: "plus.circle")
                    .font(DS.caption)
                    .foregroundStyle(DS.entityTask)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                TextField("Add a step…", text: $checklistDraft)
                    .textFieldStyle(.plain)
                    .font(DS.callout)
                    .focused(pane.focusBinding, equals: .checklist)
                    .onSubmit(addChecklistItem)
            }
        }
    }

    private func addChecklistItem() {
        let trimmed = checklistDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pane.mutateDraft { draft in
            draft.checklist.append(ChecklistItem(title: trimmed, sortOrder: draft.checklist.count))
        }
        checklistDraft = ""
    }

    // MARK: Due-date plumbing (ISO in the .date field — the query-sync contract)

    private var dueDate: Date? {
        let raw = pane.binding(.date).wrappedValue
        guard !raw.isEmpty else { return nil }
        return ISO8601.date(from: raw)
    }

    private func isDue(_ day: Date) -> Bool {
        guard let dueDate else { return false }
        return calendar.isDate(dueDate, inSameDayAs: day)
    }

    private func setDue(_ day: Date) {
        markManual(.due)
        pane.binding(.date, manualEdit: true).wrappedValue = ISO8601.string(from: day)
    }

    private func toggleDue(_ day: Date) {
        markManual(.due)
        if isDue(day) {
            pane.binding(.date, manualEdit: true).wrappedValue = ""
        } else {
            pane.binding(.date, manualEdit: true).wrappedValue = ISO8601.string(from: day)
        }
    }
}

// MARK: - Inbox capture (one field, lane-alias aware)

struct CommandKInboxComposerFields: View {
    let pane: CommandKComposerPane

    @State private var lanes: [CaptureDestination] = []

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            CommandKComposerHeroEditor(
                placeholder: "Capture anything — your Inbox sorts it",
                text: pane.binding(.body, manualEdit: true),
                accent: DS.entityResearch,
                focus: pane.focusBinding,
                field: .lead,
                minHeight: 120,
                lineLimit: 4...14
            )
            if lanes.isEmpty {
                Label("Lands in your Inbox for triage", systemImage: "tray.and.arrow.down")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            } else {
                laneHints
            }
        }
        .task {
            lanes = (try? await CaptureDestinationRepository.shared.fetchActive()) ?? []
        }
    }

    /// The user's capture lanes as teaching chips — a "name:" prefix routes
    /// straight into that lane; clicking one types the prefix for you.
    private var laneHints: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Label("Lands in your Inbox — or route it with a lane prefix", systemImage: "tray.and.arrow.down")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.space6) {
                    ForEach(lanes.prefix(8)) { lane in
                        laneChip(lane)
                    }
                }
            }
        }
    }

    private func laneChip(_ lane: CaptureDestination) -> some View {
        Button {
            let binding = pane.binding(.body, manualEdit: true)
            let current = binding.wrappedValue
            let prefix = "\(lane.name.lowercased()): "
            guard !current.lowercased().hasPrefix(prefix) else { return }
            binding.wrappedValue = prefix + current
        } label: {
            HStack(spacing: DS.space4) {
                Image(systemName: lane.icon)
                    .font(DS.caption2)
                    .accessibilityHidden(true)
                Text("\(lane.name.lowercased()):")
                    .font(DS.caption)
            }
            .foregroundStyle(DS.textSecondary)
            .padding(.horizontal, DS.space8)
            .padding(.vertical, DS.space4)
            .background(DS.glassSectionFill.opacity(0.65), in: .capsule)
            .overlay(Capsule().strokeBorder(DS.glassBorder, lineWidth: 0.5))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help("Route this capture to \(lane.name)")
        .accessibilityLabel("Route to \(lane.name)")
    }
}

// MARK: - Swipe capture (URL · hook)

struct CommandKSwipeComposerFields: View {
    let pane: CommandKComposerPane
    let clients: [CommandKComposerClient]

    private var draft: CommandKComposerDraft? { pane.viewModel.composerDraft }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            CommandKComposerHeroTitleField(
                placeholder: "Paste a reel, post, or page URL",
                text: pane.binding(.url, manualEdit: true),
                accent: DS.entitySwipe,
                focus: pane.focusBinding,
                onSubmit: pane.commit
            )
            if let badge = sourceBadge {
                Label(badge, systemImage: "checkmark.seal")
                    .font(DS.caption)
                    .foregroundStyle(DS.entitySwipe)
            }
            CommandKComposerHeroEditor(
                placeholder: "Why it works (hook note, optional)",
                text: pane.binding(.hook, manualEdit: true),
                accent: DS.entitySwipe,
                focus: pane.focusBinding,
                field: .hook,
                minHeight: 22,
                lineLimit: 1...4
            )
            CommandKComposerHeroEditor(
                placeholder: "Notes — why you captured this",
                text: pane.binding(.notes, manualEdit: true),
                accent: DS.entitySwipe,
                focus: pane.focusBinding,
                field: .notes,
                minHeight: 22,
                lineLimit: 1...4
            )
            HStack(spacing: DS.space8) {
                CommandKComposerMenuChip(
                    icon: "person.crop.square",
                    label: clientLabel,
                    isSet: !pane.binding(.client).wrappedValue.isEmpty,
                    tint: DS.entitySwipe,
                    help: "Tag this swipe for a client"
                ) {
                    Button("No client") { setClient(nil) }
                    ForEach(clients) { client in
                        Button(client.name) { setClient(client) }
                    }
                }
                Spacer(minLength: 0)
            }
            sparkSection
        }
    }

    private var sourceBadge: String? {
        let url = pane.binding(.url).wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty,
              let preview = CommandKCaptureRouter().preview(for: url),
              preview.kind == .swipe else { return nil }
        return "Recognized \(preview.source.rawValue.capitalized) source"
    }

    private var clientLabel: String {
        let name = pane.binding(.client).wrappedValue
        return name.isEmpty ? "Client" : name
    }

    private func setClient(_ client: CommandKComposerClient?) {
        pane.mutateDraft { draft in
            draft.form.setValue(client?.name ?? "", for: .client)
            draft.clientUUID = client?.uuid
        }
    }

    // MARK: Spark an idea (capture and create the linked idea in one Save)

    private var sparkSection: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            CommandKComposerSectionLabel(label: "Spark an idea")
            CommandKComposerRowGroup {
                if draft?.sparkIdea == true {
                    sparkTitleRow
                    sparkBodyRow
                } else {
                    sparkGhostRow
                }
            }
        }
        .animation(ProMotionSprings.snappy, value: draft?.sparkIdea == true)
    }

    private var sparkGhostRow: some View {
        CommandKComposerCustomRow {
            Button {
                pane.mutateDraft { $0.sparkIdea = true }
            } label: {
                HStack(spacing: DS.space10) {
                    Image(systemName: "lightbulb")
                        .font(DS.caption)
                        .foregroundStyle(DS.entityIdea)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    Text("Spark an idea from this swipe")
                        .font(DS.callout)
                        .foregroundStyle(DS.textSecondary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Save the swipe and a linked idea together")
        }
    }

    private var sparkTitleRow: some View {
        CommandKComposerCustomRow {
            HStack(spacing: DS.space10) {
                Image(systemName: "lightbulb")
                    .font(DS.caption)
                    .foregroundStyle(DS.entityIdea)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                TextField(
                    "Idea title (defaults to the hook)",
                    text: Binding(
                        get: { draft?.sparkTitle ?? "" },
                        set: { newValue in pane.mutateDraft { $0.sparkTitle = newValue } }
                    )
                )
                .textFieldStyle(.plain)
                .font(DS.callout.weight(.medium))
                .focused(pane.focusBinding, equals: .sparkTitle)
                CommandKComposerRemoveButton(label: "Remove sparked idea") {
                    pane.mutateDraft { draft in
                        draft.sparkIdea = false
                        draft.sparkTitle = ""
                        draft.sparkBody = ""
                    }
                }
            }
        }
    }

    private var sparkBodyRow: some View {
        CommandKComposerCustomRow {
            HStack(alignment: .top, spacing: DS.space10) {
                Spacer().frame(width: 18)
                TextField(
                    "What's the idea?",
                    text: Binding(
                        get: { draft?.sparkBody ?? "" },
                        set: { newValue in pane.mutateDraft { $0.sparkBody = newValue } }
                    ),
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1...5)
                .focused(pane.focusBinding, equals: .sparkBody)
            }
        }
    }
}

// MARK: - Note (title · opening paragraph)

struct CommandKNoteComposerFields: View {
    let pane: CommandKComposerPane

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            CommandKComposerHeroTitleField(
                placeholder: "Note title",
                text: pane.binding(.title),
                accent: DS.entityNote,
                focus: pane.focusBinding,
                onSubmit: pane.commit
            )
            CommandKComposerHeroEditor(
                placeholder: "Start writing…",
                text: pane.binding(.body, manualEdit: true),
                accent: DS.entityNote,
                focus: pane.focusBinding,
                field: .body,
                minHeight: 88,
                lineLimit: 3...14
            )
            Label("Creates the note and opens the editor", systemImage: "square.and.pencil")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        }
    }
}

// MARK: - Content (title · core idea · format)

struct CommandKContentComposerFields: View {
    let pane: CommandKComposerPane

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            CommandKComposerHeroTitleField(
                placeholder: "Content title",
                text: pane.binding(.title),
                accent: DS.entityContent,
                focus: pane.focusBinding,
                onSubmit: pane.commit
            )
            CommandKComposerHeroEditor(
                placeholder: "Core idea — what is this really about?",
                text: pane.binding(.body, manualEdit: true),
                accent: DS.entityContent,
                focus: pane.focusBinding,
                field: .body,
                minHeight: 44,
                lineLimit: 2...8
            )
            HStack(spacing: DS.space8) {
                CommandKComposerMenuChip(
                    icon: "rectangle.3.group",
                    label: formatLabel,
                    isSet: !pane.binding(.format).wrappedValue.isEmpty,
                    tint: DS.entityContent,
                    help: "Content format"
                ) {
                    Button("Any format") { pane.binding(.format, manualEdit: true).wrappedValue = "" }
                    ForEach(ContentFormat.allCases, id: \.self) { candidate in
                        Button(candidate.displayName) {
                            pane.binding(.format, manualEdit: true).wrappedValue = candidate.rawValue
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            Label("Creates the piece and opens the editor", systemImage: "square.and.pencil")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        }
    }

    private var formatLabel: String {
        ContentFormat(rawValue: pane.binding(.format).wrappedValue)?.displayName ?? "Format"
    }
}

// MARK: - Thinkspace (title only, deliberately)

struct CommandKThinkspaceComposerFields: View {
    let pane: CommandKComposerPane

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            CommandKComposerHeroTitleField(
                placeholder: "Thinkspace name",
                text: pane.binding(.title),
                accent: DS.entityResearch,
                focus: pane.focusBinding,
                onSubmit: pane.commit
            )
            Label("Names a fresh canvas to think on", systemImage: "square.grid.2x2")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        }
    }
}

// MARK: - Menu chip (tint wash + hairline; set-state never a solid fill)

struct CommandKComposerMenuChip<Items: View>: View {
    let icon: String
    let label: String
    let isSet: Bool
    let tint: Color
    let help: String
    @ViewBuilder let items: () -> Items

    @State private var isHovered = false

    var body: some View {
        Menu(content: items) {
            HStack(spacing: DS.space6) {
                Image(systemName: icon)
                    .font(DS.caption2)
                    .accessibilityHidden(true)
                Text(label).font(DS.caption.weight(isSet ? .semibold : .regular)).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(DS.caption2.weight(.semibold))
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(isSet ? tint : DS.textSecondary)
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space6)
            .background(
                isSet ? tint.opacity(0.13) : DS.glassSectionFill.opacity(isHovered ? 1 : 0.65),
                in: .capsule
            )
            .overlay(
                Capsule().strokeBorder(
                    isSet ? tint.opacity(0.35) : DS.glassBorder,
                    lineWidth: isSet ? 1 : 0.5
                )
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Inspired by (swipe link — the iOS inspiredBySection, Mac manners)

struct CommandKComposerInspiredBySection: View {
    let pane: CommandKComposerPane
    /// The idea's tint by default; the swipe composer's spark reuses this
    /// section shape with its own accent.
    var tint: Color = DS.entityIdea

    @State private var showPicker = false
    @State private var linkedSwipe: SwipeGalleryItem?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            CommandKComposerSectionLabel(label: "Inspired by")
            CommandKComposerRowGroup {
                if let swipe = linkedSwipe {
                    linkedRow(swipe)
                } else {
                    ghostRow
                }
            }
        }
        .animation(ProMotionSprings.snappy, value: linkedSwipe?.atomUUID)
        .onAppear(perform: syncFromDraft)
    }

    private func linkedRow(_ swipe: SwipeGalleryItem) -> some View {
        CommandKComposerCustomRow {
            HStack(spacing: DS.space10) {
                CommandKComposerSwipeThumbnail(item: swipe)
                    .frame(width: 34, height: 44)
                    .clipShape(.rect(cornerRadius: DS.radiusXSmall, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(swipe.hookText ?? swipe.title)
                        .font(DS.callout.weight(.medium))
                        .foregroundStyle(DS.text)
                        .lineLimit(2)
                    Text("Swipe")
                        .font(DS.caption2)
                        .foregroundStyle(DS.entitySwipe)
                }
                Spacer(minLength: 0)
                CommandKComposerRemoveButton(label: "Unlink swipe") {
                    linkedSwipe = nil
                    pane.mutateDraft { $0.linkedSwipeUUID = nil }
                }
            }
        }
    }

    private var ghostRow: some View {
        CommandKComposerCustomRow {
            Button {
                showPicker = true
            } label: {
                HStack(spacing: DS.space10) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(DS.caption)
                        .foregroundStyle(DS.entitySwipe)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    Text("Link a swipe")
                        .font(DS.callout)
                        .foregroundStyle(DS.textSecondary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Link the swipe that sparked this idea")
            .popover(isPresented: $showPicker, arrowEdge: .trailing) {
                CommandKComposerSwipePicker(viewModel: pane.viewModel) { item in
                    linkedSwipe = item
                    pane.mutateDraft { $0.linkedSwipeUUID = item.atomUUID }
                    showPicker = false
                }
            }
        }
    }

    private func syncFromDraft() {
        guard linkedSwipe == nil,
              let uuid = pane.viewModel.composerDraft?.linkedSwipeUUID else { return }
        linkedSwipe = pane.viewModel.swipeGalleryItems.first { $0.atomUUID == uuid }
    }
}

/// Compact swipe browser for the composer — search + rows, static thumbnails
/// only (no video anywhere near this hot path).
struct CommandKComposerSwipePicker: View {
    let viewModel: CommandKViewModel
    let onPick: (SwipeGalleryItem) -> Void

    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Search swipes…", text: $query)
                .textFieldStyle(.plain)
                .font(DS.callout)
                .padding(DS.space10)
            Rectangle().fill(DS.glassBorder).frame(height: 0.5)
            if filtered.isEmpty {
                Text(viewModel.swipeGalleryItems.isEmpty ? "Loading swipes…" : "No swipes match")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered.prefix(60)) { item in
                            pickerRow(item)
                        }
                    }
                }
            }
        }
        .frame(width: 340, height: 380)
        .task { await viewModel.loadSwipeGallery() }
    }

    private var filtered: [SwipeGalleryItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return viewModel.swipeGalleryItems }
        return viewModel.swipeGalleryItems.filter { item in
            item.title.lowercased().contains(trimmed)
                || item.hookText?.lowercased().contains(trimmed) == true
                || item.creatorName?.lowercased().contains(trimmed) == true
        }
    }

    private func pickerRow(_ item: SwipeGalleryItem) -> some View {
        Button {
            onPick(item)
        } label: {
            HStack(spacing: DS.space10) {
                CommandKComposerSwipeThumbnail(item: item)
                    .frame(width: 34, height: 44)
                    .clipShape(.rect(cornerRadius: DS.radiusXSmall, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.hookText ?? item.title)
                        .font(DS.callout)
                        .foregroundStyle(DS.text)
                        .lineLimit(2)
                    if let creator = item.creatorName ?? item.author {
                        Text(creator)
                            .font(DS.caption2)
                            .foregroundStyle(DS.textMuted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// Static thumbnail with a quiet placeholder — CachedAsyncImage only.
struct CommandKComposerSwipeThumbnail: View {
    let item: SwipeGalleryItem

    var body: some View {
        if let urlString = item.thumbnailUrl, let url = URL(string: urlString) {
            CachedAsyncImage(url: url, stableKey: item.atomUUID) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .empty, .failure:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(DS.entitySwipe.opacity(0.10))
            .overlay(
                Image(systemName: "bolt.fill")
                    .font(DS.caption2)
                    .foregroundStyle(DS.entitySwipe.opacity(0.5))
                    .accessibilityHidden(true)
            )
    }
}

// MARK: - Hooks

struct CommandKComposerHooksSection: View {
    let pane: CommandKComposerPane
    @Binding var hookDraft: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            CommandKComposerSectionLabel(
                label: "Hooks",
                count: pane.viewModel.composerDraft?.hooks.count ?? 0
            )
            CommandKComposerRowGroup {
                ForEach(Array((pane.viewModel.composerDraft?.hooks ?? []).enumerated()), id: \.offset) { index, hook in
                    CommandKComposerCustomRow {
                        HStack(spacing: DS.space10) {
                            Image(systemName: "quote.opening")
                                .font(DS.caption2)
                                .foregroundStyle(DS.entityIdea)
                                .frame(width: 18)
                                .accessibilityHidden(true)
                            Text(hook)
                                .font(DS.callout)
                                .foregroundStyle(DS.text)
                            Spacer(minLength: 0)
                            CommandKComposerRemoveButton(label: "Remove hook") {
                                pane.mutateDraft { $0.hooks.remove(at: index) }
                            }
                        }
                    }
                }
                CommandKComposerCustomRow {
                    HStack(spacing: DS.space10) {
                        Image(systemName: "plus.circle")
                            .font(DS.caption)
                            .foregroundStyle(DS.entityIdea)
                            .frame(width: 18)
                            .accessibilityHidden(true)
                        TextField("Add a hook…", text: $hookDraft)
                            .textFieldStyle(.plain)
                            .font(DS.callout)
                            .focused(pane.focusBinding, equals: .hook)
                            .onSubmit(addHook)
                    }
                }
            }
        }
    }

    private func addHook() {
        let trimmed = hookDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pane.mutateDraft { $0.hooks.append(trimmed) }
        hookDraft = ""
    }
}

// MARK: - Outline

struct CommandKComposerOutlineSection: View {
    let pane: CommandKComposerPane

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            CommandKComposerSectionLabel(
                label: "Outline",
                count: pane.viewModel.composerDraft?.outline.count ?? 0
            )
            CommandKComposerRowGroup {
                ForEach(Array((pane.viewModel.composerDraft?.outline ?? []).indices), id: \.self) { index in
                    outlineRow(index)
                }
                CommandKComposerCustomRow {
                    Button {
                        pane.mutateDraft { $0.outline.append("") }
                    } label: {
                        HStack(spacing: DS.space10) {
                            Image(systemName: "plus.circle")
                                .font(DS.caption)
                                .foregroundStyle(DS.entityIdea)
                                .frame(width: 18)
                                .accessibilityHidden(true)
                            Text("Add a slide")
                                .font(DS.callout)
                                .foregroundStyle(DS.textSecondary)
                            Spacer(minLength: 0)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help("Add slide")
                }
            }
        }
    }

    private func outlineRow(_ index: Int) -> some View {
        CommandKComposerCustomRow {
            HStack(alignment: .firstTextBaseline, spacing: DS.space10) {
                Text(CommandKComposerOutlineSection.romanNumeral(index + 1))
                    .font(DS.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 26, alignment: .trailing)
                TextField(
                    "what should this slide do?",
                    text: Binding(
                        get: { pane.viewModel.composerDraft?.outline[safe: index] ?? "" },
                        set: { newValue in
                            pane.mutateDraft { draft in
                                guard draft.outline.indices.contains(index) else { return }
                                draft.outline[index] = newValue
                            }
                        }
                    )
                )
                .textFieldStyle(.plain)
                .font(DS.callout)
                .focused(pane.focusBinding, equals: .outline(index))
                .onSubmit {
                    pane.mutateDraft { draft in
                        if index == draft.outline.count - 1 { draft.outline.append("") }
                    }
                }
                CommandKComposerRemoveButton(label: "Remove slide \(index + 1)") {
                    pane.mutateDraft { draft in
                        guard draft.outline.indices.contains(index) else { return }
                        draft.outline.remove(at: index)
                    }
                }
            }
        }
    }

    static func romanNumeral(_ number: Int) -> String {
        let values = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
                      (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var remaining = max(1, number)
        var result = ""
        for (value, symbol) in values {
            while remaining >= value {
                result += symbol
                remaining -= value
            }
        }
        return result
    }
}
