import SwiftUI
import GRDB

/// One immutable persistence scope, shared by the mature canvas and its undo
/// actions. Navigation can unmount the view without redirecting a queued write.
@MainActor @Observable
final class SpaceCompositionCanvasSession {
    let spaceID: String
    let containerUUID: String
    let database: CosmoDatabase
    private(set) var container: Atom?
    private(set) var items: [Atom] = []
    private(set) var revision = 0
    var error: String?
    var onOpen: ((Atom) -> Void)?
    var selectedUUID: String?
    var hasPendingEdits: Bool { !pending.isEmpty }
    var scopeID: String { "composition:\(spaceID):\(containerUUID)" }
    var cameraKey: String { "cosmo.space.collection.camera.mac.\(containerUUID).native" }
    private var initialPositions: [String: CGPoint] = [:]
    private var pending: [Pending] = []
    private struct Pending: Codable {
        var patch: SpaceCanvasPatch
        var title: String
        var registerUndo: Bool
    }
    private var recoveryKey: String { "cosmo.space.canvas.pending.\(containerUUID)" }

    init(spaceID: String, containerUUID: String, database: CosmoDatabase = .shared) {
        self.spaceID = spaceID; self.containerUUID = containerUUID; self.database = database
        if let data = UserDefaults.standard.data(forKey: "cosmo.space.canvas.pending.\(containerUUID)"),
           let recovered = try? JSONDecoder().decode([Pending].self, from: data) { pending = recovered }
        if let data = UserDefaults.standard.data(forKey: "cosmo.space.collection.positions.mac.\(containerUUID)"),
           let points = try? JSONDecoder().decode([String: SpaceCanvasPoint].self, from: data) {
            initialPositions = points.mapValues { CGPoint(x: $0.x, y: $0.y) }
        }
        DirtyEditorRegistry.shared.register(id: "scoped-canvas-\(scopeID)") { [weak self] in self?.retry() }
    }

    deinit {
        let id = "scoped-canvas-composition:\(spaceID):\(containerUUID)"
        Task { @MainActor in DirtyEditorRegistry.shared.unregister(id: id) }
    }

    func receive(container: Atom, items: [Atom]) {
        guard container.uuid == containerUUID else { return }
        if !hasPendingEdits { self.container = container }
        self.items = items
        reload()
    }

    func reload() {
        do {
            let loaded = try database.read { db in
                let atom = try SpaceCanvasPersistence.container(containerUUID, db: db)
                return (atom, try SpaceCanvasPersistence.items(in: atom, db: db))
            }
            container = loaded.0
            items = loaded.1
            for entry in pending { preview(entry.patch) }
            if let previewContainer = container {
                items = try database.read { try SpaceCanvasPersistence.items(in: previewContainer, db: $0) }
            }
            ensurePositions()
            revision &+= 1
            if !hasPendingEdits { error = nil }
            CanvasAtomObservationHub.shared.absorb(items + [loaded.0])
        } catch { report(error) }
    }

    func projectedBlocks() -> [CanvasBlock] {
        guard let container else { return [] }
        let hidden = Set((try? container.decodedSpaceCanvas().hiddenItemUUIDs) ?? [])
        return items.enumerated().compactMap { index, atom in
            guard !hidden.contains(atom.uuid) else { return nil }
            return project(atom, index: index)
        }
    }

    func project(_ atom: Atom, index: Int = 0) -> CanvasBlock {
        let native = CanvasBlock.fromAtom(atom, position: .zero)
        let geometry = placement(atom.uuid, fallbackSize: native.size)
        var block = CanvasBlock(id: Self.blockID(containerUUID: containerUUID, itemUUID: atom.uuid),
            position: CGPoint(x: geometry.x + (geometry.width ?? native.size.width) / 2,
                              y: geometry.y + (geometry.height ?? native.size.height) / 2),
            size: CGSize(width: geometry.width ?? native.size.width, height: geometry.height ?? native.size.height),
            zIndex: index, entityType: native.entityType, entityId: native.entityId, entityUuid: atom.uuid,
            title: native.title, subtitle: native.subtitle, metadata: native.metadata)
        block.metadata["spaceCanvasContainerUUID"] = containerUUID
        block.metadata["spaceCanvasSpaceID"] = spaceID
        block.metadata["spaceCanvasKind"] = container?.spaceCompositionKind?.rawValue ?? "page"
        if let color = atom.metadataDict?["stickyColor"] as? String { block.metadata["stickyColor"] = color }
        if atom.type == .stickyNote { block.metadata["content"] = atom.body ?? "" }
        block.isSelected = selectedUUID == atom.uuid
        return block
    }

