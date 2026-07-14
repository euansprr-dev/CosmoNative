// Tests/CosmoOSTests/ContentPerfImportTests.swift
// The paste-a-URL performance import: platform detection, Apify→sheet field
// mapping, transcript flattening, and the pure aggregation step that lifts
// published transcripts into the client dossier.

import XCTest
@testable import CosmoOS

final class ContentPerfImportTests: XCTestCase {

    // MARK: - Platform detection

    func testDetectPlatformFromURLHost() {
        func platform(_ string: String) -> SocialPlatform? {
            ContentPerfImportService.detectPlatform(from: URL(string: string)!)
        }
        XCTAssertEqual(platform("https://www.instagram.com/reel/ABC123/"), .instagram)
        XCTAssertEqual(platform("https://instagram.com/p/XYZ/"), .instagram)
        XCTAssertEqual(platform("https://www.tiktok.com/@user/video/1"), .tiktok)
        XCTAssertEqual(platform("https://youtu.be/dQw4w9WgXcQ"), .youtube)
        XCTAssertNil(platform("https://example.com/post/1"))
    }

    // MARK: - Field mapping

    func testImportedPostPerfMapsApifyFields() {
        let post = ImportedPost(
            id: "1",
            shortcode: "ABC",
            url: URL(string: "https://instagram.com/reel/ABC/")!,
            contentType: .reel,
            caption: "The hook line",
            thumbnailUrl: nil,
            videoUrl: URL(string: "https://cdn.example/video.mp4"),
            timestamp: Date(timeIntervalSince1970: 0),
            engagement: InstagramEngagement(likesCount: 120, commentsCount: 14, viewsCount: 48_200, sharesCount: 9),
            hashtags: [],
            carouselMediaCount: nil,
            carouselItems: nil,
            locationName: nil,
            ownerUsername: "josh"
        )
        let perf = ImportedPostPerf(platform: .instagram, post: post)
        XCTAssertEqual(perf.views, 48_200)
        XCTAssertEqual(perf.likes, 120)
        XCTAssertEqual(perf.comments, 14)
        XCTAssertEqual(perf.shares, 9)
        XCTAssertEqual(perf.caption, "The hook line")
        XCTAssertEqual(perf.videoURL?.absoluteString, "https://cdn.example/video.mp4")
    }

    func testImportedPostPerfDefaultsMissingViewsToZero() {
        let post = ImportedPost(
            id: "2",
            shortcode: "IMG",
            url: URL(string: "https://instagram.com/p/IMG/")!,
            contentType: .image,
            caption: nil,
            thumbnailUrl: nil,
            videoUrl: nil,
            timestamp: Date(timeIntervalSince1970: 0),
            engagement: InstagramEngagement(likesCount: 30, commentsCount: 2, viewsCount: nil, sharesCount: nil),
            hashtags: [],
            carouselMediaCount: nil,
            carouselItems: nil,
            locationName: nil,
            ownerUsername: "ben"
        )
        let perf = ImportedPostPerf(platform: .instagram, post: post)
        XCTAssertEqual(perf.views, 0)
        XCTAssertNil(perf.shares)
        XCTAssertNil(perf.videoURL)
    }

    // MARK: - Transcript flattening

    func testFlattenedTranscriptOrdersAndSkipsEmptySlides() {
        let result = TranscriptionResult(
            rawSlides: [],
            cleanedSlides: [
                TranscriptSlide(id: UUID(), text: "  ", slideNumber: 2, timestamp: nil, endTimestamp: nil, source: nil),
                TranscriptSlide(id: UUID(), text: "Second beat", slideNumber: 3, timestamp: nil, endTimestamp: nil, source: nil),
                TranscriptSlide(id: UUID(), text: "The hook", slideNumber: 1, timestamp: nil, endTimestamp: nil, source: nil)
            ],
            speechSegments: [],
            contentType: .voiceoverPlusText,
            averageOCRConfidence: 1,
            quality: .accurate,
            warnings: []
        )
        XCTAssertEqual(
            ContentPerfImportService.flattenedTranscript(result),
            "The hook\n\nSecond beat"
        )
    }

    // MARK: - Dossier transcripts

