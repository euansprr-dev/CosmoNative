// CosmoOS/UI/FocusMode/Connection/ConceptRecommendationModel.swift
// The Material rail — ambient recall while developing a concept. Receipts-
// based recommendations drawn from the whole library: book highlights
// (Readwise), inquiry moments (extracts and questions), research, adjacent
// concepts, notes and ideas, and inbox captures.
//
// Architecture (v2, July 2026): deterministic retrieval PROPOSES, the judge
// DISPOSES. Recall + phrase matchers over-fetch candidates behind per-channel
// floors and a rare-term gate (common words like "experience" can never carry
// a match alone); one batched sensor-tier judge call then keeps only what it
// can justify in a sentence — which renders under the row as its rationale.
// If the judge cannot rule (offline/timeout), the deterministic floors stand
// alone. Zero LLM on the typing path: the judge fires once per settled
// edit-signature.
//
// Laws:
// - GATED: nothing surfaces until the concept has begun; dormant states
//   teach the unlock.
// - EVOLVING: the "seeking" ladder re-aims queries and Add targets as
//   sections fill.
// - SILENCE OVER NOISE: below-floor hits, judge rejections, dismissed rows,
//   and material already on the page never render.
// - ORDER LOCK: visible rows never reorder mid-session; newcomers append.
// - PROVENANCE-AWARE: material that restates an already-linked reference
//   page is badged "via <page>", never passed off as new.

import SwiftUI
import GRDB

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

    /// Confidence floor for this channel's Recall sweep. Extracts are short,
    /// dense units of meaning — trusted low. Notes/research are long and
    /// semantically muddy — they must EARN a slot. Swipes are transcripts.
    var recallFloor: Double {
        switch self {
        case .inquiry: return 0.30
        case .concept: return 0.38
        case .book, .note, .research: return 0.45
        case .swipe: return 0.50
        case .inbox: return 0.45 // unused — inbox rides the phrase matcher
        }
    }
}

// MARK: - Recommendation

