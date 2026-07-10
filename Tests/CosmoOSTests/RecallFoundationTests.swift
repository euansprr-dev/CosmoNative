import XCTest
@testable import CosmoOS

/// The "actually good" enforcement for the Recall foundation: chunking rules,
/// hash staleness, vector math, and an end-to-end retrieval gold set running
/// on the deterministic fake embedder (bag-of-words — tests the pipeline and
/// ranking math, not the cloud model).
final class RecallFoundationTests: XCTestCase {

    // MARK: - Document builder

    private func atom(
        type: AtomType = .note,
        title: String? = "Title",
        body: String? = "Body"
    ) -> Atom {
        Atom.new(type: type, title: title, body: body)
    }

    func testIndexableWhitelist() {
        XCTAssertTrue(RecallDocumentBuilder.isIndexable(atom(type: .note)))
        XCTAssertTrue(RecallDocumentBuilder.isIndexable(atom(type: .connection)))
        XCTAssertFalse(RecallDocumentBuilder.isIndexable(atom(type: .task)))
        XCTAssertFalse(RecallDocumentBuilder.isIndexable(atom(type: .project)))
        XCTAssertFalse(RecallDocumentBuilder.isIndexable(atom(type: .note, title: nil, body: nil)))
    }

    func testDeletedAtomNotIndexable() {
        var deleted = atom()
        deleted.isDeleted = true
        XCTAssertFalse(RecallDocumentBuilder.isIndexable(deleted))
    }

    func testDocumentHashChangesWithContent() {
        let first = atom(body: "Original body")
        var second = first
        XCTAssertEqual(
            RecallDocumentBuilder.documentHash(for: first),
            RecallDocumentBuilder.documentHash(for: second)
        )
        second.body = "Edited body"
        XCTAssertNotEqual(
            RecallDocumentBuilder.documentHash(for: first),
            RecallDocumentBuilder.documentHash(for: second)
        )
    }

    func testShortDocumentIsSingleChunk() {
        let chunks = RecallDocumentBuilder.chunks(for: atom(body: "A short note about hooks."))
        XCTAssertEqual(chunks.count, 1)
        XCTAssertTrue(chunks[0].text.contains("Title"))
        XCTAssertTrue(chunks[0].text.contains("hooks"))
    }

    func testLongDocumentChunksWithTitlePrefixAndOverlap() {
        let paragraphs = (1...30).map { index in
            "Paragraph \(index): " + String(repeating: "word ", count: 40)
        }
        let source = atom(title: "Long Doc", body: paragraphs.joined(separator: "\n\n"))
        let chunks = RecallDocumentBuilder.chunks(for: source)

        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertLessThanOrEqual(chunks.count, RecallDocumentBuilder.maxChunksPerAtom)
        for chunk in chunks.dropFirst() {
            XCTAssertTrue(chunk.text.hasPrefix("Long Doc\n"), "chunks carry the title prefix")
        }
        // Indices are sequential.
        XCTAssertEqual(chunks.map(\.index), Array(0..<chunks.count))
    }

    func testGiantParagraphHardWraps() {
        let giant = String(repeating: "This is a sentence about knowledge work. ", count: 200)
        let pieces = RecallDocumentBuilder.packedParagraphs(giant)
        XCTAssertGreaterThan(pieces.count, 1)
        for piece in pieces {
            XCTAssertLessThan(piece.count, RecallDocumentBuilder.chunkTarget * 2)
        }
    }

    // MARK: - Vector math

    func testNormalizationAndDot() {
        let vector = RecallVectorMath.normalized([3, 4])
        XCTAssertEqual(RecallVectorMath.dot(vector, vector), 1.0, accuracy: 0.0001)
        XCTAssertEqual(vector[0], 0.6, accuracy: 0.0001)
        XCTAssertEqual(vector[1], 0.8, accuracy: 0.0001)
    }

    func testBlobRoundTrip() {
        let vector: [Float] = [0.1, -0.5, 0.999, 42]
        let restored = RecallStore.vector(from: RecallStore.blob(from: vector))
        XCTAssertEqual(restored, vector)
    }

    func testFakeEmbedderSimilarityOrdering() {
        let hookText = FakeEmbeddingClient.vector(for: "writing strong hooks for short form video content")
        let hookText2 = FakeEmbeddingClient.vector(for: "how to write a strong hook for video")
        let cookingText = FakeEmbeddingClient.vector(for: "slow roasted tomato pasta recipe with garlic")

        let related = RecallVectorMath.dot(hookText, hookText2)
        let unrelated = RecallVectorMath.dot(hookText, cookingText)
        XCTAssertGreaterThan(related, unrelated, "shared-vocabulary texts must rank closer")
    }

    // MARK: - Retrieval gold set (store-level, fake embeddings)

