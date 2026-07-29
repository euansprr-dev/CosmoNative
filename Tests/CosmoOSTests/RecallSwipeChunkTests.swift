import XCTest
@testable import CosmoOS

/// The reference layer. Before this, `documentText` returned title + body —
/// which for a reel is a title and an empty string, so every hook, transcript,
/// page section and screenshot's copy was invisible to recall. These tests pin
/// that swipes are indexed by their substance, and chunked by UNIT so a match
/// points at a section rather than a paragraph window that straddles three.
final class RecallSwipeChunkTests: XCTestCase {

    private func swipe(
        title: String = "A swipe",
        analysis: SwipeAnalysis? = nil,
        artifact: SwipeArtifact? = nil,
        body: String? = nil
    ) -> Atom {
        var atom = Atom.new(type: .research, title: title, body: body)
        atom.updateResearchMetadata { $0.isSwipeFile = true }
        if let analysis { atom = atom.withSwipeAnalysis(analysis) }
        if let artifact { atom = atom.withSwipeArtifact(artifact) }
        return atom
    }

    // MARK: - Document text

    /// The regression this whole layer exists for: a reel used to index as its
    /// title and nothing else.
    func testSwipeTextIncludesHookInsightAndTranscript() {
        var analysis = SwipeAnalysis(
            hookText: "Stop guessing what your funnel does",
            keyInsight: "Prices the delay instead of the product",
            analysisVersion: 4
        )
        analysis.structuralRecipe = "hook → mechanism → proof ×3 → offer"
        analysis.transcriptSlides = [
            TranscriptSlide(text: "Slide one text", slideNumber: 1),
            TranscriptSlide(text: "Slide two text", slideNumber: 2)
        ]
        let text = RecallDocumentBuilder.documentText(for: swipe(analysis: analysis))

        XCTAssertTrue(text.contains("Stop guessing what your funnel does"))
        XCTAssertTrue(text.contains("Prices the delay instead of the product"))
        XCTAssertTrue(text.contains("hook → mechanism → proof ×3 → offer"))
        XCTAssertTrue(text.contains("Slide one text"))
        XCTAssertTrue(text.contains("Slide two text"))
    }

    func testSpeechTranscriptIsIndexedWhenThereAreNoSlides() {
        var analysis = SwipeAnalysis(analysisVersion: 4)
        analysis.transcriptSpeechSegments = [
            TranscriptSegment(start: 0, end: 2, text: "Spoken opening"),
            TranscriptSegment(start: 2, end: 4, text: "Spoken close")
        ]
        let text = RecallDocumentBuilder.documentText(for: swipe(analysis: analysis))
        XCTAssertTrue(text.contains("Spoken opening"))
        XCTAssertTrue(text.contains("Spoken close"))
    }

    /// Slides win: a talking head banks BOTH a slide list and speech segments
    /// on some rows, and indexing both would double every phrase.
    func testSlidesSuppressTheSpeechFallback() {
        var analysis = SwipeAnalysis(analysisVersion: 4)
        analysis.transcriptSlides = [TranscriptSlide(text: "Slide text", slideNumber: 1)]
        analysis.transcriptSpeechSegments = [TranscriptSegment(start: 0, end: 1, text: "Spoken text")]
        let text = RecallDocumentBuilder.documentText(for: swipe(analysis: analysis))
        XCTAssertTrue(text.contains("Slide text"))
        XCTAssertFalse(text.contains("Spoken text"))
    }

    func testArtifactUnitsAreIndexed() {
        let artifact = SwipeArtifact(kind: .page, units: [
            SwipeArtifactUnit(index: 0, role: .hook, headline: "Stop guessing"),
            SwipeArtifactUnit(index: 1, role: .guarantee, copy: "Full refund inside 60 days")
        ], anatomy: "hero → offer → guarantee → CTA ×4")
        let text = RecallDocumentBuilder.documentText(for: swipe(artifact: artifact))

        XCTAssertTrue(text.contains("Stop guessing"))
        XCTAssertTrue(text.contains("Full refund inside 60 days"))
        XCTAssertTrue(text.contains("hero → offer → guarantee → CTA ×4"))
    }

    /// A non-swipe atom must index exactly as it always has.
    func testNonSwipeAtomsAreUnchanged() {
        var note = Atom.new(type: .note, title: "A note", body: "Body text")
        note.updateResearchMetadata { _ in }
        let text = RecallDocumentBuilder.documentText(for: note)
        XCTAssertEqual(text, "A note\n\nBody text")
    }

    // MARK: - Unit-aligned chunking

    func testSwipesWithUnitsChunkByUnit() {
        let artifact = SwipeArtifact(kind: .page, units: [
            SwipeArtifactUnit(index: 0, role: .hook, headline: "Stop guessing"),
            SwipeArtifactUnit(index: 1, role: .proof, copy: "Three dated screenshots"),
            SwipeArtifactUnit(index: 2, role: .guarantee, copy: "Full refund inside 60 days")
        ], anatomy: "hero → proof → guarantee")
        let atom = swipe(
            title: "The Offer",
            analysis: SwipeAnalysis(keyInsight: "Prices the delay", analysisVersion: 4),
            artifact: artifact
        )
        let chunks = RecallDocumentBuilder.chunks(for: atom)

        // One summary chunk + one per unit.
        XCTAssertEqual(chunks.count, 4)
        XCTAssertNil(chunks[0].role, "the summary chunk belongs to the swipe, not a unit")
        XCTAssertTrue(chunks[0].text.contains("Prices the delay"))
        XCTAssertEqual(chunks.dropFirst().compactMap(\.role), ["hook", "proof", "guarantee"])
        XCTAssertEqual(chunks.map(\.index), [0, 1, 2, 3], "indices stay dense and ordered")
    }

