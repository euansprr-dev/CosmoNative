import XCTest
@testable import CosmoOS

final class CraftEngineTests: XCTestCase {

    // MARK: - Draft parsing

    func testSlideHeaderParsingSplitsOnSlideMarkers() {
        let draft = """
        SLIDE 1
        I bought a duplex with $0 down.

        SLIDE 2
        Everyone told me it was impossible.
        Here's what they missed.

        SLIDE 3
        The seller wanted out more than I wanted in.
        """
        let slides = CraftDraftParser.slides(in: draft)
        XCTAssertEqual(slides.map(\.number), [1, 2, 3])
        XCTAssertEqual(slides[0].text, "I bought a duplex with $0 down.")
        XCTAssertEqual(slides[1].sentenceCount, 2)
    }

    func testParagraphFallbackWhenNoHeaders() {
        let draft = "First paragraph here.\n\nSecond paragraph here.\n\nThird one."
        let slides = CraftDraftParser.slides(in: draft)
        XCTAssertEqual(slides.count, 3)
        XCTAssertEqual(slides[2].text, "Third one.")
    }

    // MARK: - Format density heuristic

    func testDensityHeuristicReadsOneSentenceSlidesAsReel() {
        let draft = (1...8)
            .map { "SLIDE \($0)\nShort punchy line number \($0)." }
            .joined(separator: "\n\n")
        XCTAssertEqual(CraftFormatDetector.densityHeuristic(draft), .reel)
    }

    func testDensityHeuristicReadsTwoSentenceSlidesAsReel() {
        let draft = (1...8)
            .map { "SLIDE \($0)\nShort punchy line \($0). Second beat lands fast." }
            .joined(separator: "\n\n")
        XCTAssertEqual(CraftFormatDetector.densityHeuristic(draft), .reel)
    }

    func testDensityHeuristicReadsDenseSlidesAsCarousel() {
        let slideBody = "This is a full sentence with weight. Here is another one explaining more. A third sentence drives it home. And a fourth wraps the thought."
        let draft = (1...6)
            .map { "SLIDE \($0)\n\(slideBody)" }
            .joined(separator: "\n\n")
        XCTAssertEqual(CraftFormatDetector.densityHeuristic(draft), .carousel)
    }

    func testDensityHeuristicReadsThreeSentenceSlidesAsCarousel() {
        let slideBody = "This is a full sentence with weight. Here is another one explaining more. A third sentence drives it home."
        let draft = (1...6)
            .map { "SLIDE \($0)\n\(slideBody)" }
            .joined(separator: "\n\n")
        XCTAssertEqual(CraftFormatDetector.densityHeuristic(draft), .carousel)
    }

    func testDetectUsesSlideDensityBeforeCarouselMetadataForReelScripts() {
        let metadata = ContentAtomMetadata(
            phase: .draft,
            platform: .instagram,
            contentFormat: "carousel",
            clientProfileUUID: nil,
            wordCount: 96,
            createdPhaseAt: nil,
            lastPhaseTransition: nil,
            predictedReach: nil,
            predictedEngagement: nil,
            sourceIdeaUUID: nil,
            blueprintSwipeUUID: nil,
            inheritedSwipeUUIDs: nil,
            inheritedConnectionIds: nil,
            inheritedFramework: nil,
            inheritedHooks: nil,
            activatedAt: nil,
            phaseEnteredAt: nil,
            draftingNote: nil,
            draftReady: nil,
            inheritedMentionedAtomUUIDs: nil,
            inheritedArcType: nil,
            inheritedCodexOutline: nil,
            inheritedCreativeDirection: nil,
            inheritedResearchResults: nil,
            inheritedChatHistory: nil,
            inheritedContext: nil,
            codexElementNames: nil
        )
        let atom = Atom.new(type: .content, title: "Housing reel").withMetadata(metadata)
        let draft = (1...8)
            .map { "SLIDE \($0)\nShort punchy line \($0). Second beat lands fast." }
            .joined(separator: "\n\n")

        XCTAssertEqual(CraftFormatDetector.detect(atom: atom, draftText: draft), .reel)
    }

