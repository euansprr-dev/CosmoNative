// CosmoOS/Data/Repositories/AtomRepository.swift
// Unified repository for all Atom operations
// Replaces individual repositories (IdeasRepository, TasksRepository, etc.)

@preconcurrency import GRDB
import Foundation

@MainActor
class AtomRepository: ObservableObject {
    static let shared = AtomRepository()

    struct RecentlyOpenedAtom: Sendable {
        let atom: Atom
        let openedAt: String
        let accessCount: Int
    }

    private let database = CosmoDatabase.shared
    private let changeTracker = ChangeTracker.shared

    // MARK: - Editing Lock Registry
    // Prevents background processors and sync from overwriting user edits
    private var editingLocks: [String: Date] = [:]
    private let editingLockExpiry: TimeInterval = 300 // 5 minutes safety valve

    private init() {}

    // MARK: - Fetch Operations

    /// Fetch all atoms of a specific type
    func fetchAll(type: AtomType) async throws -> [Atom] {
        try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.type == type.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)
                .order(Atom.CodingKeys.updatedAt.desc)
                .fetchAll(db)
        }
    }

    /// Fetch all atoms of a specific type, including soft-deleted rows.
    func fetchAllIncludingDeleted(type: AtomType) async throws -> [Atom] {
        try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.type == type.rawValue)
                .order(Atom.CodingKeys.updatedAt.desc)
                .fetchAll(db)
        }
    }

    /// Fetch the single system-event atom carrying an agent conversation,
    /// matched inside the metadata JSON in-database — replaces loading and
    /// JSON-decoding every system event just to find one conversation.
    /// JSONSerialization writes each key/value pair contiguously, so the LIKE
    /// pattern matches regardless of key order in the object.
    func fetchAgentConversationAtom(conversationId: String) async throws -> Atom? {
        try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.type == AtomType.systemEvent.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(sql: "metadata LIKE ?", arguments: ["%\"conversationId\":\"\(conversationId)\"%"])
                .order(Atom.CodingKeys.updatedAt.desc)
                .fetchOne(db)
        }
    }

    /// Recent content atoms belonging to a client profile — matched inside the
    /// metadata JSON in-database. Used for voice exemplars in client-scoped
    /// writing requests.
    func fetchRecentContent(clientProfileUUID: String, limit: Int = 3) async throws -> [Atom] {
        try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.type == AtomType.content.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(sql: "metadata LIKE ?", arguments: ["%\"clientProfileUUID\":\"\(clientProfileUUID)\"%"])
                .order(Atom.CodingKeys.updatedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Fetch a single atom by UUID
    func fetch(uuid: String) async throws -> Atom? {
        try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.uuid == uuid)
                .filter(Atom.CodingKeys.isDeleted == false)
                .fetchOne(db)
        }
    }

    /// Batch-fetch atoms by UUIDs
    func fetchBatch(uuids: [String]) async throws -> [Atom] {
        guard !uuids.isEmpty else { return [] }
        return try await database.asyncRead { db in
            try Atom
                .filter(uuids.contains(Atom.CodingKeys.uuid))
                .filter(Atom.CodingKeys.isDeleted == false)
                .fetchAll(db)
        }
    }

    /// Batch-fetch atoms by legacy integer IDs.
    func fetchBatch(ids: [Int64]) async throws -> [Atom] {
        guard !ids.isEmpty else { return [] }
        return try await database.asyncRead { db in
            try Atom
                .filter(ids.contains(Atom.CodingKeys.id))
                .filter(Atom.CodingKeys.isDeleted == false)
                .fetchAll(db)
        }
    }

    /// Fetch a single atom by ID (legacy compatibility)
    func fetch(id: Int64) async throws -> Atom? {
        try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.id == id)
                .filter(Atom.CodingKeys.isDeleted == false)
                .fetchOne(db)
        }
    }

    /// Fetch atoms by type with custom filter
    func fetch(type: AtomType, where predicate: @escaping (Atom) -> Bool) async throws -> [Atom] {
        let all = try await fetchAll(type: type)
        return all.filter(predicate)
    }

    /// Fetch atoms linked to a specific project
    func fetchByProject(projectUuid: String) async throws -> [Atom] {
        try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(sql: "links LIKE ?", arguments: ["%\(projectUuid)%"])
                .order(Atom.CodingKeys.updatedAt.desc)
                .fetchAll(db)
        }
    }

    /// Fetch atom UUIDs that belong to project thinkspaces (canvas_blocks) or have explicit project links.
    /// Returns a dictionary mapping project UUID → Set of owned atom UUIDs, plus a flattened set of all owned UUIDs.
    func fetchProjectOwnedAtomUUIDs(projectThinkspaceIds: [String], projectUUIDs: [String]) async throws -> (allOwned: Set<String>, perProject: [String: Set<String>]) {
        guard !projectThinkspaceIds.isEmpty || !projectUUIDs.isEmpty else {
            return ([], [:])
        }

        // 1. Query canvas_blocks for entity_uuid values in project thinkspaces
        var canvasAtomToProject: [String: String] = [:] // atomUUID → projectUUID

        if !projectThinkspaceIds.isEmpty {
            // We need thinkspaceId → projectUUID mapping, passed in via ThinkspaceManager
            let placeholders = projectThinkspaceIds.map { _ in "?" }.joined(separator: ", ")
            let rows: [Row] = try await database.asyncRead { db in
                try Row.fetchAll(db, sql: """
                    SELECT entity_uuid, thinkspace_id
                    FROM canvas_blocks
                    WHERE is_deleted = 0
                      AND entity_uuid IS NOT NULL
                      AND thinkspace_id IN (\(placeholders))
                """, arguments: StatementArguments(projectThinkspaceIds))
            }

            // Build thinkspaceId → projectUUID lookup from ThinkspaceManager
            let tsToProject = ThinkspaceManager.shared.thinkspaces
                .filter { $0.projectUuid != nil }
                .reduce(into: [String: String]()) { dict, ts in
                    dict[ts.id] = ts.projectUuid!
                }

            for row in rows {
                if let entityUuid: String = row["entity_uuid"],
                   let tsId: String = row["thinkspace_id"],
                   let projUuid = tsToProject[tsId] {
                    canvasAtomToProject[entityUuid] = projUuid
                }
            }
        }

        // 2. Query atoms with explicit project links
        var linkAtomToProject: [String: String] = [:]
        for projectUUID in projectUUIDs {
            let atoms: [Atom] = try await database.asyncRead { db in
                try Atom
                    .filter(Atom.CodingKeys.isDeleted == false)
                    .filter(sql: "links LIKE ?", arguments: ["%\(projectUUID)%"])
                    .fetchAll(db)
            }
            for atom in atoms where atom.type != .project && atom.type != .thinkspace {
                linkAtomToProject[atom.uuid] = projectUUID
            }
        }

        // 3. Merge both sources into per-project sets
        var perProject: [String: Set<String>] = [:]
        for (atomUUID, projUUID) in canvasAtomToProject {
            perProject[projUUID, default: []].insert(atomUUID)
        }
        for (atomUUID, projUUID) in linkAtomToProject {
            perProject[projUUID, default: []].insert(atomUUID)
        }

        let allOwned = Set(canvasAtomToProject.keys).union(linkAtomToProject.keys)
        return (allOwned, perProject)
    }

    /// Fetch atom UUIDs from canvas_blocks for specific thinkspace IDs
    func fetchAtomUUIDsInThinkspaces(_ thinkspaceIds: [String]) async throws -> Set<String> {
        guard !thinkspaceIds.isEmpty else { return [] }

        let placeholders = thinkspaceIds.map { _ in "?" }.joined(separator: ", ")
        let rows: [Row] = try await database.asyncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT DISTINCT entity_uuid
                FROM canvas_blocks
                WHERE is_deleted = 0
                  AND entity_uuid IS NOT NULL
                  AND thinkspace_id IN (\(placeholders))
            """, arguments: StatementArguments(thinkspaceIds))
        }

        return Set(rows.compactMap { $0["entity_uuid"] as String? })
    }

    /// Fetch a mapping of atom UUID → thinkspace IDs from canvas_blocks.
    func fetchThinkspaceMembership(for atomUUIDs: [String]) async throws -> [String: [String]] {
        guard !atomUUIDs.isEmpty else { return [:] }

        let placeholders = atomUUIDs.map { _ in "?" }.joined(separator: ", ")
        let rows: [Row] = try await database.asyncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT DISTINCT entity_uuid, thinkspace_id
                FROM canvas_blocks
                WHERE is_deleted = 0
                  AND entity_uuid IS NOT NULL
                  AND thinkspace_id IS NOT NULL
                  AND entity_uuid IN (\(placeholders))
            """, arguments: StatementArguments(atomUUIDs))
        }

        var memberships: [String: [String]] = [:]
        for row in rows {
            guard let atomUUID: String = row["entity_uuid"],
                  let thinkspaceId: String = row["thinkspace_id"] else { continue }
            memberships[atomUUID, default: []].append(thinkspaceId)
        }
        return memberships.mapValues { Array(Set($0)) }
    }

    /// Fetch thinkspace IDs containing a specific atom UUID.
    func fetchThinkspaceMembership(for atomUUID: String) async throws -> [String] {
        try await fetchThinkspaceMembership(for: [atomUUID])[atomUUID] ?? []
    }

    /// Fetch atoms by multiple types
    func fetchAll(types: [AtomType]) async throws -> [Atom] {
        let typeStrings = types.map { $0.rawValue }
        return try await database.asyncRead { db in
            try Atom
                .filter(typeStrings.contains(Column("type")))
                .filter(Atom.CodingKeys.isDeleted == false)
                .order(Atom.CodingKeys.updatedAt.desc)
                .fetchAll(db)
        }
    }

    /// Fetch recent atoms (for Command-K hot context)
    /// Returns most recently updated atoms across all user-facing types
    func fetchRecent(limit: Int = 25) async throws -> [Atom] {
        // Only include user-facing atom types (exclude system types)
        let userTypes = AtomType.userSearchableTypes
        let typeStrings = userTypes.map { $0.rawValue }

        return try await database.asyncRead { db in
            try Atom
                .filter(typeStrings.contains(Column("type")))
                .filter(Atom.CodingKeys.isDeleted == false)
                .order(Atom.CodingKeys.updatedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// User-searchable atoms whose `updated_at` is at or after the stamp —
    /// INCLUDING tombstoned rows, so an incremental index refresh can drop
    /// deletions instead of serving ghosts. `>=` on purpose: same-second
    /// writes re-fetch a handful of rows rather than ever missing one.
    func fetchUserSearchableUpdatedSince(_ iso8601Stamp: String, limit: Int = 10_000) async throws -> [Atom] {
        let typeStrings = AtomType.userSearchableTypes.map { $0.rawValue }
        return try await database.asyncRead { db in
            try Atom
                .filter(typeStrings.contains(Column("type")))
                .filter(Atom.CodingKeys.updatedAt >= iso8601Stamp)
                .order(Atom.CodingKeys.updatedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Fetch atoms the user has actually opened, ordered by graph access time.
    func fetchRecentlyOpened(limit: Int = 25) async throws -> [RecentlyOpenedAtom] {
        let userTypes = AtomType.userSearchableTypes
        let typeStrings = userTypes.map(\.rawValue)
        let placeholders = typeStrings.map { _ in "?" }.joined(separator: ", ")
        let limitValue = limit

        return try await database.asyncRead { [typeStrings, placeholders, limitValue] db in
            var arguments = StatementArguments(typeStrings)
            arguments += [limitValue]
            let rows = try Row.fetchAll(db, sql: """
                SELECT atoms.*, graph_nodes.last_accessed_at AS opened_at, graph_nodes.access_count AS graph_access_count
                FROM atoms
                JOIN graph_nodes ON graph_nodes.atom_uuid = atoms.uuid
                WHERE atoms.type IN (\(placeholders))
                  AND atoms.is_deleted = 0
                  AND graph_nodes.last_accessed_at IS NOT NULL
                ORDER BY unixepoch(graph_nodes.last_accessed_at) DESC, graph_nodes.last_accessed_at DESC
                LIMIT ?
                """, arguments: arguments)

            return rows.compactMap { row in
                guard let openedAt = row["opened_at"] as String? else { return nil }
                guard let atom = try? Atom(row: row) else { return nil }
                return RecentlyOpenedAtom(
                    atom: atom,
                    openedAt: openedAt,
                    accessCount: row["graph_access_count"] as Int? ?? 0
                )
            }
        }
    }

    /// Mark a user-facing atom as opened when navigation only has the legacy entity id.
    @discardableResult
    func recordAccess(entityId: Int64, accessType: AccessType = .view) async throws -> Atom? {
        guard let atom = try await fetch(id: entityId) else { return nil }
        try await NodeGraphEngine.shared.recordAccess(atomUUID: atom.uuid, type: accessType)
        return atom
    }

    /// Search atoms by title or body content (basic keyword search)
    func search(query: String, limit: Int = 50) async throws -> [Atom] {
        let userTypes = AtomType.userSearchableTypes
        let typeStrings = userTypes.map { $0.rawValue }
        let searchPattern = "%\(query)%"

        return try await database.asyncRead { db in
            try Atom
                .filter(typeStrings.contains(Column("type")))
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(
                    sql: "(title LIKE ? COLLATE NOCASE OR body LIKE ? COLLATE NOCASE)",
                    arguments: [searchPattern, searchPattern]
                )
                .order(Atom.CodingKeys.updatedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Create Operations

    /// Create a new atom
    @discardableResult
    func create(_ atom: Atom) async throws -> Atom {
        ConsoleLog.verbose("create() called uuid=\(atom.uuid) type=\(atom.type.rawValue) title=\"\(atom.title?.prefix(50) ?? "nil")\" bodyLen=\(atom.body?.count ?? 0)", subsystem: .database)
        var preparedAtom = atom
        preparedAtom.createdAt = ISO8601.string(from: Date())
        preparedAtom.updatedAt = preparedAtom.createdAt

        // Capture prepared atom for Sendable closure
        let atomToInsert = preparedAtom
        let savedAtom = try await database.asyncWrite { db in
            var insertingAtom = atomToInsert
            try insertingAtom.insert(db)
            insertingAtom.id = db.lastInsertedRowID
            return insertingAtom
        }
        ConsoleLog.verbose("create() done uuid=\(savedAtom.uuid) id=\(savedAtom.id ?? -1) version=\(savedAtom.localVersion)", subsystem: .database)

        // Track for sync
        await changeTracker.trackInsert(table: Atom.databaseTableName, entity: savedAtom)

        // Sync to NodeGraph
        do {
            try await NodeGraphEngine.shared.handleAtomCreated(savedAtom)
        } catch {
            print("AtomRepository: NodeGraph sync failed for created atom \(savedAtom.uuid): \(error)")
        }

        // Recall index: new content becomes searchable.
        let indexSnapshot = savedAtom
        Task.detached(priority: .utility) {
            await RecallIndexer.shared.noteAtomChanged(indexSnapshot)
        }

        return savedAtom
    }

    /// Create a new atom from type with basic fields
    @discardableResult
    func create(
        type: AtomType,
        title: String? = nil,
        body: String? = nil,
        structured: String? = nil,
        metadata: String? = nil,
        links: [AtomLink]? = nil
    ) async throws -> Atom {
        let atom = Atom.new(
            type: type,
            title: title,
            body: body,
            structured: structured,
            metadata: metadata,
            links: links
        )
        return try await create(atom)
    }

    // MARK: - Update Operations

    /// Update an existing atom with optimistic locking.
    /// Throws AtomRepositoryError.versionConflict if the atom was modified
    /// since the caller's copy was fetched.
    @discardableResult
    func update(_ atom: Atom, revisionSource: RevisionSource = .userEdit) async throws -> Atom {
        ConsoleLog.verbose("update() called uuid=\(atom.uuid) expectedVersion=\(atom.localVersion) title=\"\(atom.title?.prefix(50) ?? "nil")\" bodyLen=\(atom.body?.count ?? 0) bodyPreview=\"\(String(atom.body?.prefix(80) ?? "nil"))\"", subsystem: .database)
        var updatedAtom = atom
        updatedAtom.updatedAt = ISO8601.string(from: Date())
        updatedAtom.localVersion += 1

        let atomToUpdate = updatedAtom
        let expectedVersion = atom.localVersion // Version the caller read

        let rowsAffected = try await database.asyncWrite { db -> Int in
            // Version history: snapshot the row being replaced, atomically
            // with the overwrite. Losing a snapshot never blocks the save.
            if let previous = try? Atom
                .filter(Atom.CodingKeys.uuid == atomToUpdate.uuid)
                .fetchOne(db) {
                AtomRevisionWriter.snapshotIfNeeded(
                    db, previous: previous, incoming: atomToUpdate, source: revisionSource
                )
            }
            try db.execute(
                sql: """
                    UPDATE atoms SET
                        type = ?, title = ?, body = ?, structured = ?, metadata = ?, links = ?,
                        updated_at = ?, is_deleted = ?,
                        _local_version = ?, _server_version = ?, _sync_version = ?
                    WHERE uuid = ? AND _local_version = ?
                    """,
                arguments: [
                    atomToUpdate.type.rawValue,
                    atomToUpdate.title,
                    atomToUpdate.body,
                    atomToUpdate.structured,
                    atomToUpdate.metadata,
                    atomToUpdate.links,
                    atomToUpdate.updatedAt,
                    atomToUpdate.isDeleted,
                    atomToUpdate.localVersion,
                    atomToUpdate.serverVersion,
                    atomToUpdate.syncVersion,
                    atomToUpdate.uuid,
                    expectedVersion,
                ]
            )
            return db.changesCount
        }

        ConsoleLog.verbose("update() rows=\(rowsAffected) uuid=\(atom.uuid) newVersion=\(updatedAtom.localVersion)", subsystem: .database)
        if rowsAffected == 0 {
            // Version conflict — another writer bumped _local_version (e.g., cloud agent, Supabase realtime).
            // Auto-retry: re-fetch the fresh atom, apply our changes on top, and update again.
            print("[PERSIST] ⚠️ VERSION CONFLICT — uuid=\(atom.uuid) expectedVersion=\(expectedVersion) — auto-retrying with fresh version")

            guard let fresh = try await database.asyncRead({ db in
                try Atom.filter(Column("uuid") == atom.uuid).fetchOne(db)
            }) else {
                throw AtomRepositoryError.versionConflict(uuid: atom.uuid, expectedVersion: expectedVersion)
            }

            // Merge: apply the caller's field changes onto the fresh atom.
            // structured AND metadata merge at the JSON-key level and links are unioned,
            // so the concurrent writer's changes survive; the caller wins where both wrote.
            // (Whole-blob metadata/links replacement here used to silently erase the
            // other writer's keys — the single worst data-loss vector in the app.)
            let merged = Self.mergedForConflict(caller: atom, fresh: fresh)
            PersistenceHealth.note(.conflict, context: "AtomRepository.update(\(atom.uuid.prefix(8)))", detail: "version conflict auto-merged (expected \(expectedVersion), fresh \(fresh.localVersion))")

            let retryVersion = fresh.localVersion
            let retryAtom = merged
            let retryRows = try await database.asyncWrite { db -> Int in
                // The conflict path replaces the OTHER writer's row — always
                // snapshot it so the auto-merge can never silently eat content.
                AtomRevisionWriter.snapshotIfNeeded(
                    db, previous: fresh, incoming: retryAtom, source: revisionSource
                )
                try db.execute(
                    sql: """
                        UPDATE atoms SET
                            type = ?, title = ?, body = ?, structured = ?, metadata = ?, links = ?,
                            updated_at = ?, is_deleted = ?,
                            _local_version = ?, _server_version = ?, _sync_version = ?
                        WHERE uuid = ? AND _local_version = ?
                        """,
                    arguments: [
                        retryAtom.type.rawValue,
                        retryAtom.title,
                        retryAtom.body,
                        retryAtom.structured,
                        retryAtom.metadata,
                        retryAtom.links,
                        retryAtom.updatedAt,
                        retryAtom.isDeleted,
                        retryAtom.localVersion,
                        retryAtom.serverVersion,
                        retryAtom.syncVersion,
                        retryAtom.uuid,
                        retryVersion,
                    ]
                )
                return db.changesCount
            }

            if retryRows == 0 {
                print("[PERSIST] ⚠️ VERSION CONFLICT — retry also failed for uuid=\(atom.uuid)")
                throw AtomRepositoryError.versionConflict(uuid: atom.uuid, expectedVersion: retryVersion)
            }

            print("[PERSIST] ✅ VERSION CONFLICT resolved — uuid=\(atom.uuid) merged fresh version \(retryVersion) → \(retryAtom.localVersion)")
            updatedAtom = retryAtom

            // Track + sync the merged version.
            // skipVersionIncrement: the versioned UPDATE above already bumped
            // _local_version. A second bump here would desync the DB (caller+2)
            // from the returned atom (caller+1), forcing EVERY consecutive save
            // through this conflict path.
            await changeTracker.trackUpdate(table: Atom.databaseTableName, entity: retryAtom, skipVersionIncrement: true)
            refreshEditingLock(uuid: atom.uuid)
            do {
                try await NodeGraphEngine.shared.handleAtomUpdated(retryAtom, changedFields: ["title", "body", "links", "metadata"])
            } catch {
                print("AtomRepository: NodeGraph sync failed for retried atom \(retryAtom.uuid): \(error)")
            }
            return retryAtom
        }

        // Track for sync.
        // skipVersionIncrement: the versioned UPDATE above already bumped
        // _local_version; bumping again would defeat the optimistic lock for
        // every caller that saves the returned atom.
        await changeTracker.trackUpdate(table: Atom.databaseTableName, entity: updatedAtom, skipVersionIncrement: true)

        // Keep the recall index consistent (cheap enqueue; drain is background).
        let indexSnapshot = updatedAtom
        Task.detached(priority: .utility) {
            await RecallIndexer.shared.noteAtomChanged(indexSnapshot)
        }

        // Refresh editing lock if user is actively editing
        refreshEditingLock(uuid: atom.uuid)

        // Sync to NodeGraph
        do {
            try await NodeGraphEngine.shared.handleAtomUpdated(updatedAtom, changedFields: ["title", "body", "links", "metadata"])
        } catch {
            print("AtomRepository: NodeGraph sync failed for updated atom \(updatedAtom.uuid): \(error)")
        }

        return updatedAtom
    }

    /// Synchronous update — blocks until the write completes.
    /// Use this in save-on-close paths where the app may terminate before an async write finishes.
    ///
    /// Uses the same optimistic-lock + merge policy as `update()` (the old whole-row
    /// `save(db)` silently clobbered concurrent writes with the closing view's stale
    /// snapshot), and queues the change for sync in the same transaction so a
    /// quit-time edit still reaches the cloud on next launch.
    @discardableResult
    func updateSync(_ atom: Atom, revisionSource: RevisionSource = .userEdit) throws -> Atom {
        ConsoleLog.verbose("updateSync() called uuid=\(atom.uuid) version=\(atom.localVersion) bodyLen=\(atom.body?.count ?? 0) bodyPreview=\"\(String(atom.body?.prefix(80) ?? "nil"))\"", subsystem: .database)
        var candidate = atom
        candidate.updatedAt = ISO8601.string(from: Date())
        candidate.localVersion += 1

        let expectedVersion = atom.localVersion
        let candidateAtom = candidate
        var conflicted = false

        let saved: Atom = try database.write { db in
            // Version history: snapshot the row being replaced (close-save path).
            if let previous = try? Atom
                .filter(Atom.CodingKeys.uuid == candidateAtom.uuid)
                .fetchOne(db) {
                AtomRevisionWriter.snapshotIfNeeded(
                    db, previous: previous, incoming: candidateAtom, source: revisionSource
                )
            }

            func apply(_ row: Atom, expecting expected: Int64) throws -> Bool {
                try db.execute(
                    sql: """
                        UPDATE atoms SET
                            type = ?, title = ?, body = ?, structured = ?, metadata = ?, links = ?,
                            updated_at = ?, is_deleted = ?,
                            _local_version = ?, _server_version = ?, _sync_version = ?, _local_pending = 1
                        WHERE uuid = ? AND _local_version = ?
                        """,
                    arguments: [
                        row.type.rawValue,
                        row.title,
                        row.body,
                        row.structured,
                        row.metadata,
                        row.links,
                        row.updatedAt,
                        row.isDeleted,
                        row.localVersion,
                        row.serverVersion,
                        row.syncVersion,
                        row.uuid,
                        expected,
                    ]
                )
                return db.changesCount > 0
            }

            var result = candidateAtom
            if try !apply(candidateAtom, expecting: expectedVersion) {
                // Version conflict — merge our fields over the fresh row instead of
                // clobbering whatever the other writer saved (same policy as update()).
                conflicted = true
                guard let fresh = try Atom.filter(Column("uuid") == atom.uuid).fetchOne(db) else {
                    throw AtomRepositoryError.versionConflict(uuid: atom.uuid, expectedVersion: expectedVersion)
                }
                let merged = Self.mergedForConflict(caller: atom, fresh: fresh)
                guard try apply(merged, expecting: fresh.localVersion) else {
                    throw AtomRepositoryError.versionConflict(uuid: atom.uuid, expectedVersion: fresh.localVersion)
                }
                result = merged
            }

            // Queue the change for sync in the SAME transaction so a quit-time save
            // still reaches Supabase on next launch.
            let dataJson = (try? JSONEncoder().encode(result)).flatMap { String(data: $0, encoding: .utf8) }
            // Scoped by table_name (mirrors ChangeTracker.queueChange): legacy
            // pulled placements have canvas_blocks.id == atom uuid, so a
            // uuid-only match could hijack a pending canvas_blocks row —
            // swapping its payload for atom data while the table stays
            // canvas_blocks, and dropping this atom edit from the queue.
            let existing = try Row.fetchOne(
                db,
                sql: "SELECT id FROM sync_queue WHERE uuid = ? AND table_name = ? AND status = 'pending'",
                arguments: [atom.uuid, Atom.databaseTableName]
            )
            if let existingId = existing?["id"] as Int64? {
                try db.execute(
                    sql: "UPDATE sync_queue SET operation = 'UPDATE', data = ?, local_version = ?, created_at = ? WHERE id = ?",
                    arguments: [dataJson, result.localVersion, Int64(Date().timeIntervalSince1970 * 1000), existingId]
                )
            } else {
                try db.execute(
                    sql: """
                        INSERT INTO sync_queue (uuid, table_name, row_id, operation, data, local_version, status)
                        VALUES (?, ?, ?, 'UPDATE', ?, ?, 'pending')
                        """,
                    arguments: [atom.uuid, Atom.databaseTableName, result.id, dataJson, result.localVersion]
                )
            }
            return result
        }

        if conflicted {
            PersistenceHealth.note(.conflict, context: "AtomRepository.updateSync(\(atom.uuid.prefix(8)))", detail: "version conflict auto-merged at close-save")
        }
        ConsoleLog.verbose("updateSync() done uuid=\(atom.uuid) newVersion=\(saved.localVersion)", subsystem: .database)

        return saved
    }

    /// Update specific fields of an atom by UUID
    func update(uuid: String, updates: (inout Atom) -> Void) async throws -> Atom? {
        guard var atom = try await fetch(uuid: uuid) else { return nil }
        updates(&atom)
        return try await update(atom)
    }

    // MARK: - Field-Level Updates

    /// Update only specific columns of an atom by UUID.
    /// Background processors MUST use this instead of update() to avoid
    /// overwriting user edits to unrelated fields.
    @discardableResult
    func updateFields(
        uuid: String,
        columns: [String: (any DatabaseValueConvertible)?]
    ) async throws -> Atom {
        ConsoleLog.verbose("updateFields() called uuid=\(uuid) columns=\(Array(columns.keys))", subsystem: .database)
        guard !columns.isEmpty else {
            guard let atom = try await fetch(uuid: uuid) else {
                throw AtomRepositoryError.notFound(uuid)
            }
            return atom
        }

        let now = ISO8601.string(from: Date())

        // Build SET clause — column names are trusted internal strings
        var setClauses: [String] = []
        var arguments: [any DatabaseValueConvertible] = []

        for (column, value) in columns {
            setClauses.append("\(column) = ?")
            if let v = value {
                arguments.append(v)
            } else {
                // A real SQL NULL — writing "" here used to manufacture undecodable
                // JSON columns, which then fed the decode-fail→default→re-save wipe.
                arguments.append(DatabaseValue.null)
            }
        }

        setClauses.append("updated_at = ?")
        arguments.append(now)
        setClauses.append("_local_version = _local_version + 1")

        let sql = "UPDATE atoms SET \(setClauses.joined(separator: ", ")) WHERE uuid = ?"
        arguments.append(uuid)

        try await database.asyncWrite { [arguments, sql] db in
            try db.execute(sql: sql, arguments: StatementArguments(arguments))
        }

        // Re-fetch canonical state
        guard let updated = try await fetch(uuid: uuid) else {
            throw AtomRepositoryError.notFound(uuid)
        }

        // Track for sync — the SQL above already bumped _local_version.
        await changeTracker.trackUpdate(table: Atom.databaseTableName, entity: updated, skipVersionIncrement: true)

        return updated
    }

    // MARK: - Conflict Merge Helpers

    /// Shared conflict merge used by update() and updateSync(): apply the caller's
    /// changes onto the fresh row without destroying the concurrent writer's work.
    static func mergedForConflict(caller atom: Atom, fresh: Atom) -> Atom {
        var merged = fresh
        if atom.title != nil { merged.title = atom.title }
        if atom.body != nil && atom.body != fresh.body { merged.body = atom.body }
        if atom.structured != nil && atom.structured != fresh.structured {
            merged.structured = mergedJSONKeys(fresh: fresh.structured, caller: atom.structured)
        }
        if atom.metadata != nil && atom.metadata != fresh.metadata {
            merged.metadata = mergedJSONKeys(fresh: fresh.metadata, caller: atom.metadata)
        }
        if atom.links != nil && atom.links != fresh.links {
            merged.links = mergedLinks(fresh: fresh.links, caller: atom.links)
        }
        if atom.isDeleted {
            merged.isDeleted = true
        }
        merged.updatedAt = ISO8601.string(from: Date())
        merged.localVersion += 1
        return merged
    }

    /// Key-level JSON merge for conflict resolution: the caller's keys win,
    /// the fresh row's other keys survive. Falls back to the caller's payload
    /// when either side is unparseable (previous behavior).
    static func mergedJSONKeys(fresh: String?, caller: String?) -> String? {
        guard let caller, !caller.isEmpty else { return fresh }
        guard let fresh, !fresh.isEmpty, fresh != caller else { return caller }
        guard let freshData = fresh.data(using: .utf8),
              let callerData = caller.data(using: .utf8),
              var merged = (try? JSONSerialization.jsonObject(with: freshData)) as? [String: Any],
              let callerDict = (try? JSONSerialization.jsonObject(with: callerData)) as? [String: Any] else {
            return caller
        }
        for (key, value) in callerDict {
            merged[key] = value
        }
        guard let data = try? JSONSerialization.data(withJSONObject: merged),
              let result = String(data: data, encoding: .utf8) else {
            return caller
        }
        return result
    }

    /// Union merge for links on conflict: relationships added by either writer
    /// survive. Single-value link types dedupe by type with the caller's choice
    /// winning; multi-value types dedupe by (type, target uuid).
    static func mergedLinks(fresh: String?, caller: String?) -> String? {
        guard let caller, !caller.isEmpty else { return fresh }
        guard let fresh, !fresh.isEmpty, fresh != caller else { return caller }
        guard let freshData = fresh.data(using: .utf8),
              let callerData = caller.data(using: .utf8),
              let freshLinks = try? JSONDecoder().decode([AtomLink].self, from: freshData),
              let callerLinks = try? JSONDecoder().decode([AtomLink].self, from: callerData) else {
            return caller
        }
        var seen = Set<String>()
        var union: [AtomLink] = []
        for link in callerLinks + freshLinks {
            let key = link.isSingleValue ? link.type : "\(link.type)|\(link.uuid)"
            if seen.insert(key).inserted {
                union.append(link)
            }
        }
        guard let data = try? JSONEncoder().encode(union),
              let result = String(data: data, encoding: .utf8) else {
            return caller
        }
        return result
    }

    // MARK: - Editing Locks

    /// Acquire an editing lock. Call when opening a focus mode view.
    func acquireEditingLock(uuid: String) {
        ConsoleLog.verbose("acquireEditingLock uuid=\(uuid)", subsystem: .database)
        editingLocks[uuid] = Date()
    }

    /// Refresh the lock timestamp. Call on each user save to prevent expiry.
    func refreshEditingLock(uuid: String) {
        guard editingLocks[uuid] != nil else { return }
        editingLocks[uuid] = Date()
    }

    /// Release the editing lock. Call when closing a focus mode view.
    func releaseEditingLock(uuid: String) {
        ConsoleLog.verbose("releaseEditingLock uuid=\(uuid)", subsystem: .database)
        editingLocks.removeValue(forKey: uuid)
    }

    /// Check if an atom is currently being edited by the user.
    func isBeingEdited(_ uuid: String) -> Bool {
        guard let lockTime = editingLocks[uuid] else { return false }
        if Date().timeIntervalSince(lockTime) > editingLockExpiry {
            ConsoleLog.verbose("editingLock expired uuid=\(uuid) age=\(Date().timeIntervalSince(lockTime))s", subsystem: .database)
            editingLocks.removeValue(forKey: uuid)
            return false
        }
        return true
    }

    // MARK: - Delete Operations

    /// Soft delete an atom by UUID
    func delete(uuid: String) async throws {
        try await database.asyncWrite { db in
            // Version history: keep the atom's final content so a deleted
            // note/draft is always recoverable even after the tombstone syncs.
            if let previous = try? Atom
                .filter(Atom.CodingKeys.uuid == uuid)
                .filter(Atom.CodingKeys.isDeleted == false)
                .fetchOne(db) {
                AtomRevisionWriter.snapshot(db, of: previous, source: .preDelete)
            }
            try db.execute(
                sql: """
                UPDATE atoms
                SET is_deleted = 1, updated_at = ?, _local_version = _local_version + 1
                WHERE uuid = ?
                """,
                arguments: [ISO8601.string(from: Date()), uuid]
            )

            // Also soft-delete any canvas blocks referencing this atom.
            // ISO8601, not SQLite CURRENT_TIMESTAMP — the block observer
            // pushes this updated_at to the cloud, and CURRENT_TIMESTAMP's
            // space-separated format breaks ISO8601 cursor/LWW comparisons.
            try db.execute(
                sql: "UPDATE canvas_blocks SET is_deleted = 1, updated_at = ? WHERE entity_uuid = ?",
                arguments: [ISO8601.string(from: Date()), uuid]
            )
        }

        // Track for sync
        await changeTracker.trackDelete(table: Atom.databaseTableName, uuid: uuid, rowId: nil)

        // Recall index: tombstones cascade to vectors (index cascade law).
        Task.detached(priority: .utility) {
            await RecallIndexer.shared.noteAtomDeleted(uuid)
        }

        // Reading Room marks cascade with the source atom AND the capture atom.
        Task.detached(priority: .utility) {
            await PDFHighlightStore.removeForAtom(uuid)
        }

        // Sync to NodeGraph
        do {
            try await NodeGraphEngine.shared.handleAtomDeleted(atomUUID: uuid)
        } catch {
            print("AtomRepository: NodeGraph sync failed for deleted atom \(uuid): \(error)")
        }

        // Notify canvas to remove blocks for this atom, AND every atom-list
        // surface (Command-K, library, sidebars) that observes .atomsDidChange
        // so the deleted row disappears instantly. `restore()` posts both — a
        // delete that only fired canvasBlocksChanged left ⌘K showing the row
        // until the user re-typed the query (the "doesn't update instantly" bug).
        await MainActor.run {
            NotificationCenter.default.post(
                name: Notification.Name("com.cosmo.canvasBlocksChanged"),
                object: nil
            )
            NotificationCenter.default.post(name: .atomsDidChange, object: nil)
        }
    }

    /// Soft delete an atom
    func delete(_ atom: Atom) async throws {
        try await delete(uuid: atom.uuid)
    }

    /// Hard delete an atom — permanently destroys data with no undo.
    /// Callers MUST present a confirmation dialog before invoking.
    func hardDelete(uuid: String, confirmed: Bool = false) async throws {
        guard confirmed else {
            assertionFailure("hardDelete() called without confirmed: true — add a confirmation dialog before calling")
            return
        }

        // Tombstone the cloud rows BEFORE destroying local state. Without this
        // the Supabase row lives forever and every other device resurrects the
        // "permanently deleted" atom on its next pull. trackDelete queues a
        // DELETE op (offline-safe batch retry) and fires an immediate soft
        // delete — the queue row survives the local hard delete below.
        await changeTracker.trackDelete(table: Atom.databaseTableName, uuid: uuid, rowId: nil)

        // Canvas placements: cloud rows are keyed by placement id; legacy rows
        // were keyed by entity uuid — tombstone both keys.
        let placementIds = (try? await database.asyncRead { db in
            try String.fetchAll(db, sql: "SELECT id FROM canvas_blocks WHERE entity_uuid = ?", arguments: [uuid])
        }) ?? []
        for placementId in placementIds {
            await changeTracker.trackDelete(table: CanvasBlockRecord.databaseTableName, uuid: placementId, rowId: nil)
        }
        await changeTracker.trackDelete(table: CanvasBlockRecord.databaseTableName, uuid: uuid, rowId: nil)

        try await database.asyncWrite { db in
            try db.execute(
                sql: "DELETE FROM atoms WHERE uuid = ?",
                arguments: [uuid]
            )

            // Also hard-delete any canvas blocks referencing this atom
            try db.execute(
                sql: "DELETE FROM canvas_blocks WHERE entity_uuid = ?",
                arguments: [uuid]
            )
        }

        // Notify canvas to remove blocks for this atom
        await MainActor.run {
            NotificationCenter.default.post(
                name: Notification.Name("com.cosmo.canvasBlocksChanged"),
                object: nil
            )
        }
    }

    /// Soft delete a project (same as regular soft delete)
    func softDeleteProject(_ uuid: String) async throws {
        try await delete(uuid: uuid)
    }

    /// Restore any soft-deleted atom, including its canvas placements
    /// (delete() soft-deletes both; restoring only the atom left its blocks
    /// permanently invisible).
    ///
    /// Writes the explicit-resurrection marker `metadata.restoredAt` — the
    /// ONLY writer of that key (wire contract shared with the iOS repo).
    /// Receiving devices' one-way delete guards accept the undelete only when
    /// the marker is strictly newer than their local tombstone's updated_at,
    /// so stale mirrors re-pushing old live rows still can't resurrect.
    /// Without the marker, a restore performed here never propagates past the
    /// other device's tombstone.
    func restore(uuid: String) async throws {
        let now = ISO8601.string(from: Date())
        try await database.asyncWrite { db in
            let existingMetadata = try String.fetchOne(
                db,
                sql: "SELECT metadata FROM atoms WHERE uuid = ?",
                arguments: [uuid]
            )
            let stamped = Self.metadataStampingRestoredAt(existingMetadata, restoredAt: now)
            if stamped == nil, existingMetadata?.isEmpty == false {
                // Unparseable metadata: restore locally anyway, but the
                // undelete won't cross other devices' tombstone guards.
                PersistenceHealth.note(.decodeFailure, context: "AtomRepository.restore(\(uuid.prefix(8)))", detail: "metadata unparseable; restoring without restoredAt marker")
            }
            try db.execute(
                sql: """
                UPDATE atoms
                SET is_deleted = 0, updated_at = ?, _local_version = _local_version + 1,
                    metadata = COALESCE(?, metadata)
                WHERE uuid = ?
                """,
                arguments: [now, stamped, uuid]
            )
            try db.execute(
                sql: "UPDATE canvas_blocks SET is_deleted = 0, updated_at = ? WHERE entity_uuid = ?",
                arguments: [now, uuid]
            )
        }

        // Track for sync - fetch the updated atom to track properly
        if let restoredAtom = try? await fetch(uuid: uuid) {
            await changeTracker.trackUpdate(table: Atom.databaseTableName, entity: restoredAtom, skipVersionIncrement: true)
        }

        // Recall index: the atom is live again.
        Task.detached(priority: .utility) {
            if let restoredAtom = try? await AtomRepository.shared.fetch(uuid: uuid) {
                await RecallIndexer.shared.noteAtomChanged(restoredAtom)
            }
        }

        await MainActor.run {
            NotificationCenter.default.post(
                name: Notification.Name("com.cosmo.canvasBlocksChanged"),
                object: nil
            )
            NotificationCenter.default.post(name: .atomsDidChange, object: nil)
        }
    }

    /// Merge `restoredAt` into an existing metadata JSON string. Returns nil
    /// when the existing metadata is non-empty but unparseable (the caller
    /// keeps the original column rather than destroying it). Empty/absent
    /// metadata becomes a fresh object holding just the marker.
    nonisolated static func metadataStampingRestoredAt(_ existingMetadata: String?, restoredAt: String) -> String? {
        var dict: [String: Any] = [:]
        if let existing = existingMetadata, !existing.isEmpty {
            guard let data = existing.data(using: .utf8),
                  let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                return nil
            }
            dict = parsed
        }
        dict["restoredAt"] = restoredAt
        guard let json = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: json, encoding: .utf8) else { return nil }
        return string
    }

    /// Soft-deleted atoms, newest deletions first — backs the Trash UI.
    func fetchDeleted(limit: Int = 200) async throws -> [Atom] {
        try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.isDeleted == true)
                .order(Atom.CodingKeys.updatedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Restore a soft-deleted project
    func restoreProject(_ uuid: String) async throws {
        try await restore(uuid: uuid)
    }

    /// Permanently delete a project (hard delete)
    func permanentlyDeleteProject(_ uuid: String) async throws {
        try await hardDelete(uuid: uuid, confirmed: true)
    }

    // MARK: - Batch Operations

    /// Create multiple atoms in a single transaction
    func createBatch(_ atoms: [Atom]) async throws -> [Atom] {
        let now = ISO8601.string(from: Date())
        let preparedAtoms = atoms.map { atom -> Atom in
            var a = atom
            a.createdAt = now
            a.updatedAt = now
            return a
        }

        let savedAtoms = try await database.asyncWrite { db -> [Atom] in
            var saved: [Atom] = []
            for atom in preparedAtoms {
                var insertingAtom = atom
                try insertingAtom.insert(db)
                insertingAtom.id = db.lastInsertedRowID
                saved.append(insertingAtom)
            }
            return saved
        }

        // Track for sync
        for atom in savedAtoms {
            await changeTracker.trackInsert(table: Atom.databaseTableName, entity: atom)
        }

        return savedAtoms
    }

    /// Update multiple atoms in a single transaction.
    /// Rows whose _local_version no longer matches the caller's snapshot are
    /// skipped (and reported) instead of being clobbered with stale data.
    func updateBatch(_ atoms: [Atom]) async throws {
        let now = ISO8601.string(from: Date())

        let (written, conflicted): ([Atom], [String]) = try await database.asyncWrite { db in
            var written: [Atom] = []
            var conflicted: [String] = []
            for var atom in atoms {
                let expected = atom.localVersion
                atom.updatedAt = now
                atom.localVersion += 1
                try db.execute(
                    sql: """
                        UPDATE atoms SET
                            type = ?, title = ?, body = ?, structured = ?, metadata = ?, links = ?,
                            updated_at = ?, is_deleted = ?,
                            _local_version = ?, _server_version = ?, _sync_version = ?
                        WHERE uuid = ? AND _local_version = ?
                        """,
                    arguments: [
                        atom.type.rawValue,
                        atom.title,
                        atom.body,
                        atom.structured,
                        atom.metadata,
                        atom.links,
                        atom.updatedAt,
                        atom.isDeleted,
                        atom.localVersion,
                        atom.serverVersion,
                        atom.syncVersion,
                        atom.uuid,
                        expected,
                    ]
                )
                if db.changesCount > 0 {
                    written.append(atom)
                } else {
                    conflicted.append(atom.uuid)
                }
            }
            return (written, conflicted)
        }

        if !conflicted.isEmpty {
            PersistenceHealth.note(.conflict, context: "AtomRepository.updateBatch", detail: "skipped \(conflicted.count) row(s) modified since fetch: \(conflicted.prefix(5).joined(separator: ", "))")
        }

        // Track for sync — versions already bumped by the SQL above.
        for atom in written {
            await changeTracker.trackUpdate(table: Atom.databaseTableName, entity: atom, skipVersionIncrement: true)
        }
    }

    /// Soft delete multiple atoms
    func deleteBatch(uuids: [String]) async throws {
        let now = ISO8601.string(from: Date())

        try await database.asyncWrite { db in
            for uuid in uuids {
                try db.execute(
                    sql: """
                    UPDATE atoms
                    SET is_deleted = 1, updated_at = ?, _local_version = _local_version + 1
                    WHERE uuid = ?
                    """,
                    arguments: [now, uuid]
                )
            }
        }

        // Track for sync
        for uuid in uuids {
            await changeTracker.trackDelete(table: Atom.databaseTableName, uuid: uuid, rowId: nil)
        }
    }

    // MARK: - Search Operations

    /// Search atoms by title/body text
    func search(query: String, types: [AtomType]? = nil) async throws -> [Atom] {
        let pattern = "%\(query)%"

        return try await database.asyncRead { db in
            var request = Atom
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(
                    Column("title").like(pattern) ||
                    Column("body").like(pattern)
                )

            if let types = types {
                let typeStrings = types.map { $0.rawValue }
                request = request.filter(typeStrings.contains(Column("type")))
            }

            return try request
                .order(Atom.CodingKeys.updatedAt.desc)
                .fetchAll(db)
        }
    }

    /// Batch-fetch by uuid — one IN query per 900 uuids (SQLite's variable
    /// cap is 999) instead of one round-trip per uuid. Result order is
    /// unspecified; callers key by uuid.
    func fetch(uuids: [String]) async throws -> [Atom] {
        guard !uuids.isEmpty else { return [] }
        return try await database.asyncRead { db in
            var result: [Atom] = []
            result.reserveCapacity(uuids.count)
            for chunkStart in stride(from: 0, to: uuids.count, by: 900) {
                let chunk = Array(uuids[chunkStart..<min(chunkStart + 900, uuids.count)])
                result.append(contentsOf: try Atom
                    .filter(chunk.contains(Column("uuid")))
                    .filter(Atom.CodingKeys.isDeleted == false)
                    .fetchAll(db))
            }
            return result
        }
    }

    /// Fetch swipe-file candidate atoms without the `LIKE '%%'` full scan.
    /// `search(query: "", types: [.research])` evaluated `title LIKE '%%' OR
    /// body LIKE '%%'` against every research row — reading whole transcript
    /// blobs to prove they match everything, and silently dropping rows whose
    /// title AND body are both NULL. The metadata predicate here is a cheap
    /// SQL pre-filter only (same shape SwipeProcessingService trusts);
    /// callers keep `atom.isSwipeFileAtom` as the authority downstream.
    func fetchSwipeFileAtoms() async throws -> [Atom] {
        try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(Atom.CodingKeys.type == AtomType.research.rawValue)
                .filter(sql: "metadata LIKE '%\"isSwipeFile\":true%'")
                .order(Atom.CodingKeys.updatedAt.desc)
                .fetchAll(db)
        }
    }

    /// Search atoms by metadata field value
    func search(metadataKey: String, value: String, type: AtomType? = nil) async throws -> [Atom] {
        // Use JSON path search
        let pattern = "%\"\(metadataKey)\":\"\(value)\"%"

        return try await database.asyncRead { db in
            var request = Atom
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(sql: "metadata LIKE ?", arguments: [pattern])

            if let type = type {
                request = request.filter(Atom.CodingKeys.type == type.rawValue)
            }

            return try request
                .order(Atom.CodingKeys.updatedAt.desc)
                .fetchAll(db)
        }
    }

    /// Raw-LIKE candidate fetch: live atoms of `type` whose metadata contains
    /// the substring anywhere. Callers MUST decode-filter the results — a bare
    /// LIKE hit can false-positive (e.g. a uuid inside escaped nested JSON).
    func fetchByMetadataSubstring(_ needle: String, type: AtomType) async throws -> [Atom] {
        try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(Atom.CodingKeys.type == type.rawValue)
                .filter(sql: "metadata LIKE ?", arguments: ["%\(needle)%"])
                .order(Atom.CodingKeys.updatedAt.desc)
                .fetchAll(db)
        }
    }

    /// Fetch atoms whose outline-reference metadata points at the target UUID.
    func fetchOutlineBacklinks(to targetAtomUUID: String) async throws -> [Atom] {
        let candidates = try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(sql: "metadata LIKE ?", arguments: ["%\(targetAtomUUID)%"])
                .order(Atom.CodingKeys.updatedAt.desc)
                .fetchAll(db)
        }

        return candidates.filter { atom in
            atom.outlineReferences.contains { $0.atomUUID == targetAtomUUID }
        }
    }

    // MARK: - Convenience Typed Accessors

    /// Get all ideas
    func ideas() async throws -> [Atom] {
        try await fetchAll(type: .idea)
    }

    /// Get all tasks
    func tasks() async throws -> [Atom] {
        try await fetchAll(type: .task)
    }

    /// Get all projects
    func projects() async throws -> [Atom] {
        try await fetchAll(type: .project)
    }

    /// Get all content
    func content() async throws -> [Atom] {
        try await fetchAll(type: .content)
    }

    /// Get all research
    func research() async throws -> [Atom] {
        try await fetchAll(type: .research)
    }

    /// Get all connections
    func connections() async throws -> [Atom] {
        try await fetchAll(type: .connection)
    }

    /// Get all schedule blocks
    func scheduleBlocks() async throws -> [Atom] {
        try await fetchAll(type: .scheduleBlock)
    }

    /// Get all uncommitted items
    func uncommittedItems() async throws -> [Atom] {
        try await fetchAll(type: .uncommittedItem)
    }
}

// MARK: - Typed Convenience Methods

extension AtomRepository {

    /// Create a new idea atom
    @discardableResult
    func createIdea(title: String?, content: String, tags: [String] = [], projectUuid: String? = nil) async throws -> Atom {
        let metadata = IdeaMetadata(tags: tags, priority: "Medium", isPinned: false, pinnedAt: nil)
        var links: [AtomLink] = []
        if let projectUuid = projectUuid {
            links.append(.project(projectUuid))
        }

        return try await create(
            type: .idea,
            title: title,
            body: content,
            metadata: try? String(data: JSONEncoder().encode(metadata), encoding: .utf8),
            links: links.isEmpty ? nil : links
        )
    }

    /// Create a new task atom
    @discardableResult
    func createTask(title: String, status: String = "todo", projectUuid: String? = nil) async throws -> Atom {
        let metadata = TaskMetadata(status: status, priority: "medium")
        var links: [AtomLink] = []
        if let projectUuid = projectUuid {
            links.append(.project(projectUuid))
        }

        return try await create(
            type: .task,
            title: title,
            metadata: try? String(data: JSONEncoder().encode(metadata), encoding: .utf8),
            links: links.isEmpty ? nil : links
        )
    }

    /// Create a new project atom with auto-created root ThinkSpace
    /// Part 3 of Project System Architecture - every project gets a root ThinkSpace
    @discardableResult
    func createProject(title: String, description: String? = nil, color: String = "#8B5CF6") async throws -> Atom {
        // 1. Create the project first (without rootThinkspaceUuid)
        var projectMetadata = ProjectMetadata(color: color, status: "active", priority: "Medium")

        let project = try await create(
            type: .project,
            title: title,
            body: description,
            metadata: try? String(data: JSONEncoder().encode(projectMetadata), encoding: .utf8)
        )

        // 2. Create root ThinkSpace for the project
        let thinkspaceMetadata = ThinkspaceMetadata(
            name: title,  // Same name as project
            projectUuid: project.uuid,
            parentThinkspaceId: nil,
            isRootThinkspace: true,
            accentColorHex: color
        )

        guard let thinkspaceMetadataJson = try? JSONEncoder().encode(thinkspaceMetadata),
              let thinkspaceMetadataString = String(data: thinkspaceMetadataJson, encoding: .utf8) else {
            print("⚠️ Failed to encode ThinkSpace metadata, project created without root ThinkSpace")
            return project
        }

        let rootThinkspace = Atom.new(
            type: .thinkspace,
            title: title,
            metadata: thinkspaceMetadataString
        )

        let savedThinkspace = try await create(rootThinkspace)

        // 3. Update project metadata with root ThinkSpace reference
        projectMetadata.rootThinkspaceUuid = savedThinkspace.uuid

        var updatedProject = project
        if let metadataJson = try? JSONEncoder().encode(projectMetadata),
           let metadataString = String(data: metadataJson, encoding: .utf8) {
            updatedProject.metadata = metadataString
        }
        updatedProject.updatedAt = ISO8601.string(from: Date())

        try await update(updatedProject)

        // 4. Notify ThinkspaceManager to reload (it observes thinkspaces)
        NotificationCenter.default.post(
            name: CosmoNotification.Canvas.thinkspaceChanged,
            object: nil,
            userInfo: ["action": "created", "thinkspaceId": savedThinkspace.uuid]
        )

        // 5. Notify Plannerum and other observers that atoms changed
        NotificationCenter.default.post(name: .atomsDidChange, object: nil)

        // 6. Notify about project creation (for voice routing, etc.)
        NotificationCenter.default.post(
            name: CosmoNotification.Project.created,
            object: nil,
            userInfo: ["projectUuid": updatedProject.uuid, "projectName": title]
        )

        print("✅ Project created with root ThinkSpace: \(title)")
        return updatedProject
    }

    /// Create a project from an existing ThinkSpace
    /// The ThinkSpace becomes the root ThinkSpace (no duplicate created)
    func createProjectFromThinkspace(thinkspaceUuid: String, thinkspaceName: String, color: String = "#8B5CF6") async throws -> Atom {
        // 1. Create the project with reference to existing thinkspace as root
        let projectMetadata = ProjectMetadata(
            color: color,
            status: "active",
            priority: "Medium",
            rootThinkspaceUuid: thinkspaceUuid  // Use existing thinkspace as root
        )

        let project = try await create(
            type: .project,
            title: thinkspaceName,
            body: "Created from ThinkSpace",
            metadata: try? String(data: JSONEncoder().encode(projectMetadata), encoding: .utf8)
        )

        // 2. Update the existing ThinkSpace to be the root of this project
        guard var thinkspaceAtom = try await fetch(uuid: thinkspaceUuid) else {
            throw NSError(domain: "AtomRepository", code: 404, userInfo: [NSLocalizedDescriptionKey: "ThinkSpace not found"])
        }

        // Update thinkspace metadata to mark it as root and assign to project
        var thinkspaceMetadata = thinkspaceAtom.metadataValue(as: ThinkspaceMetadata.self) ?? ThinkspaceMetadata()
        thinkspaceMetadata.projectUuid = project.uuid
        thinkspaceMetadata.isRootThinkspace = true
        thinkspaceMetadata.parentThinkspaceId = nil
        thinkspaceMetadata.accentColorHex = color

        if let metadataJson = try? JSONEncoder().encode(thinkspaceMetadata),
           let metadataString = String(data: metadataJson, encoding: .utf8) {
            thinkspaceAtom.metadata = metadataString
        }
        thinkspaceAtom.updatedAt = ISO8601.string(from: Date())

        try await update(thinkspaceAtom)

        // 3. Notify ThinkspaceManager to reload
        NotificationCenter.default.post(
            name: CosmoNotification.Canvas.thinkspaceChanged,
            object: nil,
            userInfo: ["action": "updated", "thinkspaceId": thinkspaceUuid]
        )

        // 4. Notify Plannerum and other observers that atoms changed
        NotificationCenter.default.post(name: .atomsDidChange, object: nil)

        // 5. Create project inbox streams for Plannerum
        NotificationCenter.default.post(
            name: CosmoNotification.Project.created,
            object: nil,
            userInfo: ["projectUuid": project.uuid, "projectName": thinkspaceName]
        )

        print("✅ Project created from existing ThinkSpace: \(thinkspaceName)")
        return project
    }

    /// One-way compatibility migration from the old Project container model to Thinkspace ownership.
    /// Project atoms are soft-deleted after their root Thinkspace receives the project's color
    /// and all explicit `.project` links are rewritten to `.thinkspace(rootThinkspaceUUID)`.
    ///
    /// One-shot: gated by a flag stored in the DATABASE (not UserDefaults), so this
    /// destructive migration can never re-run against an already-migrated database
    /// and can never delete `.project` atoms that arrive later via sync.
    func migrateProjectsToThinkspaces() async throws {
        let flagKey = "projectsMigratedToThinkspaces"
        let alreadyRan = try await database.asyncRead { db in
            try Row.fetchOne(db, sql: "SELECT value FROM app_flags WHERE key = ?", arguments: [flagKey]) != nil
        }
        if alreadyRan {
            return
        }

        func markDone() async throws {
            try await database.asyncWrite { db in
                try db.execute(
                    sql: "INSERT OR REPLACE INTO app_flags (key, value, updated_at) VALUES (?, '1', ?)",
                    arguments: [flagKey, ISO8601.string(from: Date())]
                )
            }
        }

        let projects = try await fetchAll(type: .project)
        guard !projects.isEmpty else {
            try await markDone()
            return
        }

        var thinkspaceAtoms = try await fetchAll(type: .thinkspace)
        var updatesByUUID: [String: Atom] = [:]
        var rootThinkspaceByProjectUUID: [String: String] = [:]

        for project in projects {
            let projectMetadata = project.metadataValue(as: ProjectMetadata.self)
            let projectColor = projectMetadata?.color
            let root = try await rootThinkspaceForMigratingProject(
                project,
                projectMetadata: projectMetadata,
                existingThinkspaces: thinkspaceAtoms,
                fallbackColorHex: projectColor
            )

            if !thinkspaceAtoms.contains(where: { $0.uuid == root.uuid }) {
                thinkspaceAtoms.append(root)
            }

            rootThinkspaceByProjectUUID[project.uuid] = root.uuid

            let updatedRoot = migratedRootThinkspaceAtom(
                root,
                project: project,
                colorHex: projectColor
            )
            updatesByUUID[updatedRoot.uuid] = updatedRoot

            for thinkspace in thinkspaceAtoms where thinkspace.uuid != root.uuid {
                guard let migrated = migratedChildThinkspaceAtom(
                    thinkspace,
                    fromProjectUUID: project.uuid,
                    rootThinkspaceUUID: root.uuid,
                    fallbackColorHex: projectColor
                ) else { continue }
                updatesByUUID[migrated.uuid] = migrated
            }
        }

        let linkedAtoms = try await atomsWithProjectLinks()
        for atom in linkedAtoms where atom.type != .project {
            guard let migrated = migratedProjectLinksAtom(
                atom,
                rootThinkspaceByProjectUUID: rootThinkspaceByProjectUUID
            ) else { continue }
            updatesByUUID[migrated.uuid] = migrated
        }

        if !updatesByUUID.isEmpty {
            try await updateBatch(Array(updatesByUUID.values))
        }

        try await deleteBatch(uuids: projects.map(\.uuid))

        try await markDone()

        NotificationCenter.default.post(name: .atomsDidChange, object: nil)
        await ThinkspaceManager.shared.loadThinkspaces()
    }

    private func rootThinkspaceForMigratingProject(
        _ project: Atom,
        projectMetadata: ProjectMetadata?,
        existingThinkspaces: [Atom],
        fallbackColorHex: String?
    ) async throws -> Atom {
        if let rootUUID = projectMetadata?.rootThinkspaceUuid {
            if let root = existingThinkspaces.first(where: { $0.uuid == rootUUID }) {
                return root
            }
            if let root = try await fetch(uuid: rootUUID) {
                return root
            }
        }

        if let root = existingThinkspaces.first(where: { atom in
            guard let metadata = atom.metadataValue(as: ThinkspaceMetadata.self) else { return false }
            return metadata.projectUuid == project.uuid && (metadata.isRootThinkspace || metadata.parentThinkspaceId == nil)
        }) {
            return root
        }

        let title = project.title ?? "Untitled Thinkspace"
        let metadata = ThinkspaceMetadata(
            name: title,
            accentColorHex: fallbackColorHex
        )
        let root = Atom.new(
            type: .thinkspace,
            title: title,
            body: project.body,
            metadata: try? String(data: JSONEncoder().encode(metadata), encoding: .utf8)
        )
        return try await create(root)
    }

    private func migratedRootThinkspaceAtom(
        _ root: Atom,
        project: Atom,
        colorHex: String?
    ) -> Atom {
        var metadata = root.metadataValue(as: ThinkspaceMetadata.self)
            ?? ThinkspaceMetadata(name: root.title ?? project.title ?? "Untitled Thinkspace")
        metadata.name = root.title ?? project.title ?? metadata.name
        metadata.projectUuid = nil
        metadata.parentThinkspaceId = nil
        metadata.isRootThinkspace = false
        if metadata.accentColorHex == nil {
            metadata.accentColorHex = colorHex
        }

        var updated = root.withMetadata(metadata)
        if updated.title == nil {
            updated.title = project.title
        }
        return updated
    }

    private func migratedChildThinkspaceAtom(
        _ thinkspace: Atom,
        fromProjectUUID projectUUID: String,
        rootThinkspaceUUID: String,
        fallbackColorHex: String?
    ) -> Atom? {
        guard var metadata = thinkspace.metadataValue(as: ThinkspaceMetadata.self),
              metadata.projectUuid == projectUUID else {
            return nil
        }

        metadata.projectUuid = nil
        if metadata.parentThinkspaceId == nil {
            metadata.parentThinkspaceId = rootThinkspaceUUID
        }
        if metadata.accentColorHex == nil {
            metadata.accentColorHex = fallbackColorHex
        }

        return thinkspace.withMetadata(metadata)
    }

    private func atomsWithProjectLinks() async throws -> [Atom] {
        try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(sql: "links LIKE ?", arguments: ["%\"type\":\"project\"%"])
                .fetchAll(db)
        }
    }

    private func migratedProjectLinksAtom(
        _ atom: Atom,
        rootThinkspaceByProjectUUID: [String: String]
    ) -> Atom? {
        var didChange = false
        let migratedLinks = atom.linksList.map { link -> AtomLink in
            guard link.linkType == .project,
                  let rootThinkspaceUUID = rootThinkspaceByProjectUUID[link.uuid] else {
                return link
            }
            didChange = true
            return .thinkspace(rootThinkspaceUUID)
        }

        guard didChange else { return nil }
        return atom.withLinks(Self.deduplicatedLinks(migratedLinks))
    }

    private static func deduplicatedLinks(_ links: [AtomLink]) -> [AtomLink] {
        var seen: Set<String> = []
        var result: [AtomLink] = []
        for link in links {
            let key = "\(link.type)|\(link.uuid)|\(link.entityType ?? "")"
            guard seen.insert(key).inserted else { continue }
            result.append(link)
        }
        return result
    }
}

// MARK: - Statistics

extension AtomRepository {

    /// Get counts by type — one GROUP BY, not one COUNT query per AtomType
    /// case (81 cases = 81 index scans on the launch path). Absent types
    /// still report 0.
    func countsByType() async throws -> [AtomType: Int] {
        try await database.asyncRead { db in
            var counts: [AtomType: Int] = [:]
            for type in AtomType.allCases {
                counts[type] = 0
            }

            let rows = try Row.fetchAll(
                db,
                sql: "SELECT type, COUNT(*) AS n FROM atoms WHERE is_deleted = 0 GROUP BY type"
            )
            for row in rows {
                if let raw = row["type"] as String?,
                   let type = AtomType(rawValue: raw) {
                    counts[type] = (row["n"] as Int?) ?? 0
                }
            }

            return counts
        }
    }

    /// One bit: does this Mac hold any live atoms at all? Cheaper than any
    /// counting path — EXISTS short-circuits on the first row.
    func hasAnyAtoms() async throws -> Bool {
        try await database.asyncRead { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM atoms WHERE is_deleted = 0)"
            ) ?? false
        }
    }

    /// Get total atom count
    func totalCount() async throws -> Int {
        try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.isDeleted == false)
                .fetchCount(db)
        }
    }

    /// Count atoms by type
    func count(type: AtomType) async throws -> Int {
        try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.type == type.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)
                .fetchCount(db)
        }
    }

    /// Count atoms across multiple types without hydrating them.
    func count(types: [AtomType]) async throws -> Int {
        let typeStrings = types.map { $0.rawValue }
        return try await database.asyncRead { db in
            try Atom
                .filter(typeStrings.contains(Column("type")))
                .filter(Atom.CodingKeys.isDeleted == false)
                .fetchCount(db)
        }
    }

    /// Count research atoms that represent saved swipe files without hydrating the gallery.
    func countSwipeFiles() async throws -> Int {
        try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.type == AtomType.research.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(sql: "metadata LIKE '%\"isSwipeFile\":true%'")
                .fetchCount(db)
        }
    }
}

