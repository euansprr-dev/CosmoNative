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
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.giltMuted)
                Text("Habits")
                    .font(DS.smallCaps)
                    .foregroundStyle(DS.giltMuted)
            }

            Spacer()

            CommandCenterComposerTrigger(composer: composer, alignment: .trailing) { anchor in
                .habitLibrary(anchor: anchor)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.inkFaded)
                    .frame(width: 26, height: 26)
            }
            .accessibilityLabel("Manage habits")

            CommandCenterComposerTrigger(composer: composer, alignment: .trailing) { anchor in
                .habitEditor(habit: nil, anchor: anchor)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
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
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 16)
                .fill(DS.bg)
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: "repeat")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(DS.textMuted)
                )

            Text("No habits yet")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.text)

            Text("Create a custom habit, map it to task intents or keywords, and let completed tasks feed it automatically.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.textMuted)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.borderSubtle, lineWidth: 1)
        )
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

    var body: some View {
        let isComplete = habit.isTodayComplete

        HStack(alignment: .center, spacing: DS.space10) {
            habitRing

            VStack(alignment: .leading, spacing: 4) {
                titleRow
                detailRow
            }

            Spacer(minLength: 0)

            if habit.allowManualComplete {
                manualButton
            }
        }
        .padding(.horizontal, DS.space8)
        .padding(.vertical, DS.space8)
        .background {
            if isComplete {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(habit.accentColor.opacity(0.045))
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DS.sepiaSubtle.opacity(0.75))
                .frame(height: 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .background(CommandCenterGlobalFrameReader(frame: $frame))
        .onTapGesture {
            guard let definition else { return }
            composer.present(.habitEditor(habit: definition, anchor: .init(sourceRect: frame, alignment: .trailing)))
        }
    }

    private var habitRing: some View {
        let accent = habit.accentColor
        let progress = animateProgress ? habit.todayProgress : 0
        let isComplete = habit.isTodayComplete
        let justCompleted = completedHabitId == habit.id

        return ZStack {
            Circle()
                .stroke(accent.opacity(0.12), lineWidth: 2)
                .frame(width: 36, height: 36)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 36, height: 36)
                .animation(
                    reduceMotion ? .none : .spring(response: 0.6, dampingFraction: 0.7),
                    value: progress
                )

            Image(systemName: habit.iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 30, height: 30)
                .background(accent.opacity(isComplete ? 0.14 : 0.06), in: Circle())

            if isComplete {
                completionBadge(accent: accent)
            }
        }
        .scaleEffect(justCompleted ? 1.08 : 1.0)
        .animation(
            reduceMotion ? .none : .spring(response: 0.25, dampingFraction: 0.5),
            value: justCompleted
        )
    }

    private func completionBadge(accent: Color) -> some View {
        Image(systemName: "checkmark")
            .font(.system(size: 7, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 12, height: 12)
            .background(accent, in: Circle())
            .overlay(Circle().stroke(DS.surface, lineWidth: 1.5))
            .offset(x: 13, y: 13)
            .transition(.scale.combined(with: .opacity))
    }

    private var titleRow: some View {
        HStack(spacing: 6) {
            Text(habit.title)
                .font(.system(size: 12, weight: .medium))
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
                    .fill(completed ? accent : (isToday ? Color.clear : DS.sepiaSubtle))
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
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(habit.accentColor)
            } else {
                Text("\(habit.todayCount)/\(habit.targetCount) today")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DS.textSecondary)
            }

            if habit.trackedMinutesToday > 0 {
                Text("  ·  \(habit.trackedMinutesToday)m")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DS.textMuted)
            }

            if habit.targetCount > 1 && !habit.isTodayComplete {
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

    private var manualButton: some View {
        let accent = habit.accentColor
        let isDone = habit.todayCount >= habit.targetCount

        return Button(action: onRecordManual) {
            Image(systemName: isDone ? "checkmark" : "plus")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isDone ? accent.opacity(0.5) : accent)
                .frame(width: 26, height: 26)
                .background(isDone ? accent.opacity(0.10) : DS.bg, in: Circle())
                .overlay(
                    Circle().stroke(isDone ? accent.opacity(0.15) : DS.borderSubtle, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDone)
    }


}
