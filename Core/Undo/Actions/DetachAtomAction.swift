// CosmoOS/Core/Undo/Actions/DetachAtomAction.swift

import Foundation

/// Undo for the "Remove from thinkspace" tier: an atom's placements in ONE
/// thinkspace were soft-deleted, but the atom itself stays alive in the Library
/// and untouched in any other thinkspaces. Undo re-attaches those placements;
/// redo detaches them again.
///
/// Because the atom is never tombstoned, restoring the placements can never
/// strand a ghost block (the canvas_tombstone_cascade hazard) — the atom row is
/// always present.
@MainActor
final class DetachAtomAction: UndoableAction {
    let actionDescription = "Remove from Thinkspace"
    let timestamp: Date

    private let entityUuid: String
    private let thinkspaceId: String
    private weak var spatialEngine: SpatialEngine?

    init(entityUuid: String, thinkspaceId: String, spatialEngine: SpatialEngine) {
        self.entityUuid = entityUuid
        self.thinkspaceId = thinkspaceId
        self.spatialEngine = spatialEngine
        self.timestamp = Date()
    }

    func undo() async {
        await spatialEngine?.reattachAtomToThinkspace(entityUuid: entityUuid, thinkspaceId: thinkspaceId)
    }

    func redo() async {
        await spatialEngine?.removeAtomFromThinkspace(entityUuid: entityUuid, thinkspaceId: thinkspaceId)
    }
}
