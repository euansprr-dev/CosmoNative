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

    // V2 "Scholar's Carrel" rail state
    @AppStorage("noteFocusV2.leftRail") private var leftRailVisible: Bool = true
    @AppStorage("noteFocusV2.rightRail") private var rightRailVisible: Bool = true
    @State private var graphOverlayVisible: Bool = false
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
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .overlay(alignment: .top) {
                topBar
            }

            // Persistent floating blocks overlay
            GeometryReader { geo in
                FocusFloatingBlocksLayer(manager: floatingBlocksManager)
                    .frame(width: geo.size.width, height: geo.size.height)
            }

            // Graph overlay (⌘G)
            if graphOverlayVisible {
                NoteGraphOverlayView(
                    centerAtom: atom,
                    onClose: { withAnimation(ProMotionSprings.modal) { graphOverlayVisible = false } }
                )
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .background(
            // Hidden keyboard shortcut buttons (rule 10: macOS shortcuts for primary actions)
            Group {
                Button("Toggle graph") { toggleGraphOverlay() }
                    .keyboardShortcut("g", modifiers: .command)
                    .opacity(0)
                    .accessibilityHidden(true)
                Button("Toggle panels") { togglePanels() }
                    .keyboardShortcut("\\", modifiers: .command)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        )
        .focusBlockContextMenu(
            manager: floatingBlocksManager,
            ownerAtomUUID: atom.uuid
        )
        .focusBlockInspector(manager: floatingBlocksManager)
        .focusImmersiveEntryTransition()
        .onAppear {
            AtomRepository.shared.acquireEditingLock(uuid: atom.uuid)
            startEditingLockRefresh()
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
            focusBackground
            // Subtle vignette that darkens edges to emphasize the center column
            RadialGradient(
                colors: [Color.clear, DS.inkWash.opacity(0.04)],
                center: .center,
                startRadius: 360,
                endRadius: 900
            )
            .blendMode(.multiply)
        }
    }

    // MARK: - Top Bar (V2)

    private var topBar: some View {
        HStack(spacing: DS.space12) {
            if !isPaneContext {
                backButton
            }

            noteTypeBadge

            if saveState != .idle {
                noteSaveBadge
                    .transition(.opacity)
            }

            Spacer()

            topBarChromeButtons
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space6)
        .background(FocusModeEditorBlurTapLayer())
        .cosmoGlassPanel(role: .floatingAssistant, cornerRadius: 22)
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
        Button(action: onClose) {
            HStack(spacing: DS.space6) {
                Image(systemName: "chevron.left")
                    .font(DS.buttonText)
                    .accessibilityLabel("Back")
                Text("Back")
                    .font(DS.callout)
            }
            .foregroundStyle(focusTextSecondary)
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space8)
            .frame(minWidth: 44, minHeight: 32)
            .background(focusBorder.opacity(0.5), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var noteTypeBadge: some View {
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
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space6)
        .background(DS.entityNote.opacity(DS.opacitySubtle), in: Capsule())
    }

    private var topBarChromeButtons: some View {
        HStack(spacing: DS.space8) {
            styleMenuButton
            chromeIconButton(
                systemName: "rectangle.split.3x1",
                isActive: leftRailVisible || rightRailVisible,
                tint: DS.accent,
                help: "Toggle panels (⌘\\)",
                accessibilityLabel: "Toggle side panels",
                action: { togglePanels() }
            )
            chromeIconButton(
                systemName: "point.3.filled.connected.trianglepath.dotted",
                isActive: graphOverlayVisible,
                tint: DS.gilt,
                help: "Graph view (⌘G)",
                accessibilityLabel: "Toggle graph view",
                action: { toggleGraphOverlay() }
            )
            if isPaneContext, !isPeekContext {
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

    /// "Aa" — the document's voice. Font family, text size, page width, and
    /// typewriter mode live here, per-note.
    private var styleMenuButton: some View {
        chromeIconButton(
            systemName: "textformat",
            isActive: styleMenuPresented || noteStyle != .default,
            tint: DS.accent,
            help: "Document style",
            accessibilityLabel: "Document style",
            action: { styleMenuPresented.toggle() }
        )
        .popover(isPresented: $styleMenuPresented, arrowEdge: .bottom) {
            NoteStyleMenuView(style: $noteStyle, typewriterMode: $typewriterMode)
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

    private var centerScroll: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
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
                    dateTagsRow
                        .padding(.leading, BlockInteractionPolicy.gutterWidth)
                        .frame(maxWidth: bodyColumnWidth, alignment: .leading)
                        .padding(.top, DS.space12)
                        .padding(.bottom, DS.space24)
                    if NoteFocusHeaderLayoutPolicy.showsMetadataDivider(for: titleChromeMode) {
                        giltDivider
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
                            placeholder: "Start writing…",
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
                    .padding(.bottom, DS.space48)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DS.space40)
            .background(FocusModeEditorBlurTapLayer())
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
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.space20) {
                railSectionLabel("❡  ON THIS NOTE")

                if bodyHeadingOutline.isEmpty {
                    Text(isEmptyNote ? "No headings yet" : "No sections — use Heading 1, 2, or 3 to create sections")
                        .font(DS.caption)
                        .foregroundStyle(focusTextMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: DS.space6) {
                        ForEach(bodyHeadingOutline) { entry in
                            outlineEntryRow(entry)
                        }
                    }
                }

                Rectangle()
                    .fill(DS.gilt.opacity(0.2))
                    .frame(height: 0.5)

                railSectionLabel("LINKS")
                VStack(alignment: .leading, spacing: DS.space4) {
                    linkCountRow(label: "backlinks", count: inLinkCount, tint: DS.gilt)
                    linkCountRow(label: "out links", count: outLinkCount, tint: DS.entityNote)
                }

                if !tags.isEmpty {
                    Rectangle()
                        .fill(DS.gilt.opacity(0.2))
                        .frame(height: 0.5)

                    railSectionLabel("TAGS")
                    FlowTagCloud(tags: tags)
                }

                Spacer(minLength: DS.space24)
            }
            .padding(.horizontal, DS.space20)
            .padding(.top, DS.space24)
            .padding(.bottom, DS.space24)
        }
        .scrollEdgeEffectStyle(.soft, for: .vertical)
        .frame(maxHeight: .infinity)
        .cosmoGlassPanel(role: .focusSidebar, cornerRadius: 22)
    }

    private func outlineEntryRow(_ entry: RichHeadingOutlineEntry) -> some View {
        Button {
            navigateToBodyHeading(entry)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: DS.space6) {
                Text(entry.level == 1 ? "¶" : "›")
                    .font(DS.caption2)
                    .foregroundStyle(DS.gilt.opacity(0.6))
                    .frame(width: 10, alignment: .leading)
                Text(entry.title)
                    .font(entry.level == 1 ? DS.subheadline : DS.caption)
                    .foregroundStyle(entry.level == 1 ? focusText : focusTextSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(entry.level - 1) * DS.space8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private func linkCountRow(label: String, count: Int, tint: Color) -> some View {
        HStack(spacing: DS.space6) {
            Text("\(count)")
                .font(DS.title3)
                .foregroundStyle(count > 0 ? tint : focusTextMuted)
                .monospacedDigit()
            Text(label)
                .font(DS.caption)
                .foregroundStyle(focusTextMuted)
            Spacer(minLength: 0)
        }
    }

    private func railSectionLabel(_ text: String) -> some View {
        Text(text)
            .font(DS.smallCaps)
            .tracking(0.8)
            .foregroundStyle(DS.gilt.opacity(0.85))
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Carrel Rail (right)

    private var carrelRail: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.space24) {
                railSectionLabel("⟡  CARREL")

                backlinksSection
                mentionedInSection
                resonanceSection
                askCosmoSection

                Spacer(minLength: DS.space24)
            }
            .padding(.horizontal, DS.space20)
            .padding(.top, DS.space24)
            .padding(.bottom, DS.space24)
        }
        .scrollEdgeEffectStyle(.soft, for: .vertical)
        .frame(maxHeight: .infinity)
        .cosmoGlassPanel(role: .focusSidebar, cornerRadius: 22)
    }

    private var backlinksSection: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            HStack(spacing: DS.space6) {
                railSectionLabel("BACKLINKS")
                Text("\(inLinkCount)")
                    .font(DS.caption)
                    .foregroundStyle(focusTextMuted)
                    .monospacedDigit()
            }

            if backlinkPreviews.isEmpty {
                Text("No backlinks yet")
                    .font(DS.caption)
                    .foregroundStyle(focusTextMuted)
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
        VStack(alignment: .leading, spacing: DS.space8) {
            railSectionLabel("MENTIONED IN")
            if mentionedInCounts.isEmpty || mentionedInCounts.values.reduce(0, +) == 0 {
                Text("Not yet referenced")
                    .font(DS.caption)
                    .foregroundStyle(focusTextMuted)
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

    private var resonanceSection: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            HStack(spacing: DS.space6) {
                railSectionLabel("∿  RESONANCE")
                Text("ai")
                    .font(DS.caption2)
                    .foregroundStyle(DS.gilt.opacity(0.6))
                    .italic()
            }

            Text("Ambient adjacencies — notes that sit near this one by tag, theme, and connection graph.")
                .font(DS.caption)
                .foregroundStyle(focusTextMuted)
                .fixedSize(horizontal: false, vertical: true)

            if resonantThemes.isEmpty {
                Text("Tag this note to surface resonances")
                    .font(DS.caption2)
                    .foregroundStyle(focusTextMuted.opacity(0.7))
                    .italic()
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

    private func toggleGraphOverlay() {
        withAnimation(ProMotionSprings.modal) {
            graphOverlayVisible.toggle()
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
        CosmoWindowViewModel.shared.updateContext(provider: provider)
        CosmoWindowPanelController.shared.show()
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

                    tags = fetchedAtom.tagsList
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
        NoteFocusLog.debug("[FOCUS-NOTE] saveAtomImmediately() — uuid=\(atom.uuid) titleLen=\(titlePlainText.count) bodyLen=\(plainContent.count) bodyPreview=\"\(String(plainContent.prefix(80)))\"")
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
            print("Failed to save note (sync): \(error)")
        }
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

// MARK: - Graph Overlay

fileprivate struct NoteGraphOverlayView: View {
    let centerAtom: Atom
    let onClose: () -> Void

    @State private var nodes: [GraphOverlayNode] = []
    @State private var isLoading = true
    @State private var hops: Int = 1

    var body: some View {
        ZStack {
            Rectangle()
                .fill(DS.focusImmersiveBackground.opacity(0.96))
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(spacing: 0) {
                graphTopBar
                graphCanvas
                graphLegend
            }
        }
        .task { await loadNeighborhood() }
        .onChange(of: hops) { _, _ in
            Task { await loadNeighborhood() }
        }
    }

    private var graphTopBar: some View {
        HStack(spacing: DS.space12) {
            Button(action: onClose) {
                HStack(spacing: DS.space4) {
                    Image(systemName: "chevron.left")
                        .font(DS.buttonText)
                    Text("Close")
                        .font(DS.callout)
                }
                .foregroundStyle(DS.focusImmersiveTextSecondary)
                .padding(.horizontal, DS.space12)
                .padding(.vertical, DS.space8)
                .frame(minHeight: 32)
                .background(DS.focusImmersiveBorder.opacity(0.5), in: Capsule())
                .accessibilityLabel("Close graph view")
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])

            Text("GRAPH VIEW  ·  \(centerAtom.title ?? "Untitled")")
                .font(DS.smallCaps)
                .foregroundStyle(DS.gilt)
                .tracking(1)

            Spacer()

            Picker("Hops", selection: $hops) {
                Text("1-hop").tag(1)
                Text("2-hop").tag(2)
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space6)
        .cosmoGlassPanel(role: .floatingAssistant, cornerRadius: 22)
        .padding(.horizontal, DS.space16)
        .padding(.top, DS.space12)
        .padding(.bottom, DS.space8)
    }

    private var graphCanvas: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack {
                // Edges
                ForEach(nodes.indices.filter { nodes[$0].atomUUID != centerAtom.uuid }, id: \.self) { idx in
                    Path { path in
                        path.move(to: center)
                        path.addLine(to: nodes[idx].position(in: geo.size, center: center))
                    }
                    .stroke(DS.gilt.opacity(0.35), style: StrokeStyle(lineWidth: 0.6, lineCap: .round))
                }

                // Nodes
                ForEach(nodes, id: \.atomUUID) { node in
                    graphNodeDot(node: node, in: geo.size, center: center)
                }

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .position(center)
                }
            }
        }
    }

    private func graphNodeDot(node: GraphOverlayNode, in size: CGSize, center: CGPoint) -> some View {
        let isCenter = node.atomUUID == centerAtom.uuid
        let pos = node.position(in: size, center: center)
        return VStack(spacing: DS.space4) {
            Image(systemName: node.type.iconName)
                .font(isCenter ? DS.title3 : DS.caption)
                .foregroundStyle(isCenter ? DS.entityNote : tint(for: node.type))
                .frame(width: isCenter ? 44 : 32, height: isCenter ? 44 : 32)
                .background(
                    Circle()
                        .fill(DS.focusImmersiveSurface)
                        .overlay(Circle().stroke(isCenter ? DS.entityNote : DS.sepiaBorder.opacity(0.6), lineWidth: isCenter ? 1.5 : 0.5))
                )
                .shadow(color: DS.inkWash.opacity(0.1), radius: isCenter ? 10 : 4, y: 2)
                .accessibilityLabel(node.title)
            Text(node.title)
                .font(DS.caption2)
                .foregroundStyle(isCenter ? DS.focusImmersiveText : DS.focusImmersiveTextSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 120)
        }
        .position(pos)
    }

    private var graphLegend: some View {
        HStack(spacing: DS.space16) {
            legendDot(color: DS.entityNote, label: "note")
            legendDot(color: DS.entityIdea, label: "idea")
            legendDot(color: DS.entityContent, label: "content")
            legendDot(color: DS.entitySwipe, label: "swipe")
            Spacer()
        }
        .padding(.horizontal, DS.space24)
        .padding(.vertical, DS.space16)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: DS.space4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(DS.caption)
                .foregroundStyle(DS.focusImmersiveTextMuted)
        }
    }

    private func tint(for type: AtomType) -> Color {
        switch type {
        case .idea: return DS.entityIdea
        case .content: return DS.entityContent
        case .research: return DS.entityResearch
        case .note: return DS.entityNote
        case .task: return DS.entityTask
        default: return DS.focusImmersiveTextSecondary
        }
    }

    @MainActor
    private func loadNeighborhood() async {
        isLoading = true
        defer { isLoading = false }

        guard let result = try? await GraphQueryEngine().getNeighborhood(
            of: centerAtom.uuid,
            depth: hops,
            maxNodesPerLevel: hops == 1 ? 8 : 12
        ) else { return }

        // Hydrate titles via AtomRepository
        let allUUIDs = result.allUUIDs
        let atoms = (try? await AtomRepository.shared.fetchBatch(uuids: allUUIDs)) ?? []
        let byUUID = Dictionary(uniqueKeysWithValues: atoms.map { ($0.uuid, $0) })

        var built: [GraphOverlayNode] = []
        // Center
        built.append(GraphOverlayNode(
            atomUUID: centerAtom.uuid,
            title: centerAtom.title ?? "Untitled",
            type: centerAtom.type,
            angleIndex: 0,
            totalInRing: 1,
            ring: 0
        ))
        for (levelIndex, level) in result.levels.enumerated() {
            let total = max(1, level.count)
            for (i, neighbor) in level.enumerated() {
                guard let a = byUUID[neighbor.node.atomUUID] else { continue }
                built.append(GraphOverlayNode(
                    atomUUID: a.uuid,
                    title: a.title ?? "Untitled",
                    type: a.type,
                    angleIndex: i,
                    totalInRing: total,
                    ring: levelIndex + 1
                ))
            }
        }
        withAnimation(ProMotionSprings.cardEntrance) {
            nodes = built
        }
    }
}

fileprivate struct GraphOverlayNode: Equatable {
    let atomUUID: String
    let title: String
    let type: AtomType
    let angleIndex: Int
    let totalInRing: Int
    let ring: Int

    func position(in size: CGSize, center: CGPoint) -> CGPoint {
        if ring == 0 { return center }
        let radius = CGFloat(ring) * min(size.width, size.height) * 0.28
        let theta = (Double(angleIndex) / Double(max(totalInRing, 1))) * 2 * .pi - .pi / 2
        return CGPoint(
            x: center.x + radius * CGFloat(cos(theta)),
            y: center.y + radius * CGFloat(sin(theta))
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
        return CosmoEditableSourceSnapshot(
            surfaceID: surfaceID,
            targetID: Self.targetID(for: atom.uuid),
            kind: .text,
            title: resolvedTitle.isEmpty ? "Untitled note" : resolvedTitle,
            text: content,
            sourceHash: CosmoEditableSurfaceHasher.hash(content),
            anchors: [
                .init(id: "body", label: "Body", utf16Start: 0, utf16Length: content.utf16.count)
            ]
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
