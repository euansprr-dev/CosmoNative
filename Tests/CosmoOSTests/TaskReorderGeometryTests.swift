import XCTest
@testable import CosmoOS

/// The live-reorder math. Every case here is a feel bug caught as arithmetic:
/// the flicker at a boundary, the sibling that steps aside too early, the
/// off-by-one that lands a downward drag one slot short.
final class TaskReorderGeometryTests: XCTestCase {

    /// Four equal 40pt rows: centres at 20, 60, 100, 140.
    private let uniform: [CGFloat] = [20, 60, 100, 140]
    private let rowHeight: CGFloat = 40

    // MARK: - Slot walking

    func testStandingStillKeepsItsOwnSlot() {
        let slot = TaskReorderGeometry.slot(
            currentSlot: 1, liftedIndex: 1, homeCentres: uniform, draggedCentre: 60
        )
        XCTAssertEqual(slot, 1)
    }

    /// A row must travel a FULL row height — to the next row's home centre —
    /// before they swap. Half a row is a hover, not a move.
    func testHalfARowOfTravelDoesNotSwap() {
        let slot = TaskReorderGeometry.slot(
            currentSlot: 0, liftedIndex: 0, homeCentres: uniform, draggedCentre: 20 + rowHeight / 2
        )
        XCTAssertEqual(slot, 0)
    }

    func testClearingTheNextRowsCentreTakesItsSlot() {
        let slot = TaskReorderGeometry.slot(
            currentSlot: 0, liftedIndex: 0, homeCentres: uniform, draggedCentre: 60 + 6
        )
        XCTAssertEqual(slot, 1)
    }

    func testASingleDragCanCrossSeveralRows() {
        let slot = TaskReorderGeometry.slot(
            currentSlot: 0, liftedIndex: 0, homeCentres: uniform, draggedCentre: 150
        )
        XCTAssertEqual(slot, 3)
    }

    func testDraggingUpwardTakesTheSlotAbove() {
        let slot = TaskReorderGeometry.slot(
            currentSlot: 3, liftedIndex: 3, homeCentres: uniform, draggedCentre: 100 - 6
        )
        XCTAssertEqual(slot, 2)
    }

    func testSlotNeverLeavesTheBand() {
        XCTAssertEqual(
            TaskReorderGeometry.slot(
                currentSlot: 0, liftedIndex: 0, homeCentres: uniform, draggedCentre: -400
            ),
            0
        )
        XCTAssertEqual(
            TaskReorderGeometry.slot(
                currentSlot: 3, liftedIndex: 3, homeCentres: uniform, draggedCentre: 4000
            ),
            3
        )
    }

    func testALoneRowHasNowhereToGo() {
        let slot = TaskReorderGeometry.slot(
            currentSlot: 0, liftedIndex: 0, homeCentres: [20], draggedCentre: 900
        )
        XCTAssertEqual(slot, 0)
    }

    // MARK: - Hysteresis (the anti-flicker guarantee)

    /// A hand resting exactly on a boundary must not buzz. Inside the
    /// hysteresis band the slot is whatever it already was — both answers are
    /// stable, and neither flips on a one-pixel tremor.
    func testRestingOnABoundaryHoldsWhicheverSlotItAlreadyHad() {
        let onBoundary: CGFloat = 60

        XCTAssertEqual(
            TaskReorderGeometry.slot(
                currentSlot: 0, liftedIndex: 0, homeCentres: uniform, draggedCentre: onBoundary
            ),
            0
        )
        XCTAssertEqual(
            TaskReorderGeometry.slot(
                currentSlot: 1, liftedIndex: 0, homeCentres: uniform, draggedCentre: onBoundary
            ),
            1
        )
    }

    /// Leaving a slot costs the hysteresis in BOTH directions. An asymmetric
    /// margin (the bug from testing `slot + 1` upward as well as downward) makes
    /// a row swap after half a row and refuse to swap back for a full one.
    func testGivingASlotBackCostsTheSameMarginAsTakingIt() {
        // Took slot 1 by clearing 60; giving it back happens just under 60.
        XCTAssertEqual(
            TaskReorderGeometry.slot(
                currentSlot: 1, liftedIndex: 0, homeCentres: uniform,
                draggedCentre: 60 - TaskReorderGeometry.hysteresis - 1
            ),
            0
        )
        // And mirrored, for a row that came from below.
        XCTAssertEqual(
            TaskReorderGeometry.slot(
                currentSlot: 2, liftedIndex: 3, homeCentres: uniform,
                draggedCentre: 100 + TaskReorderGeometry.hysteresis + 1
            ),
            3
        )
    }

