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

    /// Load an NSImage from a file path
    static func load(path: String) -> NSImage? {
        NSImage(contentsOfFile: path)
    }

    /// Delete an image file from disk
    static func delete(path: String) {
        try? FileManager.default.removeItem(atPath: path)
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
