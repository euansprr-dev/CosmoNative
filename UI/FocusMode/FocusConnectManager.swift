// CosmoOS/UI/FocusMode/FocusConnectManager.swift
// Manages Option+drag connection gestures within focus mode views
// February 2026 - Universal Linking (F6)

import SwiftUI

@MainActor
final class FocusConnectManager: ObservableObject {
    @Published var isActive = false
    @Published var sourceElement: ConnectableElement?
    @Published var sourceCenter: CGPoint = .zero
    @Published var currentDragPoint: CGPoint = .zero
    @Published var hoveredTargetId: String?
    @Published var connectionComplete = false

    /// Elements that can be connected in focus modes
    enum ConnectableElement: Equatable {
        case floatingPanel(id: String, atomUUID: String)
        case annotationCard(id: String)
        case sectionItem(id: String)

        var identifier: String {
            switch self {
            case .floatingPanel(let id, _): return "panel-\(id)"
            case .annotationCard(let id): return "annotation-\(id)"
            case .sectionItem(let id): return "section-\(id)"
            }
        }

        var atomUUID: String? {
            switch self {
            case .floatingPanel(_, let uuid): return uuid
            default: return nil
            }
        }
    }

    func beginConnection(from element: ConnectableElement, center: CGPoint) {
        isActive = true
        sourceElement = element
        sourceCenter = center
        currentDragPoint = center
        hoveredTargetId = nil
        connectionComplete = false
    }

    func updateDrag(to point: CGPoint) {
        guard isActive else { return }
        currentDragPoint = point
    }

    func cancel() {
        withAnimation(.spring(response: 0.2)) {
            isActive = false
            sourceElement = nil
            hoveredTargetId = nil
            connectionComplete = false
        }
    }

    /// Complete connection between two elements
    func completeConnection(target: ConnectableElement, focusAtomUUID: String) {
        guard let source = sourceElement, source != target else {
            cancel()
            return
        }

        connectionComplete = true

        // If both elements have atom UUIDs, create an AtomLink
        if let sourceUUID = source.atomUUID, let targetUUID = target.atomUUID {
            Task {
                do {
                    guard let sourceAtom = try await AtomRepository.shared.fetch(uuid: sourceUUID),
                          let targetAtom = try await AtomRepository.shared.fetch(uuid: targetUUID) else {
                        cancel()
                        return
                    }

                    // Create bidirectional links (same pattern as DragToConnectManager)
                    if !sourceAtom.linksList.contains(where: { $0.uuid == targetUUID }) {
                        let newLink = AtomLink.related(targetUUID, entityType: AtomType(rawValue: targetAtom.type.rawValue))
                        let updatedSource = sourceAtom.addingLink(newLink)
                        try await AtomRepository.shared.update(updatedSource)
                    }

                    if !targetAtom.linksList.contains(where: { $0.uuid == sourceUUID }) {
                        let reverseLink = AtomLink.related(sourceUUID, entityType: AtomType(rawValue: sourceAtom.type.rawValue))
                        let updatedTarget = targetAtom.addingLink(reverseLink)
                        try await AtomRepository.shared.update(updatedTarget)
                    }

                    try await Task.sleep(for: .milliseconds(400))
                    await MainActor.run { self.cancel() }
                } catch {
                    print("FocusConnect: Failed to create link: \(error)")
                    cancel()
                }
            }
        } else {
            // Intra-atom connections (annotation to section, etc.)
            // Store in UserDefaults keyed by focus atom UUID
            let key = "focusConnections_\(focusAtomUUID)"
            var connections = UserDefaults.standard.array(forKey: key) as? [[String: String]] ?? []
            connections.append([
                "source": source.identifier,
                "target": target.identifier
            ])
            UserDefaults.standard.set(connections, forKey: key)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.cancel()
            }
        }
    }
}
