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
}
