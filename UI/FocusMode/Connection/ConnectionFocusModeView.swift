// CosmoOS/UI/FocusMode/Connection/ConnectionFocusModeView.swift
// Connection Focus Mode — structured 3-pane workspace host.
// June 2026 rewrite: the free-form canvas (floating blocks, radial menu,
// space-pan, collaborator dock) is replaced by ConnectionWorkspaceView
// (navigator | board/outline/manuscript | inspector). Concept development
// now happens through the inline assistant's /concept skill, which stages
// reviewed diffs against this connection's editable surface.

import SwiftUI
import Combine
import GRDB

// MARK: - Connection Focus Mode View

struct ConnectionFocusModeView: View {

    // MARK: - Properties

    /// The connection atom being displayed
    let atom: Atom

    /// Callback to close focus mode
    let onClose: () -> Void

    // MARK: - State

    @State private var viewModel: ConnectionFocusModeViewModel
    @State private var workspace = ConnectionWorkspaceModel()
    @State private var coDevEngine = ConnectionCoDevEngine()
    /// The view OWNS its context provider — the editable-surface registry holds
    /// it weakly; the old single global slot deallocated it on any other view's
    /// registration, unbinding this surface from the assistant.
    @State private var ownedContextProvider: ConnectionContextProvider?
    @State private var wellSources: [Atom] = []
    @State private var suggestedWellSources: [Atom] = []
    @State private var isLoadingSuggestedSources = false
    @State private var isShowingSuggestedSources = false
    /// The Material rail — library recommendations in the inspector.
    @State private var recommendations = ConceptRecommendationModel()
    /// Sibling pages of the same deep dive — powers inline mention links.
    @State private var linkTargets: ConnectionLinkTargets = .empty
    /// Pending inline-assistant proposal targeting this connection's sections.
    /// Kept for the Manuscript view's full-screen diff only — Board and Outline
    /// route pending inserts into their sections instead (see below).
    @State private var reviewProposal: CosmoAssistantProposal?
    /// Staged concept-collaborator inserts routed to the section they target, so
    /// Board cards and Outline rows show them as in-place ghost rows with ✓/✗
    /// rather than replacing the whole center column with a linear text diff.
    @State private var pendingInsertsBySection: [ConnectionSectionType: [ConnectionPendingInsert]] = [:]
    /// Persisted pending material (inbox feeds, seedling develops) — loaded
    /// from the atom's metadata; renders through the same ghost-row grammar.
    @State private var persistedInserts: [ConnectionStagedInsert] = []
    /// Gallery "+" armed the shared ⌘K picker: the next atom pick attaches
    /// as gallery media instead of a Sources-rail link.
    @State private var mediaPickerArmed = false

    @Environment(\.isPaneContext) private var isPaneContext
    @Environment(\.isPeekContext) private var isPeekContext
    @Environment(\.isPaneContextOwner) private var isPaneContextOwner
    @Environment(\.atomWindowChromeContext) private var atomChrome

    // MARK: - Initialization

    init(atom: Atom, onClose: @escaping () -> Void) {
        self.atom = atom
        self.onClose = onClose
        self._viewModel = State(initialValue: ConnectionFocusModeViewModel(atom: atom))
    }

    // MARK: - Body

