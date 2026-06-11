// CosmoOS/UI/Inbox/InboxViewModel.swift
// State for the triage-queue Inbox — temporal sections, single-focus inspector,
// keyboard-first verbs, quick capture, batch actions, undo.
//
// June 2026 rebuild (INBOX_REVAMP_PLAN.md §3): the inbox shows only explicit
// captures. The unplaced-database scan, soft-cluster grid, view modes, filter
// rows, and per-item LLM insights are gone — one calm ledger, one inspector.

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

@Observable
@MainActor
final class InboxViewModel {

    // MARK: - Items & Sections

    var items: [InboxItem] = []
    var groupedItems: [InboxSection] = []
    var groupedItemsIdentity = InboxSectionIdentity(sections: [])

    var suggestedCount: Int {
        items.filter(\.hasActionableSuggestion).count
    }

    // MARK: - Focus & Selection

    /// The single focused item — drives both the keyboard cursor and the inspector.
    var focusedItemId: String?
    var isInspectorOpen: Bool = false

    var focusedItem: InboxItem? {
        guard let focusedItemId else { return nil }
        return items.first { $0.uuid == focusedItemId }
    }

    /// Multi-select for batch accept/dismiss (⌘-click).
    var selectedItemIds: Set<String> = []
    var isMultiSelectActive: Bool { !selectedItemIds.isEmpty }

    // MARK: - Quick Capture

    var captureText: String = ""
    var isCaptureExpanded: Bool = false
    var showCaptureConfirmation: Bool = false
    var captureFieldFocusRequest: Int = 0
    /// True while the capture field owns keyboard focus — letter-key verbs
    /// (T/A/I/C) must not fire while the user is typing a thought.
    var isCaptureFieldFocused: Bool = false

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

    // MARK: - Private

    private let inboxRepo = InboxRepository.shared
    private let executor = InboxActionExecutor.shared
    private let atomRepo = AtomRepository.shared
    private var cancellables = Set<AnyCancellable>()
    private var undoToastTask: Task<Void, Never>?
    private var overrideSearchTask: Task<Void, Never>?
    private var overrideSearchRequestID = UUID()

