// CosmoOS/UI/Pipeline/ClientObjectPill.swift
// A client as a thing with identity — elevated surface, soft shadow, emoji
// or colour-dot mark. Selection is the app's one selection language (tint
// wash + hairline, never a solid fill). Shared by Ideas, the Pipeline and
// the client hub so a client looks the same in every room.

import SwiftUI

struct ClientObjectPill: View {
    let name: String
    let tint: Color
    let isSelected: Bool
    var count: Int? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        let identity = CollectionEmoji.resolve(name: name, matchKeywords: false)
        Button(action: action) {
            HStack(spacing: DS.space8) {
                mark(identity.emoji)
                Text(identity.label)
                    .font(DS.callout.weight(.medium))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                if let count {
                    Text("\(count)")
                        .font(DS.caption2.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(DS.textMuted)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, DS.space16)
            .frame(height: 34)
            .background(isSelected ? AnyShapeStyle(tint.opacity(0.14)) : AnyShapeStyle(DS.surfaceElevated))
            .clipShape(.capsule)
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? tint.opacity(0.42) : DS.commandChromeBorder,
                    lineWidth: isSelected ? 1 : 0.5
                )
            )
            .shadow(color: .black.opacity(isSelected ? 0 : 0.07), radius: 5, y: 2)
            .contentShape(.capsule)
        }
        .buttonStyle(IdeaCardPressStyle())
        .scaleEffect(isHovered ? 1.02 : 1)
        .animation(ProMotionSprings.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .help(isSelected ? "Back to everyone" : identity.label)
        .accessibilityLabel(identity.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func mark(_ emoji: String?) -> some View {
        if let emoji {
            Text(emoji)
                .font(DS.subheadline)
        } else {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
        }
    }
}
