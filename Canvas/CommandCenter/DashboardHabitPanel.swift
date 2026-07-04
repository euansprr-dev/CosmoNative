import SwiftUI

struct DashboardHabitPanel: View {
    @ObservedObject var viewModel: CommandCenterDashboardViewModel
    let composer: CommandCenterComposerController

    @State private var animateProgress = false
    @State private var completedHabitId: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader

            if viewModel.habits.isEmpty {
                emptyState
            } else {
                habitList
            }
        }
        .task { await viewModel.loadHabits() }
        .onAppear { triggerEntranceAnimation() }
    }

    // MARK: - Header

    private var sectionHeader: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "repeat")
                    .font(DS.caption2).fontWeight(.semibold)
                    .foregroundStyle(DS.commandCenterOrnamentText)
                Text("Habits")
                    .font(DS.smallCaps)
                    .foregroundStyle(DS.commandCenterOrnamentText)
                if !viewModel.habits.isEmpty {
                    Text("\(viewModel.habits.filter(\.isTodayComplete).count) of \(viewModel.habits.count)")
                        .font(DS.caption2.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(DS.textMuted)
                        .contentTransition(.numericText())
                }
            }

            Spacer()

            CommandCenterComposerTrigger(composer: composer, alignment: .trailing) { anchor in
                .habitLibrary(anchor: anchor)
            } label: {
                Image(systemName: "gearshape")
                    .font(DS.caption)
                    .foregroundStyle(DS.commandCenterMutedText)
                    .frame(width: 26, height: 26)
            }
            .accessibilityLabel("Manage habits")

            CommandCenterComposerTrigger(composer: composer, alignment: .trailing) { anchor in
                .habitEditor(habit: nil, anchor: anchor)
            } label: {
                Image(systemName: "plus")
                    .font(DS.subheadline).fontWeight(.semibold)
                    .frame(width: 26, height: 26)
                    .foregroundStyle(DS.accent)
            }
            .accessibilityLabel("Add habit")
        }
    }

    // MARK: - Habit List

    private var habitList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 6) {
                ForEach(viewModel.habits) { habit in
                    DashboardHabitOrbitCard(
                        habit: habit,
                        definition: viewModel.habitDefinition(for: habit.id),
                        animateProgress: animateProgress,
                        completedHabitId: completedHabitId,
                        reduceMotion: reduceMotion,
                        onRecordManual: {
                            Task { await viewModel.recordManualHabitCompletion(habitUUID: habit.id) }
                            if !reduceMotion {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                                    completedHabitId = habit.id
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                        completedHabitId = nil
                                    }
                                }
                            }
                        },
                        composer: composer
                    )
                }
            }
            .padding(.bottom, 6)
        }
    }

    // MARK: - Animations

    private func triggerEntranceAnimation() {
        guard !animateProgress else { return }
        if reduceMotion {
            animateProgress = true
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    animateProgress = true
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        CommandCenterEmptyPane(
            icon: "repeat",
            title: "No habits yet",
            subtitle: "Create a habit and completed tasks can begin feeding progress automatically."
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.space8)
    }
}

private struct DashboardHabitOrbitCard: View {
    let habit: HabitState
    let definition: HabitDefinition?
    let animateProgress: Bool
    let completedHabitId: String?
    let reduceMotion: Bool
    let onRecordManual: () -> Void
    let composer: CommandCenterComposerController

    @State private var frame: CGRect = .zero
    @State private var isHovered = false

