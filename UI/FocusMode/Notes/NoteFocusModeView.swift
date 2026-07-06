// CosmoOS/UI/FocusMode/Notes/NoteFocusModeView.swift
// Full-screen dark-themed writing surface for ideas/notes
// February 2026 - Focus mode with GRDB observation + 1.5s debounce auto-save

import SwiftUI
import AppKit
import GRDB
import Combine

enum NoteFocusTitleChromeMode: Equatable {
    case emptyEditableTitle
    case documentHeader
}

enum NoteFocusHeaderLayoutPolicy {
    static func chromeMode(titlePlainText: String, plainContent: String) -> NoteFocusTitleChromeMode {
        let hasTitle = !titlePlainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasContent = !plainContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasTitle || hasContent ? .documentHeader : .emptyEditableTitle
    }

    static func chromeMode(
        titlePlainText: String,
        plainContent: String,
        activeEditChromeMode: NoteFocusTitleChromeMode?
    ) -> NoteFocusTitleChromeMode {
        activeEditChromeMode ?? chromeMode(titlePlainText: titlePlainText, plainContent: plainContent)
    }

    static func showsEmptyGuidance(for mode: NoteFocusTitleChromeMode) -> Bool {
        mode == .emptyEditableTitle
    }

    static func showsTitleUnderline(for mode: NoteFocusTitleChromeMode) -> Bool {
        mode == .emptyEditableTitle
    }

    static func showsMetadataDivider(for mode: NoteFocusTitleChromeMode) -> Bool {
        mode == .documentHeader
    }
}

struct NoteHeadingEntry: Equatable, Sendable {
    let level: Int
    let text: String
}

struct NoteFocusTextAnalysis: Equatable, Sendable {
    static let empty = NoteFocusTextAnalysis(
        wordCount: 0,
        estimatedReadingMinutes: 1,
        outLinkCount: 0,
        headings: []
    )

    let wordCount: Int
    let estimatedReadingMinutes: Int
    let outLinkCount: Int
    let headings: [NoteHeadingEntry]

    static func analyze(_ text: String, headingLimit: Int = 25) -> NoteFocusTextAnalysis {
        var wordCount = 0
        var outLinkCount = 0
        var headings: [NoteHeadingEntry] = []
        var currentWordHasLettersOrNumbers = false
        var line = ""
        var previousCharacter: Character?

        func finishWord() {
            if currentWordHasLettersOrNumbers {
                wordCount += 1
            }
            currentWordHasLettersOrNumbers = false
        }

        func finishLine() {
            if headings.count < headingLimit,
               let heading = headingEntry(from: line) {
                headings.append(heading)
            }
            line.removeAll(keepingCapacity: true)
        }

        for character in text {
            if character == "[" && previousCharacter == "[" {
                outLinkCount += 1
            }

            if character == "\n" {
                finishWord()
                finishLine()
            } else {
                line.append(character)
                if character.isLetter || character.isNumber {
                    currentWordHasLettersOrNumbers = true
                } else if character.isWhitespace {
                    finishWord()
                }
            }

            previousCharacter = character
        }

        finishWord()
        finishLine()

        return NoteFocusTextAnalysis(
            wordCount: wordCount,
            estimatedReadingMinutes: max(1, Int(ceil(Double(wordCount) / 220.0))),
            outLinkCount: outLinkCount,
            headings: headings
        )
    }

    private static func headingEntry(from line: String) -> NoteHeadingEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("# ") {
            return NoteHeadingEntry(level: 1, text: String(trimmed.dropFirst(2)))
        } else if trimmed.hasPrefix("## ") {
            return NoteHeadingEntry(level: 2, text: String(trimmed.dropFirst(3)))
        } else if trimmed.hasPrefix("### ") {
            return NoteHeadingEntry(level: 3, text: String(trimmed.dropFirst(4)))
        }
        return nil
    }
}

enum NoteSaveKind: Equatable, Sendable {
    case plainText
    case richDocumentCheckpoint
}

struct NoteAutosavePolicy: Equatable, Sendable {
    var richCheckpointCharacterThreshold: Int = 4_000
    var richCheckpointInterval: TimeInterval = 30

    func saveKind(
        plainTextCharacterCount: Int,
        now: Date,
        lastRichCheckpointAt: Date?,
        isClosing: Bool
    ) -> NoteSaveKind {
        if isClosing || plainTextCharacterCount < richCheckpointCharacterThreshold {
            return .richDocumentCheckpoint
        }

        guard let lastRichCheckpointAt else {
            return .richDocumentCheckpoint
        }

        return now.timeIntervalSince(lastRichCheckpointAt) >= richCheckpointInterval
            ? .richDocumentCheckpoint
            : .plainText
    }
}

enum NoteAutosaveChangePolicy {
    static func shouldAutosaveTextChange(isInitialLoad: Bool, didChange: Bool) -> Bool {
        !isInitialLoad && didChange
    }

    static func shouldAutosaveDocumentChange(
        isInitialLoad: Bool,
        previousDocument: RichDocument,
        nextDocument: RichDocument,
        previousPlainText: String,
        nextPlainText: String
    ) -> Bool {
        !isInitialLoad && (
            previousPlainText != nextPlainText
                || previousDocument != nextDocument
        )
    }
}

enum NoteFocusLog {
    static let isDebugEnabled = false

    static func debug(_ message: @autoclosure () -> String) {
        guard isDebugEnabled else { return }
        print(message())
    }
}

struct NoteFocusInitialDocuments: Equatable {
    let titleDocument: RichDocument
    let bodyDocument: RichDocument
    let titlePlainText: String
    let plainContent: String
    let tags: [String]
    let createdAt: Date

    static func from(atom: Atom) -> NoteFocusInitialDocuments {
        let titleDocument = RichDocumentPersistence.loadAtomDocument(
            field: .title,
            metadata: atom.metadata,
            fallbackPlainText: atom.title
        )
        let bodyDocument = RichDocumentPersistence.loadAtomDocument(
            field: .body,
            metadata: atom.metadata,
            fallbackPlainText: atom.body
        )
        let titlePlainText = RichDocumentPersistence.titlePlainText(from: titleDocument)
        let plainContent = bodyDocument.plainText
        let createdAt = ISO8601.date(from: atom.createdAt) ?? Date()

        return NoteFocusInitialDocuments(
            titleDocument: titleDocument,
            bodyDocument: bodyDocument,
            titlePlainText: titlePlainText,
            plainContent: plainContent,
            tags: atom.tagsList,
            createdAt: createdAt
        )
    }
}

struct NoteFocusModeView: View {
    // MARK: - Properties

    let atom: Atom
    let onClose: () -> Void

    // MARK: - Initialization

    init(atom: Atom, onClose: @escaping () -> Void) {
        let initialDocuments = NoteFocusInitialDocuments.from(atom: atom)
        self.atom = atom
        self.onClose = onClose
        self._floatingBlocksManager = StateObject(wrappedValue: FocusFloatingBlocksManager(ownerAtomUUID: atom.uuid))
        self._titleDocument = State(initialValue: initialDocuments.titleDocument)
        self._bodyDocument = State(initialValue: initialDocuments.bodyDocument)
        self._titlePlainText = State(initialValue: initialDocuments.titlePlainText)
        self._plainContent = State(initialValue: initialDocuments.plainContent)
        self._tags = State(initialValue: initialDocuments.tags)
        self._lastPersistedTags = State(initialValue: initialDocuments.tags)
        self._createdAt = State(initialValue: initialDocuments.createdAt)
        self._noteStyle = State(initialValue: NoteDocumentStyle.load(fromMetadata: atom.metadata))
    }

    // MARK: - State

    @StateObject private var floatingBlocksManager: FocusFloatingBlocksManager

    @State private var titleDocument: RichDocument = .empty
    @State private var bodyDocument: RichDocument = .empty
    /// Non-nil while the inline assistant has staged reviewable changes for this note —
    /// drives the in-document diff that temporarily replaces the body editor.
    @State private var bodyReviewProposal: CosmoAssistantProposal?
    @State private var titlePlainText: String = ""
    @State private var plainContent: String = ""
    @State private var selectedText: String = ""
    @State private var tags: [String] = []
    @State private var createdAt: Date = Date()
    @State private var showTagEditor = false
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var editingLockRefreshTask: Task<Void, Never>?
    @State private var saveClosed = false
    @State private var observationCancellable: AnyCancellable?
    @State private var isInitialLoad = true
    @State private var hasLocalBodyEdits = false
    /// Title/tags/style edits since load — gates the close save together with
    /// hasLocalBodyEdits so a zero-edit session never writes its stale
    /// open-time snapshot over newer external writes.
    @State private var hasLocalMetaEdits = false
    /// Tags as last loaded from / written to the DB — lets the observation tell
    /// an echo apart from clobbering unsaved local tag edits.
    @State private var lastPersistedTags: [String] = []

    // Sidebar state
    @State private var sidebarVisible = false
    @State private var linkedAtoms: [Atom] = []

    // Animation states
    @State private var contentAppeared = false
    @State private var titleUnderlineProgress: CGFloat = 0
    @State private var titleEditorHeight: CGFloat = 76
    @State private var scrollViewportHeight: CGFloat = 0
    @State private var pendingObservedTitleDocument: RichDocument?
    @State private var titleDocumentAtEditStart: RichDocument = .empty
    @State private var isEditingTitle = false
    @State private var titleChromeModeAtEditStart: NoteFocusTitleChromeMode?

    // Save state
    @State private var saveState: SaveState = .idle

    // Writing mode
    @AppStorage("sidebarCollapsed") private var isSidebarHidden: Bool = false
    @AppStorage("typewriterMode") private var typewriterMode = false
    /// Paragraph focus — everything but the caret's block fades back (iA model).
    @AppStorage("noteParagraphFocus") private var paragraphFocus = false

    // V2 "Scholar's Carrel" rail state
    @AppStorage("noteFocusV2.leftRail") private var leftRailVisible: Bool = true
    @AppStorage("noteFocusV2.rightRail") private var rightRailVisible: Bool = true
    /// Measured rail content heights — the glass panels hug their content
    /// instead of running full-height.
    @State private var outlineRailContentHeight: CGFloat = 0
    @State private var carrelRailContentHeight: CGFloat = 0
    /// The view OWNS its context provider — the editable-surface registry holds
    /// it weakly, and the old single global slot deallocated it whenever any
    /// other view registered, silently unbinding this note from the assistant.
    @State private var ownedContextProvider: NoteContextProvider?
    @State private var backlinkPreviews: [NoteBacklinkPreview] = []
    @State private var mentionedInCounts: [AtomType: Int] = [:]
    @State private var textAnalysis: NoteFocusTextAnalysis = .empty
    @State private var textAnalysisTask: Task<Void, Never>?
    @State private var bodyHeadingOutline: [RichHeadingOutlineEntry] = []
    @State private var bodyNavigationTargetID: UUID?
    @State private var saveGeneration: Int = 0
    @State private var lastRichCheckpointAt: Date?

    // V2 block editor + per-document style
    @State private var noteStyle: NoteDocumentStyle = .default
    @State private var styleMenuPresented = false
    /// Increments on every paper-tone pick; restarts the bloom pulse via .id.
    @State private var paperBloomTrigger = 0
    @State private var bodyFocusCoordinator = BlockFocusCoordinator()

    private let database = CosmoDatabase.shared
    private let autoSaveDelay: TimeInterval = 0.5
    private let autosavePolicy = NoteAutosavePolicy()

    /// Chrome recede — toolbar fades while the user is actively writing (iA pattern).
    @State private var isActivelyTyping = false
    @State private var typingActivityTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let titleStyle = SharedTitleSurfaceStyle.noteFocus

