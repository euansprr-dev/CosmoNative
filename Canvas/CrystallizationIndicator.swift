// CosmoOS/Canvas/CrystallizationIndicator.swift
// Compact 5-dot indicator showing knowledge crystallization level
// February 2026 - Thinking Lab WP1

import SwiftUI

// MARK: - CrystallizationIndicator

/// A compact 5-dot horizontal row showing the crystallization level of a block.
/// Filled dots represent achieved levels, unfilled dots represent remaining.
/// Tapping cycles through levels (sets userOverride).
struct CrystallizationIndicator: View {
    let level: CrystallizationLevel
    let accentColor: Color
    var onLevelChange: ((CrystallizationLevel) -> Void)? = nil

    private let dotSize: CGFloat = 6
    private let dotSpacing: CGFloat = 3

    var body: some View {
        HStack(spacing: dotSpacing) {
            ForEach(0..<5) { index in
                Circle()
                    .fill(index <= level.rawValue ? accentColor : DS.borderActive)
                    .frame(width: dotSize, height: dotSize)
            }
        }
        .frame(height: dotSize)
        .contentShape(Rectangle())
        .onTapGesture {
            let nextRaw = (level.rawValue + 1) % (CrystallizationLevel.allCases.count + 1)
            // Cycling: 0->1->2->3->4->0 (back to raw clears override)
            if let nextLevel = CrystallizationLevel(rawValue: nextRaw % CrystallizationLevel.allCases.count) {
                onLevelChange?(nextLevel)
            }
        }
    }
}