    var body: some View {
        workspaceView
            .background(DS.bg.ignoresSafeArea())
            .cosmoSurfaceKeyWindowActivation(surfaceID: "connection:\(atom.uuid)")
            .focusImmersiveEntryTransition()
            .onAppear(perform: handleAppear)
            .onDisappear(perform: handleDisappear)
            // The termination flush belongs to the MOUNTED view, never to the
            // model (the Idea/Content/Notes idiom). `State(initialValue:)` is
            // not lazy, so this view's initializer builds a model on every
            // re-render and SwiftUI discards all but the first; when the model
            // subscribed in its own init, quitting made every discarded copy
            // flush its stale open-time state over the live one. Only one view
            // is mounted, so only one flush can fire. Stays synchronous — the
            // process is about to exit.
            .onReceive(NotificationCenter.default.publisher(for: .cosmoAppWillTerminate)) { _ in
                viewModel.saveToAtom()
            }
            .onChange(of: isPaneContextOwner) { _, isOwner in
                if isOwner { registerContextProvider() }
            }
            .onReceive(CosmoInlineAssistantStore.shared.$proposals) { proposals in
                syncReviewProposal(from: proposals)
            }
            // A concept was minted or linked from this page (or a sibling):
            // refresh link targets so the new page's mentions light up now.
            // Sections stay untouched — the origin's References row was added
            // through the live VM and may not be in the DB yet. When this page
            // is an endpoint of the new link, the Sources rail refreshes too —
            // the minted page slides in without leaving and re-entering.
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Connection.referencesChanged)) { notification in
                Task { await loadLinkTargets() }
                let originUUID = notification.userInfo?["originUUID"] as? String
                let connectionUUID = notification.userInfo?["connectionUUID"] as? String
                guard originUUID == atom.uuid || connectionUUID == atom.uuid else { return }
                let counterpart = originUUID == atom.uuid ? connectionUUID : originUUID
                Task { await refreshSources(ensuring: counterpart) }
            }
            // Material staged onto this page while it's open (an inbox feed,
            // a seedling develop) appears as ghost rows immediately.
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Connection.stagedInsertsChanged)) { notification in
                guard notification.userInfo?["connectionUUID"] as? String == atom.uuid else { return }
                Task { await loadPersistedInserts() }
            }
            // Media attached from outside this workspace (quick look, agent
            // tool, iOS): fold the fresh refs into live state by id-union so
            // the gallery updates AND a later in-session save keeps them.
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Connection.mediaChanged)) { notification in
                guard notification.userInfo?["connectionUUID"] as? String == atom.uuid else { return }
                Task { await mergeExternalMedia() }
            }
            // attach_media staged ghost tiles for this concept's gallery.
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Connection.mediaStagingChanged)) { notification in
                guard notification.userInfo?["connectionUUID"] as? String == atom.uuid,
                      let uuids = notification.userInfo?["atomUUIDs"] as? [String] else { return }
                Task { await loadStagedMediaSuggestions(uuids) }
            }
            // handle_objection staged a rebuttal — ghost thread with ✓/✗.
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Connection.objectionHandlingStaged)) { notification in
                receiveStagedObjectionHandling(notification)
            }
            // The Material rail follows the page: any section/title mutation
            // pokes a debounced re-query, so recommendations evolve with the
            // concept instead of freezing at open-time.
            .onChange(of: viewModel.state.lastModified) { _, _ in
                recommendations.poke()
            }
            .onChange(of: viewModel.editableTitle) { _, _ in
                recommendations.poke()
            }
            .onKeyPress(.escape) { handleEscape() }
            .onKeyPress { handleKeyCommand($0) }
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.NodeGraph.addItemToCurrentCanvas)) { notification in
                handleAtomPicked(notification)
            }
            .overlay { lightboxOverlay }
    }

    /// The Stage lightbox — mounted over the whole workspace while a media
    /// ref is presented. First stop in the Esc chain (after Compare).
    @ViewBuilder
    private var lightboxOverlay: some View {
        if workspace.isComparePresented {
            ConceptMediaCompareStrip(
                items: viewModel.state.orderedMedia.filter { workspace.compareSelection.contains($0.id) },
                atoms: viewModel.mediaAtoms,
                onOpen: { id in
                    withAnimation(ProMotionSprings.focusTransition) {
                        workspace.isComparePresented = false
                        workspace.presentedMediaID = id
                    }
                },
                onClose: {
                    withAnimation(ProMotionSprings.focusTransition) {
                        workspace.isComparePresented = false
                    }
                }
            )
        } else if let presentedID = workspace.presentedMediaID {
            ConceptMediaLightbox(
                media: viewModel.state.orderedMedia,
                atoms: viewModel.mediaAtoms,
                presentedID: presentedID,
                actions: workspaceActions,
                onCaptionCommit: { id, caption in
                    viewModel.setMediaCaption(id: id, caption: caption)
                },
                onPinMoment: { id, seconds in
                    viewModel.pinMediaMoment(id: id, seconds: seconds)
                },
                onCaptureQuote: { item, section, text in
                    viewModel.attachItem(
                        ConnectionItem(
                            content: text,
                            sourceAtomUUID: item.atomUUID,
                            sourceSnippet: text
                        ),
                        toSection: section
                    )
                },
                onPresent: { id in workspace.presentedMediaID = id },
                onClose: {
                    withAnimation(ProMotionSprings.focusTransition) {
                        workspace.presentedMediaID = nil
                    }
                }
            )
        }
    }

    private var workspaceView: some View {
        ConnectionWorkspaceView(
            atom: atom,
            viewModel: viewModel,
            workspace: workspace,
            title: titleBinding,
            sources: workspaceSources,
            recommendations: recommendations,
            reviewProposal: reviewProposal,
            reviewSourceText: reviewSourceText,
            pendingInsertsBySection: combinedInsertsBySection,
            isPaneContext: isPaneContext,
            actions: workspaceActions
        )
        .environment(\.connectionLinkTargets, linkTargets)
    }

    /// One ghost-row stream: persisted pending material first (it's been
    /// waiting longest), then live collaborator proposals.
    private var combinedInsertsBySection: [ConnectionSectionType: [ConnectionPendingInsert]] {
        var combined: [ConnectionSectionType: [ConnectionPendingInsert]] = [:]
        for entry in persistedInserts {
            // An unknown section rawValue (newer app version) stays staged
            // but unrendered — never guessed into the wrong section.
            guard let section = entry.sectionType else { continue }
            combined[section, default: []].append(ConnectionPendingInsert(
                proposalID: Self.stableUUID(for: entry.id),
                operationID: Self.stableUUID(for: entry.id),
                section: section,
                bullets: [ConceptMentionToken.displayText(entry.text)],
                stagedEntryId: entry.id
            ))
        }
        for (section, inserts) in pendingInsertsBySection {
            combined[section, default: []].append(contentsOf: inserts)
        }
        return combined
    }

    /// Staged entry ids are UUID strings — reuse them so ForEach identity is
    /// stable across reloads (a fresh UUID per render would churn the rows).
    private static func stableUUID(for entryId: String) -> UUID {
        UUID(uuidString: entryId) ?? UUID()
    }

    // MARK: - Workspace wiring

    private var titleBinding: Binding<String> {
        Binding(
            get: { viewModel.editableTitle },
            set: { viewModel.setTitle($0) }
        )
    }

    private var workspaceSources: ConnectionWorkspaceSources {
        ConnectionWorkspaceSources(
            linked: wellSources,
            suggested: suggestedWellSources,
            isLoadingSuggestions: isLoadingSuggestedSources,
            isShowingSuggestions: isShowingSuggestedSources,
            contributions: contributionsBySource
        )
    }

    private var contributionsBySource: [String: Set<ConnectionSectionType>] {
        var out: [String: Set<ConnectionSectionType>] = [:]
        for section in viewModel.state.sections {
            for item in section.items {
                if let uuid = item.sourceAtomUUID {
                    out[uuid, default: []].insert(section.type)
                }
            }
        }
        return out
    }

    private var workspaceActions: ConnectionWorkspaceActions {
        ConnectionWorkspaceActions(
            onSourceTap: { openSource($0) },
            onAddSource: { presentSharedCommandK() },
            onRequestSuggestions: { Task { await requestSuggestedSources() } },
            onLinkSuggestedSource: { source in Task { await linkSourceToConnection(source) } },
            onTitleCommit: { viewModel.flushTitleSave() },
            onClose: onClose,
            onAcceptInsert: { acceptInsert($0) },
            onRejectInsert: { rejectInsert($0) },
            onOpenMedia: { id in
                withAnimation(ProMotionSprings.focusTransition) {
                    workspace.presentedMediaID = id
                }
            },
            onOpenMediaAsPane: { atomUUID in openMediaSourceAsPane(atomUUID) },
            onDropMediaAtoms: { uuids, anchor in
                Task { await attachDroppedAtoms(uuids, anchor: anchor) }
            },
            onDropMediaFiles: { urls, anchor in
                Task { await attachDroppedFiles(urls, anchor: anchor) }
            },
            onPasteMediaURL: { urlString, anchor in
                Task { await captureAndAttachURL(urlString, anchor: anchor) }
            },
            onAddMediaTapped: {
                mediaPickerArmed = true
                presentSharedCommandK()
            },
            onDetachMedia: { id in
                if workspace.presentedMediaID == id {
                    workspace.presentedMediaID = nil
                }
                withAnimation(ProMotionSprings.gentle) {
                    viewModel.detachMedia(id: id)
                }
            },
            onToggleMediaCover: { id in viewModel.toggleMediaCover(id: id) },
            onAnchorMedia: { id, section in
                withAnimation(ProMotionSprings.gentle) {
                    viewModel.setMediaAnchor(id: id, section: section)
                }
            },
            onToggleCompareSelection: { id in
                withAnimation(ProMotionSprings.hover) {
                    workspace.toggleCompareSelection(id)
                }
            },
            onPresentCompare: {
                withAnimation(ProMotionSprings.focusTransition) {
                    workspace.isComparePresented = true
                }
            },
            onAcceptStagedHandling: { stagedID in
                guard let staged = workspace.stagedObjectionHandlings.first(where: { $0.id == stagedID }) else { return }
                withAnimation(ProMotionSprings.gentle) {
                    viewModel.setObjectionHandling(
                        itemID: staged.objectionItemID,
                        inSection: .beliefsObjections,
                        text: staged.text,
                        linkedRefs: staged.linkedRefs
                    )
                    workspace.stagedObjectionHandlings.removeAll { $0.id == stagedID }
                }
            },
            onRejectStagedHandling: { stagedID in
                withAnimation(ProMotionSprings.gentle) {
                    workspace.stagedObjectionHandlings.removeAll { $0.id == stagedID }
                }
            },
            onAcceptStagedMedia: { atomUUID in
                guard let staged = workspace.stagedMediaAtoms.first(where: { $0.uuid == atomUUID }) else { return }
                withAnimation(ProMotionSprings.gentle) {
                    viewModel.attachMediaAtom(staged)
                    workspace.stagedMediaAtoms.removeAll { $0.uuid == atomUUID }
                }
            },
            onRejectStagedMedia: { atomUUID in
                withAnimation(ProMotionSprings.gentle) {
                    workspace.stagedMediaAtoms.removeAll { $0.uuid == atomUUID }
                }
            }
        )
    }

    /// A handle_objection staging arrived for this concept: fold it into the
    /// workspace as a ghost thread. One staged rebuttal per objection — a
    /// newer proposal replaces the old ghost, never stacks.
    private func receiveStagedObjectionHandling(_ notification: Notification) {
        guard notification.userInfo?["connectionUUID"] as? String == atom.uuid,
              let itemIDRaw = notification.userInfo?["objectionItemID"] as? String,
              let itemID = UUID(uuidString: itemIDRaw),
              let text = notification.userInfo?["text"] as? String else { return }
        let snippet = notification.userInfo?["objectionSnippet"] as? String ?? ""
        let refPairs = notification.userInfo?["linkedRefs"] as? [[String]] ?? []
        let refs: [ConnectionBoardItemRef] = refPairs.compactMap { pair in
            guard pair.count == 2,
                  let section = ConnectionSectionType(rawValue: pair[0]),
                  let refItemID = UUID(uuidString: pair[1]) else { return nil }
            return ConnectionBoardItemRef(section: section, itemID: refItemID)
        }
        withAnimation(ProMotionSprings.gentle) {
            workspace.stagedObjectionHandlings.removeAll { $0.objectionItemID == itemID }
            workspace.stagedObjectionHandlings.append(StagedObjectionHandling(
                objectionItemID: itemID,
                objectionSnippet: snippet,
                text: text,
                linkedRefs: refs
            ))
        }
    }

    /// Resolve attach_media staged candidates to atoms, excluding anything
    /// already on the board.
    @MainActor
    private func loadStagedMediaSuggestions(_ uuids: [String]) async {
        let attached = Set(viewModel.state.media.compactMap(\.atomUUID))
        let known = Set(workspace.stagedMediaAtoms.map(\.uuid))
        for uuid in uuids where !attached.contains(uuid) && !known.contains(uuid) {
            guard let fetched = try? await AtomRepository.shared.fetch(uuid: uuid), !fetched.isDeleted else { continue }
            withAnimation(ProMotionSprings.gentle) {
                workspace.stagedMediaAtoms.append(fetched)
            }
        }
    }

    // MARK: - Media attach / open

    /// Dropped atom refs (swipe cards, ⌘K results) land as gallery tiles —
    /// or anchored to the section card they were dropped on.
    @MainActor
    private func attachDroppedAtoms(_ uuids: [String], anchor: ConnectionSectionType?) async {
        for uuid in uuids {
            guard uuid != atom.uuid,
                  let source = try? await AtomRepository.shared.fetch(uuid: uuid),
                  !source.isDeleted else { continue }
            // A note/sticky/content piece dropped on the open board starts
            // the collaborator merge directly — the drop IS the intent, and
            // every bullet still goes through staged review.
            if ConceptNoteMergeComposer.isMergeableSource(source.type) {
                await ConceptNoteMergeLauncher.begin(
                    source: ConceptMergeSourceSnapshot(
                        uuid: source.uuid,
                        kind: source.type,
                        title: source.title,
                        inlineBody: source.body
                    ),
                    conceptUUID: atom.uuid
                )
                continue
            }
            // Anything with renderable media qualifies; plain text atoms
            // stay in the Sources rail flow instead.
            guard source.type == .research || ConceptMediaThumbnailResolver.thumbnailURL(for: source) != nil else {
                continue
            }
            withAnimation(ProMotionSprings.gentle) {
                viewModel.attachMediaAtom(source, anchorSection: anchor)
            }
            // Fire-and-forget: the graph edge feeds the Sources rail and the
            // swipe side's "in concepts" back-links.
            Task { await ConceptMediaAttachService.writeGraphEdge(source: source, conceptUUID: atom.uuid) }
        }
    }

    /// Finder file drops / pasted images become owned assets.
    @MainActor
    private func attachDroppedFiles(_ urls: [URL], anchor: ConnectionSectionType?) async {
        for url in urls {
            guard MediaAssetStore.isSupportedMediaExtension(url.pathExtension) else { continue }
            guard let saved = try? await MediaAssetStore.importFile(at: url) else { continue }
            withAnimation(ProMotionSprings.gentle) {
                viewModel.attachMediaAsset(saved, title: url.lastPathComponent, anchorSection: anchor)
            }
        }
    }

    /// Refs written to the DB by an external attach (quick look, agent tool)
    /// union into live state by id — never replace, the session may hold
    /// unsaved refs of its own.
    @MainActor
    private func mergeExternalMedia() async {
        guard let fresh = try? await AtomRepository.shared.fetch(uuid: atom.uuid),
              let data = fresh.structured.flatMap(ConnectionStructuredData.fromJSON),
              let freshMedia = data.media else { return }
        let knownIDs = Set(viewModel.state.media.map(\.id))
        let knownAtomUUIDs = Set(viewModel.state.media.compactMap(\.atomUUID))
        var appended = false
        for ref in freshMedia where !knownIDs.contains(ref.id) {
            if let uuid = ref.atomUUID, knownAtomUUIDs.contains(uuid) { continue }
            withAnimation(ProMotionSprings.gentle) {
                viewModel.state.addMedia(ref)
            }
            appended = true
        }
        if appended {
            await viewModel.loadMediaAtoms()
        }
    }

    /// "Open as pane": the source atom's own focus mode (Swipe Study for
    /// swipes, Research otherwise) opens beside the concept through the
    /// panes-as-tabs registry.
    private func openMediaSourceAsPane(_ atomUUID: String) {
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.openBlockInFocusMode,
            object: nil,
            userInfo: ["atomUUID": atomUUID, "asPane": true]
        )
    }

    /// Serialized snapshot text the in-board diff weaves changes into.
    private var reviewSourceText: String {
        ConnectionSurfaceSerializer.serialize(
            title: viewModel.editableTitle,
            conceptType: viewModel.state.conceptType,
            sections: viewModel.state.sections
        ).text
    }

    private func syncReviewProposal(from proposals: [CosmoAssistantProposal]) {
        // Manuscript keeps the full-screen woven diff (last proposal wins);
        // Board / Outline get per-section ghost rows. Shared resolution with
        // the Study's Concept Desk lives on the serializer.
        let staged = ConnectionSurfaceSerializer.stagedInserts(
            from: proposals,
            atomUUID: atom.uuid,
            title: viewModel.editableTitle,
            conceptType: viewModel.state.conceptType,
            sections: viewModel.state.sections
        )
        reviewProposal = staged.manuscript
        pendingInsertsBySection = staged.bySection
    }

    private func acceptInsert(_ insert: ConnectionPendingInsert) {
        // Persisted pending material (inbox feed / seedling develop): the
        // sweep-in — the bullet becomes a real section item, the capture's
        // originals re-own onto the page, and the staged entry is consumed.
        if let entryId = insert.stagedEntryId {
            guard let entry = persistedInserts.first(where: { $0.id == entryId }) else { return }
            let parsed = ConceptMentionToken.parse(entry.text)
            viewModel.attachItem(
                ConnectionItem(
                    content: parsed.plainText,
                    document: parsed.document,
                    plainText: parsed.plainText,
                    linkedConnectionUUID: parsed.soleConnectionLink?.entityUUID
                ),
                toSection: insert.section
            )
            persistedInserts.removeAll { $0.id == entryId }
            Task {
                _ = try? await ConnectionStagingStore.remove(insertId: entryId, fromConnection: atom.uuid)
                await ConnectionStagingStore.adoptAttachments(of: entry, ontoConnection: atom.uuid)
            }
            return
        }
        guard let provider = ownedContextProvider else { return }
        Task { await CosmoInlineAssistantStore.shared.accept(operationID: insert.operationID, provider: provider) }
    }

    private func rejectInsert(_ insert: ConnectionPendingInsert) {
        // Rejecting persisted material discards the row here — and hands an
        // inbox-fed capture back to the queue (it was still a real thought;
        // "not on this page" must never mean "gone").
        if let entryId = insert.stagedEntryId {
            guard let entry = persistedInserts.first(where: { $0.id == entryId }) else { return }
            persistedInserts.removeAll { $0.id == entryId }
            Task {
                _ = try? await ConnectionStagingStore.remove(insertId: entryId, fromConnection: atom.uuid)
                await ConnectionStagingStore.returnSourceCapture(of: entry)
            }
            return
        }
        Task { await CosmoInlineAssistantStore.shared.reject(operationID: insert.operationID) }
    }

    /// Fresh read of the page's persisted pending material.
    private func loadPersistedInserts() async {
        guard let fresh = try? await AtomRepository.shared.fetch(uuid: atom.uuid) else { return }
        persistedInserts = fresh.connectionStagedInserts
    }

    // MARK: - Lifecycle

    private func handleAppear() {
        AtomRepository.shared.acquireEditingLock(uuid: atom.uuid)
        viewModel.loadState()
        workspace.viewMode = viewModel.state.viewMode
        if let pendingSection = ConnectionFocusDeepLink.consume(for: atom.uuid) {
            workspace.openSection(pendingSection)
        }
        registerContextProvider()
        Task {
            // Sections come from a FRESH DB fetch — never from the UserDefaults
            // blob or the (possibly stale) open-time atom snapshot.
            await viewModel.refreshSectionsFromDatabase()
            // A source was dropped onto this concept on the canvas: the
            // collaborator opens in the pane already intaking it — AFTER the
            // fresh section load (so it stages against current content), but
            // BEFORE the slower rail loads below, so a hiccup in any of them
            // can never swallow the merge the user just confirmed.
            if let source = ConceptMergeHandoff.consume(for: atom.uuid) {
                await ConceptNoteMergeLauncher.begin(source: source, conceptUUID: atom.uuid)
            }
            await loadPersistedInserts()
            await viewModel.loadMediaAtoms()
            await loadSources()
            await loadLinkTargets()
            bindRecommendations()
            await recommendations.refresh()
        }
    }

    /// The Material rail reads the page through this snapshot — live values
    /// at query time, never open-time copies.
    private func bindRecommendations() {
        recommendations.bind(atomUUID: atom.uuid) {
            ConceptRecommendationSnapshot(
                atomUUID: atom.uuid,
                title: viewModel.editableTitle,
                conceptType: viewModel.state.conceptType,
                state: viewModel.state,
                linkedUUIDs: Set(wellSources.map(\.uuid))
            )
        }
    }

    private func handleDisappear() {
        AtomRepository.shared.releaseEditingLock(uuid: atom.uuid)
        viewModel.state.viewMode = workspace.viewMode
        viewModel.flushTitleSave()
        // ONE atom persist: saveState() routes it through the escorted async
        // close save (the old explicit saveToAtom() here ran the same
        // synchronous write TWICE inside the exit animation).
        viewModel.saveState()
        // Assistant scope and window context follow presence: leaving the
        // concept releases both.
        if let owned = ownedContextProvider {
            CosmoEditableSurfaceRegistry.shared.unregister(owned)
            CosmoWindowViewModel.shared.releaseContext(provider: owned)
            ownedContextProvider = nil
        }
    }

    /// Presence, not ownership — see `CosmoEditableSurfaceRegistry.registerPresence`.
    /// Every open document registers so the assistant's scope switcher can list
    /// it; only one pane at a time may own the *window* context.
    private func registerContextProvider() {
        let provider = ownedContextProvider ?? ConnectionContextProvider(
            atom: atom,
            viewModel: viewModel,
            titleProvider: { [weak viewModel] in
                viewModel?.editableTitle ?? "Untitled Concept"
            }
        )
        ownedContextProvider = provider
        CosmoEditableSurfaceRegistry.shared.registerPresence(provider)
        guard !isPaneContext || isPaneContextOwner else { return }
        CosmoWindowViewModel.shared.updateContext(provider: provider)
    }

    // MARK: - Keyboard

    private func handleEscape() -> KeyPress.Result {
        if workspace.isComparePresented {
            withAnimation(ProMotionSprings.focusTransition) {
                workspace.isComparePresented = false
            }
            return .handled
        }
        if workspace.presentedMediaID != nil {
            withAnimation(ProMotionSprings.focusTransition) {
                workspace.presentedMediaID = nil
            }
            return .handled
        }
        if workspace.isNavigatorOverlayPresented {
            withAnimation(ProMotionSprings.focusTransition) {
                workspace.isNavigatorOverlayPresented = false
            }
            return .handled
        }
        if workspace.isInspectorOverlayPresented {
            withAnimation(ProMotionSprings.focusTransition) {
                workspace.isInspectorOverlayPresented = false
            }
            return .handled
        }
        if workspace.pushedSection != nil {
            withAnimation(ProMotionSprings.focusTransition) {
                workspace.popSection()
            }
            return .handled
        }
        if workspace.isSearching {
            workspace.searchQuery = ""
            return .handled
        }
        if workspace.viewMode == .manuscript {
            withAnimation(ProMotionSprings.focusTransition) {
                workspace.viewMode = .board
            }
            return .handled
        }
        onClose()
        return .handled
    }

    private func handleKeyCommand(_ keyPress: KeyPress) -> KeyPress.Result {
        // Lightbox paging — arrows walk the gallery while the Stage is up.
        if workspace.presentedMediaID != nil {
            if keyPress.key == .leftArrow {
                presentAdjacentMedia(offset: -1)
                return .handled
            }
            if keyPress.key == .rightArrow {
                presentAdjacentMedia(offset: 1)
                return .handled
            }
        }
        guard keyPress.modifiers.contains(.command) else { return .ignored }

        if keyPress.modifiers.contains(.option), keyPress.key == KeyEquivalent("i") {
            withAnimation(ProMotionSprings.focusTransition) {
                workspace.toggleInspector()
            }
            return .handled
        }

        switch keyPress.characters {
        case "v": return handleBoardPaste()
        case "1": return setViewMode(.board)
        case "2": return setViewMode(.outline)
        case "3", "m": return setViewMode(workspace.viewMode == .manuscript ? .board : .manuscript)
        case "0":
            withAnimation(ProMotionSprings.focusTransition) {
                workspace.toggleNavigator()
            }
            return .handled
        case "f":
            workspace.searchFocusTick += 1
            return .handled
        case "k":
            presentSharedCommandK()
            return .handled
        default:
            return .ignored
        }
    }

    /// ⌘V on the board: media files and platform URLs land in the gallery.
    /// STATE-GATED — a focused text editor keeps its own paste (never steal
    /// ⌘V from NSTextView; see the block-shortcut precedent).
    private func handleBoardPaste() -> KeyPress.Result {
        if NSApp.keyWindow?.firstResponder is NSTextView { return .ignored }
        let pasteboard = NSPasteboard.general

        // 1. Files on the pasteboard (copied in Finder).
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] {
            let mediaFiles = urls.filter { MediaAssetStore.isSupportedMediaExtension($0.pathExtension) }
            if !mediaFiles.isEmpty {
                Task { await attachDroppedFiles(mediaFiles, anchor: nil) }
                return .handled
            }
        }

        // 2. Raw image data (screenshot, copied image).
        if let imageData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            let ext = pasteboard.data(forType: .png) != nil ? "png" : "tiff"
            Task {
                guard let saved = try? await MediaAssetStore.save(imageData, originalFilename: "pasted.\(ext)") else { return }
                withAnimation(ProMotionSprings.gentle) {
                    viewModel.attachMediaAsset(saved, title: "Pasted image", anchorSection: nil)
                }
            }
            return .handled
        }

        // 3. A platform URL (YouTube, Instagram, TikTok, X…) — capture
        // through the swipe pipeline (stable-post-id dedup included), then
        // attach. `?t=` becomes the ref's start moment.
        if let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           QuickCaptureProcessor.shared.isURL(text) {
            Task { await captureAndAttachURL(text, anchor: nil) }
            return .handled
        }
        return .ignored
    }

    /// Capture a pasted/dropped URL into a research atom, then attach it.
    /// The gallery shows a skeleton tile while the pipeline runs.
    @MainActor
    private func captureAndAttachURL(_ urlString: String, anchor: ConnectionSectionType?) async {
        workspace.pendingMediaCaptures += 1
        defer { workspace.pendingMediaCaptures = max(0, workspace.pendingMediaCaptures - 1) }
        let timestamp = ConnectionMediaItem.parseTimestamp(fromURL: urlString)
        guard let uuid = await QuickCaptureProcessor.shared.captureURLReturningUUID(urlString),
              let source = try? await AtomRepository.shared.fetch(uuid: uuid) else { return }
        withAnimation(ProMotionSprings.gentle) {
            viewModel.attachMediaAtom(source, anchorSection: anchor, timestampSeconds: timestamp)
        }
    }

    private func presentAdjacentMedia(offset: Int) {
        let ordered = viewModel.state.orderedMedia
        guard let presentedID = workspace.presentedMediaID,
              let index = ordered.firstIndex(where: { $0.id == presentedID }) else { return }
        let target = index + offset
        guard ordered.indices.contains(target) else { return }
        workspace.presentedMediaID = ordered[target].id
    }

    private func setViewMode(_ mode: ConnectionViewMode) -> KeyPress.Result {
        withAnimation(ProMotionSprings.focusTransition) {
            workspace.viewMode = mode
            workspace.pushedSection = nil
        }
        return .handled
    }

    // MARK: - Sources

    /// The one shared ⌘K palette lives in MainView (zIndex 200, above focus
    /// modes). A local `.sheet(CommandKView())` here rendered a second,
    /// backdropped copy of the palette — never present ⌘K locally.
    private func presentSharedCommandK() {
        NotificationCenter.default.post(name: .showCommandPalette, object: nil)
    }

    /// ⌘K picker selection — connections only accept source links now
    /// (floating canvas blocks are gone). The shared palette closes itself
    /// after posting the pick.
    private func handleAtomPicked(_ notification: Notification) {
        guard let uuid = notification.userInfo?["atomUUID"] as? String else { return }
        // Gallery "+" armed the picker: this pick is a media attach.
        if mediaPickerArmed {
            mediaPickerArmed = false
            Task { await attachDroppedAtoms([uuid], anchor: nil) }
            return
        }
        let typeRaw = notification.userInfo?["atomType"] as? String ?? AtomType.idea.rawValue
        let atomType = AtomType(rawValue: typeRaw) ?? .idea
        guard isEligibleSourceType(atomType) else { return }
        Task {
            guard let source = try? await AtomRepository.shared.fetch(uuid: uuid) else { return }
            await linkSourceToConnection(source)
        }
    }

    private func isEligibleSourceType(_ type: AtomType) -> Bool {
        switch type {
        case .research, .idea, .content, .note, .connection:
            return true
        default:
            return false
        }
    }

    private func openSource(_ atomUUID: String) {
        Task {
            guard let sourceAtom = try? await AtomRepository.shared.fetch(uuid: atomUUID) else { return }
            // Web-backed sources (references imported from inquiry sessions)
            // open the actual page in the browser pane instead of an atom pane.
            if let urlString = sourceAtom.researchMetadata?.url,
               let url = URL(string: urlString) {
                NotificationCenter.default.post(
                    name: CosmoNotification.Navigation.openWebBrowserPane,
                    object: nil,
                    userInfo: ["url": url, "title": sourceAtom.title ?? urlString]
                )
                return
            }
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openBlockInFocusMode,
                object: nil,
                userInfo: ["atomUUID": atomUUID, "asPane": true]
            )
        }
    }

    /// Sibling Connection pages of the same deep dive become inline link
    /// targets — mentions of their titles in item text open them as panes.
    /// Works from a FRESH fetch (the open-time snapshot may predate the deep
    /// dive link) and merges the live References rows, so a page minted
    /// seconds ago hyperlinks its mention immediately — even when this page
    /// belongs to no deep dive at all.
    @MainActor
    private func loadLinkTargets() async {
        var targets: [ConnectionLinkTargets.Target] = []
        var seen = Set<String>()

        let fresh = (try? await AtomRepository.shared.fetch(uuid: atom.uuid)) ?? atom
        var deepDive: Atom?
        if let deepDiveUUID = fresh.linksOfType(.deepDiveConnection).first?.uuid {
            deepDive = try? await AtomRepository.shared.fetch(uuid: deepDiveUUID)
        }
        if deepDive == nil {
            deepDive = await CosmoInlineInquiryQuestionResolver.resolveDeepDive(for: fresh)
        }
        if let deepDive,
           let siblings = try? await InquiryRepository.shared.fetchConnections(forDeepDive: deepDive) {
            for sibling in siblings {
                guard sibling.uuid != atom.uuid, let title = sibling.title, !title.isEmpty,
                      seen.insert(sibling.uuid).inserted else { continue }
                targets.append(.init(uuid: sibling.uuid, title: title))
            }
        }

        // Live References rows: pages this one links by hand or by minting.
        // The VM is the truth mid-session — a freshly minted page is here
        // before any deep-dive round trip settles.
        for section in viewModel.state.sections where section.type == .references {
            for item in section.items {
                guard let uuid = item.linkedConnectionUUID, uuid != atom.uuid,
                      seen.insert(uuid).inserted else { continue }
                let title = item.resolvedPlainText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { continue }
                targets.append(.init(uuid: uuid, title: title))
            }
        }

        linkTargets = ConnectionLinkTargets(targets: targets)
    }

    @MainActor
    private func loadSources() async {
        var fetched = await coDevEngine.findLinkedSourceMaterials(for: atom.uuid, limit: 20)
        // A section page develops FROM its parts — member concepts lead the rail.
        let members = await coDevEngine.findSectionMemberMaterials(for: atom)
        if !members.isEmpty {
            let memberIDs = Set(members.map(\.uuid))
            fetched.removeAll { memberIDs.contains($0.uuid) }
            fetched = members + fetched
        }
        wellSources = fetched
        if isShowingSuggestedSources {
            let linkedIDs = Set(wellSources.map(\.uuid))
            suggestedWellSources.removeAll { linkedIDs.contains($0.uuid) }
        }
    }

    /// Mid-session refresh after a reference was added: re-queries linked
    /// sources, and — because the graph index that backs the query can lag a
    /// just-written link — guarantees the named counterpart appears by
    /// fetching it directly. Animated so the new row slides into the rail.
    @MainActor
    private func refreshSources(ensuring counterpartUUID: String?) async {
        var fetched = await coDevEngine.findLinkedSourceMaterials(for: atom.uuid, limit: 20)
        if let counterpartUUID, counterpartUUID != atom.uuid,
           !fetched.contains(where: { $0.uuid == counterpartUUID }),
           let counterpart = try? await AtomRepository.shared.fetch(uuid: counterpartUUID),
           !counterpart.isDeleted, counterpart.isEligibleWellSource {
            fetched.insert(counterpart, at: 0)
        }
        withAnimation(ProMotionSprings.gentle) {
            wellSources = fetched
        }
        if isShowingSuggestedSources {
            let linkedIDs = Set(wellSources.map(\.uuid))
            suggestedWellSources.removeAll { linkedIDs.contains($0.uuid) }
        }
    }

    @MainActor
    private func requestSuggestedSources() async {
        isShowingSuggestedSources = true
        isLoadingSuggestedSources = true
        let linkedIDs = Set(wellSources.map(\.uuid))
        var suggestionSeed = atom
        suggestionSeed.title = viewModel.editableTitle
        var suggestions = await coDevEngine.findSourceMaterials(for: suggestionSeed, limit: 8)
            .filter { !linkedIDs.contains($0.uuid) }

        // The bookshelf: Readwise books whose highlights carry this concept's
        // words join the rail — linking one cites it like any other source.
        // Threshold-gated by the matcher, so a book only appears when a real
        // highlight matches, never because its title sounds adjacent.
        let bookshelf = await ReadwiseEvidenceMatcher.evidence(
            conceptName: viewModel.editableTitle,
            limit: 6
        )
        let suggestedIDs = Set(suggestions.map(\.uuid))
        var seenBooks = Set<String>()
        for match in bookshelf where !linkedIDs.contains(match.bookUUID)
            && !suggestedIDs.contains(match.bookUUID)
            && !seenBooks.contains(match.bookUUID) {
            seenBooks.insert(match.bookUUID)
            if let book = try? await AtomRepository.shared.fetch(uuid: match.bookUUID), !book.isDeleted {
                suggestions.append(book)
            }
        }

        suggestedWellSources = suggestions
        isLoadingSuggestedSources = false
    }

    @MainActor
    private func linkSourceToConnection(_ source: Atom) async {
        // Preflight both endpoints: addingLink silently no-ops on a corrupt
        // links column, so proceeding would pretend the link was created.
        guard !source.linksAreCorrupt else {
            PersistenceHealth.note(
                .decodeFailure,
                context: "ConnectionFocusMode.linkSource",
                detail: "source \(source.uuid) links column corrupt; link not created (connection \(atom.uuid))"
            )
            return
        }

        var updatedSource = source
        let hasConnectionLink = updatedSource.linksList.contains {
            $0.uuid == atom.uuid &&
            ($0.entityType == AtomType.connection.rawValue ||
             $0.type == AtomLinkType.connection.rawValue ||
             $0.type == AtomLinkType.related.rawValue)
        }

        if !hasConnectionLink {
            updatedSource = updatedSource.addingLink(.related(atom.uuid, entityType: .connection))
            do {
                try await AtomRepository.shared.update(updatedSource)
            } catch {
                PersistenceHealth.note(
                    .writeFailure,
                    context: "ConnectionFocusMode.linkSource",
                    detail: "source endpoint write failed (source \(source.uuid), connection \(atom.uuid)): \(error.localizedDescription)"
                )
                return
            }
        }

        if var updatedConnection = try? await AtomRepository.shared.fetch(uuid: atom.uuid) {
            let hasSourceLink = updatedConnection.linksList.contains { $0.uuid == source.uuid }
            if !hasSourceLink {
                if updatedConnection.linksAreCorrupt {
                    PersistenceHealth.note(
                        .decodeFailure,
                        context: "ConnectionFocusMode.linkSource",
                        detail: "connection \(atom.uuid) links column corrupt; pair half-linked (source \(source.uuid) already written)"
                    )
                } else {
                    updatedConnection = updatedConnection.addingLink(.related(source.uuid, entityType: source.type))
                    do {
                        try await AtomRepository.shared.update(updatedConnection)
                    } catch {
                        // Second endpoint failed — retry once on a fresh copy
                        // before reporting the half-linked pair.
                        do {
                            if var retryConnection = try await AtomRepository.shared.fetch(uuid: atom.uuid),
                               !retryConnection.linksAreCorrupt {
                                retryConnection = retryConnection.addingLink(.related(source.uuid, entityType: source.type))
                                try await AtomRepository.shared.update(retryConnection)
                            }
                        } catch {
                            PersistenceHealth.note(
                                .writeFailure,
                                context: "ConnectionFocusMode.linkSource",
                                detail: "second endpoint write failed; pair half-linked (source \(source.uuid), connection \(atom.uuid)): \(error.localizedDescription)"
                            )
                        }
                    }
                }
            }
        }

        suggestedWellSources.removeAll { $0.uuid == source.uuid }
        await loadSources()
        // A freshly linked source must stop being recommended material.
        recommendations.poke()
    }
}

