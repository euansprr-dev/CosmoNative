import Foundation
import GRDB

/// One membership contract for capture, materials, production and research.
/// Canvas rows are the compatibility backing; adding a reference never places it.
enum SpaceMembershipService {
    static func memberUUIDs(in spaceID: String) async throws -> Set<String> {
        try await CosmoDatabase.shared.asyncRead { db in
            try String.fetchSet(db, sql: """
                SELECT DISTINCT b.entity_uuid FROM canvas_blocks b
                JOIN atoms a ON a.uuid = b.entity_uuid AND a.is_deleted = 0
                WHERE b.thinkspace_id = ? AND b.document_type = 'home'
                  AND b.document_id = 0 AND b.is_deleted = 0
                """, arguments: [spaceID])
        }
    }

    static func spaceIDs(containing atomUUID: String) async throws -> [String] {
        try await CosmoDatabase.shared.asyncRead { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT thinkspace_id FROM canvas_blocks
                WHERE entity_uuid = ? AND document_type = 'home' AND document_id = 0
                  AND is_deleted = 0 AND thinkspace_id IS NOT NULL
                ORDER BY thinkspace_id
                """, arguments: [atomUUID])
        }
    }

    @MainActor
    @discardableResult
    static func add(_ atom: Atom, to spaceID: String) async throws -> String {
        let block = CanvasBlock.fromAtom(atom, position: .zero)
        let record = CanvasBlockRecord.from(block, documentType: "home", documentId: 0,
                                           thinkspaceId: spaceID, isPlaced: false)
        let id = try await CosmoDatabase.shared.asyncWrite { db in
            guard try Atom.filter(Column("uuid") == spaceID).filter(Column("type") == AtomType.thinkspace.rawValue)
                .filter(Column("is_deleted") == false).fetchCount(db) == 1,
                try Atom.filter(Column("uuid") == atom.uuid).filter(Column("is_deleted") == false).fetchCount(db) == 1 else {
                throw ContentPipelineError.contentNotFound
            }
            if let existing = try String.fetchOne(db, sql: """
                SELECT id FROM canvas_blocks WHERE entity_uuid = ? AND thinkspace_id = ?
                AND document_type = 'home' AND document_id = 0 AND is_deleted = 0 LIMIT 1
                """, arguments: [atom.uuid, spaceID]) { return existing }
            var row = record
            try row.insert(db)
            return row.id
        }
        NotificationCenter.default.post(name: Notification.Name("com.cosmo.canvasBlocksChanged"), object: nil)
        return id
    }

    @MainActor
    static func inherit(from sourceUUID: String, to output: Atom) async throws {
        for spaceID in try await spaceIDs(containing: sourceUUID) {
            try await add(output, to: spaceID)
        }
    }
}

/// Every editorial surface uses the same eligibility and scope, including the
/// calendar shelf. An idea remains reusable after it has produced a piece.
enum ContentIdeaLoader {
    static func load(scope: PipelineScope, archived: Bool = false) async throws -> [Atom] {
        try await CosmoDatabase.shared.asyncRead { db in
            var request = Atom.filter(Column("type") == AtomType.idea.rawValue)
                .filter(Column("is_deleted") == false)
            let status = "CASE WHEN json_valid(metadata) THEN json_extract(metadata, '$.ideaStatus') END"
            request = archived
                ? request.filter(sql: "\(status) = 'archived'")
                : request.filter(sql: "COALESCE(\(status), '') != 'archived'")
            return try scope.constraining(request, clientKey: "clientUUID")
                .order(Column("updated_at").desc, Column("uuid")).fetchAll(db)
        }
    }
}

extension PipelineScope {
    func constraining(_ request: QueryInterfaceRequest<Atom>, clientKey: String) -> QueryInterfaceRequest<Atom> {
        let key = clientKey == "clientUUID" ? "clientUUID" : "clientProfileUUID"
        let client = "CASE WHEN json_valid(metadata) THEN json_extract(metadata, '$.\(key)') END"
        switch self {
        case .all: return request
        case .client(let uuid): return request.filter(sql: "\(client) = ?", arguments: [uuid])
        case .unassigned: return request.filter(sql: "COALESCE(\(client), '') = ''")
        case .space(let uuid):
            return request.filter(sql: """
                uuid IN (SELECT entity_uuid FROM canvas_blocks
                WHERE thinkspace_id = ? AND document_type = 'home' AND document_id = 0
                AND is_deleted = 0 AND entity_uuid IS NOT NULL)
                """, arguments: [uuid])
        }
    }
}

extension SpaceMembershipService {
    /// Creating a document in a Space creates membership, never a position.
    @MainActor
    static func create(type: AtomType, title: String, in spaceID: String) async throws -> Atom {
        try await create(Atom.new(type: type, title: title, body: ""), in: spaceID)
    }

    @MainActor static func create(_ prepared: Atom, in spaceID: String) async throws -> Atom {
        let template = CanvasBlockRecord.from(CanvasBlock.fromAtom(prepared, position: .zero),
                                             documentType: "home", documentId: 0, thinkspaceId: spaceID, isPlaced: false)
        let saved = try await CosmoDatabase.shared.asyncWrite { db in
            guard try Atom.filter(Column("uuid") == spaceID).filter(Column("type") == AtomType.thinkspace.rawValue)
                .filter(Column("is_deleted") == false).fetchCount(db) == 1 else {
                throw ContentPipelineError.contentNotFound
            }
            var atom = prepared
            try atom.insert(db)
            atom.id = db.lastInsertedRowID
            var member = template
            member.entityId = Int(atom.id ?? 0)
            try member.insert(db)
            return atom
        }
        await ChangeTracker.shared.trackInsert(table: "atoms", entity: saved)
        try? await NodeGraphEngine.shared.handleAtomCreated(saved)
        Task.detached(priority: .utility) { await RecallIndexer.shared.noteAtomChanged(saved) }
        CosmoUndoManager.shared.register(InlineUndoAction(
            actionDescription: "Create \(prepared.type.displayName.lowercased())",
            undo: { try? await AtomRepository.shared.delete(uuid: saved.uuid); notifyMembersChanged() },
            redo: { try? await AtomRepository.shared.restore(uuid: saved.uuid); notifyMembersChanged() }
        ))
        notifyMembersChanged()
        return saved
    }

    @MainActor static func notifyMembersChanged() {
        NotificationCenter.default.post(name: Notification.Name("com.cosmo.canvasBlocksChanged"), object: nil)
    }

    /// Removing membership keeps the material itself and every other Space.
    @MainActor
    static func remove(_ atomUUID: String, from spaceID: String) async throws {
        try await CosmoDatabase.shared.asyncWrite { db in
            try db.execute(sql: """
                UPDATE canvas_blocks SET is_deleted = 1, updated_at = ?, _local_version = COALESCE(_local_version, 0) + 1,
                _local_pending = 1 WHERE entity_uuid = ? AND thinkspace_id = ? AND document_type = 'home' AND document_id = 0
                """, arguments: [ISO8601.string(from: Date()), atomUUID, spaceID])
        }
        notifyMembersChanged()
    }
}

/// A Space deletion changes membership separately from the underlying originals.
/// Keep the exact affected IDs so undo never revives previously deleted items.
enum SpaceDeletionService {
    enum Contents: Sendable { case keep, delete }
    struct Change: Sendable {
        var deletedUUIDs: Set<String>
        var membershipIDs: [String]
        var promotedSpaces: [String: String]
    }

    static func delete(_ spaceID: String, contents: Contents, db: Database) throws -> Change {
        let spaces = try Atom.filter(Column("type") == AtomType.thinkspace.rawValue)
            .filter(Column("is_deleted") == false).fetchAll(db)
        guard spaces.contains(where: { $0.uuid == spaceID }) else { throw SpaceCompositionError.notFound }
        var spaceIDs: Set<String> = [spaceID]
        if contents == .delete {
            var previousCount = 0
            while previousCount != spaceIDs.count {
                previousCount = spaceIDs.count
                for space in spaces {
                    if let parent = space.metadataValue(as: ThinkspaceMetadata.self)?.parentThinkspaceId,
                       spaceIDs.contains(parent) { spaceIDs.insert(space.uuid) }
                }
            }
        }
        var deleted = spaceIDs
        if contents == .delete {
            for id in spaceIDs {
                deleted.formUnion(try String.fetchAll(db, sql: """
                    SELECT DISTINCT b.entity_uuid FROM canvas_blocks b
                    JOIN atoms a ON a.uuid = b.entity_uuid AND a.is_deleted = 0
                    WHERE b.thinkspace_id = ? AND b.is_deleted = 0
                    """, arguments: [id]))
            }
        }
        let promoted = contents == .keep ? Dictionary(uniqueKeysWithValues: spaces.compactMap { atom -> (String, String)? in
            guard atom.metadataValue(as: ThinkspaceMetadata.self)?.parentThinkspaceId == spaceID else { return nil }
            return (atom.uuid, spaceID)
        }) : [:]
        // Include other placements of deleted originals, but never pre-existing tombstones.
        var membershipIDs = Set<String>()
        for id in spaceIDs {
            membershipIDs.formUnion(try String.fetchAll(db, sql:
                "SELECT id FROM canvas_blocks WHERE thinkspace_id = ? AND is_deleted = 0", arguments: [id]))
        }
        for id in deleted {
            membershipIDs.formUnion(try String.fetchAll(db, sql:
                "SELECT id FROM canvas_blocks WHERE entity_uuid = ? AND is_deleted = 0", arguments: [id]))
        }
        let change = Change(deletedUUIDs: deleted, membershipIDs: Array(membershipIDs), promotedSpaces: promoted)
        try apply(change, undo: false, db: db)
        return change
    }

    static func apply(_ change: Change, undo: Bool, db: Database) throws {
        let now = ISO8601.string(from: Date())
        for uuid in change.deletedUUIDs {
            guard let atom = try Atom.filter(Column("uuid") == uuid).fetchOne(db) else { throw SpaceCompositionError.notFound }
            if !undo { AtomRevisionWriter.snapshot(db, of: atom, source: .preDelete) }
            let metadata = undo ? AtomRepository.metadataStampingRestoredAt(atom.metadata, restoredAt: now) : atom.metadata
            try db.execute(sql: """
                UPDATE atoms SET is_deleted = ?, metadata = ?, updated_at = ?,
                    _local_version = _local_version + 1, _local_pending = 1 WHERE uuid = ?
                """, arguments: [!undo, metadata ?? atom.metadata, now, uuid])
        }
        for (uuid, parent) in change.promotedSpaces {
            guard let atom = try Atom.filter(Column("uuid") == uuid).fetchOne(db),
                  var metadata = atom.metadataValue(as: ThinkspaceMetadata.self) else { throw SpaceCompositionError.notFound }
            guard metadata.parentThinkspaceId == (undo ? nil : parent) else { throw SpaceCompositionError.conflict }
            metadata.parentThinkspaceId = undo ? parent : nil
            try db.execute(sql: """
                UPDATE atoms SET metadata = ?, updated_at = ?, _local_version = _local_version + 1,
                    _local_pending = 1 WHERE uuid = ?
                """, arguments: [metadata.mergedJSON(into: atom.metadata), now, uuid])
        }
        for id in change.membershipIDs {
            try db.execute(sql: """
                UPDATE canvas_blocks SET is_deleted = ?, updated_at = ?,
                    _local_version = COALESCE(_local_version, 0) + 1, _local_pending = 1 WHERE id = ?
                """, arguments: [!undo, now, id])
        }
    }

    @MainActor static func publish(_ change: Change, undo: Bool = false) async {
        for uuid in change.deletedUUIDs.union(change.promotedSpaces.keys) {
            if !undo && change.deletedUUIDs.contains(uuid) {
                await ChangeTracker.shared.trackDelete(table: "atoms", uuid: uuid, rowId: nil)
                try? await NodeGraphEngine.shared.handleAtomDeleted(atomUUID: uuid)
                Task.detached(priority: .utility) { await RecallIndexer.shared.noteAtomDeleted(uuid) }
            } else if let atom = try? await AtomRepository.shared.fetch(uuid: uuid) {
                await ChangeTracker.shared.trackUpdate(table: "atoms", entity: atom, skipVersionIncrement: true)
                if undo { try? await NodeGraphEngine.shared.handleAtomCreated(atom) }
                Task.detached(priority: .utility) { await RecallIndexer.shared.noteAtomChanged(atom) }
            }
        }
        NotificationCenter.default.post(name: .atomsDidChange, object: nil)
        NotificationCenter.default.post(name: SpaceCompositionService.didChange, object: nil)
        SpaceMembershipService.notifyMembersChanged()
    }
}
