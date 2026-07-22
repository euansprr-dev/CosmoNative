// Tests for the capture wash scan: captureWashTokens mirrors `parse` and
// reports the utf16 range of every token a submit would consume — dates,
// times, durations, recurrence, priority, tags, slash commands — plus intent
// keywords (reported but never stripped), against the ORIGINAL input.

import XCTest
@testable import CosmoOS

@MainActor
final class TaskInputParserCaptureWashTests: XCTestCase {

    func testEmptyInputHasNoTokens() {
        XCTAssertTrue(TaskInputParser.captureWashTokens("").isEmpty)
    }

    func testDurationTimeAndDateAllReport() {
        let tokens = TaskInputParser.captureWashTokens("gym tomorrow at 6pm for 1h")
        XCTAssertEqual(tokens.map(\.kind), [.duration, .time, .date])
        XCTAssertEqual(tokens[0].utf16Range, 20..<26) // "for 1h"
        XCTAssertEqual(tokens[1].utf16Range, 13..<19) // "at 6pm"
        XCTAssertEqual(tokens[2].utf16Range, 4..<12)  // "tomorrow"
    }

    func testRecurrencePhraseAndTime() {
        let tokens = TaskInputParser.captureWashTokens("meditate every day at 7am")
        XCTAssertEqual(tokens.map(\.kind), [.recurrence, .time])
        XCTAssertEqual(tokens[0].utf16Range, 9..<18)  // "every day"
        XCTAssertEqual(tokens[1].utf16Range, 19..<25) // "at 7am"
    }

    func testWeekdayListRecurrence() {
        let tokens = TaskInputParser.captureWashTokens("Water plants every mon, wed")
        XCTAssertEqual(tokens.map(\.kind), [.recurrence])
        XCTAssertEqual(tokens[0].utf16Range, 13..<27) // "every mon, wed"
    }

    func testPriorityIsCaseSensitive() {
        let tokens = TaskInputParser.captureWashTokens("Ship p1")
        XCTAssertEqual(tokens.map(\.kind), [.priority(.critical)])
        XCTAssertEqual(tokens[0].utf16Range, 5..<7)

        XCTAssertTrue(TaskInputParser.captureWashTokens("Ship P1").isEmpty)
    }

    func testProjectAndHeadingTags() {
        let tokens = TaskInputParser.captureWashTokens("Edit reel #content +hooks")
        XCTAssertEqual(tokens.map(\.kind), [.projectTag, .headingTag])
        XCTAssertEqual(tokens[0].utf16Range, 10..<18) // "#content"
        XCTAssertEqual(tokens[1].utf16Range, 19..<25) // "+hooks"
    }

    func testSlashCommands() {
        let someday = TaskInputParser.captureWashTokens("/someday journal ideas")
        XCTAssertEqual(someday.map(\.kind), [.schedulingState("someday")])
        XCTAssertEqual(someday[0].utf16Range, 0..<8)

        let morning = TaskInputParser.captureWashTokens("Stretch /morning")
        XCTAssertEqual(morning.map(\.kind), [.timeOfDay("morning")])
        XCTAssertEqual(morning[0].utf16Range, 8..<16)
    }

    func testIntentKeywordReportsWithoutConsuming() {
        let tokens = TaskInputParser.captureWashTokens("write essay")
        XCTAssertEqual(tokens.map(\.kind), [.intent(.writeContent)])
        XCTAssertEqual(tokens[0].utf16Range, 0..<5)

        // Mid-word never matches — mirrors `parse`'s start-or-after-space rule.
        XCTAssertTrue(TaskInputParser.captureWashTokens("rewrite essay").isEmpty)
    }

    func testDeadlinePhraseSwallowsItsDateWord() {
        let tokens = TaskInputParser.captureWashTokens("Ship deadline: friday")
        XCTAssertEqual(tokens.map(\.kind), [.deadline])
        XCTAssertEqual(tokens[0].utf16Range, 5..<21) // "deadline: friday"
    }

    func testMentionTextIsOpaque() {
        let mention = RichMention(
            entityUUID: "u-1", entityID: nil, entityType: .idea, titleSnapshot: "Monday plan"
        )
        let tokens = TaskInputParser.captureWashTokens("Refine @Monday plan", mentions: [mention])
        XCTAssertTrue(tokens.isEmpty)
    }
}
