// CosmoOS/Canvas/NoteBlockView.swift
// Orange-accented Note block for Thinkspace canvas
// Dark glass design matching Sanctuary aesthetic
// December 2025 - Thinkspace revamp

import SwiftUI
import GRDB
import Combine

struct NoteBlockView: View {
    let block: CanvasBlock
    /// Scoped canvases open the same saved Page within their own navigation.
    var onOpen: ((Atom) -> Void)? = nil

    @State private var noteTitleDocument: RichDocument = .empty
    @State private var noteBodyDocument: RichDocument = .empty
    @State private var noteTitleText: String = ""
    @State private var noteText: String = ""
    @State private var noteWordCount: Int = 0
    @State private var titleEditorHeight: CGFloat = 50
    @State private var pendingObservedTitleDocument: RichDocument?
    @State private var titleDocumentAtEditStart: RichDocument = .empty
    @State private var isEditingTitle = false
    @State private var isEditingBody = false

    // Mutable entity tracking — updated when a backing atom is created
    @State private var trackedEntityId: Int64 = 0
    @State private var trackedEntityUuid: String = ""

    // Auto-save debouncing
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var saveClosed = false

    // Guards against stale writes: only save if the user actually edited this block.
    // Without this, onDisappear would write back whatever was loaded from DB,
    // which could be an old version if a GRDB observation update was blocked by isEditingBody.
    @State private var hasLocalEdits = false

    // Prevents GRDB observation updates from triggering auto-save
    @State private var isSyncingFromDB = false
    @State private var lastLocalSaveEchoBodyPlainText: String?
    @State private var lastLocalSaveEchoBodyDocument: RichDocument?

    // GRDB observation
    @State private var atomSubscription: CanvasAtomSubscription?

    // Orange accent for notes
    private let accentColor = CosmoColors.blockNote
    private let titleStyle = SharedTitleSurfaceStyle.noteCanvas

    /// The note's per-document voice (Aa menu) travels with it — the canvas
    /// card renders in the same font family and leading as the focus mode.
    @State private var noteDocumentStyle: NoteDocumentStyle = .default

    private var titleFontSize: CGFloat { 40 }
    private var bodyFontSize: CGFloat { 20 }
    private var documentTitleFont: Font {
        .system(size: titleFontSize, weight: .semibold, design: .serif)
    }

    private var titleMinHeight: CGFloat {
        EditorLayoutMetrics.titleHeight(
            fontSize: titleFontSize,
            compact: titleStyle.compact,
            baseFontWeight: titleStyle.baseFontWeight,
            lineCount: 1
        )
    }

    private var titlePreviewMaxHeight: CGFloat {
        EditorLayoutMetrics.titleHeight(
            fontSize: titleFontSize,
            compact: titleStyle.compact,
            baseFontWeight: titleStyle.baseFontWeight,
            lineCount: titleStyle.previewLineLimit
        )
    }

    private var titleEditingMaxHeight: CGFloat {
        EditorLayoutMetrics.titleHeight(
            fontSize: titleFontSize,
            compact: titleStyle.compact,
            baseFontWeight: titleStyle.baseFontWeight,
            lineCount: titleStyle.editingLineLimit
        )
    }

    // MARK: - Thought card (compact rendering)

    /// A 30-word thought never wears a letter-page costume. Inbox placements
    /// land short notes as compact blocks; any note that is both compact and
    /// short renders as a thought card — body only, caption metadata, no 40pt
    /// serif title, no word-count footer. Writing past the cap in focus mode
    /// graduates it back to the page shape live.
    static let thoughtWordCap = 60
    private static let thoughtWidthCap: CGFloat = 320

    private var rendersAsThoughtCard: Bool {
        block.size.width <= Self.thoughtWidthCap
            && noteWordCount <= Self.thoughtWordCap
            // The thought card is a plain-text costume — a note carrying a
            // sketch, image, or element must render its real blocks or the
            // preview degrades to "[Sketch]" and flattened element text.
            && !noteBodyDocument.containsVisualBlocks
    }

