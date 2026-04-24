// CosmoOS/Core/Components/CosmoKeyboardFooter.swift
// Keyboard navigation hint bar for list-type menus

import SwiftUI

struct CosmoKeyboardFooter: View {
    var selectLabel: String = "Select"
    var darkMode: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(darkMode ? Color.white.opacity(0.06) : DS.sepiaBorder.opacity(0.7))
                .frame(height: 1)

            HStack {
                Text("↑↓ Navigate")
                    .font(.caption2)
                    .foregroundStyle(darkMode ? Color.white.opacity(0.5) : DS.textMuted)
                Spacer()
                Text("↵ \(selectLabel)")
                    .font(.caption2)
                    .foregroundStyle(darkMode ? Color.white.opacity(0.5) : DS.textMuted)
                Text("⎋ Cancel")
                    .font(.caption2)
                    .foregroundStyle(darkMode ? Color.white.opacity(0.5) : DS.textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(darkMode ? DS.bg : DS.vellum)
        }
    }
}
