import Foundation
import GRDB

enum PageContentHandoffError: Error, LocalizedError {
    case unavailablePage, unavailableClient, missingTitle, operationConflict
    var errorDescription: String? {
        switch self {
        case .unavailablePage: return "This page is no longer available. Your idea hasn't been created."
        case .unavailableClient: return "This client is no longer available. Choose another destination."
        case .missingTitle: return "Give the content idea a title."
        case .operationConflict: return "This creation has already changed. Open the existing idea before trying again."
        }
    }
}

/// An explicit handoff creates production intent, never converts the source
/// page or copies its composition, drawings, attachments or child hierarchy.
enum PageContentHandoffWriter {
    static func create(sourceUUID: String, title: String, angle: String, clientUUID: String?,
                       operationID: String, db: Database) throws -> Atom {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw PageContentHandoffError.missingTitle }
        if let existing = try Atom.filter(Column("uuid") == operationID).fetchOne(db) {
            guard existing.type == .idea, !existing.isDeleted,
                  existing.linksList.contains(where: { $0.type == "source" && $0.uuid == sourceUUID && $0.entityType == AtomType.note.rawValue }) else {
                throw PageContentHandoffError.operationConflict
            }
            return existing
        }
        guard let source = try Atom.filter(Column("uuid") == sourceUUID).fetchOne(db),
              !source.isDeleted, source.type == .note,
              try source.decodedSpaceComposition()?.kind != .group else { throw PageContentHandoffError.unavailablePage }
        let client: Atom?
        if let clientUUID {
            guard let value = try Atom.filter(Column("uuid") == clientUUID).fetchOne(db),
                  !value.isDeleted, value.type == .clientProfile else { throw PageContentHandoffError.unavailableClient }
            client = value
        } else { client = nil }

        let angle = angle.trimmingCharacters(in: .whitespacesAndNewlines)
        var fields: [String: Any] = [
            "captureSource": "page", "pageContentSourceUUID": source.uuid,
            "mentionedAtomUUIDs": [source.uuid], "ideaStatus": "spark"
        ]
        if !angle.isEmpty { fields["ideaDescription"] = angle }
        if let client { fields["clientUUID"] = client.uuid; fields["clientName"] = client.title ?? "Untitled client" }
        let metadata = String(decoding: try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]), as: UTF8.self)
        var idea = Atom.new(type: .idea, title: title, body: angle.isEmpty ? nil : angle, metadata: metadata)
        idea.uuid = operationID
        idea = idea.addingLink(AtomLink(type: "source", uuid: source.uuid, entityType: source.type.rawValue))
        if let client { idea = idea.addingLink(.ideaToClient(client.uuid)) }
        try idea.insert(db)
        idea.id = db.lastInsertedRowID
        try db.execute(sql: "UPDATE atoms SET _local_pending = 1 WHERE uuid = ?", arguments: [idea.uuid])
        let payload = String(decoding: try JSONEncoder().encode(idea), as: UTF8.self)
        try db.execute(sql: "INSERT INTO sync_queue (uuid,table_name,row_id,operation,data,local_version,status) VALUES (?,'atoms',?,'INSERT',?,?,'pending')",
            arguments: [idea.uuid, idea.id, payload, idea.localVersion])
        return idea
    }
}

@MainActor
enum PageContentHandoffService {
    static func create(sourceUUID: String, title: String, angle: String, clientUUID: String?, operationID: String) async throws -> Atom {
        let (idea, created) = try await CosmoDatabase.shared.asyncWrite { db in
            let existed = try Atom.filter(Column("uuid") == operationID).fetchCount(db) > 0
            let result = try PageContentHandoffWriter.create(sourceUUID: sourceUUID, title: title, angle: angle,
                clientUUID: clientUUID, operationID: operationID, db: db)
            return (result, !existed)
        }
        if created {
            await ChangeTracker.shared.trackInsert(table: Atom.databaseTableName, entity: idea)
            try? await NodeGraphEngine.shared.handleAtomCreated(idea)
            Task.detached(priority: .utility) { await RecallIndexer.shared.noteAtomChanged(idea) }
            NotificationCenter.default.post(name: CosmoNotification.Entity.created, object: nil,
                userInfo: ["uuid": idea.uuid, "type": AtomType.idea.rawValue])
        }
        return idea
    }
}
