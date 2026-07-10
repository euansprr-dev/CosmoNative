import SwiftUI

struct HabitsSectionView: View {
    var viewModel: CommandCenterDashboardViewModel
    let composer: CommandCenterComposerController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animateProgress = false

    var body: some View {
        CommandCenterPlanningPageScaffold(
            title: "Habits",
            icon: "repeat",
            subtitle: subtitle,
            accent: DS.entityIdea,
            actions: { headerActions },
            content: { content }
        )
        .task {
            await viewModel.loadHabits()
            await viewModel.loadHabitReport()
            await viewModel.loadTodayTimeData()
        }
        .onAppear(perform: triggerEntrance)
    }

    private var subtitle: String {
        let complete = viewModel.habits.filter(\.isTodayComplete).count
        return "\(complete)/\(viewModel.habits.count) complete today · \(formatMinutes(viewModel.todayTrackedMinutes)) tracked"
    }

    private var headerActions: some View {
        HStack(spacing: DS.space8) {
            CommandCenterComposerTrigger(composer: composer, alignment: .trailing) { anchor in
                .habitLibrary(anchor: anchor)
            } label: {
                HabitHeaderIcon(icon: "slider.horizontal.3", title: "Manage habits")
            }
            .help("Manage habits")
            .accessibilityLabel("Manage habits")

            CommandCenterComposerTrigger(composer: composer, alignment: .trailing) { anchor in
                .habitEditor(habit: nil, anchor: anchor)
            } label: {
                HabitHeaderIcon(icon: "plus", title: "Add habit", isPrimary: true)
            }
            .help("Add habit")
            .accessibilityLabel("Add habit")
        }
    }

    private var content: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: DS.space16) {
                HabitTodayHero(
                    habits: viewModel.habits,
                    trackedMinutes: viewModel.todayTrackedMinutes,
                    animateProgress: animateProgress
                )

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: DS.space16) {
                        HabitPracticeList(
                            viewModel: viewModel,
                            composer: composer,
                            animateProgress: animateProgress
                        )
                        .frame(maxWidth: .infinity)

                        habitSupportColumn
                            .frame(width: 320)
                    }

                    VStack(alignment: .leading, spacing: DS.space16) {
                        HabitPracticeList(
                            viewModel: viewModel,
                            composer: composer,
                            animateProgress: animateProgress
                        )
                        habitSupportColumn
                    }
                }
            }
            .padding(.bottom, DS.space24)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    private var habitSupportColumn: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            HabitRecoveryPane(viewModel: viewModel)
            HabitConsistencyPane(viewModel: viewModel)
        }
    }

    private func triggerEntrance() {
        guard !animateProgress else { return }
        if reduceMotion {
            animateProgress = true
        } else {
            withAnimation(ProMotionSprings.gentle) {
                animateProgress = true
            }
        }
    }
}

private struct HabitTodayHero: View {
    let habits: [HabitState]
    let trackedMinutes: Int
    let animateProgress: Bool

    var body: some View {
        CommandCenterMaterialPanel(cornerRadius: 14, contentPadding: DS.space16) {
            HStack(alignment: .center, spacing: DS.space18) {
                VStack(alignment: .leading, spacing: DS.space8) {
                    Text("Today's practice")
                        .font(DS.title2)
                        .foregroundStyle(DS.commandCenterTitleText)

                    Text(summary)
                        .font(DS.callout)
                        .foregroundStyle(DS.commandCenterSecondaryText)
                        .lineLimit(2)

                    progressTrack
                        .frame(maxWidth: 520)
                }

                Spacer(minLength: DS.space16)

                VStack(alignment: .trailing, spacing: DS.space4) {
                    Text("\(completionPercent)%")
                        .font(DS.pageTitle)
                        .monospacedDigit()
                        .foregroundStyle(DS.accent)
                        .accessibilityLabel("\(completionPercent) percent of habits complete today")

                    Text("\(formatMinutes(trackedMinutes)) tracked")
                        .font(DS.subheadline)
                        .foregroundStyle(DS.textMuted)
                }
            }
        }
    }

    private var progressTrack: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width * CGFloat(animatedProgress), 8)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(DS.glassInputFill)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(DS.accent)
                    .frame(width: width)
            }
        }
        .frame(height: 8)
        .animation(ProMotionSprings.gentle, value: animatedProgress)
    }

    private var animatedProgress: Double {
        animateProgress ? Double(completionPercent) / 100 : 0
    }

    private var completionPercent: Int {
        guard !habits.isEmpty else { return 0 }
        let complete = habits.filter(\.isTodayComplete).count
        return Int(Double(complete) / Double(habits.count) * 100)
    }

    private var summary: String {
        guard !habits.isEmpty else {
            return "Add one practice and let tasks or focus sessions feed it automatically."
        }

        let remaining = habits.filter { !$0.isTodayComplete }.count
        if remaining == 0 {
            return "Everything planned for today is complete."
        }
        return "\(remaining) still open · complete, lighten, or leave it visible for review."
    }
}

