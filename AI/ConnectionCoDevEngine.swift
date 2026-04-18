// CosmoOS/AI/ConnectionCoDevEngine.swift
// AI engine for Connection co-development: relation suggestions, ghost generation,
// section item synthesis, and maturity computation.
// February 2026

import Foundation

// MARK: - Maturity Level

enum ConnectionMaturityLevel: String, Codable, CaseIterable {
    case seed
    case developing
    case mature
    case proven

    var displayName: String {
        switch self {
        case .seed: return "Seed"
        case .developing: return "Developing"
        case .mature: return "Mature"
        case .proven: return "Proven"
        }
    }

    var sortOrder: Int {
        switch self {
        case .seed: return 0
        case .developing: return 1
        case .mature: return 2
        case .proven: return 3
        }
    }
}

private extension Atom {
    var isEligibleWellSource: Bool {
        switch type {
        case .research, .idea, .note, .content, .connection:
            return true
        default:
            return false
        }
    }
}

// MARK: - Relation Suggestion

struct RelationSuggestion: Identifiable, Equatable {
    let id: UUID
    let suggestedSections: [ConnectionSectionType]
    let relationNote: String
    let sourceTitle: String
    let sourceUUID: String

    init(
        id: UUID = UUID(),
        suggestedSections: [ConnectionSectionType],
        relationNote: String,
        sourceTitle: String,
        sourceUUID: String
    ) {
        self.id = id
        self.suggestedSections = suggestedSections
        self.relationNote = relationNote
        self.sourceTitle = sourceTitle
        self.sourceUUID = sourceUUID
    }
}

// MARK: - Connection Co-Dev Engine

@MainActor
class ConnectionCoDevEngine: ObservableObject {

    // MARK: - Suggest Relation

    /// Suggests which 1-2 sections a source material is most relevant to,
    /// plus a draft relation note. Uses Strategist tier (Sonnet) for speed.
    func suggestRelation(
        sourceMaterial: Atom,
        connection: Atom
    ) async throws -> RelationSuggestion {
        let connectionTitle = connection.title ?? "Untitled Connection"
        let sourceTitle = sourceMaterial.title ?? "Untitled"
        let sourceBody = (sourceMaterial.body ?? "").prefix(800)

        // Build existing section summary
        var sectionSummary = ""
        if let structured = connection.structured,
           let data = ConnectionStructuredData.fromJSON(structured) {
            for section in data.sections where !section.items.isEmpty {
                let itemTexts = section.items.prefix(2).map { $0.content }.joined(separator: "; ")
                sectionSummary += "\(section.type.displayName): \(itemTexts)\n"
            }
        }

        let prompt = """
        You are analyzing how a source material relates to a Connection framework.

        Connection: "\(connectionTitle)"
        \(sectionSummary.isEmpty ? "" : "Existing sections:\n\(sectionSummary)")

        Source material: "\(sourceTitle)"
        Content: \(sourceBody)

        The 8 section types are: Goal, Problems, Benefits, Examples, Beliefs & Objections, Process, Concept Name, References

        Respond in this exact format:
        SECTIONS: <comma-separated list of 1-2 most relevant section names>
        NOTE: <1-2 sentence relation note explaining how this source connects>
        """

        do {
            let response = try await ResearchService.shared.analyze(
                prompt: prompt,
                tier: .strategist,
                maxTokens: 300
            )

            return parseRelationResponse(
                response,
                sourceTitle: sourceTitle,
                sourceUUID: sourceMaterial.uuid
            )
        } catch {
            // Fallback: keyword-based suggestion
            return fallbackRelationSuggestion(
                sourceBody: String(sourceBody),
                sourceTitle: sourceTitle,
                sourceUUID: sourceMaterial.uuid
            )
        }
    }

    // MARK: - Generate Ghost Suggestions

    /// Generates 1-3 ghost suggestions per empty section from linked sources.
    /// Each suggestion has text, source attribution, and target section.
    func generateGhostSuggestions(
        connection: Atom,
        linkedSources: [Atom]
    ) async throws -> [GhostSuggestion] {
        guard !linkedSources.isEmpty else { return [] }

        let connectionTitle = connection.title ?? "Untitled Connection"

        // Identify which sections are empty or underdeveloped
        var emptySections: [ConnectionSectionType] = []
        if let structured = connection.structured,
           let data = ConnectionStructuredData.fromJSON(structured) {
            for section in data.sections where section.items.isEmpty {
                emptySections.append(section.type)
            }
        } else {
            emptySections = ConnectionSectionType.allCases.filter { $0 != .conceptName }
        }

        guard !emptySections.isEmpty else { return [] }

        // Build source content digest
        var sourceDigest = ""
        for source in linkedSources.prefix(5) {
            let title = source.title ?? "Untitled"
            let body = (source.body ?? "").prefix(400)
            sourceDigest += "[\(title)]: \(body)\n---\n"
        }

        let sectionNames = emptySections.map { $0.displayName }.joined(separator: ", ")

        let prompt = """
        You are generating section suggestions for a Connection framework based on linked source materials.

        Connection: "\(connectionTitle)"
        Empty sections needing suggestions: \(sectionNames)

        Source materials:
        \(sourceDigest)

        For each empty section, generate 1-2 suggestions ONLY if the source material provides relevant information.
        Each suggestion must be grounded in a specific source.

        Respond as a list with this exact format (one per line):
        SECTION: <section name> | SOURCE: <source title> | TEXT: <suggested content for the section>

        Only suggest items with clear source backing. Do not fabricate.
        """

        do {
            let response = try await ResearchService.shared.analyze(
                prompt: prompt,
                tier: .strategist,
                maxTokens: 1500
            )

            return parseGhostSuggestionsResponse(
                response,
                linkedSources: linkedSources,
                emptySections: emptySections
            )
        } catch {
            return []
        }
    }

