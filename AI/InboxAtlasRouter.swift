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
//   germinateDeepDive   — seed of a new research topic
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
        case spawnQuestion
        case feedConnection
        case attachClient
        case placeCluster
        case placeThinkspace
        case germinateConnection
        case germinateDeepDive
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
        /// One line on how this move grows the knowledge base.
        var growth: String
        var confidence: Double
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
    private let maxAttempts = 2

    private init() {}

    // MARK: - Route

    func route(
        text: String,
        heuristicTitle: String,
        candidates: [InboxDestinationAtlas.ScoredEntry],
        corrections: [InboxRoutingCorrectionLedger.Example]
    ) async -> Decision? {
        guard !candidates.isEmpty else { return nil }
        let prompt = Self.buildPrompt(
            text: text,
            heuristicTitle: heuristicTitle,
            candidates: candidates,
            corrections: corrections
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

    private func withTimeout(_ work: @escaping @Sendable () async throws -> String) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask { try? await work() }
            group.addTask { [timeoutNanoseconds] in
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
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
    - "germinateConnection" — the capture is the seed of a durable concept that deserves its own page \
    and no listed page covers it. newTitle = a noun-phrase name for the concept. Use sparingly: only \
    when the thought states a reusable principle, framework, or named idea — not for fleeting notes.
    - "germinateDeepDive" — the capture opens a substantial research territory no listed topic covers. \
    newTitle = the topic name. Rare; prefer spawnQuestion under an existing topic when one fits.

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
    advanceQuestion/spawnQuestion over spatial placement; research threads compound, folders don't.
    5. ABSTAIN OVER GUESS — if two destinations feel equally plausible, or nothing fits, return \
    fewer moves or none. moves: [] is a correct, honest answer. Guessing wrong is worse.

    HARD RULES:
    1. NEVER invent keys — targetKey and parentQuestionKey must be copied verbatim from DESTINATIONS.
    2. At most 3 moves, ranked best first. At most ONE spawnQuestion/germinate move per capture.
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

    Example B — an attributed finding feeds a concept page's evidence:
    Capture: "A 2023 meta-analysis found habit formation takes 59-66 days on average, not 21"
    DESTINATIONS include {"key":"connection-C4"} "Habit Loops" (developed sections: claims, examples)
    → {"title":"Habit formation takes 59-66 days","captureType":"insight","moves":[{"kind":"feedConnection",\
    "targetKey":"connection-C4","section":"evidence","newTitle":null,"parentQuestionKey":null,\
    "growth":"Adds cited evidence to a page that has claims but no support yet.","confidence":0.9}]}

    Example C — the niche test picks the right client (and vetoes the familiar one):
    Capture: "hook idea: what a $40k emergency fund actually feels like"
    DESTINATIONS include clients {"key":"client-A"} Mara — Niche: strength training for women, and \
    {"key":"client-B"} Deshawn — Niche: personal finance for first-generation earners.
    → {"title":"Hook: what a $40k emergency fund feels like","captureType":"idea","moves":[{"kind":"attachClient",\
    "targetKey":"client-B","section":null,"newTitle":null,"parentQuestionKey":null,\
    "growth":"A hook squarely in Deshawn's personal-finance lane.","confidence":0.85}]}
    (Money is Deshawn's niche. Mara being the most-worked-with client is not evidence.)

    Example D — a task never routes to knowledge destinations:
    Capture: "remember to send the invoice thursday"
    → {"title":"Send the invoice Thursday","captureType":"task","moves":[]}

    Example E — ambiguity abstains:
    Capture: "interesting thought about systems"
    → {"title":"Thought about systems","captureType":"note","moves":[]}

    OUTPUT SCHEMA:
    {"title":"<concise title>","captureType":"task|question|insight|idea|note|source",\
    "moves":[{"kind":"<move kind>","targetKey":"<key or null>","section":"<section or null>",\
    "newTitle":"<title or null>","parentQuestionKey":"<key or null>","growth":"<one line>",\
    "confidence":<0-1>}]}
    """

    static func buildPrompt(
        text: String,
        heuristicTitle: String,
        candidates: [InboxDestinationAtlas.ScoredEntry],
        corrections: [InboxRoutingCorrectionLedger.Example]
    ) -> String {
        var lines: [String] = []
        lines.append("DESTINATIONS (the only valid targetKey/parentQuestionKey values):")

        let order: [(InboxAtlasKind, String)] = [
            (.client, "CLIENTS (apply the niche test; attaching none is common):"),
            (.question, "OPEN QUESTIONS:"),
            (.deepDive, "RESEARCH TOPICS:"),
            (.connection, "CONCEPT PAGES:"),
            (.cluster, "CLUSTERS:"),
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

        lines.append("\nCAPTURE (heuristic title: \(heuristicTitle)):")
        lines.append(String(text.prefix(1600)))
        lines.append("\nReturn the routing JSON now.")
        return lines.joined(separator: "\n")
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

        var title = (dict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if title?.isEmpty == true { title = nil }
        let captureType = (dict["captureType"] as? String)?.lowercased()

        var moves: [RoutedMove] = []
        var usedCreationMove = false

        for entry in (dict["moves"] as? [[String: Any]] ?? []).prefix(3) {
            guard let kindRaw = entry["kind"] as? String,
                  let kind = MoveKind(rawValue: kindRaw) else { continue }

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

            let growth = (entry["growth"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let confidence = (entry["confidence"] as? Double) ?? 0.6

            // Per-kind structural validation — a move without its required
            // target is dropped, not repaired into a guess.
            switch kind {
            case .advanceQuestion:
                guard let key = targetKey, entriesByKey[key]?.kind == .question else { continue }
            case .spawnQuestion:
                guard let key = targetKey, entriesByKey[key]?.kind == .deepDive, newTitle != nil else { continue }
                if usedCreationMove { continue }
                usedCreationMove = true
            case .feedConnection:
                guard let key = targetKey, entriesByKey[key]?.kind == .connection, section != nil else { continue }
            case .attachClient:
                guard let key = targetKey, entriesByKey[key]?.kind == .client else { continue }
            case .placeCluster:
                guard let key = targetKey, entriesByKey[key]?.kind == .cluster else { continue }
            case .placeThinkspace:
                guard let key = targetKey, entriesByKey[key]?.kind == .thinkspace else { continue }
            case .germinateConnection, .germinateDeepDive:
                guard newTitle != nil else { continue }
                if usedCreationMove { continue }
                usedCreationMove = true
                targetKey = nil
            }

            moves.append(RoutedMove(
                kind: kind,
                targetKey: targetKey,
                section: section,
                newTitle: newTitle,
                parentQuestionKey: parentQuestionKey,
                growth: growth,
                confidence: min(max(confidence, 0), 1)
            ))
        }

        return Decision(title: title, captureType: captureType, moves: moves)
    }
}
