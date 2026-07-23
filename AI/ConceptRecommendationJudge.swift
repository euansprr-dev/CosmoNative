// CosmoOS/AI/ConceptRecommendationJudge.swift
// The Material rail's relevance judge. Deterministic retrieval (Recall +
// phrase matchers) proposes; ONE batched sensor-tier call disposes — keeping
// only candidates it can justify in a sentence, naming the section each one
// develops, and flagging material that merely restates an already-linked
// reference page. The judge FILTERS and ANNOTATES; it never generates
// material of its own.
//
// Contract:
// - One call per settled edit-signature (never on the typing path).
// - Aliases (m1…, r1…) in the prompt — models mangle raw UUIDs.
// - JSON out with reasoning disabled (the Sonnet adaptive-thinking trap).
// - nil verdict = the judge could not rule (timeout/parse failure) — the
//   caller falls back to deterministic floors. An EMPTY verdict is a real
//   ruling: nothing qualified, show silence.

import Foundation

enum ConceptRecommendationJudge {

    /// One kept candidate: the row it refers to, where it should land, the
    /// one-sentence rationale shown under the row, and — when the material
    /// only restates a linked page — that page's uuid instead of a keep.
    struct Ruling: Equatable, Sendable {
        var rowID: String
        var section: ConnectionSectionType?
        var why: String
        var coveredByUUID: String?
    }

    /// What the judge reads about the concept. Built from the live snapshot.
    struct Dossier {
        var title: String
        var typeName: String
        /// (section display name, item texts) for filled sections only.
        var sections: [(name: String, items: [String])]
        var seekingName: String?
        /// Already-linked reference pages (alias target for `covered`).
        var linkedPages: [(uuid: String, title: String)]
    }

    /// A candidate as the judge sees it.
    struct Candidate {
        var rowID: String
        var originLabel: String
        var title: String
        var excerpt: String
    }

    static let timeout: Duration = .seconds(12)
    static let maxCandidates = 18

    // MARK: - Run

