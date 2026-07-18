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
}
