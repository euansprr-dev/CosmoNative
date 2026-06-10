//
//  RecurringSeriesEngine.swift
//  CosmoOS
//
//  Virtual-occurrence recurrence engine. A recurring task is ONE series template that owns
//  the rule plus a completion/skip log; individual day-occurrences are *computed*, never
//  materialized as separate atoms. This removes the duplication and "disappearing past day"
//  failure modes of the old materialized model (TaskRecurrenceEngine).
//
//  Overdue policy = collapse-and-jump (Todoist-style): at most ONE live occurrence per series
//  (the oldest un-actioned valid occurrence ≤ today, else the next future occurrence).
//  Completing it records the completion, backfills intervening missed days as "missed", and
//  the live occurrence advances to the next future date.
//

import Foundation

/// Display status of a recurring occurrence. Top-level + `public` so `TaskViewModel` can carry it
/// in its public API without exposing the (internal) engine type.
public enum TaskOccurrenceStatus: String, Sendable, Equatable, CaseIterable {
    case upcoming    // future occurrence, not yet actioned
    case active      // the single live occurrence, falling on today
    case overdue     // the single live occurrence, falling on a past day
    case completed   // logged complete
    case missed      // explicitly skipped, backfilled, or a past day masked behind the live one
}

@MainActor
final class RecurringSeriesEngine {

    // MARK: - Singleton

    static let shared = RecurringSeriesEngine()

    private let atomRepository: AtomRepository

    init(atomRepository: AtomRepository? = nil) {
        self.atomRepository = atomRepository ?? AtomRepository.shared
    }

    // MARK: - Tunables

    /// How far back an un-actioned occurrence is still surfaced as the single overdue item.
    /// Older misses are treated as implicitly missed (not nagged).
    static let overdueHorizonDays = 60
    /// How far forward we search for the next future occurrence when nothing is currently due.
    static let futureHorizonDays = 400

    // MARK: - Occurrence Status

    /// Nested alias kept for call-site readability (`RecurringSeriesEngine.OccurrenceStatus`).
    typealias OccurrenceStatus = TaskOccurrenceStatus

    // MARK: - Pure value snapshots (no DB — fully unit-testable)

    /// Everything the projection needs, extracted from a series template atom.
    struct SeriesSnapshot: Equatable, Sendable {
        let templateUUID: String
        let title: String
        let rule: RecurrenceRule
        let startDate: Date            // first possible occurrence, carrying time-of-day
        let hasTimeOfDay: Bool         // template specified a clock time (vs. day-only)
        let durationMinutes: Int
        let completedDays: Set<String> // day-keys
        let skippedDays: Set<String>   // day-keys
        let overrides: [String: TaskOccurrenceOverride]
    }

    /// A computed occurrence of a series for a specific day.
    struct VirtualOccurrence: Identifiable, Equatable, Sendable {
        let templateUUID: String
        let title: String
        let day: Date          // startOfDay of the occurrence
        let start: Date?       // time-of-day applied (nil when the template is day-only)
        let end: Date?
        let status: OccurrenceStatus

        var dayKey: String { RecurringSeriesEngine.dayKey(for: day) }
        /// Stable identity across refreshes: "<templateUUID>#<yyyy-MM-dd>".
        var id: String { "\(templateUUID)#\(dayKey)" }
    }

    // MARK: - Day keys

