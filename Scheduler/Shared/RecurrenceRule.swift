// CosmoOS/Calendar/RecurrenceRule.swift
// Recurrence rule model for repeating events and tasks
// Stored as JSON in the recurrence field of calendar_events and tasks tables

import Foundation

// MARK: - Recurrence Frequency
enum RecurrenceFrequency: String, Codable, CaseIterable, Identifiable {
    case daily = "daily"
    case weekly = "weekly"
    case biweekly = "biweekly"
    case monthly = "monthly"
    case yearly = "yearly"
    case weekdays = "weekdays" // Mon-Fri
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .biweekly: return "Every 2 Weeks"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        case .weekdays: return "Weekdays"
        case .custom: return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .daily: return "arrow.clockwise"
        case .weekly: return "calendar.badge.clock"
        case .biweekly: return "calendar"
        case .monthly: return "calendar.circle"
        case .yearly: return "calendar.badge.exclamationmark"
        case .weekdays: return "briefcase"
        case .custom: return "slider.horizontal.3"
        }
    }
}

// MARK: - Day of Week
enum DayOfWeek: Int, Codable, CaseIterable, Identifiable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    var id: Int { rawValue }

    var shortName: String {
        switch self {
        case .sunday: return "Sun"
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        }
    }

    var singleLetter: String {
        switch self {
        case .sunday: return "S"
        case .monday: return "M"
        case .tuesday: return "T"
        case .wednesday: return "W"
        case .thursday: return "T"
        case .friday: return "F"
        case .saturday: return "S"
        }
    }

    static var weekdays: [DayOfWeek] {
        [.monday, .tuesday, .wednesday, .thursday, .friday]
    }
}

// MARK: - End Condition
enum RecurrenceEndCondition: Codable, Equatable {
    case never
    case afterOccurrences(Int)
    case onDate(Date)

    enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "never":
            self = .never
        case "afterOccurrences":
            let count = try container.decode(Int.self, forKey: .value)
            self = .afterOccurrences(count)
        case "onDate":
            let dateString = try container.decode(String.self, forKey: .value)
            if let date = ISO8601DateFormatter().date(from: dateString) {
                self = .onDate(date)
            } else {
                self = .never
            }
        default:
            self = .never
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .never:
            try container.encode("never", forKey: .type)
        case .afterOccurrences(let count):
            try container.encode("afterOccurrences", forKey: .type)
            try container.encode(count, forKey: .value)
        case .onDate(let date):
            try container.encode("onDate", forKey: .type)
            try container.encode(ISO8601DateFormatter().string(from: date), forKey: .value)
        }
    }

    var displayText: String {
        switch self {
        case .never:
            return "Never"
        case .afterOccurrences(let count):
            return "After \(count) times"
        case .onDate(let date):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return "Until \(formatter.string(from: date))"
        }
    }
}

// MARK: - Recurrence Rule
struct RecurrenceRule: Codable, Equatable {
    let frequency: RecurrenceFrequency
    let interval: Int // Every N days/weeks/months/years
    let daysOfWeek: [DayOfWeek]? // For weekly/custom
    let dayOfMonth: Int? // For monthly (1-31)
    let monthOfYear: Int? // For yearly (1-12)
    let endCondition: RecurrenceEndCondition

    // Explicit memberwise initializer (required because we have a custom init)
    init(
        frequency: RecurrenceFrequency,
        interval: Int,
        daysOfWeek: [DayOfWeek]?,
        dayOfMonth: Int?,
        monthOfYear: Int?,
        endCondition: RecurrenceEndCondition
    ) {
        self.frequency = frequency
        self.interval = interval
        self.daysOfWeek = daysOfWeek
        self.dayOfMonth = dayOfMonth
        self.monthOfYear = monthOfYear
        self.endCondition = endCondition
    }

    // MARK: - Convenience Initializers
    static func daily(every interval: Int = 1, endCondition: RecurrenceEndCondition = .never) -> RecurrenceRule {
        RecurrenceRule(
            frequency: .daily,
            interval: interval,
            daysOfWeek: nil,
            dayOfMonth: nil,
            monthOfYear: nil,
            endCondition: endCondition
        )
    }

    static func weekly(
        every interval: Int = 1,
        on days: [DayOfWeek],
        endCondition: RecurrenceEndCondition = .never
    ) -> RecurrenceRule {
        RecurrenceRule(
            frequency: .weekly,
            interval: interval,
            daysOfWeek: days,
            dayOfMonth: nil,
            monthOfYear: nil,
            endCondition: endCondition
        )
    }

    static func weekdays(endCondition: RecurrenceEndCondition = .never) -> RecurrenceRule {
        RecurrenceRule(
            frequency: .weekdays,
            interval: 1,
            daysOfWeek: DayOfWeek.weekdays,
            dayOfMonth: nil,
            monthOfYear: nil,
            endCondition: endCondition
        )
    }

    static func monthly(
        every interval: Int = 1,
        onDay dayOfMonth: Int,
        endCondition: RecurrenceEndCondition = .never
    ) -> RecurrenceRule {
        RecurrenceRule(
            frequency: .monthly,
            interval: interval,
            daysOfWeek: nil,
            dayOfMonth: dayOfMonth,
            monthOfYear: nil,
            endCondition: endCondition
        )
    }

    static func yearly(
        every interval: Int = 1,
        endCondition: RecurrenceEndCondition = .never
    ) -> RecurrenceRule {
        RecurrenceRule(
            frequency: .yearly,
            interval: interval,
            daysOfWeek: nil,
            dayOfMonth: nil,
            monthOfYear: nil,
            endCondition: endCondition
        )
    }

