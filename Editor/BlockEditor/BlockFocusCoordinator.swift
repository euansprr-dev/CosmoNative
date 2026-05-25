import Foundation
import Observation

@MainActor
@Observable
final class BlockFocusCoordinator {
    private(set) var focusedBlockID: UUID?
    private var registeredBlockIDs: [UUID] = []

    func register(_ blockID: UUID?) {
        guard let blockID, !registeredBlockIDs.contains(blockID) else { return }
        registeredBlockIDs.append(blockID)
    }

    func unregister(_ blockID: UUID?) {
        guard let blockID else { return }
        registeredBlockIDs.removeAll { $0 == blockID }
        if focusedBlockID == blockID {
            focusedBlockID = nil
        }
    }

    func focus(_ blockID: UUID?) {
        guard let blockID else { return }
        register(blockID)
        focusedBlockID = blockID
    }

    func commandTargetID(for blockID: UUID?, baseTargetID: String?) -> String? {
        guard let baseTargetID, !baseTargetID.isEmpty else { return nil }
        guard let blockID else { return baseTargetID }

        if focusedBlockID == blockID || (focusedBlockID == nil && registeredBlockIDs.first == blockID) {
            return baseTargetID
        }

        return "\(baseTargetID):block:\(blockID.uuidString)"
    }

    @discardableResult
    func focusNext() -> Bool {
        moveFocus(offset: 1)
    }

    @discardableResult
    func focusPrevious() -> Bool {
        moveFocus(offset: -1)
    }

    func focusInto(elementID: UUID?) {
        focus(elementID)
    }

    func focusOutOf(elementID: UUID?) {
        if focusedBlockID == elementID {
            focusedBlockID = nil
        }
    }

    private func moveFocus(offset: Int) -> Bool {
        guard !registeredBlockIDs.isEmpty else { return false }
        guard let focusedBlockID,
              let currentIndex = registeredBlockIDs.firstIndex(of: focusedBlockID) else {
            return false
        }

        let nextIndex = currentIndex + offset
        guard registeredBlockIDs.indices.contains(nextIndex) else { return false }
        self.focusedBlockID = registeredBlockIDs[nextIndex]
        return true
    }
}
