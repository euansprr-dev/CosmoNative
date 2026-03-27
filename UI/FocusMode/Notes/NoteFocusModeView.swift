// CosmoOS/UI/FocusMode/Notes/NoteFocusModeView.swift
// Full-screen dark-themed writing surface for ideas/notes
// February 2026 - Focus mode with GRDB observation + 1.5s debounce auto-save

import SwiftUI
import GRDB
import Combine

struct NoteFocusModeView: View {
    // MARK: - Properties

    let atom: Atom
    let onClose: () -> Void

    // MARK: - Initialization

    init(atom: Atom, onClose: @escaping () -> Void) {
        self.atom = atom
        self.onClose = onClose
        self._floatingBlocksManager = StateObject(wrappedValue: FocusFloatingBlocksManager(ownerAtomUUID: atom.uuid))
    }

    // MARK: - State

    @StateObject private var floatingBlocksManager: FocusFloatingBlocksManager

    @State private var titleDocument: RichDocument = .empty
    @State private var bodyDocument: RichDocument = .empty
    @State private var titlePlainText: String = ""
    @State private var plainContent: String = ""
    @State private var tags: [String] = []
    @State private var createdAt: Date = Date()
    @State private var showTagEditor = false
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var saveClosed = false
    @State private var observationCancellable: AnyCancellable?
    @State private var isInitialLoad = true

    // Sidebar state
    @State private var sidebarVisible = false
    @State private var linkedAtoms: [Atom] = []

    // Animation states
    @State private var contentAppeared = false
    @State private var titleUnderlineProgress: CGFloat = 0
    @State private var titleEditorHeight: CGFloat = 76
    @State private var bodyEditorHeight: CGFloat = 400
    @State private var scrollViewportHeight: CGFloat = 0
    @State private var pendingObservedTitleDocument: RichDocument?
    @State private var titleDocumentAtEditStart: RichDocument = .empty
    @State private var isEditingTitle = false

    // Save state
    @State private var saveState: SaveState = .idle

    // Writing mode
    @AppStorage("sidebarCollapsed") private var isSidebarHidden: Bool = false
    @AppStorage("typewriterMode") private var typewriterMode = false

    private let database = CosmoDatabase.shared
    private let autoSaveDelay: TimeInterval = 1.5
    private let titleStyle = SharedTitleSurfaceStyle.noteFocus

    @Environment(\.isPaneContext) private var isPaneContext
    @Environment(\.isPaneActive) private var isPaneActive

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
            // Full-bleed dark background
            DS.bg
                .ignoresSafeArea()

