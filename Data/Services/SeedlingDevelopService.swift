// CosmoOS/Data/Services/SeedlingDevelopService.swift
// Develop a GLOBAL seedling into a Concept page (the Deep Dive seedbed has
// its own dive-scoped flow in ConceptSeedbedService). The page is born
// carrying the user's own captured thoughts — verbatim, never machine-
// composed — as claims to refine in the concept collaborator, which lives on
// every connection workspace. The seedling settles as developed and every
// consumed thought keeps its provenance inside the seedling row.

import Foundation

@MainActor
final class SeedlingDevelopService {
    static let shared = SeedlingDevelopService()

    private init() {}

    /// Reuses the seedling's merge-target page when it feeds an existing
    /// concept; otherwise births the page named after the seedling, seeded
    /// with the pending thoughts in the user's own words. Returns the
    /// connection UUID to open (nil = the seedling vanished under us).
    @discardableResult
    func develop(seedlingUUID: String) async -> String? {
        guard let seedling = try? await SeedlingRepository.shared.fetch(uuid: seedlingUUID),
              !seedling.isDeleted else { return nil }

        // Already developed? Just reopen its page.
        if seedling.status == .developed, let existing = seedling.developedConnectionUUID {
            return existing
        }

        let pending = seedling.pendingThoughts
        let connectionUUID: String

        if let target = seedling.mergeTargetConnectionUUID,
           let existing = try? await AtomRepository.shared.fetch(uuid: target),
           !existing.isDeleted {
            // The seedling feeds a page the user already shaped — thoughts
            // STAGE as pending ghost rows (✓/✗ in the workspace); a page you
            // shaped by hand is never silently edited by a pipeline.
            connectionUUID = existing.uuid
            for thought in pending {
                _ = try? await ConnectionStagingStore.stage(
                    ConnectionStagedInsert(
                        section: ConnectionSectionType.claims.rawValue,
                        text: thought.text,
                        sourceKind: "seedling",
                        sourceUUID: seedling.uuid
                    ),
                    onConnection: existing.uuid
                )
            }
        } else {
            var structured = ConnectionStructuredData(sections: [])
            if !pending.isEmpty {
                structured.sections.append(ConnectionSection(
                    type: .claims,
                    items: pending.map { ConnectionItem(content: $0.text) }
                ))
            }
            var atom = Atom.new(type: .connection, title: seedling.name, body: nil)
            atom.structured = structured.toJSON()
            atom = atom.mergingMetadataKeys(["sourceSeedlingUuid": seedling.uuid])
            guard let created = try? await AtomRepository.shared.create(atom) else { return nil }
            connectionUUID = created.uuid
        }

        // The bookshelf rides along: the strongest matching Readwise
        // highlights stage as ✓/✗ ghost rows under Evidence — offered, never
        // auto-filed, and capped so a well-read concept doesn't drown its
        // own birth. Threshold-gated: no match, no rows.
        let bookshelf = await ReadwiseEvidenceMatcher.evidence(
            conceptName: seedling.name,
            aliases: seedling.aliases,
            limit: 3
        )
        for match in bookshelf {
            let citation = match.author.map { "\(match.bookTitle) — \($0)" } ?? match.bookTitle
            _ = try? await ConnectionStagingStore.stage(
                ConnectionStagedInsert(
                    section: ConnectionSectionType.evidence.rawValue,
                    text: "\u{201C}\(match.text)\u{201D} — \(citation)",
                    sourceKind: "readwise",
                    sourceUUID: match.bookUUID
                ),
                onConnection: connectionUUID
            )
        }

        try? await SeedlingRepository.shared.markDeveloped(uuid: seedling.uuid, connectionUUID: connectionUUID)
        return connectionUUID
    }
}