private struct HabitPracticeList: View {
    var viewModel: CommandCenterDashboardViewModel
    let composer: CommandCenterComposerController
    let animateProgress: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            HabitSectionHeader(title: "Today", count: "\(viewModel.habits.count)", tint: DS.entityIdea)

            if viewModel.habits.isEmpty {
                CommandCenterEmptyPane(
                    icon: "repeat",
                    title: "Start with one practice",
                    subtitle: "Add a habit that your tasks or focus sessions can feed automatically."
                )
            } else {
                VStack(spacing: DS.space8) {
                    ForEach(viewModel.habits) { habit in
                        HabitPlanningRow(
                            habit: habit,
                            definition: viewModel.habitDefinition(for: habit.id),
                            animateProgress: animateProgress,
                            onRecordManual: {
                                Task { await viewModel.recordManualHabitCompletion(habitUUID: habit.id) }
                            },
                            composer: composer
                        )
                    }
                }
            }
        }
    }
}

private struct HabitPlanningRow: View {
    let habit: HabitState
    let definition: HabitDefinition?
    let animateProgress: Bool
    let onRecordManual: () -> Void
    let composer: CommandCenterComposerController

    @State private var isHovered = false
    @State private var isManualHovered = false
    @State private var isEditHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: DS.space12) {
            habitRing

            VStack(alignment: .leading, spacing: DS.space4) {
                HStack(spacing: DS.space8) {
                    Text(habit.title)
                        .font(DS.headline)
                        .foregroundStyle(habit.isTodayComplete ? habit.accentColor : DS.text)
                        .lineLimit(1)

                    Spacer(minLength: DS.space8)

                    sevenDayDots
                }

                HStack(spacing: DS.space8) {
                    sourcePill
                    Text(habit.isTimeBased
                        ? "\(min(habit.trackedMinutesToday, habit.targetMinutes ?? 0))/\(habit.targetMinutes ?? 0)m"
                        : "\(habit.todayCount)/\(max(habit.targetCount, 1))")
                        .font(DS.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(DS.textSecondary)

                    if !habit.isTimeBased {
                        Text(formatMinutes(habit.trackedMinutesToday))
                            .font(DS.caption)
                            .monospacedDigit()
                            .foregroundStyle(DS.textMuted)
                    }
                }
            }

            Spacer(minLength: DS.space10)
            manualButton
            editButton
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(rowFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(habit.accentColor.opacity(isHovered || habit.isTodayComplete ? 0.24 : 0.10), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(isHovered ? 0.06 : 0.035), radius: isHovered ? 12 : 6, x: 0, y: isHovered ? 3 : 1)
        .scaleEffect(isHovered ? 1.01 : 1)
        .animation(ProMotionSprings.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
    }

    private var habitRing: some View {
        ZStack {
            Circle()
                .stroke(habit.accentColor.opacity(0.14), lineWidth: 3)
                .frame(width: 44, height: 44)

            Circle()
                .trim(from: 0, to: animateProgress ? habit.todayProgress : 0)
                .stroke(habit.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 44, height: 44)

            Image(systemName: habit.isTodayComplete ? "checkmark" : habit.iconName)
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(habit.accentColor)
                .frame(width: 34, height: 34)
                .background(habit.accentColor.opacity(0.08), in: Circle())
        }
        .animation(ProMotionSprings.gentle, value: animateProgress)
    }

    private var sevenDayDots: some View {
        HStack(spacing: DS.space4) {
            ForEach(Array(habit.last7Days.enumerated()), id: \.offset) { index, completed in
                let isToday = index == habit.last7Days.count - 1
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(completed ? habit.accentColor : DS.commandCenterSeparatorStrong)
                    .frame(width: 7, height: 7)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .stroke(isToday && !completed ? habit.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
                    )
                    .accessibilityHidden(true)
            }
        }
    }

    private var sourcePill: some View {
        Text(habit.sourceBreakdown.summaryText ?? "Ready")
            .font(DS.caption.weight(.medium))
            .foregroundStyle(DS.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, DS.space6)
            .padding(.vertical, 2)
            .background(DS.glassInputFill, in: Capsule())
            .overlay(Capsule().stroke(DS.glassBorder, lineWidth: 0.5))
    }

    private var manualButton: some View {
        Button(action: onRecordManual) {
            Image(systemName: habit.isTodayComplete ? "checkmark.circle.fill" : "plus.circle")
                .font(DS.title3.weight(.semibold))
                .foregroundStyle(habit.allowManualComplete ? (isManualHovered ? habit.accentColor : habit.accentColor.opacity(0.86)) : DS.textMuted)
                .frame(width: 44, height: 44)
                .background(habit.allowManualComplete && isManualHovered ? habit.accentColor.opacity(0.08) : Color.clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!habit.allowManualComplete)
        .scaleEffect(isManualHovered ? 1.01 : 1)
        .animation(ProMotionSprings.hover, value: isManualHovered)
        .onHover { isManualHovered = $0 }
        .help(habit.allowManualComplete ? "Log one completion" : "This habit completes from tasks or focus sessions")
        .accessibilityLabel(habit.allowManualComplete ? "Log \(habit.title)" : "\(habit.title) completes automatically")
    }

    private var editButton: some View {
        CommandCenterComposerTrigger(composer: composer, alignment: .trailing) { anchor in
            .habitEditor(habit: definition, anchor: anchor)
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(isEditHovered ? DS.textSecondary : DS.textMuted)
                .frame(width: 44, height: 44)
                .background(isEditHovered ? DS.glassInputFill : Color.clear, in: Circle())
                .contentShape(Circle())
        }
        .scaleEffect(isEditHovered ? 1.01 : 1)
        .animation(ProMotionSprings.hover, value: isEditHovered)
        .onHover { isEditHovered = $0 }
        .help("Edit \(habit.title)")
        .accessibilityLabel("Edit \(habit.title)")
    }

    private var rowFill: Color {
        if habit.isTodayComplete {
            return habit.accentColor.opacity(0.08)
        }
        if isHovered {
            return DS.glassCardFill
        }
        return DS.commandChromePanelFill
    }
}

private struct HabitRecoveryPane: View {
    var viewModel: CommandCenterDashboardViewModel

    var body: some View {
        CommandCenterMaterialPanel(cornerRadius: 14, contentPadding: DS.space12) {
            VStack(alignment: .leading, spacing: DS.space10) {
                HabitSectionHeader(title: "Recovery", count: nil, tint: DS.orange)

                if recoveryHabits.isEmpty {
                    Text("Nothing needs rescue right now. Keep the list visible and let the day stay honest.")
                        .font(DS.callout)
                        .foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: DS.space8) {
                        ForEach(recoveryHabits) { habit in
                            recoveryRow(habit)
                        }
                    }
                }
            }
        }
    }

    private var recoveryHabits: [HabitState] {
        Array(viewModel.habits.filter { !$0.isTodayComplete && $0.consistencyCount <= 3 }.prefix(5))
    }

    private func recoveryRow(_ habit: HabitState) -> some View {
        HStack(spacing: DS.space8) {
            Image(systemName: habit.iconName)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(habit.accentColor)
                .frame(width: 24, height: 24)
                .background(habit.accentColor.opacity(0.08), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(habit.title)
                    .font(DS.subheadline.weight(.semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)

                Text(recoveryText(for: habit))
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.space4)
    }

    private func recoveryText(for habit: HabitState) -> String {
        if habit.trackedMinutesToday == 0 && habit.todayCount == 0 {
            return "Complete once today"
        }
        if habit.consistencyCount == 0 {
            return "No work logged this week"
        }
        return "Needs a lighter target"
    }
}

private struct HabitConsistencyPane: View {
    var viewModel: CommandCenterDashboardViewModel

    var body: some View {
        CommandCenterMaterialPanel(cornerRadius: 14, contentPadding: DS.space12) {
            VStack(alignment: .leading, spacing: DS.space10) {
                HabitSectionHeader(title: "Consistency", count: completionText, tint: DS.entityIdea)

                if let report = viewModel.habitReportData, !report.habitEntries.isEmpty {
                    VStack(alignment: .leading, spacing: DS.space8) {
                        ForEach(Array(report.habitEntries.prefix(4)), id: \.id) { entry in
                            consistencyRow(entry)
                        }
                    }
                } else {
                    Text("A few logged days will turn this into a useful pattern view.")
                        .font(DS.callout)
                        .foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var completionText: String? {
        guard let report = viewModel.habitReportData else { return nil }
        return "\(Int(report.overallCompletionRate * 100))%"
    }

    private func consistencyRow(_ entry: HabitReportEntry) -> some View {
        let accent = entry.habitDefinition.accent
        return VStack(alignment: .leading, spacing: DS.space4) {
            HStack {
                Text(entry.habitDefinition.title)
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)

                Spacer()

                Text("\(Int(entry.completionRate * 100))%")
                    .font(DS.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(accent)
            }

            HStack(spacing: 3) {
                ForEach(Array(entry.sortedDays.suffix(14).enumerated()), id: \.offset) { _, item in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(item.completed ? accent : DS.commandCenterSeparatorStrong)
                        .frame(height: 7)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

private struct HabitHeaderIcon: View {
    let icon: String
    let title: String
    var isPrimary = false

    @State private var isHovered = false

    var body: some View {
        Image(systemName: icon)
            .font(DS.callout.weight(.semibold))
            .foregroundStyle(isPrimary ? DS.textOnAccent : (isHovered ? DS.text : DS.commandCenterSecondaryText))
            .frame(width: 44, height: 44)
            .background(isPrimary ? DS.accent : DS.glassInputFill, in: Circle())
            .overlay(Circle().stroke(isPrimary ? Color.clear : DS.glassBorder, lineWidth: 0.5))
            .scaleEffect(isHovered ? 1.01 : 1)
            .animation(ProMotionSprings.hover, value: isHovered)
            .onHover { isHovered = $0 }
            .accessibilityLabel(title)
    }
}

private struct HabitSectionHeader: View {
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

private func formatMinutes(_ minutes: Int) -> String {
    let hours = minutes / 60
    let remainder = minutes % 60
    if hours > 0 {
        return "\(hours)h \(remainder)m"
    }
    return "\(remainder)m"
}