    private var focusBackground: Color { DS.usesImmersiveFocusAppearance ? DS.focusImmersiveBackground : DS.documentBackground }
    private var focusSurface: Color { DS.usesImmersiveFocusAppearance ? DS.focusImmersiveSurface : DS.documentSurface }
    private var focusText: Color { DS.usesImmersiveFocusAppearance ? DS.focusImmersiveText : DS.documentText }
    private var focusTextSecondary: Color { DS.usesImmersiveFocusAppearance ? DS.focusImmersiveTextSecondary : DS.documentTextSecondary }
    private var focusTextMuted: Color { DS.usesImmersiveFocusAppearance ? DS.focusImmersiveTextMuted : DS.documentTextMuted }
    private var focusBorder: Color { DS.usesImmersiveFocusAppearance ? DS.focusImmersiveBorder : DS.documentBorder }

    @Environment(\.isPaneContext) private var isPaneContext
    @Environment(\.isPeekContext) private var isPeekContext
    @Environment(\.isPaneContextOwner) private var isPaneContextOwner
    @Environment(\.atomWindowChromeContext) private var atomChrome

    enum SaveState: Equatable {
        case idle
        case saving
        case saved
    }

    private var titleFontSize: CGFloat { titleStyle.fontSize }

    private var titleMinHeight: CGFloat { titleStyle.minimumHeight }

    private var titlePreviewMaxHeight: CGFloat { titleStyle.previewMaxHeight }

    private var titleEditingMaxHeight: CGFloat { titleStyle.editingMaxHeight }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Warm parchment background with a faint sepia wash at the edges
            backgroundSurface
                .ignoresSafeArea()
                .overlay {
                    FocusModeEditorBlurTapLayer()
                        .ignoresSafeArea()
                }

            // Main three-rail layout — the toolbar floats as an overlay so the
            // manuscript scrolls under its glass; the rails (glass themselves)
            // stay clear of it to avoid glass-on-glass.
            HStack(alignment: .top, spacing: 0) {
                if showsLeftRail {
                    outlineRail
                        .frame(width: 208)
                        .padding(.leading, DS.space16)
                        .padding(.top, noteToolbarClearance)
                        .padding(.bottom, DS.space16)
                        .opacity(railRestOpacity)
                        .onHover { hovering in
                            if hovering { wakeChrome() }
                        }
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                centerColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showsRightRail {
                    carrelRail
                        .frame(width: 272)
                        .padding(.trailing, DS.space16)
                        .padding(.top, noteToolbarClearance)
                        .padding(.bottom, DS.space16)
                        .opacity(railRestOpacity)
                        .onHover { hovering in
                            if hovering { wakeChrome() }
                        }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : ProMotionSprings.gentle, value: isActivelyTyping)
            .overlay(alignment: .top) {
                topBar
            }

            // Persistent floating blocks overlay
            GeometryReader { geo in
                FocusFloatingBlocksLayer(manager: floatingBlocksManager)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .background(
            // Hidden keyboard shortcut button (rule 10: macOS shortcuts for primary actions)
            Button("Toggle panels") { togglePanels() }
                .keyboardShortcut("\\", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        )
        .focusBlockContextMenu(
            manager: floatingBlocksManager,
            ownerAtomUUID: atom.uuid
        )
        .focusBlockInspector(manager: floatingBlocksManager)
        .cosmoSurfaceKeyWindowActivation(surfaceID: "note:\(atom.uuid)")
        .focusImmersiveEntryTransition()
        .onAppear {
            AtomRepository.shared.acquireEditingLock(uuid: atom.uuid)
            startEditingLockRefresh()
            restoreDeadLetterIfNeeded()
            startObservingAtom()
            loadLinkedAtoms()
            listenForAtomPicker()
            titleEditorHeight = titleMinHeight
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(ProMotionSprings.cardEntrance) {
                    contentAppeared = true
                }
            }
            // Register context provider for global Cosmo window
            let provider = NoteContextProvider(
                atom: atom,
                titleRef: { [self] in self.titlePlainText },
                contentRef: { [self] in self.plainContent },
                tagsRef: { [self] in self.tags },
                selectedTextRef: { [self] in self.selectedText },
                applyBodyEdit: { [self] operation in
                    try await self.applyInlineAssistantBodyEdit(operation)
                }
            )
            if !isPaneContext || isPaneContextOwner {
                ownedContextProvider = provider
                CosmoWindowViewModel.shared.updateContext(provider: provider)
            }
            // Safety fallback: ensure isInitialLoad clears even if GRDB observation
            // never fires (e.g. atom deleted between load and observation start)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if isInitialLoad {
                    isInitialLoad = false
                }
            }
        }
        .onChange(of: isPaneContextOwner) { _, isOwner in
            if isOwner {
                let provider = NoteContextProvider(
                    atom: atom,
                    titleRef: { [self] in self.titlePlainText },
                    contentRef: { [self] in self.plainContent },
                    tagsRef: { [self] in self.tags },
                    selectedTextRef: { [self] in self.selectedText },
                    applyBodyEdit: { [self] operation in
                        try await self.applyInlineAssistantBodyEdit(operation)
                    }
                )
                ownedContextProvider = provider
                CosmoWindowViewModel.shared.updateContext(provider: provider)
            }
        }
        .onReceive(CosmoInlineAssistantStore.shared.$proposals) { proposals in
            let surfaceID = "note:\(atom.uuid)"
            bodyReviewProposal = proposals.last { proposal in
                proposal.surfaceID == surfaceID && proposal.hasReviewableOperations
            }
        }
        .onDisappear {
            NoteFocusLog.debug("[FOCUS-NOTE] onDisappear — uuid=\(atom.uuid) titleLen=\(titlePlainText.count) bodyLen=\(plainContent.count) bodyPreview=\"\(String(plainContent.prefix(80)))\"")
            autoSaveTask?.cancel()
            textAnalysisTask?.cancel()
            stopEditingLockRefresh()
            observationCancellable?.cancel()
            // Defer save by one frame so CosmoDocumentEditor's flushPendingSync()
            // can propagate the latest text via onDocumentChange first.
            DispatchQueue.main.async {
                NoteFocusLog.debug("[FOCUS-NOTE] onDisappear(deferred) — saving uuid=\(atom.uuid) bodyLen=\(plainContent.count) bodyPreview=\"\(String(plainContent.prefix(80)))\"")
                saveClosed = true
                saveAtomImmediately()
                floatingBlocksManager.saveImmediately()
                AtomRepository.shared.releaseEditingLock(uuid: atom.uuid)
                // Mirror any local-only note images to the shared bucket so
                // they render on iPhone. Runs after the close save, off the
                // editing path — idempotent once every image has a remoteURL.
                let uuid = atom.uuid
                Task { await ImageStore.hydrateNoteImages(uuid: uuid) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmoAppWillTerminate)) { _ in
            autoSaveTask?.cancel()
            textAnalysisTask?.cancel()
            stopEditingLockRefresh()
            saveClosed = true
            saveAtomImmediately()
            AtomRepository.shared.releaseEditingLock(uuid: atom.uuid)
        }
        .onReceive(NotificationCenter.default.publisher(for: .blurAllBlocks)) { _ in
            isEditingTitle = false
        }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .sheet(isPresented: $showTagEditor) {
            TagEditorSheet(tags: $tags)
        }
        .onChange(of: noteStyle) { _, _ in
            guard !isInitialLoad else { return }
            hasLocalMetaEdits = true
            triggerAutoSave()
        }
        .onChange(of: tags) { _, newTags in
            // Tag edits were never autosaved — they only reached the DB if some
            // other field happened to save afterwards. Skip the echo case where
            // the observation just applied the persisted tags.
            guard !isInitialLoad, newTags != lastPersistedTags else { return }
            hasLocalMetaEdits = true
            triggerAutoSave()
        }
        .onChange(of: isEditingTitle) { _, isEditing in
            if isEditing {
                if titleChromeModeAtEditStart == nil {
                    titleChromeModeAtEditStart = liveTitleChromeMode
                }
                titleDocumentAtEditStart = titleDocument
                pendingObservedTitleDocument = nil
                titleEditorHeight = min(titleEditingMaxHeight, max(titleMinHeight, titleEditorHeight))
            } else {
                if let pendingObservedTitleDocument, titleDocument == titleDocumentAtEditStart {
                    applyObservedTitleDocument(pendingObservedTitleDocument)
                }
                pendingObservedTitleDocument = nil
                titleChromeModeAtEditStart = nil
            }
        }
    }

    // MARK: - V2 Derived state

    private var showsLeftRail: Bool {
        leftRailVisible && !typewriterMode && !isPaneContext
    }

    private var showsRightRail: Bool {
        rightRailVisible && !typewriterMode
    }

    /// Rails whisper while the user is writing and wake on hover.
    private var railRestOpacity: Double {
        isActivelyTyping ? MarginaliaRailPolicy.whisperOpacity : 1
    }

    /// The heading section the focused block sits under — lights its outline row.
    private var activeBodyHeadingID: UUID? {
        guard let focusedID = bodyFocusCoordinator.focusedBlockID,
              let index = bodyDocument.blocks.firstIndex(where: { $0.id == focusedID })
        else { return nil }
        return bodyHeadingOutline.last(where: { $0.blockIndex <= index })?.id
    }

    private var isEmptyNote: Bool {
        titleChromeMode == .emptyEditableTitle
    }

    private var titleChromeMode: NoteFocusTitleChromeMode {
        NoteFocusHeaderLayoutPolicy.chromeMode(
            titlePlainText: titlePlainText,
            plainContent: plainContent,
            activeEditChromeMode: isEditingTitle ? titleChromeModeAtEditStart : nil
        )
    }

    private var liveTitleChromeMode: NoteFocusTitleChromeMode {
        NoteFocusHeaderLayoutPolicy.chromeMode(
            titlePlainText: titlePlainText,
            plainContent: plainContent
        )
    }

    private var estimatedReadingMinutes: Int {
        textAnalysis.estimatedReadingMinutes
    }

    private var inLinkCount: Int { backlinkPreviews.count }

    private var outLinkCount: Int {
        textAnalysis.outLinkCount
    }

    // MARK: - Background Surface

    private var backgroundSurface: some View {
        ZStack {
            // Per-note paper: the tone replaces the theme surface wholesale
            // so the whole page — margins included — reads as one sheet.
            if let paper = noteStyle.paperTone.pageColor(darkMode: DS.usesImmersiveFocusAppearance) {
                paper
            } else {
                focusBackground
            }
            // Subtle vignette that darkens edges to emphasize the center column
            RadialGradient(
                colors: [Color.clear, DS.inkWash.opacity(0.04)],
                center: .center,
                startRadius: 360,
                endRadius: 900
            )
            .blendMode(.multiply)
            // Picking a paper tone blooms a wash of light from the Aa corner —
            // the page's one earned delight. Reduce Motion keeps the crossfade.
            if paperBloomTrigger > 0 {
                PaperToneBloomPulse(darkMode: DS.usesImmersiveFocusAppearance)
                    .id(paperBloomTrigger)
            }
        }
        .animation(reduceMotion ? nil : ProMotionSprings.gentle, value: noteStyle.paperTone)
        .onChange(of: noteStyle.paperTone) { _, _ in
            guard !isInitialLoad, !reduceMotion else { return }
            paperBloomTrigger += 1
        }
    }

    // MARK: - Top Bar (V2)

    @ViewBuilder
    private var topBar: some View {
        if let atomChrome {
            atomWindowTopBar(atomChrome)
        } else {
            nativeFocusTopBar
        }
    }

    private func atomWindowTopBar(_ atomChrome: AtomWindowChromePayload) -> some View {
        // Chrome islands on the shared baseline — nav (window controls) · view
        // controls · actions — never a full-width bar. Same island grammar as the
        // Content workspace toolbar (CosmoChromeRow / CosmoChromeIsland). The
        // center island stays truly centered regardless of the side islands' width.
        CosmoChromeRow(insetsEnabled: false) {
            CosmoChromeIsland {
                AtomWindowChromeLeadingControls(context: atomChrome)
                if saveState != .idle {
                    noteSaveBadge
                        .transition(.opacity)
                }
            }
        } center: {
            CosmoChromeIsland { atomViewControlsCluster }
        } trailing: {
            CosmoChromeIsland {
                AtomWindowChromeTrailingControls(context: atomChrome)
            }
        }
        // Finite chrome height — the Atom window bar must never stretch with
        // its islands' content (see AtomWindowMetrics).
        .frame(height: AtomWindowMetrics.focusToolbarHeight)
        .padding(.horizontal, DS.space16)
        .padding(.top, DS.space12)
        .padding(.bottom, DS.space8)
        .opacity(isActivelyTyping ? 0.25 : 1)
        .animation(reduceMotion ? nil : ProMotionSprings.gentle, value: isActivelyTyping)
        .onHover { hovering in
            if hovering { wakeChrome() }
        }
    }

    private var nativeFocusTopBar: some View {
        // Chrome islands on the shared baseline — nav + identity · tools — never a
        // full-width bar. Same island grammar as the Content workspace toolbar
        // (CosmoChromeRow / CosmoChromeIsland): glass hugs each control group.
        CosmoChromeRow(insetsEnabled: false) {
            CosmoChromeIsland {
                if !isPaneContext {
                    backButton
                }
                noteTypeBadge
                if saveState != .idle {
                    noteSaveBadge
                        .transition(.opacity)
                }
            }
        } center: {
            EmptyView()
        } trailing: {
            CosmoChromeIsland { topBarChromeButtons }
        }
        .background(FocusModeEditorBlurTapLayer())
        .padding(.horizontal, DS.space16)
        .padding(.top, DS.space12)
        .padding(.bottom, DS.space8)
        .opacity(isActivelyTyping ? 0.25 : 1)
        .animation(reduceMotion ? nil : ProMotionSprings.gentle, value: isActivelyTyping)
        .onHover { hovering in
            if hovering { wakeChrome() }
        }
    }

    private var backButton: some View {
        // No inner capsule — the enclosing CosmoChromeIsland provides the glass.
        Button(action: onClose) {
            HStack(spacing: DS.space6) {
                Image(systemName: "chevron.left")
                    .font(DS.buttonText)
                    .accessibilityLabel("Back")
                Text("Back")
                    .font(DS.callout)
            }
            .foregroundStyle(focusTextSecondary)
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Back (Esc)")
    }

    private var noteTypeBadge: some View {
        // Note identity + vitals as tinted text on the leading island — no inner
        // capsule; the enclosing CosmoChromeIsland provides the glass.
        HStack(spacing: DS.space6) {
            Image(systemName: "note.text")
                .font(DS.caption2)
                .accessibilityLabel("Note")
            Text("NOTE")
                .font(DS.smallCaps)
            if !isEmptyNote {
                Text("·")
                    .foregroundStyle(focusTextMuted)
                Text("\(wordCount) words · \(estimatedReadingMinutes) min")
                    .font(DS.caption)
                    .foregroundStyle(focusTextMuted)
            }
        }
        .foregroundStyle(DS.entityNote)
    }

    private var topBarChromeButtons: some View {
        HStack(spacing: DS.space8) {
            styleMenuButton
            if isPaneContext, !isPeekContext, atomChrome == nil {
                chromeIconButton(
                    systemName: "xmark",
                    isActive: false,
                    tint: focusTextMuted,
                    help: "Close",
                    accessibilityLabel: "Close note",
                    action: onClose
                )
            }
        }
    }

    /// The center pill of the Atom window bar: the page-style control. Same
    /// flat capsule language as the leading/trailing clusters
    /// (`atomWindowChromeCluster`) so all three read as one material family.
    private var atomViewControlsCluster: some View {
        HStack(spacing: DS.space4) {
            styleMenuButton
        }
        .atomWindowChromeCluster()
    }

    /// "Aa" — the page's whole personality: text voice (font, size, width,
    /// spacing) and page character (paper, icon, cover, panels), per-note.
    private var styleMenuButton: some View {
        chromeIconButton(
            systemName: "textformat",
            isActive: styleMenuPresented || noteStyle != .default,
            tint: DS.accent,
            help: "Page style",
            accessibilityLabel: "Page style",
            action: { styleMenuPresented.toggle() }
        )
        .popover(isPresented: $styleMenuPresented, arrowEdge: .bottom) {
            NotePageStylePopover(
                style: $noteStyle,
                typewriterMode: $typewriterMode,
                paragraphFocus: $paragraphFocus,
                leftRailVisible: $leftRailVisible,
                rightRailVisible: $rightRailVisible
            )
        }
    }

    private func chromeIconButton(
        systemName: String,
        isActive: Bool,
        tint: Color,
        help: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        NoteChromeIconButton(
            systemName: systemName,
            isActive: isActive,
            tint: tint,
            inactiveColor: focusTextMuted,
            hoverFill: focusBorder.opacity(0.3),
            help: help,
            accessibilityLabel: accessibilityLabel,
            action: action
        )
    }

    // MARK: - Center Column

    /// Clearance the manuscript reserves at rest so it starts below the floating
    /// toolbar — but slides *under* the glass once scrolling.
    private var noteToolbarClearance: CGFloat { 76 }

    /// The block column = reading measure + the block gutter (＋ / ⋮⋮ controls).
    /// Title and metadata are inset by the gutter so all text shares one left edge.
    private var bodyColumnWidth: CGFloat {
        noteStyle.pageWidth.readingWidth + BlockInteractionPolicy.gutterWidth
    }

    /// Click in the empty space below the last block to keep writing — focuses
    /// the tail paragraph, creating one if the document ends with something else.
    private var bodyTailClickCatcher: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(minHeight: 160)
            .contentShape(Rectangle())
            .onTapGesture { focusDocumentTail() }
    }

    private func focusDocumentTail() {
        if let last = bodyDocument.blocks.last,
           last.kind.isTextEditableBlock,
           last.plainInlineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            bodyFocusCoordinator.focus(last.id)
            return
        }
        let paragraph = RichBlock.paragraph("")
        bodyDocument.blocks.append(paragraph)
        handleBodyDocumentChange(bodyDocument, plainText: bodyDocument.plainText)
        bodyFocusCoordinator.focus(paragraph.id)
    }

