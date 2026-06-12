import SwiftUI

/// Static loading placeholder matching the card silhouette — no shimmer, no
/// spinners (repeatForever opacity pulses were a measured scroll cost in the
/// June 2026 ProMotion pass).
struct SwipeCardSkeleton: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.glassSectionFill)
                .frame(height: max(60, height - 78))
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(DS.glassSectionFill)
                .frame(maxWidth: .infinity)
                .frame(height: 12)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(DS.glassSectionFill)
                .frame(width: width * 0.45, height: 12)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: width, height: height, alignment: .top)
        .swipeCardSurface()
        .accessibilityHidden(true)
    }
}

/// A full skeleton masonry used while a grid loads — same waterfall silhouette,
/// deterministic heights so it never jumps.
struct SwipeSkeletonGrid: View {
    var targetColumnWidth: CGFloat = 252
    var spacing: CGFloat = 16

    private static let heights: [CGFloat] = [300, 220, 270, 340, 240, 290, 210, 320, 260, 230]

    var body: some View {
        SwipeWaterfallGrid(
            items: Self.heights.enumerated().map { SkeletonSlot(id: "skeleton-\($0.offset)", height: $0.element) },
            targetColumnWidth: targetColumnWidth,
            spacing: spacing,
            itemHeight: { slot, _ in slot.height },
            cell: { slot, width, _ in
                SwipeCardSkeleton(width: width, height: slot.height)
            }
        )
    }

    private struct SkeletonSlot: Identifiable, Equatable {
        let id: String
        let height: CGFloat
    }
}
