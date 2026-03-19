// CosmoOS/Data/ThumbnailCacheService.swift
// Persistent thumbnail cache with memory + disk layers.
// Replaces AsyncImage for swipe gallery thumbnails to ensure images
// load once and persist across app restarts.

import AppKit
import CryptoKit
import SwiftUI

// MARK: - ThumbnailCacheService

actor ThumbnailCacheService {
    static let shared = ThumbnailCacheService()

    private let memoryCache = NSCache<NSString, NSImage>()
    private var inflightTasks: [String: Task<NSImage?, Never>] = [:]

    private var cacheDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Cosmo/ThumbnailCache", isDirectory: true)
    }

    private init() {
        memoryCache.countLimit = 200
    }

    // MARK: - Cache Key

    /// Derive a stable, filesystem-safe cache key.
    /// Priority: explicit stableKey > YouTube video ID from URL > SHA256 of URL path (no query params).
    nonisolated func cacheKey(for url: URL, stableKey: String?) -> String {
        if let key = stableKey, !key.isEmpty { return key }

        // Extract YouTube video ID
        if let host = url.host, host.contains("youtube") || host.contains("youtu.be") {
            if host.contains("youtu.be") {
                let videoId = url.lastPathComponent
                if !videoId.isEmpty { return "yt-\(videoId)" }
            }
            if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let videoId = comps.queryItems?.first(where: { $0.name == "v" })?.value {
                return "yt-\(videoId)"
            }
        }

        // Fallback: hash the URL path (strip expiring query params)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        let stable = components?.string ?? url.absoluteString
        let hash = SHA256.hash(data: Data(stable.utf8))
        return hash.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Lookup

    /// Fast synchronous check — memory cache only.
    func cachedImage(for key: String) -> NSImage? {
        memoryCache.object(forKey: key as NSString)
    }

    /// Full lookup: memory → disk → network download.
    func image(for url: URL, key: String) async -> NSImage? {
        // 1. Memory
        if let cached = memoryCache.object(forKey: key as NSString) { return cached }

        // 2. Disk
        let diskPath = cacheDirectory.appendingPathComponent("thumb-\(key).jpg")
        if FileManager.default.fileExists(atPath: diskPath.path),
           let diskImage = NSImage(contentsOf: diskPath) {
            memoryCache.setObject(diskImage, forKey: key as NSString)
            return diskImage
        }

        // 3. Deduplicated network fetch
        if let existing = inflightTasks[key] { return await existing.value }

        let dir = cacheDirectory
        let task = Task<NSImage?, Never> {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = NSImage(data: data) else { return nil }

                // Persist to disk as JPEG
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                if let tiff = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiff),
                   let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
                    try? jpeg.write(to: diskPath)
                }

                self.memoryCache.setObject(image, forKey: key as NSString)
                return image
            } catch {
                return nil
            }
        }
        inflightTasks[key] = task
        let result = await task.value
        inflightTasks.removeValue(forKey: key)
        return result
    }
}

// MARK: - CachedAsyncImage

/// Drop-in replacement for AsyncImage that uses persistent disk + memory caching.
struct CachedAsyncImage<Content: View>: View {
    let url: URL?
    let stableKey: String?
    @ViewBuilder let content: (CachedImagePhase) -> Content

    @State private var phase: CachedImagePhase = .empty

    init(
        url: URL?,
        stableKey: String? = nil,
        @ViewBuilder content: @escaping (CachedImagePhase) -> Content
    ) {
        self.url = url
        self.stableKey = stableKey
        self.content = content
    }

    var body: some View {
        content(phase)
            .task(id: url) {
                guard let url else {
                    phase = .failure
                    return
                }

                let cache = ThumbnailCacheService.shared
                let key = cache.cacheKey(for: url, stableKey: stableKey)

                // Check memory cache first (instant, no flicker)
                if let cached = await cache.cachedImage(for: key) {
                    phase = .success(Image(nsImage: cached))
                    return
                }

                // Full lookup: disk then network
                if let image = await cache.image(for: url, key: key) {
                    phase = .success(Image(nsImage: image))
                } else {
                    phase = .failure
                }
            }
    }
}

enum CachedImagePhase {
    case empty
    case success(Image)
    case failure
}
