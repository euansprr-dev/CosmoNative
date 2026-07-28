// Canvas/CommandCenter/UpcomingDropActions.swift
// July 2026 — Dropping an idea onto the Upcoming week board books a writing session.
//
// Pure resolution logic, deliberately free of SwiftUI and the repository so it
// can be tested under `swift test`. The view supplies geometry, this decides
// what the drop MEANS; the service performs the write.

import Foundation

enum UpcomingDropActions {

    // MARK: - Payload routing

    /// Where a dropped payload should land.
    enum Target: Equatable {
        /// An hour-grid drop: a real time block at an absolute start.
        case timed(ideaUUID: String, start: Date)
        /// An all-day-lane drop: pinned to the day, no time block.
        case allDay(ideaUUID: String, day: Date)
    }

    /// The idea uuid carried by a drag payload, or nil if this payload isn't
    /// ours.
    ///
    /// LAW — route on the prefix, never accept a bare uuid. Three vocabularies
    /// share the `String` drop channel: `ContentShelfPayload` falls through to
    /// `.content(uuid)` for anything unprefixed, while the Command Center
    /// sidebar and the Today spine read bare strings as TASK uuids. A bare uuid
    /// reaching the idea handler would fail its fetch and die silently, so
    /// anything we don't positively recognise is refused and the drop returns
    /// false — which lets another destination have it.
    static func ideaUUID(from payload: String) -> String? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard case .idea(let uuid) = ContentShelfPayload(string: trimmed), !uuid.isEmpty else {
            return nil
        }
        // `ContentShelfPayload` only yields `.idea` for a real "idea:" prefix,
        // so reaching here means the prefix was present.
        return uuid
    }

    /// First idea uuid among the dropped payloads (a drop can carry several).
    static func firstIdeaUUID(in payloads: [String]) -> String? {
        payloads.lazy.compactMap(ideaUUID(from:)).first
    }

    // MARK: - Geometry → target

    /// Resolve an hour-grid drop. `y` is in the day column's own coordinate
    /// space, which is exactly what the timeline canvas is laid out in.
    ///
    /// Uses the board's own `snappedDate(forY:on:)` on purpose: the drop must
    /// agree with drag-to-create, move, resize and the renderer's `yOffset`, all
    /// of which share that conversion. (That shared conversion measures elapsed
    /// minutes from midnight while the hour labels are wall-clock, so on the two
    /// DST days a year the whole grid is internally shifted — a pre-existing
    /// board-wide issue, not one this drop should solve differently and thereby
    /// render blocks away from where they were dropped.)
    static func timedTarget(
        ideaUUID: String,
        y: CGFloat,
        on day: Date,
        hourHeight: CGFloat = CommandCenterCalendarLayout.hourHeight,
        calendar: Calendar = .current
    ) -> Target {
        let start = CommandCenterCalendarLayout.snappedDate(
            forY: y,
            on: day,
            hourHeight: hourHeight,
            calendar: calendar
        )
        return .timed(ideaUUID: ideaUUID, start: start)
    }

    /// Resolve an all-day-lane drop.
    static func allDayTarget(
        ideaUUID: String,
        on day: Date,
        calendar: Calendar = .current
    ) -> Target {
        .allDay(ideaUUID: ideaUUID, day: calendar.startOfDay(for: day))
    }

    // MARK: - Toast wording

    /// The confirmation a completed drop shows. `siblings` > 0 names the open
    /// sessions the move deliberately left behind — an unmentioned second
    /// session is invisible, and invisible is how duplicates survive.
    static func toast(
        moved: Bool,
        siblings: Int,
        target: Target,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> String {
        let when: String
        switch target {
        case .timed(_, let start):
            when = "\(dayWord(start, calendar: calendar, now: now)) \(timeWord(start))"
        case .allDay(_, let day):
            when = dayWord(day, calendar: calendar, now: now)
        }

        if moved {
            return siblings > 0
                ? "Moved the soonest session · \(when)"
                : "Session moved · \(when)"
        }
        return "Writing session · \(when)"
    }

    /// "Today" / "Tomorrow" / "Tue 28" — the app's one day voice
    /// (`IdeasPageModel.dayLabel`).
    static func dayWord(_ date: Date, calendar: Calendar = .current, now: Date = .now) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        return date.formatted(.dateTime.weekday(.abbreviated).day())
    }

    private static func timeWord(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }
}
