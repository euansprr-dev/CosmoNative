// CosmoOS/Data/ImageStore.swift
// File-based image persistence — stores images on disk at ~/Library/Application Support/Cosmo/images/

import AppKit
import UniformTypeIdentifiers

enum ImageStore {

    /// Directory where all image files are stored
    private static var imagesDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Cosmo/images", isDirectory: true)
    }

    // MARK: - Decoded-image cache

    /// Decoded images keyed by `path|mtime` so an edited file on disk
    /// invalidates naturally. Serves `load(path:)` and `resolve(_:)` — the
    /// editor serializer and presentation resyncs re-request the same paths
    /// constantly, and each miss was a full disk decode on the main thread.
    /// `nonisolated(unsafe)` is honest, not a shortcut: NSCache is
    /// thread-safe and NSImage is Sendable.
    nonisolated(unsafe) private static let decodedImageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 128
        return cache
    }()

    /// `path|mtime` identity for a file on disk; falls back to the bare path
    /// when attributes can't be read (missing file → natural cache miss).
    private static func cacheKey(forPath path: String) -> NSString {
        if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
           let mtime = attributes[.modificationDate] as? Date {
            return "\(path)|\(mtime.timeIntervalSinceReferenceDate)" as NSString
        }
        return path as NSString
    }

    /// Derived-image lookup (e.g. the serializer's scaled attachment
    /// bitmaps) under the same `path|mtime` identity plus a discriminator,
    /// so presentation resyncs don't re-rasterize every image.
    static func cachedDerivedImage(path: String, discriminator: String) -> NSImage? {
        decodedImageCache.object(forKey: "\(cacheKey(forPath: path))|\(discriminator)" as NSString)
    }

    static func storeDerivedImage(_ image: NSImage, path: String, discriminator: String) {
        decodedImageCache.setObject(image, forKey: "\(cacheKey(forPath: path))|\(discriminator)" as NSString)
    }

    /// Save image data to disk and return the path + dimensions
    static func save(_ imageData: Data, originalFilename: String?) throws -> (path: String, width: CGFloat, height: CGFloat) {
        // Ensure directory exists
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)

        // Determine file extension from original filename or default to .png
        let ext: String
        if let filename = originalFilename,
           let dotIndex = filename.lastIndex(of: ".") {
            ext = String(filename[filename.index(after: dotIndex)...]).lowercased()
        } else {
            ext = "png"
        }

        // Generate unique filename
        let filename = "\(UUID().uuidString).\(ext)"
        let fileURL = imagesDirectory.appendingPathComponent(filename)

        // Write to disk
        try imageData.write(to: fileURL)

        // Read dimensions
        let (width, height) = dimensions(from: imageData)

        return (path: fileURL.path, width: width, height: height)
    }

    /// Load an NSImage from a file path (served through the decoded cache)
    static func load(path: String) -> NSImage? {
        let key = cacheKey(forPath: path)
        if let cached = decodedImageCache.object(forKey: key) { return cached }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        decodedImageCache.setObject(image, forKey: key)
        return image
    }

    /// Delete an image file from disk
    static func delete(path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Cross-device (capture-media mirror)

    static let bucket = "capture-media"

    /// Cache for note images downloaded from other devices (iPhone captures).
    private static var remoteCacheDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Cosmo/images/Remote", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Resolve an image reference to a displayable NSImage: the device-local
    /// file when present, otherwise the shared remote copy (downloaded + cached
    /// once). Images authored on another device have no local `path`, only a
    /// `remoteURL` — this is how they render here.
    @MainActor
    static func resolve(_ ref: RichImageReference) async -> NSImage? {
        if !ref.path.isEmpty {
            // Cache check stays synchronous — the warm path returns on the
            // current tick. Only the disk decode hops off the main actor.
            let key = cacheKey(forPath: ref.path)
            if let warm = decodedImageCache.object(forKey: key) { return warm }
            let path = ref.path
            if let local = await Task.detached(priority: .userInitiated, operation: { NSImage(contentsOfFile: path) }).value {
                decodedImageCache.setObject(local, forKey: key)
                return local
            }
        }
        guard let remoteURL = ref.remoteURL, let url = URL(string: remoteURL) else { return nil }
        let cached = remoteCacheDirectory.appendingPathComponent(url.lastPathComponent)
        let cachedKey = cacheKey(forPath: cached.path)
        if let warm = decodedImageCache.object(forKey: cachedKey) { return warm }
        if let hit = NSImage(contentsOf: cached) {
            decodedImageCache.setObject(hit, forKey: cachedKey)
            return hit
        }
        guard let client = SupabaseClient.shared else { return nil }
        let request = client.authorizedRequest(for: url)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) ?? false,
              !data.isEmpty else { return nil }
        try? data.write(to: cached, options: [.atomic])
        guard let downloaded = NSImage(data: data) else { return nil }
        decodedImageCache.setObject(downloaded, forKey: cacheKey(forPath: cached.path))
        return downloaded
    }

    /// Upload a local note image to the shared bucket and return its URL, so
    /// the reference renders on iPhone. No-op offline / signed out.
    @MainActor
    static func uploadNoteImage(localPath: String) async -> String? {
        guard SupabaseSyncTrafficPolicy.allowsNetworkSync,
              let client = SupabaseClient.shared, client.isAuthenticated,
              let userId = client.currentUserId,
              let data = FileManager.default.contents(atPath: localPath) else { return nil }
        let ext = (localPath as NSString).pathExtension.isEmpty ? "png" : (localPath as NSString).pathExtension.lowercased()
        let name = (localPath as NSString).lastPathComponent
        let contentType = (ext == "jpg" || ext == "jpeg") ? "image/jpeg" : "image/\(ext)"
        return try? await client.uploadStorageObject(
            bucket: bucket,
            path: "\(userId.lowercased())/note-images/\(name)",
            data: data,
            contentType: contentType
        )
    }

    /// Mirror any local-only images in a document to the cloud, returning an
    /// updated document when at least one image gained a `remoteURL` (so the
    /// caller can persist it). Recurses through toggle/element children.
    @MainActor
    static func hydrateRemoteURLs(in document: RichDocument) async -> RichDocument? {
        var changed = false
        func process(_ blocks: [RichBlock]) async -> [RichBlock] {
            var out: [RichBlock] = []
            for var block in blocks {
                if block.kind == .image {
                    for index in block.inlines.indices {
                        guard block.inlines[index].kind == .imageRef,
                              var ref = block.inlines[index].image,
                              ref.remoteURL == nil, !ref.path.isEmpty,
                              FileManager.default.fileExists(atPath: ref.path) else { continue }
                        if let url = await uploadNoteImage(localPath: ref.path) {
                            ref.remoteURL = url
                            block.inlines[index].image = ref
                            changed = true
                        }
                    }
                }
                if !block.children.isEmpty {
                    block.children = await process(block.children)
                }
                out.append(block)
            }
            return out
        }
        let newBlocks = await process(document.blocks)
        return changed ? RichDocument(blocks: newBlocks) : nil
    }

    /// Read a note's saved body document, upload any local-only images, and
    /// persist the stamped remoteURLs back through the repository. Decoupled
    /// from the live editor save (runs at note close), idempotent, and a no-op
    /// once every image has mirrored. Safe to fire-and-forget.
    @MainActor
    static func hydrateNoteImages(uuid: String) async {
        guard let atom = try? await AtomRepository.shared.fetch(uuid: uuid),
              let document = RichDocumentMetadataStorage.readDocument(
                from: atom.metadata, key: RichDocumentMetadataKeys.bodyDocument),
              let updated = await hydrateRemoteURLs(in: document) else { return }
        _ = try? await AtomRepository.shared.update(uuid: uuid) { atom in
            atom.metadata = RichDocumentMetadataStorage.writeDocument(
                updated, into: atom.metadata, key: RichDocumentMetadataKeys.bodyDocument)
        }
    }

    /// Extract pixel dimensions from image data
    private static func dimensions(from data: Data) -> (CGFloat, CGFloat) {
        guard let image = NSImage(data: data),
              let rep = image.representations.first else {
            return (320, 240)
        }
        return (CGFloat(rep.pixelsWide), CGFloat(rep.pixelsHigh))
    }
}