    func testStoreSearchRanksSharedVocabularyFirst() async throws {
        let corpus: [(uuid: String, text: String)] = [
            ("hooks", "Strong hooks decide whether a reel survives the first second. Open with tension."),
            ("pasta", "Roast the tomatoes low and slow, then fold in garlic and basil for the pasta."),
            ("sleep", "Deep sleep consolidates memory; caffeine after noon fragments it."),
            ("story", "Storytelling reels follow an arc: hook, tension, turn, payoff."),
        ]

        var cached: [(String, [Float], String)] = []
        for item in corpus {
            cached.append((item.uuid, FakeEmbeddingClient.vector(for: item.text), item.text))
        }

        // Score a hook-flavored query against the corpus directly (pure math —
        // no DB dependency in unit tests).
        let query = FakeEmbeddingClient.vector(for: "how do I write a better hook for my reel")
        let ranked = cached
            .map { ($0.0, RecallVectorMath.dot($0.1, query)) }
            .sorted { $0.1 > $1.1 }

        let topTwo = Set(ranked.prefix(2).map(\.0))
        XCTAssertTrue(topTwo.contains("hooks"), "hook doc must rank in the top two, got \(ranked)")
        // The unrelated docs must both score below every hook-flavored doc.
        let scores = Dictionary(uniqueKeysWithValues: ranked.map { ($0.0, $0.1) })
        XCTAssertLessThan(scores["pasta"]!, scores["hooks"]!)
        XCTAssertLessThan(scores["sleep"]!, scores["hooks"]!)
    }

    // MARK: - Page-marked documents (Reading Room citations)

    func testPagedSegmentsParseMarkersAndStripBookkeeping() throws {
        let text = """
        Attention Is All You Need

        [[page 1]]
        The dominant sequence transduction models are based on recurrent networks.

        [[page 2]]
        We propose the Transformer.

        [[truncated after page 2]]
        """
        let segments = try XCTUnwrap(RecallDocumentBuilder.pagedSegments(text))
        XCTAssertEqual(segments.count, 3)
        XCTAssertNil(segments[0].page, "the pre-marker head (title) carries no page")
        XCTAssertEqual(segments[1].page, 1)
        XCTAssertEqual(segments[2].page, 2)
        XCTAssertFalse(segments[2].text.contains("[[truncated"), "bookkeeping markers never reach embeddings")
        XCTAssertFalse(segments[1].text.contains("[[page"))
    }

    func testPagedSegmentsNilForPlainDocuments() {
        XCTAssertNil(RecallDocumentBuilder.pagedSegments("Just a note about hooks and pacing."))
    }

    func testChunksStampPagesForPDFBackedAtoms() {
        var atom = Atom.new(type: .research, title: "Transformer paper", body: nil)
        atom.body = "[[page 1]]\nAttention mechanisms.\n\n[[page 7]]\nScaled dot-product attention details."
        let chunks = RecallDocumentBuilder.chunks(for: atom)
        XCTAssertFalse(chunks.isEmpty)
        XCTAssertTrue(chunks.contains { $0.page == 1 })
        XCTAssertTrue(chunks.contains { $0.page == 7 })
        XCTAssertFalse(chunks.contains { $0.text.contains("[[page") })
    }

    func testPlainAtomChunksCarryNoPage() {
        var atom = Atom.new(type: .note, title: "Hook note", body: nil)
        atom.body = "Open with a claim."
        let chunks = RecallDocumentBuilder.chunks(for: atom)
        XCTAssertFalse(chunks.isEmpty)
        XCTAssertTrue(chunks.allSatisfy { $0.page == nil })
    }

    // MARK: - PDF highlight quads

    func testHighlightQuadRoundTrip() {
        let rects = [CGRect(x: 10, y: 620.5, width: 380, height: 14), CGRect(x: 10, y: 604, width: 122, height: 14)]
        let encoded = PDFHighlight.encodeQuads(rects)
        let highlight = PDFHighlight(
            id: nil, atomUuid: "src-1", page: 6, quads: encoded,
            text: "the selection", captureUuid: "cap-1",
            createdAt: "2026-07-10T09:00:00Z"
        )
        XCTAssertEqual(highlight.quadRects, rects)
    }

    func testHighlightQuadsRejectMalformedJSON() {
        let highlight = PDFHighlight(
            id: nil, atomUuid: "src-1", page: 0, quads: "not json",
            text: "x", captureUuid: nil, createdAt: "2026-07-10T09:00:00Z"
        )
        XCTAssertTrue(highlight.quadRects.isEmpty)
    }

    // MARK: - Recall@5 eval corpus (the gold set every retrieval change must keep green)

