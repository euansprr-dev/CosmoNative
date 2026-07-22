// CosmoOS/UI/FocusMode/Connection/ConceptRecommendationModel.swift
// The Material rail — ambient recall while developing a concept. Replaces the
// old Live Insights panel with receipts-based recommendations drawn from the
// whole library: book highlights (Readwise), inquiry moments (extracts and
// questions), research, adjacent concepts, notes and ideas, and inbox captures.
//
// Design contract (inherits the Margin's laws, July 2026):
// - GATED: nothing surfaces until the concept has started developing — the
//   query would be vibes, not intent. The gate names the fastest unlock.
// - EVOLVING: the rail computes what the concept is hungry for next (the
//   "seeking" section) from what's filled and what's empty; the seek joins
//   the query and re-targets suggestions as sections fill.
// - SILENCE OVER NOISE: hits below the floor render nothing; dismissed rows
//   never return for this concept; material already woven into a section is
//   excluded by provenance.
// - ORDER LOCK: visible rows never reorder or vanish mid-session — fresh
//   matches append. Zero LLM calls; embeddings + deterministic scoring only.

import SwiftUI

// MARK: - Origin

/// Where a recommendation came from. Drives the row's mark, label, and tint.
enum ConceptRecommendationOrigin: String, CaseIterable, Sendable {
    case book       // Readwise mirror highlight
    case inquiry    // extract / question atoms from inquiry sessions
    case concept    // another connection page
    case research   // web/PDF research atoms (non-book, non-swipe)
    case swipe      // swipe-file post (real-world example material)
    case note       // notes, ideas, sticky notes
    case inbox      // inbox captures, present and past

    var label: String {
        switch self {
        case .book: return "Book"
        case .inquiry: return "Inquiry"
        case .concept: return "Concept"
        case .research: return "Research"
        case .swipe: return "Swipe"
        case .note: return "Note"
        case .inbox: return "Inbox"
        }
    }

    var icon: String {
        switch self {
        case .book: return "text.book.closed"
        case .inquiry: return "questionmark.bubble"
        case .concept: return "point.3.connected.trianglepath.dotted"
        case .research: return "doc.text.magnifyingglass"
        case .swipe: return "rectangle.stack"
        case .note: return "note.text"
        case .inbox: return "tray"
        }
    }

    var tint: Color {
        switch self {
        case .book: return DS.entityReadwise
        case .inquiry: return DS.entityIdea
        case .concept: return DS.entityConnection
        case .research: return DS.entityResearch
        case .swipe: return DS.entitySwipe
        case .note: return DS.entityNote
        case .inbox: return DS.gilt
        }
    }
}

// MARK: - Recommendation

/// One row on the rail: a receipt (why it surfaced), provenance, and a
/// suggested landing section.
struct ConceptRecommendation: Identifiable, Equatable, Sendable {
    /// Stable dedup key — also the persisted dismissal key.
    let id: String
    let origin: ConceptRecommendationOrigin
    let title: String
    /// The receipt: the matched highlight / chunk / capture text.
    let excerpt: String
    /// Secondary provenance line (author, extract kind, page, capture age).
    let detail: String?
    let score: Double
    /// Openable source atom (nil for inbox captures).
    let atomUUID: String?
    let inboxItemUUID: String?
    /// Where "Add" lands by default. Kind-mapped for extracts, seek-mapped
    /// for everything else.
    let suggestedSection: ConnectionSectionType
    /// Arrived in the latest refresh — worn as a quiet dot until the next one.
    var isNew: Bool = false
}

// MARK: - Gate

/// Recommendations appear only after the concept has begun. The dormant
/// states teach the unlock instead of showing an empty shelf.
enum ConceptRecommendationGate: Equatable {
    /// No goal yet — the concept doesn't know what it's for.
    case needsGoal
    /// Goal exists but the page is still one thought deep.
    case needsMoreMaterial
    case ready

    static func evaluate(state: ConnectionFocusModeState) -> ConceptRecommendationGate {
        let goalFilled = state.section(for: .goal)?.hasContent == true
        let total = state.totalItemCount
        // A page developed without a goal still unlocks once it has real mass.
        if total >= 4 { return .ready }
        if goalFilled && total >= 2 { return .ready }
        if !goalFilled { return .needsGoal }
        return .needsMoreMaterial
    }
}

