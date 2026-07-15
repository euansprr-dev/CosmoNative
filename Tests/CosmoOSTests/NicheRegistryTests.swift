import XCTest
@testable import CosmoOS

/// NicheMatcher is the deterministic net under LLM niche classification:
/// exact → alias → fuzzy(≥0.60) → none(create). These tests pin the folding
/// behavior on real fragmentation from the library ("Real Estate Investment"
/// must fold into "Real Estate Investing"; "Real Estate Wholesaling" must
/// NOT). The Railway worker port (cosmo-cloud-agent/src/swipes/niche.ts)
/// mirrors these cases 1:1 — keep both suites in sync.
final class NicheRegistryTests: XCTestCase {

    private func niche(_ value: String, aliases: [String] = [], usage: Int = 0, order: Int = 0) -> CanonicalNiche {
        CanonicalNiche(atomUUID: UUID().uuidString, value: value, aliases: aliases, usageCount: usage, sortOrder: order)
    }

    // MARK: - normalizeKey / cleanedCanonicalLabel

    func testNormalizeKeyCollapsesCaseAndWhitespace() {
        XCTAssertEqual(NicheMatcher.normalizeKey("  Real   Estate\nWholesaling "), "real estate wholesaling")
        XCTAssertEqual(NicheMatcher.normalizeKey("FITNESS"), "fitness")
    }

    func testCleanedCanonicalLabelStripsQuotesAndCollapses() {
        XCTAssertEqual(NicheMatcher.cleanedCanonicalLabel(from: "\"SaaS Marketing\""), "SaaS Marketing")
        XCTAssertEqual(NicheMatcher.cleanedCanonicalLabel(from: "  Health  &\nWellness "), "Health & Wellness")
        // Capitalization is preserved — "SaaS" must not become "Saas".
        XCTAssertEqual(NicheMatcher.cleanedCanonicalLabel(from: "SaaS"), "SaaS")
    }

    func testCleanedCanonicalLabelCapsOnWordBoundary() {
        let long = "Extremely Long Niche Label That Keeps Going And Going Forever"
        let cleaned = NicheMatcher.cleanedCanonicalLabel(from: long)
        XCTAssertLessThanOrEqual(cleaned.count, 48)
        XCTAssertFalse(cleaned.hasSuffix(" "))
        XCTAssertTrue(long.hasPrefix(cleaned))
    }

    // MARK: - candidateKeys (combo splitting)

    func testCandidateKeysSplitsComboLabels() {
        XCTAssertEqual(
            NicheMatcher.candidateKeys(for: "Tax Strategy & Vending Machines"),
            ["tax strategy & vending machines", "tax strategy", "vending machines"]
        )
        XCTAssertEqual(
            NicheMatcher.candidateKeys(for: "Real Estate / Sober Living"),
            ["real estate / sober living", "real estate", "sober living"]
        )
        XCTAssertEqual(
            NicheMatcher.candidateKeys(for: "Real Estate Investing - Airbnb"),
            ["real estate investing - airbnb", "real estate investing", "airbnb"]
        )
        // Simple labels produce just themselves.
        XCTAssertEqual(NicheMatcher.candidateKeys(for: "Fitness"), ["fitness"])
    }

    // MARK: - similarity

    func testSimilarityIdenticalIsOne() {
        XCTAssertEqual(NicheMatcher.similarity("fitness", "fitness"), 1.0)
    }

    func testTokenSubsequenceContainmentScoresHigh() {
        // "real estate investing" ⊂ "airbnb real estate investing" (word-boundary aware)
        let score = NicheMatcher.similarity("real estate investing", "airbnb real estate investing")
        XCTAssertGreaterThanOrEqual(score, NicheMatcher.fuzzyThreshold)
    }

    func testNoRawSubstringFalsePositives() {
        // "ai" appears inside "air travel" as a substring but NOT at a token
        // boundary — must not containment-match.
        XCTAssertLessThan(NicheMatcher.similarity("ai", "air travel"), NicheMatcher.fuzzyThreshold)
        XCTAssertLessThan(NicheMatcher.similarity("fitness", "finance"), NicheMatcher.fuzzyThreshold)
    }

    func testDistinctVerticalsStayBelowThreshold() {
        // The user's core requirement: wholesaling and investing are DIFFERENT
        // niches and must never fold into each other.
        let score = NicheMatcher.similarity("real estate wholesaling", "real estate investing")
        XCTAssertLessThan(score, NicheMatcher.fuzzyThreshold)
    }

    func testIsTokenSubsequence() {
        XCTAssertTrue(NicheMatcher.isTokenSubsequence(["real", "estate"], of: ["real", "estate", "investing"]))
        XCTAssertTrue(NicheMatcher.isTokenSubsequence(["ai", "agency"], of: ["ai", "automation", "agency"]))
        XCTAssertFalse(NicheMatcher.isTokenSubsequence(["estate", "real"], of: ["real", "estate"]))
        XCTAssertFalse(NicheMatcher.isTokenSubsequence([], of: ["real"]))
    }

