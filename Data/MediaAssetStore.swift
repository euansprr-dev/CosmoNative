// CosmoOS/Data/MediaAssetStore.swift
// File-based persistence for concept-board media assets (images AND videos)
// at ~/Library/Application Support/Cosmo/media/ — the video-capable sibling
// of ImageStore. Owned assets mirror to the shared capture-media bucket so
// other devices can render them.

import AppKit
import AVFoundation
import UniformTypeIdentifiers

enum MediaAssetStore {

    struct SavedAsset {
        let path: String
        let thumbnailPath: String?
        let width: CGFloat
        let height: CGFloat
        let isVideo: Bool
        let durationSeconds: Double?
    }

    private static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "webm"]
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "bmp"]

    /// Directory where all concept media assets live.
    static var mediaDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Cosmo/media", isDirectory: true)
    }

    static func isVideoPath(_ path: String) -> Bool {
        videoExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    static func isSupportedMediaExtension(_ ext: String) -> Bool {
        let lowered = ext.lowercased()
        return videoExtensions.contains(lowered) || imageExtensions.contains(lowered)
    }

    // MARK: - Save

    /// Persist raw media data (pasted image, downloaded file). Video assets
    /// get a poster frame generated alongside.
    static func save(_ data: Data, originalFilename: String?) async throws -> SavedAsset {
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        let ext = fileExtension(from: originalFilename, fallback: "png")
        let filename = "\(UUID().uuidString).\(ext)"
        let fileURL = mediaDirectory.appendingPathComponent(filename)
        try data.write(to: fileURL)
        return await describeSavedFile(at: fileURL)
    }

    /// Copy a file already on disk (Finder drop) into the store.
    static func importFile(at sourceURL: URL) async throws -> SavedAsset {
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension.lowercased()
        let filename = "\(UUID().uuidString).\(ext)"
        let fileURL = mediaDirectory.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: sourceURL, to: fileURL)
        return await describeSavedFile(at: fileURL)
    }

    private static func describeSavedFile(at fileURL: URL) async -> SavedAsset {
        if isVideoPath(fileURL.path) {
            let asset = AVAsset(url: fileURL)
            let duration = (try? await asset.load(.duration)).map(CMTimeGetSeconds)
            let posterPath = await generatePoster(for: fileURL)
            var width: CGFloat = 320
            var height: CGFloat = 240
            if let posterPath, let poster = NSImage(contentsOfFile: posterPath),
               let rep = poster.representations.first {
                width = CGFloat(rep.pixelsWide)
                height = CGFloat(rep.pixelsHigh)
            }
            return SavedAsset(
                path: fileURL.path,
                thumbnailPath: posterPath,
                width: width,
                height: height,
                isVideo: true,
                durationSeconds: duration
            )
        }
        var width: CGFloat = 320
        var height: CGFloat = 240
        if let image = NSImage(contentsOf: fileURL), let rep = image.representations.first {
            width = CGFloat(rep.pixelsWide)
            height = CGFloat(rep.pixelsHigh)
        }
        return SavedAsset(path: fileURL.path, thumbnailPath: nil, width: width, height: height, isVideo: false, durationSeconds: nil)
    }

    private static func fileExtension(from filename: String?, fallback: String) -> String {
        guard let filename, let dotIndex = filename.lastIndex(of: ".") else { return fallback }
        let ext = String(filename[filename.index(after: dotIndex)...]).lowercased()
        return ext.isEmpty ? fallback : ext
    }

    /// Poster frame for a video asset, saved next to it as <name>-poster.jpg.
    static func generatePoster(for videoURL: URL) async -> String? {
        let asset = AVAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 800, height: 1600)
        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        guard let (cgImage, _) = try? await generator.image(at: time) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return nil }
        let posterURL = videoURL.deletingPathExtension().appendingPathExtension("poster.jpg")
        do {
            try jpeg.write(to: posterURL)
            return posterURL.path
        } catch {
            return nil
        }
    }

    // MARK: - Load / delete

    /// Cache for assets authored on other devices (remote-only refs).
    private static var remoteCacheDirectory: URL {
        let base = mediaDirectory.appendingPathComponent("Remote", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Resolve an owned-asset ref to a displayable image: poster/local file
    /// first, then the shared remote copy (downloaded + cached once).
    @MainActor
    static func resolveImage(_ item: ConnectionMediaItem) async -> NSImage? {
        if let poster = item.thumbnailAssetPath, let image = NSImage(contentsOfFile: poster) {
            return image
        }
        if let path = item.assetPath, !isVideoPath(path), let image = NSImage(contentsOfFile: path) {
            return image
        }
        guard let remote = item.assetRemoteURL, let url = URL(string: remote) else { return nil }
        let cached = remoteCacheDirectory.appendingPathComponent(url.lastPathComponent)
        if let hit = NSImage(contentsOf: cached) { return hit }
        guard let client = SupabaseClient.shared else { return nil }
        let request = client.authorizedRequest(for: url)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) ?? false,
              !data.isEmpty else { return nil }
        try? data.write(to: cached, options: [.atomic])
        return NSImage(data: data)
    }

    /// Delete an OWNED asset's files. Only called from explicit detach —
    /// atom-backed refs never reach here.
    static func deleteAsset(of item: ConnectionMediaItem) {
        guard item.atomUUID == nil else { return }
        if let path = item.assetPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        if let poster = item.thumbnailAssetPath {
            try? FileManager.default.removeItem(atPath: poster)
        }
    }

    // MARK: - Cloud mirror

    /// Upload an owned asset to the shared bucket, returning its URL — the
    /// same capture-media bucket note images ride. No-op offline/signed out.
    @MainActor
    static func mirrorToCloud(_ item: ConnectionMediaItem) async -> String? {
        guard item.assetRemoteURL == nil,
              let localPath = item.assetPath,
              SupabaseSyncTrafficPolicy.allowsNetworkSync,
              let client = SupabaseClient.shared, client.isAuthenticated,
              let userId = client.currentUserId,
              let data = FileManager.default.contents(atPath: localPath) else { return nil }
        let ext = (localPath as NSString).pathExtension.lowercased()
        let name = (localPath as NSString).lastPathComponent
        let contentType: String
        if videoExtensions.contains(ext) {
            contentType = ext == "mov" ? "video/quicktime" : "video/\(ext)"
        } else {
            contentType = (ext == "jpg" || ext == "jpeg") ? "image/jpeg" : "image/\(ext)"
        }
        return try? await client.uploadStorageObject(
            bucket: ImageStore.bucket,
            path: "\(userId.lowercased())/concept-media/\(name)",
            data: data,
            contentType: contentType
        )
    }
}
