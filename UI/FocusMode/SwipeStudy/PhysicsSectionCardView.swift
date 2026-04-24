// CosmoOS/UI/FocusMode/SwipeStudy/PhysicsSectionCardView.swift
// Reusable expandable marginalia row for physics sections

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
        HStack(alignment: .center, spacing: DS.space10) {
            Image(systemName: icon)
                .font(DS.caption)
                .foregroundStyle(iconColor)
                .frame(width: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DS.space4) {
                headerRow
                summaryText
            }

            Spacer(minLength: DS.space8)

            preview()

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
        }
        .padding(.vertical, DS.space8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isExpanded ? iconColor.opacity(0.28) : DS.sepiaSubtle)
                .frame(height: 0.5)
        }
        .opacity(isHovered ? 0.82 : 1.0)
        .animation(ProMotionSprings.hover, value: isHovered)
    }

    @ViewBuilder
    private var headerRow: some View {
        Text(title.lowercased())
            .font(DS.callout)
            .foregroundStyle(DS.text)
            .lineLimit(1)
    }

    @ViewBuilder
    private var summaryText: some View {
        Text(summary)
            .font(DS.caption)
            .foregroundStyle(DS.textMuted)
            .lineLimit(1)
    }
}
