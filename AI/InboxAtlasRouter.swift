// CosmoOS/AI/InboxAtlasRouter.swift
// Stage B of Atlas routing: ONE taught sensor-tier call that sees the
// capture, a cross-kind shortlist of destinations (the Atlas cards), and the
// user's past corrections — and answers with typed MOVES, not folders.
//
// A move says what the capture DOES in the knowledge graph:
//   advanceQuestion     — material for an open inquiry question
//   spawnQuestion       — the capture IS a research question → new branch
//   feedConnection      — matures a concept page, into a specific section
//   attachClient        — a content idea for a client (niche-matched)
//   placeCluster /      — the classic spatial homes, now chosen with
//   placeThinkspace       understanding instead of centroid geometry
//   germinateConnection — seed of a new concept page with no home yet
//   startInquiry        — the capture is something to RESEARCH → an inquiry
//                         session inside the Space it belongs to
//   germinateDeepDive   — a research topic no Space covers → a new Space
//                         with the inquiry started inside it
//
// Anatomy follows InquiryLiveRouter (the codebase's proven classifier): a
// taught decision procedure, destination keys that must be copied from the
// input (invented keys are dropped in parse), corrections as learned rules,
// and abstention as a first-class answer. Prompt building and parsing are
// static and pure — unit-testable without a database or network.
// July 2026 — Atlas routing.

import Foundation

