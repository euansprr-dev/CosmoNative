import Foundation
import GRDB
import CryptoKit

/// Ordered authored pages, mixed groups and local canvases share atom identity.
/// Every structural command reads current rows inside one writer transaction.
/// No command rewrites a document body or turns native media into a page.
@MainActor
enum SpaceCompositionService {
    static let didChange = Notification.Name("com.cosmo.spaceCompositionChanged")
    static let didFailUndo = Notification.Name("com.cosmo.spaceCompositionUndoFailed")

    static func load(in spaceID: String) async throws -> SpaceCompositionSnapshot {
        let mapping = try await migrateLegacyGroups(in: spaceID)
        return try await CosmoDatabase.shared.asyncRead { db in
            try requireSpace(spaceID, db: db)
            return try SpaceCompositionSnapshot(spaceID: spaceID, atoms: members(in: spaceID, db: db), legacyGroupMapping: mapping)
        }
    }

    /// Finds where an original can actually be opened without filing it anywhere.
    /// Direct membership is the common fast path. A retained group member or
    /// authored section can also be reached through its containing objects.
    static func reachableSpaceIDs(containing atomUUID: String) async throws -> [String] {
        try await CosmoDatabase.shared.asyncRead { db in
            let source = try requireAtom(atomUUID, db: db)
            func spaces(containing uuids: [String]) throws -> Set<String> {
                var result = Set<String>()
                for start in stride(from: 0, to: uuids.count, by: 400) {
                    let ids = Array(uuids[start..<min(start + 400, uuids.count)])
                    let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
                    result.formUnion(try String.fetchAll(db, sql: """
                        SELECT DISTINCT s.uuid FROM canvas_blocks b
                        JOIN atoms s ON s.uuid = b.thinkspace_id AND s.type = 'thinkspace' AND s.is_deleted = 0
                        WHERE b.entity_uuid IN (\(placeholders)) AND b.document_type = 'home'
                        AND b.document_id = 0 AND b.is_deleted = 0
                        """, arguments: StatementArguments(ids)))
                }
                return result
            }
            let direct = try spaces(containing: [atomUUID])
            if !direct.isEmpty { return direct.sorted() }
            var visited: Set<String> = [atomUUID], frontier = [source], result = Set<String>()
            while !frontier.isEmpty {
                var parentIDs = Set<String>(), containers: [Atom] = []
                for atom in frontier {
                    let value = try atom.decodedSpaceComposition()
                    if value?.kind.isAuthored == true, let parent = value?.parentUUID { parentIDs.insert(parent) }
                }
                let pendingParents = Array(parentIDs.subtracting(visited))
                for start in stride(from: 0, to: pendingParents.count, by: 400) {
                    let ids = Array(pendingParents[start..<min(start + 400, pendingParents.count)])
                    let parents = try Atom.filter(ids.contains(Column("uuid"))).filter(Column("is_deleted") == false).fetchAll(db)
                    for parent in parents {
                        if try parent.decodedSpaceComposition()?.kind.isAuthored ?? (parent.type == .note) {
                            containers.append(parent)
                        }
                    }
                }
                let children = frontier.map(\.uuid)
                for start in stride(from: 0, to: children.count, by: 400) {
                    let ids = Array(children[start..<min(start + 400, children.count)])
                    let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
                    let groups = try Atom.fetchAll(db, sql: """
                        SELECT a.* FROM atoms a WHERE a.is_deleted = 0
                        AND CASE WHEN json_valid(a.metadata) THEN json_extract(a.metadata, '$.spaceComposition.kind') END = 'group'
                        AND EXISTS (SELECT 1 FROM json_each(CASE WHEN json_valid(a.metadata)
                            THEN json_extract(a.metadata, '$.spaceComposition.memberUUIDs') ELSE '[]' END) member
                            WHERE member.value IN (\(placeholders)))
                        """, arguments: StatementArguments(ids))
                    for group in groups {
                        _ = try group.decodedSpaceComposition()
                        containers.append(group)
                    }
                }
                frontier = containers.filter { visited.insert($0.uuid).inserted }
                result.formUnion(try spaces(containing: frontier.map(\.uuid)))
            }
            return result.sorted()
        }
    }

    @discardableResult
    static func create(kind: SpaceCompositionKind = .page, title: String, in spaceID: String,
                       parentUUID: String? = nil, body: String = "", groupUUID: String? = nil) async throws -> Atom {
        let title = try validTitle(title)
        let result = try await CosmoDatabase.shared.asyncWrite { db -> Mutation in
            try requireSpace(spaceID, db: db)
            var change = Mutation()
            if let parentUUID { try requireAuthoredParent(parentUUID, in: spaceID, db: db) }
            guard parentUUID == nil || kind.isAuthored else { throw SpaceCompositionError.invalidParent }
            let order = try nextOrder(parentUUID: parentUUID, in: spaceID, db: db)
            let value = SpaceCompositionMetadata(kind: kind, parentUUID: parentUUID, sortOrder: order)
            var atom = try Atom.new(type: .note, title: title, body: body).replacingSpaceComposition(value)
            try insert(&atom, in: spaceID, change: &change, db: db)
            if let groupUUID {
                try requireMember(groupUUID, in: spaceID, db: db)
                let group = try requireAtom(groupUUID, db: db)
                var metadata = try groupMetadata(group)
                metadata.memberUUIDs.append(atom.uuid)
                try save(group.replacingSpaceComposition(metadata), before: group, change: &change, db: db)
            }
            change.resultUUID = atom.uuid
            return change
        }
        await finish(result, title: "Create \(kind.title.lowercased())")
        return result.after.first { $0.uuid == result.resultUUID }!
    }

