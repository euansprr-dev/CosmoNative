// CosmoOS/UI/Inbox/CaptureLanesView.swift
// Capture lanes as a destinations grid — Finder grammar (adaptive tiles,
// folder iconography, counts), drill into a lane for its captures, with the
// Telegram command registry beneath. June 2026 rebuild.

import AppKit
import SwiftUI

@Observable
@MainActor
final class CaptureLanesViewModel {
    var destinations: [CaptureDestination] = []
    var selectedDestinationId: String?
    var selectedItems: [CapturedItem] = []
    var attachmentsByItemId: [String: [MediaAttachment]] = [:]
    var newLaneName = ""
    var isCreatingLane = false
    /// Stranded captures: nil destination with status captured/needsReview/failed.
    /// No other view displays these rows — without this section they are invisible.
    var needsReviewItems: [CapturedItem] = []

    /// The single focused capture — drives the lane inspector, the same
    /// focus/inspector pair the queue's InboxViewModel keeps.
    var focusedCaptureId: String?
    var isInspectorOpen = false
    /// The queue's model, lent by InboxView — lane verbs delegate to it so
    /// created atoms, toasts, undo, and the override sheet run through the
    /// one existing pipeline.
    weak var triageModel: InboxViewModel?

    var focusedCapture: CapturedItem? {
        guard let focusedCaptureId else { return nil }
        return selectedItems.first { $0.uuid == focusedCaptureId }
    }

    func focusCapture(_ item: CapturedItem) {
        focusedCaptureId = item.uuid
        isInspectorOpen = true
    }

    /// A lane capture dressed as an InboxItem for the shared inspector. The
    /// uuid carries over unchanged: every executor write against inbox_items
    /// guard-fetches first and no-ops for a captured_items uuid, while the
    /// atoms the verbs create come out real.
    func inspectorItem(for capture: CapturedItem) -> InboxItem {
        let attachmentUUIDs = (attachmentsByItemId[capture.uuid] ?? []).map(\.uuid)
        let payload: [String: Any] = ["attachmentUUIDs": attachmentUUIDs, "captureRecordKind": "lane"]
        let metadata = (try? JSONSerialization.data(withJSONObject: payload)).map { String(decoding: $0, as: UTF8.self) }
        return InboxItem(
            id: nil,
            uuid: capture.uuid,
            source: capture.source == .telegram ? .telegramText : .quickCapture,
            rawText: displayText(for: capture),
            title: nil,
            classification: nil,
            confidence: 0,
            mergeTargetUuid: nil,
            mergeTargetTitle: nil,
            mergeTargetType: nil,
            mergePreview: nil,
            placeThinkspaceId: nil,
            placeThinkspaceName: nil,
            placeAtomType: nil,
            recommendations: nil,
            primaryRouteKind: nil,
            destinationPath: nil,
            rationale: nil,
            placementPlanSummary: nil,
            status: .classified,
            isRead: true,
            createdAt: capture.createdAt,
            classifiedAt: nil,
            actionedAt: nil,
            metadata: metadata,
            isDeleted: false,
            syncUpdatedAt: nil,
            localVersion: capture.localVersion,
            serverVersion: capture.serverVersion,
            syncVersion: capture.syncVersion
        )
    }

    private func displayText(for capture: CapturedItem) -> String {
        if let clean = capture.cleanText, !clean.isEmpty { return clean }
        return capture.caption ?? capture.rawText ?? "Media capture"
    }

    private let destinationRepo = CaptureDestinationRepository.shared
    private let capturedRepo = CapturedItemRepository.shared
    private let mediaRepo = MediaAttachmentRepository.shared
    @ObservationIgnored private let refreshCoordinator = CoalescingRefresh()
    @ObservationIgnored private var itemsGeneration = 0

    var selectedDestination: CaptureDestination? {
        destinations.first { $0.uuid == selectedDestinationId }
    }

    func refresh() async {
        await refreshCoordinator.run { [weak self] in await self?.refreshSnapshot() }
    }

    private func refreshSnapshot() async {
        destinations = (try? await destinationRepo.fetchActive()) ?? destinationRepo.destinations
        async let review: Void = loadNeedsReview()
        async let items: Void = loadItems()
        _ = await (review, items)
    }

    func loadNeedsReview() async {
        let unrouted = (try? await capturedRepo.fetch(destinationId: nil, limit: 50)) ?? []
        needsReviewItems = unrouted.filter {
            $0.status == .captured || $0.status == .needsReview || $0.status == .failed
        }
    }

    /// Put a stranded capture into the triage queue, then mark the row routed.
    func reingestNeedsReview(_ item: CapturedItem) async {
        let raw = item.cleanText?.isEmpty == false
            ? item.cleanText!
            : (item.caption ?? "Telegram media capture")
        let outcome = await InboxIngestService.shared.ingest(
            .init(source: .telegramText, rawText: raw)
        )
        switch outcome {
        case .enqueued, .consumed:
            await markNeedsReviewResolved(item, status: .routed, intent: "needs_review_reingest")
        case .failed(let detail):
            // Keep the row visible — the only durable copy must not disappear.
            print("CaptureLanesViewModel.reingestNeedsReview ingest failed: \(detail)")
            PersistenceHealth.note(.writeFailure, context: "CaptureLanesVM.reingestNeedsReview", detail: "\(item.uuid): \(detail)")
        }
    }

