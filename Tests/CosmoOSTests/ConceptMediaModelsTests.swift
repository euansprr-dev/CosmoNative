// CosmoOS/Tests/CosmoOSTests/ConceptMediaModelsTests.swift
// The concept-media persistence contract: old structured blobs (no media key)
// decode untouched, writers that don't own media never wipe it through the
// merge path, refs written by newer app versions degrade instead of throwing,
// and cover selection is exclusive.

import XCTest
@testable import CosmoOS

final class ConceptMediaModelsTests: XCTestCase {

    // MARK: - Helpers

    private func ref(
        id: UUID = UUID(),
        atomUUID: String? = "atom-1",
        kind: ConnectionMediaItem.Kind = .video,
        anchor: ConnectionSectionType? = nil,
        isCover: Bool = false
    ) -> ConnectionMediaItem {
        ConnectionMediaItem(
            id: id,
            kind: kind,
            atomUUID: atomUUID,
            anchorSection: anchor,
            isCover: isCover
        )
    }

    // MARK: - Structured round-trip

    func testLegacyStructuredWithoutMediaKeyDecodes() throws {
        let sections = [ConnectionSection(type: .goal, items: [ConnectionItem(content: "Ship it")])]
        let legacy = ConnectionStructuredData(sections: sections)
        // Simulate a legacy blob: encode WITHOUT media (nil omits the key).
        let json = try XCTUnwrap(legacy.toJSON())
        XCTAssertFalse(json.contains("\"media\""), "nil media must omit the key entirely")

        let decoded = try XCTUnwrap(ConnectionStructuredData.fromJSON(json))
        XCTAssertNil(decoded.media)
        XCTAssertEqual(decoded.sections.count, ConnectionSectionType.allCases.count)
        XCTAssertEqual(decoded.sections.first { $0.type == .goal }?.items.first?.content, "Ship it")
    }

    func testStructuredMediaRoundTrip() throws {
        let media = [ref(kind: .video), ref(atomUUID: nil, kind: .image)]
        var withAsset = media[1]
        withAsset.assetPath = "/tmp/x.png"
        let data = ConnectionStructuredData(sections: [], media: [media[0], withAsset])
        let json = try XCTUnwrap(data.toJSON())
        let decoded = try XCTUnwrap(ConnectionStructuredData.fromJSON(json))
        XCTAssertEqual(decoded.media?.count, 2)
        XCTAssertEqual(decoded.media?[0].atomUUID, "atom-1")
        XCTAssertEqual(decoded.media?[0].kind, .video)
        XCTAssertEqual(decoded.media?[1].assetPath, "/tmp/x.png")
    }

    /// A sections-only writer merging over an atom that already has media must
    /// leave the media key alone — this is the promotion-service safety line.
    func testSectionsOnlyMergePreservesExistingMedia() throws {
        var atom = Atom.new(type: .connection, title: "T", body: "")
        let withMedia = ConnectionStructuredData(sections: [], media: [ref()])
        atom = atom.mergingStructuredKeys(withMedia)
        XCTAssertTrue(atom.structured?.contains("\"media\"") == true)

        // Second writer: sections only (media nil).
        let sectionsOnly = ConnectionStructuredData(
            sections: [ConnectionSection(type: .claims, items: [ConnectionItem(content: "A claim")])]
        )
        atom = atom.mergingStructuredKeys(sectionsOnly)

        let decoded = try XCTUnwrap(ConnectionStructuredData.fromJSON(XCTUnwrap(atom.structured)))
        XCTAssertEqual(decoded.media?.count, 1, "sections-only write wiped the media key")
        XCTAssertEqual(decoded.sections.first { $0.type == .claims }?.items.count, 1)
    }

    /// An explicitly-empty media array DOES clear the stored key's contents —
    /// detaching the last item must persist.
    func testExplicitEmptyMediaClears() throws {
        var atom = Atom.new(type: .connection, title: "T", body: "")
        atom = atom.mergingStructuredKeys(ConnectionStructuredData(sections: [], media: [ref()]))
        atom = atom.mergingStructuredKeys(ConnectionStructuredData(sections: [], media: []))
        let decoded = try XCTUnwrap(ConnectionStructuredData.fromJSON(XCTUnwrap(atom.structured)))
        XCTAssertEqual(decoded.media?.count, 0)
    }

