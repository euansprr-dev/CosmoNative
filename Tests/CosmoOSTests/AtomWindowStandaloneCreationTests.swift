import XCTest
import GRDB
@testable import CosmoOS

@MainActor
final class AtomWindowStandaloneCreationTests: XCTestCase {
    private var createdUUIDs: [String] = []
    private let defaults = UserDefaults.standard
    private let lastAtomKey = "atomWindowLastAtomUUID"
    private var originalLastAtomUUID: String?

    override func setUp() {
        super.setUp()
        originalLastAtomUUID = defaults.string(forKey: lastAtomKey)
    }

    override func tearDown() {
        let uuids = createdUUIDs.reversed()
        createdUUIDs.removeAll()

        for uuid in uuids {
            try? AtomRepository.shared.hardDelete(uuid: uuid, confirmed: true)
        }

        if let originalLastAtomUUID {
            defaults.set(originalLastAtomUUID, forKey: lastAtomKey)
        } else {
            defaults.removeObject(forKey: lastAtomKey)
        }
        super.tearDown()
    }

    func testCreateNewAtomPersistsStandaloneRecordsForSupportedTypes() async throws {
        let viewModel = AtomWindowViewModel()
        let supportedTypes: [AtomType] = [.idea, .note, .content, .research, .connection]

        for type in supportedTypes {
            await viewModel.createNewAtom(type: type)

            guard let currentAtom = viewModel.currentAtom else {
                XCTFail("Expected current atom after creating \(type.rawValue)")
                return
            }

            createdUUIDs.append(currentAtom.uuid)
            XCTAssertEqual(currentAtom.type, type)

            let persisted = try await AtomRepository.shared.fetch(uuid: currentAtom.uuid)
            XCTAssertEqual(persisted?.uuid, currentAtom.uuid)
            XCTAssertEqual(persisted?.type, type)

            let canvasBlockCount = try await canvasBlockCount(for: currentAtom.uuid)
            XCTAssertEqual(canvasBlockCount, 0, "Standalone Atom Window creation should not create canvas blocks")
        }
    }

    func testRestoreLastSessionFetchesPersistedStandaloneAtom() async throws {
        let creator = AtomWindowViewModel()
        await creator.createNewAtom(type: .note)

        guard let created = creator.currentAtom else {
            XCTFail("Expected note to be created")
            return
        }
        createdUUIDs.append(created.uuid)

        creator.saveSession()

        let restoredViewModel = AtomWindowViewModel()
        await restoredViewModel.restoreLastSession()

        XCTAssertEqual(restoredViewModel.currentAtom?.uuid, created.uuid)

        let persisted = try await AtomRepository.shared.fetch(uuid: created.uuid)
        XCTAssertNotNil(persisted)
        XCTAssertTrue(restoredViewModel.recentAtoms.contains(where: { $0.uuid == created.uuid }))
    }

    func testLibraryShowsStandaloneAtomsInDedicatedHomeSection() async throws {
        let atom = try await AtomRepository.shared.create(type: .idea, title: "Standalone Library Idea")
        createdUUIDs.append(atom.uuid)

        let libraryViewModel = LibraryViewModel()
        libraryViewModel.forceReload()
        await libraryViewModel.loadLibrary()

        XCTAssertTrue(libraryViewModel.homeStandaloneItems.contains(where: { $0.uuid == atom.uuid }))
        XCTAssertFalse(libraryViewModel.displayItems.contains(where: { $0.uuid == atom.uuid }))
    }

    func testProjectOwnedAtomsDoNotLeakIntoStandaloneSection() async throws {
        let project = try await AtomRepository.shared.create(type: .project, title: "Standalone Test Project")
        createdUUIDs.append(project.uuid)

        let linkedAtom = Atom.new(
            type: .content,
            title: "Project Owned Content",
            body: "linked to a project",
            links: [.project(project.uuid)]
        )
        let createdLinked = try await AtomRepository.shared.create(linkedAtom)
        createdUUIDs.append(createdLinked.uuid)

        let libraryViewModel = LibraryViewModel()
        libraryViewModel.forceReload()
        await libraryViewModel.loadLibrary()

        XCTAssertFalse(libraryViewModel.homeStandaloneItems.contains(where: { $0.uuid == createdLinked.uuid }))
        XCTAssertFalse(libraryViewModel.displayItems.contains(where: { $0.uuid == createdLinked.uuid }))
    }

    func testFetchRecentIncludesStandaloneNotes() async throws {
        let created = try await AtomRepository.shared.create(type: .note, title: "Recent standalone note")
        createdUUIDs.append(created.uuid)

        let recents = try await AtomRepository.shared.fetchRecent(limit: 25)
        XCTAssertTrue(recents.contains(where: { $0.uuid == created.uuid }))
    }

    func testFetchRecentlyOpenedUsesGraphAccessInsteadOfUpdatedAt() async throws {
        let opened = try await AtomRepository.shared.create(type: .note, title: "Actually opened note")
        let merelyUpdated = try await AtomRepository.shared.create(type: .note, title: "Recently updated note")
        createdUUIDs.append(opened.uuid)
        createdUUIDs.append(merelyUpdated.uuid)

        let oldUpdate = "2026-01-01T00:00:00Z"
        let newUpdate = "2026-02-01T00:00:00Z"
        let accessTime = "2099-01-15 12:00:00"

        try await CosmoDatabase.shared.asyncWrite { db in
            try db.execute(sql: "UPDATE atoms SET updated_at = ? WHERE uuid = ?", arguments: [oldUpdate, opened.uuid])
            try db.execute(sql: "UPDATE atoms SET updated_at = ? WHERE uuid = ?", arguments: [newUpdate, merelyUpdated.uuid])
            try db.execute(
                sql: "UPDATE graph_nodes SET last_accessed_at = ?, access_count = access_count + 1 WHERE atom_uuid = ?",
                arguments: [accessTime, opened.uuid]
            )
        }

        let recents = try await AtomRepository.shared.fetchRecentlyOpened(limit: 10)

        XCTAssertEqual(recents.first?.atom.uuid, opened.uuid)
        XCTAssertEqual(recents.first?.openedAt, accessTime)
        XCTAssertFalse(recents.contains { $0.atom.uuid == merelyUpdated.uuid })
    }

    private func canvasBlockCount(for atomUUID: String) async throws -> Int {
        try await CosmoDatabase.shared.asyncRead { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM canvas_blocks WHERE entity_uuid = ? AND is_deleted = 0",
                arguments: [atomUUID]
            ) ?? 0
        }
    }
}