/// One row on the rail: a receipt (why it surfaced), provenance, a suggested
/// landing section, and — when the judge ruled — its one-line rationale.
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
    /// Where "Add" lands by default. Kind-mapped for extracts, judge-mapped
    /// when a ruling named a section, seek-mapped otherwise.
    var suggestedSection: ConnectionSectionType
    /// The judge's one-sentence justification, or a matched-phrase receipt.
    var rationale: String? = nil
    /// Set when this material already lives inside a linked reference page —
    /// the row wears a "via <title>" badge instead of posing as new.
    var viaConceptUUID: String? = nil
    var viaConceptTitle: String? = nil
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
    /// True when the last refresh carried a judge ruling (rationales present).
    private(set) var isJudged = false
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

    /// Post-judge visible cap; the judge sees up to Judge.maxCandidates.
    nonisolated static let visibleCap = 9
    nonisolated static let expandedCap = 16
    /// Pre-judge over-fetch diversity guard.
    nonisolated static let gatherOriginCap = 4
    /// Pure-vector conviction that bypasses the rare-term gate.
    nonisolated static let vectorConvictionFloor = 0.50
    /// A query term present in more than this share of the corpus is a
    /// "common" — it can never qualify a match on its own.
    nonisolated static let commonTermShare = 0.06
    static let pokeDebounce: Duration = .seconds(2.5)

    // MARK: Session

    @ObservationIgnored private var boundAtomUUID: String?
    @ObservationIgnored private var snapshotProvider: (() -> ConceptRecommendationSnapshot)?
    @ObservationIgnored private var dismissed: Set<String> = []
    @ObservationIgnored private var silencedAtomUUIDs: Set<String> = []
    @ObservationIgnored private var wovenInboxUUIDs: Set<String> = []
    @ObservationIgnored private var weaveBoosts: [String: Int] = [:]
    @ObservationIgnored private var lastSignature: String = ""
    @ObservationIgnored private var pokeTask: Task<Void, Never>?
    /// Linked reference pages resolved at refresh time — weave linkification
    /// targets and the judge's "already said" context.
    @ObservationIgnored private(set) var linkedPages: [(uuid: String, title: String)] = []
    /// Corpus document frequencies, cached per session (the corpus moves
    /// slowly; a stale df is harmless).
    @ObservationIgnored private var termDocumentFrequency: [String: Int] = [:]
    @ObservationIgnored private var corpusSize: Int = 0

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
        isJudged = false
        lastSignature = ""
        linkedPages = []
        dismissed = Set(UserDefaults.standard.stringArray(forKey: Self.dismissedKey(atomUUID)) ?? [])
        silencedAtomUUIDs = Set(UserDefaults.standard.stringArray(forKey: Self.silencedKey(atomUUID)) ?? [])
        wovenInboxUUIDs = Set(UserDefaults.standard.stringArray(forKey: Self.wovenInboxKey(atomUUID)) ?? [])
        weaveBoosts = (UserDefaults.standard.dictionary(forKey: Self.weaveBoostKey(atomUUID)) as? [String: Int]) ?? [:]
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

        let signature = Self.signature(snapshot: snapshot, seeking: seeking)
        guard !signature.isEmpty else { return }
        // Unchanged signal → unchanged rail; don't re-bill embeds or the judge.
        guard force || signature != lastSignature else { return }
        if signature != lastSignature { didExpand = false }
        lastSignature = signature

        isRefreshing = true
        defer { isRefreshing = false }

        let outcome = await gatherAndJudge(snapshot: snapshot, expanded: false)
        guard boundAtomUUID == self.boundAtomUUID, lastSignature == signature else { return }
        isJudged = outcome.judged
        merge(incoming: outcome.rows, limit: Self.visibleCap)
    }

    /// One explicit widening per signature — lower floors, higher caps,
    /// results join append-only. User-invoked, never on the editing path.
    func findMore() async {
        guard !didExpand, let snapshotProvider, let boundAtomUUID else { return }
        let snapshot = snapshotProvider()
        guard snapshot.atomUUID == boundAtomUUID, gate == .ready else { return }
        didExpand = true

        isRefreshing = true
        defer { isRefreshing = false }

        let outcome = await gatherAndJudge(snapshot: snapshot, expanded: true)
        guard boundAtomUUID == self.boundAtomUUID else { return }
        merge(incoming: outcome.rows, limit: Self.expandedCap)
    }

    // MARK: - Row actions

    /// Dismissals persist per concept — and generalize: a source atom whose
    /// rows get dismissed twice is silenced for this concept entirely; a
    /// source silenced on three different concepts joins the global quiet
    /// list and stops being recommended anywhere.
    func dismiss(_ row: ConceptRecommendation) {
        guard let boundAtomUUID else { return }
        dismissed.insert(row.id)
        UserDefaults.standard.set(Array(dismissed), forKey: Self.dismissedKey(boundAtomUUID))

        if let atomUUID = row.atomUUID {
            let dismissalsFromAtom = dismissed.filter { $0.contains(atomUUID) }.count
            if dismissalsFromAtom >= 2 {
                silencedAtomUUIDs.insert(atomUUID)
                UserDefaults.standard.set(Array(silencedAtomUUIDs), forKey: Self.silencedKey(boundAtomUUID))
                Self.recordGlobalQuiet(atomUUID: atomUUID, conceptUUID: boundAtomUUID)
            }
        }
        rows.removeAll { $0.id == row.id }
    }

    /// Weave a recommendation into a section as a real item with provenance.
    /// Titles of linked reference pages inside the text become live mention
    /// links ("self-experimentation" → the Self-experimentation page), and
    /// concept rows landing in References become first-class page links.
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
            var targets = linkedPages
            if let viaUUID = row.viaConceptUUID, let viaTitle = row.viaConceptTitle,
               !targets.contains(where: { $0.uuid == viaUUID }) {
                targets.append((viaUUID, viaTitle))
            }
            let parsed = Self.linkified(text: row.excerpt, targets: targets)
            viewModel.attachItem(
                ConnectionItem(
                    content: parsed.plainText,
                    document: parsed.document,
                    plainText: parsed.plainText,
                    sourceAtomUUID: row.atomUUID,
                    sourceSnippet: row.excerpt,
                    linkedConnectionUUID: parsed.soleConnectionLink?.entityUUID
                ),
                toSection: section
            )
        }
        // The rail learns which channels actually feed this concept.
        if let boundAtomUUID {
            weaveBoosts[row.origin.rawValue, default: 0] += 1
            UserDefaults.standard.set(weaveBoosts, forKey: Self.weaveBoostKey(boundAtomUUID))
            // Inbox captures have no atom for provenance-based exclusion —
            // the woven set keeps them from resurfacing on the next refresh.
            if let inboxUUID = row.inboxItemUUID {
                wovenInboxUUIDs.insert(inboxUUID)
                UserDefaults.standard.set(Array(wovenInboxUUIDs), forKey: Self.wovenInboxKey(boundAtomUUID))
            }
        }
        rows.removeAll { $0.id == row.id }
    }

    private static func dismissedKey(_ uuid: String) -> String { "conceptrec.dismissed.\(uuid)" }
    private static func silencedKey(_ uuid: String) -> String { "conceptrec.silenced.\(uuid)" }
    private static func wovenInboxKey(_ uuid: String) -> String { "conceptrec.woven.inbox.\(uuid)" }
    private static func weaveBoostKey(_ uuid: String) -> String { "conceptrec.weaveboost.\(uuid)" }
    static let globalQuietKey = "conceptrec.quiet.map"
    nonisolated static let globalQuietThreshold = 3

    /// Atom → concepts that silenced it. Three distinct concepts = quiet
    /// everywhere.
    private static func recordGlobalQuiet(atomUUID: String, conceptUUID: String) {
        var map = (UserDefaults.standard.dictionary(forKey: globalQuietKey) as? [String: [String]]) ?? [:]
        var concepts = Set(map[atomUUID] ?? [])
        concepts.insert(conceptUUID)
        map[atomUUID] = Array(concepts)
        UserDefaults.standard.set(map, forKey: globalQuietKey)
    }

    private static func globallyQuietAtomUUIDs() -> Set<String> {
        let map = (UserDefaults.standard.dictionary(forKey: globalQuietKey) as? [String: [String]]) ?? [:]
        return Set(map.filter { $0.value.count >= globalQuietThreshold }.keys)
    }

    // MARK: - Gather + judge pipeline

    private struct Outcome {
        var rows: [ConceptRecommendation]
        var judged: Bool
    }

    private func gatherAndJudge(
        snapshot: ConceptRecommendationSnapshot,
        expanded: Bool
    ) async -> Outcome {
        await resolveLinkedPages(snapshot: snapshot)

        var candidates = await gather(snapshot: snapshot, expanded: expanded)
        candidates = await applyLineage(to: candidates)

        // Deterministic pre-rank feeds the judge its batch; boosts reward
        // channels the user has actually woven from on this concept.
        let boosts = weaveBoosts
        let preRanked = Self.rank(
            candidates,
            originCap: Self.gatherOriginCap,
            totalCap: ConceptRecommendationJudge.maxCandidates,
            weaveBoosts: boosts
        )

        let dossier = Self.dossier(snapshot: snapshot, seeking: seeking, linkedPages: linkedPages)
        let judgeCandidates = preRanked.map { row in
            ConceptRecommendationJudge.Candidate(
                rowID: row.id,
                originLabel: row.origin.label,
                title: row.title,
                excerpt: row.excerpt
            )
        }
        guard let rulings = await ConceptRecommendationJudge.judge(
            dossier: dossier, candidates: judgeCandidates
        ) else {
            // No ruling — deterministic floors stand alone.
            let cap = expanded ? Self.expandedCap : Self.visibleCap
            return Outcome(rows: Array(preRanked.prefix(cap)), judged: false)
        }

        let titleByUUID = Dictionary(
            linkedPages.map { ($0.uuid, $0.title) },
            uniquingKeysWith: { first, _ in first }
        )
        var byID: [String: ConceptRecommendation] = [:]
        for row in preRanked { byID[row.id] = row }

        var kept: [ConceptRecommendation] = []
        for ruling in rulings {
            guard var row = byID[ruling.rowID] else { continue }
            if let coveredBy = ruling.coveredByUUID {
                row.viaConceptUUID = coveredBy
                row.viaConceptTitle = titleByUUID[coveredBy]
                row.suggestedSection = .references
            } else {
                if let section = ruling.section { row.suggestedSection = section }
                if !ruling.why.isEmpty { row.rationale = ruling.why }
            }
            kept.append(row)
        }
        // Judge order is arbitrary — restore deterministic score order, with
        // covered rows sinking below fresh material.
        kept.sort { lhs, rhs in
            if (lhs.viaConceptUUID == nil) != (rhs.viaConceptUUID == nil) {
                return lhs.viaConceptUUID == nil
            }
            return lhs.score > rhs.score
        }
        return Outcome(rows: kept, judged: true)
    }

    // MARK: - Gathering

    private func gather(
        snapshot: ConceptRecommendationSnapshot,
        expanded: Bool
    ) async -> [ConceptRecommendation] {
        let exclude: Set<String> = {
            var out = Self.excludedUUIDs(snapshot: snapshot)
            out.formUnion(silencedAtomUUIDs)
            out.formUnion(Self.globallyQuietAtomUUIDs())
            return out
        }()
        let keys = Self.keyPhraseInputs(snapshot: snapshot)

        let identity = Self.identityQuery(snapshot: snapshot)
        let momentum = Self.momentumQuery(snapshot: snapshot)
        await primeTermRarity(for: identity)
        let distinctive = distinctiveTerms(in: identity)

        // The floor drops slightly on the explicit expansion — the judge is
        // still the last word, so wider nets stay safe.
        let floorScale = expanded ? 0.85 : 1.0

        @Sendable func sweep(
            _ types: Set<AtomType>, floor: Double, limit: Int
        ) async -> [RecallHit] {
            // Two facets per channel: who the concept IS, and what it is
            // thinking about right now. Long blended queries dilute both.
            async let identityHits = RecallEngine.shared.query(RecallQuery(
                text: identity, types: types, limit: limit,
                recencyHalfLifeDays: nil, excludeUuids: exclude, minScore: floor
            ))
            async let momentumHits = momentum.isEmpty
                ? [RecallHit]()
                : RecallEngine.shared.query(RecallQuery(
                    text: momentum, types: types, limit: limit,
                    recencyHalfLifeDays: nil, excludeUuids: exclude, minScore: floor
                ))
            let (a, b) = await (identityHits, momentumHits)
            // Max score per atom across facets.
            var best: [String: RecallHit] = [:]
            for hit in a + b where (best[hit.atomUuid]?.score ?? -1) < hit.score {
                best[hit.atomUuid] = hit
            }
            return best.values
                .filter { hit in
                    Self.passesRareTermGate(
                        matchedText: hit.matchedText,
                        title: hit.title,
                        vectorSimilarity: hit.vectorSimilarity,
                        distinctiveTerms: distinctive
                    )
                }
                .sorted { $0.score > $1.score }
        }

        async let conceptHits = sweep(
            [.connection],
            floor: ConceptRecommendationOrigin.concept.recallFloor * floorScale, limit: 8
        )
        async let researchHits = sweep(
            [.research],
            floor: ConceptRecommendationOrigin.research.recallFloor * floorScale, limit: 12
        )
        async let inquiryHits = sweep(
            [.extract, .question],
            floor: ConceptRecommendationOrigin.inquiry.recallFloor * floorScale, limit: 10
        )
        async let noteHits = sweep(
            [.note, .idea, .stickyNote],
            floor: ConceptRecommendationOrigin.note.recallFloor * floorScale, limit: 8
        )
        async let bookMatches = ReadwiseEvidenceMatcher.evidence(
            conceptName: keys.name, aliases: keys.aliases, limit: 6
        )
        async let inboxRows = gatherInbox(keys: keys, exclude: exclude)

        let (concepts, research, inquiry, notes, books, inbox) = await (
            conceptHits, researchHits, inquiryHits, noteHits, bookMatches, inboxRows
        )

        var candidates: [ConceptRecommendation] = []
        let fallback = seeking ?? .evidence
        let phraseKeys = ReadwiseEvidenceMatcher.keyPhrases(conceptName: keys.name, aliases: keys.aliases)

        for match in books where !exclude.contains(match.bookUUID) {
            candidates.append(Self.bookRow(from: match, fallbackSection: fallback, phraseKeys: phraseKeys))
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
        return candidates
    }

    /// Book highlights that surfaced through the phrase matcher: the receipt
    /// is the highlight itself, with the reader's own note riding along and
    /// the matched phrase as the fallback rationale.
    nonisolated private static func bookRow(
        from match: ReadwiseEvidenceMatcher.Match,
        fallbackSection: ConnectionSectionType,
        phraseKeys: [ReadwiseEvidenceMatcher.KeyPhrase]
    ) -> ConceptRecommendation {
        var excerpt = match.text
        if let note = match.note, !note.isEmpty {
            excerpt += "\n※ \(note)"
        }
        var row = ConceptRecommendation(
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
        if let phrase = containedPhrase(in: match.text, keys: phraseKeys) {
            row.rationale = "Mentions “\(phrase)”"
        }
        return row
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
            var row = ConceptRecommendation(
                id: "inbox:\(item.uuid)",
                origin: .inbox,
                title: item.title?.isEmpty == false ? item.title! : "Inbox capture",
                excerpt: text,
                detail: Self.inboxDetail(for: item),
                score: score * 0.85,
                atomUUID: nil,
                inboxItemUUID: item.uuid,
                suggestedSection: fallback
            )
            if let phrase = Self.containedPhrase(in: text, keys: phrases) {
                row.rationale = "Mentions “\(phrase)”"
            }
            out.append(row)
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

    // MARK: - Lineage (linked reference pages)

    /// Resolve the pages this concept already references — weave targets,
    /// judge context, and the "already embodied" check all read from here.
    private func resolveLinkedPages(snapshot: ConceptRecommendationSnapshot) async {
        var uuids: [String] = []
        var seen = Set<String>()
        for section in snapshot.state.sections {
            for item in section.items {
                if let linked = item.linkedConnectionUUID, seen.insert(linked).inserted {
                    uuids.append(linked)
                }
            }
        }
        for linked in snapshot.linkedUUIDs where seen.insert(linked).inserted {
            uuids.append(linked)
        }

        var pages: [(uuid: String, title: String)] = []
        var pageBodies: [String: String] = [:]
        for uuid in uuids.prefix(12) {
            guard let atom = try? await AtomRepository.shared.fetch(uuid: uuid),
                  !atom.isDeleted, atom.type == .connection,
                  let title = atom.title, !title.isEmpty else { continue }
            pages.append((uuid, title))
            let itemTexts = (atom.connectionSectionData?.sections ?? [])
                .flatMap(\.items)
                .map(\.resolvedPlainText)
            pageBodies[uuid] = ([title] + itemTexts).joined(separator: "\n")
        }
        linkedPages = pages
        linkedPageBodies = pageBodies
    }

    @ObservationIgnored private var linkedPageBodies: [String: String] = [:]

    /// Deterministic complement to the judge's `covered` ruling: a candidate
    /// whose words substantially live inside a linked page is badged "via"
    /// that page and demoted — even when the judge abstains.
    private func applyLineage(to candidates: [ConceptRecommendation]) async -> [ConceptRecommendation] {
        guard !linkedPageBodies.isEmpty else { return candidates }
        return candidates.map { row in
            guard row.viaConceptUUID == nil else { return row }
            for (uuid, body) in linkedPageBodies {
                if Self.overlapRatio(of: row.excerpt, within: body) >= 0.6 {
                    var demoted = row
                    demoted.viaConceptUUID = uuid
                    demoted.viaConceptTitle = linkedPages.first { $0.uuid == uuid }?.title
                    demoted.suggestedSection = .references
                    return demoted
                }
            }
            return row
        }
    }

    /// Share of the candidate's identity-bearing tokens present in the page.
    nonisolated static func overlapRatio(of excerpt: String, within pageText: String) -> Double {
        let candidateTokens = significantTokens(in: excerpt)
        guard candidateTokens.count >= 4 else { return 0 }
        let pageTokens = Set(significantTokens(in: pageText))
        let present = candidateTokens.filter { pageTokens.contains($0) }
        return Double(present.count) / Double(candidateTokens.count)
    }

    // MARK: - Rare-term gate

    /// Common words ("experience", "inquiry", the app's own vocabulary) match
    /// half the corpus — a hit that leans on them alone is noise. A Recall
    /// hit must either carry real semantic conviction or share at least one
    /// DISTINCTIVE query term with the matched chunk.
    nonisolated static func passesRareTermGate(
        matchedText: String,
        title: String,
        vectorSimilarity: Double,
        distinctiveTerms: Set<String>
    ) -> Bool {
        if vectorSimilarity >= vectorConvictionFloor { return true }
        // No distinctive vocabulary exists for this concept (an all-common
        // title) — semantic conviction is the only trustworthy signal left.
        guard !distinctiveTerms.isEmpty else { return false }
        let haystack = Set(significantTokens(in: matchedText + " " + title))
        return !haystack.isDisjoint(with: distinctiveTerms)
    }

    /// Lowercased alphanumeric tokens, stop words and short tokens dropped.
    nonisolated static func significantTokens(in text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 && !queryStopTokens.contains($0) }
    }

    nonisolated static let queryStopTokens: Set<String> = [
        "this", "that", "with", "from", "have", "what", "your", "when", "then",
        "them", "they", "will", "would", "could", "should", "about", "into",
        "just", "like", "only", "over", "some", "than", "there", "these",
        "thing", "things", "very", "want", "were", "which", "actually",
    ]

    /// Fetch corpus document frequencies for the identity query's terms —
    /// one cheap FTS count per uncached term, cached for the session.
    private func primeTermRarity(for identityText: String) async {
        let terms = Set(Self.significantTokens(in: identityText)).subtracting(termDocumentFrequency.keys)
        guard !terms.isEmpty || corpusSize == 0 else { return }
        let counts: (total: Int, df: [String: Int]) = (try? await CosmoDatabase.shared.asyncRead { db in
            let total = (try? Int.fetchOne(db, sql: "SELECT count(*) FROM atoms_fts")) ?? 0
            var df: [String: Int] = [:]
            for term in terms {
                let sql = "SELECT count(*) FROM atoms_fts WHERE atoms_fts MATCH ?"
                df[term] = (try? Int.fetchOne(db, sql: sql, arguments: ["\"\(term)\""])) ?? 0
            }
            return (total, df)
        }) ?? (0, [:])
        corpusSize = max(corpusSize, counts.total)
        termDocumentFrequency.merge(counts.df) { _, new in new }
    }

    /// Query terms rare enough to carry concept identity.
    private func distinctiveTerms(in identityText: String) -> Set<String> {
        guard corpusSize > 20 else {
            // Tiny corpus: everything is "rare"; the gate falls back to
            // letting all terms qualify.
            return Set(Self.significantTokens(in: identityText))
        }
        let ceiling = Int(Double(corpusSize) * Self.commonTermShare)
        return Set(Self.significantTokens(in: identityText).filter { term in
            let df = termDocumentFrequency[term] ?? 0
            return df > 0 && df <= max(ceiling, 1)
        })
    }

    // MARK: - Ranking & merge

    /// Score-ordered with an origin diversity guard and weave-taught boosts:
    /// channels the user has woven from on this concept get up to +15%.
    nonisolated static func rank(
        _ candidates: [ConceptRecommendation],
        originCap: Int,
        totalCap: Int,
        weaveBoosts: [String: Int] = [:]
    ) -> [ConceptRecommendation] {
        func boosted(_ row: ConceptRecommendation) -> Double {
            let weaves = weaveBoosts[row.origin.rawValue] ?? 0
            return row.score * (1.0 + min(0.15, 0.05 * Double(weaves)))
        }
        var seen = Set<String>()
        var perOrigin: [ConceptRecommendationOrigin: Int] = [:]
        var out: [ConceptRecommendation] = []
        for candidate in candidates.sorted(by: { boosted($0) > boosted($1) }) {
            guard out.count < totalCap else { break }
            guard seen.insert(candidate.id).inserted else { continue }
            guard perOrigin[candidate.origin, default: 0] < originCap else { continue }
            perOrigin[candidate.origin, default: 0] += 1
            out.append(candidate)
        }
        return out
    }

    /// Append-only (the order-lock law): rows on screen keep their place,
    /// newcomers join at the end wearing the new-dot. Judge annotations
    /// refresh in place — a rationale arriving for a visible row is an
    /// update, not a reorder.
    private func merge(incoming: [ConceptRecommendation], limit: Int) {
        var incomingByID: [String: ConceptRecommendation] = [:]
        for row in incoming { incomingByID[row.id] = row }

        var next: [ConceptRecommendation] = rows.map { row in
            var settled = incomingByID[row.id] ?? row
            settled.isNew = false
            return settled
        }
        var seen = Set(next.map(\.id))
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

    /// Who the concept IS: title, its own name entries, the goal. This facet
    /// also feeds the rare-term vocabulary.
    nonisolated static func identityQuery(snapshot: ConceptRecommendationSnapshot) -> String {
        var parts: [String] = []
        let title = snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { parts.append(title) }
        parts += sectionTexts(.conceptName, in: snapshot.state, limit: 3)
        parts += sectionTexts(.goal, in: snapshot.state, limit: 2)
        return dedupedJoin(parts, cap: 600)
    }

    /// What the concept is thinking about RIGHT NOW: claims, the seeking
    /// section's existing entries, and the freshest items anywhere. No
    /// boilerplate prompt questions — generic phrasing poisons embeddings.
    nonisolated static func momentumQuery(snapshot: ConceptRecommendationSnapshot) -> String {
        var parts: [String] = []
        parts += sectionTexts(.claims, in: snapshot.state, limit: 3)
        let recent = snapshot.state.sections
            .flatMap(\.items)
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(3)
            .map(\.resolvedPlainText)
        parts += recent
        return dedupedJoin(parts, cap: 600)
    }

    /// The change-detection signature: both facets plus the seek target.
    nonisolated static func signature(
        snapshot: ConceptRecommendationSnapshot,
        seeking: ConnectionSectionType?
    ) -> String {
        let facets = identityQuery(snapshot: snapshot) + "\n" + momentumQuery(snapshot: snapshot)
        guard !facets.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        return facets + "\n#seek:" + (seeking?.rawValue ?? "none")
    }

    nonisolated private static func sectionTexts(
        _ type: ConnectionSectionType,
        in state: ConnectionFocusModeState,
        limit: Int
    ) -> [String] {
        (state.section(for: type)?.items ?? [])
            .prefix(limit)
            .map(\.resolvedPlainText)
            .filter { !$0.isEmpty }
    }

    nonisolated private static func dedupedJoin(_ parts: [String], cap: Int) -> String {
        var deduped: [String] = []
        var seen = Set<String>()
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            deduped.append(trimmed)
        }
        return String(deduped.joined(separator: "\n").prefix(cap))
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

    // MARK: - Judge dossier

    nonisolated static func dossier(
        snapshot: ConceptRecommendationSnapshot,
        seeking: ConnectionSectionType?,
        linkedPages: [(uuid: String, title: String)]
    ) -> ConceptRecommendationJudge.Dossier {
        let filled = snapshot.state.sections
            .filter { !$0.items.isEmpty }
            .sorted { $0.type.sortOrder < $1.type.sortOrder }
            .map { section in
                (name: section.type.displayName,
                 items: section.items.map(\.resolvedPlainText).filter { !$0.isEmpty })
            }
        return ConceptRecommendationJudge.Dossier(
            title: snapshot.title,
            typeName: snapshot.conceptType.displayName,
            sections: filled,
            seekingName: seeking?.displayName,
            linkedPages: linkedPages
        )
    }

    // MARK: - Matched-phrase receipt (pure)

    /// The first key phrase actually contained in the text — the honest
    /// "why this surfaced" when no judge rationale exists.
    nonisolated static func containedPhrase(
        in text: String,
        keys: [ReadwiseEvidenceMatcher.KeyPhrase]
    ) -> String? {
        let normalized = " " + ReadwiseEvidenceMatcher.normalized(text) + " "
        for key in keys.sorted(by: { $0.phrase.count > $1.phrase.count }) {
            if normalized.contains(" " + key.phrase + " ") {
                return key.phrase
            }
        }
        return nil
    }

    // MARK: - Weave linkification (pure)

    /// Replaces the FIRST whole-phrase occurrence of each target page's title
    /// with a mention token, longest title first, then resolves through the
    /// one mention grammar — "self-experimentation" in woven prose becomes a
    /// live link to the Self-experimentation page.
    nonisolated static func linkified(
        text: String,
        targets: [(uuid: String, title: String)]
    ) -> ConceptMentionToken.ParsedItem {
        guard !targets.isEmpty else { return ConceptMentionToken.parse(text) }
        var tokenized = text
        for target in targets.sorted(by: { $0.title.count > $1.title.count }) {
            let title = target.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard title.count >= 4 else { continue }
            guard let range = wholePhraseRange(of: title, in: tokenized) else { continue }
            let matched = String(tokenized[range])
            tokenized.replaceSubrange(
                range,
                with: "@[\(matched)](connection:\(target.uuid))"
            )
        }
        return ConceptMentionToken.parse(tokenized)
    }

    /// Case-insensitive whole-phrase search: the match must not butt up
    /// against letters or digits on either side ("art" never claims "start"),
    /// and never lands inside an already-written mention token.
    nonisolated static func wholePhraseRange(of phrase: String, in text: String) -> Range<String.Index>? {
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(of: phrase, options: [.caseInsensitive], range: searchStart..<text.endIndex) {
            let beforeOK: Bool = {
                guard range.lowerBound > text.startIndex else { return true }
                let before = text[text.index(before: range.lowerBound)]
                return !(before.isLetter || before.isNumber) && before != "["
            }()
            let afterOK: Bool = {
                guard range.upperBound < text.endIndex else { return true }
                let after = text[range.upperBound]
                return !(after.isLetter || after.isNumber) && after != "]"
            }()
            if beforeOK && afterOK { return range }
            searchStart = range.upperBound
        }
        return nil
    }
}
