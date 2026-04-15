// CosmoOS/Core/Components/CosmoKeyboardFooter.swift
// Keyboard navigation hint bar for list-type menus

import SwiftUI

struct CosmoKeyboardFooter: View {
    var selectLabel: String = "Select"

    var body: some View {
        HStack {
            Text("↑↓ Navigate")
                .font(.caption2)
                .foregroundStyle(DS.textMuted)
            Spacer()
            Text("↵ \(selectLabel)")
                .font(.caption2)
                .foregroundStyle(DS.textMuted)
            Text("⎋ Cancel")
                .font(.caption2)
                .foregroundStyle(DS.textMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(DS.surfaceElevated)
    }
}
