// CosmoOS/UI/FocusMode/Content/ContentMarginModel.swift
// The Margin — ambient recall while writing. Watches the draft and quietly
// keeps three shelves current (Concepts / Swipes / Notes & Ideas) from the
// Recall index. Design contract: SILENCE OVER NOISE — a shelf below the
// confidence floor renders nothing; dismissed suggestions never return for
// this document; visible order is append-only while the panel is open (the
// ⌘K order-lock law); zero LLM calls on the typing path (embeddings only).
// July 2026

import SwiftUI

@MainActor
@Observable
final class ContentMarginModel {

    // MARK: - Shelves

    private(set) var concepts: [RecallHit] = []
    private(set) var swipes: [RecallHit] = []
    private(set) var notes: [RecallHit] = []
    private(set) var isRefreshing = false
    /// Receipts for own published posts on the Swipes shelf ("yours · 12.4K views").
    private(set) var perfBadges: [String: String] = [:]
    /// One explicit "Find more" expansion has run for the current signature.
    private(set) var didExpand = false

    var hasAnyShelf: Bool {
        !concepts.isEmpty || !swipes.isEmpty || !notes.isEmpty
    }

    var totalCount: Int {
        concepts.count + swipes.count + notes.count
    }

    // MARK: - Tuning

    /// Hits below this blended score never surface (silence over noise).
    nonisolated static let confidenceFloor = 0.28
    nonisolated static let shelfLimit = 3
    /// Draft must grow by this many words before a re-query fires.
    static let minNewWords = 40
    static let debounce: Duration = .seconds(2)

    // MARK: - Session State

    @ObservationIgnored private var boundAtomUUID: String?
    @ObservationIgnored private var dismissed: Set<String> = []
    @ObservationIgnored private var lastQuerySignature: String = ""
    @ObservationIgnored private var lastDraftWordCount = 0
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var clientNiche: String?

    // MARK: - Lifecycle

    /// Bind to a document. Results are keyed to this UUID at request time —
    /// a quick atom switch can never bleed suggestions across documents.
    func bind(atomUUID: String) {
        guard boundAtomUUID != atomUUID else { return }
        boundAtomUUID = atomUUID
        concepts = []
        swipes = []
        notes = []
        perfBadges = [:]
        didExpand = false
        lastQuerySignature = ""
        lastDraftWordCount = 0
        clientNiche = nil
        dismissed = Set(
            UserDefaults.standard.stringArray(forKey: Self.dismissedKey(atomUUID)) ?? []
        )
    }

