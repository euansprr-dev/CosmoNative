import XCTest
@testable import CosmoOS

final class CompanionJourneyTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 12))! }
    private func record(_ id: String, _ fields: [String: Any]) -> CompanionActivityRecord {
        .init(id: id, createdAt: "2026-09-05T10:00:00Z", metadata: String(decoding: try! JSONSerialization.data(withJSONObject: fields), as: UTF8.self))
    }
    func testOnlyRecordedTimeCountsAndDuplicateRecordsDoNot() {
        let seconds = record("saved", ["actualSeconds": 48])
        let snapshot = CompanionJourneySnapshot.make(focus: [
            seconds, seconds, record("planned", ["plannedMinutes": 25]),
            record("negative", ["actualSeconds": -50]),
            record("future", ["actualSeconds": 300, "startedAt": "2026-09-06T10:00:00Z"]),
            record("legacy", ["actualMinutes": 10])
        ], tasks: [], now: now, calendar: calendar)
        XCTAssertEqual(snapshot.totalSeconds, 648)
        XCTAssertEqual(snapshot.activeDays, 1)
        XCTAssertEqual(snapshot.days.count, 14)
        XCTAssertEqual(snapshot.today?.seconds, 648)
    }
    func testRecurringOccurrencesCountOncePerDayWithoutDoubleCountingTemplate() {
        let task = record("series", ["isCompleted": true, "completedAt": "2026-09-05T10:00:00Z", "completedOccurrences": [
            ["day": "2026-09-04", "completedAt": "2026-09-05T09:00:00Z"],
            ["day": "2026-09-04", "completedAt": "2026-09-05T09:10:00Z"],
            ["day": "2026-09-05", "completedAt": "2026-09-05T10:00:00Z"]
        ]])
        let snapshot = CompanionJourneySnapshot.make(focus: [], tasks: [task, task], now: now, calendar: calendar)
        XCTAssertEqual(snapshot.totalTasks, 2)
        XCTAssertEqual(snapshot.activeDays, 2)
        XCTAssertEqual(snapshot.today?.tasks, 1)
    }
    func testOpenAndReopenedTasksDoNotCount() {
        let snapshot = CompanionJourneySnapshot.make(focus: [], tasks: [
            record("open", ["isCompleted": false, "completedAt": "2026-09-05T10:00:00Z"]),
            record("missing", ["isCompleted": true]),
            record("done", ["isCompleted": true, "completedAt": "2026-09-05T10:00:00.123Z"])
        ], now: now, calendar: calendar)
        XCTAssertEqual(snapshot.totalTasks, 1)
    }
    func testGrowthThresholdsAndEarnedGrowthSurviveCorrections() {
        XCTAssertEqual([0,2,3,9,10,29,30,400].map(CompanionGrowth.earned(days:)),
                       [.beginning,.beginning,.budding,.budding,.flourishing,.flourishing,.wondrous,.wondrous])
        let earned = CompanionJourneyPreferences(earnedDays: 30)
        XCTAssertEqual(earned.merging(.init(earnedDays: 4)).earnedDays, 30)
    }
    func testIndependentRitualEditsMergeOnBothDevices() {
        var phone = CompanionJourneyPreferences(earnedDays: 10, tutorialComplete: true)
        var mac = CompanionJourneyPreferences(earnedDays: 3)
        phone.rituals[0] = .init(trigger: .taskCompleted, response: .nextStep, isEnabled: true, updatedAt: now)
        mac.rituals[1] = .init(trigger: .focusFinished, response: .celebrate, isEnabled: true, updatedAt: now)
        let result = phone.merging(mac)
        XCTAssertEqual(result, mac.merging(phone))
        XCTAssertEqual(result.earnedDays, 10)
        XCTAssertTrue(result.tutorialComplete)
        XCTAssertEqual(result.rituals.filter(\.isEnabled).count, 2)
        XCTAssertEqual(result.merging(result), result)
    }
    func testEqualTimestampMergeIsDeterministic() {
        var a = CompanionJourneyPreferences(), b = CompanionJourneyPreferences()
        a.rituals[0].response = .breathe
        b.rituals[0].response = .nextStep
        XCTAssertEqual(a.merging(b), b.merging(a))
    }
    func testHistoryUsesCalendarDaysAcrossDaylightSaving() {
        var cal = calendar
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let date = cal.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 12))!
        let snapshot = CompanionJourneySnapshot.make(focus: [
            record("before", ["startedAt": "2026-03-08T04:30:00Z", "actualSeconds": 60]),
            record("after", ["startedAt": "2026-03-08T07:30:00Z", "actualSeconds": 60])
        ], tasks: [], now: date, calendar: cal)
        XCTAssertEqual(snapshot.activeDays, 2)
        XCTAssertEqual(snapshot.days.suffix(3).map(\.seconds), [60,60,0])
    }
}
