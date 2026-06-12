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

        // Mark crystallized extracts so the next run only processes new material
        // and the notes rail can show what's already in a Connection.
        for candidate in accepted {
            guard let promoted = promotedByCandidateId[candidate.id] else { continue }
            await markExtractsPromoted(candidate.clusterExtractUUIDs, into: promoted.uuid)
        }

        if let deepDive {
            currentDeepDive = try await ensureDeepDiveLinks(deepDive, connectionUUIDs: promotedByCandidateId.values.map(\.uuid))
        }

        if let thinkspaceUUID = await resolveThinkspaceUUID(for: currentDeepDive) {
            for (index, connection) in promotedByCandidateId.values.sorted(by: { ($0.title ?? "") < ($1.title ?? "") }).enumerated() {
                if try await placeConnectionIfNeeded(connection, thinkspaceUUID: thinkspaceUUID, index: index, sessionUUID: session.uuid) {
                    result.canvasBlocksCreated += 1
                }
            }
            // CanvasView reloads its blocks on this targeted notification —
            // blocksChanged alone is not observed for reload.
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.refreshThinkspacePlacements,
                object: nil,
                userInfo: ["thinkspaceId": thinkspaceUUID]
            )
        }

        NotificationCenter.default.post(name: CosmoNotification.Canvas.blocksChanged, object: nil)
        NotificationCenter.default.post(name: CosmoNotification.Canvas.thinkspaceChanged, object: nil)
        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.graphNodeUpdated, object: nil)
        return result
    }

    private func markExtractsPromoted(_ extractUUIDs: [String], into connectionUUID: String) async {
        for uuid in extractUUIDs {
            guard var extract = try? await atoms.fetch(uuid: uuid),
                  var metadata = extract.extractMetadata,
                  metadata.status != .promoted else { continue }
            metadata.status = .promoted
            metadata.promotedToUUID = connectionUUID
            extract = extract.withMetadata(metadata)
            _ = try? await atoms.update(extract)
        }
    }

    /// Resolves where promoted Connections should be placed. Deep dives created
    /// outside a thinkspace have no link — fall back to the open thinkspace and
    /// persist that link so future promotions land in the same place.
    private func resolveThinkspaceUUID(for deepDive: Atom?) async -> String? {
        if let linked = deepDive?.deepDiveMetadata?.primaryThinkspaceUUID
            ?? deepDive?.deepDiveMetadata?.parentThinkspaceUUIDs?.first {
            return linked
        }
        guard let current = ThinkspaceManager.shared.currentThinkspace?.id else { return nil }
        if var dd = deepDive {
            var metadata = dd.deepDiveMetadata ?? DeepDiveMetadata()
            metadata.primaryThinkspaceUUID = current
            metadata.parentThinkspaceUUIDs = (metadata.parentThinkspaceUUIDs ?? []) + [current]
            dd = dd.withMetadata(metadata)
            _ = try? await atoms.update(dd)
        }
        return current
    }

    private func upsertConnection(
        _ candidate: CrystallizationOutput.ConnectionCandidate,
        existing: Atom?,
        session: Atom,
        deepDive: Atom?,
        siblingUUIDsByCandidateId: [String: String]
    ) async throws -> Atom {
        let proposedSections = sections(for: candidate, siblingUUIDsByCandidateId: siblingUUIDsByCandidateId)
        let links = baseLinks(
            for: candidate,
            sessionUUID: session.uuid,
            deepDiveUUID: deepDive?.uuid,
            siblingUUIDs: Array(siblingUUIDsByCandidateId.values)
        )

        let saved: Atom
        let finalSections: [ConnectionSection]
        if var existing {
            // Merge, never replace: a concept page accumulates knowledge across
            // sessions, so user edits and previously merged items must survive.
            let existingSections = existing.structured
                .flatMap { ConnectionStructuredData.fromJSON($0)?.sections } ?? []
            finalSections = Self.mergedSections(existing: existingSections, proposed: proposedSections)

            var metadata = existing.metadataValue(as: InquiryPromotedConnectionMetadata.self)
                ?? InquiryPromotedConnectionMetadata(
                    originInquirySessionUUID: session.uuid,
                    originDeepDiveUUID: deepDive?.uuid,
                    inquiryBranchNodeId: candidate.branchNodeId,
                    materialCount: candidate.materialCount,
                    candidateId: candidate.id,
                    crystallizedAt: iso.string(from: Date())
                )
            metadata.contributingSessionUUIDs = Array(Set((metadata.contributingSessionUUIDs ?? []) + [session.uuid])).sorted()
            metadata.mergedExtractUUIDs = Array(Set((metadata.mergedExtractUUIDs ?? []) + candidate.clusterExtractUUIDs)).sorted()
            metadata.materialCount = finalSections.reduce(0) { $0 + $1.items.count }
            metadata.crystallizedAt = iso.string(from: Date())

            if (existing.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                existing.title = candidate.proposedTitle
            }
            existing.body = flattenedBody(sections: finalSections, notes: candidate.proposedNotes)
            // Key-merge both JSON columns: a wholesale replace dropped the rich
            // title document (metadata) and legacy mental-model keys (structured).
            existing = existing.mergingStructuredKeys(ConnectionStructuredData(sections: finalSections))
            existing = existing.mergingMetadataKeys(metadata)
            existing = existing.withLinks(mergeLinks(existing.linksList, links))
            saved = try await atoms.update(existing)
        } else {
            finalSections = proposedSections
            var metadata = InquiryPromotedConnectionMetadata(
                originInquirySessionUUID: session.uuid,
                originDeepDiveUUID: deepDive?.uuid,
                inquiryBranchNodeId: candidate.branchNodeId,
                materialCount: candidate.materialCount,
                candidateId: candidate.id,
                crystallizedAt: iso.string(from: Date())
            )
            metadata.contributingSessionUUIDs = [session.uuid]
            metadata.mergedExtractUUIDs = candidate.clusterExtractUUIDs.sorted()
            saved = try await atoms.create(
                type: .connection,
                title: candidate.proposedTitle,
                body: flattenedBody(sections: finalSections, notes: candidate.proposedNotes),
                structured: ConnectionStructuredData(sections: finalSections).toJSON(),
                metadata: try encode(metadata),
                links: links
            )
        }

        // Load-then-mutate the existing UD state: recreating it from scratch
        // reset the user's saved layout/viewport/insights on every promotion.
        var state = ConnectionFocusModeState.load(atomUUID: saved.uuid)
            ?? ConnectionFocusModeState(atomUUID: saved.uuid)
        state.sections = finalSections
        state.lastModified = Date()
        state.save()
        return saved
    }

    /// Merges proposed items into existing sections. An item is skipped when any
    /// existing section already holds it — matched by provenance (sourceAtomUUID)
    /// or normalized content — making repeated crystallizations idempotent.
    nonisolated static func mergedSections(
        existing: [ConnectionSection],
        proposed: [ConnectionSection]
    ) -> [ConnectionSection] {
        var merged = ConnectionFocusModeState.backfillingMissingSections(existing)
        var seenSourceUUIDs = Set(merged.flatMap { $0.items.compactMap(\.sourceAtomUUID) })
        var seenContentKeys = Set(merged.flatMap { $0.items.map { normalizedKey($0.resolvedPlainText) } })

        for section in proposed {
            for item in section.items {
                if let sourceUUID = item.sourceAtomUUID, seenSourceUUIDs.contains(sourceUUID) { continue }
                let contentKey = normalizedKey(item.resolvedPlainText)
                if !contentKey.isEmpty, seenContentKeys.contains(contentKey) { continue }

                guard let index = merged.firstIndex(where: { $0.type == section.type }) else { continue }
                merged[index].items.append(item)
                if let sourceUUID = item.sourceAtomUUID { seenSourceUUIDs.insert(sourceUUID) }
                seenContentKeys.insert(contentKey)
            }
        }
        return merged
    }

    nonisolated private static func normalizedKey(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
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
        // 1. Explicit merge target chosen by the concept resolver wins.
        if let targetUUID = candidate.mergeTargetConnectionUUID,
           let target = try await atoms.fetch(uuid: targetUUID) {
            return target
        }
        guard let deepDive else { return nil }
        let existing = try await InquiryRepository.shared.fetchConnections(forDeepDive: deepDive)
        // 2. Same concept key from a previous crystallization.
        if let conceptKey = candidate.conceptKey,
           let match = existing.first(where: { atom in
               atom.metadataValue(as: InquiryPromotedConnectionMetadata.self)?.candidateId == "connection-candidate-concept-\(conceptKey)"
           }) {
            return match
        }
        // 3. Legacy per-branch match.
        if let branchNodeId = candidate.branchNodeId,
           let match = existing.first(where: { atom in
               atom.metadataValue(as: InquiryPromotedConnectionMetadata.self)?.inquiryBranchNodeId == branchNodeId
           }) {
            return match
        }
        // 4. Title/alias match.
        let titleKeys = Set(([candidate.proposedTitle] + (candidate.conceptAliases ?? [])).map(normalized))
        return existing.first { titleKeys.contains(normalized($0.title ?? "")) }
    }

    private func placeConnectionIfNeeded(_ connection: Atom, thinkspaceUUID: String, index: Int, sessionUUID: String) async throws -> Bool {
        if try await existingCanvasBlockId(atomUUID: connection.uuid, thinkspaceUUID: thinkspaceUUID) != nil {
            return false
        }

        let blockId = UUID().uuidString
        // Land next to the user's existing content, not at canvas origin where
        // it would be invisible at their current viewport.
        let anchor = try await contentAnchor(thinkspaceUUID: thinkspaceUUID)
        let x = anchor.x + CGFloat(index * 340)
        let y = anchor.y + CGFloat((index % 2) * 120)
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

    /// A placement origin just right of the thinkspace's existing content,
    /// vertically centered on it. Empty canvases get a sensible default.
    private func contentAnchor(thinkspaceUUID: String) async throws -> CGPoint {
        let bounds: (maxX: Double, avgY: Double)? = try await database.asyncRead { db in
            try Row.fetchOne(
                db,
                sql: """
                    SELECT MAX(position_x + width) AS max_x, AVG(position_y) AS avg_y FROM canvas_blocks
                    WHERE thinkspace_id = ? AND document_type = 'home' AND document_id = 0 AND is_deleted = 0
                """,
                arguments: [thinkspaceUUID]
            ).flatMap { row in
                guard let maxX: Double = row["max_x"], let avgY: Double = row["avg_y"] else { return nil }
                return (maxX, avgY)
            }
        }
        guard let bounds else { return CGPoint(x: -140, y: 220) }
        return CGPoint(x: bounds.maxX + 120, y: bounds.avgY)
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
    var mergedExtractUUIDs: [String]?         // Provenance for idempotent merges
    var contributingSessionUUIDs: [String]?   // Every session that fed this page
}
