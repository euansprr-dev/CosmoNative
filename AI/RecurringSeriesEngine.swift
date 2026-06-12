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
import GRDB

/// Display status of a recurring occurrence. Top-level + `public` so `TaskViewModel` can carry it
/// in its public API without exposing the (internal) engine type.
public enum TaskOccurrenceStatus: String, Sendable, Equatable, CaseIterable {
    case upcoming    // future occurrence, not yet actioned
    case active      // the single live occurrence, falling on today
    case overdue     // the single live occurrence, falling on a past day
    case completed   // logged complete
    case missed      // explicitly skipped, backfilled, or a past day masked behind the live one
}

/// Errors from recurring-series mutations. These used to be silent guard-returns —
/// the UI would animate a completion that never persisted and still award habit credit.
enum RecurringSeriesEngineError: LocalizedError {
    case templateNotFound(String)
    case notASeriesTemplate(String)
    case corruptMetadata(String)
    case persistenceFailed(String)

    var errorDescription: String? {
        switch self {
        case .templateNotFound(let uuid):
            return "Recurring series template \(uuid.prefix(8)) not found."
        case .notASeriesTemplate(let uuid):
            return "Atom \(uuid.prefix(8)) is not a recurring series template."
        case .corruptMetadata(let uuid):
            return "Task metadata for \(uuid.prefix(8)) is undecodable — refusing to overwrite it."
        case .persistenceFailed(let uuid):
            return "Failed to persist recurring-series change for \(uuid.prefix(8))."
        }
    }
}

// MARK: - TaskMetadata merge (clear-honoring)

extension Atom {
    /// Merge a `TaskMetadata` overlay into the metadata column. Preserves sibling JSON keys
    /// owned by other writers while still honoring fields the typed struct explicitly
    /// cleared to nil — a plain key-merge would resurrect cleared dates/completion stamps,
    /// because JSONEncoder omits nil fields.
    ///
    /// Returns nil — refuse the write — when the existing column is non-empty but
    /// unparseable, or when encoding fails. Never destroys data it can't read.
    func mergingTaskMetadata(_ metadata: TaskMetadata, context: String) -> Atom? {
        guard let overlayData = try? JSONEncoder().encode(metadata),
              let overlayObject = try? JSONSerialization.jsonObject(with: overlayData) as? [String: Any] else {
            PersistenceHealth.note(.writeFailure, context: context, detail: "task metadata encode failed; keeping existing column")
            return nil
        }

        var merged: [String: Any] = [:]
        if let existing = self.metadata, !existing.isEmpty {
            guard let data = existing.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                PersistenceHealth.note(.decodeFailure, context: context, detail: "existing metadata unparseable; refusing overwrite that would drop its data")
                return nil
            }
            merged = dict
        }

