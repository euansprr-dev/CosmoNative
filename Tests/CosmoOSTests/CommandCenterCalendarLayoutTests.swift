import XCTest
@testable import CosmoOS

final class CommandCenterCalendarLayoutTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    func testWeekVisibleDatesStartOnMondayAndEndOnSunday() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 30)))

        let dates = CommandCenterCalendarLayout.visibleDates(anchor: anchor, scope: .week, calendar: calendar)

        XCTAssertEqual(dates.count, 7)
        XCTAssertEqual(calendar.component(.weekday, from: dates[0]), 2)
        XCTAssertEqual(calendar.component(.day, from: dates[0]), 27)
        XCTAssertEqual(calendar.component(.month, from: dates[0]), 4)
        XCTAssertEqual(calendar.component(.weekday, from: dates[6]), 1)
        XCTAssertEqual(calendar.component(.day, from: dates[6]), 3)
        XCTAssertEqual(calendar.component(.month, from: dates[6]), 5)
    }

    func testWeekVisibleDatesKeepSundayInTheSameMondayBasedWeek() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 3)))

        let dates = CommandCenterCalendarLayout.visibleDates(anchor: anchor, scope: .week, calendar: calendar)

        XCTAssertEqual(dates.count, 7)
        XCTAssertEqual(calendar.component(.day, from: dates[0]), 27)
        XCTAssertEqual(calendar.component(.month, from: dates[0]), 4)
        XCTAssertEqual(calendar.component(.day, from: dates[6]), 3)
        XCTAssertEqual(calendar.component(.month, from: dates[6]), 5)
    }

    func testDayScopeStillShowsTheWholeMondayBasedWeek() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 30)))

        let dates = CommandCenterCalendarLayout.visibleDates(anchor: anchor, scope: .day, calendar: calendar)

        XCTAssertEqual(dates.count, 7)
        XCTAssertEqual(calendar.component(.day, from: dates[0]), 27)
        XCTAssertEqual(calendar.component(.day, from: dates[6]), 3)
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

    func testTopResizePreviewExpandsUpwardAndKeepsMinimumHeight() {
        let expanded = CommandCenterCalendarLayout.resizePreview(
            edge: .top,
            translationHeight: -26,
            originalHeight: 52
        )

        XCTAssertEqual(expanded.offsetY, -26, accuracy: 0.001)
        XCTAssertEqual(expanded.height, 78, accuracy: 0.001)

        let collapsed = CommandCenterCalendarLayout.resizePreview(
            edge: .top,
            translationHeight: 80,
            originalHeight: 52
        )

        XCTAssertEqual(collapsed.offsetY, 34, accuracy: 0.001)
        XCTAssertEqual(collapsed.height, 18, accuracy: 0.001)
    }

    func testBottomResizePreviewExpandsDownwardAndKeepsMinimumHeight() {
        let expanded = CommandCenterCalendarLayout.resizePreview(
            edge: .bottom,
            translationHeight: 26,
            originalHeight: 52
        )

        XCTAssertEqual(expanded.offsetY, 0, accuracy: 0.001)
        XCTAssertEqual(expanded.height, 78, accuracy: 0.001)

        let collapsed = CommandCenterCalendarLayout.resizePreview(
            edge: .bottom,
            translationHeight: -80,
            originalHeight: 52
        )

        XCTAssertEqual(collapsed.offsetY, 0, accuracy: 0.001)
        XCTAssertEqual(collapsed.height, 18, accuracy: 0.001)
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

    func testEntryDensityCollapsesShortOrNarrowBlocks() {
        XCTAssertEqual(CommandCenterCalendarLayout.entryDensity(width: 120, height: 48), .expanded)
        XCTAssertEqual(CommandCenterCalendarLayout.entryDensity(width: 120, height: 28), .compact)
        XCTAssertEqual(CommandCenterCalendarLayout.entryDensity(width: 58, height: 48), .compact)
    }

    func testWeeklyRecurrenceProducesEveryMatchingDayInVisibleWeek() throws {
        let rule = RecurrenceRule.weekly(on: [.monday, .wednesday, .friday])
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 27, hour: 9)))
        let intervalStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 27)))
        let intervalEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 4)))

        let dates = rule.occurrenceDates(
            in: DateInterval(start: intervalStart, end: intervalEnd),
            startingFrom: start,
            calendar: calendar
        )

        XCTAssertEqual(dates.map { calendar.component(.weekday, from: $0) }, [2, 4, 6])
        XCTAssertTrue(dates.allSatisfy { calendar.component(.hour, from: $0) == 9 })
    }

    func testWeekdayRecurrenceSkipsWeekendInVisibleWeek() throws {
        let rule = RecurrenceRule.weekdays()
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 27, hour: 9)))
        let intervalStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 27)))
        let intervalEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 4)))

        let dates = rule.occurrenceDates(
            in: DateInterval(start: intervalStart, end: intervalEnd),
            startingFrom: start,
            calendar: calendar
        )

        XCTAssertEqual(dates.map { calendar.component(.weekday, from: $0) }, [2, 3, 4, 5, 6])
    }

    func testTodaySectionsKeepUntimedTasksOnTheirPlannedDayOnly() throws {
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 2)))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))

        let plannedToday = task("today", title: "Untimed today", whenDate: today, createdAt: yesterday)
        let plannedTomorrow = task("tomorrow", title: "Untimed tomorrow", whenDate: tomorrow, createdAt: today)
        let noPlannedDay = task("no-date", title: "No planned day", createdAt: today)

        let sections = CommandCenterTodayTaskSectioning.sectionTasks(
            [plannedToday, plannedTomorrow, noPlannedDay],
            selectedDate: today,
            today: today,
            calendar: calendar
        )

        XCTAssertEqual(sections.unscheduled.map(\.uuid), ["today"])
        XCTAssertTrue(sections.overdue.isEmpty)
        XCTAssertTrue(sections.scheduled.isEmpty)
    }

    func testCalendarDisplayDateIncludesDayOnlyScheduledTasks() throws {
        let plannedDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 19)))
        let timedStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 19, hour: 9)))

        let dayOnly = task("day-only", title: "Day only", whenDate: plannedDay)
        let timed = task("timed", title: "Timed", scheduledStart: timedStart, whenDate: plannedDay)

        XCTAssertEqual(dayOnly.calendarDisplayDate, plannedDay)
        XCTAssertEqual(timed.calendarDisplayDate, timedStart)
    }

    func testCalendarDisplayDateMovesStaleTimedBlockOntoPlannedDay() throws {
        let plannedDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 19)))
        let staleStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 18, hour: 9)))
        let staleEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 18, hour: 9, minute: 30)))
        let expectedStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 19, hour: 9)))
        let expectedEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 19, hour: 9, minute: 30)))

        let timed = task(
            "stale-timed",
            title: "Stale timed",
            scheduledStart: staleStart,
            scheduledEnd: staleEnd,
            whenDate: plannedDay
        )

        XCTAssertEqual(timed.calendarDisplayDate, expectedStart)
        XCTAssertEqual(timed.calendarStart(using: calendar), expectedStart)
        XCTAssertEqual(timed.calendarEnd(using: calendar), expectedEnd)
    }

    func testTodaySectionsTreatStaleCalendarTimeAsScheduledWhenPlannedToday() throws {
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 19)))
        let staleStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 18, hour: 9)))

        let staleTimedTask = task(
            "stale-timed",
            title: "Stale timed",
            scheduledStart: staleStart,
            whenDate: today,
            dueDate: today
        )

        let sections = CommandCenterTodayTaskSectioning.sectionTasks(
            [staleTimedTask],
            selectedDate: today,
            today: today,
            calendar: calendar
        )

        XCTAssertTrue(sections.overdue.isEmpty)
        XCTAssertEqual(sections.scheduled.map { $0.uuid }, ["stale-timed"])
    }

    func testTodaySectionsMovePastUntimedTasksToOverdue() throws {
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 2)))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))

        let overdue = task("overdue", title: "Untimed yesterday", whenDate: yesterday)
        let todayTask = task("today", title: "Untimed today", whenDate: today)
        let scheduledStart = try XCTUnwrap(calendar.date(byAdding: .hour, value: 9, to: today))
        let scheduled = task("scheduled", title: "Scheduled today", scheduledStart: scheduledStart)
        let future = task("future", title: "Future untimed", whenDate: tomorrow)

        let sections = CommandCenterTodayTaskSectioning.sectionTasks(
            [todayTask, scheduled, overdue, future],
            selectedDate: today,
            today: today,
            calendar: calendar
        )

        XCTAssertEqual(sections.overdue.map(\.uuid), ["overdue"])
        XCTAssertEqual(sections.scheduled.map(\.uuid), ["scheduled"])
        XCTAssertEqual(sections.unscheduled.map(\.uuid), ["today"])
    }

    func testTodaySectionsSuppressRecurringOverdueWhenSameParentRepeatsToday() throws {
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 2)))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let todayStart = try XCTUnwrap(calendar.date(byAdding: .hour, value: 9, to: today))
        let yesterdayStart = try XCTUnwrap(calendar.date(byAdding: .hour, value: 9, to: yesterday))

        let oldRecurring = task(
            "old-recurring",
            title: "Old repeat",
            scheduledStart: yesterdayStart,
            recurrenceParentUUID: "repeat-1"
        )
        let todayRecurring = task(
            "today-recurring",
            title: "Today repeat",
            scheduledStart: todayStart,
            recurrenceParentUUID: "repeat-1"
        )
        let normalOverdue = task("normal-overdue", title: "Normal overdue", whenDate: yesterday)
        let otherRecurring = task(
            "other-recurring",
            title: "Other repeat overdue",
            scheduledStart: yesterdayStart,
            recurrenceParentUUID: "repeat-2"
        )

        let sections = CommandCenterTodayTaskSectioning.sectionTasks(
            [oldRecurring, todayRecurring, normalOverdue, otherRecurring],
            selectedDate: today,
            today: today,
            calendar: calendar
        )

        XCTAssertEqual(sections.scheduled.map(\.uuid), ["today-recurring"])
        XCTAssertEqual(Set(sections.overdue.map(\.uuid)), ["other-recurring", "normal-overdue"])
    }

    func testFutureDaySectionsNeverMarkTodayTasksOverdue() throws {
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 2)))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))

        let plannedToday = task("today", title: "Untimed today", whenDate: today)
        let timedToday = task(
            "timed-today",
            title: "Timed today",
            scheduledStart: try XCTUnwrap(calendar.date(byAdding: .hour, value: 9, to: today))
        )
        let trulyOverdue = task("overdue", title: "Untimed yesterday", whenDate: yesterday)
        let plannedTomorrow = task("tomorrow", title: "Untimed tomorrow", whenDate: tomorrow)

        let sections = CommandCenterTodayTaskSectioning.sectionTasks(
            [plannedToday, timedToday, trulyOverdue, plannedTomorrow],
            selectedDate: tomorrow,
            today: today,
            calendar: calendar
        )

        XCTAssertTrue(sections.overdue.isEmpty, "Browsing a future day must never brand live tasks as overdue")
        XCTAssertTrue(sections.scheduled.isEmpty)
        XCTAssertEqual(sections.unscheduled.map(\.uuid), ["tomorrow"])
    }

    func testPastDaySectionsShowOnlyThatDaysTasksWithoutOverdue() throws {
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 2)))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let twoDaysAgo = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: today))

        let onThatDay = task("yesterday", title: "Yesterday task", whenDate: yesterday)
        let older = task("older", title: "Older task", whenDate: twoDaysAgo)

        let sections = CommandCenterTodayTaskSectioning.sectionTasks(
            [onThatDay, older],
            selectedDate: yesterday,
            today: today,
            calendar: calendar
        )

        XCTAssertTrue(sections.overdue.isEmpty, "Overdue belongs to today's page only")
        XCTAssertEqual(sections.unscheduled.map(\.uuid), ["yesterday"])
    }

    func testDateSelectionAdvancesWhenViewingPreviousCurrentDayAtMidnight() throws {
        let previousToday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 9)))
        let newToday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 3, hour: 1)))

        let selected = CommandCenterDateSelection.dateForCurrentDayChange(
            selectedDate: previousToday,
            previousToday: previousToday,
            newToday: newToday,
            calendar: calendar
        )

        XCTAssertTrue(calendar.isDate(selected, inSameDayAs: newToday))
    }

    func testDateSelectionKeepsManualFutureSelectionAtMidnight() throws {
        let previousToday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 9)))
        let newToday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 3, hour: 1)))
        let manualFuture = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 4, hour: 10)))

        let selected = CommandCenterDateSelection.dateForCurrentDayChange(
            selectedDate: manualFuture,
            previousToday: previousToday,
            newToday: newToday,
            calendar: calendar
        )

        XCTAssertTrue(calendar.isDate(selected, inSameDayAs: manualFuture))
    }

    func testReschedulingTimedTaskMovesCalendarTimeToTargetDay() throws {
        let yesterday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 18, hour: 9)))
        let targetDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 19)))
        let originalEnd = try XCTUnwrap(calendar.date(byAdding: .minute, value: 30, to: yesterday))
        var metadata = TaskMetadata()
        metadata.scheduledStart = PlannerumFormatters.iso8601.string(from: yesterday)
        metadata.scheduledEnd = PlannerumFormatters.iso8601.string(from: originalEnd)
        metadata.startTime = metadata.scheduledStart
        metadata.endTime = metadata.scheduledEnd
        metadata.durationMinutes = 30
        metadata.schedulingState = "anytime"

        CommandCenterTaskScheduling.reschedule(&metadata, toDate: targetDay, calendar: calendar)

        let rescheduledStart = try XCTUnwrap(metadata.scheduledStart.flatMap(PlannerumFormatters.iso8601.date(from:)))
        let rescheduledEnd = try XCTUnwrap(metadata.scheduledEnd.flatMap(PlannerumFormatters.iso8601.date(from:)))
        let whenDate = try XCTUnwrap(metadata.whenDate.flatMap(PlannerumFormatters.iso8601.date(from:)))

        XCTAssertEqual(calendar.component(.day, from: rescheduledStart), 19)
        XCTAssertEqual(calendar.component(.hour, from: rescheduledStart), 9)
        XCTAssertEqual(calendar.component(.minute, from: rescheduledStart), 0)
        XCTAssertEqual(rescheduledEnd.timeIntervalSince(rescheduledStart), 30 * 60, accuracy: 0.001)
        XCTAssertEqual(calendar.startOfDay(for: whenDate), targetDay)
        XCTAssertEqual(metadata.startTime, metadata.scheduledStart)
        XCTAssertEqual(metadata.endTime, metadata.scheduledEnd)
        XCTAssertNil(metadata.schedulingState)
    }

    func testUnschedulingTimedTaskClearsCalendarTimeFields() throws {
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 18, hour: 9)))
        let end = try XCTUnwrap(calendar.date(byAdding: .minute, value: 30, to: start))
        var metadata = TaskMetadata()
        metadata.scheduledStart = PlannerumFormatters.iso8601.string(from: start)
        metadata.scheduledEnd = PlannerumFormatters.iso8601.string(from: end)
        metadata.startTime = metadata.scheduledStart
        metadata.endTime = metadata.scheduledEnd
        metadata.durationMinutes = 30
        metadata.schedulingState = "anytime"

        CommandCenterTaskScheduling.reschedule(&metadata, toDate: nil, calendar: calendar)

        XCTAssertNil(metadata.dueDate)
        XCTAssertNil(metadata.focusDate)
        XCTAssertNil(metadata.whenDate)
        XCTAssertNil(metadata.scheduledStart)
        XCTAssertNil(metadata.scheduledEnd)
        XCTAssertNil(metadata.startTime)
        XCTAssertNil(metadata.endTime)
        XCTAssertNil(metadata.durationMinutes)
        XCTAssertNil(metadata.schedulingState)
    }

    private func task(
        _ uuid: String,
        title: String,
        scheduledStart: Date? = nil,
        scheduledEnd: Date? = nil,
        whenDate: Date? = nil,
        dueDate: Date? = nil,
        recurrenceParentUUID: String? = nil,
        createdAt: Date? = nil
    ) -> TaskViewModel {
        TaskViewModel(
            uuid: uuid,
            title: title,
            dueDate: dueDate,
            recurrenceParentUUID: recurrenceParentUUID,
            isRecurring: recurrenceParentUUID != nil,
            scheduledStart: scheduledStart,
            scheduledEnd: scheduledEnd,
            whenDate: whenDate,
            createdAt: createdAt ?? Date(timeIntervalSince1970: 0)
        )
    }
}