    static func blockID(containerUUID: String, itemUUID: String) -> String { "composition:\(containerUUID):\(itemUUID)" }
    static func isProjectedID(_ id: String) -> Bool { id.hasPrefix("composition:") }
    func atom(forBlockID id: String) -> Atom? { items.first { Self.blockID(containerUUID: containerUUID, itemUUID: $0.uuid) == id } }
    func placement(_ id: String, fallbackSize: CGSize) -> SpaceCompositionPlacement {
        let saved = container?.spaceComposition?.placements.first { $0.itemUUID == id }
        let point = initialPositions[id] ?? .zero
        return Self.bounded(saved ?? .init(itemUUID: id, x: point.x, y: point.y,
                                          width: fallbackSize.width, height: fallbackSize.height), fallback: fallbackSize)
    }
    static func bounded(_ source: SpaceCompositionPlacement, fallback: CGSize) -> SpaceCompositionPlacement {
        func coordinate(_ v: Double) -> Double { v.isFinite ? min(1_000_000_000, max(-1_000_000_000, v)) : 0 }
        func dimension(_ v: Double?, _ base: CGFloat) -> Double {
            guard let v, v.isFinite, v > 0 else { return base }
            return min(16_384, max(1, v))
        }
        return .init(itemUUID: source.itemUUID, x: coordinate(source.x), y: coordinate(source.y),
                     width: dimension(source.width, fallback.width), height: dimension(source.height, fallback.height))
    }

    @discardableResult
    func saveGeometry(_ block: CanvasBlock, title: String = "Arrange canvas") -> Bool {
        guard let container, items.contains(where: { $0.uuid == block.entityUuid }) else { return false }
        let before = container.spaceComposition?.placements.first { $0.itemUUID == block.entityUuid }
        let after = Self.bounded(.init(itemUUID: block.entityUuid,
            x: block.position.x - block.size.width / 2, y: block.position.y - block.size.height / 2,
            width: block.size.width, height: block.size.height), fallback: block.size)
        let hidden = (try? container.decodedSpaceCanvas().hiddenItemUUIDs.contains(block.entityUuid)) ?? false
        guard before != after || hidden else { return true }
        return commit(.init(placements: [.init(itemUUID: block.entityUuid, before: before, after: after,
            hiddenBefore: hidden, hiddenAfter: false)], drawings: []), title: title)
    }

