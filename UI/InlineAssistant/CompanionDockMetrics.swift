import SwiftUI
import Observation

/// The companion owns the window's bottom-trailing corner on every page.
/// Chrome that also lives there (canvas zoom controls, panel tails) reads
/// its footprint here and keeps clear — the companion never moves.
@MainActor @Observable
final class CompanionDockMetrics {
    static let shared = CompanionDockMetrics()

    /// The launcher's measured size; zero while the dock is hidden.
    var footprint: CGSize = .zero

    /// How far from the trailing edge bottom-trailing chrome must stop.
    var trailingClearance: CGFloat {
        footprint.width > 0 ? footprint.width + DS.space16 + DS.space12 : 0
    }

    /// How far from the bottom edge scrolling content should end.
    var bottomClearance: CGFloat {
        footprint.height > 0 ? footprint.height + DS.space16 + DS.space12 : 0
    }
}

/// Pads bottom-trailing chrome past the companion. Observes the metrics
/// alone, so the host's body never re-evaluates for a dock change.
struct CompanionCornerClearance<Content: View>: View {
    var basePadding: CGFloat = 0
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var metrics: CompanionDockMetrics { .shared }

    var body: some View {
        let clearance = max(basePadding, metrics.trailingClearance)
        content()
            .padding(.trailing, clearance)
            .animation(reduceMotion ? nil : ProMotionSprings.gentle, value: clearance)
    }
}
