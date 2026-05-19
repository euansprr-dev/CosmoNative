import XCTest
@testable import CosmoOS

@MainActor
final class ProjectDeprecationMigrationTests: XCTestCase {
    private var cleanupUUIDs: [String] = []

    override func tearDown() async throws {
        let uuids = cleanupUUIDs.reversed()
        cleanupUUIDs.removeAll()

        for uuid in uuids {
            try? await AtomRepository.shared.hardDelete(uuid: uuid, confirmed: true)
        }

        await ThinkspaceManager.shared.loadThinkspaces()
        try await super.tearDown()
    }

    func testProjectMigrationMovesColorAndLinksToRootThinkspace() async throws {
        let projectColor = "#A8CCE8"
        let project = try await AtomRepository.shared.createProject(
            title: "Legacy Client Project",
            color: projectColor
        )
        cleanupUUIDs.append(project.uuid)

        guard let rootThinkspaceUUID = project.metadataValue(as: ProjectMetadata.self)?.rootThinkspaceUuid else {
            XCTFail("Expected createProject to create a root Thinkspace")
            return
        }
        cleanupUUIDs.append(rootThinkspaceUUID)

        let linkedAtom = Atom.new(
            type: .idea,
            title: "Migration-linked idea",
            links: [.project(project.uuid)]
        )
        let savedLinkedAtom = try await AtomRepository.shared.create(linkedAtom)
        cleanupUUIDs.append(savedLinkedAtom.uuid)

        try await AtomRepository.shared.migrateProjectsToThinkspaces()

        let migratedLinkedAtom = try await AtomRepository.shared.fetch(uuid: savedLinkedAtom.uuid)
        XCTAssertNil(migratedLinkedAtom?.link(ofType: .project))
        XCTAssertEqual(migratedLinkedAtom?.link(ofType: .thinkspace)?.uuid, rootThinkspaceUUID)

        let migratedRoot = try await AtomRepository.shared.fetch(uuid: rootThinkspaceUUID)
        let migratedRootMetadata = migratedRoot?.metadataValue(as: ThinkspaceMetadata.self)
        XCTAssertEqual(migratedRootMetadata?.accentColorHex, projectColor)
        XCTAssertNil(migratedRootMetadata?.projectUuid)
        XCTAssertFalse(migratedRootMetadata?.isRootThinkspace ?? true)

        let deletedProject = try await AtomRepository.shared.fetch(uuid: project.uuid)
        XCTAssertNil(deletedProject)
    }
}
