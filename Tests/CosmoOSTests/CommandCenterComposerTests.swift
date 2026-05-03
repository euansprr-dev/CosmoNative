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
    func testIntentEngineReturnsExplicitUnassignedPresentation() {
        let engine = CommandCenterIntentEngine()

        let presentation = engine.resolvedPresentation(intentUUID: nil, legacyIntentRaw: TaskIntent.general.rawValue)

        XCTAssertTrue(presentation.isUnassigned)
        XCTAssertEqual(presentation.title, "Unassigned")
        XCTAssertNil(presentation.behaviorTemplate)
    }
}
