// CosmoOS/UI/Plannerum/Components/DailyPlanningView.swift
// Planning mode overlay — "Plan Your Day" prompt when no blocks exist

import SwiftUI

// MARK: - DAILY PLANNING VIEW

/// Planning mode overlay shown when the day has no scheduled blocks.
/// Offers auto-plan from unscheduled tasks and external calendar context.
public struct DailyPlanningView: View {

    // MARK: - Properties

    let externalEventCount: Int
    let unscheduledTasks: [TaskViewModel]
    let onAutoPlan: () -> Void
    let onShowUnscheduledTray: () -> Void

    // MARK: - Body

    public var body: some View {
        VStack(spacing: PlannerumLayout.spacingLG) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 32))
                .foregroundColor(PlannerumColors.primary.opacity(0.6))

            VStack(spacing: 4) {
                Text("Plan Your Day")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(PlannerumColors.textPrimary)

                Text("No blocks scheduled. Drag on the timeline to create, or auto-plan from your tasks.")
                    .font(.system(size: 12))
                    .foregroundColor(PlannerumColors.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            // External events hint
            if externalEventCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                    Text("\(externalEventCount) external events loaded")
                        .font(.system(size: 11))
                }
                .foregroundColor(PlannerumColors.textTertiary)
            }

            HStack(spacing: PlannerumLayout.spacingMD) {
                // Auto-plan button
                Button(action: onAutoPlan) {
                    HStack(spacing: 6) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 12))
                        Text("Auto-Plan")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(PlannerumColors.primary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                // Show tray button
                if !unscheduledTasks.isEmpty {
                    Button(action: onShowUnscheduledTray) {
                        HStack(spacing: 6) {
                            Image(systemName: "tray.full.fill")
                                .font(.system(size: 12))
                            Text("\(unscheduledTasks.count) unscheduled")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(PlannerumColors.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, PlannerumLayout.spacingXL)
        .frame(maxWidth: .infinity)
    }
}
