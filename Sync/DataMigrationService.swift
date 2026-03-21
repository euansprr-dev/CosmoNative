// CosmoOS/Sync/DataMigrationService.swift
// One-time migration of local GRDB data to Supabase Postgres
// Runs after user authenticates with Supabase Auth for the first time

import Foundation
import GRDB

@MainActor
final class DataMigrationService {
    static let shared = DataMigrationService()

    private let database = CosmoDatabase.shared
    private let batchSize = 100

    // UserDefaults key to track migration state
    private let migrationCompleteKey = "supabase_data_migration_complete"
    private let migrationProgressKey = "supabase_migration_progress"

    var isMigrationComplete: Bool {
        UserDefaults.standard.bool(forKey: migrationCompleteKey)
    }

    var migrationProgress: MigrationProgress {
        guard let data = UserDefaults.standard.data(forKey: migrationProgressKey),
              let progress = try? JSONDecoder().decode(MigrationProgress.self, from: data) else {
            return MigrationProgress()
        }
        return progress
    }

    private init() {}

    // MARK: - Main Migration

    /// Migrate all local atoms, graph edges, and canvas blocks to Supabase.
    /// Idempotent — safe to call multiple times (uses upsert).
    func migrateToSupabase(
        onProgress: @escaping (String, Int, Int) -> Void
    ) async throws {
        guard let client = SupabaseClient.shared else {
            throw DataMigrationError.noSupabaseClient
        }

        guard let userId = APIKeys.supabaseUserId else {
            throw DataMigrationError.noAuthToken
        }

        var progress = migrationProgress

        // Step 1: Migrate atoms
        if !progress.atomsComplete {
            try await migrateAtoms(client: client, userId: userId, onProgress: onProgress)
            progress.atomsComplete = true
            saveProgress(progress)
        }

        // Step 2: Migrate graph edges
        if !progress.edgesComplete {
            try await migrateGraphEdges(client: client, userId: userId, onProgress: onProgress)
            progress.edgesComplete = true
            saveProgress(progress)
        }

        // Step 3: Migrate canvas blocks
        if !progress.canvasComplete {
            try await migrateCanvasBlocks(client: client, userId: userId, onProgress: onProgress)
            progress.canvasComplete = true
            saveProgress(progress)
        }

        // Step 4: Mark all local atoms as synced
        try await markAllSynced()

        // Done
        UserDefaults.standard.set(true, forKey: migrationCompleteKey)
        onProgress("Migration complete", 100, 100)
    }

    // MARK: - Atoms Migration

    private func migrateAtoms(
        client: SupabaseClient,
        userId: String,
        onProgress: @escaping (String, Int, Int) -> Void
    ) async throws {
        // Count total atoms
        let totalCount = try await database.asyncRead { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM atoms WHERE is_deleted = 0") ?? 0
        }

        onProgress("Migrating atoms...", 0, totalCount)

        var offset = 0
        while true {
            // Fetch batch of atoms
            let atoms = try await database.asyncRead { db in
                try Row.fetchAll(db, sql: """
                    SELECT uuid, type, title, body, structured, metadata, links,
                           created_at, updated_at, is_deleted, _local_version
                    FROM atoms
                    WHERE is_deleted = 0
                    ORDER BY created_at ASC
                    LIMIT ? OFFSET ?
                """, arguments: [self.batchSize, offset])
            }

            if atoms.isEmpty { break }

            // Batch convert and upsert
            let payloads = atoms.map { atomRowToSupabasePayload(row: $0, userId: userId) }

            do {
                try await client.batchUpsert(table: "atoms", records: payloads, onConflict: "uuid")
            } catch {
                print("❌ Migration batch failed at offset \(offset): \(error)")
                // Try individual upserts as fallback to identify the problematic row
                for (i, payload) in payloads.enumerated() {
                    do {
                        try await client.upsert(table: "atoms", data: payload, onConflict: "uuid")
                    } catch {
                        let uuid = payload["uuid"] as? String ?? "unknown"
                        print("❌ Failed to upsert atom \(uuid): \(error)")
                        // Skip this atom and continue
                    }
                }
            }

            offset += atoms.count
            onProgress("Migrating atoms...", offset, totalCount)
        }
    }

    // MARK: - Graph Edges Migration

