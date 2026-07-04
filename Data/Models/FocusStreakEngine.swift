// Data/Models/FocusStreakEngine.swift
// Read-only aggregation over synced focus history: the daily goal, per-day
// totals from deep_work_block atoms, and streaks. Field-for-field twin of the
// iPhone's StreakEngine (CosmoCoreKit) — both read/write the SAME synced
// user_preference atom (scope "cosmo.daily_focus_goal"), so setting the goal
// on either device moves both gauges. Streak math: today never breaks the
// current streak while the day is still pending.

import Foundation

/// One day of focus history — `date` is a startOfDay. Second precision so a
/// short sitting counts the moment it lands.
struct FocusDay: Identifiable, Equatable {
    let date: Date
    let seconds: Int
    let met: Bool

    var minutes: Int { seconds / 60 }
    var id: Date { date }
}

struct FocusStreakEngine {
    private let repository: AtomRepository

    init(repository: AtomRepository = .shared) {
        self.repository = repository
    }

    // MARK: - Daily focus goal (synced user_preference atom — iPhone parity)

    static let goalScope = "cosmo.daily_focus_goal"

    /// The goal used before the user ever picks one — modest on purpose; the
    /// gauge starts meaningful from first launch.
    static let defaultGoalMinutes = 30

    private struct FocusGoal: Codable {
        var minutes: Int
        var updatedAt: String
    }

    /// nil = the user has not set a goal yet.
    func dailyFocusGoalMinutes() async throws -> Int? {
        guard let goal = try await goalAtom()?.structuredData(as: FocusGoal.self),
              goal.minutes > 0 else { return nil }
        return goal.minutes
    }

    func setDailyFocusGoal(minutes: Int, now: Date = Date()) async throws {
        let payload = FocusGoal(minutes: minutes, updatedAt: ISO8601.string(from: now))
        let structured = String(data: try JSONEncoder().encode(payload), encoding: .utf8)
        if let existing = try await goalAtom() {
            _ = try await repository.update(uuid: existing.uuid) { atom in
                atom.structured = structured
            }
        } else {
            _ = try await repository.create(Atom.new(
                type: .userPreference,
                title: "Daily focus goal",
                structured: structured,
                metadata: #"{"scope":"\#(Self.goalScope)"}"#
            ))
        }
    }

    private func goalAtom() async throws -> Atom? {
        let prefs = try await repository.fetchAll(type: .userPreference)
        return prefs.first { atom in
            guard let dict = atom.metadataDict else { return false }
            return (dict["scope"] as? String) == Self.goalScope
        }
    }

    // MARK: - Focus history

    /// All-history focus seconds bucketed by startOfDay, from deep_work_block
    /// atoms (Mac and phone sessions both land here via sync). iPhone blocks
    /// carry actualSeconds; Mac blocks carry whole minutes — both count.
    func focusSecondsByDay(calendar: Calendar = .current) async throws -> [Date: Int] {
        let atoms = try await repository.fetchAll(type: .deepWorkBlock)
        var seconds: [Date: Int] = [:]
        for atom in atoms {
            guard let dict = atom.metadataDict else { continue }
            let startString = dict["startedAt"] as? String ?? atom.createdAt
            guard let start = ISO8601.date(from: startString) else { continue }
            let day = calendar.startOfDay(for: start)
            let blockSeconds = dict["actualSeconds"] as? Int
                ?? ((dict["actualMinutes"] as? Int ?? dict["plannedMinutes"] as? Int ?? 0) * 60)
            seconds[day, default: 0] += blockSeconds
        }
        return seconds
    }

    /// The current week Mon→Sun (respecting the calendar's first weekday) —
    /// the gauge's dots row. Future days carry seconds 0 / met false.
    func focusWeek(
        goal: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async throws -> [FocusDay] {
        let byDay = try await focusSecondsByDay(calendar: calendar)
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: week.start) else { return nil }
            let seconds = byDay[day] ?? 0
            return FocusDay(date: day, seconds: seconds, met: goal > 0 && seconds >= goal * 60)
        }
    }

    /// Current + best focus streak against `goal`. Current counts trailing met
    /// days ending yesterday, plus today once met — an unfinished today never
    /// reads as a broken streak.
    func focusStreaks(
        goal: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async throws -> (current: Int, best: Int) {
        let byDay = try await focusSecondsByDay(calendar: calendar)
        let met: (Date) -> Bool = { day in goal > 0 && (byDay[day] ?? 0) >= goal * 60 }
        return Self.streaks(
            metDays: Set(byDay.keys.filter(met)),
            today: calendar.startOfDay(for: now),
            todayMet: met(calendar.startOfDay(for: now)),
            calendar: calendar
        )
    }

    // MARK: - Streak math (iPhone parity)

    static func streaks(
        metDays: Set<Date>,
        today: Date,
        todayMet: Bool,
        calendar: Calendar
    ) -> (current: Int, best: Int) {
        var current = todayMet ? 1 : 0
        var cursor = today
        while let previous = calendar.date(byAdding: .day, value: -1, to: cursor),
              metDays.contains(previous) {
            current += 1
            cursor = previous
        }

        var best = current
        var run = 0
        var expected: Date?
        for day in metDays.sorted() {
            if let anchor = expected, calendar.isDate(day, inSameDayAs: anchor) {
                run += 1
            } else {
                run = 1
            }
            expected = calendar.date(byAdding: .day, value: 1, to: day)
            best = max(best, run)
        }
        return (current, best)
    }
}
