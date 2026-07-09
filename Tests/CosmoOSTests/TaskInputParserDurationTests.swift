// Tests for the quick-add duration grammar ("for 2 hours", "for 45m") that
// the ⌘K task composer and Command Center capture row both parse.

import XCTest
@testable import CosmoOS

@MainActor
final class TaskInputParserDurationTests: XCTestCase {
    func testForHoursPhrase() {
        let result = TaskInputParser.parse("Deep edit pass for 2 hours")
        XCTAssertEqual(result.durationMinutes, 120)
        XCTAssertEqual(result.title, "Deep edit pass")
    }

    func testForFractionalHours() {
        let result = TaskInputParser.parse("Outline sprint for 1.5h")
        XCTAssertEqual(result.durationMinutes, 90)
        XCTAssertEqual(result.title, "Outline sprint")
    }

    func testForMinutes() {
        let result = TaskInputParser.parse("Inbox sweep for 45m")
        XCTAssertEqual(result.durationMinutes, 45)
        XCTAssertEqual(result.title, "Inbox sweep")
    }

    func testForHoursAndMinutes() {
        let result = TaskInputParser.parse("Storyboard block for 1h 30m")
        XCTAssertEqual(result.durationMinutes, 90)
        XCTAssertEqual(result.title, "Storyboard block")
    }

    func testDurationCoexistsWithDateAndTime() {
        let result = TaskInputParser.parse("Filming session tomorrow at 3pm for 2 hours")
        XCTAssertEqual(result.durationMinutes, 120)
        XCTAssertNotNil(result.dueDate)
        XCTAssertNotNil(result.scheduledTime)
        XCTAssertEqual(result.title, "Filming session")
    }

    func testNoDurationLeavesTitleAlone() {
        let result = TaskInputParser.parse("Plan for the launch")
        XCTAssertNil(result.durationMinutes)
        XCTAssertEqual(result.title, "Plan for the launch")
    }
}
