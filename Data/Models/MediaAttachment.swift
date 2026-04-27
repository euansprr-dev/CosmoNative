// CosmoOS/Data/Models/MediaAttachment.swift
// Telegram media/file/audio attachments linked to captured items.

import Foundation
import GRDB

enum MediaAttachmentKind: String, Codable, CaseIterable, Sendable {
    case image
    case screenshot
    case pdf
    case epub
    case textFile = "text_file"
    case markdown
    case audio
    case video
    case document
    case unknown

    var displayName: String {
        switch self {
        case .image: return "Image"
        case .screenshot: return "Screenshot"
        case .pdf: return "PDF"
        case .epub: return "EPUB"
        case .textFile: return "Text File"
        case .markdown: return "Markdown"
        case .audio: return "Audio"
        case .video: return "Video"
        case .document: return "Document"
        case .unknown: return "File"
        }
    }
}

enum MediaProcessingStatus: String, Codable, CaseIterable, Sendable {
    case pendingDownload = "pending_download"
    case downloaded
    case thumbnailGenerated = "thumbnail_generated"
    case textExtracted = "text_extracted"
    case transcribed
    case indexed
    case failed
    case skipped

    var displayName: String {
        switch self {
        case .pendingDownload: return "Pending download"
        case .downloaded: return "Downloaded"
        case .thumbnailGenerated: return "Thumbnail ready"
        case .textExtracted: return "Text extracted"
        case .transcribed: return "Transcribed"
        case .indexed: return "Indexed"
        case .failed: return "Failed"
        case .skipped: return "Skipped"
        }
    }
}

struct MediaAttachment: Identifiable, Codable, Equatable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "media_attachments"

    var id: Int64?
    var uuid: String
    var capturedItemId: String
    var kind: MediaAttachmentKind
    var originalFilename: String?
    var mimeType: String?
    var fileSize: Int64?
    var telegramFileId: String?
    var telegramFileUniqueId: String?
    var localStoragePath: String?
    var blobReference: String?
    var thumbnailPath: String?
    var extractedText: String?
    var transcriptText: String?
    var metadata: String?
    var processingStatus: MediaProcessingStatus
    var sourceObjectId: String?
    var createdAt: String
    var updatedAt: String

    static func makeTelegram(
        capturedItemId: String,
        kind: MediaAttachmentKind,
        fileId: String,
        fileUniqueId: String? = nil,
        filename: String? = nil,
        mimeType: String? = nil,
        fileSize: Int64? = nil,
        metadata: String? = nil
    ) -> MediaAttachment {
        let now = ISO8601DateFormatter().string(from: Date())
        return MediaAttachment(
            id: nil,
            uuid: UUID().uuidString,
            capturedItemId: capturedItemId,
            kind: kind,
            originalFilename: filename,
            mimeType: mimeType,
            fileSize: fileSize,
            telegramFileId: fileId,
            telegramFileUniqueId: fileUniqueId,
            localStoragePath: nil,
            blobReference: nil,
            thumbnailPath: nil,
            extractedText: nil,
            transcriptText: nil,
            metadata: metadata,
            processingStatus: .pendingDownload,
            sourceObjectId: nil,
            createdAt: now,
            updatedAt: now
        )
    }
}
