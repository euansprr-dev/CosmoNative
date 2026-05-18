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
    var aiBusy: Bool = false
    var isRefreshingSources: Bool = false
    var sourceActivityLine: String?
    var toast: InquiryToast?

    // New shell ("Stele" redesign) UI state
    var activeReaderSourceId: String?           // when non-nil, center morphs into reader
    var isMapOverlayPresented: Bool = false     // Cmd+M full-screen map overlay
    var ephemeralAIReplies: [EphemeralAIReplyCard] = []
    var liveUnderstandingIsForming: Bool = false
    var liveUnderstandingError: String?
    private var liveUnderstandingDebounceTask: Task<Void, Never>?
    private var ephemeralEvictionTasks: [String: Task<Void, Never>] = [:]

    // Captures (in-memory until commit/crystallize)
    var captures: [SessionCapture] {
        get { structured.sessionCaptures }
        set { structured.sessionCaptures = newValue }
    }

    // Persistence
    private var saveTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var sourceActivityTask: Task<Void, Never>?

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
        await refreshSourceRecommendationsIfNeeded()
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

    // MARK: - Phase (Stele shell)

    /// Two-phase mode used by the new shell.
    var phase: InquiryPhase {
        get { InquiryPhase(layoutMode: metadata.layoutMode) }
        set { setPhase(newValue) }
    }

    func setPhase(_ phase: InquiryPhase) {
        let mode = phase.persistedLayoutMode
        guard metadata.layoutMode != mode else { return }
        metadata.layoutMode = mode
        scheduleSave()
    }

    // MARK: - Reader morph

    func openReader(sourceTabId: String) {
        activeSourceTabId = sourceTabId
        activeReaderSourceId = sourceTabId
    }

    func openReader(forSourceRef ref: InquirySourceRef) {
        if let tabId = ref.tabId, structured.sourceTabs.contains(where: { $0.id == tabId }) {
            openReader(sourceTabId: tabId)
            return
        }
        reopenSource(ref)
        if let id = activeSourceTabId {
            activeReaderSourceId = id
        }
    }

    func dismissReader() {
        activeReaderSourceId = nil
    }

    // MARK: - Map overlay

    func presentMap() { isMapOverlayPresented = true }
    func dismissMap() { isMapOverlayPresented = false }
    func toggleMap() { isMapOverlayPresented.toggle() }

    // MARK: - Ephemeral AI replies

    /// Append a transient AI reply card above the dock. Auto-fades after `lifetime` seconds.
    func appendEphemeralAIReply(_ text: String, kind: EphemeralAIReplyCard.Kind = .reply, lifetime: TimeInterval = 18) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let card = EphemeralAIReplyCard(kind: kind, text: trimmed)
        ephemeralAIReplies.append(card)
        if ephemeralAIReplies.count > 3 {
            let evicted = ephemeralAIReplies.removeFirst()
            ephemeralEvictionTasks[evicted.id]?.cancel()
            ephemeralEvictionTasks[evicted.id] = nil
        }
        let id = card.id
        ephemeralEvictionTasks[id]?.cancel()
        ephemeralEvictionTasks[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(lifetime * 1_000_000_000))
            await MainActor.run {
                guard let self else { return }
                self.ephemeralAIReplies.removeAll { $0.id == id }
                self.ephemeralEvictionTasks[id] = nil
            }
        }
    }

    func dismissEphemeralReply(_ id: String) {
        ephemeralEvictionTasks[id]?.cancel()
        ephemeralEvictionTasks[id] = nil
        ephemeralAIReplies.removeAll { $0.id == id }
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
        guard let id = activeSourceTabId else { return nil }
        return structured.sourceTabs.first { $0.id == id }
    }

    var activeRecommendationBatch: InquiryRecommendationBatch? {
        activeRecommendationBatchIndex.map { structured.recommendationBatches[$0] }
    }

    var activeSourceCandidates: [InquirySourceCandidate] {
        guard let batch = activeRecommendationBatch else { return [] }
        return batch.candidates
            .filter { !batch.dismissedCandidateIds.contains($0.id) && $0.importStatus != .dismissed }
            .sorted {
                if $0.importStatus == $1.importStatus {
                    return $0.score > $1.score
                }
                return $0.importStatus != .imported && $1.importStatus == .imported
            }
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
        scheduleLiveUnderstandingRefresh(reason: .questionSwitched)
        Task { [weak self] in
            await self?.refreshSourceRecommendationsIfNeeded()
        }
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

    func notebookItems(for questionUUID: String?) -> [Atom] {
        extracts(for: questionUUID, kinds: Set(ExtractKind.allCases))
            .filter { $0.extractMetadata?.status != .ignored }
    }

    func sourceTitle(for sourceUUID: String?) -> String? {
        guard let sourceUUID else { return nil }
        if let ref = structured.sourceRefs.first(where: { $0.sourceUUID == sourceUUID }) {
            return ref.title
        }
        return structured.sourceTabs.first(where: { $0.sourceUUID == sourceUUID })?.title
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
        defer {
            if let kind = extract.extractMetadata?.kind,
               kind.isClaimLike || kind.isEvidenceLike || kind == .note {
                scheduleLiveUnderstandingRefresh(reason: .extractSaved)
            }
        }
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
        let detectedIntent: CaptureIntent
        if let suggestedKind {
            detectedIntent = CaptureIntent(kind: suggestedKind, confidence: 1.0, reason: "Explicit route")
        } else {
            detectedIntent = CaptureIntentClassifier.classifyHeuristic(
                text: trimmed,
                context: InquiryPlacementEngine.Context(
                    deepDiveTitle: deepDive?.title,
                    activeQuestion: activeQuestion,
                    activeQuestionUUID: activeQuestionUUID,
                    activeBranchNodeId: activeBranchNodeId,
                    sourceTabId: activeSourceTabId,
                    originExtractUUID: nil,
                    originAction: .manualAdd,
                    questions: questions,
                    claims: claims(for: activeQuestionUUID)
                )
            )
        }
        let capture = SessionCapture(
            body: trimmed,
            source: source,
            suggestedKind: detectedIntent.kind,
            suggestedKindConfidence: detectedIntent.confidence,
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

    @discardableResult
    func promoteCaptureToBranch(captureId: String) async -> Atom? {
        guard let idx = structured.sessionCaptures.firstIndex(where: { $0.id == captureId }) else { return nil }
        let capture = structured.sessionCaptures[idx]
        guard capture.status == .pending else { return nil }

        if capture.attachedQuestionId != activeQuestionUUID {
            setActiveQuestion(capture.attachedQuestionId, branchNodeId: questionNodeId(for: capture.attachedQuestionId))
        }

        let question = await createChildQuestion(
            title: capture.body,
            originExtractUUID: nil,
            sourceTabId: capture.attachedSourceTabId,
            makeActive: true
        )
        if let question {
            structured.sessionCaptures[idx].status = .committed
            structured.sessionCaptures[idx].promotedToAtomUUID = question.uuid
            appendRouteReceipt(
                InquiryRouteReceipt(
                    kind: .branchCreated,
                    message: "Created branch",
                    detail: question.title,
                    questionUUID: question.uuid,
                    branchNodeId: questionNodeId(for: question.uuid)
                )
            )
            scheduleSave()
        }
        return question
    }

    @discardableResult
    func commitCaptureWith(captureId: String, kind: ExtractKind) async -> String? {
        await commitCapture(captureId, kind: kind)
    }

    func discardCapture(_ captureId: String) {
        if let idx = structured.sessionCaptures.firstIndex(where: { $0.id == captureId }) {
            structured.sessionCaptures[idx].status = .discarded
            scheduleSave()
        }
    }

    // MARK: - Sources

    private var activeRecommendationBatchIndex: Int? {
        let matching = structured.recommendationBatches.enumerated().filter { _, batch in
            batch.branchNodeId == activeBranchNodeId || batch.questionUUID == activeQuestionUUID
        }
        return matching.max { lhs, rhs in
            lhs.element.generatedAt < rhs.element.generatedAt
        }?.offset
    }

    func refreshSourceRecommendationsIfNeeded() async {
        guard activeRecommendationBatch == nil else { return }
        await refreshSourceRecommendations()
    }

    func refreshSourceRecommendations(
        query: String? = nil,
        mode: InquirySourceSearchMode = .quick
    ) async {
        guard !isRefreshingSources else { return }
        isRefreshingSources = true
        defer { isRefreshingSources = false }

        let focusedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let profile = branchResearchProfile(sourceQuery: focusedQuery)
        startSourceActivity(plan: InquirySourceRecommendationEngine.activityPlan(for: profile, mode: mode))

        let localSources = (try? await AtomRepository.shared.fetchAll(type: .research)) ?? []
        let batch = await InquirySourceRecommendationEngine.shared.recommend(
            profile: profile,
            existingSourceRefs: structured.sourceRefs,
            localSources: localSources,
            searchMode: mode
        )

        structured.recommendationBatches.removeAll { existing in
            existing.branchNodeId == batch.branchNodeId || existing.questionUUID == batch.questionUUID
        }
        structured.recommendationBatches.append(batch)
        appendRouteReceipt(
            InquiryRouteReceipt(
                kind: .sourceRefreshed,
                message: mode == .deepScout ? "Deep Scout completed" : "Source Radar refreshed",
                detail: "\(batch.candidates.count) candidates for \(focusedQuery ?? activeQuestionTitle)",
                questionUUID: activeQuestionUUID,
                branchNodeId: activeBranchNodeId
            )
        )
        finishSourceActivity(
            mode == .deepScout
                ? "Deep Scout ranked \(batch.candidates.count) source candidates"
                : "Source Radar found \(batch.candidates.count) source candidates"
        )
        scheduleSave()
    }

    func importSourceCandidate(_ candidate: InquirySourceCandidate) async {
        if let sourceUUID = candidate.importedSourceUUID,
           let source = try? await AtomRepository.shared.fetch(uuid: sourceUUID) {
            let tab = openSourceAtom(source, url: source.url ?? candidate.url, title: candidate.title, kind: candidate.sourceKind == .localNote ? .internalAtom : .web)
            markCandidate(candidate.id, status: .imported, sourceUUID: source.uuid)
            activeSourceTabId = tab.id
            appendRouteReceipt(
                InquiryRouteReceipt(
                    kind: .sourceImported,
                    message: "Opened library source",
                    detail: candidate.title,
                    questionUUID: activeQuestionUUID,
                    branchNodeId: activeBranchNodeId,
                    sourceUUID: source.uuid,
                    candidateId: candidate.id
                )
            )
            scheduleSave()
            return
        }

        guard let rawURL = candidate.url, !rawURL.isEmpty else {
            queueSourceCandidate(candidate)
            showToast("Queued source", detail: "No direct URL was available.")
            return
        }

        let canonical = InquiryRepository.shared.canonicalURL(rawURL)
        do {
            let source = try await InquiryRepository.shared.createOrFindURLSource(
                urlString: canonical,
                title: candidate.title,
                sourceType: candidate.sourceKind.rawValue
            )
            let tab = openSourceAtom(source, url: canonical, title: candidate.title, kind: sourceTabKind(for: candidate))
            markCandidate(candidate.id, status: .imported, sourceUUID: source.uuid)
            activeSourceTabId = tab.id
            appendActivity(
                .init(
                    kind: .sourceOpened,
                    title: "Source imported",
                    detail: candidate.title,
                    questionUUID: activeQuestionUUID,
                    sourceUUID: source.uuid
                )
            )
            appendRouteReceipt(
                InquiryRouteReceipt(
                    kind: .sourceImported,
                    message: "Imported source",
                    detail: candidate.title,
                    questionUUID: activeQuestionUUID,
                    branchNodeId: activeBranchNodeId,
                    sourceUUID: source.uuid,
                    candidateId: candidate.id
                )
            )
            showToast("Source imported", detail: "Attached to \(activeQuestionTitle)")
            scheduleSave()
        } catch {
            print("[InquiryWorkspaceVM] importSourceCandidate failed: \(error)")
            showToast("Import failed", detail: error.localizedDescription)
        }
    }

    func queueSourceCandidate(_ candidate: InquirySourceCandidate) {
        updateActiveRecommendationBatch { batch in
            if !batch.queuedCandidateIds.contains(candidate.id) {
                batch.queuedCandidateIds.append(candidate.id)
            }
            if let idx = batch.candidates.firstIndex(where: { $0.id == candidate.id }) {
                batch.candidates[idx].importStatus = .queued
            }
        }
        if !structured.operationalTasks.contains(where: { $0.title == candidate.title && $0.attachedQuestionUUID == activeQuestionUUID }) {
            structured.operationalTasks.append(
                InquiryOperationalTask(
                    type: .sourceSearch,
                    title: candidate.title,
                    detail: candidate.reason,
                    attachedQuestionUUID: activeQuestionUUID,
                    sourceUUID: candidate.importedSourceUUID,
                    relationshipType: .sourceSearchForQuestion
                )
            )
        }
        appendRouteReceipt(
            InquiryRouteReceipt(
                kind: .sourceQueued,
                message: "Queued source",
                detail: candidate.title,
                questionUUID: activeQuestionUUID,
                branchNodeId: activeBranchNodeId,
                sourceUUID: candidate.importedSourceUUID,
                candidateId: candidate.id
            )
        )
        showToast("Queued source", detail: "Added to research tasks.")
        scheduleSave()
    }

    func dismissSourceCandidate(_ candidate: InquirySourceCandidate) {
        updateActiveRecommendationBatch { batch in
            if !batch.dismissedCandidateIds.contains(candidate.id) {
                batch.dismissedCandidateIds.append(candidate.id)
            }
            if let idx = batch.candidates.firstIndex(where: { $0.id == candidate.id }) {
                batch.candidates[idx].importStatus = .dismissed
            }
        }
        scheduleSave()
    }

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
            appendRouteReceipt(
                InquiryRouteReceipt(
                    kind: .sourceOpened,
                    message: "Opened source",
                    detail: title,
                    questionUUID: activeQuestionUUID,
                    branchNodeId: activeBranchNodeId,
                    sourceUUID: source.uuid
                )
            )
            showToast("Source captured", detail: "Attached to \(activeQuestionTitle)")
            scheduleSave()
        } catch {
            print("[InquiryWorkspaceVM] openURLSource failed: \(error)")
        }
    }

    /// Notify the live understanding engine when a source is imported/opened.
    private func noteSourceChanged() {
        scheduleLiveUnderstandingRefresh(reason: .sourceImported)
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
            activeSourceTabId = nil
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

    private func upsertInternalSourceRef(for source: Atom, tab: SourceTab, title: String) {
        let now = ISO8601DateFormatter().string(from: Date())
        if let idx = structured.sourceRefs.firstIndex(where: { $0.sourceUUID == source.uuid }) {
            structured.sourceRefs[idx].tabId = tab.id
            structured.sourceRefs[idx].title = source.title ?? title
            structured.sourceRefs[idx].status = .viewed
            structured.sourceRefs[idx].primaryQuestionUUID = activeQuestionUUID
            structured.sourceRefs[idx].primaryNodeId = activeBranchNodeId
            structured.sourceRefs[idx].lastOpenedAt = now
        } else {
            structured.sourceRefs.append(
                InquirySourceRef(
                    sourceUUID: source.uuid,
                    tabId: tab.id,
                    url: source.url,
                    title: source.title ?? title,
                    domain: source.url.flatMap { URL(string: $0)?.host },
                    sourceType: source.type.rawValue,
                    primaryQuestionUUID: activeQuestionUUID,
                    primaryNodeId: activeBranchNodeId,
                    openedAt: now,
                    lastOpenedAt: now
                )
            )
        }
    }

    private func openSourceAtom(_ source: Atom, url: String?, title: String, kind: SourceTab.Kind) -> SourceTab {
        if let existing = structured.sourceTabs.first(where: { $0.sourceUUID == source.uuid }) {
            return existing
        }
        let tab = SourceTab(
            kind: kind,
            sourceUUID: source.uuid,
            url: url,
            title: source.title ?? title,
            attachedQuestionUUID: activeQuestionUUID,
            attachedNodeId: activeBranchNodeId
        )
        structured.sourceTabs.append(tab)
        if let url, !url.isEmpty {
            upsertSourceRef(for: source, tab: tab, url: url, title: title)
        } else {
            upsertInternalSourceRef(for: source, tab: tab, title: title)
        }
        return tab
    }

    private func sourceTabKind(for candidate: InquirySourceCandidate) -> SourceTab.Kind {
        switch candidate.sourceKind {
        case .video: return .youTube
        case .localNote: return .internalAtom
        default: return .web
        }
    }

    private func branchResearchProfile(sourceQuery: String? = nil) -> InquiryBranchResearchProfile {
        InquiryBranchResearchProfile(
            deepDiveTitle: deepDive?.title,
            activeQuestionTitle: activeQuestionTitle,
            activeQuestionUUID: activeQuestionUUID,
            branchNodeId: activeBranchNodeId,
            ancestorTitles: activeQuestion.map { questionAncestors(for: $0).compactMap(\.title) } ?? [],
            claims: claims(for: activeQuestionUUID).compactMap { $0.body ?? $0.title },
            evidence: evidence(for: activeQuestionUUID).compactMap { $0.body ?? $0.title },
            sourceQuery: sourceQuery
        )
    }

    private func updateActiveRecommendationBatch(_ update: (inout InquiryRecommendationBatch) -> Void) {
        guard let idx = activeRecommendationBatchIndex else { return }
        update(&structured.recommendationBatches[idx])
    }

    private func markCandidate(_ candidateId: String, status: InquirySourceImportStatus, sourceUUID: String? = nil) {
        updateActiveRecommendationBatch { batch in
            if let idx = batch.candidates.firstIndex(where: { $0.id == candidateId }) {
                batch.candidates[idx].importStatus = status
                batch.candidates[idx].importedSourceUUID = sourceUUID ?? batch.candidates[idx].importedSourceUUID
            }
            if status == .imported && !batch.importedCandidateIds.contains(candidateId) {
                batch.importedCandidateIds.append(candidateId)
            }
            if status == .queued && !batch.queuedCandidateIds.contains(candidateId) {
                batch.queuedCandidateIds.append(candidateId)
            }
            if status == .dismissed && !batch.dismissedCandidateIds.contains(candidateId) {
                batch.dismissedCandidateIds.append(candidateId)
            }
        }
    }

    private func startSourceActivity(plan: [String]) {
        sourceActivityTask?.cancel()
        let steps = plan.isEmpty ? ["Searching sources"] : plan
        sourceActivityLine = steps[0]
        guard steps.count > 1 else { return }

        sourceActivityTask = Task { [weak self] in
            var index = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_150_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    index = (index + 1) % steps.count
                    self.sourceActivityLine = steps[index]
                }
            }
        }
    }

    private func finishSourceActivity(_ finalLine: String) {
        sourceActivityTask?.cancel()
        sourceActivityTask = nil
        sourceActivityLine = finalLine

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run {
                guard let self,
                      !self.isRefreshingSources,
                      self.sourceActivityLine == finalLine else { return }
                self.sourceActivityLine = nil
            }
        }
    }

    func submitDockText(_ raw: String) async {
        let parsed = InquiryDockPrefixParser.parse(raw)
        let body = parsed.body.trimmingCharacters(in: .whitespacesAndNewlines)

        switch parsed.intent {
        case .refreshSources:
            await refreshSourceRecommendations(query: body.nilIfEmpty)
        case .openSource:
            await openURLSource(body)
        case .source:
            if InquiryDockPrefixParser.looksLikeURL(body) {
                await openURLSource(body)
            } else {
                createSourceSearchTask(body)
                await refreshSourceRecommendations(query: body)
            }
        case .deepScout:
            createSourceSearchTask(body.isEmpty ? activeQuestionTitle : body)
            await refreshSourceRecommendations(query: body.nilIfEmpty, mode: .deepScout)
        case .rootQuestion:
            await createRootLikeQuestion(body)
        case .branchQuestion:
            guard !body.isEmpty else { return }
            if let question = await createChildQuestion(title: body) {
                appendRouteReceipt(
                    InquiryRouteReceipt(
                        kind: .branchCreated,
                        message: "Created branch",
                        detail: question.title,
                        questionUUID: question.uuid,
                        branchNodeId: questionNodeId(for: question.uuid)
                    )
                )
            }
        case .question:
            await createPlacedQuestionFromDock(body)
        case .challenge:
            createEvidenceChallengeTask(body)
        case .summarize:
            await summarizeFromDock(body)
        case .note, .claim, .speculativeClaim, .evidence, .counterevidence, .term, .practice, .output:
            guard let kind = parsed.extractKind else { return }
            await saveDockExtract(body, kind: kind, originType: parsed.intent.rawValue)
        case .ask:
            let intent = CaptureIntentClassifier.classifyHeuristic(
                text: body,
                context: InquiryPlacementEngine.Context(
                    deepDiveTitle: deepDive?.title,
                    activeQuestion: activeQuestion,
                    activeQuestionUUID: activeQuestionUUID,
                    activeBranchNodeId: activeBranchNodeId,
                    sourceTabId: activeSourceTabId,
                    originExtractUUID: nil,
                    originAction: .manualAdd,
                    questions: questions,
                    claims: claims(for: activeQuestionUUID)
                )
            )
            if intent.kind == .question && intent.confidence >= 0.7 {
                addCapture(body, source: .type, suggestedKind: .question)
                showToast("Captured question", detail: "Make it a branch from the notes rail.")
            } else {
                await saveDockExtract(body, kind: .note, originType: "dock")
            }
        }
    }

    @discardableResult
    private func saveDockExtract(_ raw: String, kind: ExtractKind, originType: String) async -> Atom? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            let extract = try await InquiryRepository.shared.createExtract(
                body: trimmed,
                kind: kind,
                sourceUUID: activeSourceTab?.sourceUUID,
                selectionRange: nil,
                sessionUUID: session.uuid,
                questionUUID: activeQuestionUUID,
                deepDiveUUID: deepDive?.uuid,
                branchNodeId: activeBranchNodeId,
                sourceTabId: activeSourceTabId,
                userNote: nil,
                originType: originType,
                citation: activeSourceTab?.url ?? activeSourceTab?.title
            )
            registerSavedExtract(extract, sourceTabId: activeSourceTabId)
            appendRouteReceipt(
                InquiryRouteReceipt(
                    kind: kind == .note ? .noteSaved : .extractSaved,
                    message: "\(kind.displayName) saved",
                    detail: "Routed to \(activeQuestionTitle)",
                    questionUUID: activeQuestionUUID,
                    branchNodeId: activeBranchNodeId,
                    sourceUUID: activeSourceTab?.sourceUUID,
                    extractUUID: extract.uuid
                )
            )
            routeThought(trimmed, originExtractUUID: extract.uuid, sourceTabId: activeSourceTabId)
            showToast("\(kind.displayName) saved", detail: "Routed to \(activeQuestionTitle)")
            scheduleSave()
            return extract
        } catch {
            print("[InquiryWorkspaceVM] saveDockExtract failed: \(error)")
            showToast("Save failed", detail: error.localizedDescription)
            return nil
        }
    }

    private func createRootLikeQuestion(_ raw: String) async {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let placement = InquiryPlacementDecision(
            nodeType: .rootQuestion,
            parentQuestionUUID: nil,
            parentBranchNodeId: nil,
            relationshipType: .rootUnderTopic,
            confidence: .high,
            explanation: "Created from the Thinking Dock as a root-level inquiry question.",
            requiresApproval: false,
            appearsInBranchMap: true
        )
        let question = await createPlacedQuestion(title: title, placement: placement, makeActive: true)
        appendRouteReceipt(
            InquiryRouteReceipt(
                kind: .branchCreated,
                message: "Created root question",
                detail: question?.title,
                questionUUID: question?.uuid,
                branchNodeId: question.flatMap { questionNodeId(for: $0.uuid) }
            )
        )
    }

    private func createPlacedQuestionFromDock(_ raw: String) async {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let placement = InquiryPlacementEngine.placement(
            for: title,
            fullText: title,
            context: InquiryPlacementEngine.Context(
                deepDiveTitle: deepDive?.title,
                activeQuestion: activeQuestion,
                activeQuestionUUID: activeQuestionUUID,
                activeBranchNodeId: activeBranchNodeId,
                sourceTabId: activeSourceTabId,
                originExtractUUID: nil,
                originAction: .manualAdd,
                questions: questions,
                claims: claims(for: activeQuestionUUID)
            )
        )
        let question = await createPlacedQuestion(title: title, placement: placement, makeActive: true)
        appendRouteReceipt(
            InquiryRouteReceipt(
                kind: .branchCreated,
                message: placement.nodeType == .rootQuestion ? "Created root question" : "Created branch",
                detail: question?.title,
                questionUUID: question?.uuid,
                branchNodeId: question.flatMap { questionNodeId(for: $0.uuid) }
            )
        )
    }

    private func createSourceSearchTask(_ raw: String) {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Find stronger sources for \(activeQuestionTitle)"
        structured.operationalTasks.append(
            InquiryOperationalTask(
                type: .sourceSearch,
                title: title,
                detail: "Created from the Thinking Dock.",
                attachedQuestionUUID: activeQuestionUUID,
                relationshipType: .sourceSearchForQuestion
            )
        )
        appendRouteReceipt(
            InquiryRouteReceipt(
                kind: .sourceQueued,
                message: "Created source task",
                detail: title,
                questionUUID: activeQuestionUUID,
                branchNodeId: activeBranchNodeId
            )
        )
        scheduleSave()
    }

    private func createEvidenceChallengeTask(_ raw: String) {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Challenge the evidence for \(activeQuestionTitle)"
        structured.operationalTasks.append(
            InquiryOperationalTask(
                type: .evidenceAudit,
                title: title,
                detail: "Look for stronger support, limitations, replications, and counterevidence.",
                attachedQuestionUUID: activeQuestionUUID,
                relationshipType: .evidenceAuditForClaim
            )
        )
        appendRouteReceipt(
            InquiryRouteReceipt(
                kind: .sourceQueued,
                message: "Created evidence challenge",
                detail: title,
                questionUUID: activeQuestionUUID,
                branchNodeId: activeBranchNodeId
            )
        )
        scheduleSave()
    }

    private func summarizeFromDock(_ raw: String) async {
        let target = activeSourceTab?.title ?? activeQuestionTitle
        let extra = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        await runAIPrompt("Summarize \(target). Focus on claims, evidence, counterevidence, mechanisms, and what should be routed into the active inquiry. \(extra)")
        appendRouteReceipt(
            InquiryRouteReceipt(
                kind: .aiAsked,
                message: "Summarized context",
                detail: target,
                questionUUID: activeQuestionUUID,
                branchNodeId: activeBranchNodeId,
                sourceUUID: activeSourceTab?.sourceUUID
            )
        )
        scheduleSave()
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

    private func appendRouteReceipt(_ receipt: InquiryRouteReceipt) {
        structured.routeReceipts.append(receipt)
        if structured.routeReceipts.count > 16 {
            structured.routeReceipts.removeFirst(structured.routeReceipts.count - 16)
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
        let kind = ephemeralKind(forPrompt: prompt)
        appendEphemeralAIReply(response, kind: kind)
        scheduleSave()
    }

    private func ephemeralKind(forPrompt prompt: String) -> EphemeralAIReplyCard.Kind {
        let lower = prompt.lowercased()
        if lower.contains("summari") { return .summary }
        if lower.contains("challenge") || lower.contains("counter") { return .challenge }
        if lower.contains("branch") || lower.contains("propose") { return .routing }
        return .reply
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

    // MARK: - Selection → Extract (called by reader's SelectionMiniMenu)

    @discardableResult
    func saveSelectionAsExtract(_ selection: String, kind: ExtractKind, sourceTab: SourceTab) async -> Atom? {
        let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            let extract = try await InquiryRepository.shared.createExtract(
                body: trimmed,
                kind: kind,
                sourceUUID: sourceTab.sourceUUID,
                selectionRange: nil,
                sessionUUID: session.uuid,
                questionUUID: activeQuestionUUID,
                deepDiveUUID: deepDive?.uuid,
                branchNodeId: activeBranchNodeId,
                sourceTabId: sourceTab.id,
                userNote: nil,
                originType: "selection",
                citation: sourceTab.url ?? sourceTab.title
            )
            registerSavedExtract(extract, sourceTabId: sourceTab.id)
            appendRouteReceipt(
                InquiryRouteReceipt(
                    kind: kind == .note ? .noteSaved : .extractSaved,
                    message: "\(kind.displayName) saved",
                    detail: "Routed to \(activeQuestionTitle)",
                    questionUUID: activeQuestionUUID,
                    branchNodeId: activeBranchNodeId,
                    sourceUUID: sourceTab.sourceUUID,
                    extractUUID: extract.uuid
                )
            )
            showToast("\(kind.displayName) saved", detail: "From \(sourceTab.title)")
            scheduleLiveUnderstandingRefresh(reason: .extractSaved)
            scheduleSave()
            return extract
        } catch {
            print("[InquiryWorkspaceVM] saveSelectionAsExtract failed: \(error)")
            showToast("Save failed", detail: error.localizedDescription)
            return nil
        }
    }

    // MARK: - Live Understanding (debounced auto-regenerate + manual trigger)

    enum LiveUnderstandingRefreshReason: String, Sendable {
        case capture
        case extractSaved
        case sourceImported
        case questionSwitched
        case manual
    }

    func scheduleLiveUnderstandingRefresh(reason: LiveUnderstandingRefreshReason) {
        let immediate = (reason == .questionSwitched || reason == .manual)
        liveUnderstandingDebounceTask?.cancel()
        liveUnderstandingDebounceTask = Task { [weak self] in
            if !immediate {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            }
            guard !Task.isCancelled, let self else { return }
            await self.regenerateLiveUnderstanding(force: immediate)
        }
    }

    @discardableResult
    func regenerateLiveUnderstanding(force: Bool = false) async -> Bool {
        let input = liveUnderstandingInput()
        let signature = InquiryUnderstandingEngine.shared.signature(for: input)
        if !force, let existing = structured.currentUnderstandingDraft, existing.contextSignature == signature, !existing.text.isEmpty {
            return false
        }
        liveUnderstandingIsForming = true
        liveUnderstandingError = nil
        let output = await InquiryUnderstandingEngine.shared.brief(input)
        liveUnderstandingIsForming = false
        let trimmed = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            liveUnderstandingError = "No synthesis yet — try again when more is captured."
            return false
        }
        structured.currentUnderstandingDraft = LiveUnderstandingDraft(
            text: trimmed,
            contextSignature: signature,
            modelTier: output.modelTier
        )
        scheduleSave()
        return true
    }

    private func liveUnderstandingInput() -> InquiryUnderstandingEngine.Input {
        let claimAtoms = claims(for: activeQuestionUUID)
        let evidenceAtoms = evidence(for: activeQuestionUUID)
        return InquiryUnderstandingEngine.Input(
            deepDiveTitle: deepDive?.title,
            deepDiveModel: deepDive?.deepDiveStructured?.currentUnderstanding.oneSentenceModel,
            activeQuestionTitle: activeQuestionTitle,
            claims: claimAtoms.filter { $0.extractMetadata?.kind == .claim }.compactMap { $0.body ?? $0.title }.prefix(8).map { $0 },
            speculativeClaims: claimAtoms.filter { $0.extractMetadata?.kind == .speculativeClaim }.compactMap { $0.body ?? $0.title }.prefix(6).map { $0 },
            evidence: evidenceAtoms.filter { $0.extractMetadata?.kind == .evidence }.compactMap { $0.body ?? $0.title }.prefix(6).map { $0 },
            counterevidence: evidenceAtoms.filter { $0.extractMetadata?.kind == .counterevidence }.compactMap { $0.body ?? $0.title }.prefix(4).map { $0 },
            recentCaptures: structured.sessionCaptures.suffix(6).map { $0.body },
            recentSourceTitles: structured.sourceRefs
                .filter { $0.status != .archived && $0.status != .deleted }
                .sorted { $0.lastOpenedAt > $1.lastOpenedAt }
                .prefix(5)
                .map { $0.title }
        )
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
        case .notes: return "Notebook"
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
