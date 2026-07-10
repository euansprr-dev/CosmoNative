import XCTest
@testable import CosmoOS

@MainActor
final class CosmoInlineSessionLedgerTests: XCTestCase {
    private func proposal(
        title: String = "Renumber + bold headers",
        summary: String = "Renumbered slides 3-9 and bolded every header.",
        operationCount: Int = 3
    ) -> CosmoAssistantProposal {
        CosmoAssistantProposal(
            prompt: "renumber and bold",
            surfaceID: "content:deck-1",
            title: title,
            summary: summary,
            operations: (0..<operationCount).map { index in
                CosmoAssistantProposalOperation(
                    kind: .textReplacement,
                    targetID: "content:deck-1:draft",
                    anchorID: nil,
                    originalText: "SLIDE \(index + 3)",
                    proposedText: "SLIDE \(index + 4)",
                    sourceHash: "hash",
                    rationale: "bump"
                )
            }
        )
    }

    // MARK: - Record building

    func testRecordCapturesProposalSubstance() {
        let record = CosmoInlineSessionLedger.record(
            userAsk: "renumber all the slide headers and bold them",
            route: .action,
            skillID: "inlineEdit",
            newProposals: [proposal()],
            newAnswerText: nil,
            errorText: nil
        )

        XCTAssertEqual(record.proposalTitle, "Renumber + bold headers")
        XCTAssertEqual(record.operationCount, 3)
        XCTAssertNil(record.answerDigest)
        XCTAssertNil(record.errorDigest)
        XCTAssertTrue(record.hasPendingOperations)
    }

    func testRecordCapturesAnswerDigestAndErrorOnlyWithoutDeliverable() {
        let answered = CosmoInlineSessionLedger.record(
            userAsk: "what's the strongest hook?",
            route: .answer,
            skillID: nil,
            newProposals: [],
            newAnswerText: "The duplex number is the stopper — lead with it.",
            errorText: "some stale error"
        )
        XCTAssertEqual(answered.answerDigest, "The duplex number is the stopper — lead with it.")
        XCTAssertNil(answered.errorDigest, "errors are only recorded when nothing was delivered")

        let failed = CosmoInlineSessionLedger.record(
            userAsk: "do the thing",
            route: .action,
            skillID: nil,
            newProposals: [],
            newAnswerText: nil,
            errorText: "network down"
        )
        XCTAssertEqual(failed.errorDigest, "network down")
    }

    // MARK: - Review write-back

    func testReviewStateWriteBackCountsAcceptsAndRejects() {
        var reviewed = proposal()
        reviewed.operations[0].status = .applied
        reviewed.operations[1].status = .rejected

        let record = CosmoInlineSessionLedger.record(
            userAsk: "renumber",
            route: .action,
            skillID: nil,
            newProposals: [reviewed],
            newAnswerText: nil,
            errorText: nil
        )
        let updated = CosmoInlineSessionLedger.updated([record], withReviewStateOf: reviewed)

        XCTAssertEqual(updated[0].acceptedOperationCount, 1)
        XCTAssertEqual(updated[0].rejectedOperationCount, 1)
        XCTAssertTrue(updated[0].hasPendingOperations)
    }

    func testReviewStateWriteBackIgnoresUnknownProposal() {
        let record = CosmoInlineSessionLedger.record(
            userAsk: "renumber",
            route: .action,
            skillID: nil,
            newProposals: [proposal()],
            newAnswerText: nil,
            errorText: nil
        )
        let unrelated = proposal(title: "Other")
        let updated = CosmoInlineSessionLedger.updated([record], withReviewStateOf: unrelated)
        XCTAssertEqual(updated, [record])
    }

    // MARK: - Prompt rendering

