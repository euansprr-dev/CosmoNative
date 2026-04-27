// CosmoOS/Data/Repositories/MediaAttachmentRepository.swift
// Persistence and lookup for captured Telegram media.

import Foundation
import GRDB

@MainActor
final class MediaAttachmentRepository {
    static let shared = MediaAttachmentRepository()

    private let database = CosmoDatabase.shared
    private init() {}

    @discardableResult
    func create(_ attachment: MediaAttachment) async throws -> MediaAttachment {
        try await database.asyncWrite { db in
            let mutable = attachment
            try mutable.insert(db)
            return mutable
        }
    }

    func fetch(uuid: String) async throws -> MediaAttachment? {
        try await database.asyncRead { db in
            try MediaAttachment
                .filter(Column("uuid") == uuid)
                .fetchOne(db)
        }
    }

    func fetch(capturedItemId: String) async throws -> [MediaAttachment] {
        try await database.asyncRead { db in
            try MediaAttachment
                .filter(Column("capturedItemId") == capturedItemId)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    func updateDownload(
        uuid: String,
        localStoragePath: String?,
        thumbnailPath: String? = nil,
        status: MediaProcessingStatus
    ) async throws {
        try await database.asyncWrite { db in
            guard var attachment = try MediaAttachment
                .filter(Column("uuid") == uuid)
                .fetchOne(db) else { return }
            attachment.localStoragePath = localStoragePath
            attachment.thumbnailPath = thumbnailPath ?? attachment.thumbnailPath
            attachment.processingStatus = status
            attachment.updatedAt = ISO8601DateFormatter().string(from: Date())
            try attachment.update(db)
        }
    }

    func updateExtractedText(uuid: String, text: String?, status: MediaProcessingStatus) async throws {
        try await database.asyncWrite { db in
            guard var attachment = try MediaAttachment
                .filter(Column("uuid") == uuid)
                .fetchOne(db) else { return }
            attachment.extractedText = text
            attachment.processingStatus = status
            attachment.updatedAt = ISO8601DateFormatter().string(from: Date())
            try attachment.update(db)
        }
    }

    func updateTranscript(uuid: String, transcript: String?, status: MediaProcessingStatus) async throws {
        try await database.asyncWrite { db in
            guard var attachment = try MediaAttachment
                .filter(Column("uuid") == uuid)
                .fetchOne(db) else { return }
            attachment.transcriptText = transcript
            attachment.processingStatus = status
            attachment.updatedAt = ISO8601DateFormatter().string(from: Date())
            try attachment.update(db)
        }
    }
}
