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

    func testEditPromptWithStepByStepAndAddSlidesStaysActionRoute() {
        let prompt = """
        Please use @Man literally explains how to set-up a $12,000/mo sober-living home to fill in the step by step process for the remaining slides of this post. Add slides if necessary with the same structure as the rest of the post. Make sure to adapt the slide about buying the property so that it mentions both the ability to buy with a DSCR loan at 15% or rent with a corporate lease.
        """

        let plan = CosmoInlineAssistantSkillRuntime.plan(for: prompt, surfaceKind: .text)

        XCTAssertEqual(CosmoInlineAssistantPromptClassifier.route(for: prompt), .action)
        XCTAssertEqual(plan.route, .action)
        XCTAssertTrue(plan.requiresReviewedDiff)
    }

    func testOutlineIntoBodyPromptStaysEditOnlyAndDoesNotOpenPaneImmediately() async {
        let prompt = "Please take the outline of this post and put it in the actual body, in between each slide. The outline is a one-to-one with the body. The body is a one-to-one with the outline"
        let plan = CosmoInlineAssistantSkillRuntime.plan(for: prompt, surfaceKind: .text)
        let bridge = CosmoInlineAssistantAgentBridge { _, route, store in
            XCTAssertEqual(route, .action)
            XCTAssertFalse(store.isPaneRequested)
        }
        let store = CosmoInlineAssistantStore(agentBridge: bridge)
        store.composerText = prompt

        await store.submit()

        XCTAssertEqual(CosmoInlineAssistantPromptClassifier.route(for: prompt), .action)
        XCTAssertEqual(plan.route, .action)
        XCTAssertTrue(plan.requiresReviewedDiff)
        XCTAssertFalse(store.isPaneRequested)
    }

    func testFollowUpPromptCanReusePreviousActionRoute() {
        XCTAssertEqual(
            CosmoInlineAssistantPromptClassifier.route(
                for: "Do the same for slide four",
                previousRoute: .action
            ),
            .action
        )

        XCTAssertEqual(
            CosmoInlineAssistantPromptClassifier.route(
                for: "Same thing but for the ending",
                previousRoute: .answer
            ),
            .answer
        )
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
        XCTAssertEqual(store.paneMessages.count, 1)
        XCTAssertEqual(store.paneMessages.first?.proposalID, proposal.id)
        XCTAssertEqual(store.paneMessages.first?.content, "Update rent")
    }

    func testPendingProposalMatchesByTargetIDWhenSurfaceIDIsLoose() {
        let operation = CosmoAssistantProposalOperation.textReplacement(
            targetID: "content:josh-post:draft",
            anchorID: "draft",
            originalText: "SLIDE 1\n$X/mo",
            proposedText: "SLIDE 1\n$5,300/mo",
            sourceHash: "hash",
            rationale: "Fill the mortgage placeholder."
        )
        let proposal = CosmoAssistantProposal(
            prompt: "Fill slide 1 with Josh's duplex details",
            surfaceID: "josh-post",
            title: "Slide 1 facts",
            summary: "Filled the slide 1 placeholders.",
            operations: [operation]
        )
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        store.receive(proposal: proposal)

        XCTAssertEqual(
            store.pendingProposal(
                forSurfaceID: "content:josh-post",
                targetID: "content:josh-post:draft",
                activeAtomUUID: "josh-post"
            )?.id,
            proposal.id
        )
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

    func testActionSubmissionRecordsPaneAnswerWithoutOpeningPane() async {
        let bridge = CosmoInlineAssistantAgentBridge { _, _, store in
            store.receivePaneAnswer(title: nil, answer: "I updated the document.")
        }
        let store = CosmoInlineAssistantStore(agentBridge: bridge)
        store.composerText = "Replace the numbers in slide 4"

        await store.submit()

        XCTAssertFalse(store.isPaneRequested)
        XCTAssertEqual(store.paneMessages.map(\.role), [.user, .assistant])
        XCTAssertEqual(store.paneMessages.last?.content, "I updated the document.")
    }

    func testEditOnlyActionClosesExistingPaneAndKeepsInlineReviewPrimary() async {
        let bridge = CosmoInlineAssistantAgentBridge { prompt, _, store in
            store.receive(proposal: CosmoAssistantProposal(
                prompt: prompt,
                surfaceID: "content:abc",
                title: "Slide edits",
                summary: "Converted slides in place.",
                operations: []
            ))
        }
        let store = CosmoInlineAssistantStore(agentBridge: bridge)
        store.requestPane()
        store.composerText = "Starting from slide five, convert the steps into first person."

        await store.submit()

        XCTAssertFalse(store.isPaneRequested)
        XCTAssertEqual(store.paneMessages.map(\.role), [.user, .assistant])
    }

    func testProfileBackedSlideExpansionStaysDiffFirstWithoutOpeningPane() async {
        let prompt = "Add as many slides as you need to put the full step by step process for Ben (check his profile & best performing posts), make sure to include as much detail in each, and basically make a 1:1 to the best performing breakdowns in the exact same voice and structure."
        let plan = CosmoInlineAssistantSkillRuntime.plan(for: prompt, surfaceKind: .text)
        let instructions = CosmoInlineAssistantInstructionPrompt.make(
            route: plan.route,
            snapshot: nil,
            skillPlan: plan
        )
        let bridge = CosmoInlineAssistantAgentBridge { _, _, store in
            store.receivePaneAnswer(
                title: nil,
                answer: "I need to know the primary angle before adding slides.",
                route: .action
            )
        }
        let store = CosmoInlineAssistantStore(agentBridge: bridge)
        store.composerText = prompt

        await store.submit()

        XCTAssertEqual(plan.route, .action)
        XCTAssertEqual(plan.primarySkill.id, .inlineEdit)
        XCTAssertTrue(plan.requiresReviewedDiff)
        XCTAssertTrue(plan.requiredContext.contains(.clientProfile))
        XCTAssertTrue(plan.requiredContext.contains(.swipes))
        XCTAssertTrue(plan.requiredContext.contains(.bestPerformingContent))
        XCTAssertTrue(instructions.contains("do not ask the user to choose an angle"))
        XCTAssertFalse(store.isPaneRequested)
        XCTAssertEqual(store.paneMessages.map(\.role), [.user, .assistant])
    }

    func testInlineSkillRegistryIncludesBuiltInsAndCustomSkills() {
        let custom = CosmoInlineSkillDefinition.custom(
            name: "Ben Carousel Expansion",
            icon: "rectangle.stack.badge.plus",
            summary: "Expands a draft using Ben's best-performing carousel structure.",
            triggerPhrases: ["ben carousel", "best performing breakdown"],
            route: .action,
            preferredModelTier: .strategist,
            requiredContext: [.activeSurface, .clientProfile, .swipes, .bestPerformingContent],
            toolBundles: [.workspaceEditing, .clientFactLookup, .swipes, .strategy, .writing],
            instructions: ["Stage added slides as reviewed diffs."],
            outputContract: "reviewed_diff",
            tokenBudget: 2200,
            requiresReviewedDiff: true,
            panePolicy: .neverForAction
        )
        let store = CosmoInlineSkillStore.inMemory(customSkills: [custom])
        let registry = CosmoInlineSkillRegistry(store: store)

        XCTAssertNotNil(registry.skill(id: "factFill"))
        XCTAssertEqual(registry.skill(id: custom.id)?.name, "Ben Carousel Expansion")
    }

    func testSlashSkillParserExtractsSkillCommandAndRemainingPrompt() {
        let registry = CosmoInlineSkillRegistry(store: .inMemory())
        let parsed = CosmoInlineSlashSkillParser.extractCommand(
            from: "/Fact Fill replace the placeholders in slide 1",
            registry: registry
        )

        XCTAssertEqual(parsed?.skillID, "factFill")
        XCTAssertEqual(parsed?.remainingPrompt, "replace the placeholders in slide 1")
    }

    func testSelectedSlashSkillOverridesHeuristicRouting() {
        let plan = CosmoInlineAssistantSkillRuntime.plan(
            for: "replace the placeholders in slide 1",
            surfaceKind: .text,
            selectedSkillID: "voiceVariations",
            registry: CosmoInlineSkillRegistry(store: .inMemory())
        )

        XCTAssertEqual(plan.primarySkill.name, "Voice Variations")
        XCTAssertEqual(plan.route, .answer)
    }

    func testSkillPreferredModelTierIsExposedOnPlan() {
        let plan = CosmoInlineAssistantSkillRuntime.plan(
            for: "give me feedback on this",
            surfaceKind: .text,
            selectedSkillID: "contentReview",
            registry: CosmoInlineSkillRegistry(store: .inMemory())
        )

        XCTAssertEqual(plan.preferredModelTier, .strategist)
    }

    func testStoreSubmitUsesSlashSelectedSkillRoute() async {
        let bridge = CosmoInlineAssistantAgentBridge { prompt, route, store in
            XCTAssertEqual(prompt, "replace the placeholders in slide 1")
            XCTAssertEqual(route, .answer)
            XCTAssertEqual(store.activeSubmissionSkillID, "voiceVariations")
        }
        let store = CosmoInlineAssistantStore(agentBridge: bridge)
        store.composerText = "/Voice Variations replace the placeholders in slide 1"

        await store.submit()
    }

    func testPreparedInlineRequestUsesSkillModelBeforeSensorDefault() async {
        let viewModel = CosmoWindowViewModel.shared
        let request = await viewModel.prepareInlineAssistantAgentRequest(
            prompt: "give me feedback on this",
            route: .answer,
            snapshot: nil,
            inlineContextAtoms: [],
            selectedSkillID: "contentReview"
        )

        XCTAssertEqual(request.tierOverride, .strategist)
    }

    func testActiveSlashSkillMentionOnlyTriggersAtCommandBoundary() {
        XCTAssertEqual(
            CosmoInlineSlashSkillParser.activeCommand(
                in: "/voi",
                selectedRange: NSRange(location: 4, length: 0)
            )?.query,
            "voi"
        )
        XCTAssertNil(
            CosmoInlineSlashSkillParser.activeCommand(
                in: "http://example.com",
                selectedRange: NSRange(location: 7, length: 0)
            )
        )
    }

    func testResearchBackedActionSubmissionOpensPaneForExplanation() async {
        let bridge = CosmoInlineAssistantAgentBridge { prompt, _, store in
            store.receivePaneAnswer(
                title: "What I found",
                answer: "I checked current ADU permit ranges, then staged the slide 1 number fill.",
                route: .action
            )
            store.receive(proposal: CosmoAssistantProposal(
                prompt: prompt,
                surfaceID: "content:adu-post",
                title: "Slide 1 research fill",
                summary: "Filled slide 1 with current ADU permit cost context.",
                operations: []
            ))
        }
        let store = CosmoInlineAssistantStore(agentBridge: bridge)
        store.composerText = "Research current ADU permit costs and fill the different information in slide one"

        await store.submit()

        XCTAssertTrue(store.isPaneRequested)
        XCTAssertEqual(store.paneMessages.filter { $0.role == .assistant }.count, 2)
        XCTAssertEqual(store.paneMessages[1].content, "What I found")
        XCTAssertEqual(store.paneMessages[2].content, "I checked current ADU permit ranges, then staged the slide 1 number fill.")
    }

    func testActionSubmissionRecordsProposalHistoryWithoutOpeningPane() async {
        let proposalID = UUID()
        let bridge = CosmoInlineAssistantAgentBridge { _, _, store in
            store.receive(proposal: CosmoAssistantProposal(
                id: proposalID,
                prompt: "Replace the numbers in slide 4",
                surfaceID: "note:abc",
                title: "Slide 4 numbers",
                summary: "Updated the financial breakdown for slide 4.",
                operations: []
            ))
        }
        let store = CosmoInlineAssistantStore(agentBridge: bridge)
        store.composerText = "Replace the numbers in slide 4"

        await store.submit()

        XCTAssertFalse(store.isPaneRequested)
        XCTAssertEqual(store.paneMessages.map(\.role), [.user, .assistant])
        XCTAssertEqual(store.paneMessages.last?.proposalID, proposalID)
        XCTAssertEqual(store.paneMessages.last?.content, "Updated the financial breakdown for slide 4.")
    }

    func testInlineContextSelectionDeduplicatesAndSurvivesSubmitForSessionCache() async {
        let atom = Atom.new(
            type: .clientProfile,
            title: "Josh",
            body: "Josh buys underpriced homes and teaches creative finance."
        )
        let bridge = CosmoInlineAssistantAgentBridge { _, _, store in
            store.receivePaneAnswer(title: nil, answer: "I used Josh as context.")
        }
        let store = CosmoInlineAssistantStore(agentBridge: bridge)

        store.addContext(atom)
        store.addContext(atom)
        store.composerText = "Do this in Josh's voice"

        await store.submit()

        XCTAssertEqual(store.selectedContextAtoms.map(\.uuid), [atom.uuid])
        XCTAssertEqual(store.paneMessages.first?.content, "Do this in Josh's voice")
    }

    func testInlineContextMentionInsertionUsesOptionAParserAndCachesAtom() {
        let atom = Atom.new(
            type: .clientProfile,
            title: "Ben A",
            body: "Ben invests in affordable homes."
        )
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        store.composerText = "Rewrite this for @Be before Friday"
        let selection = NSRange(
            location: (store.composerText as NSString).range(of: "@Be").upperBound,
            length: 0
        )

        let replacement = store.insertContextMention(atom, selection: selection)

        XCTAssertEqual(replacement.text, "Rewrite this for @Ben A before Friday")
        XCTAssertEqual(replacement.selection.location, (replacement.text as NSString).range(of: "@Ben A ").upperBound)
        XCTAssertEqual(store.selectedContextAtoms.map(\.uuid), [atom.uuid])
    }

    func testInlineSessionPersistsMessagesContextAndProposalsBySurface() {
        let persistence = CosmoInlineAssistantSessionPersistence.inMemory()
        let sourceStore = CosmoInlineAssistantStore(agentBridge: .mock, sessionPersistence: persistence)
        sourceStore.activateSession(surfaceID: "content:alpha")
        let contextAtom = Atom.new(type: .clientProfile, title: "Josh")
        sourceStore.addContext(contextAtom)
        let proposal = CosmoAssistantProposal(
            prompt: "Fill slide 1",
            surfaceID: "content:alpha",
            title: "Slide facts",
            summary: "Filled slide 1.",
            operations: [
                .textReplacement(
                    targetID: "content:alpha:draft",
                    anchorID: "draft",
                    originalText: "Rent: $X/mo",
                    proposedText: "Rent: $5,300/mo",
                    sourceHash: "hash",
                    rationale: "Use profile fact."
                )
            ]
        )
        sourceStore.receive(proposal: proposal)

        let restoredStore = CosmoInlineAssistantStore(agentBridge: .mock, sessionPersistence: persistence)
        restoredStore.activateSession(surfaceID: "content:alpha")

        XCTAssertEqual(restoredStore.selectedContextAtoms.map(\.uuid), [contextAtom.uuid])
        XCTAssertEqual(restoredStore.paneMessages.first?.proposalID, proposal.id)
        XCTAssertEqual(restoredStore.proposals.first?.summary, "Filled slide 1.")
    }

    func testInlineSessionsAreIsolatedBySurface() {
        let persistence = CosmoInlineAssistantSessionPersistence.inMemory()
        let store = CosmoInlineAssistantStore(agentBridge: .mock, sessionPersistence: persistence)

        store.activateSession(surfaceID: "note:first")
        store.receivePaneAnswer(title: nil, answer: "First answer", route: .answer)

        store.activateSession(surfaceID: "note:second")
        XCTAssertTrue(store.paneMessages.isEmpty)
        store.receivePaneAnswer(title: nil, answer: "Second answer", route: .answer)

        store.activateSession(surfaceID: "note:first")
        XCTAssertEqual(store.paneMessages.map(\.content), ["First answer"])

        store.activateSession(surfaceID: "note:second")
        XCTAssertEqual(store.paneMessages.map(\.content), ["Second answer"])
    }

    func testSlashClearResetsOnlyActiveInlineSurfaceSession() async {
        let persistence = CosmoInlineAssistantSessionPersistence.inMemory()
        let store = CosmoInlineAssistantStore(agentBridge: .mock, sessionPersistence: persistence)

        store.activateSession(surfaceID: "note:first")
        store.addContext(Atom.new(type: .clientProfile, title: "Josh"))
        store.receivePaneAnswer(title: nil, answer: "First answer", route: .answer)

        store.activateSession(surfaceID: "note:second")
        store.receivePaneAnswer(title: nil, answer: "Second answer", route: .answer)

        store.activateSession(surfaceID: "note:first")
        store.composerText = "/clear"
        await store.submit()

        XCTAssertTrue(store.paneMessages.isEmpty)
        XCTAssertTrue(store.selectedContextAtoms.isEmpty)

        store.activateSession(surfaceID: "note:second")
        XCTAssertEqual(store.paneMessages.map(\.content), ["Second answer"])
    }

    func testContextMentionFormatterUsesBareTitleToken() {
        let atom = Atom.new(
            type: .content,
            title: "Man literally explains how to set-up a $12,000/mo sober-living home",
            body: ""
        )

        // The token is just the title — the mention pill's icon conveys the type.
        XCTAssertEqual(
            CosmoInlineAssistantContextMentionFormatter.mentionTitle(for: atom),
            "Man literally explains how to set-up a $12,000/mo sober-living home"
        )
        XCTAssertEqual(
            CosmoInlineAssistantContextMentionFormatter.accessibilityLabel(for: atom),
            "Content context: Man literally explains how to set-up a $12,000/mo sober-living home"
        )
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
        XCTAssertFalse(CosmoInlineAssistantBarVisibilityPolicy.shouldShow(isInlinePaneOpen: true))
        XCTAssertTrue(CosmoInlineAssistantBarVisibilityPolicy.shouldShow(isInlinePaneOpen: false))

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

    func testBottomBarUsesWorkingCopyInsteadOfComposerPlaceholderWhileProcessing() {
        XCTAssertEqual(
            CosmoInlineAssistantBarProcessingPolicy.leadingText(isProcessing: true),
            "Working..."
        )
        XCTAssertEqual(
            CosmoInlineAssistantBarProcessingPolicy.trailingText(
                statusText: "Reading idea josh: rework military...",
                isProcessing: true
            ),
            "Reading idea josh: rework military..."
        )
        XCTAssertNil(CosmoInlineAssistantBarProcessingPolicy.placeholder(isProcessing: true))
        XCTAssertEqual(
            CosmoInlineAssistantBarProcessingPolicy.placeholder(isProcessing: false),
            "Describe any change or ask"
        )
    }

    func testPaneShowsProgressWhileAssistantIsWorking() {
        XCTAssertTrue(CosmoInlineAssistantPaneProgressPolicy.shouldShow(
            isProcessing: true,
            statusText: "Reading current context"
        ))
        XCTAssertEqual(
            CosmoInlineAssistantPaneProgressPolicy.statusLabel(
                isProcessing: true,
                statusText: "Reading current context"
            ),
            "Reading current context"
        )
        XCTAssertFalse(CosmoInlineAssistantPaneProgressPolicy.shouldShow(
            isProcessing: false,
            statusText: "Reading current context"
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

        // The status grammar rewrites known tools into verb-first lines in the
        // user's vocabulary — the narration is the personality made visible.
        XCTAssertEqual(store.statusText, "Checking Ben's profile")

        store.receiveToolActivity(.completed(
            name: "get_client_profile",
            displayLabel: "Loading profile: Ben",
            resultPreview: "Loaded Ben profile"
        ))

        XCTAssertEqual(store.statusText, "Cosmo is writing…")

        store.receiveToolActivity(.allDone(totalCalls: 1))

        XCTAssertNil(store.statusText)
    }

    func testToolActivityLabelsAreCompactedForTheBottomBar() {
        // Unknown tools fall back to the provided display label, compacted to fit
        // the bar. (Known tools like web_search get short verb-first grammar lines
        // instead — covered below.)
        let label = CosmoInlineAssistantActivityLabel.statusText(
            for: .started(
                name: "some_future_tool",
                displayLabel: "Searching the web for \"examples of local government housing reimbursement rates in California with many details\"",
                args: [:]
            )
        )

        XCTAssertLessThanOrEqual(label?.count ?? 0, 72)
        XCTAssertEqual(label?.hasSuffix("..."), true)
    }

    func testStatusGrammarRewritesKnownToolsVerbFirst() {
        XCTAssertEqual(
            CosmoInlineAssistantStatusGrammar.line(
                toolName: "web_search",
                displayLabel: "Searching the web for a very long query that would otherwise be truncated",
                args: ["query": "curiosity hooks"]
            ),
            "Researching curiosity hooks"
        )
        XCTAssertEqual(
            CosmoInlineAssistantStatusGrammar.line(
                toolName: "search_swipes",
                displayLabel: "search_swipes",
                args: [:]
            ),
            "Pulling swipes"
        )
        XCTAssertEqual(
            CosmoInlineAssistantStatusGrammar.line(
                toolName: "propose_workspace_edit",
                displayLabel: "propose_workspace_edit",
                args: [:]
            ),
            "Staging your edits"
        )
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

    func testSkillRuntimeSelectsContentReviewForFeedbackRequests() {
        let plan = CosmoInlineAssistantSkillRuntime.plan(
            for: "Give me feedback on this piece of content for Ben.",
            surfaceKind: .text
        )

        XCTAssertEqual(plan.primarySkill.id, .contentReview)
        XCTAssertEqual(plan.route, .answer)
        XCTAssertTrue(plan.requiredContext.contains(.activeSurface))
        XCTAssertTrue(plan.requiredContext.contains(.clientProfile))
        XCTAssertTrue(plan.requiredContext.contains(.swipes))
    }

    func testSkillRuntimeSelectsVoiceVariationsWithClientContext() {
        let plan = CosmoInlineAssistantSkillRuntime.plan(
            for: "Give me five variations of this sentence in Ben's voice.",
            surfaceKind: .text
        )

        XCTAssertEqual(plan.primarySkill.id, .voiceVariations)
        XCTAssertEqual(plan.route, .answer)
        XCTAssertTrue(plan.requiredContext.contains(.clientProfile))
        XCTAssertTrue(plan.requiredContext.contains(.voiceLessons))
        XCTAssertTrue(plan.toolBundles.contains(.writing))
        XCTAssertTrue(plan.toolBundles.contains(.clientProfiles))
    }

    func testSkillRuntimeSelectsFactFillAsDiffFirstAction() {
        let plan = CosmoInlineAssistantSkillRuntime.plan(
            for: "Replace the placeholders and slide 4 numbers with Ben's real recent deal numbers.",
            surfaceKind: .text
        )

        XCTAssertEqual(plan.primarySkill.id, .factFill)
        XCTAssertEqual(plan.route, .action)
        XCTAssertTrue(plan.requiresReviewedDiff)
        XCTAssertTrue(plan.requiredContext.contains(.clientProfile))
        XCTAssertTrue(plan.requiredContext.contains(.researchEvidence))
    }

    func testResearchFillSelectsActionRouteAndForcesWebResearch() {
        let prompts = [
            "Research current ADU permit costs and fill the different information in slide one",
            "Research ADU permit costs for the slide and fill the different information in slide one"
        ]

        for prompt in prompts {
            let plan = CosmoInlineAssistantSkillRuntime.plan(
                for: prompt,
                surfaceKind: .text
            )
            let bundles = CosmoInlineAssistantToolBundlePolicy.bundles(
                for: prompt,
                route: plan.route,
                surfaceKind: .text
            )

            XCTAssertEqual(plan.route, .action, prompt)
            XCTAssertTrue(plan.requiresReviewedDiff, prompt)
            XCTAssertTrue(plan.requiredContext.contains(.researchEvidence), prompt)
            XCTAssertTrue(plan.toolBundles.contains(.webResearch), prompt)
            XCTAssertTrue(bundles.contains(.webResearch), prompt)
        }
    }

    func testFactFillInstructionsForbidRewritingNonPlaceholderCopy() {
        let snapshot = CosmoEditableSourceSnapshot(
            surfaceID: "content:josh-post",
            targetID: "content:josh-post:draft",
            kind: .text,
            title: "Josh post",
            text: "SLIDE 1\nMilitary man retires before 30 after making $X/mo...",
            sourceHash: "hash",
            anchors: [.init(id: "draft", label: "Draft", utf16Start: 0, utf16Length: 57)]
        )
        let plan = CosmoInlineAssistantSkillRuntime.plan(
            for: "Fill slide 1 with the details of Josh's first duplex from San Diego.",
            surfaceKind: .text
        )

        let prompt = CosmoInlineAssistantInstructionPrompt.make(
            route: plan.route,
            snapshot: snapshot,
            skillPlan: plan
        )

        XCTAssertEqual(plan.primarySkill.id, .factFill)
        XCTAssertTrue(prompt.contains("Only replace placeholders"))
        XCTAssertTrue(prompt.contains("Do not rewrite hooks, claims, slide framing, or user-written copy"))
    }

    func testCompactClientProfileExcludesBulkyProfileFields() {
        let hugeTranscript = String(repeating: "Full transcript should not be injected. ", count: 120)
        let hugeDocumentBody = String(repeating: "Uploaded document body should stay out. ", count: 120)
        let meta = ClientProfileMetadata(
            clientId: "josh",
            clientName: "Josh",
            platforms: [.instagram, .youtube],
            industry: "Real estate",
            targetAudience: "Military buyers and operators",
            brandStory: "Josh bought his first San Diego duplex before retiring from the Navy.",
            brandVision: "Teach service members to build wealth with real estate.",
            coreBeliefs: ["Use veteran advantages", "Make cash flow boring"],
            voiceNotes: "Direct, tactical, plainspoken.",
            uniqueAngle: "Military-to-real-estate operator.",
            topPerformingTranscripts: [hugeTranscript],
            bestFormats: ["reel", "carousel"],
            postingFrequency: "3x/week",
            handle: "@josh",
            niche: "military real estate",
            signaturePhrases: ["do the math", "buy boring"],
            documents: [
                ProfileDocument(
                    category: .story,
                    title: "San Diego Duplex Notes",
                    content: hugeDocumentBody,
                    platform: "instagram",
                    likes: 1200,
                    shares: 44
                )
            ]
        )

        let block = CosmoCompactClientProfile.format(meta: meta)

        XCTAssertTrue(block.contains("Josh"))
        XCTAssertTrue(block.contains("San Diego duplex"))
        XCTAssertTrue(block.contains("San Diego Duplex Notes"))
        XCTAssertFalse(block.contains("Full transcript should not be injected"))
        XCTAssertFalse(block.contains("Uploaded document body should stay out"))
        XCTAssertLessThan(block.count, 6_000)
    }

    func testSkillContextResolverInjectsCompactClientProfileBlock() async {
        let meta = ClientProfileMetadata(
            clientId: "josh",
            clientName: "Josh",
            platforms: [.instagram],
            brandStory: "Josh bought a San Diego duplex.",
            voiceNotes: "Direct and tactical.",
            handle: "@josh",
            niche: "military real estate"
        )
        let clientAtom = Atom
            .new(type: .clientProfile, title: "Josh")
            .withMetadata(meta)
        let plan = CosmoInlineAssistantSkillRuntime.plan(
            for: "Fill slide 1 with the details of Josh's first duplex.",
            surfaceKind: .text
        )

        let resolved = await CosmoInlineSkillContextResolver.resolve(
            skillPlan: plan,
            snapshot: nil,
            prompt: "Fill slide 1 with the details of Josh's first duplex.",
            resolvedClientAtom: clientAtom
        )

        XCTAssertTrue(resolved.satisfiedContexts.contains(.clientProfile))
        XCTAssertTrue(resolved.promptBlock.contains("## Resolved Inline Skill Context"))
        XCTAssertTrue(resolved.promptBlock.contains("Josh bought a San Diego duplex."))
        XCTAssertTrue(resolved.promptBlock.lowercased().contains("use them directly"))
    }

    func testWorkingContextClientReferenceHandlesPossessiveProfilePrompt() {
        XCTAssertEqual(
            CosmoInlineAssistantWorkingContextCache.clientReference(
                in: "Fill slide 1 with the details of Josh's first duplex from San Diego (check out Josh's profile)"
            ),
            "Josh"
        )
    }

    func testInlineActionBundlesUseClientFactLookupWhenProfileContextIsInjected() {
        let reduced = CosmoInlineAssistantToolBundlePolicy.reducedBundlesForInlineRequest(
            [.workspaceEditing, .clientProfiles, .writing],
            route: .action,
            resolvedContexts: [.clientProfile]
        )

        XCTAssertFalse(reduced.contains(.clientProfiles))
        XCTAssertTrue(reduced.contains(.clientFactLookup))
        XCTAssertTrue(reduced.contains(.workspaceEditing))
        XCTAssertTrue(reduced.contains(.writing))
    }

    func testFactFillScopeGuardRejectsUnrequestedRewrite() {
        let operation = CosmoAssistantProposalOperation.textReplacement(
            targetID: "content:josh-post:draft",
            anchorID: "draft",
            originalText: "Military man retires before 30 after making $X/mo with 1 rental property while his mortgage is only $X/mo. He explains how it works:",
            proposedText: "This Navy vet retired before 30 after making $15,000/mo with just 1 duplex. His mortgage was $5,300. Here is exactly how he did it:",
            sourceHash: "hash",
            rationale: "Fill slide 1 facts."
        )

        XCTAssertTrue(CosmoInlineAssistantEditScopeGuard.shouldReject(
            operation: operation,
            prompt: "Fill slide 1 with the details of Josh's first duplex from San Diego."
        ))
    }

    func testFactFillScopeGuardAllowsPlaceholderOnlyReplacement() {
        let operation = CosmoAssistantProposalOperation.textReplacement(
            targetID: "content:josh-post:draft",
            anchorID: "draft",
            originalText: "Military man retires before 30 after making $X/mo with 1 rental property while his mortgage is only $X/mo. He explains how it works:",
            proposedText: "Military man retires before 30 after making $15,000/mo with 1 rental property while his mortgage is only $5,300/mo. He explains how it works:",
            sourceHash: "hash",
            rationale: "Fill slide 1 numbers."
        )

        XCTAssertFalse(CosmoInlineAssistantEditScopeGuard.shouldReject(
            operation: operation,
            prompt: "Fill slide 1 with the details of Josh's first duplex from San Diego."
        ))
    }

    func testInlineInstructionsAreLayeredOnTopOfCommandPromptContext() {
        let snapshot = CosmoEditableSourceSnapshot(
            surfaceID: "note:abc",
            targetID: "note:abc:body",
            kind: .text,
            title: "Current draft",
            text: "Draft body",
            sourceHash: "hash",
            anchors: [.init(id: "body", label: "Body", utf16Start: 0, utf16Length: 10)]
        )

        let prompt = CosmoInlineAssistantInstructionPrompt.make(
            route: .answer,
            snapshot: snapshot
        )

        XCTAssertTrue(prompt.contains("## Inline Workspace Assistant"))
        XCTAssertTrue(prompt.contains("answer_in_assistant_pane"))
        XCTAssertTrue(prompt.contains("propose_workspace_edit"))
        XCTAssertTrue(prompt.contains("Active editable surface"))
        XCTAssertTrue(prompt.contains("Current draft"))
        XCTAssertTrue(prompt.contains("Never replace the normal Cosmo command context"))
    }

    func testInlineInstructionsIncludeSkillRuntimePersonalityAndContextPlan() {
        let plan = CosmoInlineAssistantSkillRuntime.plan(
            for: "Give me five variations of this sentence in Ben's voice.",
            surfaceKind: .text
        )

        let prompt = CosmoInlineAssistantInstructionPrompt.make(
            route: plan.route,
            snapshot: nil,
            skillPlan: plan
        )

        XCTAssertTrue(prompt.contains("## Inline Skill Runtime"))
        XCTAssertTrue(prompt.contains("Active skill: Voice Variations"))
        XCTAssertTrue(prompt.contains("## Cosmo Personality Layer"))
        XCTAssertTrue(prompt.contains("sharp, chill creative friend"))
        XCTAssertTrue(prompt.contains("Load the client voice/profile before writing variations"))
        XCTAssertTrue(prompt.contains("answer_in_assistant_pane"))
    }

    func testResearchBackedActionInstructionsRequireDiffAndPaneExplanation() {
        let plan = CosmoInlineAssistantSkillRuntime.plan(
            for: "Research current ADU permit costs and fill the different information in slide one",
            surfaceKind: .text
        )

        let prompt = CosmoInlineAssistantInstructionPrompt.make(
            route: plan.route,
            snapshot: nil,
            skillPlan: plan
        )

        XCTAssertTrue(prompt.contains("For research-backed or source-backed edits"))
        XCTAssertTrue(prompt.contains("call both propose_workspace_edit and answer_in_assistant_pane"))
        XCTAssertTrue(prompt.contains("what you used and why"))
    }

    func testWorkingContextCacheReusesClientForFollowUpOnSameSurface() {
        let cache = CosmoInlineAssistantWorkingContextCache()
        let snapshot = CosmoEditableSourceSnapshot(
            surfaceID: "content:deck-1",
            targetID: "content:deck-1:body",
            kind: .text,
            title: "Josh carousel",
            text: "SLIDE 1\nPlaceholder\n\nSLIDE 4\nPlaceholder",
            sourceHash: "hash-a",
            anchors: []
        )

        let firstPlan = CosmoInlineAssistantSkillRuntime.plan(
            for: "Change slide one to this for Josh. Fill out the information accurate to Josh.",
            surfaceKind: .text
        )
        let first = cache.updateFrame(
            conversationID: "conversation-1",
            prompt: "Change slide one to this for Josh. Fill out the information accurate to Josh.",
            route: .action,
            snapshot: snapshot,
            activeAtomUUID: "atom-deck-1",
            activeClientUUID: "client-josh",
            skillPlan: firstPlan,
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertFalse(first.reusedContext)
        XCTAssertEqual(first.effectiveClientUUID, "client-josh")
        XCTAssertEqual(first.skillID, .factFill)
        XCTAssertEqual(first.currentTargetHint, "slide one")

        let secondPlan = CosmoInlineAssistantSkillRuntime.plan(
            for: "Do the same for slide four",
            surfaceKind: .text
        )
        let second = cache.updateFrame(
            conversationID: "conversation-1",
            prompt: "Do the same for slide four",
            route: .action,
            snapshot: snapshot,
            activeAtomUUID: "atom-deck-1",
            activeClientUUID: nil,
            skillPlan: secondPlan,
            now: Date(timeIntervalSince1970: 120)
        )

        XCTAssertTrue(second.reusedContext)
        XCTAssertTrue(second.isFollowUp)
        XCTAssertEqual(second.effectiveClientUUID, "client-josh")
        XCTAssertEqual(second.skillID, .factFill)
        XCTAssertEqual(second.previousTargetHint, "slide one")
        XCTAssertEqual(second.currentTargetHint, "slide four")
    }

    func testWorkingContextFrameTracksSelectedContextAtoms() {
        let cache = CosmoInlineAssistantWorkingContextCache()
        let josh = Atom.new(type: .clientProfile, title: "Josh", body: "Josh voice profile")
        let swipe = Atom.new(type: .research, title: "Josh top reel", body: "Best performing reel")
        let plan = CosmoInlineAssistantSkillRuntime.plan(
            for: "Give me five variations in this voice",
            surfaceKind: .text
        )

        let frame = cache.updateFrame(
            conversationID: "conversation-1",
            prompt: "Give me five variations in this voice",
            route: .answer,
            snapshot: nil,
            activeAtomUUID: "atom-1",
            activeClientUUID: nil,
            contextAtoms: [josh, swipe],
            skillPlan: plan,
            now: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(frame.contextAtomUUIDs, [josh.uuid, swipe.uuid])
        XCTAssertEqual(frame.contextAtomTitles, ["Josh", "Josh top reel"])
        XCTAssertTrue(frame.stableContextKey.contains(josh.uuid))
        XCTAssertTrue(frame.promptBlock.contains("Selected context: Josh, Josh top reel"))
    }

    func testInlineInstructionsIncludeWorkingContextCacheFrame() {
        let plan = CosmoInlineAssistantSkillRuntime.plan(
            for: "Do the same for slide four",
            surfaceKind: .text
        )
        let frame = CosmoInlineAssistantWorkingContextFrame(
            conversationID: "conversation-1",
            surfaceID: "content:deck-1",
            targetID: "content:deck-1:body",
            surfaceKind: .text,
            surfaceTitle: "Josh carousel",
            surfaceSourceHash: "hash-a",
            activeAtomUUID: "atom-deck-1",
            effectiveClientUUID: "client-josh",
            clientReference: "Josh",
            skillID: plan.primarySkill.id,
            route: .action,
            previousPrompt: "Change slide one to this for Josh.",
            previousSkillID: .factFill,
            previousTargetHint: "slide one",
            currentTargetHint: "slide four",
            operationHint: "reuse previous operation",
            contextAtomUUIDs: ["ctx-josh", "ctx-reel"],
            contextAtomTitles: ["Josh", "Top reel"],
            isFollowUp: true,
            reusedContext: true,
            stableContextKey: "conversation-1|content:deck-1|client-josh|factFill|ctx-josh-ctx-reel",
            updatedAt: Date(timeIntervalSince1970: 120)
        )

        let prompt = CosmoInlineAssistantInstructionPrompt.make(
            route: .action,
            snapshot: nil,
            skillPlan: plan,
            workingContextFrame: frame
        )

        XCTAssertTrue(prompt.contains("## Inline Working Context Cache"))
        XCTAssertTrue(prompt.contains("Cache status: hit"))
        XCTAssertTrue(prompt.contains("Active client UUID: client-josh"))
        XCTAssertTrue(prompt.contains("Previous target: slide one"))
        XCTAssertTrue(prompt.contains("Current target: slide four"))
        XCTAssertTrue(prompt.contains("Selected context: Josh, Top reel"))
        XCTAssertTrue(prompt.contains("Reuse the prior client/profile context"))
    }
}

@MainActor
final class ComposerMentionSerializerTests: XCTestCase {
    func testPlainProjectionAndOffsetMappingAroundAPill() {
        let atom = Atom.new(type: .content, title: "My Big Idea", body: "")
        let storage = NSTextStorage(string: "Use ")
        storage.append(NSAttributedString(attachment: CosmoMentionPillAttachment(atom: atom, token: "@My Big Idea")))
        storage.append(NSAttributedString(string: " now"))

        // The agent and parser see the readable token, not the U+FFFC attachment char.
        XCTAssertEqual(ComposerMentionSerializer.plainString(from: storage), "Use @My Big Idea now")

        // Attributed length = "Use "(4) + pill(1) + " now"(4) = 9.
        // Plain length = 4 + "@My Big Idea"(12) + 4 = 20.
        XCTAssertEqual(ComposerMentionSerializer.plainOffset(forAttributedOffset: 9, in: storage), 20)
        XCTAssertEqual(ComposerMentionSerializer.attributedOffset(forPlainOffset: 20, in: storage), 9)

        // Caret immediately after the pill: attributed 5 ↔ plain 16 (4 + 12).
        XCTAssertEqual(ComposerMentionSerializer.plainOffset(forAttributedOffset: 5, in: storage), 16)
        XCTAssertEqual(ComposerMentionSerializer.attributedOffset(forPlainOffset: 16, in: storage), 5)
    }
}
