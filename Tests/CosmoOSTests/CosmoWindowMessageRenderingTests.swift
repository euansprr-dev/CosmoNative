import XCTest
import CoreGraphics
@testable import CosmoOS

final class CosmoWindowMessageRenderingTests: XCTestCase {
    func testDefaultAgentPromptIncludesGeneralCollaboratorBehavior() {
        let prompt = CosmoDefaultAgentPrompt.text

        XCTAssertTrue(prompt.contains("general collaborator for knowledge work"))
        XCTAssertTrue(prompt.contains("brainstorm with concrete options"))
        XCTAssertTrue(prompt.contains("retrieve information before answering"))
    }

    func testDefaultAgentPromptIncludesCostDiscipline() {
        let prompt = CosmoDefaultAgentPrompt.text

        XCTAssertTrue(prompt.contains("Cost discipline"))
        XCTAssertTrue(prompt.contains("Use cheaper models"))
        XCTAssertTrue(prompt.contains("Escalate only when"))
    }

    func testTimelineTextSelectionIsDisabledToAvoidSelectionOverlayLayoutLoop() {
        XCTAssertFalse(CosmoWindowMessageRenderingPolicy.allowsTimelineTextSelection)
    }

    func testMentionExpansionIncludesFullBodyByDefault() {
        let sentinel = "FINAL REVENUE: $14,400 revenue / $3,800 expenses / $10,600 cash flow"
        let longBody = String(repeating: "Deal context ", count: 230) + sentinel
        let atom = Atom.new(type: .content, title: "Walking Beam Shared Living Arbitrage Deal", body: longBody)

        let expanded = MentionContextHelper.expandMentionsInline(
            text: "Use @Walking Beam Shared Living Arbitrage Deal as the content brief.",
            atoms: [atom]
        )

        XCTAssertTrue(expanded.contains(sentinel))
    }

    func testWritingEngineMentionExpansionIncludesFullBodyByDefault() {
        let sentinel = "FINAL BLUEPRINT BEAT: reveal expected versus actual cashflow"
        let longBody = String(repeating: "Blueprint context ", count: 260) + sentinel
        let atom = Atom.new(type: .content, title: "This is why I do Sober Living", body: longBody)

        let expanded = MentionContextHelper.expandMentionsForWritingEngine(
            text: "Mirror @This is why I do Sober Living for the draft.",
            atoms: [atom]
        )

        XCTAssertTrue(expanded.contains(sentinel))
    }

    func testMentionExpansionIncludesReferencedImagesFromImageAtoms() throws {
        let metadata = ImageMetadata(
            imagePath: "/tmp/cosmo/josh-deal-front.png",
            originalFilename: "josh-deal-front.png",
            width: 1280,
            height: 720,
            fileSize: 4096
        )
        let metadataJSON = try XCTUnwrap(String(data: JSONEncoder().encode(metadata), encoding: .utf8))
        let atom = Atom.new(type: .image, title: "Josh Deal Image", body: "", metadata: metadataJSON)

        let expanded = MentionContextHelper.expandMentionsInline(
            text: "Use @Josh Deal Image as visual context.",
            atoms: [atom]
        )

        XCTAssertTrue(expanded.contains("Referenced Images:"))
        XCTAssertTrue(expanded.contains("/tmp/cosmo/josh-deal-front.png"))
        XCTAssertTrue(expanded.contains("1280x720"))
    }

    func testMentionExpansionIncludesMultipleImagePathsFromStructuredBlocks() throws {
        let structured = """
        {
          "blocks": [
            { "kind": "image", "inlines": [{ "image": { "path": "images/kitchen.png", "width": 640, "height": 480 } }] },
            { "kind": "image", "inlines": [{ "image": { "path": "images/bedroom.jpg", "width": 640, "height": 480 } }] }
          ]
        }
        """
        let atom = Atom.new(type: .note, title: "Deal Photos", body: "Photo notes", structured: structured)

        let expanded = MentionContextHelper.buildMentionBlock(atoms: [atom])

        XCTAssertTrue(expanded.contains("images/kitchen.png"))
        XCTAssertTrue(expanded.contains("images/bedroom.jpg"))
    }

