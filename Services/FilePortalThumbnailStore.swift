// CosmoOS/Services/FilePortalThumbnailStore.swift
// Tier-0 of the file-portal render ladder: every portal always has a cheap
// bitmap skin — off-viewport blocks, mid-gesture frames, and formats without
// a live renderer all draw this. QuickLook Thumbnailing does the heavy
// lifting (it understands pdf/xlsx/docx/anything with a QL plugin); PDFKit
// first-page render is the fallback, the file's Finder icon the floor.
// Disk cache keyed attachmentUUID + thumbStamp + pixel bucket so re-imports
// invalidate and block resizes don't thrash the generator.

import AppKit
import Foundation
import PDFKit
import QuickLookThumbnailing

@MainActor
final class FilePortalThumbnailStore {
    static let shared = FilePortalThumbnailStore()

    /// Pixel-width buckets a request rounds up into — bounded variants per file.
    private static let pixelBuckets: [CGFloat] = [512, 1024, 2048]

    private let memoryCache = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    private init() {
        memoryCache.countLimit = 64
    }

    private var diskCacheDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Cosmo")
            .appendingPathComponent("FilePortalThumbs")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    // MARK: - Block-facing lookup

    /// Thumbnail for a portal block: memory → disk → generate. `cacheKey` is
    /// the attachment uuid; `stamp` invalidates on re-import. Returns nil only
    /// when the file itself is unreadable — callers show the unavailable state.
    func thumbnail(for fileURL: URL, cacheKey: String, stamp: String?, pixelWidth: CGFloat) async -> NSImage? {
        let bucket = Self.pixelBuckets.first { $0 >= pixelWidth } ?? Self.pixelBuckets.last!
        let key = "\(cacheKey)|\(stamp ?? "-")|\(Int(bucket))"

        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }
        if let existing = inFlight[key] {
            return await existing.value
        }

        let diskURL = diskCacheDirectory.appendingPathComponent(Self.diskFilename(for: key))
        let task = Task<NSImage?, Never> { [weak self] in
            if let onDisk = NSImage(contentsOf: diskURL) {
                return onDisk
            }
            guard let rendered = await Self.render(fileURL: fileURL, pixelWidth: bucket) else {
                return nil
            }
            if let png = Self.pngData(from: rendered) {
                try? png.write(to: diskURL, options: [.atomic])
            }
            _ = self
            return rendered
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image {
            memoryCache.setObject(image, forKey: key as NSString)
        }
        return image
    }

    // MARK: - Import-facing render

    /// One-shot JPEG for the attachment's synced `-thumb.jpg` mirror. JPEG to
    /// match AttachmentCloudStore's thumbnail contract (uploaded as image/jpeg).
    func renderThumbnailJPEG(for fileURL: URL, pixelWidth: CGFloat = 1024) async -> Data? {
        guard let image = await Self.render(fileURL: fileURL, pixelWidth: pixelWidth) else { return nil }
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.88])
    }

    // MARK: - Rendering ladder

    private static func render(fileURL: URL, pixelWidth: CGFloat) async -> NSImage? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        if let quickLook = await quickLookThumbnail(fileURL: fileURL, pixelWidth: pixelWidth) {
            return quickLook
        }
        if fileURL.pathExtension.lowercased() == "pdf",
           let firstPage = pdfFirstPageThumbnail(fileURL: fileURL, pixelWidth: pixelWidth) {
            return firstPage
        }
        // Floor: the Finder icon — always resolves, never blank.
        return NSWorkspace.shared.icon(forFile: fileURL.path)
    }

    private static func quickLookThumbnail(fileURL: URL, pixelWidth: CGFloat) async -> NSImage? {
        let scale: CGFloat = 2
        let pointSide = pixelWidth / scale
        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: CGSize(width: pointSide, height: pointSide),
            scale: scale,
            representationTypes: .thumbnail
        )
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return nil
        }
        return representation.nsImage
    }

    private static func pdfFirstPageThumbnail(fileURL: URL, pixelWidth: CGFloat) -> NSImage? {
        guard let document = PDFDocument(url: fileURL),
              let page = document.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0 else { return nil }
        let size = CGSize(width: pixelWidth, height: pixelWidth * (bounds.height / bounds.width))
        return page.thumbnail(of: size, for: .mediaBox)
    }

    // MARK: - Helpers

    private static func diskFilename(for key: String) -> String {
        // djb2 keeps filenames short and filesystem-safe regardless of key content.
        var hash: UInt64 = 5381
        for byte in key.utf8 {
            hash = (hash << 5) &+ hash &+ UInt64(byte)
        }
        return "\(hash).png"
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
