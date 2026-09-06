// CosmoOS/Data/Repositories/MediaAttachmentRepository.swift
// Persistence and lookup for captured media (Telegram files + physical page
// scans). A synced domain since July 2026: every write bumps _local_version,
// stamps updated_at, sets the pending shield, and rides ChangeTracker so rows
// reach the iPhone. Blob bytes mirror separately via AttachmentCloudStore.

import Foundation
import GRDB

@MainActor
final class MediaAttachmentRepository {
    static let shared = MediaAttachmentRepository()

    private let database = CosmoDatabase.shared
    private init() {}

    @discardableResult
    func create(_ attachment: MediaAttachment) async throws -> MediaAttachment {
        let saved = try await database.asyncWrite { db in
            var mutable = attachment
            mutable.syncUpdatedAt = ISO8601.string(from: Date())
            try mutable.insert(db)
            mutable.id = db.lastInsertedRowID
            try CaptureSyncOutbox.enqueue(db, table: "media_attachments", uuid: mutable.uuid)
            return mutable
        }
        await ChangeTracker.shared.trackInsert(table: MediaAttachment.databaseTableName, entity: saved)
        return saved
    }

    func fetch(uuid: String) async throws -> MediaAttachment? {
        try await database.asyncRead { db in
            try MediaAttachment
                .filter(Column("uuid") == uuid)
                .fetchOne(db)
        }
    }

    func fetch(uuids: [String]) async throws -> [MediaAttachment] {
        guard !uuids.isEmpty else { return [] }
        return try await database.asyncRead { db in
            try MediaAttachment
                .filter(uuids.contains(Column("uuid")))
                .filter(sql: "COALESCE(is_deleted, 0) = 0")
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    func fetch(capturedItemId: String) async throws -> [MediaAttachment] {
        try await fetch(capturedItemIds: [capturedItemId])
    }

    /// One ordered query for a lane, preserving each capture's media order.
    func fetch(capturedItemIds: [String]) async throws -> [MediaAttachment] {
        guard !capturedItemIds.isEmpty else { return [] }
        return try await database.asyncRead { db in
            try MediaAttachment
                .filter(capturedItemIds.contains(Column("capturedItemId")))
                .filter(sql: "COALESCE(is_deleted, 0) = 0")
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    func fetch(owner: MediaAttachmentOwner, ownerUUID: String) async throws -> [MediaAttachment] {
        try await database.asyncRead { db in
            try MediaAttachment
                .filter(Column("ownerType") == owner.rawValue)
                .filter(Column("ownerUUID") == ownerUUID)
                .filter(sql: "COALESCE(is_deleted, 0) = 0")
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    /// Attachments still awaiting the careful vision-LLM pass (captured on a
    /// device without an AI key, offline, or saved mid-pass). Attempt-capped
    /// by the worker via the `transcriptionAttempts` metadata key.
    func fetchNeedingTranscription(limit: Int = 5) async throws -> [MediaAttachment] {
        try await database.asyncRead { db in
            try MediaAttachment
                .filter(sql: """
                    COALESCE(is_deleted, 0) = 0
                    AND metadata LIKE '%"needsLLMPass":true%'
                    """)
                .order(Column("createdAt").asc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Attachments whose bytes exist locally but were never mirrored to
    /// Supabase Storage — the cloud-mirror backlog.
    func fetchPendingMirror(limit: Int = 20) async throws -> [MediaAttachment] {
        try await database.asyncRead { db in
            try MediaAttachment
                .filter(sql: """
                    COALESCE(is_deleted, 0) = 0
                    AND localStoragePath IS NOT NULL
                    AND (blobReference IS NULL OR blobReference = '')
                    """)
                .order(Column("createdAt").asc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Tracked mutations

    /// Fetch-mutate-write inside one transaction with sync bookkeeping; the
    /// mutation closure returns false to abort. Returns the saved row.
    @discardableResult
    func trackedMutation(
        uuid: String,
        _ mutate: @Sendable @escaping (inout MediaAttachment) -> Bool
    ) async throws -> MediaAttachment? {
        let updated = try await database.asyncWrite { db -> MediaAttachment? in
            guard var attachment = try MediaAttachment.filter(Column("uuid") == uuid).fetchOne(db) else { return nil }
            guard mutate(&attachment) else { return nil }
            attachment.localVersion += 1
            attachment.updatedAt = ISO8601.string(from: Date())
            attachment.syncUpdatedAt = attachment.updatedAt
            try attachment.update(db)
            try CaptureSyncOutbox.enqueue(db, table: "media_attachments", uuid: attachment.uuid)
            return attachment
        }
        if let updated {
            await ChangeTracker.shared.trackUpdate(
                table: MediaAttachment.databaseTableName,
                entity: updated,
                skipVersionIncrement: true
            )
        }
        return updated
    }

    func updateDownload(
        uuid: String,
        localStoragePath: String?,
        thumbnailPath: String? = nil,
        status: MediaProcessingStatus
    ) async throws {
        _ = try await trackedMutation(uuid: uuid) { attachment in
            attachment.localStoragePath = localStoragePath
            attachment.thumbnailPath = thumbnailPath ?? attachment.thumbnailPath
            attachment.processingStatus = status
            return true
        }
    }

    func updateExtractedText(uuid: String, text: String?, status: MediaProcessingStatus) async throws {
        _ = try await trackedMutation(uuid: uuid) { attachment in
            attachment.extractedText = text
            attachment.processingStatus = status
            return true
        }
    }

    func updateTranscript(uuid: String, transcript: String?, status: MediaProcessingStatus) async throws {
        _ = try await trackedMutation(uuid: uuid) { attachment in
            attachment.transcriptText = transcript
            attachment.processingStatus = status
            return true
        }
    }

    func updateBlobReference(uuid: String, blobReference: String, thumbBlobReference: String?) async throws {
        _ = try await trackedMutation(uuid: uuid) { attachment in
            attachment.blobReference = blobReference
            if let thumbBlobReference {
                attachment.metadata = Self.mergingMetadataKey(
                    attachment.metadata, key: "thumbBlobReference", value: thumbBlobReference
                )
            }
            return true
        }
    }

    func softDelete(uuid: String) async throws {
        _ = try await trackedMutation(uuid: uuid) { attachment in
            attachment.isDeleted = true
            return true
        }
    }

    // MARK: - Helpers

    /// Key-level merge into the metadata JSON — never clobber unknown keys.
    /// Pure string work — nonisolated so mutation closures off the main
    /// actor can call it.
    nonisolated static func mergingMetadataKey(_ metadata: String?, key: String, value: Any) -> String? {
        var dict: [String: Any] = [:]
        if let metadata, let data = metadata.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict = parsed
        }
        dict[key] = value
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: data, encoding: .utf8) else { return metadata }
        return json
    }
}
