import XCTest
@testable import CosmoOS

final class CosmoInlineAssistantModelsTests: XCTestCase {
    func testOperationAcceptabilityRequiresPendingStatusAndLocatableOriginalText() {
        let source = CosmoEditableSourceSnapshot(
            surfaceID: "note:abc",
            targetID: "note:abc:body",
            kind: .text,
            title: "Launch note",
            text: "Rent: $4,556/mo",
            sourceHash: "hash-1",
            anchors: [.init(id: "line-1", label: "Line 1", utf16Start: 0, utf16Length: 15)]
        )
        let operation = CosmoAssistantProposalOperation.textReplacement(
            targetID: "note:abc:body",
            anchorID: "line-1",
            originalText: "Rent: $4,556/mo",
            proposedText: "Rent: $5,000/mo",
            sourceHash: "hash-1",
            rationale: "Use the requested rent number."
        )

        // Matching hash applies.
        XCTAssertTrue(operation.canApply(against: source))
        // Already-resolved operations never re-apply.
        XCTAssertFalse(operation.marked(.accepted).canApply(against: source))
        // A stale hash still applies while the original text is locatable in the surface…
        XCTAssertTrue(operation.canApply(against: source.withSourceHash("hash-2")))
        // …but once the targeted text is gone, it can no longer apply.
        let movedSource = CosmoEditableSourceSnapshot(
            surfaceID: "note:abc",
            targetID: "note:abc:body",
            kind: .text,
            title: "Launch note",
            text: "Rent: $9,001/mo",
            sourceHash: "hash-2",
            anchors: []
        )
        XCTAssertFalse(operation.canApply(against: movedSource))
    }

    func testDiffEngineBuildsParagraphReplacementHunks() {
        let hunks = CosmoInlineAssistantDiffEngine.hunks(
            original: "Rent: $4,556/mo\nExpenses: $1,800/mo",
            proposed: "Rent: $5,000/mo\nExpenses: $2,100/mo"
        )

        XCTAssertEqual(hunks.map(\.kind), [.removed, .added, .removed, .added])
        XCTAssertEqual(hunks[0].text, "Rent: $4,556/mo")
        XCTAssertEqual(hunks[1].text, "Rent: $5,000/mo")
        XCTAssertEqual(hunks[2].text, "Expenses: $1,800/mo")
        XCTAssertEqual(hunks[3].text, "Expenses: $2,100/mo")
    }

    func testLocatorMatchesAcrossWhitespaceDrift() {
        let haystack = "Slide 7\n\n1/7   Find an in-demand market\nSearch rooms."
        // The model echoes the original line with collapsed/altered whitespace.
        let range = CosmoInlineDiffLocator.range(of: "1/7 Find an in-demand market", in: haystack)
        XCTAssertNotNil(range)
        if let range {
            XCTAssertEqual(String(haystack[range]), "1/7   Find an in-demand market")
        }
        XCTAssertNil(CosmoInlineDiffLocator.range(of: "a line that is not present", in: haystack))
    }

    func testLocatorMatchesAcrossSmartPunctuation() {
        // Document uses curly quotes and an em dash; the model echoes straight ones.
        let haystack = "He said \u{201C}rooms for rent\u{201D} \u{2014} every time."
        let range = CosmoInlineDiffLocator.range(of: "\"rooms for rent\" - every time.", in: haystack)
        XCTAssertNotNil(range)
        if let range {
            XCTAssertEqual(String(haystack[range]), "\u{201C}rooms for rent\u{201D} \u{2014} every time.")
        }
    }

