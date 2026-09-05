// Tests/CosmoOSTests/CanvasMembershipTests.swift
// Membership without position (Sept 2026): a canvas_blocks row is membership
// in a space; `is_placed` says whether it also has a spot on the canvas.
// The world loads placed rows only, the tray reads the rest, unplace/place
// round-trip through undo, "Place all" is ONE undo, the sync payload carries
// the flag, and a gesture on an already-member atom places it instead of
// being skipped as a duplicate.

import XCTest
import GRDB
@testable import CosmoOS

@MainActor
final class CanvasMembershipTests: XCTestCase {
    private var thinkspaceId = ""
    private var atomUUIDs: [String] = []

    override func setUp() async throws {
        try await super.setUp()
        thinkspaceId = "ts-membership-\(UUID().uuidString)"
        CosmoUndoManager.shared.clearHistory()
    }

    override func tearDown() async throws {
        let ts = thinkspaceId
        try await CosmoDatabase.shared.asyncWrite { db in
            try CanvasBlockSyncObserver.suppressingSync {
                try db.execute(sql: "DELETE FROM canvas_blocks WHERE thinkspace_id = ?", arguments: [ts])
            }
        }
        for uuid in atomUUIDs.reversed() {
            try? await AtomRepository.shared.hardDelete(uuid: uuid, confirmed: true)
        }
        atomUUIDs.removeAll()
        CosmoUndoManager.shared.clearHistory()
        try await super.tearDown()
    }

    // MARK: - Fixtures

    private func makeAtom(_ title: String) async throws -> Atom {
        let atom = try await AtomRepository.shared.create(Atom.new(type: .note, title: title))
        atomUUIDs.append(atom.uuid)
        return atom
    }

    private func makeBlock(for atom: Atom, at position: CGPoint) -> CanvasBlock {
        CanvasBlock(
            id: "block-\(atom.uuid)",
            position: position,
            size: CGSize(width: 240, height: 160),
            entityType: .note,
            entityId: atom.id ?? 0,
            entityUuid: atom.uuid,
            title: atom.title ?? "",
            metadata: [:]
        )
    }

    /// A membership row written the way services write them (no gesture).
    @discardableResult
    private func insertMember(_ atom: Atom, at position: CGPoint = CGPoint(x: 100, y: 100), placed: Bool) async throws -> CanvasBlock {
        let block = makeBlock(for: atom, at: position)
        let record = CanvasBlockRecord.from(block, documentType: "home", documentId: 0, thinkspaceId: thinkspaceId, isPlaced: placed)
        try await CosmoDatabase.shared.asyncWrite { db in
            try CanvasBlockSyncObserver.suppressingSync {
                try record.insert(db)
            }
        }
        return block
    }

    private func isPlacedInDB(blockId: String) async throws -> Bool? {
        try await CosmoDatabase.shared.asyncRead { db in
            try Bool.fetchOne(db, sql: "SELECT is_placed FROM canvas_blocks WHERE id = ?", arguments: [blockId])
        }
    }

    private func positionInDB(blockId: String) async throws -> CGPoint? {
        try await CosmoDatabase.shared.asyncRead { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT position_x, position_y FROM canvas_blocks WHERE id = ?", arguments: [blockId]) else { return nil }
            return CGPoint(x: row["position_x"] as Int, y: row["position_y"] as Int)
        }
    }

    private func makeEngine() async -> SpatialEngine {
        let engine = SpatialEngine()
        await engine.loadBlocks(for: "home", documentId: 0, thinkspaceId: thinkspaceId)
        engine.currentThinkspaceId = thinkspaceId
        return engine
    }

    // MARK: - Schema

    func testInsertWithoutIsPlacedDefaultsToPlaced() async throws {
        let id = "legacy-\(UUID().uuidString)"
        let ts = thinkspaceId
        try await CosmoDatabase.shared.asyncWrite { db in
            try CanvasBlockSyncObserver.suppressingSync {
                try db.execute(
                    sql: """
                        INSERT INTO canvas_blocks (id, document_type, document_id, entity_id, entity_type, position_x, position_y, thinkspace_id)
                        VALUES (?, 'home', 0, 0, 'note', 10, 20, ?)
                        """,
                    arguments: [id, ts]
                )
            }
        }
        let placed = try await isPlacedInDB(blockId: id)
        XCTAssertEqual(placed, true, "Every pre-column row is a placement — the default must be 1")
    }