    /// Starters are ordinary editable pages. They impose no permanent Space type.
    @discardableResult
    static func createStarter(_ kind: SpaceCompositionKind, title: String? = nil, in spaceID: String,
                              groupUUID: String? = nil) async throws -> Atom {
        let name = try validTitle(title ?? "Untitled \(kind.title.lowercased())")
        let templates = starterPages(for: kind)
        let result = try await CosmoDatabase.shared.asyncWrite { db -> Mutation in
            try requireSpace(spaceID, db: db)
            var change = Mutation()
            let order = try nextOrder(parentUUID: nil, in: spaceID, db: db)
            var root = try Atom.new(type: .note, title: name, body: "")
                .replacingSpaceComposition(SpaceCompositionMetadata(kind: kind, sortOrder: order))
            try insert(&root, in: spaceID, change: &change, db: db)
            for (index, page) in templates.enumerated() {
                var child = try Atom.new(type: .note, title: page.title, body: page.body)
                    .replacingSpaceComposition(SpaceCompositionMetadata(parentUUID: root.uuid,
                        sortOrder: Double(index), includeInExport: page.included))
                try insert(&child, in: spaceID, change: &change, db: db)
                for (subindex, section) in page.children.enumerated() {
                    var nested = try Atom.new(type: .note, title: section.title, body: section.body)
                        .replacingSpaceComposition(SpaceCompositionMetadata(parentUUID: child.uuid,
                            sortOrder: Double(subindex), includeInExport: section.included))
                    try insert(&nested, in: spaceID, change: &change, db: db)
                }
            }
            if let groupUUID {
                try requireMember(groupUUID, in: spaceID, db: db)
                let group = try requireAtom(groupUUID, db: db)
                var metadata = try groupMetadata(group)
                metadata.memberUUIDs.append(root.uuid)
                try save(group.replacingSpaceComposition(metadata), before: group, change: &change, db: db)
            }
            change.resultUUID = root.uuid
            return change
        }
        await finish(result, title: "Create \(kind.title.lowercased())")
        return result.after.first { $0.uuid == result.resultUUID }!
    }

    static func rename(_ uuid: String, to title: String) async throws {
        let title = try validTitle(title)
        let result = try await CosmoDatabase.shared.asyncWrite { db -> Mutation in
            var atom = try requireAtom(uuid, db: db)
            var change = Mutation()
            let before = atom
            atom.title = title
            try save(atom, before: before, change: &change, db: db)
            return change
        }
        await finish(result, title: "Rename item")
    }

    static func move(_ uuid: String, to parentUUID: String?, in spaceID: String, at index: Int? = nil) async throws {
        let result = try await CosmoDatabase.shared.asyncWrite { db -> Mutation in
            try requireMember(uuid, in: spaceID, db: db)
            let atom = try requireAtom(uuid, db: db)
            var value = try authoredMetadata(atom)
            if let parentUUID {
                try requireAuthoredParent(parentUUID, in: spaceID, db: db)
                try validateParent(of: uuid, proposed: parentUUID, db: db)
            }
            var ordered = try siblings(parentUUID: parentUUID, in: spaceID, db: db).filter { $0.uuid != uuid }
            let insertion = min(max(0, index ?? ordered.count), ordered.count)
            value.parentUUID = parentUUID
            let moved = try atom.replacingSpaceComposition(value)
            ordered.insert(moved, at: insertion)
            var change = Mutation()
            for (offset, sibling) in ordered.enumerated() {
                var metadata = try metadataForContainer(sibling)
                metadata.sortOrder = Double(offset)
                let before = sibling.uuid == uuid ? atom : sibling
                try save(sibling.replacingSpaceComposition(metadata), before: before, change: &change, db: db)
            }
            return change
        }
        await finish(result, title: "Move page")
    }

    /// Rejects stale UI orders instead of silently dropping newly added sections.
    static func reorderChildren(of parentUUID: String?, in spaceID: String, orderedUUIDs: [String]) async throws {
        let result = try await CosmoDatabase.shared.asyncWrite { db -> Mutation in
            try requireSpace(spaceID, db: db)
            if let parentUUID { try requireAuthoredParent(parentUUID, in: spaceID, db: db) }
            let current = try siblings(parentUUID: parentUUID, in: spaceID, db: db)
            guard orderedUUIDs.count == Set(orderedUUIDs).count,
                  Set(orderedUUIDs) == Set(current.map(\.uuid)) else { throw SpaceCompositionError.invalidOrder }
            let byUUID = Dictionary(uniqueKeysWithValues: current.map { ($0.uuid, $0) })
            var change = Mutation()
            for (index, uuid) in orderedUUIDs.enumerated() {
                guard let atom = byUUID[uuid] else { throw SpaceCompositionError.invalidOrder }
                var metadata = try metadataForContainer(atom)
                metadata.sortOrder = Double(index)
                try save(atom.replacingSpaceComposition(metadata), before: atom, change: &change, db: db)
            }
            return change
        }
        await finish(result, title: "Reorder pages")
    }

