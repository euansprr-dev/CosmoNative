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

    // MARK: - Delete series keeps history (DB-backed)

    /// "Delete series" contract (July 2026): the template atom and its completion
    /// log survive — the rule is truncated so the live occurrence and everything
    /// after it vanish while past days keep projecting.
    func testEndSeriesPreservingHistoryRemovesCurrentAndFutureKeepsLog() async throws {
        let today = day(2026, 6, 9, hour: 9)
        let start = cal.date(byAdding: .day, value: -4, to: today)! // 6/5 09:00

        var meta = TaskMetadata()
        meta.startTime = PlannerumFormatters.iso8601.string(from: start)
        meta.focusDate = PlannerumFormatters.iso8601.string(from: start)
        meta.dueDate = PlannerumFormatters.iso8601.string(from: start)
        meta.recurrence = RecurrenceRule.daily().toJSON()
        meta.completedOccurrences = [
            TaskOccurrenceCompletion(day: "2026-06-05", completedAt: PlannerumFormatters.iso8601.string(from: start)),
            TaskOccurrenceCompletion(day: "2026-06-06", completedAt: PlannerumFormatters.iso8601.string(from: start))
        ]
        meta.skippedOccurrences = ["2026-06-07"]

        let created = try await AtomRepository.shared.create(Atom.new(type: .task, title: "Daily").withMetadata(meta))
        createdUUIDs.append(created.uuid)

        try await RecurringSeriesEngine().endSeriesPreservingHistory(
            templateUUID: created.uuid,
            asOf: today,
            calendar: cal
        )

        // The template atom still exists and its log is intact.
        let fetchedOpt = try await AtomRepository.shared.fetch(uuid: created.uuid)
        let fetched = try XCTUnwrap(fetchedOpt)
        let log = try XCTUnwrap(fetched.metadataValue(as: TaskMetadata.self))
        XCTAssertEqual(Set((log.completedOccurrences ?? []).map(\.day)), ["2026-06-05", "2026-06-06"])
        XCTAssertEqual(log.skippedOccurrences, ["2026-06-07"])

        // No live occurrence any more — the current (6/8 overdue) and future days are gone.
        let snapshot = try XCTUnwrap(RecurringSeriesEngine.makeSnapshot(from: fetched, calendar: cal))
        XCTAssertNil(RecurringSeriesEngine.liveOccurrenceDay(for: snapshot, asOf: today, calendar: cal))

        // Past days still project with their logged statuses; nothing on/after the cutoff.
        let occ = RecurringSeriesEngine.occurrences(
            for: snapshot,
            in: DateInterval(start: day(2026, 6, 5), end: day(2026, 6, 20)),
            asOf: today,
            calendar: cal
        )
        func status(_ d: Date) -> RecurringSeriesEngine.OccurrenceStatus? {
            occ.first { cal.isDate($0.day, inSameDayAs: d) }?.status
        }
        XCTAssertEqual(status(day(2026, 6, 5)), .completed)
        XCTAssertEqual(status(day(2026, 6, 6)), .completed)
        XCTAssertEqual(status(day(2026, 6, 7)), .missed)
        XCTAssertNil(status(day(2026, 6, 8)), "The un-actioned live day must not survive the delete")
        XCTAssertNil(status(day(2026, 6, 9)))
        XCTAssertNil(status(day(2026, 6, 10)))
    }

    /// Completing today then deleting the series keeps today's completion projecting:
    /// the rule end lands on the last logged day, never before it.
    func testEndSeriesAfterCompletingTodayKeepsTodaysCompletion() async throws {
        let today = day(2026, 6, 9, hour: 9)
        let start = cal.date(byAdding: .day, value: -2, to: today)! // 6/7 09:00

        var meta = TaskMetadata()
        meta.startTime = PlannerumFormatters.iso8601.string(from: start)
        meta.focusDate = PlannerumFormatters.iso8601.string(from: start)
        meta.dueDate = PlannerumFormatters.iso8601.string(from: start)
        meta.recurrence = RecurrenceRule.daily().toJSON()
        meta.completedOccurrences = [
            TaskOccurrenceCompletion(day: "2026-06-07", completedAt: PlannerumFormatters.iso8601.string(from: start)),
            TaskOccurrenceCompletion(day: "2026-06-08", completedAt: PlannerumFormatters.iso8601.string(from: start)),
            TaskOccurrenceCompletion(day: "2026-06-09", completedAt: PlannerumFormatters.iso8601.string(from: today))
        ]

        let created = try await AtomRepository.shared.create(Atom.new(type: .task, title: "Daily").withMetadata(meta))
        createdUUIDs.append(created.uuid)

        try await RecurringSeriesEngine().endSeriesPreservingHistory(
            templateUUID: created.uuid,
            asOf: today,
            calendar: cal
        )

        let fetchedOpt = try await AtomRepository.shared.fetch(uuid: created.uuid)
        let fetched = try XCTUnwrap(fetchedOpt)
        let snapshot = try XCTUnwrap(RecurringSeriesEngine.makeSnapshot(from: fetched, calendar: cal))

        // Today's completion is still part of the projected history…
        let occ = RecurringSeriesEngine.occurrences(
            for: snapshot,
            in: DateInterval(start: day(2026, 6, 7), end: day(2026, 6, 20)),
            asOf: today,
            calendar: cal
        )
        XCTAssertEqual(
            occ.filter { $0.status == .completed }.map(\.dayKey).sorted(),
            ["2026-06-07", "2026-06-08", "2026-06-09"]
        )
        // …and nothing lives on: no future occurrence surfaces.
        XCTAssertNil(RecurringSeriesEngine.liveOccurrenceDay(for: snapshot, asOf: today, calendar: cal))
    }

    // MARK: - Clean-slate migration (DB-backed)

    /// Data-safety contract (June 2026): the migration soft-deletes generated
    /// instances (tombstoned for sync), re-anchors only CLEAN templates, and
    /// NEVER touches a template whose completion/skip/override log is non-empty
    /// — that's new-model history a re-run must not wipe.
    func testCleanSlateMigrationSoftDeletesInstancesPreservesLogsAndReanchorsCleanTemplates() async throws {
        let today = day(2026, 6, 9, hour: 9)
        let pastStart = cal.date(byAdding: .day, value: -10, to: today)! // anchored 10 days ago @09:00

        // Template already living on the new model (has a log) — must be untouched.
        var loggedMeta = TaskMetadata()
        loggedMeta.startTime = PlannerumFormatters.iso8601.string(from: pastStart)
        loggedMeta.focusDate = PlannerumFormatters.iso8601.string(from: pastStart)
        loggedMeta.dueDate = PlannerumFormatters.iso8601.string(from: pastStart)
        loggedMeta.recurrence = RecurrenceRule.daily().toJSON()
        loggedMeta.skippedOccurrences = ["2026-05-01"]
        let loggedTemplate = try await AtomRepository.shared.create(Atom.new(type: .task, title: "Daily logged").withMetadata(loggedMeta))
        createdUUIDs.append(loggedTemplate.uuid)

        // Un-migrated template with no history — gets re-anchored to today.
        var cleanMeta = TaskMetadata()
        cleanMeta.startTime = PlannerumFormatters.iso8601.string(from: pastStart)
        cleanMeta.focusDate = PlannerumFormatters.iso8601.string(from: pastStart)
        cleanMeta.dueDate = PlannerumFormatters.iso8601.string(from: pastStart)
        cleanMeta.recurrence = RecurrenceRule.daily().toJSON()
        let cleanTemplate = try await AtomRepository.shared.create(Atom.new(type: .task, title: "Daily clean").withMetadata(cleanMeta))
        createdUUIDs.append(cleanTemplate.uuid)

        var instanceMeta = TaskMetadata()
        instanceMeta.recurrenceParentUUID = cleanTemplate.uuid
        instanceMeta.focusDate = PlannerumFormatters.iso8601.string(from: pastStart)
        let instance = try await AtomRepository.shared.create(Atom.new(type: .task, title: "Daily clean").withMetadata(instanceMeta))
        createdUUIDs.append(instance.uuid)

        var plainMeta = TaskMetadata()
        plainMeta.dueDate = PlannerumFormatters.iso8601.string(from: pastStart)
        let plain = try await AtomRepository.shared.create(Atom.new(type: .task, title: "Plain").withMetadata(plainMeta))
        createdUUIDs.append(plain.uuid)

        let failures = await RecurringSeriesEngine().performCleanSlateMigration(now: today, calendar: cal)
        XCTAssertEqual(failures, 0)

        // Generated instance soft-deleted (tombstoned, not hard-deleted) — invisible to fetch.
        let fetchedInstance = try await AtomRepository.shared.fetch(uuid: instance.uuid)
        XCTAssertNil(fetchedInstance)
        let instanceTombstone = try await CosmoDatabase.shared.asyncRead { [uuid = instance.uuid] db in
            try Int.fetchOne(db, sql: "SELECT is_deleted FROM atoms WHERE uuid = ?", arguments: [uuid])
        }
        XCTAssertEqual(instanceTombstone, 1, "Instance must be tombstoned for sync, not hard-deleted")

        // Logged template untouched: history preserved, anchor NOT moved.
        let fetchedLoggedOpt = try await AtomRepository.shared.fetch(uuid: loggedTemplate.uuid)
        let fetchedLogged = try XCTUnwrap(fetchedLoggedOpt)
        let lMeta = try XCTUnwrap(fetchedLogged.metadataValue(as: TaskMetadata.self))
        XCTAssertEqual(lMeta.skippedOccurrences, ["2026-05-01"], "A template with logged history must never be wiped by the migration")
        XCTAssertEqual(lMeta.focusDate, PlannerumFormatters.iso8601.string(from: pastStart))

        // Clean template re-anchored to today; live occurrence = today.
        let fetchedCleanOpt = try await AtomRepository.shared.fetch(uuid: cleanTemplate.uuid)
        let fetchedClean = try XCTUnwrap(fetchedCleanOpt)
        let snapshot = try XCTUnwrap(RecurringSeriesEngine.makeSnapshot(from: fetchedClean, calendar: cal))
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

/// The stranded-whenDate lag signature TaskDayPinRepair heals (pure rule —
/// CommandCenterTaskScheduling.laggingWhenDateCorrection). The signature:
/// due and focus share a day, whenDate strictly earlier. Every legitimate
/// writer moves the pins together, so only the pre-fix iOS reschedule
/// produces it.
final class TaskDayPinRepairRuleTests: XCTestCase {

    private let cal = Calendar.current

    private func iso(daysAgo: Int) -> String {
        let day = cal.startOfDay(for: cal.date(byAdding: .day, value: -daysAgo, to: Date())!)
        return PlannerumFormatters.iso8601.string(from: day)
    }

    private func metadata(due: String?, focus: String?, when: String?, recurrence: String? = nil) -> TaskMetadata {
        var m = TaskMetadata()
        m.dueDate = due
        m.focusDate = focus
        m.whenDate = when
        m.recurrence = recurrence
        return m
    }

    func testLaggedWhenDateIsCorrectedToDueDay() {
        let meta = metadata(due: iso(daysAgo: 0), focus: iso(daysAgo: 0), when: iso(daysAgo: 2))
        let corrected = CommandCenterTaskScheduling.laggingWhenDateCorrection(in: meta, calendar: cal)
        XCTAssertEqual(corrected, iso(daysAgo: 0))
    }

    func testDeliberateDeadlineSplitIsLeftAlone() {
        // Things-style: plan Wednesday (when/focus), deadline Friday (due).
        let meta = metadata(due: iso(daysAgo: 0), focus: iso(daysAgo: 2), when: iso(daysAgo: 2))
        XCTAssertNil(CommandCenterTaskScheduling.laggingWhenDateCorrection(in: meta, calendar: cal))
    }

    func testAlignedPinsAreHealthy() {
        let meta = metadata(due: iso(daysAgo: 1), focus: iso(daysAgo: 1), when: iso(daysAgo: 1))
        XCTAssertNil(CommandCenterTaskScheduling.laggingWhenDateCorrection(in: meta, calendar: cal))
    }

    func testFutureWhenDateIsLeftAlone() {
        // whenDate ahead of due is not the lag signature.
        let meta = metadata(due: iso(daysAgo: 3), focus: iso(daysAgo: 3), when: iso(daysAgo: 0))
        XCTAssertNil(CommandCenterTaskScheduling.laggingWhenDateCorrection(in: meta, calendar: cal))
    }

    func testRecurringTemplatesAreNeverTouched() {
        let meta = metadata(
            due: iso(daysAgo: 0), focus: iso(daysAgo: 0), when: iso(daysAgo: 2),
            recurrence: #"{"frequency":"daily","interval":1}"#
        )
        XCTAssertNil(CommandCenterTaskScheduling.laggingWhenDateCorrection(in: meta, calendar: cal))
    }

    func testMissingPinsAreLeftAlone() {
        XCTAssertNil(CommandCenterTaskScheduling.laggingWhenDateCorrection(
            in: metadata(due: iso(daysAgo: 0), focus: iso(daysAgo: 0), when: nil), calendar: cal
        ))
        XCTAssertNil(CommandCenterTaskScheduling.laggingWhenDateCorrection(
            in: metadata(due: nil, focus: iso(daysAgo: 0), when: iso(daysAgo: 2)), calendar: cal
        ))
    }
}
