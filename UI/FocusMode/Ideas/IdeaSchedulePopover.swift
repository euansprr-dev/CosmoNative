// UI/FocusMode/Ideas/IdeaSchedulePopover.swift
// July 2026 — schedule an idea into a development task.
// The toolbar's calendar affordance opens this popover: quick landing spots
// (today, tomorrow, the weekend, next week) above a month calendar — one
// click commits and closes (the iOS RescheduleSheet grammar, bench-sized).
// Existing scheduled sessions list below with reschedule/remove; picking a
// day while one is retargeted moves that task instead of creating another.

import SwiftUI

struct IdeaSchedulePopover: View {
    var viewModel: IdeaFocusModeViewModel

    @Environment(\.dismiss) private var dismiss
    /// Row put into "move" mode — the next day pick reschedules it.
    @State private var retargetTaskUUID: String?
    @State private var calendarSelection = Calendar.current.startOfDay(for: .now)

    private var calendar: Calendar { .current }
    private var today: Date { calendar.startOfDay(for: .now) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            header
            quickPickList
            calendarCard
            if !viewModel.scheduledTasks.isEmpty {
                Divider()
                scheduledSection
            }
        }
        .padding(DS.space16)
        .frame(width: 296)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.space2) {
            Text(retargetTaskUUID == nil ? "Schedule" : "Move session")
                .font(DS.headline)
                .foregroundStyle(DS.text)
            Text(retargetTaskUUID == nil
                 ? "Plan a session to develop this idea"
                 : "Pick the new day")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Quick picks

    private struct QuickPick: Identifiable {
        let id: String
        let icon: String
        let tint: Color
        let title: String
        let detail: String
        let date: Date
    }

    private var quickPicks: [QuickPick] {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        var picks: [QuickPick] = [
            QuickPick(id: "today", icon: "sun.max", tint: DS.accent,
                      title: "Today", detail: weekday(today), date: today),
            QuickPick(id: "tomorrow", icon: "sunrise", tint: DS.orange,
                      title: "Tomorrow", detail: weekday(tomorrow), date: tomorrow)
        ]
        // Weekend and next-week rows earn their place only when they aren't
        // just "tomorrow" wearing a different name (the iOS sheet's rule).
        if let saturday = calendar.nextDate(after: today, matching: DateComponents(weekday: 7), matchingPolicy: .nextTime),
           saturday != tomorrow {
            picks.append(QuickPick(id: "weekend", icon: "sofa", tint: DS.gilt,
                                   title: "This Weekend", detail: dayDetail(saturday), date: saturday))
        }
        if let monday = calendar.nextDate(after: today, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime),
           monday != tomorrow {
            picks.append(QuickPick(id: "next-week", icon: "calendar.badge.clock", tint: DS.textSecondary,
                                   title: "Next Week", detail: dayDetail(monday), date: monday))
        }
        return picks
    }

    private var quickPickList: some View {
        VStack(spacing: 2) {
            ForEach(quickPicks) { pick in
                quickPickRow(pick)
            }
        }
    }

    private func quickPickRow(_ pick: QuickPick) -> some View {
        Button {
            commit(day: pick.date)
        } label: {
            HStack(spacing: DS.space10) {
                Image(systemName: pick.icon)
                    .font(DS.footnote.weight(.medium))
                    .foregroundStyle(pick.tint)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(pick.title)
                    .font(DS.footnote.weight(.medium))
                    .foregroundStyle(DS.text)
                Spacer()
                Text(pick.detail)
                    .font(DS.caption.monospacedDigit())
                    .foregroundStyle(DS.textMuted)
            }
            .padding(.horizontal, DS.space8)
            .padding(.vertical, DS.space6)
            .contentShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .background(DS.surface.opacity(0.0001), in: .rect(cornerRadius: 6))
        .accessibilityLabel("\(pick.title), \(pick.detail)")
    }

    // MARK: - Calendar

    private var calendarCard: some View {
        DatePicker(
            "Pick a day",
            selection: $calendarSelection,
            in: today...,
            displayedComponents: [.date]
        )
        .datePickerStyle(.graphical)
        .tint(DS.accent)
        .labelsHidden()
        // Tapping a day commits it — the initial value never fires onChange.
        .onChange(of: calendarSelection) { _, picked in
            commit(day: calendar.startOfDay(for: picked))
        }
        .accessibilityLabel("Pick a day on the calendar")
    }

    // MARK: - Scheduled sessions

    private var scheduledSection: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Text("SCHEDULED")
                .font(DS.smallCaps)
                .tracking(1.2)
                .foregroundStyle(DS.textMuted)
            ForEach(viewModel.scheduledTasks, id: \.uuid) { task in
                scheduledRow(task)
            }
        }
    }

    private func scheduledRow(_ task: Atom) -> some View {
        let completed = task.metadataValue(as: TaskMetadata.self)?.isCompleted == true
        let isRetargeting = retargetTaskUUID == task.uuid
        return HStack(spacing: DS.space8) {
            Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                .font(DS.caption)
                .foregroundStyle(completed ? DS.green : DS.textMuted)
                .accessibilityHidden(true)
            Text(scheduledDayLabel(task))
                .font(DS.footnote)
                .foregroundStyle(completed ? DS.textMuted : DS.text)
                .strikethrough(completed)
            Spacer()
            scheduledRowMenu(task, completed: completed)
        }
        .padding(.horizontal, DS.space8)
        .padding(.vertical, DS.space4)
        .background(isRetargeting ? DS.accentSoft : Color.clear, in: .rect(cornerRadius: 6))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Session \(scheduledDayLabel(task))\(completed ? ", completed" : "")")
    }

    private func scheduledRowMenu(_ task: Atom, completed: Bool) -> some View {
        Menu {
            if !completed {
                Button("Reschedule…") { retargetTaskUUID = task.uuid }
            }
            Button("Remove", role: .destructive) {
                Sound.deleteTuck()
                Task { await viewModel.removeScheduledTask(uuid: task.uuid) }
                if retargetTaskUUID == task.uuid { retargetTaskUUID = nil }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .frame(width: 20, height: 20)
                .contentShape(.rect)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Session options")
    }

    // MARK: - Commit

    private func commit(day: Date) {
        if let uuid = retargetTaskUUID {
            retargetTaskUUID = nil
            Task { await viewModel.rescheduleTask(uuid: uuid, to: day) }
        } else {
            Task { await viewModel.scheduleTask(on: day) }
        }
        dismiss()
    }

    // MARK: - Labels

    private func scheduledDayLabel(_ task: Atom) -> String {
        guard let day = IdeaTaskLinkService.plannedDay(task) else { return "Unscheduled" }
        if calendar.isDate(day, inSameDayAs: today) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
           calendar.isDate(day, inSameDayAs: tomorrow) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private func weekday(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated))
    }

    private func dayDetail(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day())
    }
}
