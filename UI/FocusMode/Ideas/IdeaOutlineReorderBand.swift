// CosmoOS/UI/FocusMode/Ideas/IdeaOutlineReorderBand.swift
// The Idea Focus outline reorders live under the pointer. Hover a slide and
// its numeral yields to a grip; pull the grip and the row itself lifts off
// the paper — no floating ghost — while its siblings step aside in real time.
// Release and the row settles into the slot it is already standing in, the
// numerals renumber, and ⌘Z puts it back.
//
// The maths is TaskReorderGeometry, unchanged: every test is against HOME
// centres frozen at pickup, siblings step aside by the hole the lifted row
// left, and the array moves once, on release, inside the settle animation.
// The band never mutates the outline mid-drag — rows carry transform offsets,
// so ForEach identity (and the NSTextView inside each row) never churns.
//
// Why not `.draggable`/`.onMove`: a system drag can't reorder live (the row
// sits still under a floating ghost), and its insertion indicator disagrees
// with the index it commits. TaskReorderBand learned this in July 2026.
// September 2026

import SwiftUI

/// What a row needs from the band: whether it is the one airborne, whether
/// any row is, and the grip it lifts by.
struct OutlineReorderHandle {
    let isLifted: Bool
    let isAnyLifted: Bool
    fileprivate let onChanged: (DragGesture.Value) -> Void
    fileprivate let onEnded: () -> Void
}

extension View {
    /// Makes this view the grip a band row lifts by. Apply it to the gutter
    /// glyph — never to the row, whose text editor owns the pointer there.
    /// A 4pt pull lifts; a click on the grip does nothing at all.
    func outlineReorderGrip(_ handle: OutlineReorderHandle) -> some View {
        self
            .contentShape(Rectangle())
            .pointerStyle(handle.isLifted ? .grabActive : .grabIdle)
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named(OutlineReorderBandSpace.name))
                    .onChanged(handle.onChanged)
                    .onEnded { _ in handle.onEnded() }
            )
    }
}

enum OutlineReorderBandSpace {
    static let name = "idea-outline-reorder"
}

struct OutlineReorderBand<Item: Identifiable, Row: View>: View {

    let items: [Item]
    /// The VStack spacing between rows — part of the hole a lifted row leaves.
    let spacing: CGFloat
    /// Commit a slot change. Indices are into `items`.
    let onReorder: (_ from: Int, _ to: Int) -> Void
    @ViewBuilder let row: (Item, OutlineReorderHandle) -> Row

