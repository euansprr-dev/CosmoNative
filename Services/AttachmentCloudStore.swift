// CosmoOS/Services/AttachmentCloudStore.swift
// Blob mirror for the synced media_attachments domain. Rows sync through the
// standard pipeline; the actual image bytes mirror through the private
// Supabase Storage bucket `capture-media` (originals + thumbnails, one folder
// per user). Capturing device uploads; receiving devices lazy-download into
// a local cache. localStoragePath/thumbnailPath are DEVICE-LOCAL: only the
// capturing device writes them — receivers resolve bytes via this store and
// never mutate the row's path fields.

import AppKit
import Foundation

@MainActor
final class AttachmentCloudStore {
    static let shared = AttachmentCloudStore()

    static let bucket = "capture-media"

    private var mirrorInFlight = false
    private var downloadsInFlight: Set<String> = []

    private init() {}

    /// Cache directory for blobs downloaded from other devices.
    private var remoteCacheDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Cosmo")
            .appendingPathComponent("Captures")
            .appendingPathComponent("Remote")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    // MARK: - Upload (capturing device → cloud)

    /// Fire-and-forget kick from sync passes and attachment creation — drains
    /// the backlog of attachments with local bytes but no blobReference.
    static func kick() {
        Task { @MainActor in
            await shared.mirrorPending()
        }
    }

    func mirrorPending() async {
        guard !mirrorInFlight else { return }
        guard SupabaseSyncTrafficPolicy.allowsNetworkSync,
              let client = SupabaseClient.shared, client.isAuthenticated,
              let userId = client.currentUserId else { return }
        mirrorInFlight = true
        defer { mirrorInFlight = false }

        let pending = (try? await MediaAttachmentRepository.shared.fetchPendingMirror()) ?? []
        for attachment in pending {
            await mirror(attachment: attachment, client: client, userId: userId)
        }
    }

    /// Upload one attachment's original (+ thumbnail when present) and stamp
    /// blobReference — the tracked update rides sync so peers can download.
    func mirror(attachment: MediaAttachment, client: SupabaseClient, userId: String) async {
        guard let localPath = attachment.localStoragePath,
              let data = FileManager.default.contents(atPath: localPath) else { return }

        let ext = Self.fileExtension(mimeType: attachment.mimeType, localPath: attachment.localStoragePath)
        do {
            let blobURL = try await client.uploadStorageObject(
                bucket: Self.bucket,
                path: "\(userId.lowercased())/attachments/\(attachment.uuid).\(ext)",
                data: data,
                contentType: attachment.mimeType ?? "image/jpeg"
            )

            var thumbURL: String?
            if let thumbPath = attachment.thumbnailPath,
               let thumbData = FileManager.default.contents(atPath: thumbPath) {
                thumbURL = try? await client.uploadStorageObject(
                    bucket: Self.bucket,
                    path: "\(userId.lowercased())/attachments/\(attachment.uuid)-thumb.jpg",
                    data: thumbData,
                    contentType: "image/jpeg"
                )
            }

            try await MediaAttachmentRepository.shared.updateBlobReference(
                uuid: attachment.uuid,
                blobReference: blobURL,
                thumbBlobReference: thumbURL
            )
        } catch {
            print("AttachmentCloudStore: mirror failed for \(attachment.uuid): \(error)")
            // Stays in the pending-mirror backlog; next kick retries.
        }
    }

    /// Force a fresh upload after local bytes changed (in-portal edits) —
    /// `mirror` uploads with x-upsert, so the blob path stays stable and
    /// peers' next download sees the new content.
    func remirror(uuid: String) async {
        guard SupabaseSyncTrafficPolicy.allowsNetworkSync,
              let client = SupabaseClient.shared, client.isAuthenticated,
              let userId = client.currentUserId,
              let attachment = try? await MediaAttachmentRepository.shared.fetch(uuid: uuid) else { return }
        await mirror(attachment: attachment, client: client, userId: userId)
    }

    // MARK: - Resolve (any device → local bytes)

    /// Local file for the original image: the capturing device's own file when
    /// it exists, else the remote cache, else an authed download from Storage.
    func localOriginalURL(for attachment: MediaAttachment) async -> URL? {
        if let path = attachment.localStoragePath, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        let ext = Self.fileExtension(mimeType: attachment.mimeType, localPath: attachment.localStoragePath)
        let cached = remoteCacheDirectory.appendingPathComponent("\(attachment.uuid).\(ext)")
        if FileManager.default.fileExists(atPath: cached.path) { return cached }
        guard let blobReference = attachment.blobReference else { return nil }
        return await download(from: blobReference, to: cached, key: attachment.uuid)
    }

    /// Local file for the thumbnail, falling back to the original.
    func localThumbnailURL(for attachment: MediaAttachment) async -> URL? {
        if let path = attachment.thumbnailPath, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        let cached = remoteCacheDirectory.appendingPathComponent("\(attachment.uuid)-thumb.jpg")
        if FileManager.default.fileExists(atPath: cached.path) { return cached }
        if let thumbReference = Self.metadataValue(attachment.metadata, key: "thumbBlobReference"),
           let url = await download(from: thumbReference, to: cached, key: "\(attachment.uuid)-thumb") {
            return url
        }
        return await localOriginalURL(for: attachment)
    }

    private func download(from urlString: String, to destination: URL, key: String) async -> URL? {
        guard !downloadsInFlight.contains(key) else { return nil }
        guard let client = SupabaseClient.shared,
              let url = URL(string: urlString), client.isSupabaseHostedURL(url) else { return nil }
        downloadsInFlight.insert(key)
        defer { downloadsInFlight.remove(key) }
        do {
            let request = client.authorizedRequest(for: url)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  !data.isEmpty else { return nil }
            try data.write(to: destination, options: [.atomic])
            return destination
        } catch {
            print("AttachmentCloudStore: download failed for \(key): \(error)")
            return nil
        }
    }

    // MARK: - Helpers

    static func fileExtension(mimeType: String?, localPath: String?) -> String {
        if let localPath {
            let ext = (localPath as NSString).pathExtension.lowercased()
            if !ext.isEmpty { return ext }
        }
        switch mimeType?.lowercased() {
        case "image/png": return "png"
        case "image/heic": return "heic"
        case "image/webp": return "webp"
        case "application/pdf": return "pdf"
        default: return "jpg"
        }
    }

    static func metadataValue(_ metadata: String?, key: String) -> String? {
        guard let metadata, let data = metadata.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return dict[key] as? String
    }
}
