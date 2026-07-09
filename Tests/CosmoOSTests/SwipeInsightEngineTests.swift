import XCTest
@testable import CosmoOS

/// The insight pass is one LLM call — everything deterministic around it
/// (response parsing, analysis construction, title guards, backfill
/// candidacy, legacy decode) is covered here.
@MainActor
final class SwipeInsightEngineTests: XCTestCase {

    // MARK: - Fixtures

    private let fullResponseJSON = """
    {
      "displayTitle": "Housing didn't get expensive by accident",
      "keyInsight": "Validates the audience's struggle with third-party data before the reframe, so the solve lands as relief instead of a lecture.",
      "hookType": "boldClaim",
      "hookScore": 9.2,
      "hookScoreReason": "Declarative accusation with a hidden actor implied.",
      "hookMechanism": "Plants the question 'then who did it?' in one sentence.",
      "primaryNarrative": "businessBreakdown",
      "secondaryNarrative": "fearMongering",
      "contentType": "carousel",
      "niche": "Real Estate",
      "creatorHandle": "@housing_facts",
      "creatorName": "Housing Facts",
      "classificationConfidence": 0.92,
      "frameworkType": "pas",
      "sections": [
        {"label": "Hook", "purpose": "Creates the gap", "slideStart": 1, "slideEnd": 1, "sizePercent": 0.15},
        {"label": "PainAmplification", "purpose": "Quantifies the squeeze", "slideStart": 2, "slideEnd": 4, "sizePercent": 0.5},
        {"label": "Resolution", "purpose": "Reframes blame systemically", "slideStart": 5, "slideEnd": 6, "sizePercent": 0.35}
      ],
      "structuralRecipe": "1. Bold claim, one sentence, sparse\\n2. Data receipts, three slides, dense",
      "voiceMarkers": ["no hedging", "data-point-per-sentence"],
      "signatureCard": "HOOK: accusation implying hidden actor. BEATS: Hook → PainAmplification → Resolution. MOVES: receipts-first proof, blame reframe. SUBJECT: housing affordability. NUMBERS: historical price-to-income ratios. VOICE: no hedging, declarative."
    }
    """

    // MARK: - Response parsing

    func testParsesFullResponse() {
        let response = SwipeInsightEngine.parseResponse(fullResponseJSON)
        XCTAssertNotNil(response)
        XCTAssertEqual(response?.displayTitle, "Housing didn't get expensive by accident")
        XCTAssertEqual(response?.hookType, "boldClaim")
        XCTAssertEqual(response?.hookScore, 9.2)
        XCTAssertEqual(response?.sections?.count, 3)
        XCTAssertEqual(response?.sections?[1].slideStart, 2)
        XCTAssertEqual(response?.sections?[1].slideEnd, 4)
        XCTAssertNotNil(response?.signatureCard)
    }

    func testParsesFencedResponse() {
        let fenced = "```json\n\(fullResponseJSON)\n```"
        XCTAssertNotNil(SwipeInsightEngine.parseResponse(fenced))
    }

    func testParseRejectsGarbage() {
        XCTAssertNil(SwipeInsightEngine.parseResponse("Sorry, I can't analyze this."))
    }

    // MARK: - Analysis construction

    private func makeAnalysis(
        hook: String = "Housing didn't get expensive by accident. For decades, home prices ran way ahead of incomes, and now everyone is surprised.",
        slideCount: Int = 6
    ) -> SwipeAnalysis {
        let response = SwipeInsightEngine.parseResponse(fullResponseJSON)!
        let atom = Atom.new(type: .research, title: "placeholder")
        return SwipeInsightEngine.buildAnalysis(
            from: response,
            hookText: hook,
            slideCount: slideCount,
            creatorUUID: "creator-123",
            atom: atom
        )
    }

    func testBuildAnalysisMapsCoreFields() {
        let analysis = makeAnalysis()
        XCTAssertTrue(analysis.isFullyAnalyzed)
        XCTAssertEqual(analysis.analysisVersion, SwipeInsightEngine.insightVersion)
        XCTAssertEqual(analysis.hookType, .boldClaim)
        XCTAssertEqual(analysis.frameworkType, .pas)
        XCTAssertEqual(analysis.primaryNarrative, .businessBreakdown)
        XCTAssertEqual(analysis.swipeContentFormat, .carousel)
        XCTAssertEqual(analysis.creatorUUID, "creator-123")
        XCTAssertEqual(analysis.classificationSource, .ai)
        XCTAssertEqual(analysis.sections?.count, 3)
        XCTAssertNotNil(analysis.signatureCard)
        XCTAssertNotNil(analysis.keyInsight)
    }

    func testBuildAnalysisClampsSlideAnchorsToSlideCount() {
        let analysis = makeAnalysis(slideCount: 3)
        let last = analysis.sections!.last!
        XCTAssertEqual(last.slideStart, 3)   // was 5, clamped
        XCTAssertEqual(last.slideEnd, 3)     // was 6, clamped
    }