    // MARK: - Generate Section Item

    /// Produces pre-populated text for a section item when a category chip is clicked.
    /// Derives content from source material + relation note + section context.
    func generateSectionItem(
        sourceMaterial: Atom,
        targetSection: ConnectionSectionType,
        relationNote: String?,
        connection: Atom
    ) async -> String {
        let sourceTitle = sourceMaterial.title ?? "Untitled"
        let sourceBody = (sourceMaterial.body ?? "").prefix(600)
        let connectionTitle = connection.title ?? "Untitled"
        let note = relationNote ?? ""

        // Template-based generation with optional AI enhancement
        let baseContent = buildTemplateItem(
            sourceTitle: sourceTitle,
            sourceBody: String(sourceBody),
            targetSection: targetSection,
            connectionTitle: connectionTitle,
            relationNote: note
        )

        // Try AI enhancement for richer output
        let prompt = """
        Write a concise item for the "\(targetSection.displayName)" section of the connection "\(connectionTitle)".

        Based on this source: "\(sourceTitle)"
        Source content: \(sourceBody)
        \(note.isEmpty ? "" : "Relation context: \(note)")

        Write 1-2 sentences that distill the key insight for this section. Include source attribution in parentheses.
        Do not use any formatting, headers, or bullet points. Just the plain text.
        Do NOT start with the source title or topic name — jump straight into the insight.
        """

        do {
            let response = try await ResearchService.shared.analyze(
                prompt: prompt,
                tier: .sensor,
                maxTokens: 200
            )
            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? baseContent : trimmed
        } catch {
            return baseContent
        }
    }

    // MARK: - Compute Maturity

    /// Pure computation of connection maturity level.
    func computeMaturity(
        connection: Atom,
        sourceCount: Int,
        contentUsageCount: Int,
        profileCount: Int
    ) -> ConnectionMaturityLevel {
        var filledSections = 0
        if let structured = connection.structured,
           let data = ConnectionStructuredData.fromJSON(structured) {
            filledSections = data.sections.filter { !$0.items.isEmpty }.count
        }

        // Proven: Mature + used in published content that performed well
        if filledSections >= 5 && sourceCount >= 3 && contentUsageCount >= 2 {
            return .proven
        }

        // Mature: 5+ sections, 3+ sources, used in 1+ content
        if filledSections >= 5 && sourceCount >= 3 && contentUsageCount >= 1 {
            return .mature
        }

        // Developing: 2-4 sections, 1+ sources
        if filledSections >= 2 && sourceCount >= 1 {
            return .developing
        }

        // Seed: Name only, 0-1 sections, no sources
        return .seed
    }

    // MARK: - Find Content Usage

    /// Finds content atoms that reference this connection.
    func findContentUsage(connectionUUID: String) async -> [(atom: Atom, sectionsUsed: [String])] {
        do {
            let queryEngine = GraphQueryEngine()
            let neighbors = try await queryEngine.getNeighbors(of: connectionUUID, direction: .both, limit: 50)

            var usages: [(atom: Atom, sectionsUsed: [String])] = []
            for neighbor in neighbors {
                if let atom = try? await AtomRepository.shared.fetch(uuid: neighbor.node.atomUUID),
                   atom.type == .content {
                    // Check if body references connection sections
                    let sectionsUsed = detectSectionsUsed(in: atom, connectionUUID: connectionUUID)
                    usages.append((atom: atom, sectionsUsed: sectionsUsed))
                }
            }
            return usages
        } catch {
            return []
        }
    }

