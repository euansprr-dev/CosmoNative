// CosmoOS/Tests/CosmoOSTests/ObjectionHandlingTests.swift
// The objection-handling + note-merge contracts: handling rides ConnectionItem
// through tolerant decode, the serializer exposes it as a read-only line the
// apply paths can't touch, and the merge composer builds a concrete
// collaborator message (never an unbounded dump).

import XCTest
@testable import CosmoOS

final class ObjectionHandlingTests: XCTestCase {

    // MARK: - Model round-trip

    func testItemWithHandlingRoundTrips() throws {
        var item = ConnectionItem(content: "People will game the metric")
        item.handling = ObjectionHandling(
            text: "We rotate the metric quarterly",
            linkedRefs: [ConnectionBoardItemRef(section: .examples, itemID: UUID())]
        )
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ConnectionItem.self, from: data)
        XCTAssertTrue(decoded.isHandled)
        XCTAssertEqual(decoded.handling?.text, "We rotate the metric quarterly")
        XCTAssertEqual(decoded.handling?.linkedRefs.first?.section, .examples)
    }

    func testLegacyItemWithoutHandlingDecodes() throws {
        let json = """
        {"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "content": "Old objection",
         "createdAt": 700000000.0, "updatedAt": 700000000.0}
        """
        let decoded = try JSONDecoder().decode(ConnectionItem.self, from: Data(json.utf8))
        XCTAssertNil(decoded.handling)
        XCTAssertFalse(decoded.isHandled)
    }

    func testUnknownRefSectionStaysUnresolvedNotFatal() throws {
        let json = """
        {"text": "answered", "linkedRefs": [
            {"section": "sectionFromTheFuture", "itemID": "6F9619FF-8B86-D011-B42D-00C04FC964FF"}
        ]}
        """
        let decoded = try JSONDecoder().decode(ObjectionHandling.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.linkedRefs.count, 1)
        XCTAssertNil(decoded.linkedRefs.first?.section)
    }

    func testEmptyHandlingIsEmpty() {
        XCTAssertTrue(ObjectionHandling(text: "   ").isEmpty)
        XCTAssertFalse(ObjectionHandling(text: "no").isEmpty)
        XCTAssertFalse(
            ObjectionHandling(text: "", linkedRefs: [ConnectionBoardItemRef(section: .claims, itemID: UUID())]).isEmpty
        )
    }

    // MARK: - Serializer

    private func sections(objection: ConnectionItem, example: ConnectionItem) -> [ConnectionSection] {
        ConnectionSectionType.allCases.sorted { $0.sortOrder < $1.sortOrder }.map { type in
            var section = ConnectionSection(type: type)
            if type == .beliefsObjections { section.addItem(objection) }
            if type == .examples { section.addItem(example) }
            return section
        }
    }

    func testSerializerEmitsHandledLineWithResolvedLink() {
        let example = ConnectionItem(content: "The IKEA effect demo")
        var objection = ConnectionItem(content: "Nobody values what they didn't build")
        objection.handling = ObjectionHandling(
            text: "Ownership transfers through co-creation",
            linkedRefs: [ConnectionBoardItemRef(section: .examples, itemID: example.id)]
        )
        let model = ConnectionSurfaceSerializer.serialize(
            title: "T", conceptType: .framework,
            sections: sections(objection: objection, example: example)
        )
        XCTAssertTrue(model.text.contains("↳ handled: Ownership transfers through co-creation"))
        XCTAssertTrue(model.text.contains("answered by Examples: \"The IKEA effect demo\""))
    }

    func testHandledLineIsMetaAndAddsNoAnchors() {
        let example = ConnectionItem(content: "Demo")
        var objection = ConnectionItem(content: "Objection")
        objection.handling = ObjectionHandling(text: "Response")
        let handled = ConnectionSurfaceSerializer.serialize(
            title: "T", conceptType: .framework,
            sections: sections(objection: objection, example: example)
        )
        objection.handling = nil
        let open = ConnectionSurfaceSerializer.serialize(
            title: "T", conceptType: .framework,
            sections: sections(objection: objection, example: example)
        )
        XCTAssertEqual(handled.anchors.map(\.id), open.anchors.map(\.id))
        for line in handled.lines {
            if case .item = line.kind {
                XCTAssertFalse(String(handled.text[line.range]).contains("↳"))
            }
        }
    }

    func testDeletedLinkTargetRendersMissingEntry() {
        var objection = ConnectionItem(content: "Objection")
        objection.handling = ObjectionHandling(
            text: "See the example",
            linkedRefs: [ConnectionBoardItemRef(section: .examples, itemID: UUID())]
        )
        let line = ConnectionSurfaceSerializer.handlingLine(
            objection.handling!,
            sections: [ConnectionSection(type: .examples)]
        )
        XCTAssertTrue(line.contains("Examples (missing entry)"))
    }

    // MARK: - Staging resolver (handle_objection)

    func testMatchObjectionResolvesPartialQuotes() {
        let items = [
            ConnectionItem(content: "People will game any metric you publish"),
            ConnectionItem(content: "This only works for solo founders")
        ]
        XCTAssertEqual(
            ObjectionStagingResolver.matchObjection(quote: "game any metric", in: items)?.id,
            items[0].id
        )
        // A full quote with smart quotes normalized still lands.
        XCTAssertEqual(
            ObjectionStagingResolver.matchObjection(
                quote: "This only works for solo founders",
                in: items
            )?.id,
            items[1].id
        )
        XCTAssertNil(ObjectionStagingResolver.matchObjection(quote: "??", in: items), "tiny quotes never guess")
        XCTAssertNil(ObjectionStagingResolver.matchObjection(quote: "completely unrelated", in: items))
    }

    func testResolveLinkedEntriesFindsRefsAndReportsMisses() {
        let example = ConnectionItem(content: "The IKEA effect demo from the workshop")
        var examples = ConnectionSection(type: .examples)
        examples.addItem(example)
        var objections = ConnectionSection(type: .beliefsObjections)
        objections.addItem(ConnectionItem(content: "The IKEA effect demo from the workshop"))

        let resolved = ObjectionStagingResolver.resolveLinkedEntries(
            ["IKEA effect demo", "nothing like this exists"],
            sections: [objections, examples]
        )
        XCTAssertEqual(resolved.refs.count, 1)
        XCTAssertEqual(resolved.refs.first?.section, .examples, "objections' own section is never a link target")
        XCTAssertEqual(resolved.refs.first?.itemID, example.id)
        XCTAssertEqual(resolved.unmatched, ["nothing like this exists"])
    }

    // MARK: - Merge composer

    func testMergeMessageCarriesTitleBodyAndContract() throws {
        let message = ConceptNoteMergeComposer.mergeMessage(
            noteTitle: "Retention ideas",
            noteBody: "People stay for identity, not features.\nStreaks are identity scaffolding.",
            sourceKind: .note
        )
        XCTAssertTrue(message.hasPrefix("/concept "))
        XCTAssertTrue(message.contains("NOTE — Retention ideas:"))
        XCTAssertTrue(message.contains("identity scaffolding"))
        XCTAssertTrue(message.contains("never add a claim"))
        XCTAssertTrue(message.contains("ONE"))
    }

    func testMergeMessageStickyVariantAndTruncation() {
        let longBody = String(repeating: "x", count: ConceptNoteMergeComposer.bodyCharacterCap + 500)
        let message = ConceptNoteMergeComposer.mergeMessage(
            noteTitle: nil, noteBody: longBody, sourceKind: .stickyNote
        )
        XCTAssertTrue(message.contains("sticky note"))
        XCTAssertTrue(message.contains("STICKY NOTE:"))
        XCTAssertTrue(message.contains("[…note truncated for length]"))
        XCTAssertLessThan(message.count, ConceptNoteMergeComposer.bodyCharacterCap + 1200)
    }

    func testMergePayloadGates() {
        var note = Atom.new(type: .note, title: "  ", body: "   ")
        XCTAssertNil(ConceptNoteMergeComposer.mergePayload(from: note), "empty note must not offer a merge")

        note.body = "A real thought"
        let payload = ConceptNoteMergeComposer.mergePayload(from: note)
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.displayTitle, "Untitled note")

        let research = Atom.new(type: .research, title: "Swipe", body: "body")
        XCTAssertNil(ConceptNoteMergeComposer.mergePayload(from: research), "only notes and stickies merge")
    }
}