    func testReviewBuilderProducesOrderedSegmentsFromLiveText() {
        let source = "Intro line.\nRent: $4,556/mo\nOutro line."
        let operation = CosmoAssistantProposalOperation.textReplacement(
            targetID: "t",
            anchorID: "a",
            originalText: "Rent: $4,556/mo",
            proposedText: "Rent: $5,000/mo",
            sourceHash: "h",
            rationale: "Update rent."
        )

        let segments = CosmoInlineDiffReviewBuilder.segments(sourceText: source, operations: [operation])

        XCTAssertEqual(segments.count, 3)
        guard case let .change(change) = segments[1] else {
            return XCTFail("Expected the middle segment to be the change block")
        }
        XCTAssertEqual(change.removedLines, ["Rent: $4,556/mo"])
        XCTAssertEqual(change.addedLines, ["Rent: $5,000/mo"])
        XCTAssertFalse(change.isConflicted)
    }

    func testReviewBuilderMarksUnlocatableOperationsConflicted() {
        let source = "Only this text exists."
        let operation = CosmoAssistantProposalOperation.textReplacement(
            targetID: "t",
            anchorID: "a",
            originalText: "Something that is not here",
            proposedText: "Replacement",
            sourceHash: "h",
            rationale: "Stale edit."
        )

        let segments = CosmoInlineDiffReviewBuilder.segments(sourceText: source, operations: [operation])

        guard case let .change(change) = segments.last else {
            return XCTFail("Expected a trailing conflicted change block")
        }
        XCTAssertTrue(change.isConflicted)
    }

    func testEmptyOriginalReplacementIsAdditiveNotConflicted() {
        // The agent's "fill in the slides" case: a replacement with no original text.
        let source = "Existing line one.\nExisting line two."
        let operation = CosmoAssistantProposalOperation(
            kind: .textReplacement,
            targetID: "t",
            anchorID: nil,
            originalText: "",
            proposedText: "Brand new content.",
            sourceHash: "h",
            rationale: "Add content."
        )

        let segments = CosmoInlineDiffReviewBuilder.segments(sourceText: source, operations: [operation])

        guard case let .change(change) = segments.last else {
            return XCTFail("Expected a trailing additive change block")
        }
        XCTAssertFalse(change.isConflicted, "Empty original must not be flagged Outdated")
        XCTAssertEqual(change.removedLines, [])
        XCTAssertEqual(change.addedLines, ["Brand new content."])
        // And it must be acceptable against the live surface (additive content always applies).
        let snapshot = CosmoEditableSourceSnapshot(
            surfaceID: "s", targetID: "t", kind: .text, title: "T",
            text: source, sourceHash: "live", anchors: []
        )
        XCTAssertTrue(operation.canApply(against: snapshot))
    }

    func testAnchoredInsertionIsPlacedAfterAnchorNotAtEnd() {
        let source = "SLIDE 7\nSLIDE 8\nSLIDE 9"
        let operation = CosmoAssistantProposalOperation(
            kind: .textInsertion,
            targetID: "t",
            anchorID: nil,
            originalText: "SLIDE 7",
            proposedText: "Find an in-demand market.",
            sourceHash: "h",
            rationale: "Fill slide 7."
        )

        let segments = CosmoInlineDiffReviewBuilder.segments(sourceText: source, operations: [operation])

        // unchanged("SLIDE 7") / change(added) / unchanged("\nSLIDE 8\nSLIDE 9")
        XCTAssertEqual(segments.count, 3)
        guard case let .change(change) = segments[1] else {
            return XCTFail("Expected the added content to sit right after the anchor, not at the end")
        }
        XCTAssertEqual(change.removedLines, [])
        XCTAssertEqual(change.addedLines, ["Find an in-demand market."])
        guard case let .unchanged(_, trailing) = segments[2] else {
            return XCTFail("Expected trailing unchanged slides")
        }
        XCTAssertTrue(trailing.contains("SLIDE 8"))
    }