actor InboxAtlasRouter {
    static let shared = InboxAtlasRouter()

    // MARK: - Types

    enum MoveKind: String, Sendable, CaseIterable {
        case advanceQuestion
        case fileToDestination
        case spawnQuestion
        case feedConnection
        case attachClient
        case placeCluster
        case placeThinkspace
        // The global Seedbed (July 2026): insight captures GROW instead of
        // landing as canvas objects or premature concept pages. feedSeedling
        // adds mass to a growing proto-concept; startSeedling names a new one.
        // (startSeedling replaces the old germinateConnection, which created a
        // dead one-line page — pages are born ripe or not at all.)
        case feedSeedling
        case startSeedling
        /// September 2026 — the capture → inquiry loop. Spaces host
        /// inquiries; a research capture becomes a resumable session there.
        case startInquiry
        case germinateDeepDive
        /// The capture is CRAFT REFERENCE — saved for its form, not its claims.
        /// It becomes a swipe; SwipeIntakeRouter decides page vs frame vs note.
        case fileAsSwipe
        /// The capture is a SOURCE saved for its content — a link to read,
        /// watch, or cite. It becomes a research source (never a swipe), in a
        /// workspace's materials, linked to a concept page, or in the Library.
        case fileAsResearch
    }

    struct RoutedMove: Sendable, Equatable {
        var kind: MoveKind
        /// Atlas key of the destination — validated against the shortlist.
        var targetKey: String?
        /// Connection section rawValue (feedConnection only, validated).
        var section: String?
        /// Cleaned title for a spawned question or germinated page.
        var newTitle: String?
        /// Nesting contract parent for spawnQuestion (validated question key).
        var parentQuestionKey: String?
        /// The concept's future home — a cluster/thinkspace key the seedling
        /// belongs to once developed (seedling moves only, validated). Tags
        /// affinity; places nothing.
        var homeKey: String?
        /// One line on how this move grows the knowledge base.
        var growth: String
        var confidence: Double

        init(
            kind: MoveKind,
            targetKey: String? = nil,
            section: String? = nil,
            newTitle: String? = nil,
            parentQuestionKey: String? = nil,
            homeKey: String? = nil,
            growth: String,
            confidence: Double
        ) {
            self.kind = kind
            self.targetKey = targetKey
            self.section = section
            self.newTitle = newTitle
            self.parentQuestionKey = parentQuestionKey
            self.homeKey = homeKey
            self.growth = growth
            self.confidence = confidence
        }
    }

    struct Decision: Sendable, Equatable {
        /// Router-cleaned capture title (≤ 10 words).
        var title: String?
        /// The capture's shape: task | question | insight | idea | note | source.
        var captureType: String?
        /// Ranked moves, best first. Empty = honest abstain.
        var moves: [RoutedMove]
    }

    /// Background classification with a visible "Reading…" state — accuracy
    /// over latency, but bounded so a hung call never wedges the queue.
    private let timeoutNanoseconds: UInt64 = 15_000_000_000
    /// The sweep answers for a whole batch — a longer leash, same bound.
    private let sweepTimeoutNanoseconds: UInt64 = 30_000_000_000
    private let maxAttempts = 2

    private init() {}

    // MARK: - Route

    func route(
        text: String,
        heuristicTitle: String,
        candidates: [InboxDestinationAtlas.ScoredEntry],
        corrections: [InboxRoutingCorrectionLedger.Example],
        lensHint: String? = nil
    ) async -> Decision? {
        guard !candidates.isEmpty else { return nil }
        let prompt = Self.buildPrompt(
            text: text,
            heuristicTitle: heuristicTitle,
            candidates: candidates,
            corrections: corrections,
            lensHint: lensHint
        )

        var raw: String?
        for attempt in 1...maxAttempts {
            raw = await withTimeout {
                try await ResearchService.shared.analyze(
                    prompt: prompt,
                    systemPrompt: Self.systemPrompt,
                    tier: .sensor,
                    maxTokens: 700
                )
            }
            if raw != nil { break }
            if attempt < maxAttempts {
                print("[InboxAtlasRouter] route attempt \(attempt) timed out — retrying")
            }
        }
        guard let raw else { return nil }
        return Self.parse(raw: raw, candidates: candidates)
    }

    /// The sweep: several unsorted captures, one call, the same move ladder.
    /// Replaces the folders-only taxonomy pass — the recovery net now speaks
    /// the full Atlas grammar (concepts, questions, material), so an abstain
    /// at capture time can still become a concept suggestion later.
    func sweep(
        items: [(uuid: String, title: String?, text: String)],
        candidates: [InboxDestinationAtlas.ScoredEntry],
        corrections: [InboxRoutingCorrectionLedger.Example]
    ) async -> [String: Decision] {
        guard !items.isEmpty, !candidates.isEmpty else { return [:] }
        let prompt = Self.buildSweepPrompt(items: items, candidates: candidates, corrections: corrections)
        let maxTokens = min(4000, 220 * items.count)

        var raw: String?
        for attempt in 1...maxAttempts {
            raw = await withTimeout(nanoseconds: sweepTimeoutNanoseconds) {
                try await ResearchService.shared.analyze(
                    prompt: prompt,
                    systemPrompt: Self.sweepSystemPrompt,
                    tier: .sensor,
                    maxTokens: maxTokens
                )
            }
            if raw != nil { break }
            if attempt < maxAttempts {
                print("[InboxAtlasRouter] sweep attempt \(attempt) timed out — retrying")
            }
        }
        guard let raw else { return [:] }
        return Self.parseSweep(raw: raw, candidates: candidates, validUUIDs: Set(items.map(\.uuid)))
    }

    private func withTimeout(_ work: @escaping @Sendable () async throws -> String) async -> String? {
        await withTimeout(nanoseconds: timeoutNanoseconds, work)
    }

    private func withTimeout(
        nanoseconds: UInt64,
        _ work: @escaping @Sendable () async throws -> String
    ) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask { try? await work() }
            group.addTask {
                try? await Task.sleep(nanoseconds: nanoseconds)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: - Prompt

    static let validSections: Set<String> = [
        "goal", "problems", "claims", "evidence", "benefits",
        "examples", "beliefsObjections", "process", "openQuestions"
    ]

    static let systemPrompt = """
    You are Cosmo's Atlas Router. The user captured a thought; you decide where it does the most \
    work in their knowledge workspace. You receive the capture and a shortlist of real destinations \
    (with keys). Answer with MOVES — what the capture should become — not just where to file it.

    THE MOVES (use the kind value exactly):
    - "fileToDestination" — save in a listed GROUP or attach a reference to a listed PAGE. \
    targetKey must name that exact Group or Page. Group membership never changes canvas layout; \
    Page references never change writing or authored order. Do not propose moving existing Pages \
    or creating Groups. This is a normal home for useful captured writing and supporting material.
    - "advanceQuestion" — the capture is material (evidence, an insight, a lead, a source) that helps \
    answer one of the OPEN QUESTIONS listed. targetKey = that question's key.
    - "spawnQuestion" — the capture IS a research question worth pursuing that no listed open question \
    already covers. targetKey = the research topic (deepdive key) it belongs to; newTitle = a cleaned \
    phrasing of the question. If answering it would materially advance a listed open question, set \
    parentQuestionKey to that question's key (a decomposition); otherwise leave it null (top level).
    - "feedConnection" — the capture develops one of the CONCEPT PAGES listed. targetKey = that page's \
    key; section = exactly one of: goal, problems, claims, evidence, benefits, examples, \
    beliefsObjections, process, openQuestions. Pick the section by what the text IS (a cited finding → \
    evidence; a counterargument → beliefsObjections; a concrete instance → examples; a how-to step → \
    process; an unresolved question about the concept → openQuestions).
    - "attachClient" — the capture is a content idea or material FOR one of the CLIENTS listed. \
    targetKey = that client's key. THE NICHE TEST: attach a client ONLY when the capture's subject \
    matter sits inside that client's stated niche, or the capture names the client. Working with a \
    client often is NOT evidence — never attach by familiarity or recency. If the subject fits no \
    listed niche, do not attach any client.
    - "placeCluster" — the capture belongs with an existing cluster's material. targetKey = cluster key.
    - "placeThinkspace" — it fits a workspace but no cluster there. targetKey = thinkspace key.
    - "feedSeedling" — the capture adds mass to one of the GROWING SEEDLINGS listed (a named \
    proto-concept still accruing thoughts before it earns a page). targetKey = that seedling's key. \
    A THOUGHT THAT DEVELOPS A NAMED GROWING CONCEPT FEEDS IT: the seedling is where such thoughts \
    belong, and a Page or Group is for material — never for a thought about a concept the user is \
    already growing. Match on the seedling's name, its aliases, and the thoughts it already holds; \
    a capture that would sit naturally beside those thoughts feeds the seedling.
    - "startSeedling" — the capture states a reusable principle, framework, or named idea that no \
    listed seedling or concept page covers. newTitle = a noun-phrase name for the concept. The \
    seedling grows in the nursery — no page and no canvas object is created until it ripens and the \
    user develops it. Not for fleeting notes.
    Seedling moves may ALSO carry "homeKey": the key of exactly ONE cluster or workspace from \
    DESTINATIONS whose material the developed concept would sit beside — its future home. This \
    places nothing now; it only tags where the concept belongs once it becomes a page. Set homeKey \
    null unless one home is obvious.
    - "startInquiry" — the capture is something the user wants to RESEARCH or UNDERSTAND (a topic \
    to investigate, "research X", "look into Y", "how does X affect Y", "what do we know about Z") \
    and one of the WORKSPACES listed is where that research belongs. targetKey = that workspace's \
    key; newTitle = the question phrased as ONE clear research question (keep the user's words; end \
    with a question mark). This starts a resumable inquiry session inside the workspace with the \
    capture as its question — a room to investigate in, not a note. Prefer startInquiry over \
    spawnQuestion when the capture is a whole line of research rather than a narrow sub-question \
    of a listed open question.
    - "germinateDeepDive" — the capture is a research topic (as above) but NO listed workspace \
    covers it. newTitle = a short name for the NEW workspace (a topic noun phrase, 2–5 words). \
    A new Space is created with that name and the inquiry starts inside it, with the capture as \
    the question. Use it whenever a research capture has no workspace home — never leave a \
    research capture unrouted just because the topic is new.
    - "fileAsSwipe" — the capture is CRAFT REFERENCE: the user saved it for its FORM — how it is \
    written, laid out, or sold — rather than for what it claims. No targetKey. A sales page, a \
    landing page, an ad, a screenshot of someone's post, a headline or a piece of copy with no \
    question attached is a swipe. THE FORM TEST, applied literally: would the user open this again \
    to COPY HOW IT IS BUILT, or to LEARN WHAT IT SAYS? Copy-how → fileAsSwipe. Learn-what → \
    fileAsResearch when the capture IS a source (a link, a video, a paper), or another move when the \
    capture is itself a thought. A capture that asks a question, states a fact worth remembering, \
    or names something to do is NEVER a swipe, even when it carries a link.
    - "fileAsResearch" — the capture is a SOURCE saved for its CONTENT: a link, video, talk, paper, \
    or article the user wants to read, watch, study, or cite later ("watch this", "read later", \
    "study this", a bare link with no craft intent, a link plus a note about what it says). It \
    becomes a research source — never a swipe. targetKey = the WORKSPACE whose subjects it serves \
    (the source lands with that workspace's materials, ready for Study), or a CONCEPT PAGE it is a \
    source for (it links to the page and waits in its References), or null when neither is \
    obvious (the Library). When the input carries a LINK LENS line measured by the app, treat it \
    as strong evidence between fileAsSwipe and fileAsResearch.

    HOW TO DECIDE (in order):
    1. TYPE TEST — what is this capture? A task/reminder ("do X", "follow up", a deadline) → \
    captureType "task", moves []. Tasks are handled elsewhere; never route them to knowledge \
    destinations. A question → "question". A claim/insight/principle → "insight". A content/product \
    idea → "idea". A link/citation/reading pointer → "source". Otherwise → "note".
    2. CLIENT TEST — apply the niche test above. attachClient may accompany one other move (an idea \
    can be for a client AND feed a concept page).
    3. DESTINATION TEST — a destination matches only if the capture would sit naturally next to its \
    charter and example contents. The name alone is never enough evidence.
    4. QUESTIONS BEFORE FOLDERS — if the capture is a question or clearly serves one, prefer \
    advanceQuestion/spawnQuestion over spatial placement; research threads compound, folders don't. \
    RESEARCH GETS A ROOM — a capture that names something to research or understand (not a fact, \
    not a task) becomes an inquiry: startInquiry in the workspace it belongs to, or \
    germinateDeepDive when no workspace fits. Filing a research intent as a Page loses it.
    5. MATCH THE USER’S WORK — Pages and Groups are valid homes for material and writing. A \
    thought about a concept that is GROWING (a listed seedling) feeds that seedling — that is what \
    the nursery is for; suggest startSeedling when a capture names a reusable idea no seedling or \
    page covers. A Page destination attaches a reference; a Group destination adds membership. No \
    suggestion changes authored section order or creates a canvas layout.
    6. ABSTAIN OVER GUESS — if two destinations feel equally plausible, or nothing fits, return \
    fewer moves or none. moves: [] is a correct, honest answer. Guessing wrong is worse.

    HARD RULES:
    1. NEVER invent keys — targetKey, parentQuestionKey, and homeKey must be copied verbatim from \
    DESTINATIONS (homeKey additionally must be a cluster or workspace key).
    2. At most 3 moves, ranked best first. At most ONE creation move (spawnQuestion, startInquiry, \
    germinateDeepDive, startSeedling) per capture.
    3. "title": a concise title for the capture, at most 10 words, preserving the user's language.
    4. "growth": one short sentence on what accepting the move builds ("adds evidence to a maturing \
    concept", "opens a branch under an active question"). No filler.
    5. confidence 0-1 per move: 0.85+ only when the fit is unmistakable; below 0.55 means you should \
    usually drop the move instead.
    6. PAST USER DECISIONS in the input are learned rules — when a capture resembles one, follow the \
    user's choice. They override your instincts.
    7. Respond with VALID JSON only. No prose, no markdown fences.

    WORKED EXAMPLES:

    Example A — a question spawns a branch under the topic it advances:
    Capture: "how much of willpower is actually just environment design?"
    DESTINATIONS include {"key":"deepdive-D1"} Discipline & Self-Regulation (open question \
    {"key":"question-Q1"} "How do I build systems that don't rely on motivation?")
    → {"title":"Willpower vs environment design","captureType":"question","moves":[{"kind":"spawnQuestion",\
    "targetKey":"deepdive-D1","section":null,"newTitle":"How much of willpower is environment design?",\
    "parentQuestionKey":"question-Q1","growth":"Opens a branch that directly advances the systems question.",\
    "confidence":0.85}]}

    Example A2 — a research intent becomes an inquiry in the workspace it belongs to:
    Capture: "research the effects of chronic stress on the body, mind and creativity"
    DESTINATIONS include workspace {"key":"thinkspace-W3"} Health & Performance, and no open \
    question about stress.
    → {"title":"Effects of chronic stress on body, mind, creativity","captureType":"question",\
    "moves":[{"kind":"startInquiry","targetKey":"thinkspace-W3","section":null,\
    "newTitle":"How does chronic stress affect the body, mind, and creativity?","parentQuestionKey":null,\
    "homeKey":null,"growth":"Opens a resumable inquiry in Health & Performance with sources and evidence to follow.",\
    "confidence":0.85}]}
    (A "research X" capture is an inquiry, not a page. Had no workspace fit, the move would be \
    germinateDeepDive with newTitle "Chronic stress" — a new Space with the inquiry inside.)

    Example B — an attributed finding feeds a concept page's evidence:
    Capture: "A 2023 meta-analysis found habit formation takes 59-66 days on average, not 21"
    DESTINATIONS include {"key":"connection-C4"} "Habit Loops" (developed sections: claims, examples)
    → {"title":"Habit formation takes 59-66 days","captureType":"insight","moves":[{"kind":"feedConnection",\
    "targetKey":"connection-C4","section":"evidence","newTitle":null,"parentQuestionKey":null,\
    "growth":"Adds cited evidence to a page that has claims but no support yet.","confidence":0.9}]}

    Example B2 — a raw insight grows a seedling instead of landing on a canvas:
    Capture: "What you think about most develops itself and feeds you ideas — make repeated mental \
    thoughts intentional"
    DESTINATIONS include {"key":"cluster-K2"} Mindset (in Philosophy), and \
    {"key":"seedling-S1"} "Directed attention" — Growing seedling (3 thoughts).
    → {"title":"Repeated thoughts compound — direct them","captureType":"insight","moves":[{"kind":"feedSeedling",\
    "targetKey":"seedling-S1","section":null,"newTitle":null,"parentQuestionKey":null,"homeKey":"cluster-K2",\
    "growth":"Fourth thought on directed attention — the seedling is nearly ripe.","confidence":0.85}]}
    (The Mindset cluster fits thematically, but a raw thought grows; it does not get pinned to a canvas. \
    homeKey tags Mindset as where the concept will live once developed.)

    Example B3 — a principle with no home starts a seedling, never a page:
    Capture: "constraints are a gift: the smaller the canvas, the sharper the idea"
    DESTINATIONS list no seedling or concept page about constraints.
    → {"title":"Constraints sharpen ideas","captureType":"insight","moves":[{"kind":"startSeedling",\
    "targetKey":null,"section":null,"newTitle":"Constraints as a creative gift","parentQuestionKey":null,\
    "homeKey":null,"growth":"Names a proto-concept so future thoughts about constraints accrue in one place.",\
    "confidence":0.7}]}

    Example C — the niche test picks the right client (and vetoes the familiar one):
    Capture: "hook idea: what a $40k emergency fund actually feels like"
    DESTINATIONS include clients {"key":"client-A"} Mara — Niche: strength training for women, and \
    {"key":"client-B"} Deshawn — Niche: personal finance for first-generation earners.
    → {"title":"Hook: what a $40k emergency fund feels like","captureType":"idea","moves":[{"kind":"attachClient",\
    "targetKey":"client-B","section":null,"newTitle":null,"parentQuestionKey":null,\
    "growth":"A hook squarely in Deshawn's personal-finance lane.","confidence":0.85}]}
    (Money is Deshawn's niche. Mara being the most-worked-with client is not evidence.)

    Example C2 — a link saved to LEARN from becomes a research source in its workspace:
    Capture: "https://youtu.be/E_kVAVk9ioU — talk on how sleep debt wrecks decision making"
    LINK LENS: Research — Unrecognised source
    DESTINATIONS include workspace {"key":"thinkspace-W3"} Health & Performance.
    → {"title":"Talk: sleep debt and decision making","captureType":"source","moves":[{"kind":"fileAsResearch",\
    "targetKey":"thinkspace-W3","section":null,"newTitle":null,"parentQuestionKey":null,"homeKey":null,\
    "growth":"Adds a source to Health & Performance's materials, ready to open in Study.","confidence":0.85}]}
    (A talk is watched to LEARN what it says — research, not a swipe. Had no workspace fit, targetKey \
    would be null and the source would land in the Library.)

    Example D — a task never routes to knowledge destinations:
    Capture: "remember to send the invoice thursday"
    → {"title":"Send the invoice Thursday","captureType":"task","moves":[]}

    Example E — ambiguity abstains:
    Capture: "interesting thought about systems"
    → {"title":"Thought about systems","captureType":"note","moves":[]}

    OUTPUT SCHEMA:
    {"title":"<concise title>","captureType":"task|question|insight|idea|note|source",\
    "moves":[{"kind":"<move kind>","targetKey":"<key or null>","section":"<section or null>",\
    "newTitle":"<title or null>","parentQuestionKey":"<key or null>","homeKey":"<key or null>",\
    "growth":"<one line>","confidence":<0-1>}]}
    """

    /// The sweep speaks the identical move ladder over several captures at
    /// once — the system prompt is the single-capture teaching plus batch
    /// framing, so the two paths can never drift apart.
    static let sweepSystemPrompt = systemPrompt + """


    SWEEP MODE: this request carries SEVERAL captures, each tagged with its uuid. Decide each \
    capture independently with the exact move ladder above — the other captures are not context \
    for each other. "moves": [] stays a correct, honest answer for any capture that fits nothing. \
    Respond with ONLY a JSON array, one entry per capture, each entry in the single-capture \
    OUTPUT SCHEMA plus its "uuid":
    [{"uuid":"<capture uuid>","title":"…","captureType":"…","moves":[…]}]
    """

    static func buildPrompt(
        text: String,
        heuristicTitle: String,
        candidates: [InboxDestinationAtlas.ScoredEntry],
        corrections: [InboxRoutingCorrectionLedger.Example],
        lensHint: String? = nil
    ) -> String {
        var lines = destinationAndCorrectionLines(candidates: candidates, corrections: corrections)
        lines.append("\nCAPTURE (heuristic title: \(heuristicTitle)):")
        lines.append(String(text.prefix(1600)))
        // The app measured the link's lens (platform family, page shape,
        // the user's own past decisions for this domain) — the model sees
        // the verdict and its reason, never a bare label.
        if let lensHint {
            lines.append("\nLINK LENS (measured by the app from the link itself): \(lensHint). Strong evidence between fileAsSwipe and fileAsResearch; override only when the user's own words say otherwise.")
        }
        lines.append("\nReturn the routing JSON now.")
        return lines.joined(separator: "\n")
    }

    /// The sweep prompt: the same destination cards and learned rules, then
    /// every capture tagged by uuid. Captures are clipped harder than the
    /// single path (the sweep is a recovery net, not first contact).
    static func buildSweepPrompt(
        items: [(uuid: String, title: String?, text: String)],
        candidates: [InboxDestinationAtlas.ScoredEntry],
        corrections: [InboxRoutingCorrectionLedger.Example]
    ) -> String {
        var lines = destinationAndCorrectionLines(candidates: candidates, corrections: corrections)
        lines.append("\nCAPTURES:")
        for (index, item) in items.enumerated() {
            let heading = item.title.map { "\($0) — " } ?? ""
            lines.append("C\(index + 1) (uuid \(item.uuid)): \(String((heading + item.text).prefix(400)))")
        }
        lines.append("\nReturn the routing JSON array now.")
        return lines.joined(separator: "\n")
    }

    private static func destinationAndCorrectionLines(
        candidates: [InboxDestinationAtlas.ScoredEntry],
        corrections: [InboxRoutingCorrectionLedger.Example]
    ) -> [String] {
        var lines: [String] = []
        lines.append("DESTINATIONS (the only valid targetKey/parentQuestionKey/homeKey values):")

        let order: [(InboxAtlasKind, String)] = [
            (.client, "CLIENTS (apply the niche test; attaching none is common):"),
            (.question, "OPEN QUESTIONS:"),
            (.deepDive, "RESEARCH TOPICS:"),
            (.connection, "CONCEPT PAGES:"),
            (.seedling, "GROWING SEEDLINGS (thoughts about these concepts feed them):"),
            (.group, "GROUPS (membership only):"),
            (.page, "PAGES (attach original reference; never rewrite):"),
            (.cluster, "LEGACY GROUPS:"),
            (.thinkspace, "WORKSPACES:")
        ]
        for (kind, header) in order {
            let group = candidates.filter { $0.entry.kind == kind }
            guard !group.isEmpty else { continue }
            lines.append("\n\(header)")
            for scored in group {
                lines.append(card(for: scored.entry))
            }
        }

        if !corrections.isEmpty {
            lines.append("\nPAST USER DECISIONS (learned rules — follow these patterns, they override your instincts):")
            for example in corrections.prefix(8) {
                if let rejected = example.rejectedLabel {
                    lines.append("- \"\(example.text.prefix(140))\" → \(example.chosenLabel) (user rejected: \(rejected))")
                } else {
                    lines.append("- \"\(example.text.prefix(140))\" → \(example.chosenLabel)")
                }
            }
        }
        return lines
    }

    private static func card(for entry: InboxAtlasEntry) -> String {
        var line = "- {\"key\":\"\(entry.key)\"} \(entry.name)"
        if let parentName = entry.parentName {
            line += " (in \(parentName))"
        }
        line += " — \(entry.charter)"
        if !entry.examples.isEmpty {
            line += " Contains e.g. \(entry.examples.map { "\"\($0)\"" }.joined(separator: ", "))."
        }
        return line
    }

    // MARK: - Parse

    static func parse(
        raw: String,
        candidates: [InboxDestinationAtlas.ScoredEntry]
    ) -> Decision? {
        guard let dict = ConceptResolver.jsonObject(from: raw) else { return nil }
        let entriesByKey = Dictionary(uniqueKeysWithValues: candidates.map { ($0.entry.key, $0.entry) })
        return decision(fromEntry: dict, entriesByKey: entriesByKey)
    }

    /// The sweep answer: one Decision per capture uuid. Entries with invented
    /// uuids are dropped; a missing entry simply leaves that capture unsorted.
    static func parseSweep(
        raw: String,
        candidates: [InboxDestinationAtlas.ScoredEntry],
        validUUIDs: Set<String>
    ) -> [String: Decision] {
        guard let start = raw.firstIndex(of: "["),
              let end = raw.lastIndex(of: "]"),
              start < end,
              let data = String(raw[start...end]).data(using: .utf8),
              let entries = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return [:]
        }

        let entriesByKey = Dictionary(uniqueKeysWithValues: candidates.map { ($0.entry.key, $0.entry) })
        var decisions: [String: Decision] = [:]
        for entry in entries {
            guard let uuid = entry["uuid"] as? String, validUUIDs.contains(uuid) else { continue }
            decisions[uuid] = decision(fromEntry: entry, entriesByKey: entriesByKey)
        }
        return decisions
    }

    /// One capture's decision from its JSON entry — the single shared reader
    /// for the single-capture and sweep paths (they must never drift).
    private static func decision(
        fromEntry dict: [String: Any],
        entriesByKey: [String: InboxAtlasEntry]
    ) -> Decision {
        var title = (dict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if title?.isEmpty == true { title = nil }
        let captureType = (dict["captureType"] as? String)?.lowercased()

        var moves: [RoutedMove] = []
        var usedCreationMove = false
        for entry in (dict["moves"] as? [[String: Any]] ?? []).prefix(3) {
            if let move = parseMove(entry, entriesByKey: entriesByKey, usedCreationMove: &usedCreationMove) {
                moves.append(move)
            }
        }
        return Decision(title: title, captureType: captureType, moves: moves)
    }

    private static func parseMove(
        _ entry: [String: Any],
        entriesByKey: [String: InboxAtlasEntry],
        usedCreationMove: inout Bool
    ) -> RoutedMove? {
        guard let kindRaw = entry["kind"] as? String,
              let kind = MoveKind(rawValue: kindRaw) else { return nil }

        var targetKey = entry["targetKey"] as? String
        if let key = targetKey, entriesByKey[key] == nil {
            targetKey = nil   // Never trust invented keys.
        }

        var section = entry["section"] as? String
        if let s = section, !validSections.contains(s) { section = nil }

        var newTitle = (entry["newTitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if newTitle?.isEmpty == true { newTitle = nil }

        var parentQuestionKey = entry["parentQuestionKey"] as? String
        if let key = parentQuestionKey,
           entriesByKey[key]?.kind != .question {
            parentQuestionKey = nil   // Invented or non-question parents fall to top level.
        }

        // A concept's future home rides only on seedling moves, and only when
        // it names a real spatial destination.
        var homeKey = entry["homeKey"] as? String
        if kind != .feedSeedling && kind != .startSeedling {
            homeKey = nil
        } else if let key = homeKey {
            let homeKind = entriesByKey[key]?.kind
            if homeKind != .cluster && homeKind != .thinkspace { homeKey = nil }
        }

        let growth = (entry["growth"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let confidence = (entry["confidence"] as? Double) ?? 0.6

        // Per-kind structural validation — a move without its required
        // target is dropped, not repaired into a guess.
        switch kind {
        case .fileToDestination:
            guard let key = targetKey, let entry = entriesByKey[key],
                  entry.kind == .group || entry.kind == .page, entry.filingDestination != nil else { return nil }
        case .advanceQuestion:
            guard let key = targetKey, entriesByKey[key]?.kind == .question else { return nil }
        case .spawnQuestion:
            guard let key = targetKey, entriesByKey[key]?.kind == .deepDive, newTitle != nil else { return nil }
            if usedCreationMove { return nil }
            usedCreationMove = true
        case .feedConnection:
            guard let key = targetKey, entriesByKey[key]?.kind == .connection, section != nil else { return nil }
        case .attachClient:
            guard let key = targetKey, entriesByKey[key]?.kind == .client else { return nil }
        case .placeCluster:
            guard let key = targetKey, entriesByKey[key]?.kind == .cluster else { return nil }
        case .placeThinkspace:
            guard let key = targetKey, entriesByKey[key]?.kind == .thinkspace else { return nil }
        case .feedSeedling:
            guard let key = targetKey, entriesByKey[key]?.kind == .seedling else { return nil }
        case .startInquiry:
            // A Space hosts the session — the key must name a real workspace.
            // Without one the router should have said germinateDeepDive.
            guard let key = targetKey, entriesByKey[key]?.kind == .thinkspace, newTitle != nil else { return nil }
            if usedCreationMove { return nil }
            usedCreationMove = true
        case .startSeedling, .germinateDeepDive:
            guard newTitle != nil else { return nil }
            if usedCreationMove { return nil }
            usedCreationMove = true
            targetKey = nil
        case .fileAsSwipe:
            // A swipe has no Atlas destination — the swipe file IS the
            // destination, and which KIND of swipe is SwipeIntakeRouter's
            // call, never the router's. Any key the model attached is noise.
            targetKey = nil
            section = nil
        case .fileAsResearch:
            // A source may name its room (a workspace) or the page it is a
            // source for (a concept); anything else means the Library.
            if let key = targetKey, let kind = entriesByKey[key]?.kind, kind != .thinkspace && kind != .connection {
                targetKey = nil
            }
            section = nil
        }

        return RoutedMove(
            kind: kind,
            targetKey: targetKey,
            section: section,
            newTitle: newTitle,
            parentQuestionKey: parentQuestionKey,
            homeKey: homeKey,
            growth: growth,
            confidence: min(max(confidence, 0), 1)
        )
    }
}
