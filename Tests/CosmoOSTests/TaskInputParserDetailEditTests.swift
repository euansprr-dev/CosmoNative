// Tests for the detail-panel title-edit grammar: scheduling tokens typed into
// an existing task's title ("tomorrow", "deadline: friday", "/evening", "p1",
// "every monday") are stripped and reported with highlight ranges, while
// project tags, durations and mention text pass through untouched.

import XCTest
@testable import CosmoOS

@MainActor
final class TaskInputParserDetailEditTests: XCTestCase {

    func testTomorrowSetsWhenAndStrips() {
        let edit = TaskInputParser.parseDetailEdit("Call mom tomorrow")
        XCTAssertEqual(edit.title, "Call mom")
        let expected = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        XCTAssertNotNil(edit.whenDate)
        XCTAssertTrue(Calendar.current.isDate(edit.whenDate!, inSameDayAs: expected))
        XCTAssertEqual(edit.tokens.count, 1)
        XCTAssertEqual(edit.tokens[0].kind, .when)
        // "tomorrow" spans utf16 9..<17 in the original text
        XCTAssertEqual(edit.tokens[0].utf16Range, 9..<17)
    }

    func testDeadlinePhraseWinsOverBareDate() {
        let edit = TaskInputParser.parseDetailEdit("Ship draft deadline: friday")
        XCTAssertEqual(edit.title, "Ship draft")
        XCTAssertNotNil(edit.deadline)
        XCTAssertNil(edit.whenDate)
        XCTAssertEqual(edit.tokens.map(\.kind), [.deadline])
    }

    func testSlashCommandsAndPriority() {
        let edit = TaskInputParser.parseDetailEdit("Journal /evening p1")
        XCTAssertEqual(edit.title, "Journal")
        XCTAssertEqual(edit.timeOfDay, "evening")
        XCTAssertEqual(edit.priority, .critical)
    }

    func testRecurrencePhraseSeedsWhenDate() {
        let edit = TaskInputParser.parseDetailEdit("Water plants every monday")
        XCTAssertEqual(edit.title, "Water plants")
        XCTAssertNotNil(edit.recurrenceRule)
        XCTAssertNotNil(edit.whenDate)
    }

    func testMentionTextIsOpaque() {
        let mention = RichMention(
            entityUUID: "u-1", entityID: nil, entityType: .idea, titleSnapshot: "Monday plan"
        )
        let edit = TaskInputParser.parseDetailEdit("Refine @Monday plan", mentions: [mention])
        XCTAssertNil(edit.whenDate)
        XCTAssertEqual(edit.title, "Refine @Monday plan")
        XCTAssertTrue(edit.tokens.isEmpty)
    }

    func testPlainTitlePassesThrough() {
        let edit = TaskInputParser.parseDetailEdit("Develop @Boomers who got rich for Ben")
        XCTAssertEqual(edit.title, "Develop @Boomers who got rich for Ben")
        XCTAssertFalse(edit.hasSchedulingChanges)
        XCTAssertTrue(edit.tokens.isEmpty)
    }

    func testDurationAndProjectTagAreLeftAlone() {
        let edit = TaskInputParser.parseDetailEdit("Edit reel for 2 hours #content")
        XCTAssertEqual(edit.title, "Edit reel for 2 hours #content")
        XCTAssertFalse(edit.hasSchedulingChanges)
    }

    func testMonthDayDate() {
        let edit = TaskInputParser.parseDetailEdit("Send invoices aug 3")
        XCTAssertEqual(edit.title, "Send invoices")
        XCTAssertNotNil(edit.whenDate)
        let components = Calendar.current.dateComponents([.month, .day], from: edit.whenDate!)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 3)
    }
}
