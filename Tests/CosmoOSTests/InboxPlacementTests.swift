import XCTest
import GRDB
@testable import CosmoOS

/// Runs the production writer against an in-memory queue, never CosmoDatabase.shared.
final class InboxPlacementTests: XCTestCase {
    private func database() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE atoms (id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT NOT NULL UNIQUE,
                    type TEXT NOT NULL, title TEXT, body TEXT, structured TEXT, metadata TEXT, links TEXT,
                    created_at TEXT NOT NULL, updated_at TEXT NOT NULL, is_deleted INTEGER NOT NULL,
                    _local_version INTEGER NOT NULL, _server_version INTEGER NOT NULL, _sync_version INTEGER NOT NULL,
                    _local_pending INTEGER DEFAULT 0);
                CREATE TABLE inbox_items (id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT NOT NULL UNIQUE,
                    source TEXT, rawText TEXT, title TEXT, classification TEXT, confidence REAL,
                    mergeTargetUuid TEXT, mergeTargetTitle TEXT, mergeTargetType TEXT, mergePreview TEXT,
                    placeThinkspaceId TEXT, placeThinkspaceName TEXT, placeAtomType TEXT, recommendations TEXT,
                    primaryRouteKind TEXT, destinationPath TEXT, rationale TEXT, placementPlanSummary TEXT,
                    status TEXT, isRead INTEGER, createdAt TEXT, classifiedAt TEXT, actionedAt TEXT, metadata TEXT,
                    is_deleted INTEGER DEFAULT 0, updated_at TEXT, _local_version INTEGER DEFAULT 1,
                    _server_version INTEGER DEFAULT 0, _sync_version INTEGER DEFAULT 0, _local_pending INTEGER DEFAULT 0);
                CREATE TABLE canvas_blocks (id TEXT PRIMARY KEY, entity_uuid TEXT, is_deleted INTEGER DEFAULT 0);
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
    private func request(_ item: InboxItem, destination: InboxFilingDestination? = nil) -> InboxPlacementRequest {
        let destination = destination ?? .init(kind: .pages, name: "Pages", path: "Pages")
        return .init(operationID: "fixture-operation", source: .init(kind: .inbox, uuid: item.uuid),
            expectedSourceVersion: item.localVersion, destination: destination, action: destination.defaultAction)
    }

    func testRetrySettlesExactlyOneOriginalAndDurableReceipt() throws {
        let queue = try database()
        let item = InboxItem.new(source: .quickCapture, rawText: "Complete capture")
        try queue.write { try item.insert($0) }
        let command = request(item)
        let first = try queue.write { try InboxPlacementService.commit(command, preparedAtom: nil, db: $0) }
        let retry = try queue.write { try InboxPlacementService.commit(command, preparedAtom: nil, db: $0) }
        XCTAssertEqual(first, retry)
        try queue.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM atoms"), 1)
            XCTAssertEqual(try InboxItem.fetchOne(db)?.placementReceipt, first)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_queue WHERE table_name = 'atoms'"), 1)
        }
    }

    func testFailureAtSourceWriteRollsBackOriginalAndQueueIntent() throws {
        let queue = try database()
        let item = InboxItem.new(source: .quickCapture, rawText: "Keep this original")
        try queue.write { db in
            try item.insert(db)
            try db.execute(sql: "CREATE TRIGGER reject_settlement BEFORE UPDATE ON inbox_items BEGIN SELECT RAISE(ABORT, 'fixture failure'); END")
        }
        let command = request(item)
        XCTAssertThrowsError(try queue.write { try InboxPlacementService.commit(command, preparedAtom: nil, db: $0) })
        try queue.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM atoms"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_queue"), 0)
            XCTAssertEqual(try InboxItem.fetchOne(db)?.status, .pending)
        }
    }

    func testReferencePreservesLongOriginalRichBodyAndUnknownCanvas() throws {
        let queue = try database()
        let text = String(repeating: "完整 capture 👩🏽‍💻 paragraph\n", count: 300)
        let item = InboxItem.new(source: .quickCapture, rawText: text)
        let metadata = #"{"bodyDocument":"rich-image-table","spaceComposition":{"schemaVersion":1,"kind":"page","canvas":{"future":"retain"}}}"#
        let target = Atom.new(type: .note, title: "Book", body: "Authored body", metadata: metadata)
        try queue.write { db in try item.insert(db); try target.insert(db) }
        let command = request(item, destination: .init(kind: .page, uuid: target.uuid, name: "Book", path: "Pages › Book"))
        let receipt = try queue.write { try InboxPlacementService.commit(command, preparedAtom: nil, db: $0) }
        try queue.read { db in
            let page = try XCTUnwrap(Atom.filter(Column("uuid") == target.uuid).fetchOne(db))
            XCTAssertEqual(page.body, "Authored body")
            XCTAssertEqual(page.spaceComposition?.references.first?.excerpt, text)
            XCTAssertEqual(page.metadataDict?["bodyDocument"] as? String, "rich-image-table")
            XCTAssertTrue(page.metadata?.contains("retain") == true)
        }
        _ = try queue.write { try InboxPlacementService.reverse(receipt, db: $0) }
        try queue.read { db in
            XCTAssertTrue(try Atom.filter(Column("uuid") == target.uuid).fetchOne(db)?.spaceComposition?.references.isEmpty == true)
        }
    }

    func testUndoKeepsNewerWritingAndReturnsOriginalCapture() throws {
        let queue = try database()
        let item = InboxItem.new(source: .quickCapture, rawText: "Initial draft")
        try queue.write { try item.insert($0) }
        let command = request(item)
        let receipt = try queue.write { try InboxPlacementService.commit(command, preparedAtom: nil, db: $0) }
        try queue.write { db in
            try db.execute(sql: "UPDATE atoms SET body = 'Newer writing' WHERE uuid = ?", arguments: [receipt.resultAtomUUID])
        }
        let undone = try queue.write { try InboxPlacementService.reverse(receipt, db: $0) }
        XCTAssertTrue(undone.retainedOriginal)
        try queue.read { db in
            XCTAssertEqual(try Atom.fetchOne(db)?.body, "Newer writing")
            XCTAssertEqual(try Atom.fetchOne(db)?.isDeleted, false)
            XCTAssertEqual(try InboxItem.fetchOne(db)?.status, .pending)
        }
    }
}
