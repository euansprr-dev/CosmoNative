// CosmoOS/Core/Onyx/OnyxWeekGrid.swift
// Week-day indicator grid — replaces colored fitness rings.
// PRD Section 4.4: "Small 6x6pt rounded squares" like GitHub contribution graph.

import SwiftUI

/// Status for a single day in the week grid.
enum OnyxDayStatus {
    /// No data / not tracked — barely visible
    case empty
    /// Partial completion — dimension color at 40%
    case partial
    /// Full completion — dimension color at 80%
    case complete
    /// Missed — rose at 40%
    case missed
}

/// A horizontal row of small rounded squares representing 7 days.
struct OnyxWeekGrid: View {
    let days: [OnyxDayStatus]
    var color: Color
    var squareSize: CGFloat
    var labels: [String]

    init(
        days: [OnyxDayStatus],
        color: Color = OnyxColors.Accent.iris,
        squareSize: CGFloat = OnyxLayout.weekSquareSize,
        labels: [String] = ["M", "T", "W", "T", "F", "S", "S"]
    ) {
        self.days = days
        self.color = color
        self.squareSize = squareSize
        self.labels = labels
    }

    var body: some View {
        VStack(spacing: 4) {
            // Day labels
            HStack(spacing: daySpacing) {
                ForEach(Array(labels.prefix(7).enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(OnyxTypography.micro)
                        .foregroundColor(OnyxColors.Text.muted)
                        .frame(width: squareSize)
                }
            }

            // Status squares
            HStack(spacing: daySpacing) {
                ForEach(Array(paddedDays.enumerated()), id: \.offset) { index, status in
                    RoundedRectangle(cornerRadius: squareSize * 0.25)
                        .fill(fillColor(for: status))
                        .frame(width: squareSize, height: squareSize)
                        .animation(
                            OnyxSpring.staggered(index: index),
                            value: status == .complete || status == .partial
                        )
                }
            }
        }
    }

    // MARK: - Helpers

    /// Ensure we always have exactly 7 entries.
    private var paddedDays: [OnyxDayStatus] {
        let capped = Array(days.prefix(7))
        if capped.count >= 7 { return capped }
        return capped + Array(repeating: OnyxDayStatus.empty, count: 7 - capped.count)
    }

    private var daySpacing: CGFloat {
        squareSize * 1.2
    }

    private func fillColor(for status: OnyxDayStatus) -> Color {
        switch status {
        case .empty:
            return OnyxColors.Elevation.elevated
        case .partial:
            return color.opacity(0.40)
        case .complete:
            return color.opacity(0.80)
        case .missed:
            return OnyxColors.Accent.rose.opacity(0.40)
        }
    }
}
