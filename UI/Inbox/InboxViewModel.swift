// CosmoOS/UI/Inbox/InboxViewModel.swift
// State for the triage-queue Inbox — temporal sections, single-focus inspector,
// keyboard-first verbs, quick capture, batch actions, undo.
//
// June 2026 rebuild (INBOX_REVAMP_PLAN.md §3): the inbox shows only explicit
// captures. The unplaced-database scan, soft-cluster grid, view modes, filter
// rows, and per-item LLM insights are gone — one calm ledger, one inspector.

import SwiftUI
import Combine
import UniformTypeIdentifiers

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
        switch await InboxScanIngestService.shared.ingest(images: images, captureText: captureText) {
        case .captured, .routedToLane:
            showCaptureConfirmation = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                showCaptureConfirmation = false
            }
        case .failed(let detail):
            captureError = "Couldn't digitize the scan — \(detail)"
        }
    }

    /// "Upload images…" — pictures attach as pictures through the drop
    /// pipeline (OCR rides the attachment for search only). The LLM
    /// transcription pass is reserved for the scan intake above.
    func ingestUploadedImages(_ files: [(data: Data, filename: String)]) async {
        guard !files.isEmpty else { return }
        captureError = nil
        let payloads: [DropPayload] = files.map { file in
            let ext = (file.filename as NSString).pathExtension
            let type = UTType(filenameExtension: ext) ?? .image
            return .data(file.data, type: type, suggestedName: file.filename)
        }
        let text = captureText
        if await LaneCaptureAssist.resolvedMatch(for: text) != nil {
            let result = await InboxDropIngestService.shared.ingestCombined(text: text, attachments: payloads)
            if case .failed(let detail) = result.outcome {
                captureError = "Couldn't attach — \(detail)"
            } else if !result.failedNames.isEmpty {
                captureError = "Couldn't attach \(result.failedNames.joined(separator: ", "))"
            } else {
                if captureText == text { captureText = "" }
                showCaptureConfirmation = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    showCaptureConfirmation = false
                }
            }
            return
        }
        let results = await InboxDropIngestService.shared.ingest(payloads)
        let failure = results.compactMap { result -> String? in
            if case .failed(let detail) = result.outcome { return detail }
            return nil
        }.first
        if let failure {
            captureError = "Couldn't attach — \(failure)"
        } else {
            showCaptureConfirmation = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                showCaptureConfirmation = false
            }
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
    /// Which destination family the sheet opens on — the A verb lands on
    /// inquiries, the row menu's "Move to lane…" on lanes.
    var overrideFocus: InboxOverrideFocus = .destinations

    // MARK: - Lanes & inquiry Spaces (September 2026)

    /// Active capture lanes — the "Move to lane" menus and the destination
    /// sheet's Lanes section. Refreshed on start and on every lane change.
    private(set) var lanes: [CaptureDestination] = []

    /// A route the view should adopt (the toast's "Open" after a move to a
    /// lane). The view applies it and clears it.
    var pendingRoute: SidebarInboxRoute?

    /// Growing seedlings across every scope, ripest first — the manual
    /// "Grow a concept" path the queue never had (G always started a NEW
    /// seed named after the capture). Refreshed on start, on visibility,
    /// and after every grow verb.
    private(set) var seedlings: [Seedling] = []

    private func refreshSeedlings() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let growing = (try? await SeedlingRepository.shared.fetchGrowingAllScopes(limit: 40)) ?? []
            if growing != self.seedlings { self.seedlings = growing }
        }
    }

    /// Every Space that can host an inquiry session, sidebar order.
    var inquirySpaces: [InquirySpaceOption] {
        ThinkspaceManager.shared.thinkspaces
            .filter { $0.id != ThinkspaceManager.commandCenterUUID }
            .map { InquirySpaceOption(id: $0.id, name: $0.name) }
    }

    private func refreshLanes() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let active = (try? await self.destinationRepo.fetchActive()) ?? []
            if active != self.lanes { self.lanes = active }
        }
    }

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
    /// Optional follow-up the toast offers beside Undo ("Develop now" after a
    /// grow). Doing nothing is the quiet default — the toast just fades.
    var undoToastActionLabel: String?
    private var undoToastAction: (@MainActor () -> Void)?

    func runUndoToastAction() {
        undoToastAction?()
    }

    // MARK: - Private

    private var inboxRepo: InboxRepository { .shared }
    private var destinationRepo: CaptureDestinationRepository { .shared }
    private var executor: InboxActionExecutor { .shared }
    private var atomRepo: AtomRepository { .shared }
    @ObservationIgnored private let historyRefresh = CoalescingRefresh()
    @ObservationIgnored private var isSubmittingCapture = false
    private var cancellables = Set<AnyCancellable>()
    private var undoToastTask: Task<Void, Never>?
    private var overrideSearchTask: Task<Void, Never>?
    private var overrideSearchRequestID = UUID()

    /// Visibility drives the Atlas sweep for unsorted items — batched,
    /// throttled, and never run while the inbox is off-screen.
    var isInboxVisible: Bool = false {
        didSet {
            guard isInboxVisible, !oldValue else { return }
            applyItems(inboxRepo.items)
            InboxIngestService.shared.runAtlasSweepIfNeeded()
            loadEmptyStateData()
            refreshSeedlings()
        }
    }

    var thinkspaces: [Thinkspace] {
        ThinkspaceManager.shared.thinkspaces
    }

    // MARK: - Init

    /// True when at least one flow exists — gates the `→ Flow` verb. Cached
    /// rather than queried per render: the inspector reads it on every frame,
    /// and the answer changes only when the library does.
    private(set) var hasFlows = false

    /// Pure allocation. `@State`'s initial-value expression is EAGER — this
    /// model is constructed (and discarded) on every InboxView struct
    /// construction, i.e. every MainView body pass while Inbox is the
    /// destination. The observation + first loads run once from the mounted
    /// instance via `startIfNeeded()`.
    init() {}

    private var hasStarted = false

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        startObserving()
        refreshFlowAvailability()
        refreshLanes()
        refreshSeedlings()
    }

    private func refreshFlowAvailability() {
        Task { @MainActor in
            hasFlows = await SwipeFlowStore.hasAnyFlow()
        }
    }

    // MARK: - Observation

    private func startObserving() {
        // Repository delivery is already transaction-coalesced. Delaying it
        // made a successful capture/dismiss appear unchanged for 350 ms.
        inboxRepo.$items
            .removeDuplicates()
            .sink { [weak self] newItems in
                guard let self, self.isInboxVisible else { return }
                self.applyItems(newItems)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: CosmoNotification.Inbox.captureLaneChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.loadEmptyStateData()
                    self?.refreshLanes()
                }
            }
            .store(in: &cancellables)

        // The first flow a user makes must light up the `→ Flow` verb without
        // a relaunch.
        NotificationCenter.default.publisher(for: CosmoNotification.SwipeFile.libraryDidChange)
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshFlowAvailability()
            }
            .store(in: &cancellables)
    }

    func applyItems(_ newItems: [InboxItem]) {
        guard items != newItems else { return }
        let previousIndex = focusedItemId.flatMap { id in items.firstIndex { $0.uuid == id } }
        items = newItems
        regroupItems()
        reconcileFocus(previousIndex: previousIndex)
        selectedItemIds.formIntersection(newItems.map(\.uuid))
    }

    /// Keep keyboard focus on a real row after items change underneath it.
    private func reconcileFocus(previousIndex: Int?) {
        guard let focusedItemId, !items.contains(where: { $0.uuid == focusedItemId }) else { return }
        self.focusedItemId = items.isEmpty ? nil : items[min(previousIndex ?? 0, items.count - 1)].uuid
        if items.isEmpty { isInspectorOpen = false }
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
        guard !text.isEmpty, !isSubmittingCapture else { return }
        isSubmittingCapture = true
        defer { isSubmittingCapture = false }
        let submittedText = captureText

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
            // A fast typist can already be entering the next thought while
            // the previous write completes. Only clear the submitted draft.
            if captureText == submittedText {
                captureText = ""
                isCaptureExpanded = false
            }
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

    // MARK: - Correction ledger

    /// Atlas move kinds whose ACCEPTS are worth recording as positive examples
    /// (spatial placements are plentiful; knowledge-graph moves are the signal).
    private static let atlasMoveKinds: Set<InboxRouteKind> = [
        .advanceQuestion, .spawnQuestion, .feedConnection,
        .attachClient, .germinateConnection, .germinateDeepDive, .startInquiry,
        .feedSeedling, .startSeedling
    ]

    /// Fire-and-forget ledger write: what the user did with this capture, and
    /// which suggestion (if any) they rejected in doing so. The Atlas router
    /// replays these as learned rules.
    private func recordRoutingOutcome(
        for item: InboxItem,
        chosenKind: String,
        chosenLabel: String,
        countsAsOverride: Bool = true
    ) {
        let primary = item.primaryRecommendationValue
        let hadSuggestion = countsAsOverride
            && item.hasActionableSuggestion
            && primary != nil
            && primary?.kind != .createStandaloneAtom
        let text = item.rawText
        let rejectedKind = hadSuggestion ? primary?.kind.rawValue : nil
        let rejectedLabel = hadSuggestion ? primary?.destinationPath : nil
        Task.detached {
            await InboxRoutingCorrectionLedger.shared.record(
                text: text,
                chosenKind: chosenKind,
                chosenLabel: chosenLabel,
                rejectedKind: rejectedKind,
                rejectedLabel: rejectedLabel
            )
        }
    }

    // MARK: - Core Verbs

    func acceptSuggestion(for item: InboxItem) async {
        guard processingItemIds.insert(item.uuid).inserted else { return }
        defer { processingItemIds.remove(item.uuid) }

        do {
            if let outcome = try await executor.executePrimaryRecommendation(item: item) {
                presentOutcomeToast(for: item, outcome: outcome, destination: item.spatialDestinationTitle)
                if let primary = item.primaryRecommendationValue,
                   Self.atlasMoveKinds.contains(primary.kind) {
                    recordRoutingOutcome(
                        for: item,
                        chosenKind: primary.kind.rawValue,
                        chosenLabel: primary.destinationPath,
                        countsAsOverride: false
                    )
                }
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

        guard processingItemIds.insert(item.uuid).inserted else { return }
        defer { processingItemIds.remove(item.uuid) }

        do {
            let final = adjustedPosition.map { recommendation.overridingBlockPosition($0) } ?? recommendation
            if let outcome = try await executor.executeRecommendation(item: item, recommendation: final) {
                presentOutcomeToast(for: item, outcome: outcome, destination: item.spatialDestinationTitle)
            } else {
                await recoverFromNilExecution(for: item)
            }
        } catch {
            print("⚠️ [InboxVM] Place failed: \(error)")
            PersistenceHealth.note(.writeFailure, context: "InboxVM.place", detail: error.localizedDescription)
            presentErrorToast("Couldn't place that capture — it's still in your inbox.")
        }
    }

    /// Apply a non-primary recommendation (the inspector's "Also possible"
    /// rows). Choosing an alternate over the primary is teaching signal —
    /// it lands in the correction ledger.
    func applyAlternate(_ item: InboxItem, recommendation: InboxRecommendation) async {
        guard processingItemIds.insert(item.uuid).inserted else { return }
        defer { processingItemIds.remove(item.uuid) }

        do {
            if let outcome = try await executor.executeRecommendation(item: item, recommendation: recommendation) {
                presentOutcomeToast(for: item, outcome: outcome, destination: recommendation.destinationPath)
                recordRoutingOutcome(
                    for: item,
                    chosenKind: recommendation.kind.rawValue,
                    chosenLabel: recommendation.destinationPath
                )
            } else {
                await recoverFromNilExecution(for: item)
            }
        } catch {
            print("⚠️ [InboxVM] Alternate failed: \(error)")
            PersistenceHealth.note(.writeFailure, context: "InboxVM.applyAlternate", detail: error.localizedDescription)
            presentErrorToast("Couldn't apply that suggestion — the capture is still in your inbox.")
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
        guard processingItemIds.insert(item.uuid).inserted else { return }
        defer { processingItemIds.remove(item.uuid) }
        do {
            try await inboxRepo.dismiss(uuid: item.uuid)
            if item.hasActionableSuggestion {
                recordRoutingOutcome(for: item, chosenKind: "dismiss", chosenLabel: "Dismissed")
            }
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
        guard processingItemIds.insert(item.uuid).inserted else { return }
        defer { processingItemIds.remove(item.uuid) }

        do {
            guard let outcome = try await executor.executePrimaryRecommendation(item: item) else {
                await recoverFromNilExecution(for: item)
                return
            }
            // Grow & Develop: for a concept suggestion, "go" means the
            // development conversation — the page is born and opens.
            if case .seedling(let seedling) = outcome {
                presentUndoToast(for: item, verb: "\u{201C}\(seedling.name)\u{201D} is growing")
                developSeedlingNow(uuid: seedling.uuid)
                return
            }
            presentOutcomeToast(for: item, outcome: outcome, destination: item.spatialDestinationTitle)
            guard let atom = outcome.atom else { return }
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.openAtomFromCommandK,
                object: nil, userInfo: ["atomUUID": atom.uuid])
        } catch {
            print("⚠️ [InboxVM] Place & Go failed: \(error)")
            PersistenceHealth.note(.writeFailure, context: "InboxVM.placeAndGo", detail: error.localizedDescription)
            presentErrorToast("Couldn't place that capture — it's still in your inbox.")
        }
    }

    /// The destination picker and its receipt name the same actual operation.
    func fileCapture(_ item: InboxItem, destination: InboxFilingDestination, action: InboxFilingAction) async -> String? {
        guard processingItemIds.insert(item.uuid).inserted else { return "This capture is already saving." }
        defer { processingItemIds.remove(item.uuid) }
        do {
            if action == .swipe {
                let outcome = try await executor.executeSwipeOutcome(item: item)
                presentUndoToast(message: outcome.adoptedExisting ? "Existing Swipe reused" : "Saved in Swipe")
            } else {
                let (atom, receipt) = try await executor.executeFiling(item: item, destination: destination, action: action)
                presentFilingReceipt(receipt)
                if atom.type == .idea { Task { await IdeaInsightEngine.shared.quickEnrich(atom: atom) } }
            }
            showOverrideSheet = false
            recordRoutingOutcome(for: item, chosenKind: action.rawValue, chosenLabel: destination.path)
            await refreshHistory()
            return nil
        } catch {
            presentErrorToast(error.localizedDescription)
            return error.localizedDescription
        }
    }

    private func presentFilingReceipt(_ receipt: InboxPlacementReceipt) {
        presentToast(message: receipt.outcome, isError: false, actionLabel: "Open") {
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.openAtomFromCommandK, object: nil,
                userInfo: ["atomUUID": receipt.resultAtomUUID])
        }
        Task { await refreshHistory() }
    }

    func undoFilingFromHistory(_ item: InboxItem) async {
        guard let receipt = item.placementReceipt else { return }
        do {
            let result = try await InboxPlacementService.shared.undo(receipt)
            presentUndoToast(message: result.retainedOriginal ? "Filing undone · edited original retained" : "Filing undone")
            await refreshHistory()
        } catch { presentErrorToast(error.localizedDescription) }
    }

    // MARK: - Closed-Loop Verbs

    /// T — the capture is a task: it belongs in the Command Center, not a canvas.
    func makeTask(_ item: InboxItem) async {
        guard processingItemIds.insert(item.uuid).inserted else { return }
        defer { processingItemIds.remove(item.uuid) }

        do {
            _ = try await executor.executeNew(item: item, atomType: .task)
            presentUndoToast(for: item, verb: "Task created")
            recordRoutingOutcome(for: item, chosenKind: "task", chosenLabel: "Task")
        } catch {
            print("⚠️ [InboxVM] Make task failed: \(error)")
            PersistenceHealth.note(.writeFailure, context: "InboxVM.makeTask", detail: error.localizedDescription)
            presentErrorToast("Couldn't create the task — the capture is still in your inbox.")
        }
    }

    /// I — the capture is an idea: type it and let the idea pipeline enrich it.
    func fileAsIdea(_ item: InboxItem) async {
        guard processingItemIds.insert(item.uuid).inserted else { return }
        defer { processingItemIds.remove(item.uuid) }

        do {
            let atom = try await executor.executeNew(item: item, atomType: .idea)
            presentUndoToast(for: item, verb: "Filed as idea")
            recordRoutingOutcome(for: item, chosenKind: "idea", chosenLabel: "Standalone idea")
            Task { await IdeaInsightEngine.shared.quickEnrich(atom: atom) }
        } catch {
            print("⚠️ [InboxVM] File as idea failed: \(error)")
            PersistenceHealth.note(.writeFailure, context: "InboxVM.fileAsIdea", detail: error.localizedDescription)
            presentErrorToast("Couldn't file the idea — the capture is still in your inbox.")
        }
    }

    /// S — the capture is a link: file it into the Swipe File (the command-bar
    /// capture pipeline, run from triage). Surfaced in the UI only on a real link.
    func fileAsSwipe(_ item: InboxItem) async {
        guard processingItemIds.insert(item.uuid).inserted else { return }
        defer { processingItemIds.remove(item.uuid) }

        do {
            let outcome = try await executor.executeSwipeOutcome(item: item)
            // Adoption is different news than creation — "Saved as swipe"
            // over a dedup reads as the library eating the capture.
            presentUndoToast(
                for: item,
                verb: outcome.adoptedExisting ? "Already in your Swipe File" : "Saved as swipe"
            )
            recordRoutingOutcome(for: item, chosenKind: "swipe", chosenLabel: "Swipe File")
        } catch {
            print("⚠️ [InboxVM] File as swipe failed: \(error)")
            PersistenceHealth.note(.writeFailure, context: "InboxVM.fileAsSwipe", detail: error.localizedDescription)
            presentErrorToast("Couldn't save that swipe — the capture is still in your inbox.")
        }
    }

    /// F — the capture is a step in a funnel being assembled. Appends to the
    /// flow the user is recording into, or to the most recently touched one.
    ///
    /// The capture becomes a swipe first (through the one front door), then
    /// joins the flow: a flow step IS a swipe, so there is no second object
    /// type and no second capture path.
    func addCaptureToFlow(_ item: InboxItem) async {
        guard let flow = await SwipeFlowStore.flows().first else {
            presentErrorToast("No flows yet — start one from a swipe's menu.")
            return
        }
        guard processingItemIds.insert(item.uuid).inserted else { return }
        defer { processingItemIds.remove(item.uuid) }

        do {
            let swipe = try await executor.executeSwipe(item: item)
            guard await SwipeFlowStore.append(swipeUUID: swipe.uuid, toFlow: flow.uuid) else {
                presentErrorToast("Couldn't add that step — the swipe is in your Swipe File.")
                return
            }
            presentUndoToast(for: item, verb: "Added to \(flow.title ?? "the flow")")
            recordRoutingOutcome(for: item, chosenKind: "flow", chosenLabel: "Step in a flow")
        } catch {
            print("⚠️ [InboxVM] Add to flow failed: \(error)")
            PersistenceHealth.note(.writeFailure, context: "InboxVM.addCaptureToFlow", detail: error.localizedDescription)
            presentErrorToast("Couldn't add that step — the capture is still in your inbox.")
        }
    }

    /// A — the capture is something to research: it becomes a resumable
    /// inquiry session inside a Space (an existing one, or a new Space named
    /// for the topic). The old verb filed a bare question under whichever
    /// deep dive was touched last — the "stuck with nowhere to research"
    /// gap this closes.
    func startInquiry(_ item: InboxItem, in choice: InquirySpaceChoice) async {
        guard processingItemIds.insert(item.uuid).inserted else { return }
        defer { processingItemIds.remove(item.uuid) }

        do {
            let start: InboxActionExecutor.InquiryStart?
            switch choice {
            case .existing(let space):
                start = try await executor.executeStartInquiry(item: item, spaceID: space.id, question: item.title)
            case .new(let name):
                start = try await executor.executeStartInquiryInNewSpace(item: item, spaceName: name, question: item.title)
            }
            guard let start else {
                presentErrorToast("That Space is no longer available — pick another one.")
                return
            }
            showOverrideSheet = false
            presentInquiryToast(for: start)
            recordRoutingOutcome(
                for: item,
                chosenKind: InboxRouteKind.startInquiry.rawValue,
                chosenLabel: "\(start.spaceName) › Inquiry"
            )
            await refreshHistory()
        } catch {
            print("⚠️ [InboxVM] Start inquiry failed: \(error)")
            PersistenceHealth.note(.writeFailure, context: "InboxVM.startInquiry", detail: error.localizedDescription)
            presentErrorToast("Couldn't start the inquiry — the capture is still in your inbox.")
        }
    }

    /// Lane → lane: the ledger row's routing changes and the lane's recency
    /// bumps. Undo puts the row back exactly where it was.
    private func moveLaneCapture(_ item: InboxItem, to lane: CaptureDestination) async {
        let repo = CapturedItemRepository.shared
        guard let row = try? await repo.fetch(uuid: item.uuid) else {
            presentErrorToast("That capture is no longer in a lane.")
            return
        }
        guard row.captureDestinationId != lane.uuid else {
            presentErrorToast("Already in \(lane.name).")
            return
        }
        do {
            try await Self.reroute(row, toLane: lane.uuid, intent: "lane_move")
            await destinationRepo.markUsed(uuid: lane.uuid)
            showOverrideSheet = false
            NotificationCenter.default.post(name: CosmoNotification.Inbox.captureLaneChanged, object: nil)
            let original = row
            let laneID = lane.uuid
            CosmoUndoManager.shared.register(
                InlineUndoAction(actionDescription: "Move Capture to Lane") {
                    try? await Self.reroute(original, toLane: original.captureDestinationId, intent: original.parsedIntent ?? "lane_move")
                    NotificationCenter.default.post(name: CosmoNotification.Inbox.captureLaneChanged, object: nil)
                } redo: {
                    try? await Self.reroute(original, toLane: laneID, intent: "lane_move")
                    NotificationCenter.default.post(name: CosmoNotification.Inbox.captureLaneChanged, object: nil)
                }
            )
            presentToast(
                message: "Moved to \(lane.name)",
                isError: false,
                actionLabel: "Open",
                action: { [weak self] in
                    self?.dismissUndoToast()
                    self?.pendingRoute = .captureLane(id: laneID)
                }
            )
            recordRoutingOutcome(for: item, chosenKind: "lane", chosenLabel: lane.name, countsAsOverride: false)
        } catch {
            print("⚠️ [InboxVM] Lane move failed: \(error)")
            PersistenceHealth.note(.writeFailure, context: "InboxVM.moveLaneCapture", detail: error.localizedDescription)
            presentErrorToast("Couldn't move that capture — it's still in its lane.")
        }
    }

    /// A routing flip that keeps every other field as the row has it.
    private static func reroute(_ row: CapturedItem, toLane laneID: String?, intent: String) async throws {
        try await CapturedItemRepository.shared.updateRouting(
            uuid: row.uuid,
            destinationId: laneID,
            parsedCommand: row.parsedCommand,
            parsedIntent: intent,
            confidence: row.routingConfidence,
            status: row.status,
            createdObjectIds: row.createdObjectIds,
            parentDeepDiveId: row.parentDeepDiveId,
            parentInquirySessionId: row.parentInquirySessionId,
            parentQuestionId: row.parentQuestionId,
            parentProjectId: row.parentProjectId
        )
    }

    /// The A key — no Space named yet, so the destination sheet opens on
    /// its inquiry section.
    func askInDeepDive(_ item: InboxItem) async {
        showOverride(for: item, focus: .inquiry)
    }

    /// "Inquiry started in ‹Space›" — the Open follow-up lands in that
    /// Space's Inquiries with the session running.
    private func presentInquiryToast(for start: InboxActionExecutor.InquiryStart) {
        presentToast(
            message: "Inquiry started in \(start.spaceName)",
            isError: false,
            actionLabel: "Open",
            action: { [weak self] in self?.openInquiry(start) }
        )
    }

    private func openInquiry(_ start: InboxActionExecutor.InquiryStart) {
        dismissUndoToast()
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.navigateToThinkspaceById,
            object: nil,
            userInfo: CosmoNotification.Navigation.ThinkspacePayload(thinkspaceId: start.spaceID).userInfo
        )
        SpaceMapPreferences.shared.select(.inquiries, in: start.spaceID)
        _ = SpaceViewStore.shared.select(.deepDive, for: start.spaceID)
        let session = start.session
        Task {
            guard let parent = session.inquirySessionMetadata?.parentDeepDiveUUID else { return }
            await InquirySessionLauncher.shared.launch(
                anchorUUID: parent,
                anchorType: "deep_dive",
                resumeSessionUUID: session.uuid,
                mainQuestionTitle: session.title,
                rootQuestionUUID: session.inquirySessionMetadata?.mainQuestionUUID,
                appState: nil
            )
        }
    }

    /// The capture leaves the queue for a lane — a direct choice from the
    /// inspector's "Move to lane" menu, the row's context menu, or the
    /// destination sheet. Same receipt grammar as every verb (toast, undo);
    /// the Open follow-up lands inside that lane's ledger.
    func moveToLane(_ item: InboxItem, lane: CaptureDestination) async {
        guard processingItemIds.insert(item.uuid).inserted else { return }
        defer { processingItemIds.remove(item.uuid) }

        // A capture already at rest in a lane moves lane → lane: its ledger
        // row is re-routed, nothing is created. The lane page's inspector and
        // the destination sheet both land here, whichever model hosts them.
        if item.captureReference.kind == .lane {
            await moveLaneCapture(item, to: lane)
            return
        }

        do {
            _ = try await executor.executeRouteToLane(item: item, lane: lane)
            showOverrideSheet = false
            let laneID = lane.uuid
            presentToast(
                message: "Moved to \(lane.name)",
                isError: false,
                actionLabel: "Open",
                action: { [weak self] in
                    self?.dismissUndoToast()
                    self?.pendingRoute = .captureLane(id: laneID)
                }
            )
            recordRoutingOutcome(for: item, chosenKind: "lane", chosenLabel: lane.name)
            loadEmptyStateData()
        } catch {
            print("⚠️ [InboxVM] Move to lane failed: \(error)")
            PersistenceHealth.note(.writeFailure, context: "InboxVM.moveToLane", detail: error.localizedDescription)
            presentErrorToast("Couldn't move that capture — it's still in your inbox.")
        }
    }

    /// C — the capture bridges existing atoms: create a connection linked to
    /// the related material instead of merging or duplicating.
    func connectCapture(_ item: InboxItem) async {
        guard processingItemIds.insert(item.uuid).inserted else { return }
        defer { processingItemIds.remove(item.uuid) }

        do {
            _ = try await executor.executeConnect(item: item, relatedAtomUUIDs: item.relatedAtomUUIDsValue)
            presentUndoToast(for: item, verb: "Connected")
            recordRoutingOutcome(for: item, chosenKind: "connect", chosenLabel: "New connection")
        } catch {
            print("⚠️ [InboxVM] Connect failed: \(error)")
            PersistenceHealth.note(.writeFailure, context: "InboxVM.connectCapture", detail: error.localizedDescription)
            presentErrorToast("Couldn't create the concept — the capture is still in your inbox.")
        }
    }

    /// G — grow a concept. The destination sheet opens on the Growing
    /// concepts section so the thought can feed the seed it belongs to (or
    /// name a new one). The old verb always started a NEW seedling named
    /// after the capture, which is why seeds were unreachable by hand.
    func growSeedling(_ item: InboxItem) async {
        showOverride(for: item, focus: .concepts)
    }

    /// The capture adds mass to a growing seedling. No atom, no canvas
    /// object — the thought accrues with provenance and the seed ripens.
    func growSeedling(_ item: InboxItem, seedling: Seedling) async {
        guard processingItemIds.insert(item.uuid).inserted else { return }
        defer { processingItemIds.remove(item.uuid) }

        do {
            let recommendation = InboxRecommendation(
                kind: .feedSeedling,
                confidence: 1.0,
                suggestedAtomType: AtomType.connection.rawValue,
                destinationPath: "Grows \u{201C}\(seedling.name)\u{201D}",
                rationale: "Chosen by hand.",
                atlasMove: InboxAtlasMove(seedlingUUID: seedling.uuid, seedlingName: seedling.name)
            )
            guard let fed = try await executor.executeFeedSeedling(item: item, recommendation: recommendation) else {
                presentErrorToast("That concept is no longer growing — pick another one.")
                return
            }
            showOverrideSheet = false
            presentGrowToast(for: fed)
            recordRoutingOutcome(for: item, chosenKind: InboxRouteKind.feedSeedling.rawValue, chosenLabel: fed.name)
            refreshSeedlings()
        } catch {
            print("⚠️ [InboxVM] Grow seedling failed: \(error)")
            PersistenceHealth.note(.writeFailure, context: "InboxVM.growSeedling", detail: error.localizedDescription)
            presentErrorToast("Couldn't grow the concept — the capture is still in your inbox.")
        }
    }

    /// The capture names a NEW concept: a seedling is born with the thought
    /// as its first seed (or feeds a live seedling that already carries the
    /// same concept key — starting twice is an echo, not intent).
    func startSeedling(_ item: InboxItem, named name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard processingItemIds.insert(item.uuid).inserted else { return }
        defer { processingItemIds.remove(item.uuid) }

        do {
            let recommendation = InboxRecommendation(
                kind: .startSeedling,
                confidence: 1.0,
                suggestedAtomType: AtomType.connection.rawValue,
                destinationPath: "New concept: \(trimmed)",
                rationale: "Named by hand.",
                atlasMove: InboxAtlasMove(germinateTitle: trimmed)
            )
            if let seedling = try await executor.executeStartSeedling(item: item, recommendation: recommendation) {
                showOverrideSheet = false
                presentGrowToast(for: seedling)
                recordRoutingOutcome(for: item, chosenKind: InboxRouteKind.startSeedling.rawValue, chosenLabel: seedling.name)
                refreshSeedlings()
            }
        } catch {
            print("⚠️ [InboxVM] Start seedling failed: \(error)")
            PersistenceHealth.note(.writeFailure, context: "InboxVM.startSeedling", detail: error.localizedDescription)
            presentErrorToast("Couldn't start the concept — the capture is still in your inbox.")
        }
    }

    // MARK: - Research sources (September 2026)

    /// The capture is a SOURCE to read or study — a link, a video, scanned
    /// pages. It becomes a Research source (the research lens, never the
    /// Swipe File) and lands where the destination says: a Space's
    /// materials, a Group, a Page's references, a Concept's References, or
    /// the Library. The toast's Open lands on the source.
    func fileAsResearch(_ item: InboxItem, destination: InboxFilingDestination) async {
        guard processingItemIds.insert(item.uuid).inserted else { return }
        defer { processingItemIds.remove(item.uuid) }

        do {
            let (_, receipt) = try await executor.executeResearch(item: item, destination: destination)
            showOverrideSheet = false
            presentFilingReceipt(receipt)
            recordRoutingOutcome(
                for: item,
                chosenKind: InboxRouteKind.fileAsResearch.rawValue,
                chosenLabel: destination.kind == .research ? "Library › Research" : "\(destination.path) › Research"
            )
            if let url = item.detectedSwipeURL {
                // The correction is also the teaching — the domain prior
                // learns that links like this are read, not copied.
                SwipeLensRouter.recordDecision(lens: .research, url: url)
            }
        } catch {
            print("⚠️ [InboxVM] File as research failed: \(error)")
            PersistenceHealth.note(.writeFailure, context: "InboxVM.fileAsResearch", detail: error.localizedDescription)
            presentErrorToast(error.localizedDescription)
        }
    }

    // MARK: - Batch Actions

    func acceptAllSelected() async {
        let selectedItems = items.filter { selectedItemIds.contains($0.uuid) }
        selectedItemIds.removeAll()
        for item in selectedItems {
            await acceptSuggestion(for: item)
        }
    }

    /// True when EVERY selected capture could become a swipe. All-or-nothing
    /// on purpose: a bulk action that silently skips rows is how captures get
    /// lost, so the affordance simply does not appear for a mixed selection.
    var selectionCanAllBecomeSwipes: Bool {
        let selected = items.filter { selectedItemIds.contains($0.uuid) }
        guard selected.count > 1 else { return false }
        return selected.allSatisfy(\.canBecomeSwipe)
    }

    /// Batch-file the selection into the Swipe File. Each capture goes through
    /// `executeSwipe`, so each gets its own kind, its own undo, and its own
    /// decomposition — the batch is a convenience, never a different pipeline.
    func swipeAllSelected() async {
        let selected = items.filter { selectedItemIds.contains($0.uuid) && !processingItemIds.contains($0.uuid) }
        guard !selected.isEmpty else { return }
        let processing = Set(selected.map(\.uuid))
        processingItemIds.formUnion(processing)
        defer { processingItemIds.subtract(processing) }
        selectedItemIds.removeAll()

        var filed = 0
        for item in selected {
            do {
                _ = try await executor.executeSwipe(item: item)
                filed += 1
                recordRoutingOutcome(for: item, chosenKind: "swipe", chosenLabel: "Swipe File")
            } catch {
                print("⚠️ [InboxVM] Bulk swipe failed for \(item.uuid): \(error)")
                PersistenceHealth.note(
                    .writeFailure, context: "InboxVM.swipeAllSelected",
                    detail: error.localizedDescription
                )
            }
        }
        let failed = selected.count - filed
        if filed > 0 {
            presentUndoToast(message: filed == 1
                ? "Saved as swipe"
                : "Saved \(filed) swipes")
        }
        if failed > 0 {
            presentErrorToast(failed == selected.count
                ? "Couldn't save those swipes — the captures are still in your inbox."
                : "\(failed) couldn't be saved — they're still in your inbox.")
        }
    }

    /// Bulk dismiss registers ONE undo action restoring every item and shows
    /// one toast. (The >5-item confirmation lives in InboxBatchBar.)
    func dismissAllSelected() async {
        let selectedItems = items.filter { selectedItemIds.contains($0.uuid) && !processingItemIds.contains($0.uuid) }
        guard !selectedItems.isEmpty else { return }
        let processing = Set(selectedItems.map(\.uuid))
        processingItemIds.formUnion(processing)
        selectedItemIds.removeAll()
        defer { processingItemIds.subtract(processing) }

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
        showOverride(for: item, focus: .destinations)
    }

    func showOverride(for item: InboxItem, focus: InboxOverrideFocus) {
        overrideSearchTask?.cancel()
        overrideSearchRequestID = UUID()
        overrideItem = item
        overrideSearchResults = []
        overrideFocus = focus
        showOverrideSheet = true
    }

    func overrideMerge(item: InboxItem, targetUuid: String) async {
        guard processingItemIds.insert(item.uuid).inserted else { return }
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
        guard processingItemIds.insert(item.uuid).inserted else { return }
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
        guard processingItemIds.insert(item.uuid).inserted else { return }
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

    // MARK: - Edit capture text

    /// The user corrected a capture's text in the inspector. A tracked write
    /// that syncs to the phone like any other; the repo observation refreshes
    /// `items` (and so the focused inspector) on success.
    func editCaptureText(_ item: InboxItem, to newText: String) async {
        do {
            try await inboxRepo.editRawText(uuid: item.uuid, to: newText)
        } catch {
            print("⚠️ [InboxVM] Edit capture text failed: \(error)")
            PersistenceHealth.note(.writeFailure, context: "InboxVM.editCaptureText", detail: error.localizedDescription)
            presentErrorToast("Couldn't save your edit — the capture is unchanged.")
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
            await historyRefresh.run { [weak self] in
                await self?.refreshHistory()
            }
        }
    }

    private func refreshHistory() async {
        do {
            async let captureLoad = inboxRepo.fetchRecentHistory(limit: 6)
            async let laneLoad = destinationRepo.fetchArchived(limit: 6)
            async let countLoad = inboxRepo.countTriagedThisWeek()
            let (captures, deletedLanes, count) = try await (captureLoad, laneLoad, countLoad)
            recentHistory = Array(captures.prefix(3))
            recentHistoryEntries = InboxHistoryEntry.merged(
                captures: captures,
                deletedLanes: deletedLanes,
                limit: 6
            )
            triagedThisWeek = count
        } catch {
            print("⚠️ [InboxVM] Empty state data failed: \(error)")
        }
    }


    // MARK: - Undo

    func undoLastInboxAction() async {
        await CosmoUndoManager.shared.undo()
        withAnimation(ProMotionSprings.snappy) {
            showUndoToast = false
        }
    }

    func dismissUndoToast() {
        undoToastTask?.cancel()
        withAnimation(ProMotionSprings.snappy) {
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

    // MARK: - Develop now / later

    /// A grow-type accept ends in a CHOICE, not a silent receipt: the toast
    /// offers "Develop now" (the page is born from the accrued thoughts and
    /// opens in the concept workspace). Doing nothing IS "later" — the
    /// concept keeps growing where the Growing section shows it.
    private func presentGrowToast(for seedling: Seedling) {
        presentToast(
            message: "\u{201C}\(seedling.name)\u{201D} is growing",
            isError: false,
            actionLabel: "Develop now",
            action: { [weak self] in self?.developSeedlingNow(uuid: seedling.uuid) }
        )
    }

    private func developSeedlingNow(uuid: String) {
        dismissUndoToast()
        Task {
            guard let connectionUUID = await SeedlingDevelopService.shared.develop(seedlingUUID: uuid) else { return }
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openBlockInFocusMode,
                object: nil,
                userInfo: ["atomUUID": connectionUUID]
            )
        }
    }

    /// Route the accept receipt by what the executor actually produced —
    /// grown seedlings get the develop-now choice, atoms get the undo toast.
    private func presentOutcomeToast(
        for item: InboxItem,
        outcome: InboxExecutionOutcome,
        destination: String
    ) {
        if case .filed(_, let receipt) = outcome {
            presentFilingReceipt(receipt)
        } else if case .seedling(let seedling) = outcome {
            presentGrowToast(for: seedling)
        } else {
            presentUndoToast(for: item, destination: destination)
        }
    }

    /// Lane surfaces borrow the queue's toast lane for their own outcomes
    /// (archive, edit failures) — one notification voice for the whole inbox.
    func presentLaneToast(_ message: String, isError: Bool = false) {
        presentToast(message: message, isError: isError)
    }

    /// Failure variant — no Undo button, warning styling. Nil results and
    /// caught write errors must never masquerade as success.
    private func presentErrorToast(_ message: String) {
        presentToast(message: message, isError: true)
    }

    private func presentToast(
        message: String,
        isError: Bool,
        actionLabel: String? = nil,
        action: (@MainActor () -> Void)? = nil
    ) {
        undoToastTask?.cancel()
        undoToastMessage = message
        undoToastIsError = isError
        undoToastActionLabel = actionLabel
        undoToastAction = action
        withAnimation(ProMotionSprings.snappy) {
            showUndoToast = true
        }

        undoToastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self, !Task.isCancelled else { return }
            withAnimation(ProMotionSprings.snappy) {
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

// MARK: - Inspector host

/// The queue model already speaks the inspector's whole grammar.
extension InboxViewModel: InboxInspectorHost {}
