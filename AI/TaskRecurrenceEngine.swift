//
//  TaskRecurrenceEngine.swift
//  CosmoOS
//
//  Recurring task generation engine.
//  Runs on app launch and at midnight to create today's task instances
//  from recurring templates.
//

import Foundation

@MainActor
class TaskRecurrenceEngine {
    struct GeneratedInstanceSnapshot: Equatable {
        let uuid: String
        let parentUUID: String
        let occurrenceDate: Date
        let isCompleted: Bool
        let createdAt: Date
    }

    // MARK: - Singleton

    static let shared = TaskRecurrenceEngine()

    // MARK: - Dependencies

    private let atomRepository: AtomRepository

    // MARK: - Midnight Timer

    private var midnightTimer: Timer?

    // MARK: - Init

    init(atomRepository: AtomRepository? = nil) {
        self.atomRepository = atomRepository ?? AtomRepository.shared
    }

    // MARK: - Public API

    /// Run on app launch and at midnight -- generates today's task instances
    func generateTodayInstances() async throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        try await deduplicateGeneratedInstances(referenceDate: today)

        let templates = try await getTemplates()

        for template in templates {
            guard let metadata = template.metadataValue(as: TaskMetadata.self),
                  let recurrenceJSON = metadata.recurrence,
                  let rule = RecurrenceRule.fromJSON(recurrenceJSON) else {
                continue
            }

            // Check end conditions
            if shouldStopRecurrence(rule: rule, template: template, today: today) {
                continue
            }

            // Check if today is a valid occurrence day
            guard isTodayValidOccurrence(rule: rule, today: today) else {
                continue
            }

            // Skip only if today's occurrence already exists. Older incomplete
            // occurrences must not block today's repeat from being generated.
            if try await instanceExists(templateUUID: template.uuid, date: today) { continue }

            // Create today's instance
            try await createInstance(from: template, metadata: metadata, for: today)
        }