    // MARK: - Mixed row heights

    /// Bands mix one- and two-line rows (a task with meta is taller). The
    /// boundaries are the measured centres, so the crossing points follow the
    /// real layout rather than an assumed uniform pitch.
    func testTallRowsMoveTheBoundariesWithThem() {
        // 24pt row, 60pt row, 24pt row → centres 12, 54, 96.
        let mixed: [CGFloat] = [12, 54, 96]

        XCTAssertEqual(
            TaskReorderGeometry.slot(currentSlot: 0, liftedIndex: 0, homeCentres: mixed, draggedCentre: 40),
            0,
            "40 has not cleared the tall row's centre at 54"
        )
        XCTAssertEqual(
            TaskReorderGeometry.slot(currentSlot: 0, liftedIndex: 0, homeCentres: mixed, draggedCentre: 62),
            1
        )
    }

    // MARK: - Sibling offsets

    func testTheLiftedRowIsNeverGivenAStepAsideOffset() {
        XCTAssertEqual(
            TaskReorderGeometry.offset(index: 1, liftedIndex: 1, slot: 3, liftedHeight: rowHeight),
            0
        )
    }

    func testRowsBetweenHomeAndSlotStepTowardTheHole() {
        // Row 0 dragged down to slot 2: rows 1 and 2 slide up by one row height,
        // row 3 has no reason to move.
        XCTAssertEqual(
            TaskReorderGeometry.offset(index: 1, liftedIndex: 0, slot: 2, liftedHeight: rowHeight),
            -rowHeight
        )
        XCTAssertEqual(
            TaskReorderGeometry.offset(index: 2, liftedIndex: 0, slot: 2, liftedHeight: rowHeight),
            -rowHeight
        )
        XCTAssertEqual(
            TaskReorderGeometry.offset(index: 3, liftedIndex: 0, slot: 2, liftedHeight: rowHeight),
            0
        )
    }

    func testDraggingUpwardPushesTheRowsAboveDown() {
        // Row 3 dragged up to slot 1: rows 1 and 2 slide down; row 0 stays.
        XCTAssertEqual(
            TaskReorderGeometry.offset(index: 1, liftedIndex: 3, slot: 1, liftedHeight: rowHeight),
            rowHeight
        )
        XCTAssertEqual(
            TaskReorderGeometry.offset(index: 2, liftedIndex: 3, slot: 1, liftedHeight: rowHeight),
            rowHeight
        )
        XCTAssertEqual(
            TaskReorderGeometry.offset(index: 0, liftedIndex: 3, slot: 1, liftedHeight: rowHeight),
            0
        )
    }

    /// A sibling steps aside by the height of the HOLE, never its own height —
    /// otherwise a short row moving past a tall one leaves a gap or overlaps.
    func testStepAsideUsesTheLiftedRowsHeightNotTheSiblings() {
        XCTAssertEqual(
            TaskReorderGeometry.offset(index: 1, liftedIndex: 0, slot: 1, liftedHeight: 88),
            -88
        )
    }

    func testNobodyMovesWhileTheRowSitsInItsOwnSlot() {
        for index in 0..<4 {
            XCTAssertEqual(
                TaskReorderGeometry.offset(index: index, liftedIndex: 2, slot: 2, liftedHeight: rowHeight),
                0
            )
        }
    }

    // MARK: - Commit

    /// `Array.move(fromOffsets:toOffset:)` counts the destination before the
    /// element is removed. The old drop-target code used the raw index in one
    /// direction and index+1 in the other, so a downward drop landed a slot
    /// past the line it had drawn.
    func testDownwardMoveOffsetIsOnePastTheSlot() {
        XCTAssertEqual(TaskReorderGeometry.moveOffset(from: 0, to: 2), 3)
    }

    func testUpwardMoveOffsetIsTheSlotItself() {
        XCTAssertEqual(TaskReorderGeometry.moveOffset(from: 3, to: 1), 1)
    }

