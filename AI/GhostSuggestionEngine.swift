// CosmoOS/AI/GhostSuggestionEngine.swift
// Engine for generating ghost suggestions for Connection sections
// Uses semantic search and relationship mining to suggest relevant content
// December 2025 - Connection Focus Mode integration

import Foundation

// MARK: - Ghost Suggestion Engine

/// Engine for generating ghost suggestions for Connection sections.
/// Analyzes connected atoms, journal entries, research annotations to suggest
/// relevant content for each section type.
actor GhostSuggestionEngine {
    // MARK: - Singleton

    static let shared = GhostSuggestionEngine()

    // MARK: - Configuration

    /// Minimum confidence threshold for suggestions (60%)
    private let confidenceThreshold: Double = 0.6

    /// Maximum suggestions per section
    private let maxSuggestionsPerSection = 5

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
        let sourceContent = await gatherSourceContent(atomUUIDs: relatedAtomUUIDs)

        // Generate suggestions for each section
        for sectionType in ConnectionSectionType.allCases {
            let suggestions = await generateSectionsuggest(
                sectionType: sectionType,
                connectionTitle: connectionTitle,
                existingItems: existingItems,
                sourceContent: sourceContent
            )
            allSuggestions[sectionType] = suggestions
        }

        return allSuggestions
    }

    /// Generate suggestions for a specific section
    /// - Parameters:
    ///   - sectionType: The section to generate suggestions for
    ///   - connectionTitle: Title of the Connection
    ///   - existingItems: Already added items
    ///   - sourceContent: Content from related atoms
    /// - Returns: Array of ghost suggestions
    func generateSectionsuggest(
        sectionType: ConnectionSectionType,
        connectionTitle: String,
        existingItems: [ConnectionItem],
        sourceContent: [SourceContent]
    ) async -> [GhostSuggestion] {
        var suggestions: [GhostSuggestion] = []

        for source in sourceContent {
            // Extract relevant snippets based on section type
            let relevantSnippets = extractRelevantSnippets(
                from: source,
                for: sectionType,
                connectionTitle: connectionTitle
            )

            for snippet in relevantSnippets {
                // Check if similar content already exists
                if isDuplicate(snippet.content, existingItems: existingItems) {
                    continue
                }

                let suggestion = GhostSuggestion(
                    content: snippet.content,
                    sourceAtomUUID: source.atomUUID,
                    sourceAtomTitle: source.title,
                    sourceSnippet: snippet.originalText,
                    targetSectionType: sectionType,
                    confidence: snippet.confidence
                )

                if suggestion.shouldShow {
                    suggestions.append(suggestion)
                }
            }
        }

        // Sort by confidence and limit
        return Array(
            suggestions
                .sorted { $0.confidence > $1.confidence }
                .prefix(maxSuggestionsPerSection)
        )
    }

    // MARK: - Source Content Gathering

    private func gatherSourceContent(atomUUIDs: [String]) async -> [SourceContent] {
        var content: [SourceContent] = []

        for uuid in atomUUIDs {
            guard let atom = try? await AtomRepository.shared.fetch(uuid: uuid) else {
                continue
            }

            // Extract content based on atom type
            var snippets: [String] = []

            // Main body content
            if let body = atom.body, !body.isEmpty {
                snippets.append(contentsOf: splitIntoSnippets(body))
            }

            // Annotations from research atoms
            if atom.type == .research, let structured = atom.structured {
                if let annotations = extractAnnotations(from: structured) {
                    snippets.append(contentsOf: annotations)
                }
            }

            // Journal entry highlights
            if atom.type == .journalEntry, let structured = atom.structured {
                if let highlights = extractHighlights(from: structured) {
                    snippets.append(contentsOf: highlights)
                }
            }

            content.append(SourceContent(
                atomUUID: uuid,
                title: atom.title ?? "Untitled",
                type: atom.type,
                snippets: snippets
            ))
        }

        return content
    }

    // MARK: - Snippet Extraction

    private func extractRelevantSnippets(
        from source: SourceContent,
        for sectionType: ConnectionSectionType,
        connectionTitle: String
    ) -> [RelevantSnippet] {
        var relevant: [RelevantSnippet] = []

        for snippet in source.snippets {
            let confidence = calculateRelevance(
                snippet: snippet,
                sectionType: sectionType,
                connectionTitle: connectionTitle
            )

            if confidence >= confidenceThreshold {
                // Summarize long snippets
                let content = snippet.count > 150
                    ? summarizeSnippet(snippet)
                    : snippet

                relevant.append(RelevantSnippet(
                    content: content,
                    originalText: snippet,
                    confidence: confidence
                ))
            }
        }

        return relevant
    }

    private func calculateRelevance(
        snippet: String,
        sectionType: ConnectionSectionType,
        connectionTitle: String
    ) -> Double {
        var score: Double = 0.5 // Base score

        let snippetLower = snippet.lowercased()
        let titleWords = connectionTitle.lowercased().split(separator: " ")

        // Keyword matching for section types
        let keywords = sectionTypeKeywords(sectionType)
        for keyword in keywords {
            if snippetLower.contains(keyword) {
                score += 0.15
            }
        }

        // Title word matching
        for word in titleWords where word.count > 3 {
            if snippetLower.contains(word) {
                score += 0.1
            }
        }

        // Structural indicators
        switch sectionType {
        case .goal:
            if snippetLower.contains("goal") || snippetLower.contains("aim") ||
               snippetLower.contains("objective") || snippetLower.contains("want to") {
                score += 0.15
            }

        case .problems:
            if snippetLower.contains("problem") || snippetLower.contains("issue") ||
               snippetLower.contains("challenge") || snippetLower.contains("struggle") {
                score += 0.15
            }

        case .benefits:
            if snippetLower.contains("benefit") || snippetLower.contains("advantage") ||
               snippetLower.contains("improve") || snippetLower.contains("helps") {
                score += 0.15
            }

        case .examples:
            if snippetLower.contains("example") || snippetLower.contains("for instance") ||
               snippetLower.contains("such as") || snippetLower.contains("case study") {
                score += 0.15
            }

        case .beliefsObjections:
            if snippetLower.contains("but") || snippetLower.contains("however") ||
               snippetLower.contains("argue") || snippetLower.contains("believe") {
                score += 0.15
            }

        case .process:
            if snippetLower.contains("step") || snippetLower.contains("first") ||
               snippetLower.contains("then") || snippetLower.contains("process") {
                score += 0.15
            }

        case .conceptName:
            // Less likely to find suggestions for this
            score -= 0.2

        case .references:
            if snippetLower.contains("study") || snippetLower.contains("research") ||
               snippetLower.contains("according to") || snippetLower.contains("found that") {
                score += 0.15
            }
        }

        return min(score, 1.0)
    }

    private func sectionTypeKeywords(_ type: ConnectionSectionType) -> [String] {
        switch type {
        case .goal:
            return ["goal", "aim", "objective", "outcome", "achieve", "want", "desire"]
        case .problems:
            return ["problem", "issue", "challenge", "pain", "struggle", "difficulty", "obstacle"]
        case .benefits:
            return ["benefit", "advantage", "improve", "better", "positive", "gain", "help"]
        case .examples:
            return ["example", "instance", "case", "application", "real-world", "practice"]
        case .beliefsObjections:
            return ["believe", "think", "argue", "objection", "counter", "however", "but"]
        case .process:
            return ["step", "process", "how to", "method", "approach", "first", "then", "next"]
        case .conceptName:
            return ["name", "call", "term", "concept", "idea", "framework"]
        case .references:
            return ["study", "research", "source", "reference", "evidence", "data", "found"]
        }
    }

    // MARK: - Helpers

    private func splitIntoSnippets(_ text: String) -> [String] {
        // Split by sentence/paragraph
        let separators = CharacterSet(charactersIn: ".!?\n\n")
        return text
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 20 && $0.count <= 500 }
    }

    private func summarizeSnippet(_ snippet: String) -> String {
        // Simple truncation with ellipsis
        // In production, would use AI summarization
        if snippet.count > 150 {
            let endIndex = snippet.index(snippet.startIndex, offsetBy: 147)
            return String(snippet[..<endIndex]) + "..."
        }
        return snippet
    }

    private func isDuplicate(_ content: String, existingItems: [ConnectionItem]) -> Bool {
        let contentLower = content.lowercased()

        for item in existingItems {
            let itemLower = item.content.lowercased()

            // Check for high similarity (simple check)
            if contentLower == itemLower {
                return true
            }

            // Check for significant overlap
            let contentWords = Set(contentLower.split(separator: " "))
            let itemWords = Set(itemLower.split(separator: " "))

            if contentWords.count > 0 {
                let overlap = contentWords.intersection(itemWords).count
                let similarity = Double(overlap) / Double(contentWords.count)
                if similarity > 0.7 {
                    return true
                }
            }
        }

        return false
    }

    private func extractAnnotations(from structured: String) -> [String]? {
        guard let data = structured.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let annotations = json["annotations"] as? [[String: Any]] else {
            return nil
        }

        return annotations.compactMap { $0["content"] as? String }
    }

    private func extractHighlights(from structured: String) -> [String]? {
        guard let data = structured.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let highlights = json["highlights"] as? [String] else {
            return nil
        }

        return highlights
    }
}

// MARK: - Supporting Types

/// Content extracted from a source atom
struct SourceContent {
    let atomUUID: String
    let title: String
    let type: AtomType
    let snippets: [String]
}

/// A snippet identified as relevant to a section
struct RelevantSnippet {
    let content: String
    let originalText: String
    let confidence: Double
}