    static func addMembers(_ uuids: [String], to groupUUID: String, in spaceID: String) async throws {
        let result = try await CosmoDatabase.shared.asyncWrite { db -> Mutation in
            try requireMember(groupUUID, in: spaceID, db: db)
            let group = try requireAtom(groupUUID, db: db)
            var value = try groupMetadata(group)
            var change = Mutation()
            for uuid in unique(uuids) {
                guard uuid != groupUUID else { throw SpaceCompositionError.cycle }
                let atom = try requireAtom(uuid, db: db)
                if try atom.decodedSpaceComposition()?.kind == .group {
                    try validateGroupEdge(parent: groupUUID, child: uuid, db: db)
                }
                if !value.memberUUIDs.contains(uuid) { value.memberUUIDs.append(uuid) }
                var visited = Set<String>()
                try addReachableMembership(atom, in: spaceID, visited: &visited, change: &change, db: db)
            }
            try save(group.replacingSpaceComposition(value), before: group, change: &change, db: db)
            return change
        }
        await finish(result, title: "Add to group")
    }

    /// Removes the reference only. Its original atom and other groups survive.
    static func removeMembers(_ uuids: [String], from groupUUID: String) async throws {
        let removed = Set(uuids)
        try await edit(groupUUID, title: "Remove from group") { value in
            guard value.kind == .group else { throw SpaceCompositionError.invalidKind }
            value.memberUUIDs.removeAll { removed.contains($0) }
            value.placements.removeAll { removed.contains($0.itemUUID) }
        }
    }

    static func setIncludedInExport(_ included: Bool, for uuid: String) async throws {
        try await edit(uuid, title: included ? "Include in export" : "Exclude from export") {
            guard $0.kind.isAuthored else { throw SpaceCompositionError.invalidKind }
            $0.includeInExport = included
        }
    }

    static func setPreferredView(_ view: SpaceCompositionView, for uuid: String) async throws {
        try await edit(uuid, title: "Change view", registerUndo: false) {
            let allowed: Set<SpaceCompositionView> = $0.kind == .group ? [.canvas, .grid, .list] : [.canvas, .outline, .write]
            guard allowed.contains(view) else { throw SpaceCompositionError.invalidKind }
            $0.preferredView = view
        }
    }

    static func setPlacement(_ placement: SpaceCompositionPlacement?, for itemUUID: String, in containerUUID: String) async throws {
        if let placement {
            guard placement.itemUUID == itemUUID else { throw SpaceCompositionError.invalidPlacement }
            try placement.validate()
        }
        let result = try await CosmoDatabase.shared.asyncWrite { db -> Mutation in
            let container = try requireAtom(containerUUID, db: db)
            var value = try metadataForContainer(container)
            if placement != nil {
                guard itemUUID != containerUUID else { throw SpaceCompositionError.cycle }
                _ = try requireAtom(itemUUID, db: db)
            }
            value.placements.removeAll { $0.itemUUID == itemUUID }
            if let placement { value.placements.append(placement) }
            var change = Mutation()
            try save(container.replacingSpaceComposition(value), before: container, change: &change, db: db)
            return change
        }
        await finish(result, title: placement == nil ? "Remove from canvas" : "Arrange canvas")
    }

    /// Upsert by stable reference ID supports multiple anchored excerpts from one source.
    static func attachReference(_ reference: SpaceCompositionReference, to uuid: String) async throws {
        try await attachReferences([reference], to: uuid)
    }

    /// A selected batch is one atomic edit and one undo operation.
    static func attachReferences(_ references: [SpaceCompositionReference], to uuid: String) async throws {
        guard !references.isEmpty else { return }
        guard Set(references.map(\.id)).count == references.count else { throw SpaceCompositionError.invalidMetadata }
        for reference in references { try reference.validate() }
        let result = try await CosmoDatabase.shared.asyncWrite { db -> Mutation in
            let target = try requireAtom(uuid, db: db)
            var metadata = try metadataForContainer(target)
            for incoming in references {
                guard incoming.sourceUUID != uuid else { throw SpaceCompositionError.invalidSource }
                let source = try requireAtom(incoming.sourceUUID, db: db)
                var reference = incoming
                if reference.sourceTitle == nil { reference.sourceTitle = source.title }
                if let index = metadata.references.firstIndex(where: { $0.id == reference.id }) {
                    metadata.references[index] = reference
                } else { metadata.references.append(reference) }
            }
            var change = Mutation()
            try save(target.replacingSpaceComposition(metadata), before: target, change: &change, db: db)
            return change
        }
        await finish(result, title: references.count == 1 ? "Attach source" : "Attach sources")
    }

    /// Saved source context can be edited even while its original is offline or gone.
    static func updateReference(_ reference: SpaceCompositionReference, in uuid: String) async throws {
        try reference.validate()
        try await edit(uuid, title: "Edit source note") { value in
            guard let index = value.references.firstIndex(where: { $0.id == reference.id }),
                  value.references[index].sourceUUID == reference.sourceUUID else { throw SpaceCompositionError.invalidSource }
            var updated = reference
            if updated.sourceTitle == nil { updated.sourceTitle = value.references[index].sourceTitle }
            value.references[index] = updated
        }
    }

    static func removeReference(_ referenceID: String, from uuid: String) async throws {
        try await edit(uuid, title: "Remove source reference") { $0.references.removeAll { $0.id == referenceID } }
    }