    func dismissNeedsReview(_ item: CapturedItem) async {
        await markNeedsReviewResolved(item, status: .archived, intent: "needs_review_dismissed")
    }

    private func markNeedsReviewResolved(_ item: CapturedItem, status: CapturedItemStatus, intent: String) async {
        do {
            try await capturedRepo.updateRouting(
                uuid: item.uuid,
                destinationId: nil,
                parsedCommand: item.parsedCommand,
                parsedIntent: intent,
                confidence: item.routingConfidence,
                status: status
            )
        } catch {
            print("CaptureLanesViewModel.markNeedsReviewResolved failed: \(error)")
            PersistenceHealth.note(.writeFailure, context: "CaptureLanesVM.markNeedsReviewResolved", detail: "\(item.uuid): \(error.localizedDescription)")
        }
        await loadNeedsReview()
    }

    /// The user corrected a lane capture's text in the ledger. A tracked write
    /// that syncs to the phone; reload so the row shows the correction.
    func editCapture(_ item: CapturedItem, to newText: String) async {
        do {
            try await capturedRepo.editText(uuid: item.uuid, to: newText)
            await loadItems()
        } catch {
            print("CaptureLanesViewModel.editCapture failed: \(error)")
            PersistenceHealth.note(.writeFailure, context: "CaptureLanesVM.editCapture", detail: "\(item.uuid): \(error.localizedDescription)")
        }
    }

    func select(_ destination: CaptureDestination?) {
        guard selectedDestinationId != destination?.uuid else { return }
        clearSelection()
        selectedDestinationId = destination?.uuid
        Task { await loadItems() }
    }

    func clearSelection() {
        itemsGeneration += 1
        selectedDestinationId = nil
        selectedItems = []
        attachmentsByItemId = [:]
        focusedCaptureId = nil
        isInspectorOpen = false
    }

    func createLane() async {
        let name = newLaneName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !isCreatingLane else { return }
        isCreatingLane = true
        defer { isCreatingLane = false }
        do {
            let lane = try await destinationRepo.createLane(named: name)
            newLaneName = ""
            destinations = try await destinationRepo.fetchActive()
            selectedDestinationId = lane.uuid
            await loadItems()
        } catch {
            print("CaptureLanesViewModel.createLane failed: \(error)")
            PersistenceHealth.note(.writeFailure, context: "CaptureLanesVM.createLane", detail: error.localizedDescription)
        }
    }

    func deleteLane(_ destination: CaptureDestination) async {
        do {
            try await destinationRepo.archive(uuid: destination.uuid)
            let activeDestinations = try await destinationRepo.fetchActive()
            withAnimation(ProMotionSprings.gentle) {
                destinations = activeDestinations
                if selectedDestinationId == destination.uuid {
                    selectedDestinationId = nil
                    selectedItems = []
                    attachmentsByItemId = [:]
                }
            }
            await loadItems()
        } catch {
            print("CaptureLanesViewModel.deleteLane failed: \(error)")
            PersistenceHealth.note(.writeFailure, context: "CaptureLanesVM.deleteLane", detail: error.localizedDescription)
        }
    }

    private func loadItems() async {
        itemsGeneration += 1
        let generation = itemsGeneration
        guard let destinationID = selectedDestinationId else { return }
        let items = (try? await capturedRepo.fetch(destinationId: destinationID)) ?? []
        let attachments = (try? await mediaRepo.fetch(capturedItemIds: items.map(\.uuid))) ?? []
        guard generation == itemsGeneration, selectedDestinationId == destinationID else { return }
        selectedItems = items
        attachmentsByItemId = Dictionary(grouping: attachments, by: \.capturedItemId)
        // The focused row left the lane (archived, or a reload landed) —
        // an inspector must never linger over a capture that isn't there.
        if let focusedCaptureId, !selectedItems.contains(where: { $0.uuid == focusedCaptureId }) {
            self.focusedCaptureId = nil
            isInspectorOpen = false
        }
    }
}

// MARK: - Inspector host (lane dialect)

extension CaptureLanesViewModel: InboxInspectorHost {
    private func capture(matching item: InboxItem) -> CapturedItem? {
        selectedItems.first { $0.uuid == item.uuid }
    }

    func closeInspector() {
        isInspectorOpen = false
    }

    func editCaptureText(_ item: InboxItem, to newText: String) async {
        guard let capture = capture(matching: item) else { return }
        await editCapture(capture, to: newText)
    }

    /// Dismiss in a lane archives the capture — the row leaves the ledger,
    /// the durable record survives, and the toast's Undo puts it back.
    func dismiss(item: InboxItem) async {
        guard let capture = capture(matching: item) else { return }
        do {
            try await setStatus(of: capture, to: .archived, intent: "lane_inspector_dismiss")
            isInspectorOpen = false
            focusedCaptureId = nil
            await refresh()
            registerArchiveUndo(for: capture)
            triageModel?.presentLaneToast("Archived \(String(displayText(for: capture).prefix(40)))")
        } catch {
            print("CaptureLanesViewModel.dismiss failed: \(error)")
            PersistenceHealth.note(.writeFailure, context: "CaptureLanesVM.dismiss", detail: "\(capture.uuid): \(error.localizedDescription)")
            triageModel?.presentLaneToast("Couldn't archive that capture.", isError: true)
        }
    }

