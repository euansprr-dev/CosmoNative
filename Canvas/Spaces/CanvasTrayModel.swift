import SwiftUI

/// Bridges a tray drag onto the canvas drop delegate — the same idiom the
/// cluster views use (`ClusterViewDragSession`): the closure form of
/// `.onDrag` runs at drag start, which `.draggable` never exposes.
@MainActor
enum CanvasTrayDragSession {
    static var draggingEntityUuid: String?
    static let payloadPrefix = "unplaced:"

    static func payload(for entityUuid: String) -> String { payloadPrefix + entityUuid }

    static func entityUuid(from payload: String) -> String? {
        guard payload.hasPrefix(payloadPrefix) else { return nil }
        let uuid = String(payload.dropFirst(payloadPrefix.count))
        return uuid.isEmpty ? nil : uuid
    }
}