    var body: some View {
        Group {
            if rendersAsThoughtCard {
                NoteThoughtCard(
                    block: block,
                    text: noteText,
                    // Default paper tone renders nil — the card falls back to
                    // the elevated surface (the quiet warm card ground).
                    paper: noteDocumentStyle.paperTone.pageColor(darkMode: DS.palette.isDark)
                        ?? DS.surfaceElevated,
                    onOpen: openFocusMode
                )
            } else {
                documentBody
            }
        }
        .onAppear {
            saveClosed = false
            isEditingBody = false
            isEditingTitle = false
            trackedEntityId = block.entityId
            trackedEntityUuid = block.entityUuid
            loadNote()
            startObservingAtom()
            // Terminate-safe flush: the 1s debounce loses typing on ⌘Q without this.
            // saveNoteSync is dirty-gated internally (no-op when clean).
            DirtyEditorRegistry.shared.register(id: "noteblock-\(block.id)") {
                saveNoteSync()
            }
        }
        .onDisappear {
            autoSaveTask?.cancel()
            CanvasAtomObservationHub.shared.unsubscribe(atomSubscription)
            atomSubscription = nil
            // Defer sync save by one frame so CosmoDocumentEditor's flushPendingSync()
            // can propagate the latest text via onDocumentChange first.
            // Without this, the 50ms attributedText debounce can cause us to save stale content.
            DispatchQueue.main.async {
                saveClosed = true
                saveNoteSync()
                DirtyEditorRegistry.shared.unregister(id: "noteblock-\(block.id)")
            }
        }
        .onChange(of: isEditingTitle) { _, isEditing in
            if isEditing {
                titleDocumentAtEditStart = noteTitleDocument
                pendingObservedTitleDocument = nil
                titleEditorHeight = min(titleEditingMaxHeight, max(titleMinHeight, titleEditorHeight))
            } else {
                if let pendingObservedTitleDocument, noteTitleDocument == titleDocumentAtEditStart {
                    applyObservedTitleDocument(pendingObservedTitleDocument)
                }
                pendingObservedTitleDocument = nil
            }
        }
        // Listen for direct state change notifications from focus mode
        .onReceive(NotificationCenter.default.publisher(for: .noteFocusStateDidChange)) { notification in
            if let uuid = notification.userInfo?["atomUUID"] as? String,
               uuid == trackedEntityUuid {
                if let title = notification.userInfo?["title"] as? String {
                    let titleDocument: RichDocument
                    if let json = notification.userInfo?["titleDocumentJSON"] as? String,
                       let data = json.data(using: .utf8),
                       let doc = try? JSONDecoder().decode(RichDocument.self, from: data) {
                        titleDocument = RichDocumentPersistence.normalizedTitleDocument(doc)
                    } else {
                        titleDocument = RichDocumentPersistence.normalizedTitleDocument(
                            RichDocument.migrateLegacy(title)
                        )
                    }

                    if isEditingTitle {
                        if titleDocument != noteTitleDocument {
                            pendingObservedTitleDocument = titleDocument
                        }
                    } else {
                        applyObservedTitleDocument(titleDocument)
                    }
                }
                if let body = notification.userInfo?["body"] as? String {
                    noteText = body
                    noteWordCount = Self.wordCount(in: body)
                    if let json = notification.userInfo?["bodyDocumentJSON"] as? String,
                       let data = json.data(using: .utf8),
                       let doc = try? JSONDecoder().decode(RichDocument.self, from: data) {
                        noteBodyDocument = doc
                    } else {
                        noteBodyDocument = RichDocument.migrateLegacy(body)
                    }
                }
            }
        }
        // Listen for entity linkage updates (when backing atom is created)
        .onReceive(NotificationCenter.default.publisher(for: .updateBlockEntity)) { notification in
            guard let blockId = notification.userInfo?["blockId"] as? String,
                  blockId == block.id,
                  let entityId = notification.userInfo?["entityId"] as? Int64,
                  let entityUuid = notification.userInfo?["entityUuid"] as? String else { return }
            trackedEntityId = entityId
            trackedEntityUuid = entityUuid
            // Restart hub observation with the new UUID
            startObservingAtom()
        }
        // Authoritative blocks landed after a thinkspace switch — the mounted view
        // may still hold text from a stale snapshot cache. Re-run the load when
        // there's nothing local to lose. Targeted: a payload of changed block
        // ids scopes the reload to actually-affected views.
        .onReceive(NotificationCenter.default.publisher(for: .canvasBlocksDidResync)) { notification in
            if let changedIds = notification.userInfo?["blockIds"] as? [String],
               !changedIds.contains(block.id) {
                return
            }
            guard !isEditingBody, !isEditingTitle, !hasLocalEdits else { return }
            isSyncingFromDB = true
            loadNote()
            DispatchQueue.main.async {
                isSyncingFromDB = false
            }
        }
    }

    private var documentBody: some View {
        CosmoBlockWrapper(
            block: block,
            accentColor: accentColor,
            icon: "note.text",
            title: displayTitle,
            surfaceStyle: .crisp,
            surfaceTint: noteDocumentStyle.paperTone.pageColor(darkMode: DS.palette.isDark),
            fixedLayoutSize: CanvasBlock.documentLayoutSize,
            preservesAspectRatio: true,
            suppressGiltCorner: true,
            suppressAccentChip: true,
            onFocusMode: openFocusMode
        ) {
            noteContent
        }
    }

    // MARK: - Display Title

    private var displayTitle: String {
        // Use title field, or fall back to first line of content
        if !noteTitleText.isEmpty {
            return String(noteTitleText.prefix(40))
        }
        if let firstLine = noteText.components(separatedBy: .newlines).first,
           !firstLine.isEmpty {
            return String(firstLine.prefix(40))
        }
        return "Untitled Page"
    }

    // MARK: - Note Content

    private var noteContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            titleView

            bodyView

