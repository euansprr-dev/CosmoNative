// CosmoOS/UI/Inbox/InboxViewModel.swift
// State management for the Smart Triage Inbox — @Observable, temporal grouping,
// filtering, batch actions, keyboard nav, quick capture, intelligence
// March 2026

import SwiftUI
import Combine

struct InboxSectionIdentity: Equatable {
    private let ids: [String]

    init(sections: [InboxSection]) {
        ids = sections.flatMap { section in
            [section.id] + section.items.map(\.uuid)
        }
    }
}

struct InboxSoftClusterIdentity: Equatable {
    private let ids: [String]

    init(clusters: [InboxSoftCluster]) {
        ids = clusters.map(\.id)
    }
}

@Observable
@MainActor
final class InboxViewModel {

    // MARK: - Items & Sections

    var items: [InboxItem] = []
    var groupedItems: [InboxSection] = []
    var groupedItemsIdentity = InboxSectionIdentity(sections: [])
    var stats: InboxStats = .empty

    // MARK: - Filtering & Sorting

    var activeSourceFilter: InboxSource?
    var activeClassificationFilter: InboxClassification?
    var sortOrder: InboxSortOrder = .newestFirst
    var viewMode: InboxViewMode = .canvas

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
    var softClusters: [InboxSoftCluster] = []
    var softClustersIdentity = InboxSoftClusterIdentity(clusters: [])
    var unplacedDatabaseItems: [InboxDatabaseCandidate] = []
    var selectedSpatialItem: InboxSpatialSelection?
    var collapsedSoftClusterIds: Set<String> = []

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
    private let atomRepo = AtomRepository.shared
    private var cancellables = Set<AnyCancellable>()
    private var intelligenceTask: Task<Void, Never>?
    private var databaseItemsTask: Task<Void, Never>?
    private var undoToastTask: Task<Void, Never>?
    private var overrideSearchTask: Task<Void, Never>?
    private var overrideSearchRequestID = UUID()
    private var pendingDatabaseFocusUuid: String?

    // Whether the Inbox surface is currently visible. Drives whether expensive
    // LLM-backed intelligence runs at all. Toggled from InboxView.onAppear/onDisappear.
    var isInboxVisible: Bool = false {
        didSet {
            guard isInboxVisible, !oldValue else { return }
            runIntelligence()
            loadUnplacedDatabaseItems()
        }
    }

    // Stable hashes used to short-circuit redundant work when items re-emit
    // with identical content (e.g. timestamp-only changes from sync).
    private var lastIntelligenceItemsHash: Int = 0
    private var lastSoftClusterInputHash: Int = 0
    private var lastDatabaseLoadAt: Date = .distantPast
    private static let databaseLoadThrottle: TimeInterval = 10

    var thinkspaces: [Thinkspace] {
        ThinkspaceManager.shared.thinkspaces
    }

    // MARK: - Init

    init() {
        startObserving()
        loadEmptyStateData()
        loadUnplacedDatabaseItems()
    }

    // MARK: - Observation

    private func startObserving() {
        // Debounce sync bursts so a flurry of classification updates collapses
        // into a single downstream pass. Cheap synchronous work runs unconditionally;
        // expensive LLM/DB work is gated by visibility + content-hash guards inside
        // their respective methods.
        inboxRepo.$items
            .debounce(for: .milliseconds(350), scheduler: DispatchQueue.main)
            .sink { [weak self] newItems in
                guard let self else { return }
                self.items = newItems
                self.stats = InboxStats(items: newItems)
                self.regroupItems()
                self.runIntelligence()
                self.loadUnplacedDatabaseItems()
            }
            .store(in: &cancellables)
    }

    // Content fingerprint covering identity + classification + body length.
    // A timestamp-only sync emission produces the same hash → intelligence skips.
    private func intelligenceItemsHash() -> Int {
        var hasher = Hasher()
        for item in items {
            hasher.combine(item.uuid)
            hasher.combine(item.classification?.rawValue ?? "")
            hasher.combine(item.rawText.count)
            hasher.combine(item.title ?? "")
        }
        return hasher.finalize()
    }

    private func softClusterInputHash(filtered: [InboxItem]) -> Int {
        var hasher = Hasher()
        for item in filtered {
            hasher.combine(item.uuid)
            hasher.combine(item.classification?.rawValue ?? "")
            hasher.combine(item.mergeTargetUuid ?? "")
            hasher.combine(item.placeThinkspaceId ?? "")
        }
        for candidate in unplacedDatabaseItems {
            hasher.combine(candidate.uuid)
        }
        hasher.combine(collapsedSoftClusterIds.sorted())
        return hasher.finalize()
    }

