import AppKit
import SwiftUI

/// One Page host for a Space, search result, standalone window, or pane.
/// Focus changes the surrounding layout; the title, scroll view, and live block
/// editors keep their identity and their undo registrations throughout.
struct UnifiedPageView: View {
    let atom: Atom
    var spaceID: String?
    var onClose: (() -> Void)?
    var initialBlockID: UUID?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.pageFocusPresentation) private var inheritedFocus
    @Environment(\.pageFocusPaneID) private var paneID
    @Environment(\.unifiedPageNavigationInset) private var navigationInset
    @Environment(\.isPaneContext) private var isPaneContext
    @Environment(\.isPaneContextOwner) private var isPaneContextOwner
    @Environment(\.cosmoFloatingPanelIsVisible) private var panelIsVisible
    @Environment(\.pageAtmosphereHosted) private var atmosphereHosted
    @State private var localFocus = PageFocusPresentation()
    @State private var session: SpacePageEditorSession
    @State private var assistant: UnifiedPageAssistant
    @State private var activeSectionSession: SpacePageEditorSession?
    @State private var activeSectionAssistant: UnifiedPageAssistant?
    @State private var viewport = UnifiedPageViewport()
    @State private var observation: CanvasAtomSubscription?
    @State private var navigationBlockID: UUID?
    @State private var showsStyle = false
    @State private var showsHistory = false
    @State private var showsTags = false
    @State private var showsContextSheet = false
    @State private var shareText: String?
    @State private var operationError: String?
    @State private var busy = false
    @State private var preview: SpaceCompositionExportSnapshot?
    @State private var creating: SpaceCompositionKind?
    @State private var organizing: SpaceWorkspaceOrganizeAction?
    @State private var contentIdea: Atom?
    @State private var wordCount = 0
    @AppStorage("typewriterMode") private var typewriterMode = false
    @AppStorage("noteParagraphFocus") private var paragraphFocus = false
    // Fresh keys: the Notes-era rails defaulted on and left `true` persisted
    // for everyone. A Page opens without a panel; the toggles stay one click away.
    @AppStorage("page.outlinePanel") private var outlineVisible = false
    @AppStorage("page.contextPanel") private var contextVisible = false

    init(atom: Atom, spaceID: String? = nil, onClose: (() -> Void)? = nil, initialBlockID: UUID? = nil) {
        self.atom = atom
        self.spaceID = spaceID
        self.onClose = onClose
        self.initialBlockID = initialBlockID
        let editingSession = SpacePageEditorStore.shared.session(for: atom)
        _session = State(initialValue: editingSession)
        _assistant = State(initialValue: UnifiedPageAssistant(session: editingSession))
        _navigationBlockID = State(initialValue: initialBlockID)
    }

    private var focus: PageFocusPresentation { inheritedFocus ?? localFocus }
    private var isFocused: Bool { focus.focusedPageUUID == atom.uuid && focus.focusedPaneID == paneID }
    private var style: NoteDocumentStyle { session.style }
    private var paper: Color { style.paperTone.pageColor(darkMode: colorScheme == .dark) ?? DS.bg }
    private var atmosphere: PageAtmosphere { PageAtmosphere(style: style, darkMode: colorScheme == .dark) }
    private var readingWidth: CGFloat { style.pageWidth.readingWidth(for: style.textSize) }
    private var store: SpaceWorkspaceStore { .shared }
    private var showsPanel: Bool { !isFocused && (outlineVisible || contextVisible || sourcesVisible) }
    private var sourcesVisible: Bool { spaceID.map { store.location($0).sourcesVisible } ?? false }
    private var options: [SpaceCompositionView] { spaceID.map { store.views(for: atom, in: $0) } ?? [.write] }
    private var contextSession: SpacePageEditorSession { activeSectionSession ?? session }
    private var contextAssistant: UnifiedPageAssistant { activeSectionAssistant ?? assistant }
    private var sections: [SpaceCompositionSection] {
        guard let spaceID else { return [] }
        return store.snapshots[spaceID]?.orderedSections(of: atom.uuid, includedOnly: false)
            .filter { $0.atom.uuid != atom.uuid } ?? []
    }
    private var manuscriptText: String {
        ([session.document.plainText] + sections.map { $0.atom.body ?? "" }).joined(separator: "\n\n")
    }

    var body: some View {
        GeometryReader { geometry in
            pageLayout(width: geometry.size.width, height: geometry.size.height)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        // Paper and cover pour across the whole host, never a block in the
        // column. A space or focus host paints them under its floating chrome
        // instead; this Page then publishes and stays transparent.
        .background { if !atmosphereHosted { PageAtmosphereBackground(atmosphere: atmosphere) } }
        .preference(key: PageAtmospherePreferenceKey.self, value: atmosphereHosted ? atmosphere : nil)
        .environment(\.pageFocusPresentation, focus)
        .cosmoSurfaceKeyWindowActivation(surfaceID: "note:\(contextSession.atom.uuid)")
        .modifier(UnifiedPageLifecycle(page: self))
        .sheet(isPresented: $showsHistory) { AtomHistorySheet(atom: session.atom) { showsHistory = false } }
        .sheet(isPresented: $showsTags) { TagEditorSheet(tags: tagsBinding) }
        .sheet(item: $preview) { SpaceExportPreviewView(snapshot: $0) }
        .sheet(item: $contentIdea) { PageContentIdeaSheet(source: $0) }
        .sheet(item: $creating) { kind in
            if let spaceID { SpaceWorkspaceCreateSheet(spaceID: spaceID, kind: kind, parent: session.atom) }
        }
        .sheet(item: $organizing) { action in
            if let spaceID { SpaceWorkspaceOrganizeSheet(spaceID: spaceID, source: session.atom, action: action) }
        }
        .alert("Couldn't finish this action", isPresented: Binding(get: { operationError != nil }, set: { if !$0 { operationError = nil } })) {
            Button("OK", role: .cancel) { operationError = nil }
        } message: { Text(operationError ?? "Your writing remains on this page.") }
        .accessibilityIdentifier("page.unified.\(atom.uuid)")
    }

    private func pageLayout(width: CGFloat, height: CGFloat) -> some View {
        let panelWidth: CGFloat = showsPanel && width >= 960 ? 304 : 0
        return VStack(spacing: 0) {
            header(width: width)
            workspaceError
            // A hairline across a cover wash reads as a seam; the wash itself
            // separates header from manuscript.
            Divider().overlay(DS.borderSubtle).opacity(isFocused || style.cover != .none ? 0 : 1)
            HStack(spacing: 0) {
                manuscript(width: max(1, width - panelWidth), height: height)
                    .frame(width: max(1, width - panelWidth), alignment: .topLeading)
                    .frame(maxHeight: .infinity)
                contextPanel
                    .frame(width: panelWidth)
                    .clipped().opacity(showsPanel && width >= 960 ? 1 : 0)
                    .allowsHitTesting(showsPanel && width >= 960)
                    .accessibilityHidden(!showsPanel || width < 960)
            }
        }
        .overlay(alignment: .topTrailing) { focusExit }
        .sheet(isPresented: Binding(get: { showsContextSheet && !isFocused }, set: { showsContextSheet = $0 })) {
            VStack(spacing: 0) {
                HStack { Text("Page panels").font(DS.headline); Spacer(); Button("Done") { showsContextSheet = false }.keyboardShortcut(.cancelAction) }
                    .padding(DS.space16)
                contextPanel
            }.frame(width: 380, height: 620).background(DS.bg)
        }
        .onChange(of: showsPanel) { _, visible in
            if visible && width < 960 { showsContextSheet = true }
        }
    }

    @ViewBuilder private var workspaceError: some View {
        if let spaceID, let error = store.errors[spaceID] {
            HStack(spacing: DS.space12) {
                Image(systemName: "exclamationmark.circle")
                Text(error).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Retry") { Task { await store.load(spaceID) } }
            }.font(DS.caption).foregroundStyle(DS.textSecondary).padding(DS.space16)
                .accessibilityElement(children: .combine)
        }
    }

    private func header(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            breadcrumbs
                .padding(.bottom, DS.space8)
                .frame(height: isFocused ? 0 : nil, alignment: .top).clipped()
                .opacity(isFocused ? 0 : 1).allowsHitTesting(!isFocused).accessibilityHidden(isFocused)
            let titleLayout = width < 680 && !isFocused
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.space8))
                : AnyLayout(HStackLayout(alignment: .center, spacing: DS.space16))
            titleLayout {
                UnifiedPageTitle(session: session, onActivate: { activate(session, assistant: assistant) })
                    .frame(maxWidth: .infinity, alignment: .leading)
                toolbar(width: width)
                    .frame(width: isFocused ? 0 : nil, alignment: .trailing).clipped()
                    .opacity(isFocused ? 0 : 1).allowsHitTesting(!isFocused).accessibilityHidden(isFocused)
            }
            HStack(spacing: DS.space6) {
                Text(session.atom.spaceCompositionKind?.title ?? "Page")
                if wordCount > 0 {
                    Text("·")
                    Text("\(wordCount) words · \(max(1, Int(ceil(Double(wordCount) / 220)))) min")
                        .monospacedDigit().contentTransition(.numericText())
                }
            }.font(DS.caption).foregroundStyle(DS.textMuted)
                .padding(.top, DS.space4)
                .frame(height: isFocused ? 0 : nil).clipped().opacity(isFocused ? 0 : 1)
                .accessibilityHidden(isFocused)
            if options.count > 1 { representationPicker.frame(height: isFocused ? 0 : nil).clipped().opacity(isFocused ? 0 : 1).allowsHitTesting(!isFocused).accessibilityHidden(isFocused) }
        }
        .frame(width: isFocused ? min(readingWidth, max(1, width - DS.space32 * 2)) : max(1, width - DS.space32 * 2), alignment: .leading)
        .frame(width: max(1, width - DS.space32 * 2))
        .padding(.horizontal, DS.space32)
        .padding(.top, isFocused ? DS.space40 : DS.space20)
        .padding(.bottom, isFocused ? DS.space20 : DS.space16)
        .transaction { $0.animation = nil }
    }

    private var breadcrumbs: some View {
        HStack(spacing: DS.space8) {
            if let spaceID {
                Button("Canvas") { store.showRoot(.canvas, in: spaceID) }.help("Back to the Canvas")
                ForEach(ancestors, id: \.uuid) { ancestor in
                    Image(systemName: "chevron.right").font(DS.caption2).accessibilityHidden(true)
                    Button(ancestor.title ?? "Untitled") { store.open(ancestor, in: spaceID) }.lineLimit(1)
                }
            } else if let onClose {
                Button(action: onClose) { Label("Back", systemImage: "chevron.left") }.help("Return to where you opened this Page")
            } else {
                Label("Page", systemImage: "doc.text")
            }
            Spacer(minLength: 0)
        }.font(DS.caption).buttonStyle(.plain).foregroundStyle(DS.textMuted)
            .padding(.leading, navigationInset)
            .frame(minHeight: navigationInset > 0 ? 40 : 24)
    }

    private var ancestors: [Atom] {
        guard let spaceID, let snapshot = store.snapshots[spaceID] else { return [] }
        return Array(CommandKSpaceService.navigationPath(to: atom.uuid, in: snapshot).dropLast())
    }

    private var representationPicker: some View {
        CosmoSegmentedSwitcher(options: options, label: { $0.title }, selection: Binding(
            get: { .write }, set: { if let spaceID { store.selectView($0, in: spaceID) } }))
            .fixedSize().padding(.top, DS.space12).accessibilityLabel("View")
    }

    private func toolbar(width: CGFloat) -> some View {
        HStack(spacing: DS.space4) {
            UnifiedPageToolbarButton(symbol: "textformat", label: "Page appearance", active: showsStyle) { showsStyle.toggle() }
                .popover(isPresented: $showsStyle, arrowEdge: .bottom) {
                    NotePageStylePopover(style: styleBinding, typewriterMode: $typewriterMode, paragraphFocus: $paragraphFocus,
                        leftRailVisible: $outlineVisible, rightRailVisible: $contextVisible)
                }
            Menu {
                Toggle("Outline", isOn: $outlineVisible)
                Toggle("Page details and backlinks", isOn: $contextVisible)
                if let spaceID {
                    Toggle("Space references", isOn: Binding(get: { sourcesVisible }, set: { if $0 != sourcesVisible { store.toggleSources(in: spaceID) } }))
                }
                Divider()
                Button("Edit tags…", systemImage: "tag") { showsTags = true }
                if width < 960 { Button("Open panels", systemImage: "sidebar.right") { showsContextSheet = true } }
            } label: { Image(systemName: "sidebar.right").frame(width: 44, height: 44) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Page panels").accessibilityLabel("Page panels")
            UnifiedPageToolbarButton(symbol: "arrow.up.left.and.arrow.down.right", label: "Focus (⌘.)", active: isFocused, action: toggleFocus)
                .keyboardShortcut(".", modifiers: .command)
            UnifiedPageToolbarButton(symbol: "square.and.arrow.up", label: "Share page", active: shareText != nil, action: prepareShare)
                .popover(isPresented: Binding(get: { shareText != nil }, set: { if !$0 { shareText = nil } })) { sharePopover }
            moreMenu
        }.foregroundStyle(DS.textSecondary)
    }

    private var moreMenu: some View {
        Menu {
            Button("Version history…", systemImage: "clock.arrow.circlepath", action: openHistory)
            Button("Edit tags…", systemImage: "tag") { showsTags = true }
            Button("Ask Cosmo…", systemImage: "sparkle") { contextAssistant.openAssistant() }
            Button("Create content idea…", systemImage: "lightbulb", action: prepareContentIdea)
            if let spaceID {
                Divider()
                Button("New section", systemImage: "doc.badge.plus") { creating = .page }
                Button("Attach reference…", systemImage: "link", action: addReference)
                Button("Move into…", systemImage: "folder") { organizing = .move }
                Button("Adapt into a new piece…", systemImage: "arrow.triangle.branch") { organizing = .adapt }
                Divider()
                Button("Preview and export…", systemImage: "square.and.arrow.up", action: export)
                Toggle("Include in export", isOn: Binding(get: { session.atom.spaceComposition?.includeInExport ?? true }, set: { included in
                    store.perform(in: spaceID) { try await SpaceCompositionService.setIncludedInExport(included, for: atom.uuid) }
                }))
            }
        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().disabled(busy)
            .help("Page actions").accessibilityLabel("Page actions")
    }

    private func manuscript(width: CGFloat, height: CGFloat) -> some View {
        let availableWidth = max(1, width - DS.space24 * 2 - BlockInteractionPolicy.gutterWidth)
        let editorWidth = min(readingWidth + BlockInteractionPolicy.gutterWidth, availableWidth)
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .center, spacing: DS.space32) {
                    if style.pageIcon != nil { identity.frame(width: editorWidth, alignment: .leading) }
                    SpacePageEditor(session: session, initialBlockID: navigationBlockID,
                        minimumBodyHeight: sections.isEmpty ? max(220, height - 300) : 44,
                        typewriterMode: typewriterMode, paragraphFocus: paragraphFocus, showsSaveStatus: !isFocused,
                        onSelectionChanged: { snapshot in
                            if snapshot.range.location != NSNotFound { activate(session, assistant: assistant) }
                            assistant.reportSelection(snapshot)
                        })
                        .frame(width: editorWidth)
                        .id(atom.uuid)
                    LazyVStack(alignment: .center, spacing: DS.space48) {
                        ForEach(sections) { section in
                            UnifiedPageManuscriptSection(atom: section.atom, spaceID: spaceID,
                                availableWidth: availableWidth,
                                typewriterMode: typewriterMode, paragraphFocus: paragraphFocus, showsSaveStatus: !isFocused,
                                onActivate: activate)
                                .id(section.atom.uuid)
                        }
                    }
                }
                .padding(.leading, DS.space24)
                .padding(.trailing, DS.space24 + BlockInteractionPolicy.gutterWidth)
                .padding(.vertical, DS.space32)
                .frame(width: width, alignment: .top)
                .background(CosmoInlineReviewScrollResolver { viewport.attach($0) })
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onChange(of: navigationBlockID) { _, block in
                if let block { proxy.scrollTo(block, anchor: .center) }
            }
            .onAppear { landSearch(using: proxy) }
            .overlay { reviewOverlay }
        }
    }

    /// The page's mark. Its cover no longer lives in the column — the wash
    /// pours from the host's top edge (`PageAtmosphereBackground`).
    @ViewBuilder private var identity: some View {
        if let icon = style.pageIcon {
            NotePageIconView(icon: icon, style: style, darkMode: colorScheme == .dark, size: 30, seated: true)
                .padding(.leading, BlockInteractionPolicy.gutterWidth)
        }
    }

    @ViewBuilder private var reviewOverlay: some View {
        if let proposal = contextAssistant.reviewProposal {
            ScrollView {
                CosmoInlineDiffReviewView(store: CosmoInlineAssistantStore.shared, proposal: proposal,
                    sourceText: contextSession.document.plainText, bodyFont: DS.body, textColor: DS.text)
                    .frame(maxWidth: readingWidth).padding(DS.space32).frame(maxWidth: .infinity)
            }.background(paper).accessibilityIdentifier("page.ai.review")
        }
    }

    private var contextPanel: some View {
        VStack(spacing: 0) {
            if outlineVisible || contextVisible || showsContextSheet {
                UnifiedPageContextPanel(atom: contextSession.atom, document: contextSession.document,
                    tags: Binding(get: { contextSession.tags }, set: { contextSession.editTags($0) }),
                    showsOutline: outlineVisible || showsContextSheet, showsDetails: contextVisible || showsContextSheet,
                    onNavigateBlock: { navigationBlockID = $0 }, onOpenAtom: openAtom)
            }
            if let spaceID, sourcesVisible {
                Divider().overlay(DS.borderSubtle)
                SpaceWorkspaceSources(spaceID: spaceID, add: addReference, open: { openAtom($0.uuid) })
                    .frame(minHeight: 220)
            }
        }.background(DS.bg)
    }

    private var focusExit: some View {
        Button { toggleFocus() } label: { Label("Exit Focus", systemImage: "arrow.down.right.and.arrow.up.left").font(DS.caption).padding(DS.space12) }
            .buttonStyle(.plain).glassEffect(.regular.interactive(), in: .capsule)
            .help("Exit Focus (Esc)").accessibilityLabel("Exit Focus")
            .padding(DS.space12).opacity(isFocused ? 1 : 0).allowsHitTesting(isFocused).accessibilityHidden(!isFocused)
    }

    private var sharePopover: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            Text("Share page").font(DS.headline)
            if let shareText {
                ShareLink(item: shareText) { Label("Share a copy…", systemImage: "square.and.arrow.up") }
                Button("Copy Markdown") { copy(shareText); self.shareText = nil }
                Button("Copy text") { copy(session.title + "\n\n" + session.document.plainText); self.shareText = nil }
            }
            if spaceID != nil { Button("Preview and export…") { shareText = nil; export() } }
        }.padding(DS.space16)
    }

    private var styleBinding: Binding<NoteDocumentStyle> { Binding(get: { session.style }, set: session.editStyle) }
    private var tagsBinding: Binding<[String]> { Binding(get: { session.tags }, set: session.editTags) }

    private func toggleFocus() {
        viewport.capture()
        showsStyle = false; shareText = nil; showsContextSheet = false
        focus.toggle(pageUUID: atom.uuid, paneID: paneID)
        viewport.restoreAfterLayout()
    }

    private func activate(_ editing: SpacePageEditorSession, assistant selectedAssistant: UnifiedPageAssistant) {
        if contextSession.atom.uuid != editing.atom.uuid {
            activeSectionSession = editing.atom.uuid == session.atom.uuid ? nil : editing
            activeSectionAssistant = editing.atom.uuid == session.atom.uuid ? nil : selectedAssistant
        }
        selectedAssistant.activate(isContextOwner: !isPaneContext || isPaneContextOwner)
        if let spaceID, store.location(spaceID).selectedUUID != editing.atom.uuid {
            store.select(editing.atom.uuid, in: spaceID)
        }
    }

    private func openHistory() {
        commitNativeBuffer()
        Task { @MainActor in
            guard await session.prepareForHistory() else { return }
            showsHistory = true
        }
    }
    private func prepareShare() {
        commitNativeBuffer()
        Task { @MainActor in
            await Task.yield()
            shareText = ([session.title] + BlockOperations.markdownLines(for: session.document.blocks)).joined(separator: "\n\n")
        }
    }
    private func prepareContentIdea() {
        performSavedAction { contentIdea = session.atom }
    }
    private func export() {
        guard let spaceID else { return }
        performSavedAction {
            guard await SpacePageEditorStore.shared.flushAll() else { throw SpaceCompositionError.conflict }
            let snapshot = try await SpaceCompositionService.load(in: spaceID)
            preview = try SpaceCompositionExportSnapshot.capture(from: snapshot, rootUUID: atom.uuid)
        }
    }
    private func performSavedAction(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; commitNativeBuffer()
        Task { @MainActor in
            defer { busy = false }
            await Task.yield()
            guard await session.flush() else { return }
            do { try await action() } catch { operationError = error.localizedDescription }
        }
    }
    private func addReference() {
        guard let spaceID else { return }
        CommandKPickerPresentation.present(spaceID: spaceID, targetUUID: store.sourceTarget(in: spaceID)?.uuid ?? atom.uuid, purpose: .attachReferences)
    }
    private func openAtom(_ uuid: String) {
        Task { @MainActor in
            do { try await CommandKSpaceService.openAtom(uuid, preferredSpaceID: spaceID) }
            catch { operationError = error.localizedDescription }
        }
    }
    private func commitNativeBuffer() { NSApp.keyWindow?.makeFirstResponder(nil) }
    private func copy(_ value: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string) }
    private func landSearch(using proxy: ScrollViewProxy) {
        let block = initialBlockID ?? CommandKSearchLandingStore.shared.consume(for: atom.uuid)
            .flatMap { CommandKSearchLandingLocator.blockID(for: $0, in: session.document.blocks) }
        guard let block else { return }
        navigationBlockID = block
        DispatchQueue.main.async { proxy.scrollTo(block, anchor: .center) }
    }

    fileprivate func appear() {
        session.receive(atom)
        if let spaceID, store.location(spaceID).selectedUUID != atom.uuid {
            store.select(atom.uuid, in: spaceID)
        }
        observation = CanvasAtomObservationHub.shared.subscribe(uuid: atom.uuid, deliverCurrentValue: true) { session.receive($0) }
        if panelIsVisible { assistant.activate(isContextOwner: !isPaneContext || isPaneContextOwner) }
    }
    fileprivate func disappear() {
        focus.end(pageUUID: atom.uuid, paneID: paneID)
        CanvasAtomObservationHub.shared.unsubscribe(observation); observation = nil
        assistant.deactivate()
        Task { await ImageStore.hydrateNoteImages(uuid: atom.uuid) }
    }
    fileprivate func updateAnalysis() async {
        let text = manuscriptText
        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        let count = await Task.detached(priority: .utility) { NoteFocusTextAnalysis.analyze(text).wordCount }.value
        guard !Task.isCancelled else { return }
        wordCount = count
        assistant.refresh()
    }
    fileprivate func escape() -> KeyPress.Result {
        if isFocused { toggleFocus(); return .handled }
        if let onClose { onClose(); return .handled }
        if let spaceID { store.showRoot(.canvas, in: spaceID); return .handled }
        return .ignored
    }

    /// Separating subscriptions keeps the Page's layout body cheap to type-check.
    private struct UnifiedPageLifecycle: ViewModifier {
        let page: UnifiedPageView
        func body(content: Content) -> some View {
            content
                .onAppear(perform: page.appear).onDisappear(perform: page.disappear)
                .onChange(of: page.atom.localVersion) { _, _ in page.session.receive(page.atom) }
                .onChange(of: page.initialBlockID) { _, block in page.navigationBlockID = block }
                .onChange(of: page.panelIsVisible) { _, visible in
                    if visible { page.contextAssistant.activate(isContextOwner: !page.isPaneContext || page.isPaneContextOwner) }
                    else { page.assistant.deactivate(); page.activeSectionAssistant?.deactivate() }
                }
                .onChange(of: page.isPaneContextOwner) { _, owner in
                    if page.panelIsVisible { page.contextAssistant.activate(isContextOwner: owner) }
                }
                .task(id: page.manuscriptText) { await page.updateAnalysis() }
                .onChange(of: page.sections.map(\.atom.uuid)) { _, ids in
                    if let selected = page.activeSectionSession, !ids.contains(selected.atom.uuid) {
                        page.activate(page.session, assistant: page.assistant)
                    }
                }
                .onKeyPress(.escape) { page.escape() }
        }
    }
}