    private var centerColumn: some View {
        centerScroll
            .scrollEdgeEffectStyle(.soft, for: .top)
            .contentMargins(.top, noteToolbarClearance, for: .scrollContent)
    }

    /// Cover band + page icon — the page's personality, above the title,
    /// scrolling with the manuscript. Inset and rounded so it reads as part
    /// of the sheet, concentric with the page's card radii.
    @ViewBuilder
    private var pageIdentityHeader: some View {
        if noteStyle.cover != .none {
            NotePageCoverBand(style: noteStyle, darkMode: DS.usesImmersiveFocusAppearance)
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
                .frame(maxWidth: bodyColumnWidth)
                .padding(.top, DS.space8)
        }
        if let pageIcon = noteStyle.pageIcon {
            NotePageIconView(
                icon: pageIcon,
                style: noteStyle,
                darkMode: DS.usesImmersiveFocusAppearance,
                size: 30
            )
            .padding(.leading, BlockInteractionPolicy.gutterWidth)
            .frame(maxWidth: bodyColumnWidth, alignment: .leading)
            .padding(.top, noteStyle.cover != .none ? DS.space12 : DS.space24)
            .help("Page icon")
        }
    }

    private var centerScroll: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                pageIdentityHeader
                    .animation(reduceMotion ? nil : ProMotionSprings.gentle, value: noteStyle.cover)
                if isEmptyNote {
                    NoteFocusEmptyStateView {
                        titleSection
                    }
                        .padding(.top, DS.space48)
                        .frame(maxWidth: CosmoTypography.optimalReadingWidth)
                } else {
                    titleSection
                        .padding(.leading, BlockInteractionPolicy.gutterWidth)
                        .frame(maxWidth: bodyColumnWidth, alignment: .leading)
                        .padding(.top, DS.space36)
                        .opacity(headerFocusOpacity)
                    dateTagsRow
                        .padding(.leading, BlockInteractionPolicy.gutterWidth)
                        .frame(maxWidth: bodyColumnWidth, alignment: .leading)
                        .padding(.top, DS.space12)
                        .padding(.bottom, DS.space24)
                        .opacity(headerFocusOpacity)
                    if NoteFocusHeaderLayoutPolicy.showsMetadataDivider(for: titleChromeMode) {
                        giltDivider
                            .opacity(headerFocusOpacity)
                    }
                }

