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

    /// The default length of a dropped writing session, in minutes.
    /// `nonisolated` because it is used as a default argument, and those are
    /// evaluated in the caller's (nonisolated) context.
    nonisolated static let defaultSessionMinutes = 90

    /// Create a development task for `idea` planned on `day`. Day pins follow
    /// the three-pin contract (dueDate/focusDate/whenDate move together) via
    /// `CommandCenterTaskScheduling.reschedule`.
    ///
    /// Pass `at:` to book a real time block instead of an all-day session — the
    /// week board's hour grid does. `start` must be an ABSOLUTE date; it is
    /// never re-derived from components (see `CommandCenterTaskScheduling.schedule`).
    @discardableResult
    static func createScheduledTask(
        for idea: Atom,
        on day: Date,
        at start: Date? = nil,
        durationMinutes: Int = defaultSessionMinutes
    ) async throws -> Atom {
        let ideaTitle = (idea.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = ideaTitle.isEmpty ? "Untitled idea" : ideaTitle

        var metadata = TaskMetadata()
        metadata.status = "todo"
        metadata.priority = "medium"
        metadata.intent = TaskIntent.deepThink.rawValue
        metadata.intentUUID = CommandCenterIntentEngine.shared.seedID(for: .deepThink)
        if let start {
            let end = start.addingTimeInterval(TimeInterval(max(15, durationMinutes) * 60))
            CommandCenterTaskScheduling.schedule(&metadata, from: start, to: end)
        } else {
            CommandCenterTaskScheduling.reschedule(&metadata, toDate: day)
        }

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
            .filter { ideaUUIDs(of: $0).contains(ideaUUID) }
            .sorted { (plannedDay($0) ?? .distantFuture) < (plannedDay($1) ?? .distantFuture) }
    }

    /// Every idea this task counts as a session for: the decoded idea links,
    /// PLUS the promotion trace left by `retargetToPromotedContent`.
    ///
    /// THE ONE ANSWER to "is this task a session for that idea". Every reverse
    /// lookup routes through here — `scheduledTasks(for:)` for a single idea,
    /// `openSessionDaysByIdea(in:)` for a whole page. They used to be separate
    /// implementations and they drifted: the batched one never consulted
    /// `originIdeaUUID`, so after Begin Writing the Ideas Desk's "Scheduled"
    /// chip went blank on a session that was still real and still on the
    /// calendar. Two answers to one question is the bug; keep it at one.
    nonisolated static func ideaUUIDs(of task: Atom) -> [String] {
        var uuids = linkedAtoms(of: task)
            .filter { $0.atomType == AtomType.idea.rawValue }
            .map(\.atomUUID)
        if let origin = task.metadataValue(as: TaskMetadata.self)?.originIdeaUUID,
           !uuids.contains(origin) {
            uuids.append(origin)
        }
        return uuids
    }

    /// Batched reverse lookup for pages that need the answer for many ideas at
    /// once: idea uuid → the EARLIEST open session day. Pure, so callers own
    /// the fetch and it can run off the main actor.
    nonisolated static func openSessionDaysByIdea(in tasks: [Atom]) -> [String: Date] {
        var days: [String: Date] = [:]
        for task in tasks {
            guard isOpenSession(task), let day = plannedDay(task) else { continue }
            for ideaUUID in ideaUUIDs(of: task) {
                // Earliest wins — that's the session a drop would move.
                if let existing = days[ideaUUID], existing <= day { continue }
                days[ideaUUID] = day
            }
        }
        return days
    }

    /// The content twin of `openSessionDaysByIdea`: after Begin Writing,
    /// `retargetToPromotedContent` repoints a session's live link at the
    /// content atom, so the Pipeline's cards need the answer by CONTENT uuid.
    /// content uuid → earliest open session day.
    nonisolated static func openSessionDaysByContent(in tasks: [Atom]) -> [String: Date] {
        var days: [String: Date] = [:]
        for task in tasks {
            guard isOpenSession(task), let day = plannedDay(task) else { continue }
            for link in linkedAtoms(of: task) where link.atomType == AtomType.content.rawValue {
                if let existing = days[link.atomUUID], existing <= day { continue }
                days[link.atomUUID] = day
            }
        }
        return days
    }

    /// Decoded `TaskMetadata.linkedAtoms` for a task atom; empty on any decode miss.
    /// `nonisolated` — a pure read of a Sendable value, callable from loaders
    /// that build their rows off the main actor.
    nonisolated static func linkedAtoms(of task: Atom) -> [TaskLinkedAtom] {
        guard let json = task.metadataValue(as: TaskMetadata.self)?.linkedAtoms,
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([TaskLinkedAtom].self, from: data) else {
            return []
        }
        return decoded
    }

    /// The task's planned day (whenDate ?? focusDate ?? dueDate), for sorting
    /// and the "Scheduled · Tue 21" chip.
    nonisolated static func plannedDay(_ task: Atom) -> Date? {
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

    // MARK: - Drop resolution (move, never duplicate)

    /// What a drop onto a day should do for this idea.
    enum DropResolution: Equatable {
        case create
        /// Move this existing open session. `siblingCount` > 0 means other open
        /// sessions were left alone and the toast must say so — an invisible
        /// second session is the failure mode this whole rule exists to prevent.
        case move(taskUUID: String, siblingCount: Int)
    }

    /// A session is a *slot* only while it is open. Completed sessions are
    /// records of work done, and recurring rows belong to a series — moving
    /// either would be wrong, so both fall through to a fresh one-off.
    ///
    /// Note `reschedule(taskUUID:to:)` refuses recurrence by returning Void, so
    /// routing a recurring session there would produce a dead drop with no
    /// feedback. Excluding it here turns that silence into a correct create.
    nonisolated static func isOpenSession(_ task: Atom) -> Bool {
        guard let meta = task.metadataValue(as: TaskMetadata.self) else { return false }
        return meta.isCompleted != true
            && meta.status != "done"
            && meta.recurrence == nil
            && meta.recurrenceParentUUID == nil
    }

    /// Resolve a drop for `ideaUUID`. Matches both link shapes (`linkedAtoms`
    /// and `originIdeaUUID`), so a session retargeted by Begin Writing still
    /// MOVES rather than spawning a duplicate beside the content piece.
    static func resolveDrop(for ideaUUID: String) async throws -> DropResolution {
        // Already sorted by plannedDay ascending, so `first` is the soonest.
        let open = try await scheduledTasks(for: ideaUUID).filter(isOpenSession)
        guard let target = open.first else { return .create }
        return .move(taskUUID: target.uuid, siblingCount: open.count - 1)
    }

    // MARK: - Undo snapshot

    /// Exactly the keys `CommandCenterTaskScheduling.schedule` / `.reschedule`
    /// write. Restored as a set — including the nils, through the clear-honoring
    /// merge, because a plain key merge resurrects cleared dates.
    struct PinSnapshot: Sendable, Equatable {
        var dueDate: String?
        var focusDate: String?
        var whenDate: String?
        var startTime: String?
        var endTime: String?
        var scheduledStart: String?
        var scheduledEnd: String?
        var durationMinutes: Int?
        var schedulingState: String?

        init(_ meta: TaskMetadata) {
            dueDate = meta.dueDate
            focusDate = meta.focusDate
            whenDate = meta.whenDate
            startTime = meta.startTime
            endTime = meta.endTime
            scheduledStart = meta.scheduledStart
            scheduledEnd = meta.scheduledEnd
            durationMinutes = meta.durationMinutes
            schedulingState = meta.schedulingState
        }

        func apply(to meta: inout TaskMetadata) {
            meta.dueDate = dueDate
            meta.focusDate = focusDate
            meta.whenDate = whenDate
            meta.startTime = startTime
            meta.endTime = endTime
            meta.scheduledStart = scheduledStart
            meta.scheduledEnd = scheduledEnd
            meta.durationMinutes = durationMinutes
            meta.schedulingState = schedulingState
        }
    }

    // MARK: - Move (the drop's write for an existing session)

    /// Move an open session onto `day`, optionally at an absolute `start`.
    /// Returns the pre-write pins so the drop can register an exact undo.
    ///
    /// Deliberately NOT routed through `Dashboard.updateCalendarTimeBlock`: that
    /// back-fills an EKEvent for any task lacking one, and neither delete nor
    /// restore knows about EventKit — an undone session would orphan a real
    /// calendar event and redo would mint a second.
    @discardableResult
    static func move(
        taskUUID: String,
        to day: Date,
        at start: Date?,
        durationMinutes: Int = defaultSessionMinutes
    ) async throws -> PinSnapshot? {
        guard let task = try await AtomRepository.shared.fetch(uuid: taskUUID),
              var metadata = task.metadataValue(as: TaskMetadata.self) else { return nil }
        // A series template or instance must never be moved by this path — it
        // would shift the whole series onto one day.
        guard metadata.recurrence == nil, metadata.recurrenceParentUUID == nil else { return nil }

        let before = PinSnapshot(metadata)
        if let start {
            let end = start.addingTimeInterval(TimeInterval(max(15, durationMinutes) * 60))
            CommandCenterTaskScheduling.schedule(&metadata, from: start, to: end)
        } else {
            CommandCenterTaskScheduling.reschedule(&metadata, toDate: day)
            // An all-day landing must SHED any existing time block, or
            // `reschedule` carries the old wall-clock time onto the new day and
            // the entry reappears in the hour grid at a time nobody picked.
            CommandCenterTaskScheduling.clearCalendarTime(from: &metadata)
        }

        guard let merged = task.mergingTaskMetadata(
            metadata,
            context: "IdeaTaskLink.move(\(taskUUID.prefix(8)))"
        ) else { return nil }
        _ = try await AtomRepository.shared.update(merged)
        NotificationCenter.default.post(name: .atomsDidChange, object: nil)
        return before
    }

    /// Put a session's pins back exactly as they were (undo of `move`).
    static func restorePins(taskUUID: String, to snapshot: PinSnapshot) async throws {
        guard let task = try await AtomRepository.shared.fetch(uuid: taskUUID),
              var metadata = task.metadataValue(as: TaskMetadata.self) else { return }
        snapshot.apply(to: &metadata)
        guard let merged = task.mergingTaskMetadata(
            metadata,
            context: "IdeaTaskLink.restorePins(\(taskUUID.prefix(8)))"
        ) else { return }
        _ = try await AtomRepository.shared.update(merged)
        NotificationCenter.default.post(name: .atomsDidChange, object: nil)
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

    /// Bring a removed session back — the exact inverse of `removeScheduledTask`,
    /// and the ONLY correct redo for it.
    ///
    /// Undo/redo for a booked session MUST be delete/restore, never
    /// delete/re-create: re-creating mints a fresh uuid that the already-captured
    /// undo closure knows nothing about, so the next undo deletes the original
    /// (long dead) task and leaves the new one alive. Every redo would strand
    /// another orphan. `restore` also stamps `metadata.restoredAt`, which is what
    /// lets the undelete survive other devices' tombstone guards.
    static func restoreScheduledTask(taskUUID: String) async throws {
        try await AtomRepository.shared.restore(uuid: taskUUID)
        NotificationCenter.default.post(name: .atomsDidChange, object: nil)
    }
}