    func testPromptBlockRendersTurnsWithReviewState() {
        var reviewed = proposal()
        reviewed.operations = reviewed.operations.map { $0.marked(.applied) }
        var record = CosmoInlineSessionLedger.record(
            userAsk: "renumber all the slide headers and bold them",
            route: .action,
            skillID: nil,
            newProposals: [reviewed],
            newAnswerText: nil,
            errorText: nil
        )
        record = CosmoInlineSessionLedger.updated([record], withReviewStateOf: reviewed)[0]

        let answer = CosmoInlineSessionLedger.record(
            userAsk: "why slide 4?",
            route: .answer,
            skillID: nil,
            newProposals: [],
            newAnswerText: "Slide 4 carries the proof — the rent number.",
            errorText: nil
        )

        let block = CosmoInlineSessionLedger.promptBlock(records: [record, answer])

        XCTAssertNotNil(block)
        XCTAssertTrue(block!.contains("## Session So Far"))
        XCTAssertTrue(block!.contains("renumber all the slide headers"))
        XCTAssertTrue(block!.contains("user accepted 3"))
        XCTAssertTrue(block!.contains("answered: Slide 4 carries the proof"))
        XCTAssertNil(CosmoInlineSessionLedger.promptBlock(records: []))
    }

    func testPromptBlockCapsRenderedRecordsAndNotesOmissions() {
        let records = (1...30).map { index in
            CosmoInlineSessionLedger.record(
                userAsk: "ask number \(index)",
                route: .answer,
                skillID: nil,
                newProposals: [],
                newAnswerText: "answer \(index)",
                errorText: nil
            )
        }

        let block = CosmoInlineSessionLedger.promptBlock(records: records)!
        XCTAssertTrue(block.contains("(10 earlier turns omitted)"))
        XCTAssertFalse(block.contains("ask number 10"))
        XCTAssertTrue(block.contains("ask number 11"))
        XCTAssertTrue(block.contains("ask number 30"))
    }

    // MARK: - Inline history window

