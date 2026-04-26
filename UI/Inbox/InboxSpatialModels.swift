import SwiftUI

enum InboxViewMode: String, CaseIterable {
    case canvas
    case list

    var title: String {
        switch self {
        case .canvas: return "Canvas"
        case .list: return "List"
        }
    }

    var icon: String {
        switch self {
        case .canvas: return "rectangle.3.group"
        case .list: return "list.bullet"
        }
    }
}

enum InboxSpatialSelection: Equatable {
    case inboxItem(String)
    case databaseAtom(String)
}

enum InboxSoftClusterKind: String, Equatable {
    case place
    case merge
    case new
    case unclear
    case database

    var badge: String {
        switch self {
        case .place: return "PLACE"
        case .merge: return "MERGE"
        case .new: return "NEW"
        case .unclear: return "UNCLEAR"
        case .database: return "UNPLACED"
        }
    }

    var icon: String {
        switch self {
        case .place: return "arrow.turn.down.right"
        case .merge: return "arrow.triangle.merge"
        case .new: return "sparkles"
        case .unclear: return "questionmark.circle"
        case .database: return "tray.full"
        }
    }

    var accent: Color {
        switch self {
        case .place: return DS.accent
        case .merge: return DS.orange
        case .new: return DS.entityIdea
        case .unclear: return DS.textMuted
        case .database: return DS.entityConnection
        }
    }
}

struct InboxDatabaseCandidate: Identifiable, Equatable {
    let atom: Atom
    let title: String
    let preview: String
    let relativeDate: String

    var id: String { atom.uuid }
    var uuid: String { atom.uuid }
    var atomType: AtomType { atom.type }
    var entityId: Int64 { atom.id ?? 0 }

    var icon: String {
        atom.type.iconName
    }

    var accent: Color {
        switch atom.type {
        case .task: return DS.entityTask
        case .content, .contentDraft: return DS.entityContent
        case .research: return DS.entityResearch
        case .connection, .clientProfile: return DS.entityConnection
        case .note: return DS.orange
        case .image: return DS.entityImage
        default: return DS.textSecondary
        }
    }
}

struct InboxSoftCluster: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let kind: InboxSoftClusterKind
    let inboxItemIds: [String]
    let databaseAtomIds: [String]
    var isCollapsed: Bool = false

    var itemCount: Int {
        inboxItemIds.count + databaseAtomIds.count
    }

    var canBatchPlace: Bool {
        kind == .place && !inboxItemIds.isEmpty
    }
}

extension InboxItem {
    var spatialActionTitle: String {
        switch classification {
        case .merge: return "Merge"
        case .place: return "Place"
        case .new: return "New"
        case .none: return "Reading"
        }
    }

    var spatialDestinationTitle: String {
        if let destinationPath, !destinationPath.isEmpty { return destinationPath }
        if let placeThinkspaceName, !placeThinkspaceName.isEmpty { return placeThinkspaceName }
        if let mergeTargetTitle, !mergeTargetTitle.isEmpty { return mergeTargetTitle }
        if let placeAtomType, !placeAtomType.isEmpty { return placeAtomType.capitalized }
        return "Needs a home"
    }

    var confidenceLabel: String {
        if confidence >= 0.75 { return "High" }
        if confidence >= 0.45 { return "Med" }
        if confidence > 0 { return "Low" }
        return "Pending"
    }
}
