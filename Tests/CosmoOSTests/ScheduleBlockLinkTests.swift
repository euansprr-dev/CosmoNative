// Tests/CosmoOSTests/ScheduleBlockLinkTests.swift
// The task ↔ schedule-block link contract shared with iOS (July 2026):
// scheduleBlockUUID is a pure membership pointer (never time-boxes the task),
// occurrence projection picks the slot per shown day, resolution is fail-soft
// for dangling links, and unlinking removes the key through the clear-honoring
// metadata merge.

import XCTest
@testable import CosmoOS

@MainActor
final class ScheduleBlockLinkTests: XCTestCase {
    private var cleanupUUIDs: [String] = []

    override func tearDown() async throws {
        for uuid in cleanupUUIDs.reversed() {
            try? await AtomRepository.shared.hardDelete(uuid: uuid, confirmed: true)
        }
        cleanupUUIDs.removeAll()
        try await super.tearDown()
    }

    private func date(_ hour: Int, _ minute: Int, dayOffset: Int = 0, calendar: Calendar = .current) -> Date {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: .now))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    // MARK: - Occurrence projection (pure)

    func testOccurrenceRangeMatchesOneOffDayOnly() {
        var meta = ScheduleBlockMetadata()
        meta.startTime = ISO8601.string(from: date(10, 0))
        meta.endTime = ISO8601.string(from: date(11, 30))

        let today = ScheduleBlockEngine.occurrenceRange(of: meta, on: .now)
        XCTAssertEqual(today?.start, date(10, 0))
        XCTAssertEqual(today?.end, date(11, 30))

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        XCTAssertNil(ScheduleBlockEngine.occurrenceRange(of: meta, on: tomorrow))
    }

    func testOccurrenceRangeProjectsRecurringTemplateOntoRuleDays() {
        let calendar = Calendar.current
        // Repeats only on today's weekday — today hits, tomorrow never does.
        let todayDay = DayOfWeek(rawValue: calendar.component(.weekday, from: .now))!
        var meta = ScheduleBlockMetadata()
        meta.startTime = ISO8601.string(from: date(15, 0, dayOffset: -7))
        meta.endTime = ISO8601.string(from: date(16, 0, dayOffset: -7))
        meta.recurrence = RecurrenceRule.weekly(on: [todayDay]).toJSON()

        let today = ScheduleBlockEngine.occurrenceRange(of: meta, on: .now)
        XCTAssertEqual(today?.start, date(15, 0))
        XCTAssertEqual(today?.end, date(16, 0))

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now)!
        XCTAssertNil(ScheduleBlockEngine.occurrenceRange(of: meta, on: tomorrow))
    }

    // MARK: - Unlink through the clear-honoring merge (pure)

    func testMergingTaskMetadataRemovesClearedBlockLinkAndKeepsSiblings() throws {
        var atom = Atom.new(type: .task, title: "Linked task")
        atom.metadata = #"{"status":"todo","scheduleBlockUUID":"block-1","iosOnlyKey":"survives"}"#

        var meta = try XCTUnwrap(atom.metadataValue(as: TaskMetadata.self))
        XCTAssertEqual(meta.scheduleBlockUUID, "block-1")

        meta.scheduleBlockUUID = nil
        let merged = try XCTUnwrap(atom.mergingTaskMetadata(meta, context: "test"))
        let dict = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(merged.metadata!.utf8)) as? [String: Any]
        )
        XCTAssertNil(dict["scheduleBlockUUID"])
        XCTAssertEqual(dict["iosOnlyKey"] as? String, "survives")
        XCTAssertEqual(dict["status"] as? String, "todo")
    }

    // MARK: - Display resolution (repository-backed)

    func testResolveLinksResolvesBlockAndFailsSoftForDanglingPointers() async throws {
        var blockMeta = ScheduleBlockMetadata()
        blockMeta.startTime = ISO8601.string(from: date(9, 0))
        blockMeta.endTime = ISO8601.string(from: date(10, 0))
        blockMeta.color = "#34D399"
        var blockAtom = Atom.new(type: .scheduleBlock, title: "Morning focus \(UUID().uuidString.prefix(6))")
        blockAtom.metadata = Atom.mergedJSONObjectString(existing: nil, overlay: blockMeta, context: "test")
        let block = try await AtomRepository.shared.create(blockAtom)
        cleanupUUIDs.append(block.uuid)

        var linked = TaskViewModel(uuid: "task-linked", title: "Write outline")
        linked.scheduleBlockUUID = block.uuid
        var dangling = TaskViewModel(uuid: "task-dangling", title: "Orphan")
        dangling.scheduleBlockUUID = "no-such-block-\(UUID().uuidString)"
        let unlinked = TaskViewModel(uuid: "task-unlinked", title: "Free agent")

        let resolved = await ScheduleBlockEngine.resolveLinks(in: [linked, dangling, unlinked], on: .now)

        XCTAssertEqual(resolved[0].blockTitle, block.title)
        XCTAssertEqual(resolved[0].blockColorHex, "#34D399")
        XCTAssertEqual(resolved[0].blockStart, date(9, 0))
        XCTAssertEqual(resolved[0].blockEnd, date(10, 0))
        XCTAssertTrue(resolved[0].blockIsLive(at: date(9, 30)))
        XCTAssertFalse(resolved[0].blockIsLive(at: date(10, 30)))

        // Dangling pointer: badge fields stay nil, nothing crashes.
        XCTAssertNil(resolved[1].blockTitle)
        XCTAssertNil(resolved[1].blockStart)

        XCTAssertNil(resolved[2].blockTitle)
    }

    func testResolveLinksOnANonOccurrenceDayKeepsTitleButNoTimes() async throws {
        let calendar = Calendar.current
        let todayDay = DayOfWeek(rawValue: calendar.component(.weekday, from: .now))!
        var blockMeta = ScheduleBlockMetadata()
        blockMeta.startTime = ISO8601.string(from: date(15, 0))
        blockMeta.endTime = ISO8601.string(from: date(16, 0))
        blockMeta.recurrence = RecurrenceRule.weekly(on: [todayDay]).toJSON()
        var blockAtom = Atom.new(type: .scheduleBlock, title: "Deep work \(UUID().uuidString.prefix(6))")
        blockAtom.metadata = Atom.mergedJSONObjectString(existing: nil, overlay: blockMeta, context: "test")
        let block = try await AtomRepository.shared.create(blockAtom)
        cleanupUUIDs.append(block.uuid)

        var task = TaskViewModel(uuid: "task-offday", title: "Slides")
        task.scheduleBlockUUID = block.uuid

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now)!
        let resolved = await ScheduleBlockEngine.resolveLinks(in: [task], on: tomorrow)

        // The association survives (the badge still names the block)…
        XCTAssertEqual(resolved[0].blockTitle, block.title)
        // …but there is no occurrence that day, so it can never read "live".
        XCTAssertNil(resolved[0].blockStart)
        XCTAssertNil(resolved[0].blockEnd)
    }
}
