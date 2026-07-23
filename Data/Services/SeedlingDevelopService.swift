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
        var bornPage: Atom?

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
            bornPage = created
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

        // The concept lands where it belongs: a page born from a seedling
        // whose affinity names a home gets a canvas block there — "develop
        // later" still ends with the concept living in its space. A
        // merge-target page the user already shaped keeps whatever spatial
        // life it has — but a grow-pill development stub (this seedling's own
        // page, still unplaced) earns its spot exactly now.
        if let homeThinkspaceId = seedling.affinityThinkspaceId {
            if let bornPage {
                await InboxActionExecutor.shared.placeExistingAtomOnCanvas(
                    atom: bornPage,
                    thinkspaceId: homeThinkspaceId
                )
            } else if let target = try? await AtomRepository.shared.fetch(uuid: connectionUUID),
                      Self.isDevelopmentStub(target, seedlingUUID: seedling.uuid),
                      await Self.hasNoCanvasBlock(atomUUID: connectionUUID) {
                await InboxActionExecutor.shared.placeExistingAtomOnCanvas(
                    atom: target,
                    thinkspaceId: homeThinkspaceId
                )
            }
        }

        // Mint provenance rides into the graph: the born page references the
        // concepts it was spotted in, and each origin gets a staged ghost
        // References row back. (Merge-target pages skip this — user-shaped
        // pages only ever receive staged material.)
        if let bornPage {
            await SeedlingMintWiring.wire(
                bornPage: bornPage,
                thoughts: seedling.thoughts,
                seedlingUUID: seedling.uuid
            )
        }

        try? await SeedlingRepository.shared.markDeveloped(uuid: seedling.uuid, connectionUUID: connectionUUID)
        return connectionUUID
    }

    /// A development-stage stub is THIS seedling's own address page (created
    /// by the grow pill), never a page the user shaped independently — only
    /// stubs may be auto-placed at develop time.
    private nonisolated static func isDevelopmentStub(_ atom: Atom, seedlingUUID: String) -> Bool {
        atom.metadataValue(as: SourceSeedlingOverlay.self)?.sourceSeedlingUuid == seedlingUUID
    }

    private struct SourceSeedlingOverlay: Codable {
        var sourceSeedlingUuid: String?
    }

    private static func hasNoCanvasBlock(atomUUID: String) async -> Bool {
        let count = (try? await CosmoDatabase.shared.asyncRead { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM canvas_blocks WHERE entity_uuid = ? AND COALESCE(is_deleted, 0) = 0",
                arguments: [atomUUID]
            )
        }) ?? nil
        return (count ?? 1) == 0
    }
}

// MARK: - Mint wiring (spotted-in provenance → graph)

/// Wires a seedling-born page back to the concepts its `.mint` thoughts were
/// spotted in: References link rows + atom links on the BORN page (fresh —
/// nothing holds its editing lock), and a staged ghost References row on each
/// origin (usually closed, always user-shaped — reviewed ✓/✗, never silently
/// edited). Shared by both develop paths: the unrooted shelf's
/// SeedlingDevelopService and the dive seedbed's ConceptSeedbedService.
@MainActor
enum SeedlingMintWiring {

    /// Distinct origin connection uuids across `.mint` thoughts, oldest first.
    nonisolated static func mintOrigins(from thoughts: [SeedlingThought]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for thought in thoughts where thought.sourceKind == .mint {
            guard let uuid = thought.sourceAtomUUID, seen.insert(uuid).inserted else { continue }
            out.append(uuid)
        }
        return out
    }

    static func wire(bornPage: Atom, thoughts: [SeedlingThought], seedlingUUID: String) async {
        let origins = mintOrigins(from: thoughts)
        guard !origins.isEmpty else { return }

        var resolved: [(uuid: String, title: String)] = []
        for uuid in origins {
            if let atom = try? await AtomRepository.shared.fetch(uuid: uuid),
               atom.type == .connection, !atom.isDeleted {
                resolved.append((uuid, atom.title ?? "Untitled Concept"))
            }
        }
        guard !resolved.isEmpty else { return }

        // The born page: References rows + graph links.
        if var page = try? await AtomRepository.shared.fetch(uuid: bornPage.uuid) {
            var sections = ConnectionFocusModeState.backfillingMissingSections(
                page.structured.flatMap { ConnectionStructuredData.fromJSON($0)?.sections } ?? []
            )
            if let refIdx = sections.firstIndex(where: { $0.type == .references }) {
                for origin in resolved
                where !sections[refIdx].items.contains(where: { $0.linkedConnectionUUID == origin.uuid }) {
                    sections[refIdx].items.append(ConnectionItem(
                        content: origin.title,
                        sourceAtomUUID: origin.uuid,
                        sourceSnippet: "Spotted while developing this concept.",
                        linkedConnectionUUID: origin.uuid
                    ))
                }
            }
            page = page.mergingStructuredKeys(ConnectionStructuredData(sections: sections))
            var links = page.linksList
            for origin in resolved
            where !links.contains(where: { $0.type == AtomLinkType.connection.rawValue && $0.uuid == origin.uuid }) {
                links.append(AtomLink(
                    type: AtomLinkType.connection.rawValue,
                    uuid: origin.uuid,
                    entityType: AtomType.connection.rawValue
                ))
            }
            page = page.withLinks(links)
            if let saved = try? await AtomRepository.shared.update(page) {
                var state = ConnectionFocusModeState.load(atomUUID: saved.uuid)
                    ?? ConnectionFocusModeState(atomUUID: saved.uuid)
                state.sections = sections
                state.lastModified = Date()
                state.save()
            }
        }

        // Each origin: a staged ghost References row pointing back — the
        // mention token becomes a first-class link row on accept.
        let bornTitle = bornPage.title ?? "Untitled Concept"
        for origin in resolved {
            _ = try? await ConnectionStagingStore.stage(
                ConnectionStagedInsert(
                    section: ConnectionSectionType.references.rawValue,
                    text: "@[\(bornTitle)](connection:\(bornPage.uuid))",
                    sourceKind: "seedling",
                    sourceUUID: seedlingUUID
                ),
                onConnection: origin.uuid
            )
        }
    }
}
