// Canvas/CommandCenter/TaskInputParser.swift
// Natural language task input parser — extracts priority, dates, times, durations, intents
// March 2026

import Foundation

struct ParsedTaskInput {
    var title: String
    var priority: TaskPriority?
    var dueDate: Date?
    var scheduledTime: Date?
    var estimatedMinutes: Int?
    var intent: TaskIntent?
}

enum TaskInputParser {

    /// Parse a natural language task input string into structured metadata
    static func parse(_ input: String) -> ParsedTaskInput {
        var remaining = input
        var result = ParsedTaskInput(title: "")

        // Extract priority (p1/p2/p3/p4)
        result.priority = extractPriority(&remaining)

        // Extract duration (30m, 1h, 90min, 1.5h)
        result.estimatedMinutes = extractDuration(&remaining)

        // Extract intent keywords
        result.intent = extractIntent(&remaining)

        // Extract time (2pm, 14:00, at 3:30pm)
        result.scheduledTime = extractTime(&remaining)

        // Extract date (today, tomorrow, monday, next week, mar 15)
        result.dueDate = extractDate(&remaining)

        // If we got a time but no date, assume today
        if result.scheduledTime != nil && result.dueDate == nil {
            result.dueDate = Date()
        }

        // Clean up title
        result.title = remaining
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "  ", with: " ")

        return result
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

    // MARK: - Duration

    private static func extractDuration(_ input: inout String) -> Int? {
        // Match patterns like "30m", "1h", "90min", "1.5h", "1h30m"
        let patterns: [(String, (String) -> Int?)] = [
            ("\\b(\\d+)h(\\d+)m\\b", { str in
                let parts = str.components(separatedBy: CharacterSet(charactersIn: "hm")).filter { !$0.isEmpty }
                guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
                return h * 60 + m
            }),
            ("\\b(\\d+\\.\\d+)h\\b", { str in
                let num = str.replacingOccurrences(of: "h", with: "")
                guard let hours = Double(num) else { return nil }
                return Int(hours * 60)
            }),
            ("\\b(\\d+)h\\b", { str in
                let num = str.replacingOccurrences(of: "h", with: "")
                guard let hours = Int(num) else { return nil }
                return hours * 60
            }),
            ("\\b(\\d+)min\\b", { str in
                let num = str.replacingOccurrences(of: "min", with: "")
                return Int(num)
            }),
            ("\\b(\\d+)m\\b", { str in
                let num = str.replacingOccurrences(of: "m", with: "")
                return Int(num)
            }),
        ]

        for (pattern, converter) in patterns {
            if let match = input.range(of: pattern, options: .regularExpression) {
                let matchStr = String(input[match])
                if let minutes = converter(matchStr) {
                    input.removeSubrange(match)
                    return minutes
                }
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
