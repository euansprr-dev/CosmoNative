// CosmoOS/Views/Canvas/AssignmentStatusGroupHeader.swift
// Group header for assignment status sections in inbox blocks

import SwiftUI

struct AssignmentStatusGroupHeader: View {
    let status: AssignmentStatus
    let count: Int
    @State private var isCollapsed = false

    var body: some View {
        HStack(spacing: 8) {
            // Status emoji
            Text(statusEmoji)
                .font(.system(size: 12))

            // Status label and count
            Text("\(statusLabel) (\(count))")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(CosmoColors.textSecondary)

            Spacer()

            // Collapse/expand arrow (optional enhancement)
            // Button(action: { isCollapsed.toggle() }) {
            //     Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
            //         .font(.system(size: 10, weight: .medium))
            //         .foregroundColor(CosmoColors.textTertiary)
            // }
            // .buttonStyle(.plain)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Status Properties

    private var statusEmoji: String {
        switch status {
        case .assigned:
            return "✅"
        case .suggested:
            return "🟡"
        case .unassigned:
            return "⚪"
        }
    }

    private var statusLabel: String {
        switch status {
        case .assigned:
            return "Assigned"
        case .suggested:
            return "Suggested"
        case .unassigned:
            return "Unassigned"
        }
    }

    private var statusColor: Color {
        switch status {
        case .assigned:
            return CosmoColors.emerald
        case .suggested:
            return Color(hex: "#B8860B")  // Warm Amber
        case .unassigned:
            return CosmoColors.glassGrey
        }
    }
}