        try await deduplicateGeneratedInstances(referenceDate: today)
    }

    /// Generate missing instances for every occurrence in a visible calendar interval.
    func generateInstances(in interval: DateInterval) async throws {
        try await deduplicateGeneratedInstances()

        let templates = try await getTemplates()

        for template in templates {
            guard let metadata = template.metadataValue(as: TaskMetadata.self),
                  let recurrenceJSON = metadata.recurrence,
                  let rule = RecurrenceRule.fromJSON(recurrenceJSON),
                  let startDate = recurrenceStartDate(from: metadata) else {
                continue
            }

            for occurrence in rule.occurrenceDates(in: interval, startingFrom: startDate) {
                if try await instanceExists(templateUUID: template.uuid, date: occurrence) { continue }
                try await createInstance(from: template, metadata: metadata, for: occurrence)
            }
        }

        try await deduplicateGeneratedInstances()
    }

    /// Returns template UUIDs that already have at least one incomplete
    /// instance. Completed past instances do not block generation.
    func batchTemplatesWithActiveInstance() async throws -> Set<String> {
        let allTasks = try await atomRepository.fetchAll(type: .task)

        var result = Set<String>()
        for atom in allTasks {
            guard let meta = atom.metadataValue(as: TaskMetadata.self),
                  let parentUUID = meta.recurrenceParentUUID,
                  meta.isCompleted != true else {
                continue
            }
            result.insert(parentUUID)
        }
        return result
    }

    /// Check if an instance already exists for a template on a given date
    func instanceExists(templateUUID: String, date: Date) async throws -> Bool {
        let allTasks = try await atomRepository.fetchAll(type: .task)

        return allTasks.contains { atom in
            guard let meta = atom.metadataValue(as: TaskMetadata.self) else { return false }
            return Self.recurrenceInstanceMatches(templateUUID: templateUUID, date: date, metadata: meta)
        }
    }

    static func recurrenceInstanceMatches(
        templateUUID: String,
        date: Date,
        metadata: TaskMetadata,
        calendar: Calendar = .current
    ) -> Bool {
        guard metadata.recurrenceParentUUID == templateUUID,
              let occurrenceDate = occurrenceDate(from: metadata) else {
            return false
        }

        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return occurrenceDate >= dayStart && occurrenceDate < dayEnd
    }

    /// Get all recurring templates (tasks with recurrence set but no parent)
    func getTemplates() async throws -> [Atom] {
        let allTasks = try await atomRepository.fetchAll(type: .task)

        return allTasks.filter { atom in
            guard let meta = atom.metadataValue(as: TaskMetadata.self) else { return false }
            // Template = has recurrence rule AND is NOT an instance (no parent)
            return meta.recurrence != nil && meta.recurrenceParentUUID == nil
        }
    }

    /// Get completion count for a template (how many instances have been completed)
    func getCompletionCount(templateUUID: String) async throws -> Int {
        let allTasks = try await atomRepository.fetchAll(type: .task)

        return allTasks.filter { atom in
            guard let meta = atom.metadataValue(as: TaskMetadata.self) else { return false }
            return meta.recurrenceParentUUID == templateUUID && meta.isCompleted == true
        }.count
    }

    /// Get total instance count for a template
    func getInstanceCount(templateUUID: String) async throws -> Int {
        let allTasks = try await atomRepository.fetchAll(type: .task)

        return allTasks.filter { atom in
            guard let meta = atom.metadataValue(as: TaskMetadata.self) else { return false }
            return meta.recurrenceParentUUID == templateUUID
        }.count
    }

    // MARK: - Midnight Scheduling

    /// Schedule a timer to fire at the next midnight for regeneration
    func scheduleMidnightRefresh() {
        midnightTimer?.invalidate()

        let calendar = Calendar.current
        guard let nextMidnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) else {
            return
        }

        let interval = nextMidnight.timeIntervalSinceNow
        midnightTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await self?.generateTodayInstances()
                self?.scheduleMidnightRefresh()
            }
        }
    }

    /// Stop the midnight timer
    func stopMidnightRefresh() {
        midnightTimer?.invalidate()
        midnightTimer = nil
    }

    // MARK: - Private Helpers

    /// Check if today is a valid occurrence day for the given rule
    private func isTodayValidOccurrence(rule: RecurrenceRule, today: Date) -> Bool {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: today)

        switch rule.frequency {
        case .daily:
            return true

        case .weekdays:
            return weekday >= 2 && weekday <= 6

        case .weekly:
            if let days = rule.daysOfWeek, !days.isEmpty {
                return days.contains { $0.rawValue == weekday }
            }
            // If no specific days, default to any day in the week cycle
            return true

        case .biweekly:
            if let days = rule.daysOfWeek, !days.isEmpty {
                return days.contains { $0.rawValue == weekday }
            }
            return true

        case .monthly:
            if let day = rule.dayOfMonth {
                return calendar.component(.day, from: today) == day
            }
            return true

        case .yearly:
            // For yearly, check month and optionally day
            return true

        case .custom:
            if let days = rule.daysOfWeek, !days.isEmpty {
                return days.contains { $0.rawValue == weekday }
            }
            return true
        }
    }

    /// Check if recurrence should stop based on end conditions
    private func shouldStopRecurrence(rule: RecurrenceRule, template: Atom, today: Date) -> Bool {
        switch rule.endCondition {
        case .never:
            return false

        case .onDate(let endDate):
            return today > endDate

        case .afterOccurrences(let maxCount):
            // Count existing instances synchronously from cached atoms
            let allAtoms = atomRepository.atoms
            let instanceCount = allAtoms.filter { atom in
                guard let meta = atom.metadataValue(as: TaskMetadata.self) else { return false }
                return meta.recurrenceParentUUID == template.uuid
            }.count
            return instanceCount >= maxCount
        }
    }

    func deduplicateGeneratedInstances(referenceDate: Date = Date()) async throws {
        let allTasks = try await atomRepository.fetchAll(type: .task)
        let snapshots = allTasks.compactMap { atom -> GeneratedInstanceSnapshot? in
            guard let metadata = atom.metadataValue(as: TaskMetadata.self),
                  let parentUUID = metadata.recurrenceParentUUID,
                  let occurrenceDate = Self.occurrenceDate(from: metadata) else {
                return nil
            }

            return GeneratedInstanceSnapshot(
                uuid: atom.uuid,
                parentUUID: parentUUID,
                occurrenceDate: occurrenceDate,
                isCompleted: metadata.isCompleted == true,
                createdAt: PlannerumFormatters.iso8601.date(from: atom.createdAt) ?? .distantPast
            )
        }

        let deletionUUIDs = Self.generatedInstanceCleanupDeletions(
            from: snapshots,
            referenceDate: referenceDate,
            calendar: Calendar.current
        )

        for uuid in deletionUUIDs {
            try await atomRepository.delete(uuid: uuid)
        }
    }

    static func generatedInstanceCleanupDeletions(
        from snapshots: [GeneratedInstanceSnapshot],
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> Set<String> {
        let activeSnapshots = snapshots.filter { !$0.isCompleted }
        let referenceDay = calendar.startOfDay(for: referenceDate)
        var deletions = Set<String>()
        var groupedByParentAndDay: [String: [GeneratedInstanceSnapshot]] = [:]

        for snapshot in activeSnapshots {
            let occurrenceDay = calendar.startOfDay(for: snapshot.occurrenceDate)
            let dayKey = PlannerumFormatters.iso8601.string(from: occurrenceDay)
            groupedByParentAndDay["\(snapshot.parentUUID)|\(dayKey)", default: []].append(snapshot)
        }

        for duplicates in groupedByParentAndDay.values where duplicates.count > 1 {
            let sorted = duplicates.sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.uuid < rhs.uuid
            }

            for duplicate in sorted.dropFirst() {
                deletions.insert(duplicate.uuid)
            }
        }

        let parentsWithReferenceDayInstance = Set(
            activeSnapshots.compactMap { snapshot -> String? in
                calendar.isDate(snapshot.occurrenceDate, inSameDayAs: referenceDay)
                    ? snapshot.parentUUID
                    : nil
            }
        )

        for snapshot in activeSnapshots {
            let occurrenceDay = calendar.startOfDay(for: snapshot.occurrenceDate)
            if occurrenceDay < referenceDay,
               parentsWithReferenceDayInstance.contains(snapshot.parentUUID) {
                deletions.insert(snapshot.uuid)
            }
        }

        return deletions
    }

    private static func occurrenceDate(from metadata: TaskMetadata) -> Date? {
        let candidates = [
            metadata.focusDate,
            metadata.scheduledStart,
            metadata.startTime,
            metadata.whenDate,
            metadata.dueDate
        ]

        for candidate in candidates {
            if let candidate, let date = PlannerumFormatters.iso8601.date(from: candidate) {
                return date
            }
        }

        return nil
    }

    private func recurrenceStartDate(from metadata: TaskMetadata) -> Date? {
        let candidates = [
            metadata.scheduledStart,
            metadata.startTime,
            metadata.focusDate,
            metadata.whenDate,
            metadata.dueDate
        ]

        for candidate in candidates {
            if let candidate, let date = PlannerumFormatters.iso8601.date(from: candidate) {
                return date
            }
        }

        return nil
    }

    /// Create a task instance from a template for a specific date
    private func createInstance(from template: Atom, metadata: TaskMetadata, for date: Date) async throws {
        var instanceMetadata = TaskMetadata()
        instanceMetadata.status = metadata.status ?? "todo"
        instanceMetadata.priority = metadata.priority
        instanceMetadata.color = metadata.color
        instanceMetadata.durationMinutes = metadata.durationMinutes
        instanceMetadata.focusDate = PlannerumFormatters.iso8601.string(from: date)
        instanceMetadata.dueDate = PlannerumFormatters.iso8601.string(from: date)
        instanceMetadata.isCompleted = false
        instanceMetadata.recurrenceParentUUID = template.uuid
        instanceMetadata.description = metadata.description
        instanceMetadata.intent = metadata.intent
        instanceMetadata.intentUUID = metadata.intentUUID
        instanceMetadata.habitUUID = metadata.habitUUID
        instanceMetadata.habitAssignmentSource = metadata.habitAssignmentSource
        instanceMetadata.linkedAtomUUID = metadata.linkedAtomUUID
        instanceMetadata.energyLevel = metadata.energyLevel
        instanceMetadata.cognitiveLoad = metadata.cognitiveLoad
        instanceMetadata.taskType = metadata.taskType
        instanceMetadata.estimatedFocusMinutes = metadata.estimatedFocusMinutes
        instanceMetadata.headingUUID = metadata.headingUUID
        instanceMetadata.titleMentions = metadata.titleMentions
        copyCalendarTime(from: metadata, to: &instanceMetadata, on: date)
        // Do NOT copy linkedIdeaUUID -- each instance starts fresh for .writeContent

        // Copy checklist from template with all items unchecked
        if let checklistJSON = metadata.checklist,
           let data = checklistJSON.data(using: .utf8),
           var items = try? JSONDecoder().decode([ChecklistItem].self, from: data) {
            items = items.map { item in
                ChecklistItem(id: UUID().uuidString, title: item.title, isCompleted: false, sortOrder: item.sortOrder)
            }
            if let encoded = try? JSONEncoder().encode(items),
               let json = String(data: encoded, encoding: .utf8) {
                instanceMetadata.checklist = json
            }
        }

        guard let metadataData = try? JSONEncoder().encode(instanceMetadata),
              let metadataString = String(data: metadataData, encoding: .utf8) else {
            return
        }

        // Copy project links from template
        let templateLinks = template.linksList.filter { $0.type == "project" }

        let instance = Atom.new(
            type: .task,
            title: template.title,
            body: template.body,
            metadata: metadataString,
            links: templateLinks.isEmpty ? nil : templateLinks
        )

        try await atomRepository.create(instance)
    }

    private func copyCalendarTime(from source: TaskMetadata, to destination: inout TaskMetadata, on date: Date) {
        let startSource = source.scheduledStart ?? source.startTime
        guard let startSource, let sourceStart = PlannerumFormatters.iso8601.date(from: startSource) else { return }

        let endSource = source.scheduledEnd ?? source.endTime
        let sourceEnd = endSource.flatMap { PlannerumFormatters.iso8601.date(from: $0) }
        let duration = sourceEnd.map { max(15, Int($0.timeIntervalSince(sourceStart) / 60)) }
            ?? source.durationMinutes
            ?? source.estimatedFocusMinutes
            ?? 30

        let start = merge(date: date, time: sourceStart)
        let end = Calendar.current.date(byAdding: .minute, value: duration, to: start)
            ?? start.addingTimeInterval(TimeInterval(duration * 60))
        applyCalendarTimeRange(start: start, end: end, to: &destination)
    }

    private func merge(date: Date, time: Date) -> Date {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
        var merged = DateComponents()
        merged.year = dateComponents.year
        merged.month = dateComponents.month
        merged.day = dateComponents.day
        merged.hour = timeComponents.hour
        merged.minute = timeComponents.minute
        merged.second = timeComponents.second ?? 0
        return calendar.date(from: merged) ?? date
    }

    private func applyCalendarTimeRange(start: Date, end: Date, to metadata: inout TaskMetadata) {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: start)
        let dateString = PlannerumFormatters.iso8601.string(from: day)
        metadata.dueDate = dateString
        metadata.focusDate = dateString
        metadata.whenDate = dateString
        metadata.startTime = PlannerumFormatters.iso8601.string(from: start)
        metadata.endTime = PlannerumFormatters.iso8601.string(from: end)
        metadata.scheduledStart = PlannerumFormatters.iso8601.string(from: start)
        metadata.scheduledEnd = PlannerumFormatters.iso8601.string(from: end)
        metadata.durationMinutes = max(15, Int(end.timeIntervalSince(start) / 60))
        metadata.schedulingState = nil
    }
}
