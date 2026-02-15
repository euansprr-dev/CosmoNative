// CosmoOS/Core/Onyx/OnyxProgressLine.swift
// Thin progress line — replaces all thick progress bars and gaming health bars.
// PRD Section 6.3: "2-3pt, rounded-cap progress lines"

import SwiftUI

/// A thin, rounded-cap progress line with optional subtle gradient.
/// Track is barely visible; fill uses dimension color at 60% with lighter leading edge.
struct OnyxProgressLine: View {
    var progress: Double
    var height: CGFloat
    var color: Color
    var trackColor: Color
    var animated: Bool

    @State private var animatedProgress: Double = 0

    init(
        progress: Double,
        height: CGFloat = OnyxLayout.progressLineHeight,
        color: Color = OnyxColors.Accent.iris,
        trackColor: Color = OnyxColors.Elevation.raised,
        animated: Bool = true
    ) {
        self.progress = max(0, min(1, progress))
        self.height = height
        self.color = color
        self.trackColor = trackColor
        self.animated = animated
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(trackColor)
                    .frame(height: height)

                // Fill with subtle gradient (lighter at leading edge)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                color.opacity(0.85),
                                color.opacity(0.60)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: max(0, geo.size.width * currentProgress),
                        height: height
                    )
            }
        }
        .frame(height: height)
        .onAppear {
            if animated {
                withAnimation(OnyxSpring.metricSettle) {
                    animatedProgress = progress
                }
            } else {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            let clamped = max(0, min(1, newValue))
            if animated {
                withAnimation(OnyxSpring.metricSettle) {
                    animatedProgress = clamped
                }
            } else {
                animatedProgress = clamped
            }
        }
    }

    private var currentProgress: Double {
        animated ? animatedProgress : progress
    }
}