    func testMentionParserFindsQueryAtCursorInMiddleOfPrompt() {
        let text = "Write this for @Josh before Friday"
        let cursor = (text as NSString).range(of: "@Josh").upperBound

        let activeMention = MentionComposerMentionParser.activeMention(
            in: text,
            selectedRange: NSRange(location: cursor, length: 0)
        )

        XCTAssertEqual(activeMention?.query, "Josh")
        XCTAssertEqual(activeMention?.range, (text as NSString).range(of: "@Josh"))
    }

    func testMentionParserReplacementPreservesTrailingPromptText() {
        let text = "Write this for @Jo before Friday"
        let cursor = (text as NSString).range(of: "@Jo").upperBound

        let replacement = MentionComposerMentionParser.replacingActiveMention(
            in: text,
            selectedRange: NSRange(location: cursor, length: 0),
            title: "Josh"
        )

        XCTAssertEqual(replacement.text, "Write this for @Josh before Friday")
        XCTAssertEqual(replacement.selection.location, (replacement.text as NSString).range(of: "@Josh ").upperBound)
    }

    func testMentionParserClosesAfterWhitespace() {
        let text = "Write this for @Josh before Friday"
        let cursor = (text as NSString).range(of: "@Josh ").upperBound

        let activeMention = MentionComposerMentionParser.activeMention(
            in: text,
            selectedRange: NSRange(location: cursor, length: 0)
        )

        XCTAssertNil(activeMention)
    }

    func testInlineMentionDraftPolicyHandlesReferencePrompt() {
        let prompt = """
        I want to write a reel for Josh based on @Walking Beam Shared Living Arbitrage Deal and use @This is why I do Sober Living as a blueprint. Give me every detail of the deal I'll need so I can use your output as reference while writing, then also give me a 1st draft.
        """

        XCTAssertTrue(
            CosmoWindowViewModel.shouldUseInlineMentionDraftResponse(
                text: prompt,
                hasMentionedAtoms: true
            )
        )
    }

    func testInlineMentionDraftPolicyRequiresMentionContext() {
        let prompt = "I want to write a reel for Josh. Give me a first draft."

        XCTAssertFalse(
            CosmoWindowViewModel.shouldUseInlineMentionDraftResponse(
                text: prompt,
                hasMentionedAtoms: false
            )
        )
    }

    func testNoReplyComplaintIsHandledAsRecoveryMessage() {
        XCTAssertTrue(CosmoWindowViewModel.isNoReplyComplaint("You didn't reply"))
    }

    func testWritingModeRequiresWritingModeAgentSelection() {
        XCTAssertFalse(CosmoWindowViewModel.allowsWritingModeAgentRoute(selectedAgentProfileID: nil))
        XCTAssertFalse(CosmoWindowViewModel.allowsWritingModeAgentRoute(selectedAgentProfileID: "idea-collaborator"))
        XCTAssertTrue(CosmoWindowViewModel.allowsWritingModeAgentRoute(selectedAgentProfileID: "writing-editor"))
    }

    func testInlineMentionDraftResponseFiltersBroadSearchAndWritingTools() {
        let tools = [
            LLMToolDefinition(name: "search_swipes", description: "", parametersSchema: [:]),
            LLMToolDefinition(name: "search_ideas", description: "", parametersSchema: [:]),
            LLMToolDefinition(name: "generate_draft", description: "", parametersSchema: [:]),
            LLMToolDefinition(name: "get_client_profile", description: "", parametersSchema: [:])
        ]

        let filteredNames = AgentResponseMode.inlineMentionDraftReference
            .filteredTools(tools)
            .map(\.name)

        XCTAssertFalse(filteredNames.contains("search_swipes"))
        XCTAssertFalse(filteredNames.contains("search_ideas"))
        XCTAssertFalse(filteredNames.contains("generate_draft"))
        XCTAssertTrue(filteredNames.contains("get_client_profile"))
    }

