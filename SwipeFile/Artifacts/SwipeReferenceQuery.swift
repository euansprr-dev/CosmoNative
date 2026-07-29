// CosmoOS/SwipeFile/Artifacts/SwipeReferenceQuery.swift
// Retrieval by ROLE across every kind of swipe.
//
// This is the payoff half of the artifact spine. Capture makes the library
// wider; this makes it usable — "show me three guarantee sections" pulls from
// a sales page, a screenshot of an ad, and a carousel slide alike, because the
// retrievable unit is the SECTION, not the swipe.
//
// The role filter is not a text search. A vector sweep for the word
// "guarantee" finds sections that mention guarantees; a role filter finds
// sections that ARE guarantees, which is a different and much smaller set.

import Foundation

/// One retrieved unit, resolved back to the swipe it belongs to.
struct SwipeUnitHit: Identifiable, Sendable {
    var id: String { "\(swipeUUID)#\(chunkIndex)" }

    let swipeUUID: String
    let swipeTitle: String
    let chunkIndex: Int
    let kind: SwipeKind
    let role: SwipeUnitRole?
    /// The chunk's text, role prefix stripped — what the writer actually reads.
    let text: String
    let similarity: Float

    /// "Guarantee · The Offer" — the attribution line a reference row leads with.
    var attribution: String {
        guard let role else { return swipeTitle }
        return "\(role.displayName) · \(swipeTitle)"
    }
}

@MainActor
enum SwipeReferenceQuery {

    /// Semantic search over swipe units, optionally narrowed by role and kind.
    ///
    /// Over-fetches then filters: the vector sweep has no notion of swipe-ness,
    /// so we ask for a wider band and keep the units that survive the kind and
    /// live-row checks. Deleted swipes never surface — a reference to a swipe
    /// you threw away is worse than no reference.
    static func units(
        matching prompt: String,
        roles: Set<SwipeUnitRole> = [],
        kinds: Set<SwipeKind> = [],
        limit: Int = 8
    ) async -> [SwipeUnitHit] {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard let embedding = try? await RecallEmbedding.embedText(trimmed) else { return [] }

        let hits = await RecallStore.shared.search(
            embedding: embedding,
            // Over-fetch: kind and liveness filters run after the sweep.
            limit: max(limit * 4, 24),
            entityTypes: [AtomType.research.rawValue],
            minSimilarity: 0.05,
            roles: roles.isEmpty ? nil : Set(roles.map(\.rawValue))
        )
        return await resolve(hits, kinds: kinds, limit: limit)
    }

    /// Role-only retrieval, no query — "every guarantee I have saved".
    /// Ordered newest-first, because the most recent example of a move is
    /// usually the one worth copying.
    static func units(
        withRoles roles: Set<SwipeUnitRole>,
        kinds: Set<SwipeKind> = [],
        limit: Int = 8
    ) async -> [SwipeUnitHit] {
        guard !roles.isEmpty else { return [] }
        let wanted = Set(roles.map(\.rawValue))
        let swipes = (try? await AtomRepository.shared.fetchAll(type: .research)) ?? []

        var hits: [SwipeUnitHit] = []
        for atom in swipes.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            guard !atom.isDeleted, atom.isSwipeFileAtom else { continue }
            let kind = atom.swipeKind
            if !kinds.isEmpty, !kinds.contains(kind) { continue }
            for unit in atom.swipeArtifactUnits {
                guard let role = unit.role, wanted.contains(role.rawValue), unit.hasSubstance else { continue }
                hits.append(SwipeUnitHit(
                    swipeUUID: atom.uuid,
                    swipeTitle: atom.title ?? "Swipe",
                    chunkIndex: unit.index,
                    kind: kind,
                    role: role,
                    text: unit.indexableText,
                    similarity: 1
                ))
                if hits.count >= limit { return hits }
            }
        }
        return hits
    }

    /// Roles actually present across the library — what a Role facet should
    /// offer. An empty vocabulary means no artifact has been decomposed yet,
    /// and the facet hides rather than showing 23 dead rows.
    static func availableRoles() async -> Set<SwipeUnitRole> {
        let swipes = (try? await AtomRepository.shared.fetchAll(type: .research)) ?? []
        var roles: Set<SwipeUnitRole> = []
        for atom in swipes where !atom.isDeleted && atom.isSwipeFileAtom {
            roles.formUnion(atom.swipeArtifact?.roles ?? [])
        }
        return roles
    }

    // MARK: - Resolution

    private static func resolve(
        _ hits: [RecallVectorHit],
        kinds: Set<SwipeKind>,
        limit: Int
    ) async -> [SwipeUnitHit] {
        var resolved: [SwipeUnitHit] = []
        var seenSwipes: Set<String> = []

        for hit in hits {
            guard resolved.count < limit else { break }
            guard let atom = try? await AtomRepository.shared.fetch(uuid: hit.entityUuid),
                  !atom.isDeleted, atom.isSwipeFileAtom else { continue }
            let kind = atom.swipeKind
            if !kinds.isEmpty, !kinds.contains(kind) { continue }

            // At most two units from any one swipe: eight sections of the same
            // sales page is not eight references, it is one.
            let alreadyFromThisSwipe = resolved.filter { $0.swipeUUID == atom.uuid }.count
            guard alreadyFromThisSwipe < 2 else { continue }
            seenSwipes.insert(atom.uuid)

            resolved.append(SwipeUnitHit(
                swipeUUID: atom.uuid,
                swipeTitle: atom.title ?? "Swipe",
                chunkIndex: hit.chunkIndex,
                kind: kind,
                role: hit.role.flatMap(SwipeUnitRole.init(rawValue:)),
                text: strippedRolePrefix(hit.text),
                similarity: hit.similarity
            ))
        }
        return resolved
    }

    /// The stored chunk carries `[role] Title — body` so the embedding knows
    /// what it is. A human reading the reference does not need either prefix.
    ///
    /// `nonisolated` — pure string work, and the display side calls it from
    /// wherever a reference row is rendered.
    nonisolated static func strippedRolePrefix(_ text: String) -> String {
        var result = text
        if result.hasPrefix("["), let close = result.firstIndex(of: "]") {
            result = String(result[result.index(after: close)...])
                .trimmingCharacters(in: .whitespaces)
        }
        if let separator = result.range(of: " — "), result.distance(
            from: result.startIndex, to: separator.lowerBound
        ) < 80 {
            result = String(result[separator.upperBound...])
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
