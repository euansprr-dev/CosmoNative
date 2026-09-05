import Foundation
import GRDB

/// Local chat transcripts belong with the database's transactions and backups,
/// not in preferences. Legacy values are copied lazily and left recoverable.
@MainActor
enum LocalDocumentArchive {
    static func load(key: String, defaults: UserDefaults = .standard) throws -> Data? {
        try CosmoDatabase.shared.write { db in
            if let data = try Data.fetchOne(db,
                sql: "SELECT data FROM local_document_archives WHERE key = ?", arguments: [key]) {
                return data
            }
            guard let legacy = defaults.data(forKey: key) else { return nil }
            try save(in: db, key: key, data: legacy)
            return legacy
        }
    }

    static func save(key: String, data: Data) throws {
        try CosmoDatabase.shared.write { db in try save(in: db, key: key, data: data) }
    }

    nonisolated static func save(in db: Database, key: String, data: Data) throws {
        try db.execute(sql: """
            INSERT INTO local_document_archives (key, data, updated_at) VALUES (?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET previous_data = data,
                data = excluded.data, updated_at = excluded.updated_at
            WHERE data != excluded.data
            """, arguments: [key, data, ISO8601.string(from: Date())])
    }

    static func delete(key: String, defaults: UserDefaults = .standard) throws {
        try CosmoDatabase.shared.write { db in
            try db.execute(sql: "DELETE FROM local_document_archives WHERE key = ?", arguments: [key])
        }
        defaults.removeObject(forKey: key)
    }
}
