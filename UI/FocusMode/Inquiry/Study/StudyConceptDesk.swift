// CosmoOS/UI/FocusMode/Inquiry/Study/StudyConceptDesk.swift
// The Concept Desk: concept development as a POSTURE of the Study, not a
// separate destination. Developing a seedling pivots the room — the left
// column becomes the collaborator conversation (the same inline-assistant
// session the Connection pane would show), the center hosts the concept
// board with ghost-row staging, the right becomes the evidence rail of
// everything the dive gathered about this concept, and the thinking bar
// feeds the conversation. Esc restores gather posture. Same brain
// (CosmoInlineAssistantStore + /concept skill), new mouth.

import SwiftUI

// MARK: - Evidence model

/// One gathered capture offered to the page: cleaned text up front, the
/// verbatim capture and its extract UUID as provenance underneath.
struct StudyEvidenceItem: Identifiable, Equatable {
    let id: String
    var text: String
    var rawSnippet: String
    var sourceExtractUUID: String
    var section: ConnectionSectionType
    var sourceUUID: String?
    var sourceTitle: String?
}

// MARK: - Controller

@MainActor
@Observable
final class StudyConceptDeskController {
    let deepDive: Atom
    let conceptKey: String
    let conceptName: String
    let atom: Atom
    let connectionVM: ConnectionFocusModeViewModel
    let workspace = ConnectionWorkspaceModel()
    private(set) var pendingInsertsBySection: [ConnectionSectionType: [ConnectionPendingInsert]] = [:]
    /// Captures that stopped resolving anywhere on the board (it changed
    /// under them) — tracked so an abandoned page still settles them.
    private(set) var orphanedCaptures: [ConnectionOrphanedCapture] = []
    private(set) var evidence: [StudyEvidenceItem] = []
    private(set) var isPreparingEvidence = false
    /// True when this development created the page — an untouched page is
    /// discarded on close (born ripe or not at all); a pre-existing merge
    /// target is never deleted.
    private let createdFreshPage: Bool
    private var provider: ConnectionContextProvider?
    private var stagedItems: [StagedConceptItem]

    init(atom: Atom, deepDive: Atom, seedling: IncubatingConcept, createdFreshPage: Bool) {
        self.atom = atom
        self.deepDive = deepDive
        self.conceptKey = seedling.conceptKey
        self.conceptName = seedling.name
        self.createdFreshPage = createdFreshPage
        self.stagedItems = seedling.pendingItems
        self.connectionVM = ConnectionFocusModeViewModel(atom: atom)
    }

    var surfaceID: String { "connection:\(atom.uuid)" }

    // MARK: Lifecycle

    /// Mirrors ConnectionFocusModeView.handleAppear for a Study-hosted page:
    /// lock, hydrate from DB, register the editable surface, bind the
    /// assistant session to this room, and prepare the evidence rail.
    func begin(corpusExtracts: [Atom]) {
        AtomRepository.shared.acquireEditingLock(uuid: atom.uuid)
        connectionVM.loadState()
        workspace.viewMode = .board
        let provider = ConnectionContextProvider(
            atom: atom,
            viewModel: connectionVM,
            titleProvider: { [weak connectionVM] in
                connectionVM?.editableTitle ?? "Untitled Concept"
            }
        )
        self.provider = provider
        CosmoWindowViewModel.shared.updateContext(provider: provider)
        // Opening the Desk is an explicit room change — the conversation
        // column must show THIS page's thread, so bind deliberately (the
        // idle-gated bind in updateContext is for passive view appearances).
        CosmoInlineAssistantStore.shared.activateSession(surfaceID: surfaceID)
        syncStagedInserts(from: CosmoInlineAssistantStore.shared.proposals)
        Task {
            await connectionVM.refreshSectionsFromDatabase()
            await prepareEvidence(corpusExtracts: corpusExtracts)
        }
    }

