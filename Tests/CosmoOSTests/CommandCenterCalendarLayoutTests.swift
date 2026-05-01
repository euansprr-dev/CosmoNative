import XCTest
@testable import CosmoOS

final class CommandCenterCalendarLayoutTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    func testWeekVisibleDatesStartAtAnchorAndSpanSevenDays() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 30)))

        let dates = CommandCenterCalendarLayout.visibleDates(anchor: anchor, scope: .week, calendar: calendar)

        XCTAssertEqual(dates.count, 7)
        XCTAssertEqual(calendar.component(.day, from: dates[0]), 30)
        XCTAssertEqual(calendar.component(.day, from: dates[6]), 6)
        XCTAssertEqual(calendar.component(.month, from: dates[6]), 5)
    }

    func testMonthVisibleDatesIncludeFullMondayBasedGrid() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 30)))

        let dates = CommandCenterCalendarLayout.visibleDates(anchor: anchor, scope: .month, calendar: calendar)

        XCTAssertEqual(dates.count, 35)
        XCTAssertEqual(calendar.component(.weekday, from: dates.first!), 2)
        XCTAssertEqual(calendar.component(.day, from: dates.first!), 30)
        XCTAssertEqual(calendar.component(.month, from: dates.first!), 3)
        XCTAssertEqual(calendar.component(.weekday, from: dates.last!), 1)
        XCTAssertEqual(calendar.component(.day, from: dates.last!), 3)
        XCTAssertEqual(calendar.component(.month, from: dates.last!), 5)
    }

    func testSnapsYPositionToFifteenMinutes() throws {
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 30)))
        let y = CommandCenterCalendarLayout.hourHeight * 13.22

        let snapped = CommandCenterCalendarLayout.snappedDate(forY: y, on: day, calendar: calendar)

        XCTAssertEqual(calendar.component(.hour, from: snapped), 13)
        XCTAssertEqual(calendar.component(.minute, from: snapped), 15)
    }

    func testBlockPositionAndHeightForPartialHours() throws {
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 30)))
        let start = try XCTUnwrap(calendar.date(byAdding: .minute, value: 13 * 60 + 15, to: day))
        let end = try XCTUnwrap(calendar.date(byAdding: .minute, value: 15 * 60 + 30, to: day))

        let y = CommandCenterCalendarLayout.yOffset(for: start, dayStart: day, calendar: calendar)
        let height = CommandCenterCalendarLayout.blockHeight(from: start, to: end)

        XCTAssertEqual(y, CommandCenterCalendarLayout.hourHeight * 13.25, accuracy: 0.001)
        XCTAssertEqual(height, CommandCenterCalendarLayout.hourHeight * 2.25, accuracy: 0.001)
    }

    func testOverlapPlacementSplitsConcurrentEventsIntoStableLanes() throws {
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 30)))
        func time(_ hour: Int, _ minute: Int = 0) throws -> Date {
            try XCTUnwrap(calendar.date(byAdding: .minute, value: hour * 60 + minute, to: day))
        }

        let placements = CommandCenterCalendarLayout.overlapPlacements(for: [
            CalendarLayoutInterval(id: "a", start: try time(9), end: try time(11)),
            CalendarLayoutInterval(id: "b", start: try time(10), end: try time(12)),
            CalendarLayoutInterval(id: "c", start: try time(12), end: try time(13))
        ])

        XCTAssertEqual(placements["a"], CalendarOverlapPlacement(lane: 0, laneCount: 2))
        XCTAssertEqual(placements["b"], CalendarOverlapPlacement(lane: 1, laneCount: 2))
        XCTAssertEqual(placements["c"], CalendarOverlapPlacement(lane: 0, laneCount: 1))
    }

    func testAllDayClassificationRequiresFullDaySpan() throws {
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let almostFullDay = try XCTUnwrap(calendar.date(byAdding: .hour, value: 23, to: day))
        let shortBlock = try XCTUnwrap(calendar.date(byAdding: .hour, value: 2, to: day))

        XCTAssertTrue(CommandCenterCalendarLayout.isAllDay(start: day, end: almostFullDay, calendar: calendar))
        XCTAssertFalse(CommandCenterCalendarLayout.isAllDay(start: day, end: shortBlock, calendar: calendar))
    }
}
