// CosmoOS/Scheduler/CalendarSyncService.swift
// Apple Calendar integration via EventKit — bidirectional sync for time blocks
// Creates a dedicated "CosmoOS" calendar and reads external events for conflict display

import EventKit
import SwiftUI
import Combine

// MARK: - CalendarEvent

/// A unified calendar event model for both Apple Calendar events and CosmoOS time blocks
public struct CalendarEvent: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let calendarName: String
    public let calendarColor: NSColor
    public let isExternal: Bool  // true = from Apple Calendar, false = CosmoOS-created
    public let isAllDay: Bool

    public var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }

    public var durationMinutes: Int {
        Int(duration / 60)
    }

    public init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        calendarName: String,
        calendarColor: NSColor = .systemBlue,
        isExternal: Bool = true,
        isAllDay: Bool = false
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.calendarName = calendarName
        self.calendarColor = calendarColor
        self.isExternal = isExternal
        self.isAllDay = isAllDay
    }

    /// SwiftUI-compatible color from NSColor
    public var color: Color {
        Color(nsColor: calendarColor)
    }
}

// MARK: - CalendarSyncService

/// Service for bidirectional sync between CosmoOS time blocks and Apple Calendar via EventKit.
///
/// Responsibilities:
/// - Request calendar access on first use
/// - Auto-create a "CosmoOS" calendar in the default calendar source
/// - Read external calendar events for conflict display on the timeline
/// - Write CosmoOS time blocks to the CosmoOS calendar
/// - Periodic background refresh (every 15 minutes)
@MainActor
public class CalendarSyncService: ObservableObject {

    // MARK: - Singleton

    public static let shared = CalendarSyncService()

    // MARK: - Published State

    /// External calendar events for the currently visible date range
    @Published public private(set) var externalEvents: [CalendarEvent] = []

    /// Whether the user has granted calendar access
    @Published public private(set) var hasCalendarAccess: Bool = false

    /// Whether a sync is currently in progress
    @Published public private(set) var isSyncing: Bool = false

    /// Last sync timestamp
    @Published public private(set) var lastSyncDate: Date?

    /// Error from last operation
    @Published public private(set) var lastError: String?

    // MARK: - Private

    private let eventStore = EKEventStore()
    private var cosmoCalendar: EKCalendar?
    /// In-flight find-or-create of the CosmoOS calendar, so first event creations can
    /// await resolution instead of racing it (and throwing `.noCalendar`).
    private var calendarResolution: Task<Void, Never>?
    private var refreshTimer: AnyCancellable?
    private var currentDateRange: DateInterval?

    private static let cosmoCalendarTitle = "CosmoOS"
    private static let refreshInterval: TimeInterval = 15 * 60  // 15 minutes

    // MARK: - Initialization

    private init() {
        checkExistingAccess()
    }

    // MARK: - Access

    /// Check if access was already granted in a previous session
    private func checkExistingAccess() {
        let status = EKEventStore.authorizationStatus(for: .event)
        hasCalendarAccess = (status == .fullAccess)

        if hasCalendarAccess {
            Task { _ = await resolveCosmoCalendar() }
        }
    }