// MARK: - Legacy Compatibility Extensions

extension AtomRepository {

    /// Fetch atoms by legacy project ID (for backward compatibility)
    /// Searches for atoms linked to project via old projectId field or links array
    func fetchByProjectId(_ projectId: Int64) async throws -> [Atom] {
        try await database.asyncRead { db in
            // Check both links array and structured data for projectId
            try Atom
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(
                    sql: "links LIKE ? OR structured LIKE ?",
                    arguments: ["%\"projectId\":\(projectId)%", "%\"projectId\":\(projectId)%"]
                )
                .order(Atom.CodingKeys.updatedAt.desc)
                .fetchAll(db)
        }
    }

    /// Fetch tasks by status (uses metadata JSON)
    func fetchTasksByStatus(_ status: String) async throws -> [Atom] {
        try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.type == AtomType.task.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(sql: "metadata LIKE ?", arguments: ["%\"status\":\"\(status)\"%"])
                .order(Atom.CodingKeys.updatedAt.desc)
                .fetchAll(db)
        }
    }

    /// Fetch atoms by multiple types (convenience)
    func fetchByTypes(_ types: [AtomType]) async throws -> [Atom] {
        try await fetchAll(types: types)
    }

    /// Fuzzy find client profile by name (title-only, exact-first to prevent cross-client contamination)
    func fuzzyFindClient(query: String) async throws -> Atom? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return try await database.asyncRead { db in
            // Phase 1: Exact title match (SQLite LIKE is case-insensitive for ASCII)
            if let exact = try Atom
                .filter(Atom.CodingKeys.type == AtomType.clientProfile.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(Column("title").like(trimmed))
                .fetchOne(db) {
                return exact
            }

            // Phase 2: Title starts with query (e.g. "Ben" → "Ben Johnson")
            if let startsWith = try Atom
                .filter(Atom.CodingKeys.type == AtomType.clientProfile.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(Column("title").like("\(trimmed)%"))
                .fetchOne(db) {
                return startsWith
            }

            // Phase 3: Title contains query (e.g. "Ben" → "Sir Ben Kingsley")
            return try Atom
                .filter(Atom.CodingKeys.type == AtomType.clientProfile.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(Column("title").like("%\(trimmed)%"))
                .order(Atom.CodingKeys.updatedAt.desc)
                .fetchOne(db)
        }
    }

    /// Fuzzy find project by name (for voice command routing)
    func fuzzyFindProject(query: String) async throws -> Atom? {
        let pattern = "%\(query)%"
        return try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.type == AtomType.project.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(Column("title").like(pattern))
                .order(Atom.CodingKeys.updatedAt.desc)
                .fetchOne(db)
        }
    }
}

