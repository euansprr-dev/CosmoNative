import XCTest
@testable import CosmoOS

@MainActor
final class CosmoMemoryServiceTests: XCTestCase {
    func testMemoryServiceSeparatesCoreAndWorkingMemory() async throws {
        let service = CosmoMemoryService.inMemoryForTests()
        try await service.upsertCoreMemory("prefers concise direct answers", key: "style.directness")
        try await service.upsertWorkingMemory("conversation-1", value: "Current task: Walking Beam brief review")

        let core = try await service.coreMemory()
        let working = try await service.workingMemory(conversationID: "conversation-1")

        XCTAssertEqual(core, ["prefers concise direct answers"])
        XCTAssertEqual(working, ["Current task: Walking Beam brief review"])
    }

    func testAgentRegistryIncludesSharedMemoryTools() {
        let names = AgentToolRegistry.shared.allTools.map(\.name)
        XCTAssertTrue(names.contains("remember_context"))
        XCTAssertTrue(names.contains("search_memory"))
    }

    // MARK: - Recall stays semantic-only (no keyword fallback by choice)

    func testRecallReturnsNothingWithoutEmbeddingsAndReportsWhy() async throws {
        // Only meaningful (and hermetic) when embeddings are unconfigured:
        // with a live key this path would embed over the network instead.
        try XCTSkipIf(APIKeys.hasEmbeddings, "embeddings key configured — offline path not reachable")

        // Deliberate: no keyword fallback (lower-quality matches would drag
        // noise into prompts). Recall goes quiet — and the health signal must
        // name the missing key so the UI can tell the user exactly what to do.
        let service = CosmoMemoryService.inMemoryForTests()
        await service.addArchivalMemoryIfNovel("Josh's audience is first-time landlords buying rental property")

        let recalled = await service.recallArchivalMemory(
            query: "rewrite the rental property post for Josh's landlord audience"
        )
        XCTAssertEqual(recalled, [])
        XCTAssertNotNil(EmbeddingHealth.shared.userFacingIssue)
        XCTAssertTrue(EmbeddingHealth.shared.userFacingIssue?.contains("embeddings API key") == true)
    }
}