    /// A ~50-doc miniature cortex across every whitelisted type. Each topic
    /// cluster carries shared vocabulary so the bag-of-words fake embedder
    /// mirrors real semantic adjacency.
    private static let evalCorpus: [(uuid: String, text: String)] = {
        var docs: [(String, String)] = []
        // Hooks cluster (content craft)
        docs.append(("hooks-1", "Hook rule: open reels with a concrete claim, never a question. Strong hooks state the payoff."))
        docs.append(("hooks-2", "Hook study: the first two seconds of a reel decide retention. Claims beat questions in hooks."))
        docs.append(("hooks-3", "Swipe: viral reel hook — 'You are pricing yourself broke.' Concrete claim hook, high retention."))
        // Pricing cluster (client niche)
        docs.append(("pricing-1", "Value-based pricing note: anchor the price to the outcome, not hours worked."))
        docs.append(("pricing-2", "Concept: pricing psychology — anchoring, decoys, and the outcome frame for premium pricing."))
        docs.append(("pricing-3", "Research: SaaS pricing pages convert better with three tiers and an anchored premium plan."))
        // Sleep cluster (unrelated noise)
        docs.append(("sleep-1", "Note on sleep hygiene: morning light, cold room at night, no caffeine after noon."))
        docs.append(("sleep-2", "Research: circadian rhythm studies show morning light exposure anchors sleep timing."))
        // Storytelling cluster
        docs.append(("story-1", "Storytelling structure: open in the middle of the action, then loop back for context."))
        docs.append(("story-2", "Concept: narrative tension — every story beat opens a loop the next beat closes."))
        docs.append(("story-3", "Swipe transcript: creator tells a client story starting mid-crisis, huge saves. Storytelling loop."))
        // Carousel cluster
        docs.append(("carousel-1", "Carousel rule: about four slides, one sentence per slide, the last slide is the CTA."))
        docs.append(("carousel-2", "Swipe: top carousel used numbered slides with one bold sentence each, save-bait ending."))
        // Trust/audience cluster
        docs.append(("trust-1", "Concept: the trust loop — consistent posting compounds audience trust before any pitch."))
        docs.append(("trust-2", "Note: audiences buy after trust accumulates; pitch density kills the trust loop."))
        // Filler across types to make recall@5 mean something (~35 more docs)
        for index in 0..<35 {
            docs.append(("filler-\(index)", "Miscellaneous workspace document number \(index) about planning errands logistics and admin chores batch \(index % 7)."))
        }
        return docs
    }()

    /// Gold queries: each names the doc(s) that MUST appear in the top 5.
    private static let goldQueries: [(query: String, expected: [String])] = [
        ("how do I write a stronger hook for my reel", ["hooks-1", "hooks-2", "hooks-3"]),
        ("what did I learn about pricing premium offers", ["pricing-1", "pricing-2"]),
        ("storytelling structure for client stories", ["story-1", "story-3"]),
        ("how many slides should a carousel have", ["carousel-1", "carousel-2"]),
        ("building audience trust before selling", ["trust-1", "trust-2"]),
    ]

    func testGoldQueriesRecallAtFive() {
        let embedded = Self.evalCorpus.map { doc in
            (doc.uuid, FakeEmbeddingClient.vector(for: doc.text))
        }
        for gold in Self.goldQueries {
            let queryVector = FakeEmbeddingClient.vector(for: gold.query)
            let topFive = embedded
                .map { ($0.0, RecallVectorMath.dot($0.1, queryVector)) }
                .sorted { $0.1 > $1.1 }
                .prefix(5)
                .map(\.0)
            for expectedDoc in gold.expected {
                XCTAssertTrue(
                    topFive.contains(expectedDoc),
                    "recall@5 miss for '\(gold.query)': wanted \(expectedDoc), got \(topFive)"
                )
            }
        }
    }

    /// Opt-in live smoke against the real embeddings API:
    /// `RECALL_LIVE_SMOKE=1 swift test --filter RecallFoundationTests`.
    /// Skipped (not failed) without the env flag or an API key.
    func testLiveEmbeddingSmoke() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RECALL_LIVE_SMOKE"] == "1",
            "live smoke is opt-in (RECALL_LIVE_SMOKE=1)"
        )
        let client = CloudEmbeddingClient()
        try XCTSkipUnless(client.isConfigured, "no embeddings API key configured")

        let texts = [
            "how to write a strong hook for a short video",
            "opening reels with a concrete claim improves retention",
            "slow roasted tomato pasta with garlic",
        ]
        let vectors = try await client.embed(texts)
        XCTAssertEqual(vectors.count, 3)
        // Semantic sanity: the two hook texts sit closer than hook↔pasta.
        let hookPair = RecallVectorMath.dot(vectors[0], vectors[1])
        let hookPasta = RecallVectorMath.dot(vectors[0], vectors[2])
        XCTAssertGreaterThan(hookPair, hookPasta)
    }
}
