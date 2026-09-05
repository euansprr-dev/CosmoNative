// Tests/CosmoOSTests/ClientCadenceTests.swift
// The cadence parse table is a contract: every phrase the dossier field
// accepts maps to one weekly target, and anything else parses to nil —
// a guessed quota is worse than no quota.

import XCTest
@testable import CosmoOS

final class ClientCadenceTests: XCTestCase {

    // MARK: - Parse table

    func testFixedPhrasesMapToWeeklyTargets() {
        let table: [(String, Int)] = [
            ("daily", 7), ("Every day", 7), ("everyday", 7), ("7x", 7),
            ("weekly", 1), ("once a week", 1), ("1x", 1),
            ("twice a week", 2), ("2 a week", 2), ("twice weekly", 2),
            ("weekdays", 5), ("every weekday", 5),
            ("every other day", 3),
        ]
        for (phrase, expected) in table {
            XCTAssertEqual(ClientCadence.parse(phrase)?.perWeek, expected, "\"\(phrase)\" should parse to \(expected)")
        }
    }

    func testNumericWeeklyForms() {
        let table: [(String, Int)] = [
            ("3x/week", 3), ("3x / week", 3), ("3 per week", 3), ("4x a week", 4),
            ("2/wk", 2), ("5 x week", 5), ("3xw", 3), ("3x weekly", 3),
            ("6 each week", 6), ("3X/WEEK", 3), ("  3x/week  ", 3), ("3x", 3),
        ]
        for (phrase, expected) in table {
            XCTAssertEqual(ClientCadence.parse(phrase)?.perWeek, expected, "\"\(phrase)\" should parse to \(expected)")
        }
    }

    func testUnrecognisedPhrasesParseToNil() {
        for phrase in ["", "   ", "sometimes", "monthly", "3x/month", "0x/week", "when inspired", "twice daily"] {
            XCTAssertNil(ClientCadence.parse(phrase), "\"\(phrase)\" must not guess a cadence")
        }
        XCTAssertNil(ClientCadence.parse(nil))
    }

    func testZeroPerWeekIsNotACadence() {
        XCTAssertNil(ClientCadence(perWeek: 0))
        XCTAssertNil(ClientCadence(perWeek: -2))
        XCTAssertEqual(ClientCadence(perWeek: 3)?.perWeek, 3)
    }

    // MARK: - Quota

    func testQuotaReportsMetAgainstTargetUnclamped() throws {
        let cadence = try XCTUnwrap(ClientCadence.parse("3x/week"))
        let under = cadence.quota(scheduledOrShipped: 1)
        XCTAssertEqual(under.met, 1)
        XCTAssertEqual(under.target, 3)

        let over = cadence.quota(scheduledOrShipped: 4)
        XCTAssertEqual(over.met, 4, "shipping past the target is honest news, not clamped")
        XCTAssertEqual(over.target, 3)

        XCTAssertEqual(cadence.quota(scheduledOrShipped: -1).met, 0)
    }

    // MARK: - Week start

    private var sundayFirstUTC: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1   // Sunday-first on purpose — the helper must override it.
        return calendar
    }

    private func date(_ iso: String) throws -> Date {
        try XCTUnwrap(ISO8601.date(from: iso))
    }

    func testWeekStartIsMondayRegardlessOfCalendarFirstWeekday() throws {
        let calendar = sundayFirstUTC
        let monday = try date("2026-08-31T00:00:00Z")

        XCTAssertEqual(ClientCadence.weekStart(for: try date("2026-09-02T15:30:00Z"), calendar: calendar), monday, "a Wednesday belongs to the Monday before it")
        XCTAssertEqual(ClientCadence.weekStart(for: try date("2026-09-06T23:59:00Z"), calendar: calendar), monday, "Sunday closes the Monday-start week, it does not open the next")
        XCTAssertEqual(ClientCadence.weekStart(for: monday, calendar: calendar), monday)
        XCTAssertEqual(ClientCadence.weekStart(for: try date("2026-09-07T00:00:00Z"), calendar: calendar), try date("2026-09-07T00:00:00Z"))
    }
}