// MARK: - Uncommitted Item Workflow

extension AtomRepository {

    /// Fetch uncommitted items (not archived, not deleted)
    func fetchUncommittedItems(archived: Bool = false) async throws -> [Atom] {
        try await database.asyncRead { db in
            var request = Atom
                .filter(Atom.CodingKeys.type == AtomType.uncommittedItem.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)

            if archived {
                request = request.filter(sql: "metadata LIKE '%\"isArchived\":true%'")
            } else {
                request = request.filter(sql: "metadata NOT LIKE '%\"isArchived\":true%' OR metadata IS NULL")
            }

            return try request
                .order(Atom.CodingKeys.createdAt.desc)
                .fetchAll(db)
        }
    }

    /// Fetch uncommitted items by assignment status
    func fetchUncommittedByAssignmentStatus(_ status: String) async throws -> [Atom] {
        try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.type == AtomType.uncommittedItem.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(sql: "metadata NOT LIKE '%\"isArchived\":true%' OR metadata IS NULL")
                .filter(sql: "metadata LIKE ?", arguments: ["%\"assignmentStatus\":\"\(status)\"%"])
                .order(Atom.CodingKeys.createdAt.desc)
                .fetchAll(db)
        }
    }

    /// Fetch uncommitted items by inferred type
    func fetchUncommittedByInferredType(_ inferredType: String) async throws -> [Atom] {
        try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.type == AtomType.uncommittedItem.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(sql: "metadata NOT LIKE '%\"isArchived\":true%' OR metadata IS NULL")
                .filter(sql: "metadata LIKE ?", arguments: ["%\"inferredType\":\"\(inferredType)\"%"])
                .order(Atom.CodingKeys.createdAt.desc)
                .fetchAll(db)
        }
    }

    /// Fetch recently promoted uncommitted items
    func fetchRecentlyPromoted(limit: Int = 10) async throws -> [Atom] {
        try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.type == AtomType.uncommittedItem.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(sql: "metadata LIKE '%\"isArchived\":true%'")
                .filter(sql: "metadata LIKE '%\"promotedTo\":%'")
                .order(Atom.CodingKeys.updatedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Parse a metadata column for read-modify-write, refusing to proceed when the
    /// column holds data that fails to parse — defaulting to [:] and re-saving
    /// would erase the real (still-recoverable) metadata.
    private func parsedMetadataForMutation(_ atom: Atom, context: String) -> [String: Any]? {
        guard let existing = atom.metadata, !existing.isEmpty else { return [:] }
        guard let data = existing.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            PersistenceHealth.note(.decodeFailure, context: context, detail: "metadata unparseable; refusing mutation that would erase it")
            return nil
        }
        return parsed
    }

    /// Archive an uncommitted item
    func archiveUncommittedItem(uuid: String) async throws {
        guard var atom = try await fetch(uuid: uuid) else { return }
        guard var metadata = parsedMetadataForMutation(atom, context: "archiveUncommittedItem(\(uuid.prefix(8)))") else { return }

        metadata["isArchived"] = true

        // Update atom with new metadata
        if let jsonData = try? JSONSerialization.data(withJSONObject: metadata),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            atom.metadata = jsonString
            _ = try await update(atom)
        }
    }

    /// Promote an uncommitted item (archive and link to new entity)
    func promoteUncommittedItem(uuid: String, toType: AtomType, entityUuid: String) async throws {
        guard var atom = try await fetch(uuid: uuid) else { return }
        guard var metadata = parsedMetadataForMutation(atom, context: "promoteUncommittedItem(\(uuid.prefix(8)))") else { return }

        metadata["isArchived"] = true
        metadata["promotedTo"] = toType.rawValue
        metadata["promotedEntityUuid"] = entityUuid

        // Update atom with new metadata
        if let jsonData = try? JSONSerialization.data(withJSONObject: metadata),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            atom.metadata = jsonString
            _ = try await update(atom)
        }
    }

    /// Restore an archived uncommitted item
    func restoreUncommittedItem(uuid: String) async throws {
        guard var atom = try await fetch(uuid: uuid) else { return }
        guard var metadata = parsedMetadataForMutation(atom, context: "restoreUncommittedItem(\(uuid.prefix(8)))") else { return }

        // Remove archived state
        metadata["isArchived"] = false
        metadata.removeValue(forKey: "promotedTo")
        metadata.removeValue(forKey: "promotedEntityUuid")
        metadata.removeValue(forKey: "promotedEntityId")

        // Update atom with new metadata
        if let jsonData = try? JSONSerialization.data(withJSONObject: metadata),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            atom.metadata = jsonString
            _ = try await update(atom)
        }
    }

    /// Update assignment status for uncommitted item
    func updateUncommittedAssignmentStatus(uuid: String, status: String, projectUuid: String?) async throws {
        guard var atom = try await fetch(uuid: uuid) else { return }
        guard var metadata = parsedMetadataForMutation(atom, context: "updateUncommittedAssignmentStatus(\(uuid.prefix(8)))") else { return }

        metadata["assignmentStatus"] = status
        if let projectUuid = projectUuid {
            metadata["projectUuid"] = projectUuid
        }

        // Apply metadata + links in a single update so the second write can't
        // race the first one's version bump.
        if let jsonData = try? JSONSerialization.data(withJSONObject: metadata),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            atom.metadata = jsonString
        }

        if let projectUuid = projectUuid, !atom.linksAreCorrupt {
            var links = atom.linksList
            // Remove existing project links
            links.removeAll { $0.type == "project" }
            // Add new project link
            links.append(AtomLink.project(projectUuid))
            if let encoded = try? String(data: JSONEncoder().encode(links), encoding: .utf8) {
                atom.links = encoded
            }
        }

        _ = try await update(atom)
    }

    /// Count uncommitted items by assignment status
    func countUncommittedByAssignmentStatus(_ status: String) async throws -> Int {
        try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.type == AtomType.uncommittedItem.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(sql: "metadata NOT LIKE '%\"isArchived\":true%' OR metadata IS NULL")
                .filter(sql: "metadata LIKE ?", arguments: ["%\"assignmentStatus\":\"\(status)\"%"])
                .fetchCount(db)
        }
    }

    /// Count all uncommitted items (not archived)
    func countUncommittedItems() async throws -> Int {
        try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.type == AtomType.uncommittedItem.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(sql: "metadata NOT LIKE '%\"isArchived\":true%' OR metadata IS NULL")
                .fetchCount(db)
        }
    }
}

