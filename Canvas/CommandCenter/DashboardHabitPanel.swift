import SwiftUI

struct DashboardHabitPanel: View {
    @ObservedObject var viewModel: CommandCenterDashboardViewModel

    @State private var editingHabit: HabitDefinition?
    @State private var creatingHabit = false
    @State private var showingHabitSettings = false
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
        .popover(item: $editingHabit, attachmentAnchor: .rect(.bounds), arrowEdge: .leading) { habit in
            habitEditorPopover(habit)
        }
        .popover(isPresented: $creatingHabit, attachmentAnchor: .rect(.bounds), arrowEdge: .leading) {
            habitCreatePopover
        }
    }

    // MARK: - Header

    private var sectionHeader: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "repeat")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DS.giltMuted)
                Text("Habits")
                    .font(DS.smallCaps)
                    .foregroundStyle(DS.giltMuted)
            }

            Spacer()

            Button {
                showingHabitSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.inkFaded)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingHabitSettings, arrowEdge: .leading) {
                habitSettingsPopover
            }

            Button {
                creatingHabit = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text("Habit")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(DS.accent)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Habit List

    private var habitList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 6) {
                ForEach(viewModel.habits) { habit in
                    orbitCard(habit)
                }
            }
            .padding(.bottom, 6)
        }
    }

    // MARK: - Orbit Card

    @ViewBuilder
    private func orbitCard(_ habit: HabitState) -> some View {
        let isComplete = habit.isTodayComplete

        HStack(alignment: .center, spacing: 12) {
            habitRing(habit)

            VStack(alignment: .leading, spacing: 4) {
                titleRow(habit)
                detailRow(habit)
            }

            Spacer(minLength: 0)

            if habit.allowManualComplete {
                manualButton(habit)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isComplete ? DS.gilt.opacity(0.3) : DS.sepiaBorder.opacity(0.4), lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture {
            if let definition = viewModel.habitDefinition(for: habit.id) {
                editingHabit = definition
            }
        }
    }

    // MARK: - Ring Progress

    @ViewBuilder
    private func habitRing(_ habit: HabitState) -> some View {
        let accent = habit.accentColor
        let progress = animateProgress ? habit.todayProgress : 0
        let isComplete = habit.isTodayComplete
        let justCompleted = completedHabitId == habit.id

        ZStack {
            Circle()
                .stroke(accent.opacity(0.10), lineWidth: 2.5)
                .frame(width: 44, height: 44)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 44, height: 44)
                .animation(
                    reduceMotion ? .none : .spring(response: 0.6, dampingFraction: 0.7),
                    value: progress
                )

            Image(systemName: habit.iconName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 38, height: 38)
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
            .frame(width: 14, height: 14)
            .background(accent, in: Circle())
            .overlay(Circle().stroke(DS.surface, lineWidth: 1.5))
            .offset(x: 15, y: 15)
            .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Title Row

    @ViewBuilder
    private func titleRow(_ habit: HabitState) -> some View {
        HStack(spacing: 6) {
            Text(habit.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(habit.isTodayComplete ? habit.accentColor : DS.text)
                .lineLimit(1)

            Spacer(minLength: 0)

            sevenDayDots(habit)
        }
    }

    // MARK: - 7-Day Dots

    @ViewBuilder
    private func sevenDayDots(_ habit: HabitState) -> some View {
        let accent = habit.accentColor
        HStack(spacing: 3) {
            ForEach(Array(habit.last7Days.enumerated()), id: \.offset) { index, completed in
                let isToday = index == 6
                RoundedRectangle(cornerRadius: 2)
                    .fill(completed ? accent : (isToday ? Color.clear : DS.sepiaSubtle))
                    .frame(width: 7, height: 7)
                    .overlay {
                        if isToday && !completed {
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(accent.opacity(0.4), lineWidth: 1)
                        }
                    }
            }
        }
    }

    // MARK: - Detail Row

    @ViewBuilder
    private func detailRow(_ habit: HabitState) -> some View {
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
                inlineProgressBar(habit)
            }
        }
    }

    private func inlineProgressBar(_ habit: HabitState) -> some View {
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

    // MARK: - Manual Completion Button

    @ViewBuilder
    private func manualButton(_ habit: HabitState) -> some View {
        let accent = habit.accentColor
        let isDone = habit.todayCount >= habit.targetCount

        Button {
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
        } label: {
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

    // MARK: - Card Background

    @ViewBuilder
    private func cardBackground(accent: Color, isComplete: Bool) -> some View {
        if isComplete {
            ZStack {
                DS.surfaceElevated
                RadialGradient(
                    colors: [accent.opacity(0.06), Color.clear],
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: 160
                )
            }
        } else {
            DS.surfaceElevated
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

    // MARK: - Editor Popovers

    @ViewBuilder
    private func habitEditorPopover(_ habit: HabitDefinition) -> some View {
        CommandCenterHabitEditor(
            habit: habit,
            onSave: { draft in
                Task {
                    var updated = habit
                    updated.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    updated.icon = draft.icon
                    updated.accentColor = draft.accentColor
                    updated.dailyTargetCount = draft.dailyTargetCount
                    updated.keywordTriggers = draft.keywords
                    updated.mappedIntents = draft.mappedIntents.map(\.rawValue).sorted()
                    updated.allowManualCompletion = draft.allowManualCompletion
                    await viewModel.updateHabit(updated)
                }
            },
            onArchive: habit.isBuiltIn ? nil : {
                Task { await viewModel.archiveHabit(uuid: habit.id) }
            },
            onMoveUp: habit.isBuiltIn ? nil : {
                Task { await viewModel.moveHabit(uuid: habit.id, direction: -1) }
            },
            onMoveDown: habit.isBuiltIn ? nil : {
                Task { await viewModel.moveHabit(uuid: habit.id, direction: 1) }
            },
            onDisable: habit.isBuiltIn ? {
                Task {
                    await viewModel.setBuiltInHabitEnabled(id: habit.id, enabled: false)
                    editingHabit = nil
                }
            } : nil
        )
    }

    private var habitCreatePopover: some View {
        CommandCenterHabitEditor(habit: nil) { draft in
            Task {
                await viewModel.createHabit(
                    title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    icon: draft.icon,
                    accentColor: draft.accentColor,
                    dailyTargetCount: draft.dailyTargetCount,
                    keywordTriggers: draft.keywords,
                    mappedIntents: Array(draft.mappedIntents).sorted { $0.displayName < $1.displayName },
                    allowManualCompletion: draft.allowManualCompletion
                )
            }
        }
    }

    // MARK: - Settings Popover

    private var habitSettingsPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Manage Habits")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.text)
                Text("Toggle built-in habits on or off")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.textMuted)
            }

            VStack(spacing: 8) {
                ForEach(viewModel.builtInHabitToggles, id: \.definition.id) { item in
                    settingsToggleRow(item)
                }
            }

            Button {
                showingHabitSettings = false
            } label: {
                Text("Done")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.textSecondary)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .frame(width: 320)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DS.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
        .shadow(color: .black.opacity(0.05), radius: 32, y: 16)
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder
    private func settingsToggleRow(_ item: (definition: HabitDefinition, isEnabled: Bool)) -> some View {
        let accent = Color(hex: item.definition.accentColor)
        HStack(spacing: 10) {
            Image(systemName: item.definition.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(
                    accent.opacity(item.isEnabled ? 1 : 0.35),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            Text(item.definition.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(item.isEnabled ? DS.text : DS.textMuted)

            Spacer()

            Toggle("", isOn: Binding(
                get: { item.isEnabled },
                set: { newValue in
                    Task {
                        await viewModel.setBuiltInHabitEnabled(id: item.definition.id, enabled: newValue)
                    }
                }
            ))
            .toggleStyle(.switch)
            .tint(accent)
            .labelsHidden()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                        .foregroundColor(DS.textMuted)
                )

            Text("No habits yet")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.text)

            Text("Create a custom habit, map it to task intents or keywords, and let completed tasks feed it automatically.")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.textMuted)
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
