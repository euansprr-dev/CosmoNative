import XCTest
@testable import CosmoOS

final class LibraryHierarchyTests: XCTestCase {
    func testHomeItemsKeepProjectsAndStandaloneDocumentsButHideProjectOwnedAtomsAndThinkspaces() {
        let project = makeItem(uuid: "project-1", title: "Ben", kind: .project)
        let projectAtom = makeItem(uuid: "project-doc", title: "Draft", kind: .atom, projectUUID: "project-1")
        let standalone = makeItem(uuid: "loose-doc", title: "Loose", kind: .atom)
        let thinkspace = makeItem(uuid: "thinkspace-1", title: "Canvas", kind: .thinkspace, projectUUID: "project-1")

        let result = LibraryHierarchy.homeItems(
            from: [projectAtom, standalone, thinkspace, project],
            projectOwnedAtomUUIDs: ["project-doc"]
        )

        XCTAssertEqual(result.items.map(\.uuid), ["project-1"])
        XCTAssertEqual(result.standalone.map(\.uuid), ["loose-doc"])
    }

    func testProjectFolderShowsThinkspacesClustersAndDirectProjectAtoms() {
        let project = makeItem(uuid: "project-1", title: "Ben", kind: .project)
        let thinkspace = makeItem(uuid: "thinkspace-1", title: "Content Board", kind: .thinkspace, projectUUID: "project-1")
        let cluster = makeItem(uuid: "cluster-1", title: "For review", kind: .cluster, projectUUID: "project-1", thinkspaceUUIDs: ["thinkspace-1"])
        let projectAtom = makeItem(uuid: "project-doc", title: "Draft", kind: .atom, projectUUID: "project-1")
        let otherAtom = makeItem(uuid: "other", title: "Other", kind: .atom)

        let contents = LibraryHierarchy.contents(of: project, in: [otherAtom, projectAtom, cluster, thinkspace])

        XCTAssertEqual(contents.map(\.uuid), ["thinkspace-1", "cluster-1", "project-doc"])
    }

    func testThinkspaceFolderShowsClustersAndMemberAtoms() {
        let thinkspace = makeItem(uuid: "thinkspace-1", title: "Content Board", kind: .thinkspace)
        let cluster = makeItem(uuid: "cluster-1", title: "For review", kind: .cluster, thinkspaceUUIDs: ["thinkspace-1"])
        let member = makeItem(uuid: "doc-1", title: "Doc", kind: .atom, thinkspaceUUIDs: ["thinkspace-1"])
        let other = makeItem(uuid: "doc-2", title: "Other", kind: .atom)

        let contents = LibraryHierarchy.contents(of: thinkspace, in: [other, member, cluster])

        XCTAssertEqual(contents.map(\.uuid), ["cluster-1", "doc-1"])
    }

    func testClusterFolderShowsOnlyResolvedBlockAtomsInClusterOrder() {
        let cluster = makeItem(uuid: "cluster-1", title: "For review", kind: .cluster, clusterBlockUUIDs: ["doc-2", "missing", "doc-1"])
        let first = makeItem(uuid: "doc-1", title: "First", kind: .atom)
        let second = makeItem(uuid: "doc-2", title: "Second", kind: .atom)

        let contents = LibraryHierarchy.contents(of: cluster, in: [first, second])

        XCTAssertEqual(contents.map(\.uuid), ["doc-2", "doc-1"])
    }

    func testClusterInitializerPreservesMembershipAndProvenance() throws {
        let openedAt = Date(timeIntervalSince1970: 1_774_000_000)
        let metadata = ThinkspaceMetadata(
            name: "Content Board",
            lastOpened: openedAt,
            zoomLevel: 1,
            panOffsetX: 0,
            panOffsetY: 0,
            blockIds: ["doc-1", "doc-2"],
            projectUuid: "project-1"
        )
        let metadataData = try JSONEncoder().encode(metadata)
        let metadataJSON = try XCTUnwrap(String(data: metadataData, encoding: .utf8))
        var thinkspaceAtom = Atom.new(type: .thinkspace, title: "Content Board", metadata: metadataJSON)
        thinkspaceAtom.uuid = "thinkspace-1"
        let thinkspace = Thinkspace(from: thinkspaceAtom)
        var project = Atom.new(type: .project, title: "Ben")
        project.uuid = "project-1"
        let cluster = CodableCluster(
            id: "cluster-1",
            name: "For review",
            blockUUIDs: ["doc-2", "doc-1"],
            colorIndex: 2
        )

        let item = LibraryItem(cluster: cluster, thinkspace: thinkspace, project: project)

        XCTAssertEqual(item.kind, .cluster)
        XCTAssertEqual(item.uuid, "cluster-1")
        XCTAssertEqual(item.title, "For review")
        XCTAssertEqual(item.projectUUID, "project-1")
        XCTAssertEqual(item.projectName, "Ben")
        XCTAssertEqual(item.thinkspaceUUIDs, ["thinkspace-1"])
        XCTAssertEqual(item.thinkspaceNames, ["Content Board"])
        XCTAssertEqual(item.clusterBlockUUIDs, ["doc-2", "doc-1"])
        XCTAssertEqual(item.childCount, 2)
        XCTAssertEqual(item.provenanceSummary, "Ben / Content Board")
    }

    private func makeItem(
        uuid: String,
        title: String,
        kind: LibraryItemKind,
        projectUUID: String? = nil,
        thinkspaceUUIDs: [String] = [],
        clusterBlockUUIDs: [String] = []
    ) -> LibraryItem {
        LibraryItem(
            uuid: uuid,
            entityId: 0,
            title: title,
            atomType: kind == .cluster ? .thinkspace : .content,
            icon: kind == .atom ? "doc.text.fill" : "folder.fill",
            color: DS.accent,
            typeName: kind.rawValue,
            relativeDate: "now",
            childCount: clusterBlockUUIDs.count,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            preview: nil,
            thumbnailURL: nil,
            statusBadge: nil,
            kind: kind,
            projectUUID: projectUUID,
            projectName: projectUUID,
            thinkspaceUUIDs: thinkspaceUUIDs,
            thinkspaceNames: [],
            nestedThinkspaceCount: 0,
            blockCount: clusterBlockUUIDs.count,
            clusterBlockUUIDs: clusterBlockUUIDs
        )
    }
}
