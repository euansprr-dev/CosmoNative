// CosmoOS/Data/Models/MediaAttachment.swift
// Media attached to captured records — Telegram files, and (July 2026) photos
// of physical pages captured on either device. A synced, local-first domain:
// rows flow Mac ↔ iPhone through the standard pipeline; the image blobs
// mirror through Supabase Storage (`capture-media`) via AttachmentCloudStore.
//
// Owner generalization: an attachment belongs to (ownerType, ownerUUID) —
// inbox_item | captured_item | extract | source_atom. `capturedItemId`
// survives for legacy Telegram rows and always mirrors ownerUUID.

import Foundation
import GRDB

enum MediaAttachmentKind: String, Codable, CaseIterable, Sendable {
    case image
    case screenshot
    case pageScan = "page_scan"
    case pdf
    case epub
    case textFile = "text_file"
    case markdown
    case audio
    case video
    case document
    case unknown

    // Sync drift tolerance (Mac contract): one row with an unknown rawValue
    // from a newer app version must not poison every fetch.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MediaAttachmentKind(rawValue: raw) ?? .unknown
    }

    var displayName: String {
        switch self {
        case .image: return "Image"
        case .screenshot: return "Screenshot"
        case .pageScan: return "Page Scan"
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

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MediaProcessingStatus(rawValue: raw) ?? .downloaded
    }

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

/// What kind of record an attachment belongs to.
enum MediaAttachmentOwner: String, Sendable {
    case inboxItem = "inbox_item"
    case capturedItem = "captured_item"
    case extract = "extract"
    case sourceAtom = "source_atom"
    /// A routed capture's destination atom (idea, note, task, connection…).
    case atom = "atom"
    /// A page streamed for a Mac scan request, before the Mac re-homes it
    /// onto the scan source it builds.
    case captureRequest = "capture_request"
}

struct MediaAttachment: Identifiable, Codable, Equatable, FetchableRecord, PersistableRecord, Sendable, Syncable, HasUUID {
    static let databaseTableName = "media_attachments"

    var id: Int64?
    var uuid: String
    /// Legacy Telegram linkage — always mirrors ownerUUID on new rows.
    var capturedItemId: String
    /// Generalized linkage: what record this attachment belongs to.
    var ownerType: String
    var ownerUUID: String
    var kind: MediaAttachmentKind
    var originalFilename: String?
    var mimeType: String?
    var fileSize: Int64?
    var telegramFileId: String?
    var telegramFileUniqueId: String?
    /// Device-local path to the original — NEVER synced meaningfully across
    /// devices (each device resolves its own copy via AttachmentCloudStore).
    var localStoragePath: String?
    /// Authenticated Supabase Storage URL of the original once mirrored.
    var blobReference: String?
    var thumbnailPath: String?
    var extractedText: String?
    var transcriptText: String?
    /// JSON: pageIndex, scanSessionId, thumbBlobReference, visionLines
    /// (provenance boxes), inkMarks, transcriptionConfidence, needsLLMPass.
    var metadata: String?
    var processingStatus: MediaProcessingStatus
    var sourceObjectId: String?
    var createdAt: String
    var updatedAt: String

    // Sync bookkeeping (snake columns shared with iOS + Supabase)
    var isDeleted: Bool
    var syncUpdatedAt: String?
    var localVersion: Int64
    var serverVersion: Int64
    var syncVersion: Int64

    enum CodingKeys: String, CodingKey, ColumnExpression {
        case id, uuid, capturedItemId, ownerType, ownerUUID, kind
        case originalFilename, mimeType, fileSize
        case telegramFileId, telegramFileUniqueId
        case localStoragePath, blobReference, thumbnailPath
        case extractedText, transcriptText, metadata
        case processingStatus, sourceObjectId, createdAt, updatedAt
        case isDeleted = "is_deleted"
        case syncUpdatedAt = "updated_at"
        case localVersion = "_local_version"
        case serverVersion = "_server_version"
        case syncVersion = "_sync_version"
    }

    // Tolerant decode: rows written before the sync columns existed (or by an
    // older peer) decode with safe defaults instead of failing the fetch.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int64.self, forKey: .id)
        uuid = try c.decode(String.self, forKey: .uuid)
        capturedItemId = try c.decodeIfPresent(String.self, forKey: .capturedItemId) ?? ""
        let owner = try c.decodeIfPresent(String.self, forKey: .ownerUUID)
        ownerUUID = (owner?.isEmpty == false ? owner! : (try c.decodeIfPresent(String.self, forKey: .capturedItemId) ?? ""))
        ownerType = try c.decodeIfPresent(String.self, forKey: .ownerType) ?? MediaAttachmentOwner.capturedItem.rawValue
        kind = try c.decodeIfPresent(MediaAttachmentKind.self, forKey: .kind) ?? .unknown
        originalFilename = try c.decodeIfPresent(String.self, forKey: .originalFilename)
        mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType)
        fileSize = try c.decodeIfPresent(Int64.self, forKey: .fileSize)
        telegramFileId = try c.decodeIfPresent(String.self, forKey: .telegramFileId)
        telegramFileUniqueId = try c.decodeIfPresent(String.self, forKey: .telegramFileUniqueId)
        localStoragePath = try c.decodeIfPresent(String.self, forKey: .localStoragePath)
        blobReference = try c.decodeIfPresent(String.self, forKey: .blobReference)
        thumbnailPath = try c.decodeIfPresent(String.self, forKey: .thumbnailPath)
        extractedText = try c.decodeIfPresent(String.self, forKey: .extractedText)
        transcriptText = try c.decodeIfPresent(String.self, forKey: .transcriptText)
        metadata = try c.decodeIfPresent(String.self, forKey: .metadata)
        processingStatus = try c.decodeIfPresent(MediaProcessingStatus.self, forKey: .processingStatus) ?? .downloaded
        sourceObjectId = try c.decodeIfPresent(String.self, forKey: .sourceObjectId)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ISO8601.string(from: Date())
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt) ?? createdAt
        isDeleted = (try? c.decodeIfPresent(Bool.self, forKey: .isDeleted)) ?? false
        syncUpdatedAt = try c.decodeIfPresent(String.self, forKey: .syncUpdatedAt)
        localVersion = (try? c.decodeIfPresent(Int64.self, forKey: .localVersion)) ?? 1
        serverVersion = (try? c.decodeIfPresent(Int64.self, forKey: .serverVersion)) ?? 0
        syncVersion = (try? c.decodeIfPresent(Int64.self, forKey: .syncVersion)) ?? 0
    }

    init(
        id: Int64?,
        uuid: String,
        capturedItemId: String,
        ownerType: String,
        ownerUUID: String,
        kind: MediaAttachmentKind,
        originalFilename: String?,
        mimeType: String?,
        fileSize: Int64?,
        telegramFileId: String?,
        telegramFileUniqueId: String?,
        localStoragePath: String?,
        blobReference: String?,
        thumbnailPath: String?,
        extractedText: String?,
        transcriptText: String?,
        metadata: String?,
        processingStatus: MediaProcessingStatus,
        sourceObjectId: String?,
        createdAt: String,
        updatedAt: String,
        isDeleted: Bool = false,
        syncUpdatedAt: String? = nil,
        localVersion: Int64 = 1,
        serverVersion: Int64 = 0,
        syncVersion: Int64 = 0
    ) {
        self.id = id
        self.uuid = uuid
        self.capturedItemId = capturedItemId
        self.ownerType = ownerType
        self.ownerUUID = ownerUUID
        self.kind = kind
        self.originalFilename = originalFilename
        self.mimeType = mimeType
        self.fileSize = fileSize
        self.telegramFileId = telegramFileId
        self.telegramFileUniqueId = telegramFileUniqueId
        self.localStoragePath = localStoragePath
        self.blobReference = blobReference
        self.thumbnailPath = thumbnailPath
        self.extractedText = extractedText
        self.transcriptText = transcriptText
        self.metadata = metadata
        self.processingStatus = processingStatus
        self.sourceObjectId = sourceObjectId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.syncUpdatedAt = syncUpdatedAt
        self.localVersion = localVersion
        self.serverVersion = serverVersion
        self.syncVersion = syncVersion
    }

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
        let now = ISO8601.string(from: Date())
        return MediaAttachment(
            id: nil,
            uuid: UUID().uuidString,
            capturedItemId: capturedItemId,
            ownerType: MediaAttachmentOwner.capturedItem.rawValue,
            ownerUUID: capturedItemId,
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
            updatedAt: now,
            syncUpdatedAt: now
        )
    }

    /// A locally captured attachment (page scan, camera photo, upload) that
    /// already has its bytes on this device.
    static func makeLocal(
        owner: MediaAttachmentOwner,
        ownerUUID: String,
        kind: MediaAttachmentKind,
        localStoragePath: String?,
        thumbnailPath: String? = nil,
        originalFilename: String? = nil,
        mimeType: String? = "image/jpeg",
        fileSize: Int64? = nil,
        metadata: String? = nil
    ) -> MediaAttachment {
        let now = ISO8601.string(from: Date())
        return MediaAttachment(
            id: nil,
            uuid: UUID().uuidString,
            capturedItemId: ownerUUID,
            ownerType: owner.rawValue,
            ownerUUID: ownerUUID,
            kind: kind,
            originalFilename: originalFilename,
            mimeType: mimeType,
            fileSize: fileSize,
            telegramFileId: nil,
            telegramFileUniqueId: nil,
            localStoragePath: localStoragePath,
            blobReference: nil,
            thumbnailPath: thumbnailPath,
            extractedText: nil,
            transcriptText: nil,
            metadata: metadata,
            processingStatus: .downloaded,
            sourceObjectId: nil,
            createdAt: now,
            updatedAt: now,
            syncUpdatedAt: now
        )
    }
}