                if let review = bodyReviewProposal {
                    CosmoInlineDiffReviewView(
                        store: CosmoInlineAssistantStore.shared,
                        proposal: review,
                        sourceText: plainContent,
                        bodyFont: .system(size: 17),
                        textColor: focusText
                    )
                    .padding(.leading, BlockInteractionPolicy.gutterWidth)
                    .frame(maxWidth: bodyColumnWidth, alignment: .topLeading)
                    .frame(minHeight: max(400, scrollViewportHeight - 200), alignment: .topLeading)
                    .padding(.top, isEmptyNote ? DS.space32 : DS.space24)
                    .padding(.bottom, DS.space48)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        BlockListView(
                            document: $bodyDocument,
                            fontSize: noteStyle.textSize.pointSize,
                            fontDesign: noteStyle.fontFamily.design,
                            lineSpacingAdjustment: noteStyle.lineSpacing.lineSpacingDelta,
                            blockGap: noteStyle.lineSpacing.blockGap,
                            dimsInactiveBlocks: paragraphFocus,
                            placeholder: "Write, or press / for blocks…",
                            darkMode: DS.usesImmersiveFocusAppearance,
                            overrideTextColor: NSColor(focusText),
                            allowSlashCommands: true,
                            allowMentions: true,
                            allowSelectionMenu: true,
                            allowImages: true,
                            typewriterMode: typewriterMode,
                            scrollsInternally: false,
                            editorTargetID: EditorCommandTarget.noteBody(atom.uuid),
                            navigationTargetID: bodyNavigationTargetID,
                            focusCoordinator: bodyFocusCoordinator,
                            onSelectionChanged: { snapshot in
                                selectedText = snapshot.text
                                let trimmed = snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines)
                                CosmoInlineAssistantStore.shared.reportSelection(
                                    trimmed.isEmpty ? nil : CosmoEditableSelection(text: trimmed, containingLine: nil),
                                    forSurfaceID: "note:\(atom.uuid)"
                                )
                                refreshCosmoContextIfActive()
                            },
                            onDocumentChange: handleBodyDocumentChange
                        )
                        bodyTailClickCatcher
                    }
                    .frame(maxWidth: bodyColumnWidth, alignment: .topLeading)
                    .frame(
                        minHeight: max(400, scrollViewportHeight - 200),
                        alignment: .topLeading
                    )
                    .padding(.top, isEmptyNote ? DS.space32 : DS.space24)
                    // Scroll past end — the last line can always sit at eye
                    // level instead of being pinned to the screen's bottom edge.
                    .padding(.bottom, max(DS.space48, scrollViewportHeight * 0.35))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DS.space40)
            .background(FocusModeEditorBlurTapLayer())
            .animation(reduceMotion ? nil : ProMotionSprings.gentle, value: headerFocusOpacity)
        }
        .background(FocusModeEditorBlurTapLayer())
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newValue in
            withoutImplicitAnimation {
                scrollViewportHeight = newValue
            }
        }
    }

    /// While paragraph focus is on and the caret lives in the body, the
    /// title block fades back with the rest of the page.
    private var headerFocusOpacity: Double {
        guard paragraphFocus,
              !isEditingTitle,
              bodyFocusCoordinator.focusedBlockID != nil else { return 1 }
        return 0.4
    }

    private var giltDivider: some View {
        HStack(spacing: DS.space12) {
            Rectangle()
                .fill(DS.gilt.opacity(0.3))
                .frame(height: 0.5)
            Image(systemName: "diamond.fill")
                .font(DS.caption2)
                .foregroundStyle(DS.gilt.opacity(0.5))
                .accessibilityHidden(true)
            Rectangle()
                .fill(DS.gilt.opacity(0.3))
                .frame(height: 0.5)
        }
        .frame(maxWidth: CosmoTypography.optimalReadingWidth * 0.6)
    }

    // MARK: - Outline Rail (left)

    private var outlineRail: some View {
        railPanel(contentHeight: $outlineRailContentHeight) {
            noteOutlineSection
            noteLinksSection
            if !tags.isEmpty {
                noteTagsSection
            }
        }
    }

    /// A study rail: glass, top-aligned, hugging its content instead of
    /// running the full window height — the parchment breathes around it.
    private func railPanel<Content: View>(
        contentHeight: Binding<CGFloat>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.space20) {
                content()
            }
            .padding(.horizontal, DS.space20)
            .padding(.vertical, DS.space20)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newValue in
                contentHeight.wrappedValue = newValue
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .vertical)
        .frame(
            maxHeight: contentHeight.wrappedValue > 0 ? contentHeight.wrappedValue : .infinity,
            alignment: .top
        )
        .cosmoGlassPanel(role: .focusSidebar, cornerRadius: 22)
        .animation(reduceMotion ? nil : ProMotionSprings.snappy, value: contentHeight.wrappedValue)
    }

    private var noteOutlineSection: some View {
        MarginaliaDisclosureSection(
            "ON THIS NOTE",
            countText: bodyHeadingOutline.isEmpty ? nil : "\(bodyHeadingOutline.count)",
            storageKey: "note.outline",
            defaultExpanded: true
        ) {
            if bodyHeadingOutline.isEmpty {
                Text(isEmptyNote ? "no headings yet" : "headings create sections")
                    .font(DS.dateSerif)
                    .italic()
                    .foregroundStyle(focusTextMuted.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: DS.space6) {
                    ForEach(bodyHeadingOutline) { entry in
                        outlineEntryRow(entry, isActive: entry.id == activeBodyHeadingID)
                    }
                }
            }
        }
    }

    private var noteLinksSection: some View {
        MarginaliaDisclosureSection(
            "LINKS",
            countText: "\(inLinkCount + outLinkCount)",
            storageKey: "note.links"
        ) {
            VStack(alignment: .leading, spacing: DS.space4) {
                linkCountRow(label: "backlinks", count: inLinkCount, tint: DS.gilt)
                linkCountRow(label: "out links", count: outLinkCount, tint: DS.entityNote)
            }
        }
    }

    private var noteTagsSection: some View {
        MarginaliaDisclosureSection(
            "TAGS",
            countText: "\(tags.count)",
            storageKey: "note.tags"
        ) {
            FlowTagCloud(tags: tags)
        }
    }

    private func outlineEntryRow(_ entry: RichHeadingOutlineEntry, isActive: Bool) -> some View {
        Button {
            navigateToBodyHeading(entry)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: DS.space6) {
                if isActive {
                    Rectangle()
                        .fill(DS.gilt)
                        .frame(width: 3, height: 3)
                        .rotationEffect(.degrees(45))
                        .frame(width: 10, alignment: .leading)
                } else {
                    Text(entry.level == 1 ? "¶" : "›")
                        .font(DS.caption2)
                        .foregroundStyle(DS.gilt.opacity(0.6))
                        .frame(width: 10, alignment: .leading)
                }
                Text(entry.title)
                    .font(entry.level == 1 ? DS.subheadline : DS.caption)
                    .foregroundStyle(isActive ? focusText : (entry.level == 1 ? focusTextSecondary : focusTextMuted))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(entry.level - 1) * DS.space8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .animation(ProMotionSprings.gentle, value: isActive)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func linkCountRow(label: String, count: Int, tint: Color) -> some View {
        HStack(spacing: DS.space6) {
            Text("\(count)")
                .font(DS.callout)
                .foregroundStyle(count > 0 ? tint : focusTextMuted)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(DS.caption)
                .foregroundStyle(focusTextMuted)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Carrel Rail (right)

    private var carrelRail: some View {
        railPanel(contentHeight: $carrelRailContentHeight) {
            backlinksSection
            mentionedInSection
            resonanceSection
            askCosmoSection
        }
    }

    private var backlinksSection: some View {
        MarginaliaDisclosureSection(
            "BACKLINKS",
            countText: "\(inLinkCount)",
            storageKey: "note.backlinks",
            defaultExpanded: true
        ) {
            if backlinkPreviews.isEmpty {
                Text("no backlinks yet")
                    .font(DS.dateSerif)
                    .italic()
                    .foregroundStyle(focusTextMuted.opacity(0.7))
            } else {
                VStack(spacing: DS.space8) {
                    ForEach(Array(backlinkPreviews.prefix(8).enumerated()), id: \.element.atomUUID) { index, preview in
                        BacklinkCardView(preview: preview)
                            .transition(.opacity.combined(with: .offset(y: 4)))
                            .animation(ProMotionSprings.staggered(index: index), value: backlinkPreviews.count)
                    }
                }
            }
        }
    }

    private var mentionedInSection: some View {
        MarginaliaDisclosureSection(
            "MENTIONED IN",
            countText: mentionedInTotal > 0 ? "\(mentionedInTotal)" : nil,
            storageKey: "note.mentions",
            spacing: DS.space8
        ) {
            if mentionedInTotal == 0 {
                Text("not yet referenced")
                    .font(DS.dateSerif)
                    .italic()
                    .foregroundStyle(focusTextMuted.opacity(0.7))
            } else {
                VStack(alignment: .leading, spacing: DS.space4) {
                    ForEach(Array(mentionedInCounts.keys.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { type in
                        if let count = mentionedInCounts[type], count > 0 {
                            HStack(spacing: DS.space6) {
                                Image(systemName: type.iconName)
                                    .font(DS.caption2)
                                    .foregroundStyle(focusTextSecondary)
                                    .accessibilityLabel(type.displayName)
                                Text("\(count) \(type.pluralDisplayName.lowercased())")
                                    .font(DS.caption)
                                    .foregroundStyle(focusTextSecondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var mentionedInTotal: Int {
        mentionedInCounts.values.reduce(0, +)
    }

    private var resonanceSection: some View {
        MarginaliaDisclosureSection(
            "RESONANCE",
            countText: resonantThemes.isEmpty ? nil : "\(resonantThemes.count)",
            storageKey: "note.resonance",
            spacing: DS.space8
        ) {
            if resonantThemes.isEmpty {
                Text("tag this note to surface resonances")
                    .font(DS.dateSerif)
                    .italic()
                    .foregroundStyle(focusTextMuted.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: DS.space4) {
                    ForEach(resonantThemes, id: \.self) { theme in
                        HStack(spacing: DS.space6) {
                            Image(systemName: "sparkle")
                                .font(DS.caption2)
                                .foregroundStyle(DS.gilt.opacity(0.7))
                                .accessibilityHidden(true)
                            Text(theme)
                                .font(DS.caption)
                                .foregroundStyle(focusText)
                                .italic()
                        }
                    }
                }
            }
        }
    }

    private var resonantThemes: [String] {
        // Lightweight local resonance: derived from tags + first-line themes.
        // (Deeper embedding-based resonance lives in HybridSearchEngine — future pass.)
        let tagThemes = tags.prefix(3).map { $0 }
        return Array(tagThemes)
    }

    private var askCosmoSection: some View {
        Button {
            openCosmoWithNoteContext()
        } label: {
            HStack(spacing: DS.space8) {
                Image(systemName: "sparkles")
                    .font(DS.callout)
                    .foregroundStyle(DS.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask Cosmo")
                        .font(DS.subheadline.weight(.semibold))
                        .foregroundStyle(focusText)
                    Text("scoped to this note + backlinks")
                        .font(DS.caption2)
                        .foregroundStyle(focusTextMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(DS.caption2)
                    .foregroundStyle(focusTextMuted)
                    .accessibilityHidden(true)
            }
            .padding(DS.space12)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .fill(DS.accent.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusMedium)
                            .stroke(DS.accent.opacity(0.2), lineWidth: 0.5)
                    )
            )
            .clipShape(.rect(cornerRadius: DS.radiusMedium))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask Cosmo about this note")
    }

    // MARK: - Actions

    private func withoutImplicitAnimation(_ updates: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            updates()
        }
    }

    private func togglePanels() {
        withAnimation(ProMotionSprings.sidebar) {
            let anyVisible = leftRailVisible || rightRailVisible
            if anyVisible {
                leftRailVisible = false
                rightRailVisible = false
            } else {
                leftRailVisible = true
                rightRailVisible = true
            }
        }
    }

    private func openCosmoWithNoteContext() {
        let provider = NoteContextProvider(
            atom: atom,
            titleRef: { [self] in self.titlePlainText },
            contentRef: { [self] in self.plainContent },
            tagsRef: { [self] in self.tags },
            selectedTextRef: { [self] in self.selectedText },
            applyBodyEdit: { [self] operation in
                try await self.applyInlineAssistantBodyEdit(operation)
            }
        )
        ownedContextProvider = provider
        CosmoWindowViewModel.shared.updateContext(provider: provider)
        // One Cosmo: the floating chat window is gone — open the assistant
        // pane scoped to this note.
        CosmoInlineAssistantStore.shared.openPane(forSurfaceID: provider.surfaceID)
    }

    private func refreshCosmoContextIfActive() {
        CosmoWindowViewModel.shared.refreshContextIfCurrentAtomMatches(atomUUID: atom.uuid)
    }

    private func handleBodyPlainTextChange(_ plainText: String) {
        let changed = NoteAutosaveChangePolicy.shouldAutosaveTextChange(
            isInitialLoad: isInitialLoad,
            didChange: plainText != plainContent
        )
        guard changed || plainText != plainContent else { return }

        NoteFocusLog.debug("[FOCUS-NOTE] onPlainTextChange(body) — changed=\(changed) len=\(plainText.count) isInitialLoad=\(isInitialLoad) uuid=\(atom.uuid)")
        plainContent = plainText
        refreshCosmoContextIfActive()
        scheduleTextAnalysis(for: plainText)

        if changed {
            hasLocalBodyEdits = true
            registerTypingActivity()
            triggerAutoSave()
        }
    }

    private func handleBodyDocumentChange(_ document: RichDocument, plainText: String) {
        let changed = NoteAutosaveChangePolicy.shouldAutosaveDocumentChange(
            isInitialLoad: isInitialLoad,
            previousDocument: bodyDocument,
            nextDocument: document,
            previousPlainText: plainContent,
            nextPlainText: plainText
        )
        NoteFocusLog.debug("[FOCUS-NOTE] onDocumentChange(body) — changed=\(changed) len=\(plainText.count) isInitialLoad=\(isInitialLoad) uuid=\(atom.uuid)")
        if changed {
            // Typing is the strongest "this is what I'm working on" signal.
            CosmoEditableSurfaceRegistry.shared.activateIfNeeded(surfaceID: "note:\(atom.uuid)")
        }
        bodyDocument = document
        plainContent = plainText
        updateBodyHeadingOutline(from: document)
        refreshCosmoContextIfActive()
        scheduleTextAnalysis(for: plainText)

        if changed {
            hasLocalBodyEdits = true
            registerTypingActivity()
            triggerAutoSave()
        }
    }

    // MARK: - Chrome Recede

    /// Marks the user as actively writing; chrome fades until typing pauses
    /// (~1.4s) or the pointer touches the toolbar.
    private func registerTypingActivity() {
        isActivelyTyping = true
        typingActivityTask?.cancel()
        typingActivityTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            isActivelyTyping = false
        }
    }

    private func wakeChrome() {
        typingActivityTask?.cancel()
        isActivelyTyping = false
    }

    // MARK: - Text Analysis

    private func scheduleTextAnalysis(for text: String) {
        textAnalysisTask?.cancel()
        textAnalysisTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(180))
            } catch {
                return
            }

            let analysis = await Task.detached(priority: .utility) {
                NoteFocusTextAnalysis.analyze(text)
            }.value

            guard !Task.isCancelled else { return }
            await MainActor.run {
                if plainContent == text {
                    textAnalysis = analysis
                }
            }
        }
    }

    private func updateTextAnalysisImmediately(for text: String) {
        textAnalysisTask?.cancel()
        textAnalysis = NoteFocusTextAnalysis.analyze(text)
    }

    private func updateBodyHeadingOutline(from document: RichDocument) {
        let outline = RichDocumentHeadings.outline(in: document)
        // Runs per keystroke now (immediate block sync) — skip the state write
        // when nothing changed so the outline rail doesn't re-render.
        if outline != bodyHeadingOutline {
            bodyHeadingOutline = outline
        }
    }

    private func navigateToBodyHeading(_ entry: RichHeadingOutlineEntry) {
        bodyNavigationTargetID = nil
        DispatchQueue.main.async {
            bodyNavigationTargetID = entry.id
        }
    }

    // MARK: - Title Section

    private var titlePlaceholder: String {
        titleChromeMode == .emptyEditableTitle ? "Untitled note" : "Untitled Note"
    }

    private var titleTextAlignment: TextAlignment {
        titleChromeMode == .emptyEditableTitle ? .center : titleStyle.swiftUITextAlignment
    }

    private var titleNSTextAlignment: NSTextAlignment {
        titleChromeMode == .emptyEditableTitle ? .center : titleStyle.textAlignment
    }

    private var titleFrameAlignment: Alignment {
        titleChromeMode == .emptyEditableTitle ? .top : .topLeading
    }

    private var titleUnderlineAlignment: Alignment {
        titleChromeMode == .emptyEditableTitle ? .center : .leading
    }

    private var titleUnderlineVisualProgress: CGFloat {
        titleChromeMode == .emptyEditableTitle ? max(titleUnderlineProgress, 0.28) : titleUnderlineProgress
    }

    private var titleSectionMaxWidth: CGFloat {
        titleChromeMode == .emptyEditableTitle ? 420 : CosmoTypography.optimalReadingWidth
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if isEditingTitle {
                    CosmoDocumentEditor(
                        document: $titleDocument,
                        fontSize: titleFontSize,
                        compact: titleStyle.compact,
                        placeholder: titlePlaceholder,
                        darkMode: DS.usesImmersiveFocusAppearance,
                        overrideTextColor: NSColor(focusText),
                        allowSlashCommands: false,
                        allowMentions: true,
                        allowSelectionMenu: false,
                        allowImages: false,
                        titleConfiguration: titleStyle.titleConfiguration,
                        baseFontWeight: titleStyle.baseFontWeight,
                        scrollsInternally: false,
                        textAlignment: titleNSTextAlignment,
                        onContentHeightChange: { newHeight in
                            let nextHeight = min(titleEditingMaxHeight, max(titleMinHeight, newHeight))
                            if EditorHeightUpdatePolicy.shouldPublish(current: titleEditorHeight, next: nextHeight) {
                                titleEditorHeight = nextHeight
                            }
                        },
                        onPlainTextChange: { plainText in
                            titlePlainText = plainText
                            refreshCosmoContextIfActive()
                            withAnimation(ProMotionSprings.bouncy) {
                                titleUnderlineProgress = plainText.isEmpty ? 0.28 : 1
                            }
                        },
                        onStructuredDocumentChange: { document, plainText in
                            let changed = NoteAutosaveChangePolicy.shouldAutosaveDocumentChange(
                                isInitialLoad: isInitialLoad,
                                previousDocument: titleDocument,
                                nextDocument: document,
                                previousPlainText: titlePlainText,
                                nextPlainText: plainText
                            )
                            NoteFocusLog.debug("[FOCUS-NOTE] onDocumentChange(title) — len=\(plainText.count) preview=\"\(String(plainText.prefix(60)))\" isInitialLoad=\(isInitialLoad) uuid=\(atom.uuid)")
                            titleDocument = document
                            titlePlainText = plainText
                            refreshCosmoContextIfActive()
                            withAnimation(ProMotionSprings.bouncy) {
                                titleUnderlineProgress = plainText.isEmpty ? 0.28 : 1
                            }
                            if changed {
                                hasLocalMetaEdits = true
                                triggerAutoSave()
                            }
                        },
                        onActivate: { isEditingTitle = true },
                        onDeactivate: { isEditingTitle = false },
                        onCommit: { isEditingTitle = false },
                        autoFocus: true
                    )
                    .frame(height: min(titleEditingMaxHeight, max(titleMinHeight, titleEditorHeight)))
                } else {
                    Text(titlePlainText.isEmpty ? titlePlaceholder : titlePlainText)
                        .font(titleStyle.swiftUIFont)
                        .foregroundStyle(titlePlainText.isEmpty ? focusTextMuted : focusText)
                        .lineLimit(titleStyle.previewLineLimit)
                        .truncationMode(.tail)
                        .multilineTextAlignment(titleTextAlignment)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: titleMinHeight, alignment: titleFrameAlignment)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            titleDocumentAtEditStart = titleDocument
                            titleChromeModeAtEditStart = liveTitleChromeMode
                            isEditingTitle = true
                        }
                }
            }

            // Animated underline
            if NoteFocusHeaderLayoutPolicy.showsTitleUnderline(for: titleChromeMode) {
                GeometryReader { geo in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    DS.entityNote.opacity(titleUnderlineVisualProgress * 0.8),
                                    DS.entityNote.opacity(titleUnderlineVisualProgress * 0.4),
                                    DS.entityNote.opacity(0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * max(0.16, titleUnderlineVisualProgress), height: 2)
                        .frame(maxWidth: .infinity, alignment: titleUnderlineAlignment)
                        .shadow(
                            color: DS.entityNote.opacity(titleUnderlineVisualProgress * 0.4),
                            radius: 4,
                            y: 2
                        )
                }
                .frame(height: 2)
            }
        }
        .frame(maxWidth: titleSectionMaxWidth, alignment: titleFrameAlignment)
        .opacity(contentAppeared ? 1 : 0)
        .offset(y: contentAppeared ? 0 : 12)
        .blur(radius: contentAppeared ? 0 : 4)
    }

    // MARK: - Date + Tags Row

    private var dateTagsRow: some View {
        HStack(spacing: 16) {
            // Date
            Text(createdAt, format: .dateTime.month(.wide).day().year())
                .font(DS.body)
                .foregroundStyle(focusTextSecondary)

            // Tags
            if !tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(DS.caption)
                            .foregroundStyle(focusTextSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(focusBorder, in: Capsule())
                    }
                    if tags.count > 3 {
                        Text("+\(tags.count - 3)")
                            .font(DS.caption)
                            .foregroundStyle(focusTextMuted)
                    }
                }
            }

            Button(action: {
                showTagEditor = true
            }) {
                HStack(spacing: DS.space4) {
                    Image(systemName: "tag")
                        .font(DS.footnote)
                        .symbolEffect(.bounce, value: showTagEditor)
                    Text(tags.isEmpty ? "Add tags" : "Edit")
                        .font(DS.caption)
                }
                .foregroundStyle(focusTextMuted)
                .padding(.horizontal, DS.space8)
                .padding(.vertical, DS.space4)
                .background(focusBorder, in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: CosmoTypography.optimalReadingWidth, alignment: .leading)
        .opacity(contentAppeared ? 1 : 0)
        .offset(y: contentAppeared ? 0 : 8)
        .animation(ProMotionSprings.staggered(index: 1), value: contentAppeared)
    }

    // MARK: - Save Badge

    private var noteSaveBadge: some View {
        HStack(spacing: 4) {
            Group {
                switch saveState {
                case .idle:
                    EmptyView()
                case .saving:
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .symbolEffect(.rotate, isActive: true)
                case .saved:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DS.entityNote)
                        .symbolEffect(.bounce, value: saveState == .saved)
                }
            }
            .font(DS.caption)

            Text(saveState == .saving ? "Saving..." : "Saved")
                .font(DS.caption)
        }
        .foregroundStyle(saveState == .saved ? DS.entityNote.opacity(0.85) : focusTextMuted)
        .contentTransition(.opacity)
        .animation(ProMotionSprings.gentle, value: saveState)
    }

    // MARK: - Computed Properties

    private var wordCount: Int {
        textAnalysis.wordCount
    }

    // MARK: - Sidebar Content

    private var noteSidebarContent: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            if linkedAtoms.isEmpty {
                Text("No linked items")
                    .font(DS.callout)
                    .foregroundStyle(focusTextMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, DS.space20)
            } else {
                Text("LINKED ITEMS")
                    .dsSectionLabel()

                ForEach(linkedAtoms, id: \.uuid) { linked in
                    HStack(spacing: DS.space8) {
                        Image(systemName: linked.type.iconName)
                            .font(DS.footnote)
                            .foregroundStyle(focusTextSecondary)

                        Text(linked.title ?? "Untitled")
                            .font(DS.subheadline)
                            .foregroundStyle(focusText)
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(.vertical, DS.space4)
                }
            }
        }
    }

    private func loadLinkedAtoms() {
        let ownUUID = atom.uuid
        let ownTitle = atom.title ?? ""
        Task { @MainActor in
            let edges = (try? await GraphQueryEngine().getEdges(for: ownUUID)) ?? []
            let uuids = edges.map { $0.sourceUUID == ownUUID ? $0.targetUUID : $0.sourceUUID }
            var atoms: [Atom] = []
            for uuid in uuids.prefix(20) {
                if let a = try? await AtomRepository.shared.fetch(uuid: uuid) {
                    atoms.append(a)
                }
            }
            linkedAtoms = atoms

            // Build rich backlink previews with excerpts
            var previews: [NoteBacklinkPreview] = []
            for linked in atoms {
                let excerpt = extractExcerpt(from: linked.content ?? "", referencing: ownTitle)
                previews.append(NoteBacklinkPreview(
                    atomUUID: linked.uuid,
                    title: linked.title ?? "Untitled",
                    type: linked.type,
                    excerpt: excerpt
                ))
            }
            backlinkPreviews = previews

            // Aggregate mentioned-in counts by atom type (excluding notes)
            var counts: [AtomType: Int] = [:]
            for linked in atoms where linked.type != .note {
                counts[linked.type, default: 0] += 1
            }
            mentionedInCounts = counts
        }
    }

    private func extractExcerpt(from body: String, referencing title: String) -> String {
        guard !title.isEmpty else {
            return String(body.prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let lower = body.lowercased()
        let needle = title.lowercased()
        if let range = lower.range(of: needle) {
            let start = body.index(range.lowerBound, offsetBy: -40, limitedBy: body.startIndex) ?? body.startIndex
            let end = body.index(range.upperBound, offsetBy: 80, limitedBy: body.endIndex) ?? body.endIndex
            let snippet = String(body[start..<end])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
            return (start > body.startIndex ? "…" : "") + snippet + (end < body.endIndex ? "…" : "")
        }
        return String(body.prefix(120))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
    }

    // MARK: - Floating Block Listeners

    /// Listen for atom picker notifications to add existing atoms as floating blocks
    private func listenForAtomPicker() {
        NotificationCenter.default.addObserver(
            forName: CosmoNotification.FocusMode.addAtomAsFloatingBlock,
            object: nil,
            queue: .main
        ) { [self] notification in
            guard !self.isPaneContext || self.isPaneContextOwner else { return }
            guard let userInfo = notification.userInfo,
                  let atomUUID = userInfo["atomUUID"] as? String,
                  let atomTypeRaw = userInfo["atomType"] as? String,
                  let atomType = AtomType(rawValue: atomTypeRaw),
                  let title = userInfo["title"] as? String else { return }

            let position = CGPoint(
                x: 500 + CGFloat.random(in: -60...60),
                y: 300 + CGFloat.random(in: -60...60)
            )

            floatingBlocksManager.addBlock(
                linkedAtomUUID: atomUUID,
                linkedAtomType: atomType,
                title: title,
                position: position
            )
        }
    }

    // MARK: - GRDB Live Observation

    private func startObservingAtom() {
        let uuid = atom.uuid

        let observation = ValueObservation.tracking { db in
            try Atom
                .filter(Column("uuid") == uuid)
                .fetchOne(db)
        }

        observationCancellable = observation.publisher(in: database.dbQueue)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("Note observation error: \(error)")
                    }
                },
                receiveValue: { [self] fetchedAtom in
                    guard let fetchedAtom = fetchedAtom else { return }

                    let nextTitleDocument = RichDocumentPersistence.loadAtomDocument(
                        field: .title,
                        metadata: fetchedAtom.metadata,
                        fallbackPlainText: fetchedAtom.title
                    )
                    let nextBodyDocument = RichDocumentPersistence.loadAtomDocument(
                        field: .body,
                        metadata: fetchedAtom.metadata,
                        fallbackPlainText: fetchedAtom.content
                    )
                    let nextTitlePlainText = RichDocumentPersistence.titlePlainText(from: nextTitleDocument)
                    let nextBodyPlainText = nextBodyDocument.plainText
                    NoteFocusLog.debug("[FOCUS-NOTE] 🔔 GRDB observation fired — uuid=\(atom.uuid) isInitialLoad=\(isInitialLoad) isEditingTitle=\(isEditingTitle) dbBodyLen=\(nextBodyPlainText.count) localBodyLen=\(plainContent.count) dbBodyPreview=\"\(String(nextBodyPlainText.prefix(60)))\" localBodyPreview=\"\(String(plainContent.prefix(60)))\"")

                    if !isEditingTitle,
                       (nextTitlePlainText != titlePlainText || nextTitleDocument != titleDocument) {
                        NoteFocusLog.debug("[FOCUS-NOTE] 🔔 observation APPLYING title — uuid=\(atom.uuid)")
                        applyObservedTitleDocument(nextTitleDocument)
                    } else if isEditingTitle,
                              (nextTitlePlainText != titlePlainText || nextTitleDocument != titleDocument) {
                        NoteFocusLog.debug("[FOCUS-NOTE] 🔔 observation DEFERRED title (editing) — uuid=\(atom.uuid)")
                        pendingObservedTitleDocument = nextTitleDocument
                    }

                    // Only overwrite body from DB during initial load —
                    // after that, the user is always editing and observation echoes
                    // from auto-save would overwrite text typed since save started.
                    if isInitialLoad,
                       nextBodyPlainText != plainContent || nextBodyDocument != bodyDocument {
                        NoteFocusLog.debug("[FOCUS-NOTE] 🔔 observation APPLYING body (initialLoad) — uuid=\(atom.uuid) dbLen=\(nextBodyPlainText.count)")
                        bodyDocument = nextBodyDocument
                        plainContent = nextBodyPlainText
                        updateBodyHeadingOutline(from: nextBodyDocument)
                        updateTextAnalysisImmediately(for: nextBodyPlainText)
                        refreshCosmoContextIfActive()
                    } else if !isInitialLoad, nextBodyPlainText != plainContent {
                        NoteFocusLog.debug("[FOCUS-NOTE] 🔔 observation SKIPPED body (not initialLoad) — uuid=\(atom.uuid) dbLen=\(nextBodyPlainText.count) localLen=\(plainContent.count) ⚠️ DIVERGED=\(nextBodyPlainText != plainContent)")
                    }

                    // Tags: only apply observed values when the editor isn't open and
                    // local tags don't diverge from the last persisted snapshot —
                    // otherwise the observation echo reverts an in-progress edit.
                    if !showTagEditor, tags == lastPersistedTags, fetchedAtom.tagsList != tags {
                        lastPersistedTags = fetchedAtom.tagsList
                        tags = fetchedAtom.tagsList
                    } else if tags == fetchedAtom.tagsList {
                        lastPersistedTags = fetchedAtom.tagsList
                    }
                    if let date = ISO8601.date(from: fetchedAtom.createdAt) {
                        createdAt = date
                    }

                    if isInitialLoad {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isInitialLoad = false
                        }
                    }
                }
            )
    }

    // MARK: - Auto-Save

    private func startEditingLockRefresh() {
        editingLockRefreshTask?.cancel()
        let uuid = atom.uuid
        editingLockRefreshTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                AtomRepository.shared.refreshEditingLock(uuid: uuid)
            }
        }
    }

    private func stopEditingLockRefresh() {
        editingLockRefreshTask?.cancel()
        editingLockRefreshTask = nil
    }

    private func triggerAutoSave() {
        NoteFocusLog.debug("[FOCUS-NOTE] triggerAutoSave() — \(autoSaveDelay)s debounce starting uuid=\(atom.uuid)")
        AtomRepository.shared.refreshEditingLock(uuid: atom.uuid)
        autoSaveTask?.cancel()
        autoSaveTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(autoSaveDelay * 1_000_000_000))
                guard !Task.isCancelled else {
                    NoteFocusLog.debug("[FOCUS-NOTE] triggerAutoSave() CANCELLED uuid=\(atom.uuid)")
                    return
                }
                NoteFocusLog.debug("[FOCUS-NOTE] triggerAutoSave() debounce elapsed, calling saveAtom() uuid=\(atom.uuid)")
                await MainActor.run { saveAtom() }
            } catch {
                // Cancelled
            }
        }
    }

    private func applyInlineAssistantBodyEdit(
        _ operation: CosmoAssistantProposalOperation
    ) async throws -> CosmoEditableOperationResult {
        guard operation.targetID == NoteContextProvider.targetID(for: atom.uuid) else {
            return CosmoEditableOperationResult(operationID: operation.id, status: .conflicted, message: "Target changed")
        }

        switch operation.kind {
        case .textReplacement, .structuredFieldReplacement, .textInsertion:
            guard let placement = CosmoInlineTextEditResolver.placement(for: operation, in: plainContent) else {
                return CosmoEditableOperationResult(operationID: operation.id, status: .conflicted, message: "Original text not found")
            }
            plainContent.replaceSubrange(placement.range, with: placement.replacementText)
            bodyDocument = RichDocument.migrateLegacy(plainContent)

        case .formatMarks:
            guard let mark = operation.formatMark else {
                return CosmoEditableOperationResult(operationID: operation.id, status: .rejected, message: "No formatting mark specified")
            }
            guard let formatted = CosmoInlineFormatMarksApplier.apply(
                mark: mark,
                originalText: operation.originalText,
                to: bodyDocument
            ) else {
                // Honest skip, never a blocking conflict.
                return CosmoEditableOperationResult(operationID: operation.id, status: .rejected, message: "Couldn't find that text anymore — skipped")
            }
            bodyDocument = formatted
            plainContent = bodyDocument.plainText

        case .canvasPlan:
            return CosmoEditableOperationResult(operationID: operation.id, status: .conflicted, message: "Canvas edits need a canvas provider")
        }

        hasLocalBodyEdits = true
        updateBodyHeadingOutline(from: bodyDocument)
        updateTextAnalysisImmediately(for: plainContent)
        triggerAutoSave()

        return CosmoEditableOperationResult(operationID: operation.id, status: .applied, message: "Applied")
    }

    /// Debounced save with UI feedback (used during editing)
    private func saveAtom() {
        NoteFocusLog.debug("[FOCUS-NOTE] saveAtom() — uuid=\(atom.uuid) titleLen=\(titlePlainText.count) bodyLen=\(plainContent.count) bodyPreview=\"\(String(plainContent.prefix(80)))\"")
        let now = Date()
        let saveKind = autosavePolicy.saveKind(
            plainTextCharacterCount: plainContent.count,
            now: now,
            lastRichCheckpointAt: lastRichCheckpointAt,
            isClosing: false
        )

        withAnimation(ProMotionSprings.snappy) {
            saveState = .saving
        }
        performSave(kind: saveKind, requestedAt: now) { success in
            if success {
                withAnimation(ProMotionSprings.snappy) {
                    saveState = .saved
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(ProMotionSprings.gentle) {
                        saveState = .idle
                    }
                }
            } else {
                withAnimation(ProMotionSprings.snappy) {
                    saveState = .idle
                }
            }
        }
    }

    /// Immediate synchronous save (used on close) — blocks until DB write completes.
    /// Guarantees data is persisted before the view/app exits.
    private func saveAtomImmediately() {
        NoteFocusLog.debug("[FOCUS-NOTE] saveAtomImmediately() — uuid=\(atom.uuid) titleLen=\(titlePlainText.count) bodyLen=\(plainContent.count) hasLocalBodyEdits=\(hasLocalBodyEdits) hasLocalMetaEdits=\(hasLocalMetaEdits) bodyPreview=\"\(String(plainContent.prefix(80)))\"")
        // Dirty gate: a session with zero local edits must not write its stale
        // open-time snapshot over newer external writes (agent edits, another
        // device, a canvas block save). Body edits, title/tags/style edits each
        // set their flag; autosaves clear them once persisted.
        guard hasLocalBodyEdits || hasLocalMetaEdits else {
            NoteFocusLog.debug("[FOCUS-NOTE] saveAtomImmediately() SKIPPED — no local edits, avoiding stale overwrite uuid=\(atom.uuid)")
            return
        }
        let titleDocumentCopy = titleDocument
        let bodyDocumentCopy = bodyDocument
        let plainContentCopy = plainContent
        let tagsCopy = tags
        let noteStyleCopy = noteStyle
        let uuid = atom.uuid
        let hasLocalBodyEditsCopy = hasLocalBodyEdits
        AtomRepository.shared.refreshEditingLock(uuid: uuid)

        do {
            let snapshot = try database.write { db -> NoteDocumentSnapshot in
                var existingMetadata: String?
                var existingBody: String?
                if let row = try Row.fetchOne(db, sql: "SELECT metadata, body FROM atoms WHERE uuid = ?", arguments: [uuid]) {
                    existingMetadata = row["metadata"]
                    existingBody = row["body"]
                }

                let snapshot = RichDocumentPersistence.noteSnapshot(
                    existingMetadata: existingMetadata,
                    titleDocument: titleDocumentCopy,
                    bodyDocument: bodyDocumentCopy,
                    plainBodyText: plainContentCopy
                )
                guard NoteWritePolicy.allowsBodyWrite(
                    existingBody: existingBody,
                    proposedBody: snapshot.bodyPlainText,
                    hasLocalEdits: hasLocalBodyEditsCopy
                ) else {
                    throw NoteSaveError.rejectedEmptyOverwrite(uuid: uuid)
                }
                let metadataString = Self.metadataString(for: snapshot, tags: tagsCopy, style: noteStyleCopy)

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
                        snapshot.atomTitle,
                        snapshot.bodyPlainText,
                        metadataString ?? snapshot.metadata,
                        ISO8601.string(from: Date()),
                        uuid
                    ]
                )
                return snapshot
            }
            if plainContent == plainContentCopy {
                hasLocalBodyEdits = false
            }
            if tags == tagsCopy && titleDocument == titleDocumentCopy && noteStyle == noteStyleCopy {
                hasLocalMetaEdits = false
            }
            lastPersistedTags = tagsCopy
            lastRichCheckpointAt = Date()
            postNoteFocusState(snapshot: snapshot, atomUUID: uuid, notifyRichDocumentObservers: false)
            // Sync: queue for Supabase push
            Task {
                if let updatedAtom = try? await database.asyncRead({ db in
                    try Atom.filter(Column("uuid") == uuid).fetchOne(db)
                }) {
                    // skipVersionIncrement: raw SQL already did _local_version + 1
                    await ChangeTracker.shared.trackUpdate(table: "atoms", entity: updatedAtom, skipVersionIncrement: true)
                }
            }
        } catch {
            // The close/termination save is the LAST chance to persist this
            // session — dead-letter the snapshot so the next open can restore it.
            // (The intentional empty-overwrite rejection is not a loss — skip it.)
            if !(error is NoteSaveError) {
                stashDeadLetter(
                    uuid: uuid,
                    body: plainContentCopy,
                    title: RichDocumentPersistence.titlePlainText(from: titleDocumentCopy),
                    tags: tagsCopy,
                    bodyDocument: bodyDocumentCopy,
                    titleDocument: titleDocumentCopy
                )
            }
            PersistenceHealth.note(.writeFailure, context: "noteFocus.closeSave", detail: "uuid=\(uuid): \(error)")
            print("Failed to save note (sync): \(error)")
        }
    }

    // MARK: - Dead Letter (failed close save)

    private struct NoteSaveDeadLetter: Codable {
        var body: String
        var title: String
        var tags: [String]
        var bodyDocumentJSON: String?
        var titleDocumentJSON: String?
        var savedAt: Date
    }

    private static func deadLetterKey(forAtomUUID uuid: String) -> String {
        "noteSaveDeadLetter.\(uuid)"
    }

    private func stashDeadLetter(
        uuid: String,
        body: String,
        title: String,
        tags: [String],
        bodyDocument: RichDocument,
        titleDocument: RichDocument
    ) {
        let encoder = JSONEncoder()
        let letter = NoteSaveDeadLetter(
            body: body,
            title: title,
            tags: tags,
            bodyDocumentJSON: (try? encoder.encode(bodyDocument)).flatMap { String(data: $0, encoding: .utf8) },
            titleDocumentJSON: (try? encoder.encode(titleDocument)).flatMap { String(data: $0, encoding: .utf8) },
            savedAt: Date()
        )
        guard let data = try? encoder.encode(letter) else { return }
        UserDefaults.standard.set(data, forKey: Self.deadLetterKey(forAtomUUID: uuid))
        NoteFocusLog.debug("[FOCUS-NOTE] stashed dead letter — uuid=\(uuid) bodyLen=\(body.count)")
    }

    /// If a previous session's close save failed, its snapshot was dead-lettered.
    /// When the DB body still differs, restore the snapshot as the editor content
    /// and persist it; either way the key is cleared.
    private func restoreDeadLetterIfNeeded() {
        let key = Self.deadLetterKey(forAtomUUID: atom.uuid)
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        defer { UserDefaults.standard.removeObject(forKey: key) }
        guard let letter = try? JSONDecoder().decode(NoteSaveDeadLetter.self, from: data) else { return }

        let restoredBody = letter.body
        guard !restoredBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              restoredBody != plainContent else {
            return
        }

        if let json = letter.bodyDocumentJSON,
           let docData = json.data(using: .utf8),
           let doc = try? JSONDecoder().decode(RichDocument.self, from: docData) {
            bodyDocument = doc
        } else {
            bodyDocument = RichDocument.migrateLegacy(restoredBody)
        }
        plainContent = bodyDocument.plainText
        if let json = letter.titleDocumentJSON,
           let docData = json.data(using: .utf8),
           let doc = try? JSONDecoder().decode(RichDocument.self, from: docData) {
            titleDocument = doc
            titlePlainText = RichDocumentPersistence.titlePlainText(from: doc)
        } else if !letter.title.isEmpty {
            titleDocument = RichDocument.migrateLegacy(letter.title)
            titlePlainText = letter.title
        }
        if !letter.tags.isEmpty {
            tags = letter.tags
        }
        updateBodyHeadingOutline(from: bodyDocument)
        updateTextAnalysisImmediately(for: plainContent)

        // Mark dirty + leave initial-load mode so the GRDB observation's
        // initial fire can't clobber the restored content, then persist it.
        hasLocalBodyEdits = true
        hasLocalMetaEdits = true
        isInitialLoad = false
        saveAtomImmediately()
        PersistenceHealth.note(.conflict, context: "noteFocus.deadLetter", detail: "restored unsaved close snapshot for \(atom.uuid) (\(restoredBody.count) chars)")
        print("📨 Restored dead-lettered note snapshot for \(atom.uuid)")
    }

    /// Async save with completion callback (used for debounced auto-save during editing)
    private func performSave(
        kind: NoteSaveKind = .richDocumentCheckpoint,
        requestedAt: Date = Date(),
        completion: ((Bool) -> Void)?
    ) {
        let titleDocumentCopy = titleDocument
        let bodyDocumentCopy = bodyDocument
        let titleCopy = titlePlainText
        let contentCopy = plainContent
        let tagsCopy = tags
        let noteStyleCopy = noteStyle
        let uuid = atom.uuid
        let hasLocalBodyEditsCopy = hasLocalBodyEdits
        saveGeneration += 1
        let generation = saveGeneration
        AtomRepository.shared.refreshEditingLock(uuid: uuid)

        Task {
            guard await MainActor.run(body: { !saveClosed && saveGeneration == generation }) else {
                return
            }

            do {
                switch kind {
                case .plainText:
                    var existingMetadata: String?
                    var existingBody: String?
                    if let row = try await database.asyncRead({ db in
                        try Row.fetchOne(db, sql: "SELECT metadata, body FROM atoms WHERE uuid = ?", arguments: [uuid])
                    }) {
                        existingMetadata = row["metadata"]
                        existingBody = row["body"]
                    }
                    let existingBodyForWrite = existingBody

                    let snapshot = await Task.detached(priority: .utility) {
                        RichDocumentPersistence.noteSnapshot(
                            existingMetadata: existingMetadata,
                            titleDocument: titleDocumentCopy,
                            bodyDocument: bodyDocumentCopy,
                            plainBodyText: contentCopy
                        )
                    }.value

                    // Re-check right before the write: the close save may have run
                    // (saveClosed) or a newer autosave superseded this generation
                    // while the snapshot was being prepared.
                    guard await MainActor.run(body: { !saveClosed && saveGeneration == generation }) else {
                        return
                    }

                    try await database.asyncWrite { db in
                        guard NoteWritePolicy.allowsBodyWrite(
                            existingBody: existingBodyForWrite,
                            proposedBody: snapshot.bodyPlainText,
                            hasLocalEdits: hasLocalBodyEditsCopy
                        ) else {
                            throw NoteSaveError.rejectedEmptyOverwrite(uuid: uuid)
                        }
                        let metadataString = Self.metadataString(for: snapshot, tags: tagsCopy, style: noteStyleCopy)

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
                                snapshot.atomTitle ?? RichDocumentPersistence.nilIfEmpty(titleCopy),
                                snapshot.bodyPlainText,
                                metadataString ?? snapshot.metadata,
                                ISO8601.string(from: Date()),
                                uuid
                            ]
                        )
                    }

                    await MainActor.run {
                        if plainContent == contentCopy {
                            hasLocalBodyEdits = false
                        }
                        if tags == tagsCopy && titlePlainText == titleCopy && noteStyle == noteStyleCopy {
                            hasLocalMetaEdits = false
                        }
                        lastPersistedTags = tagsCopy
                        postNoteFocusState(snapshot: snapshot, atomUUID: uuid)
                    }

                case .richDocumentCheckpoint:
                    var existingMetadata: String?
                    if let row = try await database.asyncRead({ db in
                        try Row.fetchOne(db, sql: "SELECT metadata FROM atoms WHERE uuid = ?", arguments: [uuid])
                    }) {
                        existingMetadata = row["metadata"]
                    }

                    let snapshot = await Task.detached(priority: .utility) {
                        RichDocumentPersistence.noteSnapshot(
                            existingMetadata: existingMetadata,
                            titleDocument: titleDocumentCopy,
                            bodyDocument: bodyDocumentCopy,
                            plainBodyText: contentCopy
                        )
                    }.value

                    guard await MainActor.run(body: { !saveClosed && saveGeneration == generation }) else {
                        return
                    }

                    try await database.asyncWrite { db in
                        var existingBody: String?
                        if let row = try Row.fetchOne(db, sql: "SELECT body FROM atoms WHERE uuid = ?", arguments: [uuid]) {
                            existingBody = row["body"]
                        }

                        guard NoteWritePolicy.allowsBodyWrite(
                            existingBody: existingBody,
                            proposedBody: snapshot.bodyPlainText,
                            hasLocalEdits: hasLocalBodyEditsCopy
                        ) else {
                            throw NoteSaveError.rejectedEmptyOverwrite(uuid: uuid)
                        }
                        let metadataString = Self.metadataString(for: snapshot, tags: tagsCopy, style: noteStyleCopy)

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
                                snapshot.atomTitle,
                                snapshot.bodyPlainText,
                                metadataString ?? snapshot.metadata,
                                ISO8601.string(from: Date()),
                                uuid
                            ]
                        )
                    }

                    await MainActor.run {
                        if plainContent == contentCopy {
                            hasLocalBodyEdits = false
                        }
                        if tags == tagsCopy && titlePlainText == titleCopy && noteStyle == noteStyleCopy {
                            hasLocalMetaEdits = false
                        }
                        lastPersistedTags = tagsCopy
                        lastRichCheckpointAt = requestedAt
                        postNoteFocusState(snapshot: snapshot, atomUUID: uuid)
                    }
                }

                // Sync: queue for Supabase push so notes sync to cloud
                if let updatedAtom = try? await database.asyncRead({ db in
                    try Atom.filter(Column("uuid") == uuid).fetchOne(db)
                }) {
                    // skipVersionIncrement: raw SQL already did _local_version + 1
                    await ChangeTracker.shared.trackUpdate(table: "atoms", entity: updatedAtom, skipVersionIncrement: true)
                }
                if let completion {
                    await MainActor.run { completion(true) }
                }
            } catch {
                if !(error is NoteSaveError) {
                    PersistenceHealth.note(.writeFailure, context: "noteFocus.autosave", detail: "uuid=\(uuid): \(error)")
                }
                print("Failed to save note: \(error)")
                if let completion {
                    await MainActor.run { completion(false) }
                }
            }
        }
    }

    private func applyObservedTitleDocument(_ document: RichDocument) {
        titleDocument = document
        titlePlainText = RichDocumentPersistence.titlePlainText(from: document)
        titleUnderlineProgress = titlePlainText.isEmpty ? 0.28 : 1
        refreshCosmoContextIfActive()
    }

    nonisolated private static func metadataString(
        for snapshot: NoteDocumentSnapshot,
        tags: [String],
        style: NoteDocumentStyle
    ) -> String? {
        style.write(intoMetadata: metadataString(existingMetadata: snapshot.metadata, tags: tags))
    }

    nonisolated private static func metadataString(existingMetadata: String?, tags: [String]) -> String? {
        var metadataDict: [String: Any] = [:]
        if let metadata = existingMetadata,
           let data = metadata.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            metadataDict = decoded
        }

        if tags.isEmpty {
            metadataDict.removeValue(forKey: "tags")
        } else {
            metadataDict["tags"] = tags
        }

        return (try? JSONSerialization.data(withJSONObject: metadataDict))
            .flatMap { String(data: $0, encoding: .utf8) }
    }

    private func postNoteFocusState(
        snapshot: NoteDocumentSnapshot,
        atomUUID: String,
        notifyRichDocumentObservers: Bool = true
    ) {
        NotificationCenter.default.post(
            name: .noteFocusStateDidChange,
            object: nil,
            userInfo: snapshot.noteFocusStatePayload(atomUUID: atomUUID)
        )

        guard notifyRichDocumentObservers else { return }

        NotificationCenter.default.post(
            name: .richDocumentDidChange,
            object: nil,
            userInfo: ["atomUUID": atomUUID]
        )
    }

    private func postNoteFocusState(title: String, body: String, atomUUID: String) {
        NotificationCenter.default.post(
            name: .noteFocusStateDidChange,
            object: nil,
            userInfo: [
                "atomUUID": atomUUID,
                "title": title,
                "body": body
            ]
        )
    }
}

