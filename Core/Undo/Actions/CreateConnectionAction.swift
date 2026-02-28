// CosmoOS/Core/Undo/Actions/CreateConnectionAction.swift

import Foundation

@MainActor
final class CreateConnectionAction: UndoableAction {
    let actionDescription = "Create Connection"
    let timestamp: Date

    private let sourceUUID: String
    private let targetUUID: String

    init(sourceUUID: String, targetUUID: String) {
        self.sourceUUID = sourceUUID
        self.targetUUID = targetUUID
        self.timestamp = Date()
    }

    func undo() async {
        do {
            // Remove link from source atom
            if let sourceAtom = try await AtomRepository.shared.fetch(uuid: sourceUUID) {
                let updated = sourceAtom.removingLink(toUUID: targetUUID)
                try await AtomRepository.shared.update(updated)
                try await NodeGraphEngine.shared.handleAtomUpdated(updated, changedFields: ["links"])
            }

            // Remove link from target atom
            if let targetAtom = try await AtomRepository.shared.fetch(uuid: targetUUID) {
                let updated = targetAtom.removingLink(toUUID: sourceUUID)
                try await AtomRepository.shared.update(updated)
                try await NodeGraphEngine.shared.handleAtomUpdated(updated, changedFields: ["links"])
            }

            NotificationCenter.default.post(
                name: CosmoNotification.NodeGraph.graphNodeUpdated,
                object: nil
            )
        } catch {
            print("❌ CreateConnectionAction.undo failed: \(error)")
        }
    }

    func redo() async {
        do {
            guard let sourceAtom = try await AtomRepository.shared.fetch(uuid: sourceUUID),
                  let targetAtom = try await AtomRepository.shared.fetch(uuid: targetUUID) else { return }

            // Re-add link on source
            if !sourceAtom.linksList.contains(where: { $0.uuid == targetUUID }) {
                let link = AtomLink.related(targetUUID, entityType: targetAtom.type)
                let updated = sourceAtom.addingLink(link)
                try await AtomRepository.shared.update(updated)
                try await NodeGraphEngine.shared.handleAtomUpdated(updated, changedFields: ["links"])
            }

            // Re-add link on target
            if !targetAtom.linksList.contains(where: { $0.uuid == sourceUUID }) {
                let link = AtomLink.related(sourceUUID, entityType: sourceAtom.type)
                let updated = targetAtom.addingLink(link)
                try await AtomRepository.shared.update(updated)
                try await NodeGraphEngine.shared.handleAtomUpdated(updated, changedFields: ["links"])
            }

            NotificationCenter.default.post(
                name: CosmoNotification.NodeGraph.graphNodeUpdated,
                object: nil
            )
        } catch {
            print("❌ CreateConnectionAction.redo failed: \(error)")
        }
    }
}