            noteFooter
        }
        .padding(.top, noteDocumentStyle.pageIcon == nil ? 78 : 108)
        .padding(.horizontal, 56)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Page personality — the card is a faithful miniature of the page:
        // the cover wash pours from the top edge and fades into the paper
        // behind the title, the way it does behind the Page's own; the seated
        // page mark sits above the title. Style arrives live via the GRDB
        // observation.
        .background(alignment: .top) {
            NotePageCoverBand(
                style: noteDocumentStyle,
                darkMode: DS.palette.isDark,
                height: 300
            )
            .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            if let pageIcon = noteDocumentStyle.pageIcon {
                NotePageIconView(
                    icon: pageIcon,
                    style: noteDocumentStyle,
                    darkMode: DS.palette.isDark,
                    size: 30,
                    seated: true
                )
                .padding(.leading, 56)
                .padding(.top, 48)
                .allowsHitTesting(false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .blurAllBlocks)) { _ in
            isEditingTitle = false
            isEditingBody = false
        }
    }

    @ViewBuilder
    private var bodyView: some View {
        if isEditingBody {
            ScrollView(.vertical, showsIndicators: false) {
                CosmoDocumentEditor(
                    document: $noteBodyDocument,
                    fontSize: bodyFontSize,
                    fontDesign: noteDocumentStyle.fontFamily.design,
                    lineSpacingAdjustment: noteDocumentStyle.lineSpacing.lineSpacingDelta,
                    placeholder: "Press / for commands…",
                    allowSlashCommands: true,
                    allowMentions: true,
                    allowSelectionMenu: true,
                    allowImages: true,
                    scrollsInternally: false,
                    onPlainTextChange: applyBodyPlainTextChange,
                    onDocumentChange: applyBodyDocumentChange,
                    autoFocus: true
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .contentMargins(.top, 4, for: .scrollContent)
            .contentMargins(.bottom, 8, for: .scrollContent)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                if noteBodyDocument.isEmpty {
                    Text("Press / for commands…")
                        .font(.system(size: bodyFontSize))
                        .foregroundStyle(DS.documentTextMuted)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                } else {
                    CosmoDocumentRenderer(
                        document: noteBodyDocument,
                        fontSize: bodyFontSize,
                        stackMode: CosmoDocumentRendererStackPolicy.mode(
                            for: .canvasPreview,
                            blockCount: noteBodyDocument.blocks.count
                        )
                    )
                    .fontDesign(noteDocumentStyle.fontFamily.swiftUIDesign)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .contentMargins(.top, 4, for: .scrollContent)
            .contentMargins(.bottom, 8, for: .scrollContent)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture {
                // Tables, sections, callouts, toggles, code and sketches
                // exist only in the block editor — the card's continuous
                // editor would flatten them on the way back. Such a note is
                // entered through focus mode (inert-until-entered).
                if noteBodyDocument.requiresBlockEditor {
                    openFocusMode()
                } else {
                    isEditingBody = true
                }
            }
        }
    }

    private var noteFooter: some View {
        HStack {
            Spacer()
            Text("\(noteWordCount) words  ·  \(noteText.count) chars")
                .font(.system(size: 15, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(DS.documentTextMuted)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(DS.documentBorderSubtle, lineWidth: 1)
                }
        }
    }

    private var titleView: some View {
        Group {
            if isEditingTitle {
                CosmoDocumentEditor(
                    document: $noteTitleDocument,
                    fontSize: titleFontSize,
                    compact: titleStyle.compact,
                    placeholder: "Heading",
                    allowSlashCommands: false,
                    allowMentions: true,
                    allowSelectionMenu: false,
                    allowImages: false,
                    titleConfiguration: titleStyle.titleConfiguration,
                    baseFontWeight: titleStyle.baseFontWeight,
                    scrollsInternally: true,
                    onContentHeightChange: { newHeight in
                        titleEditorHeight = min(titleEditingMaxHeight, max(titleMinHeight, newHeight))
                    },
                    onPlainTextChange: { plainText in
                        let changed = plainText != noteTitleText
                        noteTitleText = plainText
                        if changed {
                            markLocalEditAndScheduleSave()
                        }
                    },
                    onStructuredDocumentChange: { document, plainText in
                        let changed = document != noteTitleDocument || plainText != noteTitleText
                        noteTitleDocument = document
                        noteTitleText = plainText
                        if changed {
                            markLocalEditAndScheduleSave()
                        }
                    },
                    onDeactivate: { isEditingTitle = false },
                    onCommit: { isEditingTitle = false },
                    autoFocus: true
                )
                .frame(height: min(titleEditingMaxHeight, max(titleMinHeight, titleEditorHeight)))
            } else {
                Text(noteTitleText.isEmpty ? "Heading" : noteTitleText)
                    .font(documentTitleFont)
                    .foregroundStyle(noteTitleText.isEmpty ? DS.documentTextMuted : DS.documentText)
                    .lineLimit(titleStyle.previewLineLimit)
                    .truncationMode(.tail)
                    .multilineTextAlignment(titleStyle.swiftUITextAlignment)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        titleDocumentAtEditStart = noteTitleDocument
                        isEditingTitle = true
                    }
            }
        }
    }

    // MARK: - Load Note

    private func loadNote() {
        // First try block.metadata (for freeform blocks)
        noteTitleDocument = RichDocumentPersistence.loadBlockDocument(
            key: RichDocumentMetadataKeys.titleDocument,
            metadata: block.metadata,
            fallbackPlainText: block.metadata["title"],
            atomUUID: block.id
        )
        noteBodyDocument = RichDocumentPersistence.loadBlockDocument(
            key: RichDocumentMetadataKeys.bodyDocument,
            metadata: block.metadata,
            fallbackPlainText: block.metadata["content"],
            atomUUID: block.id
        )
        noteTitleText = RichDocumentPersistence.titlePlainText(from: noteTitleDocument)
        noteText = noteBodyDocument.plainText
        noteWordCount = Self.wordCount(in: noteText)

        if noteTitleText.isEmpty, let title = block.metadata["title"] {
            noteTitleText = title
        }

        // Fall back to block.title / block.subtitle (for atom-backed blocks via fromAtom())
        if noteTitleText.isEmpty {
            let blockTitle = block.title
            if !["Note", "Page", "Untitled"].contains(blockTitle) {
                noteTitleText = blockTitle
                noteTitleDocument = RichDocument.migrateLegacy(blockTitle)
            }
        }
        if noteText.isEmpty, let subtitle = block.subtitle {
            noteText = subtitle
            noteBodyDocument = RichDocument.migrateLegacy(subtitle)
            noteWordCount = Self.wordCount(in: noteText)
        }

        // If linked to an atom, load freshest data — the thinkspace switch
        // batch-fetched every entity atom into the warm store, so mounts hit
        // it synchronously. The repository round-trip survives only as a
        // fallback for blocks that arrive outside a snapshot fetch.
        if trackedEntityId > 0 || !trackedEntityUuid.isEmpty {
            if let warm = warmStoreAtom() {
                applyLoadedAtom(warm)
            } else {
                Task {
                    do {
                        let atom: Atom?
                        if trackedEntityId > 0,
                           let atomByID = try await AtomRepository.shared.fetch(id: trackedEntityId) {
                            atom = atomByID
                        } else if !trackedEntityUuid.isEmpty {
                            atom = try await AtomRepository.shared.fetch(uuid: trackedEntityUuid)
                        } else {
                            atom = nil
                        }

                        if let atom {
                            await MainActor.run {
                                applyLoadedAtom(atom)
                            }
                        }
                    } catch {
                        PersistenceHealth.note(.writeFailure, context: "noteBlock.loadAtom", detail: "uuid=\(trackedEntityUuid): \(error)")
                        print("NoteBlock: Failed to load atom: \(error)")
                    }
                }
            }
        }
    }

    private func warmStoreAtom() -> Atom? {
        if trackedEntityId > 0, let atom = CanvasAtomWarmStore.shared.atom(id: trackedEntityId) {
            return atom
        }
        if !trackedEntityUuid.isEmpty {
            return CanvasAtomWarmStore.shared.atom(uuid: trackedEntityUuid)
        }
        return nil
    }

    /// Apply a freshly-loaded entity atom to view state. Shared by the warm
    /// store hit (synchronous, at mount) and the repository fallback.
    private func applyLoadedAtom(_ atom: Atom) {
        // Entity linkage is always safe to refresh.
        trackedEntityId = atom.id ?? trackedEntityId
        trackedEntityUuid = atom.uuid
        // Style refresh never clobbers text — safe mid-edit.
        noteDocumentStyle = NoteDocumentStyle.load(fromMetadata: atom.metadata)
        // Don't clobber text the user typed (or is typing) while
        // the load was in flight — mirror the hub observation.
        guard !isEditingBody, !isEditingTitle, !hasLocalEdits else { return }
        isSyncingFromDB = true
        noteTitleDocument = RichDocumentPersistence.loadAtomDocument(
            field: .title,
            metadata: atom.metadata,
            fallbackPlainText: atom.title,
            atomUUID: atom.uuid
        )
        noteBodyDocument = RichDocumentPersistence.loadAtomDocument(
            field: .body,
            metadata: atom.metadata,
            fallbackPlainText: atom.body,
            atomUUID: atom.uuid
        )
        noteTitleText = RichDocumentPersistence.titlePlainText(from: noteTitleDocument)
        noteText = noteBodyDocument.plainText
        noteWordCount = Self.wordCount(in: noteText)
        DispatchQueue.main.async {
            isSyncingFromDB = false
        }
    }

    // MARK: - GRDB Observation

    private func startObservingAtom() {
        // Re-subscribe cleanly when the entity linkage changes.
        CanvasAtomObservationHub.shared.unsubscribe(atomSubscription)
        atomSubscription = nil

        let uuid = trackedEntityUuid
        // Only observe if we have a real UUID (not empty)
        guard !uuid.isEmpty else { return }

        // One hub observation covers every mounted block. The hub dedupes on
        // version fields, so this callback only fires for genuinely new data
        // (the old per-block observation compared full metadata strings —
        // hundreds of KB for rich notes — on every atoms write, per block).
        atomSubscription = CanvasAtomObservationHub.shared.subscribe(uuid: uuid) { atom in
            applyObservedAtom(atom)
        }
    }

    private func applyObservedAtom(_ atom: Atom) {
        // Style changes (made in focus mode) apply immediately —
        // they never touch the text, so no stale-write guard needed.
        noteDocumentStyle = NoteDocumentStyle.load(fromMetadata: atom.metadata)
        let newTitleDocument = RichDocumentPersistence.loadAtomDocument(
            field: .title,
            metadata: atom.metadata,
            fallbackPlainText: atom.title,
            atomUUID: atom.uuid
        )
        let newBodyDocument = RichDocumentPersistence.loadAtomDocument(
            field: .body,
            metadata: atom.metadata,
            fallbackPlainText: atom.body,
            atomUUID: atom.uuid
        )
        let newTitle = RichDocumentPersistence.titlePlainText(from: newTitleDocument)
        let newBody = newBodyDocument.plainText
        DispatchQueue.main.async {
            var didApplyDatabaseState = false
            var didApplyObservedBody = false

            if !isEditingTitle,
               newTitle != noteTitleText || newTitleDocument != noteTitleDocument {
                didApplyDatabaseState = true
                applyObservedTitleDocument(newTitleDocument)
            } else if isEditingTitle,
                      newTitle != noteTitleText || newTitleDocument != noteTitleDocument {
                pendingObservedTitleDocument = newTitleDocument
            }

            // Only overwrite body from DB when NOT actively editing —
            // otherwise the observation echo from auto-save overwrites
            // text the user typed since the save was initiated.
            let observedBodyChanged = newBody != noteText || newBodyDocument != noteBodyDocument
            let isLocalSaveEcho = newBody == lastLocalSaveEchoBodyPlainText
                && newBodyDocument == lastLocalSaveEchoBodyDocument
            if NoteWritePolicy.shouldApplyObservedBody(
                isEditingBody: isEditingBody,
                hasLocalEdits: hasLocalEdits,
                observedBodyChanged: observedBodyChanged,
                isLocalSaveEcho: isLocalSaveEcho
            ) {
                didApplyDatabaseState = true
                didApplyObservedBody = true
                noteBodyDocument = newBodyDocument
                noteText = newBody
                noteWordCount = Self.wordCount(in: newBody)
            }

            guard didApplyDatabaseState else { return }
            // Only a body apply proves local body content now matches DB.
            // A title-only DB update must not clear pending body edits.
            if didApplyObservedBody {
                hasLocalEdits = false
            }
            isSyncingFromDB = true
            DispatchQueue.main.async {
                isSyncingFromDB = false
            }
        }
    }

    private func applyObservedTitleDocument(_ document: RichDocument) {
        noteTitleDocument = document
        noteTitleText = RichDocumentPersistence.titlePlainText(from: document)
    }

    private func applyBodyPlainTextChange(_ plainText: String) {
        let changed = plainText != noteText
        noteText = plainText
        noteWordCount = Self.wordCount(in: plainText)

        if changed {
            markLocalEditAndScheduleSave()
        }
    }

    private func applyBodyDocumentChange(_ document: RichDocument, plainText: String) {
        let changed = plainText != noteText || document != noteBodyDocument
        noteBodyDocument = document
        noteText = plainText
        noteWordCount = Self.wordCount(in: plainText)

        if changed {
            markLocalEditAndScheduleSave()
        }
    }

    private func markLocalEditAndScheduleSave() {
        guard !isSyncingFromDB else { return }
        hasLocalEdits = true
        scheduleAutoSave()
    }

    private func titleDocumentForSave() -> RichDocument {
        let normalizedDocument = RichDocumentPersistence.normalizedTitleDocument(noteTitleDocument)
        let documentPlainText = RichDocumentPersistence.titlePlainText(from: normalizedDocument)
        let currentPlainText = RichDocumentPersistence.normalizedTitleString(noteTitleText)

        guard documentPlainText != currentPlainText else {
            return normalizedDocument
        }

        return currentPlainText.isEmpty ? .empty : RichDocument.migrateLegacy(currentPlainText)
    }

    // MARK: - Auto-save

    private func scheduleAutoSave() {
        print("[BLOCK-NOTE] scheduleAutoSave() — 1s debounce starting uuid=\(trackedEntityUuid)")
        autoSaveTask?.cancel()

        autoSaveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled {
                print("[BLOCK-NOTE] scheduleAutoSave() — debounce elapsed, calling saveNote() uuid=\(trackedEntityUuid)")
                await MainActor.run {
                    saveNote()
                }
            } else {
                print("[BLOCK-NOTE] scheduleAutoSave() — CANCELLED (new keystroke) uuid=\(trackedEntityUuid)")
            }
        }
    }

    private func saveNote() {
        print("[BLOCK-NOTE] saveNote() — uuid=\(trackedEntityUuid) titleLen=\(noteTitleText.count) bodyLen=\(noteText.count) bodyPreview=\"\(String(noteText.prefix(80)))\" saveClosed=\(saveClosed)")
        let effectiveTitleDocument = titleDocumentForSave()
        let blockSnapshot = RichDocumentPersistence.noteSnapshot(
            existingMetadata: nil,
            titleDocument: effectiveTitleDocument,
            bodyDocument: noteBodyDocument,
            plainBodyText: noteText
        )

        // Update block metadata (for SpatialEngine persistence)
        NotificationCenter.default.post(
            name: .updateBlockContent,
            object: nil,
            userInfo: [
                "blockId": block.id,
                "title": blockSnapshot.titlePlainText,
                "content": blockSnapshot.bodyPlainText
            ]
        )

        let updatedMetadata = RichDocumentPersistence
            .writeBlockDocument(blockSnapshot.titleDocument, key: RichDocumentMetadataKeys.titleDocument, metadata: block.metadata)
        let bodyMetadata = RichDocumentPersistence
            .writeBlockDocument(blockSnapshot.bodyDocument, key: RichDocumentMetadataKeys.bodyDocument, metadata: updatedMetadata)
        NotificationCenter.default.post(
            name: .updateBlockMetadata,
            object: nil,
            userInfo: [
                "blockId": block.id,
                "metadata": bodyMetadata.merging([
                    "title": blockSnapshot.titlePlainText,
                    "content": blockSnapshot.bodyPlainText
                ]) { _, new in new }
            ]
        )

        // Also update the atom in the database (for blocks linked to entities)
        let uuid = trackedEntityUuid
        if !uuid.isEmpty {
            lastLocalSaveEchoBodyPlainText = blockSnapshot.bodyPlainText
            lastLocalSaveEchoBodyDocument = blockSnapshot.bodyDocument
            let titleDoc = effectiveTitleDocument
            let titleText = blockSnapshot.titlePlainText
            let bodyDoc = noteBodyDocument
            let bodyText = noteText
            let blockId = block.id
            Task {
                // Skip if sync save already ran on close
                guard !saveClosed else {
                    print("[BLOCK-NOTE] saveNote() async SKIPPED — saveClosed=true uuid=\(uuid)")
                    return
                }
                let capturedStateIsCurrent = await MainActor.run {
                    !saveClosed
                        && RichDocumentPersistence.normalizedTitleString(noteTitleText) == titleText
                        && noteText == bodyText
                }
                guard capturedStateIsCurrent else {
                    print("[BLOCK-NOTE] saveNote() async SKIPPED — stale snapshot uuid=\(uuid)")
                    await MainActor.run {
                        if lastLocalSaveEchoBodyPlainText == blockSnapshot.bodyPlainText,
                           lastLocalSaveEchoBodyDocument == blockSnapshot.bodyDocument {
                            lastLocalSaveEchoBodyPlainText = nil
                            lastLocalSaveEchoBodyDocument = nil
                        }
                    }
                    return
                }
                print("[BLOCK-NOTE] saveNote() async DB write starting — uuid=\(uuid) bodyLen=\(bodyText.count)")
                do {
                    let createdAtomId: Int64? = try await CosmoDatabase.shared.asyncWrite { db in
                        var existingMetadata: String?
                        let atomExists = try Row.fetchOne(db, sql: "SELECT metadata FROM atoms WHERE uuid = ?", arguments: [uuid])
                        existingMetadata = atomExists?["metadata"]

                        let snapshot = RichDocumentPersistence.noteSnapshot(
                            existingMetadata: existingMetadata,
                            titleDocument: titleDoc,
                            bodyDocument: bodyDoc,
                            plainBodyText: bodyText
                        )
                        let now = ISO8601.string(from: Date())

                        if atomExists != nil {
                            AtomRevisionWriter.snapshotBeforeRawWrite(db, uuid: uuid,
                                incomingTitle: snapshot.atomTitle, incomingBody: snapshot.bodyPlainText)
                            // Atom exists — update it
                            // Use bodyText (per-keystroke) instead of fields.body (from RichDocument
                            // which lags 150ms behind due to serialization debounce)
                            try db.execute(
                                sql: """
                                UPDATE atoms
                                SET title = ?,
                                    body = ?,
                                    metadata = ?,
                                    updated_at = ?,
                                    _local_version = _local_version + 1,
                                    _local_pending = 1
                                WHERE uuid = ?
                                """,
                                arguments: [
                                    snapshot.atomTitle ?? titleText,
                                    snapshot.bodyPlainText,
                                    snapshot.metadata,
                                    now,
                                    uuid
                                ]
                            )
                            return nil
                        } else {
                            // No atom yet (legacy freeform block) — create one
                            try db.execute(
                                sql: """
                                INSERT INTO atoms (uuid, type, title, body, metadata, created_at, updated_at, is_deleted, _local_version, _server_version, _sync_version)
                                VALUES (?, ?, ?, ?, ?, ?, ?, 0, 1, 0, 0)
                                """,
                                arguments: [
                                    uuid,
                                    AtomType.note.rawValue,
                                    snapshot.atomTitle ?? titleText,
                                    snapshot.bodyPlainText,
                                    snapshot.metadata,
                                    now,
                                    now
                                ]
                            )
                            let atomId = db.lastInsertedRowID
                            try db.execute(
                                sql: "UPDATE canvas_blocks SET entity_id = ? WHERE entity_uuid = ?",
                                arguments: [atomId, uuid]
                            )
                            return atomId
                        }
                    }
                    // If a new atom was created, update in-memory tracking
                    if let atomId = createdAtomId {
                        await MainActor.run {
                            trackedEntityId = atomId
                            NotificationCenter.default.post(
                                name: .updateBlockEntity,
                                object: nil,
                                userInfo: [
                                    "blockId": blockId,
                                    "entityId": atomId,
                                    "entityUuid": uuid
                                ]
                            )
                        }
                    }
                    // Sync: queue for Supabase push so notes don't only live locally
                    if let updatedAtom = try? await AtomRepository.shared.fetch(uuid: uuid) {
                        let operation = createdAtomId != nil ? "INSERT" : "UPDATE"
                        if operation == "INSERT" {
                            await ChangeTracker.shared.trackInsert(table: "atoms", entity: updatedAtom)
                        } else {
                            // skipVersionIncrement: raw SQL already did _local_version + 1
                            await ChangeTracker.shared.trackUpdate(table: "atoms", entity: updatedAtom, skipVersionIncrement: true)
                        }
                    }
                    await MainActor.run {
                        if noteTitleText == titleText && noteText == bodyText {
                            hasLocalEdits = false
                        }
                    }
                } catch {
                    await MainActor.run {
                        if lastLocalSaveEchoBodyPlainText == blockSnapshot.bodyPlainText,
                           lastLocalSaveEchoBodyDocument == blockSnapshot.bodyDocument {
                            lastLocalSaveEchoBodyPlainText = nil
                            lastLocalSaveEchoBodyDocument = nil
                        }
                    }
                    PersistenceHealth.note(.writeFailure, context: "noteBlock.autosave", detail: "uuid=\(uuid): \(error)")
                    print("NoteBlock: Failed to save to atom: \(error)")
                }
            }
        }
    }

    /// Synchronous save — blocks until DB write completes.
    /// Used on close to guarantee data is persisted before the block/app exits.
    private func saveNoteSync() {
        let uuid = trackedEntityUuid
        print("[BLOCK-NOTE] saveNoteSync() — uuid=\(uuid) titleLen=\(noteTitleText.count) bodyLen=\(noteText.count) hasLocalEdits=\(hasLocalEdits) bodyPreview=\"\(String(noteText.prefix(80)))\"")
        guard !uuid.isEmpty else { print("[BLOCK-NOTE] saveNoteSync() SKIPPED — empty uuid"); return }
        // Only write if the user actually made edits in this block. Without this guard,
        // onDisappear would write back stale state (e.g. the block loaded with 100 chars,
        // focus mode saved 2474 chars, but isEditingBody blocked the GRDB observation from
        // applying the update — so we'd overwrite the good data with the old version).
        guard hasLocalEdits else {
            print("[BLOCK-NOTE] saveNoteSync() SKIPPED — no local edits, avoiding stale overwrite uuid=\(uuid)")
            return
        }

        let effectiveTitleDocument = titleDocumentForSave()
        let blockSnapshot = RichDocumentPersistence.noteSnapshot(
            existingMetadata: nil,
            titleDocument: effectiveTitleDocument,
            bodyDocument: noteBodyDocument,
            plainBodyText: noteText
        )
        lastLocalSaveEchoBodyPlainText = blockSnapshot.bodyPlainText
        lastLocalSaveEchoBodyDocument = blockSnapshot.bodyDocument

        NotificationCenter.default.post(
            name: .updateBlockContent,
            object: nil,
            userInfo: [
                "blockId": block.id,
                "title": blockSnapshot.titlePlainText,
                "content": blockSnapshot.bodyPlainText
            ]
        )

        let updatedMetadata = RichDocumentPersistence
            .writeBlockDocument(blockSnapshot.titleDocument, key: RichDocumentMetadataKeys.titleDocument, metadata: block.metadata)
        let bodyMetadata = RichDocumentPersistence
            .writeBlockDocument(blockSnapshot.bodyDocument, key: RichDocumentMetadataKeys.bodyDocument, metadata: updatedMetadata)
        let mergedBlockMetadata = bodyMetadata.merging([
            "title": blockSnapshot.titlePlainText,
            "content": blockSnapshot.bodyPlainText
        ]) { _, new in new }
        let blockMetadataJSON = SpatialEngine.encodeBlockMetadataJSON(mergedBlockMetadata)
        NotificationCenter.default.post(
            name: .updateBlockMetadata,
            object: nil,
            userInfo: [
                "blockId": block.id,
                "metadata": mergedBlockMetadata
            ]
        )

        do {
            let createdAtomId = try CosmoDatabase.shared.write { db -> Int64? in
                let atomExists = try Row.fetchOne(db, sql: "SELECT metadata FROM atoms WHERE uuid = ?", arguments: [uuid])
                let existingMetadata: String? = atomExists?["metadata"]

                let snapshot = RichDocumentPersistence.noteSnapshot(
                    existingMetadata: existingMetadata,
                    titleDocument: effectiveTitleDocument,
                    bodyDocument: noteBodyDocument,
                    plainBodyText: noteText
                )
                let now = ISO8601.string(from: Date())

                if atomExists != nil {
                    AtomRevisionWriter.snapshotBeforeRawWrite(db, uuid: uuid,
                        incomingTitle: snapshot.atomTitle, incomingBody: snapshot.bodyPlainText)
                    // _local_pending = 1 so cloud sync can't revert this
                    // close-time edit (the async autosave path already sets it).
                    try db.execute(
                        sql: """
                        UPDATE atoms
                        SET title = ?,
                            body = ?,
                            metadata = ?,
                            updated_at = ?,
                            _local_version = _local_version + 1,
                            _local_pending = 1
                        WHERE uuid = ?
                        """,
                        arguments: [
                            snapshot.atomTitle ?? noteTitleText,
                            snapshot.bodyPlainText,
                            snapshot.metadata,
                            now,
                            uuid
                        ]
                    )
                    try db.execute(
                        sql: """
                        UPDATE canvas_blocks
                        SET entity_title = ?,
                            note_content = ?,
                            metadata = ?,
                            updated_at = ?
                        WHERE id = ?
                        """,
                        arguments: [
                            snapshot.titlePlainText.isEmpty ? "Page" : snapshot.titlePlainText,
                            snapshot.bodyPlainText,
                            blockMetadataJSON,
                            now,
                            block.id
                        ]
                    )
                    return nil
                } else {
                    // Legacy freeform block — create atom on close
                    try db.execute(
                        sql: """
                        INSERT INTO atoms (uuid, type, title, body, metadata, created_at, updated_at, is_deleted, _local_version, _server_version, _sync_version, _local_pending)
                        VALUES (?, ?, ?, ?, ?, ?, ?, 0, 1, 0, 0, 1)
                        """,
                        arguments: [
                            uuid,
                            AtomType.note.rawValue,
                            snapshot.atomTitle ?? noteTitleText,
                            snapshot.bodyPlainText,
                            snapshot.metadata,
                            now,
                            now
                        ]
                    )
                    let atomId = db.lastInsertedRowID
                    try db.execute(
                        sql: """
                        UPDATE canvas_blocks
                        SET entity_id = ?,
                            entity_title = ?,
                            note_content = ?,
                            metadata = ?,
                            updated_at = ?
                        WHERE entity_uuid = ?
                        """,
                        arguments: [
                            atomId,
                            snapshot.titlePlainText.isEmpty ? "Page" : snapshot.titlePlainText,
                            snapshot.bodyPlainText,
                            blockMetadataJSON,
                            now,
                            uuid
                        ]
                    )
                    return atomId
                }
            }
            // Sync: queue for Supabase push
            Task {
                if let updatedAtom = try? await AtomRepository.shared.fetch(uuid: uuid) {
                    if createdAtomId != nil {
                        await ChangeTracker.shared.trackInsert(table: "atoms", entity: updatedAtom)
                    } else {
                        // skipVersionIncrement: raw SQL already did _local_version + 1
                        await ChangeTracker.shared.trackUpdate(table: "atoms", entity: updatedAtom, skipVersionIncrement: true)
                    }
                }
            }
            hasLocalEdits = false
        } catch {
            if lastLocalSaveEchoBodyPlainText == blockSnapshot.bodyPlainText,
               lastLocalSaveEchoBodyDocument == blockSnapshot.bodyDocument {
                lastLocalSaveEchoBodyPlainText = nil
                lastLocalSaveEchoBodyDocument = nil
            }
            PersistenceHealth.note(.writeFailure, context: "noteBlock.closeSave", detail: "uuid=\(uuid): \(error)")
            print("NoteBlock: sync save failed: \(error)")
        }
    }

    // MARK: - Focus Mode

    private func openFocusMode() {
        autoSaveTask?.cancel()

        if NoteWritePolicy.requiresBlockFlushBeforeFocusMode(
            hasLocalEdits: hasLocalEdits,
            entityId: trackedEntityId,
            entityUUID: trackedEntityUuid
        ) {
            isEditingTitle = false
            isEditingBody = false

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                openFocusModeAfterFlushingLocalEdits()
            }
            return
        }

        openFocusModeAfterFlushingLocalEdits()
    }

    private func openFocusModeAfterFlushingLocalEdits() {
        autoSaveTask?.cancel()

        if NoteWritePolicy.requiresBlockFlushBeforeFocusMode(
            hasLocalEdits: hasLocalEdits,
            entityId: trackedEntityId,
            entityUUID: trackedEntityUuid
        ) {
            saveNoteSync()
        }

        Task {
            do {
                if !trackedEntityUuid.isEmpty,
                   let existing = try await AtomRepository.shared.fetch(uuid: trackedEntityUuid) {
                    await MainActor.run {
                        trackedEntityId = existing.id ?? trackedEntityId
                        trackedEntityUuid = existing.uuid
                        NotificationCenter.default.post(
                            name: .updateBlockEntity,
                            object: nil,
                            userInfo: [
                                "blockId": block.id,
                                "entityId": existing.id ?? -1,
                                "entityUuid": existing.uuid
                            ]
                        )
                        openResolvedPage(existing)
                    }
                    return
                }

                if trackedEntityId > 0 {
                    if let existing = try await CosmoDatabase.shared.asyncRead({ db in
                        try Atom.fetchOne(db, key: trackedEntityId)
                    }) {
                        await MainActor.run { openResolvedPage(existing) }
                        return
                    }
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .enterFocusMode,
                            object: nil,
                            userInfo: [
                                "type": EntityType.note,
                                "id": trackedEntityId
                            ]
                        )
                    }
                    return
                }

                let snapshot = RichDocumentPersistence.noteSnapshot(
                    existingMetadata: nil,
                    titleDocument: titleDocumentForSave(),
                    bodyDocument: noteBodyDocument,
                    plainBodyText: noteText
                )
                var newAtom = Atom.new(
                    type: .note,
                    title: snapshot.atomTitle,
                    body: snapshot.atomBody,
                    metadata: snapshot.metadata
                )
                if !trackedEntityUuid.isEmpty {
                    newAtom.uuid = trackedEntityUuid
                }
                let created = try await AtomRepository.shared.create(newAtom)
                let atomId = created.id ?? -1
                // Update canvas block record to link to new atom
                try await CosmoDatabase.shared.asyncWrite { db in
                    try db.execute(
                        sql: """
                        UPDATE canvas_blocks
                        SET entity_id = ?, entity_uuid = ?
                        WHERE id = ?
                        """,
                        arguments: [atomId, created.uuid, block.id]
                    )
                }
                await MainActor.run {
                    // Update in-memory block in SpatialEngine + this view
                    NotificationCenter.default.post(
                        name: .updateBlockEntity,
                        object: nil,
                        userInfo: [
                            "blockId": block.id,
                            "entityId": atomId,
                            "entityUuid": created.uuid
                        ]
                    )
                    openResolvedPage(created)
                }
            } catch {
                PersistenceHealth.note(.writeFailure, context: "noteBlock.createBackingAtom", detail: "uuid=\(trackedEntityUuid): \(error)")
                print("NoteBlock: Failed to create backing atom: \(error)")
            }
        }
    }

    private func openResolvedPage(_ atom: Atom) {
        if let onOpen {
            onOpen(atom)
        } else {
            NotificationCenter.default.post(name: .enterFocusMode, object: nil,
                                            userInfo: ["type": EntityType.note, "id": atom.id ?? -1])
        }
    }

    // MARK: - Helpers

    private static func wordCount(in text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private func formatTimestamp(_ timestamp: String) -> String {
        if let date = ISO8601.date(from: timestamp) {
            return CosmoDateFormatters.relative.localizedString(for: date, relativeTo: Date())
        }
        return timestamp
    }
}

