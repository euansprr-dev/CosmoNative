// Core/ScheduleBlockEngine.swift
// Schedule blocks — pure time blocking, the shape shared with iOS: a
// `schedule_block` atom whose ScheduleBlockMetadata carries startTime/endTime,
// a palette color, an optional link, and (for repeating blocks) a
// RecurrenceRule JSON in `recurrence`. This engine mirrors the iOS
// ScheduleEngine contract exactly: recurring templates PROJECT a virtual
// occurrence onto every day their rule hits (nothing materializes), and
// `convertToTask` is the one door from a block into the task world.
// July 2026

import Foundation

/// One block occurrence on a day — either the literal one-off or a
/// projected occurrence of a repeating template.
struct ScheduleBlockEntry: Identifiable, Equatable {
    let id: String        // atom uuid
    let title: String
    let start: Date
    let end: Date
    let isCompleted: Bool
    /// Hex color ("#8B5CF6") from the shared block palette.
    let colorHex: String?
    /// A URL or place name.
    let location: String?
    /// Occurrence of a repeating template — edits apply to the whole series.
    let isRecurring: Bool
    /// Human summary of the repeat ("Every week on Mon, Fri").
    let recurrenceText: String?
}

enum ScheduleBlockEngine {

    /// iOS parity: snapping grain and block-length floor.
    static let minimumBlockMinutes = 15

    /// Schedule blocks landing on `day`, sorted by start. Recurring
    /// templates project using the template's time-of-day, anchored on the
    /// day the block was drawn (whole-series semantics — the block shape
    /// has no per-occurrence overrides).
    static func blocks(
        on day: Date,
        repository: AtomRepository = .shared,
        calendar: Calendar = .current
    ) async -> [ScheduleBlockEntry] {
        guard let atoms = try? await repository.fetchAll(type: .scheduleBlock) else { return [] }

        var items: [ScheduleBlockEntry] = []
        for atom in atoms {
            guard let meta = atom.metadataValue(as: ScheduleBlockMetadata.self),
                  let range = occurrenceRange(of: meta, on: day, calendar: calendar) else { continue }
            let rule = meta.recurrence.flatMap(RecurrenceRule.fromJSON)
            items.append(ScheduleBlockEntry(
                id: atom.uuid,
                title: atom.title ?? "Untitled",
                start: range.start,
                end: range.end,
                isCompleted: meta.isCompleted ?? false,
                colorHex: meta.color,
                location: meta.location,
                isRecurring: rule != nil,
                recurrenceText: rule?.displayText
            ))
        }
        return items.sorted { $0.start < $1.start }
    }

