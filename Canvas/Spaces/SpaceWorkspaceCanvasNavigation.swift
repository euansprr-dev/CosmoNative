import SwiftUI

struct SpaceWorkspaceCreationRequest: Identifiable {
    let id = UUID()
    let spaceID: String
    let kind: SpaceCompositionKind
    let placingNear: CGPoint?
}

/// Placement is durable before navigation. The canvas consumes a reveal only
/// once its destination and saved blocks are mounted, with no timer race.
@MainActor @Observable
final class SpaceWorkspaceCanvasNavigation {
    static let shared = SpaceWorkspaceCanvasNavigation()
    private(set) var pendingUUIDs: [String: String] = [:]
    @ObservationIgnored private var origins: [String: CGPoint] = [:]

    func remember(origin: CGPoint, in spaceID: String) { origins[spaceID] = origin }
    func origin(in spaceID: String) -> CGPoint { origins[spaceID] ?? .zero }
    func consume(in spaceID: String) { pendingUUIDs[spaceID] = nil }

    static func reveal(atomUUID: String, in spaceID: String) async throws {
        try await SpaceCompositionService.addOriginals([atomUUID], in: spaceID,
            placingNear: shared.origin(in: spaceID))
        shared.pendingUUIDs[spaceID] = atomUUID
        let manager = ThinkspaceManager.shared
        if manager.currentThinkspace?.id != spaceID,
           let space = manager.thinkspaces.first(where: { $0.id == spaceID }) {
            await manager.switchTo(space)
        }
        SpaceWorkspaceStore.shared.showRoot(.canvas, in: spaceID)
    }
}