    // MARK: - Reads

    func testWorldLoadsPlacedMembersOnly() async throws {
        let placedAtom = try await makeAtom("Placed")
        let waitingAtom = try await makeAtom("Waiting")
        try await insertMember(placedAtom, placed: true)
        try await insertMember(waitingAtom, placed: false)

        let engine = await makeEngine()

        XCTAssertEqual(engine.blocks.map(\.entityUuid), [placedAtom.uuid])
        XCTAssertTrue(engine.blocks.allSatisfy(\.isPlaced))
    }

    func testFetchMembersCountsBothAndUnplacedReadsTheTray() async throws {
        let placedAtom = try await makeAtom("Placed")
        let waitingAtom = try await makeAtom("Waiting")
        try await insertMember(placedAtom, placed: true)
        try await insertMember(waitingAtom, placed: false)

        let members = try await SpatialEngine.fetchMembers(thinkspaceId: thinkspaceId)
        let unplaced = try await SpatialEngine.fetchUnplacedMembers(thinkspaceId: thinkspaceId)

        XCTAssertEqual(Set(members.compactMap(\.entityUuid)), [placedAtom.uuid, waitingAtom.uuid])
        XCTAssertEqual(unplaced.compactMap(\.entityUuid), [waitingAtom.uuid])
        XCTAssertEqual(unplaced.first?.isPlaced, false)
    }

    // MARK: - Unplace / place

    func testUnplaceThenRestoreRoundTripsThroughUndo() async throws {
        let atom = try await makeAtom("Round trip")
        let block = try await insertMember(atom, at: CGPoint(x: 640, y: 320), placed: true)
        let engine = await makeEngine()
        XCTAssertEqual(engine.blocks.count, 1)

        let action = UnplaceBlockAction(block: block, spatialEngine: engine)
        await action.redo()
        XCTAssertTrue(engine.blocks.isEmpty, "Unplacing leaves the world")
        let afterUnplace = try await isPlacedInDB(blockId: block.id)
        XCTAssertEqual(afterUnplace, false, "…but the row stays as membership")
        let stillMember = try await SpatialEngine.fetchMembers(thinkspaceId: thinkspaceId)
        XCTAssertEqual(stillMember.count, 1)

        await action.undo()
        XCTAssertEqual(engine.blocks.first?.id, block.id)
        XCTAssertEqual(engine.blocks.first?.position, CGPoint(x: 640, y: 320), "Undo restores the exact placement")
        let afterRestore = try await isPlacedInDB(blockId: block.id)
        XCTAssertEqual(afterRestore, true)
    }

    func testPlaceMemberGivesTheRowAPositionAndJoinsTheWorld() async throws {
        let atom = try await makeAtom("Tray member")
        let block = try await insertMember(atom, placed: false)
        let engine = await makeEngine()
        XCTAssertTrue(engine.blocks.isEmpty)

        let placed = await engine.placeMember(entityUuid: atom.uuid, at: CGPoint(x: 400, y: 300))

        XCTAssertEqual(placed?.id, block.id, "The membership row itself gains the position — no second row")
        XCTAssertEqual(engine.blocks.first?.position, CGPoint(x: 400, y: 300))
        XCTAssertEqual(engine.blocks.first?.isPlaced, true)
        let dbPosition = try await positionInDB(blockId: block.id)
        XCTAssertEqual(dbPosition, CGPoint(x: 400, y: 300))
        let dbPlaced = try await isPlacedInDB(blockId: block.id)
        XCTAssertEqual(dbPlaced, true)
        let unplaced = try await SpatialEngine.fetchUnplacedMembers(thinkspaceId: thinkspaceId)
        XCTAssertTrue(unplaced.isEmpty, "The tray empties")
    }

    func testPlaceAllRegistersExactlyOneUndo() async throws {
        let first = try await makeAtom("One")
        let second = try await makeAtom("Two")
        try await insertMember(first, placed: false)
        try await insertMember(second, placed: false)
        let engine = await makeEngine()

        let placed = await engine.placeAllUnplaced(anchor: CGPoint(x: 1000, y: 1000))

        XCTAssertEqual(Set(placed), [first.uuid, second.uuid])
        XCTAssertEqual(engine.blocks.count, 2)
        XCTAssertEqual(Set(engine.blocks.map(\.position)).count, 2, "Grid — no two members on the same point")
        XCTAssertTrue(CosmoUndoManager.shared.canUndo)

        await CosmoUndoManager.shared.undo()
        XCTAssertTrue(engine.blocks.isEmpty, "One ⌘Z sends every member back to the tray")
        XCTAssertFalse(CosmoUndoManager.shared.canUndo, "…because Place all was ONE action")
        let unplaced = try await SpatialEngine.fetchUnplacedMembers(thinkspaceId: thinkspaceId)
        XCTAssertEqual(unplaced.count, 2)

        await CosmoUndoManager.shared.redo()
        XCTAssertEqual(engine.blocks.count, 2)
    }

