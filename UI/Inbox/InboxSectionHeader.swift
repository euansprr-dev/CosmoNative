// CosmoOS/UI/Inbox/InboxSectionHeader.swift
// Sticky section header for temporal grouping (Today, Yesterday, etc.)
// March 2026

import SwiftUI

struct InboxSectionHeader: View {
    let title: String
    let itemCount: Int

    var body: some View {
        HStack(spacing: DS.space8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.textMuted)
                .tracking(0.8)

            Text("\(itemCount)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DS.textMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(DS.surface, in: Capsule())

            Spacer()
        }
        .padding(.horizontal, DS.space24)
        .padding(.vertical, DS.space8)
        .background(DS.bg.opacity(0.95))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DS.borderSubtle)
                .frame(height: 1)
        }
    }
}
