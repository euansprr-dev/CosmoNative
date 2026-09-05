// Tests/CosmoOSTests/PipelineBoardSnapshotTests.swift
// The board deal: phases land in fixed columns, shipped work ages out of
// the window, every column has a total order, filters reach every column,
// grouping is a stable partition, and the keyboard cursor walks exactly
// what is rendered.

import XCTest
@testable import CosmoOS

final class PipelineBoardSnapshotTests: XCTestCase {

    private typealias Column = PipelineBoardSnapshot.Column

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ iso: String) -> Date {
        ISO8601.date(from: iso) ?? .distantPast
    }

    private let today = ISO8601.date(from: "2030-05-10T00:00:00Z")!

    // MARK: - Fixtures

    private func content(
        _ uuid: String,
        title: String? = nil,
        phase: ContentPhase,
        stage: ContentProductionStage = .inProgress,
        client: String? = nil,
        clientName: String? = nil,
        platform: SocialPlatform? = nil,
        format: ContentFormat? = nil,
        scheduledAt: String? = nil,
        publishedAt: String? = nil,
        phaseEnteredAt: String? = nil,
        updatedAt: String = "2030-05-01T09:00:00Z"
    ) -> PipelineContentItem {
        var atom = Atom.new(type: .content, title: title ?? "Piece \(uuid)", body: nil)
        atom.uuid = uuid
        return PipelineContentItem(
            atom: atom,
            phase: phase,
            phaseBeforeSchedule: nil,
            scheduledAt: scheduledAt.map(date),
            status: nil,
            clientUUID: client,
            clientName: clientName ?? client,
            platform: platform,
            format: format?.rawValue,
            sourceIdeaUUID: nil,
            latestPublish: publishedAt.map { ContentPublishRecord(platform: "instagram", url: nil, publishedAt: $0) },
            wordCount: 120,
            updatedAt: date(updatedAt),
            phaseEnteredAt: phaseEnteredAt.map(date),
            editorialStage: stage
        )
    }

    private func idea(
        _ uuid: String,
        title: String? = nil,
        client: String? = nil,
        platform: IdeaPlatform? = nil,
        format: ContentFormat? = nil
    ) -> IdeaGalleryItem {
        IdeaGalleryItem(
            id: uuid, atomUUID: uuid, entityId: 1, title: title ?? "Idea \(uuid)", body: nil,
            status: .spark, contentFormat: format, platform: platform,
            clientName: client, clientUUID: client, tags: [], insightScore: nil,
            matchingSwipeCount: nil, suggestedFramework: nil, isPinned: false, contentCount: 0,
            createdAt: "2030-05-01T09:00:00Z", updatedAt: "2030-05-01T09:00:00Z"
        )
    }

    private func build(
        _ content: [PipelineContentItem],
        ideas: [IdeaGalleryItem] = [],
        sessionDaysByIdea: [String: Date] = [:],
        sessionDaysByContent: [String: Date] = [:],
        perf: [String: ContentPerfSnapshot] = [:],
        filters: PipelineFilters = PipelineFilters(),
        groupByClient: Bool = false,
        shippedWindowDays: Int = 30
    ) -> PipelineBoardSnapshot {
        PipelineBoardSnapshot.build(
            content: content, ideas: ideas,
            sessionDaysByIdea: sessionDaysByIdea, sessionDaysByContent: sessionDaysByContent,
            perf: perf, filters: filters, groupByClient: groupByClient,
            shippedWindowDays: shippedWindowDays, today: today, calendar: utc
        )
    }

    private func ids(_ snapshot: PipelineBoardSnapshot, _ column: Column) -> [String] {
        snapshot.cards(in: column).map(\.item.id)
    }

    // MARK: - Columns

    func testEditorialColumnsAreIndependentOfEditorActivity() {
        for phase in [ContentPhase.ideation, .draft, .polish, .scheduled] {
            XCTAssertEqual(Column.column(for: phase), .inProgress)
        }
        XCTAssertEqual(Column.column(for: ContentPhase.published), .shipped)
        XCTAssertNil(Column.column(for: ContentPhase.archived))
        XCTAssertEqual(Column.contentColumns, [.inProgress, .review, .ready, .shipped])
    }


    func testReadinessDateAndEditorActivityAreOrthogonal() {
        let snapshot = build([
            content("planning", phase: .ideation, scheduledAt: "2030-05-12T09:00:00Z"),
            content("draft", phase: .draft),
            content("review", phase: .polish, stage: .review),
            content("ready", phase: .draft, stage: .ready),
            content("published", phase: .published, publishedAt: "2030-05-08T09:00:00Z"),
            content("archived", phase: .archived)
        ])
        XCTAssertEqual(Set(ids(snapshot, .inProgress)), ["planning", "draft"])
        XCTAssertEqual(ids(snapshot, .review), ["review"])
        XCTAssertEqual(ids(snapshot, .ready), ["ready"])
        XCTAssertEqual(ids(snapshot, .shipped), ["published"])
        XCTAssertEqual(snapshot.archivedCount, 1)
        XCTAssertFalse(snapshot.isEmpty)
        XCTAssertTrue(PipelineBoardSnapshot.empty.isEmpty)
    }


    func testShippedWindowCutsOldPublishesAndFallsBackToPhaseEntry() {
        let snapshot = build([
            content("fresh", phase: .published, publishedAt: "2030-05-01T09:00:00Z"),
            content("edge", phase: .published, publishedAt: "2030-04-10T09:00:00Z"),
            content("stale", phase: .published, publishedAt: "2030-04-09T23:59:00Z"),
            content("noRecord", phase: .published, phaseEnteredAt: "2030-05-03T09:00:00Z"),
            content("noRecordOld", phase: .published, phaseEnteredAt: "2030-03-01T09:00:00Z"),
        ])
        XCTAssertEqual(ids(snapshot, .shipped), ["noRecord", "fresh", "edge"])
        XCTAssertEqual(snapshot.count(in: .shipped), 3)

        let wide = build([content("stale", phase: .published, publishedAt: "2030-04-09T23:59:00Z")], shippedWindowDays: 90)
        XCTAssertEqual(ids(wide, .shipped), ["stale"])
    }

    // MARK: - Ordering

    func testInProgressOrdersNewestEditWithStableTies() {
        let snapshot = build([
            content("old", phase: .draft, updatedAt: "2030-05-01T09:00:00Z"),
            content("new", phase: .ideation, updatedAt: "2030-05-09T09:00:00Z"),
            content("beta", title: "Beta", phase: .polish, updatedAt: "2030-05-05T09:00:00Z"),
            content("alpha", title: "Alpha", phase: .polish, updatedAt: "2030-05-05T09:00:00Z")
        ])
        XCTAssertEqual(ids(snapshot, .inProgress), ["new", "alpha", "beta", "old"])
    }


    func testMissedPublicationIsAnAttentionFlagAcrossReadiness() {
        let snapshot = build([
            content("next", phase: .draft, stage: .ready, scheduledAt: "2030-05-15T09:00:00Z"),
            content("missed", phase: .polish, stage: .ready, scheduledAt: "2030-05-08T09:00:00Z"),
            content("today", phase: .draft, stage: .ready, scheduledAt: "2030-05-10T18:00:00Z"),
            content("undated", phase: .draft, stage: .ready)
        ])
        XCTAssertEqual(snapshot.cards(in: .ready).first?.item.id, "missed")
        XCTAssertEqual(snapshot.cards(in: .ready).filter(\.isMissed).map(\.item.id), ["missed"])
    }


    func testShippedOrdersNewestPublishFirst() {
        let snapshot = build([
            content("first", phase: .published, publishedAt: "2030-05-01T09:00:00Z"),
            content("latest", phase: .analyzing, publishedAt: "2030-05-09T09:00:00Z"),
            content("middle", phase: .published, publishedAt: "2030-05-05T09:00:00Z"),
        ])
        XCTAssertEqual(ids(snapshot, .shipped), ["latest", "middle", "first"])
    }

    // MARK: - Filters

    func testFiltersReachEveryColumnIncludingIdeas() {
        let rows = [
            content("ig-draft", title: "Reel about hooks", phase: .draft, client: "josh", clientName: "Josh", platform: .instagram, format: .reel),
            content("li-draft", title: "Post about hooks", phase: .draft, client: "ben", clientName: "Ben", platform: .linkedin, format: .post),
            content("ig-ship", title: "Shipped reel", phase: .published, client: "josh", clientName: "Josh", platform: .instagram, format: .reel, publishedAt: "2030-05-08T09:00:00Z"),
        ]
        let ideas = [
            idea("idea-ig", title: "Hook ideas", client: "Josh", platform: .instagram, format: .reel),
            idea("idea-li", title: "Career ladder", client: "Ben", platform: .linkedin, format: .post),
        ]

        let byPlatform = build(rows, ideas: ideas, filters: PipelineFilters(platform: .instagram))
        XCTAssertEqual(ids(byPlatform, .inProgress), ["ig-draft"])
        XCTAssertEqual(ids(byPlatform, .shipped), ["ig-ship"])
        XCTAssertEqual(byPlatform.ideas.map(\.item.id), ["idea-ig"])

        let byFormat = build(rows, ideas: ideas, filters: PipelineFilters(format: .post))
        XCTAssertEqual(ids(byFormat, .inProgress), ["li-draft"])
        XCTAssertTrue(ids(byFormat, .shipped).isEmpty)
        XCTAssertEqual(byFormat.ideas.map(\.item.id), ["idea-li"])

        let byQuery = build(rows, ideas: ideas, filters: PipelineFilters(query: "hooks josh"))
        XCTAssertEqual(ids(byQuery, .inProgress), ["ig-draft"], "tokens match title + client name in any order")
        XCTAssertTrue(ids(byQuery, .shipped).isEmpty)
        let reversed = build(rows, ideas: ideas, filters: PipelineFilters(query: "JOSH hooks"))
        XCTAssertEqual(ids(reversed, .inProgress), ["ig-draft"])
        XCTAssertEqual(reversed.ideas.map(\.item.id), [], "\"hooks\" ≠ \"hook\" — every token must appear")

        let ideaQuery = build(rows, ideas: ideas, filters: PipelineFilters(query: "ben ladder"))
        XCTAssertEqual(ideaQuery.ideas.map(\.item.id), ["idea-li"])
        XCTAssertEqual(ideaQuery.ideas.count, 1)
    }

    // MARK: - Grouping

    func testGroupByClientIsAStablePartitionWithUnassignedLast() {
        let rows = [
            content("z1", phase: .draft, client: "zed", clientName: "Zed", updatedAt: "2030-05-09T09:00:00Z"),
            content("u1", phase: .draft, updatedAt: "2030-05-08T09:00:00Z"),
            content("a1", phase: .draft, client: "amy", clientName: "amy", updatedAt: "2030-05-07T09:00:00Z"),
            content("z2", phase: .draft, client: "zed", clientName: "Zed", updatedAt: "2030-05-06T09:00:00Z"),
            content("u2", phase: .draft, updatedAt: "2030-05-05T09:00:00Z"),
            content("a2", phase: .draft, client: "amy", clientName: "amy", updatedAt: "2030-05-04T09:00:00Z"),
        ]
        let grouped = build(rows, groupByClient: true)
        XCTAssertEqual(ids(grouped, .inProgress), ["a1", "a2", "z1", "z2", "u1", "u2"])
        XCTAssertEqual(grouped.cards(in: .inProgress).map(\.clientGroup), ["amy", "amy", "Zed", "Zed", "Unassigned", "Unassigned"])

        let flat = build(rows, groupByClient: false)
        XCTAssertEqual(ids(flat, .inProgress), ["z1", "u1", "a1", "z2", "u2", "a2"])
        XCTAssertTrue(flat.cards(in: .inProgress).allSatisfy { $0.clientGroup == nil })
    }

    // MARK: - Cursor order

    func testCursorOrderMatchesRenderedOrderInEveryColumn() {
        let rows = [
            content("d1", phase: .draft, client: "b", updatedAt: "2030-05-09T09:00:00Z"),
            content("d2", phase: .draft, client: "a", updatedAt: "2030-05-08T09:00:00Z"),
            content("s1", phase: .scheduled, scheduledAt: "2030-05-12T09:00:00Z"),
            content("s2", phase: .scheduled, scheduledAt: "2030-05-02T09:00:00Z"),
            content("p1", phase: .published, publishedAt: "2030-05-08T09:00:00Z"),
        ]
        let ideas = [idea("i2"), idea("i1")]
        for groupByClient in [false, true] {
            let snapshot = build(rows, ideas: ideas, groupByClient: groupByClient)
            XCTAssertEqual(snapshot.cursorOrder.count, Column.allCases.count)
            for (index, column) in Column.allCases.enumerated() {
                let rendered = snapshot.cards(in: column).map(\.id)
                XCTAssertEqual(snapshot.cursorOrder[index], rendered, "\(column) cursor must walk rendered order (group=\(groupByClient))")
            }
            XCTAssertFalse(snapshot.cursorOrder.flatMap { $0 }.contains { $0.hasPrefix("idea:") })
        }
    }

    // MARK: - Session chips + perf

    func testSessionDaysComeFromBothMapsAndPerfRidesShippedCards() {
        let ideaDay = date("2030-05-13T00:00:00Z")
        let contentDay = date("2030-05-14T00:00:00Z")
        let perf = ContentPerfSnapshot(
            id: nil, contentUuid: "p1", platform: "instagram", views: 900, likes: 10,
            comments: 1, shares: 0, saves: 2, followsGained: 0, capturedAt: "2030-05-09T00:00:00Z"
        )
        let snapshot = build(
            [content("d1", phase: .draft), content("p1", phase: .published, publishedAt: "2030-05-08T09:00:00Z")],
            ideas: [idea("i1"), idea("i2")],
            sessionDaysByIdea: ["i1": ideaDay],
            sessionDaysByContent: ["d1": contentDay],
            perf: ["p1": perf]
        )
        XCTAssertEqual(snapshot.ideas.map(\.sessionDay), [ideaDay, nil])
        XCTAssertEqual(snapshot.cards(in: .inProgress).first?.sessionDay, contentDay)
        XCTAssertNil(snapshot.cards(in: .shipped).first?.sessionDay)
        XCTAssertEqual(snapshot.cards(in: .shipped).first?.perf?.views, 900)
        XCTAssertNil(snapshot.cards(in: .inProgress).first?.perf)
    }

    // MARK: - Ideas order

    func testIdeasKeepInputOrderEvenWhenGrouping() {
        let ideas = [idea("c", client: "zed"), idea("a"), idea("b", client: "amy")]
        XCTAssertEqual(build([], ideas: ideas).ideas.map(\.item.id), ["c", "a", "b"])
        XCTAssertEqual(build([], ideas: ideas, groupByClient: true).ideas.map(\.item.id), ["c", "a", "b"])
        XCTAssertEqual(build([], ideas: ideas).ideas.map(\.id), ["idea:c", "idea:a", "idea:b"])
        XCTAssertEqual(build([], ideas: ideas).ideas.count, 3)
    }

    func testSnapshotEqualityTracksRenderedState() {
        let rows = [content("d1", phase: .draft)]
        XCTAssertEqual(build(rows), build(rows))
        XCTAssertNotEqual(build(rows), build(rows, sessionDaysByContent: ["d1": today]))
        XCTAssertNotEqual(build(rows, ideas: [idea("i1")]), build(rows, ideas: [idea("i1", title: "Renamed")]))
    }
}
