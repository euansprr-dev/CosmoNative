// CosmoOS/UI/FocusMode/SwipeStudy/PhysicsFabricView.swift
// Deep fabric synthesis — the soul of the analysis, beautifully typeset

import SwiftUI

struct PhysicsFabricView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            Text("THE FABRIC")
                .font(DS.caption)
                .tracking(1.2)
                .foregroundStyle(DS.textMuted)

            Text(text)
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .lineSpacing(6)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DS.space20)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(DS.entitySwipe)
                .frame(width: 3)
        }
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusMedium).stroke(DS.border, lineWidth: 1))
    }
}
