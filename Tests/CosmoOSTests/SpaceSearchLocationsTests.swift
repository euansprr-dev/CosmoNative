import XCTest
@testable import CosmoOS

final class SpaceSearchLocationsTests: XCTestCase {
    func testAuthoredPathWinsOverDirectMembershipAndRetainsEverySpace() {
        let nodes = [
            SpaceSearchNode(uuid: "space-a", title: "Alpha", type: "thinkspace"),
            SpaceSearchNode(uuid: "space-b", title: "Beta", type: "thinkspace"),
            SpaceSearchNode(uuid: "book", title: "Handbook", type: "note"),
            SpaceSearchNode(uuid: "chapter", title: "Sleep", type: "note", parentUUID: "book"),
            SpaceSearchNode(uuid: "page", title: "Pressure", type: "note", parentUUID: "chapter")
        ]
        let index = SpaceSearchLocationIndex.build(requestedIDs: ["page"], nodes: nodes,
            memberships: ["page": ["space-a", "space-b"], "book": ["space-a"]])
        XCTAssertEqual(index["page"]?.map(\.spaceID), ["space-a", "space-b"])
        XCTAssertEqual(index["page"]?.first?.ancestorUUIDs, ["book", "chapter"])
        XCTAssertEqual(index["page"]?.first?.breadcrumb, "Alpha › Handbook › Sleep")
    }

    func testOverlappingGroupMembershipRetainsTheRicherAuthoredPath() {
        let nodes = [
            SpaceSearchNode(uuid: "space", title: "Study", type: "thinkspace"),
            SpaceSearchNode(uuid: "group", title: "Reading", type: "note", isGroup: true, memberUUIDs: ["book", "page"]),
            SpaceSearchNode(uuid: "book", title: "Handbook", type: "note"),
            SpaceSearchNode(uuid: "page", title: "Chapter", type: "note", parentUUID: "book")
        ]
        let index = SpaceSearchLocationIndex.build(requestedIDs: ["page"], nodes: nodes, memberships: ["group": ["space"]])
        XCTAssertEqual(index["page"]?.first?.breadcrumb, "Study › Reading › Handbook")
        XCTAssertEqual(index["page"]?.first?.ancestorUUIDs, ["group", "book"])
        let reordered = SpaceSearchLocationIndex.build(requestedIDs: ["page"], nodes: Array(nodes.reversed()), memberships: ["group": ["space"]])
        XCTAssertEqual(index, reordered)
    }

    func testGroupCyclesTerminateAndOnlyCanonicalCommandCenterIsHidden() {
        let center = SpaceSearchLocationIndex.commandCenterID
        let nodes = [
            SpaceSearchNode(uuid: center, title: "Home", type: "thinkspace"),
            SpaceSearchNode(uuid: "user-space", title: "Command Center research", type: "thinkspace"),
            SpaceSearchNode(uuid: "a", title: "A", type: "note", isGroup: true, memberUUIDs: ["b", "source"]),
            SpaceSearchNode(uuid: "b", title: "B", type: "note", isGroup: true, memberUUIDs: ["a"]),
            SpaceSearchNode(uuid: "source", title: "Source", type: "research")
        ]
        let index = SpaceSearchLocationIndex.build(requestedIDs: ["source", "missing", "user-space"], nodes: nodes,
            memberships: ["b": ["user-space", center]])
        XCTAssertEqual(index["source"]?.map(\.spaceID), ["user-space"])
        XCTAssertEqual(index["source"]?.first?.breadcrumb, "Command Center research › B › A")
        XCTAssertNil(index["missing"]); XCTAssertNil(index["user-space"])
    }
}