    func testSlideHeaderFallbackKeepsStaleHeaderReplacementReviewableInline() {
        let source = """
        SLIDE 4
        Here is the setup.
        --
        SLIDE 5
        --
        SLIDE 6
        --
        """
        let operation = CosmoAssistantProposalOperation(
            kind: .textReplacement,
            targetID: "t",
            anchorID: "slide-5",
            originalText: "SLIDE 6\n--",
            proposedText: "SLIDE 5\nFirst, I found an owner-listed home on Zillow.",
            sourceHash: "stale",
            rationale: "Convert step 1 to first person."
        )

        let segments = CosmoInlineDiffReviewBuilder.segments(sourceText: source, operations: [operation])

        let changes = segments.compactMap { segment -> CosmoInlineDiffChange? in
            if case let .change(change) = segment { return change }
            return nil
        }
        XCTAssertEqual(changes.count, 1)
        XCTAssertFalse(changes[0].isConflicted)
        XCTAssertEqual(changes[0].addedLines, [
            "SLIDE 5",
            "First, I found an owner-listed home on Zillow."
        ])
        let rendered = segments.map { segment -> String in
            switch segment {
            case let .unchanged(_, text):
                return text
            case let .change(change):
                return change.addedLines.joined(separator: "\n")
            }
        }.joined()
        XCTAssertTrue(rendered.contains("SLIDE 6\n--"))
    }
}

/// The hardened locator fallback chain: paragraph anchoring, bounded fuzzy,
/// and — critically — the never-mis-apply property. A located range that is
/// wrong is strictly worse than a conflict.
final class CosmoInlineDiffLocatorHardeningTests: XCTestCase {
    func testParagraphAnchoredMatchSurvivesMiddleLineDrift() {
        let haystack = """
        Intro paragraph stays put.

        First line of the block anchors here.
        The middle line was reworded by the user yesterday afternoon.
        Last line of the block anchors here too.

        Outro paragraph stays put.
        """
        // The model echoes the block with a stale middle line.
        let needle = """
        First line of the block anchors here.
        A middle line the model remembers from an old snapshot.
        Last line of the block anchors here too.
        """

        let range = CosmoInlineDiffLocator.range(of: needle, in: haystack)
        XCTAssertNotNil(range)
        if let range {
            let located = String(haystack[range])
            XCTAssertTrue(located.hasPrefix("First line of the block anchors here."))
            XCTAssertTrue(located.hasSuffix("Last line of the block anchors here too."))
        }
    }

    func testParagraphAnchoringRejectsImplausiblyWideSpans() {
        // Last line exists, but pages away from the first line — anchoring the
        // span would swallow unrelated content, so this must conflict.
        let filler = Array(repeating: "Unrelated filler line padding the document.", count: 60)
            .joined(separator: "\n")
        let haystack = """
        Alpha block first line.
        \(filler)
        Omega block last line.
        """
        let needle = """
        Alpha block first line.
        Something in between.
        Omega block last line.
        """

        XCTAssertNil(CosmoInlineDiffLocator.range(of: needle, in: haystack))
    }

    func testBoundedFuzzyLocatesUniqueNearMissLine() {
        let haystack = """
        Keep this line untouched.
        Rent for the duplexx is $4,556 per month total.
        Keep this other line untouched.
        """
        // One typo ("duplexx") between the model's echo and the live document.
        let needle = "Rent for the duplex is $4,556 per month total."

        let range = CosmoInlineDiffLocator.range(of: needle, in: haystack)
        XCTAssertNotNil(range)
        if let range {
            XCTAssertEqual(String(haystack[range]), "Rent for the duplexx is $4,556 per month total.")
        }
    }

    func testBoundedFuzzyRefusesAmbiguousCandidates() {
        // Two lines are equally close to the needle — ambiguity must conflict,
        // never guess.
        let haystack = """
        The launch plan ships on Tuesday morning A.
        The launch plan ships on Tuesday morning B.
        """
        let needle = "The launch plan ships on Tuesday morning X."

        XCTAssertNil(CosmoInlineDiffLocator.range(of: needle, in: haystack))
    }