    func testBuildAnalysisDropsAnchorsWithoutSlides() {
        let analysis = makeAnalysis(slideCount: 0)
        XCTAssertNil(analysis.sections?.first?.slideStart)
        XCTAssertNil(analysis.sections?.first?.slideEnd)
    }

    func testBuildAnalysisLongHookUsesModelTitle() {
        let analysis = makeAnalysis()
        XCTAssertEqual(analysis.displayTitle, "Housing didn't get expensive by accident")
    }

    func testBuildAnalysisShortHookStaysVerbatim() {
        let analysis = makeAnalysis(hook: "Stop saving money.")
        XCTAssertEqual(analysis.displayTitle, "Stop saving money.")
    }

    // MARK: - Title sanitization

    private let longHook = String(repeating: "home prices ran ahead of incomes ", count: 6)

    func testSanitizedTitleStripsWrappingQuotes() {
        let title = SwipeInsightEngine.sanitizedDisplayTitle(
            "\"The clause nobody reads\"", hook: longHook
        )
        XCTAssertEqual(title, "The clause nobody reads")
    }

    func testSanitizedTitleTruncatesAtWordBoundary() {
        let overlong = String(repeating: "word ", count: 30)
        let title = SwipeInsightEngine.sanitizedDisplayTitle(overlong, hook: longHook)
        XCTAssertNotNil(title)
        XCTAssertLessThanOrEqual(title!.count, 90)
        XCTAssertFalse(title!.hasSuffix(" "))
    }

    func testSanitizedTitleNilForEmptyModelOutputAndLongHook() {
        XCTAssertNil(SwipeInsightEngine.sanitizedDisplayTitle("   ", hook: longHook))
        XCTAssertNil(SwipeInsightEngine.sanitizedDisplayTitle(nil, hook: longHook))
    }

    func testSanitizedTitleShortHookWinsOverModelRewrite() {
        let title = SwipeInsightEngine.sanitizedDisplayTitle(
            "A different rewrite", hook: "Stop saving money."
        )
        XCTAssertEqual(title, "Stop saving money.")
    }

    // MARK: - Legacy decode compatibility

    func testLegacyAnalysisWithoutNewFieldsDecodes() throws {
        let legacyJSON = """
        {"analysisVersion": 2, "isFullyAnalyzed": true, "hookScore": 7.5,
         "sections": [{"label": "Hook", "startIndex": 0, "endIndex": 1, "purpose": "opens"}]}
        """
        let analysis = try JSONDecoder().decode(
            SwipeAnalysis.self, from: legacyJSON.data(using: .utf8)!
        )
        XCTAssertNil(analysis.displayTitle)
        XCTAssertNil(analysis.signatureCard)
        XCTAssertNil(analysis.sections?.first?.slideStart)
        XCTAssertEqual(analysis.hookScore, 7.5)
    }

    func testNewFieldsRoundTrip() throws {
        var analysis = SwipeAnalysis(analysisVersion: 3, isFullyAnalyzed: true)
        analysis.displayTitle = "Short title"
        analysis.signatureCard = "HOOK: x. BEATS: a → b."
        analysis.sections = [
            SwipeSection(label: "Hook", purpose: "opens", slideStart: 1, slideEnd: 2)
        ]

        let data = try JSONEncoder().encode(analysis)
        let decoded = try JSONDecoder().decode(SwipeAnalysis.self, from: data)
        XCTAssertEqual(decoded.displayTitle, "Short title")
        XCTAssertEqual(decoded.signatureCard, "HOOK: x. BEATS: a → b.")
        XCTAssertEqual(decoded.sections?.first?.slideStart, 1)
        XCTAssertEqual(decoded.sections?.first?.slideEnd, 2)
    }

    // MARK: - Title backfill candidacy

    func testBackfillCandidateRequiresLongHookDerivedTitle() {
        let hook = String(repeating: "the market shifted and nobody noticed ", count: 4)
        let derivedTitle = String(hook.prefix(120))

        XCTAssertTrue(SwipeTitleBackfill.isCandidate(
            title: derivedTitle, hook: hook, analysis: nil
        ))
        // Short title — clean already.
        XCTAssertFalse(SwipeTitleBackfill.isCandidate(
            title: "Short title", hook: hook, analysis: nil
        ))
        // User-renamed title (not a hook prefix) — never touched.
        XCTAssertFalse(SwipeTitleBackfill.isCandidate(
            title: String(repeating: "my own custom research title note ", count: 3),
            hook: hook, analysis: nil
        ))
        // Already processed by the insight pass.
        var processed = SwipeAnalysis(analysisVersion: 3, isFullyAnalyzed: true)
        processed.displayTitle = "The market shifted"
        XCTAssertFalse(SwipeTitleBackfill.isCandidate(
            title: derivedTitle, hook: hook, analysis: processed
        ))
        // No hook at all — can't verify the title is auto-derived.
        XCTAssertFalse(SwipeTitleBackfill.isCandidate(
            title: derivedTitle, hook: nil, analysis: nil
        ))
    }
}
