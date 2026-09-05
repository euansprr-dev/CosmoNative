import Foundation
#if os(iOS)
import CosmoCoreKit
#endif

/// A portable, human-readable conversation. Executable tool calls and pending
/// edits deliberately stay in their original host; importing never replays work.
struct CompanionConversationRecord: Codable, Identifiable, Equatable {
    struct Message: Codable, Identifiable, Equatable {
        let id: String
        let role: String
        let text: String
        let createdAt: Date
    }
    var schemaVersion = 1
    let id: String
    let origin: String
    let title: String
    var messages: [Message]
    var updatedAt: Date

    func merging(_ other: Self) -> Self {
        guard id == other.id else { return self }
        var merged = self
        var byID = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for message in other.messages where !message.text.isEmpty { byID[message.id] = message }
        merged.messages = byID.values.sorted {
            $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt
        }
        merged.updatedAt = max(updatedAt, other.updatedAt)
        return merged
    }
}

enum CompanionConversationExchangeError: LocalizedError {
    case unreadable
    var errorDescription: String? { "The saved conversation could not be read. Its original has been kept." }
}

/// The shared library carries portable snapshots through existing atom sync.
/// Native archives remain authoritative. Each continuation creates a new native
/// conversation, preserving its source and all original review receipts.
@MainActor enum CompanionConversationExchange {
    static let subtype = "companion_conversation"
    static var localOriginID: String {
        let key = "companion.assistant.originID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let value = UUID().uuidString
        UserDefaults.standard.set(value, forKey: key)
        return value
    }

    static func load(repository: AtomRepository = .shared) async throws -> [CompanionConversationRecord] {
        let atoms = try await repository.fetchAll(type: .systemEvent)
        var records: [String: CompanionConversationRecord] = [:]
        for atom in atoms where fields(atom.metadata)["subtype"] as? String == subtype {
            guard let record = decode(atom.body), record.schemaVersion == 1 else { continue }
            records[record.id] = records[record.id].map { $0.merging(record) } ?? record
        }
        return records.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    static func save(_ record: CompanionConversationRecord, repository: AtomRepository = .shared) async throws {
        guard !record.messages.isEmpty else { return }
        let atoms = try await repository.fetchAll(type: .systemEvent)
        let existing = atoms.first {
            let metadata = fields($0.metadata)
            return metadata["subtype"] as? String == subtype && metadata["conversationId"] as? String == record.id
        }
        var final = record
        if let existing {
            guard let previous = decode(existing.body), previous.schemaVersion == 1 else { throw CompanionConversationExchangeError.unreadable }
            final = previous.merging(record)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = String(decoding: try encoder.encode(final), as: UTF8.self)
        var metadata = fields(existing?.metadata)
        metadata["subtype"] = subtype
        metadata["conversationId"] = record.id
        metadata["origin"] = record.origin
        let metadataJSON = String(decoding: try JSONSerialization.data(withJSONObject: metadata), as: UTF8.self)
        if var existing {
            existing.body = body
            existing.metadata = metadataJSON
            _ = try await repository.update(existing)
        } else {
            _ = try await repository.create(Atom.new(type: .systemEvent, title: record.title, body: body, metadata: metadataJSON))
        }
    }

    private static func decode(_ body: String?) -> CompanionConversationRecord? {
        guard let body else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CompanionConversationRecord.self, from: Data(body.utf8))
    }
    private static func fields(_ text: String?) -> [String: Any] {
        guard let text else { return [:] }
        return (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]) ?? [:]
    }
}
