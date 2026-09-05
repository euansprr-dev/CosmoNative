// CosmoOS/AI/KnowledgeContextAssembler.swift
// Layer 4 Knowledge Context — assembles relevant connections into the mega-context
// prompt for structurally-informed content generation with intellectual originality.
// February 2026

import Foundation

// MARK: - Knowledge Context Data Models

struct RankedConnection: Identifiable {
    let id: UUID
    let atom: Atom
    let relevanceScore: Double
    let maturityLevel: ConnectionMaturityLevel
    let sectionSummaries: [String]

    init(atom: Atom, relevanceScore: Double, maturityLevel: ConnectionMaturityLevel, sectionSummaries: [String]) {
        self.id = UUID()
        self.atom = atom
        self.relevanceScore = relevanceScore
        self.maturityLevel = maturityLevel
        self.sectionSummaries = sectionSummaries
    }
}

struct KnowledgeContext {
    let connections: [RankedConnection]
    let supportingInsights: [String]
    let tokenEstimate: Int
    let formattedBlock: String
}

// MARK: - Knowledge Context Assembler

@MainActor
class KnowledgeContextAssembler {

    /// Assemble knowledge context from relevant connections for a content atom.
    /// Returns connections ranked by semantic relevance, filtered to Developing+ maturity,
    /// with supporting research insights.
    func assembleKnowledgeContext(contentAtom: Atom, profileId: String?) async -> KnowledgeContext {
        // 1. Find all connections scoped to the profile (or universal)
        let allConnections = await loadProfileConnections(profileId: profileId)
        guard !allConnections.isEmpty else {
            return KnowledgeContext(connections: [], supportingInsights: [], tokenEstimate: 0, formattedBlock: "")
        }

        // 2. Rank by semantic relevance to content piece
        let ideaTitle = contentAtom.title ?? contentAtom.body ?? ""
        guard !ideaTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return KnowledgeContext(connections: [], supportingInsights: [], tokenEstimate: 0, formattedBlock: "")
        }

        let ranked = await rankConnectionsByRelevance(connections: allConnections, query: ideaTitle)

        // 3. Filter: Developing maturity or higher only
        let filtered = ranked.filter { $0.maturityLevel.sortOrder >= ConnectionMaturityLevel.developing.sortOrder }

        // 4. Select top 1-3
        let selected = Array(filtered.prefix(3))
        guard !selected.isEmpty else {
            return KnowledgeContext(connections: [], supportingInsights: [], tokenEstimate: 0, formattedBlock: "")
        }

        // 5. Load supporting research insights for each connection
        var supportingInsights: [String] = []
        for rankedConn in selected {
            let insights = await loadInsightsForConnection(connectionUUID: rankedConn.atom.uuid)
            supportingInsights.append(contentsOf: insights)
        }

        // 6. Format as prompt block
        let formattedBlock = formatKnowledgeBlock(connections: selected, insights: supportingInsights)
        let tokenEstimate = formattedBlock.count / 4  // rough token estimate