// MARK: - V2 Support Types

fileprivate struct NoteBacklinkPreview: Equatable, Identifiable {
    var id: String { atomUUID }
    let atomUUID: String
    let title: String
    let type: AtomType
    let excerpt: String
}

private enum NoteSaveError: LocalizedError {
    case rejectedEmptyOverwrite(uuid: String)

    var errorDescription: String? {
        switch self {
        case .rejectedEmptyOverwrite(let uuid):
            return "Rejected empty note overwrite for \(uuid) because the persisted body is non-empty and no local body edit was recorded."
        }
    }
}

// MARK: - Backlink Card

fileprivate struct BacklinkCardView: View {
    let preview: NoteBacklinkPreview
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            HStack(alignment: .top, spacing: DS.space6) {
                Image(systemName: preview.type.iconName)
                    .font(DS.caption2)
                    .foregroundStyle(entityTint)
                    .frame(width: 14, alignment: .leading)
                    .accessibilityLabel(preview.type.displayName)
                Text(preview.title)
                    .font(DS.subheadline.weight(.semibold))
                    .foregroundStyle(DS.focusImmersiveText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            if !preview.excerpt.isEmpty {
                Text(preview.excerpt)
                    .font(DS.caption)
                    .foregroundStyle(DS.focusImmersiveTextSecondary)
                    .italic()
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: DS.space4) {
                Text(preview.type.displayName.uppercased())
                    .font(DS.smallCaps)
                    .foregroundStyle(entityTint.opacity(0.8))
                Spacer(minLength: 0)
            }
        }
        .padding(DS.space10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .fill(isHovered ? DS.focusImmersiveSurface : DS.focusImmersiveSurface.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .stroke(DS.sepiaBorder.opacity(0.5), lineWidth: 0.5)
                )
        )
        .clipShape(.rect(cornerRadius: DS.radiusSmall))
        .shadow(color: DS.inkWash.opacity(isHovered ? 0.08 : 0.04), radius: isHovered ? 6 : 3, y: isHovered ? 3 : 1)
        .scaleEffect(isHovered ? 1.012 : 1.0)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(preview.type.displayName) backlink: \(preview.title)")
    }

    private var entityTint: Color {
        switch preview.type {
        case .idea: return DS.entityIdea
        case .content: return DS.entityContent
        case .research: return DS.entityResearch
        case .note: return DS.entityNote
        case .task: return DS.entityTask
        default: return DS.focusImmersiveTextSecondary
        }
    }
}