final class CommandCenterHabitEnginePersistenceTests: XCTestCase {
    func testHabitCompletionRecordIgnoresAgentConversationSystemEvent() {
        let atom = Atom.new(
            type: .systemEvent,
            title: "Agent Conversation: telegram",
            structured: #"{"createdAt":"2026-06-13T00:00:00Z","summary":"hello","topics":["ops"]}"#,
            metadata: #"{"subtype":"agent_conversation","conversationId":"conv-1"}"#
        )

        XCTAssertNil(CommandCenterHabitPersistence.habitCompletionRecord(from: atom))
    }

    func testHabitCompletionRecordDecodesHabitCompletionSystemEvent() throws {
        let record = HabitCompletionRecord(
            id: "record-1",
            habitUUID: "habit-1",
            date: "2026-06-13T00:00:00Z",
            source: .manual,
            taskUUID: nil,
            countDelta: 1,
            trackedMinutesSnapshot: 30
        )
        let atom = Atom.new(
            type: .systemEvent,
            title: "Habit completion"
        ).withStructured(record)

        XCTAssertEqual(CommandCenterHabitPersistence.habitCompletionRecord(from: atom), record)
    }

    func testDeepWorkSessionDecodesCurrentMetadata() throws {
        let started = try XCTUnwrap(ISO8601.date(from: "2026-06-13T08:00:00Z"))
        let metadata = DeepWorkSessionMetadata(
            taskUUID: "task-1",
            startedAt: ISO8601.string(from: started),
            endedAt: nil,
            plannedMinutes: 60,
            actualMinutes: 50,
            focusScore: 82,
            distractionCount: nil,
            intent: "deepWork",
            intentUUID: nil,
            intentTitleSnapshot: nil,
            habitUUID: "habit-1",
            habitTitleSnapshot: nil,
            outputAtomUUIDs: nil,
            xpEarned: nil,
            notes: nil
        )
        let metadataJSON = try XCTUnwrap(String(data: JSONEncoder().encode(metadata), encoding: .utf8))
        let atom = Atom.new(type: .deepWorkBlock, title: "Current session", metadata: metadataJSON)

        let session = try XCTUnwrap(CommandCenterHabitPersistence.deepWorkSession(from: atom))
        XCTAssertEqual(session.startedAt, started)
        XCTAssertEqual(session.plannedMinutes, 60)
        XCTAssertEqual(session.actualMinutes, 50)
        XCTAssertEqual(session.focusScore, 82)
        XCTAssertEqual(session.habitUUID, "habit-1")
    }

    func testDeepWorkSessionNormalizesLegacyTimerMetadata() throws {
        let started = try XCTUnwrap(ISO8601.date(from: "2026-06-13T09:00:00Z"))
        var atom = Atom.new(
            type: .deepWorkBlock,
            title: "Legacy timer session",
            metadata: #"{"sessionType":"deepWork","targetMinutes":45,"durationMinutes":30,"xpAwarded":20,"taskId":"task-1"}"#
        )
        atom.createdAt = ISO8601.string(from: started)

        let session = try XCTUnwrap(CommandCenterHabitPersistence.deepWorkSession(from: atom))
        XCTAssertEqual(session.startedAt, started)
        XCTAssertEqual(session.plannedMinutes, 45)
        XCTAssertEqual(session.actualMinutes, 30)
        XCTAssertNil(session.focusScore)
        XCTAssertNil(session.habitUUID)
    }
}