// MARK: - FTS5 Search Integration

extension AtomRepository {

    /// Full-text search using FTS5 index (if available)
    func ftsSearch(query: String, types: [AtomType]? = nil, limit: Int = 50) async throws -> [Atom] {
        // First try FTS5 search via search_index table
        do {
            let results = try await database.asyncRead { db -> [Atom] in
                let typeFilter: String
                if let types = types, !types.isEmpty {
                    let typeList = types.map { "'\($0.rawValue)'" }.joined(separator: ",")
                    typeFilter = "AND a.type IN (\(typeList))"
                } else {
                    typeFilter = ""
                }

                let rows = try Row.fetchAll(db, sql: """
                    SELECT a.* FROM atoms a
                    JOIN atoms_fts s ON s.rowid = a.id
                    WHERE atoms_fts MATCH ? AND a.is_deleted = 0 \(typeFilter)
                    ORDER BY rank
                    LIMIT ?
                    """, arguments: [query, limit])

                return rows.compactMap { try? Atom(row: $0) }
            }
            return results
        } catch {
            // Fallback to LIKE search if FTS5 not available
            return try await search(query: query, types: types)
        }
    }
}

// MARK: - Convenience Create Methods

extension AtomRepository {

    /// Create a new uncommitted item
    @discardableResult
    func createUncommittedItem(
        rawText: String,
        captureMethod: String = "keyboard",
        assignmentStatus: String = "unassigned",
        projectUuid: String? = nil,
        inferredType: String? = nil,
        inferredProject: String? = nil,
        inferredProjectConfidence: Double? = nil
    ) async throws -> Atom {
        var metadata: [String: Any] = [
            "captureMethod": captureMethod,
            "assignmentStatus": assignmentStatus,
            "isArchived": false
        ]

        if let inferredType = inferredType {
            metadata["inferredType"] = inferredType
        }
        if let inferredProject = inferredProject {
            metadata["inferredProject"] = inferredProject
        }
        if let confidence = inferredProjectConfidence {
            metadata["inferredProjectConfidence"] = confidence
        }

        var links: [AtomLink] = []
        if let projectUuid = projectUuid {
            links.append(.project(projectUuid))
            metadata["projectUuid"] = projectUuid
        }

        let metadataString = try? String(
            data: JSONSerialization.data(withJSONObject: metadata),
            encoding: .utf8
        )

        return try await create(
            type: .uncommittedItem,
            title: nil,
            body: rawText,
            metadata: metadataString,
            links: links.isEmpty ? nil : links
        )
    }

