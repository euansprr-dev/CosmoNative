import XCTest
import GRDB
@testable import CosmoOS

final class SpacePageEditorTests: XCTestCase {
    private func page(_ document: RichDocument = .migrateLegacy("Original writing")) -> Atom {
        let fields = RichDocumentPersistence.writeAtomDocuments(existingMetadata: "{\"spaceComposition\":{\"parentUUID\":\"book\"},\"futureField\":true}", bodyDocument: document)
        return Atom.new(type: .note, title: "Chapter", body: document.plainText, metadata: fields.metadata)
    }

    private func draft(_ atom: Atom, text: String = "A clearer argument") -> SpacePageDraft {
        SpacePageDraft(uuid: atom.uuid, base: SpacePageContentVersion(atom), document: .migrateLegacy(text), generation: 1)
    }

    func testBodySavePreservesConcurrentStructureTitleAndUnknownKeys() throws {
        let original = page()
        var fresh = original
        fresh.title = "Renamed elsewhere"
        let object = try XCTUnwrap(original.metadata?.data(using: .utf8))
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: object) as? [String: Any])
        fields["spaceComposition"] = ["parentUUID": "new-book", "position": "0.25"]
        fields["references"] = ["recently-attached-source"]
        fresh.metadata = String(decoding: try JSONSerialization.data(withJSONObject: fields), as: UTF8.self)

        let saved = try SpacePageContentWriter.applying(draft(original), to: fresh)
        let updated = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(saved.metadata!.utf8)) as? [String: Any])
        XCTAssertEqual(saved.title, fresh.title)
        XCTAssertEqual(updated["spaceComposition"] as? [String: String], ["parentUUID": "new-book", "position": "0.25"])
        XCTAssertEqual(updated["references"] as? [String], ["recently-attached-source"])
        XCTAssertEqual(updated["futureField"] as? Bool, true)
        XCTAssertEqual(saved.body, "A clearer argument")
    }

    func testConcurrentBodyChangeIsNotSilentlyReplaced() throws {
        let original = page()
        var fresh = original
        fresh.body = "Another writer's change"
        XCTAssertThrowsError(try SpacePageContentWriter.applying(draft(original), to: fresh)) {
            XCTAssertEqual($0 as? SpacePageSaveFailure, .contentChanged)
        }
        let resolved = try SpacePageContentWriter.applying(draft(original), to: fresh, replacingConflict: true)
        XCTAssertEqual(resolved.body, "A clearer argument")
    }

    func testConcurrentFormattingChangeIsAConflictEvenWhenPlainTextMatches() throws {
        let original = page()
        var changed = SpacePageContentVersion.document(original)
        changed.blocks[0].inlines[0].marks = [.bold]
        var fresh = original
        fresh.metadata = RichDocumentPersistence.writeAtomDocuments(existingMetadata: fresh.metadata, bodyDocument: changed).metadata
        XCTAssertEqual(changed.plainText, original.body)
        XCTAssertThrowsError(try SpacePageContentWriter.applying(draft(original), to: fresh))
    }

    func testRepeatedCommitOfSameDraftIsIdempotent() throws {
        let original = page()
        let pending = draft(original)
        let saved = try SpacePageContentWriter.applying(pending, to: original)
        let repeated = try SpacePageContentWriter.applying(pending, to: saved)
        XCTAssertEqual(repeated.body, saved.body)
        XCTAssertEqual(SpacePageContentVersion(repeated), SpacePageContentVersion(saved))
    }

    func testRichNestedBlocksAndIdentitySurviveSaving() throws {
        let original = page()
        let nested = RichDocument(blocks: [.section(title: "An exercise", children: [.paragraph("Keep these instructions")]), .table(RichTable())])
        let pending = SpacePageDraft(uuid: original.uuid, base: SpacePageContentVersion(original), document: nested, generation: 2)
        let saved = try SpacePageContentWriter.applying(pending, to: original)
        XCTAssertEqual(SpacePageContentVersion(saved).richDocument, nested)
        XCTAssertEqual(SpacePageContentVersion(saved).richDocument?.blocks.map(\.id), nested.blocks.map(\.id))
    }

    func testLegacyPlainTextCanBeEditedWithoutFalseUUIDConflict() throws {
        let original = Atom.new(type: .note, title: "Legacy page", body: "Existing plain text")
        let saved = try SpacePageContentWriter.applying(draft(original), to: original)
        XCTAssertEqual(saved.body, "A clearer argument")
        XCTAssertNotNil(SpacePageContentVersion(saved).richDocument)
    }

    func testExplicitEmptyEditIsPreserved() throws {
        let original = page()
        let pending = SpacePageDraft(uuid: original.uuid, base: SpacePageContentVersion(original), document: .empty, generation: 1)
        let saved = try SpacePageContentWriter.applying(pending, to: original)
        XCTAssertEqual(saved.body, "")
        XCTAssertEqual(SpacePageContentVersion(saved).richDocument, .empty)
    }

    func testDeletedPagesAndUnreadableMetadataAreNeverOverwritten() throws {
        let original = page()
        var removed = original
        removed.isDeleted = true
        XCTAssertThrowsError(try SpacePageContentWriter.applying(draft(original), to: removed, replacingConflict: true))
        var malformed = original
        malformed.metadata = "unreadable metadata"
        XCTAssertThrowsError(try SpacePageContentWriter.applying(draft(original), to: malformed, replacingConflict: true)) {
            XCTAssertEqual($0 as? SpacePageSaveFailure, .unreadableMetadata)
        }
        malformed.metadata = "{\"\(RichDocumentField.body.metadataKey)\":{\"futureFormat\":true}}"
        XCTAssertThrowsError(try SpacePageContentWriter.applying(draft(original), to: malformed, replacingConflict: true)) {
            XCTAssertEqual($0 as? SpacePageSaveFailure, .unreadableMetadata)
        }
    }

    func testCommitQueuesSyncAndRetainsRevisionInTheSameTransaction() throws {
        let database = try makeDatabase()
        var original = page()
        try database.write { db in try original.insert(db); original.id = db.lastInsertedRowID }
        let pending = draft(original)
        let saved = try database.write { db in try SpacePageContentWriter.persist(pending, replacingConflict: false, in: db) }
        try database.read { db in
            XCTAssertEqual(saved.localVersion, original.localVersion + 1)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT _local_pending FROM atoms WHERE uuid = ?", arguments: [original.uuid]), 1)
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT body FROM atom_revisions WHERE atom_uuid = ?", arguments: [original.uuid]), original.body)
            let payload = try XCTUnwrap(String.fetchOne(db, sql: "SELECT data FROM sync_queue WHERE uuid = ? AND table_name = 'atoms'", arguments: [original.uuid]))
            XCTAssertEqual(try JSONDecoder().decode(Atom.self, from: Data(payload.utf8)).body, saved.body)
        }
        // A failed queue write rolls back the atom and revision as well.
        try database.write { db in try db.execute(sql: "DROP TABLE sync_queue") }
        let second = draft(saved, text: "This must not be partially committed")
        XCTAssertThrowsError(try database.write { db in try SpacePageContentWriter.persist(second, replacingConflict: false, in: db) })
        try database.read { db in
            XCTAssertEqual(try Atom.filter(Column("uuid") == original.uuid).fetchOne(db)?.body, saved.body)
        }
    }

    func testRecoveryJournalCannotEraseANewerDraft() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = SpacePageDraftJournal(directory: folder)
        let original = page()
        let first = draft(original, text: "First checkpoint")
        let second = draft(original, text: "Newer writing")
        try await journal.save(first)
        try await journal.save(second)
        try await journal.remove(uuid: original.uuid, through: first.id)
        XCTAssertEqual(try journal.load(uuid: original.uuid)?.document, second.document)
        try await journal.remove(uuid: original.uuid, through: second.id)
        XCTAssertNil(try journal.load(uuid: original.uuid))
    }

    func testRecoveryJournalSurvivesANewSessionAndRetainsRichBlocks() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = page()
        let pending = draft(original)
        try SpacePageDraftJournal(directory: folder).saveSynchronously(pending)
        let restored = try XCTUnwrap(SpacePageDraftJournal(directory: folder).load(uuid: original.uuid))
        XCTAssertEqual(restored.uuid, original.uuid)
        XCTAssertEqual(restored.document, pending.document)
        XCTAssertEqual(restored.base, pending.base)
    }

    private func makeDatabase() throws -> DatabaseQueue {
        let database = try DatabaseQueue()
        try database.write { db in
            try db.execute(sql: """
                CREATE TABLE atoms (id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT NOT NULL UNIQUE,
                    type TEXT NOT NULL, title TEXT, body TEXT, structured TEXT, metadata TEXT, links TEXT,
                    created_at TEXT NOT NULL, updated_at TEXT NOT NULL, is_deleted INTEGER NOT NULL,
                    _local_version INTEGER NOT NULL, _server_version INTEGER NOT NULL, _sync_version INTEGER NOT NULL,
                    _local_pending INTEGER DEFAULT 0);
                CREATE TABLE atom_revisions (id INTEGER PRIMARY KEY AUTOINCREMENT, atom_uuid TEXT NOT NULL,
                    type TEXT NOT NULL, title TEXT, body TEXT, structured TEXT, metadata TEXT, links TEXT,
                    local_version INTEGER NOT NULL, source TEXT NOT NULL, created_at TEXT NOT NULL);
                CREATE TABLE sync_queue (id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT NOT NULL,
                    table_name TEXT NOT NULL, row_id INTEGER, operation TEXT, data TEXT,
                    local_version INTEGER, status TEXT, created_at INTEGER DEFAULT 0);
                """)
        }
        return database
    }
}
