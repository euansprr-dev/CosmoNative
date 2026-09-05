// Tests/CosmoOSTests/PipelineDropPayloadTests.swift
// The board's drop grammar: prefixed payloads only, bare uuids refused,
// and the wire format identical to the Shelf's so board↔calendar drags
// never need an adapter.

import XCTest
@testable import CosmoOS

final class PipelineDropPayloadTests: XCTestCase {

    func testPrefixedPayloadsParse() {
        XCTAssertEqual(PipelineDropPayload.parse("idea:abc-123"), .idea("abc-123"))
        XCTAssertEqual(PipelineDropPayload.parse("content:abc-123"), .content("abc-123"))
        XCTAssertEqual(PipelineDropPayload.parse("  idea:abc-123\n"), .idea("abc-123"), "surrounding whitespace is not part of the uuid")
    }

    /// THE LAW: three vocabularies share the String drop channel. A bare
    /// uuid is a task drag (sidebar, Today spine) or a legacy content drag —
    /// never ours. Refusing lets another destination take it.
    func testBareAndForeignPayloadsAreRefused() {
        XCTAssertNil(PipelineDropPayload.parse("abc-123"))
        XCTAssertNil(PipelineDropPayload.parse(""))
        XCTAssertNil(PipelineDropPayload.parse("idea:"))
        XCTAssertNil(PipelineDropPayload.parse("content:"))
        XCTAssertNil(PipelineDropPayload.parse("task:abc-123"))
        XCTAssertNil(PipelineDropPayload.parse("Idea:abc-123"), "prefixes are exact, not case-folded")
    }

    func testFirstRecognisedPayloadWins() {
        XCTAssertEqual(PipelineDropPayload.first(in: ["some-task-uuid", "content:aaa", "idea:bbb"]), .content("aaa"))
        XCTAssertEqual(PipelineDropPayload.first(in: ["idea:", "idea:bbb"]), .idea("bbb"))
        XCTAssertNil(PipelineDropPayload.first(in: ["some-task-uuid", ""]))
        XCTAssertNil(PipelineDropPayload.first(in: []))
    }

    func testDragStringRoundTripsAndMatchesShelfWireFormat() {
        for payload in [PipelineDropPayload.idea("abc"), .content("xyz")] {
            XCTAssertEqual(PipelineDropPayload.parse(payload.dragString), payload)
        }
        XCTAssertEqual(PipelineDropPayload.idea("abc").dragString, ContentShelfPayload.idea("abc").dragString)
        XCTAssertEqual(PipelineDropPayload.content("xyz").dragString, ContentShelfPayload.content("xyz").dragString)
    }

    func testShelfPayloadReadsPipelineDragStringsBackUnchanged() {
        guard case .idea(let idea) = ContentShelfPayload(string: PipelineDropPayload.idea("abc").dragString) else {
            return XCTFail("the shelf must read a pipeline idea drag as an idea")
        }
        XCTAssertEqual(idea, "abc")
        guard case .content(let content) = ContentShelfPayload(string: PipelineDropPayload.content("xyz").dragString) else {
            return XCTFail("the shelf must read a pipeline content drag as content")
        }
        XCTAssertEqual(content, "xyz")
    }

    func testUUIDAccessor() {
        XCTAssertEqual(PipelineDropPayload.idea("abc").uuid, "abc")
        XCTAssertEqual(PipelineDropPayload.content("xyz").uuid, "xyz")
    }
}
