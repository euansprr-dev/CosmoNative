import XCTest
@testable import CosmoOS

final class CommandCenterComposerTests: XCTestCase {
    func testParseDateInputHandlesTodayTomorrowAndNextWeekday() {
        let today = CommandCenterScheduleUtilities.parseDateInput("today")
        let tomorrow = CommandCenterScheduleUtilities.parseDateInput("tomorrow")
        let nextMonday = CommandCenterScheduleUtilities.parseDateInput("next monday")

        XCTAssertNotNil(today)
        XCTAssertNotNil(tomorrow)
        XCTAssertNotNil(nextMonday)

        if let today {
            XCTAssertTrue(Calendar.current.isDateInToday(today))
        }

        if let tomorrow {
            XCTAssertTrue(Calendar.current.isDateInTomorrow(tomorrow))
        }

        if let nextMonday {
            XCTAssertEqual(Calendar.current.component(.weekday, from: nextMonday), DayOfWeek.monday.rawValue)
            XCTAssertGreaterThan(nextMonday, Calendar.current.startOfDay(for: Date()))
        }
    }

    func testParseDateInputRollsPastMonthDayIntoNextYear() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let month = Calendar.current.component(.month, from: yesterday)
        let day = Calendar.current.component(.day, from: yesterday)
        let input = "\(month)/\(day)"

        let parsed = CommandCenterScheduleUtilities.parseDateInput(input)

        XCTAssertNotNil(parsed)

        if let parsed {
            XCTAssertEqual(Calendar.current.component(.month, from: parsed), month)
            XCTAssertEqual(Calendar.current.component(.day, from: parsed), day)
            XCTAssertGreaterThanOrEqual(parsed, Calendar.current.startOfDay(for: Date()))
        }
    }

    func testHabitDraftKeywordsTrimAndDropEmptyValues() {
        var draft = CommandCenterHabitEditorDraft()
        draft.keywordInput = " write,  draft ,, article  , "

        XCTAssertEqual(draft.keywords, ["write", "draft", "article"])
    }

    func testIntentBehaviorTemplateMapsToLegacyIntent() {
        XCTAssertEqual(IntentBehaviorTemplate.writeContent.taskIntent, .writeContent)
        XCTAssertEqual(IntentBehaviorTemplate(.research), .research)
        XCTAssertNil(IntentBehaviorTemplate(.general))
    }

    @MainActor
    func testRecurringInstanceMatchParsesPlannerumFractionalDates() throws {
        let calendar = Calendar(identifier: .gregorian)
        let occurrence = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 8)))

        var metadata = TaskMetadata()
        metadata.recurrenceParentUUID = "template-1"
        metadata.focusDate = PlannerumFormatters.iso8601.string(from: occurrence)

        XCTAssertTrue(
            TaskRecurrenceEngine.recurrenceInstanceMatches(
                templateUUID: "template-1",
                date: occurrence,
                metadata: metadata,
                calendar: calendar
            )
        )
        XCTAssertFalse(
            TaskRecurrenceEngine.recurrenceInstanceMatches(
                templateUUID: "template-1",
                date: try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: occurrence)),
                metadata: metadata,
                calendar: calendar
            )
        )
    }

    @MainActor
    func testRecurringCleanupDropsPastRepeat() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 8))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        let deletions = TaskRecurrenceEngine.generatedInstanceCleanupDeletions(
            from: [
                .init(uuid: "daily-yesterday", parentUUID: "daily", occurrenceDate: yesterday, isCompleted: false, createdAt: yesterday),
                .init(uuid: "daily-today", parentUUID: "daily", occurrenceDate: today, isCompleted: false, createdAt: today),
                .init(uuid: "daily-tomorrow", parentUUID: "daily", occurrenceDate: tomorrow, isCompleted: false, createdAt: tomorrow),
                .init(uuid: "weekly-yesterday", parentUUID: "weekly", occurrenceDate: yesterday, isCompleted: false, createdAt: yesterday),
                .init(uuid: "completed-yesterday", parentUUID: "daily", occurrenceDate: yesterday, isCompleted: true, createdAt: yesterday)
            ],
            referenceDate: today,
            calendar: calendar
        )

        XCTAssertEqual(deletions, ["daily-yesterday"])
    }

    @MainActor
    func testRecurringCleanupDropsSameDayDuplicate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 8))!
        let earlyCreate = calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 8))!
        let lateCreate = calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 9))!

        let deletions = TaskRecurrenceEngine.generatedInstanceCleanupDeletions(
            from: [
                .init(uuid: "first", parentUUID: "daily", occurrenceDate: today, isCompleted: false, createdAt: earlyCreate),
                .init(uuid: "second", parentUUID: "daily", occurrenceDate: today, isCompleted: false, createdAt: lateCreate)
            ],
            referenceDate: today,
            calendar: calendar
        )

        XCTAssertEqual(deletions, ["second"])
    }

    @MainActor
    func testIntentEngineReturnsExplicitUnassignedPresentation() {
        let engine = CommandCenterIntentEngine()

        let presentation = engine.resolvedPresentation(intentUUID: nil, legacyIntentRaw: TaskIntent.general.rawValue)

        XCTAssertTrue(presentation.isUnassigned)
        XCTAssertEqual(presentation.title, "Unassigned")
        XCTAssertNil(presentation.behaviorTemplate)
    }
}