    /// A status flip that keeps every other routing field as the capture has it.
    private func setStatus(of capture: CapturedItem, to status: CapturedItemStatus, intent: String?) async throws {
        try await capturedRepo.updateRouting(
            uuid: capture.uuid,
            destinationId: capture.captureDestinationId,
            parsedCommand: capture.parsedCommand,
            parsedIntent: intent,
            confidence: capture.routingConfidence,
            status: status,
            createdObjectIds: capture.createdObjectIds,
            parentDeepDiveId: capture.parentDeepDiveId,
            parentInquirySessionId: capture.parentInquirySessionId,
            parentQuestionId: capture.parentQuestionId,
            parentProjectId: capture.parentProjectId
        )
    }

    private func registerArchiveUndo(for original: CapturedItem) {
        CosmoUndoManager.shared.register(
            InlineUndoAction(actionDescription: "Archive Lane Capture") { [weak self] in
                try? await self?.setStatus(of: original, to: original.status, intent: original.parsedIntent)
                NotificationCenter.default.post(name: CosmoNotification.Inbox.captureLaneChanged, object: nil)
            } redo: { [weak self] in
                try? await self?.setStatus(of: original, to: .archived, intent: "lane_inspector_dismiss")
                NotificationCenter.default.post(name: CosmoNotification.Inbox.captureLaneChanged, object: nil)
            }
        )
    }

    func place(_ item: InboxItem, adjustedPosition: CGPoint?) async {
        await triageModel?.place(item, adjustedPosition: adjustedPosition)
    }

    func placeAndGo(_ item: InboxItem) async {
        await triageModel?.placeAndGo(item)
    }

    func applyAlternate(_ item: InboxItem, recommendation: InboxRecommendation) async {
        await triageModel?.applyAlternate(item, recommendation: recommendation)
    }

    func makeTask(_ item: InboxItem) async {
        await triageModel?.makeTask(item)
    }

    var inquirySpaces: [InquirySpaceOption] {
        triageModel?.inquirySpaces ?? []
    }

    /// A lane capture becomes an inquiry the same way a queue capture does —
    /// the executor settles the ledger row (applied, session in its created
    /// objects) instead of the queue.
    func startInquiry(_ item: InboxItem, in choice: InquirySpaceChoice) async {
        await triageModel?.startInquiry(item, in: choice)
        await refresh()
    }

    /// Every lane but the one this capture is already in.
    var lanes: [CaptureDestination] {
        destinations.filter { $0.uuid != selectedDestinationId }
    }

    /// Lane → lane: the ledger row's routing changes, nothing is created.
    /// Undo puts it back in the lane it came from.
    func moveToLane(_ item: InboxItem, lane: CaptureDestination) async {
        guard let capture = capture(matching: item) else { return }
        do {
            try await capturedRepo.updateRouting(
                uuid: capture.uuid,
                destinationId: lane.uuid,
                parsedCommand: capture.parsedCommand,
                parsedIntent: "lane_move",
                confidence: capture.routingConfidence,
                status: capture.status,
                createdObjectIds: capture.createdObjectIds,
                parentDeepDiveId: capture.parentDeepDiveId,
                parentInquirySessionId: capture.parentInquirySessionId,
                parentQuestionId: capture.parentQuestionId,
                parentProjectId: capture.parentProjectId
            )
            await CaptureDestinationRepository.shared.markUsed(uuid: lane.uuid)
            isInspectorOpen = false
            focusedCaptureId = nil
            NotificationCenter.default.post(name: CosmoNotification.Inbox.captureLaneChanged, object: nil)
            await refresh()
            let original = capture
            CosmoUndoManager.shared.register(
                InlineUndoAction(actionDescription: "Move Capture to Lane") { [weak self] in
                    try? await self?.setStatus(of: original, to: original.status, intent: original.parsedIntent)
                    NotificationCenter.default.post(name: CosmoNotification.Inbox.captureLaneChanged, object: nil)
                } redo: { [weak self] in
                    guard let self else { return }
                    try? await self.capturedRepo.updateRouting(
                        uuid: original.uuid,
                        destinationId: lane.uuid,
                        parsedCommand: original.parsedCommand,
                        parsedIntent: "lane_move",
                        confidence: original.routingConfidence,
                        status: original.status,
                        createdObjectIds: original.createdObjectIds,
                        parentDeepDiveId: original.parentDeepDiveId,
                        parentInquirySessionId: original.parentInquirySessionId,
                        parentQuestionId: original.parentQuestionId,
                        parentProjectId: original.parentProjectId
                    )
                    NotificationCenter.default.post(name: CosmoNotification.Inbox.captureLaneChanged, object: nil)
                }
            )
            triageModel?.presentLaneToast("Moved to \(lane.name)")
        } catch {
            print("CaptureLanesViewModel.moveToLane failed: \(error)")
            PersistenceHealth.note(.writeFailure, context: "CaptureLanesVM.moveToLane", detail: "\(capture.uuid): \(error.localizedDescription)")
            triageModel?.presentLaneToast("Couldn't move that capture.", isError: true)
        }
    }

