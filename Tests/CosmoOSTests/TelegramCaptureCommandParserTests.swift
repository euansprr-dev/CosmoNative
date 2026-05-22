import XCTest
@testable import CosmoOS

final class TelegramCaptureCommandParserTests: XCTestCase {
    func testParsesCustomLanePrefix() {
        let parsed = TelegramCaptureCommandParser.parse("Swipe bank: This hook structure is insane")

        XCTAssertEqual(parsed?.kind, .route)
        XCTAssertEqual(parsed?.destinationName, "Swipe bank")
        XCTAssertEqual(parsed?.subroute, .general)
        XCTAssertEqual(parsed?.body, "This hook structure is insane")
    }

    func testParsesDeepDiveSubroutePrefix() {
        let parsed = TelegramCaptureCommandParser.parse("bw/evidence: CO2 tolerance affects anxiety")

        XCTAssertEqual(parsed?.destinationName, "bw")
        XCTAssertEqual(parsed?.subroute, .evidence)
        XCTAssertEqual(parsed?.body, "CO2 tolerance affects anxiety")
    }

    func testAllowsEmptyBodyForMediaPrefix() {
        let parsed = TelegramCaptureCommandParser.parse("UI inspiration:", allowsEmptyBody: true)

        XCTAssertEqual(parsed?.destinationName, "UI inspiration")
        XCTAssertEqual(parsed?.body, "")
    }

    func testRejectsEmptyBodyWithoutMedia() {
        XCTAssertNil(TelegramCaptureCommandParser.parse("UI inspiration:", allowsEmptyBody: false))
    }

    func testParsesCreateLaneAndCapture() {
        let parsed = TelegramCaptureCommandParser.parse(
            "Create a new inbox named “Book Covers” and capture this: love this cover",
            allowsEmptyBody: true
        )

        XCTAssertEqual(parsed?.kind, .createLane)
        XCTAssertEqual(parsed?.destinationName, "Book Covers")
        XCTAssertEqual(parsed?.requestedLaneType, .mediaSwipeLane)
        XCTAssertEqual(parsed?.body, "love this cover")
        XCTAssertEqual(parsed?.shouldCaptureRemainder, true)
    }

    func testParsesCreateTaskLane() {
        let parsed = TelegramCaptureCommandParser.parse(
            "Create a lane called “Vietnam admin” for tasks and save this file",
            allowsEmptyBody: true
        )

        XCTAssertEqual(parsed?.kind, .createLane)
        XCTAssertEqual(parsed?.destinationName, "Vietnam admin")
        XCTAssertEqual(parsed?.requestedLaneType, .taskLane)
    }

    func testParsesNaturalLanguageCreateLaneAndCapture() {
        let parsed = TelegramCaptureCommandParser.parse(
            "Make a new capture lane called Travel and capture this to it.\nDa Nang",
            allowsEmptyBody: true
        )

        XCTAssertEqual(parsed?.kind, .createLane)
        XCTAssertEqual(parsed?.destinationName, "Travel")
        XCTAssertEqual(parsed?.body, "Da Nang")
        XCTAssertEqual(parsed?.shouldCaptureRemainder, true)
    }
}
