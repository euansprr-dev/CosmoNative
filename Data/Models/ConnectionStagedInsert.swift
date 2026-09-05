// CosmoOS/Data/Models/ConnectionStagedInsert.swift
// Persisted pending material for a Concept page — the durable home the
// CONCEPT_RIPENING_PLAN's ghost-row grammar always wanted ("a page you shaped
// by hand is never silently edited by a pipeline"). An inbox feedConnection,
// or a seedling developing into an existing page, STAGES here; the material
// renders as dashed ✓/✗ ghost rows in the page's sections and enters the
// page only when the user sweeps it in.
//
// Storage: the connection atom's metadata under `connectionStagedInserts`
// (key-level merge; JSON travels with the atom through sync, so both
// platforms can stage and the sweep happens wherever the page is opened).
// July 2026.

import Foundation

struct ConnectionStagedInsert: Codable, Equatable, Identifiable, Sendable {
    var id: String
    /// ConnectionSectionType rawValue — kept raw so an unknown section from a
    /// newer app version degrades to "unfiled" instead of poisoning decode.
    var section: String
    var text: String
    /// Where the material came from: "inbox" (feedConnection) or "seedling"
    /// (develop-into-existing-page).
    var sourceKind: String
    /// The inbox capture / seedling uuid behind this material — rejecting an
    /// inbox-fed row hands the capture back to the queue.
    var sourceUUID: String?
    /// Page/photo originals still owned by the source capture; they re-own
    /// onto the page only when the row is accepted.
    var attachmentUUIDs: [String]
    var stagedAt: String

    init(
        id: String = UUID().uuidString,
        section: String,
        text: String,
        sourceKind: String,
        sourceUUID: String? = nil,
        attachmentUUIDs: [String] = [],
        stagedAt: String = ISO8601.string(from: Date())
    ) {
        self.id = id
        self.section = section
        self.text = text
        self.sourceKind = sourceKind
        self.sourceUUID = sourceUUID
        self.attachmentUUIDs = attachmentUUIDs
        self.stagedAt = stagedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, section, text, sourceKind, sourceUUID, attachmentUUIDs, stagedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        section = try c.decodeIfPresent(String.self, forKey: .section) ?? ConnectionSectionType.claims.rawValue
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        sourceKind = try c.decodeIfPresent(String.self, forKey: .sourceKind) ?? "inbox"
        sourceUUID = try c.decodeIfPresent(String.self, forKey: .sourceUUID)
        attachmentUUIDs = try c.decodeIfPresent([String].self, forKey: .attachmentUUIDs) ?? []
        stagedAt = try c.decodeIfPresent(String.self, forKey: .stagedAt) ?? ISO8601.string(from: Date())
    }

    var sectionType: ConnectionSectionType? {
        ConnectionSectionType(rawValue: section)
    }
}

// MARK: - Atom accessors

/// One-key overlay so `mergingMetadataKeys` merges without touching sibling
/// metadata; the read side tolerates the key being absent.
private struct ConnectionStagedInsertsOverlay: Codable {
    var connectionStagedInserts: [ConnectionStagedInsert]?
}

extension Atom {
    /// Pending material staged onto this Concept page, awaiting a sweep.
    var connectionStagedInserts: [ConnectionStagedInsert] {
        metadataValue(as: ConnectionStagedInsertsOverlay.self)?.connectionStagedInserts ?? []
    }

    func withConnectionStagedInserts(_ inserts: [ConnectionStagedInsert]) -> Atom {
        mergingMetadataKeys(ConnectionStagedInsertsOverlay(connectionStagedInserts: inserts))
    }
}

// MARK: - Store (the one mutation path)

/// All staged-insert mutations go through here: tracked atom updates plus the
/// change notification open workspaces listen for.
@MainActor
enum ConnectionStagingStore {

    /// Stage material onto a page. Dedup: the same source (capture/seedling)
    /// staging into the same section twice is a retry echo, not new material.
    @discardableResult
    static func stage(_ insert: ConnectionStagedInsert, onConnection connectionUUID: String) async throws -> Atom? {
        let updated = try await AtomRepository.shared.update(uuid: connectionUUID) { atom in
            var inserts = atom.connectionStagedInserts
            if isRetryEcho(insert, existing: inserts) { return }
            inserts.append(insert)
            atom = atom.withConnectionStagedInserts(inserts)
        }
        notifyChanged(connectionUUID)
        return updated
    }

