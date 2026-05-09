import XCTest
@testable import CosmoOS

final class CosmoContextPackAssemblerTests: XCTestCase {
    func testContextPackIncludesEvidenceBeforeMemoryForFactLookup() {
        let request = ContextRetrievalRequest(
            query: "does it mention locks?",
            conversationID: "conversation-1",
            surface: .cosmoWindow,
            purpose: .factLookup,
            pinnedSourceIDs: ["source-1"],
            activeAtomUUID: nil,
            activeClientUUID: nil,
            maxChunks: 3,
            tokenBudget: 1_000
        )
        let source = ContextSource(
            id: "source-1",
            kind: .atom,
            title: "Walking Beam brief",
            atomUUID: "atom-1",
            bodyHash: "hash",
            metadataHash: "meta",
            pinState: .pinned
        )
        let chunk = ContextChunk(
            id: "chunk-1",
            sourceID: "source-1",
            ordinal: 0,
            rawText: "Locks on doors are required.",
            contextualHeader: "Source: Walking Beam brief.",
            anchor: "chunk-1",
            tokenCount: 8,
            bodyHash: "hash"
        )
        let result = ContextRetrievalResult(chunk: chunk, source: source, score: 1.0, matchType: "keyword")

        let pack = ContextPackAssembler.assemble(
            request: request,
            retrievalResults: [result],
            coreMemory: ["User likes direct answers."],
            workingMemory: ["Current task: review brief."],
            recallMemory: []
        )

        let prompt = pack.promptBlock
        XCTAssertLessThan(
            prompt.range(of: "Locks on doors are required.")!.lowerBound,
            prompt.range(of: "User likes direct answers.")!.lowerBound
        )
        XCTAssertTrue(prompt.contains("Walking Beam brief"))
    }
}