    func fileAsIdea(_ item: InboxItem) async {
        await triageModel?.fileAsIdea(item)
    }

    func fileAsSwipe(_ item: InboxItem) async {
        await triageModel?.fileAsSwipe(item)
    }

    /// Delegated like every other atom-creating verb, so toasts, undo and the
    /// override sheet stay one pipeline (see `InboxInspectorHost`).
    var hasFlows: Bool { triageModel?.hasFlows ?? false }

    func addCaptureToFlow(_ item: InboxItem) async {
        await triageModel?.addCaptureToFlow(item)
    }

    func growSeedling(_ item: InboxItem) async {
        await triageModel?.growSeedling(item)
    }

    func connectCapture(_ item: InboxItem) async {
        await triageModel?.connectCapture(item)
    }

    func showOverride(for item: InboxItem) {
        triageModel?.showOverride(for: item)
    }
}

struct CaptureLanesView: View {
    @State private var viewModel = CaptureLanesViewModel()
    let showsLaneSidebar: Bool
    let selectedDestinationId: String?
    let showsCommandRegistryOnly: Bool
    /// The queue's model, lent by InboxView — the lane inspector's verbs,
    /// toasts, and override sheet run through it.
    let triageModel: InboxViewModel?

    init(
        showsLaneSidebar: Bool = true,
        selectedDestinationId: String? = nil,
        showsCommandRegistryOnly: Bool = false,
        triageModel: InboxViewModel? = nil
    ) {
        self.showsLaneSidebar = showsLaneSidebar
        self.selectedDestinationId = selectedDestinationId
        self.showsCommandRegistryOnly = showsCommandRegistryOnly
        self.triageModel = triageModel
    }