    // MARK: - Temporal Grouping

    private func regroupItems() {
        let filtered = filteredAndSorted
        let calendar = Calendar.current
        let now = Date()

        var today: [InboxItem] = []
        var yesterday: [InboxItem] = []
        var thisWeek: [InboxItem] = []
        var older: [InboxItem] = []

        for item in filtered {
            guard let date = ISO8601.date(from: item.createdAt) else {
                older.append(item)
                continue
            }
            if calendar.isDateInToday(date) { today.append(item) }
            else if calendar.isDateInYesterday(date) { yesterday.append(item) }
            else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) { thisWeek.append(item) }
            else { older.append(item) }
        }

        let nextGroupedItems = [
            today.isEmpty ? nil : InboxSection(id: "today", title: "Today", items: today),
            yesterday.isEmpty ? nil : InboxSection(id: "yesterday", title: "Yesterday", items: yesterday),
            thisWeek.isEmpty ? nil : InboxSection(id: "thisWeek", title: "This Week", items: thisWeek),
            older.isEmpty ? nil : InboxSection(id: "older", title: "Older", items: older),
        ].compactMap { $0 }
        let nextIdentity = InboxSectionIdentity(sections: nextGroupedItems)
        if groupedItemsIdentity != nextIdentity {
            groupedItemsIdentity = nextIdentity
        }
        groupedItems = nextGroupedItems
        rebuildSoftClusters(filtered: filtered)
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
        overrideSearchTask?.cancel()
        overrideSearchRequestID = UUID()
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