    /// Copies authored descendants, preserving rich documents byte-for-byte.
    /// Sources remain references; each copied page records its own origin.
    @discardableResult
    static func adapt(_ sourceUUID: String, title: String? = nil, kind: SpaceCompositionKind? = nil,
                      in spaceID: String, parentUUID: String? = nil) async throws -> Atom {
        let title = try title.map(validTitle)
        let result = try await CosmoDatabase.shared.asyncWrite { db -> Mutation in
            try requireSpace(spaceID, db: db)
            if let parentUUID { try requireAuthoredParent(parentUUID, in: spaceID, db: db) }
            let source = try requireAtom(sourceUUID, db: db)
            _ = try authoredMetadata(source)
            if kind == .group { throw SpaceCompositionError.invalidKind }
            var change = Mutation()
            var visited = Set<String>()
            let order = try nextOrder(parentUUID: parentUUID, in: spaceID, db: db)
            let root = try copyPage(source, parentUUID: parentUUID, order: order, title: title,
                                    kind: kind, spaceID: spaceID, visited: &visited, change: &change, db: db)
            change.resultUUID = root.uuid
            return change
        }
        await finish(result, title: "Adapt as new page")
        return result.after.first { $0.uuid == result.resultUUID }!
    }

    /// A Space removal is membership-only. Children become reachable roots if
    /// their parent is no longer present, and native items remain in the Library.
    static func remove(_ uuid: String, from spaceID: String) async throws {
        let result = try await CosmoDatabase.shared.asyncWrite { db -> Mutation in
            try requireSpace(spaceID, db: db)
            var change = Mutation()
            let rows = try CanvasBlockRecord.filter(Column("entity_uuid") == uuid)
                .filter(Column("thinkspace_id") == spaceID).filter(Column("document_type") == "home")
                .filter(Column("document_id") == 0).filter(Column("is_deleted") == false).fetchAll(db)
            for row in rows {
                change.membershipBefore.append(row)
                var updated = row
                updated.isDeleted = true
                updated.updatedAt = ISO8601.string(from: Date())
                updated.localVersion = (row.localVersion ?? 0) + 1
                updated.localPending = 1
                try updated.update(db)
                change.membershipAfter.append(updated)
            }
            return change
        }
        await finish(result, title: "Remove from Space")
    }

    /// Idempotent and transactional, including on two devices: group identities
    /// derive from the Space and legacy identity. Original group metadata, atoms and
    /// canvas geometry are retained. A failed migration never leaves half a map.
    @discardableResult
    static func migrateLegacyGroups(in spaceID: String) async throws -> [String: String] {
        let existing = try await CosmoDatabase.shared.asyncRead { db -> (Atom, [CompositionLegacyGroup], SpaceCompositionLegacyMigration) in
            try requireSpace(spaceID, db: db)
            let atom = try requireAtom(spaceID, db: db)
            return (atom, try legacyGroups(atom), try migration(atom))
        }
        guard existing.1.contains(where: { existing.2.groups[$0.identity] == nil }) else { return existing.2.groups }
        let result = try await CosmoDatabase.shared.asyncWrite { db -> (Mutation, [String: String]) in
            let space = try requireAtom(spaceID, db: db)
            let groups = try legacyGroups(space)
            var marker = try migration(space)
            var change = Mutation()
            var order = try nextOrder(parentUUID: nil, in: spaceID, db: db)
            for legacy in groups where marker.groups[legacy.identity] == nil {
                let uuid = migratedGroupUUID(spaceID: spaceID, legacyID: legacy.identity)
                var memberUUIDs: [String] = []
                for oldID in legacy.itemUUIDs {
                    let resolved = try String.fetchOne(db, sql: "SELECT uuid FROM atoms WHERE uuid = ?", arguments: [oldID])
                        ?? String.fetchOne(db, sql: "SELECT entity_uuid FROM canvas_blocks WHERE id = ? OR uuid = ? LIMIT 1", arguments: [oldID, oldID])
                        ?? oldID
                    memberUUIDs.append(resolved)
                    if let member = try Atom.filter(Column("uuid") == resolved).filter(Column("is_deleted") == false).fetchOne(db) {
                        try addMembership(member, in: spaceID, change: &change, db: db)
                    }
                }
                if let existing = try Atom.filter(Column("uuid") == uuid).fetchOne(db) {
                    guard try existing.decodedSpaceComposition()?.kind == .group else { throw SpaceCompositionError.conflict }
                    // A deletion on another device must not be resurrected by migration.
                    if !existing.isDeleted { try addMembership(existing, in: spaceID, change: &change, db: db) }
                } else {
                    var metadata = SpaceCompositionMetadata(kind: .group, sortOrder: order)
                    metadata.memberUUIDs = unique(memberUUIDs)
                    metadata.preferredView = legacy.viewMode.flatMap(SpaceCompositionView.init(rawValue:))
                    if metadata.preferredView == .outline || metadata.preferredView == .write { metadata.preferredView = .grid }
                    var group = try Atom.new(type: .note, title: legacy.name, body: "").replacingSpaceComposition(metadata)
                    group.uuid = uuid
                    try insert(&group, in: spaceID, change: &change, db: db)
                    order += 1
                }
                marker.groups[legacy.identity] = uuid
            }
            let updated = try replacingMigration(marker, on: space)
            try save(updated, before: space, change: &change, db: db)
            return (change, marker.groups)
        }
        await finish(result.0, title: "Update Space groups", registerUndo: false)
        return result.1
    }