            // Main content
            VStack(spacing: 0) {
                // Top bar with gradient
                topBar

                // Scrollable writing surface
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Title field
                        titleSection
                            .padding(.top, DS.space32)

                        // Date + tags row
                        dateTagsRow
                            .padding(.top, DS.space12)
                            .padding(.bottom, DS.space24)

                        // Divider
                        Rectangle()
                            .fill(DS.border)
                            .frame(height: 1)
                            .frame(maxWidth: CosmoTypography.optimalReadingWidth)

                        // Full note body expands to its measured document height.
                        CosmoDocumentEditor(
                            document: $bodyDocument,
                            fontSize: 17,
                            placeholder: "Start writing...",
                            darkMode: false,
                            allowSlashCommands: true,
                            allowMentions: true,
                            allowSelectionMenu: true,
                            allowImages: true,
                            typewriterMode: typewriterMode,
                            scrollsInternally: false,
                            onContentHeightChange: { newHeight in
                                bodyEditorHeight = max(400, newHeight)
                            },
                            onDocumentChange: { _, plainText in
                                let changed = plainText != plainContent
                                print("[FOCUS-NOTE] onDocumentChange(body) — changed=\(changed) len=\(plainText.count) preview=\"\(String(plainText.prefix(60)))\" isInitialLoad=\(isInitialLoad) uuid=\(atom.uuid)")
                                plainContent = plainText
                                if !isInitialLoad { triggerAutoSave() }
                            }
                        )
                        .frame(maxWidth: CosmoTypography.optimalReadingWidth, alignment: .topLeading)
                        .frame(
                            minHeight: max(bodyEditorHeight, scrollViewportHeight - 200),
                            alignment: .topLeading
                        )
                        .padding(.top, DS.space24)
                        .padding(.bottom, DS.space24)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, DS.space40)
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newValue in
                    scrollViewportHeight = newValue
                }
            }

            // Persistent floating blocks overlay
            GeometryReader { geo in
                FocusFloatingBlocksLayer(manager: floatingBlocksManager)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .overlay(alignment: .topLeading) {
            FocusSidebarTrigger(isVisible: $sidebarVisible)
                .frame(maxHeight: .infinity)
        }
        .overlay(alignment: .topLeading) {
            UniversalFocusSidebar(
                title: "Note",
                icon: "doc.text",
                accentColor: DS.accent,
                isVisible: $sidebarVisible,
                isLocked: .constant(false)
            ) {
                noteSidebarContent
            }
            .padding(.leading, DS.space8)
            .padding(.top, 56)
        }
        .focusBlockContextMenu(
            manager: floatingBlocksManager,
            ownerAtomUUID: atom.uuid
        )
        .focusBlockInspector(manager: floatingBlocksManager)
        .onAppear {
            startObservingAtom()
            loadLinkedAtoms()
            listenForAtomPicker()
            titleEditorHeight = titleMinHeight
            bodyEditorHeight = 400
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(ProMotionSprings.cardEntrance) {
                    contentAppeared = true
                }
            }
            // Register context provider for global Cosmo window
            let provider = NoteContextProvider(atom: atom, titleRef: { [self] in self.titlePlainText }, contentRef: { [self] in self.plainContent }, tagsRef: { [self] in self.tags })
            if !isPaneContext || isPaneActive {
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
        .onChange(of: isPaneActive) { _, isActive in
            if isActive {
                let provider = NoteContextProvider(atom: atom, titleRef: { [self] in self.titlePlainText }, contentRef: { [self] in self.plainContent }, tagsRef: { [self] in self.tags })
                CosmoWindowViewModel.shared.updateContext(provider: provider)
            }
        }
        .onDisappear {
            print("[FOCUS-NOTE] onDisappear — uuid=\(atom.uuid) titleLen=\(titlePlainText.count) bodyLen=\(plainContent.count) bodyPreview=\"\(String(plainContent.prefix(80)))\"")
            // Force an immediate save before closing — don't lose unsaved edits
            autoSaveTask?.cancel()
            saveClosed = true  // Block any in-flight async writes from overwriting
            saveAtomImmediately()
            floatingBlocksManager.saveImmediately()
            observationCancellable?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmoAppWillTerminate)) { _ in
            autoSaveTask?.cancel()
            saveClosed = true
            saveAtomImmediately()
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
        .onChange(of: isEditingTitle) { _, isEditing in
            if isEditing {
                titleDocumentAtEditStart = titleDocument
                pendingObservedTitleDocument = nil
                titleEditorHeight = min(titleEditingMaxHeight, max(titleMinHeight, titleEditorHeight))
            } else {
                if let pendingObservedTitleDocument, titleDocument == titleDocumentAtEditStart {
                    applyObservedTitleDocument(pendingObservedTitleDocument)
                }
                pendingObservedTitleDocument = nil
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: DS.space16) {
            // Main sidebar toggle (standalone only)
            if !isPaneContext {
                Button {
                    withAnimation(ProMotionSprings.sidebar) {
                        isSidebarHidden.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isSidebarHidden ? DS.textMuted : DS.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(DS.border, in: Circle())
                }
                .buttonStyle(.plain)
                .help(isSidebarHidden ? "Show sidebar (⌘\\)" : "Hide sidebar (⌘\\)")
            }

            // Back button (hidden in pane mode -- X button handles close)
            if !isPaneContext {
                Button(action: onClose) {
                    HStack(spacing: DS.space6) {
                        Image(systemName: "chevron.left")
                            .font(DS.buttonText)
                        Text("Back")
                            .font(DS.callout)
                    }
                    .foregroundStyle(DS.textSecondary)
                    .padding(.horizontal, DS.space12)
                    .padding(.vertical, DS.space8)
                    .background(DS.border, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            // Type badge
            HStack(spacing: DS.space4) {
                Image(systemName: "note.text")
                    .font(DS.caption2)
                Text("NOTE")
                    .font(DS.caption2)
                    .tracking(0.8)
            }
            .foregroundStyle(DS.entityNote)
            .padding(.horizontal, DS.space8)
            .padding(.vertical, DS.space4)
            .background(DS.entityNote.opacity(DS.opacitySubtle), in: Capsule())

            // Save indicator
            if saveState != .idle {
                noteSaveBadge
                    .transition(.scale.combined(with: .opacity))
            }

            Spacer()

            // Focus mode sidebar toggle
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    sidebarVisible.toggle()
                }
            } label: {
                Image(systemName: "sidebar.right")
                    .font(DS.callout)
                    .foregroundStyle(sidebarVisible ? DS.accent : DS.textSecondary)
                    .padding(DS.space8)
                    .background(
                        sidebarVisible ? DS.accent.opacity(0.15) : DS.border,
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)

            // Typewriter mode toggle
            Button {
                withAnimation(ProMotionSprings.snappy) { typewriterMode.toggle() }
            } label: {
                Image(systemName: typewriterMode ? "line.3.horizontal.circle.fill" : "line.3.horizontal.circle")
                    .font(DS.callout)
                    .foregroundStyle(typewriterMode ? DS.accent : DS.textMuted)
                    .frame(width: 28, height: 28)
                    .background(typewriterMode ? DS.accent.opacity(0.12) : DS.border, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Typewriter mode — cursor stays centered")

            // Pane close button
            if isPaneContext {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(DS.buttonText)
                        .foregroundStyle(DS.textMuted)
                        .frame(width: 28, height: 28)
                        .background(DS.border, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DS.space20)
        .padding(.vertical, DS.space12)
        .background(
            LinearGradient(
                colors: [
                    DS.bg.opacity(0.95),
                    DS.bg.opacity(0.8),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Title Section

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if isEditingTitle {
                    CosmoDocumentEditor(
                        document: $titleDocument,
                        fontSize: titleFontSize,
                        compact: titleStyle.compact,
                        placeholder: "Untitled Note",
                        darkMode: false,
                        allowSlashCommands: false,
                        allowMentions: true,
                        allowSelectionMenu: false,
                        allowImages: false,
                        titleConfiguration: titleStyle.titleConfiguration,
                        baseFontWeight: titleStyle.baseFontWeight,
                        scrollsInternally: false,
                        onContentHeightChange: { newHeight in
                            titleEditorHeight = min(titleEditingMaxHeight, max(titleMinHeight, newHeight))
                        },
                        onPlainTextChange: { plainText in
                            titlePlainText = plainText
                            withAnimation(ProMotionSprings.bouncy) {
                                titleUnderlineProgress = plainText.isEmpty ? 0.28 : 1
                            }
                        },
                        onStructuredDocumentChange: { document, plainText in
                            print("[FOCUS-NOTE] onDocumentChange(title) — len=\(plainText.count) preview=\"\(String(plainText.prefix(60)))\" isInitialLoad=\(isInitialLoad) uuid=\(atom.uuid)")
                            titleDocument = document
                            titlePlainText = plainText
                            withAnimation(ProMotionSprings.bouncy) {
                                titleUnderlineProgress = plainText.isEmpty ? 0.28 : 1
                            }
                            if !isInitialLoad { triggerAutoSave() }
                        },
                        onActivate: { isEditingTitle = true },
                        onDeactivate: { isEditingTitle = false },
                        onCommit: { isEditingTitle = false },
                        autoFocus: true
                    )
                    .frame(height: min(titleEditingMaxHeight, max(titleMinHeight, titleEditorHeight)))
                } else {
                    Text(titlePlainText.isEmpty ? "Untitled Note" : titlePlainText)
                        .font(titleStyle.swiftUIFont)
                        .foregroundStyle(titlePlainText.isEmpty ? DS.textMuted : DS.text)
                        .lineLimit(titleStyle.previewLineLimit)
                        .truncationMode(.tail)
                        .multilineTextAlignment(titleStyle.swiftUITextAlignment)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: titleMinHeight, alignment: .topLeading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            titleDocumentAtEditStart = titleDocument
                            isEditingTitle = true
                        }
                }
            }

            // Animated underline
            GeometryReader { geo in
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                DS.entityNote.opacity(titleUnderlineProgress * 0.8),
                                DS.entityNote.opacity(titleUnderlineProgress * 0.4),
                                DS.entityNote.opacity(0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * max(0.16, titleUnderlineProgress), height: 2)
                    .shadow(
                        color: DS.entityNote.opacity(titleUnderlineProgress * 0.4),
                        radius: 4,
                        y: 2
                    )
            }
            .frame(height: 2)
        }
        .frame(maxWidth: CosmoTypography.optimalReadingWidth, alignment: .leading)
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
                .foregroundStyle(DS.textSecondary)

            // Tags
            if !tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(DS.caption)
                            .foregroundStyle(DS.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(DS.border, in: Capsule())
                    }
                    if tags.count > 3 {
                        Text("+\(tags.count - 3)")
                            .font(DS.caption)
                            .foregroundStyle(DS.textMuted)
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
                .foregroundStyle(DS.textMuted)
                .padding(.horizontal, DS.space8)
                .padding(.vertical, DS.space4)
                .background(DS.border, in: Capsule())
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
        .foregroundStyle(saveState == .saved ? DS.entityNote : DS.textSecondary)
        .padding(.horizontal, DS.space8)
        .padding(.vertical, DS.space4)
        .background(
            Capsule()
                .fill(
                    saveState == .saved
                        ? DS.entityNote.opacity(0.15)
                        : DS.border
                )
        )
    }

    // MARK: - Computed Properties

    private var wordCount: Int {
        plainContent.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    // MARK: - Sidebar Content

    private var noteSidebarContent: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            if linkedAtoms.isEmpty {
                Text("No linked items")
                    .font(DS.callout)
                    .foregroundStyle(DS.textMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, DS.space20)
            } else {
                Text("LINKED ITEMS")
                    .dsSectionLabel()

                ForEach(linkedAtoms, id: \.uuid) { linked in
                    HStack(spacing: DS.space8) {
                        Image(systemName: linked.type.iconName)
                            .font(DS.footnote)
                            .foregroundStyle(DS.textSecondary)

                        Text(linked.title ?? "Untitled")
                            .font(DS.subheadline)
                            .foregroundStyle(DS.text)
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(.vertical, DS.space4)
                }
            }
        }
    }

    private func loadLinkedAtoms() {
        Task {
            let edges = try? await GraphQueryEngine().getEdges(for: atom.uuid)
            let uuids = (edges ?? []).map { $0.sourceUUID == atom.uuid ? $0.targetUUID : $0.sourceUUID }
            var atoms: [Atom] = []
            for uuid in uuids.prefix(20) {
                if let a = try? await AtomRepository.shared.fetch(uuid: uuid) {
                    atoms.append(a)
                }
            }
            await MainActor.run { linkedAtoms = atoms }
        }
    }

    // MARK: - Floating Block Listeners

    /// Listen for atom picker notifications to add existing atoms as floating blocks
    private func listenForAtomPicker() {
        NotificationCenter.default.addObserver(
            forName: CosmoNotification.FocusMode.addAtomAsFloatingBlock,
            object: nil,
            queue: .main
        ) { [self] notification in
            guard !self.isPaneContext || self.isPaneActive else { return }
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
                    print("[FOCUS-NOTE] 🔔 GRDB observation fired — uuid=\(atom.uuid) isInitialLoad=\(isInitialLoad) isEditingTitle=\(isEditingTitle) dbBodyLen=\(nextBodyPlainText.count) localBodyLen=\(plainContent.count) dbBodyPreview=\"\(String(nextBodyPlainText.prefix(60)))\" localBodyPreview=\"\(String(plainContent.prefix(60)))\"")

                    if !isEditingTitle,
                       (nextTitlePlainText != titlePlainText || nextTitleDocument != titleDocument) {
                        print("[FOCUS-NOTE] 🔔 observation APPLYING title — uuid=\(atom.uuid)")
                        applyObservedTitleDocument(nextTitleDocument)
                    } else if isEditingTitle,
                              (nextTitlePlainText != titlePlainText || nextTitleDocument != titleDocument) {
                        print("[FOCUS-NOTE] 🔔 observation DEFERRED title (editing) — uuid=\(atom.uuid)")
                        pendingObservedTitleDocument = nextTitleDocument
                    }

                    // Only overwrite body from DB during initial load —
                    // after that, the user is always editing and observation echoes
                    // from auto-save would overwrite text typed since save started.
                    if isInitialLoad,
                       nextBodyPlainText != plainContent || nextBodyDocument != bodyDocument {
                        print("[FOCUS-NOTE] 🔔 observation APPLYING body (initialLoad) — uuid=\(atom.uuid) dbLen=\(nextBodyPlainText.count)")
                        bodyDocument = nextBodyDocument
                        plainContent = nextBodyPlainText
                    } else if !isInitialLoad, nextBodyPlainText != plainContent {
                        print("[FOCUS-NOTE] 🔔 observation SKIPPED body (not initialLoad) — uuid=\(atom.uuid) dbLen=\(nextBodyPlainText.count) localLen=\(plainContent.count) ⚠️ DIVERGED=\(nextBodyPlainText != plainContent)")
                    }

                    tags = fetchedAtom.tagsList
                    if let date = ISO8601DateFormatter().date(from: fetchedAtom.createdAt) {
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

    private func triggerAutoSave() {
        print("[FOCUS-NOTE] triggerAutoSave() — \(autoSaveDelay)s debounce starting uuid=\(atom.uuid)")
        autoSaveTask?.cancel()
        autoSaveTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(autoSaveDelay * 1_000_000_000))
                guard !Task.isCancelled else {
                    print("[FOCUS-NOTE] triggerAutoSave() CANCELLED uuid=\(atom.uuid)")
                    return
                }
                print("[FOCUS-NOTE] triggerAutoSave() debounce elapsed, calling saveAtom() uuid=\(atom.uuid)")
                await MainActor.run { saveAtom() }
            } catch {
                // Cancelled
            }
        }
    }

    /// Debounced save with UI feedback (used during editing)
    private func saveAtom() {
        print("[FOCUS-NOTE] saveAtom() — uuid=\(atom.uuid) titleLen=\(titlePlainText.count) bodyLen=\(plainContent.count) bodyPreview=\"\(String(plainContent.prefix(80)))\"")

        withAnimation(ProMotionSprings.snappy) {
            saveState = .saving
        }
        performSave { success in
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
        print("[FOCUS-NOTE] saveAtomImmediately() — uuid=\(atom.uuid) titleLen=\(titlePlainText.count) bodyLen=\(plainContent.count) bodyPreview=\"\(String(plainContent.prefix(80)))\"")
        let titleDocumentCopy = titleDocument
        let bodyDocumentCopy = bodyDocument
        let uuid = atom.uuid

        do {
            try database.write { db in
                var existingMetadata: String?
                if let row = try Row.fetchOne(db, sql: "SELECT metadata FROM atoms WHERE uuid = ?", arguments: [uuid]) {
                    existingMetadata = row["metadata"]
                }

                let fields = RichDocumentPersistence.writeAtomDocuments(
                    existingMetadata: existingMetadata,
                    titleDocument: titleDocumentCopy,
                    bodyDocument: bodyDocumentCopy
                )

                var metadataDict: [String: Any] = [:]
                if let metadata = fields.metadata,
                   let data = metadata.data(using: .utf8),
                   let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    metadataDict = decoded
                }
                if tags.isEmpty {
                    metadataDict.removeValue(forKey: "tags")
                } else {
                    metadataDict["tags"] = tags
                }
                let metadataString = (try? JSONSerialization.data(withJSONObject: metadataDict)).flatMap { String(data: $0, encoding: .utf8) }

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
                        fields.title,
                        fields.body ?? "",
                        metadataString ?? fields.metadata,
                        ISO8601DateFormatter().string(from: Date()),
                        uuid
                    ]
                )
            }
            // Post notification for immediate canvas update (sync path)
            var userInfo: [String: Any] = [
                "atomUUID": uuid,
                "title": titleDocumentCopy.plainText,
                "body": bodyDocumentCopy.plainText
            ]
            if let bodyDocData = try? JSONEncoder().encode(bodyDocumentCopy),
               let bodyDocString = String(data: bodyDocData, encoding: .utf8) {
                userInfo["bodyDocumentJSON"] = bodyDocString
            }
            if let titleDocData = try? JSONEncoder().encode(titleDocumentCopy),
               let titleDocString = String(data: titleDocData, encoding: .utf8) {
                userInfo["titleDocumentJSON"] = titleDocString
            }
            NotificationCenter.default.post(
                name: .noteFocusStateDidChange,
                object: nil,
                userInfo: userInfo
            )
            // Sync: queue for Supabase push
            Task {
                if let updatedAtom = try? await database.asyncRead({ db in
                    try Atom.filter(Column("uuid") == uuid).fetchOne(db)
                }) {
                    await ChangeTracker.shared.trackUpdate(table: "atoms", entity: updatedAtom)
                }
            }
        } catch {
            print("Failed to save note (sync): \(error)")
        }
    }

    /// Async save with completion callback (used for debounced auto-save during editing)
    private func performSave(completion: ((Bool) -> Void)?) {
        let titleDocumentCopy = titleDocument
        let bodyDocumentCopy = bodyDocument
        let titleCopy = titlePlainText
        let contentCopy = plainContent
        let uuid = atom.uuid
        print("[FOCUS-NOTE] performSave() — uuid=\(uuid) titleLen=\(titleCopy.count) bodyLen=\(contentCopy.count) bodyPreview=\"\(String(contentCopy.prefix(80)))\"")

        Task {
            // Skip if sync save already ran on close — prevents stale async write
            // from overwriting the final save
            guard !saveClosed else {
                print("[FOCUS-NOTE] performSave() SKIPPED — saveClosed=true uuid=\(uuid)")
                return
            }
            print("[FOCUS-NOTE] performSave() async DB write starting — uuid=\(uuid)")
            do {
                try await database.asyncWrite { db in
                    var existingMetadata: String?
                    if let row = try Row.fetchOne(db, sql: "SELECT metadata FROM atoms WHERE uuid = ?", arguments: [uuid]) {
                        existingMetadata = row["metadata"]
                    }

                    let fields = RichDocumentPersistence.writeAtomDocuments(
                        existingMetadata: existingMetadata,
                        titleDocument: titleDocumentCopy,
                        bodyDocument: bodyDocumentCopy
                    )

                    var metadataDict: [String: Any] = [:]
                    if let metadata = fields.metadata,
                       let data = metadata.data(using: .utf8),
                       let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        metadataDict = decoded
                    }
                    if tags.isEmpty {
                        metadataDict.removeValue(forKey: "tags")
                    } else {
                        metadataDict["tags"] = tags
                    }
                    let metadataString = (try? JSONSerialization.data(withJSONObject: metadataDict)).flatMap { String(data: $0, encoding: .utf8) }

                    try db.execute(
                        sql: """
                        UPDATE atoms
                        SET title = ?,
                            body = ?,
                            metadata = ?,
                            updated_at = ?,
                            _local_version = _local_version + 1
                        WHERE uuid = ?
                        """,
                        arguments: [
                            fields.title,
                            fields.body ?? "",
                            metadataString ?? fields.metadata,
                            ISO8601DateFormatter().string(from: Date()),
                            uuid
                        ]
                    )
                }
                // Notify floating blocks to reload immediately (GRDB observation is backup)
                await MainActor.run {
                    var userInfo: [String: Any] = ["atomUUID": uuid, "title": titleCopy, "body": contentCopy]
                    if let bodyDocData = try? JSONEncoder().encode(bodyDocumentCopy),
                       let bodyDocString = String(data: bodyDocData, encoding: .utf8) {
                        userInfo["bodyDocumentJSON"] = bodyDocString
                    }
                    if let titleDocData = try? JSONEncoder().encode(titleDocumentCopy),
                       let titleDocString = String(data: titleDocData, encoding: .utf8) {
                        userInfo["titleDocumentJSON"] = titleDocString
                    }
                    NotificationCenter.default.post(
                        name: .noteFocusStateDidChange,
                        object: nil,
                        userInfo: userInfo
                    )
                    NotificationCenter.default.post(
                        name: .richDocumentDidChange,
                        object: nil,
                        userInfo: ["atomUUID": uuid]
                    )
                }
                // Sync: queue for Supabase push so notes sync to cloud
                if let updatedAtom = try? await database.asyncRead({ db in
                    try Atom.filter(Column("uuid") == uuid).fetchOne(db)
                }) {
                    await ChangeTracker.shared.trackUpdate(table: "atoms", entity: updatedAtom)
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
    }
}

// MARK: - Cosmo Context Provider

@MainActor
class NoteContextProvider: CosmoContextProvider {
    private let atom: Atom
    private let titleRef: () -> String
    private let contentRef: () -> String
    private let tagsRef: () -> [String]

    init(atom: Atom, titleRef: @escaping () -> String, contentRef: @escaping () -> String, tagsRef: @escaping () -> [String]) {
        self.atom = atom
        self.titleRef = titleRef
        self.contentRef = contentRef
        self.tagsRef = tagsRef
    }

    var contextType: CosmoContextType { .noteFocusMode }

    var contextSummary: String {
        let title = titleRef()
        let words = contentRef().split(separator: " ").count
        return "Note: \(title.isEmpty ? "Untitled" : title) (\(words) words)"
    }

    var contextData: CosmoContextData {
        let content = contentRef()
        let tags = tagsRef()
        return CosmoContextData(
            currentAtomUUID: atom.uuid,
            currentAtomType: "note",
            currentAtomTitle: titleRef(),
            viewSpecificData: [
                "wordCount": "\(content.split(separator: " ").count)",
                "tags": tags.joined(separator: ", "),
                "contentPreview": String(content.prefix(500))
            ]
        )
    }

    var availableActions: [CosmoWindowAction] { [] }
}
