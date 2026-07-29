import XCTest
@testable import CosmoOS

/// The frame pipeline's deterministic halves: vision-response parsing (which
/// must never let a short or malformed answer misalign the index-based merge)
/// and the craft pass's role merge (which must be positional, never ordinal).
@MainActor
final class SwipeFrameAnalyzerTests: XCTestCase {

    // MARK: - Vision parsing

    func testParsesFrameReadings() {
        let raw = """
        {"frames": [
          {"copy": "How To Retire Early", "composition": "Bold white text on black", "medium": "social_post",
           "detectedSource": {"platform": "x", "handle": "@Budgetdog_"}},
          {"copy": "", "composition": "Full-bleed photo, no text", "medium": "photo", "detectedSource": null}
        ]}
        """
        let readings = SwipeFrameAnalyzer.parseVisionResponse(raw, expected: 2)
        XCTAssertEqual(readings.count, 2)
        XCTAssertEqual(readings[0].copy, "How To Retire Early")
        XCTAssertEqual(readings[0].detectedSource?.handle, "@Budgetdog_")
        XCTAssertEqual(readings[1].medium, "photo")
        XCTAssertNil(readings[1].detectedSource)
    }

    func testStripsCodeFences() {
        let raw = """
        ```json
        {"frames": [{"copy": "Hello"}]}
        ```
        """
        XCTAssertEqual(SwipeFrameAnalyzer.parseVisionResponse(raw, expected: 1).first?.copy, "Hello")
    }

    /// A model that returns fewer objects than there were images must not
    /// shift the merge: the caller pairs readings to units BY INDEX, so a
    /// short answer is padded rather than allowed to slide.
    func testShortResponseIsPaddedToTheFrameCount() {
        let readings = SwipeFrameAnalyzer.parseVisionResponse(
            #"{"frames": [{"copy": "only one"}]}"#, expected: 3
        )
        XCTAssertEqual(readings.count, 3)
        XCTAssertEqual(readings[0].copy, "only one")
        XCTAssertNil(readings[1].copy)
        XCTAssertNil(readings[2].copy)
    }

    func testOverlongResponseIsTruncated() {
        let raw = #"{"frames": [{"copy": "a"}, {"copy": "b"}, {"copy": "c"}]}"#
        XCTAssertEqual(SwipeFrameAnalyzer.parseVisionResponse(raw, expected: 2).count, 2)
    }

    func testUnparseableResponseYieldsNoReadings() {
        XCTAssertTrue(SwipeFrameAnalyzer.parseVisionResponse("sorry, I can't help", expected: 2).isEmpty)
        XCTAssertTrue(SwipeFrameAnalyzer.parseVisionResponse("", expected: 1).isEmpty)
    }

    // MARK: - Detected source

    func testFirstActionableSourceWins() {
        let readings = [
            SwipeFrameAnalyzer.FrameReading(detectedSource: .init(platform: nil, handle: nil)),
            SwipeFrameAnalyzer.FrameReading(detectedSource: .init(platform: "instagram", handle: "@creator")),
            SwipeFrameAnalyzer.FrameReading(detectedSource: .init(platform: "x", handle: "@other"))
        ]
        let source = SwipeFrameAnalyzer.firstDetectedSource(in: readings)
        XCTAssertEqual(source?.handle, "@creator", "one swipe upgrades to one post — first actionable wins")
    }

    func testNoDetectedSourceWhenNothingIsActionable() {
        let readings = [
            SwipeFrameAnalyzer.FrameReading(),
            SwipeFrameAnalyzer.FrameReading(detectedSource: .init(platform: "instagram", handle: nil))
        ]
        XCTAssertNil(SwipeFrameAnalyzer.firstDetectedSource(in: readings))
    }

    // MARK: - Role merge

    private func units(_ count: Int) -> [SwipeArtifactUnit] {
        (0..<count).map { SwipeArtifactUnit(index: $0, copy: "unit \($0)") }
    }