    var body: some View {
        Group {
            if showsCommandRegistryOnly {
                commandRegistryDetail
            } else if viewModel.selectedDestination != nil {
                laneDetail
            } else {
                destinationsGrid
            }
        }
        .background(DS.bg)
        .task(id: selectedDestinationId) {
            viewModel.triageModel = triageModel
            if let selectedDestinationId {
                viewModel.selectedDestinationId = selectedDestinationId
            }
            await viewModel.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Inbox.itemAdded)) { notification in
            let changedDestinationId = notification.userInfo?["captureDestinationId"] as? String
            guard changedDestinationId == nil || changedDestinationId == viewModel.selectedDestinationId else { return }
            Task { await viewModel.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Inbox.captureLaneChanged)) { _ in
            Task { await viewModel.refresh() }
        }
        .animation(ProMotionSprings.gentle, value: viewModel.selectedDestinationId)
        .animation(ProMotionSprings.gentle, value: viewModel.destinations.map(\.uuid))
    }

    // MARK: - Destinations grid (Finder grammar)

    private var destinationsGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space24) {
                newLaneComposer

                if !viewModel.needsReviewItems.isEmpty {
                    needsReviewSection
                }

                // The one ledger-header voice — the page's sections (Lanes,
                // Needs review, Telegram commands) speak identically.
                VStack(alignment: .leading, spacing: DS.space12) {
                    CosmoSectionHeader(label: "Lanes", detail: "\(viewModel.destinations.count)")

                    LazyVGrid(columns: laneColumns, alignment: .leading, spacing: 14) {
                        ForEach(viewModel.destinations) { destination in
                            CaptureLaneTile(
                                destination: destination,
                                onOpen: { viewModel.select(destination) },
                                onDelete: { Task { await viewModel.deleteLane(destination) } }
                            )
                        }
                    }
                }

                if !viewModel.destinations.isEmpty {
                    commandRegistrySection
                }

                if viewModel.destinations.isEmpty {
                    gridEmptyState
                }
            }
            .padding(.horizontal, DS.space32)
            .padding(.top, DS.space16)
            .padding(.bottom, DS.space48)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    private var laneColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 148, maximum: 178), spacing: 14, alignment: .top)]
    }

    private var newLaneComposer: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: "folder.badge.plus")
                .font(DS.callout)
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)

            TextField("New lane name…", text: $viewModel.newLaneName)
                .textFieldStyle(.plain)
                .font(DS.body)
                .foregroundStyle(DS.text)
                .onSubmit {
                    Task { await viewModel.createLane() }
                }

            if !viewModel.newLaneName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    Task { await viewModel.createLane() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(DS.title3)
                        .foregroundStyle(DS.accent)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isCreatingLane)
                .help("Create lane (⏎)")
                .accessibilityLabel("Create capture lane")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space8)
        .dsGlassInput(cornerRadius: 14)
        .frame(maxWidth: 420)
        .animation(ProMotionSprings.snappy, value: viewModel.newLaneName.isEmpty)
    }

    // MARK: - Needs review (stranded captures)

    /// Captures that never reached a lane or the inbox — routing crashed or the
    /// write failed. One row each: the raw text, a button to send it into the
    /// triage queue, and a dismiss.
    private var needsReviewSection: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            CosmoSectionHeader(label: "Needs review", detail: "\(viewModel.needsReviewItems.count)")

            VStack(alignment: .leading, spacing: DS.space6) {
                ForEach(viewModel.needsReviewItems) { item in
                    NeedsReviewRow(
                        item: item,
                        onReingest: { Task { await viewModel.reingestNeedsReview(item) } },
                        onDismiss: { Task { await viewModel.dismissNeedsReview(item) } }
                    )
                }
            }
            .padding(DS.space12)
            .background(DS.glassSectionFill, in: .rect(cornerRadius: 14))
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    private var commandRegistrySection: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            CosmoSectionHeader(label: "Telegram commands", detail: "\(viewModel.destinations.count)")

            VStack(alignment: .leading, spacing: DS.space6) {
                ForEach(viewModel.destinations) { destination in
                    HStack(spacing: DS.space8) {
                        // The alias as the chip it is everywhere else —
                        // the raw monospace list read like debug output.
                        Text("\(destination.aliases.first ?? destination.name.lowercased()):")
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                            .foregroundStyle(DS.accent)
                            .padding(.horizontal, DS.space6)
                            .padding(.vertical, 2)
                            .background(DS.accentSoft, in: .rect(cornerRadius: 6))
                        Text(destination.name)
                            .font(DS.caption)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(DS.space12)
            .background(DS.glassSectionFill, in: .rect(cornerRadius: 14))
        }
        .frame(maxWidth: 420, alignment: .leading)
    }

    private var gridEmptyState: some View {
        VStack(spacing: DS.space8) {
            Image(systemName: "tray.and.arrow.down")
                .font(DS.displaySerif)
                .foregroundStyle(DS.textMuted.opacity(0.5))
                .accessibilityHidden(true)
            Text("Lanes give captures a precise home")
                .font(DS.title2)
                .foregroundStyle(DS.text)
            Text("Create a lane above, then send “lane-name: your thought” from Telegram — it skips triage and files itself.")
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DS.space48)
    }

    // MARK: - Command registry detail (manage-commands route)

    private var commandRegistryDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space10) {
                ForEach(viewModel.destinations) { destination in
                    CaptureCommandRegistryRow(
                        destination: destination,
                        onOpen: { viewModel.select(destination) },
                        onDelete: { Task { await viewModel.deleteLane(destination) } }
                    )
                }
            }
            .padding(DS.space24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Lane detail (same queue grammar as the global inbox)

    private var laneDetail: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                detailHeader
                if viewModel.selectedItems.isEmpty {
                    emptyState
                } else {
                    captureLedger
                }
            }
            laneInspectorOverlay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(ProMotionSprings.gentle, value: viewModel.isInspectorOpen)
    }

    /// The queue's floating glass inspector, hosted by the lane model —
    /// same panel, same verbs, opened by clicking a capture row.
    @ViewBuilder
    private var laneInspectorOverlay: some View {
        if viewModel.isInspectorOpen, let capture = viewModel.focusedCapture {
            InboxInspector(
                item: viewModel.inspectorItem(for: capture),
                viewModel: viewModel,
                laneName: viewModel.selectedDestination.map {
                    CollectionEmoji.resolve(name: $0.name, matchKeywords: false).label
                }
            )
            .padding(.trailing, DS.space16)
            .padding(.top, 72)
            .padding(.bottom, DS.space16)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var detailHeader: some View {
        if let destination = viewModel.selectedDestination {
            let identity = CollectionEmoji.resolve(name: destination.name, matchKeywords: false)
            HStack(spacing: DS.space12) {
                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        // Esc peels back one layer: inspector first, then the lane.
                        if viewModel.isInspectorOpen {
                            viewModel.closeInspector()
                        } else {
                            viewModel.clearSelection()
                        }
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(DS.subheadline.weight(.semibold))
                        .foregroundStyle(DS.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(DS.glassSectionFill, in: .circle)
                }
                .buttonStyle(.plain)
                .help("All lanes (esc)")
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityLabel("Back to all lanes")

                Group {
                    if let emoji = identity.emoji {
                        Text(emoji)
                            .font(DS.headline)
                    } else {
                        Image(systemName: destination.icon)
                            .font(DS.headline)
                            .foregroundStyle(DS.accent)
                    }
                }
                .frame(width: 34, height: 34)
                .background(DS.accentSoft, in: .rect(cornerRadius: 10))
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(identity.label)
                        .font(DS.title2)
                        .foregroundStyle(DS.text)
                    Text("\(destination.type.displayName) lane · \(destination.itemCount) captures")
                        .font(DS.caption)
                        .foregroundStyle(DS.textMuted)
                }

                Spacer()

                Text((destination.aliases.first ?? destination.name.lowercased()) + ":")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(DS.accent)
                    .padding(.horizontal, DS.space10)
                    .padding(.vertical, DS.space6)
                    .background(DS.accentSoft, in: .capsule)
                    .help("Prefix a Telegram message with this to file straight into the lane")
            }
            .padding(.horizontal, DS.space32)
            .padding(.vertical, DS.space12)

            Rectangle()
                .fill(DS.borderSubtle)
                .frame(height: 0.5)
                .padding(.horizontal, DS.space32)
        }
    }

    /// The same temporal ledger as the global inbox queue — pinned small-caps
    /// section headers, ~56pt rows — scoped to this lane's captures.
    private var captureLedger: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(temporalSections, id: \.id) { section in
                    Section {
                        ForEach(section.items) { item in
                            CaptureLaneQueueRow(
                                item: item,
                                attachments: viewModel.attachmentsByItemId[item.uuid] ?? [],
                                isFocused: viewModel.focusedCaptureId == item.uuid && viewModel.isInspectorOpen,
                                onOpen: { viewModel.focusCapture(item) },
                                onSave: { text in Task { await viewModel.editCapture(item, to: text) } }
                            )
                        }
                    } header: {
                        InboxSectionHeader(title: section.title, itemCount: section.items.count)
                    }
                }
            }
            .padding(.horizontal, DS.space24)
            .padding(.bottom, DS.space24)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    private var temporalSections: [(id: String, title: String, items: [CapturedItem])] {
        let calendar = Calendar.current
        let now = Date()

        var today: [CapturedItem] = []
        var yesterday: [CapturedItem] = []
        var thisWeek: [CapturedItem] = []
        var older: [CapturedItem] = []

        for item in viewModel.selectedItems {
            guard let date = ISO8601.date(from: item.createdAt) else {
                older.append(item)
                continue
            }
            if calendar.isDateInToday(date) { today.append(item) }
            else if calendar.isDateInYesterday(date) { yesterday.append(item) }
            else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) { thisWeek.append(item) }
            else { older.append(item) }
        }

        return [
            today.isEmpty ? nil : (id: "today", title: "Today", items: today),
            yesterday.isEmpty ? nil : (id: "yesterday", title: "Yesterday", items: yesterday),
            thisWeek.isEmpty ? nil : (id: "thisWeek", title: "This Week", items: thisWeek),
            older.isEmpty ? nil : (id: "older", title: "Older", items: older),
        ].compactMap { $0 }
    }

    private var emptyState: some View {
        VStack(spacing: DS.space12) {
            Image(systemName: "tray.and.arrow.down")
                .font(DS.displaySerif)
                .foregroundStyle(DS.textMuted.opacity(0.5))
                .accessibilityHidden(true)
            Text("This lane is waiting")
                .font(DS.headline)
                .foregroundStyle(DS.text)
            Text(emptyStateSubtitle)
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateSubtitle: String {
        guard let destination = viewModel.selectedDestination else {
            return "Custom lanes give Telegram messages a precise destination."
        }
        let alias = destination.aliases.first ?? CaptureDestination.normalizeAlias(destination.name)
        return "Send “\(alias): …” from Telegram, or attach media with that caption."
    }
}

// MARK: - Lane tile (Finder grammar)

private struct CaptureLaneTile: View {
    let destination: CaptureDestination
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var showDeleteConfirm = false

    /// Lane identity, the App Store register: an emoji the user typed into
    /// the lane name wins (and cleans the label); otherwise the lane's own
    /// explicitly chosen icon — never a keyword guess over a user's choice.
    private var identity: (emoji: String?, label: String) {
        CollectionEmoji.resolve(name: destination.name, matchKeywords: false)
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: DS.space10) {
                Group {
                    if let emoji = identity.emoji {
                        Text(emoji)
                            .font(DS.title2)
                    } else {
                        Image(systemName: destination.icon)
                            .font(DS.title2)
                            .foregroundStyle(DS.accent)
                    }
                }
                // An elevated well — the old accentSoft wash vanished against
                // the card fill and the tiles read disabled.
                .frame(width: 40, height: 40)
                .background(DS.surfaceElevated, in: .rect(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(DS.borderSubtle, lineWidth: 0.5)
                )
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(identity.label)
                        .font(DS.headline)
                        .foregroundStyle(DS.text)
                        .lineLimit(1)

                    Text(countLine)
                        .font(DS.caption)
                        .foregroundStyle(DS.textMuted)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }

                Text("\(destination.aliases.first ?? destination.name.lowercased()):")
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(DS.textSecondary)
                    .padding(.horizontal, DS.space6)
                    .padding(.vertical, 2)
                    .background(DS.glassSectionFill, in: .capsule)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.space12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCard(isHovered: isHovered, cornerRadius: 14)
        .scaleEffect(isHovered ? 1.01 : 1)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .help("Open \(destination.name)")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            Button(action: onOpen) {
                Label("Open", systemImage: "arrow.right.circle")
            }
            Divider()
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .confirmationDialog(
            "Delete \(destination.name)?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The lane and its Telegram command aliases will be hidden. Existing captures stay in the database.")
        }
    }

    private var countLine: String {
        // Zero is a state, not a statistic — "0 captures" reads as noise.
        if destination.itemCount == 0 { return "Empty" }
        return destination.itemCount == 1 ? "1 capture" : "\(destination.itemCount) captures"
    }
}

