// CosmoOS/Cosmo/ConnectionDiscoveryEngine.swift
// Graph-based connection discovery with semantic similarity
// Finds unexpected connections through graph traversal + embedding proximity

import Foundation
import Accelerate
import GRDB

/// Engine for discovering connections between entities through graph traversal and semantic similarity
/// Supports 2-hop transitive connections and semantic neighbor discovery
@MainActor
final class ConnectionDiscoveryEngine {
    static let shared = ConnectionDiscoveryEngine()

    // MARK: - Dependencies

    private let database = CosmoDatabase.shared
    private let mlxService = MLXEmbeddingService.shared
    private let semanticEngine = SemanticSearchEngine.shared

    // MARK: - Configuration

    /// Minimum similarity for semantic neighbors
    let minSemanticSimilarity: Float = 0.6

    /// Maximum connections to return
    let maxConnections = 20

    private init() {}

    // MARK: - Discovered Connection

    struct DiscoveredConnection: Sendable {
        let fromEntity: (type: EntityType, id: Int64, title: String)
        let toEntity: (type: EntityType, id: Int64, title: String)
        let connectionStrength: Double  // 0-1
        let connectionType: ConnectionType
        let explanation: String

        enum ConnectionType: String, Sendable {
            case directReference      // Explicit link in connections table
            case sharedProject        // Same project
            case semanticSimilarity   // High embedding similarity
            case sharedConcepts       // Overlapping keywords/concepts
            case transitiveLink       // A→B→C connection
            case sameCanvas           // On same canvas

            var description: String {
                switch self {
                case .directReference: return "Directly linked"
                case .sharedProject: return "Same project"
                case .semanticSimilarity: return "Semantically related"
                case .sharedConcepts: return "Shared concepts"
                case .transitiveLink: return "Connected through"
                case .sameCanvas: return "On same canvas"
                }
            }
        }
    }

    // MARK: - Discover Connections

    /// Find entities connected to the given entity
    /// - Parameters:
    ///   - entityType: Type of source entity
    ///   - entityId: ID of source entity
    ///   - depth: How many hops in graph (1 = direct, 2 = through intermediary)
    /// - Returns: Array of discovered connections sorted by strength
    func discoverConnections(
        for entityType: EntityType,
        entityId: Int64,
        depth: Int = 2
    ) async throws -> [DiscoveredConnection] {
        var discovered: [DiscoveredConnection] = []

        // Get source entity info
        let sourceInfo = try await getEntityInfo(type: entityType, id: entityId)
        guard let source = sourceInfo else {
            return []
        }

        print("🔗 Discovering connections for \(entityType.rawValue) '\(source.title)'")

        // 1. Direct references (explicit connections in database)
        let directRefs = try await findDirectReferences(
            entityType: entityType,
            entityId: entityId,
            sourceTitle: source.title
        )
        discovered.append(contentsOf: directRefs)

        // 2. Semantic neighbors (high embedding similarity)
        let semanticNeighbors = try await findSemanticNeighbors(
            entityType: entityType,
            entityId: entityId,
            sourceTitle: source.title
        )
        discovered.append(contentsOf: semanticNeighbors)

        // 3. Same project connections
        if let projectId = source.projectId {
            let projectConnections = try await findProjectConnections(
                projectId: projectId,
                excludeType: entityType,
                excludeId: entityId,
                sourceTitle: source.title
            )
            discovered.append(contentsOf: projectConnections)
        }

        // 4. Transitive connections (2-hop: A→B→C)
        if depth > 1 {
            let transitiveConnections = try await findTransitiveConnections(
                entityType: entityType,
                entityId: entityId,
                sourceTitle: source.title,
                depth: depth
            )
            discovered.append(contentsOf: transitiveConnections)
        }

        // 5. Same canvas connections
        let canvasConnections = try await findCanvasConnections(
            entityType: entityType,
            entityId: entityId,
            sourceTitle: source.title
        )
        discovered.append(contentsOf: canvasConnections)

        // Deduplicate and sort by strength
        let deduplicated = deduplicateConnections(discovered)
        let sorted = deduplicated.sorted { $0.connectionStrength > $1.connectionStrength }

        print("  ✅ Discovered \(sorted.count) connections")

        return Array(sorted.prefix(maxConnections))
    }

