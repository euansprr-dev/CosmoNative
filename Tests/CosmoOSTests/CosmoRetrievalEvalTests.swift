import XCTest
@testable import CosmoOS

final class CosmoRetrievalEvalTests: XCTestCase {
    func testFactLookupEvalFixturesRetrieveExpectedEvidence() async throws {
        let fixtures = try loadFixtures()

        for fixture in fixtures {
            let store = ContextIndexStore.inMemoryForTests()
            let source = ContextSource(
                id: "fixture:\(fixture.name)",
                kind: .content,
                title: fixture.title,
                atomUUID: fixture.name,
                bodyHash: fixture.name,
                metadataHash: "fixture",
                pinState: .pinned
            )
            let chunks = ContextChunker.chunk(
                sourceID: source.id,
                title: source.title,
                body: fixture.body,
                bodyHash: source.bodyHash,
                maxCharacters: 180,
                overlapCharacters: 40
            )
            try await store.upsert(source: source, chunks: chunks)

            let service = CosmoRetrievalService(indexStore: store)
            let request = ContextRetrievalRequest(
                query: fixture.query,
                conversationID: "eval-\(fixture.name)",
                surface: .cosmoWindow,
                purpose: .factLookup,
                pinnedSourceIDs: [source.id],
                activeAtomUUID: source.atomUUID,
                activeClientUUID: nil,
                maxChunks: 3,
                tokenBudget: 1_500
            )

            let results = try await service.retrieve(request)
            let combined = results.map { $0.chunk.rawText }.joined(separator: "\n").lowercased()

            XCTAssertTrue(
                combined.contains(fixture.expectedPhrase.lowercased()),
                "Fixture \(fixture.name) did not retrieve expected phrase: \(fixture.expectedPhrase)"
            )
        }
    }

    private func loadFixtures() throws -> [Fixture] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/context-retrieval-fixtures.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([Fixture].self, from: data)
    }

    private struct Fixture: Decodable {
        let name: String
        let title: String
        let query: String
        let body: String
        let expectedPhrase: String
    }
}