        // Drop TaskMetadata-owned keys the overlay cleared to nil; sibling keys survive.
        for child in Mirror(reflecting: metadata).children {
            guard let key = child.label, overlayObject[key] == nil else { continue }
            merged.removeValue(forKey: key)
        }
        for (key, value) in overlayObject {
            merged[key] = value
        }

        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged),
              let mergedString = String(data: mergedData, encoding: .utf8) else {
            PersistenceHealth.note(.writeFailure, context: context, detail: "merged metadata encode failed; keeping existing column")
            return nil
        }

        var copy = self
        copy.metadata = mergedString
        return copy
    }
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

    /// Inverse of `dayKey(for:)`: startOfDay for a "yyyy-MM-dd" key in the calendar's timezone.
    nonisolated static func day(fromKey key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var c = DateComponents()
        c.year = parts[0]
        c.month = parts[1]
        c.day = parts[2]
        c.timeZone = calendar.timeZone
        return calendar.date(from: c).map { calendar.startOfDay(for: $0) }
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

        func status(forKey key: String, day: Date) -> OccurrenceStatus {
            if series.completedDays.contains(key) {
                return .completed
            } else if series.skippedDays.contains(key) {
                return .missed
            } else if let liveDay, calendar.isDate(day, inSameDayAs: liveDay) {
                return day < todayStart ? .overdue : .active
            } else if day < todayStart {
                return .missed              // a past day masked behind an older live occurrence
            } else {
                return .upcoming
            }
        }

        for date in series.rule.occurrenceDates(in: interval, startingFrom: series.startDate, calendar: calendar) {
            let day = calendar.startOfDay(for: date)
            let key = dayKey(for: day, calendar: calendar)
            let override = series.overrides[key]

            if override?.isCanceled == true { continue }
            if override?.rescheduledTo != nil { continue }   // moved away; emitted on its target day below

            result.append(makeOccurrence(
                series: series,
                day: day,
                baseDate: date,
                status: status(forKey: key, day: day),
                calendar: calendar
            ))
        }

        // Single-occurrence reschedules: emit the moved occurrence on its target day,
        // carrying its source-day override (title/time) and logging under the target key.
        // The target day's own override (keyed by the day the moved occurrence renders on)
        // wins for cancel-after-move and move-after-move.
        for (sourceKey, override) in series.overrides {
            guard override.isCanceled != true,
                  let targetKey = override.rescheduledTo,
                  targetKey != sourceKey,
                  let targetDay = day(fromKey: targetKey, calendar: calendar),
                  targetDay >= calendar.startOfDay(for: interval.start),
                  targetDay < interval.end else { continue }

            let targetOverride = series.overrides[targetKey]
            if targetOverride?.isCanceled == true || targetOverride?.rescheduledTo != nil { continue }

            result.append(makeOccurrence(
                series: series,
                day: targetDay,
                baseDate: baseDate(for: series, day: targetDay, calendar: calendar),
                status: status(forKey: targetKey, day: targetDay),
                calendar: calendar,
                override: override
            ))
        }

        // A reschedule target can coincide with a rule day — keep one occurrence per day.
        var seenIDs = Set<String>()
        return result
            .sorted { $0.day < $1.day }
            .filter { seenIDs.insert($0.id).inserted }
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
        var earliest: Date?

        for date in series.rule.occurrenceDates(in: interval, startingFrom: series.startDate, calendar: calendar) {
            let day = calendar.startOfDay(for: date)
            let key = dayKey(for: day, calendar: calendar)
            let override = series.overrides[key]
            if override?.isCanceled == true { continue }
            if override?.rescheduledTo != nil { continue }   // moved to another day
            if series.completedDays.contains(key) || series.skippedDays.contains(key) { continue }
            earliest = day
            break
        }

        // Rescheduled occurrences landing inside the interval also compete for "live".
        for (sourceKey, override) in series.overrides {
            guard override.isCanceled != true,
                  let targetKey = override.rescheduledTo,
                  targetKey != sourceKey,
                  let targetDay = day(fromKey: targetKey, calendar: calendar),
                  targetDay >= calendar.startOfDay(for: interval.start),
                  targetDay < interval.end,
                  !series.completedDays.contains(targetKey),
                  !series.skippedDays.contains(targetKey) else { continue }
            let targetOverride = series.overrides[targetKey]
            if targetOverride?.isCanceled == true || targetOverride?.rescheduledTo != nil { continue }
            if earliest == nil || targetDay < earliest! {
                earliest = targetDay
            }
        }

        return earliest
    }

    private static func makeOccurrence(
        series: SeriesSnapshot,
        day: Date,
        baseDate: Date,
        status: OccurrenceStatus,
        calendar: Calendar,
        override explicitOverride: TaskOccurrenceOverride? = nil
    ) -> VirtualOccurrence {
        let key = dayKey(for: day, calendar: calendar)
        // Rescheduled occurrences carry their source-day override explicitly (the override
        // is keyed by the day they moved FROM, not the day they render on).
        let override = explicitOverride ?? series.overrides[key]
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
    /// (instances, non-recurring tasks). A template with no anchor date falls back to its
    /// createdAt so a series never becomes unprojectable (invisible) just because its date
    /// fields were cleared.
    static func makeSnapshot(from atom: Atom, calendar: Calendar = .current) -> SeriesSnapshot? {
        guard atom.type == .task,
              let meta = atom.metadataValue(as: TaskMetadata.self),
              meta.recurrenceParentUUID == nil,
              let recurrenceJSON = meta.recurrence,
              let rule = RecurrenceRule.fromJSON(recurrenceJSON) else {
            return nil
        }

        let instantStart = seriesStartDate(from: meta)
        let start: Date
        if let anchorDay = meta.seriesAnchorDay.flatMap({ day(fromKey: $0, calendar: calendar) }) {
            // Timezone-safe anchor: the date-only day key pins the day; time-of-day (when
            // the template is timed) still comes from the instant fields.
            start = instantStart.map { merge(day: anchorDay, time: $0, calendar: calendar) } ?? anchorDay
        } else if let instantStart {
            start = instantStart
        } else {
            // Safety net: no anchor field set — never let the series vanish.
            start = PlannerumFormatters.iso8601.date(from: atom.createdAt).map { calendar.startOfDay(for: $0) }
                ?? calendar.startOfDay(for: Date())
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

    /// Shared mutation plumbing: fetch-validate-update with decode-state guards and a
    /// clear-honoring metadata merge. Throws instead of silently no-oping so callers can
    /// reverse optimistic UI and withhold habit/XP credit when persistence fails.
    private func mutateSeriesMetadata(
        templateUUID: String,
        context: String,
        requiresSnapshot: Bool,
        calendar: Calendar,
        _ mutate: @escaping (inout TaskMetadata, SeriesSnapshot?) -> Void
    ) async throws {
        guard let current = try await atomRepository.fetch(uuid: templateUUID) else {
            PersistenceHealth.note(.writeFailure, context: context, detail: "template \(templateUUID.prefix(8)) not found")
            throw RecurringSeriesEngineError.templateNotFound(templateUUID)
        }
        if case .corrupt(let error) = current.decodedMetadata(as: TaskMetadata.self) {
            PersistenceHealth.note(.decodeFailure, context: context, detail: "metadata undecodable; refusing write (\(error.localizedDescription))")
            throw RecurringSeriesEngineError.corruptMetadata(templateUUID)
        }
        if requiresSnapshot, Self.makeSnapshot(from: current, calendar: calendar) == nil {
            PersistenceHealth.note(.writeFailure, context: context, detail: "atom \(templateUUID.prefix(8)) is not a series template")
            throw RecurringSeriesEngineError.notASeriesTemplate(templateUUID)
        }

        var applied = false
        let result = try await atomRepository.update(uuid: templateUUID) { atom in
            var meta: TaskMetadata
            switch atom.decodedMetadata(as: TaskMetadata.self) {
            case .absent:
                meta = TaskMetadata()
            case .value(let decoded):
                meta = decoded
            case .corrupt(let error):
                PersistenceHealth.note(.decodeFailure, context: context, detail: "metadata undecodable at write time; refusing (\(error.localizedDescription))")
                return
            }

            let snapshot = Self.makeSnapshot(from: atom, calendar: calendar)
            if requiresSnapshot && snapshot == nil { return }

            mutate(&meta, snapshot)

            guard let merged = atom.mergingTaskMetadata(meta, context: context) else { return }
            atom = merged
            applied = true
        }

        guard applied, result != nil else {
            throw RecurringSeriesEngineError.persistenceFailed(templateUUID)
        }
    }

    /// Complete the live occurrence of a series. `occurrenceDay` is the day the live item
    /// represented. Records the completion, backfills intervening misses, advances live.
    /// Throws when the template is missing, its metadata is corrupt, or the write fails —
    /// callers must only award habit/XP credit when this returns.
    func complete(
        templateUUID: String,
        occurrenceDay: Date,
        on actionDate: Date = Date(),
        trackedMinutes: Int? = nil,
        calendar: Calendar = .current
    ) async throws {
        try await mutateSeriesMetadata(
            templateUUID: templateUUID,
            context: "RecurringSeriesEngine.complete(\(templateUUID.prefix(8)))",
            requiresSnapshot: true,
            calendar: calendar
        ) { meta, snapshot in
            guard let snapshot else { return }

            let todayStart = calendar.startOfDay(for: actionDate)
            let liveDay = calendar.startOfDay(for: occurrenceDay)

            // Credit today when today is a valid, on-or-after-live occurrence; else credit the
            // represented (overdue) day. This is what "jump ahead" means for a fresh completion.
            let todayValid = Self.isValidOccurrence(for: snapshot, day: todayStart, calendar: calendar)
            let completedDay = (todayValid && todayStart >= liveDay) ? todayStart : liveDay
            let completedKey = Self.dayKey(for: completedDay, calendar: calendar)

            var completed = meta.completedOccurrences ?? []
            let completedKeys = Set(completed.map(\.day))

            // Backfill: every valid occurrence in [liveDay, completedDay) not completed → missed.
            // Recorded on the completion entry so uncomplete can reverse exactly these days.
            var backfilled: [String] = []
            if completedDay > liveDay {
                var skipped = Set(meta.skippedOccurrences ?? [])
                let span = DateInterval(start: liveDay, end: completedDay)
                for date in snapshot.rule.occurrenceDates(in: span, startingFrom: snapshot.startDate, calendar: calendar) {
                    let key = Self.dayKey(for: calendar.startOfDay(for: date), calendar: calendar)
                    if key == completedKey || completedKeys.contains(key) { continue }
                    if skipped.insert(key).inserted {
                        backfilled.append(key)
                    }
                }
                meta.skippedOccurrences = skipped.isEmpty ? nil : Array(skipped).sorted()
            }

            if !completedKeys.contains(completedKey) {
                completed.append(TaskOccurrenceCompletion(
                    day: completedKey,
                    completedAt: PlannerumFormatters.iso8601.string(from: actionDate),
                    trackedMinutes: trackedMinutes,
                    backfilledDays: backfilled.isEmpty ? nil : backfilled.sorted()
                ))
            }
            meta.completedOccurrences = completed
        }
    }

    /// Reverse a logged completion for a specific occurrence day, including any "missed"
    /// days that completion backfilled.
    func uncomplete(templateUUID: String, occurrenceDay: Date, calendar: Calendar = .current) async throws {
        let key = Self.dayKey(for: occurrenceDay, calendar: calendar)
        try await mutateSeriesMetadata(
            templateUUID: templateUUID,
            context: "RecurringSeriesEngine.uncomplete(\(templateUUID.prefix(8)))",
            requiresSnapshot: false,
            calendar: calendar
        ) { meta, _ in
            let entries = meta.completedOccurrences ?? []
            let removedEntry = entries.first { $0.day == key }
            meta.completedOccurrences = entries.filter { $0.day != key }

            if var skipped = meta.skippedOccurrences {
                skipped.removeAll { $0 == key }
                if let backfilled = removedEntry?.backfilledDays {
                    let reversal = Set(backfilled)
                    skipped.removeAll { reversal.contains($0) }
                }
                meta.skippedOccurrences = skipped.isEmpty ? nil : skipped
            }
        }
    }

    /// Explicitly mark an occurrence skipped/missed without completing it.
    func skip(templateUUID: String, occurrenceDay: Date, calendar: Calendar = .current) async throws {
        let key = Self.dayKey(for: occurrenceDay, calendar: calendar)
        try await mutateSeriesMetadata(
            templateUUID: templateUUID,
            context: "RecurringSeriesEngine.skip(\(templateUUID.prefix(8)))",
            requiresSnapshot: false,
            calendar: calendar
        ) { meta, _ in
            var skipped = Set(meta.skippedOccurrences ?? [])
            skipped.insert(key)
            meta.skippedOccurrences = Array(skipped).sorted()
        }
    }

    // MARK: - Occurrence overrides (cancel / reschedule a single day)

    /// Remove a single occurrence from the series ("delete this occurrence") without
    /// touching the template, the rule, or the completion log. The projection skips
    /// canceled days entirely.
    func cancelOccurrence(templateUUID: String, dayKey: String, calendar: Calendar = .current) async throws {
        try await mutateSeriesMetadata(
            templateUUID: templateUUID,
            context: "RecurringSeriesEngine.cancelOccurrence(\(templateUUID.prefix(8))#\(dayKey))",
            requiresSnapshot: false,
            calendar: calendar
        ) { meta, _ in
            var overrides = meta.occurrenceOverrides ?? [:]
            var override = overrides[dayKey] ?? TaskOccurrenceOverride()
            override.isCanceled = true
            overrides[dayKey] = override
            meta.occurrenceOverrides = overrides
        }
    }

    /// Move a single occurrence to a different day without rewriting the template anchor
    /// (which would shift the entire series and its history).
    func rescheduleOccurrence(
        templateUUID: String,
        dayKey: String,
        to targetDay: Date,
        calendar: Calendar = .current
    ) async throws {
        let targetKey = Self.dayKey(for: targetDay, calendar: calendar)
        try await mutateSeriesMetadata(
            templateUUID: templateUUID,
            context: "RecurringSeriesEngine.rescheduleOccurrence(\(templateUUID.prefix(8))#\(dayKey))",
            requiresSnapshot: false,
            calendar: calendar
        ) { meta, _ in
            var overrides = meta.occurrenceOverrides ?? [:]
            var override = overrides[dayKey] ?? TaskOccurrenceOverride()
            // Rescheduling back onto its own rule day clears the override instead.
            override.rescheduledTo = targetKey == dayKey ? nil : targetKey
            if override == TaskOccurrenceOverride() {
                overrides.removeValue(forKey: dayKey)
            } else {
                overrides[dayKey] = override
            }
            meta.occurrenceOverrides = overrides.isEmpty ? nil : overrides
        }
    }

    // MARK: - Clean-slate migration (old materialized model → virtual occurrences)

    /// Legacy run-once flag. UserDefaults does NOT travel with the synced database —
    /// a reinstall/new Mac re-ran the destructive migration against already-migrated data.
    /// Honored read-only: when set, the durable DB flag is written and the body never runs.
    static let migrationDefaultsKey = "recurringSeries.cleanSlateMigration.v1"

    /// Durable run-once flag, stored in the same database as the data it protects.
    static let migrationFlagKey = "recurringSeriesCleanSlateMigration.v1"

    /// Serializes the migration across engine callers — MainView and CommandCenterDashboard
    /// both instantiate dashboard view models whose init triggers this.
    @MainActor private static var migrationTask: Task<Void, Never>?

    /// Run the one-shot switch-over from the old materialized-instance model, once per database.
    func runCleanSlateMigrationIfNeeded(now: Date = Date(), calendar: Calendar = .current) async {
        if let inFlight = Self.migrationTask {
            await inFlight.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.runGuardedCleanSlateMigration(now: now, calendar: calendar)
        }
        Self.migrationTask = task
        await task.value
    }

    private func runGuardedCleanSlateMigration(now: Date, calendar: Calendar) async {
        let database = CosmoDatabase.shared
        let flagKey = Self.migrationFlagKey

        func flagIsSet() async -> Bool {
            (try? await database.asyncRead { db in
                try Row.fetchOne(db, sql: "SELECT value FROM app_flags WHERE key = ?", arguments: [flagKey]) != nil
            }) ?? false
        }

        func setFlag() async {
            do {
                try await database.asyncWrite { db in
                    try db.execute(
                        sql: "INSERT OR REPLACE INTO app_flags (key, value, updated_at) VALUES (?, '1', ?)",
                        arguments: [flagKey, ISO8601.string(from: Date())]
                    )
                }
            } catch {
                PersistenceHealth.note(.writeFailure, context: "RecurringSeriesEngine.migrationFlag", detail: "failed to persist app_flags row: \(error.localizedDescription)")
            }
        }

        guard !(await flagIsSet()) else { return }

        // Legacy install that already migrated: promote the UserDefaults flag to the DB
        // and skip — never re-run the destructive body against migrated data.
        if UserDefaults.standard.bool(forKey: Self.migrationDefaultsKey) {
            await setFlag()
            return
        }

        let failureCount = await performCleanSlateMigration(now: now, calendar: calendar)
        if failureCount == 0 {
            await setFlag()
            UserDefaults.standard.set(true, forKey: Self.migrationDefaultsKey)
        } else {
            PersistenceHealth.note(
                .writeFailure,
                context: "RecurringSeriesEngine.cleanSlateMigration",
                detail: "\(failureCount) atom(s) failed; flag not set — remaining work retries next launch (per-template skips keep it non-destructive)"
            )
        }
    }

    /// Soft-delete generated recurring instance atoms (occurrences are projected now) and
    /// re-anchor each un-migrated series template to today. Data-shape-aware: a template whose
    /// completion/skip/override log is non-empty is already living on the new model and is
    /// NEVER touched — so a re-run (or a second device) cannot wipe recurring history.
    /// Returns the number of per-atom failures; the caller only sets the run-once flag at zero.
    func performCleanSlateMigration(now: Date = Date(), calendar: Calendar = .current) async -> Int {
        let tasks: [Atom]
        do {
            tasks = try await atomRepository.fetchAll(type: .task)
        } catch {
            PersistenceHealth.note(.writeFailure, context: "RecurringSeriesEngine.cleanSlateMigration", detail: "task fetch failed: \(error.localizedDescription)")
            return 1
        }

        let todayStart = calendar.startOfDay(for: now)
        var failures = 0

        for atom in tasks {
            let meta: TaskMetadata
            switch atom.decodedMetadata(as: TaskMetadata.self) {
            case .absent:
                continue
            case .value(let decoded):
                meta = decoded
            case .corrupt(let error):
                PersistenceHealth.note(.decodeFailure, context: "RecurringSeriesEngine.cleanSlateMigration(\(atom.uuid.prefix(8)))", detail: error.localizedDescription)
                failures += 1
                continue
            }

            do {
                // Generated instance → soft delete (tracked + synced) so the server receives
                // a tombstone instead of resurrecting the row on the next pull.
                if meta.recurrenceParentUUID != nil {
                    try await atomRepository.delete(uuid: atom.uuid)
                    continue
                }

                guard meta.recurrence != nil else { continue }

                // New-model template already live (has logged history) → never touch it.
                let hasLiveLog = !(meta.completedOccurrences ?? []).isEmpty
                    || !(meta.skippedOccurrences ?? []).isEmpty
                    || !(meta.occurrenceOverrides ?? [:]).isEmpty
                if hasLiveLog { continue }

                // Un-migrated template → re-anchor a past start to today.
                _ = try await atomRepository.update(uuid: atom.uuid) { mutable in
                    guard var m = mutable.metadataValue(as: TaskMetadata.self) else { return }
                    Self.reanchorToToday(&m, todayStart: todayStart, calendar: calendar)
                    if let merged = mutable.mergingTaskMetadata(m, context: "RecurringSeriesEngine.cleanSlateMigration(\(mutable.uuid.prefix(8)))") {
                        mutable = merged
                    }
                }
            } catch {
                PersistenceHealth.note(.writeFailure, context: "RecurringSeriesEngine.cleanSlateMigration(\(atom.uuid.prefix(8)))", detail: error.localizedDescription)
                failures += 1
            }
        }

        return failures
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
        meta.seriesAnchorDay = dayKey(for: todayStart, calendar: calendar)
    }
}