private struct UnifiedPageTitle: View {
    let session: SpacePageEditorSession
    var onActivate: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @State private var height: CGFloat = 40
    var body: some View {
        CosmoDocumentEditor(document: Binding(get: { session.titleDocument }, set: session.editTitle),
            fontSize: SharedTitleSurfaceStyle.connectionFocus.fontSize, fontDesign: session.style.fontFamily.design,
            compact: true, placeholder: "Untitled page", darkMode: colorScheme == .dark, overrideTextColor: NSColor(DS.text),
            allowSlashCommands: false, allowMentions: true, allowSelectionMenu: true, allowImages: false,
            titleConfiguration: TitleEditorConfiguration(previewLineLimit: 2, editingLineLimit: 3),
            baseFontWeight: .semibold, scrollsInternally: false,
            onContentHeightChange: { next in
                let bounded = min(112, max(40, next))
                if abs(height - bounded) > 1 { height = bounded }
            }, onActivate: onActivate)
            .frame(height: height).accessibilityLabel("Page title")
    }
}

struct UnifiedPageToolbarButton: View {
    let symbol: String
    let label: String
    var active = false
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(DS.body)
                .foregroundStyle(active ? DS.accent : DS.textSecondary)
                .frame(width: 44, height: 44)
                .background(hovered || active ? DS.glassInputFill : .clear, in: .rect(cornerRadius: DS.radiusSmall))
                .contentShape(.rect)
        }.buttonStyle(.plain).onHover { hovered = $0 }.help(label).accessibilityLabel(label)
            .scaleEffect(hovered && !reduceMotion ? 1.01 : 1)
            .animation(reduceMotion ? nil : ProMotionSprings.hover, value: hovered)
    }
}

