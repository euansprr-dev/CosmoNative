import XCTest
import GRDB
@testable import CosmoOS

final class SpaceDeletionTests: XCTestCase {
    private func database() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE atoms (id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT NOT NULL UNIQUE,
                    type TEXT NOT NULL, title TEXT, body TEXT, structured TEXT, metadata TEXT, links TEXT,
                    created_at TEXT NOT NULL, updated_at TEXT NOT NULL, is_deleted INTEGER NOT NULL,
                    _local_version INTEGER NOT NULL, _server_version INTEGER NOT NULL, _sync_version INTEGER NOT NULL,
                    _local_pending INTEGER DEFAULT 0);
                CREATE TABLE canvas_blocks (id TEXT PRIMARY KEY, entity_uuid TEXT, thinkspace_id TEXT,
                    is_deleted INTEGER DEFAULT 0, updated_at TEXT, _local_version INTEGER DEFAULT 0,
                    _local_pending INTEGER DEFAULT 0);
                CREATE TABLE atom_revisions (id INTEGER PRIMARY KEY AUTOINCREMENT, atom_uuid TEXT NOT NULL,
                    type TEXT NOT NULL, title TEXT, body TEXT, structured TEXT, metadata TEXT, links TEXT,
                    local_version INTEGER NOT NULL, source TEXT NOT NULL, created_at TEXT NOT NULL);
                """)
            for (id, parent) in [("space", nil), ("child", "space"), ("other", nil)] as [(String, String?)] {
                var metadata = ThinkspaceMetadata(name: id)
                metadata.parentThinkspaceId = parent
                var atom = Atom.new(type: .thinkspace, title: id).withMetadata(metadata)
                atom.uuid = id
                try atom.insert(db)
            }
            for id in ["note", "nested", "unrelated", "old"] {
                var atom = Atom.new(type: .note, title: id, body: "Writing to preserve")
                atom.uuid = id
                atom.isDeleted = id == "old"
                try atom.insert(db)
            }
            try db.execute(sql: """
                INSERT INTO canvas_blocks (id, entity_uuid, thinkspace_id, is_deleted) VALUES
                    ('member', 'note', 'space', 0), ('shared', 'note', 'other', 0),
                    ('nested-member', 'nested', 'child', 0), ('unrelated-member', 'unrelated', 'other', 0),
                    ('old-member', 'old', 'space', 1), ('old-placement', 'note', 'other', 1);
                """)
        }
        return queue
    }

    func testKeepContentsPreservesOriginalsOtherMembershipsAndChildSpaces() throws {
        let queue = try database()
        try queue.write { db in
            let change = try SpaceDeletionService.delete("space", contents: .keep, db: db)
            XCTAssertEqual(change.deletedUUIDs, ["space"])
            XCTAssertEqual(Set(change.membershipIDs), ["member"])
            XCTAssertEqual(try liveIDs(db), ["child", "other", "note", "nested", "unrelated"])
            XCTAssertNil(try atom("child", db).metadataValue(as: ThinkspaceMetadata.self)?.parentThinkspaceId)
            XCTAssertEqual(try atom("note", db).body, "Writing to preserve")
            XCTAssertEqual(try liveMemberships(db), ["shared", "nested-member", "unrelated-member"])
            // Undo must not overwrite writing performed after deletion.
            try db.execute(sql: "UPDATE atoms SET body = 'New writing' WHERE uuid = 'note'")
            try SpaceDeletionService.apply(change, undo: true, db: db)
            XCTAssertEqual(try atom("note", db).body, "New writing")
            XCTAssertEqual(try atom("child", db).metadataValue(as: ThinkspaceMetadata.self)?.parentThinkspaceId, "space")
            XCTAssertEqual(try liveMemberships(db), ["member", "shared", "nested-member", "unrelated-member"])
            XCTAssertTrue(try atom("old", db).isDeleted)
            try SpaceDeletionService.apply(change, undo: false, db: db)
            XCTAssertTrue(try atom("space", db).isDeleted)
            XCTAssertFalse(try atom("note", db).isDeleted)
        }
    }

    func testDeleteContentsIncludesChildSpacesAndSharedPlacementsAndUndoIsExact() throws {
        let queue = try database()
        try queue.write { db in
            let change = try SpaceDeletionService.delete("space", contents: .delete, db: db)
            XCTAssertEqual(change.deletedUUIDs, ["space", "child", "note", "nested"])
            XCTAssertEqual(try liveIDs(db), ["other", "unrelated"])
            XCTAssertEqual(try liveMemberships(db), ["unrelated-member"])
            try SpaceDeletionService.apply(change, undo: true, db: db)
            XCTAssertEqual(try liveIDs(db), ["space", "child", "other", "note", "nested", "unrelated"])
            XCTAssertEqual(try liveMemberships(db), ["member", "shared", "nested-member", "unrelated-member"])
            XCTAssertNotNil(try atom("note", db).metadataDict?["restoredAt"])
            try SpaceDeletionService.apply(change, undo: false, db: db)
            XCTAssertEqual(try liveIDs(db), ["other", "unrelated"])
        }
    }

    func testFailureRollsBackEntireDeletion() throws {
        let queue = try database()
        try queue.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_delete BEFORE UPDATE ON canvas_blocks BEGIN SELECT RAISE(ABORT, 'test failure'); END;")
        }
        XCTAssertThrowsError(try queue.write { db in
            try SpaceDeletionService.delete("space", contents: .delete, db: db)
        })
        try queue.read { db in
            XCTAssertEqual(try liveIDs(db), ["space", "child", "other", "note", "nested", "unrelated"])
            XCTAssertEqual(try liveMemberships(db), ["member", "shared", "nested-member", "unrelated-member"])
        }
    }

    private func atom(_ uuid: String, _ db: Database) throws -> Atom {
        try XCTUnwrap(Atom.filter(Column("uuid") == uuid).fetchOne(db))
    }
    private func liveIDs(_ db: Database) throws -> Set<String> {
        try String.fetchSet(db, sql: "SELECT uuid FROM atoms WHERE is_deleted = 0")
    }
    private func liveMemberships(_ db: Database) throws -> Set<String> {
        try String.fetchSet(db, sql: "SELECT id FROM canvas_blocks WHERE is_deleted = 0")
    }
}
