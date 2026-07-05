import XCTest
@testable import CosmoOS

/// The topic-inbox trust contract: a deep dive's INBOX shows only captures the
/// user explicitly routed there; classifier recommendations are suggestions.
final class TopicInboxRoutingTests: XCTestCase {

    // MARK: - Explicit routing marker

    func testMetadataMarkerMakesItemExplicitlyRouted() {
        var item = makeItem()
        XCTAssertFalse(item.isExplicitlyRouted)

        item.metadata = #"{"explicitDestination":"true"}"#
        XCTAssertTrue(item.isExplicitlyRouted)
    }

    func testLegacyPresetSignatureCountsAsExplicit() {
        // Pre-marker Telegram alias captures: full-confidence .place with no
        // recommendation bundle and no rationale.
        var item = makeItem()
        item.classification = .place
        item.confidence = 1.0
        XCTAssertTrue(item.isExplicitlyRouted)
    }

    func testClassifierPlacementIsNotExplicit() {
        // classifyAndStore always writes a recommendation bundle — its
        // placement is a suggestion no matter how confident it is.
        var item = makeItem()
        item.classification = .place
        item.confidence = 1.0
        item.recommendations = #"{"recommendations":[]}"#
        XCTAssertFalse(item.isExplicitlyRouted)
    }

    func testTaxonomyPassPlacementIsNotExplicit() {
        // The taxonomy pass writes a rationale with sub-1.0 confidence.
        var item = makeItem()
        item.classification = .place
        item.confidence = 0.7
        item.rationale = "Filed by the taxonomy pass."
        XCTAssertFalse(item.isExplicitlyRouted)
    }

    // MARK: - Per-topic suppression

    func testSuppressionIsScopedToTheTopic() {
        var item = makeItem()
        item.metadata = #"{"suppressedTopicUUIDs":"topic-a,topic-b"}"#
        XCTAssertTrue(item.isSuppressed(forTopic: "topic-a"))
        XCTAssertTrue(item.isSuppressed(forTopic: "topic-b"))
        XCTAssertFalse(item.isSuppressed(forTopic: "topic-c"))
    }

    func testNoMetadataMeansNothingSuppressed() {
        let item = makeItem()
        XCTAssertFalse(item.isSuppressed(forTopic: "topic-a"))
    }

    // MARK: - Helpers

    private func makeItem() -> InboxItem {
        InboxItem.new(source: .quickCapture, rawText: "A captured thought about growth")
    }
}
