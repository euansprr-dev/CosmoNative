// CosmoOS/Data/CatalogStore.swift
// File-based catalog persistence — stores imported creator post catalogs on disk
// at ~/Library/Application Support/Cosmo/catalogs/{creatorUUID}.json

import Foundation

enum CatalogStore {

    /// Directory where catalog JSON files are stored
    private static var catalogsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Cosmo/catalogs", isDirectory: true)
    }

    /// Save an array of imported posts to disk for a creator
    static func save(posts: [ImportedPost], forCreator creatorUUID: String) throws {
        try FileManager.default.createDirectory(at: catalogsDirectory, withIntermediateDirectories: true)

        let fileURL = catalogsDirectory.appendingPathComponent("\(creatorUUID).json")
        let data = try JSONEncoder().encode(posts)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Load a cached catalog from disk, returns nil if not found or corrupted
    static func load(creatorUUID: String) -> [ImportedPost]? {
        let fileURL = catalogsDirectory.appendingPathComponent("\(creatorUUID).json")
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode([ImportedPost].self, from: data)
    }

    /// Delete a cached catalog from disk
    static func delete(creatorUUID: String) {
        let fileURL = catalogsDirectory.appendingPathComponent("\(creatorUUID).json")
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Check whether a cached catalog exists for this creator
    static func exists(creatorUUID: String) -> Bool {
        let fileURL = catalogsDirectory.appendingPathComponent("\(creatorUUID).json")
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
}