    /// The role prefix is what lets a match announce WHAT it matched instead
    /// of returning an anonymous paragraph.
    func testUnitChunksArePrefixedWithRoleAndTitle() {
        let artifact = SwipeArtifact(kind: .page, units: [
            SwipeArtifactUnit(index: 0, role: .guarantee, copy: "Full refund inside 60 days")
        ])
        let chunks = RecallDocumentBuilder.chunks(for: swipe(title: "The Offer", artifact: artifact))
        let unitChunk = chunks.last!
        XCTAssertTrue(unitChunk.text.hasPrefix("[guarantee] The Offer — "))
        XCTAssertTrue(unitChunk.text.contains("Full refund inside 60 days"))
    }

    func testEmptyUnitsAreNotEmbedded() {
        let artifact = SwipeArtifact(kind: .frame, units: [
            SwipeArtifactUnit(index: 0, role: .visual, attachmentUUID: "a1"),
            SwipeArtifactUnit(index: 1, role: .hook, copy: "Real copy")
        ])
        let chunks = RecallDocumentBuilder.chunks(for: swipe(artifact: artifact))
        XCTAssertEqual(chunks.compactMap(\.role), ["hook"],
                       "a unit with nothing to say must not become an empty vector")
    }

    func testUnitChunksCarryTheirUnitID() {
        let unit = SwipeArtifactUnit(index: 0, role: .offer, copy: "The stack")
        let chunks = RecallDocumentBuilder.chunks(
            for: swipe(artifact: SwipeArtifact(kind: .page, units: [unit]))
        )
        XCTAssertEqual(chunks.last?.unitID, unit.id)
    }

    /// A post (no artifact) keeps the paragraph-packing path.
    func testPostsWithoutAnArtifactStillChunkByParagraph() {
        var analysis = SwipeAnalysis(hookText: "A hook", analysisVersion: 4)
        analysis.transcriptSlides = [TranscriptSlide(text: "Slide text", slideNumber: 1)]
        let chunks = RecallDocumentBuilder.chunks(for: swipe(analysis: analysis))
        XCTAssertFalse(chunks.isEmpty)
        XCTAssertTrue(chunks.allSatisfy { $0.role == nil })
    }

    func testChunkCountIsCapped() {
        let units = (0..<80).map { SwipeArtifactUnit(index: $0, role: .teaching, copy: "Section \($0)") }
        let chunks = RecallDocumentBuilder.chunks(
            for: swipe(artifact: SwipeArtifact(kind: .page, units: units))
        )
        XCTAssertLessThanOrEqual(chunks.count, RecallDocumentBuilder.maxChunksPerAtom)
    }

    // MARK: - Reading a reference back

    /// The stored chunk carries `[role] Title — body` so the embedding knows
    /// what it is; a human reading the reference needs neither prefix.
    func testRolePrefixIsStrippedForDisplay() {
        XCTAssertEqual(
            SwipeReferenceQuery.strippedRolePrefix("[guarantee] The Offer — Full refund inside 60 days"),
            "Full refund inside 60 days")
        XCTAssertEqual(
            SwipeReferenceQuery.strippedRolePrefix("[hook] Stop guessing"),
            "Stop guessing")
        XCTAssertEqual(
            SwipeReferenceQuery.strippedRolePrefix("No prefix at all"),
            "No prefix at all")
    }

    /// An em dash INSIDE the body must survive — only a leading title
    /// separator is stripped, and only when it is plausibly a title.
    func testAnEmDashDeepInTheBodyIsNotMistakenForATitleSeparator() {
        let long = "[proof] " + String(repeating: "x", count: 100) + " — the rest"
        XCTAssertTrue(SwipeReferenceQuery.strippedRolePrefix(long).hasSuffix("— the rest"))
    }

    // MARK: - Hit shape

    func testAttributionNamesTheRoleAndTheSwipe() {
        let hit = SwipeUnitHit(
            swipeUUID: "u", swipeTitle: "The Offer", chunkIndex: 2,
            kind: .page, role: .guarantee, text: "…", similarity: 0.8
        )
        XCTAssertEqual(hit.attribution, "Guarantee · The Offer")
        XCTAssertEqual(hit.id, "u#2")
    }

    func testAttributionFallsBackToTheTitleWhenARoleIsMissing() {
        let hit = SwipeUnitHit(
            swipeUUID: "u", swipeTitle: "The Offer", chunkIndex: 0,
            kind: .post, role: nil, text: "…", similarity: 0.8
        )
        XCTAssertEqual(hit.attribution, "The Offer")
    }
}