        return KnowledgeContext(
            connections: selected,
            supportingInsights: supportingInsights,
            tokenEstimate: tokenEstimate,
            formattedBlock: formattedBlock
        )
    }

    /// Find relevant connections for an idea title, ranked by semantic relevance.
    /// Filters to Developing+ maturity, scoped to profile or universal.
    func findRelevantConnections(ideaTitle: String, profileId: String?) async -> [RankedConnection] {
        let allConnections = await loadProfileConnections(profileId: profileId)
        guard !allConnections.isEmpty else { return [] }

        let ranked = await rankConnectionsByRelevance(connections: allConnections, query: ideaTitle)
        return ranked.filter { $0.maturityLevel.sortOrder >= ConnectionMaturityLevel.developing.sortOrder }
    }

    // MARK: - Graph-Enhanced Context

    /// Assemble context using graph traversal for richer connections.
    /// Walks the knowledge graph from a content atom through its linked idea, swipes,
    /// client content, and intellectual frameworks to build a comprehensive context block.
    func assembleGraphEnhancedContext(
        contentUUID: UUID,
        clientUUID: UUID?,
        topic: String
    ) async -> String {
        var contextParts: [String] = []
        let queryEngine = GraphQueryEngine()

        // 1. Find source idea via graph edges
        do {
            let edges = try await queryEngine.getEdges(for: contentUUID.uuidString, direction: .both)

            var sourceIdeaUUID: String?
            var linkedSwipeUUIDs: [String] = []

            for edge in edges {
                let neighborUUID = edge.sourceUUID == contentUUID.uuidString ? edge.targetUUID : edge.sourceUUID
                let linkType = edge.linkType ?? ""

                if linkType.contains("ideaToContent") || linkType.contains("contentToIdea") {
                    sourceIdeaUUID = neighborUUID
                } else if linkType.contains("swipe") {
                    linkedSwipeUUIDs.append(neighborUUID)
                }
            }

            // Load source idea context
            if let ideaUUID = sourceIdeaUUID,
               let ideaAtom = try await AtomRepository.shared.fetch(uuid: ideaUUID) {
                let ideaTitle = ideaAtom.title ?? ""
                let ideaBody = (ideaAtom.body ?? "").prefix(500)
                if !ideaTitle.isEmpty || !ideaBody.isEmpty {
                    contextParts.append("## Source Idea")
                    if !ideaTitle.isEmpty { contextParts.append("**\(ideaTitle)**") }
                    if !ideaBody.isEmpty { contextParts.append(String(ideaBody)) }
                }

                // 2. From source idea, find linked swipes
                let ideaEdges = try await queryEngine.getEdges(for: ideaUUID, direction: .both)
                for edge in ideaEdges {
                    let neighborUUID = edge.sourceUUID == ideaUUID ? edge.targetUUID : edge.sourceUUID
                    let linkType = edge.linkType ?? ""
                    if linkType.contains("swipe") && !linkedSwipeUUIDs.contains(neighborUUID) {
                        linkedSwipeUUIDs.append(neighborUUID)
                    }
                }
            }

            // Load linked swipe context
            if !linkedSwipeUUIDs.isEmpty {
                var swipeParts: [String] = []
                for swipeUUID in linkedSwipeUUIDs.prefix(5) {
                    guard let swipeAtom = try? await AtomRepository.shared.fetch(uuid: swipeUUID) else { continue }
                    let title = swipeAtom.title ?? ""
                    let body = (swipeAtom.body ?? "").prefix(300)
                    if !title.isEmpty || !body.isEmpty {
                        let line = title.isEmpty ? String(body) : "**\(title)**: \(body)"
                        swipeParts.append(line)
                    }
                }
                if !swipeParts.isEmpty {
                    contextParts.append("## Linked Swipes")
                    contextParts.append(contentsOf: swipeParts)
                }
            }
        } catch {
            print("[KnowledgeContextAssembler] Graph traversal error: \(error.localizedDescription)")
        }

        // 3. Find client's top-performing content
        if let clientUUID = clientUUID {
            do {
                let allContent = try await AtomRepository.shared.fetchAll(type: .content)
                let clientContent = allContent.filter { atom in
                    guard let meta = atom.metadataDict else { return false }
                    return meta["clientProfileUUID"] as? String == clientUUID.uuidString
                }

                let topContent = clientContent.prefix(3)
                if !topContent.isEmpty {
                    contextParts.append("## Client's Recent Content")
                    for atom in topContent {
                        let title = atom.title ?? "Untitled"
                        let body = (atom.body ?? "").prefix(200)
                        contextParts.append("- **\(title)**: \(body)")
                    }
                }
            } catch {
                // Non-critical, continue
            }
        }

        // 4. Find relevant Connection atoms (intellectual frameworks)
        let connections = await searchConnections(query: topic)
        if !connections.isEmpty {
            contextParts.append("## Intellectual Frameworks")
            for conn in connections.prefix(3) {
                contextParts.append("**\(conn.title ?? "Framework")**")
                contextParts.append(String((conn.body ?? "").prefix(300)))
            }
        }

        return contextParts.joined(separator: "\n\n")
    }

    private func searchConnections(query: String) async -> [Atom] {
        do {
            let results = try await HybridSearchEngine.shared.search(
                query: query,
                limit: 5,
                entityTypes: [.connection]
            )

            var atoms: [Atom] = []
            for result in results {
                guard let uuid = result.entityUUID,
                      let atom = try? await AtomRepository.shared.fetch(uuid: uuid) else { continue }
                atoms.append(atom)
            }
            return atoms
        } catch {
            return []
        }
    }

    // MARK: - Private Helpers

    /// Load all connection atoms scoped to a profile, or universal connections.
    private func loadProfileConnections(profileId: String?) async -> [Atom] {
        do {
            // Lab principles have explicit acceptance and client scope. They
            // are injected by their scoped store, never by generic connection
            // discovery (which can also return archived or client-only rows).
            let allConnections = try await AtomRepository.shared.fetchAll(type: .connection).filter {
                $0.metadataValue(as: SwipeLabPrincipleEnvelope.self) == nil
            }

            if let profileId = profileId, !profileId.isEmpty {
                // Return connections linked to this profile + universal (no profile links)
                return allConnections.filter { conn in
                    let linkedIds = conn.connectionLinkedProfileIds
                    return linkedIds.contains(profileId) || linkedIds.isEmpty
                }
            } else {
                // No profile specified — return all connections
                return allConnections
            }
        } catch {
            print("KnowledgeContextAssembler: failed to load connections: \(error)")
            return []
        }
    }

    /// Rank connections by semantic relevance to a query using HybridSearchEngine.
    private func rankConnectionsByRelevance(connections: [Atom], query: String) async -> [RankedConnection] {
        let coDevEngine = ConnectionCoDevEngine()

        // Use HybridSearchEngine to find relevant connections by semantic search
        var searchResults: [HybridSearchEngine.SearchResult] = []
        do {
            searchResults = try await HybridSearchEngine.shared.search(
                query: query,
                limit: 20,
                entityTypes: [.connection]
            )
        } catch {
            print("KnowledgeContextAssembler: search failed: \(error)")
        }

        // Build UUID -> relevance score map from search results
        var relevanceMap: [String: Double] = [:]
        for result in searchResults {
            if let uuid = result.entityUUID {
                relevanceMap[uuid] = result.combinedScore
            }
        }

        // Rank each connection
        var ranked: [RankedConnection] = []
        for conn in connections {
            let relevance = relevanceMap[conn.uuid] ?? 0.0

            // Compute maturity
            let maturity = computeMaturityForConnection(conn, engine: coDevEngine)

            // Extract section summaries
            let summaries = extractSectionSummaries(from: conn)

            // Skip connections with zero relevance and no title match
            let titleMatch = (conn.title ?? "").lowercased().contains(query.lowercased().prefix(20))
            guard relevance > 0 || titleMatch else { continue }

            let finalRelevance = titleMatch && relevance == 0 ? 0.1 : relevance

            ranked.append(RankedConnection(
                atom: conn,
                relevanceScore: finalRelevance,
                maturityLevel: maturity,
                sectionSummaries: summaries
            ))
        }

        return ranked.sorted { $0.relevanceScore > $1.relevanceScore }
    }

    /// Compute maturity level for a connection atom.
    private func computeMaturityForConnection(_ connection: Atom, engine: ConnectionCoDevEngine) -> ConnectionMaturityLevel {
        // Check if maturity is cached in metadata
        if let cached = connection.connectionMaturityLevel,
           let level = ConnectionMaturityLevel(rawValue: cached) {
            return level
        }

        // Compute from structured data
        var filledSections = 0
        if let structured = connection.structured,
           let data = ConnectionStructuredData.fromJSON(structured) {
            filledSections = data.sections.filter { !$0.items.isEmpty }.count
        }

        // Simple heuristic without content usage lookup (for speed)
        if filledSections >= 5 {
            return .mature
        } else if filledSections >= 2 {
            return .developing
        }
        return .seed
    }

    /// Extract filled section summaries from a connection's structured data.
    private func extractSectionSummaries(from connection: Atom) -> [String] {
        guard let structured = connection.structured,
              let data = ConnectionStructuredData.fromJSON(structured) else {
            return []
        }

        var summaries: [String] = []
        for section in data.sections where !section.items.isEmpty {
            let itemTexts = section.items.map(\.content).joined(separator: "; ")
            summaries.append("\(section.type.displayName): \(itemTexts)")
        }
        return summaries
    }

    /// Load research insight atoms linked to a connection via the graph.
    private func loadInsightsForConnection(connectionUUID: String) async -> [String] {
        do {
            let queryEngine = GraphQueryEngine()
            let neighbors = try await queryEngine.getNeighbors(of: connectionUUID, direction: .both, limit: 20)

            var insights: [String] = []
            for neighbor in neighbors {
                guard let atom = try? await AtomRepository.shared.fetch(uuid: neighbor.node.atomUUID) else { continue }

                // Include research insights and insight extractions
                if atom.type == .research || atom.type == .insightExtraction {
                    let title = atom.title ?? ""
                    let body = (atom.body ?? "").prefix(500)
                    if !body.isEmpty {
                        let insight = title.isEmpty ? String(body) : "\(title): \(body)"
                        insights.append(insight)
                    }
                }
            }
            return Array(insights.prefix(10))
        } catch {
            return []
        }
    }

    /// Format the knowledge context as a prompt block for the mega-context system.
    private func formatKnowledgeBlock(connections: [RankedConnection], insights: [String]) -> String {
        var lines: [String] = []
        lines.append("=== LAYER 4: KNOWLEDGE CONTEXT ===")
        lines.append("")
        lines.append("The following are unique intellectual frameworks (Connections) relevant to this content.")
        lines.append("Use these to make the content intellectually original — weave in unique terminology,")
        lines.append("process steps, beliefs, and frameworks that differentiate this content from generic advice.")
        lines.append("")

        for (i, conn) in connections.enumerated() {
            let title = conn.atom.title ?? "Untitled Connection"
            lines.append("--- CONNECTION #\(i + 1): \(title) ---")
            lines.append("Maturity: \(conn.maturityLevel.displayName) | Relevance: \(String(format: "%.2f", conn.relevanceScore))")

            // Full section content
            if !conn.sectionSummaries.isEmpty {
                for summary in conn.sectionSummaries {
                    lines.append("  \(summary)")
                }
            }

            // Connection body (concept overview)
            let body = conn.atom.body ?? ""
            if !body.isEmpty {
                let truncated = body.count > 1500 ? String(body.prefix(1500)) + "..." : body
                lines.append("Overview: \(truncated)")
            }
            lines.append("")
        }

        // Supporting insights from linked research
        if !insights.isEmpty {
            lines.append("--- SUPPORTING INSIGHTS ---")
            for (i, insight) in insights.prefix(8).enumerated() {
                let truncated = insight.count > 400 ? String(insight.prefix(400)) + "..." : insight
                lines.append("Insight #\(i + 1): \(truncated)")
            }
            lines.append("")
        }

        lines.append("INSTRUCTION: Integrate these connection frameworks naturally into the content.")
        lines.append("Use specific terminology, process names, and belief statements from the connections above.")
        lines.append("The goal is intellectual originality — content that could only come from someone with these frameworks.")

        return lines.joined(separator: "\n")
    }
}
