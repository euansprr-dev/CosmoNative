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
    ///
    /// Tasks retargeted by `retargetToPromotedContent` match on `originIdeaUUID`
    /// instead: their live link now points at the content piece, but the idea
    /// still owns the session and must keep showing it. The uuid stays somewhere
    /// in the metadata blob either way, so the LIKE prefilter still finds them.
    static func scheduledTasks(for ideaUUID: String) async throws -> [Atom] {
        let candidates = try await AtomRepository.shared.fetchByMetadataSubstring(ideaUUID, type: .task)
        return candidates
            .filter { task in
                linkedAtoms(of: task).contains { $0.atomUUID == ideaUUID }
                    || task.metadataValue(as: TaskMetadata.self)?.originIdeaUUID == ideaUUID
            }
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

    // MARK: - Promotion retarget

    /// Begin Writing moved the idea forward into `content` — move the step in the
    /// task with it. Every *unfinished* scheduled session for `ideaUUID` has its
    /// live link (the title mention pill and the primary `TaskLinkedAtom`) aimed
    /// at the content piece instead, so clicking the hyperlink or pressing play
    /// lands in the writing bench rather than back in ideation.
    ///
    /// Deliberate choices, don't regress:
    /// - **Finished tasks are never touched.** A completed session is a record of
    ///   what was worked on, and the Today row doesn't even render the pill once
    ///   a task is checked off.
    /// - **The idea is kept as `originIdeaUUID`, not as a second linked atom.**
    ///   Non-primary linked atoms fan out as side panes on play
    ///   (`CommandCenterDashboardViewModel.startFocusSession`); the promoted task
    ///   must open the content piece alone. The key still lets the idea list its
    ///   session when reopened from the content's sources.
    /// - **`titleSnapshot` is left byte-identical.** Both renderers locate the pill
    ///   by searching the title for the literal `"@<snapshot>"`
    ///   (`TaskViewModel.attributedTitle`, `TaskTitleWithMentions`); rewriting the
    ///   snapshot without rewriting the title degrades the pill to plain text. Only
    ///   the uuid and entity type move, so the pill just re-tints idea → content.
    /// - Only tasks still pointing *at the idea* are retargeted, so promoting the
    ///   same idea twice leaves already-moved sessions on their content piece.
    @discardableResult
    static func retargetToPromotedContent(ideaUUID: String, content: Atom) async throws -> Int {
        let tasks = try await scheduledTasks(for: ideaUUID)
        var moved = 0

        for task in tasks {
            guard var metadata = task.metadataValue(as: TaskMetadata.self) else { continue }
            guard metadata.isCompleted != true else { continue }

            var linked = linkedAtoms(of: task)
            guard let index = linked.firstIndex(where: { $0.atomUUID == ideaUUID }) else { continue }
            linked[index].atomUUID = content.uuid
            linked[index].atomType = AtomType.content.rawValue
            guard let linkedData = try? JSONEncoder().encode(linked),
                  let linkedJSON = String(data: linkedData, encoding: .utf8) else { continue }
            metadata.linkedAtoms = linkedJSON

            if let mentionsJSON = metadata.titleMentions,
               let mentionsData = mentionsJSON.data(using: .utf8),
               var mentions = try? JSONDecoder().decode([RichMention].self, from: mentionsData) {
                for i in mentions.indices where mentions[i].entityUUID == ideaUUID {
                    mentions[i].entityUUID = content.uuid
                    mentions[i].entityID = content.id
                    mentions[i].entityType = .content
                }
                if let data = try? JSONEncoder().encode(mentions),
                   let json = String(data: data, encoding: .utf8) {
                    metadata.titleMentions = json
                }
            }

            metadata.originIdeaUUID = ideaUUID

            guard let merged = task.mergingTaskMetadata(
                metadata,
                context: "IdeaTaskLink.retargetToPromotedContent(\(task.uuid.prefix(8)))"
            ) else { continue }
            _ = try await AtomRepository.shared.update(merged)
            moved += 1
        }

        if moved > 0 {
            NotificationCenter.default.post(name: .atomsDidChange, object: nil)
        }
        return moved
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