private struct UnifiedPageManuscriptSection: View {
    let atom: Atom
    let spaceID: String?
    let availableWidth: CGFloat
    let typewriterMode: Bool
    let paragraphFocus: Bool
    let showsSaveStatus: Bool
    let onActivate: (SpacePageEditorSession, UnifiedPageAssistant) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.cosmoFloatingPanelIsVisible) private var panelIsVisible
    @State private var session: SpacePageEditorSession
    @State private var assistant: UnifiedPageAssistant
    init(atom: Atom, spaceID: String?, availableWidth: CGFloat, typewriterMode: Bool, paragraphFocus: Bool, showsSaveStatus: Bool,
         onActivate: @escaping (SpacePageEditorSession, UnifiedPageAssistant) -> Void) {
        self.atom = atom; self.spaceID = spaceID; self.availableWidth = availableWidth
        self.typewriterMode = typewriterMode; self.paragraphFocus = paragraphFocus
        self.showsSaveStatus = showsSaveStatus
        self.onActivate = onActivate
        let editing = SpacePageEditorStore.shared.session(for: atom)
        _session = State(initialValue: editing)
        _assistant = State(initialValue: UnifiedPageAssistant(session: editing))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            Divider().overlay(DS.borderSubtle)
            if session.style.cover != .none {
                NotePageCoverBand(style: session.style, darkMode: colorScheme == .dark, height: 88)
                    .clipShape(.rect(cornerRadius: DS.radiusLarge)).padding(.leading, BlockInteractionPolicy.gutterWidth)
            }
            UnifiedPageTitle(session: session, onActivate: { onActivate(session, assistant) })
                .padding(.leading, BlockInteractionPolicy.gutterWidth)
            HStack {
                if atom.spaceComposition?.includeInExport == false { Text("Not in export").font(DS.caption).foregroundStyle(DS.textMuted) }
                Spacer()
                if let spaceID {
                    Button("References", systemImage: "link") {
                        onActivate(session, assistant)
                        if !SpaceWorkspaceStore.shared.location(spaceID).sourcesVisible {
                            SpaceWorkspaceStore.shared.toggleSources(in: spaceID)
                        }
                    }.font(DS.caption).buttonStyle(.plain).help("References for this section")
                    Button("Open page", systemImage: "arrow.up.forward") { SpaceWorkspaceStore.shared.open(atom, in: spaceID) }
                        .font(DS.caption).buttonStyle(.plain).help("Open this section as a Page")
                }
            }.padding(.leading, BlockInteractionPolicy.gutterWidth)
                .frame(height: showsSaveStatus ? nil : 0).clipped()
                .opacity(showsSaveStatus ? 1 : 0).allowsHitTesting(showsSaveStatus).accessibilityHidden(!showsSaveStatus)
            SpacePageEditor(session: session, minimumBodyHeight: 44, typewriterMode: typewriterMode,
                paragraphFocus: paragraphFocus, showsSaveStatus: showsSaveStatus,
                onSelectionChanged: { snapshot in
                    if snapshot.range.location != NSNotFound { onActivate(session, assistant) }
                    assistant.reportSelection(snapshot)
                })
        }
        .frame(width: min(availableWidth, session.style.pageWidth.readingWidth(for: session.style.textSize) + BlockInteractionPolicy.gutterWidth))
        .background(session.style.paperTone.pageColor(darkMode: colorScheme == .dark) ?? .clear)
        .onChange(of: atom.localVersion) { _, _ in session.receive(atom) }
        .onAppear { if panelIsVisible { assistant.activate(isContextOwner: false) } }
        .onDisappear { assistant.deactivate() }
        .onChange(of: panelIsVisible) { _, visible in
            if visible { assistant.activate(isContextOwner: false) } else { assistant.deactivate() }
        }
    }
}

@MainActor
private final class UnifiedPageViewport {
    private let keeper = CosmoInlineReviewScrollPositionKeeper()
    func attach(_ scrollView: NSScrollView) { keeper.attach(to: scrollView) }
    func capture() { keeper.captureBeforeSwap() }
    func restoreAfterLayout() { keeper.restoreAfterSwap() }
}
