// CosmoOS/AI/InquiryCrystallizationEngine.swift
// Synthesizes a CrystallizationOutput from an Inquiry Session: summary, lexicon candidates,
// new questions, model updates, contradictions, open loops, output candidates,
// Thinkspace map proposals, promotion suggestions.
//
// V1 strategy: condense session events (captures + extracts + AI interactions + tree path)
// into a structured prompt and ask Sonnet (via ResearchService) to return JSON. Falls back
// to a heuristic synthesis when offline or LLM fails.
//
// Naming: distinct from existing /AI/CrystallizationEngine.swift to avoid collision.

import Foundation

@MainActor
final class InquiryCrystallizationEngine {
    static let shared = InquiryCrystallizationEngine()
    private init() {}

    /// Crystallize a session. Returns the resulting CrystallizationOutput. Throws on hard failure.
    func crystallize(session: Atom, deepDive: Atom?, allExtracts: [Atom]) async throws -> CrystallizationOutput {
        let prompt = buildPrompt(session: session, deepDive: deepDive, extracts: allExtracts)
        let systemPrompt = """
        You are Cosmo's Crystallization Engine. You synthesize a research session into structured knowledge.
        ALWAYS respond with VALID JSON matching this schema:
        {
          "summary": "<3-paragraph synopsis>",
          "lexiconCandidates": [{"term":"<word>","definition":"<one-paragraph>","mentionCount":<int>}],
          "newQuestions": [{"text":"<question>","rationale":"<why>"}],
          "possibleConnections": [{"name":"<concept>","rationale":"<why>"}],
          "modelUpdates": [{"kind":"small|section|breakthrough|contradiction","before":"<text>","after":"<text>","rationale":"<why>"}],
          "contradictions": [{"description":"<what conflicts>"}],
          "openLoops": [{"description":"<unresolved>", "suggestedNextStep":"<optional>"}],
          "outputCandidates": [{"title":"<headline>","format":"carousel|reel|thread|essay|framework","rationale":"<why>"}],
          "thinkspaceMapProposals": [],
          "promotionSuggestions": []
        }
        Be precise, specific, and ground every claim in the session content. Empty arrays are fine.
        Do not invent extracts. Do not include any prose outside the JSON.
        """
        do {
            let raw = try await ResearchService.shared.analyze(
                prompt: prompt,
                systemPrompt: systemPrompt,
                tier: .strategist
            )
            if let output = parse(raw: raw) {
                return output
            }
            return heuristicFallback(session: session, deepDive: deepDive, extracts: allExtracts)
        } catch {
            print("[InquiryCrystallizationEngine] LLM failed: \(error) — falling back to heuristic")
            return heuristicFallback(session: session, deepDive: deepDive, extracts: allExtracts)
        }
    }

    // MARK: - Prompt building

    private func buildPrompt(session: Atom, deepDive: Atom?, extracts: [Atom]) -> String {
        var lines: [String] = []
        if let dd = deepDive {
            lines.append("Deep Dive: \(dd.title ?? "Untitled")")
            if let body = dd.body, !body.isEmpty { lines.append("About: \(body)") }
            if let model = dd.deepDiveStructured?.currentUnderstanding.oneSentenceModel, !model.isEmpty {
                lines.append("Current understanding (one-sentence model): \(model)")
            }
        }
        lines.append("\nSession: \(session.title ?? "Untitled")")
        if let metadata = session.inquirySessionMetadata {
            lines.append("Status entering crystallization: \(metadata.status.rawValue)")
        }

        let structured = session.inquirySessionStructured

        // Captures
        if let captures = structured?.sessionCaptures, !captures.isEmpty {
            lines.append("\nSession Captures (most recent 30):")
            for cap in captures.suffix(30) {
                let kind = cap.suggestedKind?.rawValue ?? "?"
                lines.append("- [\(kind)] \(cap.body.prefix(240))")
            }
        }

        // Extracts (committed)
        if !extracts.isEmpty {
            lines.append("\nCommitted Extracts (most recent 30):")
            for ex in extracts.suffix(30) {
                let kind = ex.extractMetadata?.kind.rawValue ?? "extract"
                let body = ex.body ?? ex.title ?? ""
                lines.append("- [\(kind)] \(body.prefix(240))")
            }
        }

        // AI interactions
        if let interactions = structured?.aiInteractions, !interactions.isEmpty {
            lines.append("\nAI Conversations (last 6 exchanges):")
            for interaction in interactions.suffix(6) {
                lines.append("Q: \(interaction.prompt.prefix(200))")
                lines.append("A: \(interaction.response.prefix(400))")
            }
        }

        // Tree summary (just kinds + labels)
        if let tree = structured?.researchTree {
            lines.append("\nResearch Tree (path):")
            walkTree(tree: tree, nodeId: tree.rootNodeId, depth: 0, into: &lines, limit: 40)
        }

        lines.append("\n---\nSynthesize this session into the JSON schema described in the system prompt.")
        return lines.joined(separator: "\n")
    }

