// Canvas/CommandCenter/TaskReorderBand.swift
// A band of task rows that reorders live under the pointer. Press and move and
// the row itself lifts — no floating ghost over its own original — while its
// siblings slide out of the way in real time; release and the row glides into
// the slot it is already standing in.
//
// The band never mutates the array mid-drag: rows carry transform offsets, so a
// 40-row ledger costs no layout passes per frame and ForEach identity never
// churns. The array moves once, on release, inside the settle animation — so the
// row's ride and its landing read as one motion.
// July 2026

import SwiftUI

/// Who owns a band's order — the answer decides what a drag inside it means.
enum TaskBandOrdering {
    /// Hand-arranged: the drag reorders and the arrangement persists.
    case manual
    /// The clock owns it (Today's Scheduled band). A row still lifts and can be
    /// carried to the Day Spine or the sidebar, but it never shuffles: a 09:00
    /// task does not belong below a 15:00 one, and letting it look like it does
    /// would be a promise the next reload breaks.
    case clock
    /// Finished work. No lift at all — completed rows are a record, not a plan.
    case fixed
}

struct TaskReorderBand<Row: View>: View {

    let tasks: [TaskViewModel]
    let ordering: TaskBandOrdering
    /// Commit a slot change. Indices are into `tasks`.
    let onReorder: (_ from: Int, _ to: Int) -> Void
    /// Raised when a lifted row leaves the ledger — not merely when it lifts — so
    /// the Day Spine's blocks warm as an invitation only once the row is actually
    /// coming their way. Lowered the instant the gesture ends; the pilot has a
    /// real onEnded, so nothing has to watchdog it back down.
    let onDragInFlightChange: (Bool) -> Void
    @ViewBuilder let row: (TaskViewModel) -> Row

    @State private var lift: Lift?
    /// Row heights, keyed by row id. Heights — not frames: a frame measured
    /// while the band is dragging reports the row's *offset* position, which
    /// feeds straight back into the offsets that produced it. Heights are
    /// transform-invariant, so home centres derived from them stay true all the
    /// way through a drag.
    @State private var rowHeights: [String: CGFloat] = [:]
    /// The band's top in screen space, sampled every scroll tick. Edge
    /// autoscroll moves the content under a still pointer; without this the
    /// lifted row would swim away from the cursor.
    ///
    /// Deliberately a box, not `@State`: this fires on every frame of every
    /// ordinary scroll, and a plain `@State` would invalidate the whole band
    /// each tick for a number nobody is looking at unless a row is airborne.
    @State private var screenTop = BandScreenTop()
    /// The just-released row, still gliding. The lift clears the instant the
    /// mouse comes up, which dropped the row's zIndex mid-settle and let it dive
    /// under the rows it was passing.
    @State private var settlingRowID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pilot: TaskDragPilot { .shared }

    /// A live lift. `homeCentres` and `height` are frozen at pickup — see
    /// TaskReorderGeometry for why the math must never look at live positions.
    private struct Lift {
        let rowID: String
        let index: Int
        let height: CGFloat
        let homeCentres: [CGFloat]
        let liftScreenTop: CGFloat
        var translation: CGFloat = 0
        var scrollDelta: CGFloat = 0
        var slot: Int
        var isTravelling = false

        /// Where the lifted row's centre sits now, in band space.
        var centre: CGFloat {
            (homeCentres.indices.contains(index) ? homeCentres[index] : 0) + travel
        }

