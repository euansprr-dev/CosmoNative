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

    func testInlineAssistantResponseModeKeepsWritingToolsAvailableForPaneAnswers() {
        let tools = AgentToolRegistry.shared.toolsForIntent(
            .draft,
            source: .inApp,
            profileBundles: [],
            forcedBundles: [.workspaceEditing, .writing, .clientProfiles, .swipes]
        )

        let directTools = AgentResponseMode.directChat.filteredTools(tools)
        let inlineTools = AgentResponseMode.inlineAssistant.filteredTools(tools)

        XCTAssertFalse(directTools.contains { $0.name == "generate_outline" })
        XCTAssertTrue(inlineTools.contains { $0.name == "generate_outline" })
        XCTAssertTrue(inlineTools.contains { $0.name == "get_client_profile" })
        XCTAssertTrue(inlineTools.contains { $0.name == "answer_in_assistant_pane" })
    }

    func testClientFactLookupBundleDoesNotExposeFullProfileTool() {
        let tools = AgentToolRegistry.shared.toolsForIntent(
            .execute,
            source: .inApp,
            profileBundles: [],
            forcedBundles: [.clientFactLookup]
        )

        XCTAssertTrue(tools.contains { $0.name == "lookup_client_facts" })
        XCTAssertFalse(tools.contains { $0.name == "get_client_profile" })
    }

    func testClientFactLookupSnippetsAreRelevantAndCapped() {
        let meta = ClientProfileMetadata(
            clientId: "josh",
            clientName: "Josh",
            platforms: [.instagram],
            brandStory: "Josh helps service members buy property.",
            topPerformingTranscripts: [
                String(repeating: "DSCR duplex mortgage was $5,300 and rent was $15,000. ", count: 20)
            ],
            documents: [
                ProfileDocument(
                    category: .story,
                    title: "San Diego Duplex",
                    content: String(repeating: "The DSCR loan detail and sober living rent detail are here. ", count: 20)
                ),
                ProfileDocument(
                    category: .voiceGuide,
                    title: "Voice",
                    content: String(repeating: "Plainspoken tactical tone. ", count: 20)
                )
            ]
        )

        let snippets = CosmoClientFactLookup.snippets(
            meta: meta,
            query: "DSCR duplex mortgage rent",
            maxSnippets: 3,
            maxSnippetLength: 180
        )

        XCTAssertLessThanOrEqual(snippets.count, 3)
        XCTAssertTrue(snippets.contains { $0.contains("DSCR") || $0.contains("duplex") })
        XCTAssertTrue(snippets.allSatisfy { $0.count <= 180 })
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

    func testOutlineBodyInsertionStripsDuplicateSlideHeaderFromInsertedText() async throws {
        let executor = AgentToolExecutor.shared
        var received: CosmoAssistantProposal?
        executor.onWorkspaceEditProposal = { proposal in
            received = proposal
        }

        let result = try await executor.execute(
            toolName: "propose_workspace_edit",
            arguments: [
                "prompt": "Please take the outline of this post and put it in the actual body, in between each slide.",
                "surfaceID": "content:abc",
                "title": "Outline into body",
                "summary": "Inserted outline points into slide bodies.",
                "operations": [[
                    "kind": "textInsertion",
                    "targetID": "content:abc:draft",
                    "anchorID": "slide-13",
                    "originalText": "SLIDE 13",
                    "proposedText": "SLIDE 13\nThis allows me to sell the right to buy the home at that price...",
                    "sourceHash": "hash-1",
                    "rationale": "Insert thirteenth outline point after Slide 13 header"
                ]]
            ]
        )

        XCTAssertTrue(result.contains("\"success\":true"))
        XCTAssertEqual(
            received?.operations.first?.proposedText,
            "This allows me to sell the right to buy the home at that price..."
        )
        executor.onWorkspaceEditProposal = nil
    }
}
