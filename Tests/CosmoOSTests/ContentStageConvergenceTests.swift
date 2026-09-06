// Tests/CosmoOSTests/ContentStageConvergenceTests.swift
// One stage machine (Sept 2026): `phase` is the truth and every writer —
// applyPhase, schedule/unschedule, ship — converges on it. Forward moves
// mint XP once, backward moves mint an honest zero-XP record, scheduling
// remembers where the piece came from, shipping strips that memory, and a
// shipped or archived piece is never un-shipped by a date change. Sibling
// metadata keys survive every write (key-merge law).

import XCTest
import GRDB
@testable import CosmoOS

final class ContentStageConvergenceTests: XCTestCase {
    private var contentUUIDs: [String] = []

    override func tearDown() async throws {
        let uuids = contentUUIDs
        try await CosmoDatabase.shared.asyncWrite { db in
            try CanvasBlockSyncObserver.suppressingSync {
                for uuid in uuids {
                    try db.execute(sql: "DELETE FROM atoms WHERE uuid = ?", arguments: [uuid])
                    try db.execute(
                        sql: "DELETE FROM atoms WHERE type = ? AND links LIKE ?",
                        arguments: [AtomType.contentPhase.rawValue, "%\(uuid)%"]
                    )
                }
            }
        }
        contentUUIDs.removeAll()
        try await super.tearDown()
    }

    // MARK: - Fixtures

    private func makeContent(phase: ContentPhase, extra: [String: Any] = [:]) async throws -> Atom {
        var dict: [String: Any] = ["phase": phase.rawValue, "clientProfileUUID": "client-sibling"]
        for (key, value) in extra { dict[key] = value }
        let data = try JSONSerialization.data(withJSONObject: dict)
        let metadata = String(decoding: data, as: UTF8.self)
        let atom = try await AtomRepository.shared.create(
            Atom.new(type: .content, title: "Stage piece", body: nil, metadata: metadata)
        )
        contentUUIDs.append(atom.uuid)
        return atom
    }

    private func reload(_ uuid: String) async throws -> Atom {
        let atom = try await AtomRepository.shared.fetch(uuid: uuid)
        return try XCTUnwrap(atom)
    }

    private func phase(_ uuid: String) async throws -> ContentPhase? {
        ContentPipelineService.currentPhase(of: try await reload(uuid))
    }

    private func meta(_ uuid: String) async throws -> ContentAtomMetadata? {
        try await reload(uuid).metadataValue(as: ContentAtomMetadata.self)
    }

    private func status(_ uuid: String) async throws -> String? {
        try await reload(uuid).metadataDict?["status"] as? String
    }

