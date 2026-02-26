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
        Do not repeat items that already exist.
        """

        let prompt = """
        Connection: "\(connectionTitle)"
        Sections: \(sectionNames)

        Source materials:
        \(sourceDigest)

        \(existingDigest.isEmpty ? "" : "Existing items (do NOT repeat these):\n\(existingDigest)\n")
        For each section where sources provide relevant information, generate 1-3 suggestions.
        Each suggestion must reference a specific source.

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
            let textPart = parts[2...].joined(separator: "|")
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

    // MARK: - Deduplication

    private func deduplicateSuggestions(
        _ suggestions: [GhostSuggestion],
        existingItems: [ConnectionItem]
    ) -> [GhostSuggestion] {
        var kept: [GhostSuggestion] = []

        for suggestion in suggestions {
            let contentWords = Set(suggestion.content.lowercased().split(separator: " "))

            // Check against existing items
            let duplicatesExisting = existingItems.contains { item in
                let itemWords = Set(item.content.lowercased().split(separator: " "))
                guard !contentWords.isEmpty else { return false }
                let overlap = Double(contentWords.intersection(itemWords).count) / Double(contentWords.count)
                return overlap > 0.7
            }
            guard !duplicatesExisting else { continue }

            // Check against already-kept suggestions
            let duplicatesKept = kept.contains { other in
                let otherWords = Set(other.content.lowercased().split(separator: " "))
                guard !contentWords.isEmpty else { return false }
                let overlap = Double(contentWords.intersection(otherWords).count) / Double(contentWords.count)
                return overlap > 0.7
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
