// Tests/CosmoOSTests/IdeasDeskEngineTests.swift
// The Desk deal is deterministic and explainable: lanes are exclusive,
// ordering is total, scores follow the published table, and why-lines are
// template prose. If a weight changes, these tests change with it — that is
// the point (the deal is a contract, not a vibe).

import XCTest
@testable import CosmoOS

final class IdeasDeskEngineTests: XCTestCase {

    private let now = ISO8601.date(from: "2026-07-25T09:00:00Z") ?? Date()
    private let clientA = "client-a"
    private let clientB = "client-b"

    private func makeIdea(
        uuid: String,
        client: String? = nil,
        status: IdeaStatus = .spark,
        hooks: [String] = [],
        outline: [String] = [],
        body: String? = nil,
        pinned: Bool = false,
        pinnedAt: String? = nil,
        hasResearch: Bool = false,
        createdHoursAgo: Double = 100,
        updatedHoursAgo: Double = 100
    ) -> IdeaGalleryItem {
        IdeaGalleryItem(
            id: uuid,
            atomUUID: uuid,
            entityId: 1,
            title: "Idea \(uuid)",
            body: body,
            status: status,
            contentFormat: nil,
            platform: nil,
            clientName: client,
            clientUUID: client,
            tags: [],
            insightScore: nil,
            matchingSwipeCount: nil,
            suggestedFramework: nil,
            isPinned: pinned,
            contentCount: 0,
            createdAt: ISO8601.string(from: now.addingTimeInterval(-createdHoursAgo * 3600)),
            updatedAt: ISO8601.string(from: now.addingTimeInterval(-updatedHoursAgo * 3600)),
            context: nil,
            hooks: hooks,
            outline: outline,
            pinnedAt: pinnedAt,
            hasResearch: hasResearch
        )
    }

    private func deal(
        _ ideas: [IdeaGalleryItem],
        scheduled: [String: Date] = [:],
        inspiration: Set<String> = [],
        clients: Set<String>? = nil
    ) -> IdeasDeskEngine.Desk {
        IdeasDeskEngine.makeDesk(
            ideas: ideas,
            scheduledDays: scheduled,
            inspiration: inspiration,
            knownClientIds: clients ?? [clientA, clientB],
            now: now
        )
    }

    // MARK: - Lanes are exclusive and complete

    func testLanesAreMutuallyExclusiveAndCoverEveryIdea() {
        let ideas = [
            makeIdea(uuid: "pinned", client: clientA, pinned: true),
            makeIdea(uuid: "scheduled", client: clientA),
            makeIdea(uuid: "unassigned"),
            makeIdea(uuid: "orphan", client: "gone-client"),
            makeIdea(uuid: "candidate", client: clientB, status: .ready),
        ]
        let desk = deal(ideas, scheduled: ["scheduled": now])

        XCTAssertEqual(Set(desk.upNext.map(\.atomUUID)), ["pinned", "scheduled"])
        XCTAssertEqual(Set(desk.sparks.map(\.atomUUID)), ["unassigned", "orphan"])
        XCTAssertEqual(desk.proposalsByClient[clientB]?.map(\.id), ["candidate"])
        XCTAssertNil(desk.proposalsByClient[clientA])

        let total = desk.upNext.count + desk.sparks.count
            + desk.proposalsByClient.values.reduce(0) { $0 + $1.count }
        XCTAssertEqual(total, ideas.count)
    }

    func testScheduledBeatsPinnedBeatsSparksForLaneMembership() {
        // A pinned unassigned idea is committed work, not triage backlog.
        let pinnedUnassigned = makeIdea(uuid: "pinned-unassigned", pinned: true)
        // Scheduled AND pinned lands once, in the scheduled bucket.
        let both = makeIdea(uuid: "both", client: clientA, pinned: true, pinnedAt: ISO8601.string(from: now))
        let desk = deal([pinnedUnassigned, both], scheduled: ["both": now])

        XCTAssertEqual(desk.upNext.map(\.atomUUID), ["both", "pinned-unassigned"])
        XCTAssertTrue(desk.sparks.isEmpty)
    }

    // MARK: - Up next ordering

    func testUpNextOrdersScheduledBySoonestDayThenPinsByRecency() {
        let tomorrow = now.addingTimeInterval(86_400)
        let ideas = [
            makeIdea(uuid: "pin-old", client: clientA, pinned: true, pinnedAt: "2026-07-01T00:00:00Z"),
            makeIdea(uuid: "pin-new", client: clientA, pinned: true, pinnedAt: "2026-07-20T00:00:00Z"),
            makeIdea(uuid: "sched-tomorrow", client: clientA),
            makeIdea(uuid: "sched-today", client: clientA),
        ]
        let desk = deal(ideas, scheduled: ["sched-tomorrow": tomorrow, "sched-today": now])

        XCTAssertEqual(
            desk.upNext.map(\.atomUUID),
            ["sched-today", "sched-tomorrow", "pin-new", "pin-old"]
        )
    }

    // MARK: - Scoring

