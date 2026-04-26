// CosmoOS/UI/Inbox/InboxTypes.swift
// Supporting types for the Inbox system — filters, sorting, sections, stats, groups
// March 2026

import Foundation

// MARK: - Filtering

enum InboxFilter: Hashable {
    case source(InboxSource)
    case classification(InboxClassification)
    case unreadOnly
}

// MARK: - Sorting

enum InboxSortOrder: String, CaseIterable {
    case newestFirst = "Newest"
    case oldestFirst = "Oldest"
    case byConfidence = "Confidence"
    case byPriority = "Priority"
}

// MARK: - Temporal Sections

struct InboxSection: Identifiable {
    let id: String
    let title: String
    let items: [InboxItem]
}

// MARK: - Stats

struct InboxStats: Equatable {
    let total: Int
    let mergeCount: Int
    let placeCount: Int
    let newCount: Int
    let pendingCount: Int

    static let empty = InboxStats(total: 0, mergeCount: 0, placeCount: 0, newCount: 0, pendingCount: 0)

    init(total: Int, mergeCount: Int, placeCount: Int, newCount: Int, pendingCount: Int) {
        self.total = total
        self.mergeCount = mergeCount
        self.placeCount = placeCount
        self.newCount = newCount
        self.pendingCount = pendingCount
    }

    init(items: [InboxItem]) {
        self.total = items.count
        self.mergeCount = items.filter { $0.classification == .merge }.count
        self.placeCount = items.filter { $0.classification == .place }.count
        self.newCount = items.filter { $0.classification == .new }.count
        self.pendingCount = items.filter { $0.classification == nil }.count
    }
}

// MARK: - Intelligence Grouping

struct InboxItemGroup: Identifiable {
    let id: String
    let theme: String
    let itemIds: [String]
    let suggestedAction: String?
    let mergeTargetUuid: String?
    let mergeTargetTitle: String?
}

// MARK: - Entity Color Helpers

import SwiftUI

extension InboxItem {
    /// Entity color for the suggested atom type
    var entityColor: Color {
        guard let typeStr = placeAtomType,
              let type = AtomType(rawValue: typeStr) else {
            return connectionEntityColor
        }
        return Self.entityColor(for: type)
    }

    /// Soft background variant of the entity color
    var entitySoftColor: Color {
        guard let typeStr = placeAtomType,
              let type = AtomType(rawValue: typeStr) else {
            return connectionEntitySoftColor
        }
        return Self.entitySoftColor(for: type)
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

    static func entitySoftColor(for type: AtomType) -> Color {
        entityColor(for: type).opacity(0.12)
    }

    private var connectionEntityColor: Color { DS.entityConnection }
    private var connectionEntitySoftColor: Color { DS.entityConnection.opacity(0.12) }

    /// Priority score (0-100) computed locally
    var priorityScore: Int {
        var score = 50
        if confidence > 0.7 { score += 15 }
        else if confidence > 0.5 { score += 5 }
        if classification == .merge { score += 10 }
        if source == .telegramVoice { score += 5 }
        if rawText.count > 200 { score += 10 }
        else if rawText.count > 100 { score += 5 }

        let ageInDays = Self.daysSinceCreation(createdAt)
        if ageInDays > 7 { score -= 20 }
        else if ageInDays > 3 { score -= 10 }

        return max(0, min(100, score))
    }

    /// Whether this item is stale (>3 days old)
    var isStale: Bool {
        Self.daysSinceCreation(createdAt) > 3
    }

    /// Days since creation
    var ageInDays: Int {
        Self.daysSinceCreation(createdAt)
    }

    private static func daysSinceCreation(_ dateStr: String) -> Int {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateStr) else { return 0 }
        return max(0, Int(Date().timeIntervalSince(date) / 86400))
    }
}