    func testReorderedMatchesArrayMove() {
        let letters = ["a", "b", "c", "d"]

        for from in letters.indices {
            for to in letters.indices {
                var expected = letters
                expected.move(
                    fromOffsets: IndexSet(integer: from),
                    toOffset: TaskReorderGeometry.moveOffset(from: from, to: to)
                )
                XCTAssertEqual(
                    TaskReorderGeometry.reordered(letters, from: from, to: to),
                    expected,
                    "from \(from) to \(to)"
                )
            }
        }
    }

    func testReorderedIgnoresIndicesOutsideTheBand() {
        let letters = ["a", "b", "c"]
        XCTAssertEqual(TaskReorderGeometry.reordered(letters, from: 0, to: 9), letters)
        XCTAssertEqual(TaskReorderGeometry.reordered(letters, from: -1, to: 1), letters)
    }

    // MARK: - End to end

    // MARK: - Permuting a visible band inside a bigger ladder

    private func task(_ id: String) -> TaskViewModel {
        TaskViewModel(id: id, uuid: id, title: id)
    }

    func testPermutingRearrangesOnlyTheNamedRows() {
        let all = ["a", "b", "c", "d"].map(task)

        let result = TaskReorderGeometry.permuted(all, to: ["c", "a"])

        // "a" and "c" swap the two slots they held (0 and 2); "b" and "d" never
        // move, because the caller never named them.
        XCTAssertEqual(result.map(\.id), ["c", "b", "a", "d"])
    }

    /// The project page draws one heading's open rows, so the band it hands over
    /// is a subset with gaps. Everything it left out has to stay exactly put —
    /// otherwise reordering inside one heading reshuffles another.
    func testPermutingLeavesUnnamedRowsInPlace() {
        let all = ["h1-a", "other", "h1-b", "done", "h1-c"].map(task)

        let result = TaskReorderGeometry.permuted(all, to: ["h1-c", "h1-a", "h1-b"])

        XCTAssertEqual(result.map(\.id), ["h1-c", "other", "h1-a", "done", "h1-b"])
    }

    func testPermutingIgnoresIDsThatAreNotInTheArray() {
        let all = ["a", "b"].map(task)

        let result = TaskReorderGeometry.permuted(all, to: ["ghost", "b", "a"])

        XCTAssertEqual(result.map(\.id), ["b", "a"])
    }

    func testPermutingWithNoNamedRowsChangesNothing() {
        let all = ["a", "b", "c"].map(task)
        XCTAssertEqual(
            TaskReorderGeometry.permuted(all, to: []).map(\.id),
            ["a", "b", "c"]
        )
    }

    /// A drag commit round trip: the band the view drew, reordered by the drag
    /// math, permuted back into the array the view model persists.
    func testDragCommitRoundTripThroughAVisibleSubset() {
        let all = ["a", "hidden", "b", "c"].map(task)
        let visible = [all[0], all[2], all[3]]  // a, b, c

        // Drag "a" (index 0) down to the last slot of the visible band.
        let arranged = TaskReorderGeometry.reordered(visible, from: 0, to: 2).map(\.id)
        XCTAssertEqual(arranged, ["b", "c", "a"])

        let result = TaskReorderGeometry.permuted(all, to: arranged)
        XCTAssertEqual(result.map(\.id), ["b", "hidden", "c", "a"])
    }

    // MARK: - End to end

    /// A full downward drag, frame by frame, from lift to commit: the row walks
    /// its slots monotonically, its siblings never oscillate, and the committed
    /// array matches where the row was standing when it was released.
    func testAFullDownwardDragWalksItsSlotsAndCommitsWhereItStands() {
        let rows = ["a", "b", "c", "d"]
        var slot = 0
        var seen: [Int] = []

        for step in stride(from: CGFloat(0), through: 130, by: 3) {
            slot = TaskReorderGeometry.slot(
                currentSlot: slot,
                liftedIndex: 0,
                homeCentres: uniform,
                draggedCentre: uniform[0] + step
            )
            seen.append(slot)
        }

        XCTAssertEqual(seen, seen.sorted(), "the slot must never walk backwards during a monotonic drag")
        XCTAssertEqual(slot, 3)
        XCTAssertEqual(TaskReorderGeometry.reordered(rows, from: 0, to: slot), ["b", "c", "d", "a"])
    }
}