    func testScoreFollowsThePublishedTable() {
        let ready = makeIdea(uuid: "r", client: clientA, status: .ready, updatedHoursAgo: 30 * 24)
        XCTAssertEqual(IdeasDeskEngine.score(for: ready, inspiration: [], now: now), 3.0)

        let developing = makeIdea(uuid: "d", client: clientA, status: .developing, updatedHoursAgo: 30 * 24)
        XCTAssertEqual(IdeasDeskEngine.score(for: developing, inspiration: [], now: now), 1.5)

        let loaded = makeIdea(
            uuid: "l", client: clientA, status: .ready,
            hooks: ["h1", "h2"], outline: ["s1"], body: "notes",
            updatedHoursAgo: 24
        )
        // ready 3 + hooks 1 + outline 1 + substance 0.5 + inspiration 0.5 + ≤48h 1
        XCTAssertEqual(IdeasDeskEngine.score(for: loaded, inspiration: ["l"], now: now), 7.0)

        let stale = makeIdea(uuid: "s", client: clientA, status: .ready, updatedHoursAgo: 70 * 24)
        XCTAssertEqual(IdeasDeskEngine.score(for: stale, inspiration: [], now: now), 2.5)

        let weekTouch = makeIdea(uuid: "w", client: clientA, updatedHoursAgo: 5 * 24)
        XCTAssertEqual(IdeasDeskEngine.score(for: weekTouch, inspiration: [], now: now), 0.5)
    }

    func testProposalsRankByScoreThenRecencyThenUUIDTotalOrder() {
        let ideas = [
            makeIdea(uuid: "b-spark", client: clientA, updatedHoursAgo: 500),
            makeIdea(uuid: "a-spark", client: clientA, updatedHoursAgo: 500),
            makeIdea(uuid: "c-spark", client: clientA, updatedHoursAgo: 500),
            makeIdea(uuid: "ready", client: clientA, status: .ready, updatedHoursAgo: 500),
        ]
        let first = deal(ideas).proposalsByClient[clientA]?.map(\.id)
        XCTAssertEqual(first, ["ready", "a-spark", "b-spark", "c-spark"])
        // Same input, same deal — the order lock.
        XCTAssertEqual(deal(ideas).proposalsByClient[clientA]?.map(\.id), first)
    }

    // MARK: - Why-lines

    func testWhyLineForReadyIdeaLeadsWithStageAndSubstance() {
        let idea = makeIdea(
            uuid: "w1", client: clientA, status: .ready,
            hooks: ["a", "b", "c"], outline: ["s1"], updatedHoursAgo: 3
        )
        XCTAssertEqual(
            IdeasDeskEngine.whyLine(for: idea, inspiration: [], now: now),
            "Ready to write · 3 hooks · outline set"
        )
    }

    func testWhyLineForFreshSparkSpeaksCaptureAge() {
        let today = makeIdea(uuid: "t", client: clientA, createdHoursAgo: 2)
        XCTAssertEqual(IdeasDeskEngine.whyLine(for: today, inspiration: [], now: now), "Captured today")

        let yesterday = makeIdea(uuid: "y", client: clientA, createdHoursAgo: 30)
        XCTAssertEqual(IdeasDeskEngine.whyLine(for: yesterday, inspiration: [], now: now), "Captured yesterday")

        let week = makeIdea(uuid: "wk", client: clientA, createdHoursAgo: 5 * 24)
        XCTAssertEqual(IdeasDeskEngine.whyLine(for: week, inspiration: ["wk"], now: now), "New this week · from a saved swipe")

        let old = makeIdea(uuid: "o", client: clientA, createdHoursAgo: 400)
        XCTAssertEqual(IdeasDeskEngine.whyLine(for: old, inspiration: [], now: now), "Spark")
    }

    func testWhyLineOldBareSparkAdmitsQuietness() {
        let stale = makeIdea(
            uuid: "stale", client: clientA,
            createdHoursAgo: 60 * 24, updatedHoursAgo: 28 * 24
        )
        XCTAssertEqual(
            IdeasDeskEngine.whyLine(for: stale, inspiration: [], now: now),
            "Spark · quiet for 4w"
        )
    }

    func testWhyLineNotesQuietNonSparksWhenSubstanceLeavesRoom() {
        let quiet = makeIdea(
            uuid: "q", client: clientA, status: .developing,
            hooks: ["a"], updatedHoursAgo: 28 * 24
        )
        XCTAssertEqual(
            IdeasDeskEngine.whyLine(for: quiet, inspiration: [], now: now),
            "In development · 1 hook · quiet for 4w"
        )

        // Two substance signals fill the line — no quiet note.
        let full = makeIdea(
            uuid: "f", client: clientA, status: .developing,
            hooks: ["a"], outline: ["s"], updatedHoursAgo: 28 * 24
        )
        XCTAssertEqual(
            IdeasDeskEngine.whyLine(for: full, inspiration: [], now: now),
            "In development · 1 hook · outline set"
        )
    }

    // MARK: - Digests

    func testDigestsCountThePipelineIncludingCommittedWork() {
        let ideas = [
            makeIdea(uuid: "1", client: clientA, status: .ready, pinned: true),
            makeIdea(uuid: "2", client: clientA, status: .developing),
            makeIdea(uuid: "3", client: clientA),
            makeIdea(uuid: "4", client: clientB, status: .ready),
            makeIdea(uuid: "5"),
        ]
        let desk = deal(ideas)

        XCTAssertEqual(desk.digests[clientA], .init(ready: 1, developing: 1, total: 3))
        XCTAssertEqual(desk.digests[clientB], .init(ready: 1, developing: 0, total: 1))
        XCTAssertEqual(desk.digests.count, 2)
    }
}