    /// Save, unbind, and settle the page's fate: an untouched fresh page is
    /// discarded and its seedling reverts to incubating; a developed page is
    /// placed on the dive's canvas.
    func finish() async {
        AtomRepository.shared.releaseEditingLock(uuid: atom.uuid)
        connectionVM.flushTitleSave()
        connectionVM.saveToAtom()
        connectionVM.saveState()
        if let provider {
            CosmoEditableSurfaceRegistry.shared.unregister(provider)
        } else {
            CosmoEditableSurfaceRegistry.shared.unregister(surfaceID: surfaceID)
        }
        // Window context follows presence: leaving the Desk releases it.
        if let provider {
            CosmoWindowViewModel.shared.releaseContext(provider: provider)
            self.provider = nil
        }

        let hasContent = connectionVM.state.sections.contains { !$0.items.isEmpty }
        if !hasContent, createdFreshPage {
            // Staged proposals must not dangle after the page dies — the
            // placeable ghost rows AND the captures the board already
            // changed under (those render nowhere, so nothing else would
            // ever settle them).
            for insert in pendingInsertsBySection.values.flatMap({ $0 }) {
                await CosmoInlineAssistantStore.shared.reject(operationID: insert.operationID)
            }
            for orphan in orphanedCaptures {
                await CosmoInlineAssistantStore.shared.reject(operationID: orphan.operationID)
            }
            await ConceptSeedbedService.shared.abandonEmptyDevelopment(
                deepDiveUUID: deepDive.uuid,
                conceptKey: conceptKey
            )
            return
        }
        if let fresh = try? await AtomRepository.shared.fetch(uuid: atom.uuid) {
            await ConnectionPromotionService.shared.placeDevelopedConnection(fresh, deepDive: deepDive)
        }
    }

    // MARK: Conversation

    /// The thinking bar's develop posture: every submission runs the /concept
    /// skill against this page's surface. The first turn carries the slash
    /// command; skill stickiness keeps the rest in-session.
    func submitFromBar(_ text: String) async {
        let store = CosmoInlineAssistantStore.shared
        store.activateSession(surfaceID: surfaceID)
        let inConceptSkill = store.selectedSkillID == CosmoInlineAssistantSkillID.concept.rawValue
        store.composerText = inConceptSkill ? text : "/concept \(text)"
        await store.submit()
    }

    func syncStagedInserts(from proposals: [CosmoAssistantProposal]) {
        let staged = ConnectionSurfaceSerializer.stagedInserts(
            from: proposals,
            atomUUID: atom.uuid,
            title: connectionVM.editableTitle,
            conceptType: connectionVM.state.conceptType,
            sections: connectionVM.state.sections
        )
        pendingInsertsBySection = staged.bySection
        orphanedCaptures = staged.orphaned
    }

    var boardActions: ConnectionWorkspaceActions {
        ConnectionWorkspaceActions(
            onAcceptInsert: { [weak self] insert in
                guard let self, let provider = self.provider else { return }
                Task { await CosmoInlineAssistantStore.shared.accept(operationID: insert.operationID, provider: provider) }
            },
            onRejectInsert: { insert in
                Task { await CosmoInlineAssistantStore.shared.reject(operationID: insert.operationID) }
            }
        )
    }

    // MARK: Evidence rail

