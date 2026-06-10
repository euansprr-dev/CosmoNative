import XCTest
@testable import CosmoOS

final class InboxIdentityTests: XCTestCase {
    func testSectionIdentityIgnoresItemContentChangesButTracksOrder() {
        let first = makeItem(title: "First")
        let second = makeItem(title: "Second")
        var updatedFirst = first
        updatedFirst.title = "First updated"

        XCTAssertEqual(
            InboxSectionIdentity(sections: [
                InboxSection(id: "today", title: "Today", items: [first, second])
            ]),
            InboxSectionIdentity(sections: [
                InboxSection(id: "today", title: "Today renamed", items: [updatedFirst, second])
            ])
        )
        XCTAssertNotEqual(
            InboxSectionIdentity(sections: [
                InboxSection(id: "today", title: "Today", items: [first, second])
            ]),
            InboxSectionIdentity(sections: [
                InboxSection(id: "today", title: "Today", items: [second, first])
            ])
        )
        XCTAssertNotEqual(
            InboxSectionIdentity(sections: [
                InboxSection(id: "today", title: "Today", items: [first, second])
            ]),
            InboxSectionIdentity(sections: [
                InboxSection(id: "older", title: "Older", items: [first, second])
            ])
        )
    }

    func testSoftClusterIdentityTracksClusterIDOrderOnly() {
        let first = makeCluster(id: "place-a", title: "Place A")
        let second = makeCluster(id: "merge-b", title: "Merge B")
        var updatedFirst = makeCluster(
            id: "place-a",
            title: "Place A updated",
            subtitle: "2 captures",
            kind: .merge
        )
        updatedFirst.isCollapsed = true

        XCTAssertEqual(
            InboxSoftClusterIdentity(clusters: [first, second]),
            InboxSoftClusterIdentity(clusters: [updatedFirst, second])
        )
        XCTAssertNotEqual(
            InboxSoftClusterIdentity(clusters: [first, second]),
            InboxSoftClusterIdentity(clusters: [second, first])
        )
    }

    private func makeItem(title: String) -> InboxItem {
        InboxItem.new(
            source: .quickCapture,
            rawText: title,
            title: title
        )
    }

    private func makeCluster(
        id: String,
        title: String,
        subtitle: String = "1 capture",
        kind: InboxSoftClusterKind = .place
    ) -> InboxSoftCluster {
        InboxSoftCluster(
            id: id,
            title: title,
            subtitle: subtitle,
            kind: kind,
            inboxItemIds: [id],
            databaseAtomIds: []
        )
    }
}
