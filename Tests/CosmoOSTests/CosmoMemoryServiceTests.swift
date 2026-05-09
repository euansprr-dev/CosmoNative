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
}
