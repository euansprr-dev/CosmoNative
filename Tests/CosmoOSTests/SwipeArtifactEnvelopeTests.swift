import XCTest
@testable import CosmoOS

/// ENVELOPE-SIBLING LAW: the artifact lives at `structured.swipeArtifact`, a
/// sibling of `autoMetadata` and `swipeAnalysis` — never nested inside
/// `swipeAnalysis`, which the Railway worker rebuilds wholesale on every cloud
/// pass. These tests pin that both directions of that coexistence survive, and
/// that a corrupt column is never overwritten.
final class SwipeArtifactEnvelopeTests: XCTestCase {

    private func swipeAtom() -> Atom {
        var atom = Atom.new(type: .research, title: "A swipe")
        atom.updateResearchMetadata { $0.isSwipeFile = true }
        return atom
    }

    private func structuredDict(_ atom: Atom) -> [String: Any] {
        guard let structured = atom.structured,
              let data = structured.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    private func sampleArtifact(kind: SwipeKind = .page) -> SwipeArtifact {
        SwipeArtifact(
            kind: kind,
            units: [
                SwipeArtifactUnit(index: 0, role: .hook, headline: "Stop guessing",
                                  copy: "Stop guessing what your funnel is doing.",
                                  mechanic: "names the reader's exact daily friction in seven words"),
                SwipeArtifactUnit(index: 1, role: .guarantee, headline: "60-day refund",
                                  copy: "Full refund inside 60 days, no questions.")
            ],
            anatomy: "hook → mechanism → proof ×3 → offer → guarantee → CTA repeated 4×",
            captureMode: "browser_pane",
            capturedURL: "https://example.com/sales",
            pageTitle: "The Offer"
        )
    }

    // MARK: - Round trip

    func testArtifactRoundTrips() {
        let atom = swipeAtom().withSwipeArtifact(sampleArtifact())
        let decoded = atom.swipeArtifact
        XCTAssertEqual(decoded?.kind, .page)
        XCTAssertEqual(decoded?.units.count, 2)
        XCTAssertEqual(decoded?.units.first?.role, .hook)
        XCTAssertEqual(decoded?.units.last?.role, .guarantee)
        XCTAssertEqual(decoded?.captureMode, "browser_pane")
        XCTAssertEqual(decoded?.roles, [.hook, .guarantee])
    }

    func testArtifactIsAStructuredSiblingNotNestedInAnalysis() {
        let atom = swipeAtom().withSwipeArtifact(sampleArtifact())
        let dict = structuredDict(atom)
        XCTAssertNotNil(dict["swipeArtifact"], "the envelope must be a top-level structured key")
        if let analysis = dict["swipeAnalysis"] as? [String: Any] {
            XCTAssertNil(analysis["swipeArtifact"],
                         "the envelope must NEVER be nested inside swipeAnalysis")
        }
    }

    // MARK: - Sibling preservation, both directions

    func testWritingTheArtifactPreservesRichContentAndAnalysis() {
        var atom = swipeAtom()
        var rich = ResearchRichContent()
        rich.author = "creator"
        rich.thumbnailUrl = "https://cdn.example/t.jpg"
        atom.setRichContent(rich)
        atom = atom.withSwipeAnalysis(SwipeAnalysis(hookText: "Original hook", analysisVersion: 4))

        atom = atom.withSwipeArtifact(sampleArtifact())

        XCTAssertEqual(atom.richContent?.author, "creator", "autoMetadata sibling was dropped")
        XCTAssertEqual(atom.swipeAnalysis?.hookText, "Original hook", "swipeAnalysis sibling was dropped")
        XCTAssertEqual(atom.swipeArtifact?.kind, .page)
    }

    /// The inverse, and the one that actually bites: the cloud worker (and the
    /// Mac's own insight pass) rewrite `swipeAnalysis` wholesale. The artifact
    /// must survive that untouched — this is the whole reason it is a sibling.
    func testRewritingTheAnalysisPreservesTheArtifact() {
        var atom = swipeAtom().withSwipeArtifact(sampleArtifact())

        let freshAnalysis = SwipeAnalysis(
            hookText: "A completely new analysis",
            analysisVersion: 4,
            isFullyAnalyzed: true
        )
        atom = atom.withSwipeAnalysis(freshAnalysis)

        XCTAssertEqual(atom.swipeAnalysis?.hookText, "A completely new analysis")
        XCTAssertEqual(atom.swipeArtifact?.units.count, 2,
                       "a wholesale analysis rewrite must not touch the artifact envelope")
        XCTAssertEqual(atom.swipeArtifact?.anatomy,
                       "hook → mechanism → proof ×3 → offer → guarantee → CTA repeated 4×")
    }

    func testWritingRichContentPreservesTheArtifact() {
        var atom = swipeAtom().withSwipeArtifact(sampleArtifact())
        var rich = ResearchRichContent()
        rich.author = "someone else"
        atom.setRichContent(rich)
        XCTAssertEqual(atom.swipeArtifact?.units.count, 2)
    }

    // MARK: - Refusals

    func testUnparseableStructuredColumnIsNeverOverwritten() {
        var atom = swipeAtom()
        atom.structured = "{not json at all"
        let after = atom.withSwipeArtifact(sampleArtifact())
        XCTAssertEqual(after.structured, "{not json at all",
                       "an unparseable column must be left alone, not replaced from an empty dict")
        XCTAssertNil(after.swipeArtifact)
    }

    func testCorruptArtifactKeyIsNeverReplaced() {
        var atom = swipeAtom()
        // A syntactically valid column whose swipeArtifact key cannot decode.
        atom.structured = #"{"swipeArtifact": "a string, not an object", "autoMetadata": "{}"}"#
        XCTAssertTrue(atom.swipeArtifactIsCorrupt)
        let after = atom.withSwipeArtifact(sampleArtifact())
        XCTAssertEqual(after.structured, atom.structured,
                       "a corrupt envelope is the only copy of a decomposition — never clobber it")
    }

    // MARK: - Tolerant decode

    func testUnknownKindAndRoleDegradeRatherThanFailingTheDecode() {
        var atom = swipeAtom()
        atom.structured = """
        {"swipeArtifact": {"kind": "hologram", "units": \
        [{"id": "u1", "index": 0, "role": "vibes", "copy": "Hello"}], \
        "artifactVersion": 99}}
        """
        let artifact = atom.swipeArtifact
        XCTAssertEqual(artifact?.kind, .post, "an unknown kind degrades to .post")
        XCTAssertEqual(artifact?.units.first?.role, .other, "an unknown role degrades to .other")
        XCTAssertEqual(artifact?.units.first?.copy, "Hello", "the rest of the unit survives")
    }

    func testArtifactWithNoUnitsDecodes() {
        var atom = swipeAtom()
        atom.structured = #"{"swipeArtifact": {"kind": "flow"}}"#
        XCTAssertEqual(atom.swipeArtifact?.kind, .flow)
        XCTAssertEqual(atom.swipeArtifact?.units, [])
    }

    // MARK: - Unit shape

    func testOrderedUnitsSortByIndexNotStorageOrder() {
        let artifact = SwipeArtifact(kind: .frame, units: [
            SwipeArtifactUnit(index: 2, copy: "third"),
            SwipeArtifactUnit(index: 0, copy: "first"),
            SwipeArtifactUnit(index: 1, copy: "second")
        ])
        XCTAssertEqual(artifact.orderedUnits.map(\.copy), ["first", "second", "third"])
    }

    func testDisplayLineFallsBackThroughHeadlineCopyMechanic() {
        XCTAssertEqual(
            SwipeArtifactUnit(index: 0, headline: "  Headline  ", copy: "Body").displayLine,
            "Headline")
        XCTAssertEqual(
            SwipeArtifactUnit(index: 0, copy: "First line\nSecond line").displayLine,
            "First line")
        XCTAssertEqual(
            SwipeArtifactUnit(index: 0, mechanic: "does a thing").displayLine,
            "does a thing")
        XCTAssertNil(SwipeArtifactUnit(index: 0).displayLine)
    }

    func testIsAnalyzedRequiresBothAStampAndSubstance() {
        let captured = SwipeArtifact(kind: .frame, units: [
            SwipeArtifactUnit(index: 0, attachmentUUID: "a1")
        ])
        XCTAssertFalse(captured.isAnalyzed, "capture-time units carry images, not judgments")

        let analyzed = SwipeArtifact(
            kind: .frame,
            units: [SwipeArtifactUnit(index: 0, role: .hook, attachmentUUID: "a1")],
            analyzedAt: ISO8601.string(from: Date())
        )
        XCTAssertTrue(analyzed.isAnalyzed)
    }

    // MARK: - Role vocabulary

    func testRoleResolutionMapsSynonymsAndNeverInventsALabel() {
        XCTAssertEqual(SwipeUnitRole.resolve("Risk Reversal"), .guarantee)
        XCTAssertEqual(SwipeUnitRole.resolve("call_to_action"), .cta)
        XCTAssertEqual(SwipeUnitRole.resolve("CTA"), .cta)
        XCTAssertEqual(SwipeUnitRole.resolve("social proof"), .proof)
        XCTAssertEqual(SwipeUnitRole.resolve("guarantee"), .guarantee)
        XCTAssertEqual(SwipeUnitRole.resolve("something nobody planned for"), .other,
                       "an unmapped answer lands on .other — a visible, fixable state")
        XCTAssertNil(SwipeUnitRole.resolve(nil))
        XCTAssertNil(SwipeUnitRole.resolve("   "))
    }

    func testEveryRoleBelongsToExactlyOneFamilyAndIsListedInThePrompt() {
        let vocabulary = SwipeUnitRole.promptVocabulary
        for role in SwipeUnitRole.allCases {
            XCTAssertTrue(role.family.roles.contains(role))
            XCTAssertTrue(vocabulary.contains(role.rawValue),
                          "\(role.rawValue) is missing from the analyzer prompt vocabulary")
            XCTAssertFalse(role.promptDefinition.isEmpty,
                           "\(role.rawValue) has no prompt definition — the model would guess")
        }
        let grouped = SwipeUnitRoleFamily.allCases.flatMap(\.roles)
        XCTAssertEqual(Set(grouped).count, SwipeUnitRole.allCases.count)
        XCTAssertEqual(grouped.count, SwipeUnitRole.allCases.count, "a role is in two families")
    }
}