    /// Debounced draft-change signal: refresh only after a typing pause AND
    /// meaningful growth, so the rail follows the writing without churning.
    func noteDraftChanged(atom: Atom, state: ContentFocusModeState) {
        let words = state.draftContent
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        guard abs(words - lastDraftWordCount) >= Self.minNewWords else { return }

        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            await self?.refresh(atom: atom, state: state)
        }
    }

    func dismiss(_ hit: RecallHit) {
        guard let boundAtomUUID else { return }
        dismissed.insert(hit.atomUuid)
        UserDefaults.standard.set(Array(dismissed), forKey: Self.dismissedKey(boundAtomUUID))
        concepts.removeAll { $0.atomUuid == hit.atomUuid }
        swipes.removeAll { $0.atomUuid == hit.atomUuid }
        notes.removeAll { $0.atomUuid == hit.atomUuid }
    }

    private static func dismissedKey(_ uuid: String) -> String {
        "margin.dismissed.\(uuid)"
    }

    // MARK: - Refresh

    func refresh(atom: Atom, state: ContentFocusModeState) async {
        let requestUUID = atom.uuid
        guard requestUUID == boundAtomUUID else { return }

        let query = Self.intentQuery(atom: atom, state: state, niche: await resolvedNiche(atom: atom))
        guard !query.isEmpty else { return }
        // Unchanged signal → unchanged shelves; don't re-bill the query embed.
        guard query != lastQuerySignature else { return }
        lastQuerySignature = query
        didExpand = false  // a new intent gets a fresh "Find more"
        lastDraftWordCount = state.draftContent
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count

        isRefreshing = true
        defer { isRefreshing = false }

        async let conceptHits = RecallEngine.shared.query(RecallQuery(
            text: query, types: [.connection], limit: 6,
            excludeUuids: [requestUUID], minScore: Self.confidenceFloor
        ))
        async let researchHits = RecallEngine.shared.query(RecallQuery(
            text: query, types: [.research], limit: 8,
            excludeUuids: [requestUUID], minScore: Self.confidenceFloor
        ))
        async let noteHits = RecallEngine.shared.query(RecallQuery(
            text: query, types: [.note, .idea], limit: 6,
            excludeUuids: [requestUUID], minScore: Self.confidenceFloor
        ))
        async let ownPostHits = RecallEngine.shared.query(RecallQuery(
            text: query, types: [.content], limit: 6,
            excludeUuids: [requestUUID], minScore: Self.confidenceFloor
        ))
        let (conceptResults, researchResults, noteResults, ownPostResults) =
            await (conceptHits, researchHits, noteHits, ownPostHits)

        // Session-stability: bind results to the atom captured at request time.
        guard requestUUID == boundAtomUUID else { return }

        // Swipe shelf: semantic score × format match × engagement percentile,
        // with published own posts joining the pool (max 1 slot).
        let intentFormat = atom.metadataValue(as: ContentAtomMetadata.self)?.contentFormat
            .flatMap(ContentFormat.init(rawValue:))
        let (swipeResults, badges) = await rankSwipeShelf(
            swipeHits: researchResults,
            ownPostHits: ownPostResults,
            intentFormat: intentFormat
        )
        guard requestUUID == boundAtomUUID else { return }

        // Suppress atoms already referenced by the document's inherited context.
        let inherited = Self.inheritedUuids(atom: atom)

        concepts = merged(existing: concepts, incoming: conceptResults, excluding: inherited)
        swipes = merged(existing: swipes, incoming: swipeResults, excluding: inherited)
        notes = merged(existing: notes, incoming: noteResults, excluding: inherited)
        perfBadges.merge(badges) { _, new in new }
    }

    /// One explicit expansion: a wider, lower-floor query whose results join
    /// append-only. User-invoked — never on the typing path.
    func findMore(atom: Atom, state: ContentFocusModeState) async {
        guard !didExpand, atom.uuid == boundAtomUUID else { return }
        didExpand = true
        let query = Self.intentQuery(atom: atom, state: state, niche: await resolvedNiche(atom: atom))
        guard !query.isEmpty else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        let floor = Self.confidenceFloor * 0.75
        async let conceptHits = RecallEngine.shared.query(RecallQuery(
            text: query, types: [.connection], limit: 8,
            excludeUuids: [atom.uuid], minScore: floor
        ))
        async let noteHits = RecallEngine.shared.query(RecallQuery(
            text: query, types: [.note, .idea], limit: 8,
            excludeUuids: [atom.uuid], minScore: floor
        ))
        async let researchHits = RecallEngine.shared.query(RecallQuery(
            text: query, types: [.research], limit: 10,
            excludeUuids: [atom.uuid], minScore: floor
        ))
        let (conceptResults, noteResults, researchResults) = await (conceptHits, noteHits, researchHits)
        guard atom.uuid == boundAtomUUID else { return }

        let intentFormat = atom.metadataValue(as: ContentAtomMetadata.self)?.contentFormat
            .flatMap(ContentFormat.init(rawValue:))
        let (swipeResults, badges) = await rankSwipeShelf(
            swipeHits: researchResults, ownPostHits: [], intentFormat: intentFormat
        )
        guard atom.uuid == boundAtomUUID else { return }

        let inherited = Self.inheritedUuids(atom: atom)
        concepts = merged(existing: concepts, incoming: conceptResults, excluding: inherited, limit: Self.shelfLimit + 2)
        swipes = merged(existing: swipes, incoming: swipeResults, excluding: inherited, limit: Self.shelfLimit + 2)
        notes = merged(existing: notes, incoming: noteResults, excluding: inherited, limit: Self.shelfLimit + 2)
        perfBadges.merge(badges) { _, new in new }
    }

    // MARK: - Query Building

    /// The intent signal that beats the cold start: title + dek (core idea) +
    /// format + client niche are available before a word of draft exists; the
    /// draft gist joins as the manuscript grows.
    static func intentQuery(atom: Atom, state: ContentFocusModeState, niche: String?) -> String {
        var parts: [String] = []
        if let title = atom.title, !title.isEmpty { parts.append(title) }
        if !state.coreIdea.isEmpty { parts.append(state.coreIdea) }
        if let format = atom.metadataValue(as: ContentAtomMetadata.self)?.contentFormat,
           !format.isEmpty {
            parts.append(format)
        }
        if let niche, !niche.isEmpty { parts.append(niche) }

        let draft = state.draftContent
        if draft.count > 80 {
            // Gist = opening + the live tail (where the writing is happening).
            parts.append(String(draft.prefix(200)))
            if draft.count > 600 { parts.append(String(draft.suffix(400))) }
        }
        return parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolvedNiche(atom: Atom) async -> String? {
        if let clientNiche { return clientNiche }
        guard let clientUUID = atom.metadataValue(as: ContentAtomMetadata.self)?.clientProfileUUID,
              let client = try? await AtomRepository.shared.fetch(uuid: clientUUID),
              let meta = client.metadataValue(as: ClientProfileMetadata.self)
        else { return nil }
        clientNiche = meta.niche
        return clientNiche
    }

    private static func inheritedUuids(atom: Atom) -> Set<String> {
        var out: Set<String> = [atom.uuid]
        if let meta = atom.metadataValue(as: ContentAtomMetadata.self) {
            if let swipes = meta.inheritedSwipeUUIDs { out.formUnion(swipes) }
            if let connections = meta.inheritedConnectionIds { out.formUnion(connections) }
            if let idea = meta.sourceIdeaUUID { out.insert(idea) }
        }
        return out
    }

    // MARK: - Swipe Shelf Ranking

    /// A candidate on the swipe shelf with everything the ranking needs.
    struct SwipeCandidate {
        let hit: RecallHit
        let format: ContentFormat?
        /// Engagement rate when real numbers exist; nil ranks neutral.
        let engagementRate: Double?
        let views: Int?
        let isOwnPost: Bool
    }

    /// Format affinity: exact format 1.0, same family 0.85, other family 0.6,
    /// unknown on either side 0.8 (neutral — never punish missing data hard).
    nonisolated static func formatMultiplier(intent: ContentFormat?, candidate: ContentFormat?) -> Double {
        guard let intent, let candidate else { return 0.8 }
        if intent == candidate { return 1.0 }
        return FormatGroup.group(for: intent) == FormatGroup.group(for: candidate) ? 0.85 : 0.6
    }

    /// Engagement percentile computed WITHIN the candidate set — performance
    /// ranks already-relevant results, it never filters the library globally
    /// (the all-swipes-are-curated rule). Missing numbers rank neutral (0.5).
    nonisolated static func engagementPercentiles(_ rates: [Double?]) -> [Double] {
        let known = rates.compactMap { $0 }.sorted()
        guard known.count > 1 else { return rates.map { _ in 0.5 } }
        return rates.map { rate in
            guard let rate else { return 0.5 }
            let below = known.lastIndex(where: { $0 <= rate }).map { $0 + 1 } ?? 0
            return Double(below) / Double(known.count)
        }
    }

    /// Blend: semantic relevance × format match × (0.5 + percentile/2).
    /// The engagement term sways within [0.5, 1.0] so a mediocre-performing
    /// but perfectly-relevant swipe still beats an off-topic viral one.
    nonisolated static func rank(_ candidates: [SwipeCandidate], intentFormat: ContentFormat?) -> [SwipeCandidate] {
        let percentiles = engagementPercentiles(candidates.map(\.engagementRate))
        return zip(candidates, percentiles)
            .map { candidate, percentile -> (SwipeCandidate, Double) in
                let score = candidate.hit.score
                    * formatMultiplier(intent: intentFormat, candidate: candidate.format)
                    * (0.5 + percentile / 2)
                return (candidate, score)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    /// Build + rank the swipe shelf pool: real swipes from the research hits,
    /// plus the writer's own PUBLISHED posts (real snapshot numbers) capped at
    /// one slot so the shelf stays a study surface, not a mirror.
    private func rankSwipeShelf(
        swipeHits: [RecallHit],
        ownPostHits: [RecallHit],
        intentFormat: ContentFormat?
    ) async -> (hits: [RecallHit], badges: [String: String]) {
        var candidates: [SwipeCandidate] = []

        for hit in swipeHits.prefix(Self.shelfLimit * 3) {
            guard let atom = try? await AtomRepository.shared.fetch(uuid: hit.atomUuid),
                  atom.isSwipeFileAtom else { continue }
            let analysis = atom.swipeAnalysis
            candidates.append(SwipeCandidate(
                hit: hit,
                format: analysis?.swipeContentFormat,
                engagementRate: analysis?.engagementRate,
                views: analysis?.viewsCount,
                isOwnPost: false
            ))
        }

        var badges: [String: String] = [:]
        var ownCandidates: [SwipeCandidate] = []
        for hit in ownPostHits.prefix(4) {
            guard let atom = try? await AtomRepository.shared.fetch(uuid: hit.atomUuid) else { continue }
            let published = !ContentPublishStore.records(for: atom).isEmpty
                || atom.metadataValue(as: ContentMetadata.self)?.status == "published"
            guard published else { continue }
            let snapshots = await ContentPerfStore.snapshots(forContent: atom.uuid)
            guard let latest = snapshots.first else { continue }
            ownCandidates.append(SwipeCandidate(
                hit: hit,
                format: atom.metadataValue(as: ContentAtomMetadata.self)?.contentFormat
                    .flatMap(ContentFormat.init(rawValue:)),
                engagementRate: latest.engagementRate,
                views: latest.views,
                isOwnPost: true
            ))
            badges[hit.atomUuid] = "yours · \(Self.compactCount(latest.views)) views"
        }

        // Own posts share the pool but claim at most ONE visible slot.
        let ranked = Self.rank(candidates + ownCandidates, intentFormat: intentFormat)
        var out: [RecallHit] = []
        var ownUsed = 0
        for candidate in ranked {
            if candidate.isOwnPost {
                guard ownUsed == 0 else { continue }
                ownUsed += 1
            }
            out.append(candidate.hit)
            if out.count >= Self.shelfLimit * 2 { break }
        }
        return (out, badges)
    }

    nonisolated static func compactCount(_ value: Int) -> String {
        switch value {
        case 1_000_000...: return String(format: "%.1fM", Double(value) / 1_000_000)
        case 10_000...: return String(format: "%.0fK", Double(value) / 1_000)
        case 1_000...: return String(format: "%.1fK", Double(value) / 1_000)
        default: return "\(value)"
        }
    }

    /// Append-only merge (order-lock law): rows the writer can already see
    /// never reorder or vanish mid-session; better matches join at the end.
    private func merged(
        existing: [RecallHit],
        incoming: [RecallHit],
        excluding: Set<String>,
        limit: Int = ContentMarginModel.shelfLimit
    ) -> [RecallHit] {
        var seen = Set(existing.map(\.atomUuid))
        var out = existing
        for hit in incoming {
            guard out.count < limit else { break }
            guard !seen.contains(hit.atomUuid),
                  !dismissed.contains(hit.atomUuid),
                  !excluding.contains(hit.atomUuid) else { continue }
            seen.insert(hit.atomUuid)
            out.append(hit)
        }
        return Array(out.prefix(limit))
    }
}

// MARK: - Suggestion Row

/// One Margin suggestion: title, the matched-chunk receipt, and a
/// hover-revealed dismiss. Clicking peeks the atom in a pane.
struct MarginSuggestionRow: View {
    let hit: RecallHit
    let tint: Color
    let typeIcon: String
    /// "yours · 12.4K views" on own published posts; nil otherwise.
    var perfBadge: String?
    var onOpen: () -> Void = {}
    var onReference: (() -> Void)?
    var onDismiss: () -> Void = {}

    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: typeIcon)
                    .font(DS.caption2)
                    .foregroundStyle(tint)
                    .frame(width: 14)
                    .padding(.top, 1)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    titleLine
                    // The receipt: WHY this surfaced (matched chunk excerpt).
                    Text(hit.matchedText)
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isHovered {
                    hoverActions
                }
            }
            .padding(8)
            .background(
                isHovered ? DS.surfaceElevated : Color.clear,
                in: .rect(cornerRadius: 8)
            )
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .accessibilityLabel("\(hit.title). \(hit.matchedText)")
    }

    private var titleLine: some View {
        HStack(spacing: 4) {
            Text(hit.title)
                .font(DS.caption)
                .fontWeight(.medium)
                .foregroundStyle(DS.text)
                .lineLimit(1)
            if let page = hit.page {
                Text("p. \(page)")
                    .font(DS.caption2.monospacedDigit())
                    .foregroundStyle(DS.textMuted)
            }
            if let perfBadge {
                Text(perfBadge)
                    .font(DS.caption2.monospacedDigit())
                    .foregroundStyle(DS.gilt)
            }
        }
    }

    private var hoverActions: some View {
        HStack(spacing: 4) {
            if let onReference {
                Button(action: onReference) {
                    Image(systemName: "at")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DS.textMuted)
                        .frame(width: 16, height: 16)
                        .background(DS.border.opacity(0.5), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Reference — insert a mention pill at the caret")
                .accessibilityLabel("Insert reference")
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 16, height: 16)
                    .background(DS.border.opacity(0.5), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Don't suggest this here again")
            .accessibilityLabel("Dismiss suggestion")
        }
        .transition(.opacity)
    }
}
