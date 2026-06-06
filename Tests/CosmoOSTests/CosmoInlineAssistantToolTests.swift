import XCTest
@testable import CosmoOS

@MainActor
final class CosmoInlineAssistantToolTests: XCTestCase {
    func testInlineAssistantToolsAreRegisteredForInAppAgentUse() {
        let tools = AgentToolRegistry.shared.toolsForIntent(
            .execute,
            source: .inApp,
            profileBundles: [],
            forcedBundles: [.workspaceEditing]
        )

        XCTAssertTrue(tools.contains { $0.name == "propose_workspace_edit" })
        XCTAssertTrue(tools.contains { $0.name == "answer_in_assistant_pane" })
    }

    func testProposeWorkspaceEditCallbackReceivesProposal() async throws {
        let executor = AgentToolExecutor.shared
        var received: CosmoAssistantProposal?
        executor.onWorkspaceEditProposal = { proposal in
            received = proposal
        }

        let result = try await executor.execute(
            toolName: "propose_workspace_edit",
            arguments: [
                "prompt": "replace rent",
                "surfaceID": "note:abc",
                "title": "Slide 4 numbers",
                "summary": "Updated rent number",
                "operations": [[
                    "kind": "textReplacement",
                    "targetID": "note:abc:body",
                    "anchorID": "line-1",
                    "originalText": "Rent: $4,556/mo",
                    "proposedText": "Rent: $5,000/mo",
                    "sourceHash": "hash-1",
                    "rationale": "Use requested rent."
                ]]
            ]
        )

        XCTAssertTrue(result.contains("\"success\":true"))
        XCTAssertEqual(received?.operations.count, 1)
        XCTAssertEqual(received?.operations.first?.proposedText, "Rent: $5,000/mo")
        executor.onWorkspaceEditProposal = nil
    }
}