    // MARK: - Voice Command Convenience Initializer
    /// Create a RecurrenceRule from a simple frequency string (for voice commands)
    init(fromVoiceCommand frequencyString: String) {
        switch frequencyString.lowercased() {
        case "daily", "every day", "daily_morning", "daily_afternoon", "daily_evening":
            self = RecurrenceRule.daily()
        case "weekdays", "monday through friday":
            self = RecurrenceRule.weekdays()
        case "weekly", "every week":
            self = RecurrenceRule.weekly(on: [.monday])  // Default to Monday
        case "biweekly", "every two weeks":
            self = RecurrenceRule(
                frequency: .biweekly,
                interval: 2,
                daysOfWeek: nil,
                dayOfMonth: nil,
                monthOfYear: nil,
                endCondition: .never
            )
        case "monthly", "every month":
            self = RecurrenceRule.monthly(onDay: 1)  // Default to 1st
        case "yearly", "every year", "annually":
            self = RecurrenceRule.yearly()
        default:
            // Default to daily
            self = RecurrenceRule.daily()
        }
    }

    // MARK: - Display Text
    var displayText: String {
        var text = ""

        switch frequency {
        case .daily:
            text = interval == 1 ? "Every day" : "Every \(interval) days"
        case .weekly:
            if interval == 1 {
                text = "Every week"
            } else {
                text = "Every \(interval) weeks"
            }
            if let days = daysOfWeek, !days.isEmpty {
                let dayNames = days.map { $0.shortName }.joined(separator: ", ")
                text += " on \(dayNames)"
            }
        case .biweekly:
            text = "Every 2 weeks"
            if let days = daysOfWeek, !days.isEmpty {
                let dayNames = days.map { $0.shortName }.joined(separator: ", ")
                text += " on \(dayNames)"
            }
        case .monthly:
            if interval == 1 {
                text = "Every month"
            } else {
                text = "Every \(interval) months"
            }
            if let day = dayOfMonth {
                text += " on the \(ordinal(day))"
            }
        case .yearly:
            text = interval == 1 ? "Every year" : "Every \(interval) years"
        case .weekdays:
            text = "Every weekday (Mon-Fri)"
        case .custom:
            text = "Custom recurrence"
        }

        if endCondition != .never {
            text += " (\(endCondition.displayText))"
        }

        return text
    }

    private func ordinal(_ n: Int) -> String {
        let suffix: String
        let ones = n % 10
        let tens = (n / 10) % 10

        if tens == 1 {
            suffix = "th"
        } else {
            switch ones {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }

    // MARK: - Generate Occurrences
    func occurrences(from startDate: Date, limit: Int = 100) -> [Date] {
        var dates: [Date] = []
        let calendar = Calendar.current
        var currentDate = startDate
        var occurrenceCount = 0

        while occurrenceCount < limit {
            // Check end condition
            switch endCondition {
            case .never:
                break
            case .afterOccurrences(let max):
                if occurrenceCount >= max {
                    return dates
                }
            case .onDate(let endDate):
                if currentDate > endDate {
                    return dates
                }
            }

            // Add current date if it matches criteria
            if shouldInclude(date: currentDate) {
                dates.append(currentDate)
                occurrenceCount += 1
            }

            // Calculate next date
            switch frequency {
            case .daily:
                currentDate = calendar.date(byAdding: .day, value: interval, to: currentDate)!
            case .weekly, .biweekly:
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
                // Skip to next week if needed
                let weekday = calendar.component(.weekday, from: currentDate)
                if weekday == 1 && frequency == .weekly { // Sunday
                    currentDate = calendar.date(byAdding: .day, value: (interval - 1) * 7, to: currentDate)!
                } else if weekday == 1 && frequency == .biweekly {
                    currentDate = calendar.date(byAdding: .day, value: 7, to: currentDate)!
                }
            case .weekdays:
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
            case .monthly:
                currentDate = calendar.date(byAdding: .month, value: interval, to: startDate)!
                currentDate = calendar.date(byAdding: .month, value: occurrenceCount, to: currentDate)!
            case .yearly:
                currentDate = calendar.date(byAdding: .year, value: interval, to: startDate)!
                currentDate = calendar.date(byAdding: .year, value: occurrenceCount, to: currentDate)!
            case .custom:
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
            }
        }

        return dates
    }

    private func shouldInclude(date: Date) -> Bool {
        let calendar = Calendar.current

        switch frequency {
        case .daily:
            return true
        case .weekly, .biweekly, .custom:
            if let days = daysOfWeek {
                let weekday = calendar.component(.weekday, from: date)
                return days.contains { $0.rawValue == weekday }
            }
            return true
        case .weekdays:
            let weekday = calendar.component(.weekday, from: date)
            return weekday >= 2 && weekday <= 6 // Mon-Fri
        case .monthly:
            if let day = dayOfMonth {
                let currentDay = calendar.component(.day, from: date)
                return currentDay == day
            }
            return true
        case .yearly:
            return true
        }
    }

    // MARK: - JSON Encoding/Decoding
    func toJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func fromJSON(_ json: String) -> RecurrenceRule? {
        guard let data = json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(RecurrenceRule.self, from: data)
    }
}

// MARK: - Extensions for UI
extension RecurrenceRule {
    var icon: String {
        frequency.icon
    }

    var shortDisplayText: String {
        switch frequency {
        case .daily: return interval == 1 ? "Daily" : "Every \(interval)d"
        case .weekly: return "Weekly"
        case .biweekly: return "Biweekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        case .weekdays: return "Weekdays"
        case .custom: return "Custom"
        }
    }
}
