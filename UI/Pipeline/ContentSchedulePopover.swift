// CosmoOS/UI/Pipeline/ContentSchedulePopover.swift
// Pick a publish day for a piece — the calendar's own date popover, lifted so
// the board, the ledger and the quick look can schedule without a month grid.

import SwiftUI

struct ContentSchedulePopover: View {
    let title: String
    let currentDay: Date?
    let onPick: (Date) -> Void
    let onUnschedule: (() -> Void)?

    @State private var day: Date

    init(title: String, currentDay: Date?, onPick: @escaping (Date) -> Void, onUnschedule: (() -> Void)? = nil) {
        self.title = title
        self.currentDay = currentDay
        self.onPick = onPick
        self.onUnschedule = onUnschedule
        _day = State(initialValue: currentDay ?? Calendar.current.startOfDay(for: Date()))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            Text(title)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.textMuted)
                .lineLimit(1)
            quickPicks
            DatePicker("Date", selection: $day, displayedComponents: [.date])
                .datePickerStyle(.graphical)
                .labelsHidden()
            footer
        }
        .padding(DS.space12)
        .frame(width: 280)
    }

    private var quickPicks: some View {
        HStack(spacing: DS.space6) {
            ForEach(Self.quickDays, id: \.label) { pick in
                Button(pick.label) { day = pick.day }
                    .buttonStyle(.plain)
                    .font(DS.caption.weight(.medium))
                    .foregroundStyle(Calendar.current.isDate(day, inSameDayAs: pick.day) ? DS.accent : DS.textSecondary)
                    .padding(.horizontal, DS.space8)
                    .frame(height: 36)
                    .background(
                        Calendar.current.isDate(day, inSameDayAs: pick.day) ? DS.accentSoft : DS.glassSectionFill,
                        in: .capsule
                    )
            }
        }
    }

    private var footer: some View {
        HStack {
            if let onUnschedule, currentDay != nil {
                Button("Remove date", action: onUnschedule)
                    .buttonStyle(.plain)
                    .font(DS.subheadline)
                    .foregroundStyle(DS.textSecondary)
            }
            Spacer()
            Button {
                onPick(Calendar.current.startOfDay(for: day))
            } label: {
                Text("Save date")
                    .font(DS.subheadline.weight(.semibold))
                    .foregroundStyle(DS.textOnAccent)
                    .padding(.horizontal, DS.space12)
                    .frame(height: 36)
                    .background(DS.accent, in: .rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
        }
    }

    private static var quickDays: [(label: String, day: Date)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var picks: [(String, Date)] = [("Today", today)]
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) { picks.append(("Tomorrow", tomorrow)) }
        if let nextWeek = calendar.date(byAdding: .day, value: 7, to: today) { picks.append(("Next week", nextWeek)) }
        return picks
    }
}
