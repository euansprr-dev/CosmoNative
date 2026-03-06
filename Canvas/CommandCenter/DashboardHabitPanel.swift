// Canvas/CommandCenter/DashboardHabitPanel.swift
// Forgiving habit tracking panel — "X of last 7 days" with dot grid
// Reframes QuestEngine quests as habits
// March 2026

import SwiftUI

struct DashboardHabitPanel: View {

    @ObservedObject var viewModel: CommandCenterDashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader

            if viewModel.habits.isEmpty {
                emptyState
            } else {
                habitCards
            }
        }
    }

    // MARK: - Header

    private var sectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "repeat")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(DS.textMuted)

            Text("HABITS")
                .dsSectionLabel()
        }
    }

    // MARK: - Habit Cards

    private var habitCards: some View {
        VStack(spacing: 6) {
            ForEach(viewModel.habits) { habit in
                habitCard(habit)
            }
        }
    }

    @ViewBuilder
    private func habitCard(_ habit: HabitState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Icon
                Image(systemName: habit.iconName)
                    .font(.system(size: 11))
                    .foregroundColor(habit.isTodayComplete ? habit.accentColor : DS.textMuted)

                // Title
                Text(habit.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.text)

                Spacer()

                // Consistency label
                Text("\(habit.consistencyCount)/7 days")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(consistencyColor(habit.consistencyCount))
            }

            HStack(spacing: 4) {
                // 7-day dot grid
                dotGrid(habit)

                Spacer()

                // Today's progress + manual complete button
                if !habit.isTodayComplete && habit.allowManualComplete {
                    Button {
                        manualComplete(habit)
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 14))
                            .foregroundColor(DS.textMuted)
                    }
                    .buttonStyle(.plain)
                } else if habit.isTodayComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(habit.accentColor)
                }
            }

            // Today's progress bar (if not complete)
            if !habit.isTodayComplete && habit.todayProgress > 0 {
                progressBar(habit)
            }
        }
        .padding(10)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DS.borderSubtle, lineWidth: 1)
        )
    }

    // MARK: - Dot Grid

    @ViewBuilder
    private func dotGrid(_ habit: HabitState) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<7, id: \.self) { index in
                let isCompleted = habit.last7Days[index]
                let isToday = index == 6

                Circle()
                    .fill(dotColor(completed: isCompleted, isToday: isToday, accentColor: habit.accentColor))
                    .frame(width: 8, height: 8)
                    .overlay {
                        if isToday && !isCompleted {
                            Circle()
                                .stroke(habit.accentColor.opacity(0.3), lineWidth: 1)
                        }
                    }
            }
        }
    }

    private func dotColor(completed: Bool, isToday: Bool, accentColor: Color) -> Color {
        if completed {
            return accentColor
        }
        if isToday {
            return Color.clear
        }
        return DS.border
    }

    // MARK: - Progress Bar

    private func progressBar(_ habit: HabitState) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(DS.surface)
                    .frame(height: 3)

                RoundedRectangle(cornerRadius: 2)
                    .fill(habit.accentColor.opacity(0.5))
                    .frame(width: geo.size.width * habit.todayProgress, height: 3)
            }
        }
        .frame(height: 3)
    }

    // MARK: - Consistency Color

    private func consistencyColor(_ count: Int) -> Color {
        if count >= 6 { return DS.green }
        if count >= 4 { return DS.accent }
        if count >= 2 { return DS.textSecondary }
        return DS.textMuted
    }

    // MARK: - Manual Complete

    private func manualComplete(_ habit: HabitState) {
        // Trigger manual quest completion via QuestEngine
        let questEngine = PlannerumViewModel.shared.liveQuestEngine
        Task {
            await questEngine.manualComplete(questId: habit.id)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "repeat")
                .font(.system(size: 20, weight: .light))
                .foregroundColor(DS.textMuted)

            Text("Habits loading...")
                .font(.system(size: 11))
                .foregroundColor(DS.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}