// MARK: - Notifications (keep existing for compatibility)

extension Notification.Name {
    static let updateBlockContent = Notification.Name("updateBlockContent")
    static let updateBlockMetadata = Notification.Name("updateBlockMetadata")
    static let updateBlockSize = Notification.Name("updateBlockSize")
    static let saveBlockSize = Notification.Name("saveBlockSize")
    static let blurAllBlocks = Notification.Name("blurAllBlocks")
    static let contentFocusStateDidChange = Notification.Name("contentFocusStateDidChange")
    static let contentFocusStateSaved = Notification.Name("contentFocusStateSaved")
    static let contentPhaseChanged = Notification.Name("contentPhaseChanged")
    static let noteFocusStateDidChange = Notification.Name("noteFocusStateDidChange")
    static let updateBlockEntity = Notification.Name("updateBlockEntity")
    /// Posted by CanvasView after an authoritative block fetch replaces a cached
    /// thinkspace snapshot — mounted note/sticky views re-sync from DB when clean.
    static let canvasBlocksDidResync = Notification.Name("canvasBlocksDidResync")
}

// MARK: - Preview

// MARK: - Thought card

/// The compact costume for a quick thought on the canvas: the words on quiet
/// paper with one caption line — no 40pt serif title, no word-count footer,
/// no page chrome. Same interaction grammar as the sticky (tap selects,
/// double-click opens focus mode, hover lifts); the frame is the block's own
/// compact footprint, so it reads as an object, not a shrunken document.
private struct NoteThoughtCard: View {
    let block: CanvasBlock
    let text: String
    let paper: Color
    let onOpen: () -> Void

