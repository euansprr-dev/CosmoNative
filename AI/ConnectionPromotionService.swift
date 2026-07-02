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

    /// A resolved link target: another Connection page this one references.
    struct ConnectionLinkRef: Sendable, Equatable {
        var uuid: String
        var title: String
    }

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
        var createdUUIDs = Set<String>()
        var currentDeepDive = deepDive
        let preexisting: [Atom] = if let currentDeepDive {
            (try? await InquiryRepository.shared.fetchConnections(forDeepDive: currentDeepDive)) ?? []
        } else {
            []
        }

        for candidate in accepted {
            let existing = try await existingConnection(for: candidate, deepDive: currentDeepDive)
            let promoted = try await upsertConnection(
                candidate,
                existing: existing,
                session: session,
                deepDive: currentDeepDive,
                siblingRefs: [],
                connectionTitlesByUUID: [:]
            )
            promotedByCandidateId[candidate.id] = promoted
            if existing == nil {
                result.created += 1
                createdUUIDs.insert(promoted.uuid)
            } else {
                result.updated += 1
            }
        }

        // Link resolution spans BOTH this run's pages and every page the deep
        // dive already has — related concepts name pages regardless of when
        // they were crystallized.
        var uuidByConceptKey: [String: String] = [:]
        var titleByUUID: [String: String] = [:]
        for atom in preexisting {
            guard let title = atom.title, !title.isEmpty else { continue }
            titleByUUID[atom.uuid] = title
            uuidByConceptKey[ConceptResolver.conceptKey(title)] = atom.uuid
        }
        for candidate in accepted {
            guard let promoted = promotedByCandidateId[candidate.id] else { continue }
            let title = promoted.title ?? candidate.proposedTitle
            titleByUUID[promoted.uuid] = title
            for name in [title] + (candidate.conceptAliases ?? []) {
                uuidByConceptKey[ConceptResolver.conceptKey(name)] = promoted.uuid
            }
        }

        // Second pass: write outgoing reference rows + atom links, collecting
        // every edge so the reciprocal backlinks can be applied afterwards
        // against fresh atoms (writing them mid-pass would race the upserts).
        var edges: [(from: ConnectionLinkRef, to: ConnectionLinkRef)] = []
        for candidate in accepted {
            guard let promoted = promotedByCandidateId[candidate.id] else { continue }
            var targetsByUUID: [String: String] = [:]
            for candidateId in candidate.proposedReferences {
                guard let sibling = promotedByCandidateId[candidateId], sibling.uuid != promoted.uuid else { continue }
                targetsByUUID[sibling.uuid] = titleByUUID[sibling.uuid] ?? sibling.title ?? "Connection"
            }
            for name in candidate.relatedConceptNames ?? [] {
                guard let uuid = uuidByConceptKey[ConceptResolver.conceptKey(name)], uuid != promoted.uuid else { continue }
                targetsByUUID[uuid] = titleByUUID[uuid] ?? name
            }
            let refs = targetsByUUID
                .map { ConnectionLinkRef(uuid: $0.key, title: $0.value) }
                .sorted { $0.title < $1.title }
            let updated = try await upsertConnection(
                candidate,
                existing: promoted,
                session: session,
                deepDive: currentDeepDive,
                siblingRefs: refs,
                connectionTitlesByUUID: titleByUUID
            )
            promotedByCandidateId[candidate.id] = updated
            result.linked += try await ensureLinks(for: updated, candidate: candidate, siblingUUIDs: refs.map(\.uuid))
            let selfRef = ConnectionLinkRef(uuid: updated.uuid, title: titleByUUID[updated.uuid] ?? updated.title ?? "Connection")
            edges.append(contentsOf: refs.map { (from: selfRef, to: $0) })
        }

        // Backlinks: every A → B edge gets a B → A reference row, so the graph
        // reads in both directions.
        for edge in edges {
            await ensureLinkRow(on: edge.to.uuid, to: edge.from)
        }

        // Retro-linking: a page created today lights up yesterday's pages that
        // already mention it — the web compounds with every crystallization.
        for createdUUID in createdUUIDs {
            guard let title = titleByUUID[createdUUID] else { continue }
            let aliases = accepted.first { promotedByCandidateId[$0.id]?.uuid == createdUUID }?.conceptAliases ?? []
            let newRef = ConnectionLinkRef(uuid: createdUUID, title: title)
            for other in preexisting where other.uuid != createdUUID {
                guard Self.connectionMentions(other, names: [title] + aliases) else { continue }
                let otherRef = ConnectionLinkRef(uuid: other.uuid, title: other.title ?? "Connection")
                await ensureLinkRow(on: other.uuid, to: newRef)
                await ensureLinkRow(on: createdUUID, to: otherRef)
            }
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
        siblingRefs: [ConnectionLinkRef],
        connectionTitlesByUUID: [String: String]
    ) async throws -> Atom {
        let proposedSections = sections(for: candidate, siblingRefs: siblingRefs)
        let links = baseLinks(
            for: candidate,
            sessionUUID: session.uuid,
            deepDiveUUID: deepDive?.uuid,
            siblingUUIDs: siblingRefs.map(\.uuid)
        )

        let saved: Atom
        let finalSections: [ConnectionSection]
        if var existing {
            // Merge, never replace: a concept page accumulates knowledge across
            // sessions, so user edits and previously merged items must survive.
            let existingSections = Self.upgradedLegacyLinkRows(
                existing.structured.flatMap { ConnectionStructuredData.fromJSON($0)?.sections } ?? [],
                connectionTitlesByUUID: connectionTitlesByUUID
            )
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
        siblingRefs: [ConnectionLinkRef]
    ) -> [ConnectionSection] {
        var sections = ConnectionSectionType.allCases.map { ConnectionSection(type: $0) }
        for (type, drafts) in candidate.proposedSections {
            guard let sectionIndex = sections.firstIndex(where: { $0.type == type }) else { continue }
            sections[sectionIndex].items = drafts.map { item(from: $0) }
        }
        if let referencesIndex = sections.firstIndex(where: { $0.type == .references }) {
            for ref in siblingRefs {
                if !sections[referencesIndex].items.contains(where: {
                    $0.linkedConnectionUUID == ref.uuid || $0.sourceAtomUUID == ref.uuid
                }) {
                    sections[referencesIndex].items.append(Self.linkItem(to: ref))
                }
            }
        }
        return ConnectionFocusModeState.backfillingMissingSections(sections)
    }

    /// A first-class hyperlink row to another Connection page.
    nonisolated private static func linkItem(to ref: ConnectionLinkRef) -> ConnectionItem {
        ConnectionItem(
            content: ref.title,
            sourceAtomUUID: ref.uuid,
            sourceSnippet: "Linked Connection from the same Deep Dive.",
            linkedConnectionUUID: ref.uuid
        )
    }

    /// Upgrades pre-hyperlink "Sibling Connection" reference rows in place:
    /// rows whose provenance points at a known Connection gain the link field
    /// and show the page's real title.
    nonisolated static func upgradedLegacyLinkRows(
        _ sections: [ConnectionSection],
        connectionTitlesByUUID: [String: String]
    ) -> [ConnectionSection] {
        guard !connectionTitlesByUUID.isEmpty else { return sections }
        var upgraded = sections
        for sectionIdx in upgraded.indices where upgraded[sectionIdx].type == .references {
            for itemIdx in upgraded[sectionIdx].items.indices {
                var item = upgraded[sectionIdx].items[itemIdx]
                guard item.linkedConnectionUUID == nil,
                      let sourceUUID = item.sourceAtomUUID,
                      let title = connectionTitlesByUUID[sourceUUID] else { continue }
                item.linkedConnectionUUID = sourceUUID
                if item.resolvedPlainText == "Sibling Connection" {
                    item.content = title
                    item.plainText = title
                    item.document = nil
                }
                upgraded[sectionIdx].items[itemIdx] = item
            }
        }
        return upgraded
    }

    /// Idempotently adds a hyperlink row (references section) + atom link from
    /// the page `uuid` to `ref`. Used for backlinks and retro-linking, where
    /// the target page is not part of the current promotion pass — the atom is
    /// fetched fresh so concurrent upserts are never clobbered.
    private func ensureLinkRow(on uuid: String, to ref: ConnectionLinkRef) async {
        guard uuid != ref.uuid, var target = try? await atoms.fetch(uuid: uuid) else { return }
        var sections = ConnectionFocusModeState.backfillingMissingSections(
            target.structured.flatMap { ConnectionStructuredData.fromJSON($0)?.sections } ?? []
        )
        guard let referencesIndex = sections.firstIndex(where: { $0.type == .references }) else { return }
        let alreadyLinked = sections[referencesIndex].items.contains {
            $0.linkedConnectionUUID == ref.uuid || $0.sourceAtomUUID == ref.uuid
        }
        let link = AtomLink(type: AtomLinkType.connection.rawValue, uuid: ref.uuid, entityType: AtomType.connection.rawValue)
        let hasAtomLink = target.linksList.contains { $0.type == link.type && $0.uuid == link.uuid }
        guard !alreadyLinked || !hasAtomLink else { return }

        if !alreadyLinked {
            sections[referencesIndex].items.append(Self.linkItem(to: ref))
            target = target.mergingStructuredKeys(ConnectionStructuredData(sections: sections))
            var state = ConnectionFocusModeState.load(atomUUID: target.uuid)
                ?? ConnectionFocusModeState(atomUUID: target.uuid)
            state.sections = sections
            state.lastModified = Date()
            state.save()
        }
        if !hasAtomLink {
            target = target.withLinks(mergeLinks(target.linksList, [link]))
        }
        _ = try? await atoms.update(target)
    }

    /// True when any non-reference item on the page mentions one of `names`
    /// (normalized containment, short names skipped to avoid noise).
    nonisolated static func connectionMentions(_ atom: Atom, names: [String]) -> Bool {
        let sections = atom.structured.flatMap { ConnectionStructuredData.fromJSON($0)?.sections } ?? []
        let keys = names.map(normalizedKey).filter { $0.count >= 4 }
        guard !keys.isEmpty else { return false }
        for section in sections where section.type != .references {
            for item in section.items {
                let text = normalizedKey(item.resolvedPlainText)
                guard !text.isEmpty else { continue }
                if keys.contains(where: { text.contains($0) }) { return true }
            }
        }
        return false
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
