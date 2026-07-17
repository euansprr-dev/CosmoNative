import SwiftUI

struct ReportsSectionView: View {
    var viewModel: CommandCenterDashboardViewModel

    @State private var scope: ReportPageScope = .week
    @State private var chartAnimated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CommandCenterPlanningPageScaffold(
            title: "Reports",
            icon: "chart.bar",
            subtitle: subtitle,
            accent: DS.info,
            actions: { scopeControl },
            content: { content }
        )
        .task { await loadScope() }
        .onChange(of: scope) { _, _ in
            chartAnimated = false
            Task { await loadScope() }
        }
        .onAppear(perform: triggerCharts)
    }

    private var subtitle: String {
        switch scope {
        case .today:
            return "Today · \(formatReportMinutes(viewModel.todayTrackedMinutes)) tracked · \(viewModel.todaySessions.count) sessions"
        case .week, .month:
            return "\(scope.title) · \(viewModel.reportDateLabel)"
        case .habits:
            let completion = Int((viewModel.habitReportData?.overallCompletionRate ?? 0) * 100)
            return "Habit history · \(completion)% completion"
        }
    }

    private var scopeControl: some View {
        HStack(spacing: DS.space2) {
            ForEach(ReportPageScope.allCases) { item in
                ReportScopeSegment(item: item, isSelected: scope == item) {
                    withAnimation(ProMotionSprings.snappy) {
                        scope = item
                    }
                }
            }
        }
        .padding(DS.space2)
        .background(DS.glassInputFill, in: Capsule())
        .overlay(Capsule().stroke(DS.glassBorder, lineWidth: 0.5))
    }

    private var content: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: DS.space16) {
                if scope != .today {
                    reportNavigator
                }

                switch scope {
                case .today:
                    todayReview
                case .week, .month:
                    if let report = viewModel.weeklyReportData {
                        reportOverview(report)
                    } else {
                        reportsEmptyState
                    }
                case .habits:
                    if let habitReport = viewModel.habitReportData, !habitReport.habitEntries.isEmpty {
                        HabitHistoryReportView(report: habitReport, chartAnimated: chartAnimated)
                    } else {
                        reportsEmptyState
                    }
                }
            }
            .padding(.bottom, DS.space24)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .animation(ProMotionSprings.gentle, value: scope)
    }

    private var reportNavigator: some View {
        HStack(spacing: DS.space8) {
            ReportNavigatorButton(
                icon: "chevron.left",
                title: "Previous \(scope.title)",
                isDisabled: false
            ) {
                Task { await viewModel.navigateReport(direction: -1) }
            }

            Text(viewModel.reportDateLabel)
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(DS.textSecondary)
                .frame(maxWidth: .infinity)

            ReportNavigatorButton(
                icon: "chevron.right",
                title: "Next \(scope.title)",
                isDisabled: isAtPresent
            ) {
                Task { await viewModel.navigateReport(direction: 1) }
            }
        }
        .padding(.horizontal, DS.space10)
        .background(DS.glassInputFill, in: .rect(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.glassBorder, lineWidth: 0.5)
        )
    }

    private var todayReview: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DS.space16) {
                TodaySessionTimeline(viewModel: viewModel)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: DS.space12) {
                    TodayFocusQualityPane(viewModel: viewModel)
                    TodayAttributionPane(viewModel: viewModel)
                }
                .frame(width: 320)
            }

            VStack(alignment: .leading, spacing: DS.space16) {
                TodaySessionTimeline(viewModel: viewModel)
                TodayFocusQualityPane(viewModel: viewModel)
                TodayAttributionPane(viewModel: viewModel)
            }
        }
    }

    private func reportOverview(_ report: ReportData) -> some View {
        LazyVStack(alignment: .leading, spacing: DS.space16) {
            ReportHeroTotals(report: report)
            AllocationBars(report: report, chartAnimated: chartAnimated)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: DS.space16) {
                    IntentBreakdownList(report: report)
                        .frame(maxWidth: .infinity)
                    FocusPatternPane(report: report)
                        .frame(width: 320)
                }

                VStack(alignment: .leading, spacing: DS.space16) {
                    IntentBreakdownList(report: report)
                    FocusPatternPane(report: report)
                }
            }
        }
    }

    private var reportsEmptyState: some View {
        CommandCenterEmptyPane(
            icon: "chart.bar",
            title: "Start a focus session",
            subtitle: "Track work from Today and this page becomes a useful review ritual."
        )
    }

    @MainActor
    private func loadScope() async {
        switch scope {
        case .today:
            await viewModel.loadTodayTimeData()
            await viewModel.loadTodaySessions()
            await viewModel.loadHabits()
        case .week:
            viewModel.selectedReportTab = .week
            await viewModel.loadWeeklyReport()
            await viewModel.loadHabitReport()
        case .month:
            viewModel.selectedReportTab = .month
            await viewModel.loadMonthReport()
            await viewModel.loadHabitReport()
        case .habits:
            viewModel.selectedReportTab = .habits
            await viewModel.loadHabitReport()
        }
        triggerCharts()
    }

    private func triggerCharts() {
        guard !chartAnimated else { return }
        if reduceMotion {
            chartAnimated = true
        } else {
            withAnimation(ProMotionSprings.gentle) {
                chartAnimated = true
            }
        }
    }

    private var isAtPresent: Bool {
        switch viewModel.selectedReportTab {
        case .week, .habits:
            return viewModel.reportWeekOffset >= 0
        case .month:
            return viewModel.reportMonthOffset >= 0
        }
    }
}

