// CosmoOS/Data/ConceptMediaAttachService.swift
// Attach media to a concept from OUTSIDE its open workspace: the swipe quick
// look's "Add to concept", the preview sidebar, ⌘K, the agent's attach_media
// tool, and Slack/iOS mirrors all route through here. Writes are idempotent
// per (concept, source atom) and merge-not-replace on the structured column;
// a mediaChanged notification lets any open workspace fold the new ref into
// live state instead of clobbering it on its next save.

import Foundation

@MainActor
enum ConceptMediaAttachService {

    @discardableResult
    static func attach(
        sourceAtomUUID: String,
        toConcept conceptUUID: String,
        anchorSection: ConnectionSectionType? = nil,
        timestampSeconds: Double? = nil
    ) async -> Bool {
        guard sourceAtomUUID != conceptUUID,
              let source = try? await AtomRepository.shared.fetch(uuid: sourceAtomUUID),
              !source.isDeleted,
              let concept = try? await AtomRepository.shared.fetch(uuid: conceptUUID),
              !concept.isDeleted, concept.type == .connection else { return false }

        let existing = concept.structured.flatMap(ConnectionStructuredData.fromJSON)
        var media = existing?.media ?? []
        if media.contains(where: { $0.atomUUID == sourceAtomUUID }) {
            return true // already on the board — attach is idempotent
        }

        var ref = ConnectionMediaItem.ref(
            for: source,
            anchorSection: anchorSection,
            timestampSeconds: timestampSeconds
        )
        ref.sortOrder = (media.map(\.sortOrder).max() ?? -1) + 1
        media.append(ref)

        // Overlay ONLY the media key — sections stay whatever the column
        // holds (an open workspace may have fresher sections in flight).
        let updated = concept.mergingStructuredKeys(MediaOnlyOverlay(media: media))
        do {
            _ = try AtomRepository.shared.updateSync(updated)
        } catch {
            PersistenceHealth.note(
                .writeFailure,
                context: "ConceptMediaAttachService.attach(\(conceptUUID.prefix(8)))",
                detail: error.localizedDescription
            )
            return false
        }

        NotificationCenter.default.post(
            name: CosmoNotification.Connection.mediaChanged,
            object: nil,
            userInfo: ["connectionUUID": conceptUUID]
        )
        await writeGraphEdge(source: source, conceptUUID: conceptUUID)
        return true
    }

    /// Bidirectional `related` links between the media source and the concept
    /// so the Sources rail, connectedSources, and swipe-side back-links all
    /// see the relationship. Idempotent; refuses corrupt links columns.
    static func writeGraphEdge(source: Atom, conceptUUID: String) async {
        guard !source.linksAreCorrupt else { return }
        var updatedSource = source
        let hasConceptLink = updatedSource.linksList.contains { $0.uuid == conceptUUID }
        if !hasConceptLink {
            updatedSource = updatedSource.addingLink(.related(conceptUUID, entityType: .connection))
            try? await AtomRepository.shared.update(updatedSource)
        }
        if var concept = try? await AtomRepository.shared.fetch(uuid: conceptUUID),
           !concept.linksAreCorrupt,
           !concept.linksList.contains(where: { $0.uuid == source.uuid }) {
            concept = concept.addingLink(.related(source.uuid, entityType: source.type))
            try? await AtomRepository.shared.update(concept)
        }
        NotificationCenter.default.post(
            name: CosmoNotification.Connection.referencesChanged,
            object: nil,
            userInfo: ["originUUID": conceptUUID, "connectionUUID": source.uuid]
        )
    }

    /// Encodes just the media key so `mergingStructuredKeys` can't disturb
    /// sections written by an open workspace.
    private struct MediaOnlyOverlay: Encodable {
        let media: [ConnectionMediaItem]
    }

    /// Recent concept pages for "Add to concept…" menus, most recently
    /// touched first.
    static func recentConcepts(limit: Int = 8) async -> [Atom] {
        guard let atoms = try? await AtomRepository.shared.fetchAll(type: .connection) else { return [] }
        return atoms
            .filter { !$0.isDeleted }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { $0 }
    }
}
