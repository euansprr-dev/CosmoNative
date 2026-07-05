// CosmoOS/Data/Models/InboxItem.swift
// Smart Triage Inbox — transient captures awaiting user action
// March 2026

import Foundation
import GRDB

// MARK: - InboxItem Model

struct InboxItem: Identifiable, Codable, Equatable, FetchableRecord, PersistableRecord, Syncable, HasUUID {
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

    // Sync bookkeeping (mirrors Atom's snake-cased sync columns). The inbox
    // is a synced, local-first domain since July 2026 — captures made on the
    // iPhone and triage/classification updates flow both ways through the
    // standard pipeline (sync_queue → push → pull → ConflictResolver).
    var isDeleted: Bool
    /// Server-cursor mirror — snake `updated_at` is what pull cursors and
    /// tombstone comparisons read; the camelCase timestamps stay app data.
    var syncUpdatedAt: String?
    var localVersion: Int64
    var serverVersion: Int64
    var syncVersion: Int64

    enum CodingKeys: String, CodingKey, ColumnExpression {
        case id, uuid, source, rawText, title, classification, confidence
        case mergeTargetUuid, mergeTargetTitle, mergeTargetType, mergePreview
        case placeThinkspaceId, placeThinkspaceName, placeAtomType
        case recommendations, primaryRouteKind, destinationPath, rationale, placementPlanSummary
        case status, isRead, createdAt, classifiedAt, actionedAt, metadata
        case isDeleted = "is_deleted"
        case syncUpdatedAt = "updated_at"
        case localVersion = "_local_version"
        case serverVersion = "_server_version"
        case syncVersion = "_sync_version"
    }

    // MARK: - Explicit routing

    /// Metadata key stamped when the destination was the USER'S choice
    /// (Telegram topic alias, deep-dive accept) — never a classifier guess.
    static let explicitDestinationMetadataKey = "explicitDestination"
    /// Metadata key listing deep-dive UUIDs the user removed this capture
    /// from (comma-joined) — those topics stop suggesting it.
    static let suppressedTopicsMetadataKey = "suppressedTopicUUIDs"

    var metadataDictionary: [String: Any] {
        guard let metadata,
              let data = metadata.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return parsed
    }

    /// True when this capture's placement is user-confirmed, not an AI
    /// recommendation. A topic's inbox shows only these; everything else is
    /// at most a suggestion the user can accept or dismiss.
    var isExplicitlyRouted: Bool {
        if (metadataDictionary[Self.explicitDestinationMetadataKey] as? String) == "true" { return true }
        // Legacy pre-marker alias captures: the preset path wrote a
        // full-confidence .place with no recommendation bundle and no
        // rationale — a signature no classifier or taxonomy write produces.
        return classification == .place
            && confidence >= 0.999
            && recommendations == nil
            && rationale == nil
    }

    /// True when the user removed this capture from the given topic —
    /// that deep dive must not resurface it as a suggestion.
    func isSuppressed(forTopic topicUUID: String) -> Bool {
        guard let joined = metadataDictionary[Self.suppressedTopicsMetadataKey] as? String else { return false }
        return joined.split(separator: ",").map(String.init).contains(topicUUID)
    }

    // MARK: - Factory

    /// True when the item's predicted destination is a task atom.
    /// Tasks live in the Command Center, not in any thinkspace canvas, so the
    /// triage UI excludes them from the "unclear" cluster.
    var routesToTask: Bool {
        placeAtomType?.lowercased() == "task"
    }

    /// True when the classifier produced a suggestion worth showing.
    /// `.unsorted` and legacy `.new` rows render as plain captures with no pill.
    var hasActionableSuggestion: Bool {
        switch classification {
        case .merge, .place: return true
        case .new, .unsorted, .none: return false
        }
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
            createdAt: ISO8601.string(from: Date()),
            classifiedAt: nil,
            actionedAt: nil,
            metadata: metadata,
            isDeleted: false,
            syncUpdatedAt: ISO8601.string(from: Date()),
            localVersion: 1,
            serverVersion: 0,
            syncVersion: 0
        )
    }
}

// MARK: - Enums
// All three decode tolerantly: one row with an unknown rawValue (newer app
// version, manual edit, sync drift) must not poison every fetch and blank the
// whole inbox. Each fallback renders safely in the existing UI.

enum InboxSource: String, Codable, Sendable {
    case telegramVoice = "telegram_voice"
    case telegramText = "telegram_text"
    case quickCapture = "quick_capture"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = InboxSource(rawValue: raw) ?? .quickCapture
    }
}

enum InboxClassification: String, Codable, Sendable {
    case merge
    case place
    case new        // Legacy: "create standalone atom" suggestion (pre-June 2026 rows)
    case unsorted   // Honest abstain — classifier ran, nothing cleared the confidence bar

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = InboxClassification(rawValue: raw) ?? .unsorted
    }
}

enum InboxItemStatus: String, Codable, Sendable {
    case pending       // Just arrived, classification in progress
    case classified    // AI has suggested an action
    case actioned      // User confirmed and action completed
    case dismissed     // User dismissed without action

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = InboxItemStatus(rawValue: raw) ?? .pending
    }
}
