// CosmoOS/AI/SmartOrganizer.swift
// AI-powered auto-organization for the Library
// Suggests folder groupings via embedding clustering and Claude analysis

import Foundation

/// Smart organization engine that suggests groupings and surfaces hidden connections
@MainActor
final class SmartOrganizer {
    static let shared = SmartOrganizer()

    // MARK: - Configuration

    /// Minimum loose atoms before suggesting folders
    private let minLooseAtomsForSuggestion = 20

    /// Maximum clusters to suggest
    private let maxSuggestions = 5

    /// Cache TTL for suggestions (1 hour)
    private let suggestionCacheTTL: TimeInterval = 3600

    // MARK: - State

    /// Cached folder suggestions
    private var cachedSuggestions: (timestamp: Date, suggestions: [FolderSuggestion])?

    /// Whether a suggestion analysis is in progress
    private(set) var isAnalyzing: Bool = false

    private init() {}

    // MARK: - Folder Suggestions

    /// Analyze loose atoms and suggest folder groupings.
    /// Returns nil if fewer than `minLooseAtomsForSuggestion` loose atoms exist.
    func suggestFolders() async -> [FolderSuggestion]? {
        // Check cache
        if let cached = cachedSuggestions,
           Date().timeIntervalSince(cached.timestamp) < suggestionCacheTTL {
            return cached.suggestions
        }

        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            // Fetch all user-facing atoms
            let userTypes: [AtomType] = [.idea, .task, .content, .research, .connection]
            let allAtoms = try await AtomRepository.shared.fetchAll(types: userTypes)
            let activeAtoms = allAtoms.filter { !$0.isDeleted }

            // Find "loose" atoms (not in any project)
            let looseAtoms = activeAtoms.filter { atom in
                !atom.linksList.contains { $0.type == AtomLinkType.project.rawValue }
            }

            guard looseAtoms.count >= minLooseAtomsForSuggestion else {
                return nil
            }

            // Build atom summaries for Claude
            let atomSummaries = looseAtoms.prefix(50).map { atom in
                let type = atom.type.displayName
                let title = atom.title ?? "Untitled"
                let body = (atom.body ?? "").prefix(80)
                return "[\(type)] \(title): \(body)"
            }.joined(separator: "\n")

            // Ask Claude to identify groupings
            let prompt = """
            I have \(looseAtoms.count) unorganized items in my knowledge base. Here are the first \(min(50, looseAtoms.count)):

            \(atomSummaries)

            Identify 2-5 logical folder groupings based on topic, theme, or project. For each group:
            1. Suggest a folder name (short, descriptive)
            2. List which items belong (by their title)
            3. Explain why they belong together (1 sentence)

            Return as JSON array: [{"name": "...", "reason": "...", "items": ["title1", "title2"]}]
            Return ONLY the JSON array.
            """

            let response = try await ResearchService.shared.analyzeContent(prompt: prompt)
            let suggestions = parseSuggestions(response, atoms: looseAtoms)

            if !suggestions.isEmpty {
                cachedSuggestions = (timestamp: Date(), suggestions: suggestions)
            }

            return suggestions.isEmpty ? nil : suggestions

        } catch {
            print("⚠️ SmartOrganizer suggestion failed: \(error)")
            return nil
        }
    }

    // MARK: - Find Related Atoms

    /// Find atoms semantically related to a given atom using vector search.
    /// Used for the "Find related" action in atom detail views.
    func findRelated(to atomUUID: String, limit: Int = 10) async -> [RelatedAtomResult] {
        do {
            // Fetch the source atom
            guard let atom = try await AtomRepository.shared.fetch(uuid: atomUUID) else {
                return []
            }

            // Get text content for embedding
            let searchText = [atom.title, atom.body].compactMap { $0 }.joined(separator: " ")
            guard !searchText.isEmpty else { return [] }

            // Generate embedding and search
            let embedding = try await DaemonXPCClient.shared.embed(text: searchText)
            let truncated = Array(embedding.prefix(VectorConfig.matryoshkaDimension))

            // Search via VectorDatabase
            let results = try await VectorDatabase.shared.searchByVector(
                embedding: truncated,
                limit: limit + 1 // +1 to exclude self
            )

            // Convert to RelatedAtomResult, excluding the source atom
            var related: [RelatedAtomResult] = []
            for result in results {
                guard result.entityUUID != atomUUID else { continue }
                guard related.count < limit else { break }

                let relatedAtom = try? await AtomRepository.shared.fetch(uuid: result.entityUUID ?? "")
                related.append(RelatedAtomResult(
                    uuid: result.entityUUID ?? "",
                    title: relatedAtom?.title ?? "Untitled",
                    atomType: relatedAtom?.type ?? .idea,
                    similarity: result.similarity,
                    preview: relatedAtom?.body.flatMap { String($0.prefix(80)) }
                ))
            }

            return related

        } catch {
            print("⚠️ SmartOrganizer findRelated failed: \(error)")
            return []
        }
    }

    // MARK: - Parse Suggestions

    private func parseSuggestions(_ response: String, atoms: [Atom]) -> [FolderSuggestion] {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let startIndex = trimmed.firstIndex(of: "["),
              let endIndex = trimmed.lastIndex(of: "]") else {
            return []
        }

        let jsonString = String(trimmed[startIndex...endIndex])
        guard let data = jsonString.data(using: .utf8) else { return [] }

        struct RawSuggestion: Decodable {
            let name: String
            let reason: String
            let items: [String]
        }

        guard let raw = try? JSONDecoder().decode([RawSuggestion].self, from: data) else {
            return []
        }

        return raw.prefix(maxSuggestions).map { suggestion in
            // Match item titles to actual atom UUIDs
            let matchedUUIDs = suggestion.items.compactMap { itemTitle -> String? in
                atoms.first { atom in
                    (atom.title ?? "").localizedCaseInsensitiveContains(itemTitle) ||
                    itemTitle.localizedCaseInsensitiveContains(atom.title ?? "---")
                }?.uuid
            }

            return FolderSuggestion(
                id: UUID().uuidString,
                folderName: suggestion.name,
                reason: suggestion.reason,
                atomUUIDs: matchedUUIDs,
                atomCount: matchedUUIDs.count
            )
        }.filter { $0.atomCount >= 2 }
    }

    /// Clear cached suggestions
    func clearCache() {
        cachedSuggestions = nil
    }
}

// MARK: - Data Types

/// A suggested folder grouping
struct FolderSuggestion: Identifiable {
    let id: String
    let folderName: String
    let reason: String
    let atomUUIDs: [String]
    let atomCount: Int
}

/// A related atom found via semantic search
struct RelatedAtomResult: Identifiable {
    let id = UUID()
    let uuid: String
    let title: String
    let atomType: AtomType
    let similarity: Float
    let preview: String?
}
