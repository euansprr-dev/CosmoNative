// CosmoOS/AI/ConnectionCoDevEngine+LiveInsights.swift
// April 2026 — Connection Focus Mode V2 "The Crucible"
//
// Rolling AI observations for The Atelier's Live Insights surface. Kinds:
// tension, gap, echo, strength, contradiction. Called whenever the user adds
// an item or crosses a maturity threshold. Fast tier model — these are
// meant to feel ambient, not ponderous.

import Foundation

extension ConnectionCoDevEngine {

    /// Generate 3–6 live observations about the current framework state.
    /// Returns an empty array on any failure — this feature is best-effort.
    func generateLiveInsights(
        state: ConnectionFocusModeState,
        conceptType: ConceptFrameworkType,
        frameworkTitle: String
    ) async -> [LiveInsight] {
        // Require at least 2 populated sections — with less, observations are noise.
        let populated = state.sections.filter { !$0.items.isEmpty }
        guard populated.count >= 2 else { return [] }

        let prompt = buildInsightsPrompt(
            title: frameworkTitle,
            conceptType: conceptType,
            populated: populated
        )

        do {
            let response = try await ResearchService.shared.analyze(
                prompt: prompt,
                tier: .sensor,
                maxTokens: 700
            )
            return parseInsights(response)
        } catch {
            return []
        }
    }

    // MARK: - Prompt

    private func buildInsightsPrompt(
        title: String,
        conceptType: ConceptFrameworkType,
        populated: [ConnectionSection]
    ) -> String {
        var body = ""
        for section in populated {
            let items = section.items.prefix(5).map { "  - \($0.plainText ?? $0.content)" }.joined(separator: "\n")
            body += "## \(section.type.displayName)\n\(items)\n\n"
        }

        return """
        You are the Live Insights engine for a framework-in-progress. You observe \
        the current state and return 3-6 short, specific observations.

        Framework: "\(title)" (\(conceptType.displayName))
        \(body)

        Return a JSON array. Each object has:
          "kind": one of "tension" | "gap" | "echo" | "strength" | "contradiction"
          "message": 1 sentence, ≤ 22 words. Name sections by their display name in CAPS.
          "sections": array of 0-3 section display names involved.

        Bias toward "tension" and "contradiction" when sections disagree.
        Bias toward "gap" when a section logically implies content in another that is empty.
        Use "echo" only when this resembles a known framework — name the framework.
        Use "strength" sparingly — only for unusually sharp or original moves.

        Return ONLY the JSON array, no preamble. Example:
        [{"kind":"tension","message":"PROCESS assumes willingness, but BELIEFS lists resistance as the primary blocker.","sections":["Process","Beliefs & Objections"]}]
        """
    }

    // MARK: - Parse

    private func parseInsights(_ raw: String) -> [LiveInsight] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "[") else { return [] }
        let jsonSlice = String(trimmed[start...])
        guard let data = jsonSlice.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        var sectionsByDisplay: [String: ConnectionSectionType] = [:]
        for type in ConnectionSectionType.allCases {
            sectionsByDisplay[type.displayName.lowercased()] = type
        }

        return root.compactMap { entry in
            guard let kindRaw = entry["kind"] as? String,
                  let kind = LiveInsight.Kind(rawValue: kindRaw),
                  let message = entry["message"] as? String,
                  !message.isEmpty
            else { return nil }

            let sectionsInput = entry["sections"] as? [String] ?? []
            let relatedSections = sectionsInput.compactMap { sectionsByDisplay[$0.lowercased()] }

            return LiveInsight(
                id: UUID(),
                kind: kind,
                message: message,
                relatedSections: relatedSections,
                createdAt: Date()
            )
        }
    }
}
