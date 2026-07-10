// Tests/CosmoOSTests/ContentPublishAndAggregatesTests.swift
// The ship→measure contracts: publish records key-merge onto content atoms
// without disturbing sibling keys (one record per platform, republish
// replaces), and client aggregates are pure math over latest snapshots.

import XCTest
@testable import CosmoOS

final class ContentPublishAndAggregatesTests: XCTestCase {

    // MARK: - Publish record lens

    private func metadataDict(of atom: Atom) throws -> [String: Any] {
        let data = try XCTUnwrap(atom.metadata?.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testPublishRecordsDecodeFromMetadata() throws {
        var atom = Atom.new(type: .content, title: "Post", body: nil)
        atom.metadata = """
        {"status":"published","publishRecords":[\
        {"platform":"x","url":"https://x.com/p/1","publishedAt":"2026-07-10T09:00:00Z"},\
        {"platform":"linkedin","publishedAt":"2026-07-11T09:00:00Z"}]}
        """
        let records = ContentPublishStore.records(for: atom)
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].platform, "x")
        XCTAssertEqual(records[0].url, "https://x.com/p/1")
        XCTAssertNil(records[1].url)
    }

    func testPublishRecordsAbsentMetadataDecodesEmpty() {
        let atom = Atom.new(type: .content, title: "Post", body: nil)
        XCTAssertTrue(ContentPublishStore.records(for: atom).isEmpty)
    }

    func testPublishOverlayMergePreservesSiblingKeys() throws {
        var atom = Atom.new(type: .content, title: "Post", body: nil)
        atom.metadata = """
        {"scheduledAt":"2026-07-12T09:00:00Z","contentFormat":"storytelling_reel",\
        "inheritedSwipeIds":["s-1"],"someFutureKey":true}
        """
        struct Overlay: Encodable {
            var publishRecords: [ContentPublishRecord]
            var status: String
        }
        let merged = atom.mergingMetadataKeys(Overlay(
            publishRecords: [ContentPublishRecord(platform: "x", url: nil, publishedAt: "2026-07-12T10:00:00Z")],
            status: "published"
        ))
        let dict = try metadataDict(of: merged)
        XCTAssertEqual(dict["status"] as? String, "published")
        XCTAssertEqual(dict["scheduledAt"] as? String, "2026-07-12T09:00:00Z")
        XCTAssertEqual(dict["contentFormat"] as? String, "storytelling_reel")
        XCTAssertEqual(dict["someFutureKey"] as? Bool, true)
        XCTAssertNotNil(dict["publishRecords"])
        // And the lens reads back what the overlay wrote.
        XCTAssertEqual(ContentPublishStore.records(for: merged).first?.platform, "x")
    }

    // MARK: - Aggregate math

    private func snapshot(
        content: String, platform: String = "x",
        views: Int, likes: Int = 0, comments: Int = 0, shares: Int = 0, saves: Int = 0
    ) -> ContentPerfSnapshot {
        ContentPerfSnapshot(
            id: nil, contentUuid: content, platform: platform,
            views: views, likes: likes, comments: comments, shares: shares,
            saves: saves, followsGained: 0,
            capturedAt: "2026-07-10T09:00:00Z"
        )
    }

    func testSummarizeComputesWeightedRateAndReach() {
        let summary = ClientPerfAggregator.summarize([
            snapshot(content: "a", views: 1_000, likes: 100),   // 10% rate
            snapshot(content: "b", views: 9_000, likes: 90)     // 1% rate
        ])
        XCTAssertEqual(summary.totalReach, 10_000)
        // Weighted mean: 190 / 10,000 — NOT the naive mean of 10% and 1%.
        XCTAssertEqual(summary.avgEngagementRate, 0.019, accuracy: 0.0001)
    }

    func testSummarizeTopPostsRankByRateWithViewsFloor() {
        let summary = ClientPerfAggregator.summarize([
            snapshot(content: "fluke", views: 3, likes: 3),          // 100% but under floor
            snapshot(content: "good", views: 1_000, likes: 150),     // 15%
            snapshot(content: "great", views: 500, likes: 100),      // 20%
            snapshot(content: "ok", views: 2_000, likes: 100),       // 5%
            snapshot(content: "meh", views: 4_000, likes: 40)        // 1%
        ])
        XCTAssertEqual(summary.topPerformingPostIds, ["great", "good", "ok"])
    }

    func testSummarizeCombinesPlatformsPerPost() {
        // One post on two platforms: reach sums, and the post ranks by its
        // combined rate.
        let summary = ClientPerfAggregator.summarize([
            snapshot(content: "a", platform: "x", views: 500, likes: 50),
            snapshot(content: "a", platform: "linkedin", views: 500, likes: 100)
        ])
        XCTAssertEqual(summary.totalReach, 1_000)
        XCTAssertEqual(summary.topPerformingPostIds, ["a"])
        XCTAssertEqual(summary.avgEngagementRate, 0.15, accuracy: 0.0001)
    }

    func testSummarizeEmptyIsZero() {
        let summary = ClientPerfAggregator.summarize([])
        XCTAssertEqual(summary.totalReach, 0)
        XCTAssertEqual(summary.avgEngagementRate, 0)
        XCTAssertTrue(summary.topPerformingPostIds.isEmpty)
    }
}
