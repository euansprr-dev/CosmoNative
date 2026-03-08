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
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    ZStack {
                        Circle()
                            .fill(DS.surfaceElevated)
                            .frame(width: 22, height: 22)

                        Circle()
                            .fill(accentColor)
                            .frame(width: 18, height: 18)

                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(DS.textOnAccent)
                    }
                    .shadow(color: .black.opacity(0.10), radius: 4, y: 2)
                    .padding(8)
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