    /// Surface unexpected connections the user might not have noticed
    /// Finds high-similarity pairs that aren't explicitly linked
    func surfaceUnexpectedConnections(limit: Int = 3) async throws -> [DiscoveredConnection] {
        // Find high-similarity entity pairs that have no explicit connection
        let chunks = try await database.asyncRead { db in
            try SemanticChunk
                .order(Column("created_at").desc)
                .limit(200)  // Limit for performance
                .fetchAll(db)
        }

        var unexpectedPairs: [(chunk1: SemanticChunk, chunk2: SemanticChunk, similarity: Float)] = []

        // Compare chunks for high similarity
        for i in 0..<chunks.count {
            guard let vec1Data = chunks[i].vector,
                  let vec1 = decodeVector(vec1Data) else { continue }

            for j in (i+1)..<chunks.count {
                // Skip same entity
                if chunks[i].entityType == chunks[j].entityType &&
                   chunks[i].entityId == chunks[j].entityId {
                    continue
                }

                guard let vec2Data = chunks[j].vector,
                      let vec2 = decodeVector(vec2Data),
                      vec1.count == vec2.count else { continue }

                let similarity = cosineSimilarity(vec1, vec2)

                if similarity >= 0.7 {  // High similarity threshold
                    // Check if already explicitly connected
                    let isConnected = try await database.asyncRead { db in
                        try Atom
                            .filter(Column("type") == AtomType.connection.rawValue)
                            .filter(sql: """
                                (json_extract(metadata, '$.source_entity_type') = ? AND json_extract(metadata, '$.source_entity_id') = ? AND
                                 json_extract(metadata, '$.target_entity_type') = ? AND json_extract(metadata, '$.target_entity_id') = ?)
                                OR
                                (json_extract(metadata, '$.source_entity_type') = ? AND json_extract(metadata, '$.source_entity_id') = ? AND
                                 json_extract(metadata, '$.target_entity_type') = ? AND json_extract(metadata, '$.target_entity_id') = ?)
                                """, arguments: [
                                    chunks[i].entityType, chunks[i].entityId,
                                    chunks[j].entityType, chunks[j].entityId,
                                    chunks[j].entityType, chunks[j].entityId,
                                    chunks[i].entityType, chunks[i].entityId
                                ])
                            .fetchCount(db) > 0
                    }

                    if !isConnected {
                        unexpectedPairs.append((chunks[i], chunks[j], similarity))
                    }
                }
            }
        }

        // Sort by similarity and convert to DiscoveredConnection
        unexpectedPairs.sort { $0.similarity > $1.similarity }

        return unexpectedPairs.prefix(limit).compactMap { pair in
            let type1 = EntityType(rawValue: pair.chunk1.entityType) ?? .idea
            let type2 = EntityType(rawValue: pair.chunk2.entityType) ?? .idea

            return DiscoveredConnection(
                fromEntity: (type1, pair.chunk1.entityId, pair.chunk1.fieldName ?? "Untitled"),
                toEntity: (type2, pair.chunk2.entityId, pair.chunk2.fieldName ?? "Untitled"),
                connectionStrength: Double(pair.similarity),
                connectionType: .semanticSimilarity,
                explanation: "High semantic similarity (\(Int(pair.similarity * 100))%)"
            )
        }
    }

    // MARK: - Direct References