    /// Create a new content atom
    @discardableResult
    func createContent(title: String, body: String? = nil, contentType: String = "note") async throws -> Atom {
        let metadata = ContentMetadata(contentType: contentType)

        return try await create(
            type: .content,
            title: title,
            body: body,
            metadata: try? String(data: JSONEncoder().encode(metadata), encoding: .utf8)
        )
    }

    /// Create a new research atom
    @discardableResult
    func createResearch(
        title: String,
        url: String,
        summary: String? = nil,
        researchType: String = "article"
    ) async throws -> Atom {
        var metadata: [String: Any] = [
            "url": url,
            "researchType": researchType,
            "processingStatus": "pending"
        ]
        if let summary = summary {
            metadata["summary"] = summary
        }

        let metadataString = try? String(
            data: JSONSerialization.data(withJSONObject: metadata),
            encoding: .utf8
        )

        return try await create(
            type: .research,
            title: title,
            body: summary,
            metadata: metadataString
        )
    }

    /// Create a new connection (mental model link)
    @discardableResult
    func createConnection(
        title: String? = nil,
        sourceUuid: String,
        targetUuid: String,
        connectionType: String = "related"
    ) async throws -> Atom {
        let links: [AtomLink] = [
            AtomLink(type: "source", uuid: sourceUuid),
            AtomLink(type: "target", uuid: targetUuid)
        ]

        let metadata: [String: Any] = [
            "connectionType": connectionType,
            "sourceUuid": sourceUuid,
            "targetUuid": targetUuid
        ]

        let metadataString = try? String(
            data: JSONSerialization.data(withJSONObject: metadata),
            encoding: .utf8
        )

        return try await create(
            type: .connection,
            title: title,
            metadata: metadataString,
            links: links
        )
    }

