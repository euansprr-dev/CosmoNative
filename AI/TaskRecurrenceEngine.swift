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
        let templates = try await getTemplates()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

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

            // Check if instance already exists for today
            let exists = try await instanceExists(templateUUID: template.uuid, date: today)
            if exists { continue }

            // Create today's instance
            try await createInstance(from: template, metadata: metadata, for: today)
        }
    }

    /// Check if an instance already exists for a template on a given date
    func instanceExists(templateUUID: String, date: Date) async throws -> Bool {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        let allTasks = try await atomRepository.fetchAll(type: .task)

        return allTasks.contains { atom in
            guard let meta = atom.metadataValue(as: TaskMetadata.self),
                  meta.recurrenceParentUUID == templateUUID,
                  let focusDateStr = meta.focusDate,
                  let focusDate = ISO8601DateFormatter().date(from: focusDateStr) else {
                return false
            }
            return focusDate >= dayStart && focusDate < dayEnd
        }
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

    /// Create a task instance from a template for a specific date
    private func createInstance(from template: Atom, metadata: TaskMetadata, for date: Date) async throws {
        var instanceMetadata = TaskMetadata()
        instanceMetadata.status = metadata.status ?? "todo"
        instanceMetadata.priority = metadata.priority
        instanceMetadata.color = metadata.color
        instanceMetadata.durationMinutes = metadata.durationMinutes
        instanceMetadata.focusDate = ISO8601DateFormatter().string(from: date)
        instanceMetadata.isCompleted = false
        instanceMetadata.recurrenceParentUUID = template.uuid
        instanceMetadata.description = metadata.description
        instanceMetadata.intent = metadata.intent
        instanceMetadata.linkedAtomUUID = metadata.linkedAtomUUID
        instanceMetadata.startTime = metadata.startTime
        instanceMetadata.energyLevel = metadata.energyLevel
        instanceMetadata.cognitiveLoad = metadata.cognitiveLoad
        instanceMetadata.taskType = metadata.taskType
        instanceMetadata.estimatedFocusMinutes = metadata.estimatedFocusMinutes
        // Do NOT copy linkedIdeaUUID -- each instance starts fresh for .writeContent

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
}
