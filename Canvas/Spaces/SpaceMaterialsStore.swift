import Foundation
import SwiftUI
import GRDB

struct SpaceMaterialGroup: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var colorIndex: Int
    var itemUUIDs: [String]
    var viewMode: String? = nil
    var sortOrder: String? = nil
    var boardGrouping: String? = nil
}

@MainActor
@Observable
final class SpaceMaterialsStore {
    private(set) var groups: [SpaceMaterialGroup] = []
    private(set) var spaceID: String?
    var errorMessage: String?
    @ObservationIgnored private var observation: AnyDatabaseCancellable?

    /// Detach the old folder membership exactly once. Coordinates and visual
    /// clusters remain untouched; future changes in either system are independent.
    func load(spaceID: String) async {
        if self.spaceID != spaceID {
            observation?.cancel()
            self.spaceID = spaceID
            groups = []
            if let db = CosmoDatabase.shared.dbPool {
                var isInitialValue = true
                observation = ValueObservation.tracking { db in
                    try String.fetchOne(db, sql: "SELECT metadata FROM atoms WHERE uuid = ?", arguments: [spaceID])
                }.removeDuplicates().start(in: db, onError: { _ in }) { [weak self] _ in
                    // The explicit load below owns the initial read/migration.
                    if isInitialValue { isInitialValue = false; return }
                    Task { @MainActor in
                        guard let self, self.spaceID == spaceID else { return }
                        await self.load(spaceID: spaceID)
                    }
                }
            }
        }
        do {
            guard let atom = try await AtomRepository.shared.fetch(uuid: spaceID) else { return }
            // The composition navigator owns migrated groups. Keep their original
            // cross-platform metadata intact; the retired UUID-only reader must
            // neither rewrite it nor report an error for valid older iOS IDs.
            if let raw = atom.metadataDict?[SpaceCompositionLegacyMigration.metadataKey] {
                let marker = try JSONDecoder().decode(SpaceCompositionLegacyMigration.self,
                    from: JSONSerialization.data(withJSONObject: raw))
                guard marker.schemaVersion == 1 else { throw SpaceCompositionError.unsupportedVersion(marker.schemaVersion) }
                let original = atom.metadataDict?["materialGroups"] ?? atom.metadataDict?["clusters"]
                if let legacy = original as? [[String: Any]], legacy.allSatisfy({ group in
                    guard let id = group["id"] as? String else { return false }
                    return marker.groups[UUID(uuidString: id)?.uuidString ?? id] != nil
                }) {
                    guard self.spaceID == spaceID else { return }
                    groups = []; errorMessage = nil
                    return
                }
            }
            if let stored = try Self.decodeGroups(atom) {
                guard self.spaceID == spaceID else { return }
                groups = stored
            } else {
                let updated = try await Self.update(spaceID: spaceID) { _ in }
                guard self.spaceID == spaceID else { return }
                groups = updated.groups
            }
            errorMessage = nil
        } catch {
            guard self.spaceID == spaceID else { return }
            errorMessage = "Couldn't load material groups. Your canvas is unchanged."
        }
    }

    func edit(_ change: @escaping @Sendable (inout [SpaceMaterialGroup]) -> Void) {
        guard let spaceID else { return }
        Task {
            do {
                let result = try await Self.update(spaceID: spaceID, change: change)
                if self.spaceID == spaceID { groups = result.groups; errorMessage = nil }
                let undo = ContentMetadataSnapshot(atom: result.before, keys: ["materialGroups"])
                let redo = ContentMetadataSnapshot(atom: result.after, keys: ["materialGroups"])
                CosmoUndoManager.shared.register(InlineUndoAction(
                    actionDescription: "Organize materials",
                    undo: { [weak self] in _ = await undo.restore(); await self?.load(spaceID: spaceID) },
                    redo: { [weak self] in _ = await redo.restore(); await self?.load(spaceID: spaceID) }
                ))
            } catch { errorMessage = "Couldn't save the group. Try again." }
        }
    }