    /// Create a new schedule block
    @discardableResult
    func createScheduleBlock(
        title: String,
        startTime: String,
        endTime: String? = nil,
        blockType: String = "task"
    ) async throws -> Atom {
        var metadata: [String: Any] = [
            "startTime": startTime,
            "blockType": blockType
        ]
        if let endTime = endTime {
            metadata["endTime"] = endTime
        }

        let metadataString = try? String(
            data: JSONSerialization.data(withJSONObject: metadata),
            encoding: .utf8
        )

        return try await create(
            type: .scheduleBlock,
            title: title,
            metadata: metadataString
        )
    }
}

// MARK: - IdeaForge Convenience Methods

extension AtomRepository {

    /// Create an enriched idea with optional format, client, and capture source
    @discardableResult
    func createEnrichedIdea(
        title: String?,
        content: String,
        tags: [String] = [],
        contentFormat: ContentFormat? = nil,
        platform: IdeaPlatform? = nil,
        clientQuery: String? = nil,
        captureSource: String? = nil,
        originSwipeUUID: String? = nil,
        projectUuid: String? = nil
    ) async throws -> Atom {
        var metadata = IdeaMetadata(
            tags: tags,
            priority: "Medium",
            isPinned: false,
            ideaStatus: .spark,
            contentFormat: contentFormat,
            platform: platform,
            captureSource: captureSource,
            originSwipeUUID: originSwipeUUID
        )

        var links: [AtomLink] = []
        if let projectUuid = projectUuid {
            links.append(.project(projectUuid))
        }

        // Auto-link to client if query provided
        if let clientQuery = clientQuery {
            if let client = try await fuzzyFindClient(query: clientQuery) {
                metadata.clientUUID = client.uuid
                links.append(.ideaToClient(client.uuid))
            }
        }

        // Auto-link to origin swipe
        if let swipeUUID = originSwipeUUID {
            links.append(.ideaToSwipe(swipeUUID))
        }

        let idea = try await create(
            type: .idea,
            title: title,
            body: content,
            metadata: try? String(data: JSONEncoder().encode(metadata), encoding: .utf8),
            links: links.isEmpty ? nil : links
        )

        // Run quick insight in background (on-device, fast)
        Task {
            await IdeaInsightEngine.shared.quickEnrich(atom: idea)
        }

        return idea
    }

