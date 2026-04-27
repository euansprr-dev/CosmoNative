// CosmoOS/UI/FocusMode/Inquiry/InquiryWorkspaceViewModel.swift
// View model for the 3-pane Inquiry Workspace.
// Owns: session atom, parent Deep Dive, root question, captures, AI conversation,
// layout mode, debounced persistence.

import Foundation
import SwiftUI

@MainActor
@Observable
final class InquiryWorkspaceViewModel {
    // Persistent atoms
    private(set) var session: Atom
    private(set) var deepDive: Atom?
    private(set) var rootQuestion: Atom?
    private(set) var questions: [Atom] = []
    private(set) var extracts: [Atom] = []

    // Live structured + metadata (mirrors session.* but mutable)
    var structured: InquirySessionStructured
    var metadata: InquirySessionMetadata

    // Active branch / question for context-aware actions
    var activeBranchNodeId: String
    var activeQuestionUUID: String?
    var activeSourceTabId: String?

    // Local UI state
    var notebookMode: InquiryNotebookMode = .notes
    var noteDraft: String = ""
    var aiPromptDraft: String = ""
    var aiBusy: Bool = false
    var toast: InquiryToast?
    var noteSaveState: Bool = false

    // Captures (in-memory until commit/crystallize)
    var captures: [SessionCapture] {
        get { structured.sessionCaptures }
        set { structured.sessionCaptures = newValue }
    }

    // Persistence
    private var saveTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    init(session: Atom) {
        self.session = session
        let meta = session.inquirySessionMetadata ?? InquirySessionMetadata()
        let structured = session.inquirySessionStructured ?? InquirySessionStructured(researchTree: ResearchTreeDocument.bootstrap(rootQuestionAtomUUID: nil))
        self.metadata = meta
        self.structured = structured
        self.activeBranchNodeId = structured.researchTree.rootNodeId
        self.activeQuestionUUID = meta.mainQuestionUUID
    }

    // MARK: - Loading

    func loadDeepDiveAndRoot() async {
        if let ddUUID = metadata.parentDeepDiveUUID,
           let dd = try? await AtomRepository.shared.fetch(uuid: ddUUID) {
            deepDive = dd
            await reloadDeepDiveScopedAtoms()
        }
        if let rqUUID = metadata.mainQuestionUUID,
           let rq = try? await AtomRepository.shared.fetch(uuid: rqUUID) {
            rootQuestion = rq
            if !questions.contains(where: { $0.uuid == rq.uuid }) {
                questions.append(rq)
            }
            syncRootNodeLabel(with: rq)
        }
        if activeQuestionUUID == nil {
            activeQuestionUUID = metadata.mainQuestionUUID
        }
        if metadata.status != .active {
            metadata.status = .active
            metadata.lastActiveAt = ISO8601DateFormatter().string(from: Date())
            scheduleSave()
        }
    }

    private func reloadDeepDiveScopedAtoms() async {
        guard let deepDive else { return }
        questions = (try? await InquiryRepository.shared.fetchQuestions(forDeepDive: deepDive.uuid)) ?? []
        extracts = (try? await InquiryRepository.shared.fetchExtracts(forDeepDive: deepDive.uuid)) ?? []
    }

    private func syncRootNodeLabel(with question: Atom) {
        guard var root = structured.researchTree.nodes[structured.researchTree.rootNodeId] else { return }
        root.atomUUID = question.uuid
        root.meta.label = question.title ?? "Untitled inquiry question"
        structured.researchTree.nodes[root.id] = root
    }

    // MARK: - Layout

    func setLayout(_ mode: InquiryLayoutMode) {
        guard metadata.layoutMode != mode else { return }
        metadata.layoutMode = mode
        if mode == .map {
            notebookMode = .tree
        }
        scheduleSave()
    }

    // MARK: - Questions

    var activeQuestion: Atom? {
        guard let activeQuestionUUID else { return rootQuestion }
        return questions.first { $0.uuid == activeQuestionUUID } ?? rootQuestion
    }

    var activeQuestionTitle: String {
        activeQuestion?.title ?? rootQuestion?.title ?? "Untitled inquiry question"
    }

    var activeQuestionBreadcrumb: String {
        var chain: [String] = []
        if let title = deepDive?.title {
            chain.append(title)
        }
        if let active = activeQuestion {
            let ancestors = questionAncestors(for: active)
            chain.append(contentsOf: ancestors.compactMap { $0.title })
            if !chain.contains(active.title ?? "") {
                chain.append(active.title ?? "Untitled inquiry question")
            }
        } else {
            chain.append("Untitled inquiry question")
        }
        return chain.joined(separator: " > ")
    }

    var activeSourceTab: SourceTab? {
        guard let id = activeSourceTabId else { return structured.sourceTabs.first }
        return structured.sourceTabs.first { $0.id == id } ?? structured.sourceTabs.first
    }

    func questionTitle(for uuid: String?) -> String {
        guard let uuid else { return "Untitled inquiry question" }
        return questions.first { $0.uuid == uuid }?.title ?? (uuid == rootQuestion?.uuid ? rootQuestion?.title : nil) ?? "Untitled inquiry question"
    }

    func questionStatus(for uuid: String?) -> QuestionStatus {
        guard let uuid else { return .open }
        return questions.first { $0.uuid == uuid }?.questionMetadata?.status ?? .open
    }

    func questionNodeId(for questionUUID: String?) -> String? {
        structured.researchTree.nodes.values.first { node in
            node.kind == .question && node.atomUUID == questionUUID
        }?.id
    }

    func setActiveQuestion(_ questionUUID: String?, branchNodeId: String? = nil) {
        activeQuestionUUID = questionUUID
        if let branchNodeId {
            activeBranchNodeId = branchNodeId
        } else if let nodeId = questionNodeId(for: questionUUID) {
            activeBranchNodeId = nodeId
        }
        structured.uiState.selectedInspectorQuestionUUID = questionUUID
        scheduleSave()
    }

    func cycleQuestion(offset: Int) {
        let ordered = orderedQuestionNodes()
        guard !ordered.isEmpty else { return }
        let currentIndex = ordered.firstIndex { $0.atomUUID == activeQuestionUUID } ?? 0
        let nextIndex = (currentIndex + offset + ordered.count) % ordered.count
        let node = ordered[nextIndex]
        setActiveQuestion(node.atomUUID, branchNodeId: node.id)
    }

    func goToParentQuestion() {
        guard let active = activeQuestion,
              let parentUUID = active.questionMetadata?.parentQuestionUUID else { return }
        setActiveQuestion(parentUUID)
    }