    func testBoundedFuzzyRefusesDistantText() {
        let haystack = "A completely different sentence about gardening tools."
        let needle = "Rent for the duplex is $4,556 per month total."

        XCTAssertNil(CosmoInlineDiffLocator.range(of: needle, in: haystack))
    }

    /// Property: for a corpus of random single-line mutations within the fuzzy
    /// budget, the locator either returns the mutated line's exact range or nil —
    /// it never returns a range pointing at a different line.
    func testLocateOrConflictNeverMisapplies() {
        let documentLines = [
            "Q3 retention cohort dropped twelve percent quarter over quarter.",
            "The onboarding email rewrite shipped to half the audience.",
            "Pricing experiment four moves the paywall behind day seven.",
            "Creator payouts reconcile every Friday at noon eastern.",
            "Support backlog cleared after the macro library refresh."
        ]
        let haystack = documentLines.joined(separator: "\n")

        var generator = SystemRandomNumberGenerator()
        for lineIndex in documentLines.indices {
            let original = documentLines[lineIndex]
            // Mutate one character (the kind of drift a stale echo produces).
            var characters = Array(original)
            let mutationIndex = Int.random(in: 5..<characters.count - 1, using: &generator)
            characters[mutationIndex] = characters[mutationIndex] == "x" ? "y" : "x"
            let needle = String(characters)

            guard let range = CosmoInlineDiffLocator.range(of: needle, in: haystack) else {
                continue // Conflict is always acceptable.
            }
            let located = String(haystack[range])
            XCTAssertEqual(
                located, original,
                "Locator returned a range for a different line than the mutated source"
            )
        }
    }
}

/// Streamed tool-argument decoding: the pane answer must read out cleanly from
/// partial `answer_in_assistant_pane` JSON, including mid-escape boundaries.
final class LLMPartialToolArgumentsTests: XCTestCase {
    func testExtractsCompleteAnswerField() {
        let json = #"{"title": "Review", "answer": "Tight hook. Cut the second line."}"#
        XCTAssertEqual(
            LLMPartialToolArguments.stringValue(of: "answer", inPartialJSON: json),
            "Tight hook. Cut the second line."
        )
    }

    func testExtractsGrowingPartialAnswer() {
        let partial = #"{"title": "Review", "answer": "Tight hook. Cu"#
        XCTAssertEqual(
            LLMPartialToolArguments.stringValue(of: "answer", inPartialJSON: partial),
            "Tight hook. Cu"
        )
    }

