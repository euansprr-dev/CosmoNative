import XCTest
@testable import CosmoOS

final class SwipeLabTests: XCTestCase {
    private func swipe(_ text: String = "A concrete opening", id: String = UUID().uuidString) -> Atom {
        var atom = Atom.new(type: .research, title: "Example", body: text)
        atom.uuid = id
        atom.updateResearchMetadata { $0.isSwipeFile = true }
        return atom
    }

    func testOriginalTranscriptTakesPrecedenceOverBody() {
        var atom = swipe("A body representation that is not the original")
        var rich = ResearchRichContent()
        rich.transcript = "The actual words in the post"
        atom.setRichContent(rich)
        XCTAssertEqual(SwipeLabCorpus.originalText(atom), "The actual words in the post")
    }

    func testJSONTranscriptIsDecodedIntoOriginalWords() throws {
        let segments = [TranscriptSegment(start: 1, end: 3, text: "Actual spoken words")]
        let atom = swipe(String(data: try JSONEncoder().encode(segments), encoding: .utf8)!)
        XCTAssertEqual(SwipeLabCorpus.originalText(atom), "Actual spoken words")
    }

    func testAnalysisDoesNotBecomeOriginalEvidence() {
        var atom = swipe("")
        atom = atom.withSwipeArtifact(SwipeArtifact(kind: .page, units: [
            SwipeArtifactUnit(index: 0, role: .hook, copy: "Original copy", mechanic: "Invented explanation")
        ]))
        atom = atom.withSwipeAnalysis(SwipeAnalysis(keyInsight: "An AI summary", analysisVersion: 4))
        let source = SwipeLabCorpus.source(atom)
        XCTAssertEqual(source.units.map(\.text), ["Original copy"])
        XCTAssertFalse(source.units.map(\.text).joined().contains("Invented explanation"))
    }

    func testEveryPassageHasStableUnicodeSafeAnchor() {
        let source = SwipeLabCorpus.source(swipe("👩🏽‍💻 Café\n\nSecond passage"))
        XCTAssertEqual(source.units.count, 2)
        XCTAssertEqual(source.units[1].anchor.utf16Start, "👩🏽‍💻 Café\n\n".utf16.count)
        XCTAssertEqual(source.units[1].anchor.quote, "Second passage")
        let again = SwipeLabCorpus.source(source.atom)
        XCTAssertEqual(source.units.map(\.id), again.units.map(\.id))
        var edited = source.atom; edited.body = "Different original"
        XCTAssertNotEqual(source.contentHash, SwipeLabCorpus.source(edited).contentHash)
    }

    func testLongOriginalIsPartitionedWithoutLosingText() {
        let original = String(repeating: "👩🏽‍💻 paragraph. ", count: 1200)
        let source = SwipeLabCorpus.source(swipe(original))
        XCTAssertGreaterThan(source.units.count, 1)
        XCTAssertEqual(source.units.map(\.text).joined(), original)
        XCTAssertEqual(Set(source.units.map(\.id)).count, source.units.count)
        XCTAssertTrue(source.units.allSatisfy { $0.text.count <= 4000 })
    }

    func testDuplicatesAreCountedOnceAndMissingMetricsStayMissing() {
        let sources = SwipeLabCorpus.build(atoms: [swipe("Same text", id: "a"), swipe("Same  text", id: "b"), swipe("Different", id: "c")], scope: .selection(["a", "b", "c"]))
        XCTAssertEqual(sources.filter(\.isReadable).count, 2)
        XCTAssertEqual(sources.filter { $0.duplicateOf != nil }.count, 1)
        let cohort = SwipeLabStatistics.cohort(sources, metric: .views, label: "Study")
        XCTAssertNil(cohort.median)
        XCTAssertEqual(cohort.missing, 2)
        XCTAssertEqual(cohort.count, 0)
    }

    func testSourcePopulationIsIndependentOfAdaptationClient() {
        let scope = SwipeLabScope.selection(["b", "a", "a"])
        XCTAssertEqual(scope.identity, SwipeLabScope.selection(["a", "b"], title: "Another name").identity)
        var first = SwipeLabSessionState(scope: scope, targetClientID: "first-client")
        let identity = first.scope.identity
        first.targetClientID = "second-client"
        XCTAssertEqual(first.scope.identity, identity)
        XCTAssertNil(SwipeLabStatistics.matchedBaseline(for: SwipeLabCorpus.source(swipe()), in: [], metric: .views))
    }