    var body: some View {
        let isComplete = habit.isTodayComplete

        HStack(alignment: .center, spacing: DS.space10) {
            habitRing

            VStack(alignment: .leading, spacing: 4) {
                titleRow
                detailRow
            }

            Spacer(minLength: 0)

            trailingAccessory
        }
        .padding(.horizontal, DS.space8)
        .padding(.vertical, DS.space8)
        .background {
            if isHovered || isComplete {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isComplete ? habit.accentColor.opacity(0.075) : DS.glassCardFill)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isHovered || isComplete ? habit.accentColor.opacity(isComplete ? 0.22 : 0.16) : Color.clear,
                    lineWidth: 0.5
                )
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill((isHovered || isComplete) ? Color.clear : DS.commandCenterSeparator)
                .frame(height: 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .background(CommandCenterGlobalFrameReader(frame: $frame))
        .onTapGesture {
            guard let definition else { return }
            composer.present(.habitEditor(habit: definition, anchor: .init(sourceRect: frame, alignment: .trailing)))
        }
        .onHover { hovering in
            withAnimation(reduceMotion ? .easeOut(duration: 0.01) : ProMotionSprings.hover) {
                isHovered = hovering
            }
        }
    }

    private var habitRing: some View {
        let accent = habit.accentColor
        let progress = animateProgress ? habit.todayProgress : 0
        let isComplete = habit.isTodayComplete
        let justCompleted = completedHabitId == habit.id

        // iOS-parity ring: hollow interior, 3.5pt track at 18% accent,
        // full-accent progress arc with round caps.
        return ZStack {
            Circle()
                .stroke(accent.opacity(0.18), lineWidth: 3.5)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(accent, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(
                    reduceMotion ? .none : .spring(response: 0.6, dampingFraction: 0.7),
                    value: progress
                )

            Image(systemName: habit.iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isComplete ? accent : DS.textSecondary)
        }
        .frame(width: 34, height: 34)
        .scaleEffect(justCompleted ? 1.08 : 1.0)
        .animation(
            reduceMotion ? .none : .spring(response: 0.25, dampingFraction: 0.5),
            value: justCompleted
        )
    }

    private var titleRow: some View {
        HStack(spacing: 6) {
            Text(habit.title)
                .font(DS.subheadline).fontWeight(.medium)
                .foregroundStyle(habit.isTodayComplete ? habit.accentColor : DS.text)
                .lineLimit(1)

            Spacer(minLength: 0)

            sevenDayDots
        }
    }

    private var sevenDayDots: some View {
        let accent = habit.accentColor
        return HStack(spacing: 3) {
            ForEach(Array(habit.last7Days.enumerated()), id: \.offset) { index, completed in
                let isToday = index == 6
                RoundedRectangle(cornerRadius: 2)
                    .fill(completed ? accent : (isToday ? Color.clear : DS.commandCenterSeparatorStrong))
                    .frame(width: 6, height: 6)
                    .overlay {
                        if isToday && !completed {
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(accent.opacity(0.4), lineWidth: 1)
                        }
                    }
            }
        }
    }

    private var detailRow: some View {
        HStack(spacing: 0) {
            if habit.isTodayComplete {
                Text("Done")
                    .font(DS.caption2).fontWeight(.medium)
                    .foregroundStyle(habit.accentColor)
            } else {
                Text(habit.todayProgressLabel)
                    .font(DS.caption2).fontWeight(.medium)
                    .foregroundStyle(DS.textSecondary)
            }

            if !habit.isTimeBased, habit.trackedMinutesToday > 0 {
                Text("  ·  \(habit.trackedMinutesToday)m")
                    .font(DS.caption2).fontWeight(.medium)
                    .foregroundStyle(DS.textMuted)
            }

            if (habit.isTimeBased || habit.targetCount > 1) && !habit.isTodayComplete {
                Spacer(minLength: 8)
                inlineProgressBar
            }
        }
    }

    private var inlineProgressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(DS.borderSubtle)
                    .frame(height: 3)

                RoundedRectangle(cornerRadius: 1.5)
                    .fill(habit.accentColor.opacity(0.65))
                    .frame(width: proxy.size.width * (animateProgress ? habit.todayProgress : 0), height: 3)
                    .animation(
                        reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.8),
                        value: animateProgress
                    )
            }
        }
        .frame(width: 48, height: 3)
    }

    // iOS-parity accessory: accent plus while incomplete, seal stamp once done.
    @ViewBuilder
    private var trailingAccessory: some View {
        let accent = habit.accentColor

        if habit.allowManualComplete && !habit.isTodayComplete {
            Button(action: onRecordManual) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(accent)
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Check in")
            .accessibilityLabel("Check in")
        } else if habit.isTodayComplete {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 18))
                .foregroundStyle(accent)
                .frame(width: 26, height: 26)
                .transition(.scale(scale: 1.4).combined(with: .opacity))
        }
    }


}