    func testDensityHeuristicNilForShortDrafts() {
        XCTAssertNil(CraftFormatDetector.densityHeuristic("Just one line."))
    }

    // MARK: - Riff apply parsing

    func testRiffApplyParserMatchesCommonPhrasings() {
        XCTAssertEqual(CraftRiffApplyParser.variationIndex(in: "apply 2"), 2)
        XCTAssertEqual(CraftRiffApplyParser.variationIndex(in: "Use option 3"), 3)
        XCTAssertEqual(CraftRiffApplyParser.variationIndex(in: "stage 1"), 1)
        XCTAssertEqual(CraftRiffApplyParser.variationIndex(in: "go with #5"), 5)
        XCTAssertEqual(CraftRiffApplyParser.variationIndex(in: "take variation 4"), 4)
    }

    func testRiffApplyParserRejectsNonApplyPrompts() {
        XCTAssertNil(CraftRiffApplyParser.variationIndex(in: "apply the hook to slide 2"))
        XCTAssertNil(CraftRiffApplyParser.variationIndex(in: "give me 3 more variations"))
        XCTAssertNil(CraftRiffApplyParser.variationIndex(in: "what about 2?"))
        XCTAssertNil(CraftRiffApplyParser.variationIndex(in: "apply 0"))
    }

    // MARK: - Stats math

    func testMedianAndPercentile() {
        XCTAssertEqual(CraftStatsBuilder.median(of: [1, 2, 3, 4, 5]), 3)
        XCTAssertEqual(CraftStatsBuilder.median(of: [10, 20, 30, 40]), 25)
        XCTAssertEqual(CraftStatsBuilder.median(of: [Int]()), nil)
        XCTAssertEqual(CraftStatsBuilder.percentile(of: [10, 20, 30, 40, 50], fraction: 0.75), 40)
        XCTAssertEqual(CraftStatsBuilder.percentile(of: [100], fraction: 0.75), 100)
    }

    func testEmptyStatsPromptBlockSaysSo() {
        let stats = CraftFormatStats(
            format: .reel, sampleCount: 0, medianViews: nil, topQuartileViews: nil,
            medianEngagementRate: nil, hookTypeLeaderboard: [], typicalSlideRange: nil
        )
        XCTAssertTrue(stats.promptBlock.contains("No engagement data"))
    }

    // MARK: - Selector primitives

    func testCosineSimilarityBasics() {
        XCTAssertEqual(CraftComparableSelector.cosineSimilarity([1, 0], [1, 0]), 1.0, accuracy: 0.001)
        XCTAssertEqual(CraftComparableSelector.cosineSimilarity([1, 0], [0, 1]), 0.0, accuracy: 0.001)
        XCTAssertEqual(CraftComparableSelector.cosineSimilarity([], [1]), 0.0)
    }

    func testTokenizationDropsStopWordsAndShortTokens() {
        let tokens = CraftComparableSelector.tokens(in: "This slide is about wholesale real estate deals")
        XCTAssertTrue(tokens.contains("wholesale"))
        XCTAssertTrue(tokens.contains("estate"))
        XCTAssertFalse(tokens.contains("this"))
        XCTAssertFalse(tokens.contains("is"))
        XCTAssertFalse(tokens.contains("slide"))
    }

    // MARK: - Structured results