    func testFriendlyPlatformScopeIncludesSavedReelAndCarouselVariants() {
        var reel = swipe("Reel words")
        reel.updateResearchMetadata { $0.contentSource = "instagram_reel" }
        var carousel = swipe("Carousel words")
        carousel.updateResearchMetadata { $0.contentSource = "instagram_carousel" }
        var scope = SwipeLabScope.selection([reel.uuid, carousel.uuid])
        scope.platform = "Instagram"
        XCTAssertEqual(SwipeLabCorpus.build(atoms: [reel, carousel], scope: scope).count, 2)
        scope.platform = "youtube"
        XCTAssertTrue(SwipeLabCorpus.build(atoms: [reel, carousel], scope: scope).isEmpty)
    }

    func testEmptyPositiveRecallScopeReturnsNoGlobalFallback() async {
        let hits = await RecallEngine.shared.query(RecallQuery(text: "specific original passage", includeUuids: []))
        XCTAssertTrue(hits.isEmpty)
    }

    func testMissingOriginalCannotBePresentedAsCompleteCoverage() {
        let coverage = SwipeLabCoverage(total: 3, readable: 1, inspectedIDs: ["read"], duplicateCount: 1)
        XCTAssertFalse(coverage.isComplete)
        XCTAssertEqual(coverage.label, "1 of 1 readable posts studied")
    }

    func testFinalFindingsRejectEvidenceOutsideAllowlist() throws {
        let source = SwipeLabCorpus.source(swipe())
        let anchor = try XCTUnwrap(source.units.first?.anchor)
        let ref = SwipeLabEngine.reference(anchor)
        let finding = SwipeLabAnswerWire.Finding(title: "Concrete promise", observation: "An opening", mechanism: "An expectation", limitations: "One post", transfer: "Try a specific promise", support: [ref], counterevidence: [])
        let wire = SwipeLabAnswerWire(answer: "A bounded observation", findings: [finding])
        XCTAssertThrowsError(try SwipeLabEngine.validate(wire, refs: [:], snapshotID: "snapshot", promptHash: "method", clientID: nil))
        let checked = try SwipeLabEngine.validate(wire, refs: [ref: anchor], snapshotID: "snapshot", promptHash: "method", clientID: "client")
        XCTAssertEqual(checked.first?.support.first?.quote, anchor.quote)
        XCTAssertEqual(checked.first?.clientID, "client")
        var repeated = finding
        repeated.support = Array(repeating: ref, count: 12)
        let deduplicated = try SwipeLabEngine.validate(.init(answer: "A supported observation", findings: [repeated]), refs: [ref: anchor], snapshotID: "snapshot", promptHash: "method", clientID: nil)
        XCTAssertEqual(deduplicated.first?.support.count, 1, "Repeated real evidence must not be mislabeled as outside the reading")
    }

    func testConcurrentSessionMergePreservesBothConversationsAndNewestEdits() {
        var first = SwipeLabSessionState(scope: .selection(["a"]))
        first.turns = [.init(role: .user, text: "First window", snapshotID: nil)]
        var second = first
        second.turns.append(.init(role: .user, text: "Second window", snapshotID: nil))
        first.turns.append(.init(role: .assistant, text: "Completed in first window", snapshotID: nil))
        let merged = first.mergingDurableHistory(from: second)
        XCTAssertEqual(merged.turns.count, 3)
        XCTAssertEqual(Set(merged.turns.map(\.text)).count, 3)
    }

    func testPromptAndMetricChangesInvalidateSnapshotIdentity() {
        var source = SwipeLabCorpus.source(swipe())
        let first = SwipeLabSnapshot(sources: [source.manifest])
        source.metrics = [.init(metric: .views, value: 300, platform: "instagram", capturedAt: nil, publishedAt: nil, provenance: "Saved post")]
        XCTAssertNotEqual(first.fingerprint, SwipeLabSnapshot(sources: [source.manifest]).fingerprint)
        XCTAssertNotEqual(SwipeLabPromptPack(system: "one", client: "client", modules: []).hash, SwipeLabPromptPack(system: "two", client: "client", modules: []).hash)
        XCTAssertNil(source.metrics[0].ageHours)
    }

    func testCancelledRunNeverReportsACompletedAnswer() async {
        let source = SwipeLabCorpus.source(swipe())
        var state = SwipeLabSessionState(scope: .selection([source.id]))
        state.snapshots = [.init(sources: [source.manifest])]
        do {
            _ = try await SwipeLabEngine.analyze(question: UUID().uuidString, state: state, sources: [source], pack: .init(system: "test", client: "", modules: []), completion: { _, _, _ in throw CancellationError() }, cache: nil, progress: { _, _ in })
            XCTFail("Cancellation must not return a fabricated answer")
        } catch is CancellationError { }
        catch { XCTFail("Expected cancellation, got \(error)") }
    }

