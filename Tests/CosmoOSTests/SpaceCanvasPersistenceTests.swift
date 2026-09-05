import XCTest
import GRDB
@testable import CosmoOS

final class SpaceCanvasPersistenceTests: XCTestCase {
    private func database() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE atoms (id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT NOT NULL UNIQUE,
                    type TEXT NOT NULL, title TEXT, body TEXT, structured TEXT, metadata TEXT, links TEXT,
                    created_at TEXT NOT NULL, updated_at TEXT NOT NULL, is_deleted INTEGER NOT NULL,
                    _local_version INTEGER NOT NULL, _server_version INTEGER NOT NULL, _sync_version INTEGER NOT NULL,
                    _local_pending INTEGER DEFAULT 0);
                CREATE TABLE canvas_blocks (id TEXT PRIMARY KEY, marker TEXT);
                CREATE TABLE canvas_drawings (id TEXT PRIMARY KEY, marker TEXT);
                INSERT INTO canvas_blocks VALUES ('root-placement', 'unchanged');
                INSERT INTO canvas_drawings VALUES ('root-drawing', 'unchanged');
                CREATE TRIGGER protect_root_blocks BEFORE UPDATE ON canvas_blocks BEGIN SELECT RAISE(ABORT, 'root layout touched'); END;
                CREATE TRIGGER protect_root_drawings BEFORE UPDATE ON canvas_drawings BEGIN SELECT RAISE(ABORT, 'root drawings touched'); END;
                CREATE TABLE atom_revisions (id INTEGER PRIMARY KEY AUTOINCREMENT, atom_uuid TEXT NOT NULL,
                    type TEXT NOT NULL, title TEXT, body TEXT, structured TEXT, metadata TEXT, links TEXT,
                    local_version INTEGER NOT NULL, source TEXT NOT NULL, created_at TEXT NOT NULL);
                CREATE TABLE sync_queue (id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT NOT NULL,
                    table_name TEXT NOT NULL, row_id INTEGER, operation TEXT, data TEXT,
                    local_version INTEGER, status TEXT, created_at INTEGER DEFAULT 0);
                """)
        }
        return queue
    }
    private func item(_ id: String, parent: String? = nil, order: Double = 0) throws -> Atom {
        var atom = Atom.new(type: .note, title: id, body: "Original writing")
        atom.uuid = id
        return try atom.replacingSpaceComposition(.init(parentUUID: parent, sortOrder: order))
    }
    private func group(_ id: String, members: [String]) throws -> Atom {
        var atom = Atom.new(type: .note, title: id)
        atom.uuid = id
        var metadata = SpaceCompositionMetadata(kind: .group)
        metadata.memberUUIDs = members
        return try atom.replacingSpaceComposition(metadata)
    }
    private func insert(_ atoms: [Atom], into queue: DatabaseQueue) throws {
        try queue.write { db in for var atom in atoms { try atom.insert(db) } }
    }
    private var mark: SpaceCanvasDrawing {
        .init(id: "mark", drawingType: "freehand", originX: 10, originY: 20, rotation: 0,
              points: [.init(x: 10, y: 20, w: 2), .init(x: 30, y: 40, w: 3)],
              strokeColor: "#112233", strokeWidth: 2.5, opacity: 1, zIndex: 0)
    }

    func testGeometryUndoPreservesOtherWorldsWritingOrderAndNewMetadata() throws {
        let queue = try database()
        let first = try group("first", members: ["page"]), second = try group("second", members: ["page"])
        try insert([first, second, item("page", parent: "book", order: 7)], into: queue)
        let placement = SpaceCompositionPlacement(itemUUID: "page", x: -100, y: 700, width: 500, height: 600)
        let patch = SpaceCanvasPatch(placements: [.init(itemUUID: "page", before: nil, after: placement, hiddenBefore: false, hiddenAfter: false)])
        try queue.write { db in
            _ = try SpaceCanvasPersistence.apply(patch, to: "first", db: db)
            try db.execute(sql: "UPDATE atoms SET metadata = json_set(metadata, '$.future', 'keep', '$.bodyDocument', 'new-rich-document') WHERE uuid = 'first'")
            let undone = try SpaceCanvasPersistence.apply(patch.reversed, to: "first", db: db)
            XCTAssertEqual(undone.metadataDict?["future"] as? String, "keep")
            XCTAssertEqual(undone.metadataDict?["bodyDocument"] as? String, "new-rich-document")
            XCTAssertEqual(undone.spaceComposition?.memberUUIDs, ["page"])
            XCTAssertTrue(undone.spaceComposition?.placements.isEmpty == true)
            XCTAssertEqual(try SpaceCanvasPersistence.container("second", db: db).metadata, second.metadata)
            let page = try SpaceCanvasPersistence.container("page", db: db)
            XCTAssertEqual(page.spaceComposition?.parentUUID, "book")
            XCTAssertEqual(page.spaceComposition?.sortOrder, 7)
            XCTAssertEqual(page.body, "Original writing")
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT marker FROM canvas_blocks"), "unchanged")
        }
    }

    func testHideAndShowPreserveMembershipAndUndoOnlyOwnedFlags() throws {
        let queue = try database()
        try insert([group("group", members: ["page"]), item("page")], into: queue)
        let hide = SpaceCanvasPatch(placements: [.init(itemUUID: "page", before: nil, after: nil, hiddenBefore: false, hiddenAfter: true)])
        try queue.write { db in
            let hidden = try SpaceCanvasPersistence.apply(hide, to: "group", db: db)
            XCTAssertEqual(try hidden.decodedSpaceCanvas().hiddenItemUUIDs, ["page"])
            XCTAssertEqual(hidden.spaceComposition?.memberUUIDs, ["page"])
            _ = try SpaceCanvasPersistence.apply(.init(drawings: [.init(id: "mark", before: nil, after: mark)]), to: "group", db: db)
            let restored = try SpaceCanvasPersistence.apply(hide.reversed, to: "group", db: db)
            XCTAssertEqual(try restored.decodedSpaceCanvas().drawings, [mark])
            XCTAssertTrue(try restored.decodedSpaceCanvas().hiddenItemUUIDs.isEmpty)
        }
    }

    func testMembershipRemovalUndoRestoresPositionWithoutReplacingOtherMembers() throws {
        let queue = try database()
        try insert([group("group", members: ["a", "b", "c"]), item("a"), item("b"), item("c"), item("d")], into: queue)
        let remove = SpaceCanvasPatch(placements: [.init(itemUUID: "b", before: nil, after: nil, hiddenBefore: false, hiddenAfter: false, memberBefore: true, memberAfter: false, memberIndex: 1)])
        try queue.write { db in
            _ = try SpaceCanvasPersistence.apply(remove, to: "group", db: db)
            var fresh = try SpaceCanvasPersistence.container("group", db: db)
            var metadata = try XCTUnwrap(fresh.spaceComposition); metadata.memberUUIDs.append("d")
            fresh = try fresh.replacingSpaceComposition(metadata); try fresh.update(db)
            let restored = try SpaceCanvasPersistence.apply(remove.reversed, to: "group", db: db)
            XCTAssertEqual(restored.spaceComposition?.memberUUIDs, ["a", "b", "c", "d"])
        }
    }

    func testConflictRollsBackWholeGestureAndKeepsNewerGeometry() throws {
        let queue = try database()
        try insert([group("group", members: ["page"]), item("page")], into: queue)
        let after = SpaceCompositionPlacement(itemUUID: "page", x: 50, y: 80)
        let patch = SpaceCanvasPatch(placements: [.init(itemUUID: "page", before: nil, after: after, hiddenBefore: false, hiddenAfter: false)])
        try queue.write { _ = try SpaceCanvasPersistence.apply(patch, to: "group", db: $0) }
        let stale = SpaceCanvasPatch(placements: patch.placements, drawings: [.init(id: "mark", before: nil, after: mark)])
        XCTAssertThrowsError(try queue.write { try SpaceCanvasPersistence.apply(stale, to: "group", db: $0) })
        try queue.read { db in
            let fresh = try SpaceCanvasPersistence.container("group", db: db)
            XCTAssertEqual(fresh.spaceComposition?.placements, [after])
            XCTAssertTrue(try fresh.decodedSpaceCanvas().drawings.isEmpty)
        }
    }

    func testDrawingsRoundTripEraseAndRejectInvalidGeometryWithoutRootRows() throws {
        let queue = try database(); try insert([group("group", members: [])], into: queue)
        let patch = SpaceCanvasPatch(drawings: [.init(id: mark.id, before: nil, after: mark)])
        try queue.write { db in
            let drawn = try SpaceCanvasPersistence.apply(patch, to: "group", db: db)
            XCTAssertEqual(try drawn.decodedSpaceCanvas().drawings, [mark])
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT marker FROM canvas_drawings"), "unchanged")
            let erased = try SpaceCanvasPersistence.apply(patch.reversed, to: "group", db: db)
            XCTAssertTrue(try erased.decodedSpaceCanvas().drawings.isEmpty)
        }
        var invalid = mark; invalid.points = [.init(x: .infinity, y: 0)]
        XCTAssertThrowsError(try queue.write { try SpaceCanvasPersistence.apply(.init(drawings: [.init(id: "mark", before: nil, after: invalid)]), to: "group", db: $0) })
    }

    func testScopedStickySaveWritesCanonicalDocumentAndPreservesContainer() throws {
        let queue = try database()
        var sticky = Atom.new(type: .stickyNote, title: "Sticky"); sticky.uuid = "sticky"
        let container = try group("group", members: [sticky.uuid])
        try insert([container, sticky], into: queue)
        try queue.write { db in
            let document = RichDocument.migrateLegacy("Changed 😀 writing")
            let saved = try CanvasNotePersistence.saveSticky(in: db, blockID: "composition:group:sticky", document: document, plainText: document.plainText)
            XCTAssertEqual(saved.atom.body, document.plainText)
            XCTAssertEqual(try SpaceCanvasPersistence.container("group", db: db).metadata, container.metadata)
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT marker FROM canvas_blocks"), "unchanged")
        }
    }

    func testUnknownCanvasKeysAndFutureVersionRemainSafe() throws {
        var atom = Atom.new(type: .note, metadata: #"{"futureRoot":true,"spaceComposition":{"schemaVersion":1,"kind":"group","futureGroup":9,"canvas":{"schemaVersion":1,"futureCanvas":"keep"}}}"#)
        var canvas = try atom.decodedSpaceCanvas(); canvas.drawings = [mark]
        atom = try atom.replacingSpaceCanvas(canvas)
        let composition = try XCTUnwrap(atom.metadataDict?["spaceComposition"] as? [String: Any])
        XCTAssertEqual(composition["futureGroup"] as? Int, 9)
        XCTAssertEqual((composition["canvas"] as? [String: Any])?["futureCanvas"] as? String, "keep")
        var raw = try XCTUnwrap(atom.metadataDict)
        var scope = try XCTUnwrap(raw["spaceComposition"] as? [String: Any])
        var rawCanvas = try XCTUnwrap(scope["canvas"] as? [String: Any])
        var records = try XCTUnwrap(rawCanvas["drawings"] as? [[String: Any]])
        records[0]["futureBrush"] = "retain pressure model"
        rawCanvas["drawings"] = records; scope["canvas"] = rawCanvas; raw["spaceComposition"] = scope
        atom.metadata = String(decoding: try JSONSerialization.data(withJSONObject: raw), as: UTF8.self)
        canvas.drawings[0].strokeColor = "#334455"
        let changed = try atom.replacingSpaceCanvas(canvas)
        let changedScope = try XCTUnwrap(changed.metadataDict?["spaceComposition"] as? [String: Any])
        let changedCanvas = try XCTUnwrap(changedScope["canvas"] as? [String: Any])
        XCTAssertEqual((changedCanvas["drawings"] as? [[String: Any]])?.first?["futureBrush"] as? String, "retain pressure model")
        let future = Atom.new(type: .note, metadata: #"{"spaceComposition":{"schemaVersion":1,"kind":"group","canvas":{"schemaVersion":99}}}"#)
        XCTAssertThrowsError(try future.replacingSpaceCanvas(SpaceCanvasContent()))
    }
}