    private func migrateGraphEdges(
        client: SupabaseClient,
        userId: String,
        onProgress: @escaping (String, Int, Int) -> Void
    ) async throws {
        let totalCount = try await database.asyncRead { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM graph_edges") ?? 0
        }

        onProgress("Migrating graph edges...", 0, totalCount)

        var offset = 0
        while true {
            let edges = try await database.asyncRead { db in
                try Row.fetchAll(db, sql: """
                    SELECT source_uuid, target_uuid, edge_type, link_type,
                           is_directed, structural_weight, semantic_weight,
                           recency_weight, usage_weight, combined_weight,
                           created_at, updated_at
                    FROM graph_edges
                    ORDER BY created_at ASC
                    LIMIT ? OFFSET ?
                """, arguments: [self.batchSize, offset])
            }

            if edges.isEmpty { break }

            let payloads = edges.map { edgeRowToSupabasePayload(row: $0, userId: userId) }
            do {
                try await client.batchUpsert(table: "graph_edges", records: payloads, onConflict: "source_uuid,target_uuid,edge_type,user_id")
            } catch {
                print("❌ Edge migration batch failed at offset \(offset): \(error)")
            }

            offset += edges.count
            onProgress("Migrating graph edges...", offset, totalCount)
        }
    }

    // MARK: - Canvas Blocks Migration

    private func migrateCanvasBlocks(
        client: SupabaseClient,
        userId: String,
        onProgress: @escaping (String, Int, Int) -> Void
    ) async throws {
        let totalCount = try await database.asyncRead { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM canvas_blocks WHERE is_deleted = 0") ?? 0
        }

        onProgress("Migrating canvas blocks...", 0, totalCount)

        var offset = 0
        while true {
            let blocks = try await database.asyncRead { db in
                try Row.fetchAll(db, sql: """
                    SELECT id, uuid, document_type, document_id, document_uuid,
                           entity_id, entity_uuid, entity_type, entity_title,
                           position_x, position_y, width, height,
                           is_collapsed, zone, note_content, z_index,
                           created_at, updated_at, is_deleted, thinkspace_id, is_pinned
                    FROM canvas_blocks
                    WHERE is_deleted = 0
                    ORDER BY created_at ASC
                    LIMIT ? OFFSET ?
                """, arguments: [self.batchSize, offset])
            }

            if blocks.isEmpty { break }

            let payloads = blocks.map { canvasBlockRowToSupabasePayload(row: $0, userId: userId) }
            do {
                try await client.batchUpsert(table: "canvas_blocks", records: payloads, onConflict: "uuid")
            } catch {
                print("❌ Canvas migration batch failed at offset \(offset): \(error)")
            }

            offset += blocks.count
            onProgress("Migrating canvas blocks...", offset, totalCount)
        }
    }

    // MARK: - Mark All Synced

    private func markAllSynced() async throws {
        try await database.asyncWrite { db in
            try db.execute(sql: """
                UPDATE atoms SET
                    _server_version = _local_version,
                    _local_pending = 0
                WHERE is_deleted = 0
            """)
        }
    }

    // MARK: - Row Converters

    /// All payloads MUST have identical keys for PostgREST batch upsert (PGRST102).
    /// Use NSNull() for missing values instead of omitting keys.
    private func atomRowToSupabasePayload(row: Row, userId: String) -> [String: Any] {
        let structured: Any = {
            if let s = row["structured"] as? String, !s.isEmpty { return parseJSONString(s) }
            return NSNull()
        }()
        let metadata: Any = {
            if let m = row["metadata"] as? String, !m.isEmpty { return parseJSONString(m) }
            return NSNull()
        }()
        let links: Any = {
            if let l = row["links"] as? String, !l.isEmpty { return parseJSONString(l) }
            return NSNull()
        }()

        return [
            "uuid": row["uuid"] as? String ?? "",
            "type": row["type"] as? String ?? "",
            "title": (row["title"] as? String) ?? NSNull(),
            "body": (row["body"] as? String) ?? NSNull(),
            "structured": structured,
            "metadata": metadata,
            "links": links,
            "created_at": row["created_at"] as? String ?? ISO8601DateFormatter().string(from: Date()),
            "updated_at": row["updated_at"] as? String ?? ISO8601DateFormatter().string(from: Date()),
            "is_deleted": false,
            "user_id": userId,
            "_version": row["_local_version"] as? Int ?? 1,
            "_source": "mac",
        ] as [String: Any]
    }

