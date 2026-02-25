// CosmoOS/UI/CommandK/CardSelectionOverlay.swift
// Shared selection overlay modifier for Command-K gallery cards
// Shows accent border + checkmark badge when a card is selected

import SwiftUI

// MARK: - CardSelectionOverlay Modifier

struct CardSelectionOverlay: ViewModifier {
    let isSelected: Bool
    var accentColor: Color = DS.accent

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(accentColor, lineWidth: isSelected ? 2 : 0)
                    .animation(ProMotionSprings.snappy, value: isSelected)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white, accentColor)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .padding(6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(ProMotionSprings.snappy, value: isSelected)
    }
}

// MARK: - View Extension

extension View {
    func cardSelectionOverlay(isSelected: Bool, accentColor: Color = DS.accent) -> some View {
        modifier(CardSelectionOverlay(isSelected: isSelected, accentColor: accentColor))
    }
}
