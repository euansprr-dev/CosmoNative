// CosmoOS/Core/DateFormatters.swift
// Shared date formatters for consistent, high-performance date handling
// Creating ISO8601DateFormatter() is expensive - these cached instances eliminate that overhead

import Foundation

// MARK: - Cached Date Formatters
/// Thread-safe, cached date formatters for CosmoOS.
/// ISO8601DateFormatter creation is ~5-10ms - using these shared instances
/// eliminates that overhead from hot paths like canvas rendering and sync.
enum CosmoDateFormatters {

    // MARK: - ISO 8601 Formatters

    /// Standard ISO 8601 formatter for database timestamps
    /// Format: "2024-01-15T14:30:00Z"
    nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// ISO 8601 with fractional seconds for high-precision timestamps
    /// Format: "2024-01-15T14:30:00.123Z"
    nonisolated(unsafe) static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// ISO 8601 with full date only (no time)
    /// Format: "2024-01-15"
    nonisolated(unsafe) static let iso8601DateOnly: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return formatter
    }()

    // MARK: - Display Formatters

    /// Relative date formatter for "Today", "Yesterday", "2 days ago"
    nonisolated(unsafe) static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    /// Short date + time for UI display
    /// Format: "Jan 15, 2:30 PM"
    static let shortDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// Short date only for UI display
    /// Format: "Jan 15, 2024"
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// Time only for calendar views
    /// Format: "2:30 PM"
    static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    /// Compact time for tight UI spaces
    /// Format: "2:30p"
    static let compactTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        formatter.amSymbol = "a"
        formatter.pmSymbol = "p"
        return formatter
    }()

    /// Day of week + date for calendar headers
    /// Format: "Monday, January 15"
    static let fullDayDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter
    }()

    /// Abbreviated day of week
    /// Format: "Mon"
    static let shortDayOfWeek: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    /// Month + Year for calendar navigation
    /// Format: "January 2024"
    static let monthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
}

// MARK: - Convenience Extensions

extension Date {
    /// Convert to ISO 8601 string for database storage
    var iso8601String: String {
        CosmoDateFormatters.iso8601.string(from: self)
    }

    /// Convert to ISO 8601 string with fractional seconds
    var iso8601StringWithFractionalSeconds: String {
        CosmoDateFormatters.iso8601WithFractionalSeconds.string(from: self)
    }

    /// Relative description ("Today", "2 days ago")
    var relativeDescription: String {
        CosmoDateFormatters.relative.localizedString(for: self, relativeTo: Date())
    }

    /// Short display format ("Jan 15, 2:30 PM")
    var shortDisplay: String {
        CosmoDateFormatters.shortDateTime.string(from: self)
    }

    /// Time only ("2:30 PM")
    var timeDisplay: String {
        CosmoDateFormatters.timeOnly.string(from: self)
    }

    /// Compact time ("2:30p")
    var compactTimeDisplay: String {
        CosmoDateFormatters.compactTime.string(from: self)
    }
}

extension String {
    /// Parse ISO 8601 string to Date
    var iso8601Date: Date? {
        CosmoDateFormatters.iso8601.date(from: self)
    }

    /// Parse ISO 8601 string with fractional seconds to Date
    var iso8601DateWithFractionalSeconds: Date? {
        CosmoDateFormatters.iso8601WithFractionalSeconds.date(from: self)
    }
}

// MARK: - Static Convenience (Drop-in replacement for ISO8601DateFormatter())

/// Drop-in replacement for `ISO8601DateFormatter().string(from: date)`
/// Use: `ISO8601.string(from: Date())` instead of `ISO8601DateFormatter().string(from: Date())`
enum ISO8601 {
    /// Convert Date to ISO 8601 string
    static func string(from date: Date) -> String {
        CosmoDateFormatters.iso8601.string(from: date)
    }

    /// Parse ISO 8601 string to Date
    static func date(from string: String) -> Date? {
        CosmoDateFormatters.iso8601.date(from: string)
    }
}
