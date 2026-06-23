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

// MARK: - History

struct InboxHistoryEntry: Identifiable, Equatable {
    enum Kind: Equatable {
        case capture(InboxItem)
        case deletedLane(CaptureDestination)
    }

    let kind: Kind

    var id: String {
        switch kind {
        case .capture(let item): return "capture-\(item.uuid)"
        case .deletedLane(let lane): return "lane-\(lane.uuid)"
        }
    }

    var title: String {
        switch kind {
        case .capture(let item):
            return item.title ?? String(item.rawText.prefix(40))
        case .deletedLane(let lane):
            return lane.name
        }
    }

    var subtitle: String {
        switch kind {
        case .capture(let item):
            if item.status == .actioned, let destination = item.destinationPath ?? item.placeThinkspaceName {
                return "Placed · \(destination)"
            }
            if item.status == .dismissed {
                return "Dismissed capture"
            }
            return item.status.rawValue.capitalized
        case .deletedLane(let lane):
            var parts = ["Deleted lane", captureCountLine(for: lane.itemCount)]
            if let alias = lane.aliases.first, !alias.isEmpty {
                parts.append("\(alias):")
            }
            return parts.joined(separator: " · ")
        }
    }

    var actionDate: Date {
        let raw: String?
        switch kind {
        case .capture(let item):
            raw = item.actionedAt ?? item.createdAt
        case .deletedLane(let lane):
            raw = lane.updatedAt
        }
        return raw.flatMap(ISO8601.date(from:)) ?? .distantPast
    }

    var isRestorable: Bool {
        switch kind {
        case .capture(let item):
            return item.status == .dismissed
        case .deletedLane:
            return true
        }
    }

    static func merged(
        captures: [InboxItem],
        deletedLanes: [CaptureDestination],
        limit: Int
    ) -> [InboxHistoryEntry] {
        let entries = captures.map { InboxHistoryEntry(kind: .capture($0)) }
            + deletedLanes.map { InboxHistoryEntry(kind: .deletedLane($0)) }
        return Array(entries.sorted { lhs, rhs in
            if lhs.actionDate == rhs.actionDate {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.actionDate > rhs.actionDate
        }.prefix(limit))
    }
}

private func captureCountLine(for count: Int) -> String {
    count == 1 ? "1 capture" : "\(count) captures"
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
