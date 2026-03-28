import SwiftUI

struct DashboardHabitPanel: View {
    @ObservedObject var viewModel: CommandCenterDashboardViewModel

    @State private var editingHabit: HabitDefinition?
    @State private var creatingHabit = false
    @State private var showingHabitSettings = false
    @State private var animateProgress = false
    @State private var bouncingHabitId: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader

            if viewModel.habits.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(viewModel.habits) { habit in
                            habitCard(habit)
                        }
                    }
                    .padding(.bottom, 6)
                }
            }
        }
        .task {
            await viewModel.loadHabits()
        }
        .onAppear {
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
        .popover(item: $editingHabit, attachmentAnchor: .rect(.bounds), arrowEdge: .leading) { habit in
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
        .popover(isPresented: $creatingHabit, attachmentAnchor: .rect(.bounds), arrowEdge: .leading) {
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
    }

    private var sectionHeader: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "repeat")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DS.textMuted)

                Text("HABITS")
                    .dsSectionLabel()
            }

            Spacer()

            Button {
                showingHabitSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 28, height: 28)
                    .background(DS.surface, in: Circle())
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
                .foregroundColor(DS.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(DS.surface, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func habitCard(_ habit: HabitState) -> some View {
        let accent = habit.accentColor
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: habit.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accent)
                    .frame(width: 30, height: 30)
                    .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(habit.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(DS.text)

                        if !habit.isBuiltIn {
                            Text("Custom")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(accent.opacity(0.12), in: Capsule())
                        }
                    }

                    Text("\(habit.todayCount)/\(habit.targetCount) today")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(habit.isTodayComplete ? accent : DS.textSecondary)
                }

                Spacer()

                if habit.allowManualComplete {
                    Button {
                        Task { await viewModel.recordManualHabitCompletion(habitUUID: habit.id) }
                        if !reduceMotion {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                                bouncingHabitId = habit.id
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                                    bouncingHabitId = nil
                                }
                            }
                        }
                    } label: {
                        Image(systemName: habit.isTodayComplete ? "checkmark" : "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(habit.todayCount >= habit.targetCount ? accent.opacity(0.55) : accent)
                            .frame(width: 28, height: 28)
                            .background(
                                habit.isTodayComplete ? accent.opacity(0.12) : DS.bg,
                                in: Circle()
                            )
                            .overlay(
                                Circle()
                                    .stroke(
                                        habit.isTodayComplete ? accent.opacity(0.18) : DS.borderSubtle,
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(bouncingHabitId == habit.id ? 1.2 : 1.0)
                    .disabled(habit.todayCount >= habit.targetCount)
                }
            }

            progressStrip(habit)

            HStack(spacing: 6) {
                statPill(
                    icon: "timer",
                    label: habit.trackedMinutesToday > 0 ? "\(habit.trackedMinutesToday)m tracked" : "No tracked time",
                    color: accent.opacity(habit.trackedMinutesToday > 0 ? 1 : 0.55)
                )

                if let sourceSummary = habit.sourceBreakdown.summaryText {
                    statPill(icon: "square.stack.3d.up", label: sourceSummary, color: DS.textSecondary)
                }
            }

            if let linkedIntentSummary = habit.linkedIntentSummary {
                statPill(icon: "wand.and.stars", label: linkedIntentSummary, color: accent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.borderSubtle, lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent.opacity(habit.isTodayComplete ? 0.85 : 0.45))
                .frame(width: 3)
                .padding(.vertical, 10)
                .padding(.leading, 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            if let definition = viewModel.habitDefinition(for: habit.id) {
                editingHabit = definition
            }
        }
    }

    private func progressStrip(_ habit: HabitState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(DS.borderSubtle)
                        .frame(height: 5)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(habit.accentColor.opacity(0.72))
                        .frame(width: proxy.size.width * (animateProgress ? habit.todayProgress : 0), height: 5)
                        .animation(
                            reduceMotion ? .none : .spring(response: 0.6, dampingFraction: 0.8).delay(0.1),
                            value: animateProgress
                        )
                }
            }
            .frame(height: 5)

            HStack(spacing: 5) {
                ForEach(Array(habit.last7Days.enumerated()), id: \.offset) { index, isComplete in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isComplete ? habit.accentColor.opacity(0.8) : DS.bg)
                        .frame(height: 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(index == 6 && !isComplete ? habit.accentColor.opacity(0.22) : .clear, lineWidth: 1)
                        )
                }
            }
        }
    }

    private func statPill(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(DS.bg, in: Capsule())
        .overlay(
            Capsule()
                .stroke(DS.borderSubtle, lineWidth: 1)
        )
    }

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
                                    await viewModel.setBuiltInHabitEnabled(
                                        id: item.definition.id,
                                        enabled: newValue
                                    )
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
