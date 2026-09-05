// Tests/CosmoOSTests/PipelineBoardSnapshotTests.swift
// The board deal: an unstaged piece needs evidence of work to leave the
// backlog, phases land in fixed columns, shipped work ages out of the
// window, every column has a total order, filters reach every column, and
// the keyboard cursor walks exactly what is rendered.

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
        stage: ContentProductionStage? = .inProgress,
        wordCount: Int = 120,
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
            wordCount: wordCount,
            updatedAt: date(updatedAt),
            phaseEnteredAt: phaseEnteredAt.map(date),
            editorialStage: stage
        )
    }

    private func build(
        _ content: [PipelineContentItem],
        sessionDaysByContent: [String: Date] = [:],
        perf: [String: ContentPerfSnapshot] = [:],
        filters: PipelineFilters = PipelineFilters(),
        shippedWindowDays: Int = 30
    ) -> PipelineBoardSnapshot {
        PipelineBoardSnapshot.build(
            content: content, sessionDaysByContent: sessionDaysByContent,
            perf: perf, filters: filters,
            shippedWindowDays: shippedWindowDays, today: today, calendar: utc
        )
    }

    private func ids(_ snapshot: PipelineBoardSnapshot, _ column: Column) -> [String] {
        snapshot.cards(in: column).map(\.item.id)
    }

    // MARK: - Columns

    func testEditorialColumnsAreIndependentOfEditorActivity() {
        XCTAssertEqual(Column.column(for: ContentPhase.ideation), .notStarted)
        for phase in [ContentPhase.draft, .polish, .scheduled] {
            XCTAssertEqual(Column.column(for: phase), .inProgress)
        }
        XCTAssertEqual(Column.column(for: ContentPhase.published), .shipped)
        XCTAssertNil(Column.column(for: ContentPhase.archived))
        XCTAssertEqual(Column.contentColumns, [.notStarted, .inProgress, .review, .ready, .shipped])
        XCTAssertEqual(Column.collapsedByDefault, [.notStarted])
    }

    // MARK: - Backlog (evidence of work)

    func testUnstagedPieceNeedsEvidenceOfWorkToLeaveTheBacklog() {
        let untouched = content("untouched", phase: .ideation, stage: nil, wordCount: 0)
        let written = content("written", phase: .ideation, stage: nil, wordCount: 40)
        let dated = content("dated", phase: .ideation, stage: nil, wordCount: 0, scheduledAt: "2030-05-12T09:00:00Z")
        let edited = content("edited", phase: .draft, stage: nil, wordCount: 0)
        let parked = content("parked", phase: .draft, stage: .notStarted, wordCount: 500)
        XCTAssertEqual(untouched.productionStage, .notStarted, "no stage, no words, no date: backlog")
        XCTAssertEqual(written.productionStage, .inProgress, "words on the page are work")
        XCTAssertEqual(dated.productionStage, .inProgress, "a publication date is a commitment")
        XCTAssertEqual(edited.productionStage, .inProgress, "editing activity is work")
        XCTAssertEqual(parked.productionStage, .notStarted, "an explicit stage always wins")

        let snapshot = build([untouched, written, dated, edited, parked])
        XCTAssertEqual(Set(ids(snapshot, .notStarted)), ["untouched", "parked"])
        XCTAssertEqual(Set(ids(snapshot, .inProgress)), ["written", "dated", "edited"])
    }

    func testBookedSessionLiftsOnlyUnstagedPiecesOutOfTheBacklog() {
        let day = date("2030-05-13T00:00:00Z")
        let untouched = content("untouched", phase: .ideation, stage: nil, wordCount: 0)
        let parked = content("parked", phase: .ideation, stage: .notStarted, wordCount: 0)
        let snapshot = build([untouched, parked], sessionDaysByContent: ["untouched": day, "parked": day])
        XCTAssertEqual(ids(snapshot, .inProgress), ["untouched"])
        XCTAssertEqual(ids(snapshot, .notStarted), ["parked"], "a deliberate Not started survives a booked session")
        XCTAssertEqual(snapshot.cards(in: .inProgress).first?.sessionDay, day)
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

    func testFiltersReachEveryColumn() {
        let rows = [
            content("ig-draft", title: "Reel about hooks", phase: .draft, client: "josh", clientName: "Josh", platform: .instagram, format: .reel),
            content("li-draft", title: "Post about hooks", phase: .draft, client: "ben", clientName: "Ben", platform: .linkedin, format: .post),
            content("ig-ship", title: "Shipped reel", phase: .published, client: "josh", clientName: "Josh", platform: .instagram, format: .reel, publishedAt: "2030-05-08T09:00:00Z"),
        ]
        let byPlatform = build(rows, filters: PipelineFilters(platform: .instagram))
        XCTAssertEqual(ids(byPlatform, .inProgress), ["ig-draft"])
        XCTAssertEqual(ids(byPlatform, .shipped), ["ig-ship"])

        let byFormat = build(rows, filters: PipelineFilters(format: .post))
        XCTAssertEqual(ids(byFormat, .inProgress), ["li-draft"])
        XCTAssertTrue(ids(byFormat, .shipped).isEmpty)

        let byQuery = build(rows, filters: PipelineFilters(query: "hooks josh"))
        XCTAssertEqual(ids(byQuery, .inProgress), ["ig-draft"], "tokens match title + client name in any order")
        XCTAssertTrue(ids(byQuery, .shipped).isEmpty)
        let reversed = build(rows, filters: PipelineFilters(query: "JOSH hooks"))
        XCTAssertEqual(ids(reversed, .inProgress), ["ig-draft"])
        XCTAssertTrue(ids(build(rows, filters: PipelineFilters(query: "hook ladder")), .inProgress).isEmpty, "every token must appear")
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
        let snapshot = build(rows)
        XCTAssertEqual(snapshot.cursorOrder.count, Column.allCases.count)
        for (index, column) in Column.allCases.enumerated() {
            let rendered = snapshot.cards(in: column).map(\.id)
            XCTAssertEqual(snapshot.cursorOrder[index], rendered, "\(column) cursor must walk rendered order")
        }
    }

    // MARK: - Session chips + perf

    func testSessionDaysAndPerfRideTheRightCards() {
        let contentDay = date("2030-05-14T00:00:00Z")
        let perf = ContentPerfSnapshot(
            id: nil, contentUuid: "p1", platform: "instagram", views: 900, likes: 10,
            comments: 1, shares: 0, saves: 2, followsGained: 0, capturedAt: "2030-05-09T00:00:00Z"
        )
        let snapshot = build(
            [content("d1", phase: .draft), content("p1", phase: .published, publishedAt: "2030-05-08T09:00:00Z")],
            sessionDaysByContent: ["d1": contentDay],
            perf: ["p1": perf]
        )
        XCTAssertEqual(snapshot.cards(in: .inProgress).first?.sessionDay, contentDay)
        XCTAssertNil(snapshot.cards(in: .shipped).first?.sessionDay)
        XCTAssertEqual(snapshot.cards(in: .shipped).first?.perf?.views, 900)
        XCTAssertNil(snapshot.cards(in: .inProgress).first?.perf)
    }

    func testSnapshotEqualityTracksRenderedState() {
        let rows = [content("d1", phase: .draft)]
        XCTAssertEqual(build(rows), build(rows))
        XCTAssertNotEqual(build(rows), build(rows, sessionDaysByContent: ["d1": today]))
    }
}