    func testDirectChatModeFiltersWritingEngineToolsOnly() {
        let tools = [
            LLMToolDefinition(name: "generate_draft", description: "", parametersSchema: [:]),
            LLMToolDefinition(name: "revise_draft", description: "", parametersSchema: [:]),
            LLMToolDefinition(name: "search_ideas", description: "", parametersSchema: [:]),
            LLMToolDefinition(name: "get_client_profile", description: "", parametersSchema: [:])
        ]

        let filteredNames = AgentResponseMode.directChat
            .filteredTools(tools)
            .map(\.name)

        XCTAssertFalse(filteredNames.contains("generate_draft"))
        XCTAssertFalse(filteredNames.contains("revise_draft"))
        XCTAssertTrue(filteredNames.contains("search_ideas"))
        XCTAssertTrue(filteredNames.contains("get_client_profile"))
    }

    func testInlineChatModesRetryWithoutToolsAfterInvalidProviderResponse() {
        let tools = [
            LLMToolDefinition(name: "get_client_profile", description: "", parametersSchema: [:])
        ]

        XCTAssertTrue(
            AgentResponseMode.inlineMentionDraftReference
                .shouldRetryWithoutTools(after: LLMProviderError.invalidResponse, tools: tools)
        )
        XCTAssertTrue(
            AgentResponseMode.directChat
                .shouldRetryWithoutTools(after: LLMProviderError.invalidResponse, tools: tools)
        )
        XCTAssertFalse(
            AgentResponseMode.automatic
                .shouldRetryWithoutTools(after: LLMProviderError.invalidResponse, tools: tools)
        )
        XCTAssertFalse(
            AgentResponseMode.inlineMentionDraftReference
                .shouldRetryWithoutTools(after: LLMProviderError.apiError("OpenAI 400"), tools: tools)
        )
        XCTAssertFalse(
            AgentResponseMode.inlineMentionDraftReference
                .shouldRetryWithoutTools(after: LLMProviderError.invalidResponse, tools: [])
        )
    }

    func testInlineChatModesRetryWithoutToolsAfterEmptyProviderResponse() {
        let tools = [
            LLMToolDefinition(name: "get_client_profile", description: "", parametersSchema: [:])
        ]

        XCTAssertTrue(
            AgentResponseMode.inlineMentionDraftReference
                .shouldRetryWithoutToolsAfterEmptyResponse(tools: tools)
        )
        XCTAssertTrue(
            AgentResponseMode.directChat
                .shouldRetryWithoutToolsAfterEmptyResponse(tools: tools)
        )
        XCTAssertFalse(
            AgentResponseMode.automatic
                .shouldRetryWithoutToolsAfterEmptyResponse(tools: tools)
        )
        XCTAssertFalse(
            AgentResponseMode.inlineMentionDraftReference
                .shouldRetryWithoutToolsAfterEmptyResponse(tools: [])
        )
    }

    func testCollaboratorPaneKeepsReadableTranscriptWhenActionsArePresent() {
        let availableHeight: CGFloat = 520
        let transcriptHeight = CosmoWindowLayoutPolicy.readableTranscriptHeight(
            availableHeight: availableHeight,
            headerHeight: 132,
            composerHeight: 160,
            dividerHeight: 2
        )

        XCTAssertGreaterThanOrEqual(transcriptHeight, CosmoWindowMetrics.minimumMessageStageHeight)
    }

    func testComposerHeightNeverCollapsesBelowSingleReadableLine() {
        let height = MentionComposerSizingPolicy.clampedHeight(forContentHeight: 0)

        XCTAssertEqual(height, MentionComposerSizingPolicy.minimumHeight)
    }
}
