import XCTest
@testable import CosmoOS

/// Version-history rules: when writes snapshot, how retention thins the
/// timeline, and the never-block contract's pure pieces.
final class AtomRevisionTests: XCTestCase {

    private func atom(
        type: AtomType = .note,
        title: String? = "Title",
        body: String? = "Body",
        structured: String? = nil
    ) -> Atom {
        var atom = Atom.new(type: type, title: title, body: body, structured: structured)
        atom.uuid = "test-uuid"
        return atom
    }

    // MARK: - Snapshot policy

    func testIneligibleTypeNeverSnapshots() {
        let previous = atom(type: .task)
        var incoming = previous
        incoming.body = "Changed"
        XCTAssertFalse(AtomRevisionPolicy.shouldSnapshot(
            previous: previous, incoming: incoming, source: .aiApply, lastRevisionAt: nil
        ))
    }

    func testUnchangedContentNeverSnapshots() {
        let previous = atom()
        let incoming = previous
        for source in [RevisionSource.userEdit, .aiApply, .syncApply, .restore] {
            XCTAssertFalse(AtomRevisionPolicy.shouldSnapshot(
                previous: previous, incoming: incoming, source: source, lastRevisionAt: nil
            ), "unchanged content snapshotted for \(source)")
        }
    }

    func testAiApplyAlwaysSnapshotsOnChange() {
        let previous = atom()
        var incoming = previous
        incoming.body = "Body!" // tiny change, seconds after the last revision
        XCTAssertTrue(AtomRevisionPolicy.shouldSnapshot(
            previous: previous, incoming: incoming, source: .aiApply,
            lastRevisionAt: Date().addingTimeInterval(-5)
        ))
    }

    func testSyncApplyAlwaysSnapshotsOnChange() {
        let previous = atom()
        var incoming = previous
        incoming.title = "Renamed"
        XCTAssertTrue(AtomRevisionPolicy.shouldSnapshot(
            previous: previous, incoming: incoming, source: .syncApply,
            lastRevisionAt: Date()
        ))
    }

    func testUserEditFirstRevisionSnapshots() {
        let previous = atom()
        var incoming = previous
        incoming.body = "Body plus a word"
        XCTAssertTrue(AtomRevisionPolicy.shouldSnapshot(
            previous: previous, incoming: incoming, source: .userEdit, lastRevisionAt: nil
        ))
    }

    func testUserEditDebouncesSmallRecentChanges() {
        let previous = atom()
        var incoming = previous
        incoming.body = "Body plus a word" // small delta
        XCTAssertFalse(AtomRevisionPolicy.shouldSnapshot(
            previous: previous, incoming: incoming, source: .userEdit,
            lastRevisionAt: Date().addingTimeInterval(-30) // 30s ago
        ))
    }

    func testUserEditSnapshotsAfterInterval() {
        let previous = atom()
        var incoming = previous
        incoming.body = "Body plus a word"
        XCTAssertTrue(AtomRevisionPolicy.shouldSnapshot(
            previous: previous, incoming: incoming, source: .userEdit,
            lastRevisionAt: Date().addingTimeInterval(-600) // 10 min ago
        ))
    }

    func testUserEditSnapshotsLargeDeltaImmediately() {
        let previous = atom()
        var incoming = previous
        incoming.body = String(repeating: "x", count: 500)
        XCTAssertTrue(AtomRevisionPolicy.shouldSnapshot(
            previous: previous, incoming: incoming, source: .userEdit,
            lastRevisionAt: Date().addingTimeInterval(-10)
        ))
    }

    func testStructuredOnlyChangeCountsAsContent() {
        let previous = atom(structured: "{\"a\":1}")
        var incoming = previous
        incoming.structured = "{\"a\":2}"
        XCTAssertTrue(AtomRevisionPolicy.shouldSnapshot(
            previous: previous, incoming: incoming, source: .aiApply, lastRevisionAt: nil
        ))
    }