    @discardableResult
    func add(_ block: CanvasBlock) async -> CanvasBlock? {
        do {
            var atom = try await AtomRepository.shared.fetch(uuid: block.entityUuid)
            if atom == nil {
                guard let type = AtomType(rawValue: block.entityType.rawValue) else { throw SpaceCompositionError.invalidKind }
                var created = Atom.new(type: type, title: block.title, body: block.metadata["content"])
                if !block.entityUuid.isEmpty { created.uuid = block.entityUuid }
                created.metadata = RichDocumentPersistence.writeAtomDocuments(existingMetadata: created.metadata,
                    titleDocument: nil, bodyDocument: RichDocumentPersistence.loadBlockDocument(
                        key: RichDocumentMetadataKeys.bodyDocument, metadata: block.metadata, fallbackPlainText: block.metadata["content"])).metadata
                atom = try await AtomRepository.shared.create(created)
            }
            guard let atom, let container else { throw SpaceCompositionError.notFound }
            let metadata = try container.decodedSpaceComposition() ?? SpaceCompositionMetadata()
            let hidden = try container.decodedSpaceCanvas().hiddenItemUUIDs.contains(atom.uuid)
            let before = metadata.placements.first { $0.itemUUID == atom.uuid }
            let after = Self.bounded(.init(itemUUID: atom.uuid, x: block.position.x - block.size.width / 2,
                y: block.position.y - block.size.height / 2, width: block.size.width, height: block.size.height), fallback: block.size)
            let memberBefore: Bool? = metadata.kind == .group && !metadata.memberUUIDs.contains(atom.uuid) ? false : nil
            let needsReference = metadata.kind.isAuthored && atom.spaceComposition?.parentUUID != containerUUID &&
                !metadata.references.contains(where: { $0.sourceUUID == atom.uuid })
            let reference = needsReference ? SpaceCompositionReference(id: "canvas:\(containerUUID):\(atom.uuid)",
                sourceUUID: atom.uuid, sourceTitle: atom.title) : nil
            let patch = SpaceCanvasPatch(placements: [.init(itemUUID: atom.uuid, before: before, after: after,
                hiddenBefore: hidden, hiddenAfter: false, memberBefore: memberBefore,
                memberAfter: memberBefore == false ? true : nil, referenceAfter: reference)])
            if !items.contains(where: { $0.uuid == atom.uuid }) { items.append(atom) }
            _ = commit(patch, title: memberBefore == false ? "Add to group canvas" : "Place on canvas")
            return project(atom, index: items.firstIndex(where: { $0.uuid == atom.uuid }) ?? 0)
        } catch { report(error); return nil }
    }

    func hide(_ block: CanvasBlock) {
        guard let container else { return }
        let hidden = (try? container.decodedSpaceCanvas().hiddenItemUUIDs.contains(block.entityUuid)) ?? false
        guard !hidden else { return }
        let before = container.spaceComposition?.placements.first { $0.itemUUID == block.entityUuid }
        _ = commit(.init(placements: [.init(itemUUID: block.entityUuid, before: before, after: before,
            hiddenBefore: false, hiddenAfter: true)]), title: "Remove from canvas")
    }

    func removeMembership(_ block: CanvasBlock) {
        guard let container, let metadata = container.spaceComposition, metadata.kind == .group,
              let index = metadata.memberUUIDs.firstIndex(of: block.entityUuid) else { return }
        let before = metadata.placements.first { $0.itemUUID == block.entityUuid }
        let hidden = (try? container.decodedSpaceCanvas().hiddenItemUUIDs.contains(block.entityUuid)) ?? false
        _ = commit(.init(placements: [.init(itemUUID: block.entityUuid, before: before, after: nil,
            hiddenBefore: hidden, hiddenAfter: false, memberBefore: true, memberAfter: false, memberIndex: index)]),
            title: "Remove from group")
    }

