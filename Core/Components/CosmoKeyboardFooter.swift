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
                    .font(DS.keycap)
                    .foregroundStyle(darkMode ? Color.white.opacity(0.5) : DS.textMuted)
                Spacer()
                Text("↵ \(selectLabel)")
                    .font(DS.keycap)
                    .foregroundStyle(darkMode ? Color.white.opacity(0.5) : DS.textMuted)
                Text("⎋ Cancel")
                    .font(DS.keycap)
                    .foregroundStyle(darkMode ? Color.white.opacity(0.5) : DS.textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(darkMode ? Color.white.opacity(0.05) : DS.glassInputFill.opacity(0.24))
        }
    }
}