    /// Visibility drives the lazy taxonomy pass for unsorted items — batched,
    /// throttled, and never run while the inbox is off-screen.
    var isInboxVisible: Bool = false {
        didSet {
            guard isInboxVisible, !oldValue else { return }
            InboxIngestService.shared.runTaxonomyPassIfNeeded()
            loadEmptyStateData()
        }
    }

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
        // Debounce sync bursts so a flurry of classification updates collapses
        // into a single regroup pass.
        inboxRepo.$items
            .debounce(for: .milliseconds(350), scheduler: DispatchQueue.main)
            .sink { [weak self] newItems in
                guard let self else { return }
                self.items = newItems
                self.regroupItems()
                self.reconcileFocus()
            }
            .store(in: &cancellables)
    }

    /// Keep keyboard focus on a real row after items change underneath it.
    private func reconcileFocus() {
        guard let focusedItemId, !items.contains(where: { $0.uuid == focusedItemId }) else { return }
        self.focusedItemId = nil
        isInspectorOpen = false
    }

    // MARK: - Temporal Grouping

    private func regroupItems() {
        let calendar = Calendar.current
        let now = Date()

        var today: [InboxItem] = []
        var yesterday: [InboxItem] = []
        var thisWeek: [InboxItem] = []
        var older: [InboxItem] = []

        for item in items {
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
    }

    private var orderedItems: [InboxItem] {
        groupedItems.flatMap(\.items)
    }

    // MARK: - Quick Capture

    func submitCapture() async {
        let text = captureText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        captureText = ""
        isCaptureExpanded = false

        // All ingestion goes through the choke point — it owns dedupe, the
        // consumed-capture rule, and queued classification.
        _ = await InboxIngestService.shared.ingest(
            .init(source: .quickCapture, rawText: text)
        )

        showCaptureConfirmation = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            showCaptureConfirmation = false
        }
    }

    func requestCaptureFieldFocus() {
        captureFieldFocusRequest += 1
    }

    // MARK: - Core Verbs

    func acceptSuggestion(for item: InboxItem) async {
        processingItemIds.insert(item.uuid)
        defer { processingItemIds.remove(item.uuid) }

        do {
            _ = try await executor.executePrimaryRecommendation(item: item)
            presentUndoToast(for: item, destination: item.spatialDestinationTitle)
        } catch {
            print("⚠️ [InboxVM] Action failed: \(error)")
        }
    }

    /// Place using the suggestion, optionally with a position adjusted on the
    /// inspector minimap (the ghost block the user dragged).
    func place(_ item: InboxItem, adjustedPosition: CGPoint?) async {
        guard let recommendation = item.primaryRecommendationValue else {
            await acceptSuggestion(for: item)
            return
        }

        processingItemIds.insert(item.uuid)
        defer { processingItemIds.remove(item.uuid) }

        do {
            let final = adjustedPosition.map { recommendation.overridingBlockPosition($0) } ?? recommendation
            _ = try await executor.executeRecommendation(item: item, recommendation: final)
            presentUndoToast(for: item, destination: item.spatialDestinationTitle)
        } catch {
            print("⚠️ [InboxVM] Place failed: \(error)")
        }
    }

    func dismiss(item: InboxItem) async {
        do {
            try await inboxRepo.dismiss(uuid: item.uuid)
        } catch {
            print("⚠️ [InboxVM] Dismiss failed: \(error)")
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

    // MARK: - Closed-Loop Verbs

    /// T — the capture is a task: it belongs in the Command Center, not a canvas.
    func makeTask(_ item: InboxItem) async {
        processingItemIds.insert(item.uuid)
        defer { processingItemIds.remove(item.uuid) }

        do {
            _ = try await executor.executeNew(item: item, atomType: .task)
            presentUndoToast(for: item, verb: "Task created")
        } catch {
            print("⚠️ [InboxVM] Make task failed: \(error)")
        }
    }

    /// I — the capture is an idea: type it and let the idea pipeline enrich it.
    func fileAsIdea(_ item: InboxItem) async {
        processingItemIds.insert(item.uuid)
        defer { processingItemIds.remove(item.uuid) }

        do {
            let atom = try await executor.executeNew(item: item, atomType: .idea)
            presentUndoToast(for: item, verb: "Filed as idea")
            Task { await IdeaInsightEngine.shared.quickEnrich(atom: atom) }
        } catch {
            print("⚠️ [InboxVM] File as idea failed: \(error)")
        }
    }

    /// A — the capture is a question: spin it into the most recent Deep Dive's
    /// inquiry queue, closing the capture → inquiry loop.
    func askInDeepDive(_ item: InboxItem) async {
        processingItemIds.insert(item.uuid)
        defer { processingItemIds.remove(item.uuid) }

        do {
            let deepDives = ((try? await atomRepo.fetchAll(type: .deepDive)) ?? [])
                .filter { !$0.isDeleted }
                .sorted { $0.updatedAt > $1.updatedAt }
            let target = deepDives.first

            let question = try await InquiryRepository.shared.createQuestion(
                title: item.title ?? String(item.rawText.prefix(120)),
                parentDeepDiveUUID: target?.uuid,
                originSessionUUID: nil,
                parentQuestionUUID: nil,
                originExtractUUID: nil
            )

            if var deepDive = target {
                deepDive = deepDive.appendingLink(AtomLink(
                    type: AtomLinkType.deepDiveQuestion.rawValue,
                    uuid: question.uuid,
                    entityType: AtomType.question.rawValue
                ))
                _ = try? await atomRepo.update(deepDive)
            }

            try await inboxRepo.markActioned(uuid: item.uuid)
            let destination = target?.title.map { "\($0) → Questions" } ?? "Inquiry"
            presentUndoToast(for: item, verb: "Asked in \(destination)")
        } catch {
            print("⚠️ [InboxVM] Ask in deep dive failed: \(error)")
        }
    }

    /// C — the capture bridges existing atoms: create a connection linked to
    /// the related material instead of merging or duplicating.
    func connectCapture(_ item: InboxItem) async {
        processingItemIds.insert(item.uuid)
        defer { processingItemIds.remove(item.uuid) }

        do {
            _ = try await executor.executeConnect(item: item, relatedAtomUUIDs: item.relatedAtomUUIDsValue)
            presentUndoToast(for: item, verb: "Connected")
        } catch {
            print("⚠️ [InboxVM] Connect failed: \(error)")
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
        selectedItemIds = Set(orderedItems.map(\.uuid))
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

    // MARK: - Focus & Inspector

    func focusItem(_ item: InboxItem) {
        focusedItemId = item.uuid
        isInspectorOpen = true
        markReadIfNeeded(item)
    }

    func closeInspector() {
        isInspectorOpen = false
    }

    func toggleInspectorForFocused() {
        guard focusedItem != nil else { return }
        isInspectorOpen.toggle()
    }

    func moveFocusUp() {
        let flat = orderedItems
        guard !flat.isEmpty else { return }

        if let current = focusedItemId,
           let index = flat.firstIndex(where: { $0.uuid == current }),
           index > 0 {
            focusedItemId = flat[index - 1].uuid
        } else {
            focusedItemId = flat.first?.uuid
        }
        if let item = focusedItem { markReadIfNeeded(item) }
    }

    func moveFocusDown() {
        let flat = orderedItems
        guard !flat.isEmpty else { return }

        if let current = focusedItemId,
           let index = flat.firstIndex(where: { $0.uuid == current }),
           index < flat.count - 1 {
            focusedItemId = flat[index + 1].uuid
        } else {
            focusedItemId = flat.first?.uuid
        }
        if let item = focusedItem { markReadIfNeeded(item) }
    }

    func acceptFocused() async {
        guard let item = focusedItem else { return }
        await acceptSuggestion(for: item)
        moveFocusDown()
    }

    func dismissFocused() async {
        guard let item = focusedItem else { return }
        await dismiss(item: item)
        moveFocusDown()
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
                limit: 8,
                entityTypes: EntityType.inboxTriageable
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

    // MARK: - Undo

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

    private func presentUndoToast(for item: InboxItem, destination: String? = nil, verb: String? = nil) {
        undoToastTask?.cancel()
        if let verb {
            undoToastMessage = verb
        } else if let destination, item.classification == .place {
            undoToastMessage = "Placed in \(destination)"
        } else if item.classification == .merge, let target = item.mergeTargetTitle {
            undoToastMessage = "Merged into \(target)"
        } else {
            undoToastMessage = "Filed \(item.title ?? String(item.rawText.prefix(40)))"
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
}
