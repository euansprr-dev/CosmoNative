// CosmoOS/AI/InboxClassificationEngine.swift
// 3-stage classification pipeline for Smart Triage Inbox
// Determines: merge into existing atom, place on thinkspace, or create new
// March 2026

import Foundation
import GRDB

@MainActor
final class InboxClassificationEngine {
    static let shared = InboxClassificationEngine()

    private let hybridSearch = HybridSearchEngine.shared
    private let database = CosmoDatabase.shared

    // Thresholds
    private let mergeHighConfidence: Double = 0.75
    private let mergeLowConfidence: Double = 0.55
    private let placeThreshold: Double = 0.40

    private let flashModel = "google/gemini-3.1-flash-lite-preview"

    private init() {}

    // MARK: - Result Types

    struct ClassificationResult: Sendable {
        let classification: InboxClassification
        let confidence: Double
        let title: String
        let mergeTarget: MergeTarget?
        let placeTarget: PlaceTarget?
        let alternatives: [Alternative]
    }

    struct MergeTarget: Sendable {
        let atomUuid: String
        let atomTitle: String
        let atomType: String
        let similarity: Double
        let preview: String
    }

    struct PlaceTarget: Sendable {
        let thinkspaceId: String
        let thinkspaceName: String
        let suggestedAtomType: String
    }

    struct Alternative: Sendable {
        let classification: InboxClassification
        let label: String
        let confidence: Double
        let mergeTarget: MergeTarget?
        let placeTarget: PlaceTarget?
    }

    // MARK: - Classification Pipeline

    func classify(text: String, source: InboxSource) async -> ClassificationResult {
        // Stage 1: Semantic search for similar atoms
        let searchResults = await runSemanticSearch(text: text)

        // Stage 2: Thinkspace matching for top results
        let thinkspaceMatch = await findThinkspaceForResults(searchResults)

        // Stage 3: Title extraction
        let title = await extractTitle(text: text)

        // Decision logic
        return buildResult(
            text: text,
            title: title,
            searchResults: searchResults,
            thinkspaceMatch: thinkspaceMatch
        )
    }

    // MARK: - Stage 1: Semantic Search

    private func runSemanticSearch(text: String) async -> [HybridSearchEngine.SearchResult] {
        do {
            return try await hybridSearch.search(
                query: text,
                limit: 10,
                entityTypes: nil
            )
        } catch {
            print("⚠️ [InboxClassification] Search failed: \(error)")
            return []
        }
    }

    // MARK: - Stage 2: Thinkspace Matching

    private struct ThinkspaceMatch: Sendable {
        let thinkspaceId: String
        let thinkspaceName: String
        let matchCount: Int
    }

