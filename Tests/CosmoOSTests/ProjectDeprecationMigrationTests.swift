import XCTest
@testable import CosmoOS

@MainActor
final class ProjectDeprecationMigrationTests: XCTestCase {
    private var cleanupUUIDs: [String] = []

    override func setUp() async throws {
        try await super.setUp()
        // The project migration is one-shot in production (gated by an app_flags
        // row so it can never destructively re-run against an already-migrated
        // or synced database). Tests exercise the migration directly, so clear
        // the flag first.
        try await CosmoDatabase.shared.asyncWrite { db in
            try db.execute(sql: "DELETE FROM app_flags WHERE key = 'projectsMigratedToThinkspaces'")
        }
    }

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
        let projectTitle = "Project migration fixture \(UUID().uuidString)"
        let project = try await AtomRepository.shared.createProject(
            title: projectTitle,
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

    func testThinkspaceManagerDeletePersistsSoftDelete() async throws {
        let metadata = ThinkspaceMetadata(
            name: "Delete persistence regression \(UUID().uuidString)",
            accentColorHex: "#A8CCE8"
        )
        let atom = Atom.new(
            type: .thinkspace,
            title: metadata.name,
            metadata: try String(data: JSONEncoder().encode(metadata), encoding: .utf8)
        )
        let saved = try await AtomRepository.shared.create(atom)
        cleanupUUIDs.append(saved.uuid)

        await ThinkspaceManager.shared.loadThinkspaces()
        guard let thinkspace = ThinkspaceManager.shared.thinkspaces.first(where: { $0.id == saved.uuid }) else {
            XCTFail("Expected created thinkspace to load")
            return
        }

        await ThinkspaceManager.shared.delete(thinkspace)

        let live = try await AtomRepository.shared.fetch(uuid: saved.uuid)
        XCTAssertNil(live)

        let deleted = try await AtomRepository.shared.fetchAllIncludingDeleted(type: .thinkspace)
            .first { $0.uuid == saved.uuid }
        XCTAssertEqual(deleted?.isDeleted, true)
        XCTAssertFalse(ThinkspaceManager.shared.thinkspaces.contains { $0.id == saved.uuid })
    }
}