    private func findDirectReferences(
        entityType: EntityType,
        entityId: Int64,
        sourceTitle: String
    ) async throws -> [DiscoveredConnection] {
        // In CosmoOS, Connection is a Mental Model entity, not a graph edge.
        // References are stored in the referencesData JSON field.
        // We need to look for Connections that reference this entity.

        let connections = try await database.asyncRead { db in
            try Atom
                .filter(Column("type") == AtomType.connection.rawValue)
                .filter(Column("is_deleted") == false)
                .fetchAll(db)
                .map { ConnectionWrapper(atom: $0) }
        }

        var results: [DiscoveredConnection] = []

        for connection in connections {
            // Parse references from JSON
            let refs = connection.references

            // Check if this connection references our entity
            for ref in refs {
                if ref.entityType == entityType.rawValue && ref.entityId == entityId {
                    // This connection references our entity
                    // Add the Connection itself as a discovered connection
                    if let connectionId = connection.id {
                        let connectionTitle = connection.title ?? "Untitled"
                        results.append(DiscoveredConnection(
                            fromEntity: (entityType, entityId, sourceTitle),
                            toEntity: (.connection, connectionId, connectionTitle),
                            connectionStrength: 1.0,  // Direct links are highest strength
                            connectionType: .directReference,
                            explanation: "Referenced in '\(connectionTitle)'"
                        ))
                    }
                }
            }

            // Also check if this is a Connection we're looking for
            if entityType == .connection && connection.id == entityId {
                // Add all references as connections
                for ref in refs {
                    if let refEntityType = ref.entityType,
                       let type = EntityType(rawValue: refEntityType),
                       let refEntityId = ref.entityId {
                        results.append(DiscoveredConnection(
                            fromEntity: (entityType, entityId, sourceTitle),
                            toEntity: (type, refEntityId, ref.title),
                            connectionStrength: 1.0,
                            connectionType: .directReference,
                            explanation: "Referenced in connection"
                        ))
                    }
                }
            }
        }

        return results
    }

    // MARK: - Semantic Neighbors

    private func findSemanticNeighbors(
        entityType: EntityType,
        entityId: Int64,
        sourceTitle: String
    ) async throws -> [DiscoveredConnection] {
        // Get embedding for source entity
        let sourceChunks = try await database.asyncRead { db in
            try SemanticChunk
                .filter(Column("entity_type") == entityType.rawValue)
                .filter(Column("entity_id") == entityId)
                .fetchAll(db)
        }

        guard let firstChunk = sourceChunks.first,
              let sourceVectorData = firstChunk.vector,
              let sourceVector = decodeVector(sourceVectorData) else {
            return []
        }

        // Find similar chunks from other entities
        let allChunks = try await database.asyncRead { db in
            try SemanticChunk
                .filter(sql: "NOT (entity_type = ? AND entity_id = ?)",
                       arguments: [entityType.rawValue, entityId])
                .fetchAll(db)
        }

        var neighbors: [(type: EntityType, id: Int64, title: String, similarity: Float)] = []

        for chunk in allChunks {
            guard let vecData = chunk.vector,
                  let vec = decodeVector(vecData),
                  vec.count == sourceVector.count else { continue }

            let similarity = cosineSimilarity(sourceVector, vec)

            if similarity >= minSemanticSimilarity {
                if let type = EntityType(rawValue: chunk.entityType) {
                    neighbors.append((type, chunk.entityId, chunk.fieldName ?? "Untitled", similarity))
                }
            }
        }

        // Deduplicate by entity and keep highest similarity
        var seen: Set<String> = []
        var uniqueNeighbors: [(type: EntityType, id: Int64, title: String, similarity: Float)] = []

        neighbors.sort { $0.similarity > $1.similarity }

        for neighbor in neighbors {
            let key = "\(neighbor.type.rawValue)-\(neighbor.id)"
            if !seen.contains(key) {
                seen.insert(key)
                uniqueNeighbors.append(neighbor)
            }
        }

        // Get actual entity titles
        var results: [DiscoveredConnection] = []

        for neighbor in uniqueNeighbors.prefix(10) {
            if let info = try await getEntityInfo(type: neighbor.type, id: neighbor.id) {
                results.append(DiscoveredConnection(
                    fromEntity: (entityType, entityId, sourceTitle),
                    toEntity: (neighbor.type, neighbor.id, info.title),
                    connectionStrength: Double(neighbor.similarity),
                    connectionType: .semanticSimilarity,
                    explanation: "Semantically similar (\(Int(neighbor.similarity * 100))%)"
                ))
            }
        }

        return results
    }

