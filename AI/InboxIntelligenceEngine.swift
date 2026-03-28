// CosmoOS/AI/InboxIntelligenceEngine.swift
// Intelligence layer for the inbox — auto-grouping, priority scoring,
// stale detection, per-item insights via LLM
// March 2026

import Foundation

@MainActor
final class InboxIntelligenceEngine {
    static let shared = InboxIntelligenceEngine()

    private var cachedGroupHash: Int = 0
    private var cachedInsightUUIDs: Set<String> = []

    // MARK: - Auto-Grouping

    /// Groups inbox items that share the same merge target or thinkspace placement.
    /// Only runs when items change (checked via hash).
    func computeGroups(items: [InboxItem]) -> [InboxItemGroup] {
        let newHash = items.map(\.uuid).hashValue
        guard newHash != cachedGroupHash else { return [] }
        cachedGroupHash = newHash

        guard items.count >= 3 else { return [] }

        var groups: [InboxItemGroup] = []

        // Group by shared merge target
        var mergeTargetGroups: [String: [String]] = [:]
        for item in items {
            if let targetUuid = item.mergeTargetUuid, item.confidence > 0.5 {
                mergeTargetGroups[targetUuid, default: []].append(item.uuid)
            }
        }

        for (targetUuid, itemIds) in mergeTargetGroups where itemIds.count >= 2 {
            let targetTitle = items
                .first(where: { $0.mergeTargetUuid == targetUuid })?
                .mergeTargetTitle ?? "Unknown"

            groups.append(InboxItemGroup(
                id: "merge-\(targetUuid)",
                theme: "Related to \"\(targetTitle)\"",
                itemIds: itemIds,
                suggestedAction: "Merge all \(itemIds.count) into \"\(targetTitle)\"",
                mergeTargetUuid: targetUuid,
                mergeTargetTitle: targetTitle
            ))
        }

        // Group by shared thinkspace placement
        var placeGroups: [String: [String]] = [:]
        for item in items {
            if item.classification == .place, let tsId = item.placeThinkspaceId {
                placeGroups[tsId, default: []].append(item.uuid)
            }
        }

        for (tsId, itemIds) in placeGroups where itemIds.count >= 2 {
            let tsName = items
                .first(where: { $0.placeThinkspaceId == tsId })?
                .placeThinkspaceName ?? "Unknown"

            groups.append(InboxItemGroup(
                id: "place-\(tsId)",
                theme: "Place on \"\(tsName)\"",
                itemIds: itemIds,
                suggestedAction: "Place all \(itemIds.count) on \"\(tsName)\"",
                mergeTargetUuid: nil,
                mergeTargetTitle: nil
            ))
        }

        return groups
    }

    // MARK: - Per-Item Insights

    /// Generates one-line insights for high-confidence classified items.
    /// Uses Gemini Flash-Lite for speed. Batches up to 10 items per call.
    /// Returns only NEW insights (skips previously generated ones).
    func generateInsights(items: [InboxItem]) async -> [String: String] {
        let candidates = items.filter {
            $0.confidence > 0.5 &&
            $0.classification != nil &&
            !cachedInsightUUIDs.contains($0.uuid)
        }

        guard !candidates.isEmpty else { return [:] }

        let batch = Array(candidates.prefix(10))
        var results: [String: String] = [:]

        let itemDescriptions = batch.map { item -> String in
            let classType = item.classification?.rawValue ?? "unknown"
            let target = item.mergeTargetTitle ?? item.placeThinkspaceName ?? "new atom"
            return "UUID: \(item.uuid) | Text: \(String(item.rawText.prefix(200))) | Action: \(classType) \u{2192} \(target)"
        }.joined(separator: "\n---\n")

        let prompt = """
        For each inbox item below, write ONE concise sentence (max 15 words) explaining \
        why the suggested action makes sense based on the content. \
        Return JSON: {"insights": [{"uuid": "...", "insight": "..."}]}

        \(itemDescriptions)
        """

        do {
            let response = try await ResearchService.shared.analyze(
                prompt: prompt,
                systemPrompt: "You generate concise insight sentences. Return ONLY valid JSON.",
                model: "google/gemini-3.1-flash-lite-preview",
                maxTokens: 1024,
                temperature: 0.0
            )

            // Strip markdown code fences if present
            let cleaned = response
                .replacingOccurrences(of: "```json\n", with: "")
                .replacingOccurrences(of: "```\n", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let data = cleaned.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let insights = json["insights"] as? [[String: String]] {
                for entry in insights {
                    if let uuid = entry["uuid"], let insight = entry["insight"] {
                        results[uuid] = insight
                        cachedInsightUUIDs.insert(uuid)
                    }
                }
            }
        } catch {
            // Insights are non-critical — silently fail
        }

        return results
    }

    /// Clear caches when items change significantly
    func invalidateCache() {
        cachedGroupHash = 0
        cachedInsightUUIDs.removeAll()
    }
}