    func testReviewResultDecodesFromSchemaShapedJSON() throws {
        let json = """
        {
          "formatRead": "9-slide carousel for Ben",
          "performanceRead": {
            "tier": "above_median",
            "reasoning": "Hook withholds the number.",
            "evidence": [
              {"comparable": "Duplex reel", "numbers": "480K views", "insight": "Same mechanism."}
            ]
          },
          "slideNotes": [
            {"slide": 3, "failedTest": "Causal Chaining", "issue": "Jump.", "fix": "Bridge it.", "comparableQuote": ""}
          ],
          "topMoves": [{"move": "Lead with the number", "why": "Top comparables do."}],
          "weakestBeat": {"location": "Slide 1 hook", "originalText": "My old hook", "microVariations": ["v1", "v2"]},
          "verdict": "One fix away."
        }
        """
        let result = try JSONDecoder().decode(CraftReviewResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.performanceRead.tierLabel, "Above your median")
        XCTAssertEqual(result.slideNotes.first?.slide, 3)
        XCTAssertEqual(result.weakestBeat?.microVariations.count, 2)
    }

    func testReviewResultExtractsFromWrappedStructuredOutput() throws {
        let output = """
        Here is the structured review payload:

        ```json
        {
          "formatRead": "24-slide reel for Ben",
          "performanceRead": {
            "tier": "around_median",
            "reasoning": "The hook has the right mechanism but leaves the number blank.",
            "evidence": [
              {"comparable": "Sober living reel", "numbers": "480K views", "insight": "Same county-pays-you mechanism with a hard dollar figure."}
            ]
          },
          "slideNotes": [
            {"slide": 1, "failedTest": "Hook Craft", "issue": "Slide 1 says '$X' instead of the real figure.", "fix": "Replace the placeholder before review ships.", "comparableQuote": "THE GOVERNMENT PAYS YOU $600-$1,000/MONTH"}
          ],
          "topMoves": [{"move": "Lead with the real number", "why": "The comparable proves the dollar figure is the scroll-stopper."}],
          "weakestBeat": {"location": "Slide 1 hook", "originalText": "Every month my county pays me $X...", "microVariations": ["Every month my county pays me $1,200 per bed..."]},
          "verdict": "One number away from making the mechanism believable."
        }
        ```
        """

        let result = try CraftStructuredOutputParser.decode(CraftReviewResult.self, from: output)
        let markdown = CraftAnswerRenderer.markdown(
            for: result,
            usage: CraftUsage(inputTokens: 1000, cacheWriteTokens: 0, cacheReadTokens: 9000, outputTokens: 800)
        )

        XCTAssertEqual(result.formatRead, "24-slide reel for Ben")
        XCTAssertTrue(markdown.contains("### Around your median"))
        XCTAssertTrue(markdown.contains("**Slide 1** · Hook Craft"))
        XCTAssertFalse(markdown.contains("\"slideNotes\""))
    }

    func testRiffResultDecodesAndRenders() throws {
        let json = """
        {
          "beatLabel": "Slide 1 hook",
          "targetOriginalText": "I bought a duplex.",
          "variations": [
            {"text": "The duplex cost me $0.", "mechanism": "number-first", "borrowedFrom": "Duplex reel", "numbers": "480K views"},
            {"text": "Everyone said no bank would touch me.", "mechanism": "objection-first", "borrowedFrom": "none", "numbers": ""}
          ],
          "bet": "Variation 1 — the number does the work."
        }
        """
        let riff = try JSONDecoder().decode(CraftRiffResult.self, from: Data(json.utf8))
        let usage = CraftUsage(inputTokens: 1000, cacheWriteTokens: 0, cacheReadTokens: 9000, outputTokens: 800)
        let markdown = CraftAnswerRenderer.markdown(for: riff, usage: usage)
        XCTAssertTrue(markdown.contains("**1. number-first** · from Duplex reel (480K views)"))
        XCTAssertTrue(markdown.contains("apply N"))
        XCTAssertTrue(markdown.contains("90% cached"))
    }

    func testRenderableRiffResultRejectsEmptyDirections() {
        let output = """
        {
          "beatLabel": "",
          "targetOriginalText": "",
          "variations": [],
          "bet": "x"
        }
        """

        XCTAssertThrowsError(
            try CraftStructuredOutputParser.decodeRenderable(CraftRiffResult.self, from: output)
        )
    }