    func testReturnsNilBeforeFieldOpens() {
        XCTAssertNil(LLMPartialToolArguments.stringValue(of: "answer", inPartialJSON: #"{"title": "Rev"#))
        XCTAssertNil(LLMPartialToolArguments.stringValue(of: "answer", inPartialJSON: #"{"answer""#))
    }

    func testDecodesEscapesAcrossChunks() {
        let partial = #"{"answer": "Line one.\nLine \"two\" and a backslash \\ plus uni é"#
        XCTAssertEqual(
            LLMPartialToolArguments.stringValue(of: "answer", inPartialJSON: partial),
            "Line one.\nLine \"two\" and a backslash \\ plus uni é"
        )
    }

    func testTrailingLoneBackslashIsHeldNotEmitted() {
        // A chunk boundary can land mid-escape; the dangling backslash must not leak.
        let partial = #"{"answer": "Hold this \"#
        XCTAssertEqual(
            LLMPartialToolArguments.stringValue(of: "answer", inPartialJSON: partial),
            "Hold this "
        )
    }

    func testStopsAtClosingQuoteIgnoringLaterFields() {
        let json = #"{"answer": "Done.", "title": "Ignore me"}"#
        XCTAssertEqual(
            LLMPartialToolArguments.stringValue(of: "answer", inPartialJSON: json),
            "Done."
        )
    }
}

/// The cache-ordered prompt split: static instructions must be byte-identical
/// across renders (they live inside the prompt-cache prefix), and the volatile
/// layer must carry everything request-specific.
final class CosmoInlineAssistantPromptSplitTests: XCTestCase {
    func testStaticInstructionsAreByteStableAcrossRenders() {
        for route in [CosmoInlineAssistantRoute.action, .answer] {
            let first = CosmoInlineAssistantInstructionPrompt.staticInstructions(
                for: route, requiresPaneExplanation: false
            )
            let second = CosmoInlineAssistantInstructionPrompt.staticInstructions(
                for: route, requiresPaneExplanation: false
            )
            XCTAssertEqual(first, second)
            XCTAssertFalse(first.isEmpty)
        }
    }

    func testStaticInstructionsContainNoSurfaceText() {
        let snapshot = CosmoEditableSourceSnapshot(
            surfaceID: "note:test",
            targetID: "body",
            kind: .text,
            title: "UNIQUE-SURFACE-TITLE-9X7",
            text: "UNIQUE-SURFACE-BODY-3Q1",
            sourceHash: "hash",
            anchors: []
        )

        let staticPart = CosmoInlineAssistantInstructionPrompt.staticInstructions(
            for: .action, requiresPaneExplanation: false
        )
        XCTAssertFalse(staticPart.contains("UNIQUE-SURFACE-TITLE-9X7"))
        XCTAssertFalse(staticPart.contains("UNIQUE-SURFACE-BODY-3Q1"))

        let volatilePart = CosmoInlineAssistantInstructionPrompt.volatileContext(snapshot: snapshot)
        XCTAssertNotNil(volatilePart)
        XCTAssertTrue(volatilePart?.contains("UNIQUE-SURFACE-BODY-3Q1") == true)
    }

    func testMakeComposesStaticAndVolatileLayers() {
        let made = CosmoInlineAssistantInstructionPrompt.make(route: .answer, snapshot: nil)
        let staticPart = CosmoInlineAssistantInstructionPrompt.staticInstructions(
            for: .answer, requiresPaneExplanation: false
        )
        XCTAssertTrue(made.hasPrefix(staticPart))
    }

    func testPersonalityStoreCustomizationFlowsIntoStaticInstructions() {
        let store = CosmoInlineAssistantPersonalityStore.shared
        defer { store.resetToDefault() }

        store.save("## Custom Persona\nSpeak like a pirate editor. UNIQUE-PERSONA-7Q2.")
        XCTAssertTrue(store.isCustomized)
        XCTAssertTrue(
            CosmoInlineAssistantInstructionPrompt
                .staticInstructions(for: .action, requiresPaneExplanation: false)
                .contains("UNIQUE-PERSONA-7Q2")
        )

        store.resetToDefault()
        XCTAssertFalse(store.isCustomized)
        XCTAssertEqual(store.currentText, CosmoInlineAssistantInstructionPrompt.defaultPersonality)
        XCTAssertTrue(
            CosmoInlineAssistantInstructionPrompt
                .staticInstructions(for: .action, requiresPaneExplanation: false)
                .contains("Cosmo Personality Layer")
        )
    }

    func testSkillExamplesAndVerificationRenderInSkillPromptBlock() {
        var skill = CosmoInlineAssistantSkillRuntime.builtInSkill(.inlineEdit)
        skill.examples = [
            CosmoInlineSkillExample(input: "tighten the hook", idealOutput: "UNIQUE-EXAMPLE-OUT-4R8")
        ]
        skill.verification = "no invented metrics"
        let plan = CosmoInlineAssistantSkillPlan(primarySkill: skill)

        XCTAssertTrue(plan.promptBlock.contains("UNIQUE-EXAMPLE-OUT-4R8"))
        XCTAssertTrue(plan.promptBlock.contains("Before staging output, verify: no invented metrics"))
    }
}

/// Source-ref attachment: answers and proposals carry the receipts for what
/// the assistant actually read.
@MainActor
final class CosmoInlineAssistantSourceChipTests: XCTestCase {
    func testPaneAnswerCarriesProvidedSourceRefs() {
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        let refs = [
            CosmoAssistantSourceRef(uuid: "u1", title: "Pricing research", kind: "research"),
            CosmoAssistantSourceRef(uuid: "u2", title: "Retention thread", kind: "content")
        ]
        store.sourceRefsProvider = { refs }

        store.receivePaneAnswer(title: nil, answer: "Here's the through-line.", route: .answer)

        let answer = store.paneMessages.last { $0.role == .assistant }
        XCTAssertEqual(answer?.sourceRefs, refs)
    }

    func testStreamedAnswerFinalizesWithSourceRefs() {
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        let refs = [CosmoAssistantSourceRef(uuid: "u1", title: "Pricing research", kind: "research")]
        store.sourceRefsProvider = { refs }

        store.receivePaneAnswerDelta("Here's the ")
        store.receivePaneAnswerDelta("through-line.")
        store.receivePaneAnswer(title: nil, answer: "Here's the through-line.", route: .answer)

        let assistantMessages = store.paneMessages.filter { $0.role == .assistant }
        XCTAssertEqual(assistantMessages.count, 1, "Streamed answer must finalize in place, not duplicate")
        XCTAssertEqual(assistantMessages.first?.content, "Here's the through-line.")
        XCTAssertEqual(assistantMessages.first?.sourceRefs, refs)
    }

    func testAnswersWithoutSourcesCarryNoChips() {
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        store.sourceRefsProvider = { [] }

        store.receivePaneAnswer(title: nil, answer: "Quick take.", route: .answer)

        XCTAssertNil(store.paneMessages.last { $0.role == .assistant }?.sourceRefs)
    }
}

@MainActor
final class CosmoInlineInquiryQuestionProposalTests: XCTestCase {
    private func makeProposal(
        deepDiveTitle: String? = nil,
        parentQuestionTitle: String? = nil
    ) -> CosmoAssistantInquiryQuestionProposal {
        CosmoAssistantInquiryQuestionProposal(
            question: "What actually blocks people from reaching peak state?",
            rationale: "Awareness alone doesn't explain the gap.",
            connectionUUID: "conn-1",
            connectionTitle: "Peak experience",
            deepDiveUUID: deepDiveTitle == nil ? nil : "dd-1",
            deepDiveTitle: deepDiveTitle,
            parentQuestionUUID: parentQuestionTitle == nil ? nil : "q-parent",
            parentQuestionTitle: parentQuestionTitle
        )
    }

    func testPlacementLabelPrefersParentThenDeepDiveThenConnection() {
        XCTAssertEqual(
            makeProposal(deepDiveTitle: "Peak states", parentQuestionTitle: "How does peak state work?").placementLabel,
            "Sub-question under “How does peak state work?”"
        )
        XCTAssertEqual(
            makeProposal(deepDiveTitle: "Peak states").placementLabel,
            "New question in “Peak states”"
        )
        XCTAssertEqual(
            makeProposal().placementLabel,
            "New deep dive from “Peak experience”"
        )
    }

    func testPersistedSessionFromBeforeInquiryCardsStillDecodes() throws {
        // A blob persisted before inquiry cards existed has no
        // inquiryQuestionProposals key — it must decode, not reset the session.
        let legacyJSON = """
        {
          "schemaVersion": 1,
          "surfaceID": "connection:conn-1",
          "paneMessages": [],
          "proposals": [],
          "selectedContextAtoms": [],
          "updatedAt": "2026-06-01T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(
            CosmoInlineAssistantPersistedSession.self,
            from: Data(legacyJSON.utf8)
        )
        XCTAssertNil(session.inquiryQuestionProposals)
    }

    func testReceiveInquiryProposalAppendsLinkedCardMessage() {
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        let proposal = makeProposal(deepDiveTitle: "Peak states")

        store.receive(inquiryProposal: proposal)

        XCTAssertEqual(store.inquiryQuestionProposals.count, 1)
        XCTAssertEqual(store.paneMessages.last?.inquiryProposalID, proposal.id)
        XCTAssertEqual(store.inquiryProposal(id: proposal.id)?.status, .pending)
        XCTAssertTrue(store.isPaneRequested)
    }

    func testDismissInquiryMarksProposalDismissedOnce() {
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        let proposal = makeProposal()
        store.receive(inquiryProposal: proposal)

        store.dismissInquiry(proposalID: proposal.id)
        XCTAssertEqual(store.inquiryProposal(id: proposal.id)?.status, .dismissed)

        // Dismissing again (or after a start) is a no-op, never a crash.
        store.dismissInquiry(proposalID: proposal.id)
        XCTAssertEqual(store.inquiryProposal(id: proposal.id)?.status, .dismissed)
    }

    func testInquiryProposalsSurviveSessionPersistenceRoundTrip() {
        let persistence = CosmoInlineAssistantSessionPersistence.inMemory()
        let store = CosmoInlineAssistantStore(agentBridge: .mock, sessionPersistence: persistence)
        let proposal = makeProposal(deepDiveTitle: "Peak states")
        store.receive(inquiryProposal: proposal)

        let restored = CosmoInlineAssistantStore(agentBridge: .mock, sessionPersistence: persistence)

        // ISO8601 persistence drops sub-second Date precision — compare fields, not whole structs.
        XCTAssertEqual(restored.inquiryQuestionProposals.map(\.id), [proposal.id])
        XCTAssertEqual(restored.inquiryQuestionProposals.first?.question, proposal.question)
        XCTAssertEqual(restored.inquiryQuestionProposals.first?.status, .pending)
        XCTAssertEqual(restored.inquiryQuestionProposals.first?.placementLabel, proposal.placementLabel)
        XCTAssertEqual(restored.paneMessages.last?.inquiryProposalID, proposal.id)
    }
}

/// Empty-state starters adapt to the surface; pill tints map source kinds onto
/// the same entity colors the composer's mention pills use.
final class CosmoInlineAssistantPaneEmptyStatePolicyTests: XCTestCase {
    func testStartersAdaptToSurfaceKind() {
        XCTAssertEqual(
            CosmoInlineAssistantPaneEmptyStatePolicy.starters(for: .canvas).first?.label,
            "Organize this canvas"
        )
        XCTAssertEqual(
            CosmoInlineAssistantPaneEmptyStatePolicy.starters(for: .text).map(\.label),
            ["Review this draft", "Tighten the opening", "Search my brain"]
        )
        XCTAssertEqual(CosmoInlineAssistantPaneEmptyStatePolicy.starters(for: nil).count, 3)
        // Every starter must stage a usable prompt.
        for kind in [CosmoEditableSurfaceKind.text, .structured, .canvas] {
            for starter in CosmoInlineAssistantPaneEmptyStatePolicy.starters(for: kind) {
                XCTAssertFalse(starter.prompt.isEmpty)
            }
        }
    }

    func testPillTintMapsSourceKindsToEntityTypes() {
        XCTAssertEqual(CosmoMentionPillTint.entityType(forSourceKind: "idea"), .idea)
        XCTAssertEqual(CosmoMentionPillTint.entityType(forSourceKind: "swipe_file"), .swipeFile)
        XCTAssertEqual(CosmoMentionPillTint.entityType(forSourceKind: "clientProfile"), .connection)
        XCTAssertEqual(CosmoMentionPillTint.entityType(forSourceKind: "client_profile"), .connection)
        XCTAssertEqual(CosmoMentionPillTint.entityType(forSourceKind: "thinkspace"), .thinkspace)
        XCTAssertEqual(CosmoMentionPillTint.entityType(forSourceKind: "unknown_kind"), .note)
    }
}
