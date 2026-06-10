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
        // Concept routing is independent of the synthesis text — resolve it
        // concurrently with the synthesis call instead of after it.
        async let projectionContext = loadProjectionContext(session: session, deepDive: deepDive, extracts: allExtracts)
        var output: CrystallizationOutput
        do {
            let raw = try await ResearchService.shared.analyze(
                prompt: prompt,
                systemPrompt: systemPrompt,
                tier: .strategist
            )
            output = parse(raw: raw) ?? heuristicFallback(session: session, deepDive: deepDive, extracts: allExtracts)
        } catch {
            print("[InquiryCrystallizationEngine] LLM failed: \(error) — falling back to heuristic")
            output = heuristicFallback(session: session, deepDive: deepDive, extracts: allExtracts)
        }
        return await attachCanvasProjection(to: output, session: session, deepDive: deepDive, extracts: allExtracts, context: projectionContext)
    }

    /// Everything the canvas projection needs that does not depend on the synthesis
    /// output: Deep Dive scoped atoms plus concept assignments for the extracts.
    private struct ProjectionContext: Sendable {
        var questions: [Atom] = []
        var lexicon: [Atom] = []
        var connections: [Atom] = []
        var sources: [Atom] = []
        var assignments: [ConceptResolver.ConceptAssignment] = []
    }

    private func loadProjectionContext(session: Atom, deepDive: Atom?, extracts: [Atom]) async -> ProjectionContext {
        var context = ProjectionContext()
        if let deepDive {
            context.questions = (try? await InquiryRepository.shared.fetchQuestions(forDeepDive: deepDive.uuid)) ?? []
            context.lexicon = (try? await InquiryRepository.shared.fetchLexicon(forDeepDive: deepDive.uuid)) ?? []
            context.connections = (try? await InquiryRepository.shared.fetchConnections(forDeepDive: deepDive)) ?? []
            context.sources = (try? await InquiryRepository.shared.fetchSources(forDeepDive: deepDive)) ?? []
        }
        context.assignments = await ConceptResolver.shared.resolve(ConceptResolver.Input(
            deepDive: deepDive,
            session: session,
            extracts: extracts,
            lexicon: context.lexicon,
            existingConnections: context.connections,
            questions: context.questions
        ))
        return context
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

    // MARK: - Canvas mapping proposal

    private func attachCanvasProjection(
        to output: CrystallizationOutput,
        session: Atom,
        deepDive: Atom?,
        extracts: [Atom],
        context: ProjectionContext
    ) async -> CrystallizationOutput {
        var copy = output
        let sourceRefs = session.inquirySessionStructured?.sourceRefs ?? []
        let branchNodes = session.inquirySessionStructured
            .map { Array($0.researchTree.nodes.values) } ?? []

        // Concept-first: the context carries durable concept assignments (persisted
        // capture-time tags, LLM for the untagged remainder), so propose one
        // Connection per concept with explicit merge targets. Falls back to
        // per-branch proposals when nothing resolved.
        if context.assignments.isEmpty {
            copy.possibleConnections = await ConnectionRoutingEngine().proposals(
                forSession: session,
                branches: branchNodes,
                extracts: extracts,
                sources: sourceRefs
            )
        } else {
            copy.possibleConnections = await ConnectionRoutingEngine().proposals(
                forSession: session,
                assignments: context.assignments,
                extracts: extracts,
                sources: sourceRefs
            )
        }

        guard let deepDive,
              let thinkspaceUUID = deepDive.deepDiveMetadata?.primaryThinkspaceUUID
                ?? deepDive.deepDiveMetadata?.parentThinkspaceUUIDs?.first else {
            return copy
        }

        let operations = buildCanvasOperations(
            output: copy,
            session: session,
            deepDive: deepDive,
            thinkspaceUUID: thinkspaceUUID,
            extracts: extracts,
            questions: context.questions,
            sources: context.sources,
            connections: context.connections,
            sourceRefs: sourceRefs
        )

        let projection = CanvasProjection(
            sessionUUID: session.uuid,
            deepDiveProfileUUID: deepDive.uuid,
            thinkspaceUUID: thinkspaceUUID,
            summary: "Map this inquiry session into \(deepDive.title ?? "this Thinkspace") with append-first, non-destructive operations.",
            operations: operations,
            verificationReport: verificationReport(for: operations),
            rollbackSnapshot: CanvasProjectionRollbackSnapshot(
                canvasBlockUUIDs: [],
                clusterUUIDs: operations.compactMap(\.targetClusterUUID),
                atomUUIDs: Array(Set(operations.compactMap(\.targetObjectUUID) + [deepDive.uuid, session.uuid])),
                summary: "Snapshot before applying \(operations.count) proposed canvas operations."
            )
        )
        copy.canvasProjection = projection
        return copy
    }

    private func buildCanvasOperations(
        output: CrystallizationOutput,
        session: Atom,
        deepDive: Atom,
        thinkspaceUUID: String,
        extracts: [Atom],
        questions: [Atom],
        sources: [Atom],
        connections: [Atom],
        sourceRefs: [InquirySourceRef]
    ) -> [CanvasOperation] {
        var operations: [CanvasOperation] = []
        let clusterName = proposedClusterName(output: output, session: session)
        let existingCluster = existingClusterMatch(named: clusterName, thinkspaceUUID: thinkspaceUUID)
        let clusterOperationId = UUID().uuidString
        let proposedClusterUUID = existingCluster ?? clusterOperationId

        if existingCluster == nil, shouldCreateCluster(named: clusterName, output: output, extracts: extracts, sourceRefs: sourceRefs) {
            operations.append(CanvasOperation(
                id: clusterOperationId,
                type: .createCluster,
                sourceArtifactID: session.uuid,
                targetThinkspaceUUID: thinkspaceUUID,
                targetClusterUUID: proposedClusterUUID,
                proposedObjectType: "cluster",
                proposedTitle: clusterName,
                proposedPlacement: CanvasPlacementProposal(x: 0, y: 0, width: 760, height: 520, placementRationale: "Create a broad field for the session's main theme."),
                rationale: "Several session artifacts share the theme \(clusterName). A cluster groups them without scattering small notes.",
                confidence: 0.76,
                appendCreateRecommendation: .create,
                rollbackMetadata: CanvasRollbackMetadata(affectedClusterUUIDs: [proposedClusterUUID]),
                visualMaturity: .conceptCardOrConnection
            ))
        }

        let uniqueSourceRefs = uniqueSources(from: sourceRefs, extracts: extracts, sources: sources)
        for (index, source) in uniqueSourceRefs.enumerated() {
            operations.append(sourceCardOperation(
                source: source,
                index: index,
                thinkspaceUUID: thinkspaceUUID,
                clusterUUID: proposedClusterUUID,
                existingSources: sources
            ))
        }

        for (index, question) in output.newQuestions.enumerated() where !question.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let duplicate = duplicateQuestionCheck(question.text, questions: questions)
            let isDuplicate = duplicate.verdict == .likelyDuplicate || duplicate.verdict == .exactMatch
            operations.append(CanvasOperation(
                type: isDuplicate ? .appendToObject : .createObject,
                sourceArtifactID: question.id,
                targetThinkspaceUUID: thinkspaceUUID,
                targetObjectUUID: duplicate.matchedObjectUUID,
                targetClusterUUID: proposedClusterUUID,
                proposedObjectType: AtomType.question.rawValue,
                proposedTitle: question.text,
                proposedBody: question.rationale,
                proposedPlacement: CanvasPlacementProposal(x: -260 + Double(index * 260), y: -40, width: 280, height: 180, clusterUUID: proposedClusterUUID),
                rationale: question.rationale ?? "Promote this question because it opens a durable inquiry path for the Thinkspace.",
                confidence: isDuplicate ? 0.68 : 0.72,
                alternatives: [
                    CanvasOperationAlternative(label: "Keep internal under session", operationType: .hideArtifact, rationale: "Use this if the question is not yet important enough for the canvas.")
                ],
                duplicateCheckResult: duplicate,
                appendCreateRecommendation: isDuplicate ? .append : .create,
                rollbackMetadata: CanvasRollbackMetadata(affectedAtomUUIDs: [duplicate.matchedObjectUUID].compactMap { $0 }),
                visualMaturity: .claimQuestionOrTerm
            ))
        }

        for (index, candidate) in output.possibleConnections.enumerated() where candidate.accepted {
            let duplicate = duplicateConnectionCheck(candidate.proposedTitle, connections: connections)
            let filledSections = candidate.proposedSections.values.filter { !$0.isEmpty }.count
            operations.append(CanvasOperation(
                type: .promoteToConnection,
                sourceArtifactID: candidate.id,
                targetThinkspaceUUID: thinkspaceUUID,
                targetObjectUUID: duplicate.matchedObjectUUID,
                targetClusterUUID: proposedClusterUUID,
                proposedObjectType: AtomType.connection.rawValue,
                proposedTitle: candidate.proposedTitle,
                proposedBody: "\(candidate.materialCount) routed items across \(filledSections) sections.",
                proposedPlacement: CanvasPlacementProposal(
                    x: -40 + Double(index * 320),
                    y: 180,
                    width: 320,
                    height: 220,
                    clusterUUID: proposedClusterUUID,
                    placementRationale: "Promote the branch as one browsable Connection card."
                ),
                relationshipType: "branch_connection",
                rationale: candidate.rationale ?? "Promote this branch as a Connection so captures stay organized around the user's question.",
                confidence: duplicate.verdict == .exactMatch ? 0.7 : 0.82,
                alternatives: [
                    CanvasOperationAlternative(label: "Skip this Connection", operationType: .ignore),
                    CanvasOperationAlternative(label: "Keep branch internal", operationType: .hideArtifact)
                ],
                duplicateCheckResult: duplicate,
                appendCreateRecommendation: duplicate.verdict == .exactMatch ? .append : .promote,
                rollbackMetadata: CanvasRollbackMetadata(affectedAtomUUIDs: [duplicate.matchedObjectUUID].compactMap { $0 }),
                visualMaturity: .conceptCardOrConnection
            ))
        }

        for update in output.modelUpdates {
            operations.append(CanvasOperation(
                type: .updateCurrentUnderstanding,
                sourceArtifactID: update.id,
                targetThinkspaceUUID: thinkspaceUUID,
                targetObjectUUID: deepDive.uuid,
                proposedObjectType: "current_understanding",
                proposedTitle: "Current Understanding",
                proposedBody: update.after,
                rationale: update.rationale ?? "Append this as a reviewed update to the Thinkspace's living model.",
                confidence: 0.74,
                alternatives: [
                    CanvasOperationAlternative(label: "Append as alternate", operationType: .appendToObject, targetObjectUUID: deepDive.uuid),
                    CanvasOperationAlternative(label: "Reject model update", operationType: .ignore)
                ],
                appendCreateRecommendation: .append,
                rollbackMetadata: CanvasRollbackMetadata(affectedAtomUUIDs: [deepDive.uuid]),
                visualMaturity: .deepDiveProfile
            ))
        }

        let lowSignalExtracts = extracts.filter { extract in
            guard let kind = extract.extractMetadata?.kind else { return false }
            let body = extract.body ?? extract.title ?? ""
            return [.quote, .highlight, .sourceSnippet, .note].contains(kind) && body.count < 240
        }
        for extract in lowSignalExtracts.prefix(6) {
            operations.append(CanvasOperation(
                type: .hideArtifact,
                sourceArtifactID: extract.uuid,
                targetThinkspaceUUID: thinkspaceUUID,
                targetObjectUUID: extract.uuid,
                proposedObjectType: AtomType.extract.rawValue,
                proposedTitle: makeCardTitle(from: extract.body ?? extract.title ?? "Extract"),
                rationale: "Keep this extract internal because it supports the session but does not yet earn standalone visual space.",
                confidence: 0.82,
                duplicateCheckResult: CanvasDuplicateCheckResult(verdict: .noneFound, explanation: "Internal artifacts do not require visual duplicate creation."),
                appendCreateRecommendation: .keepInternal,
                status: .accepted,
                rollbackMetadata: CanvasRollbackMetadata(affectedAtomUUIDs: [extract.uuid]),
                visualMaturity: .rawCapture,
                requiresReview: false
            ))
        }

        if shouldSuggestChildThinkspace(output: output, extracts: extracts, sourceRefs: sourceRefs, questions: questions) {
            operations.append(CanvasOperation(
                type: .promoteToChildThinkspace,
                sourceArtifactID: session.uuid,
                targetThinkspaceUUID: thinkspaceUUID,
                proposedObjectType: AtomType.thinkspace.rawValue,
                proposedTitle: clusterName,
                rationale: "\(clusterName) is becoming a large subtopic. Suggest a child Thinkspace while preserving this parent as a portal/summary.",
                confidence: 0.55,
                appendCreateRecommendation: .promote,
                visualMaturity: .childThinkspace
            ))
        }

        return operations
    }

    private func verificationReport(for operations: [CanvasOperation]) -> CanvasProjectionVerificationReport {
        CanvasProjectionVerificationReport(
            duplicateChecksPassed: !operations.contains { $0.duplicateCheckResult.verdict == .exactMatch && $0.appendCreateRecommendation == .create },
            appendCreateChecksPassed: !operations.contains { $0.appendCreateRecommendation == .review },
            ambiguityWarnings: operations.filter { $0.confidence < 0.6 }.map { "\($0.type.displayName): \($0.rationale)" },
            blockedOperationIds: operations.filter { $0.status == .blocked }.map(\.id)
        )
    }

    private func uniqueSources(from refs: [InquirySourceRef], extracts: [Atom], sources: [Atom]) -> [InquirySourceRef] {
        var seen = Set<String>()
        var result: [InquirySourceRef] = []
        for ref in refs where !seen.contains(ref.sourceUUID) {
            seen.insert(ref.sourceUUID)
            result.append(ref)
        }
        for source in sources where !seen.contains(source.uuid) {
            seen.insert(source.uuid)
            result.append(InquirySourceRef(
                sourceUUID: source.uuid,
                url: source.researchMetadata?.url,
                title: source.title ?? "Untitled Source",
                domain: URL(string: source.researchMetadata?.url ?? "")?.host,
                sourceType: source.researchMetadata?.researchType ?? "research",
                status: InquirySourceStatus(rawValue: source.researchMetadata?.processingStatus ?? "") ?? .saved,
                extractCount: extracts.filter { $0.extractMetadata?.sourceUUID == source.uuid }.count,
                noteCount: extracts.filter { $0.extractMetadata?.sourceUUID == source.uuid && $0.extractMetadata?.kind == .note }.count
            ))
        }
        return result
    }

    private func sourceCardOperation(
        source: InquirySourceRef,
        index: Int,
        thinkspaceUUID: String,
        clusterUUID: String,
        existingSources: [Atom]
    ) -> CanvasOperation {
        let duplicate = existingSourceCheck(source, existingSources: existingSources)
        return CanvasOperation(
            type: .createSourceCard,
            sourceArtifactID: source.sourceUUID,
            targetThinkspaceUUID: thinkspaceUUID,
            targetObjectUUID: source.sourceUUID,
            targetClusterUUID: clusterUUID,
            proposedObjectType: AtomType.research.rawValue,
            proposedTitle: source.title,
            proposedBody: [source.domain, source.sourceType, "\(source.extractCount) extracts"].compactMap { $0 }.joined(separator: " · "),
            proposedPlacement: CanvasPlacementProposal(x: -320 + Double(index * 260), y: 160, width: 320, height: 220, clusterUUID: clusterUUID),
            rationale: "Create a source card as the durable visual handle for this material; extracts remain attached internally.",
            confidence: 0.78,
            alternatives: [
                CanvasOperationAlternative(label: "Keep source in library only", operationType: .hideArtifact, targetObjectUUID: source.sourceUUID)
            ],
            duplicateCheckResult: duplicate,
            appendCreateRecommendation: duplicate.verdict == .existingAppearance ? .link : .create,
            rollbackMetadata: CanvasRollbackMetadata(affectedAtomUUIDs: [source.sourceUUID]),
            visualMaturity: .sourceCard
        )
    }

    private func proposedClusterName(output: CrystallizationOutput, session: Atom) -> String {
        let haystack = [
            session.title ?? "",
            output.summary,
            output.newQuestions.map(\.text).joined(separator: " ")
        ].joined(separator: " ").lowercased()

        if haystack.contains("ancient") || haystack.contains("tradition") {
            return "Ancient Traditions"
        }
        if haystack.contains("physiology") || haystack.contains("nervous system") || haystack.contains("co2") {
            return "Physiology"
        }
        if haystack.contains("evidence") || haystack.contains("replication") || haystack.contains("counterevidence") {
            return "Evidence Quality"
        }
        if let concept = output.possibleConnections.first?.name, !concept.isEmpty {
            return concept
        }
        return "Session Crystallization"
    }

    private func shouldCreateCluster(named name: String, output: CrystallizationOutput, extracts: [Atom], sourceRefs: [InquirySourceRef]) -> Bool {
        name != "Session Crystallization" || output.newQuestions.count + output.openLoops.count + extracts.count + sourceRefs.count >= 3
    }

    private func shouldSuggestChildThinkspace(output: CrystallizationOutput, extracts: [Atom], sourceRefs: [InquirySourceRef], questions: [Atom]) -> Bool {
        extracts.count >= 18 || sourceRefs.count >= 8 || questions.count >= 12 || output.possibleConnections.count >= 8
    }

    private func existingClusterMatch(named name: String, thinkspaceUUID: String) -> String? {
        // The actual canvas cluster list lives on ThinkspaceMetadata. This first slice
        // keeps mapping generation deterministic and lets the apply pass resolve IDs.
        nil
    }

    private func duplicateQuestionCheck(_ text: String, questions: [Atom]) -> CanvasDuplicateCheckResult {
        if let exact = questions.first(where: { normalized($0.title ?? "") == normalized(text) }) {
            return CanvasDuplicateCheckResult(verdict: .exactMatch, matchedObjectUUID: exact.uuid, explanation: "A question with the same title already exists; append or link instead of creating another.")
        }
        let normalizedText = normalized(text)
        if let likely = questions.first(where: {
            let candidate = normalized($0.title ?? "")
            return !candidate.isEmpty && !normalizedText.isEmpty && (normalizedText.contains(candidate) || candidate.contains(normalizedText))
        }) {
            return CanvasDuplicateCheckResult(verdict: .likelyDuplicate, matchedObjectUUID: likely.uuid, explanation: "A similar question already exists and should be reviewed before creating a new card.")
        }
        return CanvasDuplicateCheckResult()
    }

    private func duplicateClaimCheck(_ claim: Atom, extracts: [Atom]) -> CanvasDuplicateCheckResult {
        let text = normalized(claim.body ?? claim.title ?? "")
        if let exact = extracts.first(where: { $0.uuid != claim.uuid && normalized($0.body ?? $0.title ?? "") == text }) {
            return CanvasDuplicateCheckResult(verdict: .exactMatch, matchedObjectUUID: exact.uuid, explanation: "A matching claim/extract already exists; append provenance rather than duplicating.")
        }
        return CanvasDuplicateCheckResult()
    }

    private func duplicateConnectionCheck(_ title: String, connections: [Atom]) -> CanvasDuplicateCheckResult {
        let normalizedTitle = normalized(title)
        if let exact = connections.first(where: { normalized($0.title ?? "") == normalizedTitle }) {
            return CanvasDuplicateCheckResult(verdict: .exactMatch, matchedObjectUUID: exact.uuid, explanation: "A Connection with this title already exists; update it instead of creating another.")
        }
        return CanvasDuplicateCheckResult()
    }

    private func existingSourceCheck(_ source: InquirySourceRef, existingSources: [Atom]) -> CanvasDuplicateCheckResult {
        if let url = source.url?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty,
           let existing = existingSources.first(where: { existing in
               guard let existingURL = existing.researchMetadata?.url else { return false }
               return InquiryRepository.shared.canonicalURL(existingURL) == InquiryRepository.shared.canonicalURL(url)
           }) {
            return CanvasDuplicateCheckResult(verdict: .exactMatch, matchedObjectUUID: existing.uuid, matchedSourceURL: url, explanation: "This source URL already exists as a durable source; create an appearance/card, not a duplicate source atom.")
        }
        return CanvasDuplicateCheckResult()
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func makeCardTitle(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Untitled" }
        if trimmed.count <= 72 { return trimmed }
        return String(trimmed.prefix(72)) + "..."
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

        // 1. Lexicon entries (skip terms that already exist for this Deep Dive)
        let existingLexicon = (try? await InquiryRepository.shared.fetchLexicon(forDeepDive: dd.uuid)) ?? []
        let existingTermKeys = Set(existingLexicon.compactMap { $0.title.map(ConceptResolver.conceptKey) })
        for candidate in output.lexiconCandidates where candidate.accepted {
            guard !existingTermKeys.contains(ConceptResolver.conceptKey(candidate.term)) else { continue }
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

        // 2. New questions (find-or-create: re-crystallizing must not duplicate)
        for q in output.newQuestions where q.accepted {
            do {
                let result = try await InquiryRepository.shared.findOrCreateQuestion(
                    title: q.text,
                    parentDeepDiveUUID: dd.uuid,
                    originSessionUUID: session.uuid,
                    parentQuestionUUID: nil,
                    originExtractUUID: nil
                )
                if result.created { summary.questionsCreated += 1 }
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
                    date: ISO8601.string(from: Date()),
                    kind: update.kind,
                    before: update.before,
                    after: update.after,
                    evidence: update.evidence,
                    sessionUUID: session.uuid,
                    acceptedBy: .user
                )
                structured.currentUnderstanding.recentUpdates.append(logged)
                structured.currentUnderstanding.lastUpdated = ISO8601.string(from: Date())
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
        var canvasOperationsApplied: Int = 0
        var canvasBlocksCreated: Int = 0
        var canvasClustersCreated: Int = 0
        var canvasLinksCreated: Int = 0
        var canvasArtifactsHidden: Int = 0
        var childThinkspacesCreated: Int = 0
    }
}