    // MARK: - Gesture on an existing member

    func testAddBlockPlacesAnUnplacedMemberInsteadOfSkippingIt() async throws {
        let atom = try await makeAtom("Filed then dragged")
        let member = try await insertMember(atom, placed: false)
        let engine = await makeEngine()

        // A gesture (⌘K drag, radial create…) lands the same atom on the canvas.
        let gesture = CanvasBlock(
            id: "gesture-\(UUID().uuidString)",
            position: CGPoint(x: 120, y: 80),
            size: CGSize(width: 240, height: 160),
            entityType: .note,
            entityId: atom.id ?? 0,
            entityUuid: atom.uuid,
            title: atom.title ?? "",
            metadata: [:]
        )
        await engine.addBlock(gesture)

        XCTAssertEqual(engine.blocks.count, 1, "The member is placed, not duplicated and not skipped")
        XCTAssertEqual(engine.blocks.first?.id, member.id, "The existing membership row is the one that moves")
        XCTAssertEqual(engine.blocks.first?.position, CGPoint(x: 120, y: 80))
        let ts = thinkspaceId
        let rowCount = try await CosmoDatabase.shared.asyncRead { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM canvas_blocks WHERE thinkspace_id = ? AND entity_uuid = ? AND is_deleted = 0",
                arguments: [ts, atom.uuid]
            ) ?? 0
        }
        XCTAssertEqual(rowCount, 1)
    }

    // MARK: - Sync payload

    func testCloudSyncPayloadCarriesIsPlaced() async throws {
        let waitingAtom = try await makeAtom("Waiting")
        let placedAtom = try await makeAtom("Placed")
        let waiting = try await insertMember(waitingAtom, placed: false)
        let placed = try await insertMember(placedAtom, placed: true)

        let payloads: [String: [String: Any]?] = try await CosmoDatabase.shared.asyncRead { db in
            var out: [String: [String: Any]?] = [:]
            for id in [waiting.id, placed.id] {
                let row = try Row.fetchOne(db, sql: "SELECT * FROM canvas_blocks WHERE id = ?", arguments: [id])
                out[id] = row.flatMap { CanvasBlockRecord.cloudSyncPayload(row: $0) }
            }
            return out
        }

        XCTAssertEqual(payloads[waiting.id]??["is_placed"] as? Bool, false)
        XCTAssertEqual(payloads[placed.id]??["is_placed"] as? Bool, true)
    }

    // MARK: - Clusters

    func testClusterBoundsIgnoreUnplacedMembers() throws {
        var near = CanvasBlock(
            id: "near", position: CGPoint(x: 0, y: 0), size: CGSize(width: 200, height: 100),
            entityType: .note, entityId: 1, entityUuid: "near-uuid", title: "Near", metadata: [:]
        )
        near.isPlaced = true
        var far = CanvasBlock(
            id: "far", position: CGPoint(x: 5000, y: 5000), size: CGSize(width: 200, height: 100),
            entityType: .note, entityId: 2, entityUuid: "far-uuid", title: "Far", metadata: [:]
        )
        far.isPlaced = false

        var cluster = CanvasCluster(
            id: UUID(),
            name: "Zone",
            blockUUIDs: ["near-uuid", "far-uuid"],
            colorIndex: 0,
            boundingRect: .zero,
            isCollapsed: false,
            isUserCreated: true,
            thinkspaceId: nil,
            synthesis: nil,
            synthesisUpdatedAt: nil,
            manualSizeOverride: nil,
            isZone: false,
            zoneType: nil,
            viewMode: .canvas
        )
        cluster.updateBoundingRect(blocks: [near, far], growOnly: false)

        XCTAssertLessThan(cluster.boundingRect.maxX, 1000, "A member without a position must not stretch the zone")
        XCTAssertLessThan(cluster.boundingRect.maxY, 1000)
    }
}
