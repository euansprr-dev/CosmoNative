// CosmoOS/UI/Pipeline/PipelineCalendarView.swift
// The Pipeline's Calendar view: the month grid (re-homed from Upcoming's
// retired Content lens) beside its Shelf rail. The month is the planning
// surface — the shelf holds what still needs a decision, the calendar holds
// what's decided, ideas are seeds and never consumed. The host owns the
// anchor month; the grid and the shelf reload on the shared notification.

import SwiftUI

struct PipelineCalendarView: View {
    let model: PipelinePageModel
    @Binding var anchor: Date

    private let calendar = Calendar.current
    @State private var availableWidth: CGFloat = 1100
    private var wide: Bool { availableWidth >= 1000 }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            monthRow
            (wide ? AnyLayout(HStackLayout(alignment: .top, spacing: DS.space16)) : AnyLayout(VStackLayout(alignment: .leading, spacing: DS.space16))) {
                ContentCalendarView(anchor: anchor, scope: model.scope, filters: model.filters)
                    .frame(maxWidth: .infinity, alignment: .top)
                shelf
            }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { availableWidth = $0 }
        .background(keyboardLayer)
    }

    private var monthRow: some View {
        HStack(spacing: DS.space12) {
            Text(anchor.formatted(.dateTime.month(.wide).year()))
                .font(DS.title3.weight(.semibold))
                .foregroundStyle(DS.text)
                .contentTransition(.numericText())
                .animation(ProMotionSprings.gentle, value: anchor)
            HStack(spacing: 0) {
                MastheadNavChevron(direction: .left, help: "Previous month (⌥⌘←)") { shift(-1) }
                    .accessibilityLabel("Previous month")
                MastheadTodayButton(help: "Jump back to this month") { resetToToday() }
                MastheadNavChevron(direction: .right, help: "Next month (⌥⌘→)") { shift(1) }
                    .accessibilityLabel("Next month")
            }
            Spacer(minLength: 0)
            Text("Drag onto a day to plan publication")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .lineLimit(1)
        }
    }

    private var shelf: some View {
        CommandCenterRail {
            ContentShelfRail(scope: model.scope, filters: model.filters, showsClientFilter: false)
        }
        .frame(width: wide ? DashboardLayoutMetrics.railWidth : nil)
        .frame(minHeight: wide ? 560 : 260)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(DS.palette.sepiaBorder, lineWidth: 0.5)
        )
    }

    private var keyboardLayer: some View {
        Group {
            Button("") { shift(-1) }.keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Button("") { shift(1) }.keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Button("") { resetToToday() }.keyboardShortcut("t", modifiers: [.command, .shift])
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func shift(_ months: Int) {
        withAnimation(ProMotionSprings.snappy) {
            anchor = calendar.startOfDay(for: calendar.date(byAdding: .month, value: months, to: anchor) ?? anchor)
        }
    }

    private func resetToToday() {
        withAnimation(ProMotionSprings.snappy) {
            anchor = calendar.startOfDay(for: Date())
        }
    }
}
