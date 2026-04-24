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

@MainActor
enum TaskInputParser {

    /// Parse a natural language task input string into structured metadata
    static func parse(_ input: String) -> ParsedTaskInput {
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

        // Extract time (2pm, 14:00, at 3:30pm)
        result.scheduledTime = extractTime(&remaining)

        // Extract date (today, tomorrow, monday, next week, mar 15)
        result.dueDate = extractDate(&remaining)

        // If we got a time but no date, assume today
        if result.scheduledTime != nil && result.dueDate == nil {
            result.dueDate = Date()
        }

        // If recurrence is present but no explicit date was provided, seed from the next occurrence.
        if result.recurrenceRule != nil && result.dueDate == nil {
            result.dueDate = nextOccurrenceDate(for: result.recurrenceRule!, from: Date())
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

    // MARK: - Things 3 Scheduling Extractions

    /// Extract /someday or /anytime from input
    private static func extractSchedulingState(_ input: inout String) -> String? {
        let patterns: [(String, String)] = [
            ("\\/someday\\b", "someday"),
            ("\\/anytime\\b", "anytime"),
        ]

        for (pattern, state) in patterns {
            if let range = input.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                input.removeSubrange(range)
                return state
            }
        }
        return nil
    }

    /// Extract /morning, /am, /evening, /eve from input
    private static func extractTimeOfDay(_ input: inout String) -> String? {
        let patterns: [(String, String)] = [
            ("\\/morning\\b", "morning"),
            ("\\/am\\b", "morning"),
            ("\\/evening\\b", "evening"),
            ("\\/eve\\b", "evening"),
        ]

        for (pattern, timeOfDay) in patterns {
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
            pattern: "\\bdeadline:\\s*(\\S+(?:\\s+\\d{1,2})?)",
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
        let patterns: [(String, TaskPriority)] = [
            ("\\bp1\\b", .critical),
            ("\\bp2\\b", .high),
            ("\\bp3\\b", .medium),
            ("\\bp4\\b", .low),
            ("\\b!1\\b", .critical),
            ("\\b!!\\b", .high),
            ("\\b!\\b", .medium),
        ]

        for (pattern, priority) in patterns {
            if let range = input.range(of: pattern, options: .regularExpression, range: input.startIndex..<input.endIndex) {
                input.removeSubrange(range)
                return priority
            }
        }
        return nil
    }

    // MARK: - Intent

    private static func extractIntent(_ input: inout String) -> TaskIntent? {
        let keywords: [(String, TaskIntent)] = [
            ("\\bwrite\\b", .writeContent),
            ("\\bwriting\\b", .writeContent),
            ("\\bdraft\\b", .writeContent),
            ("\\bresearch\\b", .research),
            ("\\bstudy\\b", .studySwipes),
            ("\\bswipe\\b", .studySwipes),
            ("\\bthink\\b", .deepThink),
            ("\\breview\\b", .review),
        ]

        for (pattern, intent) in keywords {
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
        let patterns: [(String, RecurrenceRule)] = [
            ("\\bevery\\s+day\\b", .daily()),
            ("\\bdaily\\b", .daily()),
            ("\\bevery\\s+weekday(?:s)?\\b", .weekdays()),
            ("\\bweekday(?:s)?\\b", .weekdays()),
            ("\\bevery\\s+month\\b", .monthly(onDay: Calendar.current.component(.day, from: Date()))),
        ]

        for (pattern, rule) in patterns {
            if let range = input.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                input.removeSubrange(range)
                return rule
            }
        }

        guard let regex = try? NSRegularExpression(
            pattern: "\\bevery\\s+((?:(?:mon(?:day)?|tue(?:s|sday)?|wed(?:nesday)?|thu(?:r|rs|rsday)?|thur(?:s|sday)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)(?:\\s*(?:,|and)\\s*|\\s+)?)+)",
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

    private static func extractTime(_ input: inout String) -> Date? {
        // Match "at 2pm", "at 14:00", "2pm", "2:30pm", "14:00"
        let patterns = [
            "\\bat\\s+(\\d{1,2}:\\d{2}\\s*(?:am|pm))\\b",
            "\\bat\\s+(\\d{1,2}\\s*(?:am|pm))\\b",
            "\\bat\\s+(\\d{1,2}:\\d{2})\\b",
            "\\b(\\d{1,2}:\\d{2}\\s*(?:am|pm))\\b",
            "\\b(\\d{1,2}(?:am|pm))\\b",
        ]

        for pattern in patterns {
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
        let namedDates: [(String, Date?)] = [
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

        for (pattern, date) in namedDates {
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
            ("\\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\\w*\\s+(\\d{1,2})\\b", true),
            ("\\b(\\d{1,2})/(\\d{1,2})\\b", false),
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
