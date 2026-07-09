// CosmoOS/Canvas/CanvasClusterLayoutResolver.swift
// Deterministic cluster separation for AI-organized canvases.
//
// The organize plan decides SEMANTICS (which blocks belong together); geometry
// is never the model's job. Clusters derive their region from wherever their
// member blocks already sit, so grouping scattered blocks routinely produces
// overlapping cluster regions. This resolver keeps every cluster as close to
// its current position as possible while guaranteeing that no two regions
// overlap (with a breathing gutter): iterative pairwise push-apart along the
// minimum-overlap axis, with a shelf-packing fallback if the relaxation cannot
// converge. Pure geometry — same input, same output, fully unit-testable.

import Foundation

enum CanvasClusterLayoutResolver {
    struct Box {
        let id: UUID
        var rect: CGRect
        /// Fixed boxes (Command Center zones) are obstacles: they push movable
        /// clusters but never move themselves.
        var isFixed: Bool = false
    }

    static let defaultGutter: CGFloat = 48
    private static let separationEpsilon: CGFloat = 1
    private static let maxIterations = 128

    /// Displacements that make every movable box non-overlapping (gutter
    /// included). Boxes that don't need to move are absent from the result.
    static func displacements(
        for boxes: [Box],
        gutter: CGFloat = CanvasClusterLayoutResolver.defaultGutter
    ) -> [UUID: CGSize] {
        guard boxes.count > 1 else { return [:] }

        // Deterministic processing order regardless of caller ordering.
        var working = boxes.sorted { $0.id.uuidString < $1.id.uuidString }
        let originals = Dictionary(uniqueKeysWithValues: working.map { ($0.id, $0.rect.origin) })

        for _ in 0..<maxIterations {
            var moved = false
            for i in working.indices {
                for j in working.indices where j > i {
                    guard !(working[i].isFixed && working[j].isFixed) else { continue }
                    let a = working[i].rect.insetBy(dx: -gutter / 2, dy: -gutter / 2)
                    let b = working[j].rect.insetBy(dx: -gutter / 2, dy: -gutter / 2)
                    guard a.intersects(b) else { continue }

                    moved = true
                    let overlapX = min(a.maxX, b.maxX) - max(a.minX, b.minX) + separationEpsilon
                    let overlapY = min(a.maxY, b.maxY) - max(a.minY, b.minY) + separationEpsilon

                    if overlapX <= overlapY {
                        // Push apart horizontally; the box whose center sits
                        // further right moves right (array order breaks ties).
                        let jGoesPositive = b.midX >= a.midX
                        push(&working, i: i, j: j, delta: CGSize(width: overlapX, height: 0), jPositive: jGoesPositive)
                    } else {
                        let jGoesPositive = b.midY >= a.midY
                        push(&working, i: i, j: j, delta: CGSize(width: 0, height: overlapY), jPositive: jGoesPositive)
                    }
                }
            }
            if !moved { break }
        }

        // Relaxation can theoretically thrash in pathological arrangements —
        // guarantee the contract with a shelf-packing fallback.
        if hasMovableOverlap(working, gutter: gutter) {
            shelfPack(&working, gutter: gutter)
        }

        var result: [UUID: CGSize] = [:]
        for box in working where !box.isFixed {
            guard let original = originals[box.id] else { continue }
            let delta = CGSize(width: box.rect.origin.x - original.x, height: box.rect.origin.y - original.y)
            if abs(delta.width) > 0.5 || abs(delta.height) > 0.5 {
                result[box.id] = delta
            }
        }
        return result
    }

    /// Whether any pair (involving at least one movable box) still overlaps
    /// once the gutter is honored.
    static func hasMovableOverlap(_ boxes: [Box], gutter: CGFloat) -> Bool {
        for i in boxes.indices {
            for j in boxes.indices where j > i {
                guard !(boxes[i].isFixed && boxes[j].isFixed) else { continue }
                // Strictly-inside check: inset slightly less than the full
                // half-gutter so exact gutter spacing doesn't read as overlap.
                let inset = -(gutter / 2 - separationEpsilon)
                if boxes[i].rect.insetBy(dx: inset, dy: inset)
                    .intersects(boxes[j].rect.insetBy(dx: inset, dy: inset)) {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Pairwise push

    private static func push(
        _ boxes: inout [Box],
        i: Int,
        j: Int,
        delta: CGSize,
        jPositive: Bool
    ) {
        let sign: CGFloat = jPositive ? 1 : -1
        if boxes[i].isFixed {
            boxes[j].rect.origin.x += delta.width * sign
            boxes[j].rect.origin.y += delta.height * sign
        } else if boxes[j].isFixed {
            boxes[i].rect.origin.x -= delta.width * sign
            boxes[i].rect.origin.y -= delta.height * sign
        } else {
            boxes[i].rect.origin.x -= delta.width * sign / 2
            boxes[i].rect.origin.y -= delta.height * sign / 2
            boxes[j].rect.origin.x += delta.width * sign / 2
            boxes[j].rect.origin.y += delta.height * sign / 2
        }
    }

    // MARK: - Shelf-packing fallback

    /// Rebuilds the movable boxes into gutter-spaced rows anchored at the
    /// arrangement's original top-left. Loses fine positioning but keeps the
    /// no-overlap contract absolute.
    private static func shelfPack(_ boxes: inout [Box], gutter: CGFloat) {
        let movableIndices = boxes.indices.filter { !boxes[$0].isFixed }
        guard !movableIndices.isEmpty else { return }

        let anchorX = movableIndices.map { boxes[$0].rect.minX }.min() ?? 0
        let anchorY = movableIndices.map { boxes[$0].rect.minY }.min() ?? 0
        let totalWidth = movableIndices.reduce(CGFloat(0)) { $0 + boxes[$1].rect.width + gutter }
        let rowWidthCap = max(1600, totalWidth / 2)

        // Reading order of the original arrangement, id tie-broken.
        let ordered = movableIndices.sorted { lhs, rhs in
            let a = boxes[lhs].rect
            let b = boxes[rhs].rect
            if abs(a.minY - b.minY) > 1 { return a.minY < b.minY }
            if abs(a.minX - b.minX) > 1 { return a.minX < b.minX }
            return boxes[lhs].id.uuidString < boxes[rhs].id.uuidString
        }

        var cursorX = anchorX
        var cursorY = anchorY
        var rowHeight: CGFloat = 0
        for index in ordered {
            let size = boxes[index].rect.size
            if cursorX > anchorX, cursorX + size.width > anchorX + rowWidthCap {
                cursorX = anchorX
                cursorY += rowHeight + gutter
                rowHeight = 0
            }
            boxes[index].rect.origin = CGPoint(x: cursorX, y: cursorY)
            cursorX += size.width + gutter
            rowHeight = max(rowHeight, size.height)
        }
    }
}