    @State private var isSelected = false
    @State private var isHovered = false
    @State private var hasAppeared = false
    @Environment(\.canvasBlockSelectionSuppressed) private var selectionNotificationsSuppressed

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text(text.isEmpty ? "A thought…" : text)
                .font(DS.callout)
                .foregroundStyle(text.isEmpty ? DS.documentTextMuted : DS.documentText)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            Spacer(minLength: 0)

            HStack(spacing: DS.space4) {
                Image(systemName: "leaf")
                    .font(.system(size: 9, weight: .semibold))
                    .accessibilityHidden(true)
                Text(metaLine)
                    .font(DS.caption2)
            }
            .foregroundStyle(DS.textMuted)
        }
        .padding(DS.space16)
        .frame(
            width: block.size.width,
            height: block.size.height,
            alignment: .topLeading
        )
        .background(paper)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ? DS.accent.opacity(0.55) : DS.borderSubtle,
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(DS.accent.opacity(0.22), lineWidth: 3)
                        .blur(radius: 4)
                }
            }
        )
        .shadow(
            color: .black.opacity(isSelected ? 0.08 : (isHovered ? 0.06 : 0.04)),
            radius: isSelected ? 14 : (isHovered ? 12 : 8),
            x: 0,
            y: isSelected ? 4 : (isHovered ? 4 : 2)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            guard !selectionNotificationsSuppressed else { return }
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.blockSelected,
                object: nil,
                userInfo: ["blockId": block.id]
            )
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { onOpen() }
        )
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Canvas.blockSelected)) { notification in
            if let selectedId = notification.userInfo?["blockId"] as? String {
                isSelected = (selectedId == block.id)
            }
        }
        .help("A quick thought — double-click to open and develop it")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Thought: \(text)")
        .scaleEffect(hasAppeared ? 1.0 : 0.92)
        .opacity(hasAppeared ? 1.0 : 0)
        .animation(ProMotionSprings.hover, value: isHovered)
        .animation(ProMotionSprings.hover, value: isSelected)
        .onAppear {
            withAnimation(ProMotionSprings.cardEntrance) {
                hasAppeared = true
            }
        }
    }

    private var metaLine: String {
        if let updated = block.metadata["updated"],
           let date = ISO8601.date(from: updated) {
            return "Thought · \(date.cosmoCompactAge)"
        }
        return "Thought"
    }
}

#if DEBUG
struct NoteBlockView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            CosmoColors.thinkspaceVoid
                .ignoresSafeArea()

            NoteBlockView(
                block: CanvasBlock.noteBlock(position: CGPoint(x: 200, y: 200))
            )
        }
        .frame(width: 500, height: 400)
    }
}

struct NoteThoughtCard_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            DS.bg.ignoresSafeArea()
            NoteThoughtCard(
                block: {
                    var block = CanvasBlock.noteBlock(position: .zero)
                    block.size = InboxActionExecutor.thoughtCardSize(
                        for: previewThought
                    )
                    block.metadata["updated"] = ISO8601.string(from: Date().addingTimeInterval(-7_200))
                    return block
                }(),
                text: previewThought,
                paper: DS.surfaceElevated,
                onOpen: {}
            )
        }
        .frame(width: 420, height: 360)
    }

    private static let previewThought =
        "What you think about and where you spend your time most develops itself and feeds you ideas. Make repeated mental thoughts more intentional."
}
#endif