// MARK: - Connection Focus Mode ViewModel

@MainActor
@Observable
final class ConnectionFocusModeViewModel {

    // MARK: - Observable state

    var state: ConnectionFocusModeState
    var editableTitle: String
    var titleDocument: RichDocument

    // MARK: - Properties

    @ObservationIgnored private let atom: Atom
    @ObservationIgnored private var titleSaveTask: Task<Void, Never>?
    /// Tracks whether sections were actually modified in this focus mode session.
    /// Prevents saveToAtom() from overwriting DB sections with stale state
    /// when the user only viewed but didn't edit in focus mode.
    @ObservationIgnored private(set) var sectionsModifiedInFocusMode = false
    /// Monotonic ticket for escorted saves — stale in-flight snapshots skip
    /// their write (mirrors IdeaFocusModeViewModel.saveSequence).
    @ObservationIgnored private var saveSequence: UInt64 = 0

    // MARK: - Initialization

    init(atom: Atom) {
        self.atom = atom
        self.state = ConnectionFocusModeState(atomUUID: atom.uuid)
        let initialTitleDocument = RichDocumentPersistence.loadAtomDocument(
            field: .title,
            metadata: atom.metadata,
            fallbackPlainText: atom.title ?? "New Concept",
            atomUUID: atom.uuid
        )
        self.titleDocument = initialTitleDocument
        self.editableTitle = RichDocumentPersistence.titlePlainText(from: initialTitleDocument)
        parseAtomStructuredData()

        // The `.cosmoAppWillTerminate` flush lives in the VIEW (.onReceive),
        // never here: `State(initialValue:)` builds a model per re-render and
        // SwiftUI discards all but the first — an init-owned sink made every
        // discarded copy flush its stale open-time state at quit (the
        // idea_stale_model_clobber shape).
    }

