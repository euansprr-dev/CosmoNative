// CosmoOS/UI/Inbox/InboxTypes.swift
// Supporting types for the triage-queue Inbox — temporal sections and
// display helpers. June 2026 rebuild: filters, sort orders, stats rows, and
// intelligence groups were retired with the old dashboard UI.

import Foundation
import SwiftUI

// MARK: - Temporal Sections

struct InboxSection: Identifiable {
    let id: String
    let title: String
    let items: [InboxItem]
}

// MARK: - Display Helpers

extension InboxItem {
    /// Human destination line for pills, toasts, and the inspector.
    var spatialDestinationTitle: String {
        if let destinationPath, !destinationPath.isEmpty { return destinationPath }
        if let placeThinkspaceName, !placeThinkspaceName.isEmpty { return placeThinkspaceName }
        if let mergeTargetTitle, !mergeTargetTitle.isEmpty { return mergeTargetTitle }
        if let placeAtomType, !placeAtomType.isEmpty { return placeAtomType.capitalized }
        return "Needs a home"
    }

    /// Entity color for the suggested atom type
    var entityColor: Color {
        guard let typeStr = placeAtomType,
              let type = AtomType(rawValue: typeStr) else {
            return DS.entityConnection
        }
        return Self.entityColor(for: type)
    }

    static func entityColor(for type: AtomType) -> Color {
        switch type {
        case .idea: return DS.entityIdea
        case .research: return DS.entityResearch
        case .content: return DS.entityContent
        case .note: return DS.entityNote
        case .connection: return DS.entityConnection
        case .task: return DS.entityTask
        default: return DS.entityConnection
        }
    }
}