    /// A re-stage is an echo, not new material: the same source targeting the
    /// same section again (inbox/seedling retries re-derive identical rows), or
    /// byte-identical text landing in the same section (collaborator rows carry
    /// no sourceUUID — two DISTINCT bullets into one section must both land, so
    /// only an exact text match counts as an echo).
    nonisolated static func isRetryEcho(
        _ insert: ConnectionStagedInsert,
        existing: [ConnectionStagedInsert]
    ) -> Bool {
        if let sourceUUID = insert.sourceUUID,
           existing.contains(where: { $0.sourceUUID == sourceUUID && $0.section == insert.section }) {
            return true
        }
        return existing.contains { $0.section == insert.section && $0.text == insert.text }
    }

    /// Remove one staged row (accept consumed it, reject discarded it, or an
    /// undo is unwinding a stage). Returns the removed entry.
    @discardableResult
    static func remove(insertId: String, fromConnection connectionUUID: String) async throws -> ConnectionStagedInsert? {
        var removed: ConnectionStagedInsert?
        _ = try await AtomRepository.shared.update(uuid: connectionUUID) { atom in
            var inserts = atom.connectionStagedInserts
            guard let index = inserts.firstIndex(where: { $0.id == insertId }) else { return }
            removed = inserts.remove(at: index)
            atom = atom.withConnectionStagedInserts(inserts)
        }
        if removed != nil { notifyChanged(connectionUUID) }
        return removed
    }

    /// Re-add a previously removed entry (undo of a reject/accept).
    static func restore(_ insert: ConnectionStagedInsert, onConnection connectionUUID: String) async throws {
        _ = try await AtomRepository.shared.update(uuid: connectionUUID) { atom in
            var inserts = atom.connectionStagedInserts
            guard !inserts.contains(where: { $0.id == insert.id }) else { return }
            inserts.append(insert)
            atom = atom.withConnectionStagedInserts(inserts)
        }
        notifyChanged(connectionUUID)
    }

    /// Accepting a row carries its capture originals onto the page (union —
    /// never clobbering attachments the page already has).
    static func adoptAttachments(of insert: ConnectionStagedInsert, ontoConnection connectionUUID: String) async {
        guard !insert.attachmentUUIDs.isEmpty else { return }
        for uuid in insert.attachmentUUIDs {
            _ = try? await MediaAttachmentRepository.shared.trackedMutation(uuid: uuid) { attachment in
                attachment.ownerType = MediaAttachmentOwner.atom.rawValue
                attachment.ownerUUID = connectionUUID
                return true
            }
        }
        _ = try? await AtomRepository.shared.update(uuid: connectionUUID) { atom in
            let existing = atom.attachmentUUIDs
            let union = existing + insert.attachmentUUIDs.filter { !existing.contains($0) }
            atom = atom.mergingMetadataKeys(["attachmentUUIDs": union])
        }
    }

    /// Rejecting an inbox-fed row hands the capture back to the queue — the
    /// material wasn't wanted HERE, but it was still the user's thought.
    /// Best-effort: a capture dismissed or deleted since stays put.
    static func returnSourceCapture(of insert: ConnectionStagedInsert) async {
        guard let captureUUID = insert.sourceUUID else { return }
        if insert.sourceKind == "inbox",
           var item = try? await InboxRepository.shared.fetch(uuid: captureUUID),
           item.status == .actioned, !item.isDeleted {
            item.status = item.classification == nil ? .pending : .classified
            item.actionedAt = nil
            try? await InboxRepository.shared.restore(item)
        } else if insert.sourceKind == "lane",
                  let item = try? await CapturedItemRepository.shared.fetch(uuid: captureUUID),
                  item.status == .applied, !item.isDeleted {
            try? await CapturedItemRepository.shared.updateRouting(uuid: item.uuid,
                destinationId: item.captureDestinationId, parsedCommand: item.parsedCommand,
                parsedIntent: item.parsedIntent, confidence: item.routingConfidence,
                status: .routed, createdObjectIds: item.createdObjectIds,
                parentDeepDiveId: item.parentDeepDiveId, parentInquirySessionId: item.parentInquirySessionId,
                parentQuestionId: item.parentQuestionId, parentProjectId: item.parentProjectId)
        }
    }

    private static func notifyChanged(_ connectionUUID: String) {
        NotificationCenter.default.post(
            name: CosmoNotification.Connection.stagedInsertsChanged,
            object: nil,
            userInfo: ["connectionUUID": connectionUUID]
        )
    }
}