    /// Staged seedbed material plus key/alias-matched corpus extracts, cleaned
    /// at desk-open by the Concept Composer (raw shows until it returns; on
    /// any failure raw stays — never regresses).
    private func prepareEvidence(corpusExtracts: [Atom]) async {
        isPreparingEvidence = true
        defer { isPreparingEvidence = false }

        let sources = (try? await InquiryRepository.shared.fetchSources(forDeepDive: deepDive)) ?? []
        let sourceTitles = Dictionary(
            sources.compactMap { source in source.title.map { (source.uuid, $0) } },
            uniquingKeysWith: { first, _ in first }
        )

        var drafts: [ConnectionSectionType: [ConnectionSectionItemDraft]] = [:]
        var seenExtracts = Set<String>()
        func addDraft(body: String, extractUUID: String, sourceUUID: String?, section: ConnectionSectionType) {
            guard !seenExtracts.contains(extractUUID) else { return }
            seenExtracts.insert(extractUUID)
            drafts[section, default: []].append(ConnectionSectionItemDraft(
                body: body,
                sourceUUID: sourceUUID,
                originExtractUUID: extractUUID,
                kindLabel: section.displayName
            ))
        }
        for staged in stagedItems {
            let section = staged.proposedSection.flatMap(ConnectionSectionType.init(rawValue:)) ?? .claims
            addDraft(body: staged.rawSnippet, extractUUID: staged.sourceExtractUUID, sourceUUID: staged.sourceUUID, section: section)
        }
        // Corpus sweep: older or untagged captures that mention this concept.
        let matchKeys = Set([conceptKey])
        for extract in corpusExtracts {
            guard let metadata = extract.extractMetadata else { continue }
            let body = (extract.body ?? extract.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            let tagKeys = Set((metadata.conceptNames ?? []).map(ConceptResolver.conceptKey))
            let bodyMatches = conceptKey.count >= 4 && body.lowercased().contains(conceptKey)
            guard !tagKeys.isDisjoint(with: matchKeys) || bodyMatches else { continue }
            let section = ConnectionRoutingEngine.sectionType(for: metadata.kind) ?? .claims
            addDraft(body: body, extractUUID: extract.uuid, sourceUUID: metadata.sourceUUID, section: section)
        }

        func items(from sections: [ConnectionSectionType: [ConnectionSectionItemDraft]]) -> [StudyEvidenceItem] {
            // Section order keeps the rail stable across the composer swap.
            ConnectionSectionType.allCases.flatMap { section in
                (sections[section] ?? []).compactMap { draft in
                    guard let extractUUID = draft.originExtractUUID else { return nil }
                    return StudyEvidenceItem(
                        id: draft.id,
                        text: draft.body,
                        rawSnippet: draft.rawSnippet ?? draft.body,
                        sourceExtractUUID: extractUUID,
                        section: section,
                        sourceUUID: draft.sourceUUID,
                        sourceTitle: draft.sourceUUID.flatMap { sourceTitles[$0] }
                    )
                }
            }
        }

        // Anything already attached into a page stays out of the rail.
        let alreadyAttached = Set(connectionVM.state.sections.flatMap(\.items).compactMap(\.sourceAtomUUID))
        evidence = items(from: drafts).filter { !alreadyAttached.contains($0.sourceExtractUUID) }
        guard !evidence.isEmpty else { return }

        let candidate = CrystallizationOutput.ConnectionCandidate(
            name: conceptName,
            proposedSections: drafts
        )
        let organized = await ConceptComposerEngine.shared.organize([candidate])
        guard let composed = organized.first, !Task.isCancelled else { return }
        let cleaned = items(from: composed.proposedSections).filter { !alreadyAttached.contains($0.sourceExtractUUID) }
        if !cleaned.isEmpty { evidence = cleaned }
    }

    /// Attach = the ONLY way research material enters the page: cleaned bullet
    /// into its section, verbatim capture riding along as provenance.
    func attach(_ item: StudyEvidenceItem) async {
        connectionVM.attachItem(
            ConnectionItem(
                content: item.text,
                plainText: item.text,
                sourceAtomUUID: item.sourceExtractUUID,
                sourceSnippet: item.rawSnippet
            ),
            toSection: item.section
        )
        evidence.removeAll { $0.id == item.id }
        await consumeIfSettled(extractUUID: item.sourceExtractUUID)
    }

    func dismiss(_ item: StudyEvidenceItem) async {
        evidence.removeAll { $0.id == item.id }
        await consumeIfSettled(extractUUID: item.sourceExtractUUID)
    }

    /// Low-energy escape hatch: file everything left into its proposed section.
    func sweepRemaining() async {
        for item in evidence {
            await attach(item)
        }
    }

    /// A staged item is consumed once no rail row still offers it (a split
    /// capture yields several rows sharing one extract).
    private func consumeIfSettled(extractUUID: String) async {
        guard !evidence.contains(where: { $0.sourceExtractUUID == extractUUID }) else { return }
        let stamp = ISO8601.string(from: Date())
        await ConceptSeedbedService.shared.updateSeedling(
            deepDiveUUID: deepDive.uuid,
            conceptKey: conceptKey
        ) { seedling in
            for index in seedling.stagedItems.indices
            where seedling.stagedItems[index].sourceExtractUUID == extractUUID
                && seedling.stagedItems[index].consumedAt == nil {
                seedling.stagedItems[index].consumedAt = stamp
            }
        }
    }
}

// MARK: - Center column (the board, with a slim desk masthead)

@MainActor
struct StudyConceptDeskCenter: View {
    @Bindable var desk: StudyConceptDeskController
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            masthead
            Divider().overlay(DS.borderSubtle)
            ConnectionBoardView(
                viewModel: desk.connectionVM,
                workspace: desk.workspace,
                actions: desk.boardActions,
                pendingInsertsBySection: desk.pendingInsertsBySection
            )
        }
    }

    private var masthead: some View {
        HStack(spacing: DS.space10) {
            Image(systemName: "leaf")
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("DEVELOPING")
                    .dsSmallCapsLabel()
                Text(desk.connectionVM.editableTitle)
                    .font(.system(.body, design: .serif).weight(.semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: onDone) {
                Text("Done")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.accent)
                    .padding(.horizontal, DS.space10)
                    .padding(.vertical, 5)
                    .background(DS.accentSoft, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Finish developing (Esc)")
            .accessibilityLabel("Finish developing this concept")
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space10)
    }
}

// MARK: - Left column (the conversation)

/// The collaborator's thread — the exact transcript the Connection pane would
/// show for this page (same store, same session), restyled into the Study
/// panel grammar. Input comes from the thinking bar, so no composer here.
@MainActor
struct StudyConversationPanel: View {
    @ObservedObject var store: CosmoInlineAssistantStore
    var isOverlay: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if store.paneMessages.isEmpty {
                teachingState
            } else {
                CosmoInlineAssistantPaneMessages(store: store)
            }
        }
        .frame(width: StudyMetrics.panelWidth)
        .studyPanelSurface(edge: .leading, isOverlay: isOverlay)
    }

    private var header: some View {
        HStack(spacing: DS.space6) {
            Text("CONVERSATION")
                .dsSmallCapsLabel()
            Spacer()
            if store.isProcessing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
            }
        }
        .padding(.horizontal, DS.space16)
        .padding(.top, DS.space12)
        .padding(.bottom, DS.space10)
    }

    private var teachingState: some View {
        VStack {
            Text("Think out loud in the bar below. Cosmo captures what you say into the board and asks the next question.")
                .font(DS.callout)
                .foregroundStyle(DS.textMuted)
                .padding(.horizontal, DS.space16)
                .padding(.vertical, DS.space12)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
        }
    }
}

