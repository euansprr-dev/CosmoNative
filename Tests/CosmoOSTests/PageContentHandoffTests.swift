import XCTest
import GRDB
@testable import CosmoOS

@MainActor
final class PageContentHandoffTests: XCTestCase {
    private var created = Set<String>()
    override func tearDown() async throws {
        for uuid in created { try? await AtomRepository.shared.hardDelete(uuid: uuid, confirmed: true) }
        try await super.tearDown()
    }
    private func save(_ atom: Atom) async throws -> Atom {
        let saved = try await AtomRepository.shared.create(atom); created.insert(saved.uuid); return saved
    }
    private func create(_ source: Atom, client: String? = nil, operation: String = UUID().uuidString) async throws -> Atom {
        created.insert(operation)
        return try await PageContentHandoffService.create(sourceUUID: source.uuid, title: "A useful post", angle: "A different angle",
            clientUUID: client, operationID: operation)
    }
    func testHandoffPreservesOriginalRichPageAndReferencesClient() async throws {
        var original = Atom.new(type: .note, title: "A chapter", body: "Original writing",
            metadata: "{\"future\":true,\"attachmentUUIDs\":[\"image\"]}")
        original = try original.replacingSpaceComposition(.init(kind: .page, parentUUID: "book", sortOrder: 2))
        let source = try await save(original)
        let client = try await save(Atom.new(type: .clientProfile, title: "Acme"))
        let idea = try await create(source, client: client.uuid)
        let fresh = try await AtomRepository.shared.fetch(uuid: source.uuid)
        XCTAssertEqual(fresh, source)
        XCTAssertEqual(idea.type, .idea)
        XCTAssertEqual(idea.ideaMetadata?.clientUUID, client.uuid)
        XCTAssertTrue(idea.linksList.contains { $0.type == "source" && $0.uuid == source.uuid })
        XCTAssertNil(idea.spaceComposition)
        XCTAssertNil(idea.metadataDict?["attachmentUUIDs"])
        let placements = try await CosmoDatabase.shared.asyncRead { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM canvas_blocks WHERE entity_uuid = ?", arguments: [idea.uuid])
        }
        XCTAssertEqual(placements, 0, "Production intent must not create another canvas placement")
    }
    func testRetryReturnsSameIdeaAndPreservesSubsequentEditing() async throws {
        let source = try await save(Atom.new(type: .note, title: "A thought"))
        let operation = UUID().uuidString
        let first = try await create(source, operation: operation)
        let editor = IdeaFocusModeViewModel(atom: first)
        await editor.loadMentionedAtoms()
        editor.editableTitle = "Edited after creation"
        await editor.save()
        let edited = try await AtomRepository.shared.fetch(uuid: first.uuid)
        let retried = try await create(source, operation: operation)
        XCTAssertEqual(retried, edited)
        XCTAssertEqual(retried.ideaMetadata?.pageContentSourceUUID, source.uuid)
    }
    func testInvalidClientOrSourceCannotLeaveAnIdeaBehind() async throws {
        let source = try await save(Atom.new(type: .note, title: "A thought"))
        let operation = UUID().uuidString
        do { _ = try await create(source, client: "missing-client", operation: operation); XCTFail("Missing client must fail") } catch {}
        let missing = try await AtomRepository.shared.fetch(uuid: operation)
        XCTAssertNil(missing)
        let group = try await save(Atom.new(type: .note, title: "A group").replacingSpaceComposition(.init(kind: .group)))
        do { _ = try await create(group); XCTFail("A mixed group is not authored writing") } catch {}
    }
}
