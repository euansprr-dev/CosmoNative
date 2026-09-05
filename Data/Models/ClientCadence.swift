// CosmoOS/Data/Models/ClientCadence.swift
// A client's posting cadence, parsed from the free-text `postingFrequency`
// a dossier carries ("3x/week", "daily", "twice a week") into a weekly
// target the Clients page and hub can hold a Monday-week against.
//
// Pure and tested. Anything the table does not recognise parses to nil —
// a guessed quota is worse than no quota.
// September 2026

import Foundation

struct ClientCadence: Equatable, Sendable {
    /// Posts owed per Monday-start week.
    let perWeek: Int

    init?(perWeek: Int) {
        guard perWeek > 0 else { return nil }
        self.perWeek = perWeek
    }

    // MARK: - Parse

    /// Parse table (case-insensitive, trimmed):
    /// daily / every day / everyday / 7x → 7; weekly / once a week / 1x → 1;
    /// twice a week / twice weekly / 2 a week → 2; weekdays → 5;
    /// every other day → 3; `<n>x`, `<n>x/week`, `<n> per week`, `<n>/wk`,
    /// `<n> a week`, `<n>xw` → n; anything else → nil.
    static func parse(_ postingFrequency: String?) -> ClientCadence? {
        guard let raw = postingFrequency?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(), !raw.isEmpty else { return nil }
        let text = raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        if let fixed = fixedTable[text] { return ClientCadence(perWeek: fixed) }
        if let count = weeklyCount(in: text) { return ClientCadence(perWeek: count) }
        if let count = bareMultiplier(in: text) { return ClientCadence(perWeek: count) }
        return nil
    }

    private static let fixedTable: [String: Int] = [
        "daily": 7, "every day": 7, "everyday": 7, "once a day": 7, "7 days a week": 7,
        "weekly": 1, "once a week": 1, "once weekly": 1, "once per week": 1,
        "twice a week": 2, "twice weekly": 2, "twice per week": 2,
        "weekdays": 5, "every weekday": 5, "on weekdays": 5,
        "every other day": 3, "alternate days": 3,
    ]

    /// `(\d+)\s*x?\s*(/|per|a|each)?\s*(week|weekly|wk|w)\b` → n.
    private static let weeklyPattern: NSRegularExpression = {
        // Force-unwrap is safe: the pattern is a compile-time constant.
        try! NSRegularExpression(
            pattern: #"(\d+)\s*x?\s*(?:/|per|a|each)?\s*(?:week|weekly|wk|w)\b"#,
            options: [.caseInsensitive]
        )
    }()

    /// A bare `<n>x` ("3x") — the table's own "7x" / "1x" entries generalised.
    private static let barePattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"^(\d+)\s*x$"#, options: [.caseInsensitive])
    }()

    private static func weeklyCount(in text: String) -> Int? {
        firstCapturedInt(weeklyPattern, in: text)
    }

    private static func bareMultiplier(in text: String) -> Int? {
        firstCapturedInt(barePattern, in: text)
    }

    private static func firstCapturedInt(_ regex: NSRegularExpression, in text: String) -> Int? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: text),
              let value = Int(text[captured]), value > 0 else { return nil }
        return value
    }

    // MARK: - Quota

    /// This week's ledger: how many posts are scheduled-or-shipped against
    /// the cadence. `met` is never clamped — shipping 4 of 3 is honest news.
    func quota(scheduledOrShipped: Int) -> (met: Int, target: Int) {
        (met: max(0, scheduledOrShipped), target: perWeek)
    }

    /// Monday 00:00 of the week containing `date`, regardless of the
    /// calendar's own `firstWeekday` — the whole app plans Monday-start.
    static func weekStart(for date: Date, calendar: Calendar = .current) -> Date {
        var mondayFirst = calendar
        mondayFirst.firstWeekday = 2
        let day = mondayFirst.startOfDay(for: date)
        return mondayFirst.dateInterval(of: .weekOfYear, for: day)?.start ?? day
    }
}