    // MARK: - Project Connections

    private func findProjectConnections(
        projectId: Int64,
        excludeType: EntityType,
        excludeId: Int64,
        sourceTitle: String
    ) async throws -> [DiscoveredConnection] {
        // Find other entities in the same project
        var results: [DiscoveredConnection] = []

        // Ideas in same project - use Atom query
        let ideas = try await database.asyncRead { db in
            try Atom
                .filter(Column("type") == AtomType.idea.rawValue)
                .filter(Column("is_deleted") == false)
                .limit(10)
                .fetchAll(db)
                .map { IdeaWrapper(atom: $0) }
                .filter { $0.projectId == projectId && !(excludeType == .idea && $0.id == excludeId) }
        }

        for idea in ideas {
            guard let id = idea.id else { continue }
            results.append(DiscoveredConnection(
                fromEntity: (excludeType, excludeId, sourceTitle),
                toEntity: (.idea, id, idea.title ?? "Untitled"),
                connectionStrength: 0.7,  // Project connections are medium-high
                connectionType: .sharedProject,
                explanation: "In the same project"
            ))
        }

        return results
    }

    // MARK: - Transitive Connections

    private func findTransitiveConnections(
        entityType: EntityType,
        entityId: Int64,
        sourceTitle: String,
        depth: Int
    ) async throws -> [DiscoveredConnection] {
        // Since Connection uses JSON references (not graph edges), we build transitive
        // connections by finding Connections that share references with our entity

        // First get all connections that reference our entity (1-hop)
        let oneHopConnections = try await findDirectReferences(
            entityType: entityType,
            entityId: entityId,
            sourceTitle: sourceTitle
        )

        guard depth > 1 else { return [] }

        var results: [DiscoveredConnection] = []
        var seen: Set<String> = ["\(entityType.rawValue)-\(entityId)"]

        // For each 1-hop connection, find their references (2-hop)
        for oneHop in oneHopConnections {
            let key = "\(oneHop.toEntity.type.rawValue)-\(oneHop.toEntity.id)"
            if seen.contains(key) { continue }
            seen.insert(key)

            // Get the Connection's other references
            if oneHop.toEntity.type == .connection {
                let connection = try await database.asyncRead { db in
                    try Atom
                        .filter(Column("type") == AtomType.connection.rawValue)
                        .filter(Column("id") == oneHop.toEntity.id)
                        .fetchOne(db)
                        .map { ConnectionWrapper(atom: $0) }
                }

                if let conn = connection {
                    let connTitle = conn.title ?? "Untitled"
                    for ref in conn.references {
                        guard let refEntityType = ref.entityType,
                              let refEntityId = ref.entityId else { continue }
                        let refKey = "\(refEntityType)-\(refEntityId)"
                        if seen.contains(refKey) { continue }
                        seen.insert(refKey)

                        if let type = EntityType(rawValue: refEntityType) {
                            results.append(DiscoveredConnection(
                                fromEntity: (entityType, entityId, sourceTitle),
                                toEntity: (type, refEntityId, ref.title),
                                connectionStrength: 0.5,  // 2-hop is weaker
                                connectionType: .transitiveLink,
                                explanation: "2-hop via '\(connTitle)'"
                            ))
                        }
                    }
                }
            }
        }

        return results
    }

    // MARK: - Canvas Connections