    func testInlineWindowAlwaysKeepsThePreviousUserAsk() {
        // Turn 1: user → assistant(toolCalls) → tool → assistant receipt.
        // Turn 2: same shape. Turn 3: fresh user ask.
        // The OLD 4-message chop would have dropped turn 2's user ask.
        var messages: [AgentMessage] = []
        for turn in 1...2 {
            messages.append(.user("ask \(turn)"))
            messages.append(.assistant("", toolCalls: [AgentToolCall(
                id: "call-\(turn)",
                name: "propose_workspace_edit",
                argumentsJSON: #"{"title":"Edit \#(turn)","summary":"Did thing \#(turn)","operations":[{"kind":"textReplacement"}]}"#
            )]))
            messages.append(.tool(callId: "call-\(turn)", content: #"{"success":true}"#))
            messages.append(.assistant("Staged \"Edit \(turn)\" — awaiting user review."))
        }
        messages.append(.user("ask 3"))

        let window = CosmoAgentService.buildInlineHistoryWindow(
            messages,
            modelTier: .sonnet5,
            reservedOutputTokens: 8192,
            reservedSystemTokens: 1000
        )

        let userAsks = window.filter { $0.role == .user }.map(\.content)
        XCTAssertTrue(userAsks.contains("ask 1"))
        XCTAssertTrue(userAsks.contains("ask 2"))
        XCTAssertTrue(userAsks.contains("ask 3"))

        // Turn 2 onward is verbatim: its tool call and tool result survive.
        XCTAssertTrue(window.contains { $0.role == .tool && $0.toolCallId == "call-2" })
        // Turn 1 is digested: no raw tool result, but the substance remains.
        XCTAssertFalse(window.contains { $0.role == .tool && $0.toolCallId == "call-1" })
        XCTAssertTrue(window.contains { $0.role == .assistant && $0.content.contains("Edit 1") })
    }

    func testInlineWindowDigestsOlderToolCallsWithSubstance() {
        var messages: [AgentMessage] = [
            .user("first ask"),
            .assistant("", toolCalls: [AgentToolCall(
                id: "call-a",
                name: "answer_in_assistant_pane",
                argumentsJSON: #"{"title":"Hook analysis","answer":"The duplex number is the stopper."}"#
            )]),
            .tool(callId: "call-a", content: #"{"success":true}"#),
            .assistant("Answered: The duplex number is the stopper.")
        ]
        messages.append(.user("second ask"))
        messages.append(.assistant("plain reply"))
        messages.append(.user("third ask"))

        let window = CosmoAgentService.buildInlineHistoryWindow(
            messages,
            modelTier: .sonnet5,
            reservedOutputTokens: 8192,
            reservedSystemTokens: 1000
        )

        let digest = window.first {
            $0.role == .assistant && $0.content.contains("answer_in_assistant_pane")
        }
        XCTAssertNotNil(digest)
        XCTAssertTrue(digest!.content.contains("The duplex number is the stopper."))
        XCTAssertNil(digest!.toolCalls)
    }

    // MARK: - Delivery receipt substance

    func testInlineDeliveryReceiptCarriesProposalAndAnswerSubstance() {
        let receipt = CosmoAgentService.inlineDeliveryReceipt(for: [
            AgentToolCall(
                id: "1",
                name: "propose_workspace_edit",
                argumentsJSON: #"{"title":"Bold headers","summary":"Bolded all 26 headers.","operations":[{},{},{}]}"#
            ),
            AgentToolCall(
                id: "2",
                name: "answer_in_assistant_pane",
                argumentsJSON: #"{"answer":"Numbering runs clean 1-26 now."}"#
            )
        ])

        XCTAssertTrue(receipt.contains("Staged \"Bold headers\" (3 operations)"))
        XCTAssertTrue(receipt.contains("Bolded all 26 headers."))
        XCTAssertTrue(receipt.contains("Answered: Numbering runs clean 1-26 now."))
    }

    func testToolResultSucceededDistinguishesDeliveryFromRejection() {
        // A validation-rejected proposal is NOT a deliverable: the loop must
        // continue so the model reads the error and stages a corrected one —
        // ending the run here once showed "Staged … awaiting review" with
        // nothing staged.
        XCTAssertFalse(CosmoAgentService.toolResultSucceeded(
            #"{"error": "The proposal was NOT staged — fix these and call propose_workspace_edit again"}"#
        ))
        XCTAssertFalse(CosmoAgentService.toolResultSucceeded(#"{"success": false}"#))
        XCTAssertTrue(CosmoAgentService.toolResultSucceeded(
            #"{"success": true, "proposalId": "abc", "operationCount": 1}"#
        ))
        XCTAssertTrue(CosmoAgentService.toolResultSucceeded("plain engine string result"))
    }

    func testInlineDeliveryReceiptFallsBackForUnknownCalls() {
        let receipt = CosmoAgentService.inlineDeliveryReceipt(for: [
            AgentToolCall(id: "1", name: "recall", argumentsJSON: #"{"query":"x"}"#)
        ])
        XCTAssertEqual(receipt, "Delivered to the workspace for review.")
    }

    // MARK: - Token estimate includes tool-call arguments

    func testEstimatedTokensCountToolCallArguments() {
        let bigArgs = String(repeating: "x", count: 8000)
        var conversation = AgentConversation(id: "c", source: .inApp)
        conversation.append(.assistant("", toolCalls: [
            AgentToolCall(id: "1", name: "propose_workspace_edit", argumentsJSON: bigArgs)
        ]))
        XCTAssertGreaterThan(conversation.estimatedTokenCount, 1500)
    }

    // MARK: - Conversation folding

    func testFoldingOldMessagesKeepsRecentRunsAndSummarizesTheRest() {
        var conversation = AgentConversation(id: "cosmo-inline-assistant:content:deck", source: .inApp)
        for turn in 1...40 {
            conversation.append(.user("ask \(turn)"))
            conversation.append(.assistant("receipt \(turn)"))
        }

        let folded = ConversationMemoryService.foldingOldMessagesIntoSummary(conversation)

        XCTAssertLessThanOrEqual(folded.messages.count, 41)
        XCTAssertEqual(folded.messages.first?.role, .user)
        XCTAssertNotNil(folded.summary)
        XCTAssertTrue(folded.summary!.contains("ask 1"))
        XCTAssertTrue(folded.messages.contains { $0.content == "ask 40" })

        let untouched = ConversationMemoryService.foldingOldMessagesIntoSummary(folded)
        XCTAssertEqual(untouched.messages.count, folded.messages.count)
    }
}
