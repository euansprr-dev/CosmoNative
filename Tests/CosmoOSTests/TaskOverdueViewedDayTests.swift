// Tests/CosmoOSTests/TaskOverdueViewedDayTests.swift
// Overdue is judged from the VIEWED day, not wall-clock today (iOS parity):
// on its own due day a task is a normal checkable row, not "Overdue". This is
// what lets you scroll back to yesterday's page and tick a task you forgot,
// crediting that day.

import XCTest
@testable import CosmoOS

@MainActor
final class TaskOverdueViewedDayTests: XCTestCase {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testDueTaskIsNotOverdueOnItsOwnDayButIsFromLater() {
        let due = day(2026, 7, 13)
        let task = TaskViewModel(uuid: "t1", title: "Read 10 minutes before bed", dueDate: due)

        // On its own due day: not overdue, and the chip label is not "Overdue".
        XCTAssertFalse(task.isOverdue(asOf: due))
        XCTAssertNotEqual(task.dueInfo(asOf: due), "Overdue")

        // Viewed from the next day: overdue.
        let nextDay = day(2026, 7, 14)
        XCTAssertTrue(task.isOverdue(asOf: nextDay))
        XCTAssertEqual(task.dueInfo(asOf: nextDay), "Overdue")

        // A time-of-day on the due date still counts as "that day", not late.
        let dueEvening = cal.date(byAdding: .hour, value: 22, to: due)!
        let eveningTask = TaskViewModel(uuid: "t2", title: "Read", dueDate: dueEvening)
        XCTAssertFalse(eveningTask.isOverdue(asOf: due))
    }

    func testCompletedTaskIsNeverOverdue() {
        let due = day(2026, 7, 13)
        let task = TaskViewModel(uuid: "t3", title: "Read", dueDate: due, isCompleted: true)
        XCTAssertFalse(task.isOverdue(asOf: day(2026, 7, 20)))
    }
}