// MARK: - Right column (the evidence rail)

@MainActor
struct StudyEvidenceRail: View {
    @Bindable var desk: StudyConceptDeskController
    var isOverlay: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if desk.evidence.isEmpty {
                emptyState
            } else {
                feed
            }
        }
        .frame(width: StudyMetrics.panelWidth)
        .studyPanelSurface(edge: .trailing, isOverlay: isOverlay)
    }

    private var header: some View {
        HStack(spacing: DS.space6) {
            Text("EVIDENCE")
                .dsSmallCapsLabel()
            Spacer()
            if desk.isPreparingEvidence {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
            } else {
                Text("\(desk.evidence.count)")
                    .font(DS.caption)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(DS.textMuted)
            }
        }
        .padding(.horizontal, DS.space16)
        .padding(.top, DS.space12)
        .padding(.bottom, DS.space10)
    }

    private var feed: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(desk.evidence.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider()
                            .overlay(DS.glassBorder)
                            .padding(.leading, DS.space16)
                    }
                    StudyEvidenceRow(desk: desk, item: item)
                }
                sweepFooter
            }
            .padding(.bottom, StudyMetrics.panelBottomInset)
        }
        .scrollIndicators(.never)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .animation(ProMotionSprings.gentle, value: desk.evidence.map(\.id))
    }

    private var sweepFooter: some View {
        Button {
            Task { await desk.sweepRemaining() }
        } label: {
            Text("Sweep remaining into sections")
                .font(DS.caption.weight(.medium))
                .foregroundStyle(DS.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.space8)
                .background(DS.glassInputFill, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DS.space16)
        .padding(.top, DS.space12)
        .help("File everything left into its suggested section")
        .accessibilityLabel("Sweep remaining evidence into sections")
    }

    private var emptyState: some View {
        VStack {
            Text(desk.isPreparingEvidence
                 ? "Gathering what you captured about this concept…"
                 : "Everything gathered about this concept has been attached or dismissed.")
                .font(DS.callout)
                .foregroundStyle(DS.textMuted)
                .padding(.horizontal, DS.space16)
                .padding(.vertical, DS.space12)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
        }
    }
}

/// One offered capture: cleaned text, source chip, section hint, and the two
/// verbs — attach into the page, or dismiss.
@MainActor
private struct StudyEvidenceRow: View {
    let desk: StudyConceptDeskController
    let item: StudyEvidenceItem

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Text(item.text)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .fixedSize(horizontal: false, vertical: true)
            metaRow
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(isHovered ? DS.surfaceHover.opacity(0.6) : .clear)
        .onHover { isHovered = $0 }
        .help(item.rawSnippet == item.text ? "" : "Captured as: \(item.rawSnippet)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Evidence: \(item.text). Suggested section \(item.section.displayName)")
    }

    private var metaRow: some View {
        HStack(spacing: DS.space8) {
            Text(item.section.displayName)
                .font(DS.caption2.weight(.semibold))
                .foregroundStyle(DS.accent)
            if let sourceTitle = item.sourceTitle {
                Text(sourceTitle)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if isHovered {
                actionButtons
            }
        }
        .frame(minHeight: 20)
    }

    private var actionButtons: some View {
        HStack(spacing: DS.space6) {
            Button {
                Task { await desk.attach(item) }
            } label: {
                Text("Attach")
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(DS.accent)
                    .padding(.horizontal, DS.space8)
                    .padding(.vertical, 3)
                    .background(DS.accentSoft, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Add to \(item.section.displayName)")
            .accessibilityLabel("Attach to \(item.section.displayName)")

            Button {
                Task { await desk.dismiss(item) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .accessibilityLabel("Dismiss evidence")
        }
        .transition(.opacity)
    }
}