    func scheduleOverrideSearch(query: String) {
        overrideSearchTask?.cancel()

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestID = UUID()
        overrideSearchRequestID = requestID

        guard !trimmedQuery.isEmpty else {
            overrideSearchResults = []
            return
        }

        overrideSearchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.searchAtoms(query: trimmedQuery, requestID: requestID)
        }
    }

    private func searchAtoms(query: String, requestID: UUID) async {
        do {
            let results = try await HybridSearchEngine.shared.search(
                query: query,
                limit: 8
            )
            guard self.overrideSearchRequestID == requestID, !Task.isCancelled else { return }
            overrideSearchResults = results
        } catch is CancellationError {
            return
        } catch {
            guard self.overrideSearchRequestID == requestID else { return }
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

    func setViewMode(_ mode: InboxViewMode) {
        guard viewMode != mode else { return }
        withAnimation(ProMotionSprings.snappy) {
            viewMode = mode
        }
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
        // Auto-grouping is local + cheap, run it unconditionally so List mode stays correct.
        itemGroups = intelligenceEngine.computeGroups(items: items)

        // LLM-backed insights only run when the Inbox is on-screen — otherwise we'd
        // burn the OpenRouter API on every background sync.
        guard isInboxVisible else { return }

        // Skip if nothing materially changed since the last intelligence pass.
        let hash = intelligenceItemsHash()
        guard hash != lastIntelligenceItemsHash else { return }
        lastIntelligenceItemsHash = hash

        let previous = intelligenceTask
        let snapshot = items
        intelligenceTask = Task { [weak self] in
            // Wait for the prior batch to finish cancelling so two passes never overlap.
            previous?.cancel()
            _ = await previous?.value
            guard !Task.isCancelled, let self else { return }

            let newInsights = await self.intelligenceEngine.generateInsights(items: snapshot)
            guard !Task.isCancelled else { return }
            for (uuid, insight) in newInsights {
                self.itemInsights[uuid] = insight
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

    func toggleSoftCluster(_ cluster: InboxSoftCluster) {
        if collapsedSoftClusterIds.contains(cluster.id) {
            collapsedSoftClusterIds.remove(cluster.id)
        } else {
            collapsedSoftClusterIds.insert(cluster.id)
        }
        rebuildSoftClusters()
    }

    func executeSoftCluster(_ cluster: InboxSoftCluster) async {
        let clusterItems = items.filter { cluster.inboxItemIds.contains($0.uuid) && $0.confidence >= 0.7 }
        for item in clusterItems {
            await acceptSuggestion(for: item)
        }
    }

    func selectInboxItem(_ item: InboxItem) {
        selectedSpatialItem = .inboxItem(item.uuid)
        markReadIfNeeded(item)
    }

    func selectDatabaseItem(_ item: InboxDatabaseCandidate) {
        selectedSpatialItem = .databaseAtom(item.uuid)
    }

    func closeSpatialInspector() {
        selectedSpatialItem = nil
    }

    func selectedInboxItem() -> InboxItem? {
        guard case .inboxItem(let uuid) = selectedSpatialItem else { return nil }
        return items.first { $0.uuid == uuid }
    }

    func selectedDatabaseItem() -> InboxDatabaseCandidate? {
        guard case .databaseAtom(let uuid) = selectedSpatialItem else { return nil }
        return unplacedDatabaseItems.first { $0.uuid == uuid }
    }

    func focusInboxItem(uuid: String) {
        guard items.contains(where: { $0.uuid == uuid }) else { return }
        selectedSpatialItem = .inboxItem(uuid)
        viewMode = .canvas
    }

    func focusDatabaseItem(uuid: String) {
        viewMode = .canvas
        if unplacedDatabaseItems.contains(where: { $0.uuid == uuid }) {
            selectedSpatialItem = .databaseAtom(uuid)
        } else {
            pendingDatabaseFocusUuid = uuid
            loadUnplacedDatabaseItems(force: true)
        }
    }

    func placeAndGo(_ item: InboxItem) async {
        processingItemIds.insert(item.uuid)
        defer { processingItemIds.remove(item.uuid) }

        do {
            guard let atom = try await executor.executePrimaryRecommendation(item: item) else { return }
            presentUndoToast(for: item, destination: item.spatialDestinationTitle)
            let targetThinkspaceId = item.primaryRecommendationValue?.thinkspaceId
                ?? item.primaryRecommendationValue?.placementPlan?.targetThinkspaceId
                ?? item.placeThinkspaceId
            guard let targetThinkspaceId else { return }
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.navigateToThinkspaceById,
                object: nil,
                userInfo: CosmoNotification.Navigation.ThinkspacePayload(thinkspaceId: targetThinkspaceId).userInfo
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                NotificationCenter.default.post(
                    name: CosmoNotification.Navigation.openEntityOnCanvas,
                    object: nil,
                    userInfo: ["atomUUID": atom.uuid]
                )
            }
        } catch {
            print("⚠️ [InboxVM] Place & Go failed: \(error)")
        }
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

    private func presentUndoToast(for item: InboxItem, destination: String? = nil) {
        undoToastTask?.cancel()
        if let destination, item.classification == .place {
            undoToastMessage = "Placed in \(destination)"
        } else {
            undoToastMessage = "Applied recommendation for \(item.title ?? String(item.rawText.prefix(40)))"
        }
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

    private func rebuildSoftClusters(filtered providedFiltered: [InboxItem]? = nil) {
        let filtered = providedFiltered ?? filteredAndSorted

        // Identical input → identical output. Short-circuit so SwiftUI doesn't
        // re-diff a 5-cluster array on every Combine emission.
        let inputHash = softClusterInputHash(filtered: filtered)
        if inputHash == lastSoftClusterInputHash, !softClusters.isEmpty { return }
        lastSoftClusterInputHash = inputHash

        var clusters: [InboxSoftCluster] = []

        let mergeGroups = Dictionary(grouping: filtered.filter { $0.classification == .merge }) {
            $0.mergeTargetUuid ?? $0.mergeTargetTitle ?? "unknown"
        }
        clusters += mergeGroups.map { key, group in
            let target = group.first?.mergeTargetTitle ?? "possible match"
            return InboxSoftCluster(
                id: "merge-\(key)",
                title: "Possible merges",
                subtitle: target,
                kind: .merge,
                inboxItemIds: group.map(\.uuid),
                databaseAtomIds: [],
                isCollapsed: collapsedSoftClusterIds.contains("merge-\(key)")
            )
        }

        let placeGroups = Dictionary(grouping: filtered.filter { $0.classification == .place }) {
            $0.destinationPath ?? $0.placeThinkspaceName ?? "Thinkspace"
        }
        clusters += placeGroups.map { destination, group in
            let id = "place-\(destination)"
            return InboxSoftCluster(
                id: id,
                title: "Ready to place",
                subtitle: destination,
                kind: .place,
                inboxItemIds: group.map(\.uuid),
                databaseAtomIds: [],
                isCollapsed: collapsedSoftClusterIds.contains(id)
            )
        }

        let newItems = filtered.filter { $0.classification == .new }
        if !newItems.isEmpty {
            clusters.append(InboxSoftCluster(
                id: "new-patterns",
                title: "New patterns forming",
                subtitle: "\(newItems.count) item\(newItems.count == 1 ? "" : "s") without an existing fit",
                kind: .new,
                inboxItemIds: newItems.map(\.uuid),
                databaseAtomIds: [],
                isCollapsed: collapsedSoftClusterIds.contains("new-patterns")
            ))
        }

        // Tasks have a home in the Command Center, not on a thinkspace canvas.
        // Drop them from triage so they don't sit forever in "Needs your judgment".
        let unclearItems = filtered.filter { $0.classification == nil && !$0.routesToTask }
        if !unclearItems.isEmpty {
            clusters.append(InboxSoftCluster(
                id: "unclear",
                title: "Needs your judgment",
                subtitle: "\(unclearItems.count) capture\(unclearItems.count == 1 ? "" : "s") still being interpreted",
                kind: .unclear,
                inboxItemIds: unclearItems.map(\.uuid),
                databaseAtomIds: [],
                isCollapsed: collapsedSoftClusterIds.contains("unclear")
            ))
        }

        if !unplacedDatabaseItems.isEmpty {
            clusters.append(InboxSoftCluster(
                id: "database-unplaced",
                title: "Unplaced database",
                subtitle: "\(unplacedDatabaseItems.count) object\(unplacedDatabaseItems.count == 1 ? "" : "s") without a thinkspace home",
                kind: .database,
                inboxItemIds: [],
                databaseAtomIds: unplacedDatabaseItems.map(\.uuid),
                isCollapsed: collapsedSoftClusterIds.contains("database-unplaced")
            ))
        }

        let nextClusters = clusters.sorted { lhs, rhs in
            if lhs.kind.sortRank != rhs.kind.sortRank { return lhs.kind.sortRank < rhs.kind.sortRank }
            return lhs.subtitle < rhs.subtitle
        }
        let nextIdentity = InboxSoftClusterIdentity(clusters: nextClusters)
        if softClustersIdentity != nextIdentity {
            softClustersIdentity = nextIdentity
        }
        softClusters = nextClusters
    }

    private func loadUnplacedDatabaseItems(force: Bool = false) {
        // Leading-edge throttle: the 80-item GRDB scan + thinkspace-membership
        // join is expensive enough that re-running it on every Combine emission
        // is what dragged the Inbox into stutter. Cap to once per 10s.
        let now = Date()
        if !force,
           now.timeIntervalSince(lastDatabaseLoadAt) < Self.databaseLoadThrottle,
           !unplacedDatabaseItems.isEmpty {
            return
        }
        lastDatabaseLoadAt = now

        databaseItemsTask?.cancel()
        databaseItemsTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let userTypes: [AtomType] = [.note, .task, .content, .research, .connection, .clientProfile, .image]
                let atoms = try await self.atomRepo.fetchAll(types: userTypes)
                let activeAtoms = atoms.filter { atom in
                    guard !atom.isDeleted else { return false }
                    if atom.type == .idea || atom.type == .project || atom.type == .thinkspace { return false }
                    if atom.type == .research && atom.isSwipeFile { return false }
                    return true
                }
                let memberships = try await self.atomRepo.fetchThinkspaceMembership(for: activeAtoms.map(\.uuid))
                let candidates = activeAtoms
                    .filter { (memberships[$0.uuid] ?? []).isEmpty }
                    .sorted { $0.updatedAt > $1.updatedAt }
                    .prefix(80)
                    .map { atom in
                        InboxDatabaseCandidate(
                            atom: atom,
                            title: atom.title ?? "Untitled",
                            preview: Self.previewText(for: atom),
                            relativeDate: Self.relativeDate(from: ISO8601.date(from: atom.updatedAt) ?? Date())
                        )
                    }

                self.unplacedDatabaseItems = Array(candidates)
                self.rebuildSoftClusters()
                if let pending = self.pendingDatabaseFocusUuid,
                   self.unplacedDatabaseItems.contains(where: { $0.uuid == pending }) {
                    self.selectedSpatialItem = .databaseAtom(pending)
                    self.pendingDatabaseFocusUuid = nil
                }
            } catch {
                print("⚠️ [InboxVM] Failed loading unplaced database items: \(error)")
            }
        }
    }

    private static func previewText(for atom: Atom) -> String {
        let text = atom.body ?? atom.combinedText
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return atom.type.displayName }
        return String(trimmed.prefix(180))
    }

    private static func relativeDate(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        if interval < 604800 { return "\(Int(interval / 86400))d" }
        return "\(Int(interval / 604800))w"
    }
}

private extension InboxSoftClusterKind {
    var sortRank: Int {
        switch self {
        case .place: return 0
        case .merge: return 1
        case .new: return 2
        case .unclear: return 3
        case .database: return 4
        }
    }
}
