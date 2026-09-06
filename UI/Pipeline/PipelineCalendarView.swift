// CosmoOS/UI/Pipeline/PipelineCalendarView.swift
// The Pipeline's Calendar view: the month grid beside its Shelf rail. The
// month is the planning surface — the shelf holds what still needs a
// decision, the calendar holds what's decided, ideas are seeds and never
// consumed. The host owns the anchor month; the grid and the shelf reload on
// the shared notification.
//
// Viewport law (September 2026): the calendar is a VIEWPORT, not a page.
// The month fills the height it is given and the shelf scrolls inside its
// own bounds — hundreds of drafts must never stretch the page.

import SwiftUI

struct PipelineCalendarView: View {
    let model: PipelinePageModel
    @Binding var anchor: Date

    private let calendar = Calendar.current
    @State private var availableWidth: CGFloat = 1100
    private var wide: Bool { availableWidth >= 1000 }
    private static let monthRowHeight: CGFloat = 30

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: DS.space16) {
                monthRow.frame(height: Self.monthRowHeight)
                if wide {
                    HStack(alignment: .top, spacing: DS.space20) {
                        ContentCalendarView(anchor: anchor, scope: model.scope, filters: model.filters,
                            availableHeight: geometry.size.height - Self.monthRowHeight - DS.space16)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        shelf
                            .frame(width: DashboardLayoutMetrics.railWidth)
                            .frame(maxHeight: .infinity)
                    }
                } else {
                    // Narrow: the month keeps its natural height and the shelf
                    // becomes a fixed-height panel beneath it; only then does
                    // the column scroll.
                    ScrollView {
                        VStack(alignment: .leading, spacing: DS.space16) {
                            ContentCalendarView(anchor: anchor, scope: model.scope, filters: model.filters)
                            shelf.frame(height: 360)
                        }
                        .padding(.bottom, DS.space24)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
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
                MastheadTodayButton(help: "Jump back to this month (⇧⌘T)") { resetToToday() }
                MastheadNavChevron(direction: .right, help: "Next month (⌥⌘→)") { shift(1) }
                    .accessibilityLabel("Next month")
            }
            Spacer(minLength: 0)
            Text("Drag a draft onto a day to plan its publication")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .lineLimit(1)
        }
    }

    /// The shelf is an integrated side panel (the Command Center rail
    /// material): flat on the page plane, one hairline, scrolling inside.
    private var shelf: some View {
        CommandCenterRail {
            ContentShelfRail(scope: model.scope, filters: model.filters, showsClientFilter: false)
        }
        .clipShape(.rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(DS.commandChromeBorder, lineWidth: 0.5)
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
