import XCTest
@testable import CosmoOS

@MainActor
final class CosmoInlineAssistantRoutingTests: XCTestCase {
    func testQuestionPromptPrefersPaneRoute() {
        XCTAssertEqual(CosmoInlineAssistantPromptClassifier.route(for: "What is the strongest hook here?"), .answer)
        XCTAssertEqual(CosmoInlineAssistantPromptClassifier.route(for: "Explain why slide 4 works"), .answer)
        XCTAssertEqual(
            CosmoInlineAssistantPromptClassifier.route(
                for: "What would be a good flow of information/outline for this post I'm writing for Ben? Please check out all his best performing reels."
            ),
            .answer
        )
    }

    func testEditPromptPrefersActionRoute() {
        XCTAssertEqual(CosmoInlineAssistantPromptClassifier.route(for: "Replace the numbers in slide 4"), .action)
        XCTAssertEqual(CosmoInlineAssistantPromptClassifier.route(for: "Organize this canvas"), .action)
        XCTAssertEqual(CosmoInlineAssistantPromptClassifier.route(for: "Rewrite this paragraph to be sharper"), .action)
        XCTAssertEqual(CosmoInlineAssistantPromptClassifier.route(for: "Make slide 4 use real deal numbers"), .action)
        XCTAssertEqual(CosmoInlineAssistantPromptClassifier.route(for: "Fill the placeholders with Ben's recent stats"), .action)
    }

    func testReceivingProposalKeepsPaneClosed() {
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        let proposal = CosmoAssistantProposal(
            prompt: "Replace rent",
            surfaceID: "note:abc",
            title: "Numbers",
            summary: "Update rent",
            operations: []
        )

        store.receive(proposal: proposal)

        XCTAssertEqual(store.proposals.count, 1)
        XCTAssertFalse(store.isPaneRequested)
    }

    func testReceivingAnswerRequestsPane() {
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        store.receivePaneAnswer(title: "Answer", answer: "This hook works because it creates contrast.")

        XCTAssertTrue(store.isPaneRequested)
        XCTAssertEqual(store.paneMessages.last?.content, "This hook works because it creates contrast.")
    }

    func testPaneButtonRequestsPaneWithoutSubmittingPrompt() {
        let store = CosmoInlineAssistantStore(agentBridge: .mock)

        store.requestPane()

        XCTAssertTrue(store.isPaneRequested)
        XCTAssertTrue(store.paneMessages.isEmpty)
        XCTAssertFalse(store.isProcessing)
    }

    func testActionSubmissionSuppressesPaneAnswerFromAgent() async {
        let bridge = CosmoInlineAssistantAgentBridge { _, _, store in
            store.receivePaneAnswer(title: nil, answer: "I updated the document.")
        }
        let store = CosmoInlineAssistantStore(agentBridge: bridge)
        store.composerText = "Replace the numbers in slide 4"

        await store.submit()

        XCTAssertFalse(store.isPaneRequested)
        XCTAssertEqual(store.paneMessages.map(\.role), [.user])
    }

    func testAnswerSubmissionAllowsPaneAnswerFromAgent() async {
        let bridge = CosmoInlineAssistantAgentBridge { _, _, store in
            store.receivePaneAnswer(title: nil, answer: "Slide 4 works because it is concrete.")
        }
        let store = CosmoInlineAssistantStore(agentBridge: bridge)
        store.composerText = "Why does slide 4 work?"

        await store.submit()

        XCTAssertTrue(store.isPaneRequested)
        XCTAssertEqual(store.paneMessages.map(\.role), [.user, .assistant])
    }

    func testBottomBarPresentationCollapsesAtRestAndExpandsForInteraction() {
        XCTAssertFalse(CosmoInlineAssistantBarPresentationPolicy.isExpanded(
            isHovering: false,
            isFocused: false,
            hasComposerText: false,
            isProcessing: false
        ))

        XCTAssertTrue(CosmoInlineAssistantBarPresentationPolicy.isExpanded(
            isHovering: true,
            isFocused: false,
            hasComposerText: false,
            isProcessing: false
        ))
        XCTAssertTrue(CosmoInlineAssistantBarPresentationPolicy.isExpanded(
            isHovering: false,
            isFocused: true,
            hasComposerText: false,
            isProcessing: false
        ))
        XCTAssertTrue(CosmoInlineAssistantBarPresentationPolicy.isExpanded(
            isHovering: false,
            isFocused: false,
            hasComposerText: true,
            isProcessing: false
        ))
        XCTAssertTrue(CosmoInlineAssistantBarPresentationPolicy.isExpanded(
            isHovering: false,
            isFocused: false,
            hasComposerText: false,
            isProcessing: true
        ))
    }

    func testBottomBarBlurPolicyOnlyBlursForOutsideClicks() {
        let frame = CGRect(x: 100, y: 100, width: 300, height: 72)

        XCTAssertFalse(CosmoInlineAssistantBarPresentationPolicy.shouldBlur(
            clickPoint: CGPoint(x: 140, y: 120),
            barFrame: frame
        ))
        XCTAssertTrue(CosmoInlineAssistantBarPresentationPolicy.shouldBlur(
            clickPoint: CGPoint(x: 40, y: 120),
            barFrame: frame
        ))
    }

    func testToolActivityUpdatesInlineStatusWithCurrentAgentStep() {
        let store = CosmoInlineAssistantStore(agentBridge: .mock)

        store.receiveToolActivity(.started(
            name: "get_client_profile",
            displayLabel: "Loading profile: Ben",
            args: ["clientName": "Ben"]
        ))

        XCTAssertEqual(store.statusText, "Loading profile: Ben")

        store.receiveToolActivity(.completed(
            name: "get_client_profile",
            displayLabel: "Loading profile: Ben",
            resultPreview: "Loaded Ben profile"
        ))

        XCTAssertEqual(store.statusText, "Reviewing results")

        store.receiveToolActivity(.allDone(totalCalls: 1))

        XCTAssertNil(store.statusText)
    }

    func testToolActivityLabelsAreCompactedForTheBottomBar() {
        let label = CosmoInlineAssistantActivityLabel.statusText(
            for: .started(
                name: "web_search",
                displayLabel: "Searching the web for \"examples of local government housing reimbursement rates in California with many details\"",
                args: [:]
            )
        )

        XCTAssertLessThanOrEqual(label?.count ?? 0, 72)
        XCTAssertEqual(label?.hasSuffix("..."), true)
    }

    func testForcedToolBundlesMatchCommandStyleContextRequests() {
        let bundles = CosmoInlineAssistantToolBundlePolicy.bundles(
            for: "What would be a good flow/outline for this post for Ben? Check out his best performing reels and profile.",
            route: .answer,
            surfaceKind: .text
        )

        XCTAssertTrue(bundles.contains(.workspaceEditing))
        XCTAssertTrue(bundles.contains(.clientProfiles))
        XCTAssertTrue(bundles.contains(.swipes))
        XCTAssertTrue(bundles.contains(.writing))
        XCTAssertTrue(bundles.contains(.strategy))
        XCTAssertTrue(bundles.contains(.contentSearch))
    }
}