// MARK: - Tag Cloud

fileprivate struct FlowTagCloud: View {
    let tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            ForEach(tags.prefix(10), id: \.self) { tag in
                HStack(spacing: DS.space4) {
                    Circle()
                        .fill(DS.gilt.opacity(0.5))
                        .frame(width: 4, height: 4)
                    Text(tag)
                        .font(DS.caption)
                        .foregroundStyle(DS.focusImmersiveTextSecondary)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: - Empty State

fileprivate struct NoteChromeIconButton: View {
    let systemName: String
    let isActive: Bool
    let tint: Color
    let inactiveColor: Color
    let hoverFill: Color
    let help: String
    let accessibilityLabel: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(DS.callout)
                .foregroundStyle(isActive ? tint : inactiveColor)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(isActive ? tint.opacity(0.14) : hoverFill.opacity(isHovered ? 1 : 0))
                )
                .accessibilityLabel(accessibilityLabel)
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Circle())
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .help(help)
    }
}

fileprivate struct NoteFocusEmptyStateView<Title: View>: View {
    let title: Title
    @State private var appeared = false

    init(@ViewBuilder title: () -> Title) {
        self.title = title()
    }

    var body: some View {
        VStack(spacing: DS.space20) {
            Image(systemName: "diamond")
                .font(DS.display.weight(.ultraLight))
                .foregroundStyle(DS.gilt.opacity(0.6))
                .accessibilityHidden(true)
                .rotationEffect(.degrees(appeared ? 0 : -8))
                .opacity(appeared ? 1 : 0)

            title
                .accessibilityAddTraits(.isHeader)

            Text("Start writing, or press ⌘K to capture from\nyour clipboard, a voice memo, or a quote\nyou've highlighted elsewhere.")
                .font(DS.body)
                .foregroundStyle(DS.focusImmersiveTextSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.top, DS.space8)

            HStack(spacing: DS.space12) {
                emptyStatePill(icon: "command", label: "⌘K capture")
                emptyStatePill(icon: "slash.circle", label: "/ insert")
                emptyStatePill(icon: "link", label: "⌥⌘L link")
            }
            .padding(.top, DS.space8)
        }
        .padding(.vertical, DS.space32)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .onAppear {
            withAnimation(ProMotionSprings.cardEntrance.delay(0.1)) {
                appeared = true
            }
        }
    }

    private func emptyStatePill(icon: String, label: String) -> some View {
        HStack(spacing: DS.space4) {
            Image(systemName: icon)
                .font(DS.caption2)
                .accessibilityHidden(true)
            Text(label)
                .font(DS.caption)
        }
        .foregroundStyle(DS.focusImmersiveTextMuted)
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space6)
        .frame(minHeight: 32)
        .background(
            Capsule()
                .fill(DS.focusImmersiveSurface.opacity(0.6))
                .overlay(Capsule().stroke(DS.sepiaBorder.opacity(0.5), lineWidth: 0.5))
        )
    }
}