    /// POSITIONAL, not ordinal: a model that skips unit 2 must not shift
    /// unit 3's role onto unit 2.
    func testRoleMergeIsPositionalNotOrdinal() {
        let assignments: [SwipeInsightResponse.UnitRoleAssignment] = [
            .init(unit: 1, role: "hook", headline: "Stop guessing", mechanic: "names the friction"),
            .init(unit: 3, role: "guarantee", headline: nil, mechanic: "removes the risk")
        ]
        let merged = SwipeArtifactAnalyzer.applying(assignments, to: units(3))
        XCTAssertEqual(merged[0].role, .hook)
        XCTAssertEqual(merged[0].headline, "Stop guessing")
        XCTAssertNil(merged[1].role, "the skipped unit keeps what it had")
        XCTAssertEqual(merged[2].role, .guarantee)
        XCTAssertEqual(merged[2].mechanic, "removes the risk")
    }

    func testOutOfRangeAssignmentsAreDropped() {
        let assignments: [SwipeInsightResponse.UnitRoleAssignment] = [
            .init(unit: 0, role: "hook", headline: nil, mechanic: nil),    // 1-based: 0 is invalid
            .init(unit: 99, role: "cta", headline: nil, mechanic: nil),
            .init(unit: 2, role: "offer", headline: nil, mechanic: nil)
        ]
        let merged = SwipeArtifactAnalyzer.applying(assignments, to: units(2))
        XCTAssertNil(merged[0].role)
        XCTAssertEqual(merged[1].role, .offer)
    }

    /// CLOSED-VOCABULARY LAW: a free-text role never reaches storage.
    func testFreeTextRolesAreResolvedOntoTheClosedVocabulary() {
        let assignments: [SwipeInsightResponse.UnitRoleAssignment] = [
            .init(unit: 1, role: "Risk Reversal", headline: nil, mechanic: nil),
            .init(unit: 2, role: "a role nobody defined", headline: nil, mechanic: nil)
        ]
        let merged = SwipeArtifactAnalyzer.applying(assignments, to: units(2))
        XCTAssertEqual(merged[0].role, .guarantee)
        XCTAssertEqual(merged[1].role, .other)
    }

    func testBlankHeadlinesAndMechanicsDoNotOverwriteRealOnes() {
        var existing = units(1)
        existing[0].headline = "Kept"
        existing[0].mechanic = "Also kept"
        let merged = SwipeArtifactAnalyzer.applying(
            [.init(unit: 1, role: "hook", headline: "   ", mechanic: "")], to: existing
        )
        XCTAssertEqual(merged[0].headline, "Kept")
        XCTAssertEqual(merged[0].mechanic, "Also kept")
        XCTAssertEqual(merged[0].role, .hook)
    }

    func testNilAssignmentsLeaveUnitsUntouched() {
        let original = units(3)
        XCTAssertEqual(SwipeArtifactAnalyzer.applying(nil, to: original), original)
        XCTAssertEqual(SwipeArtifactAnalyzer.applying([], to: original), original)
    }

    // MARK: - Hook resolution

    func testHookPrefersTheUnitTheModelCalledAHook() {
        var units = self.units(3)
        units[1].role = .hook
        units[1].headline = "The real hook"
        let hook = SwipeArtifactAnalyzer.resolvedHookText(
            response: SwipeInsightResponse(displayTitle: "A title"), units: units
        )
        XCTAssertEqual(hook, "The real hook")
    }

    func testHookFallsBackToTheFirstSubstantiveUnit() {
        let hook = SwipeArtifactAnalyzer.resolvedHookText(
            response: SwipeInsightResponse(displayTitle: "A title"), units: units(2)
        )
        XCTAssertEqual(hook, "unit 0")
    }

    func testHookFallsBackToTheDisplayTitleWhenNoUnitHasText() {
        let bare = [SwipeArtifactUnit(index: 0, attachmentUUID: "a1")]
        let hook = SwipeArtifactAnalyzer.resolvedHookText(
            response: SwipeInsightResponse(displayTitle: "A title"), units: bare
        )
        XCTAssertEqual(hook, "A title")
    }

    // MARK: - Prompt