    /// nil = no ruling (caller keeps deterministic results); [] = ruled empty.
    static func judge(dossier: Dossier, candidates: [Candidate]) async -> [Ruling]? {
        guard !candidates.isEmpty else { return [] }
        let batch = Array(candidates.prefix(maxCandidates))
        let aliases = aliasMap(for: batch)
        let linkedAliases = linkedAliasMap(for: dossier.linkedPages)
        let promptText = prompt(dossier: dossier, candidates: batch, aliases: aliases, linkedAliases: linkedAliases)

        let raw: String? = await withTaskGroup(of: String?.self) { group in
            group.addTask {
                try? await ResearchService.shared.analyze(
                    prompt: promptText,
                    tier: .sensor,
                    maxTokens: 900,
                    disableReasoning: true
                )
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }

        guard let raw else { return nil }
        return parse(raw, aliases: aliases, linkedAliases: linkedAliases)
    }

    // MARK: - Aliases

    /// m1… in prompt order. Loop-built — model output is never trusted as
    /// dictionary keys directly.
    static func aliasMap(for candidates: [Candidate]) -> [String: String] {
        var out: [String: String] = [:]
        for (index, candidate) in candidates.enumerated() {
            out["m\(index + 1)"] = candidate.rowID
        }
        return out
    }

    static func linkedAliasMap(for pages: [(uuid: String, title: String)]) -> [String: String] {
        var out: [String: String] = [:]
        for (index, page) in pages.enumerated() {
            out["r\(index + 1)"] = page.uuid
        }
        return out
    }

    // MARK: - Prompt

    static func prompt(
        dossier: Dossier,
        candidates: [Candidate],
        aliases: [String: String],
        linkedAliases: [String: String]
    ) -> String {
        var lines: [String] = []
        lines.append("You audit recommendations inside a personal knowledge tool. The user is developing one concept page. Decide which candidate materials genuinely help develop THIS concept.")
        lines.append("")
        lines.append("THE CONCEPT")
        lines.append("Title: \(dossier.title)")
        lines.append("Type: \(dossier.typeName)")
        for section in dossier.sections {
            lines.append("\(section.name):")
            for item in section.items.prefix(6) {
                lines.append("- \(String(item.prefix(300)))")
            }
        }
        if let seeking = dossier.seekingName {
            lines.append("The page is currently hungry for: \(seeking).")
        }
        if !dossier.linkedPages.isEmpty {
            lines.append("")
            lines.append("ALREADY-LINKED REFERENCE PAGES (their content counts as already said):")
            for (index, page) in dossier.linkedPages.enumerated() {
                lines.append("r\(index + 1) · \(page.title)")
            }
        }
        lines.append("")
        lines.append("CANDIDATES")
        for (index, candidate) in candidates.enumerated() {
            lines.append("m\(index + 1) [\(candidate.originLabel) · \(String(candidate.title.prefix(80)))]")
            lines.append("\(String(candidate.excerpt.prefix(260)))")
        }
        lines.append("")
        lines.append("RULES")
        lines.append("- KEEP a candidate only if you can state, in one short plain sentence, what it adds to this concept that the page does not already say. Name the one section it develops. The sentence must mention the candidate's actual content, not just repeat the concept title.")
        lines.append("- REJECT anything about operating software or app features (including the Cosmo app itself), product documentation, API or tool lists, project logistics, or notes that merely share common words with the title.")
        lines.append("- If a candidate only restates something an ALREADY-LINKED page says, do not keep it — instead list it in \"covered\" with that page's r-alias.")
        lines.append("- When unsure, reject. Keeping nothing is a valid answer. Never invent candidates.")
        lines.append("")
        lines.append("Respond with ONLY this JSON, no prose:")
        lines.append("{\"keep\":[{\"id\":\"m1\",\"section\":\"evidence\",\"why\":\"one short sentence\"}],\"covered\":[{\"id\":\"m2\",\"by\":\"r1\"}]}")
        lines.append("Valid section values: " + ConnectionSectionType.allCases.map(\.rawValue).joined(separator: ", "))
        return lines.joined(separator: "\n")
    }

    // MARK: - Parse

    /// Tolerant parse. Returns nil when no JSON object with a "keep" array is
    /// recoverable — that means "no ruling", never "ruled empty".
    static func parse(
        _ raw: String,
        aliases: [String: String],
        linkedAliases: [String: String]
    ) -> [Ruling]? {
        // Whole-string / fenced JSON first; then the first balanced object
        // dug out of any prose the model wrapped around it.
        let object = ConceptResolver.jsonObject(from: raw)
            ?? firstJSONObject(in: raw)
        guard let object,
              let keepArray = object["keep"] as? [[String: Any]]
        else { return nil }

        var coveredByRowID: [String: String] = [:]
        if let coveredArray = object["covered"] as? [[String: Any]] {
            for entry in coveredArray {
                guard let alias = entry["id"] as? String,
                      let rowID = aliases[alias],
                      let byAlias = entry["by"] as? String,
                      let pageUUID = linkedAliases[byAlias]
                else { continue }
                coveredByRowID[rowID] = pageUUID
            }
        }

        var rulings: [Ruling] = []
        var seen = Set<String>()
        for entry in keepArray {
            guard let alias = entry["id"] as? String,
                  let rowID = aliases[alias],
                  seen.insert(rowID).inserted
            else { continue }
            let section = (entry["section"] as? String).flatMap(ConnectionSectionType.init(rawValue:))
            let why = (entry["why"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            rulings.append(Ruling(rowID: rowID, section: section, why: why, coveredByUUID: nil))
        }
        // Covered rows ride along as rulings with no keep — the model can
        // surface them as "via <page>" instead of dropping them silently.
        for (rowID, pageUUID) in coveredByRowID.sorted(by: { $0.key < $1.key }) where !seen.contains(rowID) {
            rulings.append(Ruling(rowID: rowID, section: nil, why: "", coveredByUUID: pageUUID))
        }
        return rulings
    }

    /// First balanced `{…}` in the text, string-and-escape aware — models
    /// sometimes wrap the requested JSON in a sentence despite instructions.
    static func firstJSONObject(in text: String) -> [String: Any]? {
        var start: String.Index?
        var depth = 0
        var inString = false
        var escaping = false
        for index in text.indices {
            let character = text[index]
            if start == nil {
                if character == "{" {
                    start = index
                    depth = 1
                }
                continue
            }
            if inString {
                if escaping {
                    escaping = false
                } else if character == "\\" {
                    escaping = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }
            switch character {
            case "\"": inString = true
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0, let start {
                    let candidate = String(text[start...index])
                    if let data = candidate.data(using: .utf8),
                       let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                        return object
                    }
                    return nil
                }
            default: break
            }
        }
        return nil
    }
}
