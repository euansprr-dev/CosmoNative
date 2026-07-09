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
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

        var items: [ScheduleBlockEntry] = []
        for atom in atoms {
            guard let meta = atom.metadataValue(as: ScheduleBlockMetadata.self),
                  meta.isAllDay != true,
                  let templateStart = meta.startTime.flatMap(ISO8601.date(from:)) else { continue }
            let floor = templateStart.addingTimeInterval(TimeInterval(minimumBlockMinutes * 60))
            let templateEnd = meta.endTime.flatMap(ISO8601.date(from:)).map { max($0, floor) } ?? floor

            if let rule = meta.recurrence.flatMap(RecurrenceRule.fromJSON) {
                guard !rule.occurrenceDates(
                    in: DateInterval(start: dayStart, end: dayEnd),
                    startingFrom: calendar.startOfDay(for: templateStart),
                    calendar: calendar
                ).isEmpty else { continue }
                let time = calendar.dateComponents([.hour, .minute, .second], from: templateStart)
                guard let start = calendar.date(
                    bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0,
                    of: dayStart
                ) else { continue }
                items.append(ScheduleBlockEntry(
                    id: atom.uuid,
                    title: atom.title ?? "Untitled",
                    start: start,
                    end: start.addingTimeInterval(templateEnd.timeIntervalSince(templateStart)),
                    isCompleted: meta.isCompleted ?? false,
                    colorHex: meta.color,
                    location: meta.location,
                    isRecurring: true,
                    recurrenceText: rule.displayText
                ))
            } else {
                guard calendar.isDate(templateStart, inSameDayAs: day) else { continue }
                items.append(ScheduleBlockEntry(
                    id: atom.uuid,
                    title: atom.title ?? "Untitled",
                    start: templateStart,
                    end: templateEnd,
                    isCompleted: meta.isCompleted ?? false,
                    colorHex: meta.color,
                    location: meta.location,
                    isRecurring: false,
                    recurrenceText: nil
                ))
            }
        }
        return items.sorted { $0.start < $1.start }
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