    /// The prompt must carry the full role vocabulary verbatim and demand one
    /// entry per unit — the two things that keep the model inside the closed set.
    func testPromptCarriesTheVocabularyAndTheUnitCount() {
        let artifact = SwipeArtifact(kind: .frame, units: units(3), captureMode: "clipboard")
        let prompt = SwipeArtifactAnalyzer.buildPrompt(
            artifact: artifact, units: artifact.orderedUnits,
            userNote: nil, canonicalNiches: "Real Estate Investing"
        )
        for role in SwipeUnitRole.allCases {
            XCTAssertTrue(prompt.contains(role.rawValue), "\(role.rawValue) missing from the prompt")
            XCTAssertTrue(prompt.contains(role.promptDefinition), "\(role.rawValue) definition missing")
        }
        XCTAssertTrue(prompt.contains("3 entries, 1 through 3"))
        XCTAssertTrue(prompt.contains("[1]"))
        XCTAssertTrue(prompt.contains("[3]"))
        XCTAssertTrue(prompt.contains("Real Estate Investing"))
    }

    func testPromptNamesTheUnitNounForTheKind() {
        let page = SwipeArtifact(kind: .page, units: units(2))
        XCTAssertTrue(SwipeArtifactAnalyzer.buildPrompt(
            artifact: page, units: page.orderedUnits, userNote: nil, canonicalNiches: ""
        ).contains("THE SECTIONS, IN ORDER"))

        let frames = SwipeArtifact(kind: .frame, units: units(2))
        XCTAssertTrue(SwipeArtifactAnalyzer.buildPrompt(
            artifact: frames, units: frames.orderedUnits, userNote: nil, canonicalNiches: ""
        ).contains("THE IMAGES, IN ORDER"))
    }

    /// `ContentFormat` is a POST vocabulary. Asked about a screenshot set of a
    /// landing page it has no right answer, and the model answered
    /// "twoStepCTA" — wrong in the Details rail and wrong under the Format
    /// filter. The kind already says what shape the artifact is.
    func testTheArtifactPromptNeverAsksForAPostContentFormat() {
        let artifact = SwipeArtifact(kind: .frame, units: units(3))
        let prompt = SwipeArtifactAnalyzer.buildPrompt(
            artifact: artifact, units: artifact.orderedUnits,
            userNote: nil, canonicalNiches: ""
        )
        XCTAssertFalse(prompt.contains("contentType"),
                       "asking a post-format question about a frame or page can only produce noise")
        XCTAssertFalse(prompt.contains("twoStepCTA"))
        XCTAssertFalse(prompt.contains("multiSliderReel"))
        // The taxonomy fields that DO apply are still asked for.
        XCTAssertTrue(prompt.contains("hookType"))
        XCTAssertTrue(prompt.contains("niche"))
    }

    func testPromptCarriesTheUsersNoteWhenTheyWroteOne() {
        let artifact = SwipeArtifact(kind: .frame, units: units(1))
        let prompt = SwipeArtifactAnalyzer.buildPrompt(
            artifact: artifact, units: artifact.orderedUnits,
            userNote: "  look at the guarantee stack  ", canonicalNiches: ""
        )
        XCTAssertTrue(prompt.contains("look at the guarantee stack"))
    }

    /// The attribution-strip rule is a seven-member parity family. If this
    /// assertion fails someone edited one prompt without the other six.
    func testVisionPromptCarriesTheAttributionStripRule() {
        let prompt = SwipeFrameAnalyzer.visionPrompt(frameCount: 2)
        XCTAssertTrue(prompt.contains("IGNORE author attribution"))
        XCTAssertTrue(prompt.contains("verified badge"))
        XCTAssertTrue(prompt.contains("How To Retire Early"))
        XCTAssertTrue(prompt.contains("JOIN wrapped lines"))
        XCTAssertTrue(prompt.contains("never rounded"))
        XCTAssertTrue(prompt.contains("exactly 2 objects"))
    }

    func testVisionPromptSingularisesForOneImage() {
        let prompt = SwipeFrameAnalyzer.visionPrompt(frameCount: 1)
        XCTAssertTrue(prompt.contains("1 screenshot a marketer"))
        XCTAssertTrue(prompt.contains("exactly 1 object,"))
    }
}