    func testBodyCapTruncatesPathologicalBodies() {
        let huge = String(repeating: "a", count: AtomRevisionPolicy.maxStoredBodyLength + 50_000)
        let capped = AtomRevisionPolicy.cappedBody(huge)
        XCTAssertNotNil(capped)
        XCTAssertLessThan(capped!.count, huge.count)
        XCTAssertTrue(capped!.hasSuffix("…[truncated]"))
        XCTAssertEqual(AtomRevisionPolicy.cappedBody("small"), "small")
        XCTAssertNil(AtomRevisionPolicy.cappedBody(nil))
    }

    // MARK: - Retention tiers

    func testRetentionKeepsEverythingUnderADay() {
        let now = Date()
        let dates = (0..<20).map { now.addingTimeInterval(-Double($0) * 3_600) } // hourly, 20h back
        let keep = AtomRevisionPruningPolicy.indicesToKeep(createdAt: dates, now: now)
        XCTAssertEqual(keep.count, dates.count)
    }

    /// Align a date to the start of its retention bucket so offsets can't
    /// straddle an epoch boundary and flake by time of day.
    private func bucketAligned(_ date: Date, bucketSeconds: Double) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / bucketSeconds).rounded(.down) * bucketSeconds)
    }

    func testRetentionThinsWeekOldToHourly() {
        let now = Date()
        // 3 days old, aligned to an hour edge: 4 revisions in ONE hour bucket
        // + 1 two hours later.
        let base = bucketAligned(now.addingTimeInterval(-3 * 86_400), bucketSeconds: 3_600)
        let dates = [
            base, base.addingTimeInterval(60), base.addingTimeInterval(120),
            base.addingTimeInterval(180), base.addingTimeInterval(7_200),
        ]
        let keep = AtomRevisionPruningPolicy.indicesToKeep(createdAt: dates, now: now)
        XCTAssertEqual(keep.count, 2, "one per hour bucket expected, got \(keep.count)")
    }

    func testRetentionThinsMonthOldToDaily() {
        let now = Date()
        let base = bucketAligned(now.addingTimeInterval(-30 * 86_400), bucketSeconds: 86_400)
        let dates = [
            base, base.addingTimeInterval(3_600), base.addingTimeInterval(7_200),
            base.addingTimeInterval(86_400 + 3_600),
        ]
        let keep = AtomRevisionPruningPolicy.indicesToKeep(createdAt: dates, now: now)
        XCTAssertEqual(keep.count, 2, "one per day bucket expected")
    }

    func testRetentionAlwaysKeepsPreDelete() {
        let now = Date()
        let base = now.addingTimeInterval(-30 * 86_400)
        let dates = [base, base.addingTimeInterval(60), base.addingTimeInterval(120)]
        let keep = AtomRevisionPruningPolicy.indicesToKeep(
            createdAt: dates, preDeleteIndices: [2], now: now
        )
        XCTAssertTrue(keep.contains(2), "preDelete revision must survive pruning")
    }

    func testRetentionHardCap() {
        let now = Date()
        // 300 revisions spread over the last 12 hours → all in the keep-everything
        // window, but the hard cap must bite.
        let dates = (0..<300).map { now.addingTimeInterval(-Double($0) * 144) }
        let keep = AtomRevisionPruningPolicy.indicesToKeep(createdAt: dates, now: now)
        XCTAssertLessThanOrEqual(keep.count, AtomRevisionPruningPolicy.hardCapPerAtom)
    }

    // MARK: - Record round-trip

    func testRevisionCapturesAtomFields() {
        var source = atom(title: "T", body: "B", structured: "{\"s\":1}")
        source.metadata = "{\"m\":1}"
        source.links = "[]"
        source.localVersion = 7
        let revision = AtomRevision(of: source, source: .aiApply)
        XCTAssertEqual(revision.atomUuid, source.uuid)
        XCTAssertEqual(revision.type, source.type.rawValue)
        XCTAssertEqual(revision.title, "T")
        XCTAssertEqual(revision.body, "B")
        XCTAssertEqual(revision.structured, "{\"s\":1}")
        XCTAssertEqual(revision.metadata, "{\"m\":1}")
        XCTAssertEqual(revision.links, "[]")
        XCTAssertEqual(revision.localVersion, 7)
        XCTAssertEqual(revision.revisionSource, .aiApply)
        XCTAssertNotNil(ISO8601.date(from: revision.createdAt))
    }
}
