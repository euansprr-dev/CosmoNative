// Canvas/CommandCenter/TaskInputParser.swift
// Natural language task input parser — extracts priority, dates, times, intents, and recurrence
// March 2026

import Foundation

struct ParsedTaskInput {
    var title: String
    var priority: TaskPriority?
    var dueDate: Date?
    var scheduledTime: Date?
    var intent: TaskIntent?
    var intentUUID: String?
    var recurrenceRule: RecurrenceRule?
    var durationMinutes: Int?
    var habitUUID: String?
    var habitTitle: String?
    var habitIcon: String?
    var habitColorHex: String?
    var habitAssignmentSource: HabitAssignmentSource?

    // MARK: - Things 3 Extensions
    var projectName: String?         // Parsed from #projectname
    var headingName: String?         // Parsed from +heading
    var timeOfDay: String?           // "morning" or "evening"
    var schedulingState: String?     // "someday" or "anytime"
    var deadline: Date?              // Parsed from "deadline: friday"

    // MARK: - Context (set by view, not parsed)
    var contextProjectUUID: String?  // Auto-set when adding from project view
    var contextHeadingUUID: String?  // Auto-set when adding under a heading

    // MARK: - Mentions (set by capture row, not parsed)
    var mentions: [RichMention] = []
}

/// Result of parsing an EXISTING task's title edit in the detail panel.
/// Unlike full capture parsing this touches only scheduling — project/heading
/// tags, intents, durations and clock times pass through untouched — and it
/// reports the utf16 range of every recognized token so the editor can
/// wash-highlight exactly what a commit will apply.
struct DetailTitleEdit {
    enum TokenKind: Equatable {
        case when
        case deadline
        case timeOfDay
        case schedulingState
        case priority(TaskPriority)
        case recurrence
    }

    struct Token: Equatable {
        let utf16Range: Range<Int>
        let kind: TokenKind
    }

    /// The title with recognized scheduling tokens stripped out.
    var title: String
    var whenDate: Date?
    var deadline: Date?
    var timeOfDay: String?
    var schedulingState: String?
    var priority: TaskPriority?
    var recurrenceRule: RecurrenceRule?
    /// Ranges into the ORIGINAL (unstripped) input, for highlighting.
    var tokens: [Token] = []

    var hasSchedulingChanges: Bool {
        whenDate != nil || deadline != nil || timeOfDay != nil
            || schedulingState != nil || priority != nil || recurrenceRule != nil
    }
}

/// A capture-grammar token with its utf16 range in the ORIGINAL input — the
/// highlight mirror of `parse`, which strips tokens and reports values only.
/// The scan blanks consumed text in `parse`'s exact order, so the wash shows
/// what a submit will apply without promising anything it won't.
struct CaptureWashToken: Equatable {
    enum Kind: Equatable {
        case schedulingState(String)
        case timeOfDay(String)
        case projectTag
        case headingTag
        case deadline
        case priority(TaskPriority)
        case intent(TaskIntent)
        case recurrence
        case duration
        case time
        case date
    }

    let utf16Range: Range<Int>
    let kind: Kind
}

@MainActor
enum TaskInputParser {

    /// Parse a natural language task input string into structured metadata.
    ///
    /// `referenceDate` is the day the capture is happening on — the day the user
    /// is currently viewing on the Today page (today, tomorrow, or any paged day).
    /// It only seeds the IMPLICIT day for a bare time ("at 6pm") or a bare
    /// recurrence ("every Tue") — explicit date words ("today"/"tomorrow"/"mon")
    /// stay relative to the real now inside `extractDate`.
    static func parse(_ input: String, referenceDate: Date = Date()) -> ParsedTaskInput {
        var remaining = input
        var result = ParsedTaskInput(title: "")

        // Extract Things 3 scheduling keywords first (before date parsing)
        result.schedulingState = extractSchedulingState(&remaining)
        result.timeOfDay = extractTimeOfDay(&remaining)
        result.projectName = extractProjectTag(&remaining)
        result.headingName = extractHeadingTag(&remaining)
        result.deadline = extractDeadline(&remaining)

        // Extract priority (p1/p2/p3/p4)
        result.priority = extractPriority(&remaining)

        // Extract intent keywords
        result.intent = extractIntent(&remaining)
        result.intentUUID = CommandCenterIntentEngine.shared.seedID(for: result.intent)

        // Extract recurrence phrases before weekday/date parsing consumes them
        result.recurrenceRule = extractRecurrence(&remaining)

        // Extract duration ("for 2 hours", "for 45m") before time parsing
        result.durationMinutes = extractDuration(&remaining)

        // Extract time (2pm, 14:00, at 3:30pm)
        result.scheduledTime = extractTime(&remaining)

        // Extract date (today, tomorrow, monday, next week, mar 15)
        result.dueDate = extractDate(&remaining)

        // If we got a time but no date, assume the day being viewed (not always today).
        if result.scheduledTime != nil && result.dueDate == nil {
            result.dueDate = referenceDate
        }

        // If recurrence is present but no explicit date was provided, seed from the next occurrence on/after the viewed day.
        if result.recurrenceRule != nil && result.dueDate == nil {
            result.dueDate = nextOccurrenceDate(for: result.recurrenceRule!, from: referenceDate)
        }

        // Clean up title
        result.title = remaining
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "  ", with: " ")

