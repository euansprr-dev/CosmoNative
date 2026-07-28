import XCTest
@testable import CosmoOS

/// Pins the drop grammar for "drag an idea onto the week board".
final class UpcomingDropActionsTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth)))
    }

    // MARK: - Payload routing

    func testOnlyPrefixedIdeaPayloadsAreAccepted() {
        XCTAssertEqual(UpcomingDropActions.ideaUUID(from: "idea:abc-123"), "abc-123")
    }

    /// THE LAW this guards: three vocabularies share the `String` drop channel.
    /// `ContentShelfPayload` reads an unprefixed string as CONTENT, while the
    /// sidebar and the Today spine read one as a TASK uuid. If the board's idea
    /// handler accepted bare uuids it would swallow task drags and die silently.
    func testBareAndForeignPayloadsAreRefused() {
        XCTAssertNil(UpcomingDropActions.ideaUUID(from: "abc-123"))
        XCTAssertNil(UpcomingDropActions.ideaUUID(from: "content:abc-123"))
        XCTAssertNil(UpcomingDropActions.ideaUUID(from: "idea:"))
        XCTAssertNil(UpcomingDropActions.ideaUUID(from: ""))
    }

    func testFirstIdeaWinsInAMultiPayloadDrop() {
        let payloads = ["content:aaa", "idea:bbb", "idea:ccc"]
        XCTAssertEqual(UpcomingDropActions.firstIdeaUUID(in: payloads), "bbb")
    }

    func testMultiPayloadDropWithNoIdeaIsRefused() {
        XCTAssertNil(UpcomingDropActions.firstIdeaUUID(in: ["content:aaa", "some-task-uuid"]))
    }

    // MARK: - Geometry → time

    func testDropAtColumnTopBooksMidnight() throws {
        let wednesday = try day(2026, 7, 29)

        let target = UpcomingDropActions.timedTarget(
            ideaUUID: "i1", y: 0, on: wednesday, calendar: calendar
        )

        guard case .timed(_, let start) = target else { return XCTFail("expected a timed target") }
        XCTAssertEqual(calendar.component(.hour, from: start), 0)
        XCTAssertEqual(calendar.component(.minute, from: start), 0)
    }

    func testDropMidColumnBooksThatHour() throws {
        let wednesday = try day(2026, 7, 29)
        // hourHeight is 52pt, so 10:00 sits at y = 520.
        let y = CommandCenterCalendarLayout.hourHeight * 10

        let target = UpcomingDropActions.timedTarget(
            ideaUUID: "i1", y: y, on: wednesday, calendar: calendar
        )

        guard case .timed(_, let start) = target else { return XCTFail("expected a timed target") }
        XCTAssertEqual(calendar.component(.hour, from: start), 10)
        XCTAssertEqual(calendar.component(.minute, from: start), 0)
    }

    /// Drops snap to the board's own 15-minute grid, so a session never lands
    /// at 10:07 and misaligns with every other block in the column.
    func testDropSnapsToTheFifteenMinuteGrid() throws {
        let wednesday = try day(2026, 7, 29)
        // A third of an hour past 09:00 — 20 minutes, which must snap to :15.
        let y = CommandCenterCalendarLayout.hourHeight * 9 + CommandCenterCalendarLayout.hourHeight / 3

        let target = UpcomingDropActions.timedTarget(
            ideaUUID: "i1", y: y, on: wednesday, calendar: calendar
        )

        guard case .timed(_, let start) = target else { return XCTFail("expected a timed target") }
        XCTAssertEqual(calendar.component(.hour, from: start), 9)
        XCTAssertEqual(calendar.component(.minute, from: start) % CommandCenterCalendarLayout.snapMinutes, 0)
        XCTAssertEqual(calendar.component(.minute, from: start), 15)
    }

    func testAllDayTargetNormalisesToStartOfDay() throws {
        let wednesday = try day(2026, 7, 29)
        let middleOfDay = try XCTUnwrap(calendar.date(byAdding: .hour, value: 14, to: wednesday))

        let target = UpcomingDropActions.allDayTarget(
            ideaUUID: "i1", on: middleOfDay, calendar: calendar
        )

        guard case .allDay(_, let resolved) = target else { return XCTFail("expected an all-day target") }
        XCTAssertEqual(resolved, wednesday)
    }

    // MARK: - Toast wording

    /// A move that leaves other open sessions behind must SAY so — an
    /// unmentioned second session is invisible, and invisible is how duplicate
    /// sessions survive.
    func testToastNamesTheMoveWhenOtherOpenSessionsRemain() throws {
        let wednesday = try day(2026, 7, 29)
        let target = UpcomingDropActions.allDayTarget(ideaUUID: "i1", on: wednesday, calendar: calendar)

        let toast = UpcomingDropActions.toast(
            moved: true, siblings: 2, target: target, calendar: calendar, now: wednesday
        )

        XCTAssertTrue(toast.contains("soonest"), "got: \(toast)")
    }

    func testToastForASoleMoveDoesNotMentionSiblings() throws {
        let wednesday = try day(2026, 7, 29)
        let target = UpcomingDropActions.allDayTarget(ideaUUID: "i1", on: wednesday, calendar: calendar)

        let toast = UpcomingDropActions.toast(
            moved: true, siblings: 0, target: target, calendar: calendar, now: wednesday
        )

        XCTAssertFalse(toast.contains("soonest"), "got: \(toast)")
        XCTAssertTrue(toast.contains("moved"), "got: \(toast)")
    }

    func testToastForAFreshBookingReadsAsCreation() throws {
        let wednesday = try day(2026, 7, 29)
        let target = UpcomingDropActions.allDayTarget(ideaUUID: "i1", on: wednesday, calendar: calendar)

        let toast = UpcomingDropActions.toast(
            moved: false, siblings: 0, target: target, calendar: calendar, now: wednesday
        )

        XCTAssertTrue(toast.contains("Writing session"), "got: \(toast)")
    }

    func testDayWordSpeaksTheAppsOneDayVoice() throws {
        let wednesday = try day(2026, 7, 29)
        let thursday = try day(2026, 7, 30)
        let nextWeek = try day(2026, 8, 4)

        XCTAssertEqual(UpcomingDropActions.dayWord(wednesday, calendar: calendar, now: wednesday), "Today")
        XCTAssertEqual(UpcomingDropActions.dayWord(thursday, calendar: calendar, now: wednesday), "Tomorrow")
        XCTAssertFalse(UpcomingDropActions.dayWord(nextWeek, calendar: calendar, now: wednesday).isEmpty)
    }

    // MARK: - Publish bridge lane

    private func shelfIdea(booked: Date?, publish: Date?) -> WorkShelfIdea {
        WorkShelfIdea(
            atomUUID: "i1",
            title: "A hook",
            clientUUID: nil,
            clientName: nil,
            updatedAt: "2026-07-27T00:00:00Z",
            score: 1,
            whyLine: "Ready to write",
            bookedDay: booked,
            publishDay: publish
        )
    }

    func testPublishingSoonNeedsAPublishDateAndNoBookedSession() throws {
        let now = try day(2026, 7, 27)
        let soon = try day(2026, 7, 30)

        let unbooked = shelfIdea(booked: nil, publish: soon)
        XCTAssertTrue(unbooked.isPublishingSoon(now: now, horizonDays: 14, calendar: calendar))

        // Already booked to be written — it is no longer a gap.
        let booked = shelfIdea(booked: try day(2026, 7, 28), publish: soon)
        XCTAssertFalse(booked.isPublishingSoon(now: now, horizonDays: 14, calendar: calendar))

        // No publish date at all — nothing to be late for.
        let noPublish = shelfIdea(booked: nil, publish: nil)
        XCTAssertFalse(noPublish.isPublishingSoon(now: now, horizonDays: 14, calendar: calendar))
    }

    func testPublishingSoonRespectsTheHorizonBoundary() throws {
        let now = try day(2026, 7, 27)

        let insideHorizon = shelfIdea(booked: nil, publish: try day(2026, 8, 9))
        XCTAssertTrue(insideHorizon.isPublishingSoon(now: now, horizonDays: 14, calendar: calendar))

        let pastHorizon = shelfIdea(booked: nil, publish: try day(2026, 8, 10))
        XCTAssertFalse(pastHorizon.isPublishingSoon(now: now, horizonDays: 14, calendar: calendar))
    }

    /// A publish date already gone is the most urgent case of all — it must not
    /// fall out of the lane just for being in the past.
    func testOverduePublishDateStillCountsAsPublishingSoon() throws {
        let now = try day(2026, 7, 27)
        let overdue = shelfIdea(booked: nil, publish: try day(2026, 7, 20))

        XCTAssertTrue(overdue.isPublishingSoon(now: now, horizonDays: 14, calendar: calendar))
    }
}