    private func edgeRowToSupabasePayload(row: Row, userId: String) -> [String: Any] {
        var payload: [String: Any] = [
            "source_uuid": row["source_uuid"] as? String ?? "",
            "target_uuid": row["target_uuid"] as? String ?? "",
            "edge_type": row["edge_type"] as? String ?? "",
            "user_id": userId,
            "is_directed": (row["is_directed"] as? Int ?? 1) == 1,
            "structural_weight": row["structural_weight"] as? Double ?? 0,
            "semantic_weight": row["semantic_weight"] as? Double ?? 0,
            "recency_weight": row["recency_weight"] as? Double ?? 1.0,
            "usage_weight": row["usage_weight"] as? Double ?? 0,
            "combined_weight": row["combined_weight"] as? Double ?? 0,
        ]

        payload["link_type"] = (row["link_type"] as? String) ?? NSNull()
        payload["created_at"] = row["created_at"] as? String ?? ISO8601DateFormatter().string(from: Date())
        payload["updated_at"] = row["updated_at"] as? String ?? ISO8601DateFormatter().string(from: Date())

        return payload
    }

    /// All payloads MUST have identical keys for PostgREST batch upsert (PGRST102).
    private func canvasBlockRowToSupabasePayload(row: Row, userId: String) -> [String: Any] {
        let uuid = (row["uuid"] as? String) ?? (row["id"] as? String) ?? UUID().uuidString

        return [
            "uuid": uuid,
            "atom_uuid": row["entity_uuid"] as? String ?? "",
            "thinkspace_id": (row["thinkspace_id"] as? String) ?? NSNull(),
            "position_x": row["position_x"] as? Int ?? 0,
            "position_y": row["position_y"] as? Int ?? 0,
            "width": row["width"] as? Int ?? 320,
            "height": row["height"] as? Int ?? 340,
            "z_index": row["z_index"] as? Int ?? 0,
            "is_collapsed": (row["is_collapsed"] as? Int ?? 0) == 1,
            "is_pinned": (row["is_pinned"] as? Int ?? 0) == 1,
            "document_type": (row["document_type"] as? String) ?? NSNull(),
            "document_id": (row["document_id"] as? Int) ?? NSNull(),
            "document_uuid": (row["document_uuid"] as? String) ?? NSNull(),
            "entity_id": (row["entity_id"] as? Int) ?? NSNull(),
            "entity_uuid": (row["entity_uuid"] as? String) ?? NSNull(),
            "entity_type": (row["entity_type"] as? String) ?? NSNull(),
            "entity_title": (row["entity_title"] as? String) ?? NSNull(),
            "zone": (row["zone"] as? String) ?? NSNull(),
            "note_content": (row["note_content"] as? String) ?? NSNull(),
            "is_deleted": false,
            "user_id": userId,
            "created_at": row["created_at"] as? String ?? ISO8601DateFormatter().string(from: Date()),
            "updated_at": row["updated_at"] as? String ?? ISO8601DateFormatter().string(from: Date()),
        ] as [String: Any]
    }

    // MARK: - JSON Helpers

    /// Parse a JSON string into a native object for JSONB insertion.
    /// Returns the string as-is if parsing fails (Supabase will store as text).
    private func parseJSONString(_ jsonString: String) -> Any {
        guard let data = jsonString.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) else {
            return jsonString
        }
        return parsed
    }

    // MARK: - Progress Tracking

    private func saveProgress(_ progress: MigrationProgress) {
        if let data = try? JSONEncoder().encode(progress) {
            UserDefaults.standard.set(data, forKey: migrationProgressKey)
        }
    }

    /// Reset migration state (for re-migration after data issues)
    func resetMigration() {
        UserDefaults.standard.removeObject(forKey: migrationCompleteKey)
        UserDefaults.standard.removeObject(forKey: migrationProgressKey)
    }
}

// MARK: - Supporting Types

struct MigrationProgress: Codable {
    var atomsComplete: Bool = false
    var edgesComplete: Bool = false
    var canvasComplete: Bool = false
}

enum DataMigrationError: LocalizedError {
    case noSupabaseClient
    case noAuthToken
    case migrationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noSupabaseClient: return "Supabase client not initialized"
        case .noAuthToken: return "Not authenticated with Supabase"
        case .migrationFailed(let reason): return "Migration failed: \(reason)"
        }
    }
}