    func testLargeCorpusReadsEveryPassageWithBoundedConcurrency() async throws {
        let sources = (0..<7).map { SwipeLabCorpus.source(swipe("Opening \($0)\n\nConcrete proof \($0)\n\nPayoff \($0)")) }
        var state = SwipeLabSessionState(scope: .selection(sources.map(\.id)), targetClientID: "client-a")
        state.snapshots = [.init(sources: sources.map(\.manifest))]
        let probe = SwipeLabCompletionProbe(anchor: sources[0].units[0].anchor)
        let result = try await SwipeLabEngine.analyze(question: "What changes expectation?", state: state, sources: sources,
            pack: .init(system: "test", client: "client-a", modules: []), completion: { prompt, _, _ in try await probe.respond(prompt) }, cache: nil, progress: { _, _ in })
        XCTAssertEqual(result.coverage.inspected, 7)
        XCTAssertTrue(result.coverage.isComplete)
        XCTAssertEqual(result.jobs.count, 21)
        XCTAssertEqual(result.findings.first?.support.first?.quote, sources[0].units[0].text)
        XCTAssertEqual(result.findings.first?.clientID, "client-a")
        let maximum = await probe.maximumActive
        XCTAssertLessThanOrEqual(maximum, 2)
        let passes = await probe.verificationPasses
        XCTAssertEqual(passes, 1)
    }

    func testPartialFailureAndUnavailableOriginalRemainVisibleInCoverage() async throws {
        let good = SwipeLabCorpus.source(swipe("A readable opening"))
        var broken = SwipeLabCorpus.source(swipe("Different opening")); broken.title = "FAIL_THIS_SOURCE"
        let missing = SwipeLabSourceManifest(sourceID: "deleted-source", title: "Unavailable", contentHash: "old", unitCount: 1, duplicateOf: nil, isComparison: false)
        var state = SwipeLabSessionState(scope: .selection([good.id, broken.id, missing.sourceID]))
        state.snapshots = [.init(sources: [good.manifest, broken.manifest, missing])]
        let probe = SwipeLabCompletionProbe(anchor: good.units[0].anchor)
        let result = try await SwipeLabEngine.analyze(question: "Study", state: state, sources: [good, broken], pack: .init(system: "test", client: "", modules: []),
            completion: { prompt, _, _ in try await probe.respond(prompt) }, cache: nil, progress: { _, _ in })
        XCTAssertEqual(result.coverage.total, 3)
        XCTAssertEqual(result.coverage.readable, 2)
        XCTAssertEqual(result.coverage.inspected, 1)
        XCTAssertEqual(result.coverage.failedIDs, [broken.id])
        XCTAssertFalse(result.coverage.isComplete)
    }

    func testSnapshotAndSessionRoundTripPreserveAnchorsAndClientScope() throws {
        let source = SwipeLabCorpus.source(swipe("Original words"))
        var state = SwipeLabSessionState(scope: .selection([source.id]), targetClientID: "client-a")
        state.snapshots = [.init(sources: [source.manifest])]
        state.practices = [.init(sourceID: source.id, anchor: source.units[0].anchor, question: "What does this do?", answer: "A hypothesis")]
        let roundTrip = try JSONDecoder().decode(SwipeLabSessionState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(state, roundTrip)
        XCTAssertEqual(roundTrip.practices[0].anchor.quote, "Original words")
    }
}

private actor SwipeLabCompletionProbe {
    let anchor: SwipeLabAnchor
    var active = 0
    var maximumActive = 0
    var verificationPasses = 0
    init(anchor: SwipeLabAnchor) { self.anchor = anchor }

    func respond(_ prompt: String) async throws -> String {
        if prompt.contains("Inspect every supplied passage") {
            if prompt.contains("FAIL_THIS_SOURCE") { throw SwipeLabError.invalidResponse("Test source failed") }
            active += 1; maximumActive = max(maximumActive, active)
            defer { active -= 1 }
            try await Task.sleep(for: .milliseconds(5))
            let refs = prompt.components(separatedBy: "\n").filter { $0.hasPrefix("REFERENCE E") }
                .compactMap { $0.split(separator: " ").dropFirst().first.map(String.init) }
            let reading = SwipeLabReading(observations: [.init(move: "A concrete opening", explanation: "Sets an expectation", refs: refs)],
                jobs: refs.enumerated().map { .init(ref: $0.element, job: $0.offset == 0 ? "opening" : "proof") }, counterpoint: "This does not establish performance causality")
            return String(data: try JSONEncoder().encode(reading), encoding: .utf8)!
        }
        if prompt.contains("Verify this candidate") { verificationPasses += 1 }
        let answer = SwipeLabAnswerWire(answer: "A bounded observation", findings: [.init(title: "Make the opening concrete", observation: "An explicit promise", mechanism: "Sets an expectation", limitations: "Not causal evidence", transfer: "Use a verified detail", support: [SwipeLabEngine.reference(anchor)], counterevidence: [])])
        return String(data: try JSONEncoder().encode(answer), encoding: .utf8)!
    }
}