// MARK: - Snapshot

/// Everything a refresh needs, captured at poke time — the model never holds
/// the view model, so a quick page switch can't bleed context.
struct ConceptRecommendationSnapshot {
    let atomUUID: String
    let title: String
    let conceptType: ConceptFrameworkType
    let state: ConnectionFocusModeState
    /// Linked well sources + reference-linked concept pages — never re-suggested.
    let linkedUUIDs: Set<String>
}

// MARK: - Model

@MainActor
@Observable
final class ConceptRecommendationModel {

    // MARK: State

    private(set) var gate: ConceptRecommendationGate = .needsGoal
    /// The section the concept is hungry for next; nil once well-rounded.
    private(set) var seeking: ConnectionSectionType?
    private(set) var rows: [ConceptRecommendation] = []
    private(set) var isRefreshing = false
    private(set) var didExpand = false
    /// Origin filter — nil shows everything.
    var filter: ConceptRecommendationOrigin? = nil

    var visibleRows: [ConceptRecommendation] {
        guard let filter else { return rows }
        return rows.filter { $0.origin == filter }
    }

    /// Origins that actually have rows — the filter menu offers only these.
    var presentOrigins: [ConceptRecommendationOrigin] {
        ConceptRecommendationOrigin.allCases.filter { origin in
            rows.contains { $0.origin == origin }
        }
    }

    // MARK: Tuning

    nonisolated static let confidenceFloor = 0.30
    /// Readwise matcher rows keep the matcher's own floor (0.6 scale).
    nonisolated static let perOriginCap = 3
    nonisolated static let visibleCap = 9
    nonisolated static let expandedOriginCap = 5
    nonisolated static let expandedCap = 16
    static let pokeDebounce: Duration = .seconds(2.5)

    // MARK: Session

    @ObservationIgnored private var boundAtomUUID: String?
    @ObservationIgnored private var snapshotProvider: (() -> ConceptRecommendationSnapshot)?
    @ObservationIgnored private var dismissed: Set<String> = []
    @ObservationIgnored private var wovenInboxUUIDs: Set<String> = []
    @ObservationIgnored private var lastSignature: String = ""
    @ObservationIgnored private var pokeTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func bind(atomUUID: String, snapshot: @escaping () -> ConceptRecommendationSnapshot) {
        guard boundAtomUUID != atomUUID else {
            snapshotProvider = snapshot
            return
        }
        boundAtomUUID = atomUUID
        snapshotProvider = snapshot
        rows = []
        seeking = nil
        filter = nil
        didExpand = false
        lastSignature = ""
        dismissed = Set(UserDefaults.standard.stringArray(forKey: Self.dismissedKey(atomUUID)) ?? [])
        wovenInboxUUIDs = Set(UserDefaults.standard.stringArray(forKey: Self.wovenInboxKey(atomUUID)) ?? [])
        gate = .needsGoal
    }

