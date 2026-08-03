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
        band(offsetInGrid: offsetInGrid, viewportHeight: viewportHeight, above: 1, below: 2)
    }

    /// Cache-warm band. Reaches much further than the mount band so thumbnails
    /// are decoded and resident BEFORE their cell mounts — the mount band is
    /// where the image request used to start, which is why a fast flick
    /// outran the loader.
    static func prefetchQuantized(offsetInGrid: CGFloat, viewportHeight: CGFloat) -> SwipeMasonryVisibleBand {
        band(offsetInGrid: offsetInGrid, viewportHeight: viewportHeight, above: 2, below: 5)
    }

    private static func band(
        offsetInGrid: CGFloat,
        viewportHeight: CGFloat,
        above: CGFloat,
        below: CGFloat
    ) -> SwipeMasonryVisibleBand {
        let lower = offsetInGrid - viewportHeight * above
        let upper = offsetInGrid + viewportHeight * below
        return SwipeMasonryVisibleBand(
            minY: (lower / bucket).rounded(.down) * bucket,
            maxY: (upper / bucket).rounded(.up) * bucket
        )
    }

    func intersects(_ frame: CGRect) -> Bool {
        frame.maxY > minY && frame.minY < maxY
    }
}

/// The two bands the grid tracks, carried together so one `onGeometryChange`
/// serves both mounting and cache warming.
struct SwipeMasonryScrollBands: Equatable {
    let mount: SwipeMasonryVisibleBand
    let prefetch: SwipeMasonryVisibleBand

    static let everything = SwipeMasonryScrollBands(mount: .everything, prefetch: .everything)

    static func quantized(offsetInGrid: CGFloat, viewportHeight: CGFloat) -> SwipeMasonryScrollBands {
        SwipeMasonryScrollBands(
            mount: .quantized(offsetInGrid: offsetInGrid, viewportHeight: viewportHeight),
            prefetch: .prefetchQuantized(offsetInGrid: offsetInGrid, viewportHeight: viewportHeight)
        )
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
    /// Items entering the (much wider) prefetch band. Fires only when the
    /// quantized band changes — a few times per second of scrolling, never per
    /// frame. Purely for cache warming; these items are NOT mounted.
    var onPrefetch: (([Item]) -> Void)?
    @ViewBuilder let cell: (Item, CGFloat, Int) -> Cell

    @State private var availableWidth: CGFloat = 0
    // PRECONDITION: every SwipeWaterfallGrid lives inside a vertical
    // ScrollView, so the first real band arrives from onGeometryChange on the
    // first laid-out frame. Seeding a finite band (instead of `.everything`)
    // keeps the initial mount to ~one viewport of cells rather than the whole
    // dataset for one frame.
    @State private var bands = SwipeMasonryScrollBands.quantized(offsetInGrid: 0, viewportHeight: 900)
    /// Layout memo — plain reference so body can fill it without invalidating.
    @State private var layoutMemo = LayoutMemo()

    var body: some View {
        let metrics = SwipeWaterfallLayout.columnMetrics(
            availableWidth: availableWidth,
            targetColumnWidth: targetColumnWidth,
            spacing: spacing,
            minColumns: minColumns,
            maxColumns: maxColumns
        )
        let layout = cachedLayout(
            heights: items.map { itemHeight($0, metrics.width) },
            columnCount: metrics.count,
            columnWidth: metrics.width
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
        .onGeometryChange(for: SwipeMasonryScrollBands.self, of: { proxy in
            let frame = proxy.frame(in: .scrollView)
            let viewportHeight = proxy.bounds(of: .scrollView)?.height ?? 1600
            return SwipeMasonryScrollBands.quantized(offsetInGrid: -frame.minY, viewportHeight: viewportHeight)
        }) { next in
            bands = next
            emitPrefetch(layout, band: next.prefetch)
        }
        .onChange(of: items.count) { emitPrefetch(layout, band: bands.prefetch) }
    }

    /// Memoized `SwipeWaterfallLayout.compute` — the exact same call with the
    /// exact same inputs, skipped when nothing changed. A selection or hover
    /// re-runs body without re-running the O(n·columns) waterfall.
    private func cachedLayout(
        heights: [CGFloat],
        columnCount: Int,
        columnWidth: CGFloat
    ) -> SwipeWaterfallLayout {
        let memo = layoutMemo
        if memo.heights == heights, memo.columnCount == columnCount,
           memo.columnWidth == columnWidth, memo.spacing == spacing {
            return memo.layout
        }
        let layout = SwipeWaterfallLayout.compute(
            heights: heights,
            columnCount: columnCount,
            columnWidth: columnWidth,
            spacing: spacing
        )
        memo.heights = heights
        memo.columnCount = columnCount
        memo.columnWidth = columnWidth
        memo.spacing = spacing
        memo.layout = layout
        return layout
    }

    private final class LayoutMemo {
        var heights: [CGFloat] = []
        var columnCount = -1
        var columnWidth: CGFloat = -1
        var spacing: CGFloat = -1
        var layout = SwipeWaterfallLayout.empty
    }

    private func visibleEntries(_ layout: SwipeWaterfallLayout) -> [Entry] {
        guard !layout.frames.isEmpty else { return [] }
        var entries: [Entry] = []
        for (index, item) in items.enumerated() {
            let frame = layout.frames[index]
            if bands.mount.intersects(frame) {
                entries.append(Entry(item: item, index: index, frame: frame))
            }
        }
        return entries
    }

    /// Items in the prefetch band, in scroll order — the warmer takes a bounded
    /// head of this list, so order is what decides which ones win.
    private func emitPrefetch(_ layout: SwipeWaterfallLayout, band: SwipeMasonryVisibleBand) {
        guard let onPrefetch, !layout.frames.isEmpty else { return }
        var pending: [Item] = []
        for (index, item) in items.enumerated() where band.intersects(layout.frames[index]) {
            pending.append(item)
        }
        guard !pending.isEmpty else { return }
        onPrefetch(pending)
    }

    private struct Entry: Identifiable {
        let item: Item
        let index: Int
        let frame: CGRect
        var id: Item.ID { item.id }
    }
}
