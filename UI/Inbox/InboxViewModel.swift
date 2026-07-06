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
    /// Set when the ingest write failed — rendered as an error line under the
    /// capture bar. The text stays in the field so nothing is lost.
    var captureError: String?
    var captureFieldFocusRequest: Int = 0
    /// True while the capture field owns keyboard focus — letter-key verbs
    /// (T/A/I/C) must not fire while the user is typing a thought.
    var isCaptureFieldFocused: Bool = false

    // MARK: - Physical capture (scan intake)

    /// Bumped to pop the Continuity Camera device menu at the capture bar.
    var continuityCameraMenuTick = 0
    var showScanImporter = false
    /// True while a scan batch is digitizing — the bar shows a progress line.
    var isScanIngesting = false

    /// Continuity Camera shots and uploaded images — digitized into ONE
    /// capture through the shared scan pipeline.
    func ingestScanImages(_ images: [Data]) async {
        guard !images.isEmpty else { return }
        captureError = nil
        isScanIngesting = true
        defer { isScanIngesting = false }
        switch await InboxScanIngestService.shared.ingest(images: images) {
        case .captured:
            showCaptureConfirmation = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                showCaptureConfirmation = false
            }
        case .failed(let detail):
            captureError = "Couldn't digitize the scan — \(detail)"
        }
    }

    /// "Scan with iPhone": a capture_request row + an APNs push. The pages
    /// come back as a normal inbox capture from the phone's side.
    func requestPhoneScan() async {
        captureError = nil
        do {
            let request = try await CaptureRequestRepository.shared.create(
                .new(kind: .inboxScan, scanSessionId: UUID().uuidString)
            )
            try await PushSenderService.shared.sendScanRequest(request)
        } catch {
            captureError = error.localizedDescription
        }
    }

    // MARK: - Override Sheet

    var overrideItem: InboxItem?
    var showOverrideSheet: Bool = false
    var overrideSearchResults: [HybridSearchEngine.SearchResult] = []

    // MARK: - Processing

    var processingItemIds: Set<String> = []

    // MARK: - Empty State

    var recentHistory: [InboxItem] = []
    var recentHistoryEntries: [InboxHistoryEntry] = []
    var triagedThisWeek: Int = 0

    // MARK: - Undo Toast

    var showUndoToast: Bool = false
    var undoToastMessage: String = ""
    /// True when the toast reports a failure — no Undo button, warning styling.
    var undoToastIsError: Bool = false

    // MARK: - Private

    private let inboxRepo = InboxRepository.shared
    private let destinationRepo = CaptureDestinationRepository.shared
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

        NotificationCenter.default.publisher(for: CosmoNotification.Inbox.captureLaneChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.loadEmptyStateData()
                }
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

        captureError = nil

        // All ingestion goes through the choke point — it owns dedupe, the
        // consumed-capture rule, and queued classification. The field is NOT
        // cleared until the write outcome is known: a failed save must never
        // eat the user's words behind a success checkmark.
        let outcome = await InboxIngestService.shared.ingest(
            .init(source: .quickCapture, rawText: text)
        )

        switch outcome {
        case .failed:
            if captureText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                captureText = text
            }
            captureError = "Couldn't save that capture — your text is still here. Try again."
        case .enqueued, .consumed:
            captureText = ""
            isCaptureExpanded = false
            showCaptureConfirmation = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                showCaptureConfirmation = false
            }
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
            if try await executor.executePrimaryRecommendation(item: item) != nil {
                presentUndoToast(for: item, destination: item.spatialDestinationTitle)
            } else {
                await recoverFromNilExecution(for: item)
            }
        } catch {
            print("⚠️ [InboxVM] Action failed: \(error)")
            PersistenceHealth.note(.writeFailure, context: "InboxVM.acceptSuggestion", detail: error.localizedDescription)
            presentErrorToast("Couldn't file that capture — it's still in your inbox.")
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
            if try await executor.executeRecommendation(item: item, recommendation: final) != nil {
                presentUndoToast(for: item, destination: item.spatialDestinationTitle)
            } else {
                await recoverFromNilExecution(for: item)
            }
        } catch {
            print("⚠️ [InboxVM] Place failed: \(error)")
            PersistenceHealth.note(.writeFailure, context: "InboxVM.place", detail: error.localizedDescription)
            presentErrorToast("Couldn't place that capture — it's still in your inbox.")
        }
    }

    /// The executor returned nil: the merge target was deleted or the
    /// destination thinkspace couldn't be created. A permanently-missing merge
    /// target falls back to a standalone atom so the item is never stuck;
    /// anything else surfaces an honest error instead of a success toast.
    private func recoverFromNilExecution(for item: InboxItem) async {
        let mergeTargetUuid = item.mergeTargetUuid ?? item.primaryRecommendationValue?.mergeTargetUuid
        if let mergeTargetUuid {
            let target = try? await atomRepo.fetch(uuid: mergeTargetUuid)
            if target == nil || target?.isDeleted == true {
                do {
                    _ = try await executor.executeNew(item: item)
                    presentUndoToast(for: item, verb: "Merge target was deleted — filed as new")
                    return
                } catch {
                    print("⚠️ [InboxVM] Merge fallback failed: \(error)")
                    PersistenceHealth.note(.writeFailure, context: "InboxVM.recoverFromNilExecution", detail: error.localizedDescription)
                }
            }
        }
        presentErrorToast("Couldn't complete that suggestion — the capture is still in your inbox.")
    }

    func dismiss(item: InboxItem) async {
        do {
            try await inboxRepo.dismiss(uuid: item.uuid)
            registerDismissUndo(for: [item])
            presentUndoToast(message: "Dismissed \(item.title ?? String(item.rawText.prefix(40)))")
            loadEmptyStateData()
        } catch {
            print("⚠️ [InboxVM] Dismiss failed: \(error)")
            PersistenceHealth.note(.writeFailure, context: "InboxVM.dismiss", detail: error.localizedDescription)
            presentErrorToast("Couldn't dismiss that capture.")
        }
    }

    func placeAndGo(_ item: InboxItem) async {
        processingItemIds.insert(item.uuid)
        defer { processingItemIds.remove(item.uuid) }

        do {
            guard let atom = try await executor.executePrimaryRecommendation(item: item) else {
                await recoverFromNilExecution(for: item)
                return
            }
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
            PersistenceHealth.note(.writeFailure, context: "InboxVM.placeAndGo", detail: error.localizedDescription)
            presentErrorToast("Couldn't place that capture — it's still in your inbox.")
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
            PersistenceHealth.note(.writeFailure, context: "InboxVM.makeTask", detail: error.localizedDescription)
            presentErrorToast("Couldn't create the task — the capture is still in your inbox.")
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
            PersistenceHealth.note(.writeFailure, context: "InboxVM.fileAsIdea", detail: error.localizedDescription)
            presentErrorToast("Couldn't file the idea — the capture is still in your inbox.")
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
            PersistenceHealth.note(.writeFailure, context: "InboxVM.askInDeepDive", detail: error.localizedDescription)
            presentErrorToast("Couldn't create the question — the capture is still in your inbox.")
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
            PersistenceHealth.note(.writeFailure, context: "InboxVM.connectCapture", detail: error.localizedDescription)
            presentErrorToast("Couldn't create the concept — the capture is still in your inbox.")
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

    /// Bulk dismiss registers ONE undo action restoring every item and shows
    /// one toast. (The >5-item confirmation lives in InboxBatchBar.)
    func dismissAllSelected() async {
        let selectedItems = items.filter { selectedItemIds.contains($0.uuid) }
        guard !selectedItems.isEmpty else { return }

        var dismissed: [InboxItem] = []
        for item in selectedItems {
            do {
                try await inboxRepo.dismiss(uuid: item.uuid)
                dismissed.append(item)
            } catch {
                print("⚠️ [InboxVM] Bulk dismiss failed for \(item.uuid): \(error)")
                PersistenceHealth.note(.writeFailure, context: "InboxVM.dismissAllSelected", detail: error.localizedDescription)
            }
        }

        if !dismissed.isEmpty {
            registerDismissUndo(for: dismissed)
            presentUndoToast(message: "Dismissed \(dismissed.count) capture\(dismissed.count == 1 ? "" : "s")")
            loadEmptyStateData()
        }
        if dismissed.count < selectedItems.count {
            presentErrorToast("Couldn't dismiss \(selectedItems.count - dismissed.count) capture(s).")
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
            if try await executor.executeMerge(item: item, targetAtomUuid: targetUuid) != nil {
                presentUndoToast(for: item)
                showOverrideSheet = false
            } else {
                presentErrorToast("That merge target no longer exists — pick another destination.")
            }
        } catch {
            print("⚠️ [InboxVM] Override merge failed: \(error)")
            PersistenceHealth.note(.writeFailure, context: "InboxVM.overrideMerge", detail: error.localizedDescription)
            presentErrorToast("Couldn't merge — the capture is still in your inbox.")
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
            PersistenceHealth.note(.writeFailure, context: "InboxVM.overridePlace", detail: error.localizedDescription)
            presentErrorToast("Couldn't place — the capture is still in your inbox.")
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
            PersistenceHealth.note(.writeFailure, context: "InboxVM.overrideNew", detail: error.localizedDescription)
            presentErrorToast("Couldn't create — the capture is still in your inbox.")
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
                let captures = try await inboxRepo.fetchRecentHistory(limit: 6)
                let deletedLanes = try await destinationRepo.fetchArchived(limit: 6)
                recentHistory = Array(captures.prefix(3))
                recentHistoryEntries = InboxHistoryEntry.merged(
                    captures: captures,
                    deletedLanes: deletedLanes,
                    limit: 6
                )
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
        let message: String
        if let verb {
            message = verb
        } else if let destination, item.classification == .place {
            message = "Placed in \(destination)"
        } else if item.classification == .merge, let target = item.mergeTargetTitle {
            message = "Merged into \(target)"
        } else {
            message = "Filed \(item.title ?? String(item.rawText.prefix(40)))"
        }
        presentUndoToast(message: message)
    }

    private func presentUndoToast(message: String) {
        presentToast(message: message, isError: false)
    }

    /// Failure variant — no Undo button, warning styling. Nil results and
    /// caught write errors must never masquerade as success.
    private func presentErrorToast(_ message: String) {
        presentToast(message: message, isError: true)
    }

    private func presentToast(message: String, isError: Bool) {
        undoToastTask?.cancel()
        undoToastMessage = message
        undoToastIsError = isError
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

    // MARK: - Dismiss Undo & History Restore

    /// Dismiss gets the same undo treatment as every accept verb — one
    /// registration covers single and bulk dismissals.
    private func registerDismissUndo(for dismissedItems: [InboxItem]) {
        let originals = dismissedItems
        let repo = inboxRepo
        let description = originals.count == 1
            ? "Dismiss Inbox Capture"
            : "Dismiss \(originals.count) Inbox Captures"
        CosmoUndoManager.shared.register(
            InlineUndoAction(actionDescription: description) {
                for item in originals {
                    try? await repo.restore(item)
                }
            } redo: {
                for item in originals {
                    try? await repo.dismiss(uuid: item.uuid)
                }
            }
        )
    }

    /// Restore a dismissed/actioned item from the history list back into the
    /// active queue. (InboxRepository.restore upserts the row as given.)
    func restoreFromHistory(_ item: InboxItem) async {
        var restored = item
        restored.status = item.classification != nil ? .classified : .pending
        restored.actionedAt = nil
        do {
            try await inboxRepo.restore(restored)
            loadEmptyStateData()
        } catch {
            print("⚠️ [InboxVM] Restore failed: \(error)")
            PersistenceHealth.note(.writeFailure, context: "InboxVM.restoreFromHistory", detail: error.localizedDescription)
            presentErrorToast("Couldn't restore that capture.")
        }
    }

    func restoreDeletedLane(_ lane: CaptureDestination) async {
        do {
            try await destinationRepo.restore(uuid: lane.uuid)
            loadEmptyStateData()
        } catch {
            print("⚠️ [InboxVM] Restore lane failed: \(error)")
            PersistenceHealth.note(.writeFailure, context: "InboxVM.restoreDeletedLane", detail: error.localizedDescription)
            presentErrorToast("Couldn't restore that lane.")
        }
    }
}