    private func phaseRecordCount(_ uuid: String) async throws -> Int {
        try await CosmoDatabase.shared.asyncRead { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM atoms WHERE type = ? AND links LIKE ? AND is_deleted = 0",
                arguments: [AtomType.contentPhase.rawValue, "%\(uuid)%"]
            ) ?? 0
        }
    }

    // MARK: - applyPhase

    func testForwardMoveMintsARecordAndEarnsXPOnce() async throws {
        let atom = try await makeContent(phase: .ideation)

        let first = try await ContentPipelineService.applyPhase(contentUUID: atom.uuid, to: .draft, notes: nil)
        XCTAssertEqual(first?.from, .ideation)
        XCTAssertEqual(first?.to, .draft)
        XCTAssertEqual(first?.xpEarned, ContentPhase.draft.completionXP)
        let afterFirst = try await phase(atom.uuid)
        XCTAssertEqual(afterFirst, .draft)
        let records = try await phaseRecordCount(atom.uuid)
        XCTAssertEqual(records, 1)

        // Back, then forward again into a phase already entered: honest record, zero XP.
        let back = try await ContentPipelineService.applyPhase(contentUUID: atom.uuid, to: .ideation, notes: nil)
        XCTAssertEqual(back?.xpEarned, 0, "Backward moves never earn")
        let again = try await ContentPipelineService.applyPhase(contentUUID: atom.uuid, to: .draft, notes: nil)
        XCTAssertEqual(again?.xpEarned, 0, "Re-entering a phase earns nothing twice")
        let recordsAfter = try await phaseRecordCount(atom.uuid)
        XCTAssertEqual(recordsAfter, 3, "Every real move mints a record")
    }

    func testSamePhaseIsANoOp() async throws {
        let atom = try await makeContent(phase: .polish)
        let transition = try await ContentPipelineService.applyPhase(contentUUID: atom.uuid, to: .polish, notes: nil)
        XCTAssertNil(transition)
        let records = try await phaseRecordCount(atom.uuid)
        XCTAssertEqual(records, 0)
    }

    func testSiblingMetadataKeysSurviveAPhaseWrite() async throws {
        let atom = try await makeContent(phase: .draft, extra: ["hooks": ["a", "b"]])
        _ = try await ContentPipelineService.applyPhase(contentUUID: atom.uuid, to: .polish, notes: nil)
        let dict = try await reload(atom.uuid).metadataDict
        XCTAssertEqual(dict?["clientProfileUUID"] as? String, "client-sibling")
        XCTAssertEqual(dict?["hooks"] as? [String], ["a", "b"])
        XCTAssertEqual(dict?["phase"] as? String, "polish")
    }

    func testXPRulesArePure() {
        XCTAssertEqual(
            ContentPipelineService.xpForTransition(from: .draft, to: .polish, previouslyEntered: []),
            ContentPhase.polish.completionXP
        )
        XCTAssertEqual(ContentPipelineService.xpForTransition(from: .polish, to: .draft, previouslyEntered: []), 0)
        XCTAssertEqual(ContentPipelineService.xpForTransition(from: .draft, to: .polish, previouslyEntered: [.polish]), 0)
    }

    // MARK: - Clearing the board (Published)

    func testClearingFromBoardIsKeyMergedAndReversible() async throws {
        let atom = try await makeContent(phase: .published, extra: [
            "hooks": ["a"],
            "publishRecords": [["platform": "instagram", "publishedAt": "2030-01-01T09:00:00Z"]]
        ])

        let cleared = try await ContentPipelineService.setClearedFromBoard(contentUUID: atom.uuid, cleared: true)
        let stamp = try XCTUnwrap(cleared.after.metadataDict?["boardClearedAt"] as? String)
        let dict = try await reload(atom.uuid).metadataDict
        XCTAssertEqual(dict?["boardClearedAt"] as? String, stamp)
        XCTAssertEqual(dict?["hooks"] as? [String], ["a"], "siblings survive")
        XCTAssertEqual(dict?["clientProfileUUID"] as? String, "client-sibling")
        XCTAssertEqual(dict?["phase"] as? String, "published", "clearing never changes the phase")
        XCTAssertEqual(try await phase(atom.uuid), .published)

        // Clearing again keeps the first stamp and writes nothing.
        let again = try await ContentPipelineService.setClearedFromBoard(contentUUID: atom.uuid, cleared: true)
        XCTAssertEqual(again.before.localVersion, again.after.localVersion, "a no-op must not bump the version")
        XCTAssertEqual(again.after.metadataDict?["boardClearedAt"] as? String, stamp)

        let returned = try await ContentPipelineService.setClearedFromBoard(contentUUID: atom.uuid, cleared: false)
        XCTAssertNil(returned.after.metadataDict?["boardClearedAt"])
        let back = try await reload(atom.uuid).metadataDict
        XCTAssertNil(back?["boardClearedAt"])
        XCTAssertEqual(back?["hooks"] as? [String], ["a"])
        XCTAssertEqual(try await phase(atom.uuid), .published)
    }

    func testAStageMoveReturnsAClearedPieceToTheBoard() async throws {
        let atom = try await makeContent(phase: .published, extra: ["boardClearedAt": "2030-01-01T09:00:00Z"])
        _ = try await ContentPipelineService.applyProductionStage(contentUUID: atom.uuid, to: .review)
        let dict = try await reload(atom.uuid).metadataDict
        XCTAssertNil(dict?["boardClearedAt"], "a deliberate move is activity — the piece is back on the board")
        XCTAssertEqual(dict?["productionStage"] as? String, "review")
        XCTAssertEqual(dict?["clientProfileUUID"] as? String, "client-sibling")
    }

    func testANewPublicationReturnsAClearedPieceButAPreservedReMarkDoesNot() async throws {
        let atom = try await makeContent(phase: .published, extra: [
            "boardClearedAt": "2030-01-01T09:00:00Z",
            "publishRecords": [["platform": "instagram", "publishedAt": "2030-01-01T09:00:00Z"]]
        ])
        // A performance import re-marks the same platform and keeps its date: not new activity.
        await ContentPublishStore.markPublished(atomUuid: atom.uuid, platform: "instagram", preservingExistingDate: true)
        XCTAssertNotNil(try await reload(atom.uuid).metadataDict?["boardClearedAt"], "a preserved re-mark leaves the board alone")

        // A new platform is a new publication: back on the board.
        await ContentPublishStore.markPublished(atomUuid: atom.uuid, platform: "linkedin")
        let dict = try await reload(atom.uuid).metadataDict
        XCTAssertNil(dict?["boardClearedAt"])
        XCTAssertEqual((dict?["publishRecords"] as? [[String: Any]])?.count, 2, "the instagram record is kept beside the new one")
    }

    // MARK: - Schedule writer converges

    func testPlanningPublicationPreservesPolishActivity() async throws {
        let atom = try await makeContent(phase: .polish)
        let day = Date().addingTimeInterval(86_400 * 3)

        await ContentQueueLoader.setSchedule(day, status: "scheduled", for: atom.uuid, registerUndo: false)

        let now = try await phase(atom.uuid)
        XCTAssertEqual(now, .polish)
        let metadata = try await meta(atom.uuid)
        XCTAssertNil(metadata?.phaseBeforeSchedule)
        let mirror = try await status(atom.uuid)
        XCTAssertEqual(mirror, "scheduled", "iOS still reads the status mirror")
        let dict = try await reload(atom.uuid).metadataDict
        XCTAssertNotNil(dict?["scheduledAt"])
    }

    func testUnschedulingRestoresThePhaseItCameFrom() async throws {
        let atom = try await makeContent(phase: .draft)
        await ContentQueueLoader.setSchedule(Date().addingTimeInterval(86_400), status: "scheduled", for: atom.uuid, registerUndo: false)
        let scheduled = try await phase(atom.uuid)
        XCTAssertEqual(scheduled, .draft)

        await ContentQueueLoader.setSchedule(nil, status: "draft", for: atom.uuid, registerUndo: false)

        let restored = try await phase(atom.uuid)
        XCTAssertEqual(restored, .draft)
        let metadata = try await meta(atom.uuid)
        XCTAssertNil(metadata?.phaseBeforeSchedule, "The memory is consumed on the way back")
        let dict = try await reload(atom.uuid).metadataDict
        XCTAssertNil(dict?["scheduledAt"])
        let mirror = try await status(atom.uuid)
        XCTAssertEqual(mirror, "draft")
    }

    func testDatingAShippedPieceNeverUnshipsIt() async throws {
        let atom = try await makeContent(phase: .published, extra: ["status": "published"])

        await ContentQueueLoader.setSchedule(Date().addingTimeInterval(86_400), status: "scheduled", for: atom.uuid, registerUndo: false)

        let now = try await phase(atom.uuid)
        XCTAssertEqual(now, .published, "A repost date is a correction, not a stage change")
        let mirror = try await status(atom.uuid)
        XCTAssertEqual(mirror, "published", "The mirror never regresses a shipped piece")
    }

    // MARK: - Ship writer converges

    func testMarkPublishedEntersPublishedAndStripsTheScheduleMemory() async throws {
        let atom = try await makeContent(phase: .scheduled, extra: ["phaseBeforeSchedule": "polish"])

        await ContentPublishStore.markPublished(atomUuid: atom.uuid, platform: "instagram")

        let now = try await phase(atom.uuid)
        XCTAssertEqual(now, .published)
        let metadata = try await meta(atom.uuid)
        XCTAssertNil(metadata?.phaseBeforeSchedule)
        let records = ContentPublishStore.records(for: try await reload(atom.uuid))
        XCTAssertEqual(records.count, 1, "Shipping writes the publish record the calendar reads")
    }

    func testMarkPublishedLeavesAnArchivedPieceArchived() async throws {
        let atom = try await makeContent(phase: .archived)

        await ContentPublishStore.markPublished(atomUuid: atom.uuid, platform: "instagram")

        let now = try await phase(atom.uuid)
        XCTAssertEqual(now, .archived, "Never un-archive")
    }
}
