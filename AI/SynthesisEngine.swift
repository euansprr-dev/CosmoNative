// CosmoOS/AI/SynthesisEngine.swift
// AI-powered synthesis of multiple source atoms into unified understanding

import SwiftUI

@MainActor
class SynthesisEngine: ObservableObject {
    @Published var result: LassoSynthesisResult?
    @Published var isGenerating = false

    private let researchService = ResearchService.shared
    private let model = "anthropic/claude-haiku-4-5-20251001"

    func synthesize(atoms: [Atom]) async -> LassoSynthesisResult {
        guard !atoms.isEmpty else {
            return LassoSynthesisResult()
        }

        isGenerating = true
        defer { isGenerating = false }

        // Build source content from atoms
        var sourceDescriptions: [String] = []
        for (index, atom) in atoms.enumerated() {
            let title = atom.title ?? "Untitled"
            let body = atom.body ?? ""
            let typeLabel = atom.type.rawValue.capitalized
            sourceDescriptions.append("""
            [Source \(index + 1): \(typeLabel)] "\(title)"
            \(body.prefix(2000))
            """)
        }

        let sourceBlock = sourceDescriptions.joined(separator: "\n\n---\n\n")
        let atomUUIDs = atoms.compactMap { $0.uuid }

        let systemPrompt = """
        You are a knowledge synthesis engine. Given multiple source blocks from a user's knowledge base, \
        you identify patterns, combine insights, and produce a unified synthesis.

        Respond ONLY with valid JSON matching this schema:
        {
          "themes": ["theme1", "theme2", ...],
          "synthesizedArgument": "A coherent 2-4 paragraph argument combining insights from all sources...",
          "openQuestions": ["question1", "question2", ...],
          "suggestedTitle": "A concise title for this synthesis",
          "evidenceSpans": [
            {
              "sourceIndex": 0,
              "excerpt": "quoted text from source",
              "claim": "the claim this excerpt supports"
            }
          ]
        }

        Rules:
        - Identify 3-5 common themes across all sources
        - Write a synthesized argument that combines insights — do not just summarize each source separately
        - List 2-4 open questions the sources raise but don't answer
        - For each major claim in your synthesis, cite which source it draws from with a short excerpt
        - sourceIndex is 0-based, matching the order of sources provided
        """

        let userMessage = """
        Synthesize these \(atoms.count) knowledge blocks:

        \(sourceBlock)
        """

        do {
            let response = try await researchService.generateWithCaching(
                systemBlocks: [(content: systemPrompt, cacheControl: false)],
                messages: [["role": "user", "content": userMessage]],
                model: model,
                maxTokens: 4096,
                temperature: 0.4
            )

            let parsed = parseSynthesisResponse(response, atomUUIDs: atomUUIDs)
            self.result = parsed
            return parsed
        } catch {
            print("SynthesisEngine: Generation failed — \(error)")
            let fallback = LassoSynthesisResult(
                synthesizedArgument: "Synthesis generation failed: \(error.localizedDescription)",
                sourceAtomUUIDs: atomUUIDs
            )
            self.result = fallback
            return fallback
        }
    }

    // MARK: - Parse Response

    private func parseSynthesisResponse(_ raw: String, atomUUIDs: [String]) -> LassoSynthesisResult {
        // Extract JSON from response (may be wrapped in markdown code fences)
        let jsonString: String
        if let start = raw.range(of: "{"), let end = raw.range(of: "}", options: .backwards) {
            jsonString = String(raw[start.lowerBound...end.upperBound])
        } else {
            jsonString = raw
        }

        guard let data = jsonString.data(using: .utf8) else {
            return LassoSynthesisResult(
                synthesizedArgument: raw,
                sourceAtomUUIDs: atomUUIDs
            )
        }

        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

            let themes = json["themes"] as? [String] ?? []
            let argument = json["synthesizedArgument"] as? String ?? raw
            let questions = json["openQuestions"] as? [String] ?? []
            let title = json["suggestedTitle"] as? String ?? "Synthesis"

            // Parse evidence spans
            var evidenceSpans: [LassoEvidenceSpan] = []
            if let rawSpans = json["evidenceSpans"] as? [[String: Any]] {
                for span in rawSpans {
                    let sourceIndex = span["sourceIndex"] as? Int ?? 0
                    let excerpt = span["excerpt"] as? String ?? ""
                    let claim = span["claim"] as? String ?? ""
                    let sourceUUID = sourceIndex < atomUUIDs.count ? atomUUIDs[sourceIndex] : ""
                    evidenceSpans.append(LassoEvidenceSpan(
                        sourceAtomUUID: sourceUUID,
                        excerpt: excerpt,
                        claim: claim
                    ))
                }
            }

            return LassoSynthesisResult(
                themes: themes,
                synthesizedArgument: argument,
                openQuestions: questions,
                suggestedTitle: title,
                evidenceSpans: evidenceSpans,
                sourceAtomUUIDs: atomUUIDs
            )
        } catch {
            return LassoSynthesisResult(
                synthesizedArgument: raw,
                sourceAtomUUIDs: atomUUIDs
            )
        }
    }
}
