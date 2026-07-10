import XCTest
@testable import CosmoOS

/// The Margin's intent-query contract: suggestions exist from second zero
/// (title + dek + format + niche), and the draft gist joins as the
/// manuscript grows — opening plus the live tail.
@MainActor
final class ContentMarginModelTests: XCTestCase {

    private func contentAtom(title: String, format: String? = nil) -> Atom {
        var atom = Atom.new(type: .content, title: title)
        if let format {
            // ContentAtomMetadata requires phase + wordCount to decode.
            atom.metadata = "{\"phase\": \"ideation\", \"wordCount\": 0, \"contentFormat\": \"\(format)\"}"
        }
        return atom
    }

    func testIntentQueryColdStartUsesIntentSignalOnly() {
        let atom = contentAtom(title: "Hooks that survive the first second", format: "storytelling_reel")
        var state = ContentFocusModeState(atomUUID: atom.uuid)
        state.coreIdea = "Open with tension, not context"

        let query = ContentMarginModel.intentQuery(atom: atom, state: state, niche: "creator economy")

        XCTAssertTrue(query.contains("Hooks that survive"))
        XCTAssertTrue(query.contains("Open with tension"))
        XCTAssertTrue(query.contains("storytelling_reel"))
        XCTAssertTrue(query.contains("creator economy"))
    }

    func testIntentQueryIncludesDraftGistOnceWriting() {
        let atom = contentAtom(title: "T")
        var state = ContentFocusModeState(atomUUID: atom.uuid)
        let opening = String(repeating: "opening ", count: 40)
        let tail = String(repeating: "closing ", count: 80)
        state.draftContent = opening + tail

        let query = ContentMarginModel.intentQuery(atom: atom, state: state, niche: nil)

        XCTAssertTrue(query.contains("opening"), "gist must include the opening")
        XCTAssertTrue(query.contains("closing"), "gist must include the live tail")
    }

    func testIntentQueryEmptyWhenNoSignal() {
        let atom = Atom.new(type: .content, title: nil)
        let state = ContentFocusModeState(atomUUID: atom.uuid)
        XCTAssertTrue(ContentMarginModel.intentQuery(atom: atom, state: state, niche: nil).isEmpty)
    }

    func testDismissalPersistsPerDocument() {
        let model = ContentMarginModel()
        let uuid = "margin-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: "margin.dismissed.\(uuid)") }

        model.bind(atomUUID: uuid)
        let hit = RecallHit(
            atomUuid: "victim", atomType: .connection, title: "V",
            matchedText: "m", page: nil, score: 0.9,
            vectorSimilarity: 0.9, keywordScore: 0, updatedAt: nil
        )
        model.dismiss(hit)

        let stored = UserDefaults.standard.stringArray(forKey: "margin.dismissed.\(uuid)") ?? []
        XCTAssertTrue(stored.contains("victim"))
    }

    // MARK: - Swipe shelf ranking (semantic × format × engagement)

    private func hit(_ uuid: String, score: Double) -> RecallHit {
        RecallHit(
            atomUuid: uuid, atomType: .research, title: uuid,
            matchedText: "…", page: nil, score: score,
            vectorSimilarity: score, keywordScore: 0, updatedAt: nil
        )
    }

    private func candidate(
        _ uuid: String, score: Double,
        format: ContentFormat? = nil, rate: Double? = nil, own: Bool = false
    ) -> ContentMarginModel.SwipeCandidate {
        ContentMarginModel.SwipeCandidate(
            hit: hit(uuid, score: score),
            format: format,
            engagementRate: rate,
            views: rate == nil ? nil : 10_000,
            isOwnPost: own
        )
    }

    func testFormatMultiplierMatrix() {
        // Exact format beats family, family beats stranger, unknown is neutral.
        XCTAssertEqual(ContentMarginModel.formatMultiplier(intent: .reel, candidate: .reel), 1.0)
        let family = ContentMarginModel.formatMultiplier(intent: .carousel, candidate: .carousel)
        XCTAssertEqual(family, 1.0)
        let stranger = ContentMarginModel.formatMultiplier(intent: .reel, candidate: .newsletter)
        XCTAssertEqual(stranger, 0.6)
        XCTAssertEqual(ContentMarginModel.formatMultiplier(intent: nil, candidate: .reel), 0.8)
        XCTAssertEqual(ContentMarginModel.formatMultiplier(intent: .reel, candidate: nil), 0.8)
    }

    func testEngagementPercentilesWithinSetAndNeutralForMissing() {
        let percentiles = ContentMarginModel.engagementPercentiles([0.02, 0.10, nil, 0.05])
        XCTAssertEqual(percentiles[2], 0.5, "missing numbers rank neutral, never punished")
        XCTAssertLessThan(percentiles[0], percentiles[3])
        XCTAssertLessThan(percentiles[3], percentiles[1])
        XCTAssertEqual(percentiles[1], 1.0, accuracy: 0.001, "best in set = top percentile")
    }

    func testRankRelevanceStillBeatsOffTopicViral() {
        // A perfectly relevant, mediocre performer must beat an off-topic
        // viral swipe: the engagement term only sways within [0.5, 1.0].
        let relevant = candidate("relevant", score: 0.9, format: .reel, rate: 0.01)
        let viral = candidate("viral", score: 0.35, format: .newsletter, rate: 0.25)
        let ranked = ContentMarginModel.rank([relevant, viral], intentFormat: .reel)
        XCTAssertEqual(ranked.first?.hit.atomUuid, "relevant")
    }

    func testRankPrefersMatchingFormatAtEqualRelevance() {
        let matching = candidate("match", score: 0.6, format: .reel, rate: 0.05)
        let strange = candidate("stranger", score: 0.6, format: .newsletter, rate: 0.05)
        let ranked = ContentMarginModel.rank([matching, strange], intentFormat: .reel)
        XCTAssertEqual(ranked.first?.hit.atomUuid, "match")
    }

    func testCompactCountFormatting() {
        XCTAssertEqual(ContentMarginModel.compactCount(842), "842")
        XCTAssertEqual(ContentMarginModel.compactCount(12_400), "12K")
        XCTAssertEqual(ContentMarginModel.compactCount(1_400_000), "1.4M")
    }
}
