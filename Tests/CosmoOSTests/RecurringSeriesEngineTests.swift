import XCTest
@testable import CosmoOS

/// Unit tests for the virtual-occurrence recurrence model (RecurringSeriesEngine).
/// Pure-projection tests need no DB; the completion test exercises the real atom store.
@MainActor
final class RecurringSeriesEngineTests: XCTestCase {

    private var createdUUIDs: [String] = []

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()

    override func tearDown() async throws {
        for uuid in createdUUIDs.reversed() {
            try? await AtomRepository.shared.hardDelete(uuid: uuid, confirmed: true)
        }
        createdUUIDs.removeAll()
        try await super.tearDown()
    }

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private func snap(
        rule: RecurrenceRule,
        start: Date,
        completed: [String] = [],
        skipped: [String] = [],
        hasTime: Bool = false
    ) -> RecurringSeriesEngine.SeriesSnapshot {
        .init(
            templateUUID: "t",
            title: "T",
            rule: rule,
            startDate: start,
            hasTimeOfDay: hasTime,
            durationMinutes: 30,
            completedDays: Set(completed),
            skippedDays: Set(skipped),
            overrides: [:]
        )
    }

    // MARK: - Day keys

    func testDayKeyIsStableYYYYMMDD() {
        XCTAssertEqual(RecurringSeriesEngine.dayKey(for: day(2026, 6, 9), calendar: cal), "2026-06-09")
        // time-of-day collapses to the same key
        XCTAssertEqual(RecurringSeriesEngine.dayKey(for: day(2026, 6, 9, hour: 23), calendar: cal), "2026-06-09")
    }

    // MARK: - Live occurrence (single-live invariant)

    func testLiveOccurrenceIsTodayWhenSeriesStartsToday() {
        // Anchored today with nothing done -> today is the single live (active) occurrence.
        let s = snap(rule: .daily(), start: day(2026, 6, 9))
        let live = RecurringSeriesEngine.liveOccurrence(for: s, asOf: day(2026, 6, 9), calendar: cal)
        XCTAssertEqual(live?.day, day(2026, 6, 9))
        XCTAssertEqual(live?.status, .active)
    }

    func testMissedDailyShowsSingleOldestOverdue() {
        // Anchored 5 days ago, nothing actioned -> exactly one overdue item (the oldest).
        let s = snap(rule: .daily(), start: day(2026, 6, 4))
        let live = RecurringSeriesEngine.liveOccurrence(for: s, asOf: day(2026, 6, 9), calendar: cal)
        XCTAssertEqual(live?.day, day(2026, 6, 4))
        XCTAssertEqual(live?.status, .overdue)
    }

    func testLiveSkipsCompletedAndSkippedDays() {
        let s = snap(
            rule: .daily(),
            start: day(2026, 6, 4),
            completed: ["2026-06-04"],
            skipped: ["2026-06-05"]
        )
        let live = RecurringSeriesEngine.liveOccurrenceDay(for: s, asOf: day(2026, 6, 9), calendar: cal)
        XCTAssertEqual(live, day(2026, 6, 6))
    }

    func testLiveAdvancesToFutureWhenAllPastActioned() {
        // Weekly Tuesday; both 6/2 and today 6/9 done -> next live is 6/16.
        let s = snap(
            rule: .weekly(on: [.tuesday]),
            start: day(2026, 6, 2),
            completed: ["2026-06-02", "2026-06-09"]
        )
        let live = RecurringSeriesEngine.liveOccurrenceDay(for: s, asOf: day(2026, 6, 9), calendar: cal)
        XCTAssertEqual(live, day(2026, 6, 16))
    }

    // MARK: - Projection across a window

    func testProjectionHasExactlyOneActionableOccurrence() {
        // Daily, 6/6 completed; window 6/6..6/13 viewed on 6/9.
        let s = snap(rule: .daily(), start: day(2026, 6, 6), completed: ["2026-06-06"])
        let occ = RecurringSeriesEngine.occurrences(
            for: s,
            in: DateInterval(start: day(2026, 6, 6), end: day(2026, 6, 13)),
            asOf: day(2026, 6, 9),
            calendar: cal
        )

        let actionable = occ.filter { $0.status == .overdue || $0.status == .active }
        XCTAssertEqual(actionable.count, 1, "Single-live invariant: only one actionable occurrence")

        func status(_ d: Date) -> RecurringSeriesEngine.OccurrenceStatus? {
            occ.first { cal.isDate($0.day, inSameDayAs: d) }?.status
        }
        XCTAssertEqual(status(day(2026, 6, 6)), .completed)
        XCTAssertEqual(status(day(2026, 6, 7)), .overdue)   // oldest un-actioned = live
        XCTAssertEqual(status(day(2026, 6, 8)), .missed)    // masked behind the live one
        XCTAssertEqual(status(day(2026, 6, 9)), .upcoming)  // today, masked behind older overdue
        XCTAssertEqual(status(day(2026, 6, 10)), .upcoming)
    }

