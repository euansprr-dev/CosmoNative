// CosmoOS/AI/ConceptResolver.swift
// Concept-first knowledge routing: given a session's extracts and the Deep Dive's
// existing knowledge (lexicon + Connection pages), decide which durable concept
// each extract belongs to, and whether each concept needs a new Connection page
// or should merge into an existing one.
//
// Falls back to deterministic heuristics (lexicon/connection title matching)
// when the LLM is unavailable.

import Foundation

actor ConceptResolver {
    static let shared = ConceptResolver()

    struct Input: Sendable {
        var deepDive: Atom?
        var session: Atom
        var extracts: [Atom]
        var lexicon: [Atom]
        var existingConnections: [Atom]
        var questions: [Atom]
    }

    enum Action: Sendable, Equatable {
        case createNew
        case mergeInto(connectionUUID: String)
    }

    struct ConceptAssignment: Sendable, Identifiable {
        var id: String { conceptKey }
        var conceptKey: String          // Normalized concept name
        var conceptName: String         // Display name, e.g. "Pranayama"
        var aliases: [String]
        var action: Action
        var extractUUIDs: [String]
        var rationale: String
        var confidence: Double
        var relatedConceptNames: [String] = []   // Other pages this one mentions → hyperlinks
        var parentConceptName: String? = nil     // The ONE broader page this nests under (map hierarchy)
    }

    /// Resolves concept assignments for a session's extracts.
    /// One LLM call sees the WHOLE session — every extract, with any capture-time
    /// concept tags included as hints — so pages consolidate instead of
    /// fragmenting one tag at a time. Tagged extracts the model omits are
    /// backfilled into EXISTING pages only (merge-only: the backfill can never
    /// create a new page). Falls back to tags + heuristics offline. Never throws.
    func resolve(_ input: Input) async -> [ConceptAssignment] {
        guard !input.extracts.isEmpty else { return [] }
        let preassigned = Self.assignmentsFromPersistedTags(input)
        do {
            let raw = try await ResearchService.shared.analyze(
                prompt: buildPrompt(input),
                systemPrompt: Self.systemPrompt,
                tier: .strategist,
                maxTokens: 2400
            )
            let parsed = parse(raw: raw, input: input)
            if !parsed.isEmpty {
                let backfill = preassigned.filter { assignment in
                    if case .mergeInto = assignment.action { return true }
                    return false
                }
                return Self.consolidated(Self.merged(parsed, backfill))
            }
        } catch {
            print("[ConceptResolver] LLM failed: \(error) — using tag + heuristic assignments")
        }
        return Self.consolidated(Self.merged(preassigned, Self.heuristicAssignments(input)))
    }

    // MARK: - Prompt

    static let systemPrompt = """
    You are Cosmo's Concept Resolver. Your job: organize research extracts into durable CONCEPT PAGES.

    A concept page is a permanent knowledge document about ONE noun-phrase concept — a thing, practice, \
    mechanism, or named idea. Examples of good concept names: "Pranayama", "Vagus nerve", "CO2 tolerance", \
    "Breath-spirit connection". A concept page is NEVER a question ("What is pranayama?" is wrong — the \
    concept is "Pranayama"). It is NEVER a session ("Tuesday's research" is wrong). It survives across many \
    research sessions: future sessions will merge new extracts into the same page.

    You receive:
    1. EXTRACTS — each with a UUID, kind, optional capture-time tags, and text. Tags were added mid-session \
    by a quick router with no overview: treat them as HINTS, not verdicts — consolidate freely. But when a \
    tag matches an EXISTING page, prefer merging that extract into it.
    2. EXISTING CONCEPT PAGES — each with a UUID and title. If an extract belongs to one of these, you MUST \
    merge into it by its UUID rather than creating a near-duplicate page.
    3. HOME CONCEPT — the Deep Dive's own topic. Extracts about the topic in general belong on its page \
    (when it appears in EXISTING CONCEPT PAGES), not on new miscellaneous pages.
    4. LEXICON TERMS — vocabulary the user has accumulated; prefer these spellings for concept names.

    THE GRANULARITY RUBRIC — what earns a page:
    - The encyclopedia-entry litmus: a page is a topic someone would look up on its own and revisit across \
    sessions. An ASPECT of a topic — its benefits, its history, its steps, its problems — is NEVER its own \
    page; that material merges into the topic's page. "Benefits of pranayama" is wrong: those extracts \
    belong on "Pranayama".
    - Create a NEW page only when (a) 2+ extracts substantively develop the concept, OR (b) one extract \
    but the concept is clearly central to the Deep Dive and will accrue more — justify this in rationale.
    - Otherwise merge the material into the closest existing page (or the home concept's page) and name \
    the concept in that assignment's relatedConcepts — it earns its own page in a later session once more \
    material accrues.
    - Calibration: a typical session yields 0-3 new pages. If you are proposing more than 4, you are \
    fragmenting — consolidate.

    Decision rules, in order:
    - If an extract's main subject matches an existing page (same concept, even with different wording), \
    assign action "merge" with that page's UUID. "Pranayama breathing" matches an existing "Pranayama" page.
    - If 2+ extracts share a subject with no existing page, create ONE new concept ("create").
    - OVERLAP IS GOOD: one extract may belong to MULTIPLE concepts — when a benefit, mechanism, or example \
    genuinely applies to two pages, list its UUID under BOTH. Do not pick one.
    - relatedConcepts: for each assignment, list the other concept pages (from this plan or from EXISTING \
    pages, by name) that this page mentions or depends on. These become hyperlinks between pages — be \
    generous but truthful.
    - parentConcept: every assignment ALSO names the ONE broader concept page it sits inside, chosen from \
    this plan, EXISTING pages, or the HOME CONCEPT. This builds the knowledge map's hierarchy: "Flow \
    state" sits inside "Peak human experience"; "Box breathing" sits inside "Breathwork". Use null ONLY \
    when the concept is itself a top-level pillar of the Deep Dive. A concept is never its own parent. \
    Top-level pillars are RARE: once a dive already has several pillars, a new concept almost always \
    belongs inside one of the existing pages — null means "genuinely new territory", never "didn't look".
    - If an extract is too vague, personal, or session-specific to belong to any durable concept, OMIT it \
    entirely. Do not force assignments.
    - Never invent UUIDs. Only use extract UUIDs and connection UUIDs that appear in the input.

    Worked examples:

    Example A (merge into existing): Existing page {"uuid":"abc-1","title":"Pranayama"}. \
    Extract {"uuid":"e-9","text":"Bhastrika is an energizing pranayama involving forced exhales"}. \
    → {"conceptName":"Pranayama","action":"merge","connectionUUID":"abc-1","extractUUIDs":["e-9"]}

    Example B (create new): No existing pages. Deep Dive is "Breathwork". Extracts e-1 "Vagal tone \
    improves with slow exhales", e-2 "The vagus nerve links breath rate to heart rate". \
    → {"conceptName":"Vagus nerve","action":"create","extractUUIDs":["e-1","e-2"],"relatedConcepts":["Coherent breathing"],"parentConcept":"Breathwork"}

    Example C (multi-concept extract): Extract e-4 "Slow pranayama raises vagal tone within minutes" \
    bridges both → its UUID appears under BOTH "Pranayama" (merge, if a page exists) and "Vagus nerve", \
    and each page lists the other in relatedConcepts.

    Example D (leave unassigned): Extract e-7 "remember to ask Maria about her teacher" is personal/\
    session-specific → appears in NO assignment.

    Example E (aspect folds into its topic): Existing page {"uuid":"abc-1","title":"Breathwork"}. \
    Extracts e-11 "Breathwork lowers stress", e-12 "It also improves sleep quality" (tagged \
    ["Benefits of breathwork"]). "Benefits of breathwork" is an ASPECT, not a topic → \
    {"conceptName":"Breathwork","action":"merge","connectionUUID":"abc-1","extractUUIDs":["e-11","e-12"]}. \
    No "Benefits of breathwork" page is ever created.

    ALWAYS respond with VALID JSON only, no prose, matching:
    {
      "assignments": [
        {
          "conceptName": "<noun phrase>",
          "aliases": ["<alternate name>", ...],
          "action": "create" | "merge",
          "connectionUUID": "<existing page UUID, required when action is merge>",
          "extractUUIDs": ["<uuid>", ...],
          "relatedConcepts": ["<other concept page name>", ...],
          "parentConcept": "<broader concept page name, or null for a top-level pillar>",
          "rationale": "<one sentence>",
          "confidence": <0.0-1.0>
        }
      ]
    }
    """

    private func buildPrompt(_ input: Input) -> String {
        var lines: [String] = []
        if let dd = input.deepDive {
            lines.append("HOME CONCEPT (the Deep Dive's own topic): \(dd.title ?? "Untitled")")
        }
        if !input.existingConnections.isEmpty {
            lines.append("\nEXISTING CONCEPT PAGES:")
            for connection in input.existingConnections.prefix(40) {
                lines.append(#"- {"uuid":"\#(connection.uuid)","title":"\#(connection.title ?? "Untitled")"}"#)
            }
        } else {
            lines.append("\nEXISTING CONCEPT PAGES: none")
        }
        if !input.lexicon.isEmpty {
            let terms = input.lexicon.prefix(30).compactMap(\.title).joined(separator: ", ")
            lines.append("\nLEXICON TERMS: \(terms)")
        }
        lines.append("\nEXTRACTS:")
        for extract in input.extracts.prefix(60) {
            let kind = extract.extractMetadata?.kind.rawValue ?? "extract"
            let body = (extract.body ?? extract.title ?? "").prefix(280)
            let tags = extract.extractMetadata?.conceptNames ?? []
            if tags.isEmpty {
                lines.append(#"- {"uuid":"\#(extract.uuid)","kind":"\#(kind)","text":"\#(body)"}"#)
            } else {
                let tagList = tags.prefix(3).map { #""\#($0)""# }.joined(separator: ",")
                lines.append(#"- {"uuid":"\#(extract.uuid)","kind":"\#(kind)","tags":[\#(tagList)],"text":"\#(body)"}"#)
            }
        }
        lines.append("\n---\nAssign these extracts to concept pages per the system prompt rules. JSON only.")
        return lines.joined(separator: "\n")
    }

    // MARK: - Parsing

    private func parse(raw: String, input: Input) -> [ConceptAssignment] {
        guard let dict = Self.jsonObject(from: raw),
              let array = dict["assignments"] as? [[String: Any]] else { return [] }

        let validExtractUUIDs = Set(input.extracts.map(\.uuid))
        let validConnectionUUIDs = Set(input.existingConnections.map(\.uuid))

        var assignments: [ConceptAssignment] = []
        var seenKeys = Set<String>()
        for entry in array {
            guard let name = (entry["conceptName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { continue }
            let key = Self.conceptKey(name)
            guard !seenKeys.contains(key) else { continue }

            let extractUUIDs = ((entry["extractUUIDs"] as? [String]) ?? []).filter(validExtractUUIDs.contains)
            guard !extractUUIDs.isEmpty else { continue }

            let action: Action
            if (entry["action"] as? String) == "merge",
               let target = entry["connectionUUID"] as? String,
               validConnectionUUIDs.contains(target) {
                action = .mergeInto(connectionUUID: target)
            } else {
                // Defensive: if the model said "create" but a page with this title exists, merge anyway.
                if let existing = input.existingConnections.first(where: { Self.conceptKey($0.title ?? "") == key }) {
                    action = .mergeInto(connectionUUID: existing.uuid)
                } else {
                    action = .createNew
                }
            }

            var parentName = (entry["parentConcept"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let candidate = parentName, candidate.isEmpty || Self.conceptKey(candidate) == key {
                parentName = nil   // A concept is never its own parent.
            }
            seenKeys.insert(key)
            assignments.append(ConceptAssignment(
                conceptKey: key,
                conceptName: name,
                aliases: (entry["aliases"] as? [String]) ?? [],
                action: action,
                extractUUIDs: extractUUIDs,
                rationale: (entry["rationale"] as? String) ?? "",
                confidence: (entry["confidence"] as? Double) ?? 0.6,
                relatedConceptNames: ((entry["relatedConcepts"] as? [String]) ?? [])
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && Self.conceptKey($0) != key },
                parentConceptName: parentName
            ))
        }
        return assignments
    }

    // MARK: - Persisted-tag pre-assignment

    /// Builds assignments from the `conceptNames` the live router persisted on each
    /// extract during capture. Merge-vs-create resolves by matching existing
    /// connection titles. Deterministic — no LLM.
    nonisolated static func assignmentsFromPersistedTags(_ input: Input) -> [ConceptAssignment] {
        var buckets: [String: (name: String, extractUUIDs: [String])] = [:]
        var order: [String] = []
        for extract in input.extracts {
            for name in extract.extractMetadata?.conceptNames ?? [] {
                let key = conceptKey(name)
                guard !key.isEmpty else { continue }
                if buckets[key] == nil { order.append(key) }
                buckets[key, default: (name, [])].extractUUIDs.append(extract.uuid)
            }
        }
        guard !buckets.isEmpty else { return [] }
        let connectionsByKey = Dictionary(
            input.existingConnections.compactMap { connection -> (String, Atom)? in
                guard let title = connection.title, !title.isEmpty else { return nil }
                return (conceptKey(title), connection)
            },
            uniquingKeysWith: { first, _ in first }
        )
        return order.compactMap { key in
            guard let bucket = buckets[key] else { return nil }
            let existing = connectionsByKey[key]
            return ConceptAssignment(
                conceptKey: key,
                conceptName: existing?.title ?? bucket.name,
                aliases: [],
                action: existing.map { .mergeInto(connectionUUID: $0.uuid) } ?? .createNew,
                extractUUIDs: bucket.extractUUIDs,
                rationale: "Concept tagged at capture time by the live router.",
                confidence: 0.9
            )
        }
    }

    /// Merges two assignment lists by concept key: extract UUID sets union, and a
    /// merge target wins over create when either side found an existing page.
    nonisolated static func merged(
        _ primary: [ConceptAssignment],
        _ secondary: [ConceptAssignment]
    ) -> [ConceptAssignment] {
        var result = primary
        var indexByKey = Dictionary(
            result.enumerated().map { ($0.element.conceptKey, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        for assignment in secondary {
            if let idx = indexByKey[assignment.conceptKey] {
                let known = Set(result[idx].extractUUIDs)
                result[idx].extractUUIDs += assignment.extractUUIDs.filter { !known.contains($0) }
                if case .createNew = result[idx].action, case .mergeInto = assignment.action {
                    result[idx].action = assignment.action
                }
                let knownRelated = Set(result[idx].relatedConceptNames.map(conceptKey))
                result[idx].relatedConceptNames += assignment.relatedConceptNames
                    .filter { !knownRelated.contains(conceptKey($0)) }
            } else {
                indexByKey[assignment.conceptKey] = result.count
                result.append(assignment)
            }
        }
        return result
    }

    // MARK: - Deterministic consolidation post-pass

    /// Anti-fragmentation safety net applied to every resolver result (LLM and
    /// fallback alike):
    /// 1. Near-duplicate fold — assignments whose concept keys are token-subsets
    ///    of each other ("breathing" ⊂ "box breathing") collapse into whichever
    ///    holds more material; the folded name survives as an alias.
    /// 2. Singleton fold — a one-extract "create" whose extract already lives in
    ///    another assignment is dropped; its name survives as a relatedConcept
    ///    (a mention link), not a page.
    nonisolated static func consolidated(_ assignments: [ConceptAssignment]) -> [ConceptAssignment] {
        guard assignments.count > 1 else { return assignments }
        var result = assignments
        // Folded concept names may still be referenced as parents — remember
        // where each folded concept went so parent links follow the survivor.
        var foldedInto: [String: String] = [:]   // folded conceptKey → survivor conceptName

        // 1. Near-duplicate fold.
        var didFold = true
        while didFold {
            didFold = false
            outer: for i in result.indices {
                for j in result.indices where i != j {
                    let a = Set(result[i].conceptKey.split(separator: " ").map(String.init))
                    let b = Set(result[j].conceptKey.split(separator: " ").map(String.init))
                    guard !a.isEmpty, !b.isEmpty, a != b, a.isSubset(of: b) || b.isSubset(of: a) else { continue }
                    // Survivor = more material; a merge action always survives a create.
                    var survivorIdx = result[i].extractUUIDs.count >= result[j].extractUUIDs.count ? i : j
                    var otherIdx = survivorIdx == i ? j : i
                    if case .createNew = result[survivorIdx].action, case .mergeInto = result[otherIdx].action {
                        swap(&survivorIdx, &otherIdx)
                    }
                    var kept = result[survivorIdx]
                    let dropped = result[otherIdx]
                    let knownExtracts = Set(kept.extractUUIDs)
                    kept.extractUUIDs += dropped.extractUUIDs.filter { !knownExtracts.contains($0) }
                    if kept.conceptName != dropped.conceptName, !kept.aliases.contains(dropped.conceptName) {
                        kept.aliases.append(dropped.conceptName)
                    }
                    let knownRelated = Set(kept.relatedConceptNames.map(conceptKey) + [kept.conceptKey])
                    kept.relatedConceptNames += dropped.relatedConceptNames
                        .filter { !knownRelated.contains(conceptKey($0)) }
                    if kept.parentConceptName == nil { kept.parentConceptName = dropped.parentConceptName }
                    foldedInto[dropped.conceptKey] = kept.conceptName
                    result[survivorIdx] = kept
                    result.remove(at: otherIdx)
                    didFold = true
                    break outer
                }
            }
        }

        // 2. Singleton fold.
        let allExtractCounts = result.reduce(into: [String: Int]()) { counts, assignment in
            for uuid in assignment.extractUUIDs { counts[uuid, default: 0] += 1 }
        }
        var survivors: [ConceptAssignment] = []
        var mentionNames: [String] = []
        var singletonHomes: [String: String] = [:]   // folded conceptKey → its extract's UUID
        for assignment in result {
            let isSingletonCreate: Bool
            if case .createNew = assignment.action, assignment.extractUUIDs.count == 1,
               let only = assignment.extractUUIDs.first, (allExtractCounts[only] ?? 0) > 1 {
                isSingletonCreate = true
            } else {
                isSingletonCreate = false
            }
            if isSingletonCreate {
                mentionNames.append(assignment.conceptName)
                singletonHomes[assignment.conceptKey] = assignment.extractUUIDs.first
            } else {
                survivors.append(assignment)
            }
        }
        // A folded singleton's parent-link target is whichever survivor holds
        // its extract.
        for (foldedKey, extractUUID) in singletonHomes {
            if let home = survivors.first(where: { $0.extractUUIDs.contains(extractUUID) }) {
                foldedInto[foldedKey] = home.conceptName
            }
        }
        if !mentionNames.isEmpty {
            survivors = survivors.map { assignment in
                var copy = assignment
                let known = Set(copy.relatedConceptNames.map(conceptKey) + [copy.conceptKey])
                copy.relatedConceptNames += mentionNames.filter { !known.contains(conceptKey($0)) }
                return copy
            }
        }
        // Remap parents that pointed at folded concepts (chase short chains).
        guard !foldedInto.isEmpty else { return survivors }
        return survivors.map { assignment in
            var copy = assignment
            var hops = 0
            while let parent = copy.parentConceptName,
                  let survivorName = foldedInto[conceptKey(parent)],
                  hops < 5 {
                copy.parentConceptName = conceptKey(survivorName) == copy.conceptKey ? nil : survivorName
                hops += 1
            }
            return copy
        }
    }

    // MARK: - Heuristic fallback

    /// Deterministic assignment: match extract text against existing connection titles
    /// and lexicon terms; leftovers group under their branch question's concept.
    nonisolated static func heuristicAssignments(_ input: Input) -> [ConceptAssignment] {
        var buckets: [String: (name: String, action: Action, extractUUIDs: [String])] = [:]

        let connectionTargets: [(key: String, name: String, uuid: String)] = input.existingConnections.compactMap {
            guard let title = $0.title, !title.isEmpty else { return nil }
            return (conceptKey(title), title, $0.uuid)
        }
        let lexiconTargets: [(key: String, name: String)] = input.lexicon.compactMap {
            guard let title = $0.title, !title.isEmpty else { return nil }
            return (conceptKey(title), title)
        }
        let questionTitlesByUUID = Dictionary(
            input.questions.compactMap { question -> (String, String)? in
                guard let title = question.title else { return nil }
                return (question.uuid, title)
            },
            uniquingKeysWith: { first, _ in first }
        )

        for extract in input.extracts {
            let text = (extract.body ?? extract.title ?? "").lowercased()
            guard !text.isEmpty else { continue }

            if let match = connectionTargets.first(where: { text.contains($0.key) }) {
                buckets[match.key, default: (match.name, .mergeInto(connectionUUID: match.uuid), [])].extractUUIDs.append(extract.uuid)
            } else if let match = lexiconTargets.first(where: { text.contains($0.key) }) {
                buckets[match.key, default: (match.name, .createNew, [])].extractUUIDs.append(extract.uuid)
            } else if let questionUUID = extract.extractMetadata?.parentQuestionUUID,
                      let questionTitle = questionTitlesByUUID[questionUUID] {
                let concept = conceptName(fromQuestion: questionTitle)
                let key = conceptKey(concept)
                guard !key.isEmpty else { continue }
                buckets[key, default: (concept, .createNew, [])].extractUUIDs.append(extract.uuid)
            }
        }

        return buckets.map { key, bucket in
            ConceptAssignment(
                conceptKey: key,
                conceptName: bucket.name,
                aliases: [],
                action: bucket.action,
                extractUUIDs: bucket.extractUUIDs,
                rationale: "Matched by title/term overlap (offline heuristic).",
                confidence: 0.45
            )
        }
        .sorted { $0.extractUUIDs.count > $1.extractUUIDs.count }
    }

    // MARK: - Shared helpers

    /// Normalizes a concept name into a stable dedup key.
    nonisolated static func conceptKey(_ name: String) -> String {
        name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Derives a concept noun-phrase from a question title ("What is pranayama?" → "pranayama").
    nonisolated static func conceptName(fromQuestion question: String) -> String {
        var text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " ?"))
        let prefixes = ["what is ", "what are ", "how does ", "how do ", "why does ", "why do ", "can ", "should "]
        for prefix in prefixes where text.lowercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
            break
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? question : trimmed
    }

    nonisolated static func jsonObject(from raw: String) -> [String: Any]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped: String
        if trimmed.hasPrefix("```") {
            let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
            stripped = lines.dropFirst().dropLast().joined(separator: "\n")
        } else {
            stripped = trimmed
        }
        guard let data = stripped.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