    func file(_ uuid: String, in groupID: UUID) {
        edit { groups in
            guard let target = groups.firstIndex(where: { $0.id == groupID }) else { return }
            for index in groups.indices { groups[index].itemUUIDs.removeAll { $0 == uuid } }
            groups[target].itemUUIDs.append(uuid)
        }
    }

    func remove(_ uuid: String, from groupID: UUID) {
        edit { groups in
            if let index = groups.firstIndex(where: { $0.id == groupID }) { groups[index].itemUUIDs.removeAll { $0 == uuid } }
        }
    }

    func rename(_ id: UUID, to name: String) {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        edit { groups in if let i = groups.firstIndex(where: { $0.id == id }) { groups[i].name = title } }
    }

    func recolor(_ id: UUID, to index: Int) {
        edit { groups in if let i = groups.firstIndex(where: { $0.id == id }) { groups[i].colorIndex = index } }
    }

    func delete(_ id: UUID) { edit { $0.removeAll { $0.id == id } } }

    func create(name: String = "New group") {
        edit { $0.append(SpaceMaterialGroup(id: UUID(), name: name, colorIndex: 0, itemUUIDs: [])) }
    }

    nonisolated static func decodeGroups(_ atom: Atom) throws -> [SpaceMaterialGroup]? {
        guard let raw = atom.metadataDict?["materialGroups"] else { return nil }
        return try JSONDecoder().decode([SpaceMaterialGroup].self, from: JSONSerialization.data(withJSONObject: raw))
    }

    nonisolated static func seedGroups(from atom: Atom) throws -> [SpaceMaterialGroup] {
        // Decode only the fields being migrated. A newer camera setting or a
        // missing legacy default must never silently erase a material group.
        guard let raw = atom.metadataDict?["clusters"] else { return [] }
        struct Membership: Decodable {
            let id: UUID
            let name: String
            let colorIndex: Int?
            let blockUUIDs: [String]
        }
        return try JSONDecoder().decode([Membership].self, from: JSONSerialization.data(withJSONObject: raw)).map {
            SpaceMaterialGroup(id: $0.id, name: $0.name, colorIndex: $0.colorIndex ?? 0, itemUUIDs: $0.blockUUIDs)
        }
    }

    struct Mutation: Sendable { let before: Atom; let after: Atom; let groups: [SpaceMaterialGroup] }

    static func update(spaceID: String, change: @escaping @Sendable (inout [SpaceMaterialGroup]) -> Void) async throws -> Mutation {
        let result = try await CosmoDatabase.shared.asyncWrite { db -> Mutation in
            guard var atom = try Atom.filter(Column("uuid") == spaceID).fetchOne(db), !atom.isDeleted,
                  atom.metadata == nil || atom.metadataDict != nil else { throw ContentPipelineError.invalidMetadata }
            let before = atom
            var groups = try decodeGroups(atom) ?? seedGroups(from: atom)
            change(&groups)
            struct Patch: Encodable { var materialGroups: [SpaceMaterialGroup] }
            atom = atom.mergingMetadataKeys(Patch(materialGroups: groups))
            atom.updatedAt = ISO8601.string(from: Date())
            atom.localVersion += 1
            try atom.update(db)
            try db.execute(sql: "UPDATE atoms SET _local_pending = 1 WHERE uuid = ?", arguments: [spaceID])
            return Mutation(before: before, after: atom, groups: groups)
        }
        await ChangeTracker.shared.trackUpdate(table: "atoms", entity: result.after, skipVersionIncrement: true)
        return result
    }
}

extension ThinkspaceMetadata {
    /// Preserve unknown metadata (home document, detached material groups and
    /// newer-device fields) while retaining intentional removal of known keys.
    func mergedJSON(into existing: String?) -> String? {
        guard let encoded = try? JSONEncoder().encode(self),
              let owned = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any] else { return existing }
        var dict: [String: Any] = [:]
        if let existing {
            guard let data = existing.data(using: .utf8),
                  let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return existing }
            dict = decoded
        }
        for key in CodingKeys.allCases { dict[key.rawValue] = owned[key.rawValue] }
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return existing }
        return String(decoding: data, as: UTF8.self)
    }
}