    /// Finds atoms explicitly linked to this connection and eligible to appear in
    /// The Well before they are quoted into any station item.
    func findLinkedSourceMaterials(for connectionUUID: String, limit: Int = 20) async -> [Atom] {
        do {
            let queryEngine = GraphQueryEngine()
            let neighbors = try await queryEngine.getNeighbors(of: connectionUUID, direction: .both, limit: 80)

            var seen = Set<String>()
            var sources: [Atom] = []

            for neighbor in neighbors {
                let uuid = neighbor.node.atomUUID
                guard uuid != connectionUUID, !seen.contains(uuid) else { continue }
                guard let atom = try? await AtomRepository.shared.fetch(uuid: uuid),
                      atom.isEligibleWellSource else {
                    continue
                }
                seen.insert(uuid)
                sources.append(atom)
                if sources.count >= limit {
                    break
                }
            }

            return sources.sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return (lhs.title ?? "") < (rhs.title ?? "")
            }
        } catch {
            return []
        }
    }

    /// Finds source materials relevant to this connection via semantic search.
    func findSourceMaterials(for connection: Atom, limit: Int = 10) async -> [Atom] {
        let query = connection.title ?? ""
        guard !query.isEmpty else { return [] }

        do {
            let results = try await HybridSearchEngine.shared.search(
                query: query,
                limit: limit,
                entityTypes: [.research, .idea, .connection]
            )

            var atoms: [Atom] = []
            for result in results {
                guard let uuid = result.entityUUID, uuid != connection.uuid else { continue }
                if let atom = try? await AtomRepository.shared.fetch(uuid: uuid) {
                    atoms.append(atom)
                }
            }
            return atoms
        } catch {
            return []
        }
    }

    // MARK: - Private Helpers

    private func parseRelationResponse(
        _ response: String,
        sourceTitle: String,
        sourceUUID: String
    ) -> RelationSuggestion {
        var sections: [ConnectionSectionType] = []
        var note = ""

        for line in response.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.uppercased().hasPrefix("SECTIONS:") {
                let sectionStr = trimmed.replacingOccurrences(of: "SECTIONS:", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let names = sectionStr.components(separatedBy: ",").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                }
                for name in names {
                    if let match = matchSectionType(name) {
                        sections.append(match)
                    }
                }
            } else if trimmed.uppercased().hasPrefix("NOTE:") {
                note = trimmed.replacingOccurrences(of: "NOTE:", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if sections.isEmpty {
            sections = [.examples]
        }

        return RelationSuggestion(
            suggestedSections: sections,
            relationNote: note.isEmpty ? "Related source material" : note,
            sourceTitle: sourceTitle,
            sourceUUID: sourceUUID
        )
    }

    private func parseGhostSuggestionsResponse(
        _ response: String,
        linkedSources: [Atom],
        emptySections: [ConnectionSectionType]
    ) -> [GhostSuggestion] {
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
            let textPart = parts[2].replacingOccurrences(of: "TEXT:", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let sectionType = matchSectionType(sectionPart.lowercased()),
                  emptySections.contains(sectionType),
                  !textPart.isEmpty else { continue }

            // Find matching source atom
            let matchingSource = linkedSources.first {
                ($0.title ?? "").lowercased().contains(sourcePart.lowercased()) ||
                sourcePart.lowercased().contains(($0.title ?? "").lowercased())
            } ?? linkedSources.first

            guard let source = matchingSource else { continue }

            suggestions.append(GhostSuggestion(
                content: textPart,
                sourceAtomUUID: source.uuid,
                sourceAtomTitle: source.title ?? "Source",
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

    private func fallbackRelationSuggestion(
        sourceBody: String,
        sourceTitle: String,
        sourceUUID: String
    ) -> RelationSuggestion {
        let lower = sourceBody.lowercased()
        var sections: [ConnectionSectionType] = []

        if lower.contains("example") || lower.contains("case study") || lower.contains("instance") {
            sections.append(.examples)
        }
        if lower.contains("problem") || lower.contains("challenge") || lower.contains("struggle") {
            sections.append(.problems)
        }
        if lower.contains("benefit") || lower.contains("advantage") || lower.contains("result") {
            sections.append(.benefits)
        }
        if lower.contains("step") || lower.contains("process") || lower.contains("how to") {
            sections.append(.process)
        }
        if lower.contains("study") || lower.contains("research") || lower.contains("data") {
            sections.append(.references)
        }

        if sections.isEmpty {
            sections = [.examples]
        }

        return RelationSuggestion(
            suggestedSections: Array(sections.prefix(2)),
            relationNote: "Related source material",
            sourceTitle: sourceTitle,
            sourceUUID: sourceUUID
        )
    }

    private func buildTemplateItem(
        sourceTitle: String,
        sourceBody: String,
        targetSection: ConnectionSectionType,
        connectionTitle: String,
        relationNote: String
    ) -> String {
        let snippet = String(sourceBody.prefix(120))
        switch targetSection {
        case .goal:
            return "\(snippet) (from: \(sourceTitle))"
        case .problems:
            return "\(snippet) (from: \(sourceTitle))"
        case .benefits:
            return "\(snippet) (from: \(sourceTitle))"
        case .examples:
            return "\(snippet) (from: \(sourceTitle))"
        case .beliefsObjections:
            return "\(snippet) (from: \(sourceTitle))"
        case .process:
            return "\(snippet) (from: \(sourceTitle))"
        case .conceptName:
            return sourceTitle
        case .references:
            return "\(sourceTitle): \(snippet)"
        }
    }

    private func detectSectionsUsed(in content: Atom, connectionUUID: String) -> [String] {
        let body = (content.body ?? "").lowercased()
        var used: [String] = []
        for sectionType in ConnectionSectionType.allCases {
            let keywords = sectionType.displayName.lowercased()
            if body.contains(keywords) {
                used.append(sectionType.displayName)
            }
        }
        return used
    }
}
