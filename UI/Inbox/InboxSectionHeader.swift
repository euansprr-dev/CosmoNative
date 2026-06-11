// CosmoOS/UI/Inbox/InboxSectionHeader.swift
// Pinned ledger section header — small caps, hairline, Command Center grammar.
// June 2026 — Inbox Revamp

import SwiftUI

struct InboxSectionHeader: View {
    let title: String
    let itemCount: Int

    var body: some View {
        HStack(spacing: DS.space8) {
            Text(title.uppercased())
                .font(DS.caption.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(DS.textMuted)

            Text("\(itemCount)")
                .font(DS.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(DS.textMuted)

            Rectangle()
                .fill(DS.borderSubtle)
                .frame(height: 0.5)
        }
        .padding(.horizontal, DS.space16)
        .padding(.top, DS.space16)
        .padding(.bottom, DS.space6)
        .background(DS.bg.opacity(0.96))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(itemCount) capture\(itemCount == 1 ? "" : "s")")
    }
}