    /// Debounced change signal from the host — edits, title changes, appear.
    func poke() {
        pokeTask?.cancel()
        pokeTask = Task { [weak self] in
            try? await Task.sleep(for: Self.pokeDebounce)
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    // MARK: - Refresh

    func refresh(force: Bool = false) async {
        guard let snapshotProvider, let boundAtomUUID else { return }
        let snapshot = snapshotProvider()
        guard snapshot.atomUUID == boundAtomUUID else { return }

        gate = ConceptRecommendationGate.evaluate(state: snapshot.state)
        seeking = Self.seekingSection(in: snapshot.state)
        guard gate == .ready else {
            rows = []
            lastSignature = ""
            return
        }

        let query = Self.intentQuery(snapshot: snapshot, seeking: seeking)
        guard !query.isEmpty else { return }
        // Unchanged signal → unchanged rail; don't re-bill the query embed.
        guard force || query != lastSignature else { return }
        let isNewSignature = query != lastSignature
        lastSignature = query
        if isNewSignature { didExpand = false }

        isRefreshing = true
        defer { isRefreshing = false }

        let incoming = await gather(
            snapshot: snapshot,
            query: query,
            floorScale: 1.0,
            originCap: Self.perOriginCap,
            totalCap: Self.visibleCap
        )
        guard boundAtomUUID == self.boundAtomUUID else { return }
        merge(incoming: incoming, limit: Self.visibleCap)
    }

    /// One explicit widening per signature — lower floor, higher caps,
    /// results join append-only. User-invoked, never on the editing path.
    func findMore() async {
        guard !didExpand, let snapshotProvider, let boundAtomUUID else { return }
        let snapshot = snapshotProvider()
        guard snapshot.atomUUID == boundAtomUUID, gate == .ready else { return }
        didExpand = true

        isRefreshing = true
        defer { isRefreshing = false }

        let query = Self.intentQuery(snapshot: snapshot, seeking: seeking)
        let incoming = await gather(
            snapshot: snapshot,
            query: query,
            floorScale: 0.75,
            originCap: Self.expandedOriginCap,
            totalCap: Self.expandedCap
        )
        guard boundAtomUUID == self.boundAtomUUID else { return }
        merge(incoming: incoming, limit: Self.expandedCap)
    }

    // MARK: - Row actions

    func dismiss(_ row: ConceptRecommendation) {
        guard let boundAtomUUID else { return }
        dismissed.insert(row.id)
        UserDefaults.standard.set(Array(dismissed), forKey: Self.dismissedKey(boundAtomUUID))
        rows.removeAll { $0.id == row.id }
    }

    /// Weave a recommendation into a section as a real item with provenance.
    /// Concept rows landing in References become first-class page links.
    func weave(
        _ row: ConceptRecommendation,
        into section: ConnectionSectionType,
        viewModel: ConnectionFocusModeViewModel
    ) {
        if row.origin == .concept, section == .references, let uuid = row.atomUUID {
            viewModel.attachItem(
                ConnectionItem(content: row.title, linkedConnectionUUID: uuid),
                toSection: .references
            )
        } else {
            viewModel.attachItem(
                ConnectionItem(
                    content: row.excerpt,
                    sourceAtomUUID: row.atomUUID,
                    sourceSnippet: row.excerpt
                ),
                toSection: section
            )
        }
        // Inbox captures have no atom for provenance-based exclusion — the
        // woven set keeps them from resurfacing on the next refresh.
        if let inboxUUID = row.inboxItemUUID, let boundAtomUUID {
            wovenInboxUUIDs.insert(inboxUUID)
            UserDefaults.standard.set(Array(wovenInboxUUIDs), forKey: Self.wovenInboxKey(boundAtomUUID))
        }
        rows.removeAll { $0.id == row.id }
    }

    private static func dismissedKey(_ uuid: String) -> String { "conceptrec.dismissed.\(uuid)" }
    private static func wovenInboxKey(_ uuid: String) -> String { "conceptrec.woven.inbox.\(uuid)" }

    // MARK: - Gathering

    private func gather(
        snapshot: ConceptRecommendationSnapshot,
        query: String,
        floorScale: Double,
        originCap: Int,
        totalCap: Int
    ) async -> [ConceptRecommendation] {
        let floor = Self.confidenceFloor * floorScale
        let exclude = Self.excludedUUIDs(snapshot: snapshot)
        let keys = Self.keyPhraseInputs(snapshot: snapshot)

        async let conceptHits = RecallEngine.shared.query(RecallQuery(
            text: query, types: [.connection], limit: 8,
            excludeUuids: exclude, minScore: floor
        ))
        async let researchHits = RecallEngine.shared.query(RecallQuery(
            text: query, types: [.research], limit: 12,
            excludeUuids: exclude, minScore: floor
        ))
        async let inquiryHits = RecallEngine.shared.query(RecallQuery(
            text: query, types: [.extract, .question], limit: 10,
            excludeUuids: exclude, minScore: floor
        ))
        async let noteHits = RecallEngine.shared.query(RecallQuery(
            text: query, types: [.note, .idea, .stickyNote], limit: 8,
            excludeUuids: exclude, minScore: floor
        ))
        async let bookMatches = ReadwiseEvidenceMatcher.evidence(
            conceptName: keys.name, aliases: keys.aliases, limit: 6
        )
        async let inboxRows = gatherInbox(keys: keys, exclude: exclude)

        let (concepts, research, inquiry, notes, books, inbox) = await (
            conceptHits, researchHits, inquiryHits, noteHits, bookMatches, inboxRows
        )

        var candidates: [ConceptRecommendation] = []
        let fallback = seeking ?? .evidence

        for match in books {
            candidates.append(Self.bookRow(from: match, fallbackSection: fallback))
        }
        let matchedBookUUIDs = Set(books.map(\.bookUUID))
        candidates += await classifyResearch(
            research, excludingBooks: matchedBookUUIDs, fallbackSection: fallback
        )
        candidates += await inquiryRows(from: inquiry, fallbackSection: fallback)
        for hit in concepts {
            candidates.append(ConceptRecommendation(
                id: "atom:\(hit.atomUuid)",
                origin: .concept,
                title: hit.title,
                excerpt: hit.matchedText,
                detail: nil,
                score: hit.score,
                atomUUID: hit.atomUuid,
                inboxItemUUID: nil,
                suggestedSection: .references
            ))
        }
        for hit in notes {
            candidates.append(ConceptRecommendation(
                id: "atom:\(hit.atomUuid)",
                origin: .note,
                title: hit.title,
                excerpt: hit.matchedText,
                detail: nil,
                score: hit.score,
                atomUUID: hit.atomUuid,
                inboxItemUUID: nil,
                suggestedSection: fallback
            ))
        }
        candidates += inbox

        return Self.rank(candidates, originCap: originCap, totalCap: totalCap)
    }

    /// Book highlights that surfaced through the phrase matcher: the receipt
    /// is the highlight itself, with the reader's own note riding along.
    nonisolated private static func bookRow(
        from match: ReadwiseEvidenceMatcher.Match,
        fallbackSection: ConnectionSectionType
    ) -> ConceptRecommendation {
        var excerpt = match.text
        if let note = match.note, !note.isEmpty {
            excerpt += "\n※ \(note)"
        }
        return ConceptRecommendation(
            id: "book:\(match.bookUUID):\(match.highlightId)",
            origin: .book,
            title: match.bookTitle,
            excerpt: excerpt,
            detail: match.author,
            // Matcher scores live on a 0.6–1.0 scale; damp slightly so a
            // perfect semantic hit can still outrank a single-word match.
            score: match.score * 0.9,
            atomUUID: match.bookUUID,
            inboxItemUUID: nil,
            suggestedSection: fallbackSection
        )
    }

    /// Research hits split by what the atom really is: Readwise mirrors join
    /// the Books shelf (their chunks ARE highlight text), swipe posts become
    /// example material, the rest stay research.
    private func classifyResearch(
        _ hits: [RecallHit],
        excludingBooks matchedBookUUIDs: Set<String>,
        fallbackSection: ConnectionSectionType
    ) async -> [ConceptRecommendation] {
        var out: [ConceptRecommendation] = []
        for hit in hits {
            guard let atom = try? await AtomRepository.shared.fetch(uuid: hit.atomUuid) else { continue }
            if atom.isReadwiseMirror {
                // The phrase matcher already offered this book — keep its
                // per-highlight rows over the coarser chunk hit.
                guard !matchedBookUUIDs.contains(atom.uuid) else { continue }
                out.append(ConceptRecommendation(
                    id: "atom:\(hit.atomUuid)",
                    origin: .book,
                    title: hit.title,
                    excerpt: hit.matchedText,
                    detail: atom.readwiseAuthor,
                    score: hit.score,
                    atomUUID: hit.atomUuid,
                    inboxItemUUID: nil,
                    suggestedSection: fallbackSection
                ))
            } else if atom.isSwipeFileAtom {
                out.append(ConceptRecommendation(
                    id: "atom:\(hit.atomUuid)",
                    origin: .swipe,
                    title: hit.title,
                    excerpt: hit.matchedText,
                    detail: nil,
                    score: hit.score,
                    atomUUID: hit.atomUuid,
                    inboxItemUUID: nil,
                    suggestedSection: .examples
                ))
            } else {
                out.append(ConceptRecommendation(
                    id: "atom:\(hit.atomUuid)",
                    origin: .research,
                    title: hit.title,
                    excerpt: hit.matchedText,
                    detail: hit.page.map { "p. \($0)" },
                    score: hit.score,
                    atomUUID: hit.atomUuid,
                    inboxItemUUID: nil,
                    suggestedSection: fallbackSection
                ))
            }
        }
        return out
    }

    /// Inquiry moments: extracts carry their kind → section mapping (the same
    /// routing crystallization uses), questions land in Open Questions.
    private func inquiryRows(
        from hits: [RecallHit],
        fallbackSection: ConnectionSectionType
    ) async -> [ConceptRecommendation] {
        var out: [ConceptRecommendation] = []
        for hit in hits {
            if hit.atomType == .question {
                out.append(ConceptRecommendation(
                    id: "atom:\(hit.atomUuid)",
                    origin: .inquiry,
                    title: hit.title,
                    excerpt: hit.matchedText,
                    detail: "Question",
                    score: hit.score,
                    atomUUID: hit.atomUuid,
                    inboxItemUUID: nil,
                    suggestedSection: .openQuestions
                ))
                continue
            }
            let atom = try? await AtomRepository.shared.fetch(uuid: hit.atomUuid)
            let metadata = atom?.extractMetadata
            var detail = metadata.map { $0.kind.displayName } ?? "Extract"
            if let citation = metadata?.citation, !citation.isEmpty {
                detail += " · \(citation)"
            }
            let section = metadata.flatMap { ConnectionRoutingEngine.sectionType(for: $0.kind) }
            out.append(ConceptRecommendation(
                id: "atom:\(hit.atomUuid)",
                origin: .inquiry,
                title: hit.title,
                excerpt: hit.matchedText,
                detail: detail,
                score: hit.score,
                atomUUID: hit.atomUuid,
                inboxItemUUID: nil,
                suggestedSection: section ?? fallbackSection
            ))
        }
        return out
    }

    /// Inbox captures — active queue plus recent history ("past ones") —
    /// scored with the same phrase matcher that gates book evidence, so a
    /// capture only surfaces when the concept's own words appear in it.
    private func gatherInbox(
        keys: (name: String, aliases: [String]),
        exclude: Set<String>
    ) async -> [ConceptRecommendation] {
        let phrases = ReadwiseEvidenceMatcher.keyPhrases(conceptName: keys.name, aliases: keys.aliases)
        guard !phrases.isEmpty else { return [] }

        let active = (try? await InboxRepository.shared.fetchActive()) ?? []
        let history = (try? await InboxRepository.shared.fetchRecentHistory(limit: 150)) ?? []
        let fallback = seeking ?? .evidence

        var out: [ConceptRecommendation] = []
        for item in (active + history).prefix(400) {
            guard !item.isDeleted,
                  !wovenInboxUUIDs.contains(item.uuid),
                  !exclude.contains(item.uuid) else { continue }
            let text = item.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let score = ReadwiseEvidenceMatcher.score(
                highlight: ReadwiseMirrorHighlight(id: item.uuid, text: text, note: item.title),
                bookTitleNormalized: "",
                keys: phrases
            )
            guard score >= ReadwiseEvidenceMatcher.scoreFloor else { continue }
            out.append(ConceptRecommendation(
                id: "inbox:\(item.uuid)",
                origin: .inbox,
                title: item.title?.isEmpty == false ? item.title! : "Inbox capture",
                excerpt: text,
                detail: Self.inboxDetail(for: item),
                score: score * 0.85,
                atomUUID: nil,
                inboxItemUUID: item.uuid,
                suggestedSection: fallback
            ))
        }
        return out
    }

    nonisolated private static func inboxDetail(for item: InboxItem) -> String {
        var parts: [String] = []
        if let date = ISO8601.date(from: item.createdAt) {
            parts.append(date.cosmoCompactAge)
        }
        if item.status == .actioned || item.status == .dismissed {
            parts.append("triaged")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Ranking & merge

    /// Score-ordered with an origin diversity guard: no single source may
    /// flood the rail, and the caps rise only on the explicit expansion.
    nonisolated static func rank(
        _ candidates: [ConceptRecommendation],
        originCap: Int,
        totalCap: Int
    ) -> [ConceptRecommendation] {
        var seen = Set<String>()
        var perOrigin: [ConceptRecommendationOrigin: Int] = [:]
        var out: [ConceptRecommendation] = []
        for candidate in candidates.sorted(by: { $0.score > $1.score }) {
            guard out.count < totalCap else { break }
            guard seen.insert(candidate.id).inserted else { continue }
            guard perOrigin[candidate.origin, default: 0] < originCap else { continue }
            perOrigin[candidate.origin, default: 0] += 1
            out.append(candidate)
        }
        return out
    }

    /// Append-only (the order-lock law): rows on screen keep their place,
    /// newcomers join at the end wearing the new-dot.
    private func merge(incoming: [ConceptRecommendation], limit: Int) {
        var seen = Set(rows.map(\.id))
        var next = rows.map { row -> ConceptRecommendation in
            var settled = row
            settled.isNew = false
            return settled
        }
        for candidate in incoming {
            guard next.count < limit else { break }
            guard !seen.contains(candidate.id), !dismissed.contains(candidate.id) else { continue }
            seen.insert(candidate.id)
            var fresh = candidate
            fresh.isNew = !rows.isEmpty
            next.append(fresh)
        }
        withAnimation(ProMotionSprings.gentle) {
            rows = next
        }
    }

    // MARK: - Query building (pure)

    /// The intent signal: title + the concept's own name entries + goal +
    /// claims + the freshest thinking + what the concept is seeking next.
    nonisolated static func intentQuery(
        snapshot: ConceptRecommendationSnapshot,
        seeking: ConnectionSectionType?
    ) -> String {
        var parts: [String] = []
        let title = snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { parts.append(title) }
        parts.append(snapshot.conceptType.displayName)

        func sectionTexts(_ type: ConnectionSectionType, limit: Int) -> [String] {
            (snapshot.state.section(for: type)?.items ?? [])
                .prefix(limit)
                .map(\.resolvedPlainText)
                .filter { !$0.isEmpty }
        }
        parts += sectionTexts(.conceptName, limit: 2)
        parts += sectionTexts(.goal, limit: 2)
        parts += sectionTexts(.claims, limit: 3)

        // The live tail: the three most recently touched items anywhere.
        let recent = snapshot.state.sections
            .flatMap(\.items)
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(3)
            .map(\.resolvedPlainText)
        parts += recent

        if let seeking {
            parts.append(seeking.promptQuestion)
        }

        var deduped: [String] = []
        var seen = Set<String>()
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            deduped.append(trimmed)
        }
        return String(deduped.joined(separator: "\n").prefix(900))
    }

    /// Name + aliases for the phrase matchers (books, inbox): the title, the
    /// Concept Name entries, and the goal's opening thoughts.
    nonisolated static func keyPhraseInputs(
        snapshot: ConceptRecommendationSnapshot
    ) -> (name: String, aliases: [String]) {
        var aliases: [String] = []
        for item in snapshot.state.section(for: .conceptName)?.items.prefix(3) ?? [] {
            aliases.append(item.resolvedPlainText)
        }
        for item in snapshot.state.section(for: .goal)?.items.prefix(2) ?? [] {
            aliases.append(item.resolvedPlainText)
        }
        return (snapshot.title, aliases.filter { !$0.isEmpty })
    }

    /// What the concept is hungry for next — the first structurally missing
    /// piece whose prerequisite exists. This is what makes the rail evolve:
    /// fill Claims and it starts hunting Evidence; add Evidence and it goes
    /// looking for the counterargument.
    nonisolated static func seekingSection(in state: ConnectionFocusModeState) -> ConnectionSectionType? {
        func filled(_ type: ConnectionSectionType) -> Bool {
            state.section(for: type)?.hasContent == true
        }
        let ladder: [(ConnectionSectionType, Bool)] = [
            (.claims, filled(.goal)),
            (.evidence, filled(.claims)),
            (.beliefsObjections, filled(.claims) || filled(.evidence)),
            (.examples, filled(.claims) || filled(.process)),
            (.problems, filled(.goal)),
            (.process, filled(.claims) && filled(.evidence)),
            (.openQuestions, state.totalItemCount >= 6),
        ]
        for (candidate, prerequisite) in ladder where prerequisite && !filled(candidate) {
            return candidate
        }
        return nil
    }

    /// Material already on the page (by provenance), linked sources, and the
    /// page itself — none of it is ever re-recommended.
    nonisolated static func excludedUUIDs(snapshot: ConceptRecommendationSnapshot) -> Set<String> {
        var out: Set<String> = [snapshot.atomUUID]
        out.formUnion(snapshot.linkedUUIDs)
        for section in snapshot.state.sections {
            for item in section.items {
                if let source = item.sourceAtomUUID { out.insert(source) }
                if let linked = item.linkedConnectionUUID { out.insert(linked) }
            }
        }
        return out
    }
}
