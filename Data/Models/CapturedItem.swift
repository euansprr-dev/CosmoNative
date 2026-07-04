// CosmoOS/Data/Models/CapturedItem.swift
// Durable raw capture records with provenance, created before routing or AI processing.

import Foundation
import GRDB

enum CapturedItemSource: String, Codable, Sendable {
    case telegram
    case quickCapture = "quick_capture"
    case cmdK = "cmd_k"
}

enum CapturedItemStatus: String, Codable, CaseIterable, Sendable {
    case captured
    case routed
    case applied
    case needsReview = "needs_review"
    case archived
    case failed
}

struct CapturedItem: Identifiable, Codable, Equatable, FetchableRecord, PersistableRecord, Sendable, Syncable, HasUUID {
    static let databaseTableName = "captured_items"

    var id: Int64?
    var uuid: String
    var rawText: String?
    var caption: String?
    var cleanText: String?
    var source: CapturedItemSource
    var telegramMessageId: String?
    var telegramMediaGroupId: String?
    var telegramChatId: String?
    var sender: String?
    var timestamp: String
    var captureDestinationId: String?
    var parsedCommand: String?
    var parsedIntent: String?
    var mediaAttachmentIdsJSON: String?
    var createdObjectIdsJSON: String?
    var routingConfidence: Double
    var status: CapturedItemStatus
    var parentDeepDiveId: String?
    var parentInquirySessionId: String?
    var parentQuestionId: String?
    var parentProjectId: String?
    var provenanceMetadata: String?
    var createdAt: String
    var updatedAt: String

    // Sync bookkeeping — lane captures sync Mac ↔ iPhone (July 2026). Snake
    // columns feed the shared pipeline; `updatedAt` above stays app data.
    var isDeleted: Bool
    var syncUpdatedAt: String?
    var localVersion: Int64
    var serverVersion: Int64
    var syncVersion: Int64

    enum CodingKeys: String, CodingKey, ColumnExpression {
        case id, uuid, rawText, caption, cleanText, source
        case telegramMessageId, telegramMediaGroupId, telegramChatId, sender, timestamp
        case captureDestinationId, parsedCommand, parsedIntent
        case mediaAttachmentIdsJSON, createdObjectIdsJSON, routingConfidence, status
        case parentDeepDiveId, parentInquirySessionId, parentQuestionId, parentProjectId
        case provenanceMetadata, createdAt, updatedAt
        case isDeleted = "is_deleted"
        case syncUpdatedAt = "updated_at"
        case localVersion = "_local_version"
        case serverVersion = "_server_version"
        case syncVersion = "_sync_version"
    }

    var mediaAttachmentIds: [String] {
        decodeCapturedStringArray(mediaAttachmentIdsJSON)
    }

    var createdObjectIds: [String] {
        decodeCapturedStringArray(createdObjectIdsJSON)
    }

    static func makeTelegram(
        rawText: String?,
        caption: String?,
        chatId: String,
        messageId: String?,
        mediaGroupId: String? = nil,
        sender: String? = nil,
        metadata: String? = nil
    ) -> CapturedItem {
        let now = ISO8601.string(from: Date())
        return CapturedItem(
            id: nil,
            uuid: UUID().uuidString,
            rawText: rawText,
            caption: caption,
            cleanText: rawText ?? caption,
            source: .telegram,
            telegramMessageId: messageId,
            telegramMediaGroupId: mediaGroupId,
            telegramChatId: chatId,
            sender: sender,
            timestamp: now,
            captureDestinationId: nil,
            parsedCommand: nil,
            parsedIntent: nil,
            mediaAttachmentIdsJSON: "[]",
            createdObjectIdsJSON: "[]",
            routingConfidence: 0,
            status: .captured,
            parentDeepDiveId: nil,
            parentInquirySessionId: nil,
            parentQuestionId: nil,
            parentProjectId: nil,
            provenanceMetadata: metadata,
            createdAt: now,
            updatedAt: now,
            isDeleted: false,
            syncUpdatedAt: now,
            localVersion: 1,
            serverVersion: 0,
            syncVersion: 0
        )
    }
}

private func decodeCapturedStringArray(_ value: String?) -> [String] {
    guard let value,
          let data = value.data(using: .utf8),
          let decoded = try? JSONDecoder().decode([String].self, from: data) else {
        return []
    }
    return decoded
}