    /// A schedule block's slot on `day`, or nil when it doesn't occur there.
    /// One-offs match their literal day; repeating templates project their
    /// time-of-day shape onto every day their rule hits (whole-series
    /// semantics). The one projection shared by the timeline and the
    /// task-link resolution — identical to iOS ScheduleEngine.occurrenceRange.
    static func occurrenceRange(
        of meta: ScheduleBlockMetadata,
        on day: Date,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date)? {
        guard meta.isAllDay != true,
              let templateStart = meta.startTime.flatMap(ISO8601.date(from:)) else { return nil }
        let floor = templateStart.addingTimeInterval(TimeInterval(minimumBlockMinutes * 60))
        let templateEnd = meta.endTime.flatMap(ISO8601.date(from:)).map { max($0, floor) } ?? floor

        if let rule = meta.recurrence.flatMap(RecurrenceRule.fromJSON) {
            let dayStart = calendar.startOfDay(for: day)
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart),
                  !rule.occurrenceDates(
                      in: DateInterval(start: dayStart, end: dayEnd),
                      startingFrom: calendar.startOfDay(for: templateStart),
                      calendar: calendar
                  ).isEmpty else { return nil }
            let time = calendar.dateComponents([.hour, .minute, .second], from: templateStart)
            guard let start = calendar.date(
                bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0,
                of: dayStart
            ) else { return nil }
            return (start, start.addingTimeInterval(templateEnd.timeIntervalSince(templateStart)))
        }
        guard calendar.isDate(templateStart, inSameDayAs: day) else { return nil }
        return (templateStart, templateEnd)
    }

    /// Resolve every task's block link for display against `day` (iOS
    /// TodayEngine parity): title and color come from the block atom;
    /// start/end are the block's occurrence on the shown day — nil when it
    /// doesn't occur there, so the badge shows but can never read "live".
    /// Dangling pointers (block deleted/converted) resolve to all-nil,
    /// fail-soft — tombstones never come back from the repository.
    static func resolveLinks(
        in tasks: [TaskViewModel],
        on day: Date,
        repository: AtomRepository = .shared,
        calendar: Calendar = .current
    ) async -> [TaskViewModel] {
        guard tasks.contains(where: { $0.scheduleBlockUUID != nil }),
              let atoms = try? await repository.fetchAll(type: .scheduleBlock) else { return tasks }

        struct ResolvedBlock {
            let title: String
            let colorHex: String?
            let range: (start: Date, end: Date)?
        }
        var blocksByUUID: [String: ResolvedBlock] = [:]
        for atom in atoms {
            guard let meta = atom.metadataValue(as: ScheduleBlockMetadata.self) else { continue }
            blocksByUUID[atom.uuid] = ResolvedBlock(
                title: atom.title ?? "Untitled",
                colorHex: meta.color,
                range: occurrenceRange(of: meta, on: day, calendar: calendar)
            )
        }
        return tasks.map { task in
            guard let uuid = task.scheduleBlockUUID, let block = blocksByUUID[uuid] else { return task }
            var linked = task
            linked.blockTitle = block.title
            linked.blockColorHex = block.colorHex
            linked.blockStart = block.range?.start
            linked.blockEnd = block.range?.end
            return linked
        }
    }

    /// Promote a schedule block into a real task: the task inherits the
    /// block's title and slot (full Command Center range contract —
    /// dueDate/focusDate/whenDate pins plus startTime/endTime and
    /// scheduledStart/scheduledEnd), a repeating block becomes a recurring
    /// task series, and the block itself retires — one object, one truth.
    @discardableResult
    static func convertToTask(
        scheduleBlockUUID: String,
        repository: AtomRepository = .shared,
        calendar: Calendar = .current
    ) async throws -> Atom? {
        guard let block = try await repository.fetch(uuid: scheduleBlockUUID),
              block.type == .scheduleBlock,
              let blockMeta = block.metadataValue(as: ScheduleBlockMetadata.self),
              let start = blockMeta.startTime.flatMap(ISO8601.date(from:)) else { return nil }
        let floor = start.addingTimeInterval(TimeInterval(minimumBlockMinutes * 60))
        let end = blockMeta.endTime.flatMap(ISO8601.date(from:)).map { max($0, floor) } ?? floor

        var meta = TaskMetadata()
        let dayString = ISO8601.string(from: calendar.startOfDay(for: start))
        meta.dueDate = dayString
        meta.focusDate = dayString
        meta.whenDate = dayString
        meta.startTime = ISO8601.string(from: start)
        meta.endTime = ISO8601.string(from: end)
        meta.scheduledStart = meta.startTime
        meta.scheduledEnd = meta.endTime
        meta.durationMinutes = max(minimumBlockMinutes, Int(end.timeIntervalSince(start) / 60))
        if let recurrence = blockMeta.recurrence, RecurrenceRule.fromJSON(recurrence) != nil {
            meta.recurrence = recurrence
            meta.seriesAnchorDay = RecurringSeriesEngine.dayKey(for: start, calendar: calendar)
        }

        let metadata = Atom.mergedJSONObjectString(existing: nil, overlay: meta, context: "ScheduleBlockEngine.convertToTask")
        let task = try await repository.create(
            type: .task,
            title: block.title ?? "Untitled",
            metadata: metadata
        )
        try await repository.delete(uuid: scheduleBlockUUID)
        return task
    }
}