    private func walkTree(tree: ResearchTreeDocument, nodeId: String, depth: Int, into lines: inout [String], limit: Int) {
        guard lines.count < limit + 80, let node = tree.nodes[nodeId] else { return }
        let indent = String(repeating: "  ", count: depth)
        let label = node.meta.label?.prefix(120) ?? Substring(node.kind.rawValue)
        lines.append("\(indent)- [\(node.kind.rawValue)] \(label)")
        for childId in node.childNodeIds {
            walkTree(tree: tree, nodeId: childId, depth: depth + 1, into: &lines, limit: limit)
        }
    }

    // MARK: - Parsing

    private func parse(raw: String) -> CrystallizationOutput? {
        // Extract JSON substring (LLMs sometimes wrap in markdown fences)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped: String
        if trimmed.hasPrefix("```") {
            // Drop first line and trailing fence
            let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
            let inner = lines.dropFirst().dropLast().joined(separator: "\n")
            stripped = inner
        } else {
            stripped = trimmed
        }
        guard let data = stripped.data(using: .utf8) else { return nil }
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        var output = CrystallizationOutput()
        output.summary = (dict["summary"] as? String) ?? ""

        if let arr = dict["lexiconCandidates"] as? [[String: Any]] {
            output.lexiconCandidates = arr.compactMap { lc in
                guard let term = lc["term"] as? String else { return nil }
                let def = lc["definition"] as? String ?? ""
                let count = (lc["mentionCount"] as? Int) ?? 1
                return CrystallizationOutput.LexiconCandidate(term: term, definition: def, mentionCount: count)
            }
        }
        if let arr = dict["newQuestions"] as? [[String: Any]] {
            output.newQuestions = arr.compactMap { q in
                guard let text = q["text"] as? String else { return nil }
                return CrystallizationOutput.QuestionCandidate(text: text, rationale: q["rationale"] as? String)
            }
        }
        if let arr = dict["possibleConnections"] as? [[String: Any]] {
            output.possibleConnections = arr.compactMap { c in
                guard let name = c["name"] as? String else { return nil }
                return CrystallizationOutput.ConnectionCandidate(name: name, rationale: c["rationale"] as? String)
            }
        }
        if let arr = dict["modelUpdates"] as? [[String: Any]] {
            output.modelUpdates = arr.compactMap { m in
                guard let before = m["before"] as? String, let after = m["after"] as? String else { return nil }
                let kindRaw = (m["kind"] as? String) ?? "small"
                let kind = ModelUpdate.Kind(rawValue: kindRaw) ?? .small
                return CrystallizationOutput.ModelUpdateProposal(kind: kind, before: before, after: after, rationale: m["rationale"] as? String)
            }
        }
        if let arr = dict["contradictions"] as? [[String: Any]] {
            output.contradictions = arr.compactMap { c in
                guard let desc = c["description"] as? String else { return nil }
                return CrystallizationOutput.ContradictionAlert(description: desc)
            }
        }
        if let arr = dict["openLoops"] as? [[String: Any]] {
            output.openLoops = arr.compactMap { l in
                guard let desc = l["description"] as? String else { return nil }
                return CrystallizationOutput.OpenLoop(description: desc, suggestedNextStep: l["suggestedNextStep"] as? String)
            }
        }
        if let arr = dict["outputCandidates"] as? [[String: Any]] {
            output.outputCandidates = arr.compactMap { o in
                guard let title = o["title"] as? String, let format = o["format"] as? String else { return nil }
                return CrystallizationOutput.OutputCandidate(title: title, format: format, rationale: o["rationale"] as? String)
            }
        }
        return output
    }

    // MARK: - Heuristic fallback