// MARK: - Command registry row (manage-commands route)

private struct CaptureCommandRegistryRow: View {
    let destination: CaptureDestination
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    /// Same identity register as the lane tiles: a typed emoji wins the
    /// mark slot and cleans the label; never a keyword guess.
    private var identity: (emoji: String?, label: String) {
        CollectionEmoji.resolve(name: destination.name, matchKeywords: false)
    }

    var body: some View {
        HStack(spacing: DS.space12) {
            Group {
                if let emoji = identity.emoji {
                    Text(emoji)
                        .font(DS.callout.weight(.semibold))
                } else {
                    Image(systemName: destination.icon)
                        .font(DS.callout.weight(.semibold))
                        .foregroundStyle(DS.accent)
                }
            }
            .frame(width: 28, height: 28)
            .background(DS.accentSoft, in: .rect(cornerRadius: 7))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DS.space4) {
                Text(identity.label)
                    .font(DS.headline)
                    .foregroundStyle(DS.text)
                    .lineLimit(1)

                HStack(spacing: DS.space6) {
                    ForEach(destination.aliases.prefix(4), id: \.self) { alias in
                        Text("\(alias):")
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                            .foregroundStyle(DS.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(DS.accentSoft, in: .rect(cornerRadius: 6))
                    }
                }
            }

            Spacer()

            Text(destination.type.displayName)
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        }
        .padding(DS.space12)
        .dsGlassCard(cornerRadius: 12)
        .contextMenu {
            Button(action: onOpen) {
                Label("Open Lane", systemImage: "arrow.right.circle")
            }
            Divider()
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete Command", systemImage: "trash")
            }
        }
        .confirmationDialog(
            "Delete \(destination.name)?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the lane from the sidebar and command registry.")
        }
    }
}

