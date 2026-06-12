import SwiftUI

// MARK: - Layout math

struct SwipeWaterfallLayout: Equatable {
    /// Frames in item order (waterfall: each item flows into the shortest column).
    let frames: [CGRect]
    let columnWidth: CGFloat
    let totalHeight: CGFloat

    static let empty = SwipeWaterfallLayout(frames: [], columnWidth: 0, totalHeight: 0)

    static func columnMetrics(
        availableWidth: CGFloat,
        targetColumnWidth: CGFloat,
        spacing: CGFloat,
        minColumns: Int = 2,
        maxColumns: Int = 5
    ) -> (count: Int, width: CGFloat) {
        guard availableWidth > 0 else { return (minColumns, 0) }
        let raw = Int((availableWidth + spacing) / (targetColumnWidth + spacing))
        let count = max(minColumns, min(maxColumns, raw))
        let width = ((availableWidth - spacing * CGFloat(count - 1)) / CGFloat(count)).rounded(.down)
        return (count, max(width, 0))
    }

    /// Pure arithmetic — O(n·columns), no view measurement, exact total height.
    static func compute(
        heights: [CGFloat],
        columnCount: Int,
        columnWidth: CGFloat,
        spacing: CGFloat
    ) -> SwipeWaterfallLayout {
        guard columnCount > 0, columnWidth > 0, !heights.isEmpty else { return .empty }

        var columnHeights = [CGFloat](repeating: 0, count: columnCount)
        var frames: [CGRect] = []
        frames.reserveCapacity(heights.count)

        for height in heights {
            var shortest = 0
            for column in 1..<columnCount where columnHeights[column] < columnHeights[shortest] {
                shortest = column
            }
            let x = CGFloat(shortest) * (columnWidth + spacing)
            let y = columnHeights[shortest]
            frames.append(CGRect(x: x, y: y, width: columnWidth, height: height))
            columnHeights[shortest] = y + height + spacing
        }

        let total = max(0, (columnHeights.max() ?? 0) - spacing)
        return SwipeWaterfallLayout(frames: frames, columnWidth: columnWidth, totalHeight: total)
    }
}

// MARK: - Visible band

/// The grid's visible slice in its own coordinates, quantized to coarse buckets so
/// scrolling only mutates state a few times per second — never per frame.
struct SwipeMasonryVisibleBand: Equatable {
    let minY: CGFloat
    let maxY: CGFloat

    static let bucket: CGFloat = 300

    static let everything = SwipeMasonryVisibleBand(minY: -.infinity, maxY: .infinity)

    /// Overscans one viewport above and below so fast flicks land on live cells.
    static func quantized(offsetInGrid: CGFloat, viewportHeight: CGFloat) -> SwipeMasonryVisibleBand {
        let lower = offsetInGrid - viewportHeight
        let upper = offsetInGrid + viewportHeight * 2
        return SwipeMasonryVisibleBand(
            minY: (lower / bucket).rounded(.down) * bucket,
            maxY: (upper / bucket).rounded(.up) * bucket
        )
    }

    func intersects(_ frame: CGRect) -> Bool {
        frame.maxY > minY && frame.minY < maxY
    }
}

// MARK: - Windowed waterfall grid

/// Virtualized masonry: precomputed frames, exact scroll extent, correct waterfall
/// order, and only the cells inside the visible band (±1 viewport) are live —
/// ~30–80 views regardless of item count. Must live inside a `ScrollView`.
struct SwipeWaterfallGrid<Item: Identifiable & Equatable, Cell: View>: View {
    let items: [Item]
    var targetColumnWidth: CGFloat = 252
    var spacing: CGFloat = 16
    var minColumns = 2
    var maxColumns = 5
    let itemHeight: (Item, CGFloat) -> CGFloat
    @ViewBuilder let cell: (Item, CGFloat, Int) -> Cell

    @State private var availableWidth: CGFloat = 0
    @State private var visibleBand = SwipeMasonryVisibleBand.everything

    var body: some View {
        let metrics = SwipeWaterfallLayout.columnMetrics(
            availableWidth: availableWidth,
            targetColumnWidth: targetColumnWidth,
            spacing: spacing,
            minColumns: minColumns,
            maxColumns: maxColumns
        )
        let layout = SwipeWaterfallLayout.compute(
            heights: items.map { itemHeight($0, metrics.width) },
            columnCount: metrics.count,
            columnWidth: metrics.width,
            spacing: spacing
        )

        ZStack(alignment: .topLeading) {
            ForEach(visibleEntries(layout)) { entry in
                cell(entry.item, layout.columnWidth, entry.index)
                    .frame(width: entry.frame.width, height: entry.frame.height, alignment: .topLeading)
                    .offset(x: entry.frame.minX, y: entry.frame.minY)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: layout.totalHeight > 0 ? layout.totalHeight : nil, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
            availableWidth = width
        }
        .onGeometryChange(for: SwipeMasonryVisibleBand.self, of: { proxy in
            let frame = proxy.frame(in: .scrollView)
            let viewportHeight = proxy.bounds(of: .scrollView)?.height ?? 1600
            return SwipeMasonryVisibleBand.quantized(offsetInGrid: -frame.minY, viewportHeight: viewportHeight)
        }) { band in
            visibleBand = band
        }
    }

    private func visibleEntries(_ layout: SwipeWaterfallLayout) -> [Entry] {
        guard !layout.frames.isEmpty else { return [] }
        var entries: [Entry] = []
        for (index, item) in items.enumerated() {
            let frame = layout.frames[index]
            if visibleBand.intersects(frame) {
                entries.append(Entry(item: item, index: index, frame: frame))
            }
        }
        return entries
    }

    private struct Entry: Identifiable {
        let item: Item
        let index: Int
        let frame: CGRect
        var id: Item.ID { item.id }
    }
}
