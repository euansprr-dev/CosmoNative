import Foundation
import GRDB

/// Editorial readiness is independent of the publication plan and writing tools.
/// `phase` remains readable by earlier clients and records the editor's activity.
enum ContentProductionStage: String, Codable, CaseIterable, Identifiable, Sendable {
    case inProgress, review, ready, published

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inProgress: return "In progress"
        case .review: return "Review"
        case .ready: return "Ready"
        case .published: return "Published"
        }
    }

    var icon: String {
        switch self {
        case .inProgress: return "square.and.pencil"
        case .review: return "text.bubble"
        case .ready: return "checkmark.circle"
        case .published: return "paperplane"
        }
    }

    static func resolve(metadata: [String: Any], phase: ContentPhase) -> Self {
        if phase.isShipped { return .published }
        if let raw = metadata["productionStage"] as? String, let explicit = Self(rawValue: raw) {
            return explicit
        }
        // A legacy date, polish activity, or missing prior phase cannot prove readiness.
        return .inProgress
    }

    static func of(_ atom: Atom) -> Self {
        resolve(metadata: atom.metadataDict ?? [:], phase: ContentPipelineService.currentPhase(of: atom) ?? .draft)
    }
}

/// Undo owns only the keys touched by its operation. It never overwrites a newer
/// manuscript, source link, client brief, or unrelated metadata from another device.
struct ContentMetadataSnapshot: Sendable {
    let uuid: String
    let metadata: String?
    let keys: [String]

    init(atom: Atom, keys: [String]) {
        uuid = atom.uuid
        metadata = atom.metadata
        self.keys = keys
    }

    @discardableResult
    func restore() async -> Bool {
        do {
            let updated = try await CosmoDatabase.shared.asyncWrite { db in
                guard var fresh = try Atom.filter(Column("uuid") == uuid)
                    .filter(Column("is_deleted") == false).fetchOne(db) else {
                    throw ContentPipelineError.contentNotFound
                }
                guard fresh.metadata == nil || fresh.metadataDict != nil else {
                    throw ContentPipelineError.invalidMetadata
                }
                let old = metadata?.data(using: .utf8)
                    .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
                var dict = fresh.metadataDict ?? [:]
                for key in keys { dict[key] = old[key] }
                fresh.metadata = String(decoding: try JSONSerialization.data(withJSONObject: dict), as: UTF8.self)
                fresh.updatedAt = ISO8601.string(from: Date())
                fresh.localVersion += 1
                try fresh.update(db)
                try db.execute(sql: "UPDATE atoms SET _local_pending = 1 WHERE uuid = ?", arguments: [uuid])
                return fresh
            }
            await ChangeTracker.shared.trackUpdate(table: "atoms", entity: updated, skipVersionIncrement: true)
            await ContentPipelineService.notifyCalendar()
            return true
        } catch {
            PersistenceHealth.note(.writeFailure, context: "ContentMetadataSnapshot.restore", detail: error.localizedDescription)
            return false
        }
    }
}

extension ContentPipelineService {
    /// One key-merged write; changing readiness never changes a publication date.
    @discardableResult
    static func applyProductionStage(contentUUID: String, to stage: ContentProductionStage) async throws -> Atom {
        let updated = try await CosmoDatabase.shared.asyncWrite { db in
            guard let fresh = try Atom.filter(Column("uuid") == contentUUID)
                .filter(Column("is_deleted") == false)
                .filter(Column("type") == AtomType.content.rawValue).fetchOne(db) else {
                throw ContentPipelineError.contentNotFound
            }
            guard fresh.metadata == nil || fresh.metadataDict != nil else {
                throw ContentPipelineError.invalidMetadata
            }
            var dict = fresh.metadataDict ?? [:]
            let prior = Self.currentPhase(of: fresh) ?? .draft
            dict["productionStage"] = stage.rawValue
            if stage == .published {
                dict["phase"] = ContentPhase.published.rawValue
                dict["status"] = "published"
            } else if prior.isShipped || prior == .scheduled || prior == .archived {
                dict["phase"] = ContentPhase.draft.rawValue
                dict["status"] = dict["scheduledAt"] == nil ? "draft" : "scheduled"
            }
            dict.removeValue(forKey: "phaseBeforeSchedule")
            var result = fresh
            result.metadata = String(decoding: try JSONSerialization.data(withJSONObject: dict), as: UTF8.self)
            result.updatedAt = ISO8601.string(from: Date())
            result.localVersion += 1
            try result.update(db)
            try db.execute(sql: "UPDATE atoms SET _local_pending = 1 WHERE uuid = ?", arguments: [result.uuid])
            return result
        }
        await ChangeTracker.shared.trackUpdate(table: "atoms", entity: updated, skipVersionIncrement: true)
        await notifyCalendar()
        return updated
    }
}

extension ContentPipelineService {
    /// The client field and graph edge describe the same assignment and must
    /// change atomically. Other source links and manuscript keys are preserved.
    static func assignClient(contentUUID: String, to clientUUID: String?) async throws -> (before: Atom, after: Atom) {
        let change = try await CosmoDatabase.shared.asyncWrite { db -> (Atom, Atom) in
            guard let before = try Atom.filter(Column("uuid") == contentUUID)
                .filter(Column("is_deleted") == false).fetchOne(db), before.type == .content,
                  before.metadata == nil || before.metadataDict != nil else { throw ContentPipelineError.contentNotFound }
            var updated = before.removingLinks(ofType: .contentToClient).removingLinks(ofType: "client")
            var metadata = before.metadataDict ?? [:]
            metadata["clientProfileUUID"] = clientUUID
            updated.metadata = String(decoding: try JSONSerialization.data(withJSONObject: metadata), as: UTF8.self)
            if let clientUUID { updated = updated.addingLink(.contentToClient(clientUUID)) }
            updated.updatedAt = ISO8601.string(from: Date()); updated.localVersion += 1
            try updated.update(db)
            try db.execute(sql: "UPDATE atoms SET _local_pending = 1 WHERE uuid = ?", arguments: [contentUUID])
            return (before, updated)
        }
        await ChangeTracker.shared.trackUpdate(table: "atoms", entity: change.1, skipVersionIncrement: true)
        await notifyCalendar()
        return change
    }
}