    /// Request calendar access from the user
    public func requestAccess() async {
        do {
            let granted: Bool
            if #available(macOS 14.0, *) {
                granted = try await eventStore.requestFullAccessToEvents()
            } else {
                granted = try await eventStore.requestAccess(to: .event)
            }

            hasCalendarAccess = granted

            if granted {
                _ = await resolveCosmoCalendar()
            }
        } catch {
            lastError = "Calendar access request failed: \(error.localizedDescription)"
            hasCalendarAccess = false
        }
    }

    // MARK: - CosmoOS Calendar Management

    /// Find or create the dedicated "CosmoOS" calendar, awaitable so first event creations
    /// don't race the setup. Concurrent callers share one in-flight task; EventKit work runs
    /// off the main thread.
    private func resolveCosmoCalendar() async -> EKCalendar? {
        if let cosmoCalendar { return cosmoCalendar }

        let resolution: Task<Void, Never>
        if let inFlight = calendarResolution {
            resolution = inFlight
        } else {
            let store = self.eventStore
            let calendarTitle = Self.cosmoCalendarTitle
            resolution = Task.detached(priority: .userInitiated) {
                // Look for existing CosmoOS calendar
                let calendars = store.calendars(for: .event)
                if let existing = calendars.first(where: { $0.title == calendarTitle }) {
                    await MainActor.run { self.cosmoCalendar = existing }
                    return
                }

                // Create a new CosmoOS calendar
                let newCalendar = EKCalendar(for: .event, eventStore: store)
                newCalendar.title = calendarTitle
                newCalendar.cgColor = NSColor(red: 139/255, green: 92/255, blue: 246/255, alpha: 1.0).cgColor  // Plannerum violet

                // Use the default calendar source
                if let defaultSource = store.defaultCalendarForNewEvents?.source {
                    newCalendar.source = defaultSource
                } else if let localSource = store.sources.first(where: { $0.sourceType == .local }) {
                    newCalendar.source = localSource
                } else if let firstSource = store.sources.first {
                    newCalendar.source = firstSource
                }

                do {
                    try store.saveCalendar(newCalendar, commit: true)
                    await MainActor.run { self.cosmoCalendar = newCalendar }
                } catch {
                    PersistenceHealth.note(.syncFailure, context: "CalendarSyncService.resolveCosmoCalendar", detail: error.localizedDescription)
                    await MainActor.run {
                        self.lastError = "Failed to create CosmoOS calendar: \(error.localizedDescription)"
                    }
                }
            }
            calendarResolution = resolution
        }

        await resolution.value
        calendarResolution = nil
        return cosmoCalendar
    }

    // MARK: - Read Sync (External Events)

    /// Fetch external calendar events for a date range
    public func fetchExternalEvents(for dateRange: DateInterval) async {
        guard hasCalendarAccess else { return }

        isSyncing = true
        defer { isSyncing = false }

        currentDateRange = dateRange

        let predicate = eventStore.predicateForEvents(
            withStart: dateRange.start,
            end: dateRange.end,
            calendars: nil  // All calendars
        )

        let ekEvents = eventStore.events(matching: predicate)

        externalEvents = ekEvents.compactMap { event -> CalendarEvent? in
            // Skip CosmoOS calendar events (we manage those separately)
            if event.calendar.title == Self.cosmoCalendarTitle {
                return nil
            }

            return CalendarEvent(
                id: event.eventIdentifier,
                title: event.title ?? "Untitled",
                startDate: event.startDate,
                endDate: event.endDate,
                calendarName: event.calendar.title,
                calendarColor: NSColor(cgColor: event.calendar.cgColor) ?? .systemBlue,
                isExternal: true,
                isAllDay: event.isAllDay
            )
        }
        .sorted { $0.startDate < $1.startDate }

        lastSyncDate = Date()
    }

    /// Convenience: fetch events for a single day
    public func fetchExternalEvents(for date: Date) async {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        await fetchExternalEvents(for: DateInterval(start: dayStart, end: dayEnd))
    }

    // MARK: - Write Sync (CosmoOS -> Apple Calendar)

    /// Create an Apple Calendar event for a CosmoOS time block
    /// - Returns: The `eventIdentifier` to store in `TaskMetadata.calendarEventId`
    @discardableResult
    public func createCosmoEvent(title: String, start: Date, end: Date) async throws -> String {
        guard hasCalendarAccess else {
            throw CalendarSyncError.noAccess
        }

        // Await calendar resolution so the first creation after launch/grant doesn't
        // race the find-or-create and throw `.noCalendar`.
        guard let calendar = await resolveCosmoCalendar() else {
            throw CalendarSyncError.noCalendar
        }

        return try await createEventInCalendar(title: title, start: start, end: end, calendar: calendar)
    }

    private func createEventInCalendar(title: String, start: Date, end: Date, calendar: EKCalendar) async throws -> String {
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.calendar = calendar

        try eventStore.save(event, span: .thisEvent, commit: true)

        return event.eventIdentifier
    }

    /// Update an existing CosmoOS calendar event's time range
    public func updateCosmoEvent(eventId: String, start: Date, end: Date) async throws {
        guard hasCalendarAccess else {
            throw CalendarSyncError.noAccess
        }

        guard let event = eventStore.event(withIdentifier: eventId) else {
            throw CalendarSyncError.eventNotFound
        }

        event.startDate = start
        event.endDate = end

        try eventStore.save(event, span: .thisEvent, commit: true)
    }

    /// Update an existing CosmoOS calendar event's title and time range
    public func updateCosmoEvent(eventId: String, title: String, start: Date, end: Date) async throws {
        guard hasCalendarAccess else {
            throw CalendarSyncError.noAccess
        }

        guard let event = eventStore.event(withIdentifier: eventId) else {
            throw CalendarSyncError.eventNotFound
        }

        event.title = title
        event.startDate = start
        event.endDate = end

        try eventStore.save(event, span: .thisEvent, commit: true)
    }

    /// Delete a CosmoOS calendar event
    public func deleteCosmoEvent(eventId: String) async throws {
        guard hasCalendarAccess else {
            throw CalendarSyncError.noAccess
        }

        guard let event = eventStore.event(withIdentifier: eventId) else {
            throw CalendarSyncError.eventNotFound
        }

        try eventStore.remove(event, span: .thisEvent, commit: true)
    }

    // MARK: - Conflict Detection

    /// Check if a proposed time range overlaps with any external calendar event
    public func findConflicts(start: Date, end: Date) -> [CalendarEvent] {
        externalEvents.filter { event in
            // Check for overlap: event.start < proposed.end AND event.end > proposed.start
            event.startDate < end && event.endDate > start
        }
    }

    /// Check if a specific block has conflicts with external events
    public func hasConflict(start: Date, end: Date) -> Bool {
        !findConflicts(start: start, end: end).isEmpty
    }

    // MARK: - Periodic Refresh

    /// Start periodic refresh timer (every 15 minutes)
    public func startPeriodicRefresh() {
        stopPeriodicRefresh()

        refreshTimer = Timer.publish(every: Self.refreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { [weak self] in
                    guard let self = self,
                          let dateRange = self.currentDateRange else { return }
                    await self.fetchExternalEvents(for: dateRange)
                }
            }
    }

    /// Stop periodic refresh
    public func stopPeriodicRefresh() {
        refreshTimer?.cancel()
        refreshTimer = nil
    }
}

// MARK: - CalendarSyncError

public enum CalendarSyncError: LocalizedError {
    case noAccess
    case noCalendar
    case eventNotFound
    case saveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noAccess:
            return "Calendar access not granted. Please enable calendar access in System Settings."
        case .noCalendar:
            return "Could not find or create the CosmoOS calendar."
        case .eventNotFound:
            return "Calendar event not found. It may have been deleted."
        case .saveFailed(let message):
            return "Failed to save calendar event: \(message)"
        }
    }
}