    /// Get all client profile atoms
    func clientProfiles() async throws -> [Atom] {
        try await fetchAll(type: .clientProfile)
    }

    /// Create a client profile atom
    @discardableResult
    func createClientProfile(
        name: String,
        handles: [String: String]? = nil,
        niche: String? = nil,
        color: String? = nil
    ) async throws -> Atom {
        let metadata = ClientMetadata(
            handles: handles,
            niche: niche,
            color: color,
            isActive: true
        )

        return try await create(
            type: .clientProfile,
            title: name,
            metadata: try? String(data: JSONEncoder().encode(metadata), encoding: .utf8)
        )
    }
}

// MARK: - Swipe Intelligence Taxonomy Methods

extension AtomRepository {

    /// Create a content creator atom
    @discardableResult
    func createCreator(name: String, handle: String, platform: String) async throws -> Atom {
        let metadata = CreatorMetadata(
            handle: handle,
            platform: platform,
            swipeCount: 0,
            isActive: true
        )

        return try await create(
            type: .creator,
            title: name,
            metadata: try? String(data: JSONEncoder().encode(metadata), encoding: .utf8)
        )
    }

    /// Fetch creator atoms with optional platform/niche filters
    func fetchCreators(platform: String? = nil, niche: String? = nil) async throws -> [Atom] {
        return try await database.asyncRead { db in
            var request = Atom
                .filter(Atom.CodingKeys.type == AtomType.creator.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)

            if let platform = platform {
                request = request.filter(
                    sql: "metadata LIKE ?",
                    arguments: ["%\"platform\":\"\(platform)\"%"]
                )
            }

            if let niche = niche {
                request = request.filter(
                    sql: "metadata LIKE ?",
                    arguments: ["%\"niche\":\"\(niche)\"%"]
                )
            }

            return try request
                .order(Column("title").asc)
                .fetchAll(db)
        }
    }