    // MARK: - bestMatch tiers

    func testExactMatchIsCaseInsensitive() {
        let niches = [niche("Real Estate Wholesaling"), niche("Fitness")]
        XCTAssertEqual(NicheMatcher.bestMatch(raw: "real estate wholesaling", in: niches), .exact(index: 0))
        XCTAssertEqual(NicheMatcher.bestMatch(raw: "FITNESS", in: niches), .exact(index: 1))
    }

    func testAliasMatch() {
        let niches = [
            niche("Health & Wellness", aliases: ["Mental Health & Wellness", "Spiritual Wellness"]),
            niche("Fitness"),
        ]
        XCTAssertEqual(NicheMatcher.bestMatch(raw: "mental health & wellness", in: niches), .alias(index: 0))
    }

    func testFuzzyFoldsNearDuplicates() {
        let niches = [niche("Real Estate Investing"), niche("Fitness")]
        // Historical fragmentation: "Investment" vs "Investing".
        guard case .fuzzy(let index, let score) = NicheMatcher.bestMatch(raw: "Real Estate Investment", in: niches) else {
            return XCTFail("Expected fuzzy match for near-duplicate")
        }
        XCTAssertEqual(index, 0)
        XCTAssertGreaterThanOrEqual(score, NicheMatcher.fuzzyThreshold)
    }

    func testSubNicheFoldsIntoCoreCategory() {
        let niches = [niche("Fitness")]
        guard case .fuzzy(let index, _) = NicheMatcher.bestMatch(raw: "Fitness Coaching", in: niches) else {
            return XCTFail("Expected fuzzy containment fold")
        }
        XCTAssertEqual(index, 0)
    }

    func testComboSegmentMatchesExistingCanonical() {
        let niches = [niche("Vending Machine Business"), niche("Real Estate Investing")]
        // "Tax Strategy & Vending Machine Business" — segment matches exactly.
        XCTAssertEqual(
            NicheMatcher.bestMatch(raw: "Tax Strategy & Vending Machine Business", in: niches),
            .exact(index: 0)
        )
        // Dash-subtitle mashup resolves via its head segment.
        XCTAssertEqual(
            NicheMatcher.bestMatch(raw: "Real Estate Investing - Airbnb", in: niches),
            .exact(index: 1)
        )
    }

    func testFullLabelExactBeatsSegmentExact() {
        // When both the combo and a segment exist as canonicals, the combo wins.
        let niches = [niche("Tax Strategy"), niche("Tax Strategy & Vending Machine Business")]
        XCTAssertEqual(
            NicheMatcher.bestMatch(raw: "tax strategy & vending machine business", in: niches),
            .exact(index: 1)
        )
    }

    func testDistinctNicheReturnsNone() {
        let niches = [niche("Real Estate Wholesaling"), niche("Fitness"), niche("Content Creation")]
        XCTAssertEqual(NicheMatcher.bestMatch(raw: "Quantum Computing", in: niches), .none)
        // Different real-estate vertical stays distinct.
        XCTAssertEqual(NicheMatcher.bestMatch(raw: "Real Estate Investing", in: niches), .none)
    }

    func testEmptyInputs() {
        XCTAssertEqual(NicheMatcher.bestMatch(raw: "", in: [niche("Fitness")]), .none)
        XCTAssertEqual(NicheMatcher.bestMatch(raw: "Fitness", in: []), .none)
    }

    // MARK: - Backfill cluster response parsing

    @MainActor
    func testParseClusterResponseValidatesLabelsAndDedupes() {
        let raw = """
        ```json
        {"niches": [
          {"canonical": "Real Estate Investing", "rawLabels": ["Real Estate Investing", "Real Estate Investment", "Not Submitted Label"]},
          {"canonical": "  \\"Fitness\\"  ", "rawLabels": ["Fitness Coaching", "real estate investment"]}
        ]}
        ```
        """
        let clusters = SwipeNicheBackfill.parseClusterResponse(
            raw,
            validLabels: ["Real Estate Investing", "Real Estate Investment", "Fitness Coaching"]
        )
        XCTAssertEqual(clusters.count, 2)
        // Unsubmitted labels are dropped; duplicates keep their first assignment.
        XCTAssertEqual(clusters[0].canonical, "Real Estate Investing")
        XCTAssertEqual(clusters[0].rawLabels, ["Real Estate Investing", "Real Estate Investment"])
        // Canonical names are cleaned (quotes/whitespace stripped).
        XCTAssertEqual(clusters[1].canonical, "Fitness")
        XCTAssertEqual(clusters[1].rawLabels, ["Fitness Coaching"])
    }

    @MainActor
    func testParseClusterResponseGarbageReturnsEmpty() {
        XCTAssertTrue(SwipeNicheBackfill.parseClusterResponse("not json", validLabels: ["Fitness"]).isEmpty)
        XCTAssertTrue(SwipeNicheBackfill.parseClusterResponse("{\"niches\": []}", validLabels: ["Fitness"]).isEmpty)
    }
}
