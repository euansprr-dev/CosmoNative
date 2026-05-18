// CosmoOS/AI/ConnectionPromotionService.swift
// Promotes accepted Inquiry branch drafts into structured Connection atoms.

import Foundation
import GRDB
import SwiftUI

struct ConnectionPromotionResult: Sendable {
    var created: Int = 0
    var updated: Int = 0
    var linked: Int = 0
    var canvasBlocksCreated: Int = 0
}

@MainActor
final class ConnectionPromotionService {
    static let shared = ConnectionPromotionService()

    private let atoms = AtomRepository.shared
    private let database = CosmoDatabase.shared
    private let iso = ISO8601DateFormatter()

    private init() {}

    @discardableResult
    func applyAcceptedCandidates(
        _ candidates: [CrystallizationOutput.ConnectionCandidate],
        session: Atom,
        deepDive: Atom?
    ) async throws -> ConnectionPromotionResult {
        let accepted = candidates.filter(\.accepted)
        guard !accepted.isEmpty else { return ConnectionPromotionResult() }

        var result = ConnectionPromotionResult()
        var promotedByCandidateId: [String: Atom] = [:]
        var currentDeepDive = deepDive

        for candidate in accepted {
            let existing = try await existingConnection(for: candidate, deepDive: currentDeepDive)
            let promoted = try await upsertConnection(
                candidate,
                existing: existing,
                session: session,
                deepDive: currentDeepDive,
                siblingUUIDsByCandidateId: [:]
            )
            promotedByCandidateId[candidate.id] = promoted
            if existing == nil {
                result.created += 1
            } else {
                result.updated += 1
            }
        }

        for candidate in accepted {
            guard let promoted = promotedByCandidateId[candidate.id] else { continue }
            let siblingUUIDs = candidate.proposedReferences.compactMap { promotedByCandidateId[$0]?.uuid }
            let updated = try await upsertConnection(
                candidate,
                existing: promoted,
                session: session,
                deepDive: currentDeepDive,
                siblingUUIDsByCandidateId: Dictionary(uniqueKeysWithValues: siblingUUIDs.map { ($0, $0) })
            )
            promotedByCandidateId[candidate.id] = updated
            result.linked += try await ensureLinks(for: updated, candidate: candidate, siblingUUIDs: siblingUUIDs)
        }

        if let deepDive {
            currentDeepDive = try await ensureDeepDiveLinks(deepDive, connectionUUIDs: promotedByCandidateId.values.map(\.uuid))
        }

        if let thinkspaceUUID = currentDeepDive?.deepDiveMetadata?.primaryThinkspaceUUID
            ?? currentDeepDive?.deepDiveMetadata?.parentThinkspaceUUIDs?.first {
            for (index, connection) in promotedByCandidateId.values.sorted(by: { ($0.title ?? "") < ($1.title ?? "") }).enumerated() {
                if try await placeConnectionIfNeeded(connection, thinkspaceUUID: thinkspaceUUID, index: index, sessionUUID: session.uuid) {
                    result.canvasBlocksCreated += 1
                }
            }
        }

        NotificationCenter.default.post(name: CosmoNotification.Canvas.blocksChanged, object: nil)
        NotificationCenter.default.post(name: CosmoNotification.Canvas.thinkspaceChanged, object: nil)
        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.graphNodeUpdated, object: nil)
        return result
    }

    private func upsertConnection(
        _ candidate: CrystallizationOutput.ConnectionCandidate,
        existing: Atom?,
        session: Atom,
        deepDive: Atom?,
        siblingUUIDsByCandidateId: [String: String]
    ) async throws -> Atom {
        let sections = sections(for: candidate, siblingUUIDsByCandidateId: siblingUUIDsByCandidateId)
        let structured = ConnectionStructuredData(sections: sections)
        let body = flattenedBody(sections: sections, notes: candidate.proposedNotes)
        let metadata = InquiryPromotedConnectionMetadata(
            originInquirySessionUUID: session.uuid,
            originDeepDiveUUID: deepDive?.uuid,
            inquiryBranchNodeId: candidate.branchNodeId,
            materialCount: candidate.materialCount,
            candidateId: candidate.id,
            crystallizedAt: iso.string(from: Date())
        )
        let metadataJSON = try encode(metadata)
        let structuredJSON = structured.toJSON()

        let links = baseLinks(
            for: candidate,
            sessionUUID: session.uuid,
            deepDiveUUID: deepDive?.uuid,
            siblingUUIDs: Array(siblingUUIDsByCandidateId.values)
        )

        let saved: Atom
        if var existing {
            existing.title = candidate.proposedTitle
            existing.body = body
            existing.structured = structuredJSON
            existing.metadata = metadataJSON
            existing = existing.withLinks(mergeLinks(existing.linksList, links))
            saved = try await atoms.update(existing)
        } else {
            saved = try await atoms.create(
                type: .connection,
                title: candidate.proposedTitle,
                body: body,
                structured: structuredJSON,
                metadata: metadataJSON,
                links: links
            )
        }

        var state = ConnectionFocusModeState(atomUUID: saved.uuid)
        state.sections = sections
        state.save()
        return saved
    }

    private func sections(
        for candidate: CrystallizationOutput.ConnectionCandidate,
        siblingUUIDsByCandidateId: [String: String]
    ) -> [ConnectionSection] {
        var sections = ConnectionSectionType.allCases.map { ConnectionSection(type: $0) }
        for (type, drafts) in candidate.proposedSections {
            guard let sectionIndex = sections.firstIndex(where: { $0.type == type }) else { continue }
            sections[sectionIndex].items = drafts.map { item(from: $0) }
        }
        if let referencesIndex = sections.firstIndex(where: { $0.type == .references }) {
            for siblingUUID in siblingUUIDsByCandidateId.values.sorted() {
                if !sections[referencesIndex].items.contains(where: { $0.sourceAtomUUID == siblingUUID }) {
                    sections[referencesIndex].items.append(
                        ConnectionItem(
                            content: "Sibling Connection",
                            sourceAtomUUID: siblingUUID,
                            sourceSnippet: "Auto-linked sibling Connection from the same Deep Dive."
                        )
                    )
                }
            }
        }
        return ConnectionFocusModeState.backfillingMissingSections(sections)
    }

    private func item(from draft: ConnectionSectionItemDraft) -> ConnectionItem {
        ConnectionItem(
            content: draft.body,
            sourceAtomUUID: draft.originExtractUUID ?? draft.sourceUUID,
            sourceSnippet: draft.body
        )
    }

    private func flattenedBody(sections: [ConnectionSection], notes: [ConnectionSectionItemDraft]) -> String {
        var lines: [String] = []
        for section in sections where !section.items.isEmpty {
            lines.append("## \(section.type.displayName)")
            lines.append(contentsOf: section.items.map(\.resolvedPlainText))
            lines.append("")
        }
        if !notes.isEmpty {
            lines.append("## Notes")
            lines.append(contentsOf: notes.map(\.body))
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func baseLinks(
        for candidate: CrystallizationOutput.ConnectionCandidate,
        sessionUUID: String,
        deepDiveUUID: String?,
        siblingUUIDs: [String]
    ) -> [AtomLink] {
        var links: [AtomLink] = [
            AtomLink(type: "origin_session", uuid: sessionUUID, entityType: AtomType.inquirySession.rawValue)
        ]
        if let deepDiveUUID {
            links.append(AtomLink(type: AtomLinkType.deepDiveConnection.rawValue, uuid: deepDiveUUID, entityType: AtomType.deepDive.rawValue))
        }
        for draft in candidate.proposedSections.values.flatMap({ $0 }) {
            if let origin = draft.originExtractUUID {
                links.append(AtomLink(type: AtomLinkType.connection.rawValue, uuid: origin, entityType: AtomType.extract.rawValue))
            }
            if let source = draft.sourceUUID {
                links.append(AtomLink(type: AtomLinkType.connection.rawValue, uuid: source, entityType: AtomType.research.rawValue))
            }
        }
        for siblingUUID in siblingUUIDs {
            links.append(AtomLink(type: AtomLinkType.connection.rawValue, uuid: siblingUUID, entityType: AtomType.connection.rawValue))
        }
        return deduplicatedLinks(links)
    }

    private func ensureLinks(
        for connection: Atom,
        candidate: CrystallizationOutput.ConnectionCandidate,
        siblingUUIDs: [String]
    ) async throws -> Int {
        var links = connection.linksList
        let before = links.count
        links = mergeLinks(links, baseLinks(for: candidate, sessionUUID: "", deepDiveUUID: nil, siblingUUIDs: siblingUUIDs))
            .filter { !($0.type == "origin_session" && $0.uuid.isEmpty) }
        if links.count != before {
            var copy = connection.withLinks(links)
            copy.updatedAt = iso.string(from: Date())
            _ = try await atoms.update(copy)
        }
        return max(links.count - before, 0)
    }

    private func ensureDeepDiveLinks(_ deepDive: Atom, connectionUUIDs: [String]) async throws -> Atom {
        var copy = deepDive
        var links = copy.linksList
        for uuid in connectionUUIDs {
            let link = AtomLink(type: AtomLinkType.deepDiveConnection.rawValue, uuid: uuid, entityType: AtomType.connection.rawValue)
            if !links.contains(where: { $0.type == link.type && $0.uuid == link.uuid }) {
                links.append(link)
            }
        }
        copy = copy.withLinks(links)
        return try await atoms.update(copy)
    }

    private func existingConnection(for candidate: CrystallizationOutput.ConnectionCandidate, deepDive: Atom?) async throws -> Atom? {
        guard let deepDive else { return nil }
        let existing = try await InquiryRepository.shared.fetchConnections(forDeepDive: deepDive)
        if let branchNodeId = candidate.branchNodeId,
           let match = existing.first(where: { atom in
               atom.metadataValue(as: InquiryPromotedConnectionMetadata.self)?.inquiryBranchNodeId == branchNodeId
           }) {
            return match
        }
        return existing.first { normalized($0.title ?? "") == normalized(candidate.proposedTitle) }
    }

    private func placeConnectionIfNeeded(_ connection: Atom, thinkspaceUUID: String, index: Int, sessionUUID: String) async throws -> Bool {
        if try await existingCanvasBlockId(atomUUID: connection.uuid, thinkspaceUUID: thinkspaceUUID) != nil {
            return false
        }

        let blockId = UUID().uuidString
        let x = -140 + CGFloat(index * 340)
        let y = CGFloat(220 + (index % 2) * 120)
        var block = CanvasBlock.fromAtom(connection, position: CGPoint(x: x, y: y))
        block = CanvasBlock(
            id: blockId,
            position: CGPoint(x: x, y: y),
            size: CGSize(width: 320, height: 220),
            isPinned: block.isPinned,
            zIndex: 0,
            entityType: block.entityType,
            entityId: block.entityId,
            entityUuid: block.entityUuid,
            title: block.title,
            subtitle: block.subtitle,
            metadata: block.metadata.merging([
                "originSessionUUID": sessionUUID,
                "visualMaturity": CanvasObjectVisualMaturity.conceptCardOrConnection.rawValue
            ]) { current, _ in current }
        )
        let record = CanvasBlockRecord.from(block, documentType: "home", documentId: 0, thinkspaceId: thinkspaceUUID)
        try await database.asyncWrite { db in
            try record.save(db)
        }
        try await appendBlockToThinkspaceMetadata(blockId: blockId, thinkspaceUUID: thinkspaceUUID)
        return true
    }

    private func existingCanvasBlockId(atomUUID: String, thinkspaceUUID: String) async throws -> String? {
        try await database.asyncRead { db in
            try String.fetchOne(
                db,
                sql: """
                    SELECT id FROM canvas_blocks
                    WHERE entity_uuid = ? AND thinkspace_id = ? AND document_type = 'home' AND document_id = 0 AND is_deleted = 0
                    LIMIT 1
                """,
                arguments: [atomUUID, thinkspaceUUID]
            )
        }
    }

    private func appendBlockToThinkspaceMetadata(blockId: String, thinkspaceUUID: String) async throws {
        guard var thinkspace = try await atoms.fetch(uuid: thinkspaceUUID) else { return }
        var metadata = thinkspace.metadataValue(as: ThinkspaceMetadata.self) ?? ThinkspaceMetadata(name: thinkspace.title ?? "Thinkspace")
        if !metadata.blockIds.contains(blockId) {
            metadata.blockIds.append(blockId)
            thinkspace = thinkspace.withMetadata(metadata)
            _ = try await atoms.update(thinkspace)
        }
    }

    private func mergeLinks(_ existing: [AtomLink], _ additions: [AtomLink]) -> [AtomLink] {
        deduplicatedLinks(existing + additions)
    }

    private func deduplicatedLinks(_ links: [AtomLink]) -> [AtomLink] {
        var seen = Set<String>()
        return links.filter { link in
            let key = "\(link.type)|\(link.uuid)|\(link.entityType ?? "")"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private struct InquiryPromotedConnectionMetadata: Codable, Sendable {
    var kind: String = "inquiry_v2_branch_connection"
    var originInquirySessionUUID: String
    var originDeepDiveUUID: String?
    var inquiryBranchNodeId: String?
    var materialCount: Int
    var candidateId: String
    var crystallizedAt: String
}
