// CosmoOS/Data/Models/InboxItem.swift
// Smart Triage Inbox — transient captures awaiting user action
// March 2026

import Foundation
import GRDB

// MARK: - InboxItem Model

struct InboxItem: Identifiable, Codable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "inbox_items"

    var id: Int64?
    let uuid: String

    // Raw capture
    let source: InboxSource
    let rawText: String
    var title: String?

    // Classification (populated by InboxClassificationEngine)
    var classification: InboxClassification?
    var confidence: Double

    // Merge target (when classification == .merge)
    var mergeTargetUuid: String?
    var mergeTargetTitle: String?
    var mergeTargetType: String?
    var mergePreview: String?

    // Place target (when classification == .place)
    var placeThinkspaceId: String?
    var placeThinkspaceName: String?
    var placeAtomType: String?
    var recommendations: String?
    var primaryRouteKind: String?
    var destinationPath: String?
    var rationale: String?
    var placementPlanSummary: String?

    // State
    var status: InboxItemStatus
    var isRead: Bool

    // Timestamps
    var createdAt: String
    var classifiedAt: String?
    var actionedAt: String?

    // Source-specific metadata (JSON)
    var metadata: String?

    // MARK: - Factory

    /// True when the item's predicted destination is a task atom.
    /// Tasks live in the Command Center, not in any thinkspace canvas, so the
    /// triage UI excludes them from the "unclear" cluster.
    var routesToTask: Bool {
        placeAtomType?.lowercased() == "task"
    }

    static func new(
        source: InboxSource,
        rawText: String,
        title: String? = nil,
        metadata: String? = nil
    ) -> InboxItem {
        InboxItem(
            id: nil,
            uuid: UUID().uuidString,
            source: source,
            rawText: rawText,
            title: title,
            classification: nil,
            confidence: 0.0,
            mergeTargetUuid: nil,
            mergeTargetTitle: nil,
            mergeTargetType: nil,
            mergePreview: nil,
            placeThinkspaceId: nil,
            placeThinkspaceName: nil,
            placeAtomType: nil,
            recommendations: nil,
            primaryRouteKind: nil,
            destinationPath: nil,
            rationale: nil,
            placementPlanSummary: nil,
            status: .pending,
            isRead: false,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            classifiedAt: nil,
            actionedAt: nil,
            metadata: metadata
        )
    }
}

// MARK: - Enums

enum InboxSource: String, Codable, Sendable {
    case telegramVoice = "telegram_voice"
    case telegramText = "telegram_text"
    case quickCapture = "quick_capture"
}

enum InboxClassification: String, Codable, Sendable {
    case merge
    case place
    case new
}

enum InboxItemStatus: String, Codable, Sendable {
    case pending       // Just arrived, classification in progress
    case classified    // AI has suggested an action
    case actioned      // User confirmed and action completed
    case dismissed     // User dismissed without action
}