    private func findThinkspaceForResults(_ results: [HybridSearchEngine.SearchResult]) async -> ThinkspaceMatch? {
        let entityUuids = results.compactMap(\.entityUUID)
        guard !entityUuids.isEmpty else { return nil }

        // Find which thinkspaces contain these atoms via canvas_blocks
        do {
            let thinkspaceCounts: [(String, Int)] = try await database.asyncRead { db in
                let placeholders = entityUuids.map { _ in "?" }.joined(separator: ", ")
                let sql = """
                    SELECT thinkspace_id, COUNT(*) as cnt
                    FROM canvas_blocks
                    WHERE entity_uuid IN (\(placeholders))
                      AND is_deleted = 0
                      AND thinkspace_id IS NOT NULL
                    GROUP BY thinkspace_id
                    ORDER BY cnt DESC
                    LIMIT 3
                """
                let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(entityUuids))
                return rows.compactMap { row -> (String, Int)? in
                    guard let tsId = row["thinkspace_id"] as? String,
                          let cnt = row["cnt"] as? Int else { return nil }
                    return (tsId, cnt)
                }
            }

            guard let top = thinkspaceCounts.first else { return nil }

            // Resolve thinkspace name
            let thinkspaces = ThinkspaceManager.shared.thinkspaces
            let name = thinkspaces.first(where: { $0.id == top.0 })?.name ?? "Thinkspace"

            return ThinkspaceMatch(
                thinkspaceId: top.0,
                thinkspaceName: name,
                matchCount: top.1
            )
        } catch {
            print("⚠️ [InboxClassification] Thinkspace query failed: \(error)")
            return nil
        }
    }

    // MARK: - Stage 3: Title Extraction

    private func extractTitle(text: String) async -> String {
        let words = text.split(separator: " ")

        // Short text: use first sentence or whole text
        if words.count < 30 {
            let firstSentence = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n")).first ?? text
            return String(firstSentence.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Long text: use LLM to extract a title
        do {
            let prompt = """
            Extract a concise title (max 8 words) from this text. Return ONLY the title, no quotes or explanation.

            Text: \(String(text.prefix(1000)))
            """
            let title = try await ResearchService.shared.analyze(
                prompt: prompt,
                model: flashModel,
                maxTokens: 30,
                temperature: 0.0
            )
            let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return cleaned.isEmpty ? String(text.prefix(60)) : String(cleaned.prefix(80))
        } catch {
            // Fallback: first sentence
            let firstSentence = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n")).first ?? text
            return String(firstSentence.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    // MARK: - Decision Logic

    private func buildResult(
        text: String,
        title: String,
        searchResults: [HybridSearchEngine.SearchResult],
        thinkspaceMatch: ThinkspaceMatch?
    ) -> ClassificationResult {
        var alternatives: [Alternative] = []

        // Check for merge candidate
        if let topResult = searchResults.first, topResult.combinedScore >= mergeLowConfidence {
            let mergeTarget = MergeTarget(
                atomUuid: topResult.entityUUID ?? "",
                atomTitle: topResult.title,
                atomType: topResult.entityType.rawValue,
                similarity: topResult.combinedScore,
                preview: topResult.preview
            )

            let confidence = min(topResult.combinedScore, 1.0)

            // Build alternatives: other merge candidates + place option
            for result in searchResults.dropFirst().prefix(2) where result.combinedScore >= mergeLowConfidence {
                alternatives.append(Alternative(
                    classification: .merge,
                    label: "Merge with: \(result.title)",
                    confidence: result.combinedScore,
                    mergeTarget: MergeTarget(
                        atomUuid: result.entityUUID ?? "",
                        atomTitle: result.title,
                        atomType: result.entityType.rawValue,
                        similarity: result.combinedScore,
                        preview: result.preview
                    ),
                    placeTarget: nil
                ))
            }

            if let ts = thinkspaceMatch {
                alternatives.append(Alternative(
                    classification: .place,
                    label: "Place in: \(ts.thinkspaceName)",
                    confidence: 0.5,
                    mergeTarget: nil,
                    placeTarget: PlaceTarget(
                        thinkspaceId: ts.thinkspaceId,
                        thinkspaceName: ts.thinkspaceName,
                        suggestedAtomType: AtomType.connection.rawValue
                    )
                ))
            }

            return ClassificationResult(
                classification: .merge,
                confidence: confidence,
                title: title,
                mergeTarget: mergeTarget,
                placeTarget: nil,
                alternatives: alternatives
            )
        }

        // Check for thinkspace placement
        if let ts = thinkspaceMatch, ts.matchCount >= 2 {
            // Determine suggested atom type based on text characteristics
            let suggestedType = suggestAtomType(text: text)

            let placeTarget = PlaceTarget(
                thinkspaceId: ts.thinkspaceId,
                thinkspaceName: ts.thinkspaceName,
                suggestedAtomType: suggestedType
            )

            // Add "new" as alternative
            alternatives.append(Alternative(
                classification: .new,
                label: "Create without placing",
                confidence: 0.3,
                mergeTarget: nil,
                placeTarget: nil
            ))

            return ClassificationResult(
                classification: .place,
                confidence: 0.6,
                title: title,
                mergeTarget: nil,
                placeTarget: placeTarget,
                alternatives: alternatives
            )
        }

        // Weak thinkspace match
        if let ts = thinkspaceMatch {
            alternatives.append(Alternative(
                classification: .place,
                label: "Place in: \(ts.thinkspaceName)",
                confidence: 0.35,
                mergeTarget: nil,
                placeTarget: PlaceTarget(
                    thinkspaceId: ts.thinkspaceId,
                    thinkspaceName: ts.thinkspaceName,
                    suggestedAtomType: suggestAtomType(text: text)
                )
            ))
        }

        // Default: new
        return ClassificationResult(
            classification: .new,
            confidence: 0.5,
            title: title,
            mergeTarget: nil,
            placeTarget: nil,
            alternatives: alternatives
        )
    }

    // MARK: - Helpers

    private func suggestAtomType(text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("research") || lower.contains("article") || lower.contains("study") || lower.contains("read") {
            return AtomType.research.rawValue
        }
        if lower.contains("idea") || lower.contains("concept") || lower.contains("what if") {
            return AtomType.idea.rawValue
        }
        if lower.contains("connect") || lower.contains("remind") || lower.contains("thought about") {
            return AtomType.connection.rawValue
        }
        return AtomType.connection.rawValue // Default for general thoughts
    }
}