// MARK: - Needs review row

/// One stranded capture: raw text, status, re-ingest into the triage queue, dismiss.
private struct NeedsReviewRow: View {
    let item: CapturedItem
    let onReingest: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: DS.space8) {
            Circle()
                .fill(item.status == .failed ? DS.red : DS.accent)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(rawText)
                    .font(DS.callout)
                    .foregroundStyle(DS.text)
                    .lineLimit(2)
                Text(metaLine)
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            }

            Spacer(minLength: DS.space8)

            Button("To Inbox", action: onReingest)
                .font(DS.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(DS.accent)
                .help("Send this capture into the triage queue")
                .accessibilityLabel("Re-ingest capture into inbox")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(DS.caption2.weight(.medium))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Dismiss without re-ingesting")
            .accessibilityLabel("Dismiss stranded capture")
        }
        .padding(.vertical, DS.space4)
    }

    private var rawText: String {
        item.cleanText?.isEmpty == false ? item.cleanText! : (item.caption ?? "Media capture")
    }

    private var metaLine: String {
        var parts = ["Telegram", statusLabel]
        if let date = ISO8601.date(from: item.createdAt) {
            parts.append(date.cosmoCompactAge)
        }
        return parts.joined(separator: " · ")
    }

    private var statusLabel: String {
        switch item.status {
        case .failed: return "Processing failed"
        case .needsReview: return "Routing incomplete"
        default: return "Unrouted"
        }
    }
}

// MARK: - Lane queue row (same grammar as InboxQueueRow)

/// One lane capture, one calm row — identical visual grammar to the global
/// inbox queue. Lane captures already have a home, so the trailing area shows
/// status/media instead of a suggestion pill. Click opens the inspector.
private struct CaptureLaneQueueRow: View {
    let item: CapturedItem
    let attachments: [MediaAttachment]
    let isFocused: Bool
    let onOpen: () -> Void
    let onSave: (String) -> Void

    @State private var isHovered = false
    @State private var isExpanded = false