    func testRenderableRiffResultSkipsEmptyCandidateAndUsesFullCandidate() throws {
        let output = """
        {"beatLabel":"","targetOriginalText":"","variations":[],"bet":"x"}

        {
          "beatLabel": "Hook",
          "targetOriginalText": "It's called the DSCR loan.",
          "variations": [
            {"text": "It's called a DSCR loan — and it lets you buy the house off the income, not your W-2.", "mechanism": "mechanism-first", "borrowedFrom": "Seller financing explainer", "numbers": "612K views"}
          ],
          "bet": "Variation 1 — it keeps the named mechanism and quickly explains why it matters."
        }
        """

        let result = try CraftStructuredOutputParser.decodeRenderable(CraftRiffResult.self, from: output)

        XCTAssertEqual(result.beatLabel, "Hook")
        XCTAssertEqual(result.variations.count, 1)
        XCTAssertEqual(result.variations.first?.mechanism, "mechanism-first")
    }

    func testSchemasAreValidJSONObjects() {
        XCTAssertTrue(JSONSerialization.isValidJSONObject(CosmoCraftEngine.reviewSchema))
        XCTAssertTrue(JSONSerialization.isValidJSONObject(CosmoCraftEngine.riffSchema))
    }

    // MARK: - Cost accounting

    func testUsageCostUsesCurrentOpusPricing() {
        // 10K uncached in + 10K 1h-cache write + 100K cache read + 4K out:
        // 10K*$5 + 10K*$10 + 100K*$0.5 + 4K*$25 per MTok = 0.05+0.10+0.05+0.10
        let usage = CraftUsage(inputTokens: 10_000, cacheWriteTokens: 10_000, cacheReadTokens: 100_000, outputTokens: 4_000)
        XCTAssertEqual(usage.costUSD, 0.30, accuracy: 0.0001)
        XCTAssertEqual(usage.cacheHitPercent, 83)
        XCTAssertTrue(usage.receiptLine.hasPrefix("≈$0.30"))
    }

    func testCraftEngineUsesOpus48() {
        XCTAssertEqual(CosmoCraftEngine.model, "claude-opus-4-8")
    }

    func testCraftEngineRequestUsesExtraHighAdaptiveReasoning() {
        let body = CosmoCraftEngine.requestBody(
            system: [["type": "text", "text": "study method"]],
            messages: [["role": "user", "content": "Review this draft."]],
            jsonSchema: CosmoCraftEngine.reviewSchema,
            maxTokens: 8_192
        )

        XCTAssertEqual(body["model"] as? String, "claude-opus-4-8")
        XCTAssertEqual(body["thinking"] as? [String: String], ["type": "adaptive"])
        let outputConfig = body["output_config"] as? [String: Any]
        XCTAssertEqual(outputConfig?["effort"] as? String, "xhigh")
        XCTAssertNotNil(outputConfig?["format"])
    }

    func testCraftEngineDefaultOutputBudgetLeavesRoomForXHighAdaptiveThinking() {
        let body = CosmoCraftEngine.requestBody(
            system: [["type": "text", "text": "study method"]],
            messages: [["role": "user", "content": "Review this draft."]],
            jsonSchema: CosmoCraftEngine.reviewSchema
        )

        XCTAssertGreaterThanOrEqual(CosmoCraftEngine.defaultMaxTokens, 65_536)
        XCTAssertEqual(body["max_tokens"] as? Int, CosmoCraftEngine.defaultMaxTokens)
    }