    /// Fetch taxonomy value atoms for a specific dimension
    func fetchTaxonomyValues(dimension: String) async throws -> [Atom] {
        return try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.type == AtomType.taxonomyValue.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(
                    sql: "metadata LIKE ?",
                    arguments: ["%\"dimension\":\"\(dimension)\"%"]
                )
                .order(sql: "json_extract(metadata, '$.sortOrder') ASC")
                .fetchAll(db)
        }
    }

    /// Create a taxonomy value atom
    @discardableResult
    func createTaxonomyValue(dimension: String, value: String, sortOrder: Int = 0, isDefault: Bool = false) async throws -> Atom {
        let metadata = TaxonomyValueMetadata(
            dimension: dimension,
            value: value,
            sortOrder: sortOrder,
            isDefault: isDefault
        )

        return try await create(
            type: .taxonomyValue,
            title: value,
            metadata: try? String(data: JSONEncoder().encode(metadata), encoding: .utf8)
        )
    }

    /// Query swipe files by taxonomy dimensions. All parameters are optional;
    /// nil parameters are ignored (partial matching). Results ordered by hookScore descending.
    func fetchSwipesByTaxonomy(
        contentType: ContentFormat? = nil,
        narrative: NarrativeStyle? = nil,
        niche: String? = nil,
        creatorUUID: String? = nil
    ) async throws -> [Atom] {
        // Fetch all swipe file atoms, then filter in-memory by swipeAnalysis fields
        let allSwipes = try await database.asyncRead { db in
            var request = Atom
                .filter(Atom.CodingKeys.type == AtomType.research.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(sql: "metadata LIKE '%\"isSwipeFile\":true%'")

            // Pre-filter by creatorUUID in structured JSON if provided
            if let creatorUUID = creatorUUID {
                request = request.filter(
                    sql: "structured LIKE ?",
                    arguments: ["%\"creatorUUID\":\"\(creatorUUID)\"%"]
                )
            }

            // Pre-filter by niche in structured JSON if provided
            if let niche = niche {
                request = request.filter(
                    sql: "structured LIKE ?",
                    arguments: ["%\"niche\":\"\(niche)\"%"]
                )
            }

            // Pre-filter by narrative in structured JSON if provided
            if let narrative = narrative {
                request = request.filter(
                    sql: "structured LIKE ?",
                    arguments: ["%\"primaryNarrative\":\"\(narrative.rawValue)\"%"]
                )
            }

            // Pre-filter by content format in structured JSON if provided
            if let contentType = contentType {
                request = request.filter(
                    sql: "structured LIKE ?",
                    arguments: ["%\"swipeContentFormat\":\"\(contentType.rawValue)\"%"]
                )
            }

            return try request.fetchAll(db)
        }

        // Sort by hookScore descending (from swipeAnalysis)
        let sorted = allSwipes.sorted { a, b in
            let scoreA = a.swipeAnalysis?.hookScore ?? 0
            let scoreB = b.swipeAnalysis?.hookScore ?? 0
            return scoreA > scoreB
        }

        return sorted
    }

    // MARK: - Engagement Queries

    /// Engagement sort options for swipe queries
    enum EngagementSort: String, CaseIterable, Sendable {
        case likes, views, comments, engagementRate, recent
    }

    /// Fetch swipe files sorted by an engagement metric
    func fetchSwipesByEngagement(
        creatorUUID: String? = nil,
        sortBy: EngagementSort = .likes,
        limit: Int = 50
    ) async throws -> [Atom] {
        let allSwipes = try await fetchSwipesByTaxonomy(creatorUUID: creatorUUID)

        // Sort by the requested metric (in-memory, since structured is JSON)
        let sorted: [Atom]
        switch sortBy {
        case .likes:
            sorted = allSwipes.sorted {
                ($0.swipeAnalysis?.likesCount ?? 0) > ($1.swipeAnalysis?.likesCount ?? 0)
            }
        case .views:
            sorted = allSwipes.sorted {
                ($0.swipeAnalysis?.viewsCount ?? 0) > ($1.swipeAnalysis?.viewsCount ?? 0)
            }
        case .comments:
            sorted = allSwipes.sorted {
                ($0.swipeAnalysis?.commentsCount ?? 0) > ($1.swipeAnalysis?.commentsCount ?? 0)
            }
        case .engagementRate:
            sorted = allSwipes.sorted {
                ($0.swipeAnalysis?.engagementRate ?? 0) > ($1.swipeAnalysis?.engagementRate ?? 0)
            }
        case .recent:
            sorted = allSwipes.sorted {
                ($0.swipeAnalysis?.publishedAt ?? .distantPast) > ($1.swipeAnalysis?.publishedAt ?? .distantPast)
            }
        }

        return Array(sorted.prefix(limit))
    }

    /// Check which post shortcodes already exist as swipe atoms
    func findExistingShortcodes(_ shortcodes: [String]) async throws -> Set<String> {
        guard !shortcodes.isEmpty else { return [] }

        let allSwipes = try await database.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.type == AtomType.research.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)
                .filter(sql: "metadata LIKE '%\"isSwipeFile\":true%'")
                .filter(sql: "structured LIKE '%postShortcode%'")
                .fetchAll(db)
        }

        // Extract shortcodes from swipe analysis
        var found = Set<String>()
        for swipe in allSwipes {
            if let sc = swipe.swipeAnalysis?.postShortcode, shortcodes.contains(sc) {
                found.insert(sc)
            }
        }
        return found
    }
}

// MARK: - Errors

enum AtomRepositoryError: LocalizedError {
    case notFound(String)
    case versionConflict(uuid: String, expectedVersion: Int64)

    var errorDescription: String? {
        switch self {
        case .notFound(let uuid):
            return "Atom not found: \(uuid)"
        case .versionConflict(let uuid, let version):
            return "Version conflict for atom \(uuid): expected v\(version) but it was already modified"
        }
    }

    var isVersionConflict: Bool {
        if case .versionConflict = self { return true }
        return false
    }
}
