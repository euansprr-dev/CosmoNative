// CosmoOS/Core/Components/LocalFileThumbnail.swift
// Async, downsampled thumbnail for local file paths.
//
// Replaces synchronous `NSImage(contentsOfFile:)` calls inside view bodies
// (inbox capture rows, ⌘K database browser, library grids). Those decoded
// full-resolution images on the main thread on every body re-evaluation —
// per-row disk IO + decode during list scrolling.
//
// Decode happens once per (path, size) off the main thread via
// ThumbnailCacheService.downsampledImage(contentsOf:maxPixelSize:); the result
// lands in a shared NSCache so every later body evaluation renders on frame 1.

import AppKit
import SwiftUI

struct LocalFileThumbnail<Content: View, Placeholder: View>: View {
    let path: String
    var maxPixelSize: CGFloat = ThumbnailCacheService.displayMaxPixelSize
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var loaded: NSImage?

    var body: some View {
        ZStack {
            if let image = loaded ?? LocalFileThumbnailCache.shared.object(forKey: cacheKey) {
                content(Image(nsImage: image))
            } else {
                placeholder()
                    .task(id: cacheKey) { await load() }
            }
        }
    }

    private var cacheKey: NSString {
        "\(path)#\(Int(maxPixelSize))" as NSString
    }

    private func load() async {
        let key = cacheKey
        if let hit = LocalFileThumbnailCache.shared.object(forKey: key) {
            loaded = hit
            return
        }
        let filePath = path
        let size = maxPixelSize
        let image = await Task.detached(priority: .userInitiated) {
            ThumbnailCacheService.downsampledImage(
                contentsOf: URL(fileURLWithPath: filePath),
                maxPixelSize: size
            )
        }.value
        guard let image, !Task.isCancelled else { return }
        LocalFileThumbnailCache.shared.setObject(
            image,
            forKey: key,
            cost: Int(image.size.width * image.size.height * 4)
        )
        loaded = image
    }
}

/// Shared memory cache for local-file thumbnails. Separate from
/// ThumbnailCacheService's actor-internal cache so hits stay synchronously
/// readable on the render path (NSCache is thread-safe).
enum LocalFileThumbnailCache {
    static let shared: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 600
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()
}