    func testCraftEngineRetriesTransientOverloadResponses() async throws {
        let successBody: [String: Any] = [
            "content": [
                ["type": "text", "text": "Recovered review"]
            ],
            "usage": [
                "input_tokens": 10,
                "cache_creation_input_tokens": 0,
                "cache_read_input_tokens": 0,
                "output_tokens": 2
            ]
        ]
        let successData = try JSONSerialization.data(withJSONObject: successBody)
        var attempts = 0

        let completion = try await CosmoCraftEngine.complete(
            systemBlocks: [.init(text: "study method", cacheTTL: nil)],
            messages: [["role": "user", "content": "Review this draft."]],
            jsonSchema: nil,
            maxTokens: 1_024,
            apiKey: "test-key",
            retryBaseBackoff: 0,
            requestPerformer: { request in
                attempts += 1
                let status = attempts == 1 ? 529 : 200
                let data = attempts == 1
                    ? Data(#"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#.utf8)
                    : successData
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: status,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (data, response)
            }
        )

        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(completion.text, "Recovered review")
    }

    // MARK: - Craft skill routing

    func testCraftRouterResolvesSlashSelectedSkills() {
        XCTAssertEqual(
            CosmoCraftSkillRunner.resolveCraftSkillID(
                selectedSkillID: "contentReview", prompt: "Begin.", surfaceKind: .text
            ),
            .contentReview
        )
        XCTAssertEqual(
            CosmoCraftSkillRunner.resolveCraftSkillID(
                selectedSkillID: "voiceVariations", prompt: "the hook feels flat", surfaceKind: .text
            ),
            .voiceVariations
        )
    }

    func testCraftRouterLeavesOtherSkillsAlone() {
        XCTAssertNil(
            CosmoCraftSkillRunner.resolveCraftSkillID(
                selectedSkillID: "inlineEdit", prompt: "tighten slide 2", surfaceKind: .text
            )
        )
        XCTAssertNil(
            CosmoCraftSkillRunner.resolveCraftSkillID(
                selectedSkillID: nil, prompt: "organize the canvas", surfaceKind: .canvas
            )
        )
    }

    func testCraftRouterLeavesAutomaticVoicePromptAloneWithoutActiveSurface() {
        let prompt = """
        I found this hook I want to replicate for Josh, then go into sober living. Explain the DSCR loan in Josh's voice and give me a few variations we can do.
        """

        XCTAssertNil(
            CosmoCraftSkillRunner.resolveCraftSkillID(
                selectedSkillID: nil,
                prompt: prompt,
                surfaceKind: nil
            )
        )
    }

    func testCraftRouterResolvesAutomaticVoicePromptForTextIdeaSurface() {
        let prompt = """
        I found this hook I want to replicate for Josh, then go into sober living. Explain the DSCR loan in Josh's voice and give me a few variations we can do.
        """

        XCTAssertEqual(
            CosmoCraftSkillRunner.resolveCraftSkillID(
                selectedSkillID: nil,
                prompt: prompt,
                surfaceKind: .text
            ),
            .voiceVariations
        )
    }

    func testCraftSurfaceContextUsesIdeaTitleAndHooksWhenBodyIsEmpty() {
        let snapshot = CosmoEditableSourceSnapshot(
            surfaceID: "idea:josh-dscr",
            targetID: "idea:josh-dscr:body",
            kind: .text,
            title: "It's called the DSCR loan",
            text: "",
            sourceHash: "empty",
            anchors: [
                .init(id: "body", label: "Idea context", utf16Start: 0, utf16Length: 0),
                .init(id: "hook-0", label: "It lets you buy a property with 15% down without XYZ.", utf16Start: 0, utf16Length: 0)
            ]
        )

        let draftText = CraftSurfaceContext.draftText(for: snapshot)

        XCTAssertTrue(CraftSurfaceContext.hasUsableDraft(snapshot))
        XCTAssertTrue(draftText.contains("It's called the DSCR loan"))
        XCTAssertTrue(draftText.contains("It lets you buy a property with 15% down without XYZ."))
        XCTAssertEqual(
            CraftSurfaceContext.anchorID(
                forOriginalText: "It lets you buy a property with 15% down without XYZ.",
                in: snapshot
            ),
            "hook-0"
        )
    }
}
