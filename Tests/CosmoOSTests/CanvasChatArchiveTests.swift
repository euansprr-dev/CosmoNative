import XCTest
import GRDB
@testable import CosmoOS

@MainActor
final class CanvasChatArchiveTests: XCTestCase {
    func testBackedChatPreservesSyncPayloadAndMergesRemoteTurns() throws {
        let atom = Atom.new(type: .note, structured: "{\"unrelated\":\"keep\"}")
        try CosmoDatabase.shared.write { db in try atom.insert(db) }
        defer {
            try? LocalDocumentArchive.delete(key: "cosmoCanvas.messageArchive." + atom.uuid)
            try? CosmoDatabase.shared.write { db in try db.execute(sql: "DELETE FROM atoms WHERE uuid = ?", arguments: [atom.uuid]) }
        }
        let original = CosmoWindowMessage.user("Local question")
        try CanvasChatArchive.save([original], entityUUID: atom.uuid)
        var payload = try CosmoDatabase.shared.read { db -> [String: Any] in
            let saved = try XCTUnwrap(Atom.filter(Column("uuid") == atom.uuid).fetchOne(db))
            XCTAssertEqual(try Bool.fetchOne(db, sql: "SELECT _local_pending FROM atoms WHERE uuid = ?", arguments: [atom.uuid]), true)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try XCTUnwrap(saved.structured).utf8)) as? [String: Any])
        }
        XCTAssertEqual(payload["unrelated"] as? String, "keep")
        XCTAssertEqual((payload["messages"] as? [[String: Any]])?.count, 1)
        let remote = CosmoWindowMessage.assistant("Answer from another device")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        payload["canvasMessageArchive"] = try JSONSerialization.jsonObject(with: encoder.encode([original, remote]))
        let json = try JSONSerialization.data(withJSONObject: payload)
        try CosmoDatabase.shared.write { db in
            try db.execute(sql: "UPDATE atoms SET structured = ? WHERE uuid = ?", arguments: [String(decoding: json, as: UTF8.self), atom.uuid])
        }
        let loaded = try CanvasChatArchive.load(entityUUID: atom.uuid)
        XCTAssertEqual(loaded.map(\.content), [original.content, remote.content])
    }

    func testAtomlessChatRetainsAllTurnsAcrossStaleSurfaceSave() throws {
        let uuid = UUID().uuidString
        defer { try? LocalDocumentArchive.delete(key: "cosmoCanvas.messageArchive." + uuid) }
        let original = (0..<75).map { CosmoWindowMessage.user("Question \($0)") }
        try CanvasChatArchive.save(original, entityUUID: uuid)
        var stale = Array(original.prefix(2))
        stale.append(.assistant("Answer from another surface"))
        try CanvasChatArchive.save(stale, entityUUID: uuid)
        let loaded = try CanvasChatArchive.load(entityUUID: uuid)
        XCTAssertEqual(loaded.count, 76)
        XCTAssertEqual(loaded.first?.content, "Question 0")
        XCTAssertTrue(loaded.contains { $0.content == "Question 74" })
        XCTAssertEqual(loaded.last?.content, "Answer from another surface")
    }

    func testCorruptArchiveIsPreservedOnSave() throws {
        let uuid = UUID().uuidString
        let key = "cosmoCanvas.messageArchive." + uuid
        defer { try? LocalDocumentArchive.delete(key: key) }
        let original = Data("cannot decode this saved transcript".utf8)
        try LocalDocumentArchive.save(key: key, data: original)
        XCTAssertThrowsError(try CanvasChatArchive.save([.user("New question")], entityUUID: uuid))
        XCTAssertEqual(try LocalDocumentArchive.load(key: key), original)
    }

    func testBackedChatFailureRollsBackBothCopies() throws {
        let atom = Atom.new(type: .note, structured: "[]")
        try CosmoDatabase.shared.write { db in try atom.insert(db) }
        defer {
            try? LocalDocumentArchive.delete(key: "cosmoCanvas.messageArchive." + atom.uuid)
            try? CosmoDatabase.shared.write { db in try db.execute(sql: "DELETE FROM atoms WHERE uuid = ?", arguments: [atom.uuid]) }
        }
        XCTAssertThrowsError(try CanvasChatArchive.save([.user("Keep this draft")], entityUUID: atom.uuid))
        XCTAssertNil(try LocalDocumentArchive.load(key: "cosmoCanvas.messageArchive." + atom.uuid))
        let structured = try CosmoDatabase.shared.read { db in
            try String.fetchOne(db, sql: "SELECT structured FROM atoms WHERE uuid = ?", arguments: [atom.uuid])
        }
        XCTAssertEqual(structured, "[]")
    }
}
