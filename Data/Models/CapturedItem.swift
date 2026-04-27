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

struct CapturedItem: Identifiable, Codable, Equatable, FetchableRecord, PersistableRecord, Sendable {
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
        let now = ISO8601DateFormatter().string(from: Date())
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
            updatedAt: now
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