    func testAggregatorPicksPublishedTranscriptOverBodyInTopOrder() {
        var withTranscript = Atom.new(type: .content, title: "Winner", body: "draft body")
        withTranscript.metadata = #"{"publishedTranscript":"what actually shipped","status":"published"}"#

        var bodyOnly = Atom.new(type: .content, title: "Runner-up", body: "the draft text")
        bodyOnly.metadata = #"{"status":"published"}"#

        var empty = Atom.new(type: .content, title: "Silent", body: nil)
        empty.metadata = #"{"status":"published"}"#

        let transcripts = ClientPerfAggregator.transcripts(
            forTop: [bodyOnly.uuid, withTranscript.uuid, empty.uuid],
            from: [withTranscript, bodyOnly, empty]
        )
        XCTAssertEqual(transcripts, ["the draft text", "what actually shipped"])
    }

    // MARK: - Cadence pulses

    private func day(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.startOfDay(for: formatter.date(from: string)!)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func testCadencePulseProjectsMedianGapFromLastPublish() {
        // Publishes every 3 days → median 3 → due 3 days after the last.
        let pulses = ContentCadenceEngine.pulses(
            publishDatesByClient: ["josh": [day("2030-01-01"), day("2030-01-04"), day("2030-01-07"), day("2030-01-10")]],
            clientNames: ["josh": "Josh"],
            today: day("2030-01-11"),
            calendar: utcCalendar
        )
        XCTAssertEqual(pulses.count, 1)
        XCTAssertEqual(pulses.first?.dueDay, day("2030-01-13"))
        XCTAssertEqual(pulses.first?.medianGapDays, 3)
        XCTAssertEqual(pulses.first?.clientName, "Josh")
    }

    func testCadencePulseOverdueClampsToToday() {
        let pulses = ContentCadenceEngine.pulses(
            publishDatesByClient: ["ben": [day("2030-01-01"), day("2030-01-03"), day("2030-01-05"), day("2030-01-07")]],
            clientNames: ["ben": "Ben A"],
            today: day("2030-02-01"),
            calendar: utcCalendar
        )
        XCTAssertEqual(pulses.first?.dueDay, day("2030-02-01"))
    }

    func testCadencePulseSilentUnderFourPublishes() {
        let pulses = ContentCadenceEngine.pulses(
            publishDatesByClient: ["euan": [day("2030-01-01"), day("2030-01-05"), day("2030-01-09")]],
            clientNames: ["euan": "Euan"],
            today: day("2030-01-10"),
            calendar: utcCalendar
        )
        XCTAssertTrue(pulses.isEmpty)
    }

    func testAggregatorCapsTranscriptLength() {
        var atom = Atom.new(type: .content, title: "Long", body: nil)
        let huge = String(repeating: "a", count: ClientPerfAggregator.transcriptCharCap + 500)
        atom.metadata = "{\"publishedTranscript\":\"\(huge)\"}"

        let transcripts = ClientPerfAggregator.transcripts(forTop: [atom.uuid], from: [atom])
        XCTAssertEqual(transcripts.first?.count, ClientPerfAggregator.transcriptCharCap)
    }

    // MARK: - Calendar snapshot (all derivation is pure and tested here)

    private func queueItem(
        title: String,
        scheduledAt: Date? = nil,
        status: String = "draft",
        client: String? = nil,
        publishRecords: [(platform: String, publishedAt: String)] = []
    ) -> ContentQueueItem {
        var atom = Atom.new(type: .content, title: title, body: nil)
        if !publishRecords.isEmpty {
            let records = publishRecords
                .map { #"{"platform":"\#($0.platform)","publishedAt":"\#($0.publishedAt)"}"# }
                .joined(separator: ",")
            atom.metadata = #"{"publishRecords":[\#(records)]}"#
        }
        return ContentQueueItem(
            atom: atom,
            scheduledAt: scheduledAt,
            status: status,
            clientName: client,
            clientUUID: client
        )
    }

    func testSnapshotPlacesScheduledAndPublishedOnTheirDays() {
        let shipped = day("2030-05-05")
        let planned = day("2030-05-20")
        let items = [
            queueItem(title: "Shipped", status: "published", client: "josh",
                      publishRecords: [("instagram", "2030-05-05T09:00:00Z")]),
            queueItem(title: "Planned", scheduledAt: planned, status: "scheduled", client: "josh")
        ]
        let snapshot = ContentCalendarSnapshot.build(
            items: items, perf: [:], monthDates: [shipped, planned],
            today: day("2030-05-10"), calendar: utcCalendar
        )
        XCTAssertEqual(snapshot.entries(on: shipped).map(\.item.title), ["Shipped"])
        XCTAssertTrue(snapshot.entries(on: shipped)[0].isPublished)
        XCTAssertEqual(snapshot.entries(on: planned).map(\.item.title), ["Planned"])
        XCTAssertFalse(snapshot.entries(on: planned)[0].isMissed)
    }

    func testSnapshotRepostShowsHistoryAndPlanTwice() {
        let shipped = day("2030-05-05")
        let repostDay = day("2030-06-08")
        let item = queueItem(
            title: "Winner", scheduledAt: repostDay, status: "published", client: "ben",
            publishRecords: [("instagram", "2030-05-05T09:00:00Z")]
        )
        let snapshot = ContentCalendarSnapshot.build(
            items: [item], perf: [:], monthDates: [shipped, repostDay],
            today: day("2030-05-10"), calendar: utcCalendar
        )
        XCTAssertEqual(snapshot.entries(on: shipped).count, 1)
        XCTAssertFalse(snapshot.entries(on: shipped)[0].isRepost)
        XCTAssertEqual(snapshot.entries(on: repostDay).count, 1)
        XCTAssertTrue(snapshot.entries(on: repostDay)[0].isRepost)
    }

    func testSnapshotMarksMissedAndScoresPastDays() {
        let missedDay = day("2030-05-02")
        let scoredDay = day("2030-05-03")
        let scored = queueItem(
            title: "Scored", status: "published", client: "ben",
            publishRecords: [("instagram", "2030-05-03T09:00:00Z")]
        )
        let missed = queueItem(title: "Missed", scheduledAt: missedDay, status: "scheduled", client: "ben")
        let perf = [scored.id: ContentPerfSnapshot(
            id: nil, contentUuid: scored.id, platform: "instagram",
            views: 5000, likes: 10, comments: 1, shares: 0, saves: 0,
            followsGained: 0, capturedAt: "2030-05-04T00:00:00Z"
        )]
        let snapshot = ContentCalendarSnapshot.build(
            items: [scored, missed], perf: perf, monthDates: [missedDay, scoredDay],
            today: day("2030-05-10"), calendar: utcCalendar
        )
        XCTAssertTrue(snapshot.entries(on: missedDay)[0].isMissed)
        XCTAssertEqual(snapshot.views(on: scoredDay), 5000)
        XCTAssertEqual(snapshot.bestDay, scoredDay)
    }

    func testSnapshotSuppressesPulseWhenClientAlreadyPlanned() {
        let dueDay = day("2030-01-13")
        // Rhythm: every 3 days, last publish Jan 10 → due Jan 13.
        let records: [(String, String)] = [
            ("instagram", "2030-01-01T09:00:00Z"),
            ("instagram", "2030-01-04T09:00:00Z"),
            ("instagram", "2030-01-07T09:00:00Z"),
            ("instagram", "2030-01-10T09:00:00Z")
        ]
        let history = queueItem(title: "History", status: "published", client: "josh", publishRecords: [records[3]])
        // Fake the rhythm through separate published items so all records land.
        let older = records.prefix(3).enumerated().map { index, record in
            queueItem(title: "Old \(index)", status: "published", client: "josh", publishRecords: [record])
        }

        let without = ContentCalendarSnapshot.build(
            items: older + [history], perf: [:], monthDates: [dueDay],
            today: day("2030-01-11"), calendar: utcCalendar
        )
        XCTAssertEqual(without.pulses(on: dueDay).map(\.clientUUID), ["josh"])

        let planned = queueItem(title: "Planned", scheduledAt: dueDay, status: "scheduled", client: "josh")
        let with = ContentCalendarSnapshot.build(
            items: older + [history, planned], perf: [:], monthDates: [dueDay],
            today: day("2030-01-11"), calendar: utcCalendar
        )
        XCTAssertTrue(with.pulses(on: dueDay).isEmpty)
    }
}
