// CosmoOS/UI/FocusMode/SwipeStudy/PhysicsSectionCardView.swift
// Reusable expandable card wrapper for physics section grid

import SwiftUI

struct PhysicsSectionCardView<Preview: View, Detail: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    let summary: String
    let isExpanded: Bool
    let onTap: () -> Void
    @ViewBuilder let preview: () -> Preview
    @ViewBuilder let detail: () -> Detail

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            cardContent
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(title), \(summary)")
        .accessibilityHint(isExpanded ? "Double-tap to collapse" : "Double-tap to expand")
    }

    @ViewBuilder
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            headerRow
            summaryText
            preview()
        }
        .padding(DS.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .stroke(isExpanded ? iconColor.opacity(0.4) : DS.border, lineWidth: isExpanded ? 1.5 : 1)
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(ProMotionSprings.hover, value: isHovered)
    }

    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: DS.space6) {
            Image(systemName: icon)
                .font(DS.callout)
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)

            Text(title)
                .font(DS.headline)
                .foregroundStyle(DS.text)

            Spacer()

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var summaryText: some View {
        Text(summary)
            .font(DS.caption)
            .foregroundStyle(DS.textMuted)
            .lineLimit(1)
    }
}
