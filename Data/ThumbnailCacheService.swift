// CosmoOS/Data/ThumbnailCacheService.swift
// Persistent thumbnail cache with memory + disk layers.
// Replaces AsyncImage for swipe gallery thumbnails to ensure images
// load once and persist across app restarts.

import AppKit
import CryptoKit
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: - ThumbnailCacheService

actor ThumbnailCacheService {
    static let shared = ThumbnailCacheService()

    /// Cards render at ≤ ~272pt; 600px covers 2× retina with margin. Disk keeps
    /// full quality, so a future larger display size only changes this constant.
    nonisolated static let displayMaxPixelSize: CGFloat = 600

    private let memoryCache = NSCache<NSString, NSImage>()
    private var inflightTasks: [String: Task<NSImage?, Never>] = [:]

    private var cacheDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Cosmo/ThumbnailCache", isDirectory: true)
    }

    private init() {
        memoryCache.countLimit = 400
        // Decoded bitmaps are charged by pixel cost; without this the cache could
        // hold gigabytes of full-frame textures.
        memoryCache.totalCostLimit = 128 * 1024 * 1024
    }

    // MARK: - Downsampled decode

    /// Decode an image already sized for card display. Decoding happens here
    /// (ShouldCacheImmediately), never lazily on the render path.
    nonisolated static func downsampledImage(
        data: Data,
        maxPixelSize: CGFloat = ThumbnailCacheService.displayMaxPixelSize
    ) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        return downsample(from: source, maxPixelSize: maxPixelSize)
    }

    nonisolated static func downsampledImage(
        contentsOf url: URL,
        maxPixelSize: CGFloat = ThumbnailCacheService.displayMaxPixelSize
    ) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        if let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
           let image = downsample(from: source, maxPixelSize: maxPixelSize) {
            return image
        }
        // ImageIO's thumbnailer rejects some valid images (e.g. 1×1 JPEGs it
        // wrote itself) — fall back to a plain decode before giving up.
        guard let data = try? Data(contentsOf: url) else { return nil }
        return NSImage(data: data)
    }

    private nonisolated static func downsample(from source: CGImageSource, maxPixelSize: CGFloat) -> NSImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// Persist as JPEG without the NSImage→TIFF→bitmap roundtrip. Already-JPEG
    /// payloads are written as-is; other formats transcode straight from the source.
    private nonisolated static func writeJPEG(from source: CGImageSource, to url: URL, originalData: Data) {
        if let type = CGImageSourceGetType(source) as String?, type == UTType.jpeg.identifier {
            try? originalData.write(to: url)
            return
        }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        let options = [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary
        CGImageDestinationAddImageFromSource(destination, source, 0, options)
        CGImageDestinationFinalize(destination)
    }

    private nonisolated static func cacheCost(of image: NSImage) -> Int {
        let rep = image.representations.first
        let width = rep?.pixelsWide ?? Int(image.size.width)
        let height = rep?.pixelsHigh ?? Int(image.size.height)
        return max(width * height * 4, 1)
    }

    private func store(_ image: NSImage, forKey key: String) {
        memoryCache.setObject(image, forKey: key as NSString, cost: Self.cacheCost(of: image))
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

        // 2. Disk — decode downsampled, never at full resolution
        let diskPath = cacheDirectory.appendingPathComponent("thumb-\(key).jpg")
        if FileManager.default.fileExists(atPath: diskPath.path),
           let diskImage = Self.downsampledImage(contentsOf: diskPath) {
            store(diskImage, forKey: key)
            return diskImage
        }

        let fallbackImage = InstagramCarouselImageCache.fallbackImage(forStableKey: key)

        // 3. Deduplicated network fetch
        if let existing = inflightTasks[key] { return await existing.value }

        let dir = cacheDirectory
        let task = Task<NSImage?, Never> {
            do {
                let request: URLRequest
                if InstagramCarouselImageCache.shouldUseInstagramHeaders(for: url) {
                    request = InstagramCarouselImageCache.request(for: url)
                } else if let authorized = await MainActor.run(body: {
                    SupabaseClient.shared.flatMap { client in
                        client.isSupabaseHostedURL(url) ? client.authorizedRequest(for: url) : nil
                    }
                }) {
                    // Mirrored thumbnails live in a private storage bucket —
                    // fetch them with the client's own Bearer.
                    request = authorized
                } else {
                    var genericRequest = URLRequest(url: url)
                    genericRequest.timeoutInterval = 45
                    request = genericRequest
                }
                let (data, _) = try await URLSession.shared.data(for: request)
                let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
                guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
                      let image = Self.downsample(from: source, maxPixelSize: Self.displayMaxPixelSize) else {
                    return nil
                }

                // Persist full quality to disk; memory only ever holds the downsample
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                Self.writeJPEG(from: source, to: diskPath, originalData: data)

                await self.store(image, forKey: key)
                return image
            } catch {
                return nil
            }
        }
        inflightTasks[key] = task
        let result = await task.value
        inflightTasks.removeValue(forKey: key)
        if let result { return result }

        if let fallbackImage {
            store(fallbackImage, forKey: key)
            return fallbackImage
        }

        return nil
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

                if let fallback = InstagramCarouselImageCache.fallbackImage(forStableKey: key) {
                    phase = .success(Image(nsImage: fallback))
                }

                // Full lookup: disk then network
                if let image = await cache.image(for: url, key: key) {
                    phase = .success(Image(nsImage: image))
                } else if case .success = phase {
                    return
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

    static func displayURL(for item: CarouselItem, shortcode: String?) -> URL {
        let sourceURL = imageSourceURL(for: item)
        let key = stableKey(for: item, shortcode: shortcode)
        return cachedFileURL(for: key) ?? sourceURL
    }

    static func stableKey(for item: CarouselItem, shortcode: String?) -> String {
        cacheKey(shortcode: shortcode, index: item.index, url: imageSourceURL(for: item))
    }

    static func cacheCarouselImages(items: [CarouselItem], shortcode: String?) async -> Int {
        var cachedCount = 0

        for item in items {
            let sourceURL = imageSourceURL(for: item)
            let key = stableKey(for: item, shortcode: shortcode)
            if let data = await imageData(for: sourceURL, stableKey: key), !data.isEmpty {
                cachedCount += 1
            }
        }

        return cachedCount
    }

    static func imageData(for url: URL, stableKey: String) async -> Data? {
        if url.isFileURL {
            guard let data = try? Data(contentsOf: url),
                  let image = NSImage(data: data) else {
                return nil
            }
            return persistImage(image, originalData: data, stableKey: stableKey)
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

            return persistImage(image, originalData: data, stableKey: stableKey)
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

    static func fallbackImage(forStableKey stableKey: String) -> NSImage? {
        guard let fallbackURL = fallbackFileURL(forStableKey: stableKey) else { return nil }
        return ThumbnailCacheService.downsampledImage(contentsOf: fallbackURL)
    }

    private static func cachePath(for stableKey: String) -> URL {
        cacheDirectory.appendingPathComponent("thumb-\(stableKey).jpg")
    }

    private static func imageSourceURL(for item: CarouselItem) -> URL {
        if item.mediaType == .video {
            return item.thumbnailURL ?? item.mediaURL
        }
        return item.mediaURL
    }

    private static func fallbackFileURL(forStableKey stableKey: String) -> URL? {
        guard stableKey.hasPrefix("ig-carousel-") else { return nil }
        let remainder = stableKey.dropFirst("ig-carousel-".count)
        guard let separator = remainder.lastIndex(of: "-") else { return nil }
        guard remainder[remainder.index(after: separator)...] == "0" else { return nil }
        let shortcode = String(remainder[..<separator])
        guard !shortcode.isEmpty else { return nil }

        let legacyPath = cacheDirectory.appendingPathComponent("thumb-\(shortcode).jpg")
        guard fileManager.fileExists(atPath: legacyPath.path) else { return nil }
        return legacyPath
    }

    private static func persistImage(_ image: NSImage, originalData: Data, stableKey: String) -> Data? {
        let path = cachePath(for: stableKey)
        let persisted = jpegData(from: image) ?? originalData
        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try persisted.write(to: path)
            return persisted
        } catch {
            print("InstagramCarouselImageCache: Image cache write failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func jpegData(from image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let options = [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary
        CGImageDestinationAddImage(destination, cgImage, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
