// CosmoOS/UI/CommandK/CommandKSearchLanding.swift
// Jump-to-sentence: when a ⌘K result was matched by body text, opening it
// should land ON that text, not at the top of the document.
//
// The palette stages a landing right before posting openAtomFromCommandK;
// the destination surface consumes it (one-shot, TTL-guarded) once its
// content is mounted and scrolls to / highlights the matched passage.
// Surfaces that don't consume simply open normally — a landing is an
// enhancement, never a gate.

import Foundation

// MARK: - Landing

struct CommandKSearchLanding: Equatable {
    let atomUUID: String
    /// Verbatim-ish context window from the search result (may carry edge
    /// ellipses). The strongest anchor: it names the exact region.
    let excerpt: String?
    /// The raw query, for re-matching when the excerpt can't be located
    /// (content edited since indexing, excerpt spanning block boundaries).
    let query: String
    let stagedAt: Date
}

// MARK: - Store

/// One pending landing at a time — the user opens one result. Consumption is
/// keyed by atom UUID so an unrelated surface appearing (a pane, a sidebar
/// editor) can't steal another atom's landing.
@MainActor
final class CommandKSearchLandingStore {
    static let shared = CommandKSearchLandingStore()

    /// A landing older than this is stale — the open it belonged to either
    /// happened long ago or never happened. Never fire it.
    private let timeToLive: TimeInterval = 15

    private var pending: CommandKSearchLanding?

    init() {}

    func stage(atomUUID: String, excerpt: String?, query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !atomUUID.isEmpty, !trimmedQuery.isEmpty else { return }
        pending = CommandKSearchLanding(
            atomUUID: atomUUID,
            excerpt: excerpt,
            query: trimmedQuery,
            stagedAt: Date()
        )
    }

    /// One-shot: the landing is cleared on first successful consume.
    func consume(for atomUUID: String) -> CommandKSearchLanding? {
        guard let landing = pending, landing.atomUUID == atomUUID else { return nil }
        guard Date().timeIntervalSince(landing.stagedAt) <= timeToLive else {
            pending = nil
            return nil
        }
        pending = nil
        return landing
    }

    func clear() {
        pending = nil
    }
}

// MARK: - Block Locator

/// Resolves a landing to the block that holds the matched passage in a
/// block-editor document. Excerpts come from the atom's joined plain text,
/// so they can span block boundaries — the locator scores blocks by how
/// much of the excerpt they carry instead of demanding a literal match.
enum CommandKSearchLandingLocator {
    /// Minimum fraction of excerpt tokens a block must carry to win by
    /// overlap. Below this, fall through to query-token matching.
    private static let overlapFloor = 0.4

    static func blockID(for landing: CommandKSearchLanding, in blocks: [RichBlock]) -> UUID? {
        let candidates = flatten(blocks)
        guard !candidates.isEmpty else { return nil }

        let normalizedQuery = CommandKSearchMatcher.normalizeQuery(landing.query)

        // 1. The whole query as a contiguous phrase inside one block — the
        //    unambiguous winner.
        let queryTokens = normalizedQuery.split(separator: " ")
        if queryTokens.count > 1 {
            if let hit = candidates.first(where: { $0.text.contains(normalizedQuery) }) {
                return hit.id
            }
        }

        // 2. Token overlap with the excerpt: the excerpt is one contiguous
        //    region of the document, so the block carrying most of its words
        //    is where the match lives (even when the region straddles a
        //    block boundary).
        if let excerpt = landing.excerpt {
            let excerptTokens = meaningfulTokens(in: excerpt)
            if !excerptTokens.isEmpty {
                var best: (id: UUID, score: Double)?
                for candidate in candidates {
                    let carried = excerptTokens.filter { candidate.text.contains($0) }
                    let score = Double(carried.count) / Double(excerptTokens.count)
                    if score >= overlapFloor, score > (best?.score ?? 0) {
                        best = (candidate.id, score)
                    }
                }
                if let best { return best.id }
            }
        }

        // 3. Any query token — better than landing at the top.
        let meaningfulQueryTokens = meaningfulTokens(in: landing.query)
        return candidates.first { candidate in
            meaningfulQueryTokens.contains { candidate.text.contains($0) }
        }?.id
    }

    /// Normalized tokens worth matching on: 3+ characters, so "the"/"of"/"a"
    /// can't crown the wrong block.
    private static func meaningfulTokens(in text: String) -> [String] {
        CommandKSearchMatcher.normalize(text.trimmingCharacters(in: CharacterSet(charactersIn: "…")))
            .split(separator: " ")
            .filter { $0.count >= 3 }
            .map(String.init)
    }

    /// Candidates are keyed by their TOP-LEVEL block id: nested children
    /// (toggle/element bodies) have no scroll anchor of their own in the
    /// host's block list, so a match inside one reveals its root row. Each
    /// candidate keeps per-block text so scoring stays granular.
    private static func flatten(_ blocks: [RichBlock]) -> [(id: UUID, text: String)] {
        var result: [(id: UUID, text: String)] = []
        func walk(_ blocks: [RichBlock], rootID: UUID?) {
            for block in blocks {
                let anchorID = rootID ?? block.id
                let text = CommandKSearchMatcher.normalize(
                    block.inlines.map(\.plainText).joined()
                )
                if !text.isEmpty {
                    result.append((anchorID, text))
                }
                if !block.children.isEmpty {
                    walk(block.children, rootID: anchorID)
                }
            }
        }
        walk(blocks, rootID: nil)
        return result
    }
}
