// Tests/CosmoOSTests/CanvasAtomObservationHubTests.swift
// Locks the thinkspace-switch data-flow invariants introduced July 2026:
// - The shared observation hub delivers only genuinely NEWER atoms to
//   subscribed block views (version-keyed dedupe — never payload string
//   compares), and a stale batch racing a fresher wake can never regress
//   a subscriber to older content.
// - The warm store serves the switch's batch-fetched atoms synchronously
//   by uuid AND row id, so mounting block views never queue per-block
//   repository round-trips.
// - The targeted resync payload (changedCanvasBlockIds) flags exactly the
//   blocks whose canvas-persisted content changed between the applied
//   cached snapshot and the authoritative fetch.

import XCTest
@testable import CosmoOS

@MainActor
final class CanvasAtomObservationHubTests: XCTestCase {

    private func makeAtom(title: String, updatedAt: String, localVersion: Int64, id: Int64? = nil) -> Atom {
        var atom = Atom.new(type: .note, title: title)
        atom.updatedAt = updatedAt
        atom.localVersion = localVersion
        atom.id = id
        return atom
    }

    // MARK: - Warm store

    func testWarmStoreServesAbsorbedAtomsByUuidAndRowId() {
        let atom = makeAtom(title: "Warm", updatedAt: "2026-07-16T00:00:00Z", localVersion: 1, id: 987_654)
        CanvasAtomObservationHub.shared.absorb([atom])

        XCTAssertEqual(CanvasAtomWarmStore.shared.atom(uuid: atom.uuid)?.title, "Warm")
        XCTAssertEqual(CanvasAtomWarmStore.shared.atom(id: 987_654)?.uuid, atom.uuid)
        XCTAssertNil(CanvasAtomWarmStore.shared.atom(uuid: ""))
        XCTAssertNil(CanvasAtomWarmStore.shared.atom(id: 0))
    }

    // MARK: - Hub delivery

    func testHubDeliversOnlyNewerAtomsAndNeverRegresses() {
        let hub = CanvasAtomObservationHub.shared
        let base = makeAtom(title: "v1", updatedAt: "2026-07-16T00:00:00Z", localVersion: 1)

        // Warm the store first — a subscriber's mount content is warm-store
        // vintage, so subscribing must baseline there (no initial echo).
        hub.absorb([base])

        var delivered: [Atom] = []
        let subscription = hub.subscribe(uuid: base.uuid) { delivered.append($0) }
        defer { hub.unsubscribe(subscription) }

        // Same version again → no delivery (this is the save-echo/dedupe path).
        hub.absorb([base])
        XCTAssertTrue(delivered.isEmpty, "identical version must not be re-delivered")

        // Strictly newer → delivered once.
        var newer = base
        newer.localVersion = 2
        newer.updatedAt = "2026-07-16T00:00:05Z"
        newer.title = "v2"
        hub.absorb([newer])
        XCTAssertEqual(delivered.map(\.title), ["v2"])

        // An older row arriving late (slow batch fetch racing a newer wake)
        // must never overwrite fresher content.
        hub.absorb([base])
        XCTAssertEqual(delivered.map(\.title), ["v2"], "stale atom must not regress a subscriber")
        XCTAssertEqual(CanvasAtomWarmStore.shared.atom(uuid: base.uuid)?.title, "v2",
                       "A remounted editor must also receive the newer version")

        // Same timestamp, different version (rapid same-second local edits)
        // still delivers.
        var sameSecondEdit = newer
        sameSecondEdit.localVersion = 3
        sameSecondEdit.title = "v3"
        hub.absorb([sameSecondEdit])
        XCTAssertEqual(delivered.map(\.title), ["v2", "v3"])
        hub.absorb([newer])
        XCTAssertEqual(delivered.map(\.title), ["v2", "v3"], "Same-second delayed reads must not undo typing")
        XCTAssertEqual(CanvasAtomWarmStore.shared.atom(uuid: base.uuid)?.title, "v3")
    }

