// CosmoOS/UI/FocusMode/SwipeStudy/CodexConceptLookup.swift
// Parses the Exemplar Codex into a concept dictionary for interactive tags.
// Each concept entry contains: name, category, definition, frequency, examples, anti-patterns.

import Foundation

struct CodexConceptEntry: Identifiable {
    let id: String  // lowercased concept name
    let name: String
    let category: String
    let definition: String
    let frequency: String
    let examples: [String]       // First 3 real quoted examples
    let whereActive: String?     // First "Where active" line
    let antiPatterns: [String]   // First 2 anti-patterns
}

@Observable
final class CodexConceptLookup {
    private(set) var concepts: [String: CodexConceptEntry] = [:]
    private(set) var isLoaded = false

    /// Parse the full Codex body into a concept dictionary.
    /// Extracts from: Periodic Table entries (NAME | CATEGORY | definition | frequency)
    /// and deep concept entries (═══ headers with examples).
    func parse(codexBody: String) {
        var result: [String: CodexConceptEntry] = [:]

        // Phase 1: Parse Periodic Table entries
        // Format: **NAME | CATEGORY | definition text | frequency**
        let periodicPattern = /\*\*(.+?)\s*\|\s*(.+?)\s*\|\s*(.+?)\s*\|\s*(.+?)\*\*/
        for match in codexBody.matches(of: periodicPattern) {
            let name = String(match.output.1).trimmingCharacters(in: .whitespaces)
            let category = String(match.output.2).trimmingCharacters(in: .whitespaces)
            let definition = String(match.output.3).trimmingCharacters(in: .whitespaces)
            let frequency = String(match.output.4).trimmingCharacters(in: .whitespaces)

            let key = normalizeKey(name)
            if result[key] == nil {
                result[key] = CodexConceptEntry(
                    id: key,
                    name: name,
                    category: category,
                    definition: definition,
                    frequency: frequency,
                    examples: [],
                    whereActive: nil,
                    antiPatterns: []
                )
            }
        }

        // Phase 2: Parse deep concept entries for examples + anti-patterns
        // Format: ═══ CONCEPT NAME (Category) ═══ ... EXAMPLES: ... ANTI-PATTERNS: ...
        let sections = codexBody.components(separatedBy: "═══")
        for i in stride(from: 1, to: sections.count - 1, by: 2) {
            let header = sections[i].trimmingCharacters(in: .whitespacesAndNewlines)
            let body = i + 1 < sections.count ? sections[i + 1] : ""

            // Extract concept name from header (e.g., "HOOK (Speech Act)")
            let conceptName: String
            if let parenIdx = header.firstIndex(of: "(") {
                conceptName = String(header[header.startIndex..<parenIdx]).trimmingCharacters(in: .whitespaces)
            } else {
                conceptName = header.trimmingCharacters(in: .whitespaces)
            }

            let key = normalizeKey(conceptName)
            guard !key.isEmpty, key.count > 1 else { continue }

            // Extract up to 3 examples — look for numbered entries with quoted text
            // Codex format: 1. "slide text here" \n   — [Post title] Slide N
            // or: 1. **"slide text here"** \n   — [Post title] Slide N
            var examples: [String] = []
            let lines = body.components(separatedBy: "\n")
            var i2 = 0
            while i2 < lines.count && examples.count < 3 {
                let line = lines[i2].trimmingCharacters(in: .whitespaces)
                // Match numbered example lines: starts with digit + period, contains a quote
                if line.first?.isNumber == true && line.contains(".") && line.contains("\"") {
                    // This is an example line — grab it plus the attribution line below
                    var example = line
                        .replacingOccurrences(of: "**", with: "")
                        .trimmingCharacters(in: .whitespaces)

                    // Check next line for attribution "— [Post...]"
                    if i2 + 1 < lines.count {
                        let nextLine = lines[i2 + 1].trimmingCharacters(in: .whitespaces)
                        if nextLine.hasPrefix("—") || nextLine.hasPrefix("-") {
                            example += "\n   " + nextLine
                        }
                    }

                    if example.count > 20 {
                        examples.append(example)
                    }
                }
                i2 += 1
            }

            // Extract "Where active" line from first example
            var whereActive: String?
            if let whereIdx = body.range(of: "Where active:") ?? body.range(of: "Where the concept is active:") {
                let afterWhere = body[whereIdx.upperBound...]
                if let lineEnd = afterWhere.firstIndex(of: "\n") {
                    whereActive = String(afterWhere[afterWhere.startIndex..<lineEnd]).trimmingCharacters(in: .whitespaces)
                }
            }

            // Extract anti-patterns
            var antiPatterns: [String] = []
            if let apIdx = body.range(of: "ANTI-PATTERNS") ?? body.range(of: "Anti-Patterns") {
                let apSection = String(body[apIdx.upperBound...])
                let apLines = apSection.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { $0.hasPrefix("- ") || $0.hasPrefix("Bad:") }
                    .prefix(2)
                antiPatterns = Array(apLines)
            }

            // Merge with existing entry from Periodic Table, or create new
            if var existing = result[key] {
                // Update with deep entry data
                result[key] = CodexConceptEntry(
                    id: existing.id,
                    name: existing.name,
                    category: existing.category,
                    definition: existing.definition,
                    frequency: existing.frequency,
                    examples: examples.isEmpty ? existing.examples : examples,
                    whereActive: whereActive ?? existing.whereActive,
                    antiPatterns: antiPatterns.isEmpty ? existing.antiPatterns : antiPatterns
                )
            } else if !examples.isEmpty || !conceptName.isEmpty {
                // Deep entry without Periodic Table match — create entry
                let catMatch = header.firstMatch(of: /\((.+?)\)/)
                let cat = catMatch.map { String($0.output.1) } ?? "Physics"

                result[key] = CodexConceptEntry(
                    id: key,
                    name: conceptName,
                    category: cat,
                    definition: "",
                    frequency: "",
                    examples: examples,
                    whereActive: whereActive,
                    antiPatterns: antiPatterns
                )
            }
        }

        // Phase 3: Add variant mappings — e.g., "confession-hook" → CONFESSION
        // Look for "→ includes:" patterns in the Variant Mapping section
        let variantPattern = /\*\*(.+?)\*\*\s*→\s*includes:\s*(.+)/
        for match in codexBody.matches(of: variantPattern) {
            let parentName = String(match.output.1).trimmingCharacters(in: .whitespaces)
            let variants = String(match.output.2).components(separatedBy: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            let parentKey = normalizeKey(parentName)
            guard let parentEntry = result[parentKey] else { continue }

            for variant in variants {
                let variantKey = normalizeKey(variant)
                if !variantKey.isEmpty && result[variantKey] == nil {
                    // Point variant to parent entry
                    result[variantKey] = parentEntry
                }
            }
        }

        self.concepts = result
        self.isLoaded = true
        print("📚 CodexConceptLookup: parsed \(result.count) concepts")
    }

    /// Look up a concept by name (case-insensitive, handles variants)
    func lookup(_ name: String) -> CodexConceptEntry? {
        let key = normalizeKey(name)
        return concepts[key]
    }

    /// Check if a concept exists in the lookup
    func has(_ name: String) -> Bool {
        concepts[normalizeKey(name)] != nil
    }

    private func normalizeKey(_ name: String) -> String {
        name.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " / ", with: "/")
            .replacingOccurrences(of: "  ", with: " ")
    }
}
