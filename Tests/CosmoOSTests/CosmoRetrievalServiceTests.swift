import XCTest
@testable import CosmoOS

@MainActor
final class CosmoRetrievalServiceTests: XCTestCase {
    func testIndexStoreCanRoundTripSourceAndChunksInMemory() async throws {
        let store = ContextIndexStore.inMemoryForTests()
        let source = ContextSource(
            id: "source-1",
            kind: .atom,
            title: "Walking Beam brief",
            atomUUID: "atom-1",
            bodyHash: "body-hash",
            metadataHash: "meta-hash",
            pinState: .pinned
        )
        let chunks = ContextChunker.chunk(
            sourceID: source.id,
            title: source.title,
            body: "This brief mentions locks on doors and intake sequencing.",
            bodyHash: source.bodyHash,
            maxCharacters: 200,
            overlapCharacters: 20
        )

        try await store.upsert(source: source, chunks: chunks)
        let loaded = try await store.source(id: "source-1")
        let loadedChunks = try await store.chunks(sourceIDs: ["source-1"])

        XCTAssertEqual(loaded?.title, "Walking Beam brief")
        XCTAssertEqual(loadedChunks.count, 1)
        XCTAssertTrue(loadedChunks[0].rawText.contains("locks on doors"))
    }

    func testKeywordSearchFindsExactPhraseInsidePinnedChunk() async throws {
        let store = ContextIndexStore.inMemoryForTests()
        let source = ContextSource(
            id: "source-1",
            kind: .atom,
            title: "Walking Beam brief",
            atomUUID: "atom-1",
            bodyHash: "hash",
            metadataHash: "meta",
            pinState: .pinned
        )
        let chunks = ContextChunker.chunk(
            sourceID: source.id,
            title: source.title,
            body: "Kitchen checklist.\n\nBedroom setup requires locks on doors before move-in.",
            bodyHash: "hash",
            maxCharacters: 120,
            overlapCharacters: 20
        )
        try await store.upsert(source: source, chunks: chunks)

        let results = try await store.keywordSearch(query: "\"locks on doors\"", sourceIDs: ["source-1"], limit: 5)

        XCTAssertEqual(results.first?.0.title, "Walking Beam brief")
        XCTAssertTrue(results.first?.1.rawText.contains("locks on doors") == true)
    }

    func testRetrievalSearchesPinnedSourcesBeforeAnsweringFactLookup() async throws {
        let store = ContextIndexStore.inMemoryForTests()
        let source = ContextSource(
            id: "source-1",
            kind: .atom,
            title: "Walking Beam brief",
            atomUUID: "atom-1",
            bodyHash: "hash",
            metadataHash: "meta",
            pinState: .pinned
        )
        let chunks = ContextChunker.chunk(
            sourceID: source.id,
            title: source.title,
            body: "The setup checklist says locks on doors are required before residents arrive.",
            bodyHash: "hash"
        )
        try await store.upsert(source: source, chunks: chunks)

        let service = CosmoRetrievalService(indexStore: store)
        let request = ContextRetrievalRequest(
            query: "does the brief mention locks on doors?",
            conversationID: "conversation-1",
            surface: .cosmoWindow,
            purpose: .factLookup,
            pinnedSourceIDs: ["source-1"],
            activeAtomUUID: nil,
            activeClientUUID: nil,
            maxChunks: 4,
            tokenBudget: 1_200
        )

        let results = try await service.retrieve(request)

        XCTAssertEqual(results.first?.source.title, "Walking Beam brief")
        XCTAssertTrue(results.first?.chunk.rawText.localizedCaseInsensitiveContains("locks on doors") == true)
        XCTAssertEqual(results.first?.matchType, "keyword")
    }

    func testAgentRegistryIncludesSharedRetrievalTool() {
        let names = AgentToolRegistry.shared.allTools.map(\.name)
        XCTAssertTrue(names.contains("retrieve_context"))
        XCTAssertTrue(names.contains("inspect_pinned_sources"))
    }

    func testContextualHeaderIncludesSourceTitleAndRole() async throws {
        let source = ContextSource(
            id: "source-1",
            kind: .content,
            title: "Walking Beam brief",
            atomUUID: "atom-1",
            bodyHash: "hash",
            metadataHash: "meta",
            pinState: .pinned
        )
        let header = ContextualChunkAnnotator.deterministicHeader(
            source: source,
            chunkOrdinal: 2,
            totalChunks: 5
        )

        XCTAssertTrue(header.contains("Walking Beam brief"))
        XCTAssertTrue(header.contains("content"))
        XCTAssertTrue(header.contains("chunk 3 of 5"))
    }

    func testFactLookupRerankerPrefersExactPhraseMatches() {
        let exact = CosmoRetrievalService.rerankScore(
            query: "locks on doors",
            candidateText: "The brief says locks on doors are required.",
            baseScore: 0.4,
            purpose: .factLookup
        )
        let fuzzy = CosmoRetrievalService.rerankScore(
            query: "locks on doors",
            candidateText: "The brief talks about resident safety.",
            baseScore: 0.9,
            purpose: .factLookup
        )

        XCTAssertGreaterThan(exact, fuzzy)
    }

    func testRetrievalStillWorksWithoutEmbeddingsForExactLookup() async throws {
        let store = ContextIndexStore.inMemoryForTests()
        let source = ContextSource(
            id: "source-1",
            kind: .atom,
            title: "Brief",
            atomUUID: "atom-1",
            bodyHash: "hash",
            metadataHash: "meta",
            pinState: .pinned
        )
        let chunks = ContextChunker.chunk(
            sourceID: source.id,
            title: source.title,
            body: "Locks on doors are required.",
            bodyHash: "hash"
        )
        try await store.upsert(source: source, chunks: chunks)

        let service = CosmoRetrievalService(indexStore: store)
        let request = ContextRetrievalRequest(
            query: "locks on doors",
            conversationID: "conversation-1",
            surface: .cosmoWindow,
            purpose: .factLookup,
            pinnedSourceIDs: ["source-1"],
            activeAtomUUID: nil,
            activeClientUUID: nil,
            maxChunks: 3,
            tokenBudget: 1_200
        )

        let results = try await service.retrieve(request)

        XCTAssertFalse(results.isEmpty)
        XCTAssertEqual(results.first?.matchType, "keyword")
    }
}