    func orderedQuestionNodes() -> [ResearchTreeNode] {
        func walk(_ id: String, into output: inout [ResearchTreeNode]) {
            guard let node = structured.researchTree.nodes[id] else { return }
            if shouldShowQuestionNode(node) {
                output.append(node)
            }
            for child in node.childNodeIds.sorted(by: {
                (structured.researchTree.nodes[$0]?.branchOrder ?? 0) < (structured.researchTree.nodes[$1]?.branchOrder ?? 0)
            }) {
                walk(child, into: &output)
            }
        }
        var output: [ResearchTreeNode] = []
        for rootId in rootQuestionNodeIds() {
            walk(rootId, into: &output)
        }
        return output
    }

    func rootQuestionNodeIds() -> [String] {
        let explicitRoots = structured.researchTree.rootQuestionNodeIds
        if !explicitRoots.isEmpty {
            return explicitRoots.filter { id in
                guard let node = structured.researchTree.nodes[id] else { return false }
                return shouldShowQuestionNode(node)
            }
        }
        return [structured.researchTree.rootNodeId].filter { id in
            guard let node = structured.researchTree.nodes[id] else { return false }
            return shouldShowQuestionNode(node)
        }
    }

    func childQuestionNodes(for nodeId: String) -> [ResearchTreeNode] {
        guard let node = structured.researchTree.nodes[nodeId] else { return [] }
        return node.childNodeIds.compactMap { structured.researchTree.nodes[$0] }.filter { shouldShowQuestionNode($0) }
    }

    func shouldShowQuestionNode(_ node: ResearchTreeNode) -> Bool {
        guard node.kind == .question else { return false }
        if node.meta.visibility == .hidden || node.meta.isPlaceholder == true { return false }
        if (node.meta.label ?? "").localizedCaseInsensitiveCompare("New branch question") == .orderedSame && node.atomUUID == nil { return false }
        guard let uuid = node.atomUUID else { return node.id == structured.researchTree.rootNodeId && rootQuestion == nil }
        return questionStatus(for: uuid) != .archived
    }

    func questionAncestors(for question: Atom) -> [Atom] {
        var result: [Atom] = []
        var parentUUID = question.questionMetadata?.parentQuestionUUID
        while let uuid = parentUUID, let parent = questions.first(where: { $0.uuid == uuid }) {
            result.insert(parent, at: 0)
            parentUUID = parent.questionMetadata?.parentQuestionUUID
        }
        return result
    }

    func counts(for questionUUID: String?) -> InquiryQuestionCounts {
        let sourceCount = structured.sourceRefs.filter { $0.primaryQuestionUUID == questionUUID && $0.status != .archived && $0.status != .deleted }.count
        let attachedExtracts = extracts.filter { $0.extractMetadata?.parentQuestionUUID == questionUUID }
        let noteCount = attachedExtracts.filter { $0.extractMetadata?.kind == .note }.count
        let claimCount = attachedExtracts.filter { $0.extractMetadata?.kind.isClaimLike == true }.count
        let evidenceCount = attachedExtracts.filter { $0.extractMetadata?.kind.isEvidenceLike == true }.count
        let extractCount = attachedExtracts.filter { atom in
            guard let kind = atom.extractMetadata?.kind else { return false }
            return kind != .note && !kind.isEpistemic
        }.count
        let childCount = questions.filter { $0.questionMetadata?.parentQuestionUUID == questionUUID }.count
        let taskCount = structured.operationalTasks.filter { task in
            task.status != .archived && task.attachedQuestionUUID == questionUUID
        }.count
        return InquiryQuestionCounts(sources: sourceCount, extracts: extractCount, notes: noteCount, claims: claimCount, evidence: evidenceCount, tasks: taskCount, children: childCount)
    }

    func extracts(for questionUUID: String?, kinds: Set<ExtractKind>) -> [Atom] {
        extracts
            .filter { atom in
                atom.extractMetadata?.parentQuestionUUID == questionUUID && kinds.contains(atom.extractMetadata?.kind ?? .note)
            }
            .sorted { ($0.extractMetadata?.committedAt ?? $0.createdAt) > ($1.extractMetadata?.committedAt ?? $1.createdAt) }
    }

    func recentNotes(for questionUUID: String?, limit: Int = 3) -> [Atom] {
        Array(extracts(for: questionUUID, kinds: [.note]).prefix(limit))
    }

    func claims(for questionUUID: String?) -> [Atom] {
        extracts(for: questionUUID, kinds: [.claim, .speculativeClaim])
    }

    func evidence(for questionUUID: String?) -> [Atom] {
        extracts(for: questionUUID, kinds: [.evidence, .counterevidence])
    }

    func mechanisms(for questionUUID: String?) -> [Atom] {
        extracts(for: questionUUID, kinds: [.mechanism, .assumption, .sourceQualityNote])
    }