    private func heuristicFallback(session: Atom, deepDive: Atom?, extracts: [Atom]) -> CrystallizationOutput {
        var output = CrystallizationOutput()
        output.summary = "Session captured \(extracts.count) extracts. Cosmo is offline; review captures manually below."
        // Promote any session capture suggested as a term into a lexicon candidate
        if let captures = session.inquirySessionStructured?.sessionCaptures {
            output.lexiconCandidates = captures
                .filter { $0.suggestedKind == .term && $0.status == .pending }
                .map { CrystallizationOutput.LexiconCandidate(term: String($0.body.prefix(80)), definition: "", mentionCount: 1) }
        }
        // Open loops = pending captures that look like questions
        let pendingQuestions = (session.inquirySessionStructured?.sessionCaptures ?? [])
            .filter { $0.suggestedKind == .question || $0.body.hasSuffix("?") }
        output.openLoops = pendingQuestions.map { CrystallizationOutput.OpenLoop(description: $0.body) }
        return output
    }

    // MARK: - Apply accepted output to atoms

    /// Commits the accepted items in `output` to atoms + Deep Dive structure. Returns counts of each.
    @discardableResult
    func applyAcceptedOutput(
        _ output: CrystallizationOutput,
        toSession session: Atom,
        deepDive: Atom?
    ) async throws -> AppliedSummary {
        var summary = AppliedSummary()
        guard let dd = deepDive else { return summary }

        // 1. Lexicon entries
        for candidate in output.lexiconCandidates where candidate.accepted {
            do {
                _ = try await InquiryRepository.shared.createLexiconEntry(
                    term: candidate.term,
                    definition: candidate.definition,
                    parentDeepDiveUUID: dd.uuid
                )
                summary.lexiconCreated += 1
            } catch {
                print("[InquiryCrystallizationEngine] lexicon create failed: \(error)")
            }
        }

        // 2. New questions
        for q in output.newQuestions where q.accepted {
            do {
                _ = try await InquiryRepository.shared.createQuestion(
                    title: q.text,
                    parentDeepDiveUUID: dd.uuid,
                    originSessionUUID: session.uuid,
                    parentQuestionUUID: nil,
                    originExtractUUID: nil
                )
                summary.questionsCreated += 1
            } catch {
                print("[InquiryCrystallizationEngine] question create failed: \(error)")
            }
        }

        // 3. Model updates → patch Current Understanding
        if !output.modelUpdates.isEmpty {
            var ddCopy = dd
            var structured = ddCopy.deepDiveStructured ?? DeepDiveStructured()
            for update in output.modelUpdates where update.accepted {
                if update.kind == .breakthrough || update.kind == .section {
                    structured.currentUnderstanding.oneSentenceModel = update.after
                }
                let logged = ModelUpdate(
                    date: ISO8601DateFormatter().string(from: Date()),
                    kind: update.kind,
                    before: update.before,
                    after: update.after,
                    evidence: update.evidence,
                    sessionUUID: session.uuid,
                    acceptedBy: .user
                )
                structured.currentUnderstanding.recentUpdates.append(logged)
                structured.currentUnderstanding.lastUpdated = ISO8601DateFormatter().string(from: Date())
                summary.modelUpdatesApplied += 1
            }
            ddCopy = ddCopy.withStructured(structured)
            // Bump Deep Dive maturity if a breakthrough was accepted
            if output.modelUpdates.contains(where: { $0.accepted && $0.kind == .breakthrough }) {
                var ddMeta = ddCopy.deepDiveMetadata ?? DeepDiveMetadata()
                ddMeta.maturity = .evolving
                ddCopy = ddCopy.withMetadata(ddMeta)
            }
            do {
                _ = try await AtomRepository.shared.update(ddCopy)
            } catch {
                print("[InquiryCrystallizationEngine] DeepDive update failed: \(error)")
            }
        }

        // 4. Output candidates → seed OutputAngle records on the Deep Dive
        if !output.outputCandidates.isEmpty {
            if let fresh = try? await AtomRepository.shared.fetch(uuid: dd.uuid) {
                var ddCopy = fresh
                var structured = ddCopy.deepDiveStructured ?? DeepDiveStructured()
                for o in output.outputCandidates where o.accepted {
                    structured.outputAngles.append(OutputAngle(
                        title: o.title,
                        format: o.format,
                        rationale: o.rationale,
                        sourceExtractUUIDs: o.sourceExtractUUIDs
                    ))
                    summary.outputAnglesAdded += 1
                }
                ddCopy = ddCopy.withStructured(structured)
                _ = try? await AtomRepository.shared.update(ddCopy)
            }
        }

        return summary
    }

    struct AppliedSummary {
        var lexiconCreated: Int = 0
        var questionsCreated: Int = 0
        var modelUpdatesApplied: Int = 0
        var outputAnglesAdded: Int = 0
    }
}