    // MARK: - Forward tolerance

    func testUnknownKindAndSectionDegradeGracefully() throws {
        let json = """
        {"sections": [], "media": [{
            "id": "6F9619FF-8B86-D011-B42D-00C04FC964FF",
            "kind": "hologram",
            "atomUUID": "atom-9",
            "anchorSection": "sectionFromTheFuture",
            "isCover": true
        }]}
        """
        let decoded = try XCTUnwrap(ConnectionStructuredData.fromJSON(json))
        let item = try XCTUnwrap(decoded.media?.first)
        XCTAssertEqual(item.kind, .image, "unknown kind must degrade to image, not throw")
        XCTAssertNil(item.anchorSection, "unknown section must stay unanchored")
        XCTAssertTrue(item.isCover)
        XCTAssertEqual(item.atomUUID, "atom-9")
    }

    func testMinimalMediaEntryDecodes() throws {
        let json = """
        {"sections": [], "media": [{"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF"}]}
        """
        let decoded = try XCTUnwrap(ConnectionStructuredData.fromJSON(json))
        let item = try XCTUnwrap(decoded.media?.first)
        XCTAssertEqual(item.kind, .image)
        XCTAssertFalse(item.isCover)
        XCTAssertEqual(item.sortOrder, 0)
    }

    // MARK: - Focus-mode state

    func testStateDecodeWithoutMediaKey() throws {
        var state = ConnectionFocusModeState(atomUUID: "c-1")
        state.media = [ref()]
        var encoded = try XCTUnwrap(String(data: JSONEncoder().encode(state), encoding: .utf8))
        // Strip the media key to simulate a pre-media persisted blob.
        let decodedFull = try JSONDecoder().decode(ConnectionFocusModeState.self, from: Data(encoded.utf8))
        XCTAssertEqual(decodedFull.media.count, 1)

        encoded = try XCTUnwrap(String(
            data: JSONEncoder().encode(ConnectionFocusModeState(atomUUID: "c-2")),
            encoding: .utf8
        ))
        XCTAssertNotNil(encoded)
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any]
        )
        object.removeValue(forKey: "media")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decodedLegacy = try JSONDecoder().decode(ConnectionFocusModeState.self, from: legacyData)
        XCTAssertTrue(decodedLegacy.media.isEmpty)
    }

    // MARK: - Mutators

    func testAddMediaStampsSortOrder() {
        var state = ConnectionFocusModeState(atomUUID: "c-1")
        state.addMedia(ref(atomUUID: "a"))
        state.addMedia(ref(atomUUID: "b"))
        state.addMedia(ref(atomUUID: "c"))
        XCTAssertEqual(state.orderedMedia.map(\.atomUUID), ["a", "b", "c"])
        XCTAssertEqual(state.media.map(\.sortOrder), [0, 1, 2])
    }

    func testSetCoverIsExclusiveAndToggles() {
        var state = ConnectionFocusModeState(atomUUID: "c-1")
        let first = ref(atomUUID: "a")
        let second = ref(atomUUID: "b")
        state.addMedia(first)
        state.addMedia(second)

        state.setCoverMedia(id: first.id)
        XCTAssertEqual(state.coverMedia?.id, first.id)

        state.setCoverMedia(id: second.id)
        XCTAssertEqual(state.coverMedia?.id, second.id)
        XCTAssertEqual(state.media.filter(\.isCover).count, 1)

        // Toggling the current cover clears it.
        state.setCoverMedia(id: second.id)
        XCTAssertNil(state.coverMedia)
    }

    func testAnchoredMediaFilter() {
        var state = ConnectionFocusModeState(atomUUID: "c-1")
        state.addMedia(ref(atomUUID: "a", anchor: .examples))
        state.addMedia(ref(atomUUID: "b"))
        XCTAssertEqual(state.media(anchoredTo: .examples).count, 1)
        XCTAssertEqual(state.media(anchoredTo: .claims).count, 0)
    }

    // MARK: - Kind classification

    func testKindClassificationFromAtomFallsBackToImage() {
        let atom = Atom.new(type: .research, title: "Plain article", body: "")
        XCTAssertEqual(ConnectionMediaItem.kind(for: atom), .image)
    }
}