private enum ReportPageScope: String, CaseIterable, Identifiable {
    case today
    case week
    case month
    case habits

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .week: return "Week"
        case .month: return "Month"
        case .habits: return "Habits"
        }
    }
}

private struct ReportScopeSegment: View {
    let item: ReportPageScope
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(item.title)
                .font(DS.buttonText)
                .foregroundStyle(isSelected ? DS.text : (isHovered ? DS.textSecondary : DS.textMuted))
                .padding(.horizontal, DS.space10)
                .frame(height: 32)
                .background(segmentFill, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.01 : 1)
        .animation(ProMotionSprings.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .help("Show \(item.title.lowercased()) report")
        .accessibilityLabel("Show \(item.title) report")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var segmentFill: Color {
        if isSelected { return DS.surfaceElevated }
        if isHovered { return DS.glassInputFillFocused }
        return Color.clear
    }
}

private struct ReportNavigatorButton: View {
    let icon: String
    let title: String
    let isDisabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(isDisabled ? DS.textMuted.opacity(0.45) : (isHovered ? DS.text : DS.textSecondary))
                .frame(width: 44, height: 44)
                .background(!isDisabled && isHovered ? DS.glassInputFillFocused : Color.clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .scaleEffect(isHovered && !isDisabled ? 1.01 : 1)
        .animation(ProMotionSprings.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct TodaySessionTimeline: View {
    var viewModel: CommandCenterDashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            ReportsSectionHeader(title: "Review Timeline", count: "\(viewModel.todaySessions.count)", tint: DS.info)

            if viewModel.todaySessions.isEmpty {
                CommandCenterEmptyPane(
                    icon: "timer",
                    title: "Start from Today",
                    subtitle: "A focus session builds the timeline you can correct and review here."
                )
            } else {
                VStack(spacing: DS.space8) {
                    ForEach(viewModel.todaySessions) { session in
                        TodayTimelineRow(session: session)
                    }
                }
            }
        }
    }
}

private struct TodayTimelineRow: View {
    let session: SessionTimelineEntry
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: DS.space12) {
            VStack(spacing: DS.space4) {
                Circle()
                    .fill(session.intent.accent)
                    .frame(width: 10, height: 10)
                Rectangle()
                    .fill(DS.commandCenterSeparator)
                    .frame(width: 1, height: 36)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DS.space4) {
                HStack(spacing: DS.space8) {
                    Text(session.title)
                        .font(DS.headline)
                        .foregroundStyle(DS.text)
                        .lineLimit(1)

                    Spacer(minLength: DS.space8)

                    Text("\(Int(session.focusScore)) focus")
                        .font(DS.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(focusTint)
                }

                HStack(spacing: DS.space8) {
                    Label(session.intent.title, systemImage: session.intent.icon)
                        .font(DS.caption)
                        .foregroundStyle(session.intent.accent)
                        .lineLimit(1)

                    if let habitTitle = session.habitTitle {
                        Text(CollectionEmoji.resolve(name: habitTitle).label)
                            .font(DS.caption)
                            .foregroundStyle(DS.textMuted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Text(timeText)
                        .font(DS.caption)
                        .monospacedDigit()
                        .foregroundStyle(DS.textMuted)
                }
            }
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space10)
        .background(DS.commandChromePanelFill, in: .rect(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isHovered ? session.intent.accent.opacity(0.22) : DS.commandChromeBorder, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(isHovered ? 0.06 : 0.035), radius: isHovered ? 12 : 6, x: 0, y: isHovered ? 3 : 1)
        .scaleEffect(isHovered ? 1.01 : 1)
        .animation(ProMotionSprings.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
    }

    private var timeText: String {
        let start = CosmoDateFormatters.timeOnly.string(from: session.startTime)
        let end = CosmoDateFormatters.timeOnly.string(from: session.endTime)
        return "\(start)-\(end) · \(formatReportMinutes(durationMinutes))"
    }

    private var durationMinutes: Int {
        max(Int(session.endTime.timeIntervalSince(session.startTime) / 60), 0)
    }

    private var focusTint: Color {
        if session.focusScore >= 80 { return DS.green }
        if session.focusScore >= 65 { return DS.orange }
        return DS.textMuted
    }
}

private struct TodayFocusQualityPane: View {
    var viewModel: CommandCenterDashboardViewModel

    var body: some View {
        CommandCenterMaterialPanel(cornerRadius: 14, contentPadding: DS.space12) {
            VStack(alignment: .leading, spacing: DS.space10) {
                ReportsSectionHeader(title: "Focus Quality", count: focusText, tint: focusTint)

                Text(focusLine)
                    .font(DS.callout)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ReportInsightRow(icon: "calendar.badge.clock", title: "Next move", subtitle: nextMove, tint: focusTint)
            }
        }
    }

    private var averageFocus: Double {
        guard !viewModel.todaySessions.isEmpty else { return 0 }
        return viewModel.todaySessions.map(\.focusScore).reduce(0, +) / Double(viewModel.todaySessions.count)
    }

    private var focusText: String {
        viewModel.todaySessions.isEmpty ? "n/a" : "\(Int(averageFocus))"
    }

    private var focusTint: Color {
        if averageFocus >= 80 { return DS.green }
        if averageFocus >= 65 { return DS.orange }
        return DS.info
    }

    private var focusLine: String {
        if viewModel.todaySessions.isEmpty {
            return "No focus sessions yet. Start one from Today to create a reviewable trace."
        }
        if averageFocus >= 80 {
            return "Good depth today. Preserve whatever protected those sessions."
        }
        if averageFocus >= 65 {
            return "Usable focus with some friction. Look for interruptions or oversized blocks."
        }
        return "The day may need smaller blocks or a cleaner start cue."
    }

    private var nextMove: String {
        if viewModel.todaySessions.isEmpty { return "start focus" }
        if averageFocus >= 80 { return "keep cadence" }
        if averageFocus >= 65 { return "adjust block size" }
        return "schedule a lighter block"
    }
}

private struct TodayAttributionPane: View {
    var viewModel: CommandCenterDashboardViewModel

    var body: some View {
        CommandCenterMaterialPanel(cornerRadius: 14, contentPadding: DS.space12) {
            VStack(alignment: .leading, spacing: DS.space10) {
                ReportsSectionHeader(title: "Allocation", count: nil, tint: DS.entityIdea)

                if viewModel.todayIntentSummaries.isEmpty {
                    Text("Focus sessions and completed tasks will show which intents actually got time.")
                        .font(DS.callout)
                        .foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: DS.space8) {
                        ForEach(Array(viewModel.todayIntentSummaries.prefix(5)), id: \.id) { intent in
                            IntentAllocationRow(intent: intent, totalMinutes: max(viewModel.todayTrackedMinutes, 1))
                        }
                    }
                }
            }
        }
    }
}

private struct ReportHeroTotals: View {
    let report: ReportData

    var body: some View {
        CommandCenterMaterialPanel(cornerRadius: 14, contentPadding: DS.space16) {
            HStack(alignment: .center, spacing: DS.space18) {
                VStack(alignment: .leading, spacing: DS.space8) {
                    Text(heroTitle)
                        .font(DS.title2)
                        .foregroundStyle(DS.commandCenterTitleText)

                    Text(heroSubtitle)
                        .font(DS.callout)
                        .foregroundStyle(DS.commandCenterSecondaryText)
                }

                Spacer(minLength: DS.space16)

                ReportMetricStack(title: "Tracked", value: formatReportMinutes(report.totalMinutes), tint: DS.info)
                ReportMetricStack(title: "Sessions", value: "\(report.totalSessions)", tint: DS.entityIdea)
                ReportMetricStack(title: "Focus", value: "\(Int(report.avgFocusScore))", tint: focusTint)
            }
        }
    }

    private var heroTitle: String {
        report.timeRange == .month ? "Month in practice" : "Week in practice"
    }

    private var heroSubtitle: String {
        "\(report.tasksCompleted) tasks completed · \(formatReportMinutes(report.avgSessionMinutes)) average session"
    }

    private var focusTint: Color {
        if report.avgFocusScore >= 80 { return DS.green }
        if report.avgFocusScore >= 65 { return DS.orange }
        return DS.info
    }
}

private struct AllocationBars: View {
    let report: ReportData
    let chartAnimated: Bool

    var body: some View {
        CommandCenterMaterialPanel(cornerRadius: 14, contentPadding: DS.space16) {
            VStack(alignment: .leading, spacing: DS.space12) {
                ReportsSectionHeader(title: "Time Allocation", count: formatReportMinutes(report.totalMinutes), tint: DS.info)

                HStack(alignment: .bottom, spacing: DS.space8) {
                    ForEach(Array(report.days.enumerated()), id: \.element.id) { index, day in
                        AllocationDayBar(day: day, maxMinutes: maxMinutes, animate: chartAnimated, index: index)
                    }
                }
                .frame(height: 150)
            }
        }
    }

    private var maxMinutes: Int {
        max(report.days.map(\.trackedMinutes).max() ?? 1, 1)
    }
}

private struct AllocationDayBar: View {
    let day: DayReportEntry
    let maxMinutes: Int
    let animate: Bool
    let index: Int

    var body: some View {
        VStack(spacing: DS.space4) {
            Spacer(minLength: 0)

            if day.trackedMinutes > 0 {
                Text(formatReportMinutes(day.trackedMinutes))
                    .font(DS.caption2.weight(.medium))
                    .foregroundStyle(DS.textMuted)
                    .monospacedDigit()
            }

            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(day.dominantIntent?.accent ?? DS.info)
                .frame(height: animate ? barHeight : 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(day.isToday ? DS.accent : Color.clear, lineWidth: 1)
                )
                .animation(ProMotionSprings.cascade(index: min(index, 8)), value: animate)

            Text(day.dayLabel)
                .font(DS.caption2.weight(day.isToday ? .semibold : .medium))
                .foregroundStyle(day.isToday ? DS.accent : DS.textMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var barHeight: CGFloat {
        max(CGFloat(day.trackedMinutes) / CGFloat(maxMinutes) * 108, day.trackedMinutes > 0 ? 10 : 4)
    }
}

private struct IntentBreakdownList: View {
    let report: ReportData

    var body: some View {
        CommandCenterMaterialPanel(cornerRadius: 14, contentPadding: DS.space16) {
            VStack(alignment: .leading, spacing: DS.space10) {
                ReportsSectionHeader(title: "By Intent", count: nil, tint: DS.entityIdea)

                if report.intentDistribution.isEmpty {
                    Text("Tracked sessions will show where the week actually went.")
                        .font(DS.callout)
                        .foregroundStyle(DS.textSecondary)
                } else {
                    VStack(alignment: .leading, spacing: DS.space8) {
                        ForEach(Array(report.intentDistribution.prefix(6)), id: \.id) { intent in
                            IntentAllocationRow(intent: intent, totalMinutes: max(report.totalMinutes, 1))
                        }
                    }
                }
            }
        }
    }
}

private struct IntentAllocationRow: View {
    let intent: IntentSummary
    let totalMinutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            HStack(spacing: DS.space8) {
                Label(intent.title, systemImage: intent.icon)
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(intent.accent)
                    .lineLimit(1)

                Spacer(minLength: DS.space8)

                Text("\(formatReportMinutes(intent.minutes)) · \(percent)%")
                    .font(DS.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(DS.textMuted)
            }

            GeometryReader { proxy in
                let width = max(proxy.size.width * CGFloat(percent) / 100, intent.minutes > 0 ? 8 : 0)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(DS.glassInputFill)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(intent.accent)
                        .frame(width: width)
                }
            }
            .frame(height: 7)
        }
    }

    private var percent: Int {
        Int(Double(intent.minutes) / Double(max(totalMinutes, 1)) * 100)
    }
}

private struct FocusPatternPane: View {
    let report: ReportData

    var body: some View {
        CommandCenterMaterialPanel(cornerRadius: 14, contentPadding: DS.space12) {
            VStack(alignment: .leading, spacing: DS.space10) {
                ReportsSectionHeader(title: "Planning Signal", count: nil, tint: focusTint)
                ReportInsightRow(icon: "target", title: focusTitle, subtitle: focusSubtitle, tint: focusTint)
                ReportInsightRow(icon: "calendar", title: "Next move", subtitle: nextMove, tint: DS.accent)
            }
        }
    }

    private var focusTint: Color {
        if report.avgFocusScore >= 80 { return DS.green }
        if report.avgFocusScore >= 65 { return DS.orange }
        return DS.info
    }

    private var focusTitle: String {
        if report.totalSessions == 0 { return "No tracked work" }
        if report.avgFocusScore >= 80 { return "Depth is holding" }
        if report.avgFocusScore >= 65 { return "Friction is visible" }
        return "Make the next block smaller"
    }

    private var focusSubtitle: String {
        if report.totalSessions == 0 { return "Start with one session before reading patterns." }
        return "\(report.totalSessions) sessions · \(formatReportMinutes(report.avgSessionMinutes)) average"
    }

    private var nextMove: String {
        if report.totalSessions == 0 { return "start focus" }
        if report.avgFocusScore >= 80 { return "protect same hours" }
        if report.avgFocusScore >= 65 { return "review interruptions" }
        return "schedule work"
    }
}

private struct HabitHistoryReportView: View {
    let report: HabitReportData
    let chartAnimated: Bool

    var body: some View {
        LazyVStack(alignment: .leading, spacing: DS.space16) {
            CommandCenterMaterialPanel(cornerRadius: 14, contentPadding: DS.space16) {
                HStack(alignment: .center, spacing: DS.space18) {
                    VStack(alignment: .leading, spacing: DS.space8) {
                        Text("Habit history")
                            .font(DS.title2)
                            .foregroundStyle(DS.commandCenterTitleText)

                        Text(historyLine)
                            .font(DS.callout)
                            .foregroundStyle(DS.commandCenterSecondaryText)
                    }

                    Spacer()

                    ReportMetricStack(title: "Completion", value: "\(Int(report.overallCompletionRate * 100))%", tint: DS.entityIdea)
                    ReportMetricStack(title: "Done", value: "\(report.totalCompletions)", tint: DS.green)
                    ReportMetricStack(title: "Possible", value: "\(report.totalPossible)", tint: DS.textMuted)
                }
            }

            VStack(alignment: .leading, spacing: DS.space10) {
                ReportsSectionHeader(title: "By Habit", count: "\(report.habitEntries.count)", tint: DS.entityIdea)
                ForEach(report.habitEntries) { entry in
                    HabitHistoryRow(entry: entry, animate: chartAnimated)
                }
            }
        }
    }

    private var historyLine: String {
        if let needsWork = report.needsWork {
            return "\(needsWork.habitTitle) needs attention · review habit"
        }
        if let mostConsistent = report.mostConsistent {
            return "\(mostConsistent.habitTitle) is carrying the cadence."
        }
        return "A calm read on what is repeating, not a scoreboard."
    }
}

private struct HabitHistoryRow: View {
    let entry: HabitReportEntry
    let animate: Bool

    @State private var isHovered = false

    var body: some View {
        let accent = entry.habitDefinition.accent
        VStack(alignment: .leading, spacing: DS.space8) {
            HStack(spacing: DS.space8) {
                Label(entry.habitDefinition.title, systemImage: entry.habitDefinition.icon)
                    .font(DS.headline)
                    .foregroundStyle(accent)
                    .lineLimit(1)

                Spacer(minLength: DS.space8)

                Text("\(Int(entry.completionRate * 100))%")
                    .font(DS.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(accent)
            }

            HStack(spacing: 3) {
                ForEach(Array(entry.sortedDays.suffix(30).enumerated()), id: \.offset) { index, item in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(item.completed ? accent : DS.commandCenterSeparatorStrong)
                        .frame(height: 10)
                        .opacity(animate ? 1 : 0.35)
                        .animation(ProMotionSprings.cascade(index: min(index, 8)), value: animate)
                        .accessibilityHidden(true)
                }
            }

            HStack(spacing: DS.space8) {
                Text("\(entry.completedDays)/\(entry.totalDays) days")
                    .font(DS.caption)
                    .monospacedDigit()
                    .foregroundStyle(DS.textMuted)

                Text("best streak \(entry.bestStreak)")
                    .font(DS.caption)
                    .monospacedDigit()
                    .foregroundStyle(DS.textMuted)

                Spacer()

                Text(entry.completionRate < 0.5 ? "review habit" : "keep cadence")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(entry.completionRate < 0.5 ? DS.orange : DS.green)
            }
        }
        .padding(DS.space12)
        .background(DS.commandChromePanelFill, in: .rect(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isHovered ? accent.opacity(0.24) : DS.commandChromeBorder, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(isHovered ? 0.06 : 0.035), radius: isHovered ? 12 : 6, x: 0, y: isHovered ? 3 : 1)
        .scaleEffect(isHovered ? 1.01 : 1)
        .animation(ProMotionSprings.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
    }
}

private struct ReportMetricStack: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: DS.space4) {
            Text(value)
                .font(DS.title2)
                .monospacedDigit()
                .foregroundStyle(tint)

            Text(title)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.textMuted)
        }
    }
}

private struct ReportsSectionHeader: View {
    let title: String
    let count: String?
    let tint: Color

    var body: some View {
        HStack(spacing: DS.space6) {
            Text(title)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(tint)

            if let count {
                Text(count)
                    .font(DS.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint.opacity(0.66))
            }

            Rectangle()
                .fill(DS.commandCenterSeparator)
                .frame(height: 0.5)
        }
    }
}

private struct ReportInsightRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: DS.space8) {
            Image(systemName: icon)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.08), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.subheadline.weight(.semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)

                Text(subtitle)
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private func formatReportMinutes(_ minutes: Int) -> String {
    let hours = minutes / 60
    let remainder = minutes % 60
    if hours > 0 {
        return "\(hours)h \(remainder)m"
    }
    return "\(remainder)m"
}
