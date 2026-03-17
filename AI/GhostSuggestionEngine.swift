// CosmoOS/AI/GhostSuggestionEngine.swift
// Engine for generating ghost suggestions for Connection sections
// Uses AI analysis via ResearchService to suggest relevant content
// December 2025 - Connection Focus Mode integration

import Foundation

// MARK: - Ghost Suggestion Engine

/// Engine for generating ghost suggestions for Connection sections.
/// Uses ResearchService (Haiku tier) to analyze connected atoms and produce
/// synthesized suggestions grounded in source material.
actor GhostSuggestionEngine {
    // MARK: - Singleton

    static let shared = GhostSuggestionEngine()

    // MARK: - Configuration

    /// Maximum suggestions per section
    private let maxSuggestionsPerSection = 5

    /// Maximum characters per source for the prompt
    private let maxSourceChars = 800

    // MARK: - Public Methods

    /// Generate ghost suggestions for all sections of a Connection
    /// - Parameters:
    ///   - connectionTitle: Title of the Connection atom
    ///   - existingItems: Items already in the connection (to avoid duplicates)
    ///   - relatedAtomUUIDs: UUIDs of atoms linked to this connection
    /// - Returns: Dictionary of section type to suggestions
    func generateSuggestions(
        connectionTitle: String,
        existingItems: [ConnectionItem],
        relatedAtomUUIDs: [String]
    ) async -> [ConnectionSectionType: [GhostSuggestion]] {
        var allSuggestions: [ConnectionSectionType: [GhostSuggestion]] = [:]

        // Initialize empty arrays for all sections
        for sectionType in ConnectionSectionType.allCases {
            allSuggestions[sectionType] = []
        }

        // Gather source content from related atoms
        let sources = await gatherSourceContent(atomUUIDs: relatedAtomUUIDs)
        guard !sources.isEmpty else { return allSuggestions }

        // Build existing items digest for dedup
        let existingDigest = existingItems.map { $0.content }.joined(separator: "\n")

        // Build source digest
        var sourceDigest = ""
        for source in sources.prefix(6) {
            let body = String(source.cleanText.prefix(maxSourceChars))
            sourceDigest += "[\(source.title)]: \(body)\n---\n"
        }

        let sectionNames = ConnectionSectionType.allCases.map { $0.displayName }.joined(separator: ", ")

        let systemPrompt = """
        You generate section suggestions for a Connection framework. \
        Each suggestion must be grounded in the provided source materials. \
        Write 1-2 sentence synthesized insights, not raw quotes. \
        Skip sections where sources have nothing relevant. \
        Do not repeat items that already exist — not even reworded versions of the same point. \
        NEVER prefix suggestions with the source title or topic name. \
        Jump straight into the insight — no preamble like "Topic Name | " or "According to...".
        """

        let prompt = """
        Connection: "\(connectionTitle)"
        Sections: \(sectionNames)

        Source materials:
        \(sourceDigest)

        \(existingDigest.isEmpty ? "" : "Existing items (do NOT repeat or rephrase these — each suggestion must cover a DIFFERENT point):\n\(existingDigest)\n")
        For each section where sources provide relevant information, generate 1-3 suggestions.
        Each suggestion must reference a specific source.

        CRITICAL RULES:
        - Do NOT start the TEXT with the source title, topic name, or any prefix before the insight.
        - Each suggestion must make a DISTINCT point — no two suggestions should cover the same idea even if worded differently.
        - Go straight to the insight. Bad: "Solipsism | The problem is..." Good: "The fundamental problem is..."

        Respond ONLY with lines in this exact format (one per line):
        SECTION: <section name> | SOURCE: <source title> | TEXT: <suggested content>
        """

        do {
            let response = try await ResearchService.shared.analyze(
                prompt: prompt,
                systemPrompt: systemPrompt,
                tier: .sensor,
                maxTokens: 1500
            )

            let suggestions = parseResponse(response, sources: sources)
            let deduped = deduplicateSuggestions(suggestions, existingItems: existingItems)

            // Group by section type
            for suggestion in deduped {
                allSuggestions[suggestion.targetSectionType, default: []].append(suggestion)
            }

            // Limit per section
            for sectionType in ConnectionSectionType.allCases {
                if let sectionSuggestions = allSuggestions[sectionType], sectionSuggestions.count > maxSuggestionsPerSection {
                    allSuggestions[sectionType] = Array(sectionSuggestions.prefix(maxSuggestionsPerSection))
                }
            }
        } catch {
            // Silently return empty suggestions on API failure
        }

        return allSuggestions
    }

    // MARK: - Source Content Gathering

    private func gatherSourceContent(atomUUIDs: [String]) async -> [SourceContent] {
        var content: [SourceContent] = []

        for uuid in atomUUIDs {
            guard let atom = try? await AtomRepository.shared.fetch(uuid: uuid) else {
                continue
            }

            let title = atom.title ?? "Untitled"
            let cleanText = extractCleanText(from: atom)

            guard !cleanText.isEmpty else { continue }

            content.append(SourceContent(
                atomUUID: uuid,
                title: title,
                type: atom.type,
                cleanText: cleanText
            ))
        }

        return content
    }

    /// Extract clean text from an atom, handling JSON transcript arrays
    private func extractCleanText(from atom: Atom) -> String {
        var parts: [String] = []

        // Main body — detect and clean JSON transcript arrays
        if let body = atom.body, !body.isEmpty {
            parts.append(cleanBodyText(body))
        }

        // Annotations from research atoms
        if atom.type == .research, let structured = atom.structured,
           let data = structured.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let annotations = json["annotations"] as? [[String: Any]] {
            for annotation in annotations {
                if let content = annotation["content"] as? String, !content.isEmpty {
                    parts.append(content)
                }
            }
        }

        return parts.joined(separator: "\n")
    }

    /// Clean body text — extract just text fields from JSON transcript arrays
    private func cleanBodyText(_ body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)

        // Detect JSON transcript array: starts with [ and contains "text" keys
        if trimmed.hasPrefix("["),
           let data = trimmed.data(using: .utf8),
           let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            let texts = jsonArray.compactMap { $0["text"] as? String }
            if !texts.isEmpty {
                return texts.joined(separator: " ")
            }
        }

        return body
    }

    // MARK: - Response Parsing

    private func parseResponse(_ response: String, sources: [SourceContent]) -> [GhostSuggestion] {
        var suggestions: [GhostSuggestion] = []

        for line in response.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.contains("SECTION:") && trimmed.contains("TEXT:") else { continue }

            // Parse: SECTION: <name> | SOURCE: <title> | TEXT: <content>
            let parts = trimmed.components(separatedBy: "|")
            guard parts.count >= 3 else { continue }

            let sectionPart = parts[0].replacingOccurrences(of: "SECTION:", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let sourcePart = parts[1].replacingOccurrences(of: "SOURCE:", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var textPart = parts[2...].joined(separator: "|")
                .replacingOccurrences(of: "TEXT:", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let sectionType = matchSectionType(sectionPart.lowercased()),
                  !textPart.isEmpty else { continue }

            // Find matching source atom
            let matchingSource = sources.first {
                $0.title.lowercased().contains(sourcePart.lowercased()) ||
                sourcePart.lowercased().contains($0.title.lowercased())
            } ?? sources.first

            guard let source = matchingSource else { continue }

            // Strip title prefix the LLM may have prepended (e.g. "Topic Name | actual insight")
            textPart = stripTitlePrefix(textPart, sourceTitles: sources.map(\.title))

            suggestions.append(GhostSuggestion(
                content: textPart,
                sourceAtomUUID: source.atomUUID,
                sourceAtomTitle: source.title,
                sourceSnippet: sourcePart,
                targetSectionType: sectionType,
                confidence: 0.75
            ))
        }

        return suggestions
    }

    private func matchSectionType(_ name: String) -> ConnectionSectionType? {
        let normalized = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for type in ConnectionSectionType.allCases {
            if type.displayName.lowercased() == normalized ||
               type.rawValue.lowercased() == normalized {
                return type
            }
        }
        // Fuzzy matching
        if normalized.contains("goal") { return .goal }
        if normalized.contains("problem") { return .problems }
        if normalized.contains("benefit") { return .benefits }
        if normalized.contains("example") { return .examples }
        if normalized.contains("belief") || normalized.contains("objection") { return .beliefsObjections }
        if normalized.contains("process") || normalized.contains("step") { return .process }
        if normalized.contains("concept") || normalized.contains("name") { return .conceptName }
        if normalized.contains("reference") || normalized.contains("source") { return .references }
        return nil
    }

    // MARK: - Title Prefix Stripping

    /// Strip a source title the LLM may have prepended (e.g. "Topic Name | actual insight" or "Topic Name: insight")
    private func stripTitlePrefix(_ text: String, sourceTitles: [String]) -> String {
        var cleaned = text

        // Strip "Title | rest" pattern
        if let pipeRange = cleaned.range(of: " | ") {
            let before = String(cleaned[cleaned.startIndex..<pipeRange.lowerBound])
            let isTitle = sourceTitles.contains { title in
                before.lowercased().contains(title.lowercased().prefix(20)) ||
                title.lowercased().contains(before.lowercased().prefix(20))
            }
            if isTitle {
                cleaned = String(cleaned[pipeRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Strip "Title: rest" or "Title — rest" patterns
        for separator in [": ", " — ", " - "] {
            if let sepRange = cleaned.range(of: separator) {
                let before = String(cleaned[cleaned.startIndex..<sepRange.lowerBound])
                // Only strip if the prefix is short (likely a title, not part of the insight)
                if before.count < 60 {
                    let isTitle = sourceTitles.contains { title in
                        before.lowercased().contains(title.lowercased().prefix(20)) ||
                        title.lowercased().contains(before.lowercased().prefix(20))
                    }
                    if isTitle {
                        cleaned = String(cleaned[sepRange.upperBound...])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        break
                    }
                }
            }
        }

        return cleaned.isEmpty ? text : cleaned
    }

    // MARK: - Deduplication

    private func deduplicateSuggestions(
        _ suggestions: [GhostSuggestion],
        existingItems: [ConnectionItem]
    ) -> [GhostSuggestion] {
        var kept: [GhostSuggestion] = []

        // Build significant-words set (drop common stop words for better semantic matching)
        func significantWords(_ text: String) -> Set<String> {
            let stopWords: Set<String> = [
                "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
                "have", "has", "had", "do", "does", "did", "will", "would", "shall",
                "should", "may", "might", "must", "can", "could", "of", "in", "to",
                "for", "with", "on", "at", "from", "by", "as", "into", "through",
                "and", "but", "or", "nor", "not", "so", "yet", "both", "either",
                "neither", "each", "every", "all", "any", "few", "more", "most",
                "other", "some", "such", "no", "only", "own", "same", "than",
                "too", "very", "just", "that", "this", "it", "its", "we", "they",
                "their", "our", "how", "what", "which", "who", "whom", "when", "where"
            ]
            return Set(
                text.lowercased()
                    .split(separator: " ")
                    .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                    .filter { $0.count > 2 && !stopWords.contains($0) }
            )
        }

        for suggestion in suggestions {
            let contentWords = significantWords(suggestion.content)
            guard contentWords.count >= 2 else {
                kept.append(suggestion)
                continue
            }

            // Check against existing items (lower threshold to catch reworded duplicates)
            let duplicatesExisting = existingItems.contains { item in
                let itemWords = significantWords(item.content)
                guard !itemWords.isEmpty else { return false }
                let overlap = Double(contentWords.intersection(itemWords).count) / Double(min(contentWords.count, itemWords.count))
                return overlap > 0.45
            }
            guard !duplicatesExisting else { continue }

            // Check against already-kept suggestions
            let duplicatesKept = kept.contains { other in
                let otherWords = significantWords(other.content)
                guard !otherWords.isEmpty else { return false }
                let overlap = Double(contentWords.intersection(otherWords).count) / Double(min(contentWords.count, otherWords.count))
                return overlap > 0.45
            }
            guard !duplicatesKept else { continue }

            kept.append(suggestion)
        }

        return kept
    }
}

// MARK: - Supporting Types

/// Content extracted from a source atom
struct SourceContent {
    let atomUUID: String
    let title: String
    let type: AtomType
    let cleanText: String
}
