import XCTest
import GRDB
@testable import CosmoOS

@MainActor
final class ConversationDurabilityTests: XCTestCase {
    func testSavingLongConversationPreservesEveryMessage() async throws {
        let id = "durability-test-\(UUID().uuidString)"
        var conversation = AgentConversation(id: id, source: .inApp)
        for index in 0..<40 {
            conversation.append(.user("Original question \(index)"))
            conversation.append(.assistant(String(repeating: "Detailed answer \(index). ", count: 15)))
        }
        await ConversationMemoryService.shared.saveConversation(conversation)
        let result = await ConversationMemoryService.shared.loadConversation(id: id)
        let loaded = try XCTUnwrap(result)
        XCTAssertEqual(loaded.messages.map(\.content), conversation.messages.map(\.content))
        await ConversationMemoryService.shared.saveConversation(AgentConversation(id: id, source: .inApp))
        let afterEmptySave = await ConversationMemoryService.shared.loadConversation(id: id)
        XCTAssertEqual(afterEmptySave?.messages.count, 80, "An uninitialized conversation is not a delete request")
        await ConversationMemoryService.shared.deleteConversation(id: id)
    }

    func testUnreadableAgentConversationIsPreservedOnSave() async throws {
        let id = "corrupt-conversation-\(UUID().uuidString)"
        var original = AgentConversation(id: id, source: .inApp)
        original.append(.user("Original question"))
        await ConversationMemoryService.shared.saveConversation(original)
        let record = try await AtomRepository.shared.fetchAgentConversationAtom(conversationId: id)
        let atom = try XCTUnwrap(record)
        try CosmoDatabase.shared.write { db in
            try db.execute(sql: "UPDATE atoms SET body = ? WHERE uuid = ?", arguments: ["unreadable saved turns", atom.uuid])
        }
        await ConversationMemoryService.shared.saveConversation(original)
        let retained = try CosmoDatabase.shared.read { db in
            try String.fetchOne(db, sql: "SELECT body FROM atoms WHERE uuid = ?", arguments: [atom.uuid])
        }
        XCTAssertEqual(retained, "unreadable saved turns")
        await ConversationMemoryService.shared.deleteConversation(id: id)
    }

    func testChatArchivesAreNeverClassifiedAsDisposableUIState() {
        let uuid = UUID().uuidString
        XCTAssertNil(UserDefaultsPruner.atomUUID(inKey: "cosmo.inlineAssistant.session.content:\(uuid)"))
        XCTAssertNil(UserDefaultsPruner.atomUUID(inKey: "cosmoWindow.messageArchive.cosmo-collaborator-outline-\(uuid)"))
    }

    func testUnreadableSessionCannotBeOverwrittenByFreshState() {
        var stored = Data("unreadable saved conversation".utf8)
        let original = stored
        let persistence = CosmoInlineAssistantSessionPersistence(
            loadData: { _ in stored }, saveData: { _, data in stored = data },
            deleteData: { _ in stored = Data() }
        )
        XCTAssertNil(persistence.load(surfaceID: "test"))
        let replacement = CosmoInlineAssistantPersistedSession(
            surfaceID: "test", paneMessages: [.init(role: .user, content: "New question")],
            proposals: [], selectedContextAtoms: [], selectedSkillID: nil, lastSubmissionRoute: nil
        )
        persistence.save(replacement)
        XCTAssertEqual(stored, original)
    }

    func testDatabaseArchiveMigratesLegacyAndKeepsPreviousCommit() throws {
        let key = "test-archive-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: key))
        defer {
            defaults.removePersistentDomain(forName: key)
            try? LocalDocumentArchive.delete(key: key, defaults: defaults)
        }
        let old = Data("original conversation".utf8)
        let new = Data("original conversation plus new turn".utf8)
        defaults.set(old, forKey: key)
        XCTAssertEqual(try LocalDocumentArchive.load(key: key, defaults: defaults), old)
        try LocalDocumentArchive.save(key: key, data: new)
        try LocalDocumentArchive.save(key: key, data: new)
        XCTAssertEqual(try LocalDocumentArchive.load(key: key, defaults: defaults), new)
        XCTAssertEqual(defaults.data(forKey: key), old)
        let previous = try CosmoDatabase.shared.read { db in
            try Data.fetchOne(db, sql: "SELECT previous_data FROM local_document_archives WHERE key = ?", arguments: [key])
        }
        XCTAssertEqual(previous, old, "Identical saves must not displace the recovery copy")
    }
}
