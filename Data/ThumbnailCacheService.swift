// CosmoOS/Data/ThumbnailCacheService.swift
// Persistent thumbnail cache with memory + disk layers.
// Replaces AsyncImage for swipe gallery thumbnails to ensure images
// load once and persist across app restarts.

import AppKit
import CryptoKit
import Foundation
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
    /// `nonisolated` is safe because NSCache is thread-safe.
    nonisolated func cachedImage(for key: String) -> NSImage? {
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
                let request: URLRequest
                if InstagramCarouselImageCache.shouldUseInstagramHeaders(for: url) {
                    request = InstagramCarouselImageCache.request(for: url)
                } else {
                    var genericRequest = URLRequest(url: url)
                    genericRequest.timeoutInterval = 45
                    request = genericRequest
                }
                let (data, _) = try await URLSession.shared.data(for: request)
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
        // Synchronous memory cache check on first frame — eliminates flicker for cached images
        if let url = url {
            let cache = ThumbnailCacheService.shared
            let key = cache.cacheKey(for: url, stableKey: stableKey)
            if let cached = cache.cachedImage(for: key) {
                self._phase = State(initialValue: .success(Image(nsImage: cached)))
            }
        }
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

// MARK: - Instagram Carousel Image Cache

/// Shared local image cache for Instagram carousel slides.
///
/// Instagram CDN URLs are short-lived and often require browser-like headers. This
/// cache gives carousel display and OCR a stable local copy keyed by post shortcode
/// and slide index, so a later CDN URL rotation does not break already captured
/// swipes.
enum InstagramCarouselImageCache {
    private static let fileManager = FileManager.default

    private static var cacheDirectory: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Cosmo/ThumbnailCache", isDirectory: true)
    }

    static func cacheKey(shortcode: String?, index: Int, url: URL) -> String {
        if let shortcode, !shortcode.isEmpty {
            return "ig-carousel-\(shortcode)-\(index)"
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        let stable = components?.string ?? url.absoluteString
        let hash = SHA256.hash(data: Data(stable.utf8))
        let digest = hash.prefix(16).map { String(format: "%02x", $0) }.joined()
        return "ig-img-\(digest)"
    }

    static func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 45
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://www.instagram.com/", forHTTPHeaderField: "Referer")
        request.setValue(
            "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
        return request
    }

    static func shouldUseInstagramHeaders(for url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.contains("instagram.com") ||
            host.contains("cdninstagram.com") ||
            host.contains("fbcdn.net")
    }

    static func imageData(for url: URL, stableKey: String) async -> Data? {
        if url.isFileURL {
            return try? Data(contentsOf: url)
        }

        let path = cachePath(for: stableKey)
        if fileManager.fileExists(atPath: path.path),
           let cached = try? Data(contentsOf: path),
           NSImage(data: cached) != nil {
            return cached
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request(for: url))
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let image = NSImage(data: data) else {
                return nil
            }

            let persisted = jpegData(from: image) ?? data
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try? persisted.write(to: path)
            return persisted
        } catch {
            print("InstagramCarouselImageCache: Image download failed: \(error.localizedDescription)")
            return nil
        }
    }

    static func cachedFileURL(for stableKey: String) -> URL? {
        let path = cachePath(for: stableKey)
        guard fileManager.fileExists(atPath: path.path) else { return nil }
        return path
    }

    private static func cachePath(for stableKey: String) -> URL {
        cacheDirectory.appendingPathComponent("thumb-\(stableKey).jpg")
    }

    private static func jpegData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.88])
    }
}
