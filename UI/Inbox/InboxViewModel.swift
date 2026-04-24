// CosmoOS/UI/Inbox/InboxViewModel.swift
// State management for the Smart Triage Inbox — @Observable, temporal grouping,
// filtering, batch actions, keyboard nav, quick capture, intelligence
// March 2026

import SwiftUI
import Combine

@Observable
@MainActor
final class InboxViewModel {

    // MARK: - Items & Sections

    var items: [InboxItem] = []
    var groupedItems: [InboxSection] = []
    var stats: InboxStats = .empty

    // MARK: - Filtering & Sorting

    var activeSourceFilter: InboxSource?
    var activeClassificationFilter: InboxClassification?
    var sortOrder: InboxSortOrder = .newestFirst

    var hasActiveFilters: Bool {
        activeSourceFilter != nil || activeClassificationFilter != nil
    }

    // MARK: - Selection & Batch

    var selectedItemIds: Set<String> = []
    var isMultiSelectActive: Bool { !selectedItemIds.isEmpty }
    var focusedItemId: String?

    // MARK: - Quick Capture

    var captureText: String = ""
    var isCaptureExpanded: Bool = false
    var showCaptureConfirmation: Bool = false

    // MARK: - Intelligence

    var itemInsights: [String: String] = [:]
    var itemGroups: [InboxItemGroup] = []

    // MARK: - Override Sheet

    var overrideItem: InboxItem?
    var showOverrideSheet: Bool = false
    var overrideSearchResults: [HybridSearchEngine.SearchResult] = []

    // MARK: - Processing

    var processingItemIds: Set<String> = []

    // MARK: - Empty State

    var recentHistory: [InboxItem] = []
    var triagedThisWeek: Int = 0

    // MARK: - Undo Toast

    var showUndoToast: Bool = false
    var undoToastMessage: String = ""

    // MARK: - Expanded Cards

    var expandedItemIds: Set<String> = []

    // MARK: - Private

    private let inboxRepo = InboxRepository.shared
    private let executor = InboxActionExecutor.shared
    private var cancellables = Set<AnyCancellable>()
    private var intelligenceTask: Task<Void, Never>?
    private var undoToastTask: Task<Void, Never>?

    var thinkspaces: [Thinkspace] {
        ThinkspaceManager.shared.thinkspaces
    }

    // MARK: - Init

    init() {
        startObserving()
        loadEmptyStateData()
    }

    // MARK: - Observation