        /// The pointer's travel plus whatever the list scrolled underneath it.
        var travel: CGFloat { translation + scrollDelta }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                bandRow(task, at: index)
            }
        }
        // Rows glide to close the gap when a task departs (completed, deleted,
        // rescheduled) or arrives, instead of teleporting — and a committed
        // reorder rides the SAME spring the released row's offset unwinds with,
        // so its landing reads as one motion rather than a snap plus a shuffle.
        .animation(reduceMotion ? nil : ProMotionSprings.release, value: tasks.map(\.id))
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .global).minY
        } action: { top in
            screenTop.value = top
            // Autoscroll during a lift: the content moved, the hand did not.
            guard let liftScreenTop = lift?.liftScreenTop else { return }
            lift?.scrollDelta = liftScreenTop - top
            recomputeSlot()
        }
        // A gesture that never gets its mouse-up (the window deactivating
        // mid-drag) would leave the pilot lifted and the grab cursor pushed.
        .onDisappear {
            guard lift != nil else { return }
            lift = nil
            pilot.cancel()
            onDragInFlightChange(false)
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func bandRow(_ task: TaskViewModel, at index: Int) -> some View {
        let isLifted = lift?.rowID == task.id
        // Tracking = under the hand, in the ledger. A row that has left the
        // ledger hands off to the travel card and settles back into its own slot,
        // dimmed — so the list reads intact and only one thing is moving.
        let isTracking = isLifted && lift?.isTravelling != true
        let isSettling = settlingRowID == task.id
        let offset = rowOffset(for: index, isTracking: isTracking)

        row(task)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                rowHeights[task.id] = height
            }
            .opacity(isLifted && lift?.isTravelling == true ? 0.32 : 1)
            // The lift is a shadow, NOT a scale, and the shadow lives inside an
            // 8pt gutter.
            //
            // A row here is full-bleed (~1200pt), and the only clear space
            // around its card is the `DS.space8` the row glass is inset by —
            // beyond that the ledger's ScrollView clips. So:
            //
            //  · No scaleEffect. At this width even 1.012 grows the card 7pt per
            //    side, which parks its edges flush against that clip and shears
            //    the shadow off in a straight vertical line (top and bottom stay
            //    soft, because nothing clips vertically — that asymmetry is the
            //    tell). It also resamples the row's text for a 1.2% change no eye
            //    can see. Scale belongs to cards, not to full-bleed rows.
            //  · radius 6 / y 3, so the falloff reaches ~6pt sideways and stays
            //    clear of the clip, while the downward offset does the lifting.
            //
            // Anything that widens the card mid-drag — or a fatter radius — must
            // buy the room first.
            .shadow(color: .black.opacity(isTracking ? 0.13 : 0), radius: 6, y: 3)
            .offset(y: offset)
            .zIndex(isLifted || isSettling ? 2 : 0)
            .animation(offsetAnimation(isTracking: isTracking, isSettling: isSettling), value: offset)
            .animation(reduceMotion ? nil : ProMotionSprings.snappy, value: isTracking)
            // Simultaneous, not exclusive: the row's tap and its inline buttons
            // are deeper in the hierarchy, and an exclusive parent gesture
            // starves them (the pane deck's tab strip settled this). The drop's
            // stray mouse-up is handled where it lands instead — every row
            // action checks `TaskDragPilot.suppressesRowTap`.
            .simultaneousGesture(
                liftGesture(task, at: index),
                including: ordering == .fixed ? .subviews : .all
            )
            .accessibilityActions {
                if ordering == .manual {
                    if index > 0 {
                        Button("Move Up") { commit(from: index, to: index - 1) }
                    }
                    if index < tasks.count - 1 {
                        Button("Move Down") { commit(from: index, to: index + 1) }
                    }
                }
            }
    }

    private func rowOffset(for index: Int, isTracking: Bool) -> CGFloat {
        guard let lift else { return 0 }
        if isTracking { return lift.travel }
        guard ordering == .manual, !lift.isTravelling, lift.rowID != tasks[index].id else { return 0 }
        return TaskReorderGeometry.offset(
            index: index,
            liftedIndex: lift.index,
            slot: lift.slot,
            liftedHeight: lift.height
        )
    }

    /// The tracked row follows the pointer raw — an animation on the thing under
    /// your hand reads as lag. Siblings step aside snappily; the released row
    /// glides home with a little life.
    private func offsetAnimation(isTracking: Bool, isSettling: Bool) -> Animation? {
        if isTracking { return nil }
        if reduceMotion { return nil }
        return isSettling ? ProMotionSprings.release : ProMotionSprings.snappy
    }

    // MARK: - The lift

    private func liftGesture(_ task: TaskViewModel, at index: Int) -> some Gesture {
        // 5pt of slop: a click that wobbles opens the task, a deliberate pull
        // lifts it. (The row's own tap gesture keeps working — the drag simply
        // never starts.)
        DragGesture(minimumDistance: 5, coordinateSpace: .named(CommandCenterDragSpace.name))
            .onChanged { value in
                if lift == nil { beginLift(task, at: index, value: value) }
                guard lift != nil else { return }
                lift?.translation = value.translation.height
                pilot.update(pointer: value.location)
                let travelling = pilot.isTravelling
                if lift?.isTravelling != travelling {
                    lift?.isTravelling = travelling
                    onDragInFlightChange(travelling)
                }
                recomputeSlot()
            }
            .onEnded { _ in endLift() }
    }

    private func beginLift(_ task: TaskViewModel, at index: Int, value: DragGesture.Value) {
        guard let height = rowHeights[task.id], height > 0 else { return }
        let centres = homeCentres()
        guard centres.count == tasks.count, centres.indices.contains(index) else { return }

        lift = Lift(
            rowID: task.id,
            index: index,
            height: height,
            homeCentres: centres,
            liftScreenTop: screenTop.value,
            slot: index
        )
        pilot.begin(taskUUID: task.uuid, title: task.title, at: value.location)
    }

    private func endLift() {
        guard let lift else { return }
        let landing = pilot.end()
        onDragInFlightChange(false)

        settlingRowID = lift.rowID
        let settlingID = lift.rowID
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(360))
            if settlingRowID == settlingID { settlingRowID = nil }
        }

        let shouldCommit: Bool = {
            guard case .band = landing else { return false }
            return ordering == .manual && lift.slot != lift.index
        }()

        // One animation for both halves of the landing: the row's offset
        // unwinds while the array move slides its slot into place, so the eye
        // sees a single glide instead of a teleport followed by a shuffle.
        withAnimation(reduceMotion ? nil : ProMotionSprings.release) {
            self.lift = nil
            if shouldCommit {
                onReorder(lift.index, lift.slot)
            }
        }
        if shouldCommit { Sound.dragDrop() }
    }

    private func recomputeSlot() {
        guard let current = lift, ordering == .manual, !current.isTravelling else { return }
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
        guard ordering == .manual, from != to else { return }
        withAnimation(reduceMotion ? nil : ProMotionSprings.release) {
            onReorder(from, to)
        }
        Sound.dragDrop()
    }

    /// Home centres from measured heights: a VStack of spacing 0 stacks them, so
    /// the running total is the exact layout the band would have if nothing were
    /// lifted — and it stays exact while rows are offset.
    private func homeCentres() -> [CGFloat] {
        var centres: [CGFloat] = []
        centres.reserveCapacity(tasks.count)
        var y: CGFloat = 0
        for task in tasks {
            guard let height = rowHeights[task.id] else { return [] }
            centres.append(y + height / 2)
            y += height
        }
        return centres
    }
}

/// A scroll position nobody observes — see `TaskReorderBand.screenTop`.
@MainActor
private final class BandScreenTop {
    var value: CGFloat = 0
}