    // MARK: - Inline edit
    @State private var isEditing = false
    @State private var draft = ""
    /// Optimistic echo of a saved edit — the row shows it instantly while the
    /// lane reload lands.
    @State private var editedText: String?
    @FocusState private var editorFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                // No expand-toggle wrapper while editing — a Button around the
                // TextEditor would swallow the clicks meant for the field.
                rowContent
            } else {
                Button(action: onOpen) {
                    rowContent
                }
                .buttonStyle(.plain)
            }
        }
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .onChange(of: item.uuid) {
            // Row recycled to a different capture — drop edit state.
            isEditing = false
            editorFocused = false
            editedText = nil
        }
        .onChange(of: item.cleanText) {
            // The saved edit (or a sync from the phone) landed on the row —
            // let the real value take over from the optimistic echo.
            if !isEditing { editedText = nil }
        }
        .accessibilityElement(children: isEditing ? .contain : .combine)
        .accessibilityAddTraits(isFocused ? [.isSelected] : [])
        .help(isEditing ? "" : "Open this capture in the inspector")
    }

    private var rowContent: some View {
        HStack(alignment: isExpanded ? .top : .center, spacing: DS.space12) {
            leadingPreview
            titleColumn
            Spacer(minLength: DS.space12)
            trailingArea
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, isExpanded ? DS.space12 : 0)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .background(rowBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DS.borderSubtle)
                .frame(height: 0.5)
                .padding(.leading, DS.space16 + 7 + DS.space12)
        }
    }

    // Real media preview when the capture carries attachments; the queue's
    // status dot otherwise.
    @ViewBuilder
    private var leadingPreview: some View {
        if let thumbnail = attachments.compactMap(\.thumbnailPath).first {
            // Async + downsampled: the old sync NSImage(contentsOfFile:)
            // decoded a full-res JPEG on the main thread on every row render.
            // While loading (or if the file is unreadable) the attachment
            // icon stands in — same look as the old decode-failure branch.
            LocalFileThumbnail(path: thumbnail, maxPixelSize: 120) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                attachmentIconWell
            }
            .frame(width: 40, height: 40)
            .clipShape(.rect(cornerRadius: 8))
            .accessibilityLabel("Capture attachment preview")
        } else if attachments.first != nil {
            attachmentIconWell
        } else {
            Circle()
                .fill(item.status == .failed ? DS.red : DS.accent)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var attachmentIconWell: some View {
        if let first = attachments.first {
            Image(systemName: icon(for: first.kind))
                .font(DS.callout)
                .foregroundStyle(DS.accent)
                .frame(width: 40, height: 40)
                .background(DS.accentSoft, in: .rect(cornerRadius: 8))
                .accessibilityHidden(true)
        }
    }

    private var titleColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            if isEditing {
                TextEditor(text: $draft)
                    .font(DS.body)
                    .foregroundStyle(DS.text)
                    .lineSpacing(2)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 48, maxHeight: 160)
                    .focused($editorFocused)
                    .tint(DS.accent)
                    .padding(DS.space6)
                    .background(DS.glassSectionFill, in: .rect(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(DS.focusRing, lineWidth: 1.5)
                    )
                    .accessibilityLabel("Capture text")
                editControls
            } else {
                Text(itemTitle)
                    .font(DS.body)
                    .foregroundStyle(DS.text)
                    .lineLimit(isExpanded ? nil : 1)
                    .fixedSize(horizontal: false, vertical: isExpanded)

                Text(metaLine)
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            }
        }
    }

    private var editControls: some View {
        HStack(spacing: DS.space12) {
            Spacer()
            Button("Cancel") { cancelEditing() }
                .font(DS.caption.weight(.medium))
                .foregroundStyle(DS.textSecondary)
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Discard changes (esc)")
            Button("Save") { saveEdit() }
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(canSave ? DS.accent : DS.textMuted)
                .buttonStyle(.plain)
                .disabled(!canSave)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Save (⌘↩)")
        }
        .padding(.top, DS.space6)
    }

    @ViewBuilder
    private var trailingArea: some View {
        HStack(spacing: DS.space8) {
            if isHovered && !isEditing {
                Button { beginEditing() } label: {
                    Image(systemName: "square.and.pencil")
                        .font(DS.caption.weight(.semibold))
                        .foregroundStyle(DS.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(DS.glassCardFill, in: .circle)
                }
                .buttonStyle(.plain)
                .help("Edit capture text")
                .accessibilityLabel("Edit capture text")
                .transition(.opacity)
            }
            if item.status == .failed {
                Text("Failed")
                    .font(DS.caption.weight(.medium))
                    .foregroundStyle(DS.red)
                    .padding(.horizontal, DS.space10)
                    .padding(.vertical, DS.space4 + 1)
                    .background(DS.redSoft, in: .capsule)
            } else if attachments.count > 1 {
                Text("\(attachments.count) attachments")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            }
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isFocused {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.accentSoft.opacity(0.45))
                .padding(.horizontal, DS.space6)
        } else if isHovered || isExpanded {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.glassSectionFill)
                .padding(.horizontal, DS.space6)
        }
    }

    private var itemTitle: String {
        if let editedText { return editedText }
        return item.cleanText?.isEmpty == false ? item.cleanText! : item.caption ?? "Media capture"
    }

    // MARK: - Edit

    /// The current text an edit starts from and is compared against.
    private var currentText: String {
        if let editedText { return editedText }
        return item.cleanText?.isEmpty == false ? item.cleanText! : (item.caption ?? "")
    }

    private var canSave: Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != currentText
    }

    private func beginEditing() {
        draft = currentText
        withAnimation(ProMotionSprings.snappy) {
            isExpanded = true
            isEditing = true
        }
        DispatchQueue.main.async { editorFocused = true }
    }

    private func cancelEditing() {
        editorFocused = false
        withAnimation(ProMotionSprings.snappy) { isEditing = false }
    }

    private func saveEdit() {
        guard canSave else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        editorFocused = false
        editedText = text
        withAnimation(ProMotionSprings.snappy) { isEditing = false }
        onSave(text)
    }

    private var metaLine: String {
        var parts = ["Telegram", relativeDate]
        if let first = attachments.first {
            parts.append(first.kind.displayName)
        }
        return parts.joined(separator: " · ")
    }

    private var relativeDate: String {
        // The one age voice — compact, never "ago".
        guard let date = ISO8601.date(from: item.createdAt) else { return item.createdAt }
        if Date().timeIntervalSince(date) < 60 { return "now" }
        return date.cosmoCompactAge
    }

    private func icon(for kind: MediaAttachmentKind) -> String {
        switch kind {
        case .image, .screenshot: return "photo"
        case .pageScan: return "doc.viewfinder"
        case .pdf: return "doc.richtext"
        case .audio: return "waveform"
        case .video: return "film"
        case .markdown, .textFile: return "doc.text"
        case .epub: return "book.closed"
        case .spreadsheet: return "tablecells"
        case .document, .unknown: return "doc"
        }
    }
}
