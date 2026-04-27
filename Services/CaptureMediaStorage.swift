// CosmoOS/Services/CaptureMediaStorage.swift
// Local-first storage for Telegram capture media. Originals are preserved untouched.

import AppKit
import Foundation

struct StoredCaptureMedia: Sendable {
    let originalPath: String
    let thumbnailPath: String?
}

enum CaptureMediaStorageError: LocalizedError {
    case unableToCreateImage

    var errorDescription: String? {
        switch self {
        case .unableToCreateImage: return "Unable to create image thumbnail"
        }
    }
}

final class CaptureMediaStorage: @unchecked Sendable {
    static let shared = CaptureMediaStorage()

    private init() {}

    func store(
        data: Data,
        capturedItemId: String,
        attachmentId: String,
        originalFilename: String?,
        mimeType: String?,
        telegramFilePath: String?,
        kind: MediaAttachmentKind
    ) throws -> StoredCaptureMedia {
        let directory = try directoryURL(capturedItemId: capturedItemId)
        let ext = fileExtension(originalFilename: originalFilename, mimeType: mimeType, telegramFilePath: telegramFilePath, kind: kind)
        let originalURL = directory.appendingPathComponent("\(attachmentId).\(ext)")
        try data.write(to: originalURL, options: [.atomic])

        let thumbnailPath: String?
        if kind == .image || kind == .screenshot {
            thumbnailPath = try? writeThumbnail(data: data, directory: directory, attachmentId: attachmentId)
        } else {
            thumbnailPath = nil
        }

        return StoredCaptureMedia(originalPath: originalURL.path, thumbnailPath: thumbnailPath)
    }

    private func directoryURL(capturedItemId: String) throws -> URL {
        let calendar = Calendar.current
        let now = Date()
        let year = String(calendar.component(.year, from: now))
        let month = String(format: "%02d", calendar.component(.month, from: now))
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Cosmo")
            .appendingPathComponent("Captures")
            .appendingPathComponent(year)
            .appendingPathComponent(month)
            .appendingPathComponent(capturedItemId)

        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func fileExtension(
        originalFilename: String?,
        mimeType: String?,
        telegramFilePath: String?,
        kind: MediaAttachmentKind
    ) -> String {
        if let originalFilename, let ext = originalFilename.split(separator: ".").last, ext.count <= 8 {
            return String(ext).lowercased()
        }
        if let telegramFilePath, let ext = telegramFilePath.split(separator: ".").last, ext.count <= 8 {
            return String(ext).lowercased()
        }
        switch mimeType?.lowercased() {
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        case "image/heic": return "heic"
        case "application/pdf": return "pdf"
        case "text/markdown": return "md"
        case "text/plain": return "txt"
        case "audio/ogg": return "ogg"
        case "audio/mpeg": return "mp3"
        case "video/mp4": return "mp4"
        default:
            switch kind {
            case .image, .screenshot: return "jpg"
            case .pdf: return "pdf"
            case .markdown: return "md"
            case .textFile: return "txt"
            case .audio: return "ogg"
            case .video: return "mp4"
            default: return "bin"
            }
        }
    }

    private func writeThumbnail(data: Data, directory: URL, attachmentId: String) throws -> String {
        guard let image = NSImage(data: data) else {
            throw CaptureMediaStorageError.unableToCreateImage
        }
        let maxSide: CGFloat = 512
        let scale = min(maxSide / max(image.size.width, 1), maxSide / max(image.size.height, 1), 1)
        let targetSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1)
        thumbnail.unlockFocus()

        guard let tiff = thumbnail.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CaptureMediaStorageError.unableToCreateImage
        }

        let url = directory.appendingPathComponent("\(attachmentId)-thumb.png")
        try png.write(to: url, options: [.atomic])
        return url.path
    }
}
