import Foundation
import GRDB
import CryptoKit

/// A canvas chat has a stable UUID even when it has no backing atom.
/// Canvas and focus mode share this transcript and merge messages by ID so
/// one mounted surface cannot truncate turns saved by another.
@MainActor
enum CanvasChatArchive {
    private static func key(_ uuid: String) -> String { "cosmoCanvas.messageArchive." + uuid }

    static func load(entityUUID: String) throws -> [CosmoWindowMessage] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let local: [CosmoWindowMessage]
        if let data = try LocalDocumentArchive.load(key: key(entityUUID)) {
            local = try decoder.decode([CosmoWindowMessage].self, from: data)
        } else { local = [] }
        let legacy: [CosmoWindowMessage] = try CosmoDatabase.shared.read { db in
            if let atom = try Atom.filter(Column("uuid") == entityUUID).fetchOne(db),
               let structured = atom.structured {
                let object = try JSONSerialization.jsonObject(with: Data(structured.utf8)) as? [String: Any]
                if let archive = object?["canvasMessageArchive"] {
                    return try decoder.decode([CosmoWindowMessage].self,
                        from: JSONSerialization.data(withJSONObject: archive))
                }
                if let messages = object?["messages"] as? [[String: Any]] {
                    return messages.enumerated().compactMap { (index, entry) -> CosmoWindowMessage? in
                        guard let role = entry["type"] as? String, let content = entry["content"] as? String else { return nil }
                        let type: CosmoWindowMessageType
                        switch role {
                        case "user": type = .user
                        case "assistant": type = .assistant
                        case "system": type = .system
                        default: return nil
                        }
                        let timestamp = entry["timestamp"] as? Double ?? 0
                        // Legacy transcripts had no message IDs. Derive them
                        // consistently so repeated imports cannot duplicate turns.
                        let digest = SHA256.hash(data: Data("\(entityUUID)|\(index)|\(role)|\(timestamp)|\(content)".utf8))
                        let bytes = Array(digest.prefix(16))
                        let id = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                                                 bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
                        return CosmoWindowMessage(id: id, type: type, content: content,
                            timestamp: Date(timeIntervalSince1970: timestamp))
                    }
                }
            }
            guard local.isEmpty else { return [] }
            // Old atomless blocks failed to save their preview transcript,
            // but the agent-memory conversation may still hold the turns.
            let rows = try Atom.fetchAll(db, sql: """
                SELECT * FROM atoms WHERE is_deleted = 0 AND type = 'system_event'
                AND json_extract(metadata, '$.subtype') = 'agent_conversation'
                AND json_extract(metadata, '$.conversationId') IN (?, ?)
                ORDER BY updated_at DESC
                """, arguments: ["cosmo-ai-block-" + entityUUID, "cosmo-ai-focus-" + entityUUID])
            guard let body = rows.first?.body else { return [] }
            return try decoder.decode([AgentMessage].self, from: Data(body.utf8)).compactMap { message in
                let type: CosmoWindowMessageType
                switch message.role {
                case .user: type = .user
                case .assistant: type = .assistant
                case .system: type = .system
                case .tool: return nil
                }
                guard !message.content.isEmpty else { return nil }
                return CosmoWindowMessage(type: type, content: message.content, timestamp: message.timestamp)
            }
        }
        let localIDs = Set(local.map(\.id))
        let merged = local + legacy.filter { !localIDs.contains($0.id) }
        if local.isEmpty, !merged.isEmpty {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try LocalDocumentArchive.save(key: key(entityUUID), data: encoder.encode(merged))
        }
        return merged
    }

    static func save(_ messages: [CosmoWindowMessage], entityUUID: String) throws {
        let incoming = messages.filter { message in
            switch message.type {
            case .user, .assistant, .system: return true
            default: return false
            }
        }
        // Loading also validates the prior archive: a decoding failure leaves
        // its bytes untouched instead of replacing them with a partial chat.
        var merged = try load(entityUUID: entityUUID)
        for message in incoming {
            if let index = merged.firstIndex(where: { $0.id == message.id }) {
                merged[index] = message
            } else {
                merged.append(message)
            }
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(merged)
        try CosmoDatabase.shared.write { db in
            try LocalDocumentArchive.save(in: db, key: key(entityUUID), data: data)
            // Retain the existing sync behavior of atom-backed chats. Read the
            // current row inside this transaction so unrelated fields survive.
            if let atom = try Atom.filter(Column("uuid") == entityUUID && Column("is_deleted") == false).fetchOne(db) {
                var structured: [String: Any] = [:]
                if let raw = atom.structured {
                    guard let object = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] else {
                        throw CocoaError(.coderReadCorrupt)
                    }
                    structured = object
                }
                structured["canvasMessageArchive"] = try JSONSerialization.jsonObject(with: data)
                // Older clients still read this field.
                structured["messages"] = merged.map { message in
                    let role: String
                    switch message.type {
                    case .user: role = "user"
                    case .assistant: role = "assistant"
                    default: role = "system"
                    }
                    return ["type": role,
                     "content": message.content, "timestamp": message.timestamp.timeIntervalSince1970] as [String: Any]
                }
                let json = try JSONSerialization.data(withJSONObject: structured)
                try db.execute(sql: """
                    UPDATE atoms SET structured = ?, updated_at = ?,
                        _local_version = _local_version + 1, _local_pending = 1
                    WHERE uuid = ? AND is_deleted = 0
                    """, arguments: [String(decoding: json, as: UTF8.self), ISO8601.string(from: Date()), entityUUID])
            }
        }
    }
}
