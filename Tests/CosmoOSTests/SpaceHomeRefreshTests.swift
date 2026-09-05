import XCTest
import GRDB
@testable import CosmoOS

final class SpaceHomeRefreshTests: XCTestCase {
    @MainActor
    func testScopedInquiryReadPreservesResultsAndSessionOrder() async throws {
        let diveID = UUID().uuidString
        let question = Atom.new(type: .question, title: "Scoped question").withMetadata(QuestionMetadata(parentDeepDiveUUID: diveID))
        let foreign = Atom.new(type: .question, title: "Foreign question").withMetadata(QuestionMetadata(parentDeepDiveUUID: "other"))
        let invalid = Atom.new(type: .question, title: "Malformed", metadata: "not-json")
        let old = Atom.new(type: .inquirySession, title: "Earlier session").withMetadata(InquirySessionMetadata(parentDeepDiveUUID: diveID, lastActiveAt: "2026-09-01T00:00:00Z"))
        let recent = Atom.new(type: .inquirySession, title: "Recent session").withMetadata(InquirySessionMetadata(parentDeepDiveUUID: diveID, lastActiveAt: "2026-09-05T00:00:00Z"))
        let fixtures = [question, foreign, invalid, old, recent]
        try await CosmoDatabase.shared.asyncWrite { db in
            try CanvasBlockSyncObserver.suppressingSync {
                for atom in fixtures { try atom.insert(db) }
            }
        }
        addTeardownBlock {
            try await CosmoDatabase.shared.asyncWrite { db in
                try CanvasBlockSyncObserver.suppressingSync {
                    for atom in fixtures { try db.execute(sql: "DELETE FROM atoms WHERE uuid = ?", arguments: [atom.uuid]) }
                }
            }
        }
        let questions = try await InquiryRepository.shared.fetchQuestions(forDeepDive: diveID)
        let sessions = try await InquiryRepository.shared.fetchSessions(forDeepDive: diveID)
        XCTAssertEqual(questions.map(\.uuid), [question.uuid])
        XCTAssertEqual(sessions.map(\.uuid), [recent.uuid, old.uuid])
    }

    func testDependencySignatureIgnoresWorkingNotesButTracksMembersAndInquiry() throws {
        let db = try DatabaseQueue()
        try db.write { db in
            try db.execute(sql: """
                CREATE TABLE atoms (uuid TEXT PRIMARY KEY, type TEXT, metadata TEXT,
                    updated_at TEXT NOT NULL DEFAULT 'now', _local_version INTEGER NOT NULL DEFAULT 1,
                    is_deleted INTEGER NOT NULL DEFAULT 0);
                CREATE TABLE canvas_blocks (entity_uuid TEXT, thinkspace_id TEXT,
                    document_type TEXT DEFAULT 'home', document_id INTEGER DEFAULT 0, is_deleted INTEGER DEFAULT 0);
                INSERT INTO atoms (uuid, type) VALUES ('space', 'thinkspace'), ('member', 'note'), ('other', 'note');
                INSERT INTO atoms (uuid, type, metadata) VALUES
                    ('question', 'question', '{"parentDeepDiveUUID":"dive"}'),
                    ('session', 'inquiry_session', '{"parentDeepDiveUUID":"dive"}'),
                    ('foreign', 'question', '{"parentDeepDiveUUID":"other-dive"}'),
                    ('malformed', 'question', 'invalid-json');
                INSERT INTO canvas_blocks (entity_uuid, thinkspace_id) VALUES ('member', 'space');
                """)
            let original = try SpaceHomeDependencyVersion.fetch(db, spaceID: "space", diveID: "dive")
            XCTAssertEqual(original.map(\.uuid), ["member", "question", "session"])
            try db.execute(sql: "UPDATE atoms SET _local_version = 2 WHERE uuid IN ('space', 'other', 'foreign')")
            XCTAssertEqual(original, try SpaceHomeDependencyVersion.fetch(db, spaceID: "space", diveID: "dive"))
            try db.execute(sql: "UPDATE atoms SET _local_version = 2 WHERE uuid = 'question'")
            let revised = try SpaceHomeDependencyVersion.fetch(db, spaceID: "space", diveID: "dive")
            XCTAssertNotEqual(original, revised)
            try db.execute(sql: "UPDATE canvas_blocks SET is_deleted = 1 WHERE entity_uuid = 'member'")
            XCTAssertEqual(try SpaceHomeDependencyVersion.fetch(db, spaceID: "space", diveID: "dive").map(\.uuid), ["question", "session"])
            XCTAssertEqual(try SpaceHomeDependencyVersion.fetch(db, spaceID: "space", diveID: nil), [])
        }
    }
}