        if let resolution = CommandCenterHabitEngine.shared.resolveHabit(title: result.title, intent: result.intent) {
            result.habitUUID = resolution.definition.id
            result.habitTitle = resolution.definition.title
            result.habitIcon = resolution.definition.icon
            result.habitColorHex = resolution.definition.accentColor
            result.habitAssignmentSource = resolution.source
            if result.intentUUID == nil {
                result.intentUUID = resolution.definition.defaultIntentUUID
            }
        }

        return result
    }

    // MARK: - Detail-panel title edits (highlight + commit share one pass)

    /// Parse a title edit from the task detail panel. Every recognized token's
    /// range is reported against the ORIGINAL input so the field can wash it;
    /// `title` comes back with those same tokens stripped. Text inside an
    /// `@mention` is opaque — a weekday in "@Monday plan" never schedules.
    static func parseDetailEdit(_ input: String, mentions: [RichMention] = []) -> DetailTitleEdit {
        var edit = DetailTitleEdit(title: input)

        // Two aligned buffers: `detect` is scanned (mention spans blanked with
        // a non-word placeholder), `output` becomes the stripped title. Every
        // replacement preserves utf16 length, so ranges stay valid throughout.
        var detect = input as NSString
        var output = input as NSString

        for mention in mentions {
            let span = detect.range(of: "@\(mention.titleSnapshot)")
            guard span.location != NSNotFound else { continue }
            detect = detect.replacingCharacters(
                in: span, with: String(repeating: "\u{FFFC}", count: span.length)
            ) as NSString
        }

        func firstMatch(
            _ pattern: String,
            options: NSRegularExpression.Options = [.caseInsensitive]
        ) -> NSTextCheckingResult? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
            return regex.firstMatch(in: detect as String, range: NSRange(location: 0, length: detect.length))
        }

        func consume(_ range: NSRange, kind: DetailTitleEdit.TokenKind) {
            let blank = String(repeating: " ", count: range.length)
            detect = detect.replacingCharacters(in: range, with: blank) as NSString
            output = output.replacingCharacters(in: range, with: blank) as NSString
            edit.tokens.append(.init(utf16Range: range.location..<(range.location + range.length), kind: kind))
        }

        // /someday, /anytime
        for (pattern, state) in schedulingStatePatterns {
            guard let match = firstMatch(pattern) else { continue }
            edit.schedulingState = state
            consume(match.range, kind: .schedulingState)
            break
        }

        // /morning, /am, /evening, /eve
        for (pattern, timeOfDay) in timeOfDayPatterns {
            guard let match = firstMatch(pattern) else { continue }
            edit.timeOfDay = timeOfDay
            consume(match.range, kind: .timeOfDay)
            break
        }

        // "deadline: friday" — consumed before the bare date scan so the date
        // word inside lands on Deadline, not When.
        if let match = firstMatch(deadlinePattern) {
            var dateStr = detect.substring(with: match.range(at: 1))
            if let date = extractDate(&dateStr) {
                edit.deadline = date
                consume(match.range, kind: .deadline)
            }
        }

        // Priority codes — case-sensitive, same as capture parsing.
        for (pattern, priority) in priorityPatterns {
            guard let match = firstMatch(pattern, options: []) else { continue }
            edit.priority = priority
            consume(match.range, kind: .priority(priority))
            break
        }

        // Recurrence phrases before weekday/date parsing consumes them.
        for (pattern, rule) in recurrencePhrasePatterns {
            guard let match = firstMatch(pattern) else { continue }
            edit.recurrenceRule = rule
            consume(match.range, kind: .recurrence)
            break
        }
        if edit.recurrenceRule == nil,
           let match = firstMatch(weekdayListRecurrencePattern) {
            let days = parseWeekdayList(detect.substring(with: match.range(at: 1)))
            if !days.isEmpty {
                edit.recurrenceRule = .weekly(on: days)
                consume(match.range, kind: .recurrence)
            }
        }

        // Dates → When
        let cal = Calendar.current
        let today = Date()
        for (pattern, date) in namedDatePatterns(calendar: cal, today: today) {
            guard let match = firstMatch(pattern), let date else { continue }
            edit.whenDate = date
            consume(match.range, kind: .when)
            break
        }
        if edit.whenDate == nil, let match = firstMatch("\\bin\\s+(\\d+)\\s+days?\\b"),
           let days = Int(detect.substring(with: match.range(at: 1))) {
            edit.whenDate = cal.date(byAdding: .day, value: days, to: today)
            consume(match.range, kind: .when)
        }
        if edit.whenDate == nil,
           let match = firstMatch(namedMonthDayPattern),
           let month = monthFromAbbreviation(detect.substring(with: match.range(at: 1)).lowercased()),
           let day = Int(detect.substring(with: match.range(at: 2))) {
            var components = cal.dateComponents([.year], from: today)
            components.month = month
            components.day = day
            if let date = cal.date(from: components) {
                edit.whenDate = date < today ? cal.date(byAdding: .year, value: 1, to: date) : date
                consume(match.range, kind: .when)
            }
        }
        if edit.whenDate == nil,
           let match = firstMatch(numericMonthDayPattern),
           let month = Int(detect.substring(with: match.range(at: 1))),
           let day = Int(detect.substring(with: match.range(at: 2))) {
            var components = cal.dateComponents([.year], from: today)
            components.month = month
            components.day = day
            if let date = cal.date(from: components) {
                edit.whenDate = date < today ? cal.date(byAdding: .year, value: 1, to: date) : date
                consume(match.range, kind: .when)
            }
        }

        // A recurrence without an explicit date seeds from its next occurrence.
        if let rule = edit.recurrenceRule, edit.whenDate == nil {
            edit.whenDate = nextOccurrenceDate(for: rule, from: today)
        }

        edit.title = (output as String)
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return edit
    }

    // MARK: - Capture wash tokens (highlight mirror of `parse`)

    /// Scan a capture input for every token `parse` would consume, reporting
    /// ranges against the ORIGINAL text so a creation field can wash them in
    /// place — the ⌥C treatment. Text inside an `@mention` is opaque, same as
    /// `parseDetailEdit`. Intent keywords are reported but never stripped by
    /// `parse`, so they wash while staying part of the title.
    static func captureWashTokens(_ input: String, mentions: [RichMention] = []) -> [CaptureWashToken] {
        var tokens: [CaptureWashToken] = []
        var detect = input as NSString

        for mention in mentions {
            let span = detect.range(of: "@\(mention.titleSnapshot)")
            guard span.location != NSNotFound else { continue }
            detect = detect.replacingCharacters(
                in: span, with: String(repeating: "\u{FFFC}", count: span.length)
            ) as NSString
        }

        func firstMatch(
            _ pattern: String,
            options: NSRegularExpression.Options = [.caseInsensitive]
        ) -> NSTextCheckingResult? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
            return regex.firstMatch(in: detect as String, range: NSRange(location: 0, length: detect.length))
        }

        func blank(_ range: NSRange) {
            detect = detect.replacingCharacters(
                in: range, with: String(repeating: " ", count: range.length)
            ) as NSString
        }

        func consume(_ range: NSRange, kind: CaptureWashToken.Kind) {
            blank(range)
            tokens.append(.init(utf16Range: range.location..<(range.location + range.length), kind: kind))
        }

        // Same order as `parse` — earlier passes consume before later ones scan.
        for (pattern, state) in schedulingStatePatterns {
            guard let match = firstMatch(pattern) else { continue }
            consume(match.range, kind: .schedulingState(state))
            break
        }

        for (pattern, timeOfDay) in timeOfDayPatterns {
            guard let match = firstMatch(pattern) else { continue }
            consume(match.range, kind: .timeOfDay(timeOfDay))
            break
        }

        if let match = firstMatch("#(\\S+)", options: []) {
            consume(match.range, kind: .projectTag)
        }
        if let match = firstMatch("\\+(\\S+)", options: []) {
            consume(match.range, kind: .headingTag)
        }

        // `parse` strips the deadline phrase whether or not the date inside it
        // parses — so blank it either way, but only wash a real deadline.
        if let match = firstMatch(deadlinePattern) {
            var dateStr = detect.substring(with: match.range(at: 1))
            if extractDate(&dateStr) != nil {
                consume(match.range, kind: .deadline)
            } else {
                blank(match.range)
            }
        }

        for (pattern, priority) in priorityPatterns {
            guard let match = firstMatch(pattern, options: []) else { continue }
            consume(match.range, kind: .priority(priority))
            break
        }

        for (pattern, intent) in intentKeywords {
            guard let match = firstMatch(pattern) else { continue }
            let location = match.range.location
            let isAtStart = location == 0
            let isAfterSpace = location > 0 && detect.character(at: location - 1) == 0x20
            if isAtStart || isAfterSpace {
                // Reported without blanking — `parse` keeps the word in the title.
                tokens.append(.init(
                    utf16Range: location..<(location + match.range.length),
                    kind: .intent(intent)
                ))
                break
            }
        }

        var matchedRecurrence = false
        for (pattern, _) in recurrencePhrasePatterns {
            guard let match = firstMatch(pattern) else { continue }
            consume(match.range, kind: .recurrence)
            matchedRecurrence = true
            break
        }
        if !matchedRecurrence, let match = firstMatch(weekdayListRecurrencePattern) {
            let days = parseWeekdayList(detect.substring(with: match.range(at: 1)))
            if !days.isEmpty {
                consume(match.range, kind: .recurrence)
            }
        }

        for (pattern, minutes) in durationPatterns {
            guard let match = firstMatch(pattern),
                  let value = minutes(match, detect as String), value > 0 else { continue }
            consume(match.range, kind: .duration)
            break
        }

        for pattern in timePatterns {
            guard let match = firstMatch(pattern) else { continue }
            let timeStr = detect.substring(with: match.range(at: 1))
            if parseTimeString(timeStr) != nil {
                consume(match.range, kind: .time)
                break
            }
        }

        let cal = Calendar.current
        let today = Date()
        var matchedDate = false
        for (pattern, date) in namedDatePatterns(calendar: cal, today: today) {
            guard let match = firstMatch(pattern), date != nil else { continue }
            consume(match.range, kind: .date)
            matchedDate = true
            break
        }
        if !matchedDate, let match = firstMatch("\\bin\\s+(\\d+)\\s+days?\\b"),
           Int(detect.substring(with: match.range(at: 1))) != nil {
            consume(match.range, kind: .date)
            matchedDate = true
        }
        if !matchedDate,
           let match = firstMatch(namedMonthDayPattern),
           let month = monthFromAbbreviation(detect.substring(with: match.range(at: 1)).lowercased()),
           let day = Int(detect.substring(with: match.range(at: 2))) {
            var components = cal.dateComponents([.year], from: today)
            components.month = month
            components.day = day
            if cal.date(from: components) != nil {
                consume(match.range, kind: .date)
                matchedDate = true
            }
        }
        if !matchedDate,
           let match = firstMatch(numericMonthDayPattern),
           let month = Int(detect.substring(with: match.range(at: 1))),
           let day = Int(detect.substring(with: match.range(at: 2))) {
            var components = cal.dateComponents([.year], from: today)
            components.month = month
            components.day = day
            if cal.date(from: components) != nil {
                consume(match.range, kind: .date)
            }
        }

        return tokens
    }

    // MARK: - Shared token grammar (parse / parseDetailEdit / captureWashTokens)

    private static let schedulingStatePatterns: [(String, String)] = [
        ("\\/someday\\b", "someday"),
        ("\\/anytime\\b", "anytime"),
    ]

    private static let timeOfDayPatterns: [(String, String)] = [
        ("\\/morning\\b", "morning"),
        ("\\/am\\b", "morning"),
        ("\\/evening\\b", "evening"),
        ("\\/eve\\b", "evening"),
    ]

    private static let deadlinePattern = "\\bdeadline:\\s*(\\S+(?:\\s+\\d{1,2})?)"

    private static let priorityPatterns: [(String, TaskPriority)] = [
        ("\\bp1\\b", .critical),
        ("\\bp2\\b", .high),
        ("\\bp3\\b", .medium),
        ("\\bp4\\b", .low),
        ("\\b!1\\b", .critical),
        ("\\b!!\\b", .high),
        ("\\b!\\b", .medium),
    ]

    private static let intentKeywords: [(String, TaskIntent)] = [
        ("\\bwrite\\b", .writeContent),
        ("\\bwriting\\b", .writeContent),
        ("\\bdraft\\b", .writeContent),
        ("\\bresearch\\b", .research),
        ("\\bstudy\\b", .studySwipes),
        ("\\bswipe\\b", .studySwipes),
        ("\\bthink\\b", .deepThink),
        ("\\breview\\b", .review),
    ]

    /// Computed fresh per call — the monthly rule anchors to today's day.
    private static var recurrencePhrasePatterns: [(String, RecurrenceRule)] {
        [
            ("\\bevery\\s+day\\b", .daily()),
            ("\\bdaily\\b", .daily()),
            ("\\bevery\\s+weekday(?:s)?\\b", .weekdays()),
            ("\\bweekday(?:s)?\\b", .weekdays()),
            ("\\bevery\\s+month\\b", .monthly(onDay: Calendar.current.component(.day, from: Date()))),
        ]
    }

    private static let weekdayListRecurrencePattern =
        "\\bevery\\s+((?:(?:mon(?:day)?|tue(?:s|sday)?|wed(?:nesday)?|thu(?:r|rs|rsday)?|thur(?:s|sday)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)(?:\\s*(?:,|and)\\s*|\\s+)?)+)"

    private static let durationPatterns: [(pattern: String, minutes: (NSTextCheckingResult, String) -> Int?)] = [
        // "for 1h30m" / "for 1h 30m"
        ("\\bfor\\s+(\\d{1,2})\\s*h(?:ours?)?\\s*(\\d{1,2})\\s*m(?:in(?:ute)?s?)?\\b", { match, text in
            guard let hoursRange = Range(match.range(at: 1), in: text),
                  let minutesRange = Range(match.range(at: 2), in: text),
                  let hours = Int(text[hoursRange]),
                  let minutes = Int(text[minutesRange]) else { return nil }
            return hours * 60 + minutes
        }),
        // "for 1.5 hours" / "for 2 hours" / "for 2h"
        ("\\bfor\\s+(\\d{1,2}(?:\\.\\d)?)\\s*h(?:ours?|rs?)?\\b", { match, text in
            guard let valueRange = Range(match.range(at: 1), in: text),
                  let hours = Double(text[valueRange]) else { return nil }
            return Int((hours * 60).rounded())
        }),
        // "for 90 minutes" / "for 45 min" / "for 30m"
        ("\\bfor\\s+(\\d{1,3})\\s*m(?:in(?:ute)?s?)?\\b", { match, text in
            guard let valueRange = Range(match.range(at: 1), in: text) else { return nil }
            return Int(text[valueRange])
        }),
    ]

    private static let timePatterns = [
        "\\bat\\s+(\\d{1,2}:\\d{2}\\s*(?:am|pm))\\b",
        "\\bat\\s+(\\d{1,2}\\s*(?:am|pm))\\b",
        "\\bat\\s+(\\d{1,2}:\\d{2})\\b",
        "\\b(\\d{1,2}:\\d{2}\\s*(?:am|pm))\\b",
        "\\b(\\d{1,2}(?:am|pm))\\b",
    ]

    private static let namedMonthDayPattern = "\\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\\w*\\s+(\\d{1,2})\\b"
    private static let numericMonthDayPattern = "\\b(\\d{1,2})/(\\d{1,2})\\b"

    private static func namedDatePatterns(calendar cal: Calendar, today: Date) -> [(String, Date?)] {
        [
            ("\\btoday\\b", today),
            ("\\btomorrow\\b", cal.date(byAdding: .day, value: 1, to: today)),
            ("\\bnext week\\b", cal.date(byAdding: .weekOfYear, value: 1, to: today)),
            ("\\bmonday\\b", nextWeekday(.monday, from: today)),
            ("\\btuesday\\b", nextWeekday(.tuesday, from: today)),
            ("\\bwednesday\\b", nextWeekday(.wednesday, from: today)),
            ("\\bthursday\\b", nextWeekday(.thursday, from: today)),
            ("\\bfriday\\b", nextWeekday(.friday, from: today)),
            ("\\bsaturday\\b", nextWeekday(.saturday, from: today)),
            ("\\bsunday\\b", nextWeekday(.sunday, from: today)),
        ]
    }

    // MARK: - Things 3 Scheduling Extractions

    /// Extract /someday or /anytime from input
    private static func extractSchedulingState(_ input: inout String) -> String? {
        for (pattern, state) in schedulingStatePatterns {
            if let range = input.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                input.removeSubrange(range)
                return state
            }
        }
        return nil
    }

    /// Extract /morning, /am, /evening, /eve from input
    private static func extractTimeOfDay(_ input: inout String) -> String? {
        for (pattern, timeOfDay) in timeOfDayPatterns {
            if let range = input.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                input.removeSubrange(range)
                return timeOfDay
            }
        }
        return nil
    }

    /// Extract #projectname from input
    private static func extractProjectTag(_ input: inout String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "#(\\S+)", options: []) else { return nil }
        let nsRange = NSRange(input.startIndex..<input.endIndex, in: input)
        guard let match = regex.firstMatch(in: input, range: nsRange),
              let nameRange = Range(match.range(at: 1), in: input),
              let fullRange = Range(match.range, in: input) else { return nil }

        let name = String(input[nameRange])
        input.removeSubrange(fullRange)
        return name
    }

    /// Extract +heading from input (only meaningful in project view)
    private static func extractHeadingTag(_ input: inout String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\\+(\\S+)", options: []) else { return nil }
        let nsRange = NSRange(input.startIndex..<input.endIndex, in: input)
        guard let match = regex.firstMatch(in: input, range: nsRange),
              let nameRange = Range(match.range(at: 1), in: input),
              let fullRange = Range(match.range, in: input) else { return nil }

        let name = String(input[nameRange])
        input.removeSubrange(fullRange)
        return name
    }

    /// Extract "deadline: friday" or "deadline: mar 15" from input
    private static func extractDeadline(_ input: inout String) -> Date? {
        guard let regex = try? NSRegularExpression(
            pattern: deadlinePattern,
            options: .caseInsensitive
        ) else { return nil }

        let nsRange = NSRange(input.startIndex..<input.endIndex, in: input)
        guard let match = regex.firstMatch(in: input, range: nsRange),
              let dateStrRange = Range(match.range(at: 1), in: input),
              let fullRange = Range(match.range, in: input) else { return nil }

        var dateStr = String(input[dateStrRange])
        input.removeSubrange(fullRange)

        // Try to parse the deadline date expression
        let parsedDate = extractDate(&dateStr)
        return parsedDate
    }

    // MARK: - Priority

    private static func extractPriority(_ input: inout String) -> TaskPriority? {
        for (pattern, priority) in priorityPatterns {
            if let range = input.range(of: pattern, options: .regularExpression, range: input.startIndex..<input.endIndex) {
                input.removeSubrange(range)
                return priority
            }
        }
        return nil
    }

    // MARK: - Intent

    private static func extractIntent(_ input: inout String) -> TaskIntent? {
        for (pattern, intent) in intentKeywords {
            if let range = input.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                // Only extract if it appears to be a keyword, not part of a title
                // Check if it's at the start or preceded by space
                let beforeIndex = range.lowerBound
                let isAtStart = beforeIndex == input.startIndex
                let isAfterSpace = !isAtStart && input[input.index(before: beforeIndex)] == " "

                if isAtStart || isAfterSpace {
                    // Don't remove intent keywords from title — they might be part of task name
                    return intent
                }
            }
        }
        return nil
    }

    // MARK: - Time

    private static func extractRecurrence(_ input: inout String) -> RecurrenceRule? {
        for (pattern, rule) in recurrencePhrasePatterns {
            if let range = input.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                input.removeSubrange(range)
                return rule
            }
        }

        guard let regex = try? NSRegularExpression(
            pattern: weekdayListRecurrencePattern,
            options: .caseInsensitive
        ) else {
            return nil
        }

        let nsRange = NSRange(input.startIndex..<input.endIndex, in: input)
        guard let match = regex.firstMatch(in: input, range: nsRange),
              let daysRange = Range(match.range(at: 1), in: input) else {
            return nil
        }

        let daysString = String(input[daysRange])
        let days = parseWeekdayList(daysString)
        guard !days.isEmpty, let fullRange = Range(match.range, in: input) else {
            return nil
        }

        input.removeSubrange(fullRange)
        return .weekly(on: days)
    }

    /// Extract "for 2 hours", "for 1.5h", "for 90 minutes", "for 45m",
    /// "for 1h30m" — a scheduling-estimate duration in minutes.
    private static func extractDuration(_ input: inout String) -> Int? {
        for (pattern, minutes) in durationPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let nsRange = NSRange(input.startIndex..<input.endIndex, in: input)
            guard let match = regex.firstMatch(in: input, range: nsRange),
                  let value = minutes(match, input), value > 0,
                  let fullRange = Range(match.range, in: input) else { continue }
            input.removeSubrange(fullRange)
            return value
        }
        return nil
    }

    private static func extractTime(_ input: inout String) -> Date? {
        // Match "at 2pm", "at 14:00", "2pm", "2:30pm", "14:00"
        for pattern in timePatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let nsRange = NSRange(input.startIndex..<input.endIndex, in: input)

            if let match = regex.firstMatch(in: input, range: nsRange),
               let timeRange = Range(match.range(at: 1), in: input) {
                let timeStr = String(input[timeRange])
                if let date = parseTimeString(timeStr) {
                    let fullRange = Range(match.range, in: input)!
                    input.removeSubrange(fullRange)
                    return date
                }
            }
        }
        return nil
    }

    private static func parseTimeString(_ str: String) -> Date? {
        let formatters = [
            "h:mma", "h:mm a", "ha", "h a", "HH:mm", "H:mm"
        ]

        let cleaned = str.trimmingCharacters(in: .whitespaces).lowercased()

        for format in formatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")

            if let time = formatter.date(from: cleaned) {
                // Set to today with that time
                let cal = Calendar.current
                let components = cal.dateComponents([.hour, .minute], from: time)
                return cal.date(bySettingHour: components.hour ?? 0, minute: components.minute ?? 0, second: 0, of: Date())
            }
        }
        return nil
    }

    // MARK: - Date

    private static func extractDate(_ input: inout String) -> Date? {
        let cal = Calendar.current
        let today = Date()

        // Named dates
        for (pattern, date) in namedDatePatterns(calendar: cal, today: today) {
            if let range = input.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                input.removeSubrange(range)
                return date
            }
        }

        // "in X days"
        if let regex = try? NSRegularExpression(pattern: "\\bin\\s+(\\d+)\\s+days?\\b", options: .caseInsensitive) {
            let nsRange = NSRange(input.startIndex..<input.endIndex, in: input)
            if let match = regex.firstMatch(in: input, range: nsRange),
               let numRange = Range(match.range(at: 1), in: input),
               let days = Int(input[numRange]) {
                let fullRange = Range(match.range, in: input)!
                input.removeSubrange(fullRange)
                return cal.date(byAdding: .day, value: days, to: today)
            }
        }

        // Month day: "mar 15", "march 15", "3/15"
        let monthPatterns = [
            (namedMonthDayPattern, true),
            (numericMonthDayPattern, false),
        ]

        for (pattern, isNamedMonth) in monthPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let nsRange = NSRange(input.startIndex..<input.endIndex, in: input)

            if let match = regex.firstMatch(in: input, range: nsRange) {
                let fullRange = Range(match.range, in: input)!

                if isNamedMonth,
                   let monthRange = Range(match.range(at: 1), in: input),
                   let dayRange = Range(match.range(at: 2), in: input) {
                    let monthStr = String(input[monthRange]).lowercased()
                    let dayStr = String(input[dayRange])

                    if let month = monthFromAbbreviation(monthStr), let day = Int(dayStr) {
                        var components = cal.dateComponents([.year], from: today)
                        components.month = month
                        components.day = day
                        if let date = cal.date(from: components) {
                            input.removeSubrange(fullRange)
                            return date < today ? cal.date(byAdding: .year, value: 1, to: date) : date
                        }
                    }
                } else if !isNamedMonth,
                          let monthRange = Range(match.range(at: 1), in: input),
                          let dayRange = Range(match.range(at: 2), in: input) {
                    if let month = Int(input[monthRange]), let day = Int(input[dayRange]) {
                        var components = cal.dateComponents([.year], from: today)
                        components.month = month
                        components.day = day
                        if let date = cal.date(from: components) {
                            input.removeSubrange(fullRange)
                            return date < today ? cal.date(byAdding: .year, value: 1, to: date) : date
                        }
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Helpers

    private static func parseWeekdayList(_ input: String) -> [DayOfWeek] {
        let normalized = input
            .lowercased()
            .replacingOccurrences(of: "and", with: ",")
            .replacingOccurrences(of: ".", with: "")

        let parts = normalized
            .split(separator: ",")
            .flatMap { chunk in
                chunk.split(whereSeparator: \.isWhitespace)
            }

        var days: [DayOfWeek] = []
        for part in parts {
            guard let day = weekdayFromToken(String(part)) else { continue }
            if !days.contains(day) {
                days.append(day)
            }
        }
        return days
    }

    private static func weekdayFromToken(_ token: String) -> DayOfWeek? {
        switch token {
        case "mon", "monday":
            return .monday
        case "tue", "tues", "tuesday":
            return .tuesday
        case "wed", "weds", "wednesday":
            return .wednesday
        case "thu", "thur", "thurs", "thursday":
            return .thursday
        case "fri", "friday":
            return .friday
        case "sat", "saturday":
            return .saturday
        case "sun", "sunday":
            return .sunday
        default:
            return nil
        }
    }

    private static func nextOccurrenceDate(for rule: RecurrenceRule, from date: Date) -> Date? {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)

        switch rule.frequency {
        case .daily:
            return start
        case .weekdays:
            let weekday = calendar.component(.weekday, from: start)
            if (2...6).contains(weekday) {
                return start
            }
            return nextWeekday(.monday, from: start)
        case .weekly, .biweekly, .custom:
            let orderedDays = (rule.daysOfWeek ?? []).sorted { $0.rawValue < $1.rawValue }
            if orderedDays.isEmpty {
                return start
            }

            let currentWeekday = calendar.component(.weekday, from: start)
            if let sameOrLater = orderedDays.first(where: { $0.rawValue >= currentWeekday }) {
                let delta = sameOrLater.rawValue - currentWeekday
                return calendar.date(byAdding: .day, value: delta, to: start)
            }

            let next = orderedDays[0]
            let delta = (7 - currentWeekday) + next.rawValue
            return calendar.date(byAdding: .day, value: delta, to: start)
        case .monthly:
            let targetDay = rule.dayOfMonth ?? calendar.component(.day, from: start)
            if calendar.component(.day, from: start) <= targetDay,
               let thisMonth = calendar.date(
                   from: calendar.dateComponents([.year, .month], from: start)
               ).flatMap({
                   calendar.date(byAdding: .day, value: max(0, targetDay - 1), to: $0)
               }) {
                return thisMonth
            }

            guard let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: start),
                  let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: nextMonthStart)) else {
                return start
            }
            return calendar.date(byAdding: .day, value: max(0, targetDay - 1), to: firstOfMonth)
        case .yearly:
            return start
        }
    }

    private static func nextWeekday(_ weekday: Weekday, from date: Date) -> Date? {
        let cal = Calendar.current
        let current = cal.component(.weekday, from: date)
        let target = weekday.calendarValue
        var daysAhead = target - current
        if daysAhead <= 0 { daysAhead += 7 }
        return cal.date(byAdding: .day, value: daysAhead, to: date)
    }

    private enum Weekday {
        case sunday, monday, tuesday, wednesday, thursday, friday, saturday

        var calendarValue: Int {
            switch self {
            case .sunday: return 1
            case .monday: return 2
            case .tuesday: return 3
            case .wednesday: return 4
            case .thursday: return 5
            case .friday: return 6
            case .saturday: return 7
            }
        }
    }

    private static func monthFromAbbreviation(_ str: String) -> Int? {
        let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
                      "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]
        let prefix = String(str.prefix(3))
        return months[prefix]
    }
}