// MARK: - Cosmo Context Provider

@MainActor
class NoteContextProvider: CosmoContextProvider, CosmoEditableSurfaceProvider {
    private let atom: Atom
    private let titleRef: () -> String
    private let contentRef: () -> String
    private let tagsRef: () -> [String]
    private let selectedTextRef: () -> String
    private let applyBodyEdit: ((CosmoAssistantProposalOperation) async throws -> CosmoEditableOperationResult)?

    init(
        atom: Atom,
        titleRef: @escaping () -> String,
        contentRef: @escaping () -> String,
        tagsRef: @escaping () -> [String],
        selectedTextRef: @escaping () -> String = { "" },
        applyBodyEdit: ((CosmoAssistantProposalOperation) async throws -> CosmoEditableOperationResult)? = nil
    ) {
        self.atom = atom
        self.titleRef = titleRef
        self.contentRef = contentRef
        self.tagsRef = tagsRef
        self.selectedTextRef = selectedTextRef
        self.applyBodyEdit = applyBodyEdit
    }

    var contextType: CosmoContextType { .noteFocusMode }

    var surfaceID: String {
        "note:\(atom.uuid)"
    }

    static func targetID(for atomUUID: String) -> String {
        "note:\(atomUUID):body"
    }

    private var resolvedTitle: String {
        let liveTitle = titleRef().trimmingCharacters(in: .whitespacesAndNewlines)
        if !liveTitle.isEmpty {
            return liveTitle
        }
        return atom.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var contextSummary: String {
        let title = resolvedTitle
        let words = contentRef().split(separator: " ").count
        return "Note: \(title.isEmpty ? "Untitled" : title) (\(words) words)"
    }

    var contextData: CosmoContextData {
        let content = contentRef()
        let tags = tagsRef()
        return CosmoContextData(
            currentAtomUUID: atom.uuid,
            currentAtomType: "note",
            currentAtomTitle: resolvedTitle,
            viewSpecificData: [
                "wordCount": "\(content.split(separator: " ").count)",
                "tags": tags.joined(separator: ", "),
                "noteBody": content,
                "contentPreview": String(content.prefix(500))
            ],
            selectedText: selectedTextRef()
        )
    }

    func editableSnapshot() -> CosmoEditableSourceSnapshot {
        let content = contentRef()
        let selectedText = selectedTextRef().trimmingCharacters(in: .whitespacesAndNewlines)
        let selection: CosmoEditableSelection? = selectedText.isEmpty ? nil : CosmoEditableSelection(
            text: selectedText,
            // Block rows cage selection to one block; the containing line is the
            // first body line holding the selection's lead.
            containingLine: content
                .components(separatedBy: .newlines)
                .first { $0.contains(selectedText.components(separatedBy: .newlines).first ?? selectedText) }?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
        return CosmoEditableSourceSnapshot(
            surfaceID: surfaceID,
            targetID: Self.targetID(for: atom.uuid),
            kind: .text,
            title: resolvedTitle.isEmpty ? "Untitled note" : resolvedTitle,
            text: content,
            sourceHash: CosmoEditableSurfaceHasher.hash(content),
            anchors: [
                .init(id: "body", label: "Body", utf16Start: 0, utf16Length: content.utf16.count)
            ],
            selection: selection
        )
    }

    func apply(operation: CosmoAssistantProposalOperation) async throws -> CosmoEditableOperationResult {
        guard let applyBodyEdit else {
            return CosmoEditableOperationResult(operationID: operation.id, status: .conflicted, message: "Note editor is unavailable")
        }
        return try await applyBodyEdit(operation)
    }

    func reject(operation: CosmoAssistantProposalOperation) async -> CosmoEditableOperationResult {
        CosmoEditableOperationResult(operationID: operation.id, status: .rejected, message: "Rejected")
    }

    var availableActions: [CosmoWindowAction] {
        let targetEditorID = EditorCommandTarget.noteBody(atom.uuid)
        let appendPrefix = contentRef().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"

        return [
            CosmoWindowAction(
                id: "note-insert-selection",
                name: "Insert at Cursor",
                description: "Insert into the active note editor at the current cursor.",
                modelTier: .balanced
            ) { prompt in
                let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return "Nothing inserted." }
                await EditorCommandBus.shared.insertText(
                    trimmed,
                    at: .cursor,
                    targetEditorID: targetEditorID,
                    allowInactive: true
                )
                return "Inserted into the note."
            },
            CosmoWindowAction(
                id: "note-append-end",
                name: "Append to Note",
                description: "Append a new paragraph to the end of the note.",
                modelTier: .balanced
            ) { prompt in
                let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return "Nothing appended." }
                await EditorCommandBus.shared.insertText(
                    "\(appendPrefix)\(trimmed)",
                    at: .endOfDocument,
                    targetEditorID: targetEditorID,
                    allowInactive: true
                )
                return "Appended to the note."
            }
        ]
    }
}
