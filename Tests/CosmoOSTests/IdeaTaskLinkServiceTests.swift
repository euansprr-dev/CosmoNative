// Tests/CosmoOSTests/IdeaTaskLinkServiceTests.swift
// Schedule-an-idea contract (July 2026): the created task carries the link
// (title mention pill + primary TaskLinkedAtom) with all three day pins set
// together; the idea atom is never written. Reverse lookup decode-filters
// LIKE candidates so a uuid mentioned elsewhere in metadata never counts as
// a scheduled session, and tombstoned tasks drop out.

import XCTest
@testable import CosmoOS

@MainActor
final class IdeaTaskLinkServiceTests: XCTestCase {
    private var cleanupUUIDs: [String] = []

    override func tearDown() async throws {
        for uuid in cleanupUUIDs.reversed() {
            try? await AtomRepository.shared.hardDelete(uuid: uuid, confirmed: true)
        }
        cleanupUUIDs.removeAll()
        try await super.tearDown()
    }

    private func makeIdea(title: String = "Test schedule idea") async throws -> Atom {
        let idea = try await AtomRepository.shared.create(Atom.new(type: .idea, title: title))
        cleanupUUIDs.append(idea.uuid)
        return idea
    }

    private func day(offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: .now))!
    }

    // MARK: - Creation shape

    func testCreateScheduledTaskCarriesLinkAndDayPins() async throws {
        let idea = try await makeIdea()
        let target = day(offset: 1)

        let task = try await IdeaTaskLinkService.createScheduledTask(for: idea, on: target)
        cleanupUUIDs.append(task.uuid)

        XCTAssertEqual(task.title, "Develop @Test schedule idea")

        let meta = try XCTUnwrap(task.metadataValue(as: TaskMetadata.self))
        XCTAssertEqual(meta.status, "todo")
        XCTAssertEqual(meta.intent, TaskIntent.deepThink.rawValue)
        XCTAssertNil(meta.recurrence)

        // Three pins move together — all on the target day.
        let iso = PlannerumFormatters.iso8601.string(from: Calendar.current.startOfDay(for: target))
        XCTAssertEqual(meta.dueDate, iso)
        XCTAssertEqual(meta.focusDate, iso)
        XCTAssertEqual(meta.whenDate, iso)

        // Primary linked atom points at the idea.
        let linked = IdeaTaskLinkService.linkedAtoms(of: task)
        XCTAssertEqual(linked.count, 1)
        XCTAssertEqual(linked.first?.atomUUID, idea.uuid)
        XCTAssertEqual(linked.first?.atomType, AtomType.idea.rawValue)
        XCTAssertEqual(linked.first?.isPrimary, true)

        // Title mention pill round-trips and matches the title's @span.
        let mentionsJSON = try XCTUnwrap(meta.titleMentions)
        let mentions = try JSONDecoder().decode([RichMention].self, from: Data(mentionsJSON.utf8))
        XCTAssertEqual(mentions.count, 1)
        XCTAssertEqual(mentions.first?.entityUUID, idea.uuid)
        XCTAssertEqual(mentions.first?.entityType, .idea)
        XCTAssertTrue(task.title?.contains("@\(mentions.first!.titleSnapshot)") == true)

        // The idea atom was never written.
        let fetchedIdea = try await AtomRepository.shared.fetch(uuid: idea.uuid)
        let freshIdea = try XCTUnwrap(fetchedIdea)
        XCTAssertEqual(freshIdea.updatedAt, idea.updatedAt)
        XCTAssertEqual(freshIdea.metadata ?? "", idea.metadata ?? "")
    }

    func testCreateWithEmptyTitleFallsBackToUntitled() async throws {
        let idea = try await makeIdea(title: "   ")
        let task = try await IdeaTaskLinkService.createScheduledTask(for: idea, on: day(offset: 0))
        cleanupUUIDs.append(task.uuid)
        XCTAssertEqual(task.title, "Develop @Untitled idea")
    }

    // MARK: - Reverse lookup

    func testScheduledTasksFiltersLikeFalsePositivesAndTombstones() async throws {
        let idea = try await makeIdea()

        let real = try await IdeaTaskLinkService.createScheduledTask(for: idea, on: day(offset: 2))
        cleanupUUIDs.append(real.uuid)

        // A task that merely mentions the uuid elsewhere in metadata must not count.
        var impostorMeta = TaskMetadata()
        impostorMeta.description = "references \(idea.uuid) in prose"
        let impostorJSON = String(data: try JSONEncoder().encode(impostorMeta), encoding: .utf8)
        let impostor = try await AtomRepository.shared.create(
            Atom.new(type: .task, title: "Impostor", metadata: impostorJSON)
        )
        cleanupUUIDs.append(impostor.uuid)

        let found = try await IdeaTaskLinkService.scheduledTasks(for: idea.uuid)
        XCTAssertEqual(found.map(\.uuid), [real.uuid])

        // Tombstoned sessions drop out.
        try await IdeaTaskLinkService.removeScheduledTask(taskUUID: real.uuid)
        let afterRemove = try await IdeaTaskLinkService.scheduledTasks(for: idea.uuid)
        XCTAssertTrue(afterRemove.isEmpty)

        // The idea survived the remove untouched.
        let freshIdea = try await AtomRepository.shared.fetch(uuid: idea.uuid)
        XCTAssertNotNil(freshIdea)
        XCTAssertEqual(freshIdea?.isDeleted, false)
    }

    // MARK: - Batched reverse lookup (the Desk / shelf chips)

    /// The bug this guards: `resolveScheduledDays` used to read only
    /// `linkedAtoms`, so after Begin Writing retargeted the link to the content
    /// atom the Ideas Desk chip went blank — while the ⌘⇧T popover still listed
    /// the session and the calendar still held it. Only the chip lied.
    func testBatchedLookupStillFindsSessionsRetargetedToContent() async throws {
        let idea = try await makeIdea()
        let task = try await IdeaTaskLinkService.createScheduledTask(for: idea, on: day(offset: 2))
        cleanupUUIDs.append(task.uuid)

        let content = try await AtomRepository.shared.create(Atom.new(type: .content, title: "Promoted piece"))
        cleanupUUIDs.append(content.uuid)
        _ = try await IdeaTaskLinkService.retargetToPromotedContent(ideaUUID: idea.uuid, content: content)

        let fetched = try await AtomRepository.shared.fetch(uuid: task.uuid)
        let retargeted = try XCTUnwrap(fetched)
        let days = IdeaTaskLinkService.openSessionDaysByIdea(in: [retargeted])

        XCTAssertNotNil(days[idea.uuid], "a promoted idea must keep its Scheduled chip")
    }

    /// The batched lookup and the single-idea lookup are twins — they must
    /// answer "is this a session for that idea" identically, or a surface goes
    /// blank while another still shows the session.
    func testBatchedLookupAgreesWithTheSingleIdeaLookup() async throws {
        let idea = try await makeIdea()
        let task = try await IdeaTaskLinkService.createScheduledTask(for: idea, on: day(offset: 3))
        cleanupUUIDs.append(task.uuid)

        let single = try await IdeaTaskLinkService.scheduledTasks(for: idea.uuid)
        let batched = IdeaTaskLinkService.openSessionDaysByIdea(in: single)

        XCTAssertEqual(single.map(\.uuid), [task.uuid])
        XCTAssertNotNil(batched[idea.uuid])
    }

    func testBatchedLookupKeepsTheEarliestOpenSessionAndSkipsCompleted() async throws {
        let idea = try await makeIdea()
        let later = try await IdeaTaskLinkService.createScheduledTask(for: idea, on: day(offset: 9))
        cleanupUUIDs.append(later.uuid)
        let sooner = try await IdeaTaskLinkService.createScheduledTask(for: idea, on: day(offset: 4))
        cleanupUUIDs.append(sooner.uuid)

        let both = try await IdeaTaskLinkService.scheduledTasks(for: idea.uuid)
        let days = IdeaTaskLinkService.openSessionDaysByIdea(in: both)
        XCTAssertEqual(days[idea.uuid], IdeaTaskLinkService.plannedDay(sooner))

        // A finished session is a record, not a booking — it must not hold the chip.
        let onlyCompleted = both.filter { $0.uuid == later.uuid }
        var completedMeta = try XCTUnwrap(onlyCompleted.first?.metadataValue(as: TaskMetadata.self))
        completedMeta.isCompleted = true
        let completedAtom = try XCTUnwrap(onlyCompleted.first?.mergingTaskMetadata(completedMeta, context: "test"))
        XCTAssertTrue(IdeaTaskLinkService.openSessionDaysByIdea(in: [completedAtom]).isEmpty)
    }

    // MARK: - Undo symmetry

    /// Remove and restore are the undo/redo pair for a booked session, and they
    /// must round-trip the SAME uuid.
    ///
    /// Guards a real bug: the desk's redo used to call `createScheduledTask`
    /// again, minting a fresh uuid the already-captured undo closure knew
    /// nothing about — so the next undo deleted the long-dead original and left
    /// the new task alive, stranding one orphan per redo.
    func testRemoveAndRestoreRoundTripTheSameSession() async throws {
        let idea = try await makeIdea()
        let task = try await IdeaTaskLinkService.createScheduledTask(for: idea, on: day(offset: 1))
        cleanupUUIDs.append(task.uuid)

        // undo
        try await IdeaTaskLinkService.removeScheduledTask(taskUUID: task.uuid)
        let afterUndo = try await IdeaTaskLinkService.scheduledTasks(for: idea.uuid)
        XCTAssertTrue(afterUndo.isEmpty)

        // redo — the SAME task comes back, not a second one.
        try await IdeaTaskLinkService.restoreScheduledTask(taskUUID: task.uuid)
        let afterRedo = try await IdeaTaskLinkService.scheduledTasks(for: idea.uuid)
        XCTAssertEqual(afterRedo.map(\.uuid), [task.uuid])

        // undo again — the pair stays symmetric, nothing is stranded.
        try await IdeaTaskLinkService.removeScheduledTask(taskUUID: task.uuid)
        let afterSecondUndo = try await IdeaTaskLinkService.scheduledTasks(for: idea.uuid)
        XCTAssertTrue(afterSecondUndo.isEmpty)
    }

    /// The restore has to survive other devices' one-way delete guards, which
    /// only accept an undelete carrying a `restoredAt` marker newer than their
    /// tombstone. Without it the session comes back locally and vanishes again
    /// on the next sync.
    func testRestoreStampsTheResurrectionMarker() async throws {
        let idea = try await makeIdea()
        let task = try await IdeaTaskLinkService.createScheduledTask(for: idea, on: day(offset: 1))
        cleanupUUIDs.append(task.uuid)

        try await IdeaTaskLinkService.removeScheduledTask(taskUUID: task.uuid)
        try await IdeaTaskLinkService.restoreScheduledTask(taskUUID: task.uuid)

        let restored = try await AtomRepository.shared.fetch(uuid: task.uuid)
        XCTAssertEqual(restored?.isDeleted, false)
        XCTAssertTrue(
            restored?.metadata?.contains("restoredAt") == true,
            "restore must stamp restoredAt or the undelete never crosses a tombstone"
        )
    }

    // MARK: - Reschedule

    func testRescheduleMovesAllThreePinsAndKeepsSiblingKeys() async throws {
        let idea = try await makeIdea()
        let task = try await IdeaTaskLinkService.createScheduledTask(for: idea, on: day(offset: 1))
        cleanupUUIDs.append(task.uuid)

        // Plant a sibling key another writer owns — it must survive the merge.
        var meta = try XCTUnwrap(task.metadataValue(as: TaskMetadata.self))
        meta.description = "session notes"
        let withNotes = try XCTUnwrap(task.mergingTaskMetadata(meta, context: "test"))
        _ = try await AtomRepository.shared.update(withNotes)

        let newDay = day(offset: 4)
        try await IdeaTaskLinkService.reschedule(taskUUID: task.uuid, to: newDay)

        let fetched = try await AtomRepository.shared.fetch(uuid: task.uuid)
        let fresh = try XCTUnwrap(fetched)
        let freshMeta = try XCTUnwrap(fresh.metadataValue(as: TaskMetadata.self))
        let iso = PlannerumFormatters.iso8601.string(from: Calendar.current.startOfDay(for: newDay))
        XCTAssertEqual(freshMeta.dueDate, iso)
        XCTAssertEqual(freshMeta.focusDate, iso)
        XCTAssertEqual(freshMeta.whenDate, iso)
        XCTAssertEqual(freshMeta.description, "session notes")
        // The link rode along untouched.
        XCTAssertEqual(IdeaTaskLinkService.linkedAtoms(of: fresh).first?.atomUUID, idea.uuid)
        XCTAssertEqual(IdeaTaskLinkService.plannedDay(fresh), Calendar.current.startOfDay(for: newDay))
    }

    // MARK: - Promotion retarget

    private func makeContent(title: String = "Test promoted content") async throws -> Atom {
        let content = try await AtomRepository.shared.createContent(title: title)
        cleanupUUIDs.append(content.uuid)
        return content
    }

    private func complete(_ task: Atom) async throws {
        var meta = try XCTUnwrap(task.metadataValue(as: TaskMetadata.self))
        meta.isCompleted = true
        meta.status = "done"
        let merged = try XCTUnwrap(task.mergingTaskMetadata(meta, context: "test.complete"))
        _ = try await AtomRepository.shared.update(merged)
    }

    /// Begin Writing moves the step: the live link and the title pill aim at the
    /// content piece, the pill's @span text is untouched (both renderers locate
    /// it by literal string), and no second linked atom appears — a non-primary
    /// entry would fan out as a side pane on play.
    func testRetargetAimsUnfinishedSessionAtContent() async throws {
        let idea = try await makeIdea()
        let task = try await IdeaTaskLinkService.createScheduledTask(for: idea, on: day(offset: 1))
        cleanupUUIDs.append(task.uuid)
        let content = try await makeContent()

        let moved = try await IdeaTaskLinkService.retargetToPromotedContent(
            ideaUUID: idea.uuid, content: content
        )
        XCTAssertEqual(moved, 1)

        let fetched = try await AtomRepository.shared.fetch(uuid: task.uuid)
        let fresh = try XCTUnwrap(fetched)
        let meta = try XCTUnwrap(fresh.metadataValue(as: TaskMetadata.self))

        let linked = IdeaTaskLinkService.linkedAtoms(of: fresh)
        XCTAssertEqual(linked.count, 1, "a second linked atom would open as a side pane on play")
        XCTAssertEqual(linked.first?.atomUUID, content.uuid)
        XCTAssertEqual(linked.first?.atomType, AtomType.content.rawValue)
        XCTAssertEqual(linked.first?.isPrimary, true)

        let mentions = try JSONDecoder().decode(
            [RichMention].self, from: Data(try XCTUnwrap(meta.titleMentions).utf8)
        )
        XCTAssertEqual(mentions.first?.entityUUID, content.uuid)
        XCTAssertEqual(mentions.first?.entityType, .content)
        // The @span must still be findable in the unchanged title.
        XCTAssertEqual(mentions.first?.titleSnapshot, "Test schedule idea")
        XCTAssertEqual(fresh.title, "Develop @Test schedule idea")
        XCTAssertTrue(fresh.title?.contains("@\(mentions.first!.titleSnapshot)") == true)

        // Day pins and intent are untouched — only the target moved.
        let iso = PlannerumFormatters.iso8601.string(from: Calendar.current.startOfDay(for: day(offset: 1)))
        XCTAssertEqual(meta.whenDate, iso)
        XCTAssertEqual(meta.intent, TaskIntent.deepThink.rawValue)
    }

    /// The idea keeps the session after promotion — it's reachable from the
    /// content's sources, and reopening it must still show "Scheduled · day".
    func testIdeaStillListsItsSessionAfterRetarget() async throws {
        let idea = try await makeIdea()
        let task = try await IdeaTaskLinkService.createScheduledTask(for: idea, on: day(offset: 2))
        cleanupUUIDs.append(task.uuid)
        let content = try await makeContent()

        _ = try await IdeaTaskLinkService.retargetToPromotedContent(ideaUUID: idea.uuid, content: content)

        let sessions = try await IdeaTaskLinkService.scheduledTasks(for: idea.uuid)
        XCTAssertEqual(sessions.map(\.uuid), [task.uuid])
        XCTAssertEqual(
            sessions.first?.metadataValue(as: TaskMetadata.self)?.originIdeaUUID,
            idea.uuid
        )
    }

    /// A finished session is a record of what was worked on — never rewritten.
    func testRetargetLeavesCompletedSessionsOnTheIdea() async throws {
        let idea = try await makeIdea()
        let task = try await IdeaTaskLinkService.createScheduledTask(for: idea, on: day(offset: 1))
        cleanupUUIDs.append(task.uuid)
        try await complete(task)
        let content = try await makeContent()

        let moved = try await IdeaTaskLinkService.retargetToPromotedContent(
            ideaUUID: idea.uuid, content: content
        )
        XCTAssertEqual(moved, 0)

        let fetched = try await AtomRepository.shared.fetch(uuid: task.uuid)
        let fresh = try XCTUnwrap(fetched)
        XCTAssertEqual(IdeaTaskLinkService.linkedAtoms(of: fresh).first?.atomUUID, idea.uuid)
        XCTAssertNil(fresh.metadataValue(as: TaskMetadata.self)?.originIdeaUUID)
    }

    /// Promoting the same idea twice leaves already-moved sessions where they
    /// are, rather than dragging them onto the newest content piece.
    func testSecondPromotionDoesNotMoveAlreadyRetargetedSessions() async throws {
        let idea = try await makeIdea()
        let task = try await IdeaTaskLinkService.createScheduledTask(for: idea, on: day(offset: 1))
        cleanupUUIDs.append(task.uuid)
        let first = try await makeContent(title: "First piece")
        let second = try await makeContent(title: "Second piece")

        _ = try await IdeaTaskLinkService.retargetToPromotedContent(ideaUUID: idea.uuid, content: first)
        let moved = try await IdeaTaskLinkService.retargetToPromotedContent(ideaUUID: idea.uuid, content: second)
        XCTAssertEqual(moved, 0)

        let fetched = try await AtomRepository.shared.fetch(uuid: task.uuid)
        let fresh = try XCTUnwrap(fetched)
        XCTAssertEqual(IdeaTaskLinkService.linkedAtoms(of: fresh).first?.atomUUID, first.uuid)
    }
}