    // MARK: - Transaction helpers

    private struct Mutation: Sendable {
        var before: [Atom] = []
        var after: [Atom] = []
        var insertedUUIDs: Set<String> = []
        var membershipBefore: [CanvasBlockRecord] = []
        var membershipAfter: [CanvasBlockRecord] = []
        var resultUUID: String?
    }

    private static func edit(_ uuid: String, title: String, registerUndo: Bool = true,
                             change: @escaping @Sendable (inout SpaceCompositionMetadata) throws -> Void) async throws {
        let result = try await CosmoDatabase.shared.asyncWrite { db -> Mutation in
            let atom = try requireAtom(uuid, db: db)
            var value = try metadataForContainer(atom)
            try change(&value)
            var result = Mutation()
            try save(atom.replacingSpaceComposition(value), before: atom, change: &result, db: db)
            return result
        }
        await finish(result, title: title, registerUndo: registerUndo)
    }

    nonisolated private static func validTitle(_ value: String) throws -> String {
        let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw SpaceCompositionError.emptyTitle }
        return title
    }

    nonisolated private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    nonisolated private static func requireAtom(_ uuid: String, db: Database) throws -> Atom {
        guard let atom = try Atom.filter(Column("uuid") == uuid).filter(Column("is_deleted") == false).fetchOne(db) else {
            throw SpaceCompositionError.notFound
        }
        return atom
    }

    nonisolated private static func requireSpace(_ uuid: String, db: Database) throws {
        guard try requireAtom(uuid, db: db).type == .thinkspace else { throw SpaceCompositionError.notFound }
    }

    nonisolated private static func requireMember(_ uuid: String, in spaceID: String, db: Database) throws {
        try requireSpace(spaceID, db: db)
        let directCount = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM canvas_blocks WHERE entity_uuid = ? AND thinkspace_id = ?
            AND document_type = 'home' AND document_id = 0 AND is_deleted = 0
            """, arguments: [uuid, spaceID]) ?? 0
        if directCount > 0 { return }
        // Removing an item's root placement must not make a retained group or
        // authored-child reference read-only. This is the same reachability
        // used by loading; it never recreates the removed membership row.
        guard try members(in: spaceID, db: db).contains(where: { $0.uuid == uuid }) else {
            throw SpaceCompositionError.notFound
        }
    }

    nonisolated private static func metadataForContainer(_ atom: Atom) throws -> SpaceCompositionMetadata {
        if let value = try atom.decodedSpaceComposition() { return value }
        guard atom.type == .note else { throw SpaceCompositionError.invalidKind }
        return SpaceCompositionMetadata()
    }

    nonisolated private static func authoredMetadata(_ atom: Atom) throws -> SpaceCompositionMetadata {
        let value = try metadataForContainer(atom)
        guard value.kind.isAuthored else { throw SpaceCompositionError.invalidKind }
        return value
    }

    nonisolated private static func groupMetadata(_ atom: Atom) throws -> SpaceCompositionMetadata {
        let value = try metadataForContainer(atom)
        guard value.kind == .group else { throw SpaceCompositionError.invalidKind }
        return value
    }

    nonisolated private static func requireAuthoredParent(_ uuid: String, in spaceID: String, db: Database) throws {
        try requireMember(uuid, in: spaceID, db: db)
        do { _ = try authoredMetadata(requireAtom(uuid, db: db)) }
        catch SpaceCompositionError.invalidKind { throw SpaceCompositionError.invalidParent }
    }

    nonisolated private static func members(in spaceID: String, db: Database) throws -> [Atom] {
        let direct = try Atom.fetchAll(db, sql: """
            SELECT a.* FROM atoms a WHERE a.is_deleted = 0 AND a.uuid IN (
                SELECT entity_uuid FROM canvas_blocks WHERE thinkspace_id = ? AND document_type = 'home'
                AND document_id = 0 AND is_deleted = 0)
            """, arguments: [spaceID])
        var byUUID = Dictionary(uniqueKeysWithValues: direct.map { ($0.uuid, $0) })
        var frontier = direct
        while !frontier.isEmpty {
            var groupIDs = Set<String>(), parentIDs: [String] = []
            for container in frontier {
                let metadata = try container.decodedSpaceComposition()
                if metadata?.kind == .group { groupIDs.formUnion(metadata?.memberUUIDs ?? []) }
                else if metadata?.kind.isAuthored == true || container.type == .note { parentIDs.append(container.uuid) }
            }
            var related: [Atom] = []
            let missing = Array(groupIDs.subtracting(byUUID.keys))
            // Bounded batches avoid both one-query-per-page loading and SQLite's
            // bind limit when a Space contains a large image collection.
            for start in stride(from: 0, to: missing.count, by: 400) {
                let ids = Array(missing[start..<min(start + 400, missing.count)])
                related += try Atom.filter(ids.contains(Column("uuid"))).filter(Column("is_deleted") == false).fetchAll(db)
            }
            for start in stride(from: 0, to: parentIDs.count, by: 400) {
                let ids = Array(parentIDs[start..<min(start + 400, parentIDs.count)])
                let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
                related += try Atom.fetchAll(db, sql: """
                    SELECT * FROM atoms WHERE is_deleted = 0
                    AND CASE WHEN json_valid(metadata) THEN json_extract(metadata, '$.spaceComposition.parentUUID') END IN (\(placeholders))
                    """, arguments: StatementArguments(ids))
            }
            frontier = []
            for atom in related where byUUID[atom.uuid] == nil {
                byUUID[atom.uuid] = atom
                frontier.append(atom)
            }
        }
        return Array(byUUID.values)
    }

    nonisolated private static func siblings(parentUUID: String?, in spaceID: String, db: Database) throws -> [Atom] {
        let snapshot = try SpaceCompositionSnapshot(spaceID: spaceID, atoms: members(in: spaceID, db: db))
        if let parentUUID { return snapshot.children(of: parentUUID) }
        return snapshot.roots
    }

    nonisolated private static func nextOrder(parentUUID: String?, in spaceID: String, db: Database) throws -> Double {
        let ordered = try siblings(parentUUID: parentUUID, in: spaceID, db: db)
        return (ordered.compactMap { $0.spaceComposition?.sortOrder }.max() ?? -1) + 1
    }

    nonisolated private static func legacyGroups(_ atom: Atom) throws -> [CompositionLegacyGroup] {
        if let metadata = atom.metadata, !metadata.isEmpty, atom.metadataDict == nil { throw SpaceCompositionError.invalidMetadata }
        if let raw = atom.metadataDict?["materialGroups"] {
            return try JSONDecoder().decode([CompositionLegacyGroup].self, from: JSONSerialization.data(withJSONObject: raw))
        }
        guard let raw = atom.metadataDict?["clusters"] else { return [] }
        struct Legacy: Decodable { let id: String; let name: String; let blockUUIDs: [String]; let viewMode: String? }
        return try JSONDecoder().decode([Legacy].self, from: JSONSerialization.data(withJSONObject: raw)).map {
            CompositionLegacyGroup(id: $0.id, name: $0.name, itemUUIDs: $0.blockUUIDs, viewMode: $0.viewMode)
        }
    }

    nonisolated private static func migration(_ atom: Atom) throws -> SpaceCompositionLegacyMigration {
        guard let raw = atom.metadataDict?[SpaceCompositionLegacyMigration.metadataKey] else { return .init() }
        do {
            let marker = try JSONDecoder().decode(SpaceCompositionLegacyMigration.self, from: JSONSerialization.data(withJSONObject: raw))
            guard marker.schemaVersion == 1 else { throw SpaceCompositionError.unsupportedVersion(marker.schemaVersion) }
            return marker
        } catch let error as SpaceCompositionError { throw error }
        catch { throw SpaceCompositionError.invalidMetadata }
    }

    nonisolated private static func replacingMigration(_ value: SpaceCompositionLegacyMigration, on atom: Atom) throws -> Atom {
        var object = atom.metadataDict ?? [:]
        var namespace = object[SpaceCompositionLegacyMigration.metadataKey] as? [String: Any] ?? [:]
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any] ?? [:]
        for (key, value) in encoded { namespace[key] = value }
        object[SpaceCompositionLegacyMigration.metadataKey] = namespace
        var updated = atom
        updated.metadata = String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
        return updated
    }

    nonisolated private static func migratedGroupUUID(spaceID: String, legacyID: String) -> String {
        var bytes = Array(SHA256.hash(data: Data("cosmo.space.group.v1:\(spaceID):\(legacyID)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let hex = bytes.map { String(format: "%02X", $0) }.joined()
        return "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20))"
    }

    nonisolated private static func validateParent(of uuid: String, proposed: String, db: Database) throws {
        var seen = Set<String>(), cursor: String? = proposed
        while let id = cursor {
            guard id != uuid, seen.insert(id).inserted else { throw SpaceCompositionError.cycle }
            // The proposed parent is already validated as live. Keep following
            // tombstoned ancestors to catch cycles on a later restore, while a
            // missing older ancestor simply ends this otherwise usable branch.
            guard let ancestor = try Atom.filter(Column("uuid") == id).fetchOne(db) else { break }
            cursor = try ancestor.decodedSpaceComposition()?.parentUUID
        }
    }

    nonisolated private static func validateGroupEdge(parent: String, child: String, db: Database) throws {
        var visited = Set<String>(), pending = [child]
        while let uuid = pending.popLast() {
            guard uuid != parent else { throw SpaceCompositionError.cycle }
            guard visited.insert(uuid).inserted else { continue }
            guard let atom = try Atom.filter(Column("uuid") == uuid).filter(Column("is_deleted") == false).fetchOne(db),
                  let value = try atom.decodedSpaceComposition(), value.kind == .group else { continue }
            pending.append(contentsOf: value.memberUUIDs)
        }
    }

    nonisolated private static func save(_ incoming: Atom, before: Atom, change: inout Mutation, db: Database) throws {
        guard incoming != before else { return }
        var atom = incoming
        atom.updatedAt = ISO8601.string(from: Date())
        atom.localVersion = before.localVersion + 1
        AtomRevisionWriter.snapshotIfNeeded(db, previous: before, incoming: atom, source: .userEdit)
        try atom.update(db)
        try db.execute(sql: "UPDATE atoms SET _local_pending = 1 WHERE uuid = ?", arguments: [atom.uuid])
        change.before.append(before)
        change.after.append(atom)
    }

    nonisolated private static func insert(_ atom: inout Atom, in spaceID: String, change: inout Mutation, db: Database) throws {
        try atom.insert(db)
        atom.id = db.lastInsertedRowID
        try db.execute(sql: "UPDATE atoms SET _local_pending = 1 WHERE uuid = ?", arguments: [atom.uuid])
        change.after.append(atom)
        change.insertedUUIDs.insert(atom.uuid)
        try addMembership(atom, in: spaceID, change: &change, db: db)
    }

    nonisolated private static func addMembership(_ atom: Atom, in spaceID: String, change: inout Mutation, db: Database) throws {
        let rows = try CanvasBlockRecord.filter(Column("entity_uuid") == atom.uuid)
            .filter(Column("thinkspace_id") == spaceID).filter(Column("document_type") == "home")
            .filter(Column("document_id") == 0).order(Column("id")).fetchAll(db)
        if rows.contains(where: { !$0.isDeleted }) { return }
        if let old = rows.first {
            var restored = old
            restored.isDeleted = false
            restored.isPlaced = false
            restored.localVersion = (old.localVersion ?? 0) + 1
            restored.updatedAt = ISO8601.string(from: Date())
            restored.localPending = 1
            try restored.update(db)
            change.membershipBefore.append(old)
            change.membershipAfter.append(restored)
        } else {
            let now = ISO8601.string(from: Date())
            let size: (Int, Int)
            if atom.type == .image, let image = atom.imageMetadata, let width = image.width, let height = image.height,
               width > 0, height > 0 {
                let scale = min(400 / width, 1)
                size = (max(1, Int(width * scale)), max(1, Int(height * scale)))
            } else { size = (320, atom.type == .note ? 360 : 240) }
            let row = CanvasBlockRecord(id: UUID().uuidString, uuid: atom.uuid, userId: nil,
                documentType: "home", documentId: 0, documentUuid: nil,
                entityId: Int(atom.id ?? 0), entityUuid: atom.uuid, entityType: atom.type.rawValue,
                entityTitle: atom.title, positionX: 0, positionY: 0, width: size.0, height: size.1,
                isCollapsed: false, zone: nil, noteContent: nil, zIndex: 0, isPinned: false,
                thinkspaceId: spaceID, isPlaced: false, createdAt: now, updatedAt: now, syncedAt: nil,
                isDeleted: false, atomUuid: atom.uuid, localVersion: 1, serverVersion: 0, syncVersion: 0, localPending: 1)
            try row.insert(db)
            change.membershipAfter.append(row)
        }
    }

    nonisolated private static func addReachableMembership(_ atom: Atom, in spaceID: String, visited: inout Set<String>,
                                                         change: inout Mutation, db: Database) throws {
        guard visited.insert(atom.uuid).inserted else { return }
        try addMembership(atom, in: spaceID, change: &change, db: db)
        if let value = try atom.decodedSpaceComposition(), value.kind == .group {
            for uuid in unique(value.memberUUIDs) {
                if let member = try Atom.filter(Column("uuid") == uuid).filter(Column("is_deleted") == false).fetchOne(db) {
                    try addReachableMembership(member, in: spaceID, visited: &visited, change: &change, db: db)
                }
            }
        } else if atom.spaceCompositionKind?.isAuthored == true {
            let children = try Atom.fetchAll(db, sql: """
                SELECT * FROM atoms WHERE is_deleted = 0
                AND CASE WHEN json_valid(metadata) THEN json_extract(metadata, '$.spaceComposition.parentUUID') END = ?
                """, arguments: [atom.uuid])
            for child in children {
                try addReachableMembership(child, in: spaceID, visited: &visited, change: &change, db: db)
            }
        }
    }

    nonisolated private static func copyPage(_ source: Atom, parentUUID: String?, order: Double,
        title: String?, kind: SpaceCompositionKind?, spaceID: String, visited: inout Set<String>,
        change: inout Mutation, db: Database) throws -> Atom {
        guard visited.insert(source.uuid).inserted else { throw SpaceCompositionError.cycle }
        var metadata = try authoredMetadata(source)
        metadata.parentUUID = parentUUID
        metadata.sortOrder = order
        if let kind { metadata.kind = kind }
        metadata.origin = SpaceCompositionOrigin(sourceUUID: source.uuid, sourceTitle: source.title,
            sourceVersion: source.localVersion, adaptedAt: ISO8601.string(from: Date()))
        // Canvas references to copied sections must never accidentally point at
        // the originals. The independent adaptation starts with an unplaced layout.
        metadata.placements = []
        var copy = Atom.new(type: .note, title: title ?? source.title, body: source.body,
            structured: source.structured, metadata: source.metadata)
        copy = try copy.replacingSpaceComposition(metadata)
        try insert(&copy, in: spaceID, change: &change, db: db)
        let children = try Atom.fetchAll(db, sql: """
            SELECT * FROM atoms WHERE is_deleted = 0
            AND CASE WHEN json_valid(metadata) THEN json_extract(metadata, '$.spaceComposition.parentUUID') END = ?
            ORDER BY COALESCE(CASE WHEN json_valid(metadata) THEN json_extract(metadata, '$.spaceComposition.sortOrder') END, 0), uuid
            """, arguments: [source.uuid])
        for (index, child) in children.enumerated() {
            _ = try copyPage(child, parentUUID: copy.uuid, order: Double(index), title: nil,
                kind: nil, spaceID: spaceID, visited: &visited, change: &change, db: db)
        }
        return copy
    }

    private static func finish(_ change: Mutation, title: String, registerUndo: Bool = true) async {
        guard !change.after.isEmpty || !change.membershipAfter.isEmpty else { return }
        for atom in change.after {
            if change.insertedUUIDs.contains(atom.uuid) {
                await ChangeTracker.shared.trackInsert(table: "atoms", entity: atom)
                try? await NodeGraphEngine.shared.handleAtomCreated(atom)
            } else {
                await ChangeTracker.shared.trackUpdate(table: "atoms", entity: atom, skipVersionIncrement: true)
            }
            Task.detached(priority: .utility) { await RecallIndexer.shared.noteAtomChanged(atom) }
        }
        if registerUndo {
            CosmoUndoManager.shared.register(InlineUndoAction(actionDescription: title,
                undo: { await restore(change, undo: true) }, redo: { await restore(change, undo: false) }))
        }
        NotificationCenter.default.post(name: didChange, object: nil)
        SpaceMembershipService.notifyMembersChanged()
    }

    /// Undo restores only composition/title/membership, never stale body text.
    /// A changed structure is rejected rather than clobbering another device.
    private static func restore(_ original: Mutation, undo: Bool) async {
        do {
            let result = try await CosmoDatabase.shared.asyncWrite { db -> Mutation in
                var result = Mutation()
                let beforeByID = Dictionary(uniqueKeysWithValues: original.before.map { ($0.uuid, $0) })
                for after in original.after where !original.insertedUUIDs.contains(after.uuid) {
                    guard let before = beforeByID[after.uuid] else { continue }
                    let expected = undo ? after : before, target = undo ? before : after
                    let fresh = try requireAtom(after.uuid, db: db)
                    guard try fresh.decodedSpaceComposition() == expected.decodedSpaceComposition() else {
                        throw SpaceCompositionError.conflict
                    }
                    var restored = try fresh.replacingSpaceComposition(target.decodedSpaceComposition())
                    if before.title != after.title {
                        guard fresh.title == expected.title else { throw SpaceCompositionError.conflict }
                        restored.title = target.title
                    }
                    try save(restored, before: fresh, change: &result, db: db)
                }
                let beforeRows = Dictionary(uniqueKeysWithValues: original.membershipBefore.map { ($0.id, $0) })
                for after in original.membershipAfter {
                    guard var fresh = try CanvasBlockRecord.filter(Column("id") == after.id).fetchOne(db) else {
                        throw SpaceCompositionError.conflict
                    }
                    let before = beforeRows[after.id]
                    let expectedDeleted = undo ? after.isDeleted : (before?.isDeleted ?? true)
                    guard fresh.isDeleted == expectedDeleted else { throw SpaceCompositionError.conflict }
                    result.membershipBefore.append(fresh)
                    fresh.isDeleted = undo ? (before?.isDeleted ?? true) : after.isDeleted
                    fresh.localPending = 1
                    fresh.localVersion = (fresh.localVersion ?? 0) + 1
                    fresh.updatedAt = ISO8601.string(from: Date())
                    try fresh.update(db)
                    result.membershipAfter.append(fresh)
                }
                return result
            }
            await finish(result, title: "Restore organization", registerUndo: false)
        } catch {
            NotificationCenter.default.post(name: didFailUndo, object: nil,
                userInfo: ["message": error.localizedDescription])
        }
    }

    private struct StarterPage: Sendable {
        var title: String
        var body: String = ""
        var included: Bool = true
        var children: [StarterPage] = []
    }

    nonisolated private static func starterPages(for kind: SpaceCompositionKind) -> [StarterPage] {
        switch kind {
        case .book:
            return [StarterPage(title: "Premise & audience", body: "What is this book about? Who is it for? What should stay with the reader?", included: false),
                    StarterPage(title: "Introduction"), StarterPage(title: "Chapter 1"), StarterPage(title: "Chapter 2")]
        case .course:
            return [StarterPage(title: "Course promise", body: "Who is this for? What will they be able to do by the end?", included: false),
                    StarterPage(title: "Module 1", children: [
                        StarterPage(title: "Lesson 1", body: "Learning outcome\n\nExplanation\n\nExample\n\nPractice\n\nCheck your understanding"),
                        StarterPage(title: "Exercise", body: "Task\n\nSteps\n\nReflection")]),
                    StarterPage(title: "Recording notes", included: false)]
        case .guide:
            return [StarterPage(title: "Reader & promise", body: "Who needs this? What one useful result does it help them achieve?", included: false),
                    StarterPage(title: "Start here"), StarterPage(title: "The practical steps"),
                    StarterPage(title: "Your checklist", body: "A short set of actions the reader can use immediately.")]
        case .page, .group: return []
        }
    }
}

/// Legacy iOS groups used opaque string IDs; valid UUIDs keep the canonical
/// spelling used by earlier Mac migrations so both devices converge.
private struct CompositionLegacyGroup: Decodable, Sendable {
    var id: String
    var name: String
    var itemUUIDs: [String]
    var viewMode: String?
    var identity: String { UUID(uuidString: id)?.uuidString ?? id }
}