    // MARK: - State Management

    func loadState() {
        // The UserDefaults blob carries ONLY layout/viewport/insights/view-mode.
        // Sections are owned by the DB (atom.structured): applying the blob's
        // sections here used to clobber fresher DB sections with last session's
        // snapshot, and the next save persisted the regression (RC6).
        if let savedState = ConnectionFocusModeState.load(atomUUID: atom.uuid) {
            let liveSections = state.sections
            let liveMedia = state.media
            state = savedState
            state.sections = liveSections
            state.media = liveMedia
        }
    }

    /// Replaces in-memory sections with a fresh decode of the atom's structured
    /// column. Called on appear so sections never come from a stale snapshot.
    @MainActor
    func refreshSectionsFromDatabase() async {
        guard let fresh = try? await AtomRepository.shared.fetch(uuid: atom.uuid) else { return }
        applySections(fromStructured: fresh.structured)
    }

    func saveState(persistToAtom: Bool = true) {
        state.lastModified = Date()
        state.save()

        // Also save to atom.structured — escorted async, so the focus-exit
        // animation never blocks on the DB write lock. The app-termination
        // sink calls the synchronous saveToAtom() directly.
        if persistToAtom {
            saveToAtomEscorted()
        }
    }

    // MARK: - Title

    /// UI-driven title edits (navigator title field). Debounced DB write.
    func setTitle(_ newTitle: String) {
        editableTitle = newTitle
        titleDocument = RichDocument.migrateLegacy(newTitle)
        scheduleTitleSave()
    }