    func operationalTasks(for questionUUID: String?) -> [InquiryOperationalTask] {
        structured.operationalTasks
            .filter { $0.status != .archived && $0.attachedQuestionUUID == questionUUID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func registerSavedExtract(_ extract: Atom, sourceTabId: String?) {
        if !extracts.contains(where: { $0.uuid == extract.uuid }) {
            extracts.append(extract)
        }
        if let sourceUUID = extract.extractMetadata?.sourceUUID,
           let refIdx = structured.sourceRefs.firstIndex(where: { $0.sourceUUID == sourceUUID }) {
            if extract.extractMetadata?.kind == .note {
                structured.sourceRefs[refIdx].noteCount += 1
            } else {
                structured.sourceRefs[refIdx].extractCount += 1
            }
        }
        if let sourceTabId,
           let tabIdx = structured.sourceTabs.firstIndex(where: { $0.id == sourceTabId }),
           extract.extractMetadata?.kind != .note {
            structured.sourceTabs[tabIdx].highlightCount += 1
        }
        let kind = extract.extractMetadata?.kind ?? .highlight
        appendActivity(
            .init(
                kind: kind.isEvidenceLike ? .evidenceSaved : .extractSaved,
                title: "\(kind.displayName) saved",
                detail: extract.body,
                questionUUID: extract.extractMetadata?.parentQuestionUUID,
                sourceUUID: extract.extractMetadata?.sourceUUID,
                extractUUID: extract.uuid
            )
        )
    }

    func togglePinActiveQuestion() {
        guard let activeQuestionUUID else { return }
        togglePinnedQuestion(activeQuestionUUID)
    }

    func togglePinnedQuestion(_ questionUUID: String) {
        if structured.uiState.pinnedQuestionUUIDs.contains(questionUUID) {
            structured.uiState.pinnedQuestionUUIDs.removeAll { $0 == questionUUID }
        } else {
            structured.uiState.pinnedQuestionUUIDs.append(questionUUID)
        }
        scheduleSave()
    }

    func pinnedQuestions() -> [Atom] {
        structured.uiState.pinnedQuestionUUIDs.compactMap { uuid in
            questions.first { $0.uuid == uuid }
        }
    }

    @discardableResult
    func createRootQuestion(title: String) async -> Atom? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let deepDive else { return nil }
        do {
            let question = try await InquiryRepository.shared.createQuestion(
                title: trimmed,
                parentDeepDiveUUID: deepDive.uuid,
                originSessionUUID: session.uuid,
                parentQuestionUUID: nil,
                originExtractUUID: nil,
                questionRole: .rootQuestion,
                relationshipToParent: .rootUnderTopic,
                placementOrigin: "manual"
            )
            metadata.mainQuestionUUID = question.uuid
            rootQuestion = question
            questions.append(question)
            syncRootNodeLabel(with: question)
            setActiveQuestion(question.uuid, branchNodeId: structured.researchTree.rootNodeId)
            scheduleSave()
            return question
        } catch {
            print("[InquiryWorkspaceVM] createRootQuestion failed: \(error)")
            return nil
        }
    }

    @discardableResult
    func createChildQuestion(title: String, originExtractUUID: String? = nil, sourceTabId: String? = nil, makeActive: Bool = true) async -> Atom? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            let parentQuestionUUID = activeQuestionUUID ?? metadata.mainQuestionUUID
            let parentNodeId = activeBranchNodeId
            let question = try await InquiryRepository.shared.createQuestion(
                title: trimmed,
                parentDeepDiveUUID: deepDive?.uuid,
                originSessionUUID: session.uuid,
                parentQuestionUUID: parentQuestionUUID,
                originExtractUUID: originExtractUUID,
                questionRole: .branchQuestion,
                relationshipToParent: .childOf,
                placementOrigin: originExtractUUID == nil ? "manual" : "deepen",
                sourceExtractUUID: originExtractUUID
            )
            questions.append(question)
            let newNodeId = structured.researchTree.appendChild(
                parentId: parentNodeId,
                kind: .question,
                atomUUID: question.uuid,
                label: trimmed,
                aiSuggested: originExtractUUID != nil,
                accepted: true,
                sourceTabId: sourceTabId,
                nodeType: .branchQuestion,
                relationshipType: .childOf,
                visibility: .solidNode,
                linkedExtractUUIDs: originExtractUUID.map { [$0] }
            )
            if makeActive {
                setActiveQuestion(question.uuid, branchNodeId: newNodeId)
            } else {
                scheduleSave()
            }
            return question
        } catch {
            print("[InquiryWorkspaceVM] createChildQuestion failed: \(error)")
            return nil
        }
    }

    @discardableResult
    func createPlacedQuestion(title: String, placement: InquiryPlacementDecision, originExtractUUID: String? = nil, sourceTabId: String? = nil, makeActive: Bool = true) async -> Atom? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let isRoot = placement.nodeType == .rootQuestion || placement.relationshipType == .rootUnderTopic
        let parentQuestionUUID = isRoot ? nil : (placement.parentQuestionUUID ?? activeQuestionUUID ?? metadata.mainQuestionUUID)
        let parentNodeId = isRoot ? nil : (placement.parentBranchNodeId ?? parentQuestionUUID.flatMap { questionNodeId(for: $0) } ?? activeBranchNodeId)

        if questions.contains(where: { InquiryPlacementEngine.normalized($0.title ?? "") == InquiryPlacementEngine.normalized(trimmed) }) {
            showToast("Question already exists", detail: "Jumping to the existing question.")
            if let existing = questions.first(where: { InquiryPlacementEngine.normalized($0.title ?? "") == InquiryPlacementEngine.normalized(trimmed) }) {
                setActiveQuestion(existing.uuid)
            }
            return nil
        }

        do {
            let question = try await InquiryRepository.shared.createQuestion(
                title: trimmed,
                parentDeepDiveUUID: deepDive?.uuid,
                originSessionUUID: session.uuid,
                parentQuestionUUID: parentQuestionUUID,
                originExtractUUID: originExtractUUID,
                questionRole: isRoot ? .rootQuestion : .branchQuestion,
                relationshipToParent: placement.relationshipType,
                placementOrigin: "placement_engine",
                placementConfidence: placement.confidence,
                placementExplanation: placement.explanation,
                sourceQuestionUUID: activeQuestionUUID,
                sourceExtractUUID: originExtractUUID
            )
            questions.append(question)

            let newNodeId: String?
            if isRoot {
                if rootQuestion == nil || metadata.mainQuestionUUID == nil {
                    metadata.mainQuestionUUID = question.uuid
                    rootQuestion = question
                    syncRootNodeLabel(with: question)
                    if var root = structured.researchTree.nodes[structured.researchTree.rootNodeId] {
                        root.meta.nodeType = .rootQuestion
                        root.meta.relationshipType = .rootUnderTopic
                        root.meta.visibility = .solidNode
                        root.meta.isPlaceholder = false
                        root.meta.placementDecisionId = placement.id
                        structured.researchTree.nodes[root.id] = root
                    }
                    newNodeId = structured.researchTree.rootNodeId
                } else {
                    newNodeId = structured.researchTree.appendRootQuestion(
                        atomUUID: question.uuid,
                        label: trimmed,
                        aiSuggested: originExtractUUID != nil,
                        accepted: true,
                        sourceTabId: sourceTabId,
                        placementDecisionId: placement.id
                    )
                }
            } else if let parentNodeId {
                newNodeId = structured.researchTree.appendChild(
                    parentId: parentNodeId,
                    kind: .question,
                    atomUUID: question.uuid,
                    label: trimmed,
                    aiSuggested: originExtractUUID != nil,
                    accepted: true,
                    sourceTabId: sourceTabId,
                    nodeType: .branchQuestion,
                    relationshipType: placement.relationshipType,
                    visibility: .solidNode,
                    placementDecisionId: placement.id,
                    linkedExtractUUIDs: originExtractUUID.map { [$0] }
                )
            } else {
                newNodeId = structured.researchTree.appendRootQuestion(
                    atomUUID: question.uuid,
                    label: trimmed,
                    aiSuggested: originExtractUUID != nil,
                    accepted: true,
                    sourceTabId: sourceTabId,
                    placementDecisionId: placement.id
                )
            }

            if let sourceTabId,
               let tabIdx = structured.sourceTabs.firstIndex(where: { $0.id == sourceTabId }) {
                structured.sourceTabs[tabIdx].attachedQuestionUUID = question.uuid
                structured.sourceTabs[tabIdx].attachedNodeId = newNodeId
            }

            if makeActive {
                setActiveQuestion(question.uuid, branchNodeId: newNodeId)
            } else {
                scheduleSave()
            }
            return question
        } catch {
            print("[InquiryWorkspaceVM] createPlacedQuestion failed: \(error)")
            return nil
        }
    }

    func updateQuestionStatus(_ questionUUID: String?, status: QuestionStatus) async {
        guard let questionUUID,
              let idx = questions.firstIndex(where: { $0.uuid == questionUUID }),
              var meta = questions[idx].questionMetadata else { return }
        meta.status = status
        var copy = questions[idx].withMetadata(meta)
        do {
            copy = try await AtomRepository.shared.update(copy)
            questions[idx] = copy
            if rootQuestion?.uuid == copy.uuid {
                rootQuestion = copy
            }
        } catch {
            print("[InquiryWorkspaceVM] updateQuestionStatus failed: \(error)")
        }
    }

    func renameQuestion(_ questionUUID: String?, title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let questionUUID, !trimmed.isEmpty,
              let idx = questions.firstIndex(where: { $0.uuid == questionUUID }) else { return }
        var copy = questions[idx]
        copy.title = trimmed
        do {
            copy = try await AtomRepository.shared.update(copy)
            questions[idx] = copy
            if rootQuestion?.uuid == copy.uuid {
                rootQuestion = copy
                syncRootNodeLabel(with: copy)
            }
            if let nodeId = questionNodeId(for: questionUUID), var node = structured.researchTree.nodes[nodeId] {
                node.meta.label = trimmed
                structured.researchTree.nodes[nodeId] = node
            }
            scheduleSave()
        } catch {
            print("[InquiryWorkspaceVM] renameQuestion failed: \(error)")
        }
    }

    func archiveQuestion(_ questionUUID: String?) async {
        await updateQuestionStatus(questionUUID, status: .archived)
        if activeQuestionUUID == questionUUID {
            let next = orderedQuestionNodes().first
            setActiveQuestion(next?.atomUUID, branchNodeId: next?.id)
        }
        scheduleSave()
    }

    func deleteQuestion(_ questionUUID: String?) async {
        guard let questionUUID,
              let nodeId = questionNodeId(for: questionUUID),
              let node = structured.researchTree.nodes[nodeId] else { return }
        let promoteParentId = node.parentNodeId
        let promoteParentQuestionUUID = promoteParentId.flatMap { structured.researchTree.nodes[$0]?.atomUUID }
        let childQuestionUUIDs = node.childNodeIds.compactMap { structured.researchTree.nodes[$0]?.atomUUID }
        do {
            try await AtomRepository.shared.delete(uuid: questionUUID)
            questions.removeAll { $0.uuid == questionUUID }
            structured.researchTree.removeNode(nodeId, promoteChildrenTo: promoteParentId)
            for childUUID in childQuestionUUIDs {
                await updateQuestionParent(childUUID, newParentQuestionUUID: promoteParentQuestionUUID, relationship: promoteParentQuestionUUID == nil ? .rootUnderTopic : .childOf)
            }
            if rootQuestion?.uuid == questionUUID {
                rootQuestion = questions.first { $0.questionMetadata?.parentQuestionUUID == nil }
                metadata.mainQuestionUUID = rootQuestion?.uuid
            }
            if activeQuestionUUID == questionUUID {
                let next = orderedQuestionNodes().first
                setActiveQuestion(next?.atomUUID, branchNodeId: next?.id)
            }
            showToast("Question deleted", detail: "Children were kept in the map.")
            scheduleSave()
        } catch {
            print("[InquiryWorkspaceVM] deleteQuestion failed: \(error)")
        }
    }

    func reparentQuestion(_ questionUUID: String?, to newParentQuestionUUID: String?, relationship: InquiryRelationshipType? = nil) async {
        guard let questionUUID,
              let nodeId = questionNodeId(for: questionUUID) else { return }
        let newParentNodeId = newParentQuestionUUID.flatMap { questionNodeId(for: $0) }
        let rel = relationship ?? (newParentQuestionUUID == nil ? .rootUnderTopic : .childOf)
        guard structured.researchTree.reparentNode(nodeId, to: newParentNodeId, relationshipType: rel) else {
            showToast("Cannot move question", detail: "That would create a loop.")
            return
        }
        await updateQuestionParent(questionUUID, newParentQuestionUUID: newParentQuestionUUID, relationship: rel)
        if newParentQuestionUUID == nil {
            metadata.mainQuestionUUID = rootQuestion?.uuid ?? questionUUID
        }
        setActiveQuestion(questionUUID, branchNodeId: nodeId)
        showToast("Question moved", detail: newParentQuestionUUID == nil ? "Now a root question." : "Reparented under \(questionTitle(for: newParentQuestionUUID)).")
        scheduleSave()
    }

    func makeQuestionSibling(_ questionUUID: String?) async {
        guard let questionUUID,
              let current = questions.first(where: { $0.uuid == questionUUID }) else { return }
        let parentUUID = current.questionMetadata?.parentQuestionUUID
        let grandparentUUID = parentUUID.flatMap { parent in
            questions.first { $0.uuid == parent }?.questionMetadata?.parentQuestionUUID
        }
        await reparentQuestion(questionUUID, to: grandparentUUID, relationship: grandparentUUID == nil ? .rootUnderTopic : .siblingOf)
    }

    private func updateQuestionParent(_ questionUUID: String, newParentQuestionUUID: String?, relationship: InquiryRelationshipType) async {
        guard let idx = questions.firstIndex(where: { $0.uuid == questionUUID }),
              var meta = questions[idx].questionMetadata else { return }
        meta.parentQuestionUUID = newParentQuestionUUID
        meta.questionRole = newParentQuestionUUID == nil ? .rootQuestion : .branchQuestion
        meta.relationshipToParent = relationship
        var copy = questions[idx].withMetadata(meta)
        do {
            copy = try await AtomRepository.shared.update(copy)
            questions[idx] = copy
            if rootQuestion?.uuid == copy.uuid {
                rootQuestion = copy
            }
        } catch {
            print("[InquiryWorkspaceVM] updateQuestionParent failed: \(error)")
        }
    }

    // MARK: - Captures

    /// Append a temporary capture (not yet promoted to an atom).
    func addCapture(_ body: String, source: SessionCapture.Source = .type, suggestedKind: ExtractKind? = nil) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let capture = SessionCapture(
            body: trimmed,
            source: source,
            suggestedKind: suggestedKind,
            attachedQuestionId: activeQuestionUUID,
            attachedSourceTabId: activeSourceTabId
        )
        structured.sessionCaptures.append(capture)
        scheduleSave()
    }

    /// Commit a capture to an Extract atom. Returns the new Extract UUID on success.
    func commitCapture(_ captureId: String, kind: ExtractKind) async -> String? {
        guard let idx = structured.sessionCaptures.firstIndex(where: { $0.id == captureId }) else { return nil }
        let capture = structured.sessionCaptures[idx]
        do {
            let extract = try await InquiryRepository.shared.createExtract(
                body: capture.body,
                kind: kind,
                sourceUUID: nil,
                selectionRange: nil,
                sessionUUID: session.uuid,
                questionUUID: capture.attachedQuestionId,
                deepDiveUUID: deepDive?.uuid,
                branchNodeId: activeBranchNodeId,
                sourceTabId: capture.attachedSourceTabId,
                userNote: nil,
                originType: capture.source.rawValue,
                citation: nil
            )
            structured.sessionCaptures[idx].status = .committed
            structured.sessionCaptures[idx].promotedToAtomUUID = extract.uuid

            // Append to research tree under active branch
            structured.researchTree.appendChild(
                parentId: activeBranchNodeId,
                kind: .extract,
                atomUUID: extract.uuid,
                label: capture.body.prefix(60).description,
                aiSuggested: false,
                accepted: true
            )
            scheduleSave()
            await reloadDeepDiveScopedAtoms()
            return extract.uuid
        } catch {
            print("[InquiryWorkspaceVM] commitCapture failed: \(error)")
            return nil
        }
    }

    func discardCapture(_ captureId: String) {
        if let idx = structured.sessionCaptures.firstIndex(where: { $0.id == captureId }) {
            structured.sessionCaptures[idx].status = .discarded
            scheduleSave()
        }
    }

    // MARK: - Sources

    func openURLSource(_ rawURL: String) async {
        let canonical = InquiryRepository.shared.canonicalURL(rawURL)
        guard let url = URL(string: canonical) else { return }
        let title = url.host ?? canonical
        do {
            let source = try await InquiryRepository.shared.createOrFindURLSource(urlString: canonical, title: title)
            let tab = openTab(for: source, url: canonical, title: title)
            upsertSourceRef(for: source, tab: tab, url: canonical, title: title)
            activeSourceTabId = tab.id
            appendActivity(
                .init(
                    kind: .sourceOpened,
                    title: "Source opened",
                    detail: title,
                    questionUUID: activeQuestionUUID,
                    sourceUUID: source.uuid
                )
            )
            showToast("Source captured", detail: "Attached to \(activeQuestionTitle)")
            scheduleSave()
        } catch {
            print("[InquiryWorkspaceVM] openURLSource failed: \(error)")
        }
    }

    func reopenSource(_ ref: InquirySourceRef) {
        if let tabId = ref.tabId, structured.sourceTabs.contains(where: { $0.id == tabId }) {
            activeSourceTabId = tabId
            return
        }
        let tab = SourceTab(
            kind: .web,
            sourceUUID: ref.sourceUUID,
            url: ref.url,
            title: ref.title,
            attachedQuestionUUID: ref.primaryQuestionUUID,
            attachedNodeId: ref.primaryNodeId
        )
        structured.sourceTabs.append(tab)
        if let idx = structured.sourceRefs.firstIndex(where: { $0.sourceUUID == ref.sourceUUID }) {
            structured.sourceRefs[idx].tabId = tab.id
            structured.sourceRefs[idx].lastOpenedAt = ISO8601DateFormatter().string(from: Date())
        }
        activeSourceTabId = tab.id
        scheduleSave()
    }

    func closeSourceTab(_ id: String) {
        guard let tab = structured.sourceTabs.first(where: { $0.id == id }) else { return }
        structured.sourceTabs.removeAll { $0.id == id }
        if let sourceUUID = tab.sourceUUID,
           let refIdx = structured.sourceRefs.firstIndex(where: { $0.sourceUUID == sourceUUID }) {
            structured.sourceRefs[refIdx].tabId = nil
        }
        if activeSourceTabId == id {
            activeSourceTabId = structured.sourceTabs.first?.id
        }
        appendActivity(
            .init(
                kind: .sourceClosed,
                title: "Source closed",
                detail: "It remains in session history.",
                questionUUID: tab.attachedQuestionUUID,
                sourceUUID: tab.sourceUUID
            )
        )
        showToast("Closed source", detail: "It remains in session history.")
        scheduleSave()
    }

    func attachSourceTab(_ tab: SourceTab, toQuestionUUID questionUUID: String?, nodeId: String) {
        guard let idx = structured.sourceTabs.firstIndex(where: { $0.id == tab.id }) else { return }
        structured.sourceTabs[idx].attachedQuestionUUID = questionUUID
        structured.sourceTabs[idx].attachedNodeId = nodeId
        if let sourceUUID = structured.sourceTabs[idx].sourceUUID,
           let refIdx = structured.sourceRefs.firstIndex(where: { $0.sourceUUID == sourceUUID }) {
            structured.sourceRefs[refIdx].primaryQuestionUUID = questionUUID
            structured.sourceRefs[refIdx].primaryNodeId = nodeId
        }
        scheduleSave()
    }

    private func openTab(for source: Atom, url: String, title: String) -> SourceTab {
        if let existing = structured.sourceTabs.first(where: { $0.sourceUUID == source.uuid }) {
            return existing
        }
        let tab = SourceTab(
            kind: .web,
            sourceUUID: source.uuid,
            url: url,
            title: source.title ?? title,
            attachedQuestionUUID: activeQuestionUUID,
            attachedNodeId: activeBranchNodeId
        )
        structured.sourceTabs.append(tab)
        return tab
    }

    private func upsertSourceRef(for source: Atom, tab: SourceTab, url: String, title: String) {
        let now = ISO8601DateFormatter().string(from: Date())
        let domain = URL(string: url)?.host
        if let idx = structured.sourceRefs.firstIndex(where: { $0.sourceUUID == source.uuid }) {
            structured.sourceRefs[idx].tabId = tab.id
            structured.sourceRefs[idx].url = url
            structured.sourceRefs[idx].title = source.title ?? title
            structured.sourceRefs[idx].domain = domain
            structured.sourceRefs[idx].status = .viewed
            structured.sourceRefs[idx].primaryQuestionUUID = activeQuestionUUID
            structured.sourceRefs[idx].primaryNodeId = activeBranchNodeId
            structured.sourceRefs[idx].lastOpenedAt = now
        } else {
            structured.sourceRefs.append(
                InquirySourceRef(
                    sourceUUID: source.uuid,
                    tabId: tab.id,
                    url: url,
                    title: source.title ?? title,
                    domain: domain,
                    primaryQuestionUUID: activeQuestionUUID,
                    primaryNodeId: activeBranchNodeId,
                    openedAt: now,
                    lastOpenedAt: now
                )
            )
        }
    }

    // MARK: - Notes (commits a note Atom on save)

    func saveNoteDraft() async {
        let trimmed = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Persist as an Extract atom of kind .note (preserves provenance).
        do {
            let extract = try await InquiryRepository.shared.createExtract(
                body: trimmed,
                kind: .note,
                sourceUUID: activeSourceTab?.sourceUUID,
                selectionRange: nil,
                sessionUUID: session.uuid,
                questionUUID: activeQuestionUUID,
                deepDiveUUID: deepDive?.uuid,
                branchNodeId: activeBranchNodeId,
                sourceTabId: activeSourceTabId,
                userNote: nil,
                originType: "manual",
                citation: nil
            )
            extracts.append(extract)
            if let sourceUUID = extract.extractMetadata?.sourceUUID,
               let refIdx = structured.sourceRefs.firstIndex(where: { $0.sourceUUID == sourceUUID }) {
                structured.sourceRefs[refIdx].noteCount += 1
            }
            noteSaveState = true
            appendActivity(
                .init(
                    kind: .noteSaved,
                    title: "Note saved",
                    detail: "Saved to \(activeQuestionTitle)",
                    questionUUID: activeQuestionUUID,
                    sourceUUID: activeSourceTab?.sourceUUID,
                    extractUUID: extract.uuid
                )
            )
            showToast("Saved to \(activeQuestionTitle)", detail: nil)
            routeThought(trimmed, originExtractUUID: extract.uuid, sourceTabId: activeSourceTabId)
            scheduleSave()
            noteDraft = ""
            resetNoteSaveStateSoon()
        } catch {
            print("[InquiryWorkspaceVM] saveNoteDraft failed: \(error)")
        }
    }

    func savePinnedNoteDraft(for questionUUID: String) async {
        let raw = structured.uiState.pinnedNoteDraftsByQuestionUUID[questionUUID] ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let branchNodeId = questionNodeId(for: questionUUID) ?? activeBranchNodeId
        do {
            let extract = try await InquiryRepository.shared.createExtract(
                body: trimmed,
                kind: .note,
                sourceUUID: activeSourceTab?.sourceUUID,
                selectionRange: nil,
                sessionUUID: session.uuid,
                questionUUID: questionUUID,
                deepDiveUUID: deepDive?.uuid,
                branchNodeId: branchNodeId,
                sourceTabId: activeSourceTabId,
                userNote: nil,
                originType: "manual",
                citation: nil
            )
            extracts.append(extract)
            if let sourceUUID = extract.extractMetadata?.sourceUUID,
               let refIdx = structured.sourceRefs.firstIndex(where: { $0.sourceUUID == sourceUUID }) {
                structured.sourceRefs[refIdx].noteCount += 1
            }
            appendActivity(
                .init(
                    kind: .noteSaved,
                    title: "Note saved",
                    detail: "Saved to \(questionTitle(for: questionUUID))",
                    questionUUID: questionUUID,
                    sourceUUID: activeSourceTab?.sourceUUID,
                    extractUUID: extract.uuid
                )
            )
            showToast("Saved to \(questionTitle(for: questionUUID))", detail: nil)
            routeThought(trimmed, originExtractUUID: extract.uuid, sourceTabId: activeSourceTabId, questionUUID: questionUUID, branchNodeId: branchNodeId)
            structured.uiState.pinnedNoteDraftsByQuestionUUID[questionUUID] = ""
            scheduleSave()
        } catch {
            print("[InquiryWorkspaceVM] savePinnedNoteDraft failed: \(error)")
        }
    }

    private func routeThought(_ text: String, originExtractUUID: String?, sourceTabId: String?, questionUUID: String? = nil, branchNodeId: String? = nil) {
        let scopedQuestionUUID = questionUUID ?? activeQuestionUUID
        let cards = InquiryPlacementEngine.route(
            text: text,
            context: InquiryPlacementEngine.Context(
                deepDiveTitle: deepDive?.title,
                activeQuestion: scopedQuestionUUID.flatMap { uuid in questions.first { $0.uuid == uuid } } ?? activeQuestion,
                activeQuestionUUID: scopedQuestionUUID,
                activeBranchNodeId: branchNodeId ?? activeBranchNodeId,
                sourceTabId: sourceTabId,
                originExtractUUID: originExtractUUID,
                originAction: .saveNote,
                questions: questions,
                claims: claims(for: scopedQuestionUUID)
            )
        )
        let filtered = cards.filter { card in
            guard let proposed = card.proposedQuestion else { return true }
            return !questions.contains { InquiryPlacementEngine.normalized($0.title ?? "") == InquiryPlacementEngine.normalized(proposed) }
        }
        guard !filtered.isEmpty else { return }
        structured.routingCards.append(contentsOf: filtered)
        for card in filtered {
            appendActivity(
                .init(
                    kind: .routingSuggested,
                    title: card.title,
                    detail: card.proposedQuestion ?? card.proposedExtractText,
                    questionUUID: card.parentQuestionUUID,
                    routingCardId: card.id
                )
            )
        }
    }

    private func appendActivity(_ event: InquiryActivityEvent) {
        structured.activityEvents.append(event)
        if structured.activityEvents.count > 80 {
            structured.activityEvents.removeFirst(structured.activityEvents.count - 80)
        }
    }

    private func showToast(_ message: String, detail: String?) {
        toastTask?.cancel()
        toast = InquiryToast(message: message, detail: detail)
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard let self, !Task.isCancelled else { return }
            self.toast = nil
        }
    }

    private func resetNoteSaveStateSoon() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard let self else { return }
            self.noteSaveState = false
        }
    }

    // MARK: - AI

    /// Append a record of an AI exchange (no LLM call yet — call site provides response).
    func recordAIInteraction(prompt: String, response: String, modelTier: String? = nil) {
        let interaction = AIInteractionRef(
            branchNodeId: activeBranchNodeId,
            sourceTabId: activeSourceTabId,
            prompt: prompt,
            response: response,
            modelTier: modelTier
        )
        structured.aiInteractions.append(interaction)
        appendActivity(
            .init(
                kind: .aiReply,
                title: "AI replied",
                detail: prompt,
                questionUUID: activeQuestionUUID,
                sourceUUID: activeSourceTab?.sourceUUID
            )
        )
        scheduleSave()
    }

    func proposeBranchFromSelection(_ selection: String, originExtractUUID: String?, sourceTabId: String?) {
        let title = branchQuestionTitle(from: selection)
        let placement = InquiryPlacementEngine.placement(
            for: title,
            fullText: selection,
            context: InquiryPlacementEngine.Context(
                deepDiveTitle: deepDive?.title,
                activeQuestion: activeQuestion,
                activeQuestionUUID: activeQuestionUUID,
                activeBranchNodeId: activeBranchNodeId,
                sourceTabId: sourceTabId,
                originExtractUUID: originExtractUUID,
                originAction: .deepen,
                questions: questions,
                claims: claims(for: activeQuestionUUID)
            )
        )
        let card = InquiryRoutingCard(
            kind: .placementPreview,
            title: "Child question candidate",
            detail: selection.prefix(180).description,
            proposedQuestion: title,
            actionTitle: "Create here",
            parentQuestionUUID: activeQuestionUUID,
            parentBranchNodeId: activeBranchNodeId,
            originExtractUUID: originExtractUUID,
            sourceTabId: sourceTabId,
            placement: placement
        )
        structured.routingCards.append(card)
        recordAIInteraction(
            prompt: "Deepen selected text",
            response: "This deserves its own branch: \(title)",
            modelTier: AgentModelTier.sensor.rawValue
        )
        scheduleSave()
    }

    func acceptRoutingCard(_ card: InquiryRoutingCard) async {
        await acceptRoutingCard(card, overridePlacement: nil)
    }

    func acceptRoutingCard(_ card: InquiryRoutingCard, overridePlacement: InquiryPlacementDecision?) async {
        guard let idx = structured.routingCards.firstIndex(where: { $0.id == card.id }) else { return }
        let placement = overridePlacement ?? card.placement
        switch card.kind {
        case .placementPreview, .branchProposal, .childBranchProposal:
            if let placement, placement.nodeType == .evidenceQualityInvestigation {
                createOperationalTask(from: card, placement: placement, type: .evidenceAudit)
                break
            }
            if let placement, placement.nodeType == .sourceSearchTask {
                createOperationalTask(from: card, placement: placement, type: .sourceSearch)
                break
            }
            if let placement, placement.nodeType == .lexiconTerm || placement.nodeType == .deepDiveCandidate {
                await saveExtract(from: card)
                break
            }
            let previousQuestion = activeQuestionUUID
            let newQuestion = await createPlacedQuestion(
                title: card.proposedQuestion ?? card.title,
                placement: placement ?? InquiryPlacementDecision(
                    nodeType: .branchQuestion,
                    parentQuestionUUID: card.parentQuestionUUID,
                    parentBranchNodeId: card.parentBranchNodeId,
                    relationshipType: .childOf,
                    confidence: .medium,
                    explanation: "Legacy branch proposal accepted as a child of the selected question.",
                    appearsInBranchMap: true
                ),
                originExtractUUID: card.originExtractUUID,
                sourceTabId: card.sourceTabId,
                makeActive: true
            )
            if let previousQuestion, previousQuestion != activeQuestionUUID {
                if !structured.uiState.pinnedQuestionUUIDs.contains(previousQuestion) {
                    structured.uiState.pinnedQuestionUUIDs.append(previousQuestion)
                }
            }
            structured.uiState.selectedInspectorQuestionUUID = activeQuestionUUID
            appendActivity(
                .init(
                    kind: .branchCreated,
                    title: "Branch created",
                    detail: newQuestion?.title,
                    questionUUID: newQuestion?.uuid,
                    sourceUUID: activeSourceTab?.sourceUUID,
                    routingCardId: card.id
                )
            )
        case .evidenceAudit:
            createOperationalTask(from: card, placement: placement, type: .evidenceAudit)
        case .sourceSearchTask, .sourceFinding:
            createOperationalTask(from: card, placement: placement, type: .sourceSearch)
        case .termCandidate, .deepDiveCandidate:
            await saveExtract(from: card)
        case .claimProposal, .evidenceProposal, .counterevidenceProposal, .mechanismProposal, .assumptionProposal, .sourceQualityWarning:
            await saveExtract(from: card)
        case .noteRoute, .modelUpdate:
            break
        }
        structured.routingCards[idx].status = .accepted
        scheduleSave()
    }

    private func createOperationalTask(from card: InquiryRoutingCard, placement: InquiryPlacementDecision?, type: InquiryOperationalTaskType) {
        let relationship: InquiryRelationshipType = placement?.relationshipType ?? (type == .evidenceAudit ? .evidenceAuditForClaim : .sourceSearchForQuestion)
        let tab = card.sourceTabId.flatMap { id in structured.sourceTabs.first { $0.id == id } } ?? activeSourceTab
        let task = InquiryOperationalTask(
            type: type,
            title: card.proposedQuestion ?? card.title,
            detail: card.detail,
            attachedQuestionUUID: placement?.parentQuestionUUID ?? card.parentQuestionUUID ?? activeQuestionUUID,
            attachedClaimExtractUUID: card.linkedClaimExtractUUID,
            sourceUUID: tab?.sourceUUID,
            sourceTabId: tab?.id,
            relationshipType: relationship,
            originExtractUUID: card.originExtractUUID
        )
        structured.operationalTasks.append(task)
        appendActivity(
            .init(
                kind: .routingSuggested,
                title: type == .evidenceAudit ? "Evidence task created" : "Source task created",
                detail: task.title,
                questionUUID: task.attachedQuestionUUID,
                sourceUUID: task.sourceUUID,
                routingCardId: card.id
            )
        )
        showToast(type == .evidenceAudit ? "Evidence task created" : "Source task created", detail: "Attached outside the Branch Map.")
    }

    func ignoreRoutingCard(_ card: InquiryRoutingCard) {
        guard let idx = structured.routingCards.firstIndex(where: { $0.id == card.id }) else { return }
        structured.routingCards[idx].status = .ignored
        appendActivity(
            .init(
                kind: .routingIgnored,
                title: "Routing ignored",
                detail: card.proposedQuestion ?? card.proposedExtractText,
                questionUUID: card.parentQuestionUUID,
                routingCardId: card.id
            )
        )
        scheduleSave()
    }

    private func saveExtract(from card: InquiryRoutingCard) async {
        let text = (card.proposedExtractText ?? card.detail ?? card.title).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let kind = card.proposedExtractKind ?? .aiInsight
        let tab = card.sourceTabId.flatMap { id in structured.sourceTabs.first { $0.id == id } } ?? activeSourceTab
        do {
            let extract = try await InquiryRepository.shared.createExtract(
                body: text,
                kind: kind,
                sourceUUID: tab?.sourceUUID,
                selectionRange: nil,
                sessionUUID: session.uuid,
                questionUUID: card.parentQuestionUUID ?? activeQuestionUUID,
                deepDiveUUID: deepDive?.uuid,
                branchNodeId: card.parentBranchNodeId ?? activeBranchNodeId,
                sourceTabId: tab?.id,
                userNote: nil,
                originType: "routing",
                citation: tab?.url ?? tab?.title
            )
            extracts.append(extract)
            if let sourceUUID = extract.extractMetadata?.sourceUUID,
               let refIdx = structured.sourceRefs.firstIndex(where: { $0.sourceUUID == sourceUUID }) {
                structured.sourceRefs[refIdx].extractCount += 1
            }
            let activityKind: InquiryActivityEvent.Kind = kind.isClaimLike ? .claimSaved : (kind.isEvidenceLike ? .evidenceSaved : .extractSaved)
            appendActivity(
                .init(
                    kind: activityKind,
                    title: "\(kind.displayName) saved",
                    detail: text,
                    questionUUID: card.parentQuestionUUID ?? activeQuestionUUID,
                    sourceUUID: tab?.sourceUUID,
                    extractUUID: extract.uuid,
                    routingCardId: card.id
                )
            )
            showToast("\(kind.displayName) saved", detail: "Added to Answer Forming")
        } catch {
            print("[InquiryWorkspaceVM] saveExtract(from:) failed: \(error)")
        }
    }

    /// Run an AI prompt via ResearchService. Records the interaction on completion.
    func runAIPrompt(_ prompt: String) async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        aiBusy = true
        defer { aiBusy = false }

        let context = buildAIContext()
        let fullPrompt = """
        \(context)

        Question from Euan: \(trimmed)

        Answer thoughtfully, drawing on the provided context. If you don't know, say so.
        """

        let response = await InquiryAICopilot.shared.ask(prompt: fullPrompt)
        recordAIInteraction(prompt: trimmed, response: response)
        routeThought(trimmed, originExtractUUID: nil, sourceTabId: activeSourceTabId)
        aiPromptDraft = ""
    }

    private func buildAIContext() -> String {
        var lines: [String] = []
        if let dd = deepDive, let title = dd.title {
            lines.append("You are inside the Deep Dive: \(title)")
            if let about = dd.body, !about.isEmpty {
                lines.append("About this Deep Dive: \(about)")
            }
            if let model = dd.deepDiveStructured?.currentUnderstanding.oneSentenceModel,
               !model.isEmpty {
                lines.append("Current understanding: \(model)")
            }
        }
        if let rq = rootQuestion, let qt = rq.title {
            lines.append("Root question: \(qt)")
        }
        if let activeQ = activeQuestion {
            lines.append("Active question: \(activeQ.title ?? activeQ.uuid)")
            lines.append("Active question status: \((activeQ.questionMetadata?.status ?? .open).displayName)")
        }
        if let source = activeSourceTab {
            lines.append("Current source: \(source.title)")
        }
        let activeClaims = claims(for: activeQuestionUUID).prefix(5).compactMap { $0.body ?? $0.title }
        if !activeClaims.isEmpty {
            lines.append("Current claims for active question:\n\(activeClaims.map { "- \($0)" }.joined(separator: "\n"))")
        }
        let activeEvidence = evidence(for: activeQuestionUUID).prefix(5).compactMap { $0.body ?? $0.title }
        if !activeEvidence.isEmpty {
            lines.append("Evidence/counterevidence for active question:\n\(activeEvidence.map { "- \($0)" }.joined(separator: "\n"))")
        }
        let pinned = pinnedQuestions().compactMap(\.title)
        if !pinned.isEmpty {
            lines.append("Pinned questions: \(pinned.joined(separator: "; "))")
        }
        let recent = structured.sessionCaptures.suffix(5).map { "- \($0.body.prefix(120))" }.joined(separator: "\n")
        if !recent.isEmpty {
            lines.append("Recent captures:\n\(recent)")
        }
        return lines.joined(separator: "\n")
    }

    private func branchQuestionTitle(from selection: String) -> String {
        let cleaned = selection
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = cleaned.count > 84 ? String(cleaned.prefix(84)) + "..." : cleaned
        if prefix.lowercased().hasPrefix("what") || prefix.hasSuffix("?") {
            return prefix
        }
        return "What does this reveal about \(prefix)?"
    }

    // MARK: - Pause / Save / Resume

    /// Persist pending changes immediately and mark the session paused.
    func pauseAndPersist() async {
        saveTask?.cancel()
        do {
            session = try await InquiryRepository.shared.saveSession(session, metadata: metadata, structured: structured)
            session = try await InquiryRepository.shared.pauseSession(session)
            metadata = session.inquirySessionMetadata ?? metadata
            structured = session.inquirySessionStructured ?? structured
            NotificationCenter.default.post(
                name: CosmoNotification.Inquiry.sessionEnded,
                object: nil,
                userInfo: ["sessionUUID": session.uuid]
            )
        } catch {
            print("[InquiryWorkspaceVM] pauseAndPersist failed: \(error)")
        }
    }

    /// Debounced save (500ms).
    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.persistNow()
        }
    }

    private func persistNow() async {
        do {
            metadata.lastActiveAt = ISO8601DateFormatter().string(from: Date())
            session = try await InquiryRepository.shared.saveSession(session, metadata: metadata, structured: structured)
            metadata = session.inquirySessionMetadata ?? metadata
            structured = session.inquirySessionStructured ?? structured
        } catch {
            print("[InquiryWorkspaceVM] persistNow failed: \(error)")
        }
    }
}

enum InquiryNotebookMode: String, CaseIterable {
    case notes
    case tree
    case captures
    case currentUnderstanding
    case localMap

    var title: String {
        switch self {
        case .notes: return "Notes"
        case .tree: return "Branch Map"
        case .captures: return "Captures"
        case .currentUnderstanding: return "Current Understanding"
        case .localMap: return "Local Map"
        }
    }
}

struct InquiryQuestionCounts: Equatable {
    var sources: Int
    var extracts: Int
    var notes: Int
    var claims: Int
    var evidence: Int
    var tasks: Int
    var children: Int

    var compactLabel: String {
        "S\(sources) · N\(notes) · C\(claims) · Ev\(evidence) · T\(tasks) · Q\(children)"
    }
}