    // MARK: - Completion (collapse-and-jump, DB-backed)

    func testCompleteCollapsesBacklogAndJumps() async throws {
        let today = day(2026, 6, 9, hour: 9)
        let start = cal.date(byAdding: .day, value: -3, to: today)! // 6/6 09:00

        var meta = TaskMetadata()
        meta.startTime = PlannerumFormatters.iso8601.string(from: start)
        meta.focusDate = PlannerumFormatters.iso8601.string(from: start)
        meta.dueDate = PlannerumFormatters.iso8601.string(from: start)
        meta.recurrence = RecurrenceRule.daily().toJSON()

        let created = try await AtomRepository.shared.create(Atom.new(type: .task, title: "Daily").withMetadata(meta))
        createdUUIDs.append(created.uuid)

        let engine = RecurringSeriesEngine()
        try await engine.complete(
            templateUUID: created.uuid,
            occurrenceDay: cal.startOfDay(for: start),   // the live overdue day (6/6)
            on: today,
            calendar: cal
        )

        let fetched = try await AtomRepository.shared.fetch(uuid: created.uuid)
        let updated = try XCTUnwrap(fetched)
        let log = try XCTUnwrap(updated.metadataValue(as: TaskMetadata.self))

        // Today is credited as completed; the missed days are backfilled.
        XCTAssertTrue((log.completedOccurrences ?? []).contains { $0.day == "2026-06-09" })
        XCTAssertEqual(Set(log.skippedOccurrences ?? []), ["2026-06-06", "2026-06-07", "2026-06-08"])

        // Live now jumps to the next future occurrence.
        let snapshot = try XCTUnwrap(RecurringSeriesEngine.makeSnapshot(from: updated, calendar: cal))
        XCTAssertEqual(
            RecurringSeriesEngine.liveOccurrenceDay(for: snapshot, asOf: today, calendar: cal),
            day(2026, 6, 10)
        )
    }

    // MARK: - Clean-slate migration (DB-backed)

    func testCleanSlateMigrationPurgesInstancesAndReanchorsTemplates() async throws {
        let today = day(2026, 6, 9, hour: 9)
        let pastStart = cal.date(byAdding: .day, value: -10, to: today)! // anchored 10 days ago @09:00

        var templateMeta = TaskMetadata()
        templateMeta.startTime = PlannerumFormatters.iso8601.string(from: pastStart)
        templateMeta.focusDate = PlannerumFormatters.iso8601.string(from: pastStart)
        templateMeta.dueDate = PlannerumFormatters.iso8601.string(from: pastStart)
        templateMeta.recurrence = RecurrenceRule.daily().toJSON()
        templateMeta.skippedOccurrences = ["2026-05-01"] // stray pre-migration log
        let template = try await AtomRepository.shared.create(Atom.new(type: .task, title: "Daily").withMetadata(templateMeta))
        createdUUIDs.append(template.uuid)

        var instanceMeta = TaskMetadata()
        instanceMeta.recurrenceParentUUID = template.uuid
        instanceMeta.focusDate = PlannerumFormatters.iso8601.string(from: pastStart)
        let instance = try await AtomRepository.shared.create(Atom.new(type: .task, title: "Daily").withMetadata(instanceMeta))
        createdUUIDs.append(instance.uuid) // migration hard-deletes; tearDown tolerates a re-delete

        var plainMeta = TaskMetadata()
        plainMeta.dueDate = PlannerumFormatters.iso8601.string(from: pastStart)
        let plain = try await AtomRepository.shared.create(Atom.new(type: .task, title: "Plain").withMetadata(plainMeta))
        createdUUIDs.append(plain.uuid)

        try await RecurringSeriesEngine().performCleanSlateMigration(now: today, calendar: cal)

        // Generated instance purged.
        let fetchedInstance = try await AtomRepository.shared.fetch(uuid: instance.uuid)
        XCTAssertNil(fetchedInstance)

        // Template re-anchored to today, stray log cleared, live occurrence = today.
        let fetchedTemplate = try await AtomRepository.shared.fetch(uuid: template.uuid)
        let templateUpdated = try XCTUnwrap(fetchedTemplate)
        let tMeta = try XCTUnwrap(templateUpdated.metadataValue(as: TaskMetadata.self))
        XCTAssertNil(tMeta.skippedOccurrences)
        let snapshot = try XCTUnwrap(RecurringSeriesEngine.makeSnapshot(from: templateUpdated, calendar: cal))
        XCTAssertEqual(
            RecurringSeriesEngine.liveOccurrenceDay(for: snapshot, asOf: today, calendar: cal),
            cal.startOfDay(for: today)
        )

        // Plain task untouched.
        let fetchedPlain = try await AtomRepository.shared.fetch(uuid: plain.uuid)
        let pMeta = try XCTUnwrap(fetchedPlain?.metadataValue(as: TaskMetadata.self))
        XCTAssertEqual(pMeta.dueDate, PlannerumFormatters.iso8601.string(from: pastStart))
    }
}