    @State private var lift: Lift?
    /// Heights, never frames — a frame measured mid-drag reports the row's
    /// offset position and feeds straight back into the offsets that made it.
    @State private var rowHeights: [Item.ID: CGFloat] = [:]
    /// The band's top in screen space. A wheel scroll during a lift moves the
    /// content under a still hand; this keeps the row under the pointer.
    @State private var screenTop = OutlineBandScreenTop()
    /// The just-released row, still gliding: keeps its zIndex through the
    /// settle so it never dives under the rows it is passing.
    @State private var settlingID: Item.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Lift {
        let id: Item.ID
        let index: Int
        let height: CGFloat
        let homeCentres: [CGFloat]
        let liftScreenTop: CGFloat
        var translation: CGFloat = 0
        var scrollDelta: CGFloat = 0
        var slot: Int

        var travel: CGFloat { translation + scrollDelta }
        var centre: CGFloat {
            (homeCentres.indices.contains(index) ? homeCentres[index] : 0) + travel
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                bandRow(item, at: index)
            }
        }
        // A committed reorder rides the SAME spring the released row's offset
        // unwinds with, so its landing reads as one motion — and a slide
        // added or removed glides its neighbours instead of teleporting them.
        .animation(reduceMotion ? nil : ProMotionSprings.release, value: items.map(\.id))
        .coordinateSpace(name: OutlineReorderBandSpace.name)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .global).minY
        } action: { top in
            screenTop.value = top
            guard let liftScreenTop = lift?.liftScreenTop else { return }
            lift?.scrollDelta = liftScreenTop - top
            recomputeSlot()
        }
        // A lift that never gets its mouse-up (the pane closing mid-drag)
        // must not stay airborne.
        .onDisappear { lift = nil }
    }

    @ViewBuilder
    private func bandRow(_ item: Item, at index: Int) -> some View {
        let isLifted = lift?.id == item.id
        let isSettling = settlingID == item.id
        let offset = rowOffset(for: item, at: index, isLifted: isLifted)
        let handle = OutlineReorderHandle(
            isLifted: isLifted,
            isAnyLifted: lift != nil,
            onChanged: { value in dragChanged(item, at: index, value: value) },
            onEnded: { endLift() }
        )

        row(item, handle)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                rowHeights[item.id] = height
            }
            .offset(y: offset)
            .zIndex(isLifted || isSettling ? 2 : 0)
            // The row under the hand follows raw — an animation there reads as
            // lag. Siblings step aside snappily; the released row glides home.
            .animation(offsetAnimation(isLifted: isLifted, isSettling: isSettling), value: offset)
            .accessibilityActions {
                if index > 0 {
                    Button("Move Up") { commit(from: index, to: index - 1) }
                }
                if index < items.count - 1 {
                    Button("Move Down") { commit(from: index, to: index + 1) }
                }
            }
    }

    private func rowOffset(for item: Item, at index: Int, isLifted: Bool) -> CGFloat {
        guard let lift else { return 0 }
        if isLifted { return lift.travel }
        return TaskReorderGeometry.offset(
            index: index,
            liftedIndex: lift.index,
            slot: lift.slot,
            liftedHeight: lift.height + spacing
        )
    }

    private func offsetAnimation(isLifted: Bool, isSettling: Bool) -> Animation? {
        if isLifted || reduceMotion { return nil }
        return isSettling ? ProMotionSprings.release : ProMotionSprings.snappy
    }

    // MARK: - The lift

    private func dragChanged(_ item: Item, at index: Int, value: DragGesture.Value) {
        if lift == nil { beginLift(item, at: index) }
        guard lift != nil else { return }
        lift?.translation = value.translation.height
        recomputeSlot()
    }

    private func beginLift(_ item: Item, at index: Int) {
        guard items.count > 1,
              let height = rowHeights[item.id], height > 0 else { return }
        let centres = homeCentres()
        guard centres.count == items.count, centres.indices.contains(index) else { return }

        withAnimation(reduceMotion ? nil : ProMotionSprings.snappy) {
            lift = Lift(
                id: item.id,
                index: index,
                height: height,
                homeCentres: centres,
                liftScreenTop: screenTop.value,
                slot: index
            )
        }
        Sound.dragPickup()
    }

    private func endLift() {
        guard let lift else { return }

        settlingID = lift.id
        let settling = lift.id
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(360))
            if settlingID == settling { settlingID = nil }
        }

        let shouldCommit = lift.slot != lift.index
        // One animation for both halves of the landing: the offset unwinds
        // while the array move slides the slot into place — a single glide,
        // never a teleport followed by a shuffle.
        withAnimation(reduceMotion ? nil : ProMotionSprings.release) {
            self.lift = nil
            if shouldCommit { onReorder(lift.index, lift.slot) }
        }
        if shouldCommit { Sound.dragDrop() }
    }

    private func recomputeSlot() {
        guard let current = lift else { return }
        let next = TaskReorderGeometry.slot(
            currentSlot: current.slot,
            liftedIndex: current.index,
            homeCentres: current.homeCentres,
            draggedCentre: current.centre
        )
        guard next != current.slot else { return }
        lift?.slot = next
    }

    private func commit(from: Int, to: Int) {
        guard from != to else { return }
        withAnimation(reduceMotion ? nil : ProMotionSprings.release) {
            onReorder(from, to)
        }
        Sound.dragDrop()
    }

    /// Home centres from measured heights and the band's spacing — the exact
    /// layout the VStack has when nothing is lifted, and still exact while
    /// rows are offset.
    private func homeCentres() -> [CGFloat] {
        var centres: [CGFloat] = []
        centres.reserveCapacity(items.count)
        var y: CGFloat = 0
        for item in items {
            guard let height = rowHeights[item.id] else { return [] }
            centres.append(y + height / 2)
            y += height + spacing
        }
        return centres
    }
}

/// A scroll position nobody observes — see `TaskReorderBand.screenTop`.
@MainActor
private final class OutlineBandScreenTop {
    var value: CGFloat = 0
}
