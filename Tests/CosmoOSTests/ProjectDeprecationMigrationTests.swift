import XCTest
@testable import CosmoOS

@MainActor
final class ProjectDeprecationMigrationTests: XCTestCase {
    private var cleanupUUIDs: [String] = []

    /// `nonisolated` — read inside the database's Sendable write closures.
    private nonisolated static let migrationFlagKey = "projectsMigratedToThinkspaces"

    /// Runs `body` with the migration's one-shot guard disarmed, re-arming it
    /// immediately afterwards even if `body` throws.
    ///
    /// The guard MUST be down for the shortest possible moment. This suite runs
    /// against the REAL application database, which is shared with any running
    /// instance of the app and with every other suite in the process. While the
    /// flag is absent, ANY of them can trigger
    /// `ThinkspaceManager.loadThinkspaces()` → `migrateLegacyProjectsIfNeeded()`
    /// and re-run a destructive migration that rewrites `.project` links into
    /// thinkspace memberships — silently stripping the link out from under a
    /// concurrent test (this is what made `AtomWindowStandaloneCreationTests`
    /// flaky). Disarming it for a whole setUp/tearDown span, as this suite used
    /// to, left that window open for the entire suite — and, because nothing
    /// restored the flag, for every later run and for the user's own app.
    private func withMigrationGuardDisarmed<T>(_ body: () async throws -> T) async throws -> T {
        try await setMigrationFlag(present: false)
        do {
            let result = try await body()
            try await setMigrationFlag(present: true)
            return result
        } catch {
            try? await setMigrationFlag(present: true)
            throw error
        }
    }

    private func setMigrationFlag(present: Bool) async throws {
        try await CosmoDatabase.shared.asyncWrite { db in
            if present {
                try db.execute(
                    sql: "INSERT OR REPLACE INTO app_flags (key, value, updated_at) VALUES (?, '1', ?)",
                    arguments: [Self.migrationFlagKey, ISO8601.string(from: Date())]
                )
            } else {
                try db.execute(
                    sql: "DELETE FROM app_flags WHERE key = ?",
                    arguments: [Self.migrationFlagKey]
                )
            }
        }
    }

    override func tearDown() async throws {
        let uuids = cleanupUUIDs.reversed()
        cleanupUUIDs.removeAll()

        for uuid in uuids {
            try? await AtomRepository.shared.hardDelete(uuid: uuid, confirmed: true)
        }

        // Belt and braces: `withMigrationGuardDisarmed` already re-arms on both
        // the success and throw paths, but a test that fails an assertion before
        // reaching it must never leave the guard down — a deleted flag primes
        // the user's own app to re-run a destructive migration on next launch.
        try await setMigrationFlag(present: true)

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

        try await withMigrationGuardDisarmed {
            try await AtomRepository.shared.migrateProjectsToThinkspaces()
        }

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