    /// Deterministic "yyyy-MM-dd" key for an occurrence day (no DateFormatter state).
    /// `nonisolated` so `VirtualOccurrence` (a plain Sendable struct) can derive its id.
    nonisolated static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: calendar.startOfDay(for: date))
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: - Projection (pure)

    /// All occurrences of a series within `interval`, each tagged with display status,
    /// computed against `today`. Honors the completed/skipped logs and per-day overrides.
    static func occurrences(
        for series: SeriesSnapshot,
        in interval: DateInterval,
        asOf today: Date,
        calendar: Calendar = .current
    ) -> [VirtualOccurrence] {
        let liveDay = liveOccurrenceDay(for: series, asOf: today, calendar: calendar)
        let todayStart = calendar.startOfDay(for: today)
        var result: [VirtualOccurrence] = []

        for date in series.rule.occurrenceDates(in: interval, startingFrom: series.startDate, calendar: calendar) {
            let day = calendar.startOfDay(for: date)
            let key = dayKey(for: day, calendar: calendar)

            if series.overrides[key]?.isCanceled == true { continue }

            let status: OccurrenceStatus
            if series.completedDays.contains(key) {
                status = .completed
            } else if series.skippedDays.contains(key) {
                status = .missed
            } else if let liveDay, calendar.isDate(day, inSameDayAs: liveDay) {
                status = day < todayStart ? .overdue : .active
            } else if day < todayStart {
                status = .missed            // a past day masked behind an older live occurrence
            } else {
                status = .upcoming
            }

            result.append(makeOccurrence(series: series, day: day, baseDate: date, status: status, calendar: calendar))
        }
        return result
    }

    /// The single live occurrence for a series as of `today`, or nil if none applies.
    static func liveOccurrence(
        for series: SeriesSnapshot,
        asOf today: Date,
        calendar: Calendar = .current
    ) -> VirtualOccurrence? {
        guard let day = liveOccurrenceDay(for: series, asOf: today, calendar: calendar) else { return nil }
        let todayStart = calendar.startOfDay(for: today)
        let base = baseDate(for: series, day: day, calendar: calendar)
        let status: OccurrenceStatus
        if day < todayStart {
            status = .overdue
        } else if calendar.isDate(day, inSameDayAs: todayStart) {
            status = .active
        } else {
            status = .upcoming
        }
        return makeOccurrence(series: series, day: day, baseDate: base, status: status, calendar: calendar)
    }

    /// Day of the single live occurrence = oldest un-actioned valid occurrence within
    /// [today − overdueHorizon, today]; else the next valid occurrence in (today, today + futureHorizon].
    static func liveOccurrenceDay(
        for series: SeriesSnapshot,
        asOf today: Date,
        calendar: Calendar = .current
    ) -> Date? {
        let todayStart = calendar.startOfDay(for: today)
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        let lookback = calendar.date(byAdding: .day, value: -overdueHorizonDays, to: todayStart) ?? todayStart
        let searchStart = max(calendar.startOfDay(for: series.startDate), lookback)

        // 1) Oldest un-actioned occurrence up to and including today.
        if searchStart < todayEnd,
           let day = firstUnactioned(in: DateInterval(start: searchStart, end: todayEnd), series: series, calendar: calendar) {
            return day
        }

        // 2) Otherwise the next future occurrence.
        let futureEnd = calendar.date(byAdding: .day, value: futureHorizonDays, to: todayEnd) ?? todayEnd
        return firstUnactioned(in: DateInterval(start: todayEnd, end: futureEnd), series: series, calendar: calendar)
    }

    /// Whether `day` is a valid occurrence of the series rule.
    static func isValidOccurrence(
        for series: SeriesSnapshot,
        day: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return !series.rule.occurrenceDates(in: DateInterval(start: start, end: end), startingFrom: series.startDate, calendar: calendar).isEmpty
    }

    // MARK: - Projection helpers (private, pure)

    private static func firstUnactioned(
        in interval: DateInterval,
        series: SeriesSnapshot,
        calendar: Calendar
    ) -> Date? {
        for date in series.rule.occurrenceDates(in: interval, startingFrom: series.startDate, calendar: calendar) {
            let day = calendar.startOfDay(for: date)
            let key = dayKey(for: day, calendar: calendar)
            if series.overrides[key]?.isCanceled == true { continue }
            if series.completedDays.contains(key) || series.skippedDays.contains(key) { continue }
            return day
        }
        return nil
    }

    private static func makeOccurrence(
        series: SeriesSnapshot,
        day: Date,
        baseDate: Date,
        status: OccurrenceStatus,
        calendar: Calendar
    ) -> VirtualOccurrence {
        let key = dayKey(for: day, calendar: calendar)
        let override = series.overrides[key]
        let title = override?.title ?? series.title

        var start: Date? = series.hasTimeOfDay ? baseDate : nil
        if let overrideStart = override?.startTime.flatMap({ PlannerumFormatters.iso8601.date(from: $0) }) {
            start = merge(day: day, time: overrideStart, calendar: calendar)
        }
        let end = start.map { calendar.date(byAdding: .minute, value: series.durationMinutes, to: $0) ?? $0 }
        return VirtualOccurrence(templateUUID: series.templateUUID, title: title, day: day, start: start, end: end, status: status)
    }

    private static func baseDate(for series: SeriesSnapshot, day: Date, calendar: Calendar) -> Date {
        series.hasTimeOfDay ? merge(day: day, time: series.startDate, calendar: calendar) : calendar.startOfDay(for: day)
    }

    private static func merge(day: Date, time: Date, calendar: Calendar) -> Date {
        let d = calendar.dateComponents([.year, .month, .day], from: day)
        let t = calendar.dateComponents([.hour, .minute, .second], from: time)
        var c = DateComponents()
        c.year = d.year; c.month = d.month; c.day = d.day
        c.hour = t.hour; c.minute = t.minute; c.second = t.second ?? 0
        c.timeZone = calendar.timeZone
        return calendar.date(from: c) ?? calendar.startOfDay(for: day)
    }

    // MARK: - Snapshot extraction

    /// Build a pure `SeriesSnapshot` from a series template atom. Returns nil for non-templates
    /// (instances, non-recurring tasks, or templates missing an anchor date).
    static func makeSnapshot(from atom: Atom, calendar: Calendar = .current) -> SeriesSnapshot? {
        guard atom.type == .task,
              let meta = atom.metadataValue(as: TaskMetadata.self),
              meta.recurrenceParentUUID == nil,
              let recurrenceJSON = meta.recurrence,
              let rule = RecurrenceRule.fromJSON(recurrenceJSON),
              let start = seriesStartDate(from: meta) else {
            return nil
        }
        let hasTime = (meta.scheduledStart ?? meta.startTime) != nil
        return SeriesSnapshot(
            templateUUID: atom.uuid,
            title: atom.title ?? "Untitled Task",
            rule: rule,
            startDate: start,
            hasTimeOfDay: hasTime,
            durationMinutes: max(15, meta.durationMinutes ?? meta.estimatedFocusMinutes ?? 30),
            completedDays: Set((meta.completedOccurrences ?? []).map(\.day)),
            skippedDays: Set(meta.skippedOccurrences ?? []),
            overrides: meta.occurrenceOverrides ?? [:]
        )
    }

    private static func seriesStartDate(from meta: TaskMetadata) -> Date? {
        let candidates = [meta.scheduledStart, meta.startTime, meta.focusDate, meta.whenDate, meta.dueDate]
        for candidate in candidates {
            if let candidate, let date = PlannerumFormatters.iso8601.date(from: candidate) { return date }
        }
        return nil
    }

    // MARK: - DB-facing projection

    /// All series templates as snapshots.
    func loadSeriesSnapshots() async throws -> [SeriesSnapshot] {
        try await atomRepository.fetchAll(type: .task).compactMap { Self.makeSnapshot(from: $0) }
    }

    /// One live occurrence per active series (for the Today list).
    func liveOccurrences(asOf today: Date = Date()) async throws -> [VirtualOccurrence] {
        try await loadSeriesSnapshots().compactMap { Self.liveOccurrence(for: $0, asOf: today) }
    }

    /// Every occurrence (all statuses) across `interval` (for the Upcoming history view).
    func occurrences(in interval: DateInterval, asOf today: Date = Date()) async throws -> [VirtualOccurrence] {
        try await loadSeriesSnapshots().flatMap { Self.occurrences(for: $0, in: interval, asOf: today) }
    }

    // MARK: - Mutations (collapse-and-jump)

    /// Complete the live occurrence of a series. `occurrenceDay` is the day the live item
    /// represented. Records the completion, backfills intervening misses, advances live.
    func complete(
        templateUUID: String,
        occurrenceDay: Date,
        on actionDate: Date = Date(),
        trackedMinutes: Int? = nil,
        calendar: Calendar = .current
    ) async throws {
        _ = try await atomRepository.update(uuid: templateUUID) { atom in
            guard var meta = atom.metadataValue(as: TaskMetadata.self),
                  let snapshot = Self.makeSnapshot(from: atom, calendar: calendar) else { return }

            let todayStart = calendar.startOfDay(for: actionDate)
            let liveDay = calendar.startOfDay(for: occurrenceDay)

            // Credit today when today is a valid, on-or-after-live occurrence; else credit the
            // represented (overdue) day. This is what "jump ahead" means for a fresh completion.
            let todayValid = Self.isValidOccurrence(for: snapshot, day: todayStart, calendar: calendar)
            let completedDay = (todayValid && todayStart >= liveDay) ? todayStart : liveDay
            let completedKey = Self.dayKey(for: completedDay, calendar: calendar)

            var completed = meta.completedOccurrences ?? []
            if !completed.contains(where: { $0.day == completedKey }) {
                completed.append(TaskOccurrenceCompletion(
                    day: completedKey,
                    completedAt: PlannerumFormatters.iso8601.string(from: actionDate),
                    trackedMinutes: trackedMinutes
                ))
            }
            meta.completedOccurrences = completed
            let completedKeys = Set(completed.map(\.day))

            // Backfill: every valid occurrence in [liveDay, completedDay) not completed → missed.
            if completedDay > liveDay {
                var skipped = Set(meta.skippedOccurrences ?? [])
                let span = DateInterval(start: liveDay, end: completedDay)
                for date in snapshot.rule.occurrenceDates(in: span, startingFrom: snapshot.startDate, calendar: calendar) {
                    let key = Self.dayKey(for: calendar.startOfDay(for: date), calendar: calendar)
                    if key == completedKey || completedKeys.contains(key) { continue }
                    skipped.insert(key)
                }
                meta.skippedOccurrences = skipped.isEmpty ? nil : Array(skipped).sorted()
            }

            atom = atom.withMetadata(meta)
        }
    }

    /// Reverse a logged completion for a specific occurrence day.
    func uncomplete(templateUUID: String, occurrenceDay: Date, calendar: Calendar = .current) async throws {
        let key = Self.dayKey(for: occurrenceDay, calendar: calendar)
        _ = try await atomRepository.update(uuid: templateUUID) { atom in
            guard var meta = atom.metadataValue(as: TaskMetadata.self) else { return }
            meta.completedOccurrences = (meta.completedOccurrences ?? []).filter { $0.day != key }
            if var skipped = meta.skippedOccurrences {
                skipped.removeAll { $0 == key }
                meta.skippedOccurrences = skipped.isEmpty ? nil : skipped
            }
            atom = atom.withMetadata(meta)
        }
    }

    /// Explicitly mark an occurrence skipped/missed without completing it.
    func skip(templateUUID: String, occurrenceDay: Date, calendar: Calendar = .current) async throws {
        let key = Self.dayKey(for: occurrenceDay, calendar: calendar)
        _ = try await atomRepository.update(uuid: templateUUID) { atom in
            guard var meta = atom.metadataValue(as: TaskMetadata.self) else { return }
            var skipped = Set(meta.skippedOccurrences ?? [])
            skipped.insert(key)
            meta.skippedOccurrences = Array(skipped).sorted()
            atom = atom.withMetadata(meta)
        }
    }

    // MARK: - Clean-slate migration (old materialized model → virtual occurrences)

    static let migrationDefaultsKey = "recurringSeries.cleanSlateMigration.v1"

    /// Run the one-shot switch-over from the old materialized-instance model, once per install.
    func runCleanSlateMigrationIfNeeded(now: Date = Date(), calendar: Calendar = .current) async {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.migrationDefaultsKey) else { return }
        do {
            try await performCleanSlateMigration(now: now, calendar: calendar)
            defaults.set(true, forKey: Self.migrationDefaultsKey)
        } catch {
            print("❌ RecurringSeriesEngine: clean-slate migration failed: \(error)")
        }
    }

    /// Purge generated recurring instance atoms (occurrences are projected now) and re-anchor each
    /// series template to today so projection starts fresh. Recurring history before the switch is
    /// intentionally dropped (clean slate). Non-recurring tasks are untouched.
    func performCleanSlateMigration(now: Date = Date(), calendar: Calendar = .current) async throws {
        let tasks = try await atomRepository.fetchAll(type: .task)
        let todayStart = calendar.startOfDay(for: now)

        for atom in tasks {
            guard let meta = atom.metadataValue(as: TaskMetadata.self) else { continue }

            // Generated instance → delete; it's a projected occurrence now.
            if meta.recurrenceParentUUID != nil {
                try await atomRepository.hardDelete(uuid: atom.uuid, confirmed: true)
                continue
            }

            // Series template → clear any stray log and re-anchor a past start to today.
            guard meta.recurrence != nil else { continue }
            _ = try await atomRepository.update(uuid: atom.uuid) { mutable in
                guard var m = mutable.metadataValue(as: TaskMetadata.self) else { return }
                m.completedOccurrences = nil
                m.skippedOccurrences = nil
                m.occurrenceOverrides = nil
                Self.reanchorToToday(&m, todayStart: todayStart, calendar: calendar)
                mutable = mutable.withMetadata(m)
            }
        }
    }

    /// Shift a template's anchor date fields to today (preserving time-of-day for timed fields).
    /// No-op when the existing anchor is already today or in the future.
    private static func reanchorToToday(_ meta: inout TaskMetadata, todayStart: Date, calendar: Calendar) {
        guard let anchor = seriesStartDate(from: meta),
              calendar.startOfDay(for: anchor) < todayStart else { return }

        let dayISO = PlannerumFormatters.iso8601.string(from: todayStart)
        func shiftTimed(_ iso: String?) -> String? {
            guard let iso, let date = PlannerumFormatters.iso8601.date(from: iso) else { return nil }
            return PlannerumFormatters.iso8601.string(from: merge(day: todayStart, time: date, calendar: calendar))
        }

        if meta.focusDate != nil { meta.focusDate = dayISO }
        if meta.dueDate != nil { meta.dueDate = dayISO }
        if meta.whenDate != nil { meta.whenDate = dayISO }
        if meta.startTime != nil { meta.startTime = shiftTimed(meta.startTime) }
        if meta.endTime != nil { meta.endTime = shiftTimed(meta.endTime) }
        if meta.scheduledStart != nil { meta.scheduledStart = shiftTimed(meta.scheduledStart) }
        if meta.scheduledEnd != nil { meta.scheduledEnd = shiftTimed(meta.scheduledEnd) }
    }
}
