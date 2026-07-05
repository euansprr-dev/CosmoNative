// CosmoOS/AI/ConnectionRoutingEngine.swift
// Deterministic Inquiry branch -> Connection proposal routing.

import Foundation

actor ConnectionRoutingEngine {
    private let minimumMaterialCount: Int

    init(minimumMaterialCount: Int = 3) {
        self.minimumMaterialCount = minimumMaterialCount
    }

    /// Concept-first proposals: one candidate per resolved concept assignment.
    /// Candidates carry a stable per-concept id and an explicit merge target so the
    /// same concept never produces duplicate Connections across sessions.
    func proposals(
        forSession session: Atom,
        assignments: [ConceptResolver.ConceptAssignment],
        extracts: [Atom],
        sources: [InquirySourceRef] = []
    ) -> [CrystallizationOutput.ConnectionCandidate] {
        let sourceTitlesByUUID = Dictionary(uniqueKeysWithValues: sources.map { ($0.sourceUUID, $0.title) })
        let extractsByUUID = Dictionary(uniqueKeysWithValues: extracts.map { ($0.uuid, $0) })

        var candidates: [CrystallizationOutput.ConnectionCandidate] = []
        for assignment in assignments {
            let conceptExtracts = assignment.extractUUIDs.compactMap { extractsByUUID[$0] }
            guard !conceptExtracts.isEmpty else { continue }
            let routed = routedConceptSections(
                conceptName: assignment.conceptName,
                extracts: conceptExtracts,
                sourceTitlesByUUID: sourceTitlesByUUID
            )
            guard routed.materialCount > 0 else { continue }

            let mergeTarget: String?
            if case .mergeInto(let connectionUUID) = assignment.action {
                mergeTarget = connectionUUID
            } else {
                mergeTarget = nil
            }
            candidates.append(CrystallizationOutput.ConnectionCandidate(
                id: "connection-candidate-concept-\(assignment.conceptKey)",
                name: assignment.conceptName,
                rationale: assignment.rationale.isEmpty
                    ? "\(routed.materialCount) extracts cluster around \(assignment.conceptName)."
                    : assignment.rationale,
                clusterExtractUUIDs: conceptExtracts.map(\.uuid),
                proposedTitle: assignment.conceptName,
                proposedConcept: assignment.conceptName,
                proposedSections: routed.sections,
                proposedReferences: [],
                materialCount: routed.materialCount,
                proposedNotes: routed.notes,
                accepted: mergeTarget != nil || routed.materialCount >= minimumMaterialCount,
                mergeTargetConnectionUUID: mergeTarget,
                conceptAliases: assignment.aliases.isEmpty ? nil : assignment.aliases,
                conceptKey: assignment.conceptKey,
                relatedConceptNames: assignment.relatedConceptNames.isEmpty ? nil : assignment.relatedConceptNames,
                parentConceptName: assignment.parentConceptName
            ))
        }
        return crossLinked(candidates)
    }

    private func routedConceptSections(
        conceptName: String,
        extracts: [Atom],
        sourceTitlesByUUID: [String: String]
    ) -> RoutedMaterial {
        var sections: [ConnectionSectionType: [ConnectionSectionItemDraft]] = [
            .goal: [ConnectionSectionItemDraft(body: "Understand \(conceptName).", kindLabel: "Goal")],
            .conceptName: [ConnectionSectionItemDraft(body: conceptName, kindLabel: "Concept")]
        ]
        var notes: [ConnectionSectionItemDraft] = []
        var materialCount = 0
        var referencedSourceUUIDs = Set<String>()

        for extract in extracts {
            guard let kind = extract.extractMetadata?.kind else { continue }
            let body = (extract.body ?? extract.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            if let target = sectionType(for: kind) {
                sections[target, default: []].append(draft(from: extract, kind: kind))
            } else if kind == .note || kind == .term || kind == .aiInsight {
                notes.append(draft(from: extract, kind: kind))
            } else {
                continue
            }
            if let sourceUUID = extract.extractMetadata?.sourceUUID {
                referencedSourceUUIDs.insert(sourceUUID)
            }
            materialCount += 1
        }

        let referenceDrafts = referencedSourceUUIDs.sorted().map { uuid in
            ConnectionSectionItemDraft(
                body: sourceTitlesByUUID[uuid] ?? "Source \(uuid.prefix(8))",
                sourceUUID: uuid,
                kindLabel: "Source"
            )
        }
        if !referenceDrafts.isEmpty {
            sections[.references, default: []].append(contentsOf: referenceDrafts)
        }
        return RoutedMaterial(sections: sections, notes: notes, materialCount: materialCount)
    }

    func proposals(
        forSession session: Atom,
        branches: [ResearchTreeNode],
        extracts: [Atom],
        sources: [InquirySourceRef] = [],
        lexicon: [Atom] = []
    ) -> [CrystallizationOutput.ConnectionCandidate] {
        let sourceTitlesByUUID = Dictionary(uniqueKeysWithValues: sources.map { ($0.sourceUUID, $0.title) })
        let captures = session.inquirySessionStructured?.sessionCaptures ?? []
        let questionBranches = branches.filter { $0.kind == .question && $0.meta.visibility != .hidden }

        var candidates: [CrystallizationOutput.ConnectionCandidate] = []
        for branch in questionBranches {
            let branchExtracts = extractsForBranch(branch, extracts: extracts)
            let branchCaptures = capturesForBranch(branch, captures: captures)
            let routed = routedSections(
                branch: branch,
                extracts: branchExtracts,
                captures: branchCaptures,
                childQuestions: childQuestionTitles(for: branch, in: questionBranches),
                sourceTitlesByUUID: sourceTitlesByUUID
            )
            let materialCount = routed.materialCount
            guard materialCount > 0 else { continue }

            let title = branchTitle(branch)
            let concept = conceptName(from: title)
            let candidate = CrystallizationOutput.ConnectionCandidate(
                id: stableCandidateId(for: branch),
                name: concept,
                rationale: materialCount >= minimumMaterialCount
                    ? "Branch has \(materialCount) routed captures or extracts."
                    : "Branch has only \(materialCount) routed captures or extracts.",
                clusterExtractUUIDs: branchExtracts.map(\.uuid),
                proposedTitle: title,
                proposedConcept: concept,
                proposedSections: routed.sections,
                proposedReferences: [],
                branchNodeId: branch.id,
                materialCount: materialCount,
                proposedNotes: routed.notes,
                accepted: materialCount >= minimumMaterialCount
            )
            candidates.append(candidate)
        }

        return crossLinked(candidates)
    }

    private func extractsForBranch(_ branch: ResearchTreeNode, extracts: [Atom]) -> [Atom] {
        extracts.filter { atom in
            let metadata = atom.extractMetadata
            return metadata?.parentBranchNodeId == branch.id
                || (branch.atomUUID != nil && metadata?.parentQuestionUUID == branch.atomUUID)
        }
    }

    private func capturesForBranch(_ branch: ResearchTreeNode, captures: [SessionCapture]) -> [SessionCapture] {
        captures.filter { capture in
            capture.status == .pending && capture.attachedQuestionId == branch.atomUUID
        }
    }

    private struct RoutedMaterial {
        var sections: [ConnectionSectionType: [ConnectionSectionItemDraft]]
        var notes: [ConnectionSectionItemDraft]
        var materialCount: Int
    }

    private func routedSections(
        branch: ResearchTreeNode,
        extracts: [Atom],
        captures: [SessionCapture],
        childQuestions: [String],
        sourceTitlesByUUID: [String: String]
    ) -> RoutedMaterial {
        var sections: [ConnectionSectionType: [ConnectionSectionItemDraft]] = [
            .goal: [
                ConnectionSectionItemDraft(
                    body: goalLine(from: branchTitle(branch)),
                    kindLabel: "Goal"
                )
            ],
            .conceptName: [
                ConnectionSectionItemDraft(
                    body: conceptName(from: branchTitle(branch)),
                    kindLabel: "Concept"
                )
            ]
        ]
        var notes: [ConnectionSectionItemDraft] = []
        var materialCount = 0
        var referencedSourceUUIDs = Set<String>()

        for extract in extracts {
            guard let kind = extract.extractMetadata?.kind else { continue }
            let body = (extract.body ?? extract.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            guard let target = sectionType(for: kind) else {
                if kind == .note {
                    notes.append(draft(from: extract, kind: kind))
                    materialCount += 1
                }
                continue
            }
            sections[target, default: []].append(draft(from: extract, kind: kind))
            if let sourceUUID = extract.extractMetadata?.sourceUUID {
                referencedSourceUUIDs.insert(sourceUUID)
            }
            materialCount += 1
        }

        for capture in captures {
            let kind = capture.suggestedKind ?? CaptureIntentClassifier.classifyHeuristic(text: capture.body).kind
            let body = capture.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            if let target = sectionType(for: kind) {
                sections[target, default: []].append(
                    ConnectionSectionItemDraft(
                        body: body,
                        sourceUUID: nil,
                        originExtractUUID: nil,
                        kindLabel: kind.displayName
                    )
                )
            } else if kind == .note {
                notes.append(
                    ConnectionSectionItemDraft(
                        body: body,
                        kindLabel: kind.displayName
                    )
                )
            }
            materialCount += 1
        }

        for question in childQuestions {
            sections[.openQuestions, default: []].append(
                ConnectionSectionItemDraft(body: question, kindLabel: ExtractKind.question.displayName)
            )
        }

        let referenceDrafts = referencedSourceUUIDs
            .sorted()
            .map { uuid in
                ConnectionSectionItemDraft(
                    body: sourceTitlesByUUID[uuid] ?? "Source \(uuid.prefix(8))",
                    sourceUUID: uuid,
                    kindLabel: "Source"
                )
            }
        if !referenceDrafts.isEmpty {
            sections[.references, default: []].append(contentsOf: referenceDrafts)
        }

        return RoutedMaterial(sections: sections, notes: notes, materialCount: materialCount)
    }

    private func draft(from extract: Atom, kind: ExtractKind) -> ConnectionSectionItemDraft {
        ConnectionSectionItemDraft(
            body: extract.body ?? extract.title ?? "",
            sourceUUID: extract.extractMetadata?.sourceUUID,
            originExtractUUID: extract.uuid,
            kindLabel: kind.displayName
        )
    }

    private func sectionType(for kind: ExtractKind) -> ConnectionSectionType? {
        switch kind {
        case .goal:
            return .goal
        case .problem:
            return .problems
        case .claim, .speculativeClaim:
            return .claims
        case .evidence:
            return .evidence
        case .counterevidence, .objection, .principle, .assumption, .sourceQualityNote:
            return .beliefsObjections
        case .mechanism, .practice:
            return .process
        case .example:
            return .examples
        case .outputIdea, .benefit:
            return .benefits
        case .question:
            return .openQuestions
        case .reference:
            return .references
        case .quote, .highlight, .sourceSnippet, .term, .note, .aiInsight:
            return nil
        }
    }

    private func childQuestionTitles(for branch: ResearchTreeNode, in branches: [ResearchTreeNode]) -> [String] {
        branch.childNodeIds.compactMap { childId in
            guard let child = branches.first(where: { $0.id == childId }) else { return nil }
            return branchTitle(child)
        }
    }

    private func crossLinked(
        _ candidates: [CrystallizationOutput.ConnectionCandidate]
    ) -> [CrystallizationOutput.ConnectionCandidate] {
        var updated = candidates
        for i in updated.indices {
            let sourceUUIDs = Set(updated[i].proposedSections.values.flatMap { drafts in drafts.compactMap(\.sourceUUID) })
            let ownTokens = conceptTokens(updated[i].proposedTitle + " " + (updated[i].proposedConcept ?? ""))
            var refs = Set(updated[i].proposedReferences)
            for j in updated.indices where i != j {
                let otherSources = Set(updated[j].proposedSections.values.flatMap { drafts in drafts.compactMap(\.sourceUUID) })
                let otherTokens = conceptTokens(updated[j].proposedTitle + " " + (updated[j].proposedConcept ?? ""))
                if !sourceUUIDs.isDisjoint(with: otherSources) || !ownTokens.isDisjoint(with: otherTokens) {
                    refs.insert(updated[j].id)
                }
            }
            updated[i].proposedReferences = Array(refs).sorted()
        }
        return updated
    }

    private func branchTitle(_ branch: ResearchTreeNode) -> String {
        let title = branch.meta.label?.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.nonEmptyString ?? "Untitled Connection"
    }

    private func goalLine(from question: String) -> String {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutQuestionMark = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: " ?"))
        let lower = withoutQuestionMark.lowercased()
        if lower.hasPrefix("what is ") {
            let subject = String(withoutQuestionMark.dropFirst("What is ".count))
            return "Understand what \(subject) is."
        }
        if lower.hasPrefix("how does ") {
            let subject = String(withoutQuestionMark.dropFirst("How does ".count))
            return "Understand how \(subject)."
        }
        return "Understand \(withoutQuestionMark)."
    }

    private func conceptName(from question: String) -> String {
        var text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " ?"))
        let removals = ["What is ", "How does ", "How do ", "Why does ", "Why do ", "Can ", "Should "]
        for prefix in removals where text.localizedCaseInsensitiveContains(prefix) && text.lowercased().hasPrefix(prefix.lowercased()) {
            text = String(text.dropFirst(prefix.count))
            break
        }
        return text.nonEmptyString ?? question
    }

    private func stableCandidateId(for branch: ResearchTreeNode) -> String {
        "connection-candidate-\(branch.id)"
    }

    private func conceptTokens(_ text: String) -> Set<String> {
        let stop: Set<String> = ["what", "does", "about", "with", "from", "into", "this", "that", "connection", "question", "understand"]
        return Set(
            text.lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
                .filter { $0.count > 3 && !stop.contains($0) }
        )
    }
}

private extension Optional where Wrapped == String {
    var nonEmptyString: String? {
        guard case .some(let value) = self else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension String {
    var nonEmptyString: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
