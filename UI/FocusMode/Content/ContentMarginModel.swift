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

    var hasAnyShelf: Bool {
        !concepts.isEmpty || !swipes.isEmpty || !notes.isEmpty
    }

    var totalCount: Int {
        concepts.count + swipes.count + notes.count
    }

    // MARK: - Tuning

    /// Hits below this blended score never surface (silence over noise).
    static let confidenceFloor = 0.28
    static let shelfLimit = 3
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
        let (conceptResults, researchResults, noteResults) = await (conceptHits, researchHits, noteHits)

        // Session-stability: bind results to the atom captured at request time.
        guard requestUUID == boundAtomUUID else { return }

        // Swipe shelf keeps only actual swipe-file atoms.
        let swipeResults = await filterSwipes(researchResults)
        guard requestUUID == boundAtomUUID else { return }

        // Suppress atoms already referenced by the document's inherited context.
        let inherited = Self.inheritedUuids(atom: atom)

        concepts = merged(existing: concepts, incoming: conceptResults, excluding: inherited)
        swipes = merged(existing: swipes, incoming: swipeResults, excluding: inherited)
        notes = merged(existing: notes, incoming: noteResults, excluding: inherited)
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

    private func filterSwipes(_ hits: [RecallHit]) async -> [RecallHit] {
        var out: [RecallHit] = []
        for hit in hits {
            guard let atom = try? await AtomRepository.shared.fetch(uuid: hit.atomUuid),
                  atom.isSwipeFileAtom else { continue }
            out.append(hit)
            if out.count >= Self.shelfLimit * 2 { break }
        }
        return out
    }

    /// Append-only merge (order-lock law): rows the writer can already see
    /// never reorder or vanish mid-session; better matches join at the end.
    private func merged(
        existing: [RecallHit],
        incoming: [RecallHit],
        excluding: Set<String>
    ) -> [RecallHit] {
        var seen = Set(existing.map(\.atomUuid))
        var out = existing
        for hit in incoming {
            guard out.count < Self.shelfLimit else { break }
            guard !seen.contains(hit.atomUuid),
                  !dismissed.contains(hit.atomUuid),
                  !excluding.contains(hit.atomUuid) else { continue }
            seen.insert(hit.atomUuid)
            out.append(hit)
        }
        return Array(out.prefix(Self.shelfLimit))
    }
}

// MARK: - Suggestion Row

/// One Margin suggestion: title, the matched-chunk receipt, and a
/// hover-revealed dismiss. Clicking peeks the atom in a pane.
struct MarginSuggestionRow: View {
    let hit: RecallHit
    let tint: Color
    let typeIcon: String
    var onOpen: () -> Void = {}
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
                    Text(hit.title)
                        .font(DS.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(DS.text)
                        .lineLimit(1)
                    // The receipt: WHY this surfaced (matched chunk excerpt).
                    Text(hit.matchedText)
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isHovered {
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
}
