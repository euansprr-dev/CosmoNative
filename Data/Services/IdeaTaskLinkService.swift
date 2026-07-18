// Data/Services/IdeaTaskLinkService.swift
// July 2026 — Schedule an idea into a task.
// One action in Idea Focus Mode creates a one-off task pinned to a chosen day
// that carries a live link back to the idea: a mention pill in the title
// (titleMentions) plus a primary TaskLinkedAtom, so clicking the pill or
// pressing play on the task opens the idea for development. The idea atom is
// never written — the link lives entirely on the task, so removing the task
// leaves no residue and a deleted idea degrades to a fail-soft dangling link.

import Foundation

@MainActor
enum IdeaTaskLinkService {

    // MARK: - Create

    /// Create a development task for `idea` planned on `day`. Day pins follow
    /// the three-pin contract (dueDate/focusDate/whenDate move together) via
    /// `CommandCenterTaskScheduling.reschedule`.
    @discardableResult
    static func createScheduledTask(for idea: Atom, on day: Date) async throws -> Atom {
        let ideaTitle = (idea.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = ideaTitle.isEmpty ? "Untitled idea" : ideaTitle

        var metadata = TaskMetadata()
        metadata.status = "todo"
        metadata.priority = "medium"
        metadata.intent = TaskIntent.deepThink.rawValue
        metadata.intentUUID = CommandCenterIntentEngine.shared.seedID(for: .deepThink)
        CommandCenterTaskScheduling.reschedule(&metadata, toDate: day)

        let linked = [TaskLinkedAtom(
            atomUUID: idea.uuid,
            atomType: AtomType.idea.rawValue,
            titleSnapshot: snapshot,
            isPrimary: true
        )]
        if let data = try? JSONEncoder().encode(linked) {
            metadata.linkedAtoms = String(data: data, encoding: .utf8)
        }

        let mention = RichMention(
            entityUUID: idea.uuid,
            entityID: idea.id,
            entityType: .idea,
            titleSnapshot: snapshot
        )
        if let data = try? JSONEncoder().encode([mention]) {
            metadata.titleMentions = String(data: data, encoding: .utf8)
        }

        let metadataJSON = (try? JSONEncoder().encode(metadata))
            .flatMap { String(data: $0, encoding: .utf8) }

        let task = try await AtomRepository.shared.create(Atom.new(
            type: .task,
            title: "Develop @\(snapshot)",
            metadata: metadataJSON
        ))
        NotificationCenter.default.post(name: .atomsDidChange, object: nil)
        return task
    }

    // MARK: - Reverse lookup

    /// Tasks whose linkedAtoms point at `ideaUUID` (the idea's scheduled
    /// development sessions). LIKE narrows candidates; the decode filter is
    /// the truth — a bare substring hit can false-positive.
    static func scheduledTasks(for ideaUUID: String) async throws -> [Atom] {
        let candidates = try await AtomRepository.shared.fetchByMetadataSubstring(ideaUUID, type: .task)
        return candidates
            .filter { linkedAtoms(of: $0).contains { $0.atomUUID == ideaUUID } }
            .sorted { (plannedDay($0) ?? .distantFuture) < (plannedDay($1) ?? .distantFuture) }
    }

    /// Decoded `TaskMetadata.linkedAtoms` for a task atom; empty on any decode miss.
    static func linkedAtoms(of task: Atom) -> [TaskLinkedAtom] {
        guard let json = task.metadataValue(as: TaskMetadata.self)?.linkedAtoms,
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([TaskLinkedAtom].self, from: data) else {
            return []
        }
        return decoded
    }

    /// The task's planned day (whenDate ?? focusDate ?? dueDate), for sorting
    /// and the "Scheduled · Tue 21" chip.
    static func plannedDay(_ task: Atom) -> Date? {
        guard let meta = task.metadataValue(as: TaskMetadata.self) else { return nil }
        let pin = meta.whenDate ?? meta.focusDate ?? meta.dueDate
        return pin.flatMap { PlannerumFormatters.iso8601.date(from: $0) }
    }

    // MARK: - Reschedule / remove

    /// Move a scheduled development task to a new day — same three-pin
    /// contract as creation, written back through the clear-honoring merge.
    static func reschedule(taskUUID: String, to day: Date) async throws {
        guard let task = try await AtomRepository.shared.fetch(uuid: taskUUID),
              var metadata = task.metadataValue(as: TaskMetadata.self) else { return }
        // Recurring templates never come from this feature; refuse rather
        // than corrupt a series.
        guard metadata.recurrence == nil else { return }
        CommandCenterTaskScheduling.reschedule(&metadata, toDate: day)
        guard let merged = task.mergingTaskMetadata(metadata, context: "IdeaTaskLink.reschedule(\(taskUUID.prefix(8)))") else { return }
        _ = try await AtomRepository.shared.update(merged)
        NotificationCenter.default.post(name: .atomsDidChange, object: nil)
    }

    /// Remove a scheduled development task (soft delete — the idea is untouched).
    static func removeScheduledTask(taskUUID: String) async throws {
        try await AtomRepository.shared.delete(uuid: taskUUID)
        NotificationCenter.default.post(name: .atomsDidChange, object: nil)
    }
}