    private func startObserving() {
        inboxRepo.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newItems in
                guard let self else { return }
                self.items = newItems
                self.stats = InboxStats(items: newItems)
                self.regroupItems()
                self.runIntelligence()
            }
            .store(in: &cancellables)
    }

    // MARK: - Temporal Grouping

    private func regroupItems() {
        let filtered = filteredAndSorted
        let calendar = Calendar.current
        let now = Date()
        let formatter = ISO8601DateFormatter()

        var today: [InboxItem] = []
        var yesterday: [InboxItem] = []
        var thisWeek: [InboxItem] = []
        var older: [InboxItem] = []

        for item in filtered {
            guard let date = formatter.date(from: item.createdAt) else {
                older.append(item)
                continue
            }
            if calendar.isDateInToday(date) { today.append(item) }
            else if calendar.isDateInYesterday(date) { yesterday.append(item) }
            else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) { thisWeek.append(item) }
            else { older.append(item) }
        }

        groupedItems = [
            today.isEmpty ? nil : InboxSection(id: "today", title: "Today", items: today),
            yesterday.isEmpty ? nil : InboxSection(id: "yesterday", title: "Yesterday", items: yesterday),
            thisWeek.isEmpty ? nil : InboxSection(id: "thisWeek", title: "This Week", items: thisWeek),
            older.isEmpty ? nil : InboxSection(id: "older", title: "Older", items: older),
        ].compactMap { $0 }
    }

    private var filteredAndSorted: [InboxItem] {
        var result = items

        if let source = activeSourceFilter {
            result = result.filter { $0.source == source }
        }
        if let classification = activeClassificationFilter {
            result = result.filter { $0.classification == classification }
        }

        switch sortOrder {
        case .newestFirst:
            break // already sorted desc by repo
        case .oldestFirst:
            result.reverse()
        case .byConfidence:
            result.sort { $0.confidence > $1.confidence }
        case .byPriority:
            result.sort { $0.priorityScore > $1.priorityScore }
        }

        return result
    }

    // MARK: - Quick Capture

    func submitCapture() async {
        let text = captureText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        captureText = ""
        isCaptureExpanded = false

        let item = InboxItem.new(
            source: .quickCapture,
            rawText: text
        )

        do {
            let saved = try await inboxRepo.create(item)

            // Show confirmation
            showCaptureConfirmation = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                showCaptureConfirmation = false
            }

            // Classify async
            let classification = await InboxClassificationEngine.shared.classify(
                text: text,
                source: .quickCapture
            )

            try await inboxRepo.updateClassification(
                uuid: saved.uuid,
                classification: classification.classification,
                confidence: classification.confidence,
                title: classification.title,
                mergeTargetUuid: classification.mergeTarget?.atomUuid,
                mergeTargetTitle: classification.mergeTarget?.atomTitle,
                mergeTargetType: classification.mergeTarget?.atomType,
                mergePreview: classification.mergeTarget?.preview,
                placeThinkspaceId: classification.placeTarget?.thinkspaceId,
                placeThinkspaceName: classification.placeTarget?.thinkspaceName,
                placeAtomType: classification.placeTarget?.suggestedAtomType,
                recommendations: classification.recommendationBundle.encodedJSONString,
                primaryRouteKind: classification.recommendationBundle.primaryRecommendation?.kind.rawValue,
                destinationPath: classification.recommendationBundle.primaryRecommendation?.destinationPath,
                rationale: classification.recommendationBundle.primaryRecommendation?.rationale,
                placementPlanSummary: classification.recommendationBundle.primaryRecommendation?.placementPlan?.summary
            )
        } catch {
            print("⚠️ [InboxVM] Capture failed: \(error)")
        }
    }

    // MARK: - Actions

    func acceptSuggestion(for item: InboxItem) async {
        processingItemIds.insert(item.uuid)
        defer { processingItemIds.remove(item.uuid) }

        do {
            _ = try await executor.executePrimaryRecommendation(item: item)
            presentUndoToast(for: item)
        } catch {
            print("⚠️ [InboxVM] Action failed: \(error)")
        }
    }

    func dismiss(item: InboxItem) async {
        do {
            try await inboxRepo.dismiss(uuid: item.uuid)
        } catch {
            print("⚠️ [InboxVM] Dismiss failed: \(error)")
        }
    }

    // MARK: - Batch Actions

    func acceptAllSelected() async {
        let selectedItems = items.filter { selectedItemIds.contains($0.uuid) }
        for item in selectedItems {
            await acceptSuggestion(for: item)
        }
        selectedItemIds.removeAll()
    }

    func dismissAllSelected() async {
        let selectedItems = items.filter { selectedItemIds.contains($0.uuid) }
        for item in selectedItems {
            await dismiss(item: item)
        }
        selectedItemIds.removeAll()
    }

    func selectAll() {
        let visibleIds = filteredAndSorted.map(\.uuid)
        selectedItemIds = Set(visibleIds)
    }

    func deselectAll() {
        selectedItemIds.removeAll()
    }

    func toggleSelection(for item: InboxItem) {
        if selectedItemIds.contains(item.uuid) {
            selectedItemIds.remove(item.uuid)
        } else {
            selectedItemIds.insert(item.uuid)
        }
    }

    // MARK: - Keyboard Navigation

    func moveFocusUp() {
        let flatItems = filteredAndSorted
        guard !flatItems.isEmpty else { return }

        if let current = focusedItemId,
           let index = flatItems.firstIndex(where: { $0.uuid == current }),
           index > 0 {
            focusedItemId = flatItems[index - 1].uuid
        } else {
            focusedItemId = flatItems.first?.uuid
        }
    }

    func moveFocusDown() {
        let flatItems = filteredAndSorted
        guard !flatItems.isEmpty else { return }

        if let current = focusedItemId,
           let index = flatItems.firstIndex(where: { $0.uuid == current }),
           index < flatItems.count - 1 {
            focusedItemId = flatItems[index + 1].uuid
        } else {
            focusedItemId = flatItems.first?.uuid
        }
    }

    func acceptFocused() async {
        guard let id = focusedItemId,
              let item = items.first(where: { $0.uuid == id }) else { return }
        await acceptSuggestion(for: item)
        moveFocusDown()
    }

    func dismissFocused() async {
        guard let id = focusedItemId,
              let item = items.first(where: { $0.uuid == id }) else { return }
        await dismiss(item: item)
        moveFocusDown()
    }

    func toggleFocusedSelection() {
        guard let id = focusedItemId,
              let item = items.first(where: { $0.uuid == id }) else { return }
        toggleSelection(for: item)
    }

    // MARK: - Expand/Collapse

    func toggleExpanded(for item: InboxItem) {
        if expandedItemIds.contains(item.uuid) {
            expandedItemIds.remove(item.uuid)
        } else {
            expandedItemIds.insert(item.uuid)
        }
    }

    func isExpanded(_ item: InboxItem) -> Bool {
        expandedItemIds.contains(item.uuid)
    }

    // MARK: - Override Sheet

    func showOverride(for item: InboxItem) {
        overrideItem = item
        overrideSearchResults = []
        showOverrideSheet = true
    }

    func overrideMerge(item: InboxItem, targetUuid: String) async {
        processingItemIds.insert(item.uuid)
        defer { processingItemIds.remove(item.uuid) }

        do {
            _ = try await executor.executeMerge(item: item, targetAtomUuid: targetUuid)
            presentUndoToast(for: item)
            showOverrideSheet = false
        } catch {
            print("⚠️ [InboxVM] Override merge failed: \(error)")
        }
    }

    func overridePlace(item: InboxItem, thinkspaceId: String, atomType: AtomType) async {
        processingItemIds.insert(item.uuid)
        defer { processingItemIds.remove(item.uuid) }

        do {
            _ = try await executor.executePlace(item: item, thinkspaceId: thinkspaceId, atomType: atomType)
            presentUndoToast(for: item)
            showOverrideSheet = false
        } catch {
            print("⚠️ [InboxVM] Override place failed: \(error)")
        }
    }

    func overrideNew(item: InboxItem, atomType: AtomType) async {
        processingItemIds.insert(item.uuid)
        defer { processingItemIds.remove(item.uuid) }

        do {
            _ = try await executor.executeNew(item: item, atomType: atomType)
            presentUndoToast(for: item)
            showOverrideSheet = false
        } catch {
            print("⚠️ [InboxVM] Override new failed: \(error)")
        }
    }

    func searchAtoms(query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            overrideSearchResults = []
            return
        }
        do {
            overrideSearchResults = try await HybridSearchEngine.shared.search(
                query: query,
                limit: 8
            )
        } catch {
            overrideSearchResults = []
        }
    }

    // MARK: - Filters

    func toggleSourceFilter(_ source: InboxSource) {
        if activeSourceFilter == source {
            activeSourceFilter = nil
        } else {
            activeSourceFilter = source
        }
        regroupItems()
    }

    func toggleClassificationFilter(_ classification: InboxClassification) {
        if activeClassificationFilter == classification {
            activeClassificationFilter = nil
        } else {
            activeClassificationFilter = classification
        }
        regroupItems()
    }

    func clearFilters() {
        activeSourceFilter = nil
        activeClassificationFilter = nil
        regroupItems()
    }

    func setSortOrder(_ order: InboxSortOrder) {
        sortOrder = order
        regroupItems()
    }

    // MARK: - Mark Read

    func markReadIfNeeded(_ item: InboxItem) {
        guard !item.isRead else { return }
        Task {
            try? await inboxRepo.markRead(uuid: item.uuid)
        }
    }

    // MARK: - Empty State Data

    private func loadEmptyStateData() {
        Task {
            do {
                recentHistory = try await inboxRepo.fetchRecentHistory(limit: 3)
                triagedThisWeek = try await inboxRepo.countTriagedThisWeek()
            } catch {
                print("⚠️ [InboxVM] Empty state data failed: \(error)")
            }
        }
    }

    // MARK: - Intelligence

    private let intelligenceEngine = InboxIntelligenceEngine.shared

    private func runIntelligence() {
        intelligenceTask?.cancel()
        intelligenceTask = Task {
            // Auto-grouping (local, fast)
            itemGroups = intelligenceEngine.computeGroups(items: items)

            // Per-item insights (LLM, async)
            let newInsights = await intelligenceEngine.generateInsights(items: items)
            for (uuid, insight) in newInsights {
                itemInsights[uuid] = insight
            }
        }
    }

    /// Execute a suggested batch action from an InboxItemGroup
    func executeBatchGroup(_ group: InboxItemGroup) async {
        guard let targetUuid = group.mergeTargetUuid else { return }
        let groupItems = items.filter { group.itemIds.contains($0.uuid) }
        for item in groupItems {
            processingItemIds.insert(item.uuid)
            do {
                _ = try await executor.executeMerge(item: item, targetAtomUuid: targetUuid)
            } catch {
                print("⚠️ [InboxVM] Batch group action failed for \(item.uuid): \(error)")
            }
            processingItemIds.remove(item.uuid)
        }
        // Remove the group after execution
        itemGroups.removeAll { $0.id == group.id }
    }

    func dismissGroup(_ group: InboxItemGroup) {
        itemGroups.removeAll { $0.id == group.id }
    }

    func undoLastInboxAction() async {
        await CosmoUndoManager.shared.undo()
        withAnimation(.easeOut(duration: 0.2)) {
            showUndoToast = false
        }
    }

    func dismissUndoToast() {
        undoToastTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            showUndoToast = false
        }
    }

    private func presentUndoToast(for item: InboxItem) {
        undoToastTask?.cancel()
        undoToastMessage = "Applied recommendation for \(item.title ?? String(item.rawText.prefix(40)))"
        withAnimation(.easeOut(duration: 0.2)) {
            showUndoToast = true
        }

        undoToastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                self.showUndoToast = false
            }
        }
    }
}
