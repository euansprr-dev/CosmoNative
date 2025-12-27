// CosmoOS/Navigation/CommandPaletteModeIndicator.swift
// Mode indicator at bottom of Ctrl+K showing current mode with Tab hint

import SwiftUI

enum CommandHubMode {
    case library
    case inboxViews
}

struct CommandHubModeIndicator: View {
    let currentMode: CommandHubMode

    var body: some View {
        HStack(spacing: 32) {
            // Library tab
            ModeTab(
                title: "Library",
                isActive: currentMode == .library
            )

            // Separator dot
            Circle()
                .fill(CosmoColors.textTertiary.opacity(0.3))
                .frame(width: 3, height: 3)

            // Inbox Views tab
            ModeTab(
                title: "Inbox Views",
                isActive: currentMode == .inboxViews
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(
            Rectangle()
                .fill(CosmoColors.mistGrey.opacity(0.15))
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(CosmoColors.glassGrey.opacity(0.3))
                .frame(height: 1)
        }
    }
}

// MARK: - Mode Tab

struct ModeTab: View {
    let title: String
    let isActive: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isActive ? CosmoColors.textPrimary : CosmoColors.textTertiary.opacity(0.5))

            // Active indicator underline
            if isActive {
                Rectangle()
                    .fill(CosmoColors.textPrimary)
                    .frame(width: CGFloat(title.count) * 5, height: 2)
                    .transition(.scale)
            } else {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 1, height: 2)
            }
        }
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isActive)
    }
}