    func testHubStopsDeliveringAfterUnsubscribe() {
        let hub = CanvasAtomObservationHub.shared
        let base = makeAtom(title: "v1", updatedAt: "2026-07-16T00:00:00Z", localVersion: 1)
        hub.absorb([base])

        var delivered: [Atom] = []
        let subscription = hub.subscribe(uuid: base.uuid) { delivered.append($0) }
        hub.unsubscribe(subscription)

        var newer = base
        newer.localVersion = 2
        newer.updatedAt = "2026-07-16T00:00:05Z"
        hub.absorb([newer])
        XCTAssertTrue(delivered.isEmpty)
    }

    func testSubscribeRejectsEmptyUuid() {
        XCTAssertNil(CanvasAtomObservationHub.shared.subscribe(uuid: "") { _ in })
    }

    func testDeliverCurrentValueHandsWarmAtomToTheNewSubscriberOnly() {
        let hub = CanvasAtomObservationHub.shared
        let base = makeAtom(title: "current", updatedAt: "2026-07-16T00:00:00Z", localVersion: 1)
        hub.absorb([base])

        // An existing steady-state subscriber must NOT receive an echo when a
        // second subscriber asks for its initial value.
        var steadyDeliveries: [Atom] = []
        let steady = hub.subscribe(uuid: base.uuid) { steadyDeliveries.append($0) }
        defer { hub.unsubscribe(steady) }

        var initialDeliveries: [Atom] = []
        let asking = hub.subscribe(uuid: base.uuid, deliverCurrentValue: true) {
            initialDeliveries.append($0)
        }
        defer { hub.unsubscribe(asking) }

        XCTAssertEqual(initialDeliveries.map(\.title), ["current"], "focus-mode-style subscribers load via their first delivery")
        XCTAssertTrue(steadyDeliveries.isEmpty, "initial delivery must not echo to steady-state subscribers")
    }

    // MARK: - Card text excerpt

    func testCanvasCardExcerptBoundsLongTextAtWordBoundary() {
        let short = "A short draft."
        XCTAssertEqual(CanvasCardTextExcerpt.excerpt(short), short, "under-cap text passes through untouched")

        let long = Array(repeating: "word", count: 3_000).joined(separator: " ")
        let excerpt = CanvasCardTextExcerpt.excerpt(long)
        XCTAssertLessThanOrEqual(excerpt.count, CanvasCardTextExcerpt.maxCharacters + 1)
        XCTAssertTrue(excerpt.hasSuffix("…"))
        XCTAssertFalse(excerpt.dropLast().hasSuffix(" "), "cut lands on a word boundary, not mid-word whitespace")
    }

    // MARK: - Targeted resync payload

    func testChangedCanvasBlockIdsFlagsExactlyTheChangedBlocks() {
        let unchanged = CanvasBlock(
            id: "unchanged", position: .zero,
            entityType: .note, entityId: 1, entityUuid: "u-1",
            title: "Same", metadata: ["content": "same text"]
        )
        var edited = CanvasBlock(
            id: "edited", position: .zero,
            entityType: .stickyNote, entityId: 2, entityUuid: "u-2",
            title: "Sticky", metadata: ["content": "old text"]
        )
        let previous = [unchanged, edited]

        edited.metadata["content"] = "new text"
        // Geometry-only drift must NOT trigger a content resync.
        var moved = unchanged
        moved.position = CGPoint(x: 400, y: 300)
        let added = CanvasBlock(
            id: "added", position: .zero,
            entityType: .note, entityId: 3, entityUuid: "u-3",
            title: "New", metadata: [:]
        )
        let fetched = [moved, edited, added]

        let changed = CanvasView.changedCanvasBlockIds(previous: previous, fetched: fetched)
        XCTAssertEqual(changed, ["edited", "added"])
    }
}