    private func findCanvasConnections(
        entityType: EntityType,
        entityId: Int64,
        sourceTitle: String
    ) async throws -> [DiscoveredConnection] {
        // Find other blocks on the same canvas near this entity
        let nearbyBlocks = try await database.asyncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT b2.entity_type, b2.entity_id, b2.entity_title,
                       ABS(b1.position_x - b2.position_x) + ABS(b1.position_y - b2.position_y) AS distance
                FROM canvas_blocks b1
                JOIN canvas_blocks b2 ON b1.uuid != b2.uuid AND b1.is_deleted = 0 AND b2.is_deleted = 0
                WHERE b1.entity_type = ? AND b1.entity_uuid IN (
                    SELECT uuid FROM ideas WHERE id = ?
                    UNION SELECT uuid FROM tasks WHERE id = ?
                    UNION SELECT uuid FROM content WHERE id = ?
                )
                ORDER BY distance
                LIMIT 5
                """, arguments: [entityType.rawValue, entityId, entityId, entityId])
        }

        var results: [DiscoveredConnection] = []

        for row in nearbyBlocks {
            guard let typeStr = row["entity_type"] as? String,
                  let title = row["entity_title"] as? String,
                  let type = EntityType(rawValue: typeStr) else { continue }

            // Canvas proximity is weak connection
            results.append(DiscoveredConnection(
                fromEntity: (entityType, entityId, sourceTitle),
                toEntity: (type, 0, title),  // ID not directly available from blocks
                connectionStrength: 0.4,
                connectionType: .sameCanvas,
                explanation: "Placed near each other on canvas"
            ))
        }

        return results
    }

    // MARK: - Helper Methods

    private struct EntityInfo {
        let title: String
        let projectId: Int64?
    }

    private func getEntityInfo(type: EntityType, id: Int64) async throws -> EntityInfo? {
        switch type {
        case .idea:
            let idea = try await database.asyncRead { db in
                try Atom
                    .filter(Column("type") == AtomType.idea.rawValue)
                    .filter(Column("id") == id)
                    .fetchOne(db)
                    .map { IdeaWrapper(atom: $0) }
            }
            return idea.map { EntityInfo(title: $0.title ?? "Untitled", projectId: $0.projectId) }

        case .task:
            let task = try await database.asyncRead { db in
                try Atom
                    .filter(Column("type") == AtomType.task.rawValue)
                    .filter(Column("id") == id)
                    .fetchOne(db)
                    .map { TaskWrapper(atom: $0) }
            }
            return task.map { EntityInfo(title: $0.title ?? "Untitled", projectId: $0.projectId) }

        case .content:
            let content = try await database.asyncRead { db in
                try Atom
                    .filter(Column("type") == AtomType.content.rawValue)
                    .filter(Column("id") == id)
                    .fetchOne(db)
                    .map { ContentWrapper(atom: $0) }
            }
            return content.map { EntityInfo(title: $0.title ?? "Untitled", projectId: $0.projectId) }

        case .research:
            let research = try await database.asyncRead { db in
                try Atom
                    .filter(Column("type") == AtomType.research.rawValue)
                    .filter(Column("id") == id)
                    .fetchOne(db)
                    .map { ResearchWrapper(atom: $0) }
            }
            return research.map { EntityInfo(title: $0.title ?? "Untitled", projectId: nil) }

        case .connection:
            let connection = try await database.asyncRead { db in
                try Atom
                    .filter(Column("type") == AtomType.connection.rawValue)
                    .filter(Column("id") == id)
                    .fetchOne(db)
                    .map { ConnectionWrapper(atom: $0) }
            }
            return connection.map { EntityInfo(title: $0.title ?? "Untitled", projectId: nil) }

        default:
            return nil
        }
    }

    private func deduplicateConnections(_ connections: [DiscoveredConnection]) -> [DiscoveredConnection] {
        var seen: Set<String> = []
        var unique: [DiscoveredConnection] = []

        for conn in connections {
            let key = "\(conn.toEntity.type.rawValue)-\(conn.toEntity.id)"
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(conn)
            }
        }

        return unique
    }

    // MARK: - Vector Utilities

    private func decodeVector(_ data: Data) -> [Float]? {
        let floatSize = MemoryLayout<Float>.size
        let elementCount = data.count / floatSize

        guard [384, 768, 1024].contains(elementCount) else {
            return nil
        }

        return data.withUnsafeBytes { bytes in
            Array(bytes.bindMemory(to: Float.self))
        }
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        vDSP_dotpr(a, 1, a, 1, &normA, vDSP_Length(a.count))
        vDSP_dotpr(b, 1, b, 1, &normB, vDSP_Length(b.count))

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }

        return dotProduct / denominator
    }
}