    /// Rich content is owned by the real atom. Geometry and membership remain in the container.
    func updateAtomMetadata(blockID: String, patch: [String: String]) throws {
        guard let item = atom(forBlockID: blockID) else { throw SpaceCompositionError.notFound }
        let updated = try database.write { db -> Atom in
            guard var fresh = try Atom.filter(Column("uuid") == item.uuid).filter(Column("is_deleted") == false).fetchOne(db) else { throw SpaceCompositionError.notFound }
            var metadata = fresh.metadataDict ?? [:]
            for (key, value) in patch where !key.hasPrefix("spaceCanvas") && key != "content" && key != "title" {
                if key == RichDocumentMetadataKeys.bodyDocument || key == RichDocumentMetadataKeys.titleDocument {
                    metadata[key] = try JSONSerialization.jsonObject(with: Data(value.utf8))
                } else { metadata[key] = value }
            }
            fresh.metadata = String(decoding: try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]), as: UTF8.self)
            if let content = patch["content"] {
                let document = RichDocumentPersistence.loadBlockDocument(key: RichDocumentMetadataKeys.bodyDocument, metadata: patch, fallbackPlainText: content)
                fresh.metadata = RichDocumentPersistence.writeAtomDocuments(existingMetadata: fresh.metadata, titleDocument: nil, bodyDocument: document).metadata
                fresh.body = content
            }
            if let title = patch["title"] { fresh.title = title }
            fresh.updatedAt = ISO8601.string(from: Date()); fresh.localVersion += 1
            try db.execute(sql: "UPDATE atoms SET title = ?, body = ?, metadata = ?, updated_at = ?, _local_version = ?, _local_pending = 1 WHERE uuid = ?", arguments: [fresh.title, fresh.body, fresh.metadata, fresh.updatedAt, fresh.localVersion, fresh.uuid])
            return fresh
        }
        CanvasAtomObservationHub.shared.absorb([updated])
        Task { await ChangeTracker.shared.trackUpdate(table: "atoms", entity: updated, skipVersionIncrement: true) }
        reload()
    }

    func saveDrawing(_ drawing: CanvasDrawing?) {
        guard let drawing, let container else { return }
        let before = try? container.decodedSpaceCanvas().drawings.first { $0.id == drawing.id }
        let after = SpaceCanvasDrawing(drawing)
        guard before != after else { return }
        _ = commit(.init(drawings: [.init(id: drawing.id, before: before, after: after)]), title: "Draw on canvas")
    }
    func deleteDrawing(_ id: String) {
        guard let before = try? container?.decodedSpaceCanvas().drawings.first(where: { $0.id == id }) else { return }
        _ = commit(.init(drawings: [.init(id: id, before: before, after: nil)]), title: "Erase drawing")
    }
    var drawings: [CanvasDrawing] { ((try? container?.decodedSpaceCanvas().drawings) ?? []).map(\.drawing) }

    func clusters(blocks: [CanvasBlock]) -> [CanvasCluster] {
        let values = (try? container?.decodedSpaceCanvas().clusters) ?? []
        return values.compactMap { value in
            guard let data = try? JSONEncoder().encode(value), let stored = try? JSONDecoder().decode(CodableCluster.self, from: data) else { return nil }
            return stored.toCanvasCluster(blocks: blocks, thinkspaceId: spaceID)
        }
    }
    func saveClusters(_ clusters: [CanvasCluster]) {
        let previous = (try? container?.decodedSpaceCanvas().clusters) ?? []
        let next = clusters.compactMap { cluster -> SpaceCanvasCluster? in
            guard let data = try? JSONEncoder().encode(CodableCluster(from: cluster)) else { return nil }
            return try? JSONDecoder().decode(SpaceCanvasCluster.self, from: data)
        }
        let oldByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        let newByID = Dictionary(uniqueKeysWithValues: next.map { ($0.id, $0) })
        let changes = Set(oldByID.keys).union(newByID.keys).sorted().compactMap { id -> SpaceCanvasClusterChange? in
            guard oldByID[id] != newByID[id] else { return nil }
            return .init(id: id, before: oldByID[id], after: newByID[id])
        }
        _ = commit(.init(clusters: changes), title: "Arrange canvas group")
    }

    func retry() {
        while let next = pending.first {
            do {
                let updated = try database.write { try SpaceCanvasPersistence.apply(next.patch, to: containerUUID, db: $0) }
                pending.removeFirst(); persistRecovery(); container = updated
                finish(updated, patch: next.patch, title: next.title, registerUndo: next.registerUndo)
            } catch { report(error); return }
        }
        error = nil; reload()
    }

    @discardableResult
    private func commit(_ patch: SpaceCanvasPatch, title: String, registerUndo: Bool = true) -> Bool {
        guard !patch.isEmpty else { return true }
        if pending.isEmpty {
            do {
                let updated = try database.write { try SpaceCanvasPersistence.apply(patch, to: containerUUID, db: $0) }
                container = updated
                finish(updated, patch: patch, title: title, registerUndo: registerUndo)
                reload(); return true
            } catch { report(error) }
        }
        pending.append(Pending(patch: patch, title: title, registerUndo: registerUndo))
        persistRecovery(); preview(patch); revision &+= 1
        return false
    }
    private func finish(_ atom: Atom, patch: SpaceCanvasPatch, title: String, registerUndo: Bool) {
        CanvasAtomObservationHub.shared.absorb([atom])
        Task { await ChangeTracker.shared.trackUpdate(table: "atoms", entity: atom, skipVersionIncrement: true) }
        NotificationCenter.default.post(name: SpaceCompositionService.didChange, object: nil)
        if registerUndo {
            CosmoUndoManager.shared.register(InlineUndoAction(actionDescription: title,
                undo: { [self] in _ = commit(patch.reversed, title: "Undo \(title)", registerUndo: false) },
                redo: { [self] in _ = commit(patch, title: "Redo \(title)", registerUndo: false) }))
        }
    }
    private func preview(_ patch: SpaceCanvasPatch) {
        guard let atom = container, var value = try? atom.decodedSpaceComposition(), var canvas = try? atom.decodedSpaceCanvas() else { return }
        for change in patch.placements {
            value.placements.removeAll { $0.itemUUID == change.itemUUID }
            if let after = change.after { value.placements.append(after) }
            canvas.hiddenItemUUIDs.removeAll { $0 == change.itemUUID }
            if change.hiddenAfter { canvas.hiddenItemUUIDs.append(change.itemUUID) }
            if let member = change.memberAfter {
                value.memberUUIDs.removeAll { $0 == change.itemUUID }
                if member { value.memberUUIDs.insert(change.itemUUID, at: min(value.memberUUIDs.count, max(0, change.memberIndex ?? value.memberUUIDs.count))) }
            }
            if let id = change.referenceBefore?.id ?? change.referenceAfter?.id {
                value.references.removeAll { $0.id == id }
                if let reference = change.referenceAfter { value.references.append(reference) }
            }
        }
        for change in patch.drawings {
            canvas.drawings.removeAll { $0.id == change.id }
            if let after = change.after { canvas.drawings.append(after) }
        }
        for change in patch.clusters {
            canvas.clusters.removeAll { $0.id == change.id }
            if let after = change.after { canvas.clusters.append(after) }
        }
        container = try? atom.replacingSpaceComposition(value).replacingSpaceCanvas(canvas)
    }
    private func ensurePositions() {
        var changed = false
        for atom in items where initialPositions[atom.uuid] == nil {
            let index = initialPositions.count
            initialPositions[atom.uuid] = CGPoint(x: CGFloat(index % 3) * 500, y: CGFloat(index / 3) * 630)
            changed = true
        }
        if changed {
            let encoded = initialPositions.mapValues { SpaceCanvasPoint(x: $0.x, y: $0.y) }
            if let data = try? JSONEncoder().encode(encoded) { UserDefaults.standard.set(data, forKey: "cosmo.space.collection.positions.mac.\(containerUUID)") }
        }
    }
    private func persistRecovery() {
        if pending.isEmpty { UserDefaults.standard.removeObject(forKey: recoveryKey) }
        else if let data = try? JSONEncoder().encode(pending) { UserDefaults.standard.set(data, forKey: recoveryKey) }
    }
    func report(_ error: Error) { self.error = "This canvas change hasn’t saved. \(error.localizedDescription)" }
    func open(_ atom: Atom) { selectedUUID = atom.uuid; onOpen?(atom) }
}

@MainActor
enum SpaceCompositionCanvasStore {
    private static var sessions: [String: SpaceCompositionCanvasSession] = [:]
    private static var order: [String] = []
    static func session(spaceID: String, containerUUID: String) -> SpaceCompositionCanvasSession {
        let key = "\(spaceID):\(containerUUID)"
        if let session = sessions[key] { return session }
        let session = SpaceCompositionCanvasSession(spaceID: spaceID, containerUUID: containerUUID)
        sessions[key] = session; order.append(key)
        while sessions.count > 12, let old = order.first(where: { $0 != key && sessions[$0]?.hasPendingEdits == false }) {
            sessions[old] = nil; order.removeAll { $0 == old }
        }
        return session
    }
}
