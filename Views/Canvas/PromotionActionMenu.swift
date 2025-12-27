// CosmoOS/Views/Canvas/PromotionActionMenu.swift
// Action menu for promoting uncommitted items

import SwiftUI

struct PromotionActionMenu: View {
    let onAction: (PromotionAction) -> Void
    @State private var hoveredAction: PromotionAction?

    var body: some View {
        VStack(spacing: 4) {
            // Expand Idea
            actionRow(
                action: .expandIdea,
                icon: "sparkles",
                label: "Expand Idea",
                color: CosmoColors.lavender
            )

            // Turn into Content
            actionRow(
                action: .turnIntoContent,
                icon: "doc.text.fill",
                label: "Turn into Content",
                color: CosmoColors.skyBlue
            )

            // Turn into Task
            actionRow(
                action: .turnIntoTask,
                icon: "checkmark.circle.fill",
                label: "Turn into Task",
                color: CosmoColors.coral
            )

            // Divider
            Divider()
                .background(CosmoColors.glassGrey.opacity(0.3))
                .padding(.vertical, 4)

            // Dismiss
            actionRow(
                action: .dismiss,
                icon: "trash.fill",
                label: "Dismiss",
                color: CosmoColors.coral.opacity(0.7)
            )
        }
        .padding(.vertical, 4)
        .frame(width: 180)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(CosmoColors.softWhite)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CosmoColors.glassGrey.opacity(0.5), lineWidth: 1)
        )
        .shadow(
            color: Color.black.opacity(0.15),
            radius: 16,
            x: 0,
            y: 4
        )
    }

    // MARK: - Action Row

    private func actionRow(
        action: PromotionAction,
        icon: String,
        label: String,
        color: Color
    ) -> some View {
        Button(action: { onAction(action) }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(color)
                    .frame(width: 16)

                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(CosmoColors.textPrimary)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hoveredAction == action ? CosmoColors.mistGrey.opacity(0.5) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                hoveredAction = hovering ? action : nil
            }
        }
    }
}
