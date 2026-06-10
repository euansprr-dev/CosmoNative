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
    }

    /// Resolves concept assignments for a session's extracts.
    /// Extracts the live router already concept-tagged at capture time are assigned
    /// deterministically from their persisted tags — they are NOT re-categorized.
    /// Only untagged extracts go to the LLM; when everything is tagged, no LLM
    /// call happens at all. Never throws.
    func resolve(_ input: Input) async -> [ConceptAssignment] {
        guard !input.extracts.isEmpty else { return [] }
        let preassigned = Self.assignmentsFromPersistedTags(input)
        let taggedUUIDs = Set(preassigned.flatMap(\.extractUUIDs))
        let remaining = input.extracts.filter { !taggedUUIDs.contains($0.uuid) }
        guard !remaining.isEmpty else { return preassigned }

        var llmInput = input
        llmInput.extracts = remaining
        do {
            let raw = try await ResearchService.shared.analyze(
                prompt: buildPrompt(llmInput, sessionConcepts: preassigned.map(\.conceptName)),
                systemPrompt: Self.systemPrompt,
                tier: .strategist,
                maxTokens: 2400
            )
            let parsed = parse(raw: raw, input: llmInput)
            if !parsed.isEmpty { return Self.merged(preassigned, parsed) }
        } catch {
            print("[ConceptResolver] LLM failed: \(error) — using heuristic assignments")
        }
        return Self.merged(preassigned, Self.heuristicAssignments(llmInput))
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
    1. EXTRACTS — each with a UUID, kind, and text.
    2. EXISTING CONCEPT PAGES — each with a UUID and title. If an extract belongs to one of these, you MUST \
    merge into it by its UUID rather than creating a near-duplicate page.
    3. LEXICON TERMS — vocabulary the user has accumulated; prefer these spellings for concept names.

    Decision rules, in order:
    - If an extract's main subject matches an existing page (same concept, even with different wording), \
    assign action "merge" with that page's UUID. "Pranayama breathing" matches an existing "Pranayama" page.
    - If 2+ extracts share a subject with no existing page, create ONE new concept ("create").
    - One extract may belong to MULTIPLE concepts when it genuinely bridges them — list its UUID under each.
    - If an extract is too vague, personal, or session-specific to belong to any durable concept, OMIT it \
    entirely. Do not force assignments.
    - Never invent UUIDs. Only use extract UUIDs and connection UUIDs that appear in the input.

    Worked examples:

    Example A (merge into existing): Existing page {"uuid":"abc-1","title":"Pranayama"}. \
    Extract {"uuid":"e-9","text":"Bhastrika is an energizing pranayama involving forced exhales"}. \
    → {"conceptName":"Pranayama","action":"merge","connectionUUID":"abc-1","extractUUIDs":["e-9"]}

    Example B (create new): No existing pages. Extracts e-1 "Vagal tone improves with slow exhales", \
    e-2 "The vagus nerve links breath rate to heart rate". \
    → {"conceptName":"Vagus nerve","action":"create","extractUUIDs":["e-1","e-2"]}

    Example C (multi-concept extract): Extract e-4 "Slow pranayama raises vagal tone within minutes" \
    bridges both → its UUID appears under BOTH "Pranayama" (merge, if a page exists) and "Vagus nerve".

    Example D (leave unassigned): Extract e-7 "remember to ask Maria about her teacher" is personal/\
    session-specific → appears in NO assignment.

    ALWAYS respond with VALID JSON only, no prose, matching:
    {
      "assignments": [
        {
          "conceptName": "<noun phrase>",
          "aliases": ["<alternate name>", ...],
          "action": "create" | "merge",
          "connectionUUID": "<existing page UUID, required when action is merge>",
          "extractUUIDs": ["<uuid>", ...],
          "rationale": "<one sentence>",
          "confidence": <0.0-1.0>
        }
      ]
    }
    """

    private func buildPrompt(_ input: Input, sessionConcepts: [String] = []) -> String {
        var lines: [String] = []
        if let dd = input.deepDive {
            lines.append("Deep Dive topic: \(dd.title ?? "Untitled")")
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
        if !sessionConcepts.isEmpty {
            lines.append("\nCONCEPTS ALREADY ASSIGNED THIS SESSION (reuse these exact names when an extract fits one): \(sessionConcepts.prefix(25).joined(separator: ", "))")
        }
        lines.append("\nEXTRACTS:")
        for extract in input.extracts.prefix(60) {
            let kind = extract.extractMetadata?.kind.rawValue ?? "extract"
            let body = (extract.body ?? extract.title ?? "").prefix(280)
            lines.append(#"- {"uuid":"\#(extract.uuid)","kind":"\#(kind)","text":"\#(body)"}"#)
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

            seenKeys.insert(key)
            assignments.append(ConceptAssignment(
                conceptKey: key,
                conceptName: name,
                aliases: (entry["aliases"] as? [String]) ?? [],
                action: action,
                extractUUIDs: extractUUIDs,
                rationale: (entry["rationale"] as? String) ?? "",
                confidence: (entry["confidence"] as? Double) ?? 0.6
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
            } else {
                indexByKey[assignment.conceptKey] = result.count
                result.append(assignment)
            }
        }
        return result
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
