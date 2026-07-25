// Canvas/CommandCenter/TaskReorderGeometry.swift
// The pure geometry of a live task reorder — the slot the lifted row currently
// owns, the step-aside offset every sibling takes, and the destination index a
// release commits. No SwiftUI, no state: all of it is a function of the band's
// HOME row centres and how far the lifted row has travelled.
// July 2026

import CoreGraphics

/// Live-reorder math for a band of task rows (the iOS Today lift, ported).
///
/// Every test is made against HOME centres — the row positions frozen the
/// instant a row lifts — never the live, already-offset frames. Measuring
/// against moving frames double-counts the pointer: the sibling that steps
/// aside moves the very boundary it was judged by, so the pair oscillates
/// under a still hand. (The iOS lesson: `TodayView.rowFrames` freezes for
/// exactly this reason.)
enum TaskReorderGeometry {

    /// How far past a boundary the lifted row travels before it takes the next
    /// slot — and how far back before it gives it up. Without this margin a row
    /// resting on a neighbour's centre flickers between two slots on a one-pixel
    /// mouse tremor, and the whole band buzzes.
    static let hysteresis: CGFloat = 5

    /// The slot the lifted row currently occupies, walked from the slot it held
    /// last frame. Walking (rather than recomputing from scratch) is what makes
    /// the hysteresis directional: the margin is spent leaving a slot, not
    /// re-derived from the pointer every frame.
    ///
    /// - Parameters:
    ///   - currentSlot: the slot from the previous frame (the lifted row's own
    ///     index on the first frame of a lift).
    ///   - liftedIndex: the lifted row's home index in the band.
    ///   - homeCentres: every band row's home centre, in band order.
    ///   - draggedCentre: the lifted row's centre right now (home centre +
    ///     pointer travel + any autoscroll the drag caused).
    static func slot(
        currentSlot: Int,
        liftedIndex: Int,
        homeCentres: [CGFloat],
        draggedCentre: CGFloat,
        hysteresis: CGFloat = hysteresis
    ) -> Int {
        guard homeCentres.count > 1,
              homeCentres.indices.contains(liftedIndex) else { return liftedIndex }

        var slot = min(max(currentSlot, 0), homeCentres.count - 1)

        while let boundary = downwardBoundary(slot: slot, liftedIndex: liftedIndex, homeCentres: homeCentres),
              draggedCentre > boundary + hysteresis {
            slot += 1
        }
        while let boundary = upwardBoundary(slot: slot, liftedIndex: liftedIndex, homeCentres: homeCentres),
              draggedCentre < boundary - hysteresis {
            slot -= 1
        }
        return slot
    }

    /// The centre the lifted row must clear to fall one slot further down.
    ///
    /// Below its home slot that is the next row down (`slot + 1`). Above it, the
    /// row it has to give back is the one currently displaced downward — the row
    /// sitting at `slot` itself. Using `slot + 1` in both directions would make
    /// the hysteresis asymmetric by a whole row height: the row would swap after
    /// half a row of travel and refuse to swap back for a full one.
    private static func downwardBoundary(slot: Int, liftedIndex: Int, homeCentres: [CGFloat]) -> CGFloat? {
        let index = slot < liftedIndex ? slot : slot + 1
        guard homeCentres.indices.contains(index) else { return nil }
        return homeCentres[index]
    }

    /// The mirror of `downwardBoundary`: below the home slot the row to give
    /// back is the one at `slot`; at or above it, the next row up.
    private static func upwardBoundary(slot: Int, liftedIndex: Int, homeCentres: [CGFloat]) -> CGFloat? {
        let index = slot > liftedIndex ? slot : slot - 1
        guard homeCentres.indices.contains(index) else { return nil }
        return homeCentres[index]
    }

    /// The vertical offset the row at `index` takes while the lifted row owns
    /// `slot`. Siblings step aside by exactly the height of the hole the lifted
    /// row left — their own heights never enter it, which is why bands of mixed
    /// one- and two-line rows stay gap-free.
    static func offset(index: Int, liftedIndex: Int, slot: Int, liftedHeight: CGFloat) -> CGFloat {
        guard index != liftedIndex else { return 0 }
        if slot > liftedIndex, index > liftedIndex, index <= slot { return -liftedHeight }
        if slot < liftedIndex, index >= slot, index < liftedIndex { return liftedHeight }
        return 0
    }

    /// `Array.move(fromOffsets:toOffset:)` counts the destination *before* the
    /// element is removed, so a downward move lands one index later than the
    /// slot it is aiming at.
    static func moveOffset(from: Int, to: Int) -> Int {
        to > from ? to + 1 : to
    }

    /// The band order after a committed slot change — the same result as
    /// `move(fromOffsets:toOffset:)`, in a form that can be reasoned about (and
    /// tested) without an `IndexSet`.
    static func reordered<Element>(_ elements: [Element], from: Int, to: Int) -> [Element] {
        guard elements.indices.contains(from), elements.indices.contains(to), from != to else { return elements }
        var next = elements
        let moved = next.remove(at: from)
        next.insert(moved, at: to)
        return next
    }

    /// Rearranges only the rows named in `orderedIDs`, permuting them among the
    /// slots they already occupy. Anything not named — another heading's tasks, a
    /// completed row the view filtered out — keeps its position.
    ///
    /// This is what lets a view hand over the band it actually DREW, by id,
    /// instead of indices into an array it never saw. Indices from a filtered
    /// subset address the wrong task; ids cannot.
    static func permuted<Element: Identifiable>(_ all: [Element], to orderedIDs: [Element.ID]) -> [Element] {
        let members = Set(orderedIDs)
        guard !members.isEmpty else { return all }
        let byID = Dictionary(all.filter { members.contains($0.id) }.map { ($0.id, $0) }) { first, _ in first }
        var arranged = orderedIDs.compactMap { byID[$0] }.makeIterator()
        return all.map { members.contains($0.id) ? (arranged.next() ?? $0) : $0 }
    }
}