    /// Programmatic renames (e.g. the inline assistant's editable surface).
    /// Updates the live UI title and persists immediately.
    func updateTitle(_ newTitle: String) {
        editableTitle = newTitle
        titleDocument = RichDocument.migrateLegacy(newTitle)
        flushTitleSave()
    }

    private func scheduleTitleSave() {
        let atomUUID = atom.uuid
        let document = titleDocument
        let plainTitle = editableTitle
        titleSaveTask?.cancel()
        titleSaveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
            guard !Task.isCancelled else { return }
            do {
                let titleDocument = RichDocumentPersistence.normalizedTitleDocument(
                    document.isEmpty ? RichDocument.migrateLegacy(plainTitle) : document
                )
                try await CosmoDatabase.shared.asyncWrite { db in
                    var existingMetadata: String?
                    if let row = try Row.fetchOne(db, sql: "SELECT metadata FROM atoms WHERE uuid = ?", arguments: [atomUUID]) {
                        existingMetadata = row["metadata"]
                    }
                    let fields = RichDocumentPersistence.writeAtomDocuments(
                        existingMetadata: existingMetadata,
                        titleDocument: titleDocument
                    )
                    try db.execute(
                        sql: "UPDATE atoms SET title = ?, metadata = ?, updated_at = ?, _local_version = _local_version + 1 WHERE uuid = ?",
                        arguments: [fields.title, fields.metadata, ISO8601.string(from: Date()), atomUUID]
                    )
                }
            } catch {
                print("❌ Connection title save failed: \(error)")
            }
        }
    }

    /// Immediate title save (title commit / view disappear). The write itself
    /// is async so the UI never blocks on the DB write lock (cross-process
    /// busy timeout is 5s); the DirtyEditorRegistry escort keeps the quit
    /// guarantee — terminating mid-write flushes synchronously.
    func flushTitleSave() {
        titleSaveTask?.cancel()
        let escortID = "connection-title-\(atom.uuid)-\(UUID().uuidString.prefix(8))"
        DirtyEditorRegistry.shared.register(id: escortID) { [weak self] in
            self?.flushTitleSaveSync()
        }
        let titleDocument = RichDocumentPersistence.normalizedTitleDocument(
            self.titleDocument.isEmpty ? RichDocument.migrateLegacy(editableTitle) : self.titleDocument
        )
        let atomUUID = atom.uuid
        Task { @MainActor in
            defer { DirtyEditorRegistry.shared.unregister(id: escortID) }
            do {
                try await CosmoDatabase.shared.asyncWrite { db in
                    var existingMetadata: String?
                    if let row = try Row.fetchOne(db, sql: "SELECT metadata FROM atoms WHERE uuid = ?", arguments: [atomUUID]) {
                        existingMetadata = row["metadata"]
                    }
                    let fields = RichDocumentPersistence.writeAtomDocuments(
                        existingMetadata: existingMetadata,
                        titleDocument: titleDocument
                    )
                    try db.execute(
                        sql: "UPDATE atoms SET title = ?, metadata = ?, updated_at = ?, _local_version = _local_version + 1, _local_pending = 1 WHERE uuid = ?",
                        arguments: [fields.title, fields.metadata, ISO8601.string(from: Date()), atomUUID]
                    )
                }
                // Sync: queue for Supabase push
                if let updatedAtom = try? await AtomRepository.shared.fetch(uuid: atomUUID) {
                    // skipVersionIncrement: raw SQL already did _local_version + 1
                    await ChangeTracker.shared.trackUpdate(table: "atoms", entity: updatedAtom, skipVersionIncrement: true)
                }
            } catch {
                print("❌ Connection title flush failed: \(error)")
            }
        }
    }

    /// Synchronous title save — escort/termination path only.
    private func flushTitleSaveSync() {
        let titleDocument = RichDocumentPersistence.normalizedTitleDocument(
            self.titleDocument.isEmpty ? RichDocument.migrateLegacy(editableTitle) : self.titleDocument
        )
        let atomUUID = atom.uuid
        do {
            try CosmoDatabase.shared.write { db in
                var existingMetadata: String?
                if let row = try Row.fetchOne(db, sql: "SELECT metadata FROM atoms WHERE uuid = ?", arguments: [atomUUID]) {
                    existingMetadata = row["metadata"]
                }
                let fields = RichDocumentPersistence.writeAtomDocuments(
                    existingMetadata: existingMetadata,
                    titleDocument: titleDocument
                )
                try db.execute(
                    sql: "UPDATE atoms SET title = ?, metadata = ?, updated_at = ?, _local_version = _local_version + 1, _local_pending = 1 WHERE uuid = ?",
                    arguments: [fields.title, fields.metadata, ISO8601.string(from: Date()), atomUUID]
                )
            }
            // Sync: queue for Supabase push
            Task {
                if let updatedAtom = try? await AtomRepository.shared.fetch(uuid: atomUUID) {
                    // skipVersionIncrement: raw SQL already did _local_version + 1
                    await ChangeTracker.shared.trackUpdate(table: "atoms", entity: updatedAtom, skipVersionIncrement: true)
                }
            }
        } catch {
            print("❌ Connection title flush failed: \(error)")
        }
    }

    // MARK: - Atom persistence

    private func parseAtomStructuredData() {
        // Memoized decode (Atom.DecodedColumnCache): this init re-runs on
        // every SwiftUI re-init of the focus view, and the raw whole-column
        // parse was per-init main-thread cost. Same nil-on-absent/corrupt
        // semantics as the old ConnectionStructuredData.fromJSON guard.
        guard let data = atom.structuredData(as: ConnectionStructuredData.self) else { return }
        applyParsedSections(data)
    }

    private func applySections(fromStructured structured: String?) {
        guard let structured,
              let data = ConnectionStructuredData.fromJSON(structured) else {
            return
        }
        applyParsedSections(data)
    }

    private func applyParsedSections(_ data: ConnectionStructuredData) {
        // Merge saved sections with default sections
        for savedSection in data.sections {
            if let index = state.sections.firstIndex(where: { $0.type == savedSection.type }) {
                state.sections[index] = savedSection
            }
        }

        // Media rides the same structured column; absent key = no media yet.
        state.media = data.media ?? []
    }

    func saveToAtom() {
        // Only write structured/body to atom if sections were actually modified
        // in this focus mode session. Otherwise, skip to avoid overwriting
        // sections that were edited in the canvas block view.
        guard sectionsModifiedInFocusMode else { return }
        let structuredData = ConnectionStructuredData(sections: state.sections, media: state.media)
        let atomUUID = atom.uuid
        do {
            // Re-fetch the live row (synchronously — this also runs from the
            // app-termination sink). Saving from the immutable open-time `atom`
            // snapshot reverted title/metadata/links to open-time values.
            let fresh = try CosmoDatabase.shared.read { db in
                try Atom.filter(Column("uuid") == atomUUID).fetchOne(db)
            } ?? atom
            // Merge the sections key over existing structured so legacy
            // mental-model keys survive the round-trip.
            var updatedAtom = fresh.mergingStructuredKeys(structuredData)
            updatedAtom.body = state.flattenedBodyText
            // updateSync is versioned, merge-on-conflict, and queues the sync
            // row in the same transaction — no separate ChangeTracker call.
            _ = try AtomRepository.shared.updateSync(updatedAtom)
        } catch {
            PersistenceHealth.note(
                .writeFailure,
                context: "ConnectionFocusMode.saveToAtom(\(atomUUID.prefix(8)))",
                detail: error.localizedDescription
            )
        }
    }

    /// Escorted async atom persist — mirrors IdeaFocusModeViewModel.saveOnClose:
    /// the focus-exit animation must never block on the DB write lock
    /// (cross-process busy timeout is 5s). The registry escort preserves the
    /// quit guarantee — terminating mid-write flushes the captured snapshot
    /// synchronously; the commit unregisters it. The `.cosmoAppWillTerminate`
    /// sink keeps calling the synchronous `saveToAtom()` directly.
    private func saveToAtomEscorted() {
        // GUARD-TWIN of the gate in `saveToAtom()` (change together): a
        // session that never edited sections must not overwrite sections
        // edited in the canvas block view.
        guard sectionsModifiedInFocusMode else { return }

        // Snapshot on main — the write body must never read live state later.
        let structuredData = ConnectionStructuredData(sections: state.sections, media: state.media)
        let bodyText = state.flattenedBodyText
        let sequence = nextSaveSequence()

        let escortID = "connection-close-\(atom.uuid)-\(UUID().uuidString.prefix(8))"
        DirtyEditorRegistry.shared.register(id: escortID) { [weak self] in
            self?.writeStructuredSnapshotSync(structuredData, bodyText: bodyText, sequence: sequence)
        }
        Task { @MainActor in
            defer { DirtyEditorRegistry.shared.unregister(id: escortID) }
            await self.writeStructuredSnapshot(structuredData, bodyText: bodyText, sequence: sequence)
        }
    }

    private func nextSaveSequence() -> UInt64 {
        saveSequence += 1
        return saveSequence
    }

    private func writeStructuredSnapshot(_ structuredData: ConnectionStructuredData, bodyText: String, sequence: UInt64) async {
        guard sequence == saveSequence else { return }
        let atomUUID = atom.uuid
        do {
            // Fetch-fresh-row anti-clobber stays INSIDE the escorted body:
            // saving from the immutable open-time `atom` snapshot reverted
            // title/metadata/links to open-time values.
            let fresh = try await CosmoDatabase.shared.asyncRead { db in
                try Atom.filter(Column("uuid") == atomUUID).fetchOne(db)
            } ?? atom
            // Merge the sections key over existing structured so legacy
            // mental-model keys survive the round-trip.
            var updatedAtom = fresh.mergingStructuredKeys(structuredData)
            updatedAtom.body = bodyText
            // update() is the async twin of updateSync: versioned,
            // merge-on-conflict, and queues the sync row.
            _ = try await AtomRepository.shared.update(updatedAtom)
        } catch {
            PersistenceHealth.note(
                .writeFailure,
                context: "ConnectionFocusMode.saveToAtomEscorted(\(atomUUID.prefix(8)))",
                detail: error.localizedDescription
            )
        }
    }

    /// Synchronous escort fallback — termination path only.
    private func writeStructuredSnapshotSync(_ structuredData: ConnectionStructuredData, bodyText: String, sequence: UInt64) {
        guard sequence == saveSequence else { return }
        let atomUUID = atom.uuid
        do {
            let fresh = try CosmoDatabase.shared.read { db in
                try Atom.filter(Column("uuid") == atomUUID).fetchOne(db)
            } ?? atom
            var updatedAtom = fresh.mergingStructuredKeys(structuredData)
            updatedAtom.body = bodyText
            _ = try AtomRepository.shared.updateSync(updatedAtom)
        } catch {
            PersistenceHealth.note(
                .writeFailure,
                context: "ConnectionFocusMode.saveToAtomEscorted.sync(\(atomUUID.prefix(8)))",
                detail: error.localizedDescription
            )
        }
    }

    // MARK: - Item Management

    func addItem(document: RichDocument, plainText: String, toSection type: ConnectionSectionType) {
        sectionsModifiedInFocusMode = true
        let item = ConnectionItem(content: plainText, document: document, plainText: plainText)
        state.addItem(item, toSection: type)
        saveState()
    }

    /// Evidence-rail attach (Concept Desk): a fully-formed item lands in its
    /// section with provenance (sourceAtomUUID + sourceSnippet) intact.
    func attachItem(_ item: ConnectionItem, toSection type: ConnectionSectionType) {
        sectionsModifiedInFocusMode = true
        state.addItem(item, toSection: type)
        saveState()
    }

    func editItem(_ item: ConnectionItem, inSection type: ConnectionSectionType) {
        sectionsModifiedInFocusMode = true
        state.updateItem(item, inSection: type)
        saveState()
    }

    /// Inserts an item at a specific position: directly after `afterItemID`,
    /// or at the top of the section when nil. Used by the inline assistant's
    /// editable surface so accepted diffs land exactly where they previewed.
    @discardableResult
    func insertItem(
        document: RichDocument,
        plainText: String,
        inSection type: ConnectionSectionType,
        afterItemID: UUID?,
        linkedConnectionUUID: String? = nil
    ) -> ConnectionItem? {
        guard let sectionIndex = state.sections.firstIndex(where: { $0.type == type }) else { return nil }
        sectionsModifiedInFocusMode = true
        let item = ConnectionItem(
            content: plainText,
            document: document,
            plainText: plainText,
            linkedConnectionUUID: linkedConnectionUUID
        )
        if let afterItemID,
           let itemIndex = state.sections[sectionIndex].items.firstIndex(where: { $0.id == afterItemID }) {
            state.sections[sectionIndex].items.insert(item, at: itemIndex + 1)
        } else if afterItemID == nil {
            state.sections[sectionIndex].items.insert(item, at: 0)
        } else {
            state.sections[sectionIndex].items.append(item)
        }
        state.lastModified = Date()
        saveState()
        return item
    }

    func deleteItem(_ id: UUID, fromSection type: ConnectionSectionType) {
        // Snapshot for ⌘Z before the removal mutates the section.
        let removedSnapshot: (item: ConnectionItem, index: Int)? = state.sections
            .first(where: { $0.type == type })
            .flatMap { section in
                section.items.firstIndex(where: { $0.id == id })
                    .map { (section.items[$0], $0) }
            }

        sectionsModifiedInFocusMode = true
        state.removeItem(id: id, fromSection: type)
        saveState()

        guard let removed = removedSnapshot else { return }
        CosmoUndoManager.shared.register(InlineUndoAction(
            actionDescription: "Delete Item",
            undo: { [weak self] in
                guard let self,
                      let sectionIndex = self.state.sections.firstIndex(where: { $0.type == type }) else { return }
                let clamped = min(removed.index, self.state.sections[sectionIndex].items.count)
                self.state.sections[sectionIndex].items.insert(removed.item, at: clamped)
                self.state.lastModified = Date()
                self.sectionsModifiedInFocusMode = true
                self.saveState()
            },
            redo: { [weak self] in
                guard let self else { return }
                self.sectionsModifiedInFocusMode = true
                self.state.removeItem(id: id, fromSection: type)
                self.saveState()
            }
        ))
    }

    func updateConceptType(_ type: ConceptFrameworkType) {
        state.conceptType = type
        saveState()
    }

    // MARK: - Objection handling

    /// Upsert the handling thread on an item. An empty handling (no text, no
    /// links) clears it — the objection reopens.
    func setObjectionHandling(
        itemID: UUID,
        inSection type: ConnectionSectionType,
        text: String,
        linkedRefs: [ConnectionBoardItemRef]
    ) {
        guard let sectionIndex = state.sections.firstIndex(where: { $0.type == type }),
              let itemIndex = state.sections[sectionIndex].items.firstIndex(where: { $0.id == itemID }) else { return }
        sectionsModifiedInFocusMode = true
        var item = state.sections[sectionIndex].items[itemIndex]
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && linkedRefs.isEmpty {
            item.handling = nil
        } else if var existing = item.handling {
            existing.text = trimmed
            existing.linkedRefs = linkedRefs
            existing.updatedAt = Date()
            item.handling = existing
        } else {
            item.handling = ObjectionHandling(text: trimmed, linkedRefs: linkedRefs)
        }
        item.updatedAt = Date()
        state.sections[sectionIndex].items[itemIndex] = item
        state.lastModified = Date()
        saveState()
    }

    func clearObjectionHandling(itemID: UUID, inSection type: ConnectionSectionType) {
        setObjectionHandling(itemID: itemID, inSection: type, text: "", linkedRefs: [])
    }

    /// Resolve a board ref to its live item (for link chips + jump).
    func resolveBoardRef(_ ref: ConnectionBoardItemRef) -> (section: ConnectionSectionType, item: ConnectionItem)? {
        guard let section = ref.section,
              let item = state.section(for: section)?.items.first(where: { $0.id == ref.itemID }) else { return nil }
        return (section, item)
    }

    // MARK: - Media

    /// Source atoms for atom-backed media refs, keyed by uuid. Populated on
    /// appear and on attach so gallery tiles render without per-tile fetches.
    var mediaAtoms: [String: Atom] = [:]

    /// Fetch source atoms for every atom-backed ref not already cached.
    func loadMediaAtoms() async {
        let missing = state.media.compactMap(\.atomUUID).filter { mediaAtoms[$0] == nil }
        guard !missing.isEmpty else { return }
        for uuid in missing {
            if let fetched = try? await AtomRepository.shared.fetch(uuid: uuid), !fetched.isDeleted {
                mediaAtoms[uuid] = fetched
            }
        }
    }

    /// Attach an atom's media to the board. Idempotent per source atom: a
    /// second attach re-anchors/re-stamps the existing ref instead of
    /// duplicating the tile.
    @discardableResult
    func attachMediaAtom(
        _ source: Atom,
        anchorSection: ConnectionSectionType? = nil,
        timestampSeconds: Double? = nil
    ) -> ConnectionMediaItem {
        mediaAtoms[source.uuid] = source
        if var existing = state.mediaItem(forAtomUUID: source.uuid) {
            var changed = false
            if let anchorSection, existing.anchorSection != anchorSection {
                existing.anchorSection = anchorSection
                changed = true
            }
            if let timestampSeconds, existing.timestampSeconds != timestampSeconds {
                existing.timestampSeconds = timestampSeconds
                changed = true
            }
            if changed {
                sectionsModifiedInFocusMode = true
                state.updateMedia(existing)
                saveState()
            }
            return existing
        }
        let ref = ConnectionMediaItem.ref(
            for: source,
            anchorSection: anchorSection,
            timestampSeconds: timestampSeconds
        )
        sectionsModifiedInFocusMode = true
        state.addMedia(ref)
        saveState()
        return ref
    }

    /// Attach an owned asset (file drop / paste) already persisted by
    /// MediaAssetStore.
    @discardableResult
    func attachMediaAsset(
        _ saved: MediaAssetStore.SavedAsset,
        title: String?,
        anchorSection: ConnectionSectionType? = nil
    ) -> ConnectionMediaItem {
        let ref = ConnectionMediaItem(
            kind: saved.isVideo ? .video : .image,
            assetPath: saved.path,
            thumbnailAssetPath: saved.thumbnailPath,
            assetTitle: title,
            anchorSection: anchorSection
        )
        sectionsModifiedInFocusMode = true
        state.addMedia(ref)
        saveState()
        // Mirror in the background so other devices can render the asset;
        // stamp the URL back onto the ref when the upload lands.
        Task { [weak self] in
            guard let self else { return }
            guard let url = await MediaAssetStore.mirrorToCloud(ref) else { return }
            if var current = self.state.mediaItem(id: ref.id) {
                current.assetRemoteURL = url
                self.state.updateMedia(current)
                self.saveState()
            }
        }
        return ref
    }

    /// Detach a ref. Owned-asset files are deleted only AFTER the ref is out
    /// of the persisted blob (crash-safe order); source atoms are untouched.
    func detachMedia(id: UUID) {
        guard let item = state.mediaItem(id: id) else { return }
        sectionsModifiedInFocusMode = true
        state.removeMedia(id: id)
        saveState()
        if !item.isAtomBacked {
            MediaAssetStore.deleteAsset(of: item)
        }
    }

    func updateMediaRef(_ item: ConnectionMediaItem) {
        sectionsModifiedInFocusMode = true
        state.updateMedia(item)
        saveState()
    }

    func setMediaCaption(id: UUID, caption: String) {
        guard var item = state.mediaItem(id: id) else { return }
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        item.caption = trimmed.isEmpty ? nil : trimmed
        updateMediaRef(item)
    }

    func setMediaAnchor(id: UUID, section: ConnectionSectionType?) {
        guard var item = state.mediaItem(id: id) else { return }
        item.anchorSection = section
        updateMediaRef(item)
    }

    func toggleMediaCover(id: UUID) {
        sectionsModifiedInFocusMode = true
        state.setCoverMedia(id: id)
        saveState()
    }

    func pinMediaMoment(id: UUID, seconds: Double) {
        guard var item = state.mediaItem(id: id) else { return }
        item.timestampSeconds = max(0, seconds)
        updateMediaRef(item)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Connection Focus Mode") {
    ConnectionFocusModeView(
        atom: Atom.new(
            type: .connection,
            title: "Atomic Habits Framework",
            body: "Building lasting habits through small improvements."
        ),
        onClose: {}
    )
    .frame(width: 1280, height: 800)
}
#endif

// ConnectionContextProvider lives in ConnectionEditableSurface.swift — it
// doubles as the inline assistant's editable surface for this connection.
